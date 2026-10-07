-- 20261007qa: níveis de acesso, a conta de teste "QA Sessoes (conta de teste)" (perfil d4b4f75f…, qa.sessoes@advmais.com)
-- vira MASTER, para o JP testar a tela de níveis de acesso com a flag NEXT_PUBLIC_ACESSO_V2. Pedido do Victor Hugo em
-- 07/10/2026 ("conta de teste master para o JP testar a tela de acesso").
--
-- STATUS: APLICADA em produção em 07/10/2026 às 20:40 UTC, versão 20261007204002 (nome acesso_master_qa_sessoes, era
-- 20261007qa), pelo aplica_sql.py aplicar + insert em supabase_migrations.schema_migrations na mesma transação; md5 gravado =
-- a66c0760fa337698e634595911cffeb4 = este arquivo antes desta troca de STATUS. Ensaio: 20261007204002_ensaio.sql.
-- Relatório: 20261007204002.explain.md.
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
