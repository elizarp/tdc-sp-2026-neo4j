#!/usr/bin/env python3
"""Fase 2 — gera os CSVs fake do workshop (sem dependências externas).

Roda com: python3 generate_dados.py

Gera, na mesma pasta:
  clientes.csv, rgs.csv, emails.csv, telefones.csv, dispositivos.csv,
  localizacoes.csv, transacoes.csv, tipos_produto.csv, produtos.csv,
  contratacoes.csv, chamados.csv, acessos.csv, acoes_app.csv,
  registros_brutos.csv
e o gabarito (data/gabarito.json) com a verdade injetada — anéis de fraude,
contas-laranja, perfis de contratação, personas comportamentais e o mapa de
resolução dos registros brutos — que NÃO deve ser carregado no grafo. Serve só
para o palestrante validar os resultados de GDS durante o ensaio.

Dimensionamento: calcula o overhead fixo (Cliente + identidades já deduplicadas
pelos anéis de fraude + Localizacao + Produto/TipoProduto + Registros Brutos) e
distribui o orçamento restante entre Acesso/AcaoApp/Transacao/Chamado por
proporção fixa, mirando TARGET_TOTAL_NODES sem nunca estourar o teto de 200 mil
nós do AuraDB Free (ver docs/00-modelo-dados.md, seção "Orçamento de nós").

Determinístico (seed fixa) para reprodutibilidade entre execuções.
"""
import csv
import json
import os
import random
from datetime import date, datetime, timedelta

random.seed(42)

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
REF_DATE = date(2026, 3, 1)
JANELA_EVENTOS_DIAS = 180  # acessos/transações/chamados distribuídos nesta janela

N_CLIENTES = 1500
TARGET_TOTAL_NODES = 195_000

FRAUD_RING_COUNT = 18
FRAUD_RING_SIZE_RANGE = (3, 6)
FRAUD_POOL_SIZE = 150
N_ORANGE_ACCOUNTS = 6

N_REGISTROS_BRUTOS_DUPLICADOS = 90
N_REGISTROS_BRUTOS_NEGATIVOS = 25

# Proporção do orçamento de eventos por categoria (o resto vai para AcaoApp).
PCT_ACESSO = 0.28
PCT_TRANSACAO = 0.13
PCT_CHAMADO = 0.02

FIRST_NAMES = [
    "Ana", "Bruno", "Carla", "Daniel", "Eduarda", "Felipe", "Gabriela", "Henrique",
    "Isabela", "João", "Karina", "Lucas", "Mariana", "Nicolas", "Otávio", "Patrícia",
    "Rafael", "Sabrina", "Thiago", "Vanessa", "Aline", "Bruna", "Caio", "Débora",
    "Enzo", "Fernanda", "Guilherme", "Helena", "Igor", "Juliana",
]
LAST_NAMES = [
    "Silva", "Santos", "Oliveira", "Souza", "Rodrigues", "Ferreira", "Almeida",
    "Pereira", "Lima", "Gomes", "Costa", "Ribeiro", "Martins", "Carvalho", "Araujo",
    "Melo", "Barbosa", "Rocha", "Dias", "Nascimento",
]

CIDADES = [
    ("São Paulo", "SP", -23.5505, -46.6333),
    ("Rio de Janeiro", "RJ", -22.9068, -43.1729),
    ("Belo Horizonte", "MG", -19.9167, -43.9345),
    ("Curitiba", "PR", -25.4284, -49.2733),
    ("Porto Alegre", "RS", -30.0346, -51.2177),
    ("Salvador", "BA", -12.9777, -38.5016),
    ("Recife", "PE", -8.0476, -34.8770),
    ("Fortaleza", "CE", -3.7172, -38.5433),
    ("Brasília", "DF", -15.7939, -47.8828),
    ("Campinas", "SP", -22.9099, -47.0626),
]

SEGMENTOS = ["Varejo", "Premium", "Private", "Universitário"]

DEVICE_MODELS = [
    ("iPhone 14", "iOS 17"), ("iPhone 15", "iOS 18"), ("Galaxy S23", "Android 14"),
    ("Galaxy A54", "Android 13"), ("Moto G84", "Android 14"), ("Redmi Note 12", "Android 13"),
    ("Pixel 8", "Android 14"),
]

EMAIL_DOMAINS = ["gmail.com", "hotmail.com", "outlook.com", "yahoo.com.br", "uol.com.br"]

