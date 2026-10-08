-- 08/10/2026: tirada a prova gps.eh_equipe() da sonda e a chave 'gps' virou 'admin_ou_editar_educacional' (o GPS
-- tem guarda própria, gps.eh_admin, e não lê mais o acesso central; ver docs/niveis-de-acesso-banco.md). O resto não mudou.
-- Ensaio de 20261007zz_gps_trocar_meu_nome.sql: sonda de 32 guardas antes, 2 passadas, sonda depois, provas, ROLLBACK e sonda de novo.
-- Transação desfeita: nada persiste.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;
create function pg_temp.sonda(p_id uuid) returns jsonb language plpgsql as $s$
declare j jsonb; k text; a record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  j := jsonb_build_object(
    'equipe', public.gp_eh_equipe(), 'admin', public.gp_is_admin(),
    'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'cpf', public.gp_pode_ver_cpf(),
    'crm_gestor', crm.eh_gestor(), 'crm_comercial', crm.eh_comercial(), 'crm_catalogar', crm.pode_catalogar(),
    'remocao', public.ra_pode_ver(), 'pedidos', public.pa_pode_pedir(), 'placas', public.gp_pode_editar('placas'),
    'base_pessoas', pessoas.pode_ver(), 'pa_pode_ver_doc', public.pa_pode_ver_doc(), 'alunos_ver_sensivel', public.tem_permissao(p_id, 'alunos.ver_sensivel'),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'admin_ou_editar_educacional', public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar('educacional', null), false),
    'ver_financeiro', public.gp_acesso_pode_ver('financeiro', null));
  for a in select d.key as dep, null::text as ar from acesso.departamento d union all select ar2.departamento, ar2.key from acesso.area ar2 loop
    j := j || jsonb_build_object('ed:' || a.dep || coalesce('/' || a.ar, ''), public.gp_acesso_pode_editar(a.dep, a.ar));
  end loop;
  return j;
end $s$;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 100);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.sonda(uuid), pg_temp.tenta(uuid, text) to authenticated;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';

-- ===== PASSADA 1 =====
-- 20261007zz: níveis de acesso, B3 do pentester: gps.trocar_meu_nome deixa de falhar inteira para quem é da equipe e não
-- é master. A parte do aluno (public.thb_alunos) funciona para todo mundo; o nome de EQUIPE (public.perfis) só muda
-- quando quem chama é master (regra do gatilho acesso_guarda da fase 3).
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007zz_ensaio.sql (2 passadas, sonda de 32 guardas, provas, rollback).
--   Relatório: 20261007zz.explain.md.
--
-- POR QUE
--   O corpo atual faz primeiro "update public.perfis set nome …" e depois o update do aluno. Desde a fase 3
--   (20261007195738), o gatilho acesso_guarda recusa (42501) a troca do próprio nome para quem não é master, e o erro
--   derruba a função inteira: a pessoa da equipe que também é aluna do Programa não consegue trocar o nome de aluna.
--
-- O QUE FAZ (corpo vivo + 1 mudança)
--   (a) equipe: só faz o update em perfis se quem chama está em acesso.master; senão marca que o nome de equipe não mudou.
--   (b) aluno: igual ao de hoje.
--   Sem nada alterado: se a pessoa só tem perfil de equipe e não é master → 42501 "O nome da equipe só muda pela gestão
--   de usuários." (mensagem clara em vez do erro do gatilho); sem cadastro → P0002 como hoje.
--   O retorno ganha 'equipe_nao_alterada' (true quando havia perfil de equipe e ele não foi trocado).
--
-- AS 5 PERGUNTAS
--   escala: 1 função. frequência: rara (pessoa troca o próprio nome). reversão: corpo anterior em acesso.corpo_antes.
--
-- IDEMPOTENTE: a guarda aceita o corpo vivo de hoje (md5 46d2cd34…) ou o desta migration.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B3 (20261007zz): gps.trocar_meu_nome sem derrubar a parte do aluno');
  end if;
