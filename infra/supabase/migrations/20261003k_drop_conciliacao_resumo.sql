-- 20261003k — Remove fn_aluno_conciliacao_resumo (morta desde a tela da conciliação)
--
-- POR QUÊ (joao, veredito 30/09/2026): conciliacao.ts:223 conta no cliente a partir da lista (20261003h) e ninguém chama
--   o resumo. Continuava SECURITY DEFINER com grant a authenticated, reexecutando a conciliação inteira (~1,7 s) por
--   chamada: superfície e custo sem uso.
-- CHAMADORES (30/09): 0 no repo, 0 em pg_proc (fora ela mesma), 0 em cron.job, 0 dependentes. Criada hoje na 20261003e,
--   nenhum outro sistema a conhece.
-- REVERSÃO: recriar pelo corpo em 20261003e_aluno_conciliacao.sql.

drop function public.fn_aluno_conciliacao_resumo();
