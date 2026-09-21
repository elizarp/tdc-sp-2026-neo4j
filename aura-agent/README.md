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

## As 12 ferramentas

| Ferramenta | Tipo | Caso de uso |
|---|---|---|
| Verificar Anel de Fraude | cypherTemplate | Fraude (WCC) |
| Ranking de Contas Suspeitas por Influência | cypherTemplate | Fraude (PageRank) |
| Recomendar Produto para Cliente | cypherTemplate | Recomendação (Node Similarity) |
| Produtos Comprados Junto | cypherTemplate | Recomendação (agregação) |
| Visão 360 do Cliente | cypherTemplate | Customer 360 |
| Jornada Recente do Cliente | cypherTemplate | Jornada (`PROXIMO_EVENTO`) |
| Ocorrências (Chamados) do Cliente | cypherTemplate | Customer 360 / atendimento (lista os `Chamado` do cliente) |
| Risco de Churn de um Cliente | cypherTemplate | Churn (recência + insatisfação) |
| Ranking de Clientes em Risco de Churn | cypherTemplate | Churn, agregado |
| Segmento Comportamental do Cliente | cypherTemplate | Segmentação (Louvain + Node Similarity) |
| Resolver Identidade de Registro Bruto | cypherTemplate | Resolução de identidade |
| Consulta Livre no Grafo | text2cypher | Fallback pra tudo que não se encaixa acima |

Todas as CypherTemplates foram testadas direto no banco antes de entrar no config (não só
validadas por schema) — inclusive um bug real (`duration.between` vs `duration.inDays`, e um erro
de sintaxe usando `melhor.cliente` direto num `MERGE`) foi encontrado e corrigido nesse processo.

> **"Ocorrências" não é a mesma coisa que "Visão 360".** A Visão 360 só devolve a *contagem* de
> chamados (`totalChamados`) — pra ver o conteúdo de cada um (canal, assunto, severidade,
> satisfação), essa ferramenta separada é necessária. Foi adicionada depois de testar o agente ao
> vivo: perguntar por "ocorrências" não tinha ferramenta dedicada.

## Perguntas de exemplo (testadas, com IDs reais da base)

O agente pede o parâmetro que faltar se você só disser o nome da ferramenta (ex.: digitar
"Verificar Anel de Fraude" sem CPF/ID faz ele perguntar de volta). Pra ir direto ao resultado,
inclua o valor na própria pergunta — como nos exemplos abaixo, todos com IDs reais e resultado
esperado real (testado nesta base):

| Pergunte isso | Ferramenta usada | Resultado esperado |
|---|---|---|
| "O cliente CLI0018 faz parte de algum anel de fraude?" | Verificar Anel de Fraude | Sim — grupo com CLI0050, CLI0112, CLI0149 |
| "Quais as 5 contas com maior score de influência?" | Ranking de Contas Suspeitas | As 6 contas-laranja injetadas, score 345-408 |
| "Que produto você recomenda para o cliente CLI0001?" | Recomendar Produto | Empréstimo Pessoal, CDB Rende Mais, entre outros |
| "Quais produtos são comprados junto com o Cartão Platinum?" | Produtos Comprados Junto | Seguro Viagem (90), Empréstimo Pessoal (89)... |
| "Me dê uma visão completa do cliente CLI0001" | Visão 360 do Cliente | Nome, segmento, cidade, totais de transação/acesso/chamado |
| "Mostre os 10 eventos mais recentes da jornada do cliente CLI0001" | Jornada Recente do Cliente | Mistura de Acesso/Transacao/Chamado em ordem cronológica |
| "Quais ocorrências o cliente CLI0001 abriu?" | Ocorrências (Chamados) do Cliente | 3 chamados, incluindo uma "Contestação de transação" ligada à TX0020438 |
| "O cliente CLI0001 está em risco de cancelar?" | Risco de Churn de um Cliente | Dias sem acessar/transacionar + chamados de insatisfação |
| "Quais os 5 clientes com maior risco de churn?" | Ranking de Clientes em Risco de Churn | Ranking por dias desde o último acesso |
| "Qual o segmento comportamental do cliente CLI0001, e quem se parece com ele?" | Segmento Comportamental | Segmento + até 5 clientes parecidos |
| "Para qual cliente o registro REG0001 foi resolvido?" | Resolver Identidade de Registro Bruto | CLI1423, com score de confiança |
| "Quantos clientes existem no segmento Premium?" | Consulta Livre no Grafo (Text2Cypher) | Contagem — não tem ferramenta dedicada pra isso, é o caso de uso do fallback |

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
