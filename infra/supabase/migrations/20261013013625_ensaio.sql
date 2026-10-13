-- Ensaio de 20261013013625 (transação desfeita, REPEATABLE READ). Black: marcar/desmarcar teste só master.
-- Prova: (1) antes, equipe não master marca e desmarca na Black (o furo); (2) depois, master marca/desmarca, equipe não
-- master, fora da equipe e anon recebem 42501; (3) o ramo do ATM dá exatamente as mesmas respostas antes, depois e depois
-- da reversão, para master, equipe, fora da equipe e anon; (4) o md5 do resultado das RPCs de leitura (dados_atm_* e
-- dados_black_*) e do corpo das funções não tocadas é igual nas três fases; (5) o desmarcar da Black não toca marcação
-- de outro dashboard com o mesmo valor; (6) a reversão volta os corpos ao md5 de antes e o furo reaparece.
-- Só contagens, sqlstate e md5: nenhum dado pessoal sai do ensaio. Gerado por um script a partir da migration e da
-- reversão (o texto delas entra aqui sem mudança).
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_snap (fase text, nome text, h text) on commit drop;
create temp table _z_src (fase text, f text, h text) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_snap to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;

-- 0. quem é quem (conferido no banco, não nome fixo)
do $q$ begin
  if not exists (select 1 from acesso.master where perfil_id = '81d2eaee-cce1-4058-8714-439b0fc6f970') then raise exception 'ensaio: M não é master'; end if;
  if exists (select 1 from acesso.master where perfil_id = '00b177e0-3c8b-4e55-8f64-f57560bbbd74')
     or not exists (select 1 from public.perfis p where p.id = '00b177e0-3c8b-4e55-8f64-f57560bbbd74' and p.status = 'ativo' and p.email ilike '%@advmais.com') then
    raise exception 'ensaio: E não é equipe não master'; end if;
end $q$;
-- e-mail da Black sem marcação ativa; e-mail com marcação ativa na Black; e-mail do ATM sem marcação
create temp table _z_be on commit drop as select l.email from dados.black_leads l where l.email is not null
   and not exists (select 1 from dados.marcacoes_teste m where m.chave = 'black-friday-2026-10' and m.desmarcado_em is null and m.tipo = 'email' and m.valor = l.email)
 order by l.email limit 1;
create temp table _z_bm on commit drop as select m.valor as email from dados.marcacoes_teste m
 where m.chave = 'black-friday-2026-10' and m.desmarcado_em is null and m.tipo = 'email' order by m.id limit 1;
create temp table _z_a on commit drop as select l.email from dados.atm_leads('atm-elaine-1-2026-10') l
 where l.email is not null and not dados.teste_ativo('atm-elaine-1-2026-10', l.email, null) order by l.email limit 1;
grant select on pg_temp._z_be, pg_temp._z_bm, pg_temp._z_a to authenticated, anon;
insert into pg_temp._z_out (passo, linha) select '0 apoio', jsonb_build_object('be', (select count(*) from pg_temp._z_be), 'bm', (select count(*) from pg_temp._z_bm), 'a', (select count(*) from pg_temp._z_a))::text;
-- 2ª chave do mesmo modelo (a trava da chave continua valendo)
insert into dados.dashboards select (jsonb_populate_record(null::dados.dashboards, to_jsonb(d) || '{"chave":"ensaio-outra-jornada"}')).* from dados.dashboards d where d.chave = 'black-friday-2026-10';

