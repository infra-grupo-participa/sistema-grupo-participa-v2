-- 20261016230000: índice da linha do tempo para achar o evento Hotmart pela transação (carga repetível e webhook idempotente)
--
-- STATUS: APLICADA em 16/10/2026 11:31 UTC pelo Victor (sessão principal), depois do pentest APROVADO; versão 20261016230000 em schema_migrations. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Pacote com 230100, 230200, 230300 e 230400.
-- ORDEM DE APLICAÇÃO: este primeiro. As funções da 230100 consultam por ref_id e sem este índice cada consulta varre a tabela inteira.
-- CONCURRENTLY: não trava a escrita ao vivo do webhook em pessoas.eventos. NÃO pode rodar dentro de transação: aplicar com o runner
--   sem begin/commit (um statement por chamada), nunca com `aplica_sql.py aplicar`. Se ficar INVALID, dropar e rodar de novo.
-- POR QUE: o plano medido em 16/10 de `select min(id) from pessoas.eventos where ref_tipo='hotmart.transacao' and ref_id=... and tipo=...
--   and fonte_id is null` (a consulta que a carga faz POR TRANSAÇÃO para reivindicar a linha do webhook) é Parallel Seq Scan nas
--   641.635 linhas (195 MB), 398 ms. Com 56 mil transações por carregar isso é a maior parte do tempo da carga. A nova consulta do
--   webhook (230100) faz a mesma busca por transação.
-- O QUE FAZ: um índice parcial (ref_id, tipo) só nas linhas ref_tipo = 'hotmart.transacao' (~7,5 mil hoje, ~65 mil depois da carga).
-- AS 5 PERGUNTAS: escala = parcial, cresce com as vendas (não com os 641 mil eventos); índice = este; frequência = única;
--   repetição = nenhuma; reversão = 20261016230000_reversao.sql (drop index concurrently).

create index concurrently if not exists eventos_hotmart_ref_idx on pessoas.eventos (ref_id, tipo) where ref_tipo = 'hotmart.transacao';
