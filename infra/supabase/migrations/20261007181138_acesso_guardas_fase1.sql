-- 20261007s: níveis de acesso, fase 1 ("velho OU novo"). Cada guarda passa a aceitar a regra antiga OU a nova
-- (acesso.*, da 20261007180503). Ninguém perde nada; quem só tem vínculo (ex.: Luis Fernando, Web) já ganha.
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007181138 (nome acesso_guardas_fase1, era 20261007s), pelo aplica_sql.py aplicar
-- + insert em supabase_migrations.schema_migrations na mesma transação. md5 gravado = e8547c35d6f3723e813699f66c0783bc = este arquivo
-- antes desta troca de STATUS. Ensaio: 20261007181138_ensaio.sql. Relatório: 20261007181138.explain.md.
--
-- POR QUE
--   Regra do Victor Hugo (07/10/2026): líder edita a própria área e só vê as outras; financeiro só quem foi nomeado.
--   Hoje a guarda do Marketing (mkt.pode_ver) é só gp_is_admin() e serve para LEITURA e ESCRITA juntas; e 124 funções
--   do GPS, 90 policies, turmas, remoção de acessos e pedidos de alteração dependem de gp_is_admin() ou do cargo. A
--   fase 2 (rebaixar quem não é master) só pode rodar depois que cada guarda souber o departamento: é esta migration.
--
-- O QUE FAZ (todas as funções recriadas guardam o corpo anterior em acesso.corpo_antes, para reverter)
--   1. Financeiro, CPF, setores antigos, Comercial, remoção de acessos e pedidos de alteração: regra antiga OR nova.
--      - gp_pode_ver_financeiro    OR acesso.tem('financeiro.ver')
--      - gp_pode_operar_financeiro OR acesso.tem('financeiro.operar')
--      - gp_pode_ver_cpf           OR acesso.tem('cpf.ver')
--      - gp_pode_editar(setor)     OR (ativacao, placas, depoimentos, centro_controle, remocao_acessos,
--                                      pedidos_alteracao → editar educacional; social_media → marketing/social-media;
--                                      comercial → editar comercial; financeiro → financeiro.operar)
--      - crm.eh_gestor             OR master OR responsável do comercial
--      - crm.eh_comercial          OR vínculo no comercial (decisão 2: quem é do Comercial usa tudo de lá)
--      - ra_pode_ver, pa_pode_pedir OR editar educacional
--   2. Marketing: mkt.pode_ver(area) vira LEITURA = gp_is_admin() OR acesso.pode_ver('marketing', área);
--      nasce mkt.pode_editar(area) = gp_is_admin() OR acesso.pode_editar('marketing', área). As 31 RPCs de escrita
--      (as voláteis que chamavam mkt.pode_ver) passam a chamar mkt.pode_editar. mkt_pagina_salvar → área web;
--      mkt_projeto_salvar → área trafego ("o cara de web n pode iniciar projeto no trafego"). trafego_receita
--      (dinheiro) passa a exigir também gp_pode_ver_financeiro().
--   3. gp_is_admin() em funções e policies, por departamento, vira (gp_is_admin() OR editar <departamento>):
--      - educacional: schema gps inteiro (funções e policies), policies de storage gps_*, depoimentos/cursos/tags
--        (public.gp_*), hm_liberacoes, fn_turma_criar, fn_turma_set_atual, ra_definir_responsavel, ra_meu_papel;
--      - marketing/mensageria: mkt_msg_anonimizar_disparo, mkt_msg_anonimizar_recusa, mkt_msg_recusas_listar;
--      - infra: ops_saude_rotinas.
--      Fica SÓ com gp_is_admin() (vira master na fase 3, regra mais fechada quando a fonte não decide):
--      compradores, compras, ht_editions, ht_product_catalog, hm_product_catalog, gp_rate_limit_log e pessoas.*.
--   4. fn_fin_board: quem não pode ver financeiro passa a receber ERRO 42501 em vez de lista vazia
--      (public.gp_exige_ver_financeiro()).
--
-- AS 5 PERGUNTAS
--   escala: ~170 funções recriadas e ~85 policies alteradas, uma vez. índice: as guardas novas são busca por PK/índice
--   parcial em acesso.* (explain no relatório); nas policies a chamada nova vai em (select …) para virar InitPlan.
--   frequência: toda RPC e todo select com policy. repetição: 1 avaliação por comando. reversão: acesso.corpo_antes
--   guarda cada corpo e cada expressão de policy anteriores (bloco REVERSÃO no fim).
--
-- IDEMPOTENTE: função cujo corpo já cita a regra nova é pulada; policy já reescrita é pulada; as redefinições
--   explícitas conferem o md5 do corpo antigo OU a marca da regra nova.

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- 0. Guarda de premissa
do $g$
declare r record;
begin
  if to_regprocedure('acesso.pode_editar(text,text)') is null or to_regprocedure('public.gp_acesso_pode_editar(text,text)') is null then
    raise exception '20261007s: falta a fase 0 (20261007180503_acesso_fundacao)';
  end if;
  for r in select * from (values
      ('public.gp_pode_ver_financeiro()',    '00a14c04f83bffe66bd77f7c09a361f0'),
      ('public.gp_pode_operar_financeiro()', '81e7fdc30a1e3feff14fcf68275b3f78'),
      ('public.gp_pode_ver_cpf()',           'bc8d784281b425ad6355f2a349874983'),
      ('public.gp_pode_editar(text)',        '025f990953e66202283c21b0a20faeb5'),
      ('crm.eh_gestor()',                    '298a341f791efa57f69ed5f1c69e04bc'),
      ('crm.eh_comercial()',                 'f089810f31ec324999f56fb636b5be6b'),
      ('public.ra_pode_ver()',               'e35d5eb0a68fce5fb5c668e5b7c6dfb6'),
      ('public.pa_pode_pedir()',             '0185f19d27de163eb4557051c09fa64c'),
      ('mkt.pode_ver(text)',                 '39c6bacb935c0dbdd8962b2e7a61df95')) v(sig, md5_antigo)
  loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.sig)
                    and (md5(p.prosrc) = r.md5_antigo or p.prosrc like '%20261007s%')) then
      raise exception '20261007s: corpo vivo de % mudou (nem o antigo nem o desta migration). Reler pg_get_functiondef.', r.sig;
    end if;
  end loop;
