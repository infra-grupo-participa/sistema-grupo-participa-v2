-- Ensaio de 20261016240000 + 20261016240100 numa transação DESFEITA (rollback). Dado inventado: nomes "Pessoa Teste N" e e-mails .invalid.
-- RODADO em 16/10/2026 (aplica_sql.py ensaio, transação desfeita); saída em 20261016240000.explain.md §8. Rodar com o executor que só aceita arquivo
-- terminado em rollback. O segredo do Vault nunca é impresso (só existência e tamanho).
-- Prova: a migration inteira roda; o seed nasce sem cópia; gravar (novo, igual, erro, inválido, chave inexistente); a função da tela
-- (equipe vê tudo, md5 igual não devolve conteúdo, chave inexistente P0002, fora da equipe 42501, anon 42501, tabela e funções internas
-- fechadas); explain (analyze, buffers) da leitura por PK; o cron nasce como esperado.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
insert into pg_temp._z_out (passo, linha) select '00 antes de tudo', jsonb_build_object(
  'tabela_existe', to_regclass('dados.relatorio_planilha') is not null,
  'funcao_existe', to_regprocedure('public.dados_miami_relatorio(text,text)') is not null,
  'jobs_cron', (select count(*) from cron.job),
  'dashboard_ativo', (select count(*) from dados.dashboards where chave = 'clinica-miami-2026-12' and ativo))::text;

-- ===== 20261016240000 =====
-- 20261016240000: cópia da aba `Relatório` da planilha "Dados [MIAMI 2026]" no banco + função que a tela da Clínica Miami lê.
--
-- STATUS: ver 20261016240000.explain.md (NÃO APLICADA; Edge dados-planilha-relatorio NÃO PUBLICADA).
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

-- ===== 20261016240100 =====
-- 20261016240100: liga a cópia da aba Relatório (cron dados-relatorio-planilha-sync → Edge dados-planilha-relatorio).
--
-- STATUS: NÃO APLICADA. APLICAR SÓ DEPOIS de (1) 20261016240000 aplicada, (2) a Edge dados-planilha-relatorio publicada e
--   (3) uma rodada manual com sucesso (ver 20261016240000.explain.md, "Ordem"). Sem a Edge no ar o cron recebe 404 e o vigia abre incidente.
-- COMO VOLTAR: 20261016240100_reversao.sql. Desligar sem apagar: select cron.alter_job((select jobid from cron.job where jobname = 'dados-relatorio-planilha-sync'), active := false);
-- O QUE FAZ
--   a. Cron dados-relatorio-planilha-sync, a cada 5 minutos nos minutos 2, 7, 12... (2-59/5; a mensageria-planilha-sync roda nos
--      minutos 6, 16, 26... desde a 20261014010300 e as duas Edges leem o Google com a mesma conta de serviço: os minutos
--      2, 7, 12, 17... nunca coincidem com os dela),
--      pelo ops.cron_post (regra 11 do CLAUDE.md), header x-sync-chave do Vault (dados_relatorio_planilha_chave).
--   b. Linha do vigia escrita à mão (ops.rotina / ops.rotina_estado): intervalo 5 min, 3 falhas seguidas ou 30 min sem
--      sucesso abrem incidente, 3 sucessos fecham.
-- AS 5 PERGUNTAS
--   escala: 1 planilha, 1 aba, 1 chamada à Google Sheets API (values.batchGet) + 1 token por rodada.
--   índice: nenhum (a Edge lê a config de uma tabela de 1 linha).
--   frequência: 288 chamadas por dia (cota do Google: 300 leituras por minuto por projeto; a rodada usa 1).
--   repetição: uma rodada por 5 minutos, não por tela. A tela lê o banco.
--   reversão: cron.unschedule ou active := false.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $guarda$
begin
  if to_regclass('dados.relatorio_planilha') is null or to_regprocedure('dados.relatorio_planilha_gravar(text,jsonb,text)') is null then
    raise exception '20261016240100: aplique antes 20261016240000 (dados.relatorio_planilha ausente)';
  end if;
end
$guarda$;

