-- 20260928z23 — Calendário das turmas do AURUM (A1–A11), ESTIMADO pelas vendas (João, 28/09: "se não tiver resposta, dá
-- uma estimativa com base em dados concretos"). public.thb_turmas tem A1–A10 sem data; o Drive não tem o calendário.
-- Método: semanas com pico de compradores NOVOS de Aurum (1ª compra paga por pessoa, fin.identidade) × mediana da 1ª
-- compra dos alunos de cada turma (thb_alunos.turma_aurum_id). Os dois batem:
--   A1 05/07/2021 (92 novos em 4 semanas; mediana 11/07) · A2 18/04/2022 (52) · A3 14/11/2022 (50) ·
--   A4 03/07/2023 (69; mediana 09/07 — Encontro THB ed. 1) · A5 04/12/2023 (20; mediana 10/12) ·
--   A6 01/07/2024 (22; mediana 07/07 — Encontro THB 2024) · A7 25/11/2024 (54; mediana 26/11) ·
--   A8 14/07/2025 (39; mediana 27/07 — Congresso) · A9 15/12/2025 (28; mediana 16/12 — ETHB 2025) ·
--   A10 19/04/2026 (mediana 20/04 — Clínica Goiânia; segue na Clínica POA de 06/2026) · A11 03/08/2026 (ETHB SP; 28).
-- A11 não existe em thb_turmas: é a numeração seguinte, marcada como estimada.
insert into fin.acoes (produto, nome, canal, turma, inicio, fim, sck_regex, prioridade, fonte)
select 'AURUM', v.turma || ' · Aurum — ' || to_char(v.ini, 'MM/YYYY') || ' (estimada pelas vendas)', 'Aurum', v.turma,
       (v.ini::timestamp at time zone 'America/Sao_Paulo'),
       (coalesce(lead(v.ini) over (order by v.ini), date '2027-01-01')::timestamp at time zone 'America/Sao_Paulo'),
       null, 50, 'estimativa: picos de compradores novos de Aurum × mediana da 1ª compra por turma (thb_alunos)'
  from (values ('A1', date '2021-07-05'), ('A2', date '2022-04-18'), ('A3', date '2022-11-14'), ('A4', date '2023-07-03'),
               ('A5', date '2023-12-04'), ('A6', date '2024-07-01'), ('A7', date '2024-11-25'), ('A8', date '2025-07-14'),
               ('A9', date '2025-12-15'), ('A10', date '2026-04-19'), ('A11', date '2026-08-03')) v(turma, ini)
 where not exists (select 1 from fin.acoes a where a.produto = 'AURUM' and a.turma = v.turma and a.prioridade = 50);

-- a ação do ETHB SP era marcada "A8" (herança da janela antiga); pela contagem é a A11
update fin.acoes set turma = 'A11' where produto = 'AURUM' and nome like 'ETHB São Paulo%' and turma = 'A8';
