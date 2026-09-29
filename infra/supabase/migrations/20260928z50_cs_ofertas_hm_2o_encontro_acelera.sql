-- 20260928z50 — Ofertas do 2º Encontro Acelera Holding (28/09/2026, 19h), criadas pelo Arthur às 21:33:
-- "Ofertas da Implementação para os alunos do Acelera" — HM (produto 5064314) com desconto de Acelera Holding:
--   506c1lz1  R$ 1.499  (para quem pagou 2.997 no Acelera)
--   3kojl3fv  R$ 1.249  (para quem pagou 2.497 no Acelera)
--   mhfkfbdi  R$   999  (para quem pagou 1.997 no Acelera)
-- Mesma natureza das "HM com desconto de Acelera Holding" anteriores (5o3z1yur, yzih2l0a, t2vejhvv, hyopam51):
-- 'diferenca'. Catalogadas ANTES da 1ª venda — o gatilho trg_seed_contato_hm só cria card para oferta que já está
-- no catálogo quando a compra chega (foi o buraco de 09/09).
-- E a ação do board: todo card de HM que entrar a partir das 19h de 28/09 cai em "2º Encontro Acelera Holding".
insert into public.hm_product_catalog
  (product_id, offer_code, product_name, categoria, nome_comercial, explicacao, origem_do_dado, atualizado_por, atualizado_em, valor_tabela)
values
  ('5064314', '506c1lz1', 'Holding Masters', 'diferenca', 'HM com desconto de Acelera Holding',
   '2º Encontro Acelera (28/09/2026): R$ 1.499 para quem pagou R$ 2.997 no Acelera. Oferta do Arthur.', 'manual', 'financeiro z50', now(), 1499),
  ('5064314', '3kojl3fv', 'Holding Masters', 'diferenca', 'HM com desconto de Acelera Holding',
   '2º Encontro Acelera (28/09/2026): R$ 1.249 para quem pagou R$ 2.497 no Acelera. Oferta do Arthur.', 'manual', 'financeiro z50', now(), 1249),
  ('5064314', 'mhfkfbdi', 'Holding Masters', 'diferenca', 'HM com desconto de Acelera Holding',
   '2º Encontro Acelera (28/09/2026): R$ 999 para quem pagou R$ 1.997 no Acelera. Oferta do Arthur.', 'manual', 'financeiro z50', now(), 999)
on conflict (offer_code) do nothing;

insert into fin.acoes (produto, nome, canal, turma, inicio, fim, prioridade, fonte)
select 'HM', '2º Encontro Acelera Holding (28/09/2026)', 'Acelera Holding', 'T41',
       timestamptz '2026-09-28 22:00+00', timestamptz '2026-10-06 03:00+00', 30,
       'ofertas do Arthur no WhatsApp, 28/09 21:33 (506c1lz1, 3kojl3fv, mhfkfbdi)'
 where not exists (select 1 from fin.acoes where nome like '2º Encontro Acelera Holding%');
