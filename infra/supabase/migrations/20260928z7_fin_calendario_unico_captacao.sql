-- 20260928z7 — Calendário ÚNICO de captação do HM/Aurum (João, 28/09/2026: "preciso saber de onde vem cada pessoa de cada
-- família desde que a gente começou o programa"; escolheu "calendário único, o do Drive").
--
-- Antes: a origem do card vinha 1º da janela antiga (cs.hm_evento_janela, só 2026, por data) e as ações de fin.acoes só
-- cobriam mai–set/2026. Resultado: "Seminário ATM" no HM, cards que pagaram em jan/2026 marcados "HT ATM T39" (julho),
-- 16 cards "Base antiga" sem turma.
-- Agora: fin.acoes = calendário de captação por TURMA do HM, ligado a fin.eventos (a mesma lista da aba Funis):
--   T5–T17 Jornadas (2020–22) · T18 lançamento pago (dez/22) · T19–T38 = HT1–HT20 · T39 = HT21–HT27 + lives/reuniões de
--   2026 · T40 = HT29/HT30/HT ATM 23/08 · T41 = Acelera + Imersão HT32.
--   Fonte da turma × edição: Drive "[HT] Catálogo de Ofertas" (1JCpGs9EmG1lBgomAe-XF8zwEFWBkztS3UhVvBoVj5E4).
-- Regra do card (a 1ª que responde): link de venda → evento acontecendo no dia da compra (vence o comercial: ETHB SP teve
-- 31 vendas de Aurum pelo link do comercial) → link do comercial → janela da turma (depois do evento) → "Base (fora de evento)". A janela antiga deixa de mandar. cs.hm_evento_janela NÃO é tocada.
-- Valores de dinheiro do board: intocados (só acao_* muda).

alter table fin.eventos add column if not exists turma_hm text;
alter table fin.acoes add column if not exists evento_id bigint references fin.eventos(id);

-- 1. turma de cada evento (Catálogo de Ofertas)
update fin.eventos e set turma_hm = m.turma
  from (values
    ('jornada', date '2020-06-01', 'T5'), ('jornada', date '2020-08-03', 'T6'), ('jornada', date '2020-11-04', 'T7'),
    ('jornada', date '2021-02-01', 'T8'), ('jornada', date '2021-03-25', 'T9'), ('jornada', date '2021-05-11', 'T10'),
    ('jornada', date '2021-08-17', 'T11'), ('jornada', date '2021-10-18', 'T12'), ('jornada', date '2021-12-06', 'T13'),
    ('jornada', date '2022-01-24', 'T14'), ('jornada', date '2022-03-21', 'T15'), ('jornada', date '2022-05-30', 'T16'),
    ('jornada', date '2022-07-25', 'T17'),
    ('holding_total', date '2022-12-03', 'T18'), ('certificacao', date '2023-01-23', 'T19'),
    ('holding_total', date '2023-03-31', 'T20'), ('holding_total', date '2023-05-19', 'T21'), ('holding_total', date '2023-08-04', 'T22'),
    ('holding_total', date '2023-09-15', 'T23'), ('holding_total', date '2023-11-10', 'T24'), ('holding_total', date '2024-01-12', 'T25'),
    ('holding_total', date '2024-03-07', 'T26'), ('holding_total', date '2024-05-03', 'T27'), ('holding_total', date '2024-08-01', 'T28'),
    ('holding_total', date '2024-11-01', 'T29'), ('holding_total', date '2025-02-07', 'T30'), ('holding_total', date '2025-05-23', 'T31'),
    ('holding_total', date '2025-07-04', 'T32'), ('holding_total', date '2025-09-05', 'T33'), ('holding_total', date '2025-10-03', 'T34'),
    ('holding_total', date '2025-11-27', 'T35'), ('holding_total', date '2026-01-13', 'T36'), ('holding_total', date '2026-02-24', 'T37'),
    ('holding_total', date '2026-03-14', 'T38'), ('holding_total', date '2026-04-06', 'T39'),
    ('live_hm', date '2026-06-25', 'T39'), ('live_hm', date '2026-07-13', 'T39'), ('encontro_thb', date '2026-08-04', 'T40')
  ) m(categoria, inicio, turma)
 where e.categoria = m.categoria and e.inicio = m.inicio;

-- 2. eventos de 2026 que só existiam nas ações do board entram no calendário (aparecem também na aba Funis)
insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, observacao, turma_hm) values
  ('Holding Total ATM — reunião fechada (06/07/2026)', 'holding_total', 'educacao', '2026-07-06', '2026-07-06', '2026-07-09', 'HT ATM', 'gp-operacoes + sck reuniao-fechada-0607', null, 'T39'),
  ('Holding Total (HT29)', 'holding_total', 'educacao', '2026-07-26', '2026-07-26', '2026-07-31', 'HT29', 'gp-operacoes (live HT29 26/07)', null, 'T40'),
  ('Holding Total (HT30)', 'holding_total', 'educacao', '2026-08-09', '2026-08-10', '2026-08-16', 'HT30', 'gp-operacoes série histórica §7 (oferta HM R$ 697)', null, 'T40'),
  ('Holding Total ATM (23/08/2026)', 'holding_total', 'educacao', '2026-08-23', '2026-08-23', '2026-08-26', 'HT ATM', 'sck ht-2308', null, 'T40'),
  ('Imersão Holding Total (HT32)', 'holding_total', 'educacao', '2026-09-26', '2026-09-27', '2026-09-30', 'HT32', 'gp-operacoes HT32 (oferta 6fceg8ye)', null, 'T41')