end
$bl$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) is distinct from '46d2cd341dc39e82e499f2c720dde51a'
     and (select prosrc from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) !~ '20261007zz' then
    raise exception '20261007zz: corpo vivo de gps.trocar_meu_nome mudou. Refazer a partir do pg_get_functiondef.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007zz'
  from pg_proc p where p.oid = 'gps.trocar_meu_nome(text)'::regprocedure
on conflict do nothing;

create or replace function gps.trocar_meu_nome(p_nome text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_aluno uuid;
  v_onde text := null;
  v_equipe_nao_alterada boolean := false;
begin
  if v_user is null then
    raise exception 'Faça login para alterar o seu nome.' using errcode = '42501';
  end if;
  if char_length(v_nome) < 2 then
    raise exception 'Escreva o seu nome completo.' using errcode = '22023';
  end if;
  if char_length(v_nome) > 120 then
    raise exception 'O nome passa de 120 caracteres.' using errcode = '22023';
  end if;
  -- Sem quebra de linha: o nome vai para e-mail e para o Slack.
  if v_nome ~ '[\r\n]' then
    raise exception 'O nome não pode ter quebra de linha.' using errcode = '22023';
  end if;

  -- (a) equipe: 20261007zz, só master troca o próprio nome de equipe (regra do gatilho acesso_guarda, fase 3);
  --     para os outros o nome de equipe muda pela gestão de usuários, e a parte do aluno segue abaixo.
  if exists (select 1 from public.perfis p where p.id = v_user) then
    if exists (select 1 from acesso.master m where m.perfil_id = v_user) then
      update public.perfis set nome = v_nome, atualizado_em = now() where id = v_user;
      if found then v_onde := 'perfis'; end if;
    else
      v_equipe_nao_alterada := true;
    end if;
  end if;

  -- (b) aluno: a pessoa daquele login, não o titular do ambiente -- num
  --     ambiente com sócio os dois têm o mesmo aluno_id de ambiente, e usar
  --     ele trocaria o nome do titular.
  select m.pessoa_aluno_id into v_aluno
    from gps.membros m where m.user_id = v_user and m.pessoa_aluno_id is not null
   limit 1;
  if v_aluno is not null then
    update public.thb_alunos set nome = v_nome where id = v_aluno;
    if found then v_onde := coalesce(v_onde || '+', '') || 'thb_alunos'; end if;
  end if;

  if v_onde is null then
    if v_equipe_nao_alterada then
      raise exception 'O nome da equipe só muda pela gestão de usuários.' using errcode = '42501';
    end if;
    raise exception 'Não encontramos o seu cadastro para alterar o nome.' using errcode = 'P0002';
  end if;

  return jsonb_build_object('nome', v_nome, 'onde', v_onde, 'equipe_nao_alterada', v_equipe_nao_alterada);
end;
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'gps.trocar_meu_nome(text)'::regprocedure) !~ '20261007zz' then
    raise exception '20261007zz: corpo não foi recriado';
  end if;
  if has_function_privilege('anon', 'gps.trocar_meu_nome(text)', 'execute')
     or not has_function_privilege('authenticated', 'gps.trocar_meu_nome(text)', 'execute') then
    raise exception '20261007zz: permissões de gps.trocar_meu_nome mudaram';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/niveis-de-acesso/rollback-b3.sql (cérebro), ensaiado em 20261007zz_ensaio.sql.

