-- Ensaio de 20261007144641_crm_whatsapp_envio_imediato_audio (era 20261007s) — tudo numa transação abortada por raise (resultado no erro) + ROLLBACK.
-- Nada persiste e nenhuma chamada HTTP sai: o pg_net só lê a fila (net.http_request_queue) depois de COMMIT.
-- JWT real: gestor Arthur 3bd183e5… (admin, comercial), vendedor Marcos Paulo 9d347183… (operador, comercial). Telefone
-- fictício 5521999990002 (0 conversa, 0 identificador). Nenhuma mensagem real.
-- Esperado (chaves do _r):
--   1.*  webhook ok; pessoa criada (janela aberta)
--   2.*  vendedor sobe .ogg e .m4a na própria pasta (inseriu); .webm e .wav recusados 42501
--   3.*  ogg ok, m4a ok (legenda em branco = sem legenda), mp3 de 16 MB ok; mime trocado "Só imagem…, PDF ou áudio…";
--        17 MB "Arquivo grande demais (máximo 16 MB)."; com legenda "Áudio vai sem legenda…"; .webm "Anexo inválido.";
--        repetido "Este anexo já foi enviado."; imagem e texto continuam ok; linhas audio "[áudio]" na_fila mst ok com mime;
--        log "Enviou áudio para …"
--   4.*  5 envios aceitos = 5 pedidos na fila do pg_net e 5 em ops.rotina_chamada (job crm-whatsapp-enviar, url da Edge),
--        header com chave de 64, POST, 60 s; envio_imediato=false → envia e 0 pedido;
--        authenticated chamando crm.whatsapp_disparar_envio direto → 42501
--   5.*  fila: audio ogg e mp3 com caminho/mime, legenda null, texto "[áudio]"; m4a apagado do Storage → falhou "Arquivo do anexo indisponível."
--   6.*  disparar_envio e fila_pegar só do dono; crm_enviar_mensagem auth+srv; midia_pode_subir auth; anon nada; envio_imediato true
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _r (k text, v jsonb) on commit drop;
grant all on _r to authenticated, anon;

-- Resultado da execução final (07/10/2026): TODOS os esperados acima conferiram (ver 20261007144641.explain.md, seção Ensaio).

-- ══ MIGRATION (conteúdo idêntico ao arquivo) ══
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

-- ══ TESTES ══
-- 0. Base para medir o disparo (dentro da transação: o pg_net só veria a fila depois de um COMMIT, que nunca acontece)
select set_config('ensaio.q0', (select count(*)::text from net.http_request_queue), true);
select set_config('ensaio.c0', (select coalesce(max(request_id), 0)::text from ops.rotina_chamada), true);

