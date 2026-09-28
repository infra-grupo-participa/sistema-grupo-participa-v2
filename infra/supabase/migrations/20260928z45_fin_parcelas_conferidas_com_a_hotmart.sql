-- 20260928z45 — Parcelamento Hotmart: o razão é o que a API da Hotmart diz, parcela por parcela (polimento, rodada 3).
-- No parcelamento Hotmart (HOTMART_INSTALLMENTS) cada parcela é uma TRANSAÇÃO própria na API. cs.fn_hm_lancar_compra,
-- ao receber a parcela N, grava N linhas com a transação da parcela N e datas estimadas para trás (a Hotmart "não reenvia
-- as anteriores"). Quando as anteriores também chegam, a mesma parcela entra duas vezes; quando o webhook de uma parcela
-- se perde, ela nunca entra.
-- Medido (42 parcelamentos com lançamento Hotmart): 5 divergem da API — 2 com parcela contada em dobro (+R$ 2.771,98),
-- 3 com parcelas faltando (−R$ 21.386,35: uma 1ª parcela de HM; 3 e 4 parcelas de Aurum). 1 com o mesmo total e a
-- transação trocada.
-- fin.reconciliar_parcelas(): para cada (comprador, oferta) parcelada cujo conjunto de transações no razão difere do da
-- API (espelho fin, grupo 'pago'), refaz o conjunto — tira a linha estimada/duplicada, põe a parcela real que faltava
-- (data real, compra_id quando existe) — deixa interação no card e recalcula o financeiro. Só mexe em lançamento de
-- origem 'hotmart'; manual/csv ficam. Roda agora e de hora em hora (:27, depois do estorno das :23). Idempotente.
create or replace function fin.parcelas_hotmart(p_comprador uuid, p_oferta text)
returns table (transacao text, valor numeric, aprovado_em timestamptz)
language sql stable set search_path = '' as $$
  with em as (
    select distinct coalesce(substr(i2.no, 3), lower(btrim(c.email))) email
      from public.compradores c
      left join fin.identidade i on i.no = 'e:' || lower(btrim(c.email))
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
     where c.id = p_comprador
    union
    select lower(btrim(c2.email)) from cs.hm_comprador_alias a join public.compradores c2 on c2.id = a.comprador_id
     where a.canonico_id = p_comprador
  )
  select distinct t.transacao, t.valor_oferta, t.aprovado_em
    from em join fin.vw_transacoes t on t.email = em.email
   where t.oferta_codigo = p_oferta and t.grupo = 'pago' and t.oferta_modo like 'HOTMART_INSTALLMENTS%'
$$;

create or replace function fin.reconciliar_parcelas()
returns int language plpgsql security definer set search_path = '' as $$
declare g record; v_cat text; v_antes numeric; v_depois numeric; v_card uuid; n int := 0;
begin
  for g in
    select x.comprador_id, x.oferta_codigo
      from (select distinct p.comprador_id, p.oferta_codigo
              from cs.hm_pagamentos p
             where p.metodo_pagamento = 'HOTMART_INSTALLMENTS' and p.origem = 'hotmart' and p.oferta_codigo is not null) x
     where exists (select 1 from fin.parcelas_hotmart(x.comprador_id, x.oferta_codigo))
       and (select array_agg(l.transacao || ':' || coalesce(l.parcela, 1) order by l.transacao, coalesce(l.parcela, 1))
              from cs.hm_pagamentos l
             where l.comprador_id = x.comprador_id and l.oferta_codigo = x.oferta_codigo and l.origem = 'hotmart')
           is distinct from
           (select array_agg(m.transacao || ':1' order by m.transacao)
              from fin.parcelas_hotmart(x.comprador_id, x.oferta_codigo) m)
  loop
    select max(l.categoria), sum(l.valor) into v_cat, v_antes
      from cs.hm_pagamentos l
     where l.comprador_id = g.comprador_id and l.oferta_codigo = g.oferta_codigo and l.origem = 'hotmart';

    delete from cs.hm_pagamentos l
     where l.comprador_id = g.comprador_id and l.oferta_codigo = g.oferta_codigo and l.origem = 'hotmart'
       and (coalesce(l.parcela, 1) > 1
            or l.transacao is null
            or l.transacao not in (select m.transacao from fin.parcelas_hotmart(g.comprador_id, g.oferta_codigo) m));

    insert into cs.hm_pagamentos (comprador_id, categoria, valor, pago_em, origem, transacao, compra_id, oferta_codigo,
                                  metodo_pagamento, parcela, obs, autor)
    select g.comprador_id, v_cat, m.valor, m.aprovado_em, 'hotmart', m.transacao,
           (select k.id from public.compras k where k.hotmart_transaction = m.transacao limit 1),
           g.oferta_codigo, 'HOTMART_INSTALLMENTS', 1,
           'Parcela conferida com a API da Hotmart (financeiro, z45)', 'financeiro'
      from fin.parcelas_hotmart(g.comprador_id, g.oferta_codigo) m
     where not exists (select 1 from cs.hm_pagamentos l where l.transacao = m.transacao)
    on conflict do nothing;

    select sum(l.valor) into v_depois
      from cs.hm_pagamentos l
     where l.comprador_id = g.comprador_id and l.oferta_codigo = g.oferta_codigo and l.origem = 'hotmart';

    select ch.id into v_card from cs.contatos_hm ch
     where ch.comprador_id = g.comprador_id and cs.fn_hm_pagamento_do_produto(g.oferta_codigo, ch.produto)
     order by ch.criado_em limit 1;
    if v_card is not null then
      insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
      values (v_card, 'sistema',
              'Parcelas da oferta ' || g.oferta_codigo || ' conferidas com a API da Hotmart: razão tinha R$ '
              || trim(to_char(coalesce(v_antes, 0), '999G999G990D00')) || ', Hotmart confirma R$ '
              || trim(to_char(coalesce(v_depois, 0), '999G999G990D00'))
              || ' (parcela duplicada ou que faltava — conferência automática do financeiro)', 'financeiro');
    end if;
    perform cs.fn_hm_recalcular_financeiro(g.comprador_id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function fin.reconciliar_parcelas() from public, anon, authenticated;
revoke all on function fin.parcelas_hotmart(uuid, text) from public, anon, authenticated;

select fin.reconciliar_parcelas();

select cron.schedule('fin-parcelas-conferidas', '27 * * * *', $$select fin.reconciliar_parcelas()$$);