end
$g$;

-- 1. Onde guardar o que muda (reversão)
create table if not exists acesso.corpo_antes (
  tipo        text not null check (tipo in ('funcao', 'policy')),
  alvo        text not null,
  md5         text,
  definicao   text,
  qual        text,
  with_check  text,
  migration   text not null,
  guardado_em timestamptz not null default now(),
  primary key (tipo, alvo, migration)
);
alter table acesso.corpo_antes enable row level security;
revoke all on acesso.corpo_antes from public, anon, authenticated;

create or replace function acesso.guardar_funcao(p_oid oid) returns void
language sql set search_path = '' as $f$
  insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
  select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007s'
    from pg_proc p where p.oid = p_oid
  on conflict do nothing
$f$;
revoke all on function acesso.guardar_funcao(oid) from public, anon, authenticated;

select acesso.guardar_funcao(to_regprocedure(s)) from unnest(array[
  'public.gp_pode_ver_financeiro()', 'public.gp_pode_operar_financeiro()', 'public.gp_pode_ver_cpf()',
  'public.gp_pode_editar(text)', 'crm.eh_gestor()', 'crm.eh_comercial()', 'public.ra_pode_ver()',
  'public.pa_pode_pedir()', 'mkt.pode_ver(text)', 'public.fn_fin_board(text,text)']) s;

-- 2. Redefinições explícitas: corpo antigo inteiro OR regra nova
create or replace function public.gp_pode_ver_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and (
        p.cargo in ('dev','admin')
        or (p.cargo in ('gestor','operador') and 'financeiro' = any(coalesce(p.areas,'{}')))
      )
  ) or coalesce(acesso.tem('financeiro.ver'), false);  -- 20261007s
$function$;

