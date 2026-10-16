-- Painel do /renov, versão 2 (16/10/2026, pedidos do Arthur às 14h25 e 14h27):
--   acessos à página (metodo.renov_visitas), acessos de cada visitante antes de aplicar, marcar teste por linha,
--   e-mail @advmais.com sempre teste na leitura, "aplicaram e pagaram" por pessoa distinta (parecer do Auditor no PR 65).
-- Marcar teste: public.renov_marcar_teste, só master (mesma regra de dados_marcar_teste, 20261015180100).
-- Volume pequeno (centenas de linhas): leitura direta. Reversão: 20261016180500_reversao.sql (volta o corpo da v1).
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_renov_thb(boolean)'::regprocedure) is distinct from 'c527ebe1f000af9e6c06228de48d26d1' then
    raise exception 'premissa: corpo vivo de dados_renov_thb mudou; revisar antes de aplicar';
  end if;
  if to_regclass('metodo.renov_visitas') is null then raise exception 'premissa: falta metodo.renov_visitas'; end if;
end $g$;

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
  with base as (
    select a.*, (a.teste or lower(a.email) like '%@advmais.com') as teste_efetivo,
           lower(a.email) like '%@advmais.com' as advmais
    from metodo.renov_aplicacoes a
  ), ap as (
    select * from base where p_incluir_teste or not teste_efetivo
  ), reais as (
    select * from base where not teste_efetivo
  ), vd as (
    select t.transacao, t.oferta_codigo, t.status, t.valor_base, coalesce(t.aprovado_em, t.pedido_em) as em,
           lower(t.comprador_email) as email, t.comprador_nome
    from (select * from fin.hotmart_transacoes where conta = 'academy') t
    where t.oferta_codigo in ('nv5f10zq', 'wftji6dl') and t.status in ('APPROVED', 'COMPLETE')
  ), ap_mais as (
    select ap.*,
           exists (select 1 from vd where vd.email = lower(ap.email)) as pagou,
           case when ap.visitante is null then null
                else (select count(*) from metodo.renov_visitas rv where rv.visitante = ap.visitante and rv.criado_em <= ap.criado_em) end as acessos_antes
    from ap
  ), vis as (
    select count(*) as acessos, count(distinct visitante) as visitantes from metodo.renov_visitas
  )
  select jsonb_build_object(
    'atualizado_em', now(),
    'aplicacoes_total', (select count(*) from reais),
    'por_opcao', (select coalesce(jsonb_object_agg(opcao, n), '{}'::jsonb) from (select opcao, count(*) n from reais group by opcao) x),
    'aplicaram_e_pagaram', (select count(distinct lower(r.email)) from reais r where r.opcao <> 'nao-renovar' and exists (select 1 from vd where vd.email = lower(r.email))),
    'acessos', (select acessos from vis),
    'visitantes', (select visitantes from vis),
    'visitantes_que_aplicaram', (select count(distinct visitante) from reais where visitante is not null),
    'vendas', (select coalesce(jsonb_agg(jsonb_build_object('oferta', o.cod, 'vendas', coalesce(s.n, 0), 'valor', coalesce(s.v, 0)) order by o.cod), '[]'::jsonb)
               from (values ('nv5f10zq'), ('wftji6dl')) o(cod)
               left join (select oferta_codigo, count(*) n, sum(valor_base) v from vd group by oferta_codigo) s on s.oferta_codigo = o.cod),
    'aplicacoes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id, 'criado_em', criado_em, 'opcao', opcao, 'origem', coalesce(utm_source, ''), 'pagou', pagou,
                     'teste', teste_efetivo, 'teste_fixo', advmais, 'acessos_antes', acessos_antes,
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end,
                     'telefone', case when v_ver then telefone end) order by criado_em desc), '[]'::jsonb)
                   from (select * from ap_mais order by criado_em desc limit 500) l),
    'ultimas_vendas', (select coalesce(jsonb_agg(jsonb_build_object(
                     'em', em, 'oferta', oferta_codigo, 'valor', valor_base, 'status', status,
                     'aplicou', exists (select 1 from reais r where lower(r.email) = vd2.email),
                     'nome', case when v_ver then comprador_nome end, 'email', case when v_ver then email end) order by em desc), '[]'::jsonb)
                   from (select * from vd order by em desc limit 50) vd2),
    've_contato', v_ver,
    'eh_master', coalesce(acesso.eh_master(), false)
  ) into v;
  return v;
end;
$function$;

revoke all on function public.dados_renov_thb(boolean) from public, anon;
grant execute on function public.dados_renov_thb(boolean) to authenticated, service_role;

-- Marcar ou desmarcar teste numa aplicação. Só master. E-mail @advmais.com segue teste na leitura de qualquer jeito.
create or replace function public.renov_marcar_teste(p_id uuid, p_teste boolean)
returns boolean
language plpgsql
volatile security definer
set search_path to ''
as $function$
declare
  n int;
begin
  if acesso.eu() is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_id is null or p_teste is null then
    raise exception 'informe a aplicação e o valor' using errcode = '22023';
  end if;
  update metodo.renov_aplicacoes set teste = p_teste where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'aplicação não encontrada' using errcode = 'P0002'; end if;
  return p_teste;
end;
$function$;

revoke all on function public.renov_marcar_teste(uuid, boolean) from public, anon;
grant execute on function public.renov_marcar_teste(uuid, boolean) to authenticated, service_role;
