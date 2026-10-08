-- 20261008152212 — WhatsApp por QR Code (Evolution API v2) no CRM Comercial, ao lado do número oficial (Infobip).
-- Explicação, ensaio e status: 20261008152212.explain.md / 20261008152212_ensaio.sql. Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
--
-- Modelo: crm.numero_whatsapp JÁ é o canal (crm.conversa.numero_id é NOT NULL desde a F4). Esta migration o estende para
-- provedor 'evolution' (instância, status, dono/equipe, recebe/envia) em vez de criar uma tabela paralela; a mensagem
-- ganha numero_id (canal) e externa (enviada pelo celular/Clint, fora do CRM).
-- Regras no banco (valem para tela, MCP e qualquer escritor):
--   * canal Evolution não recebe disparo em massa (ficha_id) nem template — trigger crm.tg_mensagem_canal;
--   * anti-ban por canal: limite por minuto, por hora e de primeiros contatos por hora (crm.config.evolution_*);
--   * kill-switch novo crm.config.evolution_ligado (default false) — envio Evolution exige ele E envio_ligado;
--   * o envio Infobip (fila, mídia) passa a olhar só provedor='infobip' (as funções vivas são guardadas por md5).
-- Segredos: Vault evolution_api_url / evolution_api_key (Edge) e crm_whatsapp_envio_chave (já existe, Edge→Edge).
-- Chave de webhook por instância: crm.numero_whatsapp_segredo (sem grant; só funções do dono leem).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ── 0. Guarda de premissa: corpo vivo das funções/constraints que esta migration reescreve ──
do $g$
declare v text;
begin
  for v in
    select x.k from (values
      ('crm.whatsapp_fila_pegar(integer)', '0915cf92498a967957419f1df741ce5e'),
      ('crm.whatsapp_fila_tem()', '613f830ace01ce620f847d235412b89e'),
      ('crm.whatsapp_midia_pegar(integer)', '8a69558e3e32a84c00d2a9874496fd15'),
      ('crm.whatsapp_midia_tem()', 'acf4d32177ab66823ca1e330c9393cac'),
      ('crm.mensagem_json(crm.mensagem,uuid)', '180389cef07a9ff8972947be39015210'),
      ('public.crm_conversas(integer)', 'a6fab7e8689e9c6aba6564b8e262e786'),
      ('public.crm_enviar_mensagem(uuid,text,uuid,text,text,uuid)', 'a6fe93d8008ac62f42b9131f7029de89')
    ) x(k, h)
    where to_regprocedure(x.k) is null or md5(pg_get_functiondef(to_regprocedure(x.k))) <> x.h
  loop
    raise exception 'premissa: % mudou desde a leitura (reler o corpo vivo antes de aplicar)', v;
  end loop;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'crm.mensagem'::regclass and conname = 'mensagem_check1')
     is distinct from 'CHECK (((direcao = ''entrada''::text) OR (autor_id IS NOT NULL) OR (ficha_id IS NOT NULL)))' then
    raise exception 'premissa: mensagem_check1 mudou';
  end if;
  if (select count(*) from crm.numero_whatsapp) <> 1 or exists (select 1 from crm.numero_whatsapp where provedor <> 'infobip') then
    raise exception 'premissa: esperava 1 canal (Infobip)';
  end if;
  if exists (select 1 from crm.mensagem m where m.provedor <> 'infobip') then raise exception 'premissa: mensagem de outro provedor'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'crm_enviar_mensagem') <> 1 then
    raise exception 'premissa: esperava 1 assinatura de crm_enviar_mensagem';
  end if;
end $g$;

-- ── 1. Config: kill-switch e limites anti-ban ──
alter table crm.config
  add column evolution_ligado boolean not null default false,
  add column evolution_limite_minuto smallint not null default 15 check (evolution_limite_minuto between 1 and 60),
  add column evolution_limite_hora smallint not null default 200 check (evolution_limite_hora between 1 and 2000),
  add column evolution_novos_hora smallint not null default 20 check (evolution_novos_hora between 0 and 500);
comment on column crm.config.evolution_ligado is 'Kill-switch do WhatsApp por QR (Evolution): entrada processada e envio. Default false.';
comment on column crm.config.evolution_novos_hora is 'Anti-ban: conversas por hora em que o CRM escreve primeiro (contato nunca escreveu neste número).';

-- ── 2. Canal = crm.numero_whatsapp ──
alter table crm.numero_whatsapp drop constraint numero_whatsapp_provedor_check;
alter table crm.numero_whatsapp
  add constraint numero_whatsapp_provedor_check check (provedor in ('infobip', 'evolution')),
  alter column numero drop not null,
  add column instancia text unique check (instancia ~ '^crm-[a-z0-9-]{3,40}$'),
  add column status text not null default 'conectado'
    check (status in ('desconectado', 'aguardando_qr', 'conectado', 'banido')),
  add column status_em timestamptz not null default now(),
  add column status_motivo text check (status_motivo is null or length(status_motivo) <= 200),
  add column conectado_em timestamptz,
  add column dono_id uuid references public.perfis(id) on delete set null,
  add column equipe text check (equipe is null or length(btrim(equipe)) between 1 and 60),
  add column recebe boolean not null default true,
  add column envia boolean not null default true,
  add column criado_por uuid references public.perfis(id) on delete set null;
alter table crm.numero_whatsapp add constraint numero_whatsapp_provedor_campos check (
  (provedor = 'infobip' and numero is not null and instancia is null)
  or (provedor = 'evolution' and instancia is not null));
comment on table crm.numero_whatsapp is 'Canal de WhatsApp do CRM: número oficial (Infobip) ou número conectado por QR (Evolution). crm.conversa.numero_id = canal.';

create table crm.numero_whatsapp_segredo (
  numero_id uuid primary key references crm.numero_whatsapp(id) on delete restrict,
  webhook_chave text not null check (length(webhook_chave) between 32 and 128),
  qr_base64 text check (qr_base64 is null or length(qr_base64) <= 60000),
  qr_em timestamptz,
  atualizado_em timestamptz not null default now()
);
alter table crm.numero_whatsapp_segredo enable row level security;
revoke all on crm.numero_whatsapp_segredo from public, anon, authenticated, service_role;
comment on table crm.numero_whatsapp_segredo is 'Chave do webhook por instância Evolution e último QR. Sem grant e sem policy: só funções do dono.';

-- O número padrão do CRM (disparos/templates) é sempre o oficial
create or replace function crm.tg_config_numero_oficial() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.whatsapp_numero_id is not null
     and not exists (select 1 from crm.numero_whatsapp n where n.id = new.whatsapp_numero_id and n.provedor = 'infobip') then
    raise exception 'O número padrão (disparos e templates) precisa ser o oficial (Infobip).' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function crm.tg_config_numero_oficial() from public, anon, authenticated;
create trigger config_numero_oficial before insert or update of whatsapp_numero_id on crm.config
  for each row execute function crm.tg_config_numero_oficial();