-- 1. Entrada fictícia abre a janela de 24 h (telefone 5521999990002, conferido: 0 conversa, 0 identificador)
select set_config('ensaio.agora', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"+0000"'), true);
insert into _r select '1.webhook', crm.whatsapp_webhook(jsonb_build_object('results', jsonb_build_array(
  jsonb_build_object('from', '5521999990002', 'to', '5521987545211', 'messageId', 'ensaio-audio-in', 'receivedAt', current_setting('ensaio.agora'),
    'contact', jsonb_build_object('name', 'Ensaio Audio'), 'message', jsonb_build_object('type', 'TEXT', 'text', 'oi')))));
select set_config('ensaio.pessoa', (select m.pessoa_id::text from crm.mensagem m where m.provedor_msg_id = 'ensaio-audio-in'), true);
insert into _r select '1.pessoa', to_jsonb(current_setting('ensaio.pessoa', true) is not null and current_setting('ensaio.pessoa', true) <> '');

-- 2. Upload (policy do Storage, JWT real do vendedor Marcos): ogg/m4a na própria pasta ok; webm/wav recusados
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
set local role authenticated;
do $t2$
declare nome text; r text;
begin
  foreach nome in array array['envio/9d347183-5395-434e-9e96-2a65dde1a3cd/11111111-1111-4111-8111-111111111111.ogg',
                              'envio/9d347183-5395-434e-9e96-2a65dde1a3cd/11111111-1111-4111-8111-111111111112.m4a',
                              'envio/9d347183-5395-434e-9e96-2a65dde1a3cd/11111111-1111-4111-8111-111111111113.webm',
                              'envio/9d347183-5395-434e-9e96-2a65dde1a3cd/11111111-1111-4111-8111-111111111114.wav'] loop
    begin
      insert into storage.objects (bucket_id, name, owner_id, metadata) values ('crm-midia', nome, auth.uid()::text, '{"mimetype":"audio/ogg","size":10}');
      r := 'inseriu';
    exception when insufficient_privilege then r := 'recusado 42501';
    end;
    insert into _r values ('2.' || substring(nome from '\.([a-z0-9]+)$'), to_jsonb(r));
  end loop;
end
$t2$;
reset role;

-- 3. Envio de áudio (gestor Arthur; janela aberta pelo item 1)
insert into storage.objects (bucket_id, name, owner_id, metadata) values
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000001.ogg', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/ogg","size":41234}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000002.m4a', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/mp4","size":52000}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000003.ogg', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/webm","size":4000}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000004.ogg', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/ogg","size":17000000}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000005.ogg', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/ogg","size":3000}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000006.mp3', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"audio/mpeg","size":16777216}'),
  ('crm-midia', 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000007.png', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"mimetype":"image/png","size":2048}');
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('3.ogg_ok', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000001.ogg'));
insert into _r values ('3.m4a_ok', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, '  ', null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000002.m4a'));
insert into _r values ('3.mp3_16mb_ok', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000006.mp3'));
insert into _r values ('3.mime_trocado', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000003.ogg'));
insert into _r values ('3.grande', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000004.ogg'));
insert into _r values ('3.com_legenda', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, 'ouve aí', null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000005.ogg'));
insert into _r values ('3.webm_invalido', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000008.webm'));
insert into _r values ('3.repetido', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, null, null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000001.ogg'));
insert into _r values ('3.imagem_continua', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, 'foto', null,
  'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000007.png'));
insert into _r values ('3.texto_continua', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, 'texto simples'));
reset role;
insert into _r select '3.linhas', jsonb_agg(jsonb_build_object('tipo', m.tipo, 'texto', m.texto, 'st', m.status, 'mst', m.midia_status,
                                                              'mime', m.midia_mime, 'tam', m.midia_tamanho) order by m.tipo, m.midia_mime)
  from crm.mensagem m where m.direcao = 'saida' and m.pessoa_id = current_setting('ensaio.pessoa')::uuid;
insert into _r select '3.log', jsonb_agg(l.resumo order by l.id) from crm.log l
 where l.acao = 'enviou' and l.entidade_id in (select m.id::text from crm.mensagem m where m.direcao = 'saida' and m.pessoa_id = current_setting('ensaio.pessoa')::uuid);

-- 4. Disparo na hora: 1 pedido por envio aceito (5), nenhum pelos recusados; mesmo jobname/url do cron; chave do Vault no header
insert into _r select '4.disparos', jsonb_build_object(
  'fila_net', (select count(*) from net.http_request_queue) - current_setting('ensaio.q0')::bigint,
  'chamadas', (select jsonb_agg(distinct jsonb_build_object('job', ch.jobname, 'url', ch.url)) from ops.rotina_chamada ch where ch.request_id > current_setting('ensaio.c0')::bigint),
  'n_chamadas', (select count(*) from ops.rotina_chamada ch where ch.request_id > current_setting('ensaio.c0')::bigint),
  'header_ok', (select bool_and(length(q.headers ->> 'x-crm-chave') = 64 and q.body is not null and q.method = 'POST' and q.timeout_milliseconds = 60000)
                  from net.http_request_queue q where q.id > current_setting('ensaio.c0')::bigint));
-- kill-switch: envio_imediato=false → envia sem disparar
update crm.config set envio_imediato = false;
select set_config('ensaio.q1', (select count(*)::text from net.http_request_queue), true);
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('4.kill_texto', public.crm_enviar_mensagem(current_setting('ensaio.pessoa')::uuid, 'sem disparo'));
reset role;
insert into _r select '4.kill_fila_net', to_jsonb((select count(*) from net.http_request_queue) - current_setting('ensaio.q1')::bigint);
update crm.config set envio_imediato = true;
-- chamada direta por authenticated recusada
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
set local role authenticated;
do $t4$
begin
  perform crm.whatsapp_disparar_envio();
  insert into _r values ('4.direto_auth', '"ERRADO: executou"');
exception when insufficient_privilege then insert into _r values ('4.direto_auth', '"recusado 42501"');
end
$t4$;
reset role;

-- 5. Fila de saída: áudio sai com caminho/mime e sem legenda; áudio sumido do Storage → falhou
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects o where o.name = 'envio/3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975/a0000000-0000-4000-8000-000000000002.m4a';
create temp table _f on commit drop as select * from crm.whatsapp_fila_pegar(60);
insert into _r select '5.fila', jsonb_agg(jsonb_build_object('tipo', f.tipo, 'cam', f.midia_caminho is not null, 'mime', f.midia_mime, 'leg', f.legenda, 'texto', f.texto) order by f.tipo, f.midia_mime)
  from _f f where f.mensagem_id in (select m.id from crm.mensagem m where m.pessoa_id = current_setting('ensaio.pessoa')::uuid);
insert into _r select '5.m4a_sumido', jsonb_build_object('st', m.status, 'erro', m.erro) from crm.mensagem m
 where m.pessoa_id = current_setting('ensaio.pessoa')::uuid and m.direcao = 'saida' and m.midia_mime = 'audio/mp4';

-- 6. Permissões
insert into _r select '6.acl', jsonb_object_agg(p.oid::regprocedure::text, jsonb_build_object(
    'anon', has_function_privilege('anon', p.oid, 'execute'), 'auth', has_function_privilege('authenticated', p.oid, 'execute'),
    'srv', has_function_privilege('service_role', p.oid, 'execute')))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname = 'crm' and p.proname in ('whatsapp_disparar_envio', 'midia_pode_subir', 'whatsapp_fila_pegar'))
    or (n.nspname = 'public' and p.proname = 'crm_enviar_mensagem');
insert into _r select '6.config', jsonb_build_object('envio_imediato', c.envio_imediato) from crm.config c;

-- ══ RESULTADO (aborta: nada persiste) ══
do $fim$ begin raise exception 'ENSAIO %', (select jsonb_object_agg(k, v) from _r); end $fim$;
rollback;
