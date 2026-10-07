-- 20261007175055 (APLICADA) — salvar a Distribuição dava "permission denied for function confere_distribuicao"
--
-- Causa: distribuicao_soma / funil_distribuicao_soma são CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED.
-- Rodam no COMMIT, fora do SECURITY DEFINER de public.crm_salvar_distribuicao, com o papel do usuário
-- (authenticated). crm.tg_distribuicao_soma era SECURITY INVOKER e chama crm.confere_distribuicao, que só
-- o postgres executa → 42501 para todo gestor que salvasse.
-- Correção: a função do trigger passa a SECURITY DEFINER (dono postgres). Função de trigger não é chamável
-- por RPC (retorna trigger), e o EXECUTE de confere_distribuicao continua fechado.
-- Sem query nova: mesmo corpo, só o contexto de segurança muda (nada a medir com explain).
-- Reversão: alter function crm.tg_distribuicao_soma() security invoker;

alter function crm.tg_distribuicao_soma() security definer;
revoke all on function crm.tg_distribuicao_soma() from public, anon, authenticated;