create or replace function public.gp_pode_operar_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and (
        p.cargo in ('dev','admin')
        or (p.cargo = 'gestor' and 'financeiro' = any(coalesce(p.areas,'{}')))
        or (p.cargo = 'operador'
            and 'financeiro' = any(coalesce(p.areas,'{}'))
            and 'financeiro.operar' = any(coalesce(p.funcoes,'{}')))
      )
  ) or coalesce(acesso.tem('financeiro.operar'), false);  -- 20261007s
$function$;

create or replace function public.gp_pode_ver_cpf()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and (p.cargo in ('dev','admin') or p.pode_ver_cpf_completo is true)
  ) or coalesce(acesso.tem('cpf.ver'), false);  -- 20261007s
$function$;

create or replace function public.gp_pode_editar(p_setor text)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfis p
    WHERE p.id = auth.uid()
      AND p.status = 'ativo'
      AND (
        p.cargo IN ('dev','admin')
        OR (p.cargo = 'gestor' AND p_setor = ANY(coalesce(p.areas,'{}')))
        OR (p.cargo = 'operador' AND p_setor = ANY(coalesce(p.areas,'{}'))
            AND EXISTS (SELECT 1 FROM unnest(coalesce(p.funcoes,'{}')) f WHERE f LIKE p_setor || '.%'))
      )
  ) OR coalesce(case  -- 20261007s: setor antigo → departamento/área de acesso.*
         when p_setor in ('ativacao', 'placas', 'depoimentos', 'centro_controle', 'remocao_acessos', 'pedidos_alteracao')
           then acesso.pode_editar('educacional')
         when p_setor = 'social_media' then acesso.pode_editar('marketing', 'social-media')
         when p_setor = 'comercial' then acesso.pode_editar('comercial')
         when p_setor = 'financeiro' then acesso.tem('financeiro.operar')
       end, false);
$function$;

create or replace function crm.eh_gestor()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce((
    select p.status = 'ativo'
       and (p.cargo in ('dev', 'admin') or (p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))))
      from public.perfis p where p.id = (select auth.uid())
  ), false)
  or coalesce(acesso.eh_master(), false)  -- 20261007s: master ou responsável do comercial
  or exists (select 1 from acesso.vinculo v where v.perfil_id = acesso.eu() and v.vigente_ate is null
               and v.departamento = 'comercial' and v.area is null and v.papel = 'responsavel');
$function$;

create or replace function crm.eh_comercial()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false)
      or coalesce(acesso.pode_editar('comercial'), false);  -- 20261007s
$function$;

create or replace function public.ra_pode_ver()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and (p.cargo in ('dev', 'admin')
           or (p.cargo in ('gestor', 'operador') and 'remocao_acessos' = any(coalesce(p.areas, '{}'))))
  ) or coalesce(acesso.pode_editar('educacional'), false);  -- 20261007s
$function$;

create or replace function public.pa_pode_pedir()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_eh_equipe(), false) and (exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and (p.cargo in ('dev', 'admin')
            or (p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))))
    or coalesce(acesso.pode_editar('educacional'), false));  -- 20261007s
$function$;

-- Marketing: leitura e escrita separadas
create or replace function mkt.pode_ver(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_is_admin(), false)
      or coalesce(acesso.pode_ver('marketing', acesso.area_mkt(p_area)), false);  -- 20261007s: leitura
$function$;

create or replace function mkt.pode_editar(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_is_admin(), false)
      or coalesce(acesso.pode_editar('marketing', acesso.area_mkt(p_area)), false);  -- 20261007s: escrita
$function$;
revoke all on function mkt.pode_editar(text) from public, anon, authenticated;

-- Financeiro: erro em vez de lista vazia
create or replace function public.gp_exige_ver_financeiro() returns boolean
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'sem acesso ao financeiro' using errcode = '42501';
  end if;
  return true;
end
$f$;
revoke all on function public.gp_exige_ver_financeiro() from public, anon;
grant execute on function public.gp_exige_ver_financeiro() to authenticated;

-- 3. Reescrita das funções, a partir do corpo VIVO (pg_get_functiondef), com o corpo anterior guardado
do $r$
declare
  r record; v_def text; v_n_esc int := 0; v_n_adm int := 0; v_n int;
  c_adm constant text := '(^|[^a-z_.])(public\.)?gp_is_admin\(\)';
