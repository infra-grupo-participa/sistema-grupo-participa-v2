-- Segurança do banco principal — lote 2: fecha a leitura aberta de public.thb_alunos e public.perfis.
-- Status: APLICADA em 08/10/2026 via Management API (histórico registrado em schema_migrations).
--   Ensaio ok_geral=true nos 5 perfis; explain antes×depois e revisão do kirad no .explain.md.
--
-- POR QUÊ
--   auth.users é compartilhada por 7+ sistemas (gp-v2, v1, gps, sip, central, workbook, rede, metodo).
--   thb_alunos tem 2 policies SELECT USING (true) para authenticated; perfis tem 1 (todos_auth_podem_ler).
--   Qualquer login de qualquer sistema lê a base inteira de alunos (CPF, telefone, endereço) e a equipe.
--   Dívida 🔴 em CLAUDE.md ("Débito técnico").
--
-- QUEM LÊ COM SESSÃO authenticated (levantado no código em 08/10/2026; detalhe no .explain.md)
--   gp-v2 e v1 ............ equipe (@advmais.com, perfil ativo): todas as linhas das duas tabelas;
--                           qualquer login: a PRÓPRIA linha de perfis (montar a sessão, inclusive pendente).
--   gps (admin) ........... gps.admins ativo (fonte única gps.eh_admin(), 20261008000366): todas as
--                           linhas de thb_alunos; perfis (id, nome) da equipe no Diário.
--   gps (aluno/sócio) ..... thb_alunos por id: a linha do AMBIENTE (titular) e a de cada PESSOA do
--                           mesmo ambiente (gps.membros.aluno_id / pessoa_aluno_id). Não casa por e-mail.
--                           perfis: já bloqueado por gps_block_aluno (RESTRICTIVE), não muda.
--   service_role (Edge hotmart-*, fluxo público de placas) e funções/views de dono postgres: ignoram RLS.
--
-- O QUE MUDA
--   1. public.gp_le_cadastro_interno()   = gp_eh_equipe() OR gps.eh_admin()           (DEFINER, coalesce)
--   2. public.gp_thb_alunos_do_ambiente() = ids de thb_alunos do(s) ambiente(s) GPS do login (DEFINER)
--   3. Policy nova thb_alunos_select_escopo: interno OR id = any(ambiente).
--   4. Policy nova perfis_select_escopo:     interno OR id = auth.uid().
--   5. As policies abertas NÃO são apagadas: USING (true) vira USING (false) e ganham comentário
--      'seg_lote2 20261009060000: ...' — a reversão as acha pelo comentário e devolve USING (true).
--   Policies RESTRICTIVE (gps_block_aluno, sip_block_*, sip_cannot_access_perfis) e as de escrita: intocadas.
--
-- O QUE NÃO ENTRA, DE PROPÓSITO
--   Casar "a própria linha" de thb_alunos por e-mail do JWT: o Auth está com disable_signup = false e
--   mailer_autoconfirm = true (lido em 07/10, 20261007174525.explain.md). Quem cria conta com o e-mail de
--   um aluno que ainda não tem login recebe sessão na hora e leria o CPF dele. Nenhum leitor achado no
--   código casa por e-mail; o GPS usa gps.membros.pessoa_aluno_id.
--
-- GUARDA DE PREMISSA: aborta se as policies abertas não forem exatamente 2 (thb_alunos) e 1 (perfis),
--   todas SELECT, PERMISSIVE, TO authenticated, USING (true); se faltar gp_eh_equipe(), gps.eh_admin()
--   ou gps.membros(user_id, aluno_id, pessoa_aluno_id); se gps.membros aceitar escrita aberta
--   (policy de escrita com true); se gps.membros tiver FORCE RLS; se a policy nova já existir.
--
-- REVERSÃO: 20261009060000_seg_lote2_reversao.sql (≈10 s, sem deploy).

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $pre$
declare
  v_thb   int;
  v_perf  int;
  v_lista text;
