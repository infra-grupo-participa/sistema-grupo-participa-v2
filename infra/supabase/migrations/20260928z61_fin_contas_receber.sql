-- 20260928z61 — Contas a Receber, fatia 2: blocos 1 e 2 da planilha semanal do financeiro, derivados do espelho Hotmart.
--
-- APLICADA em produção em 28/09/2026 (apply_migration "fin_contas_receber"), já com o nome fn_fin_receber_semanal. Provas (seção PROVAS) ainda por medir.
-- Depende da z60 (calendário de caixa em dias úteis). A guarda aborta se a z60 não estiver aplicada.
--
-- Substitui, da planilha "Contas a Receber Semanal Set-Dez26", só o que é CERTO:
--   bloco 1 — Vendas já realizadas: 90% − 3,89% em D+2 útil e 10% no 1º dia útil ≥ D+30, ainda não caídos no corte.
--             Todo o espelho (um produtor só em 2026 = Academy; a conta da Soluções não está conectada).
--   bloco 2 — Recorrências já contratadas: próxima(s) cobrança(s) de assinatura e de parcelado Hotmart, SEM fator de perda
--             (fase 2 põe as perdas em fin.premissas_receber).
-- Blocos 3–7 (vendas novas, evento, informados, ajustes, Soluções) ficam fora. Bloco 5 NÃO entra agora.
--
-- O que cria:
--   1) 2 índices parciais em fin.hotmart_transacoes: (aprovado_em) das pagas e (e-mail, oferta, recorrência) das recorrentes.
--   2) fin.premissas_receber (chave, vigente_de) → valor. Carga: tolerância de atraso 5 d, conciliação 10%, atraso máximo
--      projetado 35 d (aba Premissas da planilha).
--   3) fin.receber_vendas_realizadas(corte) — bloco 1, interna.
--   4) fin.cobrancas_previstas(corte, ate) — bloco 2, interna, derivada (sem tabela).
--   5) public.fn_fin_receber_semanal(p_corte, p_ate) — ÚNICA RPC da aba. Contrato (a tela do iromar depende dele):
--        bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, origem_dia date,
--        ref text, rotulo text, produto text, k int, detalhe jsonb
--      componente: 'antecipacao' | 'garantia' (dinheiro que cai em data_caixa) | 'cheio' (linha de auditoria, data_caixa NULL)
--      situacao:   'a_receber' (soma) | 'em_atraso_fora' (saiu da projeção, não soma) | 'realizada' (auditoria, não soma)
--      origem_dia: bloco 1 = dia da venda; bloco 2 = vencimento previsto da cobrança.
--      ref:        bloco 2 = fin.chave_opaca do contrato (e-mail|oferta) — nunca o e-mail. rotulo = nome próprio.
--      detalhe:    bloco 1 = [{transacao, produto, nome, liquido}] das vendas do dia (sem e-mail/documento); bloco 2 = NULL.
--      p_corte NULL = agora; p_ate NULL = último dia de (mês do corte + 3). Horizonte máximo: corte + 400 dias.
--
-- Regras do bloco 2 (decisões registradas no relatório do Victor, 28/09):
--   * contrato = lower(trim(e-mail)) | oferta_codigo (a mesma chave de fn_fin_contratado; o código do assinante NÃO existe
--     no bruto_json). Universo: contratos com cobrança recorrente PAGA nos 120 dias até o corte, em modo SUBSCRIPTION,
--     HOTMART_INSTALLMENTS* ou MULTIPLE_PAYMENTS (Holding Mais — tratado como parcelado).
--   * UNIQUE_PAYMENT com recorrência NÃO cria contrato; conta só como pagamento de um contrato que já existe pelos modos acima.
--   * assinatura: próxima n = recorrência da ÚLTIMA paga + 1, até p_ate. parcelado: de (maior paga + 1) até parcelas, até p_ate.
--   * vencimento(n) = 1ª cobrança (recorrência 1 paga mais recente) + (n − 1) meses; sem recorrência 1 no espelho:
--     última paga + (n − n_última) meses. (vencimento_b = sempre "última paga + …" — só para a prova P-B2-DATA.)
--   * valor = líquido da última paga. Contrato com estorno na série atual (≥ 1ª cobrança) sai.
--   * situação: vencimento + tolerância < corte → em_atraso_fora; senão a_receber com data efetiva = max(vencimento, corte + 1).
--     Vencida há mais de atraso_max_projetado_dias não é listada; contrato cuja 1ª cobrança em aberto venceu há mais que
--     isso sai inteiro (planilha: "contratos > 35 dias em atraso já excluídos").
--   * "Pago" é o que foi aprovado ATÉ o corte (p_corte no passado reproduz a posição daquele dia).
--   * caixa de cada cobrança a receber = fin.recebimento(data efetiva, valor). k = meses à frente (mês do corte = 1).
--
-- REVERSÃO (nada mais depende disto; a tela some sem a RPC):
--   drop function public.fn_fin_receber_semanal(timestamptz, date);
--   drop function fin.cobrancas_previstas(timestamptz, date);
--   drop function fin.receber_vendas_realizadas(timestamptz);
--   alter table fin.premissas_receber rename to premissas_receber_arquivada_z61;
--   drop index fin.hotmart_transacoes_aprovado_pago_idx;  drop index fin.hotmart_transacoes_contrato_rec_idx;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('fin.calendario_caixa') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'fin' and table_name = 'premissas_recebimento' and column_name = 'dias_uteis') then
    raise exception 'z61: aplicar a z60 (calendário de caixa) antes';
  end if;
  if to_regclass('fin.premissas_receber') is not null
     or to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date)') is not null then
    raise exception 'z61: já aplicada (fin.premissas_receber ou fn_fin_receber_semanal existe)';
  end if;
  if exists (select 1 from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) then
    raise exception 'z61: existe fn_fin_receber_semanal com outra assinatura — conferir antes (sobrecarga)';
  end if;
