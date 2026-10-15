-- 20261014180000: export diário dos grupos do SendFlow (decisão do Victor, 14/10/2026; substitui o desenho de 10 em 10 min).
-- dados.dashboard_grupos: foto_ate (último dia BRT com export; nulo = sem export) e dia_live (dia sem export).
-- dados.grupo_fotos: dia_sp + índice único (grupo_id, dia_sp) = no máximo 1 export por campanha por dia.
-- dados.grupo_foto_ciclo: 1 export por campanha ativa por dia, às 23h BRT, pela conta de final 2536
-- ("Criador de Comunidades 1", kennke6bAUASGleIjOng), reserva antes de chamar, teto de 6 por dia.
-- Campanhas: só ATM 10/26, até 15/10/2026. BF26 - Live 03/11 - Advogados/Contadores/Outros: conta e dia da live (03/11)
-- gravados, foto_ate nulo (sem export) até a 2536 entrar nos grupos; Consultoria ao Vivo - Aberto fora.
-- O job dados-grupo-foto (jobid 223) NÃO é ligado aqui: ligar é passo à parte, com ok do Victor.
-- Sem grant, RLS ou auth. Reversão: 20261014180000_reversao.sql. Ver 20261014180000.explain.md.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_ciclo()'::regprocedure)
      is distinct from '15f922ee8450f272159108a206692dec' then
    raise exception '20261014180000: corpo vivo de grupo_foto_ciclo mudou; revisar';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'dados'
              and ((table_name = 'dashboard_grupos' and column_name in ('foto_ate', 'dia_live'))
                or (table_name = 'grupo_fotos' and column_name = 'dia_sp'))) then
    raise exception '20261014180000: colunas já existem';
  end if;
  if (select count(*) from dados.dashboard_grupos where papel = 'dashboard' and sendflow_release_id is not null
       and sendflow_campanha in ('ATM 10/26', 'BF26 - Live 03/11 - Advogados', 'BF26 - Live 03/11 - Contadores',
                                 'BF26 - Live 03/11 - Outros')) <> 4 then
    raise exception '20261014180000: as 4 campanhas não estão como esperado';
  end if;
  if (select active from cron.job where jobname = 'dados-grupo-foto') then
    raise exception '20261014180000: o job dados-grupo-foto está ligado; desligue antes';
  end if;
end
$g$;

alter table dados.dashboard_grupos
  add column foto_ate date,
  add column dia_live date;
comment on column dados.dashboard_grupos.foto_ate is
  'Último dia (BRT) com export diário do SendFlow para a campanha. Nulo = sem export (o webhook é a fonte). 20261014180000.';
comment on column dados.dashboard_grupos.dia_live is 'Dia da live: sem export nesse dia, só webhook. 20261014180000.';

alter table dados.grupo_fotos add column dia_sp date;
comment on column dados.grupo_fotos.dia_sp is
  'Dia (BRT) do export diário; com o índice único (grupo_id, dia_sp), no máximo 1 por campanha por dia. 20261014180000.';
create unique index grupo_fotos_um_por_dia on dados.grupo_fotos (grupo_id, dia_sp);

update dados.dashboard_grupos set foto_ate = date '2026-10-15', sendflow_conta_id = 'kennke6bAUASGleIjOng'
 where papel = 'dashboard' and sendflow_campanha = 'ATM 10/26';
-- Black: sem export por enquanto (foto_ate nulo) até a conta 2536 entrar nos 9 grupos (decisão de 14/10 ~21h45);
-- conta e dia da live já gravados. Ligar = foto_ate 2026-11-05 nas 3 campanhas.
update dados.dashboard_grupos set dia_live = date '2026-11-03', sendflow_conta_id = 'kennke6bAUASGleIjOng'
 where papel = 'dashboard' and chave = 'black-friday-2026-10'
   and sendflow_campanha in ('BF26 - Live 03/11 - Advogados', 'BF26 - Live 03/11 - Contadores', 'BF26 - Live 03/11 - Outros');

CREATE OR REPLACE FUNCTION dados.grupo_foto_ciclo()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261008200000: exportar -> baixar -> processar; uma foto nova por grupo a cada 10 min (9 de folga para o cron)
-- 20261013001500: só uma foto nova por ciclo (limite por minuto do export-leads do SendFlow)
-- 20261014180000 (decisão do Victor, 14/10): o webhook é a fonte e o export é complemento. UM export por campanha por
-- dia, às 23h de Brasília, só de campanha com foto_ate >= hoje e fora do dia_live, pela conta gravada em
-- sendflow_conta_id. Teto no banco: índice único (grupo_id, dia_sp) em grupo_fotos; a linha é reservada ANTES da chamada
-- ao SendFlow, então um 2º ciclo no mesmo dia não chama nada. Sem nova tentativa no dia se der erro. Teto geral c_max_dia.
declare
  r record;
  v_chave_api text;
  v_resp record;
  v_url text;
  v_feitas int := 0; v_abertas int := 0; v_erros int := 0;
  c_max_dia constant int := 6;  -- teto de exports por dia, todas as campanhas somadas
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_foto_id bigint;
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
  -- 20261013001500: no máximo UMA foto nova por ciclo. O SendFlow limita export-leads por minuto: abrir todas no
  -- mesmo minuto fazia só uma passar e as outras levarem 403 (e, sem ordem, sempre a mesma ficava de fora).
  -- Vai primeiro quem tem a última foto concluída mais antiga (quem nunca concluiu antes), depois a tentativa mais antiga.
  for r in
    select g.* from dados.dashboard_grupos g join dados.dashboards d on d.chave = g.chave
     where d.ativo and g.sendflow_release_id is not null
       -- 20261014180000: só campanha ativa (foto_ate >= hoje), fora do dia da live, às 23h BRT, ainda sem foto hoje
       and g.foto_ate is not null and v_hoje <= g.foto_ate
       and (g.dia_live is null or v_hoje <> g.dia_live)
       and extract(hour from now() at time zone 'America/Sao_Paulo') = 23
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.dia_sp = v_hoje)
       and (select count(*) from dados.grupo_fotos f where f.dia_sp = v_hoje) < c_max_dia
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa in ('exportar', 'baixar'))
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.iniciado_em > now() - interval '9 minutes')
     order by (select max(f.iniciado_em) from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa = 'feito') asc nulls first,
              (select max(f.iniciado_em) from dados.grupo_fotos f where f.grupo_id = g.id) asc nulls first,
              g.id
     limit 1
  loop
    -- 20261014180000: reserva a foto do dia antes de chamar; se o dia já tem foto (índice único), não chama nada.
    v_foto_id := null;
    insert into dados.grupo_fotos (grupo_id, dia_sp) values (r.id, v_hoje)
    on conflict (grupo_id, dia_sp) do nothing
    returning id into v_foto_id;
    continue when v_foto_id is null;
    update dados.grupo_fotos set req_exportar = ops.cron_post('dados-grupo-foto',
      url := 'https://sendflow.pro/sendapi/actions/export-leads',
      body := jsonb_strip_nulls(jsonb_build_object('releaseId', r.sendflow_release_id, 'includeLeft', true,
                                                   'accountId', r.sendflow_conta_id)),
      params := '{}'::jsonb,
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_chave_api, 'Content-Type', 'application/json'),
      timeout_milliseconds := 60000)
     where id = v_foto_id;
    v_abertas := v_abertas + 1;
  end loop;
  return format('feitas %s, abertas %s, erros %s', v_feitas, v_abertas, v_erros);
end
$function$;
