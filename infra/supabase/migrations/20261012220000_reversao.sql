-- Reversão da 20261012220000: volta o corpo da mkt_trafego.etapa_black da 20261012120000 (dois subtipos = subtipo
-- nulo, sem conflito). Assinatura, dono e grants não mudam com create or replace.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function mkt_trafego.etapa_black(p_nome text)
 returns table (etapa text, subtipo text, conflito boolean)
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  with regra (etapa, chave, rotulo) as (
    values ('C1', 'TEASER', 'TEASER'), ('C1', 'MANIFESTO', 'MANIFESTO'), ('C1', 'REELS', 'REELS'), ('C1', 'CORTES', 'CORTES'),
           ('C2', 'CONSULTORIA', 'CONSULTORIA'), ('C2', 'ISCA', 'ISCA'),
           ('C3', 'LEADS', 'LEADS')
  ),
  termo as (
    select distinct upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                               'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) as u (t)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  sub as (select distinct r.rotulo from regra r join termo on termo.t = r.chave join cod on cod.etapa = r.etapa)
  -- código sem subtipo (ex.: "X | C3 | LEAD"): etapa preenchida e subtipo nulo, para o gasto não sumir da etapa (DECIDIDO)
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end as etapa,
         case when (select count(*) from cod) = 1 and (select count(*) from sub) = 1 then (select s.rotulo from sub s) end as subtipo,
         (select count(*) from cod) > 1 as conflito
$function$;
