# 1 Grafo, N Casos de Uso

Workshop do TDC São Paulo 2026 (23/09, 17:00–18:30): como uma única base em grafo Neo4j resolve
seis casos de uso de negócio diferentes — detecção de fraude, recomendação de produtos, visão 360
do cliente, jornada, churn, segmentação comportamental e resolução de identidade — trocando só o
algoritmo de Graph Data Science que "olha" para o grafo, sem remodelar nada entre um caso e outro.

Base fictícia de uma fintech ("FinTechConecta"), ~195 mil nós, calibrada para caber no teto do
AuraDB Free. Tudo neste repositório foi testado de ponta a ponta contra uma instância AuraDB Free
real, com o banco limpo e recarregado do zero.

## Comece por aqui

1. **[docs/00-modelo-dados.md](docs/00-modelo-dados.md)** — o modelo de grafo: nós, relacionamentos,
   diagrama, e como cada caso de uso usa um subgrafo diferente.
2. **[docs/01-plano-workshop.md](docs/01-plano-workshop.md)** — plano geral, fases de construção,
   agenda.
3. **[docs/slides/roteiro-ao-vivo.md](docs/slides/roteiro-ao-vivo.md)** — roteiro minuto a minuto
   do workshop (formato build-along). **[docs/slides/slides.md](docs/slides/slides.md)** é o deck
   alternativo em formato de palestra clássica.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| [`data/`](data) | Gerador dos CSVs fake (`generate_dados.py`) + os CSVs em si, prontos pra `LOAD CSV` |
| [`cypher/`](cypher) | Constraints + carga (`LOAD CSV`) + construção da jornada do cliente |
| [`gds/`](gds) | Scripts de Graph Data Science (via Aura Graph Analytics) para os 6 casos de uso |
| [`aura-agent/`](aura-agent) | Config do Aura Agent único que responde perguntas sobre os 6 casos de uso |
| [`docs/`](docs) | Modelo de dados, plano do workshop, slides, submissão do TDC |

## Passo a passo pra rodar

```bash
# 1. Gerar os CSVs (opcional — já vêm gerados no repo, só regerar se mudar algo em data/generate_dados.py)
cd data && python3 generate_dados.py

# 2. No Neo4j Browser / Aura Query, apontando pra sua AuraDB Free:
:param baseUrl => 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/'
```

Depois, na ordem: `cypher/01_constraints.cypher` → `cypher/02_carga.cypher` →
`cypher/03_jornada.cypher` → `gds/04_gds_fraude.cypher` → `gds/05_gds_recomendacao.cypher` →
`gds/06_gds_jornada.cypher` → (bônus) `gds/07_segmentacao_comportamental.cypher` →
`gds/08_resolucao_identidade.cypher`. Detalhes e resultados esperados em cada `README.md` das
pastas acima.

## O que não está neste repositório (de propósito)

`data/gabarito.json` — a verdade injetada nos dados fake (quais clientes formam cada anel de
fraude, quais são as contas-laranja, qual registro bruto resolve pra qual cliente) fica só na
máquina de quem gera os dados, nunca commitada. É a resposta do exercício — publicar isso junto
com os CSVs tiraria a graça de descobrir ao vivo. Ver [data/README.md](data/README.md).

## Autor

Eliézer Zarpelão — Sr. Solutions Engineer LATAM, Neo4j
[linkedin.com/in/eliezerzarpelao](https://linkedin.com/in/eliezerzarpelao) ·
eliezer.zarpelao@neo4j.com
