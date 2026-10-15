-- Ensaio de 20261015200000_acesso_master_isabela.sql: sonda de guardas (a mesma de 20261007204002) em todos os perfis
-- ativos antes, depois de 2 passadas, depois da reversão; provas com o JWT da Isabela; explain (analyze, buffers) 2x.
-- Esperado: só a Isabela (#e1d2) muda; 7 masters; reversão devolve a sonda igual à de antes. Nada persiste (rollback).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_sonda (fase text, perfil text, j jsonb) on commit drop;
grant all on pg_temp._z_out to authenticated; grant all on sequence pg_temp._z_out_em_seq to authenticated;
create function pg_temp.sonda(p_id uuid) returns jsonb language plpgsql as $s$
declare j jsonb; a record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  j := jsonb_build_object(
    'equipe', public.gp_eh_equipe(), 'admin', public.gp_is_admin(), 'master', acesso.eh_master(),
    'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'cpf', public.gp_pode_ver_cpf(),
    'contato', acesso.tem('contato.ver'),
    'crm_gestor', crm.eh_gestor(), 'crm_comercial', crm.eh_comercial(), 'crm_catalogar', crm.pode_catalogar(),
    'remocao', public.ra_pode_ver(), 'pedidos', public.pa_pode_pedir(), 'placas', public.gp_pode_editar('placas'),
    'base_pessoas', pessoas.pode_ver(), 'pa_pode_ver_doc', public.pa_pode_ver_doc(), 'alunos_ver_sensivel', public.tem_permissao(p_id, 'alunos.ver_sensivel'),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'ver_financeiro', public.gp_acesso_pode_ver('financeiro', null));
  for a in select d.key as dep, null::text as ar from acesso.departamento d union all select ar2.departamento, ar2.key from acesso.area ar2 loop
    j := j || jsonb_build_object('ed:' || a.dep || coalesce('/' || a.ar, ''), public.gp_acesso_pode_editar(a.dep, a.ar));
  end loop;
  perform set_config('request.jwt.claims', '', true);
  return j;
end $s$;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 300);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated;
create function pg_temp.fotografa(p_fase text) returns void language sql as $f$
  insert into pg_temp._z_sonda select p_fase, p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id) from public.perfis p where p.status = 'ativo';
$f$;
create function pg_temp.compara(p_a text, p_b text) returns text language sql as $c$
  select coalesce(string_agg(b.perfil || ' (' || (select count(*) from jsonb_each(b.j) e where e.value is distinct from a.j -> e.key) || ' guardas)', '; '), 'nenhum perfil mudou')
    from pg_temp._z_sonda a join pg_temp._z_sonda b on b.perfil = a.perfil and b.fase = p_b
   where a.fase = p_a and a.j is distinct from b.j;
$c$;
create function pg_temp.provas(p_fase text) returns void language plpgsql as $p$
begin
  set local role authenticated;
  insert into pg_temp._z_out (passo, linha) select p_fase || ': Isabela gp_meu_acesso', pg_temp.tenta('e1d2863d-c975-46bd-b35f-45b1039328e3', 'select public.gp_meu_acesso()::text');
  insert into pg_temp._z_out (passo, linha) select p_fase || ': Isabela acesso_listar', pg_temp.tenta('e1d2863d-c975-46bd-b35f-45b1039328e3', $q$select jsonb_build_object('masters', jsonb_array_length(public.acesso_listar() -> 'masters'), 'vinculos', jsonb_array_length(public.acesso_listar() -> 'vinculos'))::text$q$);
  reset role;
end $p$;

select pg_temp.fotografa('antes');
select pg_temp.provas('0 antes');
insert into pg_temp._z_out (passo, linha) select '0 antes: masters', count(*)::text from acesso.master;
insert into pg_temp._z_out (passo, linha) select '0 antes: log total', count(*)::text from acesso.log;

