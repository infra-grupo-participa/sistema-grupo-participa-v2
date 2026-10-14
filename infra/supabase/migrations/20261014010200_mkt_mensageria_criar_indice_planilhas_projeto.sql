-- 20261014010200: índice na FK mkt_mensageria.planilhas.projeto_id (auditoria pelo guia do JP, item 11, parte nossa)
--
-- POR QUE: toda FK tem índice (padrão). A FK planilhas.projeto_id -> mkt.projetos(id) ON DELETE RESTRICT não tinha.
-- O QUE FAZ: create index if not exists. A tabela tem 1 linha: o índice não muda nenhum plano hoje (o guia lembra que em
--   tabela pequena o seq scan vence); serve para a checagem da FK quando um projeto for apagado e para o futuro. Sem
--   CONCURRENTLY porque o runner embrulha em transação e a tabela tem 1 linha (lock instantâneo).
-- AS 5 PERGUNTAS: escala = 1 linha; índice = este; frequência = única; repetição = nenhuma; reversão = 20261014010200_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create index if not exists planilhas_projeto_id_idx on mkt_mensageria.planilhas (projeto_id);
