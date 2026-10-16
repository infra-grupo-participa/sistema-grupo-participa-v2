-- Ensaio de 20261017050300_dados_renov_thb_com_chave.sql numa transação DESFEITA (rollback), sobre produção.
-- Roda antes 20261017050000 (ofertas), 20261017050100 (de-para) e 20261017050200 (atm_pertence) na mesma transação. Sem dado pessoal na saída: dados fictícios @example.invalid (prefixo zz.),
-- as linhas reais entram só como contagem. Prova: guarda; ACL; fechamento do painel com o card Vendas; teste pela coluna, pelo e-mail e pelo
-- telefone marcados; p_incluir_teste; outra origem/chave; permissões; tempo da RPC inteira (2x) contra a antiga; reversão.
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

set local session_replication_role = replica;
insert into pg_temp._z_out(passo, linha) select '00 versão atual (boolean): md5 e ACL', md5(prosrc) || ' ' || coalesce(proacl::text, '(nula)') from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '00 aplicações reais / reais marcadas teste na coluna', count(*) || ' / ' || count(*) filter (where teste) from metodo.renov_aplicacoes;
-- dados fictícios. Vendas que contam: ap1 (nv, 6000), ap2 (wf, 10000); vendas que NÃO contam: estornada, recorrência 2, antes de vendas_desde, outra oferta.
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V1', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 1, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.ap1@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V2', 'ZZ-PRODUTO', 'wftji6dl', 'COMPLETE', 1, 'BRL', 10000, 10000, 10000*0.9, now() - interval '2 minutes', now(), 'zz.ap2@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V3', 'ZZ-PRODUTO', 'nv5f10zq', 'REFUNDED', 1, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.ap3@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V4', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 2, 'BRL', 6000, 6000, 6000*0.9, now() - interval '2 minutes', now(), 'zz.ap4@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V5', 'ZZ-PRODUTO', 'nv5f10zq', 'APPROVED', 1, 'BRL', 6000, 6000, 6000*0.9, timestamptz '2026-10-13 12:00+00', timestamptz '2026-10-13 12:05+00', 'zz.ap5@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado, liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, conta)
  values ('ZZ-V6', 'ZZ-PRODUTO', 'zzzzzzzz', 'APPROVED', 1, 'BRL', 777, 777, 777*0.9, now() - interval '2 minutes', now(), 'zz.ap6@example.invalid', 'Zz Comprador', '{}'::jsonb, 'academy');

insert into cs.hotmart_eventos (evento, transacao, email, payload) values ('PURCHASE_APPROVED', 'ZZ-V7-WEBHOOK', 'zz.ap7@example.invalid', jsonb_build_object('data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'zz.ap7@example.invalid', 'name', 'Zz Webhook'),
  'purchase', jsonb_build_object('offer', jsonb_build_object('code', 'wftji6dl'), 'price', jsonb_build_object('value', 10000, 'currency_value', 'BRL'), 'status', 'APPROVED',
     'order_date', (extract(epoch from now() - interval '1 minute') * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint, 'recurrence_number', 1),
  'commissions', jsonb_build_array(jsonb_build_object('value', 9000, 'source', 'PRODUCER')))));
-- aplicações fictícias: ap1 e ap2 pagaram; ap7 (venda só no webhook); ap8 sem venda; ap9 'nao-renovar'; ap10 já com a coluna teste; ap11 de outra origem (fora da chave)
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap1@example.invalid', '(21) 99999-2001', 'renovar-holding-masters', 'renov-thb', false);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap2@example.invalid', '(21) 99999-2002', 'upgrade-implementacao-assistida', 'renov-thb', false);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap7@example.invalid', '(21) 99999-2007', 'upgrade-implementacao-assistida', 'renov-thb', false);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap8@example.invalid', '(21) 99999-2008', 'renovar-holding-masters', 'renov-thb', false);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap9@example.invalid', '(21) 99999-2009', 'nao-renovar', 'renov-thb', false);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap10@example.invalid', '(21) 99999-2010', 'renovar-holding-masters', 'renov-thb', true);
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem, teste) values ('Zz Aplicou', 'zz.ap11@example.invalid', '(21) 99999-2011', 'renovar-holding-masters', 'outra-origem', false);

