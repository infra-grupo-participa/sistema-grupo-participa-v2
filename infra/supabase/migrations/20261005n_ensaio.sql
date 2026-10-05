-- 20261005n: ENSAIO (não aplica nada: cada bloco termina abortado; nada fica gravado)
--
-- COMO RODAR: 3 blocos INDEPENDENTES. Cada um vai de "-- ▶ BLOCO n" até "-- ◀ FIM DO BLOCO n" e é mandado INTEIRO
--   numa única chamada (SQL editor do Supabase, psql ou execute_sql), como postgres. Cada bloco: begin; corpo da
--   migration (cópia exata de 20261005n_mkt_mensageria.sql); preparo; testes; aborto.
--   O último comando de cada bloco é um RAISE de propósito: a mensagem de erro É O RELATÓRIO e o aborto garante que
--   nada persiste mesmo que o cliente ignore o "rollback;" seguinte.
--     esperado:  ERROR  ENSAIO 20261005n BLOCO n CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.  + linhas
--     qualquer outro erro (… FALHOU …, 23514, 42501 inesperado, timeout) = a migration não serve como está: NÃO aplicar.
--   Tempos: lock_timeout 3s, statement_timeout 20s por comando. Medido no local (PGlite): bloco 1 < 2s, 2 < 10s, 3 < 10s.
--   O admin dos caminhos felizes é achado por subselect (primeiro perfil com gp_is_admin() = true); nenhum uid escrito.
--   Projeto dos testes: o primeiro de mkt.projetos (por id). Nada é escrito em mkt.projetos.
--
-- GERADO: o corpo da migration é colado sem mudança em cada bloco. Se a migration mudar, gerar de novo.
--
-- BLOCO 1 (segurança e regras), linhas esperadas no relatório:
--   Ta  anon: 42501 nas 11 funções                         Tb  authenticated não-admin: 42501 nas 11 funções
--   Tf  sem USAGE no schema, sem privilégio nas 5 tabelas, select direto = 42501
--   Tc  tabela recusa tipo fora da API, API sem tipo, lidas>entregues, entregues+falhas>tamanho, sem copy, negativo,
--       número fora do E.164; retorno/custo sem default
--   Tc2 RPC: mensagens legíveis; 0 lançado → ["conferir_zero_leitura"], nulo → ["sem_custo","sem_retorno"]
--   Tc3 gravado: 0 continua 0 e nulo continua nulo
--   Td.erros (o JSON devolvido)   Td  boa+ruim com confirmar=true → nada entra; só a boa → entra convertida
--   Td3 duplicata no banco e no lote: prévia lista, confirmar recusa, p_aceitar_duplicadas grava
--   Te  histórico arquivar/alterar/inserir; DELETE recusado   Tg período   Th consumo_hoje = 40   Ti retorno   Tj ferramentas
--   Tk  origem_sistema/id_externo fora da tela e imutáveis   Tm guarda coalesce   Tn ferramenta desativada/número arquivado
--   To  anonimização LGPD   Tl  DELETE/TRUNCATE/UPDATE bloqueados (42501)
-- BLOCO 2 (volume): E1..E4 = linhas do explain (analyze, buffers) + "usa <índice>"; V1..V4 tempo e tamanho; V5 consumo.
-- BLOCO 3 (importação no teto): I1 prévia 2.000, I2 confirmar 2.000, I3 aviso de duplicata, I3b reimportar confirmado = recusado, I4 2.001 recusado, I5 contagens.

-- ▶ BLOCO 1 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005n_mkt_mensageria.sql) ═══
-- 20261005n: Marketing > Mensageria (etapa 2: o banco da área)
--
-- O QUE FAZ
--   Cria o schema mkt_mensageria: o LOG CENTRAL DE DISPAROS (todo envio de WhatsApp API, e-mail, SMS, ligação e grupo,
--   de qualquer ferramenta), o CONTROLE DE NÚMEROS (quem responde por cada número, para quê, quanto aguenta por dia) e o
--   cadastro de FERRAMENTAS. Decisões de 05/10/2026:
--     - Retorno e custo não lançados ficam NULOS, nunca 0. Sem default nessas colunas. 0 é "medido e deu zero".
--     - Consumo do dia de cada número vem do log (soma de tamanho_lista dos disparos de hoje). Ninguém digita.
--     - Nada se apaga: disparo errado é ARQUIVADO com motivo; triggers recusam DELETE/TRUNCATE (e UPDATE em historico e
--       importacoes). Toda mudança vai para o histórico. Única exceção: anonimização LGPD (mkt_msg_anonimizar_disparo).
--     - Planilha recusa possível duplicata (no log ou no próprio lote) salvo aceite explícito; id_externo só via API.
--     - Projeto = mkt.projetos (20261005m), pela sigla. cs.disparos e cs.canais_disparo são de OUTRO sistema: não toca.
--     - Quem vê: o mesmo de todo o Marketing, mkt.pode_ver('mkt_mensageria') (hoje admin/dev). Função NÃO alterada aqui.
--
--   Padrão da 20261005m: tabelas fechadas (RLS ligada, sem policy, revoke de public/anon/authenticated em schema,
--   tabelas e sequências), todo acesso por função public.mkt_msg_* SECURITY DEFINER, search_path '', guarda no corpo
--   com 42501. Cada função tem o revoke/grant logo abaixo do create (função nova nasce executável por PUBLIC).
--
-- O QUE CRIA
--   mkt_mensageria.ferramentas (13 de seed), numeros, importacoes, disparos, historico
--   mkt_mensageria.* internas: inteiro, inteiro_br, centavos_br, data_hora_br, instante, pendencias, disparo_validar,
--                              importar_linha, trg_carimbo, trg_numero_status, trg_historico, trg_bloqueio, trg_disparo_procedencia
--   public.mkt_msg_*  disparos_listar, disparo_salvar, disparo_arquivar, disparo_lancar_retorno, importar,
--                     numeros_listar, numero_salvar, ferramentas_listar, ferramenta_salvar, historico,
--                     anonimizar_disparo (LGPD, só admin)
--   Projetos: a tela usa public.mkt_projetos_listar() (20261005m). Não há mkt_msg_projetos_listar.
--
-- AS 5 PERGUNTAS
--   escala: estimativa de dezenas a centenas de disparos/dia. listar exige período (máx. 366 dias) e devolve no máximo
--     500 linhas; os totais varrem só o período, pelo índice. numeros_listar: um lookup por número no índice
--     (numero_id, enviado_em), só o dia de hoje. importar: no máximo 2.000 linhas, validação em uma query.
--   índice: disparos (enviado_em desc), (projeto_id, enviado_em desc), (numero_id, enviado_em); historico
--     (tabela, registro_id, em desc). Prova: 20261005n_ensaio.sql bloco 2 (explain analyze com 10.000 disparos).
--   frequência: a tela lê ao abrir e ao trocar filtro; escrita manual (pessoa) ou importação de planilha.
--   repetição: uma chamada por tela/filtro; totais e linhas na mesma query (CTE materializada, uma varredura).
--   reversão: bloco REVERSÃO no fim (o schema é novo e isolado; drop dele não afeta a 20261005m).
--
-- ENSAIO: 20261005n_ensaio.sql (3 blocos, cada um begin … aborto). Contrato e medições: 20261005n.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regnamespace('mkt_mensageria') is not null then
    raise exception '20261005n: schema mkt_mensageria já existe (migration já aplicada?)';
  end if;
  if to_regclass('mkt.projetos') is null or to_regprocedure('mkt.pode_ver(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null then
    raise exception '20261005n: base compartilhada ausente (mkt.projetos, mkt.pode_ver, mkt.sem_acento): aplicar 20261005m antes';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception '20261005n: auth.uid() ausente';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') then
    raise exception '20261005n: já existem funções public.mkt_msg_*';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'perfis' and column_name in ('id', 'nome')) <> 2 then
    raise exception '20261005n: public.perfis (id, nome) ausente';
  end if;
end
$guarda$;

-- ─── 1. Schema ───────────────────────────────────────────────────────────────────────────────────────────────────────
create schema mkt_mensageria;
revoke all on schema mkt_mensageria from public, anon, authenticated;
comment on schema mkt_mensageria is
  'Marketing > Mensageria: log central de disparos, controle de números e ferramentas. Retorno/custo nulo = não '
  'lançado (nunca 0). Nada se apaga (arquivar). Fechado: acesso só pelas funções public.mkt_msg_*. 20261005n.';

-- ─── 2. Funções auxiliares (internas: revoke de todos logo após cada create) ─────────────────────────────────────────
-- Inteiro ≥ 0 vindo da tela/JSON ("1234"). Vazio = nulo. Fora do formato (negativo, decimal, texto) = -1.
create function mkt_mensageria.inteiro(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro(text) from public, anon, authenticated;

-- Inteiro ≥ 0 vindo de planilha brasileira ("1234" ou "1.234"). Vazio = nulo. Fora do formato = -1.
create function mkt_mensageria.inteiro_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              when btrim(p) ~ '^[0-9]{1,3}(\.[0-9]{3}){1,2}$' then replace(btrim(p), '.', '')::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro_br(text) from public, anon, authenticated;

-- Reais de planilha ("1.234,56", "R$ 12,5", "990") → centavos. Vazio = nulo. Fora do formato = -1. Teto R$ 999.999,99.
create function mkt_mensageria.centavos_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when v = '' then null
              when v ~ '^([0-9]{1,3}(\.[0-9]{3})?|[0-9]{1,6})(,[0-9]{1,2})?$' then
                replace(split_part(v, ',', 1), '.', '')::bigint * 100
                + coalesce(rpad(nullif(split_part(v, ',', 2), ''), 2, '0')::bigint, 0)
              else -1 end
    from (select regexp_replace(btrim(coalesce(p, '')), '^R\$\s*', '') as v) t;
$$;
revoke all on function mkt_mensageria.centavos_br(text) from public, anon, authenticated;

-- "dd/mm/aaaa" + "hh:mm" no horário de São Paulo. Nulo se faltar ou não existir (31/02, 25:00).
create function mkt_mensageria.data_hora_br(p_data text, p_hora text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v_d text[] := regexp_match(btrim(coalesce(p_data, '')), '^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})$');
  v_h text[] := regexp_match(btrim(coalesce(p_hora, '')), '^([0-9]{1,2}):([0-9]{2})$');
begin
  if v_d is null or v_h is null then return null; end if;
  return make_timestamptz(v_d[3]::int, v_d[2]::int, v_d[1]::int, v_h[1]::int, v_h[2]::int, 0, 'America/Sao_Paulo');
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.data_hora_br(text, text) from public, anon, authenticated;

-- Instante vindo da tela: "2026-10-05T14:30" (sem fuso = São Paulo) ou ISO com fuso ("…Z", "…-03:00"). Nulo se inválido.
create function mkt_mensageria.instante(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v text := btrim(coalesce(p, ''));
begin
  if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?$' then
    return null;
  end if;
  if v ~ '(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then return v::timestamptz; end if;
  return v::timestamp at time zone 'America/Sao_Paulo';
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.instante(text) from public, anon, authenticated;

-- Pendências de um disparo (a tela mostra o selo; os totais contam). Mesma regra em todo lugar.
--   sem_custo: custo não lançado · sem_retorno: entregues ou lidas não lançadas · conferir_zero_leitura: 0 lidas com custo
create function mkt_mensageria.pendencias(p_entregues integer, p_lidas integer, p_custo integer) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null then 'sem_custo' end,
    case when p_entregues is null or p_lidas is null then 'sem_retorno' end,
    case when p_lidas = 0 and p_custo > 0 then 'conferir_zero_leitura' end], null);
$$;
revoke all on function mkt_mensageria.pendencias(integer, integer, integer) from public, anon, authenticated;

-- ─── 3. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt_mensageria.ferramentas (
  id                     bigint generated always as identity primary key,
  nome                   text not null check (nome = btrim(nome) and length(nome) between 1 and 60),
  api                    text not null check (api in ('sim', 'futura', 'nao')),
  custo_mensal_centavos  integer check (custo_mensal_centavos is null or custo_mensal_centavos >= 0),   -- nulo = não lançado
  responsavel            text check (responsavel is null or length(btrim(responsavel)) between 1 and 80),
  ativa                  boolean not null default true,
  obs                    text check (obs is null or length(obs) <= 1000),
  criado_em              timestamptz not null default now(),
  criado_por             uuid references public.perfis(id) on delete set null,
  atualizado_em          timestamptz not null default now(),
  atualizado_por         uuid references public.perfis(id) on delete set null
);
-- Único sem diferenciar maiúscula: a planilha acha a ferramenta pelo nome, sem diferenciar maiúscula.
create unique index ferramentas_nome_unico on mkt_mensageria.ferramentas (lower(nome));
comment on table mkt_mensageria.ferramentas is 'Ferramentas de disparo e apoio. api: sim (integra), futura (vai integrar), nao (registro manual). Custo mensal nulo = não lançado.';

create table mkt_mensageria.numeros (
  id              bigint generated always as identity primary key,
  numero          text not null unique check (numero ~ '^\+[1-9][0-9]{7,14}$'),   -- E.164
  projeto_id      bigint references mkt.projetos(id) on delete restrict,
  frente          text check (frente is null or length(btrim(frente)) between 1 and 60),
  responsavel     text not null check (length(btrim(responsavel)) between 1 and 80),
  finalidade      text not null check (finalidade in ('mensageria', 'comercial', 'financeiro', 'suporte')),
  ferramenta_id   bigint references mkt_mensageria.ferramentas(id) on delete restrict,
  capacidade_dia  smallint check (capacidade_dia is null or capacidade_dia between 1 and 1000),   -- nulo = não definida
  status          text not null check (status in ('ativo', 'aquecendo', 'restrito', 'disponivel')),
  status_desde    timestamptz not null default now(),     -- trigger carimba quando o status muda
  arquivado_em    timestamptz,
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null
);
comment on table mkt_mensageria.numeros is 'Números de WhatsApp/SMS. consumo do dia NÃO é coluna: vem do log (mkt_msg_numeros_listar).';

create table mkt_mensageria.importacoes (
  id          bigint generated always as identity primary key,
  arquivo     text check (arquivo is null or length(arquivo) <= 255),
  linhas      integer not null check (linhas between 1 and 2000),
  criado_por  uuid references public.perfis(id) on delete set null,
  criado_em   timestamptz not null default now()
);
comment on table mkt_mensageria.importacoes is 'Cada importação de planilha confirmada (tudo ou nada). disparos.importacao_id aponta para cá.';

create table mkt_mensageria.disparos (
  id                bigint generated always as identity primary key,
  enviado_em        timestamptz not null,
  projeto_id        bigint not null references mkt.projetos(id) on delete restrict,
  canal             text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  ferramenta_id     bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  numero_id         bigint references mkt_mensageria.numeros(id) on delete restrict,
  tipo              text check (tipo is null or tipo in ('utility', 'marketing')),
  copy_texto        text check (copy_texto is null or length(copy_texto) <= 4000),
  copy_link         text check (copy_link is null or length(copy_link) <= 2000),
  publico_lista     text not null check (length(btrim(publico_lista)) between 1 and 200),
  publico_origem    text check (publico_origem is null or length(publico_origem) <= 200),
  tamanho_lista     integer not null check (tamanho_lista >= 0),
  -- Retorno e custo: SEM DEFAULT. Nulo = não lançado; 0 = lançado e deu zero.
  entregues         integer check (entregues is null or entregues >= 0),
  lidas             integer check (lidas is null or lidas >= 0),
  cliques           integer check (cliques is null or cliques >= 0),
  falhas            integer check (falhas is null or falhas >= 0),
  custo_centavos    integer check (custo_centavos is null or custo_centavos >= 0),
  disparado_por     text not null check (length(btrim(disparado_por)) between 1 and 80),
  retorno_em        timestamptz,
  origem            text not null default 'manual' check (origem in ('manual', 'planilha', 'api')),
  origem_sistema    text check (origem_sistema is null or length(btrim(origem_sistema)) between 1 and 60),
  id_externo        text check (id_externo is null or length(btrim(id_externo)) between 1 and 200),
  importacao_id     bigint references mkt_mensageria.importacoes(id) on delete restrict,
  arquivado_em      timestamptz,
  arquivado_motivo  text check (arquivado_motivo is null or length(btrim(arquivado_motivo)) between 3 and 500),
  criado_em         timestamptz not null default now(),
  criado_por        uuid references public.perfis(id) on delete set null,
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid references public.perfis(id) on delete set null,
  constraint disparos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  constraint disparos_copy_obrigatoria check (nullif(btrim(copy_texto), '') is not null or nullif(btrim(copy_link), '') is not null),
  constraint disparos_entregues_falhas check (coalesce(entregues, 0)::bigint + coalesce(falhas, 0) <= tamanho_lista),
  constraint disparos_lidas_entregues check (lidas is null or entregues is null or lidas <= entregues),
  constraint disparos_cliques_entregues check (cliques is null or entregues is null or cliques <= entregues),
  constraint disparos_externo_com_sistema check (id_externo is null or origem_sistema is not null),
  -- Chave externa só para integração (origem 'api'). Tela (manual) e planilha não gravam: não colidem com a da API.
  constraint disparos_externo_so_api check (origem = 'api' or (origem_sistema is null and id_externo is null)),
  constraint disparos_importacao_planilha check (importacao_id is null or origem = 'planilha'),
  constraint disparos_arquivo_com_motivo check ((arquivado_em is null) = (arquivado_motivo is null))
);
create unique index disparos_externo_unico on mkt_mensageria.disparos (origem_sistema, id_externo) where id_externo is not null;
create index disparos_enviado_idx on mkt_mensageria.disparos (enviado_em desc);
create index disparos_projeto_enviado_idx on mkt_mensageria.disparos (projeto_id, enviado_em desc);
create index disparos_numero_enviado_idx on mkt_mensageria.disparos (numero_id, enviado_em);
comment on table mkt_mensageria.disparos is 'Log central de disparos (todo canal, toda ferramenta). Retorno/custo nulo = não lançado. Arquivar, nunca apagar.';
comment on column mkt_mensageria.disparos.tipo is 'Categoria da mensagem na API oficial do WhatsApp (utility, marketing). Só existe em canal whatsapp_api.';
comment on column mkt_mensageria.disparos.retorno_em is 'Quando o retorno (entregues, lidas, cliques, falhas, custo) foi lançado pela última vez.';
comment on column mkt_mensageria.disparos.id_externo is 'Id no sistema de origem. Só origem api (integração futura); imutável depois de gravado. Único por origem_sistema: reenvio não duplica.';

create table mkt_mensageria.historico (
  id           bigint generated always as identity primary key,
  tabela       text not null check (tabela in ('disparos', 'numeros', 'ferramentas')),
  registro_id  text not null,
  acao         text not null check (acao in ('inserir', 'alterar', 'arquivar', 'anonimizar')),
  antes        jsonb,
  depois       jsonb,
  por          uuid,                                   -- auth.uid(); sem FK: o histórico sobrevive ao perfil
  em           timestamptz not null default now()
);
create index historico_registro_idx on mkt_mensageria.historico (tabela, registro_id, em desc);
comment on table mkt_mensageria.historico is 'Toda inserção/alteração/arquivamento em disparos, numeros e ferramentas (trigger). Linha inteira antes/depois.';

alter table mkt_mensageria.ferramentas enable row level security;
alter table mkt_mensageria.numeros enable row level security;
alter table mkt_mensageria.importacoes enable row level security;
alter table mkt_mensageria.disparos enable row level security;
alter table mkt_mensageria.historico enable row level security;
revoke all on mkt_mensageria.ferramentas, mkt_mensageria.numeros, mkt_mensageria.importacoes, mkt_mensageria.disparos,
              mkt_mensageria.historico from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Triggers: carimbo, status_desde, histórico, sem DELETE ───────────────────────────────────────────────────────
create function mkt_mensageria.trg_carimbo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := coalesce(new.criado_por, auth.uid());
    new.atualizado_em := new.criado_em;
    new.atualizado_por := new.criado_por;
  else
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
    new.atualizado_em := now();
    new.atualizado_por := auth.uid();
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_carimbo() from public, anon, authenticated;

create function mkt_mensageria.trg_numero_status() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.status_desde := now();
  elsif new.status is distinct from old.status then
    new.status_desde := now();
  else
    new.status_desde := old.status_desde;
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_numero_status() from public, anon, authenticated;

-- Grava a linha inteira antes/depois. UPDATE que só muda o carimbo não gera linha. arquivado_em nulo→preenchido = arquivar.
-- Durante a anonimização (flag local à transação, ligada só por mkt_msg_anonimizar_disparo) não grava: a própria função
-- registra a linha 'anonimizar', sem o dado pessoal no "antes".
create function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, auth.uid());
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Bloqueio (42501): DELETE (linha) e TRUNCATE (comando) nas 5 tabelas; UPDATE em historico e importacoes.
-- Única exceção: UPDATE em historico com a flag de anonimização ligada, e só em antes/depois (id, tabela, registro,
-- ação, autor e data não mudam).
create function mkt_mensageria.trg_bloqueio() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'historico'
     and coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    if (new.id, new.tabela, new.registro_id, new.acao, new.por, new.em)
       is not distinct from (old.id, old.tabela, old.registro_id, old.acao, old.por, old.em) then
      return new;
    end if;
  end if;
  raise exception 'mkt_mensageria.%: % não é permitido (o registro é permanente: arquivar ou desativar)', tg_table_name, tg_op
    using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_bloqueio() from public, anon, authenticated;

-- Procedência do disparo não muda depois de gravada (nem pela tela, nem por update direto).
create function mkt_mensageria.trg_disparo_procedencia() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.origem, new.origem_sistema, new.id_externo, new.importacao_id)
     is distinct from (old.origem, old.origem_sistema, old.id_externo, old.importacao_id) then
    raise exception 'mkt_mensageria.disparos: origem, origem_sistema, id_externo e importacao_id não mudam depois de gravados'
      using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_disparo_procedencia() from public, anon, authenticated;

