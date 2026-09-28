-- 20260928z54 — Faturamento líquido realista: antecipação D+2 e retenção de 10% (decisão do Marcio, 28/09/2026).
--
-- NÃO APLICADA — coordenador aplica. Uma transação só (o apply_migration do Supabase já envolve o arquivo em uma).
--
-- Regra: a empresa paga 3,89% sobre 90% do líquido do dia para receber em D+2 (em vez de D+30); 10% ficam retidos para
-- reembolso e voltam em 30 dias. Vale para todas as formas de pagamento e todo o histórico. Venda de 100:
-- líquido Hotmart 93,70 → retido 9,37 · custo antecipação 3,28 · entra em 2 dias 81,05 · líquido total 90,42.
-- A regra é aplicada ao LÍQUIDO SOMADO DO DIA (linear; arredonda uma vez por dia), não por transação.
-- Base = só grupo 'pago' (o mesmo "liquido" de hoje): estorno sai inteiro das três linhas. Os 3,89% de antecipação de
-- venda depois estornada NÃO são somados aqui (≈ R$ 15 mil/ano × R$ 472 mil de custo total — fica para depois).
-- Moeda: fin.vw_transacoes NÃO converte (soma liquido_produtor como vier). A regra segue o "liquido" exatamente como ele
-- já é somado hoje; não há conversão nova aqui. Ver prova P6.
--
-- O que muda:
--   1) fin.premissas_recebimento — parâmetros com vigência (última linha com vigente_de <= dia). ativa=false → colunas
--      novas nulas e a tela volta ao "Líquido Hotmart". É o kill-switch: desliga sem deploy.
--   2) fin.recebimento(dia, liquido) — ÚNICA fonte da fórmula. Sem grant.
--   3) public.fn_fin_premissas_recebimento() — a tela lê os parâmetros daqui (nunca "3,89" fixo no front).
--   4) public.fn_fin_hotmart_faturamento e public.fn_fin_hotmart_funis — mesmos argumentos, + entra_rapido, retido,
--      retido_a_liberar, custo_antecipacao, liquido_total (nulas sem premissa ativa). Drop/create: o RETURNS TABLE muda.
--
-- Guarda: as duas funções só são recriadas se o corpo VIVO (prosrc, sem espaços) for igual ao do repositório
-- (20260927b linhas 53–101 e 20260927h linhas 32–71). Divergiu → exception e nada é aplicado.
--
-- REVERSÃO (uma transação; o corpo antigo é o do repositório, que a guarda provou ser o vivo no momento da aplicação):
--   Desligar sem reverter:  update fin.premissas_recebimento set ativa = false;   -- colunas novas viram null
--   Reverter de verdade:
--   begin;
--   drop function public.fn_fin_hotmart_faturamento(text, date, date);
--   drop function public.fn_fin_hotmart_funis(text, date, date);
--   -- recriar public.fn_fin_hotmart_faturamento: copiar 20260927b_fin_relatorios_hotmart.sql linhas 53–101 (create or
--   --   replace function ... end $$;) e em seguida:
--   revoke all on function public.fn_fin_hotmart_faturamento(text, date, date) from public, anon;
--   grant execute on function public.fn_fin_hotmart_faturamento(text, date, date) to authenticated;
--   -- recriar public.fn_fin_hotmart_funis: copiar 20260927h_fin_acelera_e_funis.sql linhas 32–73 (inclui revoke/grant).
--   drop function public.fn_fin_premissas_recebimento();
--   drop function fin.recebimento(date, numeric);
--   alter table fin.premissas_recebimento rename to premissas_recebimento_arquivada_z54;   -- arquivar, não apagar
--   commit;


-- ─── 0. Guarda: corpo vivo = corpo do repositório ─────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_fat  oid := to_regprocedure('public.fn_fin_hotmart_faturamento(text,date,date)');
  v_fun  oid := to_regprocedure('public.fn_fin_hotmart_funis(text,date,date)');
  v_src  text;
  v_res  text;
  e_fat  text := $esperado$
