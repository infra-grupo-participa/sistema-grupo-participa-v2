-- 20260928g — Identidade recalculada de hora em hora (era 1×/dia às 04:37).
-- Quem compra hoje com um e-mail novo só era juntado aos outros e-mails da pessoa na madrugada seguinte.
-- O recálculo leva ~930 ms (medido 27/09) e roda aos :20, depois da rotina de sincronização (:07).
select cron.unschedule('fin-identidade-recalcular');
select cron.schedule('fin-identidade-recalcular', '20 * * * *', $$ select fin.recalcular_identidade() $$);
