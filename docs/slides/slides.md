---
marp: true
theme: default
paginate: true
size: 16:9
---

# 1 Grafo, N Casos de Uso
### De fraude a recomendação com Neo4j GDS e Aura Agents

TDC São Paulo 2026 · Workshop (1h30)
Eliézer Zarpelão — Sr. Solutions Engineer LATAM, Neo4j

---

## Quem sou eu

- Sr. Solutions Engineer LATAM @ Neo4j
- +20 anos em engenharia de software
- Professor de Graph Database na FIAP
- Ajudo empresas a usar grafos em fraude, knowledge graphs e personalização
- github.com/elizarp · linkedin.com/in/eliezerzarpelao

---

## O problema

Times de **fraude** e times de **personalização/recomendação** normalmente:

- usam bases diferentes
- duplicam pipelines de identidade do cliente
- reconstroem "quem se parece com quem" duas vezes, com ferramentas diferentes

E se os dois times pudessem usar **o mesmo grafo**?

---

## A ideia central

> Não é o dado que muda entre fraude e recomendação. **É o algoritmo que olha para ele.**

- Fraude → comunidades e influência em identidades/transações compartilhadas
- Recomendação → similaridade e coocorrência em contratações de produto

Mesmo grafo, vários algoritmos de Graph Data Science, dois agentes de IA.

---

## Agenda de hoje

1. O modelo de dados (uma base, múltiplos casos de uso)
2. GDS para fraude — WCC + PageRank
3. GDS para recomendação — Node Similarity + FastRP/KNN
4. Jornada do cliente — Customer 360 encadeando tudo isso
5. Agentes de IA conversando com o grafo
6. Mão na massa: vocês constroem essa base do zero

---

## Caso 1 — Detecção de fraude

Inspirado no *Account Takeover Fraud* (Neo4j Developer):

- Identidades soltas: e-mail, telefone, RG, dispositivo
- Reuso do mesmo identificador entre clientes → **anel de fraude**
- Reuso do mesmo dispositivo em várias contas → **account takeover**
- Fluxo de dinheiro (Pix) concentrado em poucas contas → **conta-laranja**

---

## Caso 2 — Recomendação

Inspirado no *Recommendation Engine Hands-On* (NeoRestro):

```
(:User)-[:HAS_ORDERED]->(:Item)
(:Item)-[:ORDERED_ALONG_WITH]->(:Item)
```

No nosso domínio de fintech:

```
(:Cliente)-[:CONTRATOU]->(:Produto)
(:Produto)-[:COMPRADO_JUNTO]->(:Produto)
```

Mesma estrutura, domínio diferente.

---

## Caso 3 — Jornada do cliente (Customer 360)

`Acesso` (login no app), `Transacao` e `Chamado` (ocorrência multicanal) têm timestamp — dá pra
encadear os três em ordem cronológica com `PROXIMO_EVENTO`, no mesmo padrão de `NEXT` que existe em
schemas reais de fintech:

```
login falho → login OK (dispositivo novo) → Pix de alto valor → chamado de contestação
```

A mesma sequência que um analista de fraude reconhece de cabeça vira uma travessia de caminho.

---

## O modelo de dados unificado

- `Cliente` no centro
- Identidades soltas: `RG`, `Email`, `Telefone`, `Dispositivo`
- `Transacao` (Pix) entre clientes
- `Produto` / `TipoProduto` contratados pelo cliente
- `Chamado` (multicanal) e `Acesso` → `AcaoApp` (sessão no app)

(diagrama completo em `docs/00-modelo-dados.md`)

---

## Por que esse modelo funciona para múltiplos casos

| Caso de uso | Subgrafo | Fica claro quando... |
|---|---|---|
| Fraude | identidades compartilhadas + Pix + acessos falhos | vários clientes compartilham o mesmo RG/e-mail/dispositivo |
| Recomendação | Cliente → Produto | clientes parecidos contratam os mesmos produtos |
| Jornada / Customer 360 | Acesso + Transacao + Chamado encadeados | a sequência de eventos de um cliente conta uma história sozinha |

---

## Os 6 casos de uso que essa base resolve

| Caso de uso | Metodologia | Nós/relacionamentos |
|---|---|---|
| Detecção de fraude | WCC (identidades) + PageRank (Pix) | `Cliente`, `RG`, `Email`, `Telefone`, `Dispositivo`, `Transacao` |
| Recomendação | Node Similarity + FastRP/KNN + `COMPRADO_JUNTO` | `Cliente`, `Produto`, `TipoProduto` |
| Jornada / Customer 360 | BFS sobre `PROXIMO_EVENTO` | `Acesso`, `Transacao`, `Chamado` |
| Churn | Recência (Cypher) + insatisfação em `Chamado` | `Acesso`, `Transacao`, `Chamado` |
| Segmentação comportamental | Node Similarity ponderada + Louvain | `Cliente`, `AcaoApp` agregado em `TipoAcao` |
| Resolução de identidade | Blocking + similaridade fuzzy (Jaro-Winkler/Levenshtein) | `RegistroBruto`, `Cliente`, `Telefone` |

Os 3 primeiros são o foco desta apresentação; os outros 3 já estão testados na mesma base — ver
`gds/README.md`.

---

