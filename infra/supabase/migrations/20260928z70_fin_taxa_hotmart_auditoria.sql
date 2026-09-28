-- 20260928z70 — Contas a Receber / Faturamento, fatia F7 (catálogo A.1 R08–R13): auditoria da taxa Hotmart por produto.
--
-- NÃO APLICADA — coordenador aplica. Não depende da z69 (só de fin.vw_transacoes/z27b, do índice
-- hotmart_transacoes_aprovado_pago_idx/z61 e de public.gp_pode_ver_financeiro/z14).
--
-- Por quê: a taxa Hotmart combinada é POR PRODUTO (R08). Medido em produção em 28/09/2026: 1.995 vendas à vista
-- (parcelas ≤ 1) com oferta ≥ R$ 100 em 2026, tolerância ± R$ 10 — a regra por produto bate 100% em todos os
-- produtos (4% + R$ 1: 'Holding Masters', 'Holding - Holding Masters', 'Aurum', 'Aurum - A', 'Diamante'; 5,3% + R$ 1:
-- o resto). A regra "≥ R$ 10 mil" (premissa antiga, Conflito 5 do catálogo) bate só 85,4%.
--
-- O que entra:
--   1) fin.acordo_taxa_hotmart (produto_id, pct, fixo, vigente_de, fonte, criado_em) — PK (produto_id, vigente_de).
--      RLS ligada, sem policy, sem grant (nem service_role). SÓ ACRÉSCIMO (trigger barra UPDATE/DELETE/TRUNCATE, até como postgres):
--      mudar o acordo = inserir linha nova com vigente_de novo. produto_id '*' = default (5,3% + R$ 1).
--      Carga: os 5 produtos do grupo 4% (ids resolvidos pelo NOME COM btrim no espelho fin.hotmart_transacoes —
--      'Aurum ' tem espaço no fim lá; a guarda aborta se um nome não resolver para exatamente 1 produto_id) + default.
--      "Verificar" da planilha (Imersão Holding sem Improviso, VIP - Holding Total, Sessão de Viabilidade) NÃO têm
--      linha própria: caem no default e a RPC devolve sem_acordo_especifico = true.
--   2) fin.taxa_hotmart_vendas(ini, fim) — interna (sem grant): uma linha por venda paga com oferta ≥ R$ 100 e a taxa
--      esperada do acordo vigente no dia da venda (linha do produto vence o default; entre linhas do mesmo produto,
--      a de maior vigente_de ≤ dia). As duas RPCs leem daqui: mesma regra, somas coerentes por construção.
--   3) public.fn_fin_taxa_auditoria(inicio, fim) — por produto (tipo 'a_vista') e por nº de parcelas 1..12 (tipo
--      'parcelado', informativo, R13). Sem dado pessoal.
--   4) public.fn_fin_taxa_divergencias(inicio, fim) — vendas à vista com |real − esperado| > R$ 10, sem nome/e-mail,
--      no máximo 500, maior diferença primeiro.
--
-- Predicado de venda paga: t.status in ('APPROVED','COMPLETE') LITERAL + range em t.aprovado_em (coluna crua) — é o
-- predicado do índice parcial hotmart_transacoes_aprovado_pago_idx (z61). Não usar grupo='pago' nem dia_aprovado.
--
-- REVERSÃO (uma transação; o DROP passa por cima do trigger de só-acréscimo):
--   begin;
--   drop function public.fn_fin_taxa_divergencias(date, date);
--   drop function public.fn_fin_taxa_auditoria(date, date);
--   drop function fin.taxa_hotmart_vendas(timestamptz, timestamptz);
--   drop table fin.acordo_taxa_hotmart;
--   drop function fin.tg_acordo_taxa_hotmart_so_acrescimo();
--   commit;
-- Desligar sem reverter: revoke execute on function public.fn_fin_taxa_auditoria(date, date),
--   public.fn_fin_taxa_divergencias(date, date) from authenticated;   (a tela recebe 42501; nada grava)


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  if to_regclass('fin.vw_transacoes') is null or to_regclass('fin.hotmart_transacoes') is null then
    raise exception 'z70: fin.vw_transacoes ou fin.hotmart_transacoes não existe';
  end if;
  select string_agg(c, ', ') into v_falta
    from unnest(array['transacao','produto_id','produto_nome','status','parcelas','valor_oferta','valor_cobrado',
                      'taxa_hotmart','liquido','aprovado_em','dia_aprovado']) c
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'fin' and ic.table_name = 'vw_transacoes' and ic.column_name = c);
  if v_falta is not null then
    raise exception 'z70: fin.vw_transacoes sem as colunas: %', v_falta;
  end if;
  if to_regprocedure('public.gp_pode_ver_financeiro()') is null then
    raise exception 'z70: public.gp_pode_ver_financeiro() não existe';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'fin' and tablename = 'hotmart_transacoes'
                   and indexname = 'hotmart_transacoes_aprovado_pago_idx'
                   and indexdef ilike '%(aprovado_em)%'
                   and indexdef ilike '%status%APPROVED%COMPLETE%') then
    raise exception 'z70: hotmart_transacoes_aprovado_pago_idx ausente ou com outra definição — a z61 foi aplicada?';
  end if;
  -- idempotência
  if to_regclass('fin.acordo_taxa_hotmart') is not null
     or to_regprocedure('fin.taxa_hotmart_vendas(timestamptz,timestamptz)') is not null
     or to_regprocedure('fin.tg_acordo_taxa_hotmart_so_acrescimo()') is not null
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname in ('fn_fin_taxa_auditoria','fn_fin_taxa_divergencias')) then
    raise exception 'z70: objeto da z70 já existe — z70 já aplicada?';
  end if;