do $cron$
begin
  if to_regnamespace('cron') is null or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261016240100: pg_cron, ops.cron_post ou Vault ausente; cron dados-relatorio-planilha-sync NÃO agendado';
    return;
  end if;
  perform cron.schedule('dados-relatorio-planilha-sync', '2-59/5 * * * *', $c$
    select ops.cron_post('dados-relatorio-planilha-sync',
      url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/dados-planilha-relatorio',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'dados_relatorio_planilha_chave')),
      timeout_milliseconds := 60000)
  $c$);
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('dados-relatorio-planilha-sync', 3, interval '30 minutes', 3, interval '5 minutes', 'manual')
  on conflict (jobname) do nothing;
  insert into ops.rotina_estado (jobname) values ('dados-relatorio-planilha-sync') on conflict (jobname) do nothing;
end
$cron$;

do $conf$
begin
  if to_regnamespace('cron') is null then return; end if;
  if (select count(*) from cron.job where jobname = 'dados-relatorio-planilha-sync' and schedule = '2-59/5 * * * *' and active
         and command like '%ops.cron_post(''dados-relatorio-planilha-sync''%'
         and command like '%dados_relatorio_planilha_chave%') <> 1 then
    raise exception '20261016240100: cron dados-relatorio-planilha-sync ausente ou fora do padrão';
  end if;
  if (select count(*) from ops.rotina where jobname = 'dados-relatorio-planilha-sync') <> 1 then
    raise exception '20261016240100: linha do vigia ausente';
  end if;
end
$conf$;

-- ===== PROVAS (como postgres) =====
insert into pg_temp._z_out (passo, linha) select '01 seed', jsonb_build_object('linhas', count(*), 'ativa', bool_and(ativa),
  'sem_copia', bool_and(conteudo is null and md5 is null), 'aba', min(aba))::text from dados.relatorio_planilha;
insert into pg_temp._z_out (passo, linha) select '02 config', dados.relatorio_planilha_config()::text;
insert into pg_temp._z_out (passo, linha) select '03 chave do Vault', jsonb_build_object('existe', count(*) = 1, 'tamanho', max(length(decrypted_secret)))::text
  from vault.decrypted_secrets where name = 'dados_relatorio_planilha_chave';
insert into pg_temp._z_out (passo, linha) select '04 chave via função (só confere tamanho)', length(dados.relatorio_planilha_chave())::text;

create temp table _z_c as select jsonb_build_object('versao', 1, 'aba', 'Relatório', 'avisos', '[]'::jsonb, 'blocos', jsonb_build_object(
  'diamantes', jsonb_build_object('titulo', 'Respostas por pessoa da Lista Diamantes', 'colunas', jsonb_build_array('Nome (Lista Diamantes)', 'E-mail'),
    'linhas', jsonb_build_array(jsonb_build_array('Pessoa Teste 1', 'pessoa.teste1@exemplo.invalid'))))) as v;
grant select on pg_temp._z_c to authenticated, anon;
insert into pg_temp._z_out (passo, linha) select '05 gravar novo', dados.relatorio_planilha_gravar('clinica-miami-2026-12', v, null)::text from _z_c;
insert into pg_temp._z_out (passo, linha) select '06 gravar igual (não reescreve)', dados.relatorio_planilha_gravar('clinica-miami-2026-12', v, null)::text from _z_c;
insert into pg_temp._z_out (passo, linha) select '07 gravar com erro (mantém a cópia)', dados.relatorio_planilha_gravar('clinica-miami-2026-12', null, 'cabecalho_diferente:diamantes:3')::text;
insert into pg_temp._z_out (passo, linha) select '08 depois do erro', jsonb_build_object('tem_conteudo', conteudo is not null, 'md5_confere', md5 = md5(conteudo::text),
  'erro', erro, 'lido_antes_de_tentado', lido_em <= tentado_em)::text from dados.relatorio_planilha;
