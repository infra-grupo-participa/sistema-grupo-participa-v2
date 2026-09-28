-- 20260928z64 — Feriados bancários: dois achados BAIXOS do Kirad na z60 (já aplicada), corrigidos em migration nova.
--
-- NÃO APLICADA — coordenador aplica (apply_migration "fin_feriados_endurecer"). Independe da z63.
-- Obs.: o plano do Arthur reservava "z64" para o PDF (fatia 4); o coordenador realocou o número para esta correção.
--
-- (1) fin.recalcular_calendario_caixa() e fin.tg_feriados_recalcular() eram SECURITY DEFINER sem guarda. Não precisam:
--     a única porta de escrita em fin.feriados_bancarios é public.fn_fin_feriado_salvar (SECURITY DEFINER, dono
--     postgres), então o trigger já roda com os direitos do dono. Passam a SECURITY INVOKER (search_path '' mantido).
--     Ninguém além do dono consegue escrever em feriados (sem grant), logo ninguém dispara o recálculo com outro papel.
-- (2) fn_fin_feriado_salvar: (a) trilha só-acréscimo fin.feriados_bancarios_log (dia, antes, depois, por, em) gravada
--     pela própria RPC; (b) nada mudou (nome e ativo iguais, "is not distinct from") → devolve a linha e SAI sem
--     escrever — sem UPDATE, o trigger AFTER STATEMENT não dispara e o calendário (8 mil linhas) não é refeito.
--     Mesma assinatura, mesmo RETURNS TABLE, mesma ACL. Guarda: o corpo vivo tem que ser o da z60.
--
-- REVERSÃO (uma transação):
--   begin;
--   alter function fin.recalcular_calendario_caixa() security definer;
--   alter function fin.tg_feriados_recalcular() security definer;
--   -- recolocar o corpo da z60 em public.fn_fin_feriado_salvar (20260928z60 linhas 268–293, create or replace);
--   alter table fin.feriados_bancarios_log rename to feriados_bancarios_log_arquivada_z64;   -- não apagar
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_oid oid := to_regprocedure('public.fn_fin_feriado_salvar(date,text,boolean)');
  v_src text;
  v_res text;
  e_src text := $esperado$
#variable_conflict use_column
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_dia is null or p_dia < date '2015-01-01' or p_dia > date '2036-12-31' then
    raise exception 'Data fora do calendário de caixa (2015 a 2036).' using errcode = '22023';
  end if;
  if p_ativo is null then
    raise exception 'Informe se o feriado está ativo.' using errcode = '22023';
  end if;
  if coalesce(btrim(p_nome), '') = '' or length(btrim(p_nome)) > 120 then
    raise exception 'Nome do feriado vazio ou longo demais (até 120).' using errcode = '22023';
  end if;
  return query
  insert into fin.feriados_bancarios as f (dia, nome, ativo, fonte, criado_por)
  values (p_dia, btrim(p_nome), p_ativo, 'manual (tela do Financeiro)', v_uid)
  on conflict (dia) do update
     set nome = excluded.nome, ativo = excluded.ativo, atualizado_por = v_uid, atualizado_em = now()
  returning f.dia, f.nome, f.ativo, f.fonte;
end $esperado$;
begin
  if v_oid is null or to_regprocedure('fin.recalcular_calendario_caixa()') is null
     or to_regprocedure('fin.tg_feriados_recalcular()') is null then
    raise exception 'z64: aplicar a z60 antes';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_feriado_salvar' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'z64: há sobrecarga viva de fn_fin_feriado_salvar — conferir pg_get_function_arguments';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_oid;
  if regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(e_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> 'TABLE(diadate,nometext,ativoboolean,fontetext)' then
    raise exception 'z64: corpo vivo de fn_fin_feriado_salvar diverge da z60. Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;
  if (select count(*) from pg_proc p
       where p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure)
         and p.prosecdef and p.proconfig = array['search_path=""']) <> 2 then
    raise exception 'z64: recalcular_calendario_caixa / tg_feriados_recalcular não estão como a z60 deixou (definer, search_path vazio)';
  end if;
  if to_regclass('fin.feriados_bancarios_log') is not null then
    raise exception 'z64: fin.feriados_bancarios_log já existe — z64 já aplicada?';
  end if;
end $guarda$;


-- ─── 1. Recálculo sem SECURITY DEFINER ──────────────────────────────────────────────────────────────────────────────
alter function fin.recalcular_calendario_caixa() security invoker;
alter function fin.tg_feriados_recalcular() security invoker;


