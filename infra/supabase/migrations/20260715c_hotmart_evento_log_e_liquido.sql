-- Captura do payload bruto da Hotmart + suporte ao valor líquido/taxa.
--
-- Contexto (auditoria 2026-07-15): o webhook `hotmart-events-webhook` gravava só
-- o preço BRUTO em `public.compras.preco` e NUNCA `valor_liquido`/`taxa_processamento`.
-- Resultado: `fn_fin_faturamento_diario` faz `coalesce(valor_liquido, valor)` e
-- exibe líquido = bruto (taxa Hotmart = 0). Além disso NENHUM payload bruto era
-- persistido, então não havia como fazer backfill do histórico.
--
-- Esta migration cria o canal de captura (RPC SECURITY DEFINER que insere em
-- cs.hotmart_eventos — schema `cs` não é exposto ao PostgREST, padrão fn_aluno_360)
-- para: (1) o webhook passar a arquivar cada PURCHASE_APPROVED cru; (2) viabilizar
-- backfill de líquido/taxa a partir de commissions[] daqui pra frente.

create or replace function public.fn_log_hotmart_evento(
  p_evento    text,
  p_transacao text,
  p_email     text,
  p_payload   jsonb
) returns void
language sql
security definer
set search_path = public, cs
as $$
  insert into cs.hotmart_eventos (evento, transacao, email, payload)
  values (p_evento, p_transacao, p_email, p_payload);
$$;

-- Só service_role (webhook) chama. Revoga o acesso amplo (padrão das RPCs cs.*).
revoke all on function public.fn_log_hotmart_evento(text, text, text, jsonb) from public;

comment on function public.fn_log_hotmart_evento is
  'Arquiva o payload bruto de um evento Hotmart em cs.hotmart_eventos. Chamado pelo Edge Function hotmart-events-webhook (service_role). Fonte de verdade p/ backfill de valor_liquido/taxa.';
