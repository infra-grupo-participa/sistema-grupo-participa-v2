-- 20261016240000: cópia da aba `Relatório` da planilha "Dados [MIAMI 2026]" no banco + função que a tela da Clínica Miami lê.
--
-- STATUS: APLICADA em 16/10/2026 13:20 UTC (aplica_sql.py aplicar, transação única, registrada em schema_migrations). Edge dados-planilha-relatorio PUBLICADA (versão 1). Ver 20261016240000.explain.md.
-- POR QUE: o time da Clínica Miami mantém o Relatório de preenchimento numa planilha (Diamantes e Time); o Victor pediu o
--   mesmo relatório dentro do dashboard (16/10/2026). A tela não lê a planilha direto (cota do Google, chave no navegador):
--   uma Edge copia a aba para o banco a cada 5 minutos e a tela lê a cópia por uma função.
-- O QUE FAZ:
--   1. dados.relatorio_planilha: uma linha por dashboard (chave) com a planilha, a aba, a cópia (jsonb), o md5, quando leu,
--      quando tentou e o último erro. ativa = kill-switch. Sem acesso pela API (RLS ligada, sem policy, sem grant).
--   2. dados.relatorio_planilha_chave(), _config(), _gravar(chave, conteudo, erro): só para postgres (a Edge entra pelo
--      SUPABASE_DB_URL). _gravar com erro NUNCA apaga a cópia anterior; só registra a tentativa e o erro. Conteúdo igual
--      (mesmo md5) só carimba lido_em, sem reescrever a cópia.
--   3. public.dados_miami_relatorio(p_chave, p_md5): a função da tela. Mesmo gate dos outros dados_miami_* (equipe + acesso
--      ao dashboard; 42501 sem acesso, P0002 dashboard não cadastrado). md5 igual ao da cópia = devolve sem conteúdo.
--   4. Chave do Vault dados_relatorio_planilha_chave (gerada no banco).
--   5. Seed: dashboard clinica-miami-2026-12 → planilha 1MjGDuk32NgcJ7N-ab0oPfk75kwu1pgHoJ3FkCURZCA0, aba Relatório.
-- O CRON NÃO ESTÁ AQUI de propósito: vai na 20261016240100, que só se aplica DEPOIS de publicar a Edge (senão o cron chama
--   uma função que não existe e o vigia de rotinas alerta).
-- DECISÃO DO VICTOR (16/10/2026, provisória até a revisão dos níveis de acesso): quem pode ver o dashboard
--   (dados.pode_ver) vê também e-mail e telefone das tabelas. NÃO filtra por contato.ver por enquanto. A resposta traz
--   contato_visivel = true para a tela não precisar mudar quando o filtro voltar.
-- AS 5 PERGUNTAS: escala = 1 linha por dashboard (hoje 1), cópia ~50 a 100 KB (jsonb, TOAST), tetos de 1.000 linhas por tabela
--   e 500 caracteres por célula no leitor; índice = a PK (leitura por chave, 1 linha); frequência = 288 gravações/dia (cron a
--   cada 5 min) e 1 leitura da tela por abertura/atualização; repetição = N telas = N leituras de 1 linha, e md5 igual não
--   devolve o conteúdo; reversão = 20261016240000_reversao.sql (derruba tudo; a planilha não é tocada).
-- SEGURANÇA: a cópia tem nome, e-mail e telefone de pessoas. Tabela sem grant para anon/authenticated/service_role e sem
--   policy; funções internas só para postgres; a pública só para authenticated, com gate de equipe + pode_ver.
-- IDEMPOTENTE: create if not exists, create or replace, seed com on conflict do nothing, segredo só se não existir.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if not exists (select 1 from dados.dashboards where chave = 'clinica-miami-2026-12' and ativo) then
    raise exception '20261016240000: dashboard clinica-miami-2026-12 não existe ativo';
  end if;
  -- O gate da função pública usa dados.pode_ver; se o corpo mudou desde 16/10/2026, reler antes de aplicar.
  if (select md5(prosrc) from pg_proc where oid = 'dados.pode_ver(text)'::regprocedure)
     is distinct from '985b4a65e8edd11cb08232dc286e9d57' then
    raise exception '20261016240000: dados.pode_ver mudou desde 16/10/2026; reler antes de aplicar';
  end if;
  if to_regprocedure('public.gp_eh_equipe()') is null
     or to_regprocedure('vault.create_secret(text,text,text,uuid)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '20261016240000: public.gp_eh_equipe / vault.create_secret / extensions.gen_random_bytes ausente';
  end if;
end
$g$;

-- 1. A cópia ---------------------------------------------------------------------------------------------------------
create table if not exists dados.relatorio_planilha (
  chave       text primary key references dados.dashboards (chave) on update cascade on delete cascade,
  planilha_id text not null check (planilha_id ~ '^[A-Za-z0-9_-]{20,100}$'),
  aba         text not null default 'Relatório' check (btrim(aba) <> '' and length(aba) <= 100),
  ativa       boolean not null default true,
  conteudo    jsonb check (conteudo is null or (jsonb_typeof(conteudo) = 'object' and conteudo ->> 'versao' = '1')),
  md5         text check (md5 is null or md5 ~ '^[0-9a-f]{32}$'),
  lido_em     timestamptz,
  tentado_em  timestamptz,
  erro        text check (length(erro) <= 300),
  criado_em   timestamptz not null default now(),
  check ((conteudo is null) = (md5 is null))
);
comment on table dados.relatorio_planilha is
  '20261016240000: cópia da aba Relatório da planilha Dados [MIAMI 2026] (Edge dados-planilha-relatorio). Tem dado pessoal: só postgres lê; a tela lê por public.dados_miami_relatorio.';
alter table dados.relatorio_planilha enable row level security;
revoke all on dados.relatorio_planilha from public, anon, authenticated, service_role;

-- 2. Funções internas (a Edge entra como postgres) ------------------------------------------------------------------------
create or replace function dados.relatorio_planilha_chave()
 returns text
 language sql
 stable security definer
 set search_path to ''
as $f$
  select decrypted_secret from vault.decrypted_secrets where name = 'dados_relatorio_planilha_chave';
$f$;

create or replace function dados.relatorio_planilha_config()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $f$
  select coalesce(jsonb_agg(jsonb_build_object('chave', r.chave, 'planilha_id', r.planilha_id, 'aba', r.aba)
                            order by r.chave), '[]'::jsonb)
    from dados.relatorio_planilha r
   where r.ativa;
$f$;

-- Grava o resultado de uma rodada. Com p_erro: só registra a tentativa (a cópia boa fica). Sem erro: confere o formato
-- mínimo, e se o md5 mudou troca a cópia; se não mudou, só carimba lido_em.
create or replace function dados.relatorio_planilha_gravar(p_chave text, p_conteudo jsonb, p_erro text)
 returns jsonb
 language plpgsql
 volatile security definer
 set search_path to ''
as $f$
declare
  v_md5    text;
  v_antigo text;
begin
  perform 1 from dados.relatorio_planilha r where r.chave = p_chave and r.ativa for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'chave_inativa');
  end if;

  if p_erro is not null then
    update dados.relatorio_planilha r set tentado_em = now(), erro = left(p_erro, 300) where r.chave = p_chave;
    return jsonb_build_object('ok', false, 'mudou', false);
  end if;

  if p_conteudo is null or jsonb_typeof(p_conteudo) is distinct from 'object' or (p_conteudo ->> 'versao') is distinct from '1'
     or jsonb_typeof(p_conteudo -> 'blocos') is distinct from 'object' or octet_length(p_conteudo::text) > 2000000 then
    update dados.relatorio_planilha r set tentado_em = now(), erro = 'conteudo_invalido' where r.chave = p_chave;
    return jsonb_build_object('ok', false, 'mudou', false, 'erro', 'conteudo_invalido');
  end if;

  v_md5 := md5(p_conteudo::text);
  select r.md5 into v_antigo from dados.relatorio_planilha r where r.chave = p_chave;
  if v_antigo is not distinct from v_md5 then
    update dados.relatorio_planilha r set lido_em = now(), tentado_em = now(), erro = null where r.chave = p_chave;
    return jsonb_build_object('ok', true, 'mudou', false);
  end if;
  update dados.relatorio_planilha r
     set conteudo = p_conteudo, md5 = v_md5, lido_em = now(), tentado_em = now(), erro = null
   where r.chave = p_chave;
  return jsonb_build_object('ok', true, 'mudou', true);