on conflict (categoria, inicio) do update set turma_hm = excluded.turma_hm;

-- 3. linhas históricas do HM (T5–T39) no calendário de captação; janela = do carrinho até o início da turma seguinte
--    (no máximo 45 dias depois do fim de vendas)
insert into fin.acoes (produto, nome, canal, turma, inicio, fim, sck_regex, prioridade, fonte, evento_id)
select 'HM',
       e.turma_hm || ' · ' || regexp_replace(e.nome, ' \(T\d+\)$', '') || ' — ' || to_char(e.inicio, 'MM/YYYY'),
       case when e.categoria = 'jornada' then 'Jornada' else 'Holding Total' end,
       e.turma_hm,
       (coalesce(e.carrinho_inicio, e.inicio)::timestamp at time zone 'America/Sao_Paulo'),
       null, null, 50, 'fin.eventos #' || e.id || ' + Catálogo de Ofertas (turma)', e.id
  from fin.eventos e
 where e.turma_hm is not null and e.inicio < date '2026-05-01'
   and e.categoria in ('jornada','holding_total','certificacao')
   and not exists (select 1 from fin.acoes a where a.evento_id = e.id);

update fin.acoes a set fim = x.fim
  from (select a2.id,
               least(lead(a2.inicio) over (order by a2.inicio),
                     ((e.venda_ate + 46)::timestamp at time zone 'America/Sao_Paulo')) fim
          from fin.acoes a2 join fin.eventos e on e.id = a2.evento_id
         where a2.produto = 'HM' and a2.prioridade = 50) x
 where a.id = x.id;
-- a T39 (HT21/22, abr/2026) vai até o LPSG (01/05)
update fin.acoes set fim = '2026-05-01 03:00+00' where produto = 'HM' and prioridade = 50 and turma = 'T39';

-- 4. ações de 2026: nome com a turma e ligação ao evento
update fin.acoes a set nome = v.novo, evento_id = (select id from fin.eventos e where e.categoria = v.cat and e.inicio = v.ini)
  from (values
    ('LPSG Holding Total (mai–jun/26)', 'T39 · LPSG Holding Total (mai–jun/2026)', null, null::date),
    ('Lançamento T39', 'T39 · Live Direto ao Ponto (25/06/2026)', 'live_hm', date '2026-06-25'),
    ('Reunião fechada 25/06 (pós-lançamento T39)', 'T39 · Reunião fechada (25/06/2026)', null, null),
    ('HT ATM T39', 'T39 · Holding Total ATM (06/07/2026)', 'holding_total', date '2026-07-06'),
    ('Ex aluno T39', 'T39 · Reunião ex-alunos HM (13/07/2026)', 'live_hm', date '2026-07-13'),
    ('Captação T40 — live HT29 de 26/07', 'T40 · Holding Total HT29 (26/07/2026)', 'holding_total', date '2026-07-26'),
    ('HT30 — 09 e 10/08', 'T40 · Holding Total HT30 (09–10/08/2026)', 'holding_total', date '2026-08-09'),
    ('HT ATM 23/08', 'T40 · Holding Total ATM (23/08/2026)', 'holding_total', date '2026-08-23'),
    ('Saldo com desconto Acelera (01–08/09)', 'T41 · Saldo com desconto Acelera (01–08/09/2026)', null, null),
    ('Imersão HT — 26 e 27/09/2026', 'T41 · Imersão Holding Total HT32 (26–27/09/2026)', 'holding_total', date '2026-09-26'),
    ('ETHB SP — captação Aurum', 'ETHB São Paulo (04–06/08/2026)', 'encontro_thb', date '2026-08-04')
  ) v(antigo, novo, cat, ini)
 where a.nome = v.antigo;

