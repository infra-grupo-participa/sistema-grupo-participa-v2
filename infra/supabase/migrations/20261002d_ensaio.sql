-- 20261002d — ENSAIO (não aplica nada)
-- RODADO 30/09/2026: selo comprovado 49 · nao_comprovado 313 · outro_nivel 4 · null 1519. A referência antiga (49/307/10) contava
--   solicitações ainda em andamento (cadastro_concluido 5 + docs_aprovados 1 = os 6 de diferença); a regra da 20261002c não conta.
--   Guardas 42501 ok · equipe 1885 linhas · Hash Left Join 2,4 ms · 3 rodadas 2,5–3,0 ms · cadastro_impacto 1 aluno.
--
-- Como rodar: arquivo inteiro numa transação única (MCP execute_sql), como postgres. SEM begin/rollback aqui:
--   o último comando levanta 'ZOUT…' com todo o _z_out, e o erro desfaz a transação inteira (função criada inclusive).
-- Grava só DENTRO da transação: cria public.fn_aluno_nivel_selo() (cópia literal da migration, passo 1).
-- Nenhuma linha de tabela é escrita.
--
-- Esperados (conferir no ZOUT):
--   0.existe                  = 0 (a função ainda não existe em produção) — CONFERIR se vier 1
--   0.super_diamante_ativos   = CONFERIR: ativos com nivel_resultado 'super_diamante' (fora do domínio -> selo null)
--   0.ciclos                  = tipo | n | nivel nulo | concluido_em nulo | aluno nulo (defs-vivas §6.3: cadastro 7 · placa 3)
--   2.conf_*                  = secdef t, search_path, anon f, authenticated t
--   3.sub_*                   = sub equipe encontrado; 3.eh_equipe_fora = f, 3.eh_equipe_equipe = t
--   3.auth_uid                = o sub da equipe (CONFERIR: auth.uid() lê request.jwt.claims / claim.sub)
--   4.selo                    = referência medida antes: comprovado 49 · nao_comprovado 307 · outro_nivel 10 (≥ ouro)
--   4.integridade             = linhas = aluno_ids = ativos; comprovacao_sem_data 0
--   4.cadastro_impacto        = alunos cujo selo mudaria se ciclos tipo 'cadastro' contassem (vazio = nenhum)
--   5.guarda_anon             = 42501 … OK
--   5.guarda_authenticated    = 42501 … OK   (authenticated fora da equipe)
--   5.equipe_authenticated    = OK ~1.885 linhas (authenticated da equipe: grant + guarda deixam passar)
--   6.explain_chamada         = Function Scan (tempo total da chamada)
--   6.explain_central         = Seq Scan thb_alunos + Hash Left Join sobre o DISTINCT ON (≈60 linhas); sem índice novo
--   6.tempo                   = 3 rodadas, ms

set local statement_timeout = '20s';
set local lock_timeout = '3s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;

create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;

create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;

-- ─── 0. Fatos do banco ───────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('0.now', 'select now(), current_user, session_user');
select pg_temp.z_q('0.existe', $q$select count(*) from pg_proc where proname = 'fn_aluno_nivel_selo'$q$);
select pg_temp.z_q('0.gp_eh_equipe', $q$select md5(prosrc), prosecdef from pg_proc where oid = 'public.gp_eh_equipe()'::regprocedure$q$);
select pg_temp.z_q('0.ativos', $q$
  select count(*) ativos,
         count(*) filter (where nivel_resultado in ('ouro','platina','diamante','diamante_vermelho')) ativos_ouro_ou_mais
    from public.thb_alunos where cancelado_em is null$q$);
select pg_temp.z_q('0.super_diamante_ativos', $q$
  select count(*) from public.thb_alunos where cancelado_em is null and nivel_resultado = 'super_diamante'$q$);
select pg_temp.z_q('0.ciclos', $q$
  select tipo, count(*) n, count(*) filter (where nivel is null) nivel_nulo,
         count(*) filter (where concluido_em is null) concluido_em_nulo, count(*) filter (where aluno_id is null) aluno_nulo
    from public.thb_placas_ciclos group by 1 order by 1$q$);
