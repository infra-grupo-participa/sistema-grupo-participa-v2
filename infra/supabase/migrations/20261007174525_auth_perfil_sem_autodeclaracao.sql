-- 20261007174525: Auth/perfis, quem se cadastra não escolhe o próprio status nem o próprio cargo (achado CRÍTICO 1.1 do
-- pentester, 07/10/2026, docs/dashboard-presencial.md §3.1).
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007174525_ensaio.sql (begin … rollback, 2 passadas). Relatório: 20261007174525.explain.md.
--
-- O BURACO (lido no banco vivo em 07/10/2026)
--   O cadastro do Supabase Auth está aberto (disable_signup = false, mailer_autoconfirm = true, sem captcha) e é usado
--   por outros sistemas do mesmo projeto (portais e workbook: milhares de cadastros públicos de jul a out/2026), então
--   não dá para fechar no Auth sem quebrar quem entra de verdade. O gatilho public.handle_new_user() (AFTER INSERT em
--   auth.users) gravava perfis.status e perfis.cargo a partir de raw_user_meta_data, que é o JSON que QUEM SE CADASTRA
--   escolhe. Cadastro com {status: ativo, cargo: admin} virava:
--     - equipe (gp_eh_equipe: ativo + @advmais.com), se o e-mail fosse @advmais.com (sem confirmar, autoconfirm);
--     - admin (gp_is_admin: ativo + dev/admin), com QUALQUER e-mail, porque gp_is_admin não conferia o domínio.
--   E a tabela perfis tinha GRANT de INSERT/DELETE/TRUNCATE/REFERENCES/TRIGGER para anon e authenticated (hoje só
--   barrado por não haver policy de INSERT/DELETE; uma policy futura abriria).
--
-- O QUE MUDA (a classe: privilégio nunca vem de dado que o próprio usuário escreve)
--   1. handle_new_user: perfil novo nasce SEMPRE status 'pendente' e cargo 'visualizador' (o mais baixo; a coluna é
--      NOT NULL com CHECK, então "sem cargo" = o default da coluna). Quem cria o perfil continua igual (mesmas 3
--      saídas antecipadas); o nome continua vindo do metadata. Ativar e dar cargo: só o admin, pela rota
--      /api/admin/usuarios (service_role), que já faz isso hoje logo depois do generateLink do convite.
--   2. gp_is_admin: passa a exigir e-mail @advmais.com, igual ao gp_eh_equipe e ao get-current-user do front.
--      Hoje nenhum perfil ativo dev/admin está fora do domínio (guarda abaixo aborta se houver).
--   3. perfis: revoga de anon tudo; de authenticated, INSERT, DELETE, TRUNCATE, REFERENCES e TRIGGER. Fica para
--      authenticated o SELECT (policy todos_auth_podem_ler, ver "Fora daqui") e o UPDATE só de nome, avatar_url e
--      atualizado_em (grant de coluna já existente, policy usuario_atualiza_proprio).
--
-- FORA DAQUI (de propósito)
--   - Configuração do Auth (disable_signup, mailer_autoconfirm): quebraria o cadastro dos outros sistemas.
--   - Policy todos_auth_podem_ler: há leitura de perfis por id de terceiros feita por authenticated (pg_stat_statements:
--     ~36 mil chamadas "id, nome, email, cargo, status where id = $1", ~2 mil "nome where id = $1", ~500 "id = any"),
--     de origem não identificada nos repositórios clonados. Restringir sem saber quem chama pode quebrar outro sistema.
--   - EXECUTE de handle_new_user: função de gatilho não é chamável por RPC; mexer no ACL dela não fecha nada e arrisca o
--     cadastro de todos os sistemas.
--   - Contas existentes: nenhuma é desativada ou apagada aqui (decisão do Victor).
--
-- REVERSÃO
--   Recriar as duas funções com o corpo anterior (está no 20261007174525.explain.md, lido por pg_get_functiondef) e
--   devolver os grants: grant all on public.perfis to anon; grant insert, delete, truncate, references, trigger on
--   public.perfis to authenticated. Não há dado alterado: a migration não faz UPDATE em linha nenhuma.

-- Guarda de premissa: aborta se a base não estiver como o ensaio leu (tolera rodar 2x).
do $g$
begin
  if to_regprocedure('public.handle_new_user()') is null
     or to_regprocedure('public.gp_is_admin()') is null
     or to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261007174525: função esperada não existe';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created'
                    and tgfoid = 'public.handle_new_user()'::regprocedure and tgenabled = 'O') then
    raise exception '20261007174525: gatilho on_auth_user_created não está ligado a public.handle_new_user()';
  end if;
  if exists (select 1 from public.perfis
              where status = 'ativo' and cargo in ('dev', 'admin')
                and not (coalesce(email, '') ilike '%@advmais.com')) then
    raise exception '20261007174525: há perfil ativo dev/admin fora de @advmais.com; o novo gp_is_admin tiraria o acesso dele';
  end if;
end
$g$;

-- 1. handle_new_user: corpo vigente (pg_get_functiondef, 07/10/2026) com status e cargo fixos.
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_portal text := coalesce(new.raw_user_meta_data->>'origem', new.raw_user_meta_data->>'sistema', '');
  v_declara_equipe boolean := (new.raw_user_meta_data ? 'cargo') or (new.raw_user_meta_data ? 'status');
  v_email_equipe boolean := coalesce(new.email, '') ilike '%@advmais.com';
BEGIN
  IF NEW.raw_app_meta_data->>'role' IN ('admin', 'mentor', 'student') THEN
    RETURN NEW;
  END IF;

  -- Cadastro veio de um portal de aluno: não é equipe.
  IF v_portal <> '' AND NOT v_declara_equipe THEN
    RETURN NEW;
  END IF;

  -- Sem sinal de equipe (nem cargo/status, nem e-mail do domínio): não é equipe.
  IF NOT v_declara_equipe AND NOT v_email_equipe THEN
    RETURN NEW;
  END IF;

  -- 20261007174525: status e cargo NUNCA vêm do raw_user_meta_data (quem se cadastra escreve esse JSON).
  -- Perfil nasce pendente e visualizador; ativar e dar cargo é do admin (/api/admin/usuarios, service_role).
  INSERT INTO public.perfis (id, nome, email, cargo, status)
  VALUES (NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    NEW.email,
    'visualizador',
    'pendente')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;

-- 2. gp_is_admin: corpo vigente + o mesmo domínio do gp_eh_equipe. Mesma assinatura (sem sobrecarga), ACL preservado.
CREATE OR REPLACE FUNCTION public.gp_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfis p
    WHERE p.id = auth.uid() AND p.status = 'ativo' AND p.cargo IN ('dev','admin')
      AND p.email ILIKE '%@advmais.com'
  );
$function$;

-- 3. perfis: ninguém de fora do servidor cria, apaga ou reescreve perfil.
revoke all on table public.perfis from anon;
revoke insert, delete, truncate, references, trigger on table public.perfis from authenticated;
