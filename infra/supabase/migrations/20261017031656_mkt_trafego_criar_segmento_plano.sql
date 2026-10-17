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
--      CAPTACAO com ALUNO ou NAO ALUNO             -> c3 (decisão do Arthur, 16/10/2026)
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
    when k && array['BASE', 'ENTRESAFRA', 'C3']
      or ('CAPTACAO' = any(k) and k && array['ALUNO', 'NAO ALUNO']) then 'c3'
    when 'C1' = any(k) then 'c1'
    when 'C2' = any(k) then 'c2'
  end
  from t
$f$;
comment on function mkt_trafego.segmento_plano(text, text) is
  'Camada do plano diário (c1, c2, c3, aquecimento, remarketing, remarketing_live, carrinho, historico) pelo nome da campanha. De-para do Maestro, 16/10/2026. Null = sem segmento.';
revoke execute on function mkt_trafego.segmento_plano(text, text) from public, anon, authenticated;
