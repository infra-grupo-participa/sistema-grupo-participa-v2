-- 20261003c — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada,
-- DEPOIS de 20261003a e 20261003b aplicadas. A migration roda com as constantes reais (2 / 115): se a base mudou,
-- o ensaio para no raise da guarda — é o resultado esperado nesse caso (medir de novo).
-- ATENÇÃO: o passo 3 (reversão) faz ALTER TABLE … DISABLE TRIGGER: lock exclusivo em thb_alunos até o rollback
-- (o fim do arquivo vem logo depois; ~1 s).
-- Esperados:
--   0.antes                        = self 2 · pares 121 · historico H · audit N
--   1.depois                       = self 0 · pares 6 · historico H (igual) · audit N+117
--   1.alvos_por_caso               = autorreferencia 2 · par 115
--   1.linhas_mudadas_vs_snapshot   = 117 · 1.audit_origem = (117,117,0,117) · 1.audit_bate_com_mudadas = 0
--   1.evento                       = info | conciliacao | … | {"pares": 115, "linhas": 117, "autorreferencias": 2}
--   2.programas_delta              = CONFERIR (alunos cuja saída de fn_aluno_programas_safe muda)
--   3.reversao_except_*            = 0 e 0 · 3.reversao_audit = 117 · 3.trava_religada = O · 3.historico_final = H

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

-- ─── 0. ANTES ───────────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _z_snap on commit drop as
  select a.id, a.socio_de_aluno_id, a.eh_socio from public.thb_alunos a;
select pg_temp.z_q('0.antes', $q$select
  (select count(*) from public.thb_alunos a where a.cancelado_em is null and a.socio_de_aluno_id = a.id) self,
  (select count(*) from public.thb_alunos a join public.thb_alunos b on b.id = a.socio_de_aluno_id and b.socio_de_aluno_id = a.id
    where a.cancelado_em is null and b.cancelado_em is null and a.id < b.id) pares,
  (select count(*) from public.thb_alunos_historico) historico,
  (select count(*) from public.thb_alunos_audit_log) audit$q$);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
create temp table _z_prog_antes on commit drop as select * from public.fn_aluno_programas_safe();
reset role;

-- ─── Migration (cópia literal do corpo da 20261003c, constantes 2 / 115 como estão) ────────────────────────────────
do $c$
declare
  c_esperado_self   constant int := 2;     -- passo 0 (analista, 30/09/2026)
  c_esperado_pares  constant int := 115;   -- 121 pares; 115 com S1 unânime e sem contradição
  v_self   int;
  v_pares  int;
  v_linhas int;
  v_audit  int;
  v_def    text;