#variable_conflict use_column
declare v_ini date := coalesce(p_inicio, (now() at time zone 'America/Sao_Paulo')::date - 89);
        v_fim date := coalesce(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- Sem teto de dias: o custo é o das transações da família (plano 27/09: Aurum 2021→hoje 50 ms), não do intervalo.
  -- Um teto fixo voltaria a quebrar o "Tudo" da tela quando a história passasse dele.
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with p as (
    select t.dia_aprovado d,
           count(*) filter (where t.grupo = 'pago')::int vendas,  -- estorno não é venda paga (Fable 27/09)
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) oferta,
           coalesce(sum(t.valor_cobrado) filter (where t.grupo = 'pago'), 0) cobrado,
           coalesce(sum(t.juros) filter (where t.grupo = 'pago'), 0) juros,
           coalesce(sum(t.taxa_hotmart) filter (where t.grupo = 'pago'), 0) taxa,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.liquido_estimado)::int estimado,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) estornado,
           count(distinct t.email) filter (where t.grupo = 'pago')::int compradores
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('pago','estornado') and t.dia_aprovado between v_ini and v_fim
     group by 1
  ), a as (
    select t.dia_pedido d,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           count(*) filter (where t.grupo in ('em_aberto','expirado'))::int boletos
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('recusado','em_aberto','expirado') and t.dia_pedido between v_ini and v_fim
     group by 1
  )
  select coalesce(p.d, a.d), coalesce(p.vendas, 0), coalesce(p.oferta, 0), coalesce(p.cobrado, 0),
         coalesce(p.juros, 0), coalesce(p.taxa, 0), coalesce(p.liquido, 0), coalesce(p.estimado, 0),
         coalesce(p.estornos, 0), coalesce(p.estornado, 0), coalesce(a.recusadas, 0), coalesce(a.boletos, 0),
         coalesce(p.compradores, 0)
    from p full join a on a.d = p.d
   order by 1;
end $esperado$;
  e_fat_res text := 'TABLE(dia date, vendas integer, valor_oferta numeric, cobrado_cliente numeric, juros numeric, '
                 || 'taxa_hotmart numeric, liquido numeric, liquido_estimado integer, estornos integer, valor_estornado numeric, '
                 || 'recusadas integer, boletos_gerados integer, compradores integer)';
  e_fun  text := $esperado$
#variable_conflict use_column
declare v_ini date := coalesce(p_inicio, date '2021-01-01');
        v_fim date := coalesce(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with t as (
    select x.*, coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = p_familia
  ), tf as (
    select t.*, f.nome funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = p_familia and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between v_ini and v_fim
  )
  select coalesce(tf.funil_nome, 'Sem funil'), min(tf.f_de), max(tf.f_ate),
         count(*) filter (where tf.grupo = 'pago')::int,
         count(distinct tf.email) filter (where tf.grupo = 'pago')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0),
         count(*) filter (where tf.grupo = 'estornado')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0),
         count(*) filter (where tf.grupo = 'recusado')::int,
         count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int,
         count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int,
         round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1)
    from tf group by coalesce(tf.funil_nome, 'Sem funil')
   order by min(tf.f_de) nulls last;
end $esperado$;
  e_fun_res text := 'TABLE(funil text, vale_de date, vale_ate date, vendas integer, compradores integer, valor_oferta numeric, '
                 || 'cobrado_cliente numeric, juros numeric, taxa_hotmart numeric, liquido numeric, estornos integer, '
                 || 'valor_estornado numeric, recusadas integer, boletos integer, parcelado integer, parcelas_media numeric)';
