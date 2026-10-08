// Fase 4.6 — Previsão de risco de inadimplência (7º caso de uso)
// Contraste didático com os blocos anteriores: 04-08 usam algoritmos "clássicos"
// de GDS (WCC, PageRank, Node Similarity, FastRP/KNN, BFS, Louvain, blocking) —
// todos não-supervisionados ou determinísticos. Aqui é Node Classification de
// verdade: um classificador SUPERVISIONADO (Random Forest), treinado sobre o
// padrão de atraso progressivo injetado em ObrigacaoPagamento (ver
// data/README.md § Padrões injetados de propósito).
//
// Testado de ponta a ponta numa AuraDB Free real: F1_WEIGHTED de teste
// ~0.9999 e ACCURACY de teste 1.0 (ver pipeline/README.md).
//
// Alternativas testadas e descartadas antes deste script (sem código morto no
// repo, só documentado aqui e em pipeline/README.md): GraphSAGE, FastRP sobre
// o grafo de obrigações, e similaridade por embeddings de jornada. Nenhuma
// delas bateu Random Forest com 3 features escalares simples.

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
// (limpeza idempotente: dropa qualquer grafo/pipeline/modelo de rodada
// anterior antes de recriar — mesmo padrão dos blocos 04-08)
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
// IMPORTANTE: na API de sessão AGA, todo procedimento do catálogo de pipeline/
// modelo pede o nome da sessão ('workshop-session') como 1º argumento — ao
// contrário do catálogo de grafo (gds.graph.*), que não pede. Isso NÃO aparece
// na documentação genérica de Node Classification (que assume GDS embarcado,
// sem sessão) — só foi descoberto testando contra a sessão AGA real.
CALL gds.pipeline.drop('workshop-session', 'pipelineInadimplencia', false) YIELD pipelineName;
CALL gds.model.drop('workshop-session', 'modeloInadimplencia', false) YIELD modelName;

CALL gds.beta.pipeline.nodeClassification.create('workshop-session', 'pipelineInadimplencia');

// Sem addNodeProperty pra embedding nenhum (FastRP foi testado e removido —
// ver pipeline/README.md): só as 3 features escalares de atraso.
CALL gds.beta.pipeline.nodeClassification.selectFeatures('workshop-session', 'pipelineInadimplencia', [
  'atrasoMedioPrimeiros9Meses', 'atrasoMedioUltimos3Meses', 'tendenciaAtraso'
]) YIELD featureProperties;

CALL gds.beta.pipeline.nodeClassification.configureSplit('workshop-session', 'pipelineInadimplencia', {
  testFraction: 0.2,
  validationFolds: 5
}) YIELD splitConfig;

// Único candidato — GraphSAGE/embeddings foram testados à parte e descartados
// (pipeline/README.md), não ficam como código morto aqui.
CALL gds.beta.pipeline.nodeClassification.addRandomForest('workshop-session', 'pipelineInadimplencia', {
  numberOfDecisionTrees: 100
}) YIELD parameterSpace;

// --- Passo 4: treina (aqui sim, só o nome do grafo — sem sessionName) --------
CALL gds.beta.pipeline.nodeClassification.train('inadimplenciaGraph', {
  pipeline: 'pipelineInadimplencia',
  modelName: 'modeloInadimplencia',
  targetProperty: 'inadimplenciaHistorica',
  metrics: ['F1_WEIGHTED', 'ACCURACY']
}) YIELD modelInfo
RETURN modelInfo.bestParameters AS melhoresParametros, modelInfo.metrics.F1_WEIGHTED.test AS f1Teste;

// --- Passo 5: aplica o modelo treinado -----------------------------------------
// predict.write NÃO suporta gravar classe prevista e probabilidades em duas
// propriedades separadas na mesma chamada nesta versão da AGA (testado: com
// includePredictedProbabilities, writeProperty passa a guardar a lista de
// probabilidades inteira, não a classe) — por isso usamos predict.mutate (que
// aceita mutateProperty + predictedProbabilityProperty como propriedades
// distintas) e depois gds.graph.nodeProperties.write pra persistir as duas.
CALL gds.beta.pipeline.nodeClassification.predict.mutate('inadimplenciaGraph', {
  modelName: 'modeloInadimplencia',
  mutateProperty: 'classePrevista',
  includePredictedProbabilities: true,
  predictedProbabilityProperty: 'probabilidades'
}) YIELD nodePropertiesWritten;

CALL gds.graph.nodeProperties.write('inadimplenciaGraph', ['classePrevista', 'probabilidades'])
YIELD propertiesWritten;

// probabilidades[1] é a probabilidade da classe 1 (inadimplenciaHistorica =
// true) — a ordem das classes no vetor é ascendente pelo valor inteiro da
// classe (0=em dia, 1=inadimplente), confirmado contra os dados de teste.
MATCH (c:Cliente) WHERE c.probabilidades IS NOT NULL
SET c.riscoInadimplencia = c.probabilidades[1]
REMOVE c.classePrevista, c.probabilidades;

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
