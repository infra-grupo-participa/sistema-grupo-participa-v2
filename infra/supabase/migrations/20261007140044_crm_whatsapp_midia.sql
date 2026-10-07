-- STATUS: APLICADA em produção em 07/10/2026 — versão 20261007140044, nome crm_whatsapp_midia (era 20261007m). md5 gravado em
-- schema_migrations = 1c8e9a07506e723ef652ab5ef88053f0 = este arquivo SEM estas 2 linhas de STATUS.
-- 20261007m_crm_whatsapp_midia — arquivos no WhatsApp do CRM (número 5521987545211, Infobip). Pedido do Arthur, 07/10/2026.
--
-- RECEBIDO (imagem, áudio/voz, documento, vídeo):
--   crm.whatsapp_entrada passa a marcar a mensagem de mídia como midia_status='pendente' (nome e mime do documento quando a
--   Infobip informa). O download NÃO acontece no banco: a Edge crm-whatsapp-enviar (acao "midia") pega a fila
--   (crm.whatsapp_midia_pegar, SKIP LOCKED + arrendamento de 10 min), baixa da Infobip com a chave do Vault, sobe para o
--   bucket PRIVADO crm-midia em <conversa>/<mensagem>.<ext> e grava caminho/mime/tamanho/nome (crm.whatsapp_midia_resultado).
--   Limite: crm.config.midia_limite_bytes (25 MB) → acima disso 'grande_demais' com o motivo, sem baixar.
--   Falha: volta para 'pendente' com espera (5 min × tentativa), até 6 tentativas; a Infobip guarda 7 dias, depois 'falhou'.
--   Gatilhos: a Edge do webhook chama a de envio logo depois de gravar (em segundo plano); o cron que já existe
--   (crm-whatsapp-reprocessar, */10) passa a chamar a Edge quando crm.whatsapp_midia_tem() — é o reprocessamento.
-- LEITURA SEGURA:
--   storage.objects: SELECT no bucket crm-midia só para authenticated com crm.midia_pode_ver(name) — mesma regra das
--   policies conversa_ler/mensagem_ler (gestor; vendedor só das pessoas dele). O front pede a URL assinada de 10 min pela
--   API do Storage (createSignedUrl), que aplica essa policy. Nada público, nenhuma policy para anon.
-- ENVIADO PELO VENDEDOR (imagem jpg/png/webp até 5 MB, PDF até 16 MB):
--   INSERT no bucket só em envio/<auth.uid()>/<uuid>.<jpg|jpeg|png|webp|pdf> (crm.midia_pode_subir); nada de update/delete.
--   public.crm_enviar_mensagem ganha p_midia e p_midia_nome (DROP + CREATE: assinatura nova) e valida no banco: dono do
--   objeto = quem envia, mime × extensão, tamanho, legenda ≤ 1.024, janela de 24 h (fora dela só template), não reusar.
--   crm.whatsapp_fila_pegar devolve também caminho/nome/mime/legenda (DROP + CREATE: retorno novo) e recusa anexo sumido.
--   A Edge assina uma URL de 1 h que a Infobip baixa (/whatsapp/1/message/image|document). Status igual ao do texto.
-- crm.mensagem_json ganha "midia" {status, caminho (só quando ok), mime, tamanho, nome}. Mensagem antiga: midia = null.
--
-- Reversão: alter job do cron de volta para 'select crm.whatsapp_reprocessar()'; recriar crm_enviar_mensagem(uuid,text,uuid),
--   whatsapp_fila_pegar, whatsapp_entrada e mensagem_json pelos corpos de 20261006051434 (md5 na guarda); drop das policies
--   crm_midia_*; o bucket e as colunas podem ficar (sem leitor). Kill-switch: whatsapp_ligado=false para tudo.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- ── Guarda de premissa: corpos vivos exatamente como lidos em 07/10/2026 ──
do $guarda$
declare r record;
begin
  for r in select * from (values
      ('crm.whatsapp_entrada(jsonb)', '99022ff68eeae96244b8629e06a1224e'),
      ('crm.whatsapp_fila_pegar(integer)', '1b3414ecdd8af7352ebb5509673bd87e'),
      ('public.crm_enviar_mensagem(uuid,text,uuid)', '9a382541edd4e64fc7864a5ea5a35823'),
      ('crm.mensagem_json(crm.mensagem,uuid)', '7b1c5b48badf5a3edaaa15b29cc31c1d')) v(sig, esperado) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception 'premissa: % mudou (ou não existe)', r.sig;
    end if;
  end loop;
  if exists (select 1 from storage.buckets b where b.id = 'crm-midia') then raise exception 'premissa: bucket crm-midia já existe'; end if;
  if exists (select 1 from information_schema.columns c where c.table_schema = 'crm' and c.table_name = 'mensagem' and c.column_name like 'midia\_%' and c.column_name <> 'midia_url') then
    raise exception 'premissa: colunas midia_* já existem';
  end if;
  if (select j.command from cron.job j where j.jobname = 'crm-whatsapp-reprocessar') is distinct from 'select crm.whatsapp_reprocessar()' then
    raise exception 'premissa: cron crm-whatsapp-reprocessar mudou';
  end if;
  if to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null then raise exception 'premissa: ops.cron_post ausente'; end if;
