// Fase 4.5 — Resolução de identidade (bônus, além dos 3 casos de uso centrais)
// Baseado em https://neo4j.com/developer/industry-use-cases/finserv/retail-banking/entity-resolution/
// — o problema INVERSO da fraude: lá, o mesmo identificador em clientes
// DIFERENTES é suspeito (WCC, bloco 04); aqui, atributos PARECIDOS mas não
// idênticos em registros de sistemas diferentes (agência legada, migração,
// sistema adquirido) têm que voltar a apontar pro mesmo cliente real.
//
// Blocking + similaridade fuzzy, sem GDS pesado — roda direto na base
// conectada (nem precisa de sessão AGA). Testado numa AuraDB Free real:
// dos 90 registros brutos que SÃO duplicados de um cliente real, 90/90
// resolveram pro cliente certo (score >= 0.8) — e nenhum dos 25 registros
// negativos (pessoas diferentes, de propósito) gerou falso positivo.
// Ver gds/README.md.
//
// A essa escala (115 registros × 1.500 clientes = ~172k comparações) dá pra
// comparar todo par sem blocking prévio — em produção, com milhões de
// registros, o primeiro filtro (mesma cidade/CPF parcial/telefone parecido)
// seria feito ANTES de calcular similaridade fuzzy, não depois.

MATCH ()-[r:CANDIDATO_MESMO_QUE]->() DELETE r;
MATCH ()-[r:RESOLVIDO_PARA]->() DELETE r;

MATCH (r:RegistroBruto)
MATCH (c:Cliente)-[:POSSUI_TELEFONE]->(tel:Telefone)
WITH r, c, tel,
     replace(replace(replace(c.cpf, '.', ''), '-', ''), '*', '') AS cpfClienteDigits,
     replace(replace(replace(r.cpfBruto, '.', ''), '-', ''), '*', '') AS cpfBrutoDigits,
     replace(replace(replace(r.telefoneBruto, '(', ''), ')', ''), ' ', '') AS telBrutoLimpo
WITH r, c,
     // similaridade de nome: 1 - distância de Jaro-Winkler (0 = idêntico)
     1 - apoc.text.jaroWinklerDistance(toLower(r.nomeBruto), toLower(c.nome)) AS simNome,
     // CPF: aceita match parcial (CPF mascarado só mostra um trecho)
     CASE WHEN cpfBrutoDigits <> '' AND cpfClienteDigits CONTAINS cpfBrutoDigits THEN 1.0 ELSE 0.0 END AS simCpf,
     // telefone: com ou sem DDD, ou próximo o bastante (Levenshtein) pra cobrir 1 dígito trocado
     CASE
       WHEN telBrutoLimpo = (tel.ddd + tel.numero) THEN 1.0
       WHEN telBrutoLimpo = tel.numero THEN 1.0
       WHEN apoc.text.levenshteinSimilarity(telBrutoLimpo, tel.numero) > 0.85 THEN 0.7
       ELSE 0.0
     END AS simTel,
     CASE WHEN r.dataNascimentoBruto = toString(c.dataNascimento) THEN 1.0 ELSE 0.0 END AS simData
// Cliente com cadastro alterado (fase 2) pode ter mais de um POSSUI_TELEFONE
// (histórico) — pega o MELHOR telefone do cliente pra esse registro, não
// "qualquer um" (senão um telefone antigo/diferente pode arrastar o score
// pra baixo por acaso da ordem de processamento).
WITH r, c, simNome, simCpf, simData, max(simTel) AS simTel
WITH r, c, simNome, simCpf, simTel, simData,
     (0.45 * simNome + 0.25 * simCpf + 0.20 * simTel + 0.10 * simData) AS score
WHERE score >= 0.5
MERGE (r)-[cand:CANDIDATO_MESMO_QUE]->(c)
SET cand.score = score,
    cand.sinais = 'nome=' + toString(round(simNome*100)) + '% cpf=' + toString(simCpf) +
                  ' telefone=' + toString(simTel) + ' data=' + toString(simData);

// Resolução final: só o melhor candidato de cada registro, e só se confiança alta
MATCH (r:RegistroBruto)-[cand:CANDIDATO_MESMO_QUE]->(c:Cliente)
WITH r, c, cand.score AS score
ORDER BY r.registro_id, score DESC
WITH r, collect({cliente: c, score: score})[0] AS melhor
WITH r, melhor.cliente AS cliente, melhor.score AS score
WHERE score >= 0.8
MERGE (r)-[res:RESOLVIDO_PARA]->(cliente)
SET res.score = score;

// Verificação: registros SEM resolução (score alto, mas indefinido —
// candidatos empatados, ou nenhum candidato bom — vão pra revisão manual)
// MATCH (r:RegistroBruto)
// WHERE NOT (r)-[:RESOLVIDO_PARA]->()
// RETURN r.registro_id, r.nomeBruto, r.canalOrigem;
