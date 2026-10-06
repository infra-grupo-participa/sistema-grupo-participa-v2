-- F3 do Comercial — Hotmart (eventos das 2 contas → jornada da pessoa e negócio) + aviso no Slack por fila
--
-- STATUS: APLICADA em produção em 06/10/2026 (versão 20261006043612 crm_f3_hotmart em supabase_migrations.schema_migrations).
-- md5 do statement gravado = 1cb7e9ec0654b43fba1cfac4b6f4f207 (= este arquivo SEM esta linha de STATUS e a seguinte;
-- antes dizia "STATUS: ver o .explain.md…"). Nada ligado: hotmart_ligado/slack_ligado false, hotmart_desde null, sem cron.
-- Exige a F2 (crm_f2_escrita) aplicada: a guarda abaixo aborta se faltar.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §5.1, §5.7, §6 (F3), §8 (D7, D8, R6).
--
-- O QUE FAZ
-- 1. Sem webhook novo: triggers em cs.hotmart_eventos (edge hotmart-events-webhook, tempo real, conta academy) e em
-- fin.hotmart_transacoes (edge hotmart-sync, as 2 contas, ~26 min; INSERT e UPDATE quando o status muda). As duas
-- fontes caem na MESMA chave 'tx:<conta>:<transação>:<classe>' ('ev:<id>' no carrinho): 1 processamento por fato.
-- 2. Classe: APPROVED/COMPLETE → aprovada; BILLET_PRINTED/PRINTED_BILLET/WAITING_PAYMENT → compra_em_aberto;
-- CANCELED/CANCELLED → cartao_recusado (D7, medido); EXPIRED → expirada; OUT_OF_SHOPPING_CART →
-- carrinho_abandonado; REFUNDED → reembolso; CHARGEBACK → chargeback; PROTEST/PROTESTED → disputa. DELAYED/OVERDUE
-- e CLUB_* ficam fora.
-- 3. Pessoa por E-MAIL (pessoas.resolver, F0) + evento em pessoas.eventos (compra | checkout | reembolso). Sem CPF.
-- 4. Negócio só de produto vinculado ao comercial, em funil tipo 'hotmart' que escuta a classe; ganho só por aqui
-- (crm.ganho_hotmart); reembolso/chargeback marcam reembolsado_em; notificações pela F2 (e aqui no ganho direto).
-- 5. Oferta fora do catálogo: negócio sem oferta + aviso + pedido de catálogo (crm.hotmart_catalogo_disparar).
-- 6. Slack por fila (crm.slack_fila), URL só do Vault pelo nome 'crm_slack_webhook'; texto sem e-mail/telefone.
-- 7. Kill-switches em crm.config: hotmart_ligado, hotmart_desde (null = nada processa), slack_ligado. Os triggers
-- saem na 1ª linha lendo só crm.config; toda exceção é engolida (a gravação da edge nunca aborta).
-- 8. RPCs do gestor: public.crm_hotmart_painel, public.crm_hotmart_reprocessar.
-- NADA é agendado nem ligado aqui: ver bloco LIGAR no fim.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- 0. Guarda de premissa
do $guarda$
declare v_falta text;
begin
  -- F2 aplicada: exatamente os objetos da F2 que a F3 usa (só a F2 os cria; não exige as 22 RPCs, que a F3 não chama)
  select string_agg(f, ', ') into v_falta
    from unnest(array['crm.escolher_dono(uuid,uuid)', 'crm.garantir_pc(uuid)', 'crm.nome_pessoa(uuid)', 'crm.nome_perfil(uuid)',
                      'crm.vendedor_ativo(uuid)', 'crm.campos_faltando(jsonb,uuid,uuid)', 'crm.tg_negocio_regras()',
                      'crm.tg_negocio_notifica()']) f
   where to_regprocedure(f) is null;
  if v_falta is not null then raise exception '20261006a: F2 (20261005t) não aplicada (faltam: %)', v_falta; end if;
  if (select count(*) from pg_trigger t where t.tgrelid = 'crm.negocio'::regclass and not t.tgisinternal
         and t.tgname in ('negocio_regras', 'negocio_notifica_ins', 'negocio_notifica_upd')) <> 3 then
    raise exception '20261006a: triggers negocio_regras/negocio_notifica_* da F2 ausentes';
  end if;
  if position('crm.ganho_hotmart' in (select p.prosrc from pg_proc p where p.oid = 'crm.tg_negocio_regras()'::regprocedure)) = 0 then
    raise exception '20261006a: crm.tg_negocio_regras não conhece a porta crm.ganho_hotmart';
  end if;
  -- F3 não aplicada
  if to_regclass('crm.hotmart_processado') is not null or to_regclass('crm.slack_fila') is not null
     or to_regprocedure('crm.hotmart_processar(jsonb)') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                   and column_name in ('hotmart_desde', 'slack_ligado')) then
    raise exception '20261006a: F3 já aplicada (objetos existem)';
  end if;
  if coalesce((select c.hotmart_ligado from crm.config c), true) then
    raise exception '20261006a: crm.config.hotmart_ligado deveria estar false';
  end if;
  if exists (select 1 from pg_trigger t where t.tgrelid in ('cs.hotmart_eventos'::regclass, 'fin.hotmart_transacoes'::regclass)
                and not t.tgisinternal and t.tgname like '%crm%') then
    raise exception '20261006a: já existe trigger do CRM nas fontes Hotmart';
  end if;
  -- fontes
  select string_agg(x.s || '.' || x.t || '.' || x.c, ', ') into v_falta
    from (values ('cs','hotmart_eventos','id'), ('cs','hotmart_eventos','evento'), ('cs','hotmart_eventos','transacao'),
                 ('cs','hotmart_eventos','email'), ('cs','hotmart_eventos','payload'), ('cs','hotmart_eventos','recebido_em'),
                 ('fin','hotmart_transacoes','conta'), ('fin','hotmart_transacoes','transacao'), ('fin','hotmart_transacoes','status'),
                 ('fin','hotmart_transacoes','comprador_email'), ('fin','hotmart_transacoes','comprador_nome'),
                 ('fin','hotmart_transacoes','comprador_telefone'), ('fin','hotmart_transacoes','produto_id'),
                 ('fin','hotmart_transacoes','oferta_codigo'), ('fin','hotmart_transacoes','valor_cobrado'),
                 ('fin','hotmart_transacoes','metodo'), ('fin','hotmart_transacoes','origem_sck'),
                 ('fin','hotmart_transacoes','recorrencia'), ('fin','hotmart_transacoes','aprovado_em'),
                 ('fin','hotmart_transacoes','pedido_em'), ('fin','produtos','conta'), ('fin','produtos','sincroniza'),
                 ('fin','ofertas','preco'), ('fin','hotmart_contas','conta')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then raise exception '20261006a: colunas ausentes: %', v_falta; end if;
  if (select count(*) from fin.hotmart_contas where conta in ('academy', 'escritorio')) <> 2 then
    raise exception '20261006a: fin.hotmart_contas sem academy/escritorio';
  end if;
  -- CHECKs da F0 que esta migration reescreve: têm de estar como a F0 deixou (senão apagaríamos valor em silêncio)
  select string_agg(x.n, ', ') into v_falta
    from (values
      ('eventos_tipo_check', 'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text])))'),
      ('eventos_fonte_check', 'CHECK ((fonte = ANY (ARRAY[''formulario''::text, ''crm''::text, ''importacao''::text, ''sistema''::text])))'),
      ('eventos_ref_tipo_check', 'CHECK (((ref_tipo IS NULL) OR (ref_tipo = ANY (ARRAY[''crm.negocio''::text, ''public.compras''::text, ''public.thb_alunos''::text, ''public.compradores''::text, ''pessoas.pessoas''::text, ''pessoas.revisao''::text]))))'),
      ('identificadores_origem_check', 'CHECK ((origem = ANY (ARRAY[''formulario''::text, ''crm''::text, ''importacao''::text])))')
    ) x(n, def)
   where not exists (select 1 from pg_constraint c
                      where c.conrelid in ('pessoas.eventos'::regclass, 'pessoas.identificadores'::regclass)
                        and c.conname = x.n and pg_get_constraintdef(c.oid) = x.def);
  if v_falta is not null then raise exception '20261006a: CHECK diferente do esperado: %', v_falta; end if;
  select string_agg(f, ', ') into v_falta
    from unnest(array['pessoas.resolver(text,text,text,text,boolean,uuid)', 'pessoas.anexar(uuid,text,text,text,text)',
                      'pessoas.norm_email(text)', 'pessoas.norm_telefone(text)', 'pessoas.chave_telefone(text)',
                      'pessoas.atual(uuid)', 'pessoas.grupo(uuid)', 'net.http_post(text,jsonb,jsonb,jsonb,integer)',
                      'ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)']) f
   where to_regprocedure(f) is null;
  if v_falta is not null then raise exception '20261006a: funções ausentes: %', v_falta; end if;
  if to_regclass('vault.decrypted_secrets') is null or to_regclass('net._http_response') is null then
    raise exception '20261006a: vault.decrypted_secrets ou net._http_response ausente';
  end if;
end
$guarda$;

-- 1. Valores novos nos CHECKs da F0 e kill-switches
-- Só ACRESCENTA valores (lista antiga conferida na guarda). Tabelas da F0 (pessoas.*) ainda pequenas.
alter table pessoas.eventos drop constraint eventos_tipo_check;
alter table pessoas.eventos add constraint eventos_tipo_check check (tipo in ('lead', 'mql', 'nao_mql', 'cadastro', 'compra',
  'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso'));
alter table pessoas.eventos drop constraint eventos_fonte_check;
alter table pessoas.eventos add constraint eventos_fonte_check check (fonte in ('formulario', 'crm', 'importacao', 'sistema', 'hotmart'));
alter table pessoas.eventos drop constraint eventos_ref_tipo_check;
alter table pessoas.eventos add constraint eventos_ref_tipo_check check (ref_tipo is null or ref_tipo in ('crm.negocio',
  'public.compras', 'public.thb_alunos', 'public.compradores', 'pessoas.pessoas', 'pessoas.revisao', 'hotmart.transacao', 'hotmart.evento'));
alter table pessoas.identificadores drop constraint identificadores_origem_check;
alter table pessoas.identificadores add constraint identificadores_origem_check check (origem in ('formulario', 'crm', 'importacao', 'hotmart'));

alter table crm.config add column hotmart_desde timestamptz; -- corte: nada antes vira negócio (D8)
alter table crm.config add column slack_ligado boolean not null default false; -- envio da fila do Slack
comment on column crm.config.hotmart_ligado is 'F3: liga os triggers em cs.hotmart_eventos e fin.hotmart_transacoes (false = saem na 1ª linha).';
comment on column crm.config.hotmart_desde is 'F3: evento Hotmart anterior a isto não vira negócio (sem retroativo, D8). null = nada é processado.';
comment on column crm.config.slack_ligado is 'F3: crm.slack_enviar() só posta com true e com o segredo crm_slack_webhook no Vault.';

-- 2. Tabelas
-- Uma linha por FATO Hotmart processado (idempotência). Sem e-mail, nome, telefone ou documento: só referência à fonte.
create table crm.hotmart_processado (
  chave text primary key check (length(chave) between 4 and 300), -- tx:<conta>:<transação>:<classe> | ev:<id>
  fonte text not null check (fonte in ('webhook', 'sync')),
  ref text not null check (length(ref) between 1 and 200), -- cs.hotmart_eventos.id | <conta>:<transação>
  conta text,
  classe text not null check (classe in ('aprovada', 'compra_em_aberto', 'cartao_recusado', 'expirada',
                                                 'carrinho_abandonado', 'reembolso', 'chargeback', 'disputa')),
  transacao text,
  produto_id text,
  oferta_codigo text,
  oferta_orfa boolean not null default false,
  quando timestamptz,
  pessoa_id uuid, -- pessoas.pessoas, sem FK (alias)
  negocio_id uuid, -- crm.negocio, sem FK (só referência)
  resultado text not null default 'processando' check (length(resultado) <= 300),
  processado_em timestamptz not null default now(),
  tentativas smallint not null default 1
);
alter table crm.hotmart_processado enable row level security;
create index hotmart_processado_em_idx on crm.hotmart_processado (processado_em desc);
create index hotmart_processado_erro_idx on crm.hotmart_processado (processado_em desc) where resultado like 'erro%';
create index hotmart_processado_orfa_idx on crm.hotmart_processado (conta, processado_em desc) where oferta_orfa;
comment on table crm.hotmart_processado is 'F3: idempotência e resultado do processamento de cada fato Hotmart (webhook + sync). Sem dado pessoal.';

-- Fila de avisos para o Slack. Texto sem e-mail/telefone/documento. Sem FK: sobrevive a tudo; expira em 24 h sem envio.
create table crm.slack_fila (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('reembolso', 'chargeback', 'disputa', 'oferta_orfa', 'erro_hotmart')),
  ref text not null check (length(ref) between 1 and 300),
  texto text not null check (length(texto) between 1 and 1500),
  criado_em timestamptz not null default now(),
  tentativas smallint not null default 0,
  request_id bigint, -- net.http_post em voo (reconciliado com net._http_response)
  tentado_em timestamptz,
  enviado_em timestamptz,
  descartado_em timestamptz,
  erro text check (erro is null or length(erro) <= 300),
  unique (tipo, ref) -- o mesmo aviso não entra 2×
);
alter table crm.slack_fila enable row level security;
create index slack_fila_pendente_idx on crm.slack_fila (id) where enviado_em is null and descartado_em is null;

