-- Ensaio de 20261007204002_acesso_master_qa_sessoes.sql (era 20261007qa): sonda de 32 guardas (a mesma da fase 3) em todos os perfis ativos
-- antes, depois de 2 passadas e depois do rollback; provas com o JWT da QA Sessoes; explain (analyze, buffers) 2x.
-- Esperado: só a QA Sessoes (#d4b4) muda; 4 masters; 3 linhas de log com autor Victor Hugo (+1 do rollback); rollback
-- devolve a sonda igual à de antes. Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste.
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
    'base_pessoas', pessoas.pode_ver(), 'gps_eh_equipe', gps.eh_equipe(), 'pa_pode_ver_doc', public.pa_pode_ver_doc(), 'alunos_ver_sensivel', public.tem_permissao(p_id, 'alunos.ver_sensivel'),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'gps', public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar('educacional', null), false),
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
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '0 antes: QA gp_meu_acesso', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', 'select public.gp_meu_acesso()::text');
insert into pg_temp._z_out (passo, linha) select '0 antes: QA acesso_listar', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', $q$select jsonb_build_object('masters', jsonb_array_length(public.acesso_listar() -> 'masters'), 'vinculos', jsonb_array_length(public.acesso_listar() -> 'vinculos'))::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes: Luis acesso_listar', pg_temp.tenta('9d5fb8e7-f61e-459d-be04-d103ec783c08', 'select left(public.acesso_listar()::text, 40)');
reset role;
select set_config('request.jwt.claims', '', true);

