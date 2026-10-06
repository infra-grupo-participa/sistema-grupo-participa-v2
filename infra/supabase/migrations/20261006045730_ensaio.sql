-- 20261006d: ENSAIO da F6 (não aplica nada: tudo termina em ROLLBACK).
-- Rodado em produção (mbvybujpkwuorhtdzcde) em 06/10/2026, numa chamada só (~1 s), com F0, F1 e F2 aplicadas (a F2 entrou
-- em produção durante a preparação, versão 20261006041654; antes disso o ensaio incluía as seções 0–2 da F2 no mesmo
-- begin e a guarda conferiu o md5 de crm.tg_negocio_notifica contra o corpo do arquivo da F2 — igual ao vivo).
-- Conteúdo: o corpo INTEIRO da migration (cópia literal de 20261006d_crm_f6_migracao_clint.sql; mudou a migration,
-- regerar este arquivo) + as provas. Resultado: 44/44 OK (ver 20261006d.explain.md). PARTE C, em chamada separada,
-- conferiu que nada persistiu.
-- Como rodar: o arquivo inteiro de uma vez (SQL editor, psql ou execute_sql), como postgres. Saída = última consulta;
-- esperado: NENHUMA linha começando com "ERRADO". Dados fictícios: contatos "Ensaio F6 …" com e-mail @exemplo.invalid;
-- vendedor, 1 e-mail de comprador e 1 transação Hotmart aprovada reais escolhidos por SELECT (só em temp/GUC local;
-- a saída mostra só booleanos/contagens). clint_import_ligado só é ligado DENTRO desta transação.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;

-- ═══ CORPO DA F6 (cópia literal de 20261006d_crm_f6_migracao_clint.sql) ═══════════════════════════════════════════
-- 20261006d: F6 do Comercial — migração da Clint para o CRM (staging em arquivo + carga staging → pessoas/crm)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006d_ensaio.sql (begin … rollback; rodado em produção em 06/10/2026, tudo OK).
-- Medidas, decisões e resultado do ensaio: 20261006d.explain.md. Mapeamento campo a campo: docs/projetos/comercial/
-- migracao-clint.md. Extração: infra/scripts/clint_extrair.py (só GET na Clint; grava aqui pelas 2 RPCs service_role).
-- Ao aplicar: renomear o arquivo para a versão gravada em supabase_migrations.schema_migrations.
-- Depende de F0 (20261005r), F1 (20261005s) e F2 (20261005t, aplicada em 06/10/2026 como versão 20261006041654): a guarda
-- aborta sem a F2 (a F2 exige crm.negocio vazio e a carga escreve em crm.negocio: ordem obrigatória F2 → F6).
-- Independe de F3/F4/F5/F7 (20261006a/b/c/e): só exige que crm.tg_negocio_notifica continue com o corpo da F2 (md5).
--
-- O QUE FAZ
--   1. Staging no schema arquivo (fechado: sem grant, sem API; manual §6 "backups/staging novos vão em arquivo"):
--        arquivo.clint_lote       uma extração (abrir/fechar, contagens da API × gravadas)
--        arquivo.clint_objeto     bruto idempotente: PK (tipo, clint_id), payload jsonb + md5; reextrair = upsert
--        arquivo.clint_resultado  o que a carga fez com cada objeto (pessoa/negócio/nota/atividade criados, status)
--        arquivo.clint_mapa_*     de-para revisado pelo gestor: funil (origin → linha), etapa (stage → papel),
--                                 usuario (user → perfil/vendedor por e-mail), motivo (lost-status → crm.motivo_perda),
--                                 campo (field → campo_def/utm/nota). Só linha com confirmado = true é usada.
--        arquivo.clint_carga      relatório de cada carga real
--   2. public.crm_clint_staging_lote / public.crm_clint_staging_gravar: as ÚNICAS portas de escrita do script de
--      extração. SECURITY DEFINER, só service_role (revoke de PUBLIC/anon/authenticated).
--   3. crm.clint_preparar_mapas(): preenche os mapas com SUGESTÃO (confirmado = false) a partir do staging; usuário
--      casa com public.perfis por e-mail (lower(btrim)). Nunca sobrescreve o que o gestor confirmou.
--   4. crm.clint_carregar(p_lote, p_ensaio default TRUE, p_limite, p_opcoes): staging → pessoas/crm, em lotes.
--        contato  → pessoas.registrar(..., 'importacao') = a cascata da F0: e-mail primeiro; telefone (controle.fone_key)
--                   só sem e-mail e com 1 candidato de nome compatível; nome nunca casa (revisão). Sem identificador =
--                   fica de fora. Tags → crm.pessoa_comercial.tags (união, máx. 30).
--        negócio  → crm.funil "Clint · <origin>" criado a partir do mapa (etapas = stages com papel; etapa Fechado
--                   garantida), crm.negocio origem 'venda_ativa'. OPEN = aberto (2º aberto da mesma pessoa no mesmo
--                   funil = 'duplicado', não cria); LOST = perdido com motivo do mapa; WON = ganho SÓ se casar 1
--                   transação Hotmart aprovada real (e-mail, linha do funil, janela) — senão 'ganho_sem_transacao':
--                   não vira negócio, vira pessoas.eventos (tipo crm). Campos sem destino + histórico → 1 nota.
--        histórico (GET /v2/deals/{id}/history) → notas (categoria de nota) + 1 nota "Histórico na Clint" por negócio.
--        atividade aberta de negócio aberto → crm.atividade (dono = dono do negócio); concluída fica no histórico.
--      Idempotente pela chave de origem (tipo, clint_id) em arquivo.clint_resultado: reprocessar = 0 novos.
--      Modo ensaio (padrão): faz tudo, mede, e desfaz (exceção capturada) — devolve o MESMO relatório, nada grava.
--      Modo real: exige crm.config.clint_import_ligado = true e lote fechado.
--      Log: crm.tg_log grava com canal 'clint_import' (autor_tipo 'integracao').
--   5. crm.tg_negocio_notifica (F2) recriada a partir do corpo da F2 + 1 linha: não notifica "lead novo" durante a
--      carga da Clint (canal clint_import). Sem isso, cada negócio aberto importado avisaria o dono (centenas de avisos).
--      A guarda confere o md5 do corpo vigente: mudou a F2, regerar esta função a partir do corpo novo.
--   6. crm.clint_relatorio(): fotografia (staging × resultado × mapas pendentes × alterados depois da carga).
--
-- O QUE NÃO FAZ: não chama a Clint, não liga clint_import_ligado, não agenda cron, não toca cs.contatos (D4),
--   não importa conversas/mensagens do WhatsApp (F4/D9), não usa CPF, não apaga nada.
--
-- AS 5 PERGUNTAS
--   escala: volume da Clint NÃO medido (token não está no Vault; ver .explain.md). Custo por contato = 1
--     pessoas.registrar (Index Scan nas fontes, medido na F0) + upsert de pessoa_comercial; por negócio = PK/índice
--     único; ganho = hotmart_transacoes_email_idx. Lote limitado por p_limite (padrão 300) → chamada curta.
--   índice: clint_objeto PK (tipo, clint_id) + (tipo, pai_id) + contato do negócio (expressão payload#>>'{contact,id}');
--     clint_resultado PK; fin.hotmart_transacoes pela expressão exata lower(btrim(comprador_email)).
--   frequência: manual (operador roda em laço até "pendentes = 0"); sem cron nesta fase.
--   repetição: cada objeto é processado 1× (resultado final não reprocessa).
--   reversão: kill-switch crm.config.clint_import_ligado; tudo criado tem canal clint_import no crm.log e linha em
--     arquivo.clint_resultado (negocio_id/nota_id/atividade_id) → arquivar em lote. Bloco REVERSÃO no fim.
--
-- PREMISSAS (guarda aborta): F0/F1 aplicadas; F2 aplicada (crm.guarda_escrita, crm.tg_negocio_regras, gatilhos
--   negocio_regras/negocio_notifica_ins e corpo de crm.tg_negocio_notifica com md5 conhecido); schema arquivo existe e
--   nenhuma arquivo.clint_*; crm.config.clint_import_ligado = false; pessoas.registrar(jsonb,text,uuid);
--   motivos de fábrica; índice hotmart_transacoes_email_idx com a expressão exata.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  select string_agg(t, ', ') into v_falta
    from unnest(array['crm.config','crm.vendedor','crm.log','crm.linha','crm.agrupador','crm.funil','crm.etapa_funil',
                      'crm.motivo_perda','crm.campo_def','crm.pessoa_comercial','crm.negocio','crm.atividade','crm.nota',
                      'crm.produto_comercial','pessoas.pessoas','pessoas.eventos','fin.hotmart_transacoes']) t
   where to_regclass(t) is null;
  if v_falta is not null then raise exception '20261006d: faltam tabelas da F0/F1: %', v_falta; end if;
  if to_regprocedure('pessoas.registrar(jsonb,text,uuid)') is null or to_regprocedure('pessoas.atual(uuid)') is null
     or to_regprocedure('pessoas.dados(uuid)') is null or to_regprocedure('pessoas.norm_email(text)') is null
     or to_regprocedure('pessoas.chave_telefone(text)') is null or to_regprocedure('crm.tg_log()') is null then
    raise exception '20261006d: funções da F0 ausentes';
  end if;
  -- F2: a carga respeita as regras do negócio (ganho só por pagamento, motivo ativo) que nascem nela
  if to_regprocedure('crm.guarda_escrita()') is null or to_regprocedure('crm.tg_negocio_regras()') is null
     or to_regprocedure('crm.tg_negocio_notifica()') is null or to_regprocedure('crm.nome_pessoa(uuid)') is null
     or not exists (select 1 from pg_trigger where tgrelid = 'crm.negocio'::regclass and tgname = 'negocio_regras')
     or not exists (select 1 from pg_trigger where tgrelid = 'crm.negocio'::regclass and tgname = 'negocio_notifica_ins') then
    raise exception '20261006d: F2 (20261005t) não aplicada';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.tg_negocio_notifica()'::regprocedure)
     <> '86f28a83cde4d50c6d1031a8ce878967' then
    raise exception '20261006d: crm.tg_negocio_notifica mudou desde a F2: regerar a seção 5 a partir do corpo vigente';
  end if;
  if to_regnamespace('arquivo') is null then raise exception '20261006d: schema arquivo ausente'; end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'arquivo'::regnamespace and c.relname like 'clint\_%') then
    raise exception '20261006d: arquivo.clint_* já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('crm.clint_carregar(text,boolean,integer,jsonb)') is not null then
    raise exception '20261006d: crm.clint_carregar já existe';
  end if;
  if coalesce((select c.clint_import_ligado from crm.config c), true) then
    raise exception '20261006d: crm.config.clint_import_ligado deveria estar false';
  end if;
  if (select count(*) from crm.motivo_perda where sistema) <> 9 then
    raise exception '20261006d: esperava 9 motivos de fábrica';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'fin' and indexname = 'hotmart_transacoes_email_idx'
                    and indexdef like '%(lower(TRIM(BOTH FROM comprador_email)))%') then
    raise exception '20261006d: fin.hotmart_transacoes_email_idx ausente ou com outra expressão';
  end if;
end
$guarda$;

-- ─── 1. Staging em arquivo ───────────────────────────────────────────────────────────────────────────────────────────
create table arquivo.clint_lote (
  lote         text primary key check (lote ~ '^clint-[0-9]{8}T[0-9]{6}$'),
  iniciado_em  timestamptz not null default now(),
  terminado_em timestamptz,
  situacao     text not null default 'aberto' check (situacao in ('aberto', 'completo', 'incompleto')),
  contagens    jsonb not null default '{}' check (jsonb_typeof(contagens) = 'object'),   -- só números (API × gravado)
  check ((situacao = 'aberto') = (terminado_em is null))
);
comment on table arquivo.clint_lote is 'Extração da Clint (20261006d). contagens = totalCount da API × gravados, sem dado pessoal.';

