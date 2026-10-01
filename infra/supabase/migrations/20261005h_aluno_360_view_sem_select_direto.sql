-- 20261005h — Fecha o SELECT direto de authenticated em public.vw_aluno_360 (LGPD).
-- Achado do kirad na revisão da 20261005e, confirmado em 01/10/2026: a view não tem security_invoker
-- (roda como o dono, sem RLS) e authenticated tinha arwdDxtm nela. Qualquer conta logada da auth.users
-- compartilhada (11.080, só 40 da equipe) lia 1.902 alunos via /rest/v1/vw_aluno_360, contornando a
-- guarda gp_eh_equipe() de fn_aluno_360 / fn_aluno_360_safe (mesma classe do incidente de 28/09).
-- Ninguém do app lê a view direto (grep em web/: 0). Leitores legítimos seguem funcionando:
--   fn_aluno_360, fn_aluno_360_safe, rede.* e cs.fn_tag_hm_origem são SECURITY DEFINER (dono postgres);
--   disparos_ui_ro mantém o SELECT próprio; service_role mantém tudo.
revoke all on public.vw_aluno_360 from public, anon, authenticated;

-- REVERSÃO (reabre o vazamento — só com guarda equivalente no lugar):
--   grant select on public.vw_aluno_360 to authenticated;