-- Disparo em massa (ficha) só pelo número oficial: bloqueio na ficha, antes de virar mensagem
create or replace function crm.tg_ficha_numero_oficial() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.numero_id is not null
     and not exists (select 1 from crm.numero_whatsapp n where n.id = new.numero_id and n.provedor = 'infobip') then
    raise exception 'Disparo em massa só sai pelo número oficial. Número conectado por QR não faz disparo (risco de banimento).' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function crm.tg_ficha_numero_oficial() from public, anon, authenticated;
create trigger ficha_numero_oficial before insert or update of numero_id on crm.ficha_disparo
  for each row execute function crm.tg_ficha_numero_oficial();

-- ── 3. Mensagem: canal e "externa" ──
alter table crm.mensagem
  add column numero_id uuid references crm.numero_whatsapp(id) on delete restrict,
  add column externa boolean not null default false;
comment on column crm.mensagem.numero_id is 'Canal (número) da mensagem; preenchido pelo trigger a partir da conversa.';
comment on column crm.mensagem.externa is 'Saída que não nasceu no CRM (celular ou Clint no mesmo número conectado por QR).';
alter table crm.mensagem drop constraint mensagem_provedor_check;
alter table crm.mensagem add constraint mensagem_provedor_check check (provedor in ('infobip', 'evolution'));
alter table crm.mensagem drop constraint mensagem_check1;
alter table crm.mensagem add constraint mensagem_check1
  check (direcao = 'entrada' or autor_id is not null or ficha_id is not null or externa);
alter table crm.mensagem add constraint mensagem_externa_check
  check (not externa or (direcao = 'saida' and provedor = 'evolution'));

update crm.mensagem m set numero_id = c.numero_id from crm.conversa c where c.id = m.conversa_id and m.numero_id is null;

create or replace function crm.tg_mensagem_canal() returns trigger
language plpgsql set search_path = '' as $$
declare n crm.numero_whatsapp%rowtype; c crm.config%rowtype; v_min int; v_hora int; v_novos int; v_fria boolean;
begin
  if new.numero_id is null then
    select cv.numero_id into new.numero_id from crm.conversa cv where cv.id = new.conversa_id;
  end if;
  select * into n from crm.numero_whatsapp x where x.id = new.numero_id;
  if not found then raise exception 'Mensagem sem canal.' using errcode = 'P0001'; end if;
  if new.provedor is distinct from n.provedor then
    raise exception 'Mensagem de % em canal %.', new.provedor, n.provedor using errcode = 'P0001';
  end if;
  if n.provedor = 'evolution' and new.direcao = 'saida' and not new.externa then
    if new.ficha_id is not null then
      raise exception 'Disparo em massa não sai por número conectado por QR (risco de banimento). Use o número oficial.' using errcode = 'P0001';
    end if;
    if new.tipo = 'template' then
      raise exception 'Template é só do número oficial. Neste número, escreva a mensagem.' using errcode = 'P0001';
    end if;
    select * into c from crm.config;
    -- serializa conta + insert por canal (duas vendedoras ao mesmo tempo não furam o limite)
    perform pg_advisory_xact_lock(hashtext('crm.evolution.envio'), hashtext(new.numero_id::text));
    select count(*) filter (where m.em > now() - interval '1 minute'), count(*)
      into v_min, v_hora
      from crm.mensagem m
     where m.numero_id = new.numero_id and m.direcao = 'saida' and not m.externa and m.em > now() - interval '1 hour';
    if v_min >= c.evolution_limite_minuto then
      raise exception 'Limite deste número: % mensagens por minuto. Espere um pouco (proteção contra banimento).', c.evolution_limite_minuto using errcode = 'P0001';
    end if;
    if v_hora >= c.evolution_limite_hora then
      raise exception 'Limite deste número: % mensagens por hora (proteção contra banimento).', c.evolution_limite_hora using errcode = 'P0001';
    end if;
    select cv.ultima_entrada_em is null into v_fria from crm.conversa cv where cv.id = new.conversa_id;
    if coalesce(v_fria, true) and not exists (
         select 1 from crm.mensagem m where m.conversa_id = new.conversa_id and m.direcao = 'saida' and not m.externa
            and m.em > now() - interval '1 hour') then
      select count(distinct m.conversa_id) into v_novos
        from crm.mensagem m join crm.conversa cv on cv.id = m.conversa_id
       where m.numero_id = new.numero_id and m.direcao = 'saida' and not m.externa and m.em > now() - interval '1 hour'
         and cv.ultima_entrada_em is null;
      if v_novos >= c.evolution_novos_hora then
        raise exception 'Limite deste número: % primeiros contatos por hora (quem nunca escreveu). Proteção contra banimento.', c.evolution_novos_hora using errcode = 'P0001';
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function crm.tg_mensagem_canal() from public, anon, authenticated;
create trigger mensagem_canal before insert on crm.mensagem for each row execute function crm.tg_mensagem_canal();

alter table crm.mensagem alter column numero_id set not null;
create index mensagem_canal_saida_idx on crm.mensagem (numero_id, em desc) where direcao = 'saida' and not externa;
create index mensagem_evolution_fila_idx on crm.mensagem (fila_em) where status = 'na_fila' and provedor = 'evolution';

alter table crm.integracao_evento drop constraint integracao_evento_fonte_check;
alter table crm.integracao_evento add constraint integracao_evento_fonte_check check (fonte = any (array[
  'infobip', 'unnichat', 'manychat', 'activecampaign', 'respondi', 'sendflow', 'clint', 'slack', 'evolution']));

-- ── 4. Infobip olha só o que é dele (corpo vivo + filtro de provedor) ──
CREATE OR REPLACE FUNCTION crm.whatsapp_fila_pegar(p_lote integer DEFAULT NULL::integer)
 RETURNS TABLE(mensagem_id uuid, de text, para text, tipo text, texto text, template_nome text, template_idioma text, variaveis jsonb, midia_caminho text, midia_nome text, midia_mime text, legenda text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c crm.config%rowtype; m record; v_lote int; v_erro text;
begin
  select * into c from crm.config;
  if not (coalesce(c.whatsapp_ligado, false) and coalesce(c.envio_ligado, false)) then return; end if;
  -- enviando há mais de 5 min: a Edge morreu no meio. NÃO reenvia (pode ter saído): falha incerta, o relatório corrige.
  update crm.mensagem x set status = 'falhou', falha_incerta = true, status_em = now(),
         erro = 'Sem confirmação do provedor: conferir relatório de entrega.'
   where x.status = 'enviando' and x.status_em < now() - interval '5 minutes' and x.provedor = 'infobip';
  -- validade na fila (envio desligado por muito tempo não dispara coisa velha depois)
  update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Expirou na fila sem envio.'
   where x.status = 'na_fila' and x.provedor = 'infobip'
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
            where x.status = 'na_fila' and x.provedor = 'infobip' and x.fila_em <= now() and coalesce(x.proxima_tentativa_em, x.fila_em) <= now()
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

CREATE OR REPLACE FUNCTION crm.whatsapp_fila_tem()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select c.whatsapp_ligado and c.envio_ligado from crm.config c), false)
     and (exists (select 1 from crm.mensagem m where m.status = 'na_fila' and m.provedor = 'infobip' and m.fila_em <= now()
                     and coalesce(m.proxima_tentativa_em, m.fila_em) <= now())
          or exists (select 1 from crm.ficha_disparo f where f.status = 'aprovada' and f.agendado_para <= now())
          or exists (select 1 from crm.mensagem m where m.status = 'enviando' and m.provedor = 'infobip' and m.status_em < now() - interval '5 minutes'));