insert into pg_temp._z_out (passo, linha) select '09 gravar inválido (versão 2)', dados.relatorio_planilha_gravar('clinica-miami-2026-12', '{"versao":2,"blocos":{}}'::jsonb, null)::text;
insert into pg_temp._z_out (passo, linha) select '09b gravar inválido (sem blocos)', dados.relatorio_planilha_gravar('clinica-miami-2026-12', '{"versao":1}'::jsonb, null)::text;
insert into pg_temp._z_out (passo, linha) select '09c gravar inválido (sem versão)', dados.relatorio_planilha_gravar('clinica-miami-2026-12', '{"blocos":{}}'::jsonb, null)::text;
insert into pg_temp._z_out (passo, linha) select '10 erro do inválido', erro from dados.relatorio_planilha;
insert into pg_temp._z_out (passo, linha) select '11 chave inexistente', dados.relatorio_planilha_gravar('nao-existe', v, null)::text from _z_c;
insert into pg_temp._z_out (passo, linha) select '12 gravar bom limpa o erro', dados.relatorio_planilha_gravar('clinica-miami-2026-12', v, null)::text from _z_c;
insert into pg_temp._z_out (passo, linha) select '13 erro limpo', coalesce(erro, '(nulo)') from dados.relatorio_planilha;
insert into pg_temp._z_out (passo, linha) select '14 gravar conteúdo diferente', dados.relatorio_planilha_gravar('clinica-miami-2026-12',
  jsonb_set(v, '{avisos}', jsonb_build_array(jsonb_build_object('codigo', 'x', 'texto', 'y'))), null)::text from _z_c;
update dados.relatorio_planilha set ativa = false where chave = 'clinica-miami-2026-12';
insert into pg_temp._z_out (passo, linha) select '15 inativa: config vazia e gravar recusa', jsonb_build_object('config', dados.relatorio_planilha_config(),
  'gravar', dados.relatorio_planilha_gravar('clinica-miami-2026-12', v, null))::text from _z_c;
update dados.relatorio_planilha set ativa = true where chave = 'clinica-miami-2026-12';
select dados.relatorio_planilha_gravar('clinica-miami-2026-12', v, null) from _z_c; -- volta ao conteúdo base

create temp table _z_m as select md5 from dados.relatorio_planilha where chave = 'clinica-miami-2026-12';
grant select on pg_temp._z_m to authenticated, anon;

-- ===== PROVAS (como usuário da equipe) =====
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '20 equipe lê', jsonb_build_object('disponivel', r ->> 'disponivel', 'igual', r ->> 'igual', 'contato_visivel', r ->> 'contato_visivel',
  'chaves', (select jsonb_agg(k order by k) from jsonb_object_keys(r) k),
  'email_na_resposta', (r -> 'conteudo' -> 'blocos' -> 'diamantes' -> 'linhas' -> 0 ->> 1))::text
  from (select public.dados_miami_relatorio('clinica-miami-2026-12') r) x;
insert into pg_temp._z_out (passo, linha) select '21 md5 igual: sem conteúdo', jsonb_build_object('igual', r ->> 'igual', 'conteudo_json_null', jsonb_typeof(r -> 'conteudo'))::text
  from (select public.dados_miami_relatorio('clinica-miami-2026-12', (select md5 from pg_temp._z_m)) r) x;
insert into pg_temp._z_out (passo, linha) select '22 md5 velho: devolve conteúdo', jsonb_build_object('igual', r ->> 'igual', 'conteudo', jsonb_typeof(r -> 'conteudo'))::text
  from (select public.dados_miami_relatorio('clinica-miami-2026-12', '00000000000000000000000000000000') r) x;
