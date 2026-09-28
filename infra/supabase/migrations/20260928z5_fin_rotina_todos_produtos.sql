-- 20260928z5 — A rotina horária só enfileirava produtos com sincroniza = true (HM, Aurum, Acelera, Diamante). Os 69
-- A_CLASSIFICAR (Holding Total, Encontro, Clínica, Imersão…) e todo produto novo do catálogo ficavam fora: venda nova
-- não entrava. Agora: de hora em hora, uma janela '*' (todos os produtos) dos últimos 3 dias. Upsert por transação.
select cron.schedule('fin-hotmart-rotina-todos', '7 * * * *', $c$
  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo, status, tentativas)
  select '*', (now() at time zone 'America/Sao_Paulo')::date - 3, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
   where not exists (select 1 from fin.hotmart_sync_fila where produto_id = '*' and tipo = 'rotina' and status in ('pendente','processando'))
$c$);