TIPOS_PRODUTO = [
    ("TP01", "Cartão", False),
    ("TP02", "Crédito", True),
    ("TP03", "Seguro", True),
    ("TP04", "Investimento", False),
    ("TP05", "Consórcio", True),
]

PRODUTOS = [
    ("PR01", "Cartão Gold", "TP01"),
    ("PR02", "Cartão Platinum", "TP01"),
    ("PR03", "Empréstimo Pessoal", "TP02"),
    ("PR04", "Financiamento Veicular", "TP02"),
    ("PR05", "Seguro de Vida", "TP03"),
    ("PR06", "Seguro Viagem", "TP03"),
    ("PR07", "Seguro Residencial", "TP03"),
    ("PR08", "CDB Rende Mais", "TP04"),
    ("PR09", "Fundo Multimercado", "TP04"),
    ("PR10", "Consórcio Imóvel", "TP05"),
]

# Perfis de CONTRATAÇÃO: dão sinal real para Node Similarity / FastRP+KNN de
# recomendação (o que o cliente compra).
PERFIS = {
    "viajante_premium": ["PR02", "PR06", "PR08"],
    "comprador_imovel": ["PR10", "PR07", "PR03"],
    "investidor_conservador": ["PR08", "PR09", "PR01"],
    "alto_risco_credito": ["PR03", "PR04", "PR02"],
    "basico": ["PR01", "PR05"],
}
PERFIL_NOMES = list(PERFIS.keys())

# Personas COMPORTAMENTAIS: dão sinal real para Louvain/Node Similarity de
# segmentação (como o cliente usa os canais — diferente de o que ele compra).
PERSONAS_COMPORTAMENTAIS = {
    "digital_nativo": {
        "canal_acesso": {"App": 95, "WebApp": 5},
        "canal_chamado": {"App": 55, "Chat": 35, "Telefone": 5, "E-mail": 5, "Agência": 0},
        "tipos_pref": ["ConsultarSaldo", "ConsultarExtrato", "PagarPix", "VisualizarProduto"],
    },
    "tradicional": {
        "canal_acesso": {"App": 35, "WebApp": 65},
        "canal_chamado": {"App": 5, "Chat": 5, "Telefone": 45, "E-mail": 10, "Agência": 35},
        "tipos_pref": ["ConsultarSaldo", "ConsultarExtrato"],
    },
    "investidor_pesquisador": {
        "canal_acesso": {"App": 80, "WebApp": 20},
        "canal_chamado": {"App": 35, "Chat": 30, "Telefone": 10, "E-mail": 20, "Agência": 5},
        "tipos_pref": ["VisualizarProduto", "SimularEmprestimo", "IniciarContratacao", "ConsultarExtrato"],
    },
    "operacional_puro": {
        "canal_acesso": {"App": 90, "WebApp": 10},
        "canal_chamado": {"App": 45, "Chat": 20, "Telefone": 15, "E-mail": 10, "Agência": 10},
        "tipos_pref": ["PagarPix", "ConsultarSaldo"],
    },
}
PERSONA_NOMES = list(PERSONAS_COMPORTAMENTAIS.keys())

ASSUNTOS_CHAMADO = [
    "Dúvida sobre fatura", "Contestação de transação", "Problema no aplicativo",
    "Solicitação de cancelamento", "Elogio ao atendimento", "Reclamação de atendimento",
    "Dúvida sobre produto", "Alteração cadastral",
]
SEVERIDADES = ["Baixa", "Média", "Alta"]
SEVERIDADES_PESOS = [60, 30, 10]

TIPOS_ACAO = [
    "ConsultarSaldo", "ConsultarExtrato", "VisualizarProduto", "SimularEmprestimo",
    "IniciarContratacao", "PagarPix", "AlterarDadosCadastrais", "AbrirChamado",
]
TIPOS_ACAO_COM_PRODUTO = {"VisualizarProduto", "SimularEmprestimo", "IniciarContratacao"}

CANAIS_ORIGEM_BRUTO = ["Agência Legada", "Sistema Legado A", "Sistema Legado B", "Migração 2019", "App"]


def rand_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, max(delta, 0)))


def rand_datetime(start: date, end: date) -> datetime:
    d = rand_date(start, end)
    return datetime(d.year, d.month, d.day, random.randint(0, 23), random.randint(0, 59), random.randint(0, 59))


