-- 20261003c — Correção automática de vínculo de sócio (desenho 1.3). ÚNICA migration desta entrega que grava dado.
--
-- O QUE FAZ (só alunos ativos: cancelado_em is null)
--   1. Autorreferência (socio_de_aluno_id = id): socio_de_aluno_id := null. eh_socio intocado.        Esperado: 2
--   2. Par A↔B (A aponta para B e B para A), com sinal unânime:
--        S1 = eh_socio is false (cadastro diz titular);
--        S2 = compra paga de programa PRÓPRIA — public.fn_aluno_pagamentos_programa() somada por pessoa
--             (e-mail → fin.vw_email_pessoa.pessoa_chave; sem pessoa, só o próprio e-mail): pg_hm or pg_catalogo or
--             pg_aurum or pg_mmd.
--      Titular = o lado com S1 quando EXATAMENTE um lado tem S1 e S2 não contradiz (contradiz = o outro lado tem S2 e o
--      lado S1 não tem). Ação: titular.socio_de_aluno_id := null; o sócio mantém a FK; eh_socio intocado.
--      Esperado (analista, passo 0, 30/09): 121 pares; 115 com S1 em exatamente um lado e 0 contradições; 6 sem S1
--      decisivo ficam para a conciliação (socio_par_mutuo).
--   Linhas alteradas esperadas = 117. Contagem diferente = ABORTA (a base mudou: medir de novo antes de aplicar).
--   Cada linha alterada → public.thb_alunos_audit_log (campo 'socio_de_aluno_id', valor_anterior = FK antiga,
--   valor_novo null, origem 'conciliacao_20261003'). Resumo só com contagens em public.thb_system_events.
--   Não muda plano/turma/situação/status → não gera linha em thb_alunos_historico. Nada mais é automático.
--
-- EFEITO COLATERAL CONHECIDO: muda a saída de fn_aluno_programas_safe (no par, os dois herdavam um do outro; agora só o
--   sócio herda do titular). O ensaio mede quantos alunos mudam.
--
-- AS 5 PERGUNTAS
--   escala: 1 passada em thb_alunos (~2 mil ativos) + 1 em fin.vw_transacoes (~57 mil); roda 1 vez.
--   índice: PK de thb_alunos no update (117 linhas). Nenhum novo.
--   frequência: 1 vez (migration).
--   repetição: n/a.
--   reversão: bloco REVERSÃO no fim (a partir do audit_log com a origem desta migration).
--
-- ENSAIO: infra/supabase/migrations/20261003c_ensaio.sql (antes/depois, audit, histórico, delta de programas, reversão).
-- ORDEM: depois da 20261003a (lê fn_aluno_pagamentos_programa) e da 20261003b (a reversão desliga a trava).

set local lock_timeout = '3s';

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

-- ─── REVERSÃO (NÃO executar junto; rodar só para desfazer). Volta a FK de quem ainda está com FK nula e grava audit
-- ─── com origem conciliacao_20261003_reversao. Testada no ensaio (EXCEPT = 0). O ALTER TABLE segura lock exclusivo
-- ─── em thb_alunos até o commit: rodar tudo de uma vez.
-- begin;
-- set local lock_timeout = '3s';
-- -- a trava da 20261003b recusaria recriar autorreferência e par mútuo: desligada só dentro desta transação
-- alter table public.thb_alunos disable trigger trg_thb_alunos_trava_vinculo_socio;
-- with r as (
--   select distinct on (l.aluno_id) l.aluno_id, l.valor_anterior
--     from public.thb_alunos_audit_log l
--    where l.origem = 'conciliacao_20261003' and l.campo = 'socio_de_aluno_id' and l.valor_anterior is not null
--    order by l.aluno_id, l.criado_em desc, l.id desc
-- ),
-- u as (
--   update public.thb_alunos a
--      set socio_de_aluno_id = r.valor_anterior::uuid,
--          atualizado_em     = now()
--     from r
--    where a.id = r.aluno_id
--      and a.socio_de_aluno_id is null          -- só onde ninguém mexeu depois
--   returning a.id, r.valor_anterior
-- )
-- insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
-- select u.id, 'socio_de_aluno_id', null, u.valor_anterior, 'conciliacao_20261003_reversao' from u;
-- alter table public.thb_alunos enable trigger trg_thb_alunos_trava_vinculo_socio;
-- commit;
