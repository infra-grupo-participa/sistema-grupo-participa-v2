-- Ensaio de 20261013001456 (uma foto nova por ciclo). Transação desfeita: nada persiste e nenhuma chamada HTTP sai
-- (o pg_net só envia depois do commit). Saída só com contagens, nomes de campanha e md5; nenhum telefone.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_ini (max_id bigint) on commit drop;
insert into pg_temp._z_out (passo, linha) select '01 md5 funcao antes', md5(pg_get_functiondef('dados.grupo_foto_ciclo'::regproc));
insert into pg_temp._z_out (passo, linha) select '01 acl antes', (select coalesce(proacl::text,'') || ' dono ' || pg_get_userbyid(proowner) from pg_proc where oid = 'dados.grupo_foto_ciclo'::regproc);

-- migration
-- 20261013001456: foto do grupo do SendFlow abre no máximo UMA exportação por ciclo
--
-- STATUS: ver 20261013001456.explain.md. Ensaio: 20261013001456_ensaio.sql. Reversão: 20261013001456_reversao.sql.
--
-- POR QUE (diagnóstico do Maestro, autorizado pelo Victor, 13/10/2026 ~00:10 UTC)
--   dados.grupo_foto_ciclo() abria no mesmo minuto a foto de todos os grupos elegíveis. O export-leads do SendFlow
--   tem limite por minuto: só uma passava e as outras levavam "export-leads: http 403". Sem ORDER BY, a mesma
--   campanha (BF26 - Live 03/11 - Outros) ficava sempre de fora e nunca teve foto.
--
-- O QUE FAZ
--   CREATE OR REPLACE de dados.grupo_foto_ciclo() com o corpo que está no banco (lido por pg_get_functiondef em
--   13/10/2026 00:1x UTC) e uma só mudança, no bloco "foto nova": ORDER BY (última foto concluída mais antiga,
--   nulls first; depois última tentativa mais antiga, nulls first; depois id) e LIMIT 1. Com o cron de 2 em 2 min e
--   a trava de 9 min por grupo, os 4 grupos ativos ficam com foto a cada ~10 min, um por ciclo.
--   Assinatura, dono, ACL (só postgres), search_path e o resto do corpo ficam iguais.