begin
  -- 3.1 Marketing: escritas (voláteis) passam a mkt.pode_editar
  for r in select p.oid, p.proname, pg_get_functiondef(p.oid) def
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.provolatile = 'v' and p.prosrc ~ 'mkt\.pode_ver\(' loop
    perform acesso.guardar_funcao(r.oid);
    v_def := r.def;
    if r.proname = 'mkt_pagina_salvar' then v_def := replace(v_def, 'mkt.pode_ver()', 'mkt.pode_editar(''mkt_web'')');
    elsif r.proname = 'mkt_projeto_salvar' then v_def := replace(v_def, 'mkt.pode_ver()', 'mkt.pode_editar(''mkt_trafego'')');
    end if;
    v_def := replace(v_def, 'mkt.pode_ver(', 'mkt.pode_editar(');
    if v_def ~ 'mkt\.pode_editar\(\)' then
      raise exception '20261007s: % ficaria com mkt.pode_editar() sem área. Mapear a área.', r.proname;
    end if;
    execute v_def;
    v_n_esc := v_n_esc + 1;
  end loop;

  -- 3.2 receita do Tráfego exige financeiro
  select p.oid, pg_get_functiondef(p.oid) def into r from pg_proc p
   where p.oid = 'public.trafego_receita(bigint)'::regprocedure and p.prosrc !~ 'gp_pode_ver_financeiro';
  if found then
    perform acesso.guardar_funcao(r.oid);
    execute replace(r.def, 'mkt.pode_ver(''mkt_trafego'')',
                    '(mkt.pode_ver(''mkt_trafego'') and coalesce(public.gp_pode_ver_financeiro(), false))');
  end if;

  -- 3.3 fn_fin_board: erro, não lista vazia
  select p.oid, pg_get_functiondef(p.oid) def into r from pg_proc p
   where p.oid = 'public.fn_fin_board(text,text)'::regprocedure and p.prosrc !~ 'gp_exige_ver_financeiro';
  if found then
    if position('coalesce(public.gp_pode_ver_financeiro(), false)' in r.def) = 0 then
      raise exception '20261007s: fn_fin_board não tem mais o filtro esperado';
    end if;
    perform acesso.guardar_funcao(r.oid);
    execute replace(r.def, 'coalesce(public.gp_pode_ver_financeiro(), false)', 'public.gp_exige_ver_financeiro()');
  end if;

  -- 3.4 gp_is_admin() por departamento
  for r in
    select p.oid, pg_get_functiondef(p.oid) def,
           case when n.nspname = 'gps' or p.oid in ('public.fn_turma_criar(text,text,boolean)'::regprocedure,
                                                    'public.fn_turma_set_atual(smallint)'::regprocedure,
                                                    'public.ra_definir_responsavel(text,uuid)'::regprocedure,
                                                    'public.ra_meu_papel()'::regprocedure)
                  then '''educacional'', null'
                when p.proname in ('mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa', 'mkt_msg_recusas_listar')
                     and n.nspname = 'public' then '''marketing'', ''mensageria'''
                when p.oid = 'public.ops_saude_rotinas()'::regprocedure then '''infra'', null'
           end as alvo
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.prosrc ~ c_adm and p.prosrc !~ 'gp_acesso_pode_editar' and p.proname <> 'gp_is_admin'
  loop
    continue when r.alvo is null;  -- fora da lista: fica só com gp_is_admin (master na fase 3)
    perform acesso.guardar_funcao(r.oid);
    execute regexp_replace(r.def, c_adm,
      '\1(public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar(' || r.alvo || '), false))', 'g');
    v_n_adm := v_n_adm + 1;
  end loop;

  raise notice '20261007s: % escritas do Marketing e % funções com gp_is_admin reescritas', v_n_esc, v_n_adm;
end
$r$;