-- ===== PASSADA 2 =====
-- 20261007zz: níveis de acesso, B3 do pentester: gps.trocar_meu_nome deixa de falhar inteira para quem é da equipe e não
-- é master. A parte do aluno (public.thb_alunos) funciona para todo mundo; o nome de EQUIPE (public.perfis) só muda
-- quando quem chama é master (regra do gatilho acesso_guarda da fase 3).
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007zz_ensaio.sql (2 passadas, sonda de 32 guardas, provas, rollback).
--   Relatório: 20261007zz.explain.md.
--
-- POR QUE
--   O corpo atual faz primeiro "update public.perfis set nome …" e depois o update do aluno. Desde a fase 3
--   (20261007195738), o gatilho acesso_guarda recusa (42501) a troca do próprio nome para quem não é master, e o erro
--   derruba a função inteira: a pessoa da equipe que também é aluna do Programa não consegue trocar o nome de aluna.
--
-- O QUE FAZ (corpo vivo + 1 mudança)
--   (a) equipe: só faz o update em perfis se quem chama está em acesso.master; senão marca que o nome de equipe não mudou.
--   (b) aluno: igual ao de hoje.
--   Sem nada alterado: se a pessoa só tem perfil de equipe e não é master → 42501 "O nome da equipe só muda pela gestão
--   de usuários." (mensagem clara em vez do erro do gatilho); sem cadastro → P0002 como hoje.
--   O retorno ganha 'equipe_nao_alterada' (true quando havia perfil de equipe e ele não foi trocado).
--
-- AS 5 PERGUNTAS
--   escala: 1 função. frequência: rara (pessoa troca o próprio nome). reversão: corpo anterior em acesso.corpo_antes.
--
-- IDEMPOTENTE: a guarda aceita o corpo vivo de hoje (md5 46d2cd34…) ou o desta migration.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B3 (20261007zz): gps.trocar_meu_nome sem derrubar a parte do aluno');
  end if;
end
$bl$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) is distinct from '46d2cd341dc39e82e499f2c720dde51a'
     and (select prosrc from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) !~ '20261007zz' then
    raise exception '20261007zz: corpo vivo de gps.trocar_meu_nome mudou. Refazer a partir do pg_get_functiondef.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007zz'
  from pg_proc p where p.oid = 'gps.trocar_meu_nome(text)'::regprocedure
on conflict do nothing;

create or replace function gps.trocar_meu_nome(p_nome text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_aluno uuid;
  v_onde text := null;
  v_equipe_nao_alterada boolean := false;
begin
  if v_user is null then
    raise exception 'Faça login para alterar o seu nome.' using errcode = '42501';
  end if;
  if char_length(v_nome) < 2 then
    raise exception 'Escreva o seu nome completo.' using errcode = '22023';
  end if;
  if char_length(v_nome) > 120 then
    raise exception 'O nome passa de 120 caracteres.' using errcode = '22023';
  end if;
  -- Sem quebra de linha: o nome vai para e-mail e para o Slack.
  if v_nome ~ '[\r\n]' then
    raise exception 'O nome não pode ter quebra de linha.' using errcode = '22023';
  end if;

  -- (a) equipe: 20261007zz, só master troca o próprio nome de equipe (regra do gatilho acesso_guarda, fase 3);
  --     para os outros o nome de equipe muda pela gestão de usuários, e a parte do aluno segue abaixo.
  if exists (select 1 from public.perfis p where p.id = v_user) then
    if exists (select 1 from acesso.master m where m.perfil_id = v_user) then
      update public.perfis set nome = v_nome, atualizado_em = now() where id = v_user;
      if found then v_onde := 'perfis'; end if;
    else
      v_equipe_nao_alterada := true;
    end if;
  end if;

  -- (b) aluno: a pessoa daquele login, não o titular do ambiente -- num
  --     ambiente com sócio os dois têm o mesmo aluno_id de ambiente, e usar
  --     ele trocaria o nome do titular.
  select m.pessoa_aluno_id into v_aluno
    from gps.membros m where m.user_id = v_user and m.pessoa_aluno_id is not null
   limit 1;
  if v_aluno is not null then
    update public.thb_alunos set nome = v_nome where id = v_aluno;
    if found then v_onde := coalesce(v_onde || '+', '') || 'thb_alunos'; end if;
  end if;

  if v_onde is null then
    if v_equipe_nao_alterada then
      raise exception 'O nome da equipe só muda pela gestão de usuários.' using errcode = '42501';
    end if;
    raise exception 'Não encontramos o seu cadastro para alterar o nome.' using errcode = 'P0002';
  end if;

  return jsonb_build_object('nome', v_nome, 'onde', v_onde, 'equipe_nao_alterada', v_equipe_nao_alterada);
end;
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'gps.trocar_meu_nome(text)'::regprocedure) !~ '20261007zz' then
    raise exception '20261007zz: corpo não foi recriado';
  end if;
  if has_function_privilege('anon', 'gps.trocar_meu_nome(text)', 'execute')
     or not has_function_privilege('authenticated', 'gps.trocar_meu_nome(text)', 'execute') then
    raise exception '20261007zz: permissões de gps.trocar_meu_nome mudaram';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/niveis-de-acesso/rollback-b3.sql (cérebro), ensaiado em 20261007zz_ensaio.sql.

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '2 depois') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;

