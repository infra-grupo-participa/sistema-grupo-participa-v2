-- 20261009153515: CRM, ações na mensagem (responder citando, editar, apagar para todos), status do atendimento
-- (aberto / em espera / encerrado) e mensagem agendada.
--
-- STATUS: APLICADA em 09/10/2026 (versão gravada 20261009153515). Ver 20261009153515.explain.md e _ensaio.sql (38/38).
--
-- POR QUE
--   Pedido do Marcos Paulo (gestor e vendedor), repassado pelo Arthur com ok para construir (09/10/2026): itens 2
--   (ações na mensagem), 4 (agendar mensagem pelo painel da conversa) e 5 (status do atendimento) da tela de Conversas.
--
-- O QUE FAZ
--   a. crm.mensagem: editada_em, apagada_em, apagada_por, citada_id, agendada_para (+ índice parcial das agendadas).
--      O texto ANTERIOR de uma edição não é guardado em lugar nenhum (decisão: é conteúdo de conversa, dado pessoal; o
--      log registra só que houve edição e o tamanho antes/depois). Mensagem apagada continua na linha (prova de
--      atendimento), mas a API (crm.mensagem_json) devolve "Mensagem apagada" sem texto nem arquivo.
--   b. crm.conversa: atendimento ('aberto' | 'espera' | 'encerrado'), atendimento_em, atendimento_por.
--      Mensagem nova do contato (entrada) reabre sozinha (trigger crm.tg_mensagem_reabre). Em espera e encerrada saem
--      da fila de "esperando resposta" e dos contadores (regra na tela: domain/atendimento.ts).
--   c. crm.mensagem_acao: fila de edição/exclusão para o número QR (Evolution). Quem fala com a Evolution é a Edge
--      crm-evolution-enviar (a mesma do envio), nunca o navegador. RLS ligada sem policy (só funções do dono).
--   d. public.crm_mensagem_editar / crm_mensagem_apagar: só mensagem ENVIADA pelo CRM, por quem enviou ou pelo gestor,
--      só número QR, dentro do limite do WhatsApp (editar 15 min; apagar para todos 48 h). Oficial (API Cloud) não tem
--      editar/apagar: recusa com o motivo.
--   e. public.crm_responder_mensagem: responde citando (só QR; Infobip sem citação confirmada na doc). Usa
--      crm_enviar_mensagem inteira (todas as travas da tela) e marca citada_id na mensagem nova.
--   f. public.crm_conversa_atendimento: muda o status do atendimento (dono do contato/negócio ou gestor; leitor não).
--   g. public.crm_agendar_mensagem / crm_cancelar_agendada: mensagem agendada entra na MESMA fila do envio
--      (crm.mensagem status na_fila, fila_em = enviar_em). As funções de fila já ignoram fila_em no futuro e revalidam
--      tudo na hora (janela de 24 h, template aprovado, número conectado, opt-out). Falhou na hora → status falhou com
--      o motivo + aviso ao autor (crm.notificacao gatilho 'mensagem_falhou'). Cancelar = sai da fila e some da conversa.
--   h. crm.evolution_acoes_pegar / crm.evolution_acao_resultado / crm.evolution_citacoes: contrato da Edge.
--      crm.evolution_alteracao: edição/exclusão que chega pelo webhook (o contato editou/apagou, ou o celular).
--   i. Recriados a partir do corpo VIVO (md5 conferido na guarda): crm.mensagem_json (+ editadaEm, apagadaEm, citadaId,
--      agendadaPara), public.crm_conversas (+ atendimento), crm.tg_rt_caixa (+ colunas novas), crm.tg_mensagem_canal
--      (anti-ban não conta agendada do futuro), crm.evolution_webhook (+ eventos edicao/revogacao),
--      crm.evolution_fila_tem (+ ações pendentes).
--   j. crm.notificacao: gatilho 'mensagem_falhou' (CHECK reescrito a partir de pg_get_constraintdef vivo).
--
-- REVERSÃO: 20261009153515_reversao.sql. Kill-switches existentes: crm.config.envio_ligado / evolution_ligado (param a
-- fila de envio e de ações), escrita_ligada (para as RPCs de escrita).

-- ═══ Guarda de premissa: corpo vivo igual ao lido em 09/10/2026 ═══
do $$
declare v text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname, p.proname, md5(p.prosrc)) not in (
     ('crm', 'mensagem_json', '3f9649c311d49e4504a13ce1794c7107'),
     ('public', 'crm_conversas', 'f813b5f3c4fb74f833326e256dfaa6fc'),
     ('crm', 'tg_rt_caixa', 'e487964b32d9bb44511403e5cd8e455d'),
     ('crm', 'tg_mensagem_canal', 'a98a151dc0294887b2973e0f3da515b7'),
     ('crm', 'evolution_webhook', 'c3526c98c078c58d6e7c806327487a7e'),
     ('crm', 'evolution_fila_tem', 'fff496564b557bff17ee4bf2b161f6e0'))
     and (n.nspname, p.proname) in (('crm', 'mensagem_json'), ('public', 'crm_conversas'), ('crm', 'tg_rt_caixa'),
                                    ('crm', 'tg_mensagem_canal'), ('crm', 'evolution_webhook'), ('crm', 'evolution_fila_tem'));
  if v is not null then raise exception 'Premissa: corpo mudou desde a leitura (%). Reler e refazer.', v; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'mensagem' and column_name = 'editada_em')
     or exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'conversa' and column_name = 'atendimento') then
    raise exception 'Premissa: colunas novas já existem.';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'crm.notificacao'::regclass and c.conname = 'notificacao_gatilho_check')
     is distinct from 'CHECK ((gatilho = ANY (ARRAY[''lead_novo''::text, ''lead_respondeu''::text, ''prazo_estourado''::text, ''venda_aprovada''::text, ''ficha_para_aprovar''::text, ''atividade_vencendo''::text, ''estrategia''::text])))' then
    raise exception 'Premissa: CHECK de crm.notificacao.gatilho mudou.';
  end if;