CREATE OR REPLACE FUNCTION dados.grupo_foto_ciclo()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261008200000: exportar -> baixar -> processar; uma foto nova por grupo a cada 10 min (9 de folga para o cron)
-- 20261013001456: só uma foto nova por ciclo (limite por minuto do export-leads do SendFlow)
declare
  r record;
  v_chave_api text;
  v_resp record;
  v_url text;
  v_feitas int := 0; v_abertas int := 0; v_erros int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('dados.grupo_foto_ciclo')) then
    return 'outro ciclo em andamento';
  end if;
  -- foto parada há mais de 15 min: erro
  update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'sem resposta em 15 min'
   where etapa in ('exportar', 'baixar') and iniciado_em < now() - interval '15 minutes';
  get diagnostics v_erros = row_count;

  -- resposta que chegou depois de a foto fechar (erro por tempo): o conteúdo também sai de net._http_response
  update net._http_response h set content = null
    from dados.grupo_fotos f
   where f.etapa in ('erro', 'feito') and f.iniciado_em > now() - interval '7 hours'
     and h.id in (f.req_exportar, f.req_baixar) and h.created >= f.iniciado_em and h.content is not null;

  -- exportar respondido: pega a URL do CSV e baixa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'exportar' and f.req_exportar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_exportar and h.created >= r.iniciado_em;
    continue when not found;
    begin
      v_url := case when v_resp.status_code = 200 and length(v_resp.content) < 10000 then (v_resp.content::jsonb ->> 'url') end;
    exception when others then v_url := null;
    end;
    -- a resposta traz a URL assinada do CSV: apaga o conteúdo e mantém o status (o vigia ops.vigiar lê o status)
    update net._http_response h set content = null where h.id = r.req_exportar;
    -- só o Storage do Firebase (barra depois do host: barra https://host@outro)
    if v_url is null or v_url !~ '^https://firebasestorage\.googleapis\.com/v0/b/[A-Za-z0-9._-]+/o/[^@\s]+$' then
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'export-leads: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
                    || case when v_resp.status_code = 200 then ' (sem URL do Storage na resposta)' else '' end
       where id = r.id;
      v_erros := v_erros + 1;
    else
      update dados.grupo_fotos set etapa = 'baixar',
             req_baixar = net.http_get(url := v_url, params := '{}'::jsonb, headers := '{}'::jsonb, timeout_milliseconds := 60000)
       where id = r.id;
    end if;
  end loop;

  -- CSV baixado: processa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'baixar' and f.req_baixar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_baixar and h.created >= r.iniciado_em;
    continue when not found;
    -- o CSV tem telefone e nome de todo o grupo: sai de net._http_response assim que é lido
    delete from net._http_response h where h.id = r.req_baixar;
    if v_resp.status_code = 200 then
      begin
        perform dados.grupo_foto_processar(r.id, v_resp.content);
        v_feitas := v_feitas + 1;
      exception when others then
        update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'processar: ' || left(sqlerrm, 200)
         where id = r.id;
        v_erros := v_erros + 1;
      end;
    else
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'csv: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
       where id = r.id;
      v_erros := v_erros + 1;
    end if;
  end loop;

  -- foto nova
  select s.decrypted_secret into v_chave_api from vault.decrypted_secrets s where s.name = 'sendflow_api_key';
  if v_chave_api is null then
    return format('feitas %s, erros %s; sem segredo sendflow_api_key no Vault: nenhuma foto nova', v_feitas, v_erros);
  end if;
  -- 20261013001456: no máximo UMA foto nova por ciclo. O SendFlow limita export-leads por minuto: abrir todas no
  -- mesmo minuto fazia só uma passar e as outras levarem 403 (e, sem ordem, sempre a mesma ficava de fora).
  -- Vai primeiro quem tem a última foto concluída mais antiga (quem nunca concluiu antes), depois a tentativa mais antiga.
  for r in
    select g.* from dados.dashboard_grupos g join dados.dashboards d on d.chave = g.chave
     where d.ativo and g.sendflow_release_id is not null
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa in ('exportar', 'baixar'))
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.iniciado_em > now() - interval '9 minutes')
     order by (select max(f.iniciado_em) from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa = 'feito') asc nulls first,
              (select max(f.iniciado_em) from dados.grupo_fotos f where f.grupo_id = g.id) asc nulls first,
              g.id
     limit 1
  loop
    insert into dados.grupo_fotos (grupo_id, req_exportar)
    values (r.id, ops.cron_post('dados-grupo-foto',
      url := 'https://sendflow.pro/sendapi/actions/export-leads',
      body := jsonb_strip_nulls(jsonb_build_object('releaseId', r.sendflow_release_id, 'includeLeft', true,
                                                   'accountId', r.sendflow_conta_id)),
      params := '{}'::jsonb,
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_chave_api, 'Content-Type', 'application/json'),
      timeout_milliseconds := 60000));
    v_abertas := v_abertas + 1;
  end loop;
  return format('feitas %s, abertas %s, erros %s', v_feitas, v_abertas, v_erros);
end
$function$;

insert into pg_temp._z_out (passo, linha) select '02 acl depois', (select coalesce(proacl::text,'') || ' dono ' || pg_get_userbyid(proowner) from pg_proc where oid = 'dados.grupo_foto_ciclo'::regproc);

-- simula: todas as fotos com mais de 9 min (todos os grupos ativos elegíveis) e roda o ciclo duas vezes
insert into pg_temp._z_ini select max(id) from dados.grupo_fotos;
update dados.grupo_fotos set iniciado_em = iniciado_em - interval '1 hour', concluido_em = concluido_em - interval '1 hour';
insert into pg_temp._z_out (passo, linha) select '03 elegiveis', (select count(*) from dados.dashboard_grupos g join dados.dashboards d on d.chave = g.chave where d.ativo and g.sendflow_release_id is not null and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa in ('exportar','baixar')))::text;
insert into pg_temp._z_out (passo, linha) select '04 ciclo 1', dados.grupo_foto_ciclo();
insert into pg_temp._z_out (passo, linha) select '04 ciclo 1 abriu', (select string_agg(g.sendflow_campanha, ' | ' order by f.id) from dados.grupo_fotos f join dados.dashboard_grupos g on g.id = f.grupo_id where f.id > (select max_id from pg_temp._z_ini));
insert into pg_temp._z_out (passo, linha) select '05 ciclo 2', dados.grupo_foto_ciclo();
insert into pg_temp._z_out (passo, linha) select '05 ciclos 1+2 abriram', (select string_agg(g.sendflow_campanha, ' | ' order by f.id) from dados.grupo_fotos f join dados.dashboard_grupos g on g.id = f.grupo_id where f.id > (select max_id from pg_temp._z_ini));

-- reversão
-- Reversão de 20261013001456: volta dados.grupo_foto_ciclo() ao corpo lido no banco antes da mudança
-- (todas as fotos elegíveis abertas no mesmo ciclo). Não apaga nada de dados.grupo_fotos.