begin
  -- ─── 0. Guardas ───────────────────────────────────────────────────────────────────────────────────────────────────
  if to_regprocedure('public.fn_aluno_pagamentos_programa()') is null then
    raise exception '20261003c: aplicar a 20261003a antes (falta public.fn_aluno_pagamentos_programa())';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.thb_alunos'::regclass
                    and tgname = 'trg_thb_alunos_trava_vinculo_socio') then
    raise exception '20261003c: aplicar a 20261003b antes (falta trg_thb_alunos_trava_vinculo_socio)';
  end if;
  if exists (select 1 from public.thb_alunos_audit_log where origem = 'conciliacao_20261003') then
    raise exception '20261003c: já aplicada (há audit_log com origem conciliacao_20261003)';
  end if;
  select string_agg(pg_get_constraintdef(k.oid), ' | ') into v_def
    from pg_constraint k
   where k.conrelid = 'public.thb_system_events'::regclass and k.contype = 'c'
     and ((pg_get_constraintdef(k.oid) ilike '%fonte%' and pg_get_constraintdef(k.oid) not ilike '%conciliacao%')
       or (pg_get_constraintdef(k.oid) ilike '%tipo%'  and pg_get_constraintdef(k.oid) not ilike '%info%'));
  if v_def is not null then
    raise exception '20261003c: CHECK de thb_system_events recusaria o resumo (fonte conciliacao / tipo info): %', v_def;
  end if;

  -- ─── 1. Alvos ─────────────────────────────────────────────────────────────────────────────────────────────────────
  create temp table _c20261003_alvo (aluno_id uuid primary key, fk_anterior uuid not null, caso text not null) on commit drop;

  insert into _c20261003_alvo (aluno_id, fk_anterior, caso)
  with al as (
    select a.id, a.socio_de_aluno_id as fk, a.eh_socio, nullif(lower(trim(both from a.email)), '') as email_n
      from public.thb_alunos a
     where a.cancelado_em is null
  ),
  ep as (
    select e.email, e.pessoa_chave from fin.vw_email_pessoa e
  ),
  pag as (
    select coalesce(ep.pessoa_chave, '#email:' || pp.email) as chave,
           bool_or(pp.pg_hm or pp.pg_catalogo or pp.pg_aurum or pp.pg_mmd) as s2
      from public.fn_aluno_pagamentos_programa() pp
      left join ep on ep.email = pp.email
     group by 1
  ),
  sinal as (
    select al.id, al.fk, (al.eh_socio is false) as s1, coalesce(p.s2, false) as s2
      from al
      left join ep on ep.email = al.email_n
      left join pag p on p.chave = coalesce(ep.pessoa_chave, '#email:' || al.email_n)
  ),
  par as (
    select a.id as a_id, b.id as b_id, a.s1 as a_s1, b.s1 as b_s1, a.s2 as a_s2, b.s2 as b_s2
      from sinal a
      join sinal b on b.id = a.fk and b.fk = a.id
     where a.id < b.id
  )
  select case when p.a_s1 then p.a_id else p.b_id end,          -- titular: perde a FK
         case when p.a_s1 then p.b_id else p.a_id end,          -- FK anterior do titular = o outro lado
         'par'
    from par p
   where p.a_s1 <> p.b_s1
     and not (p.a_s1 and p.b_s2 and not p.a_s2)
     and not (p.b_s1 and p.a_s2 and not p.b_s2)
  union all
  select s.id, s.fk, 'autorreferencia'
    from sinal s
   where s.fk = s.id;

  select count(*) filter (where caso = 'autorreferencia'), count(*) filter (where caso = 'par')
    into v_self, v_pares from _c20261003_alvo;
  if v_self <> c_esperado_self or v_pares <> c_esperado_pares then
    raise exception '20261003c: base mudou — autorreferências % (esperado %), pares % (esperado %). Medir de novo antes de aplicar.',
      v_self, c_esperado_self, v_pares, c_esperado_pares;
  end if;

  -- ─── 2. Correção ──────────────────────────────────────────────────────────────────────────────────────────────────
  update public.thb_alunos a
     set socio_de_aluno_id = null,
         atualizado_em     = now()
    from _c20261003_alvo t
   where a.id = t.aluno_id
     and a.socio_de_aluno_id = t.fk_anterior;
  get diagnostics v_linhas = row_count;
  if v_linhas <> c_esperado_self + c_esperado_pares then
    raise exception '20261003c: % linhas alteradas (esperado %)', v_linhas, c_esperado_self + c_esperado_pares;
  end if;

  insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
  select t.aluno_id, 'socio_de_aluno_id', t.fk_anterior::text, null, 'conciliacao_20261003'
    from _c20261003_alvo t;
  get diagnostics v_audit = row_count;
  if v_audit <> v_linhas then
    raise exception '20261003c: audit % ≠ linhas %', v_audit, v_linhas;
  end if;

  insert into public.thb_system_events (tipo, fonte, titulo, detalhe)
  values ('info', 'conciliacao', 'Vínculos de sócio corrigidos (20261003c)',
          jsonb_build_object('autorreferencias', v_self, 'pares', v_pares, 'linhas', v_linhas));
end $c$;

-- ─── 1. DEPOIS ──────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('1.depois', $q$select
  (select count(*) from public.thb_alunos a where a.cancelado_em is null and a.socio_de_aluno_id = a.id) self,
  (select count(*) from public.thb_alunos a join public.thb_alunos b on b.id = a.socio_de_aluno_id and b.socio_de_aluno_id = a.id
    where a.cancelado_em is null and b.cancelado_em is null and a.id < b.id) pares,
  (select count(*) from public.thb_alunos_historico) historico,
  (select count(*) from public.thb_alunos_audit_log) audit$q$);
select pg_temp.z_q('1.alvos_por_caso', $q$select caso, count(*) from _c20261003_alvo group by 1 order by 1$q$);
select pg_temp.z_q('1.linhas_mudadas_vs_snapshot', $q$select count(*) from public.thb_alunos a join _z_snap s on s.id = a.id
  where a.socio_de_aluno_id is distinct from s.socio_de_aluno_id or a.eh_socio is distinct from s.eh_socio$q$);