end
$guarda$;

-- ── Colunas e config ──
alter table crm.mensagem
  add column midia_status text check (midia_status in ('pendente', 'ok', 'grande_demais', 'falhou')),
  add column midia_caminho text check (midia_caminho is null or (length(midia_caminho) <= 300 and midia_caminho ~ '^[A-Za-z0-9/_.-]+$')),
  add column midia_mime text check (midia_mime is null or length(midia_mime) <= 120),
  add column midia_tamanho bigint check (midia_tamanho is null or midia_tamanho >= 0),
  add column midia_nome text check (midia_nome is null or length(midia_nome) <= 200),
  add column midia_tentativas smallint not null default 0 check (midia_tentativas between 0 and 20),
  add column midia_proxima_em timestamptz,
  add column midia_erro text check (midia_erro is null or length(midia_erro) <= 300),
  add constraint mensagem_midia_ok_check check (midia_status is distinct from 'ok' or midia_caminho is not null);

create index mensagem_midia_fila_idx on crm.mensagem (midia_proxima_em) where midia_status = 'pendente';
create unique index mensagem_midia_caminho_idx on crm.mensagem (midia_caminho) where midia_caminho is not null;

alter table crm.config
  add column midia_limite_bytes bigint not null default 26214400 check (midia_limite_bytes between 1048576 and 104857600);

-- ── Bucket privado ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('crm-midia', 'crm-midia', false, 26214400, null);

-- ── Regras do Storage ──
create function crm.midia_pode_ver(p_nome text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_eu uuid := auth.uid();
begin
  if p_nome is null or v_eu is null then return false; end if;
  -- o próprio upload (pré-visualização antes de enviar)
  if p_nome like 'envio/' || v_eu::text || '/%' then
    return coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false);
  end if;
  -- arquivo de mensagem: a mesma regra das policies conversa_ler/mensagem_ler
  return coalesce(exists (
    select 1 from crm.mensagem m
     where m.midia_caminho = p_nome and m.midia_status = 'ok'
       and (coalesce(crm.eh_gestor(), false)
            or (coalesce(crm.eh_vendedor(), false) and m.pessoa_id in (select crm.pessoas_do_vendedor())))), false);
end
$$;
revoke all on function crm.midia_pode_ver(text) from public, anon;
grant execute on function crm.midia_pode_ver(text) to authenticated;

create function crm.midia_pode_subir(p_nome text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_eu uuid := auth.uid();
begin
  if p_nome is null or v_eu is null then return false; end if;
  return p_nome ~ ('^envio/' || v_eu::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf)$')
     and coalesce((select c.whatsapp_ligado and c.escrita_ligada from crm.config c), false)
     and (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false));
