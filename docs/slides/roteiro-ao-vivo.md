# Roteiro ao vivo — 1 Grafo, N Casos de Uso

23/09/2026, 17:00–18:30 (90 min). Formato **build-along**: você constrói a base ao vivo, na mesma
velocidade que os participantes, em vez de mostrar slides e só depois soltar pra mão na massa. Cada
`##` abaixo é um bloco de slide(s) + a ação ao vivo correspondente. Os números de resultado citados
são reais, do teste de ponta a ponta feito com banco **limpo e recarregado do zero** numa AuraDB
Free real (ver [gds/README.md](../../gds/README.md)) — pode citar com confiança, não são estimativa.

> **Pré-requisito crítico (fazer ANTES do dia 23/09):** publicar `data/`, `cypher/` e `gds/` num
> repo público (GitHub) — `$baseUrl` do `LOAD CSV` depende disso. Sem isso, ninguém consegue
> carregar os CSVs ao vivo.

---

## Antes do workshop (checklist, não é slide)

**Você (apresentador), até o dia 22/09:**
- [ ] Repositório publicado no GitHub com `data/*.csv`, `cypher/*.cypher`, `gds/*.cypher`.
- [ ] Uma instância AuraDB Free sua, pré-carregada e com a fase 4 já rodada, como **backup** — se
      o wifi do evento falhar durante a demo ao vivo, você segue pela instância de backup sem
      travar o workshop.
- [ ] Os dois Aura Agents (fraude e recomendação — fase 5) **já configurados** nessa instância de
      backup. Não dá tempo de montar agente ao vivo em 90 min — isso é demo, não mão na massa (ver
      bloco final).
