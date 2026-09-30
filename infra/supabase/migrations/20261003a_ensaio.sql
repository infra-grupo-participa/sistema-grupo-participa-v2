-- 20261003a — ENSAIO (begin … rollback; nada fica gravado)
-- Como rodar: arquivo inteiro numa chamada (MCP execute_sql), como postgres. Saída = 1 json (último select).
-- Esperados:
--   0.existe_pagamentos        = 0 (função nova ainda não existe)
--   1.antes_ms / 3.depois_ms   = mesma ordem de grandeza (~400–450 ms na 20261002e)
--   3.except_antes_menos_depois = 0 · 3.except_depois_menos_antes = 0 · 3.linhas antes = depois
--   4.inline                   = plano SEM "Function Scan on fn_aluno_pagamentos_programa" (corpo expandido)
--   5.authenticated_pagamentos = 42501 (sem EXECUTE) · 5.anon_pagamentos = 42501
--   6.ultima_paga_em_coerente  = (0,0)
--   2.grants                   = programas_safe: anon f / authenticated t; pagamentos: anon f / authenticated f

begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to authenticated, anon;
create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;
create function pg_temp.z_err(p_passo text, p_sql text) returns void language plpgsql as $f$
begin
  execute p_sql;
  insert into pg_temp._z_out (passo, linha) values (p_passo, 'SEM ERRO');
exception when others then
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;
create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;
grant execute on function pg_temp.z_q(text, text), pg_temp.z_err(text, text), pg_temp.z_explain(text, text) to authenticated, anon;
-- papéis: equipe (dev/admin @advmais) e não-equipe (perfil ativo que não passa em gp_eh_equipe)
select set_config('z.eq', (select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
                             and p.cargo in ('dev', 'admin') order by p.id limit 1), true);

select pg_temp.z_q('0.existe_pagamentos', $q$select count(*) from pg_proc where proname = 'fn_aluno_pagamentos_programa'$q$);

-- ─── 1. ANTES, como equipe ──────────────────────────────────────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select set_config('z.t0', clock_timestamp()::text, true);
create temp table _z_antes on commit drop as select * from public.fn_aluno_programas_safe();
select pg_temp.z_q('1.antes_ms', $q$select count(*), round(extract(epoch from clock_timestamp() - current_setting('z.t0')::timestamptz) * 1000) from _z_antes$q$);
select pg_temp.z_explain('1.explain_antes', 'select * from public.fn_aluno_programas_safe()');
reset role;

-- ─── Migration (cópia literal do corpo da 20261003a) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas (falham ANTES de gravar) ───────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_res  text;
  v_src  text;
  v_falta text;
begin
  -- 0.1 assinatura e saída de fn_aluno_programas_safe = as da 20261002e (create or replace não pode mudar isso)
  select pg_get_function_result(p.oid), p.prosrc into v_res, v_src
    from pg_proc p where p.oid = to_regprocedure('public.fn_aluno_programas_safe()');
  if v_res is null then
    raise exception '20261003a: public.fn_aluno_programas_safe() não existe (aplicar a 20261002e antes)';
  end if;
  if v_res <> 'TABLE(aluno_id uuid, programas text[], status_programa jsonb, revisar_motivos text[])' then
    raise exception '20261003a: saída de fn_aluno_programas_safe mudou: %', v_res;
  end if;
  -- 0.2 corpo vivo = o da 20261002e (md5 sem comentários e sem espaços), ou já é esta versão
  if md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g')) <> '46e4a7e48b35cb0682f67b239520b15f'
     and position('fn_aluno_pagamentos_programa' in v_src) = 0 then
    raise exception '20261003a: corpo vivo de fn_aluno_programas_safe difere da 20261002e (md5 normalizado %) — parar e comparar',
      md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g'));
  end if;
  -- 0.3 colunas lidas pela função nova
  select string_agg(format('%s.%s.%s', x.s, x.t, x.c), ', ') into v_falta
    from (values ('fin','vw_transacoes','email'), ('fin','vw_transacoes','familia'), ('fin','vw_transacoes','produto_id'),
                 ('fin','vw_transacoes','produto_nome'), ('fin','vw_transacoes','oferta_codigo'), ('fin','vw_transacoes','grupo'),
                 ('fin','vw_transacoes','aprovado_em'), ('fin','vw_transacoes','pedido_em'),
                 ('public','hm_product_catalog','offer_code'), ('public','hm_product_catalog','categoria')) x(s, t, c)
    left join information_schema.columns c on c.table_schema = x.s and c.table_name = x.t and c.column_name = x.c
   where c.column_name is null;
  if v_falta is not null then
    raise exception '20261003a: coluna ausente: %', v_falta;
  end if;
  -- 0.4 ACL de fn_aluno_programas_safe guardado para a conferência do passo 3 (create or replace preserva; aqui se prova)
  perform set_config('z20261003a.acl',
    (select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>')
       from pg_proc p where p.oid = 'public.fn_aluno_programas_safe()'::regprocedure), false);  -- sessão: sobrevive se o cliente não abrir transação
