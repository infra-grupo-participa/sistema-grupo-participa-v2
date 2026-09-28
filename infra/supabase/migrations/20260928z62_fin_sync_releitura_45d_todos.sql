-- 20260928z62 — NÃO APLICADA — coordenador aplica.
--
-- Problema: fin.hotmart_sync_enfileirar(60) (20260927c_fin_hotmart_sync_cron.sql l.26-38, cron
-- 'fin-hotmart-sync-60dias' às 03:23) só releva os produtos com fin.produtos.sincroniza = true (HM,
-- Aurum, Acelera, Diamante). Os demais — Holding Total, Encontro THB e todo produto ainda
-- A_CLASSIFICAR — só são relidos pela rotina horária 'fin-hotmart-rotina-todos'
-- (20260928z5_fin_rotina_todos_produtos.sql), que cobre só os últimos 3 dias (produto_id = '*').
-- Um reembolso/chargeback que muda o status de uma venda desses produtos com mais de 3 dias nunca
-- chega a fin.hotmart_transacoes → o Contas a Receber (20260928z61, bloco 1: dinheiro de vendas
-- ainda a cair) conta como "a receber" uma venda que já foi estornada.
--
-- Mecanismo: mesma fila (fin.hotmart_sync_fila) e mesmo padrão de enfileiramento do
-- 'fin-hotmart-rotina-todos' (20260928z5) — produto_id = '*' (todos, resolvido item a item pela
-- Edge Function), tipo 'rotina'. Diferença: janela de 45 dias (cobre reembolso/chargeback tardio;
-- a garantia padrão Hotmart é 7-30 dias, alguns produtos chegam a 90 — 45 cobre a maioria sem
-- reprocessar a história inteira todo dia) e frequência diária, não horária.
--
-- Horário 03:43 — fora do expediente, e não colide com nenhum cron existente:
--   'fin-hotmart-sync-fila'      */2 * * * *   (minuto par, sempre)      → 43 é ímpar, nunca cai junto
--   'fin-hotmart-sync-rotina'    7  * * * *   (minuto 7, toda hora)     → 43 ≠ 7
--   'fin-hotmart-rotina-todos'   7  * * * *   (minuto 7, toda hora)     → 43 ≠ 7
--   'fin-hotmart-sync-60dias'    23 3 * * *                              → 20 min de folga
--   'fin-hotmart-catalogo'       31 3 * * *                              → 12 min de folga
--   'fin-hotmart-sync-purga'     17 4 * * *                              → antes, sem sobrepor
--
-- Idempotência: cron.schedule() do pg_cron faz upsert por jobname — rodar esta migration de novo
-- reescreve a mesma linha em cron.job, não duplica. A query enfileirada usa "where not exists"
-- (mesmo padrão do 20260928z5): mesmo se o cron disparar duas vezes no mesmo dia (inicio/fim iguais,
-- calculados a partir da data de hoje), a segunda chamada não insere de novo. A tabela também tem
-- unique index em (produto_id, inicio, fim, tipo) where status <> 'feito' (20260927_fin_espelho_hotmart.sql
-- l.73) como segunda trava, caso o "where not exists" corra em paralelo com outra sessão.
--
-- Reversão:
--   select cron.unschedule('fin-hotmart-rotina-todos-45dias');

select cron.schedule('fin-hotmart-rotina-todos-45dias', '43 3 * * *', $c$
  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo, status, tentativas)
  select '*', (now() at time zone 'America/Sao_Paulo')::date - 45, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
   where not exists (
     select 1 from fin.hotmart_sync_fila
      where produto_id = '*' and tipo = 'rotina' and status in ('pendente','processando')
        and inicio = (now() at time zone 'America/Sao_Paulo')::date - 45
        and fim    = (now() at time zone 'America/Sao_Paulo')::date
   )
$c$);

-- ==========================================================================================
-- PROVAS (rodar depois de aplicado — não roda sozinho nesta migration; comentado de propósito)
-- ==========================================================================================
--
-- 1) Tempo de uma execução com janela de 45 dias, produto_id = '*':
--    A Edge Function grava cada janela processada em fin.hotmart_sync_fila (itens, iniciado_em,
--    feito_em). Depois que o cron das 03:43 rodar pela primeira vez e a fila-processadora
--    ('fin-hotmart-sync-fila', a cada 2 min) pegar essa linha:
--
--      select id, inicio, fim, itens, tentativas,
--             iniciado_em, feito_em, (feito_em - iniciado_em) as duracao
--        from fin.hotmart_sync_fila
--       where produto_id = '*' and tipo = 'rotina' and (fim - inicio) >= 44
--       order by feito_em desc limit 5;
--
--    Se `duracao` estourar perto de 110s (ORCAMENTO_MS em hotmart-sync/index.ts:19, limite de
--    parede de 150s da Edge Function) ou se `itens` vier NULL com `erro` preenchido por timeout
--    parcial, a janela de 45 dias é grande demais para um único ciclo e precisa ser fatiada (como
--    o comentário de 20260927c l.23-25 já fatiou 300→60 dias pelo mesmo motivo).
--
-- 2) Chamadas à API da Hotmart geradas por essa janela:
--    processarJanela (hotmart-sync/index.ts:89-186) faz, no mínimo, por execução da janela '*':
--      - 15 chamadas a /sales/history      (uma por status em STATUS, l.20-24)
--      - 1 chamada a  /sales/price/details (sem filtro de status)
--      - 1 chamada a  /sales/commissions   (sem filtro de status)
--      - 15 chamadas a /sales/users        (uma por status)
--      = 32 chamadas mínimas, MAIS 1 chamada extra por página além da primeira em qualquer uma
--      dessas 32 (paginar() pede de 50 em 50 itens, index.ts:72-82) — dado o volume de venda por
--      produto por status, é o "mais" que dita o total real, não os 45 dias em si.
--    Para medir o total real depois de aplicado, usar os logs da função:
--      supabase functions logs hotmart-sync --project-ref mbvybujpkwuorhtdzcde
--    (contar linhas de fetch, ou instrumentar um contador — hoje a função não expõe esse número na
--    resposta, só `itens` gravados por produto/status, não por chamada HTTP).
--
-- 3) Controle de rate limit da Hotmart no repo:
--    Não há limite documentado (nº de req/s ou req/min) em nenhum arquivo do repo — busca por
--    "429", "rate limit", "limite de requisi" nos infra/supabase/functions/* só retorna o handler
--    de hotmart-sync/index.ts:61-69: em HTTP 429 espera `5000 * tentativa` ms (5s, 10s, 15s, 20s) e
--    tenta de novo, até 4 tentativas; na 4ª falha lança "limite de requisições da Hotmart (429)
--    persistente" e a janela cai em 'erro' (reprocessada depois, tentativas < 3 — ver linha 234-236
--    da própria função). Não há limite de concorrência entre janelas diferentes lido do lado de cá
--    além do "até 3 em paralelo" do cron 'fin-hotmart-sync-fila' (20260927c l.51). Não achei no
--    repo o número oficial de rate limit da Hotmart (req/s) — se o coordenador tiver essa
--    informação da doc oficial da Hotmart, vale confirmar se 32+ chamadas em sequência rápida por
--    execução de janela '*' fica dentro do limite.
