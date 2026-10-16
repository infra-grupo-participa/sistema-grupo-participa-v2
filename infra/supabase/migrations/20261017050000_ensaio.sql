-- Ensaio de 20261017050000_dados_ligar_ofertas_black_thb.sql numa transação DESFEITA (rollback), sobre produção.
-- Sem dado pessoal na saída: e-mails fictícios @example.invalid, transações ZZ-*, só agregados.
-- Prova: com vendas FICTÍCIAS nas duas ofertas (e casos que NÃO devem contar), antes da migration os cards de venda ficam
-- "aguardando oferta" (nulo); depois, Vendas, Receita e ROAS contam as duas ofertas (inclusive uma venda que só existe no webhook);
-- sem a oferta extra o upgrade deixa de contar (a extra é o que traz); marcar o comprador como teste tira a venda do card;
-- as outras chaves não mudam; a reversão devolve o estado; rodar duas vezes aborta pela guarda.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', case when p_id is null then '{"role":"anon"}' else jsonb_build_object('sub', p_id, 'role', 'authenticated')::text end, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 900);
exception when others then return sqlstate || ' ' || left(sqlerrm, 300);
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated, anon;
-- registra uma linha como o papel pedido (o papel volta ao que era)
create function pg_temp.foto(p_rotulo text, p_id uuid, p_sql text) returns void language plpgsql as $t$
begin
  insert into pg_temp._z_out(passo, linha) values (p_rotulo, pg_temp.tenta(p_id, p_sql));
end $t$;
grant execute on function pg_temp.foto(text, uuid, text) to authenticated, anon;

create temp table _ch as select chave from dados.dashboards where modelo in ('acao-black', 'seminario-atm') and chave <> 'black-thb-2026-10' and ativo;
grant select on pg_temp._ch to authenticated;
set local session_replication_role = replica;   -- sem o gatilho do CRM nas linhas fictícias (tudo é desfeito no rollback)

