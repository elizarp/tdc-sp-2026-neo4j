# Fase 2 — CSVs fake

Gerados por [`generate_dados.py`](generate_dados.py) (sem dependências externas, seed fixa = 42,
reproduzível). Para regenerar:

```bash
python3 generate_dados.py
```

Todos os arquivos ficam prontos para `LOAD CSV` direto (fase 3), com os nomes de coluna já
alinhados às propriedades do modelo de dados (documentação local, fora deste repositório).

**`clientes.csv` é o cadastro completo do cliente num arquivo só** — não tem mais
`rgs.csv`/`emails.csv`/`telefones.csv`/`localizacoes.csv` separados. RG/e-mail/telefone/localização
viraram colunas prefixadas (`rg_*`, `email_*`, `telefone_*`) do mesmo jeito que já eram
identificáveis antes, só que juntas — a fase 3 faz tudo (`Cliente`, `Localizacao`, `RG`, `Email`,
`Telefone`) num único `LOAD CSV`, na mesma transação por linha.

**Um cliente pode ter mais de uma linha.** A maioria tem 1 linha só; ~20% dos clientes (fora dos
anéis de fraude) tem 2 — a original (`dataAlteracao` = `dataCriacao`) e uma com **um** dos campos
`rg`/`email`/`telefone` trocado por um valor novo e `dataAlteracao` mais recente. `nome`, `cpf`,
`dataNascimento`, `cidade`, `estado`, `segmento`, `latitude`, `longitude` e `dataCriacao` se
repetem iguais nas duas linhas — só o campo alterado (e a data) muda. A fase 3 usa
`MERGE ... ON CREATE SET` no relacionamento de identidade, então o RG/e-mail/telefone antigo
continua no grafo como histórico (ver
[00-modelo-dados.md § Histórico cadastral](../docs/00-modelo-dados.md#histórico-cadastral)).

## Orçamento de nós: ~195.000 (teto do AuraDB Free é 200.000)

O script calcula primeiro o overhead fixo (Cliente + identidades já deduplicadas pelos anéis de
fraude + Localizacao + Produto/TipoProduto) e só depois distribui o orçamento restante entre
Acesso/AcaoApp/Transacao/Chamado por proporção fixa — o total nunca estoura, mesmo mudando
`N_CLIENTES` no topo do script.

| Arquivo | Linhas | Colunas | Vira no grafo |
|---|---|---|---|
| `clientes.csv` | 1.560 (1.300 clientes, 260 com 2ª linha) | `cliente_id, nome, cpf, dataNascimento, cidade, estado, segmento, latitude, longitude, dataCriacao, dataAlteracao, rg_id, rg_numero, email_id, email_endereco, email_dominio, telefone_id, telefone_numero, telefone_ddd` | `(:Cliente)`, `(:Cliente)-[:LOCALIZADO_EM]->(:Localizacao)`, `(:Cliente)-[:POSSUI_RG]->(:RG)`, `(:Cliente)-[:POSSUI_EMAIL]->(:Email)`, `(:Cliente)-[:POSSUI_TELEFONE]->(:Telefone)` — **o cadastro inteiro do cliente, com histórico** (ver nota acima) |
| `dispositivos.csv` | 1.300 | `cliente_id, device_id, modelo, sistemaOperacional, primeiroAcesso, ultimoAcesso` | `(:Cliente)-[:USA_DISPOSITIVO {primeiroAcesso, ultimoAcesso}]->(:Dispositivo)` — fica separado do cadastro de propósito: dispositivo é dado de *uso*, não algo que o cliente declara no cadastro |
| `transacoes.csv` | ~24.500 | `transacao_id, clienteOrigemId, clienteDestinoId, valor, data, tipo` | `(:Cliente)-[:ENVIOU]->(:Transacao)-[:PARA]->(:Cliente)` |
| `tipos_produto.csv` | 5 | `tipo_id, nome, ehContrato` | `(:TipoProduto)` |
| `produtos.csv` | 10 | `produto_id, nome, categoria, tipo_id` | `(:Produto)-[:DO_TIPO]->(:TipoProduto)` (`tipo_id` só serve pra montar o relacionamento) |
| `contratacoes.csv` | ~2.700 | `cliente_id, produto_id, vezes, valorTotal, ultimoUso` | `(:Cliente)-[:CONTRATOU {vezes, valorTotal, ultimoUso}]->(:Produto)` |
| `acessos.csv` | ~52.700 | `acesso_id, cliente_id, dataHora, canal, sucesso, duracaoSegundos` | `(:Cliente)-[:ACESSOU]->(:Acesso)` |
| `acoes_app.csv` | ~107.300 | `acao_id, acesso_id, tipo, dataHora, produto_id` | `(:Acesso)-[:REALIZOU_ACAO]->(:AcaoApp)`, e `(:AcaoApp)-[:SOBRE_PRODUTO]->(:Produto)` quando `produto_id` não é vazio |
| `chamados.csv` | ~3.760 | `chamado_id, cliente_id, canal, assunto, severidade, status, abertoEm, resolvidoEm, tempoResolucaoHoras, satisfacao, transacaoDisputadaId` | `(:Cliente)-[:ABRIU_CHAMADO]->(:Chamado)`, e `(:Chamado)-[:SOBRE_TRANSACAO]->(:Transacao)` quando `transacaoDisputadaId` não é vazio |
| `registros_brutos.csv` | 115 | `registro_id, nomeBruto, cpfBruto, telefoneBruto, dataNascimentoBruto, cidadeBruto, canalOrigem` | `(:RegistroBruto)` — **sem** link com `Cliente` na carga (isso é o que a resolução de identidade, fase 4, descobre) |

**Total real após dedupe de identidades: 195.000 nós, 1.300 clientes** (verificado por recontagem
independente).

`(:Cliente)-[:SIMILAR_A]->(:Cliente)`, `(:Produto)-[:COMPRADO_JUNTO]->(:Produto)`,
`(evento)-[:PROXIMO_EVENTO]->(evento)` (a jornada), `(:TipoAcao)` + `(:Cliente)-[:REALIZOU_TIPO]->(:TipoAcao)`
(segmentação) e `(:RegistroBruto)-[:RESOLVIDO_PARA|CANDIDATO_MESMO_QUE]->(:Cliente)` (resolução de
identidade) **não** têm CSV — são calculados na fase 3/4 (GDS e agregação/`UNION`/blocking em Cypher).

## Padrões injetados de propósito

- **Anéis de fraude** (18 no total, 3–6 clientes cada): metade reaproveita um `RG`/`Email`/
  `Telefone` entre os membros (fraude de identidade), a outra metade reaproveita o mesmo
  `Dispositivo` (account takeover / credential stuffing).
- **Contas-laranja** (6 clientes): recebem ~20% de todas as transações Pix, com valores mais altos
  (R$ 1.500–15.000) — pensado pra aparecer destacado em PageRank sobre o grafo de Pix.
- **Perfis de contratação** (5 perfis): 75% dos clientes tendem a contratar produtos do mesmo
  perfil — dá sinal real pra Node Similarity / FastRP+KNN, e pra emergirem pares "comprados
  juntos".
- **Peso de atividade por cliente**: cada cliente recebe um peso (a maioria perto de 1.0, alguns
  "power users", alguns quase inativos) usado pra distribuir acessos/transações/chamados de forma
  correlacionada — clientes ativos em um canal tendem a ser ativos nos outros, o que torna a
  jornada (próxima seção) mais realista.
- **Acessos com falha** (~5% do total): simulam tentativa de login malsucedida — nenhuma `AcaoApp`
  é gerada pra um acesso malsucedido, mas o evento em si fica no grafo como sinal de account
  takeover (login falho → login com sucesso de outro dispositivo → Pix de alto valor é o padrão
  clássico do artigo de fraude).
- **Chamados de "Contestação de transação"** (~430 chamados): sempre linkados a uma transação real
  em que o próprio cliente foi a origem — dá pra rastrear "cliente contestou o quê" na jornada.
- **Personas comportamentais** (4 personas: `digital_nativo`, `tradicional`, `investidor_pesquisador`,
  `operacional_puro`): cada cliente tem uma, e ela vies a o canal de `Acesso`, o canal de `Chamado` e
  o tipo de `AcaoApp` — sinal real pra segmentação (Node Similarity/Louvain), diferente do perfil de
  *contratação* acima (uma é comportamento de uso, a outra é o que o cliente compra).
- **Alteração cadastral** (260 clientes, 20% — fora dos anéis de fraude): 2ª linha em
  `clientes.csv` com RG, e-mail **ou** telefone trocado (um campo por cliente) e `dataAlteracao`
  posterior à `dataCriacao` — o dado antigo continua no grafo como histórico (ver
  [00-modelo-dados.md § Histórico cadastral](../docs/00-modelo-dados.md#histórico-cadastral)).
- **Registros brutos** (115: 90 duplicados + 25 negativos): os 90 duplicados são clientes reais
  capturados de novo com ruído — nome abreviado/com typo, CPF mascarado ou sem pontuação, telefone
  sem DDD ou com 1 dígito trocado, às vezes data de nascimento com dia/mês invertidos. Os 25
  negativos são pessoas diferentes de propósito, pra testar se o algoritmo de resolução de
  identidade não erra por excesso de zelo.

## Jornada do cliente

`Acesso`, `Transacao` e `Chamado` têm timestamp (`dataHora`, `data`, `abertoEm`). A fase 3 encadeia
os três por cliente, em ordem cronológica, com `PROXIMO_EVENTO` — a consulta completa está em
[cypher/03_jornada.cypher](../cypher/03_jornada.cypher).

## `gabarito.json` — não carregar no grafo

Guarda a verdade injetada (quais clientes formam cada anel, quais são as contas-laranja, qual o
perfil de cada cliente) só para o palestrante validar os resultados de GDS durante o ensaio.
Fica fora do carregamento (fase 3) e, quando os agentes da fase 5 forem configurados, o padrão do
[aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent) já bloqueia a
leitura de propriedades tipo "gabarito" — mesma lógica aqui: o agente deve *chegar* na resposta via
GDS, não ler a resposta pronta.
