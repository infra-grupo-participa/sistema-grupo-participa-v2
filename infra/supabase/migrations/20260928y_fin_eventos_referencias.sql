-- 20260928y — Funis: janelas exatas de carrinho e o resultado DECLARADO pela equipe na época (28/09/2026).
-- Fontes (Drive › EVENTOS):
--   * "Dados para Análise" (3) EVENTOS 2022): Lançamentos T11–T17 (abertura/fechamento de carrinho, recuperação,
--     vendas e "Arrecadação/Comissões" = comissão do produtor) e Seminários S1–S3/2022 (carrinho de Sessão de Viabilidade).
--   * "Métricas dos Lançamentos de 2021" (2) EVENTOS 2021): LI1T8 (carrinho 01–04/02/2021, recuperação 08/02).
--   * "Base Histórica de Eventos - Métricas" (Mapeamento Histórico): seminários 2026, Clínicas GO/POA, live ex-HM.
-- ref_* NUNCA é usado como dinheiro — é a conferência. O dinheiro sai do espelho da Hotmart; a tela mostra os dois
-- lado a lado e a diferença.
alter table fin.eventos
  add column if not exists carrinho_inicio date,
  add column if not exists ref_vendas int,
  add column if not exists ref_valor numeric,
  add column if not exists ref_tipo text,
  add column if not exists ref_fonte text;

-- Jornadas 2021–2022 (Curso Prático de Holding Familiar)
update fin.eventos set carrinho_inicio = '2021-02-01', venda_ate = '2021-02-08', ref_vendas = 123, ref_valor = 423028.54, ref_tipo = 'comissao',
  ref_fonte = 'Métricas dos Lançamentos de 2021 › LI1T82021 (curso; + VIP R$ 8.637,31 → total R$ 431.665,85)' where categoria = 'jornada' and inicio = '2021-02-01';
update fin.eventos set ref_vendas = 369, ref_fonte = 'Mapeamento Histórico (debriefing LI2T9)' where categoria = 'jornada' and inicio = '2021-03-25';
update fin.eventos set ref_vendas = 463, ref_valor = 2105562.70, ref_tipo = 'nao_informado', ref_fonte = 'Mapeamento Histórico (debriefing LI3T10)' where categoria = 'jornada' and inicio = '2021-05-11';
update fin.eventos set carrinho_inicio = '2021-08-26', venda_ate = '2021-09-04', ref_vendas = 342, ref_valor = 1540385.53, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise › Lançamentos (carrinho 26–31/08/2021)' where categoria = 'jornada' and inicio = '2021-08-17';
insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, codigo, fonte, observacao, ref_vendas, ref_valor, ref_tipo, ref_fonte) values
 ('Jornada de Holding Familiar (T12)', 'jornada', 'educacao', '2021-10-18', '2021-10-26', '2021-10-26', '2021-10-21', 'T12', 'Dados para Análise',
  'Mapeamento Histórico cita outro número: 237 vendas, R$ 1.302.290,10 líquido', 223, 1046933.70, 'comissao', 'Dados para Análise › Lançamentos (carrinho 21–26/10/2021)'),
 ('Jornada de Holding Familiar (T13)', 'jornada', 'educacao', '2021-12-06', '2021-12-15', '2021-12-15', '2021-12-11', 'T13', 'Dados para Análise',
  'dia de início das aulas não identificado', 60, 270385.21, 'comissao', 'Dados para Análise › Lançamentos (carrinho 11–15/12/2021)')
