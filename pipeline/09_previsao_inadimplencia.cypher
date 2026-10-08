// Fase 4.6 — Previsão de risco de inadimplência (7º caso de uso)
// Contraste didático com os blocos anteriores: 04-08 usam algoritmos "clássicos"
// de GDS (WCC, PageRank, Node Similarity, FastRP/KNN, BFS, Louvain, blocking) —
// todos não-supervisionados ou determinísticos. Aqui é Node Classification de
// verdade: um classificador SUPERVISIONADO (Random Forest), treinado sobre o
// padrão de atraso progressivo injetado em ObrigacaoPagamento (ver
// data/README.md § Padrões injetados de propósito).
//
// Alternativas testadas e descartadas antes deste script (sem código morto no
// repo, só documentado aqui e em pipeline/README.md): GraphSAGE, FastRP sobre
// o grafo de obrigações, e similaridade por embeddings de jornada. Nenhuma
// delas bateu Random Forest com 3 features escalares simples — ver "Lições
// aprendidas" em pipeline/README.md.

// --- Passo 1: feature engineering em Cypher puro (mesmo padrão do bloco 07,
// que agrega AcaoApp.tipo antes de projetar) -----------------------------------
MATCH (c:Cliente)-[:POSSUI_OBRIGACAO]->(o:ObrigacaoPagamento)
WITH c, o ORDER BY o.numeroParcela
WITH c, collect(o) AS parcelas
WITH c,
     [p IN parcelas WHERE p.numeroParcela <= 9] AS primeiras9,
     [p IN parcelas WHERE p.numeroParcela > 9]  AS ultimas3
WITH c,
     reduce(s = 0.0, p IN primeiras9 | s + p.diasAtraso) / size(primeiras9) AS atrasoMedioPrimeiros9Meses,
     reduce(s = 0.0, p IN ultimas3  | s + p.diasAtraso) / size(ultimas3)   AS atrasoMedioUltimos3Meses,
     any(p IN ultimas3 WHERE p.status = 'inadimplente') AS inadimplenciaHistorica
SET c.atrasoMedioPrimeiros9Meses = atrasoMedioPrimeiros9Meses,
    c.atrasoMedioUltimos3Meses = atrasoMedioUltimos3Meses,
    c.tendenciaAtraso = atrasoMedioUltimos3Meses - atrasoMedioPrimeiros9Meses,
    c.inadimplenciaHistorica = inadimplenciaHistorica;

// --- Passo 2: projeta o pool de clientes com ObrigacaoPagamento ---------------
CALL gds.graph.drop('inadimplenciaGraph', false) YIELD graphName;

CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (c:Cliente)
  WHERE c.atrasoMedioPrimeiros9Meses IS NOT NULL
  RETURN gds.graph.project(
    'inadimplenciaGraph', c, null,
    { sourceNodeLabels: ['Cliente'],
      sourceNodeProperties: c {
        .atrasoMedioPrimeiros9Meses, .atrasoMedioUltimos3Meses, .tendenciaAtraso,
        inadimplenciaHistorica: toInteger(c.inadimplenciaHistorica)
      } },
    { sessionId: sessionId }
  ) AS proj
}
RETURN sessionId, proj;

// --- Passo 3: pipeline de Node Classification ---------------------------------
CALL gds.beta.pipeline.drop('pipelineInadimplencia', false) YIELD pipelineName;

CALL gds.beta.pipeline.nodeClassification.create('pipelineInadimplencia');

// Sem addNodeProperty pra embedding nenhum (FastRP foi testado e removido —
// ver pipeline/README.md): só as 3 features escalares de atraso.
CALL gds.beta.pipeline.nodeClassification.selectFeatures('pipelineInadimplencia', [
  'atrasoMedioPrimeiros9Meses', 'atrasoMedioUltimos3Meses', 'tendenciaAtraso'
]) YIELD featureProperties;

CALL gds.beta.pipeline.nodeClassification.configureSplit('pipelineInadimplencia', {
  testFraction: 0.2,
  validationFolds: 5
}) YIELD splitConfig;

// Único candidato — GraphSAGE/embeddings foram testados à parte e descartados
// (pipeline/README.md), não ficam como código morto aqui.
CALL gds.beta.pipeline.nodeClassification.addRandomForest('pipelineInadimplencia', {
  numberOfDecisionTrees: 100
}) YIELD parameterSpace;

// --- Passo 4: treina -----------------------------------------------------------
CALL gds.beta.pipeline.nodeClassification.train('inadimplenciaGraph', {
  pipeline: 'pipelineInadimplencia',
  modelName: 'modeloInadimplencia',
  targetProperty: 'inadimplenciaHistorica',
  metrics: ['F1_WEIGHTED', 'ACCURACY']
}) YIELD modelInfo
RETURN modelInfo.bestParameters AS melhoresParametros, modelInfo.metrics.F1_WEIGHTED.test AS f1Teste;

// --- Passo 5: aplica o modelo treinado e grava o score de volta no grafo ------
CALL gds.beta.pipeline.nodeClassification.predict.write('inadimplenciaGraph', {
  modelName: 'modeloInadimplencia',
  writeProperty: 'riscoInadimplencia',
  predictedProbabilityProperty: '_probabilidades'
}) YIELD nodePropertiesWritten;

// --- Passo 6: calibra o corte por prevalência observada (não um valor fixo
// tipo >= 0.5) — percentileCont sobre a distribuição real de scores -----------
MATCH (c:Cliente) WHERE c.riscoInadimplencia IS NOT NULL
WITH count(c) AS total, count(CASE WHEN c.inadimplenciaHistorica THEN 1 END) AS positivos
WITH total, positivos, toFloat(positivos) / total AS taxaPositivaObservada
MATCH (c:Cliente) WHERE c.riscoInadimplencia IS NOT NULL
WITH taxaPositivaObservada, percentileCont(c.riscoInadimplencia, 1 - taxaPositivaObservada) AS corteCalibrado
MATCH (c:Cliente) WHERE c.riscoInadimplencia IS NOT NULL
SET c.altoRiscoInadimplencia = (c.riscoInadimplencia >= corteCalibrado);

// Ranking de risco, pra conferir contra o gabarito (data/gabarito.json →
// clientes_inadimplentes):
// MATCH (c:Cliente) WHERE c.riscoInadimplencia IS NOT NULL
// RETURN c.cliente_id, c.riscoInadimplencia, c.altoRiscoInadimplencia
// ORDER BY c.riscoInadimplencia DESC LIMIT 20;
