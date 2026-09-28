-- 20260928z68 — Contas a Receber / Faturamento, fatia F6: Caixa Hotmart por dia + vigência real da antecipação
--               (decisão do coordenador, 28/09, delegada pelo Marcio) + carga de feriados bancários 2028–2030.
--
-- NÃO APLICADA — coordenador aplica.
--
-- Por quê (3 coisas nesta migration, todas em fin.premissas_recebimento / fin.recebimento — SEM MUDAR O CORPO da
-- função, só o dado que ela lê):
--   1) A antecipação (90% − 3,89% em D+2 útil) vale DESDE 01/06/2026, como a aba "Faturamento Diário" da planilha
--      (ela só começa a coluna de antecipação em 01/06). Antes disso: SEM antecipação — o líquido inteiro é
--      RETIDO e cai inteiro no 1º dia útil ≥ D+30 (custo 0). A BLOQUEIO 1 do catálogo ("vale para todo o
--      histórico") foi a decisão do Marcio de 28/09; esta é a correção do coordenador na mesma data — registrada
--      como decisão nova, não como erro do Marcio.
--   2) fin.feriados_bancarios só tinha 2021–2027 (a planilha não vai além). O horizonte da previsão (corte + 400
--      dias) passa de 2028 a partir de dezembro/2026 — sem os feriados de 2028+ o calendário marca essas datas
--      como úteis por omissão (fin.recalcular_calendario_caixa trata "sem feriado cadastrado" = dia útil).
--      fin.calendario_caixa (z60) já cobre 2015–2036 — NENHUM ajuste de intervalo é necessário, só o dado.
--   3) public.fn_fin_caixa_hotmart(inicio, fim) — nova, só leitura, por DIA de aprovação: quanto já caiu (D+2),
--      quanto está retido, quanto custou antecipar, situação de cada um contra hoje. É o dado da sub-aba
--      "Faturamento · Caixa Hotmart" (F6). fn_fin_caixa_hotmart_totais — função irmã, 1 linha com os totais do
--      período (R22 do catálogo: "Resumo da antecipação").
--
-- Como a vigência é escolhida (fin.recebimento, z54/z60): "order by vigente_de desc limit 1" entre as linhas com
-- vigente_de <= dia da venda. Isso significa que uma vigência NOVA só muda o resultado de datas >= o seu próprio
-- vigente_de — não dá para uma linha nova mudar o passado ANTES dela. Por isso a linha "sem antecipação" desta
-- migration não fica em 2000-01-01 (a linha existente, que NUNCA é editada nem apagada): fica em 2015-01-01 (o
-- início do calendário de caixa da z60 — antes disso não há transação real). Ela passa a ser a vigência que
-- vence para qualquer venda entre 2015-01-01 e 2026-05-31; a segunda linha nova (2026-06-01) volta a valer a
-- fórmula de antecipação (MESMOS parâmetros 3,89%/10%/D+2/D+30 da linha original) a partir dali. A linha de
-- 2000-01-01 fica órfã (nenhuma venda real tem data anterior a 2015), preservada por decisão ("nunca
-- apagar/editar a existente"), sem efeito prático.
--
-- fin.recebimento (corpo) NÃO MUDA — só o dado de fin.premissas_recebimento. Guarda abaixo confere que o corpo
-- vivo ainda é o da z60 (mesma seleção "última vigente_de <= dia") antes de inserir as linhas novas.
--
-- REVERSÃO (uma transação; as duas linhas são deste arquivo, nunca a de 2000-01-01):
--   Desligar sem reverter de vez (mesmas duas linhas, comportamento fica NULO em vez de recuar ao 2000-01-01 —
--   fin.recebimento devolve ZERO linhas quando a vigência escolhida tem ativa=false, não cai para a anterior):
--     update fin.premissas_recebimento set ativa = false where vigente_de in (date '2015-01-01', date '2026-06-01');
--   Reverter de verdade (volta ao comportamento de antes desta migration: antecipação para todo o histórico):
--   begin;
--   delete from fin.premissas_recebimento where vigente_de in (date '2015-01-01', date '2026-06-01');
--   drop function public.fn_fin_caixa_hotmart(date, date);
--   drop function public.fn_fin_caixa_hotmart_totais(date, date);
--   delete from fin.feriados_bancarios where dia >= date '2028-01-01';  -- dispara o trigger, recalcula o calendário
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_oid oid := to_regprocedure('fin.recebimento(date,numeric)');
  v_src text;
  v_res text;
  e_rec text := $esperado$
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
$esperado$;
  e_res text := 'TABLE(entra_rapido numeric, retido numeric, custo_antecipacao numeric, liquido_total numeric, '
             || 'entra_em date, libera_em date)';
begin
  if v_oid is null then
    raise exception 'z68: fin.recebimento(date,numeric) não existe — a z54/z60 foram aplicadas?';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_oid;
  if regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(e_rec, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z68: corpo vivo de fin.recebimento diverge da z60. Alterado fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;
  if to_regclass('fin.feriados_bancarios') is null or to_regclass('fin.calendario_caixa') is null then
    raise exception 'z68: fin.feriados_bancarios ou fin.calendario_caixa não existe — a z60 foi aplicada?';
  end if;
  if to_regprocedure('public.gp_pode_ver_financeiro()') is null then
    raise exception 'z68: public.gp_pode_ver_financeiro() não existe';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'fin' and tablename = 'hotmart_transacoes'
                   and indexname = 'hotmart_transacoes_aprovado_pago_idx') then
    raise exception 'z68: hotmart_transacoes_aprovado_pago_idx não existe — a z61 foi aplicada?';
  end if;
  -- idempotência: as duas vigências novas ainda não existem
  if exists (select 1 from fin.premissas_recebimento where vigente_de in (date '2015-01-01', date '2026-06-01')) then
    raise exception 'z68: já existe vigência em 2015-01-01 ou 2026-06-01 — z68 já aplicada?';
  end if;
  -- idempotência: feriados de 2028+ ainda não carregados
  if exists (select 1 from fin.feriados_bancarios where dia >= date '2028-01-01') then
    raise exception 'z68: já existe feriado a partir de 2028 — z68 já aplicada?';
  end if;
  if (select count(*) from fin.feriados_bancarios) <> 88 then
    raise exception 'z68: esperava 88 feriados antes da carga, há %', (select count(*) from fin.feriados_bancarios);
  end if;
  -- idempotência: as RPCs novas ainda não existem
  if to_regprocedure('public.fn_fin_caixa_hotmart(date,date)') is not null
     or to_regprocedure('public.fn_fin_caixa_hotmart_totais(date,date)') is not null then
    raise exception 'z68: fn_fin_caixa_hotmart ou fn_fin_caixa_hotmart_totais já existe — z68 já aplicada?';
  end if;
end $guarda$;


-- ─── 1. Vigência real da antecipação (nunca apaga/edita a linha de 2000-01-01) ────────────────────────────────────────
-- Sem antecipação até 31/05/2026: pct_retido=100% zera a base antecipável (entra_rapido = 0 sempre) e
-- taxa_antecipacao=0 zera o custo; o líquido inteiro vira "retido" e só libera em WORKDAY(dia+29, 1) = D+30 útil.
insert into fin.premissas_recebimento
  (vigente_de, taxa_antecipacao, pct_retido, dias_ate_entrar, dias_retencao, ativa, fonte)
values
  (date '2015-01-01', 0.00000, 1.0000, 2, 30, true,
   'coordenador 28/09/2026 (decisão delegada pelo Marcio): sem antecipação antes de 01/06/2026 — líquido inteiro no 1º dia útil ≥ D+30, custo 0'),
  (date '2026-06-01', 0.03890, 0.1000, 2, 30, true,
   'coordenador 28/09/2026 (decisão delegada pelo Marcio): antecipação vigente desde 01/06/2026, como a aba Faturamento Diário da planilha — mesmos parâmetros da linha de 2000-01-01 (Marcio 28/09/2026)')
on conflict (vigente_de) do nothing;


-- ─── 2. Feriados bancários 2028–2030 (o trigger recalcula fin.calendario_caixa ao fim do INSERT) ──────────────────────
-- Mesma fonte/convenção da carga 2021–2027 (z60): fixos nacionais + móveis pela Páscoa (algoritmo Meeus/Butcher,
-- Carnaval = Páscoa −48/−47, Sexta Santa = Páscoa −2, Corpus Christi = Páscoa +60 — conferido na seção 3 abaixo).
-- Fora do range da planilha (que só vai até 2027): calculado, não copiado de aba.
insert into fin.feriados_bancarios (dia, nome, fonte)
select v.dia::date, v.nome, 'nacional (Febraban) — calculado (Páscoa Meeus/Butcher); fora do range da planilha (só até 2027)'
  from (values
  ('2028-01-01','Confraternização Universal'),('2028-02-28','Carnaval (segunda)'),('2028-02-29','Carnaval (terça)'),
  ('2028-04-14','Sexta-feira Santa'),('2028-04-21','Tiradentes'),('2028-05-01','Dia do Trabalho'),
  ('2028-06-15','Corpus Christi'),('2028-09-07','Independência'),('2028-10-12','Nossa Senhora Aparecida'),
  ('2028-11-02','Finados'),('2028-11-15','Proclamação da República'),
  ('2028-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2028-12-25','Natal'),
  ('2029-01-01','Confraternização Universal'),('2029-02-12','Carnaval (segunda)'),('2029-02-13','Carnaval (terça)'),
  ('2029-03-30','Sexta-feira Santa'),('2029-04-21','Tiradentes'),('2029-05-01','Dia do Trabalho'),
  ('2029-05-31','Corpus Christi'),('2029-09-07','Independência'),('2029-10-12','Nossa Senhora Aparecida'),
  ('2029-11-02','Finados'),('2029-11-15','Proclamação da República'),
  ('2029-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2029-12-25','Natal'),
  ('2030-01-01','Confraternização Universal'),('2030-03-04','Carnaval (segunda)'),('2030-03-05','Carnaval (terça)'),
  ('2030-04-19','Sexta-feira Santa'),('2030-04-21','Tiradentes'),('2030-05-01','Dia do Trabalho'),
  ('2030-06-20','Corpus Christi'),('2030-09-07','Independência'),('2030-10-12','Nossa Senhora Aparecida'),
  ('2030-11-02','Finados'),('2030-11-15','Proclamação da República'),
  ('2030-11-20','Dia Nacional de Zumbi e da Consciência Negra'),('2030-12-25','Natal')
  ) v(dia, nome);


-- ─── 3. Caixa Hotmart por dia (só leitura; usa fin.recebimento por dia, não recalcula calendário) ─────────────────────
-- Filtro em t.status (não t.grupo): é o predicado LITERAL do índice parcial hotmart_transacoes_aprovado_pago_idx
-- (z61) — grupo='pago' é gerado da mesma condição dentro da view, mas um índice parcial só é usado se a query
-- repetir o predicado igual, caractere a caractere (ver protocolo de sustentabilidade). Range em t.aprovado_em
-- (coluna crua, timestamptz) — não em t.dia_aprovado (expressão) — pelo mesmo motivo; GROUP BY em dia_aprovado é
-- barato porque já roda só sobre as linhas que o índice filtrou.
create function public.fn_fin_caixa_hotmart(p_inicio date, p_fim date)
returns table (
  dia date, liquido numeric, retido numeric, custo_antecipacao numeric, entra_rapido numeric, entra_em date,
  retido_a_liberar numeric, libera_em date, situacao_d2 text, situacao_retido text, n_vendas int)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini_ts  timestamptz;
  v_fim_ts  timestamptz;
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
  with d as (
    select t.dia_aprovado dia, coalesce(sum(t.liquido), 0) liquido, count(*)::int n_vendas
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')   -- = grupo='pago'; literal p/ bater o índice parcial
       and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts
     group by t.dia_aprovado
  )
  select d.dia, d.liquido, r.retido, r.custo_antecipacao, r.entra_rapido, r.entra_em,
         case when r.libera_em > v_hoje then r.retido else 0 end,
         r.libera_em,
         case when r.entra_em <= v_hoje then 'recebido' else 'a_receber' end,
         case when r.libera_em <= v_hoje then 'liberado' else 'em_garantia' end,
         d.n_vendas
    from d
    left join lateral fin.recebimento(d.dia, d.liquido) r on true
   order by d.dia;
end $$;
comment on function public.fn_fin_caixa_hotmart(date, date) is
  'z68: Caixa Hotmart por dia de aprovação (só pago). situacao_d2/situacao_retido comparam entra_em/libera_em com hoje.';
revoke all on function public.fn_fin_caixa_hotmart(date, date) from public, anon;
grant execute on function public.fn_fin_caixa_hotmart(date, date) to authenticated;


-- ─── 4. Totais do período (função irmã — R22 do catálogo: "Resumo da antecipação") ─────────────────────────────────────
create function public.fn_fin_caixa_hotmart_totais(p_inicio date, p_fim date)
returns table (
  liquido numeric, retido numeric, custo_antecipacao numeric, entra_rapido numeric,
  retido_a_liberar numeric, liquido_total numeric, n_vendas int)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini_ts  timestamptz;
  v_fim_ts  timestamptz;
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
  with d as (
    select t.dia_aprovado dia, coalesce(sum(t.liquido), 0) liquido, count(*)::int n
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts
     group by t.dia_aprovado
  )
  select coalesce(sum(d.liquido), 0), coalesce(sum(r.retido), 0), coalesce(sum(r.custo_antecipacao), 0),
         coalesce(sum(r.entra_rapido), 0),
         coalesce(sum(case when r.libera_em > v_hoje then r.retido else 0 end), 0),
         coalesce(sum(r.liquido_total), 0),
         coalesce(sum(d.n), 0)::int
    from d
    left join lateral fin.recebimento(d.dia, d.liquido) r on true;
end $$;
comment on function public.fn_fin_caixa_hotmart_totais(date, date) is
  'z68: totais do período de fn_fin_caixa_hotmart (soma das linhas por dia) — R22 do catálogo.';
revoke all on function public.fn_fin_caixa_hotmart_totais(date, date) from public, anon;
grant execute on function public.fn_fin_caixa_hotmart_totais(date, date) to authenticated;


-- ─── 5. Conferência dentro da migration (falha → rollback de tudo) ────────────────────────────────────────────────────
do $chk$
declare
  r record;
  y int; a int; b int; c int; d int; e int; f int; g int; h int; i int; k int; l int; m int;
  v_pascoa date;
  v_ok boolean;
begin
  -- 5.1 vigência nova: sem antecipação antes de 01/06/2026 (aceite com líquido = 93,70, igual ao aceite da z54/z60)
  select * into r from fin.recebimento(date '2026-05-15', 93.70);
  if r.entra_rapido is distinct from 0 or r.retido is distinct from 93.70 or r.custo_antecipacao is distinct from 0
     or r.liquido_total is distinct from 93.70 then
    raise exception 'z68: sem antecipação (15/05/2026) falhou: %', row_to_json(r);
  end if;
  -- mesma checagem num dia com transação real desde sempre (2021) — cobre o histórico de verdade, não só a borda
  select * into r from fin.recebimento(date '2021-06-15', 93.70);
  if r.entra_rapido is distinct from 0 or r.retido is distinct from 93.70 or r.custo_antecipacao is distinct from 0 then
    raise exception 'z68: sem antecipação (15/06/2021) falhou: %', row_to_json(r);
  end if;
  -- dia antes da virada: ainda sem antecipação
  select * into r from fin.recebimento(date '2026-05-31', 93.70);
  if r.entra_rapido is distinct from 0 or r.retido is distinct from 93.70 then
    raise exception 'z68: véspera da virada (31/05/2026) falhou: %', row_to_json(r);
  end if;
  -- dia da virada (inclusive) e um dia depois: regra atual, MESMOS valores do aceite da z54/z60 (81.05/9.37/3.28/90.42)
  select * into r from fin.recebimento(date '2026-06-01', 93.70);
  if r.entra_rapido is distinct from 81.05 or r.retido is distinct from 9.37 or r.custo_antecipacao is distinct from 3.28
     or r.liquido_total is distinct from 90.42 then
    raise exception 'z68: virada (01/06/2026) falhou: %', row_to_json(r);
  end if;
  select * into r from fin.recebimento(date '2026-06-15', 93.70);
  if r.entra_rapido is distinct from 81.05 or r.retido is distinct from 9.37 or r.custo_antecipacao is distinct from 3.28
     or r.liquido_total is distinct from 90.42 then
    raise exception 'z68: 15/06/2026 (regra atual) falhou: %', row_to_json(r);
  end if;
  -- a linha de 2000-01-01 continua intacta (não editada, não apagada)
  if not exists (select 1 from fin.premissas_recebimento
                  where vigente_de = date '2000-01-01' and taxa_antecipacao = 0.0389 and pct_retido = 0.10
                    and dias_ate_entrar = 2 and dias_retencao = 30 and ativa and fonte = 'Marcio 28/09/2026') then
    raise exception 'z68: a linha de 2000-01-01 foi alterada — não deveria';
  end if;
  if (select count(*) from fin.premissas_recebimento) <> 3 then
    raise exception 'z68: esperava 3 linhas em fin.premissas_recebimento, há %',
      (select count(*) from fin.premissas_recebimento);
  end if;

  -- 5.2 feriados: 88 + 39 = 127; calendário sem mudar de tamanho (só o "util" das datas novas)
  if (select count(*) from fin.feriados_bancarios) <> 127 then
    raise exception 'z68: esperava 127 feriados, há %', (select count(*) from fin.feriados_bancarios);
  end if;
  if (select count(*) from fin.calendario_caixa) <> 8036 then
    raise exception 'z68: calendário com % dias (esperado 8036 — mesmo intervalo da z60)',
      (select count(*) from fin.calendario_caixa);
  end if;
  if (select max(dia) from fin.calendario_caixa) < date '2030-12-31' then
    raise exception 'z68: calendário não cobre até 2030';
  end if;
  if exists (select 1 from fin.calendario_caixa x join fin.feriados_bancarios fb on fb.dia = x.dia
              where x.util and fb.dia >= date '2028-01-01')
     or exists (select 1 from fin.calendario_caixa x where x.util and extract(isodow from x.dia) >= 6
                 and x.dia >= date '2028-01-01' and x.dia <= date '2030-12-31') then
    raise exception 'z68: feriado ou fim de semana de 2028–2030 marcado como útil';
  end if;

  -- 5.3 datas móveis 2028–2030 = algoritmo da Páscoa (Meeus/Butcher), mesma fórmula validada pela z60
  for y in 2028..2030 loop
    a := y % 19; b := y / 100; c := y % 100; d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
    h := (19 * a + b - d - g + 15) % 30; i := c / 4; k := c % 4; l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;
    v_pascoa := make_date(y, (h + l - 7 * m + 114) / 31, ((h + l - 7 * m + 114) % 31) + 1);
    if (select count(*) from fin.feriados_bancarios
         where dia in (v_pascoa - 48, v_pascoa - 47, v_pascoa - 2, v_pascoa + 60)) <> 4 then
      raise exception 'z68: datas móveis de % não batem com a Páscoa %', y, v_pascoa;
    end if;
  end loop;

  -- 5.4 fn_fin_caixa_hotmart: soma do período = soma das linhas (contra fn_fin_caixa_hotmart_totais), sem sessão → 42501
  v_ok := false;
  begin
    perform * from public.fn_fin_caixa_hotmart(current_date - 30, current_date);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z68: fn_fin_caixa_hotmart aceitou chamada sem sessão'; end if;
  v_ok := false;
  begin
    perform * from public.fn_fin_caixa_hotmart_totais(current_date - 30, current_date);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'z68: fn_fin_caixa_hotmart_totais aceitou chamada sem sessão'; end if;
  -- a guarda de janela (> 400 dias) roda DEPOIS da guarda de sessão dentro da função: sob "postgres" (sem
  -- request.jwt.claims) qualquer chamada já cai em 42501 antes de chegar lá. Provar o 22023 exige sessão real
  -- (JWT do Financeiro) — fica no bloco de PROVAS (P2), não aqui.

  -- 5.5 grants: nada aberto a public/anon
  if has_function_privilege('anon', 'public.fn_fin_caixa_hotmart(date,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_caixa_hotmart_totais(date,date)', 'execute') then
    raise exception 'z68: grant aberto demais para anon';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_caixa_hotmart(date,date)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_caixa_hotmart_totais(date,date)', 'execute') then
    raise exception 'z68: authenticated sem execute nas RPCs novas';
  end if;
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) ac
              where p.oid in ('public.fn_fin_caixa_hotmart(date,date)'::regprocedure,
                              'public.fn_fin_caixa_hotmart_totais(date,date)'::regprocedure)
                and ac::text like '=%') then
    raise exception 'z68: função com EXECUTE para PUBLIC';
  end if;

  -- 5.6 fin.recebimento não mudou (mesmos atributos da z60: sql/stable/sem definer/sem set/parallel safe)
  if not exists (select 1 from pg_proc p join pg_language lg on lg.oid = p.prolang
                  where p.oid = 'fin.recebimento(date,numeric)'::regprocedure and lg.lanname = 'sql'
                    and p.provolatile = 's' and not p.prosecdef and p.proconfig is null and p.proparallel = 's') then
    raise exception 'z68: fin.recebimento mudou de atributos — não deveria (esta migration só insere dado)';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres ou com JWT de um usuário do Financeiro; tudo leitura) ════════════