end $guarda$;

-- ─── 1. Fonte única do "pagou programa" ─────────────────────────────────────────────────────────────────────────────
-- SQL, stable, SECURITY INVOKER, sem SET: o planner expande o corpo dentro de quem chama (inlining), então
-- fn_aluno_programas_safe continua com o mesmo plano. Ninguém de fora executa: revoke de public/anon/authenticated.
-- Quem chama são funções SECURITY DEFINER do owner (postgres), que tem EXECUTE.
create or replace function public.fn_aluno_pagamentos_programa()
returns table (email text, pg_hm boolean, pg_impl boolean, pg_sinal boolean, pg_catalogo boolean,
               pg_aurum boolean, pg_mmd boolean, ultima_paga_em timestamptz)
language sql
stable
as $fn$
  -- 1 passada em fin.vw_transacoes (só conta academy), agregada por e-mail — literal do CTE pag_email da 20261002e
  select t.email,
         bool_or(t.familia = 'HM' and t.produto_id <> '446345'
                 and coalesce(t.produto_nome, '') not ilike '%curso pr_tico%')   as pg_hm,
         bool_or(c.categoria in ('compra_cheia', 'diferenca'))                  as pg_impl,
         bool_or(c.categoria in ('sinal', 'reserva'))                           as pg_sinal,
         bool_or(c.categoria is not null)                                       as pg_catalogo,
         bool_or(t.familia = 'AURUM')                                           as pg_aurum,
         bool_or(t.familia = 'PROGRAMA_DIAMANTE')                               as pg_mmd,
         -- novo: data da última compra paga que conta como "pagou programa" (hm ou catálogo ou aurum ou mastermind)
         max(coalesce(t.aprovado_em, t.pedido_em))
           filter (where (t.familia = 'HM' and t.produto_id <> '446345'
                          and coalesce(t.produto_nome, '') not ilike '%curso pr_tico%')
                      or c.categoria is not null
                      or t.familia in ('AURUM', 'PROGRAMA_DIAMANTE'))           as ultima_paga_em
    from fin.vw_transacoes t
    left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
   where t.grupo = 'pago'
     and t.email is not null and t.email <> ''
     and (t.familia in ('HM', 'AURUM', 'PROGRAMA_DIAMANTE') or c.categoria is not null)
   group by t.email
$fn$;

comment on function public.fn_aluno_pagamentos_programa() is
  '20261003a: regra única do "pagou programa" por e-mail (conta academy). Interna: sem EXECUTE para public/anon/authenticated. '
  'Leitores: fn_aluno_programas_safe, fn_aluno_conciliacao (comprou_fora_da_base) e a correção 20261003c.';

revoke all on function public.fn_aluno_pagamentos_programa() from public, anon, authenticated;