end $$;

-- ═══ a. crm.mensagem ═══
alter table crm.mensagem
  add column editada_em timestamptz,
  add column apagada_em timestamptz,
  add column apagada_por uuid references public.perfis(id) on delete restrict,
  add column citada_id uuid references crm.mensagem(id) on delete restrict,
  add column agendada_para timestamptz,
  add constraint mensagem_apagada_check check (apagada_em is not null or apagada_por is null),
  add constraint mensagem_agendada_check check (agendada_para is null or direcao = 'saida');
comment on column crm.mensagem.editada_em is 'Quando o texto foi editado (pelo CRM ou pelo WhatsApp). O texto anterior não é guardado.';
comment on column crm.mensagem.apagada_em is 'Apagada para todos (pelo CRM, pelo celular ou pelo contato). A API devolve "Mensagem apagada".';
comment on column crm.mensagem.apagada_por is 'Quem apagou pelo CRM; null = apagada no WhatsApp (contato ou celular).';
comment on column crm.mensagem.citada_id is 'Resposta citando esta mensagem (só número QR).';
comment on column crm.mensagem.agendada_para is 'Mensagem agendada: entra na fila com fila_em = agendada_para.';
create index mensagem_agendada_idx on crm.mensagem (pessoa_id, agendada_para) where agendada_para is not null and status = 'na_fila';

-- ═══ b. crm.conversa ═══
alter table crm.conversa
  add column atendimento text not null default 'aberto',
  add column atendimento_em timestamptz,
  add column atendimento_por uuid references public.perfis(id) on delete restrict,
  add constraint conversa_atendimento_check check (atendimento in ('aberto', 'espera', 'encerrado'));
comment on column crm.conversa.atendimento is 'aberto | espera (pausa o SLA) | encerrado (sai da fila e dos contadores). Mensagem nova do contato reabre.';

-- ═══ c. crm.mensagem_acao ═══
create table crm.mensagem_acao (
  id uuid primary key default gen_random_uuid(),
  mensagem_id uuid not null references crm.mensagem(id) on delete restrict,
  tipo text not null check (tipo in ('editar', 'apagar')),
  texto text check (texto is null or (length(texto) between 1 and 4096)),
  status text not null default 'na_fila' check (status in ('na_fila', 'enviando', 'feita', 'falhou')),
  erro text check (erro is null or length(erro) <= 300),
  tentativas smallint not null default 0 check (tentativas between 0 and 20),
  autor_id uuid not null references public.perfis(id) on delete restrict,
  criado_em timestamptz not null default now(),
  status_em timestamptz not null default now(),
  constraint mensagem_acao_editar_texto_check check ((tipo = 'editar') = (texto is not null))
);
comment on table crm.mensagem_acao is 'Fila de edição/exclusão de mensagem no número QR (Evolution). Processada pela Edge crm-evolution-enviar.';
create unique index mensagem_acao_pendente_key on crm.mensagem_acao (mensagem_id) where status in ('na_fila', 'enviando');
create index mensagem_acao_fila_idx on crm.mensagem_acao (criado_em) where status in ('na_fila', 'enviando');
alter table crm.mensagem_acao enable row level security;
revoke all on table crm.mensagem_acao from public, anon, authenticated;

-- ═══ j. crm.notificacao: gatilho novo ═══
alter table crm.notificacao drop constraint notificacao_gatilho_check;
alter table crm.notificacao add constraint notificacao_gatilho_check check (gatilho = any (array['lead_novo'::text, 'lead_respondeu'::text,
  'prazo_estourado'::text, 'venda_aprovada'::text, 'ficha_para_aprovar'::text, 'atividade_vencendo'::text, 'estrategia'::text,
  'mensagem_falhou'::text]));

-- ═══ i. crm.mensagem_json (corpo vivo 3f9649c3… + campos novos; apagada sem texto/arquivo) ═══
create or replace function crm.mensagem_json(m crm.mensagem, p_contato uuid)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao,
    'tipo', case when m.apagada_em is not null then 'texto' else m.tipo end,
    'texto', case when m.apagada_em is not null then 'Mensagem apagada' else m.texto end, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'canalId', m.numero_id, 'externa', m.externa, 'origem', m.origem,
    'editadaEm', m.editada_em, 'apagadaEm', m.apagada_em, 'citadaId', m.citada_id, 'agendadaPara', m.agendada_para,
    'midia', case when m.midia_status is not null and m.apagada_em is null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;

