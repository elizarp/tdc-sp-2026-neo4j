# Fase 5 — Agente

**Um agente só, seis casos de uso.** Criado e testado via API real (`api.neo4j.io`) sobre a
instância AuraDB Free `b49e0444`. Config completo em [agent-config.json](agent-config.json).

## Por que um agente privado

Criar um Aura Agent **público** exige forma de pagamento cadastrada no projeto (mesmo que a
instância de banco seja Free — é exigência a nível de conta, não da instância). Um agente
**privado** (`is_private: true`) não exige isso.

Trade-off: um agente privado **não recebe endpoint de API/MCP** — a resposta de criação não traz
`endpoint_link`/`mcp_endpoint_link`, e chamar `.../invoke` via API dá `403 "Agent is private"`. Ele
só funciona pelo **chat dentro do Aura Console** (Console → Agents → agente → conversar). Pra uma
demo ao vivo isso não é uma limitação — é até melhor visualmente do que `curl`.

## As 11 ferramentas

| Ferramenta | Tipo | Caso de uso |
|---|---|---|
| Verificar Anel de Fraude | cypherTemplate | Fraude (WCC) |
| Ranking de Contas Suspeitas por Influência | cypherTemplate | Fraude (PageRank) |
| Recomendar Produto para Cliente | cypherTemplate | Recomendação (Node Similarity) |
| Produtos Comprados Junto | cypherTemplate | Recomendação (agregação) |
| Visão 360 do Cliente | cypherTemplate | Customer 360 |
| Jornada Recente do Cliente | cypherTemplate | Jornada (`PROXIMO_EVENTO`) |
| Risco de Churn de um Cliente | cypherTemplate | Churn (recência + insatisfação) |
| Ranking de Clientes em Risco de Churn | cypherTemplate | Churn, agregado |
| Segmento Comportamental do Cliente | cypherTemplate | Segmentação (Louvain + Node Similarity) |
| Resolver Identidade de Registro Bruto | cypherTemplate | Resolução de identidade |
| Consulta Livre no Grafo | text2cypher | Fallback pra tudo que não se encaixa acima |

Todas as CypherTemplates foram testadas direto no banco antes de entrar no config (não só
validadas por schema) — inclusive um bug real (`duration.between` vs `duration.inDays`, e um erro
de sintaxe usando `melhor.cliente` direto num `MERGE`) foi encontrado e corrigido nesse processo.

## Como recriar/atualizar

```bash
TOKEN=$(curl -s --request POST 'https://api.neo4j.io/oauth/token' \
  --user "$AURA_CLIENT_ID:$AURA_CLIENT_SECRET" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' | jq -r '.access_token')

# criar
curl -X POST "https://api.neo4j.io/v2beta1/organizations/$ORG_ID/projects/$PROJECT_ID/agents" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @agent-config.json

# atualizar (PATCH parcial — só os campos que mudam)
curl -X PATCH "https://api.neo4j.io/v2beta1/organizations/$ORG_ID/projects/$PROJECT_ID/agents/$AGENT_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"tools": [...]}'
```

`ORG_ID` e `PROJECT_ID` costumam ser o mesmo UUID numa conta com um único projeto — confirme em
`GET /v2beta1/organizations` e `GET /v2beta1/organizations/{orgId}/projects`.

## Guardrails no system prompt

- O agente **indica padrões, nunca afirma culpa** ("indício", "candidato a", nunca "é fraude").
- Churn é framed como **ranking relativo** entre os próprios clientes da base, não um limiar fixo
  de dias — os dados são fictícios numa janela de tempo específica (2025-2026), comparar com a
  data real do dia do workshop não faz sentido.
- Nunca inventa números — todo valor numérico vem de uma consulta ao grafo.
