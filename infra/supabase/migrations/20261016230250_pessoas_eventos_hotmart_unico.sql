-- 20261016230250: índice ÚNICO da linha do tempo da Hotmart por (transação, tipo). Conserto da classe dos achados 4 e 5 do pentest
--   (Projetos/sistema-unico/pessoa-unica/PENTEST-HOTMART-SETOR-2026-10-16.md no cérebro): corrida webhook x carga e lock de aviso.
--
-- STATUS: APLICADA em 16/10/2026: índice único 16:29:34 a 16:29:37 UTC (indisunique, indisvalid, indisready true, 2456 kB), drop do
--   índice comum 16:29:45 UTC. Branch victor-hotmart-unico. Versão gravada em schema_migrations.
-- ORDEM: este primeiro (2 statements), depois 20261016230255 (funções com on conflict).
-- CONCURRENTLY: não trava a escrita do webhook em pessoas.eventos. NÃO roda dentro de transação: um statement por chamada, nunca com
--   `aplica_sql.py aplicar`. Depois do 1º statement conferir em pg_index indisunique, indisvalid e indisready = true; se ficar INVALID
--   (nasceu uma duplicata no meio), dropar o índice, rodar a query de duplicados e tratar antes de tentar de novo.
-- PREMISSA MEDIDA (16/10/2026 ~16h20 UTC): 0 grupos repetidos de (ref_id, tipo) em ref_tipo = 'hotmart.transacao'; 57.987 linhas.
-- O QUE FAZ: 1) cria eventos_hotmart_ref_unico (mesmas colunas e predicado do eventos_hotmart_ref_idx da 230000, agora único);
--   2) apaga o eventos_hotmart_ref_idx, que vira redundante (o único atende as mesmas consultas).
-- AS 5 PERGUNTAS: escala = parcial, ~58 mil linhas, cresce com as vendas; índice = este; frequência = única; repetição = nenhuma;
--   reversão = 20261016230250_reversao.sql (recria o comum e apaga o único; antes, reverter a 230255).

create unique index concurrently if not exists eventos_hotmart_ref_unico on pessoas.eventos (ref_id, tipo) where ref_tipo = 'hotmart.transacao';

drop index concurrently if exists pessoas.eventos_hotmart_ref_idx;
