-- 20260929z80 — Relatório "Acelera → HM": só "subiu" quem NÃO era HM antes do Acelera
--
-- Por quê (Marcio, 29/09): quem já tinha HM (mensalidade do plano antigo, sinal, compra) antes
-- de comprar o Acelera só PARTICIPOU do Acelera; pagar HM depois não é subir. Medido antes:
-- 44 "subiram", 15 já eram HM (ex.: mensalidade 3507214 nº 12 contada como subida).
-- Regra nova:
--   * subiu = teve compra NOVA de HM depois do Acelera E não tinha nenhum HM pago antes.
--   * "compra nova" exclui mensalidade (oferta_modo SUBSCRIPTION) e parcela recorrente
--     (recorrencia > 1): pagamento de algo que já existia não é compra.
--   * ja_era_hm continua marcando quem tinha HM antes (filtro "Já eram HM" da tela).
-- Colunas e tipo de retorno iguais (create or replace). Reversão: corpo anterior em 20260928e.

create or replace function public.fn_fin_acelera_para_hm()
returns table (pessoa_chave text, nome text, email text, primeira_acelera date, acelera_pago numeric,
               acelera_funil text, ja_era_hm boolean, subiu boolean, primeira_hm_depois date,
               dias_ate_subir integer, hm_pago_depois numeric, hm_caminho text, tem_card boolean)
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
    select ac.p, ac.primeira, i.no from ac join fin.identidade i on i.pessoa_chave = ac.p and i.no like 'e:%'
  ), hmtx as materialized (
    select 'e:' || t.email no, t.dia_aprovado, t.valor_oferta, t.oferta_codigo, t.papel_produto,
           -- z80: compra nova = nem mensalidade nem parcela recorrente
           (t.oferta_modo is distinct from 'SUBSCRIPTION' and coalesce(t.recorrencia, 1) <= 1) compra_nova
      from fin.vw_transacoes t where t.familia = 'HM' and t.grupo = 'pago'
  ), hm as materialized (
    select a.p, a.primeira acelera_em, t.dia_aprovado, t.valor_oferta, t.compra_nova,
           coalesce(cat.categoria, t.papel_produto) cat
      from hmtx t
      join ac_no a on a.no = t.no
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
  ), resumo as materialized (
    select h.p,
           bool_or(h.dia_aprovado < h.acelera_em) antes,
           min(h.dia_aprovado) filter (where h.dia_aprovado >= h.acelera_em and h.compra_nova) primeira,
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
         -- z80: quem já era HM antes do Acelera não "sobe"
         (r.primeira is not null and not coalesce(r.antes, false)),
         case when not coalesce(r.antes, false) then r.primeira end,
         case when not coalesce(r.antes, false) then (r.primeira - ac.primeira)::int end,
         coalesce(r.pago, 0), r.caminho,
         k.p is not null
    from ac
    left join resumo r on r.p = ac.p
    left join card k on k.p = ac.p
   order by (r.primeira is not null and not coalesce(r.antes, false)) desc, r.primeira desc nulls last, ac.primeira desc;
end $$;

revoke all on function public.fn_fin_acelera_para_hm() from public, anon;
grant execute on function public.fn_fin_acelera_para_hm() to authenticated, service_role;
