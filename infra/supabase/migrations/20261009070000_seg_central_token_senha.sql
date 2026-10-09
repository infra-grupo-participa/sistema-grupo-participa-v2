-- Segurança — fecha tomada de conta na Central de Projetos (09/10/2026, achado do kirad no lote 3).
-- central.criar_token_senha_autoatendimento(p_email, p_token_hash, p_ip) aceita um hash ESCOLHIDO por quem chama,
-- para qualquer e-mail, e central.definir_senha_com_token troca a senha de auth.users com o token correspondente.
-- Com a anon key, qualquer pessoa definia a senha de qualquer aluno da Central (173, 6 deles da equipe @advmais.com).
-- Medido: 52 tokens no total, 0 nos últimos 7 dias, último em 21/09; nenhum uso com cara de abuso (todos 30 s–11 min).
-- Efeito colateral aceito: o "esqueci a senha" self-service da Central para até o servidor chamar com service_role
-- ou a função gerar o token dentro do banco (card no ClickUp). definir_senha_com_token fica como está (exige token válido).
-- Reversão: grant execute on function central.criar_token_senha_autoatendimento(text, text, text) to anon, authenticated;
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
revoke execute on function central.criar_token_senha_autoatendimento(text, text, text) from public, anon, authenticated;
grant execute on function central.criar_token_senha_autoatendimento(text, text, text) to service_role;
commit;
