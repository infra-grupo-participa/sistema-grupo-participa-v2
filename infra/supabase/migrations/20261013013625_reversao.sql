-- Reversão de 20261013013625 (Black: marcar/desmarcar teste só master). Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_marcar_teste e dados_desmarcar_teste ao corpo exato gravado por 20261012234606 (lido no banco em
-- 13/10/2026 ~01:35 UTC; o comentário de dentro ainda diz 20261013130000, nome antigo do arquivo) e apaga
-- dados.black_evento_master. Não apaga dado: as marcações feitas por master depois da aplicação ficam.
-- Efeito: a Black volta a aceitar marcar/desmarcar de qualquer pessoa da equipe (o furo do achado).
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 20261013130000: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  v_black boolean := exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao');
  d dados.dashboards := case when v_black then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
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

CREATE OR REPLACE FUNCTION public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 20261013130000: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;
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

revoke all on function public.dados_marcar_teste(text, text, text, text) from public, anon;
revoke all on function public.dados_desmarcar_teste(text, text, text) from public, anon;
grant execute on function public.dados_marcar_teste(text, text, text, text) to authenticated;
grant execute on function public.dados_desmarcar_teste(text, text, text) to authenticated;

drop function if exists dados.black_evento_master(text);

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '05d7fecb174f8b16fa9cb3abcd7cea44'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '1e715847e3e96a74b01cfa0a9260afc0'
     or to_regprocedure('dados.black_evento_master(text)') is not null then
    raise exception 'reversão 20261013013625: corpo das RPCs de teste não voltou ao de antes';
  end if;
end
$c$;