create trigger a_carimbo before insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger b_status before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_numero_status();
create trigger b_procedencia before update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_disparo_procedencia();
create trigger z_historico after insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_historico();
do $bloqueio$
declare t text;
begin
  foreach t in array array['ferramentas', 'numeros', 'disparos', 'importacoes', 'historico'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;
create trigger sem_update before update on mkt_mensageria.importacoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.historico
  for each row execute function mkt_mensageria.trg_bloqueio();

-- ─── 5. Seed: 13 ferramentas, custos não lançados ────────────────────────────────────────────────────────────────────
insert into mkt_mensageria.ferramentas (nome, api) values
  ('SendFlow', 'sim'), ('Unichat', 'sim'), ('ActiveCampaign', 'sim'), ('n8n', 'sim'), ('Google Drive', 'sim'),
  ('Slack', 'sim'), ('ClickUp', 'sim'),
  ('Infobip', 'nao'), ('Clint', 'nao'), ('Ligue Lead', 'nao'), ('Encurtador', 'nao'), ('Respondi', 'nao'), ('ManyChat', 'nao');

-- ─── 6. Validação de disparo (uma regra para a tela e para a planilha) ───────────────────────────────────────────────
-- Entrada (texto): enviado_em, projeto (sigla), canal, ferramenta_id, numero_id, tipo, copy_texto, copy_link,
--   publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por.
--   origem_sistema/id_externo NÃO entram (só integração, origem 'api'). Ferramenta desativada e número arquivado: recusa.
--   Saída: {erros:[{campo,msg}], v:{… valores já convertidos, projeto_id …}}.
create function mkt_mensageria.disparo_validar(p jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_enviado timestamptz := mkt_mensageria.instante(p ->> 'enviado_em');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_projeto bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_num_txt text := btrim(coalesce(p ->> 'numero_id', ''));
  v_num bigint;
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_copy text := nullif(btrim(coalesce(p ->> 'copy_texto', '')), '');
  v_link text := nullif(btrim(coalesce(p ->> 'copy_link', '')), '');
  v_lista text := btrim(coalesce(p ->> 'publico_lista', ''));
  v_origem_lista text := nullif(btrim(coalesce(p ->> 'publico_origem', '')), '');
  v_tam bigint := mkt_mensageria.inteiro(p ->> 'tamanho_lista');
  v_ent bigint := mkt_mensageria.inteiro(p ->> 'entregues');
  v_lid bigint := mkt_mensageria.inteiro(p ->> 'lidas');
  v_cli bigint := mkt_mensageria.inteiro(p ->> 'cliques');
  v_fal bigint := mkt_mensageria.inteiro(p ->> 'falhas');
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_centavos');
  v_por text := btrim(coalesce(p ->> 'disparado_por', ''));
  v_ferr_ativa boolean;
  v_ferr_nome text;
  v_num_arq timestamptz;
  v_num_txt2 text;
  v_numeros_ok boolean := true;
begin
  if v_enviado is null then
    e := e || jsonb_build_object('campo', 'enviado_em', 'msg', 'Informe a data e a hora do envio.');
  end if;

  if v_sigla = '' then
    e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
  else
    select pr.id into v_projeto from mkt.projetos pr where pr.sigla = v_sigla;
    if v_projeto is null then
      e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
    end if;
  end if;

  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  end if;

  if v_ferr_txt !~ '^[0-9]{1,18}$' then
    e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.');
  else
    select f.id, f.ativa, f.nome into v_ferr, v_ferr_ativa, v_ferr_nome
      from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Ferramenta não cadastrada.');
    elsif not v_ferr_ativa then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg',
        'Ferramenta ' || v_ferr_nome || ' está desativada: reative em Ferramentas ou escolha outra.');
    end if;
  end if;

  if v_num_txt <> '' then
    if v_num_txt ~ '^[0-9]{1,18}$' then
      select n.id, n.arquivado_em, n.numero into v_num, v_num_arq, v_num_txt2
        from mkt_mensageria.numeros n where n.id = v_num_txt::bigint;
    end if;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg', 'Número não cadastrado em Números.');
    elsif v_num_arq is not null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg',
        'Número ' || v_num_txt2 || ' está arquivado: desarquive em Números ou escolha outro.');
    end if;
  end if;

  if v_canal = 'whatsapp_api' and v_tipo is null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal in ('email', 'sms', 'ligacao', 'grupo') and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  elsif v_tipo is not null and v_tipo not in ('utility', 'marketing') then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo inválido: utility ou marketing.');
  end if;

  if v_copy is null and v_link is null then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Informe a copy: o texto, o link, ou os dois.');
  end if;
  if length(v_copy) > 4000 then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Texto da copy passa de 4.000 caracteres.');
  end if;
  if length(v_link) > 2000 then
    e := e || jsonb_build_object('campo', 'copy_link', 'msg', 'Link passa de 2.000 caracteres.');
  end if;

  if v_lista = '' or length(v_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_lista', 'msg', 'Informe a lista (público), até 200 caracteres.');
  end if;
  if length(v_origem_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_origem', 'msg', 'Origem da lista passa de 200 caracteres.');
  end if;

  if v_tam is null then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Informe o tamanho da lista.');
    v_numeros_ok := false;
  elsif v_tam < 0 then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Tamanho da lista: número inteiro, sem sinal.');
    v_numeros_ok := false;
  end if;
  if v_ent < 0 then e := e || jsonb_build_object('campo', 'entregues', 'msg', 'Entregues: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_lid < 0 then e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_cli < 0 then e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_fal < 0 then e := e || jsonb_build_object('campo', 'falhas', 'msg', 'Falhas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
  end if;

  if v_numeros_ok then
    if coalesce(v_ent, 0) + coalesce(v_fal, 0) > v_tam then
      e := e || jsonb_build_object('campo', 'entregues', 'msg',
        'Entregues + falhas (' || (coalesce(v_ent, 0) + coalesce(v_fal, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
    end if;
    if v_lid > v_ent then
      e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas (' || v_lid || ') não pode passar de entregues (' || v_ent || ').');
    end if;
    if v_cli > v_ent then
      e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques (' || v_cli || ') não pode passar de entregues (' || v_ent || ').');
    end if;
  end if;

  if v_por = '' or length(v_por) > 80 then
    e := e || jsonb_build_object('campo', 'disparado_por', 'msg', 'Informe quem disparou (até 80 caracteres).');
  end if;

  return jsonb_build_object('erros', e, 'v', jsonb_build_object(
    'enviado_em', v_enviado, 'projeto_id', v_projeto, 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', v_copy, 'copy_link', v_link, 'publico_lista', v_lista, 'publico_origem', v_origem_lista,
    'tamanho_lista', v_tam, 'entregues', v_ent, 'lidas', v_lid, 'cliques', v_cli, 'falhas', v_fal,
    'custo_centavos', v_custo, 'disparado_por', v_por));
end
$$;
revoke all on function mkt_mensageria.disparo_validar(jsonb) from public, anon, authenticated;

-- Uma linha de planilha → mesma validação. Colunas: data (dd/mm/aaaa), hora (hh:mm), projeto (sigla), canal (código ou
-- rótulo), ferramenta (nome, sem diferenciar maiúscula), numero (+55…; vazio = sem número), tipo, copy_texto, copy_link,
-- publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas ("1.234"), custo ("1.234,56" reais),
-- disparado_por. Saída: {linha, erros:[{linha,campo,msg}], v:{…}}. campo = nome da coluna da planilha.
create function mkt_mensageria.importar_linha(l jsonb, n integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_canon jsonb;
  r jsonb;
  x jsonb;
  v_ja text[] := '{}';
  v_quando timestamptz;
  v_txt text;
  v_ferr bigint;
  v_num bigint;
  v_custo bigint;
  v_canal text;
  v_tipo text;
  k text;
  v_map jsonb := '{"enviado_em":"data","ferramenta_id":"ferramenta","numero_id":"numero","custo_centavos":"custo"}';
begin
  if l is null or jsonb_typeof(l) <> 'object' then
    return jsonb_build_object('linha', n, 'erros', jsonb_build_array(jsonb_build_object('linha', n, 'campo', '-', 'msg', 'Linha em formato inválido.')), 'v', null);
  end if;

  if btrim(coalesce(l ->> 'data', '')) !~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then
    e := e || jsonb_build_object('campo', 'data', 'msg', 'Data inválida: use dd/mm/aaaa.'); v_ja := array_append(v_ja, 'enviado_em');
  elsif btrim(coalesce(l ->> 'hora', '')) !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
    e := e || jsonb_build_object('campo', 'hora', 'msg', 'Hora inválida: use hh:mm (00:00 a 23:59).'); v_ja := array_append(v_ja, 'enviado_em');
  else
    v_quando := mkt_mensageria.data_hora_br(l ->> 'data', l ->> 'hora');
    if v_quando is null then
      e := e || jsonb_build_object('campo', 'data', 'msg', 'Data não existe: ' || btrim(l ->> 'data') || '.'); v_ja := array_append(v_ja, 'enviado_em');
    end if;
  end if;

  v_txt := btrim(coalesce(l ->> 'ferramenta', ''));
  if v_txt = '' then
    e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Informe a ferramenta.'); v_ja := array_append(v_ja, 'ferramenta_id');
  else
    select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.'); v_ja := array_append(v_ja, 'ferramenta_id');
    end if;
  end if;

  v_txt := regexp_replace(coalesce(l ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero', 'msg', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.'); v_ja := array_append(v_ja, 'numero_id');
    end if;
  end if;

  v_custo := mkt_mensageria.centavos_br(l ->> 'custo');
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo', 'msg', 'Custo inválido: use reais, como 1.234,56 (ou vazio se não lançado).');
    v_ja := array_append(v_ja, 'custo_centavos'); v_custo := null;
  end if;

  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'canal', '')));
  v_canal := case when v_txt in ('WHATSAPP_API', 'API WHATSAPP', 'WHATSAPP API', 'API') then 'whatsapp_api'
                  when v_txt in ('EMAIL', 'E-MAIL') then 'email'
                  when v_txt = 'SMS' then 'sms'
                  when v_txt in ('LIGACAO', 'LIGACOES') then 'ligacao'
                  when v_txt in ('GRUPO', 'GRUPOS') then 'grupo'
                  else lower(v_txt) end;
  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'tipo', '')));
  v_tipo := case when v_txt in ('UTILITY', 'UTILIDADE') then 'utility' when v_txt = 'MARKETING' then 'marketing'
                 else nullif(lower(v_txt), '') end;

  v_canon := jsonb_build_object(
    'enviado_em', v_quando, 'projeto', l ->> 'projeto', 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', l ->> 'copy_texto', 'copy_link', l ->> 'copy_link', 'publico_lista', l ->> 'publico_lista',
    'publico_origem', l ->> 'publico_origem', 'disparado_por', l ->> 'disparado_por', 'custo_centavos', v_custo);
  foreach k in array array['tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas'] loop
    -- "1.234" vira "1234"; formato errado segue cru e a validação acusa.
    v_canon := v_canon || jsonb_build_object(k, case when mkt_mensageria.inteiro_br(l ->> k) >= 0
                                                     then mkt_mensageria.inteiro_br(l ->> k)::text else l ->> k end);
  end loop;

  r := mkt_mensageria.disparo_validar(v_canon);
  for x in select * from jsonb_array_elements(r -> 'erros') loop
    if not (x ->> 'campo' = any(v_ja)) then
      e := e || jsonb_build_object('campo', coalesce(v_map ->> (x ->> 'campo'), x ->> 'campo'), 'msg', x ->> 'msg');
    end if;
  end loop;

  return jsonb_build_object('linha', n,
    'erros', (select coalesce(jsonb_agg(jsonb_build_object('linha', n) || y), '[]'::jsonb) from jsonb_array_elements(e) y),
    'v', case when jsonb_array_length(e) = 0 then r -> 'v' end);
end
$$;
revoke all on function mkt_mensageria.importar_linha(jsonb, integer) from public, anon, authenticated;

-- ─── 7. Funções públicas (RPC). Toda uma: guarda mkt.pode_ver('mkt_mensageria') + revoke/grant logo abaixo ──────────

-- Lista do período. Ver contrato em 20261005n.explain.md. plan_cache_mode: cada chamada planeja com os valores reais,
-- então "(v_proj is null or projeto_id = v_proj)" vira "projeto_id = 5" e o índice (projeto_id, enviado_em) entra.
create function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                               p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, mkt_mensageria.pendencias(d.entregues, d.lidas, d.custo_centavos) as pendencias
        from mkt_mensageria.disparos d
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias))
               order by b.enviado_em desc, b.id desc)
          from pagina b
          join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo, count(*) filter (where b.custo_centavos is null) as sem_custo
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: ver mkt_mensageria.disparo_validar. Retorna {ok, msg, id, erros?}.
-- origem é sempre 'manual'; origem_sistema/id_externo vindos no JSON são ignorados (não grava nem altera).
-- Na edição, retorno_em é carimbado se entregues/lidas/cliques/falhas/custo mudaram. Arquivado não se edita.
create function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Arquiva (some da lista e dos totais; fica no banco e no histórico). Motivo obrigatório. Nunca apaga.
create function public.mkt_msg_disparo_arquivar(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo do arquivamento (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.disparos set arquivado_em = now(), arquivado_motivo = v_motivo
   where id = p_id and arquivado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.disparos where id = p_id) then 'Disparo já arquivado.'
      else 'Disparo não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Disparo arquivado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_disparo_arquivar(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_arquivar(bigint, text) to authenticated;

-- Lança o retorno de um disparo. Os 5 valores substituem os atuais; nulo = não lançado (nunca vira 0).
-- retorno_em = agora; se os 5 vierem nulos, retorno_em volta a nulo.
create function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                      p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista into v_tam from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
                            'pendencias', to_jsonb(mkt_mensageria.pendencias(p_entregues, p_lidas, p_custo_centavos)));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Importa planilha. p_confirmar=false: só valida e devolve {ok, erros, validas, total, duplicadas_banco, duplicadas_lote}.
-- p_confirmar=true: tudo ou nada; com qualquer erro, nada entra. Com possível duplicata (já no log, ou repetida no
-- próprio lote: mesma data/hora, projeto, canal e lista) também nada entra, a menos que p_aceitar_duplicadas=true.
-- Máx. 2.000 linhas. A planilha não grava origem_sistema/id_externo (ver 20261005n.explain.md). Colunas em importar_linha.
create function public.mkt_msg_importar(p_linhas jsonb, p_confirmar boolean default false, p_arquivo text default null,
                                        p_aceitar_duplicadas boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer;
  v_res jsonb[];
  v_erros jsonb;
  v_qtd_erros integer;
  v_validas integer;
  v_dup_banco jsonb;
  v_dup_lote jsonb;
  v_tem_dup boolean;
  v_imp bigint;
  v_ins integer;
  v_con text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Nenhuma linha para importar.', 'erros', '[]'::jsonb, 'validas', 0, 'total', 0);
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n > 2000 then
    return jsonb_build_object('ok', false, 'msg', 'Máximo de 2.000 linhas por importação (vieram ' || v_n || '). Divida a planilha.',
                              'erros', '[]'::jsonb, 'validas', 0, 'total', v_n);
  end if;
  -- Duas confirmações ao mesmo tempo não passam juntas: a segunda espera a primeira e então vê as duplicatas dela.
  if coalesce(p_confirmar, false) then
    perform pg_advisory_xact_lock(hashtext('mkt_mensageria.importar'));
  end if;

  select array_agg(mkt_mensageria.importar_linha(t.l, t.n::int) order by t.n) into v_res
    from jsonb_array_elements(p_linhas) with ordinality t(l, n);

  select count(*), coalesce(jsonb_agg(x.e order by x.linha, x.o) filter (where x.rn <= 500), '[]'::jsonb)
    into v_qtd_erros, v_erros
    from (select (r ->> 'linha')::int as linha, e.o, e.e, row_number() over (order by (r ->> 'linha')::int, e.o) as rn
            from unnest(v_res) r, jsonb_array_elements(r -> 'erros') with ordinality e(e, o)) x;
  select count(*) into v_validas from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object';

  -- Duplicata contra o banco: mesma data/hora, projeto, canal e lista já no log (não arquivado). Índice (projeto_id, enviado_em).
  select coalesce(jsonb_agg((r ->> 'linha')::int order by (r ->> 'linha')::int), '[]'::jsonb) into v_dup_banco
    from unnest(v_res) r
   where jsonb_typeof(r -> 'v') = 'object'
     and exists (select 1 from mkt_mensageria.disparos d
                  where d.projeto_id = (r -> 'v' ->> 'projeto_id')::bigint
                    and d.enviado_em = (r -> 'v' ->> 'enviado_em')::timestamptz
                    and d.canal = r -> 'v' ->> 'canal'
                    and d.publico_lista = r -> 'v' ->> 'publico_lista'
                    and d.arquivado_em is null);
  -- Duplicata dentro do lote: todas as linhas de um grupo repetido.
  select coalesce(jsonb_agg(x.linha order by x.linha), '[]'::jsonb) into v_dup_lote
    from (select (r ->> 'linha')::int as linha,
                 count(*) over (partition by r -> 'v' ->> 'projeto_id', (r -> 'v' ->> 'enviado_em')::timestamptz,
                                             r -> 'v' ->> 'canal', r -> 'v' ->> 'publico_lista') as qtd
            from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object') x
   where x.qtd > 1;
  v_tem_dup := jsonb_array_length(v_dup_banco) > 0 or jsonb_array_length(v_dup_lote) > 0;

  if not coalesce(p_confirmar, false) or v_qtd_erros > 0 then
    return jsonb_build_object('ok', v_qtd_erros = 0,
      'msg', case when v_qtd_erros > 0 then v_qtd_erros || ' erro(s) em ' || (v_n - v_validas) || ' linha(s). Nada foi gravado.'
                  when v_tem_dup then v_validas || ' linhas válidas, com possível duplicata (veja as linhas). Nada foi gravado ainda.'
                  else v_validas || ' linhas válidas. Nada foi gravado ainda.' end,
      'erros', v_erros, 'erros_total', v_qtd_erros, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;
  if v_tem_dup and not coalesce(p_aceitar_duplicadas, false) then
    return jsonb_build_object('ok', false,
      'msg', 'Possível duplicata: ' || jsonb_array_length(v_dup_banco) || ' linha(s) já no registro e '
             || jsonb_array_length(v_dup_lote) || ' repetida(s) na planilha. Nada foi gravado. Confira e, se estiver certo, '
             || 'confirme de novo marcando "importar mesmo assim".',
      'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;

  begin
    insert into mkt_mensageria.importacoes (arquivo, linhas, criado_por)
    values (nullif(left(btrim(coalesce(p_arquivo, '')), 255), ''), v_n, (select auth.uid()))
    returning id into v_imp;

    insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, importacao_id)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'planilha', v_imp
      from (select r -> 'v' as v, (r ->> 'linha')::int as linha from unnest(v_res) r) s
     order by s.linha;
    get diagnostics v_ins = row_count;
  exception
    when check_violation or foreign_key_violation or not_null_violation or unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Nada foi importado: valor fora da regra (' || coalesce(v_con, 'dados') || ').',
                                'erros', '[]'::jsonb, 'validas', v_validas, 'total', v_n);
  end;
  return jsonb_build_object('ok', true, 'msg', v_ins || ' disparos importados.', 'importacao_id', v_imp,
                            'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_ins, 'total', v_n,
                            'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
end
$$;
revoke all on function public.mkt_msg_importar(jsonb, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.mkt_msg_importar(jsonb, boolean, text, boolean) to authenticated;

-- Números com consumo de hoje (America/Sao_Paulo) somado do log. Uma query; por número, um lookup no índice
-- (numero_id, enviado_em) restrito ao dia. Arquivados vêm por último, com arquivado_em preenchido.
create function public.mkt_msg_numeros_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini timestamptz := v_hoje::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (v_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'numeros', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', n.id, 'numero', n.numero, 'projeto_id', n.projeto_id, 'projeto', pr.sigla, 'frente', n.frente,
             'responsavel', n.responsavel, 'finalidade', n.finalidade, 'ferramenta_id', n.ferramenta_id,
             'ferramenta', f.nome, 'capacidade_dia', n.capacidade_dia, 'status', n.status, 'status_desde', n.status_desde,
             'arquivado_em', n.arquivado_em, 'consumo_hoje', coalesce(c.total, 0),
             'acima_da_capacidade', n.capacidade_dia is not null and coalesce(c.total, 0) > n.capacidade_dia,
             'atualizado_em', n.atualizado_em)
           order by (n.arquivado_em is not null), array_position(array['ativo', 'aquecendo', 'restrito', 'disponivel'], n.status), n.numero),
           '[]'::jsonb)
      from mkt_mensageria.numeros n
      left join mkt.projetos pr on pr.id = n.projeto_id
      left join mkt_mensageria.ferramentas f on f.id = n.ferramenta_id
      left join lateral (select sum(d.tamanho_lista) as total
                           from mkt_mensageria.disparos d
                          where d.numero_id = n.id and d.enviado_em >= v_ini and d.enviado_em < v_fim
                            and d.arquivado_em is null) c on true));
end
$$;
revoke all on function public.mkt_msg_numeros_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_numeros_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: numero (+55 11 99999-0000: espaços, traços e parênteses saem; o "+" e o
-- código do país são obrigatórios), projeto (sigla, opcional), frente, responsavel, finalidade, ferramenta_id,
-- capacidade_dia (1 a 1000, opcional), status, arquivado (bool). Retorna {ok, msg, id}.
create function public.mkt_msg_numero_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_numero text := regexp_replace(coalesce(p ->> 'numero', ''), '[\s().-]', '', 'g');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_proj bigint;
  v_frente text := nullif(btrim(coalesce(p ->> 'frente', '')), '');
  v_resp text := btrim(coalesce(p ->> 'responsavel', ''));
  v_fin text := lower(btrim(coalesce(p ->> 'finalidade', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_cap bigint := mkt_mensageria.inteiro(p ->> 'capacidade_dia');
  v_status text := lower(btrim(coalesce(p ->> 'status', '')));
  v_arq boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados do número ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_arq := coalesce(nullif(p ->> 'arquivado', '')::boolean, false);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "arquivado" deve ser verdadeiro ou falso.');
  end;
  if v_numero !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número no formato internacional, com + e código do país (ex.: +55 11 99999-0000).');
  end if;
  if v_sigla <> '' then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
    if v_proj is null then return jsonb_build_object('ok', false, 'msg', 'Projeto ' || v_sigla || ' não cadastrado.'); end if;
  end if;
  if length(v_frente) > 60 then return jsonb_build_object('ok', false, 'msg', 'Frente: até 60 caracteres.'); end if;
  if v_resp = '' or length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Informe o responsável (até 80 caracteres).'); end if;
  if v_fin not in ('mensageria', 'comercial', 'financeiro', 'suporte') then
    return jsonb_build_object('ok', false, 'msg', 'Finalidade: mensageria, comercial, financeiro ou suporte.');
  end if;
  if v_ferr_txt <> '' then
    if v_ferr_txt ~ '^[0-9]{1,18}$' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    end if;
    if v_ferr is null then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não cadastrada.'); end if;
  end if;
  if v_cap is not null and (v_cap < 1 or v_cap > 1000) then
    return jsonb_build_object('ok', false, 'msg', 'Capacidade por dia: de 1 a 1.000 (ou vazio se não definida).');
  end if;
  if v_status not in ('ativo', 'aquecendo', 'restrito', 'disponivel') then
    return jsonb_build_object('ok', false, 'msg', 'Status: ativo, aquecendo, restrito ou disponível.');
  end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.numeros (numero, projeto_id, frente, responsavel, finalidade, ferramenta_id, capacidade_dia,
                                          status, arquivado_em)
      values (v_numero, v_proj, v_frente, v_resp, v_fin, v_ferr, v_cap::smallint, v_status, case when v_arq then now() end)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' cadastrado.', 'id', v_id);
    end if;
    update mkt_mensageria.numeros n
       set numero = v_numero, projeto_id = v_proj, frente = v_frente, responsavel = v_resp, finalidade = v_fin,
           ferramenta_id = v_ferr, capacidade_dia = v_cap::smallint, status = v_status,
           arquivado_em = case when v_arq then coalesce(n.arquivado_em, now()) end
     where n.id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Número não encontrado.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' salvo.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Número ' || v_numero || ' já cadastrado.');
  end;
end
$$;
revoke all on function public.mkt_msg_numero_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_numero_salvar(jsonb) to authenticated;

create function public.mkt_msg_ferramentas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', f.id, 'nome', f.nome, 'api', f.api, 'custo_mensal_centavos', f.custo_mensal_centavos,
            'responsavel', f.responsavel, 'ativa', f.ativa, 'obs', f.obs, 'atualizado_em', f.atualizado_em)
          order by f.ativa desc, lower(f.nome)), '[]'::jsonb)
            from mkt_mensageria.ferramentas f);
end
$$;
revoke all on function public.mkt_msg_ferramentas_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramentas_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: nome, api (sim|futura|nao), custo_mensal_centavos (inteiro ≥ 0; vazio =
-- não lançado), responsavel, ativa, obs. Ferramenta não se apaga: desativa (ativa=false). Retorna {ok, msg, id}.
create function public.mkt_msg_ferramenta_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_api text := lower(btrim(coalesce(p ->> 'api', '')));
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_mensal_centavos');
  v_resp text := nullif(btrim(coalesce(p ->> 'responsavel', '')), '');
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_ativa boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados da ferramenta ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Ferramenta inválida.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_ativa := coalesce(nullif(p ->> 'ativa', '')::boolean, true);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "ativa" deve ser verdadeiro ou falso.');
  end;
  if v_nome = '' or length(v_nome) > 60 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome (até 60 caracteres).'); end if;
  if v_api not in ('sim', 'futura', 'nao') then
    return jsonb_build_object('ok', false, 'msg', 'API: sim, futura ou não.');
  end if;
  if v_custo < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Custo mensal: centavos, inteiro ≥ 0 (ou vazio se não lançado).');
  end if;
  if length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Responsável: até 80 caracteres.'); end if;
  if length(v_obs) > 1000 then return jsonb_build_object('ok', false, 'msg', 'Observação: até 1.000 caracteres.'); end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.ferramentas (nome, api, custo_mensal_centavos, responsavel, ativa, obs)
      values (v_nome, v_api, v_custo::int, v_resp, v_ativa, v_obs)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' cadastrada.', 'id', v_id);
    end if;
    update mkt_mensageria.ferramentas
       set nome = v_nome, api = v_api, custo_mensal_centavos = v_custo::int, responsavel = v_resp, ativa = v_ativa, obs = v_obs
     where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não encontrada.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' salva.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Já existe ferramenta com o nome ' || v_nome || '.');
  end;
end
$$;
revoke all on function public.mkt_msg_ferramenta_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramenta_salvar(jsonb) to authenticated;

-- Histórico de um registro (até 200 mudanças, mais recente primeiro). p_tabela: disparos | numeros | ferramentas.
create function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', pf.nome, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- LGPD: apaga o conteúdo que pode ter dado pessoal (copy_texto, publico_lista, publico_origem) de UM disparo e de todas
-- as linhas do histórico dele, e registra a anonimização no histórico (acao 'anonimizar', com motivo, sem o conteúdo).
-- Só admin/dev (gp_is_admin), mesmo quando mkt.pode_ver for aberto a operador/gestor. Funciona com disparo arquivado.
-- Exceção controlada ao bloqueio de UPDATE do histórico: flag local à transação, desligada antes de sair.
create function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform 1 from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  f record;
  v_publicas text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                             'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                             'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                             'mkt_msg_historico', 'mkt_msg_anonimizar_disparo'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_mensageria', 'usage') or has_schema_privilege(r, 'mkt_mensageria', 'create') then
      raise exception '20261005n: % tem acesso ao schema mkt_mensageria', r;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005n: % tem privilégio em %', r, t;
      end if;
    end loop;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005n: RLS desligada em %', t;
    end if;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005n: PUBLIC tem privilégio em %', t;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'S' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_sequence_privilege(r, t, 'usage, select, update') then
        raise exception '20261005n: % tem privilégio na sequência %', r, t;
      end if;
    end loop;
  end loop;

  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005n: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005n: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005n: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_publicas))
       <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005n: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005n: % deveria ser SECURITY DEFINER', f.sig;
    end if;
    if f.proname = any(v_publicas) and f.proname <> 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda coalesce(mkt.pode_ver(''mkt_mensageria''), false)', f.sig;
    end if;
    if f.proname = 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda gp_is_admin', f.sig;
    end if;
    if f.pronamespace = 'mkt_mensageria'::regnamespace and f.prosecdef then
      raise exception '20261005n: interna % não deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 11
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 11 then
    raise exception '20261005n: esperava exatamente as 11 funções public.mkt_msg_* (sobrecarga?)';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria' and table_name = 'disparos'
                and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos') and column_default is not null) then
    raise exception '20261005n: retorno/custo com default (nulo tem que ser "não lançado")';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas) <> 13
     or exists (select 1 from mkt_mensageria.ferramentas where custo_mensal_centavos is not null) then
    raise exception '20261005n: seed diferente do esperado (13 ferramentas, custos nulos)';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; apaga TODO o log de disparos, números e histórico: exportar antes) ═══════════════════
