-- APLICADA EM PRODUÇÃO 2026-08-19 — este arquivo é o registro do que rodou.
--
-- Canal de aquisição é POR PRODUTO. Card do AURUM herdava ação do HM.
--
-- ── Como apareceu ────────────────────────────────────────────────────────────
-- O Marcio pediu para separar HM de AURUM em abas, e disse: "no AURUM tem o
-- próprio canal de aquisição que é do ETHB SP, enquanto no HM tem diversos
-- canais". Ao medir para montar as abas, o board mostrava:
--     AURUM · "Lançamento T39"  (1 card)
--     AURUM · "HT ATM T39"      (12 cards)
-- Essas são ações do HM. Ele estava certo — havia um bug.
--
-- ── A causa ──────────────────────────────────────────────────────────────────
-- cs.hm_evento_janela não tinha coluna de produto. A CTE `acao` de
-- cs.vw_fin_board cruzava só a data do sinal com [inicio, fim], sem filtrar
-- produto. Um AURUM que pagou o sinal em 06/07 recebia o rótulo da ação do HM
-- que rodava naquela data.
--
-- Medido: 34 dos 41 cards AURUM têm a tag 'ETHB SP' e pagaram o sinal entre
-- 05/08 e 07/08. Essa janela simplesmente não existia cadastrada.
--
-- ── O que mudou ──────────────────────────────────────────────────────────────
-- 1. cs.hm_evento_janela ganha `produto` (default 'HM').
-- 2. Janela do ETHB SP cadastrada (AURUM, 05–08/08).
-- 3. cs.vw_fin_board: CTE `acao` casa por (comprador, produto); CTE
--    `sinal_pago` passa a resolver o sinal por (comprador, produto) usando
--    cs.fn_hm_pagamento_do_produto — antes um `distinct on (comprador_id)`
--    escolhia UM sinal para os dois cards da mesma pessoa.
--
-- ⚠️ DEFAULT 'HM' é deliberado: cs.fn_hm_janela_evento(p_venda_em) roda no seed
-- do webhook da Hotmart e NÃO filtra produto. Com o default, ela continua vendo
-- o mesmo conjunto de janelas — comportamento inalterado. Alterá-la é caminho
-- do webhook (risco de venda invisível) e não é necessário: quem precisa do
-- recorte por produto é a LEITURA do board. Mesmo raciocínio para os outros
-- consumidores, cs.fn_hm_health_check e cs.fn_sync_hm_atm.
--
-- ── Por que a constraint de overlap saiu ─────────────────────────────────────
-- hm_evento_janela_sem_overlap era EXCLUDE USING gist global: duas janelas
-- nunca podiam coexistir no tempo. Certo quando só existia o funil do HM.
--
-- Com AURUM paralelo, deixou de valer — e BARROU o insert do ETHB SP: a
-- captação (05–08/08, AURUM) acontece DENTRO da "Captação T40 — live HT29"
-- (26/07–10/08, HM). Ações simultâneas de produtos diferentes não são erro de
-- cadastro; são dois funis rodando ao mesmo tempo.
--
-- Um EXCLUDE por (produto, range) exigiria a extensão btree_gist — não
-- instalada neste banco (checado em pg_extension). Em vez de instalar extensão
-- só para isto, a garantia virou índice único por (produto, inicio): impede
-- duplicar a mesma janela do mesmo produto, que é o erro de cadastro real.
--
-- ⚠️ Diferença assumida: o índice único NÃO pega sobreposição PARCIAL dentro do
-- mesmo produto (ex.: HM 01–10/08 e HM 05–15/08). São 5 janelas cadastradas
-- manualmente; o risco é baixo e uma extensão nova é custo permanente. Se a
-- tabela crescer ou passar a ser alimentada por automação, reavaliar
-- btree_gist.
--
-- ── O furo do ::date: a janela perdia o PRIMEIRO DIA ─────────────────────────
-- Achado ao conferir por que 12 cards AURUM da tag 'ETHB SP' ainda apareciam
-- como "sem ação" DEPOIS de cadastrar a janela que cobria exatamente o dia
-- deles.
--
-- A CTE `acao` comparava `sp.pago_em::date between ev.inicio and ev.fim`. Como
-- inicio/fim são timestamptz, o Postgres promove a date para timestamptz em
-- MEIA-NOITE UTC — e a janela começa 00:00 no fuso de SP (= 03:00 UTC). Todo
-- pagamento do próprio dia de início caía FORA.
--
-- Prova rodada no banco:
--   '2026-08-05'::date::timestamptz             → 2026-08-05 00:00:00+00
--   janela ETHB SP inicio                        → 2026-08-05 03:00:00+00
--   '2026-08-05'::date between inicio e fim      → FALSE
--   '2026-08-05 21:42:33+00' between inicio/fim  → TRUE
--
-- Não era só do Aurum: o mesmo furo comia o primeiro dia de TODAS as janelas
-- do HM. Corrigido comparando timestamptz com timestamptz, sem cast.
--
-- ── Resultado (conferido) ────────────────────────────────────────────────────
--                            só produto → + fix do ::date
--   AURUM · ETHB SP               22    →  34 cards
--   AURUM · (sem ação)            19    →   7
--   HM · Lançamento T39            4    →  11
--   HM · HT ATM T39               81    →  86
--   HM · Ex aluno T39              7    →  39
--   HM · Captação T40             45    →  46
--   HM · (sem ação)              127    →  82
--
-- 45 cards do HM e 12 do AURUM deixaram de ficar órfãos de canal. Nenhum card
-- AURUM aparece mais em ação do HM.
--
-- Custo: cs.vw_fin_board caiu de ~204 ms para ~35 ms. O `distinct on` por
-- (comprador, produto) deu ao planner um plano melhor que o anterior.