-- ─── 2. Trilha só-acréscimo ─────────────────────────────────────────────────────────────────────────────────────────
create table fin.feriados_bancarios_log (
  id      bigint generated always as identity primary key,
  dia     date not null,
  antes   jsonb,
  depois  jsonb not null,
  por     uuid,
  em      timestamptz not null default now()
);
create index feriados_bancarios_log_dia_idx on fin.feriados_bancarios_log (dia, em);
comment on table fin.feriados_bancarios_log is
  'Trilha só-acréscimo das mudanças de feriado bancário (z64), gravada por public.fn_fin_feriado_salvar. '
  'UPDATE/DELETE/TRUNCATE barrados.';
alter table fin.feriados_bancarios_log enable row level security;
revoke all on fin.feriados_bancarios_log from public, anon, authenticated;
revoke all on sequence fin.feriados_bancarios_log_id_seq from public, anon, authenticated;

create function fin.tg_feriados_log_so_acrescimo()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  raise exception 'A trilha de feriados só recebe acréscimo.' using errcode = '42501';
end $$;
revoke all on function fin.tg_feriados_log_so_acrescimo() from public, anon, authenticated;

create trigger feriados_log_so_acrescimo before update or delete on fin.feriados_bancarios_log
  for each row execute function fin.tg_feriados_log_so_acrescimo();
create trigger feriados_log_nao_trunca before truncate on fin.feriados_bancarios_log
  for each statement execute function fin.tg_feriados_log_so_acrescimo();


-- ─── 3. Porta de escrita: trilha + saída cedo quando nada mudou ─────────────────────────────────────────────────────
create or replace function public.fn_fin_feriado_salvar(p_dia date, p_nome text, p_ativo boolean)
returns table (dia date, nome text, ativo boolean, fonte text)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_nome  text := btrim(p_nome);
  v_antes fin.feriados_bancarios;
  v_dep   fin.feriados_bancarios;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_dia is null or p_dia < date '2015-01-01' or p_dia > date '2036-12-31' then
    raise exception 'Data fora do calendário de caixa (2015 a 2036).' using errcode = '22023';
  end if;
  if p_ativo is null then
    raise exception 'Informe se o feriado está ativo.' using errcode = '22023';
  end if;
  if coalesce(v_nome, '') = '' or length(v_nome) > 120 then
    raise exception 'Nome do feriado vazio ou longo demais (até 120).' using errcode = '22023';
  end if;

  select * into v_antes from fin.feriados_bancarios f where f.dia = p_dia for update;
  if found and (v_antes.nome, v_antes.ativo) is not distinct from (v_nome, p_ativo) then
    -- nada mudou: sem escrita, sem trilha, sem recálculo do calendário
    return query select v_antes.dia, v_antes.nome, v_antes.ativo, v_antes.fonte;
    return;
  end if;

  insert into fin.feriados_bancarios as f (dia, nome, ativo, fonte, criado_por)
  values (p_dia, v_nome, p_ativo, 'manual (tela do Financeiro)', v_uid)
  on conflict (dia) do update
     set nome = excluded.nome, ativo = excluded.ativo, atualizado_por = v_uid, atualizado_em = now()
  returning f.* into v_dep;

  insert into fin.feriados_bancarios_log (dia, antes, depois, por)
  values (p_dia, case when v_antes.dia is not null then to_jsonb(v_antes) end, to_jsonb(v_dep), v_uid);

  return query select v_dep.dia, v_dep.nome, v_dep.ativo, v_dep.fonte;
end $$;
revoke all on function public.fn_fin_feriado_salvar(date, text, boolean) from public, anon;
grant execute on function public.fn_fin_feriado_salvar(date, text, boolean) to authenticated;


-- ─── 4. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_adm   uuid;
  v_ok    boolean;
  v_xmin  text;
  v_n     int;