def weighted_choice(dist: dict) -> str:
    return random.choices(list(dist.keys()), weights=list(dist.values()))[0]


def nome_completo() -> str:
    return f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"


def cpf_fake(idx: int) -> str:
    # Não é um CPF válido de verdade (sem dígito verificador) — só um identificador plausível.
    return f"{idx:03d}.{random.randint(100,999)}.{random.randint(100,999)}-{random.randint(10,99)}"


def ruido_nome(nome: str) -> str:
    """Simula como o mesmo nome apareceria em sistemas diferentes (fase 4 — resolução de identidade)."""
    tipo = random.choice(["igual", "abrevia", "typo", "caixa"])
    if tipo == "abrevia":
        partes = nome.split(" ")
        if len(partes) > 1:
            return f"{partes[0]} {partes[1][0]}."
    elif tipo == "typo" and len(nome) > 4:
        i = random.randint(1, len(nome) - 2)
        letras = list(nome)
        letras[i], letras[i + 1] = letras[i + 1], letras[i]
        return "".join(letras)
    elif tipo == "caixa":
        return nome.upper()
    return nome


def ruido_cpf(cpf: str) -> str:
    tipo = random.choice(["igual", "mascarado", "sem_pontuacao"])
    if tipo == "mascarado":
        partes = cpf.split(".")
        if len(partes) > 1:
            return f"***.{partes[1]}.***-**"
    elif tipo == "sem_pontuacao":
        return cpf.replace(".", "").replace("-", "")
    return cpf


def ruido_telefone(numero: str, ddd: str) -> str:
    tipo = random.choice(["com_ddd", "sem_ddd", "typo_digito"])
    if tipo == "com_ddd":
        return f"({ddd}) {numero}"
    if tipo == "typo_digito":
        letras = list(numero)
        candidatos = [i for i, ch in enumerate(letras) if ch.isdigit()]
        if candidatos:
            i = random.choice(candidatos)
            letras[i] = str(random.randint(0, 9))
        return "".join(letras)
    return numero


def write_csv(filename, fieldnames, rows):
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fieldnames})
    print(f"  {filename}: {len(rows)} linhas")


