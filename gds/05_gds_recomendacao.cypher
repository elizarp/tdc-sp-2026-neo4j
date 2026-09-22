// Fase 4.2 — GDS para recomendação, via Aura Graph Analytics (AGA)
// Reaproveita a sessão 'workshop-session' criada em 04_gds_fraude.cypher (getOrCreate
// é idempotente). Testado numa AuraDB Free real: pares SIMILAR_A de maior score
// compartilham o perfil de contratação injetado em 42-43% dos casos, contra ~11%
// esperado por acaso. Ver gds/README.md.

CALL gds.graph.drop('recomendacaoGraph', false) YIELD graphName;

CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (source:Cliente|Produto)
  OPTIONAL MATCH (source)-[rel:CONTRATOU]-(target)
  RETURN gds.graph.project(
    'recomendacaoGraph', source, target,
    { sourceNodeLabels: labels(source), targetNodeLabels: labels(target) },
    { sessionId: sessionId, undirectedRelationshipTypes: ['*'] }
  ) AS proj
}
RETURN sessionId, proj;

// --- Node Similarity (Jaccard) — collaborative filtering clássico -----------
// .filtered restringe a comparação a Cliente-Cliente (sem gerar Produto-Produto
// junto, que não é o que queremos aqui). Precisa de sourceNodeLabels/
// targetNodeLabels na projeção acima — sem isso, o filtro por label falha.
// write cria relacionamento novo a cada chamada (não é MERGE) — limpa antes,
// pra rodar o script de novo não duplicar.
MATCH ()-[r:SIMILAR_A]->() DELETE r;

CALL gds.nodeSimilarity.filtered.write('recomendacaoGraph', {
  sourceNodeFilter: 'Cliente',
  targetNodeFilter: 'Cliente',
  writeRelationshipType: 'SIMILAR_A',
  writeProperty: 'score',
  topK: 10
});

// --- FastRP + KNN — embeddings pra similaridade em escala -------------------
MATCH ()-[r:SIMILAR_A_EMBEDDING]->() DELETE r;

CALL gds.fastRP.mutate('recomendacaoGraph', {
  embeddingDimension: 64,
  mutateProperty: 'embedding',
  randomSeed: 42
});

CALL gds.knn.filtered.write('recomendacaoGraph', {
  nodeProperties: ['embedding'],
  sourceNodeFilter: 'Cliente',
  targetNodeFilter: 'Cliente',
  writeRelationshipType: 'SIMILAR_A_EMBEDDING',
  writeProperty: 'score',
  topK: 5
});

// Recomendação por similaridade: produtos que clientes parecidos têm e o
// cliente-alvo ainda não tem
// MATCH (alvo:Cliente {cliente_id: $clienteId})-[:SIMILAR_A]->(parecido:Cliente)
// MATCH (parecido)-[:CONTRATOU]->(p:Produto)
// WHERE NOT (alvo)-[:CONTRATOU]->(p)
// RETURN p.nome, count(*) AS recomendado_por, avg(parecido.score) AS confianca
// ORDER BY recomendado_por DESC, confianca DESC LIMIT 5;

// --- Recomendação por conteúdo: produtos comprados juntos (Cypher puro) -----
// Complementa o collaborative filtering acima: agregação direta em CONTRATOU,
// sem GDS — mostra que nem tudo precisa de um algoritmo pra ter valor.
// Com só 10 produtos e 1.300 clientes, TODO par de produtos passa de 5
// coocorrências (testado: 45/45 pares) — não filtra nada. >= 70 ficou testado
// como o corte que isola os ~11 pares realmente puxados pelos perfis
// injetados (ex.: Cartão Platinum+Seguro Viagem, Empréstimo+Financiamento).
MATCH (c:Cliente)-[:CONTRATOU]->(p1:Produto), (c)-[:CONTRATOU]->(p2:Produto)
WHERE p1.produto_id < p2.produto_id
WITH p1, p2, count(c) AS vezes
WHERE vezes >= 70
MERGE (p1)-[r:COMPRADO_JUNTO]->(p2)
SET r.vezes = vezes;
