-- 20261015220100: liga a coleta da aba "Lives" da Black Friday (cron black-youtube → Edge black-youtube).
--
-- COMO VOLTAR: 20261015220100_reversao.sql (cron.unschedule, linhas do vigia e segredo do Vault). Desligar sem apagar:
--   select cron.alter_job((select jobid from cron.job where jobname = 'black-youtube'), active := false);
--
-- POR QUE: 20261015220000 criou as tabelas e as funções; a Edge black-youtube (publicada antes desta migration) só roda
-- quando alguém a chama. Este arquivo cria o chamador. Pedido do Victor Hugo (15/10/2026): a coleta ao vivo precisa estar
-- testada numa live real antes de 03/11 (a primeira é a de 15/10, 19:30 BRT).
--
-- O QUE FAZ
--   a. Segredo aleatório no Vault (dados_black_youtube_chave): o header x-sync-chave que a Edge confere (fail-closed).
--      A chave da YouTube Data API (dados_black_youtube_api_key) NÃO entra aqui: vai à mão, fora do repositório.
--   b. Cron black-youtube, todo minuto, pelo ops.cron_post (regra 11 do CLAUDE.md), só chamando a Edge quando
--      dados.black_live_pede_chamada() é verdadeira: a cada 10 minutos (cadastro, foto, comentários) e todo minuto
--      enquanto alguma live está na janela (15 min antes do horário previsto até 3 h depois, ou "ao_vivo").
--   c. Linha do vigia (ops.rotina / ops.rotina_estado): intervalo 10 min (o maior silêncio normal), 3 falhas seguidas ou
--      30 min sem sucesso abrem incidente, 3 sucessos fecham. Sem isto o vigia semearia pelo schedule (1 min) e daria
--      os mesmos números; a linha manual deixa a decisão escrita.
--
-- AS 5 PERGUNTAS
--   escala: 9 lives; cada chamada lê no máximo 9 vídeos (1 unidade de cota) e, no ar, o chat. Não cresce com a base.
--   índice: nenhuma consulta nova em tabela grande; black_live_alvos lê as 9 linhas de black_lives (plano no .explain.md).
--   frequência: 144 chamadas por dia fora de live, mais 1 por minuto nas janelas (até 3 h 15 min por live, 9 lives).
--     Cota do YouTube (10 mil/dia, compartilhada com o dashboard-ht): fora de live ~150 unidades/dia; uma live de 2 h
--     com chat ~ 195 min x (1 videos.list + ~5 do chat) ~ 1.200 unidades. Medir na live de 15/10 (README da Edge).
--   repetição: uma chamada por minuto, não por tela. A aba lê do banco.
--   reversão: cron.unschedule, ou active := false; a Edge sem chamador não faz nada.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- Guarda: a base (20261015220000) tem de estar aplicada e o pg_cron, o ops.cron_post e o Vault têm de existir.
-- Sem eles (banco local), só avisa e não agenda.
do $guarda$
begin
  if to_regprocedure('dados.black_live_pede_chamada()') is null or to_regclass('dados.black_lives') is null then
    raise exception '20261015220100: aplique antes 20261015220000 (dados.black_lives / black_live_pede_chamada ausentes)';
  end if;
end
$guarda$;

do $cron$
begin
  if to_regnamespace('cron') is null or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261015220100: pg_cron, ops.cron_post ou Vault ausente; cron black-youtube NÃO agendado';
    return;
  end if;
  if not exists (select 1 from vault.secrets where name = 'dados_black_youtube_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'dados_black_youtube_chave', 'Header x-sync-chave do cron black-youtube (Edge black-youtube confere). 20261015220100.');
  end if;
  perform cron.schedule('black-youtube', '* * * * *', $c$
    select ops.cron_post('black-youtube',
      url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/black-youtube',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'dados_black_youtube_chave')),
      timeout_milliseconds := 120000)
     where dados.black_live_pede_chamada()
  $c$);
  -- Linha do vigia, escrita na mão (a semeadura automática usaria o schedule de 1 minuto e chegaria nos mesmos números).
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('black-youtube', 3, interval '30 minutes', 3, interval '10 minutes', 'manual')
  on conflict (jobname) do nothing;
  insert into ops.rotina_estado (jobname) values ('black-youtube') on conflict (jobname) do nothing;
end
$cron$;

-- ─── Conferência (aborta se o cron não nasceu como esperado) ─────────────────────────────────────────────────────────
do $conf$
begin
  if to_regnamespace('cron') is null then return; end if;
  if (select count(*) from cron.job where jobname = 'black-youtube' and schedule = '* * * * *' and active
         and command like '%where dados.black_live_pede_chamada()%' and command like '%ops.cron_post(''black-youtube''%') <> 1 then
    raise exception '20261015220100: cron black-youtube ausente ou fora do padrão';
  end if;
  if not exists (select 1 from vault.secrets where name = 'dados_black_youtube_chave') then
    raise exception '20261015220100: segredo dados_black_youtube_chave ausente';
  end if;
  if (select count(*) from ops.rotina where jobname = 'black-youtube') <> 1 then
    raise exception '20261015220100: linha do vigia ausente';
  end if;
end
$conf$;