select pg_temp.z_q('0.solic_concluidas', $q$
  select status, count(*) n, count(*) filter (where nivel is null) nivel_nulo, count(*) filter (where aluno_id is null) aluno_nulo
    from public.thb_placas_solicitacoes where status in ('concluido','placa_postada') group by 1 order by 1$q$);
select pg_temp.z_q('0.perfis_equipe', $q$
  select count(*) from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'$q$);

-- ─── 1. MIGRATION 20261002d (cópia literal do arquivo) ───────────────────────────────────────────────────────────────
-- 20261002d — public.fn_aluno_nivel_selo(): selo de comprovação do nível de cada aluno ativo
--
-- O QUE FAZ: devolve, para TODOS os alunos ativos (thb_alunos.cancelado_em is null, ~1.885), numa única chamada:
--   aluno_id | nivel_comprovado | comprovado_em | selo
-- Só leitura. NÃO altera thb_alunos.nivel_resultado nem nada mais.
--
-- COMPROVAÇÃO = união de duas fontes; vale a MAIS RECENTE (decisão do Marcio), desempate id DESC:
--   * public.thb_placas_solicitacoes com status IN ('concluido','placa_postada') e nivel NOT NULL;
--       data = updated_at (mantido por trigger BEFORE UPDATE; medido: 0 de 50 concluídas/postadas com
--       updated_at parado em created_at). Mesma regra de "concluída" da 20261002c (fn_sync_placa_nivel).
--   * public.thb_placas_ciclos com tipo = 'placa' e nivel NOT NULL; data = concluido_em (nulo vai para o fim).
--       tipo 'cadastro' fica fora: é snapshot de solicitação em 'cadastro_concluido' (fn_placas_refazer), status
--       que também NÃO conta como comprovação na solicitação. Ver "Decisão" no relatório; o ensaio mede o impacto.
--
-- ESCALA DE NÍVEIS: web/shared/domain/nivel-resultado/index.ts
--   NIVEIS_COM_COMPROVACAO = ['ouro','platina','diamante','diamante_vermelho']  (níveis que exigem placa).
--   Obs.: o CHECK thb_alunos_nivel_resultado_check aceita também 'super_diamante', que NÃO está no domínio;
--   aqui ele segue o domínio (selo null). O ensaio conta quantos ativos têm esse valor.
--
-- REGRA DO selo:
--   nivel_resultado fora de NIVEIS_COM_COMPROVACAO (abaixo de ouro) ou nulo -> null
--   sem comprovação                                                        -> 'nao_comprovado'
--   comprovação = nivel_resultado                                          -> 'comprovado'
--   comprovação <> nivel_resultado                                         -> 'outro_nivel'
--   nivel_comprovado/comprovado_em vêm preenchidos para qualquer aluno que tenha comprovação, mesmo com selo null.
--
-- SEGURANÇA: SECURITY DEFINER, search_path public, pg_temp; guarda gp_eh_equipe() (perfil ativo @advmais.com)
--   com errcode 42501; EXECUTE revogado de PUBLIC e anon (revogar só de anon não pega o grant de PUBLIC), concedido
--   só a authenticated.
--
-- AS 5 PERGUNTAS
--   escala: 1 SELECT set-based; custo = seq de thb_alunos (1.888) + solicitações (191) + ciclos (10). Linear na base;
--           com 10x continua na casa de dezenas de milhares de linhas lidas, sem N+1.
--   índice: não precisa. Lê as 3 tabelas inteiras (a lista mostra todos); DISTINCT ON sobre ~60 comprovações.
--           Plano medido no ensaio (passo 6). Nenhum índice criado.
--   frequência: 1 chamada por carga da lista de alunos (equipe interna).
--   repetição: 1 chamada devolve todos; o front não chama por aluno.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261002d_ensaio.sql

select set_config('lock_timeout', '3s', true);

-- ─── 1. Função ────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_nivel_selo()
returns table (aluno_id uuid, nivel_comprovado text, comprovado_em timestamptz, selo text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
begin
  if not public.gp_eh_equipe() then
    raise exception 'fn_aluno_nivel_selo: acesso restrito à equipe' using errcode = '42501';
  end if;

  return query
  with comp as (
    select distinct on (x.aid) x.aid, x.nivel, x.em
      from (
        select s.aluno_id as aid, s.nivel, s.updated_at as em, s.id
          from public.thb_placas_solicitacoes s
         where s.status in ('concluido', 'placa_postada')
           and s.nivel is not null
           and s.aluno_id is not null
        union all
        select c.aluno_id as aid, c.nivel, c.concluido_em as em, c.id
          from public.thb_placas_ciclos c
         where c.tipo = 'placa'
           and c.nivel is not null
           and c.aluno_id is not null
      ) x
     order by x.aid, x.em desc nulls last, x.id desc
  )
  select a.id,
         cp.nivel,
         cp.em,
         case
           when a.nivel_resultado in ('ouro', 'platina', 'diamante', 'diamante_vermelho') then
             case
               when cp.nivel is null               then 'nao_comprovado'
               when cp.nivel = a.nivel_resultado   then 'comprovado'
               else                                     'outro_nivel'
             end
         end::text
    from public.thb_alunos a
    left join comp cp on cp.aid = a.id
   where a.cancelado_em is null;
end;
$function$;

revoke all on function public.fn_aluno_nivel_selo() from public, anon;
grant execute on function public.fn_aluno_nivel_selo() to authenticated;

-- ─── 2. Conferência pós-aplicação ─────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = 'public.fn_aluno_nivel_selo()'::regprocedure
                    and p.prosecdef
                    and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261002d: fn_aluno_nivel_selo sem SECURITY DEFINER ou search_path';
  end if;
  if exists (select 1 from pg_proc p
              where p.oid = 'public.fn_aluno_nivel_selo()'::regprocedure
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE'))) then
    raise exception '20261002d: PUBLIC executa public.fn_aluno_nivel_selo()';
  end if;
  if has_function_privilege('anon', 'public.fn_aluno_nivel_selo()', 'execute') then
    raise exception '20261002d: anon executa public.fn_aluno_nivel_selo()';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_aluno_nivel_selo()', 'execute') then
    raise exception '20261002d: authenticated sem EXECUTE em public.fn_aluno_nivel_selo()';
  end if;
end $confere$;


-- ═══ REVERSÃO ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Função nova, só leitura, sem dado próprio: reverter = remover a função (antes, remover o consumidor no web/).
--
-- drop function if exists public.fn_aluno_nivel_selo();
-- ─── fim da cópia da migration ───────────────────────────────────────────────────────────────────────────────────────

-- ─── 2. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('2.conf_def', $q$
  select prosecdef, proconfig, provolatile, proacl::text from pg_proc
   where oid = 'public.fn_aluno_nivel_selo()'::regprocedure$q$);
select pg_temp.z_q('2.conf_exec', $q$
  select r, has_function_privilege(r, 'public.fn_aluno_nivel_selo()', 'execute')
    from unnest(array['anon','authenticated','service_role']) r$q$);

-- ─── 3. Subs escolhidos dinamicamente. gp_eh_equipe() (defs-vivas §1.2): existe perfis p com p.id = auth.uid(),
--        p.status = 'ativo' e p.email ilike '%@advmais.com' ──────────────────────────────────────────────────────────
select set_config('z.sub_equipe', coalesce((
  select p.id::text from public.perfis p
   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by p.id limit 1), ''), true);
select set_config('z.sub_fora', coalesce((
  select p.id::text from public.perfis p
   where not coalesce(p.status = 'ativo' and p.email ilike '%@advmais.com', false) order by p.id limit 1),
  gen_random_uuid()::text), true);
insert into _z_out (passo, linha) values
  ('3.sub_equipe', coalesce(nullif(current_setting('z.sub_equipe'), ''), 'NENHUM PERFIL DE EQUIPE: testes de equipe inválidos')),
  ('3.sub_fora', current_setting('z.sub_fora') ||
     case when exists (select 1 from public.perfis where id::text = current_setting('z.sub_fora'))
          then ' (perfil real)' else ' (uuid aleatório, sem perfil)' end);

-- claims do usuário FORA da equipe
select set_config('request.jwt.claim.sub', current_setting('z.sub_fora'), true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.sub_fora'), 'role', 'authenticated')::text, true);
select pg_temp.z_q('3.eh_equipe_fora', 'select public.gp_eh_equipe()');
-- claims do usuário DA equipe
select set_config('request.jwt.claim.sub', current_setting('z.sub_equipe'), true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.sub_equipe'), 'role', 'authenticated')::text, true);
select pg_temp.z_q('3.eh_equipe_equipe', 'select public.gp_eh_equipe()');
-- CONFERIR: auth.uid() não está na defs-vivas; aqui só confirmo que devolve o sub setado
select pg_temp.z_q('3.auth_uid', 'select auth.uid()');

-- ─── 4. Resultado (postgres com claims da equipe: a guarda passa) ─────────────────────────────────────────────────────
select pg_temp.z_q('4.selo', $q$
  select coalesce(selo, '(null)') selo, count(*) from public.fn_aluno_nivel_selo() group by 1 order by 1$q$);
select pg_temp.z_q('4.selo_por_nivel', $q$
  select a.nivel_resultado, f.selo, count(*)
    from public.fn_aluno_nivel_selo() f join public.thb_alunos a on a.id = f.aluno_id
   where f.selo is not null group by 1, 2 order by 1, 2$q$);
select pg_temp.z_q('4.integridade', $q$
  select (select count(*) from public.fn_aluno_nivel_selo()) linhas,
         (select count(distinct aluno_id) from public.fn_aluno_nivel_selo()) aluno_ids,
         (select count(*) from public.thb_alunos where cancelado_em is null) ativos,
         (select count(*) from public.fn_aluno_nivel_selo() where nivel_comprovado is not null) com_comprovacao,
         (select count(*) from public.fn_aluno_nivel_selo() where nivel_comprovado is not null and comprovado_em is null) comprovacao_sem_data$q$);
select pg_temp.z_q('4.amostra_outro_nivel', $q$
  select f.aluno_id, a.nivel_resultado, f.nivel_comprovado, f.comprovado_em
    from public.fn_aluno_nivel_selo() f join public.thb_alunos a on a.id = f.aluno_id
   where f.selo = 'outro_nivel' order by f.comprovado_em desc nulls last limit 20$q$);
-- Impacto de contar também ciclos tipo 'cadastro' (a migration exclui)
select pg_temp.z_q('4.cadastro_impacto', $q$
  with base as (
    select s.aluno_id aid, s.nivel, s.updated_at em, s.id from public.thb_placas_solicitacoes s
     where s.status in ('concluido','placa_postada') and s.nivel is not null and s.aluno_id is not null
    union all
    select c.aluno_id, c.nivel, c.concluido_em, c.id from public.thb_placas_ciclos c
     where c.nivel is not null and c.aluno_id is not null),
  com as (select distinct on (aid) aid, nivel from base order by aid, em desc nulls last, id desc),
  alt as (
    select a.id,
           case when a.nivel_resultado in ('ouro','platina','diamante','diamante_vermelho') then
             case when c.nivel is null then 'nao_comprovado' when c.nivel = a.nivel_resultado then 'comprovado' else 'outro_nivel' end
           end selo_com_cadastro
      from public.thb_alunos a left join com c on c.aid = a.id where a.cancelado_em is null)
  select f.selo selo_migration, alt.selo_com_cadastro, count(*)
    from public.fn_aluno_nivel_selo() f join alt on alt.id = f.aluno_id
   where f.selo is distinct from alt.selo_com_cadastro group by 1, 2$q$);

-- ─── 5. Guarda ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- 5a. anon (sem sub)
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $g$
declare v text;
begin
  begin
    perform 1 from public.fn_aluno_nivel_selo() limit 1;
    v := 'SEM ERRO';
  exception when others then
    v := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('z.g_anon', v, true);
end $g$;
reset role;
insert into _z_out (passo, linha) values ('5.guarda_anon', current_setting('z.g_anon') ||
  case when current_setting('z.g_anon') like '42501%' then '  OK' else '  FALHA' end);

-- 5b. authenticated fora da equipe
select set_config('request.jwt.claim.sub', current_setting('z.sub_fora'), true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.sub_fora'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $g$
declare v text;
begin
  begin
    perform 1 from public.fn_aluno_nivel_selo() limit 1;
    v := 'SEM ERRO';
  exception when others then
    v := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('z.g_auth', v, true);
end $g$;
reset role;
insert into _z_out (passo, linha) values ('5.guarda_authenticated', current_setting('z.g_auth') ||
  case when current_setting('z.g_auth') like '42501%' then '  OK' else '  FALHA' end);

-- 5c. authenticated da equipe (tem que passar)
select set_config('request.jwt.claim.sub', current_setting('z.sub_equipe'), true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.sub_equipe'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $g$
declare v text; n int;
begin
  begin
    select count(*) into n from public.fn_aluno_nivel_selo();
    v := 'OK ' || n || ' linhas';
  exception when others then
    v := 'FALHA ' || sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('z.g_equipe', v, true);
end $g$;
reset role;
insert into _z_out (passo, linha) values ('5.equipe_authenticated', current_setting('z.g_equipe'));

-- ─── 6. Plano e tempo (postgres, claims da equipe ainda setados) ─────────────────────────────────────────────────────
select pg_temp.z_explain('6.explain_chamada', 'select * from public.fn_aluno_nivel_selo()');
-- SELECT central (corpo da função, igual caractere a caractere): o Function Scan acima esconde os nós internos
select pg_temp.z_explain('6.explain_central', $q$
  with comp as (
    select distinct on (x.aid) x.aid, x.nivel, x.em
      from (
        select s.aluno_id as aid, s.nivel, s.updated_at as em, s.id
          from public.thb_placas_solicitacoes s
         where s.status in ('concluido', 'placa_postada')
           and s.nivel is not null
           and s.aluno_id is not null
        union all
        select c.aluno_id as aid, c.nivel, c.concluido_em as em, c.id
          from public.thb_placas_ciclos c
         where c.tipo = 'placa'
           and c.nivel is not null
           and c.aluno_id is not null
      ) x
     order by x.aid, x.em desc nulls last, x.id desc
  )
  select a.id,
         cp.nivel,
         cp.em,
         case
           when a.nivel_resultado in ('ouro', 'platina', 'diamante', 'diamante_vermelho') then
             case
               when cp.nivel is null               then 'nao_comprovado'
               when cp.nivel = a.nivel_resultado   then 'comprovado'
               else                                     'outro_nivel'
             end
         end::text
    from public.thb_alunos a
    left join comp cp on cp.aid = a.id
   where a.cancelado_em is null$q$);
do $t$
declare t0 timestamptz; n int; i int;
begin
  for i in 1..3 loop
    t0 := clock_timestamp();
    select count(*) into n from public.fn_aluno_nivel_selo();
    insert into pg_temp._z_out (passo, linha)
    values ('6.tempo', format('rodada %s: %s linhas em %s ms', i, n,
                              round((extract(epoch from clock_timestamp() - t0) * 1000)::numeric, 1)));
  end loop;
end $t$;

-- ─── Resultado (a exceção desfaz a transação inteira) ────────────────────────────────────────────────────────────────
do $z$ begin raise exception 'ZOUT%', (select string_agg(passo||' | '||linha, E'\n' order by em) from pg_temp._z_out); end $z$;