-- ===== PASSADA 1 =====
-- 20261015200000: a Isabela Teixeira (Head de Sucesso do Cliente, perfil e1d2863d…) vira MASTER no acesso central do v2.
-- Pedido do Victor Hugo em 15/10/2026: "dá acesso pra isabela de admin no grupoparticipa.app.br". Decisão do Victor,
-- passada pelo Maestro: master pela migration, com revisão do pentester antes de aplicar.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261015200000_ensaio.sql. Reversão: 20261015200000_reversao.sql.
-- Relatório: 20261015200000.explain.md.
--
-- POR QUE
--   Ela já tem cargo admin e está em acesso.excecao_admin, mas produção roda com NEXT_PUBLIC_ACESSO_V2=true, e aí as
--   telas de admin (Usuários, seção admin do menu, Acessos) exigem acesso.master. Nenhuma tela ou RPC concede master:
--   o caminho é uma linha em acesso.master, igual à fase 0 (20261007180503) e à QA Sessoes (20261007204002).
--   Cargo, áreas, funções, vínculos e capacidades dela NÃO mudam. Nenhuma função é recriada (sem blindagem).
--
-- AUTORIA NO LOG
--   O gatilho log_master grava autor = auth.uid(). O claim sub vira o Victor Hugo (81d2eaee…) só nesta transação
--   (set_config local) e é limpo no fim. Mais 1 linha de motivo (tabela master, acao motivo).
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em acesso.master, 2 em acesso.log. índice: PK de acesso.master (perfil_id). frequência: uma vez.
--   repetição: nenhuma (idempotente). reversão: 20261015200000_reversao.sql (delete da linha; o gatilho registra).
--
-- IDEMPOTENTE: on conflict / where not exists.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select nome from public.perfis where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and status = 'ativo')
     is distinct from 'Isabela Teixeira' then
    raise exception '20261015200000: perfil e1d2863d não é mais a Isabela Teixeira ativa';
  end if;
  if not exists (select 1 from auth.users u where u.id = 'e1d2863d-c975-46bd-b35f-45b1039328e3'
                   and lower(u.email) like '%@advmais.com' and u.deleted_at is null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261015200000: conta do Auth da Isabela não confere (domínio, excluída ou banida)';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo' then
    raise exception '20261015200000: autor esperado (Victor Hugo) não confere';
  end if;
  if (select count(*) from acesso.master) <> 6
     and not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception '20261015200000: esperava 6 masters antes (Victor, Arthur, JP, QA Sessoes, Elaine, Marcio)';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

insert into acesso.master (perfil_id, criado_por)
values ('e1d2863d-c975-46bd-b35f-45b1039328e3', '81d2eaee-cce1-4058-8714-439b0fc6f970')
on conflict (perfil_id) do nothing;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'e1d2863d-c975-46bd-b35f-45b1039328e3', null,
       jsonb_build_object('motivo', 'admin do v2 para a Isabela (Head de Sucesso do Cliente), pedido do Victor 15/10',
                          'registrado_por', 'migration 20261015200000', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3'
                     and tabela = 'master' and acao = 'motivo' and depois->>'registrado_por' = 'migration 20261015200000');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if (select count(*) from acesso.master) <> 7
     or not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception '20261015200000: esperava 7 masters, com a Isabela';
  end if;
  if (select cargo from public.perfis where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') is distinct from 'admin' then
    raise exception '20261015200000: o cargo da Isabela não deveria mudar';
  end if;
  if not exists (select 1 from acesso.log where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and tabela = 'master'
                   and acao = 'insert' and autor = '81d2eaee-cce1-4058-8714-439b0fc6f970') then
    raise exception '20261015200000: falta o log master/insert da Isabela com autor Victor Hugo (rodou fora de transação?)';
  end if;
end
$c$;

select pg_temp.fotografa('depois1');
insert into pg_temp._z_out (passo, linha) select '1 depois1: quem mudou', pg_temp.compara('antes', 'depois1');

-- ===== PASSADA 2 (idempotência) =====
-- 20261015200000: a Isabela Teixeira (Head de Sucesso do Cliente, perfil e1d2863d…) vira MASTER no acesso central do v2.
-- Pedido do Victor Hugo em 15/10/2026: "dá acesso pra isabela de admin no grupoparticipa.app.br". Decisão do Victor,
-- passada pelo Maestro: master pela migration, com revisão do pentester antes de aplicar.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261015200000_ensaio.sql. Reversão: 20261015200000_reversao.sql.
-- Relatório: 20261015200000.explain.md.
--
-- POR QUE
--   Ela já tem cargo admin e está em acesso.excecao_admin, mas produção roda com NEXT_PUBLIC_ACESSO_V2=true, e aí as
--   telas de admin (Usuários, seção admin do menu, Acessos) exigem acesso.master. Nenhuma tela ou RPC concede master:
--   o caminho é uma linha em acesso.master, igual à fase 0 (20261007180503) e à QA Sessoes (20261007204002).
--   Cargo, áreas, funções, vínculos e capacidades dela NÃO mudam. Nenhuma função é recriada (sem blindagem).
--
-- AUTORIA NO LOG
--   O gatilho log_master grava autor = auth.uid(). O claim sub vira o Victor Hugo (81d2eaee…) só nesta transação
--   (set_config local) e é limpo no fim. Mais 1 linha de motivo (tabela master, acao motivo).
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em acesso.master, 2 em acesso.log. índice: PK de acesso.master (perfil_id). frequência: uma vez.
--   repetição: nenhuma (idempotente). reversão: 20261015200000_reversao.sql (delete da linha; o gatilho registra).
--
-- IDEMPOTENTE: on conflict / where not exists.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select nome from public.perfis where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and status = 'ativo')
     is distinct from 'Isabela Teixeira' then
    raise exception '20261015200000: perfil e1d2863d não é mais a Isabela Teixeira ativa';
  end if;
  if not exists (select 1 from auth.users u where u.id = 'e1d2863d-c975-46bd-b35f-45b1039328e3'
                   and lower(u.email) like '%@advmais.com' and u.deleted_at is null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261015200000: conta do Auth da Isabela não confere (domínio, excluída ou banida)';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo' then
    raise exception '20261015200000: autor esperado (Victor Hugo) não confere';
  end if;
  if (select count(*) from acesso.master) <> 6
     and not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception '20261015200000: esperava 6 masters antes (Victor, Arthur, JP, QA Sessoes, Elaine, Marcio)';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

insert into acesso.master (perfil_id, criado_por)
values ('e1d2863d-c975-46bd-b35f-45b1039328e3', '81d2eaee-cce1-4058-8714-439b0fc6f970')
on conflict (perfil_id) do nothing;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'e1d2863d-c975-46bd-b35f-45b1039328e3', null,
       jsonb_build_object('motivo', 'admin do v2 para a Isabela (Head de Sucesso do Cliente), pedido do Victor 15/10',
                          'registrado_por', 'migration 20261015200000', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3'
                     and tabela = 'master' and acao = 'motivo' and depois->>'registrado_por' = 'migration 20261015200000');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if (select count(*) from acesso.master) <> 7
     or not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception '20261015200000: esperava 7 masters, com a Isabela';
  end if;
  if (select cargo from public.perfis where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') is distinct from 'admin' then
    raise exception '20261015200000: o cargo da Isabela não deveria mudar';
  end if;
  if not exists (select 1 from acesso.log where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and tabela = 'master'
                   and acao = 'insert' and autor = '81d2eaee-cce1-4058-8714-439b0fc6f970') then
    raise exception '20261015200000: falta o log master/insert da Isabela com autor Victor Hugo (rodou fora de transação?)';
  end if;
end
$c$;

select pg_temp.fotografa('depois2');
insert into pg_temp._z_out (passo, linha) select '2 depois2 x depois1', pg_temp.compara('depois1', 'depois2');
insert into pg_temp._z_out (passo, linha) select '2 masters', count(*)::text from acesso.master;
insert into pg_temp._z_out (passo, linha) select '2 log novas', string_agg(tabela || '/' || acao || ' autor ' || coalesce((select nome from public.perfis where id = autor), 'null'), '; ' order by id)
  from acesso.log where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and quando >= now();
select pg_temp.provas('2 depois');
insert into pg_temp._z_out (passo, linha) select '2 isabela diferenças p/ um master (Victor)',
  coalesce(string_agg(e.key, ', '), 'nenhuma') from pg_temp._z_sonda a join pg_temp._z_sonda b on b.fase = 'depois2' and b.perfil like 'Victor Hugo #81d2'
  cross join jsonb_each(a.j) e where a.fase = 'depois2' and a.perfil like 'Isabela Teixeira #e1d2' and e.value is distinct from b.j -> e.key;


-- ===== REVERSÃO =====
-- Reversão de 20261015200000_acesso_master_isabela.sql: tira a Isabela Teixeira (e1d2863d…) de acesso.master.
-- O gatilho log_master registra o delete com autor Victor Hugo; mais 1 linha de motivo. Cargo, vínculos e
-- capacidades dela não mudam (continuam como antes da migration). Depois: delete da versão 20261015200000 em
-- supabase_migrations.schema_migrations.
set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception 'reversão 20261015200000: a Isabela não está em acesso.master (nada a reverter)';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);
delete from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3';
insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
values ('81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'e1d2863d-c975-46bd-b35f-45b1039328e3', null,
        jsonb_build_object('motivo', 'reversão de 20261015200000: Isabela deixa de ser master',
                           'registrado_por', 'reversão 20261015200000', 'registrado_em', now()));
select set_config('request.jwt.claims', '', true);

do $c$
begin
  if exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception 'reversão 20261015200000: a Isabela continua master';
  end if;
  if (select count(*) from acesso.master) <> 6 then
    raise exception 'reversão 20261015200000: esperava 6 masters depois de tirar a Isabela';
  end if;
end
$c$;

select pg_temp.fotografa('revertido');
insert into pg_temp._z_out (passo, linha) select '3 revertido x antes', pg_temp.compara('antes', 'revertido');
insert into pg_temp._z_out (passo, linha) select '3 masters', count(*)::text from acesso.master;
select pg_temp.provas('3 revertido');

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