end $guarda$;


-- ─── 1. Resolução dos 5 produtos do grupo 4% pelo nome (btrim), exatamente 1 produto_id por nome ─────────────────────
create temp table z70_ids (nome text primary key, produto_id text not null);   -- dropada no fim do arquivo

do $resolve$
declare
  v_nome text;
  v_n    int;
  v_ids  text;
begin
  foreach v_nome in array array['Holding Masters','Holding - Holding Masters','Aurum','Aurum - A','Diamante'] loop
    select count(distinct h.produto_id), string_agg(distinct h.produto_id, ', ')
      into v_n, v_ids
      from fin.hotmart_transacoes h
     where pg_catalog.btrim(h.produto_nome) = v_nome;
    if v_n <> 1 then
      raise exception 'z70: o nome "%" (com btrim) resolveu para % produto_id no espelho (%). Esperado exatamente 1. '
                      'Mandar ao Victor: select produto_id, produto_nome, count(*) from fin.hotmart_transacoes '
                      'where btrim(produto_nome) = ''%'' group by 1, 2;', v_nome, v_n, coalesce(v_ids, 'nenhum'), v_nome;
    end if;
    insert into z70_ids values (v_nome, v_ids);
  end loop;
end $resolve$;


-- ─── 2. Acordo por produto (só acréscimo) ───────────────────────────────────────────────────────────────────────────
create table fin.acordo_taxa_hotmart (
  produto_id  text not null check (produto_id <> ''),
  pct         numeric(7,5) not null check (pct >= 0 and pct < 1),
  fixo        numeric(12,2) not null check (fixo >= 0),
  vigente_de  date not null,
  fonte       text not null check (pg_catalog.btrim(fonte) <> ''),
  criado_em   timestamptz not null default now(),
  primary key (produto_id, vigente_de)
);
comment on table fin.acordo_taxa_hotmart is
  'z70 (R08): taxa Hotmart combinada por produto. esperado = round(pct × valor_oferta + fixo, 2). produto_id ''*'' = '
  'default de quem não tem linha própria. Vigência: linha do produto vence o default; entre linhas do mesmo produto, a '
  'de maior vigente_de ≤ dia da venda. Só acréscimo: mudar = inserir linha nova com vigente_de novo.';

