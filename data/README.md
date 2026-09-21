# Fase 2 — CSVs fake

Gerados por [`generate_dados.py`](generate_dados.py) (sem dependências externas, seed fixa = 42,
reproduzível). Para regenerar:

```bash
python3 generate_dados.py
```

Todos os arquivos ficam prontos para `LOAD CSV` direto (fase 3), com os nomes de coluna já
alinhados às propriedades do [modelo de dados](../docs/00-modelo-dados.md).

## Orçamento de nós: ~195.000 (teto do AuraDB Free é 200.000)

O script calcula primeiro o overhead fixo (Cliente + identidades já deduplicadas pelos anéis de
fraude + Localizacao + Produto/TipoProduto) e só depois distribui o orçamento restante entre
Acesso/AcaoApp/Transacao/Chamado por proporção fixa — o total nunca estoura, mesmo mudando
`N_CLIENTES` no topo do script.

| Arquivo | Linhas | Colunas | Vira no grafo |
|---|---|---|---|
| `clientes.csv` | 1.500 | `cliente_id, nome, cpf, dataNascimento, cidade, estado, segmento, dataCadastro` | `(:Cliente)` |
| `localizacoes.csv` | 1.500 | `cliente_id, location_id, cidade, estado, latitude, longitude` | `(:Cliente)-[:LOCALIZADO_EM]->(:Localizacao)` — `location_id` repete por cidade (10 cidades), então o `MERGE` da fase 3 dedupe pra ~10 nós |
| `rgs.csv` | 1.500 | `cliente_id, rg_id, numero, desde` | `(:Cliente)-[:POSSUI_RG {desde}]->(:RG)` |
| `emails.csv` | 1.500 | `cliente_id, email_id, endereco, dominio, desde` | `(:Cliente)-[:POSSUI_EMAIL {desde}]->(:Email)` |
| `telefones.csv` | 1.500 | `cliente_id, telefone_id, numero, ddd, desde` | `(:Cliente)-[:POSSUI_TELEFONE {desde}]->(:Telefone)` |
| `dispositivos.csv` | 1.500 | `cliente_id, device_id, modelo, sistemaOperacional, primeiroAcesso, ultimoAcesso` | `(:Cliente)-[:USA_DISPOSITIVO {primeiroAcesso, ultimoAcesso}]->(:Dispositivo)` |
| `transacoes.csv` | ~24.400 | `transacao_id, clienteOrigemId, clienteDestinoId, valor, data, tipo` | `(:Cliente)-[:ENVIOU]->(:Transacao)-[:PARA]->(:Cliente)` |
| `tipos_produto.csv` | 5 | `tipo_id, nome, ehContrato` | `(:TipoProduto)` |
| `produtos.csv` | 10 | `produto_id, nome, categoria, tipo_id` | `(:Produto)-[:DO_TIPO]->(:TipoProduto)` (`tipo_id` só serve pra montar o relacionamento) |
| `contratacoes.csv` | ~3.000 | `cliente_id, produto_id, vezes, valorTotal, ultimoUso` | `(:Cliente)-[:CONTRATOU {vezes, valorTotal, ultimoUso}]->(:Produto)` |
| `acessos.csv` | ~52.500 | `acesso_id, cliente_id, dataHora, canal, sucesso, duracaoSegundos` | `(:Cliente)-[:ACESSOU]->(:Acesso)` |
| `acoes_app.csv` | ~107.000 | `acao_id, acesso_id, tipo, dataHora, produto_id` | `(:Acesso)-[:REALIZOU_ACAO]->(:AcaoApp)`, e `(:AcaoApp)-[:SOBRE_PRODUTO]->(:Produto)` quando `produto_id` não é vazio |
| `chamados.csv` | ~3.750 | `chamado_id, cliente_id, canal, assunto, severidade, status, abertoEm, resolvidoEm, tempoResolucaoHoras, satisfacao, transacaoDisputadaId` | `(:Cliente)-[:ABRIU_CHAMADO]->(:Chamado)`, e `(:Chamado)-[:SOBRE_TRANSACAO]->(:Transacao)` quando `transacaoDisputadaId` não é vazio |
| `registros_brutos.csv` | 115 | `registro_id, nomeBruto, cpfBruto, telefoneBruto, dataNascimentoBruto, cidadeBruto, canalOrigem` | `(:RegistroBruto)` — **sem** link com `Cliente` na carga (isso é o que a resolução de identidade, fase 4, descobre) |