-- ===== PASSADA 1 =====
-- 20261007qa: níveis de acesso, a conta de teste "QA Sessoes (conta de teste)" (perfil d4b4f75f…, qa.sessoes@advmais.com)
-- vira MASTER, para o JP testar a tela de níveis de acesso com a flag NEXT_PUBLIC_ACESSO_V2. Pedido do Victor Hugo em
-- 07/10/2026 ("conta de teste master para o JP testar a tela de acesso").
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007qa_ensaio.sql. Relatório: 20261007qa.explain.md.
--
-- POR QUE
--   A tela de acesso (gestão de vínculos e capacidades) só abre para master. O JP precisa testar com uma conta que não é
--   de pessoa real. A conta QA Sessoes é do agente de teste do JP (palavra do Victor, decisoes-maestro.md item 10).
--   Caminho oficial: linha em acesso.master, o mesmo da fase 0 (20261007180503) para Victor, Arthur e JP. Cargo, áreas,
--   funções, vínculos e capacidades da conta NÃO mudam (continua cargo visualizador). Nenhuma função é recriada, então a
--   blindagem (blindagem.autorizar_guarda) não entra.
--
-- AUTORIA NO LOG
--   O gatilho log_master grava autor = auth.uid(). A migration roda como postgres, sem JWT; para o log dizer quem pediu,
--   o claim sub é posto como o Victor Hugo (81d2eaee…) só dentro desta transação (set_config local) e limpo no fim.
--   Mais 1 linha com o motivo (tabela master, acao motivo) e 1 com a senha padrão definida pela API admin do Auth
--   (tabela auth, acao senha, sem a senha), como nos registros da Jusy e do Marcos Paulo.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em acesso.master, 3 em acesso.log. índice: PK de acesso.master (perfil_id). frequência: uma vez.
--   repetição: nenhuma. reversão: delete da linha em acesso.master (rollback-qa-master.sql), gatilho registra no log.
--
-- IDEMPOTENTE: on conflict / where not exists.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select nome from public.perfis where id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465' and status = 'ativo')
     is distinct from 'QA Sessoes (conta de teste)' then
    raise exception '20261007qa: perfil d4b4f75f não é mais a conta ativa QA Sessoes (conta de teste)';
  end if;
  if not exists (select 1 from auth.users u where u.id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465'
                   and u.email = 'qa.sessoes@advmais.com' and u.deleted_at is null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261007qa: conta do Auth da QA Sessoes não confere (e-mail, excluída ou banida)';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo' then
    raise exception '20261007qa: autor esperado (Victor Hugo) não confere';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

insert into acesso.master (perfil_id, criado_por)
values ('d4b4f75f-582d-4a41-a4bd-93ec87748465', '81d2eaee-cce1-4058-8714-439b0fc6f970')
on conflict (perfil_id) do nothing;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', null,
       jsonb_build_object('motivo', 'conta de teste master para o JP testar a tela de acesso, pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007qa', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465'
                     and tabela = 'master' and acao = 'motivo');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'auth', 'senha', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', null,
       jsonb_build_object('motivo', 'senha padrão de testes definida pela API admin do Auth a pedido do Victor 07/10 (a senha anterior não era conhecida)',
                          'login_testado', true, 'registrado_por', 'migration 20261007qa', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465' and tabela = 'auth');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if (select count(*) from acesso.master) <> 4
     or not exists (select 1 from acesso.master where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465') then
    raise exception '20261007qa: esperava 4 masters, com a QA Sessoes';
  end if;
  if (select cargo from public.perfis where id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465') is distinct from 'visualizador' then
    raise exception '20261007qa: o cargo da QA Sessoes não deveria mudar';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '2 depois1', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';

-- ===== PASSADA 2 (idempotência) =====
-- 20261007qa: níveis de acesso, a conta de teste "QA Sessoes (conta de teste)" (perfil d4b4f75f…, qa.sessoes@advmais.com)
-- vira MASTER, para o JP testar a tela de níveis de acesso com a flag NEXT_PUBLIC_ACESSO_V2. Pedido do Victor Hugo em
-- 07/10/2026 ("conta de teste master para o JP testar a tela de acesso").
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007qa_ensaio.sql. Relatório: 20261007qa.explain.md.
--
-- POR QUE
--   A tela de acesso (gestão de vínculos e capacidades) só abre para master. O JP precisa testar com uma conta que não é
--   de pessoa real. A conta QA Sessoes é do agente de teste do JP (palavra do Victor, decisoes-maestro.md item 10).
--   Caminho oficial: linha em acesso.master, o mesmo da fase 0 (20261007180503) para Victor, Arthur e JP. Cargo, áreas,
--   funções, vínculos e capacidades da conta NÃO mudam (continua cargo visualizador). Nenhuma função é recriada, então a
--   blindagem (blindagem.autorizar_guarda) não entra.
--
-- AUTORIA NO LOG
--   O gatilho log_master grava autor = auth.uid(). A migration roda como postgres, sem JWT; para o log dizer quem pediu,
--   o claim sub é posto como o Victor Hugo (81d2eaee…) só dentro desta transação (set_config local) e limpo no fim.
--   Mais 1 linha com o motivo (tabela master, acao motivo) e 1 com a senha padrão definida pela API admin do Auth
--   (tabela auth, acao senha, sem a senha), como nos registros da Jusy e do Marcos Paulo.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em acesso.master, 3 em acesso.log. índice: PK de acesso.master (perfil_id). frequência: uma vez.
--   repetição: nenhuma. reversão: delete da linha em acesso.master (rollback-qa-master.sql), gatilho registra no log.
--
-- IDEMPOTENTE: on conflict / where not exists.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select nome from public.perfis where id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465' and status = 'ativo')
     is distinct from 'QA Sessoes (conta de teste)' then
    raise exception '20261007qa: perfil d4b4f75f não é mais a conta ativa QA Sessoes (conta de teste)';
  end if;
  if not exists (select 1 from auth.users u where u.id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465'
                   and u.email = 'qa.sessoes@advmais.com' and u.deleted_at is null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261007qa: conta do Auth da QA Sessoes não confere (e-mail, excluída ou banida)';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo' then
    raise exception '20261007qa: autor esperado (Victor Hugo) não confere';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

insert into acesso.master (perfil_id, criado_por)
values ('d4b4f75f-582d-4a41-a4bd-93ec87748465', '81d2eaee-cce1-4058-8714-439b0fc6f970')
on conflict (perfil_id) do nothing;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', null,
       jsonb_build_object('motivo', 'conta de teste master para o JP testar a tela de acesso, pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007qa', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465'
                     and tabela = 'master' and acao = 'motivo');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'auth', 'senha', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', null,
       jsonb_build_object('motivo', 'senha padrão de testes definida pela API admin do Auth a pedido do Victor 07/10 (a senha anterior não era conhecida)',
                          'login_testado', true, 'registrado_por', 'migration 20261007qa', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465' and tabela = 'auth');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if (select count(*) from acesso.master) <> 4
     or not exists (select 1 from acesso.master where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465') then
    raise exception '20261007qa: esperava 4 masters, com a QA Sessoes';
  end if;
  if (select cargo from public.perfis where id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465') is distinct from 'visualizador' then
    raise exception '20261007qa: o cargo da QA Sessoes não deveria mudar';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '3 depois2', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois2', coalesce(jsonb_agg(jsonb_build_object('perfil', a.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> a.key -> g.key)), '[]')::text
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois2') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois2 perfis', coalesce(string_agg(distinct a.key, ', '), 'nenhum')
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois2') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha) select 'dif antes x depois2 guardas na sonda', (select count(*) from jsonb_object_keys((select linha::jsonb -> 'QA Sessoes (conta de teste) #d4b4' from pg_temp._z_out where passo = '1 antes')))::text;
insert into pg_temp._z_out (passo, linha) select 'dif antes x depois2 perfis ativos', (select count(*) from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '1 antes')))::text;
insert into pg_temp._z_out (passo, linha) select 'masters', string_agg(p.nome, ', ' order by p.nome) from acesso.master m join public.perfis p on p.id = m.perfil_id;
insert into pg_temp._z_out (passo, linha) select 'log QA', coalesce(jsonb_agg(jsonb_build_object('autor', (select nome from public.perfis where id = l.autor), 'tabela', l.tabela, 'acao', l.acao, 'motivo', l.depois ->> 'motivo') order by l.id), '[]')::text from acesso.log l where l.perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465';
insert into pg_temp._z_out (passo, linha) select 'cargo QA e admin/dev ativos', jsonb_build_object('cargo_qa', (select cargo from public.perfis where id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465'), 'admin_dev_ativos', (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin','dev')))::text;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 depois: QA gp_meu_acesso', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', 'select public.gp_meu_acesso()::text');
insert into pg_temp._z_out (passo, linha) select '1 depois: QA acesso_listar', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', $q$select jsonb_build_object('masters', jsonb_array_length(public.acesso_listar() -> 'masters'), 'vinculos', jsonb_array_length(public.acesso_listar() -> 'vinculos'))::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: Luis acesso_listar', pg_temp.tenta('9d5fb8e7-f61e-459d-be04-d103ec783c08', 'select left(public.acesso_listar()::text, 40)');
reset role;
select set_config('request.jwt.claims', '', true);
set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', 'role', 'authenticated')::text, true);
do $e$ declare r record; i int; begin
  for i in 1..2 loop
    for r in execute 'explain (analyze, buffers) select public.gp_meu_acesso()' loop
      insert into pg_temp._z_out (passo, linha) values ('explain ' || i, r."QUERY PLAN");
    end loop;
  end loop;
end $e$;
reset role;
select set_config('request.jwt.claims', '', true);

-- ===== ROLLBACK =====
-- Rollback de 20261007qa: a QA Sessoes deixa de ser master. O gatilho log_master registra o delete (autor Victor Hugo).
-- A senha não volta (a anterior não era conhecida); se quiser fechar a conta, trocar a senha ou banir pela API admin.
set local lock_timeout = '3s';
set local statement_timeout = '10s';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);
delete from acesso.master where perfil_id = 'd4b4f75f-582d-4a41-a4bd-93ec87748465';
insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
values ('81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'd4b4f75f-582d-4a41-a4bd-93ec87748465', null,
        jsonb_build_object('motivo', 'rollback de 20261007qa: QA Sessoes deixa de ser master', 'registrado_em', now()));
select set_config('request.jwt.claims', '', true);
do $c$ begin
  if (select count(*) from acesso.master) <> 3 then raise exception 'rollback 20261007qa: esperava 3 masters'; end if;
end $c$;

insert into pg_temp._z_out (passo, linha) select '4 depois do rollback', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback', coalesce(jsonb_agg(jsonb_build_object('perfil', a.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> a.key -> g.key)), '[]')::text
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '4 depois do rollback') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback perfis', coalesce(string_agg(distinct a.key, ', '), 'nenhum')
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '4 depois do rollback') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha) select 'dif antes x rollback guardas na sonda', (select count(*) from jsonb_object_keys((select linha::jsonb -> 'QA Sessoes (conta de teste) #d4b4' from pg_temp._z_out where passo = '1 antes')))::text;
insert into pg_temp._z_out (passo, linha) select 'dif antes x rollback perfis ativos', (select count(*) from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '1 antes')))::text;
insert into pg_temp._z_out (passo, linha) select 'masters depois do rollback', string_agg(p.nome, ', ' order by p.nome) from acesso.master m join public.perfis p on p.id = m.perfil_id;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '2 rollback: QA gp_meu_acesso', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', 'select public.gp_meu_acesso()::text');
insert into pg_temp._z_out (passo, linha) select '2 rollback: QA acesso_listar', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', $q$select jsonb_build_object('masters', jsonb_array_length(public.acesso_listar() -> 'masters'), 'vinculos', jsonb_array_length(public.acesso_listar() -> 'vinculos'))::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: Luis acesso_listar', pg_temp.tenta('9d5fb8e7-f61e-459d-be04-d103ec783c08', 'select left(public.acesso_listar()::text, 40)');
reset role;
select set_config('request.jwt.claims', '', true);

set local statement_timeout = '60s';
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
