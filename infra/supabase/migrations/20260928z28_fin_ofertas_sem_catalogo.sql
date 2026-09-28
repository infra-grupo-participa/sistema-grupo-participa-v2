-- 20260928z28 — Oferta PAGA fora do catálogo, visível no board (melhoria 8 da proposta de 28/09).
-- O webhook grava a compra, mas sem a oferta em public.hm_product_catalog o card não nasce e o pagamento não é lançado.
-- O sistema já gravava alerta crítico em cs.hm_alertas ("oferta_orfa") e ninguém via: a Aurum de R$ 57.700 de 28/08
-- (07tj9ipj) e os 39 do Programa sem card nasceram assim. Fonte: public.compras aprovadas desde 01/01/2026, de produto
-- do HM ou do Aurum (fin.produtos), com oferta ausente do catálogo. Some sozinho quando a oferta é catalogada.
create or replace function public.fn_fin_ofertas_sem_catalogo()
returns table (oferta text, familia text, produto text, pagamentos int, pessoas int, valor numeric,
               primeira date, ultima date, nomes text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select k.oferta_codigo::text, p.familia::text, max(p.nome)::text, count(*)::int, count(distinct k.comprador_id)::int,
         round(sum(coalesce(k.preco, 0)), 2),
         min((coalesce(k.data_aprovacao, k.data_compra) at time zone 'America/Sao_Paulo')::date),
         max((coalesce(k.data_aprovacao, k.data_compra) at time zone 'America/Sao_Paulo')::date),
         string_agg(distinct fin.nome_proprio(cp.nome::text), ', ')::text
    from public.compras k
    join fin.produtos p on p.produto_id = k.produto_id::text and p.familia in ('HM','AURUM')
    left join public.compradores cp on cp.id = k.comprador_id
   where k.status in ('APPROVED','COMPLETE','COMPLETED')
     and coalesce(k.data_aprovacao, k.data_compra) >= timestamptz '2026-01-01 03:00+00'
     and k.oferta_codigo is not null
     and not exists (select 1 from public.hm_product_catalog c where c.offer_code = k.oferta_codigo)
   group by k.oferta_codigo, p.familia
   order by max(coalesce(k.data_aprovacao, k.data_compra)) desc;
end $$;
revoke all on function public.fn_fin_ofertas_sem_catalogo() from public, anon;
grant execute on function public.fn_fin_ofertas_sem_catalogo() to authenticated;