-- begin;
-- drop function public.mkt_msg_disparos_listar(date, date, text, text, bigint), public.mkt_msg_disparo_salvar(jsonb),
--   public.mkt_msg_disparo_arquivar(bigint, text),
--   public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer),
--   public.mkt_msg_importar(jsonb, boolean, text, boolean), public.mkt_msg_numeros_listar(), public.mkt_msg_numero_salvar(jsonb),
--   public.mkt_msg_ferramentas_listar(), public.mkt_msg_ferramenta_salvar(jsonb), public.mkt_msg_historico(text, text),
--   public.mkt_msg_anonimizar_disparo(bigint, text);
-- drop schema mkt_mensageria cascade;   -- leva tabelas, triggers e as FKs para mkt.projetos (mkt.projetos fica intacta)
-- commit;
-- Desligar sem apagar dado: revoke execute on function public.mkt_msg_<…> from authenticated; (a tela recebe 42501).

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito) ═══════════════════════════
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projeto e ferramenta usados nos testes (os ids reais de produção; nada é escrito em mkt.projetos)
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as projeto_id,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign;
grant all on _z_ref to public;
-- Muda para "admin logado" (role authenticated + JWT do admin) e de volta para postgres.
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;

-- ═══ BLOCO 1: segurança e regras (a–f e extras) ═══════════════════════════════════════════════════════════════════
-- Ta. anon: nenhuma função executa (sem EXECUTE → 42501)
-- Tb. authenticated NÃO-admin (uid sem perfil): guarda mkt.pode_ver nega com 42501
do $tab$
declare
  c text;
  v_r text;
  v_chamadas text[] := array[
    'select public.mkt_msg_disparos_listar(current_date - 30, current_date)',
    'select public.mkt_msg_disparo_salvar(''{}'')',
    'select public.mkt_msg_disparo_arquivar(1, ''teste'')',
    'select public.mkt_msg_disparo_lancar_retorno(1, 1, 1, 1, 0, 100)',
    'select public.mkt_msg_importar(''[]'', false, null)',
    'select public.mkt_msg_numeros_listar()',
    'select public.mkt_msg_numero_salvar(''{}'')',
    'select public.mkt_msg_ferramentas_listar()',
    'select public.mkt_msg_ferramenta_salvar(''{}'')',
    'select public.mkt_msg_historico(''disparos'', ''1'')',
    'select public.mkt_msg_anonimizar_disparo(1, ''teste'')'];
begin
  foreach v_r in array array['anon', 'authenticated'] loop
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000ff","role":"' || v_r || '"}', true);
    foreach c in array v_chamadas loop
      execute format('set local role %I', v_r);
      begin
        execute c;
        reset role;
        raise exception 'T% FALHOU: % executou %', case v_r when 'anon' then 'a' else 'b' end, v_r, c;
      exception when insufficient_privilege then
        reset role;
      end;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.ok('Ta', 'anon: 42501 nas 11 funções');
  perform pg_temp.ok('Tb', 'authenticated não-admin: 42501 nas 11 funções');
end
$tab$;

-- Tf. anon/authenticated sem USAGE no schema, sem privilégio em tabela/sequência; select direto recusado
do $tf$
declare
  r text;
  t text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_mensageria', 'usage') or has_schema_privilege(r, 'mkt_mensageria', 'create') then
      raise exception 'Tf FALHOU: % tem USAGE/CREATE em mkt_mensageria', r;
    end if;
    for t in select c.oid::regclass::text from pg_class c where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'r' loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate') then
        raise exception 'Tf FALHOU: % tem privilégio em %', r, t;
      end if;
    end loop;
    execute format('set local role %I', r);
    begin
      perform 1 from mkt_mensageria.disparos limit 1;
      reset role;
      raise exception 'Tf FALHOU: % leu mkt_mensageria.disparos direto', r;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;
  perform pg_temp.ok('Tf', 'sem USAGE no schema, sem privilégio nas 5 tabelas, select direto = 42501 (anon e authenticated)');
end
$tf$;

-- Tc. CHECKs na tabela (insert direto como postgres, sem passar pela RPC)
create function pg_temp.espera_check(p_sql text, p_con text) returns void language plpgsql as $f$
declare v_con text;
begin
  begin
    execute p_sql;
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if v_con is distinct from p_con then
      raise exception 'Tc FALHOU: esperava %, veio %', p_con, v_con;
    end if;
    return;
  end;
  raise exception 'Tc FALHOU: a tabela aceitou (deveria recusar por %)', p_con;
end
$f$;
do $tc$
declare
  v_base text := 'insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, tipo, copy_texto, publico_lista, '
              || 'tamanho_lista, entregues, lidas, falhas, disparado_por) values (now(), '
              || (select projeto_id from pg_temp._z_ref) || ', %L, ' || (select sendflow from pg_temp._z_ref) || ', %L, %L, ''L'', 100, %s, %s, %s, ''Ensaio'')';
begin
  perform pg_temp.espera_check(format(v_base, 'email', 'marketing', 'x', 'null', 'null', 'null'), 'disparos_tipo_so_na_api');
  perform pg_temp.espera_check(format(v_base, 'whatsapp_api', null, 'x', 'null', 'null', 'null'), 'disparos_tipo_so_na_api');
  perform pg_temp.espera_check(format(v_base, 'sms', null, 'x', '5', '10', 'null'), 'disparos_lidas_entregues');
  perform pg_temp.espera_check(format(v_base, 'sms', null, 'x', '90', 'null', '20'), 'disparos_entregues_falhas');
  perform pg_temp.espera_check(format(v_base, 'sms', null, null, 'null', 'null', 'null'), 'disparos_copy_obrigatoria');
  perform pg_temp.espera_check(format(v_base, 'sms', null, 'x', '-1', 'null', 'null'), 'disparos_entregues_check');
  perform pg_temp.espera_check(
    'insert into mkt_mensageria.numeros (numero, responsavel, finalidade, status) values (''5511999990000'', ''R'', ''mensageria'', ''ativo'')',
    'numeros_numero_check');
  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria' and table_name = 'disparos'
                and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos') and column_default is not null) then
    raise exception 'Tc FALHOU: retorno/custo com default';
  end if;
  perform pg_temp.ok('Tc', 'tabela recusa: tipo fora da API, API sem tipo, lidas>entregues, entregues+falhas>tamanho, sem copy, negativo, número fora do E.164; retorno/custo sem default');
end
$tc$;

-- Tc2. Pela RPC (como admin): mensagem legível; retorno 0 ≠ nulo (pendências e valor gravado)
create temp table _z_ids (nome text primary key, id bigint) on commit drop;
grant all on _z_ids to public;
select pg_temp.como_admin();
do $tc2$
declare
  r jsonb;
  v_base jsonb := jsonb_build_object('enviado_em', to_jsonb(now()), 'projeto', (select sigla from pg_temp._z_ref),
                    'ferramenta_id', (select activecampaign from pg_temp._z_ref), 'copy_texto', 'Copy do ensaio',
                    'publico_lista', 'Lista do ensaio', 'tamanho_lista', 100, 'disparado_por', 'Ensaio');
begin
  r := public.mkt_msg_disparo_salvar(v_base || '{"canal":"email","tipo":"marketing"}');
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Tipo só existe na API do WhatsApp%' then
    raise exception 'Tc2 FALHOU: tipo em e-mail pela RPC: %', r;
  end if;
  r := public.mkt_msg_disparo_salvar(v_base || '{"canal":"sms","entregues":5,"lidas":10}');
  if (r ->> 'ok')::boolean or r ->> 'msg' <> 'Lidas (10) não pode passar de entregues (5).' then
    raise exception 'Tc2 FALHOU: lidas>entregues pela RPC: %', r;
  end if;
  r := public.mkt_msg_disparo_salvar(v_base || '{"canal":"email","entregues":0,"lidas":0,"cliques":0,"falhas":0,"custo_centavos":500}');
  if not (r ->> 'ok')::boolean then raise exception 'Tc2 FALHOU: salvar A: %', r; end if;
  insert into pg_temp._z_ids values ('A', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || '{"canal":"email"}');
  if not (r ->> 'ok')::boolean then raise exception 'Tc2 FALHOU: salvar B: %', r; end if;
  insert into pg_temp._z_ids values ('B', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparos_listar((now() at time zone 'America/Sao_Paulo')::date - 1, (now() at time zone 'America/Sao_Paulo')::date);
  if (select x -> 'pendencias' from jsonb_array_elements(r -> 'linhas') x where (x ->> 'id')::bigint = (select id from pg_temp._z_ids where nome = 'A'))
       <> '["conferir_zero_leitura"]'::jsonb
     or (select x -> 'pendencias' from jsonb_array_elements(r -> 'linhas') x where (x ->> 'id')::bigint = (select id from pg_temp._z_ids where nome = 'B'))
       <> '["sem_custo", "sem_retorno"]'::jsonb
     or (r -> 'totais' ->> 'qtd')::int <> 2 or (r -> 'totais' ->> 'custo_centavos')::int <> 500
     or (r -> 'totais' ->> 'sem_custo')::int <> 1 or (r -> 'totais' ->> 'sem_retorno')::int <> 1
     or (r -> 'totais' ->> 'conferir_zero_leitura')::int <> 1 or (r -> 'totais' ->> 'entregues')::int <> 0 then
    raise exception 'Tc2 FALHOU: listar/pendências/totais: %', r;
  end if;
  perform pg_temp.ok('Tc2', 'RPC: mensagens legíveis; A(0 lançado)=["conferir_zero_leitura"], B(nulo)=["sem_custo","sem_retorno"]; totais qtd=2 custo=500 entregues=0');
end
$tc2$;
reset role;
do $tc3$
begin
  if not exists (select 1 from mkt_mensageria.disparos d join pg_temp._z_ids i on i.id = d.id and i.nome = 'A'
                  where d.entregues = 0 and d.lidas = 0 and d.retorno_em is not null and d.origem = 'manual'
                    and d.criado_por = (select id from pg_temp._z_admin))
     or not exists (select 1 from mkt_mensageria.disparos d join pg_temp._z_ids i on i.id = d.id and i.nome = 'B'
                     where d.entregues is null and d.lidas is null and d.custo_centavos is null and d.retorno_em is null) then
    raise exception 'Tc3 FALHOU: 0 e nulo não ficaram distintos no banco (ou carimbo errado)';
  end if;
  perform pg_temp.ok('Tc3', 'gravado: A entregues=0 lidas=0 retorno_em preenchido criado_por=admin; B entregues/lidas/custo nulos, retorno_em nulo');
end
$tc3$;

-- Td. Importar: 1 linha boa + 1 ruim com confirmar=true → nada entra. Depois só a boa → entra, formato BR convertido.
select pg_temp.como_admin();
do $td$
declare
  r jsonb;
  v_boa jsonb := jsonb_build_object('data', '05/10/2026', 'hora', '14:30', 'projeto', lower((select sigla from pg_temp._z_ref)),
                   'canal', 'E-mail', 'ferramenta', 'activecampaign', 'tipo', '', 'copy_texto', 'Oi', 'publico_lista', 'Lista importada',
                   'tamanho_lista', '1.234', 'entregues', '1.000', 'lidas', '0', 'custo', 'R$ 1.234,56', 'disparado_por', 'Ensaio');
  v_ruim jsonb := jsonb_build_object('data', '31/02/2026', 'hora', '14:30', 'projeto', 'ZZ99', 'canal', 'fax',
                   'ferramenta', 'Inexistente', 'copy_texto', 'x', 'publico_lista', 'L', 'tamanho_lista', '-3', 'custo', '12.50',
                   'disparado_por', 'Ensaio');
begin
  r := public.mkt_msg_importar(jsonb_build_array(v_boa, v_ruim), true, 'ensaio.csv');
  if (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 1 or (r ->> 'total')::int <> 2
     or exists (select 1 from jsonb_array_elements(r -> 'erros') e where (e ->> 'linha')::int <> 2)
     or (select array_agg(e ->> 'campo' order by e ->> 'campo') from jsonb_array_elements(r -> 'erros') e)
          <> array['canal', 'custo', 'data', 'ferramenta', 'projeto', 'tamanho_lista'] then
    raise exception 'Td FALHOU: importação com linha ruim: %', r;
  end if;
  insert into pg_temp._z_out (passo, linha) values ('Td.erros', r::text);
  r := public.mkt_msg_importar(jsonb_build_array(v_boa), false, 'ensaio.csv');
  if not (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 1
     or r -> 'duplicadas_banco' <> '[]'::jsonb or r -> 'duplicadas_lote' <> '[]'::jsonb then
    raise exception 'Td FALHOU: prévia da linha boa: %', r;
  end if;
  -- origem_sistema/id_externo numa linha de planilha: ignorados
  r := public.mkt_msg_importar(jsonb_build_array(v_boa || '{"origem_sistema":"x","id_externo":"y"}'), true, 'ensaio.csv');
  if not (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 1 or r ->> 'importacao_id' is null then
    raise exception 'Td FALHOU: confirmar a linha boa: %', r;
  end if;
end
$td$;
reset role;
do $td2$
begin
  if (select count(*) from mkt_mensageria.importacoes) <> 1
     or (select count(*) from mkt_mensageria.disparos where origem = 'planilha') <> 1
     or not exists (select 1 from mkt_mensageria.disparos d join mkt_mensageria.ferramentas f on f.id = d.ferramenta_id
                     where d.origem = 'planilha' and d.importacao_id is not null and f.nome = 'ActiveCampaign'
                       and d.enviado_em = '2026-10-05 14:30:00-03'::timestamptz and d.canal = 'email' and d.tipo is null
                       and d.tamanho_lista = 1234 and d.entregues = 1000 and d.lidas = 0 and d.cliques is null
                       and d.custo_centavos = 123456 and d.retorno_em is not null
                       and d.origem_sistema is null and d.id_externo is null) then
    raise exception 'Td FALHOU: o que entrou não confere (ou a linha ruim deixou rastro)';
  end if;
  perform pg_temp.ok('Td', 'boa+ruim com confirmar=true: ok=false, nada gravado; só a boa: 1 importação, 05/10/2026 14:30 SP, 1.234→1234, R$ 1.234,56→123456; origem_sistema/id_externo da planilha ignorados');
end
$td2$;

-- Td3. Duplicata contra o banco e dentro do lote: prévia lista; confirmar recusa (nada grava); só p_aceitar_duplicadas grava.
select pg_temp.como_admin();
do $td3$
declare
  r jsonb;
  v_boa jsonb := jsonb_build_object('data', '05/10/2026', 'hora', '14:30', 'projeto', (select sigla from pg_temp._z_ref),
                   'canal', 'E-mail', 'ferramenta', 'activecampaign', 'copy_texto', 'Oi', 'publico_lista', 'Lista importada',
                   'tamanho_lista', '1.234', 'disparado_por', 'Ensaio');
  v_lote jsonb := jsonb_build_array(v_boa || '{"publico_lista":"Lista lote"}', v_boa || '{"publico_lista":"Outra lista"}',
                                    v_boa || '{"publico_lista":"Lista lote"}');
begin
  r := public.mkt_msg_importar(jsonb_build_array(v_boa), false, 'ensaio.csv');
  if r -> 'duplicadas_banco' <> '[1]'::jsonb or not (r ->> 'ok')::boolean then
    raise exception 'Td3 FALHOU: prévia não listou duplicata do banco: %', r;
  end if;
  r := public.mkt_msg_importar(jsonb_build_array(v_boa), true, 'ensaio.csv');
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Possível duplicata%' then
    raise exception 'Td3 FALHOU: confirmou duplicata do banco: %', r;
  end if;
  insert into pg_temp._z_out (passo, linha) values ('Td3.recusa', r::text);
  r := public.mkt_msg_importar(v_lote, false, 'lote.csv');
  if r -> 'duplicadas_lote' <> '[1, 3]'::jsonb or r -> 'duplicadas_banco' <> '[]'::jsonb then
    raise exception 'Td3 FALHOU: prévia não listou duplicata no lote: %', r;
  end if;
  r := public.mkt_msg_importar(v_lote, true, 'lote.csv');
  if (r ->> 'ok')::boolean then raise exception 'Td3 FALHOU: confirmou lote com linha repetida: %', r; end if;
  r := public.mkt_msg_importar(v_lote, true, 'lote.csv', true);
  if not (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 3 then
    raise exception 'Td3 FALHOU: com p_aceitar_duplicadas não gravou: %', r;
  end if;
end
$td3$;
reset role;
do $td4$
begin
  if (select count(*) from mkt_mensageria.importacoes) <> 2
     or (select count(*) from mkt_mensageria.disparos where origem = 'planilha') <> 4
     or (select count(*) from mkt_mensageria.disparos where publico_lista = 'Lista importada') <> 1 then
    raise exception 'Td3 FALHOU: contagens depois das duplicatas';
  end if;
  perform pg_temp.ok('Td3', 'duplicata do banco ([1]) e do lote ([1,3]) listadas na prévia; confirmar recusa sem gravar; com p_aceitar_duplicadas grava (2 importações, 4 de planilha)');
end
$td4$;

-- Te. Histórico: alterar e arquivar gravam; arquivado some da lista e não se edita; DELETE recusado
select pg_temp.como_admin();
do $te$
declare
  r jsonb;
  v_a bigint := (select id from pg_temp._z_ids where nome = 'A');
  v_p jsonb := jsonb_build_object('enviado_em', to_jsonb(now()), 'projeto', (select sigla from pg_temp._z_ref),
                 'ferramenta_id', (select activecampaign from pg_temp._z_ref), 'copy_texto', 'Copy do ensaio',
                 'publico_lista', 'Lista do ensaio', 'publico_origem', 'Origem editada', 'tamanho_lista', 100,
                 'disparado_por', 'Ensaio', 'canal', 'email', 'entregues', 0, 'lidas', 0, 'cliques', 0, 'falhas', 0,
                 'custo_centavos', 500);
begin
  r := public.mkt_msg_disparo_salvar(v_p || jsonb_build_object('id', v_a));
  if not (r ->> 'ok')::boolean then raise exception 'Te FALHOU: editar: %', r; end if;
  r := public.mkt_msg_disparo_arquivar(v_a, '  ');
  if (r ->> 'ok')::boolean then raise exception 'Te FALHOU: arquivou sem motivo'; end if;
  r := public.mkt_msg_disparo_arquivar(v_a, 'Lançado em duplicidade');
  if not (r ->> 'ok')::boolean then raise exception 'Te FALHOU: arquivar: %', r; end if;
  r := public.mkt_msg_disparo_arquivar(v_a, 'De novo');
  if r ->> 'msg' <> 'Disparo já arquivado.' then raise exception 'Te FALHOU: arquivar 2x: %', r; end if;
  r := public.mkt_msg_disparo_salvar(v_p || jsonb_build_object('id', v_a));
  if r ->> 'msg' <> 'Disparo arquivado: não pode ser editado.' then raise exception 'Te FALHOU: editou arquivado: %', r; end if;
  r := public.mkt_msg_historico('disparos', v_a::text);
  if (select array_agg(x ->> 'acao' order by o) from jsonb_array_elements(r -> 'itens') with ordinality t(x, o))
       <> array['arquivar', 'alterar', 'inserir']
     or (r -> 'itens' -> 0 ->> 'por')::uuid is distinct from (select id from pg_temp._z_admin)
     or r -> 'itens' -> 1 -> 'antes' ->> 'publico_origem' is not null
     or r -> 'itens' -> 1 -> 'depois' ->> 'publico_origem' <> 'Origem editada' then
    raise exception 'Te FALHOU: histórico: %', r;
  end if;
  r := public.mkt_msg_disparos_listar((now() at time zone 'America/Sao_Paulo')::date - 1, (now() at time zone 'America/Sao_Paulo')::date);
  if exists (select 1 from jsonb_array_elements(r -> 'linhas') x where (x ->> 'id')::bigint = v_a) then
    raise exception 'Te FALHOU: arquivado ainda aparece na lista';
  end if;
end
$te$;
reset role;
do $te2$
begin
  begin
    delete from mkt_mensageria.disparos where id = (select id from pg_temp._z_ids where nome = 'B');
    raise exception 'Te FALHOU: DELETE aceito';
  exception when insufficient_privilege then
    null;
  end;
  perform pg_temp.ok('Te', 'histórico = arquivar, alterar, inserir (por = admin; antes/depois certos); sem motivo recusa; arquivado some da lista e não se edita; DELETE recusado (42501)');
end
$te2$;

-- Tg. Período e filtros inválidos; Th. consumo_hoje vem do log; Ti. lançar retorno; Tj. ferramentas
select pg_temp.como_admin();
do $tg$
declare
  r jsonb;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_n bigint;
  v_base jsonb;
  v_arq bigint;
  v_b bigint := (select id from pg_temp._z_ids where nome = 'B');
begin
  if (public.mkt_msg_disparos_listar(null, v_hoje) ->> 'ok')::boolean
     or public.mkt_msg_disparos_listar(v_hoje - 366, v_hoje) ->> 'msg' <> 'Período máximo: 366 dias.'
     or not (public.mkt_msg_disparos_listar(v_hoje - 365, v_hoje) ->> 'ok')::boolean
     or (public.mkt_msg_disparos_listar(v_hoje, v_hoje - 1) ->> 'ok')::boolean
     or (public.mkt_msg_disparos_listar(v_hoje - 1, v_hoje, 'ZZ99') ->> 'ok')::boolean
     or (public.mkt_msg_disparos_listar(v_hoje - 1, v_hoje, null, 'fax') ->> 'ok')::boolean then
    raise exception 'Tg FALHOU: validação de período/filtro';
  end if;
  perform pg_temp.ok('Tg', 'período nulo, invertido, 367 dias, projeto e canal inexistentes = ok:false; 366 dias = ok');

  r := public.mkt_msg_numero_salvar(jsonb_build_object('numero', '+55 (11) 90000-0001', 'responsavel', 'Ensaio',
         'finalidade', 'mensageria', 'ferramenta_id', (select sendflow from pg_temp._z_ref), 'capacidade_dia', 50, 'status', 'ativo'));
  if not (r ->> 'ok')::boolean then raise exception 'Th FALHOU: cadastrar número: %', r; end if;
  v_n := (r ->> 'id')::bigint;
  if (public.mkt_msg_numero_salvar(jsonb_build_object('numero', '+5511900000001', 'responsavel', 'X', 'finalidade', 'mensageria', 'status', 'ativo')) ->> 'ok')::boolean
     or (public.mkt_msg_numero_salvar(jsonb_build_object('numero', '11900000001', 'responsavel', 'X', 'finalidade', 'mensageria', 'status', 'ativo')) ->> 'ok')::boolean then
    raise exception 'Th FALHOU: aceitou número duplicado ou sem +país';
  end if;
  v_base := jsonb_build_object('projeto', (select sigla from pg_temp._z_ref), 'canal', 'whatsapp_api', 'tipo', 'marketing',
              'ferramenta_id', (select sendflow from pg_temp._z_ref), 'numero_id', v_n, 'copy_link', 'https://exemplo.invalid/x',
              'publico_lista', 'Lista consumo', 'disparado_por', 'Ensaio');
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', to_jsonb(now()), 'tamanho_lista', 40));
  if not (r ->> 'ok')::boolean then raise exception 'Th FALHOU: disparo de hoje: %', r; end if;
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', to_jsonb(now()), 'tamanho_lista', 1000));
  v_arq := (r ->> 'id')::bigint;
  perform public.mkt_msg_disparo_arquivar(v_arq, 'Teste de arquivado fora do consumo');
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', to_jsonb(now() - interval '1 day'), 'tamanho_lista', 7));
  if not (r ->> 'ok')::boolean then raise exception 'Th FALHOU: disparo de ontem: %', r; end if;
  r := public.mkt_msg_numeros_listar();
  if (select (x ->> 'consumo_hoje')::int from jsonb_array_elements(r -> 'numeros') x where (x ->> 'id')::bigint = v_n) <> 40
     or (select (x ->> 'acima_da_capacidade')::boolean from jsonb_array_elements(r -> 'numeros') x where (x ->> 'id')::bigint = v_n)
     or (select x ->> 'numero' from jsonb_array_elements(r -> 'numeros') x where (x ->> 'id')::bigint = v_n) <> '+5511900000001' then
    raise exception 'Th FALHOU: consumo_hoje: %', r;
  end if;
  perform pg_temp.ok('Th', 'consumo_hoje = 40 (hoje 40 + arquivado 1000 ignorado + ontem 7 ignorado); número normalizado para +5511900000001; duplicado e sem +país recusados');

  r := public.mkt_msg_disparo_lancar_retorno(v_b, 100, 50, 10, 0, 990);
  if not (r ->> 'ok')::boolean or r -> 'pendencias' <> '[]'::jsonb then raise exception 'Ti FALHOU: lançar: %', r; end if;
  r := public.mkt_msg_disparo_lancar_retorno(v_b, 10, 20, null, null, null);
  if (r ->> 'ok')::boolean then raise exception 'Ti FALHOU: aceitou lidas > entregues'; end if;
  r := public.mkt_msg_disparo_lancar_retorno(v_b, 90, null, null, 20, null);
  if (r ->> 'ok')::boolean then raise exception 'Ti FALHOU: aceitou entregues+falhas > tamanho'; end if;
  perform pg_temp.ok('Ti', 'lançar retorno ok (sem pendência); lidas>entregues e entregues+falhas>tamanho recusados');

  r := public.mkt_msg_ferramentas_listar();
  if jsonb_array_length(r) <> 13 or exists (select 1 from jsonb_array_elements(r) x where x ->> 'custo_mensal_centavos' is not null) then
    raise exception 'Tj FALHOU: seed de ferramentas: %', r;
  end if;
  if (public.mkt_msg_ferramenta_salvar('{"nome":"sendflow","api":"sim"}') ->> 'ok')::boolean then
    raise exception 'Tj FALHOU: aceitou ferramenta duplicada sem diferenciar maiúscula';
  end if;
  r := public.mkt_msg_ferramenta_salvar(jsonb_build_object('id', (select sendflow from pg_temp._z_ref), 'nome', 'SendFlow', 'api', 'sim',
         'custo_mensal_centavos', 29900, 'responsavel', 'Ensaio'));
  if not (r ->> 'ok')::boolean
     or (public.mkt_msg_historico('ferramentas', (select sendflow from pg_temp._z_ref)::text) -> 'itens' -> 0 ->> 'acao') <> 'alterar' then
    raise exception 'Tj FALHOU: editar ferramenta/histórico: %', r;
  end if;
  perform pg_temp.ok('Tj', '13 ferramentas, custos nulos; nome único sem diferenciar maiúscula; edição vai para o histórico');
end
$tg$;
reset role;

-- Tk. origem_sistema/id_externo: a tela não grava nem altera; só origem 'api' tem chave externa; procedência imutável
select pg_temp.como_admin();
do $tk$
declare
  r jsonb;
begin
  r := public.mkt_msg_disparo_salvar(jsonb_build_object('enviado_em', to_jsonb(now()), 'projeto', (select sigla from pg_temp._z_ref),
         'canal', 'sms', 'ferramenta_id', (select activecampaign from pg_temp._z_ref), 'copy_texto', 'Copy Tk',
         'publico_lista', 'Lista Tk', 'tamanho_lista', 10, 'disparado_por', 'Ensaio',
         'origem_sistema', 'sendflow', 'id_externo', 'tk-1'));
  if not (r ->> 'ok')::boolean then raise exception 'Tk FALHOU: salvar: %', r; end if;
  insert into pg_temp._z_ids values ('K', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(jsonb_build_object('id', (r ->> 'id')::bigint, 'enviado_em', to_jsonb(now()),
         'projeto', (select sigla from pg_temp._z_ref), 'canal', 'sms', 'ferramenta_id', (select activecampaign from pg_temp._z_ref),
         'copy_texto', 'Copy Tk', 'publico_lista', 'Lista Tk', 'tamanho_lista', 10, 'disparado_por', 'Ensaio',
         'origem_sistema', 'outro', 'id_externo', 'tk-2'));
  if not (r ->> 'ok')::boolean then raise exception 'Tk FALHOU: editar: %', r; end if;
end
$tk$;
reset role;
do $tk2$
declare
  v_api bigint;
begin
  if not exists (select 1 from mkt_mensageria.disparos d join pg_temp._z_ids i on i.id = d.id and i.nome = 'K'
                  where d.origem = 'manual' and d.origem_sistema is null and d.id_externo is null) then
    raise exception 'Tk FALHOU: a tela gravou origem_sistema/id_externo';
  end if;
  perform pg_temp.espera_check(format(
    'insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, copy_texto, publico_lista, tamanho_lista, '
    || 'disparado_por, origem, origem_sistema, id_externo) values (now(), %s, ''sms'', %s, ''x'', ''L'', 1, ''E'', ''manual'', ''sendflow'', ''tk-3'')',
    (select projeto_id from pg_temp._z_ref), (select sendflow from pg_temp._z_ref)), 'disparos_externo_so_api');
  insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, copy_texto, publico_lista, tamanho_lista,
         disparado_por, origem, origem_sistema, id_externo)
  values (now(), (select projeto_id from pg_temp._z_ref), 'sms', (select sendflow from pg_temp._z_ref), 'x', 'L', 1, 'E',
          'api', 'sendflow', 'tk-4')
  returning id into v_api;
  begin
    update mkt_mensageria.disparos set id_externo = 'tk-5' where id = v_api;
    raise exception 'Tk FALHOU: id_externo alterado';
  exception when insufficient_privilege then null;
  end;
  begin
    update mkt_mensageria.disparos set origem = 'manual', origem_sistema = null, id_externo = null where id = v_api;
    raise exception 'Tk FALHOU: origem alterada';
  exception when insufficient_privilege then null;
  end;
  begin
    update mkt_mensageria.disparos set importacao_id = null where origem = 'planilha';
    raise exception 'Tk FALHOU: importacao_id alterado';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.ok('Tk', 'tela ignora origem_sistema/id_externo (criar e editar); id_externo fora de origem api = 23514; origem/origem_sistema/id_externo/importacao_id imutáveis (42501)');
end
$tk2$;

-- Tm. As 10 funções da área têm a guarda coalesce(mkt.pode_ver('mkt_mensageria'), false); a de LGPD, gp_is_admin
do $tm$
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%'
        and p.proname <> 'mkt_msg_anonimizar_disparo'
        and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in p.prosrc) > 0) <> 10
     or position('if not coalesce(public.gp_is_admin(), false) then raise exception' in
                 (select p.prosrc from pg_proc p where p.oid = 'public.mkt_msg_anonimizar_disparo(bigint,text)'::regprocedure)) = 0 then
    raise exception 'Tm FALHOU: guarda sem coalesce';
  end if;
  perform pg_temp.ok('Tm', '10 funções com coalesce(mkt.pode_ver(...), false); anonimizar com coalesce(gp_is_admin(), false)');
end
$tm$;

-- Tn. Ferramenta desativada e número arquivado: disparo novo/editado e planilha recusam, com mensagem
select pg_temp.como_admin();
do $tn$
declare
  r jsonb;
  v_clint bigint := (select (x ->> 'id')::bigint from jsonb_array_elements(public.mkt_msg_ferramentas_listar()) x where x ->> 'nome' = 'Clint');
  v_num bigint;
  v_base jsonb := jsonb_build_object('enviado_em', to_jsonb(now()), 'projeto', (select sigla from pg_temp._z_ref), 'canal', 'sms',
                    'copy_texto', 'Copy Tn', 'publico_lista', 'Lista Tn', 'tamanho_lista', 10, 'disparado_por', 'Ensaio');
begin
  r := public.mkt_msg_ferramenta_salvar(jsonb_build_object('id', v_clint, 'nome', 'Clint', 'api', 'nao', 'ativa', false));
  if not (r ->> 'ok')::boolean then raise exception 'Tn FALHOU: desativar: %', r; end if;
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('ferramenta_id', v_clint));
  if (r ->> 'ok')::boolean or r ->> 'msg' <> 'Ferramenta Clint está desativada: reative em Ferramentas ou escolha outra.' then
    raise exception 'Tn FALHOU: aceitou ferramenta desativada: %', r;
  end if;
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('id', (select id from pg_temp._z_ids where nome = 'K'), 'ferramenta_id', v_clint));
  if (r ->> 'ok')::boolean then raise exception 'Tn FALHOU: edição aceitou ferramenta desativada: %', r; end if;
  r := public.mkt_msg_importar(jsonb_build_array(jsonb_build_object('data', '05/10/2026', 'hora', '10:00',
         'projeto', (select sigla from pg_temp._z_ref), 'canal', 'SMS', 'ferramenta', 'clint', 'copy_texto', 'x',
         'publico_lista', 'Lista Tn', 'tamanho_lista', '10', 'disparado_por', 'Ensaio')), false, null);
  if (r -> 'erros' -> 0 ->> 'campo') <> 'ferramenta' or (r -> 'erros' -> 0 ->> 'msg') not like 'Ferramenta Clint está desativada%' then
    raise exception 'Tn FALHOU: planilha aceitou ferramenta desativada: %', r;
  end if;
  r := public.mkt_msg_numero_salvar(jsonb_build_object('numero', '+5511900000099', 'responsavel', 'Ensaio', 'finalidade', 'suporte',
         'status', 'disponivel', 'arquivado', true));
  v_num := (r ->> 'id')::bigint;
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('ferramenta_id', (select sendflow from pg_temp._z_ref), 'numero_id', v_num));
  if (r ->> 'ok')::boolean or r ->> 'msg' <> 'Número +5511900000099 está arquivado: desarquive em Números ou escolha outro.' then
    raise exception 'Tn FALHOU: aceitou número arquivado: %', r;
  end if;
  perform pg_temp.ok('Tn', 'ferramenta desativada recusada (novo, edição, planilha) e número arquivado recusado, com mensagem');