-- Último pedido de atualização de catálogo por conta (limita a 1×/6 h).
create table crm.hotmart_catalogo_pedido (
  conta text primary key,
  pedido_em timestamptz not null,
  request_id bigint
);
alter table crm.hotmart_catalogo_pedido enable row level security;

-- 3. Funções internas (sem grant: só triggers/RPCs definer, donas postgres)
create function crm.ms_para_ts(p text) returns timestamptz
language sql immutable set search_path = '' as $$
  select case when p ~ '^\d{10,14}$' then to_timestamp(p::numeric / 1000) end;
$$;

create function crm.num_ou_null(p text) returns numeric
language sql immutable set search_path = '' as $$
  select case when p ~ '^-?\d{1,12}(\.\d{1,6})?$' then p::numeric end;
$$;

-- Webhook (nome do evento; o CS acrescenta ':PRODUTO_NAO_MAPEADO', que não decide nada aqui).
create function crm.hotmart_classe_evento(p text) returns text
language sql immutable set search_path = '' as $$
  select case split_part(coalesce(p, ''), ':', 1)
    when 'PURCHASE_APPROVED' then 'aprovada' when 'PURCHASE_COMPLETE' then 'aprovada'
    when 'PURCHASE_BILLET_PRINTED' then 'compra_em_aberto'
    when 'PURCHASE_CANCELED' then 'cartao_recusado' when 'PURCHASE_EXPIRED' then 'expirada'
    when 'PURCHASE_OUT_OF_SHOPPING_CART' then 'carrinho_abandonado'
    when 'PURCHASE_REFUNDED' then 'reembolso' when 'PURCHASE_CHARGEBACK' then 'chargeback'
    when 'PURCHASE_PROTEST' then 'disputa' end;
