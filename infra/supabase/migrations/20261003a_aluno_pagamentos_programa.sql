-- 20261003a — Fonte única do "pagou programa" (extração do CTE pag_email da 20261002e, resultado idêntico)
--
-- O QUE FAZ
--   1. public.fn_aluno_pagamentos_programa(): o CTE pag_email da 20261002e, literal (email, pg_hm, pg_impl, pg_sinal,
--      pg_catalogo, pg_aurum, pg_mmd) + ultima_paga_em (última compra paga que conta como programa).
--      language sql, stable, SECURITY INVOKER, sem SET → inlinável. Sem EXECUTE para public/anon/authenticated.
--   2. create or replace de public.fn_aluno_programas_safe(): o CTE pag_email passa a ler da função 1. Resto do corpo,
--      assinatura, saída, guarda e grants iguais (a conferência do passo 3 prova o ACL antes = depois).
--   Leitores da regra: fn_aluno_programas_safe (lista), 20261003c (sinal S2 do par), fn_aluno_conciliacao (fora da base).
--
-- AS 5 PERGUNTAS
--   escala: fin.vw_transacoes ~57 mil linhas (≈37 mil pagas); agregado por e-mail, 1 passada. 10x = 570 mil: hash agg
--     continua linear; se passar de 1 s vira materialização (fora daqui).
--   índice: nenhum novo. O corpo é o mesmo SQL da 20261002e; inlining mantém o plano (ensaio: explain antes/depois).
--   frequência: 1× por abertura da lista (programas_safe) + 1× por conciliação.
--   repetição: a regra passa a existir em 1 lugar; nenhuma query nova por tela.
--   reversão: bloco REVERSÃO no fim (corpo da 20261002e) + drop function public.fn_aluno_pagamentos_programa().
--
-- ENSAIO: infra/supabase/migrations/20261003a_ensaio.sql (begin … rollback). Esperado: EXCEPT antes×depois = 0 nos 2 sentidos.

set local lock_timeout = '3s';

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

-- ─── REVERSÃO (não executar junto; rodar só para desfazer) ──────────────────────────────────────────────────────────
-- 1) reaplicar a seção "1. Lista" da 20261002e trocando "create function" por "create or replace function"
--    (corpo com o CTE pag_email literal; create or replace preserva os grants);
-- 2) drop function public.fn_aluno_pagamentos_programa();   -- só depois de reverter a 20261003c/e, que a leem
