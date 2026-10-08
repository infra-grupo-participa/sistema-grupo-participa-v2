-- 20261005s: ENSAIO da F1 (não aplica nada: tudo termina em ROLLBACK). Rodado em produção (mbvybujpkwuorhtdzcde) em
-- 05–06/10/2026, em partes (cada chamada do MCP bem abaixo de 25 s, cada uma com seu begin … rollback):
--   PARTE A (este arquivo, até o "rollback" da PARTE A): o corpo INTEIRO da migration + provas funcionais e de RLS.
--   PARTE B (fim do arquivo): massa sintética 10× + medições/planos (explain analyze 2×). Reaplica só o necessário.
--   PARTE C: conferência separada de que nada persistiu.
-- Como rodar: cada parte inteira de uma vez (SQL editor, psql ou execute_sql), como postgres. O resultado vai para a temp
-- _z_out; o select antes do rollback mostra tudo. Esperado: NENHUMA linha começando com "ERRADO".
-- Dados fictícios: e-mails @exemplo.com.br. Perfis reais (admin = gestor, visualizador, vendedores reais mp/ro) são
-- escolhidos por SELECT e só booleanos/contagens saem. O comprador real da prova 5.jornada_real só aparece em contagens.
--
-- ═══ PARTE A ═════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;

-- ═══ CORPO DA MIGRATION (copiado sem mudança de 20261005s_crm_f1_leitura.sql; mudou a migration, gerar de novo) ═══
-- 20261005s: F1 do Comercial — modelo de dados do CRM + RPCs de LEITURA (nenhuma escrita)
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Ensaio: 20261005s_ensaio.sql (begin … rollback, 3 partes).
-- Medidas e planos: 20261005s.explain.md. Desenho: docs/projetos/comercial/backend-arquitetura.md §2.5, 3.3, 3.4,
-- 3.5, 3.8, 4.1–4.5, 6 (F1) e 7; convergência: docs/projetos/comercial/convergencia-pessoas-crm.md (a pessoa é
-- pessoas.pessoas, NÃO crm.pessoa). Depende da F0 (20261005r, versão 20261006012515), lida VIVA antes de escrever
-- (crm.tg_log, eh_gestor/eh_vendedor/eh_comercial idênticos ao arquivo da F0).
--
-- O QUE FAZ
--   1. Tabelas do CRM (schema crm, NÃO exposto no PostgREST): linha, agrupador, produto_comercial (sobre fin.produtos),
--      oferta_comercial (sobre fin.ofertas), campo_def, modelo_funil, modelo_projeto, funil, etapa_funil, campanha,
--      motivo_perda, distribuicao, pessoa_comercial (atributos comerciais 1:1 de pessoas.pessoas, criada sob demanda),
--      negocio, atividade, nota, dashboard, painel, preferencias_notificacao, notificacao.
--      Nada apaga histórico: FKs RESTRICT (agrupador/funil/etapa/motivo/vendedor são arquivados ou inativados).
--      Alias da base de pessoas respeitado: toda leitura devolve contatoId = pessoas.atual(pessoa_id).
--   2. RLS em todas (D6): gestor (dev/admin, ou cargo gestor + área comercial) vê tudo; vendedor vê os seus + sem dono;
--      configuração (linha, funil, etapa, motivo, campos, produtos/ofertas) visível a quem é do comercial; o resto
--      (visualizador, equipe fora do comercial) não vê nada. Policies só por helpers SECURITY DEFINER (sem recursão).
--      Só GRANT SELECT para authenticated; nenhuma policy/grant de escrita (escrita = F2, por RPC definer).
--   3. crm.tg_log (F0) ligado em toda tabela de negócio (lista da §3.2). Triggers de integridade que cruzam tabela
--      (CHECK não aceita subquery): campos do negócio × crm.campo_def, campos obrigatórios da etapa × campo_def,
--      oferta vigente só com produto vinculado, motivo de fábrica imutável (só nota/ativo/ordem).
--   4. Seeds: 6 linhas, 1 agrupador por linha, 6 campos, 9 motivos de fábrica (sistema=true), 10 modelos de funil e
--      6 modelos de projeto (gerados de web/modules/comercial/domain/modelos.ts). Funis reais NÃO são criados.
--   5. RPCs de LEITURA public.crm_* (jsonb no formato camelCase de web/modules/comercial/domain/types.ts):
--        invoker + RLS : crm_sessao, crm_config, crm_agrupadores, crm_funis, crm_motivos_perda, crm_negocios,
--                        crm_atividades, crm_eventos, crm_log, crm_dashboards, crm_painel, crm_notificacoes,
--                        crm_preferencias
--        definer + guarda igual à policy (cruzam pessoas/fin/thb_alunos/compradores/controle/respondi/cs):
--                        crm_vendedores, crm_contatos, crm_jornada, crm_produtos_hotmart, crm_ofertas,
--                        crm_ofertas_orfas, crm_buscar_por_link
--      Quem não é do comercial recebe erro 42501 (nunca lista vazia/zero). Toda lista tem limite. Nunca CPF.
--      fin.hotmart_transacoes: o Comercial vende as DUAS contas (escada B = 'academy', escada A = 'escritorio'), então
--      toda leitura cita as duas na forma canônica exigida por fin.trava_conta_hotmart (event trigger), uma por conta.
--      E-mail/telefone completos só para gestor ou para o vendedor dono (ou com negócio dele); o resto, mascarado.
--   6. NENHUMA RPC de escrita. crm.config.escrita_ligada continua false.
--
-- AS 5 PERGUNTAS (números em 20261005s.explain.md)
--   escala: tabelas nascem vazias (só seeds). Medido com massa sintética 10× (20 mil pessoas comerciais, 30 mil
--     negócios, 60 mil atividades, 300 mil linhas de log) dentro de rollback. Toda lista tem limite (≤ 2.000).
--   índice: cada RPC lê pelo índice da expressão exata da fonte (hotmart_transacoes_email_idx, ix_lead_active_email_lower,
--     ix_geu_fone, respostas_email_idx, contatos_comprador_id_key, identidade_pkey/pessoa_idx) — guarda confere.
--   frequência: leitura ao abrir tela (sem cron, sem polling). Notificação por Realtime fica para a F2.
--   repetição: crm_funis traz etapas+campanhas+distribuição numa chamada; crm_negocios traz próxima atividade por lateral.
--   reversão: nada escreve nas tabelas (escrita = F2). Front volta ao mock com NEXT_PUBLIC_COMERCIAL_FONTE=mock.
--     Bloco REVERSÃO no fim (tabelas vazias: drop).
--
-- PREMISSAS (guarda aborta se faltar): F0 aplicada (crm.config/vendedor/log, crm.tg_log, helpers, pessoas.atual/grupo/
--   dados/mascara_*); nenhuma tabela da F1 nem public.crm_*; escrita_ligada=false; fin.ofertas ≥ 1.143 e fin.produtos ≥ 97;
--   índices das fontes da jornada com a expressão exata.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  if to_regclass('crm.config') is null or to_regclass('crm.vendedor') is null or to_regclass('crm.log') is null
     or to_regprocedure('crm.tg_log()') is null or to_regprocedure('crm.eh_gestor()') is null
     or to_regprocedure('crm.eh_vendedor()') is null or to_regprocedure('crm.eh_comercial()') is null
     or to_regclass('pessoas.pessoas') is null or to_regprocedure('pessoas.atual(uuid)') is null
     or to_regprocedure('pessoas.grupo(uuid)') is null or to_regprocedure('pessoas.dados(uuid)') is null
     or to_regprocedure('pessoas.mascara_email(text)') is null or to_regprocedure('pessoas.mascara_fim(text)') is null
     or to_regprocedure('pessoas.norm_email(text)') is null or to_regprocedure('pessoas.chave_telefone(text)') is null then
    raise exception '20261005s: F0 (20261005r) não aplicada ou incompleta';
  end if;
  if to_regclass('crm.linha') is not null or to_regclass('crm.negocio') is not null or to_regclass('crm.pessoa_comercial') is not null then
    raise exception '20261005s: tabelas da F1 já existem (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%') then
    raise exception '20261005s: já existem funções public.crm_*';
  end if;
  if coalesce((select c.escrita_ligada from crm.config c), true) then
    raise exception '20261005s: crm.config.escrita_ligada deveria estar false na F1';
  end if;
  if (select count(*) from fin.ofertas) < 1143 or (select count(*) from fin.produtos) < 97 then
    raise exception '20261005s: catálogo fin.ofertas/fin.produtos menor que o medido (1.143/97)';
  end if;
  select string_agg(x.i, ', ') into v_falta
    from (values
      ('fin',      'hotmart_transacoes_email_idx', '(lower(TRIM(BOTH FROM comprador_email)))'),
      ('fin',      'hotmart_transacoes_oferta_idx', '(oferta_codigo)'),
      ('fin',      'identidade_pkey',              '(no)'),
      ('fin',      'identidade_pessoa_idx',        '(pessoa_chave)'),
      ('controle', 'ix_lead_active_email_lower',   '(lower(btrim(email)))'),
      ('controle', 'ix_geu_fone',                  '(fone_key)'),
      ('respondi', 'respostas_email_idx',          '(email)'),
      ('cs',       'contatos_comprador_id_key',    '(comprador_id)')
    ) x(s, i, trecho)
   where not exists (select 1 from pg_indexes pi where pi.schemaname = x.s and pi.indexname = x.i
                        and position(x.trecho in pi.indexdef) > 0);
  if v_falta is not null then
    raise exception '20261005s: índice ausente ou com expressão diferente: %', v_falta;
  end if;
  select string_agg(x.t || '.' || x.c, ', ') into v_falta
    from (values ('fin','produtos','familia'), ('fin','produtos','conta'), ('fin','ofertas','visto_em'),
                 ('fin','ofertas','is_main_offer'), ('fin','hotmart_transacoes','origem_sck'),
                 ('controle','lead_active','opt_in_at'), ('controle','grupo_evento_unificado','group_name'),
                 ('respondi','respostas','form_slug'), ('cs','contatos','estagio_id'), ('cs','estagios','nome'),
                 ('public','thb_alunos','cidade'), ('public','compradores','endereco_estado')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then
    raise exception '20261005s: colunas ausentes: %', v_falta;
  end if;
end
$guarda$;

-- ─── 1. Helpers de visibilidade (SECURITY DEFINER, coalesce em toda guarda; usados por policies e RPCs) ──────────────
-- Erro explícito para quem não é do comercial (nunca "zero").
create function crm.exige_comercial() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(crm.eh_comercial(), false) then
    raise exception 'Sem acesso ao Comercial.' using errcode = '42501';
  end if;
end
$$;

-- Pessoa atual (fim da cadeia de alias) de um LOTE de ids: 1 chamada por RPC, não 1 por linha (medido: chamar uma
-- função guardada por linha custava 240–720 ms em 1.000 negócios; em lote, 47 ms). Só para quem é do comercial.
create function crm.atual_de(p_ids uuid[]) returns table (pessoa_id uuid, atual uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(crm.eh_comercial(), false) then return; end if;
  return query select x, pessoas.atual(x) from unnest(p_ids) x;
end
$$;

-- Grupo (atual + aliases) da pessoa. Só para quem é do comercial.
create function crm.pessoa_grupo(p_pessoa uuid) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select case when coalesce(crm.eh_comercial(), false) then pessoas.grupo(pessoas.atual(p_pessoa)) else '{}'::uuid[] end;
$$;

-- Pode ver a pessoa: gestor; vendedor se a pessoa (grupo) é dele ou sem dono, ou se tem negócio dele.
create function crm.pode_ver_pessoa(p_pessoa uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_g uuid[];
begin
  if p_pessoa is null or v_eu is null then return false; end if;
  if coalesce(crm.eh_gestor(), false) then return true; end if;
  if not coalesce(crm.eh_vendedor(), false) then return false; end if;
  v_g := pessoas.grupo(pessoas.atual(p_pessoa));
  return coalesce(
       exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and (pc.dono_id = v_eu or pc.dono_id is null))
    or exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.dono_id = v_eu), false);
end
$$;

-- ─── 2. Linha, produto e oferta (§2.5, §3.3) ─────────────────────────────────────────────────────────────────────────
create table crm.linha (                         -- família comercial (substitui o enum ProdutoKey)
  chave      text primary key check (chave ~ '^[a-z0-9_]{2,20}$'),
  nome       text not null check (length(btrim(nome)) between 1 and 80),
  escada     char(1) not null check (escada in ('A', 'B')),
  ticket_ref numeric(12,2) not null check (ticket_ref >= 0),
  ordem      smallint not null default 0,
  ativo      boolean not null default true
);

create table crm.agrupador (                     -- pasta de funis (na Clint, "agrupador" = produto)
  id           uuid primary key default gen_random_uuid(),
  nome         text not null check (length(btrim(nome)) between 1 and 80),
  linha        text references crm.linha(chave) on delete restrict,
  ordem        smallint not null default 0,
  arquivado_em timestamptz,
  criado_em    timestamptz not null default now()
);
create unique index agrupador_nome_uidx on crm.agrupador (lower(btrim(nome))) where arquivado_em is null;

create table crm.produto_comercial (             -- camada comercial sobre fin.produtos (o produto nasce na Hotmart)
  produto_id     text primary key references fin.produtos(produto_id) on delete restrict,
  no_comercial   boolean not null default false,
  nome_comercial text check (nome_comercial is null or length(btrim(nome_comercial)) between 1 and 120),
  linha          text references crm.linha(chave) on delete restrict,
  escada         char(1) check (escada in ('A', 'B')),
  agrupador_id   uuid references crm.agrupador(id) on delete restrict,
  vinculado_por  uuid references public.perfis(id) on delete restrict,
  vinculado_em   timestamptz,
  check (not no_comercial or (nome_comercial is not null and escada is not null))
);
create index produto_comercial_linha_idx on crm.produto_comercial (linha) where no_comercial;

create table crm.oferta_comercial (              -- camada comercial sobre fin.ofertas
  oferta_codigo  text primary key references fin.ofertas(oferta_codigo) on delete restrict,
  vigente        boolean not null default false,
  condicao       text check (condicao is null or length(condicao) <= 300),
  valida_ate     date,
  uso            text check (uso is null or length(uso) <= 200),
  atualizado_por uuid references public.perfis(id) on delete restrict,
  atualizado_em  timestamptz not null default now()
);

-- ─── 3. Construtor de funis (§3.4) ───────────────────────────────────────────────────────────────────────────────────
create table crm.campo_def (                     -- campos do negócio (playbook 4.3, máx. 8)
  chave  text primary key check (chave ~ '^[a-z_]{3,40}$'),
  rotulo text not null check (length(btrim(rotulo)) between 1 and 80),
  tipo   text not null check (tipo in ('texto', 'opcao', 'linha')),   -- linha = valor validado contra crm.linha
  opcoes text[],
  ordem  smallint not null default 0,
  ativo  boolean not null default true,
  check ((tipo = 'opcao') = (opcoes is not null and cardinality(opcoes) > 0))
);

create table crm.modelo_funil (                  -- modelos prontos (domain/modelos.ts); o gestor cria funis a partir deles
  id              text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  nome            text not null,
  descricao       text not null,
  icone           text not null,
  tipo            text not null check (tipo in ('manual', 'hotmart')),
  eventos_hotmart text[] not null default '{}',
  etapas          jsonb not null check (jsonb_typeof(etapas) = 'array' and jsonb_array_length(etapas) >= 2),
  campanhas       jsonb not null default '[]' check (jsonb_typeof(campanhas) = 'array'),
  ordem           smallint not null default 0
);

create table crm.modelo_projeto (
  tipo      text primary key check (tipo ~ '^[a-z_]{3,40}$'),
  nome      text not null,
  descricao text not null,
  icone     text not null,
  funis     text[] not null,
  checklist text[] not null default '{}',
  ordem     smallint not null default 0
);

create table crm.funil (
  id                   uuid primary key default gen_random_uuid(),
  nome                 text not null check (length(btrim(nome)) between 1 and 80),
  icone                text not null default 'kanban' check (icone ~ '^[a-z0-9-]{1,40}$'),
  projeto              text check (projeto ~ '^[a-z0-9-]{3,60}$'),   -- chave do projeto (= utm_campaign/ClickUp/Drive)
  agrupador_id         uuid not null references crm.agrupador(id) on delete restrict,
  linha                text not null references crm.linha(chave) on delete restrict,
  tipo                 text not null check (tipo in ('manual', 'hotmart')),
  eventos_hotmart      text[] not null default '{}'
    check (eventos_hotmart <@ array['carrinho_abandonado','compra_em_aberto','cartao_recusado','compra_aprovada','expirada','reembolso']::text[]),
  distribuicao_propria boolean not null default false,
  ativo                boolean not null default true,
  arquivado_em         timestamptz,
  criado_por           uuid references public.perfis(id) on delete restrict,
  criado_em            timestamptz not null default now(),
  check (tipo = 'manual' or cardinality(eventos_hotmart) > 0),
  check (ativo = (arquivado_em is null))
);
create index funil_agrupador_idx on crm.funil (agrupador_id);

create table crm.etapa_funil (
  id                  uuid primary key default gen_random_uuid(),
  funil_id            uuid not null references crm.funil(id) on delete restrict,
  ordem               smallint not null check (ordem >= 0),
  nome                text not null check (length(btrim(nome)) between 1 and 60),
  papel               text not null check (papel in ('primeiro_contato','qualificar','apresentar_oferta','negociar','aguardar_pagamento','fechado')),
  cor                 text not null check (cor in ('neutral','accent','info','cyan','purple','yellow','green','red')),
  sla_atencao_min     int check (sla_atencao_min > 0),
  sla_critico_min     int,
  campos_obrigatorios text[] not null default '{}',     -- validado contra crm.campo_def (trigger)
  criterio            text not null default '' check (length(criterio) <= 300),
  arquivada_em        timestamptz,
  criado_em           timestamptz not null default now(),
  unique (funil_id, id),                                 -- alvo da FK composta do negócio
  check ((sla_atencao_min is null) = (sla_critico_min is null)),
  check (sla_critico_min is null or sla_critico_min > sla_atencao_min)
);
create unique index etapa_ordem_uidx on crm.etapa_funil (funil_id, ordem) where arquivada_em is null;
create unique index etapa_nome_uidx  on crm.etapa_funil (funil_id, lower(btrim(nome))) where arquivada_em is null;
create unique index etapa_ganho_uidx on crm.etapa_funil (funil_id) where papel = 'fechado' and arquivada_em is null;

create table crm.campanha (
  id         uuid primary key default gen_random_uuid(),
  funil_id   uuid not null references crm.funil(id) on delete restrict,
  nome       text not null check (length(btrim(nome)) between 1 and 120),
  canal      text not null check (canal in ('utm','formulario','disparo','hotmart','webhook','manual')),
  regra      text not null default '' check (length(regra) <= 300),   -- legível (o que a tela mostra)
  regra_json jsonb not null default '{}' check (jsonb_typeof(regra_json) = 'object'),  -- máquina (F2/F3)
  ativa      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create index campanha_funil_idx on crm.campanha (funil_id);
create index campanha_utm_idx  on crm.campanha ((regra_json->>'utm_campaign')) where ativa and canal = 'utm';
create index campanha_form_idx on crm.campanha ((regra_json->>'form_slug')) where ativa and canal = 'formulario';

create table crm.motivo_perda (
  chave         text primary key check (chave ~ '^[a-z0-9_]{3,40}$'),
  rotulo        text not null check (length(btrim(rotulo)) between 1 and 80),
  reativa       boolean not null default false,
  bloqueia      boolean not null default false,
  alerta_gestor boolean not null default false,
  nota          text check (nota is null or length(nota) <= 300),
  sistema       boolean not null default false,
  ativo         boolean not null default true,
  ordem         smallint not null default 0,
  criado_em     timestamptz not null default now()
);

create table crm.distribuicao (                   -- funil_id null = distribuição geral do Comercial
  id            uuid primary key default gen_random_uuid(),
  funil_id      uuid references crm.funil(id) on delete restrict,
  vendedor_id   uuid not null references crm.vendedor(perfil_id) on delete restrict,
  percentual    smallint not null check (percentual between 0 and 100),
  ativo         boolean not null default true,
  atualizado_em timestamptz not null default now()
);
create unique index distribuicao_uidx on crm.distribuicao (coalesce(funil_id, '00000000-0000-0000-0000-000000000000'::uuid), vendedor_id);
create index distribuicao_vendedor_idx on crm.distribuicao (vendedor_id);

-- ─── 4. Pessoa comercial, negócio, atividade, nota (§3.5 + convergência) ────────────────────────────────────────────
-- Atributos COMERCIAIS da pessoa única (pessoas.pessoas). 1:1, criada sob demanda (F2: ao criar negócio/atribuir dono).
-- Nome/e-mail/telefone NÃO moram aqui: são lidos na hora de pessoas.dados (aluno/comprador/identificadores).
create table crm.pessoa_comercial (
  pessoa_id        uuid primary key references pessoas.pessoas(id) on delete restrict,
  dono_id          uuid references crm.vendedor(perfil_id) on delete restrict,
  perfil           text check (perfil in ('advogado', 'contador', 'outro')),
  atua_com_holding text check (atua_com_holding in ('sim', 'nao', 'comecando')),
  tags             text[] not null default '{}' check (cardinality(tags) <= 30),
  score            smallint check (score between 0 and 100),
  opt_out          boolean not null default false,          -- supressão: pediu para não receber contato
  opt_out_em       timestamptz,
  opt_out_motivo   text check (opt_out_motivo is null or length(opt_out_motivo) <= 200),
  utm_primeira     jsonb not null default '{}' check (jsonb_typeof(utm_primeira) = 'object'),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  check (opt_out = (opt_out_em is not null))
);
create index pessoa_comercial_dono_idx    on crm.pessoa_comercial (dono_id, criado_em desc) where dono_id is not null;
create index pessoa_comercial_semdono_idx on crm.pessoa_comercial (criado_em desc) where dono_id is null;
create index pessoa_comercial_criado_idx  on crm.pessoa_comercial (criado_em desc);

create table crm.negocio (
  id                  uuid primary key default gen_random_uuid(),
  pessoa_id           uuid not null references pessoas.pessoas(id) on delete restrict,   -- leitura resolve pessoas.atual
  funil_id            uuid not null references crm.funil(id) on delete restrict,
  etapa_id            uuid not null,
  campanha_id         uuid references crm.campanha(id) on delete restrict,
  linha               text not null references crm.linha(chave) on delete restrict,
  origem              text not null check (origem in ('venda_ativa','carrinho_abandonado','compra_em_aberto','cartao_recusado','compra_aprovada','expirada','reembolso')),
  status              text not null default 'aberto' check (status in ('aberto', 'ganho', 'perdido')),
  dono_id             uuid references crm.vendedor(perfil_id) on delete restrict,
  valor               numeric(12,2) not null default 0 check (valor >= 0),
  oferta_codigo       text references fin.ofertas(oferta_codigo) on delete restrict,
  campos              jsonb not null default '{}' check (jsonb_typeof(campos) = 'object'),   -- chaves/valores × crm.campo_def (trigger)
  motivo_perda        text references crm.motivo_perda(chave) on delete restrict,
  nota_perda          text check (nota_perda is null or length(nota_perda) <= 1000),
  transacao_ganho     text,            -- fin.hotmart_transacoes.transacao; sem FK: webhook chega antes da sincronização
  reembolsado_em      timestamptz,
  utm                 jsonb not null default '{}' check (jsonb_typeof(utm) = 'object'),
  criado_em           timestamptz not null default now(),
  etapa_desde         timestamptz not null default now(),
  fechado_em          timestamptz,
  ultima_interacao_em timestamptz,
  atualizado_em       timestamptz not null default now(),
  foreign key (funil_id, etapa_id) references crm.etapa_funil(funil_id, id) on delete restrict,   -- etapa é do funil
  check ((status = 'perdido') = (motivo_perda is not null)),
  check ((status = 'ganho')   = (transacao_ganho is not null)),
  check ((status = 'aberto')  = (fechado_em is null))
);
create unique index negocio_aberto_uidx    on crm.negocio (pessoa_id, funil_id) where status = 'aberto';   -- 1 aberto por pessoa+funil
create index negocio_criado_idx            on crm.negocio (criado_em desc);
create index negocio_dono_idx              on crm.negocio (dono_id, criado_em desc);
create index negocio_semdono_idx           on crm.negocio (criado_em desc) where dono_id is null;
create index negocio_funil_aberto_idx      on crm.negocio (funil_id, etapa_id) where status = 'aberto';
create index negocio_pessoa_idx            on crm.negocio (pessoa_id, criado_em desc);
create index negocio_fechado_idx           on crm.negocio (fechado_em) where status <> 'aberto';
create index negocio_oferta_idx            on crm.negocio (oferta_codigo) where oferta_codigo is not null;
create unique index negocio_transacao_uidx on crm.negocio (transacao_ganho) where transacao_ganho is not null;

create table crm.atividade (
  id           uuid primary key default gen_random_uuid(),
  negocio_id   uuid references crm.negocio(id) on delete restrict,
  pessoa_id    uuid not null references pessoas.pessoas(id) on delete restrict,
  dono_id      uuid not null references public.perfis(id) on delete restrict,   -- vendedor ou gestor
  tipo         text not null check (tipo in ('whatsapp','ligacao','email','tarefa','reuniao')),
  titulo       text not null check (length(btrim(titulo)) between 1 and 200),
  vence_em     timestamptz not null,
  concluida_em timestamptz,
  resultado    text check (resultado is null or length(resultado) <= 1000),
  cancelada    boolean not null default false,
  cadencia_dia smallint check (cadencia_dia between 1 and 5),
  criado_por   uuid references public.perfis(id) on delete restrict,
  criado_em    timestamptz not null default now(),
  check ((concluida_em is null) = (resultado is null))
);
create index atividade_dono_aberta_idx    on crm.atividade (dono_id, vence_em) where concluida_em is null;
create index atividade_negocio_aberta_idx on crm.atividade (negocio_id, vence_em) where concluida_em is null;
create index atividade_concluida_idx      on crm.atividade (concluida_em) where concluida_em is not null;
create index atividade_pessoa_idx         on crm.atividade (pessoa_id, criado_em desc);
create index atividade_negocio_idx        on crm.atividade (negocio_id) where negocio_id is not null;

create table crm.nota (
  id         uuid primary key default gen_random_uuid(),
  pessoa_id  uuid not null references pessoas.pessoas(id) on delete restrict,
  negocio_id uuid references crm.negocio(id) on delete restrict,
  texto      text not null check (length(btrim(texto)) between 1 and 5000),
  autor_id   uuid references public.perfis(id) on delete restrict,
  em         timestamptz not null default now()
);
create index nota_pessoa_idx  on crm.nota (pessoa_id, em desc);
create index nota_negocio_idx on crm.nota (negocio_id) where negocio_id is not null;

-- ─── 5. Relatórios, painel, notificações (§3.8) ─────────────────────────────────────────────────────────────────────
create table crm.dashboard (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(btrim(nome)) between 1 and 80),
  descricao     text check (descricao is null or length(descricao) <= 300),
  dono_id       uuid not null references public.perfis(id) on delete restrict,
  compartilhado boolean not null default false,
  widgets       jsonb not null default '[]' check (jsonb_typeof(widgets) = 'array' and jsonb_array_length(widgets) <= 40),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  arquivado_em  timestamptz                       -- "excluir" na tela = arquivar
);
create index dashboard_dono_idx on crm.dashboard (dono_id) where arquivado_em is null;
create index dashboard_comp_idx on crm.dashboard (atualizado_em desc) where compartilhado and arquivado_em is null;

create table crm.painel (
  perfil_id     uuid primary key references public.perfis(id) on delete restrict,
  widgets       jsonb not null check (jsonb_typeof(widgets) = 'array' and jsonb_array_length(widgets) <= 40),
  atualizado_em timestamptz not null default now()
);

create table crm.preferencias_notificacao (
  perfil_id       uuid primary key references public.perfis(id) on delete restrict,
  desktop         boolean not null default false,
  gatilhos        jsonb not null
    check (jsonb_typeof(gatilhos) = 'object'
       and (gatilhos - array['lead_novo','lead_respondeu','prazo_estourado','venda_aprovada','ficha_para_aprovar','atividade_vencendo']) = '{}'::jsonb),
  silencio_inicio time,
  silencio_fim    time,
  atualizado_em   timestamptz not null default now()
);

create table crm.notificacao (
  id        bigint generated always as identity primary key,
  perfil_id uuid not null references public.perfis(id) on delete restrict,
  gatilho   text not null check (gatilho in ('lead_novo','lead_respondeu','prazo_estourado','venda_aprovada','ficha_para_aprovar','atividade_vencendo')),
  ref_id    text not null check (length(ref_id) between 1 and 80),
  titulo    text not null check (length(titulo) <= 200),
  corpo     text not null check (length(corpo) <= 500),
  href      text not null check (href ~ '^/comercial/'),
  em        timestamptz not null default now(),
  lida_em   timestamptz,
  unique (perfil_id, gatilho, ref_id)               -- cron e trigger (F2) não duplicam aviso
);
create index notificacao_perfil_idx on crm.notificacao (perfil_id, em desc);

-- ─── 5b. Conjuntos de visibilidade do vendedor (SQL: precisam das tabelas acima) ──────────────────────────────────
-- Usados nas policies como "coluna IN (select crm.f())": o Postgres calcula o conjunto UMA vez por consulta (hashed
-- SubPlan). Medido: uma função chamada por linha (papel + alias por linha) custava ~3 ms/linha; com 300 mil linhas de
-- log o vendedor passava de 20 s. SECURITY DEFINER (lê as tabelas sem RLS: sem recursão de policy), sem papel aqui (as
-- policies checam papel antes, por initplan), e só devolve ids do próprio auth.uid().
create function crm.pessoas_negocio_meu() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct n.pessoa_id from crm.negocio n where n.dono_id = (select auth.uid());
$$;

create function crm.pessoas_do_vendedor() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pc.pessoa_id from crm.pessoa_comercial pc where pc.dono_id = (select auth.uid()) or pc.dono_id is null
  union
  select n.pessoa_id from crm.negocio n where n.dono_id = (select auth.uid());
$$;

-- ─── 6. Triggers de integridade (CHECK não aceita subquery: trigger que cruza tabela) ────────────────────────────────
create function crm.tg_negocio_campos() returns trigger
language plpgsql set search_path = '' as $$
declare r record; d record; v text;
begin
  if tg_op = 'UPDATE' and new.campos is not distinct from old.campos then return new; end if;
  for r in select e.key, e.value from jsonb_each(new.campos) e loop
    select * into d from crm.campo_def c where c.chave = r.key and c.ativo;
    if not found then
      raise exception 'Campo "%" não existe no cadastro de campos.', r.key using errcode = '23514';
    end if;
    if jsonb_typeof(r.value) not in ('string', 'null') then
      raise exception 'Campo "%" precisa ser texto.', r.key using errcode = '23514';
    end if;
    v := nullif(btrim(r.value #>> '{}'), '');
    continue when v is null;
    if d.tipo = 'opcao' and not (v = any(d.opcoes)) then
      raise exception 'Valor "%" não é opção de "%".', v, d.rotulo using errcode = '23514';
    end if;
    if d.tipo = 'linha' and not exists (select 1 from crm.linha l where l.chave = v) then
      raise exception 'Produto "%" não é uma linha do comercial.', v using errcode = '23514';
    end if;
  end loop;
  return new;
end
$$;
create trigger negocio_campos before insert or update on crm.negocio for each row execute function crm.tg_negocio_campos();

create function crm.tg_etapa_campos() returns trigger
language plpgsql set search_path = '' as $$
declare v_falta text;
begin
  select string_agg(c, ', ') into v_falta from unnest(new.campos_obrigatorios) c
   where not exists (select 1 from crm.campo_def d where d.chave = c and d.ativo);
  if v_falta is not null then
    raise exception 'Campo obrigatório fora do cadastro: %.', v_falta using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger etapa_campos before insert or update on crm.etapa_funil for each row execute function crm.tg_etapa_campos();

create function crm.tg_oferta_vigente() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.vigente and not exists (select 1 from fin.ofertas o
                                   join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial
                                  where o.oferta_codigo = new.oferta_codigo) then
    raise exception 'Vincule o produto ao comercial antes de marcar oferta vigente.' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger oferta_vigente before insert or update on crm.oferta_comercial for each row execute function crm.tg_oferta_vigente();

create function crm.tg_motivo_sistema() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.sistema then raise exception 'Motivo de fábrica não se apaga: desative.' using errcode = '23514'; end if;
    raise exception 'Motivo de perda não se apaga: desative.' using errcode = '23514';
  end if;
  if old.sistema and (new.chave, new.rotulo, new.reativa, new.bloqueia, new.alerta_gestor, new.sistema)
                     is distinct from (old.chave, old.rotulo, old.reativa, old.bloqueia, old.alerta_gestor, old.sistema) then
    raise exception 'Motivo de fábrica só muda nota, ativo e ordem.' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger motivo_sistema before update or delete on crm.motivo_perda for each row execute function crm.tg_motivo_sistema();

-- Log (F0, crm.tg_log): AFTER INSERT/DELETE + AFTER UPDATE WHEN (old.* is distinct from new.*), sem "OF" (manual §7).
-- Lista = §3.2 (sem mensagem/fila_item/ficha/link: F2/F4). Fora: linha, campo_def, modelos, notificacao (seed/derivado).
do $log$
declare r record;
begin
  for r in select * from (values
      ('agrupador', 'agrupador', 'id'), ('funil', 'funil', 'id'), ('etapa_funil', 'etapa', 'id'),
      ('campanha', 'campanha', 'id'), ('motivo_perda', 'motivo', 'chave'), ('distribuicao', 'distribuicao', 'id'),
      ('produto_comercial', 'produto', 'produto_id'), ('oferta_comercial', 'oferta', 'oferta_codigo'),
      ('pessoa_comercial', 'contato', 'pessoa_id'), ('negocio', 'negocio', 'id'), ('atividade', 'atividade', 'id'),
      ('nota', 'nota', 'id'), ('dashboard', 'dashboard', 'id'), ('painel', 'painel', 'perfil_id'),
      ('preferencias_notificacao', 'preferencias', 'perfil_id')) x(tabela, entidade, col)
  loop
    execute format('create trigger %I after insert or delete on crm.%I for each row execute function crm.tg_log(%L, %L)',
                   r.tabela || '_log_ins_del', r.tabela, r.entidade, r.col);
    execute format('create trigger %I after update on crm.%I for each row when (old.* is distinct from new.*) '
                   'execute function crm.tg_log(%L, %L)', r.tabela || '_log_upd', r.tabela, r.entidade, r.col);
  end loop;
end
$log$;

-- ─── 7. Seeds ────────────────────────────────────────────────────────────────────────────────────────────────────────
select set_config('crm.canal', 'migracao', true);
select set_config('crm.resumo', '', true);

insert into crm.linha (chave, nome, escada, ticket_ref, ordem) values   -- domain/catalogo.ts PRODUTOS
  ('ht',      'Holding Total',          'B',    297, 1),
  ('acelera', 'Acelera Holding',        'B',   2997, 2),
  ('hm',      'Holding Masters',        'B',  30000, 3),
  ('aurum',   'Aurum',                  'B', 100000, 4),
  ('ethb',    'ETHB',                   'B',    997, 5),
  ('sv',      'Sessão de Viabilidade',  'A',   1200, 6);

insert into crm.agrupador (nome, linha, ordem) select l.nome, l.chave, l.ordem from crm.linha l order by l.ordem;

insert into crm.campo_def (chave, rotulo, tipo, opcoes, ordem) values   -- domain/catalogo.ts ROTULO_CAMPO/OPCOES_CAMPO
  ('perfil_profissional', 'Perfil profissional',  'opcao', array['advogado','contador','outro'], 1),
  ('atua_com_holding',    'Já atua com holding',  'opcao', array['sim','comecando','nao'], 2),
  ('produto_interesse',   'Produto de interesse', 'linha', null, 3),
  ('origem',              'Origem do lead',       'texto', null, 4),
  ('objecao_principal',   'Objeção principal',    'opcao', array['preco','pensar','socio_conjuge','momento','ja_sei','sem_cliente','outra'], 5),
  ('forma_pagamento',     'Forma de pagamento',   'opcao', array['cartao','pix','boleto'], 6);

insert into crm.motivo_perda (chave, rotulo, reativa, bloqueia, alerta_gestor, nota, sistema, ordem) values  -- playbook 4.4
  ('fora_do_perfil',             'Fora do perfil',                   false, false, false, null, true, 1),
  ('tentativas_esgotadas',       'Tentativas de contato esgotadas',  false, false, false, null, true, 2),
  ('sem_interesse',              'Sem interesse',                    false, false, false, null, true, 3),
  ('nao_e_o_momento',            'Não é o momento',                  true,  false, false, 'Volta para reativação', true, 4),
  ('sem_condicao_financeira',    'Sem condição financeira agora',    true,  false, false, 'Volta para reativação', true, 5),
  ('comprou_outro_produto',      'Comprou outro produto da casa',    false, false, false, null, true, 6),
  ('contato_invalido',           'Contato inválido',                 false, false, false, null, true, 7),
  ('pediu_sem_contato',          'Pediu para não receber contato',  false, true,  false, 'Vai para a lista de bloqueio', true, 8),
  ('ja_atendido_outro_vendedor', 'Já atendido por outro vendedor',   false, false, true,  'Falha de distribuição: o gestor trata no mesmo dia', true, 9);

-- Modelos de funil e de projeto: gerados de web/modules/comercial/domain/modelos.ts (etapas/campanhas em camelCase, como
-- o tipo ModeloFunil). Mudou o modelo no front, nova migration.
insert into crm.modelo_funil (id, nome, descricao, icone, tipo, eventos_hotmart, etapas, campanhas, ordem) values
  ('venda_ativa', 'Venda ativa', 'As 6 etapas do playbook. Onde o comercial trabalha lead que pediu contato ou veio de lista.', 'kanban', 'manual', array[]::text[], '[{"nome":"Fazer primeiro contato","papel":"primeiro_contato","cor":"info","slaAtencaoMin":5,"slaCriticoMin":15,"criterio":"O lead respondeu","camposObrigatorios":[]},{"nome":"Qualificar","papel":"qualificar","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Campos de qualificação preenchidos","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Apresentar a oferta","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":2880,"slaCriticoMin":4320,"criterio":"Oferta apresentada e lead pediu condição ou link","camposObrigatorios":[]},{"nome":"Negociar","papel":"negociar","cor":"accent","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Lead escolheu a forma de pagamento","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado na Hotmart","camposObrigatorios":["forma_pagamento"]},{"nome":"Fechado","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Captação {chave}","canal":"utm","regra":"utm_campaign = {chave}","ativa":true}]'::jsonb, 1),
  ('checkout', 'Checkout e recuperação', 'Nasce sozinho da Hotmart. Ligação em até 15 minutos; cartão recusado é problema de meio de pagamento, não objeção.', 'zap', 'hotmart', array['carrinho_abandonado','cartao_recusado','compra_em_aberto','expirada']::text[], '[{"nome":"Ligar em até 15 min","papel":"primeiro_contato","cor":"red","slaAtencaoMin":10,"slaCriticoMin":15,"criterio":"Atendeu ou respondeu","camposObrigatorios":[]},{"nome":"Em conversa","papel":"qualificar","cor":"cyan","slaAtencaoMin":240,"slaCriticoMin":1440,"criterio":"Entendeu o que travou","camposObrigatorios":[]},{"nome":"Link novo enviado","papel":"negociar","cor":"accent","slaAtencaoMin":720,"slaCriticoMin":2880,"criterio":"Escolheu a forma de pagamento","camposObrigatorios":[]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Recuperado","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Checkout {chave}","canal":"hotmart","regra":"Eventos de checkout das ofertas de {chave}","ativa":true}]'::jsonb, 2),
  ('captacao_mql', 'Captação e MQL', 'Acompanha o MQL da pesquisa até o evento (três toques: mensagem, ligação na sexta, link no privado).', 'target', 'manual', array[]::text[], '[{"nome":"Respondeu a pesquisa","papel":"primeiro_contato","cor":"info","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Toque 1 enviado","camposObrigatorios":[]},{"nome":"Toque 1: salvou o número","papel":"qualificar","cor":"cyan","slaAtencaoMin":4320,"slaCriticoMin":7200,"criterio":"Ligação feita","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Ligação de confirmação","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Confirmou presença","camposObrigatorios":[]},{"nome":"Presença confirmada","papel":"negociar","cor":"accent","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Assistiu ao vivo","camposObrigatorios":[]},{"nome":"Assistiu e comprou","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Pesquisa MQL {chave}","canal":"formulario","regra":"Pesquisa de qualificação de {chave} com perfil MQL","ativa":true}]'::jsonb, 3),
  ('pos_carrinho', 'Recuperação pós-carrinho', 'Quem assistiu e não comprou. Primeiro quem respondeu e ficou sem retorno; C e D só depois de A e B zeradas.', 'rotate', 'manual', array[]::text[], '[{"nome":"A abordar","papel":"primeiro_contato","cor":"neutral","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Mensagem 1 enviada","camposObrigatorios":[]},{"nome":"Tentando contato","papel":"qualificar","cor":"info","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Respondeu","camposObrigatorios":[]},{"nome":"Em conversa","papel":"apresentar_oferta","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":4320,"criterio":"Pediu condição ou link","camposObrigatorios":[]},{"nome":"Vai comprar","papel":"negociar","cor":"accent","slaAtencaoMin":2880,"slaCriticoMin":7200,"criterio":"Escolheu a forma de pagamento","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Ganho","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Fila de recuperação {chave}","canal":"manual","regra":"Fila montada no fechamento do carrinho de {chave}","ativa":true}]'::jsonb, 4),
  ('quentes', 'Quentes primeiro', 'Logo depois da aula gravada: quem clicou no link, depois quem só leu, depois quem nem abriu.', 'flame', 'manual', array[]::text[], '[{"nome":"Clicou no link","papel":"primeiro_contato","cor":"red","slaAtencaoMin":30,"slaCriticoMin":120,"criterio":"Recebeu contato","camposObrigatorios":[]},{"nome":"Em conversa","papel":"qualificar","cor":"cyan","slaAtencaoMin":720,"slaCriticoMin":1440,"criterio":"Objeção identificada","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Negociando","papel":"negociar","cor":"accent","slaAtencaoMin":1440,"slaCriticoMin":4320,"criterio":"Escolheu pagamento","camposObrigatorios":[]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Ganho","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Aula {chave}","canal":"utm","regra":"utm_campaign = {chave}","ativa":true}]'::jsonb, 5),
  ('webinar', 'Inscritos do webinar', 'Webinar perpétuo: inscrição, presença e oferta no pitch.', 'video', 'manual', array[]::text[], '[{"nome":"Inscrito","papel":"primeiro_contato","cor":"info","slaAtencaoMin":120,"slaCriticoMin":1440,"criterio":"Lembrete enviado","camposObrigatorios":[]},{"nome":"Assistiu","papel":"qualificar","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Conversa aberta","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Oferta apresentada","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":2880,"slaCriticoMin":4320,"criterio":"Pediu link","camposObrigatorios":[]},{"nome":"Negociar","papel":"negociar","cor":"accent","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Escolheu pagamento","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Ganho","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Webinar {chave}","canal":"webhook","regra":"Inscrição na página do webinar {chave}","ativa":true}]'::jsonb, 6),
  ('sessao_viabilidade', 'Sessão de Viabilidade', 'Escada A (cliente final): agendar, realizar e propor o croqui. Valor pago abate no degrau seguinte.', 'calendar', 'manual', array[]::text[], '[{"nome":"Agendar a sessão","papel":"primeiro_contato","cor":"info","slaAtencaoMin":30,"slaCriticoMin":120,"criterio":"Sessão marcada","camposObrigatorios":[]},{"nome":"Sessão marcada","papel":"qualificar","cor":"cyan","slaAtencaoMin":4320,"slaCriticoMin":7200,"criterio":"Sessão realizada","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Sessão realizada","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":1440,"slaCriticoMin":4320,"criterio":"Croqui proposto","camposObrigatorios":[]},{"nome":"Proposta do croqui","papel":"negociar","cor":"accent","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Família decidiu","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Sessão paga","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Seminário {chave}","canal":"utm","regra":"utm_campaign = {chave}","ativa":true}]'::jsonb, 7),
  ('croqui_implantacao', 'Croqui e implantação', 'Escada A depois da sessão: croqui estrutural e implantação da holding.', 'briefcase', 'manual', array[]::text[], '[{"nome":"Croqui em elaboração","papel":"qualificar","cor":"cyan","slaAtencaoMin":7200,"slaCriticoMin":14400,"criterio":"Croqui apresentado","camposObrigatorios":[]},{"nome":"Croqui apresentado","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Proposta de implantação enviada","camposObrigatorios":[]},{"nome":"Negociar implantação","papel":"negociar","cor":"accent","slaAtencaoMin":7200,"slaCriticoMin":20160,"criterio":"Contrato aceito","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":2880,"slaCriticoMin":7200,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Implantação contratada","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[]'::jsonb, 8),
  ('presenca_evento', 'Confirmação de presença', 'Evento presencial: quem comprou o ingresso confirma presença e vira oportunidade da oferta do evento.', 'user-check', 'manual', array[]::text[], '[{"nome":"Ingresso comprado","papel":"primeiro_contato","cor":"info","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Contato feito","camposObrigatorios":[]},{"nome":"Presença confirmada","papel":"qualificar","cor":"cyan","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Fez check-in","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Presente no evento","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Recebeu a oferta","camposObrigatorios":[]},{"nome":"Negociar no evento","papel":"negociar","cor":"accent","slaAtencaoMin":720,"slaCriticoMin":1440,"criterio":"Escolheu pagamento","camposObrigatorios":[]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Vendido","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Ingressos {chave}","canal":"hotmart","regra":"Compra aprovada do ingresso de {chave}","ativa":true}]'::jsonb, 9),
  ('ascensao', 'Ascensão de aluno', 'Aluno que está pronto para o próximo degrau (HT → HM, HM → Aurum). Dono a definir com a Educação.', 'trending-up', 'manual', array[]::text[], '[{"nome":"Sinal de ascensão","papel":"primeiro_contato","cor":"info","slaAtencaoMin":2880,"slaCriticoMin":7200,"criterio":"Conversa marcada","camposObrigatorios":[]},{"nome":"Conversa de diagnóstico","papel":"qualificar","cor":"cyan","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Momento entendido","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Proposta do degrau","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Pediu condição","camposObrigatorios":[]},{"nome":"Negociar","papel":"negociar","cor":"accent","slaAtencaoMin":7200,"slaCriticoMin":20160,"criterio":"Escolheu pagamento","camposObrigatorios":["objecao_principal"]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Subiu de degrau","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Ascensão {chave}","canal":"manual","regra":"Lista de alunos indicada pela Educação","ativa":true}]'::jsonb, 10);

insert into crm.modelo_projeto (tipo, nome, descricao, icone, funis, checklist, ordem) values
  ('lancamento_classico', 'Lançamento clássico', 'Captação, CPLs, carrinho aberto e recuperação.', 'megaphone', array['captacao_mql','venda_ativa','checkout','pos_carrinho']::text[], array['Oferta vigente definida (preço, forma de pagamento e prazo) antes de abrir o carrinho','Links rastreáveis por vendedor criados (SCK com a sigla)','Escala do plantão comercial publicada para os dias de evento e carrinho','Script de abordagem e de checkout abandonado escritos até D-10','Supressões combinadas com a Mensageria: a mesma pessoa não recebe régua e cadência no mesmo dia']::text[], 1),
  ('lancamento_meteorico', 'Lançamento semanal gravado (meteórico)', 'Aula gravada, carrinho curto: quentes primeiro, logo depois da aula.', 'zap', array['quentes','venda_ativa','checkout']::text[], array['Lista de quem clicou no link pronta no fim da aula','Teto de 30 a 50 conversas novas por dia por número','Oferta vigente e prazo real do carrinho (não inventar lote)']::text[], 2),
  ('webinar_perpetuo', 'Webinar / perpétuo', 'Inscrição contínua, presença e oferta no pitch.', 'video', array['webinar','venda_ativa','checkout']::text[], array['Webhook da página de inscrição ligado','Lembrete antes da sessão configurado na Mensageria']::text[], 3),
  ('seminario', 'Seminário (Escada A)', 'Cliente final: Sessão de Viabilidade, croqui e implantação.', 'calendar', array['captacao_mql','sessao_viabilidade','croqui_implantacao','checkout']::text[], array['Critério de MQL escrito (patrimônio, idade) antes da captação','Agenda de sessões com capacidade por escritório','Nunca misturar escada A e escada B na mesma conversa']::text[], 4),
  ('evento_presencial', 'Evento presencial (Imersão, ETHB)', 'Ingresso, presença, venda no evento e recuperação depois.', 'user-check', array['presenca_evento','checkout','pos_carrinho']::text[], array['Lista de presentes exportada no fim de cada dia','Fila de recuperação dos presentes que não compraram em até 48 h']::text[], 5),
  ('ascensao_aluno', 'Ascensão de aluno', 'Alunos que sobem de degrau: HT → HM → Aurum.', 'trending-up', array['ascensao']::text[], array['Dono definido com a Educação (Isabela) antes de abordar','Faturamento declarado conferido']::text[], 6);

select set_config('crm.canal', '', true);

-- ─── 8. RLS, policies (D6) e grants ─────────────────────────────────────────────────────────────────────────────────
do $rls$
declare t text;
begin
  foreach t in array array['linha','agrupador','produto_comercial','oferta_comercial','campo_def','modelo_funil',
                           'modelo_projeto','funil','etapa_funil','campanha','motivo_perda','distribuicao','pessoa_comercial',
                           'negocio','atividade','nota','dashboard','painel','preferencias_notificacao','notificacao'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated', t);
    execute format('grant select on crm.%I to authenticated', t);
  end loop;
  -- configuração: visível a quem é do comercial
  foreach t in array array['linha','agrupador','produto_comercial','oferta_comercial','campo_def','modelo_funil',
                           'modelo_projeto','funil','etapa_funil','campanha','motivo_perda'] loop
    execute format('create policy %I on crm.%I for select to authenticated using ((select crm.eh_comercial()))', t || '_ler', t);
  end loop;
end
$rls$;

-- F0: crm.config passa a ser lida (invoker) por quem é do comercial. Escrita continua sem grant.
revoke all on crm.config from public, anon, authenticated;
grant select on crm.config to authenticated;
create policy config_ler on crm.config for select to authenticated using ((select crm.eh_comercial()));

create policy distribuicao_ler on crm.distribuicao for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and vendedor_id = (select auth.uid())));

create policy pessoa_comercial_ler on crm.pessoa_comercial for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (dono_id = (select auth.uid()) or dono_id is null
                                      or pessoa_id in (select crm.pessoas_negocio_meu()))));