end
$tn$;
reset role;

-- To. LGPD: anonimizar limpa o disparo e o histórico dele, registra 'anonimizar'; flag desligada ao sair
select pg_temp.como_admin();
do $to$
declare
  r jsonb;
  v_b bigint := (select id from pg_temp._z_ids where nome = 'B');
begin
  r := public.mkt_msg_anonimizar_disparo(v_b, ' ');
  if (r ->> 'ok')::boolean then raise exception 'To FALHOU: anonimizou sem motivo'; end if;
  r := public.mkt_msg_anonimizar_disparo(v_b, 'Pedido do titular (LGPD)');
  if not (r ->> 'ok')::boolean or (r ->> 'historico_limpo')::int < 2 then raise exception 'To FALHOU: anonimizar: %', r; end if;
  r := public.mkt_msg_historico('disparos', v_b::text);
  if r -> 'itens' -> 0 ->> 'acao' <> 'anonimizar' or r -> 'itens' -> 0 -> 'depois' ->> 'motivo' <> 'Pedido do titular (LGPD)'
     or (r -> 'itens' -> 0 ->> 'por')::uuid is distinct from (select id from pg_temp._z_admin) then
    raise exception 'To FALHOU: histórico da anonimização: %', r;
  end if;
end
$to$;
reset role;
do $to2$
declare
  v_b bigint := (select id from pg_temp._z_ids where nome = 'B');
begin
  if not exists (select 1 from mkt_mensageria.disparos where id = v_b and copy_texto = '[anonimizado]'
                    and publico_lista = '[anonimizado]' and publico_origem is null)
     or exists (select 1 from mkt_mensageria.historico h where h.tabela = 'disparos' and h.registro_id = v_b::text
                  and (coalesce(h.antes::text, '') || coalesce(h.depois::text, '')) ~ '(Copy do ensaio|Lista do ensaio)')
     or not exists (select 1 from mkt_mensageria.disparos where copy_texto = 'Copy do ensaio')
     or coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    raise exception 'To FALHOU: dado pessoal sobrou no disparo/histórico, mexeu em outro registro ou a flag ficou ligada';
  end if;
  perform pg_temp.ok('To', 'copy/lista do disparo e de todas as linhas do histórico dele viraram [anonimizado]; outros disparos intactos; linha anonimizar com motivo; flag desligada');
end
$to2$;

-- Tl. DELETE/TRUNCATE nas 5 tabelas e UPDATE em historico/importacoes: 42501 (mesmo com a flag ligada à mão, só antes/depois)
do $tl$
declare
  t text;
  c text;
begin
  foreach t in array array['ferramentas', 'numeros', 'disparos', 'importacoes', 'historico'] loop
    foreach c in array array['truncate mkt_mensageria.%I cascade', 'delete from mkt_mensageria.%I'] loop
      begin
        execute format(c, t);
        raise exception 'Tl FALHOU: % aceito', format(c, t);
      exception when insufficient_privilege then null;
      end;
    end loop;
  end loop;
  foreach c in array array['update mkt_mensageria.historico set acao = ''alterar''',
                           'update mkt_mensageria.historico set antes = null',
                           'update mkt_mensageria.importacoes set arquivo = ''x'''] loop
    begin
      execute c;
      raise exception 'Tl FALHOU: % aceito', c;
    exception when insufficient_privilege then null;
    end;
  end loop;
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  begin
    update mkt_mensageria.historico set acao = 'alterar';
    raise exception 'Tl FALHOU: flag ligada liberou mudar a ação';
  exception when insufficient_privilege then null;
  end;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  perform pg_temp.ok('Tl', 'TRUNCATE e DELETE nas 5 tabelas, UPDATE em historico/importacoes = 42501; flag ligada à mão não libera mudar a ação');
end
$tl$;

-- Fim do bloco 1: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005n BLOCO 1 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.\n'
    || (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 1

-- ▶ BLOCO 2 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005n_mkt_mensageria.sql) ═══
-- 20261005n: Marketing > Mensageria (etapa 2: o banco da área)
--
-- O QUE FAZ
--   Cria o schema mkt_mensageria: o LOG CENTRAL DE DISPAROS (todo envio de WhatsApp API, e-mail, SMS, ligação e grupo,
--   de qualquer ferramenta), o CONTROLE DE NÚMEROS (quem responde por cada número, para quê, quanto aguenta por dia) e o
--   cadastro de FERRAMENTAS. Decisões de 05/10/2026:
--     - Retorno e custo não lançados ficam NULOS, nunca 0. Sem default nessas colunas. 0 é "medido e deu zero".
--     - Consumo do dia de cada número vem do log (soma de tamanho_lista dos disparos de hoje). Ninguém digita.
--     - Nada se apaga: disparo errado é ARQUIVADO com motivo; triggers recusam DELETE/TRUNCATE (e UPDATE em historico e
--       importacoes). Toda mudança vai para o histórico. Única exceção: anonimização LGPD (mkt_msg_anonimizar_disparo).
--     - Planilha recusa possível duplicata (no log ou no próprio lote) salvo aceite explícito; id_externo só via API.
--     - Projeto = mkt.projetos (20261005m), pela sigla. cs.disparos e cs.canais_disparo são de OUTRO sistema: não toca.
--     - Quem vê: o mesmo de todo o Marketing, mkt.pode_ver('mkt_mensageria') (hoje admin/dev). Função NÃO alterada aqui.
--
--   Padrão da 20261005m: tabelas fechadas (RLS ligada, sem policy, revoke de public/anon/authenticated em schema,
--   tabelas e sequências), todo acesso por função public.mkt_msg_* SECURITY DEFINER, search_path '', guarda no corpo
--   com 42501. Cada função tem o revoke/grant logo abaixo do create (função nova nasce executável por PUBLIC).
--
-- O QUE CRIA
--   mkt_mensageria.ferramentas (13 de seed), numeros, importacoes, disparos, historico
--   mkt_mensageria.* internas: inteiro, inteiro_br, centavos_br, data_hora_br, instante, pendencias, disparo_validar,
--                              importar_linha, trg_carimbo, trg_numero_status, trg_historico, trg_bloqueio, trg_disparo_procedencia
--   public.mkt_msg_*  disparos_listar, disparo_salvar, disparo_arquivar, disparo_lancar_retorno, importar,
--                     numeros_listar, numero_salvar, ferramentas_listar, ferramenta_salvar, historico,
--                     anonimizar_disparo (LGPD, só admin)
--   Projetos: a tela usa public.mkt_projetos_listar() (20261005m). Não há mkt_msg_projetos_listar.
--
-- AS 5 PERGUNTAS
--   escala: estimativa de dezenas a centenas de disparos/dia. listar exige período (máx. 366 dias) e devolve no máximo
--     500 linhas; os totais varrem só o período, pelo índice. numeros_listar: um lookup por número no índice
--     (numero_id, enviado_em), só o dia de hoje. importar: no máximo 2.000 linhas, validação em uma query.
--   índice: disparos (enviado_em desc), (projeto_id, enviado_em desc), (numero_id, enviado_em); historico
--     (tabela, registro_id, em desc). Prova: 20261005n_ensaio.sql bloco 2 (explain analyze com 10.000 disparos).
--   frequência: a tela lê ao abrir e ao trocar filtro; escrita manual (pessoa) ou importação de planilha.
--   repetição: uma chamada por tela/filtro; totais e linhas na mesma query (CTE materializada, uma varredura).
--   reversão: bloco REVERSÃO no fim (o schema é novo e isolado; drop dele não afeta a 20261005m).
--
-- ENSAIO: 20261005n_ensaio.sql (3 blocos, cada um begin … aborto). Contrato e medições: 20261005n.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regnamespace('mkt_mensageria') is not null then
    raise exception '20261005n: schema mkt_mensageria já existe (migration já aplicada?)';
  end if;
  if to_regclass('mkt.projetos') is null or to_regprocedure('mkt.pode_ver(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null then
    raise exception '20261005n: base compartilhada ausente (mkt.projetos, mkt.pode_ver, mkt.sem_acento): aplicar 20261005m antes';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception '20261005n: auth.uid() ausente';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') then
    raise exception '20261005n: já existem funções public.mkt_msg_*';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'perfis' and column_name in ('id', 'nome')) <> 2 then
    raise exception '20261005n: public.perfis (id, nome) ausente';
  end if;
end
$guarda$;

-- ─── 1. Schema ───────────────────────────────────────────────────────────────────────────────────────────────────────
create schema mkt_mensageria;
revoke all on schema mkt_mensageria from public, anon, authenticated;
comment on schema mkt_mensageria is
  'Marketing > Mensageria: log central de disparos, controle de números e ferramentas. Retorno/custo nulo = não '
  'lançado (nunca 0). Nada se apaga (arquivar). Fechado: acesso só pelas funções public.mkt_msg_*. 20261005n.';

-- ─── 2. Funções auxiliares (internas: revoke de todos logo após cada create) ─────────────────────────────────────────
-- Inteiro ≥ 0 vindo da tela/JSON ("1234"). Vazio = nulo. Fora do formato (negativo, decimal, texto) = -1.
create function mkt_mensageria.inteiro(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro(text) from public, anon, authenticated;

-- Inteiro ≥ 0 vindo de planilha brasileira ("1234" ou "1.234"). Vazio = nulo. Fora do formato = -1.
create function mkt_mensageria.inteiro_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              when btrim(p) ~ '^[0-9]{1,3}(\.[0-9]{3}){1,2}$' then replace(btrim(p), '.', '')::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro_br(text) from public, anon, authenticated;

-- Reais de planilha ("1.234,56", "R$ 12,5", "990") → centavos. Vazio = nulo. Fora do formato = -1. Teto R$ 999.999,99.
create function mkt_mensageria.centavos_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when v = '' then null
              when v ~ '^([0-9]{1,3}(\.[0-9]{3})?|[0-9]{1,6})(,[0-9]{1,2})?$' then
                replace(split_part(v, ',', 1), '.', '')::bigint * 100
                + coalesce(rpad(nullif(split_part(v, ',', 2), ''), 2, '0')::bigint, 0)
              else -1 end
    from (select regexp_replace(btrim(coalesce(p, '')), '^R\$\s*', '') as v) t;
$$;
revoke all on function mkt_mensageria.centavos_br(text) from public, anon, authenticated;

-- "dd/mm/aaaa" + "hh:mm" no horário de São Paulo. Nulo se faltar ou não existir (31/02, 25:00).
create function mkt_mensageria.data_hora_br(p_data text, p_hora text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v_d text[] := regexp_match(btrim(coalesce(p_data, '')), '^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})$');
  v_h text[] := regexp_match(btrim(coalesce(p_hora, '')), '^([0-9]{1,2}):([0-9]{2})$');
begin
  if v_d is null or v_h is null then return null; end if;
  return make_timestamptz(v_d[3]::int, v_d[2]::int, v_d[1]::int, v_h[1]::int, v_h[2]::int, 0, 'America/Sao_Paulo');
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.data_hora_br(text, text) from public, anon, authenticated;

-- Instante vindo da tela: "2026-10-05T14:30" (sem fuso = São Paulo) ou ISO com fuso ("…Z", "…-03:00"). Nulo se inválido.
create function mkt_mensageria.instante(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v text := btrim(coalesce(p, ''));
begin
  if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?$' then
    return null;
  end if;
  if v ~ '(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then return v::timestamptz; end if;
  return v::timestamp at time zone 'America/Sao_Paulo';
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.instante(text) from public, anon, authenticated;

-- Pendências de um disparo (a tela mostra o selo; os totais contam). Mesma regra em todo lugar.
--   sem_custo: custo não lançado · sem_retorno: entregues ou lidas não lançadas · conferir_zero_leitura: 0 lidas com custo
create function mkt_mensageria.pendencias(p_entregues integer, p_lidas integer, p_custo integer) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null then 'sem_custo' end,
    case when p_entregues is null or p_lidas is null then 'sem_retorno' end,
    case when p_lidas = 0 and p_custo > 0 then 'conferir_zero_leitura' end], null);
$$;
revoke all on function mkt_mensageria.pendencias(integer, integer, integer) from public, anon, authenticated;

-- ─── 3. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt_mensageria.ferramentas (
  id                     bigint generated always as identity primary key,
  nome                   text not null check (nome = btrim(nome) and length(nome) between 1 and 60),
  api                    text not null check (api in ('sim', 'futura', 'nao')),
  custo_mensal_centavos  integer check (custo_mensal_centavos is null or custo_mensal_centavos >= 0),   -- nulo = não lançado
  responsavel            text check (responsavel is null or length(btrim(responsavel)) between 1 and 80),
  ativa                  boolean not null default true,
  obs                    text check (obs is null or length(obs) <= 1000),
  criado_em              timestamptz not null default now(),
  criado_por             uuid references public.perfis(id) on delete set null,
  atualizado_em          timestamptz not null default now(),
  atualizado_por         uuid references public.perfis(id) on delete set null
);
-- Único sem diferenciar maiúscula: a planilha acha a ferramenta pelo nome, sem diferenciar maiúscula.
create unique index ferramentas_nome_unico on mkt_mensageria.ferramentas (lower(nome));
comment on table mkt_mensageria.ferramentas is 'Ferramentas de disparo e apoio. api: sim (integra), futura (vai integrar), nao (registro manual). Custo mensal nulo = não lançado.';

create table mkt_mensageria.numeros (
  id              bigint generated always as identity primary key,
  numero          text not null unique check (numero ~ '^\+[1-9][0-9]{7,14}$'),   -- E.164
  projeto_id      bigint references mkt.projetos(id) on delete restrict,
  frente          text check (frente is null or length(btrim(frente)) between 1 and 60),
  responsavel     text not null check (length(btrim(responsavel)) between 1 and 80),
  finalidade      text not null check (finalidade in ('mensageria', 'comercial', 'financeiro', 'suporte')),
  ferramenta_id   bigint references mkt_mensageria.ferramentas(id) on delete restrict,
  capacidade_dia  smallint check (capacidade_dia is null or capacidade_dia between 1 and 1000),   -- nulo = não definida
  status          text not null check (status in ('ativo', 'aquecendo', 'restrito', 'disponivel')),
  status_desde    timestamptz not null default now(),     -- trigger carimba quando o status muda
  arquivado_em    timestamptz,
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null
);
comment on table mkt_mensageria.numeros is 'Números de WhatsApp/SMS. consumo do dia NÃO é coluna: vem do log (mkt_msg_numeros_listar).';

create table mkt_mensageria.importacoes (
  id          bigint generated always as identity primary key,
  arquivo     text check (arquivo is null or length(arquivo) <= 255),
  linhas      integer not null check (linhas between 1 and 2000),
  criado_por  uuid references public.perfis(id) on delete set null,
  criado_em   timestamptz not null default now()
);
comment on table mkt_mensageria.importacoes is 'Cada importação de planilha confirmada (tudo ou nada). disparos.importacao_id aponta para cá.';

create table mkt_mensageria.disparos (
  id                bigint generated always as identity primary key,
  enviado_em        timestamptz not null,
  projeto_id        bigint not null references mkt.projetos(id) on delete restrict,
  canal             text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  ferramenta_id     bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  numero_id         bigint references mkt_mensageria.numeros(id) on delete restrict,
  tipo              text check (tipo is null or tipo in ('utility', 'marketing')),
  copy_texto        text check (copy_texto is null or length(copy_texto) <= 4000),
  copy_link         text check (copy_link is null or length(copy_link) <= 2000),
  publico_lista     text not null check (length(btrim(publico_lista)) between 1 and 200),
  publico_origem    text check (publico_origem is null or length(publico_origem) <= 200),
  tamanho_lista     integer not null check (tamanho_lista >= 0),
  -- Retorno e custo: SEM DEFAULT. Nulo = não lançado; 0 = lançado e deu zero.
  entregues         integer check (entregues is null or entregues >= 0),
  lidas             integer check (lidas is null or lidas >= 0),
  cliques           integer check (cliques is null or cliques >= 0),
  falhas            integer check (falhas is null or falhas >= 0),
  custo_centavos    integer check (custo_centavos is null or custo_centavos >= 0),
  disparado_por     text not null check (length(btrim(disparado_por)) between 1 and 80),
  retorno_em        timestamptz,
  origem            text not null default 'manual' check (origem in ('manual', 'planilha', 'api')),
  origem_sistema    text check (origem_sistema is null or length(btrim(origem_sistema)) between 1 and 60),
  id_externo        text check (id_externo is null or length(btrim(id_externo)) between 1 and 200),
  importacao_id     bigint references mkt_mensageria.importacoes(id) on delete restrict,
  arquivado_em      timestamptz,
  arquivado_motivo  text check (arquivado_motivo is null or length(btrim(arquivado_motivo)) between 3 and 500),
  criado_em         timestamptz not null default now(),
  criado_por        uuid references public.perfis(id) on delete set null,
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid references public.perfis(id) on delete set null,
  constraint disparos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  constraint disparos_copy_obrigatoria check (nullif(btrim(copy_texto), '') is not null or nullif(btrim(copy_link), '') is not null),
  constraint disparos_entregues_falhas check (coalesce(entregues, 0)::bigint + coalesce(falhas, 0) <= tamanho_lista),
  constraint disparos_lidas_entregues check (lidas is null or entregues is null or lidas <= entregues),
  constraint disparos_cliques_entregues check (cliques is null or entregues is null or cliques <= entregues),
  constraint disparos_externo_com_sistema check (id_externo is null or origem_sistema is not null),
  -- Chave externa só para integração (origem 'api'). Tela (manual) e planilha não gravam: não colidem com a da API.
  constraint disparos_externo_so_api check (origem = 'api' or (origem_sistema is null and id_externo is null)),
  constraint disparos_importacao_planilha check (importacao_id is null or origem = 'planilha'),
  constraint disparos_arquivo_com_motivo check ((arquivado_em is null) = (arquivado_motivo is null))
);
create unique index disparos_externo_unico on mkt_mensageria.disparos (origem_sistema, id_externo) where id_externo is not null;
create index disparos_enviado_idx on mkt_mensageria.disparos (enviado_em desc);
create index disparos_projeto_enviado_idx on mkt_mensageria.disparos (projeto_id, enviado_em desc);
create index disparos_numero_enviado_idx on mkt_mensageria.disparos (numero_id, enviado_em);
comment on table mkt_mensageria.disparos is 'Log central de disparos (todo canal, toda ferramenta). Retorno/custo nulo = não lançado. Arquivar, nunca apagar.';
comment on column mkt_mensageria.disparos.tipo is 'Categoria da mensagem na API oficial do WhatsApp (utility, marketing). Só existe em canal whatsapp_api.';
comment on column mkt_mensageria.disparos.retorno_em is 'Quando o retorno (entregues, lidas, cliques, falhas, custo) foi lançado pela última vez.';
comment on column mkt_mensageria.disparos.id_externo is 'Id no sistema de origem. Só origem api (integração futura); imutável depois de gravado. Único por origem_sistema: reenvio não duplica.';

create table mkt_mensageria.historico (
  id           bigint generated always as identity primary key,
  tabela       text not null check (tabela in ('disparos', 'numeros', 'ferramentas')),
  registro_id  text not null,
  acao         text not null check (acao in ('inserir', 'alterar', 'arquivar', 'anonimizar')),
  antes        jsonb,
  depois       jsonb,
  por          uuid,                                   -- auth.uid(); sem FK: o histórico sobrevive ao perfil
  em           timestamptz not null default now()
);
create index historico_registro_idx on mkt_mensageria.historico (tabela, registro_id, em desc);
comment on table mkt_mensageria.historico is 'Toda inserção/alteração/arquivamento em disparos, numeros e ferramentas (trigger). Linha inteira antes/depois.';

alter table mkt_mensageria.ferramentas enable row level security;
alter table mkt_mensageria.numeros enable row level security;
alter table mkt_mensageria.importacoes enable row level security;
alter table mkt_mensageria.disparos enable row level security;
alter table mkt_mensageria.historico enable row level security;
revoke all on mkt_mensageria.ferramentas, mkt_mensageria.numeros, mkt_mensageria.importacoes, mkt_mensageria.disparos,
              mkt_mensageria.historico from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Triggers: carimbo, status_desde, histórico, sem DELETE ───────────────────────────────────────────────────────
create function mkt_mensageria.trg_carimbo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := coalesce(new.criado_por, auth.uid());
    new.atualizado_em := new.criado_em;
    new.atualizado_por := new.criado_por;
  else
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
    new.atualizado_em := now();
    new.atualizado_por := auth.uid();
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_carimbo() from public, anon, authenticated;

create function mkt_mensageria.trg_numero_status() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.status_desde := now();
  elsif new.status is distinct from old.status then
    new.status_desde := now();
  else
    new.status_desde := old.status_desde;
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_numero_status() from public, anon, authenticated;

-- Grava a linha inteira antes/depois. UPDATE que só muda o carimbo não gera linha. arquivado_em nulo→preenchido = arquivar.
-- Durante a anonimização (flag local à transação, ligada só por mkt_msg_anonimizar_disparo) não grava: a própria função
-- registra a linha 'anonimizar', sem o dado pessoal no "antes".
create function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, auth.uid());
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Bloqueio (42501): DELETE (linha) e TRUNCATE (comando) nas 5 tabelas; UPDATE em historico e importacoes.
-- Única exceção: UPDATE em historico com a flag de anonimização ligada, e só em antes/depois (id, tabela, registro,
-- ação, autor e data não mudam).
create function mkt_mensageria.trg_bloqueio() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'historico'
     and coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    if (new.id, new.tabela, new.registro_id, new.acao, new.por, new.em)
       is not distinct from (old.id, old.tabela, old.registro_id, old.acao, old.por, old.em) then
      return new;
    end if;
  end if;
  raise exception 'mkt_mensageria.%: % não é permitido (o registro é permanente: arquivar ou desativar)', tg_table_name, tg_op
    using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_bloqueio() from public, anon, authenticated;

