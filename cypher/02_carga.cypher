// Fase 3.2 — Carga via LOAD CSV (idempotente, com MERGE)
// Rodar DEPOIS de 01_constraints.cypher, na ordem dos blocos abaixo
// (algumas cargas dependem de nós criados no bloco anterior).
//
// Antes de rodar, defina o parâmetro com a URL base dos CSVs (GitHub raw do
// repositório do workshop, terminando em "/"):
//
//   :param baseUrl => 'https://raw.githubusercontent.com/<org>/<repo>/main/data/'
//
// Cada bloco usa `CALL (row) { ... } IN TRANSACTIONS OF 1000 ROWS` (Cypher 25)
// pra não estourar memória de transação em arquivos grandes (acessos.csv e
// acoes_app.csv passam de 50k/100k linhas).

// ============================================================
// 1) Cliente
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'clientes.csv' AS row
CALL (row) {
  MERGE (c:Cliente {cliente_id: row.cliente_id})
  SET c.nome = row.nome,
      c.cpf = row.cpf,
      c.dataNascimento = date(row.dataNascimento),
      c.cidade = row.cidade,
      c.estado = row.estado,
      c.segmento = row.segmento,
      c.dataCadastro = date(row.dataCadastro)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 2) TipoProduto e Produto (+ DO_TIPO)
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'tipos_produto.csv' AS row
CALL (row) {
  MERGE (t:TipoProduto {tipo_id: row.tipo_id})
  SET t.nome = row.nome,
      t.ehContrato = toBoolean(row.ehContrato)
} IN TRANSACTIONS OF 100 ROWS;

LOAD CSV WITH HEADERS FROM $baseUrl + 'produtos.csv' AS row
CALL (row) {
  MERGE (p:Produto {produto_id: row.produto_id})
  SET p.nome = row.nome,
      p.categoria = row.categoria
  WITH p, row
  MATCH (t:TipoProduto {tipo_id: row.tipo_id})
  MERGE (p)-[:DO_TIPO]->(t)
} IN TRANSACTIONS OF 100 ROWS;

// ============================================================
// 3) Localizacao (+ LOCALIZADO_EM) — location_id se repete por cidade, dedupe automático
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'localizacoes.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (l:Localizacao {location_id: row.location_id})
  SET l.cidade = row.cidade,
      l.estado = row.estado,
      l.latitude = toFloat(row.latitude),
      l.longitude = toFloat(row.longitude)
  MERGE (c)-[:LOCALIZADO_EM]->(l)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 4) Identidades soltas (RG, Email, Telefone, Dispositivo)
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'rgs.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (r:RG {rg_id: row.rg_id})
  SET r.numero = row.numero
  MERGE (c)-[rel:POSSUI_RG]->(r)
  SET rel.desde = date(row.desde)
} IN TRANSACTIONS OF 1000 ROWS;

LOAD CSV WITH HEADERS FROM $baseUrl + 'emails.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (e:Email {email_id: row.email_id})
  SET e.endereco = row.endereco,
      e.dominio = row.dominio
  MERGE (c)-[rel:POSSUI_EMAIL]->(e)
  SET rel.desde = date(row.desde)
} IN TRANSACTIONS OF 1000 ROWS;

LOAD CSV WITH HEADERS FROM $baseUrl + 'telefones.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (t:Telefone {telefone_id: row.telefone_id})
  SET t.numero = row.numero,
      t.ddd = row.ddd
  MERGE (c)-[rel:POSSUI_TELEFONE]->(t)
  SET rel.desde = date(row.desde)
} IN TRANSACTIONS OF 1000 ROWS;