on conflict (categoria, inicio) do nothing;
update fin.eventos set carrinho_inicio = '2022-01-27', venda_ate = '2022-02-23', ref_vendas = 626, ref_valor = 2185556.83, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise (carrinho 27/01–01/02/2022; recuperação 02–23/02)' where categoria = 'jornada' and inicio = '2022-01-24';
update fin.eventos set carrinho_inicio = '2022-03-24', venda_ate = '2022-04-14', ref_vendas = 621, ref_valor = 2150575.76, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise (carrinho 24–29/03/2022; recuperação 30/03–14/04)' where categoria = 'jornada' and inicio = '2022-03-21';
update fin.eventos set carrinho_inicio = '2022-06-02', venda_ate = '2022-06-15', ref_vendas = 573, ref_valor = 2162400.01, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise (carrinho 02–07/06/2022; recuperação 08–15/06)' where categoria = 'jornada' and inicio = '2022-05-30';
update fin.eventos set carrinho_inicio = '2022-07-28', venda_ate = '2022-08-10', ref_vendas = 630, ref_valor = 2117513.82, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise (carrinho 28/07–02/08/2022; aba Página3 soma 601)' where categoria = 'jornada' and inicio = '2022-07-25';

-- Seminários 2022 (Sessão de Viabilidade — conta do escritório)
update fin.eventos set carrinho_inicio = '2022-02-17', venda_ate = '2022-02-23', ref_vendas = 23, ref_valor = 18930.56, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise › Seminários S1.FEV.2022 (carrinho 17–21/02; recuperação 22–23/02)' where categoria = 'seminario_marcio' and inicio = '2022-02-15';
update fin.eventos set carrinho_inicio = '2022-04-14', venda_ate = '2022-04-20', ref_vendas = 31, ref_valor = 32003.66, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise › Seminários S2.ABR.2022 (carrinho 14–18/04; recuperação 19–20/04)' where categoria = 'seminario_marcio' and inicio = '2022-04-12';
update fin.eventos set carrinho_inicio = '2022-06-23', venda_ate = '2022-07-02', ref_vendas = 60, ref_valor = 54828.06, ref_tipo = 'comissao',
  ref_fonte = 'Dados para Análise › Seminários S3.JUN.2022 (carrinho 23–27/06; recuperação 28/06–02/07)' where categoria = 'seminario_marcio' and inicio = '2022-06-21';

-- 2026 (Base Histórica de Eventos - Métricas)
update fin.eventos set ref_vendas = 4, ref_fonte = 'Base Histórica › Métricas dos Seminários (4 SV brutas, 1 reembolsada)' where categoria = 'seminario_marcio' and inicio = '2026-02-02';
update fin.eventos set ref_vendas = 13, ref_fonte = 'Base Histórica › Métricas dos Seminários' where categoria = 'seminario_elaine' and inicio = '2026-04-27';
update fin.eventos set ref_vendas = 15, ref_valor = 18000, ref_tipo = 'nao_informado', ref_fonte = 'Base Histórica › Métricas dos Seminários (R$ 18.000 de SV, não identificado se líquido)' where categoria = 'seminario_elaine' and inicio = '2026-06-15';
update fin.eventos set ref_vendas = 7, ref_fonte = 'Base Histórica › Métricas dos Seminários (35 checkouts, 20%)' where categoria = 'seminario_elaine' and inicio = '2026-07-16';
update fin.eventos set ref_vendas = 26, ref_fonte = 'Base Histórica › provisório: 26 SV + 6 croquis' where categoria = 'seminario_elaine' and inicio = '2026-07-28';
update fin.eventos set ref_vendas = 66, ref_valor = 95597.18, ref_tipo = 'liquido', ref_fonte = 'Base Histórica › Métricas das Clínicas (66 ingressos; oferta Aurum: 11 sinais, R$ 21.109)' where categoria = 'clinica' and inicio = '2026-04-19';
update fin.eventos set ref_vendas = 88, ref_valor = 100372.90, ref_tipo = 'bruto', ref_fonte = 'Base Histórica › Métricas das Clínicas (88 ingressos; oferta Aurum: 8 vendas)' where categoria = 'clinica' and inicio = '2026-06-09';
update fin.eventos set ref_vendas = 44, ref_fonte = 'Base Histórica (planilha de vendas EX-HMs ATM)' where categoria = 'live_hm' and inicio = '2026-07-13';
update fin.eventos set ref_vendas = 25, ref_fonte = 'Mapeamento Histórico (HT22: 25 ingressos)' where categoria = 'holding_total' and inicio = '2026-04-06';