end $guarda$;


-- ─── 1. Índices ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Bloco 1 e universo do bloco 2: pagas por aprovado_em. A consulta repete o predicado literal "status in (...)".
create index if not exists hotmart_transacoes_aprovado_pago_idx
  on fin.hotmart_transacoes (aprovado_em) where status in ('APPROVED','COMPLETE');
-- Bloco 2: história de cada contrato. lower(trim(x)) = a expressão da view (email) e do índice hotmart_transacoes_email_idx.
create index if not exists hotmart_transacoes_contrato_rec_idx
  on fin.hotmart_transacoes (lower(trim(comprador_email)), oferta_codigo, recorrencia) where recorrencia is not null;


-- ─── 2. Premissas do contas a receber ───────────────────────────────────────────────────────────────────────────────
create table fin.premissas_receber (
  chave       text not null check (btrim(chave) <> ''),
  vigente_de  date not null,
  valor       numeric not null check (valor >= 0),
  fonte       text not null check (btrim(fonte) <> ''),
  criado_em   timestamptz not null default now(),
  primary key (chave, vigente_de)
);
comment on table fin.premissas_receber is
  'Premissas do Contas a Receber (z61). Vale a última linha com vigente_de <= dia do corte, por chave. Fase 2: perdas.';
alter table fin.premissas_receber enable row level security;
revoke all on fin.premissas_receber from public, anon, authenticated;

insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
  ('tolerancia_atraso_dias',    date '2000-01-01', 5,    'planilha Contas a Receber Semanal, aba Premissas (25/09/2026)'),
  ('tolerancia_conciliacao',    date '2000-01-01', 0.10, 'planilha Contas a Receber Semanal, aba Premissas (25/09/2026)'),
  ('atraso_max_projetado_dias', date '2000-01-01', 35,   'planilha Contas a Receber Semanal, aba Premissas (25/09/2026)');


