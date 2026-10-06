-- 20261006d: F6 do Comercial — migração da Clint para o CRM (staging em arquivo + carga staging → pessoas/crm)
--
-- STATUS: APLICADA em 06/10/2026, versão 20261006045730 (crm_f6_migracao_clint). md5 do statement gravado = arquivo
-- original sem a quebra final (cab569ec…). Ensaio final 44/44 OK em begin … rollback; nada persistiu. Nenhuma carga feita.
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