-- ===== dependências: ofertas e de-para =====
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

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050100: falta metodo.origem_etiqueta (20261014200000)';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null then
    raise exception '20261017050100: falta metodo.renov_aplicacoes (20261016163924, Arthur)';
  end if;
  if exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb') then
    raise exception '20261017050100: renov-thb já está no de-para; revisar';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black') then
    raise exception '20261017050100: black-thb-2026-10 não existe como acao-black';
  end if;
  if exists (select 1 from metodo.pesquisa_respostas where origem = 'renov-thb') then
    raise exception '20261017050100: já existe pesquisa_respostas com origem renov-thb; o gatilho passaria a etiquetar essas linhas. Revisar';
  end if;
end
$g$;

insert into metodo.origem_etiqueta (origem, etiqueta) values ('renov-thb', 'black-thb-2026-10');

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.atm_pertence(text,text,text)') is null then
    raise exception '20261017050200: dados.atm_pertence(text,text,text) não existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure) <> '7945be0a410031528e24bd21a4c876ca' then
    raise exception '20261017050200: o corpo vivo de dados.atm_pertence mudou desde a leitura de 16/10/2026; reler e refazer a partir dele';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050200: faltam metodo.renov_aplicacoes (20261016163924, Arthur) ou metodo.origem_etiqueta';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050200: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100); sem ele o ramo novo nunca casa';
  end if;
end
$g$;

create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261008191000; número da foto do grupo em 20261008200000; aplicações do /renov em 20261017050200
  select case p_tipo
    when 'email' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and lower(btrim(a.email)) = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and right(controle.fone_key(a.telefone), 8) = p_valor)
      or exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$function$;

-- a ACL não pode ter mudado (create or replace a preserva; conferido aqui)
do $a$
begin
  if has_function_privilege('anon', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'dados.atm_pertence(text,text,text)', 'execute') then
    raise exception '20261017050200: dados.atm_pertence ficou executável por anon, authenticated ou service_role';
  end if;
end
$a$;