$$;

-- Espelho do hotmart-sync (status da API de vendas).
create function crm.hotmart_classe_status(p text) returns text
language sql immutable set search_path = '' as $$
  select case coalesce(p, '')
    when 'APPROVED' then 'aprovada' when 'COMPLETE' then 'aprovada'
    when 'PRINTED_BILLET' then 'compra_em_aberto' when 'WAITING_PAYMENT' then 'compra_em_aberto'
    when 'CANCELLED' then 'cartao_recusado' when 'EXPIRED' then 'expirada'
    when 'REFUNDED' then 'reembolso' when 'PARTIALLY_REFUNDED' then 'reembolso'
    when 'CHARGEBACK' then 'chargeback' when 'PROTESTED' then 'disputa' when 'DISPUTE' then 'disputa' end;
$$;

-- Linha de cs.hotmart_eventos (to_jsonb) → fato normalizado. null = não é evento comercial.
create function crm.hotmart_norm_evento(j jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare d jsonb := j -> 'payload' -> 'data'; v_classe text := crm.hotmart_classe_evento(j ->> 'evento');
        v_conta text; v_tx text; v_q timestamptz;
begin
  if v_classe is null then return null; end if;
  select pr.conta into v_conta from fin.produtos pr where pr.produto_id = d -> 'product' ->> 'id';
  v_conta := coalesce(v_conta, 'academy'); -- o webhook é o da Academy (medido: 100% dos produtos em 30 d)
  v_tx := nullif(btrim(coalesce(j ->> 'transacao', d -> 'purchase' ->> 'transaction', '')), '');
  if v_classe = 'aprovada' then v_q := crm.ms_para_ts(d -> 'purchase' ->> 'approved_date'); end if;
  v_q := coalesce(v_q, crm.ms_para_ts(j -> 'payload' ->> 'creation_date'), crm.ms_para_ts(j -> 'payload' ->> 'creationDate'),
                  (j ->> 'recebido_em')::timestamptz, now());
  return jsonb_build_object(
    'fonte', 'webhook', 'ref', j ->> 'id', 'classe', v_classe, 'conta', v_conta, 'transacao', v_tx,
    'chave', case when v_tx is not null then 'tx:' || v_conta || ':' || v_tx || ':' || v_classe
                  else 'ev:' || coalesce(nullif(j -> 'payload' ->> 'id', ''), 'cs' || (j ->> 'id')) end,
    'email', coalesce(nullif(j ->> 'email', ''), d -> 'buyer' ->> 'email'),
    'nome', d -> 'buyer' ->> 'name',
    'telefone', coalesce(nullif(d -> 'buyer' ->> 'checkout_phone', ''), d -> 'buyer' ->> 'phone'),
    'produto_id', d -> 'product' ->> 'id',
    'oferta_codigo', nullif(d -> 'purchase' -> 'offer' ->> 'code', ''),
    'valor', crm.num_ou_null(d -> 'purchase' -> 'price' ->> 'value'),
    'metodo', d -> 'purchase' -> 'payment' ->> 'type',
    'sck', nullif(d -> 'purchase' -> 'origin' ->> 'sck', ''),
    'recorrencia', crm.num_ou_null(d -> 'purchase' ->> 'recurrence_number'),
    'quando', v_q);
end
$$;

-- Linha do espelho do hotmart-sync (to_jsonb) → fato normalizado. null = status sem classe (OVERDUE etc.).
create function crm.hotmart_norm_sync(j jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare v_classe text := crm.hotmart_classe_status(j ->> 'status'); v_tx text := nullif(btrim(coalesce(j ->> 'transacao', '')), '');
begin
  if v_classe is null or v_tx is null or coalesce(j ->> 'conta', '') = '' then return null; end if;
  return jsonb_build_object(
    'fonte', 'sync', 'ref', (j ->> 'conta') || ':' || v_tx, 'classe', v_classe, 'conta', j ->> 'conta', 'transacao', v_tx,
    'chave', 'tx:' || (j ->> 'conta') || ':' || v_tx || ':' || v_classe,
    'email', j ->> 'comprador_email', 'nome', j ->> 'comprador_nome', 'telefone', j ->> 'comprador_telefone',
    'produto_id', j ->> 'produto_id', 'oferta_codigo', nullif(j ->> 'oferta_codigo', ''),
    'valor', crm.num_ou_null(j ->> 'valor_cobrado'), 'metodo', j ->> 'metodo', 'sck', nullif(j ->> 'origem_sck', ''),
    'recorrencia', crm.num_ou_null(j ->> 'recorrencia'),
    -- checkout pelo pedido (frescor de 48 h); aprovada pela aprovação; reembolso/disputa: o espelho não tem a data → agora
    'quando', case when v_classe = 'aprovada' then coalesce(j ->> 'aprovado_em', j ->> 'pedido_em')
                   when v_classe in ('compra_em_aberto', 'cartao_recusado', 'expirada') then j ->> 'pedido_em' end);
end
$$;

-- Slack: escapa & < > (formato mrkdwn) e corta.
create function crm.slack_esc(p text) returns text
language sql immutable set search_path = '' as $$
  select left(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), 300);
$$;

create function crm.slack_enfileirar(p_tipo text, p_ref text, p_texto text) returns void
language sql set search_path = '' as $$
  insert into crm.slack_fila (tipo, ref, texto) values (p_tipo, left(p_ref, 300), left(p_texto, 1500))
  on conflict (tipo, ref) do nothing;
$$;

-- Primeiro nome só (o Slack não recebe nome completo, e-mail, telefone nem documento).
create function crm.primeiro_nome(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(split_part(btrim(crm.nome_pessoa(p)), ' ', 1), ''), 'contato');
$$;

-- O núcleo. Chamado só por crm.hotmart_entrada (que segura o erro). Devolve o resultado gravado.
create function crm.hotmart_processar(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_chave text := p ->> 'chave';
  v_classe text := p ->> 'classe';
  v_tx text := p ->> 'transacao';
  v_quando timestamptz := coalesce((p ->> 'quando')::timestamptz, now());
  v_desde timestamptz;
  v_email text := pessoas.norm_email(p ->> 'email');
  v_tel text := pessoas.norm_telefone(p ->> 'telefone');
  v_nome text := nullif(left(btrim(coalesce(p ->> 'nome', '')), 160), '');
  v_ins int; v_res jsonb; v_pessoa uuid; v_atual uuid; v_g uuid[];
  pc crm.produto_comercial%rowtype; v_linha_nome text; v_oferta text; v_orfa boolean := false; v_valor numeric;
  n crm.negocio%rowtype; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pcid uuid; v_camp uuid; v_neg uuid;
  v_criados int := 0; v_abertos int := 0; v_funis int := 0; v_resultado text; v_rotulo text; v_sinc boolean;
begin
  -- 1. idempotência (PK). Reprocesso explícito ('forcar') reaproveita a linha.
  if coalesce((p ->> 'forcar')::boolean, false) then
    update crm.hotmart_processado x set resultado = 'processando', processado_em = now(), tentativas = x.tentativas + 1
     where x.chave = v_chave;
  else
    insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, quando)
    values (v_chave, p ->> 'fonte', p ->> 'ref', p ->> 'conta', v_classe, v_tx, p ->> 'produto_id', p ->> 'oferta_codigo', v_quando)
    on conflict (chave) do nothing;
    get diagnostics v_ins = row_count;
    if v_ins = 0 then return 'duplicado'; end if;
  end if;

  perform set_config('crm.canal', 'hotmart', true); -- crm.tg_log: autor_tipo 'integracao'
  select c.hotmart_desde into v_desde from crm.config c; -- crm.hotmart_entrada garante não nulo

  -- 2. pessoa por e-mail (F0). Sem e-mail não há pessoa (o webhook sempre manda; medido 0 sem e-mail em PURCHASE_*).
  if v_email is null then
    v_resultado := 'sem_email';
  elsif v_quando < v_desde - interval '1 hour' and v_classe <> 'reembolso' and v_classe <> 'chargeback' then
    v_resultado := 'antes_do_corte'; -- D8: sem retroativo (reembolso de venda antiga ainda marca o negócio, se houver)
  end if;
  if v_resultado is not null then
    update crm.hotmart_processado x set resultado = v_resultado where x.chave = v_chave;
    return v_resultado;
  end if;

  v_res := pessoas.resolver(v_nome, v_email, v_tel, null, false, null);
  v_pessoa := (v_res ->> 'pessoa_id')::uuid;
  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, 'hotmart');
  if v_tel is not null then perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'hotmart'); end if;
  v_atual := pessoas.atual(v_pessoa);
  v_g := pessoas.grupo(v_atual);

  -- 3. jornada da pessoa (toda classe, todo produto das 2 contas)
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe, quando)
  values (v_atual,
          case when v_classe = 'aprovada' then 'compra'
               when v_classe in ('reembolso', 'chargeback', 'disputa') then 'reembolso' else 'checkout' end,
          'hotmart', case when v_tx is not null then 'hotmart.transacao' else 'hotmart.evento' end,
          left(coalesce(v_tx, p ->> 'ref'), 80),
          jsonb_strip_nulls(jsonb_build_object('classe', v_classe, 'conta', p ->> 'conta', 'produto', p ->> 'produto_id',
                            'oferta', p ->> 'oferta_codigo', 'valor', p -> 'valor', 'metodo', p ->> 'metodo',
                            'recorrencia', p -> 'recorrencia', 'sck', p ->> 'sck', 'casou_por', v_res ->> 'como')),
          v_quando);

  -- 4. camada comercial: só produto vinculado ao comercial com linha
  select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  if not found then
    update crm.hotmart_processado x set resultado = 'jornada: produto fora do comercial', pessoa_id = v_atual where x.chave = v_chave;
    return 'jornada: produto fora do comercial';
  end if;
  select l.nome into v_linha_nome from crm.linha l where l.chave = pc.linha;

  -- oferta: só entra no negócio se estiver no catálogo (FK fin.ofertas). Fora = aviso (catalogar no mesmo dia).
  if p ->> 'oferta_codigo' is not null then
    select o.oferta_codigo into v_oferta from fin.ofertas o where o.oferta_codigo = p ->> 'oferta_codigo';
    if v_oferta is null then
      v_orfa := true;
      select pr.sincroniza into v_sinc from fin.produtos pr where pr.produto_id = pc.produto_id;
      perform crm.slack_enfileirar('oferta_orfa', p ->> 'oferta_codigo',
        format(':label: *Oferta fora do catálogo* · %s · oferta %s (conta %s). Catalogar hoje em Comercial › Produtos%s.',
               crm.slack_esc(coalesce(pc.nome_comercial, v_linha_nome)), crm.slack_esc(p ->> 'oferta_codigo'),
               crm.slack_esc(p ->> 'conta'),
               case when coalesce(v_sinc, false) then '' else ' (o produto está com sincronização de ofertas desligada no Financeiro)' end));
    end if;
  end if;
  v_valor := coalesce((p ->> 'valor')::numeric,
                      (select o.preco from fin.ofertas o where o.oferta_codigo = v_oferta),
                      (select l.ticket_ref from crm.linha l where l.chave = pc.linha), 0);
  v_valor := greatest(round(v_valor, 2), 0);

  -- 5. por classe
  if v_classe = 'aprovada' then
    if coalesce((p ->> 'recorrencia')::numeric, 1) > 1 then
      v_resultado := 'jornada: recorrência ' || (p ->> 'recorrencia') || ' não é venda nova';
    elsif v_tx is null then
      v_resultado := 'jornada: aprovada sem transação';
    elsif exists (select 1 from crm.negocio x where x.transacao_ganho = v_tx) then
      v_resultado := 'ja_ganho';
    else
      select * into n from crm.negocio x
       where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
       order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
       limit 1 for update;
      if found then
        select e.id into v_etapa from crm.etapa_funil e
         where e.funil_id = n.funil_id and e.papel = 'fechado' and e.arquivada_em is null;
        perform set_config('crm.resumo', format('Venda aprovada na Hotmart (transação %s): negócio ganho', v_tx), true);
        perform set_config('crm.ganho_hotmart', 'on', true);
        update crm.negocio x
           set status = 'ganho', etapa_id = v_etapa, etapa_desde = now(), fechado_em = v_quando, transacao_ganho = v_tx,
               valor = v_valor, oferta_codigo = coalesce(v_oferta, x.oferta_codigo), ultima_interacao_em = now(),
               atualizado_em = now()
         where x.id = n.id;
        perform set_config('crm.ganho_hotmart', 'off', true);
        v_neg := n.id; v_resultado := 'ganho';
      else
        select * into f from crm.funil x
         where x.ativo and x.tipo = 'hotmart' and x.linha = pc.linha and 'compra_aprovada' = any(x.eventos_hotmart)
           and (pc.agrupador_id is null or x.agrupador_id = pc.agrupador_id)
         order by x.criado_em, x.id limit 1;
        if not found then
          v_resultado := 'jornada: venda sem negócio aberto e sem funil de compra aprovada';
        else
          select e.id into v_etapa from crm.etapa_funil e where e.funil_id = f.id and e.papel = 'fechado' and e.arquivada_em is null;
          select x.dono_id into v_dono from crm.pessoa_comercial x
           where x.pessoa_id = any(v_g) and x.dono_id is not null order by x.pessoa_id = v_atual desc, x.criado_em limit 1;
          if v_dono is not null and not crm.vendedor_ativo(v_dono) then v_dono := null; end if;
          v_pcid := crm.garantir_pc(v_atual);
          select c.id into v_camp from crm.campanha c where c.funil_id = f.id and c.ativa and c.canal = 'hotmart' order by c.criado_em limit 1;
          perform set_config('crm.resumo', format('Venda aprovada na Hotmart (transação %s): negócio criado já ganho em %s', v_tx, f.nome), true);
          perform set_config('crm.ganho_hotmart', 'on', true);
          insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, status, dono_id, valor, oferta_codigo,
                                   campos, transacao_ganho, utm, fechado_em, ultima_interacao_em)
          values (v_atual, f.id, v_etapa, v_camp, pc.linha, 'compra_aprovada', 'ganho', v_dono, v_valor, v_oferta,
                  jsonb_build_object('origem', 'Hotmart · compra aprovada'), v_tx,
                  case when p ->> 'sck' is not null then jsonb_build_object('sck', p ->> 'sck') else '{}'::jsonb end,
                  v_quando, now())
          returning id into v_neg;
          perform set_config('crm.ganho_hotmart', 'off', true);
          -- o trigger da F2 só avisa venda_aprovada em UPDATE para ganho: o negócio que já nasce ganho avisa aqui
          if v_dono is not null and not exists (select 1 from crm.preferencias_notificacao x
                                                 where x.perfil_id = v_dono and (x.gatilhos ->> 'venda_aprovada') = 'false') then
            insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
            values (v_dono, 'venda_aprovada', v_neg::text, left('Venda aprovada: ' || crm.nome_pessoa(v_atual), 200),
                    left(coalesce(v_linha_nome, pc.linha) || ' · pagamento aprovado na Hotmart.', 500), '/comercial/funil?negocio=' || v_neg)
            on conflict (perfil_id, gatilho, ref_id) do nothing;
          end if;
          v_resultado := 'ganho: negócio novo';
        end if;
      end if;
    end if;

  elsif v_classe in ('carrinho_abandonado', 'compra_em_aberto', 'cartao_recusado', 'expirada') then
    if v_quando < now() - interval '48 hours' then
      v_resultado := 'jornada: checkout com mais de 48 h';
    elsif exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = any(v_g) and x.opt_out) then
      v_resultado := 'jornada: opt-out';
    elsif exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'ganho'
                     and x.fechado_em > now() - interval '30 days') then
      v_resultado := 'jornada: já comprou a linha em 30 dias';
    else
      for f in select x.* from crm.funil x
                where x.ativo and x.tipo = 'hotmart' and x.linha = pc.linha and v_classe = any(x.eventos_hotmart)
                  and (pc.agrupador_id is null or x.agrupador_id = pc.agrupador_id)
                order by x.criado_em, x.id loop
        v_funis := v_funis + 1;
        perform pg_advisory_xact_lock(hashtext('crm.dist:' || f.id::text)); -- mesmo lock de crm_criar_negocio (F2)
        if exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.funil_id = f.id and x.status = 'aberto') then
          v_abertos := v_abertos + 1;
          continue;
        end if;
        select e.id into v_etapa from crm.etapa_funil e where e.funil_id = f.id and e.arquivada_em is null order by e.ordem limit 1;
        continue when v_etapa is null;
        v_dono := crm.escolher_dono(v_atual, f.id);
        v_pcid := crm.garantir_pc(v_atual);
        if v_dono is not null then
          perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição, Hotmart)', crm.nome_pessoa(v_atual), crm.nome_perfil(v_dono)), true);
          update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pcid and x.dono_id is null;
        end if;
        select c.id into v_camp from crm.campanha c where c.funil_id = f.id and c.ativa and c.canal = 'hotmart' order by c.criado_em limit 1;
        v_rotulo := case v_classe when 'carrinho_abandonado' then 'carrinho abandonado' when 'compra_em_aberto' then 'boleto/pix gerado'
                                  when 'cartao_recusado' then 'cartão recusado' else 'pagamento expirado' end;
        perform set_config('crm.resumo', format('Hotmart: %s → negócio em %s (dono: %s)', v_rotulo, f.nome, crm.nome_perfil(v_dono)), true);
        insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, oferta_codigo, campos, utm,
                                 ultima_interacao_em)
        values (v_atual, f.id, v_etapa, v_camp, pc.linha, v_classe, v_dono, v_valor, v_oferta,
                jsonb_build_object('origem', 'Hotmart · ' || v_rotulo),
                case when p ->> 'sck' is not null then jsonb_build_object('sck', p ->> 'sck') else '{}'::jsonb end, null)
        returning id into v_neg;
        v_criados := v_criados + 1;
      end loop;
      v_resultado := case when v_criados > 0 then 'negocio_criado: ' || v_criados
                          when v_abertos > 0 then 'ja_aberto'
                          when v_funis = 0 then 'jornada: nenhum funil hotmart da linha escuta ' || v_classe
                          else 'jornada: funil sem etapa' end;
    end if;

  elsif v_classe in ('reembolso', 'chargeback') then
    perform set_config('crm.resumo', format('Hotmart: %s da transação %s', v_classe, coalesce(v_tx, '?')), true);
    update crm.negocio x set reembolsado_em = coalesce(x.reembolsado_em, now()), atualizado_em = now()
     where v_tx is not null and x.transacao_ganho = v_tx and x.reembolsado_em is null
     returning * into n;
    if found then
      v_neg := n.id; v_resultado := v_classe || '_marcado';
      perform crm.slack_enfileirar(v_classe, coalesce(v_tx, v_chave),
        format(':rotating_light: *%s* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               case when v_classe = 'reembolso' then 'Reembolso' else 'Chargeback' end,
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
    else
      v_resultado := 'jornada: sem negócio ganho desta transação';
    end if;

  elsif v_classe = 'disputa' then
    select * into n from crm.negocio x where v_tx is not null and x.transacao_ganho = v_tx;
    if found then
      v_neg := n.id; v_resultado := 'disputa_avisada';
      perform crm.slack_enfileirar('disputa', coalesce(v_tx, v_chave),
        format(':warning: *Disputa aberta na Hotmart* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
    else
      v_resultado := 'jornada: disputa sem negócio ganho';
    end if;
  end if;

  perform set_config('crm.resumo', '', true);
  update crm.hotmart_processado x
     set resultado = left(coalesce(v_resultado, 'ok'), 300), pessoa_id = v_atual, negocio_id = v_neg, oferta_orfa = v_orfa
   where x.chave = v_chave;
  return v_resultado;
end
$$;

-- Porta única: kill-switch + isolamento de erro. NUNCA propaga exceção para quem gravou a fonte.
create function crm.hotmart_entrada(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare v text; v_s text; v_m text;
begin
  if p is null then return 'ignorado'; end if;
  if not coalesce((select c.hotmart_ligado from crm.config c), false) then return 'desligado'; end if;
  if (select c.hotmart_desde from crm.config c) is null then return 'desligado: falta hotmart_desde'; end if;
  begin
    v := crm.hotmart_processar(p);
  exception when others then
    get stacked diagnostics v_s = returned_sqlstate, v_m = message_text;
    v := left('erro: ' || v_s || ' ' || v_m, 300);
    begin
      insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, resultado)
      values (p ->> 'chave', p ->> 'fonte', p ->> 'ref', p ->> 'conta', p ->> 'classe', p ->> 'transacao', p ->> 'produto_id',
              p ->> 'oferta_codigo', v)
      on conflict (chave) do update
         set resultado = excluded.resultado, processado_em = now(),
             tentativas = crm.hotmart_processado.tentativas + case when coalesce((p ->> 'forcar')::boolean, false) then 1 else 0 end;
      perform crm.slack_enfileirar('erro_hotmart', p ->> 'chave',
        format(':x: *Hotmart → CRM falhou* · %s · %s (%s). Ver Comercial › Integrações; reprocessar depois de corrigir.',
               crm.slack_esc(p ->> 'classe'), crm.slack_esc(p ->> 'chave'), crm.slack_esc(v_s)));
    exception when others then
      raise warning 'crm.hotmart_entrada: não registrou o erro (%): %', sqlstate, sqlerrm;
    end;
  end;
  perform set_config('crm.canal', '', true);
  perform set_config('crm.resumo', '', true);
  perform set_config('crm.ganho_hotmart', 'off', true);
  return v;
end
$$;

-- Triggers das fontes. 1ª linha: kill-switch (só lê crm.config; desligado ou sem hotmart_desde = sai sem tocar em mais
-- nada). Toda exceção — inclusive query_canceled (statement_timeout), que "others" não pega — é engolida: a gravação da
-- edge é preservada (manual §10, R6).
create function crm.tg_hotmart_evento() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    if not coalesce((select c.hotmart_ligado and c.hotmart_desde is not null from crm.config c), false) then return null; end if;
    perform crm.hotmart_entrada(crm.hotmart_norm_evento(to_jsonb(new)));
  exception when others or query_canceled then
    raise warning 'crm.tg_hotmart_evento: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;

create function crm.tg_hotmart_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    if not coalesce((select c.hotmart_ligado and c.hotmart_desde is not null from crm.config c), false) then return null; end if;
    perform crm.hotmart_entrada(crm.hotmart_norm_sync(to_jsonb(new)));
  exception when others or query_canceled then
    raise warning 'crm.tg_hotmart_sync: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;

-- Fila do Slack. Para cron de 2 min (NÃO agendado aqui): reconcilia o que foi postado e posta até 5 pendentes.
-- p_simular = true: não posta (ensaio). URL do webhook só do Vault, pelo nome; nunca em tabela, log ou retorno.
create function crm.slack_enviar(p_simular boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_url text; r record; v_id bigint; v_ok int := 0; v_err int := 0; v_env int := 0; v_desc int := 0;
begin
  if not coalesce((select c.slack_ligado from crm.config c), false) then
    return jsonb_build_object('ok', false, 'motivo', 'desligado');
  end if;
  -- 1. reconcilia (resposta casada pelo id E pela hora: o id do pg_net é reciclado)
  update crm.slack_fila f set enviado_em = h.created, request_id = null, erro = null
    from net._http_response h
   where f.request_id = h.id and f.enviado_em is null and h.created >= f.tentado_em - interval '1 minute'
     and h.status_code = 200;
  get diagnostics v_ok = row_count;
  update crm.slack_fila f
     set request_id = null,
         erro = left(coalesce('HTTP ' || h.status_code || ' ' || left(coalesce(h.content, ''), 80),
                              case when h.timed_out then 'timeout' end, h.error_msg, 'falhou'), 300)
    from net._http_response h
   where f.request_id = h.id and f.enviado_em is null and h.created >= f.tentado_em - interval '1 minute'
     and coalesce(h.status_code, 0) <> 200;
  get diagnostics v_err = row_count;
  update crm.slack_fila f set request_id = null, erro = 'sem resposta em 30 min'
   where f.request_id is not null and f.enviado_em is null and f.tentado_em < now() - interval '30 minutes';
  -- 2. descarta velho (aviso de ontem não ajuda) e o que já tentou 5×
  update crm.slack_fila f set descartado_em = now()
   where f.enviado_em is null and f.descartado_em is null and f.request_id is null
     and (f.criado_em < now() - interval '24 hours' or f.tentativas >= 5);
  get diagnostics v_desc = row_count;
  -- 3. posta (Slack aceita ~1/s por webhook: 5 por rodada)
  if not exists (select 1 from crm.slack_fila f where f.enviado_em is null and f.descartado_em is null and f.request_id is null) then
    return jsonb_build_object('ok', true, 'confirmados', v_ok, 'falhas', v_err, 'descartados', v_desc, 'postados', 0);
  end if;
  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'crm_slack_webhook';
  if v_url is null or v_url !~ '^https://hooks\.slack\.com/' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_segredo', 'confirmados', v_ok, 'falhas', v_err, 'descartados', v_desc);
  end if;
  for r in select f.id, f.texto from crm.slack_fila f
            where f.enviado_em is null and f.descartado_em is null and f.request_id is null
            order by f.id limit 5 for update skip locked loop
    if p_simular then
      v_id := null;
    else
      v_id := net.http_post(url := v_url, body := jsonb_build_object('text', r.texto),
                            headers := '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds := 10000);
    end if;
    update crm.slack_fila f set request_id = v_id, tentado_em = now(), tentativas = f.tentativas + 1 where f.id = r.id;
    v_env := v_env + 1;
  end loop;
  return jsonb_build_object('ok', true, 'confirmados', v_ok, 'falhas', v_err, 'descartados', v_desc, 'postados', v_env,
                            'simulado', p_simular);
end
$$;

-- Oferta órfã de produto comercial → pede o catálogo da conta à edge hotmart-sync (no máximo 1×/6 h por conta).
-- Para cron de hora em hora (NÃO agendado aqui). p_simular = true: diz o que pediria, sem HTTP.
create function crm.hotmart_catalogo_disparar(p_simular boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v_id bigint; v_chave text; v_pedidos jsonb := '[]';
begin
  if not coalesce((select c.hotmart_ligado from crm.config c), false) then
    return jsonb_build_object('ok', false, 'motivo', 'desligado');
  end if;
  for r in select distinct h.conta from crm.hotmart_processado h
             join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial
             join fin.produtos pr on pr.produto_id = h.produto_id and pr.sincroniza
            where h.oferta_orfa and h.processado_em > now() - interval '7 days' and h.conta is not null
              and not exists (select 1 from fin.ofertas o where o.oferta_codigo = h.oferta_codigo)
              and not exists (select 1 from crm.hotmart_catalogo_pedido q
                               where q.conta = h.conta and q.pedido_em > now() - interval '6 hours') loop
    if not p_simular then
      select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'fin_hotmart_sync_chave';
      if v_chave is null then return jsonb_build_object('ok', false, 'motivo', 'sem_segredo'); end if;
      v_id := ops.cron_post('crm-hotmart-catalogo',
                url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/hotmart-sync',
                headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-chave', v_chave),
                body := jsonb_build_object('catalogo', true, 'conta', r.conta), timeout_milliseconds := 150000);
      insert into crm.hotmart_catalogo_pedido (conta, pedido_em, request_id) values (r.conta, now(), v_id)
      on conflict (conta) do update set pedido_em = excluded.pedido_em, request_id = excluded.request_id;
    end if;
    v_pedidos := v_pedidos || to_jsonb(r.conta);
  end loop;
  return jsonb_build_object('ok', true, 'contas', v_pedidos, 'simulado', p_simular);
end
$$;

-- 4. Triggers nas fontes (tabelas de outras equipes: só AFTER, só leitura de NEW, exceção engolida)
create trigger zz_crm_hotmart_evento after insert on cs.hotmart_eventos
  for each row when (new.evento like 'PURCHASE\_%') execute function crm.tg_hotmart_evento();
create trigger zz_crm_hotmart_sync_ins after insert on fin.hotmart_transacoes
  for each row execute function crm.tg_hotmart_sync();
create trigger zz_crm_hotmart_sync_upd after update on fin.hotmart_transacoes
  for each row when (old.status is distinct from new.status) execute function crm.tg_hotmart_sync();

-- 5. RPCs do gestor
-- Saúde da integração (sem dado pessoal): chaves, contagens por fonte/classe/resultado, erros recentes, fila do Slack.
create function public.crm_hotmart_painel(p_dias int default 7) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_d int := least(greatest(coalesce(p_dias, 7), 1), 90); v_desde timestamptz;
begin
  if not coalesce(crm.eh_gestor(), false) then
    raise exception 'Só o gestor do Comercial vê a integração.' using errcode = '42501';
  end if;
  v_desde := now() - make_interval(days => v_d);
  return jsonb_build_object(
    'hotmartLigado', (select c.hotmart_ligado from crm.config c),
    'slackLigado', (select c.slack_ligado from crm.config c),
    'desde', (select c.hotmart_desde from crm.config c),
    'ultimoProcessadoEm', (select max(h.processado_em) from crm.hotmart_processado h),
    'porResultado', coalesce((select jsonb_agg(jsonb_build_object('fonte', x.fonte, 'classe', x.classe, 'resultado', x.res, 'n', x.n)
                                                order by x.n desc)
                                from (select h.fonte, h.classe, split_part(h.resultado, ':', 1) res, count(*) n
                                        from crm.hotmart_processado h where h.processado_em >= v_desde group by 1, 2, 3) x), '[]'::jsonb),
    'erros', coalesce((select jsonb_agg(jsonb_build_object('chave', x.chave, 'classe', x.classe, 'resultado', x.resultado,
                                                           'em', x.processado_em, 'tentativas', x.tentativas) order by x.processado_em desc)
                         from (select * from crm.hotmart_processado h where h.resultado like 'erro%' and h.processado_em >= v_desde
                                order by h.processado_em desc limit 50) x), '[]'::jsonb),
    'ofertasOrfas', coalesce((select jsonb_agg(distinct h.oferta_codigo) from crm.hotmart_processado h
                               where h.oferta_orfa and h.processado_em >= v_desde
                                 and not exists (select 1 from fin.ofertas o where o.oferta_codigo = h.oferta_codigo)), '[]'::jsonb),
    'slack', (select jsonb_build_object('pendentes', count(*) filter (where f.enviado_em is null and f.descartado_em is null),
                                        'enviados', count(*) filter (where f.enviado_em >= v_desde),
                                        'descartados', count(*) filter (where f.descartado_em >= v_desde))
                from crm.slack_fila f where f.criado_em >= v_desde or (f.enviado_em is null and f.descartado_em is null)));
end
$$;

-- Refaz UM fato com erro, relendo a fonte. Só gestor; respeita o kill-switch.
create function public.crm_hotmart_reprocessar(p_chave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h crm.hotmart_processado%rowtype; v_j jsonb; v_conta text; v_tx text; v text;
begin
  if not coalesce(crm.eh_gestor(), false) then
    return jsonb_build_object('ok', false, 'msg', 'Só o gestor do Comercial reprocessa.');
  end if;
  if not coalesce((select c.hotmart_ligado from crm.config c), false) then
    return jsonb_build_object('ok', false, 'msg', 'Integração Hotmart desligada.');
  end if;
  select * into h from crm.hotmart_processado x where x.chave = p_chave for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Evento não encontrado.'); end if;
  if h.resultado not like 'erro%' then return jsonb_build_object('ok', false, 'msg', 'Só evento com erro é reprocessado.'); end if;
  if h.fonte = 'webhook' then
    select crm.hotmart_norm_evento(to_jsonb(e)) into v_j from cs.hotmart_eventos e where e.id = (h.ref)::bigint;
  else
    v_conta := split_part(h.ref, ':', 1);
    v_tx := substr(h.ref, length(v_conta) + 2);
    select crm.hotmart_norm_sync(to_jsonb(t)) into v_j
      from (select * from fin.hotmart_transacoes where conta = v_conta) t where t.transacao = v_tx;
  end if;
  if v_j is null or v_j ->> 'chave' is distinct from h.chave then
    return jsonb_build_object('ok', false, 'msg', 'A fonte mudou ou sumiu: não dá para refazer este evento.');
  end if;
  v := crm.hotmart_entrada(v_j || jsonb_build_object('forcar', true));
  return jsonb_build_object('ok', v not like 'erro%', 'msg', v);
end
$$;

-- 6. Grants e conferência
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('ms_para_ts', 'num_ou_null', 'hotmart_classe_evento', 'hotmart_classe_status', 'hotmart_norm_evento',
                                'hotmart_norm_sync', 'slack_esc', 'slack_enfileirar', 'primeiro_nome', 'hotmart_processar',
                                'hotmart_entrada', 'tg_hotmart_evento', 'tg_hotmart_sync', 'slack_enviar', 'hotmart_catalogo_disparar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  revoke all on function public.crm_hotmart_painel(int), public.crm_hotmart_reprocessar(text) from public, anon, service_role;
  grant execute on function public.crm_hotmart_painel(int), public.crm_hotmart_reprocessar(text) to authenticated;
end
$grants$;
revoke all on crm.hotmart_processado, crm.slack_fila, crm.hotmart_catalogo_pedido from public, anon, authenticated, service_role;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_hotmart\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006a: executável por anon/PUBLIC: %', v_aberto; end if;
  if has_function_privilege('authenticated', 'crm.hotmart_processar(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'crm.slack_enviar(boolean)', 'execute')
     or has_function_privilege('service_role', 'crm.hotmart_entrada(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_hotmart_painel(integer)', 'execute') then
    raise exception '20261006a: grants das funções fora do esperado';
  end if;
  if exists (select 1 from information_schema.role_table_grants
              where table_schema = 'crm' and table_name in ('hotmart_processado', 'slack_fila', 'hotmart_catalogo_pedido')
                and grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role')) then
    raise exception '20261006a: tabela nova com grant indevido';
  end if;
  if not exists (select 1 from pg_class c where c.oid = 'crm.hotmart_processado'::regclass and c.relrowsecurity)
     or not exists (select 1 from pg_class c where c.oid = 'crm.slack_fila'::regclass and c.relrowsecurity) then
    raise exception '20261006a: RLS desligada em tabela nova';
  end if;
  if coalesce((select c.hotmart_ligado or c.slack_ligado from crm.config c), true) then
    raise exception '20261006a: kill-switches devem nascer desligados';
  end if;
end
$confere$;

-- LIGAR (o Arthur, depois do ok, em chamadas separadas; desliga do mesmo jeito com false)
-- Pré: F2 ligada (escrita_ligada) e ao menos 1 produto vinculado (crm_vincular_produto) + 1 funil tipo 'hotmart' da linha.
-- update crm.config set hotmart_desde = now(), hotmart_ligado = true;
-- Slack (depois de criar no Vault o segredo 'crm_slack_webhook' com a URL do webhook do canal do Comercial):
-- select vault.create_secret('<url>', 'crm_slack_webhook'); -- pelo painel; a URL nunca vai para arquivo
-- update crm.config set slack_ligado = true;
-- select cron.schedule('crm-slack-fila', '*/2 * * * *',
-- $$select crm.slack_enviar() where exists (select 1 from crm.slack_fila where enviado_em is null and descartado_em is null)$$);
-- Catálogo sob demanda (oferta órfã de produto comercial):
-- select cron.schedule('crm-hotmart-catalogo', '50 * * * *',
-- $$select crm.hotmart_catalogo_disparar() where exists (select 1 from crm.hotmart_processado where oferta_orfa and processado_em > now() - interval '7 days')$$);

-- REVERSÃO (numa transação; o que a F3 gravou em crm.negocio/pessoas.eventos fica, com canal 'hotmart' no log)
-- update crm.config set hotmart_ligado = false, slack_ligado = false; -- desliga em ~10 s, sem deploy (preferir isto)
-- select cron.unschedule('crm-slack-fila'); select cron.unschedule('crm-hotmart-catalogo'); -- se agendados
-- drop trigger zz_crm_hotmart_evento on cs.hotmart_eventos;
-- drop trigger zz_crm_hotmart_sync_ins on fin.hotmart_transacoes; drop trigger zz_crm_hotmart_sync_upd on fin.hotmart_transacoes;
-- drop function public.crm_hotmart_painel(int), public.crm_hotmart_reprocessar(text), crm.hotmart_catalogo_disparar(boolean),
-- crm.slack_enviar(boolean), crm.tg_hotmart_sync(), crm.tg_hotmart_evento(), crm.hotmart_entrada(jsonb),
-- crm.hotmart_processar(jsonb), crm.primeiro_nome(uuid), crm.slack_enfileirar(text,text,text), crm.slack_esc(text),
-- crm.hotmart_norm_sync(jsonb), crm.hotmart_norm_evento(jsonb), crm.hotmart_classe_status(text),
-- crm.hotmart_classe_evento(text), crm.num_ou_null(text), crm.ms_para_ts(text);
-- drop table crm.hotmart_catalogo_pedido, crm.slack_fila, crm.hotmart_processado; -- exportar antes se tiver dado
-- alter table crm.config drop column slack_ligado, drop column hotmart_desde;
-- (os valores novos dos CHECKs de pessoas.* ficam: removê-los exige apagar eventos 'hotmart' — não fazer)
