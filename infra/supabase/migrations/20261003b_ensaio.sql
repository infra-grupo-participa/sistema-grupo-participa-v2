-- 20261003b — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada.
-- Alunos fictícios 00000000-0000-4000-8000-0000000003b1..b9 (inseridos e desfeitos no rollback).
-- Esperados:
--   0.triggers_antes            = a_trg_thb_alunos_skip_noop, trg_aluno_retornou, trg_thb_alunos_historico
--   1.self_update / 1.self_insert = 23514 … (caso=autorreferencia)
--   2.par_ida = SEM ERRO · 2.par_volta = 23514 … · 2.par_insert_ok = SEM ERRO
--   3.cadeia = SEM ERRO (cadeia passa)
--   4.par_antigo_outra_coluna = SEM ERRO · 4.par_antigo_mesma_fk = SEM ERRO · 4.par_antigo_troca_fk = SEM ERRO (sai do par)
--   5.fk_para_null = SEM ERRO
--   6.hm_socios_vigentes = (32, 0): vigentes, que cairiam na trava hoje (analista 30/09: 32 e 0). >0 = PARAR e listar.
--   7.triggers_depois = trava depois de a_trg_thb_alunos_skip_noop; 7.explain_trava = Index Scan thb_alunos_pkey

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

select pg_temp.z_q('0.triggers_antes', $q$select string_agg(tgname, ', ' order by tgname) from pg_trigger where tgrelid = 'public.thb_alunos'::regclass and not tgisinternal$q$);

-- ─── Migration (cópia literal do corpo da 20261003b) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_n int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'thb_alunos' and column_name = 'socio_de_aluno_id'
                    and data_type = 'uuid') then
    raise exception '20261003b: public.thb_alunos.socio_de_aluno_id ausente ou não uuid';
  end if;
  -- nenhum outro trigger BEFORE (além dos 2 conhecidos) que possa trocar a FK antes da trava
  select count(*) into v_n
    from pg_trigger t
   where t.tgrelid = 'public.thb_alunos'::regclass and not t.tgisinternal
     and (t.tgtype & 2) = 2   -- BEFORE
     and t.tgname not in ('a_trg_thb_alunos_skip_noop', 'trg_aluno_retornou', 'trg_thb_alunos_trava_vinculo_socio');
  if v_n > 0 then
    raise exception '20261003b: % trigger(s) BEFORE novo(s) em thb_alunos — conferir se mexem em socio_de_aluno_id antes de aplicar', v_n;
  end if;
end $guarda$;

-- ─── 1. Função do trigger ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_thb_alunos_trava_vinculo_socio()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_alvo_fk uuid;
begin
  -- guarda: só roda como trigger desta tabela
  if tg_table_schema <> 'public' or tg_table_name <> 'thb_alunos' or tg_when <> 'BEFORE' then
    raise exception 'fn_thb_alunos_trava_vinculo_socio: uso restrito ao trigger de public.thb_alunos' using errcode = '42501';
  end if;
  if new.socio_de_aluno_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.socio_de_aluno_id is not distinct from old.socio_de_aluno_id then
    return new;
  end if;

  if new.socio_de_aluno_id = new.id then
    raise exception 'Vínculo de sócio inválido: o aluno não pode ser sócio de si mesmo nem de quem já é sócio dele.'
      using errcode = '23514', detail = 'caso=autorreferencia', hint = 'Definir o titular pela conciliação de alunos.';
  end if;

  select a.socio_de_aluno_id into v_alvo_fk
    from public.thb_alunos a
   where a.id = new.socio_de_aluno_id
     for share;
  if v_alvo_fk is not distinct from new.id and v_alvo_fk is not null then
    raise exception 'Vínculo de sócio inválido: o aluno não pode ser sócio de si mesmo nem de quem já é sócio dele.'
      using errcode = '23514', detail = 'caso=par_mutuo', hint = 'Definir o titular pela conciliação de alunos.';
  end if;

  return new;
end
$fn$;

comment on function public.fn_thb_alunos_trava_vinculo_socio() is
  '20261003b: recusa (23514) sócio de si mesmo e par mútuo em thb_alunos.socio_de_aluno_id. Cadeia passa (vira item de conciliação).';

revoke all on function public.fn_thb_alunos_trava_vinculo_socio() from public, anon, authenticated;

drop trigger if exists trg_thb_alunos_trava_vinculo_socio on public.thb_alunos;
create trigger trg_thb_alunos_trava_vinculo_socio
  before insert or update of socio_de_aluno_id on public.thb_alunos
  for each row execute function public.fn_thb_alunos_trava_vinculo_socio();

-- ─── 2. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'public.fn_thb_alunos_trava_vinculo_socio()'::regprocedure
                    and p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261003b: função da trava sem SECURITY DEFINER/search_path';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_thb_alunos_trava_vinculo_socio()'::regprocedure
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE')))
     or has_function_privilege('anon', 'public.fn_thb_alunos_trava_vinculo_socio()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_thb_alunos_trava_vinculo_socio()', 'execute') then
    raise exception '20261003b: função da trava executável por PUBLIC/anon/authenticated';
  end if;
  -- ordem: a trava dispara depois do skip_noop
  if (select array_agg(t.tgname order by t.tgname) from pg_trigger t
       where t.tgrelid = 'public.thb_alunos'::regclass and not t.tgisinternal and (t.tgtype & 2) = 2)
     <> array['a_trg_thb_alunos_skip_noop', 'trg_aluno_retornou', 'trg_thb_alunos_trava_vinculo_socio']::name[] then
    raise exception '20261003b: ordem/lista de triggers BEFORE diferente do esperado';
  end if;
