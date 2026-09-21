// Fase 3.3 — Jornada do cliente
// Rodar DEPOIS de 02_carga.cypher (precisa de Cliente, Transacao, Acesso e
// Chamado já carregados, com os índices de data criados em 01_constraints.cypher).
//
// Encadeia, por cliente, os três tipos de evento com timestamp (Transacao,
// Acesso, Chamado) em ordem cronológica, via PROXIMO_EVENTO — o mesmo padrão
// de NEXT do schema real inspecionado via aura-mcp (ver docs/00-modelo-dados.md
// § Jornada do cliente).
//
// Rodar em batches por cliente evita uma única transação gigante (1.500
// clientes, ~190 eventos em média cada).

MATCH (c:Cliente)
CALL (c) {
  CALL (c) {
    MATCH (c)-[:ENVIOU]->(e:Transacao)      RETURN e, e.data     AS quando
    UNION
    MATCH (c)-[:ACESSOU]->(e:Acesso)        RETURN e, e.dataHora AS quando
    UNION
    MATCH (c)-[:ABRIU_CHAMADO]->(e:Chamado) RETURN e, e.abertoEm AS quando
  }
  WITH e, quando ORDER BY quando
  WITH collect(e) AS eventos
  UNWIND range(0, size(eventos) - 2) AS i
  WITH eventos[i] AS e1, eventos[i + 1] AS e2
  MERGE (e1)-[:PROXIMO_EVENTO]->(e2)
} IN TRANSACTIONS OF 50 ROWS;

// Verificação rápida: quantos PROXIMO_EVENTO foram criados e um exemplo de
// jornada completa de um cliente ativo.
// MATCH ()-[r:PROXIMO_EVENTO]->() RETURN count(r);
//
// MATCH (c:Cliente)-[:ACESSOU|ENVIOU|ABRIU_CHAMADO]->(inicio)
// WHERE NOT ( ()-[:PROXIMO_EVENTO]->(inicio) )
// WITH c, inicio LIMIT 1
// MATCH caminho = (inicio)-[:PROXIMO_EVENTO*0..20]->(fim)
// RETURN c.cliente_id, [n IN nodes(caminho) | labels(n)[0]] AS sequencia_de_eventos
// ORDER BY size(sequencia_de_eventos) DESC LIMIT 1;