$function$;

CREATE OR REPLACE FUNCTION crm.whatsapp_midia_pegar(p_lote integer DEFAULT 5)
 RETURNS TABLE(mensagem_id uuid, conversa_id uuid, url text, tipo text, mime text, nome text, limite_bytes bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c crm.config%rowtype; m record;
begin
  select * into c from crm.config;
  if not coalesce(c.whatsapp_ligado, false) then return; end if;
  -- a Infobip guarda o arquivo por 7 dias; 6 tentativas (inclui arrendamentos vencidos) = desiste
  update crm.mensagem x
     set midia_status = 'falhou', midia_proxima_em = null,
         midia_erro = case when x.em < now() - interval '7 days' then 'Arquivo expirou no provedor (7 dias).'
                           else coalesce(x.midia_erro, 'Download falhou várias vezes.') end
   where x.midia_status = 'pendente' and x.provedor = 'infobip' and (x.em < now() - interval '7 days' or x.midia_tentativas >= 6)
     and x.midia_proxima_em <= now();
  for m in select x.id, x.conversa_id, x.midia_url, x.tipo, x.midia_mime, x.midia_nome
             from crm.mensagem x
            where x.midia_status = 'pendente' and x.provedor = 'infobip' and x.midia_proxima_em <= now()
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
$function$;

CREATE OR REPLACE FUNCTION crm.whatsapp_midia_tem()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select c.whatsapp_ligado from crm.config c), false)
     and exists (select 1 from crm.mensagem m where m.midia_status = 'pendente' and m.provedor = 'infobip' and m.midia_proxima_em <= now());
$function$;

-- ── 5. Tela: canal em cada mensagem e na conversa ──
CREATE OR REPLACE FUNCTION crm.mensagem_json(m crm.mensagem, p_contato uuid)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'canalId', m.numero_id, 'externa', m.externa,
    'midia', case when m.midia_status is not null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;

CREATE OR REPLACE FUNCTION public.crm_conversas(p_limite integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_lim int := least(greatest(coalesce(p_limite, 300), 1), 1000); v jsonb;
begin
  perform crm.exige_comercial();
  with c as (select x.* from crm.conversa x where x.ultima_mensagem_id is not null order by x.ultima_em desc limit v_lim * 2),
  al as (select * from crm.atual_de(array(select distinct c.pessoa_id from c))),
  g as (select al.atual, (array_agg(c.ultima_mensagem_id order by c.ultima_em desc))[1] msg_id, sum(c.nao_lidas)::int nao,
               max(c.ultima_entrada_em) ent, max(c.ultima_em) ult,
               (array_agg(c.numero_id order by c.ultima_em desc))[1] canal, array_agg(distinct c.numero_id) canais
          from c join al on al.pessoa_id = c.pessoa_id group by al.atual order by max(c.ultima_em) desc limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'contatoId', g.atual, 'ultimaMensagem', crm.mensagem_json(m, g.atual), 'naoLidas', g.nao,
           'janelaAteEm', case when g.ent > now() - interval '24 hours' then g.ent + interval '24 hours' end,
           'atribuidaA', pc.dono_id, 'canalId', g.canal, 'canais', to_jsonb(g.canais)) order by g.ult desc), '[]'::jsonb)
    into v
    from g join crm.mensagem m on m.id = g.msg_id
    left join crm.pessoa_comercial pc on pc.pessoa_id = g.atual;
  return v;
end
$function$;

-- ── 6. Envio pelo canal da conversa ──
drop function public.crm_enviar_mensagem(uuid, text, uuid, text, text, uuid);
CREATE FUNCTION public.crm_enviar_mensagem(p_pessoa uuid, p_texto text, p_template uuid DEFAULT NULL::uuid, p_midia text DEFAULT NULL::text, p_midia_nome text DEFAULT NULL::text, p_chave uuid DEFAULT NULL::uuid, p_canal uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; v_conv uuid; cv crm.conversa%rowtype;
        t crm.template%rowtype; v_rend jsonb; v_texto text; v_tipo text := 'texto'; v_vars jsonb; v_id uuid := gen_random_uuid();
        v_s text; v_c text; v_m text;
        v_meta jsonb; v_mime text; v_tam bigint; v_ext text; v_lim bigint; v_mnome text; v_leg text;
        v_dup uuid; v_dup_autor uuid; n crm.numero_whatsapp%rowtype;
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
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  -- canal (20261008152212): o pedido; senão o da conversa mais recente da pessoa (responde pelo mesmo número); senão o oficial
  if p_canal is not null then
    select * into n from crm.numero_whatsapp x where x.id = p_canal;
    if not found then return crm.res(false, 'Número de WhatsApp não encontrado.'); end if;
  else
    select x.* into n from crm.conversa k join crm.numero_whatsapp x on x.id = k.numero_id
     where k.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.ativo
     order by k.ultima_em desc nulls last, k.criado_em desc limit 1;
    if not found then select * into n from crm.numero_whatsapp x where x.id = c.whatsapp_numero_id; end if;
  end if;
  if n.provedor = 'evolution' then
    if not coalesce(c.evolution_ligado, false) then return crm.res(false, 'WhatsApp por QR desligado.'); end if;
    if not coalesce(c.envio_ligado, false) then return crm.res(false, 'Envio de WhatsApp desligado.'); end if;
    if not n.ativo or not n.envia then return crm.res(false, 'Este número não envia pelo CRM.'); end if;
    if n.status <> 'conectado' then return crm.res(false, 'Número desconectado: o gestor reconecta em Configurações.'); end if;
    if p_template is not null then return crm.res(false, 'Template é só do número oficial. Neste número, escreva a mensagem.'); end if;
    if n.dono_id is not null and n.dono_id is distinct from v_eu and not coalesce(crm.eh_gestor(), false) then
      return crm.res(false, 'Este número é de outra pessoa.');
    end if;
  else
    if not coalesce(c.whatsapp_ligado, false) then return crm.res(false, 'WhatsApp desligado.'); end if;
    if not coalesce(c.envio_ligado, false) then return crm.res(false, 'Envio de WhatsApp desligado.'); end if;
    if n.id is null or not n.ativo then return crm.res(false, 'Número de envio não configurado.'); end if;
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
  if not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
  if crm.pessoa_optout(v_atual) then return crm.res(false, 'Contato pediu para não receber mensagens.'); end if;
  if p_template is not null then
    select * into t from crm.template x where x.id = p_template;
    if not found or not t.aprovado or not t.ativo or t.categoria not in ('marketing', 'utility') then
      return crm.res(false, 'Template não aprovado.');
    end if;
    if t.numero_id <> n.id then return crm.res(false, 'Template de outro número de envio.'); end if;
  end if;
  -- daqui em diante a conversa pode ter sido criada: recusa = exceção P0001 (desfaz tudo) → {ok:false}
  v_conv := crm.whatsapp_conversa_para(n.id, v_atual);
  if v_conv is null then return crm.res(false, 'Contato sem telefone de WhatsApp.'); end if;
  select * into cv from crm.conversa x where x.id = v_conv for update;
  if p_template is null then
    -- janela de 24 h é regra da API oficial; número conectado por QR é WhatsApp normal (o anti-ban fica no trigger)
    if n.provedor = 'infobip' and (cv.ultima_entrada_em is null or cv.ultima_entrada_em <= now() - interval '24 hours') then
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
  insert into crm.mensagem (id, conversa_id, numero_id, pessoa_id, direcao, tipo, texto, em, status, status_em, fila_em, autor_id,
                            template_id, template_vars, provedor, provedor_msg_id,
                            midia_status, midia_caminho, midia_mime, midia_tamanho, midia_nome, chave)
  values (v_id, cv.id, n.id, cv.pessoa_id, 'saida', v_tipo, v_texto, now(), 'na_fila', now(), now(), v_eu,
          t.id, v_vars, n.provedor, case when n.provedor = 'infobip' then v_id::text end,
          case when p_midia is not null then 'ok' end, p_midia, case when p_midia is not null then v_mime end,
          case when p_midia is not null then v_tam end, v_mnome, p_chave);
  update crm.conversa x set ultima_em = now(), ultima_mensagem_id = v_id, nao_lidas = 0 where x.id = cv.id;
  update crm.mensagem x set lida_em = now() where x.conversa_id = cv.id and x.direcao = 'entrada' and x.lida_em is null;
  perform crm.log_registrar('enviou', 'mensagem', v_id::text, v_atual,
                            format('Enviou %s para %s%s', case when v_tipo = 'template' then 'template ' || t.nome_provedor
                                                             when v_tipo = 'imagem' then 'imagem'
                                                             when v_tipo = 'documento' then 'PDF'
                                                             when v_tipo = 'audio' then 'áudio' else 'mensagem' end,
                                   crm.nome_pessoa(v_atual), case when n.provedor = 'evolution' then ' pelo número ' || n.nome else '' end),
                            jsonb_build_object('conversa_id', cv.id, 'template_id', t.id, 'canal_id', n.id));
  -- envio na hora: a Edge é chamada depois do COMMIT; falha aqui nunca derruba o enfileiramento
  if n.provedor = 'evolution' then perform crm.evolution_disparar_envio(); else perform crm.whatsapp_disparar_envio(); end if;
  return crm.res(true, 'Mensagem na fila de envio.', jsonb_build_object('mensagemId', v_id, 'canalId', n.id));
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
revoke all on function public.crm_enviar_mensagem(uuid, text, uuid, text, text, uuid, uuid) from public, anon;
grant execute on function public.crm_enviar_mensagem(uuid, text, uuid, text, text, uuid, uuid) to authenticated, service_role;

-- ── 7. Evolution: credenciais, disparo do envio ──
create or replace function crm.evolution_credenciais(out url text, out api_key text, out chave_envio text)
returns record language sql stable security definer set search_path = '' as $$
  select (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'evolution_api_url'),
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'evolution_api_key'),
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'crm_whatsapp_envio_chave');
$$;