begin
  -- 4.1 atributos e grants
  if (select count(*) from pg_proc p
       where p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure)
         and not p.prosecdef and p.proconfig = array['search_path=""']) <> 2 then
    raise exception 'z64: recálculo continua SECURITY DEFINER (ou perdeu o search_path)';
  end if;
  if has_table_privilege('anon', 'fin.feriados_bancarios_log', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.feriados_bancarios_log', 'select,insert,update,delete,truncate,references,trigger')
     or not (select relrowsecurity from pg_class where oid = 'fin.feriados_bancarios_log'::regclass)
     or has_function_privilege('anon', 'fin.recalcular_calendario_caixa()', 'execute')
     or has_function_privilege('authenticated', 'fin.recalcular_calendario_caixa()', 'execute')
     or has_function_privilege('authenticated', 'fin.tg_feriados_recalcular()', 'execute')
     or has_function_privilege('authenticated', 'fin.tg_feriados_log_so_acrescimo()', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_feriado_salvar(date,text,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_feriado_salvar(date,text,boolean)', 'execute') then
    raise exception 'z64: grant fora do esperado (conferir relacl/proacl)';
  end if;
  if exists (select 1 from pg_proc p
              where p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure,
                              'fin.tg_feriados_log_so_acrescimo()'::regprocedure,
                              'public.fn_fin_feriado_salvar(date,text,boolean)'::regprocedure)
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z64: função com EXECUTE para PUBLIC (ou proacl nulo)';
  end if;

  -- 4.2 sem sessão → 42501
  v_ok := false;
  begin
    perform * from public.fn_fin_feriado_salvar(date '2026-12-24', 'teste', true);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z64: fn_fin_feriado_salvar respondeu sem sessão'; end if;

  -- 4.3 com sessão (admin ativo, claims locais só aqui): grava + trilha + recálculo (trigger invoker);
  --     repetir igual = sem trilha e sem recálculo (xmin do calendário não muda); desligar = trilha + volta a data.
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z64: nenhum perfil admin ativo para conferir a RPC'; end if;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform * from public.fn_fin_feriado_salvar(date '2026-12-24', 'teste z64', true);
    if (select x.entra_em from fin.recebimento(date '2026-12-22', 100) x) is distinct from date '2026-12-28' then
      raise exception 'z64: feriado novo não recalculou o calendário (trigger invoker)';
    end if;
    if (select count(*) from fin.feriados_bancarios_log l
         where l.dia = date '2026-12-24' and l.antes is null and l.por = v_adm and l.depois ->> 'nome' = 'teste z64') <> 1 then
      raise exception 'z64: trilha da criação ausente';
    end if;
    select xmin::text into v_xmin from fin.calendario_caixa where dia = date '2026-12-24';
    perform * from public.fn_fin_feriado_salvar(date '2026-12-24', '  teste z64 ', true);   -- igual (após btrim)
    if (select xmin::text from fin.calendario_caixa where dia = date '2026-12-24') is distinct from v_xmin
       or (select count(*) from fin.feriados_bancarios_log where dia = date '2026-12-24') <> 1 then
      raise exception 'z64: salvar sem mudança recalculou o calendário ou gravou trilha';
    end if;
    perform * from public.fn_fin_feriado_salvar(date '2026-12-24', 'teste z64', false);
    select count(*) into v_n from fin.feriados_bancarios_log
     where dia = date '2026-12-24' and antes ->> 'ativo' = 'true' and depois ->> 'ativo' = 'false';
    if v_n <> 1 or (select x.entra_em from fin.recebimento(date '2026-12-22', 100) x) is distinct from date '2026-12-24' then
      raise exception 'z64: desligar o feriado não gravou a trilha ou não devolveu o dia útil';
    end if;
    v_ok := false;
    begin
      delete from fin.feriados_bancarios_log where dia = date '2026-12-24';
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z64: DELETE na trilha de feriados não foi barrado'; end if;
    perform set_config('request.jwt.claims', '', true);
    raise exception using errcode = 'P0001', message = 'z64_desfaz_teste';
  exception when raise_exception then
    if sqlerrm <> 'z64_desfaz_teste' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from fin.feriados_bancarios where dia = date '2026-12-24')
     or exists (select 1 from fin.feriados_bancarios_log)
     or (select x.entra_em from fin.recebimento(date '2026-12-22', 100) x) is distinct from date '2026-12-24' then
    raise exception 'z64: teste não foi desfeito';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar; cada bloco é UMA chamada — o MCP é autocommit) ═════════════════════════════
/*
-- P1) Atributos vivos: recálculo sem definer; RPC com definer; ACL sem PUBLIC.
select p.oid::regprocedure, p.prosecdef, p.proconfig, p.proacl from pg_proc p
 where p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure,
                 'public.fn_fin_feriado_salvar(date,text,boolean)'::regprocedure);
select relname, relacl, relrowsecurity from pg_class where oid = 'fin.feriados_bancarios_log'::regclass;

-- P2) Com quem OPERA o financeiro (escreve → begin…rollback na MESMA chamada). Esperado: 1 linha de trilha na criação,
--     nenhuma na repetição; entra_em 22/12 → 28/12; explain da repetição SEM "Trigger feriados_recalcula".
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_OPERA_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_feriado_salvar(date '2026-12-24', 'Véspera de Natal (teste)', true);
explain (analyze, buffers) select * from public.fn_fin_feriado_salvar(date '2026-12-24', 'Véspera de Natal (teste)', true);
reset role;
select dia, antes is null criacao, depois ->> 'nome' nome, por, em from fin.feriados_bancarios_log;
select entra_em from fin.recebimento(date '2026-12-22', 100);
rollback;
*/
