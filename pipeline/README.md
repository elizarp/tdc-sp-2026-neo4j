# Fase 3+4 — Constraints, carga e Graph Data Science

Pasta única e numerada ponta a ponta (antes dividida em `cypher/` + `gds/`) — a ordem de execução
completa do workshop é a ordem dos arquivos aqui dentro, 01 a 09.

## Ordem de execução

1. **[01_constraints.cypher](01_constraints.cypher)** — todas as constraints de unicidade + índices
   auxiliares nas datas (usados pela jornada e pelo GDS). Idempotente.
2. **[02_carga.cypher](02_carga.cypher)** — `LOAD CSV` de todos os arquivos gerados na fase 2, em
   10 blocos, na ordem certa de dependência (nó antes do relacionamento que aponta pra ele).
   Idempotente (`MERGE` em tudo — pode rodar de novo sem duplicar). O bloco 1 sozinho já carrega
   `Cliente` + `Localizacao` + `RG` + `Email` + `Telefone`, porque `clientes.csv` traz o cadastro
   inteiro (ver [data/README.md](../data/README.md)) — **inclusive mais de uma linha por cliente**,
   quando ele alterou RG/e-mail/telefone. Os relacionamentos de identidade usam
   `MERGE ... ON CREATE SET` em vez de `SET` puro: a data "desde" só é gravada na 1ª vez que aquele
   par (cliente, identidade) aparece, então uma 2ª linha do mesmo cliente não sobrescreve a data
   original do que não mudou, e o dado antigo continua no grafo como histórico. O bloco 9
   (`RegistroBruto`) carrega sem link nenhum com `Cliente` de propósito — a resolução de identidade
   (bloco 08) é quem descobre esse link. O bloco 10 (`ObrigacaoPagamento`) carrega as parcelas usadas
   na previsão de inadimplência (bloco 09).
3. **[03_jornada.cypher](03_jornada.cypher)** — encadeia `Transacao`/`Acesso`/`Chamado` por cliente
   em ordem cronológica via `PROXIMO_EVENTO`. Precisa rodar depois do passo 2.
4. **[04_gds_fraude.cypher](04_gds_fraude.cypher)** — cria/reconecta a sessão `workshop-session` +
   WCC (identidades compartilhadas) + PageRank (grafo de Pix).
5. **[05_gds_recomendacao.cypher](05_gds_recomendacao.cypher)** — reaproveita a mesma sessão + Node
   Similarity + FastRP/KNN + agregação Cypher pra `COMPRADO_JUNTO`.
6. **[06_gds_jornada.cypher](06_gds_jornada.cypher)** — reaproveita a sessão + BFS sobre
   `PROXIMO_EVENTO`.
7. **[07_segmentacao_comportamental.cypher](07_segmentacao_comportamental.cypher)** — bônus: agrega
   `TipoAcao` + Node Similarity ponderada + Louvain.
8. **[08_resolucao_identidade.cypher](08_resolucao_identidade.cypher)** — bônus: blocking +
   similaridade fuzzy entre `RegistroBruto` e `Cliente`. Roda direto na base conectada, não precisa
   de sessão AGA.
9. **[09_previsao_inadimplencia.cypher](09_previsao_inadimplencia.cypher)** — 7º caso de uso: feature
   engineering em Cypher puro + pipeline de Node Classification (Random Forest) supervisionado,
   prevendo risco de inadimplência sobre o padrão de atraso progressivo injetado em
   `ObrigacaoPagamento`.

`gds.session.getOrCreate` é idempotente — os scripts 05, 06, 07 e 09 reconectam na sessão criada
pelo 04 em vez de criar uma nova (importante: **só dá 1 sessão por vez no Free**, então usar o mesmo
nome `'workshop-session'` em todo lugar não é estilo, é obrigatório).

## Antes de rodar