-- ─── 3. Bloco 1 — vendas já realizadas, dinheiro ainda a cair ───────────────────────────────────────────────────────
-- Soma o líquido PAGO por dia de aprovação (a mesma base e a mesma regra "por dia" do Faturamento), aplica
-- fin.recebimento e devolve as duas parcelas de caixa ainda depois do dia do corte (fuso de São Paulo).
-- Janela: 50 dias antes do corte (a garantia mais distante cai em ~D+34 com feriados). Filtro direto em status/aprovado_em
-- (colunas cruas da view) para o índice parcial de aprovado_em.
create function fin.receber_vendas_realizadas(p_corte timestamptz)
returns table (componente text, data_caixa date, valor numeric, origem_dia date, detalhe jsonb)
language sql stable set search_path = ''
as $$
  with d as (
    select t.dia_aprovado dia, sum(t.liquido) liquido,
           jsonb_agg(jsonb_build_object('transacao', t.transacao, 'produto', t.produto_nome,
                                        'nome', fin.nome_proprio(t.nome), 'liquido', t.liquido)
                     order by t.aprovado_em, t.transacao) detalhe
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em >= p_corte - interval '50 days' and t.aprovado_em <= p_corte
     group by t.dia_aprovado
  )
  select u.componente, u.data_caixa, u.valor, d.dia, d.detalhe
    from d
    cross join lateral fin.recebimento(d.dia, d.liquido) r
    cross join lateral (values ('antecipacao'::text, r.entra_em, r.entra_rapido),
                               ('garantia'::text,    r.libera_em, r.retido)) u(componente, data_caixa, valor)
   where u.data_caixa > (p_corte at time zone 'America/Sao_Paulo')::date
   order by u.data_caixa, u.componente, d.dia
$$;
comment on function fin.receber_vendas_realizadas(timestamptz) is
  'Contas a Receber bloco 1 (z61): antecipação e garantia das vendas pagas até o corte, com data de caixa depois do corte.';
revoke all on function fin.receber_vendas_realizadas(timestamptz) from public, anon, authenticated;