create table arquivo.clint_objeto (
  tipo        text not null check (tipo in ('grupo','origem','usuario','motivo','tag','campo','contato','negocio',
                                               'atividade','historico')),
  clint_id    text not null check (length(clint_id) between 1 and 200),
  pai_id      text check (pai_id is null or length(pai_id) <= 200),      -- negócio do histórico/atividade
  payload     jsonb not null check (jsonb_typeof(payload) = 'object'),
  hash        text not null,                                              -- md5(payload::text)
  lote        text not null references arquivo.clint_lote(lote) on delete restrict,   -- último lote que viu
  primeiro_em timestamptz not null default now(),
  visto_em    timestamptz not null default now(),
  alterado_em timestamptz not null default now(),
  primary key (tipo, clint_id)
);
create index clint_objeto_pai_idx on arquivo.clint_objeto (tipo, pai_id) where pai_id is not null;
create index clint_objeto_contato_idx on arquivo.clint_objeto ((payload #>> '{contact,id}')) where tipo = 'negocio';
comment on table arquivo.clint_objeto is 'Bruto da API da Clint, 1 linha por objeto (idempotente por tipo+clint_id). '
  'historico: clint_id = <deal>:<item>. Dado pessoal: fica só aqui (fechado); expurgar após o corte (ver migracao-clint.md).';

create table arquivo.clint_resultado (
  tipo           text not null,
  clint_id       text not null,
  status         text not null check (status in ('ok','duplicado','ganho_sem_transacao','sem_identificador','ignorado',
                                                  'pendente_mapa','pendente_motivo','pendente_contato','pendente_dono','erro')),
  pessoa_id      uuid,
  negocio_id     uuid,
  nota_id        uuid,
  atividade_id   uuid,
  detalhe        jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object'),   -- sem dado pessoal
  hash_processado text,
  processado_em  timestamptz not null default now(),
  primary key (tipo, clint_id)
);
create index clint_resultado_negocio_idx on arquivo.clint_resultado (negocio_id) where negocio_id is not null;
create index clint_resultado_status_idx on arquivo.clint_resultado (tipo, status);

create table arquivo.clint_mapa_funil (
  clint_origem_id  text primary key,
  nome             text not null,
  grupo_nome       text,
  arquivado_clint  boolean not null default false,
  importar         boolean not null default true,
  linha            text references crm.linha(chave) on delete restrict,
  agrupador_id     uuid references crm.agrupador(id) on delete restrict,   -- vazio = agrupador da linha
  confirmado       boolean not null default false,
  funil_id         uuid references crm.funil(id) on delete restrict,       -- preenchido pela carga
  etapa_fechado_id uuid references crm.etapa_funil(id) on delete restrict,
  check (not confirmado or not importar or linha is not null)
);

create table arquivo.clint_mapa_etapa (
  clint_etapa_id  text primary key,
  clint_origem_id text not null references arquivo.clint_mapa_funil(clint_origem_id) on delete restrict,
  nome            text not null,
  ordem           int not null default 0,
  tipo_clint      text,
  papel           text check (papel in ('primeiro_contato','qualificar','apresentar_oferta','negociar','aguardar_pagamento','fechado')),
  confirmado      boolean not null default false,
  etapa_id        uuid references crm.etapa_funil(id) on delete restrict,
  check (not confirmado or papel is not null)
);

create table arquivo.clint_mapa_usuario (
  clint_usuario_id text primary key,
  nome             text,
  email_norm       text,                         -- lower(btrim(email)) do usuário da Clint (equipe)
  perfil_id        uuid references public.perfis(id) on delete restrict,
  confirmado       boolean not null default false   -- true = gestor fixou perfil_id à mão (preparar não mexe)
);

create table arquivo.clint_mapa_motivo (
  clint_motivo_id text primary key,              -- 'sem_motivo' = perdido sem lost_status na Clint
  nome            text not null,
  motivo_chave    text references crm.motivo_perda(chave) on delete restrict,
  confirmado      boolean not null default false,
  check (not confirmado or motivo_chave is not null)
);

create table arquivo.clint_mapa_campo (
  entidade   text not null check (entidade in ('CONTACT', 'DEAL')),
  chave      text not null,
  rotulo     text,
  tipo_clint text,
  destino    text not null default 'nota'
    check (destino in ('nota','ignorar','utm_source','utm_medium','utm_campaign','utm_content','utm_term','tag')
           or destino ~ '^campo:[a-z_]{3,40}$'),
  confirmado boolean not null default false,     -- não confirmado = vai para a nota (nada se perde)
  primary key (entidade, chave)
);

create table arquivo.clint_carga (
  id         bigint generated always as identity primary key,
  lote       text not null references arquivo.clint_lote(lote) on delete restrict,
  em         timestamptz not null default now(),
  por        text not null default session_user,
  relatorio  jsonb not null
);

do $fecha$
declare t text;
begin
  foreach t in array array['clint_lote','clint_objeto','clint_resultado','clint_mapa_funil','clint_mapa_etapa',
                           'clint_mapa_usuario','clint_mapa_motivo','clint_mapa_campo','clint_carga'] loop
    execute format('alter table arquivo.%I enable row level security', t);
    execute format('revoke all on arquivo.%I from public, anon, authenticated, service_role', t);
  end loop;
end
$fecha$;

-- ─── 2. Portas do script de extração (só service_role) ───────────────────────────────────────────────────────────────
create function public.crm_clint_staging_lote(p_lote text, p_acao text, p_contagens jsonb default '{}')
returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if p_lote is null or p_lote !~ '^clint-[0-9]{8}T[0-9]{6}$' then
    return jsonb_build_object('ok', false, 'msg', 'Lote inválido (clint-AAAAMMDDTHHMMSS).');
  end if;
  if p_contagens is null or jsonb_typeof(p_contagens) <> 'object' or length(p_contagens::text) > 20000 then
    return jsonb_build_object('ok', false, 'msg', 'Contagens inválidas.');
  end if;
  if p_acao = 'abrir' then
    insert into arquivo.clint_lote (lote) values (p_lote) on conflict (lote) do nothing;
  elsif p_acao in ('completo', 'incompleto') then
    update arquivo.clint_lote set situacao = p_acao, terminado_em = now(), contagens = p_contagens
     where lote = p_lote and situacao = 'aberto';
    if not found then return jsonb_build_object('ok', false, 'msg', 'Lote não está aberto.'); end if;
  else
    return jsonb_build_object('ok', false, 'msg', 'Ação inválida (abrir, completo, incompleto).');
  end if;
  return jsonb_build_object('ok', true, 'lote', p_lote);
end
$$;

-- p_itens = [{clint_id, pai_id?, payload}] (até 1000). Upsert idempotente: payload igual só atualiza visto_em/lote.
create function public.crm_clint_staging_gravar(p_lote text, p_tipo text, p_itens jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_novos int; v_alt int; v_tot int;
begin
  if not exists (select 1 from arquivo.clint_lote l where l.lote = p_lote and l.situacao = 'aberto') then
    return jsonb_build_object('ok', false, 'msg', 'Lote inexistente ou fechado.');
  end if;
  if p_tipo not in ('grupo','origem','usuario','motivo','tag','campo','contato','negocio','atividade','historico') then
    return jsonb_build_object('ok', false, 'msg', 'Tipo inválido.');
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) > 1000 then
    return jsonb_build_object('ok', false, 'msg', 'Itens: lista de até 1000.');
  end if;
  if exists (select 1 from jsonb_array_elements(p_itens) x
              where coalesce(x ->> 'clint_id', '') = '' or length(x ->> 'clint_id') > 200
                 or jsonb_typeof(x -> 'payload') is distinct from 'object' or length((x -> 'payload')::text) > 200000) then
    return jsonb_build_object('ok', false, 'msg', 'Item sem clint_id, sem payload objeto ou grande demais.');
  end if;
  v_tot := jsonb_array_length(p_itens);
  -- contagem ANTES do upsert (novo = não existia; alterado = existia com outro md5)
  select count(*) filter (where o.clint_id is null), count(*) filter (where o.hash <> md5((x -> 'payload')::text))
    into v_novos, v_alt
    from (select distinct on (x ->> 'clint_id') x from jsonb_array_elements(p_itens) x order by x ->> 'clint_id') d(x)
    left join arquivo.clint_objeto o on o.tipo = p_tipo and o.clint_id = x ->> 'clint_id';
  insert into arquivo.clint_objeto as o (tipo, clint_id, pai_id, payload, hash, lote)
  select p_tipo, x.cid, x.pai, x.pl, md5(x.pl::text), p_lote
    from (select distinct on (x ->> 'clint_id') x ->> 'clint_id' cid, nullif(x ->> 'pai_id', '') pai, x -> 'payload' pl
            from jsonb_array_elements(p_itens) x order by x ->> 'clint_id') x
  on conflict (tipo, clint_id) do update
     set lote = excluded.lote, visto_em = now(), pai_id = coalesce(excluded.pai_id, o.pai_id),
         payload = case when o.hash = excluded.hash then o.payload else excluded.payload end,
         alterado_em = case when o.hash = excluded.hash then o.alterado_em else now() end,
         hash = excluded.hash;
  return jsonb_build_object('ok', true, 'recebidos', v_tot, 'novos', v_novos, 'alterados', v_alt);
end
$$;

-- ─── 3. Helpers internos (sem grant; só postgres roda a carga) ───────────────────────────────────────────────────────
create function crm._clint_ts(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
begin
  return nullif(btrim(p), '')::timestamptz;
exception when others then
  return null;
end
$$;

create function crm._clint_txt(p text) returns text            -- minúsculas, sem acento, só [a-z0-9 ]
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(translate(lower(coalesce(p, '')),
               'áàâãäåéèêëíìîïóòôõöúùûüçñý', 'aaaaaaeeeeiiiiooooouuuucny'), '[^a-z0-9]+', ' ', 'g'));
$$;

create function crm._clint_linha_sugerida(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when crm._clint_txt(p) ~ '(^| )(aurum)( |$)' then 'aurum'
    when crm._clint_txt(p) ~ '(holding masters|(^| )hm( |$))' then 'hm'
    when crm._clint_txt(p) ~ '(acelera)' then 'acelera'
    when crm._clint_txt(p) ~ '(ethb|encontro)' then 'ethb'
    when crm._clint_txt(p) ~ '(sessao|viabilidade|seminario|croqui|implantacao)' then 'sv'
    when crm._clint_txt(p) ~ '(holding total|(^| )ht( |$))' then 'ht'
  end;
$$;

create function crm._clint_papel_sugerido(p_nome text, p_pos int, p_total int) returns text
language sql immutable set search_path = '' as $$
  select case
    when crm._clint_txt(p_nome) ~ '(ganho|ganha|fechad|vendid|comprou|matricul)' then 'fechado'
    when crm._clint_txt(p_nome) ~ '(pagamento|boleto|pix|link enviado|aguardando pag)' then 'aguardar_pagamento'
    when crm._clint_txt(p_nome) ~ '(negocia|follow|vai comprar)' then 'negociar'
    when crm._clint_txt(p_nome) ~ '(proposta|oferta|apresenta|reuniao|call|sessao)' then 'apresentar_oferta'
    when crm._clint_txt(p_nome) ~ '(qualific|conexao|conversa|diagnost)' then 'qualificar'
    when crm._clint_txt(p_nome) ~ '(novo|entrada|lead|primeiro|base|contato|tentativa)' or p_pos = 1 then 'primeiro_contato'
  end;
$$;

create function crm._clint_motivo_sugerido(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when crm._clint_txt(p) ~ '(outro vendedor|duplicad)' then 'ja_atendido_outro_vendedor'
    when crm._clint_txt(p) ~ '(descadastr|nao quer contato|pediu para nao|bloque|spam)' then 'pediu_sem_contato'
    when crm._clint_txt(p) ~ '(invalid|errad|inexistente)' then 'contato_invalido'
    when crm._clint_txt(p) ~ '(comprou)' then 'comprou_outro_produto'
    when crm._clint_txt(p) ~ '(dinheiro|financ|caro|preco|valor|condic)' then 'sem_condicao_financeira'
    when crm._clint_txt(p) ~ '(momento|depois|futuro|agora nao)' then 'nao_e_o_momento'
    when crm._clint_txt(p) ~ '(perfil|nao e advogado|estudante)' then 'fora_do_perfil'
    when crm._clint_txt(p) ~ '(nao atende|sem resposta|nao respond|tentativa|sumiu|ghost)' then 'tentativas_esgotadas'
    when crm._clint_txt(p) ~ '(interesse|desist)' then 'sem_interesse'
  end;
$$;

create function crm._clint_destino_sugerido(p_chave text, p_rotulo text) returns text
language sql immutable set search_path = '' as $$
  select case
    when crm._clint_txt(p_chave) in ('utm source','utm medium','utm campaign','utm content','utm term')
      then replace(crm._clint_txt(p_chave), ' ', '_')
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(profiss|perfil)' then 'campo:perfil_profissional'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(holding)' then 'campo:atua_com_holding'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(produto|interesse)' then 'campo:produto_interesse'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(objec)' then 'campo:objecao_principal'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(pagamento)' then 'campo:forma_pagamento'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(origem)' then 'campo:origem'
    when crm._clint_txt(coalesce(p_rotulo, p_chave)) ~ '(cpf|cnpj|rg|documento|senha)' then 'ignorar'   -- CPF não entra
    else 'nota'
  end;
$$;

-- valor de campo da Clint → valor aceito por crm.campo_def (null = não cabe: vai para a nota)
create function crm._clint_valor_campo(p_chave text, p_valor text) returns text
language plpgsql stable set search_path = '' as $$
declare d record; v text := nullif(btrim(coalesce(p_valor, '')), ''); n text;
begin
  if v is null then return null; end if;
  select * into d from crm.campo_def c where c.chave = p_chave and c.ativo;
  if not found then return null; end if;
  if d.tipo = 'texto' then return left(v, 300); end if;
  n := replace(crm._clint_txt(v), ' ', '_');
  if d.tipo = 'opcao' then
    return case when n = any(d.opcoes) then n
                when n in ('nao', 'n') and 'nao' = any(d.opcoes) then 'nao'
                when n in ('s', 'yes') and 'sim' = any(d.opcoes) then 'sim' end;
  end if;
  return (select l.chave from crm.linha l where l.chave = n or crm._clint_txt(l.nome) = crm._clint_txt(v) limit 1);
end
$$;

-- ─── 4. Mapas: sugestão a partir do staging ──────────────────────────────────────────────────────────────────────────
create function crm.clint_preparar_mapas() returns jsonb
language plpgsql set search_path = '' as $$
declare v_f int; v_e int; v_u int; v_m int; v_c int;
begin
  -- funis (origins) e etapas (stages)
  insert into arquivo.clint_mapa_funil (clint_origem_id, nome, grupo_nome, arquivado_clint, linha)
  select o.clint_id, left(coalesce(nullif(btrim(o.payload ->> 'name'), ''), 'Origem ' || o.clint_id), 200),
         left(o.payload #>> '{group,name}', 200), o.payload ->> 'archived_at' is not null,
         crm._clint_linha_sugerida(coalesce(o.payload #>> '{group,name}', '') || ' ' || coalesce(o.payload ->> 'name', ''))
    from arquivo.clint_objeto o where o.tipo = 'origem'
  on conflict (clint_origem_id) do update
     set nome = excluded.nome, grupo_nome = excluded.grupo_nome, arquivado_clint = excluded.arquivado_clint;
  get diagnostics v_f = row_count;

  insert into arquivo.clint_mapa_etapa (clint_etapa_id, clint_origem_id, nome, ordem, tipo_clint, papel)
  select s ->> 'id', o.clint_id, left(coalesce(nullif(btrim(s ->> 'label'), ''), 'Etapa'), 200),
         coalesce((s ->> 'order')::int, i::int), s ->> 'type',
         crm._clint_papel_sugerido(s ->> 'label', i::int, jsonb_array_length(o.payload -> 'stages'))
    from arquivo.clint_objeto o
   cross join lateral jsonb_array_elements(case when jsonb_typeof(o.payload -> 'stages') = 'array'
                                                then o.payload -> 'stages' else '[]' end) with ordinality x(s, i)
   where o.tipo = 'origem' and coalesce(s ->> 'id', '') <> ''
  on conflict (clint_etapa_id) do update
     set nome = excluded.nome, ordem = excluded.ordem, tipo_clint = excluded.tipo_clint,
         papel = case when arquivo.clint_mapa_etapa.confirmado then arquivo.clint_mapa_etapa.papel else excluded.papel end;
  get diagnostics v_e = row_count;

  -- usuários: casa com perfis pelo e-mail (equipe); o gestor pode fixar à mão (confirmado)
  insert into arquivo.clint_mapa_usuario (clint_usuario_id, nome, email_norm)
  select o.clint_id, left(btrim(concat_ws(' ', o.payload ->> 'first_name', o.payload ->> 'last_name')), 200),
         lower(btrim(o.payload ->> 'email'))
    from arquivo.clint_objeto o where o.tipo = 'usuario'
  on conflict (clint_usuario_id) do update set nome = excluded.nome, email_norm = excluded.email_norm;
  update arquivo.clint_mapa_usuario mu
     set perfil_id = (select p.id from public.perfis p where lower(btrim(p.email)) = mu.email_norm limit 1)
   where not mu.confirmado;
  get diagnostics v_u = row_count;

  -- motivos de perda (+ "sem motivo")
  insert into arquivo.clint_mapa_motivo (clint_motivo_id, nome, motivo_chave)
  select o.clint_id, left(coalesce(o.payload ->> 'name', o.clint_id), 200), crm._clint_motivo_sugerido(o.payload ->> 'name')
    from arquivo.clint_objeto o where o.tipo = 'motivo'
  union all
  select 'sem_motivo', '(perdido sem motivo na Clint)', null
  on conflict (clint_motivo_id) do update
     set nome = excluded.nome,
         motivo_chave = case when arquivo.clint_mapa_motivo.confirmado then arquivo.clint_mapa_motivo.motivo_chave
                             else excluded.motivo_chave end;
  get diagnostics v_m = row_count;

  -- campos: do cadastro (tipo campo) e de toda chave vista nos payloads
  insert into arquivo.clint_mapa_campo (entidade, chave, rotulo, tipo_clint, destino)
  select distinct on (x.ent, x.k) x.ent, x.k, x.rot, x.tp, crm._clint_destino_sugerido(x.k, x.rot)
    from (
      select o.payload ->> 'entidade' ent, o.payload ->> 'chave' k, o.payload ->> 'label' rot, o.payload ->> 'type' tp, 0 pr
        from arquivo.clint_objeto o where o.tipo = 'campo' and o.payload ->> 'entidade' in ('CONTACT', 'DEAL')
      union all
      select 'CONTACT', f.k, null, null, 1 from arquivo.clint_objeto o, jsonb_object_keys(
               case when jsonb_typeof(o.payload -> 'fields') = 'object' then o.payload -> 'fields' else '{}' end) f(k)
       where o.tipo = 'contato'
      union all
      select 'DEAL', f.k, null, null, 1 from arquivo.clint_objeto o, jsonb_object_keys(
               case when jsonb_typeof(o.payload -> 'fields') = 'object' then o.payload -> 'fields' else '{}' end) f(k)
       where o.tipo = 'negocio'
    ) x
   where coalesce(x.k, '') <> ''
   order by x.ent, x.k, x.pr
  on conflict (entidade, chave) do update
     set rotulo = coalesce(excluded.rotulo, arquivo.clint_mapa_campo.rotulo),
         tipo_clint = coalesce(excluded.tipo_clint, arquivo.clint_mapa_campo.tipo_clint),
         destino = case when arquivo.clint_mapa_campo.confirmado then arquivo.clint_mapa_campo.destino
                        else crm._clint_destino_sugerido(arquivo.clint_mapa_campo.chave,
                                                         coalesce(excluded.rotulo, arquivo.clint_mapa_campo.rotulo)) end;
  get diagnostics v_c = row_count;

  return jsonb_build_object('ok', true, 'funis', v_f, 'etapas', v_e, 'usuarios', v_u, 'motivos', v_m, 'campos', v_c,
    'pendentes', jsonb_build_object(
      'funis_sem_confirmar', (select count(*) from arquivo.clint_mapa_funil where importar and not confirmado),
      'etapas_sem_confirmar', (select count(*) from arquivo.clint_mapa_etapa e join arquivo.clint_mapa_funil f
                                 using (clint_origem_id) where f.importar and not e.confirmado),
      'usuarios_sem_perfil', (select count(*) from arquivo.clint_mapa_usuario where perfil_id is null),
      'motivos_sem_confirmar', (select count(*) from arquivo.clint_mapa_motivo where not confirmado),
      'campos_sem_confirmar', (select count(*) from arquivo.clint_mapa_campo where not confirmado)));
end
$$;

-- ─── 5. crm.tg_negocio_notifica (corpo da F2 + linha da carga Clint) ─────────────────────────────────────────────────
create or replace function crm.tg_negocio_notifica() returns trigger
language plpgsql set search_path = '' as $$
declare v_gat text; v_tit text; v_corpo text; v_nome text;
begin
  if new.dono_id is null then return null; end if;
  if coalesce(current_setting('crm.canal', true), '') = 'clint_import' then return null; end if;   -- 20261006d: carga da Clint não avisa
  if new.status = 'aberto' and (tg_op = 'INSERT' or old.dono_id is distinct from new.dono_id)
     and new.dono_id is distinct from auth.uid() then
    v_gat := 'lead_novo';
  elsif tg_op = 'UPDATE' and new.status = 'ganho' and old.status is distinct from 'ganho' then
    v_gat := 'venda_aprovada';
  else
    return null;
  end if;
  begin
    if exists (select 1 from crm.preferencias_notificacao p
                where p.perfil_id = new.dono_id and (p.gatilhos ->> v_gat) = 'false') then
      return null;
    end if;
    v_nome := crm.nome_pessoa(new.pessoa_id);
    if v_gat = 'lead_novo' then
      v_tit := 'Lead novo: ' || v_nome;
      v_corpo := coalesce((select e.nome from crm.etapa_funil e where e.id = new.etapa_id), 'Entrada') || ' · primeiro contato em até 5 minutos.';
    else
      v_tit := 'Venda aprovada: ' || v_nome;
      v_corpo := coalesce((select l.nome from crm.linha l where l.chave = new.linha), new.linha) || ' · pagamento aprovado na Hotmart.';
    end if;
    insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
    values (new.dono_id, v_gat, new.id::text, left(v_tit, 200), left(v_corpo, 500), '/comercial/funil?negocio=' || new.id)
    on conflict (perfil_id, gatilho, ref_id) do nothing;
  exception when others then
    raise warning 'crm.tg_negocio_notifica: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;

-- ─── 6. A carga ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- Grava o resultado de um objeto (idempotente).
create function crm._clint_res(p_tipo text, p_id text, p_status text, p_hash text, p_detalhe jsonb default '{}',
                               p_pessoa uuid default null, p_negocio uuid default null, p_nota uuid default null,
                               p_atividade uuid default null) returns void
language sql set search_path = '' as $$
  insert into arquivo.clint_resultado as r (tipo, clint_id, status, pessoa_id, negocio_id, nota_id, atividade_id, detalhe, hash_processado)
  values (p_tipo, p_id, p_status, p_pessoa, p_negocio, p_nota, p_atividade, coalesce(p_detalhe, '{}'), p_hash)
  on conflict (tipo, clint_id) do update
     set status = excluded.status, pessoa_id = coalesce(excluded.pessoa_id, r.pessoa_id),
         negocio_id = coalesce(excluded.negocio_id, r.negocio_id), nota_id = coalesce(excluded.nota_id, r.nota_id),
         atividade_id = coalesce(excluded.atividade_id, r.atividade_id), detalhe = r.detalhe || excluded.detalhe,
         hash_processado = excluded.hash_processado, processado_em = now();
$$;

-- Status que NÃO se reprocessa (o resto — pendente_*, erro, ganho_sem_transacao — tenta de novo a cada chamada).
create function crm._clint_final(p_status text) returns boolean
language sql immutable set search_path = '' as $$
  select p_status in ('ok', 'duplicado', 'sem_identificador', 'ignorado');
$$;

create function crm._clint_carregar(p_limite int, p_opcoes jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_lim       int := greatest(1, least(coalesce(p_limite, 300), 2000));
  v_so_neg    boolean := coalesce((p_opcoes ->> 'so_contatos_com_negocio')::boolean, true);
  v_ganho     boolean := coalesce((p_opcoes ->> 'ganho_por_transacao')::boolean, true);
  v_jan_antes interval := make_interval(days => coalesce((p_opcoes ->> 'ganho_janela_dias_antes')::int, 30));
  v_jan_depois interval := make_interval(days => coalesce((p_opcoes ->> 'ganho_janela_dias_depois')::int, 7));
  c jsonb := '{}';                 -- contadores desta chamada
  r record; m record; s record;
  v_res jsonb; v_pessoa uuid; v_funil uuid; v_etapa uuid; v_fech uuid; v_ag uuid; v_dono uuid; v_neg uuid; v_nota uuid;
  v_ativ uuid; v_status text; v_motivo text; v_campos jsonb; v_utm jsonb; v_extra text; v_txt text; v_email text;
  v_tx text; v_valor numeric; v_n int; v_ord int; v_nomes text[]; v_tags text[]; v_k text; v_v text; v_dest text;
  v_det jsonb; v_criado timestamptz; v_fechado timestamptz; v_tipo text;
begin
  perform set_config('crm.canal', 'clint_import', true);

  -- 6.1 funis confirmados ainda não criados (todas as etapas da origem confirmadas; no máximo 1 'fechado')
  for m in select f.* from arquivo.clint_mapa_funil f
            where f.importar and f.confirmado and f.funil_id is null
              and not exists (select 1 from arquivo.clint_mapa_etapa e where e.clint_origem_id = f.clint_origem_id and not e.confirmado)
              and (select count(*) from arquivo.clint_mapa_etapa e where e.clint_origem_id = f.clint_origem_id and e.papel = 'fechado') <= 1
            order by f.nome loop
    v_ag := coalesce(m.agrupador_id, (select a.id from crm.agrupador a where a.linha = m.linha and a.arquivado_em is null
                                       order by a.ordem, a.criado_em limit 1));
    if v_ag is null then c := jsonb_set(c, '{funis_sem_agrupador}', to_jsonb(coalesce((c ->> 'funis_sem_agrupador')::int, 0) + 1)); continue; end if;
    perform set_config('crm.resumo', 'Importou da Clint o funil ' || left('Clint · ' || m.nome, 80), true);
    insert into crm.funil (nome, icone, agrupador_id, linha, tipo)
    values (left('Clint · ' || m.nome, 80), 'kanban', v_ag, m.linha, 'manual') returning id into v_funil;
    v_ord := 0; v_nomes := '{}'; v_fech := null;
    for s in select e.* from arquivo.clint_mapa_etapa e where e.clint_origem_id = m.clint_origem_id
              order by (e.papel = 'fechado'), e.ordem, e.nome loop
      v_txt := left(s.nome, 60);
      if lower(v_txt) = any(v_nomes) then v_txt := left(s.nome, 50) || ' (' || (v_ord + 1) || ')'; end if;
      v_nomes := v_nomes || lower(v_txt);
      insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, criterio)
      values (v_funil, v_ord, v_txt, s.papel,
              case s.papel when 'primeiro_contato' then 'info' when 'qualificar' then 'cyan' when 'apresentar_oferta' then 'purple'
                           when 'negociar' then 'accent' when 'aguardar_pagamento' then 'yellow' else 'green' end,
              'Etapa importada da Clint')
      returning id into v_etapa;
      update arquivo.clint_mapa_etapa set etapa_id = v_etapa where clint_etapa_id = s.clint_etapa_id;
      if s.papel = 'fechado' then v_fech := v_etapa; end if;
      v_ord := v_ord + 1;
    end loop;
    if v_fech is null then
      insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, criterio)
      values (v_funil, v_ord, case when 'fechado' = any(v_nomes) then 'Fechado (Clint)' else 'Fechado' end, 'fechado', 'green',
              'Ganho é pagamento aprovado na Hotmart')
      returning id into v_fech;
    end if;
    update arquivo.clint_mapa_funil set funil_id = v_funil, etapa_fechado_id = v_fech where clint_origem_id = m.clint_origem_id;
    c := jsonb_set(c, '{funis_criados}', to_jsonb(coalesce((c ->> 'funis_criados')::int, 0) + 1));
  end loop;
  perform set_config('crm.resumo', '', true);

  -- 6.2 contatos → pessoas.registrar (cascata da F0). Contato só citado em negócio usa o contato embutido no negócio.
  for r in
    select x.cid, x.pl, x.h from (
      select o.clint_id cid, o.payload pl, o.hash h from arquivo.clint_objeto o where o.tipo = 'contato'
      union all
      (select distinct on (d.payload #>> '{contact,id}') d.payload #>> '{contact,id}',
             jsonb_build_object('name', d.payload #>> '{contact,name}', 'email', d.payload #>> '{contact,email}',
                                'fullPhone', d.payload #>> '{contact,phone}', '_do_negocio', true),
             md5(coalesce(d.payload -> 'contact', '{}'::jsonb)::text)
        from arquivo.clint_objeto d
       where d.tipo = 'negocio' and coalesce(d.payload #>> '{contact,id}', '') <> ''
         and not exists (select 1 from arquivo.clint_objeto o2 where o2.tipo = 'contato' and o2.clint_id = d.payload #>> '{contact,id}')
       order by d.payload #>> '{contact,id}')
    ) x
    left join arquivo.clint_resultado rs on rs.tipo = 'contato' and rs.clint_id = x.cid
    where (rs.status is null or not crm._clint_final(rs.status))
      and (not v_so_neg or exists (select 1 from arquivo.clint_objeto d where d.tipo = 'negocio' and d.payload #>> '{contact,id}' = x.cid))
    order by x.cid
    limit v_lim
  loop
    begin
      if pessoas.norm_email(r.pl ->> 'email') is null and pessoas.chave_telefone(r.pl ->> 'fullPhone') is null then
        perform crm._clint_res('contato', r.cid, 'sem_identificador', r.h);
        c := jsonb_set(c, '{contatos_sem_identificador}', to_jsonb(coalesce((c ->> 'contatos_sem_identificador')::int, 0) + 1));
        continue;
      end if;
      -- UTMs do contato (só campos mapeados e confirmados como utm_*)
      v_utm := '{}';
      for v_k, v_v in select e.key, e.value #>> '{}' from jsonb_each(case when jsonb_typeof(r.pl -> 'fields') = 'object'
                                                                       then r.pl -> 'fields' else '{}' end) e loop
        select mc.destino into v_dest from arquivo.clint_mapa_campo mc
         where mc.entidade = 'CONTACT' and mc.chave = v_k and mc.confirmado;
        if v_dest like 'utm\_%' and nullif(btrim(v_v), '') is not null then v_utm := v_utm || jsonb_build_object(v_dest, left(v_v, 300)); end if;
      end loop;
      v_res := pessoas.registrar(jsonb_build_object('nome', r.pl ->> 'name', 'email', r.pl ->> 'email',
                                                    'telefone', r.pl ->> 'fullPhone', 'evento', 'cadastro') || v_utm,
                                 'importacao', null);
      if not coalesce((v_res ->> 'ok')::boolean, false) then
        perform crm._clint_res('contato', r.cid, 'erro', r.h, jsonb_build_object('msg', v_res ->> 'msg'));
        c := jsonb_set(c, '{contatos_erro}', to_jsonb(coalesce((c ->> 'contatos_erro')::int, 0) + 1));
        continue;
      end if;
      v_pessoa := (v_res ->> 'pessoa_id')::uuid;
      -- tags → pessoa_comercial (união, máx. 30); a linha comercial nasce aqui (contato da Clint é contato comercial)
      v_tags := array(select distinct left(btrim(t ->> 'name'), 60) from jsonb_array_elements(
                        case when jsonb_typeof(r.pl -> 'tags') = 'array' then r.pl -> 'tags' else '[]' end) t
                       where nullif(btrim(t ->> 'name'), '') is not null);
      for v_k, v_v in select e.key, e.value #>> '{}' from jsonb_each(case when jsonb_typeof(r.pl -> 'fields') = 'object'
                                                                       then r.pl -> 'fields' else '{}' end) e loop
        if exists (select 1 from arquivo.clint_mapa_campo mc where mc.entidade = 'CONTACT' and mc.chave = v_k
                      and mc.confirmado and mc.destino = 'tag') and nullif(btrim(v_v), '') is not null then
          v_tags := v_tags || left(btrim(v_v), 60);
        end if;
      end loop;
      v_ativ := crm.garantir_pc(v_pessoa);   -- linha comercial do grupo (F2); aqui só o id da pessoa
      if cardinality(v_tags) > 0 then
        perform set_config('crm.resumo', 'Tags da Clint', true);
        update crm.pessoa_comercial pc
           set tags = (array(select distinct t from unnest(pc.tags || v_tags) t order by t))[1:30], atualizado_em = now()
         where pc.pessoa_id = v_ativ and not (v_tags <@ pc.tags) and cardinality(pc.tags) < 30;
        perform set_config('crm.resumo', '', true);
      end if;
      v_ativ := null;
      perform crm._clint_res('contato', r.cid, 'ok', r.h,
                             jsonb_build_object('como', v_res ->> 'como', 'nova', (v_res ->> 'nova')::boolean,
                                                'revisao', v_res ->> 'revisao', 'do_negocio', coalesce((r.pl ->> '_do_negocio')::boolean, false)),
                             v_pessoa);
      v_k := case when v_res ->> 'revisao' is not null then 'contatos_em_revisao'
                  when (v_res ->> 'nova')::boolean then 'contatos_criados'
                  when v_res ->> 'como' = 'telefone' then 'contatos_casados_telefone'
                  else 'contatos_casados_email' end;
      c := jsonb_set(c, array[v_k], to_jsonb(coalesce((c ->> v_k)::int, 0) + 1));
    exception when others then
      perform crm._clint_res('contato', r.cid, 'erro', r.h, jsonb_build_object('msg', left(sqlerrm, 200), 'estado', sqlstate));
      c := jsonb_set(c, '{contatos_erro}', to_jsonb(coalesce((c ->> 'contatos_erro')::int, 0) + 1));
    end;
  end loop;

  -- 6.3 negócios
  for r in
    select d.clint_id cid, d.payload pl, d.hash h, mf.funil_id, mf.etapa_fechado_id, mf.linha, mf.nome funil_nome,
           mf.importar, rc.pessoa_id contato_pessoa, rc.status contato_status
      from arquivo.clint_objeto d
      left join arquivo.clint_resultado rs on rs.tipo = 'negocio' and rs.clint_id = d.clint_id
      left join arquivo.clint_mapa_funil mf on mf.clint_origem_id = d.payload ->> 'origin_id'
      left join arquivo.clint_resultado rc on rc.tipo = 'contato' and rc.clint_id = d.payload #>> '{contact,id}'
     where d.tipo = 'negocio' and (rs.status is null or not crm._clint_final(rs.status))
     order by d.payload ->> 'created_at', d.clint_id
     limit v_lim
  loop
    begin
      v_status := upper(coalesce(r.pl ->> 'status', 'OPEN'));
      if r.importar is false then
        perform crm._clint_res('negocio', r.cid, 'ignorado', r.h, jsonb_build_object('motivo', 'funil_nao_importar'));
        c := jsonb_set(c, '{negocios_ignorados}', to_jsonb(coalesce((c ->> 'negocios_ignorados')::int, 0) + 1));
        continue;
      end if;
      if r.funil_id is null then
        perform crm._clint_res('negocio', r.cid, 'pendente_mapa', r.h, jsonb_build_object('falta', 'funil'));
        c := jsonb_set(c, '{negocios_pendente_mapa}', to_jsonb(coalesce((c ->> 'negocios_pendente_mapa')::int, 0) + 1));
        continue;
      end if;
      if r.contato_status is distinct from 'ok' or r.contato_pessoa is null then
        v_k := case when r.contato_status in ('sem_identificador', 'ignorado') then 'ignorado' else 'pendente_contato' end;
        perform crm._clint_res('negocio', r.cid, v_k, r.h, jsonb_build_object('contato', coalesce(r.contato_status, 'nao_processado')));
        c := jsonb_set(c, array['negocios_' || v_k], to_jsonb(coalesce((c ->> ('negocios_' || v_k))::int, 0) + 1));
        continue;
      end if;
      v_pessoa := pessoas.atual(r.contato_pessoa);
      v_etapa := case when v_status = 'WON' then r.etapa_fechado_id
                      else (select me.etapa_id from arquivo.clint_mapa_etapa me where me.clint_etapa_id = r.pl ->> 'stage_id') end;
      if v_etapa is null then
        perform crm._clint_res('negocio', r.cid, 'pendente_mapa', r.h, jsonb_build_object('falta', 'etapa'));
        c := jsonb_set(c, '{negocios_pendente_mapa}', to_jsonb(coalesce((c ->> 'negocios_pendente_mapa')::int, 0) + 1));
        continue;
      end if;
      -- dono: usuário da Clint → perfil → vendedor ativo (senão sem dono)
      select mu.perfil_id into v_dono from arquivo.clint_mapa_usuario mu where mu.clint_usuario_id = r.pl #>> '{user,id}';
      if v_dono is not null and not exists (select 1 from crm.vendedor v where v.perfil_id = v_dono and v.ativo) then v_dono := null; end if;
      -- campos: destino confirmado campo:<chave> com valor aceito; o resto vai para a nota (utm → negocio.utm)
      v_campos := '{}'; v_utm := '{}'; v_extra := '';
      for v_k, v_v in select e.key, e.value #>> '{}' from jsonb_each(case when jsonb_typeof(r.pl -> 'fields') = 'object'
                                                                       then r.pl -> 'fields' else '{}' end) e order by e.key loop
        continue when nullif(btrim(coalesce(v_v, '')), '') is null;
        select mc.destino, mc.rotulo into v_dest, v_txt from arquivo.clint_mapa_campo mc
         where mc.entidade = 'DEAL' and mc.chave = v_k and mc.confirmado;
        if v_dest like 'campo:%' and crm._clint_valor_campo(substr(v_dest, 7), v_v) is not null then
          v_campos := v_campos || jsonb_build_object(substr(v_dest, 7), crm._clint_valor_campo(substr(v_dest, 7), v_v));
        elsif v_dest like 'utm\_%' then
          v_utm := v_utm || jsonb_build_object(v_dest, left(v_v, 300));
        elsif v_dest is distinct from 'ignorar' and v_dest is distinct from 'tag' then
          v_extra := v_extra || E'\n· ' || coalesce(v_txt, v_k) || ': ' || left(v_v, 300);
        end if;
        v_dest := null; v_txt := null;
      end loop;
      v_criado := coalesce(crm._clint_ts(r.pl ->> 'created_at'), now());
      v_tx := null; v_n := 0; v_valor := 0; v_motivo := null; v_fechado := null;

      if v_status = 'LOST' then
        select mm.motivo_chave into v_motivo from arquivo.clint_mapa_motivo mm
         where mm.clint_motivo_id = coalesce(nullif(r.pl ->> 'lost_status_id', ''), 'sem_motivo') and mm.confirmado
           and exists (select 1 from crm.motivo_perda mp where mp.chave = mm.motivo_chave and mp.ativo);
        if v_motivo is null then
          perform crm._clint_res('negocio', r.cid, 'pendente_motivo', r.h, '{}');
          c := jsonb_set(c, '{negocios_pendente_motivo}', to_jsonb(coalesce((c ->> 'negocios_pendente_motivo')::int, 0) + 1));
          continue;
        end if;
        v_fechado := coalesce(crm._clint_ts(r.pl ->> 'lost_at'), crm._clint_ts(r.pl ->> 'updated_stage_at'), v_criado);
      elsif v_status = 'WON' then
        v_fechado := coalesce(crm._clint_ts(r.pl ->> 'won_at'), crm._clint_ts(r.pl ->> 'updated_stage_at'), v_criado);
        if v_ganho then
          v_email := coalesce(pessoas.norm_email(r.pl #>> '{contact,email}'), (select d.d_email from pessoas.dados(v_pessoa) d));
          -- 1 transação aprovada, da linha do funil, na janela, ainda não usada por outro negócio (fin.trava_conta_hotmart: forma canônica)
          select min(h.transacao), count(distinct h.transacao), min(h.valor_cobrado) into v_tx, v_n, v_valor
            from (select * from fin.hotmart_transacoes where conta = 'academy'
                  union all
                  select * from fin.hotmart_transacoes where conta = 'escritorio') h
            join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = r.linha
           where v_email is not null and lower(btrim(h.comprador_email)) = v_email
             and h.status in ('APPROVED', 'COMPLETE') and coalesce(h.recorrencia, 1) = 1
             and coalesce(h.aprovado_em, h.pedido_em) between v_fechado - v_jan_antes and v_fechado + v_jan_depois
             and not exists (select 1 from crm.negocio n where n.transacao_ganho = h.transacao);
          if v_n <> 1 then v_tx := null; end if;
        end if;
        if v_tx is null then
          -- não vira negócio (ganho é pagamento): fica na jornada da pessoa como evento, 1 vez
          if not exists (select 1 from arquivo.clint_resultado x where x.tipo = 'negocio' and x.clint_id = r.cid and x.detalhe ? 'evento') then
            insert into pessoas.eventos (pessoa_id, tipo, fonte, detalhe, quando)
            values (v_pessoa, 'crm', 'importacao',
                    jsonb_build_object('clint', 'ganho_sem_transacao', 'funil', left(r.funil_nome, 120), 'linha', r.linha,
                                       'candidatas', coalesce(v_n, 0)),
                    v_fechado)
            returning id into v_n;
            v_det := jsonb_build_object('evento', v_n);
          else
            v_det := '{}';
          end if;
          perform crm._clint_res('negocio', r.cid, 'ganho_sem_transacao', r.h, v_det, v_pessoa);
          c := jsonb_set(c, '{negocios_ganho_sem_transacao}', to_jsonb(coalesce((c ->> 'negocios_ganho_sem_transacao')::int, 0) + 1));
          continue;
        end if;
      end if;

      if v_status not in ('LOST', 'WON') then
        -- 1 aberto por pessoa+funil: o 2º é duplicado (nota vai para o que já existe)
        select n.id into v_neg from crm.negocio n where n.pessoa_id = any(pessoas.grupo(v_pessoa)) and n.funil_id = r.funil_id and n.status = 'aberto' limit 1;
        if v_neg is not null then
          perform crm._clint_res('negocio', r.cid, 'duplicado', r.h, jsonb_build_object('negocio_existente', v_neg), v_pessoa, v_neg);
          c := jsonb_set(c, '{negocios_duplicados}', to_jsonb(coalesce((c ->> 'negocios_duplicados')::int, 0) + 1));
          v_neg := null;
          continue;
        end if;
      end if;

      perform crm.garantir_pc(v_pessoa);
      if v_dono is not null and v_status not in ('LOST', 'WON') then
        update crm.pessoa_comercial set dono_id = v_dono, atualizado_em = now()
         where pessoa_id = any(pessoas.grupo(v_pessoa)) and dono_id is null;
      end if;
      perform set_config('crm.resumo', 'Importou da Clint: ' || left(r.funil_nome, 80), true);
      if v_tx is not null then perform set_config('crm.ganho_hotmart', 'on', true); end if;
      insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, status, dono_id, valor, campos, motivo_perda,
                               nota_perda, transacao_ganho, utm, criado_em, etapa_desde, fechado_em)
      values (v_pessoa, r.funil_id, v_etapa, r.linha, 'venda_ativa',
              case v_status when 'LOST' then 'perdido' when 'WON' then 'ganho' else 'aberto' end,
              v_dono, coalesce(v_valor, 0), v_campos, v_motivo,
              case when v_status = 'LOST' then left('Perdido na Clint: ' || coalesce((select mm.nome from arquivo.clint_mapa_motivo mm
                       where mm.clint_motivo_id = coalesce(nullif(r.pl ->> 'lost_status_id', ''), 'sem_motivo')), '?'), 1000) end,
              v_tx, v_utm, v_criado, coalesce(crm._clint_ts(r.pl ->> 'updated_stage_at'), v_criado), v_fechado)
      returning id into v_neg;
      perform set_config('crm.ganho_hotmart', '', true);
      -- nota de origem: dono/etapa da Clint + campos sem destino
      v_txt := 'Importado da Clint (negócio ' || r.cid || '). Funil: ' || r.funil_nome
               || coalesce('. Etapa na Clint: ' || (select me.nome from arquivo.clint_mapa_etapa me where me.clint_etapa_id = r.pl ->> 'stage_id'), '')
               || coalesce('. Dono na Clint: ' || nullif(r.pl #>> '{user,full_name}', ''), '')
               || case when v_dono is null and nullif(r.pl #>> '{user,id}', '') is not null then ' (sem vendedor correspondente no CRM)' else '' end
               || '. Status: ' || v_status || '.'
               || case when v_extra <> '' then E'\nCampos da Clint:' || v_extra else '' end;
      perform set_config('crm.resumo', 'Nota de importação da Clint', true);
      insert into crm.nota (pessoa_id, negocio_id, texto, em) values (v_pessoa, v_neg, left(v_txt, 5000), now()) returning id into v_nota;
      perform set_config('crm.resumo', '', true);
      perform crm._clint_res('negocio', r.cid, 'ok', r.h, jsonb_build_object('status', v_status, 'sem_dono', v_dono is null,
                             'ganho_transacao', v_tx is not null), v_pessoa, v_neg, v_nota);
      v_k := 'negocios_' || case v_status when 'LOST' then 'perdidos' when 'WON' then 'ganhos' else 'abertos' end;
      c := jsonb_set(c, array[v_k], to_jsonb(coalesce((c ->> v_k)::int, 0) + 1));
      if v_dono is null then c := jsonb_set(c, '{negocios_sem_dono}', to_jsonb(coalesce((c ->> 'negocios_sem_dono')::int, 0) + 1)); end if;
      v_neg := null;
    exception when others then
      perform set_config('crm.ganho_hotmart', '', true);
      perform crm._clint_res('negocio', r.cid, 'erro', r.h, jsonb_build_object('msg', left(sqlerrm, 200), 'estado', sqlstate));
      c := jsonb_set(c, '{negocios_erro}', to_jsonb(coalesce((c ->> 'negocios_erro')::int, 0) + 1));
    end;
  end loop;

  -- 6.4 histórico: notas (categoria de nota) + 1 nota "Histórico na Clint" por negócio, só de negócio criado/duplicado
  for r in
    select rn.clint_id cid, coalesce(rn.negocio_id, (rn.detalhe ->> 'negocio_existente')::uuid) neg, rn.pessoa_id pes
      from arquivo.clint_resultado rn
     where rn.tipo = 'negocio' and rn.status in ('ok', 'duplicado')
       and exists (select 1 from arquivo.clint_objeto h
                    left join arquivo.clint_resultado rh on rh.tipo = 'historico' and rh.clint_id = h.clint_id
                    where h.tipo = 'historico' and h.pai_id = rn.clint_id and rh.clint_id is null)
     order by rn.clint_id
     limit v_lim
  loop
    begin
      v_txt := '';
      for s in select h.clint_id hid, h.payload pl, h.hash hh from arquivo.clint_objeto h
                left join arquivo.clint_resultado rh on rh.tipo = 'historico' and rh.clint_id = h.clint_id
                where h.tipo = 'historico' and h.pai_id = r.cid and rh.clint_id is null
                order by crm._clint_ts(h.payload ->> 'date') nulls first, h.clint_id loop
        if lower(coalesce(s.pl ->> 'category', '')) like '%note%' or lower(coalesce(s.pl ->> 'category', '')) like '%nota%' then
          v_v := nullif(btrim(coalesce(s.pl #>> '{body,text}', s.pl #>> '{body,content}', s.pl #>> '{body,note}',
                                       s.pl #>> '{body,description}', s.pl ->> 'summary', '')), '');
          if v_v is null then
            perform crm._clint_res('historico', s.hid, 'ignorado', s.hh, jsonb_build_object('motivo', 'nota_vazia'));
            continue;
          end if;
          perform set_config('crm.resumo', 'Nota importada da Clint', true);
          insert into crm.nota (pessoa_id, negocio_id, texto, autor_id, em)
          values (r.pes, r.neg, left(v_v, 5000),
                  (select mu.perfil_id from arquivo.clint_mapa_usuario mu where mu.clint_usuario_id = s.pl #>> '{user,id}'),
                  coalesce(crm._clint_ts(s.pl ->> 'date'), now()))
          returning id into v_nota;
          perform crm._clint_res('historico', s.hid, 'ok', s.hh, jsonb_build_object('categoria', left(s.pl ->> 'category', 60)), r.pes, r.neg, v_nota);
          c := jsonb_set(c, '{notas_importadas}', to_jsonb(coalesce((c ->> 'notas_importadas')::int, 0) + 1));
        else
          v_txt := v_txt || E'\n' || coalesce(to_char(crm._clint_ts(s.pl ->> 'date') at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), '?')
                   || ' · ' || coalesce(nullif(s.pl ->> 'summary', ''), lower(coalesce(s.pl ->> 'category', 'evento')))
                   || coalesce(' (' || nullif(s.pl #>> '{user,name}', '') || ')', '');
          perform crm._clint_res('historico', s.hid, 'ok', s.hh, jsonb_build_object('categoria', left(s.pl ->> 'category', 60), 'na_nota_historico', true), r.pes, r.neg);
        end if;
      end loop;
      if v_txt <> '' then
        v_txt := 'Histórico na Clint (negócio ' || r.cid || '):' || v_txt;
        perform set_config('crm.resumo', 'Histórico importado da Clint', true);
        insert into crm.nota (pessoa_id, negocio_id, texto, em)
        values (r.pes, r.neg, case when length(v_txt) > 5000 then left(v_txt, 4980) || E'\n[…cortado]' else v_txt end, now())
        returning id into v_nota;
        c := jsonb_set(c, '{notas_historico}', to_jsonb(coalesce((c ->> 'notas_historico')::int, 0) + 1));
        if length(v_txt) > 5000 then c := jsonb_set(c, '{notas_historico_cortadas}', to_jsonb(coalesce((c ->> 'notas_historico_cortadas')::int, 0) + 1)); end if;
      end if;
      perform set_config('crm.resumo', '', true);
    exception when others then
      c := jsonb_set(c, '{historico_erro}', to_jsonb(coalesce((c ->> 'historico_erro')::int, 0) + 1));
      raise warning 'clint historico % : % (%)', r.cid, left(sqlerrm, 200), sqlstate;
    end;
  end loop;

  -- 6.5 atividades: aberta de negócio aberto → crm.atividade (dono = dono do negócio); concluída fica no histórico
  for r in
    select a.clint_id cid, a.payload pl, a.hash h, rn.negocio_id neg, n.pessoa_id pes, n.dono_id dono, n.status nst, rn.status rst
      from arquivo.clint_objeto a
      left join arquivo.clint_resultado ra on ra.tipo = 'atividade' and ra.clint_id = a.clint_id
      left join arquivo.clint_resultado rn on rn.tipo = 'negocio' and rn.clint_id = coalesce(a.pai_id, a.payload #>> '{deal,id}')
      left join crm.negocio n on n.id = rn.negocio_id
     where a.tipo = 'atividade' and (ra.status is null or not crm._clint_final(ra.status))
     order by a.clint_id
     limit v_lim
  loop
    begin
      if coalesce((r.pl ->> 'completed')::boolean, false) then
        perform crm._clint_res('atividade', r.cid, 'ignorado', r.h, jsonb_build_object('motivo', 'concluida_no_historico'));
        c := jsonb_set(c, '{atividades_concluidas_no_historico}', to_jsonb(coalesce((c ->> 'atividades_concluidas_no_historico')::int, 0) + 1));
        continue;
      end if;
      if r.rst is null or crm._clint_final(r.rst) is not true or r.neg is null then
        v_k := case when r.rst in ('ignorado', 'sem_identificador', 'duplicado', 'ganho_sem_transacao') then 'ignorado' else 'pendente_contato' end;
        perform crm._clint_res('atividade', r.cid, v_k, r.h, jsonb_build_object('negocio', coalesce(r.rst, 'nao_processado')));
        c := jsonb_set(c, array['atividades_' || v_k], to_jsonb(coalesce((c ->> ('atividades_' || v_k))::int, 0) + 1));
        continue;
      end if;
      if r.nst <> 'aberto' then
        perform crm._clint_res('atividade', r.cid, 'ignorado', r.h, jsonb_build_object('motivo', 'negocio_encerrado'));
        c := jsonb_set(c, '{atividades_ignoradas}', to_jsonb(coalesce((c ->> 'atividades_ignoradas')::int, 0) + 1));
        continue;
      end if;
      if r.dono is null then
        perform crm._clint_res('atividade', r.cid, 'pendente_dono', r.h, '{}');
        c := jsonb_set(c, '{atividades_pendente_dono}', to_jsonb(coalesce((c ->> 'atividades_pendente_dono')::int, 0) + 1));
        continue;
      end if;
      v_tipo := case upper(coalesce(r.pl ->> 'type', '')) when 'CALL' then 'ligacao' when 'MAIL' then 'email'
                  when 'WHATSAPP' then 'whatsapp' when 'MEETING' then 'reuniao' when 'SCHEDULE' then 'reuniao' else 'tarefa' end;
      perform set_config('crm.resumo', 'Atividade importada da Clint', true);
      insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, criado_em)
      values (r.neg, r.pes, r.dono, v_tipo,
              left(coalesce(nullif(btrim(r.pl ->> 'title'), ''), initcap(v_tipo)) ||
                   case when upper(coalesce(r.pl ->> 'type', '')) = 'INSTAGRAM' then ' (Instagram)' else '' end, 200),
              coalesce(crm._clint_ts(r.pl ->> 'due_at'), now()), coalesce(crm._clint_ts(r.pl ->> 'created_at'), now()))
      returning id into v_ativ;
      perform set_config('crm.resumo', '', true);
      perform crm._clint_res('atividade', r.cid, 'ok', r.h, '{}', r.pes, r.neg, null, v_ativ);
      c := jsonb_set(c, '{atividades_criadas}', to_jsonb(coalesce((c ->> 'atividades_criadas')::int, 0) + 1));
    exception when others then
      perform crm._clint_res('atividade', r.cid, 'erro', r.h, jsonb_build_object('msg', left(sqlerrm, 200), 'estado', sqlstate));
      c := jsonb_set(c, '{atividades_erro}', to_jsonb(coalesce((c ->> 'atividades_erro')::int, 0) + 1));
    end;
  end loop;

  perform set_config('crm.canal', '', true);
  perform set_config('crm.resumo', '', true);
  return c;
end
$$;

-- Relatório (só leitura, sem dado pessoal): staging × resultado × mapas × alterados depois da carga.
create function crm.clint_relatorio() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'staging', (select coalesce(jsonb_object_agg(t, n), '{}') from (select o.tipo t, count(*) n from arquivo.clint_objeto o group by 1) x),
    'resultado', (select coalesce(jsonb_object_agg(t, s), '{}') from (
                    select x.tipo t, jsonb_object_agg(x.status, x.n) s
                      from (select r.tipo, r.status, count(*) n from arquivo.clint_resultado r group by 1, 2) x group by 1) y),
    'contatos_como', (select coalesce(jsonb_object_agg(k, n), '{}') from (
                        select case when r.detalhe ->> 'revisao' is not null then 'em_revisao'
                                    when (r.detalhe ->> 'nova')::boolean then 'criados'
                                    else 'casados_' || coalesce(r.detalhe ->> 'como', '?') end k, count(*) n
                          from arquivo.clint_resultado r where r.tipo = 'contato' and r.status = 'ok' group by 1) x),
    'negocios_por_status', (select coalesce(jsonb_object_agg(s, n), '{}') from (
                              select n.status s, count(*) n from arquivo.clint_resultado r join crm.negocio n on n.id = r.negocio_id
                               where r.tipo = 'negocio' and r.status = 'ok' group by 1) x),
    'pendentes', jsonb_build_object(
      'contatos', (select count(*) from arquivo.clint_objeto o left join arquivo.clint_resultado r on r.tipo = 'contato' and r.clint_id = o.clint_id
                    where o.tipo = 'contato' and (r.status is null or not crm._clint_final(r.status))),
      'negocios', (select count(*) from arquivo.clint_objeto o left join arquivo.clint_resultado r on r.tipo = 'negocio' and r.clint_id = o.clint_id
                    where o.tipo = 'negocio' and (r.status is null or not crm._clint_final(r.status))),
      'atividades', (select count(*) from arquivo.clint_objeto o left join arquivo.clint_resultado r on r.tipo = 'atividade' and r.clint_id = o.clint_id
                      where o.tipo = 'atividade' and (r.status is null or not crm._clint_final(r.status))),
      'historico', (select count(*) from arquivo.clint_objeto o left join arquivo.clint_resultado r on r.tipo = 'historico' and r.clint_id = o.clint_id
                     where o.tipo = 'historico' and r.clint_id is null)),
    'mapas', jsonb_build_object(
      'funis_a_confirmar', (select count(*) from arquivo.clint_mapa_funil where importar and not confirmado),
      'etapas_a_confirmar', (select count(*) from arquivo.clint_mapa_etapa e join arquivo.clint_mapa_funil f using (clint_origem_id)
                              where f.importar and not e.confirmado),
      'usuarios_sem_perfil', (select count(*) from arquivo.clint_mapa_usuario where perfil_id is null),
      'usuarios_sem_vendedor', (select count(*) from arquivo.clint_mapa_usuario mu
                                 where not exists (select 1 from crm.vendedor v where v.perfil_id = mu.perfil_id and v.ativo)),
      'motivos_a_confirmar', (select count(*) from arquivo.clint_mapa_motivo where not confirmado),
      'campos_a_confirmar', (select count(*) from arquivo.clint_mapa_campo where not confirmado)),
    'alterados_depois_da_carga', (select count(*) from arquivo.clint_objeto o join arquivo.clint_resultado r
                                     on r.tipo = o.tipo and r.clint_id = o.clint_id
                                  where crm._clint_final(r.status) and r.hash_processado is distinct from o.hash),
    'nao_vistos_no_ultimo_lote', (select count(*) from arquivo.clint_objeto o
                                   where o.tipo in ('contato', 'negocio')
                                     and o.lote <> (select l.lote from arquivo.clint_lote l where l.situacao = 'completo'
                                                     order by l.terminado_em desc limit 1)));
$$;

-- Entrada: p_ensaio = true (padrão) faz tudo e DESFAZ (exceção capturada); devolve o relatório da chamada + fotografia.
create function crm.clint_carregar(p_lote text, p_ensaio boolean default true, p_limite int default 300,
                                   p_opcoes jsonb default '{}') returns jsonb
language plpgsql set search_path = '' as $$
declare v_c jsonb := '{}'; v_foto jsonb; v_ini timestamptz := clock_timestamp(); v_lote record;
begin
  select * into v_lote from arquivo.clint_lote l where l.lote = p_lote;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Lote inexistente.'); end if;
  if p_opcoes is null or jsonb_typeof(p_opcoes) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Opções inválidas.'); end if;
  if not coalesce(p_ensaio, true) then
    if not coalesce((select c.clint_import_ligado from crm.config c), false) then
      return jsonb_build_object('ok', false, 'msg', 'Importação da Clint desligada (crm.config.clint_import_ligado).');
    end if;
    if v_lote.situacao <> 'completo' then
      return jsonb_build_object('ok', false, 'msg', 'Carga real só de lote completo (extração terminou sem falha).');
    end if;
  end if;
  begin
    v_c := crm._clint_carregar(p_limite, p_opcoes);
    v_foto := crm.clint_relatorio();
    if coalesce(p_ensaio, true) then raise exception 'clint_ensaio'; end if;
  exception when raise_exception then
    if sqlerrm <> 'clint_ensaio' then raise; end if;   -- ensaio: tudo acima foi desfeito; v_c/v_foto ficam
  end;
  if not coalesce(p_ensaio, true) then
    insert into arquivo.clint_carga (lote, relatorio)
    values (p_lote, jsonb_build_object('chamada', v_c, 'foto', v_foto, 'limite', p_limite, 'opcoes', p_opcoes));
  end if;
  return jsonb_build_object('ok', true, 'ensaio', coalesce(p_ensaio, true), 'lote', p_lote,
                            'ms', round(extract(epoch from clock_timestamp() - v_ini) * 1000),
                            'chamada', v_c, 'foto', v_foto);
end
$$;

-- ─── 7. Grants e conferência ─────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'crm'::regnamespace and (p.proname like '\_clint\_%' or p.proname like 'clint\_%'))
               or p.oid in ('public.crm_clint_staging_lote(text,text,jsonb)'::regprocedure,
                            'public.crm_clint_staging_gravar(text,text,jsonb)'::regprocedure) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  grant execute on function public.crm_clint_staging_lote(text,text,jsonb), public.crm_clint_staging_gravar(text,text,jsonb)
    to service_role;
end
$grants$;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where ((p.pronamespace = 'crm'::regnamespace and (p.proname like '\_clint\_%' or p.proname like 'clint\_%'))
          or p.proname like 'crm\_clint\_%')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_aberto is not null then raise exception '20261006d: executável por anon/authenticated: %', v_aberto; end if;
  if exists (select 1 from information_schema.role_table_grants
              where table_schema = 'arquivo' and table_name like 'clint\_%'
                and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')) then
    raise exception '20261006d: arquivo.clint_* com grant indevido';
  end if;
  if not has_function_privilege('service_role', 'public.crm_clint_staging_gravar(text,text,jsonb)', 'execute')
     or has_function_privilege('service_role', 'crm.clint_carregar(text,boolean,integer,jsonb)', 'execute') then
    raise exception '20261006d: grants fora do esperado';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.tg_negocio_notifica()'::regprocedure) = '86f28a83cde4d50c6d1031a8ce878967' then
    raise exception '20261006d: crm.tg_negocio_notifica não foi recriada';
  end if;
end
$confere$;

-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- Antes de qualquer carga real: drop das peças (staging vazio).
-- begin;
-- set local lock_timeout = '3s';
-- update crm.config set clint_import_ligado = false;
-- drop function public.crm_clint_staging_lote(text,text,jsonb), public.crm_clint_staging_gravar(text,text,jsonb),
--   crm.clint_carregar(text,boolean,integer,jsonb), crm._clint_carregar(integer,jsonb), crm.clint_relatorio(),
--   crm.clint_preparar_mapas(), crm._clint_res(text,text,text,text,jsonb,uuid,uuid,uuid,uuid), crm._clint_final(text),
--   crm._clint_ts(text), crm._clint_txt(text), crm._clint_linha_sugerida(text), crm._clint_papel_sugerido(text,integer,integer),
--   crm._clint_motivo_sugerido(text), crm._clint_destino_sugerido(text,text), crm._clint_valor_campo(text,text);
-- -- crm.tg_negocio_notifica: recriar com o corpo da F2 (20261005t, seção 2) — só tirar a linha "20261006d".
-- drop table arquivo.clint_carga, arquivo.clint_mapa_campo, arquivo.clint_mapa_motivo, arquivo.clint_mapa_usuario,
--   arquivo.clint_mapa_etapa, arquivo.clint_mapa_funil, arquivo.clint_resultado, arquivo.clint_objeto, arquivo.clint_lote;
-- commit;
-- Depois de carga real: NÃO apagar. Desligar (clint_import_ligado=false) e ARQUIVAR o que veio da Clint:
--   negócios abertos importados → crm_marcar_perdido pela tela/RPC, ou arquivar os funis "Clint · …" (crm_arquivar_funil);
--   a lista exata está em arquivo.clint_resultado (negocio_id, nota_id, atividade_id) e em crm.log (canal 'clint_import').

-- ═══ PROVAS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Referências reais (só ids/e-mails em temp; nada disso sai na saída): 1 vendedor ativo, 1 e-mail de comprador,
-- 1 transação Hotmart aprovada (academy) sem outra aprovada do mesmo e-mail na janela.
create temp table _z_ref on commit drop as
select v.perfil_id vend, lower(btrim(p.email)) vend_email,
       null::text comp_email, null::text tx, null::text tx_email, null::text tx_produto, null::timestamptz tx_em
  from crm.vendedor v join public.perfis p on p.id = v.perfil_id
 where v.ativo and p.email is not null order by v.criado_em, v.perfil_id limit 1;   -- 1 linha só (empate de criado_em)
update _z_ref set comp_email = (select lower(btrim(c.email::text)) from public.compradores c
                                 where c.email is not null and lower(btrim(c.email::text)) like '%@%.%'
                                   and not exists (select 1 from public.thb_alunos a where lower(btrim(a.email)) = lower(btrim(c.email::text)))
                                 order by c.id limit 1);
update _z_ref z set tx = t.transacao, tx_email = t.e, tx_produto = t.produto_id, tx_em = t.em
  from (select h.transacao, lower(btrim(h.comprador_email)) e, h.produto_id, coalesce(h.aprovado_em, h.pedido_em) em
          from (select * from fin.hotmart_transacoes where conta = 'academy') h
         where h.status in ('APPROVED', 'COMPLETE') and coalesce(h.recorrencia, 1) = 1 and h.comprador_email is not null
           and h.aprovado_em > now() - interval '120 days'
           and lower(btrim(h.comprador_email)) <> (select comp_email from _z_ref)
           and (select count(*) from (select * from fin.hotmart_transacoes where conta = 'academy'
                                       union all select * from fin.hotmart_transacoes where conta = 'escritorio') h2
                 where lower(btrim(h2.comprador_email)) = lower(btrim(h.comprador_email))
                   and h2.status in ('APPROVED', 'COMPLETE')
                   and coalesce(h2.aprovado_em, h2.pedido_em) between h.aprovado_em - interval '40 days' and h.aprovado_em + interval '10 days') = 1
         order by h.aprovado_em desc limit 1) t;
select pg_temp.ok('0.referencias', (select vend is not null and vend_email is not null and comp_email is not null and tx is not null from _z_ref),
                  'vendedor ativo, comprador e transação aprovada escolhidos por SELECT');
-- produto da transação vinculado à linha ht (só nesta transação) para a regra de ganho achar a linha
insert into crm.produto_comercial (produto_id, no_comercial, nome_comercial, linha, escada)
select tx_produto, true, 'Ensaio F6', 'ht', 'B' from _z_ref
on conflict (produto_id) do update set no_comercial = true, nome_comercial = 'Ensaio F6', linha = 'ht', escada = 'B';

-- 1. grants
select pg_temp.ok('1.anon', not exists (select 1 from pg_proc p where ((p.pronamespace = 'crm'::regnamespace and p.proname like '%clint%') or p.proname like 'crm\_clint\_%')
                                         and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
                  'nenhuma função da F6 executável por anon/authenticated');
select pg_temp.ok('1.service_role', has_function_privilege('service_role', 'public.crm_clint_staging_gravar(text,text,jsonb)', 'execute')
                                and not has_function_privilege('service_role', 'crm.clint_carregar(text,boolean,integer,jsonb)', 'execute')
                                and not has_table_privilege('service_role', 'arquivo.clint_objeto', 'select'),
                  'service_role só grava staging pelas 2 RPCs; não lê arquivo nem roda a carga');
select pg_temp.ok('1.notifica', (select position('clint_import' in p.prosrc) > 0 from pg_proc p where p.oid = 'crm.tg_negocio_notifica()'::regprocedure),
                  'tg_negocio_notifica recriada com a linha da carga');

-- 2. staging pelo script (como service_role: sem acesso às temp; valores passam por GUC local)
select set_config('z.vend_email', (select vend_email from _z_ref), true), set_config('z.comp_email', (select comp_email from _z_ref), true),
       set_config('z.tx_email', (select tx_email from _z_ref), true), set_config('z.tx_em', (select tx_em from _z_ref)::text, true);
set local role service_role;
select set_config('z.lote', public.crm_clint_staging_lote('clint-20261006T000000', 'abrir')::text, true);
select set_config('z.lote_inv', public.crm_clint_staging_lote('x', 'abrir')::text, true);
select public.crm_clint_staging_gravar('clint-20261006T000000', 'grupo', '[{"clint_id":"g1","payload":{"id":"g1","name":"Holding Total"}}]');
select public.crm_clint_staging_gravar('clint-20261006T000000', 'origem', '[
 {"clint_id":"o1","payload":{"id":"o1","name":"HT Venda","group":{"id":"g1","name":"Holding Total"},"stages":[
   {"id":"s1","label":"Novo lead","order":1,"type":"BASE"},{"id":"s2","label":"Qualificação","order":2,"type":"BASE"},
   {"id":"s3","label":"Negociação","order":3,"type":"BASE"},{"id":"s4","label":"Aguardando pagamento","order":4,"type":"BASE"}]}},
 {"clint_id":"o2","payload":{"id":"o2","name":"Origem sem mapa","group":{"id":"g1","name":"Holding Total"},"stages":[{"id":"s9","label":"Base","order":1}]}}]');
select public.crm_clint_staging_gravar('clint-20261006T000000', 'usuario',
  jsonb_build_array(jsonb_build_object('clint_id','u1','payload',jsonb_build_object('id','u1','email',upper(current_setting('z.vend_email')),'first_name','Ensaio','last_name','Vendedor')),
                    jsonb_build_object('clint_id','u2','payload',jsonb_build_object('id','u2','email','ninguem.f6@exemplo.invalid','first_name','Fora'))));
select public.crm_clint_staging_gravar('clint-20261006T000000', 'motivo', '[{"clint_id":"m1","payload":{"id":"m1","name":"Sem interesse"}},{"clint_id":"m2","payload":{"id":"m2","name":"Achou caro"}}]');
select public.crm_clint_staging_gravar('clint-20261006T000000', 'campo', '[
 {"clint_id":"DEAL:profissao","payload":{"entidade":"DEAL","chave":"profissao","label":"Profissão","type":"TEXT"}},
 {"clint_id":"DEAL:obs","payload":{"entidade":"DEAL","chave":"obs","label":"Observação","type":"TEXT"}},
 {"clint_id":"CONTACT:utm_source","payload":{"entidade":"CONTACT","chave":"utm_source","label":"utm_source","type":"TEXT"}}]');
select public.crm_clint_staging_gravar('clint-20261006T000000', 'contato', jsonb_build_array(
  jsonb_build_object('clint_id','c1','payload',jsonb_build_object('id','c1','name','Ensaio F6 Um','email','ensaio.f6.c1@exemplo.invalid','fullPhone','+5511990000001','tags',jsonb_build_array(jsonb_build_object('id','t1','name','quente')),'fields',jsonb_build_object('utm_source','clint'))),
  jsonb_build_object('clint_id','c2','payload',jsonb_build_object('id','c2','name','Ensaio F6 Um','email','  ENSAIO.F6.C1@exemplo.invalid ')),
  jsonb_build_object('clint_id','c3','payload',jsonb_build_object('id','c3','name','Ensaio F6 Tres','email',current_setting('z.comp_email'))),
  jsonb_build_object('clint_id','c4','payload',jsonb_build_object('id','c4','name','Ensaio F6 Quatro','fullPhone','+5599990000404')),
  jsonb_build_object('clint_id','c5','payload',jsonb_build_object('id','c5','name','Ensaio F6 So Nome')),
  jsonb_build_object('clint_id','c6','payload',jsonb_build_object('id','c6','name','Ensaio F6 Seis','email',current_setting('z.tx_email'))),
  jsonb_build_object('clint_id','c7','payload',jsonb_build_object('id','c7','name','Ensaio F6 Sete','email','ensaio.f6.c7@exemplo.invalid'))));
select public.crm_clint_staging_gravar('clint-20261006T000000', 'negocio', jsonb_build_array(
  jsonb_build_object('clint_id','d1','payload',jsonb_build_object('id','d1','origin_id','o1','stage_id','s2','status','OPEN','created_at','2026-09-01T10:00:00+00:00','updated_stage_at','2026-09-02T10:00:00+00:00','user',jsonb_build_object('id','u1','full_name','Ensaio Vendedor'),'contact',jsonb_build_object('id','c1'),'fields',jsonb_build_object('profissao','Advogado','obs','texto livre'))),
  jsonb_build_object('clint_id','d2','payload',jsonb_build_object('id','d2','origin_id','o1','stage_id','s1','status','OPEN','created_at','2026-09-03T10:00:00+00:00','contact',jsonb_build_object('id','c2'))),
  jsonb_build_object('clint_id','d3','payload',jsonb_build_object('id','d3','origin_id','o1','stage_id','s3','status','LOST','lost_status_id','m1','lost_at','2026-09-05T10:00:00+00:00','created_at','2026-08-01T10:00:00+00:00','contact',jsonb_build_object('id','c7'))),
  jsonb_build_object('clint_id','d4','payload',jsonb_build_object('id','d4','origin_id','o1','stage_id','s3','status','LOST','lost_status_id','m2','lost_at','2026-09-05T10:00:00+00:00','created_at','2026-08-01T10:00:00+00:00','contact',jsonb_build_object('id','c3'))),
  jsonb_build_object('clint_id','d5','payload',jsonb_build_object('id','d5','origin_id','o1','stage_id','s4','status','WON','won_at',current_setting('z.tx_em'),'created_at','2026-06-01T10:00:00+00:00','contact',jsonb_build_object('id','c6'))),
  jsonb_build_object('clint_id','d6','payload',jsonb_build_object('id','d6','origin_id','o1','stage_id','s4','status','WON','won_at','2026-09-10T10:00:00+00:00','created_at','2026-08-01T10:00:00+00:00','contact',jsonb_build_object('id','c7'))),
  jsonb_build_object('clint_id','d7','payload',jsonb_build_object('id','d7','origin_id','o2','stage_id','s9','status','OPEN','created_at','2026-09-01T10:00:00+00:00','contact',jsonb_build_object('id','c4'))),
  jsonb_build_object('clint_id','d8','payload',jsonb_build_object('id','d8','origin_id','o1','stage_id','s1','status','OPEN','created_at','2026-09-01T11:00:00+00:00','user',jsonb_build_object('id','u2','full_name','Fora'),'contact',jsonb_build_object('id','c4'))),
  jsonb_build_object('clint_id','d9','payload',jsonb_build_object('id','d9','origin_id','o1','stage_id','s1','status','OPEN','created_at','2026-09-01T12:00:00+00:00','contact',jsonb_build_object('id','c5')))));
select public.crm_clint_staging_gravar('clint-20261006T000000', 'historico', '[
 {"clint_id":"d1:h1","pai_id":"d1","payload":{"id":"h1","category":"NOTE","date":"2026-09-01T12:00:00Z","user":{"id":"u1","name":"Ensaio"},"body":{"text":"Nota de ensaio"},"summary":null}},
 {"clint_id":"d1:h2","pai_id":"d1","payload":{"id":"h2","category":"STAGE_CHANGE","date":"2026-09-02T10:00:00Z","user":{"id":"u1","name":"Ensaio"},"body":{},"summary":"Mudou de etapa: Novo lead → Qualificação"}}]');
select public.crm_clint_staging_gravar('clint-20261006T000000', 'atividade', jsonb_build_array(
  jsonb_build_object('clint_id','a1','pai_id','d1','payload',jsonb_build_object('id','a1','title','Ligar de volta','type','CALL','completed',false,'due_at',(now() + interval '1 day')::text,'deal',jsonb_build_object('id','d1'))),
  jsonb_build_object('clint_id','a2','pai_id','d1','payload',jsonb_build_object('id','a2','title','Já feita','type','TASK','completed',true,'deal',jsonb_build_object('id','d1'))),
  jsonb_build_object('clint_id','a3','pai_id','d8','payload',jsonb_build_object('id','a3','title','Sem dono','type','WHATSAPP','completed',false,'deal',jsonb_build_object('id','d8')))));
-- reenvio idêntico = 0 novos, 0 alterados
select set_config('z.idem', public.crm_clint_staging_gravar('clint-20261006T000000', 'motivo',
                    '[{"clint_id":"m1","payload":{"id":"m1","name":"Sem interesse"}},{"clint_id":"m2","payload":{"id":"m2","name":"Achou caro"}}]')::text, true);
select set_config('z.alt', public.crm_clint_staging_gravar('clint-20261006T000000', 'tag', '[{"clint_id":"t9","payload":{"id":"t9","name":"x"}}]')::text, true);
select set_config('z.alt2', public.crm_clint_staging_gravar('clint-20261006T000000', 'tag', '[{"clint_id":"t9","payload":{"id":"t9","name":"y"}}]')::text, true);
reset role;
select pg_temp.ok('2.lote', (current_setting('z.lote')::jsonb ->> 'ok')::boolean, 'lote aberto pelo service_role');
select pg_temp.ok('2.lote_invalido', not (current_setting('z.lote_inv')::jsonb ->> 'ok')::boolean, 'lote fora do padrão recusado');
select pg_temp.ok('2.idempotente', current_setting('z.idem')::jsonb ->> 'novos' = '0' and current_setting('z.idem')::jsonb ->> 'alterados' = '0',
                  'regravar o mesmo payload não duplica nem marca alteração');
select pg_temp.ok('2.alterado', current_setting('z.alt')::jsonb ->> 'novos' = '1' and current_setting('z.alt2')::jsonb ->> 'alterados' = '1',
                  'novo e alterado contados: ' || current_setting('z.alt2'));
select pg_temp.ok('2.staging', (select count(*) from arquivo.clint_objeto) = 32, 'staging com ' || (select count(*) from arquivo.clint_objeto) || ' objetos (esperado 32)');

-- 3. mapas sugeridos
select pg_temp.ok('3.preparar', (crm.clint_preparar_mapas() ->> 'ok')::boolean, 'mapas preparados');
select pg_temp.ok('3.linha', (select linha = 'ht' and not confirmado from arquivo.clint_mapa_funil where clint_origem_id = 'o1'), 'linha sugerida ht, não confirmada');
select pg_temp.ok('3.papeis', (select string_agg(papel, ',' order by ordem) from arquivo.clint_mapa_etapa where clint_origem_id = 'o1')
                               = 'primeiro_contato,qualificar,negociar,aguardar_pagamento',
                  'papéis sugeridos: ' || (select string_agg(coalesce(papel, '?'), ',' order by ordem) from arquivo.clint_mapa_etapa where clint_origem_id = 'o1'));
select pg_temp.ok('3.usuario', (select perfil_id = (select vend from _z_ref) from arquivo.clint_mapa_usuario where clint_usuario_id = 'u1')
                               and (select perfil_id is null from arquivo.clint_mapa_usuario where clint_usuario_id = 'u2'),
                  'usuário casa com perfil por e-mail (maiúscula ignorada); e-mail de fora fica sem perfil');
select pg_temp.ok('3.motivos', (select motivo_chave from arquivo.clint_mapa_motivo where clint_motivo_id = 'm1') = 'sem_interesse'
                               and (select motivo_chave from arquivo.clint_mapa_motivo where clint_motivo_id = 'm2') = 'sem_condicao_financeira'
                               and exists (select 1 from arquivo.clint_mapa_motivo where clint_motivo_id = 'sem_motivo'),
                  'motivos sugeridos + linha "sem motivo"');
select pg_temp.ok('3.campos', (select destino from arquivo.clint_mapa_campo where entidade = 'DEAL' and chave = 'profissao') = 'campo:perfil_profissional'
                              and (select destino from arquivo.clint_mapa_campo where entidade = 'DEAL' and chave = 'obs') = 'nota'
                              and (select destino from arquivo.clint_mapa_campo where entidade = 'CONTACT' and chave = 'utm_source') = 'utm_source',
                  'destinos de campo sugeridos');
-- gestor confirma (m2 fica SEM confirmar de propósito)
update arquivo.clint_mapa_funil set confirmado = true where clint_origem_id = 'o1';
update arquivo.clint_mapa_etapa set confirmado = true where clint_origem_id = 'o1';
update arquivo.clint_mapa_motivo set confirmado = true where clint_motivo_id = 'm1';
update arquivo.clint_mapa_campo set confirmado = true;

-- 4. ensaio: faz tudo e desfaz
create temp table _z_r (k text primary key, v jsonb) on commit drop;
insert into _z_r select 'ensaio', crm.clint_carregar('clint-20261006T000000', true, 300, '{}');
select pg_temp.ok('4.ensaio_relatorio', (select (v ->> 'ensaio')::boolean and (v #>> '{chamada,negocios_abertos}')::int = 2
                                                 and (v #>> '{chamada,funis_criados}')::int = 1 from _z_r where k = 'ensaio'),
                  'ensaio devolve relatório: ' || (select (v -> 'chamada')::text from _z_r where k = 'ensaio'));
select pg_temp.ok('4.ensaio_nada', (select count(*) from crm.negocio) = 0 and (select count(*) from crm.funil) = 0
                                   and (select count(*) from arquivo.clint_resultado) = 0 and (select count(*) from crm.nota) = 0
                                   and (select count(*) from crm.pessoa_comercial) = 0
                                   and not exists (select 1 from pessoas.pessoas p where p.nome like 'Ensaio F6%')
                                   and (select funil_id is null from arquivo.clint_mapa_funil where clint_origem_id = 'o1'),
                  'depois do ensaio: nada gravado (negócio, funil, nota, pessoa, resultado, mapa)');

-- 5. modo real recusado sem kill-switch / com lote aberto
select pg_temp.ok('5.desligado', not (crm.clint_carregar('clint-20261006T000000', false) ->> 'ok')::boolean, 'real recusado: clint_import_ligado=false');
update crm.config set clint_import_ligado = true;
select pg_temp.ok('5.lote_aberto', not (crm.clint_carregar('clint-20261006T000000', false) ->> 'ok')::boolean, 'real recusado: lote não completo');
set local role service_role;
select public.crm_clint_staging_lote('clint-20261006T000000', 'completo', '{"negocio":{"api":9,"gravados":9}}');
reset role;

-- 6. carga real
insert into _z_r select 'real1', crm.clint_carregar('clint-20261006T000000', false, 300, '{}');
select pg_temp.ok('6.ok', (select (v ->> 'ok')::boolean and not (v ->> 'ensaio')::boolean from _z_r where k = 'real1'),
                  'real: ' || (select (v -> 'chamada')::text || ' em ' || (v ->> 'ms') || ' ms' from _z_r where k = 'real1'));
select pg_temp.ok('6.funil', (select count(*) from crm.funil f where f.nome = 'Clint · HT Venda') = 1
                             and (select string_agg(e.papel, ',' order by e.ordem) from crm.etapa_funil e join crm.funil f on f.id = e.funil_id where f.nome = 'Clint · HT Venda')
                                 = 'primeiro_contato,qualificar,negociar,aguardar_pagamento,fechado',
                  'funil "Clint · HT Venda" com 4 etapas mapeadas + Fechado');
create temp table _z_neg on commit drop as
select r.clint_id, r.status rs, r.negocio_id, r.pessoa_id, n.status, n.dono_id, n.campos, n.motivo_perda, n.transacao_ganho, n.etapa_id
  from arquivo.clint_resultado r left join crm.negocio n on n.id = r.negocio_id where r.tipo = 'negocio';
select pg_temp.ok('6.contatos_mesma', (select count(distinct pessoa_id) = 1 from arquivo.clint_resultado where tipo = 'contato' and clint_id in ('c1', 'c2')),
                  'c1 e c2 (mesmo e-mail com espaço/maiúscula) = 1 pessoa');
select pg_temp.ok('6.casado_email', (select detalhe ->> 'como' = 'email' and not (detalhe ->> 'nova')::boolean from arquivo.clint_resultado where tipo = 'contato' and clint_id = 'c3'),
                  'c3 casou por e-mail com o comprador existente (referência, sem cópia)');
select pg_temp.ok('6.sem_identificador', (select status from arquivo.clint_resultado where tipo = 'contato' and clint_id = 'c5') = 'sem_identificador'
                                          and (select rs from _z_neg where clint_id = 'd9') = 'ignorado',
                  'só nome: contato fica de fora e o negócio dele é ignorado');
select pg_temp.ok('6.aberto', (select status = 'aberto' and dono_id = (select vend from _z_ref) and campos ->> 'perfil_profissional' = 'advogado' from _z_neg where clint_id = 'd1'),
                  'd1 aberto, dono = vendedor pelo e-mail, campo Profissão → perfil_profissional=advogado');
select pg_temp.ok('6.nota_campos', exists (select 1 from crm.nota x join _z_neg z on z.negocio_id = x.negocio_id
                                            where z.clint_id = 'd1' and x.texto like '%Observação: texto livre%'),
                  'campo sem destino de dado vai para a nota de importação');
select pg_temp.ok('6.duplicado', (select rs = 'duplicado' and negocio_id = (select negocio_id from _z_neg where clint_id = 'd1') from _z_neg where clint_id = 'd2'),
                  '2º aberto da mesma pessoa no mesmo funil = duplicado (aponta para o existente)');
select pg_temp.ok('6.perdido', (select status = 'perdido' and motivo_perda = 'sem_interesse' from _z_neg where clint_id = 'd3'), 'd3 perdido com motivo mapeado');
select pg_temp.ok('6.pendente_motivo', (select rs from _z_neg where clint_id = 'd4') = 'pendente_motivo', 'motivo não confirmado: não cria, fica pendente');
select pg_temp.ok('6.ganho', (select status = 'ganho' and transacao_ganho = (select tx from _z_ref)
                                     and etapa_id = (select etapa_fechado_id from arquivo.clint_mapa_funil where clint_origem_id = 'o1') from _z_neg where clint_id = 'd5'),
                  'd5 ganho SÓ porque casou 1 transação aprovada real (e-mail + linha + janela), na etapa Fechado');
select pg_temp.ok('6.ganho_sem_tx', (select rs = 'ganho_sem_transacao' and negocio_id is null from _z_neg where clint_id = 'd6')
                                    and (select count(*) from pessoas.eventos e where e.tipo = 'crm' and e.detalhe ->> 'clint' = 'ganho_sem_transacao'
                                          and e.pessoa_id = (select pessoa_id from _z_neg where clint_id = 'd6')) = 1,
                  'd6 ganho sem pagamento: não vira negócio, vira 1 evento na jornada da pessoa');
select pg_temp.ok('6.pendente_mapa', (select rs from _z_neg where clint_id = 'd7') = 'pendente_mapa', 'origem não confirmada: pendente_mapa');
select pg_temp.ok('6.sem_dono', (select status = 'aberto' and dono_id is null from _z_neg where clint_id = 'd8'), 'usuário da Clint sem perfil: negócio sem dono');
select pg_temp.ok('6.tags_dono', (select 'quente' = any(pc.tags) and pc.dono_id = (select vend from _z_ref) from crm.pessoa_comercial pc
                                   where pc.pessoa_id = (select pessoa_id from _z_neg where clint_id = 'd1')),
                  'tag da Clint e dono no contato comercial');
select pg_temp.ok('6.historico', (select count(*) from crm.nota x join _z_neg z on z.negocio_id = x.negocio_id
                                   where z.clint_id = 'd1' and (x.texto = 'Nota de ensaio' or x.texto like 'Histórico na Clint%Novo lead → Qualificação%')) = 2,
                  'histórico: 1 nota da Clint + 1 nota "Histórico na Clint"');
select pg_temp.ok('6.atividades', (select status from arquivo.clint_resultado where tipo = 'atividade' and clint_id = 'a1') = 'ok'
                                  and (select a.dono_id = (select vend from _z_ref) and a.tipo = 'ligacao' from crm.atividade a
                                        join arquivo.clint_resultado r on r.atividade_id = a.id where r.clint_id = 'a1')
                                  and (select status from arquivo.clint_resultado where tipo = 'atividade' and clint_id = 'a2') = 'ignorado'
                                  and (select status from arquivo.clint_resultado where tipo = 'atividade' and clint_id = 'a3') = 'pendente_dono',
                  'atividade aberta → crm.atividade (dono do negócio); concluída fica no histórico; sem dono pendente');
select pg_temp.ok('6.sem_aviso', (select count(*) from crm.notificacao) = 0, 'carga não gerou notificação "lead novo"');
select pg_temp.ok('6.log', (select count(*) from crm.log where canal = 'clint_import' and autor_tipo = 'integracao') > 0
                           and not exists (select 1 from crm.log where canal = 'clint_import' and autor_tipo <> 'integracao'),
                  'log: ' || (select count(*) from crm.log where canal = 'clint_import') || ' linhas canal clint_import, todas integracao');
select pg_temp.ok('6.relatorio', (select (v #>> '{foto,pendentes,negocios}')::int = 3 from _z_r where k = 'real1'),
                  'foto: ' || (select (v -> 'foto' -> 'resultado')::text from _z_r where k = 'real1'));

-- 7. idempotência: reprocessar = 0 novos
create temp table _z_cont on commit drop as
select (select count(*) from crm.negocio) neg, (select count(*) from pessoas.pessoas) pes, (select count(*) from crm.nota) nota,
       (select count(*) from crm.atividade) atv, (select count(*) from pessoas.eventos) ev, (select count(*) from crm.funil) fun;
insert into _z_r select 'real2', crm.clint_carregar('clint-20261006T000000', false, 300, '{}');
select pg_temp.ok('7.reprocessar', (select neg = (select count(*) from crm.negocio) and pes = (select count(*) from pessoas.pessoas)
                                           and nota = (select count(*) from crm.nota) and atv = (select count(*) from crm.atividade)
                                           and ev = (select count(*) from pessoas.eventos) and fun = (select count(*) from crm.funil) from _z_cont),
                  '2ª carga: 0 novos. chamada=' || (select (v -> 'chamada')::text from _z_r where k = 'real2'));
-- gestor confirma o motivo pendente → só o d4 entra
update arquivo.clint_mapa_motivo set confirmado = true where clint_motivo_id = 'm2';
insert into _z_r select 'real3', crm.clint_carregar('clint-20261006T000000', false, 300, '{}');
select pg_temp.ok('7.pendente_resolvido', (select count(*) from crm.negocio) = (select neg from _z_cont) + 1
                                          and (select n.motivo_perda from crm.negocio n join arquivo.clint_resultado r on r.negocio_id = n.id
                                                where r.tipo = 'negocio' and r.clint_id = 'd4') = 'sem_condicao_financeira',
                  'motivo confirmado depois: só o d4 entra (1 novo)');
-- payload alterado na Clint depois da carga: contado, não aplicado
set local role service_role;
select public.crm_clint_staging_lote('clint-20261007T000000', 'abrir');
select public.crm_clint_staging_gravar('clint-20261007T000000', 'negocio', jsonb_build_array(
  jsonb_build_object('clint_id','d1','payload',jsonb_build_object('id','d1','origin_id','o1','stage_id','s3','status','OPEN','created_at','2026-09-01T10:00:00+00:00','user',jsonb_build_object('id','u1','full_name','Ensaio Vendedor'),'contact',jsonb_build_object('id','c1'),'fields',jsonb_build_object('profissao','Advogado','obs','texto livre')))));
reset role;
select pg_temp.ok('7.alterado', (crm.clint_relatorio() ->> 'alterados_depois_da_carga')::int = 1, 'mudança na Clint depois da carga aparece no relatório (não é aplicada)');

-- 8. regras da F2 continuam valendo fora da carga
do $$
begin
  begin
    insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, status, transacao_ganho, fechado_em)
    select z.pessoa_id, f.funil_id, f.etapa_fechado_id, 'ht', 'venda_ativa', 'ganho', 'HP-ENSAIO-F6', now()
      from _z_neg z, arquivo.clint_mapa_funil f where z.clint_id = 'd6' and f.clint_origem_id = 'o1';
    perform pg_temp.ok('8.ganho_barrado', false, 'ganho sem a função da Hotmart passou');
  exception when others then
    perform pg_temp.ok('8.ganho_barrado', sqlstate = '23514', 'ganho fora da Hotmart/carga casada recusado: ' || sqlerrm);
  end;
end $$;
select pg_temp.ok('8.flag_limpa', coalesce(current_setting('crm.ganho_hotmart', true), '') = '' and coalesce(current_setting('crm.canal', true), '') = '',
                  'carga não deixa crm.ganho_hotmart/crm.canal ligados na sessão');

select linha from _z_out order by n;
rollback;


-- ═══ PARTE C (chamada separada, depois do rollback): nada persistiu ═══════════════════════════════════════════════
-- select to_regclass('arquivo.clint_objeto') is null sem_staging,
--        not exists (select 1 from pg_proc where proname like '%clint%') sem_funcoes,
--        (select md5(prosrc) from pg_proc where oid = to_regprocedure('crm.tg_negocio_notifica()'))
--          = '86f28a83cde4d50c6d1031a8ce878967' notifica_intacta,
--        (select count(*) from crm.funil) funis, (select count(*) from crm.negocio) negocios,
--        (select count(*) from crm.nota) notas, (select count(*) from crm.atividade) atividades,
--        (select count(*) from crm.pessoa_comercial) pessoa_comercial, (select count(*) from crm.produto_comercial) produto_comercial,
--        (select count(*) from pessoas.pessoas) pessoas, (select count(*) from pessoas.eventos) eventos,
--        (select clint_import_ligado from crm.config) clint_ligado,
--        (select count(*) from crm.log where canal = 'clint_import') log_clint, (select count(*) from crm.notificacao) notif;
-- Resultado 06/10/2026: true, true, true, 0, 0, 0, 0, 0, 0, 0, 0, false, 0, 0.
