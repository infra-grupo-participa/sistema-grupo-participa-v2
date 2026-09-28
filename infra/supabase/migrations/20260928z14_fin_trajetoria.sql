-- 20260928z14 — Trajetória da pessoa (João, 28/09: "a origem de todo mundo, de onde veio, qual funil já participou, qual
-- funil já comprou, o que fez em cada funil… toda a trajetória do aluno, tudo que ele já fez com a gente").
-- Uma linha por COMPRA (1ª cobrança; parcelamento Hotmart vira o valor contratado), de todos os e-mails da mesma pessoa
-- (fin.identidade), de qualquer produto (HM antigo, Programa, Aurum, Acelera, Diamante, ingressos de evento…).
-- Cada compra ganha o evento/funil: produto do funil → ingresso vai para o PRÓXIMO evento da categoria, oferta para o
-- evento do carrinho; senão o evento acontecendo no dia; senão o último evento até 30 dias antes ("depois do evento"). HM ganha a turma (fin.acoes). Papel: ingresso (ticket do evento, via
-- fin.evento_produtos) · programa (oferta do Programa desde 25/06/2026) · compra (o resto).
-- Só leitura. Guarda gp_pode_ver_financeiro. Recusadas/expiradas ficam de fora (tentativa sem dinheiro); estornadas entram.
create or replace function public.fn_fin_trajetoria(p_email text)
returns table (dia date, familia text, produto text, oferta text, situacao text, valor numeric, parcelas int,
               papel text, evento_id bigint, evento text, evento_categoria text, turma text, regra_evento text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with alvo as (
    select lower(trim(p_email)) email
  ), emails as (
    select distinct coalesce(substr(i2.no, 3), a.email) email
      from alvo a
      left join fin.identidade i on i.no = 'e:' || a.email
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), evs as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.*, coalesce(t.dia_aprovado, t.dia_pedido) d, cat.categoria cat
      from emails e
      join fin.vw_transacoes t on t.email = e.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.grupo in ('pago','estornado','atrasado','em_aberto') and coalesce(t.recorrencia, 1) = 1
  )
  select x.d, x.familia, x.produto_nome, x.oferta_codigo,
         case x.grupo when 'pago' then 'pago' when 'estornado' then 'estornado' when 'atrasado' then 'em atraso' else 'em aberto' end,
         round(x.valor_oferta * case when x.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(x.parcelas, 1) else 1 end, 2),
         x.parcelas,
         case when ev.regra = 'ingresso do evento' then 'ingresso'
              when x.produto_id = '5064314' and x.d >= date '2026-06-25' and coalesce(x.cat, '') not in ('renovacao','reserva') then 'programa'
              else 'compra' end,
         ev.id, ev.nome, ev.categoria,
         tor.turma,
         ev.regra
    from tx x
    left join lateral (
      -- produto do funil (fin.evento_produtos): ingresso olha para o PRÓXIMO evento da categoria (janela de ingresso da
      -- aba Funis: do fim de vendas do evento anterior até o fim de vendas deste); oferta, do carrinho ao fim de vendas
      select e.id, e.nome, e.categoria, case when ep.papel = 'ingresso' then 'ingresso do evento' else 'oferta do evento' end regra
        from evs e
        join fin.evento_produtos ep on ep.categoria = e.categoria and ep.produto_id = x.produto_id
       where (ep.papel = 'ingresso' and x.d between e.ing_de and e.venda_ate)
          or (ep.papel = 'oferta' and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
       order by (ep.papel = 'oferta') desc, e.venda_ate, e.inicio limit 1
    ) ev0 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'dia do evento'::text regra
        from fin.eventos e
       where ev0.id is null and e.setor = 'educacao'
         and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
         and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1
    ) ev1 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'depois do evento'::text regra
        from fin.eventos e
       where ev0.id is null and ev1.id is null and e.setor = 'educacao'
         and e.venda_ate < x.d and e.venda_ate >= x.d - 30
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by e.venda_ate desc limit 1
    ) ev2 on true
    cross join lateral (select coalesce(ev0.id, ev1.id, ev2.id) id, coalesce(ev0.nome, ev1.nome, ev2.nome) nome,
                               coalesce(ev0.categoria, ev1.categoria, ev2.categoria) categoria,
                               coalesce(ev0.regra, ev1.regra, ev2.regra) regra) ev
    -- turma de ORIGEM da pessoa (regra do João, 28/09): a da 1ª compra de HM/Aurum; quem nunca teve, a da entrada no Programa
    left join lateral (select a.turma from fin.acoes a
                        where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) >= a.inicio
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) < a.fim
                        order by a.prioridade desc, a.inicio desc limit 1) tor on true
   order by x.d, x.pedido_em;
end $$;
revoke all on function public.fn_fin_trajetoria(text) from public, anon;
grant execute on function public.fn_fin_trajetoria(text) to authenticated;