create policy negocio_ler on crm.negocio for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (dono_id = (select auth.uid()) or dono_id is null)));

create policy atividade_ler on crm.atividade for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and dono_id = (select auth.uid())));

create policy nota_ler on crm.nota for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (autor_id = (select auth.uid()) or pessoa_id in (select crm.pessoas_do_vendedor()))));

create policy dashboard_ler on crm.dashboard for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_comercial()) and (dono_id = (select auth.uid()) or compartilhado)));

create policy painel_ler on crm.painel for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_comercial()) and perfil_id = (select auth.uid())));

create policy preferencias_ler on crm.preferencias_notificacao for select to authenticated using (
  (select crm.eh_comercial()) and perfil_id = (select auth.uid()));

create policy notificacao_ler on crm.notificacao for select to authenticated using (
  (select crm.eh_comercial()) and perfil_id = (select auth.uid()));

-- log (F0): gestor tudo; vendedor o que ele fez ou o que é de pessoa que ele vê
revoke all on crm.log from public, anon, authenticated;
grant select on crm.log to authenticated;
create policy log_ler on crm.log for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (autor_id = (select auth.uid()) or pessoa_id in (select crm.pessoas_do_vendedor()))));

-- ─── 9. RPCs de leitura: SECURITY INVOKER + RLS ──────────────────────────────────────────────────────────────────────
create function public.crm_sessao() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v_g boolean := coalesce(crm.eh_gestor(), false); v_v boolean := coalesce(crm.eh_vendedor(), false);
begin
  if not (v_g or v_v) then raise exception 'Sem acesso ao Comercial.' using errcode = '42501'; end if;
  return jsonb_build_object('vendedorId', auth.uid(), 'papel', case when v_g then 'gestor' else 'vendedor' end);
