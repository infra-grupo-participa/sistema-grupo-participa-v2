-- Ensaio de 20261007174525_auth_perfil_sem_autodeclaracao.sql: 2 passadas num só begin … rollback. Gerado a partir do .sql como está.
-- Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste: cadastros de ensaio (e-mail
-- ensaio-20261007174525-*) são inseridos em auth.users dentro da transação desfeita. Nenhum dado pessoal real na saída.
--
-- ESPERADO
--   t0 antes:   forj_dom ativo/admin com eh_equipe=true is_admin=true (prova do buraco); forj_fora ativo/admin com
--               is_admin=true; anon e authenticated com INSERT/DELETE na tabela.
--   passada 1 e 2: forj_dom e forj_fora pendente/visualizador com todas as portas false; portal sem perfil; convite
--               pendente e, depois do update do admin, eh_equipe=true is_admin=true; update de status e insert de
--               perfil recusados (42501); anon sem SELECT; authenticated só SELECT e UPDATE de nome/avatar/atualizado_em;
--               ativos_admin_dev_regra_antiga = ativos_admin_dev_regra_nova (ninguém perde admin); admin real is_admin=true.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_ids (rot text primary key, id uuid) on commit drop;
grant all on pg_temp._z_out to anon, authenticated; grant all on sequence pg_temp._z_out_em_seq to anon, authenticated;
grant select on pg_temp._z_ids to anon, authenticated;

-- ===== checagens: t0 antes =====
insert into pg_temp._z_ids (rot, id) values ('t0_antes_forj_dom', gen_random_uuid()), ('t0_antes_forj_fora', gen_random_uuid()),
  ('t0_antes_convite', gen_random_uuid()), ('t0_antes_portal', gen_random_uuid());
-- cadastro como o GoTrue grava (signup público e convite), em auth.users; os 7 gatilhos reais rodam.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', i.id, 'authenticated', 'authenticated',
       'ensaio-20261007174525-' || i.rot || case when i.rot like '%_fora' or i.rot like '%_portal' then '@exemplo.invalid' else '@advmais.com' end,
       '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
       case when i.rot like '%_forj_%' then '{"nome":"Ensaio","status":"ativo","cargo":"admin","email_verified":true}'::jsonb
            when i.rot like '%_portal' then '{"nome":"Ensaio","origem":"portal-ensaio","email_verified":true}'::jsonb
            else '{}'::jsonb end,
       now(), now()
  from pg_temp._z_ids i where i.rot like 't0_antes\_%';
insert into pg_temp._z_out (passo, linha)
select 't0 antes perfil ' || i.rot, coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = i.id), 'sem perfil')
  from pg_temp._z_ids i where i.rot like 't0_antes\_%' order by i.rot;
-- convite legítimo: o admin ativa pelo servidor (service_role), igual a /api/admin/usuarios POST
update public.perfis set status = 'ativo', cargo = 'admin' where id = (select id from pg_temp._z_ids where rot = 't0_antes_convite');

-- portas vistas por cada usuário de ensaio, com JWT de authenticated
select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 't0_antes_forj_dom'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('t0 antes portas forj_dom', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);
set local role authenticated;
do $t$ begin
  begin
    update public.perfis set status = 'ativo' where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom update proprio status', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom update proprio status', sqlstate || ': ' || sqlerrm); end;
  begin
    delete from public.perfis where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom delete proprio', 'rodou, linhas afetadas abaixo');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom delete proprio', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;
insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_dom perfil depois do delete', coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = (select id from pg_temp._z_ids where rot = 't0_antes_forj_dom')), 'sem perfil'));

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 't0_antes_forj_fora'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('t0 antes portas forj_fora', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('t0 antes forj_fora crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 't0_antes_portal'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $t$ begin
  begin
    insert into public.perfis (id, nome, email, cargo, status) values (auth.uid(), 'x', 'x@exemplo.invalid', 'admin', 'ativo');
    insert into pg_temp._z_out (passo, linha) values ('t0 antes portal insert proprio perfil admin', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('t0 antes portal insert proprio perfil admin', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 't0_antes_convite'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('t0 antes portas convite ativado pelo admin', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ve_proprio_perfil=' || (select count(*) from public.perfis where id = auth.uid()) || ' ve_perfis=' || (select count(*) from public.perfis));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin
  begin
    perform count(*) from public.perfis;
    insert into pg_temp._z_out (passo, linha) values ('t0 antes anon select perfis', 'permitido, linhas=' || (select count(*) from public.perfis));
  exception when others then insert into pg_temp._z_out (passo, linha) values ('t0 antes anon select perfis', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

insert into pg_temp._z_out (passo, linha) select 't0 antes privilegios', jsonb_build_object(
  'anon', jsonb_build_object('select', has_table_privilege('anon', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('anon', 'public.perfis', 'INSERT'),
                             'delete', has_table_privilege('anon', 'public.perfis', 'DELETE'), 'update_cargo', has_column_privilege('anon', 'public.perfis', 'cargo', 'UPDATE')),
  'authenticated', jsonb_build_object('select', has_table_privilege('authenticated', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('authenticated', 'public.perfis', 'INSERT'),
                             'insert_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'INSERT'),
                             'delete', has_table_privilege('authenticated', 'public.perfis', 'DELETE'), 'truncate', has_table_privilege('authenticated', 'public.perfis', 'TRUNCATE'),
                             'update_nome', has_column_privilege('authenticated', 'public.perfis', 'nome', 'UPDATE'),
                             'update_status', has_column_privilege('authenticated', 'public.perfis', 'status', 'UPDATE'),
                             'update_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'UPDATE')),
  'disparos_ui_ro_select', has_table_privilege('disparos_ui_ro', 'public.perfis', 'SELECT'),
  'service_role_update', has_table_privilege('service_role', 'public.perfis', 'UPDATE'),
  'proacl', (select jsonb_object_agg(p.proname, coalesce(p.proacl::text, '-')) from pg_proc p where p.oid in ('public.handle_new_user()'::regprocedure, 'public.gp_is_admin()'::regprocedure, 'public.gp_eh_equipe()'::regprocedure)),
  'sobrecargas_gp_is_admin', (select count(*) from pg_proc where proname = 'gp_is_admin'),
  'sobrecargas_handle_new_user_public', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'handle_new_user')
)::text;

insert into pg_temp._z_out (passo, linha) select 't0 antes perfis reais', jsonb_build_object(
  'total', count(*), 'ativos', count(*) filter (where status = 'ativo'),
  'ativos_admin_dev_regra_antiga', count(*) filter (where status = 'ativo' and cargo in ('dev','admin')),
  'ativos_admin_dev_regra_nova', count(*) filter (where status = 'ativo' and cargo in ('dev','admin') and email ilike '%@advmais.com'),
  'ativos_equipe', count(*) filter (where status = 'ativo' and email ilike '%@advmais.com'))::text
  from public.perfis where email not like 'ensaio-20261007174525-%';

-- ===== explain: t0 antes (gp_is_admin com o JWT de um admin real ativo; o id não sai na saída) =====
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.perfis where status = 'ativo' and cargo = 'admin' and email ilike '%@advmais.com' and email not like 'ensaio-%' order by criado_em limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;
do $t$ declare l text; i int; begin
  for i in 1..2 loop
    for l in execute 'explain (analyze, buffers) select public.gp_is_admin()' loop
      insert into pg_temp._z_out (passo, linha) values ('t0 antes explain gp_is_admin #' || i, l);
    end loop;
  end loop;
  insert into pg_temp._z_out (passo, linha) values ('t0 antes admin real', 'is_admin=' || public.gp_is_admin() || ' eh_equipe=' || public.gp_eh_equipe());
end $t$;
reset role;
do $t$ declare l text; i int; v uuid; begin
  for i in 1..2 loop
    v := gen_random_uuid();
    for l in execute format($q$explain (analyze, buffers) insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
      values ('00000000-0000-0000-0000-000000000000', %L, 'authenticated', 'authenticated', %L, '', now(), '{"provider":"email"}'::jsonb, '{"nome":"Ensaio","status":"ativo","cargo":"admin"}'::jsonb, now(), now())$q$,
      v, 'ensaio-20261007174525-explain-t0_antes-' || i || '@advmais.com') loop
      if l ~ '(Trigger|Execution Time|Planning Time|Insert on)' then
        insert into pg_temp._z_out (passo, linha) values ('t0 antes explain signup #' || i, l);
      end if;
    end loop;
  end loop;
end $t$;

-- Limpa os cadastros forjados do t0 dentro da transação: o forj_fora ativo/admin fora do domínio faria a guarda abortar
-- (foi assim que a guarda se provou na 1a rodada).
with d as (delete from auth.users where email like 'ensaio-20261007174525-%' returning 1) insert into pg_temp._z_out (passo, linha) select 't0 limpeza', count(*)::text from d;

-- ===== PASSADA 1: 20261007174525_auth_perfil_sem_autodeclaracao.sql =====
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

-- ===== checagens: p1 =====
insert into pg_temp._z_ids (rot, id) values ('p1_forj_dom', gen_random_uuid()), ('p1_forj_fora', gen_random_uuid()),
  ('p1_convite', gen_random_uuid()), ('p1_portal', gen_random_uuid());
-- cadastro como o GoTrue grava (signup público e convite), em auth.users; os 7 gatilhos reais rodam.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', i.id, 'authenticated', 'authenticated',
       'ensaio-20261007174525-' || i.rot || case when i.rot like '%_fora' or i.rot like '%_portal' then '@exemplo.invalid' else '@advmais.com' end,
       '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
       case when i.rot like '%_forj_%' then '{"nome":"Ensaio","status":"ativo","cargo":"admin","email_verified":true}'::jsonb
            when i.rot like '%_portal' then '{"nome":"Ensaio","origem":"portal-ensaio","email_verified":true}'::jsonb
            else '{}'::jsonb end,
       now(), now()
  from pg_temp._z_ids i where i.rot like 'p1\_%';
insert into pg_temp._z_out (passo, linha)
select 'p1 perfil ' || i.rot, coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = i.id), 'sem perfil')
  from pg_temp._z_ids i where i.rot like 'p1\_%' order by i.rot;
-- convite legítimo: o admin ativa pelo servidor (service_role), igual a /api/admin/usuarios POST
update public.perfis set status = 'ativo', cargo = 'admin' where id = (select id from pg_temp._z_ids where rot = 'p1_convite');

-- portas vistas por cada usuário de ensaio, com JWT de authenticated
select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p1_forj_dom'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p1 portas forj_dom', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);
set local role authenticated;
do $t$ begin
  begin
    update public.perfis set status = 'ativo' where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom update proprio status', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom update proprio status', sqlstate || ': ' || sqlerrm); end;
  begin
    delete from public.perfis where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom delete proprio', 'rodou, linhas afetadas abaixo');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom delete proprio', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;
insert into pg_temp._z_out (passo, linha) values ('p1 forj_dom perfil depois do delete', coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = (select id from pg_temp._z_ids where rot = 'p1_forj_dom')), 'sem perfil'));

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p1_forj_fora'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p1 portas forj_fora', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('p1 forj_fora crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p1_portal'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $t$ begin
  begin
    insert into public.perfis (id, nome, email, cargo, status) values (auth.uid(), 'x', 'x@exemplo.invalid', 'admin', 'ativo');
    insert into pg_temp._z_out (passo, linha) values ('p1 portal insert proprio perfil admin', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p1 portal insert proprio perfil admin', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p1_convite'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p1 portas convite ativado pelo admin', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ve_proprio_perfil=' || (select count(*) from public.perfis where id = auth.uid()) || ' ve_perfis=' || (select count(*) from public.perfis));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin
  begin
    perform count(*) from public.perfis;
    insert into pg_temp._z_out (passo, linha) values ('p1 anon select perfis', 'permitido, linhas=' || (select count(*) from public.perfis));
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p1 anon select perfis', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

insert into pg_temp._z_out (passo, linha) select 'p1 privilegios', jsonb_build_object(
  'anon', jsonb_build_object('select', has_table_privilege('anon', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('anon', 'public.perfis', 'INSERT'),
                             'delete', has_table_privilege('anon', 'public.perfis', 'DELETE'), 'update_cargo', has_column_privilege('anon', 'public.perfis', 'cargo', 'UPDATE')),
  'authenticated', jsonb_build_object('select', has_table_privilege('authenticated', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('authenticated', 'public.perfis', 'INSERT'),
                             'insert_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'INSERT'),
                             'delete', has_table_privilege('authenticated', 'public.perfis', 'DELETE'), 'truncate', has_table_privilege('authenticated', 'public.perfis', 'TRUNCATE'),
                             'update_nome', has_column_privilege('authenticated', 'public.perfis', 'nome', 'UPDATE'),
                             'update_status', has_column_privilege('authenticated', 'public.perfis', 'status', 'UPDATE'),
                             'update_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'UPDATE')),
  'disparos_ui_ro_select', has_table_privilege('disparos_ui_ro', 'public.perfis', 'SELECT'),
  'service_role_update', has_table_privilege('service_role', 'public.perfis', 'UPDATE'),
  'proacl', (select jsonb_object_agg(p.proname, coalesce(p.proacl::text, '-')) from pg_proc p where p.oid in ('public.handle_new_user()'::regprocedure, 'public.gp_is_admin()'::regprocedure, 'public.gp_eh_equipe()'::regprocedure)),
  'sobrecargas_gp_is_admin', (select count(*) from pg_proc where proname = 'gp_is_admin'),
  'sobrecargas_handle_new_user_public', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'handle_new_user')
)::text;

insert into pg_temp._z_out (passo, linha) select 'p1 perfis reais', jsonb_build_object(
  'total', count(*), 'ativos', count(*) filter (where status = 'ativo'),
  'ativos_admin_dev_regra_antiga', count(*) filter (where status = 'ativo' and cargo in ('dev','admin')),
  'ativos_admin_dev_regra_nova', count(*) filter (where status = 'ativo' and cargo in ('dev','admin') and email ilike '%@advmais.com'),
  'ativos_equipe', count(*) filter (where status = 'ativo' and email ilike '%@advmais.com'))::text
  from public.perfis where email not like 'ensaio-20261007174525-%';

-- ===== explain: p1 (gp_is_admin com o JWT de um admin real ativo; o id não sai na saída) =====
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.perfis where status = 'ativo' and cargo = 'admin' and email ilike '%@advmais.com' and email not like 'ensaio-%' order by criado_em limit 1), 'role', 'authenticated')::text, true);
set local role authenticated;
do $t$ declare l text; i int; begin
  for i in 1..2 loop
    for l in execute 'explain (analyze, buffers) select public.gp_is_admin()' loop
      insert into pg_temp._z_out (passo, linha) values ('p1 explain gp_is_admin #' || i, l);
    end loop;
  end loop;
  insert into pg_temp._z_out (passo, linha) values ('p1 admin real', 'is_admin=' || public.gp_is_admin() || ' eh_equipe=' || public.gp_eh_equipe());
end $t$;
reset role;
do $t$ declare l text; i int; v uuid; begin
  for i in 1..2 loop
    v := gen_random_uuid();
    for l in execute format($q$explain (analyze, buffers) insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
      values ('00000000-0000-0000-0000-000000000000', %L, 'authenticated', 'authenticated', %L, '', now(), '{"provider":"email"}'::jsonb, '{"nome":"Ensaio","status":"ativo","cargo":"admin"}'::jsonb, now(), now())$q$,
      v, 'ensaio-20261007174525-explain-p1-' || i || '@advmais.com') loop
      if l ~ '(Trigger|Execution Time|Planning Time|Insert on)' then
        insert into pg_temp._z_out (passo, linha) values ('p1 explain signup #' || i, l);
      end if;
    end loop;
  end loop;
end $t$;

-- ===== PASSADA 2: 20261007174525_auth_perfil_sem_autodeclaracao.sql =====
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

-- ===== checagens: p2 =====
insert into pg_temp._z_ids (rot, id) values ('p2_forj_dom', gen_random_uuid()), ('p2_forj_fora', gen_random_uuid()),
  ('p2_convite', gen_random_uuid()), ('p2_portal', gen_random_uuid());
-- cadastro como o GoTrue grava (signup público e convite), em auth.users; os 7 gatilhos reais rodam.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', i.id, 'authenticated', 'authenticated',
       'ensaio-20261007174525-' || i.rot || case when i.rot like '%_fora' or i.rot like '%_portal' then '@exemplo.invalid' else '@advmais.com' end,
       '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
       case when i.rot like '%_forj_%' then '{"nome":"Ensaio","status":"ativo","cargo":"admin","email_verified":true}'::jsonb
            when i.rot like '%_portal' then '{"nome":"Ensaio","origem":"portal-ensaio","email_verified":true}'::jsonb
            else '{}'::jsonb end,
       now(), now()
  from pg_temp._z_ids i where i.rot like 'p2\_%';
insert into pg_temp._z_out (passo, linha)
select 'p2 perfil ' || i.rot, coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = i.id), 'sem perfil')
  from pg_temp._z_ids i where i.rot like 'p2\_%' order by i.rot;
