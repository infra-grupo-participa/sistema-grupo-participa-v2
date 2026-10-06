-- 20261006b: F4 do Comercial — WhatsApp oficial via Infobip (conversa, mensagem, template, fichas de disparo, fila de envio)
--
-- STATUS: APLICADA em produção em 06/10/2026 — versão 20261006051434 (nome crm_f4_whatsapp) em
-- supabase_migrations.schema_migrations; md5 do texto gravado = 6a742af713d6b48908be7785a4b0e764 (= este arquivo antes
-- desta troca de STATUS, que mexe só nestas 4 linhas de comentário). Ensaio final do texto exato, sobre F2/F3/F5/F6/F7
-- aplicadas: 20261006051434_ensaio.sql. Tudo desligado (whatsapp/envio/escrita = false). Provas: 20261006051434.explain.md.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §3.6, §3.7, §5 (5.4), §6 (F4). Contrato: web/modules/comercial/
-- application/ports.ts (conversas, mensagens, templates, fichas, enviarMensagem, marcarConversaLida, salvarFicha,
-- decidirFicha) e domain/types.ts (Conversa, Mensagem, Template, FichaDisparo). Mensagens = mock-comercial.repository.ts.
--
-- O QUE FAZ
--   1. Tabelas (schema crm, NÃO exposto): numero_whatsapp, template, conversa (1 por número × telefone), mensagem (é também
--      a FILA de saída: status na_fila → enviando → enviada → entregue → lida | falhou), supressao (opt-out por canal),
--      ficha_disparo, ficha_destinatario, integracao_evento (bruto idempotente de webhook, comum às integrações).
--   2. crm.config ganha: envio_ligado (kill-switch do ENVIO à Infobip, nasce false), whatsapp_numero_id (número de envio:
--      o que termina em 7717946 — cadastrado pelo Arthur, NÃO há número no código), infobip_base_url, envio_lote,
--      envio_validade_min, disparo_validade_min, disparo_max_destinatarios, optout_palavras.
--      whatsapp_ligado (F0) continua sendo o interruptor geral (webhook processa, tela enfileira).
--   3. Entrada (Edge crm-whatsapp-webhook → crm.whatsapp_webhook): só aceita o que é NOSSO (mensagem para número
--      cadastrado; status/visto de mensagem que nós enviamos); grava o bruto em crm.integracao_evento com chave única
--      (reenvio da Infobip = no-op); processa no banco (pessoa por telefone via pessoas.registrar — nunca funde por nome;
--      conversa; mensagem; janela de 24 h; opt-out por palavra; aviso lead_respondeu ao dono). Status fora de ordem não
--      regride (rank + greatest). Com whatsapp_ligado=false o bruto fica guardado e processa depois (whatsapp_reprocessar).
--   4. Saída: RPC enfileira (crm_enviar_mensagem) → cron SQL decide se há fila (crm.whatsapp_fila_tem) → ops.cron_post chama
--      a Edge crm-whatsapp-enviar → crm.whatsapp_fila_pegar (revalida opt-out, janela 24 h, template aprovado, número ativo,
--      validade na fila; trava com SKIP LOCKED) → Infobip → crm.whatsapp_fila_resultado. O id da Infobip É o nosso id
--      (messageId = crm.mensagem.id): relatório de entrega casa mesmo se a resposta HTTP se perder. HTTP 200 ≠ entregue:
--      "enviada" = aceita pelo provedor; "entregue"/"lida" só pelo relatório. Sem resposta → falhou com falha_incerta (nunca
--      reenvia sozinho; relatório posterior corrige). 429 → volta para a fila com espera.
--   5. Fichas: crm_salvar_ficha (vendedor com dispara_api ou gestor; lista de destinatários no banco, supressões calculadas no
--      banco na ordem do domínio: opt_out, ja_comprou, em_negociacao, disparo_48h) → vendedor = aguardando_aprovacao + aviso
--      ao gestor; gestor = aprovada. crm_decidir_ficha (só gestor; aprova, reprova ou cancela aprovada antes do disparo).
--      Na hora agendada, crm.fichas_liberar (chamada pela fila) recalcula as supressões e enfileira 1 template por elegível.
--   6. RPCs de LEITURA: crm_conversas, crm_mensagens, crm_templates (invoker + RLS), crm_fichas, crm_whatsapp_status
--      (definer com guarda). ESCRITA (definer, guarda escrita_ligada + papel, {ok,msg}, log): crm_enviar_mensagem,
--      crm_marcar_conversa_lida, crm_salvar_ficha, crm_decidir_ficha.
--   7. Segredos SÓ no Vault (nomes; nenhum valor aqui): infobip_api_key, crm_whatsapp_webhook_chave, crm_whatsapp_envio_chave.
--      Lidos por crm.whatsapp_chave_webhook() / crm.whatsapp_credenciais_envio(), executáveis só pelo dono (postgres = a Edge
--      via SUPABASE_DB_URL). Nenhum cron é agendado aqui (bloco LIGAR no fim).
--
-- AS 5 PERGUNTAS (números em 20261006b.explain.md)
--   escala: entrada/saída por mensagem (índices únicos (provedor, provedor_msg_id) e (numero_id, telefone)). Leituras com
--     limite (conversas ≤ 1.000, mensagens ≤ 1.000, fichas ≤ 500). Ficha ≤ disparo_max_destinatarios (2.000): supressão por
--     pessoa, medida com massa sintética 10× no ensaio.
--   índice: mensagem_fila_idx (parcial na_fila) para a fila; mensagem_pessoa_idx p/ conversa e 48 h; conversa_ultima_idx p/
--     a lista; hotmart_transacoes_email_idx (forma canônica por conta) p/ "já comprou".
--   frequência: webhook = 1 chamada por lote da Infobip; cron SQL 1/min SÓ decide (HTTP só quando há fila); templates 1/dia.
--   repetição: crm_conversas traz última mensagem + não lidas + janela + dono numa chamada.
--   reversão: envio_ligado=false para o envio em ~10 s (fila espera, depois expira); whatsapp_ligado=false para tudo
--     (webhook guarda bruto sem processar); bloco REVERSÃO no fim.
--
-- PREMISSAS (guarda aborta): F2 aplicada (crm.guarda_escrita, crm.garantir_pc, crm.pode_escrever_pessoa, crm_mover_etapa…);
--   F4 não aplicada; crm.config sem envio_ligado e com whatsapp_ligado=false; crm.log aceita entidade mensagem/ficha;
--   pessoas.registrar/chave_telefone/dados, mkt.sem_acento; colunas de fin.hotmart_transacoes e índice de e-mail; Vault.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  select string_agg(f, ', ') into v_falta
    from unnest(array['crm.guarda_escrita()', 'crm.garantir_pc(uuid)', 'crm.pode_escrever_pessoa(uuid)', 'crm.res(boolean,text,jsonb)',
                      'crm.erro_dados(text,text,text)', 'crm.uuid_ou_null(text)', 'crm.nome_pessoa(uuid)',
                      'public.crm_mover_etapa(uuid,uuid)', 'public.crm_atribuir_contato(uuid,uuid,text)',
                      'crm.pode_ver_pessoa(uuid)', 'crm.atual_de(uuid[])', 'crm.pessoa_grupo(uuid)', 'crm.exige_comercial()',
                      'crm.tg_log()', 'pessoas.registrar(jsonb,text,uuid)', 'pessoas.atual(uuid)', 'pessoas.grupo(uuid)',
                      'pessoas.dados(uuid)', 'pessoas.chave_telefone(text)', 'pessoas.norm_email(text)', 'pessoas.so_digitos(text)',
                      'mkt.sem_acento(text)']) f
   where to_regprocedure(f) is null;
  if v_falta is not null then raise exception '20261006b: F2/F0 não aplicadas (faltam: %)', v_falta; end if;
  if to_regclass('crm.mensagem') is not null or to_regclass('crm.numero_whatsapp') is not null
     or to_regclass('crm.integracao_evento') is not null or to_regclass('crm.ficha_disparo') is not null then
    raise exception '20261006b: tabelas da F4 já existem (migration já aplicada?)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'envio_ligado') then
    raise exception '20261006b: crm.config já tem envio_ligado';
  end if;
  if coalesce((select c.whatsapp_ligado from crm.config c), true) then
    raise exception '20261006b: crm.config.whatsapp_ligado deveria estar false';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'crm.log'::regclass and contype = 'c'
                    and pg_get_constraintdef(oid) like '%''mensagem''%' and pg_get_constraintdef(oid) like '%''ficha''%') then
    raise exception '20261006b: crm.log não aceita entidade mensagem/ficha';
  end if;
  select string_agg(c, ', ') into v_falta
    from unnest(array['conta', 'status', 'produto_id', 'comprador_email']) c
   where not exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'hotmart_transacoes' and column_name = c);
  if v_falta is not null then raise exception '20261006b: fin.hotmart_transacoes sem: %', v_falta; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'fin' and indexname = 'hotmart_transacoes_email_idx'
                    and indexdef like '%lower(TRIM(BOTH FROM comprador_email))%') then
    raise exception '20261006b: índice fin.hotmart_transacoes_email_idx ausente ou com outra expressão';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then raise exception '20261006b: Vault ausente'; end if;
end
$guarda$;

-- ─── 1. Número, template, configuração ───────────────────────────────────────────────────────────────────────────────
create table crm.numero_whatsapp (
  id        uuid primary key default gen_random_uuid(),
  provedor  text not null default 'infobip' check (provedor in ('infobip')),
  numero    text not null unique check (numero ~ '^[0-9]{10,15}$'),        -- E.164 sem "+" (o "from" da Infobip)
  nome      text not null check (length(btrim(nome)) between 1 and 80),
  ativo     boolean not null default true,                                  -- inativar, nunca apagar
  criado_em timestamptz not null default now()
);

create table crm.template (
  id              uuid primary key default gen_random_uuid(),
  provedor        text not null default 'infobip' check (provedor in ('infobip')),
  numero_id       uuid not null references crm.numero_whatsapp(id) on delete restrict,   -- template é do remetente (WABA)
  nome_provedor   text not null check (length(nome_provedor) between 1 and 512),
  idioma          text not null default 'pt_BR' check (idioma ~ '^[a-z]{2,3}(_[A-Z]{2})?$'),
  categoria       text not null check (categoria in ('marketing', 'utility', 'authentication')),
  texto           text not null check (length(texto) between 1 and 4096),
  variaveis       smallint not null default 0 check (variaveis between 0 and 20),
  aprovado        boolean not null default false,                          -- status APPROVED na Infobip/Meta
  status_provedor text check (status_provedor is null or length(status_provedor) <= 40),
  ativo           boolean not null default true,                           -- sumiu da Infobip = inativo (nunca apagado)
  sincronizado_em timestamptz not null default now(),
  unique (numero_id, nome_provedor, idioma)
);

