-- 20260928z40 — Polimento, rodada 2: saldo Aurum pago por oferta fora do catálogo.
-- 07tj9ipj: R$ 57.700,03 em 12x no cartão (28/08/2026), 1 pessoa — que JÁ tem card no Aurum (sinal qm4lu7py R$ 1.000).
-- Sem catálogo, o webhook não lançou o saldo e o card mostrava só o sinal (dívida falsa de ~R$ 57 mil).
-- Mesma natureza de fysepc10/vg96e2tc/z950cse4 (Saldo Aurum): 'diferenca', papel 'saldo'. Lança pelo razão oficial.
insert into public.hm_product_catalog
  (product_id, offer_code, product_name, categoria, papel, nome_comercial, explicacao, origem_do_dado, atualizado_por, atualizado_em)
select k.produto_id::text, '07tj9ipj', 'Aurum', 'diferenca', 'saldo', 'Aurum',
       'Saldo Aurum em 12x no cartão (R$ 57.700,03). 1 pagamento em 28/08/2026. Catalogada no polimento de 28/09 (z40).',
       'manual', 'financeiro z40', now()
  from public.compras k where k.oferta_codigo = '07tj9ipj' limit 1
on conflict (offer_code) do nothing;

do $do$
declare r record;
begin
  for r in select k.id, k.comprador_id from public.compras k
            where k.oferta_codigo = '07tj9ipj' and k.status in ('APPROVED','COMPLETE','COMPLETED')
  loop
    perform cs.fn_hm_lancar_compra(r.id);
    perform cs.fn_hm_recalcular_financeiro(cs.fn_hm_dono_do_pagamento(r.comprador_id));
  end loop;
end $do$;