## Fase 2 — Dados fake com propósito

Não é dado aleatório: injetamos **padrões de propósito**.

- Anéis de fraude de 3–6 clientes reutilizando RG/e-mail/telefone/dispositivo
- Um pequeno grupo de contas recebendo Pix de muitos clientes (conta-laranja)
- Clientes com perfis parecidos contratando os mesmos produtos (senão a
  recomendação não tem o que aprender)
- ~5% de acessos malsucedidos e chamados de "contestação" ligados à transação disputada

**~195 mil nós no total** — perto do teto de 200 mil do AuraDB Free, sem estourar.
CSVs publicados no repo para todo mundo carregar via `LOAD CSV`.

---

## Fase 3 — Constraints antes de tudo

```cypher
CREATE CONSTRAINT cliente_id IF NOT EXISTS
FOR (c:Cliente) REQUIRE c.cliente_id IS UNIQUE;

CREATE CONSTRAINT produto_id IF NOT EXISTS
FOR (p:Produto) REQUIRE p.produto_id IS UNIQUE;
```

Depois, `LOAD CSV` idempotente com `MERGE` — pode rodar de novo sem duplicar.

---

## Fase 4 — GDS para fraude

1. Projetar o grafo de identidades compartilhadas
2. **WCC** (Weakly Connected Components) → cliente ganha `grupoFraude`
3. Projetar o grafo de transações Pix
4. **PageRank** → cliente ganha `scoreInfluencia` (hub suspeito)

Resultado escrito de volta no grafo — sem exportar nada para fora do Neo4j.

---

## Fase 4 — GDS para recomendação

1. Projetar o grafo bipartido `Cliente-[:CONTRATOU]->Produto`
2. **Node Similarity** (Jaccard/Overlap) → `(:Cliente)-[:SIMILAR_A]->(:Cliente)`
3. **FastRP + KNN** → embeddings para similaridade em escala
4. Consulta em `COMPRADO_JUNTO` → recomendação por conteúdo (cross-sell)

---

## Um grafo, dois resultados gravados

```
Cliente {..., grupoFraude: 7, scoreInfluencia: 0.83}
(:Cliente)-[:SIMILAR_A {score: 0.91}]->(:Cliente)
```

Essas propriedades viram a "memória" que os agentes vão consultar.

---

## Fase 5 — Agentes conversando com o grafo

Aura Agent com duas famílias de ferramentas:

- **CypherTemplates**: consultas prontas e parametrizadas (ex: "buscar anel de
  fraude de um CPF", "recomendar produto para um cliente")
- **Text2Cypher**: fallback para perguntas livres

Mesmo padrão do [aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent)
que já uso em produção.

---

## Demo — Agente de fraude

> "Esse cliente faz parte de algum anel de fraude?"
> "Quais são as contas com maior score de influência nas últimas transações?"

O agente só lê o que o GDS já calculou — não decide sozinho, **indica**.

---

## Demo — Agente de recomendação

> "Que produto eu recomendo para esse cliente?"
> "Quais produtos são contratados juntos com cartão de crédito?"

Mesma base, mesmo agente framework, ferramentas diferentes.

---

## Agora é com vocês

Na parte prática (60 min) vocês vão:

1. Subir uma AuraDB Free
2. Criar constraints e carregar os CSVs com `LOAD CSV`
3. Rodar WCC + PageRank e depois Node Similarity + FastRP/KNN
4. Encadear a jornada (`PROXIMO_EVENTO`) e navegar por ela
5. Ver os dois agentes respondendo perguntas sobre a mesma base

---

## Lições aprendidas

Engenharia, não conceito — o que só aparece testando de verdade:

- A plataforma muda mais rápido que a documentação (Aura Graph Analytics chegou no Free tier dias
  antes deste workshop)
- AuraDB Free só permite **1 sessão de GDS por vez** — sempre o mesmo nome de sessão
- Projeção de grafo precisa de `sourceNodeLabels`/`targetNodeLabels` explícitos pra filtros por
  label funcionarem depois
- "Caminho mais longo" ≠ "caminho mais interessante" — BFS sem filtrar por conteúdo só achava o
  evento mais comum, não a história
- Dado sintético não gera sinal sozinho — sem viés de propósito, Node Similarity e Louvain não
  achavam nada
- Testar contra um gabarito desde o início transformou "parece que funcionou" em "18 de 18, 90 de
  90, zero erros"

---

## Venha construir com a gente

- Comunidade Neo4j: **community.neo4j.com**
- Cursos gratuitos: **graphacademy.neo4j.com**
- `[QR code — confirmar link com marketing antes do evento]`
- **Visite o estande da Neo4j aqui no TDC** — time disponível o dia inteiro

---

## Recursos

- Repositório do workshop: `<link a publicar>`
- Modelo de dados: `docs/00-modelo-dados.md`
- Account Takeover Fraud: neo4j.com/developer/industry-use-cases/finserv/retail-banking/account-takeover-fraud
- Recommendation Engine Hands-On: neo4j.com/blog/developer/recommendation-engine-hands-on-1
- Aura Agent de referência: github.com/elizarp/neo4j-agente-fraude

---

# Obrigado!

Perguntas?

eliezer.zarpelao@neo4j.com · linkedin.com/in/eliezerzarpelao