alter table crm.config
  add column envio_ligado              boolean not null default false,
  add column whatsapp_numero_id        uuid references crm.numero_whatsapp(id) on delete restrict,
  add column infobip_base_url          text not null default 'https://8k6q23.api-us.infobip.com'
    check (infobip_base_url ~ '^https://[a-z0-9]+\.api(-[a-z]+)?\.infobip\.com$'),
  add column envio_lote                smallint not null default 60 check (envio_lote between 1 and 200),
  add column envio_validade_min        smallint not null default 30 check (envio_validade_min between 1 and 1440),
  add column disparo_validade_min      smallint not null default 720 check (disparo_validade_min between 10 and 2880),
  add column disparo_max_destinatarios int not null default 2000 check (disparo_max_destinatarios between 1 and 20000),
  add column optout_palavras           text[] not null default array['SAIR', 'PARAR', 'STOP', 'CANCELAR', 'DESCADASTRAR']
    check (cardinality(optout_palavras) between 1 and 30);

-- ─── 2. Fichas de disparo ────────────────────────────────────────────────────────────────────────────────────────────
create table crm.ficha_disparo (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique check (codigo ~ '^[A-Z0-9]+-[0-9]{8}-[0-9]{2}$'),   -- = template, log, utm_content
  objetivo      text not null check (length(btrim(objetivo)) between 1 and 300),
  linha         text not null references crm.linha(chave) on delete restrict,
  filtro        text not null check (length(btrim(filtro)) between 1 and 500),
  supressoes    text[] not null default array['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou']
    check (supressoes <@ array['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou']),
  quantidade    int not null default 0 check (quantidade >= 0),
  suprimidos    int not null default 0 check (suprimidos between 0 and quantidade),
  template_id   uuid not null references crm.template(id) on delete restrict,
  numero_id     uuid not null references crm.numero_whatsapp(id) on delete restrict,
  agendado_para timestamptz not null,
  operador_id   uuid not null references public.perfis(id) on delete restrict,
  link          text not null check (link ~ '^https://[^[:space:]]+$' and length(link) <= 1000),
  status        text not null default 'rascunho' check (status in ('rascunho', 'aguardando_aprovacao', 'aprovada', 'reprovada', 'enviada')),
  aprovado_por  uuid references public.perfis(id) on delete restrict,
  aprovado_em   timestamptz,
  decidido_por  uuid references public.perfis(id) on delete restrict,   -- quem aprovou/reprovou/cancelou
  decidido_em   timestamptz,
  motivo_status text check (motivo_status is null or length(motivo_status) <= 300),   -- reprovação automática na liberação
  enviada_em    timestamptz,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (status not in ('aprovada', 'enviada') or aprovado_por is not null),
  check ((status = 'enviada') = (enviada_em is not null))
);
create index ficha_criado_idx on crm.ficha_disparo (criado_em desc);
create index ficha_agendada_idx on crm.ficha_disparo (agendado_para) where status = 'aprovada';

create table crm.ficha_destinatario (
  ficha_id      uuid not null references crm.ficha_disparo(id) on delete restrict,
  pessoa_id     uuid not null references pessoas.pessoas(id) on delete restrict,   -- pessoa atual na hora de montar a lista
  suprimido_por text check (suprimido_por in ('em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou', 'sem_dados')),
  mensagem_id   uuid,                                                              -- FK abaixo (crm.mensagem)
  primary key (ficha_id, pessoa_id)
);
create index ficha_dest_pessoa_idx on crm.ficha_destinatario (pessoa_id);

-- ─── 3. Conversa e mensagem (mensagem = fila de saída) ──────────────────────────────────────────────────────────────
create table crm.conversa (
  id                 uuid primary key default gen_random_uuid(),
  numero_id          uuid not null references crm.numero_whatsapp(id) on delete restrict,
  telefone           text not null check (telefone ~ '^[0-9]{10,15}$'),            -- do lead, E.164 sem "+"
  pessoa_id          uuid not null references pessoas.pessoas(id) on delete restrict,   -- leitura resolve pessoas.atual
  nome_perfil        text check (nome_perfil is null or length(nome_perfil) <= 160),   -- nome do perfil no WhatsApp
  ultima_mensagem_id uuid,                                                      -- derivado (sem FK: atualizado junto)
  ultima_em          timestamptz,
  ultima_entrada_em  timestamptz,                                               -- janela de 24 h = isto + 24 h
  nao_lidas          int not null default 0 check (nao_lidas >= 0),
  criado_em          timestamptz not null default now(),
  unique (numero_id, telefone)
);
create index conversa_pessoa_idx on crm.conversa (pessoa_id);
create index conversa_ultima_idx on crm.conversa (ultima_em desc) where ultima_mensagem_id is not null;

create table crm.mensagem (
  id                   uuid primary key default gen_random_uuid(),
  conversa_id          uuid not null references crm.conversa(id) on delete restrict,
  pessoa_id            uuid not null references pessoas.pessoas(id) on delete restrict,   -- = conversa.pessoa_id na gravação
  direcao              text not null check (direcao in ('entrada', 'saida')),
  tipo                 text not null default 'texto' check (tipo in ('texto', 'template', 'imagem', 'documento', 'audio', 'video',
                                                                       'localizacao', 'contato', 'botao', 'figurinha', 'outro')),
  texto                text not null check (length(texto) between 1 and 4096),
  midia_url            text check (midia_url is null or (midia_url ~ '^https://' and length(midia_url) <= 2000)),
  em                   timestamptz not null default now(),
  status               text check (status in ('na_fila', 'enviando', 'enviada', 'entregue', 'lida', 'falhou')),
  status_em            timestamptz,
  falha_incerta        boolean not null default false,     -- sem resposta do provedor: pode ter saído; relatório corrige
  erro                 text check (erro is null or length(erro) <= 300),
  tentativas           smallint not null default 0 check (tentativas between 0 and 20),
  fila_em              timestamptz,
  proxima_tentativa_em timestamptz,
  autor_id             uuid references public.perfis(id) on delete restrict,
  template_id          uuid references crm.template(id) on delete restrict,
  template_vars        jsonb check (template_vars is null or jsonb_typeof(template_vars) = 'array'),
  ficha_id             uuid references crm.ficha_disparo(id) on delete restrict,
  provedor             text not null default 'infobip' check (provedor in ('infobip')),
  provedor_msg_id      text check (provedor_msg_id is null or length(provedor_msg_id) <= 200),
  lida_em              timestamptz,                         -- entrada lida pela equipe
  unique (provedor, provedor_msg_id),                       -- idempotência do webhook; saída usa o próprio id
  check ((direcao = 'entrada') = (status is null)),
  check (direcao = 'entrada' or autor_id is not null or ficha_id is not null),
  check (tipo <> 'template' or template_id is not null),
  check (status is distinct from 'na_fila' or fila_em is not null)
);
create index mensagem_conversa_idx on crm.mensagem (conversa_id, em desc);
create index mensagem_pessoa_idx   on crm.mensagem (pessoa_id, em desc);
create index mensagem_fila_idx     on crm.mensagem (fila_em) where status = 'na_fila';
create index mensagem_enviando_idx on crm.mensagem (status_em) where status = 'enviando';
create index mensagem_ficha_idx    on crm.mensagem (ficha_id) where ficha_id is not null;
create index mensagem_nao_lida_idx on crm.mensagem (conversa_id) where direcao = 'entrada' and lida_em is null;

alter table crm.ficha_destinatario
  add constraint ficha_destinatario_mensagem_fk foreign key (mensagem_id) references crm.mensagem(id) on delete restrict;

-- opt-out por canal (tipo e = e-mail normalizado, f = controle.fone_key)
create table crm.supressao (
  tipo   char(1) not null check (tipo in ('e', 'f')),
  valor  text not null check (length(valor) between 1 and 320),
  canal  text not null check (canal in ('todos', 'whatsapp', 'email')),
  motivo text not null check (length(motivo) between 1 and 200),
  origem text not null check (origem in ('whatsapp_stop', 'activecampaign', 'motivo_perda', 'gestor')),
  em     timestamptz not null default now(),
  primary key (tipo, valor, canal)
);

-- evento bruto de webhook (comum às integrações; F5 reaproveita). Só entra o que é do Comercial.
create table crm.integracao_evento (
  id              bigint generated always as identity primary key,
  fonte           text not null check (fonte in ('infobip', 'unnichat', 'manychat', 'activecampaign', 'respondi', 'sendflow', 'clint', 'slack')),
  tipo            text not null check (length(tipo) between 1 and 40),
  fonte_evento_id text not null check (length(fonte_evento_id) between 1 and 300),
  recebido_em     timestamptz not null default now(),
  payload         jsonb not null check (length(payload::text) <= 200000),
  processado_em   timestamptz,
  tentativas      smallint not null default 0,
  resultado       text check (resultado is null or length(resultado) <= 300),
  unique (fonte, fonte_evento_id)
);
create index integracao_pendente_idx on crm.integracao_evento (id) where processado_em is null;

-- log (crm.tg_log da F0) na ficha: cada mudança com resumo e diff. Mensagem NÃO tem trigger de log (entrada e status são
-- volume de integração): o envio pela tela grava 'enviou' explícito (crm.log_registrar).
create trigger ficha_disparo_log_ins_del after insert or delete on crm.ficha_disparo for each row execute function crm.tg_log('ficha', 'id');
create trigger ficha_disparo_log_upd after update on crm.ficha_disparo for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('ficha', 'id');

-- ─── 4. Helpers internos (sem grant: só as RPCs definer e a Edge, como postgres) ────────────────────────────────────
create function crm.log_registrar(p_acao text, p_entidade text, p_entidade_id text, p_pessoa uuid, p_resumo text,
                                  p_dados jsonb default '{}') returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_autor uuid := coalesce(auth.uid(), nullif(current_setting('crm.autor', true), '')::uuid);
  -- mesma regra de canal do crm.tg_log VIVO (recriado pela F7: MCP vem do claim gp_canal do JWT)
  v_canal text := coalesce(nullif(current_setting('crm.canal', true), ''),
                           case when auth.uid() is not null and (auth.jwt() ->> 'gp_canal') = 'mcp' then 'mcp' end,
                           case when auth.uid() is null then 'sistema' else 'tela' end);
