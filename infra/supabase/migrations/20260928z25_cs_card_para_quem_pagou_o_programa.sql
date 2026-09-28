-- 20260928z25 — Card para quem PAGOU oferta do Programa e ficou sem card (João, 28/09: "corrija todos os buracos";
-- sobre o saldo do Acelera: "são pessoas que a gente calculou o saldo com base no que pagaram do Acelera — elas pagaram").
-- Causa: as ofertas de saldo pós-Acelera (5o3z1yur, yzih2l0a, hyopam51, cnfrh6wj, p4t1xid7, t2vejhvv) entraram no
-- catálogo em 09/09, DEPOIS de as compras chegarem; o gatilho trg_seed_contato_hm só roda na chegada (ou na virada para
-- aprovado), então essas compras nunca viraram card nem pagamento. Mesmo caso para v13z0o19 (boleto parcelado).
-- Refaz, uma vez, o MESMO caminho do webhook (ramo 'diferenca'/'compra_cheia' de cs.fn_seed_contato_hm):
-- card em "Pendente de Liberação", interação de sistema, cs.fn_tag_hm_origem, cs.fn_hm_lancar_compra (pagamentos) e
-- cs.fn_hm_provisionar_aluno. Idempotente: só pessoa sem card do produto; lançar_compra tem on conflict por transação.
-- FORA, de propósito: 1v92rpey, 7ycm05gs, kf4tnech (ofertas avulsas do comercial, 4 pessoas) — o pacote fechado com o
-- vendedor não está em lugar nenhum; inventar criaria dívida errada. Ficam no bloco "pagaram sem card" do board.
do $do$
declare
  r record; v_prod text; v_turma text; v_pend smallint; v_id uuid; v_val record; v_aluno uuid; k record;
  n_card int := 0; n_pag int := 0;
begin
  select id into v_pend from cs.estagios where evento = 'HM' and chave = 'hm_pendente_liberacao' limit 1;
  for r in
    select distinct on (dono) dono, c.id compra_id, c.oferta_codigo, c.produto_id, cat.categoria, cat.notes,
           coalesce(c.data_aprovacao, c.data_compra) quando
      from (select q.*, coalesce((select a.canonico_id from cs.hm_comprador_alias a where a.comprador_id = q.comprador_id), q.comprador_id) dono
              from public.compras q
             where q.status in ('APPROVED','COMPLETE','COMPLETED')
               and q.oferta_codigo in ('5o3z1yur','yzih2l0a','hyopam51','cnfrh6wj','p4t1xid7','t2vejhvv','v13z0o19')
               and coalesce(q.data_aprovacao, q.data_compra) >= timestamptz '2026-06-25 00:00+00') c
      join public.hm_product_catalog cat on cat.offer_code = c.oferta_codigo
     where not exists (select 1 from cs.contatos_hm ch where ch.comprador_id = c.dono
                         and coalesce(ch.produto, 'HM') = coalesce(cs.fn_hm_produto_da_oferta(c.oferta_codigo, c.produto_id), 'HM'))
     order by dono, coalesce(c.data_aprovacao, c.data_compra)
  loop
    v_prod := cs.fn_hm_produto_da_oferta(r.oferta_codigo, r.produto_id);
    v_turma := cs.fn_hm_turma_por_data(r.quando);
    insert into cs.contatos_hm (comprador_id, produto, estagio_id, turma, plano, categoria_entrada, apto_ativacao, pagamento_em, entrada_em)
    values (r.dono, v_prod, v_pend, v_turma, coalesce(r.notes, 'saldo'), r.categoria, true, r.quando, r.quando)
    on conflict (comprador_id, produto) do nothing
    returning id into v_id;
    if v_id is null then continue; end if;
    n_card := n_card + 1;
    insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
    values (v_id, 'sistema', 'Card criado pelo financeiro em 28/09/2026: pagamento aprovado em '
            || to_char(r.quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ' pela oferta ' || r.oferta_codigo
            || ', que ainda não estava no catálogo quando a compra chegou — o webhook não tinha criado o card', 'financeiro');
    begin perform cs.fn_tag_hm_origem(r.dono); exception when others then null; end;
    for k in select c2.id from public.compras c2
              where coalesce((select a.canonico_id from cs.hm_comprador_alias a where a.comprador_id = c2.comprador_id), c2.comprador_id) = r.dono
                and c2.status in ('APPROVED','COMPLETE','COMPLETED')
                and exists (select 1 from public.hm_product_catalog cat2 where cat2.offer_code = c2.oferta_codigo
                             and cat2.categoria in ('sinal','diferenca','compra_cheia'))
    loop
      if cs.fn_hm_lancar_compra(k.id) is not null then n_pag := n_pag + 1; end if;
    end loop;
    begin
      select * into v_val from cs.fn_hm_valores_derivados(r.dono);
      v_aluno := cs.fn_hm_provisionar_aluno(r.dono, v_val.valor_total, v_val.valor_pago);
    exception when others then
      insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
      values (v_id, 'sistema', 'Falha ao criar o aluno na base THB (' || sqlerrm || ')', 'financeiro');
    end;
  end loop;
  raise notice 'cards criados: %, pagamentos lançados: %', n_card, n_pag;
end $do$;
