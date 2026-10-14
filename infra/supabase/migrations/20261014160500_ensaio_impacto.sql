-- Ensaio de IMPACTO de 20261014160500 (HT21/HT22 e ATM de setembro) e 20261014160600 (HT20 começa em 01/01) nos
-- leitores do financeiro, numa transação DESFEITA. Sem DDL: aplica só as mudanças de linha de fin.eventos (sem a coluna
-- chave, que é da 160000), para não segurar lock exclusivo. Lock só nas linhas 57 e 59 durante ~30 s.
-- Mede public.fn_fin_funis() (com a identidade de um perfil da equipe com acesso ao financeiro, via request.jwt.claims)
-- e fin.trajetoria_nucleo() para os compradores de HT de jan a mai/2026, em 3 fotos: A (hoje), B (depois da 160500),
-- C (depois da 160600). Saída só com nomes de evento e números agregados.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
create temp table _z_out (em serial, passo text, linha text);
create temp table _z_em as select distinct lower(btrim(t.comprador_email)) e from fin.hotmart_transacoes t join fin.produtos p using (produto_id)
  where p.familia in ('HT', 'HM') and t.pedido_em >= '2026-01-01' and t.pedido_em < '2026-06-01' and t.comprador_email is not null order by 1 limit 200;
create temp table _z_fa as select 'A'::text foto, f.evento_id, f.nome, f.inicio, f.ingresso_de, f.venda_ate, f.ingressos, f.compradores, f.oferta_vendas, f.bruto, f.liquido
  from public.fn_fin_funis() f where f.categoria in ('holding_total', 'seminario_elaine');
create temp table _z_ta as select 'A'::text foto, t.transacao, t.evento_id, t.evento from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_em)) t;
insert into pg_temp._z_out(passo, linha) select '01 foto A: funis HT+Elaine / linhas de trajetória (200 compradores)', (select count(*) from pg_temp._z_fa) || ' / ' || (select count(*) from pg_temp._z_ta);

-- ===== 160500 (sem a coluna chave) =====
update fin.eventos set nome = 'Holding Total (HT22)' where id = 59;
insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, automatico) values
  ('Holding Total (HT21)', 'holding_total', 'educacao', date '2026-03-13', date '2026-04-05', date '2026-04-05', 'HT21', 'ensaio', false),
  ('Seminário ATM (Dra. Elaine, set/2026)', 'seminario_elaine', 'escritorio', date '2026-09-09', date '2026-09-11', date '2026-09-11', null, 'ensaio', false);
insert into pg_temp._z_fa select 'B', f.evento_id, f.nome, f.inicio, f.ingresso_de, f.venda_ate, f.ingressos, f.compradores, f.oferta_vendas, f.bruto, f.liquido
  from public.fn_fin_funis() f where f.categoria in ('holding_total', 'seminario_elaine');
insert into pg_temp._z_ta select 'B', t.transacao, t.evento_id, t.evento from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_em)) t;

-- ===== 160600 =====
update fin.eventos set inicio = date '2026-01-01' where id = 57;
insert into pg_temp._z_fa select 'C', f.evento_id, f.nome, f.inicio, f.ingresso_de, f.venda_ate, f.ingressos, f.compradores, f.oferta_vendas, f.bruto, f.liquido
  from public.fn_fin_funis() f where f.categoria in ('holding_total', 'seminario_elaine');
insert into pg_temp._z_ta select 'C', t.transacao, t.evento_id, t.evento from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_em)) t;

-- ===== diferenças =====
insert into pg_temp._z_out(passo, linha)
select '10 funis A->B: ' || coalesce(b.nome, a.nome),
       coalesce('janela ' || a.ingresso_de || ' -> ' || b.ingresso_de || '; ', '') ||
       'ingressos ' || coalesce(a.ingressos::text, 'novo') || ' -> ' || coalesce(b.ingressos::text, '-') ||
       '; compradores ' || coalesce(a.compradores::text, 'novo') || ' -> ' || coalesce(b.compradores::text, '-') ||
       '; bruto ' || coalesce(round(a.bruto)::text, 'novo') || ' -> ' || coalesce(round(b.bruto)::text, '-')
  from (select * from pg_temp._z_fa where foto = 'A') a
  full join (select * from pg_temp._z_fa where foto = 'B') b using (evento_id)
 where row(a.ingresso_de, a.ingressos, a.compradores, a.oferta_vendas, a.bruto, a.liquido) is distinct from row(b.ingresso_de, b.ingressos, b.compradores, b.oferta_vendas, b.bruto, b.liquido);
insert into pg_temp._z_out(passo, linha)
select '20 funis B->C: ' || coalesce(c.nome, b.nome),
       'início ' || b.inicio || ' -> ' || c.inicio || '; janela ' || coalesce(b.ingresso_de::text, '-') || ' -> ' || coalesce(c.ingresso_de::text, '-') ||
       '; ingressos ' || coalesce(b.ingressos::text, '-') || ' -> ' || coalesce(c.ingressos::text, '-') ||
       '; compradores ' || coalesce(b.compradores::text, '-') || ' -> ' || coalesce(c.compradores::text, '-') ||
       '; bruto ' || coalesce(round(b.bruto)::text, '-') || ' -> ' || coalesce(round(c.bruto)::text, '-')
  from (select * from pg_temp._z_fa where foto = 'B') b
  full join (select * from pg_temp._z_fa where foto = 'C') c using (evento_id)
 where row(b.inicio, b.ingresso_de, b.ingressos, b.compradores, b.oferta_vendas, b.bruto, b.liquido) is distinct from row(c.inicio, c.ingresso_de, c.ingressos, c.compradores, c.oferta_vendas, c.bruto, c.liquido);
insert into pg_temp._z_out(passo, linha)
select '30 trajetória A->B: ' || coalesce(a.evento, '(sem evento)') || ' -> ' || coalesce(b.evento, '(sem evento)'), count(*) || ' transações'
  from (select * from pg_temp._z_ta where foto = 'A') a join (select * from pg_temp._z_ta where foto = 'B') b using (transacao)
 where a.evento_id is distinct from b.evento_id group by a.evento, b.evento;
insert into pg_temp._z_out(passo, linha)
select '40 trajetória B->C: ' || coalesce(b.evento, '(sem evento)') || ' -> ' || coalesce(c.evento, '(sem evento)'), count(*) || ' transações'
  from (select * from pg_temp._z_ta where foto = 'B') b join (select * from pg_temp._z_ta where foto = 'C') c using (transacao)
 where b.evento_id is distinct from c.evento_id group by b.evento, c.evento;
insert into pg_temp._z_out(passo, linha) select '99 fim: fotos (A/B/C) de funis', string_agg(foto || '=' || n, ' ') from (select foto, count(*) n from pg_temp._z_fa group by 1 order by 1) x;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