create function fin.tg_acordo_taxa_hotmart_so_acrescimo()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'fin.%: só acréscimo (% bloqueado). Mudar o acordo = inserir linha com vigente_de novo.', tg_table_name, tg_op
    using errcode = 'P0001';
end $$;
revoke all on function fin.tg_acordo_taxa_hotmart_so_acrescimo() from public, anon, authenticated, service_role;

create trigger acordo_taxa_hotmart_so_acrescimo before update or delete on fin.acordo_taxa_hotmart
  for each row execute function fin.tg_acordo_taxa_hotmart_so_acrescimo();
create trigger acordo_taxa_hotmart_nao_trunca before truncate on fin.acordo_taxa_hotmart
  for each statement execute function fin.tg_acordo_taxa_hotmart_so_acrescimo();

alter table fin.acordo_taxa_hotmart enable row level security;
-- sem grant a ninguém além do dono (inclusive service_role: a carga é por migration; nada no app escreve aqui)
revoke all on table fin.acordo_taxa_hotmart from public, anon, authenticated, service_role;

-- Carga. vigente_de 2015-01-01 = início do calendário de caixa (z60/z68): antes disso não há transação real.
insert into fin.acordo_taxa_hotmart (produto_id, pct, fixo, vigente_de, fonte)
select distinct z.produto_id, 0.04000, 1.00, date '2015-01-01',
       'planilha (grupo 4% + R$ 1: Holding Masters, Holding - Holding Masters, Aurum, Aurum - A, Diamante); medido em '
       || 'produção 28/09/2026: 1.995 vendas à vista ≥ R$ 100 em 2026, 100% dentro de ± R$ 10'
  from z70_ids z;
insert into fin.acordo_taxa_hotmart (produto_id, pct, fixo, vigente_de, fonte)
values ('*', 0.05300, 1.00, date '2015-01-01',
        'planilha (grupo 5,3% + R$ 1: todos os demais produtos; "Verificar": Imersão Holding sem Improviso, '
        || 'VIP - Holding Total, Sessão de Viabilidade — sem acordo específico); medido em produção 28/09/2026');


-- ─── 3. Vendas pagas com a taxa esperada (interna, sem grant) ───────────────────────────────────────────────────────
create function fin.taxa_hotmart_vendas(p_ini timestamptz, p_fim timestamptz)
returns table (
  transacao text, dia date, produto_id text, produto_nome text, parcelas int, valor_oferta numeric,
  valor_cobrado numeric, liquido numeric, taxa_hotmart numeric, grupo_acordo text, especifico boolean,
  taxa_esperada numeric)
language sql stable set search_path = ''
as $$
  select t.transacao, t.dia_aprovado, t.produto_id, pg_catalog.btrim(t.produto_nome),
         greatest(coalesce(t.parcelas, 1), 1), t.valor_oferta, coalesce(t.valor_cobrado, t.valor_oferta), t.liquido,
         t.taxa_hotmart,
         pg_catalog.replace(pg_catalog.trim_scale(ac.pct * 100)::text, '.', ',') || '% + R$ '
           || pg_catalog.replace(pg_catalog.to_char(ac.fixo, 'FM999990.00'), '.', ','),
         ac.especifico,
         pg_catalog.round(ac.pct * t.valor_oferta + ac.fixo, 2)
    from fin.vw_transacoes t
    left join lateral (
      select a.pct, a.fixo, a.produto_id <> '*' especifico
        from fin.acordo_taxa_hotmart a
       where a.produto_id in (t.produto_id, '*') and a.vigente_de <= t.dia_aprovado
       order by a.produto_id = '*', a.vigente_de desc
       limit 1) ac on true
   where t.status in ('APPROVED','COMPLETE')           -- = grupo 'pago'; literal p/ bater o índice parcial (z61)
     and t.aprovado_em >= p_ini and t.aprovado_em < p_fim
     and t.valor_oferta >= 100                          -- R11: tíquete < R$ 100 é ruído
