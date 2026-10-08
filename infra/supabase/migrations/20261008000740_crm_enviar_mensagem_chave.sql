-- 20261008000740 (era 20261008ch): envio idempotente no WhatsApp do CRM (Onda 1 da auditoria, item 3) + apagar upload órfão.
--
--
-- STATUS: APLICADA em produção em 08/10/2026 (versão 20261008000740, nome crm_enviar_mensagem_chave).
-- POR QUE
--   Duplo clique, Ctrl+Enter repetido ou retry depois de rede instável mandavam a MESMA mensagem duas vezes ao lead.
--   O front agora trava o envio (useRef), e o banco passa a aceitar uma chave de idempotência: a mesma chave devolve a
--   mesma mensagem (ok, repetida=true) sem inserir de novo. Também: anexo/áudio recusado deixava o arquivo órfão no
--   bucket crm-midia; agora quem subiu pode apagar o PRÓPRIO upload que nenhuma mensagem usa.
--
-- O QUE MUDA
--   crm.mensagem.chave uuid (nova, nula) + índice único parcial mensagem_chave_idx.
--   public.crm_enviar_mensagem: drop da assinatura de 5 parâmetros + create com p_chave uuid default null (6º). O corpo
--   parte do VIVO (md5 a626f59bdafaa2ca6e27c3c22c64d697, conferido na guarda). Diferenças: (1) com p_chave, se já há
--   mensagem com a chave e o autor sou eu → ok + mensagemId + repetida; de outro autor → recusa; (2) insert grava chave;
--   (3) corrida (2 chamadas simultâneas com a mesma chave): unique_violation em mensagem_chave_idx → devolve a vencedora.
--   crm.midia_pode_apagar(text) + policy crm_midia_apagar (DELETE em storage.objects): só envio/<meu uid>/..., só se
--   nenhuma crm.mensagem aponta para o caminho.
--
-- REVERSÃO: recriar a assinatura antiga a partir de pg_get_functiondef gravado no .explain.md; drop policy
--   crm_midia_apagar; drop function crm.midia_pode_apagar; a coluna pode ficar (nula, sem efeito).

do $$
begin
  if md5(pg_get_functiondef('public.crm_enviar_mensagem(uuid,text,uuid,text,text)'::regprocedure)) <> 'a626f59bdafaa2ca6e27c3c22c64d697' then
    raise exception 'guarda: crm_enviar_mensagem mudou desde a leitura (md5 diferente)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'mensagem' and column_name = 'chave') then
    raise exception 'guarda: crm.mensagem.chave já existe';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'crm_midia_apagar') then
    raise exception 'guarda: policy crm_midia_apagar já existe';
  end if;
end $$;

alter table crm.mensagem add column chave uuid;
comment on column crm.mensagem.chave is 'Chave de idempotência do envio (crm_enviar_mensagem p_chave): mesma chave = mesma mensagem.';
create unique index mensagem_chave_idx on crm.mensagem (chave) where chave is not null;

drop function public.crm_enviar_mensagem(uuid, text, uuid, text, text);

create function public.crm_enviar_mensagem(p_pessoa uuid, p_texto text, p_template uuid DEFAULT NULL::uuid, p_midia text DEFAULT NULL::text, p_midia_nome text DEFAULT NULL::text, p_chave uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; v_conv uuid; cv crm.conversa%rowtype;
        t crm.template%rowtype; v_rend jsonb; v_texto text; v_tipo text := 'texto'; v_vars jsonb; v_id uuid := gen_random_uuid();
        v_s text; v_c text; v_m text;
        v_meta jsonb; v_mime text; v_tam bigint; v_ext text; v_lim bigint; v_mnome text; v_leg text;
        v_dup uuid; v_dup_autor uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  -- idempotência (20261008ch): a mesma chave devolve a mesma mensagem, sem inserir de novo
  if p_chave is not null then
    select m.id, m.autor_id into v_dup, v_dup_autor from crm.mensagem m where m.chave = p_chave;
    if v_dup is not null then
      if v_dup_autor is distinct from v_eu then return crm.res(false, 'Chave de envio inválida.'); end if;
      return crm.res(true, 'Mensagem já enviada.', jsonb_build_object('mensagemId', v_dup, 'repetida', true));
    end if;
  end if;
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
                            midia_status, midia_caminho, midia_mime, midia_tamanho, midia_nome, chave)
  values (v_id, cv.id, cv.pessoa_id, 'saida', v_tipo, v_texto, now(), 'na_fila', now(), now(), v_eu,
          t.id, v_vars, 'infobip', v_id::text,
          case when p_midia is not null then 'ok' end, p_midia, case when p_midia is not null then v_mime end,
          case when p_midia is not null then v_tam end, v_mnome, p_chave);
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
  when unique_violation then
    get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
    -- corrida com a mesma chave: a outra chamada venceu (o índice esperou o COMMIT dela) → devolve a mensagem dela
    if v_c = 'mensagem_chave_idx' and p_chave is not null then
      select m.id into v_dup from crm.mensagem m where m.chave = p_chave and m.autor_id = v_eu;
      if v_dup is not null then
        return crm.res(true, 'Mensagem já enviada.', jsonb_build_object('mensagemId', v_dup, 'repetida', true));
      end if;
    end if;
    return crm.erro_dados(v_s, v_m, v_c);
  when check_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

revoke all on function public.crm_enviar_mensagem(uuid, text, uuid, text, text, uuid) from public, anon;
grant execute on function public.crm_enviar_mensagem(uuid, text, uuid, text, text, uuid) to authenticated, service_role;

-- Apagar o PRÓPRIO upload que nenhuma mensagem usa (anexo/áudio recusado ou repetido).
create function crm.midia_pode_apagar(p_nome text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid();
begin
  if p_nome is null or v_eu is null then return false; end if;
  if p_nome !~ ('^envio/' || v_eu::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf|ogg|m4a|aac|mp3)$') then
    return false;
  end if;
  if not (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false)) then return false; end if;
  return not exists (select 1 from crm.mensagem m where m.midia_caminho = p_nome);
end
$function$;

revoke all on function crm.midia_pode_apagar(text) from public, anon;
grant execute on function crm.midia_pode_apagar(text) to authenticated;

create policy crm_midia_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'crm-midia' and crm.midia_pode_apagar(name));
