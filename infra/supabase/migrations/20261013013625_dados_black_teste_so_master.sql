-- 20261013013625: na Black (modelo jornada-captacao, chave black-friday-2026-10), marcar e desmarcar teste só para master.
-- Achado do pentester (13/10/2026): no ramo da Black, dados_marcar_teste e dados_desmarcar_teste só exigiam a equipe
-- (black_evento -> black_cadastro -> dados.cadastro -> gp_eh_equipe), não master. O presencial já exige
-- acesso.eh_master() (dados_presencial_marcar_teste). Esta migration:
--   1. cria dados.black_evento_master(chave): 42501 se não for master; depois o mesmo dados.black_evento de antes
--      (P0002 fora da chave da Black). Sem grant.
--   2. dados_marcar_teste e dados_desmarcar_teste: o ramo da Black passa a chamar black_evento_master. O ramo do ATM
--      (atm_cadastro) fica com o texto e o comportamento de antes: só equipe. Isso é pendência para decisão (explain §5).
--   3. O desmarcar continua preso ao evento: o update só toca linhas com m.chave = d.chave, e d.chave vem de
--      black_evento (só 'black-friday-2026-10'). Nada muda em dados_testes nem nas RPCs dados_black_* de leitura.
-- Pré-requisito: corpo vivo das duas RPCs igual ao gravado por 20261012234606 (md5 conferido abaixo).
-- Reversão: 20261013013625_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('dados.black_evento(text)') is null then
    raise exception '20261013013625: dados.black_evento não existe (aplicar 20261012234606 antes).';
  end if;
  if to_regprocedure('acesso.eh_master()') is null or to_regprocedure('acesso.eu()') is null then
    raise exception '20261013013625: acesso.eh_master() ou acesso.eu() não existe.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '05d7fecb174f8b16fa9cb3abcd7cea44'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '1e715847e3e96a74b01cfa0a9260afc0'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_evento(text)'::regprocedure) <> '0f6a30a86f69abf4a4981a1efd885f87'
     or (select md5(prosrc) from pg_proc where oid = 'dados.atm_cadastro(text)'::regprocedure) <> '0501ccd5647a89b44c7b9c02dc4ad8ca' then
    raise exception '20261013013625: corpo vivo de dados_marcar_teste, dados_desmarcar_teste, black_evento ou atm_cadastro mudou. Reler.';
  end if;
end
$g$;

-- 1. trava de master da Black (mesma regra de dados_presencial_marcar_teste)
create or replace function dados.black_evento_master(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  -- 20261013013625: marcar e desmarcar teste na Black só para master
  if acesso.eu() is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return dados.black_evento(p_chave);   -- P0002 fora da chave da Black
end
$function$;
revoke all on function dados.black_evento_master(text) from public, anon, authenticated, service_role;

-- 2. marcar teste: só o ramo da Black muda (black_evento -> black_evento_master)
create or replace function public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  -- 20261013013625: na Black só master (42501); o ramo do ATM não mudou
  v_black boolean := exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao');
  d dados.dashboards := case when v_black then dados.black_evento_master(p_chave) else dados.atm_cadastro(p_chave) end;   -- Black: 42501 não master; ATM: 42501 não equipe; P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not (case when v_black then dados.black_pertence(d.chave, 'email', v_email)
                                       else dados.atm_pertence(d.chave, 'email', v_email) end) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not (case when v_black then dados.black_pertence(d.chave, 'fone', right(v_fk, 8))
                                    else dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) end) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$function$;

-- 3. desmarcar teste: só o ramo da Black muda; o update já fica preso a d.chave (o evento resolvido)
create or replace function public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  -- 20261013013625: na Black só master (42501); o ramo do ATM não mudou
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento_master(p_chave) else dados.atm_cadastro(p_chave) end;
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  -- só a marcação ativa deste evento (d.chave); a de outro dashboard com o mesmo valor não é tocada
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_marcar_teste(text, text, text, text) from public, anon;
revoke all on function public.dados_desmarcar_teste(text, text, text) from public, anon;
grant execute on function public.dados_marcar_teste(text, text, text, text) to authenticated;
grant execute on function public.dados_desmarcar_teste(text, text, text) to authenticated;

-- 4. conferência
do $c$
begin
  if exists (select 1 from pg_proc where oid = 'dados.black_evento_master(text)'::regprocedure
              and (proacl is null or proacl::text <> '{postgres=X/postgres}' or prosecdef)) then
    raise exception '20261013013625: black_evento_master com permissão errada';
  end if;
  if (select prosrc from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) not like '%dados.black_evento_master(p_chave)%'
     or (select prosrc from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) not like '%dados.black_evento_master(p_chave)%' then
    raise exception '20261013013625: ramo da Black sem a trava de master';
  end if;
  if has_function_privilege('anon', 'public.dados_marcar_teste(text,text,text,text)', 'execute')
     or has_function_privilege('anon', 'public.dados_desmarcar_teste(text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_marcar_teste(text,text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_desmarcar_teste(text,text,text)', 'execute') then
    raise exception '20261013013625: permissões das RPCs de teste erradas';
  end if;
end
$c$;
