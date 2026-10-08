-- Reversão de 20261008230000 (fila do webhook do CRM). Volta ao estado lido em 08/10/2026, sem apagar dado:
--   a fila é ARQUIVADA (renomeada), não apagada; as funções novas saem; a RPC e o gatilho voltam ao corpo vivo de
--   08/10 (pg_get_functiondef, md5 7f3af05c… e o do gatilho); o cron sai; as 2 colunas de crm.config saem.
-- Freio sem reverter (instantâneo, sem DDL): update crm.config set integracao_fila_ligada = false;  (caminho antigo)
-- Aborta se houver item pendente/erro: drene antes (select crm.integracao_processar_fila(); até zerar) ou decida
-- perdê-los conscientemente (eles ficam na tabela arquivada).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $g$
declare v_n int;
begin
  select count(*) into v_n from crm.integracao_fila where estado in ('pendente', 'erro');
  if v_n > 0 then
    raise exception 'reversão 20261008230000: % itens pendentes/erro na fila; drene antes', v_n;
  end if;
end
$g$;

select cron.unschedule('crm-integracao-fila') where exists (select 1 from cron.job where jobname = 'crm-integracao-fila');

CREATE OR REPLACE FUNCTION public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ligado boolean; v_seg text; e jsonb; v_id bigint; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0; v_criadas int := 0;
  v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end
    into v_ligado from crm.config c;
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
    begin
      v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, now());
    exception when others then v_quando := null;
    end;
    if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
       or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > now() + interval '1 day' then
      v_inval := v_inval + 1; continue;
    end if;
    v_utm := jsonb_strip_nulls(jsonb_build_object(
               'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
               'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
    insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, fone_key, nome, lista, tag, dados)
    values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando,
            pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
            nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
            nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
            case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
    begin
      -- 20261007a: só o AC leva o telefone (cria/completa a pessoa); o número não é gravado no evento
      v_res := crm.anexar_integracao(v_id, case when p_fonte = 'activecampaign' then left(e ->> 'telefone', 40) end);
      if v_res in ('anexado', 'pessoa_criada') then v_anex := v_anex + 1; end if;
      if v_res = 'pessoa_criada' then v_criadas := v_criadas + 1; end if;
    exception when others then
      raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    end;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'pessoas_criadas', v_criadas, 'invalidos', v_inval);
end
$function$;

CREATE OR REPLACE FUNCTION crm.tg_ativacao_ac()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_dados jsonb; v_proj text;
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return null; end if;
  begin
    v_dados := jsonb_strip_nulls(jsonb_build_object('tipo', new.tipo, 'lista', nullif(nullif(btrim(coalesce(new.lista, '')), ''), '0'),
                                                    'tag', nullif(btrim(coalesce(new.tag, '')), ''), 'utm', new.dados -> 'utm',
                                                    'eventoId', new.id));
    v_proj := crm.projeto_do_evento('activecampaign', v_dados);
    if v_proj is not null then
      perform crm.ativacao_entrar(v_proj, new.pessoa_id, 'activecampaign', 'ej-' || new.id, crm.mql_do_evento('activecampaign', v_dados),
                                  case when new.tipo = 'subscribe' then 'inscrição na lista ' || coalesce(new.lista, '?')
                                       else 'tag ' || coalesce(new.tag, '?') end);
    end if;
  exception when others then
    raise warning 'crm.tg_ativacao_ac: evento % (%: %)', new.id, sqlstate, sqlerrm;   -- nunca derruba o webhook
  end;
  return null;
end
$function$;

drop function crm.integracao_processar_fila(integer);
drop function crm.ativacao_ac_evento(crm.evento_jornada);
drop function crm.integracao_gravar_evento(text, jsonb, timestamptz);

-- arquivo sem PII desnecessária: o processado já está em crm.evento_jornada; tira e-mail/telefone/nome do jsonb.
-- O resto (descartado/erro) guarda PII para reprocessar: prazo de 30 dias no explain (comando de expurgo).
update crm.integracao_fila set evento = evento - 'email' - 'telefone' - 'nome' where estado = 'processado';
alter table crm.integracao_fila rename to integracao_fila_arquivo_20261008;
comment on table crm.integracao_fila_arquivo_20261008 is
  'Arquivo da reversão de 20261008230000. Expurgo: delete … where recebido_em < now() - interval ''30 days'' (ver explain).';
alter table crm.config drop column integracao_fila_ligada, drop column integracao_rajada_por_minuto;
