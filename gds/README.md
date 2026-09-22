# Fase 4 — Graph Data Science

**AuraDB Free não tem GDS embarcado.** GDS aqui roda via **Aura Graph Analytics (AGA)** — uma
sessão serverless separada, [anunciada recentemente no Free tier](https://neo4j-aura.canny.io/changelog/aura-graph-analytics-is-now-available-on-auradb-free):
1 sessão simultânea por instância, até 2GB de memória, timeout de 30 min de inatividade, sessão
máxima de 4h, **sem cobrança**. Tudo via Cypher puro (`CALL gds.session.getOrCreate(...)` +
`gds.graph.project(...)` com `sessionId`) — nenhum cliente Python é necessário pros participantes.

Testado de ponta a ponta em **duas instâncias reais**:
- Sandbox self-managed Enterprise (GDS embarcado, só pra comparação).
- **AuraDB Free real** (`b49e0444`, região `sa-east-1`) — é isso que os participantes vão usar, e é
  isso que os scripts abaixo assumem.

## Ordem de execução

1. **[04_gds_fraude.cypher](04_gds_fraude.cypher)** — cria/reconecta a sessão `workshop-session` +
   WCC (identidades compartilhadas) + PageRank (grafo de Pix).
2. **[05_gds_recomendacao.cypher](05_gds_recomendacao.cypher)** — reaproveita a mesma sessão + Node
   Similarity + FastRP/KNN + agregação Cypher pra `COMPRADO_JUNTO`.
3. **[06_gds_jornada.cypher](06_gds_jornada.cypher)** — reaproveita a sessão + BFS sobre
   `PROXIMO_EVENTO`.
4. **[07_segmentacao_comportamental.cypher](07_segmentacao_comportamental.cypher)** — bônus: agrega
   `TipoAcao` + Node Similarity ponderada + Louvain.
5. **[08_resolucao_identidade.cypher](08_resolucao_identidade.cypher)** — bônus: blocking +
   similaridade fuzzy entre `RegistroBruto` e `Cliente`. Roda direto na base conectada, não precisa
   de sessão AGA.

`gds.session.getOrCreate` é idempotente — os scripts 05, 06 e 07 reconectam na sessão criada pelo 04
em vez de criar uma nova (importante: **só dá 1 sessão por vez no Free**, então usar o mesmo nome
`'workshop-session'` em todo lugar não é estilo, é obrigatório).

## Resultados do teste end-to-end (AuraDB Free real)

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
| Blocking + fuzzy matching (`RegistroBruto`↔`Cliente`) | Registros de outros sistemas resolvem pro cliente certo | **90 de 90 duplicados verdadeiros** resolvidos (score ≥ 0.8) pro cliente correto, **0 erros**, **0 falsos positivos** nos 25 negativos verdadeiros |

## Tempo real medido (AuraDB Free, sessão AGA)

| Passo | Tempo |
|---|---|
| Criar a sessão AGA do zero (cold start) | ~43s (só na primeira vez) |
| Reconectar numa sessão já existente + projetar um grafo | 1–5s cada |
| WCC | ~4s |
| PageRank | ~2s |
| Node Similarity | ~2s |
| FastRP + KNN | ~1s cada |
| BFS (20 acessos malsucedidos, `maxDepth: 4`) | ~10s |

Total da fase 4 inteira (3 scripts, sessão fria incluída): **~80 segundos**. Cabe folgado nos ~35
min reservados pra isso na agenda do workshop.

## Lições do teste (pra não repetir na hora do workshop)

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

## Detalhes da resolução de identidade (bloco 08)

Fórmula de score: `0.45×simNome + 0.25×simCpf + 0.20×simTel + 0.10×simData`.
- `simNome`: `1 - apoc.text.jaroWinklerDistance(nomeBruto, cliente.nome)` — cobre abreviação, typo,
  caixa alta.
- `simCpf`: 1.0 se os dígitos do CPF do cliente **contêm** os dígitos do CPF bruto — cobre CPF
  mascarado (só um trecho visível) e CPF sem pontuação.
- `simTel`: 1.0 se bate com ou sem DDD; 0.7 se Levenshtein > 0.85 (cobre 1 dígito trocado). Cliente
  com telefone alterado (fase 2) tem 2 relacionamentos `POSSUI_TELEFONE` — a query pega o
  `max(simTel)` entre eles, não "qualquer um" (ver lições do teste acima).
- `simData`: 1.0 se a data bate exatamente (12% dos casos de teste tinham dia/mês trocados de
  propósito, e ainda resolveram certo — os outros 3 sinais compensam).
- `CANDIDATO_MESMO_QUE` a partir de score ≥ 0.5 (todo candidato plausível); `RESOLVIDO_PARA` só o
  melhor candidato por registro, e só se score ≥ 0.8 (a decisão automática).

Em produção, blocking (mesma cidade/CPF parcial/telefone parecido) viria **antes** do cálculo de
similaridade, pra não comparar todo registro com todo cliente — aqui, a essa escala (115×1.300 =
~150k pares), comparar tudo é mais simples e ainda roda em ~4s.

## Próxima fase

**Fase 5 — Agentes**: um único Aura Agent com 13 ferramentas cobrindo os 6 casos de uso (fraude,
recomendação, Customer 360, jornada, churn, segmentação comportamental e resolução de identidade),
no padrão do [aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent). Já
criado e testado — ver `aura-agent/README.md`.