/*
-- P1) Venda de 15/05/2026 → entra 0 em D+2, tudo no D+30 útil. Venda de 15/06/2026 → regra atual (81,05/9,37/3,28/90,42).
select * from fin.recebimento(date '2026-05-15', 93.70);
select * from fin.recebimento(date '2026-06-15', 93.70);

-- P2) fn_fin_caixa_hotmart × fn_fin_caixa_hotmart_totais — soma das linhas = totais (diferença 0 em cada coluna).
--     Trocar <UUID_FINANCEIRO> por um perfis.id ativo com acesso ao financeiro.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
with l as (
  select sum(liquido) liquido, sum(retido) retido, sum(custo_antecipacao) custo, sum(entra_rapido) entra,
         sum(retido_a_liberar) a_liberar, count(*) dias, sum(n_vendas) n_vendas
    from public.fn_fin_caixa_hotmart('2026-06-01', current_date)
), t as (
  select liquido, retido, custo_antecipacao custo, entra_rapido entra, retido_a_liberar a_liberar, n_vendas
    from public.fn_fin_caixa_hotmart_totais('2026-06-01', current_date)
)
select l.liquido - t.liquido dif_liquido, l.retido - t.retido dif_retido, l.custo - t.custo dif_custo,
       l.entra - t.entra dif_entra, l.a_liberar - t.a_liberar dif_a_liberar, l.n_vendas - t.n_vendas dif_n_vendas
  from l, t;
-- janela > 400 dias com sessão real: esperado 22023
select * from public.fn_fin_caixa_hotmart(current_date - 401, current_date);
rollback;

-- P3) Totais desde jun/2026 (referência da planilha: custo de antecipação ≈ R$ 136 mil; retido a receber ≈ R$ 84 mil;
--     já liberado ≈ R$ 305 mil — "já liberado" = liquido_total − retido_a_liberar).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select liquido, retido, custo_antecipacao, entra_rapido, retido_a_liberar, liquido_total,
       liquido_total - retido_a_liberar ja_liberado, n_vendas
  from public.fn_fin_caixa_hotmart_totais('2026-06-01', current_date);
rollback;

-- P4) Faturamento INALTERADO ao centavo para vendas ≥ 01/06/2026 — foto ANTES de aplicar esta migration (rodar e
--     salvar o resultado), depois repetir o MESMO select DEPOIS de aplicar. Tem que bater linha a linha.
select dia, liquido, entra_rapido, retido, retido_a_liberar, custo_antecipacao, liquido_total
  from public.fn_fin_hotmart_faturamento('HM', date '2026-06-01', current_date)
 order by dia;
-- idem com 'HT' e com public.fn_fin_hotmart_funis('HM', date '2026-06-01', current_date)

-- P5) Grants vivos.
select p.oid::regprocedure, p.proacl from pg_proc p
 where p.oid in ('public.fn_fin_caixa_hotmart(date,date)'::regprocedure,
                 'public.fn_fin_caixa_hotmart_totais(date,date)'::regprocedure);

-- P6) 42501 vs PGRST205 pela anon key (confirma que a migration rodou E que não vazou para anon), via curl:
--   curl -s -X POST "$URL/rest/v1/rpc/fn_fin_caixa_hotmart" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
--     -H "Content-Type: application/json" -d '{"p_inicio":"2026-06-01","p_fim":"2026-06-30"}'
--   esperado: {"code":"42501", ...} (existe e está fechada para anon)

-- ═══ DESEMPENHO — explain (analyze, buffers). Meta: ≤ 300 ms para 12 meses. Rodar 2× (1ª é cache frio, usar a 2ª). ═══
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_caixa_hotmart(current_date - 364, current_date);
-- conferir no plano: Index Scan/Bitmap em hotmart_transacoes_aprovado_pago_idx (nunca Seq Scan em fin.hotmart_transacoes)
explain (analyze, buffers) select * from public.fn_fin_caixa_hotmart_totais(current_date - 364, current_date);
rollback;
*/