end
$$;
revoke all on function crm.midia_pode_subir(text) from public, anon;
grant execute on function crm.midia_pode_subir(text) to authenticated;

create policy crm_midia_ler on storage.objects for select to authenticated
  using (bucket_id = 'crm-midia' and crm.midia_pode_ver(name));
create policy crm_midia_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'crm-midia' and crm.midia_pode_subir(name));

-- ── JSON da mensagem (+ midia) ──
create or replace function crm.mensagem_json(m crm.mensagem, p_contato uuid)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'midia', case when m.midia_status is not null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;

-- ── Entrada: mídia vira pendente de download ──
create or replace function crm.whatsapp_entrada(e jsonb)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_para text := pessoas.so_digitos(e ->> 'to');
  v_de   text := pessoas.so_digitos(e ->> 'from');
  v_mid  text := e ->> 'messageId';
  v_m    jsonb := coalesce(e -> 'message', '{}'::jsonb);
  v_tp   text := upper(coalesce(v_m ->> 'type', 'TEXT'));
  v_num  crm.numero_whatsapp%rowtype; v_conv crm.conversa%rowtype; c crm.config%rowtype;
  v_reg jsonb; v_pessoa uuid; v_tipo text; v_texto text; v_url text; v_em timestamptz; v_id uuid; v_nome text;
  v_palavra text; v_nao int; v_dono uuid; v_pc uuid;
  v_midia text; v_mnome text; v_mmime text;