select pg_temp.z_q('1.audit_origem', $q$select count(*), count(valor_anterior), count(valor_novo), count(distinct aluno_id)
  from public.thb_alunos_audit_log where origem = 'conciliacao_20261003'$q$);
select pg_temp.z_q('1.audit_bate_com_mudadas', $q$select count(*) from public.thb_alunos a join _z_snap s on s.id = a.id
  where a.socio_de_aluno_id is distinct from s.socio_de_aluno_id
    and not exists (select 1 from public.thb_alunos_audit_log l where l.origem = 'conciliacao_20261003' and l.aluno_id = a.id
                      and l.valor_anterior = s.socio_de_aluno_id::text)$q$);
select pg_temp.z_q('1.evento', $q$select tipo, fonte, titulo, detalhe from public.thb_system_events
  where titulo = 'Vínculos de sócio corrigidos (20261003c)'$q$);
-- eh_socio dos titulares corrigidos (intocado): quantos seguem eh_socio=true sem FK (viram socio_sem_vinculo)
select pg_temp.z_q('1.corrigidos_eh_socio', $q$select t.caso, a.eh_socio, count(*) from _c20261003_alvo t join public.thb_alunos a on a.id = t.aluno_id group by 1, 2 order by 1, 2$q$);

-- delta de fn_aluno_programas_safe (alunos cuja saída mudou)
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
create temp table _z_prog_depois on commit drop as select * from public.fn_aluno_programas_safe();
reset role;
select pg_temp.z_q('2.programas_delta', $q$select count(*) alunos_mudam,
  count(*) filter (where a.programas::text <> d.programas::text) muda_programas,
  count(*) filter (where a.revisar_motivos::text <> d.revisar_motivos::text) muda_motivos,
  count(*) filter (where a.status_programa::text <> d.status_programa::text) muda_status
  from _z_prog_antes a join _z_prog_depois d using (aluno_id)
  where (a.programas, a.status_programa, a.revisar_motivos)::text is distinct from (d.programas, d.status_programa, d.revisar_motivos)::text$q$);
select pg_temp.z_q('2.a_revisar', $q$select (select count(*) from _z_prog_antes where cardinality(revisar_motivos) > 0) antes,
  (select count(*) from _z_prog_depois where cardinality(revisar_motivos) > 0) depois$q$);

-- ─── 3. REVERSÃO (cópia do bloco comentado da migration, sem begin/commit) ────────────────────────────────────────
-- a trava da 20261003b recusaria recriar autorreferência e par mútuo: desligada só dentro desta transação
alter table public.thb_alunos disable trigger trg_thb_alunos_trava_vinculo_socio;
with r as (
  select distinct on (l.aluno_id) l.aluno_id, l.valor_anterior
    from public.thb_alunos_audit_log l
   where l.origem = 'conciliacao_20261003' and l.campo = 'socio_de_aluno_id' and l.valor_anterior is not null
   order by l.aluno_id, l.criado_em desc, l.id desc
),
u as (
  update public.thb_alunos a
     set socio_de_aluno_id = r.valor_anterior::uuid,
         atualizado_em     = now()
    from r
   where a.id = r.aluno_id
     and a.socio_de_aluno_id is null          -- só onde ninguém mexeu depois
  returning a.id, r.valor_anterior
)
insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
select u.id, 'socio_de_aluno_id', null, u.valor_anterior, 'conciliacao_20261003_reversao' from u;
alter table public.thb_alunos enable trigger trg_thb_alunos_trava_vinculo_socio;

select pg_temp.z_q('3.reversao_except_snap_menos_atual', $q$select count(*) from (select id, socio_de_aluno_id, eh_socio from _z_snap
  except select id, socio_de_aluno_id, eh_socio from public.thb_alunos) x$q$);
select pg_temp.z_q('3.reversao_except_atual_menos_snap', $q$select count(*) from (select id, socio_de_aluno_id, eh_socio from public.thb_alunos
  except select id, socio_de_aluno_id, eh_socio from _z_snap) x$q$);
select pg_temp.z_q('3.reversao_audit', $q$select count(*) from public.thb_alunos_audit_log where origem = 'conciliacao_20261003_reversao'$q$);
select pg_temp.z_q('3.trava_religada', $q$select tgenabled from pg_trigger where tgrelid = 'public.thb_alunos'::regclass and tgname = 'trg_thb_alunos_trava_vinculo_socio'$q$);
select pg_temp.z_q('3.historico_final', $q$select count(*) from public.thb_alunos_historico$q$);

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003c',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