end
$$;

create function public.crm_config() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object('horarioContato', coalesce(c.horario_contato, ''), 'limiteNegociosAbertos', c.limite_negocios_abertos,
                            'escritaLigada', c.escrita_ligada)
    into v from crm.config c;
  return v;
end
$$;

create function public.crm_agrupadores() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'produto', a.linha, 'ordem', a.ordem)
                            order by a.ordem, a.nome), '[]'::jsonb)
    into v from crm.agrupador a where a.arquivado_em is null;
  return v;
end
$$;

create function public.crm_funis(p_incluir_arquivados boolean default false) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'nome', f.nome, 'icone', f.icone, 'projeto', f.projeto, 'agrupadorId', f.agrupador_id,
           'produto', f.linha, 'tipo', f.tipo, 'eventosHotmart', to_jsonb(f.eventos_hotmart),
           'etapas', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', e.id, 'nome', e.nome, 'papel', e.papel, 'cor', e.cor, 'slaAtencaoMin', e.sla_atencao_min,
                        'slaCriticoMin', e.sla_critico_min, 'camposObrigatorios', to_jsonb(e.campos_obrigatorios),
                        'criterio', e.criterio) order by e.ordem)
                        from crm.etapa_funil e where e.funil_id = f.id and e.arquivada_em is null), '[]'::jsonb),
           'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', c.id, 'nome', c.nome, 'canal', c.canal, 'regra', c.regra, 'regraJson', c.regra_json,
                        'ativa', c.ativa, 'criadoEm', c.criado_em) order by c.criado_em)
                        from crm.campanha c where c.funil_id = f.id), '[]'::jsonb),
           'distribuicao', case when f.distribuicao_propria then coalesce((select jsonb_agg(jsonb_build_object(
                        'vendedorId', d.vendedor_id, 'percentual', d.percentual) order by d.percentual desc)
                        from crm.distribuicao d where d.funil_id = f.id and d.ativo), '[]'::jsonb) end,
           'ativo', f.ativo, 'criadoEm', f.criado_em) order by f.criado_em), '[]'::jsonb)
    into v from crm.funil f where f.ativo or coalesce(p_incluir_arquivados, false);
  return v;
