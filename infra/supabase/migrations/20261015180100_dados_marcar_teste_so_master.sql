-- 20261015180100: dados_marcar_teste e dados_desmarcar_teste só master, em todos os modelos (pedido do Maestro/Victor, 15/10).
-- Por quê: na Black já era só master (20261013013625); no ATM e nas ações da Black bastava ser da equipe. Escrita fica master.
-- O front (ATM e Ações Black) já mostra o botão só para master, então a tela não muda. Massa: 36 marcações hoje; nenhuma
-- feita por quem não é master (19 por master, 17 sem autor, de carga).
-- Reversão: 20261015180100_reversao.sql (recria os dois corpos de antes).
-- Guarda: aborta se algum corpo vivo não for o lido em 15/10.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) is distinct from 'dbe100ce4eb055f04a831175be5a48be' then
    raise exception '20261015180100: corpo vivo de dados_marcar_teste mudou; revisar antes de aplicar';
  end if;
end
$g$;
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) is distinct from 'ab2fcbf796630fe6f0a254d27bb7e54a' then
    raise exception '20261015180100: corpo vivo de dados_desmarcar_teste mudou; revisar antes de aplicar';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- 20261015180100: marcar e desmarcar teste só master em todos os modelos (antes, no ATM e nas ações, bastava ser da equipe)
  if acesso.eu() is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
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

CREATE OR REPLACE FUNCTION public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  -- 20261013013625: na Black só master (42501); o ramo do ATM não mudou
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento_master(p_chave) else dados.atm_cadastro(p_chave) end;
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  -- 20261015180100: marcar e desmarcar teste só master em todos os modelos (antes, no ATM e nas ações, bastava ser da equipe)
  if acesso.eu() is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
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

revoke all on function public.dados_marcar_teste(text,text,text,text) from public, anon;
grant execute on function public.dados_marcar_teste(text,text,text,text) to authenticated;
revoke all on function public.dados_desmarcar_teste(text,text,text) from public, anon;
grant execute on function public.dados_desmarcar_teste(text,text,text) to authenticated;
