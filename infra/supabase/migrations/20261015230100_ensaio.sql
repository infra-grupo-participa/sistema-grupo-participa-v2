-- Ensaio de 20261015230100_dados_black_lives_teto_janela.sql (transação desfeita, sobre produção). Tabela-verdade antes e depois,
-- relativa a now() (não depende de data fixa), e a prova no cadastro real: uma live 'ao_vivo' esquecida não mantém a janela.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', case when p_id is null then '{"role":"anon"}' else jsonb_build_object('sub', p_id, 'role', 'authenticated')::text end, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 600);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated, anon;

create temp table _z_antes as select md5(prosrc) h from pg_proc where oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: ao_vivo 4 h depois do previsto (esperado true)', dados.black_live_na_janela(now() - interval '4 hours', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: ao_vivo 5 h 59 min depois (esperado true)', dados.black_live_na_janela(now() - interval '5 hours 59 minutes', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: ao_vivo 6 h 1 min depois (o teto) (esperado false)', dados.black_live_na_janela(now() - interval '6 hours 1 minute', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: ao_vivo parada há 7 dias (esperado false)', dados.black_live_na_janela(now() - interval '7 days', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: ao_vivo que começou 20 min antes do previsto (esperado true)', dados.black_live_na_janela(now() + interval '20 minutes', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: em_breve dentro das 3 h (esperado true)', dados.black_live_na_janela(now() - interval '2 hours', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: em_breve passadas as 3 h (esperado false)', dados.black_live_na_janela(now() - interval '4 hours', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: em_breve 10 min antes (esperado true)', dados.black_live_na_janela(now() + interval '10 minutes', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: em_breve 20 min antes (esperado false)', dados.black_live_na_janela(now() + interval '20 minutes', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: realizada dentro das 3 h (esperado true)', dados.black_live_na_janela(now() - interval '2 hours', 'realizada')::text;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: realizada passadas as 3 h (esperado false)', dados.black_live_na_janela(now() - interval '4 hours', 'realizada')::text;
create temp table _z_old as select
  (select count(*) from dados.black_lives l where l.ativo and dados.black_live_na_janela(l.data_prevista, l.situacao)) na_janela;

-- ═══ migration inteira ═══
-- 20261015230100: teto de cota na janela da coleta da aba "Lives" (achado do pentester, 15/10/2026).
--
-- POR QUE: dados.black_live_na_janela devolvia verdadeiro para QUALQUER live com situação 'ao_vivo', sem limite. Se a Edge
-- parar de conseguir atualizar a situação (cota do YouTube estourada, chave revogada, falha repetida), a live fica
-- 'ao_vivo' para sempre no banco, a janela fica aberta para sempre e o cron chama a Edge todo minuto gastando cota (chat
-- ~5 unidades por chamada, a chave é compartilhada com o dashboard-ht). Esta migration põe um teto absoluto.
--
-- O QUE FAZ (só dados.black_live_na_janela; assinatura, grants e quem chama não mudam)
--   Antes: ao_vivo (sem limite) OU de 15 min antes até 3 h depois do horário previsto.
--   Agora: ao_vivo ATÉ 6 h depois do horário previsto OU de 15 min antes até 3 h depois do horário previsto.
--   Passadas 6 h do horário previsto a live deixa de manter a janela aberta mesmo que a situação diga 'ao_vivo'. O cron continua
--   chamando a cada 10 minutos (cadastro e foto), e é essa leitura que corrige a situação quando a API voltar.
--   (A trava de concorrência da Edge está em functions/black-youtube/index.ts, não no banco.)
--
-- AS 5 PERGUNTAS
--   escala: 9 lives, uma função de 1 linha chamada 1 vez por live ativa por minuto. Não cresce com a base.
--   índice: não lê tabela (recebe os valores por argumento). Nenhuma query nova.
--   frequência: chamada por black_live_pede_chamada() a cada minuto (9 avaliações) e por black_live_alvos() a cada chamada da Edge.
--   repetição: nenhuma tela.
--   reversão: 20261015230100_reversao.sql devolve o corpo anterior (byte a byte).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('dados.black_live_na_janela(timestamptz,text)') is null then
    raise exception '20261015230100: aplique antes 20261015220000 (black_live_na_janela ausente)';
  end if;
end
$g$;

create or replace function dados.black_live_na_janela(p_prevista timestamptz, p_situacao text) returns boolean
language sql stable set search_path = '' as $$
  select (p_situacao = 'ao_vivo' and now() <= p_prevista + interval '6 hours')
      or (now() >= p_prevista - interval '15 minutes' and now() <= p_prevista + interval '3 hours')
$$;

do $conf$
begin
  if has_function_privilege('anon', 'dados.black_live_na_janela(timestamptz,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_live_na_janela(timestamptz,text)', 'execute')
     or has_function_privilege('service_role', 'dados.black_live_na_janela(timestamptz,text)', 'execute') then
    raise exception '20261015230100: black_live_na_janela com grant aberto';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure) !~ '6 hours' then
    raise exception '20261015230100: corpo novo não está no banco';
  end if;
end
$conf$;

-- ═══ fim da migration ═══

insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: ao_vivo 4 h depois do previsto (esperado true)', dados.black_live_na_janela(now() - interval '4 hours', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: ao_vivo 5 h 59 min depois (esperado true)', dados.black_live_na_janela(now() - interval '5 hours 59 minutes', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: ao_vivo 6 h 1 min depois (o teto) (esperado false)', dados.black_live_na_janela(now() - interval '6 hours 1 minute', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: ao_vivo parada há 7 dias (esperado false)', dados.black_live_na_janela(now() - interval '7 days', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: ao_vivo que começou 20 min antes do previsto (esperado true)', dados.black_live_na_janela(now() + interval '20 minutes', 'ao_vivo')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: em_breve dentro das 3 h (esperado true)', dados.black_live_na_janela(now() - interval '2 hours', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: em_breve passadas as 3 h (esperado false)', dados.black_live_na_janela(now() - interval '4 hours', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: em_breve 10 min antes (esperado true)', dados.black_live_na_janela(now() + interval '10 minutes', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: em_breve 20 min antes (esperado false)', dados.black_live_na_janela(now() + interval '20 minutes', 'em_breve')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: realizada dentro das 3 h (esperado true)', dados.black_live_na_janela(now() - interval '2 hours', 'realizada')::text;
insert into pg_temp._z_out (passo, linha) select '1 DEPOIS: realizada passadas as 3 h (esperado false)', dados.black_live_na_janela(now() - interval '4 hours', 'realizada')::text;
-- no cadastro real: live esquecida em ao_vivo, 7 h depois do previsto
update dados.black_lives set situacao = 'ao_vivo', data_prevista = now() - interval '7 hours' where video_id = 'A9d6HjegnTk';
insert into pg_temp._z_out (passo, linha) select '2 live esquecida ao_vivo 7 h depois: lives na janela (esperado 0 se nenhuma outra está na janela)',
  (select count(*) from dados.black_lives l where l.ativo and dados.black_live_na_janela(l.data_prevista, l.situacao))::text;
insert into pg_temp._z_out (passo, linha) select '2 pede_chamada() é só o minuto %10 ou a janela: parte da janela (esperado false)',
  exists (select 1 from dados.black_lives l where l.ativo and dados.black_live_na_janela(l.data_prevista, l.situacao))::text;
update dados.black_lives set situacao = 'ao_vivo', data_prevista = now() - interval '2 hours' where video_id = 'A9d6HjegnTk';
insert into pg_temp._z_out (passo, linha) select '2 a mesma live 2 h depois (esperado true)',
  exists (select 1 from dados.black_lives l where l.ativo and dados.black_live_na_janela(l.data_prevista, l.situacao))::text;
-- permissões e plano
insert into pg_temp._z_out (passo, linha) select '3 na_janela executável por anon / authenticated / service_role (esperado false false false)',
  concat_ws(' ', has_function_privilege('anon', 'dados.black_live_na_janela(timestamptz,text)', 'execute'),
    has_function_privilege('authenticated', 'dados.black_live_na_janela(timestamptz,text)', 'execute'),
    has_function_privilege('service_role', 'dados.black_live_na_janela(timestamptz,text)', 'execute'));
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select dados.black_live_pede_chamada(), dados.black_live_alvos()' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared)' then insert into pg_temp._z_out (passo, linha) values ('4 explain pede_chamada+alvos ' || n, r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
-- reversão ensaiada: o corpo antigo volta byte a byte
-- Reversão de 20261015230100: devolve o corpo anterior de dados.black_live_na_janela (ao_vivo sem teto).
-- Atenção: volta o risco de a janela ficar aberta para sempre se a situação 'ao_vivo' não for corrigida.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function dados.black_live_na_janela(p_prevista timestamptz, p_situacao text) returns boolean
language sql stable set search_path = '' as $$
  select p_situacao = 'ao_vivo'
      or (now() >= p_prevista - interval '15 minutes' and now() <= p_prevista + interval '3 hours')
$$;

do $c$
begin
  if (select p.prosrc from pg_proc p where p.oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure) ~ '6 hours' then
    raise exception 'reversão de 20261015230100 incompleta';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '5 depois da reversão: corpo igual ao de antes (esperado true)', (select md5(prosrc) = a.h from pg_proc, _z_antes a where oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure)::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
