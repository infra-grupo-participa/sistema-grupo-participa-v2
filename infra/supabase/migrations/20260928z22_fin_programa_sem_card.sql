-- 20260928z22 — Quem PAGOU oferta do Programa (produto 5064314, fora renovação, desde o marco 25/06/2026) e não tem card
-- no board. Medido em 28/09: 297 pessoas pagaram, 39 sem card (R$ 428.669) — 34 do "HM com desconto Acelera" (01–03/09)
-- e 5 por ofertas fora de public.hm_product_catalog (o webhook não cria card). Criar o card é do sistema de ativação
-- (cs.contatos_hm, dado de produção) — aqui só fica VISÍVEL no board, com a ação de origem pela data (fin.acoes 2026).
create or replace function public.fn_fin_programa_sem_card(p_familia text default 'HM')
returns table (nome text, email text, telefone text, primeira date, valor numeric, ofertas text, fora_do_catalogo boolean,
               acao text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with pagos as (
    select coalesce(i.pessoa_chave, 'e:' || t.email) pk, t.email, t.nome, t.transacao, t.aprovado_em, t.dia_aprovado,
           t.valor_oferta, t.oferta_codigo, cat.offer_code is null fora, t.origem_sck
      from fin.vw_transacoes t
      left join fin.identidade i on i.no = 'e:' || t.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where p_familia = 'HM' and t.produto_id = '5064314' and t.grupo = 'pago' and t.dia_aprovado >= date '2026-06-25'
       and coalesce(cat.categoria, '') not in ('renovacao','reserva')
  ), board as (
    select distinct coalesce(i.pessoa_chave, 'e:' || lower(trim(b.email))) pk
      from cs.vw_fin_board b left join fin.identidade i on i.no = 'e:' || lower(trim(b.email))
     where b.origem = p_familia
  ), pessoa as (
    select p.pk, min(p.aprovado_em) primeira_em, sum(p.valor_oferta) valor,
           string_agg(distinct p.oferta_codigo, ', ') ofertas, bool_or(p.fora) fora,
           (array_agg(p.email order by p.aprovado_em))[1] email, (array_agg(p.nome order by p.aprovado_em))[1] nome,
           (array_agg(p.transacao order by p.aprovado_em))[1] transacao
      from pagos p where not exists (select 1 from board b where b.pk = p.pk)
     group by p.pk
  )
  select fin.nome_proprio(x.nome), x.email,
         case when coalesce(public.gp_pode_ver_cpf(), false) then h.comprador_telefone
              when h.comprador_telefone is not null then '···' || right(h.comprador_telefone, 4) end,
         (x.primeira_em at time zone 'America/Sao_Paulo')::date, round(x.valor, 2), x.ofertas, x.fora,
         (select a.nome from fin.acoes a
           where a.produto = p_familia and a.inicio is not null and a.fim is not null and a.prioridade <> 50
             and x.primeira_em >= a.inicio and x.primeira_em < a.fim
           order by a.prioridade, a.id limit 1)
    from pessoa x
    left join fin.hotmart_transacoes h on h.transacao = x.transacao
   order by x.primeira_em;
end $$;
revoke all on function public.fn_fin_programa_sem_card(text) from public, anon;
grant execute on function public.fn_fin_programa_sem_card(text) to authenticated;
