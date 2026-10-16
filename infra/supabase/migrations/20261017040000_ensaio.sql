-- Ensaio de 20261017040000 numa transação DESFEITA (rollback). Saída só com contagens, sem dado pessoal.
-- Prova: a guarda passa sobre o estado vivo; a função recriada roda; o número novo = pessoas distintas; proacl igual (sem anon/public);
--   a reversão devolve o md5 de 20261016180000.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (em serial, passo text, linha text);

insert into pg_temp._z_out(passo, linha)
select '00 antes', jsonb_build_object('aplicaram_e_pagaram', (public.dados_renov_thb(false))->'aplicaram_e_pagaram',
  'proacl', (select proacl::text from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure))::text;

-- ===== 20261017040000 (corpo da migration) =====
-- 20261017040000: painel do /renov, ajuste pedido pelo Auditor de Repositório no PR 65 (ponto baixo 1).
-- aplicaram_e_pagaram passa a contar PESSOAS distintas (count(distinct lower(email))), não linhas de aplicação:
-- quem aplica duas vezes e paga contava 2. Assinatura, permissões e o resto do corpo ficam iguais.
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026. Só rodou o ensaio (20261017040000_ensaio.sql, begin ... rollback).
-- Corpo partiu da definição VIVA lida em 16/10 (md5 de pg_get_functiondef = b0ded7ddc6471eaff44c595a44b6a59f, igual a 20261016180000).
-- Massa em 16/10: 8 aplicações não teste, 2 linhas de e-mail repetido, aplicaram_e_pagaram = 0 nas duas contagens.
-- Reversão: 20261017040000_reversao.sql (devolve o corpo de 20261016180000).
do $$ begin
  if (select md5(pg_get_functiondef('public.dados_renov_thb(boolean)'::regprocedure))) is distinct from 'b0ded7ddc6471eaff44c595a44b6a59f' then
    raise exception 'premissa: public.dados_renov_thb mudou desde 16/10 (md5 diferente de 20261016180000), reler o corpo vivo';
  end if;
end $$;

create or replace function public.dados_renov_thb(p_incluir_teste boolean default false)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_ver boolean := coalesce(acesso.tem('contato.ver'), false);
  v jsonb;
begin
  with ap as (
    select a.* from metodo.renov_aplicacoes a where p_incluir_teste or not a.teste
  ), vd as (
    select t.transacao, t.oferta_codigo, t.status, t.valor_base, coalesce(t.aprovado_em, t.pedido_em) as em,
           lower(t.comprador_email) as email, t.comprador_nome, t.origem_sck
    from (select * from fin.hotmart_transacoes where conta = 'academy') t
    where t.oferta_codigo in ('nv5f10zq', 'wftji6dl') and t.status in ('APPROVED', 'COMPLETE')
  ), ap_pago as (
    select ap.*, exists (select 1 from vd where vd.email = lower(ap.email)) as pagou from ap
  )
  select jsonb_build_object(
    'atualizado_em', now(),
    'aplicacoes_total', (select count(*) from ap),
    'por_opcao', (select coalesce(jsonb_object_agg(opcao, n), '{}'::jsonb) from (select opcao, count(*) n from ap group by opcao) x),
    'aplicaram_e_pagaram', (select count(distinct lower(email)) from ap_pago where pagou and opcao <> 'nao-renovar'),
    'vendas', (select coalesce(jsonb_agg(jsonb_build_object('oferta', o.cod, 'vendas', coalesce(s.n, 0), 'valor', coalesce(s.v, 0)) order by o.cod), '[]'::jsonb)
               from (values ('nv5f10zq'), ('wftji6dl')) o(cod)
               left join (select oferta_codigo, count(*) n, sum(valor_base) v from vd group by oferta_codigo) s on s.oferta_codigo = o.cod),
    'aplicacoes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'criado_em', criado_em, 'opcao', opcao, 'origem', coalesce(utm_source, ''), 'pagou', pagou, 'teste', teste,
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end,
                     'telefone', case when v_ver then telefone end) order by criado_em desc), '[]'::jsonb)
                   from (select * from ap_pago order by criado_em desc limit 500) l),
    'ultimas_vendas', (select coalesce(jsonb_agg(jsonb_build_object(
                     'em', em, 'oferta', oferta_codigo, 'valor', valor_base, 'status', status,
                     'aplicou', exists (select 1 from ap where lower(ap.email) = vd2.email),
                     'nome', case when v_ver then comprador_nome end, 'email', case when v_ver then email end) order by em desc), '[]'::jsonb)
                   from (select * from vd order by em desc limit 50) vd2),
    've_contato', v_ver
  ) into v;
  return v;
end;
$function$;

revoke all on function public.dados_renov_thb(boolean) from public, anon;
grant execute on function public.dados_renov_thb(boolean) to authenticated, service_role;

-- ===== fim do corpo =====

insert into pg_temp._z_out(passo, linha)
with ap as (select a.* from metodo.renov_aplicacoes a where not a.teste),
vd as (select lower(t.comprador_email) as email from (select * from fin.hotmart_transacoes where conta = 'academy') t
       where t.oferta_codigo in ('nv5f10zq', 'wftji6dl') and t.status in ('APPROVED', 'COMPLETE'))
select '01 depois (esperado: rpc = esperado_distinto; proacl igual ao 00)', jsonb_build_object(
  'rpc', (public.dados_renov_thb(false))->'aplicaram_e_pagaram',
  'esperado_distinto', (select count(distinct lower(ap.email)) from ap where ap.opcao <> 'nao-renovar' and exists (select 1 from vd where vd.email = lower(ap.email))),
  'proacl', (select proacl::text from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure),
  'anon_executa', has_function_privilege('anon', 'public.dados_renov_thb(boolean)', 'execute'))::text;