insert into pg_temp._z_out(passo, linha) select '01 depois de 20261017050000, 20261017050100 e 20261017050200: cadastro', jsonb_build_object('oferta_codigo', oferta_codigo, 'ofertas_extra', ofertas_extra)::text from dados.dashboards where chave = 'black-thb-2026-10';
-- ===== ANTES (versão atual, boolean) =====
set local role authenticated;
select pg_temp.foto('10 ANTES: versão (boolean) como Victor (agregados)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text from (select public.dados_renov_thb(false) r) x$q$);
reset role;
select set_config('request.jwt.claims', '', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select public.dados_renov_thb(false)' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared hit)' and r."QUERY PLAN" !~ '^\s{4,}' then
        insert into pg_temp._z_out (passo, linha) values ('11 explain ANTES da versão (boolean) #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- ===== corpo da migration =====
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('public.dados_renov_thb(text,boolean)') is not null then
    raise exception '20261017050300: public.dados_renov_thb(text,boolean) já existe; revisar';
  end if;
  if to_regprocedure('public.dados_renov_thb(boolean)') is null then
    raise exception '20261017050300: falta a versão atual dados_renov_thb(boolean) (20261016173552)';
  end if;
  if to_regprocedure('dados.atm_cadastro(text)') is null or to_regprocedure('dados.teste_ativo(text,text,text)') is null
     or to_regprocedure('dados.transacoes(text,text)') is null then
    raise exception '20261017050300: faltam dados.atm_cadastro, dados.teste_ativo ou dados.transacoes';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.renov_visitas') is null then
    raise exception '20261017050300: faltam metodo.renov_aplicacoes (20261016163924) ou metodo.renov_visitas (20261016172921)';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050300: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100)';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black' and oferta_codigo is not null) then
    raise exception '20261017050300: black-thb-2026-10 sem oferta ligada (20261017050000)';
  end if;
end
$g$;

create function public.dados_renov_thb(p_chave text, p_incluir_teste boolean default false)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe; P0002 chave fora do cadastro ou outro modelo
  v_conta text := d.conta_hotmart;
  v_ofertas text[] := case when d.oferta_codigo is null then '{}'::text[] else array[d.oferta_codigo] || coalesce(d.ofertas_extra, '{}'::text[]) end;
  v_ver boolean := coalesce(acesso.tem('contato.ver'), false);
  v jsonb;
begin
  with base as (
    select a.*, lower(a.email) like '%@advmais.com' as advmais, m.marcado,
           (a.teste or lower(a.email) like '%@advmais.com' or m.marcado) as teste_efetivo
    from metodo.renov_aplicacoes a
    join metodo.origem_etiqueta o on o.origem = a.origem and o.etiqueta = p_chave
    cross join lateral (select dados.teste_ativo(p_chave, a.email, a.telefone) as marcado) m
  ), ap as (
    select * from base where p_incluir_teste or not teste_efetivo
  ), reais as (
    select * from base where not teste_efetivo
  ), mapa as (
    select distinct on (x.transacao) x.transacao, x.oferta_codigo
    from (
      select t.transacao, t.oferta_codigo
        from (select * from fin.hotmart_transacoes where conta = v_conta) t
       where t.oferta_codigo = any (v_ofertas)
      union all
      select e.transacao, e.payload #>> '{data,purchase,offer,code}'
        from cs.hotmart_eventos e
       where v_conta = 'academy' and e.transacao is not null and e.evento like 'PURCHASE%'
         and e.payload #>> '{data,purchase,offer,code}' = any (v_ofertas)
         and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h where h.transacao = e.transacao)
    ) x
    order by x.transacao, x.oferta_codigo
  ), vd as (
    select t.transacao, t.status, t.valor_bruto, t.moeda, coalesce(t.aprovado_em, t.pedido_em) as em, t.email, t.nome,
           mp.oferta_codigo as oferta, dados.teste_ativo(p_chave, t.email, null) as teste_v
    from dados.transacoes(v_conta, d.oferta_codigo) t
    left join mapa mp on mp.transacao = t.transacao
    where d.oferta_codigo is not null and t.pago and t.primeira
      and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
  ), vdv as (
    select * from vd where p_incluir_teste or not teste_v
  ), ap_mais as (
    select ap.*,
           exists (select 1 from vdv where vdv.email = lower(ap.email)) as pagou,
           case when ap.visitante is null then null
                else (select count(*) from metodo.renov_visitas rv where rv.visitante = ap.visitante and rv.criado_em <= ap.criado_em) end as acessos_antes
    from ap
  ), vis as (
    select count(*) as acessos, count(distinct visitante) as visitantes from metodo.renov_visitas
  )
  select jsonb_build_object(
    'atualizado_em', now(),
    'chave', p_chave,
    'sem_oferta', d.oferta_codigo is null,
    'aplicacoes_total', (select count(*) from reais),
    'por_opcao', (select coalesce(jsonb_object_agg(opcao, n), '{}'::jsonb) from (select opcao, count(*) n from reais group by opcao) x),
    'aplicaram_e_pagaram', (select count(distinct lower(r.email)) from reais r where r.opcao <> 'nao-renovar' and exists (select 1 from vdv where vdv.email = lower(r.email))),
    'acessos', (select acessos from vis),
    'visitantes', (select visitantes from vis),
    'visitantes_que_aplicaram', (select count(distinct visitante) from reais where visitante is not null),
    'vendas', (select coalesce(jsonb_agg(jsonb_build_object('oferta', o.cod, 'vendas', coalesce(s.n, 0), 'valor', coalesce(s.v, 0)) order by o.ord), '[]'::jsonb)
               from unnest(v_ofertas) with ordinality o(cod, ord)
               left join (select oferta, count(*) n, sum(valor_bruto) filter (where moeda = 'BRL') v from vdv group by oferta) s on s.oferta = o.cod),
    'vendas_total', (select count(*) from vdv),
    'valor_total', (select coalesce(sum(valor_bruto) filter (where moeda = 'BRL'), 0) from vdv),
    'vendas_fora_brl', (select count(*) from vdv where moeda <> 'BRL'),
    'aplicacoes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id, 'criado_em', criado_em, 'opcao', opcao, 'origem', coalesce(utm_source, ''), 'pagou', pagou,
                     'teste', teste_efetivo, 'teste_fixo', advmais, 'teste_coluna', teste, 'teste_marcado', marcado,
                     'acessos_antes', acessos_antes,
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end,
                     'telefone', case when v_ver then telefone end) order by criado_em desc), '[]'::jsonb)
                   from (select * from ap_mais order by criado_em desc limit 500) l),
    'ultimas_vendas', (select coalesce(jsonb_agg(jsonb_build_object(
                     'em', em, 'oferta', oferta, 'valor', valor_bruto, 'status', status,
                     'aplicou', exists (select 1 from reais r where lower(r.email) = vd2.email),
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end) order by em desc), '[]'::jsonb)
                   from (select * from vdv order by em desc limit 50) vd2),
    've_contato', v_ver,
    'eh_master', coalesce(acesso.eh_master(), false)
  ) into v;
  return v;