end
$$;

create function public.crm_motivos_perda() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object('key', m.chave, 'label', m.rotulo, 'reativa', m.reativa, 'bloqueia', m.bloqueia,
                            'alertaGestor', m.alerta_gestor, 'nota', m.nota, 'sistema', m.sistema, 'ativo', m.ativo)
                            order by m.ordem, m.rotulo), '[]'::jsonb)
    into v from crm.motivo_perda m;
  return v;
end
$$;

-- Negócios (RLS: gestor tudo; vendedor os seus + sem dono). Próxima atividade por lateral (atividade_negocio_aberta_idx).
create function public.crm_negocios(p_funil uuid default null, p_status text default null, p_pessoa uuid default null,
                                    p_limite int default 1000, p_offset int default 0) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_lim int := least(greatest(coalesce(p_limite, 1000), 1), 2000);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_g uuid[]; v jsonb;
begin
  perform crm.exige_comercial();
  if p_status is not null and p_status not in ('aberto', 'ganho', 'perdido') then
    raise exception 'Status inválido.' using errcode = '22023';
  end if;
  if p_pessoa is not null then v_g := crm.pessoa_grupo(p_pessoa); end if;
  with pg as (
    select n.*, e.nome etapa_nome, e.papel, e.sla_atencao_min, e.sla_critico_min
      from crm.negocio n
      join crm.etapa_funil e on e.id = n.etapa_id
     where (p_funil is null or n.funil_id = p_funil)
       and (p_status is null or n.status = p_status)
       and (v_g is null or n.pessoa_id = any(v_g))
     order by n.criado_em desc, n.id
     limit v_lim offset v_off),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pg.id, 'contatoId', al.atual, 'produto', pg.linha, 'origem', pg.origem,
           'funilId', pg.funil_id, 'campanhaId', pg.campanha_id, 'etapaId', pg.etapa_id, 'etapaNome', pg.etapa_nome, 'etapa', pg.papel,
           'sla', case when pg.sla_atencao_min is not null
                       then jsonb_build_object('atencaoMin', pg.sla_atencao_min, 'criticoMin', pg.sla_critico_min) end,
           'status', pg.status, 'donoId', pg.dono_id, 'valor', pg.valor, 'campos', pg.campos, 'motivoPerda', pg.motivo_perda,
           'criadoEm', pg.criado_em, 'etapaDesde', pg.etapa_desde, 'fechadoEm', pg.fechado_em,
           'proximaAtividade', case when pa.id is not null
                                    then jsonb_build_object('id', pa.id, 'tipo', pa.tipo, 'titulo', pa.titulo, 'venceEm', pa.vence_em) end,
           'ultimaInteracaoEm', pg.ultima_interacao_em) order by pg.criado_em desc, pg.id), '[]'::jsonb)
    into v
    from pg
    left join al on al.pessoa_id = pg.pessoa_id
    left join lateral (select a.id, a.tipo, a.titulo, a.vence_em from crm.atividade a
                        where a.negocio_id = pg.id and a.concluida_em is null and not a.cancelada
                        order by a.vence_em limit 1) pa on true;
  return v;
end
$$;

-- Atividades: todas as ABERTAS + as concluídas desde p_desde (padrão: 30 dias), ordenadas por vencimento.
-- Paginação: p_limite (≤ 2.000) + p_offset.
create function public.crm_atividades(p_desde timestamptz default null, p_pessoa uuid default null, p_limite int default 2000,
                                      p_offset int default 0)
returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_desde timestamptz := coalesce(p_desde, now() - interval '30 days');
  v_lim int := least(greatest(coalesce(p_limite, 2000), 1), 2000);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_g uuid[]; v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is not null then v_g := crm.pessoa_grupo(p_pessoa); end if;
  with pg as (
    select a.* from crm.atividade a
     where (a.concluida_em is null or a.concluida_em >= v_desde)
       and (v_g is null or a.pessoa_id = any(v_g))
     order by a.vence_em, a.id
     limit v_lim offset v_off),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pg.id, 'negocioId', pg.negocio_id, 'contatoId', al.atual, 'donoId', pg.dono_id,
           'tipo', pg.tipo, 'titulo', pg.titulo, 'venceEm', pg.vence_em, 'concluidaEm', pg.concluida_em,
           'resultado', pg.resultado, 'cadenciaDia', pg.cadencia_dia) order by pg.vence_em, pg.id), '[]'::jsonb)
    into v
    from pg left join al on al.pessoa_id = pg.pessoa_id;
  return v;
end
$$;

-- Linha do tempo (EventoTimeline) a partir do crm.log (fonte única) + nota/atividade. Sem pessoa: desde p_desde (padrão:
-- início do dia em São Paulo = fechamento do dia).
create function public.crm_eventos(p_pessoa uuid default null, p_desde timestamptz default null, p_limite int default 500)
returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 2000);
  v_desde timestamptz := coalesce(p_desde, date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo');
  v_g uuid[]; v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is not null then v_g := crm.pessoa_grupo(p_pessoa); end if;
  -- 1º só os ids (índice log_em_idx / log_pessoa_idx + top-N); o jsonb e os joins só nas linhas que voltam (medido:
  -- montar o jsonb antes do limite custava 1,1–2,3 s com 290 mil linhas no dia).
  with ids as (
    select l.id from crm.log l
     where l.pessoa_id is not null
       and ((l.entidade = 'negocio' and l.acao in ('criou', 'moveu_etapa', 'trocou_dono', 'atribuiu', 'marcou_perdido', 'marcou_ganho'))
            or (l.entidade = 'nota' and l.acao = 'criou')
            or (l.entidade = 'atividade' and l.acao = 'concluiu')
            or (l.entidade = 'contato' and l.acao in ('trocou_dono', 'atribuiu')))
       and (v_g is null or l.pessoa_id = any(v_g))
       and (v_g is not null or l.em >= v_desde)
     order by l.em desc, l.id desc
     limit v_lim),
  pg as (
    select l.em, l.id, l.pessoa_id, jsonb_build_object(
             'id', 'log-' || l.id,
             'negocioId', case l.entidade when 'negocio' then l.entidade_id
                                          when 'nota' then nt.negocio_id::text
                                          when 'atividade' then atv.negocio_id::text end,
             'tipo', case
                       when l.entidade = 'negocio' and l.acao = 'criou' then 'criado'
                       when l.acao = 'moveu_etapa' then 'etapa'
                       when l.acao in ('trocou_dono', 'atribuiu') then 'dono'
                       when l.acao = 'marcou_perdido' then 'perdido'
                       when l.acao = 'marcou_ganho' then 'ganho'
                       when l.entidade = 'atividade' and atv.tipo = 'ligacao' then 'ligacao'
                       when l.entidade = 'atividade' and atv.tipo in ('whatsapp', 'email') then 'mensagem'
                       else 'nota' end,
             'titulo', case when l.acao = 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa') else l.resumo end,
             'detalhe', case when l.entidade = 'nota' then nt.texto
                             when l.entidade = 'atividade' then atv.resultado
                             when l.acao = 'moveu_etapa' then ep.papel end,
             'em', l.em, 'autorId', l.autor_id) j
      from ids join crm.log l on l.id = ids.id
      left join crm.nota nt on l.entidade = 'nota' and nt.id::text = l.entidade_id
      left join crm.atividade atv on l.entidade = 'atividade' and atv.id::text = l.entidade_id
      left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(pg.j || jsonb_build_object('contatoId', al.atual) order by pg.em desc, pg.id desc), '[]'::jsonb)
    into v
    from pg left join al on al.pessoa_id = pg.pessoa_id;
  return v;
end
$$;

-- Registro do CRM. p_autor: null = qualquer; 'sistema' = sem autor; uuid = esse autor.
create function public.crm_log(p_autor text default null, p_entidade text default null, p_entidade_id text default null,
                               p_pessoa uuid default null, p_desde timestamptz default null, p_ate timestamptz default null,
                               p_limite int default 500) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_autor uuid; v_g uuid[]; v jsonb;
begin
  perform crm.exige_comercial();
  if p_autor is not null and p_autor <> 'sistema' then
    begin v_autor := p_autor::uuid; exception when others then raise exception 'Autor inválido.' using errcode = '22023'; end;
  end if;
  if p_pessoa is not null then v_g := crm.pessoa_grupo(p_pessoa); end if;
  with pg as (
    select l.em, l.id, l.pessoa_id, jsonb_build_object(
             'id', l.id::text, 'em', l.em, 'autorId', l.autor_id, 'acao', l.acao, 'entidade', l.entidade,
             'entidadeId', l.entidade_id, 'resumo', l.resumo,
             'mudancas', coalesce((select jsonb_agg(jsonb_build_object('campo', m->>'campo', 'antes', m->>'de', 'depois', m->>'para'))
                                     from jsonb_array_elements(l.mudancas) m), '[]'::jsonb)) j
      from crm.log l
     where (p_autor is null or (p_autor = 'sistema' and l.autor_id is null) or l.autor_id = v_autor)
       and (p_entidade is null or l.entidade = p_entidade)
       and (p_entidade_id is null or l.entidade_id = p_entidade_id)
       and (v_g is null or l.pessoa_id = any(v_g))
       and (p_desde is null or l.em >= p_desde)
       and (p_ate is null or l.em <= p_ate)
     order by l.em desc, l.id desc
     limit v_lim),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(pg.j || jsonb_build_object('contatoId', al.atual) order by pg.em desc, pg.id desc), '[]'::jsonb)
    into v
    from pg left join al on al.pessoa_id = pg.pessoa_id;
  return v;
end
$$;

create function public.crm_dashboards() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'descricao', d.descricao, 'donoId', d.dono_id,
                            'compartilhado', d.compartilhado, 'widgets', d.widgets, 'criadoEm', d.criado_em,
                            'atualizadoEm', d.atualizado_em) order by d.atualizado_em desc), '[]'::jsonb)
    into v from crm.dashboard d
   where d.arquivado_em is null and (d.dono_id = auth.uid() or d.compartilhado);
  return v;
end
$$;

-- Painel de uma pessoa (padrão: quem está na sessão). null = ainda não personalizou (a tela usa o padrão).
create function public.crm_painel(p_perfil uuid default null) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object('vendedorId', p.perfil_id, 'widgets', p.widgets)
    into v from crm.painel p where p.perfil_id = coalesce(p_perfil, auth.uid());
  return v;
end
$$;

create function public.crm_notificacoes(p_limite int default 100) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(x.j order by x.em desc, x.id desc), '[]'::jsonb) into v from (
    select n.em, n.id, jsonb_build_object('id', n.id::text, 'vendedorId', n.perfil_id, 'gatilho', n.gatilho, 'titulo', n.titulo,
                                          'corpo', n.corpo, 'href', n.href, 'em', n.em, 'lida', n.lida_em is not null) j
      from crm.notificacao n
     where n.perfil_id = auth.uid()
     order by n.em desc, n.id desc
     limit least(greatest(coalesce(p_limite, 100), 1), 200)) x;
  return v;
end
$$;

-- null = ainda não salvou (a tela usa o padrão).
create function public.crm_preferencias() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object('vendedorId', p.perfil_id, 'desktop', p.desktop, 'gatilhos', p.gatilhos,
                            'silencioInicio', to_char(p.silencio_inicio, 'HH24:MI'), 'silencioFim', to_char(p.silencio_fim, 'HH24:MI'))
    into v from crm.preferencias_notificacao p where p.perfil_id = auth.uid();
  return v;