begin
  if coalesce(v_mid, '') = '' or length(v_mid) > 200 then return 'sem_message_id'; end if;
  select * into v_num from crm.numero_whatsapp n where n.numero = v_para and n.ativo;
  if not found then return 'numero_desconhecido'; end if;
  if v_de !~ '^[0-9]{10,15}$' then return 'remetente_invalido'; end if;
  select * into c from crm.config;

  v_tipo := case v_tp when 'TEXT' then 'texto' when 'IMAGE' then 'imagem' when 'DOCUMENT' then 'documento' when 'AUDIO' then 'audio'
                      when 'VOICE' then 'audio' when 'VIDEO' then 'video' when 'LOCATION' then 'localizacao' when 'CONTACT' then 'contato'
                      when 'BUTTON' then 'botao' when 'INTERACTIVE_BUTTON_REPLY' then 'botao' when 'INTERACTIVE_LIST_REPLY' then 'botao'
                      when 'STICKER' then 'figurinha' else 'outro' end;
  v_texto := nullif(btrim(coalesce(v_m ->> 'text', v_m ->> 'title', '')), '');
  v_texto := case v_tipo
               when 'imagem' then '[imagem]' || coalesce(' ' || nullif(btrim(v_m ->> 'caption'), ''), '')
               when 'documento' then '[documento]' || coalesce(' ' || nullif(btrim(v_m ->> 'caption'), ''), '')
               when 'video' then '[vídeo]' || coalesce(' ' || nullif(btrim(v_m ->> 'caption'), ''), '')
               when 'audio' then '[áudio]' when 'localizacao' then '[localização]' when 'contato' then '[contato]'
               when 'figurinha' then '[figurinha]'
               else coalesce(v_texto, '[mensagem não suportada]') end;
  v_texto := left(v_texto, 4096);
  v_url := case when v_m ->> 'url' ~ '^https://' and length(v_m ->> 'url') <= 2000 then v_m ->> 'url' end;
  v_em := crm.ts_ou_agora(e ->> 'receivedAt');
  v_nome := nullif(left(btrim(coalesce(e -> 'contact' ->> 'name', '')), 160), '');
  -- arquivo: baixado depois pela Edge (crm.whatsapp_midia_pegar); sem URL não há o que baixar
  if v_tipo in ('imagem', 'documento', 'audio', 'video') then
    v_midia := case when v_url is null then 'falhou' else 'pendente' end;
    v_mnome := nullif(left(btrim(regexp_replace(coalesce(v_m ->> 'filename', v_m ->> 'fileName', ''), '[\\/[:cntrl:]]', '_', 'g')), 200), '');
    v_mmime := nullif(left(lower(btrim(coalesce(v_m ->> 'mimeType', v_m ->> 'mimetype', ''))), 120), '');
  end if;

  select * into v_conv from crm.conversa x where x.numero_id = v_num.id and x.telefone = v_de for update;
  if not found then
    -- pessoa só por telefone (sem nome: o nome do perfil do WhatsApp não decide casamento); dúvida vira revisão na F0
    v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
    if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
    v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
    perform crm.garantir_pc(v_pessoa);
    insert into crm.conversa (numero_id, telefone, pessoa_id, nome_perfil) values (v_num.id, v_de, v_pessoa, v_nome)
    on conflict (numero_id, telefone) do nothing;
    select * into v_conv from crm.conversa x where x.numero_id = v_num.id and x.telefone = v_de for update;
  end if;

  insert into crm.mensagem (conversa_id, pessoa_id, direcao, tipo, texto, midia_url, em, provedor, provedor_msg_id,
                            midia_status, midia_nome, midia_mime, midia_proxima_em, midia_erro)
  values (v_conv.id, v_conv.pessoa_id, 'entrada', v_tipo, v_texto, v_url, v_em, 'infobip', v_mid,
          v_midia, v_mnome, v_mmime, case when v_midia = 'pendente' then now() end,
          case when v_midia = 'falhou' then 'Provedor não informou o endereço do arquivo.' end)
  on conflict (provedor, provedor_msg_id) do nothing
  returning id into v_id;
  if v_id is null then return 'duplicada'; end if;

  update crm.conversa x
     set ultima_mensagem_id = case when x.ultima_em is null or v_em >= x.ultima_em then v_id else x.ultima_mensagem_id end,
         ultima_em = greatest(x.ultima_em, v_em),
         ultima_entrada_em = greatest(x.ultima_entrada_em, v_em),
         nao_lidas = x.nao_lidas + 1,
         nome_perfil = coalesce(v_nome, x.nome_perfil)
   where x.id = v_conv.id
  returning x.nao_lidas into v_nao;

  -- opt-out por palavra (lista em crm.config.optout_palavras; comparação sem acento e sem pontuação)
  v_palavra := btrim(regexp_replace(mkt.sem_acento(v_texto), '[^A-Z ]', '', 'g'));
  if v_tipo in ('texto', 'botao') and v_palavra = any(c.optout_palavras) then
    insert into crm.supressao (tipo, valor, canal, motivo, origem)
    select 'f', pessoas.chave_telefone(v_de), 'whatsapp', 'Pediu para sair pelo WhatsApp', 'whatsapp_stop'
     where pessoas.chave_telefone(v_de) is not null
    on conflict do nothing;
    v_pc := crm.garantir_pc(v_conv.pessoa_id);
    perform set_config('crm.resumo', 'Opt-out pelo WhatsApp: ' || crm.nome_pessoa(v_conv.pessoa_id), true);
    update crm.pessoa_comercial pc set opt_out = true, opt_out_em = now(), opt_out_motivo = 'Pediu para sair pelo WhatsApp', atualizado_em = now()
     where pc.pessoa_id = v_pc and not pc.opt_out;
    perform set_config('crm.resumo', '', true);
    update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Contato pediu para não receber mensagens.'
     where x.conversa_id = v_conv.id and x.status = 'na_fila';
    return 'opt_out';
  end if;

  -- aviso ao dono quando a conversa passa de 0 para 1 não lida (não a cada mensagem)
  if v_nao = 1 then
    begin
      select pc.dono_id into v_dono from crm.pessoa_comercial pc
       where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(v_conv.pessoa_id))) and pc.dono_id is not null
       order by pc.pessoa_id = pessoas.atual(v_conv.pessoa_id) desc limit 1;
      if v_dono is not null and not exists (select 1 from crm.preferencias_notificacao p
                                             where p.perfil_id = v_dono and (p.gatilhos ->> 'lead_respondeu') = 'false') then
        insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
        values (v_dono, 'lead_respondeu', v_id::text, left('Respondeu no WhatsApp: ' || crm.nome_pessoa(v_conv.pessoa_id), 200),
                left(v_texto, 140), '/comercial/conversas?contato=' || pessoas.atual(v_conv.pessoa_id))
        on conflict (perfil_id, gatilho, ref_id) do nothing;
      end if;
    exception when others then
      raise warning 'crm.whatsapp_entrada (aviso): %', sqlstate;   -- aviso nunca derruba a mensagem
    end;
  end if;
  return 'ok';
