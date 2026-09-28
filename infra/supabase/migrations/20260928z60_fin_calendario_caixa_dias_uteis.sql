-- 20260928z60 — Contas a Receber, fatia 1: calendário de caixa em DIAS ÚTEIS com feriados bancários.
--
-- NÃO APLICADA — coordenador aplica (o Victor não tem ferramenta de banco; nada aqui foi executado nem medido).
--
-- Por quê: a planilha do financeiro ("Contas a Receber Semanal", aba Premissas) usa D+2 em dias ÚTEIS (WORKDAY com
-- feriados) para os 90% antecipados e "1º dia útil a partir de D+30" para os 10% retidos. A z54 usava dias CORRIDOS.
--
-- O que muda:
--   1) fin.feriados_bancarios — lista editável (nunca se apaga: ativo=false desliga). Carga 2021–2027, nacionais.
--   2) fin.calendario_caixa — 2015-01-01 a 2036-12-31: util + n_util (nº acumulado de dias úteis; dia não útil
--      repete o do último útil). Recalculado por fin.recalcular_calendario_caixa() a cada mudança em feriados
--      (trigger AFTER STATEMENT; delete+insert, nunca truncate — truncate travaria a leitura do Faturamento).
--   3) fin.premissas_recebimento.dias_uteis — kill-switch próprio: false volta às datas corridas da z54, sem deploy.
--   4) fin.recebimento — MESMA assinatura, MESMO RETURNS TABLE; muda só entra_em/libera_em quando dias_uteis:
--        entra_em  = dia útil com n_util = n_util(dia) + dias_ate_entrar                  (= WORKDAY(dia, 2))
--        libera_em = dia útil com n_util = n_util(dia + dias_retencao − 1) + 1           (= WORKDAY(dia + 29, 1))
--      Fora do calendário (antes de 2015 / depois de 2036): cai nas datas corridas da z54 (nunca null por falta de
--      calendário). Valores (entra/retido/custo/total) NÃO mudam. No Faturamento só muda "retido_a_liberar" (depende de
--      libera_em > hoje). Continua SQL, STABLE, sem SECURITY DEFINER, SEM "set", nomes qualificados, PARALLEL SAFE
--      (as condições do inline; sem parallel safe o Faturamento ficou +57% na z54).
--   5) public.fn_fin_feriado_salvar(dia, nome, ativo) — única porta de escrita (quem OPERA o financeiro).
--
-- Lista carregada (88 datas; móveis calculadas pela Páscoa: Carnaval = Páscoa −48/−47, Sexta Santa = −2,
-- Corpus Christi = +60 — conferidas contra o algoritmo de Páscoa na seção 6):
--   fixos todo ano: 01/01 · 21/04 · 01/05 · 07/09 · 12/10 · 02/11 · 15/11 · 25/12 · 20/11 (a partir de 2024)
--   2021: Carnaval 15–16/02 · Sexta Santa 02/04 · Corpus Christi 03/06
--   2022: Carnaval 28/02–01/03 · Sexta Santa 15/04 · Corpus Christi 16/06
--   2023: Carnaval 20–21/02 · Sexta Santa 07/04 · Corpus Christi 08/06
--   2024: Carnaval 12–13/02 · Sexta Santa 29/03 · Corpus Christi 30/05
--   2025: Carnaval 03–04/03 · Sexta Santa 18/04 · Corpus Christi 19/06
--   2026: Carnaval 16–17/02 · Sexta Santa 03/04 · Corpus Christi 04/06
--   2027: Carnaval 08–09/02 · Sexta Santa 26/03 · Corpus Christi 27/05
--   (2015–2020 e 2028–2036: só fim de semana até alguém cadastrar os feriados pela RPC.)
--
-- Guarda: fin.recebimento só é trocada se o corpo VIVO (sem comentários "--" e sem espaços) for igual ao da z54 e os
-- atributos forem os da z54 (sql, stable, sem definer, sem set, parallel safe). Divergiu → exception, nada aplicado.
--
-- REVERSÃO
--   Desligar sem reverter (volta às datas corridas):  update fin.premissas_recebimento set dias_uteis = false;
--   Reverter de verdade (uma transação):
--   begin;
--   -- recriar fin.recebimento com o corpo da z54 (20260928z54 linhas 192–209), depois:
--   revoke all on function fin.recebimento(date, numeric) from public, anon, authenticated;
--   alter function fin.recebimento(date, numeric) parallel safe;
--   drop function public.fn_fin_feriado_salvar(date, text, boolean);
--   alter table fin.premissas_recebimento rename column dias_uteis to dias_uteis_arquivada_z60;  -- não apagar
--   drop trigger feriados_recalcula on fin.feriados_bancarios;
--   alter table fin.feriados_bancarios rename to feriados_bancarios_arquivada_z60;
--   alter table fin.calendario_caixa rename to calendario_caixa_arquivada_z60;
--   commit;