end
$f$;

revoke all on function dados.relatorio_planilha_chave(), dados.relatorio_planilha_config(),
  dados.relatorio_planilha_gravar(text, jsonb, text) from public, anon, authenticated, service_role;

-- 3. A função da tela ------------------------------------------------------------------------------------------------
-- Devolve um jsonb:
--   disponivel      boolean  há cópia (false antes da 1ª leitura boa ou sem planilha cadastrada)
--   md5             text     identifica a cópia (null se não há)
--   igual           boolean  true quando p_md5 é o da cópia: nesse caso conteudo vem null
--   lido_em         timestamptz  última leitura boa da planilha (null se nunca)
--   tentado_em      timestamptz  última tentativa (boa ou ruim)
--   erro            text     código do erro da última tentativa (null se a última deu certo); a cópia boa anterior segue valendo
--   contato_visivel boolean  hoje sempre true (decisão do Victor, 16/10/2026: quem vê o dashboard vê e-mail e telefone)
--   conteudo        jsonb    ver docs/dashboard-presencial.md §2.12
create or replace function public.dados_miami_relatorio(p_chave text, p_md5 text default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  r dados.relatorio_planilha;
  v_igual boolean;
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if not exists (select 1 from dados.dashboards d where d.chave = p_chave and d.ativo) then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  if not coalesce(dados.pode_ver(p_chave), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;

  select * into r from dados.relatorio_planilha x where x.chave = p_chave and x.ativa;
  if not found then
    return jsonb_build_object('disponivel', false, 'md5', null, 'igual', false, 'lido_em', null, 'tentado_em', null,
                              'erro', null, 'contato_visivel', true, 'conteudo', null);
  end if;

  v_igual := coalesce(p_md5 = r.md5, false);
  return jsonb_build_object(
    'disponivel', r.conteudo is not null,
    'md5', r.md5,
    'igual', v_igual,
    'lido_em', r.lido_em,
    'tentado_em', r.tentado_em,
    'erro', r.erro,
    'contato_visivel', true,
    'conteudo', case when v_igual then null else r.conteudo end);
end
$function$;
revoke all on function public.dados_miami_relatorio(text, text) from public, anon, service_role;
grant execute on function public.dados_miami_relatorio(text, text) to authenticated;

-- 4. Chave da Edge ---------------------------------------------------------------------------------------------------
do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'dados_relatorio_planilha_chave') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'dados_relatorio_planilha_chave',
                                'Chave do cron para a Edge dados-planilha-relatorio (20261016240000; gerada no banco)');
  end if;