end
$function$;

-- ── Fila de download (interna: só o dono; a Edge conecta como postgres) ──
create function crm.whatsapp_midia_tem()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select c.whatsapp_ligado from crm.config c), false)
     and exists (select 1 from crm.mensagem m where m.midia_status = 'pendente' and m.midia_proxima_em <= now());
$$;

create function crm.whatsapp_midia_pegar(p_lote integer default 5)
returns table (mensagem_id uuid, conversa_id uuid, url text, tipo text, mime text, nome text, limite_bytes bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare c crm.config%rowtype; m record;
begin
  select * into c from crm.config;
  if not coalesce(c.whatsapp_ligado, false) then return; end if;
  -- a Infobip guarda o arquivo por 7 dias; 6 tentativas (inclui arrendamentos vencidos) = desiste
  update crm.mensagem x
     set midia_status = 'falhou', midia_proxima_em = null,
         midia_erro = case when x.em < now() - interval '7 days' then 'Arquivo expirou no provedor (7 dias).'
                           else coalesce(x.midia_erro, 'Download falhou várias vezes.') end
   where x.midia_status = 'pendente' and (x.em < now() - interval '7 days' or x.midia_tentativas >= 6)
     and x.midia_proxima_em <= now();
  for m in select x.id, x.conversa_id, x.midia_url, x.tipo, x.midia_mime, x.midia_nome
             from crm.mensagem x
            where x.midia_status = 'pendente' and x.midia_proxima_em <= now()
            order by x.midia_proxima_em, x.id
            limit least(greatest(coalesce(p_lote, 5), 1), 20)
              for update of x skip locked loop
    if m.midia_url is null then
      update crm.mensagem x set midia_status = 'falhou', midia_proxima_em = null,
             midia_erro = 'Provedor não informou o endereço do arquivo.' where x.id = m.id;
      continue;
    end if;
    -- arrendamento: se a Edge morrer no meio, a mensagem volta a ser pega em 10 min
    update crm.mensagem x set midia_tentativas = x.midia_tentativas + 1, midia_proxima_em = now() + interval '10 minutes'
     where x.id = m.id;
    mensagem_id := m.id; conversa_id := m.conversa_id; url := m.midia_url; tipo := m.tipo; mime := m.midia_mime;
    nome := m.midia_nome; limite_bytes := c.midia_limite_bytes;
    return next;
  end loop;
end
$$;

create function crm.whatsapp_midia_resultado(p_mensagem uuid, p_resultado text, p_caminho text, p_mime text,
                                             p_tamanho bigint, p_nome text, p_erro text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare m crm.mensagem%rowtype; v_mime text := nullif(left(lower(btrim(coalesce(p_mime, ''))), 120), '');
        v_nome text := nullif(left(btrim(regexp_replace(coalesce(p_nome, ''), '[\\/[:cntrl:]]', '_', 'g')), 200), '');
begin
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or m.midia_status is distinct from 'pendente' then return 'ignorado'; end if;
  if p_resultado = 'ok' then
    if p_caminho is null or p_caminho !~ ('^' || m.conversa_id::text || '/' || m.id::text || '\.[a-z0-9]{1,8}$') then
      raise exception 'caminho fora do padrão' using errcode = '22023';
    end if;
    update crm.mensagem x set midia_status = 'ok', midia_caminho = p_caminho, midia_mime = coalesce(v_mime, x.midia_mime),
           midia_tamanho = p_tamanho, midia_nome = coalesce(x.midia_nome, v_nome), midia_erro = null, midia_proxima_em = null
     where x.id = m.id;
    return 'ok';
  elsif p_resultado = 'grande_demais' then
    update crm.mensagem x set midia_status = 'grande_demais', midia_mime = coalesce(v_mime, x.midia_mime),
           midia_tamanho = p_tamanho, midia_nome = coalesce(x.midia_nome, v_nome), midia_proxima_em = null,
           midia_erro = left(coalesce(p_erro, 'Arquivo acima do limite.'), 300)
     where x.id = m.id;
    return 'grande_demais';
  elsif p_resultado = 'falhou' or m.midia_tentativas >= 6 then
    update crm.mensagem x set midia_status = 'falhou', midia_proxima_em = null,
           midia_erro = left(coalesce(p_erro, 'Download falhou.'), 300)
     where x.id = m.id;
    return 'falhou';
  else
    update crm.mensagem x set midia_proxima_em = now() + make_interval(mins => 5 * greatest(m.midia_tentativas, 1)),
           midia_erro = left(coalesce(p_erro, 'Download falhou.'), 300)
     where x.id = m.id;
    return 'tentar';
  end if;
end
$$;

revoke all on function crm.whatsapp_midia_tem() from public, anon, authenticated, service_role;
revoke all on function crm.whatsapp_midia_pegar(integer) from public, anon, authenticated, service_role;
revoke all on function crm.whatsapp_midia_resultado(uuid, text, text, text, bigint, text, text) from public, anon, authenticated, service_role;

-- ── Fila de saída: devolve o anexo (retorno novo → drop + create) ──
drop function crm.whatsapp_fila_pegar(integer);
create function crm.whatsapp_fila_pegar(p_lote integer default null::integer)
 returns table(mensagem_id uuid, de text, para text, tipo text, texto text, template_nome text, template_idioma text, variaveis jsonb,
               midia_caminho text, midia_nome text, midia_mime text, legenda text)
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
                   when m.tipo in ('imagem', 'documento') and (m.midia_status is distinct from 'ok' or not m.arq_ok)
                     then 'Arquivo do anexo indisponível.' end;
    if v_erro is not null then
      update crm.mensagem x set status = 'falhou', status_em = now(), erro = v_erro where x.id = m.id;
      continue;
    end if;
    update crm.mensagem x set status = 'enviando', status_em = now(), tentativas = x.tentativas + 1 where x.id = m.id;
    mensagem_id := m.id; de := m.numero; para := m.telefone; tipo := m.tipo; texto := m.texto;
    template_nome := m.nome_provedor; template_idioma := m.idioma; variaveis := coalesce(m.template_vars, '[]'::jsonb);
    midia_caminho := case when m.tipo in ('imagem', 'documento') then m.midia_caminho end;
    midia_nome := case when m.tipo = 'documento' then m.midia_nome end;
    midia_mime := case when m.tipo in ('imagem', 'documento') then m.midia_mime end;
    -- texto "[imagem]"/"[documento] nome" é rótulo do CRM, não legenda
    legenda := case when m.tipo in ('imagem', 'documento') and m.texto !~ '^\[(imagem|documento)\]' then m.texto end;
    return next;
  end loop;
end
$function$;
revoke all on function crm.whatsapp_fila_pegar(integer) from public, anon, authenticated, service_role;

-- ── Envio pela tela: texto, template ou anexo (assinatura nova → drop + create) ──
drop function public.crm_enviar_mensagem(uuid, text, uuid);
create function public.crm_enviar_mensagem(p_pessoa uuid, p_texto text, p_template uuid default null::uuid,
                                           p_midia text default null, p_midia_nome text default null)
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
    -- anexo: imagem (jpg/png/webp ≤ 5 MB) ou PDF (≤ 16 MB) que a própria pessoa subiu em envio/<uid>/<uuid>.<ext>
    if p_template is not null then return crm.res(false, 'Anexo não vai junto com template.'); end if;
    v_leg := nullif(btrim(coalesce(p_texto, '')), '');
    if length(v_leg) > 1024 then return crm.res(false, 'Legenda longa demais (máximo 1.024 caracteres).'); end if;
    if v_eu is null or p_midia !~ ('^envio/' || v_eu::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf)$') then
      return crm.res(false, 'Anexo inválido.');
    end if;
    select o.metadata into v_meta from storage.objects o
     where o.bucket_id = 'crm-midia' and o.name = p_midia and o.owner_id = v_eu::text;
    if not found then return crm.res(false, 'Anexo não encontrado. Anexe o arquivo de novo.'); end if;
    if exists (select 1 from crm.mensagem x where x.midia_caminho = p_midia) then return crm.res(false, 'Este anexo já foi enviado.'); end if;
    v_mime := lower(btrim(split_part(coalesce(v_meta ->> 'mimetype', ''), ';', 1)));
    v_tam := case when coalesce(v_meta ->> 'size', '') ~ '^[0-9]{1,12}$' then (v_meta ->> 'size')::bigint end;
    v_ext := substring(p_midia from '\.([a-z]+)$');
    if v_mime is distinct from (case v_ext when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg' when 'png' then 'image/png'
                                            when 'webp' then 'image/webp' when 'pdf' then 'application/pdf' end) then
      return crm.res(false, 'Só imagem (JPG, PNG, WebP) ou PDF.');
    end if;
    v_tipo := case when v_ext = 'pdf' then 'documento' else 'imagem' end;
    v_lim := case when v_tipo = 'documento' then 16777216 else 5242880 end;
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
                                                             when v_tipo = 'documento' then 'PDF' else 'mensagem' end,
                                   crm.nome_pessoa(v_atual)),
                            jsonb_build_object('conversa_id', cv.id, 'template_id', t.id));
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