begin
  insert into crm.log (autor_id, autor_tipo, canal, acao, entidade, entidade_id, pessoa_id, resumo, dados)
  values (v_autor,
          case when v_canal = 'mcp' then 'mcp' when v_autor is not null then 'pessoa'
               when v_canal in ('hotmart', 'whatsapp', 'activecampaign', 'sendflow', 'respondi', 'clint_import') then 'integracao'
               else 'sistema' end,
          v_canal, p_acao, p_entidade, p_entidade_id, p_pessoa, p_resumo, coalesce(p_dados, '{}'::jsonb));
end
$$;

-- horário da Infobip ("2026-10-06T13:48:28.743+0000"); inválido ou no futuro = agora
create function crm.ts_ou_agora(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
begin
  return least(coalesce(p::timestamptz, now()), now());
exception when others then
  return now();
end
$$;

create function crm.status_rank(p text) returns int
language sql immutable set search_path = '' as $$
  select case p when 'na_fila' then 0 when 'enviando' then 1 when 'enviada' then 2 when 'entregue' then 3 when 'lida' then 4
                when 'falhou' then 9 else -1 end;
$$;

-- Mensagem no formato do front (types.ts Mensagem). status do front: entrada → null (não lida) | 'lida';
-- saída na fila/enviando → null + "envio" (o tipo do front não tem estado de fila: ver explain, Integração no front).
create function crm.mensagem_json(m crm.mensagem, p_contato uuid) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id);
$$;

-- Grupo da pessoa (atual + aliases) sem a recursão quando ninguém aponta para ela (o caso comum): 1 lookup no índice
-- parcial pessoas_mesclada_idx. Igual a pessoas.grupo(pessoas.atual(p)) em resultado (medido no ensaio: a recursão por
-- pessoa era o custo dominante de uma ficha de 2.000).
create function crm.grupo_rapido(p_pessoa uuid) returns uuid[]
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := pessoas.atual(p_pessoa);
begin
  if v is null then return '{}'::uuid[]; end if;
  if exists (select 1 from pessoas.pessoas x where x.mesclada_em = v) then return pessoas.grupo(v); end if;
  return array[v];
end
$$;

-- Chaves de contato do GRUPO da pessoa (para opt-out e "já comprou"): grupo, telefones (fone_key) e e-mails normalizados.
-- SEM pessoas.dados (medido no ensaio: com dados + grupo repetidos, 2.000 destinatários estouravam 20 s). Uma consulta,
-- tudo por PK/índice: identificadores (pessoa_id, tipo, chave), pessoas.pessoas PK, thb_alunos PK, compradores PK, conversa_pessoa_idx.
create function crm.chaves_contato(p_pessoa uuid, out g uuid[], out fks text[], out emails text[])
language plpgsql stable security definer set search_path = '' as $$
begin
  g := crm.grupo_rapido(p_pessoa);
  select coalesce(array_agg(distinct x.fk) filter (where x.fk is not null), '{}'::text[]),
         coalesce(array_agg(distinct x.em) filter (where x.em is not null), '{}'::text[])
    into fks, emails
    from (select case when i.tipo = 'telefone' then i.chave end fk, case when i.tipo = 'email' then i.chave end em
            from pessoas.identificadores i where i.pessoa_id = any(g) and i.tipo in ('telefone', 'email')
          union all
          select pessoas.chave_telefone(coalesce(a.telefone_e164, a.telefone)), pessoas.norm_email(a.email)
            from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(g)
          union all
          select pessoas.chave_telefone((c.telefone)::text), pessoas.norm_email((c.email)::text)
            from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id where p.id = any(g)
          union all
          select pessoas.chave_telefone(cv.telefone), null from crm.conversa cv where cv.pessoa_id = any(g)) x;
end
$$;

create function crm.optout_chaves(p_g uuid[], p_fks text[], p_emails text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(p_g) and pc.opt_out)
              or exists (select 1 from crm.supressao s where s.tipo = 'f' and s.canal in ('todos', 'whatsapp') and s.valor = any(p_fks))
              or exists (select 1 from crm.supressao s where s.tipo = 'e' and s.canal = 'todos' and s.valor = any(p_emails)), false);
$$;

create function crm.pessoa_optout(p_pessoa uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare k record;
begin
  select * into k from crm.chaves_contato(p_pessoa);
  return crm.optout_chaves(k.g, k.fks, k.emails);
end
$$;

-- Supressão de disparo = motivoSupressao do domínio (regras.ts), na MESMA ordem: opt_out, ja_comprou, em_negociacao,
-- disparo_48h. null = elegível. "Já comprou" = negócio ganho (não reembolsado) na linha OU transação aprovada na Hotmart de
-- produto vinculado à linha (pelos e-mails do grupo; as duas contas na forma canônica de fin.trava_conta_hotmart).
create function crm.supressao_motivo(p_pessoa uuid, p_linha text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare k record;
begin
  select * into k from crm.chaves_contato(p_pessoa);    -- 1 vez por pessoa (grupo + chaves)
  if crm.optout_chaves(k.g, k.fks, k.emails) then return 'opt_out'; end if;
  if exists (select 1 from crm.negocio n where n.pessoa_id = any(k.g) and n.linha = p_linha and n.status = 'ganho' and n.reembolsado_em is null) then
    return 'ja_comprou';
  end if;
  if cardinality(k.emails) > 0 and exists (
       select 1
         from (select * from fin.hotmart_transacoes where conta = 'academy'
               union all
               select * from fin.hotmart_transacoes where conta = 'escritorio') h
         join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = p_linha
        where lower(btrim(h.comprador_email)) = any(k.emails) and h.status in ('APPROVED', 'COMPLETE')) then
    return 'ja_comprou';
  end if;
  if exists (select 1 from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
              where n.pessoa_id = any(k.g) and n.status = 'aberto' and e.papel in ('negociar', 'aguardar_pagamento')) then
    return 'em_negociacao';
  end if;
  if exists (select 1 from crm.mensagem m
              where m.pessoa_id = any(k.g) and m.direcao = 'saida' and m.ficha_id is not null
                and m.em > now() - interval '48 hours' and m.status is distinct from 'falhou') then
    return 'disparo_48h';
  end if;
  return null;
end
$$;

-- Texto e variáveis do template. Regra (decisão D-F4-3): {{1}} = primeiro nome do contato; {{2}} = link da ficha (só em
-- ficha). Mais variáveis = não suportado (recusa, nunca manda placeholder vazio).
create function crm.template_render(t crm.template, p_pessoa uuid, p_link text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_nome text; v_vars jsonb := '[]'::jsonb; v_texto text := t.texto; v_g uuid[]; v_atual uuid;
begin
  if t.variaveis > 2 then return jsonb_build_object('ok', false, 'msg', 'Template com mais de 2 variáveis ainda não é suportado.'); end if;
  if t.variaveis >= 1 then
    v_atual := pessoas.atual(p_pessoa); v_g := crm.grupo_rapido(p_pessoa);
    -- nome na mesma precedência de pessoas.dados (aluno, comprador, informado), sem a função inteira (custo por destinatário)
    select initcap(split_part(btrim(coalesce(a.nome, c.nome::text, p.nome)), ' ', 1)) into v_nome
      from pessoas.pessoas p
      left join public.thb_alunos a on a.id = p.aluno_id
      left join public.compradores c on c.id = p.comprador_id
     where p.id = any(v_g) and coalesce(a.nome, c.nome::text, p.nome) is not null
     order by p.id = v_atual desc, p.criado_em limit 1;
    if coalesce(length(v_nome), 0) < 2 then
      v_nome := (select initcap(split_part(btrim(c.nome_perfil), ' ', 1)) from crm.conversa c
                  where c.pessoa_id = any(v_g) and c.nome_perfil is not null
                  order by c.ultima_em desc nulls last limit 1);
    end if;
    if coalesce(length(v_nome), 0) < 2 then return jsonb_build_object('ok', false, 'msg', 'Contato sem nome: o template precisa do primeiro nome.'); end if;
    v_vars := jsonb_build_array(v_nome);
    v_texto := replace(v_texto, '{{1}}', v_nome);
  end if;
  if t.variaveis = 2 then
    if p_link is null then return jsonb_build_object('ok', false, 'msg', 'Template com link: use numa ficha de disparo.'); end if;
    v_vars := v_vars || jsonb_build_array(p_link);
    v_texto := replace(v_texto, '{{2}}', p_link);
  end if;
  return jsonb_build_object('ok', true, 'texto', left(v_texto, 4096), 'vars', v_vars);
end
$$;

-- Conversa de envio da pessoa no número: a mais recente do grupo; senão cria pelo telefone da pessoa (pessoas.dados,
-- BR normalizado → 55 + DDD + número). null = sem telefone.
create function crm.whatsapp_conversa_para(p_numero uuid, p_pessoa uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_atual uuid := pessoas.atual(p_pessoa); v_g uuid[] := crm.grupo_rapido(p_pessoa); v uuid; v_tel text;
begin
  select c.id into v from crm.conversa c
   where c.numero_id = p_numero and c.pessoa_id = any(v_g)
   order by c.ultima_em desc nulls last, c.criado_em desc limit 1;
  if v is not null then return v; end if;
  -- telefone na precedência de pessoas.dados (aluno, comprador, informado mais recente), por PK/índice
  v_tel := '55' || coalesce(
    (select pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone)) from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
      where p.id = any(v_g) and pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone)) is not null order by p.id = v_atual desc limit 1),
    (select pessoas.norm_telefone((c.telefone)::text) from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
      where p.id = any(v_g) and pessoas.norm_telefone((c.telefone)::text) is not null order by p.id = v_atual desc limit 1),
    (select pessoas.norm_telefone(i.valor) from pessoas.identificadores i
      where i.pessoa_id = any(v_g) and i.tipo = 'telefone' and pessoas.norm_telefone(i.valor) is not null order by i.id desc limit 1));
  if v_tel is null or v_tel !~ '^[0-9]{12,13}$' then return null; end if;
  insert into crm.conversa (numero_id, telefone, pessoa_id) values (p_numero, v_tel, v_atual)
  on conflict (numero_id, telefone) do nothing returning id into v;
  if v is null then select c.id into v from crm.conversa c where c.numero_id = p_numero and c.telefone = v_tel; end if;
  return v;
