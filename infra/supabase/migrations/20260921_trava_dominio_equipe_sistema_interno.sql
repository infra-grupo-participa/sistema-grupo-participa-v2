-- Trava de acesso ao sistema interno (v2): só e-mail @advmais.com com perfil ativo.
-- Aplicada em produção em 21/09/2026 (MCP Supabase), replicada aqui para versionamento.
--
-- Motivo: auth.users é compartilhada pelos 7 sistemas do grupo. 11.011 logins de
-- aluno/lead sem perfil caíam no fallback 'visualizador' e enxergavam 188
-- solicitações de placa com nome, telefone, endereço, documento_nf e faturamento.
-- Medido com JWT real de usuário sem perfil e sem membro GPS: 188 linhas.
--
-- explain (analyze) da guarda: Index Scan using perfis_pkey, 0.099 ms, shared hit=2.
--
-- Contraprova: aluno 188 -> 0; admin da equipe mantém 188 placas e 1.861 alunos.

create or replace function public.gp_eh_equipe()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and p.email ilike '%@advmais.com'
  );
$function$;

comment on function public.gp_eh_equipe() is
  'Porteiro do sistema interno: perfil ativo E e-mail do dominio @advmais.com. '
  'auth.users e compartilhada pelos 7 sistemas — ter login NAO significa ser equipe.';

revoke all on function public.gp_eh_equipe() from public, anon;
grant execute on function public.gp_eh_equipe() to authenticated;

-- placas_select_auth tinha qual = true: QUALQUER login autenticado dos 7 sistemas
-- lia as 188 solicitações. O acesso do próprio aluno ao seu processo NÃO passa por
-- aqui: é por token UUID via fn_placas_* (SECURITY DEFINER), que ignora RLS.
drop policy if exists placas_select_auth on public.thb_placas_solicitacoes;

create policy placas_select_equipe
  on public.thb_placas_solicitacoes
  for select
  to authenticated
  using (public.gp_eh_equipe());
