// Fase 3.2 — Carga via LOAD CSV (idempotente, com MERGE)
// Rodar DEPOIS de 01_constraints.cypher, na ordem dos blocos abaixo
// (algumas cargas dependem de nós criados no bloco anterior).
//
// Aponta direto pro raw do repositório público do workshop — não precisa de
// :param nem de setup extra, só colar e rodar:
//   https://github.com/elizarp/tdc-sp-2026-neo4j
//
// Cada bloco usa `CALL (row) { ... } IN TRANSACTIONS OF 1000 ROWS` (Cypher 25)
// pra não estourar memória de transação em arquivos grandes (acessos.csv e
// acoes_app.csv passam de 50k/100k linhas).

// ============================================================
// 1) Cliente — cadastro completo num único arquivo: dados pessoais,
// localização e as identidades soltas (RG/e-mail/telefone) que viram anéis de
// fraude quando repetidas entre clientes. clientes.csv é a fonte única do
// cadastro (não tem mais rgs.csv/emails.csv/telefones.csv/localizacoes.csv
// separados) — dataCriacao é quando o cadastro nasceu.
//
// Um cliente pode ter MAIS DE UMA LINHA em clientes.csv (uma por alteração
// cadastral — troca de RG/e-mail/telefone ao longo do tempo). As linhas vêm
// em ordem cronológica por cliente, então:
//   - As propriedades do nó Cliente usam SET normal — a última linha
//     processada "vence", refletindo o estado atual.
//   - Os relacionamentos de identidade (POSSUI_RG/EMAIL/TELEFONE) usam
//     `ON CREATE SET` — a data "desde" só é gravada na 1ª vez que aquele par
//     (cliente, identidade) aparece. Se o campo mudou entre as linhas, é um
//     nó de identidade NOVO (o antigo continua no grafo, ligado ao cliente,
//     como histórico); se não mudou, o MERGE só reencontra o mesmo
//     relacionamento e não sobrescreve a data original.
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/clientes.csv' AS row
CALL (row) {
  MERGE (c:Cliente {cliente_id: row.cliente_id})
  SET c.nome = row.nome,
      c.cpf = row.cpf,
      c.dataNascimento = date(row.dataNascimento),
      c.cidade = row.cidade,
      c.estado = row.estado,
      c.segmento = row.segmento,
      c.dataCriacao = date(row.dataCriacao)

  MERGE (l:Localizacao {location_id: 'LOC_' + toUpper(replace(row.cidade, ' ', '_'))})
  SET l.cidade = row.cidade,
      l.estado = row.estado,
      l.latitude = toFloat(row.latitude),
      l.longitude = toFloat(row.longitude)
  MERGE (c)-[:LOCALIZADO_EM]->(l)

  MERGE (rg:RG {rg_id: row.rg_id})
  SET rg.numero = row.rg_numero
  MERGE (c)-[relRg:POSSUI_RG]->(rg)
  ON CREATE SET relRg.desde = date(row.dataAlteracao)

  MERGE (email:Email {email_id: row.email_id})
  SET email.endereco = row.email_endereco,
      email.dominio = row.email_dominio
  MERGE (c)-[relEmail:POSSUI_EMAIL]->(email)
  ON CREATE SET relEmail.desde = date(row.dataAlteracao)

  MERGE (tel:Telefone {telefone_id: row.telefone_id})
  SET tel.numero = row.telefone_numero,
      tel.ddd = row.telefone_ddd
  MERGE (c)-[relTel:POSSUI_TELEFONE]->(tel)
  ON CREATE SET relTel.desde = date(row.dataAlteracao)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 2) Dispositivo — continua em arquivo próprio: é dado técnico/de uso, não
// de cadastro (o cliente não "declara" um dispositivo, ele só usa).
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/dispositivos.csv' AS row
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
// 3) TipoProduto e Produto (+ DO_TIPO)
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/tipos_produto.csv' AS row
CALL (row) {
  MERGE (t:TipoProduto {tipo_id: row.tipo_id})
  SET t.nome = row.nome,
      t.ehContrato = toBoolean(row.ehContrato)
} IN TRANSACTIONS OF 100 ROWS;

LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/produtos.csv' AS row
CALL (row) {
  MERGE (p:Produto {produto_id: row.produto_id})
  SET p.nome = row.nome,
      p.categoria = row.categoria
  WITH p, row
  MATCH (t:TipoProduto {tipo_id: row.tipo_id})
  MERGE (p)-[:DO_TIPO]->(t)
} IN TRANSACTIONS OF 100 ROWS;

// ============================================================
// 4) Transacao (+ ENVIOU, PARA) — grafo de Pix entre clientes
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/transacoes.csv' AS row
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
// 5) Contratacoes (+ CONTRATOU)
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/contratacoes.csv' AS row
CALL (row) {
  MATCH (c:Cliente {cliente_id: row.cliente_id})
  MATCH (p:Produto {produto_id: row.produto_id})
  MERGE (c)-[rel:CONTRATOU]->(p)
  SET rel.vezes = toInteger(row.vezes),
      rel.valorTotal = toFloat(row.valorTotal),
      rel.ultimoUso = date(row.ultimoUso)
} IN TRANSACTIONS OF 1000 ROWS;

// ============================================================
// 6) Acesso (+ ACESSOU) — logins/sessões no app
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/acessos.csv' AS row
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
// 7) AcaoApp (+ REALIZOU_ACAO, SOBRE_PRODUTO) — clickstream dentro da sessão
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/acoes_app.csv' AS row
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
// 8) Chamado (+ ABRIU_CHAMADO, SOBRE_TRANSACAO) — ocorrências multicanal
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/chamados.csv' AS row
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
// 9) RegistroBruto — registros crus de outros sistemas, SEM link com Cliente
// (a fase 4 de resolução de identidade é quem descobre esse link)
// ============================================================
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/elizarp/tdc-sp-2026-neo4j/main/data/registros_brutos.csv' AS row
CALL (row) {
  MERGE (r:RegistroBruto {registro_id: row.registro_id})
  SET r.nomeBruto = row.nomeBruto,
      r.cpfBruto = row.cpfBruto,
      r.telefoneBruto = row.telefoneBruto,
      r.dataNascimentoBruto = row.dataNascimentoBruto,
      r.cidadeBruto = row.cidadeBruto,
      r.canalOrigem = row.canalOrigem
} IN TRANSACTIONS OF 1000 ROWS;