-- ─── 2. fn_aluno_programas_safe passa a ler da fonte única (mesma assinatura, mesma saída, mesmos grants) ───────────
-- create or replace preserva proacl; o comment da 20261002e fica como está.
create or replace function public.fn_aluno_programas_safe()
returns table (aluno_id uuid, programas text[], status_programa jsonb, revisar_motivos text[])
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_programas_safe: acesso restrito à equipe' using errcode = '42501';
  end if;

  return query
  -- CENTRAL:INICIO
  with al as (
    select a.id, a.socio_de_aluno_id, a.espaco_instrucao, a.plano, a.turma_aurum_id,
           nullif(lower(trim(both from a.email)), '') as email_n
      from public.thb_alunos a
     where a.cancelado_em is null
  ),
  ep as (
    select e.email, e.pessoa_chave
      from fin.vw_email_pessoa e
  ),
  -- 20261003a: a regra "pagou programa" mora em public.fn_aluno_pagamentos_programa() (mesmo SQL, extraído)
  pag_email as (
    select pp.email, pp.pg_hm, pp.pg_impl, pp.pg_sinal, pp.pg_catalogo, pp.pg_aurum, pp.pg_mmd
      from public.fn_aluno_pagamentos_programa() pp
  ),
  -- e-mail → pessoa: todos os e-mails da mesma pessoa_chave somam
  pag as (
    select coalesce(ep.pessoa_chave, '#email:' || pe.email) as chave,
           bool_or(pe.pg_hm) as pg_hm, bool_or(pe.pg_impl) as pg_impl, bool_or(pe.pg_sinal) as pg_sinal,
           bool_or(pe.pg_catalogo) as pg_catalogo, bool_or(pe.pg_aurum) as pg_aurum, bool_or(pe.pg_mmd) as pg_mmd
      from pag_email pe
      left join ep on ep.email = pe.email
     group by 1
  ),
  gps_ids as (
    select m.aluno_id as id from gps.membros m
    union
    select m.pessoa_aluno_id from gps.membros m where m.pessoa_aluno_id is not null
  ),
  own as (
    select al.id, al.socio_de_aluno_id,
           (g.id is not null)                                                          as no_gps,
           coalesce(p.pg_hm, false)                                                    as pg_hm,
           coalesce(p.pg_impl, false)                                                  as pg_impl,
           coalesce(p.pg_sinal, false)                                                 as pg_sinal,
           coalesce(p.pg_hm or p.pg_catalogo, false)                                   as pg_hm_algum,
           coalesce(p.pg_aurum, false)                                                 as pg_aurum,
           coalesce(p.pg_mmd, false)                                                   as pg_mmd,
           coalesce(al.espaco_instrucao = 'holding_masters_implementacao', false)      as cad_impl,
           coalesce(al.espaco_instrucao = 'aurum' or al.turma_aurum_id is not null
                    or al.plano = 'aurum', false)                                      as cad_aurum,
           coalesce(al.espaco_instrucao = 'mastermind_diamante' or al.plano = 'diamante', false) as cad_mmd,
           coalesce(al.espaco_instrucao = 'platina' or al.plano = 'platina', false)    as cad_platina,
           coalesce(al.espaco_instrucao = 'diamante_vermelho', false)                  as cad_dv
      from al
      left join ep on ep.email = al.email_n
      left join pag p on p.chave = coalesce(ep.pessoa_chave, '#email:' || al.email_n)
      left join gps_ids g on g.id = al.id
  ),
  prog as (
    select o.id, v.programa, v.status, v.motivos
      from own o
      left join own tt on tt.id = o.socio_de_aluno_id   -- pagamento do titular cobre o sócio no GPS
      cross join lateral (values
        ('implementacao',
         case when o.no_gps                 then 'confirmado'
              when o.pg_impl or o.cad_impl  then 'a_revisar'
              when o.pg_sinal               then 'reservou' end,
         array_remove(array[
           case when o.no_gps and not (o.pg_hm_algum or coalesce(tt.pg_hm_algum, false))
                then 'impl_gps_sem_pagamento' end,
           case when not o.no_gps and o.pg_impl  then 'impl_pago_fora_gps' end,
           case when not o.no_gps and o.cad_impl then 'impl_espaco_fora_gps' end], null)),
        ('hm',
         case when o.pg_hm then 'confirmado' end,
         '{}'::text[]),
        ('aurum',
         case when o.pg_aurum and o.cad_aurum then 'confirmado'
              when o.pg_aurum or o.cad_aurum  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_aurum and not o.cad_aurum then 'aurum_so_pagamento' end,
           case when o.cad_aurum and not o.pg_aurum then 'aurum_so_cadastro' end], null)),
        ('mastermind_diamante',
         case when o.pg_mmd and o.cad_mmd then 'confirmado'
              when o.pg_mmd or o.cad_mmd  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_mmd and not o.cad_mmd then 'mastermind_diamante_so_pagamento' end,
           case when o.cad_mmd and not o.pg_mmd then 'mastermind_diamante_so_cadastro' end], null)),
        ('diamante_vermelho',
         case when o.cad_dv then 'confirmado_cadastro' end,
         '{}'::text[]),
        ('platina',
         case when o.cad_platina then 'confirmado_cadastro' end,
         '{}'::text[])
      ) v(programa, status, motivos)
     where v.status is not null
  ),
  -- sócio herda do titular ativo (o titular também está em own/prog); compra própria soma
  herd as (
    select p.id, p.programa, p.status, p.motivos from prog p
    union all
    select s.id, p.programa, p.status, p.motivos
      from own s
      join prog p on p.id = s.socio_de_aluno_id
  ),
  por_status as (
    select h.id, h.programa, h.status,
           case h.status when 'confirmado' then 1 when 'confirmado_cadastro' then 2
                         when 'a_revisar' then 3 else 4 end                             as r,
           array_agg(distinct m.x) filter (where m.x is not null)                        as motivos
      from herd h
      left join lateral unnest(h.motivos) m(x) on true
     group by h.id, h.programa, h.status
  ),
  melhor as (
    select distinct on (ps.id, ps.programa) ps.id, ps.programa, ps.status, coalesce(ps.motivos, '{}'::text[]) as motivos
      from por_status ps
     order by ps.id, ps.programa, ps.r
  ),
  efetivo as (
    select w.id, w.programa, w.status, w.motivos
      from (select mm.id, mm.programa, mm.status, mm.motivos,
                   bool_or(mm.programa = 'implementacao' and mm.status <> 'reservou')
                     over (partition by mm.id) as tem_impl
              from melhor mm) w
     where not (w.programa = 'hm' and w.tem_impl)
  ),
  mot as (
    select e.id, array_agg(distinct x.m order by x.m) as motivos
      from efetivo e
     cross join lateral unnest(e.motivos) x(m)
     group by e.id
  )
  select al.id,
         coalesce(array_agg(e.programa
                            order by array_position(array['implementacao','hm','aurum','mastermind_diamante',
                                                          'diamante_vermelho','platina']::text[], e.programa))
                  filter (where e.programa is not null), '{}'::text[]),
         coalesce(jsonb_object_agg(e.programa, e.status) filter (where e.programa is not null), '{}'::jsonb),
         coalesce(mo.motivos, '{}'::text[])
    from al
    left join efetivo e on e.id = al.id
    left join mot mo on mo.id = al.id
   group by al.id, mo.motivos
  -- CENTRAL:FIM
  ;