alter table cs.hm_evento_janela
  add column if not exists produto text not null default 'HM';

comment on column cs.hm_evento_janela.produto is
  'Produto a que a janela pertence (HM | AURUM | ETHB). Default HM: as janelas '
  'pré-existentes são todas do HM, e cs.fn_hm_janela_evento (seed do webhook) '
  'não filtra produto — o default preserva o comportamento dela.';

alter table cs.hm_evento_janela
  drop constraint if exists hm_evento_janela_sem_overlap;

create unique index if not exists hm_evento_janela_produto_inicio_uk
  on cs.hm_evento_janela (produto, inicio);

comment on index cs.hm_evento_janela_produto_inicio_uk is
  'Substitui o EXCLUDE global de overlap, que impedia HM e AURUM de terem ações '
  'simultâneas (são funis paralelos). Impede duplicar a mesma janela do mesmo '
  'produto. NÃO cobre sobreposição parcial — ver comentário da migration.';

insert into cs.hm_evento_janela (canal, inicio, fim, turma, nota, produto)
select 'ETHB SP',
       '2026-08-05 00:00:00-03'::timestamptz,
       '2026-08-08 23:59:59-03'::timestamptz,
       'A8',
       'ETHB SP — captação Aurum',
       'AURUM'
where not exists (
  select 1 from cs.hm_evento_janela where produto = 'AURUM' and canal = 'ETHB SP'
);

-- ── cs.vw_fin_board: ação e sinal resolvidos POR PRODUTO ─────────────────────