end;
$function$;

revoke all on function public.dados_renov_thb(text, boolean) from public, anon;
grant execute on function public.dados_renov_thb(text, boolean) to authenticated, service_role;

comment on function public.dados_renov_thb(text, boolean) is
  'Painel do /renov da ação (chave): aplicações da página, acessos e vendas das ofertas da ação, com o teste padrão do dashboard (dados.marcacoes_teste). 16/10/2026.';

do $a$
begin
  if has_function_privilege('anon', 'public.dados_renov_thb(text,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_renov_thb(text,boolean)', 'execute') then
    raise exception '20261017050300: ACL da função nova fora do esperado (anon sem, authenticated com)';
  end if;
end
$a$;

insert into pg_temp._z_out(passo, linha) select '20 função nova: ACL', coalesce(proacl::text, '(nula)') from pg_proc where oid = 'public.dados_renov_thb(text,boolean)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '20 a antiga (boolean) segue igual (md5)', md5(prosrc) from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure;
set local role authenticated;
select pg_temp.foto('21 Victor (master, contato.ver): sem testes', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text || ' | linhas=' || jsonb_array_length(r->'aplicacoes') || ' | ficticias: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '[teste=' || (e->>'teste') || ',col=' || (e->>'teste_coluna') || ',marc=' || (e->>'teste_marcado') || ',fixo=' || (e->>'teste_fixo') || ',pagou=' || (e->>'pagou') || ']', ' ' order by e->>'email')
             from jsonb_array_elements(r->'aplicacoes') e where e->>'email' like 'zz.%'), '-') || ' | vendas fict: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '=' || (e->>'oferta') || '/' || (e->>'valor') || '/aplicou=' || (e->>'aplicou'), ' ' order by e->>'email') from jsonb_array_elements(r->'ultimas_vendas') e where e->>'email' like 'zz.%'), '-')
  from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
select pg_temp.foto('22 Victor: com testes (p_incluir_teste)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text || ' | linhas=' || jsonb_array_length(r->'aplicacoes') || ' | ficticias: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '[teste=' || (e->>'teste') || ',col=' || (e->>'teste_coluna') || ',marc=' || (e->>'teste_marcado') || ',fixo=' || (e->>'teste_fixo') || ',pagou=' || (e->>'pagou') || ']', ' ' order by e->>'email')
             from jsonb_array_elements(r->'aplicacoes') e where e->>'email' like 'zz.%'), '-') || ' | vendas fict: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '=' || (e->>'oferta') || '/' || (e->>'valor') || '/aplicou=' || (e->>'aplicou'), ' ' order by e->>'email') from jsonb_array_elements(r->'ultimas_vendas') e where e->>'email' like 'zz.%'), '-')
  from (select public.dados_renov_thb('black-thb-2026-10', true) r) x$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- fechamento com o card Vendas da ação
