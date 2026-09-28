-- 20260928z15 — HT23 a HT28 (abr–jul/2026) entram no calendário único.
-- Achado da trajetória: ingressos do HT comprados em 16/05 e 20/06/2026 caíam no "HT ATM 06/07" porque o calendário pulava
-- do HT21/22 (abr) para julho. Fonte das datas: public.ht_editions (ciclos de 2 semanas do HT "perpétuo"; o dia exato de
-- cada evento não está registrado — vale o ciclo de vendas) + vendas semanais de ingresso 1560865 (25–48 por semana,
-- contínuas de abr a jul). Catálogo de Ofertas do Drive: T39 = HT21–HT27; HT28 (22/06–05/07) também é T39.
-- Os dois "HT ATM" de 2026 (06/07 e 23/08) são reunião fechada para a base, não vendem ingresso de HT: passam para
-- live_hm, senão roubavam a janela de ingresso do HT29.
update fin.eventos set categoria = 'live_hm'
 where categoria = 'holding_total' and inicio in (date '2026-07-06', date '2026-08-23') and codigo = 'HT ATM';

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, codigo, fonte, observacao, turma_hm) values
  ('Holding Total (HT23)', 'holding_total', 'educacao', '2026-04-13', '2026-04-26', '2026-04-26', '2026-04-13', 'HT23', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 13–26/04', 'T39'),
  ('Holding Total (HT24)', 'holding_total', 'educacao', '2026-04-27', '2026-05-10', '2026-05-10', '2026-04-27', 'HT24', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 27/04–10/05', 'T39'),
  ('Holding Total (HT25)', 'holding_total', 'educacao', '2026-05-11', '2026-05-24', '2026-05-24', '2026-05-11', 'HT25', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 11–24/05', 'T39'),
  ('Holding Total (HT26)', 'holding_total', 'educacao', '2026-05-25', '2026-06-07', '2026-06-07', '2026-05-25', 'HT26', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 25/05–07/06', 'T39'),
  ('Holding Total (HT27)', 'holding_total', 'educacao', '2026-06-08', '2026-06-21', '2026-06-21', '2026-06-08', 'HT27', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 08–21/06', 'T39'),
  ('Holding Total (HT28)', 'holding_total', 'educacao', '2026-06-22', '2026-07-05', '2026-07-05', '2026-06-22', 'HT28', 'public.ht_editions (ciclo de vendas)', 'dia exato do evento não registrado; vale o ciclo 22/06–05/07', 'T39')
on conflict (categoria, inicio) do nothing;

-- HT21/22 passa a valer só até o início do HT23 (antes ia até 15/04)
update fin.eventos set venda_ate = date '2026-04-12', fim = date '2026-04-12'
 where categoria = 'holding_total' and inicio = date '2026-04-06' and venda_ate > date '2026-04-12';
