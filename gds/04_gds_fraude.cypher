// Fase 4.1 — GDS para fraude, via Aura Graph Analytics (AGA)
//
// AuraDB Free NÃO tem GDS embarcado — GDS aqui é uma sessão serverless separada
// (AGA), disponível no Free desde o anúncio recente (1 sessão simultânea, até 2GB,
// timeout de 30 min de inatividade, sessão máxima de 4h, sem cobrança). Isso é
// puro Cypher — nenhuma instalação de cliente Python é necessária pros participantes.
//
// Testado de ponta a ponta numa AuraDB Free real: 18/18 anéis do gabarito bateram
// com os componentes do WCC, e as 6/6 contas-laranja ficaram nas 6 primeiras
// posições do PageRank. Ver gds/README.md.

CALL gds.graph.drop('identidadesGraph', false) YIELD graphName;
CALL gds.graph.drop('pixGraph', false) YIELD graphName;

// --- WCC sobre identidades compartilhadas -----------------------------------
// getOrCreate é idempotente: reconecta na sessão 'workshop-session' se ela já
// existir (os próximos scripts 05 e 06 reaproveitam a mesma sessão).
CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (source:Cliente|RG|Email|Telefone|Dispositivo)
  OPTIONAL MATCH (source)-[rel:POSSUI_RG|POSSUI_EMAIL|POSSUI_TELEFONE|USA_DISPOSITIVO]-(target)
  RETURN gds.graph.project(
    'identidadesGraph', source, target,
    { sourceNodeLabels: labels(source), targetNodeLabels: labels(target) },
    { sessionId: sessionId, undirectedRelationshipTypes: ['*'] }
  ) AS proj
}
RETURN sessionId, proj;

CALL gds.wcc.write('identidadesGraph', {writeProperty: 'grupoFraude'});

// Anéis de fraude = componentes com mais de 1 Cliente
// MATCH (c:Cliente)
// WITH c.grupoFraude AS grupo, collect(c.cliente_id) AS clientes
// WHERE size(clientes) > 1
// RETURN grupo, clientes, size(clientes) AS tamanho
// ORDER BY tamanho DESC;

// --- PageRank sobre o grafo de Pix (Cliente-ENVIOU->Transacao-PARA->Cliente) -
// Roda direto sobre o grafo tripartido (sem colapsar Transacao) — mesmo padrão
// do artigo de Account Takeover Fraud, PageRank flui naturalmente através dos
// nós de evento.
CALL gds.session.getOrCreate('workshop-session', '2GB', duration({minutes: 30}))
YIELD id AS sessionId
CALL (sessionId) {
  MATCH (source:Cliente|Transacao)
  OPTIONAL MATCH (source)-[rel:ENVIOU|PARA]->(target)
  RETURN gds.graph.project(
    'pixGraph', source, target,
    { sourceNodeLabels: labels(source), targetNodeLabels: labels(target) },
    { sessionId: sessionId }
  ) AS proj
}
RETURN sessionId, proj;

CALL gds.pageRank.write('pixGraph', {writeProperty: 'scoreInfluencia'});

// Contas-laranja = maior scoreInfluencia
// MATCH (c:Cliente)
// RETURN c.cliente_id, c.scoreInfluencia
// ORDER BY c.scoreInfluencia DESC LIMIT 20;
