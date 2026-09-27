-- 20260928n — Toda pessoa do board com a AÇÃO de onde veio (pedido do João, 27/09/2026):
-- "identificar em que setor estão os sem ação identificada e onde foi que a gente captou eles, base na data de compra
-- e data de venda… não pode ter uma pessoa sem o dado faltando". E: "tira o mapa dos alunos… aprimora o que a gente já tem".
--
-- Medido antes (27/09): 104 cards HM e 8 AURUM sem ação; 140 com canal "Não classificado". Causa: cs.hm_evento_janela tem só
-- 6 janelas (Lançamento T39, HT ATM T39, Ex aluno T39, HT29, Imersão HT, ETHB SP), e a ação só vinha da data do 1º sinal
-- dentro delas. 76 cards pagaram o sinal fora de todas (abr–ago/26).
--
-- NÃO se mexe em cs.hm_evento_janela: ela também alimenta cs.fn_sync_hm_atm, cs.fn_hm_janela_evento e o health-check do
-- sistema de disparos (etiquetas de canal). Mudar lá reclassificaria etiquetas fora do financeiro.
-- Aqui: fin.acoes (catálogo do financeiro) e fin.vw_acao_card (a ação de cada card), usados SÓ pelo board financeiro.
--
-- Regra da ação de um card, na ordem (a primeira que responde vence):
--   1. a janela antiga (cs.vw_fin_board.acao_nome) — o que já estava certo não muda;
--   2. o LINK DE VENDA (sck) da 1ª compra na Hotmart casa com o padrão de uma ação (decisão 27/09 do gp-operacoes:
--      "o dado da fonte de origem" — a venda diz de onde veio);
--   3. a DATA da 1ª compra cai na janela de uma ação;
--   4. link de venda do comercial → "Comercial (venda direta)";
--   5. 1ª compra antes de 2026 → "Base antiga (antes de 2026)";
--   6. nenhuma compra paga → "Sem pagamento ainda".
-- Datas e nomes das ações: calendário e série histórica do gp-operacoes (projetos/README.md,
-- departamentos/dados/areas/analise/serie-historica-holding-total.md) + os links de venda medidos em 27/09.

-- 0. O Mapa de alunos saiu (João, 27/09: "tira o mapa dos alunos… vai causar muita confusão").
drop function if exists public.fn_fin_mapa_alunos();

-- 1. Catálogo de ações do financeiro
create table if not exists fin.acoes (
  id          serial primary key,
  produto     text not null check (produto in ('HM','AURUM')),
  nome        text not null,
  canal       text not null,
  turma       text,
  inicio      timestamptz,
  fim         timestamptz,
  sck_regex   text,
  prioridade  int not null default 100,
  fonte       text not null
);
alter table fin.acoes enable row level security;
revoke all on fin.acoes from public, anon, authenticated;

insert into fin.acoes (produto, nome, canal, turma, inicio, fim, sck_regex, prioridade, fonte) values
  -- HM, em ordem de data
  ('HM', 'LPSG Holding Total (mai–jun/26)', 'LPSG Holding Total', null,
     '2026-05-01 03:00+00', '2026-06-25 03:00+00', '^lpsg', 10, 'gp-operacoes glossário (LPSG) + sck lpsg-holding-total medido'),
  ('HM', 'Lançamento T39', 'Live Direto ao Ponto', 'T39',
     '2026-06-25 03:00+00', '2026-06-27 03:00+00', null, 20, 'cs.hm_evento_janela #1'),
  ('HM', 'Reunião fechada 25/06 (pós-lançamento T39)', 'Reunião fechada', 'T39',
     '2026-06-25 03:00+00', null, 'reuniao-fechada-2506', 5, 'sck reuniao-fechada-2506 medido (27/06–11/08); sem fim = só casa pelo link, a data é a da reunião'),
  ('HM', 'HT ATM T39', 'HT ATM', 'T39',
     '2026-07-06 03:00+00', '2026-07-10 03:00+00', 'reuniao-fechada-0607', 20, 'cs.hm_evento_janela #2, estendida a 09/07 (carrinho medido 08–09/07)'),
  ('HM', 'Ex aluno T39', 'Ex aluno Direto ao Ponto', 'T39',
     '2026-07-13 03:00+00', '2026-07-16 03:00+00', 'reuniao-fechada-1307', 20, 'cs.hm_evento_janela #3, estendida a 15/07 (sck 1307 medido 14–15/07)'),
  ('HM', 'Captação T40 — live HT29 de 26/07', 'HT29 - 26-07', 'T40',
     '2026-07-26 03:00+00', '2026-08-09 03:00+00', null, 20, 'cs.hm_evento_janela #4 (até a véspera do HT30)'),
  ('HM', 'HT30 — 09 e 10/08', 'HT30 - 09-08', 'T40',
     '2026-08-09 03:00+00', '2026-08-17 03:00+00', '(ht30|-0908|-1008|-1108)', 10, 'gp-operacoes série histórica §7 (HT30, oferta HM R$ 697) + sck ht-*-0908/1008/1108'),
  ('HM', 'HT ATM 23/08', 'HT ATM', 'T40',
     '2026-08-23 03:00+00', '2026-08-27 03:00+00', '-2308', 10, 'sck ht-2308 medido (24/08)'),
  ('HM', 'Saldo com desconto Acelera (01–08/09)', 'Acelera Holding', 'T41',
     '2026-09-01 03:00+00', '2026-09-09 03:00+00', null, 30, 'ofertas "HM com desconto Acelera" 01–03/09 (vault, 27/09)'),
  ('HM', 'Seminário ATM (09/09)', 'Seminário ATM', 'T41',
     '2026-09-09 03:00+00', '2026-09-25 03:00+00', 'atm-2009|seminario-atm', 30, 'gp-operacoes projetos/2026-09-seminario-atm'),
  ('HM', 'Imersão HT — 26 e 27/09/2026', 'Imersão HT - 26-09', 'T41',
     '2026-09-25 03:00+00', '2027-01-01 03:00+00', '^ht32', 20, 'cs.hm_evento_janela #9 + gp-operacoes HT32 (oferta 6fceg8ye)'),
  -- AURUM
  ('AURUM', 'ETHB SP — captação Aurum', 'ETHB SP', 'A8',
     '2026-08-04 03:00+00', '2026-08-10 03:00+00', null, 20, 'gp-operacoes projetos/2026-08-ethb-sao-paulo (04 a 06/08) — a janela antiga começava em 05/08'),
  ('AURUM', 'Reserva Aurum (base)', 'Base Aurum', null,
     '2026-04-01 03:00+00', '2026-07-01 03:00+00', null, 90, 'reservas Aurum abr–jun/26 medidas (sck qrcode/whatsapp)');

