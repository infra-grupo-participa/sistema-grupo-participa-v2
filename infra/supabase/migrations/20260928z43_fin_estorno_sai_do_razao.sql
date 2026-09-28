-- 20260928z43 — Polimento, rodada 3: dinheiro devolvido não conta como recebido (regra 0266 do disparos), sempre.
-- Medido: 13 lançamentos no razão (cs.hm_pagamentos) de transações que a Hotmart dá como REFUNDED — R$ 22.190,98 —
-- em 12 cards (reembolsados; num deles a compra cheia de R$ 13.000 foi devolvida e o sinal de R$ 2.000 segue pago).
-- Reembolso PARCIAL não entra (o lançamento inteiro não pode sair).
-- O board somava esse dinheiro como pago e a conferência com a Hotmart acusava divergência.
-- Causa: (a) o REFUNDED chegou a public.compras pela sincronização da madrugada, e o estorno do gatilho
-- trg_hm_compra_cancelada falha em silêncio (exception → null, 0193/0266); (b) em 2 casos o webhook de reembolso nunca
-- chegou (compra segue APPROVED), mas a API da Hotmart (espelho fin) diz REFUNDED.
-- Conserto da classe: fin.estornar_pagamentos_invalidos() — tira do razão, pela função oficial cs.fn_hm_estornar_pagamento
-- (que deixa interação no card), todo lançamento cuja transação está estornada no espelho OU em public.compras.
-- Recalcula o financeiro do card. Roda agora e de hora em hora (depois da rotina do espelho). Idempotente.
-- NÃO muda estágio nem status de compra (isso dispara revogação de acesso e avisos — é decisão operacional).
create or replace function fin.estornar_pagamentos_invalidos()
returns int language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in
    select p.id, p.comprador_id, p.transacao,
           coalesce(t.status, k.status::text) status
      from cs.hm_pagamentos p
      left join fin.vw_transacoes t on t.transacao = p.transacao
      left join public.compras k on k.hotmart_transaction = p.transacao
     where p.transacao is not null
       and (t.status in ('REFUNDED','CHARGEBACK','PROTESTED','CANCELED','CANCELLED')
            or k.status in ('REFUNDED','CHARGEBACK','PROTESTED','CANCELED','CANCELLED'))
  loop
    perform cs.fn_hm_estornar_pagamento(r.id,
      'Estornado na Hotmart (' || coalesce(r.status, '?') || ') — dinheiro devolvido não conta como recebido '
      || '(conferência automática do financeiro, z43)', 'financeiro');
    perform cs.fn_hm_recalcular_financeiro(r.comprador_id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function fin.estornar_pagamentos_invalidos() from public, anon, authenticated;

select fin.estornar_pagamentos_invalidos();

select cron.schedule('fin-estorno-sai-do-razao', '23 * * * *', $$select fin.estornar_pagamentos_invalidos()$$);