end
$$;

-- ─── 10. RPCs de leitura: SECURITY DEFINER (cruzam pessoas/fin/controle/respondi/cs) com a MESMA guarda da policy ────
create function public.crm_vendedores() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(x.j order by x.j->>'nome'), '[]'::jsonb) into v from (
    select jsonb_build_object(
             'id', p.id, 'nome', coalesce(p.nome, ''), 'sigla', coalesce(vd.sigla, ''),
             'papel', case when p.status = 'ativo' and (p.cargo in ('dev', 'admin')
                                or (p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}')))) then 'gestor' else 'vendedor' end,
             'ativo', coalesce(vd.ativo, true) and p.status = 'ativo',
             'percentual', coalesce((select d.percentual from crm.distribuicao d
                                      where d.funil_id is null and d.vendedor_id = p.id and d.ativo), 0),
             'disparaApi', coalesce(vd.dispara_api, false)) j
      from public.perfis p
      left join crm.vendedor vd on vd.perfil_id = p.id
     where vd.perfil_id is not null
        or (p.id = v_eu and coalesce(crm.eh_gestor(), false))) x;
  return v;
end
$$;

-- Contatos = pessoas com camada comercial. Visibilidade = policy de crm.pessoa_comercial. E-mail/telefone completos só
-- para gestor, dono ou vendedor com negócio da pessoa; o resto mascarado. Nunca documento/CPF. Alias: id = pessoa atual
-- (linha de alias só aparece se a pessoa atual não tem camada comercial; o filtro vale ANTES do limite).
-- Devolve {"itens": Contato[], "temMais": boolean} (paginação por p_limite ≤ 500 + p_offset).
-- Sem "foneKey": a chave DDD + 8 últimos dígitos reconstrói o celular (só falta o 9) = dado pessoal; duplicidade por
-- telefone para o vendedor fica para uma RPC no servidor (F2), que compara sem devolver a chave.
create function public.crm_contatos(p_busca text default null, p_limite int default 100, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_email text; v_fk text; v_like text; v_ids uuid[];
  v jsonb;
begin
  perform crm.exige_comercial();
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'temMais', false); end if;
    v_email := pessoas.norm_email(v_t);
    v_fk := pessoas.chave_telefone(v_t);
    v_like := case when v_email is null and v_fk is null
                   then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
    -- candidatos por índice (mesmas expressões da F0), depois o grupo de cada um
    v_ids := array(
      select distinct pessoas.atual(s.x) from (
        select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
        union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_email is not null and lower(btrim((c.email)::text)) = v_email
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null
        union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
        union (select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
                where v_like is not null and a.nome ilike v_like limit 200)
      ) s);
    v_ids := array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
  end if;

  select coalesce(jsonb_agg(x.j order by x.criado_em desc, x.pid), '[]'::jsonb) into v from (
    select pc.criado_em, pc.pessoa_id pid, jsonb_build_object(
             'id', atu.id, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when pc.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em) j
      from (select pc0.*, (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())) completo
              from crm.pessoa_comercial pc0
              join pessoas.pessoas pp on pp.id = pc0.pessoa_id
             where (v_ids is null or pc0.pessoa_id = any(v_ids))
               and (v_gestor or pc0.dono_id = v_eu or pc0.dono_id is null or pc0.pessoa_id in (select crm.pessoas_negocio_meu()))
               and (pp.situacao <> 'mesclada'   -- alias: vale a linha da pessoa atual, se ela tiver camada comercial
                    or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = pessoas.atual(pc0.pessoa_id)))
             order by pc0.criado_em desc, pc0.pessoa_id
             limit v_lim + 1 offset v_off) pc
      cross join lateral (select pessoas.atual(pc.pessoa_id) id) atu
      cross join lateral pessoas.dados(atu.id) d
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id) x;
  return jsonb_build_object('itens', coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v) with ordinality t(e, o) where o <= v_lim), '[]'::jsonb),
                            'temMais', jsonb_array_length(v) > v_lim);
end
$$;

-- Jornada da pessoa: tudo o que ela fez com a empresa. Guarda = crm.pode_ver_pessoa. Cada fonte pelo seu índice
-- (valor normalizado na variável × expressão exata do índice). Sem e-mail/telefone/CPF na saída. Limite 500.
create function public.crm_jornada(p_pessoa uuid, p_limite int default 500) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_atual uuid; v_g uuid[]; v_emails text[]; v_fks text[]; v_compr uuid[];
  v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is null or not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a esta pessoa.' using errcode = '42501';
  end if;
  v_atual := pessoas.atual(p_pessoa);
  v_g := pessoas.grupo(v_atual);

  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  -- e-mails irmãos pelo grafo fin.identidade (por chave, no momento da leitura; recalculado de hora em hora)
  v_emails := array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
  v_fks := array(
    select k from (
      select controle.fone_key(coalesce(a.telefone_e164, a.telefone)) k from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
       where p.id = any(v_g)
      union select controle.fone_key((c.telefone)::text) from public.compradores c where c.id = any(v_compr) and c.telefone is not null
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'telefone'
    ) s where k is not null limit 10);

  with pts as (
    -- inscrição (origem com a UTM daquela entrada)
    (select 'or-' || o.id id, 'inscricao' tipo, o.quando em,
            'Inscrição' || coalesce(' · ' || pr.sigla, '') titulo, o.campanha detalhe, 'formulario' fonte,
            lower(pr.sigla) lancamento, null::text produto,
            jsonb_build_object('source', o.utm_source, 'medium', o.utm_medium, 'campaign', o.utm_campaign, 'content', o.utm_content) utm,
            null::numeric valor, null::uuid negocio_id
       from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id
      where o.pessoa_id = any(v_g) order by o.quando desc limit v_lim)
    union all
    (select 'ev-' || e.id, 'pesquisa', e.quando, case e.tipo when 'mql' then 'Qualificou como MQL' else 'Não qualificou (MQL)' end,
            null, 'formulario', lower(pr.sigla), null, null, null, null
       from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id
      where e.pessoa_id = any(v_g) and e.tipo in ('mql', 'nao_mql') order by e.quando desc limit v_lim)
    union all
    -- Hotmart: compra, reembolso, checkout (índice hotmart_transacoes_email_idx = lower(btrim(comprador_email)))
    (select 'hm-' || h.transacao,
            case when h.status in ('APPROVED', 'COMPLETE') then 'compra'
                 when h.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED') then 'reembolso' else 'checkout' end,
            coalesce(h.aprovado_em, h.pedido_em),
            case when h.status in ('APPROVED', 'COMPLETE') then 'Compra aprovada'
                 when h.status in ('REFUNDED', 'PARTIALLY_REFUNDED') then 'Reembolso'
                 when h.status = 'CHARGEBACK' then 'Chargeback'
                 when h.status in ('WAITING_PAYMENT', 'PRINTED_BILLET') then 'Boleto/Pix gerado'
                 when h.status = 'EXPIRED' then 'Pagamento expirado'
                 when h.status = 'CANCELLED' then 'Compra cancelada'
                 else 'Checkout: ' || lower(h.status) end || coalesce(' · ' || h.produto_nome, ''),
            nullif(concat_ws(' · ', 'oferta ' || h.oferta_codigo, h.metodo), ''), 'hotmart', null, pcm.linha,
            case when h.origem_sck is not null then jsonb_build_object('sck', h.origem_sck) end,
            h.valor_cobrado, null
       from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
       left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id and pcm.no_comercial
      where lower(btrim(h.comprador_email)) = any(v_emails)
      order by coalesce(h.aprovado_em, h.pedido_em) desc nulls last limit v_lim)
    union all
    -- lista do ActiveCampaign (índice ix_lead_active_email_lower)
    (select 'ac-' || la.id, 'lista', coalesce(la.opt_in_at, la.atualizado_em), 'Entrou na lista' || coalesce(' · ' || la.origem, ''),
            la.segmento, 'activecampaign', null, null,
            jsonb_build_object('source', la.utm_source, 'campaign', la.utm_campaign, 'content', la.utm_content), null, null
       from controle.lead_active la
      where lower(btrim(la.email)) = any(v_emails)
      order by coalesce(la.opt_in_at, la.atualizado_em) desc limit v_lim)
    union all
    -- grupos de WhatsApp (índice ix_geu_fone, chave controle.fone_key)
    (select 'gr-' || g.id, 'grupo', g.ocorreu_em,
            case g.tipo when 'entrada' then 'Entrou no grupo' else 'Saiu do grupo' end || coalesce(' · ' || g.group_name, ''),
            g.segmento, 'sendflow', null, null, null, null, null
       from controle.grupo_evento_unificado g
      where g.fone_key = any(v_fks)
      order by g.ocorreu_em desc limit v_lim)
    union all
    -- pesquisas/formulários (índice respostas_email_idx; e-mail já normalizado na fonte). Nunca cpf/respostas.
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            null, 'respondi', null, null, null, null, null
       from respondi.respostas r
      where r.email = any(v_emails)
      order by r.respondido_em desc limit v_lim)
    union all
    -- mini-CRM do CS (só leitura; D4 coexistir)
    (select 'cs-' || c.id, 'nota', coalesce(c.ultimo_contato_em, c.atualizado_em, c.criado_em),
            'CS: ' || coalesce(es.nome, 'sem estágio') || coalesce(' · ' || c.evento, ''),
            case when c.responsavel is not null then 'responsável: ' || c.responsavel end, 'crm', null, null, null, null, null
       from cs.contatos c left join cs.estagios es on es.id = c.estagio_id
      where c.comprador_id = any(v_compr))
    union all
    -- CRM: negócios (mesma regra da policy de negócio)
    (select 'ng-' || n.id, 'negocio', n.criado_em, 'Negócio criado · ' || f.nome, null, 'crm', f.projeto, n.linha,
            case when n.utm <> '{}'::jsonb then n.utm end, null, n.id
       from crm.negocio n join crm.funil f on f.id = n.funil_id
      where n.pessoa_id = any(v_g) and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by n.criado_em desc limit v_lim)
    union all
    (select 'lg-' || l.id, 'negocio', l.em,
            case l.acao when 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa')
                        when 'marcou_ganho' then 'Ganho' when 'marcou_perdido' then 'Perdido'
                        else 'Troca de dono' end || ' · ' || f.nome,
            l.resumo, 'crm', f.projeto, n.linha, null,
            case when l.acao = 'marcou_ganho' then n.valor end, n.id
       from crm.log l
       join crm.negocio n on n.id::text = l.entidade_id
       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g)
      order by nt.em desc limit v_lim)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'contatoId', v_atual, 'tipo', p.tipo, 'em', p.em, 'titulo', p.titulo, 'detalhe', p.detalhe,
           'fonte', p.fonte, 'lancamento', p.lancamento, 'produto', p.produto, 'utm', p.utm, 'valor', p.valor,
           'negocioId', p.negocio_id) order by p.em desc nulls last, p.id), '[]'::jsonb)
    into v
    from (select * from pts where pts.em is not null order by pts.em desc limit v_lim) p;
  return v;
end
$$;

-- Produtos Hotmart (fin.produtos ⟕ camada comercial). p_produto = um só.
create function public.crm_produtos_hotmart(p_produto text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object(
           'produtoId', p.produto_id, 'nomeHotmart', p.nome, 'conta', p.conta, 'familia', p.familia,
           'noComercial', coalesce(pc.no_comercial, false), 'nomeComercial', pc.nome_comercial, 'produtoKey', pc.linha,
           'agrupadorId', pc.agrupador_id, 'escada', coalesce(pc.escada, l.escada),
           'sincronizadoEm', (select max(o.visto_em) from fin.ofertas o where o.produto_id = p.produto_id))
           order by coalesce(pc.no_comercial, false) desc, p.nome), '[]'::jsonb)
    into v
    from fin.produtos p
    left join crm.produto_comercial pc on pc.produto_id = p.produto_id
    left join crm.linha l on l.chave = pc.linha
   where p_produto is null or p.produto_id = p_produto;
  return v;
end
$$;

-- Ofertas Hotmart (fin.ofertas ⟕ camada comercial + transações por código). p_produto ou p_codigo filtram.
create function public.crm_ofertas(p_produto text default null, p_codigo text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  with o as (
    select o.* from fin.ofertas o
     where (p_produto is null or o.produto_id = p_produto) and (p_codigo is null or o.oferta_codigo = p_codigo)
  ), t as (
    select h.oferta_codigo, count(*) n,
           max(coalesce(h.aprovado_em, h.pedido_em)) filter (where h.status in ('APPROVED', 'COMPLETE')) ultima
      from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
     where h.oferta_codigo in (select o.oferta_codigo from o)
     group by h.oferta_codigo
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', o.oferta_codigo, 'produtoId', o.produto_id, 'nomeHotmart', o.nome, 'preco', o.preco,
           'moeda', coalesce(o.moeda, 'BRL'), 'modo', coalesce(o.modo, ''), 'principal', coalesce(o.is_main_offer, false),
           'linkCheckout', 'https://pay.hotmart.com/' || o.produto_id || '?off=' || o.oferta_codigo,
           'vigente', coalesce(oc.vigente, false), 'condicao', oc.condicao, 'validaAte', oc.valida_ate, 'uso', oc.uso,
           'transacoes', coalesce(t.n, 0), 'ultimaVendaEm', t.ultima, 'vistaEm', o.visto_em)
           order by coalesce(oc.vigente, false) desc, coalesce(t.n, 0) desc, o.oferta_codigo), '[]'::jsonb)
    into v
    from o
    left join crm.oferta_comercial oc on oc.oferta_codigo = o.oferta_codigo
    left join t on t.oferta_codigo = o.oferta_codigo;
  return v;
end
$$;

-- Códigos vendidos fora do catálogo (venda que não vira pagamento no sistema). Mais recentes primeiro.
-- Janela padrão: pedidos dos últimos 90 dias (o que o gestor ainda cataloga; medido 05/10: 2 códigos em 90 d, 20 em 365 d,
-- 229 no histórico). p_dias = null = histórico inteiro (2 Seq Scans de fin.hotmart_transacoes: 0,6–1,2 s, só sob pedido).
create function public.crm_ofertas_orfas(p_dias int default 90, p_limite int default 500) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'produtoId', x.produto_id, 'transacoes', x.n, 'ultimaEm', x.ultima)
                            order by x.ultima desc nulls last, x.codigo), '[]'::jsonb)
    into v
    from (select h.oferta_codigo codigo, max(h.produto_id) produto_id, count(*) n, max(coalesce(h.aprovado_em, h.pedido_em)) ultima
            from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
           where h.oferta_codigo is not null
             and (p_dias is null or h.pedido_em >= now() - make_interval(days => greatest(p_dias, 1)))
             and not exists (select 1 from fin.ofertas o where o.oferta_codigo = h.oferta_codigo)
           group by h.oferta_codigo
           order by max(coalesce(h.aprovado_em, h.pedido_em)) desc nulls last
           limit least(greatest(coalesce(p_limite, 500), 1), 500)) x;
  return v;
end
$$;