set local role authenticated;
select pg_temp.foto('23 card Vendas da ação (dados_atm_resumo)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('vendas', vendas, 'receita_bruta', receita_bruta, 'vendas_teste', vendas_teste)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('24 painel: vendas_total e valor_total (esperado igual ao card: 3 e 26000)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (public.dados_renov_thb('black-thb-2026-10', false)->>'vendas_total') || ' / ' || (public.dados_renov_thb('black-thb-2026-10', false)->>'valor_total')$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- teste pelo e-mail marcado (ap1) e pelo telefone marcado (ap2)
set local role authenticated;
select pg_temp.foto('30 master marca o e-mail de ap1', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.ap1@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('31 master marca o telefone de ap2', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', null, '(21) 99999-2002', 'teste')::text$q$);
reset role;
select set_config('request.jwt.claims', '', true);

set local role authenticated;
select pg_temp.foto('32 sem testes: ap1 (e-mail) e ap2 (telefone) saem das aplicações; só o e-mail marcado tira a VENDA do card (esperado vendas_total 2 / 20000, aplicaram_e_pagaram 2)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text || ' | linhas=' || jsonb_array_length(r->'aplicacoes') || ' | ficticias: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '[teste=' || (e->>'teste') || ',col=' || (e->>'teste_coluna') || ',marc=' || (e->>'teste_marcado') || ',fixo=' || (e->>'teste_fixo') || ',pagou=' || (e->>'pagou') || ']', ' ' order by e->>'email')
             from jsonb_array_elements(r->'aplicacoes') e where e->>'email' like 'zz.%'), '-') || ' | vendas fict: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '=' || (e->>'oferta') || '/' || (e->>'valor') || '/aplicou=' || (e->>'aplicou'), ' ' order by e->>'email') from jsonb_array_elements(r->'ultimas_vendas') e where e->>'email' like 'zz.%'), '-')
  from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
select pg_temp.foto('33 com testes: ap1 e ap2 voltam marcadas teste (marc=true), vendas voltam (esperado vendas_total 3)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text || ' | linhas=' || jsonb_array_length(r->'aplicacoes') || ' | ficticias: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '[teste=' || (e->>'teste') || ',col=' || (e->>'teste_coluna') || ',marc=' || (e->>'teste_marcado') || ',fixo=' || (e->>'teste_fixo') || ',pagou=' || (e->>'pagou') || ']', ' ' order by e->>'email')
             from jsonb_array_elements(r->'aplicacoes') e where e->>'email' like 'zz.%'), '-') || ' | vendas fict: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '=' || (e->>'oferta') || '/' || (e->>'valor') || '/aplicou=' || (e->>'aplicou'), ' ' order by e->>'email') from jsonb_array_elements(r->'ultimas_vendas') e where e->>'email' like 'zz.%'), '-')
  from (select public.dados_renov_thb('black-thb-2026-10', true) r) x$q$);
select pg_temp.foto('34 card Vendas depois das marcações (esperado vendas 2, vendas_teste 1)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('vendas', vendas, 'receita_bruta', receita_bruta, 'vendas_teste', vendas_teste)::text from public.dados_atm_resumo('black-thb-2026-10')$q$);
select pg_temp.foto('35 painel vendas_total/valor_total (esperado 2 / 20000, igual ao card)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (public.dados_renov_thb('black-thb-2026-10', false)->>'vendas_total') || ' / ' || (public.dados_renov_thb('black-thb-2026-10', false)->>'valor_total')$q$);
reset role;
select set_config('request.jwt.claims', '', true);

set local role authenticated;
select pg_temp.foto('36 master desmarca ap1 e ap2', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (public.dados_desmarcar_teste('black-thb-2026-10', 'zz.ap1@example.invalid', null) + public.dados_desmarcar_teste('black-thb-2026-10', null, '(21) 99999-2002'))::text$q$);
select pg_temp.foto('37 depois de desmarcar (esperado igual ao passo 21)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text || ' | linhas=' || jsonb_array_length(r->'aplicacoes') || ' | ficticias: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '[teste=' || (e->>'teste') || ',col=' || (e->>'teste_coluna') || ',marc=' || (e->>'teste_marcado') || ',fixo=' || (e->>'teste_fixo') || ',pagou=' || (e->>'pagou') || ']', ' ' order by e->>'email')
             from jsonb_array_elements(r->'aplicacoes') e where e->>'email' like 'zz.%'), '-') || ' | vendas fict: ' ||
  coalesce((select string_agg(split_part(e->>'email','@',1) || '=' || (e->>'oferta') || '/' || (e->>'valor') || '/aplicou=' || (e->>'aplicou'), ' ' order by e->>'email') from jsonb_array_elements(r->'ultimas_vendas') e where e->>'email' like 'zz.%'), '-')
  from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- permissões e guardas