-- 2. A ação de cada card
create or replace view fin.vw_acao_card as
with card as (
  select b.contato_hm_id, b.origem, b.acao_nome, b.acao_data, lower(trim(b.email)) email
    from cs.vw_fin_board b
), emails as (
  select c.contato_hm_id, coalesce(substr(i2.no, 3), c.email) email
    from card c
    left join fin.identidade i on i.no = 'e:' || c.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
), primeira as (
  -- 1ª compra paga da família do card: sinal/cheio primeiro (é o que o board chama de entrada), depois a mais antiga
  select distinct on (c.contato_hm_id) c.contato_hm_id, t.aprovado_em, t.dia_aprovado, t.origem_sck
    from card c
    join emails e on e.contato_hm_id = c.contato_hm_id
    join fin.vw_transacoes t on t.email = e.email and t.familia = c.origem and t.grupo = 'pago'
    left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
   order by c.contato_hm_id, (cat.categoria in ('sinal','compra_cheia')) desc nulls last, t.aprovado_em
)
select c.contato_hm_id,
       coalesce(c.acao_nome, s.nome, j.nome,
                case when p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%' then 'Comercial (venda direta)' end,
                case when p.dia_aprovado < date '2026-01-01' then 'Base antiga (antes de 2026)' end,
                case when p.aprovado_em is null then 'Sem pagamento ainda' end,
                'Base (fora de evento)') acao_nome,
       coalesce(c.acao_data, s.inicio, j.inicio, p.aprovado_em) acao_data,
       case when c.acao_nome is not null then 'janela do evento'
            when s.nome is not null then 'link de venda'
            when j.nome is not null then 'data da compra'
            when p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%' then 'link do comercial'
            when p.aprovado_em is null then 'sem compra paga'
            else 'data da compra' end acao_regra,
       coalesce(s.canal, j.canal,
                case when p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%' then 'Comercial' end) acao_canal,
       p.dia_aprovado captado_em,
       p.origem_sck captado_sck
  from card c
  left join primeira p on p.contato_hm_id = c.contato_hm_id
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = c.origem and a.sck_regex is not null and p.origem_sck ~* a.sck_regex
                      order by a.prioridade, a.id limit 1) s on true
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = c.origem and a.inicio is not null and p.aprovado_em >= a.inicio and p.aprovado_em < a.fim
                      order by a.prioridade, a.id limit 1) j on true;
revoke all on fin.vw_acao_card from public, anon, authenticated;

-- 3. O board passa a ler a ação de fin.vw_acao_card; canal "Não classificado"/vazio herda o canal da ação.
--    Mesmas colunas de antes + 3 no fim (acao_regra, captado_em, captado_sck). Valores de dinheiro: intocados.
drop function if exists public.fn_fin_board(text, text);
create function public.fn_fin_board(p_turma text default null, p_produto text default null)
returns table(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying,
  turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text,
  vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric,
  sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date,
  dias_atraso integer, entrou_estagio_em timestamptz, dias_no_estagio integer, solicitou_cancelamento boolean,
  cancelamento_em timestamptz, cancelamento_efetivado_em timestamptz, quitado_em timestamptz, reembolso_em timestamptz,
  reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamptz, ultimo_pagamento_em timestamptz,
  aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamptz,
  reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date,
  pacote_regra numeric, divergencia_regra numeric,
  acao_regra text, captado_em date, captado_sck text)
language sql stable security definer
set search_path to 'public', 'cs'
as $function$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    b.nome, b.email,
    b.turma, b.turma_origem,
    case when b.canal is null or b.canal = 'Não classificado' then coalesce(a.acao_canal, b.canal) else b.canal end,
    b.publico, b.produto,
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    a.acao_nome, a.acao_data,
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    b.pacote_regra, b.divergencia_regra,
    a.acao_regra, a.captado_em, a.captado_sck
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  where coalesce(public.gp_pode_ver_financeiro(), false)
    and (p_turma is null or b.turma = p_turma)
    and (p_produto is null or b.origem = p_produto)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;
revoke all on function public.fn_fin_board(text, text) from public, anon;
grant execute on function public.fn_fin_board(text, text) to authenticated, service_role;