-- 5. a origem do card sai só do calendário
create or replace view fin.vw_acao_card as
with card as (
  select b.contato_hm_id, b.origem, lower(trim(b.email)) email, ch.criado_em entrada
    from cs.vw_fin_board b
    join cs.contatos_hm ch on ch.id = b.contato_hm_id
), emails as (
  select c.contato_hm_id, coalesce(substr(i2.no, 3), c.email) email
    from card c
    left join fin.identidade i on i.no = 'e:' || c.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
), primeira as (
  -- a compra que abriu o card: sinal/cheio do catálogo; senão a 1ª de 2026; senão a mais antiga
  select distinct on (c.contato_hm_id) c.contato_hm_id, t.aprovado_em, t.dia_aprovado, t.origem_sck
    from card c
    join emails e on e.contato_hm_id = c.contato_hm_id
    join fin.vw_transacoes t on t.email = e.email and t.familia = c.origem and t.grupo = 'pago'
    left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
   order by c.contato_hm_id, (cat.categoria in ('sinal','compra_cheia')) desc nulls last,
            (t.dia_aprovado >= date '2026-01-01') desc, t.aprovado_em
), base as (
  select c.*, p.aprovado_em, p.dia_aprovado, p.origem_sck,
         coalesce(p.aprovado_em, c.entrada) quando,
         coalesce(p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%', false) comercial
    from card c left join primeira p on p.contato_hm_id = c.contato_hm_id
)
select b.contato_hm_id,
       coalesce(s.nome, d.nome, case when b.comercial then 'Comercial (venda direta)' end, j.nome, 'Base (fora de evento)') acao_nome,
       coalesce(s.inicio, d.inicio, case when b.comercial then b.quando end, j.inicio, b.quando) acao_data,
       case when s.nome is not null then 'link de venda'
            when d.nome is not null and b.aprovado_em is null then 'data de entrada no board (dia do evento)'
            when d.nome is not null then 'dia do evento'
            when b.comercial then 'link do comercial'
            when j.nome is not null and b.aprovado_em is null then 'data de entrada no board'
            when j.nome is not null then 'depois do evento (turma)'
            when b.aprovado_em is null then 'sem compra paga'
            else 'fora de evento' end acao_regra,
       coalesce(s.canal, d.canal, case when b.comercial then 'Comercial' end, j.canal, 'Base (fora de evento)') acao_canal,
       b.dia_aprovado captado_em,
       b.origem_sck captado_sck
  from base b
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = b.origem and a.sck_regex is not null and b.origem_sck ~* a.sck_regex
                      order by a.prioridade, a.id limit 1) s on true
  left join lateral (select a.nome, a.inicio, a.canal, a.turma from fin.acoes a
                      where a.produto = b.origem and a.inicio is not null and a.fim is not null
                        and b.quando >= a.inicio and b.quando < a.fim
                      order by a.prioridade, a.id limit 1) j on true
  -- evento acontecendo no dia (do carrinho ao fim das vendas): vence o link do comercial — vendedor vendendo no evento
  left join lateral (select coalesce(ae.nome, coalesce(case when b.origem = 'HM' and j.turma is not null then j.turma || ' · ' end, '') || e.nome) nome,
                            (coalesce(e.carrinho_inicio, e.inicio)::timestamp at time zone 'America/Sao_Paulo') inicio,
                            coalesce(ae.canal, case e.categoria
                              when 'jornada' then 'Jornada' when 'holding_total' then 'Holding Total' when 'certificacao' then 'Holding Total'
                              when 'live_hm' then 'Live Direto ao Ponto' when 'clinica' then 'Clínica' when 'imersao' then 'Imersão'
                              when 'encontro_thb' then 'Encontro THB' when 'aurum_plus' then 'Aurum+' when 'congresso' then 'Congresso'
                              when 'diamantes' then 'Diamantes' when 'residencia' then 'Residência' when 'workshop' then 'Residência'
                              when 'lancamento_cnhf' then 'CNHF' else e.categoria end) canal
                       from fin.eventos e
                       left join lateral (select a.nome, a.canal from fin.acoes a where a.evento_id = e.id and a.produto = b.origem
                                           order by a.prioridade, a.id limit 1) ae on true
                      where e.setor = 'educacao'
                        and not (b.origem = 'HM' and e.categoria in ('aurum_plus','diamantes'))  -- evento só do Aurum/Diamante não capta HM
                        and (b.quando at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
                      order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1) d on true;
revoke all on fin.vw_acao_card from public, anon, authenticated;