end;
$fn$;

-- ─── 3. Conferência pós-aplicação ───────────────────────────────────────────────────────────────────────────────────
do $confere$
declare
  v_acl text;
begin
  select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>') into v_acl
    from pg_proc p where p.oid = 'public.fn_aluno_programas_safe()'::regprocedure;
  if v_acl is distinct from current_setting('z20261003a.acl', true) then
    raise exception '20261003a: ACL de fn_aluno_programas_safe mudou: antes % / depois %', current_setting('z20261003a.acl', true), v_acl;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_programas_safe()'::regprocedure and p.prosecdef
                    and p.proconfig @> array['search_path=public, pg_temp']
                    and position('fn_aluno_pagamentos_programa' in p.prosrc) > 0) then
    raise exception '20261003a: fn_aluno_programas_safe sem SECURITY DEFINER/search_path ou sem a fonte única';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_pagamentos_programa()'::regprocedure
                and (p.prosecdef or p.proconfig is not null or p.prolang <> (select oid from pg_language where lanname = 'sql')
                     or p.provolatile <> 's')) then
    raise exception '20261003a: fn_aluno_pagamentos_programa deixou de ser inlinável (sql, stable, invoker, sem SET)';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_pagamentos_programa()'::regprocedure
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE')))
     or has_function_privilege('anon', 'public.fn_aluno_pagamentos_programa()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_aluno_pagamentos_programa()', 'execute') then
    raise exception '20261003a: fn_aluno_pagamentos_programa executável por PUBLIC/anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.fn_aluno_programas_safe()', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_aluno_programas_safe()', 'execute') then
    raise exception '20261003a: grants de fn_aluno_programas_safe fora do esperado (anon não, authenticated sim)';
  end if;
