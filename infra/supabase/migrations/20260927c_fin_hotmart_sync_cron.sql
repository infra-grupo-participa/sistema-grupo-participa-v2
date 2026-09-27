-- 20260927c — Disparo do sincronizador da Hotmart (pg_cron → pg_net → Edge Function hotmart-sync).
-- APLICADO em produção em 27/09/2026 (migrações fin_hotmart_sync_disparador e fin_hotmart_sync_backfill_e_cron).
--
-- A chave vai no header `x-sync-chave` e vem do Vault; a Edge Function compara com o
-- mesmo segredo. Sem a chave, a função responde 401 — é o que protege um endpoint
-- com verify_jwt = false.

create or replace function fin.hotmart_sync_disparar(p_rotina boolean default false)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_chave text; v_id bigint;
begin
  select decrypted_secret into v_chave from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave';
  select net.http_post(
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/hotmart-sync',
    headers := jsonb_build_object('Content-Type','application/json','x-sync-chave', v_chave),
    body := jsonb_build_object('rotina', p_rotina),
    timeout_milliseconds := 150000) into v_id;
  return v_id;
end $$;
revoke all on function fin.hotmart_sync_disparar(boolean) from public, anon, authenticated;


-- Janelas de 60 dias: a API recusa intervalo de ~1 ano, e a de 300 dias passava dos 150 s da
-- Edge Function depois que os participantes passaram a vir status a status (27/09).
-- (Versão consolidada: o arquivo tinha o corpo de 300 dias e o de 60 empilhados; vale só este.)
create or replace function fin.hotmart_sync_enfileirar(p_dias int)
returns int language plpgsql security definer set search_path = '' as $$
declare v_n int; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
  select p.produto_id, g::date, least(g::date + 59, v_hoje), 'rotina'
    from fin.produtos p
    cross join generate_series(v_hoje - p_dias, v_hoje, interval '60 days') g
   where p.sincroniza
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function fin.hotmart_sync_enfileirar(int) from public, anon, authenticated;

-- Backfill: a história inteira desde 2022-01-01 (nenhuma venda antes disso, medido na API).
select fin.hotmart_sync_enfileirar(((now() at time zone 'America/Sao_Paulo')::date - date '2022-01-01'));

-- Fila: a cada 2 min, só dispara se houver trabalho e menos de 3 execuções recentes em curso.
select cron.schedule('fin-hotmart-sync-fila', '*/2 * * * *', $cron$
  select fin.hotmart_sync_disparar(false)
   where exists (select 1 from fin.hotmart_sync_fila
                  where status = 'pendente' or (status = 'erro' and tentativas < 3)
                     or (status = 'processando' and iniciado_em < now() - interval '5 minutes' and tentativas < 3))
     and (select count(*) from fin.hotmart_sync_fila
           where status = 'processando' and iniciado_em > now() - interval '3 minutes') < 3  -- até 3 em paralelo
$cron$);
-- Rotina: de hora em hora, últimos 3 dias de cada produto.
select cron.schedule('fin-hotmart-sync-rotina', '7 * * * *', $$ select fin.hotmart_sync_disparar(true) $$);

-- Purga diária: janela 'feito' com mais de 7 dias (a rotina reinsere 7 por hora; sem isto a fila cresce ~168/dia).
select cron.schedule('fin-hotmart-sync-purga', '17 4 * * *',
  $$ delete from fin.hotmart_sync_fila where status = 'feito' and feito_em < now() - interval '7 days' $$);

-- Releituras: reembolso/chargeback de venda antiga muda o status de uma transação velha,
-- e a rotina de hora em hora só relê 3 dias.
select cron.schedule('fin-hotmart-sync-60dias', '23 3 * * *', $$ select fin.hotmart_sync_enfileirar(60) $$);
select cron.schedule('fin-hotmart-sync-historia', '13 2 * * 0',
  $$ select fin.hotmart_sync_enfileirar(((now() at time zone 'America/Sao_Paulo')::date - date '2022-01-01')) $$);