CREATE OR REPLACE FUNCTION dados.grupo_foto_ciclo()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261008200000: exportar -> baixar -> processar; uma foto nova por grupo a cada 10 min (9 de folga para o cron)
declare
  r record;
  v_chave_api text;
  v_resp record;
  v_url text;
  v_feitas int := 0; v_abertas int := 0; v_erros int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('dados.grupo_foto_ciclo')) then
    return 'outro ciclo em andamento';
  end if;
  -- foto parada há mais de 15 min: erro
  update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'sem resposta em 15 min'
   where etapa in ('exportar', 'baixar') and iniciado_em < now() - interval '15 minutes';
  get diagnostics v_erros = row_count;

  -- resposta que chegou depois de a foto fechar (erro por tempo): o conteúdo também sai de net._http_response
  update net._http_response h set content = null
    from dados.grupo_fotos f
   where f.etapa in ('erro', 'feito') and f.iniciado_em > now() - interval '7 hours'
     and h.id in (f.req_exportar, f.req_baixar) and h.created >= f.iniciado_em and h.content is not null;

  -- exportar respondido: pega a URL do CSV e baixa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'exportar' and f.req_exportar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_exportar and h.created >= r.iniciado_em;
    continue when not found;
    begin
      v_url := case when v_resp.status_code = 200 and length(v_resp.content) < 10000 then (v_resp.content::jsonb ->> 'url') end;
    exception when others then v_url := null;
    end;
    -- a resposta traz a URL assinada do CSV: apaga o conteúdo e mantém o status (o vigia ops.vigiar lê o status)
    update net._http_response h set content = null where h.id = r.req_exportar;
    -- só o Storage do Firebase (barra depois do host: barra https://host@outro)
    if v_url is null or v_url !~ '^https://firebasestorage\.googleapis\.com/v0/b/[A-Za-z0-9._-]+/o/[^@\s]+$' then
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'export-leads: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
                    || case when v_resp.status_code = 200 then ' (sem URL do Storage na resposta)' else '' end
       where id = r.id;
      v_erros := v_erros + 1;
    else
      update dados.grupo_fotos set etapa = 'baixar',
             req_baixar = net.http_get(url := v_url, params := '{}'::jsonb, headers := '{}'::jsonb, timeout_milliseconds := 60000)
       where id = r.id;
    end if;
  end loop;

  -- CSV baixado: processa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'baixar' and f.req_baixar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_baixar and h.created >= r.iniciado_em;
    continue when not found;
    -- o CSV tem telefone e nome de todo o grupo: sai de net._http_response assim que é lido
    delete from net._http_response h where h.id = r.req_baixar;
    if v_resp.status_code = 200 then
      begin
        perform dados.grupo_foto_processar(r.id, v_resp.content);
        v_feitas := v_feitas + 1;
      exception when others then
        update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'processar: ' || left(sqlerrm, 200)
         where id = r.id;
        v_erros := v_erros + 1;
      end;
    else
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'csv: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
       where id = r.id;
      v_erros := v_erros + 1;
    end if;
  end loop;

  -- foto nova
  select s.decrypted_secret into v_chave_api from vault.decrypted_secrets s where s.name = 'sendflow_api_key';
  if v_chave_api is null then
    return format('feitas %s, erros %s; sem segredo sendflow_api_key no Vault: nenhuma foto nova', v_feitas, v_erros);
  end if;
  for r in
    select g.* from dados.dashboard_grupos g join dados.dashboards d on d.chave = g.chave
     where d.ativo and g.sendflow_release_id is not null
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa in ('exportar', 'baixar'))
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.iniciado_em > now() - interval '9 minutes')
  loop
    insert into dados.grupo_fotos (grupo_id, req_exportar)
    values (r.id, ops.cron_post('dados-grupo-foto',
      url := 'https://sendflow.pro/sendapi/actions/export-leads',
      body := jsonb_strip_nulls(jsonb_build_object('releaseId', r.sendflow_release_id, 'includeLeft', true,
                                                   'accountId', r.sendflow_conta_id)),
      params := '{}'::jsonb,
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_chave_api, 'Content-Type', 'application/json'),
      timeout_milliseconds := 60000));
    v_abertas := v_abertas + 1;
  end loop;
  return format('feitas %s, abertas %s, erros %s', v_feitas, v_abertas, v_erros);
end
$function$;

insert into pg_temp._z_out (passo, linha) select '06 md5 funcao depois da reversao', md5(pg_get_functiondef('dados.grupo_foto_ciclo'::regproc));
insert into pg_temp._z_out (passo, linha) select '06 acl depois da reversao', (select coalesce(proacl::text,'') || ' dono ' || pg_get_userbyid(proowner) from pg_proc where oid = 'dados.grupo_foto_ciclo'::regproc);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
