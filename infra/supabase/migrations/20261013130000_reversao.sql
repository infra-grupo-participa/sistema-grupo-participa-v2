-- Reversão de 20261013130000. Numa transação. Rodar ANTES da reversão da A (20261012231649).
-- As 3 RPCs de teste voltam ao corpo de antes (só atm_cadastro + atm_pertence, md5 de prosrc conferidos na migration).
-- As marcações de teste da Black e as 3 linhas de dashboard_grupos saem; a foto do grupo da Black (grupo_participantes,
-- FK em dashboard_grupos) sai junto se existir. crm.evento_jornada não é tocada (é a timeline do CRM, tag BF26).

drop function if exists public.dados_black_grupo(text, date, date, boolean, jsonb);
drop function if exists public.dados_black_leads(text, text[]);
drop function if exists public.dados_black_perfil(text, date, date, boolean);
drop function if exists dados.black_recorte_valido(jsonb);
drop function if exists dados.black_no_recorte(jsonb, text, text, text, text, text);

create or replace function public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
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
  if v_email is not null and not dados.atm_pertence(d.chave, 'email', v_email) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) then
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

create or replace function public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

create or replace function public.dados_testes(p_chave text)
 returns table(id bigint, tipo text, valor text, motivo text, marcado_por_email text, marcado_em timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select m.id, m.tipo, m.valor, m.motivo, m.marcado_por_email, m.marcado_em
    from dados.marcacoes_teste m
   where m.chave = d.chave and m.desmarcado_em is null
   order by m.marcado_em desc, m.id desc;
end
$function$;

drop function if exists dados.black_pertence(text, text, text);
drop function if exists dados.black_evento(text);
drop view if exists dados.black_leads;

delete from dados.marcacoes_teste where chave = 'black-friday-2026-10';
delete from dados.grupo_participantes p using dados.dashboard_grupos g where g.id = p.grupo_id and g.chave = 'black-friday-2026-10';
delete from dados.dashboard_grupos where chave = 'black-friday-2026-10';

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '2632356addaa503a8c1e6415ab6cb06d'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '99ed0ca0dc9c1268b2be18c9c055b84b'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_testes(text)'::regprocedure) <> '15cc20af1d1593c869a1787908406d64' then
    raise exception 'reversão 20261013130000: corpo das RPCs de teste não voltou ao de antes';
  end if;
end
$c$;