-- Procedência do disparo não muda depois de gravada (nem pela tela, nem por update direto).
create function mkt_mensageria.trg_disparo_procedencia() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.origem, new.origem_sistema, new.id_externo, new.importacao_id)
     is distinct from (old.origem, old.origem_sistema, old.id_externo, old.importacao_id) then
    raise exception 'mkt_mensageria.disparos: origem, origem_sistema, id_externo e importacao_id não mudam depois de gravados'
      using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_disparo_procedencia() from public, anon, authenticated;

create trigger a_carimbo before insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger b_status before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_numero_status();
create trigger b_procedencia before update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_disparo_procedencia();
create trigger z_historico after insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_historico();
do $bloqueio$
declare t text;
begin
  foreach t in array array['ferramentas', 'numeros', 'disparos', 'importacoes', 'historico'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;
create trigger sem_update before update on mkt_mensageria.importacoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.historico
  for each row execute function mkt_mensageria.trg_bloqueio();

-- ─── 5. Seed: 13 ferramentas, custos não lançados ────────────────────────────────────────────────────────────────────
insert into mkt_mensageria.ferramentas (nome, api) values
  ('SendFlow', 'sim'), ('Unichat', 'sim'), ('ActiveCampaign', 'sim'), ('n8n', 'sim'), ('Google Drive', 'sim'),
  ('Slack', 'sim'), ('ClickUp', 'sim'),
  ('Infobip', 'nao'), ('Clint', 'nao'), ('Ligue Lead', 'nao'), ('Encurtador', 'nao'), ('Respondi', 'nao'), ('ManyChat', 'nao');

-- ─── 6. Validação de disparo (uma regra para a tela e para a planilha) ───────────────────────────────────────────────
-- Entrada (texto): enviado_em, projeto (sigla), canal, ferramenta_id, numero_id, tipo, copy_texto, copy_link,
--   publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por.
--   origem_sistema/id_externo NÃO entram (só integração, origem 'api'). Ferramenta desativada e número arquivado: recusa.
--   Saída: {erros:[{campo,msg}], v:{… valores já convertidos, projeto_id …}}.
create function mkt_mensageria.disparo_validar(p jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_enviado timestamptz := mkt_mensageria.instante(p ->> 'enviado_em');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_projeto bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_num_txt text := btrim(coalesce(p ->> 'numero_id', ''));
  v_num bigint;
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_copy text := nullif(btrim(coalesce(p ->> 'copy_texto', '')), '');
  v_link text := nullif(btrim(coalesce(p ->> 'copy_link', '')), '');
  v_lista text := btrim(coalesce(p ->> 'publico_lista', ''));
  v_origem_lista text := nullif(btrim(coalesce(p ->> 'publico_origem', '')), '');
  v_tam bigint := mkt_mensageria.inteiro(p ->> 'tamanho_lista');
  v_ent bigint := mkt_mensageria.inteiro(p ->> 'entregues');
  v_lid bigint := mkt_mensageria.inteiro(p ->> 'lidas');
  v_cli bigint := mkt_mensageria.inteiro(p ->> 'cliques');
  v_fal bigint := mkt_mensageria.inteiro(p ->> 'falhas');
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_centavos');
  v_por text := btrim(coalesce(p ->> 'disparado_por', ''));
  v_ferr_ativa boolean;
  v_ferr_nome text;
  v_num_arq timestamptz;
  v_num_txt2 text;
  v_numeros_ok boolean := true;
begin
  if v_enviado is null then
    e := e || jsonb_build_object('campo', 'enviado_em', 'msg', 'Informe a data e a hora do envio.');
  end if;

  if v_sigla = '' then
    e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
  else
    select pr.id into v_projeto from mkt.projetos pr where pr.sigla = v_sigla;
    if v_projeto is null then
      e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
    end if;
  end if;

  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  end if;

  if v_ferr_txt !~ '^[0-9]{1,18}$' then
    e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.');
  else
    select f.id, f.ativa, f.nome into v_ferr, v_ferr_ativa, v_ferr_nome
      from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Ferramenta não cadastrada.');
    elsif not v_ferr_ativa then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg',
        'Ferramenta ' || v_ferr_nome || ' está desativada: reative em Ferramentas ou escolha outra.');
    end if;
  end if;

  if v_num_txt <> '' then
    if v_num_txt ~ '^[0-9]{1,18}$' then
      select n.id, n.arquivado_em, n.numero into v_num, v_num_arq, v_num_txt2
        from mkt_mensageria.numeros n where n.id = v_num_txt::bigint;
    end if;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg', 'Número não cadastrado em Números.');
    elsif v_num_arq is not null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg',
        'Número ' || v_num_txt2 || ' está arquivado: desarquive em Números ou escolha outro.');
    end if;
  end if;

  if v_canal = 'whatsapp_api' and v_tipo is null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal in ('email', 'sms', 'ligacao', 'grupo') and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  elsif v_tipo is not null and v_tipo not in ('utility', 'marketing') then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo inválido: utility ou marketing.');
  end if;

  if v_copy is null and v_link is null then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Informe a copy: o texto, o link, ou os dois.');
  end if;
  if length(v_copy) > 4000 then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Texto da copy passa de 4.000 caracteres.');
  end if;
  if length(v_link) > 2000 then
    e := e || jsonb_build_object('campo', 'copy_link', 'msg', 'Link passa de 2.000 caracteres.');
  end if;

  if v_lista = '' or length(v_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_lista', 'msg', 'Informe a lista (público), até 200 caracteres.');
  end if;
  if length(v_origem_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_origem', 'msg', 'Origem da lista passa de 200 caracteres.');
  end if;

  if v_tam is null then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Informe o tamanho da lista.');
    v_numeros_ok := false;
  elsif v_tam < 0 then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Tamanho da lista: número inteiro, sem sinal.');
    v_numeros_ok := false;
  end if;
  if v_ent < 0 then e := e || jsonb_build_object('campo', 'entregues', 'msg', 'Entregues: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_lid < 0 then e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_cli < 0 then e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_fal < 0 then e := e || jsonb_build_object('campo', 'falhas', 'msg', 'Falhas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
  end if;

  if v_numeros_ok then
    if coalesce(v_ent, 0) + coalesce(v_fal, 0) > v_tam then
      e := e || jsonb_build_object('campo', 'entregues', 'msg',
        'Entregues + falhas (' || (coalesce(v_ent, 0) + coalesce(v_fal, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
    end if;
    if v_lid > v_ent then
      e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas (' || v_lid || ') não pode passar de entregues (' || v_ent || ').');
    end if;
    if v_cli > v_ent then
      e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques (' || v_cli || ') não pode passar de entregues (' || v_ent || ').');
    end if;
  end if;

  if v_por = '' or length(v_por) > 80 then
    e := e || jsonb_build_object('campo', 'disparado_por', 'msg', 'Informe quem disparou (até 80 caracteres).');
  end if;

  return jsonb_build_object('erros', e, 'v', jsonb_build_object(
    'enviado_em', v_enviado, 'projeto_id', v_projeto, 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', v_copy, 'copy_link', v_link, 'publico_lista', v_lista, 'publico_origem', v_origem_lista,
    'tamanho_lista', v_tam, 'entregues', v_ent, 'lidas', v_lid, 'cliques', v_cli, 'falhas', v_fal,
    'custo_centavos', v_custo, 'disparado_por', v_por));
end
$$;
revoke all on function mkt_mensageria.disparo_validar(jsonb) from public, anon, authenticated;

-- Uma linha de planilha → mesma validação. Colunas: data (dd/mm/aaaa), hora (hh:mm), projeto (sigla), canal (código ou
-- rótulo), ferramenta (nome, sem diferenciar maiúscula), numero (+55…; vazio = sem número), tipo, copy_texto, copy_link,
-- publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas ("1.234"), custo ("1.234,56" reais),
-- disparado_por. Saída: {linha, erros:[{linha,campo,msg}], v:{…}}. campo = nome da coluna da planilha.
create function mkt_mensageria.importar_linha(l jsonb, n integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_canon jsonb;
  r jsonb;
  x jsonb;
  v_ja text[] := '{}';
  v_quando timestamptz;
  v_txt text;
  v_ferr bigint;
  v_num bigint;
  v_custo bigint;
  v_canal text;
  v_tipo text;
  k text;
  v_map jsonb := '{"enviado_em":"data","ferramenta_id":"ferramenta","numero_id":"numero","custo_centavos":"custo"}';
begin
  if l is null or jsonb_typeof(l) <> 'object' then
    return jsonb_build_object('linha', n, 'erros', jsonb_build_array(jsonb_build_object('linha', n, 'campo', '-', 'msg', 'Linha em formato inválido.')), 'v', null);
  end if;

  if btrim(coalesce(l ->> 'data', '')) !~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then
    e := e || jsonb_build_object('campo', 'data', 'msg', 'Data inválida: use dd/mm/aaaa.'); v_ja := array_append(v_ja, 'enviado_em');
  elsif btrim(coalesce(l ->> 'hora', '')) !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
    e := e || jsonb_build_object('campo', 'hora', 'msg', 'Hora inválida: use hh:mm (00:00 a 23:59).'); v_ja := array_append(v_ja, 'enviado_em');
  else
    v_quando := mkt_mensageria.data_hora_br(l ->> 'data', l ->> 'hora');
    if v_quando is null then
      e := e || jsonb_build_object('campo', 'data', 'msg', 'Data não existe: ' || btrim(l ->> 'data') || '.'); v_ja := array_append(v_ja, 'enviado_em');
    end if;
  end if;

  v_txt := btrim(coalesce(l ->> 'ferramenta', ''));
  if v_txt = '' then
    e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Informe a ferramenta.'); v_ja := array_append(v_ja, 'ferramenta_id');
  else
    select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.'); v_ja := array_append(v_ja, 'ferramenta_id');
    end if;
  end if;

  v_txt := regexp_replace(coalesce(l ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero', 'msg', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.'); v_ja := array_append(v_ja, 'numero_id');
    end if;
  end if;

  v_custo := mkt_mensageria.centavos_br(l ->> 'custo');
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo', 'msg', 'Custo inválido: use reais, como 1.234,56 (ou vazio se não lançado).');
    v_ja := array_append(v_ja, 'custo_centavos'); v_custo := null;
  end if;

  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'canal', '')));
  v_canal := case when v_txt in ('WHATSAPP_API', 'API WHATSAPP', 'WHATSAPP API', 'API') then 'whatsapp_api'
                  when v_txt in ('EMAIL', 'E-MAIL') then 'email'
                  when v_txt = 'SMS' then 'sms'
                  when v_txt in ('LIGACAO', 'LIGACOES') then 'ligacao'
                  when v_txt in ('GRUPO', 'GRUPOS') then 'grupo'
                  else lower(v_txt) end;
  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'tipo', '')));
  v_tipo := case when v_txt in ('UTILITY', 'UTILIDADE') then 'utility' when v_txt = 'MARKETING' then 'marketing'
                 else nullif(lower(v_txt), '') end;

  v_canon := jsonb_build_object(
    'enviado_em', v_quando, 'projeto', l ->> 'projeto', 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', l ->> 'copy_texto', 'copy_link', l ->> 'copy_link', 'publico_lista', l ->> 'publico_lista',
    'publico_origem', l ->> 'publico_origem', 'disparado_por', l ->> 'disparado_por', 'custo_centavos', v_custo);
  foreach k in array array['tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas'] loop
    -- "1.234" vira "1234"; formato errado segue cru e a validação acusa.
    v_canon := v_canon || jsonb_build_object(k, case when mkt_mensageria.inteiro_br(l ->> k) >= 0
                                                     then mkt_mensageria.inteiro_br(l ->> k)::text else l ->> k end);
  end loop;

  r := mkt_mensageria.disparo_validar(v_canon);
  for x in select * from jsonb_array_elements(r -> 'erros') loop
    if not (x ->> 'campo' = any(v_ja)) then
      e := e || jsonb_build_object('campo', coalesce(v_map ->> (x ->> 'campo'), x ->> 'campo'), 'msg', x ->> 'msg');
    end if;
  end loop;

  return jsonb_build_object('linha', n,
    'erros', (select coalesce(jsonb_agg(jsonb_build_object('linha', n) || y), '[]'::jsonb) from jsonb_array_elements(e) y),
    'v', case when jsonb_array_length(e) = 0 then r -> 'v' end);
end
$$;
revoke all on function mkt_mensageria.importar_linha(jsonb, integer) from public, anon, authenticated;

-- ─── 7. Funções públicas (RPC). Toda uma: guarda mkt.pode_ver('mkt_mensageria') + revoke/grant logo abaixo ──────────

-- Lista do período. Ver contrato em 20261005n.explain.md. plan_cache_mode: cada chamada planeja com os valores reais,
-- então "(v_proj is null or projeto_id = v_proj)" vira "projeto_id = 5" e o índice (projeto_id, enviado_em) entra.
create function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                               p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, mkt_mensageria.pendencias(d.entregues, d.lidas, d.custo_centavos) as pendencias
        from mkt_mensageria.disparos d
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias))
               order by b.enviado_em desc, b.id desc)
          from pagina b
          join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo, count(*) filter (where b.custo_centavos is null) as sem_custo
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: ver mkt_mensageria.disparo_validar. Retorna {ok, msg, id, erros?}.
-- origem é sempre 'manual'; origem_sistema/id_externo vindos no JSON são ignorados (não grava nem altera).
-- Na edição, retorno_em é carimbado se entregues/lidas/cliques/falhas/custo mudaram. Arquivado não se edita.
create function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Arquiva (some da lista e dos totais; fica no banco e no histórico). Motivo obrigatório. Nunca apaga.
create function public.mkt_msg_disparo_arquivar(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo do arquivamento (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.disparos set arquivado_em = now(), arquivado_motivo = v_motivo
   where id = p_id and arquivado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.disparos where id = p_id) then 'Disparo já arquivado.'
      else 'Disparo não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Disparo arquivado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_disparo_arquivar(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_arquivar(bigint, text) to authenticated;

-- Lança o retorno de um disparo. Os 5 valores substituem os atuais; nulo = não lançado (nunca vira 0).
-- retorno_em = agora; se os 5 vierem nulos, retorno_em volta a nulo.
create function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                      p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista into v_tam from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
                            'pendencias', to_jsonb(mkt_mensageria.pendencias(p_entregues, p_lidas, p_custo_centavos)));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Importa planilha. p_confirmar=false: só valida e devolve {ok, erros, validas, total, duplicadas_banco, duplicadas_lote}.
-- p_confirmar=true: tudo ou nada; com qualquer erro, nada entra. Com possível duplicata (já no log, ou repetida no
-- próprio lote: mesma data/hora, projeto, canal e lista) também nada entra, a menos que p_aceitar_duplicadas=true.
-- Máx. 2.000 linhas. A planilha não grava origem_sistema/id_externo (ver 20261005n.explain.md). Colunas em importar_linha.
create function public.mkt_msg_importar(p_linhas jsonb, p_confirmar boolean default false, p_arquivo text default null,
                                        p_aceitar_duplicadas boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer;
  v_res jsonb[];
  v_erros jsonb;
  v_qtd_erros integer;
  v_validas integer;
  v_dup_banco jsonb;
  v_dup_lote jsonb;
  v_tem_dup boolean;
  v_imp bigint;
  v_ins integer;
  v_con text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Nenhuma linha para importar.', 'erros', '[]'::jsonb, 'validas', 0, 'total', 0);
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n > 2000 then
    return jsonb_build_object('ok', false, 'msg', 'Máximo de 2.000 linhas por importação (vieram ' || v_n || '). Divida a planilha.',
                              'erros', '[]'::jsonb, 'validas', 0, 'total', v_n);
  end if;
  -- Duas confirmações ao mesmo tempo não passam juntas: a segunda espera a primeira e então vê as duplicatas dela.
  if coalesce(p_confirmar, false) then
    perform pg_advisory_xact_lock(hashtext('mkt_mensageria.importar'));
  end if;

  select array_agg(mkt_mensageria.importar_linha(t.l, t.n::int) order by t.n) into v_res
    from jsonb_array_elements(p_linhas) with ordinality t(l, n);

  select count(*), coalesce(jsonb_agg(x.e order by x.linha, x.o) filter (where x.rn <= 500), '[]'::jsonb)
    into v_qtd_erros, v_erros
    from (select (r ->> 'linha')::int as linha, e.o, e.e, row_number() over (order by (r ->> 'linha')::int, e.o) as rn
            from unnest(v_res) r, jsonb_array_elements(r -> 'erros') with ordinality e(e, o)) x;
  select count(*) into v_validas from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object';

  -- Duplicata contra o banco: mesma data/hora, projeto, canal e lista já no log (não arquivado). Índice (projeto_id, enviado_em).
  select coalesce(jsonb_agg((r ->> 'linha')::int order by (r ->> 'linha')::int), '[]'::jsonb) into v_dup_banco
    from unnest(v_res) r
   where jsonb_typeof(r -> 'v') = 'object'
     and exists (select 1 from mkt_mensageria.disparos d
                  where d.projeto_id = (r -> 'v' ->> 'projeto_id')::bigint
                    and d.enviado_em = (r -> 'v' ->> 'enviado_em')::timestamptz
                    and d.canal = r -> 'v' ->> 'canal'
                    and d.publico_lista = r -> 'v' ->> 'publico_lista'
                    and d.arquivado_em is null);
  -- Duplicata dentro do lote: todas as linhas de um grupo repetido.
  select coalesce(jsonb_agg(x.linha order by x.linha), '[]'::jsonb) into v_dup_lote
    from (select (r ->> 'linha')::int as linha,
                 count(*) over (partition by r -> 'v' ->> 'projeto_id', (r -> 'v' ->> 'enviado_em')::timestamptz,
                                             r -> 'v' ->> 'canal', r -> 'v' ->> 'publico_lista') as qtd
            from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object') x
   where x.qtd > 1;
  v_tem_dup := jsonb_array_length(v_dup_banco) > 0 or jsonb_array_length(v_dup_lote) > 0;

  if not coalesce(p_confirmar, false) or v_qtd_erros > 0 then
    return jsonb_build_object('ok', v_qtd_erros = 0,
      'msg', case when v_qtd_erros > 0 then v_qtd_erros || ' erro(s) em ' || (v_n - v_validas) || ' linha(s). Nada foi gravado.'
                  when v_tem_dup then v_validas || ' linhas válidas, com possível duplicata (veja as linhas). Nada foi gravado ainda.'
                  else v_validas || ' linhas válidas. Nada foi gravado ainda.' end,
      'erros', v_erros, 'erros_total', v_qtd_erros, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;
  if v_tem_dup and not coalesce(p_aceitar_duplicadas, false) then
    return jsonb_build_object('ok', false,
      'msg', 'Possível duplicata: ' || jsonb_array_length(v_dup_banco) || ' linha(s) já no registro e '
             || jsonb_array_length(v_dup_lote) || ' repetida(s) na planilha. Nada foi gravado. Confira e, se estiver certo, '
             || 'confirme de novo marcando "importar mesmo assim".',
      'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;

  begin
    insert into mkt_mensageria.importacoes (arquivo, linhas, criado_por)
    values (nullif(left(btrim(coalesce(p_arquivo, '')), 255), ''), v_n, (select auth.uid()))
    returning id into v_imp;

    insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, importacao_id)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'planilha', v_imp
      from (select r -> 'v' as v, (r ->> 'linha')::int as linha from unnest(v_res) r) s
     order by s.linha;
    get diagnostics v_ins = row_count;
  exception
    when check_violation or foreign_key_violation or not_null_violation or unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Nada foi importado: valor fora da regra (' || coalesce(v_con, 'dados') || ').',
                                'erros', '[]'::jsonb, 'validas', v_validas, 'total', v_n);
  end;
  return jsonb_build_object('ok', true, 'msg', v_ins || ' disparos importados.', 'importacao_id', v_imp,
                            'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_ins, 'total', v_n,
                            'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
end
$$;
revoke all on function public.mkt_msg_importar(jsonb, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.mkt_msg_importar(jsonb, boolean, text, boolean) to authenticated;

-- Números com consumo de hoje (America/Sao_Paulo) somado do log. Uma query; por número, um lookup no índice
-- (numero_id, enviado_em) restrito ao dia. Arquivados vêm por último, com arquivado_em preenchido.
create function public.mkt_msg_numeros_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini timestamptz := v_hoje::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (v_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'numeros', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', n.id, 'numero', n.numero, 'projeto_id', n.projeto_id, 'projeto', pr.sigla, 'frente', n.frente,
             'responsavel', n.responsavel, 'finalidade', n.finalidade, 'ferramenta_id', n.ferramenta_id,
             'ferramenta', f.nome, 'capacidade_dia', n.capacidade_dia, 'status', n.status, 'status_desde', n.status_desde,
             'arquivado_em', n.arquivado_em, 'consumo_hoje', coalesce(c.total, 0),
             'acima_da_capacidade', n.capacidade_dia is not null and coalesce(c.total, 0) > n.capacidade_dia,
             'atualizado_em', n.atualizado_em)
           order by (n.arquivado_em is not null), array_position(array['ativo', 'aquecendo', 'restrito', 'disponivel'], n.status), n.numero),
           '[]'::jsonb)
      from mkt_mensageria.numeros n
      left join mkt.projetos pr on pr.id = n.projeto_id
      left join mkt_mensageria.ferramentas f on f.id = n.ferramenta_id
      left join lateral (select sum(d.tamanho_lista) as total
                           from mkt_mensageria.disparos d
                          where d.numero_id = n.id and d.enviado_em >= v_ini and d.enviado_em < v_fim
                            and d.arquivado_em is null) c on true));