- [ ] Dry run completo cronometrado, se possível na mesma rede do evento.
- [ ] E-mail/mensagem pros inscritos, com 1-2 dias de antecedência: criar conta grátis em
      [console.neo4j.io](https://console.neo4j.io) e subir uma instância AuraDB Free *antes* de
      chegar (evita perder 5-10 min do workshop com signup).

**Participantes, antes de chegar:**
- [ ] Conta + instância AuraDB Free criadas.
- [ ] Navegador com Neo4j Browser ou Aura Query aberto.

---

## Bloco 1 — Abertura (17:00–17:05 · 5 min)

**Slide: título + quem sou eu.**

Fale rápido, isso é aquecimento, não o conteúdo:
- Sr. Solutions Engineer LATAM @ Neo4j, professor na FIAP, +20 anos de engenharia de software.
- A pergunta que abre o workshop: *"por que o time de fraude e o time de recomendação da mesma
  empresa, olhando pro mesmo cliente, quase sempre usam bases e pipelines diferentes?"*

Não precisa de ação ao vivo ainda.

---

## Bloco 2 — A ideia + o modelo (17:05–17:14 · 9 min)

**Slide: "não é o dado que muda, é o algoritmo que olha pra ele".**

Mostre o diagrama do modelo (de [00-modelo-dados.md](../00-modelo-dados.md)) e narre em 3 camadas,
sem entrar em Cypher ainda:

1. **Identidade** — `Cliente` + `RG`/`Email`/`Telefone`/`Dispositivo` soltos → sinal de fraude
   quando reaproveitados entre clientes.
2. **Transação e produto** — `Transacao` (Pix) e `Cliente-[:CONTRATOU]->Produto` → fluxo de
   dinheiro e sinal de recomendação.
3. **Jornada** — `Acesso`, `Chamado` e a própria `Transacao` têm timestamp → dá pra contar a
   história de um cliente em ordem cronológica (Customer 360).

Diga o número do dataset aqui, já cria expectativa: **~195 mil nós, 1.500 clientes**, calibrado pra
caber no teto de 200 mil do AuraDB Free.

**Slide: "os 6 casos de uso que essa base resolve" (tabela de referência — mostre rápido, ela existe
pra consulta, não pra ler linha por linha ao vivo).**

| Caso de uso | Metodologia | Nós/relacionamentos envolvidos | Hoje |
|---|---|---|---|
| Detecção de fraude | WCC (identidades compartilhadas) + PageRank (grafo de Pix) | `Cliente`, `RG`, `Email`, `Telefone`, `Dispositivo`, `Transacao` | Mão na massa (bloco 6) |
| Recomendação | Node Similarity + FastRP/KNN (bipartido `Cliente-Produto`) + agregação (`COMPRADO_JUNTO`) | `Cliente`, `Produto`, `TipoProduto` | Mão na massa (bloco 7) |
| Jornada / Customer 360 | BFS sobre a cadeia `PROXIMO_EVENTO` | `Acesso`, `Transacao`, `Chamado` | Mão na massa (bloco 8) |
| Churn | Recência (Cypher, `duration.inDays`) + insatisfação em `Chamado` | `Acesso`, `Transacao`, `Chamado` | Só via agente (bloco 9) |
| Segmentação comportamental | Node Similarity ponderada + Louvain | `Cliente`, `AcaoApp` agregado em `TipoAcao` (derivado, sem CSV) | Bônus — não ao vivo |
| Resolução de identidade | Blocking + similaridade fuzzy (Jaro-Winkler + Levenshtein + match parcial de CPF) | `RegistroBruto`, `Cliente`, `Telefone` | Bônus — não ao vivo |

Uma frase de amarração: "quatro desses seis a gente constrói juntos hoje; os outros dois já estão
testados no mesmo grafo, e a gente volta neles no encerramento se der tempo."

---

## Bloco 3 — Preparação (17:14–17:17 · 3 min)

**Slide: "antes de começar" (checklist na tela).**

Confirme com a sala:
- Todo mundo tem uma AuraDB Free rodando?
- Todo mundo tem o link do repositório aberto?
- **Atenção**: em instâncias Free mais novas, usuário e database às vezes vêm iguais ao ID da
  instância (ex.: `b49e0444`/`b49e0444`), não o clássico `neo4j`/`neo4j` — cada um confere as
  próprias credenciais na tela de conexão da Console antes de tentar logar.

Passe o `:param baseUrl => 'https://raw.githubusercontent.com/<org>/<repo>/main/data/'` na tela —
todo mundo cola isso primeiro.

---

## Bloco 4 — Mão na massa 1: Constraints + carga (17:17–17:27 · 10 min)

**Slide: "por que constraints antes de carregar".** Uma frase: sem `UNIQUE`, todo `MERGE` vira um
`MATCH` completo na base inteira — em 195 mil nós isso é a diferença entre 1 minuto e "a página
travou".

**Ação ao vivo — todo mundo cola junto, na ordem:**
1. `cypher/01_constraints.cypher` (13 constraints + 3 índices).
2. `cypher/02_carga.cypher` (10 blocos de `LOAD CSV`).

**O que dizer enquanto carrega:** no teste real (banco limpo, do zero), a carga inteira levou
**~90 segundos** — dá pra
literalmente contar em voz alta enquanto sobe, e ainda aproveitar o tempo morto pra apontar os
padrões injetados nos dados (18 anéis de fraude, 6 contas-laranja, 5 perfis de contratação — ver
[data/README.md](../../data/README.md)) sem revelar ainda os resultados.

**Verificação rápida (todo mundo roda):**
```cypher
MATCH (n) RETURN count(n) AS total;
```
Esperado: **195.000**. Se alguém tiver um número bem diferente, é sinal de que algum bloco falhou —
peça pra rodar de novo (é idempotente, `MERGE` não duplica).

---

## Bloco 5 — Mão na massa 2: Jornada (17:27–17:32 · 5 min)

**Slide: o encadeamento `PROXIMO_EVENTO` (mostrar a query de** [03_jornada.cypher](../../cypher/03_jornada.cypher) **na tela).**

Explique a ideia em uma frase: três tipos de nó diferentes (`Acesso`, `Transacao`, `Chamado`), uma
`UNION` que junta todos os que têm timestamp, ordena, e liga consecutivos.

**Ação ao vivo:** rodar `cypher/03_jornada.cypher`.

**Esperado:** ~4 segundos, **~79 mil relacionamentos `PROXIMO_EVENTO`** criados. Rápido o
suficiente pra nem precisar preencher tempo — já emenda no próximo bloco.

---

## Bloco 6 — Mão na massa 3: GDS para fraude (17:32–17:47 · 15 min)

**Slide: uma frase sobre COMO o GDS roda aqui, antes de entrar nos algoritmos.** AuraDB Free não
tem GDS embarcado — cada `gds/*.cypher` abre (ou reconecta) uma sessão serverless (**Aura Graph
Analytics**, lançada recentemente no Free) via `gds.session.getOrCreate`, tudo em Cypher, sem
instalar nada. É rápido: a sessão inteira + os três scripts de GDS levaram **~80s** no teste real.

**Slide: WCC — o que é e como ajuda em fraude.**
- **O que é:** agrupa nós que estão conectados entre si, direta ou indiretamente, ignorando a
  direção da aresta — "quem consegue chegar em quem, andando pelo grafo".
- **Como ajuda em fraude:** se dois clientes compartilham RG, e-mail, telefone ou dispositivo, eles
  caem no mesmo componente. Um componente com 1 cliente é normal; um componente com 3+ é, por
  construção, identidade reaproveitada — candidato a anel de fraude. WCC não "decide" que é fraude,
  só revela a estrutura que já estava no grafo.

**Slide: PageRank — o que é e como ajuda em fraude.**
- **O que é:** mede a importância de um nó pela importância de quem aponta pra ele — não é só
  "quantas conexões chegam", é "conexões de quem". Nasceu pra rankear páginas web pelos links que
  recebiam.
- **Como ajuda em fraude:** no grafo de Pix, uma conta que recebe transferência de muitas contas
  diferentes acumula score alto — exatamente o padrão de uma conta-laranja recebendo depósitos de
  vários golpes diferentes. Quanto mais espalhadas as origens, maior o score.

**Ação ao vivo:** rodar `gds/04_gds_fraude.cypher` (projeta + WCC + PageRank).

**Momento interativo (antes de revelar o resultado):** pergunte pra sala — *"quem acha que consegue
achar uma conta-laranja só olhando o grafo?"* — deixa 1-2 pessoas tentarem no Browser antes de rodar
a query de verificação.

**Verificação (WCC):**
```cypher
MATCH (c:Cliente)
WITH c.grupoFraude AS grupo, collect(c.cliente_id) AS clientes
WHERE size(clientes) > 1
RETURN grupo, clientes, size(clientes) AS tamanho
ORDER BY tamanho DESC;
```
**Esperado:** **18 componentes** — batem exatamente com os 18 anéis injetados na fase 2 (testado,
zero ruído).

**Verificação (PageRank):**
```cypher
MATCH (c:Cliente)
RETURN c.cliente_id, c.scoreInfluencia
ORDER BY c.scoreInfluencia DESC LIMIT 10;
```
**Esperado:** as 6 contas-laranja injetadas aparecem nas 6 primeiras posições, com score na casa de
**345–408** contra uma média de **0,95** no resto da base — a diferença é gritante na tela, ótimo
momento de "uau" pra plateia.

---

## Bloco 7 — Mão na massa 4: GDS para recomendação (17:47–18:02 · 15 min)

**Slide: Node Similarity — o que é e como ajuda em recomendação.**
- **O que é:** para cada par de nós, mede quantos vizinhos eles têm em comum, proporcionalmente
  (interseção sobre união — coeficiente de Jaccard). Simples de calcular, fácil de explicar pra
  qualquer stakeholder.
- **Como ajuda em recomendação:** dois clientes que contrataram muitos dos mesmos produtos têm
  Node Similarity alta — collaborative filtering clássico: "clientes parecidos com você compraram
  X". Funciona bem até a base ficar grande demais pra comparar todo par com todo par.

**Slide: FastRP — o que é e como ajuda em recomendação.**
- **O que é:** transforma cada nó num vetor numérico (embedding) que resume sua posição na rede —
  nós com vizinhança parecida ficam com vetores parecidos. Rápido e escala pra grafos gigantes, ao
  custo de ser menos direto de interpretar que o Node Similarity.
- **Como ajuda em recomendação:** é o que torna viável fazer o que o Node Similarity faz, mas numa
  base com milhões de clientes — em vez de comparar vizinhança par a par, compara vetores.

**Slide: KNN — o que é e como ajuda em recomendação.**
- **O que é:** dado os embeddings do FastRP, acha os K vizinhos mais próximos de cada nó no espaço
  vetorial (aqui, por similaridade de cosseno).
- **Como ajuda em recomendação:** é a mesma pergunta do Node Similarity — "quem é mais parecido com
  quem" — respondida em cima dos embeddings, de um jeito que escala. Por isso o workshop mostra os
  dois algoritmos lado a lado: mesmo problema, duas soluções, escalas diferentes.

**Ação ao vivo:** rodar `gds/05_gds_recomendacao.cypher` (Node Similarity + FastRP/KNN +
`COMPRADO_JUNTO` via Cypher puro).

**Verificação:**
```cypher
MATCH (a:Cliente)-[r:SIMILAR_A]->(b:Cliente)
RETURN a.cliente_id, b.cliente_id, r.score
ORDER BY r.score DESC LIMIT 10;
```
Comente o número real: nos pares de maior score, **43% compartilham o mesmo perfil de contratação
injetado**, contra **~11% esperado por acaso** — o algoritmo achou o sinal sem nunca ter visto o
perfil, só o padrão de compra.

```cypher
MATCH (p1:Produto)-[r:COMPRADO_JUNTO]->(p2:Produto)
RETURN p1.nome, p2.nome, r.vezes
ORDER BY r.vezes DESC;
```
**Esperado:** ~11 pares, ex. "Cartão Platinum + Seguro Viagem" (90 clientes) — mostra que nem tudo
precisa de GDS pra ter valor, uma agregação simples já conta uma história.

---

## Bloco 8 — Mão na massa 5: GDS para jornada (18:02–18:14 · 12 min)

**Este é o fechamento da história — guarde energia pra ele.**

**Slide: BFS (Busca em Largura) — o que é e como ajuda na jornada.**
- **O que é:** explora o grafo "em camadas" a partir de um nó de origem — acha tudo que está a 1
  salto, depois a 2 saltos, depois a 3, e assim por diante.
- **Como ajuda aqui:** a partir de um login que falhou, o BFS acha tudo que aconteceu depois na
  jornada daquele cliente. Se aparecer um Pix de valor alto poucos saltos depois, é o padrão
  clássico de account takeover contado como **sequência** — diferente de WCC (que acha comunidade)
  e PageRank (que acha influência), o BFS acha **ordem**.

**Slide: "e se a gente perguntar pro grafo: depois de um login que falhou, o que aconteceu?"**

**Ação ao vivo:** rodar `gds/06_gds_jornada.cypher` (BFS filtrando por Pix de alto valor no
caminho).

**Esperado:** sequências como
```
Acesso → Transacao → Transacao → Transacao → Transacao
valores_pix: [2839.65, 2927.17, 545.22, 1721.09]
```
Narre isso como a história completa: login que falhou → (implícito: outro login com sucesso) →
uma sequência de Pix logo em seguida. É literalmente o padrão do artigo de Account Takeover Fraud
contado como travessia de caminho, no mesmo grafo que achou os anéis de fraude e recomendou
produto duas seções atrás.

**Fechamento do bloco (fale isso explicitamente):** "WCC achou comunidade, PageRank achou
influência, Node Similarity e KNN acharam parecença, BFS achou sequência — cinco algoritmos
diferentes, uma base só, sem migrar dado nenhum entre uma pergunta e outra."

**Gancho pro encerramento (uma frase, não desenvolva agora):** "e dá pra ir além, sem mudar uma
linha do modelo — os mesmos dados de `Acesso` e `Chamado` que a gente acabou de usar também servem
pra prever **churn**: cliente que para de acessar o app e some das transações, com um chamado de
insatisfação no meio do caminho, é candidato a cancelamento. Fica de bônus pro encerramento."

---

## Bloco 9 — Demo dos agentes de IA (18:14–18:24 · 10 min)

**Importante: isso é DEMO, não mão na massa.** Não dá tempo de configurar um Aura Agent do zero em
13 minutos, e a agenda já não tem folga pra isso — os dois agentes vêm **pré-configurados** por você
antes do evento (checklist do topo), no padrão do
[aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent).

**Slide: CypherTemplates + Text2Cypher, uma frase cada.**
- CypherTemplates = perguntas conhecidas, viram query parametrizada pronta.
- Text2Cypher = fallback pra pergunta livre.

**Demo ao vivo (você digita, a plateia lê a resposta):**
1. Agente de fraude: *"esse cliente faz parte de algum anel de fraude?"* (usa um `cliente_id` de um
   dos 18 anéis) e *"quais as contas com maior score de influência?"*.
2. Agente de recomendação: *"que produto eu recomendo pra esse cliente?"* e *"quais produtos são
   comprados junto com Cartão Platinum?"*.

Feche com a mensagem central: o agente só **lê** o que WCC/PageRank/Node Similarity já calcularam —
ele não decide, ele consulta.

---

## Bloco 10 — Encerramento (18:24–18:32 · 8 min)

**Slide: "e se a gente fosse além?" — o gancho do bloco 8, agora desenvolvido.**

Retome a frase que você deixou solta no bloco 8: os mesmos `Acesso`/`Transacao`/`Chamado` que
alimentaram a jornada também dão sinal de **churn** — já é uma das ferramentas do agente que vocês
acabaram de ver (bloco 9). Se sobrar tempo ou vier pergunta, tem mais dois casos de uso **já
testados no mesmo grafo, fora da agenda de hoje por falta de tempo, não por limitação**:
segmentação comportamental (Louvain + Node Similarity sobre como o cliente usa os canais — 3
personas encontradas com 56-73% de pureza, sem nunca ver o rótulo) e resolução de identidade
(blocking + similaridade fuzzy de nome/CPF/telefone — 90 de 90 registros de sistemas legados
resolvidos pro cliente certo). Ver [gds/README.md](../../gds/README.md) se alguém pedir detalhe.
Não desenvolva ao vivo — é só pra fechar a mensagem central do workshop com prova de que "múltiplos
casos de uso" não para em 3.

**Slide: Lições aprendidas.**

Não é lição de negócio, é lição de engenharia — o tipo de coisa que só aparece testando de
verdade, não lendo doc. Vale mais pra essa plateia do que outro slide de conceito:

- **A plataforma muda mais rápido que o material.** Aura Graph Analytics chegou no Free tier
  poucos dias antes deste workshop — sempre confira o changelog antes de assumir uma limitação
  como definitiva.
- **AuraDB Free só permite 1 sessão de GDS por vez.** Use sempre o mesmo nome de sessão
  (`gds.session.getOrCreate` é idempotente) — nomes diferentes entre scripts estouram
  `429 Session limit reached`.
- **`sourceNodeLabels`/`targetNodeLabels` na projeção não é opcional** sempre que um algoritmo
  depois for filtrar por label (Node Similarity/KNN `.filtered`) — sem isso, "the node label
  is missing from the graph".
- **"Caminho mais longo" não é "caminho mais interessante".** BFS puro, sem filtrar por conteúdo,
  só achava sequências do evento mais comum (`Acesso` repetido). Filtrar por Pix de valor no
  caminho é o que trouxe a narrativa de account takeover.
- **Dado sintético não gera sinal sozinho.** Sem viés de propósito nos perfis de contratação e nas
  personas comportamentais, Node Similarity e Louvain não achavam nada — dado aleatório não tem
  padrão pra um algoritmo achar.
- **Agente privado não cobra, mas também não tem endpoint de API** — só chat no Console. Trade-off
  real, não bug.
- **Testar contra um gabarito desde o início** (quem são os anéis de fraude de verdade, quem são
  as contas-laranja de verdade) foi o que transformou "parece que funcionou" em "18 de 18, 90 de
  90, zero erros" — sem isso, um resultado plausível na tela pode estar sutilmente errado.

**Slide: venha construir com a gente.**

- Comunidade Neo4j: [community.neo4j.com](https://community.neo4j.com) — fórum de dúvidas, gente
  que já passou pelo mesmo problema.
- [graphacademy.neo4j.com](https://graphacademy.neo4j.com) — cursos gratuitos, inclusive de Graph
  Data Science e Aura Agents.
- **[Inserir QR code aqui]** apontando pro link que a organização/marketing confirmar (comunidade,
  Discord, ou formulário de contato) — não travar esse slide num link genérico, confirmar com o
  time de marketing da Neo4j antes do dia 23/09.
- **Visite o estande da Neo4j no TDC** — time por lá o dia inteiro pra dúvida de modelagem,
  demo ao vivo, ou só trocar ideia sobre grafo.

**Slide: recursos + contato.**

- Link do repositório (CSVs, constraints, GDS, tudo reaproveitável).
- `docs/00-modelo-dados.md` pra quem quiser adaptar o modelo pro próprio domínio.
- `eliezer.zarpelao@neo4j.com` · `linkedin.com/in/eliezerzarpelao`.

Pergunta de fechamento pra deixar no ar: *"que outro caso de uso vocês rodariam nesse mesmo
grafo, sem mudar uma linha do modelo?"*

---

## Conferência de tempo

| Bloco | Duração | Acumulado |
|---|---|---|
| 1. Abertura | 5 min | 5 |
| 2. Ideia + modelo (+ tabela dos 6 casos de uso) | 9 min | 14 |
| 3. Preparação | 3 min | 17 |
| 4. Constraints + carga | 10 min | 27 |
| 5. Jornada | 5 min | 32 |
| 6. GDS fraude | 15 min | 47 |
| 7. GDS recomendação | 15 min | 62 |
| 8. GDS jornada | 12 min | 74 |
| 9. Demo agentes | 10 min | 84 |
| 10. Encerramento (gancho + lições aprendidas + comunidade/estande + recursos) | 8 min | 92 |

Dá 92, não 90 — os 2 min extra saem da folga que já existia: a carga real leva ~90s (não 10 min) e
a jornada ~4s (não 5 min), sobra de propósito pra perguntas, wifi lento, ou alguém que ficou pra
trás. Se o bloco 10 apertar, corte o slide de "comunidade/estande" pra depois do encerramento
oficial (ele pode ficar no ar enquanto a plateia sai) — não corte lições aprendidas, é o que fica
com o público.