-- ===== PROVAS =====
create function pg_temp.troca(p_id uuid) returns text language plpgsql as $t$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  v := gps.trocar_meu_nome('Nome De Ensaio B3');
  return jsonb_build_object('onde', v ->> 'onde', 'equipe_nao_alterada', v -> 'equipe_nao_alterada')::text;
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.troca(uuid) to authenticated;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'b3 Luis (equipe, não master, sem aluno)', pg_temp.troca('9d5fb8e7-f61e-459d-be04-d103ec783c08');
insert into pg_temp._z_out (passo, linha) select 'b3 Victor (master)', pg_temp.troca('81d2eaee-cce1-4058-8714-439b0fc6f970');
reset role;
select set_config('request.jwt.claims', '{}', true);
update public.perfis set nome = 'Victor Hugo' where id = '81d2eaee-cce1-4058-8714-439b0fc6f970';  -- desfaz o teste (a sonda usa o nome)
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'b3 aluno sem perfil de equipe', pg_temp.troca('55bb3a65-ab23-4406-b97c-9edfc9fe7039');
reset role;
-- simula o Luis também como aluno (só neste ensaio): liga ao login dele um vínculo de aluno NÃO titular (fora do gatilho do Drive)
select set_config('request.jwt.claims', '{}', true);
update gps.membros set user_id = '9d5fb8e7-f61e-459d-be04-d103ec783c08' where id = 'd99a8462-d47e-426c-af2a-3b6841efbd29' and papel <> 'titular';
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'b3 Luis (equipe, não master, também aluno)', pg_temp.troca('9d5fb8e7-f61e-459d-be04-d103ec783c08');
reset role;
insert into pg_temp._z_out (passo, linha) select 'b3 nome de equipe do Luis não mudou', ((select nome from public.perfis where id = '9d5fb8e7-f61e-459d-be04-d103ec783c08') <> 'Nome De Ensaio B3')::text;
select set_config('request.jwt.claims', '{}', true);

-- ===== ROLLBACK =====
-- Rollback da migration 20261007zz_gps_trocar_meu_nome: volta o corpo anterior (acesso.corpo_antes). Numa transação.
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $bl$ begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('rollback do B3 de níveis de acesso (20261007zz): gps.trocar_meu_nome de antes');
  end if;
end $bl$;
do $v$ declare r record; begin
  for r in select * from acesso.corpo_antes where migration = '20261007zz' and tipo = 'funcao' loop execute r.definicao; end loop;
end $v$;
do $c$ begin
  if (select prosrc from pg_proc where oid = 'gps.trocar_meu_nome(text)'::regprocedure) ~ '20261007zz' then
    raise exception 'rollback B3: corpo não voltou';
  end if;
end $c$;

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '3 depois do rollback', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas depois do rollback', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois do rollback') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
