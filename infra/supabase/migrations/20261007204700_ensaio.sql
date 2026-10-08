-- 08/10/2026: tirada a prova gps.eh_equipe() da sonda e a chave 'gps' virou 'admin_ou_editar_educacional' (o GPS
-- tem guarda própria, gps.eh_admin, e não lê mais o acesso central; ver docs/niveis-de-acesso-banco.md). O resto não mudou.
-- Ensaio de 20261007204700_acesso_qa_trafego_editor.sql: a conta de teste QA Tráfego (6e8d878d…) vira membro do Tráfego.
-- Sonda de 32 guardas (a mesma da fase 3 e de 20261007204002) em todos os perfis ativos antes, depois de 2 passadas e
-- depois do rollback; provas com o JWT da QA Tráfego (A); prova do pedido (B) com a QA Sessoes (master) alterando e
-- revertendo o Robô de teste E2E (Financeiro); explain (analyze, buffers) 2x.
-- Esperado: nenhum perfil existente muda; aparece 1 perfil novo (QA Tráfego #6e8d) que edita marketing/trafego e nada
-- mais, sem financeiro, sem CPF, sem gestão de acesso (42501); rollback devolve a sonda igual à de antes (0 diferença,
-- 0 perfil novo). Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste.
-- Gerado por um script a partir do arquivo da migration (as passadas são cópia exata dele).
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
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
select set_config('ensaio.vid', (select min(id) from acesso.vinculo where vigente_ate is null)::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A gp_meu_acesso', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.gp_meu_acesso()::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A financeiro (gp_pode_ver_financeiro, operar, ver depto, cpf)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'ver_depto_financeiro', public.gp_acesso_pode_ver('financeiro', null), 'cpf', public.gp_pode_ver_cpf())::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A edita (gp_acesso_pode_editar)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('marketing/trafego', public.gp_acesso_pode_editar('marketing', 'trafego'), 'marketing/web', public.gp_acesso_pode_editar('marketing', 'web'), 'marketing', public.gp_acesso_pode_editar('marketing', null), 'financeiro', public.gp_acesso_pode_editar('financeiro', null), 'infra', public.gp_acesso_pode_editar('infra', null))::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_listar', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select left(public.acesso_listar()::text, 40)$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_vincular no Robo (marketing/web)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'marketing', 'web', 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_vincular em si (financeiro)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro', null, 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_capacidade_definir financeiro.ver em si', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_capacidade_definir('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro.ver', true)::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_desvincular (vínculo de outra pessoa)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_desvincular(current_setting('ensaio.vid')::bigint)::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A acesso_perfil_atualizar_como (authenticated)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_perfil_atualizar_como('6e8d878d-086c-4b12-bef7-c424d89d85b6', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "negado"}'::jsonb)::text$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A update proprio cargo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set cargo = 'gestor' where id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A update nome do Robo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set nome = 'x' where id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '0 antes (pendente): A insert em acesso.master', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (insert into acesso.master (perfil_id) values ('6e8d878d-086c-4b12-bef7-c424d89d85b6') returning 1) select count(*)::text from u$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- ===== PASSADA 1 =====
-- 20261007204700: níveis de acesso, conta de teste "QA Tráfego (conta de teste)" (perfil 6e8d878d…, qa.trafego@advmais.com)
-- vira MEMBRO do Tráfego (marketing/trafego, papel membro = edita a área), sem financeiro, sem master, sem admin.
-- Pedido do Victor Hugo em 07/10/2026: o JP precisa provar na tela (flag NEXT_PUBLIC_ACESSO_V2) que um editor de área
-- não vê o Financeiro e não dá acesso a ninguém, sem usar pessoa real.
--
-- STATUS: ver 20261007204700.explain.md (a linha de STATUS de lá é a fonte; este arquivo vai igual para schema_migrations).
-- Ensaio: 20261007204700_ensaio.sql.
--
-- POR QUE ESTA CONTA E NÃO UMA QUE JÁ EXISTE
--   Contas de teste no banco em 07/10: "QA Sessoes (conta de teste)" (é master desde 20261007204002) e "Robô de teste E2E
--   (Financeiro)" (tem financeiro.ver, é o usuário dos testes e2e do Financeiro, web/e2e). Usar qualquer uma das duas para
--   "editor sem financeiro" mudaria o propósito dela. A conta do Auth foi criada às 20:46 UTC pela API admin do Auth
--   (e-mail confirmado, user_metadata só com o nome, igual ao Robô); o gatilho handle_new_user criou o perfil pendente e
--   visualizador, e o rede.handle_new_user criou rede.perfis pendente/aluno, como acontece com todo convite da rota
--   /api/admin/usuarios.
--
-- CAMINHO OFICIAL
--   1. Ativar o perfil pela RPC da rota de Usuários (public.acesso_perfil_atualizar_como), autor Victor Hugo, o mesmo
--      patch que o POST de /api/admin/usuarios manda no acesso v2 ({nome, status: 'ativo'}).
--   2. Vínculo pela RPC de gestão (public.acesso_vincular), que exige master: o claim sub é o Victor Hugo (81d2eaee…),
--      só dentro desta transação (set_config local), limpo no fim. O gatilho log_vinculo grava autor = Victor.
--   Cargo (visualizador), áreas, funções e CPF NÃO mudam; nenhuma capacidade; nenhuma função recriada (sem blindagem).
--   Igual aos membros do Tráfego que já existem (renan, emmanuel: visualizador, sem áreas, vínculo marketing/trafego membro).
--
-- AS 5 PERGUNTAS
--   escala: 1 update em perfis, 1 linha em acesso.vinculo, 4 em acesso.log. índice: PK de perfis e de vinculo.
--   frequência: uma vez. repetição: idempotente. reversão: explain §5 (desvincular + status negado; apagar no Auth).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.nome = 'QA Tráfego (conta de teste)'
                    and p.email = 'qa.trafego@advmais.com' and p.cargo = 'visualizador' and p.status in ('pendente', 'ativo')
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil 6e8d878d não é a conta de teste QA Tráfego como esperado';
  end if;
  if not exists (select 1 from auth.users u where u.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                   and u.email = 'qa.trafego@advmais.com' and u.deleted_at is null and u.email_confirmed_at is not null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261007204700: conta do Auth da QA Tráfego não confere (e-mail, confirmação, excluída ou banida)';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.excecao_admin where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master, exceção nem ter capacidade';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo'
     or not exists (select 1 from acesso.master where perfil_id = '81d2eaee-cce1-4058-8714-439b0fc6f970') then
    raise exception '20261007204700: autor esperado (Victor Hugo, master) não confere';
  end if;
  if not exists (select 1 from acesso.area where departamento = 'marketing' and key = 'trafego') then
    raise exception '20261007204700: área marketing/trafego não existe';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

do $a$
declare r jsonb;
begin
  r := public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '6e8d878d-086c-4b12-bef7-c424d89d85b6',
                                           '{"nome": "QA Tráfego (conta de teste)", "status": "ativo"}'::jsonb);
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: ativar perfil falhou: %', r; end if;
  r := public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'marketing', 'trafego', 'membro');
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: vincular falhou: %', r; end if;
end
$a$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'vinculo', 'motivo', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta de teste membro do Tráfego, sem financeiro, para o JP testar a tela de acesso, pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                     and tabela = 'vinculo' and acao = 'motivo');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'auth', 'senha', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta criada pela API admin do Auth com a senha padrão de testes do @advmais, a pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and tabela = 'auth');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.status = 'ativo' and p.cargo = 'visualizador'
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil da QA Tráfego não ficou ativo/visualizador sem áreas';
  end if;
  if (select count(*) from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null) <> 1
     or not exists (select 1 from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null
                      and departamento = 'marketing' and area = 'trafego' and papel = 'membro') then
    raise exception '20261007204700: esperava 1 vínculo vigente marketing/trafego membro';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master nem ter capacidade';
  end if;