end
$v$;

-- 5. Seed: a planilha "Dados [MIAMI 2026]" ------------------------------------------------------------------------------
insert into dados.relatorio_planilha (chave, planilha_id, aba)
values ('clinica-miami-2026-12', '1MjGDuk32NgcJ7N-ab0oPfk75kwu1pgHoJ3FkCURZCA0', 'Relatório')
on conflict (chave) do nothing;

-- 6. Conferência final -----------------------------------------------------------------------------------------------------
do $c$
begin
  if not exists (select 1 from dados.relatorio_planilha where chave = 'clinica-miami-2026-12' and ativa and conteudo is null) then
    raise exception '20261016240000: seed não ficou como esperado';
  end if;
  if has_table_privilege('anon', 'dados.relatorio_planilha', 'select') or has_table_privilege('authenticated', 'dados.relatorio_planilha', 'select')
     or has_table_privilege('service_role', 'dados.relatorio_planilha', 'select') then
    raise exception '20261016240000: tabela da cópia está aberta para a API';
  end if;
  if has_function_privilege('anon', 'public.dados_miami_relatorio(text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_miami_relatorio(text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.relatorio_planilha_gravar(text,jsonb,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.relatorio_planilha_chave()', 'execute')
     or has_function_privilege('anon', 'dados.relatorio_planilha_config()', 'execute') then
    raise exception '20261016240000: permissão de função fora do desenhado';
  end if;
  if not exists (select 1 from vault.secrets where name = 'dados_relatorio_planilha_chave') then
    raise exception '20261016240000: chave do Vault não foi criada';
  end if;
end
$c$;