end
$$;

-- Destinatários da ficha: recalcula a supressão de quem ainda não recebeu. Devolve (quantidade, suprimidos).
create function crm.ficha_calcular(p_ficha uuid, p_linha text, out quantidade int, out suprimidos int)
language plpgsql security definer set search_path = '' as $$
begin
  update crm.ficha_destinatario d set suprimido_por = s.m
    from (select d2.pessoa_id, crm.supressao_motivo(d2.pessoa_id, p_linha) m
            from crm.ficha_destinatario d2 where d2.ficha_id = p_ficha and d2.mensagem_id is null) s
   where d.ficha_id = p_ficha and d.pessoa_id = s.pessoa_id and d.suprimido_por is distinct from s.m;
  select count(*), count(*) filter (where d.suprimido_por is not null) into quantidade, suprimidos
    from crm.ficha_destinatario d where d.ficha_id = p_ficha;
end
$$;

-- Código da ficha = mock: LINHA-AAAAMMDD-NN (dia de Brasília), sob trava do prefixo.
create function crm.ficha_codigo(p_linha text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_pref text; v_n int;
begin
  v_pref := upper(regexp_replace(p_linha, '[^a-z0-9]', '', 'g')) || '-'
            || to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD') || '-';
  perform pg_advisory_xact_lock(hashtext('crm.ficha_codigo:' || v_pref));
  select coalesce(max(substr(f.codigo, length(v_pref) + 1)::int), 0) + 1 into v_n
    from crm.ficha_disparo f where f.codigo like v_pref || '%';
  if v_n > 99 then raise exception 'Limite de 99 fichas por produto no dia.' using errcode = 'P0001'; end if;
  return v_pref || lpad(v_n::text, 2, '0');
end
$$;

-- Segredos (Vault). Só o dono (postgres) executa: a Edge conecta com SUPABASE_DB_URL. Nada de valor no repositório.
create function crm.whatsapp_chave_webhook() returns text
language sql stable security definer set search_path = '' as $$
  select (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'crm_whatsapp_webhook_chave');
$$;
create function crm.whatsapp_credenciais_envio(out api_key text, out chave_envio text, out base_url text, out remetente text)
language sql stable security definer set search_path = '' as $$
  select (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'infobip_api_key'),
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'crm_whatsapp_envio_chave'),
         c.infobip_base_url,
         (select n.numero from crm.numero_whatsapp n where n.id = c.whatsapp_numero_id and n.ativo)
    from crm.config c;
$$;

-- ─── 5. Entrada: webhook da Infobip (mensagem recebida, relatório de entrega, visto) ─────────────────────────────────
create function crm.whatsapp_entrada(e jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_para text := pessoas.so_digitos(e ->> 'to');
  v_de   text := pessoas.so_digitos(e ->> 'from');
  v_mid  text := e ->> 'messageId';
  v_m    jsonb := coalesce(e -> 'message', '{}'::jsonb);
  v_tp   text := upper(coalesce(v_m ->> 'type', 'TEXT'));
  v_num  crm.numero_whatsapp%rowtype; v_conv crm.conversa%rowtype; c crm.config%rowtype;
  v_reg jsonb; v_pessoa uuid; v_tipo text; v_texto text; v_url text; v_em timestamptz; v_id uuid; v_nome text;
  v_palavra text; v_nao int; v_dono uuid; v_pc uuid;
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

  insert into crm.mensagem (conversa_id, pessoa_id, direcao, tipo, texto, midia_url, em, provedor, provedor_msg_id)
  values (v_conv.id, v_conv.pessoa_id, 'entrada', v_tipo, v_texto, v_url, v_em, 'infobip', v_mid)
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
$$;

-- Relatório de entrega (status) e visto (lida). Nunca regride: rank; falhou só antes de entregue; falha incerta é corrigida.
create function crm.whatsapp_status(e jsonb, p_tipo text) returns text
language plpgsql security definer set search_path = '' as $$
declare m crm.mensagem%rowtype; v_novo text; v_em timestamptz; v_err text; v_grupo text;
begin
  select * into m from crm.mensagem x where x.provedor = 'infobip' and x.provedor_msg_id = e ->> 'messageId' for update;
  if not found then return 'mensagem_desconhecida'; end if;
  if m.direcao <> 'saida' then return 'nao_e_saida'; end if;
  if p_tipo = 'lida' then
    v_novo := 'lida'; v_em := crm.ts_ou_agora(e ->> 'seenAt');
  else
    v_grupo := upper(coalesce(e -> 'status' ->> 'groupName', ''));
    v_novo := case v_grupo when 'PENDING' then 'enviada' when 'DELIVERED' then 'entregue'
                           when 'UNDELIVERABLE' then 'falhou' when 'EXPIRED' then 'falhou' when 'REJECTED' then 'falhou' end;
    v_em := crm.ts_ou_agora(coalesce(e ->> 'doneAt', e ->> 'sentAt'));
    if v_novo = 'falhou' then
      v_err := left(coalesce(nullif(concat_ws(': ', e -> 'error' ->> 'name', e -> 'error' ->> 'description'), ''),
                             concat_ws(': ', e -> 'status' ->> 'name', e -> 'status' ->> 'description'), 'Falha informada pelo provedor'), 300);
    end if;
  end if;
  if v_novo is null then return 'status_ignorado'; end if;
  if v_novo = 'falhou' then
    if m.status in ('entregue', 'lida') or (m.status = 'falhou' and not m.falha_incerta) then return 'sem_mudanca'; end if;
    update crm.mensagem x set status = 'falhou', status_em = greatest(x.status_em, v_em), erro = v_err, falha_incerta = false where x.id = m.id;
    return 'falhou';
  end if;
  if crm.status_rank(v_novo) <= crm.status_rank(m.status) and not (m.status = 'falhou' and m.falha_incerta) then
    return 'sem_mudanca';
  end if;
  update crm.mensagem x
     set status = v_novo, status_em = greatest(x.status_em, v_em), falha_incerta = false,
         erro = case when x.status = 'falhou' then null else x.erro end
   where x.id = m.id;
  return v_novo;
end
$$;

-- Processa 1 evento bruto. Erro fica no evento (resultado) e NÃO derruba o lote; volta em whatsapp_reprocessar.
create function crm.whatsapp_processar(p_evento bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare ev crm.integracao_evento%rowtype; v_res text;
begin
  select * into ev from crm.integracao_evento x where x.id = p_evento for update skip locked;
  if not found or ev.processado_em is not null then return 'ja_processado'; end if;
  begin
    perform set_config('crm.canal', 'whatsapp', true);
    v_res := case when ev.tipo = 'entrada' then crm.whatsapp_entrada(ev.payload)
                  when ev.tipo in ('status', 'lida') then crm.whatsapp_status(ev.payload, ev.tipo)
                  else 'tipo_desconhecido' end;
    update crm.integracao_evento x set processado_em = now(), resultado = v_res, tentativas = x.tentativas + 1 where x.id = p_evento;
  exception when others then
    v_res := 'erro';
    update crm.integracao_evento x set tentativas = x.tentativas + 1, resultado = left('erro ' || sqlstate || ': ' || sqlerrm, 300)
     where x.id = p_evento;
  end;
  perform set_config('crm.canal', '', true);
  return v_res;
end
$$;

-- Ponto de entrada da Edge crm-whatsapp-webhook. p = corpo da Infobip ({"results": [...]}). Só grava o que é do Comercial.
create function crm.whatsapp_webhook(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb; v_tipo text; v_mid text; v_evid text; v_id bigint; v_res text;
  v_lig boolean := coalesce((select c.whatsapp_ligado from crm.config c), false);
  n_rec int := 0; n_novo int := 0; n_dup int := 0; n_ign int := 0; n_proc int := 0; n_err int := 0;
begin
  if p is null or jsonb_typeof(p -> 'results') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Corpo sem "results".');
  end if;
  for r in select x from jsonb_array_elements(p -> 'results') with ordinality t(x, o) where o <= 1000 loop
    n_rec := n_rec + 1;
    v_mid := r ->> 'messageId';
    v_tipo := case when r ? 'receivedAt' and r ? 'message' then 'entrada'
                   when r ? 'seenAt' then 'lida'
                   when r ? 'status' then 'status' end;
    if v_tipo is null or coalesce(v_mid, '') = '' or length(v_mid) > 200 then n_ign := n_ign + 1; continue; end if;
    if v_tipo = 'entrada' then
      if not exists (select 1 from crm.numero_whatsapp n where n.numero = pessoas.so_digitos(r ->> 'to') and n.ativo) then
        n_ign := n_ign + 1; continue;   -- outro número da conta Infobip (ex.: Marketing): não é do CRM, não guarda
      end if;
    elsif not exists (select 1 from crm.mensagem m where m.provedor = 'infobip' and m.provedor_msg_id = v_mid and m.direcao = 'saida') then
      n_ign := n_ign + 1; continue;     -- relatório de mensagem que não saiu do CRM
    end if;
    v_evid := left(case v_tipo when 'entrada' then 'in:' || v_mid when 'lida' then 'seen:' || v_mid
                               else 'st:' || v_mid || ':' || coalesce(r -> 'status' ->> 'name', r -> 'status' ->> 'groupName', '?') end, 300);
    insert into crm.integracao_evento (fonte, tipo, fonte_evento_id, payload)
    values ('infobip', v_tipo, v_evid, r)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then n_dup := n_dup + 1; continue; end if;
    n_novo := n_novo + 1;
    if v_lig then
      v_res := crm.whatsapp_processar(v_id);
      if v_res = 'erro' then n_err := n_err + 1; else n_proc := n_proc + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'recebidos', n_rec, 'novos', n_novo, 'duplicados', n_dup, 'ignorados', n_ign,
                            'processados', n_proc, 'erros', n_err, 'ligado', v_lig);
end
$$;

-- Pendentes (whatsapp desligado na chegada, ou erro): para cron SQL de 10 min (sem HTTP). Sai na 1ª linha se desligado.
create function crm.whatsapp_reprocessar(p_limite int default 500) returns int
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; n int := 0;
begin
  if not coalesce((select c.whatsapp_ligado from crm.config c), false) then return 0; end if;
  for v_id in select x.id from crm.integracao_evento x
               where x.processado_em is null and x.fonte = 'infobip' and x.tentativas < 5
               order by x.id limit least(greatest(coalesce(p_limite, 500), 1), 2000) loop
    perform crm.whatsapp_processar(v_id);
    n := n + 1;
  end loop;
  return n;
end
$$;

-- ─── 6. Saída: fichas, fila, resultado, templates ───────────────────────────────────────────────────────────────────
-- Fichas aprovadas cuja hora chegou: revalida template e validade, recalcula supressões e enfileira 1 template por elegível.
create function crm.fichas_liberar() returns int
language plpgsql security definer set search_path = '' as $$
declare f crm.ficha_disparo%rowtype; t crm.template%rowtype; c crm.config%rowtype; d record; v_r jsonb; v_conv uuid;
        cv crm.conversa%rowtype; v_id uuid; v_q int; v_s int; v_n int; n_tot int := 0;
begin
  select * into c from crm.config;
  if not (coalesce(c.whatsapp_ligado, false) and coalesce(c.envio_ligado, false)) then return 0; end if;
  for f in select * from crm.ficha_disparo x where x.status = 'aprovada' and x.agendado_para <= now()
           order by x.agendado_para limit 3 for update skip locked loop
    select * into t from crm.template x where x.id = f.template_id;
    if not (t.aprovado and t.ativo) or f.agendado_para < now() - make_interval(mins => c.disparo_validade_min) then
      perform set_config('crm.resumo', 'Ficha ' || f.codigo || ' não saiu: ' ||
                         case when not (t.aprovado and t.ativo) then 'template deixou de estar aprovado' else 'agendamento expirou sem envio' end, true);
      update crm.ficha_disparo x set status = 'reprovada', motivo_status = case when not (t.aprovado and t.ativo)
               then 'Template deixou de estar aprovado.' else 'Agendamento expirou sem envio (envio desligado?).' end,
             decidido_em = now(), atualizado_em = now()
       where x.id = f.id;
      continue;
    end if;
    -- supressões recalculadas na 1ª rodada desta ficha; depois segue em lotes de 500 por ciclo (a fila chama de novo)
    if not exists (select 1 from crm.ficha_destinatario y where y.ficha_id = f.id and y.mensagem_id is not null) then
      select q.quantidade, q.suprimidos into v_q, v_s from crm.ficha_calcular(f.id, f.linha) q;
    end if;
    v_n := 0;
    for d in select x.pessoa_id from crm.ficha_destinatario x
             where x.ficha_id = f.id and x.suprimido_por is null and x.mensagem_id is null
             order by x.pessoa_id limit 500 loop
      v_r := crm.template_render(t, d.pessoa_id, f.link);
      v_conv := case when (v_r ->> 'ok')::boolean then crm.whatsapp_conversa_para(f.numero_id, d.pessoa_id) end;
      if v_conv is null then
        update crm.ficha_destinatario x set suprimido_por = 'sem_dados' where x.ficha_id = f.id and x.pessoa_id = d.pessoa_id;
        continue;
      end if;
      select * into cv from crm.conversa x where x.id = v_conv;
      v_id := gen_random_uuid();
      insert into crm.mensagem (id, conversa_id, pessoa_id, direcao, tipo, texto, em, status, status_em, fila_em, autor_id,
                                template_id, template_vars, ficha_id, provedor, provedor_msg_id)
      values (v_id, cv.id, cv.pessoa_id, 'saida', 'template', v_r ->> 'texto', now(), 'na_fila', now(), now(), f.operador_id,
              t.id, v_r -> 'vars', f.id, 'infobip', v_id::text);
      update crm.ficha_destinatario x set mensagem_id = v_id where x.ficha_id = f.id and x.pessoa_id = d.pessoa_id;
      update crm.conversa x set ultima_em = now(), ultima_mensagem_id = v_id where x.id = cv.id;
      v_n := v_n + 1;
    end loop;
    n_tot := n_tot + v_n;
    if exists (select 1 from crm.ficha_destinatario y where y.ficha_id = f.id and y.suprimido_por is null and y.mensagem_id is null) then
      continue;   -- ainda há lote: continua 'aprovada', o próximo ciclo da fila segue
    end if;
    perform set_config('crm.resumo', format('Disparou a ficha %s: %s mensagens na fila',
                       f.codigo, (select count(*) from crm.ficha_destinatario y where y.ficha_id = f.id and y.mensagem_id is not null)), true);
    update crm.ficha_disparo x
       set status = 'enviada', enviada_em = now(), atualizado_em = now(),
           quantidade = (select count(*) from crm.ficha_destinatario y where y.ficha_id = f.id),
           suprimidos = (select count(*) from crm.ficha_destinatario y where y.ficha_id = f.id and y.suprimido_por is not null)
     where x.id = f.id;
  end loop;
  perform set_config('crm.resumo', '', true);
  return n_tot;
end
$$;

-- O cron (SQL, 1/min) só chama a Edge quando isto é true: fila vencida, ficha na hora ou envio travado.
create function crm.whatsapp_fila_tem() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select c.whatsapp_ligado and c.envio_ligado from crm.config c), false)
     and (exists (select 1 from crm.mensagem m where m.status = 'na_fila' and m.fila_em <= now()
                     and coalesce(m.proxima_tentativa_em, m.fila_em) <= now())
          or exists (select 1 from crm.ficha_disparo f where f.status = 'aprovada' and f.agendado_para <= now())
          or exists (select 1 from crm.mensagem m where m.status = 'enviando' and m.status_em < now() - interval '5 minutes'));