create or replace function crm.evolution_disparar_envio() returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_chave text;
begin
  if not coalesce((select c.evolution_ligado and c.envio_ligado and c.envio_imediato from crm.config c), false) then return null; end if;
  select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'crm_whatsapp_envio_chave';
  if coalesce(v_chave, '') = '' then return null; end if;
  return ops.cron_post('crm-evolution-enviar',
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-evolution-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-crm-chave', v_chave),
    body := '{"acao":"enviar"}'::jsonb, timeout_milliseconds := 60000);
exception when others then
  return null;  -- a mensagem já está na fila; o cron de 1 min envia
end $$;

-- ── 8. Evolution: entrada (webhook já normalizado pela Edge) ──
-- e = {canalId, id, fromMe, telefone, nome, tipo, texto, mime, arquivo, em, temMidia}
create or replace function crm.evolution_entrada(e jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  n crm.numero_whatsapp%rowtype; v_conv crm.conversa%rowtype; c crm.config%rowtype;
  v_mid text := e ->> 'id'; v_de text := pessoas.so_digitos(e ->> 'telefone'); v_eu_msg boolean := coalesce((e ->> 'fromMe')::boolean, false);
  v_tipo text := coalesce(e ->> 'tipo', 'outro'); v_texto text; v_em timestamptz; v_nome text; v_reg jsonb; v_pessoa uuid;
  v_id uuid; v_nao int; v_palavra text; v_dono uuid; v_pc uuid; v_midia text; v_mmime text; v_mnome text; v_pid text;
begin
  select * into n from crm.numero_whatsapp x where x.id = (e ->> 'canalId')::uuid and x.provedor = 'evolution';
  if not found or not n.ativo then return 'canal_desconhecido'; end if;
  if not n.recebe then return 'canal_nao_recebe'; end if;
  if coalesce(v_mid, '') !~ '^[A-Za-z0-9_-]{4,120}$' then return 'sem_message_id'; end if;
  -- celular BR sem o 9 (JID antigo de 12 dígitos) vira o formato de 13 dígitos do resto do CRM
  if v_de ~ '^55[1-9][1-9][6-9][0-9]{7}$' then v_de := left(v_de, 4) || '9' || substr(v_de, 5); end if;
  if v_de !~ '^[0-9]{10,15}$' then return 'remetente_invalido'; end if;
  if v_de = n.numero then return 'proprio_numero'; end if;
  select * into c from crm.config;
  if v_tipo not in ('texto', 'imagem', 'documento', 'audio', 'video', 'localizacao', 'contato', 'botao', 'figurinha', 'outro') then
    v_tipo := 'outro';
  end if;
  v_texto := nullif(btrim(coalesce(e ->> 'texto', '')), '');
  v_texto := case v_tipo
               when 'imagem' then '[imagem]' || coalesce(' ' || v_texto, '')
               when 'documento' then '[documento]' || coalesce(' ' || v_texto, '')
               when 'video' then '[vídeo]' || coalesce(' ' || v_texto, '')
               when 'audio' then '[áudio]' when 'localizacao' then '[localização]' when 'contato' then '[contato]'
               when 'figurinha' then '[figurinha]'
               else coalesce(v_texto, '[mensagem não suportada]') end;
  v_texto := left(v_texto, 4096);
  v_em := crm.ts_ou_agora(e ->> 'em');
  v_nome := case when not v_eu_msg then nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), '') end;
  v_pid := n.instancia || ':' || v_mid;
  if v_tipo in ('imagem', 'documento', 'audio', 'video') then
    v_midia := case when coalesce((e ->> 'temMidia')::boolean, false) then 'pendente' else 'falhou' end;
    v_mnome := nullif(left(btrim(regexp_replace(coalesce(e ->> 'arquivo', ''), '[\\/[:cntrl:]]', '_', 'g')), 200), '');
    v_mmime := nullif(left(lower(btrim(coalesce(e ->> 'mime', ''))), 120), '');
  end if;

  select * into v_conv from crm.conversa x where x.numero_id = n.id and x.telefone = v_de for update;
  if not found then
    v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
    if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
    v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
    perform crm.garantir_pc(v_pessoa);
    insert into crm.conversa (numero_id, telefone, pessoa_id, nome_perfil) values (n.id, v_de, v_pessoa, v_nome)
    on conflict (numero_id, telefone) do nothing;
    select * into v_conv from crm.conversa x where x.numero_id = n.id and x.telefone = v_de for update;
  end if;

  if v_eu_msg then
    -- eco da mensagem que o PRÓPRIO CRM mandou (o webhook pode chegar antes da resposta do envio): só liga o id
    update crm.mensagem x set provedor_msg_id = v_pid
     where x.id = (select y.id from crm.mensagem y
                    where y.conversa_id = v_conv.id and y.direcao = 'saida' and not y.externa and y.provedor = 'evolution'
                      and y.provedor_msg_id is null and y.status in ('enviando', 'enviada') and y.tipo = v_tipo
                      and y.em > now() - interval '10 minutes' and (v_tipo <> 'texto' or y.texto = v_texto)
                    order by y.em limit 1)
       and not exists (select 1 from crm.mensagem z where z.provedor = 'evolution' and z.provedor_msg_id = v_pid)
    returning x.id into v_id;
    if v_id is not null then return 'eco_crm'; end if;
    insert into crm.mensagem (conversa_id, numero_id, pessoa_id, direcao, tipo, texto, em, status, status_em, externa, provedor, provedor_msg_id,
                              midia_status, midia_nome, midia_mime, midia_proxima_em, midia_erro)
    values (v_conv.id, n.id, v_conv.pessoa_id, 'saida', v_tipo, v_texto, v_em, 'enviada', v_em, true, 'evolution', v_pid,
            v_midia, v_mnome, v_mmime, case when v_midia = 'pendente' then now() end,
            case when v_midia = 'falhou' then 'Arquivo não veio no webhook.' end)
    on conflict (provedor, provedor_msg_id) do nothing
    returning id into v_id;
    if v_id is null then return 'duplicada'; end if;
    -- respondeu pelo celular: o que o lead mandou antes já foi visto
    update crm.conversa x
       set ultima_mensagem_id = case when x.ultima_em is null or v_em >= x.ultima_em then v_id else x.ultima_mensagem_id end,
           ultima_em = greatest(x.ultima_em, v_em), nao_lidas = 0
     where x.id = v_conv.id;
    update crm.mensagem x set lida_em = now() where x.conversa_id = v_conv.id and x.direcao = 'entrada' and x.lida_em is null and x.em <= v_em;
    return 'ok_saida';
  end if;

  insert into crm.mensagem (conversa_id, numero_id, pessoa_id, direcao, tipo, texto, em, provedor, provedor_msg_id,
                            midia_status, midia_nome, midia_mime, midia_proxima_em, midia_erro)
  values (v_conv.id, n.id, v_conv.pessoa_id, 'entrada', v_tipo, v_texto, v_em, 'evolution', v_pid,
          v_midia, v_mnome, v_mmime, case when v_midia = 'pendente' then now() end,
          case when v_midia = 'falhou' then 'Arquivo não veio no webhook.' end)
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

  -- opt-out por palavra (mesma regra do número oficial)
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

  if v_nao = 1 then
    begin
      select pc.dono_id into v_dono from crm.pessoa_comercial pc
       where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(v_conv.pessoa_id))) and pc.dono_id is not null
       order by pc.pessoa_id = pessoas.atual(v_conv.pessoa_id) desc limit 1;
      if v_dono is not null and not exists (select 1 from crm.preferencias_notificacao p
                                             where p.perfil_id = v_dono and (p.gatilhos ->> 'lead_respondeu') = 'false') then
        insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
        values (v_dono, 'lead_respondeu', v_id::text, left('Respondeu no WhatsApp (' || n.nome || '): ' || crm.nome_pessoa(v_conv.pessoa_id), 200),
                left(v_texto, 140), '/comercial/conversas?contato=' || pessoas.atual(v_conv.pessoa_id))
        on conflict (perfil_id, gatilho, ref_id) do nothing;
      end if;
    exception when others then
      raise warning 'crm.evolution_entrada (aviso): %', sqlstate;
    end;
  end if;
  return 'ok';
