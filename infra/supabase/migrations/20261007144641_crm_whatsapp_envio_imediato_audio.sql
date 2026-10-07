-- STATUS: APLICADA em produção em 07/10/2026 — versão 20261007144641, nome crm_whatsapp_envio_imediato_audio (era 20261007s).
-- md5 gravado em schema_migrations = 150fa2b2f4d2639a6c5fd08efa0a7987 = este arquivo SEM estas 2 linhas de STATUS.
-- 20261007s_crm_whatsapp_envio_imediato_audio — WhatsApp do CRM (5521987545211): envio na hora + áudio gravado no computador.
-- Pedido do Arthur, 07/10/2026.
--
-- ENVIO NA HORA: a fila de saída só andava pelo cron crm-whatsapp-enviar (1/min): uma imagem levou ~1 min. Agora
--   public.crm_enviar_mensagem, depois de enfileirar, chama crm.whatsapp_disparar_envio(), que faz ops.cron_post (ADR 0001,
--   mesmo jobname 'crm-whatsapp-enviar' do cron, então o vigia soma as respostas na mesma rotina) para a Edge
--   crm-whatsapp-enviar com o header x-crm-chave lido do Vault (crm_whatsapp_envio_chave) no próprio SQL. O pg_net só
--   dispara depois do COMMIT (a fila do pg_net é tabela): a Edge já enxerga a mensagem; se a transação desfizer, nada sai.
--   O cron de 1 min fica como reserva; crm.whatsapp_fila_pegar usa SKIP LOCKED, então os dois nunca pegam a mesma mensagem.
--   Qualquer erro no disparo é engolido (o envio já está na fila; o cron cobre). Kill-switch: crm.config.envio_imediato.
-- ÁUDIO: o vendedor grava no navegador (ogg/opus = nota de voz; m4a/aac/mp3 = áudio comum, para Safari antigo) e sobe em
--   envio/<uid>/<uuid>.<ogg|m4a|aac|mp3>. crm.midia_pode_subir aceita essas extensões; crm_enviar_mensagem valida mime ×
--   extensão, até 16 MB, sem legenda, janela de 24 h; texto "[áudio]", tipo 'audio'. crm.whatsapp_fila_pegar devolve o
--   caminho/mime do áudio e recusa anexo sumido; a Edge manda /whatsapp/1/message/audio com a URL assinada (1 h).
--   Duração (até 5 min) é controlada na gravação (a tela para sozinha); o banco não decodifica áudio — o teto de 16 MB vale.
--
-- Reversão: update crm.config set envio_imediato = false (desliga o envio na hora em ~1 s; o cron segue). Voltar áudio:
--   recriar crm_enviar_mensagem, midia_pode_subir e whatsapp_fila_pegar pelos corpos de 20261007140044 (md5 na guarda).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- ── Guarda de premissa: corpos vivos exatamente como lidos em 07/10/2026 (depois de 20261007140044) ──
do $guarda$
declare r record;
begin
  for r in select * from (values
      ('public.crm_enviar_mensagem(uuid,text,uuid,text,text)', 'f59fb61616cd6d30452d5993321de752'),
      ('crm.midia_pode_subir(text)', '6491fa728acdd7fc9ffe1127c93b6814'),
      ('crm.whatsapp_fila_pegar(integer)', '1e78f6dc0c8d4aee5dba836f3d072043'),
      ('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)', '3599787bb8e14ebe17849198b9e5b342')) v(sig, esperado) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception 'premissa: % mudou (ou não existe)', r.sig;
    end if;
  end loop;
  if to_regprocedure('crm.whatsapp_disparar_envio()') is not null then raise exception 'premissa: whatsapp_disparar_envio já existe'; end if;
  if exists (select 1 from information_schema.columns c where c.table_schema = 'crm' and c.table_name = 'config' and c.column_name = 'envio_imediato') then
    raise exception 'premissa: crm.config.envio_imediato já existe';
  end if;
  if not exists (select 1 from vault.secrets s where s.name = 'crm_whatsapp_envio_chave') then raise exception 'premissa: segredo crm_whatsapp_envio_chave ausente'; end if;
  if (select j.command from cron.job j where j.jobname = 'crm-whatsapp-enviar') not like '%ops.cron_post(''crm-whatsapp-enviar''%https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar%' then
    raise exception 'premissa: cron crm-whatsapp-enviar mudou';
  end if;
