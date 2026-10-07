-- 20261007zz: níveis de acesso, B3 do pentester: gps.trocar_meu_nome deixa de falhar inteira para quem é da equipe e não
-- é master. A parte do aluno (public.thb_alunos) funciona para todo mundo; o nome de EQUIPE (public.perfis) só muda
-- quando quem chama é master (regra do gatilho acesso_guarda da fase 3).
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007204024 (nome gps_trocar_meu_nome, era 20261007zz), com o ok do pentester (rodada 4)
--   e do Victor, pelo aplica_sql.py aplicar + insert em supabase_migrations.schema_migrations na mesma transação; md5
--   gravado = a63c62b56089d4ec4b585d8b769b9b51 = este arquivo antes desta troca de STATUS. Ensaio: 20261007204024_ensaio.sql. Relatório: 20261007204024.explain.md.
--
-- POR QUE
--   O corpo atual faz primeiro "update public.perfis set nome …" e depois o update do aluno. Desde a fase 3
--   (20261007195738), o gatilho acesso_guarda recusa (42501) a troca do próprio nome para quem não é master, e o erro
--   derruba a função inteira: a pessoa da equipe que também é aluna do Programa não consegue trocar o nome de aluna.
--
-- O QUE FAZ (corpo vivo + 1 mudança)
--   (a) equipe: só faz o update em perfis se quem chama está em acesso.master; senão marca que o nome de equipe não mudou.
--   (b) aluno: igual ao de hoje.
--   Sem nada alterado: se a pessoa só tem perfil de equipe e não é master → 42501 "O nome da equipe só muda pela gestão
--   de usuários." (mensagem clara em vez do erro do gatilho); sem cadastro → P0002 como hoje.
--   O retorno ganha 'equipe_nao_alterada' (true quando havia perfil de equipe e ele não foi trocado).
--
-- AS 5 PERGUNTAS
--   escala: 1 função. frequência: rara (pessoa troca o próprio nome). reversão: corpo anterior em acesso.corpo_antes.
--
-- IDEMPOTENTE: a guarda aceita o corpo vivo de hoje (md5 46d2cd34…) ou o desta migration.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B3 (20261007zz): gps.trocar_meu_nome sem derrubar a parte do aluno');
  end if;
end
$bl$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) is distinct from '46d2cd341dc39e82e499f2c720dde51a'
     and (select prosrc from pg_proc where oid = to_regprocedure('gps.trocar_meu_nome(text)')) !~ '20261007zz' then
    raise exception '20261007zz: corpo vivo de gps.trocar_meu_nome mudou. Refazer a partir do pg_get_functiondef.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007zz'
  from pg_proc p where p.oid = 'gps.trocar_meu_nome(text)'::regprocedure
on conflict do nothing;

create or replace function gps.trocar_meu_nome(p_nome text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_aluno uuid;
  v_onde text := null;
  v_equipe_nao_alterada boolean := false;
begin
  if v_user is null then
    raise exception 'Faça login para alterar o seu nome.' using errcode = '42501';
  end if;
  if char_length(v_nome) < 2 then
    raise exception 'Escreva o seu nome completo.' using errcode = '22023';
  end if;
  if char_length(v_nome) > 120 then
    raise exception 'O nome passa de 120 caracteres.' using errcode = '22023';
  end if;
  -- Sem quebra de linha: o nome vai para e-mail e para o Slack.
  if v_nome ~ '[\r\n]' then
    raise exception 'O nome não pode ter quebra de linha.' using errcode = '22023';
  end if;

  -- (a) equipe: 20261007zz, só master troca o próprio nome de equipe (regra do gatilho acesso_guarda, fase 3);
  --     para os outros o nome de equipe muda pela gestão de usuários, e a parte do aluno segue abaixo.
  if exists (select 1 from public.perfis p where p.id = v_user) then
    if exists (select 1 from acesso.master m where m.perfil_id = v_user) then
      update public.perfis set nome = v_nome, atualizado_em = now() where id = v_user;
      if found then v_onde := 'perfis'; end if;
    else
      v_equipe_nao_alterada := true;
    end if;
  end if;

  -- (b) aluno: a pessoa daquele login, não o titular do ambiente -- num
  --     ambiente com sócio os dois têm o mesmo aluno_id de ambiente, e usar
  --     ele trocaria o nome do titular.
  select m.pessoa_aluno_id into v_aluno
    from gps.membros m where m.user_id = v_user and m.pessoa_aluno_id is not null
   limit 1;
  if v_aluno is not null then
    update public.thb_alunos set nome = v_nome where id = v_aluno;
    if found then v_onde := coalesce(v_onde || '+', '') || 'thb_alunos'; end if;
  end if;

  if v_onde is null then
    if v_equipe_nao_alterada then
      raise exception 'O nome da equipe só muda pela gestão de usuários.' using errcode = '42501';
    end if;
    raise exception 'Não encontramos o seu cadastro para alterar o nome.' using errcode = 'P0002';
  end if;

  return jsonb_build_object('nome', v_nome, 'onde', v_onde, 'equipe_nao_alterada', v_equipe_nao_alterada);
end;
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'gps.trocar_meu_nome(text)'::regprocedure) !~ '20261007zz' then
    raise exception '20261007zz: corpo não foi recriado';
  end if;
  if has_function_privilege('anon', 'gps.trocar_meu_nome(text)', 'execute')
     or not has_function_privilege('authenticated', 'gps.trocar_meu_nome(text)', 'execute') then
    raise exception '20261007zz: permissões de gps.trocar_meu_nome mudaram';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/niveis-de-acesso/rollback-b3.sql (cérebro), ensaiado em 20261007zz_ensaio.sql.
