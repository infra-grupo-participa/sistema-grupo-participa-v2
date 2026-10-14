-- Ensaio transacional: substitui temporariamente a função e faz ROLLBACK explícito ao final.
-- Sem nomes, e-mails ou outros dados pessoais são retornados; só classificação e contagens.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
create temp table _antes as
  select c.id, c.nome, e.etapa, e.subtipo, e.conflito
    from mkt_trafego.campanhas c cross join lateral mkt_trafego.etapa_black(c.nome) e;

-- Medida da implementação anterior no conjunto atual e em 10×; não imprime nomes.
explain (analyze, buffers, timing off)
select count(*) from mkt_trafego.campanhas c cross join lateral mkt_trafego.etapa_black(c.nome) e;
explain (analyze, buffers, timing off)
select count(*) from generate_series(1, 10) x cross join mkt_trafego.campanhas c
cross join lateral mkt_trafego.etapa_black(c.nome) e;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure)
      is distinct from 'ad283827886ef398bff20d806a8fd02b' then
    raise exception '20261014130200 ensaio: corpo vivo mudou';
  end if;
end
$g$;

create or replace function mkt_trafego.etapa_black(p_nome text)
 returns table (etapa text, subtipo text, conflito boolean)
 language sql immutable parallel safe set search_path to ''
as $function$
  with regra (etapa, chave, rotulo) as (
    values ('C1', 'TEASER', 'TEASER'), ('C1', 'MANIFESTO', 'MANIFESTO'), ('C1', 'REELS', 'REELS'), ('C1', 'CORTES', 'CORTES'),
           ('C2', 'CONSULTORIA', 'CONSULTORIA'), ('C2', 'ISCA', 'ISCA'), ('C2', 'ISCAS', 'ISCA'), ('C3', 'LEADS', 'LEADS')
  ),
  termo as (
    select u.n, upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                         'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) with ordinality as u (t, n)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  sub as (select r.rotulo, min(termo.n) as pos from regra r join termo on termo.t = r.chave join cod on cod.etapa = r.etapa group by r.rotulo)
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end,
         case when (select count(*) from cod) = 1 then (select s.rotulo from sub s order by s.pos limit 1) end,
         (select count(*) from cod) > 1 or ((select count(*) from cod) = 1 and (select count(*) from sub) > 1)
$function$;

create temp table _casos (nome text, etapa text, subtipo text, conflito boolean);
insert into _casos values
  ('X | C2 | ISCAS', 'C2', 'ISCA', false),
  ('X | C2 | ISCAS | CONSULTORIA', 'C2', 'ISCA', true),
  ('X | C2 | ISCA | ISCAS', 'C2', 'ISCA', false),
  ('X | C2 | ISCASA', 'C2', null, false),
  ('X | C2 ISCAS', null, null, false),
  ('X | C2 | CONSULTORIA | ISCAS', 'C2', 'CONSULTORIA', true),
  ('X | C1 | TEASER | MANIFESTO', 'C1', 'TEASER', true),
  ('X | C3 | LEADS', 'C3', 'LEADS', false);

do $g$
begin
  if exists (
    select 1 from _casos v cross join lateral mkt_trafego.etapa_black(v.nome) e
     where (e.etapa, e.subtipo, e.conflito) is distinct from (v.etapa, v.subtipo, v.conflito)
  ) then raise exception '20261014130200 ensaio: caso unitário falhou'; end if;

  if (select count(*) from _antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
       where (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito)) <> 1 then
    raise exception '20261014130200 ensaio: esperado exatamente um nome de campanha alterado';
  end if;

  if not exists (
    select 1 from mkt_trafego.campanhas c cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.nome = 'CF | BF26 | C2 | ISCAS | CAPTAÇÃO | META | PQ | ABO | LEAD'
       and e.etapa = 'C2' and e.subtipo = 'ISCA' and e.conflito = false
  ) then raise exception '20261014130200 ensaio: campanha alvo não recebeu ISCA'; end if;

  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_trafego.etapa_black(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261014130200 ensaio: ACL contém grant além do dono';
  end if;
end
$g$;

-- A saída retorna apenas totais e o alvo nominal, sem dado pessoal.
select 'campanhas_comparadas' as item, count(*)::text as valor from _antes
union all
select 'casos_unitarios', count(*)::text from _casos
union all
select 'classificacoes_alteradas', count(*)::text from _antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
  where (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito);

rollback;
