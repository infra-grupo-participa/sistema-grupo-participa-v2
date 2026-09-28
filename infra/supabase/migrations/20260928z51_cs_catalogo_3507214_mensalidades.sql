-- 20260928z51 — Catálogo: as 12 ofertas do produto 3507214 ("Holding - Holding Masters") que o catálogo não conhecia.
-- NÃO APLICADA — coordenador aplica.
--
-- O 3507214 é a MENSALIDADE de um plano antigo do Holding Masters, paga no cartão (definição do Marcio, 28/09).
-- Medido pelo coordenador em 28/09: 10 destas ofertas têm pagamento (R$ 637.830) e 2 não têm. Fora do catálogo elas só
-- acendem o alerta falso de oferta órfã (fn_fin_ofertas_sem_catalogo, z28) — não há card a criar nem acesso a dar
-- (decisão 4 do Marcio: mensalidade não dá acesso ao GPS e não passa pela fila de ativação).
--
-- Molde EXATO da hfoem61t (z39): categoria 'renovacao', papel NULL, product_type NULL (coluna omitida, como na z39),
-- concede_trilha false, recorrente true, origem 'manual'. on conflict do nothing: oferta já catalogada não é tocada.
--
-- PRÉ-CHECAGEM (rodar ANTES de aplicar; esperado: 0 linhas — o insert não pode disparar reprocessamento de compra):
--   select tgname, tgfoid::regprocedure from pg_trigger
--    where tgrelid = 'public.hm_product_catalog'::regclass and not tgisinternal;
--
-- REVERSÃO:
--   delete from public.hm_product_catalog where atualizado_por = 'financeiro z51';
insert into public.hm_product_catalog
  (product_id, offer_code, product_name, categoria, papel, nome_comercial, explicacao, origem_do_dado, atualizado_por, atualizado_em, concede_trilha, recorrente)
select '3507214', o.codigo, 'Holding - Holding Masters', 'renovacao', null, 'HM antigo em mensalidades (cartão)',
       'Mensalidade de plano antigo do Holding Masters, paga no cartão (produto 3507214, assinatura). Não cria card, não '
       || 'entra na fila de ativação nem concede trilha; aparece à parte no bloco "Assinatura HM" do board. '
       || 'Catalogada em 28/09 (z51) para sair do alerta de oferta órfã.',
       'manual', 'financeiro z51', now(), false, true
  from (values ('7r91uhzf'), ('dfgtpzkf'), ('z32y6wpw'), ('itzn9ned'), ('9gf90f2o'), ('jqhtq3m1'),
               ('wnzgsaop'), ('6rl13gqc'), ('04sh8t0k'), ('al0hm1ts'), ('ins5j0qh'), ('upz5jddn')) o(codigo)
on conflict (offer_code) do nothing;

-- ─── Prova (só SELECT) ────────────────────────────────────────────────────────────────────────────────────────────────
/*
-- A) As 19 ofertas do 3507214 no catálogo (esperado: 12 com atualizado_por 'financeiro z51', todas renovacao / product_type
--    NULL / concede_trilha false / recorrente true; as 7 antigas intocadas).
select offer_code, categoria, product_type, concede_trilha, recorrente, atualizado_por
  from public.hm_product_catalog where product_id = '3507214' order by atualizado_por, offer_code;

-- B) Alerta de órfã some (esperado: 0 compras do 3507214 sem oferta catalogada).
select count(*) from public.compras k
 where k.produto_id::text = '3507214' and k.oferta_codigo is not null
   and not exists (select 1 from public.hm_product_catalog c where c.offer_code = k.oferta_codigo);
*/