end $$;

create or replace function crm.evolution_processar(p_evento bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare ev crm.integracao_evento%rowtype; v_res text;
begin
  select * into ev from crm.integracao_evento x where x.id = p_evento and x.fonte = 'evolution' for update skip locked;
  if not found or ev.processado_em is not null then return 'ja_processado'; end if;
  begin
    perform set_config('crm.canal', 'whatsapp', true);
    v_res := case when ev.tipo = 'mensagem' then crm.evolution_entrada(ev.payload) else 'tipo_desconhecido' end;
    update crm.integracao_evento x set processado_em = now(), resultado = v_res, tentativas = x.tentativas + 1 where x.id = p_evento;
  exception when others then
    v_res := 'erro';
    update crm.integracao_evento x set tentativas = x.tentativas + 1, resultado = left('erro ' || sqlstate || ': ' || sqlerrm, 300)
     where x.id = p_evento;
  end;
  perform set_config('crm.canal', '', true);
  return v_res;
end $$;

create or replace function crm.evolution_reprocessar(p_limite integer default 300) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; k int := 0;
begin
  if not coalesce((select c.evolution_ligado from crm.config c), false) then return 0; end if;
  for v_id in select x.id from crm.integracao_evento x
               where x.processado_em is null and x.fonte = 'evolution' and x.tentativas < 5
               order by x.id limit least(greatest(coalesce(p_limite, 300), 1), 2000) loop
    perform crm.evolution_processar(v_id);
    k := k + 1;
  end loop;
  return k;
end $$;

-- Estado da conexão (webhook CONNECTION_UPDATE ou leitura da tela): estado open|close|connecting, numero, motivo (http)
create or replace function crm.evolution_conexao(p_canal uuid, e jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare n crm.numero_whatsapp%rowtype; v_estado text := lower(coalesce(e ->> 'estado', '')); v_num text := pessoas.so_digitos(e ->> 'numero');
        v_cod int := case when coalesce(e ->> 'codigo', '') ~ '^[0-9]{1,4}$' then (e ->> 'codigo')::int end;
begin
  select * into n from crm.numero_whatsapp x where x.id = p_canal and x.provedor = 'evolution' for update;
  if not found then return 'canal_desconhecido'; end if;
  if v_num ~ '^55[1-9][1-9][6-9][0-9]{7}$' then v_num := left(v_num, 4) || '9' || substr(v_num, 5); end if;
  if v_estado = 'open' then
    if v_num !~ '^[0-9]{10,15}$' then v_num := n.numero; end if;
    if n.numero is not null and v_num is not null and v_num <> n.numero then
      update crm.numero_whatsapp x set status = 'desconectado', status_em = now(),
             status_motivo = 'Outro celular leu o QR. Desconecte e crie um número novo para ele.' where x.id = n.id;
      return 'numero_trocado';
    end if;
    if v_num is not null and exists (select 1 from crm.numero_whatsapp x where x.numero = v_num and x.id <> n.id) then
      update crm.numero_whatsapp x set status = 'desconectado', status_em = now(),
             status_motivo = 'Este celular já está conectado em outro número do CRM.' where x.id = n.id;
      return 'numero_repetido';
    end if;
    update crm.numero_whatsapp x set numero = coalesce(v_num, x.numero), status = 'conectado', status_motivo = null,
           status_em = case when x.status = 'conectado' then x.status_em else now() end,
           conectado_em = case when x.status = 'conectado' then x.conectado_em else now() end
     where x.id = n.id;
    update crm.numero_whatsapp_segredo s set qr_base64 = null, qr_em = null, atualizado_em = now() where s.numero_id = n.id;
    return 'conectado';
  elsif v_estado = 'close' then
    update crm.numero_whatsapp x
       set status = case when v_cod = 403 then 'banido' else 'desconectado' end, status_em = now(),
           status_motivo = left(case when v_cod = 403 then 'O WhatsApp bloqueou este número.'
                                     when v_cod = 401 then 'Sessão encerrada no celular (aparelho desconectado).'
                                     else coalesce(nullif(e ->> 'motivo', ''), 'Conexão caiu.') end, 200)
     where x.id = n.id and (x.status <> 'desconectado' or v_cod = 403);
    return 'desconectado';
  elsif v_estado = 'connecting' then
    return 'conectando';
  end if;
  return 'ignorado';
end $$;

create or replace function crm.evolution_guardar_qr(p_canal uuid, p_base64 text) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_base64, '') !~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' or length(p_base64) > 60000 then return 'qr_invalido'; end if;
  update crm.numero_whatsapp_segredo s set qr_base64 = p_base64, qr_em = now(), atualizado_em = now()
   where s.numero_id = p_canal and exists (select 1 from crm.numero_whatsapp x where x.id = p_canal and x.status <> 'conectado');
  if not found then return 'ignorado'; end if;
  update crm.numero_whatsapp x set status = 'aguardando_qr', status_em = now(), status_motivo = null
   where x.id = p_canal and x.status <> 'aguardando_qr';
  return 'ok';
end $$;

-- Chave do webhook da instância (Edge compara em tempo constante)
create or replace function crm.evolution_chave_webhook(p_instancia text, out canal_id uuid, out chave text)
returns record language sql stable security definer set search_path = '' as $$
  select x.id, s.webhook_chave from crm.numero_whatsapp x join crm.numero_whatsapp_segredo s on s.numero_id = x.id
   where x.instancia = p_instancia and x.provedor = 'evolution' and x.ativo;
$$;

-- Webhook: p_eventos = [{evento:'mensagem'|'conexao'|'qr', ...normalizado}] (até 200). Devolve contagens e as mensagens
-- com arquivo pendente (a Edge sobe o arquivo que veio em base64 e chama crm.whatsapp_midia_resultado).
create or replace function crm.evolution_webhook(p_canal uuid, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_id bigint; v_res text; v_lig boolean := coalesce((select c.evolution_ligado from crm.config c), false);
        n_rec int := 0; n_novo int := 0; n_dup int := 0; n_ign int := 0; n_proc int := 0; n_err int := 0;
        v_midias jsonb := '[]'::jsonb; v_inst text; v_m record; v_ref int := -1;
begin
  select x.instancia into v_inst from crm.numero_whatsapp x where x.id = p_canal and x.provedor = 'evolution';
  if v_inst is null or jsonb_typeof(p_eventos) is distinct from 'array' then return jsonb_build_object('ok', false); end if;
  for r in select x from jsonb_array_elements(p_eventos) with ordinality t(x, o) where o <= 200 loop
    n_rec := n_rec + 1; v_ref := v_ref + 1;
    if r ->> 'evento' = 'conexao' then
      perform crm.evolution_conexao(p_canal, r); n_proc := n_proc + 1; continue;
    elsif r ->> 'evento' = 'qr' then
      perform crm.evolution_guardar_qr(p_canal, r ->> 'base64'); n_proc := n_proc + 1; continue;
    elsif r ->> 'evento' is distinct from 'mensagem' or coalesce(r ->> 'id', '') !~ '^[A-Za-z0-9_-]{4,120}$' then
      n_ign := n_ign + 1; continue;
    end if;
    insert into crm.integracao_evento (fonte, tipo, fonte_evento_id, payload)
    values ('evolution', 'mensagem', left('msg:' || v_inst || ':' || (r ->> 'id'), 300), (r - 'evento') || jsonb_build_object('canalId', p_canal))
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then
      n_dup := n_dup + 1;
    else
      n_novo := n_novo + 1;
      if v_lig then
        v_res := crm.evolution_processar(v_id);
        if v_res = 'erro' then n_err := n_err + 1; else n_proc := n_proc + 1; end if;
      end if;
    end if;
    -- arquivo ainda pendente (novo ou reenvio do webhook depois de falha no upload)
    select m.id, m.conversa_id into v_m from crm.mensagem m
     where m.provedor = 'evolution' and m.provedor_msg_id = v_inst || ':' || (r ->> 'id') and m.midia_status = 'pendente';
    if found then
      v_midias := v_midias || jsonb_build_object('ref', v_ref, 'mensagemId', v_m.id, 'conversaId', v_m.conversa_id);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'recebidos', n_rec, 'novos', n_novo, 'duplicados', n_dup, 'ignorados', n_ign,
                            'processados', n_proc, 'erros', n_err, 'ligado', v_lig, 'midias', v_midias);
end $$;

-- ── 9. Evolution: fila de envio ──
create or replace function crm.evolution_fila_tem() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select c.evolution_ligado from crm.config c), false)
     and (exists (select 1 from crm.integracao_evento x where x.fonte = 'evolution' and x.processado_em is null and x.tentativas < 5)
          or (coalesce((select c.envio_ligado from crm.config c), false)
              and (exists (select 1 from crm.mensagem m where m.status = 'na_fila' and m.provedor = 'evolution' and m.fila_em <= now()
                              and coalesce(m.proxima_tentativa_em, m.fila_em) <= now())
                   or exists (select 1 from crm.mensagem m where m.status = 'enviando' and m.provedor = 'evolution'
                                and m.status_em < now() - interval '5 minutes')))
          or exists (select 1 from crm.mensagem m where m.midia_status = 'pendente' and m.provedor = 'evolution'
                       and m.midia_proxima_em < now() - interval '15 minutes'));