begin
  if v_fat is null or v_fun is null then
    raise exception 'z54: fn_fin_hotmart_faturamento ou fn_fin_hotmart_funis não existe com a assinatura (text,date,date)';
  end if;
  if (select count(*) from pg_proc where proname in ('fn_fin_hotmart_faturamento','fn_fin_hotmart_funis')
        and pronamespace = 'public'::regnamespace) <> 2 then
    raise exception 'z54: há sobrecarga viva de fn_fin_hotmart_faturamento/funis — conferir pg_get_function_arguments';
  end if;

  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_fat;
  if regexp_replace(v_src, '\s+', '', 'g') <> regexp_replace(e_fat, '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_fat_res, '\s+', '', 'g') then
    raise exception 'z54: corpo vivo de fn_fin_hotmart_faturamento diverge do repositório (20260927b). Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;

  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_fun;
  if regexp_replace(v_src, '\s+', '', 'g') <> regexp_replace(e_fun, '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_fun_res, '\s+', '', 'g') then
    raise exception 'z54: corpo vivo de fn_fin_hotmart_funis diverge do repositório (20260927h). Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;

  if (select count(*) from pg_proc where oid in (v_fat, v_fun) and prosecdef and provolatile = 's') <> 2 then
    raise exception 'z54: atributos vivos (security definer / stable) diferentes do esperado';
  end if;
end $guarda$;


-- ─── 1. Premissas com vigência ────────────────────────────────────────────────────────────────────────────────────────
create table if not exists fin.premissas_recebimento (
  vigente_de        date primary key,
  taxa_antecipacao  numeric(6,5) not null check (taxa_antecipacao >= 0 and taxa_antecipacao <= 0.2),
  pct_retido        numeric(5,4) not null check (pct_retido >= 0 and pct_retido <= 1),
  dias_ate_entrar   int not null check (dias_ate_entrar >= 0),
  dias_retencao     int not null check (dias_retencao >= 0),
  ativa             boolean not null default true,
  fonte             text not null check (btrim(fonte) <> ''),
  criado_em         timestamptz not null default now()
);
comment on table fin.premissas_recebimento is
  'Premissas do líquido realista (z54). Vale a última linha com vigente_de <= dia. ativa=false → colunas de recebimento nulas.';
alter table fin.premissas_recebimento enable row level security;   -- sem policy: só o dono (funções SECURITY DEFINER) lê
revoke all on fin.premissas_recebimento from public, anon, authenticated;

insert into fin.premissas_recebimento (vigente_de, taxa_antecipacao, pct_retido, dias_ate_entrar, dias_retencao, ativa, fonte)
values (date '2000-01-01', 0.0389, 0.10, 2, 30, true, 'Marcio 28/09/2026')
on conflict (vigente_de) do nothing;


-- ─── 2. A fórmula (fonte única) ───────────────────────────────────────────────────────────────────────────────────────
-- Sem premissa ativa para o dia → ZERO linhas (quem chama usa LEFT JOIN LATERAL ... ON TRUE e recebe nulos).
-- SQL, STABLE, não STRICT, sem SECURITY DEFINER e SEM "set search_path": são as condições para o planner EMBUTIR
-- (inline) a função no LATERAL. Com SET ela vira uma chamada por dia (≈2.500 no HT "Tudo"). Nomes todos qualificados;
-- sem grant: só o dono (as RPCs SECURITY DEFINER) executa. Ver "Decisão minha" no relatório da z54.
create or replace function fin.recebimento(p_dia date, p_liquido numeric)
returns table (entra_rapido numeric, retido numeric, custo_antecipacao numeric, liquido_total numeric,
               entra_em date, libera_em date)
language sql stable
as $$
  select c.antecipado - c.custo, c.ret, c.custo, c.antecipado - c.custo + c.ret,
         p_dia + c.dias_ate_entrar, p_dia + c.dias_retencao
    from (select r.ret, p_liquido - r.ret antecipado,
                 pg_catalog.round((p_liquido - r.ret) * r.taxa_antecipacao, 2) custo,
                 r.dias_ate_entrar, r.dias_retencao
            from (select pg_catalog.round(p_liquido * pr.pct_retido, 2) ret, pr.taxa_antecipacao,
                         pr.dias_ate_entrar, pr.dias_retencao, pr.ativa
                    from fin.premissas_recebimento pr
                   where pr.vigente_de <= p_dia
                   order by pr.vigente_de desc
                   limit 1) r
           where r.ativa) c
$$;
comment on function fin.recebimento(date, numeric) is
  'Fonte única da fórmula do líquido realista (z54): retido = round(L×pct,2); custo = round((L−retido)×taxa,2); entra = L−retido−custo.';
revoke all on function fin.recebimento(date, numeric) from public, anon, authenticated;


-- ─── 3. Parâmetros para a tela ────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_fin_premissas_recebimento()
returns table (vigente_de date, taxa_antecipacao numeric, pct_retido numeric, dias_ate_entrar int, dias_retencao int,
               ativa boolean, fonte text, vigente_hoje boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select p.vigente_de, p.taxa_antecipacao, p.pct_retido, p.dias_ate_entrar, p.dias_retencao, p.ativa, p.fonte,
         p.vigente_de = (select max(q.vigente_de) from fin.premissas_recebimento q where q.vigente_de <= v_hoje)
    from fin.premissas_recebimento p
   order by p.vigente_de desc;
end $$;
revoke all on function public.fn_fin_premissas_recebimento() from public, anon;
grant execute on function public.fn_fin_premissas_recebimento() to authenticated;


-- ─── 4. Faturamento diário + recebimento ──────────────────────────────────────────────────────────────────────────────
drop function public.fn_fin_hotmart_faturamento(text, date, date);
create function public.fn_fin_hotmart_faturamento(
  p_familia text default 'HM', p_inicio date default null, p_fim date default null)
returns table (
  dia date, vendas int, valor_oferta numeric, cobrado_cliente numeric, juros numeric,
  taxa_hotmart numeric, liquido numeric, liquido_estimado int,
  estornos int, valor_estornado numeric, recusadas int, boletos_gerados int, compradores int,
  entra_rapido numeric, retido numeric, retido_a_liberar numeric, custo_antecipacao numeric, liquido_total numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        v_ini  date := coalesce(p_inicio, v_hoje - 89);
        v_fim  date := coalesce(p_fim, v_hoje);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- Sem teto de dias: o custo é o das transações da família (plano 27/09: Aurum 2021→hoje 50 ms), não do intervalo.
  -- Um teto fixo voltaria a quebrar o "Tudo" da tela quando a história passasse dele.
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with p as (
    select t.dia_aprovado d,
           count(*) filter (where t.grupo = 'pago')::int vendas,  -- estorno não é venda paga (Fable 27/09)
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) oferta,
           coalesce(sum(t.valor_cobrado) filter (where t.grupo = 'pago'), 0) cobrado,
           coalesce(sum(t.juros) filter (where t.grupo = 'pago'), 0) juros,
           coalesce(sum(t.taxa_hotmart) filter (where t.grupo = 'pago'), 0) taxa,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.liquido_estimado)::int estimado,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) estornado,
           count(distinct t.email) filter (where t.grupo = 'pago')::int compradores
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('pago','estornado') and t.dia_aprovado between v_ini and v_fim
     group by 1
  ), a as (
    select t.dia_pedido d,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           count(*) filter (where t.grupo in ('em_aberto','expirado'))::int boletos
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('recusado','em_aberto','expirado') and t.dia_pedido between v_ini and v_fim
     group by 1
  )
  -- z54: recebimento sobre o líquido PAGO somado do dia (estorno fora). Sem premissa ativa → r.* nulo.
  select coalesce(p.d, a.d), coalesce(p.vendas, 0), coalesce(p.oferta, 0), coalesce(p.cobrado, 0),
         coalesce(p.juros, 0), coalesce(p.taxa, 0), coalesce(p.liquido, 0), coalesce(p.estimado, 0),
         coalesce(p.estornos, 0), coalesce(p.estornado, 0), coalesce(a.recusadas, 0), coalesce(a.boletos, 0),
         coalesce(p.compradores, 0),
         r.entra_rapido, r.retido,
         case when r.libera_em > v_hoje then r.retido when r.libera_em is not null then 0 end,
         r.custo_antecipacao, r.liquido_total
    from p full join a on a.d = p.d
    left join lateral fin.recebimento(coalesce(p.d, a.d), coalesce(p.liquido, 0)) r on true
   order by 1;
end $$;
revoke all on function public.fn_fin_hotmart_faturamento(text, date, date) from public, anon;
grant execute on function public.fn_fin_hotmart_faturamento(text, date, date) to authenticated;


-- ─── 5. Funis + recebimento (regra aplicada por funil × dia, depois somada) ───────────────────────────────────────────
drop function public.fn_fin_hotmart_funis(text, date, date);
create function public.fn_fin_hotmart_funis(p_familia text default 'HM', p_inicio date default null, p_fim date default null)
returns table (funil text, vale_de date, vale_ate date, vendas int, compradores int, valor_oferta numeric, cobrado_cliente numeric,
               juros numeric, taxa_hotmart numeric, liquido numeric, estornos int, valor_estornado numeric,
               recusadas int, boletos int, parcelado int, parcelas_media numeric,
               entra_rapido numeric, retido numeric, retido_a_liberar numeric, custo_antecipacao numeric, liquido_total numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        v_ini  date := coalesce(p_inicio, date '2021-01-01');
        v_fim  date := coalesce(p_fim, v_hoje);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with t as (
    -- z54: só as colunas usadas (tf agora é lido duas vezes e vira CTE materializada; linha estreita = tuplestore menor)
    select x.grupo, x.email, x.valor_oferta, x.valor_cobrado, x.juros, x.taxa_hotmart, x.liquido, x.parcelas,
           coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = p_familia
  ), tf as (
    select t.*, coalesce(f.nome, 'Sem funil') funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = p_familia and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between v_ini and v_fim
  ), g as (
    select tf.funil_nome, min(tf.f_de) f_de, max(tf.f_ate) f_ate,
           count(*) filter (where tf.grupo = 'pago')::int n_vendas,
           count(distinct tf.email) filter (where tf.grupo = 'pago')::int n_compradores,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0) s_oferta,
           coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0) s_cobrado,
           coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0) s_juros,
           coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0) s_taxa,
           coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) s_liquido,
           count(*) filter (where tf.grupo = 'estornado')::int n_estornos,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0) s_estornado,
           count(*) filter (where tf.grupo = 'recusado')::int n_recusadas,
           count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int n_boletos,
           count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int n_parcelado,
           round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1) m_parcelas
      from tf group by tf.funil_nome
  ), pd as (
    -- líquido PAGO do funil em cada dia (estorno fora); todo funil de g tem ao menos um dia aqui
    select tf.funil_nome, tf.dia_ref, coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) liq
      from tf group by tf.funil_nome, tf.dia_ref
  ), rec as (
    select pd.funil_nome,
           bool_and(r.liquido_total is not null) completo,   -- algum dia sem premissa ativa → funil inteiro nulo
           sum(r.entra_rapido) s_entra, sum(r.retido) s_retido,
           coalesce(sum(r.retido) filter (where r.libera_em > v_hoje), 0) s_a_liberar,
           sum(r.custo_antecipacao) s_custo, sum(r.liquido_total) s_total
      from pd left join lateral fin.recebimento(pd.dia_ref, pd.liq) r on true
     group by pd.funil_nome
  )
  select g.funil_nome, g.f_de, g.f_ate, g.n_vendas, g.n_compradores, g.s_oferta, g.s_cobrado, g.s_juros, g.s_taxa,
         g.s_liquido, g.n_estornos, g.s_estornado, g.n_recusadas, g.n_boletos, g.n_parcelado, g.m_parcelas,
         case when rec.completo then rec.s_entra end,
         case when rec.completo then rec.s_retido end,
         case when rec.completo then rec.s_a_liberar end,
         case when rec.completo then rec.s_custo end,
         case when rec.completo then rec.s_total end
    from g left join rec on rec.funil_nome = g.funil_nome
   order by g.f_de nulls last;
