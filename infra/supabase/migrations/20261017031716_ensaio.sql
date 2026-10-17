do $ensaio$
declare v jsonb;
begin
-- 1/3: mkt_trafego.plano_diario, a meta diária de verba e leads por plataforma e camada, e a carga do plano da Black.
-- Pedido do Desenvolvedor Full Stack (plano meta x realizado, 16/10/2026). Fonte da carga:
-- gp-operacoes/projetos/2026-10-black-friday/plano-diario-de-trafego.csv (161 linhas, R$ 365.837, 10.794 leads).
-- Padrão do schema: RLS ligada sem policy e sem grant; quem lê é RPC security definer.
set local lock_timeout = '3s';

create table mkt_trafego.plano_diario (
  id bigint generated always as identity primary key,
  projeto_id bigint not null references mkt.projetos(id) on delete restrict,
  dia date not null,
  plataforma text not null references mkt_trafego.plataformas(codigo) on delete restrict,
  camada text not null check (camada in ('c1', 'c2', 'c3', 'aquecimento', 'remarketing', 'remarketing_live', 'carrinho')),
  verba_meta_midia numeric(12, 2) not null check (verba_meta_midia >= 0),
  leads_meta integer not null check (leads_meta >= 0),
  origem text not null,
  criado_em timestamptz not null default now(),
  constraint plano_diario_uk unique (projeto_id, dia, plataforma, camada)
);
comment on table mkt_trafego.plano_diario is 'Meta diária de verba em mídia (sem imposto) e de leads por plataforma e camada do plano de tráfego. 20261017: Black (projeto 4).';
alter table mkt_trafego.plano_diario enable row level security;
revoke all on mkt_trafego.plano_diario from public, anon, authenticated;

