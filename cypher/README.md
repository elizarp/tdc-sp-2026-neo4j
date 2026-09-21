# Fase 3 — Constraints + carga via `LOAD CSV`

## Ordem de execução

1. **[01_constraints.cypher](01_constraints.cypher)** — todas as constraints de unicidade + índices
   auxiliares nas datas (usados pela jornada e pelo GDS). Idempotente.
2. **[02_carga.cypher](02_carga.cypher)** — `LOAD CSV` de todos os arquivos gerados na fase 2, em
   9 blocos, na ordem certa de dependência (nó antes do relacionamento que aponta pra ele).
   Idempotente (`MERGE` em tudo — pode rodar de novo sem duplicar). O bloco 1 sozinho já carrega
   `Cliente` + `Localizacao` + `RG` + `Email` + `Telefone`, porque `clientes.csv` traz o cadastro
   inteiro numa linha só (ver [data/README.md](../data/README.md)). O último bloco (`RegistroBruto`)
   carrega sem link nenhum com `Cliente` de propósito — a resolução de identidade (fase 4) é quem
   descobre esse link.
3. **[03_jornada.cypher](03_jornada.cypher)** — encadeia `Transacao`/`Acesso`/`Chamado` por cliente
   em ordem cronológica via `PROXIMO_EVENTO`. Precisa rodar depois do passo 2.

## Antes de rodar

Nada — os `LOAD CSV` já apontam direto pro raw do repositório público
([github.com/elizarp/tdc-sp-2026-neo4j](https://github.com/elizarp/tdc-sp-2026-neo4j)), sem
`:param` nem setup. Só precisa que o repositório esteja público antes do workshop.

Em execução local (Neo4j Desktop/Docker) dá pra trocar as URLs por `file:///` apontando pra pasta
`import/` da instância, se preferir não depender de rede.

## Por que `CALL (row) { ... } IN TRANSACTIONS OF N ROWS`

Sintaxe do Cypher 25 (substitui o antigo `USING PERIODIC COMMIT`, removido). Faz commit a cada N
linhas em vez de tudo numa transação só — importante aqui porque `acessos.csv` (~52,5k linhas) e
`acoes_app.csv` (~107k linhas) não cabem confortavelmente numa única transação.

## Tempo real medido

Testado de ponta a ponta 3 vezes (2 numa AuraDB Free real, 1 num sandbox self-managed), sempre
começando de banco vazio: **carga completa em 32-90 segundos** (a variação é mais rede/latência do
que volume de dado). Cabe folgado nos ~15 min reservados na agenda do workshop pra constraints + carga.

## O que NÃO vem de CSV

`SIMILAR_A`/`SIMILAR_A_EMBEDDING`/`SIMILAR_COMPORTAMENTO` (Cliente↔Cliente), `COMPRADO_JUNTO`
(Produto↔Produto), `TipoAcao`/`REALIZOU_TIPO` (segmentação) e `CANDIDATO_MESMO_QUE`/`RESOLVIDO_PARA`
(resolução de identidade) são calculados na fase 4 (GDS + agregação/blocking em Cypher).
`PROXIMO_EVENTO` vem do passo 3 acima, não de CSV.