$$;

create or replace function crm.evolution_fila_pegar(p_lote integer default 20)
returns table(mensagem_id uuid, instancia text, para text, tipo text, texto text, midia_caminho text, midia_nome text, midia_mime text, legenda text)
language plpgsql security definer set search_path = '' as $$
declare c crm.config%rowtype; m record; v_erro text;
begin
  select * into c from crm.config;
  if not coalesce(c.evolution_ligado, false) then return; end if;
  -- arquivo recebido que não subiu em 15 min (a Edge do webhook morreu): o base64 não volta mais
  update crm.mensagem x set midia_status = 'falhou', midia_proxima_em = null, midia_erro = 'Arquivo não chegou ao CRM.'
   where x.midia_status = 'pendente' and x.provedor = 'evolution' and x.midia_proxima_em < now() - interval '15 minutes';
  if not coalesce(c.envio_ligado, false) then return; end if;
  update crm.mensagem x set status = 'falhou', falha_incerta = true, status_em = now(),
         erro = 'Sem confirmação do WhatsApp: confira no celular se saiu.'
   where x.status = 'enviando' and x.provedor = 'evolution' and x.status_em < now() - interval '5 minutes';
  update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Expirou na fila sem envio.'
   where x.status = 'na_fila' and x.provedor = 'evolution' and x.fila_em < now() - make_interval(mins => c.envio_validade_min);
  for m in select x.id, x.pessoa_id, x.tipo, x.texto, cv.telefone, n.instancia, n.ativo, n.envia, n.status n_status,
                  x.midia_status, x.midia_caminho, x.midia_nome, x.midia_mime,
                  (x.midia_caminho is not null and exists (select 1 from storage.objects o
                                                           where o.bucket_id = 'crm-midia' and o.name = x.midia_caminho)) arq_ok
             from crm.mensagem x
             join crm.conversa cv on cv.id = x.conversa_id
             join crm.numero_whatsapp n on n.id = x.numero_id
            where x.status = 'na_fila' and x.provedor = 'evolution' and x.fila_em <= now()
              and coalesce(x.proxima_tentativa_em, x.fila_em) <= now()
            order by x.fila_em, x.id
            limit least(greatest(coalesce(p_lote, 20), 1), 60)
              for update of x skip locked loop
    v_erro := case when not m.ativo or not m.envia then 'Número não envia pelo CRM.'
                   when m.n_status <> 'conectado' then 'Número desconectado.'
                   when crm.pessoa_optout(m.pessoa_id) then 'Contato pediu para não receber mensagens.'
                   when m.tipo not in ('texto', 'imagem', 'documento', 'audio') then 'Tipo de mensagem não suportado neste número.'
                   when m.tipo in ('imagem', 'documento', 'audio') and (m.midia_status is distinct from 'ok' or not m.arq_ok)
                     then 'Arquivo do anexo indisponível.' end;
    if v_erro is not null then
      update crm.mensagem x set status = 'falhou', status_em = now(), erro = v_erro where x.id = m.id;
      continue;
    end if;
    update crm.mensagem x set status = 'enviando', status_em = now(), tentativas = x.tentativas + 1 where x.id = m.id;
    mensagem_id := m.id; instancia := m.instancia; para := m.telefone; tipo := m.tipo; texto := m.texto;
    midia_caminho := case when m.tipo in ('imagem', 'documento', 'audio') then m.midia_caminho end;
    midia_nome := case when m.tipo = 'documento' then m.midia_nome end;
    midia_mime := case when m.tipo in ('imagem', 'documento', 'audio') then m.midia_mime end;
    legenda := case when m.tipo in ('imagem', 'documento') and m.texto !~ '^\[(imagem|documento)\]' then m.texto end;
    return next;
  end loop;