-- ─── 0. Guarda: fin.recebimento vivo = corpo da z54 ──────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_oid oid := to_regprocedure('fin.recebimento(date,numeric)');
  v_src text;
  v_res text;
  e_rec text := $esperado$
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
$esperado$;
  e_res text := 'TABLE(entra_rapido numeric, retido numeric, custo_antecipacao numeric, liquido_total numeric, '
             || 'entra_em date, libera_em date)';
begin
  if v_oid is null then
    raise exception 'z60: fin.recebimento(date,numeric) não existe — a z54 foi aplicada?';
  end if;
  if (select count(*) from pg_proc where proname = 'recebimento' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z60: há sobrecarga viva de fin.recebimento — conferir pg_get_function_arguments';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_oid;
  if regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(e_rec, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z60: corpo vivo de fin.recebimento diverge da z54. Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_oid and l.lanname = 'sql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig is null and p.proparallel = 's') then
    raise exception 'z60: atributos vivos de fin.recebimento diferentes da z54 (sql/stable/sem definer/sem set/parallel safe)';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'fin' and table_name = 'premissas_recebimento' and column_name = 'dias_uteis') then
    raise exception 'z60: fin.premissas_recebimento.dias_uteis já existe — z60 já aplicada?';
  end if;
  if to_regclass('fin.feriados_bancarios') is not null or to_regclass('fin.calendario_caixa') is not null then
    raise exception 'z60: fin.feriados_bancarios ou fin.calendario_caixa já existe — z60 já aplicada?';
  end if;
end $guarda$;


-- ─── 1. Feriados bancários (editável, nunca apagado) ────────────────────────────────────────────────────────────────
create table fin.feriados_bancarios (
  dia             date primary key,
  nome            text not null check (btrim(nome) <> ''),
  ativo           boolean not null default true,
  fonte           text not null check (btrim(fonte) <> ''),
  criado_por      uuid,
  criado_em       timestamptz not null default now(),
  atualizado_por  uuid,
  atualizado_em   timestamptz
);
comment on table fin.feriados_bancarios is
  'Feriados bancários do calendário de caixa (z60). Não se apaga: ativo=false desliga. Escrita só por public.fn_fin_feriado_salvar.';
alter table fin.feriados_bancarios enable row level security;   -- sem policy: só o dono (funções SECURITY DEFINER)
revoke all on fin.feriados_bancarios from public, anon, authenticated;


-- ─── 2. Calendário de caixa ─────────────────────────────────────────────────────────────────────────────────────────
create table fin.calendario_caixa (
  dia     date primary key,
  util    boolean not null,
  n_util  int not null
);
comment on table fin.calendario_caixa is
  'Calendário de caixa (z60), 2015–2036. n_util = nº acumulado de dias úteis; dia não útil repete o do último útil. '
  'Derivado de fin.feriados_bancarios por fin.recalcular_calendario_caixa() — não editar à mão.';
create unique index calendario_caixa_n_util_uidx on fin.calendario_caixa (n_util) where util;
alter table fin.calendario_caixa enable row level security;
revoke all on fin.calendario_caixa from public, anon, authenticated;

create function fin.recalcular_calendario_caixa()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  -- EXCLUSIVE: serializa dois recálculos simultâneos (senão o 2º insert bate na PK) sem bloquear a LEITURA
  -- (SELECT pega ACCESS SHARE, que EXCLUSIVE não barra). Quem lê vê o calendário antigo até o commit.
  lock table fin.calendario_caixa in exclusive mode;
  delete from fin.calendario_caixa where true;
  insert into fin.calendario_caixa (dia, util, n_util)
  select g.dia, g.util, (sum(g.util::int) over (order by g.dia))::int
    from (select s::date dia,
                 extract(isodow from s) < 6
                 and not exists (select 1 from fin.feriados_bancarios f where f.dia = s::date and f.ativo) util
            from generate_series(timestamp '2015-01-01', timestamp '2036-12-31', interval '1 day') s) g;
end $$;
revoke all on function fin.recalcular_calendario_caixa() from public, anon, authenticated;

create function fin.tg_feriados_recalcular()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform fin.recalcular_calendario_caixa();
  return null;
end $$;
revoke all on function fin.tg_feriados_recalcular() from public, anon, authenticated;

create function fin.tg_feriados_nao_apaga()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  raise exception 'Feriado bancário não se apaga: use ativo = false (fn_fin_feriado_salvar).' using errcode = '42501';
end $$;
revoke all on function fin.tg_feriados_nao_apaga() from public, anon, authenticated;

create trigger feriados_nao_apaga before delete on fin.feriados_bancarios
  for each row execute function fin.tg_feriados_nao_apaga();
create trigger feriados_nao_trunca before truncate on fin.feriados_bancarios
  for each statement execute function fin.tg_feriados_nao_apaga();
create trigger feriados_recalcula after insert or update on fin.feriados_bancarios
  for each statement execute function fin.tg_feriados_recalcular();


-- ─── 1b. Carga 2021–2027 (o trigger recalcula o calendário ao fim do INSERT) ────────────────────────────────────────
insert into fin.feriados_bancarios (dia, nome, fonte)
select v.dia::date, v.nome, 'nacional (Febraban) — conferir com aba Faturamento Diário da planilha 1'
  from (values
  ('2021-01-01','Confraternização Universal'),('2021-02-15','Carnaval (segunda)'),('2021-02-16','Carnaval (terça)'),
  ('2021-04-02','Sexta-feira Santa'),('2021-04-21','Tiradentes'),('2021-05-01','Dia do Trabalho'),
  ('2021-06-03','Corpus Christi'),('2021-09-07','Independência'),('2021-10-12','Nossa Senhora Aparecida'),
  ('2021-11-02','Finados'),('2021-11-15','Proclamação da República'),('2021-12-25','Natal'),
  ('2022-01-01','Confraternização Universal'),('2022-02-28','Carnaval (segunda)'),('2022-03-01','Carnaval (terça)'),
  ('2022-04-15','Sexta-feira Santa'),('2022-04-21','Tiradentes'),('2022-05-01','Dia do Trabalho'),
  ('2022-06-16','Corpus Christi'),('2022-09-07','Independência'),('2022-10-12','Nossa Senhora Aparecida'),
  ('2022-11-02','Finados'),('2022-11-15','Proclamação da República'),('2022-12-25','Natal'),
  ('2023-01-01','Confraternização Universal'),('2023-02-20','Carnaval (segunda)'),('2023-02-21','Carnaval (terça)'),
  ('2023-04-07','Sexta-feira Santa'),('2023-04-21','Tiradentes'),('2023-05-01','Dia do Trabalho'),
  ('2023-06-08','Corpus Christi'),('2023-09-07','Independência'),('2023-10-12','Nossa Senhora Aparecida'),
  ('2023-11-02','Finados'),('2023-11-15','Proclamação da República'),('2023-12-25','Natal'),
  ('2024-01-01','Confraternização Universal'),('2024-02-12','Carnaval (segunda)'),('2024-02-13','Carnaval (terça)'),
  ('2024-03-29','Sexta-feira Santa'),('2024-04-21','Tiradentes'),('2024-05-01','Dia do Trabalho'),
  ('2024-05-30','Corpus Christi'),('2024-09-07','Independência'),('2024-10-12','Nossa Senhora Aparecida'),
  ('2024-11-02','Finados'),('2024-11-15','Proclamação da República'),
  ('2024-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2024-12-25','Natal'),
  ('2025-01-01','Confraternização Universal'),('2025-03-03','Carnaval (segunda)'),('2025-03-04','Carnaval (terça)'),
  ('2025-04-18','Sexta-feira Santa'),('2025-04-21','Tiradentes'),('2025-05-01','Dia do Trabalho'),
  ('2025-06-19','Corpus Christi'),('2025-09-07','Independência'),('2025-10-12','Nossa Senhora Aparecida'),
  ('2025-11-02','Finados'),('2025-11-15','Proclamação da República'),
  ('2025-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2025-12-25','Natal'),
  ('2026-01-01','Confraternização Universal'),('2026-02-16','Carnaval (segunda)'),('2026-02-17','Carnaval (terça)'),
  ('2026-04-03','Sexta-feira Santa'),('2026-04-21','Tiradentes'),('2026-05-01','Dia do Trabalho'),
  ('2026-06-04','Corpus Christi'),('2026-09-07','Independência'),('2026-10-12','Nossa Senhora Aparecida'),
  ('2026-11-02','Finados'),('2026-11-15','Proclamação da República'),
  ('2026-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2026-12-25','Natal'),
  ('2027-01-01','Confraternização Universal'),('2027-02-08','Carnaval (segunda)'),('2027-02-09','Carnaval (terça)'),
  ('2027-03-26','Sexta-feira Santa'),('2027-04-21','Tiradentes'),('2027-05-01','Dia do Trabalho'),
  ('2027-05-27','Corpus Christi'),('2027-09-07','Independência'),('2027-10-12','Nossa Senhora Aparecida'),
  ('2027-11-02','Finados'),('2027-11-15','Proclamação da República'),
  ('2027-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2027-12-25','Natal')
  ) v(dia, nome);


-- ─── 3. Kill-switch dos dias úteis ──────────────────────────────────────────────────────────────────────────────────
alter table fin.premissas_recebimento add column dias_uteis boolean not null default false;
comment on column fin.premissas_recebimento.dias_uteis is
  'z60: true = entra_em/libera_em em dias úteis (fin.calendario_caixa); false = dias corridos (z54).';
update fin.premissas_recebimento set dias_uteis = true where not dias_uteis;


-- ─── 4. A fórmula (fonte única) — só as duas datas mudam ────────────────────────────────────────────────────────────
-- Mesmas condições de inline da z54: SQL, STABLE, não STRICT, sem SECURITY DEFINER, SEM "set", nomes qualificados.
-- As buscas no calendário são subconsultas escalares pela PK (dia) e pelo índice único parcial (n_util) where util —
-- a subconsulta repete o predicado "util" literal. No ramo dias corridos o CASE não executa as buscas.
create or replace function fin.recebimento(p_dia date, p_liquido numeric)
returns table (entra_rapido numeric, retido numeric, custo_antecipacao numeric, liquido_total numeric,
               entra_em date, libera_em date)
language sql stable
as $$
  select c.antecipado - c.custo, c.ret, c.custo, c.antecipado - c.custo + c.ret,
         case when c.dias_uteis then
                coalesce((select e.dia from fin.calendario_caixa e
                           where e.util
                             and e.n_util = (select b.n_util from fin.calendario_caixa b where b.dia = p_dia)
                                            + c.dias_ate_entrar),
                         p_dia + c.dias_ate_entrar)
              else p_dia + c.dias_ate_entrar end,
         case when c.dias_uteis then
                coalesce((select e.dia from fin.calendario_caixa e
                           where e.util
                             and e.n_util = (select b.n_util from fin.calendario_caixa b
                                              where b.dia = p_dia + c.dias_retencao - 1) + 1),
                         p_dia + c.dias_retencao)
              else p_dia + c.dias_retencao end
    from (select r.ret, p_liquido - r.ret antecipado,
                 pg_catalog.round((p_liquido - r.ret) * r.taxa_antecipacao, 2) custo,
                 r.dias_ate_entrar, r.dias_retencao, r.dias_uteis
            from (select pg_catalog.round(p_liquido * pr.pct_retido, 2) ret, pr.taxa_antecipacao,
                         pr.dias_ate_entrar, pr.dias_retencao, pr.ativa, pr.dias_uteis
                    from fin.premissas_recebimento pr
                   where pr.vigente_de <= p_dia
                   order by pr.vigente_de desc
                   limit 1) r
           where r.ativa) c
$$;
comment on function fin.recebimento(date, numeric) is
  'Fonte única da fórmula do líquido realista (z54; datas em dias úteis desde a z60): retido = round(L×pct,2); '
  'custo = round((L−retido)×taxa,2); entra = L−retido−custo; entra_em = WORKDAY(dia, dias_ate_entrar); '
  'libera_em = WORKDAY(dia + dias_retencao − 1, 1).';
revoke all on function fin.recebimento(date, numeric) from public, anon, authenticated;
alter function fin.recebimento(date, numeric) parallel safe;


-- ─── 5. Porta de escrita dos feriados ───────────────────────────────────────────────────────────────────────────────
create function public.fn_fin_feriado_salvar(p_dia date, p_nome text, p_ativo boolean)
returns table (dia date, nome text, ativo boolean, fonte text)
language plpgsql security definer set search_path = ''
as $$
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
end $$;
revoke all on function public.fn_fin_feriado_salvar(date, text, boolean) from public, anon;
grant execute on function public.fn_fin_feriado_salvar(date, text, boolean) to authenticated;


-- ─── 6. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  r record;
  y int; a int; b int; c int; d int; e int; f int; g int; h int; i int; k int; l int; m int;
  v_pascoa date;
  v_ok boolean;
begin
  -- 6.1 tamanhos
  if (select count(*) from fin.feriados_bancarios) <> 88 then
    raise exception 'z60: esperava 88 feriados, há %', (select count(*) from fin.feriados_bancarios);
  end if;
  if (select count(*) from fin.calendario_caixa) <> 8036 then
    raise exception 'z60: calendário com % dias (esperado 8036)', (select count(*) from fin.calendario_caixa);
  end if;
  if exists (select 1 from fin.calendario_caixa x join fin.feriados_bancarios fb on fb.dia = x.dia where x.util)
     or exists (select 1 from fin.calendario_caixa x where x.util and extract(isodow from x.dia) >= 6) then
    raise exception 'z60: feriado ou fim de semana marcado como útil';
  end if;

  -- 6.2 datas móveis = algoritmo da Páscoa (Meeus/Butcher), 2021–2027
  for y in 2021..2027 loop
    a := y % 19; b := y / 100; c := y % 100; d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
    h := (19 * a + b - d - g + 15) % 30; i := c / 4; k := c % 4; l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;
    v_pascoa := make_date(y, (h + l - 7 * m + 114) / 31, ((h + l - 7 * m + 114) % 31) + 1);
    if (select count(*) from fin.feriados_bancarios
         where dia in (v_pascoa - 48, v_pascoa - 47, v_pascoa - 2, v_pascoa + 60)) <> 4 then
      raise exception 'z60: datas móveis de % não batem com a Páscoa %', y, v_pascoa;
    end if;
  end loop;

  -- 6.3 datas de caixa (planilha: WORKDAY(d,2) e WORKDAY(d+29,1))
  for r in select * from (values
      (date '2026-09-28', date '2026-09-30', date '2026-10-28'),   -- seg
      (date '2026-09-25', date '2026-09-29', date '2026-10-26'),   -- sex
      (date '2026-09-26', date '2026-09-29', date '2026-10-26'),   -- sáb
      (date '2026-10-09', date '2026-10-14', date '2026-11-09'),   -- sex, 12/10 no meio
      (date '2026-10-30', date '2026-11-04', date '2026-11-30'),   -- sex, 02/11 no meio
      (date '2026-11-18', date '2026-11-23', date '2026-12-18')    -- qua, 20/11 no meio
    ) v(dia, entra, libera) loop
    if (select x.entra_em from fin.recebimento(r.dia, 100) x) is distinct from r.entra
       or (select x.libera_em from fin.recebimento(r.dia, 100) x) is distinct from r.libera then
      raise exception 'z60: data de caixa errada para %: %', r.dia,
        (select row_to_json(x) from fin.recebimento(r.dia, 100) x);
    end if;
  end loop;

  -- 6.4 aceite da z54 (valores iguais; datas: 28/09 seg → 30/09 e 28/10, iguais às corridas)
  select * into r from fin.recebimento(date '2026-09-28', 93.70);
  if r.entra_rapido is distinct from 81.05 or r.retido is distinct from 9.37 or r.custo_antecipacao is distinct from 3.28
     or r.liquido_total is distinct from 90.42 or r.entra_em is distinct from date '2026-09-30'
     or r.libera_em is distinct from date '2026-10-28' then
    raise exception 'z60: aceite de fin.recebimento falhou: %', row_to_json(r);
  end if;
  if exists (select 1 from fin.recebimento(date '1999-12-31', 100)) then
    raise exception 'z60: fin.recebimento devolveu linha sem premissa vigente';
  end if;
  -- fora do calendário: datas corridas (nunca null)
  select * into r from fin.recebimento(date '2014-12-31', 100);
  if r.entra_em is distinct from date '2015-01-02' or r.libera_em is distinct from date '2015-01-30' then
    raise exception 'z60: fallback fora do calendário errado: %', row_to_json(r);
  end if;

  -- 6.5 recálculo: feriado novo muda a data; desfeito por subtransação
  begin
    insert into fin.feriados_bancarios (dia, nome, fonte) values (date '2026-09-29', 'teste z60', 'teste z60');
    if (select x.entra_em from fin.recebimento(date '2026-09-28', 100) x) is distinct from date '2026-10-01' then
      raise exception 'z60: recálculo do calendário não pegou o feriado novo';
    end if;
    update fin.feriados_bancarios set ativo = false where dia = date '2026-09-29';
    if (select x.entra_em from fin.recebimento(date '2026-09-28', 100) x) is distinct from date '2026-09-30' then
      raise exception 'z60: ativo=false não devolveu o dia útil';
    end if;
    raise exception using errcode = 'P0001', message = 'z60_desfaz_teste';
  exception when raise_exception then
    if sqlerrm <> 'z60_desfaz_teste' then raise; end if;
  end;
  if exists (select 1 from fin.feriados_bancarios where dia = date '2026-09-29')
     or (select x.entra_em from fin.recebimento(date '2026-09-28', 100) x) is distinct from date '2026-09-30' then
    raise exception 'z60: teste de recálculo não foi desfeito';
  end if;

  -- 6.6 exclusão barrada
  v_ok := false;
  begin
    delete from fin.feriados_bancarios where dia = date '2026-12-25';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok or not exists (select 1 from fin.feriados_bancarios where dia = date '2026-12-25') then
    raise exception 'z60: DELETE em fin.feriados_bancarios não foi barrado';
  end if;

  -- 6.7 RPC de escrita sem sessão → 42501
  v_ok := false;
  begin
    perform * from public.fn_fin_feriado_salvar(date '2026-12-24', 'teste', true);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok or exists (select 1 from fin.feriados_bancarios where dia = date '2026-12-24') then
    raise exception 'z60: fn_fin_feriado_salvar aceitou chamada sem sessão';
  end if;

  -- 6.8 fin.recebimento continua inlinável e parallel safe
  if not exists (select 1 from pg_proc p join pg_language lg on lg.oid = p.prolang
                  where p.oid = 'fin.recebimento(date,numeric)'::regprocedure and lg.lanname = 'sql'
                    and p.provolatile = 's' and not p.prosecdef and p.proconfig is null and p.proparallel = 's') then
    raise exception 'z60: fin.recebimento perdeu sql/stable/sem definer/sem set/parallel safe';
  end if;

  -- 6.9 grants: nada aberto a public/anon; internas fechadas também a authenticated; ACL sem entrada PUBLIC
  if has_table_privilege('anon', 'fin.feriados_bancarios', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.feriados_bancarios', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('anon', 'fin.calendario_caixa', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.calendario_caixa', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.premissas_recebimento', 'select,insert,update,delete,truncate,references,trigger')
     or has_function_privilege('anon', 'fin.recalcular_calendario_caixa()', 'execute')
     or has_function_privilege('authenticated', 'fin.recalcular_calendario_caixa()', 'execute')
     or has_function_privilege('authenticated', 'fin.tg_feriados_recalcular()', 'execute')
     or has_function_privilege('authenticated', 'fin.tg_feriados_nao_apaga()', 'execute')
     or has_function_privilege('anon', 'fin.recebimento(date,numeric)', 'execute')
     or has_function_privilege('authenticated', 'fin.recebimento(date,numeric)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_feriado_salvar(date,text,boolean)', 'execute') then
    raise exception 'z60: grant aberto demais (conferir relacl/proacl)';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_feriado_salvar(date,text,boolean)', 'execute') then
    raise exception 'z60: authenticated sem execute em fn_fin_feriado_salvar';
  end if;
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) ac
              where p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure,
                              'fin.tg_feriados_nao_apaga()'::regprocedure, 'fin.recebimento(date,numeric)'::regprocedure,
                              'public.fn_fin_feriado_salvar(date,text,boolean)'::regprocedure)
                and ac::text like '=%') then
    raise exception 'z60: função com EXECUTE para PUBLIC';
  end if;
  if exists (select 1 from pg_proc p where p.proacl is null
                and p.oid in ('fin.recalcular_calendario_caixa()'::regprocedure, 'fin.tg_feriados_recalcular()'::regprocedure,
                              'fin.tg_feriados_nao_apaga()'::regprocedure, 'public.fn_fin_feriado_salvar(date,text,boolean)'::regprocedure)) then
    raise exception 'z60: proacl nulo (= padrão, PUBLIC executa)';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar; tudo leitura salvo onde dito) ════════════════════════════════════════════════
