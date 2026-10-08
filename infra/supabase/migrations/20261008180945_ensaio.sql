-- Ensaio de 20261008180945_crm_integracoes_status — termina em ROLLBACK (rodado em produção em 08/10/2026, antes de aplicar).
-- Esperado (obtido):
--   gestor / vendedor / leitor = ok, ≈25 ms (3ª chamada), 10 integrações + 1 número (Comercial oficial, infobip, conectado, final 5211)
--   operador (fora do Comercial) = ERRO 42501 Sem acesso ao Comercial.
--   anon = ERRO 42501 permission denied for function crm_integracoes_status
--   proacl = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} · public_exec = false · anon_exec = false
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('public.crm_integracoes_status()') is not null then
    raise exception 'premissa: public.crm_integracoes_status() já existe';
  end if;
  if to_regclass('crm.evento_jornada_fonte_recebido_idx') is not null or to_regclass('crm.mensagem_numero_em_idx') is not null then
    raise exception 'premissa: índices já existem';
  end if;
  if (select count(*) from crm.config) <> 1 then raise exception 'premissa: crm.config precisa ter 1 linha'; end if;
  if to_regprocedure('crm.eh_comercial()') is null or to_regclass('ops.rotina_estado') is null
     or to_regclass('controle.grupo_evento_unificado') is null or to_regclass('respondi.respostas') is null then
    raise exception 'premissa: crm.eh_comercial, ops.rotina_estado, controle.grupo_evento_unificado ou respondi.respostas ausente';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'crm' and table_name = 'config'
         and column_name in ('hotmart_ligado', 'hotmart_desde', 'whatsapp_ligado', 'evolution_ligado', 'activecampaign_ligado',
                             'unnichat_ligado', 'sendflow_ligado', 'respondi_ligado', 'slack_ligado', 'mcp_ligado',
                             'clint_import_ligado', 'whatsapp_numero_id', 'infobip_base_url')) <> 13 then
    raise exception 'premissa: colunas de kill-switch em crm.config mudaram';
  end if;
end $g$;

-- Último evento / 24 h por fonte sem varrer o activecampaign (≈22 mil/dia) para achar unnichat/sendflow.
create index evento_jornada_fonte_recebido_idx on crm.evento_jornada (fonte, recebido_em desc);
-- Última mensagem e volume de 24 h por número de WhatsApp (o índice existente é parcial: só saída não externa).
create index mensagem_numero_em_idx on crm.mensagem (numero_id, em desc);

create function public.crm_integracoes_status()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
-- crm_integracoes_status: status VIVO de cada integração do Comercial para a aba Integrações (só leitura).
-- Fatos crus: ligada (kill-switch em crm.config), configurada (segredo existe no Vault — só o NOME, nunca o valor),
-- último evento, eventos nas 24 h e erro recente (dado da fonte ou vigia de rotinas). Quem deriva o selo
-- (conectada / sem eventos / desligada / não configurada / em breve) é a regra pura do front (domain/integracoes-status.ts).
declare
  c crm.config%rowtype;
  v_24h timestamptz := now() - interval '24 hours';
  v_seg text[];
  v_rot jsonb;
  v_num jsonb;
  v_res jsonb := '[]'::jsonb;