$$;

-- Pega um lote para a Edge enviar. Revalida TUDO na hora (opt-out, janela 24 h, template, número, validade) e trava com
-- SKIP LOCKED (duas Edges ao mesmo tempo não pegam a mesma mensagem). Devolve só o necessário para a chamada à Infobip.
create function crm.whatsapp_fila_pegar(p_lote int default null)
returns table (mensagem_id uuid, de text, para text, tipo text, texto text, template_nome text, template_idioma text, variaveis jsonb)
language plpgsql security definer set search_path = '' as $$
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
                  t.nome_provedor, t.idioma, coalesce(t.aprovado and t.ativo, false) t_ok
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
                   when m.tipo = 'template' and not m.t_ok then 'Template deixou de estar aprovado.' end;
    if v_erro is not null then
      update crm.mensagem x set status = 'falhou', status_em = now(), erro = v_erro where x.id = m.id;
      continue;
    end if;
    update crm.mensagem x set status = 'enviando', status_em = now(), tentativas = x.tentativas + 1 where x.id = m.id;
    mensagem_id := m.id; de := m.numero; para := m.telefone; tipo := m.tipo; texto := m.texto;
    template_nome := m.nome_provedor; template_idioma := m.idioma; variaveis := coalesce(m.template_vars, '[]'::jsonb);
    return next;
  end loop;
end
$$;

-- Resposta da Infobip ao envio. p_http: 0 = sem resposta (rede/timeout/5xx) → falha incerta, sem reenvio;
-- p_reenfileirar (429, ou não chegou a sair por falta de tempo) → volta para a fila com espera crescente (até 5 tentativas).
-- Só mexe em quem está 'enviando' (o relatório pode ter chegado antes e avançado o status).
create function crm.whatsapp_fila_resultado(p_mensagem uuid, p_http int, p_grupo text, p_erro text, p_reenfileirar boolean default false)
returns text
language plpgsql security definer set search_path = '' as $$
declare m crm.mensagem%rowtype; v_grupo text := upper(coalesce(p_grupo, ''));
begin
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or m.status <> 'enviando' then return 'ignorado'; end if;
  if coalesce(p_reenfileirar, false) and m.tentativas < 5 then
    update crm.mensagem x set status = 'na_fila', status_em = now(), erro = left(p_erro, 300),
           proxima_tentativa_em = now() + make_interval(mins => greatest(m.tentativas, 1))
     where x.id = m.id;
    return 'na_fila';
  elsif p_http between 200 and 299 and v_grupo in ('PENDING', 'DELIVERED', '') then
    update crm.mensagem x set status = 'enviada', status_em = now(), erro = null where x.id = m.id;
    return 'enviada';
  elsif coalesce(p_http, 0) = 0 or p_http >= 500 then
    update crm.mensagem x set status = 'falhou', falha_incerta = true, status_em = now(),
           erro = left('Sem confirmação do provedor: ' || coalesce(p_erro, 'sem resposta'), 300)
     where x.id = m.id;
    return 'falhou_incerta';
  else
    update crm.mensagem x set status = 'falhou', status_em = now(), erro = left(coalesce(p_erro, 'HTTP ' || p_http), 300) where x.id = m.id;
    return 'falhou';
  end if;
end
$$;