-- convite legítimo: o admin ativa pelo servidor (service_role), igual a /api/admin/usuarios POST
update public.perfis set status = 'ativo', cargo = 'admin' where id = (select id from pg_temp._z_ids where rot = 'p2_convite');

-- portas vistas por cada usuário de ensaio, com JWT de authenticated
select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p2_forj_dom'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p2 portas forj_dom', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);
set local role authenticated;
do $t$ begin
  begin
    update public.perfis set status = 'ativo' where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom update proprio status', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom update proprio status', sqlstate || ': ' || sqlerrm); end;
  begin
    delete from public.perfis where id = auth.uid();
    insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom delete proprio', 'rodou, linhas afetadas abaixo');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom delete proprio', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;
insert into pg_temp._z_out (passo, linha) values ('p2 forj_dom perfil depois do delete', coalesce((select p.status || '/' || p.cargo from public.perfis p where p.id = (select id from pg_temp._z_ids where rot = 'p2_forj_dom')), 'sem perfil'));

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p2_forj_fora'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p2 portas forj_fora', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ver_cpf=' || public.gp_pode_ver_cpf());
reset role;
insert into pg_temp._z_out (passo, linha) values ('p2 forj_fora crm.pode_catalogar (como postgres, mesmo JWT)', crm.pode_catalogar()::text);

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p2_portal'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $t$ begin
  begin
    insert into public.perfis (id, nome, email, cargo, status) values (auth.uid(), 'x', 'x@exemplo.invalid', 'admin', 'ativo');
    insert into pg_temp._z_out (passo, linha) values ('p2 portal insert proprio perfil admin', 'GRAVOU');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p2 portal insert proprio perfil admin', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp._z_ids where rot = 'p2_convite'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('p2 portas convite ativado pelo admin', 'eh_equipe=' || public.gp_eh_equipe() || ' is_admin=' || public.gp_is_admin() || ' ve_proprio_perfil=' || (select count(*) from public.perfis where id = auth.uid()) || ' ve_perfis=' || (select count(*) from public.perfis));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin
  begin
    perform count(*) from public.perfis;
    insert into pg_temp._z_out (passo, linha) values ('p2 anon select perfis', 'permitido, linhas=' || (select count(*) from public.perfis));
  exception when others then insert into pg_temp._z_out (passo, linha) values ('p2 anon select perfis', sqlstate || ': ' || sqlerrm); end;