create or replace view cs.vw_fin_board as
with sinal_pago as (
  -- 1 linha por (comprador, produto): a data do sinal DAQUELE produto.
  -- Antes era distinct on (comprador_id) sem filtrar produto — a mesma pessoa
  -- com card HM e AURUM tinha UM sinal escolhido para os dois.
  select distinct on (p.comprador_id, ch.produto)
         p.comprador_id, ch.produto, p.pago_em
    from cs.hm_pagamentos p
    join cs.contatos_hm ch on ch.comprador_id = p.comprador_id
   where p.categoria = 'sinal'
     and cs.fn_hm_pagamento_do_produto(p.oferta_codigo, ch.produto)
   order by p.comprador_id, ch.produto, p.pago_em
), acao as (
  select sp.comprador_id, sp.produto, ev.nota as acao_nome, ev.inicio as acao_data
    from sinal_pago sp
    join cs.hm_evento_janela ev
      on ev.produto = sp.produto                       -- ← o funil certo
     -- timestamptz direto: ::date promoveria a meia-noite UTC e descartaria o
     -- PRIMEIRO DIA de cada janela (ver bloco "furo do ::date" no cabeçalho).
     and sp.pago_em >= ev.inicio
     and sp.pago_em <= ev.fim
), faixa_estagios as (
  select e.id, e.chave, e.aba from cs.estagios e where e.evento = 'HM'
)
select
  v.contato_hm_id, v.comprador_id, v.aluno_id,
  v.nome, v.email, v.telefone, v.documento,
  v.turma, v.turma_origem, v.canal, v.publico,
  ch.produto as origem,
  case ch.produto when 'AURUM' then 'Aurum' else 'Holding Masters' end as produto,
  v.estagio_id, v.estagio_nome, v.estagio_aba, v.vendedor,
  v.status_financeiro, v.pacote, v.total_pago_bruto, v.total_pago_liquido,
  v.saldo_a_pagar, v.credito, v.pago_pct, v.vencimento, v.dias_atraso,
  fe5.chave is not null as solicitou_cancelamento_faixa,
  v.solicitou_cancelamento, v.cancelamento_em, v.cancelamento_efetivado_em,
  v.quitado_em, v.reembolso_em, v.reembolso_valor,
  v.oferta_codigo, v.oferta_enviada_em, v.ultimo_pagamento_em,
  apa.excecao        as aurum_excecao,
  apa.excecao_motivo as aurum_excecao_motivo,
  apa.situacao       as aurum_situacao,
  case when apa.excecao then 'nao_cobrar - ' || coalesce(apa.excecao_motivo, apa.situacao) else null end as aurum_rotulo_operador,
  apa.valor_pago as aurum_valor_pago,
  apa.credito    as aurum_credito,
  case
    when fe5.chave is not null then 'em_risco'
    when fe4.aba is not null then 'quitado'
    when v.vencimento is not null or coalesce(v.parcelas_pagas, 0) > 0 then 'acordo_em_curso'
    when fe2.chave is not null then 'em_negociacao'
    else 'sem_tratativa'
  end as faixa,
  me.criado_em as entrou_estagio_em,
  case when me.criado_em is not null
       then (extract(epoch from now() - me.criado_em) / 86400)::int
       else null end as dias_no_estagio,
  ac.acao_nome,
  ac.acao_data,
  v.sinal_bruto,
  v.saldo_pago_bruto
from cs.vw_fin_contas_receber v
join cs.contatos_hm ch on ch.id = v.contato_hm_id
left join cs.aurum_pagamento_aluno apa on apa.comprador_id = v.comprador_id and ch.produto = 'AURUM'
left join faixa_estagios fe5 on fe5.id = v.estagio_id and fe5.chave in ('hm_solicitou_cancelamento', 'hm_cancelamento', 'hm_reembolsado')
left join faixa_estagios fe4 on fe4.id = v.estagio_id and fe4.aba = 'ativacao'
left join faixa_estagios fe2 on fe2.id = v.estagio_id and fe2.chave in ('hm_reuniao_agendada', 'hm_reuniao_finalizada')
left join lateral (
  select i.criado_em from cs.interacoes i
   where i.contato_hm_id = v.contato_hm_id and i.tipo = 'mudanca_estagio'
   order by i.criado_em desc limit 1
) me on true
-- join casa por comprador E produto: cada card recebe a ação do SEU funil.
left join acao ac on ac.comprador_id = v.comprador_id and ac.produto = ch.produto;