end
$$;
revoke all on function public.mkt_msg_numeros_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_numeros_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: numero (+55 11 99999-0000: espaços, traços e parênteses saem; o "+" e o
-- código do país são obrigatórios), projeto (sigla, opcional), frente, responsavel, finalidade, ferramenta_id,
-- capacidade_dia (1 a 1000, opcional), status, arquivado (bool). Retorna {ok, msg, id}.
create function public.mkt_msg_numero_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_numero text := regexp_replace(coalesce(p ->> 'numero', ''), '[\s().-]', '', 'g');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_proj bigint;
  v_frente text := nullif(btrim(coalesce(p ->> 'frente', '')), '');
  v_resp text := btrim(coalesce(p ->> 'responsavel', ''));
  v_fin text := lower(btrim(coalesce(p ->> 'finalidade', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_cap bigint := mkt_mensageria.inteiro(p ->> 'capacidade_dia');
  v_status text := lower(btrim(coalesce(p ->> 'status', '')));
  v_arq boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados do número ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_arq := coalesce(nullif(p ->> 'arquivado', '')::boolean, false);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "arquivado" deve ser verdadeiro ou falso.');
  end;
  if v_numero !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número no formato internacional, com + e código do país (ex.: +55 11 99999-0000).');
  end if;
  if v_sigla <> '' then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
    if v_proj is null then return jsonb_build_object('ok', false, 'msg', 'Projeto ' || v_sigla || ' não cadastrado.'); end if;
  end if;
  if length(v_frente) > 60 then return jsonb_build_object('ok', false, 'msg', 'Frente: até 60 caracteres.'); end if;
  if v_resp = '' or length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Informe o responsável (até 80 caracteres).'); end if;
  if v_fin not in ('mensageria', 'comercial', 'financeiro', 'suporte') then
    return jsonb_build_object('ok', false, 'msg', 'Finalidade: mensageria, comercial, financeiro ou suporte.');
  end if;
  if v_ferr_txt <> '' then
    if v_ferr_txt ~ '^[0-9]{1,18}$' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    end if;
    if v_ferr is null then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não cadastrada.'); end if;
  end if;
  if v_cap is not null and (v_cap < 1 or v_cap > 1000) then
    return jsonb_build_object('ok', false, 'msg', 'Capacidade por dia: de 1 a 1.000 (ou vazio se não definida).');
  end if;
  if v_status not in ('ativo', 'aquecendo', 'restrito', 'disponivel') then
    return jsonb_build_object('ok', false, 'msg', 'Status: ativo, aquecendo, restrito ou disponível.');
  end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.numeros (numero, projeto_id, frente, responsavel, finalidade, ferramenta_id, capacidade_dia,
                                          status, arquivado_em)
      values (v_numero, v_proj, v_frente, v_resp, v_fin, v_ferr, v_cap::smallint, v_status, case when v_arq then now() end)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' cadastrado.', 'id', v_id);
    end if;
    update mkt_mensageria.numeros n
       set numero = v_numero, projeto_id = v_proj, frente = v_frente, responsavel = v_resp, finalidade = v_fin,
           ferramenta_id = v_ferr, capacidade_dia = v_cap::smallint, status = v_status,
           arquivado_em = case when v_arq then coalesce(n.arquivado_em, now()) end
     where n.id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Número não encontrado.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' salvo.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Número ' || v_numero || ' já cadastrado.');
  end;
end
$$;
revoke all on function public.mkt_msg_numero_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_numero_salvar(jsonb) to authenticated;

create function public.mkt_msg_ferramentas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', f.id, 'nome', f.nome, 'api', f.api, 'custo_mensal_centavos', f.custo_mensal_centavos,
            'responsavel', f.responsavel, 'ativa', f.ativa, 'obs', f.obs, 'atualizado_em', f.atualizado_em)
          order by f.ativa desc, lower(f.nome)), '[]'::jsonb)
            from mkt_mensageria.ferramentas f);
end
$$;
revoke all on function public.mkt_msg_ferramentas_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramentas_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: nome, api (sim|futura|nao), custo_mensal_centavos (inteiro ≥ 0; vazio =
-- não lançado), responsavel, ativa, obs. Ferramenta não se apaga: desativa (ativa=false). Retorna {ok, msg, id}.
create function public.mkt_msg_ferramenta_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_api text := lower(btrim(coalesce(p ->> 'api', '')));
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_mensal_centavos');
  v_resp text := nullif(btrim(coalesce(p ->> 'responsavel', '')), '');
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_ativa boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados da ferramenta ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Ferramenta inválida.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_ativa := coalesce(nullif(p ->> 'ativa', '')::boolean, true);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "ativa" deve ser verdadeiro ou falso.');
  end;
  if v_nome = '' or length(v_nome) > 60 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome (até 60 caracteres).'); end if;
  if v_api not in ('sim', 'futura', 'nao') then
    return jsonb_build_object('ok', false, 'msg', 'API: sim, futura ou não.');
  end if;
  if v_custo < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Custo mensal: centavos, inteiro ≥ 0 (ou vazio se não lançado).');
  end if;
  if length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Responsável: até 80 caracteres.'); end if;
  if length(v_obs) > 1000 then return jsonb_build_object('ok', false, 'msg', 'Observação: até 1.000 caracteres.'); end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.ferramentas (nome, api, custo_mensal_centavos, responsavel, ativa, obs)
      values (v_nome, v_api, v_custo::int, v_resp, v_ativa, v_obs)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' cadastrada.', 'id', v_id);
    end if;
    update mkt_mensageria.ferramentas
       set nome = v_nome, api = v_api, custo_mensal_centavos = v_custo::int, responsavel = v_resp, ativa = v_ativa, obs = v_obs
     where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não encontrada.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' salva.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Já existe ferramenta com o nome ' || v_nome || '.');
  end;
end
$$;
revoke all on function public.mkt_msg_ferramenta_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramenta_salvar(jsonb) to authenticated;

-- Histórico de um registro (até 200 mudanças, mais recente primeiro). p_tabela: disparos | numeros | ferramentas.
create function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', pf.nome, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- LGPD: apaga o conteúdo que pode ter dado pessoal (copy_texto, publico_lista, publico_origem) de UM disparo e de todas
-- as linhas do histórico dele, e registra a anonimização no histórico (acao 'anonimizar', com motivo, sem o conteúdo).
-- Só admin/dev (gp_is_admin), mesmo quando mkt.pode_ver for aberto a operador/gestor. Funciona com disparo arquivado.
-- Exceção controlada ao bloqueio de UPDATE do histórico: flag local à transação, desligada antes de sair.
create function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform 1 from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  f record;
  v_publicas text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                             'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                             'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                             'mkt_msg_historico', 'mkt_msg_anonimizar_disparo'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_mensageria', 'usage') or has_schema_privilege(r, 'mkt_mensageria', 'create') then
      raise exception '20261005n: % tem acesso ao schema mkt_mensageria', r;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005n: % tem privilégio em %', r, t;
      end if;
    end loop;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005n: RLS desligada em %', t;
    end if;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005n: PUBLIC tem privilégio em %', t;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'S' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_sequence_privilege(r, t, 'usage, select, update') then
        raise exception '20261005n: % tem privilégio na sequência %', r, t;
      end if;
    end loop;
  end loop;

  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005n: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005n: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005n: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_publicas))
       <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005n: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005n: % deveria ser SECURITY DEFINER', f.sig;
    end if;
    if f.proname = any(v_publicas) and f.proname <> 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda coalesce(mkt.pode_ver(''mkt_mensageria''), false)', f.sig;
    end if;
    if f.proname = 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda gp_is_admin', f.sig;
    end if;
    if f.pronamespace = 'mkt_mensageria'::regnamespace and f.prosecdef then
      raise exception '20261005n: interna % não deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 11
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 11 then
    raise exception '20261005n: esperava exatamente as 11 funções public.mkt_msg_* (sobrecarga?)';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria' and table_name = 'disparos'
                and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos') and column_default is not null) then
    raise exception '20261005n: retorno/custo com default (nulo tem que ser "não lançado")';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas) <> 13
     or exists (select 1 from mkt_mensageria.ferramentas where custo_mensal_centavos is not null) then
    raise exception '20261005n: seed diferente do esperado (13 ferramentas, custos nulos)';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; apaga TODO o log de disparos, números e histórico: exportar antes) ═══════════════════
-- begin;
-- drop function public.mkt_msg_disparos_listar(date, date, text, text, bigint), public.mkt_msg_disparo_salvar(jsonb),
--   public.mkt_msg_disparo_arquivar(bigint, text),
--   public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer),
--   public.mkt_msg_importar(jsonb, boolean, text, boolean), public.mkt_msg_numeros_listar(), public.mkt_msg_numero_salvar(jsonb),
--   public.mkt_msg_ferramentas_listar(), public.mkt_msg_ferramenta_salvar(jsonb), public.mkt_msg_historico(text, text),
--   public.mkt_msg_anonimizar_disparo(bigint, text);
-- drop schema mkt_mensageria cascade;   -- leva tabelas, triggers e as FKs para mkt.projetos (mkt.projetos fica intacta)
-- commit;
-- Desligar sem apagar dado: revoke execute on function public.mkt_msg_<…> from authenticated; (a tela recebe 42501).

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito) ═══════════════════════════
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projeto e ferramenta usados nos testes (os ids reais de produção; nada é escrito em mkt.projetos)
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as projeto_id,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign;
grant all on _z_ref to public;
-- Muda para "admin logado" (role authenticated + JWT do admin) e de volta para postgres.
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;

-- ═══ BLOCO 2: volume (10.000 disparos) + explain (analyze, buffers) das consultas quentes ═════════════════════════
-- 20 números e 10.000 disparos sintéticos, um a cada 52 min (≈ 361 dias para trás), 40% com número, 1/7 sem retorno,
-- 1/3 sem custo; projetos = os reais, em rodízio. Triggers ligados (carimbo + histórico), como em produção.
insert into mkt_mensageria.numeros (numero, responsavel, finalidade, ferramenta_id, capacidade_dia, status)
select '+55119000000' || lpad(i::text, 2, '0'), 'Ensaio', 'mensageria', (select sendflow from pg_temp._z_ref), 50, 'ativo'
  from generate_series(1, 20) i;

insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
       publico_lista, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por)
select now() - i * interval '52 minutes',
       pr.ids[1 + i % array_length(pr.ids, 1)],
       c.canal,
       f.ids[1 + i % array_length(f.ids, 1)],
       case when c.canal in ('whatsapp_api', 'grupo') then nu.ids[1 + (i / 5) % 20] end,
       case when c.canal = 'whatsapp_api' then (array['utility', 'marketing'])[1 + (i / 5) % 2] end,
       'Copy sintética ' || i, 'Lista ' || (i % 37), 100 + i % 900,
       case when i % 7 = 0 then null else 50 + i % 50 end,
       case when i % 7 = 0 then null else i % 50 end,
       case when i % 7 = 0 then null else i % 10 end,
       case when i % 7 = 0 then null else i % 5 end,
       case when i % 3 = 0 then null else i % 2000 end,
       'Ensaio'
  from generate_series(1, 10000) i
  cross join lateral (select (array['whatsapp_api', 'email', 'sms', 'ligacao', 'grupo'])[1 + i % 5] as canal) c
  cross join (select array_agg(id order by id) as ids from mkt.projetos) pr
  cross join (select array_agg(id order by id) as ids from mkt_mensageria.ferramentas) f
  cross join (select array_agg(id order by id) as ids from mkt_mensageria.numeros) nu;

analyze mkt_mensageria.disparos;
analyze mkt_mensageria.numeros;
analyze mkt_mensageria.historico;

-- Plano de cada consulta quente. O texto é o MESMO do corpo da função, com os valores no lugar das variáveis (é o
-- que o plan_cache_mode = force_custom_plan faz em listar). Se o índice esperado não aparecer, o bloco aborta.
create function pg_temp.plano(p_passo text, p_sql text, p_indice text) returns void language plpgsql as $f$
declare
  l text;
  v text := '';
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
    v := v || l || E'\n';
  end loop;
  if v !~ p_indice then
    raise exception '% FALHOU: o plano não usa %:%', p_passo, p_indice, E'\n' || v;
  end if;
  perform pg_temp.ok(p_passo, 'usa ' || substring(v from p_indice));
end
$f$;

do $e$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_q text := $q$
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, mkt_mensageria.pendencias(d.entregues, d.lidas, d.custo_centavos) as pendencias
        from mkt_mensageria.disparos d
       where d.enviado_em >= %1$L::timestamptz and d.enviado_em < %2$L::timestamptz
         and d.arquivado_em is null
         and (%3$L::bigint is null or d.projeto_id = %3$L::bigint)
         and (%4$L::text is null or d.canal = %4$L::text)
         and (%5$L::bigint is null or d.ferramenta_id = %5$L::bigint)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias))
               order by b.enviado_em desc, b.id desc)
          from pagina b
          join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo, count(*) filter (where b.custo_centavos is null) as sem_custo
                  from base b group by b.canal) c), '[]'::jsonb))
  $q$;
  v_ini timestamptz := (v_hoje - 29)::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (v_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
  v_hini timestamptz := v_hoje::timestamp at time zone 'America/Sao_Paulo';
  v_proj bigint := (select projeto_id from pg_temp._z_ref);
begin
  perform pg_temp.plano('E1 listar 30 dias', format(v_q, v_ini, v_fim, null, null, null), 'disparos_enviado_idx');
  -- 30 dias + projeto: com 4 projetos o planner pode preferir varrer o mês pelo índice de data e filtrar (correto);
  -- aceita qualquer um dos dois índices, nunca Seq Scan.
  perform pg_temp.plano('E2 listar 30 dias + projeto', format(v_q, v_ini, v_fim, v_proj, null, null), 'disparos_(projeto_)?enviado_idx');
  -- 366 dias + projeto: é aqui que o índice (projeto_id, enviado_em) se paga; ele TEM que aparecer.
  perform pg_temp.plano('E2b listar 366 dias + projeto', format(v_q, (v_hoje - 365)::timestamp at time zone 'America/Sao_Paulo', v_fim, v_proj, null, null),
                        'disparos_projeto_enviado_idx');
  perform pg_temp.plano('E3 numeros_listar', format($q$
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', n.id, 'numero', n.numero, 'projeto_id', n.projeto_id, 'projeto', pr.sigla, 'frente', n.frente,
             'responsavel', n.responsavel, 'finalidade', n.finalidade, 'ferramenta_id', n.ferramenta_id,
             'ferramenta', f.nome, 'capacidade_dia', n.capacidade_dia, 'status', n.status, 'status_desde', n.status_desde,
             'arquivado_em', n.arquivado_em, 'consumo_hoje', coalesce(c.total, 0),
             'acima_da_capacidade', n.capacidade_dia is not null and coalesce(c.total, 0) > n.capacidade_dia,
             'atualizado_em', n.atualizado_em)
           order by (n.arquivado_em is not null), array_position(array['ativo', 'aquecendo', 'restrito', 'disponivel'], n.status), n.numero),
           '[]'::jsonb)
      from mkt_mensageria.numeros n
      left join mkt.projetos pr on pr.id = n.projeto_id
      left join mkt_mensageria.ferramentas f on f.id = n.ferramenta_id
      left join lateral (select sum(d.tamanho_lista) as total
                           from mkt_mensageria.disparos d
                          where d.numero_id = n.id and d.enviado_em >= %1$L::timestamptz and d.enviado_em < %2$L::timestamptz
                            and d.arquivado_em is null) c on true $q$, v_hini, v_fim), 'disparos_numero_enviado_idx');
  perform pg_temp.plano('E4 historico', format($q$
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', pf.nome, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = 'disparos' and h.registro_id = %1$L
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por $q$, (select max(id) from mkt_mensageria.disparos)::text), 'historico_registro_idx');
end
$e$;

-- Tempo e tamanho reais das funções, chamadas como a tela chama (admin logado)
select pg_temp.como_admin();
do $t$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t0 timestamptz;
  r jsonb;
  v_sigla text := (select sigla from pg_temp._z_ref);
begin
  t0 := clock_timestamp(); r := public.mkt_msg_disparos_listar(v_hoje - 29, v_hoje);
  perform pg_temp.ok('V1 listar 30 dias', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'linhas') || ' linhas, qtd=' || (r -> 'totais' ->> 'qtd') || ', truncado=' || (r ->> 'truncado')
    || ', ' || pg_size_pretty(length(r::text)::bigint));
  t0 := clock_timestamp(); r := public.mkt_msg_disparos_listar(v_hoje - 29, v_hoje, v_sigla);
  perform pg_temp.ok('V2 listar 30 dias + projeto', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'linhas') || ' linhas, qtd=' || (r -> 'totais' ->> 'qtd') || ', ' || pg_size_pretty(length(r::text)::bigint));
  t0 := clock_timestamp(); r := public.mkt_msg_disparos_listar(v_hoje - 365, v_hoje);
  perform pg_temp.ok('V3 listar 366 dias (pior caso)', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'linhas') || ' linhas, qtd=' || (r -> 'totais' ->> 'qtd') || ', truncado=' || (r ->> 'truncado')
    || ', ' || pg_size_pretty(length(r::text)::bigint));
  if (r -> 'totais' ->> 'qtd')::int < 9000 or jsonb_array_length(r -> 'linhas') <> 500 or not (r ->> 'truncado')::boolean then
    raise exception 'V3 FALHOU: limite/totais: qtd=% linhas=%', r -> 'totais' ->> 'qtd', jsonb_array_length(r -> 'linhas');
  end if;
  t0 := clock_timestamp(); r := public.mkt_msg_numeros_listar();
  perform pg_temp.ok('V4 numeros_listar', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'numeros') || ' números, consumo_hoje total='
    || (select sum((x ->> 'consumo_hoje')::int) from jsonb_array_elements(r -> 'numeros') x));
end
$t$;
reset role;
do $c$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_esperado bigint := (select coalesce(sum(tamanho_lista), 0) from mkt_mensageria.disparos
                         where numero_id is not null and arquivado_em is null
                           and (enviado_em at time zone 'America/Sao_Paulo')::date = v_hoje);
  v_obtido bigint;
begin
  perform pg_temp.como_admin();
  v_obtido := (select sum((x ->> 'consumo_hoje')::int) from jsonb_array_elements(public.mkt_msg_numeros_listar() -> 'numeros') x);
  reset role;
  if v_obtido <> v_esperado then
    raise exception 'V5 FALHOU: consumo_hoje total % ≠ soma direta %', v_obtido, v_esperado;
  end if;
  perform pg_temp.ok('V5 consumo_hoje', 'soma dos números = soma direta do log de hoje (' || v_esperado || ')');
end
$c$;

-- Fim do bloco 2: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005n BLOCO 2 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.\n'
    || (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 2

-- ▶ BLOCO 3 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005n_mkt_mensageria.sql) ═══
-- 20261005n: Marketing > Mensageria (etapa 2: o banco da área)
--
-- O QUE FAZ
--   Cria o schema mkt_mensageria: o LOG CENTRAL DE DISPAROS (todo envio de WhatsApp API, e-mail, SMS, ligação e grupo,
--   de qualquer ferramenta), o CONTROLE DE NÚMEROS (quem responde por cada número, para quê, quanto aguenta por dia) e o
--   cadastro de FERRAMENTAS. Decisões de 05/10/2026:
--     - Retorno e custo não lançados ficam NULOS, nunca 0. Sem default nessas colunas. 0 é "medido e deu zero".
--     - Consumo do dia de cada número vem do log (soma de tamanho_lista dos disparos de hoje). Ninguém digita.
--     - Nada se apaga: disparo errado é ARQUIVADO com motivo; triggers recusam DELETE/TRUNCATE (e UPDATE em historico e
--       importacoes). Toda mudança vai para o histórico. Única exceção: anonimização LGPD (mkt_msg_anonimizar_disparo).
--     - Planilha recusa possível duplicata (no log ou no próprio lote) salvo aceite explícito; id_externo só via API.
--     - Projeto = mkt.projetos (20261005m), pela sigla. cs.disparos e cs.canais_disparo são de OUTRO sistema: não toca.
--     - Quem vê: o mesmo de todo o Marketing, mkt.pode_ver('mkt_mensageria') (hoje admin/dev). Função NÃO alterada aqui.
--
--   Padrão da 20261005m: tabelas fechadas (RLS ligada, sem policy, revoke de public/anon/authenticated em schema,
--   tabelas e sequências), todo acesso por função public.mkt_msg_* SECURITY DEFINER, search_path '', guarda no corpo
--   com 42501. Cada função tem o revoke/grant logo abaixo do create (função nova nasce executável por PUBLIC).
--
-- O QUE CRIA
--   mkt_mensageria.ferramentas (13 de seed), numeros, importacoes, disparos, historico
--   mkt_mensageria.* internas: inteiro, inteiro_br, centavos_br, data_hora_br, instante, pendencias, disparo_validar,
--                              importar_linha, trg_carimbo, trg_numero_status, trg_historico, trg_bloqueio, trg_disparo_procedencia
--   public.mkt_msg_*  disparos_listar, disparo_salvar, disparo_arquivar, disparo_lancar_retorno, importar,
--                     numeros_listar, numero_salvar, ferramentas_listar, ferramenta_salvar, historico,
--                     anonimizar_disparo (LGPD, só admin)
--   Projetos: a tela usa public.mkt_projetos_listar() (20261005m). Não há mkt_msg_projetos_listar.
--
-- AS 5 PERGUNTAS
--   escala: estimativa de dezenas a centenas de disparos/dia. listar exige período (máx. 366 dias) e devolve no máximo
--     500 linhas; os totais varrem só o período, pelo índice. numeros_listar: um lookup por número no índice
--     (numero_id, enviado_em), só o dia de hoje. importar: no máximo 2.000 linhas, validação em uma query.
--   índice: disparos (enviado_em desc), (projeto_id, enviado_em desc), (numero_id, enviado_em); historico
--     (tabela, registro_id, em desc). Prova: 20261005n_ensaio.sql bloco 2 (explain analyze com 10.000 disparos).
--   frequência: a tela lê ao abrir e ao trocar filtro; escrita manual (pessoa) ou importação de planilha.
--   repetição: uma chamada por tela/filtro; totais e linhas na mesma query (CTE materializada, uma varredura).
--   reversão: bloco REVERSÃO no fim (o schema é novo e isolado; drop dele não afeta a 20261005m).
--
-- ENSAIO: 20261005n_ensaio.sql (3 blocos, cada um begin … aborto). Contrato e medições: 20261005n.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regnamespace('mkt_mensageria') is not null then
    raise exception '20261005n: schema mkt_mensageria já existe (migration já aplicada?)';
  end if;
  if to_regclass('mkt.projetos') is null or to_regprocedure('mkt.pode_ver(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null then
    raise exception '20261005n: base compartilhada ausente (mkt.projetos, mkt.pode_ver, mkt.sem_acento): aplicar 20261005m antes';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception '20261005n: auth.uid() ausente';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') then
    raise exception '20261005n: já existem funções public.mkt_msg_*';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'perfis' and column_name in ('id', 'nome')) <> 2 then
    raise exception '20261005n: public.perfis (id, nome) ausente';
  end if;
end
$guarda$;

-- ─── 1. Schema ───────────────────────────────────────────────────────────────────────────────────────────────────────
create schema mkt_mensageria;
revoke all on schema mkt_mensageria from public, anon, authenticated;
comment on schema mkt_mensageria is
  'Marketing > Mensageria: log central de disparos, controle de números e ferramentas. Retorno/custo nulo = não '
  'lançado (nunca 0). Nada se apaga (arquivar). Fechado: acesso só pelas funções public.mkt_msg_*. 20261005n.';

