-- 20260928z39 — Polimento, rodada 2: as ofertas pagas do HM que o catálogo não conhecia (João, 28/09: "corrija todos os
-- buracos"; "enquanto não bater 100%, roda mais uma vez").
--
-- Acordos individuais do comercial (produto 5064314, depois do marco 25/06/2026):
--   1v92rpey  R$ 6.250,50 em 10x — 2 pessoas (24/09)
--   kf4tnech  R$ 7.972,60 em 5x  — 1 pessoa (10/09; ex-aluna HM R$ 15 mil de fev/2026)
--   7ycm05gs  R$ 6.000,00 à vista — 1 pessoa (25/09, na HT32; ex-aluna HM 2024 e Aurum 2025)
-- Entram como 'diferenca' / papel 'acordo_individual' (mesma natureza de cnfrh6wj e p4t1xid7, "saldo individual do
-- Programa"): o valor pago é o acordo fechado — z38 faz o pacote ser a soma paga quando não há sinal nem compra cheia.
-- A z25 deixou estes de fora por não conhecer o pacote; o valor da oferta É o acordo, e o pagamento foi integral
-- (cartão parcelado pela Hotmart repassa o total).
--
-- HM antigo em mensalidades (produto 3507214): hfoem61t R$ 3.500 x 6 (set/2025 em diante, 3 pessoas, anterior ao
-- Programa). Entra como 'renovacao' e sem trilha: fica classificado sem criar card nem lançar no razão do Programa.
insert into public.hm_product_catalog
  (product_id, offer_code, product_name, categoria, papel, nome_comercial, explicacao, origem_do_dado, atualizado_por, atualizado_em, concede_trilha, recorrente)
values
  ('5064314', '1v92rpey', 'Holding Masters', 'diferenca', 'acordo_individual', 'Acordo individual do Programa',
   'Oferta avulsa do comercial, R$ 6.250,50 em 10x. 2 pagamentos em 24/09/2026. Catalogada no polimento de 28/09 (z39).',
   'manual', 'financeiro z39', now(), true, false),
  ('5064314', 'kf4tnech', 'Holding Masters', 'diferenca', 'acordo_individual', 'Acordo individual do Programa',
   'Oferta avulsa do comercial, R$ 7.972,60 em 5x. 1 pagamento em 10/09/2026. Catalogada no polimento de 28/09 (z39).',
   'manual', 'financeiro z39', now(), true, false),
  ('5064314', '7ycm05gs', 'Holding Masters', 'diferenca', 'acordo_individual', 'Acordo individual do Programa',
   'Oferta avulsa do comercial, R$ 6.000 à vista, vendida na HT32. 1 pagamento em 25/09/2026. Catalogada no polimento de 28/09 (z39).',
   'manual', 'financeiro z39', now(), true, false),
  ('3507214', 'hfoem61t', 'Holding - Holding Masters', 'renovacao', null, 'HM antigo em 6 mensalidades de R$ 3.500',
   'Assinatura do HM anterior ao Programa (set/2025 em diante, 3 pessoas). Não cria card nem entra no razão do Programa. Catalogada em 28/09 (z39).',
   'manual', 'financeiro z39', now(), false, true)
on conflict (offer_code) do nothing;

-- Cards pelo MESMO caminho do webhook (igual à z25).
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
               and q.oferta_codigo in ('1v92rpey','kf4tnech','7ycm05gs')
               and coalesce(q.data_aprovacao, q.data_compra) >= timestamptz '2026-06-25 00:00+00') c
      join public.hm_product_catalog cat on cat.offer_code = c.oferta_codigo
     where not exists (select 1 from cs.contatos_hm ch where ch.comprador_id = c.dono
                         and coalesce(ch.produto, 'HM') = coalesce(cs.fn_hm_produto_da_oferta(c.oferta_codigo, c.produto_id), 'HM'))
     order by dono, coalesce(c.data_aprovacao, c.data_compra)
  loop
    v_prod := cs.fn_hm_produto_da_oferta(r.oferta_codigo, r.produto_id);
    v_turma := cs.fn_hm_turma_por_data(r.quando);
    insert into cs.contatos_hm (comprador_id, produto, estagio_id, turma, plano, categoria_entrada, apto_ativacao, pagamento_em, entrada_em)
    values (r.dono, v_prod, v_pend, v_turma, coalesce(r.notes, 'Acordo individual do Programa'), r.categoria, true, r.quando, r.quando)
    on conflict (comprador_id, produto) do nothing
    returning id into v_id;
    if v_id is null then continue; end if;
    n_card := n_card + 1;
    insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
    values (v_id, 'sistema', 'Card criado pelo financeiro em 28/09/2026: pagamento aprovado em '
            || to_char(r.quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ' pela oferta ' || r.oferta_codigo
            || ' (acordo individual do comercial), que não estava no catálogo — o webhook não tinha criado o card', 'financeiro');
    begin perform cs.fn_tag_hm_origem(r.dono); exception when others then null; end;
    for k in select c2.id from public.compras c2
              where coalesce((select a.canonico_id from cs.hm_comprador_alias a where a.comprador_id = c2.comprador_id), c2.comprador_id) = r.dono
                and c2.status in ('APPROVED','COMPLETE','COMPLETED')
                and coalesce(c2.data_aprovacao, c2.data_compra) >= timestamptz '2026-06-25 00:00+00'
                and exists (select 1 from public.hm_product_catalog cat2 where cat2.offer_code = c2.oferta_codigo
                             and cat2.categoria in ('sinal','diferenca','compra_cheia'))
    loop
      if cs.fn_hm_lancar_compra(k.id) is not null then n_pag := n_pag + 1; end if;
    end loop;
    -- o acordo é o pacote do card: só o dinheiro do Programa (compra de HM antes do marco não entra — é a turma de origem)
    update cs.contatos_hm set valor_total = (select sum(p.valor) from cs.hm_pagamentos p where p.comprador_id = r.dono)
     where id = v_id;
    begin
      select ch.valor_total as valor_total into v_val from cs.contatos_hm ch where ch.id = v_id;
      v_aluno := cs.fn_hm_provisionar_aluno(r.dono, v_val.valor_total, v_val.valor_total);
    exception when others then
      insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
      values (v_id, 'sistema', 'Falha ao criar o aluno na base THB (' || sqlerrm || ')', 'financeiro');
    end;
    perform cs.fn_hm_recalcular_financeiro(r.dono);
  end loop;
  raise notice 'z39: cards criados: %, pagamentos lançados: %', n_card, n_pag;
end $do$;