**Total real após dedupe de identidades: 195.000 nós** (verificado por recontagem independente).
Breakdown completo em [00-modelo-dados.md § Orçamento de nós](../docs/00-modelo-dados.md#orçamento-de-nós-dimensionamento-pro-free-tier).

`(:Cliente)-[:SIMILAR_A]->(:Cliente)`, `(:Produto)-[:COMPRADO_JUNTO]->(:Produto)`,
`(evento)-[:PROXIMO_EVENTO]->(evento)` (a jornada), `(:TipoAcao)` + `(:Cliente)-[:REALIZOU_TIPO]->(:TipoAcao)`
(segmentação) e `(:RegistroBruto)-[:RESOLVIDO_PARA|CANDIDATO_MESMO_QUE]->(:Cliente)` (resolução de
identidade) **não** têm CSV — são calculados na fase 3/4 (GDS e agregação/`UNION`/blocking em Cypher).

## Padrões injetados de propósito

- **Anéis de fraude** (18 no total, 3–6 clientes cada): metade reaproveita um `RG`/`Email`/
  `Telefone` entre os membros (fraude de identidade), a outra metade reaproveita o mesmo
  `Dispositivo` (account takeover / credential stuffing).
- **Contas-laranja** (6 clientes): recebem ~20% de todas as transações Pix, com valores mais altos
  (R$ 1.500–15.000) — pensado pra aparecer destacado em PageRank sobre o grafo de Pix.
- **Perfis de contratação** (5 perfis): 75% dos clientes tendem a contratar produtos do mesmo
  perfil — dá sinal real pra Node Similarity / FastRP+KNN, e pra emergirem pares "comprados
  juntos".
- **Peso de atividade por cliente**: cada cliente recebe um peso (a maioria perto de 1.0, alguns
  "power users", alguns quase inativos) usado pra distribuir acessos/transações/chamados de forma
  correlacionada — clientes ativos em um canal tendem a ser ativos nos outros, o que torna a
  jornada (próxima seção) mais realista.
- **Acessos com falha** (~5% do total): simulam tentativa de login malsucedida — nenhuma `AcaoApp`
  é gerada pra um acesso malsucedido, mas o evento em si fica no grafo como sinal de account
  takeover (login falho → login com sucesso de outro dispositivo → Pix de alto valor é o padrão
  clássico do artigo de fraude).
- **Chamados de "Contestação de transação"** (~430 chamados): sempre linkados a uma transação real
  em que o próprio cliente foi a origem — dá pra rastrear "cliente contestou o quê" na jornada.
- **Personas comportamentais** (4 personas: `digital_nativo`, `tradicional`, `investidor_pesquisador`,
  `operacional_puro`): cada cliente tem uma, e ela vies a o canal de `Acesso`, o canal de `Chamado` e
  o tipo de `AcaoApp` — sinal real pra segmentação (Node Similarity/Louvain), diferente do perfil de
  *contratação* acima (uma é comportamento de uso, a outra é o que o cliente compra).
- **Registros brutos** (115: 90 duplicados + 25 negativos): os 90 duplicados são clientes reais
  capturados de novo com ruído — nome abreviado/com typo, CPF mascarado ou sem pontuação, telefone
  sem DDD ou com 1 dígito trocado, às vezes data de nascimento com dia/mês invertidos. Os 25
  negativos são pessoas diferentes de propósito, pra testar se o algoritmo de resolução de
  identidade não erra por excesso de zelo.

## Jornada do cliente

`Acesso`, `Transacao` e `Chamado` têm timestamp (`dataHora`, `data`, `abertoEm`). A fase 3 encadeia
os três por cliente, em ordem cronológica, com `PROXIMO_EVENTO` — ver
[00-modelo-dados.md § Jornada do cliente](../docs/00-modelo-dados.md#jornada-do-cliente) pra a
consulta completa.

## `gabarito.json` — não carregar no grafo

Guarda a verdade injetada (quais clientes formam cada anel, quais são as contas-laranja, qual o
perfil de cada cliente) só para o palestrante validar os resultados de GDS durante o ensaio.
Fica fora do carregamento (fase 3) e, quando os agentes da fase 5 forem configurados, o padrão do
[aura-agent](https://github.com/elizarp/neo4j-agente-fraude/tree/main/aura-agent) já bloqueia a
leitura de propriedades tipo "gabarito" — mesma lógica aqui: o agente deve *chegar* na resposta via
GDS, não ler a resposta pronta.