end
$guarda$;

-- ── Kill-switch do envio na hora ──
alter table crm.config add column envio_imediato boolean not null default true;
comment on column crm.config.envio_imediato is
  'true = crm_enviar_mensagem chama a Edge crm-whatsapp-enviar logo depois do commit (20261007s). false = só o cron de 1 min.';

-- ── Disparo na hora (interna: só o dono executa; chamada pela RPC SECURITY DEFINER) ──
create function crm.whatsapp_disparar_envio()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare v_chave text;
begin
  if not coalesce((select c.whatsapp_ligado and c.envio_ligado and c.envio_imediato from crm.config c), false) then return null; end if;
  select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'crm_whatsapp_envio_chave';
  if coalesce(v_chave, '') = '' then return null; end if;
  -- mesmo destino, header, corpo e timeout do cron crm-whatsapp-enviar; o pg_net só envia depois do COMMIT
  return ops.cron_post('crm-whatsapp-enviar',
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-crm-chave', v_chave),
    body := '{"acao":"enviar"}'::jsonb, timeout_milliseconds := 60000);
exception when others then
  return null;  -- atalho: a mensagem já está na fila e o cron de 1 min envia
end
$$;
revoke all on function crm.whatsapp_disparar_envio() from public, anon, authenticated, service_role;

-- ── Upload: áudio na pasta do próprio usuário ──
create or replace function crm.midia_pode_subir(p_nome text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid();
begin
  if p_nome is null or v_eu is null then return false; end if;
  return p_nome ~ ('^envio/' || v_eu::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf|ogg|m4a|aac|mp3)$')
     and coalesce((select c.whatsapp_ligado and c.escrita_ligada from crm.config c), false)
     and (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false));
end
$function$;
revoke all on function crm.midia_pode_subir(text) from public, anon, service_role;
grant execute on function crm.midia_pode_subir(text) to authenticated;