-- Produto e oferta a partir do link de checkout ou do código (mesma regra de extrairCodigoOferta, domain/hotmart.ts).
create function public.crm_buscar_por_link(p_texto text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_t text := btrim(coalesce(p_texto, ''));
  v_cod text; v_of jsonb; v_pr jsonb;
begin
  perform crm.exige_comercial();
  v_cod := substring(v_t from '[?&]off=([A-Za-z0-9_-]+)');
  if v_cod is null and v_t ~ '^[A-Za-z0-9_-]{4,40}$' then v_cod := v_t; end if;
  if v_cod is not null then
    v_of := public.crm_ofertas(null, v_cod) -> 0;
    if v_of is not null then v_pr := public.crm_produtos_hotmart(v_of->>'produtoId') -> 0; end if;
  end if;
  return jsonb_build_object('produto', v_pr, 'oferta', v_of, 'codigo', v_cod);
end
$$;

-- ─── 11. Grants e conferência ────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('exige_comercial', 'atual_de', 'pessoa_grupo', 'pessoas_negocio_meu', 'pessoas_do_vendedor', 'pode_ver_pessoa',
                                'tg_negocio_campos', 'tg_etapa_campos', 'tg_oferta_vigente', 'tg_motivo_sistema') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  grant execute on function crm.exige_comercial(), crm.atual_de(uuid[]), crm.pessoa_grupo(uuid),
                            crm.pessoas_negocio_meu(), crm.pessoas_do_vendedor(), crm.pode_ver_pessoa(uuid) to authenticated;
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

do $confere$
declare v_aberto text; v_n int;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and has_function_privilege('anon', p.oid, 'execute');
  if v_aberto is not null then raise exception '20261005s: executável por anon: %', v_aberto; end if;
  select string_agg(table_name || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC') or (grantee = 'authenticated' and privilege_type <> 'SELECT'));
  if v_aberto is not null then raise exception '20261005s: grant indevido em crm: %', v_aberto; end if;
  select string_agg(c.relname, ', ') into v_aberto
    from pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind = 'r' and not c.relrowsecurity;
  if v_aberto is not null then raise exception '20261005s: tabela sem RLS: %', v_aberto; end if;
  select string_agg(c.relname, ', ') into v_aberto
    from pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind = 'r'
     and has_table_privilege('authenticated', c.oid, 'select')
     and not exists (select 1 from pg_policy po where po.polrelid = c.oid);
  if v_aberto is not null then raise exception '20261005s: tabela legível sem policy: %', v_aberto; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%';
  if v_n <> 20 then raise exception '20261005s: esperava 20 RPCs public.crm_*, há %', v_n; end if;
  if (select count(*) from crm.linha) <> 6 or (select count(*) from crm.agrupador) <> 6
     or (select count(*) from crm.campo_def) <> 6 or (select count(*) from crm.motivo_perda where sistema) <> 9
     or (select count(*) from crm.modelo_funil) <> 10 or (select count(*) from crm.modelo_projeto) <> 6
     or (select count(*) from crm.funil) <> 0 or (select count(*) from crm.negocio) <> 0 then
    raise exception '20261005s: seeds fora do esperado';
  end if;
  if coalesce((select c.escrita_ligada from crm.config c), true) then
    raise exception '20261005s: escrita_ligada deveria continuar false';
  end if;
end
$confere$;

-- ═══ REVERSÃO (numa transação; F1 sem dado operacional = drop. Com dado: exportar crm.* antes) ═══════════════════════
-- begin;
-- set local lock_timeout = '3s';
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'
--   loop execute format('drop function %s', f); end loop; end $$;
-- drop policy log_ler on crm.log; drop policy config_ler on crm.config;
-- revoke select on crm.config, crm.log from authenticated;
-- drop table crm.notificacao, crm.preferencias_notificacao, crm.painel, crm.dashboard, crm.nota, crm.atividade, crm.negocio,
--   crm.pessoa_comercial, crm.distribuicao, crm.motivo_perda, crm.campanha, crm.etapa_funil, crm.funil, crm.modelo_projeto,
--   crm.modelo_funil, crm.campo_def, crm.oferta_comercial, crm.produto_comercial, crm.agrupador, crm.linha;
-- drop function crm.pode_ver_pessoa(uuid), crm.pessoas_do_vendedor(), crm.pessoas_negocio_meu(), crm.pessoa_grupo(uuid), crm.atual_de(uuid[]),
--   crm.exige_comercial(), crm.tg_negocio_campos(), crm.tg_etapa_campos(), crm.tg_oferta_vigente(), crm.tg_motivo_sistema();
-- -- crm.log guarda as linhas 'migracao' dos seeds (append-only: ficam como registro da F1)
-- commit;

-- ═══ PROVAS ═══

-- ═══ PARTE A: provas (dados fictícios @exemplo.com.br; perfis reais escolhidos por SELECT, só booleanos na saída) ═══
do $t$
declare
  v_admin uuid; v_visu uuid; v_a uuid; v_b uuid; ag uuid; f uuid; f2 uuid; c1 uuid; e1 uuid; e2 uuid; e2b uuid;
  p1 uuid; p2 uuid; p3 uuid; p5 uuid; p6 uuid; n1 uuid; n2 uuid; n3 uuid; n5 uuid; n6 uuid; a1 uuid; a2 uuid; a3 uuid;
  d1 uuid; d2 uuid; d3 uuid; pv text; ov text; ov2 text;
  v jsonb; v2 jsonb; v3 jsonb; v_n int; v_n2 int; v_err text; v_txt text; v_b1 boolean; v_ids text[];
  v_sql text; v_log0 bigint;
  v_rpcs text[];
begin
  select id into v_admin from public.perfis where cargo = 'admin' and status = 'ativo' order by criado_em limit 1;
  select id into v_visu  from public.perfis where cargo = 'visualizador' order by criado_em limit 1;
  select perfil_id into v_a from crm.vendedor where sigla = 'mp';
  select perfil_id into v_b from crm.vendedor where sigla = 'ro';
  perform pg_temp.ok('0.perfis', v_admin is not null and v_visu is not null and v_a is not null and v_b is not null,
                     'gestor (admin real), visualizador real, vendedores reais A (mp) e B (ro)');

  -- 1. estrutura e seeds
  perform pg_temp.ok('1.seeds', (select count(*) from crm.linha) = 6 and (select count(*) from crm.agrupador) = 6
                     and (select count(*) from crm.campo_def) = 6 and (select count(*) from crm.motivo_perda where sistema) = 9
                     and (select count(*) from crm.modelo_funil) = 10 and (select count(*) from crm.modelo_projeto) = 6
                     and (select count(*) from crm.funil) = 0,
                     '6 linhas, 6 agrupadores, 6 campos, 9 motivos de fábrica, 10 modelos de funil, 6 de projeto, 0 funis reais');
  perform pg_temp.ok('1.escrita', not (select escrita_ligada from crm.config), 'crm.config.escrita_ligada continua false');
  perform pg_temp.ok('1.log_seeds', (select count(*) from crm.log where canal = 'migracao' and entidade in ('agrupador', 'motivo')) = 15,
                     'seeds de agrupador (6) e motivo (9) gravados no log pelo tg_log (canal migracao)');
  select count(*), count(*) filter (where c.relrowsecurity) into v_n, v_n2 from pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind = 'r';
  perform pg_temp.ok('1.rls', v_n = 23 and v_n2 = 23, v_n2 || '/' || v_n || ' tabelas crm com RLS');
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relnamespace = 'crm'::regnamespace and not t.tgisinternal and t.tgfoid = 'crm.tg_log()'::regprocedure;
  perform pg_temp.ok('1.tg_log', v_n = 34, v_n || ' triggers de log (15 tabelas novas × 2 + config × 2 + vendedor × 2)');

  -- 2. dados fictícios
  select id into ag from crm.agrupador where linha = 'ht';
  insert into crm.funil (nome, agrupador_id, linha, tipo, projeto) values ('Ensaio · Venda ativa', ag, 'ht', 'manual', 'ensaio-f1') returning id into f;
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
  select f, x.ord - 1, x.e->>'nome', x.e->>'papel', x.e->>'cor', (x.e->>'slaAtencaoMin')::int, (x.e->>'slaCriticoMin')::int,
         array(select jsonb_array_elements_text(x.e->'camposObrigatorios')), x.e->>'criterio'
    from crm.modelo_funil m, jsonb_array_elements(m.etapas) with ordinality x(e, ord) where m.id = 'venda_ativa';
  select id into e1 from crm.etapa_funil where funil_id = f and ordem = 0;
  select id into e2 from crm.etapa_funil where funil_id = f and ordem = 1;
  insert into crm.campanha (funil_id, nome, canal, regra, regra_json) values (f, 'Captação ensaio-f1', 'utm', 'utm_campaign = ensaio-f1', '{"utm_campaign":"ensaio-f1"}') returning id into c1;
  insert into crm.funil (nome, agrupador_id, linha, tipo, eventos_hotmart) values ('Ensaio · Checkout', ag, 'ht', 'hotmart', array['carrinho_abandonado']) returning id into f2;
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
  select f2, x.ord - 1, x.e->>'nome', x.e->>'papel', x.e->>'cor', (x.e->>'slaAtencaoMin')::int, (x.e->>'slaCriticoMin')::int,
         array(select jsonb_array_elements_text(x.e->'camposObrigatorios')), x.e->>'criterio'
    from crm.modelo_funil m, jsonb_array_elements(m.etapas) with ordinality x(e, ord) where m.id = 'checkout';
  select id into e2b from crm.etapa_funil where funil_id = f2 and ordem = 0;
  perform pg_temp.ok('2.modelo_vira_funil', (select count(*) from crm.etapa_funil where funil_id = f) = 6
                     and (select count(*) from crm.etapa_funil where funil_id = f2) = 5,
                     'etapas dos modelos venda_ativa (6) e checkout (5) viram funis válidos');

  insert into pessoas.pessoas (nome, teste) values ('Ensaio Ana Comercial', true) returning id into p1;
  insert into pessoas.pessoas (nome, teste) values ('Ensaio Beto Comercial', true) returning id into p2;
  insert into pessoas.pessoas (nome, teste) values ('Ensaio Caio Semdono', true) returning id into p3;
  insert into pessoas.pessoas (nome, teste, situacao, mesclada_em) values ('Ensaio Ana Duplicada', true, 'mesclada', p1) returning id into p5;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values
    (p1, 'email', 'ana.f1@exemplo.com.br', 'ana.f1@exemplo.com.br', 'crm'),
    (p2, 'email', 'beto.f1@exemplo.com.br', 'beto.f1@exemplo.com.br', 'crm'),
    (p3, 'email', 'caio.f1@exemplo.com.br', 'caio.f1@exemplo.com.br', 'crm'),
    (p5, 'email', 'ana.dup.f1@exemplo.com.br', 'ana.dup.f1@exemplo.com.br', 'crm');
  -- p6 = referência a um comprador REAL com compra aprovada (só contagens saem do ensaio)
  insert into pessoas.pessoas (comprador_id, teste)
  select c.id, true from fin.hotmart_transacoes h join public.compradores c on lower(btrim((c.email)::text)) = lower(btrim(h.comprador_email))
   where h.status = 'APPROVED' order by h.aprovado_em desc nulls last limit 1
  returning id into p6;

  insert into crm.pessoa_comercial (pessoa_id, dono_id, perfil, utm_primeira) values
    (p1, v_a, 'advogado', '{"source":"meta","campaign":"ensaio-f1"}'), (p2, v_b, 'contador', '{}'),
    (p3, null, null, '{}'), (p5, v_a, null, '{}'), (p6, v_a, null, '{}');
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, campos)
  values (p1, f, e1, c1, 'ht', 'venda_ativa', v_a, 297, '{"perfil_profissional":"advogado","origem":"meta / ensaio-f1"}') returning id into n1;
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p2, f, e1, 'ht', 'venda_ativa', v_b, 297) returning id into n2;
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p3, f, e1, 'ht', 'venda_ativa', null, 297) returning id into n3;
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p5, f2, e2b, 'ht', 'carrinho_abandonado', v_a, 297) returning id into n5;
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p6, f, e1, 'ht', 'venda_ativa', v_a, 297) returning id into n6;
  insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em) values (n1, p1, v_a, 'whatsapp', 'Ensaio: abordar', now() + interval '1 hour') returning id into a1;
  insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em) values (n2, p2, v_b, 'ligacao', 'Ensaio: ligar', now() + interval '2 hour') returning id into a2;
  insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, concluida_em, resultado)
  values (n1, p1, v_a, 'ligacao', 'Ensaio: ligação feita', now() - interval '1 hour', now() - interval '30 min', 'Atendeu') returning id into a3;
  insert into crm.nota (pessoa_id, negocio_id, texto, autor_id) values (p1, n1, 'Ensaio: nota da A', v_a), (p2, n2, 'Ensaio: nota do B', v_b);
  insert into crm.dashboard (nome, dono_id, compartilhado) values ('Ensaio A privado', v_a, false) returning id into d1;
  insert into crm.dashboard (nome, dono_id, compartilhado) values ('Ensaio B compartilhado', v_b, true) returning id into d2;
  insert into crm.dashboard (nome, dono_id, compartilhado) values ('Ensaio B privado', v_b, false) returning id into d3;
  insert into crm.painel (perfil_id, widgets) values (v_a, '[{"id":"w1","titulo":"Vendas","metrica":"vendas","visual":"numero","periodo":"hoje","agrupar":"nenhum","largura":1,"funilId":null}]');
  insert into crm.preferencias_notificacao (perfil_id, desktop, gatilhos, silencio_inicio, silencio_fim)
  values (v_a, true, '{"lead_novo":true,"lead_respondeu":true,"prazo_estourado":false,"venda_aprovada":true,"ficha_para_aprovar":true,"atividade_vencendo":true}', '20:00', '08:00');
  insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href) values
    (v_a, 'lead_novo', n1::text, 'Lead novo: Ensaio', 'Primeiro contato', '/comercial/funil?negocio=' || n1),
    (v_b, 'lead_novo', n2::text, 'Lead novo: Ensaio B', 'Primeiro contato', '/comercial/funil?negocio=' || n2);
  insert into crm.distribuicao (funil_id, vendedor_id, percentual) values (null, v_a, 50), (null, v_b, 50);

  select h.produto_id into pv from fin.hotmart_transacoes h join fin.produtos p on p.produto_id = h.produto_id
   group by h.produto_id order by count(*) desc limit 1;
  select o.oferta_codigo into ov from fin.ofertas o where o.produto_id = pv order by o.oferta_codigo limit 1;
  select o.oferta_codigo into ov2 from fin.ofertas o where o.produto_id <> pv order by o.oferta_codigo limit 1;
  insert into crm.produto_comercial (produto_id, no_comercial, nome_comercial, linha, escada, agrupador_id, vinculado_em)
  values (pv, true, 'Ensaio produto', 'ht', 'B', ag, now());
  insert into crm.oferta_comercial (oferta_codigo, vigente, condicao) values (ov, true, 'Ensaio 12x');

  -- 3. integridade (triggers e constraints)
  v_n := 0; v_err := null;
  begin insert into crm.oferta_comercial (oferta_codigo, vigente) values (ov2, true); v_err := concat_ws(',', v_err, 'oferta');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.negocio set campos = '{"xyz":"1"}' where id = n2; v_err := concat_ws(',', v_err, 'chave');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.negocio set campos = '{"perfil_profissional":"medico"}' where id = n2; v_err := concat_ws(',', v_err, 'opcao');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.negocio set campos = '{"produto_interesse":"zzz"}' where id = n2; v_err := concat_ws(',', v_err, 'linha');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.etapa_funil set campos_obrigatorios = array['nada'] where id = e2; v_err := concat_ws(',', v_err, 'etapa');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.motivo_perda set rotulo = 'x' where chave = 'sem_interesse'; v_err := concat_ws(',', v_err, 'motivo_rotulo');
  exception when check_violation then v_n := v_n + 1; end;
  begin delete from crm.motivo_perda where chave = 'sem_interesse'; v_err := concat_ws(',', v_err, 'motivo_delete');
  exception when check_violation then v_n := v_n + 1; end;
  begin update crm.negocio set status = 'perdido', fechado_em = now() where id = n2; v_err := concat_ws(',', v_err, 'perdido_sem_motivo');
  exception when check_violation then v_n := v_n + 1; end;
  perform pg_temp.ok('3.recusas_23514', v_n = 8, v_n || '/8 recusas (oferta vigente sem produto vinculado, campo fora do cadastro, '
                     || 'opção inválida, linha inválida, campo obrigatório fora do cadastro, motivo de fábrica (rótulo e delete), '
                     || 'perdido sem motivo)' || coalesce(' / PASSOU: ' || v_err, ''));
  v_n := 0; v_err := null;
  begin insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem) values (p3, f2, e1, 'ht', 'venda_ativa'); v_err := 'fk';
  exception when foreign_key_violation then v_n := v_n + 1; end;
  begin insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem) values (p1, f, e1, 'ht', 'venda_ativa'); v_err := concat_ws(',', v_err, 'unico');
  exception when unique_violation then v_n := v_n + 1; end;
  begin delete from crm.funil where id = f; v_err := concat_ws(',', v_err, 'delete_funil');
  exception when foreign_key_violation then v_n := v_n + 1; end;
  perform pg_temp.ok('3.fk_unico', v_n = 3, v_n || '/3 (etapa de outro funil, 2º negócio aberto na mesma pessoa+funil, '
                     || 'apagar funil com histórico = RESTRICT)' || coalesce(' / PASSOU: ' || v_err, ''));
  update crm.motivo_perda set nota = 'Ensaio: nota editável' where chave = 'sem_interesse';
  perform pg_temp.ok('3.motivo_nota', (select nota from crm.motivo_perda where chave = 'sem_interesse') = 'Ensaio: nota editável',
                     'motivo de fábrica aceita mudar a nota');

  -- 4. log grava diff
  select max(id) into v_log0 from crm.log;
  perform set_config('crm.resumo', 'Ensaio: moveu Ana para Qualificar', true);
  update crm.negocio set etapa_id = e2 where id = n1;
  perform pg_temp.ok('4.moveu', (select acao = 'moveu_etapa' and resumo = 'Ensaio: moveu Ana para Qualificar' and pessoa_id = p1
                                       and dados->>'etapa_para' = e2::text and mudancas @> jsonb_build_array(jsonb_build_object('campo', 'etapa_id'))
                                  from crm.log where id > v_log0 and entidade = 'negocio' order by id desc limit 1),
                     'mover etapa → log moveu_etapa com diff, dados.etapa_para e pessoa');
  update crm.negocio set campos = campos || '{"atua_com_holding":"sim"}' where id = n1;
  perform pg_temp.ok('4.diff_campos', (select acao = 'editou' and jsonb_array_length(mudancas) = 1 and mudancas->0->>'campo' = 'campos'
                                         and mudancas->0->'para'->>'atua_com_holding' = 'sim'
                                         and resumo like 'Editou negocio %' from crm.log where entidade = 'negocio' order by id desc limit 1),
                     'editar campos → log editou com de/para; sem resumo explícito vira "Editou negocio <id>"');
  update crm.negocio set etapa_desde = now() where id = n1;
  perform pg_temp.ok('4.ignora', (select max(id) from crm.log) = (select max(id) from crm.log where entidade = 'negocio' and acao = 'editou'),
                     'mudar só etapa_desde não grava log (coluna ignorada)');
  perform pg_temp.ok('4.contato', exists (select 1 from crm.log where entidade = 'contato' and entidade_id = p1::text and acao = 'criou' and pessoa_id = p1),
                     'pessoa_comercial loga como entidade contato com entidade_id = pessoa');

  -- 5. GESTOR (admin real) — todas as RPCs, formato do tipo TypeScript
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := public.crm_sessao();
  v2 := public.crm_negocios();
  v3 := public.crm_contatos()->'itens';
  reset role;
  perform pg_temp.ok('5.sessao', v->>'papel' = 'gestor' and (v->>'vendedorId')::uuid = v_admin, 'gestor: papel gestor, vendedorId = auth.uid()');
  perform pg_temp.ok('5.negocios', jsonb_array_length(v2) = 5
                     and (v2->0) ?& array['id','contatoId','produto','origem','funilId','campanhaId','etapaId','etapaNome','etapa','sla',
                                          'status','donoId','valor','campos','motivoPerda','criadoEm','etapaDesde','fechadoEm',
                                          'proximaAtividade','ultimaInteracaoEm'],
                     'gestor vê os 5 negócios; chaves = tipo Negocio');
  perform pg_temp.ok('5.alias', (select (x->>'contatoId')::uuid = p1 from jsonb_array_elements(v2) x where (x->>'id')::uuid = n5),
                     'negócio de pessoa mesclada devolve contatoId = pessoa atual');
  perform pg_temp.ok('5.proxima', (select x->'proximaAtividade'->>'id' = a1::text and x->>'etapaNome' = 'Qualificar' and x->>'etapa' = 'qualificar'
                                          and (x->'sla'->>'atencaoMin')::int = 1440
                                     from jsonb_array_elements(v2) x where (x->>'id')::uuid = n1),
                     'próxima atividade = a aberta mais próxima; etapaNome/papel/sla da etapa');
  perform pg_temp.ok('5.contatos', jsonb_array_length(v3) = 4
                     and (select bool_and(x ?& array['id','nome','email','telefone','cidade','uf','perfil','atuaComHolding','donoId','tags',
                                                    'utm','score','ehAluno','optOut','criadoEm']) from jsonb_array_elements(v3) x)
                     and (select x->>'email' like 'ana%@exemplo.com.br' and x->>'email' not like '%*%' and x->'utm'->>'campaign' = 'ensaio-f1'
                            from jsonb_array_elements(v3) x where (x->>'id')::uuid = p1)
                     and not exists (select 1 from jsonb_array_elements(v3) x where (x->>'id')::uuid = p5),
                     'gestor vê 4 contatos (alias p5 some na p1), e-mail completo, chaves = tipo Contato');
  perform pg_temp.ok('5.sem_cpf', v3::text !~* '(documento|cpf)', 'contatos sem documento/CPF');
  set local role authenticated;
  v := public.crm_contatos('ana.f1@exemplo.com.br')->'itens';
  v2 := public.crm_contatos('Ensaio Beto')->'itens';
  reset role;
  set local role authenticated;
  v_txt := (public.crm_contatos(null, 2, 0)->>'temMais') || '|' || jsonb_array_length(public.crm_contatos(null, 2, 0)->'itens') || '|'
        || (public.crm_contatos(null, 2, 2)->>'temMais') || '|' || jsonb_array_length(public.crm_contatos(null, 2, 2)->'itens') || '|'
        || (select count(*) from (select x->>'id' from jsonb_array_elements(public.crm_contatos(null, 2, 0)->'itens') x
                                   intersect select x->>'id' from jsonb_array_elements(public.crm_contatos(null, 2, 2)->'itens') x) s) || '|'
        || jsonb_array_length(public.crm_atividades(null, null, 2, 0)) || '|' || jsonb_array_length(public.crm_atividades(null, null, 2, 2));
  reset role;
  perform pg_temp.ok('5.paginacao', v_txt = 'true|2|false|2|0|2|1', 'contatos {itens, temMais}: 4 visíveis em 2 páginas de 2 sem sobreposição (alias filtrado antes do limite); atividades com p_offset: 2 + 1 (' || v_txt || ')');
  perform pg_temp.ok('5.busca', jsonb_array_length(v) = 1 and (v->0->>'id')::uuid = p1 and jsonb_array_length(v2) = 1,
                     'busca por e-mail e por nome');
  set local role authenticated;
  v := public.crm_funis(); v2 := public.crm_agrupadores(); v3 := public.crm_motivos_perda();
  reset role;
  perform pg_temp.ok('5.funis', jsonb_array_length(v) = 2
                     and (select jsonb_array_length(x->'etapas') = 6 and jsonb_array_length(x->'campanhas') = 1 and x->'distribuicao' = 'null'::jsonb
                                 and x ?& array['id','nome','icone','projeto','agrupadorId','produto','tipo','eventosHotmart','etapas','campanhas','distribuicao','ativo','criadoEm']
                                 and (x->'etapas'->1) ?& array['id','nome','papel','cor','slaAtencaoMin','slaCriticoMin','camposObrigatorios','criterio']
                            from jsonb_array_elements(v) x where (x->>'id')::uuid = f),
                     'funis com etapas em ordem, campanhas e distribuição (null = geral)');
  perform pg_temp.ok('5.agrupadores_motivos', jsonb_array_length(v2) = 6 and v2->0 ?& array['id','nome','produto','ordem']
                     and jsonb_array_length(v3) = 9 and v3->0 ?& array['key','label','reativa','bloqueia','alertaGestor','nota','sistema','ativo'],
                     'agrupadores (6) e motivos (9) no formato do tipo');
  set local role authenticated;
  v := public.crm_config(); v2 := public.crm_vendedores(); v3 := public.crm_atividades();
  reset role;
  perform pg_temp.ok('5.config', v ?& array['horarioContato','limiteNegociosAbertos'] and (v->>'escritaLigada')::boolean = false, 'config');
  perform pg_temp.ok('5.vendedores', (select count(*) from jsonb_array_elements(v2) x where x->>'sigla' in ('mp', 'ro') and x->>'papel' = 'vendedor'
                                        and (x->>'percentual')::int = 50) = 2
                     and exists (select 1 from jsonb_array_elements(v2) x where (x->>'id')::uuid = v_admin and x->>'papel' = 'gestor')
                     and (v2->0) ?& array['id','nome','sigla','papel','ativo','percentual','disparaApi'],
                     'vendedores reais (mp, ro, 50% cada na distribuição geral) + o gestor da sessão');
  perform pg_temp.ok('5.atividades', jsonb_array_length(v3) = 3 and (v3->0) ?& array['id','negocioId','contatoId','donoId','tipo','titulo','venceEm',
                     'concluidaEm','resultado','cadenciaDia'], 'gestor vê 3 atividades');
  set local role authenticated;
  v := public.crm_eventos(p1); v2 := public.crm_eventos(); v3 := public.crm_log(null, null, null, p1);
  reset role;
  perform pg_temp.ok('5.eventos', exists (select 1 from jsonb_array_elements(v) x where x->>'tipo' = 'etapa' and x->>'titulo' = 'Moveu para Qualificar')
                     and exists (select 1 from jsonb_array_elements(v) x where x->>'tipo' = 'criado' and (x->>'negocioId')::uuid = n5)
                     and exists (select 1 from jsonb_array_elements(v) x where x->>'tipo' = 'nota' and x->>'detalhe' = 'Ensaio: nota da A')
                     and jsonb_array_length(v2) >= jsonb_array_length(v)
                     and (v->0) ?& array['id','contatoId','negocioId','tipo','titulo','detalhe','em','autorId'],
                     'eventos da pessoa (inclui o alias): criado, etapa, nota; sem pessoa = do dia');
  perform pg_temp.ok('5.log', jsonb_array_length(v3) >= 5 and (v3->0) ?& array['id','em','autorId','acao','entidade','entidadeId','contatoId','resumo','mudancas']
                     and exists (select 1 from jsonb_array_elements(v3) x, jsonb_array_elements(x->'mudancas') m
                                  where m->>'campo' = 'etapa_id' and m->>'depois' = e2::text and m->>'antes' = e1::text),
                     'log da pessoa com mudancas {campo, antes, depois}');
  set local role authenticated;
  v := public.crm_produtos_hotmart(); v2 := public.crm_ofertas(pv); v3 := public.crm_ofertas_orfas(null);
  reset role;
  perform pg_temp.ok('5.produtos', jsonb_array_length(v) >= 97 and (v->0->>'produtoId') = pv and (v->0->>'noComercial')::boolean
                     and (v->0) ?& array['produtoId','nomeHotmart','conta','familia','noComercial','nomeComercial','produtoKey','agrupadorId','escada','sincronizadoEm'],
                     jsonb_array_length(v) || ' produtos; o vinculado vem primeiro');
  perform pg_temp.ok('5.ofertas', (v2->0->>'codigo') = ov and (v2->0->>'vigente')::boolean and (v2->0->>'transacoes')::int >= 0
                     and (v2->0) ?& array['codigo','produtoId','nomeHotmart','preco','moeda','modo','principal','linkCheckout','vigente','condicao',
                                          'validaAte','uso','transacoes','ultimaVendaEm','vistaEm'],
                     jsonb_array_length(v2) || ' ofertas do produto; a vigente vem primeiro');
  perform pg_temp.ok('5.orfas', jsonb_array_length(v3) = (select count(distinct oferta_codigo) from fin.hotmart_transacoes t where oferta_codigo is not null
                                                          and not exists (select 1 from fin.ofertas o where o.oferta_codigo = t.oferta_codigo))
                     and (v3->0) ?& array['codigo','produtoId','transacoes','ultimaEm'],
                     jsonb_array_length(v3) || ' códigos órfãos (medido antes: 229)');
  set local role authenticated;
  v := public.crm_buscar_por_link('https://pay.hotmart.com/X?off=' || ov); v2 := public.crm_buscar_por_link('não é link');
  v3 := public.crm_jornada(p6);
  reset role;
  perform pg_temp.ok('5.link', v->>'codigo' = ov and v->'oferta'->>'codigo' = ov and v->'produto'->>'produtoId' = pv
                     and v2->>'codigo' is null and v2->'oferta' = 'null'::jsonb, 'link de checkout acha produto e oferta; texto inválido não');
  perform pg_temp.ok('5.jornada_real', exists (select 1 from jsonb_array_elements(v3) x where x->>'fonte' = 'hotmart' and x->>'tipo' = 'compra')
                     and exists (select 1 from jsonb_array_elements(v3) x where x->>'fonte' = 'crm' and x->>'tipo' = 'negocio')
                     and (v3->0) ?& array['id','contatoId','tipo','em','titulo','detalhe','fonte','lancamento','produto','utm','valor','negocioId']
                     and v3::text !~* '(@|cpf|documento)',
                     'jornada de comprador real: ' || (select string_agg(fonte || '=' || n, ' ') from (select x->>'fonte' fonte, count(*) n
                       from jsonb_array_elements(v3) x group by 1 order by 1) s) || '; sem e-mail/CPF na saída');
  set local role authenticated;
  v := public.crm_jornada(p1); v2 := public.crm_dashboards(); v3 := public.crm_painel(v_a);
  reset role;
  perform pg_temp.ok('5.jornada_alias', (select count(*) from jsonb_array_elements(v) x where x->>'tipo' = 'negocio' and x->>'titulo' like 'Negócio criado%') = 2
                     and (select bool_and((x->>'contatoId')::uuid = p1) from jsonb_array_elements(v) x),
                     'jornada junta o grupo (p1 + alias p5): 2 negócios criados, contatoId = atual');
  perform pg_temp.ok('5.dashboards', jsonb_array_length(v2) = 1 and (v2->0->>'id')::uuid = d2
                     and (v2->0) ?& array['id','nome','descricao','donoId','compartilhado','widgets','criadoEm','atualizadoEm'],
                     'dashboards: meus + compartilhados (gestor não é dono de nenhum)');
  perform pg_temp.ok('5.painel_gestor', (v3->>'vendedorId')::uuid = v_a and jsonb_array_length(v3->'widgets') = 1, 'gestor lê o painel do vendedor');
  set local role authenticated;
  v := public.crm_notificacoes(); v2 := public.crm_preferencias(); v3 := public.crm_painel();
  reset role;
  perform pg_temp.ok('5.proprios', jsonb_array_length(v) = 0 and v2 is null and v3 is null,
                     'notificações/preferências/painel do gestor: vazios (null = tela usa o padrão)');

  -- 6. VENDEDOR A (real, mp)
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := public.crm_sessao(); v2 := public.crm_negocios(); v3 := public.crm_contatos()->'itens';
  select count(*) into v_n from crm.negocio where id = n2;
  select count(*) into v_n2 from crm.log where entidade_id = n2::text or pessoa_id = p2;
  reset role;
  perform pg_temp.ok('6.sessao', v->>'papel' = 'vendedor', 'vendedor A: papel vendedor');
  select array_agg(x->>'id' order by x->>'id') into v_ids from jsonb_array_elements(v2) x;
  perform pg_temp.ok('6.negocios', v_ids = (select array_agg(i::text order by i::text) from unnest(array[n1, n3, n5, n6]) i) and v_n = 0 and v_n2 = 0,
                     'A vê os seus (n1, n5, n6) + sem dono (n3); NÃO vê o de B (RPC, select direto e log)');
  perform pg_temp.ok('6.contatos', jsonb_array_length(v3) = 3
                     and not exists (select 1 from jsonb_array_elements(v3) x where (x->>'id')::uuid = p2)
                     and (select x->>'email' like 'ana%@exemplo.com.br' and x->>'email' not like '%*%' from jsonb_array_elements(v3) x where (x->>'id')::uuid = p1)
                     and (select x->>'email' like 'c***@%' from jsonb_array_elements(v3) x where (x->>'id')::uuid = p3),
                     'A vê p1 (dono, e-mail completo), p3 (sem dono, e-mail mascarado), p6; não vê p2');
  set local role authenticated;
  v_n := 0; v_err := null;
  begin perform public.crm_jornada(p2); v_err := 'jornada_p2'; exception when insufficient_privilege then v_n := v_n + 1; end;
  v := public.crm_atividades(); v2 := public.crm_dashboards(); v3 := public.crm_notificacoes();
  select count(*) into v_n2 from crm.nota;
  v_txt := coalesce(public.crm_painel(v_b)::text, 'null') || '|' || (select count(*) from crm.distribuicao)::text || '|'
           || coalesce(public.crm_preferencias()->>'silencioInicio', 'null');
  v_ids := array(select x->>'contatoId' from jsonb_array_elements(public.crm_log()) x);
  reset role;
  perform pg_temp.ok('6.jornada_b', v_n = 1, 'A não abre a jornada da pessoa de B (42501)' || coalesce(' / PASSOU: ' || v_err, ''));
  perform pg_temp.ok('6.atividades', jsonb_array_length(v) = 2 and not exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = a2),
                     'A vê as suas 2 atividades, não a de B');
  perform pg_temp.ok('6.dashboards', (select array_agg((x->>'id')::uuid order by x->>'nome') from jsonb_array_elements(v2) x) = array[d1, d2],
                     'A vê o seu dashboard + o compartilhado de B; não o privado de B');
  perform pg_temp.ok('6.notif_nota', jsonb_array_length(v3) = 1 and v3->0->>'vendedorId' = v_a::text and v_n2 = 1,
                     'A vê só a sua notificação e só a sua nota');
  perform pg_temp.ok('6.painel_dist', v_txt = 'null|1|20:00' and not coalesce(p2::text = any(v_ids), false), 'A não lê o painel de B; vê só a própria linha da distribuição; lê as próprias preferências');

  -- 7. VENDEDOR B (real, ro)
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v2 := public.crm_negocios(); v3 := public.crm_contatos()->'itens';
  v_n := 0;
  begin perform public.crm_jornada(p6); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform public.crm_jornada(p1); exception when insufficient_privilege then v_n := v_n + 1; end;
  select count(*) into v_n2 from crm.negocio where dono_id = v_a;
  reset role;
  select array_agg(x->>'id' order by x->>'id') into v_ids from jsonb_array_elements(v2) x;
  perform pg_temp.ok('7.negocios', v_ids = (select array_agg(i::text order by i::text) from unnest(array[n2, n3]) i) and v_n2 = 0,
                     'B vê o seu (n2) + sem dono (n3); NÃO vê os de A');
  perform pg_temp.ok('7.contatos_jornada', jsonb_array_length(v3) = 2 and v_n = 2, 'B vê p2 e p3; jornada de pessoas de A recusada (2/2)');

  -- 8. VISUALIZADOR real e sem JWT: erro explícito em TODAS as RPCs; RLS devolve 0 linha em select direto
  v_rpcs := array['crm_sessao()', 'crm_config()', 'crm_agrupadores()', 'crm_funis()', 'crm_motivos_perda()', 'crm_negocios()',
                  'crm_atividades()', 'crm_eventos()', 'crm_log()', 'crm_dashboards()', 'crm_painel()', 'crm_notificacoes()',
                  'crm_preferencias()', 'crm_vendedores()', 'crm_contatos()', format('crm_jornada(%L::uuid)', p1),
                  'crm_produtos_hotmart()', 'crm_ofertas()', 'crm_ofertas_orfas()', format('crm_buscar_por_link(%L)', ov)];
  perform set_config('request.jwt.claims', json_build_object('sub', v_visu, 'role', 'authenticated')::text, true);
  v_n := 0; v_err := null;
  set local role authenticated;
  foreach v_sql in array v_rpcs loop
    begin execute 'select public.' || v_sql; v_err := concat_ws(',', v_err, v_sql);
    exception when insufficient_privilege then v_n := v_n + 1; end;
  end loop;
  select (select count(*) from crm.negocio) + (select count(*) from crm.linha) + (select count(*) from crm.log)
       + (select count(*) from crm.pessoa_comercial) + (select count(*) from crm.config) into v_n2;
  reset role;
  perform pg_temp.ok('8.visualizador', v_n = 20 and v_n2 = 0, v_n || '/20 RPCs recusadas (42501); select direto vê ' || v_n2
                     || ' linhas' || coalesce(' / PASSOU: ' || v_err, ''));
  perform set_config('request.jwt.claims', '', true);
  v_n := 0;
  set local role authenticated;
  foreach v_sql in array v_rpcs loop
    begin execute 'select public.' || v_sql; exception when insufficient_privilege then v_n := v_n + 1; end;
  end loop;
  reset role;
  perform pg_temp.ok('8.sem_jwt', v_n = 20, v_n || '/20 RPCs recusadas sem JWT');

  -- 9. permissões
  select count(*), count(*) filter (where has_function_privilege('anon', p.oid, 'execute')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))
    into v_n, v_n2, v_log0
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%';
  perform pg_temp.ok('9.anon_rpcs', v_n = 20 and v_n2 = 0 and v_log0 = 20, v_n || ' RPCs; anon executa ' || v_n2 || '; authenticated ' || v_log0);
  select count(*) into v_n from pg_proc p where p.pronamespace = 'crm'::regnamespace and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.ok('9.anon_crm', v_n = 0, v_n || ' funções crm.* executáveis por anon');
  select count(*) into v_n from pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind = 'r'
     and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update')
          or has_table_privilege('authenticated', c.oid, 'delete') or has_table_privilege('anon', c.oid, 'select'));
  perform pg_temp.ok('9.tabelas', v_n = 0, v_n || ' tabelas crm com escrita para authenticated ou leitura para anon');
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_n := 0;
  set local role authenticated;
  begin insert into crm.linha (chave, nome, escada, ticket_ref) values ('zz', 'x', 'B', 1); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin update crm.negocio set valor = 1 where id = n1; exception when insufficient_privilege then v_n := v_n + 1; end;
  begin delete from crm.nota; exception when insufficient_privilege then v_n := v_n + 1; end;
  reset role;
  perform pg_temp.ok('9.gestor_sem_escrita', v_n = 3, v_n || '/3: nem o gestor escreve direto (escrita = RPC da F2)');
  perform set_config('request.jwt.claims', '', true);
  v_n := 0;
  set local role anon;
  begin perform public.crm_sessao(); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform public.crm_contatos(); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform 1 from crm.negocio; exception when insufficient_privilege then v_n := v_n + 1; end;
  reset role;
  perform pg_temp.ok('9.anon_chama', v_n = 3, v_n || '/3 recusas ao chamar como anon');