end $confere$;

-- ─── Fictícios ──────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.thb_alunos (id, nome) values
  ('00000000-0000-4000-8000-0000000003b1', 'ZZ ENSAIO B1'), ('00000000-0000-4000-8000-0000000003b2', 'ZZ ENSAIO B2'),
  ('00000000-0000-4000-8000-0000000003b3', 'ZZ ENSAIO B3'), ('00000000-0000-4000-8000-0000000003b6', 'ZZ ENSAIO B6'),
  ('00000000-0000-4000-8000-0000000003b7', 'ZZ ENSAIO B7');

-- 1. autorreferência
select pg_temp.z_err('1.self_update', $q$update public.thb_alunos set socio_de_aluno_id = id where id = '00000000-0000-4000-8000-0000000003b1'$q$);
select pg_temp.z_err('1.self_insert', $q$insert into public.thb_alunos (id, nome, socio_de_aluno_id) values ('00000000-0000-4000-8000-0000000003b9', 'ZZ ENSAIO B9', '00000000-0000-4000-8000-0000000003b9')$q$);
-- 2. par mútuo
select pg_temp.z_err('2.par_ida', $q$update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b2' where id = '00000000-0000-4000-8000-0000000003b1'$q$);
select pg_temp.z_err('2.par_volta', $q$update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b1' where id = '00000000-0000-4000-8000-0000000003b2'$q$);
select pg_temp.z_err('2.par_insert_ok', $q$insert into public.thb_alunos (id, nome, socio_de_aluno_id) values ('00000000-0000-4000-8000-0000000003b8', 'ZZ ENSAIO B8', '00000000-0000-4000-8000-0000000003b2')$q$);
-- 3. cadeia B3 → B1 → B2: passa
select pg_temp.z_err('3.cadeia', $q$update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b1' where id = '00000000-0000-4000-8000-0000000003b3'$q$);
-- 4. par já quebrado (criado com a trava desligada): update de outra coluna e da mesma FK passam
alter table public.thb_alunos disable trigger trg_thb_alunos_trava_vinculo_socio;
update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b7' where id = '00000000-0000-4000-8000-0000000003b6';
update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b6' where id = '00000000-0000-4000-8000-0000000003b7';
alter table public.thb_alunos enable trigger trg_thb_alunos_trava_vinculo_socio;
select pg_temp.z_err('4.par_antigo_outra_coluna', $q$update public.thb_alunos set nome = 'ZZ ENSAIO B6 x' where id = '00000000-0000-4000-8000-0000000003b6'$q$);
select pg_temp.z_err('4.par_antigo_mesma_fk', $q$update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b7', nome = 'ZZ ENSAIO B6 y' where id = '00000000-0000-4000-8000-0000000003b6'$q$);
select pg_temp.z_err('4.par_antigo_troca_fk', $q$update public.thb_alunos set socio_de_aluno_id = '00000000-0000-4000-8000-0000000003b2' where id = '00000000-0000-4000-8000-0000000003b6'$q$);
-- 5. limpar vínculo sempre passa
select pg_temp.z_err('5.fk_para_null', $q$update public.thb_alunos set socio_de_aluno_id = null where id = '00000000-0000-4000-8000-0000000003b1'$q$);

-- 6. cs.hm_socios vigentes que cairiam na trava hoje (mesma busca de cs.fn_hm_provisionar_socios, 0263)
select pg_temp.z_q('6.hm_socios_vigentes', $q$
  with s as (
    select hs.id, ch.aluno_id as titular,
           coalesce(hs.aluno_id, (select a.id from public.thb_alunos a
                                   where lower(trim(a.email)) = lower(trim(hs.email)) and coalesce(trim(hs.email), '') <> ''
                                   limit 1)) as socio
      from cs.hm_socios hs
      join cs.contatos_hm ch on ch.id = hs.contato_hm_id
     where hs.substituido_em is null and ch.aluno_id is not null)
  select count(*) vigentes,
         count(*) filter (where s.socio is not null
                            and (s.socio = s.titular
                                 or exists (select 1 from public.thb_alunos t where t.id = s.titular and t.socio_de_aluno_id = s.socio))
                            and exists (select 1 from public.thb_alunos x where x.id = s.socio
                                          and x.socio_de_aluno_id is distinct from s.titular)) cairiam
    from s$q$);

-- 7. ordem e custo
select pg_temp.z_q('7.triggers_depois', $q$select string_agg(tgname, ', ' order by tgname) from pg_trigger where tgrelid = 'public.thb_alunos'::regclass and not tgisinternal and (tgtype & 2) = 2$q$);
select pg_temp.z_explain('7.explain_trava', $q$select a.socio_de_aluno_id from public.thb_alunos a where a.id = '00000000-0000-4000-8000-0000000003b2' for share$q$);

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003b',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