-- ─── 2. Funções auxiliares (internas: revoke de todos logo após cada create) ─────────────────────────────────────────
-- Inteiro ≥ 0 vindo da tela/JSON ("1234"). Vazio = nulo. Fora do formato (negativo, decimal, texto) = -1.
create function mkt_mensageria.inteiro(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro(text) from public, anon, authenticated;

-- Inteiro ≥ 0 vindo de planilha brasileira ("1234" ou "1.234"). Vazio = nulo. Fora do formato = -1.
create function mkt_mensageria.inteiro_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p is null or btrim(p) = '' then null
              when btrim(p) ~ '^[0-9]{1,9}$' then btrim(p)::bigint
              when btrim(p) ~ '^[0-9]{1,3}(\.[0-9]{3}){1,2}$' then replace(btrim(p), '.', '')::bigint
              else -1 end;
$$;
revoke all on function mkt_mensageria.inteiro_br(text) from public, anon, authenticated;

-- Reais de planilha ("1.234,56", "R$ 12,5", "990") → centavos. Vazio = nulo. Fora do formato = -1. Teto R$ 999.999,99.
create function mkt_mensageria.centavos_br(p text) returns bigint
language sql immutable set search_path = '' as $$
  select case when v = '' then null
              when v ~ '^([0-9]{1,3}(\.[0-9]{3})?|[0-9]{1,6})(,[0-9]{1,2})?$' then
                replace(split_part(v, ',', 1), '.', '')::bigint * 100
                + coalesce(rpad(nullif(split_part(v, ',', 2), ''), 2, '0')::bigint, 0)
              else -1 end
    from (select regexp_replace(btrim(coalesce(p, '')), '^R\$\s*', '') as v) t;
$$;
revoke all on function mkt_mensageria.centavos_br(text) from public, anon, authenticated;

-- "dd/mm/aaaa" + "hh:mm" no horário de São Paulo. Nulo se faltar ou não existir (31/02, 25:00).
create function mkt_mensageria.data_hora_br(p_data text, p_hora text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v_d text[] := regexp_match(btrim(coalesce(p_data, '')), '^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})$');
  v_h text[] := regexp_match(btrim(coalesce(p_hora, '')), '^([0-9]{1,2}):([0-9]{2})$');
begin
  if v_d is null or v_h is null then return null; end if;
  return make_timestamptz(v_d[3]::int, v_d[2]::int, v_d[1]::int, v_h[1]::int, v_h[2]::int, 0, 'America/Sao_Paulo');
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.data_hora_br(text, text) from public, anon, authenticated;

-- Instante vindo da tela: "2026-10-05T14:30" (sem fuso = São Paulo) ou ISO com fuso ("…Z", "…-03:00"). Nulo se inválido.
create function mkt_mensageria.instante(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
declare
  v text := btrim(coalesce(p, ''));
begin
  if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?$' then
    return null;
  end if;
  if v ~ '(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then return v::timestamptz; end if;
  return v::timestamp at time zone 'America/Sao_Paulo';
exception when others then
  return null;
end
$$;
revoke all on function mkt_mensageria.instante(text) from public, anon, authenticated;

-- Pendências de um disparo (a tela mostra o selo; os totais contam). Mesma regra em todo lugar.
--   sem_custo: custo não lançado · sem_retorno: entregues ou lidas não lançadas · conferir_zero_leitura: 0 lidas com custo
create function mkt_mensageria.pendencias(p_entregues integer, p_lidas integer, p_custo integer) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null then 'sem_custo' end,
    case when p_entregues is null or p_lidas is null then 'sem_retorno' end,
    case when p_lidas = 0 and p_custo > 0 then 'conferir_zero_leitura' end], null);
$$;
revoke all on function mkt_mensageria.pendencias(integer, integer, integer) from public, anon, authenticated;

-- ─── 3. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt_mensageria.ferramentas (
  id                     bigint generated always as identity primary key,
  nome                   text not null check (nome = btrim(nome) and length(nome) between 1 and 60),
  api                    text not null check (api in ('sim', 'futura', 'nao')),
  custo_mensal_centavos  integer check (custo_mensal_centavos is null or custo_mensal_centavos >= 0),   -- nulo = não lançado
  responsavel            text check (responsavel is null or length(btrim(responsavel)) between 1 and 80),
  ativa                  boolean not null default true,
  obs                    text check (obs is null or length(obs) <= 1000),
  criado_em              timestamptz not null default now(),
  criado_por             uuid references public.perfis(id) on delete set null,
  atualizado_em          timestamptz not null default now(),
  atualizado_por         uuid references public.perfis(id) on delete set null
);
-- Único sem diferenciar maiúscula: a planilha acha a ferramenta pelo nome, sem diferenciar maiúscula.
create unique index ferramentas_nome_unico on mkt_mensageria.ferramentas (lower(nome));
comment on table mkt_mensageria.ferramentas is 'Ferramentas de disparo e apoio. api: sim (integra), futura (vai integrar), nao (registro manual). Custo mensal nulo = não lançado.';

create table mkt_mensageria.numeros (
  id              bigint generated always as identity primary key,
  numero          text not null unique check (numero ~ '^\+[1-9][0-9]{7,14}$'),   -- E.164
  projeto_id      bigint references mkt.projetos(id) on delete restrict,
  frente          text check (frente is null or length(btrim(frente)) between 1 and 60),
  responsavel     text not null check (length(btrim(responsavel)) between 1 and 80),
  finalidade      text not null check (finalidade in ('mensageria', 'comercial', 'financeiro', 'suporte')),
  ferramenta_id   bigint references mkt_mensageria.ferramentas(id) on delete restrict,
  capacidade_dia  smallint check (capacidade_dia is null or capacidade_dia between 1 and 1000),   -- nulo = não definida
  status          text not null check (status in ('ativo', 'aquecendo', 'restrito', 'disponivel')),
  status_desde    timestamptz not null default now(),     -- trigger carimba quando o status muda
  arquivado_em    timestamptz,
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null
);
comment on table mkt_mensageria.numeros is 'Números de WhatsApp/SMS. consumo do dia NÃO é coluna: vem do log (mkt_msg_numeros_listar).';

create table mkt_mensageria.importacoes (
  id          bigint generated always as identity primary key,
  arquivo     text check (arquivo is null or length(arquivo) <= 255),
  linhas      integer not null check (linhas between 1 and 2000),
  criado_por  uuid references public.perfis(id) on delete set null,
  criado_em   timestamptz not null default now()
);
comment on table mkt_mensageria.importacoes is 'Cada importação de planilha confirmada (tudo ou nada). disparos.importacao_id aponta para cá.';

create table mkt_mensageria.disparos (
  id                bigint generated always as identity primary key,
  enviado_em        timestamptz not null,
  projeto_id        bigint not null references mkt.projetos(id) on delete restrict,
  canal             text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  ferramenta_id     bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  numero_id         bigint references mkt_mensageria.numeros(id) on delete restrict,
  tipo              text check (tipo is null or tipo in ('utility', 'marketing')),
  copy_texto        text check (copy_texto is null or length(copy_texto) <= 4000),
  copy_link         text check (copy_link is null or length(copy_link) <= 2000),
  publico_lista     text not null check (length(btrim(publico_lista)) between 1 and 200),
  publico_origem    text check (publico_origem is null or length(publico_origem) <= 200),
  tamanho_lista     integer not null check (tamanho_lista >= 0),
  -- Retorno e custo: SEM DEFAULT. Nulo = não lançado; 0 = lançado e deu zero.
  entregues         integer check (entregues is null or entregues >= 0),
  lidas             integer check (lidas is null or lidas >= 0),
  cliques           integer check (cliques is null or cliques >= 0),
  falhas            integer check (falhas is null or falhas >= 0),
  custo_centavos    integer check (custo_centavos is null or custo_centavos >= 0),
  disparado_por     text not null check (length(btrim(disparado_por)) between 1 and 80),
  retorno_em        timestamptz,
  origem            text not null default 'manual' check (origem in ('manual', 'planilha', 'api')),
  origem_sistema    text check (origem_sistema is null or length(btrim(origem_sistema)) between 1 and 60),
  id_externo        text check (id_externo is null or length(btrim(id_externo)) between 1 and 200),
  importacao_id     bigint references mkt_mensageria.importacoes(id) on delete restrict,
  arquivado_em      timestamptz,
  arquivado_motivo  text check (arquivado_motivo is null or length(btrim(arquivado_motivo)) between 3 and 500),
  criado_em         timestamptz not null default now(),
  criado_por        uuid references public.perfis(id) on delete set null,
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid references public.perfis(id) on delete set null,
  constraint disparos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  constraint disparos_copy_obrigatoria check (nullif(btrim(copy_texto), '') is not null or nullif(btrim(copy_link), '') is not null),
  constraint disparos_entregues_falhas check (coalesce(entregues, 0)::bigint + coalesce(falhas, 0) <= tamanho_lista),
  constraint disparos_lidas_entregues check (lidas is null or entregues is null or lidas <= entregues),
  constraint disparos_cliques_entregues check (cliques is null or entregues is null or cliques <= entregues),
  constraint disparos_externo_com_sistema check (id_externo is null or origem_sistema is not null),
  -- Chave externa só para integração (origem 'api'). Tela (manual) e planilha não gravam: não colidem com a da API.
  constraint disparos_externo_so_api check (origem = 'api' or (origem_sistema is null and id_externo is null)),
  constraint disparos_importacao_planilha check (importacao_id is null or origem = 'planilha'),
  constraint disparos_arquivo_com_motivo check ((arquivado_em is null) = (arquivado_motivo is null))
);
create unique index disparos_externo_unico on mkt_mensageria.disparos (origem_sistema, id_externo) where id_externo is not null;
create index disparos_enviado_idx on mkt_mensageria.disparos (enviado_em desc);
create index disparos_projeto_enviado_idx on mkt_mensageria.disparos (projeto_id, enviado_em desc);
create index disparos_numero_enviado_idx on mkt_mensageria.disparos (numero_id, enviado_em);
comment on table mkt_mensageria.disparos is 'Log central de disparos (todo canal, toda ferramenta). Retorno/custo nulo = não lançado. Arquivar, nunca apagar.';
comment on column mkt_mensageria.disparos.tipo is 'Categoria da mensagem na API oficial do WhatsApp (utility, marketing). Só existe em canal whatsapp_api.';
comment on column mkt_mensageria.disparos.retorno_em is 'Quando o retorno (entregues, lidas, cliques, falhas, custo) foi lançado pela última vez.';
comment on column mkt_mensageria.disparos.id_externo is 'Id no sistema de origem. Só origem api (integração futura); imutável depois de gravado. Único por origem_sistema: reenvio não duplica.';

create table mkt_mensageria.historico (
  id           bigint generated always as identity primary key,
  tabela       text not null check (tabela in ('disparos', 'numeros', 'ferramentas')),
  registro_id  text not null,
  acao         text not null check (acao in ('inserir', 'alterar', 'arquivar', 'anonimizar')),
  antes        jsonb,
  depois       jsonb,
  por          uuid,                                   -- auth.uid(); sem FK: o histórico sobrevive ao perfil
  em           timestamptz not null default now()
);
create index historico_registro_idx on mkt_mensageria.historico (tabela, registro_id, em desc);
comment on table mkt_mensageria.historico is 'Toda inserção/alteração/arquivamento em disparos, numeros e ferramentas (trigger). Linha inteira antes/depois.';

alter table mkt_mensageria.ferramentas enable row level security;
alter table mkt_mensageria.numeros enable row level security;
alter table mkt_mensageria.importacoes enable row level security;
alter table mkt_mensageria.disparos enable row level security;
alter table mkt_mensageria.historico enable row level security;
revoke all on mkt_mensageria.ferramentas, mkt_mensageria.numeros, mkt_mensageria.importacoes, mkt_mensageria.disparos,
              mkt_mensageria.historico from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Triggers: carimbo, status_desde, histórico, sem DELETE ───────────────────────────────────────────────────────
create function mkt_mensageria.trg_carimbo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := coalesce(new.criado_por, auth.uid());
    new.atualizado_em := new.criado_em;
    new.atualizado_por := new.criado_por;
  else
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
    new.atualizado_em := now();
    new.atualizado_por := auth.uid();
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_carimbo() from public, anon, authenticated;

create function mkt_mensageria.trg_numero_status() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.status_desde := now();
  elsif new.status is distinct from old.status then
    new.status_desde := now();
  else
    new.status_desde := old.status_desde;
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_numero_status() from public, anon, authenticated;

-- Grava a linha inteira antes/depois. UPDATE que só muda o carimbo não gera linha. arquivado_em nulo→preenchido = arquivar.
-- Durante a anonimização (flag local à transação, ligada só por mkt_msg_anonimizar_disparo) não grava: a própria função
-- registra a linha 'anonimizar', sem o dado pessoal no "antes".
create function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, auth.uid());
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Bloqueio (42501): DELETE (linha) e TRUNCATE (comando) nas 5 tabelas; UPDATE em historico e importacoes.
-- Única exceção: UPDATE em historico com a flag de anonimização ligada, e só em antes/depois (id, tabela, registro,
-- ação, autor e data não mudam).
create function mkt_mensageria.trg_bloqueio() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'historico'
     and coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    if (new.id, new.tabela, new.registro_id, new.acao, new.por, new.em)
       is not distinct from (old.id, old.tabela, old.registro_id, old.acao, old.por, old.em) then
      return new;
    end if;
  end if;
  raise exception 'mkt_mensageria.%: % não é permitido (o registro é permanente: arquivar ou desativar)', tg_table_name, tg_op
    using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_bloqueio() from public, anon, authenticated;

-- Procedência do disparo não muda depois de gravada (nem pela tela, nem por update direto).
create function mkt_mensageria.trg_disparo_procedencia() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.origem, new.origem_sistema, new.id_externo, new.importacao_id)
     is distinct from (old.origem, old.origem_sistema, old.id_externo, old.importacao_id) then
    raise exception 'mkt_mensageria.disparos: origem, origem_sistema, id_externo e importacao_id não mudam depois de gravados'
      using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_disparo_procedencia() from public, anon, authenticated;

create trigger a_carimbo before insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger a_carimbo before insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_carimbo();
create trigger b_status before insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_numero_status();
create trigger b_procedencia before update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_disparo_procedencia();
create trigger z_historico after insert or update on mkt_mensageria.ferramentas
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.numeros
  for each row execute function mkt_mensageria.trg_historico();
create trigger z_historico after insert or update on mkt_mensageria.disparos
  for each row execute function mkt_mensageria.trg_historico();
