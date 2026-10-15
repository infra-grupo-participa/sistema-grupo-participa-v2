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