do $t$ begin perform public.dados_miami_relatorio('nao-existe');
  insert into pg_temp._z_out (passo, linha) values ('23 chave inexistente', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('23 chave inexistente', sqlstate); end $t$;
do $t$ begin perform * from dados.relatorio_planilha;
  insert into pg_temp._z_out (passo, linha) values ('24 equipe lê a tabela direto', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('24 equipe lê a tabela direto', sqlstate); end $t$;
do $t$ begin perform dados.relatorio_planilha_chave();
  insert into pg_temp._z_out (passo, linha) values ('25 equipe lê a chave', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('25 equipe lê a chave', sqlstate); end $t$;
do $t$ begin perform dados.relatorio_planilha_gravar('clinica-miami-2026-12', null, 'x');
  insert into pg_temp._z_out (passo, linha) values ('26 equipe grava', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('26 equipe grava', sqlstate); end $t$;
-- explain (analyze, buffers) da função como a tela a chama
do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select public.dados_miami_relatorio(''clinica-miami-2026-12'')' loop
    insert into pg_temp._z_out (passo, linha) values ('27 explain da função (equipe)', l);
  end loop;
end $x$;
reset role;
-- explain (analyze, buffers) da leitura por PK (o que a função faz por dentro; como postgres para poder ler a tabela)
do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select * from dados.relatorio_planilha x where x.chave = ''clinica-miami-2026-12'' and x.ativa' loop
    insert into pg_temp._z_out (passo, linha) values ('28 explain da leitura por PK', l);
  end loop;
end $x$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.dados_miami_relatorio('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('29 authenticated fora da equipe', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('29 authenticated fora da equipe', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin perform public.dados_miami_relatorio('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('30 anon', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('30 anon', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== PROVAS DO CRON (20261016240100) =====
insert into pg_temp._z_out (passo, linha) select '40 cron', jsonb_build_object('jobs', count(*), 'schedule', min(schedule), 'ativo', bool_and(active),
  'chama_a_edge', bool_and(command like '%/functions/v1/dados-planilha-relatorio%'), 'usa_ops_cron_post', bool_and(command like '%ops.cron_post(''dados-relatorio-planilha-sync''%'))::text
  from cron.job where jobname = 'dados-relatorio-planilha-sync';
insert into pg_temp._z_out (passo, linha) select '41 vigia', jsonb_build_object('rotina', (select count(*) from ops.rotina where jobname = 'dados-relatorio-planilha-sync' and intervalo_fonte = 'manual' and n_falhas = 3 and k_ok = 3),
  'estado', (select count(*) from ops.rotina_estado where jobname = 'dados-relatorio-planilha-sync'))::text;
insert into pg_temp._z_out (passo, linha) select '42 outros jobs intactos', (select count(*) from cron.job where jobname <> 'dados-relatorio-planilha-sync')::text;

-- ===== REVERSÃO (dentro do rollback: prova que ela fecha limpa) =====
-- 20261016240100_reversao.sql
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select cron.unschedule('dados-relatorio-planilha-sync') where exists (select 1 from cron.job where jobname = 'dados-relatorio-planilha-sync');
delete from ops.rotina_estado where jobname = 'dados-relatorio-planilha-sync';
delete from ops.rotina where jobname = 'dados-relatorio-planilha-sync';

do $c$
begin
  if exists (select 1 from cron.job where jobname = 'dados-relatorio-planilha-sync') or exists (select 1 from ops.rotina where jobname = 'dados-relatorio-planilha-sync') then
    raise exception 'reversão de 20261016240100 incompleta';
  end if;
end
$c$;
-- 20261016240000_reversao.sql
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists public.dados_miami_relatorio(text, text);
drop function if exists dados.relatorio_planilha_gravar(text, jsonb, text);
drop function if exists dados.relatorio_planilha_config();
drop function if exists dados.relatorio_planilha_chave();
drop table if exists dados.relatorio_planilha;
delete from vault.secrets where name = 'dados_relatorio_planilha_chave';

do $c$
begin
  if to_regclass('dados.relatorio_planilha') is not null
     or to_regprocedure('public.dados_miami_relatorio(text,text)') is not null
     or to_regprocedure('dados.relatorio_planilha_gravar(text,jsonb,text)') is not null
     or to_regprocedure('dados.relatorio_planilha_config()') is not null
     or to_regprocedure('dados.relatorio_planilha_chave()') is not null
     or exists (select 1 from vault.secrets where name = 'dados_relatorio_planilha_chave') then
    raise exception 'reversão de 20261016240000 incompleta';
  end if;
end
$c$;
insert into pg_temp._z_out (passo, linha) select '50 depois da reversão', jsonb_build_object('tabela', to_regclass('dados.relatorio_planilha') is not null,
  'funcao', to_regprocedure('public.dados_miami_relatorio(text,text)') is not null, 'cron', (select count(*) from cron.job where jobname = 'dados-relatorio-planilha-sync'),
  'segredo', (select count(*) from vault.secrets where name = 'dados_relatorio_planilha_chave'))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
