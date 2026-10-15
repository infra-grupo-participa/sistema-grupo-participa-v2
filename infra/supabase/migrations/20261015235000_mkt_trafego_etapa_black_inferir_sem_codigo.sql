-- 20261015235000: etapa_black infere a etapa de captação quando o nome não traz C1, C2 ou C3 (PROVISÓRIO até o padrão do Caio).
-- Escopo: somente o corpo da função; nenhuma tabela, linha, grant ou RLS é alterado.
-- Reversão: 20261015235000_reversao.sql restaura o corpo da 20261014130200.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.etapa_black(text)') is null then
    raise exception '20261015235000: mkt_trafego.etapa_black(text) não existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure)
      is distinct from '6c4ff2cd76f3d6b1cf9c5b3d3064ed93' then
    raise exception '20261015235000: corpo vivo mudou; revisar antes de aplicar';
  end if;
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
           ('C2', 'CONSULTORIA', 'CONSULTORIA'), ('C2', 'ISCA', 'ISCA'), ('C2', 'ISCAS', 'ISCA'),
           ('C3', 'LEADS', 'LEADS')
  ),
  termo as (
    select u.n, upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                         'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) with ordinality as u (t, n)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  -- PROVISÓRIO (16/10/2026, até o padrão de nomenclatura do Caio): sem o código C1, C2 ou C3 no nome, a etapa de
  -- captação é inferida. Palavra de C2 (CONSULTORIA, ISCA, ISCAS) → C2; senão CAPTACAO ou LEADS → C3. C1 sem código
  -- segue pela regra provisória do front (ehC1PeloNome). Com código no nome, nada muda.
  inf as (
    select case when exists (select 1 from regra r join termo on termo.t = r.chave where r.etapa = 'C2') then 'C2'
                when exists (select 1 from termo where termo.t in ('CAPTACAO', 'LEADS')) then 'C3' end as etapa
     where not exists (select 1 from cod)
  ),
  et as (select c.etapa from cod c union all select i.etapa from inf i where i.etapa is not null),
  -- Os aliases ISCA e ISCAS têm o mesmo rótulo canônico e não criam conflito entre si.
  sub as (select r.rotulo, min(termo.n) as pos
            from regra r join termo on termo.t = r.chave join et on et.etapa = r.etapa
           group by r.rotulo)
  select case when (select count(*) from et) = 1 then (select e.etapa from et e) end as etapa,
         case when (select count(*) from et) = 1 then (select s.rotulo from sub s order by s.pos limit 1) end as subtipo,
         (select count(*) from et) > 1 or ((select count(*) from et) = 1 and (select count(*) from sub) > 1) as conflito
$function$;

do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_trafego.etapa_black(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261015235000: etapa_black tem grant além do dono';
  end if;
end
$g$;