insert into pg_temp._z_out(passo, linha) select '00 cadastro antes', jsonb_build_object('oferta_codigo', oferta_codigo, 'ofertas_extra', ofertas_extra, 'vendas_desde', vendas_desde, 'conta', conta_hotmart)::text from dados.dashboards where chave = 'black-thb-2026-10';
insert into pg_temp._z_out(passo, linha) select '00 transacoes reais nas 2 ofertas (fin / webhook)', (select count(*) from fin.hotmart_transacoes where oferta_codigo in ('nv5f10zq','wftji6dl'))::text || ' / ' || (select count(*) from cs.hotmart_eventos where payload #>> '{data,purchase,offer,code}' in ('nv5f10zq','wftji6dl'))::text;
set local role authenticated;
select pg_temp.foto('10 ANTES (oferta nula, sem venda) cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('10 ANTES (oferta nula, sem venda) serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('10 ANTES (oferta nula, sem venda) controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- vendas FICTÍCIAS: contam 3 (a, b, webhook); NÃO contam d (estornada), e (pedido antes de vendas_desde), f (2a recorrência), g (outra oferta)
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-A-NV', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 1, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.a@example.invalid', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-B-WF', 'ZZ-PRODUTO', 'wftji6dl', 'COMPLETE', 1, 'BRL', 10000, 10000, 10000*0.9, now() - interval '2 minutes', now(), 'zz.b@example.invalid', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-D-REEMB', 'ZZ-PRODUTO', 'nv5f10zq', 'REFUNDED', 1, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.d@example.invalid', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-E-ANTES', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 1, 'BRL', 6000, 6000, 6000*0.9, timestamptz '2026-10-13 12:00+00', timestamptz '2026-10-13 12:05+00', 'zz.e@example.invalid', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-F-REC2', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 2, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.f@example.invalid', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, bruto_json, conta)
  values ('ZZ-G-OUTRA', 'ZZ-PRODUTO', 'zzzzzzzz', 'APPROVED', 1, 'BRL', 777, 777, 777*0.9, now() - interval '2 minutes', now(), 'zz.g@example.invalid', '{}'::jsonb, 'academy');

-- venda que só o webhook conhece (o sync ainda não trouxe), na oferta EXTRA
insert into cs.hotmart_eventos (evento, transacao, email, payload) values ('PURCHASE_APPROVED', 'ZZ-C-WEBHOOK', 'zz.c@example.invalid', jsonb_build_object('data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'zz.c@example.invalid', 'name', 'Zz Webhook'),
  'purchase', jsonb_build_object('offer', jsonb_build_object('code', 'wftji6dl'), 'price', jsonb_build_object('value', 10000, 'currency_value', 'BRL'), 'status', 'APPROVED',
     'order_date', (extract(epoch from now() - interval '1 minute') * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint, 'recurrence_number', 1),
  'commissions', jsonb_build_array(jsonb_build_object('value', 9000, 'source', 'PRODUCER')))));
insert into pg_temp._z_out(passo, linha) select '11 vendas fictícias inseridas (fin / webhook)', (select count(*) from fin.hotmart_transacoes where transacao like 'ZZ-%')::text || ' / ' || (select count(*) from cs.hotmart_eventos where transacao like 'ZZ-%')::text;
-- investimento FICTÍCIO: R$ 1.300 de custo num disparo da ação (hoje o custo é 0, e por regra da RPC o ROAS só aparece com investimento > 0)
update mkt_mensageria.disparos set custo_centavos = 130000 where id = (select min(id) from mkt_mensageria.disparos where projeto_id = (select projeto_id from dados.dashboards where chave = 'black-thb-2026-10') and arquivado_em is null);
set local role authenticated;
select pg_temp.foto('12 ANTES da migration, COM vendas (esperado: cards de venda nulos = aguardando oferta) cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('12 ANTES da migration, COM vendas (esperado: cards de venda nulos = aguardando oferta) serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('12 ANTES da migration, COM vendas (esperado: cards de venda nulos = aguardando oferta) controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- tempo antes (explain analyze da RPC inteira, 2x)
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_resumo(''black-thb-2026-10'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared hit)' and r."QUERY PLAN" !~ '^\s{6,}' then
        insert into pg_temp._z_out (passo, linha) values ('13 explain ANTES #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- ===== corpo da migration, sem begin/commit =====
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
declare r dados.dashboards;
begin
  select * into r from dados.dashboards where chave = 'black-thb-2026-10';
  if not found then
    raise exception '20261017050000: dashboard black-thb-2026-10 não existe';
  end if;
  if r.modelo is distinct from 'acao-black' or r.conta_hotmart is distinct from 'academy' or not r.ativo then
    raise exception '20261017050000: black-thb-2026-10 não é acao-black ativo da conta academy (modelo %, conta %, ativo %)', r.modelo, r.conta_hotmart, r.ativo;
  end if;
  if r.oferta_codigo is not null or coalesce(cardinality(r.ofertas_extra), 0) <> 0 then
    raise exception '20261017050000: black-thb-2026-10 já tem oferta (principal %, extras %); revisar antes de sobrescrever', r.oferta_codigo, r.ofertas_extra;
  end if;
  -- uma oferta não pode ser de dois dashboards da mesma conta: dados.transacoes acha o dashboard pela oferta principal
  if exists (select 1 from dados.dashboards x
              where x.chave <> r.chave and x.conta_hotmart = r.conta_hotmart
                and (x.oferta_codigo in ('nv5f10zq', 'wftji6dl') or x.ofertas_extra && array['nv5f10zq', 'wftji6dl'])) then
    raise exception '20261017050000: nv5f10zq ou wftji6dl já pertence a outro dashboard da conta academy';
  end if;
  -- premissa de que isto basta: dados.transacoes lê oferta principal + ofertas_extra (corpo de 20261007ma/20261013av)
  if to_regprocedure('dados.transacoes(text,text)') is null
     or (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) <> 'efbd212fc50a114fa307b4681454e1a9' then
    raise exception '20261017050000: dados.transacoes mudou desde a leitura de 16/10/2026 (md5 do corpo diferente); reconferir que ela ainda soma ofertas_extra';
  end if;
end
$g$;

update dados.dashboards
   set oferta_codigo = 'nv5f10zq', ofertas_extra = array['wftji6dl']
 where chave = 'black-thb-2026-10' and oferta_codigo is null and coalesce(cardinality(ofertas_extra), 0) = 0;

do $v$
begin
  if not exists (select 1 from dados.dashboards
                  where chave = 'black-thb-2026-10' and oferta_codigo = 'nv5f10zq' and ofertas_extra = array['wftji6dl']) then
    raise exception '20261017050000: a linha de black-thb-2026-10 não ficou com as duas ofertas';
  end if;
end
$v$;

insert into pg_temp._z_out(passo, linha) select '20 cadastro depois', jsonb_build_object('oferta_codigo', oferta_codigo, 'ofertas_extra', ofertas_extra)::text from dados.dashboards where chave = 'black-thb-2026-10';
set local role authenticated;
select pg_temp.foto('21 DEPOIS da migration (esperado: vendas 3, receita 26000, compradores 3, roas 20.00 (26000 / 1300), roas_liquido 18.00) cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('21 DEPOIS da migration (esperado: vendas 3, receita 26000, compradores 3, roas 20.00 (26000 / 1300), roas_liquido 18.00) serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('21 DEPOIS da migration (esperado: vendas 3, receita 26000, compradores 3, roas 20.00 (26000 / 1300), roas_liquido 18.00) controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_resumo(''black-thb-2026-10'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared hit)' and r."QUERY PLAN" !~ '^\s{6,}' then
        insert into pg_temp._z_out (passo, linha) values ('22 explain DEPOIS #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);
-- conferência cruzada: a mesma soma direto das vendas do dashboard (dados.atm_vendas), sem passar pelo resumo
insert into pg_temp._z_out(passo, linha) select '23 dados.atm_vendas direto (esperado 3 vendas, 26000)', count(*)::text || ' / ' || coalesce(sum(valor_bruto), 0)::text from dados.atm_vendas('black-thb-2026-10');

-- a guarda, reexecutada com a migration já aplicada, tem que abortar
create temp table _g (txt text);
insert into pg_temp._g values ($zz$
do $g$
declare r dados.dashboards;
begin
  select * into r from dados.dashboards where chave = 'black-thb-2026-10';
  if not found then
    raise exception '20261017050000: dashboard black-thb-2026-10 não existe';
  end if;
  if r.modelo is distinct from 'acao-black' or r.conta_hotmart is distinct from 'academy' or not r.ativo then
    raise exception '20261017050000: black-thb-2026-10 não é acao-black ativo da conta academy (modelo %, conta %, ativo %)', r.modelo, r.conta_hotmart, r.ativo;
  end if;
  if r.oferta_codigo is not null or coalesce(cardinality(r.ofertas_extra), 0) <> 0 then
    raise exception '20261017050000: black-thb-2026-10 já tem oferta (principal %, extras %); revisar antes de sobrescrever', r.oferta_codigo, r.ofertas_extra;
  end if;
  -- uma oferta não pode ser de dois dashboards da mesma conta: dados.transacoes acha o dashboard pela oferta principal
  if exists (select 1 from dados.dashboards x
              where x.chave <> r.chave and x.conta_hotmart = r.conta_hotmart
                and (x.oferta_codigo in ('nv5f10zq', 'wftji6dl') or x.ofertas_extra && array['nv5f10zq', 'wftji6dl'])) then
    raise exception '20261017050000: nv5f10zq ou wftji6dl já pertence a outro dashboard da conta academy';
  end if;
  -- premissa de que isto basta: dados.transacoes lê oferta principal + ofertas_extra (corpo de 20261007ma/20261013av)
  if to_regprocedure('dados.transacoes(text,text)') is null
     or (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) <> 'efbd212fc50a114fa307b4681454e1a9' then
    raise exception '20261017050000: dados.transacoes mudou desde a leitura de 16/10/2026 (md5 do corpo diferente); reconferir que ela ainda soma ofertas_extra';
  end if;
end
$g$;
$zz$);
do $n$ begin
  begin
    execute (select txt from pg_temp._g);
    insert into pg_temp._z_out(passo, linha) values ('24 reaplicar sem reverter', 'NAO ABORTOU (erro!)');
  exception when others then
    insert into pg_temp._z_out(passo, linha) values ('24 reaplicar sem reverter', 'abortou: ' || left(sqlerrm, 160));
  end;
end $n$;

-- contraprova 1: sem a oferta EXTRA o upgrade não conta (esperado: vendas 1 = só a nv5f10zq)
update dados.dashboards set ofertas_extra = '{}' where chave = 'black-thb-2026-10';
set local role authenticated;
select pg_temp.foto('30 SEM a oferta extra (contraprova) cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('30 SEM a oferta extra (contraprova) serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('30 SEM a oferta extra (contraprova) controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);

update dados.dashboards set ofertas_extra = array['wftji6dl'] where chave = 'black-thb-2026-10';

-- contraprova 2: marcar o comprador da venda a como teste tira a venda do card (mesma RPC do resto do dashboard, só master)
set local role authenticated;
select pg_temp.foto('40 marcar zz.a como teste (retorno = linhas marcadas)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.a@example.invalid', null, 'teste')::text$q$);reset role;
select set_config('request.jwt.claims', '', true);

set local role authenticated;
select pg_temp.foto('41 COM o comprador a marcado teste (esperado: vendas 2, receita 20000, vendas_teste 1, receita_teste_bruta 6000) cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('41 COM o comprador a marcado teste (esperado: vendas 2, receita 20000, vendas_teste 1, receita_teste_bruta 6000) serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('41 COM o comprador a marcado teste (esperado: vendas 2, receita 20000, vendas_teste 1, receita_teste_bruta 6000) controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);


-- reversão ensaiada
-- Reversão da 20261017050000. Só desfaz se a linha ainda estiver como a migration deixou (não pisa em ajuste posterior).
update dados.dashboards
   set oferta_codigo = null, ofertas_extra = '{}'
 where chave = 'black-thb-2026-10' and oferta_codigo = 'nv5f10zq' and ofertas_extra = array['wftji6dl'];
delete from supabase_migrations.schema_migrations where version = '20261017050000';

insert into pg_temp._z_out(passo, linha) select '50 cadastro depois da reversao', jsonb_build_object('oferta_codigo', oferta_codigo, 'ofertas_extra', ofertas_extra)::text from dados.dashboards where chave = 'black-thb-2026-10';
set local role authenticated;
select pg_temp.foto('51 DEPOIS da reversao cards (resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('oferta', oferta_codigo, 'vendas', vendas, 'fora_brl', vendas_fora_brl, 'compradores', compradores, 'receita_bruta', receita_bruta, 'receita_liquida', receita_liquida, 'cac_centavos', cac_centavos, 'roas', roas, 'roas_liquido', roas_liquido, 'investimento_centavos', investimento_total_centavos, 'vendas_teste', vendas_teste, 'receita_teste_bruta', receita_teste_bruta)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('51 DEPOIS da reversao serie diaria (soma)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('dias', count(*), 'vendas', sum(vendas), 'receita_bruta', sum(receita_bruta))::text from public.dados_atm_serie_diaria('black-thb-2026-10')$q$);
select pg_temp.foto('51 DEPOIS da reversao controle: resumo das outras chaves (md5)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select string_agg(c.chave || ':' || md5((to_jsonb(r) - 'atualizado_em')::text), ' ' order by c.chave) from pg_temp._ch c cross join lateral public.dados_atm_resumo(c.chave) r$q$);
reset role;
select set_config('request.jwt.claims', '', true);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