-- ═══ i. public.crm_conversas (corpo vivo f813b5f3… + atendimento da conversa mais recente) ═══
create or replace function public.crm_conversas(p_limite integer default 300)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_lim int := least(greatest(coalesce(p_limite, 300), 1), 1000); v jsonb;
begin
  perform crm.exige_comercial();
  with c as (select x.* from crm.conversa x where x.ultima_mensagem_id is not null and x.excluida_em is null order by x.ultima_em desc limit v_lim * 2),
  al as (select * from crm.atual_de(array(select distinct c.pessoa_id from c))),
  g as (select al.atual, (array_agg(c.ultima_mensagem_id order by c.ultima_em desc))[1] msg_id, sum(c.nao_lidas)::int nao,
               max(c.ultima_entrada_em) ent, max(c.ultima_em) ult,
               (array_agg(c.numero_id order by c.ultima_em desc))[1] canal, array_agg(distinct c.numero_id) canais,
               jsonb_agg(jsonb_build_object('id', c.id, 'canalId', c.numero_id) order by c.ultima_em desc) convs,
               (array_agg(jsonb_build_object('estado', c.atendimento, 'em', c.atendimento_em, 'por', c.atendimento_por)
                          order by c.ultima_em desc))[1] atend
          from c join al on al.pessoa_id = c.pessoa_id group by al.atual order by max(c.ultima_em) desc limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'contatoId', g.atual, 'ultimaMensagem', crm.mensagem_json(m, g.atual), 'naoLidas', g.nao,
           'janelaAteEm', case when g.ent > now() - interval '24 hours' then g.ent + interval '24 hours' end,
           'atribuidaA', pc.dono_id, 'canalId', g.canal, 'canais', to_jsonb(g.canais), 'conversas', g.convs,
           'atendimento', g.atend ->> 'estado', 'atendimentoEm', g.atend -> 'em', 'atendimentoPor', g.atend -> 'por')
           order by g.ult desc), '[]'::jsonb)
    into v
    from g join crm.mensagem m on m.id = g.msg_id
    left join crm.pessoa_comercial pc on pc.pessoa_id = g.atual;
  return v;
end
$function$;

-- ═══ i. crm.tg_rt_caixa (corpo vivo e487964b… + colunas novas) ═══
create or replace function crm.tg_rt_caixa()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_mudou boolean := false;
begin
  begin
    if tg_table_name = 'mensagem' and tg_op = 'INSERT' then
      v_mudou := exists (select 1 from novas);
    elsif tg_table_name = 'mensagem' then
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.status, n.lida_em, n.erro, n.texto, n.tipo, n.em, n.pessoa_id, n.autor_id, n.template_id,
                n.midia_status, n.midia_caminho, n.midia_mime, n.midia_tamanho, n.midia_nome,
                n.editada_em, n.apagada_em, n.citada_id, n.agendada_para, n.excluida_em)
               is distinct from
               (o.status, o.lida_em, o.erro, o.texto, o.tipo, o.em, o.pessoa_id, o.autor_id, o.template_id,
                o.midia_status, o.midia_caminho, o.midia_mime, o.midia_tamanho, o.midia_nome,
                o.editada_em, o.apagada_em, o.citada_id, o.agendada_para, o.excluida_em));
    elsif tg_table_name = 'conversa' then
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.nao_lidas, n.pessoa_id, n.atendimento, n.ultima_mensagem_id) is distinct from (o.nao_lidas, o.pessoa_id, o.atendimento, o.ultima_mensagem_id));
    end if;
    if v_mudou then
      perform realtime.send(jsonb_build_object('t', tg_table_name), 'mudou', 'crm:caixa', true);
    end if;
  exception when others then
    raise warning 'crm.tg_rt_caixa: %', sqlerrm;
  end;
  return null;
end $function$;

-- ═══ i. crm.tg_mensagem_canal (corpo vivo a98a151d…; anti-ban não conta mensagem agendada do futuro) ═══
create or replace function crm.tg_mensagem_canal()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
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
    perform pg_advisory_xact_lock(hashtext('crm.evolution.envio'), hashtext(new.numero_id::text));
    select count(*) filter (where m.em > now() - interval '1 minute'), count(*)
      into v_min, v_hora
      from crm.mensagem m
     where m.numero_id = new.numero_id and m.direcao = 'saida' and not m.externa and m.em > now() - interval '1 hour' and m.em <= now();
    if v_min >= c.evolution_limite_minuto then
      raise exception 'Limite deste número: % mensagens por minuto. Espere um pouco (proteção contra banimento).', c.evolution_limite_minuto using errcode = 'P0001';
    end if;
    if v_hora >= c.evolution_limite_hora then
      raise exception 'Limite deste número: % mensagens por hora (proteção contra banimento).', c.evolution_limite_hora using errcode = 'P0001';
    end if;
    select cv.ultima_entrada_em is null into v_fria from crm.conversa cv where cv.id = new.conversa_id;
    if coalesce(v_fria, true) and not exists (
         select 1 from crm.mensagem m where m.conversa_id = new.conversa_id and m.direcao = 'saida' and not m.externa
            and m.em > now() - interval '1 hour' and m.em <= now()) then
      select count(distinct m.conversa_id) into v_novos
        from crm.mensagem m join crm.conversa cv on cv.id = m.conversa_id
       where m.numero_id = new.numero_id and m.direcao = 'saida' and not m.externa and m.em > now() - interval '1 hour'
         and m.em <= now() and cv.ultima_entrada_em is null;
      if v_novos >= c.evolution_novos_hora then
        raise exception 'Limite deste número: % primeiros contatos por hora (quem nunca escreveu). Proteção contra banimento.', c.evolution_novos_hora using errcode = 'P0001';
      end if;
    end if;
  end if;
  return new;
end $function$;

