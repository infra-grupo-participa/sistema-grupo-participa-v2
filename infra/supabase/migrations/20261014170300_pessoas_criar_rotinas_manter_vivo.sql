-- 20261014170300: manter a pessoa única viva (rotina de hora em hora só no banco + agendamento do delta diário do AC)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014150034 (ex-170000) e 170100.
--   Ensaio: 20261014170300_ensaio.sql. Detalhe: 20261014170300.explain.md.
--
-- POR QUE: "temos q configurar isso tbm pra ficar funcional" (Victor, 14/10/2026). Regras do Maestro/Victor: incremental,
--   leve (máquina de ~1 GB), minuto vazio, chave de desligar; rotina EXTERNA (AC) nasce desligada, 1×/dia de madrugada,
--   teto de chamadas no código e data de fim gravada (padrão 31/12/2026).
-- O QUE FAZ:
--   1. pessoas.carga_incremental(p_limite): para cada fonte do banco (Hotmart das 2 contas, Central, T1-T40, HM, sócios do
--      HM, Respondi, leads, CRM), roda a carga no modo "só novos" (linhas sem o seu evento), até p_limite por fonte. Pula a
--      fonte que (a) está com a chave desligada, (b) tem carga inicial aberta ou (c) ainda não terminou a carga inicial.
--      Erro numa fonte: fecha aquela execução como 'erro' com o SQLSTATE e segue as outras.
--      Hotmart e Respondi NÃO têm rotina externa: o webhook da Hotmart e o respondi-sync já põem o dado no banco; esta
--      rotina só lê o banco.
--   2. Job pg_cron 'pessoas-incremental' às :50 de toda hora, CRIADO DESLIGADO (active = false). Liga depois da carga
--      inicial, com o roteiro.
--   3. Job pg_cron 'pessoas-ac-delta' às 05:40 UTC (02:40 em Brasília), CRIADO DESLIGADO, chamando a Edge Function
--      pessoas-ac-delta (código no repo, a publicar). Chave 'activecampaign_delta' nasce desligada, com fim 31/12/2026.
--      A Edge usa a chave do AC do Vault (activecampaign_api_key) e o segredo do cron já existente (cron_webhook_secret).
-- AS 5 PERGUNTAS: escala = dezenas de linhas novas por hora (contra ~58 mil transações e ~40 mil leads de base: o anti-join
--   pelo índice único custa ~1 ms por mil linhas lidas); índice = eventos_fonte_unico; frequência = 24×/dia (só banco) e
--   1×/dia (AC); repetição = idempotente; reversão = 20261014170300_reversao.sql (desagenda os 2 jobs e tira a função).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('pessoas.carga_thb_alunos(bigint,integer,boolean)') is null then
    raise exception '20261014170300: falta 20261014170100 (cargas das fontes com modo só novos).';
  end if;
  if exists (select 1 from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta')) then
    raise exception '20261014170300: jobs já existem.';
  end if;
end
$g$;

insert into pessoas.carga_chave (fonte, ligada, ate, por) values
  ('incremental', true, null, 'migration 20261014170300 (o job nasce desligado; esta chave é a segunda trava)'),
  ('activecampaign_delta', false, date '2026-12-31', 'migration 20261014170300: rotina externa, liga só com ok do Victor')
on conflict (fonte) do nothing;

create function pessoas.carga_incremental(p_limite integer default 200) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  f text; v_e bigint; r jsonb; v_saida jsonb := '{}';
begin
  if not pessoas.carga_ligada('incremental') then return jsonb_build_object('desligada', true); end if;
  if p_limite not between 1 and 1000 then raise exception 'limite entre 1 e 1.000' using errcode = '22023'; end if;
  foreach f in array array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios',
                           'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio'] loop
    if not pessoas.carga_ligada(f) then v_saida := v_saida || jsonb_build_object(f, 'desligada'); continue; end if;
    if exists (select 1 from pessoas.carga_execucao where fonte = f and status in ('rodando', 'parada')) then
      v_saida := v_saida || jsonb_build_object(f, 'carga aberta'); continue;
    end if;
    if not exists (select 1 from pessoas.carga_execucao where fonte = f and fase = 'pessoas' and status = 'ok' and coalesce(por, '') <> 'incremental') then
      v_saida := v_saida || jsonb_build_object(f, 'sem carga inicial'); continue;
    end if;
    begin
      v_e := (pessoas.carga_abrir(f, 'pessoas', 'incremental')->>'execucao')::bigint;
      r := case f
             when 'hotmart_academy'    then pessoas.carga_fin_hotmart(v_e, 'academy', p_limite, true)
             when 'hotmart_escritorio' then pessoas.carga_fin_hotmart(v_e, 'escritorio', p_limite, true)
             when 'thb_alunos'         then pessoas.carga_thb_alunos(v_e, p_limite, true)
             when 'aluno_historico'    then pessoas.carga_aluno_historico(v_e, p_limite, true)
             when 'contatos_hm'        then pessoas.carga_contatos_hm(v_e, p_limite, true)
             when 'hm_socios'          then pessoas.carga_hm_socios(v_e, p_limite, true)
             when 'respondi'           then pessoas.carga_respondi(v_e, p_limite, true)
             when 'crm_negocio'        then pessoas.carga_crm_negocio(v_e, p_limite, true)
             else pessoas.carga_leads(v_e, f, p_limite, true) end;
      perform pessoas.carga_fechar(v_e, 'ok');
      v_saida := v_saida || jsonb_build_object(f, (r->>'lidas')::int);
    exception when others then
      -- a subtransação desfez o lote E a execução aberta nele; registra uma execução 'erro' (só o código) fora dela
      v_saida := v_saida || jsonb_build_object(f, 'erro ' || sqlstate);
      insert into pessoas.carga_execucao (fonte, fase, status, erro, por, terminada_em)
      values (f, 'pessoas', 'erro', 'incremental: ' || sqlstate, 'incremental', now());
    end;
  end loop;
  return v_saida;
end $f$;
revoke all on function pessoas.carga_incremental(integer) from public, anon, authenticated, service_role;

-- jobs: criados e desligados na mesma migration
select cron.schedule('pessoas-incremental', '50 * * * *',
  $c$ set statement_timeout = '120s'; select pessoas.carga_incremental(200) $c$);
select cron.schedule('pessoas-ac-delta', '40 5 * * *',
  $c$ select ops.cron_post('pessoas-ac-delta',
       url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/pessoas-ac-delta',
       body := '{}'::jsonb,
       headers := jsonb_build_object('Content-Type', 'application/json',
                                     'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_webhook_secret')),
       timeout_milliseconds := 150000) $c$);
select cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname in ('pessoas-incremental', 'pessoas-ac-delta');

do $g$
begin
  if (select count(*) from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta') and not active) <> 2 then
    raise exception '20261014170300: os 2 jobs tinham de nascer desligados.';
  end if;
  if has_function_privilege('anon', 'pessoas.carga_incremental(integer)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_incremental(integer)', 'execute') then
    raise exception '20261014170300: carga_incremental executável por anon/authenticated.';
  end if;
end
$g$;