Nada — os `LOAD CSV` já apontam direto pro raw do repositório público
([github.com/elizarp/tdc-sp-2026-neo4j](https://github.com/elizarp/tdc-sp-2026-neo4j)), sem
`:param` nem setup. Só precisa que o repositório esteja público antes do workshop.

Em execução local (Neo4j Desktop/Docker) dá pra trocar as URLs por `file:///` apontando pra pasta
`import/` da instância, se preferir não depender de rede.

**AuraDB Free não tem GDS embarcado.** GDS aqui roda via **Aura Graph Analytics (AGA)** — uma
sessão serverless separada, [anunciada recentemente no Free tier](https://neo4j-aura.canny.io/changelog/aura-graph-analytics-is-now-available-on-auradb-free):
1 sessão simultânea por instância, até 2GB de memória, timeout de 30 min de inatividade, sessão
máxima de 4h, **sem cobrança**. Tudo via Cypher puro (`CALL gds.session.getOrCreate(...)` +
`gds.graph.project(...)` com `sessionId`) — nenhum cliente Python é necessário pros participantes.

## Por que `CALL (row) { ... } IN TRANSACTIONS OF N ROWS`

Sintaxe do Cypher 25 (substitui o antigo `USING PERIODIC COMMIT`, removido). Faz commit a cada N
linhas em vez de tudo numa transação só — importante aqui porque `acessos.csv` (~51k linhas) e
`acoes_app.csv` (~104k linhas) não cabem confortavelmente numa única transação.

## Testado de ponta a ponta

Blocos 01-09: testados de ponta a ponta numa AuraDB Free real (instância `d034b8ef`), banco vazio
→ carga → jornada → GDS (01-09), tudo numa rodada só: **carga completa (01-03) em ~24s**,
**GDS 04-08 em ~190s** (sessão AGA fria incluída, ~106s só no cold start, confirmando o padrão já
documentado), **bloco 09 em ~19s** (sessão já quente). Cabe folgado na agenda do workshop.

## Resultados do teste end-to-end (AuraDB Free real, blocos 01-09)

| Algoritmo | O que valida | Resultado real |
|---|---|---|
| WCC (`identidadesGraph`) | Anéis de fraude do gabarito viram componentes conectados | **18 de 18 anéis** bateram exatamente com um componente WCC |
| PageRank (`pixGraph`) | Contas-laranja concentram influência no grafo de Pix | **6 de 6 contas-laranja** nas 6 primeiras posições (top 5 com score 345–408 contra média 0,95) |
| Node Similarity (`recomendacaoGraph`) | Clientes do mesmo perfil ficam parecidos | Pares `SIMILAR_A` de maior score compartilham o perfil injetado em **42-43%** dos casos, contra **~11%** esperado por acaso |
| FastRP + KNN | Alternativa por embedding pro mesmo problema | 7.500 relacionamentos `SIMILAR_A_EMBEDDING` (topK=5) |
| Cypher puro (`COMPRADO_JUNTO`) | Coocorrência de produtos | **11 pares** com `vezes >= 70` (calibrado — com só 10 produtos, threshold 5 não filtra nada, 45/45 pares passam) |
| BFS (`jornadaGraph`) | Sequência de account takeover é encontrável | `Acesso → Transacao → Transacao → Transacao → Transacao`, valores [2839, 2927, 545, 1721] |
| Node Similarity ponderada (`segmentacaoGraph`) | Clientes com a mesma persona comportamental ficam parecidos | Pares `SIMILAR_COMPORTAMENTO` de maior score compartilham a persona injetada em **499 de 500 casos (99,8%)** |
| Louvain ponderado (`segmentacaoGraph`) | Segmentos macro emergem do comportamento | 6 comunidades — **3 grandes** (663/561/273 clientes) com 56-73% de pureza por persona, mais 3 singletons. `digital_nativo` e `operacional_puro` se misturam num segmento (preferências de ação parecidas de propósito — resultado honesto, não bug) |
| Blocking + fuzzy matching (`RegistroBruto`↔`Cliente`) | Registros de outros sistemas resolvem pro cliente certo | **89-90 de 90 duplicados verdadeiros** resolvidos (score ≥ 0.8) pro cliente correto (varia 1 caso entre rodadas por causa do ruído aleatório injetado), **0 falsos positivos** nos 25 negativos verdadeiros |
| Node Classification — Random Forest (`inadimplenciaGraph`) | Previsão de risco de inadimplência a partir do atraso progressivo em `ObrigacaoPagamento` | F1_WEIGHTED de teste **0.9999**, ACCURACY de teste **1.0**; corte calibrado por prevalência (`altoRiscoInadimplencia`) bateu **250 de 250** clientes do gabarito (100% precisão, 100% recall), 0 falsos positivos |

## Lições aprendidas

- **`Transacao.data` precisou virar `datetime` completo** (era só `date`): misturar `date` e
  `datetime` no `UNION`/`ORDER BY quando` da jornada (bloco 03) quebra a ordenação cronológica —
  Cypher compara por *tipo* antes de *valor* quando os tipos divergem, então um `date` e um
  `datetime` do mesmo dia não ficam necessariamente na ordem certa um em relação ao outro. Corrigido
  na fase 2 (`data/gerador_dados.py`) e no bloco 02 (`datetime(row.data)` em vez de `date(row.data)`).
- **Username ≠ `neo4j` em instâncias Free mais novas**: a instância de teste usa `NEO4J_USERNAME`
  e `NEO4J_DATABASE` iguais ao ID da instância (`b49e0444`), não o clássico `neo4j`/`neo4j`. Sempre
  confira as credenciais exatas que a Console entrega, não assuma o default.
- **Só 1 sessão AGA por vez no Free**: usar nomes de sessão diferentes entre scripts estoura
  `429 Session limit reached`. Todos os scripts usam `'workshop-session'`.
- **`sessionId` só entra no `gds.graph.project`**, nunca nas chamadas de algoritmo depois
  (`gds.wcc.write`, `gds.pageRank.write` etc. não aceitam essa chave — dá erro "Unexpected
  configuration key").
- **`sourceNodeLabels`/`targetNodeLabels` são obrigatórios na projeção** (4º argumento do
  `gds.graph.project`) sempre que algum algoritmo depois usar `sourceNodeFilter`/`targetNodeFilter`
  por label (caso do Node Similarity e do KNN `.filtered`) — sem isso, "the node label `Cliente` is
  missing from the graph".
- **`gds.session.delete` só retorna a coluna `deleted`**, não `id`/`name` como outros procedures.
- **`nodeSimilarity`/`knn` escrevem relacionamento novo a cada chamada**, não fazem `MERGE` — os
  scripts agora limpam (`DELETE`) antes de escrever de novo, senão rodar duas vezes duplica.
- **BFS sem filtro de conteúdo não é interessante**: "caminho mais longo" a partir de um acesso
  malsucedido só trazia `Acesso` repetido (é o evento mais comum). Filtrar por Pix de valor no
  caminho é o que traz a narrativa — e `LIMIT 20` acessos malsucedidos antes do BFS (em vez de rodar
  pra todos os ~2.600) é o que mantém isso em ~10s numa sessão Free de 1 núcleo.
- **A resposta de alguns `write` mostra `writeProperty`/`writeRelationshipType` genéricos** (ex.:
  `componentId`, `similarity`, `SIMILAR`) mesmo quando você passa outro nome — é só um detalhe
  cosmético da resposta da API AGA; o property/relacionamento realmente escrito no banco é o que
  você pediu (confirmado consultando o grafo direto depois).
- **Cliente com histórico cadastral (fase 2) pode ter mais de um `POSSUI_TELEFONE`/`POSSUI_EMAIL`/
  `POSSUI_RG`** — a query de resolução de identidade (bloco 08) fazia `MATCH (c)-[:POSSUI_TELEFONE]
  ->(tel)` e usava o score de "qualquer" telefone que viesse por último no processamento, não o
  melhor. Isso derrubou 3 dos 90 matches verdadeiros pra baixo do limiar de 0.8. Corrigido agregando
  `max(simTel)` por par (registro, cliente) **antes** de calcular o score final — mesmo cuidado vale
  pra qualquer campo que passe a ter histórico (múltiplos relacionamentos do mesmo tipo).
- **Alternativas testadas e descartadas pro bloco 09 (previsão de inadimplência)**: GraphSAGE,
  FastRP sobre o grafo de `ObrigacaoPagamento`, e similaridade por embeddings de jornada — nenhuma
  bateu Random Forest com as 3 features escalares (`atrasoMedioPrimeiros9Meses`,
  `atrasoMedioUltimos3Meses`, `tendenciaAtraso`), que sozinho chegou a 100% de precisão/recall nos
  250 clientes injetados. O padrão de degradação é forte e linear o suficiente pra não precisar de
  nenhuma estrutura de grafo/embedding — por isso o pipeline final **não usa embedding nenhum**.
  Mantido fora do repositório como código morto; registrado só aqui, em prosa.
- **Corte de classificação calibrado por prevalência** (`percentileCont(score, 1 -
  taxaPositivaObservada)`), em vez de um limiar fixo tipo `>= 0.5`: um valor fixo quebraria
  silenciosamente se a proporção real de inadimplentes mudasse (hoje é 250/500 = 50%, mas calculado
  dinamicamente a cada execução, não hardcoded).
- **Na sessão AGA, o catálogo de pipeline/modelo (`gds.beta.pipeline.nodeClassification.*`,
  `gds.pipeline.*`, `gds.model.*`) pede o nome da sessão (`'workshop-session'`) como 1º argumento**
  — diferente do catálogo de grafo (`gds.graph.*`), que não pede. Isso não aparece na documentação
  genérica de Node Classification (que assume GDS embarcado, sem sessão); só foi descoberto testando
  contra a sessão AGA real (`gds.beta.pipeline.nodeClassification.create('workshop-session',
  'pipelineInadimplencia')`, não só `create('pipelineInadimplencia')`). `train` e `predict.*`, por
  outro lado, só pedem o nome do grafo — não da sessão.
- **`predict.write` não grava classe prevista e probabilidades em duas propriedades separadas**
  nesta versão da AGA: com `includePredictedProbabilities: true`, `writeProperty` passa a guardar a
  lista de probabilidades inteira (sobrescrevendo a classe), e `predictedProbabilityProperty` é
  ignorado silenciosamente (sem erro, só um aviso de "property key does not exist" ao ler depois).
  O fix foi usar `predict.mutate` (que aceita `mutateProperty` + `predictedProbabilityProperty` como
  propriedades distintas de verdade) seguido de `gds.graph.nodeProperties.write(...)` pra persistir
  as duas — só então extrair `riscoInadimplencia = probabilidades[1]` (índice 1 = probabilidade da
  classe `1`/inadimplente, confirmado contra os dados de teste) em Cypher puro.

## Detalhes da resolução de identidade (bloco 08)

Fórmula de score: `0.45×simNome + 0.25×simCpf + 0.20×simTel + 0.10×simData`.
- `simNome`: `1 - apoc.text.jaroWinklerDistance(nomeBruto, cliente.nome)` — cobre abreviação, typo,
  caixa alta.
- `simCpf`: 1.0 se os dígitos do CPF do cliente **contêm** os dígitos do CPF bruto — cobre CPF
  mascarado (só um trecho visível) e CPF sem pontuação.
- `simTel`: 1.0 se bate com ou sem DDD; 0.7 se Levenshtein > 0.85 (cobre 1 dígito trocado). Cliente
  com telefone alterado (fase 2) tem 2 relacionamentos `POSSUI_TELEFONE` — a query pega o
  `max(simTel)` entre eles, não "qualquer um" (ver lições aprendidas acima).
- `simData`: 1.0 se a data bate exatamente (12% dos casos de teste tinham dia/mês trocados de
  propósito, e ainda resolveram certo — os outros 3 sinais compensam).
- `CANDIDATO_MESMO_QUE` a partir de score ≥ 0.5 (todo candidato plausível); `RESOLVIDO_PARA` só o
  melhor candidato por registro, e só se score ≥ 0.8 (a decisão automática).

Em produção, blocking (mesma cidade/CPF parcial/telefone parecido) viria **antes** do cálculo de
similaridade, pra não comparar todo registro com todo cliente — aqui, a essa escala (115×1.300 =
~150k pares), comparar tudo é mais simples e ainda roda em ~4s.

## Detalhes da previsão de inadimplência (bloco 09)

- **Alvo de treino** (`inadimplenciaHistorica`): calculado em Cypher a partir do histórico de
  `ObrigacaoPagamento` (`status = 'inadimplente'` nas últimas 3 parcelas), nunca carregado pronto do
  CSV — mesmo princípio de `grupoFraude`/`scoreInfluencia`, que também são sempre calculados.
- **Features**: `atrasoMedioPrimeiros9Meses`, `atrasoMedioUltimos3Meses`, `tendenciaAtraso` (a
  diferença entre as duas médias) — todas derivadas de `ObrigacaoPagamento.diasAtraso`.
- **Modelo**: Random Forest (`numberOfDecisionTrees: 100`), único candidato — ver "Lições
  aprendidas" acima pro porquê de não ter GraphSAGE/embeddings.
- **Saída**: `Cliente.riscoInadimplencia` (probabilidade, via `predict.mutate` +
  `gds.graph.nodeProperties.write`, ver "lições aprendidas" acima) e `Cliente.altoRiscoInadimplencia`
  (bool, corte calibrado por prevalência observada).
- **Testado numa AuraDB Free real**: F1_WEIGHTED de teste 0.9999, ACCURACY de teste 1.0,
  `altoRiscoInadimplencia` bateu 250 de 250 clientes do gabarito (100% precisão/recall).

## Próxima fase

**Fase 5 — Agentes**: um único Aura Agent com 16 ferramentas cobrindo os 7 casos de uso (fraude,
recomendação, Customer 360, jornada, churn, segmentação comportamental, resolução de identidade e
previsão de risco de inadimplência), no padrão do
[aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent). Já criado e
testado (blocos 01-08) — ver `aura-agent/README.md`.
