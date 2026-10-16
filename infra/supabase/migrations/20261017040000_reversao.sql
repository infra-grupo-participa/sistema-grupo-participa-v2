-- Reversão de 20261017040000: devolve o corpo de 20261016180000 (aplicaram_e_pagaram volta a contar linhas).
-- Aborta se o corpo vivo não for o desta migration.
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