-- Templates do remetente (GET /whatsapp/2/senders/{sender}/templates, só leitura na Infobip). Quem sumiu vira inativo.
create function crm.whatsapp_templates_sincronizar(p_numero text, p_lista jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n crm.numero_whatsapp%rowtype; t jsonb; v_ini timestamptz := clock_timestamp(); v_texto text; v_cat text; k int := 0; v_inat int;
begin
  select * into n from crm.numero_whatsapp x where x.numero = pessoas.so_digitos(p_numero);
  if not found then return jsonb_build_object('ok', false, 'msg', 'Número não cadastrado.'); end if;
  if jsonb_typeof(p_lista) is distinct from 'array' then return jsonb_build_object('ok', false, 'msg', 'Lista inválida.'); end if;
  for t in select x from jsonb_array_elements(p_lista) with ordinality y(x, o) where o <= 500 loop
    v_texto := left(coalesce(t -> 'structure' -> 'body' ->> 'text', t -> 'body' ->> 'text', t ->> 'body'), 4096);
    v_cat := lower(t ->> 'category');
    continue when coalesce(t ->> 'name', '') = '' or coalesce(v_texto, '') = '' or coalesce(v_cat, '') not in ('marketing', 'utility', 'authentication');
    insert into crm.template (numero_id, nome_provedor, idioma, categoria, texto, variaveis, aprovado, status_provedor, ativo, sincronizado_em)
    values (n.id, left(t ->> 'name', 512), coalesce(nullif(t ->> 'language', ''), 'pt_BR'), v_cat, v_texto,
            coalesce((select max((mm[1])::int) from regexp_matches(v_texto, '\{\{([0-9]+)\}\}', 'g') mm), 0),
            upper(coalesce(t ->> 'status', '')) = 'APPROVED', left(upper(t ->> 'status'), 40), true, clock_timestamp())
    on conflict (numero_id, nome_provedor, idioma) do update
       set categoria = excluded.categoria, texto = excluded.texto, variaveis = excluded.variaveis, aprovado = excluded.aprovado,
           status_provedor = excluded.status_provedor, ativo = true, sincronizado_em = excluded.sincronizado_em;
    k := k + 1;
  end loop;
  update crm.template x set ativo = false where x.numero_id = n.id and x.ativo and x.sincronizado_em < v_ini;
  get diagnostics v_inat = row_count;
  return jsonb_build_object('ok', true, 'sincronizados', k, 'inativados', v_inat);
end
$$;

-- ─── 7. RLS e grants das tabelas ────────────────────────────────────────────────────────────────────────────────────
do $rls$
declare t text;
begin
  foreach t in array array['numero_whatsapp', 'template', 'ficha_disparo', 'ficha_destinatario', 'conversa', 'mensagem',
                           'supressao', 'integracao_evento'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['numero_whatsapp', 'template', 'ficha_disparo', 'ficha_destinatario', 'conversa', 'mensagem'] loop
    execute format('grant select on crm.%I to authenticated', t);
  end loop;
end
$rls$;
revoke all on all sequences in schema crm from public, anon, authenticated;
-- supressao e integracao_evento: sem grant e sem policy (só funções definer).

create policy numero_whatsapp_ler on crm.numero_whatsapp for select to authenticated using ((select crm.eh_comercial()));
create policy template_ler on crm.template for select to authenticated using ((select crm.eh_comercial()));
-- fichas são agenda do time (conflito de 48 h): todo o comercial vê; a lista de pessoas só o gestor e o operador
create policy ficha_ler on crm.ficha_disparo for select to authenticated using ((select crm.eh_comercial()));
create policy ficha_destinatario_ler on crm.ficha_destinatario for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and ficha_id in (select f.id from crm.ficha_disparo f where f.operador_id = (select auth.uid()))));
create policy conversa_ler on crm.conversa for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and pessoa_id in (select crm.pessoas_do_vendedor())));
create policy mensagem_ler on crm.mensagem for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and pessoa_id in (select crm.pessoas_do_vendedor())));

-- ─── 8. RPCs de LEITURA ─────────────────────────────────────────────────────────────────────────────────────────────
-- Conversas (RLS). Uma por CONTATO (pessoa atual): a conversa mais recente do grupo; não lidas somadas; janela aberta.
create function public.crm_conversas(p_limite int default 300) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v_lim int := least(greatest(coalesce(p_limite, 300), 1), 1000); v jsonb;
begin
  perform crm.exige_comercial();
  with c as (select x.* from crm.conversa x where x.ultima_mensagem_id is not null order by x.ultima_em desc limit v_lim * 2),
  al as (select * from crm.atual_de(array(select distinct c.pessoa_id from c))),
  g as (select al.atual, (array_agg(c.ultima_mensagem_id order by c.ultima_em desc))[1] msg_id, sum(c.nao_lidas)::int nao,
               max(c.ultima_entrada_em) ent, max(c.ultima_em) ult
          from c join al on al.pessoa_id = c.pessoa_id group by al.atual order by max(c.ultima_em) desc limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'contatoId', g.atual, 'ultimaMensagem', crm.mensagem_json(m, g.atual), 'naoLidas', g.nao,
           'janelaAteEm', case when g.ent > now() - interval '24 hours' then g.ent + interval '24 hours' end,
           'atribuidaA', pc.dono_id) order by g.ult desc), '[]'::jsonb)
    into v
    from g join crm.mensagem m on m.id = g.msg_id
    left join crm.pessoa_comercial pc on pc.pessoa_id = g.atual;
  return v;
end
$$;

-- Mensagens do contato (grupo), da mais antiga para a mais nova; as últimas p_limite (≤ 1.000). RLS.
create function public.crm_mensagens(p_pessoa uuid, p_limite int default 500) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v_lim int := least(greatest(coalesce(p_limite, 500), 1), 1000); v_g uuid[]; v_atual uuid; v jsonb;
begin
  perform crm.exige_comercial();
  v_g := crm.pessoa_grupo(p_pessoa);
  select a.atual into v_atual from crm.atual_de(array[p_pessoa]) a;
  select coalesce(jsonb_agg(crm.mensagem_json(m, v_atual) order by m.em, m.id), '[]'::jsonb) into v
    from (select x.* from crm.mensagem x where x.pessoa_id = any(v_g) order by x.em desc, x.id desc limit v_lim) m;
  return v;
end
$$;

-- Templates ativos do número de envio (sem autenticação/OTP). RLS.
create function public.crm_templates() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome_provedor, 'categoria', t.categoria, 'texto', t.texto,
                                               'aprovado', t.aprovado, 'idioma', t.idioma, 'variaveis', t.variaveis)
                            order by t.aprovado desc, t.nome_provedor), '[]'::jsonb)
    into v
    from crm.template t
    join crm.config c on c.whatsapp_numero_id = t.numero_id
   where t.ativo and t.categoria in ('marketing', 'utility');
  return v;
end
$$;

-- Fichas (agenda do time) com o resultado medido nas mensagens. DEFINER: o resultado conta todas as mensagens da ficha,
-- não só as que a RLS do vendedor mostra (só números, nenhuma pessoa).
create function public.crm_fichas(p_limite int default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_lim int := least(greatest(coalesce(p_limite, 200), 1), 500); v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'codigo', f.codigo, 'objetivo', f.objetivo, 'produto', f.linha, 'filtro', f.filtro,
           'quantidade', f.quantidade, 'supressoes', to_jsonb(f.supressoes), 'suprimidos', f.suprimidos,
           'templateId', f.template_id, 'numeroEnvio', n.numero, 'agendadoPara', f.agendado_para, 'operadorId', f.operador_id,
           'link', f.link, 'status', f.status, 'aprovadoPor', coalesce(f.aprovado_por, f.decidido_por), 'criadoEm', f.criado_em,
           'motivoStatus', f.motivo_status,
           'resultado', case when f.status = 'enviada' then jsonb_build_object(
                          'entregues', r.entregues, 'lidas', r.lidas, 'respostas', r.respostas, 'falhas', r.falhas, 'naFila', r.fila) end)
           order by f.criado_em desc), '[]'::jsonb)
    into v
    from (select x.* from crm.ficha_disparo x order by x.criado_em desc limit v_lim) f
    join crm.numero_whatsapp n on n.id = f.numero_id
    left join lateral (
      select count(*) filter (where m.status in ('entregue', 'lida'))::int entregues,
             count(*) filter (where m.status = 'lida')::int lidas,
             count(*) filter (where m.status = 'falhou')::int falhas,
             count(*) filter (where m.status in ('na_fila', 'enviando'))::int fila,
             count(*) filter (where exists (select 1 from crm.mensagem e where e.conversa_id = m.conversa_id and e.direcao = 'entrada'
                                               and e.em > m.em and e.em < m.em + interval '72 hours'))::int respostas
        from crm.mensagem m where m.ficha_id = f.id and f.status = 'enviada') r on true;
  return v;
end
$$;