$$;
comment on function fin.taxa_hotmart_vendas(timestamptz, timestamptz) is
  'z70: vendas pagas com oferta ≥ R$ 100 no intervalo [p_ini, p_fim) com a taxa esperada do acordo vigente no dia. '
  'Interna: só as RPCs fn_fin_taxa_* (definer) leem.';
revoke all on function fin.taxa_hotmart_vendas(timestamptz, timestamptz) from public, anon, authenticated, service_role;


-- ─── 4. Auditoria por produto (à vista) + taxa efetiva do cliente por nº de parcelas (informativo) ──────────────────
-- a_vista (parcelas ≤ 1): n_vendas/valor_oferta/taxa_* só das vendas COM taxa_hotmart (n_sem_taxa = as que vieram sem);
--   taxa_real_pct = Σ taxa_hotmart / Σ oferta; taxa_esperada_pct = Σ esperado / Σ oferta (média ponderada pela oferta);
--   n_divergentes = |taxa_hotmart − esperado| > R$ 10; impacto_rs = Σ (real − esperado) de todas;
--   impacto_divergentes_rs = só das divergentes (o que o financeiro contesta).
--   sem_acordo_especifico = alguma venda do produto caiu no default '*' (não há linha do produto).
-- parcelado (1..12, sempre 12 linhas; 1 = referência à vista de todos os produtos): taxa_cliente_pct =
--   Σ (valor_cobrado − liquido) / Σ oferta (R13; inclui juros do cliente e, se houver, comissão de coprodutor).
create function public.fn_fin_taxa_auditoria(p_inicio date, p_fim date)
returns table (
  tipo text, produto_id text, produto_nome text, grupo_acordo text, sem_acordo_especifico boolean, parcelas int,
  n_vendas int, n_sem_taxa int, valor_oferta numeric, taxa_real_rs numeric, taxa_esperada_rs numeric,
  taxa_real_pct numeric, taxa_esperada_pct numeric, n_divergentes int, impacto_rs numeric,
  impacto_divergentes_rs numeric, taxa_cliente_pct numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_inicio is null or p_fim is null then
    raise exception 'Informe início e fim.' using errcode = '22023';
  end if;
  if p_fim < p_inicio then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  if p_fim - p_inicio > 400 then raise exception 'Janela máxima de 400 dias.' using errcode = '22023'; end if;
  v_ini_ts := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim_ts := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  return query
  with v as materialized (
    select * from fin.taxa_hotmart_vendas(v_ini_ts, v_fim_ts)
  ), av as (
    select v.produto_id,
           (array_agg(v.produto_nome order by v.dia desc, v.transacao desc))[1] produto_nome,
           string_agg(distinct v.grupo_acordo, ' / ') grupo_acordo,
           bool_or(not coalesce(v.especifico, false)) sem_esp,
           count(*) filter (where v.taxa_hotmart is not null)::int n,
           count(*) filter (where v.taxa_hotmart is null)::int n_sem,
           coalesce(sum(v.valor_oferta) filter (where v.taxa_hotmart is not null), 0) oferta,
           coalesce(sum(v.taxa_hotmart), 0) reais,
           coalesce(sum(v.taxa_esperada) filter (where v.taxa_hotmart is not null), 0) esper,
           count(*) filter (where abs(v.taxa_hotmart - v.taxa_esperada) > 10)::int ndiv,
           coalesce(sum(v.taxa_hotmart - v.taxa_esperada), 0) imp,
           coalesce(sum(v.taxa_hotmart - v.taxa_esperada) filter (where abs(v.taxa_hotmart - v.taxa_esperada) > 10), 0) impdiv,
           coalesce(sum(v.valor_cobrado - v.liquido), 0) cli
      from v
     where v.parcelas <= 1
     group by v.produto_id
  ), pc as (
    select g.n,
           count(v.transacao)::int nv,
           count(v.transacao) filter (where v.taxa_hotmart is null)::int n_sem,
           coalesce(sum(v.valor_oferta), 0) oferta,
           coalesce(sum(v.taxa_hotmart), 0) reais,
           coalesce(sum(v.valor_oferta) filter (where v.taxa_hotmart is not null), 0) oferta_tx,
           coalesce(sum(v.valor_cobrado - v.liquido), 0) cli
      from pg_catalog.generate_series(1, 12) g(n)
      left join v on v.parcelas = g.n
     group by g.n
  )
  select x.* from (
    select 'a_vista'::text, av.produto_id, av.produto_nome, av.grupo_acordo, av.sem_esp, 1, av.n, av.n_sem,
           av.oferta, av.reais, av.esper,
           pg_catalog.round(100 * av.reais / nullif(av.oferta, 0), 3),
           pg_catalog.round(100 * av.esper / nullif(av.oferta, 0), 3),
           av.ndiv, av.imp, av.impdiv, null::numeric
      from av
    union all
    select 'parcelado'::text, null::text, null::text, null::text, null::boolean, pc.n, pc.nv - pc.n_sem, pc.n_sem,
           pc.oferta, pc.reais, null::numeric,
           pg_catalog.round(100 * pc.reais / nullif(pc.oferta_tx, 0), 3), null::numeric,
           null::int, null::numeric, null::numeric,
           pg_catalog.round(100 * pc.cli / nullif(pc.oferta, 0), 3)
      from pc
  ) x(tipo, produto_id, produto_nome, grupo_acordo, sem_acordo_especifico, parcelas, n_vendas, n_sem_taxa,
      valor_oferta, taxa_real_rs, taxa_esperada_rs, taxa_real_pct, taxa_esperada_pct, n_divergentes, impacto_rs,
      impacto_divergentes_rs, taxa_cliente_pct)
  order by x.tipo = 'parcelado', case when x.tipo = 'a_vista' then x.valor_oferta end desc nulls last, x.parcelas,
           x.produto_id;
end $$;
comment on function public.fn_fin_taxa_auditoria(date, date) is
  'z70 (R08–R13): taxa Hotmart real × acordo por produto (tipo a_vista) e taxa efetiva do cliente por nº de parcelas '
  '1..12 (tipo parcelado, informativo). Só venda paga com oferta ≥ R$ 100. Janela ≤ 400 dias. Sem dado pessoal.';
revoke all on function public.fn_fin_taxa_auditoria(date, date) from public, anon;
grant execute on function public.fn_fin_taxa_auditoria(date, date) to authenticated;


-- ─── 5. Vendas divergentes (à vista, |real − esperado| > R$ 10), no máximo 500 ──────────────────────────────────────
create function public.fn_fin_taxa_divergencias(p_inicio date, p_fim date)
returns table (
  transacao text, dia date, produto_id text, produto_nome text, valor_oferta numeric, taxa_real numeric,
  taxa_esperada numeric, diferenca numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_inicio is null or p_fim is null then
    raise exception 'Informe início e fim.' using errcode = '22023';
  end if;
  if p_fim < p_inicio then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  if p_fim - p_inicio > 400 then raise exception 'Janela máxima de 400 dias.' using errcode = '22023'; end if;
  v_ini_ts := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim_ts := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  return query
  select v.transacao, v.dia, v.produto_id, v.produto_nome, v.valor_oferta, v.taxa_hotmart, v.taxa_esperada,
         v.taxa_hotmart - v.taxa_esperada
    from fin.taxa_hotmart_vendas(v_ini_ts, v_fim_ts) v
   where v.parcelas <= 1 and abs(v.taxa_hotmart - v.taxa_esperada) > 10
   order by abs(v.taxa_hotmart - v.taxa_esperada) desc, v.dia desc, v.transacao
   limit 500;
end $$;
comment on function public.fn_fin_taxa_divergencias(date, date) is
  'z70 (R10): vendas à vista (oferta ≥ R$ 100) com |taxa real − esperada| > R$ 10; maior diferença primeiro; até 500. '
  'Sem nome/e-mail. O total está em fn_fin_taxa_auditoria (Σ n_divergentes).';
revoke all on function public.fn_fin_taxa_divergencias(date, date) from public, anon;
grant execute on function public.fn_fin_taxa_divergencias(date, date) to authenticated;


-- ─── 6. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  f      text;
  v_ok   boolean;
  v_adm  uuid;
  v_ini  date := date '2026-01-01';
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_n    int;  v_n2 int;  v_div int;  v_div2 int;
  v_imp  numeric;  v_imp2 numeric;
  v_txt  text;
begin
  -- 6.1 carga: cada um dos 5 nomes tem linha própria 4% + R$ 1; default '*' 5,3% + R$ 1; nada além disso
  select string_agg(z.nome, ', ') into v_txt from z70_ids z
   where not exists (select 1 from fin.acordo_taxa_hotmart a
                      where a.produto_id = z.produto_id and a.pct = 0.04 and a.fixo = 1 and a.vigente_de = date '2015-01-01');
  if (select count(*) from z70_ids) <> 5 or v_txt is not null then
    raise exception 'z70: carga não resolveu os 5 produtos do grupo 4%% (faltou: %)', coalesce(v_txt, '?');
  end if;
  if not exists (select 1 from fin.acordo_taxa_hotmart where produto_id = '*' and pct = 0.053 and fixo = 1) then
    raise exception 'z70: default ''*'' 5,3%% + R$ 1 ausente';
  end if;
  if (select count(*) from fin.acordo_taxa_hotmart)
     <> (select count(distinct produto_id) from z70_ids) + 1 then
    raise exception 'z70: fin.acordo_taxa_hotmart com linhas a mais';
  end if;

  -- 6.2 grants: tabela fechada; RPCs sem PUBLIC/anon; interna só para o dono
  if not (select c.relrowsecurity from pg_class c where c.oid = 'fin.acordo_taxa_hotmart'::regclass) then
    raise exception 'z70: RLS desligada em fin.acordo_taxa_hotmart';
  end if;
  foreach f in array array['select','insert','update','delete','truncate'] loop
    if has_table_privilege('anon', 'fin.acordo_taxa_hotmart', f)
       or has_table_privilege('authenticated', 'fin.acordo_taxa_hotmart', f)
       or has_table_privilege('service_role', 'fin.acordo_taxa_hotmart', f) then
      raise exception 'z70: fin.acordo_taxa_hotmart com % para anon/authenticated/service_role', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.fn_fin_taxa_auditoria(date,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_taxa_divergencias(date,date)', 'execute')
     or has_function_privilege('anon', 'fin.taxa_hotmart_vendas(timestamptz,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'fin.taxa_hotmart_vendas(timestamptz,timestamptz)', 'execute')
     or has_function_privilege('service_role', 'fin.taxa_hotmart_vendas(timestamptz,timestamptz)', 'execute') then
    raise exception 'z70: EXECUTE aberto demais (anon nas RPCs ou authenticated/service_role na interna)';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_taxa_auditoria(date,date)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_taxa_divergencias(date,date)', 'execute') then
    raise exception 'z70: authenticated sem EXECUTE nas RPCs';
  end if;
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) ac
              where p.oid in ('public.fn_fin_taxa_auditoria(date,date)'::regprocedure,
                              'public.fn_fin_taxa_divergencias(date,date)'::regprocedure,
                              'fin.taxa_hotmart_vendas(timestamptz,timestamptz)'::regprocedure,
                              'fin.tg_acordo_taxa_hotmart_so_acrescimo()'::regprocedure)
                and ac::text like '=%') then
    raise exception 'z70: função com EXECUTE para PUBLIC';
  end if;
  if exists (select 1 from pg_proc p
              where p.oid in ('public.fn_fin_taxa_auditoria(date,date)'::regprocedure,
                              'public.fn_fin_taxa_divergencias(date,date)'::regprocedure)
                and not (p.prosecdef and p.proconfig = array['search_path=""'])) then
    raise exception 'z70: RPC sem security definer ou sem search_path vazio';
  end if;

  -- 6.3 só acréscimo (mesmo como postgres)
  foreach f in array array['update fin.acordo_taxa_hotmart set pct = pct',
                           'delete from fin.acordo_taxa_hotmart',
                           'truncate fin.acordo_taxa_hotmart'] loop
    v_ok := false;
    begin
      execute f;
    exception when others then
      v_ok := sqlerrm like 'fin.acordo_taxa_hotmart: só acréscimo%';
    end;
    if not v_ok then raise exception 'z70: só-acréscimo não barrou: %', f; end if;
  end loop;

  -- 6.4 sem sessão → 42501 (as duas RPCs)
  perform set_config('request.jwt.claims', '', true);
  v_ok := false;
  begin
    perform * from public.fn_fin_taxa_auditoria(v_ini, v_hoje);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z70: fn_fin_taxa_auditoria aceitou chamada sem sessão'; end if;
  v_ok := false;
  begin
    perform * from public.fn_fin_taxa_divergencias(v_ini, v_hoje);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z70: fn_fin_taxa_divergencias aceitou chamada sem sessão'; end if;

  -- 6.5 com sessão de admin (local à transação): janela, somas coerentes, 2026 ≈ sem divergência
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z70: nenhum perfil admin ativo para conferir as RPCs'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_ok := false;
  begin
    perform * from public.fn_fin_taxa_auditoria(v_hoje - 401, v_hoje);
  exception when sqlstate '22023' then v_ok := true;
  end;
  if not v_ok then raise exception 'z70: janela de 401 dias aceita'; end if;

  -- à vista: Σ (n_vendas + n_sem_taxa) = contagem direta na view com o mesmo filtro
  select coalesce(sum(a.n_vendas + a.n_sem_taxa), 0), coalesce(sum(a.n_divergentes), 0),
         coalesce(sum(a.impacto_divergentes_rs), 0)
    into v_n, v_div, v_imp
    from public.fn_fin_taxa_auditoria(v_ini, v_hoje) a where a.tipo = 'a_vista';
  select count(*) into v_n2 from fin.vw_transacoes t
   where t.status in ('APPROVED','COMPLETE') and t.dia_aprovado between v_ini and v_hoje
     and t.valor_oferta >= 100 and coalesce(t.parcelas, 1) <= 1;
  if v_n <> v_n2 then raise exception 'z70: à vista 2026 na RPC (%) ≠ contagem direta (%)', v_n, v_n2; end if;
  if v_n = 0 then raise exception 'z70: nenhuma venda à vista ≥ R$ 100 em 2026 — espelho vazio?'; end if;
  -- parcelado: 12 linhas; Σ (n_vendas + n_sem_taxa) de 2..12 = contagem direta
  if (select count(*) from public.fn_fin_taxa_auditoria(v_ini, v_hoje) a where a.tipo = 'parcelado') <> 12 then
    raise exception 'z70: parcelado sem as 12 linhas';
  end if;
  select coalesce(sum(a.n_vendas + a.n_sem_taxa), 0) into v_n2
    from public.fn_fin_taxa_auditoria(v_ini, v_hoje) a where a.tipo = 'parcelado' and a.parcelas = 1;
  if v_n2 <> v_n then raise exception 'z70: parcelado 1× (%) ≠ à vista (%)', v_n2, v_n; end if;
  -- divergências: lista = contagem e impacto da auditoria (quando cabe no limite de 500)
  select count(*), coalesce(sum(d.diferenca), 0) into v_div2, v_imp2
    from public.fn_fin_taxa_divergencias(v_ini, v_hoje) d;
  if v_div <= 500 and (v_div2 <> v_div or v_imp2 <> v_imp) then
    raise exception 'z70: divergências (% / R$ %) ≠ auditoria (% / R$ %)', v_div2, v_imp2, v_div, v_imp;
  end if;
  -- R08 medido: 2026 à vista bate 100% ± R$ 10. Aceita até 1% (vendas novas desde a medição); a regra errada
  -- ("≥ R$ 10 mil") daria ~14,6% — ids trocados ou carga errada param aqui.
  if v_div * 100 > v_n then
    raise exception 'z70: % de % vendas à vista de 2026 divergem do acordo (> 1%%). Carga errada? Não aplicar.', v_div, v_n;
  end if;
  raise notice 'z70: 2026 à vista: % vendas, % divergentes, impacto divergentes R$ %', v_n, v_div, v_imp;

  perform set_config('request.jwt.claims', '', true);
end $chk$;

drop table pg_temp.z70_ids;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit; tudo leitura) ═══
-- <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro. explain: rodar 2× e usar a 2ª (1ª é cache frio).
/*
-- P1) Carga: os 5 ids do grupo 4% com o nome como está no espelho (o 'Aurum ' aparece com o espaço).
select a.produto_id, a.pct, a.fixo, a.vigente_de,
       (select string_agg(distinct '"' || h.produto_nome || '"', ', ') from fin.hotmart_transacoes h
         where h.produto_id = a.produto_id) nomes_no_espelho
  from fin.acordo_taxa_hotmart a order by a.pct, a.produto_id;

-- P2) Tabela por produto de 2026 (esperado: n_divergentes ≈ 0 e impacto_divergentes_rs ≈ 0 em todas as linhas
--     a_vista; grupo 4% nos 5 produtos; parcelado 1× ≈ 5,1% até 12× ≈ 24,5%).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select tipo, produto_id, produto_nome, grupo_acordo, sem_acordo_especifico, parcelas, n_vendas, n_sem_taxa,
       valor_oferta, taxa_real_pct, taxa_esperada_pct, n_divergentes, impacto_rs, impacto_divergentes_rs, taxa_cliente_pct
  from public.fn_fin_taxa_auditoria(date '2026-01-01', current_date);
select * from public.fn_fin_taxa_divergencias(date '2026-01-01', current_date);
rollback;

-- P3) Custo das RPCs (plpgsql: o explain de fora mostra Function Scan; o tempo total é o que importa).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_taxa_auditoria(date '2026-01-01', current_date);
explain (analyze, buffers) select * from public.fn_fin_taxa_auditoria(date '2026-01-01', current_date);
explain (analyze, buffers) select * from public.fn_fin_taxa_divergencias(date '2026-01-01', current_date);
explain (analyze, buffers) select * from public.fn_fin_taxa_auditoria(current_date - 400, current_date);
rollback;

-- P4) Por dentro: a leitura das vendas usa hotmart_transacoes_aprovado_pago_idx (Index/Bitmap Index Scan) e o acordo
--     é lido por venda (6 linhas). Janela de 30 dias (seletiva) e de 2026 inteiro (em tabela pequena o planner pode
--     preferir Seq Scan — registrar o que sair; o que importa é o tempo).
explain (analyze, buffers)
select * from fin.taxa_hotmart_vendas((current_date - 30)::timestamp at time zone 'America/Sao_Paulo', now());
explain (analyze, buffers)
select t.transacao, t.valor_oferta, t.taxa_hotmart from fin.vw_transacoes t
 where t.status in ('APPROVED','COMPLETE')
   and t.aprovado_em >= (current_date - 30)::timestamp at time zone 'America/Sao_Paulo' and t.aprovado_em < now();
select pg_size_pretty(pg_total_relation_size('fin.hotmart_transacoes')) tamanho,
       (select count(*) from fin.hotmart_transacoes) linhas,
       (select count(*) from fin.hotmart_transacoes where status in ('APPROVED','COMPLETE')) pagas;
*/