begin
  if to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception 'seg_lote2: public.gp_eh_equipe() não existe';
  end if;
  if to_regprocedure('gps.eh_admin()') is null then
    raise exception 'seg_lote2: gps.eh_admin() não existe (GPS 20261008000366 não aplicada?)';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'gps' and table_name = 'membros'
         and column_name in ('user_id', 'aluno_id', 'pessoa_aluno_id')) <> 3 then
    raise exception 'seg_lote2: gps.membros sem user_id/aluno_id/pessoa_aluno_id';
  end if;
  if (select relforcerowsecurity from pg_class where oid = 'gps.membros'::regclass) then
    raise exception 'seg_lote2: gps.membros com FORCE RLS — o helper DEFINER deixaria de enxergar';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.thb_alunos'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.perfis'::regclass) then
    raise exception 'seg_lote2: RLS desligada em thb_alunos ou perfis';
  end if;

  -- o vínculo que dá acesso não pode ser gravável pelo próprio aluno
  select string_agg(policyname, ', ') into v_lista
    from pg_policies
   where schemaname = 'gps' and tablename = 'membros' and permissive = 'PERMISSIVE'
     and cmd in ('INSERT', 'UPDATE', 'ALL')
     and coalesce(with_check, qual, 'true') = 'true';
  if v_lista is not null then
    raise exception 'seg_lote2: gps.membros tem escrita aberta (%): o aluno criaria o próprio vínculo', v_lista;
  end if;

  -- as policies abertas: contagem e forma exatas
  select count(*) filter (where tablename = 'thb_alunos'),
         count(*) filter (where tablename = 'perfis')
    into v_thb, v_perf
    from pg_policies
   where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
     and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
     and coalesce(qual, 'true') = 'true';
  if v_thb <> 2 or v_perf <> 1 then
    raise exception 'seg_lote2: esperava 2 policies abertas em thb_alunos e 1 em perfis, achei % e %', v_thb, v_perf;
  end if;

  select string_agg(tablename || '.' || policyname || ' cmd=' || cmd || ' roles=' || roles::text, '; ') into v_lista
    from pg_policies
   where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
     and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
     and coalesce(qual, 'true') = 'true'
     and (cmd <> 'SELECT' or roles <> array['authenticated']::name[]);
  if v_lista is not null then
    raise exception 'seg_lote2: policy aberta fora do formato SELECT TO authenticated: %', v_lista;
  end if;

  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and policyname in ('thb_alunos_select_escopo', 'perfis_select_escopo')) then
    raise exception 'seg_lote2: policy nova já existe (migration já aplicada?)';
  end if;
end
$pre$;

-- 1. quem é do cadastro interno: equipe do v2/v1 OU admin do GPS
create function public.gp_le_cadastro_interno()
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(public.gp_eh_equipe(), false) or coalesce(gps.eh_admin(), false)
$f$;

comment on function public.gp_le_cadastro_interno() is
  'seg_lote2 20261009060000: lê thb_alunos/perfis inteiros = gp_eh_equipe() (perfil ativo @advmais.com) OU '
  'gps.eh_admin() (gps.admins ativo). Usada pelas policies thb_alunos_select_escopo e perfis_select_escopo.';

-- 2. o que o aluno do GPS alcança: o ambiente e as pessoas do mesmo ambiente
create function public.gp_thb_alunos_do_ambiente()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(array_agg(distinct v.id) filter (where v.id is not null), '{}'::uuid[])
    from gps.membros eu
    join gps.membros m on m.aluno_id = eu.aluno_id
    cross join lateral (values (m.aluno_id), (m.pessoa_aluno_id)) v(id)
   where eu.user_id = (select auth.uid())
$f$;

comment on function public.gp_thb_alunos_do_ambiente() is
  'seg_lote2 20261009060000: ids de public.thb_alunos que o login alcança pelo GPS — o ambiente (gps.membros.aluno_id) '
  'e a pessoa de cada membro do MESMO ambiente (pessoa_aluno_id). Sem vínculo = vazio. Não casa por e-mail.';

revoke all on function public.gp_le_cadastro_interno()    from public, anon;
revoke all on function public.gp_thb_alunos_do_ambiente() from public, anon;
grant execute on function public.gp_le_cadastro_interno()    to authenticated, service_role;
grant execute on function public.gp_thb_alunos_do_ambiente() to authenticated, service_role;

-- 3 + 4. as policies novas (helpers em (select ...) = InitPlan, avaliado 1× por consulta)
create policy thb_alunos_select_escopo on public.thb_alunos
  for select to authenticated
  using (
    (select public.gp_le_cadastro_interno())
    or id = any ((select public.gp_thb_alunos_do_ambiente())::uuid[])
  );

create policy perfis_select_escopo on public.perfis
  for select to authenticated
  using (
    (select public.gp_le_cadastro_interno())
    or id = (select auth.uid())
  );

-- 5. neutraliza (não apaga) as abertas; o comentário é a chave da reversão
do $neutro$
declare
  r record;
begin
  for r in
    select tablename, policyname
      from pg_policies
     where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
       and permissive = 'PERMISSIVE' and cmd = 'SELECT'
       and roles = array['authenticated']::name[]
       and qual = 'true'
  loop
    execute format('alter policy %I on public.%I using (false)', r.policyname, r.tablename);
    execute format('comment on policy %I on public.%I is %L', r.policyname, r.tablename,
      'seg_lote2 20261009060000: era USING (true); neutralizada. Reverter: 20261009060000_seg_lote2_reversao.sql');
  end loop;
end
$neutro$;

-- conferência final dentro da transação
do $pos$
begin
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
         and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
         and coalesce(qual, 'true') = 'true') <> 0 then
    raise exception 'seg_lote2: ainda há policy aberta depois da troca';
  end if;
  if exists (select 1
               from pg_proc p, unnest(coalesce(p.proacl, '{}')) a
              where p.oid in ('public.gp_le_cadastro_interno()'::regprocedure,
                              'public.gp_thb_alunos_do_ambiente()'::regprocedure)
                and (a::text like '=%' or a::text like 'anon=%')) then
    raise exception 'seg_lote2: helper executável por PUBLIC/anon';
  end if;
end
$pos$;

commit;