-- Estado do WhatsApp para a tela (interruptores, número mascarado, templates aprovados, fila). Sem dado de pessoa.
create function public.crm_whatsapp_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object(
           'whatsappLigado', c.whatsapp_ligado, 'envioLigado', c.envio_ligado, 'escritaLigada', c.escrita_ligada,
           'numero', case when n.id is not null then jsonb_build_object('id', n.id, 'nome', n.nome, 'final', right(n.numero, 4), 'ativo', n.ativo) end,
           'templatesAprovados', (select count(*) from crm.template t where t.numero_id = n.id and t.ativo and t.aprovado
                                     and t.categoria in ('marketing', 'utility')),
           'naFila', (select count(*) from crm.mensagem m where m.status = 'na_fila'),
           'falhasHoje', (select count(*) from crm.mensagem m where m.status = 'falhou'
                            and m.status_em >= date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
           'janelaHoras', 24, 'maxDestinatarios', c.disparo_max_destinatarios)
    into v
    from crm.config c left join crm.numero_whatsapp n on n.id = c.whatsapp_numero_id;
  return v;
end
$$;

-- ─── 9. RPCs de ESCRITA ─────────────────────────────────────────────────────────────────────────────────────────────
-- Enfileira mensagem (texto na janela de 24 h, ou template aprovado fora dela). Mesmas mensagens do mock.
create function public.crm_enviar_mensagem(p_pessoa uuid, p_texto text, p_template uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; v_conv uuid; cv crm.conversa%rowtype;
        t crm.template%rowtype; v_rend jsonb; v_texto text; v_tipo text := 'texto'; v_vars jsonb; v_id uuid := gen_random_uuid();
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into c from crm.config;
  if not coalesce(c.whatsapp_ligado, false) then return crm.res(false, 'WhatsApp desligado.'); end if;
  if not coalesce(c.envio_ligado, false) then return crm.res(false, 'Envio de WhatsApp desligado.'); end if;
  if c.whatsapp_numero_id is null or not exists (select 1 from crm.numero_whatsapp n where n.id = c.whatsapp_numero_id and n.ativo) then
    return crm.res(false, 'Número de envio não configurado.');
  end if;
  if p_template is null and btrim(coalesce(p_texto, '')) = '' then return crm.res(false, 'Mensagem vazia.'); end if;
  if p_template is null and length(btrim(p_texto)) > 4096 then return crm.res(false, 'Mensagem longa demais (máximo 4.096 caracteres).'); end if;
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
    v_texto := btrim(p_texto);
  else
    v_rend := crm.template_render(t, v_atual, null);
    if not (v_rend ->> 'ok')::boolean then raise exception '%', v_rend ->> 'msg' using errcode = 'P0001'; end if;
    v_texto := v_rend ->> 'texto'; v_vars := v_rend -> 'vars'; v_tipo := 'template';
  end if;
  insert into crm.mensagem (id, conversa_id, pessoa_id, direcao, tipo, texto, em, status, status_em, fila_em, autor_id,
                            template_id, template_vars, provedor, provedor_msg_id)
  values (v_id, cv.id, cv.pessoa_id, 'saida', v_tipo, v_texto, now(), 'na_fila', now(), now(), v_eu,
          t.id, v_vars, 'infobip', v_id::text);
  update crm.conversa x set ultima_em = now(), ultima_mensagem_id = v_id, nao_lidas = 0 where x.id = cv.id;
  update crm.mensagem x set lida_em = now() where x.conversa_id = cv.id and x.direcao = 'entrada' and x.lida_em is null;
  perform crm.log_registrar('enviou', 'mensagem', v_id::text, v_atual,
                            format('Enviou %s para %s', case when v_tipo = 'template' then 'template ' || t.nome_provedor else 'mensagem' end,
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
$$;

-- Marca como lidas as mensagens recebidas do contato (grupo). Quem vê a pessoa pode marcar.
create function public.crm_marcar_conversa_lida(p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_atual uuid; v_g uuid[]; v_n int;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not crm.pode_ver_pessoa(v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  v_g := pessoas.grupo(v_atual);
  update crm.mensagem m set lida_em = now()
    from crm.conversa cv
   where m.conversa_id = cv.id and cv.pessoa_id = any(v_g) and m.direcao = 'entrada' and m.lida_em is null;
  get diagnostics v_n = row_count;
  update crm.conversa x set nao_lidas = 0 where x.pessoa_id = any(v_g) and x.nao_lidas > 0;
  return crm.res(true, null, jsonb_build_object('marcadas', v_n));
end
$$;

-- Ficha de disparo. p_ficha (camelCase, = NovaFicha + id opcional + destinatarios: contatoIds). quantidade/suprimidos do
-- cliente são ignorados: o banco conta. Gestor que envia = aprovada; vendedor (dispara_api) = aguardando_aprovacao.
create function public.crm_salvar_ficha(p_ficha jsonb, p_enviar_para_aprovacao boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid(); v_r jsonb; v_gestor boolean; c crm.config%rowtype; f crm.ficha_disparo%rowtype; v_id uuid; v_existe boolean := false;
  v_obj text; v_linha text; v_filtro text; t crm.template%rowtype; v_num uuid; v_ag timestamptz; v_link text;
  v_lista uuid[]; v_n_in int; v_status text; v_cod text; v_q int; v_s int; v_msg text; v_enviar boolean := coalesce(p_enviar_para_aprovacao, false);
  v_s1 text; v_c1 text; v_m1 text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_ficha is null or jsonb_typeof(p_ficha) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_gestor := coalesce(crm.eh_gestor(), false);
  if not v_gestor and not coalesce((select v.dispara_api and v.ativo from crm.vendedor v where v.perfil_id = v_eu), false) then
    return crm.res(false, 'Seu usuário não opera disparo por API.');
  end if;
  select * into c from crm.config;
  v_id := crm.uuid_ou_null(p_ficha ->> 'id');
  if v_id is not null then
    select * into f from crm.ficha_disparo x where x.id = v_id for update;
    v_existe := found;
    if v_existe then
      if not (v_gestor or f.operador_id = v_eu) then return crm.res(false, 'Esta ficha não é sua.'); end if;
      if f.status in ('aprovada', 'enviada') then return crm.res(false, 'Ficha aprovada não muda: reprove ou crie outra.'); end if;
    else
      v_id := null;
    end if;
  end if;

  v_obj := btrim(coalesce(p_ficha ->> 'objetivo', ''));
  if v_obj = '' then return crm.res(false, 'Descreva o objetivo do disparo.'); end if;
  v_linha := p_ficha ->> 'produto';
  if not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  v_filtro := btrim(coalesce(p_ficha ->> 'filtro', ''));
  if v_filtro = '' then return crm.res(false, 'Descreva o filtro da lista.'); end if;
  select * into t from crm.template x where x.id = crm.uuid_ou_null(p_ficha ->> 'templateId') and x.ativo;
  if not found or t.categoria not in ('marketing', 'utility') then return crm.res(false, 'Escolha um template.'); end if;
  if nullif(btrim(coalesce(p_ficha ->> 'numeroEnvio', '')), '') is not null then
    select n.id into v_num from crm.numero_whatsapp n where n.numero = pessoas.so_digitos(p_ficha ->> 'numeroEnvio') and n.ativo;
    if v_num is null then return crm.res(false, 'Número de envio inválido.'); end if;
  else
    v_num := c.whatsapp_numero_id;
    if v_num is null then return crm.res(false, 'Número de envio não configurado.'); end if;
  end if;
  if t.numero_id <> v_num then return crm.res(false, 'O template é de outro número de envio.'); end if;
  v_ag := nullif(p_ficha ->> 'agendadoPara', '')::timestamptz;
  if v_ag is null then return crm.res(false, 'Informe quando disparar.'); end if;
  v_link := btrim(coalesce(p_ficha ->> 'link', ''));
  if v_link !~ '^https://[^[:space:]]+$' or length(v_link) > 1000 then return crm.res(false, 'O link precisa começar com https://.'); end if;

  if p_ficha ? 'destinatarios' then
    if jsonb_typeof(p_ficha -> 'destinatarios') <> 'array' then return crm.res(false, 'Lista de destinatários inválida.'); end if;
    select count(*) into v_n_in from jsonb_array_elements_text(p_ficha -> 'destinatarios') x;
    v_lista := array(select distinct pessoas.atual(crm.uuid_ou_null(x)) from jsonb_array_elements_text(p_ficha -> 'destinatarios') x
                      where crm.uuid_ou_null(x) is not null);
    v_lista := array(select x from unnest(v_lista) x where x is not null);
    if cardinality(v_lista) = 0 and v_n_in > 0 then return crm.res(false, 'Há destinatários inválidos.'); end if;
    if exists (select 1 from jsonb_array_elements_text(p_ficha -> 'destinatarios') x
                where crm.uuid_ou_null(x) is null or not exists (select 1 from pessoas.pessoas p where p.id = crm.uuid_ou_null(x))) then
      return crm.res(false, 'Há destinatários inválidos.');
    end if;
    if cardinality(v_lista) > c.disparo_max_destinatarios then
      return crm.res(false, format('Lista acima do limite de %s contatos.', c.disparo_max_destinatarios));
    end if;
    -- vendedor: só pessoas que ele vê (as dele, as sem dono, as com negócio dele), por CONJUNTO (1 consulta, não 1 por pessoa)
    if not v_gestor and exists (select 1 from unnest(v_lista) x where x not in (select crm.pessoas_do_vendedor())) then
      return crm.res(false, 'Há contatos na lista que não são seus.');
    end if;
  end if;

  if v_enviar then
    if not t.aprovado then return crm.res(false, 'Template não aprovado.'); end if;
    if v_ag < now() then return crm.res(false, 'Agendamento no passado.'); end if;
    if coalesce(cardinality(v_lista), case when v_existe then (select count(*) from crm.ficha_destinatario d where d.ficha_id = v_id) end, 0) = 0 then
      return crm.res(false, 'Ficha sem destinatários: monte a lista antes de enviar para aprovação.');
    end if;
  end if;
  v_status := case when not v_enviar then 'rascunho' when v_gestor then 'aprovada' else 'aguardando_aprovacao' end;

  if not v_existe then
    v_cod := crm.ficha_codigo(v_linha);
    perform set_config('crm.resumo', format('Criou a ficha de disparo %s (%s)', v_cod, v_status), true);
    insert into crm.ficha_disparo (codigo, objetivo, linha, filtro, template_id, numero_id, agendado_para, operador_id, link, status,
                                   aprovado_por, aprovado_em, decidido_por, decidido_em)
    values (v_cod, v_obj, v_linha, v_filtro, t.id, v_num, v_ag, v_eu, v_link, v_status,
            case when v_status = 'aprovada' then v_eu end, case when v_status = 'aprovada' then now() end,
            case when v_status = 'aprovada' then v_eu end, case when v_status = 'aprovada' then now() end)
    returning * into f;
    v_id := f.id;
  end if;
  if v_lista is not null then
    delete from crm.ficha_destinatario d where d.ficha_id = v_id and d.mensagem_id is null;   -- lista de ficha não aprovada
    insert into crm.ficha_destinatario (ficha_id, pessoa_id) select v_id, x from unnest(v_lista) x on conflict do nothing;
  end if;
  select q.quantidade, q.suprimidos into v_q, v_s from crm.ficha_calcular(v_id, v_linha) q;
  if v_enviar and v_q - v_s = 0 then
    raise exception 'Todos os contatos da lista estão suprimidos.' using errcode = 'P0001';
  end if;
  perform set_config('crm.resumo', format('%s a ficha de disparo %s (%s): %s contatos, %s suprimidos',
                                          case when v_existe then 'Editou' else 'Montou a lista da' end,
                                          f.codigo, v_status, v_q, v_s), true);
  update crm.ficha_disparo x
     set objetivo = v_obj, linha = v_linha, filtro = v_filtro, template_id = t.id, numero_id = v_num, agendado_para = v_ag, link = v_link,
         status = v_status, quantidade = v_q, suprimidos = v_s, motivo_status = null, atualizado_em = now(),
         aprovado_por = case when v_status = 'aprovada' then v_eu end, aprovado_em = case when v_status = 'aprovada' then now() end,
         decidido_por = case when v_status = 'aprovada' then v_eu end, decidido_em = case when v_status = 'aprovada' then now() end
   where x.id = v_id;
  perform set_config('crm.resumo', '', true);

  if v_status = 'aguardando_aprovacao' then
    begin
      insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
      select p.id, 'ficha_para_aprovar', v_id::text || ':' || floor(extract(epoch from now()))::bigint,
             left('Ficha para aprovar: ' || f.codigo, 200), left(v_obj, 500), '/comercial/disparos?ficha=' || v_id
        from public.perfis p
       where p.status = 'ativo' and p.id <> v_eu and 'comercial' = any(coalesce(p.areas, '{}'))
         and p.cargo in ('dev', 'admin', 'gestor')
         and not exists (select 1 from crm.preferencias_notificacao x where x.perfil_id = p.id and (x.gatilhos ->> 'ficha_para_aprovar') = 'false')
      on conflict (perfil_id, gatilho, ref_id) do nothing;
    exception when others then
      raise warning 'crm_salvar_ficha (aviso): %', sqlstate;
    end;
  end if;
  v_msg := case v_status when 'aguardando_aprovacao' then 'Ficha enviada para aprovação do gestor.'
                         when 'aprovada' then 'Ficha registrada e aprovada.' else 'Rascunho salvo.' end;
  return crm.res(true, v_msg, jsonb_build_object('fichaId', v_id, 'codigo', f.codigo, 'quantidade', v_q, 'suprimidos', v_s));
exception
  when sqlstate 'P0001' then
    get stacked diagnostics v_m1 = message_text;
    return crm.res(false, v_m1);
  when check_violation or unique_violation or foreign_key_violation or not_null_violation
       or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
       or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
    get stacked diagnostics v_s1 = returned_sqlstate, v_c1 = constraint_name, v_m1 = message_text;
    return crm.erro_dados(v_s1, v_m1, v_c1);
end
$$;

-- Decisão do gestor: aprova/reprova a que aguarda; "reprovar" uma aprovada que ainda não saiu = cancelar.
create function public.crm_decidir_ficha(p_ficha uuid, p_aprovar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; f crm.ficha_disparo%rowtype; t crm.template%rowtype; v_q int; v_s int; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor aprova ficha de disparo.'); end if;
  select * into f from crm.ficha_disparo x where x.id = p_ficha for update;
  if not found then return crm.res(false, 'Ficha não encontrada.'); end if;
  if f.status = 'aguardando_aprovacao' and coalesce(p_aprovar, false) then
    select * into t from crm.template x where x.id = f.template_id;
    if not (t.aprovado and t.ativo) then return crm.res(false, 'Template não aprovado.'); end if;
    if f.agendado_para < now() then return crm.res(false, 'Agendamento já passou: remarque a ficha.'); end if;
    select q.quantidade, q.suprimidos into v_q, v_s from crm.ficha_calcular(f.id, f.linha) q;
    if v_q - v_s = 0 then raise exception 'Todos os contatos da lista estão suprimidos.' using errcode = 'P0001'; end if;
    perform set_config('crm.resumo', format('Aprovou a ficha %s (%s contatos, %s suprimidos)', f.codigo, v_q, v_s), true);
    update crm.ficha_disparo x set status = 'aprovada', aprovado_por = v_eu, aprovado_em = now(), decidido_por = v_eu, decidido_em = now(),
           quantidade = v_q, suprimidos = v_s, atualizado_em = now()
     where x.id = f.id;
  elsif f.status = 'aguardando_aprovacao' then
    perform set_config('crm.resumo', format('Reprovou a ficha %s', f.codigo), true);
    update crm.ficha_disparo x set status = 'reprovada', decidido_por = v_eu, decidido_em = now(), atualizado_em = now() where x.id = f.id;
  elsif f.status = 'aprovada' and not coalesce(p_aprovar, false) then
    perform set_config('crm.resumo', format('Cancelou a ficha %s antes do disparo', f.codigo), true);
    update crm.ficha_disparo x set status = 'reprovada', aprovado_por = null, aprovado_em = null, decidido_por = v_eu, decidido_em = now(),
           motivo_status = 'Cancelada pelo gestor antes do disparo.', atualizado_em = now()
     where x.id = f.id;
  else
    return crm.res(false, 'Ficha não está aguardando aprovação.');
  end if;
  perform set_config('crm.resumo', '', true);
  return crm.res(true);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_m = message_text;
  return crm.res(false, v_m);
end
$$;

-- ─── 10. Grants das funções e conferência ───────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('log_registrar', 'ts_ou_agora', 'status_rank', 'mensagem_json', 'grupo_rapido', 'chaves_contato', 'optout_chaves', 'pessoa_optout',
                                'supressao_motivo', 'template_render', 'whatsapp_conversa_para', 'ficha_calcular', 'ficha_codigo',
                                'whatsapp_chave_webhook', 'whatsapp_credenciais_envio', 'whatsapp_entrada', 'whatsapp_status',
                                'whatsapp_processar', 'whatsapp_webhook', 'whatsapp_reprocessar', 'fichas_liberar', 'whatsapp_fila_tem',
                                'whatsapp_fila_pegar', 'whatsapp_fila_resultado', 'whatsapp_templates_sincronizar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- montagem do JSON (pura, sem leitura) usada pelas RPCs invoker
  grant execute on function crm.mensagem_json(crm.mensagem, uuid) to authenticated;
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_conversas', 'crm_mensagens', 'crm_templates', 'crm_fichas', 'crm_whatsapp_status',
                                'crm_enviar_mensagem', 'crm_marcar_conversa_lida', 'crm_salvar_ficha', 'crm_decidir_ficha') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

do $confere$
declare v_aberto text; v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('crm_conversas', 'crm_mensagens', 'crm_templates', 'crm_fichas', 'crm_whatsapp_status',
                       'crm_enviar_mensagem', 'crm_marcar_conversa_lida', 'crm_salvar_ficha', 'crm_decidir_ficha');
  if v_n <> 9 then raise exception '20261006b: esperava 9 RPCs, achou %', v_n; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006b: função executável por anon/PUBLIC: %', v_aberto; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where p.pronamespace = 'crm'::regnamespace
     and p.proname in ('whatsapp_chave_webhook', 'whatsapp_credenciais_envio', 'whatsapp_webhook', 'whatsapp_fila_pegar',
                       'whatsapp_fila_resultado', 'fichas_liberar', 'whatsapp_templates_sincronizar', 'supressao_motivo')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'));
  if v_aberto is not null then raise exception '20261006b: função interna executável por authenticated/service_role: %', v_aberto; end if;
  select string_agg(table_name || ':' || privilege_type || ':' || grantee, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC') or (grantee = 'authenticated' and privilege_type <> 'SELECT')
                                   or (grantee = 'authenticated' and table_name in ('supressao', 'integracao_evento')));
  if v_aberto is not null then raise exception '20261006b: grant indevido em crm: %', v_aberto; end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind = 'r' and not c.relrowsecurity) then
    raise exception '20261006b: tabela crm sem RLS';
  end if;
  if coalesce((select c.whatsapp_ligado or c.envio_ligado from crm.config c), true) then
    raise exception '20261006b: whatsapp_ligado/envio_ligado não podem ser ligados aqui';
  end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamadas separadas; nada disto roda na migration) ═══════════════════════════════
-- 1. Vault (painel → Vault; NUNCA em arquivo/chat): infobip_api_key (chave "App" da Infobip, permissão WhatsApp),
--    crm_whatsapp_webhook_chave e crm_whatsapp_envio_chave (gerar 32+ bytes aleatórios cada).
-- 2. Número de envio (o que termina em 7717946; E.164 sem "+", com 55 e DDD):
--      insert into crm.numero_whatsapp (numero, nome) values ('<55DDDNÚMERO>', 'Comercial oficial');
--      update crm.config set whatsapp_numero_id = (select id from crm.numero_whatsapp where numero = '<55DDDNÚMERO>');
-- 3. Deploy das Edges (verify_jwt = false nas duas; entradas no config.toml): crm-whatsapp-webhook, crm-whatsapp-enviar.
-- 4. Infobip (portal → Numbers/Subscriptions): URL de entrada, de relatório de entrega e de visto =
--    https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-webhook, autenticação Basic com senha =
--    crm_whatsapp_webhook_chave (ou header x-crm-chave).
-- 5. Templates (só leitura na Infobip): POST na Edge crm-whatsapp-enviar com {"acao":"templates"}; diário:
--      select cron.schedule('crm-whatsapp-templates', '15 6 * * *', $c$ select ops.cron_post('crm-whatsapp-templates',
--        url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
--        headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
--                   (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
--        body := '{"acao":"templates"}'::jsonb, timeout_milliseconds := 15000) $c$);
-- 6. Ligar entrada: update crm.config set whatsapp_ligado = true;   (escrita_ligada já ligada na F2)
--      select cron.schedule('crm-whatsapp-reprocessar', '*/10 * * * *', 'select crm.whatsapp_reprocessar()');
-- 7. Ligar envio (por último, depois de 1 mensagem de teste para um número da equipe):
--      select cron.schedule('crm-whatsapp-enviar', '* * * * *', $c$ select ops.cron_post('crm-whatsapp-enviar',
--        url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
--        headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
--                   (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
--        body := '{"acao":"enviar"}'::jsonb, timeout_milliseconds := 60000) where crm.whatsapp_fila_tem() $c$);
--      update crm.config set envio_ligado = true;

-- ═══ REVERSÃO ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- update crm.config set envio_ligado = false;              -- para o envio em ~10 s (fila espera e depois expira)
-- update crm.config set whatsapp_ligado = false;           -- para tudo (webhook guarda bruto sem processar)
-- select cron.unschedule('crm-whatsapp-enviar'); select cron.unschedule('crm-whatsapp-reprocessar'); select cron.unschedule('crm-whatsapp-templates');
-- Drop (só sem dado real; com dado: exportar mensagem/conversa/integracao_evento antes), numa transação:
-- drop function public.crm_conversas(int), public.crm_mensagens(uuid,int), public.crm_templates(), public.crm_fichas(int),
--   public.crm_whatsapp_status(), public.crm_enviar_mensagem(uuid,text,uuid), public.crm_marcar_conversa_lida(uuid),
--   public.crm_salvar_ficha(jsonb,boolean), public.crm_decidir_ficha(uuid,boolean);
-- drop function crm.whatsapp_templates_sincronizar(text,jsonb), crm.whatsapp_fila_resultado(uuid,int,text,text,boolean),
--   crm.whatsapp_fila_pegar(int), crm.whatsapp_fila_tem(), crm.fichas_liberar(), crm.whatsapp_reprocessar(int),
--   crm.whatsapp_webhook(jsonb), crm.whatsapp_processar(bigint), crm.whatsapp_status(jsonb,text), crm.whatsapp_entrada(jsonb),
--   crm.whatsapp_credenciais_envio(), crm.whatsapp_chave_webhook(), crm.ficha_codigo(text), crm.ficha_calcular(uuid,text),
--   crm.whatsapp_conversa_para(uuid,uuid), crm.template_render(crm.template,uuid,text), crm.supressao_motivo(uuid,text),
--   crm.pessoa_optout(uuid), crm.optout_chaves(uuid[],text[],text[]), crm.chaves_contato(uuid), crm.grupo_rapido(uuid), crm.mensagem_json(crm.mensagem,uuid), crm.status_rank(text),
--   crm.ts_ou_agora(text), crm.log_registrar(text,text,text,uuid,text,jsonb);
-- drop table crm.ficha_destinatario, crm.mensagem, crm.conversa, crm.ficha_disparo, crm.integracao_evento, crm.supressao;
-- alter table crm.config drop column whatsapp_numero_id, drop column envio_ligado, drop column infobip_base_url,
--   drop column envio_lote, drop column envio_validade_min, drop column disparo_validade_min,
--   drop column disparo_max_destinatarios, drop column optout_palavras;
-- drop table crm.template, crm.numero_whatsapp;
