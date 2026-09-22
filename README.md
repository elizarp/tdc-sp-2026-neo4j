# 1 Grafo, N Casos de Uso

Workshop do TDC São Paulo 2026 (23/09, 17:00–18:30): como uma única base em grafo Neo4j resolve
seis casos de uso de negócio diferentes — detecção de fraude, recomendação de produtos, visão 360
do cliente, jornada, churn, segmentação comportamental e resolução de identidade — trocando só o
algoritmo de Graph Data Science que "olha" para o grafo, sem remodelar nada entre um caso e outro.

Base fictícia de uma fintech ("FinTechConecta"), ~195 mil nós, calibrada para caber no teto do
AuraDB Free. Tudo neste repositório foi testado de ponta a ponta contra uma instância AuraDB Free
real, com o banco limpo e recarregado do zero.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| [`data/`](data) | Gerador dos CSVs fake (`generate_dados.py`) + os CSVs em si, prontos pra `LOAD CSV` |
| [`cypher/`](cypher) | Constraints + carga (`LOAD CSV`) + construção da jornada do cliente |
| [`gds/`](gds) | Scripts de Graph Data Science (via Aura Graph Analytics) para os 6 casos de uso |
| [`aura-agent/`](aura-agent) | Config do Aura Agent único que responde perguntas sobre os 6 casos de uso |

O modelo de dados, o plano do workshop e os slides ficam num diretório `docs/` local, fora deste
repositório público.

## Passo a passo pra rodar

### 1. Criar sua conta e a instância AuraDB Free

1. Acesse [console.neo4j.io](https://console.neo4j.io) e crie uma conta gratuita (ou faça login,
   se já tiver uma) — não pede cartão de crédito.
2. No painel do Console, clique em **"New instance"** (às vezes aparece como **"+ Create
   instance"**).
3. Escolha o plano **AuraDB Free**.
4. Dê um nome pra instância (ex.: `tdc-workshop`) e escolha uma região — qualquer uma serve; se
   você estiver no Brasil, uma região da América do Sul costuma dar menor latência.
5. Clique em **criar** — a instância leva 1-2 minutos pra ficar pronta (status muda de
   "Creating" pra "Running").
6. **A tela de credenciais (usuário, senha, URI de conexão) só aparece uma única vez.** Clique em
   **"Download and continue"** (baixa um `.txt`) antes de sair dessa tela — se você fechar sem
   baixar/copiar, não tem como recuperar a senha depois; a única saída é resetar a senha da
   instância.

> [!WARNING]
> **O AuraDB Free permite só 1 instância gratuita por conta.** Se sua conta já tem uma instância
> Free (de outro teste, curso ou projeto), você tem duas opções antes do workshop: (a) pausar ou
> apagar essa instância existente, ou (b) criar uma conta nova (outro e-mail) só pra este
> workshop. Tentar criar uma segunda instância Free na mesma conta não funciona.

7. Guarde à mão o **usuário**, a **senha** e a **URI** de conexão. Em instâncias Free mais novas,
   o usuário e o nome do banco costumam ser iguais ao ID da instância (ex.: `b49e0444`/`b49e0444`),
   não o clássico `neo4j`/`neo4j` — confira exatamente o que a tela de credenciais mostrou pra
   você, não assuma o padrão antigo.

### 2. Abrir o editor de Cypher (Aura Query)

1. Na lista de instâncias do Console, clique na sua instância e depois em **"Query"** (às vezes
   **"Open"** → aba **Query**) — isso abre o editor de Cypher já conectado, direto no navegador,
   sem precisar instalar nada.
2. Alternativa: clique em **"Connect"** e abra pelo **Neo4j Browser**, colando a URI/usuário/senha
   manualmente.
3. Teste a conexão rodando:
   ```cypher
   RETURN 1 AS ok;
   ```
   Se voltar `ok: 1`, está tudo certo pra seguir.

### 3. Rodar os Cyphers, na ordem — cada um aberto do GitHub

Gerar os CSVs de novo **não é necessário** — eles já vêm prontos no repositório, e os `LOAD CSV`
abaixo já apontam direto pro raw do GitHub. Cada arquivo da tabela abaixo precisa ser **aberto no
link do GitHub, copiado (Cmd/Ctrl+A, Cmd/Ctrl+C, ou o ícone de copiar do bloco de código) e colado
no editor Query do Aura** — nessa ordem exata, porque cada bloco depende do anterior:

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | [`cypher/01_constraints.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/cypher/01_constraints.cypher) | Cria as constraints de unicidade + índices auxiliares |
| 2 | [`cypher/02_carga.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/cypher/02_carga.cypher) | `LOAD CSV` de todos os dados (10 blocos, ~90s) — direto do raw do GitHub |
| 3 | [`cypher/03_jornada.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/cypher/03_jornada.cypher) | Encadeia `Acesso`/`Transacao`/`Chamado` em `PROXIMO_EVENTO` |
| 4 | [`gds/04_gds_fraude.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/gds/04_gds_fraude.cypher) | WCC + PageRank — detecção de fraude |
| 5 | [`gds/05_gds_recomendacao.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/gds/05_gds_recomendacao.cypher) | Node Similarity + FastRP/KNN — recomendação |
| 6 | [`gds/06_gds_jornada.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/gds/06_gds_jornada.cypher) | BFS sobre a jornada — sequência de account takeover |
| 7 (bônus) | [`gds/07_segmentacao_comportamental.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/gds/07_segmentacao_comportamental.cypher) | Louvain + Node Similarity ponderada |
| 8 (bônus) | [`gds/08_resolucao_identidade.cypher`](https://github.com/elizarp/tdc-sp-2026-neo4j/blob/main/gds/08_resolucao_identidade.cypher) | Blocking + similaridade fuzzy |

Pra cada linha da tabela, nessa ordem:
1. Clique no link — abre o arquivo `.cypher` no GitHub.
2. Copie o conteúdo inteiro do arquivo.
3. Cole no editor de Cypher do Aura Query.
4. Rode (botão **"Run"**, ou Ctrl/Cmd+Enter).
5. Espere terminar antes de colar o próximo — os blocos 1-3 e o 4-8 (GDS) dependem do que veio
   antes. A carga (bloco 2) é a etapa mais longa, ~90 segundos; o resto costuma levar poucos
   segundos cada.

Detalhes de cada bloco, tempos reais medidos e o que esperar de resultado ficam nos `README.md` de
[`cypher/`](cypher) e [`gds/`](gds).

### 4. Verificar que funcionou

```cypher
MATCH (n) RETURN count(n) AS total;
```
Esperado: **195.000** nós (pode variar 1-2% se os dados forem regenerados). Se o número estiver
muito diferente, rode o bloco de carga de novo — tudo é idempotente (`MERGE`), não duplica.

### 5. (Opcional) Regenerar os CSVs

Só necessário se você alterar `data/generate_dados.py`. Os CSVs já vêm gerados no repositório:

```bash
cd data && python3 generate_dados.py
```

## O que não está neste repositório (de propósito)

`data/gabarito.json` — a verdade injetada nos dados fake (quais clientes formam cada anel de
fraude, quais são as contas-laranja, qual registro bruto resolve pra qual cliente) fica só na
máquina de quem gera os dados, nunca commitada. É a resposta do exercício — publicar isso junto
com os CSVs tiraria a graça de descobrir ao vivo. Ver [data/README.md](data/README.md).

## Autor

Eliézer Zarpelão — Sr. Solutions Engineer LATAM, Neo4j
[linkedin.com/in/eliezerzarpelao](https://linkedin.com/in/eliezerzarpelao) ·
eliezer.zarpelao@neo4j.com