-- cenário fictício: a mesma pessoa aplica 2 vezes (e-mail com caixa diferente) e paga 1 vez; esperado +1 pessoa, não +2.
-- Em 16/10 não há venda real das duas ofertas, então a venda também é fictícia (e-mail .invalid). fin.hotmart_transacoes tem os
-- triggers zz_crm_hotmart_sync_*: a venda entra com session_replication_role = replica (só nesta transação, sem lock de tabela),
-- e o papel volta a origin logo depois. Tudo some no rollback.
insert into pg_temp._z_out(passo, linha)
select '02 antes do ficticio', jsonb_build_object('rpc', (public.dados_renov_thb(false))->'aplicaram_e_pagaram')::text;

set local session_replication_role = replica;
insert into fin.hotmart_transacoes (transacao, produto_id, oferta_codigo, status, comprador_email, bruto_json, conta)
values ('ZZ-ENSAIO-20261017040000', 'zz-ensaio', 'nv5f10zq', 'APPROVED', 'zz.ensaio@exemplo.invalid', '{}'::jsonb, 'academy');
set local session_replication_role = origin;

insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, teste) values
  ('Zz Ensaio', 'zz.ensaio@exemplo.invalid', '+550000000000', 'renovar-holding-masters', false),
  ('Zz Ensaio', 'ZZ.Ensaio@Exemplo.invalid', '+550000000000', 'upgrade-implementacao-assistida', false);

insert into pg_temp._z_out(passo, linha)
select '03 ficticio (esperado: rpc = 02 + 1)', jsonb_build_object(
  'inseridas', (select count(*) from metodo.renov_aplicacoes where nome = 'Zz Ensaio'),
  'rpc', (public.dados_renov_thb(false))->'aplicaram_e_pagaram')::text;

-- reversão (arquivo _reversao.sql) dentro do mesmo ensaio
do $$ begin
  if position('count(distinct lower(email)) from ap_pago' in pg_get_functiondef('public.dados_renov_thb(boolean)'::regprocedure)) = 0 then
    raise exception 'reversão sem efeito: public.dados_renov_thb não está no corpo de 20261017040000';
  end if;
end $$;

create or replace function public.dados_renov_thb(p_incluir_teste boolean default false)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_ver boolean := coalesce(acesso.tem('contato.ver'), false);
  v jsonb;
begin
  with ap as (
    select a.* from metodo.renov_aplicacoes a where p_incluir_teste or not a.teste
  ), vd as (
    select t.transacao, t.oferta_codigo, t.status, t.valor_base, coalesce(t.aprovado_em, t.pedido_em) as em,
           lower(t.comprador_email) as email, t.comprador_nome, t.origem_sck
    from (select * from fin.hotmart_transacoes where conta = 'academy') t
    where t.oferta_codigo in ('nv5f10zq', 'wftji6dl') and t.status in ('APPROVED', 'COMPLETE')
  ), ap_pago as (
    select ap.*, exists (select 1 from vd where vd.email = lower(ap.email)) as pagou from ap
  )
  select jsonb_build_object(
    'atualizado_em', now(),
    'aplicacoes_total', (select count(*) from ap),
    'por_opcao', (select coalesce(jsonb_object_agg(opcao, n), '{}'::jsonb) from (select opcao, count(*) n from ap group by opcao) x),
    'aplicaram_e_pagaram', (select count(*) from ap_pago where pagou and opcao <> 'nao-renovar'),
    'vendas', (select coalesce(jsonb_agg(jsonb_build_object('oferta', o.cod, 'vendas', coalesce(s.n, 0), 'valor', coalesce(s.v, 0)) order by o.cod), '[]'::jsonb)
               from (values ('nv5f10zq'), ('wftji6dl')) o(cod)
               left join (select oferta_codigo, count(*) n, sum(valor_base) v from vd group by oferta_codigo) s on s.oferta_codigo = o.cod),
    'aplicacoes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'criado_em', criado_em, 'opcao', opcao, 'origem', coalesce(utm_source, ''), 'pagou', pagou, 'teste', teste,
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end,
                     'telefone', case when v_ver then telefone end) order by criado_em desc), '[]'::jsonb)
                   from (select * from ap_pago order by criado_em desc limit 500) l),
    'ultimas_vendas', (select coalesce(jsonb_agg(jsonb_build_object(
                     'em', em, 'oferta', oferta_codigo, 'valor', valor_base, 'status', status,
                     'aplicou', exists (select 1 from ap where lower(ap.email) = vd2.email),
                     'nome', case when v_ver then comprador_nome end, 'email', case when v_ver then email end) order by em desc), '[]'::jsonb)
                   from (select * from vd order by em desc limit 50) vd2),
    've_contato', v_ver
  ) into v;
  return v;
end;
$function$;

revoke all on function public.dados_renov_thb(boolean) from public, anon;
grant execute on function public.dados_renov_thb(boolean) to authenticated, service_role;

insert into pg_temp._z_out(passo, linha)
select '04 depois da reversao (esperado: md5 = b0ded7ddc6471eaff44c595a44b6a59f; rpc = 02 + 2, volta a contar linhas)', jsonb_build_object(
  'md5', md5(pg_get_functiondef('public.dados_renov_thb(boolean)'::regprocedure)),
  'rpc', (public.dados_renov_thb(false))->'aplicaram_e_pagaram',
  'proacl', (select proacl::text from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure))::text;

select passo, linha from pg_temp._z_out order by em;
rollback;