do $c$
declare v_n int; v_verba numeric; v_leads int;
begin
  if not exists (select 1 from mkt.projetos where id = 4 and sigla = 'BF26') then
    raise exception 'premissa: projeto 4 não é a Black (BF26)';
  end if;
  insert into mkt_trafego.plano_diario (projeto_id, dia, plataforma, camada, verba_meta_midia, leads_meta, origem)
  select 4, v.dia, v.plataforma, v.camada, v.verba, v.leads, 'csv-plano-diario-de-trafego-2026-10-16'
    from (values
  ('2026-10-17'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-17'::date, 'google', 'c2', 276.0, 7),
  ('2026-10-17'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-17'::date, 'meta', 'aquecimento', 480.0, 0),
  ('2026-10-17'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-17'::date, 'meta', 'c2', 2569.0, 137),
  ('2026-10-17'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-17'::date, 'meta', 'remarketing', 389.0, 17),
  ('2026-10-18'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-18'::date, 'google', 'c2', 276.0, 7),
  ('2026-10-18'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-18'::date, 'meta', 'aquecimento', 480.0, 0),
  ('2026-10-18'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-18'::date, 'meta', 'c2', 2569.0, 137),
  ('2026-10-18'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-18'::date, 'meta', 'remarketing', 389.0, 17),
  ('2026-10-19'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-19'::date, 'google', 'c2', 276.0, 7),
  ('2026-10-19'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-19'::date, 'meta', 'aquecimento', 1000.0, 0),
  ('2026-10-19'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-19'::date, 'meta', 'c2', 2569.0, 137),
  ('2026-10-19'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-19'::date, 'meta', 'remarketing', 389.0, 17),
  ('2026-10-20'::date, 'google', 'aquecimento', 900.0, 0),
  ('2026-10-20'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-20'::date, 'google', 'c2', 497.0, 12),
  ('2026-10-20'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-20'::date, 'meta', 'aquecimento', 2000.0, 0),
  ('2026-10-20'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-20'::date, 'meta', 'c2', 4624.0, 247),
  ('2026-10-20'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-20'::date, 'meta', 'remarketing', 907.0, 41),
  ('2026-10-21'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-21'::date, 'google', 'c2', 497.0, 12),
  ('2026-10-21'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-21'::date, 'meta', 'aquecimento', 1000.0, 0),
  ('2026-10-21'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-21'::date, 'meta', 'c2', 4624.0, 247),
  ('2026-10-21'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-21'::date, 'meta', 'remarketing', 907.0, 41),
  ('2026-10-22'::date, 'google', 'aquecimento', 900.0, 0),
  ('2026-10-22'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-22'::date, 'google', 'c2', 497.0, 12),
  ('2026-10-22'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-22'::date, 'meta', 'aquecimento', 2000.0, 0),
  ('2026-10-22'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-22'::date, 'meta', 'c2', 4624.0, 247),
  ('2026-10-22'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-22'::date, 'meta', 'remarketing', 907.0, 41),
  ('2026-10-23'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-23'::date, 'google', 'c2', 497.0, 12),
  ('2026-10-23'::date, 'google', 'c3', 1777.0, 44),
  ('2026-10-23'::date, 'meta', 'aquecimento', 480.0, 0),
  ('2026-10-23'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-23'::date, 'meta', 'c2', 4624.0, 247),
  ('2026-10-23'::date, 'meta', 'c3', 5685.0, 182),
  ('2026-10-23'::date, 'meta', 'remarketing', 907.0, 41),
  ('2026-10-24'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-24'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-24'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-24'::date, 'meta', 'aquecimento', 480.0, 0),
  ('2026-10-24'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-24'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-24'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-24'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-25'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-25'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-25'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-25'::date, 'meta', 'aquecimento', 480.0, 0),
  ('2026-10-25'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-25'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-25'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-25'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-26'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-26'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-26'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-26'::date, 'meta', 'aquecimento', 1000.0, 0),
  ('2026-10-26'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-26'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-26'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-26'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-27'::date, 'google', 'aquecimento', 900.0, 0),
  ('2026-10-27'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-27'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-27'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-27'::date, 'meta', 'aquecimento', 2000.0, 0),
  ('2026-10-27'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-27'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-27'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-27'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-28'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-28'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-28'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-28'::date, 'meta', 'aquecimento', 1000.0, 0),
  ('2026-10-28'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-28'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-28'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-28'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-29'::date, 'google', 'aquecimento', 900.0, 0),
  ('2026-10-29'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-29'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-29'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-29'::date, 'meta', 'aquecimento', 2000.0, 0),
  ('2026-10-29'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-29'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-29'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-29'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-30'::date, 'google', 'aquecimento', 600.0, 0),
  ('2026-10-30'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-30'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-30'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-30'::date, 'meta', 'aquecimento', 900.0, 0),
  ('2026-10-30'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-30'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-30'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-30'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-10-31'::date, 'google', 'aquecimento', 600.0, 0),
  ('2026-10-31'::date, 'google', 'c1', 882.0, 0),
  ('2026-10-31'::date, 'google', 'c2', 691.0, 17),
  ('2026-10-31'::date, 'google', 'c3', 1954.0, 49),
  ('2026-10-31'::date, 'meta', 'aquecimento', 900.0, 0),
  ('2026-10-31'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-10-31'::date, 'meta', 'c2', 6423.0, 343),
  ('2026-10-31'::date, 'meta', 'c3', 6254.0, 200),
  ('2026-10-31'::date, 'meta', 'remarketing', 1554.0, 70),
  ('2026-11-01'::date, 'google', 'aquecimento', 600.0, 0),
  ('2026-11-01'::date, 'google', 'c1', 882.0, 0),
  ('2026-11-01'::date, 'google', 'c2', 552.0, 14),
  ('2026-11-01'::date, 'google', 'c3', 2310.0, 58),
  ('2026-11-01'::date, 'meta', 'aquecimento', 900.0, 0),
  ('2026-11-01'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-11-01'::date, 'meta', 'c2', 5138.0, 274),
  ('2026-11-01'::date, 'meta', 'c3', 7391.0, 237),
  ('2026-11-01'::date, 'meta', 'remarketing', 2591.0, 116),
  ('2026-11-02'::date, 'google', 'aquecimento', 600.0, 0),
  ('2026-11-02'::date, 'google', 'c1', 882.0, 0),
  ('2026-11-02'::date, 'google', 'c2', 552.0, 14),
  ('2026-11-02'::date, 'google', 'c3', 2310.0, 58),
  ('2026-11-02'::date, 'meta', 'aquecimento', 900.0, 0),
  ('2026-11-02'::date, 'meta', 'c1', 1471.0, 0),
  ('2026-11-02'::date, 'meta', 'c2', 5138.0, 274),
  ('2026-11-02'::date, 'meta', 'c3', 7391.0, 237),
  ('2026-11-02'::date, 'meta', 'remarketing', 2591.0, 116),
  ('2026-11-03'::date, 'google', 'c2', 552.0, 14),
  ('2026-11-03'::date, 'google', 'c3', 2310.0, 58),
  ('2026-11-03'::date, 'google', 'carrinho', 857.0, 0),
  ('2026-11-03'::date, 'google', 'remarketing_live', 800.0, 0),
  ('2026-11-03'::date, 'meta', 'c2', 5138.0, 274),
  ('2026-11-03'::date, 'meta', 'c3', 7391.0, 237),
  ('2026-11-03'::date, 'meta', 'carrinho', 4321.0, 0),
  ('2026-11-03'::date, 'meta', 'remarketing', 2591.0, 116),
  ('2026-11-03'::date, 'meta', 'remarketing_live', 2000.0, 0),
  ('2026-11-04'::date, 'google', 'carrinho', 857.0, 0),
  ('2026-11-04'::date, 'google', 'remarketing_live', 1200.0, 0),
  ('2026-11-04'::date, 'meta', 'carrinho', 4321.0, 0),
  ('2026-11-04'::date, 'meta', 'remarketing_live', 3500.0, 0),
  ('2026-11-05'::date, 'google', 'carrinho', 857.0, 0),
  ('2026-11-05'::date, 'google', 'remarketing_live', 1000.0, 0),
  ('2026-11-05'::date, 'meta', 'carrinho', 4321.0, 0),
  ('2026-11-05'::date, 'meta', 'remarketing_live', 2800.0, 0)
    ) v(dia, plataforma, camada, verba, leads);
  select count(*), sum(verba_meta_midia), sum(leads_meta) into v_n, v_verba, v_leads
    from mkt_trafego.plano_diario where projeto_id = 4;
  if v_n <> 161 or v_verba <> 365837 or v_leads <> 10794 then
    raise exception 'guarda: carga % linhas, R$ %, % leads (esperado 161, 365837, 10794)', v_n, v_verba, v_leads;
  end if;
end $c$;

-- 2/3: mkt_trafego.segmento_plano(plataforma, nome da campanha) -> camada do plano diário.
-- De-para do Maestro para a conta CNF Holding Familiar (16/10/2026). Os termos são lidos entre as barras do nome,
-- sem acento e em caixa alta, como na etapa_black. A primeira regra que casa vence, nesta ordem:
--   1. CARRINHO                                   -> carrinho
--   2. REMARKETING com LIVE no nome               -> remarketing_live
--   3. REMARKETING                                -> remarketing
--   4. ANTECIPACAO com PQ (teaser)                -> historico (fora do plano)
--   5. ANTECIPACAO com PF, CORTES, MANIFESTO(S)   -> c1
--   6. AQUECIMENTO, E HOJE, LIVE FAKE, FAKE LIVE  -> aquecimento
--   7. ISCA, ISCAS, CONSULTORIA                   -> c2
--   8. BASE, ENTRESAFRA ou o código C3            -> c3
--   9. o código C1 ou C2 sozinho                  -> c1 / c2
--   sem casamento                                 -> null (linha "sem segmento" no painel)
-- A plataforma não muda a regra hoje (o Google segue o mesmo padrão de nome); fica no contrato para o de-para do Google.
set local lock_timeout = '3s';

create function mkt_trafego.segmento_plano(p_plataforma text, p_nome_campanha text)
returns text
language sql
immutable parallel safe
set search_path to ''
as $f$
  with t as (
    select array_agg(upper(btrim(translate(u, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                              'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')))) as k
      from unnest(string_to_array(coalesce(p_nome_campanha, ''), '|')) u
  )
  select case
    when p_plataforma is null or p_nome_campanha is null then null
    when 'CARRINHO' = any(k) then 'carrinho'
    when 'REMARKETING' = any(k) and exists (select 1 from unnest(k) x where x like '%LIVE%') then 'remarketing_live'
    when 'REMARKETING' = any(k) then 'remarketing'
    when 'ANTECIPACAO' = any(k) and 'PQ' = any(k) then 'historico'
    when ('ANTECIPACAO' = any(k) and 'PF' = any(k)) or k && array['CORTES', 'MANIFESTO', 'MANIFESTOS'] then 'c1'
    when k && array['AQUECIMENTO', 'E HOJE', 'LIVE FAKE', 'FAKE LIVE'] then 'aquecimento'
    when k && array['ISCA', 'ISCAS', 'CONSULTORIA'] then 'c2'
    when k && array['BASE', 'ENTRESAFRA', 'C3'] then 'c3'
    when 'C1' = any(k) then 'c1'
    when 'C2' = any(k) then 'c2'
  end
  from t
$f$;
comment on function mkt_trafego.segmento_plano(text, text) is
  'Camada do plano diário (c1, c2, c3, aquecimento, remarketing, remarketing_live, carrinho, historico) pelo nome da campanha. De-para do Maestro, 16/10/2026. Null = sem segmento.';
revoke execute on function mkt_trafego.segmento_plano(text, text) from public, anon, authenticated;

-- 3/3: RPC public.dados_black_plano_diario(p_chave): meta contra realizado por dia, plataforma e camada (17/10 a 05/11).
-- Contrato combinado com o Desenvolvedor Full Stack (16/10/2026). Padrão dados_black_*: security definer, só equipe
-- (dados.black_evento -> dados.cadastro: 42501 sem acesso, P0002 fora da Black), execute só para authenticated.
-- Regras:
--   - campanhas: as mesmas do dados_black_trafego (projeto da Black, ou sem projeto com a sigla BF26 entre barras), conta BRL;
--   - verba_real: soma de mkt_trafego.desempenho_dia.gasto (sem imposto) pela camada mkt_trafego.segmento_plano;
--   - leads_real: dados.black_leads sem teste, sem "parece teste" e sem @advmais.com, pessoa única no dia da 1ª aparição
--     (mesma regra de relatorio.black_leads_hora), ligada à campanha pelo campanha_id (id da campanha no anúncio);
--   - plataforma sem conta cadastrada em mkt_trafego.contas (hoje o Google): verba_real e leads_real null, não 0;
--   - dia futuro: realizado null; dia passado ou hoje, sem gasto: 0;
--   - camada null = campanha sem segmento; 'historico' = teaser (fora do plano), aparece se tiver gasto no período.
set local lock_timeout = '3s';

create function public.dados_black_plano_diario(p_chave text)
returns table(dia date, plataforma text, camada text, verba_meta numeric, verba_real numeric, leads_meta int, leads_real int)
language plpgsql
stable security definer
set search_path to ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);
  v_de constant date := date '2026-10-17';
  v_ate constant date := date '2026-11-05';
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with c as (
    select c.id, c.plataforma, c.campanha_externa, mkt_trafego.segmento_plano(c.plataforma, c.nome) as camada
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  coleta as (select distinct ct.plataforma from mkt_trafego.contas ct where ct.ativa),
  gasto as (
    select x.dia, c.plataforma, c.camada, sum(x.gasto) as verba
      from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
     where x.dia between v_de and v_ate
     group by 1, 2, 3
  ),
  l as (
    select distinct on (b.pessoa_chave) b.pessoa_chave, b.criado_em, b.campanha_id
      from dados.black_leads b
     where not b.teste and not b.parece_teste and coalesce(b.email, '') not like '%@advmais.com'
     order by b.pessoa_chave, b.criado_em
  ),
  lead as (
    select (l.criado_em at time zone 'America/Sao_Paulo')::date as dia, c.plataforma, c.camada, count(*)::int as n
      from l join c on c.campanha_externa = l.campanha_id
     where (l.criado_em at time zone 'America/Sao_Paulo')::date between v_de and v_ate
     group by 1, 2, 3
  ),
  meta as (
    select m.dia, m.plataforma, m.camada, m.verba_meta_midia as verba, m.leads_meta as n
      from mkt_trafego.plano_diario m
     where m.projeto_id = d.projeto_id and m.dia between v_de and v_ate
  ),
  k as (
    select meta.dia, meta.plataforma, meta.camada from meta
    union select gasto.dia, gasto.plataforma, gasto.camada from gasto
    union select lead.dia, lead.plataforma, lead.camada from lead
  )
  select k.dia, k.plataforma, k.camada,
         m.verba,
         case when k.dia > v_hoje or not exists (select 1 from coleta co where co.plataforma = k.plataforma) then null
              else coalesce(g.verba, 0) end,
         m.n,
         case when k.dia > v_hoje or not exists (select 1 from coleta co where co.plataforma = k.plataforma) then null
              else coalesce(ld.n, 0) end
    from k
    left join meta m on m.dia = k.dia and m.plataforma = k.plataforma and m.camada is not distinct from k.camada
    left join gasto g on g.dia = k.dia and g.plataforma = k.plataforma and g.camada is not distinct from k.camada
    left join lead ld on ld.dia = k.dia and ld.plataforma = k.plataforma and ld.camada is not distinct from k.camada
   order by k.dia, k.plataforma, k.camada nulls last;
end
$f$;
comment on function public.dados_black_plano_diario(text) is
  'Black: meta x realizado de verba e leads por dia, plataforma e camada (17/10 a 05/11). Só equipe. Contrato do painel black-friday-2026-10, 16/10/2026.';
revoke execute on function public.dados_black_plano_diario(text) from public, anon;
grant execute on function public.dados_black_plano_diario(text) to authenticated;

  -- testes
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := jsonb_build_object(
    'plano', (select jsonb_build_object('linhas', count(*), 'verba', sum(verba_meta_midia), 'leads', sum(leads_meta)) from mkt_trafego.plano_diario),
    'segmento_por_campanha', (select jsonb_agg(jsonb_build_object('id', c.id, 'seg', mkt_trafego.segmento_plano(c.plataforma, c.nome),
          'gasto_out', (select round(coalesce(sum(x.gasto),0)) from mkt_trafego.desempenho_dia x where x.campanha_id = c.id and x.dia >= '2026-10-01')) order by c.id)
        from mkt_trafego.campanhas c join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
       where c.projeto_id = 4 or (c.projeto_id is null and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = 'BF26'))),
    'gasto_out_por_segmento', (select jsonb_object_agg(coalesce(s, 'SEM'), g) from (
        select mkt_trafego.segmento_plano(c.plataforma, c.nome) s, round(sum(x.gasto)) g
          from mkt_trafego.campanhas c join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
          join mkt_trafego.desempenho_dia x on x.campanha_id = c.id and x.dia >= '2026-10-01'
         where c.projeto_id = 4 or (c.projeto_id is null and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = 'BF26'))
         group by 1) z),
    'casos', jsonb_build_object(
       'rmk_live', mkt_trafego.segmento_plano('meta', 'CF | BF26 | REMARKETING | LIVE | FB'),
       'carrinho', mkt_trafego.segmento_plano('meta', 'CF | BF26 | CARRINHO | FB'),
       'manifesto', mkt_trafego.segmento_plano('meta', 'CF | BF26 | MANIFESTOS | FB'),
       'nulo', mkt_trafego.segmento_plano('meta', null)),
    'rpc', (select jsonb_build_object('linhas', count(*), 'verba_meta', sum(verba_meta), 'leads_meta', sum(leads_meta),
                   'verba_real', sum(verba_real), 'leads_real', sum(leads_real),
                   'google_real_nao_nulo', count(*) filter (where plataforma = 'google' and (verba_real is not null or leads_real is not null)),
                   'futuro_real_nao_nulo', count(*) filter (where dia > (now() at time zone 'America/Sao_Paulo')::date and verba_real is not null),
                   'sem_segmento', count(*) filter (where camada is null), 'dias', count(distinct dia))
              from public.dados_black_plano_diario('black-friday-2026-10')),
    'acl', jsonb_build_object(
       'anon_rpc', has_function_privilege('anon', 'public.dados_black_plano_diario(text)', 'execute'),
       'auth_rpc', has_function_privilege('authenticated', 'public.dados_black_plano_diario(text)', 'execute'),
       'auth_seg', has_function_privilege('authenticated', 'mkt_trafego.segmento_plano(text,text)', 'execute'),
       'auth_tabela', has_table_privilege('authenticated', 'mkt_trafego.plano_diario', 'select'),
       'rls', (select relrowsecurity from pg_class where oid = 'mkt_trafego.plano_diario'::regclass)));
  perform set_config('request.jwt.claims', '', true);
  begin
    perform * from public.dados_black_plano_diario('black-friday-2026-10');
    v := v || '{"sem_jwt": "PASSOU (ruim)"}';
  exception when insufficient_privilege then v := v || '{"sem_jwt": "42501 (bom)"}';
  end;
  begin
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    perform * from public.dados_black_plano_diario('atm-elaine-1-2026-10');
    v := v || '{"outra_chave": "PASSOU (ruim)"}';
  exception when others then v := v || jsonb_build_object('outra_chave', sqlstate);
  end;
  raise exception 'ENSAIO_DESFEITO %', v;
end $ensaio$;
