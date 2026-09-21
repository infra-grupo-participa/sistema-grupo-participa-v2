-- Fecha a leitura das tabelas internas para quem não é equipe.
-- Aplicada em produção em 21/09/2026 (MCP Supabase), replicada aqui para versionamento.
--
-- Mesma classe do vazamento de thb_placas_solicitacoes: policies SELECT com
-- qual = true para `authenticated`, numa auth.users compartilhada pelos 7 sistemas.
--
-- Medido com JWT de aluno ANTES:  auditoria 81 · ciclos 10 · reprovacoes 37 ·
--   audit_log 1538 · sys_events 641 · templates 7 · agend_logs 72
-- Medido DEPOIS: todos 0. Equipe mantém todos os números originais.
--
-- audit_log guarda valor_anterior/valor_novo de QUALQUER campo do aluno (CPF,
-- telefone, endereço). reprovacoes guarda declaracao_url e faturamento.
--
-- NÃO alteradas de propósito: thb_turmas (54), app_central (1), tags_produtos (13)
-- — catálogo sem dado pessoal, lido pelos portais de aluno dos outros sistemas.
-- thb_alunos e perfis já retornam 0 para não-equipe via outras policies restritivas.

drop policy if exists "autenticados podem ler" on public.thb_placas_auditoria;
create policy placas_auditoria_select_equipe on public.thb_placas_auditoria
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists "autenticados leem ciclos" on public.thb_placas_ciclos;
create policy placas_ciclos_select_equipe on public.thb_placas_ciclos
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists reprovacoes_select_auth on public.thb_placas_reprovacoes;
create policy reprovacoes_select_equipe on public.thb_placas_reprovacoes
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists alunos_audit_log_authenticated_select on public.thb_alunos_audit_log;
create policy alunos_audit_log_select_equipe on public.thb_alunos_audit_log
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists system_events_authenticated_select on public.thb_system_events;
create policy system_events_select_equipe on public.thb_system_events
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists placas_agendamento_logs_authenticated_select on public.thb_placas_agendamento_logs;
create policy placas_agendamento_logs_select_equipe on public.thb_placas_agendamento_logs
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists tpl_select_authenticated on public.templates_cargo;
create policy templates_cargo_select_equipe on public.templates_cargo
  for select to authenticated using (public.gp_eh_equipe());

drop policy if exists perm_select_authenticated on public.permissoes_usuario;
create policy permissoes_usuario_select_equipe on public.permissoes_usuario
  for select to authenticated using (public.gp_eh_equipe());