-- ===== 1. ANTES =====
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_src (fase, f, h) select 'antes', p.oid::regprocedure::text, md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname = 'public' and (p.proname like 'dados_black%' or p.proname like 'dados_atm%' or p.proname in ('dados_testes', 'dados_presencial_marcar_teste')))
    or (n.nspname = 'dados' and p.proname in ('black_evento', 'black_pertence', 'black_cadastro', 'cadastro', 'atm_cadastro', 'atm_pertence', 'pode_ver', 'teste_ativo'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'atm_resumo', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'atm_leads', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'atm_grupo_numeros', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'atm testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'black perfil sem pessoa_id', md5(coalesce((select jsonb_agg(to_jsonb(x) - 'pessoa_id' order by (to_jsonb(x) - 'pessoa_id')::text) from public.dados_black_perfil('black-friday-2026-10', null, null, true) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'black leads 500', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_black_leads('black-friday-2026-10', (select array_agg(lead_id) from (select lead_id from public.dados_black_perfil('black-friday-2026-10', null, null, true) order by criado_em desc, lead_id limit 500) z)) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'black grupo', md5(coalesce((select public.dados_black_grupo('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'black trafego', md5(coalesce((select public.dados_black_trafego('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'antes', 'black testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('black-friday-2026-10') x)::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | antes', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_marcar_teste(''black-friday-2026-10'', (select email from pg_temp._z_be))' loop
    if l ~ '(Execution|Planning) Time|^Result' then insert into pg_temp._z_out (passo, linha) values ('E explain marcar black | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_desmarcar_teste(''black-friday-2026-10'', (select email from pg_temp._z_be))' loop
    if l ~ '(Execution|Planning) Time|^Result' then insert into pg_temp._z_out (passo, linha) values ('E explain desmarcar black | antes', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 2. MIGRATION (texto de 20261013013625_dados_black_teste_so_master.sql) =====
-- 20261013013625: na Black (modelo jornada-captacao, chave black-friday-2026-10), marcar e desmarcar teste só para master.
-- Achado do pentester (13/10/2026): no ramo da Black, dados_marcar_teste e dados_desmarcar_teste só exigiam a equipe
-- (black_evento -> black_cadastro -> dados.cadastro -> gp_eh_equipe), não master. O presencial já exige
-- acesso.eh_master() (dados_presencial_marcar_teste). Esta migration:
--   1. cria dados.black_evento_master(chave): 42501 se não for master; depois o mesmo dados.black_evento de antes
--      (P0002 fora da chave da Black). Sem grant.
--   2. dados_marcar_teste e dados_desmarcar_teste: o ramo da Black passa a chamar black_evento_master. O ramo do ATM
--      (atm_cadastro) fica com o texto e o comportamento de antes: só equipe. Isso é pendência para decisão (explain §5).
--   3. O desmarcar continua preso ao evento: o update só toca linhas com m.chave = d.chave, e d.chave vem de
--      black_evento (só 'black-friday-2026-10'). Nada muda em dados_testes nem nas RPCs dados_black_* de leitura.
-- Pré-requisito: corpo vivo das duas RPCs igual ao gravado por 20261012234606 (md5 conferido abaixo).
-- Reversão: 20261013013625_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('dados.black_evento(text)') is null then
    raise exception '20261013013625: dados.black_evento não existe (aplicar 20261012234606 antes).';
  end if;
  if to_regprocedure('acesso.eh_master()') is null or to_regprocedure('acesso.eu()') is null then
    raise exception '20261013013625: acesso.eh_master() ou acesso.eu() não existe.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '05d7fecb174f8b16fa9cb3abcd7cea44'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '1e715847e3e96a74b01cfa0a9260afc0'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_evento(text)'::regprocedure) <> '0f6a30a86f69abf4a4981a1efd885f87'
     or (select md5(prosrc) from pg_proc where oid = 'dados.atm_cadastro(text)'::regprocedure) <> '0501ccd5647a89b44c7b9c02dc4ad8ca' then
    raise exception '20261013013625: corpo vivo de dados_marcar_teste, dados_desmarcar_teste, black_evento ou atm_cadastro mudou. Reler.';
  end if;
end
$g$;

-- 1. trava de master da Black (mesma regra de dados_presencial_marcar_teste)
create or replace function dados.black_evento_master(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  -- 20261013013625: marcar e desmarcar teste na Black só para master
  if acesso.eu() is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return dados.black_evento(p_chave);   -- P0002 fora da chave da Black
end
$function$;
revoke all on function dados.black_evento_master(text) from public, anon, authenticated, service_role;

-- 2. marcar teste: só o ramo da Black muda (black_evento -> black_evento_master)
create or replace function public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  -- 20261013013625: na Black só master (42501); o ramo do ATM não mudou
  v_black boolean := exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao');
  d dados.dashboards := case when v_black then dados.black_evento_master(p_chave) else dados.atm_cadastro(p_chave) end;   -- Black: 42501 não master; ATM: 42501 não equipe; P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not (case when v_black then dados.black_pertence(d.chave, 'email', v_email)
                                       else dados.atm_pertence(d.chave, 'email', v_email) end) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not (case when v_black then dados.black_pertence(d.chave, 'fone', right(v_fk, 8))
                                    else dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) end) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$function$;

-- 3. desmarcar teste: só o ramo da Black muda; o update já fica preso a d.chave (o evento resolvido)
create or replace function public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  -- 20261013013625: na Black só master (42501); o ramo do ATM não mudou
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento_master(p_chave) else dados.atm_cadastro(p_chave) end;
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  -- só a marcação ativa deste evento (d.chave); a de outro dashboard com o mesmo valor não é tocada
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_marcar_teste(text, text, text, text) from public, anon;
revoke all on function public.dados_desmarcar_teste(text, text, text) from public, anon;
grant execute on function public.dados_marcar_teste(text, text, text, text) to authenticated;
grant execute on function public.dados_desmarcar_teste(text, text, text) to authenticated;

-- 4. conferência
do $c$
begin
  if exists (select 1 from pg_proc where oid = 'dados.black_evento_master(text)'::regprocedure
              and (proacl is null or proacl::text <> '{postgres=X/postgres}' or prosecdef)) then
    raise exception '20261013013625: black_evento_master com permissão errada';
  end if;
  if (select prosrc from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) not like '%dados.black_evento_master(p_chave)%'
     or (select prosrc from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) not like '%dados.black_evento_master(p_chave)%' then
    raise exception '20261013013625: ramo da Black sem a trava de master';
  end if;
  if has_function_privilege('anon', 'public.dados_marcar_teste(text,text,text,text)', 'execute')
     or has_function_privilege('anon', 'public.dados_desmarcar_teste(text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_marcar_teste(text,text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_desmarcar_teste(text,text,text)', 'execute') then
    raise exception '20261013013625: permissões das RPCs de teste erradas';
  end if;
end
$c$;

-- ===== fim da migration =====

reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_src (fase, f, h) select 'depois', p.oid::regprocedure::text, md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname = 'public' and (p.proname like 'dados_black%' or p.proname like 'dados_atm%' or p.proname in ('dados_testes', 'dados_presencial_marcar_teste')))
    or (n.nspname = 'dados' and p.proname in ('black_evento', 'black_pertence', 'black_cadastro', 'cadastro', 'atm_cadastro', 'atm_pertence', 'pode_ver', 'teste_ativo'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'atm_resumo', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'atm_leads', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'atm_grupo_numeros', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'atm testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'black perfil sem pessoa_id', md5(coalesce((select jsonb_agg(to_jsonb(x) - 'pessoa_id' order by (to_jsonb(x) - 'pessoa_id')::text) from public.dados_black_perfil('black-friday-2026-10', null, null, true) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'black leads 500', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_black_leads('black-friday-2026-10', (select array_agg(lead_id) from (select lead_id from public.dados_black_perfil('black-friday-2026-10', null, null, true) order by criado_em desc, lead_id limit 500) z)) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'black grupo', md5(coalesce((select public.dados_black_grupo('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'black trafego', md5(coalesce((select public.dados_black_trafego('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'depois', 'black testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('black-friday-2026-10') x)::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black anon | marcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black anon | marcar | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black anon | desmarcar | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black anon | desmarcar | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_bm)))::text;
  insert into pg_temp._z_out (passo, linha) values ('D E desmarca marcacao real da Black | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('D E desmarca marcacao real da Black | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'D marcacao real segue ativa', (select count(*) from dados.marcacoes_teste m where m.chave = 'black-friday-2026-10' and m.desmarcado_em is null and m.tipo = 'email' and m.valor = (select email from pg_temp._z_bm))::text;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into dados.marcacoes_teste (chave, tipo, valor, motivo) values ('atm-elaine-1-2026-10', 'email', 'ensaio-cruzado@ensaio.invalid', 'teste');
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', 'ensaio-cruzado@ensaio.invalid'))::text;
  insert into pg_temp._z_out (passo, linha) values ('D M desmarca na Black valor marcado so no ATM | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('D M desmarca na Black valor marcado so no ATM | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into dados.marcacoes_teste (chave, tipo, valor, motivo) values ('black-friday-2026-10', 'email', 'ensaio-cruzado@ensaio.invalid', 'teste');
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', 'ensaio-cruzado@ensaio.invalid'))::text;
  insert into pg_temp._z_out (passo, linha) values ('D M desmarca na Black valor marcado nos dois | depois', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('D M desmarca na Black valor marcado nos dois | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'D marcacao do ATM segue ativa', (select count(*) from dados.marcacoes_teste m where m.chave = 'atm-elaine-1-2026-10' and m.desmarcado_em is null and m.valor = 'ensaio-cruzado@ensaio.invalid')::text;
reset role;
select set_config('request.jwt.claims', '{}', true);
delete from dados.marcacoes_teste where valor = 'ensaio-cruzado@ensaio.invalid';
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_marcar_teste(''black-friday-2026-10'', (select email from pg_temp._z_be))' loop
    if l ~ '(Execution|Planning) Time|^Result' then insert into pg_temp._z_out (passo, linha) values ('E explain marcar black | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_desmarcar_teste(''black-friday-2026-10'', (select email from pg_temp._z_be))' loop
    if l ~ '(Execution|Planning) Time|^Result' then insert into pg_temp._z_out (passo, linha) values ('E explain desmarcar black | depois', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'F acl black_evento_master', (select coalesce(proacl::text, 'null') || ' secdef=' || prosecdef from pg_proc where oid = 'dados.black_evento_master(text)'::regprocedure);
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 3. REVERSÃO (texto de 20261013013625_reversao.sql) =====
-- Reversão de 20261013013625 (Black: marcar/desmarcar teste só master). Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_marcar_teste e dados_desmarcar_teste ao corpo exato gravado por 20261012234606 (lido no banco em
-- 13/10/2026 ~01:35 UTC; o comentário de dentro ainda diz 20261013130000, nome antigo do arquivo) e apaga
-- dados.black_evento_master. Não apaga dado: as marcações feitas por master depois da aplicação ficam.
-- Efeito: a Black volta a aceitar marcar/desmarcar de qualquer pessoa da equipe (o furo do achado).
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 20261013130000: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  v_black boolean := exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao');
  d dados.dashboards := case when v_black then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not (case when v_black then dados.black_pertence(d.chave, 'email', v_email)
                                       else dados.atm_pertence(d.chave, 'email', v_email) end) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not (case when v_black then dados.black_pertence(d.chave, 'fone', right(v_fk, 8))
                                    else dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) end) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 20261013130000: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

revoke all on function public.dados_marcar_teste(text, text, text, text) from public, anon;
revoke all on function public.dados_desmarcar_teste(text, text, text) from public, anon;
grant execute on function public.dados_marcar_teste(text, text, text, text) to authenticated;
grant execute on function public.dados_desmarcar_teste(text, text, text) to authenticated;

drop function if exists dados.black_evento_master(text);

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '05d7fecb174f8b16fa9cb3abcd7cea44'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '1e715847e3e96a74b01cfa0a9260afc0'
     or to_regprocedure('dados.black_evento_master(text)') is not null then
    raise exception 'reversão 20261013013625: corpo das RPCs de teste não voltou ao de antes';
  end if;
end
$c$;


-- ===== fim da reversão =====

reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_src (fase, f, h) select 'reversao', p.oid::regprocedure::text, md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname = 'public' and (p.proname like 'dados_black%' or p.proname like 'dados_atm%' or p.proname in ('dados_testes', 'dados_presencial_marcar_teste')))
    or (n.nspname = 'dados' and p.proname in ('black_evento', 'black_pertence', 'black_cadastro', 'cadastro', 'atm_cadastro', 'atm_pertence', 'pode_ver', 'teste_ativo'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'atm_resumo', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'atm_leads', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'atm_grupo_numeros', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'atm testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'black perfil sem pessoa_id', md5(coalesce((select jsonb_agg(to_jsonb(x) - 'pessoa_id' order by (to_jsonb(x) - 'pessoa_id')::text) from public.dados_black_perfil('black-friday-2026-10', null, null, true) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'black leads 500', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_black_leads('black-friday-2026-10', (select array_agg(lead_id) from (select lead_id from public.dados_black_perfil('black-friday-2026-10', null, null, true) order by criado_em desc, lead_id limit 500) z)) x)::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'black grupo', md5(coalesce((select public.dados_black_grupo('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'black trafego', md5(coalesce((select public.dados_black_trafego('black-friday-2026-10'))::text, 'null'));
insert into pg_temp._z_snap (fase, nome, h) select 'reversao', 'black testes', md5(coalesce((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('black-friday-2026-10') x)::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | motivo invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | telefone invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar vazio | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | desmarcar chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | chave da clinica | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm M | testes atm | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | motivo invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | telefone invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar vazio | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | desmarcar chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | chave da clinica | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm E | testes atm | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | motivo invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | telefone invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar vazio | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | desmarcar chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | chave da clinica | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm F | testes atm | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a)))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a), null, 'x'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | motivo invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | telefone invalido | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar vazio | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('nao-existe-ensaio', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | desmarcar chave inexistente | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | chave da clinica | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('atm-elaine-1-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B atm anon | testes atm | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | outra chave jornada desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | testes black | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black M | perfil black | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00b177e0-3c8b-4e55-8f64-f57560bbbd74","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | outra chave jornada desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | testes black | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black E | perfil black | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_be)))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | fora do evento | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_marcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada marcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_desmarcar_teste('ensaio-outra-jornada', 'a@b.c'))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | outra chave jornada desmarcar | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_testes('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | testes black | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := ((select count(*) from public.dados_black_perfil('black-friday-2026-10')))::text;
  insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | reversao', 'ok:' || coalesce(v, 'null'));
exception when others then insert into pg_temp._z_out (passo, linha) values ('C black F | perfil black | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 4. COMPARAÇÕES =====
insert into pg_temp._z_out (passo, linha)
select 'Z snap ' || a.nome, case when a.h = d.h and a.h = r.h then 'IGUAL' else 'DIFERENTE' end
  from pg_temp._z_snap a join pg_temp._z_snap d on d.nome = a.nome and d.fase = 'depois' join pg_temp._z_snap r on r.nome = a.nome and r.fase = 'reversao'
 where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z src ' || a.f, case when a.h = d.h and a.h = r.h then 'IGUAL' else 'DIFERENTE' end
  from pg_temp._z_src a left join pg_temp._z_src d on d.f = a.f and d.fase = 'depois' left join pg_temp._z_src r on r.f = a.f and r.fase = 'reversao'
 where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z bateria atm ' || split_part(a.passo, ' | ', 1) || ' | ' || split_part(a.passo, ' | ', 2),
       case when a.linha = d.linha and a.linha = r.linha then 'IGUAL ' || a.linha else 'DIFERENTE ' || a.linha || ' / ' || d.linha || ' / ' || r.linha end
  from pg_temp._z_out a
  join pg_temp._z_out d on d.passo = replace(a.passo, '| antes', '| depois')
  join pg_temp._z_out r on r.passo = replace(a.passo, '| antes', '| reversao')
 where a.passo like 'B atm %| antes';
select passo, linha from pg_temp._z_out where passo not like 'B atm %' order by em;
rollback;