end $$;
revoke all on function public.fn_fin_hotmart_funis(text, date, date) from public, anon;
grant execute on function public.fn_fin_hotmart_funis(text, date, date) to authenticated;


-- ─── 6. Conferência dentro da migration (falha → rollback de tudo) ────────────────────────────────────────────────────
do $chk$
declare r record;
begin
  -- aceite da fórmula: 93,70 → entra 81,05 · retido 9,37 · custo 3,28 · total 90,42 · D+2 · D+30
  select * into r from fin.recebimento(date '2026-09-28', 93.70);
  if r.entra_rapido is distinct from 81.05 or r.retido is distinct from 9.37 or r.custo_antecipacao is distinct from 3.28
     or r.liquido_total is distinct from 90.42 or r.entra_em is distinct from date '2026-09-30'
     or r.libera_em is distinct from date '2026-10-28' then
    raise exception 'z54: aceite de fin.recebimento falhou: %', row_to_json(r);
  end if;
  -- antes da vigência inicial: sem linha (a tela recebe nulo, não zero)
  if exists (select 1 from fin.recebimento(date '1999-12-31', 100)) then
    raise exception 'z54: fin.recebimento devolveu linha sem premissa vigente';
  end if;
  -- grants: nada novo aberto para public/anon; fórmula e tabela fechadas também para authenticated
  if has_function_privilege('anon', 'public.fn_fin_hotmart_faturamento(text,date,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_hotmart_funis(text,date,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_premissas_recebimento()', 'execute')
     or has_function_privilege('anon', 'fin.recebimento(date,numeric)', 'execute')
     or has_function_privilege('authenticated', 'fin.recebimento(date,numeric)', 'execute')
     or has_table_privilege('anon', 'fin.premissas_recebimento', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.premissas_recebimento', 'select,insert,update,delete,truncate,references,trigger') then
    raise exception 'z54: grant aberto demais (conferir proacl/relacl)';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_hotmart_faturamento(text,date,date)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_hotmart_funis(text,date,date)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_premissas_recebimento()', 'execute') then
    raise exception 'z54: authenticated perdeu execute numa RPC da tela';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres, no SQL editor ou execute_sql; tudo leitura) ═════════════════════
