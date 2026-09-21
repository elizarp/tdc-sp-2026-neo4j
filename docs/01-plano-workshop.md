# Plano do Workshop — TDC São Paulo 2026

**1 Grafo, N Casos de Uso**: de fraude a recomendação com Neo4j GDS e Aura Agents.

**23/09/2026, 17:00–18:30 (1h30).** Formato build-along: sem bloco separado de slides — você
constrói a base ao vivo junto com os participantes, do primeiro `CREATE CONSTRAINT` até o BFS da
jornada. Roteiro minuto a minuto em [slides/roteiro-ao-vivo.md](slides/roteiro-ao-vivo.md).

## Fases de construção (este repo)

| Fase | Entregável | Status |
|---|---|---|
| 0 | Inspecionar base de referência real via `aura-mcp` (`get-schema`) para inspirar o modelo, sem reaproveitar dados | ✅ feito |
| 1 | Modelo de dados do grafo fictício | ✅ [00-modelo-dados.md](00-modelo-dados.md) |
| 2 | CSVs fake (clientes, identidades, transações Pix, contratações de produto, chamados multicanal, acessos/ações no app) com anéis de fraude, contas-laranja e padrões de coocorrência injetados — ~195 mil nós, dentro do teto de 200 mil do AuraDB Free | ✅ [data/README.md](../data/README.md) |
| 3 | Cyphers de constraints + carga via `LOAD CSV` (idempotente, com `MERGE`) + jornada (`PROXIMO_EVENTO`) | ✅ [cypher/README.md](../cypher/README.md) |
| 4 | Scripts de GDS via Aura Graph Analytics: WCC + PageRank (fraude), Node Similarity + FastRP/KNN (recomendação), BFS (jornada), + **bônus** Louvain/Node Similarity ponderada (segmentação comportamental) e blocking/fuzzy matching (resolução de identidade) — **testado de ponta a ponta numa AuraDB Free real**, banco limpo e recarregado do zero pra validar: 18/18 anéis, 6/6 contas-laranja, 499/500 pares de mesma persona, 90/90 registros resolvidos certo, 0 erros | ✅ [gds/README.md](../gds/README.md) |
| 5 | Um único Aura Agent — 11 ferramentas cobrindo os 6 casos de uso (fraude, recomendação, Customer 360, jornada, churn, segmentação, resolução de identidade) — criado e testado via API real, agente privado (sem custo) | ✅ [aura-agent/README.md](../aura-agent/README.md) |
| 6 | Roteiro ao vivo (build-along, minuto a minuto) | ✅ [slides/roteiro-ao-vivo.md](slides/roteiro-ao-vivo.md) — gerar os slides a partir dele |
| — | Deck conceitual alternativo (formato palestra clássica, se um dia precisar) | ✅ [slides/slides.md](slides/slides.md) |
| — | Proposta para a plataforma do TDC | ✅ [tdc-submissao.md](tdc-submissao.md) |

Cada fase pendente gera sua pasta correspondente: `data/`, `cypher/`, `gds/`, `aura-agent/`
(já criadas, vazias).

## Agenda (1h30) — build-along

Detalhe minuto a minuto, com o que dizer e o que rodar em cada bloco, em
[slides/roteiro-ao-vivo.md](slides/roteiro-ao-vivo.md). Resumo:

| Tempo | Bloco | Participante faz junto? |
|---|---|---|
| 0–5 min | Abertura | não |
| 5–12 min | A ideia + o modelo | não |
| 12–15 min | Preparação (confirmar AuraDB Free de cada um) | sim |
| 15–25 min | Constraints + `LOAD CSV` | **sim** |
| 25–30 min | Jornada (`PROXIMO_EVENTO`) | **sim** |
| 30–45 min | GDS para fraude (WCC + PageRank) | **sim** |
| 45–60 min | GDS para recomendação (Node Similarity + FastRP/KNN) | **sim** |
| 60–72 min | GDS para jornada (BFS) | **sim** |
| 72–85 min | Demo dos Aura Agents (pré-configurados) | não — é demo |
| 85–90 min | Encerramento / perguntas | — |

Fase 5 (agente) é demo, não mão na massa — não cabe montar um Aura Agent do zero em 90 min junto
com o resto. **Já está pronto** ([aura-agent/README.md](../aura-agent/README.md)), é só abrir o chat
no Aura Console no dia.

**Bônus fora da agenda dos 90 min** (testado e documentado, mas não cabe no tempo): segmentação
comportamental e resolução de identidade — ver [gds/README.md](../gds/README.md). Boa matéria pra
"e se a gente fosse além" no encerramento, ou pra expandir o workshop numa versão mais longa.

## Pré-requisitos para os participantes

- Conta gratuita em [console.neo4j.io](https://console.neo4j.io) (AuraDB Free, sem cartão).
- Navegador (Neo4j Browser / Aura Console) — não precisa instalar nada localmente, nem credencial
  de API: o GDS via Aura Graph Analytics roda com `CALL gds.session.getOrCreate(...)` — um
  procedure Cypher comum, autenticado pela própria conexão com o banco.
- Repositório do workshop com os CSVs hospedados (GitHub raw) para `LOAD CSV` direto da internet.

## Observações de infraestrutura para a organização do evento

- Wi-fi estável para ~N participantes conectando simultaneamente a instâncias AuraDB Free.
- Projetor/HDMI para live coding (Neo4j Browser + notebook/terminal).
- Tomadas suficientes (participantes trazem notebook).