do $bloqueio$
declare t text;
begin
  foreach t in array array['ferramentas', 'numeros', 'disparos', 'importacoes', 'historico'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;
create trigger sem_update before update on mkt_mensageria.importacoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.historico
  for each row execute function mkt_mensageria.trg_bloqueio();

-- ─── 5. Seed: 13 ferramentas, custos não lançados ────────────────────────────────────────────────────────────────────
insert into mkt_mensageria.ferramentas (nome, api) values
  ('SendFlow', 'sim'), ('Unichat', 'sim'), ('ActiveCampaign', 'sim'), ('n8n', 'sim'), ('Google Drive', 'sim'),
  ('Slack', 'sim'), ('ClickUp', 'sim'),
  ('Infobip', 'nao'), ('Clint', 'nao'), ('Ligue Lead', 'nao'), ('Encurtador', 'nao'), ('Respondi', 'nao'), ('ManyChat', 'nao');

-- ─── 6. Validação de disparo (uma regra para a tela e para a planilha) ───────────────────────────────────────────────
-- Entrada (texto): enviado_em, projeto (sigla), canal, ferramenta_id, numero_id, tipo, copy_texto, copy_link,
--   publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por.
--   origem_sistema/id_externo NÃO entram (só integração, origem 'api'). Ferramenta desativada e número arquivado: recusa.
--   Saída: {erros:[{campo,msg}], v:{… valores já convertidos, projeto_id …}}.
create function mkt_mensageria.disparo_validar(p jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_enviado timestamptz := mkt_mensageria.instante(p ->> 'enviado_em');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_projeto bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_num_txt text := btrim(coalesce(p ->> 'numero_id', ''));
  v_num bigint;
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_copy text := nullif(btrim(coalesce(p ->> 'copy_texto', '')), '');
  v_link text := nullif(btrim(coalesce(p ->> 'copy_link', '')), '');
  v_lista text := btrim(coalesce(p ->> 'publico_lista', ''));
  v_origem_lista text := nullif(btrim(coalesce(p ->> 'publico_origem', '')), '');
  v_tam bigint := mkt_mensageria.inteiro(p ->> 'tamanho_lista');
  v_ent bigint := mkt_mensageria.inteiro(p ->> 'entregues');
  v_lid bigint := mkt_mensageria.inteiro(p ->> 'lidas');
  v_cli bigint := mkt_mensageria.inteiro(p ->> 'cliques');
  v_fal bigint := mkt_mensageria.inteiro(p ->> 'falhas');
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_centavos');
  v_por text := btrim(coalesce(p ->> 'disparado_por', ''));
  v_ferr_ativa boolean;
  v_ferr_nome text;
  v_num_arq timestamptz;
  v_num_txt2 text;
  v_numeros_ok boolean := true;
begin
  if v_enviado is null then
    e := e || jsonb_build_object('campo', 'enviado_em', 'msg', 'Informe a data e a hora do envio.');
  end if;

  if v_sigla = '' then
    e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
  else
    select pr.id into v_projeto from mkt.projetos pr where pr.sigla = v_sigla;
    if v_projeto is null then
      e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
    end if;
  end if;

  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  end if;

  if v_ferr_txt !~ '^[0-9]{1,18}$' then
    e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.');
  else
    select f.id, f.ativa, f.nome into v_ferr, v_ferr_ativa, v_ferr_nome
      from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Ferramenta não cadastrada.');
    elsif not v_ferr_ativa then
      e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg',
        'Ferramenta ' || v_ferr_nome || ' está desativada: reative em Ferramentas ou escolha outra.');
    end if;
  end if;

  if v_num_txt <> '' then
    if v_num_txt ~ '^[0-9]{1,18}$' then
      select n.id, n.arquivado_em, n.numero into v_num, v_num_arq, v_num_txt2
        from mkt_mensageria.numeros n where n.id = v_num_txt::bigint;
    end if;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg', 'Número não cadastrado em Números.');
    elsif v_num_arq is not null then
      e := e || jsonb_build_object('campo', 'numero_id', 'msg',
        'Número ' || v_num_txt2 || ' está arquivado: desarquive em Números ou escolha outro.');
    end if;
  end if;

  if v_canal = 'whatsapp_api' and v_tipo is null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal in ('email', 'sms', 'ligacao', 'grupo') and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  elsif v_tipo is not null and v_tipo not in ('utility', 'marketing') then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo inválido: utility ou marketing.');
  end if;

  if v_copy is null and v_link is null then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Informe a copy: o texto, o link, ou os dois.');
  end if;
  if length(v_copy) > 4000 then
    e := e || jsonb_build_object('campo', 'copy_texto', 'msg', 'Texto da copy passa de 4.000 caracteres.');
  end if;
  if length(v_link) > 2000 then
    e := e || jsonb_build_object('campo', 'copy_link', 'msg', 'Link passa de 2.000 caracteres.');
  end if;

  if v_lista = '' or length(v_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_lista', 'msg', 'Informe a lista (público), até 200 caracteres.');
  end if;
  if length(v_origem_lista) > 200 then
    e := e || jsonb_build_object('campo', 'publico_origem', 'msg', 'Origem da lista passa de 200 caracteres.');
  end if;

  if v_tam is null then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Informe o tamanho da lista.');
    v_numeros_ok := false;
  elsif v_tam < 0 then
    e := e || jsonb_build_object('campo', 'tamanho_lista', 'msg', 'Tamanho da lista: número inteiro, sem sinal.');
    v_numeros_ok := false;
  end if;
  if v_ent < 0 then e := e || jsonb_build_object('campo', 'entregues', 'msg', 'Entregues: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_lid < 0 then e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_cli < 0 then e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_fal < 0 then e := e || jsonb_build_object('campo', 'falhas', 'msg', 'Falhas: número inteiro ≥ 0, ou vazio se ainda não lançado.'); v_numeros_ok := false; end if;
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
  end if;

  if v_numeros_ok then
    if coalesce(v_ent, 0) + coalesce(v_fal, 0) > v_tam then
      e := e || jsonb_build_object('campo', 'entregues', 'msg',
        'Entregues + falhas (' || (coalesce(v_ent, 0) + coalesce(v_fal, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
    end if;
    if v_lid > v_ent then
      e := e || jsonb_build_object('campo', 'lidas', 'msg', 'Lidas (' || v_lid || ') não pode passar de entregues (' || v_ent || ').');
    end if;
    if v_cli > v_ent then
      e := e || jsonb_build_object('campo', 'cliques', 'msg', 'Cliques (' || v_cli || ') não pode passar de entregues (' || v_ent || ').');
    end if;
  end if;

  if v_por = '' or length(v_por) > 80 then
    e := e || jsonb_build_object('campo', 'disparado_por', 'msg', 'Informe quem disparou (até 80 caracteres).');
  end if;

  return jsonb_build_object('erros', e, 'v', jsonb_build_object(
    'enviado_em', v_enviado, 'projeto_id', v_projeto, 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', v_copy, 'copy_link', v_link, 'publico_lista', v_lista, 'publico_origem', v_origem_lista,
    'tamanho_lista', v_tam, 'entregues', v_ent, 'lidas', v_lid, 'cliques', v_cli, 'falhas', v_fal,
    'custo_centavos', v_custo, 'disparado_por', v_por));
end
$$;
revoke all on function mkt_mensageria.disparo_validar(jsonb) from public, anon, authenticated;

-- Uma linha de planilha → mesma validação. Colunas: data (dd/mm/aaaa), hora (hh:mm), projeto (sigla), canal (código ou
-- rótulo), ferramenta (nome, sem diferenciar maiúscula), numero (+55…; vazio = sem número), tipo, copy_texto, copy_link,
-- publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas ("1.234"), custo ("1.234,56" reais),
-- disparado_por. Saída: {linha, erros:[{linha,campo,msg}], v:{…}}. campo = nome da coluna da planilha.
create function mkt_mensageria.importar_linha(l jsonb, n integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_canon jsonb;
  r jsonb;
  x jsonb;
  v_ja text[] := '{}';
  v_quando timestamptz;
  v_txt text;
  v_ferr bigint;
  v_num bigint;
  v_custo bigint;
  v_canal text;
  v_tipo text;
  k text;
  v_map jsonb := '{"enviado_em":"data","ferramenta_id":"ferramenta","numero_id":"numero","custo_centavos":"custo"}';
begin
  if l is null or jsonb_typeof(l) <> 'object' then
    return jsonb_build_object('linha', n, 'erros', jsonb_build_array(jsonb_build_object('linha', n, 'campo', '-', 'msg', 'Linha em formato inválido.')), 'v', null);
  end if;

  if btrim(coalesce(l ->> 'data', '')) !~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then
    e := e || jsonb_build_object('campo', 'data', 'msg', 'Data inválida: use dd/mm/aaaa.'); v_ja := array_append(v_ja, 'enviado_em');
  elsif btrim(coalesce(l ->> 'hora', '')) !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
    e := e || jsonb_build_object('campo', 'hora', 'msg', 'Hora inválida: use hh:mm (00:00 a 23:59).'); v_ja := array_append(v_ja, 'enviado_em');
  else
    v_quando := mkt_mensageria.data_hora_br(l ->> 'data', l ->> 'hora');
    if v_quando is null then
      e := e || jsonb_build_object('campo', 'data', 'msg', 'Data não existe: ' || btrim(l ->> 'data') || '.'); v_ja := array_append(v_ja, 'enviado_em');
    end if;
  end if;

  v_txt := btrim(coalesce(l ->> 'ferramenta', ''));
  if v_txt = '' then
    e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Informe a ferramenta.'); v_ja := array_append(v_ja, 'ferramenta_id');
  else
    select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
    if v_ferr is null then
      e := e || jsonb_build_object('campo', 'ferramenta', 'msg', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.'); v_ja := array_append(v_ja, 'ferramenta_id');
    end if;
  end if;

  v_txt := regexp_replace(coalesce(l ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      e := e || jsonb_build_object('campo', 'numero', 'msg', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.'); v_ja := array_append(v_ja, 'numero_id');
    end if;
  end if;

  v_custo := mkt_mensageria.centavos_br(l ->> 'custo');
  if v_custo < 0 then
    e := e || jsonb_build_object('campo', 'custo', 'msg', 'Custo inválido: use reais, como 1.234,56 (ou vazio se não lançado).');
    v_ja := array_append(v_ja, 'custo_centavos'); v_custo := null;
  end if;

  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'canal', '')));
  v_canal := case when v_txt in ('WHATSAPP_API', 'API WHATSAPP', 'WHATSAPP API', 'API') then 'whatsapp_api'
                  when v_txt in ('EMAIL', 'E-MAIL') then 'email'
                  when v_txt = 'SMS' then 'sms'
                  when v_txt in ('LIGACAO', 'LIGACOES') then 'ligacao'
                  when v_txt in ('GRUPO', 'GRUPOS') then 'grupo'
                  else lower(v_txt) end;
  v_txt := mkt.sem_acento(btrim(coalesce(l ->> 'tipo', '')));
  v_tipo := case when v_txt in ('UTILITY', 'UTILIDADE') then 'utility' when v_txt = 'MARKETING' then 'marketing'
                 else nullif(lower(v_txt), '') end;

  v_canon := jsonb_build_object(
    'enviado_em', v_quando, 'projeto', l ->> 'projeto', 'canal', v_canal, 'ferramenta_id', v_ferr, 'numero_id', v_num,
    'tipo', v_tipo, 'copy_texto', l ->> 'copy_texto', 'copy_link', l ->> 'copy_link', 'publico_lista', l ->> 'publico_lista',
    'publico_origem', l ->> 'publico_origem', 'disparado_por', l ->> 'disparado_por', 'custo_centavos', v_custo);
  foreach k in array array['tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas'] loop
    -- "1.234" vira "1234"; formato errado segue cru e a validação acusa.
    v_canon := v_canon || jsonb_build_object(k, case when mkt_mensageria.inteiro_br(l ->> k) >= 0
                                                     then mkt_mensageria.inteiro_br(l ->> k)::text else l ->> k end);
  end loop;

  r := mkt_mensageria.disparo_validar(v_canon);
  for x in select * from jsonb_array_elements(r -> 'erros') loop
    if not (x ->> 'campo' = any(v_ja)) then
      e := e || jsonb_build_object('campo', coalesce(v_map ->> (x ->> 'campo'), x ->> 'campo'), 'msg', x ->> 'msg');
    end if;
  end loop;

  return jsonb_build_object('linha', n,
    'erros', (select coalesce(jsonb_agg(jsonb_build_object('linha', n) || y), '[]'::jsonb) from jsonb_array_elements(e) y),
    'v', case when jsonb_array_length(e) = 0 then r -> 'v' end);
end
$$;
revoke all on function mkt_mensageria.importar_linha(jsonb, integer) from public, anon, authenticated;

-- ─── 7. Funções públicas (RPC). Toda uma: guarda mkt.pode_ver('mkt_mensageria') + revoke/grant logo abaixo ──────────

-- Lista do período. Ver contrato em 20261005n.explain.md. plan_cache_mode: cada chamada planeja com os valores reais,
-- então "(v_proj is null or projeto_id = v_proj)" vira "projeto_id = 5" e o índice (projeto_id, enviado_em) entra.
create function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                               p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, mkt_mensageria.pendencias(d.entregues, d.lidas, d.custo_centavos) as pendencias
        from mkt_mensageria.disparos d
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias))
               order by b.enviado_em desc, b.id desc)
          from pagina b
          join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo, count(*) filter (where b.custo_centavos is null) as sem_custo
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: ver mkt_mensageria.disparo_validar. Retorna {ok, msg, id, erros?}.
-- origem é sempre 'manual'; origem_sistema/id_externo vindos no JSON são ignorados (não grava nem altera).
-- Na edição, retorno_em é carimbado se entregues/lidas/cliques/falhas/custo mudaram. Arquivado não se edita.
create function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Arquiva (some da lista e dos totais; fica no banco e no histórico). Motivo obrigatório. Nunca apaga.
create function public.mkt_msg_disparo_arquivar(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo do arquivamento (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.disparos set arquivado_em = now(), arquivado_motivo = v_motivo
   where id = p_id and arquivado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.disparos where id = p_id) then 'Disparo já arquivado.'
      else 'Disparo não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Disparo arquivado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_disparo_arquivar(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_arquivar(bigint, text) to authenticated;

-- Lança o retorno de um disparo. Os 5 valores substituem os atuais; nulo = não lançado (nunca vira 0).
-- retorno_em = agora; se os 5 vierem nulos, retorno_em volta a nulo.
create function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                      p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista into v_tam from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
                            'pendencias', to_jsonb(mkt_mensageria.pendencias(p_entregues, p_lidas, p_custo_centavos)));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Importa planilha. p_confirmar=false: só valida e devolve {ok, erros, validas, total, duplicadas_banco, duplicadas_lote}.
-- p_confirmar=true: tudo ou nada; com qualquer erro, nada entra. Com possível duplicata (já no log, ou repetida no
-- próprio lote: mesma data/hora, projeto, canal e lista) também nada entra, a menos que p_aceitar_duplicadas=true.
-- Máx. 2.000 linhas. A planilha não grava origem_sistema/id_externo (ver 20261005n.explain.md). Colunas em importar_linha.
create function public.mkt_msg_importar(p_linhas jsonb, p_confirmar boolean default false, p_arquivo text default null,
                                        p_aceitar_duplicadas boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer;
  v_res jsonb[];
  v_erros jsonb;
  v_qtd_erros integer;
  v_validas integer;
  v_dup_banco jsonb;
  v_dup_lote jsonb;
  v_tem_dup boolean;
  v_imp bigint;
  v_ins integer;
  v_con text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Nenhuma linha para importar.', 'erros', '[]'::jsonb, 'validas', 0, 'total', 0);
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n > 2000 then
    return jsonb_build_object('ok', false, 'msg', 'Máximo de 2.000 linhas por importação (vieram ' || v_n || '). Divida a planilha.',
                              'erros', '[]'::jsonb, 'validas', 0, 'total', v_n);
  end if;
  -- Duas confirmações ao mesmo tempo não passam juntas: a segunda espera a primeira e então vê as duplicatas dela.
  if coalesce(p_confirmar, false) then
    perform pg_advisory_xact_lock(hashtext('mkt_mensageria.importar'));
  end if;

  select array_agg(mkt_mensageria.importar_linha(t.l, t.n::int) order by t.n) into v_res
    from jsonb_array_elements(p_linhas) with ordinality t(l, n);

  select count(*), coalesce(jsonb_agg(x.e order by x.linha, x.o) filter (where x.rn <= 500), '[]'::jsonb)
    into v_qtd_erros, v_erros
    from (select (r ->> 'linha')::int as linha, e.o, e.e, row_number() over (order by (r ->> 'linha')::int, e.o) as rn
            from unnest(v_res) r, jsonb_array_elements(r -> 'erros') with ordinality e(e, o)) x;
  select count(*) into v_validas from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object';

  -- Duplicata contra o banco: mesma data/hora, projeto, canal e lista já no log (não arquivado). Índice (projeto_id, enviado_em).
  select coalesce(jsonb_agg((r ->> 'linha')::int order by (r ->> 'linha')::int), '[]'::jsonb) into v_dup_banco
    from unnest(v_res) r
   where jsonb_typeof(r -> 'v') = 'object'
     and exists (select 1 from mkt_mensageria.disparos d
                  where d.projeto_id = (r -> 'v' ->> 'projeto_id')::bigint
                    and d.enviado_em = (r -> 'v' ->> 'enviado_em')::timestamptz
                    and d.canal = r -> 'v' ->> 'canal'
                    and d.publico_lista = r -> 'v' ->> 'publico_lista'
                    and d.arquivado_em is null);
  -- Duplicata dentro do lote: todas as linhas de um grupo repetido.
  select coalesce(jsonb_agg(x.linha order by x.linha), '[]'::jsonb) into v_dup_lote
    from (select (r ->> 'linha')::int as linha,
                 count(*) over (partition by r -> 'v' ->> 'projeto_id', (r -> 'v' ->> 'enviado_em')::timestamptz,
                                             r -> 'v' ->> 'canal', r -> 'v' ->> 'publico_lista') as qtd
            from unnest(v_res) r where jsonb_typeof(r -> 'v') = 'object') x
   where x.qtd > 1;
  v_tem_dup := jsonb_array_length(v_dup_banco) > 0 or jsonb_array_length(v_dup_lote) > 0;

  if not coalesce(p_confirmar, false) or v_qtd_erros > 0 then
    return jsonb_build_object('ok', v_qtd_erros = 0,
      'msg', case when v_qtd_erros > 0 then v_qtd_erros || ' erro(s) em ' || (v_n - v_validas) || ' linha(s). Nada foi gravado.'
                  when v_tem_dup then v_validas || ' linhas válidas, com possível duplicata (veja as linhas). Nada foi gravado ainda.'
                  else v_validas || ' linhas válidas. Nada foi gravado ainda.' end,
      'erros', v_erros, 'erros_total', v_qtd_erros, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;
  if v_tem_dup and not coalesce(p_aceitar_duplicadas, false) then
    return jsonb_build_object('ok', false,
      'msg', 'Possível duplicata: ' || jsonb_array_length(v_dup_banco) || ' linha(s) já no registro e '
             || jsonb_array_length(v_dup_lote) || ' repetida(s) na planilha. Nada foi gravado. Confira e, se estiver certo, '
             || 'confirme de novo marcando "importar mesmo assim".',
      'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_validas, 'total', v_n,
      'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
  end if;

  begin
    insert into mkt_mensageria.importacoes (arquivo, linhas, criado_por)
    values (nullif(left(btrim(coalesce(p_arquivo, '')), 255), ''), v_n, (select auth.uid()))
    returning id into v_imp;

    insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, importacao_id)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'planilha', v_imp
      from (select r -> 'v' as v, (r ->> 'linha')::int as linha from unnest(v_res) r) s
     order by s.linha;
    get diagnostics v_ins = row_count;
  exception
    when check_violation or foreign_key_violation or not_null_violation or unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Nada foi importado: valor fora da regra (' || coalesce(v_con, 'dados') || ').',
                                'erros', '[]'::jsonb, 'validas', v_validas, 'total', v_n);
  end;
  return jsonb_build_object('ok', true, 'msg', v_ins || ' disparos importados.', 'importacao_id', v_imp,
                            'erros', '[]'::jsonb, 'erros_total', 0, 'validas', v_ins, 'total', v_n,
                            'duplicadas_banco', v_dup_banco, 'duplicadas_lote', v_dup_lote);
end
$$;
revoke all on function public.mkt_msg_importar(jsonb, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.mkt_msg_importar(jsonb, boolean, text, boolean) to authenticated;

-- Números com consumo de hoje (America/Sao_Paulo) somado do log. Uma query; por número, um lookup no índice
-- (numero_id, enviado_em) restrito ao dia. Arquivados vêm por último, com arquivado_em preenchido.
create function public.mkt_msg_numeros_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini timestamptz := v_hoje::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (v_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'numeros', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', n.id, 'numero', n.numero, 'projeto_id', n.projeto_id, 'projeto', pr.sigla, 'frente', n.frente,
             'responsavel', n.responsavel, 'finalidade', n.finalidade, 'ferramenta_id', n.ferramenta_id,
             'ferramenta', f.nome, 'capacidade_dia', n.capacidade_dia, 'status', n.status, 'status_desde', n.status_desde,
             'arquivado_em', n.arquivado_em, 'consumo_hoje', coalesce(c.total, 0),
             'acima_da_capacidade', n.capacidade_dia is not null and coalesce(c.total, 0) > n.capacidade_dia,
             'atualizado_em', n.atualizado_em)
           order by (n.arquivado_em is not null), array_position(array['ativo', 'aquecendo', 'restrito', 'disponivel'], n.status), n.numero),
           '[]'::jsonb)
      from mkt_mensageria.numeros n
      left join mkt.projetos pr on pr.id = n.projeto_id
      left join mkt_mensageria.ferramentas f on f.id = n.ferramenta_id
      left join lateral (select sum(d.tamanho_lista) as total
                           from mkt_mensageria.disparos d
                          where d.numero_id = n.id and d.enviado_em >= v_ini and d.enviado_em < v_fim
                            and d.arquivado_em is null) c on true));
end
$$;
revoke all on function public.mkt_msg_numeros_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_numeros_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: numero (+55 11 99999-0000: espaços, traços e parênteses saem; o "+" e o
-- código do país são obrigatórios), projeto (sigla, opcional), frente, responsavel, finalidade, ferramenta_id,
-- capacidade_dia (1 a 1000, opcional), status, arquivado (bool). Retorna {ok, msg, id}.
create function public.mkt_msg_numero_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_numero text := regexp_replace(coalesce(p ->> 'numero', ''), '[\s().-]', '', 'g');
  v_sigla text := upper(btrim(coalesce(p ->> 'projeto', '')));
  v_proj bigint;
  v_frente text := nullif(btrim(coalesce(p ->> 'frente', '')), '');
  v_resp text := btrim(coalesce(p ->> 'responsavel', ''));
  v_fin text := lower(btrim(coalesce(p ->> 'finalidade', '')));
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_cap bigint := mkt_mensageria.inteiro(p ->> 'capacidade_dia');
  v_status text := lower(btrim(coalesce(p ->> 'status', '')));
  v_arq boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados do número ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_arq := coalesce(nullif(p ->> 'arquivado', '')::boolean, false);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "arquivado" deve ser verdadeiro ou falso.');
  end;
  if v_numero !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok', false, 'msg', 'Número no formato internacional, com + e código do país (ex.: +55 11 99999-0000).');
  end if;
  if v_sigla <> '' then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
    if v_proj is null then return jsonb_build_object('ok', false, 'msg', 'Projeto ' || v_sigla || ' não cadastrado.'); end if;
  end if;
  if length(v_frente) > 60 then return jsonb_build_object('ok', false, 'msg', 'Frente: até 60 caracteres.'); end if;
  if v_resp = '' or length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Informe o responsável (até 80 caracteres).'); end if;
  if v_fin not in ('mensageria', 'comercial', 'financeiro', 'suporte') then
    return jsonb_build_object('ok', false, 'msg', 'Finalidade: mensageria, comercial, financeiro ou suporte.');
  end if;
  if v_ferr_txt <> '' then
    if v_ferr_txt ~ '^[0-9]{1,18}$' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
    end if;
    if v_ferr is null then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não cadastrada.'); end if;
  end if;
  if v_cap is not null and (v_cap < 1 or v_cap > 1000) then
    return jsonb_build_object('ok', false, 'msg', 'Capacidade por dia: de 1 a 1.000 (ou vazio se não definida).');
  end if;
  if v_status not in ('ativo', 'aquecendo', 'restrito', 'disponivel') then
    return jsonb_build_object('ok', false, 'msg', 'Status: ativo, aquecendo, restrito ou disponível.');
  end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.numeros (numero, projeto_id, frente, responsavel, finalidade, ferramenta_id, capacidade_dia,
                                          status, arquivado_em)
      values (v_numero, v_proj, v_frente, v_resp, v_fin, v_ferr, v_cap::smallint, v_status, case when v_arq then now() end)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' cadastrado.', 'id', v_id);
    end if;
    update mkt_mensageria.numeros n
       set numero = v_numero, projeto_id = v_proj, frente = v_frente, responsavel = v_resp, finalidade = v_fin,
           ferramenta_id = v_ferr, capacidade_dia = v_cap::smallint, status = v_status,
           arquivado_em = case when v_arq then coalesce(n.arquivado_em, now()) end
     where n.id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Número não encontrado.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Número ' || v_numero || ' salvo.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Número ' || v_numero || ' já cadastrado.');
  end;
end
$$;
revoke all on function public.mkt_msg_numero_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_numero_salvar(jsonb) to authenticated;

create function public.mkt_msg_ferramentas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', f.id, 'nome', f.nome, 'api', f.api, 'custo_mensal_centavos', f.custo_mensal_centavos,
            'responsavel', f.responsavel, 'ativa', f.ativa, 'obs', f.obs, 'atualizado_em', f.atualizado_em)
          order by f.ativa desc, lower(f.nome)), '[]'::jsonb)
            from mkt_mensageria.ferramentas f);
end
$$;
revoke all on function public.mkt_msg_ferramentas_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramentas_listar() to authenticated;

-- Cria (sem "id") ou edita (com "id"). Campos: nome, api (sim|futura|nao), custo_mensal_centavos (inteiro ≥ 0; vazio =
-- não lançado), responsavel, ativa, obs. Ferramenta não se apaga: desativa (ativa=false). Retorna {ok, msg, id}.
create function public.mkt_msg_ferramenta_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_api text := lower(btrim(coalesce(p ->> 'api', '')));
  v_custo bigint := mkt_mensageria.inteiro(p ->> 'custo_mensal_centavos');
  v_resp text := nullif(btrim(coalesce(p ->> 'responsavel', '')), '');
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_ativa boolean;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados da ferramenta ausentes.'); end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Ferramenta inválida.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  begin
    v_ativa := coalesce(nullif(p ->> 'ativa', '')::boolean, true);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo "ativa" deve ser verdadeiro ou falso.');
  end;
  if v_nome = '' or length(v_nome) > 60 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome (até 60 caracteres).'); end if;
  if v_api not in ('sim', 'futura', 'nao') then
    return jsonb_build_object('ok', false, 'msg', 'API: sim, futura ou não.');
  end if;
  if v_custo < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Custo mensal: centavos, inteiro ≥ 0 (ou vazio se não lançado).');
  end if;
  if length(v_resp) > 80 then return jsonb_build_object('ok', false, 'msg', 'Responsável: até 80 caracteres.'); end if;
  if length(v_obs) > 1000 then return jsonb_build_object('ok', false, 'msg', 'Observação: até 1.000 caracteres.'); end if;

  begin
    if v_id is null then
      insert into mkt_mensageria.ferramentas (nome, api, custo_mensal_centavos, responsavel, ativa, obs)
      values (v_nome, v_api, v_custo::int, v_resp, v_ativa, v_obs)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' cadastrada.', 'id', v_id);
    end if;
    update mkt_mensageria.ferramentas
       set nome = v_nome, api = v_api, custo_mensal_centavos = v_custo::int, responsavel = v_resp, ativa = v_ativa, obs = v_obs
     where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Ferramenta não encontrada.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Ferramenta ' || v_nome || ' salva.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Já existe ferramenta com o nome ' || v_nome || '.');
  end;
end
$$;
revoke all on function public.mkt_msg_ferramenta_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_ferramenta_salvar(jsonb) to authenticated;

-- Histórico de um registro (até 200 mudanças, mais recente primeiro). p_tabela: disparos | numeros | ferramentas.
create function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', pf.nome, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- LGPD: apaga o conteúdo que pode ter dado pessoal (copy_texto, publico_lista, publico_origem) de UM disparo e de todas
-- as linhas do histórico dele, e registra a anonimização no histórico (acao 'anonimizar', com motivo, sem o conteúdo).
-- Só admin/dev (gp_is_admin), mesmo quando mkt.pode_ver for aberto a operador/gestor. Funciona com disparo arquivado.
-- Exceção controlada ao bloqueio de UPDATE do histórico: flag local à transação, desligada antes de sair.
create function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform 1 from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  f record;
  v_publicas text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                             'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                             'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                             'mkt_msg_historico', 'mkt_msg_anonimizar_disparo'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_mensageria', 'usage') or has_schema_privilege(r, 'mkt_mensageria', 'create') then
      raise exception '20261005n: % tem acesso ao schema mkt_mensageria', r;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005n: % tem privilégio em %', r, t;
      end if;
    end loop;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005n: RLS desligada em %', t;
    end if;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005n: PUBLIC tem privilégio em %', t;
    end if;
  end loop;

  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind = 'S' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_sequence_privilege(r, t, 'usage, select, update') then
        raise exception '20261005n: % tem privilégio na sequência %', r, t;
      end if;
    end loop;
  end loop;

  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005n: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005n: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005n: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_publicas))
       <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005n: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005n: % deveria ser SECURITY DEFINER', f.sig;
    end if;
    if f.proname = any(v_publicas) and f.proname <> 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda coalesce(mkt.pode_ver(''mkt_mensageria''), false)', f.sig;
    end if;
    if f.proname = 'mkt_msg_anonimizar_disparo'
       and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in f.prosrc) = 0 then
      raise exception '20261005n: % sem a guarda gp_is_admin', f.sig;
    end if;
    if f.pronamespace = 'mkt_mensageria'::regnamespace and f.prosecdef then
      raise exception '20261005n: interna % não deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 11
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 11 then
    raise exception '20261005n: esperava exatamente as 11 funções public.mkt_msg_* (sobrecarga?)';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria' and table_name = 'disparos'
                and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos') and column_default is not null) then
    raise exception '20261005n: retorno/custo com default (nulo tem que ser "não lançado")';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas) <> 13
     or exists (select 1 from mkt_mensageria.ferramentas where custo_mensal_centavos is not null) then
    raise exception '20261005n: seed diferente do esperado (13 ferramentas, custos nulos)';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; apaga TODO o log de disparos, números e histórico: exportar antes) ═══════════════════
-- begin;
-- drop function public.mkt_msg_disparos_listar(date, date, text, text, bigint), public.mkt_msg_disparo_salvar(jsonb),
--   public.mkt_msg_disparo_arquivar(bigint, text),
--   public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer),
--   public.mkt_msg_importar(jsonb, boolean, text, boolean), public.mkt_msg_numeros_listar(), public.mkt_msg_numero_salvar(jsonb),
--   public.mkt_msg_ferramentas_listar(), public.mkt_msg_ferramenta_salvar(jsonb), public.mkt_msg_historico(text, text),
--   public.mkt_msg_anonimizar_disparo(bigint, text);
-- drop schema mkt_mensageria cascade;   -- leva tabelas, triggers e as FKs para mkt.projetos (mkt.projetos fica intacta)
-- commit;
-- Desligar sem apagar dado: revoke execute on function public.mkt_msg_<…> from authenticated; (a tela recebe 42501).

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito) ═══════════════════════════
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projeto e ferramenta usados nos testes (os ids reais de produção; nada é escrito em mkt.projetos)
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as projeto_id,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign;
grant all on _z_ref to public;
-- Muda para "admin logado" (role authenticated + JWT do admin) e de volta para postgres.
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;

-- ═══ BLOCO 3: importação no teto (2.000 linhas) — tempo da prévia, da confirmação e do aviso de duplicata ═══════════
create temp table _z_linhas on commit drop as
select jsonb_agg(jsonb_build_object(
         'data', to_char(current_date - (i % 300), 'DD/MM/YYYY'), 'hora', lpad((i % 24)::text, 2, '0') || ':' || lpad((i % 60)::text, 2, '0'),
         'projeto', (select sigla from pg_temp._z_ref), 'canal', (array['API WhatsApp', 'E-mail', 'SMS', 'Ligação', 'Grupo'])[1 + i % 5],
         'tipo', case when i % 5 = 0 then (array['Utilidade', 'Marketing'])[1 + i % 2] else '' end,
         'ferramenta', (array['sendflow', 'ActiveCampaign', 'INFOBIP', 'Clint', 'ManyChat'])[1 + i % 5],
         'copy_texto', 'Copy importada ' || i, 'publico_lista', 'Lista ' || i, 'tamanho_lista', ((1000 + i) / 1000) || '.' || lpad(((1000 + i) % 1000)::text, 3, '0'),
         'entregues', case when i % 4 = 0 then '' else (900 + i % 50)::text end,
         'lidas', case when i % 4 = 0 then '' else (i % 100)::text end,
         'custo', case when i % 3 = 0 then '' else (i % 500) || ',' || lpad((i % 100)::text, 2, '0') end,
         'disparado_por', 'Ensaio') order by i) as linhas
  from generate_series(1, 2000) i;
grant all on _z_linhas to public;

select pg_temp.como_admin();
do $t$
declare
  t0 timestamptz;
  r jsonb;
  v_l jsonb := (select linhas from pg_temp._z_linhas);
begin
  t0 := clock_timestamp(); r := public.mkt_msg_importar(v_l, false, 'ensaio-2000.csv');
  if not (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 2000 then
    raise exception 'I1 FALHOU: prévia de 2.000: %', left(r::text, 2000);
  end if;
  perform pg_temp.ok('I1 prévia 2.000 linhas', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, validas=2000');

  t0 := clock_timestamp(); r := public.mkt_msg_importar(v_l, true, 'ensaio-2000.csv');
  if not (r ->> 'ok')::boolean or (r ->> 'validas')::int <> 2000 then
    raise exception 'I2 FALHOU: confirmar 2.000: %', left(r::text, 2000);
  end if;
  perform pg_temp.ok('I2 confirmar 2.000 linhas', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms (insert + 2.000 linhas de histórico)');

  t0 := clock_timestamp(); r := public.mkt_msg_importar(v_l, false, 'ensaio-2000.csv');
  if jsonb_array_length(r -> 'duplicadas_banco') <> 2000 then
    raise exception 'I3 FALHOU: reimportação: % duplicatas avisadas', jsonb_array_length(r -> 'duplicadas_banco');
  end if;
  perform pg_temp.ok('I3 prévia da mesma planilha de novo', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, 2000 duplicadas_banco listadas');
  t0 := clock_timestamp(); r := public.mkt_msg_importar(v_l, true, 'ensaio-2000.csv');
  if (r ->> 'ok')::boolean or jsonb_array_length(r -> 'duplicadas_banco') <> 2000 then
    raise exception 'I3b FALHOU: confirmou reimportação: %', left(r::text, 500);
  end if;
  perform pg_temp.ok('I3b confirmar a mesma planilha de novo', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, recusado: ' || (r ->> 'msg'));

  r := public.mkt_msg_importar(v_l || jsonb_build_array(v_l -> 0), false, null);
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Máximo de 2.000 linhas%' then
    raise exception 'I4 FALHOU: aceitou 2.001 linhas';
  end if;
  perform pg_temp.ok('I4 2.001 linhas', 'recusado: ' || (r ->> 'msg'));
end
$t$;
reset role;
do $c$
begin
  if (select count(*) from mkt_mensageria.disparos where origem = 'planilha') <> 2000
     or (select count(*) from mkt_mensageria.importacoes) <> 1
     or (select count(*) from mkt_mensageria.historico where tabela = 'disparos' and acao = 'inserir') <> 2000
     or exists (select 1 from mkt_mensageria.disparos where origem = 'planilha' and canal <> 'whatsapp_api' and tipo is not null)
     or (select count(*) from mkt_mensageria.disparos where origem = 'planilha' and entregues is null) <> 500
     or (select count(*) from mkt_mensageria.disparos where origem = 'planilha' and custo_centavos is null) <> 666 then
    raise exception 'I5 FALHOU: contagens depois da importação';
  end if;
  perform pg_temp.ok('I5 conferência', '2000 disparos origem=planilha, 1 importação, 2000 históricos; vazio virou nulo (500 sem entregues, 666 sem custo)');
end
$c$;

-- Fim do bloco 3: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005n BLOCO 3 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.\n'
    || (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 3