/*
-- P1) Aceite da fórmula. Esperado: 81.05 | 9.37 | 3.28 | 90.42 | hoje+2 | hoje+30
select * from fin.recebimento(current_date, 93.70);

-- P2) Razão líquido_total / líquido no HM, 12 meses. Esperado ≈ 0,9650 (= 1 − 0,9 × 0,0389 = 0,96499).
--     Também o custo de antecipação de 12 meses de todas as famílias. Esperado ≈ R$ 472.010 sobre ≈ R$ 13.482.155.
with d as (
  select t.familia, t.dia_aprovado d, sum(t.liquido) l
    from fin.vw_transacoes t
   where t.grupo = 'pago' and t.dia_aprovado > (now() at time zone 'America/Sao_Paulo')::date - 365
   group by 1, 2)
select coalesce(d.familia, 'TODAS') familia, sum(d.l) liquido, sum(r.custo_antecipacao) custo, sum(r.liquido_total) total,
       round(sum(r.liquido_total) / nullif(sum(d.l), 0), 4) razao
  from d left join lateral fin.recebimento(d.d, d.l) r on true
 group by rollup (d.familia) order by 1;

-- P3) A RPC real (com guarda e JWT de um usuário do Financeiro) bate com P2 e as identidades fecham.
--     Trocar <UUID_FINANCEIRO> por um perfis.id ativo com acesso ao financeiro. Uma chamada só (begin…rollback juntos).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select round(sum(liquido_total) / nullif(sum(liquido), 0), 4) razao,                        -- ≈ 0,9650
       count(*) filter (where liquido_total is distinct from entra_rapido + retido) quebra_1,   -- 0
       count(*) filter (where liquido_total is distinct from liquido - custo_antecipacao) quebra_2, -- 0
       count(*) filter (where entra_rapido is null) sem_premissa,                               -- 0
       sum(retido_a_liberar) a_liberar                                                          -- ≈ retido dos últimos 30 dias
  from public.fn_fin_hotmart_faturamento('HM', (now() at time zone 'America/Sao_Paulo')::date - 364, null);
rollback;

-- P4) Funis × faturamento: por funil, líquido_total da RPC de funis = soma direta por funil×dia. Esperado: diferença 0.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select funil, liquido, liquido_total, round(liquido_total / nullif(liquido, 0), 4) razao, retido_a_liberar
  from public.fn_fin_hotmart_funis('HM', null, null);
rollback;

-- P5) Kill-switch. Esperado: colunas novas NULL, "liquido" intacto; depois volta. (Escreve: rodar em UMA chamada.)
begin;
update fin.premissas_recebimento set ativa = false;
select count(*) linhas, count(r.entra_rapido) com_valor from (values (current_date, 100::numeric)) v(d, l)
  left join lateral fin.recebimento(v.d, v.l) r on true;          -- esperado: 1 | 0
rollback;

-- P6) Moeda. vw_transacoes NÃO converte. Se a razão liquido/cobrado das vendas fora de BRL for ≈ 0,9 o líquido está na
--     moeda da venda (USD/EUR somados como R$ — risco já existente no "liquido", herdado pelas três linhas);
--     se for ≈ 5 (≈ câmbio) a comissão já vem em BRL e não há erro.
select t.moeda, count(*) vendas, sum(t.liquido_produtor) liquido,
       percentile_cont(0.5) within group (order by t.liquido_produtor / nullif(t.valor_cobrado, 0)) liq_sobre_cobrado
  from fin.hotmart_transacoes t
 where t.status in ('APPROVED','COMPLETE')
 group by 1 order by 2 desc;

-- P7) Grants vivos (esperado: anon/public ausentes; authenticated só nas 3 RPCs públicas).
select p.oid::regprocedure, p.proacl from pg_proc p
 where p.oid in ('public.fn_fin_hotmart_faturamento(text,date,date)'::regprocedure,
                 'public.fn_fin_hotmart_funis(text,date,date)'::regprocedure,
                 'public.fn_fin_premissas_recebimento()'::regprocedure,
                 'fin.recebimento(date,numeric)'::regprocedure);
select relname, relacl, relrowsecurity from pg_class where oid = 'fin.premissas_recebimento'::regclass;


-- ═══ DESEMPENHO — explain (analyze, buffers) do corpo interno ANTES × DEPOIS. Critério: depois ≤ antes + 10%. ═══════
-- Cada bloco é UMA chamada (prepare + explain na mesma sessão). Rodar cada um 2× e usar a 2ª (1ª é cache frio).
-- O corpo ANTES é o do repo (a guarda provou = vivo); roda antes OU depois de aplicar (só lê fin.vw_transacoes).
-- Parâmetros: $1 família · $2 início · $3 fim. Casos: ('HT','2019-01-01',current_date) · ('HM','2015-01-01',current_date)
-- ["Tudo"] · ('HM', current_date - 29, current_date) [30 dias].
-- DEPOIS: conferir que NÃO aparece "Function Scan on recebimento" (sinal de que o inline falhou; aí a fórmula vira
-- uma chamada por dia) — o esperado é um Limit/Seq Scan on premissas_recebimento dentro do Nested Loop.

-- D1) faturamento ANTES
deallocate all;
prepare fat_antes(text, date, date) as
  with p as (
    select t.dia_aprovado d,
           count(*) filter (where t.grupo = 'pago')::int vendas,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) oferta,
           coalesce(sum(t.valor_cobrado) filter (where t.grupo = 'pago'), 0) cobrado,
           coalesce(sum(t.juros) filter (where t.grupo = 'pago'), 0) juros,
           coalesce(sum(t.taxa_hotmart) filter (where t.grupo = 'pago'), 0) taxa,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.liquido_estimado)::int estimado,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) estornado,
           count(distinct t.email) filter (where t.grupo = 'pago')::int compradores
      from fin.vw_transacoes t
     where t.familia = $1 and t.grupo in ('pago','estornado') and t.dia_aprovado between $2 and $3
     group by 1
  ), a as (
    select t.dia_pedido d,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           count(*) filter (where t.grupo in ('em_aberto','expirado'))::int boletos
      from fin.vw_transacoes t
     where t.familia = $1 and t.grupo in ('recusado','em_aberto','expirado') and t.dia_pedido between $2 and $3
     group by 1
  )
  select coalesce(p.d, a.d), coalesce(p.vendas, 0), coalesce(p.oferta, 0), coalesce(p.cobrado, 0),
         coalesce(p.juros, 0), coalesce(p.taxa, 0), coalesce(p.liquido, 0), coalesce(p.estimado, 0),
         coalesce(p.estornos, 0), coalesce(p.estornado, 0), coalesce(a.recusadas, 0), coalesce(a.boletos, 0),
         coalesce(p.compradores, 0)
    from p full join a on a.d = p.d
   order by 1;
explain (analyze, buffers) execute fat_antes('HT', '2019-01-01', current_date);
-- idem com ('HM', '2015-01-01', current_date) e ('HM', current_date - 29, current_date)

-- D2) faturamento DEPOIS
deallocate all;
prepare fat_depois(text, date, date) as
  with p as (
    select t.dia_aprovado d,
           count(*) filter (where t.grupo = 'pago')::int vendas,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) oferta,
           coalesce(sum(t.valor_cobrado) filter (where t.grupo = 'pago'), 0) cobrado,
           coalesce(sum(t.juros) filter (where t.grupo = 'pago'), 0) juros,
           coalesce(sum(t.taxa_hotmart) filter (where t.grupo = 'pago'), 0) taxa,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.liquido_estimado)::int estimado,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) estornado,
           count(distinct t.email) filter (where t.grupo = 'pago')::int compradores
      from fin.vw_transacoes t
     where t.familia = $1 and t.grupo in ('pago','estornado') and t.dia_aprovado between $2 and $3
     group by 1
  ), a as (
    select t.dia_pedido d,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           count(*) filter (where t.grupo in ('em_aberto','expirado'))::int boletos
      from fin.vw_transacoes t
     where t.familia = $1 and t.grupo in ('recusado','em_aberto','expirado') and t.dia_pedido between $2 and $3
     group by 1
  )
  select coalesce(p.d, a.d), coalesce(p.vendas, 0), coalesce(p.oferta, 0), coalesce(p.cobrado, 0),
         coalesce(p.juros, 0), coalesce(p.taxa, 0), coalesce(p.liquido, 0), coalesce(p.estimado, 0),
         coalesce(p.estornos, 0), coalesce(p.estornado, 0), coalesce(a.recusadas, 0), coalesce(a.boletos, 0),
         coalesce(p.compradores, 0),
         r.entra_rapido, r.retido,
         case when r.libera_em > (now() at time zone 'America/Sao_Paulo')::date then r.retido
              when r.libera_em is not null then 0 end,
         r.custo_antecipacao, r.liquido_total
    from p full join a on a.d = p.d
    left join lateral fin.recebimento(coalesce(p.d, a.d), coalesce(p.liquido, 0)) r on true
   order by 1;
explain (analyze, buffers) execute fat_depois('HT', '2019-01-01', current_date);
-- idem com ('HM', '2015-01-01', current_date) e ('HM', current_date - 29, current_date)

-- D3) funis ANTES — ('HM', null, null) = v_ini 2021-01-01, v_fim hoje
deallocate all;
prepare fun_antes(text, date, date) as
  with t as (
    select x.*, coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = $1
  ), tf as (
    select t.*, f.nome funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = $1 and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between $2 and $3
  )
  select coalesce(tf.funil_nome, 'Sem funil'), min(tf.f_de), max(tf.f_ate),
         count(*) filter (where tf.grupo = 'pago')::int,
         count(distinct tf.email) filter (where tf.grupo = 'pago')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0),
         count(*) filter (where tf.grupo = 'estornado')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0),
         count(*) filter (where tf.grupo = 'recusado')::int,
         count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int,
         count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int,
         round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1)
    from tf group by coalesce(tf.funil_nome, 'Sem funil')
   order by min(tf.f_de) nulls last;
explain (analyze, buffers) execute fun_antes('HM', '2021-01-01', (now() at time zone 'America/Sao_Paulo')::date);

-- D4) funis DEPOIS
deallocate all;
prepare fun_depois(text, date, date) as
  with t as (
    select x.grupo, x.email, x.valor_oferta, x.valor_cobrado, x.juros, x.taxa_hotmart, x.liquido, x.parcelas,
           coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = $1
  ), tf as (
    select t.*, coalesce(f.nome, 'Sem funil') funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = $1 and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between $2 and $3
  ), g as (
    select tf.funil_nome, min(tf.f_de) f_de, max(tf.f_ate) f_ate,
           count(*) filter (where tf.grupo = 'pago')::int n_vendas,
           count(distinct tf.email) filter (where tf.grupo = 'pago')::int n_compradores,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0) s_oferta,
           coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0) s_cobrado,
           coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0) s_juros,
           coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0) s_taxa,
           coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) s_liquido,
           count(*) filter (where tf.grupo = 'estornado')::int n_estornos,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0) s_estornado,
           count(*) filter (where tf.grupo = 'recusado')::int n_recusadas,
           count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int n_boletos,
           count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int n_parcelado,
           round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1) m_parcelas
      from tf group by tf.funil_nome
  ), pd as (
    select tf.funil_nome, tf.dia_ref, coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) liq
      from tf group by tf.funil_nome, tf.dia_ref
  ), rec as (
    select pd.funil_nome, bool_and(r.liquido_total is not null) completo,
           sum(r.entra_rapido) s_entra, sum(r.retido) s_retido,
           coalesce(sum(r.retido) filter (where r.libera_em > (now() at time zone 'America/Sao_Paulo')::date), 0) s_a_liberar,
           sum(r.custo_antecipacao) s_custo, sum(r.liquido_total) s_total
      from pd left join lateral fin.recebimento(pd.dia_ref, pd.liq) r on true
     group by pd.funil_nome
  )
  select g.funil_nome, g.f_de, g.f_ate, g.n_vendas, g.n_compradores, g.s_oferta, g.s_cobrado, g.s_juros, g.s_taxa,
         g.s_liquido, g.n_estornos, g.s_estornado, g.n_recusadas, g.n_boletos, g.n_parcelado, g.m_parcelas,
         case when rec.completo then rec.s_entra end, case when rec.completo then rec.s_retido end,
         case when rec.completo then rec.s_a_liberar end, case when rec.completo then rec.s_custo end,
         case when rec.completo then rec.s_total end
    from g left join rec on rec.funil_nome = g.funil_nome
   order by g.f_de nulls last;
explain (analyze, buffers) execute fun_depois('HM', '2021-01-01', (now() at time zone 'America/Sao_Paulo')::date);

-- D5) A RPC inteira (o livro manda medir a função, não só o corpo): antes de aplicar e depois, mesmo usuário.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_hotmart_faturamento('HT', '2019-01-01', current_date);
rollback;
-- idem para ('HM','2015-01-01',current_date), ('HM',current_date-29,current_date) e fn_fin_hotmart_funis('HM',null,null)
*/
