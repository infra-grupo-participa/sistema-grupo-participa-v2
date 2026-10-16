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
