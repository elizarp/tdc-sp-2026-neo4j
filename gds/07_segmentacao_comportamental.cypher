// Fase 4.4 — Segmentação comportamental (bônus, além dos 3 casos de uso centrais)
// Contraste didático com a fraude: WCC (bloco 04) acha anel por identidade
// IDÊNTICA; aqui, Node Similarity + Louvain acham segmento por comportamento
// PARECIDO — mesma família de algoritmo (GDS), pergunta de negócio diferente
// (marketing/personalização, não fraude).
//
// Testado numa AuraDB Free real: pares SIMILAR_COMPORTAMENTO de maior score
// batem com a persona comportamental injetada em 499 de 500 casos (99,8%).
// Louvain encontra 3 segmentos grandes com 56-73% de pureza — duas das 4
// personas injetadas (`digital_nativo` e `operacional_puro`) têm preferências
// de ação parecidas de propósito e acabam no mesmo segmento macro; é um
// resultado honesto, não um bug. Ver gds/README.md.

// --- Passo 1: agrega AcaoApp.tipo em TipoAcao (Cypher puro, sem GDS) ---------
// Cria o grafo bipartido Cliente-TipoAcao que a segmentação usa. TipoAcao não
// vem de CSV — é derivado, igual ao padrão de TipoProduto.
MATCH (c:Cliente)-[:ACESSOU]->(:Acesso)-[:REALIZOU_ACAO]->(a:AcaoApp)
WITH c, a.tipo AS tipo, count(*) AS vezes
MERGE (t:TipoAcao {nome: tipo})
MERGE (c)-[r:REALIZOU_TIPO]->(t)
SET r.vezes = vezes;

// --- Passo 2: projeta o bipartido Cliente-TipoAcao, com peso ------------------
CALL gds.graph.drop('segmentacaoGraph', false) YIELD graphName;

CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (source:Cliente|TipoAcao)
  OPTIONAL MATCH (source)-[rel:REALIZOU_TIPO]->(target)
  RETURN gds.graph.project(
    'segmentacaoGraph', source, target,
    { sourceNodeLabels: labels(source), targetNodeLabels: labels(target),
      relationshipProperties: { vezes: coalesce(rel.vezes, 0.0) } },
    { sessionId: sessionId, undirectedRelationshipTypes: ['*'] }
  ) AS proj
}
RETURN sessionId, proj;

// --- Node Similarity (ponderado por 'vezes') — "quem se parece com quem" ----
MATCH ()-[r:SIMILAR_COMPORTAMENTO]->() DELETE r;

CALL gds.nodeSimilarity.filtered.write('segmentacaoGraph', {
  sourceNodeFilter: 'Cliente',
  targetNodeFilter: 'Cliente',
  relationshipWeightProperty: 'vezes',
  writeRelationshipType: 'SIMILAR_COMPORTAMENTO',
  writeProperty: 'score',
  topK: 10
});

// --- Louvain (ponderado) — "em que segmento esse cliente cai" ---------------
CALL gds.louvain.write('segmentacaoGraph', {
  writeProperty: 'segmentoComportamental',
  relationshipWeightProperty: 'vezes'
});

// Quantos clientes por segmento, e o que eles mais fazem:
// MATCH (c:Cliente) WITH c.segmentoComportamental AS seg, count(c) AS n
// RETURN seg, n ORDER BY n DESC LIMIT 10;