-- ─── 4. Bloco 2 — cobranças recorrentes previstas ───────────────────────────────────────────────────────────────────
create function fin.cobrancas_previstas(p_corte timestamptz, p_ate date)
returns table (
  grupo text, tipo text, ref text, rotulo text, produto text, n int, parcelas int,
  vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k int,
  entra_em date, entra_rapido numeric, libera_em date, retido numeric)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dia   date;
  v_tol   int;
  v_max   int;
  v_meses int;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.cobrancas_previstas: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'fin.cobrancas_previstas: horizonte fora de [corte, corte + 400 dias]' using errcode = '22023';
  end if;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_max is null then
    raise exception 'fin.cobrancas_previstas: premissa de atraso ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;
  -- teto de cobranças por assinatura: meses entre (corte − atraso máximo) e o horizonte, com folga de 2
  v_meses := ((extract(year from p_ate) - extract(year from v_dia - v_max)) * 12
              + extract(month from p_ate) - extract(month from v_dia - v_max))::int + 2;

  return query
  with ativos as (
    select distinct t.email, t.oferta_codigo
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > p_corte - interval '120 days' and t.aprovado_em <= p_corte
       and t.recorrencia is not null
       and (t.oferta_modo = 'SUBSCRIPTION' or t.oferta_modo = 'MULTIPLE_PAYMENTS'
            or t.oferta_modo like 'HOTMART_INSTALLMENTS%')
       and t.email is not null and t.oferta_codigo is not null
  ), tx as materialized (
    select t.email, t.oferta_codigo, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
           t.recorrencia, t.parcelas, t.liquido, t.aprovado_em, t.dia_aprovado, t.dia_pedido, t.nome,
           (t.grupo = 'pago' and t.aprovado_em <= p_corte) pago
      from ativos a
      join fin.vw_transacoes t
        on t.email = a.email and t.oferta_codigo = a.oferta_codigo and t.recorrencia is not null
  ), c as (
    select x.email, x.oferta_codigo,
           (array_agg(x.oferta_modo order by x.aprovado_em desc, x.recorrencia desc)
              filter (where x.pago and x.oferta_modo <> 'UNIQUE_PAYMENT'))[1] modo,
           (array_agg(x.recorrencia  order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] n_ult,
           (array_agg(x.dia_aprovado order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] d_ult,
           (array_agg(x.liquido      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] valor_ult,
           (array_agg(x.nome         order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] nome,
           (array_agg(x.produto_nome order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_nome,
           (array_agg(x.produto_id   order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_id,
           (array_agg(x.familia      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] familia,
           max(x.recorrencia) filter (where x.pago) n_max,
           max(x.dia_aprovado) filter (where x.pago and x.recorrencia = 1) d1,
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           fin.chave_opaca('rc:' || c.email || '|' || c.oferta_codigo) ref   -- uma vez por contrato (lê o Vault)
      from c
     where c.modo is not null and c.n_ult is not null
       and not exists (select 1 from tx e
                        where e.email = c.email and e.oferta_codigo = c.oferta_codigo and e.grupo = 'estornado'
                          and (c.d1 is null or coalesce(e.dia_aprovado, e.dia_pedido) >= c.d1))
  ), g as (
    select c2.*, s.n,
           case when c2.d1 is not null then (c2.d1 + make_interval(months => s.n - 1))::date
                else (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date end venc,
           (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date venc_b
      from c2
      cross join lateral generate_series(c2.n_base + 1,
               case when c2.tipo = 'parcelado' then least(c2.parcelas, c2.n_base + v_meses)
                    else c2.n_base + v_meses end) s(n)
  ), vivos as (
    select g.ref from g where g.n = g.n_base + 1 and g.venc >= v_dia - v_max
  ), prev as (
    select g.*,
           case when g.venc + v_tol < v_dia then 'em_atraso_fora' else 'a_receber' end sit,
           case when g.venc + v_tol < v_dia then null::date else greatest(g.venc, v_dia + 1) end efetiva
      from g
     where g.ref in (select vivos.ref from vivos)
       and g.venc <= p_ate and g.venc >= v_dia - v_max
  ), feitas as (
    select c2.*, x.recorrencia n_pago, x.liquido liq_pago
      from c2
      join tx x on x.email = c2.email and x.oferta_codigo = c2.oferta_codigo
     where x.pago and x.dia_aprovado > v_dia - v_max
  )
  select p.grupo_nome, p.tipo, p.ref, fin.nome_proprio(p.nome), p.produto_nome, p.n, p.parcelas,
         p.venc, p.venc_b, p.sit, p.efetiva, p.valor_ult,
         case when p.sit = 'a_receber'
              then ((extract(year from p.efetiva) - extract(year from v_dia)) * 12
                    + extract(month from p.efetiva) - extract(month from v_dia))::int + 1 end,
         r.entra_em, r.entra_rapido, r.libera_em, r.retido
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber'
  union all
  select f.grupo_nome, f.tipo, f.ref, fin.nome_proprio(f.nome), f.produto_nome, f.n_pago, f.parcelas,
         case when f.d1 is not null then (f.d1 + make_interval(months => f.n_pago - 1))::date end,
         (f.d_ult + make_interval(months => f.n_pago - f.n_ult))::date,
         'realizada', null::date, f.liq_pago, null::int, null::date, null::numeric, null::date, null::numeric
    from feitas f
   order by 1, 8, 3, 6;
end $$;
comment on function fin.cobrancas_previstas(timestamptz, date) is
  'Contas a Receber bloco 2 (z61): cobranças recorrentes previstas (assinatura/parcelado Hotmart) por contrato e-mail|oferta.';
revoke all on function fin.cobrancas_previstas(timestamptz, date) from public, anon, authenticated;


-- ─── 5. A RPC da aba ────────────────────────────────────────────────────────────────────────────────────────────────
create function public.fn_fin_receber_semanal(p_corte timestamptz default null, p_ate date default null)
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_corte timestamptz := coalesce(p_corte, now());
  v_dia   date := (coalesce(p_corte, now()) at time zone 'America/Sao_Paulo')::date;
  v_ate   date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  return query
  select 1::smallint, 'Vendas já realizadas'::text, b.componente, b.data_caixa, b.valor, 'a_receber'::text,
         b.origem_dia, null::text, null::text, null::text, null::int, b.detalhe
    from fin.receber_vendas_realizadas(v_corte) b
  union all
  select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.situacao, c.vencimento,
         c.ref, c.rotulo, c.produto, c.k, null::jsonb
    from fin.cobrancas_previstas(v_corte, v_ate) c
    cross join lateral (
      select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.situacao = 'a_receber'
      union all
      select 'garantia'::text, c.libera_em, c.retido where c.situacao = 'a_receber'
      union all
      select 'cheio'::text, null::date, c.valor where c.situacao <> 'a_receber'
    ) u(componente, data_caixa, valor)
   order by 1, 4 nulls last, 2, 3;
end $$;
comment on function public.fn_fin_receber_semanal(timestamptz, date) is
  'Aba Contas a Receber (z61): blocos 1 e 2. Soma só situacao = a_receber. Sem e-mail/documento: ref opaca, nome próprio.';
revoke all on function public.fn_fin_receber_semanal(timestamptz, date) from public, anon;
grant execute on function public.fn_fin_receber_semanal(timestamptz, date) to authenticated;


-- ─── 6. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp) + interval '4 months' - interval '1 day')::date;
  v_ok  boolean;
begin
  if (select count(*) from fin.premissas_receber) <> 3 then
    raise exception 'z61: premissas_receber sem as 3 linhas';
  end if;

  -- bloco 1: só caixa futuro, só os 2 componentes, valor não nulo
  if exists (select 1 from fin.receber_vendas_realizadas(now()) b
              where b.data_caixa <= v_dia or b.componente not in ('antecipacao','garantia') or b.valor is null
                 or b.origem_dia > v_dia or jsonb_typeof(b.detalhe) <> 'array') then
    raise exception 'z61: bloco 1 com linha fora do contrato';
  end if;

  -- bloco 2: invariantes de situação
  if exists (select 1 from fin.cobrancas_previstas(now(), v_ate) c
              where c.situacao not in ('a_receber','em_atraso_fora','realizada')
                 or (c.situacao = 'a_receber' and (c.data_efetiva <= v_dia or c.entra_em <= v_dia or c.k < 1
                                                   or c.vencimento > v_ate))
                 or (c.situacao <> 'a_receber' and (c.data_efetiva is not null or c.entra_em is not null))
                 or (c.situacao = 'em_atraso_fora' and c.vencimento < v_dia - 35)
                 or c.ref is null or c.grupo is null) then
    raise exception 'z61: bloco 2 com linha fora do contrato';
  end if;

  -- RPC sem sessão → 42501
  v_ok := false;
  begin
    perform * from public.fn_fin_receber_semanal(null, null);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z61: fn_fin_receber_semanal respondeu sem sessão'; end if;

  -- grants
  if has_table_privilege('anon', 'fin.premissas_receber', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.premissas_receber', 'select,insert,update,delete,truncate,references,trigger')
     or has_function_privilege('anon', 'fin.receber_vendas_realizadas(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'fin.receber_vendas_realizadas(timestamptz)', 'execute')
     or has_function_privilege('anon', 'fin.cobrancas_previstas(timestamptz,date)', 'execute')
     or has_function_privilege('authenticated', 'fin.cobrancas_previstas(timestamptz,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_receber_semanal(timestamptz,date)', 'execute') then
    raise exception 'z61: grant aberto demais (conferir relacl/proacl)';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_receber_semanal(timestamptz,date)', 'execute') then
    raise exception 'z61: authenticated sem execute em fn_fin_receber_semanal';
  end if;
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{=X/postgres}'::aclitem[])) ac
              where p.oid in ('fin.receber_vendas_realizadas(timestamptz)'::regprocedure,
                              'fin.cobrancas_previstas(timestamptz,date)'::regprocedure,
                              'public.fn_fin_receber_semanal(timestamptz,date)'::regprocedure)
                and ac::text like '=%') then
    raise exception 'z61: função com EXECUTE para PUBLIC (ou proacl nulo)';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; tudo leitura) ═════════════════════════════════════════════════
-- Cada bloco é UMA chamada. explain: rodar 2× e usar a 2ª (1ª é cache frio). <UUID_FINANCEIRO> = perfis.id ativo que VÊ
-- o financeiro.
/*
-- E1) Faturamento/Funis com o corpo novo de fin.recebimento (z60). Rodar SEM MUDAR os blocos da z54:
--     D2 (z54 linhas 513–551) com ('HT','2019-01-01',current_date), ('HM','2015-01-01',current_date),
--     ('HM',current_date-29,current_date); D4 (linhas 582–627) com ('HM','2021-01-01',hoje); D5 (linhas 629–635).
--     Teto: HT tudo ≤ 345 ms · HM tudo ≤ 281 · HM 30 d ≤ 84 · funis ≤ 388.
--     NÃO pode aparecer "Function Scan on recebimento" (inline perdido → uma chamada por dia). Esperado: dentro do
--     Nested Loop, Limit/Seq Scan on premissas_recebimento + SubPlans com Index Scan em calendario_caixa_pkey e
--     calendario_caixa_n_util_uidx.

-- E2) Corpo do bloco 1 (índice parcial de aprovado_em). Esperado: Index Scan/Bitmap em hotmart_transacoes_aprovado_pago_idx,
--     sem "Function Scan on recebimento".
deallocate all;
prepare b1(timestamptz) as
  with d as (
    select t.dia_aprovado dia, sum(t.liquido) liquido,
           jsonb_agg(jsonb_build_object('transacao', t.transacao, 'produto', t.produto_nome,
                                        'nome', fin.nome_proprio(t.nome), 'liquido', t.liquido)
                     order by t.aprovado_em, t.transacao) detalhe
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em >= $1 - interval '50 days' and t.aprovado_em <= $1
     group by t.dia_aprovado
  )
  select u.componente, u.data_caixa, u.valor, d.dia, d.detalhe
    from d
    cross join lateral fin.recebimento(d.dia, d.liquido) r
    cross join lateral (values ('antecipacao'::text, r.entra_em, r.entra_rapido),
                               ('garantia'::text,    r.libera_em, r.retido)) u(componente, data_caixa, valor)
   where u.data_caixa > ($1 at time zone 'America/Sao_Paulo')::date
   order by u.data_caixa, u.componente, d.dia;
explain (analyze, buffers) execute b1(now());
explain (analyze, buffers) execute b1(timestamptz '2026-09-25 23:59:59-03');

-- E3) Corpo do bloco 2. $1 corte · $2 horizonte · $3 tolerância (5) · $4 atraso máximo (35) · $5 v_meses (ver função).
--     Esperado: universo por hotmart_transacoes_aprovado_pago_idx; história por hotmart_transacoes_contrato_rec_idx
--     (Index Scan com Index Cond lower(btrim(comprador_email)) = … AND oferta_codigo = …). Seq Scan em hotmart_transacoes
--     = índice ignorado → avisar o Victor.
deallocate all;
prepare b2(timestamptz, date, int, int, int) as
  with ativos as (
    select distinct t.email, t.oferta_codigo
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > $1 - interval '120 days' and t.aprovado_em <= $1
       and t.recorrencia is not null
       and (t.oferta_modo = 'SUBSCRIPTION' or t.oferta_modo = 'MULTIPLE_PAYMENTS'
            or t.oferta_modo like 'HOTMART_INSTALLMENTS%')
       and t.email is not null and t.oferta_codigo is not null
  ), tx as materialized (
    select t.email, t.oferta_codigo, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
           t.recorrencia, t.parcelas, t.liquido, t.aprovado_em, t.dia_aprovado, t.dia_pedido, t.nome,
           (t.grupo = 'pago' and t.aprovado_em <= $1) pago
      from ativos a
      join fin.vw_transacoes t
        on t.email = a.email and t.oferta_codigo = a.oferta_codigo and t.recorrencia is not null
  ), c as (
    select x.email, x.oferta_codigo,
           (array_agg(x.oferta_modo order by x.aprovado_em desc, x.recorrencia desc)
              filter (where x.pago and x.oferta_modo <> 'UNIQUE_PAYMENT'))[1] modo,
           (array_agg(x.recorrencia  order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] n_ult,
           (array_agg(x.dia_aprovado order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] d_ult,
           (array_agg(x.liquido      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] valor_ult,
           (array_agg(x.nome         order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] nome,
           (array_agg(x.produto_nome order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_nome,
           (array_agg(x.produto_id   order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_id,
           (array_agg(x.familia      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] familia,
           max(x.recorrencia) filter (where x.pago) n_max,
           max(x.dia_aprovado) filter (where x.pago and x.recorrencia = 1) d1,
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           fin.chave_opaca('rc:' || c.email || '|' || c.oferta_codigo) ref
      from c
     where c.modo is not null and c.n_ult is not null
       and not exists (select 1 from tx e
                        where e.email = c.email and e.oferta_codigo = c.oferta_codigo and e.grupo = 'estornado'
                          and (c.d1 is null or coalesce(e.dia_aprovado, e.dia_pedido) >= c.d1))
  ), g as (
    select c2.*, s.n,
           case when c2.d1 is not null then (c2.d1 + make_interval(months => s.n - 1))::date
                else (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date end venc,
           (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date venc_b
      from c2
      cross join lateral generate_series(c2.n_base + 1,
               case when c2.tipo = 'parcelado' then least(c2.parcelas, c2.n_base + $5)
                    else c2.n_base + $5 end) s(n)
  ), vivos as (
    select g.ref from g where g.n = g.n_base + 1 and g.venc >= ($1 at time zone 'America/Sao_Paulo')::date - $4
  ), prev as (
    select g.*,
           case when g.venc + $3 < ($1 at time zone 'America/Sao_Paulo')::date then 'em_atraso_fora' else 'a_receber' end sit,
           case when g.venc + $3 < ($1 at time zone 'America/Sao_Paulo')::date then null::date
                else greatest(g.venc, ($1 at time zone 'America/Sao_Paulo')::date + 1) end efetiva
      from g
     where g.ref in (select vivos.ref from vivos)
       and g.venc <= $2 and g.venc >= ($1 at time zone 'America/Sao_Paulo')::date - $4
  )
  select p.grupo_nome, p.sit, p.efetiva, p.valor_ult, r.entra_em, r.entra_rapido, r.libera_em, r.retido
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber';
explain (analyze, buffers) execute b2(timestamptz '2026-09-25 23:59:59-03', date '2026-12-31', 5, 35, 6);   -- $5 = v_meses (ago→dez + 2)
explain (analyze, buffers) execute b2(now(), (date_trunc('month', current_date) + interval '4 months' - interval '1 day')::date, 5, 35, 6);

-- E5) A RPC inteira, com o usuário do Financeiro. Teto: ≤ 300 ms (2ª execução).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31');
select count(*), pg_size_pretty(sum(pg_column_size(x))::bigint) tamanho from public.fn_fin_receber_semanal(null, null) x;
rollback;

-- P-B1-EQ) Regra aplicada por DIA (como o Faturamento) × por VENDA. Esperado: por venda, entra ≤ 0,01 (dois
--          arredondamentos) e retido ≤ 0,005 (um arredondamento); o total diverge só por arredondamento.
with v as (
  select t.dia_aprovado dia, t.liquido from fin.vw_transacoes t
   where t.status in ('APPROVED','COMPLETE') and t.aprovado_em >= now() - interval '50 days' and t.aprovado_em <= now()
), pv as (
  select v.dia, count(*) n, sum(r.entra_rapido) entra, sum(r.retido) ret
    from v cross join lateral fin.recebimento(v.dia, v.liquido) r group by v.dia
), pd as (
  select v.dia, sum(v.liquido) l from v group by v.dia
)
select max(abs(pv.entra - r.entra_rapido) / pv.n) dif_entra_por_venda,
       max(abs(pv.ret - r.retido) / pv.n)         dif_retido_por_venda,
       sum(pv.entra) - sum(r.entra_rapido)        dif_total_entra,
       sum(pv.ret) - sum(r.retido)                dif_total_retido
  from pv join pd on pd.dia = pv.dia cross join lateral fin.recebimento(pd.dia, pd.l) r;

-- P-B2-DATA) Método de data: A = "1ª cobrança + (n−1) meses" (o escolhido) × B = "última paga + 1 mês".
--   (a) quanto os dois divergem por grupo;
select c.grupo, count(*) cobrancas, count(*) filter (where c.vencimento <> c.vencimento_b) difere,
       min(c.vencimento - c.vencimento_b) min_dias, max(c.vencimento - c.vencimento_b) max_dias,
       percentile_cont(0.5) within group (order by c.vencimento - c.vencimento_b) mediana_dias
  from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
 where c.situacao <> 'realizada' group by 1 order by 1;
--   (b) valor por grupo × semana (seg–dom cortada no mês, a partir de 24/09) pelo vencimento A e pelo B — comparar com a
--       aba "Carteira e Recorrências" da planilha (colunas "Data prevista da cobrança" × "Valor líquido").
with c as (
  select * from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') where situacao <> 'realizada'
), s as (
  select c.grupo, 'A' m, greatest(date_trunc('week', c.vencimento)::date, date_trunc('month', c.vencimento)::date, date '2026-09-24') sem, c.valor from c
  union all
  select c.grupo, 'B', greatest(date_trunc('week', c.vencimento_b)::date, date_trunc('month', c.vencimento_b)::date, date '2026-09-24'), c.valor from c
)
select s.grupo, s.sem, round(sum(s.valor) filter (where s.m = 'A'), 2) metodo_a, round(sum(s.valor) filter (where s.m = 'B'), 2) metodo_b
  from s group by 1, 2 order by 1, 2;

-- CONF-25/09) Posição de 25/09 × planilha. Esperado: bloco 1 ≈ R$ 120 mil até outubro; bloco 2 bruto ≈ R$ 263 mil
--   (planilha, sem fator: HM 96 mil · Diamante 84 mil · "Holding - Holding Masters" 66 mil · Aurum 13 mil · outras 4 mil).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
with l as (
  select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31') where situacao = 'a_receber'
)
select l.bloco, l.grupo,
       greatest(date_trunc('week', l.data_caixa)::date, date_trunc('month', l.data_caixa)::date, date '2026-09-24') semana,
       round(sum(l.valor), 2) caixa
  from l group by rollup (1, 2, 3) order by 1, 2, 3;
rollback;
select c.grupo, c.situacao, count(*) cobrancas, count(distinct c.ref) contratos, round(sum(c.valor), 2) bruto
  from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
 group by rollup (1, 2) order by 1, 2;

-- P-B2-UNIQ) UNIQUE_PAYMENT com recorrência (5064314, 3094405): o que são? Decisão da z61: NÃO criam contrato; só contam
--            como pagamento de contrato que existe em modo recorrente. Se "com_contrato_recorrente" = 0, não afetam nada.
select t.produto_id, t.oferta_codigo, t.recorrencia, t.parcelas, t.tipo_pagamento, count(*) n,
       count(*) filter (where exists (select 1 from fin.hotmart_transacoes o
                                        where lower(trim(o.comprador_email)) = lower(trim(t.comprador_email))
                                          and o.oferta_codigo = t.oferta_codigo and o.recorrencia is not null
                                          and o.oferta_modo <> 'UNIQUE_PAYMENT')) com_contrato_recorrente,
       min(t.aprovado_em)::date primeira, max(t.aprovado_em)::date ultima,
       string_agg(distinct coalesce(t.bruto_json #>> '{purchase,is_subscription}', '∅'), ',') is_subscription
  from fin.hotmart_transacoes t
 where t.oferta_modo = 'UNIQUE_PAYMENT' and t.recorrencia is not null and t.status in ('APPROVED','COMPLETE')
   and t.aprovado_em > now() - interval '120 days'
 group by 1, 2, 3, 4, 5 order by n desc;

-- P-B2-MP) MULTIPLE_PAYMENTS (Holding Mais): "parcelas" vem preenchido? Se vier nulo/1, o contrato não projeta nada
--          (buraco fica buraco) — avisar o Victor.
select t.produto_id, t.oferta_codigo, t.recorrencia, t.parcelas, t.status, count(*)
  from fin.hotmart_transacoes t where t.oferta_modo = 'MULTIPLE_PAYMENTS' group by 1, 2, 3, 4, 5 order by 1, 2, 3;

-- P-B2-VALOR) "valor = líquido da última paga": contratos cuja última paga é > 1,5× a mediana das anteriores (Hotmart
--             cobra meses atrasados numa tentativa só → projeção inflada). Esperado: poucos; listar para o Victor.
with x as (
  select lower(trim(t.comprador_email)) e, t.oferta_codigo o, t.aprovado_em, t.liquido_produtor l,
         row_number() over (partition by lower(trim(t.comprador_email)), t.oferta_codigo order by t.aprovado_em desc) rn
    from fin.hotmart_transacoes t
   where t.status in ('APPROVED','COMPLETE') and t.recorrencia is not null and t.oferta_modo = 'SUBSCRIPTION'
), u as (
  select x.e, x.o, x.l from x where x.rn = 1 and x.aprovado_em > now() - interval '120 days'
), m as (
  select x.e, x.o, percentile_cont(0.5) within group (order by x.l) med from x where x.rn between 2 and 4 group by 1, 2
)
select u.o oferta, count(*) contratos, count(*) filter (where u.l > 1.5 * m.med) inflados
  from u join m on m.e = u.e and m.o = u.o
 group by 1 order by 3 desc;

-- P-B2-GRUPOS) Produto → grupo (conferir que Aurum parcelado caiu em "Parcelas a vencer Aurum" e Holding Mais em "outros").
select c.grupo, c.tipo, c.produto, count(distinct c.ref) contratos, count(*) cobrancas
  from fin.cobrancas_previstas(now(), (date_trunc('month', current_date) + interval '4 months' - interval '1 day')::date) c
 group by 1, 2, 3 order by 1, 3;
*/
