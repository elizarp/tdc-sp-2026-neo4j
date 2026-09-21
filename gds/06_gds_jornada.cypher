// Fase 4.3 — GDS para jornada / Customer 360, via Aura Graph Analytics (AGA)
// Reaproveita a sessão 'workshop-session'. Testado numa AuraDB Free real: BFS a
// partir de um Acesso malsucedido, filtrando por Pix de valor no caminho, acha
// sequências como Acesso -> Transacao -> Transacao -> Transacao -> Transacao.
// Ver gds/README.md.

CALL gds.graph.drop('jornadaGraph', false) YIELD graphName;

CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (source:Acesso|Transacao|Chamado)
  OPTIONAL MATCH (source)-[rel:PROXIMO_EVENTO]->(target)
  RETURN gds.graph.project(
    'jornadaGraph', source, target,
    { sourceNodeLabels: labels(source), targetNodeLabels: labels(target) },
    { sessionId: sessionId }
  ) AS proj
}
RETURN sessionId, proj;

// BFS a partir de cada acesso malsucedido, olhando só os 4 próximos saltos da
// jornada e filtrando pra sequências que já têm um Pix de valor (> 1000)
// no meio — candidatos a account takeover: login falho -> ... -> Pix alto
// valor. Testado: usar "caminho mais longo" sem esse filtro só trazia
// sequências de Acesso repetido (o tipo de evento mais comum) — o filtro por
// Transacao de valor é o que faz a narrativa aparecer.
//
// Numa sessão AGA Free (concurrency: 1) isso demora mais que nos tiers pagos
// — rodar em ~2500 acessos malsucedidos leva bem mais que os poucos segundos
// dos outros algoritmos. Se estiver com pouco tempo no palco, limite ANTES do
// BFS (ex.: LIMIT 20 acessos malsucedidos) em vez de esperar todos.
MATCH (inicio:Acesso {sucesso: false})
WITH inicio LIMIT 20
CALL (inicio) {
  CALL gds.bfs.stream('jornadaGraph', {sourceNode: inicio, maxDepth: 4})
  YIELD path
  WITH path, nodes(path) AS ns
  WHERE any(n IN ns WHERE n:Transacao AND n.valor > 1000)
  RETURN path
  ORDER BY size(nodes(path)) DESC
  LIMIT 1
}
WITH inicio, path
RETURN inicio.acesso_id AS acesso_falho,
       [n IN nodes(path) | labels(n)[0]] AS sequencia,
       [n IN nodes(path) WHERE 'Transacao' IN labels(n) | n.valor] AS valores_pix
ORDER BY size(sequencia) DESC
LIMIT 20;

// Alternativa mais cirúrgica pra demo: caminho mais curto entre um Acesso
// malsucedido específico e o próximo Chamado de "Contestação de transação"
// do mesmo cliente (se existir), via Dijkstra sem peso (todos os saltos custam 1):
// MATCH (a:Acesso {acesso_id: $acessoId})
// MATCH (ch:Chamado {assunto: 'Contestação de transação'})<-[:ABRIU_CHAMADO]-(:Cliente)<-[:ACESSOU]-(a)
// CALL gds.shortestPath.dijkstra.stream('jornadaGraph', {sourceNode: a, targetNode: ch})
// YIELD path
// RETURN [n IN nodes(path) | labels(n)[0]] AS sequencia;
