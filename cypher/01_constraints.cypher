// Fase 3.1 — Constraints (rodar ANTES de qualquer LOAD CSV)
// Idempotente: pode rodar de novo sem erro.

CREATE CONSTRAINT cliente_id IF NOT EXISTS
FOR (c:Cliente) REQUIRE c.cliente_id IS UNIQUE;

CREATE CONSTRAINT rg_id IF NOT EXISTS
FOR (r:RG) REQUIRE r.rg_id IS UNIQUE;

CREATE CONSTRAINT email_id IF NOT EXISTS
FOR (e:Email) REQUIRE e.email_id IS UNIQUE;

CREATE CONSTRAINT telefone_id IF NOT EXISTS
FOR (t:Telefone) REQUIRE t.telefone_id IS UNIQUE;

CREATE CONSTRAINT device_id IF NOT EXISTS
FOR (d:Dispositivo) REQUIRE d.device_id IS UNIQUE;

CREATE CONSTRAINT location_id IF NOT EXISTS
FOR (l:Localizacao) REQUIRE l.location_id IS UNIQUE;

CREATE CONSTRAINT transacao_id IF NOT EXISTS
FOR (t:Transacao) REQUIRE t.transacao_id IS UNIQUE;

CREATE CONSTRAINT produto_id IF NOT EXISTS
FOR (p:Produto) REQUIRE p.produto_id IS UNIQUE;

CREATE CONSTRAINT tipo_produto_id IF NOT EXISTS
FOR (t:TipoProduto) REQUIRE t.tipo_id IS UNIQUE;

CREATE CONSTRAINT chamado_id IF NOT EXISTS
FOR (c:Chamado) REQUIRE c.chamado_id IS UNIQUE;

CREATE CONSTRAINT acesso_id IF NOT EXISTS
FOR (a:Acesso) REQUIRE a.acesso_id IS UNIQUE;

CREATE CONSTRAINT acao_id IF NOT EXISTS
FOR (a:AcaoApp) REQUIRE a.acao_id IS UNIQUE;

CREATE CONSTRAINT registro_bruto_id IF NOT EXISTS
FOR (r:RegistroBruto) REQUIRE r.registro_id IS UNIQUE;

CREATE CONSTRAINT tipo_acao_nome IF NOT EXISTS
FOR (t:TipoAcao) REQUIRE t.nome IS UNIQUE;

// Índices auxiliares — usados pela consulta de jornada (fase 3.3) e pelas
// projeções de GDS (fase 4). Não são chaves de unicidade, só aceleram ORDER BY.
CREATE INDEX transacao_data IF NOT EXISTS FOR (t:Transacao) ON (t.data);
CREATE INDEX acesso_dataHora IF NOT EXISTS FOR (a:Acesso) ON (a.dataHora);
CREATE INDEX chamado_abertoEm IF NOT EXISTS FOR (c:Chamado) ON (c.abertoEm);