-- 4. Policies com gp_is_admin(), por departamento (educacional), com a expressão anterior guardada
do $p$
declare
  r record; v_q text; v_w text; v_sql text; v_n int := 0;
  c_adm constant text := '(^|[^a-z_.])(public\.)?gp_is_admin\(\)';
  c_novo constant text := '\1(public.gp_is_admin() OR (SELECT public.gp_acesso_pode_editar(''educacional''::text, NULL::text)))';
begin
  for r in
    select pol.schemaname, pol.tablename, pol.policyname, pol.qual, pol.with_check
      from pg_policies pol
     where (coalesce(pol.qual, '') ~ c_adm or coalesce(pol.with_check, '') ~ c_adm)
       and coalesce(pol.qual, '') || coalesce(pol.with_check, '') !~ 'gp_acesso_pode_editar'
       and (pol.schemaname = 'gps'
            or (pol.schemaname = 'storage' and pol.policyname like 'gps\_%')
            or (pol.schemaname = 'public' and pol.tablename in ('gp_depoimentos', 'gp_depoimento_cursos', 'gp_depoimento_tags',
                  'gp_cursos', 'gp_tags', 'gp_depoimento_transcription_jobs', 'hm_liberacoes')))
  loop
    insert into acesso.corpo_antes (tipo, alvo, qual, with_check, migration)
    values ('policy', r.schemaname || '.' || r.tablename || ':' || r.policyname, r.qual, r.with_check, '20261007s')
    on conflict do nothing;
    v_q := case when r.qual is not null then regexp_replace(r.qual, c_adm, c_novo, 'g') end;
    v_w := case when r.with_check is not null then regexp_replace(r.with_check, c_adm, c_novo, 'g') end;
    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename)
          || case when v_q is not null then format(' using (%s)', v_q) else '' end
          || case when v_w is not null then format(' with check (%s)', v_w) else '' end;
    execute v_sql;
    v_n := v_n + 1;
  end loop;
  raise notice '20261007s: % policies reescritas', v_n;
end
$p$;

-- 5. Pós-condição
do $c$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.provolatile = 'v' and p.prosrc ~ 'mkt\.pode_ver\(') then
    raise exception '20261007s: sobrou escrita do Marketing com mkt.pode_ver';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'gps' and p.prosrc ~ 'gp_is_admin\(\)' and p.prosrc !~ 'gp_acesso_pode_editar') then
    raise exception '20261007s: sobrou função do gps só com gp_is_admin';
  end if;
  if exists (select 1 from pg_policies pol where pol.schemaname = 'gps'
              and coalesce(pol.qual, '') || coalesce(pol.with_check, '') ~ 'gp_is_admin\(\)'
              and coalesce(pol.qual, '') || coalesce(pol.with_check, '') !~ 'gp_acesso_pode_editar') then
    raise exception '20261007s: sobrou policy do gps só com gp_is_admin';
  end if;
  if (select prosrc from pg_proc where oid = 'public.trafego_receita(bigint)'::regprocedure) !~ 'gp_pode_ver_financeiro' then
    raise exception '20261007s: trafego_receita sem a trava do financeiro';
  end if;
  if (select prosrc from pg_proc where oid = 'public.fn_fin_board(text,text)'::regprocedure) !~ 'gp_exige_ver_financeiro' then
    raise exception '20261007s: fn_fin_board sem a trava que dá erro';
  end if;
  if has_function_privilege('authenticated', 'mkt.pode_editar(text)', 'execute') then
    raise exception '20261007s: mkt.pode_editar executável pela API';
  end if;
end
$c$;

-- REVERSÃO (numa transação), a partir de acesso.corpo_antes:
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007s' and tipo = 'funcao' loop execute r.definicao; end loop;
--   for r in select * from acesso.corpo_antes where migration = '20261007s' and tipo = 'policy' loop
--     execute format('alter policy %I on %s', split_part(r.alvo, ':', 2), split_part(r.alvo, ':', 1))
--          || case when r.qual is not null then format(' using (%s)', r.qual) else '' end
--          || case when r.with_check is not null then format(' with check (%s)', r.with_check) else '' end;
--   end loop; end $v$;
-- drop function if exists mkt.pode_editar(text), public.gp_exige_ver_financeiro();
