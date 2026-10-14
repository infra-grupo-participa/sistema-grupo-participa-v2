-- Reverte 20261014130200 restaurando o corpo anterior da 20261012214704.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.etapa_black(text)') is null then
    raise exception '20261014130200 reversão: função não existe';
  end if;
  if not exists (
    select 1 from mkt_trafego.etapa_black('X | C2 | ISCAS') e
     where e.etapa = 'C2' and e.subtipo = 'ISCA' and e.conflito = false
  ) then raise exception '20261014130200 reversão: regra atual não é a versão esperada'; end if;
end
$g$;

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
    select u.n, upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                         'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) with ordinality as u (t, n)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  -- posição da primeira aparição de cada subtipo da etapa encontrada
  sub as (select r.rotulo, min(termo.n) as pos
            from regra r join termo on termo.t = r.chave join cod on cod.etapa = r.etapa
           group by r.rotulo)
  -- código sem subtipo (ex.: "X | C3 | LEAD"): etapa preenchida e subtipo nulo (DECIDIDO)
  -- dois subtipos: fica o primeiro e conflito = true (DECIDIDO, 12/10/2026 noite)
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end as etapa,
         case when (select count(*) from cod) = 1 then (select s.rotulo from sub s order by s.pos limit 1) end as subtipo,
         (select count(*) from cod) > 1 or ((select count(*) from cod) = 1 and (select count(*) from sub) > 1) as conflito
$function$;

do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_trafego.etapa_black(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261014130200 reversão: etapa_black tem grant além do dono';
  end if;
end
$g$;
