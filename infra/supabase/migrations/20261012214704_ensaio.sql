-- ENSAIO da 20261012214704 (roda em produção e desfaz tudo: termina em raise exception, que aborta a transação;
-- a saída volta na mensagem de erro entre ZZSAIDA e ZZFIM, porque a Management API só devolve o último comando).
-- Confere: (1) casos da regra, antigos e novos; (2) diferença velho x novo em todos os nomes de campanha do banco
-- (só pode mudar nome com dois subtipos); (3) anon e authenticated seguem com 42501; (4) grants e dono iguais.
begin;
create temp table _z_out (ord serial, passo text, linha text);
create temp table _z_antes as
  select c.id, c.nome, e.etapa, e.subtipo, e.conflito from mkt_trafego.campanhas c cross join lateral mkt_trafego.etapa_black(c.nome) e;
insert into pg_temp._z_out (passo, linha)
  select '0 acl antes', coalesce(proacl::text, '(nulo)') || ' dono=' || proowner::regrole::text
    from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure;

-- 20261012214704: mkt_trafego.etapa_black passa a ficar com o PRIMEIRO subtipo e a sinalizar o conflito.
-- ARQUIVO EM UTF-8: o translate usa um mapa de letras acentuadas (mesmo cuidado da 20261012212726).
-- POR QUE: regra do Victor (12/10/2026, noite), registrada no cérebro em
--   _contexto/decisoes/2026-10-black-etapas-pelo-nome-da-campanha.md: "dois subtipos no mesmo nome: sinaliza o
--   conflito e fica com o primeiro subtipo que aparece no nome". Na 20261012212726 o subtipo ficava nulo e sem
--   sinal (era o "por ora" enquanto ele não decidia).
-- O QUE MUDA (só o corpo da função; assinatura, dono, grants e search_path iguais):
--   - dois ou mais subtipos da mesma etapa: subtipo = o que aparece primeiro no nome (posição entre as barras) e
--     conflito = true;
--   - dois códigos diferentes (C1 e C2 no mesmo nome): igual a antes, etapa nula e conflito = true;
--   - como ler: conflito com etapa nula = códigos; conflito com etapa preenchida = subtipos.
--   - o mesmo subtipo repetido (MANIFESTO | MANIFESTO) não é conflito.
-- AS 5 PERGUNTAS: escala, índice e frequência: nenhuma mudança (função imutável, calculada na leitura, ninguém
--   chama ainda além do ensaio; a RPC do dashboard é de outra fase). Repetição: create or replace, idempotente.
--   Reversão: 20261012214704_reversao.sql (corpo anterior).
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.etapa_black(text)') is null then
    raise exception '20261012214704: mkt_trafego.etapa_black não existe (aplicar antes a 20261012212726).';
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
    raise exception '20261012214704: mkt_trafego.etapa_black tem grant além do dono (inclusive PUBLIC)';
  end if;
end
$g$;

insert into pg_temp._z_out (passo, linha)
  select '0 acl depois', coalesce(proacl::text, '(nulo)') || ' dono=' || proowner::regrole::text
    from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure;

create temp table _z_etapa as
  select v.n, e.etapa, e.subtipo, e.conflito,
         (e.etapa is not distinct from v.esp_e and e.subtipo is not distinct from v.esp_s and e.conflito = v.esp_c) as confere
  from (values
    ('X | c1 | antecipação', 'C1', null, false),
    ('C1 | ANTECIPAÇÃO | TEASER', 'C1', 'TEASER', false),
    ('X | C1 | MANIFESTO', 'C1', 'MANIFESTO', false),
    ('X | C1 | Manifésto', 'C1', 'MANIFESTO', false),
    ('X | C1 | TEASER | MANIFESTO', 'C1', 'TEASER', true),
    ('X | C1 | MANIFESTO | TEASER', 'C1', 'MANIFESTO', true),
    ('MANIFESTO | X | C1 | TEASER', 'C1', 'MANIFESTO', true),
    ('X | C1 | MANIFESTO | MANIFESTO', 'C1', 'MANIFESTO', false),
    ('X | C1 | REELS | CORTES | TEASER', 'C1', 'REELS', true),
    ('X | C2 | ISCA | CONSULTORIA', 'C2', 'ISCA', true),
    ('X | C2 | ISCAS | CONSULTORIA', 'C2', 'CONSULTORIA', false),
    ('X | C3 | TEASER | LEADS', 'C3', 'LEADS', false),
    ('C1|TEASER', 'C1', 'TEASER', false),
    ('X | c2 | isca', 'C2', 'ISCA', false),
    ('X | C2 | ISCAS', 'C2', null, false),
    ('X | C2 ISCAS | Y', null, null, false),
    ('X | C3 | LEADS', 'C3', 'LEADS', false),
    ('X | C3 | LEAD', 'C3', null, false),
    ('X | C1 | C2 | TEASER', null, null, true),
    ('X | C1 | C2 | TEASER | ISCA', null, null, true),
    ('X | C1 | C1 | TEASER', 'C1', 'TEASER', false),
    ('BF26 | CPF01 | META | IG | MORNO | ABO | LEAD', null, null, false),
    (null, null, null, false)
  ) v (n, esp_e, esp_s, esp_c)
  cross join lateral mkt_trafego.etapa_black(v.n) e;
insert into pg_temp._z_out (passo, linha)
  select '1 etapa ' || coalesce(n, '(nulo)'),
         jsonb_build_object('etapa', etapa, 'subtipo', subtipo, 'conflito', conflito, 'confere', confere)::text
    from pg_temp._z_etapa where not confere;
insert into pg_temp._z_out (passo, linha)
  select '1 etapa resumo', jsonb_build_object('casos', count(*), 'erradas', count(*) filter (where not confere))::text from pg_temp._z_etapa;

insert into pg_temp._z_out (passo, linha)
  select '2 banco mudou', jsonb_build_object('nome', a.nome, 'antes', jsonb_build_array(a.etapa, a.subtipo, a.conflito),
                                             'depois', jsonb_build_array(e.etapa, e.subtipo, e.conflito))::text
    from pg_temp._z_antes a cross join lateral mkt_trafego.etapa_black(a.nome) e
   where (a.etapa, a.subtipo, a.conflito) is distinct from (e.etapa, e.subtipo, e.conflito);
insert into pg_temp._z_out (passo, linha)
  select '2 banco resumo', jsonb_build_object('campanhas', count(*))::text from pg_temp._z_antes;

do $zz$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    begin
      execute format('set local role %I', r);
      perform * from mkt_trafego.etapa_black('X | C1 | TEASER');
      reset role;
      insert into pg_temp._z_out (passo, linha) values ('3 ' || r, 'ERRO DO ENSAIO: executou');
    exception when others then
      reset role;
      insert into pg_temp._z_out (passo, linha) values ('3 ' || r, sqlstate);
    end;
  end loop;
end
$zz$;

do $zz$
begin
  raise exception 'ZZSAIDA%ZZFIM', (select string_agg(passo || ' :: ' || linha, E'
' order by ord) from pg_temp._z_out);
end
$zz$;
