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