LOAD CSV WITH HEADERS FROM $baseUrl + 'dispositivos.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (d:Dispositivo {device_id: row.device_id})
  SET d.modelo = row.modelo,
      d.sistemaOperacional = row.sistemaOperacional
  MERGE (c)-[rel:USA_DISPOSITIVO]->(d)
  SET rel.primeiroAcesso = date(row.primeiroAcesso),
      rel.ultimoAcesso = date(row.ultimoAcesso)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 5) Transacao (+ ENVIOU, PARA) — grafo de Pix entre clientes
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'transacoes.csv' AS row
CALL (row) {
  MATCH (origem:Cliente {cliente_id: row.clienteOrigemId})
  MATCH (destino:Cliente {cliente_id: row.clienteDestinoId})
  MERGE (t:Transacao {transacao_id: row.transacao_id})
  SET t.valor = toFloat(row.valor),
      t.data = date(row.data),
      t.tipo = row.tipo
  SET t:Pix
  MERGE (origem)-[:ENVIOU]->(t)
  MERGE (t)-[:PARA]->(destino)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 6) Contratacoes (+ CONTRATOU)
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'contratacoes.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MATCH (p:Produto {produto_id: row.produto_id})
  MERGE (c)-[rel:CONTRATOU]->(p)
  SET rel.vezes = toInteger(row.vezes),
      rel.valorTotal = toFloat(row.valorTotal),
      rel.ultimoUso = date(row.ultimoUso)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 7) Acesso (+ ACESSOU) — logins/sessões no app
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'acessos.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (a:Acesso {acesso_id: row.acesso_id})
  SET a.dataHora = datetime(row.dataHora),
      a.canal = row.canal,
      a.sucesso = toBoolean(row.sucesso),
      a.duracaoSegundos = toInteger(row.duracaoSegundos)
  MERGE (c)-[:ACESSOU]->(a)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 8) AcaoApp (+ REALIZOU_ACAO, SOBRE_PRODUTO) — clickstream dentro da sessão
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'acoes_app.csv' AS row
CALL (row) {
  MATCH (a:Acesso {acesso_id: row.acesso_id})
  MERGE (acao:AcaoApp {acao_id: row.acao_id})
  SET acao.tipo = row.tipo,
      acao.dataHora = datetime(row.dataHora)
  MERGE (a)-[:REALIZOU_ACAO]->(acao)
  WITH acao, row
  WHERE row.produto_id IS NOT NULL AND row.produto_id <> ''
  MATCH (p:Produto {produto_id: row.produto_id})
  MERGE (acao)-[:SOBRE_PRODUTO]->(p)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 9) Chamado (+ ABRIU_CHAMADO, SOBRE_TRANSACAO) — ocorrências multicanal
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'chamados.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MERGE (ch:Chamado {chamado_id: row.chamado_id})
  SET ch.canal = row.canal,
      ch.assunto = row.assunto,
      ch.severidade = row.severidade,
      ch.status = row.status,
      ch.abertoEm = datetime(row.abertoEm),
      ch.resolvidoEm = CASE WHEN row.resolvidoEm <> '' THEN datetime(row.resolvidoEm) ELSE null END,
      ch.tempoResolucaoHoras = CASE WHEN row.tempoResolucaoHoras <> '' THEN toInteger(row.tempoResolucaoHoras) ELSE null END,
      ch.satisfacao = CASE WHEN row.satisfacao <> '' THEN toInteger(row.satisfacao) ELSE null END
  MERGE (c)-[:ABRIU_CHAMADO]->(ch)
  WITH ch, row
  WHERE row.transacaoDisputadaId IS NOT NULL AND row.transacaoDisputadaId <> ''
  MATCH (t:Transacao {transacao_id: row.transacaoDisputadaId})
  MERGE (ch)-[:SOBRE_TRANSACAO]->(t)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 10) RegistroBruto — registros crus de outros sistemas, SEM link com Cliente
// (a fase 4 de resolução de identidade é quem descobre esse link)
// ============================================================
LOAD CSV WITH HEADERS FROM $baseUrl + 'registros_brutos.csv' AS row
CALL (row) {
  MERGE (r:RegistroBruto {registro_id: row.registro_id})
  SET r.nomeBruto = row.nomeBruto,
      r.cpfBruto = row.cpfBruto,
      r.telefoneBruto = row.telefoneBruto,
      r.dataNascimentoBruto = row.dataNascimentoBruto,
      r.cidadeBruto = row.cidadeBruto,
      r.canalOrigem = row.canalOrigem
} IN TRANSACTIONS OF 1000 ROWS;
