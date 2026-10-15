-- Reversão da 20261015235000: volta etapa_black ao corpo da 20261014130200 (sem inferência; só o código C1/C2/C3 define a etapa).
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
           ('C2', 'CONSULTORIA', 'CONSULTORIA'), ('C2', 'ISCA', 'ISCA'), ('C2', 'ISCAS', 'ISCA'),
           ('C3', 'LEADS', 'LEADS')
  ),
  termo as (
    select u.n, upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                         'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) with ordinality as u (t, n)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  -- Os aliases ISCA e ISCAS têm o mesmo rótulo canônico e não criam conflito entre si.
  sub as (select r.rotulo, min(termo.n) as pos
            from regra r join termo on termo.t = r.chave join cod on cod.etapa = r.etapa
           group by r.rotulo)
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end as etapa,
         case when (select count(*) from cod) = 1 then (select s.rotulo from sub s order by s.pos limit 1) end as subtipo,
         (select count(*) from cod) > 1 or ((select count(*) from cod) = 1 and (select count(*) from sub) > 1) as conflito
$function$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure)
      is distinct from '6c4ff2cd76f3d6b1cf9c5b3d3064ed93' then
    raise exception '20261015235000 reversão: corpo restaurado não confere com a 20261014130200';
  end if;
end
$g$;