-- ── Enfileirar: + áudio, + disparo na hora (mesma assinatura: create or replace) ──
create or replace function public.crm_enviar_mensagem(p_pessoa uuid, p_texto text, p_template uuid default null::uuid, p_midia text default null::text, p_midia_nome text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; v_conv uuid; cv crm.conversa%rowtype;
        t crm.template%rowtype; v_rend jsonb; v_texto text; v_tipo text := 'texto'; v_vars jsonb; v_id uuid := gen_random_uuid();
        v_s text; v_c text; v_m text;
        v_meta jsonb; v_mime text; v_tam bigint; v_ext text; v_lim bigint; v_mnome text; v_leg text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into c from crm.config;
  if not coalesce(c.whatsapp_ligado, false) then return crm.res(false, 'WhatsApp desligado.'); end if;
  if not coalesce(c.envio_ligado, false) then return crm.res(false, 'Envio de WhatsApp desligado.'); end if;
  if c.whatsapp_numero_id is null or not exists (select 1 from crm.numero_whatsapp n where n.id = c.whatsapp_numero_id and n.ativo) then
    return crm.res(false, 'Número de envio não configurado.');
  end if;
  if p_midia is not null then
    -- anexo: imagem (jpg/png/webp ≤ 5 MB), PDF (≤ 16 MB) ou áudio (ogg/m4a/aac/mp3 ≤ 16 MB, sem legenda) que a própria
    -- pessoa subiu em envio/<uid>/<uuid>.<ext>
    if p_template is not null then return crm.res(false, 'Anexo não vai junto com template.'); end if;
    v_leg := nullif(btrim(coalesce(p_texto, '')), '');
    if length(v_leg) > 1024 then return crm.res(false, 'Legenda longa demais (máximo 1.024 caracteres).'); end if;
    if v_eu is null or p_midia !~ ('^envio/' || v_eu::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf|ogg|m4a|aac|mp3)$') then
      return crm.res(false, 'Anexo inválido.');
    end if;
    select o.metadata into v_meta from storage.objects o
     where o.bucket_id = 'crm-midia' and o.name = p_midia and o.owner_id = v_eu::text;
    if not found then return crm.res(false, 'Anexo não encontrado. Anexe o arquivo de novo.'); end if;
    if exists (select 1 from crm.mensagem x where x.midia_caminho = p_midia) then return crm.res(false, 'Este anexo já foi enviado.'); end if;
    v_mime := lower(btrim(split_part(coalesce(v_meta ->> 'mimetype', ''), ';', 1)));
    v_tam := case when coalesce(v_meta ->> 'size', '') ~ '^[0-9]{1,12}$' then (v_meta ->> 'size')::bigint end;
    v_ext := substring(p_midia from '\.([a-z0-9]+)$');
    if v_mime is distinct from (case v_ext when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg' when 'png' then 'image/png'
                                            when 'webp' then 'image/webp' when 'pdf' then 'application/pdf'
                                            when 'ogg' then 'audio/ogg' when 'm4a' then 'audio/mp4' when 'aac' then 'audio/aac'
                                            when 'mp3' then 'audio/mpeg' end) then
      return crm.res(false, 'Só imagem (JPG, PNG, WebP), PDF ou áudio (OGG, M4A, AAC, MP3).');
    end if;
    v_tipo := case when v_ext = 'pdf' then 'documento' when v_ext in ('ogg', 'm4a', 'aac', 'mp3') then 'audio' else 'imagem' end;
    if v_tipo = 'audio' and v_leg is not null then return crm.res(false, 'Áudio vai sem legenda: mande o texto em outra mensagem.'); end if;
    v_lim := case when v_tipo in ('documento', 'audio') then 16777216 else 5242880 end;
    if v_tam is null or v_tam <= 0 then return crm.res(false, 'Anexo vazio.'); end if;
    if v_tam > v_lim then return crm.res(false, format('Arquivo grande demais (máximo %s MB).', v_lim / 1048576)); end if;
    if v_tipo = 'documento' then
      v_mnome := nullif(left(btrim(regexp_replace(coalesce(p_midia_nome, ''), '[\\/[:cntrl:]]', '_', 'g')), 120), '');
      v_mnome := coalesce(v_mnome, 'documento.pdf');
      if lower(v_mnome) !~ '\.pdf$' then v_mnome := left(v_mnome, 116) || '.pdf'; end if;
    end if;
  else
    if p_template is null and btrim(coalesce(p_texto, '')) = '' then return crm.res(false, 'Mensagem vazia.'); end if;
    if p_template is null and length(btrim(p_texto)) > 4096 then return crm.res(false, 'Mensagem longa demais (máximo 4.096 caracteres).'); end if;
  end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  if not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
  if crm.pessoa_optout(v_atual) then return crm.res(false, 'Contato pediu para não receber mensagens.'); end if;
  if p_template is not null then
    select * into t from crm.template x where x.id = p_template;
    if not found or not t.aprovado or not t.ativo or t.categoria not in ('marketing', 'utility') then
      return crm.res(false, 'Template não aprovado.');
    end if;
    if t.numero_id <> c.whatsapp_numero_id then return crm.res(false, 'Template de outro número de envio.'); end if;
  end if;
  -- daqui em diante a conversa pode ter sido criada: recusa = exceção P0001 (desfaz tudo) → {ok:false}
  v_conv := crm.whatsapp_conversa_para(c.whatsapp_numero_id, v_atual);
  if v_conv is null then return crm.res(false, 'Contato sem telefone de WhatsApp.'); end if;
  select * into cv from crm.conversa x where x.id = v_conv for update;
  if p_template is null then
    if cv.ultima_entrada_em is null or cv.ultima_entrada_em <= now() - interval '24 hours' then
      raise exception 'Janela de 24 h fechada: só sai template aprovado.' using errcode = 'P0001';
    end if;
    v_texto := case when p_midia is null then btrim(p_texto)
                    when v_tipo = 'audio' then '[áudio]'
                    else coalesce(v_leg, case when v_tipo = 'imagem' then '[imagem]' else '[documento] ' || v_mnome end) end;
  else
    v_rend := crm.template_render(t, v_atual, null);
    if not (v_rend ->> 'ok')::boolean then raise exception '%', v_rend ->> 'msg' using errcode = 'P0001'; end if;
    v_texto := v_rend ->> 'texto'; v_vars := v_rend -> 'vars'; v_tipo := 'template';
  end if;
  insert into crm.mensagem (id, conversa_id, pessoa_id, direcao, tipo, texto, em, status, status_em, fila_em, autor_id,
                            template_id, template_vars, provedor, provedor_msg_id,
                            midia_status, midia_caminho, midia_mime, midia_tamanho, midia_nome)
  values (v_id, cv.id, cv.pessoa_id, 'saida', v_tipo, v_texto, now(), 'na_fila', now(), now(), v_eu,
          t.id, v_vars, 'infobip', v_id::text,
          case when p_midia is not null then 'ok' end, p_midia, case when p_midia is not null then v_mime end,
          case when p_midia is not null then v_tam end, v_mnome);
  update crm.conversa x set ultima_em = now(), ultima_mensagem_id = v_id, nao_lidas = 0 where x.id = cv.id;
  update crm.mensagem x set lida_em = now() where x.conversa_id = cv.id and x.direcao = 'entrada' and x.lida_em is null;
  perform crm.log_registrar('enviou', 'mensagem', v_id::text, v_atual,
                            format('Enviou %s para %s', case when v_tipo = 'template' then 'template ' || t.nome_provedor
                                                             when v_tipo = 'imagem' then 'imagem'
                                                             when v_tipo = 'documento' then 'PDF'
                                                             when v_tipo = 'audio' then 'áudio' else 'mensagem' end,
                                   crm.nome_pessoa(v_atual)),
                            jsonb_build_object('conversa_id', cv.id, 'template_id', t.id));
  -- envio na hora (20261007s): a Edge é chamada depois do COMMIT; falha aqui nunca derruba o enfileiramento
  perform crm.whatsapp_disparar_envio();
  return crm.res(true, 'Mensagem na fila de envio.', jsonb_build_object('mensagemId', v_id));
exception
  when sqlstate 'P0001' then
    get stacked diagnostics v_m = message_text;
    return crm.res(false, v_m);
  when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke all on function public.crm_enviar_mensagem(uuid, text, uuid, text, text) from public, anon;
grant execute on function public.crm_enviar_mensagem(uuid, text, uuid, text, text) to authenticated, service_role;

-- ── Fila de saída: áudio leva caminho/mime (sem legenda) ──
create or replace function crm.whatsapp_fila_pegar(p_lote integer default null::integer)
 returns table(mensagem_id uuid, de text, para text, tipo text, texto text, template_nome text, template_idioma text, variaveis jsonb, midia_caminho text, midia_nome text, midia_mime text, legenda text)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c crm.config%rowtype; m record; v_lote int; v_erro text;
begin
  select * into c from crm.config;
  if not (coalesce(c.whatsapp_ligado, false) and coalesce(c.envio_ligado, false)) then return; end if;
  -- enviando há mais de 5 min: a Edge morreu no meio. NÃO reenvia (pode ter saído): falha incerta, o relatório corrige.
  update crm.mensagem x set status = 'falhou', falha_incerta = true, status_em = now(),
         erro = 'Sem confirmação do provedor: conferir relatório de entrega.'
   where x.status = 'enviando' and x.status_em < now() - interval '5 minutes';
  -- validade na fila (envio desligado por muito tempo não dispara coisa velha depois)
  update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Expirou na fila sem envio.'
   where x.status = 'na_fila'
     and x.fila_em < now() - make_interval(mins => case when x.ficha_id is null then c.envio_validade_min else c.disparo_validade_min end);
  perform crm.fichas_liberar();
  v_lote := least(greatest(coalesce(p_lote, c.envio_lote), 1), c.envio_lote);
  for m in select x.id, x.pessoa_id, x.tipo, x.texto, x.template_vars, cv.telefone, cv.ultima_entrada_em, n.numero, n.ativo n_ativo,
                  t.nome_provedor, t.idioma, coalesce(t.aprovado and t.ativo, false) t_ok,
                  x.midia_status, x.midia_caminho, x.midia_nome, x.midia_mime,
                  (x.midia_caminho is not null and exists (select 1 from storage.objects o
                                                           where o.bucket_id = 'crm-midia' and o.name = x.midia_caminho)) arq_ok
             from crm.mensagem x
             join crm.conversa cv on cv.id = x.conversa_id
             join crm.numero_whatsapp n on n.id = cv.numero_id
             left join crm.template t on t.id = x.template_id
            where x.status = 'na_fila' and x.fila_em <= now() and coalesce(x.proxima_tentativa_em, x.fila_em) <= now()
            order by x.fila_em, x.id
            limit v_lote
              for update of x skip locked loop
    v_erro := case when not m.n_ativo then 'Número de envio inativo.'
                   when crm.pessoa_optout(m.pessoa_id) then 'Contato pediu para não receber mensagens.'
                   when m.tipo <> 'template' and (m.ultima_entrada_em is null or m.ultima_entrada_em <= now() - interval '24 hours')
                     then 'Janela de 24 h fechou antes do envio.'
                   when m.tipo = 'template' and not m.t_ok then 'Template deixou de estar aprovado.'
                   when m.tipo in ('imagem', 'documento', 'audio') and (m.midia_status is distinct from 'ok' or not m.arq_ok)
                     then 'Arquivo do anexo indisponível.' end;
    if v_erro is not null then
      update crm.mensagem x set status = 'falhou', status_em = now(), erro = v_erro where x.id = m.id;
      continue;
    end if;
    update crm.mensagem x set status = 'enviando', status_em = now(), tentativas = x.tentativas + 1 where x.id = m.id;
    mensagem_id := m.id; de := m.numero; para := m.telefone; tipo := m.tipo; texto := m.texto;
    template_nome := m.nome_provedor; template_idioma := m.idioma; variaveis := coalesce(m.template_vars, '[]'::jsonb);
    midia_caminho := case when m.tipo in ('imagem', 'documento', 'audio') then m.midia_caminho end;
    midia_nome := case when m.tipo = 'documento' then m.midia_nome end;
    midia_mime := case when m.tipo in ('imagem', 'documento', 'audio') then m.midia_mime end;
    -- texto "[imagem]"/"[documento] nome" é rótulo do CRM, não legenda; áudio não tem legenda
    legenda := case when m.tipo in ('imagem', 'documento') and m.texto !~ '^\[(imagem|documento)\]' then m.texto end;
    return next;
  end loop;
end
$function$;
revoke all on function crm.whatsapp_fila_pegar(integer) from public, anon, authenticated, service_role;

-- ── Conferência de permissões (aborta se algo ficou aberto) ──
do $acl$
declare v text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.oid in ('crm.whatsapp_disparar_envio()'::regprocedure, 'crm.whatsapp_fila_pegar(integer)'::regprocedure)
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
          or has_function_privilege('service_role', p.oid, 'execute'));
  if v is not null then raise exception 'interna executável fora do dono: %', v; end if;
  if has_function_privilege('anon', 'public.crm_enviar_mensagem(uuid,text,uuid,text,text)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'crm.midia_pode_subir(text)'::regprocedure, 'execute') then
    raise exception 'RPC executável por anon';
  end if;
end
$acl$;
