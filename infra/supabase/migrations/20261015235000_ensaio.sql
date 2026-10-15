-- Ensaio transacional da 20261015235000: aplica a migration, confere casos e a reversão, e desfaz tudo no ROLLBACK final.
-- Retorna só contagens e nomes de campanha (sem dado pessoal).
begin;
create temp table _antes as
  select c.id, c.nome, e.etapa, e.subtipo, e.conflito
    from mkt_trafego.campanhas c cross join lateral mkt_trafego.etapa_black(c.nome) e;

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

create temp table _casos (nome text, etapa text, subtipo text, conflito boolean);
insert into _casos values
  -- com código: igual a antes
  ('X | C2 | ISCAS', 'C2', 'ISCA', false),
  ('X | C2 | ISCAS | CONSULTORIA', 'C2', 'ISCA', true),
  ('X | C1 | TEASER | MANIFESTO', 'C1', 'TEASER', true),
  ('X | C3 | LEADS', 'C3', 'LEADS', false),
  ('X | C1 | C3 | CAPTAÇÃO', null, null, true),
  ('X | C1 | CAPTAÇÃO', 'C1', null, false),
  -- sem código: inferência
  ('CF | BF26 | CAPTAÇÃO | ISCAS | FB', 'C2', 'ISCA', false),
  ('CF | BF26 | CAPTAÇÃO | CONSULTORIA', 'C2', 'CONSULTORIA', false),
  ('CF | BF26 | CAPTAÇÃO | BASE | FB', 'C3', null, false),
  ('CF | BF26 | LEADS', 'C3', 'LEADS', false),
  ('CF | BF26 | ISCAS | CONSULTORIA', 'C2', 'ISCA', true),
  ('CF | BF26 | AQUECIMENTO | FB', null, null, false),
  ('CF | BF26 | ANTECIPAÇÃO | FB', null, null, false),
  ('CF | BF26 | TEASER', null, null, false),
  ('CF | BF26 | CAPTACAOX', null, null, false),
  (null, null, null, false);

do $g$
begin
  if exists (select 1 from _casos v cross join lateral mkt_trafego.etapa_black(v.nome) e
              where (e.etapa, e.subtipo, e.conflito) is distinct from (v.etapa, v.subtipo, v.conflito)) then
    raise exception '20261015235000 ensaio: caso unitário falhou';
  end if;
  -- Com código C1/C2/C3 no nome, nada muda.
  if exists (select 1 from _antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
              where a.etapa is not null and (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito)) then
    raise exception '20261015235000 ensaio: campanha com etapa mudou';
  end if;
end
$g$;

create temp table _resumo as
  select (select count(*) from _antes) as comparadas,
         (select count(*) from _antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
           where (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito)) as alteradas,
         (select json_agg(json_build_object('nome', a.nome, 'etapa', e.etapa, 'subtipo', e.subtipo) order by a.nome)
            from _antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
           where a.nome ilike '%BF26%' and (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito)) as black;

-- Reversão também é ensaiada: tem de voltar ao md5 da 20261014130200.
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

select * from _resumo;
rollback;
