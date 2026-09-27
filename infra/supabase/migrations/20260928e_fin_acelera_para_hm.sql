-- 20260928e — Quem subiu do Acelera Holding para o HM (pedido do João, 27/09/2026).
-- Acelera Holding (família ACELERA) é a porta de entrada do HM. Uma linha por pessoa que comprou o Acelera,
-- com o que ela comprou de HM DEPOIS da 1ª compra do Acelera (subiu) e se já era do HM antes.
-- Pessoa = componente de fin.identidade (junta os e-mails da mesma pessoa). Só leitura.
-- Medido em 27/09/2026: 413 compradores do Acelera; 43 subiram (R$ 484.838 — 39 pelo saldo, 3 cheio, 1 reserva);
-- 54 já eram do HM antes.

create or replace function public.fn_fin_acelera_para_hm()
returns table (pessoa_chave text, nome text, email text, primeira_acelera date, acelera_pago numeric, acelera_funil text,
               ja_era_hm boolean, subiu boolean, primeira_hm_depois date, dias_ate_subir int,
               hm_pago_depois numeric, hm_caminho text, tem_card boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with ac as materialized (
    select i.pessoa_chave p,
           (array_agg(t.nome order by t.aprovado_em))[1] nome,
           (array_agg(t.email order by t.aprovado_em))[1] email,
           min(t.dia_aprovado) primeira, sum(t.valor_oferta) pago,
           (array_agg(f.nome order by t.aprovado_em))[1] funil
      from fin.vw_transacoes t
      join fin.identidade i on i.no = 'e:' || t.email
      left join fin.funis f on f.familia = 'ACELERA' and t.dia_aprovado between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.familia = 'ACELERA' and t.grupo = 'pago'
     group by i.pessoa_chave
  ), ac_no as materialized (
    -- nós 'e:' das pessoas do Acelera. Materializar os dois lados deixa o banco cruzar por hash; antes ele
    -- comparava cada transação com cada nó (3.991 × 1.223 = 4,9 mi comparações, 4,8 s — medido 27/09).
    select ac.p, ac.primeira, i.no from ac join fin.identidade i on i.pessoa_chave = ac.p and i.no like 'e:%'
  ), hmtx as materialized (
    select 'e:' || t.email no, t.dia_aprovado, t.valor_oferta, t.oferta_codigo, t.papel_produto
      from fin.vw_transacoes t where t.familia = 'HM' and t.grupo = 'pago'
  ), hm as materialized (
    select a.p, a.primeira acelera_em, t.dia_aprovado, t.valor_oferta, coalesce(cat.categoria, t.papel_produto) cat
      from hmtx t
      join ac_no a on a.no = t.no
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
  ), resumo as materialized (
    select h.p,
           bool_or(h.dia_aprovado < h.acelera_em) antes,
           min(h.dia_aprovado) filter (where h.dia_aprovado >= h.acelera_em) primeira,
           sum(h.valor_oferta) filter (where h.dia_aprovado >= h.acelera_em) pago,
           string_agg(distinct h.cat, ' · ') filter (where h.dia_aprovado >= h.acelera_em) caminho
      from hm h group by h.p
  ), card as materialized (
    select distinct i.pessoa_chave p
      from cs.contatos_hm ch
      join public.compradores c on c.id = ch.comprador_id
      join fin.identidade i on i.no = 'e:' || lower(trim(c.email))
     where coalesce(ch.produto, 'HM') = 'HM'
  )
  select fin.chave_opaca(ac.p), ac.nome, ac.email, ac.primeira, ac.pago, ac.funil,
         coalesce(r.antes, false),
         r.primeira is not null, r.primeira, (r.primeira - ac.primeira)::int, coalesce(r.pago, 0), r.caminho,
         k.p is not null
    from ac
    left join resumo r on r.p = ac.p
    left join card k on k.p = ac.p
   order by (r.primeira is not null) desc, r.primeira desc nulls last, ac.primeira desc;
end $$;
revoke all on function public.fn_fin_acelera_para_hm() from public, anon;
grant execute on function public.fn_fin_acelera_para_hm() to authenticated;