/*
-- P1) Datas de caixa em outubro/novembro (conferir contra a aba "Faturamento Diário" da planilha 1, colunas
--     "Data do crédito D+2" e "Liberação garantia"). Esperado: igual linha a linha.
select d::date dia, r.entra_em, r.libera_em
  from generate_series(date '2026-09-21', date '2026-11-30', interval '1 day') d
  cross join lateral fin.recebimento(d::date, 100) r order by 1;

-- P2) Feriados carregados (88) e calendário (8036 dias; úteis por ano).
select extract(year from dia) ano, count(*) from fin.feriados_bancarios group by 1 order by 1;
select extract(year from dia) ano, count(*) filter (where util) uteis, count(*) dias from fin.calendario_caixa group by 1 order by 1;

-- P3) Faturamento: só retido_a_liberar muda (libera_em > hoje). Antes/depois do kill-switch, na MESMA transação.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select sum(liquido_total) total, sum(retido_a_liberar) a_liberar
  from public.fn_fin_hotmart_faturamento('HM', (now() at time zone 'America/Sao_Paulo')::date - 89, null);
rollback;
-- (repetir com "update fin.premissas_recebimento set dias_uteis = false;" antes do select, como postgres, em begin…rollback)

-- P4) Grants vivos.
select p.oid::regprocedure, p.proacl, p.proconfig, p.proparallel, p.prosecdef from pg_proc p
 where p.oid in ('fin.recebimento(date,numeric)'::regprocedure, 'fin.recalcular_calendario_caixa()'::regprocedure,
                 'public.fn_fin_feriado_salvar(date,text,boolean)'::regprocedure);
select relname, relacl, relrowsecurity from pg_class
 where oid in ('fin.feriados_bancarios'::regclass, 'fin.calendario_caixa'::regclass);

-- P5) RPC de escrita com usuário que OPERA o financeiro (escreve → begin…rollback na MESMA chamada).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_OPERA_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select * from public.fn_fin_feriado_salvar(date '2026-12-24', 'Véspera de Natal (teste)', true);  -- 1 linha
reset role;
select entra_em from fin.recebimento(date '2026-12-22', 100);  -- esperado 2026-12-28 (24 e 25 fora); sem o teste: 24/12
rollback;
-- e com usuário que só VÊ o financeiro: esperado 42501.

-- DESEMPENHO: ver a z61, prova E1 (Faturamento/Funis com o corpo novo; NÃO pode aparecer "Function Scan on recebimento").
*/