-- ═══ b. Mensagem nova do contato reabre o atendimento ═══
create or replace function crm.tg_mensagem_reabre()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid;
begin
  begin
    with u as (
      update crm.conversa x set atendimento = 'aberto', atendimento_em = now(), atendimento_por = null
       where x.pessoa_id = any(crm.grupo_rapido(new.pessoa_id)) and x.excluida_em is null and x.atendimento <> 'aberto'
      returning x.id)
    select min(u.id::text)::uuid into v_id from u;
    if v_id is not null then
      perform crm.log_registrar('editou', 'conversa', v_id::text, pessoas.atual(new.pessoa_id),
                                'Atendimento reaberto: chegou mensagem de ' || crm.nome_pessoa(new.pessoa_id),
                                jsonb_build_object('atendimento', 'aberto', 'motivo', 'mensagem_do_contato'));
    end if;
  exception when others then
    raise warning 'crm.tg_mensagem_reabre: %', sqlstate;
  end;
  return null;
end $function$;
create trigger mensagem_reabre after insert on crm.mensagem
  for each row when (new.direcao = 'entrada') execute function crm.tg_mensagem_reabre();

-- ═══ g. Agendada saiu da fila: vira a última da conversa; falhou: avisa o autor ═══
create or replace function crm.tg_mensagem_agendada()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  begin
    if new.excluida_em is not null then return null; end if;
    if new.status in ('enviando', 'enviada', 'entregue', 'lida') then
      update crm.conversa x
         set ultima_mensagem_id = case when x.ultima_em is null or new.em >= x.ultima_em then new.id else x.ultima_mensagem_id end,
             ultima_em = greatest(x.ultima_em, new.em)
       where x.id = new.conversa_id;
    elsif new.status = 'falhou' and new.autor_id is not null then
      insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
      values (new.autor_id, 'mensagem_falhou', new.id::text,
              left('Mensagem agendada não saiu: ' || crm.nome_pessoa(new.pessoa_id), 200),
              left(coalesce(new.erro, 'Falhou no envio.'), 140), '/comercial/conversas?contato=' || pessoas.atual(new.pessoa_id))
      on conflict (perfil_id, gatilho, ref_id) do nothing;
    end if;
  exception when others then
    raise warning 'crm.tg_mensagem_agendada: %', sqlstate;
  end;
  return null;
end $function$;
create trigger mensagem_agendada after update on crm.mensagem
  for each row when (old.agendada_para is not null and old.status = 'na_fila' and new.status is distinct from 'na_fila')
  execute function crm.tg_mensagem_agendada();

-- ═══ d. Editar / apagar para todos (só QR) ═══
-- Regra comum: devolve null (pode) ou o motivo. Espelho em web/modules/comercial/domain/acoes-mensagem.ts.
create or replace function crm.mensagem_acao_motivo(m crm.mensagem, p_tipo text, p_eu uuid)
 returns text
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare n crm.numero_whatsapp%rowtype; c crm.config%rowtype;
begin
  if m.id is null or m.excluida_em is not null then return 'Mensagem não encontrada.'; end if;
  if m.direcao <> 'saida' then return 'Só dá para editar ou apagar mensagem enviada por nós.'; end if;
  if m.provedor <> 'evolution' then return 'O WhatsApp oficial não permite editar ou apagar mensagem enviada.'; end if;
  if m.apagada_em is not null then return 'Mensagem já apagada.'; end if;
  if m.externa or m.autor_id is null then
    if not coalesce(crm.eh_gestor(p_eu), false) then return 'Só quem enviou (ou o gestor) mexe nesta mensagem.'; end if;
  elsif m.autor_id is distinct from p_eu and not coalesce(crm.eh_gestor(p_eu), false) then
    return 'Só quem enviou (ou o gestor) mexe nesta mensagem.';
  end if;
  if m.status is null or m.status not in ('enviada', 'entregue', 'lida') or coalesce(m.provedor_msg_id, '') !~ ':' then
    return 'A mensagem ainda não saiu no WhatsApp.';
  end if;
  if p_tipo = 'editar' then
    if m.tipo <> 'texto' then return 'Só mensagem de texto pode ser editada.'; end if;
    if m.em < now() - interval '15 minutes' then return 'O WhatsApp só deixa editar até 15 minutos depois do envio.'; end if;
  elsif m.em < now() - interval '48 hours' then
    return 'O WhatsApp só deixa apagar para todos até 2 dias depois do envio.';
  end if;
  select * into c from crm.config;
  if not coalesce(c.evolution_ligado, false) or not coalesce(c.envio_ligado, false) then return 'Envio de WhatsApp desligado.'; end if;
  select * into n from crm.numero_whatsapp x where x.id = m.numero_id;
  if not found or not n.ativo or not n.envia then return 'Este número não envia pelo CRM.'; end if;
  if n.status <> 'conectado' then return 'Número desconectado: o gestor reconecta em Configurações.'; end if;
  if exists (select 1 from crm.mensagem_acao a where a.mensagem_id = m.id and a.status in ('na_fila', 'enviando')) then
    return 'Já há uma alteração desta mensagem a caminho do WhatsApp.';
  end if;
  return null;
end $function$;