-- ── Cron de reprocessamento (já existe, */10): também tenta de novo o download pendente ──
select cron.alter_job(
  job_id := (select j.jobid from cron.job j where j.jobname = 'crm-whatsapp-reprocessar'),
  command := $c$select crm.whatsapp_reprocessar(), (select ops.cron_post('crm-whatsapp-midia',
  url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
  headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
             (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
  body := '{"acao":"midia"}'::jsonb, timeout_milliseconds := 60000) where crm.whatsapp_midia_tem())$c$);

-- ── Conferência ──
do $conf$
declare v text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('crm', 'public') and (p.proname like 'whatsapp_midia%' or p.proname in ('midia_pode_ver', 'midia_pode_subir', 'crm_enviar_mensagem', 'whatsapp_fila_pegar'))
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  if v is not null then raise exception 'executável por anon/public: %', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and (p.proname like 'whatsapp_midia%' or p.proname = 'whatsapp_fila_pegar')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'));
  if v is not null then raise exception 'interna executável por authenticated/service_role: %', v; end if;
  if to_regprocedure('public.crm_enviar_mensagem(uuid,text,uuid)') is not null then raise exception 'sobrecarga antiga de crm_enviar_mensagem viva'; end if;
  if (select b.public from storage.buckets b where b.id = 'crm-midia') is distinct from false then raise exception 'bucket crm-midia não é privado'; end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
              and (p.qual like '%crm-midia%' or p.with_check like '%crm-midia%') and p.roles::text <> '{authenticated}') then
    raise exception 'policy do crm-midia fora de authenticated';
  end if;
end
$conf$;
