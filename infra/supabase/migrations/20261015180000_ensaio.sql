-- Ensaio de 20261015180000 e 20261015180100 (transação desfeita). Rodar com aplica_sql.py ensaio.
begin;
set local statement_timeout = '60s';
set local lock_timeout = '3s';
create temp table _z_out (em serial, passo text, linha text);
grant all on pg_temp._z_out to authenticated;
-- personas (só ids e contagens saem no resultado)
select set_config('z.master', (select m.perfil_id::text from acesso.master m join public.perfis p on p.id = m.perfil_id where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1), true);
select set_config('z.master_email', (select p.email from public.perfis p where p.id::text = current_setting('z.master')), true);
select set_config('z.equipe', coalesce((select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
  and not exists (select 1 from acesso.master m where m.perfil_id = p.id)
  and not exists (select 1 from acesso.capacidade c where c.perfil_id = p.id and c.chave = 'contato.ver') order by p.id limit 1), ''), true);
select set_config('z.equipe_email', coalesce((select p.email from public.perfis p where p.id::text = current_setting('z.equipe')), ''), true);
select set_config('z.contato', coalesce((select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
  and not exists (select 1 from acesso.master m where m.perfil_id = p.id)
  and exists (select 1 from acesso.capacidade c where c.perfil_id = p.id and c.chave = 'contato.ver') order by p.id limit 1), ''), true);
select set_config('z.contato_email', coalesce((select p.email from public.perfis p where p.id::text = current_setting('z.contato')), ''), true);
select set_config('z.leads', (select array_agg(lead_id)::text from (select lead_id from dados.black_leads order by criado_em limit 3) x), true);
select set_config('z.email_atm', (select valor from dados.marcacoes_teste where chave = 'atm-elaine-1-2026-10' and tipo = 'email' and desmarcado_em is null order by marcado_em limit 1), true);
insert into pg_temp._z_out(passo, linha) values ('0 personas (equipe sem contato.ver / equipe com contato.ver achadas)',
  (current_setting('z.equipe') <> '')::text || ' / ' || (current_setting('z.contato') <> '')::text);
insert into pg_temp._z_out(passo, linha) select '0 md5 antes', string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('dados_black_leads','dados_marcar_teste','dados_desmarcar_teste');
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  select count(*) into n from public.dados_black_leads('black-friday-2026-10', current_setting('z.leads')::text[]);
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('1a ANTES equipe sem contato.ver: black_leads (esperado ok, é o furo)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_marcar_teste('atm-elaine-1-2026-10', current_setting('z.email_atm'));
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('1b ANTES equipe: marcar teste ATM (esperado ok, é o furo)', current_setting('z.r'));

-- ===== aplica as duas migrations =====
-- 20261015180000: dados_black_leads passa a exigir a capacidade contato.ver (pedido do Maestro/Victor, 15/10).
-- Por quê: a RPC devolve nome, e-mail e telefone e só exigia ser da equipe (@advmais ativo). As outras que devolvem
-- contato (dados_black_lista, dados_atm_leads, dados_atm_pre_checkout, dados_atm_sv_vendas) já exigem contato.ver.
-- Efeito: equipe sem contato.ver recebe 42501 ao abrir a tabela de leads da Black; master e quem tem contato.ver seguem iguais.
-- Reversão: 20261015180000_reversao.sql (recria o corpo de antes, md5 do prosrc 1eadf321...).
-- Guarda: aborta se o corpo vivo não for o lido em 15/10.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_leads(text,text[])'::regprocedure) is distinct from '1eadf32102cc43026c67e6143b68113e' then
    raise exception '20261015180000: corpo vivo de dados_black_leads mudou; revisar antes de aplicar';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_leads(p_chave text, p_lead_ids text[])
 RETURNS TABLE(lead_id text, nome text, email text, telefone text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);
begin
  -- 20261015180000: devolve nome, e-mail e telefone; exige contato.ver, como dados_black_lista e dados_atm_leads
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if p_lead_ids is null or cardinality(p_lead_ids) = 0 then return; end if;
  if cardinality(p_lead_ids) > 500 then
    raise exception 'no máximo 500 leads por chamada' using errcode = '22023';
  end if;
  return query
  select l.lead_id, l.nome, l.email, l.whatsapp
    from dados.black_leads l
   where l.lead_id = any (p_lead_ids)
   order by l.criado_em, l.lead_id;
end
$function$;

revoke all on function public.dados_black_leads(text,text[]) from public, anon;
grant execute on function public.dados_black_leads(text,text[]) to authenticated;

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

select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.master'), 'role', 'authenticated', 'email', current_setting('z.master_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  select count(*) into n from public.dados_black_leads('black-friday-2026-10', current_setting('z.leads')::text[]);
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('2 master: black_leads (esperado ok: 3)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  select count(*) into n from public.dados_black_leads('black-friday-2026-10', current_setting('z.leads')::text[]);
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('3 equipe sem contato.ver: black_leads (esperado 42501)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.contato'), 'role', 'authenticated', 'email', current_setting('z.contato_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  select count(*) into n from public.dados_black_leads('black-friday-2026-10', current_setting('z.leads')::text[]);
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('4 equipe com contato.ver: black_leads (esperado ok: 3)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.master'), 'role', 'authenticated', 'email', current_setting('z.master_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_marcar_teste('atm-elaine-1-2026-10', current_setting('z.email_atm'));
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('5 master: marcar teste ATM, e-mail já marcado (esperado ok: 0)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_marcar_teste('atm-elaine-1-2026-10', current_setting('z.email_atm'));
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('6 equipe: marcar teste ATM (esperado 42501)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_desmarcar_teste('atm-elaine-1-2026-10', current_setting('z.email_atm'));
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('7 equipe: desmarcar teste ATM (esperado 42501)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.master'), 'role', 'authenticated', 'email', current_setting('z.master_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_desmarcar_teste('atm-elaine-1-2026-10', current_setting('z.email_atm'));
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('8 master: desmarcar teste ATM (esperado ok: 1, desfeito no rollback)', current_setting('z.r'));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.equipe'), 'role', 'authenticated', 'email', current_setting('z.equipe_email'))::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  n := public.dados_marcar_teste('black-friday-2026-10', 'x@x.com');
  perform set_config('z.r', 'ok: ' || coalesce(n::text, 'null'), true);
exception when others then perform set_config('z.r', 'erro ' || sqlstate || ': ' || sqlerrm, true);
end $t$;
reset role;
insert into pg_temp._z_out(passo, linha) values ('9 equipe: marcar teste Black (esperado 42501, como antes)', current_setting('z.r'));
insert into pg_temp._z_out(passo, linha) select '10 md5 depois', string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('dados_black_leads','dados_marcar_teste','dados_desmarcar_teste');
insert into pg_temp._z_out(passo, linha) select '11 acl depois', string_agg(p.proname || '=' || array_to_string(p.proacl, ','), ' ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('dados_black_leads','dados_marcar_teste','dados_desmarcar_teste');
insert into pg_temp._z_out(passo, linha) select '12 anon executa?', string_agg(p.proname || '=' || has_function_privilege('anon', p.oid, 'execute')::text, ' ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('dados_black_leads','dados_marcar_teste','dados_desmarcar_teste');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