end
$c$;


-- ===== PASSADA 2 (idempotência) =====
-- 20261007204700: níveis de acesso, conta de teste "QA Tráfego (conta de teste)" (perfil 6e8d878d…, qa.trafego@advmais.com)
-- vira MEMBRO do Tráfego (marketing/trafego, papel membro = edita a área), sem financeiro, sem master, sem admin.
-- Pedido do Victor Hugo em 07/10/2026: o JP precisa provar na tela (flag NEXT_PUBLIC_ACESSO_V2) que um editor de área
-- não vê o Financeiro e não dá acesso a ninguém, sem usar pessoa real.
--
-- STATUS: ver 20261007204700.explain.md (a linha de STATUS de lá é a fonte; este arquivo vai igual para schema_migrations).
-- Ensaio: 20261007204700_ensaio.sql.
--
-- POR QUE ESTA CONTA E NÃO UMA QUE JÁ EXISTE
--   Contas de teste no banco em 07/10: "QA Sessoes (conta de teste)" (é master desde 20261007204002) e "Robô de teste E2E
--   (Financeiro)" (tem financeiro.ver, é o usuário dos testes e2e do Financeiro, web/e2e). Usar qualquer uma das duas para
--   "editor sem financeiro" mudaria o propósito dela. A conta do Auth foi criada às 20:46 UTC pela API admin do Auth
--   (e-mail confirmado, user_metadata só com o nome, igual ao Robô); o gatilho handle_new_user criou o perfil pendente e
--   visualizador, e o rede.handle_new_user criou rede.perfis pendente/aluno, como acontece com todo convite da rota
--   /api/admin/usuarios.
--
-- CAMINHO OFICIAL
--   1. Ativar o perfil pela RPC da rota de Usuários (public.acesso_perfil_atualizar_como), autor Victor Hugo, o mesmo
--      patch que o POST de /api/admin/usuarios manda no acesso v2 ({nome, status: 'ativo'}).
--   2. Vínculo pela RPC de gestão (public.acesso_vincular), que exige master: o claim sub é o Victor Hugo (81d2eaee…),
--      só dentro desta transação (set_config local), limpo no fim. O gatilho log_vinculo grava autor = Victor.
--   Cargo (visualizador), áreas, funções e CPF NÃO mudam; nenhuma capacidade; nenhuma função recriada (sem blindagem).
--   Igual aos membros do Tráfego que já existem (renan, emmanuel: visualizador, sem áreas, vínculo marketing/trafego membro).
--
-- AS 5 PERGUNTAS
--   escala: 1 update em perfis, 1 linha em acesso.vinculo, 4 em acesso.log. índice: PK de perfis e de vinculo.
--   frequência: uma vez. repetição: idempotente. reversão: explain §5 (desvincular + status negado; apagar no Auth).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.nome = 'QA Tráfego (conta de teste)'
                    and p.email = 'qa.trafego@advmais.com' and p.cargo = 'visualizador' and p.status in ('pendente', 'ativo')
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil 6e8d878d não é a conta de teste QA Tráfego como esperado';
  end if;
  if not exists (select 1 from auth.users u where u.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                   and u.email = 'qa.trafego@advmais.com' and u.deleted_at is null and u.email_confirmed_at is not null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261007204700: conta do Auth da QA Tráfego não confere (e-mail, confirmação, excluída ou banida)';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.excecao_admin where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master, exceção nem ter capacidade';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo'
     or not exists (select 1 from acesso.master where perfil_id = '81d2eaee-cce1-4058-8714-439b0fc6f970') then
    raise exception '20261007204700: autor esperado (Victor Hugo, master) não confere';
  end if;
  if not exists (select 1 from acesso.area where departamento = 'marketing' and key = 'trafego') then
    raise exception '20261007204700: área marketing/trafego não existe';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

do $a$
declare r jsonb;
begin
  r := public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '6e8d878d-086c-4b12-bef7-c424d89d85b6',
                                           '{"nome": "QA Tráfego (conta de teste)", "status": "ativo"}'::jsonb);
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: ativar perfil falhou: %', r; end if;
  r := public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'marketing', 'trafego', 'membro');
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: vincular falhou: %', r; end if;
end
$a$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'vinculo', 'motivo', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta de teste membro do Tráfego, sem financeiro, para o JP testar a tela de acesso, pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                     and tabela = 'vinculo' and acao = 'motivo');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'auth', 'senha', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta criada pela API admin do Auth com a senha padrão de testes do @advmais, a pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and tabela = 'auth');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.status = 'ativo' and p.cargo = 'visualizador'
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil da QA Tráfego não ficou ativo/visualizador sem áreas';
  end if;
  if (select count(*) from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null) <> 1
     or not exists (select 1 from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null
                      and departamento = 'marketing' and area = 'trafego' and papel = 'membro') then
    raise exception '20261007204700: esperava 1 vínculo vigente marketing/trafego membro';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master nem ter capacidade';
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
select 'dif antes x depois2: perfis que mudaram', coalesce(string_agg(distinct a.key, ', '), 'nenhum')
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois2') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois2: perfis novos', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '3 depois2')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '1 antes') ? k);
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois2: perfis que sumiram', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '1 antes')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '3 depois2') ? k);
insert into pg_temp._z_out (passo, linha) select '3 depois2: perfis ativos e guardas por perfil', (select count(*) from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '3 depois2')))::text || ' perfis, ' || (select count(*) from jsonb_object_keys((select linha::jsonb -> 'Victor Hugo #81d2' from pg_temp._z_out where passo = '3 depois2')))::text || ' guardas';
insert into pg_temp._z_out (passo, linha) select 'log A', coalesce(jsonb_agg(jsonb_build_object('autor', (select nome from public.perfis where id = l.autor), 'tabela', l.tabela, 'acao', l.acao, 'via', l.depois ->> 'via', 'status', l.depois ->> 'status', 'vinculo', l.depois ->> 'departamento' || '/' || coalesce(l.depois ->> 'area', '-') || ':' || coalesce(l.depois ->> 'papel', ''), 'motivo', l.depois ->> 'motivo') order by l.id), '[]')::text from acesso.log l where l.perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6';
insert into pg_temp._z_out (passo, linha) select 'A no banco', jsonb_build_object('status', status, 'cargo', cargo, 'areas', areas, 'funcoes', funcoes, 'cpf', pode_ver_cpf_completo, 'master', exists(select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'), 'excecao', exists(select 1 from acesso.excecao_admin where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'), 'caps', (select jsonb_agg(chave) from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'), 'vinculos', (select jsonb_agg(departamento || '/' || coalesce(area, '-') || ':' || papel) from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null))::text from public.perfis where id = '6e8d878d-086c-4b12-bef7-c424d89d85b6';
insert into pg_temp._z_out (passo, linha) select 'masters', string_agg(p.nome, ', ' order by p.nome) from acesso.master m join public.perfis p on p.id = m.perfil_id;
select set_config('ensaio.vid', (select min(id) from acesso.vinculo where vigente_ate is null)::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 depois: A gp_meu_acesso', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.gp_meu_acesso()::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A financeiro (gp_pode_ver_financeiro, operar, ver depto, cpf)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'ver_depto_financeiro', public.gp_acesso_pode_ver('financeiro', null), 'cpf', public.gp_pode_ver_cpf())::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A edita (gp_acesso_pode_editar)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('marketing/trafego', public.gp_acesso_pode_editar('marketing', 'trafego'), 'marketing/web', public.gp_acesso_pode_editar('marketing', 'web'), 'marketing', public.gp_acesso_pode_editar('marketing', null), 'financeiro', public.gp_acesso_pode_editar('financeiro', null), 'infra', public.gp_acesso_pode_editar('infra', null))::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_listar', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select left(public.acesso_listar()::text, 40)$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_vincular no Robo (marketing/web)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'marketing', 'web', 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_vincular em si (financeiro)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro', null, 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_capacidade_definir financeiro.ver em si', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_capacidade_definir('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro.ver', true)::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_desvincular (vínculo de outra pessoa)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_desvincular(current_setting('ensaio.vid')::bigint)::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A acesso_perfil_atualizar_como (authenticated)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_perfil_atualizar_como('6e8d878d-086c-4b12-bef7-c424d89d85b6', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "negado"}'::jsonb)::text$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A update proprio cargo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set cargo = 'gestor' where id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A update nome do Robo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set nome = 'x' where id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '1 depois: A insert em acesso.master', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (insert into acesso.master (perfil_id) values ('6e8d878d-086c-4b12-bef7-c424d89d85b6') returning 1) select count(*)::text from u$q$);
reset role;
select set_config('request.jwt.claims', '', true);
do $r$ begin
  begin
    perform public.acesso_perfil_atualizar_como('6e8d878d-086c-4b12-bef7-c424d89d85b6', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "negado"}'::jsonb);
    insert into pg_temp._z_out (passo, linha) values ('1 depois: RPC da rota com autor A no Robo', 'passou (ERRADO)');
  exception when others then
    insert into pg_temp._z_out (passo, linha) values ('1 depois: RPC da rota com autor A no Robo', sqlstate || ' ' || sqlerrm);
  end;
end $r$;
insert into pg_temp._z_out (passo, linha) select '1 depois: status do Robo', status from public.perfis where id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8';
set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', '6e8d878d-086c-4b12-bef7-c424d89d85b6', 'role', 'authenticated')::text, true);
do $e$ declare r record; i int; begin
  for i in 1..2 loop
    for r in execute 'explain (analyze, buffers) select public.gp_meu_acesso()' loop
      insert into pg_temp._z_out (passo, linha) values ('explain ' || i, r."QUERY PLAN");
    end loop;
  end loop;
end $e$;
reset role;
select set_config('request.jwt.claims', '', true);
-- ===== (B): QA Sessoes (master) altera e reverte o Robô, autor no acesso.log =====
do $b$ declare r jsonb; n0 bigint := (select coalesce(max(id), 0) from acesso.log); begin
  r := public.acesso_perfil_atualizar_como('d4b4f75f-582d-4a41-a4bd-93ec87748465', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "pendente"}'::jsonb);
  r := public.acesso_perfil_atualizar_como('d4b4f75f-582d-4a41-a4bd-93ec87748465', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "ativo"}'::jsonb);
  insert into pg_temp._z_out (passo, linha)
  select 'B: log da rota (status ida e volta)', jsonb_agg(jsonb_build_object('autor', (select nome from public.perfis where id = l.autor), 'tabela', l.tabela, 'acao', l.acao, 'antes', l.antes ->> 'status', 'depois', l.depois ->> 'status', 'via', l.depois ->> 'via') order by l.id)::text
    from acesso.log l where l.id > n0 and l.perfil_id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8';
end $b$;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'B: QA vincula Robo marketing/web', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', $q$select public.acesso_vincular('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'marketing', 'web', 'membro')::text$q$);
reset role;
select set_config('ensaio.vid', (select id from acesso.vinculo where perfil_id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' and departamento = 'marketing' and area = 'web' and vigente_ate is null)::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'B: QA desvincula Robo marketing/web', pg_temp.tenta('d4b4f75f-582d-4a41-a4bd-93ec87748465', $q$select public.acesso_desvincular(current_setting('ensaio.vid')::bigint)::text$q$);
reset role;
select set_config('request.jwt.claims', '', true);
insert into pg_temp._z_out (passo, linha)
select 'B: log do vinculo', jsonb_agg(jsonb_build_object('autor', (select nome from public.perfis where id = l.autor), 'tabela', l.tabela, 'acao', l.acao, 'vigente_ate_antes', l.antes ->> 'vigente_ate', 'vigente_ate_depois', l.depois ->> 'vigente_ate') order by l.id)::text
  from acesso.log l where l.perfil_id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' and l.tabela = 'vinculo' and l.quando = now();
insert into pg_temp._z_out (passo, linha) select 'B: Robo depois da ida e volta', jsonb_build_object('status', status, 'cargo', cargo, 'areas', areas, 'vinculos_vigentes', (select count(*) from acesso.vinculo where perfil_id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' and vigente_ate is null), 'caps', (select jsonb_agg(chave) from acesso.capacidade where perfil_id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8'))::text from public.perfis where id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8';

insert into pg_temp._z_out (passo, linha) select '3b depois de B', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois de B', coalesce(jsonb_agg(jsonb_build_object('perfil', a.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> a.key -> g.key)), '[]')::text
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '3b depois de B') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois de B: perfis que mudaram', coalesce(string_agg(distinct a.key, ', '), 'nenhum')
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '3b depois de B') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois de B: perfis novos', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '3b depois de B')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '1 antes') ? k);
insert into pg_temp._z_out (passo, linha)
select 'dif antes x depois de B: perfis que sumiram', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '1 antes')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '3b depois de B') ? k);
insert into pg_temp._z_out (passo, linha) select '3b depois de B: perfis ativos e guardas por perfil', (select count(*) from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '3b depois de B')))::text || ' perfis, ' || (select count(*) from jsonb_object_keys((select linha::jsonb -> 'Victor Hugo #81d2' from pg_temp._z_out where passo = '3b depois de B')))::text || ' guardas';
-- ===== ROLLBACK (o mesmo de rollback-qa-trafego.sql) =====
set local lock_timeout = '3s';
set local statement_timeout = '10s';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);
do $rb$ declare r jsonb; v bigint; begin
  for v in select id from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null loop
    r := public.acesso_desvincular(v);
  end loop;
  r := public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '6e8d878d-086c-4b12-bef7-c424d89d85b6', '{"status": "negado"}'::jsonb);
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values ('81d2eaee-cce1-4058-8714-439b0fc6f970', 'vinculo', 'motivo', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
          jsonb_build_object('motivo', 'rollback de 20261007204700: QA Tráfego sem vínculo e negada', 'registrado_em', now()));