end
$t$;

select string_agg(linha, E'\n' order by n) from pg_temp._z_out;
rollback;

-- ═══ PARTE B: massa sintética 10× + medição (cada bloco = 1 chamada, begin … rollback) ════════════════════════════════
-- Cada bloco recria SÓ o que a medição precisa (mesmas colunas/índices/policies/corpo de RPC da migration; tabelas
-- auxiliares reduzidas às colunas usadas), gera a massa com generate_series, faz analyze e mede a RPC INTEIRA 2× como
-- authenticated + JWT real (gestor = admin real; vendedor A = mp). Massa: 20 mil pessoas (pessoas.pessoas, teste=true),
-- 20 mil pessoa_comercial, ~30 mil negócios, 60 mil atividades, ~300 mil linhas de crm.log (pior caso: o log inteiro no
-- MESMO dia). Os números e planos colados estão em 20261005s.explain.md. O _z_out recebe GRANT para authenticated porque
-- as medições gravam a linha ainda dentro de "set local role authenticated".

-- B1 — crm_negocios (corpo da migration: página + alias em lote por crm.atual_de)
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, linha text) on commit drop;
grant insert, select on _z_out to authenticated;
grant usage on sequence _z_out_n_seq to authenticated;
create function crm.exige_comercial() returns void language plpgsql stable security definer set search_path = '' as $$
begin if not coalesce(crm.eh_comercial(), false) then raise exception 'Sem acesso ao Comercial.' using errcode = '42501'; end if; end $$;
create function crm.atual_de(p_ids uuid[]) returns table (pessoa_id uuid, atual uuid) language plpgsql stable security definer set search_path = '' as $$
begin if not coalesce(crm.eh_comercial(), false) then return; end if; return query select x, pessoas.atual(x) from unnest(p_ids) x; end $$;
create function crm.pessoa_grupo(p_pessoa uuid) returns uuid[] language sql stable security definer set search_path = '' as $$
  select case when coalesce(crm.eh_comercial(), false) then pessoas.grupo(pessoas.atual(p_pessoa)) else '{}'::uuid[] end; $$;