def main():
    clientes = []
    for i in range(1, N_CLIENTES + 1):
        cliente_id = f"CLI{i:04d}"
        cidade, estado, lat, lon = random.choice(CIDADES)
        perfil = random.choice(PERFIL_NOMES) if random.random() < 0.75 else ""
        persona = random.choice(PERSONA_NOMES)
        clientes.append({
            "cliente_id": cliente_id,
            "nome": nome_completo(),
            "cpf": cpf_fake(i),
            "dataNascimento": rand_date(date(1960, 1, 1), date(2005, 12, 31)).isoformat(),
            "cidade": cidade,
            "estado": estado,
            "segmento": random.choice(SEGMENTOS),
            "dataCadastro": rand_date(date(2018, 1, 1), date(2025, 12, 31)).isoformat(),
            "_lat": lat,
            "_lon": lon,
            "_perfil": perfil,
            "_persona": persona,
            # peso de atividade: a maioria "normal" perto de 1.0, alguns power users, alguns quase inativos
            "_peso": max(0.15, random.gauss(1.0, 0.6)),
        })
    todos_ids = [c["cliente_id"] for c in clientes]
    clientes_by_id = {c["cliente_id"]: c for c in clientes}
    persona_by_cliente = {c["cliente_id"]: c["_persona"] for c in clientes}
    pesos = {c["cliente_id"]: c["_peso"] for c in clientes}
    peso_lista = [pesos[i] for i in todos_ids]

    def sample_clientes(k):
        return random.choices(todos_ids, weights=peso_lista, k=k)

    # --- Identidades individuais (uma por cliente, por padrão) -----------------
    rgs = {}
    emails = {}
    telefones = {}
    dispositivos = {}
    for c in clientes:
        i = c["cliente_id"]
        rgs[i] = {"rg_id": f"RG{i[3:]}", "numero": f"{random.randint(10000000,99999999)}"}
        nome_slug = c["nome"].lower().replace(" ", ".")
        endereco = f"{nome_slug}{random.randint(1,999)}@{random.choice(EMAIL_DOMAINS)}"
        emails[i] = {"email_id": f"EM{i[3:]}", "endereco": endereco, "dominio": endereco.split("@")[1]}
        telefones[i] = {
            "telefone_id": f"TEL{i[3:]}",
            "numero": f"9{random.randint(1000,9999)}-{random.randint(1000,9999)}",
            "ddd": str(random.choice([11, 21, 31, 41, 51, 61, 71, 81, 85])),
        }
        modelo, so = random.choice(DEVICE_MODELS)
        dispositivos[i] = {
            "device_id": f"DEV{i[3:]}",
            "modelo": modelo,
            "sistemaOperacional": so,
            "primeiroAcesso": rand_date(date(2022, 1, 1), date(2024, 12, 31)).isoformat(),
            "ultimoAcesso": rand_date(date(2025, 1, 1), REF_DATE).isoformat(),
        }

    # --- Anéis de fraude: sobrescreve identidades compartilhadas ----------------
    fraud_pool = [c["cliente_id"] for c in clientes[:FRAUD_POOL_SIZE]]
    random.shuffle(fraud_pool)
    aneis = []
    pos = 0
    for ring_idx in range(1, FRAUD_RING_COUNT + 1):
        size = random.randint(*FRAUD_RING_SIZE_RANGE)
        if pos + size > len(fraud_pool):
            break
        membros = fraud_pool[pos:pos + size]
        pos += size
        tipo_ring = random.choice(["identidade", "dispositivo"])
        if tipo_ring == "identidade":
            atributos = random.sample(["rg", "email", "telefone"], k=random.choice([1, 2]))
            shared_rg = rgs[membros[0]]["rg_id"] if "rg" in atributos else None
            shared_rg_numero = rgs[membros[0]]["numero"] if "rg" in atributos else None
            shared_email = emails[membros[0]] if "email" in atributos else None
            shared_tel = telefones[membros[0]] if "telefone" in atributos else None
            for m in membros[1:]:
                if "rg" in atributos:
                    rgs[m] = {"rg_id": shared_rg, "numero": shared_rg_numero}
                if "email" in atributos:
                    emails[m] = dict(shared_email)
                if "telefone" in atributos:
                    telefones[m] = dict(shared_tel)
        else:
            atributos = ["dispositivo"]
            shared_dev = dispositivos[membros[0]]
            for m in membros[1:]:
                dispositivos[m] = dict(shared_dev)
        aneis.append({
            "ring_id": f"RING{ring_idx:02d}",
            "tipo": tipo_ring,
            "atributos_compartilhados": atributos,
            "clientes": membros,
        })

    # --- Contas-laranja ---------------------------------------------------------
    resto_pool = [c["cliente_id"] for c in clientes[FRAUD_POOL_SIZE:]]
    orange_accounts = random.sample(resto_pool, N_ORANGE_ACCOUNTS)

    # --- Localizações (dedupe por cidade) ----------------------------------------
    localizacoes = [{
        "cliente_id": c["cliente_id"],
        "location_id": "LOC_" + c["cidade"].upper().replace(" ", "_"),
        "cidade": c["cidade"],
        "estado": c["estado"],
        "latitude": c["_lat"],
        "longitude": c["_lon"],
    } for c in clientes]

    # --- Registros brutos (fase 4 — resolução de identidade) --------------------
    # Metade "duplicados" de clientes reais com ruído de captura (nomes
    # abreviados/com typo, CPF mascarado, telefone sem DDD...), metade
    # "negativos" (pessoas diferentes de propósito, pra não deixar o algoritmo
    # combinar tudo com tudo). O mapa registro->cliente real fica só no
    # gabarito — o algoritmo tem que resolver sem ver essa resposta.
    registros_brutos = []
    resolucao_gabarito = {}
    reg_idx = 0

    pool_duplicados = random.sample(todos_ids, N_REGISTROS_BRUTOS_DUPLICADOS)
    for cliente_id in pool_duplicados:
        reg_idx += 1
        registro_id = f"REG{reg_idx:04d}"
        c = clientes_by_id[cliente_id]
        tel = telefones[cliente_id]
        data_nasc = date.fromisoformat(c["dataNascimento"])
        if random.random() < 0.12:
            try:
                data_nasc = data_nasc.replace(day=min(data_nasc.month, 28), month=min(data_nasc.day, 12))
            except ValueError:
                pass
        registros_brutos.append({
            "registro_id": registro_id,
            "nomeBruto": ruido_nome(c["nome"]),
            "cpfBruto": ruido_cpf(c["cpf"]),
            "telefoneBruto": ruido_telefone(tel["numero"], tel["ddd"]),
            "dataNascimentoBruto": data_nasc.isoformat(),
            "cidadeBruto": c["cidade"] if random.random() < 0.85 else c["estado"],
            "canalOrigem": random.choice(CANAIS_ORIGEM_BRUTO),
        })
        resolucao_gabarito[registro_id] = cliente_id

    for _ in range(N_REGISTROS_BRUTOS_NEGATIVOS):
        reg_idx += 1
        registro_id = f"REG{reg_idx:04d}"
        cidade, estado, _, _ = random.choice(CIDADES)
        registros_brutos.append({
            "registro_id": registro_id,
            "nomeBruto": nome_completo(),
            "cpfBruto": cpf_fake(9000 + reg_idx),
            "telefoneBruto": f"9{random.randint(1000,9999)}-{random.randint(1000,9999)}",
            "dataNascimentoBruto": rand_date(date(1960, 1, 1), date(2005, 12, 31)).isoformat(),
            "cidadeBruto": cidade,
            "canalOrigem": random.choice(CANAIS_ORIGEM_BRUTO),
        })
        resolucao_gabarito[registro_id] = None

    # --- Orçamento de nós: overhead fixo primeiro, resto pros eventos -----------
    n_rg = len({v["rg_id"] for v in rgs.values()})
    n_email = len({v["email_id"] for v in emails.values()})
    n_tel = len({v["telefone_id"] for v in telefones.values()})
    n_dev = len({v["device_id"] for v in dispositivos.values()})
    n_loc = len({r["location_id"] for r in localizacoes})
    base_overhead = (N_CLIENTES + n_rg + n_email + n_tel + n_dev + n_loc
                      + len(TIPOS_PRODUTO) + len(PRODUTOS) + len(registros_brutos))
    events_budget = max(TARGET_TOTAL_NODES - base_overhead, 0)

    n_acesso = round(events_budget * PCT_ACESSO)
    n_transacao = round(events_budget * PCT_TRANSACAO)
    n_chamado = round(events_budget * PCT_CHAMADO)
    n_acao = events_budget - n_acesso - n_transacao - n_chamado  # absorve o arredondamento

    print(f"Overhead fixo (Cliente+identidades+Localizacao+Produto/Tipo+RegistroBruto): {base_overhead}")
    print(f"Orçamento de eventos: {events_budget} "
          f"(Acesso={n_acesso}, AcaoApp={n_acao}, Transacao={n_transacao}, Chamado={n_chamado})")
    print(f"Total estimado de nós: {base_overhead + events_budget} (alvo: {TARGET_TOTAL_NODES})")

    janela_ini = REF_DATE - timedelta(days=JANELA_EVENTOS_DIAS)

    # --- Transações Pix -----------------------------------------------------------
    transacoes = []
    origem_por_cliente = {i: [] for i in todos_ids}
    origens = sample_clientes(n_transacao)
    for t, origem in enumerate(origens, start=1):
        if random.random() < 0.20:
            destino = random.choice([o for o in orange_accounts if o != origem])
            valor = round(random.uniform(1500, 15000), 2)
        else:
            destino = random.choice([o for o in todos_ids if o != origem])
            valor = round(random.uniform(15, 3000), 2)
        transacao_id = f"TX{t:07d}"
        transacoes.append({
            "transacao_id": transacao_id,
            "clienteOrigemId": origem,
            "clienteDestinoId": destino,
            "valor": valor,
            "data": rand_date(janela_ini, REF_DATE).isoformat(),
            "tipo": "Pix",
        })
        origem_por_cliente[origem].append(transacao_id)

    # --- Acessos (login/sessão no app) — canal vem da persona comportamental -----
    acessos = []
    acessos_por_cliente = {i: [] for i in todos_ids}
    clientes_acesso = sample_clientes(n_acesso)
    for a, cliente_id in enumerate(clientes_acesso, start=1):
        persona = PERSONAS_COMPORTAMENTAIS[persona_by_cliente[cliente_id]]
        sucesso = random.random() > 0.05
        dt = rand_datetime(janela_ini, REF_DATE)
        acesso_id = f"AC{a:07d}"
        acessos.append({
            "acesso_id": acesso_id,
            "cliente_id": cliente_id,
            "dataHora": dt.isoformat(),
            "canal": weighted_choice(persona["canal_acesso"]),
            "sucesso": sucesso,
            "duracaoSegundos": random.randint(20, 900) if sucesso else 0,
        })
        acessos_por_cliente[cliente_id].append((acesso_id, dt))

    # --- Ações dentro das sessões — tipo tende ao perfil comportamental -----------
    acoes = []
    acessos_com_sucesso = [a for a in acessos if a["sucesso"]]
    if acessos_com_sucesso:
        alvo_acessos = random.choices(acessos_com_sucesso, k=n_acao)
        for idx, acesso in enumerate(alvo_acessos, start=1):
            persona = PERSONAS_COMPORTAMENTAIS[persona_by_cliente[acesso["cliente_id"]]]
            tipo = random.choice(persona["tipos_pref"]) if random.random() < 0.65 else random.choice(TIPOS_ACAO)
            base_dt = datetime.fromisoformat(acesso["dataHora"])
            offset = random.randint(0, max(acesso["duracaoSegundos"], 10))
            acoes.append({
                "acao_id": f"ACAO{idx:08d}",
                "acesso_id": acesso["acesso_id"],
                "tipo": tipo,
                "dataHora": (base_dt + timedelta(seconds=offset)).isoformat(),
                "produto_id": random.choice(PRODUTOS)[0] if tipo in TIPOS_ACAO_COM_PRODUTO else "",
            })

    # --- Chamados (multicanal) — canal vem da persona comportamental -------------
    chamados = []
    clientes_chamado = sample_clientes(n_chamado)
    for idx, cliente_id in enumerate(clientes_chamado, start=1):
        persona = PERSONAS_COMPORTAMENTAIS[persona_by_cliente[cliente_id]]
        assunto = random.choice(ASSUNTOS_CHAMADO)
        aberto_dt = rand_datetime(janela_ini, REF_DATE)
        status = random.choices(["Resolvido", "Em Andamento", "Aberto", "Cancelado"], weights=[70, 15, 10, 5])[0]
        resolvido_em = ""
        tempo_resolucao = ""
        satisfacao = ""
        if status == "Resolvido":
            horas = random.randint(1, 96)
            resolvido_em = (aberto_dt + timedelta(hours=horas)).isoformat()
            tempo_resolucao = horas
            satisfacao = random.randint(1, 5)
        transacao_disputada = ""
        if assunto == "Contestação de transação" and origem_por_cliente.get(cliente_id):
            transacao_disputada = random.choice(origem_por_cliente[cliente_id])
        chamados.append({
            "chamado_id": f"CH{idx:07d}",
            "cliente_id": cliente_id,
            "canal": weighted_choice(persona["canal_chamado"]),
            "assunto": assunto,
            "severidade": random.choices(SEVERIDADES, weights=SEVERIDADES_PESOS)[0],
            "status": status,
            "abertoEm": aberto_dt.isoformat(),
            "resolvidoEm": resolvido_em,
            "tempoResolucaoHoras": tempo_resolucao,
            "satisfacao": satisfacao,
            "transacaoDisputadaId": transacao_disputada,
        })

    # --- Contratações de produto (com viés de perfil) ----------------------------
    contratacoes = []
    for c in clientes:
        n_produtos = random.choice([1, 2, 2, 3, 3, 4])
        perfil = c["_perfil"]
        escolhidos = set()
        for _ in range(n_produtos):
            candidatos = PERFIS[perfil] if (perfil and random.random() < 0.7) else [p[0] for p in PRODUTOS]
            escolhidos.add(random.choice(candidatos))
        for produto_id in escolhidos:
            vezes = random.randint(1, 12)
            contratacoes.append({
                "cliente_id": c["cliente_id"],
                "produto_id": produto_id,
                "vezes": vezes,
                "valorTotal": round(vezes * random.uniform(80, 900), 2),
                "ultimoUso": rand_date(date(2025, 1, 1), REF_DATE).isoformat(),
            })

    # --- Escreve CSVs -------------------------------------------------------------
    print("Gerando CSVs em", OUT_DIR)

    write_csv("clientes.csv",
               ["cliente_id", "nome", "cpf", "dataNascimento", "cidade", "estado", "segmento", "dataCadastro"],
               clientes)

    write_csv("localizacoes.csv",
               ["cliente_id", "location_id", "cidade", "estado", "latitude", "longitude"],
               localizacoes)

    write_csv("rgs.csv",
               ["cliente_id", "rg_id", "numero", "desde"],
               [{"cliente_id": cid, **v, "desde": rand_date(date(2018, 1, 1), date(2025, 12, 31)).isoformat()}
                for cid, v in rgs.items()])

    write_csv("emails.csv",
               ["cliente_id", "email_id", "endereco", "dominio", "desde"],
               [{"cliente_id": cid, **v, "desde": rand_date(date(2018, 1, 1), date(2025, 12, 31)).isoformat()}
                for cid, v in emails.items()])

    write_csv("telefones.csv",
               ["cliente_id", "telefone_id", "numero", "ddd", "desde"],
               [{"cliente_id": cid, **v, "desde": rand_date(date(2018, 1, 1), date(2025, 12, 31)).isoformat()}
                for cid, v in telefones.items()])

    write_csv("dispositivos.csv",
               ["cliente_id", "device_id", "modelo", "sistemaOperacional", "primeiroAcesso", "ultimoAcesso"],
               [{"cliente_id": cid, **v} for cid, v in dispositivos.items()])

    write_csv("transacoes.csv",
               ["transacao_id", "clienteOrigemId", "clienteDestinoId", "valor", "data", "tipo"],
               transacoes)

    write_csv("tipos_produto.csv",
               ["tipo_id", "nome", "ehContrato"],
               [{"tipo_id": t, "nome": n, "ehContrato": eh} for t, n, eh in TIPOS_PRODUTO])

    tipo_nome_by_id = {t: n for t, n, _ in TIPOS_PRODUTO}
    write_csv("produtos.csv",
               ["produto_id", "nome", "categoria", "tipo_id"],
               [{"produto_id": pid, "nome": nome, "categoria": tipo_nome_by_id[tid], "tipo_id": tid}
                for pid, nome, tid in PRODUTOS])

    write_csv("contratacoes.csv",
               ["cliente_id", "produto_id", "vezes", "valorTotal", "ultimoUso"],
               contratacoes)

    write_csv("acessos.csv",
               ["acesso_id", "cliente_id", "dataHora", "canal", "sucesso", "duracaoSegundos"],
               acessos)

    write_csv("acoes_app.csv",
               ["acao_id", "acesso_id", "tipo", "dataHora", "produto_id"],
               acoes)

    write_csv("chamados.csv",
               ["chamado_id", "cliente_id", "canal", "assunto", "severidade", "status",
                "abertoEm", "resolvidoEm", "tempoResolucaoHoras", "satisfacao", "transacaoDisputadaId"],
               chamados)

    write_csv("registros_brutos.csv",
               ["registro_id", "nomeBruto", "cpfBruto", "telefoneBruto", "dataNascimentoBruto",
                "cidadeBruto", "canalOrigem"],
               registros_brutos)

    # --- Gabarito (não carregar no grafo) -----------------------------------------
    gabarito = {
        "aneis_de_fraude": aneis,
        "contas_laranja": orange_accounts,
        "perfis_por_cliente": {c["cliente_id"]: c["_perfil"] for c in clientes if c["_perfil"]},
        "personas_por_cliente": {c["cliente_id"]: c["_persona"] for c in clientes},
        "resolucao_registros_brutos": resolucao_gabarito,
    }
    with open(os.path.join(OUT_DIR, "gabarito.json"), "w", encoding="utf-8") as f:
        json.dump(gabarito, f, ensure_ascii=False, indent=2)
    print(f"  gabarito.json: {len(aneis)} anéis, {len(orange_accounts)} contas-laranja, "
          f"{len(registros_brutos)} registros brutos ({N_REGISTROS_BRUTOS_DUPLICADOS} duplicados, "
          f"{N_REGISTROS_BRUTOS_NEGATIVOS} negativos)")

    total_real = (N_CLIENTES + n_rg + n_email + n_tel + n_dev + n_loc + len(TIPOS_PRODUTO)
                  + len(PRODUTOS) + len(transacoes) + len(acessos) + len(acoes) + len(chamados)
                  + len(registros_brutos))
    print(f"\nTotal real de nós (após dedupe de identidades): {total_real}")


if __name__ == "__main__":
    main()