end $rb$;
select set_config('request.jwt.claims', '', true);
do $c$ begin
  if exists (select 1 from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null)
     or (select status from public.perfis where id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') <> 'negado' then
    raise exception 'rollback 20261007204700: QA Tráfego ainda tem vínculo ou não está negada';
  end if;
end $c$;

insert into pg_temp._z_out (passo, linha) select '4 depois do rollback', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback', coalesce(jsonb_agg(jsonb_build_object('perfil', a.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> a.key -> g.key)), '[]')::text
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '4 depois do rollback') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback: perfis que mudaram', coalesce(string_agg(distinct a.key, ', '), 'nenhum')
  from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') x
  cross join lateral jsonb_each(x.j) a cross join lateral jsonb_each(a.value) g
  cross join (select linha::jsonb j from pg_temp._z_out where passo = '4 depois do rollback') y
 where (y.j -> a.key -> g.key) is distinct from g.value;
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback: perfis novos', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '4 depois do rollback')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '1 antes') ? k);
insert into pg_temp._z_out (passo, linha)
select 'dif antes x rollback: perfis que sumiram', coalesce(string_agg(k, ', '), 'nenhum')
  from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '1 antes')) k
 where not ((select linha::jsonb from pg_temp._z_out where passo = '4 depois do rollback') ? k);
