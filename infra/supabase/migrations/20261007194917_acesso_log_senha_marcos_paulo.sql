-- 20261007x: níveis de acesso, registro em acesso.log da senha padrão definida para o Marcos Paulo (perfil da equipe
-- 9d347183…, @advmais.com, operador/vendedor do Comercial), a pedido do Victor Hugo em 07/10/2026.
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007194917 (nome acesso_log_senha_marcos_paulo, era 20261007x),
-- pelo aplica_sql.py aplicar + insert em supabase_migrations.schema_migrations; md5 gravado = c1d4d99c350e3e8e7830bce848b18d33 =
-- este arquivo antes desta troca de STATUS. Ensaio: 20261007194917_ensaio.sql. Relatório: 20261007194917.explain.md.
--
-- POR QUE
--   O Victor pediu a senha padrão para o Marcos Paulo. Havia duas contas no Auth com esse nome; o Victor confirmou a do
--   perfil da equipe (9d347183…) e mandou não tocar na outra (86904eed…, @gmail.com, sem perfil de equipe). A senha foi
--   definida pela API admin do Supabase Auth e o login real com e-mail e senha foi testado (entrou). A senha não é
--   registrada em lugar nenhum. Papel, área, vínculo e cargo NÃO mudaram. Esta migration só REGISTRA.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em acesso.log. índice: PK. frequência: uma vez. repetição: nenhuma. reversão: nenhuma (só acréscimo).
--
-- IDEMPOTENTE: só insere se ainda não houver o registro.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select nome from public.perfis where id = '9d347183-5395-434e-9e96-2a65dde1a3cd') is distinct from 'Marcos Paulo' then
    raise exception '20261007x: perfil 9d347183 não é mais o Marcos Paulo';
  end if;
end
$g$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select null, 'auth', 'senha', '9d347183-5395-434e-9e96-2a65dde1a3cd', null,
       jsonb_build_object('motivo', 'senha padrão definida pela API admin do Auth a pedido do Victor 07/10 (conta da equipe confirmada por ele; a conta 86904eed não foi tocada)',
                          'login_testado', true, 'registrado_por', 'migration 20261007x', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '9d347183-5395-434e-9e96-2a65dde1a3cd' and tabela = 'auth');
