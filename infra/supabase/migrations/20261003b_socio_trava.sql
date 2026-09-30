-- 20261003b — Trava de vínculo de sócio em public.thb_alunos (desenho 1.4)
--
-- O QUE FAZ
--   Trigger BEFORE INSERT OR UPDATE OF socio_de_aluno_id → public.fn_thb_alunos_trava_vinculo_socio().
--   Age só quando o vínculo MUDA (INSERT com FK não nula; UPDATE com FK distinta da anterior). Recusa com 23514:
--     (a) sócio de si mesmo (socio_de_aluno_id = id);
--     (b) par mútuo (o alvo já aponta para esta linha).
--   CADEIA NÃO É BLOQUEADA (vira item socio_cadeia na conciliação): cs.fn_hm_provisionar_socios (repo disparos, 0263)
--   grava socio_de_aluno_id e o app engole o erro — travar cadeia faria a Ativação falhar em silêncio.
--   Linhas já quebradas não são revalidadas: update de outra coluna não dispara (UPDATE OF + FK igual).
--   Nome trg_thb_alunos_* ordena DEPOIS de a_trg_thb_alunos_skip_noop (BEFORE dispara em ordem alfabética).
--   Limite conhecido: UPDATE OF não vê a coluna trocada por outro trigger BEFORE (nenhum troca a FK hoje).
--
-- AS 5 PERGUNTAS
--   escala: 1 leitura por PK (thb_alunos_pkey) por escrita que muda o vínculo; custo constante com 10x linhas.
--   índice: PK. Nenhum novo.
--   frequência: escritas de vínculo (tela, Ativação): dezenas/dia.
--   repetição: 1 select por linha alterada; update em massa de FK paga 1 lookup por linha (aceito).
--   reversão: drop trigger trg_thb_alunos_trava_vinculo_socio on public.thb_alunos;
--             drop function public.fn_thb_alunos_trava_vinculo_socio();
--
-- ENSAIO: infra/supabase/migrations/20261003b_ensaio.sql. Medido pelo analista em 30/09: 32 cs.hm_socios vigentes, 0 violam.

set local lock_timeout = '3s';

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