insert into pg_temp._z_out (passo, linha) select '4 depois do rollback: perfis ativos e guardas por perfil', (select count(*) from jsonb_object_keys((select linha::jsonb from pg_temp._z_out where passo = '4 depois do rollback')))::text || ' perfis, ' || (select count(*) from jsonb_object_keys((select linha::jsonb -> 'Victor Hugo #81d2' from pg_temp._z_out where passo = '4 depois do rollback')))::text || ' guardas';
select set_config('ensaio.vid', (select min(id) from acesso.vinculo where vigente_ate is null)::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '2 rollback: A gp_meu_acesso', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.gp_meu_acesso()::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A financeiro (gp_pode_ver_financeiro, operar, ver depto, cpf)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'ver_depto_financeiro', public.gp_acesso_pode_ver('financeiro', null), 'cpf', public.gp_pode_ver_cpf())::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A edita (gp_acesso_pode_editar)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select jsonb_build_object('marketing/trafego', public.gp_acesso_pode_editar('marketing', 'trafego'), 'marketing/web', public.gp_acesso_pode_editar('marketing', 'web'), 'marketing', public.gp_acesso_pode_editar('marketing', null), 'financeiro', public.gp_acesso_pode_editar('financeiro', null), 'infra', public.gp_acesso_pode_editar('infra', null))::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_listar', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select left(public.acesso_listar()::text, 40)$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_vincular no Robo (marketing/web)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'marketing', 'web', 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_vincular em si (financeiro)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro', null, 'membro')::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_capacidade_definir financeiro.ver em si', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_capacidade_definir('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'financeiro.ver', true)::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_desvincular (vínculo de outra pessoa)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_desvincular(current_setting('ensaio.vid')::bigint)::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A acesso_perfil_atualizar_como (authenticated)', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select public.acesso_perfil_atualizar_como('6e8d878d-086c-4b12-bef7-c424d89d85b6', '6f0c31a2-26cf-4ef0-a608-b482b1e92db8', '{"status": "negado"}'::jsonb)::text$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A update proprio cargo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set cargo = 'gestor' where id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A update nome do Robo', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (update public.perfis set nome = 'x' where id = '6f0c31a2-26cf-4ef0-a608-b482b1e92db8' returning 1) select count(*)::text from u$q$);
insert into pg_temp._z_out (passo, linha) select '2 rollback: A insert em acesso.master', pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$with u as (insert into acesso.master (perfil_id) values ('6e8d878d-086c-4b12-bef7-c424d89d85b6') returning 1) select count(*)::text from u$q$);
reset role;
select set_config('request.jwt.claims', '', true);
insert into pg_temp._z_out (passo, linha) select 'masters depois do rollback', string_agg(p.nome, ', ' order by p.nome) from acesso.master m join public.perfis p on p.id = m.perfil_id;

set local statement_timeout = '60s';
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