end $$;

-- p_msg_id = key.id devolvido pela Evolution
create or replace function crm.evolution_fila_resultado(p_mensagem uuid, p_http integer, p_msg_id text, p_erro text, p_reenfileirar boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
declare m crm.mensagem%rowtype; v_inst text; v_pid text;
begin
  select * into m from crm.mensagem x where x.id = p_mensagem and x.provedor = 'evolution' for update;
  if not found or m.status <> 'enviando' then return 'ignorado'; end if;
  if coalesce(p_reenfileirar, false) and m.tentativas < 5 then
    update crm.mensagem x set status = 'na_fila', status_em = now(), erro = left(p_erro, 300),
           proxima_tentativa_em = now() + make_interval(mins => greatest(m.tentativas, 1))
     where x.id = m.id;
    return 'na_fila';
  elsif p_http between 200 and 299 then
    select n.instancia into v_inst from crm.numero_whatsapp n where n.id = m.numero_id;
    v_pid := case when coalesce(p_msg_id, '') ~ '^[A-Za-z0-9_-]{4,120}$' then v_inst || ':' || p_msg_id end;
    update crm.mensagem x set status = 'enviada', status_em = now(), erro = null,
           provedor_msg_id = case when x.provedor_msg_id is null and v_pid is not null
                                   and not exists (select 1 from crm.mensagem z where z.provedor = 'evolution' and z.provedor_msg_id = v_pid)
                                  then v_pid else x.provedor_msg_id end
     where x.id = m.id;
    return 'enviada';
  elsif coalesce(p_http, 0) = 0 or p_http >= 500 then
    update crm.mensagem x set status = 'falhou', falha_incerta = true, status_em = now(),
           erro = left('Sem confirmação do WhatsApp: ' || coalesce(p_erro, 'sem resposta'), 300)
     where x.id = m.id;
    return 'falhou_incerta';
  else
    update crm.mensagem x set status = 'falhou', status_em = now(), erro = left(coalesce(p_erro, 'HTTP ' || p_http), 300) where x.id = m.id;
    return 'falhou';
  end if;
end $$;

-- ── 10. Telas (authenticated) ──
create or replace function public.crm_canais() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object(
    'evolutionLigado', c.evolution_ligado, 'envioLigado', c.envio_ligado,
    'limiteMinuto', c.evolution_limite_minuto, 'limiteHora', c.evolution_limite_hora, 'novosHora', c.evolution_novos_hora,
    'canais', coalesce((select jsonb_agg(jsonb_build_object(
        'id', n.id, 'provedor', n.provedor, 'nome', n.nome, 'final', right(n.numero, 4), 'status', n.status,
        'statusEm', n.status_em, 'statusMotivo', n.status_motivo, 'conectadoEm', n.conectado_em, 'ativo', n.ativo,
        'recebe', n.recebe, 'envia', n.envia, 'donoId', n.dono_id, 'equipe', n.equipe, 'padrao', n.id = c.whatsapp_numero_id,
        'criadoEm', n.criado_em) order by (n.provedor = 'infobip') desc, n.criado_em)
      from crm.numero_whatsapp n where n.ativo), '[]'::jsonb))
    into v from crm.config c;
  return coalesce(v, jsonb_build_object('canais', '[]'::jsonb));
end $$;

create or replace function public.crm_canal_criar(p_nome text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_nome text := btrim(coalesce(p_nome, '')); v_slug text; v_inst text; v_id uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor do Comercial conecta números.'); end if;
  if length(v_nome) not between 2 and 80 then return crm.res(false, 'Dê um nome ao número (2 a 80 caracteres).'); end if;
  if (select count(*) from crm.numero_whatsapp x where x.provedor = 'evolution' and x.ativo) >= 10 then
    return crm.res(false, 'Limite de 10 números conectados por QR.');
  end if;
  v_slug := trim(both '-' from left(regexp_replace(lower(mkt.sem_acento(v_nome)), '[^a-z0-9]+', '-', 'g'), 24));
  v_inst := 'crm-' || coalesce(nullif(v_slug, ''), 'numero') || '-' || encode(extensions.gen_random_bytes(3), 'hex');
  insert into crm.numero_whatsapp (provedor, numero, nome, instancia, status, status_motivo, criado_por)
  values ('evolution', null, v_nome, v_inst, 'aguardando_qr', null, auth.uid())
  returning id into v_id;
  insert into crm.numero_whatsapp_segredo (numero_id, webhook_chave) values (v_id, encode(extensions.gen_random_bytes(32), 'hex'));
  perform crm.log_registrar('criou', 'config', v_id::text, null, format('Criou o número de WhatsApp "%s" (QR)', v_nome), '{}'::jsonb);
  return crm.res(true, null, jsonb_build_object('canalId', v_id, 'instancia', v_inst));
end $$;

-- Portão das ações na Evolution feitas pelo Route Handler (que só então usa a chave global): conectar|desconectar|ver
create or replace function public.crm_canal_portao(p_canal uuid, p_acao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; n crm.numero_whatsapp%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor do Comercial conecta ou desconecta números.'); end if;
  if p_acao not in ('conectar', 'desconectar', 'ver') then return crm.res(false, 'Ação inválida.'); end if;
  select * into n from crm.numero_whatsapp x where x.id = p_canal;
  if not found or not n.ativo then return crm.res(false, 'Número não encontrado.'); end if;
  if n.provedor <> 'evolution' then return crm.res(false, 'O número oficial é configurado na Infobip, não por QR.'); end if;
  if p_acao <> 'ver' then
    perform crm.log_registrar('editou', 'config', n.id::text, null,
                              format('%s o número de WhatsApp "%s"', case when p_acao = 'conectar' then 'Pediu QR para' else 'Desconectou' end, n.nome),
                              '{}'::jsonb);
  end if;
  return crm.res(true, null, jsonb_build_object('instancia', n.instancia, 'status', n.status));
end $$;

create or replace function public.crm_canal_salvar(p_canal uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; n crm.numero_whatsapp%rowtype; v_nome text; v_dono uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor do Comercial altera números.'); end if;
  select * into n from crm.numero_whatsapp x where x.id = p_canal for update;
  if not found then return crm.res(false, 'Número não encontrado.'); end if;
  v_nome := coalesce(nullif(btrim(p_dados ->> 'nome'), ''), n.nome);
  if length(v_nome) > 80 then return crm.res(false, 'Nome longo demais.'); end if;
  if p_dados ? 'donoId' then
    v_dono := nullif(p_dados ->> 'donoId', '')::uuid;
    if v_dono is not null and not exists (select 1 from crm.vendedor v where v.perfil_id = v_dono) then
      return crm.res(false, 'Dono precisa ser alguém da equipe do Comercial.');
    end if;
  else
    v_dono := n.dono_id;
  end if;
  update crm.numero_whatsapp x set nome = v_nome, dono_id = v_dono,
         recebe = coalesce((p_dados ->> 'recebe')::boolean, x.recebe),
         envia = case when x.provedor = 'infobip' then x.envia else coalesce((p_dados ->> 'envia')::boolean, x.envia) end,
         ativo = case when x.provedor = 'evolution' and (p_dados ->> 'ativo') = 'false' and x.status <> 'conectado' then false else x.ativo end
   where x.id = n.id;
  perform crm.log_registrar('editou', 'config', n.id::text, null, format('Alterou o número de WhatsApp "%s"', v_nome), p_dados - 'nome');
  return crm.res(true, 'Número salvo.');
exception when invalid_text_representation then
  return crm.res(false, 'Dados inválidos.');
end $$;

-- Só service_role (Route Handler, depois do portão): segredos para falar com a Evolution e gravar o que ela devolveu
create or replace function public.crm_evolution_servico(p_acao text, p_canal uuid, p_dados jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n crm.numero_whatsapp%rowtype; s crm.numero_whatsapp_segredo%rowtype;
begin
  select * into n from crm.numero_whatsapp x where x.id = p_canal and x.provedor = 'evolution';
  if not found then return jsonb_build_object('ok', false, 'msg', 'Número não encontrado.'); end if;
  select * into s from crm.numero_whatsapp_segredo x where x.numero_id = n.id;
  if p_acao = 'webhook' then
    return jsonb_build_object('ok', true, 'instancia', n.instancia, 'webhookChave', s.webhook_chave);
  elsif p_acao = 'qr_ler' then
    return jsonb_build_object('ok', true, 'status', n.status,
      'qr', case when s.qr_em > now() - interval '25 seconds' then s.qr_base64 end);
  elsif p_acao = 'qr_guardar' then
    return jsonb_build_object('ok', true, 'r', crm.evolution_guardar_qr(n.id, p_dados ->> 'base64'));
  elsif p_acao = 'estado' then
    return jsonb_build_object('ok', true, 'r', crm.evolution_conexao(n.id, p_dados));
  elsif p_acao = 'desconectado' then
    update crm.numero_whatsapp x set status = 'desconectado', status_em = now(),
           status_motivo = left(coalesce(nullif(p_dados ->> 'motivo', ''), 'Desconectado pelo gestor.'), 200)
     where x.id = n.id;
    update crm.numero_whatsapp_segredo x set qr_base64 = null, qr_em = null, atualizado_em = now() where x.numero_id = n.id;
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('ok', false, 'msg', 'Ação inválida.');
end $$;

-- ── 11. Permissões: tudo nasce executável por PUBLIC ──
revoke all on function crm.evolution_credenciais() from public, anon, authenticated, service_role;
revoke all on function crm.evolution_disparar_envio() from public, anon, authenticated, service_role;
revoke all on function crm.evolution_entrada(jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_processar(bigint) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_reprocessar(integer) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_conexao(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_guardar_qr(uuid, text) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_chave_webhook(text) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_webhook(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_fila_tem() from public, anon, authenticated, service_role;
revoke all on function crm.evolution_fila_pegar(integer) from public, anon, authenticated, service_role;
revoke all on function crm.evolution_fila_resultado(uuid, integer, text, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.crm_canais() from public, anon;
revoke all on function public.crm_canal_criar(text) from public, anon;
revoke all on function public.crm_canal_portao(uuid, text) from public, anon;
revoke all on function public.crm_canal_salvar(uuid, jsonb) from public, anon;
revoke all on function public.crm_evolution_servico(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.crm_canais() to authenticated;
grant execute on function public.crm_canal_criar(text) to authenticated;
grant execute on function public.crm_canal_portao(uuid, text) to authenticated;
grant execute on function public.crm_canal_salvar(uuid, jsonb) to authenticated;
grant execute on function public.crm_evolution_servico(text, uuid, jsonb) to service_role;

-- ── 12. Cron de reserva (1/min, só chama a Edge quando há trabalho) ──
select cron.schedule('crm-evolution-enviar', '* * * * *', $c$ select crm.evolution_reprocessar(), (select ops.cron_post('crm-evolution-enviar',
  url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-evolution-enviar',
  headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
             (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
  body := '{"acao":"enviar"}'::jsonb, timeout_milliseconds := 60000) where crm.evolution_fila_tem()) $c$);