create table crm.funil (id uuid primary key default gen_random_uuid(), nome text not null);
create table crm.etapa_funil (id uuid primary key default gen_random_uuid(), funil_id uuid not null references crm.funil(id), ordem smallint not null, nome text not null, papel text not null, sla_atencao_min int, sla_critico_min int, unique (funil_id, id));
create table crm.negocio (id uuid primary key default gen_random_uuid(), pessoa_id uuid not null references pessoas.pessoas(id), funil_id uuid not null references crm.funil(id), etapa_id uuid not null, campanha_id uuid, linha text not null default 'ht', origem text not null default 'venda_ativa', status text not null default 'aberto', dono_id uuid references crm.vendedor(perfil_id), valor numeric(12,2) not null default 0, campos jsonb not null default '{}', motivo_perda text, criado_em timestamptz not null default now(), etapa_desde timestamptz not null default now(), fechado_em timestamptz, ultima_interacao_em timestamptz);
create index negocio_criado_idx on crm.negocio (criado_em desc);
create index negocio_dono_idx on crm.negocio (dono_id, criado_em desc);
create index negocio_semdono_idx on crm.negocio (criado_em desc) where dono_id is null;
create table crm.atividade (id uuid primary key default gen_random_uuid(), negocio_id uuid, pessoa_id uuid not null, dono_id uuid not null, tipo text not null, titulo text not null, vence_em timestamptz not null, concluida_em timestamptz, cancelada boolean not null default false);
create index atividade_negocio_aberta_idx on crm.atividade (negocio_id, vence_em) where concluida_em is null;
do $rls$ declare t text; begin
  foreach t in array array['funil','etapa_funil','negocio','atividade'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('grant select on crm.%I to authenticated', t);
  end loop; end $rls$;
create policy e on crm.etapa_funil for select to authenticated using ((select crm.eh_comercial()));
create policy n on crm.negocio for select to authenticated using ((select crm.eh_gestor()) or ((select crm.eh_vendedor()) and (dono_id = (select auth.uid()) or dono_id is null)));
create policy a on crm.atividade for select to authenticated using ((select crm.eh_gestor()) or ((select crm.eh_vendedor()) and dono_id = (select auth.uid())));
create function public.crm_negocios(p_funil uuid default null, p_status text default null, p_pessoa uuid default null, p_limite int default 1000, p_offset int default 0) returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_lim int := least(greatest(coalesce(p_limite, 1000), 1), 2000); v_off int := greatest(coalesce(p_offset, 0), 0); v jsonb;
begin
  perform crm.exige_comercial();
  with pg as (
    select n.*, e.nome etapa_nome, e.papel, e.sla_atencao_min, e.sla_critico_min
      from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
     where (p_funil is null or n.funil_id = p_funil) and (p_status is null or n.status = p_status)
     order by n.criado_em desc, n.id limit v_lim offset v_off),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(jsonb_build_object('id', pg.id, 'contatoId', al.atual, 'produto', pg.linha, 'origem', pg.origem, 'funilId', pg.funil_id, 'campanhaId', pg.campanha_id, 'etapaId', pg.etapa_id, 'etapaNome', pg.etapa_nome, 'etapa', pg.papel,
             'sla', case when pg.sla_atencao_min is not null then jsonb_build_object('atencaoMin', pg.sla_atencao_min, 'criticoMin', pg.sla_critico_min) end,
             'status', pg.status, 'donoId', pg.dono_id, 'valor', pg.valor, 'campos', pg.campos, 'motivoPerda', pg.motivo_perda, 'criadoEm', pg.criado_em, 'etapaDesde', pg.etapa_desde, 'fechadoEm', pg.fechado_em,
             'proximaAtividade', case when pa.id is not null then jsonb_build_object('id', pa.id, 'tipo', pa.tipo, 'titulo', pa.titulo, 'venceEm', pa.vence_em) end, 'ultimaInteracaoEm', pg.ultima_interacao_em)
           order by pg.criado_em desc, pg.id), '[]'::jsonb) into v
    from pg left join al on al.pessoa_id = pg.pessoa_id
    left join lateral (select a.id, a.tipo, a.titulo, a.vence_em from crm.atividade a where a.negocio_id = pg.id and a.concluida_em is null and not a.cancelada order by a.vence_em limit 1) pa on true;
  return v;
end $$;
grant execute on function crm.exige_comercial(), crm.atual_de(uuid[]), crm.pessoa_grupo(uuid), public.crm_negocios(uuid,text,uuid,int,int) to authenticated;
create temp table _vend on commit drop as select array_agg(perfil_id order by sigla) v from crm.vendedor;
insert into crm.funil (nome) select 'F' || g from generate_series(1, 10) g;
insert into crm.etapa_funil (funil_id, ordem, nome, papel, sla_atencao_min, sla_critico_min) select f.id, o, 'Etapa ' || o, 'qualificar', 60, 120 from crm.funil f, generate_series(0, 5) o;
insert into pessoas.pessoas (nome, teste) select 'Ensaio Massa ' || g, true from generate_series(1, 20000) g;
insert into crm.negocio (pessoa_id, funil_id, etapa_id, dono_id, criado_em)
select p.id, e.funil_id, e.id, case when p.r % 10 = 0 then null else (select v[1 + p.r % 2] from _vend) end, now() - ((p.r * 1.5)::int || ' minutes')::interval
  from (select id, row_number() over () r from pessoas.pessoas where teste and nome like 'Ensaio Massa %') p
  cross join generate_series(1, case when p.r % 2 = 0 then 2 else 1 end) i
  join lateral (select ef.id, ef.funil_id from crm.etapa_funil ef order by ef.id offset ((p.r + i) % 60) limit 1) e on true;
insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, concluida_em) select n.id, n.pessoa_id, coalesce(n.dono_id, (select v[1] from _vend)), 'ligacao', 'x', now() + (j || ' hours')::interval, case when j = 1 then now() end from crm.negocio n cross join generate_series(1, 2) j;
analyze crm.negocio; analyze crm.atividade; analyze crm.etapa_funil;
do $x$
declare v_admin uuid; v_a uuid; r record; v_txt text; v_t0 timestamptz; v jsonb; i int; quem text; sub uuid;
begin
  select id into v_admin from public.perfis where cargo = 'admin' and status = 'ativo' order by criado_em limit 1;
  select perfil_id into v_a from crm.vendedor where sigla = 'mp';
  insert into _z_out (linha) select format('massa: negocio=%s atividade=%s', (select count(*) from crm.negocio), (select count(*) from crm.atividade));
  for i in 1..2 loop
    foreach quem in array array['gestor', 'vendedor A'] loop
      sub := case quem when 'gestor' then v_admin else v_a end;
      perform set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated')::text, true);
      set local role authenticated;
      v_txt := '';
      for r in execute 'explain (analyze, buffers, format text) select public.crm_negocios()' loop v_txt := v_txt || r."QUERY PLAN" || ' / '; end loop;
      v_t0 := clock_timestamp(); v := public.crm_negocios();
      insert into _z_out (linha) values (format('[%s] %s crm_negocios(): %s itens, %s ms | %s', i, quem, jsonb_array_length(v), round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1), v_txt));
      reset role;
    end loop;
  end loop;
end $x$;
select string_agg(linha, E'\n' order by n) from _z_out;
rollback;

-- B2 — crm_jornada (comprador real com mais transações) e crm_ofertas_orfas (histórico inteiro), 300 mil linhas de log
-- (mesmo corpo de crm_jornada da migration; ver a chamada registrada no .explain.md)

-- B3 — crm_log, crm_contatos e crm_ofertas_orfas(90 d) com policies por conjunto (crm.pessoas_do_vendedor /
-- crm.pessoas_negocio_meu) e 290 mil linhas de log no mesmo dia

-- B4 — crm_eventos "ids primeiro" com 300 mil linhas de log no mesmo dia
-- B2–B4 seguem o mesmo esqueleto do B1 (temp _z_out com grant, helpers, tabelas mínimas com os índices da migration,
-- policies da migration, corpo da RPC da migration, massa por generate_series, analyze, 2 medições por papel). O que
-- muda em cada um (massa e consultas medidas) está descrito no .explain.md, seção "Planos"; para repetir, copie o corpo
-- atual da RPC da migration para dentro do esqueleto do B1.

-- ═══ PARTE C: conferência (chamada separada, sem transação) ════════════════════════════════════════════════════════
-- Esperado: crm só com config,log,vendedor; 5 funções crm.*; 0 public.crm_*; log = o que havia antes (3 linhas, max id 3);
-- 2 vendedores; escrita_ligada=false; 0 policies em crm.log/crm.config; pessoas vazia; authenticated sem SELECT em crm.log;
-- última versão 20261006012515; 0 sessões presas.
select (select string_agg(relname, ',' order by relname) from pg_class where relnamespace = 'crm'::regnamespace and relkind = 'r') crm_tabelas,
 (select count(*) from pg_proc where pronamespace = 'crm'::regnamespace) crm_funcoes,
 (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'crm\_%') rpcs_crm,
 (select count(*) from crm.log) log_n, (select max(id) from crm.log) log_max, (select count(*) from crm.vendedor) vendedores,
 (select escrita_ligada from crm.config) escrita,
 (select count(*) from pg_policy where polrelid in ('crm.log'::regclass, 'crm.config'::regclass)) policies_f0,
 (select count(*) from pessoas.pessoas) pessoas_n, (select count(*) from pessoas.identificadores) ident_n,
 has_table_privilege('authenticated', 'crm.log', 'select') auth_le_log,
 (select version from supabase_migrations.schema_migrations order by version desc limit 1) ultima_versao,
 (select count(*) from pg_stat_activity where state like 'idle in transaction%') sessoes_presas;