end $confere$;

-- ─── 2. Grants ──────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('2.grants', $q$select f, r, has_function_privilege(r, f, 'execute') from unnest(array['public.fn_aluno_programas_safe()','public.fn_aluno_pagamentos_programa()']) f, unnest(array['anon','authenticated']) r order by 1, 2$q$);

-- ─── 3. DEPOIS, como equipe: EXCEPT nos 2 sentidos ─────────────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select set_config('z.t0', clock_timestamp()::text, true);
create temp table _z_depois on commit drop as select * from public.fn_aluno_programas_safe();
select pg_temp.z_q('3.depois_ms', $q$select count(*), round(extract(epoch from clock_timestamp() - current_setting('z.t0')::timestamptz) * 1000) from _z_depois$q$);
select pg_temp.z_q('3.except_antes_menos_depois', $q$select count(*) from (select aluno_id, programas::text, status_programa::text, revisar_motivos::text from _z_antes except select aluno_id, programas::text, status_programa::text, revisar_motivos::text from _z_depois) x$q$);
select pg_temp.z_q('3.except_depois_menos_antes', $q$select count(*) from (select aluno_id, programas::text, status_programa::text, revisar_motivos::text from _z_depois except select aluno_id, programas::text, status_programa::text, revisar_motivos::text from _z_antes) x$q$);
select pg_temp.z_q('3.linhas', $q$select (select count(*) from _z_antes) antes, (select count(*) from _z_depois) depois$q$);
select pg_temp.z_explain('3.explain_depois', 'select * from public.fn_aluno_programas_safe()');

-- ─── 5. Função interna não é executável por authenticated nem anon ─────────────────────────────────────────────────
select pg_temp.z_err('5.authenticated_pagamentos', 'select count(*) from public.fn_aluno_pagamentos_programa()');
reset role;
set local role anon;
select pg_temp.z_err('5.anon_pagamentos', 'select count(*) from public.fn_aluno_pagamentos_programa()');
reset role;

-- ─── 4. Inlining (como postgres): o corpo aparece no plano ────────────────────────────────────────────────────────
select pg_temp.z_explain('4.inline', 'select count(*) from public.fn_aluno_pagamentos_programa()');

-- ─── 6. ultima_paga_em coerente com as flags ───────────────────────────────────────────────────────────────────────
select pg_temp.z_q('6.ultima_paga_em_coerente', $q$select count(*) filter (where (pg_hm or pg_catalogo or pg_aurum or pg_mmd) and ultima_paga_em is null),
  count(*) filter (where not (pg_hm or pg_catalogo or pg_aurum or pg_mmd) and ultima_paga_em is not null) from public.fn_aluno_pagamentos_programa()$q$);

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003a',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