create or replace function public.crm_mensagem_editar(p_mensagem uuid, p_texto text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; m crm.mensagem%rowtype; v_motivo text; v_texto text := btrim(coalesce(p_texto, '')); v_id uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or not crm.pode_escrever_pessoa(m.pessoa_id) then return crm.res(false, 'Mensagem não encontrada.'); end if;
  if v_texto = '' then return crm.res(false, 'Mensagem vazia.'); end if;
  if length(v_texto) > 4096 then return crm.res(false, 'Mensagem longa demais (máximo 4.096 caracteres).'); end if;
  v_motivo := crm.mensagem_acao_motivo(m, 'editar', v_eu);
  if v_motivo is not null then return crm.res(false, v_motivo); end if;
  if v_texto = m.texto then return crm.res(false, 'O texto não mudou.'); end if;
  insert into crm.mensagem_acao (mensagem_id, tipo, texto, autor_id) values (m.id, 'editar', v_texto, v_eu) returning id into v_id;
  perform crm.log_registrar('editou', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                            'Editou mensagem enviada para ' || crm.nome_pessoa(m.pessoa_id),
                            jsonb_build_object('acao_id', v_id, 'canal_id', m.numero_id, 'tamanho_antes', length(m.texto), 'tamanho_depois', length(v_texto)));
  perform crm.evolution_disparar_envio();
  return crm.res(true, 'Edição a caminho do WhatsApp.', jsonb_build_object('acaoId', v_id));
end $function$;

create or replace function public.crm_mensagem_apagar(p_mensagem uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; m crm.mensagem%rowtype; v_motivo text; v_id uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or not crm.pode_escrever_pessoa(m.pessoa_id) then return crm.res(false, 'Mensagem não encontrada.'); end if;
  v_motivo := crm.mensagem_acao_motivo(m, 'apagar', v_eu);
  if v_motivo is not null then return crm.res(false, v_motivo); end if;
  insert into crm.mensagem_acao (mensagem_id, tipo, autor_id) values (m.id, 'apagar', v_eu) returning id into v_id;
  perform crm.log_registrar('excluiu', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                            'Apagou para todos uma mensagem enviada para ' || crm.nome_pessoa(m.pessoa_id),
                            jsonb_build_object('acao_id', v_id, 'canal_id', m.numero_id));
  perform crm.evolution_disparar_envio();
  return crm.res(true, 'Apagando para todos no WhatsApp.', jsonb_build_object('acaoId', v_id));
end $function$;

-- ═══ e. Responder citando (só QR) ═══
create or replace function public.crm_responder_mensagem(p_citada uuid, p_texto text, p_chave uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_r jsonb; q crm.mensagem%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into q from crm.mensagem x where x.id = p_citada;
  if not found or q.excluida_em is not null or not crm.pode_escrever_pessoa(q.pessoa_id) then
    return crm.res(false, 'Mensagem não encontrada.');
  end if;
  if q.provedor <> 'evolution' then return crm.res(false, 'Responder citando só no número por QR.'); end if;
  if q.apagada_em is not null then return crm.res(false, 'Mensagem apagada não pode ser citada.'); end if;
  if coalesce(q.provedor_msg_id, '') !~ ':' then return crm.res(false, 'Esta mensagem ainda não tem identificação no WhatsApp.'); end if;
  v_r := public.crm_enviar_mensagem(q.pessoa_id, p_texto, null, null, null, p_chave, q.numero_id);
  if coalesce((v_r ->> 'ok')::boolean, false) and not coalesce((v_r ->> 'repetida')::boolean, false) then
    update crm.mensagem x set citada_id = q.id where x.id = (v_r ->> 'mensagemId')::uuid and x.status = 'na_fila';
  end if;
  return v_r;
end $function$;

-- ═══ f. Status do atendimento ═══
create or replace function public.crm_conversa_atendimento(p_pessoa uuid, p_estado text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_atual uuid; v_ids uuid[]; v_de text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_estado is null or p_estado not in ('aberto', 'espera', 'encerrado') then return crm.res(false, 'Status inválido.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
  select (array_agg(x.atendimento order by x.ultima_em desc nulls last))[1] into v_de
    from crm.conversa x where x.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.excluida_em is null;
  if v_de is null then return crm.res(false, 'Ainda não há conversa com este contato.'); end if;
  with u as (
    update crm.conversa x set atendimento = p_estado, atendimento_em = now(), atendimento_por = v_eu
     where x.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.excluida_em is null and x.atendimento <> p_estado
    returning x.id)
  select array_agg(u.id) into v_ids from u;
  if v_ids is null then return crm.res(true, 'Nada mudou.'); end if;
  perform crm.log_registrar('editou', 'conversa', v_ids[1]::text, v_atual,
                            format('Atendimento %s: %s', case p_estado when 'aberto' then 'reaberto' when 'espera' then 'em espera'
                                                              else 'encerrado' end, crm.nome_pessoa(v_atual)),
                            jsonb_build_object('de', v_de, 'para', p_estado, 'conversas', to_jsonb(v_ids)));
  return crm.res(true, case p_estado when 'aberto' then 'Atendimento reaberto.' when 'espera' then 'Conversa em espera.'
                                     else 'Atendimento encerrado.' end);
end $function$;

-- ═══ g. Mensagem agendada (mesma fila do envio) ═══
create or replace function public.crm_agendar_mensagem(p_pessoa uuid, p_texto text, p_enviar_em timestamptz,
                                                       p_canal uuid default null, p_template uuid default null, p_chave uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; n crm.numero_whatsapp%rowtype;
        t crm.template%rowtype; v_rend jsonb; v_texto text; v_tipo text := 'texto'; v_vars jsonb; v_conv uuid;
        cv crm.conversa%rowtype; v_id uuid := gen_random_uuid(); v_dup uuid; v_dup_autor uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_chave is not null then
    select m.id, m.autor_id into v_dup, v_dup_autor from crm.mensagem m where m.chave = p_chave;
    if v_dup is not null then
      if v_dup_autor is distinct from v_eu then return crm.res(false, 'Chave de envio inválida.'); end if;
      return crm.res(true, 'Mensagem já agendada.', jsonb_build_object('mensagemId', v_dup, 'repetida', true));
    end if;
  end if;
  if p_enviar_em is null then return crm.res(false, 'Escolha data e hora.'); end if;
  if p_enviar_em < now() + interval '1 minute' then return crm.res(false, 'Escolha um horário no futuro.'); end if;
  if p_enviar_em > now() + interval '30 days' then return crm.res(false, 'Agende para no máximo 30 dias.'); end if;
  select * into c from crm.config;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  if not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
  if crm.pessoa_optout(v_atual) then return crm.res(false, 'Contato pediu para não receber mensagens.'); end if;
  if (select count(*) from crm.mensagem x where x.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.agendada_para is not null
         and x.status = 'na_fila' and x.excluida_em is null) >= 10 then
    return crm.res(false, 'Este contato já tem 10 mensagens agendadas.');
  end if;
  if p_canal is not null then
    select * into n from crm.numero_whatsapp x where x.id = p_canal;
    if not found then return crm.res(false, 'Número de WhatsApp não encontrado.'); end if;
  else
    select x.* into n from crm.conversa k join crm.numero_whatsapp x on x.id = k.numero_id
     where k.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.ativo and k.excluida_em is null
     order by k.ultima_em desc nulls last, k.criado_em desc limit 1;
    if not found then select * into n from crm.numero_whatsapp x where x.id = c.whatsapp_numero_id; end if;
  end if;
  if n.id is null or not n.ativo then return crm.res(false, 'Número de envio não configurado.'); end if;
  if n.provedor = 'evolution' then
    if not coalesce(c.evolution_ligado, false) then return crm.res(false, 'WhatsApp por QR desligado.'); end if;
    if not n.envia then return crm.res(false, 'Este número não envia pelo CRM.'); end if;
    if p_template is not null then return crm.res(false, 'Template é só do número oficial. Neste número, escreva a mensagem.'); end if;
    if n.dono_id is not null and n.dono_id is distinct from v_eu and not coalesce(crm.eh_gestor(), false) then
      return crm.res(false, 'Este número é de outra pessoa.');
    end if;
  elsif not coalesce(c.whatsapp_ligado, false) then
    return crm.res(false, 'WhatsApp desligado.');
  end if;
  if p_template is null then
    if btrim(coalesce(p_texto, '')) = '' then return crm.res(false, 'Mensagem vazia.'); end if;
    if length(btrim(p_texto)) > 4096 then return crm.res(false, 'Mensagem longa demais (máximo 4.096 caracteres).'); end if;
  else
    select * into t from crm.template x where x.id = p_template;
    if not found or not t.aprovado or not t.ativo or t.categoria not in ('marketing', 'utility') then return crm.res(false, 'Template não aprovado.'); end if;
    if t.numero_id <> n.id then return crm.res(false, 'Template de outro número de envio.'); end if;
  end if;
  v_conv := crm.whatsapp_conversa_para(n.id, v_atual);
  if v_conv is null then return crm.res(false, 'Contato sem telefone de WhatsApp.'); end if;
  select * into cv from crm.conversa x where x.id = v_conv;
  if p_template is null then
    if n.provedor = 'infobip' and (cv.ultima_entrada_em is null or cv.ultima_entrada_em + interval '24 hours' <= p_enviar_em) then
      return crm.res(false, 'A janela de 24 h estará fechada nesse horário: agende um template aprovado ou escolha um horário antes.');
    end if;
    v_texto := btrim(p_texto);
  else
    v_rend := crm.template_render(t, v_atual, null);
    if not (v_rend ->> 'ok')::boolean then return crm.res(false, v_rend ->> 'msg'); end if;
    v_texto := v_rend ->> 'texto'; v_vars := v_rend -> 'vars'; v_tipo := 'template';
  end if;
  insert into crm.mensagem (id, conversa_id, numero_id, pessoa_id, direcao, tipo, texto, em, status, status_em, fila_em, autor_id,
                            template_id, template_vars, provedor, provedor_msg_id, chave, agendada_para)
  values (v_id, cv.id, n.id, cv.pessoa_id, 'saida', v_tipo, v_texto, p_enviar_em, 'na_fila', now(), p_enviar_em, v_eu,
          t.id, v_vars, n.provedor, case when n.provedor = 'infobip' then v_id::text end, p_chave, p_enviar_em);
  perform crm.log_registrar('agendou', 'mensagem', v_id::text, v_atual,
                            format('Agendou %s para %s em %s', case when v_tipo = 'template' then 'template ' || t.nome_provedor else 'mensagem' end,
                                   crm.nome_pessoa(v_atual), to_char(p_enviar_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')),
                            jsonb_build_object('conversa_id', cv.id, 'canal_id', n.id, 'enviar_em', p_enviar_em, 'template_id', t.id));
  return crm.res(true, 'Mensagem agendada.', jsonb_build_object('mensagemId', v_id, 'canalId', n.id));
exception
  when sqlstate 'P0001' then
    get stacked diagnostics v_m = message_text;
    return crm.res(false, v_m);
  when unique_violation or check_violation or foreign_key_violation or not_null_violation or invalid_text_representation
       or invalid_datetime_format or datetime_field_overflow or string_data_right_truncation or invalid_parameter_value then
    get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
    return crm.erro_dados(v_s, v_m, v_c);
end $function$;

create or replace function public.crm_cancelar_agendada(p_mensagem uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; m crm.mensagem%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or m.agendada_para is null or m.excluida_em is not null or not crm.pode_escrever_pessoa(m.pessoa_id) then
    return crm.res(false, 'Mensagem agendada não encontrada.');
  end if;
  if m.autor_id is distinct from v_eu and not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só quem agendou (ou o gestor) cancela.'); end if;
  if m.status <> 'na_fila' or m.fila_em <= now() then return crm.res(false, 'A mensagem já está saindo ou já saiu.'); end if;
  update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Agendamento cancelado.',
         excluida_em = now(), excluida_por = v_eu, excluida_motivo = 'Agendamento cancelado antes do envio.'
   where x.id = m.id;
  perform crm.log_registrar('excluiu', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                            'Cancelou mensagem agendada para ' || crm.nome_pessoa(m.pessoa_id),
                            jsonb_build_object('agendada_para', m.agendada_para));
  return crm.res(true, 'Agendamento cancelado.');
end $function$;

-- ═══ h. Contrato da Edge crm-evolution-enviar ═══
create or replace function crm.evolution_acoes_pegar(p_lote integer default 10)
 returns table(acao_id uuid, tipo text, instancia text, telefone text, key_id text, texto text)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c crm.config%rowtype; a record; v_erro text;
begin
  select * into c from crm.config;
  if not (coalesce(c.evolution_ligado, false) and coalesce(c.envio_ligado, false)) then return; end if;
  update crm.mensagem_acao x set status = 'falhou', status_em = now(), erro = 'Sem confirmação do WhatsApp: confira no celular.'
   where x.status = 'enviando' and x.status_em < now() - interval '5 minutes';
  for a in select x.id, x.tipo, x.texto, m.em, m.apagada_em, m.excluida_em, m.provedor_msg_id, cv.telefone,
                  n.instancia, n.ativo, n.envia, n.status n_status
             from crm.mensagem_acao x
             join crm.mensagem m on m.id = x.mensagem_id
             join crm.conversa cv on cv.id = m.conversa_id
             join crm.numero_whatsapp n on n.id = m.numero_id
            where x.status = 'na_fila'
            order by x.criado_em, x.id
            limit least(greatest(coalesce(p_lote, 10), 1), 30)
              for update of x skip locked loop
    v_erro := case when not a.ativo or not a.envia then 'Número não envia pelo CRM.'
                   when a.n_status <> 'conectado' then 'Número desconectado.'
                   when a.apagada_em is not null or a.excluida_em is not null then 'Mensagem já apagada.'
                   when coalesce(a.provedor_msg_id, '') !~ ':' then 'Mensagem sem identificação no WhatsApp.'
                   when a.tipo = 'editar' and a.em < now() - interval '15 minutes' then 'Passou dos 15 minutos para editar.'
                   when a.tipo = 'apagar' and a.em < now() - interval '48 hours' then 'Passou de 2 dias para apagar.' end;
    if v_erro is not null then
      update crm.mensagem_acao x set status = 'falhou', status_em = now(), erro = v_erro where x.id = a.id;
      continue;
    end if;
    update crm.mensagem_acao x set status = 'enviando', status_em = now(), tentativas = x.tentativas + 1 where x.id = a.id;
    acao_id := a.id; tipo := a.tipo; instancia := a.instancia; telefone := a.telefone;
    key_id := split_part(a.provedor_msg_id, ':', 2); texto := a.texto;
    return next;
  end loop;
end $function$;

create or replace function crm.evolution_acao_resultado(p_acao uuid, p_http integer, p_erro text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare a crm.mensagem_acao%rowtype;
begin
  select * into a from crm.mensagem_acao x where x.id = p_acao for update;
  if not found or a.status <> 'enviando' then return 'ignorado'; end if;
  if p_http between 200 and 299 then
    update crm.mensagem_acao x set status = 'feita', status_em = now(), erro = null where x.id = a.id;
    if a.tipo = 'editar' then
      update crm.mensagem x set texto = a.texto, editada_em = now() where x.id = a.mensagem_id;
    else
      update crm.mensagem x set apagada_em = now(), apagada_por = a.autor_id where x.id = a.mensagem_id and x.apagada_em is null;
    end if;
    return 'feita';
  end if;
  update crm.mensagem_acao x set status = 'falhou', status_em = now(),
         erro = left(coalesce(nullif(p_erro, ''), 'Evolution HTTP ' || coalesce(p_http, 0)), 300)
   where x.id = a.id;
  return 'falhou';
end $function$;

-- Citação: key.id e texto da mensagem citada (a Edge monta o "quoted" do sendText).
create or replace function crm.evolution_citacoes(p_ids uuid[])
 returns table(mensagem_id uuid, key_id text, from_me boolean, texto text)
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select m.id, split_part(q.provedor_msg_id, ':', 2), q.direcao = 'saida', left(q.texto, 1000)
    from crm.mensagem m join crm.mensagem q on q.id = m.citada_id
   where m.id = any(p_ids) and q.provedor = 'evolution' and q.provedor_msg_id ~ ':' and q.apagada_em is null;
$function$;

-- Edição/exclusão que chega pelo webhook (contato ou celular). Idempotente.
create or replace function crm.evolution_alteracao(p_canal uuid, e jsonb)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_inst text; m crm.mensagem%rowtype; v_texto text := left(btrim(coalesce(e ->> 'texto', '')), 4096);
begin
  select x.instancia into v_inst from crm.numero_whatsapp x where x.id = p_canal and x.provedor = 'evolution';
  if v_inst is null or coalesce(e ->> 'id', '') !~ '^[A-Za-z0-9_-]{4,120}$' then return 'ignorado'; end if;
  select * into m from crm.mensagem x where x.provedor = 'evolution' and x.provedor_msg_id = v_inst || ':' || (e ->> 'id') for update;
  if not found then return 'sem_mensagem'; end if;
  perform set_config('crm.canal', 'whatsapp', true);
  if e ->> 'evento' = 'revogacao' then
    if m.apagada_em is not null then return 'ja_apagada'; end if;
    update crm.mensagem x set apagada_em = now() where x.id = m.id;
    perform crm.log_registrar('excluiu', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                              case when m.direcao = 'entrada' then 'O contato apagou uma mensagem: ' else 'Mensagem apagada pelo celular: ' end
                              || crm.nome_pessoa(m.pessoa_id), jsonb_build_object('canal_id', m.numero_id));
    perform set_config('crm.canal', '', true);
    return 'apagada';
  elsif e ->> 'evento' = 'edicao' then
    if v_texto = '' or m.apagada_em is not null or v_texto = m.texto then perform set_config('crm.canal', '', true); return 'sem_mudanca'; end if;
    update crm.mensagem x set texto = v_texto, editada_em = now() where x.id = m.id;
    perform crm.log_registrar('editou', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                              case when m.direcao = 'entrada' then 'O contato editou uma mensagem: ' else 'Mensagem editada pelo celular: ' end
                              || crm.nome_pessoa(m.pessoa_id),
                              jsonb_build_object('canal_id', m.numero_id, 'tamanho_antes', length(m.texto), 'tamanho_depois', length(v_texto)));
    perform set_config('crm.canal', '', true);
    return 'editada';
  end if;
  return 'ignorado';
end $function$;

-- ═══ i. crm.evolution_webhook (corpo vivo c3526c98… + edicao/revogacao) ═══
create or replace function crm.evolution_webhook(p_canal uuid, p_eventos jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    elsif r ->> 'evento' in ('edicao', 'revogacao') then
      if v_lig then
        begin
          perform crm.evolution_alteracao(p_canal, r); n_proc := n_proc + 1;
        exception when others then
          n_err := n_err + 1; raise warning 'crm.evolution_webhook (alteracao): %', sqlstate;
        end;
      else
        n_ign := n_ign + 1;
      end if;
      continue;
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
    select m.id, m.conversa_id into v_m from crm.mensagem m
     where m.provedor = 'evolution' and m.provedor_msg_id = v_inst || ':' || (r ->> 'id') and m.midia_status = 'pendente';
    if found then
      v_midias := v_midias || jsonb_build_object('ref', v_ref, 'mensagemId', v_m.id, 'conversaId', v_m.conversa_id);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'recebidos', n_rec, 'novos', n_novo, 'duplicados', n_dup, 'ignorados', n_ign,
                            'processados', n_proc, 'erros', n_err, 'ligado', v_lig, 'midias', v_midias);
end $function$;

-- ═══ i. crm.evolution_fila_tem (corpo vivo fff49656… + ações pendentes) ═══
create or replace function crm.evolution_fila_tem()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce((select c.evolution_ligado from crm.config c), false)
     and (exists (select 1 from crm.integracao_evento x where x.fonte = 'evolution' and x.processado_em is null and x.tentativas < 5)
          or (coalesce((select c.envio_ligado from crm.config c), false)
              and (exists (select 1 from crm.mensagem m where m.status = 'na_fila' and m.provedor = 'evolution' and m.fila_em <= now()
                              and coalesce(m.proxima_tentativa_em, m.fila_em) <= now())
                   or exists (select 1 from crm.mensagem m where m.status = 'enviando' and m.provedor = 'evolution'
                                and m.status_em < now() - interval '5 minutes')
                   or exists (select 1 from crm.mensagem_acao a where a.status = 'na_fila')
                   or exists (select 1 from crm.mensagem_acao a where a.status = 'enviando' and a.status_em < now() - interval '5 minutes')))
          or exists (select 1 from crm.mensagem m where m.midia_status = 'pendente' and m.provedor = 'evolution'
                       and m.midia_proxima_em < now() - interval '15 minutes'));
$function$;

-- ═══ Permissões ═══
revoke all on function crm.tg_mensagem_reabre() from public, anon, authenticated;
revoke all on function crm.tg_mensagem_agendada() from public, anon, authenticated;
revoke all on function crm.mensagem_acao_motivo(crm.mensagem, text, uuid) from public, anon, authenticated;
revoke all on function crm.evolution_acoes_pegar(integer) from public, anon, authenticated;
revoke all on function crm.evolution_acao_resultado(uuid, integer, text) from public, anon, authenticated;
revoke all on function crm.evolution_citacoes(uuid[]) from public, anon, authenticated;
revoke all on function crm.evolution_alteracao(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.crm_mensagem_editar(uuid, text) from public, anon;
revoke all on function public.crm_mensagem_apagar(uuid) from public, anon;
revoke all on function public.crm_responder_mensagem(uuid, text, uuid) from public, anon;
revoke all on function public.crm_conversa_atendimento(uuid, text) from public, anon;
revoke all on function public.crm_agendar_mensagem(uuid, text, timestamptz, uuid, uuid, uuid) from public, anon;
revoke all on function public.crm_cancelar_agendada(uuid) from public, anon;
grant execute on function public.crm_mensagem_editar(uuid, text) to authenticated;
grant execute on function public.crm_mensagem_apagar(uuid) to authenticated;
grant execute on function public.crm_responder_mensagem(uuid, text, uuid) to authenticated;
grant execute on function public.crm_conversa_atendimento(uuid, text) to authenticated;
grant execute on function public.crm_agendar_mensagem(uuid, text, timestamptz, uuid, uuid, uuid) to authenticated;
grant execute on function public.crm_cancelar_agendada(uuid) to authenticated;
