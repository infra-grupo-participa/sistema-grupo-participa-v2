-- 20261012220000: mkt_trafego.etapa_black passa a ficar com o PRIMEIRO subtipo e a sinalizar o conflito.
-- ARQUIVO EM UTF-8: o translate usa um mapa de letras acentuadas (mesmo cuidado da 20261012120000).
-- POR QUE: regra do Victor (12/10/2026, noite), registrada no cérebro em
--   _contexto/decisoes/2026-10-black-etapas-pelo-nome-da-campanha.md: "dois subtipos no mesmo nome: sinaliza o
--   conflito e fica com o primeiro subtipo que aparece no nome". Na 20261012120000 o subtipo ficava nulo e sem
--   sinal (era o "por ora" enquanto ele não decidia).
-- O QUE MUDA (só o corpo da função; assinatura, dono, grants e search_path iguais):
--   - dois ou mais subtipos da mesma etapa: subtipo = o que aparece primeiro no nome (posição entre as barras) e
--     conflito = true;
--   - dois códigos diferentes (C1 e C2 no mesmo nome): igual a antes, etapa nula e conflito = true;
--   - como ler: conflito com etapa nula = códigos; conflito com etapa preenchida = subtipos.
--   - o mesmo subtipo repetido (MANIFESTO | MANIFESTO) não é conflito.
-- AS 5 PERGUNTAS: escala, índice e frequência: nenhuma mudança (função imutável, calculada na leitura, ninguém
--   chama ainda além do ensaio; a RPC do dashboard é de outra fase). Repetição: create or replace, idempotente.
--   Reversão: 20261012220000_reversao.sql (corpo anterior).
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.etapa_black(text)') is null then
    raise exception '20261012220000: mkt_trafego.etapa_black não existe (aplicar antes a 20261012120000).';
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

-- create or replace preserva dono e grants; a conferência abaixo garante que continua sem grant além do dono.
do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_trafego.etapa_black(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261012220000: mkt_trafego.etapa_black tem grant além do dono (inclusive PUBLIC)';
  end if;
end
$g$;
