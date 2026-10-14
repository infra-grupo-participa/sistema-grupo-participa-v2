-- APLICADA em 14/10/2026 ~15:01 UTC, um índice por chamada pela Management API (/database/query, fora de transação);
-- os 3 conferidos válidos (indisvalid). Não fica em schema_migrations: concurrently não roda dentro da transação do registro.
-- 20261014160300: índices da linha do tempo para a carga repetível e para a leitura por evento/turma
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2), 14/10/2026. Depende de 20261014160200.
-- CONCURRENTLY: não trava a escrita ao vivo do webhook Hotmart em pessoas.eventos. Por isso NÃO pode rodar dentro de
--   transação: aplicar com o runner sem begin/commit (um statement por chamada), nunca com `aplica_sql.py aplicar`.
--   Se um índice ficar INVALID (queda no meio), dropar e rodar de novo.
-- O QUE FAZ:
--   eventos_fonte_unico: único em (fonte_tabela, fonte_id, tipo) quando há fonte. É o que torna a carga repetível
--     (insert ... on conflict do nothing). Uma linha de origem pode virar mais de um tipo (checkout e compra da mesma
--     transação), por isso o tipo entra na chave.
--   eventos_evento_idx: (evento_id, tipo, quando) parcial, para "todo mundo do evento X que fez Y".
--   eventos_turma_idx: (turma_id, tipo) parcial.
-- AS 5 PERGUNTAS: escala = 22 mil linhas hoje (índices nascem vazios: as colunas ainda são nulas), ~250 mil depois;
--   índice = estes; frequência = única; repetição = nenhuma; reversão = 20261014160300_reversao.sql.
-- ENSAIO: o 20261014160000_ensaio.sql cria os mesmos índices sem CONCURRENTLY dentro da transação desfeita e prova o
--   on conflict.

create unique index concurrently if not exists eventos_fonte_unico on pessoas.eventos (fonte_tabela, fonte_id, tipo) where fonte_id is not null;
create index concurrently if not exists eventos_evento_idx on pessoas.eventos (evento_id, tipo, quando) where evento_id is not null;
create index concurrently if not exists eventos_turma_idx on pessoas.eventos (turma_id, tipo) where turma_id is not null;