set local role authenticated;
select pg_temp.foto('40 jessica', '012bbcd3-cade-4889-a6ff-4804ed15c36d', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
select pg_temp.foto('41 QA', '6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
select pg_temp.foto('42 Deborah', '5231a48f-a2d9-4c5f-8ee4-cde459aa7a9e', $q$select (r - 'aplicacoes' - 'ultimas_vendas' - 'atualizado_em')::text from (select public.dados_renov_thb('black-thb-2026-10', false) r) x$q$);
select pg_temp.foto('42b usuário autenticado fora da equipe (esperado 42501)', '00000000-0000-0000-0000-000000000001', $q$select public.dados_renov_thb('black-thb-2026-10', false)::text$q$);
select pg_temp.foto('43 chave inexistente (esperado P0002)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_renov_thb('nao-existe-2026-10', false)::text$q$);
select pg_temp.foto('44 chave de outro modelo (jornada-captacao) (esperado P0002)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_renov_thb('black-friday-2026-10', false)::text$q$);
select pg_temp.foto('45 outra ação ATM (sem de-para do renov): zero aplicações', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select (r->>'aplicacoes_total') || ' / ' || (r->>'sem_oferta') || ' / ' || (r->>'vendas_total') from (select public.dados_renov_thb('atm-elaine-1-2026-10', false) r) x$q$);
reset role;
select set_config('request.jwt.claims', '', true);

set local role anon;
select pg_temp.foto('46 anônimo (esperado 42501 permission denied)', null, $q$select public.dados_renov_thb('black-thb-2026-10', false)::text$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- tempo
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select public.dados_renov_thb(''black-thb-2026-10'', false)' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared hit)' and r."QUERY PLAN" !~ '^\s{4,}' then
        insert into pg_temp._z_out (passo, linha) values ('50 explain DEPOIS da versão nova (chave, boolean) #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select public.dados_renov_thb(''black-thb-2026-10'', true)' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared hit)' and r."QUERY PLAN" !~ '^\s{4,}' then
        insert into pg_temp._z_out (passo, linha) values ('51 explain DEPOIS da versão nova com testes #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- a guarda reexecutada com a migration aplicada tem que abortar
create temp table _g (txt text);
insert into pg_temp._g values ($zz$
do $g$
begin
  if to_regprocedure('public.dados_renov_thb(text,boolean)') is not null then
    raise exception '20261017050300: public.dados_renov_thb(text,boolean) já existe; revisar';
  end if;
  if to_regprocedure('public.dados_renov_thb(boolean)') is null then
    raise exception '20261017050300: falta a versão atual dados_renov_thb(boolean) (20261016173552)';
  end if;
  if to_regprocedure('dados.atm_cadastro(text)') is null or to_regprocedure('dados.teste_ativo(text,text,text)') is null
     or to_regprocedure('dados.transacoes(text,text)') is null then
    raise exception '20261017050300: faltam dados.atm_cadastro, dados.teste_ativo ou dados.transacoes';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.renov_visitas') is null then
    raise exception '20261017050300: faltam metodo.renov_aplicacoes (20261016163924) ou metodo.renov_visitas (20261016172921)';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050300: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100)';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black' and oferta_codigo is not null) then
    raise exception '20261017050300: black-thb-2026-10 sem oferta ligada (20261017050000)';
  end if;
end
$g$;
$zz$);
do $n$ begin
  begin execute (select txt from pg_temp._g); insert into pg_temp._z_out(passo, linha) values ('60 reaplicar sem reverter', 'NAO ABORTOU (erro!)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('60 reaplicar sem reverter', 'abortou: ' || left(sqlerrm, 160)); end;
end $n$;
-- reversão ensaiada
-- Reversão da 20261017050300. Apaga só a função nova; dados_renov_thb(boolean) (20261016173552) não foi tocada.
drop function if exists public.dados_renov_thb(text, boolean);
delete from supabase_migrations.schema_migrations where version = '20261017050300';

insert into pg_temp._z_out(passo, linha) select '70 depois da reversão: nova existe? / antiga (md5)', (to_regprocedure('public.dados_renov_thb(text,boolean)') is not null)::text || ' / ' || (select md5(prosrc) from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