end $t$;
reset role;

insert into pg_temp._z_out (passo, linha) select 'p2 privilegios', jsonb_build_object(
  'anon', jsonb_build_object('select', has_table_privilege('anon', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('anon', 'public.perfis', 'INSERT'),
                             'delete', has_table_privilege('anon', 'public.perfis', 'DELETE'), 'update_cargo', has_column_privilege('anon', 'public.perfis', 'cargo', 'UPDATE')),
  'authenticated', jsonb_build_object('select', has_table_privilege('authenticated', 'public.perfis', 'SELECT'), 'insert', has_table_privilege('authenticated', 'public.perfis', 'INSERT'),
                             'insert_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'INSERT'),
                             'delete', has_table_privilege('authenticated', 'public.perfis', 'DELETE'), 'truncate', has_table_privilege('authenticated', 'public.perfis', 'TRUNCATE'),
                             'update_nome', has_column_privilege('authenticated', 'public.perfis', 'nome', 'UPDATE'),
                             'update_status', has_column_privilege('authenticated', 'public.perfis', 'status', 'UPDATE'),
                             'update_cargo', has_column_privilege('authenticated', 'public.perfis', 'cargo', 'UPDATE')),
  'disparos_ui_ro_select', has_table_privilege('disparos_ui_ro', 'public.perfis', 'SELECT'),
  'service_role_update', has_table_privilege('service_role', 'public.perfis', 'UPDATE'),
  'proacl', (select jsonb_object_agg(p.proname, coalesce(p.proacl::text, '-')) from pg_proc p where p.oid in ('public.handle_new_user()'::regprocedure, 'public.gp_is_admin()'::regprocedure, 'public.gp_eh_equipe()'::regprocedure)),
  'sobrecargas_gp_is_admin', (select count(*) from pg_proc where proname = 'gp_is_admin'),
  'sobrecargas_handle_new_user_public', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'handle_new_user')
)::text;

insert into pg_temp._z_out (passo, linha) select 'p2 perfis reais', jsonb_build_object(
  'total', count(*), 'ativos', count(*) filter (where status = 'ativo'),
  'ativos_admin_dev_regra_antiga', count(*) filter (where status = 'ativo' and cargo in ('dev','admin')),
  'ativos_admin_dev_regra_nova', count(*) filter (where status = 'ativo' and cargo in ('dev','admin') and email ilike '%@advmais.com'),
  'ativos_equipe', count(*) filter (where status = 'ativo' and email ilike '%@advmais.com'))::text
  from public.perfis where email not like 'ensaio-20261007174525-%';

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