begin
  if not coalesce(crm.eh_comercial(), false) then
    raise exception 'Sem acesso ao Comercial.' using errcode = '42501';
  end if;

  select * into c from crm.config limit 1;
  select coalesce(array_agg(s.name), '{}') into v_seg from vault.secrets s
   where s.name = any (array['fin_hotmart_sync_chave', 'infobip_api_key', 'crm_whatsapp_webhook_chave', 'evolution_api_key',
                             'evolution_api_url', 'crm_webhook_unnichat', 'crm_webhook_activecampaign', 'crm_webhook_sendflow',
                             'respondi_sync_chave', 'crm_slack_webhook', 'clint_api_token']);

  -- Vigia de rotinas: só falha REAL (última chamada não foi ok). "Nenhum sucesso em 30 min" de job que só chama quando há
  -- trabalho fica de fora (alarme do vigia, não da integração).
  select coalesce(jsonb_object_agg(r.jobname, jsonb_build_object(
           'texto', 'Rotina ' || r.jobname || ': ' || coalesce(r.incidente_motivo, r.ultima_classe)
                    || coalesce(' (' || left(r.ultimo_erro, 120) || ')', ''),
           'em', coalesce(r.ultimo_evento_em, r.incidente_aberto_em))), '{}'::jsonb)
    into v_rot
    from ops.rotina_estado r
   where r.jobname in ('fin-hotmart-sync-rotina', 'fin-hotmart-sync-fila', 'crm-whatsapp-enviar', 'crm-whatsapp-templates',
                       'crm-evolution-enviar', 'crm-slack-fila', 'respondi-sync', 'ingest-sendflow-30min')
     and r.incidente_aberto_em is not null and coalesce(r.ultima_classe, 'ok') <> 'ok';

  -- Números de WhatsApp: últimos 4 dígitos, nunca o número inteiro. Última mensagem por número (índice numero_id, em).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id, 'nome', n.nome, 'provedor', n.provedor, 'status', n.status, 'statusEm', n.status_em,
           'statusMotivo', n.status_motivo, 'final', right(n.numero, 4), 'ativo', n.ativo,
           'principal', n.id = c.whatsapp_numero_id, 'recebe', n.recebe, 'envia', n.envia,
           'ultimaMensagemEm', m.ultima, 'mensagens24h', m.n24, 'falhas24h', m.f24, 'ultimaFalha', m.falha)
           order by n.ativo desc, (n.id = c.whatsapp_numero_id) desc, n.nome), '[]'::jsonb)
    into v_num
    from crm.numero_whatsapp n
    left join lateral (
      select (select max(x.em) from crm.mensagem x where x.numero_id = n.id) ultima,
             count(*) n24,
             count(*) filter (where y.status = 'falhou') f24,
             (select jsonb_build_object('texto', 'Mensagem falhou: ' || coalesce(left(z.erro, 160), 'sem detalhe'), 'em', z.status_em)
                from crm.mensagem z where z.numero_id = n.id and z.em >= v_24h and z.status = 'falhou'
               order by z.em desc limit 1) falha
        from crm.mensagem y where y.numero_id = n.id and y.em >= v_24h) m on true;

  -- Hotmart: o que o CRM processou (webhook em tempo real + sync das 2 contas).
  v_res := v_res || jsonb_build_object(
    'chave', 'hotmart', 'ligada', coalesce(c.hotmart_ligado, false) and c.hotmart_desde is not null,
    'configurada', 'fin_hotmart_sync_chave' = any (v_seg),
    'ultimoEventoEm', (select max(h.processado_em) from crm.hotmart_processado h),
    'eventos24h', (select count(*) from crm.hotmart_processado h where h.processado_em >= v_24h),
    'erroRecente', coalesce(
       (select jsonb_build_object('texto', 'Evento com erro: ' || left(regexp_replace(h.resultado, '^erro\s*:?\s*', ''), 160), 'em', h.processado_em)
          from crm.hotmart_processado h where h.resultado like 'erro%' and h.processado_em >= v_24h
         order by h.processado_em desc limit 1),
       v_rot -> 'fin-hotmart-sync-fila', v_rot -> 'fin-hotmart-sync-rotina'));

  -- WhatsApp por provedor: soma dos números daquele provedor.
  v_res := v_res || (
    select jsonb_agg(jsonb_build_object(
             'chave', p.prov,
             'ligada', case p.prov when 'infobip' then coalesce(c.whatsapp_ligado, false) else coalesce(c.evolution_ligado, false) end,
             'configurada', case p.prov
                              when 'infobip' then 'infobip_api_key' = any (v_seg) and 'crm_whatsapp_webhook_chave' = any (v_seg)
                                                  and c.infobip_base_url is not null
                              else 'evolution_api_key' = any (v_seg) and 'evolution_api_url' = any (v_seg) end,
             'ultimoEventoEm', (select max((e ->> 'ultimaMensagemEm')::timestamptz) from jsonb_array_elements(v_num) e where e ->> 'provedor' = p.prov),
             'eventos24h', coalesce((select sum((e ->> 'mensagens24h')::int) from jsonb_array_elements(v_num) e where e ->> 'provedor' = p.prov), 0),
             'erroRecente', coalesce(
                (select e -> 'ultimaFalha' from jsonb_array_elements(v_num) e
                  where e ->> 'provedor' = p.prov and jsonb_typeof(e -> 'ultimaFalha') = 'object'
                  order by e #>> '{ultimaFalha,em}' desc limit 1),
                case p.prov when 'infobip' then coalesce(v_rot -> 'crm-whatsapp-enviar', v_rot -> 'crm-whatsapp-templates')
                            else v_rot -> 'crm-evolution-enviar' end)))
      from (values ('infobip'), ('evolution')) p(prov));

  -- Webhooks da jornada (crm.evento_jornada; índice fonte, recebido_em).
  v_res := v_res || (
    select jsonb_agg(jsonb_build_object(
             'chave', f.fonte, 'ligada', f.ligada, 'configurada', f.segredo = any (v_seg),
             'ultimoEventoEm', greatest((select max(j.recebido_em) from crm.evento_jornada j where j.fonte = f.fonte), f.extra_ult),
             'eventos24h', (select count(*) from crm.evento_jornada j where j.fonte = f.fonte and j.recebido_em >= v_24h) + f.extra_24h,
             'erroRecente', v_rot -> f.rotina))
      from (values
              ('activecampaign', coalesce(c.activecampaign_ligado, false), 'crm_webhook_activecampaign', null::timestamptz, 0::bigint, null::text),
              ('unnichat', coalesce(c.unnichat_ligado, false), 'crm_webhook_unnichat', null, 0, null),
              -- SendFlow: além do webhook, a ingestão (ingest-sendflow-30min) grava em controle.grupo_evento_unificado,
              -- que é o que a jornada mostra (índice ix_geu_tipo).
              ('sendflow', coalesce(c.sendflow_ligado, false), 'crm_webhook_sendflow',
               (select max(g.ocorreu_em) from controle.grupo_evento_unificado g where g.tipo in ('entrada', 'saida')),
               (select count(*) from controle.grupo_evento_unificado g where g.tipo in ('entrada', 'saida') and g.ocorreu_em >= v_24h),
               'ingest-sendflow-30min')
           ) f(fonte, ligada, segredo, extra_ult, extra_24h, rotina));

  -- Respondi: a jornada lê respondi.respostas (respondi-sync, 1×/dia).
  v_res := v_res || jsonb_build_object(
    'chave', 'respondi', 'ligada', coalesce(c.respondi_ligado, false), 'configurada', 'respondi_sync_chave' = any (v_seg),
    'ultimoEventoEm', (select max(r.respondido_em) from respondi.respostas r),
    'eventos24h', (select count(*) from respondi.respostas r where r.respondido_em >= v_24h),
    'erroRecente', v_rot -> 'respondi-sync');

  -- Slack: fila de avisos (crm.slack_fila).
  v_res := v_res || jsonb_build_object(
    'chave', 'slack', 'ligada', coalesce(c.slack_ligado, false), 'configurada', 'crm_slack_webhook' = any (v_seg),
    'ultimoEventoEm', (select max(s.enviado_em) from crm.slack_fila s),
    'eventos24h', (select count(*) from crm.slack_fila s where s.enviado_em >= v_24h),
    'erroRecente', coalesce(
       (select jsonb_build_object('texto', 'Aviso não enviado: ' || left(s.erro, 160), 'em', coalesce(s.tentado_em, s.criado_em))
          from crm.slack_fila s where s.erro is not null and s.enviado_em is null and s.criado_em >= v_24h
         order by s.id desc limit 1),
       v_rot -> 'crm-slack-fila'));

  -- MCP: "configurada" = existe token/conexão ativa (não há segredo; o acesso é por token de cada pessoa).
  v_res := v_res || jsonb_build_object(
    'chave', 'mcp', 'ligada', coalesce(c.mcp_ligado, false),
    'configurada', exists (select 1 from crm.mcp_token t where t.revogado_em is null and t.expira_em > now()),
    'ultimoEventoEm', (select max(m.em) from crm.mcp_chamada m),
    'eventos24h', (select count(*) from crm.mcp_chamada m where m.em >= v_24h),
    'erroRecente', null);

  -- Clint: só migração (crm.log canal clint_import).
  v_res := v_res || jsonb_build_object(
    'chave', 'clint', 'ligada', coalesce(c.clint_import_ligado, false), 'configurada', 'clint_api_token' = any (v_seg),
    'ultimoEventoEm', (select max(l.em) from crm.log l where l.canal = 'clint_import'),
    'eventos24h', (select count(*) from crm.log l where l.canal = 'clint_import' and l.em >= v_24h),
    'erroRecente', null);

  return jsonb_build_object('geradoEm', now(), 'integracoes', v_res, 'numeros', v_num);
end
$$;
revoke all on function public.crm_integracoes_status() from public, anon;
grant execute on function public.crm_integracoes_status() to authenticated, service_role;
analyze crm.evento_jornada; analyze crm.mensagem;
create temp table _r(t text, v text) on commit drop;
grant all on _r to anon, authenticated;
do $$
declare r record; t0 timestamptz; j jsonb; i int;
begin
  for r in select * from (values ('gestor','bd5361bc-3c3f-4f85-8b5a-f21433d040e3'), ('vendedor','9d347183-5395-434e-9e96-2a65dde1a3cd'),
                                 ('leitor','00b177e0-3c8b-4e55-8f64-f57560bbbd74'), ('operador','0788cdcd-9a6e-4850-897d-89f3724f57b4')) v(p, uid) loop
    perform set_config('request.jwt.claims', json_build_object('sub', r.uid, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      for i in 1..3 loop
        t0 := clock_timestamp();
        j := public.crm_integracoes_status();
      end loop;
      reset role;
      insert into _r values (r.p, 'ok ' || round(extract(epoch from clock_timestamp() - t0) * 1000, 2) || ' ms · ' ||
        (select string_agg(e ->> 'chave' || '=' || (e ->> 'ligada') || '/' || (e ->> 'configurada') || '/' || coalesce(e ->> 'ultimoEventoEm', '-')
                 || '/' || (e ->> 'eventos24h') || coalesce('/ERRO:' || (e #>> '{erroRecente,texto}'), ''), ' | ')
           from jsonb_array_elements(j -> 'integracoes') e)
        || ' · numeros=' || (select string_agg(n ->> 'nome' || ':' || (n ->> 'provedor') || ':' || (n ->> 'status') || ':' || (n ->> 'final')
                                                || ':' || coalesce(n ->> 'ultimaMensagemEm', '-') || ':' || (n ->> 'mensagens24h'), ', ')
                             from jsonb_array_elements(j -> 'numeros') n));
    exception when others then
      reset role;
      insert into _r values (r.p, 'ERRO ' || sqlstate || ' ' || sqlerrm);
    end;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
  begin
    j := public.crm_integracoes_status();
    reset role;
    insert into _r values ('anon', 'EXECUTOU (ruim)');
  exception when others then
    reset role;
    insert into _r values ('anon', 'ERRO ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;
insert into _r select 'proacl', proacl::text from pg_proc where oid = 'public.crm_integracoes_status()'::regprocedure;
insert into _r select 'public_exec', has_function_privilege('public', 'public.crm_integracoes_status()', 'execute')::text;
insert into _r select 'anon_exec', has_function_privilege('anon', 'public.crm_integracoes_status()', 'execute')::text;
select * from _r;
rollback;
