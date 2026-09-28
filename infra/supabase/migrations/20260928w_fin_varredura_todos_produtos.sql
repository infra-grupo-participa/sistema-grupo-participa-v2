-- 20260928w — Varredura de TODOS os produtos da Hotmart (27/09/2026). O João: "a gente não pode deixar nada fora do
-- sistema… toda compra que cair, todo webhook". O catálogo (20260928v) mostrou 91 produtos; o espelho só lia 13.
-- Entre os de fora: 9 produtos de Serviço Diamante criados em 01/2026 (um por serviço + Combo) e os do seminário
-- (Sessão de Viabilidade, Croqui Estrutural).
-- 1) Todo produto do catálogo entra em fin.produtos como 'A_CLASSIFICAR' (invisível para telas e grafo) — sem isso a
--    venda cairia como família 'OUTRO' e ENTRARIA no grafo de identidade sem revisão.
-- 2) A fila ganha janelas com produto_id '*': a Edge Function chama sales/history SEM filtro de produto (uma
--    passada pela conta inteira, 2017→hoje), e cada venda leva o produto do próprio item.
-- Classificar depois = update fin.produtos set familia = … (e medir a junção de identidade antes, como no 446345).
insert into fin.produtos (produto_id, nome, familia, papel, sincroniza, nota)
select c.produto_id, c.nome, 'A_CLASSIFICAR', null, false, 'Do catálogo da Hotmart; aguarda classificação.'
  from fin.hotmart_catalogo c
on conflict (produto_id) do nothing;

insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
select '*', g::date, least(g::date + 59, (now() at time zone 'America/Sao_Paulo')::date), 'backfill'
  from generate_series(date '2017-01-01', (now() at time zone 'America/Sao_Paulo')::date, interval '60 days') g
on conflict do nothing;
