-- Ensaio de 20261013140000 (transação desfeita, REPEATABLE READ). Recorte de anúncio com lista de ids e metaads como Meta.
-- Prova: (1) recorte de anúncio com 1 id dá o mesmo de antes; com a lista de ids de um criativo (anúncios de mesmo nome em
-- vários conjuntos, ids reais de mkt_trafego.anuncios) soma os anúncios e bate com a contagem direta da view, sem a RPC;
-- (2) valor malformado (espaço, letra, vírgula sobrando, vazio, quebra de linha, mais de 2000) dá 22023; (3) metaads vira
-- canal meta e sai de utm_campaign_fora_do_padrao, e nenhuma outra linha nem coluna da view ou de dados_black_perfil muda;
-- (4) dados_black_grupo sem recorte e com recorte que não é de anúncio fica idêntico; (5) dono, ACL, opções, comentário e
-- colunas da view e das funções iguais; travas (42501, P0002) iguais; (6) a reversão volta os md5 e os resultados ao de
-- antes; as guardas recusam fora de hora.
-- Só contagens, sqlstate, md5 e ids de anúncio do Meta: nenhum dado pessoal sai do ensaio. Gerado por um script a partir
-- da migration e da reversão (o texto delas entra aqui sem mudança).
-- Depois de aplicada, a guarda da migration recusa: para reensaiar, cole o texto de 20261013140000_reversao.sql logo
-- depois do begin abaixo. M (master) é buscado no banco; o uid de "fora da equipe" é fictício de propósito.
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_r (fase text, caso text, r jsonb) on commit drop;
create temp table _z_meta (fase text, k text, v text) on commit drop;
create temp table _z_view (fase text, lead_id text, us text, canal text, a_corrigir text[], resto text) on commit drop;
create temp table _z_perfil (fase text, lead_id text, canal text, a_corrigir text[], resto text) on commit drop;
create temp table _z_dir (fase text, caso text, unicos int, mql int) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_r, pg_temp._z_meta, pg_temp._z_view, pg_temp._z_perfil, pg_temp._z_dir to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('ensaio.m', coalesce((select m.perfil_id::text from acesso.master m join public.perfis p on p.id = m.perfil_id
  where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1), ''), true);
do $q$ begin
  if current_setting('ensaio.m') = '' then raise exception 'ensaio: nenhum master ativo da equipe no banco'; end if;
end $q$;
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '72b790f32645801faba5fc3563338d8c' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261012234606 (md5 72b790f3…). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> 'f445e3dd27a3b268e17b6f3cd0e8b61d' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261012234606 (md5 f445e3dd…). Reler antes de aplicar.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '2054c3dad0aeb1fb1351bacb693d56b9' then
    raise exception 'migration 20261013140000: definição viva de dados.black_leads não é a gravada por 20261012234606 (md5 2054c3da…). Reler antes de aplicar.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G migration | antes', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G migration | antes', sqlstate); end $t$;
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> 'd315533cdfbaab649da865a688c45b08' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '71d6b291d608911d1507e22bc9c850e2' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798' then
    raise exception 'reversão 20261013140000: definição viva de dados.black_leads não é a gravada por 20261013140000. Reler antes de reverter.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G reversao | antes', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G reversao | antes', sqlstate); end $t$;
-- ===== ANTES =====
reset role;
insert into pg_temp._z_meta (fase, k, v)
select 'antes', x.k, x.v from (values
  ('md5 no_recorte', (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure)),
  ('md5 recorte_valido', (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure)),
  ('md5 viewdef', md5(pg_get_viewdef('dados.black_leads'::regclass))),
  ('fn meta', (select string_agg(p.proname || ' ' || p.proowner::regrole::text || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || coalesce(p.proconfig::text, '-'), ' ; ' order by p.proname)
                 from pg_proc p where p.oid in ('dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure, 'dados.black_recorte_valido(jsonb)'::regprocedure))),
  ('view meta', (select c.relowner::regrole::text || ' ' || coalesce(c.relacl::text, '-') || ' ' || coalesce(c.reloptions::text, '-') from pg_class c where c.oid = 'dados.black_leads'::regclass)),
  ('view comment', md5(coalesce(obj_description('dados.black_leads'::regclass, 'pg_class'), ''))),
  ('view cols', md5((select string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' order by attnum) from pg_attribute where attrelid = 'dados.black_leads'::regclass and attnum > 0 and not attisdropped))),
  ('anon/auth select view', (has_table_privilege('anon', 'dados.black_leads', 'select') or has_table_privilege('authenticated', 'dados.black_leads', 'select'))::text),
  ('rpcs acl', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || md5(p.prosrc), ' ; ' order by p.proname) from pg_proc p
                 where p.oid in ('public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure, 'public.dados_black_perfil(text,date,date,boolean)'::regprocedure,
                                 'public.dados_black_leads(text,text[])'::regprocedure, 'dados.black_pertence(text,text,text)'::regprocedure)))
) x(k, v);
insert into pg_temp._z_view (fase, lead_id, us, canal, a_corrigir, resto)
select 'antes', l.lead_id, lower(btrim(l.utm_source)), l.canal, l.a_corrigir, md5((to_jsonb(l) - 'canal' - 'a_corrigir')::text) from dados.black_leads l;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '12025602855058022a'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221,'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ',120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '1,,2'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ''));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221' || chr(10)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', repeat('1', 2001)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 2000 - 1994)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', repeat('x', 201)));
  insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', 'consultoria'));
  insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | antes', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'conjunto', 'valor', '120256028515140221'));
  insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;

insert into pg_temp._z_r (fase, caso, r) select 'antes', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'a_um_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'a_um_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'l_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720940221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'l_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550540221,120256028550560221,120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'l_dossie_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028714850221,120256028714890221,120256028714910221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'l_dois_criativos', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'conjunto', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"conjunto","valor":"120256028515140221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_perfil (fase, lead_id, canal, a_corrigir, resto)
select 'antes', p.lead_id, p.canal, p.a_corrigir, md5((to_jsonb(p) - 'pessoa_id' - 'canal' - 'a_corrigir')::text) from public.dados_black_perfil('black-friday-2026-10') p;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | antes', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 6))))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | antes', 'ok:' || md5(v));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | antes', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo todo | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 1 id | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 2 criativos | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select count(*) from public.dados_black_perfil(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E perfil todo | antes', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_dir (fase, caso, unicos, mql)
select 'antes', r.caso, (select count(distinct l.pessoa_chave) from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ','))),
       (select count(*) from (select l.pessoa_chave, (array_agg(l.profissao_classe order by l.criado_em desc, l.lead_id desc) filter (where l.profissao_classe is not null))[1] c
                                from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ',')) group by 1) x
         where x.c in ('advogado', 'contador', 'estudante_direito'))
  from (values ('a_um_prova_a', '120256028720990221'), ('a_um_convite_b', '120256028550580221'), ('l_prova_a', '120256028720940221,120256028720990221'), ('l_convite_b', '120256028550540221,120256028550560221,120256028550580221'), ('l_dossie_b', '120256028714850221,120256028714890221,120256028714910221'), ('l_dois_criativos', '120256028550580221,120256028720990221')) r(caso, valor);
-- ===== MIGRATION (texto de 20261013140000_dados_black_recorte_lista_e_metaads.sql) =====
reset role;
-- 20261013140000: dashboard da Black. (1) o recorte de ANÚNCIO aceita vários ids do Meta (criativo = anúncios de mesmo nome);
-- (2) utm_source=metaads passa a valer como canal Meta. Numa transação (o arquivo não abre nem fecha uma).
-- Escrita em 13/10/2026 (UTC) na branch victor-black-funil-mql-grupo; guarda corrigida e ensaiada contra produção na branch
-- victor-black-recorte-lista (ver 20261013140000.explain.md). Só o Victor/João aplicam.
-- Não muda tabela nem dado, só 2 funções internas e 1 view (sem leitura para anon/authenticated).
-- Ensaio: 20261013140000_ensaio.sql. Reversão: 20261013140000_reversao.sql.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- guarda: as duas funções e a view precisam estar como a migration 20261012234606 deixou no banco (senão alguém mudou
-- depois). md5 lidos no banco em 13/10/2026: o corpo vivo das funções traz o comentário "20261013130000" (número com que
-- 20261012234606 foi escrita), por isso o md5 do texto do arquivo 20261012234606 (1cdc4228…, 394cb0ae…) não serve aqui.
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '72b790f32645801faba5fc3563338d8c' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261012234606 (md5 72b790f3…). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> 'f445e3dd27a3b268e17b6f3cd0e8b61d' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261012234606 (md5 f445e3dd…). Reler antes de aplicar.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '2054c3dad0aeb1fb1351bacb693d56b9' then
    raise exception 'migration 20261013140000: definição viva de dados.black_leads não é a gravada por 20261012234606 (md5 2054c3da…). Reler antes de aplicar.';
  end if;
end
$g$;

-- 1. recorte de anúncio com lista de ids (valor = ids do Meta só com dígitos, separados por vírgula; até 2000 caracteres)
create or replace function dados.black_no_recorte(p_recorte jsonb, p_porta text, p_isca text,
                                                  p_campanha_id text, p_conjunto_id text, p_anuncio_id text)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  -- 20261012234606
  -- 20261013140000: tipo anuncio aceita vários ids do Meta separados por vírgula (criativo = anúncios de mesmo nome)
  select p_recorte is null
      or case p_recorte ->> 'tipo'
           when 'porta' then (p_recorte ->> 'valor') = p_porta
           when 'isca' then (p_recorte ->> 'valor') = p_isca
           when 'campanha' then (p_recorte ->> 'valor') = p_campanha_id
           when 'conjunto' then (p_recorte ->> 'valor') = p_conjunto_id
           when 'anuncio' then p_anuncio_id = any (string_to_array(p_recorte ->> 'valor', ','))
         end
$function$;
revoke all on function dados.black_no_recorte(jsonb, text, text, text, text, text) from public, anon, authenticated, service_role;

create or replace function dados.black_recorte_valido(p_recorte jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  -- 20261012234606: null, {} e jsonb null = sem recorte. 20261013140000: anúncio aceita lista de ids (só dígitos e vírgula)
  if p_recorte is null or p_recorte = '{}'::jsonb or jsonb_typeof(p_recorte) = 'null' then return null; end if;
  if jsonb_typeof(p_recorte) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_recorte) k where k not in ('tipo', 'valor'))
     or jsonb_typeof(p_recorte -> 'tipo') is distinct from 'string'
     or jsonb_typeof(p_recorte -> 'valor') is distinct from 'string'
     or p_recorte ->> 'tipo' not in ('porta', 'isca', 'campanha', 'conjunto', 'anuncio')
     or length(p_recorte ->> 'valor') not between 1 and 2000
     or (p_recorte ->> 'tipo' = 'anuncio' and (p_recorte ->> 'valor') !~ '^[0-9]+(,[0-9]+)*$')
     or (p_recorte ->> 'tipo' <> 'anuncio' and length(p_recorte ->> 'valor') > 200) then
    raise exception 'recorte inválido: {"tipo": porta|isca|campanha|conjunto|anuncio, "valor": texto}' using errcode = '22023';
  end if;
  return p_recorte;
end
$function$;
revoke all on function dados.black_recorte_valido(jsonb) from public, anon, authenticated, service_role;

-- 2. utm_source=metaads é Meta (canal 'meta' e utm_campaign nome|id no padrão). Resto da view idêntico ao de 20261012234606.
create or replace view dados.black_leads with (security_invoker = true) as
with b as (
  select 'captacao'::text as pagina, r.id::text as id_fonte, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding)) as campos
    from metodo.pesquisa_respostas r
   where r.origem = 'metodo-perfeito' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'fluxograma', r.id::text, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding))
    from metodo.pesquisa_respostas r
   where r.origem = 'fluxograma-holding-familiar' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'consultoria', c.id::text, c.criado_em, c.nome, c.email, c.whatsapp, c.profissao,
         c.utm_source, c.utm_medium, c.utm_campaign, c.utm_content, c.utm_term,
         jsonb_strip_nulls(jsonb_build_object('cursos', to_jsonb(c.cursos), 'momento', c.momento, 'dificuldade', c.dificuldade,
           'quer_levar_caso', c.quer_levar_caso, 'participa_camera', c.participa_camera, 'nota_indicacao', c.nota_indicacao))
    from metodo.consultoria_aplicacoes c
   where c.origem = 'consultoria-ao-vivo' and c.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'checkup', g.id::text, g.criado_em, g.nome, g.email, g.whatsapp, g.profissao,
         g.utm_source, g.utm_medium, g.utm_campaign, g.utm_content, g.utm_term,
         jsonb_strip_nulls(jsonb_build_object('faixa', g.faixa, 'pontos_total', g.pontos_total, 'mql_fonte', g.mql))
    from rede.diagnosticos g
   where g.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'futurometro', f.id::text, f.criado_em, f.nome, f.email, f.whatsapp, f.profissao,
         f.utm_source, f.utm_medium, f.utm_campaign, f.utm_content, f.utm_term,
         jsonb_strip_nulls(jsonb_build_object('casos_ativos', f.casos_ativos, 'satisfeito', f.satisfeito))
    from rede.futurometros f
   where f.criado_em >= timestamptz '2026-10-04 00:00:00-03'
), n as (
  select b.*,
         nullif(lower(btrim(b.email)), '') as email_norm,
         controle.fone_key(b.whatsapp) as fk,
         nullif(btrim(b.profissao), '') as prof,
         nullif(btrim(b.utm_source), '') as us, nullif(btrim(b.utm_medium), '') as um, nullif(btrim(b.utm_campaign), '') as uc,
         nullif(btrim(b.utm_content), '') as ut, nullif(btrim(b.utm_term), '') as ue
    from b
)
select n.pagina || ':' || n.id_fonte as lead_id,
       n.pagina, n.id_fonte, n.criado_em, n.nome, n.email_norm as email, n.whatsapp,
       n.profissao,
       case when n.prof is null then null
            when n.prof = 'Advogado(a)' then 'advogado'
            when n.prof = 'Contador(a)' then 'contador'
            when n.prof = 'Estudante de Direito' then 'estudante_direito'
            else 'outros' end as profissao_classe,
       coalesce(n.prof in ('Advogado(a)', 'Contador(a)', 'Estudante de Direito'), false) as mql,
       n.utm_source, n.utm_medium, n.utm_campaign, n.utm_content, n.utm_term,
       -- padrão Meta dos anúncios (auditoria 12/10): utm_campaign = nome|id, utm_medium = conjunto|id, utm_content = anúncio|id
       substring(n.uc from '\|([0-9]+)$') as campanha_id,
       substring(n.um from '\|([0-9]+)$') as conjunto_id,
       substring(n.ut from '\|([0-9]+)$') as anuncio_id,
       case when n.pagina = 'captacao' then 'inscricao_direta' when n.pagina = 'consultoria' then 'consultoria' else 'isca' end as porta,
       case n.pagina when 'fluxograma' then 'Fluxograma' when 'checkup' then 'Checkup' when 'futurometro' then 'Futurômetro' end as isca,
       case when lower(n.us) in ('fb', 'facebook', 'ig', 'instagram', 'meta', 'metaads') then 'meta'
            when lower(n.us) in ('google', 'googleads', 'google_ads') then 'google' end as canal,
       n.fk as fone_key,
       right(n.fk, 8) as fone8,
       left(n.fk, 2) as ddd,
       case when n.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(n.fk, 2)), 'Outros') end as uf,
       coalesce('f:' || right(n.fk, 8), 'e:' || n.email_norm, 'l:' || n.pagina || ':' || n.id_fonte) as pessoa_chave,
       dados.teste_ativo('black-friday-2026-10', n.email_norm, n.whatsapp) as teste,
       -- heurística da auditoria de 12/10 (só sinaliza; quem tira do número é a marcação)
       coalesce(n.email_norm like '%teste%' or n.nome ilike '%teste%' or n.email_norm like '%@advmais.com%', false) as parece_teste,
       array_remove(array[
         case when n.prof is null then 'profissao_vazia' end,
         case when n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null then 'sem_utm' end,
         case when not (n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null)
               and n.uc is distinct from 'black-friday-2026-10'
               and not (lower(coalesce(n.us, '')) in ('fb', 'facebook', 'ig', 'instagram', 'meta', 'metaads') and n.uc ~ '\|[0-9]+$')
              then 'utm_campaign_fora_do_padrao' end
       ], null) as a_corrigir,
       n.campos
  from n;
revoke all on dados.black_leads from public, anon, authenticated, service_role;

-- conferência: o banco ficou com o texto deste arquivo (md5 medidos no ensaio de 13/10/2026; a reversão confere os mesmos)
do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> 'd315533cdfbaab649da865a688c45b08'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '71d6b291d608911d1507e22bc9c850e2'
     or md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798' then
    raise exception 'migration 20261013140000: o banco não ficou com o texto desta migration';
  end if;
end
$c$;

-- ===== fim da migration =====
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '72b790f32645801faba5fc3563338d8c' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261012234606 (md5 72b790f3…). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> 'f445e3dd27a3b268e17b6f3cd0e8b61d' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261012234606 (md5 f445e3dd…). Reler antes de aplicar.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '2054c3dad0aeb1fb1351bacb693d56b9' then
    raise exception 'migration 20261013140000: definição viva de dados.black_leads não é a gravada por 20261012234606 (md5 2054c3da…). Reler antes de aplicar.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G migration | depois', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G migration | depois', sqlstate); end $t$;
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> 'd315533cdfbaab649da865a688c45b08' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '71d6b291d608911d1507e22bc9c850e2' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798' then
    raise exception 'reversão 20261013140000: definição viva de dados.black_leads não é a gravada por 20261013140000. Reler antes de reverter.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G reversao | depois', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G reversao | depois', sqlstate); end $t$;
-- ===== DEPOIS =====
reset role;
insert into pg_temp._z_meta (fase, k, v)
select 'depois', x.k, x.v from (values
  ('md5 no_recorte', (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure)),
  ('md5 recorte_valido', (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure)),
  ('md5 viewdef', md5(pg_get_viewdef('dados.black_leads'::regclass))),
  ('fn meta', (select string_agg(p.proname || ' ' || p.proowner::regrole::text || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || coalesce(p.proconfig::text, '-'), ' ; ' order by p.proname)
                 from pg_proc p where p.oid in ('dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure, 'dados.black_recorte_valido(jsonb)'::regprocedure))),
  ('view meta', (select c.relowner::regrole::text || ' ' || coalesce(c.relacl::text, '-') || ' ' || coalesce(c.reloptions::text, '-') from pg_class c where c.oid = 'dados.black_leads'::regclass)),
  ('view comment', md5(coalesce(obj_description('dados.black_leads'::regclass, 'pg_class'), ''))),
  ('view cols', md5((select string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' order by attnum) from pg_attribute where attrelid = 'dados.black_leads'::regclass and attnum > 0 and not attisdropped))),
  ('anon/auth select view', (has_table_privilege('anon', 'dados.black_leads', 'select') or has_table_privilege('authenticated', 'dados.black_leads', 'select'))::text),
  ('rpcs acl', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || md5(p.prosrc), ' ; ' order by p.proname) from pg_proc p
                 where p.oid in ('public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure, 'public.dados_black_perfil(text,date,date,boolean)'::regprocedure,
                                 'public.dados_black_leads(text,text[])'::regprocedure, 'dados.black_pertence(text,text,text)'::regprocedure)))
) x(k, v);
insert into pg_temp._z_view (fase, lead_id, us, canal, a_corrigir, resto)
select 'depois', l.lead_id, lower(btrim(l.utm_source)), l.canal, l.a_corrigir, md5((to_jsonb(l) - 'canal' - 'a_corrigir')::text) from dados.black_leads l;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '12025602855058022a'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221,'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ',120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '1,,2'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ''));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221' || chr(10)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', repeat('1', 2001)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 2000 - 1994)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', repeat('x', 201)));
  insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', 'consultoria'));
  insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | depois', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'conjunto', 'valor', '120256028515140221'));
  insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;

insert into pg_temp._z_r (fase, caso, r) select 'depois', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'a_um_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'a_um_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'l_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720940221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'l_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550540221,120256028550560221,120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'l_dossie_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028714850221,120256028714890221,120256028714910221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'l_dois_criativos', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'conjunto', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"conjunto","valor":"120256028515140221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_perfil (fase, lead_id, canal, a_corrigir, resto)
select 'depois', p.lead_id, p.canal, p.a_corrigir, md5((to_jsonb(p) - 'pessoa_id' - 'canal' - 'a_corrigir')::text) from public.dados_black_perfil('black-friday-2026-10') p;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | depois', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 6))))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | depois', 'ok:' || md5(v));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | depois', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo todo | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 1 id | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 2 criativos | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select count(*) from public.dados_black_perfil(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E perfil todo | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, jsonb_build_object(''tipo'', ''anuncio'', ''valor'', rtrim(repeat(''120256028550580221,'', 105), '','') || repeat(''1'', 6)))' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 105 ids | depois', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_dir (fase, caso, unicos, mql)
select 'depois', r.caso, (select count(distinct l.pessoa_chave) from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ','))),
       (select count(*) from (select l.pessoa_chave, (array_agg(l.profissao_classe order by l.criado_em desc, l.lead_id desc) filter (where l.profissao_classe is not null))[1] c
                                from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ',')) group by 1) x
         where x.c in ('advogado', 'contador', 'estudante_direito'))
  from (values ('a_um_prova_a', '120256028720990221'), ('a_um_convite_b', '120256028550580221'), ('l_prova_a', '120256028720940221,120256028720990221'), ('l_convite_b', '120256028550540221,120256028550560221,120256028550580221'), ('l_dossie_b', '120256028714850221,120256028714890221,120256028714910221'), ('l_dois_criativos', '120256028550580221,120256028720990221')) r(caso, valor);
-- ===== REVERSÃO (texto de 20261013140000_reversao.sql) =====
reset role;
-- Reversão de 20261013140000. Numa transação (o arquivo não abre nem fecha uma).
-- Devolve black_no_recorte, black_recorte_valido e a view dados.black_leads ao que 20261012234606 gravou, byte a byte como
-- estava no banco (o corpo vivo das funções traz o comentário "20261013130000", número com que 20261012234606 foi escrita;
-- md5 de volta: 72b790f3…, f445e3dd… e view 2054c3da…, conferido no fim).
-- Efeito na tela: o recorte de anúncio volta a aceitar um id só (criativo em vários conjuntos volta a pedir um conjunto) e
-- utm_source=metaads volta a não contar como Meta. Não toca em dado.
-- Guarda: só roda se os corpos vivos forem os gravados por 20261013140000 (md5 d315533c…, 71d6b291… e view 5ce61662…).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> 'd315533cdfbaab649da865a688c45b08' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '71d6b291d608911d1507e22bc9c850e2' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798' then
    raise exception 'reversão 20261013140000: definição viva de dados.black_leads não é a gravada por 20261013140000. Reler antes de reverter.';
  end if;
end
$g$;

create or replace function dados.black_no_recorte(p_recorte jsonb, p_porta text, p_isca text,
                                                  p_campanha_id text, p_conjunto_id text, p_anuncio_id text)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  -- 20261013130000
  select p_recorte is null
      or (p_recorte ->> 'valor') = case p_recorte ->> 'tipo'
           when 'porta' then p_porta when 'isca' then p_isca when 'campanha' then p_campanha_id
           when 'conjunto' then p_conjunto_id when 'anuncio' then p_anuncio_id end
$function$;
revoke all on function dados.black_no_recorte(jsonb, text, text, text, text, text) from public, anon, authenticated, service_role;

create or replace function dados.black_recorte_valido(p_recorte jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  -- 20261013130000: null, {} e jsonb null = sem recorte
  if p_recorte is null or p_recorte = '{}'::jsonb or jsonb_typeof(p_recorte) = 'null' then return null; end if;
  if jsonb_typeof(p_recorte) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_recorte) k where k not in ('tipo', 'valor'))
     or jsonb_typeof(p_recorte -> 'tipo') is distinct from 'string'
     or jsonb_typeof(p_recorte -> 'valor') is distinct from 'string'
     or p_recorte ->> 'tipo' not in ('porta', 'isca', 'campanha', 'conjunto', 'anuncio')
     or length(p_recorte ->> 'valor') not between 1 and 200 then
    raise exception 'recorte inválido: {"tipo": porta|isca|campanha|conjunto|anuncio, "valor": texto}' using errcode = '22023';
  end if;
  return p_recorte;
end
$function$;
revoke all on function dados.black_recorte_valido(jsonb) from public, anon, authenticated, service_role;

create or replace view dados.black_leads with (security_invoker = true) as
with b as (
  select 'captacao'::text as pagina, r.id::text as id_fonte, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding)) as campos
    from metodo.pesquisa_respostas r
   where r.origem = 'metodo-perfeito' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'fluxograma', r.id::text, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding))
    from metodo.pesquisa_respostas r
   where r.origem = 'fluxograma-holding-familiar' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'consultoria', c.id::text, c.criado_em, c.nome, c.email, c.whatsapp, c.profissao,
         c.utm_source, c.utm_medium, c.utm_campaign, c.utm_content, c.utm_term,
         jsonb_strip_nulls(jsonb_build_object('cursos', to_jsonb(c.cursos), 'momento', c.momento, 'dificuldade', c.dificuldade,
           'quer_levar_caso', c.quer_levar_caso, 'participa_camera', c.participa_camera, 'nota_indicacao', c.nota_indicacao))
    from metodo.consultoria_aplicacoes c
   where c.origem = 'consultoria-ao-vivo' and c.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'checkup', g.id::text, g.criado_em, g.nome, g.email, g.whatsapp, g.profissao,
         g.utm_source, g.utm_medium, g.utm_campaign, g.utm_content, g.utm_term,
         jsonb_strip_nulls(jsonb_build_object('faixa', g.faixa, 'pontos_total', g.pontos_total, 'mql_fonte', g.mql))
    from rede.diagnosticos g
   where g.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'futurometro', f.id::text, f.criado_em, f.nome, f.email, f.whatsapp, f.profissao,
         f.utm_source, f.utm_medium, f.utm_campaign, f.utm_content, f.utm_term,
         jsonb_strip_nulls(jsonb_build_object('casos_ativos', f.casos_ativos, 'satisfeito', f.satisfeito))
    from rede.futurometros f
   where f.criado_em >= timestamptz '2026-10-04 00:00:00-03'
), n as (
  select b.*,
         nullif(lower(btrim(b.email)), '') as email_norm,
         controle.fone_key(b.whatsapp) as fk,
         nullif(btrim(b.profissao), '') as prof,
         nullif(btrim(b.utm_source), '') as us, nullif(btrim(b.utm_medium), '') as um, nullif(btrim(b.utm_campaign), '') as uc,
         nullif(btrim(b.utm_content), '') as ut, nullif(btrim(b.utm_term), '') as ue
    from b
)
select n.pagina || ':' || n.id_fonte as lead_id,
       n.pagina, n.id_fonte, n.criado_em, n.nome, n.email_norm as email, n.whatsapp,
       n.profissao,
       case when n.prof is null then null
            when n.prof = 'Advogado(a)' then 'advogado'
            when n.prof = 'Contador(a)' then 'contador'
            when n.prof = 'Estudante de Direito' then 'estudante_direito'
            else 'outros' end as profissao_classe,
       coalesce(n.prof in ('Advogado(a)', 'Contador(a)', 'Estudante de Direito'), false) as mql,
       n.utm_source, n.utm_medium, n.utm_campaign, n.utm_content, n.utm_term,
       -- padrão Meta dos anúncios (auditoria 12/10): utm_campaign = nome|id, utm_medium = conjunto|id, utm_content = anúncio|id
       substring(n.uc from '\|([0-9]+)$') as campanha_id,
       substring(n.um from '\|([0-9]+)$') as conjunto_id,
       substring(n.ut from '\|([0-9]+)$') as anuncio_id,
       case when n.pagina = 'captacao' then 'inscricao_direta' when n.pagina = 'consultoria' then 'consultoria' else 'isca' end as porta,
       case n.pagina when 'fluxograma' then 'Fluxograma' when 'checkup' then 'Checkup' when 'futurometro' then 'Futurômetro' end as isca,
       case when lower(n.us) in ('fb', 'facebook', 'ig', 'instagram', 'meta') then 'meta'
            when lower(n.us) in ('google', 'googleads', 'google_ads') then 'google' end as canal,
       n.fk as fone_key,
       right(n.fk, 8) as fone8,
       left(n.fk, 2) as ddd,
       case when n.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(n.fk, 2)), 'Outros') end as uf,
       coalesce('f:' || right(n.fk, 8), 'e:' || n.email_norm, 'l:' || n.pagina || ':' || n.id_fonte) as pessoa_chave,
       dados.teste_ativo('black-friday-2026-10', n.email_norm, n.whatsapp) as teste,
       -- heurística da auditoria de 12/10 (só sinaliza; quem tira do número é a marcação)
       coalesce(n.email_norm like '%teste%' or n.nome ilike '%teste%' or n.email_norm like '%@advmais.com%', false) as parece_teste,
       array_remove(array[
         case when n.prof is null then 'profissao_vazia' end,
         case when n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null then 'sem_utm' end,
         case when not (n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null)
               and n.uc is distinct from 'black-friday-2026-10'
               and not (lower(coalesce(n.us, '')) in ('fb', 'facebook', 'ig', 'instagram', 'meta') and n.uc ~ '\|[0-9]+$')
              then 'utm_campaign_fora_do_padrao' end
       ], null) as a_corrigir,
       n.campos
  from n;
revoke all on dados.black_leads from public, anon, authenticated, service_role;

-- conferência: voltou ao que estava no banco antes de 20261013140000
do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '72b790f32645801faba5fc3563338d8c'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> 'f445e3dd27a3b268e17b6f3cd0e8b61d'
     or md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '2054c3dad0aeb1fb1351bacb693d56b9' then
    raise exception 'reversão 20261013140000: corpos não voltaram ao de antes';
  end if;
end
$c$;

-- ===== fim da reversão =====
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '72b790f32645801faba5fc3563338d8c' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261012234606 (md5 72b790f3…). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> 'f445e3dd27a3b268e17b6f3cd0e8b61d' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261012234606 (md5 f445e3dd…). Reler antes de aplicar.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '2054c3dad0aeb1fb1351bacb693d56b9' then
    raise exception 'migration 20261013140000: definição viva de dados.black_leads não é a gravada por 20261012234606 (md5 2054c3da…). Reler antes de aplicar.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G migration | reversao', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G migration | reversao', sqlstate); end $t$;
do $t$ begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> 'd315533cdfbaab649da865a688c45b08' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '71d6b291d608911d1507e22bc9c850e2' then
    raise exception 'reversão 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261013140000. Reler antes de reverter.';
  end if;
  -- pg_get_viewdef depende do search_path da sessão; lido com o padrão do projeto ("$user", public, extensions)
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798' then
    raise exception 'reversão 20261013140000: definição viva de dados.black_leads não é a gravada por 20261013140000. Reler antes de reverter.';
  end if;
  insert into pg_temp._z_out (passo, linha) values ('G reversao | reversao', 'passa');
exception when others then insert into pg_temp._z_out (passo, linha) values ('G reversao | reversao', sqlstate); end $t$;
-- ===== REVERSAO =====
reset role;
insert into pg_temp._z_meta (fase, k, v)
select 'reversao', x.k, x.v from (values
  ('md5 no_recorte', (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure)),
  ('md5 recorte_valido', (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure)),
  ('md5 viewdef', md5(pg_get_viewdef('dados.black_leads'::regclass))),
  ('fn meta', (select string_agg(p.proname || ' ' || p.proowner::regrole::text || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || coalesce(p.proconfig::text, '-'), ' ; ' order by p.proname)
                 from pg_proc p where p.oid in ('dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure, 'dados.black_recorte_valido(jsonb)'::regprocedure))),
  ('view meta', (select c.relowner::regrole::text || ' ' || coalesce(c.relacl::text, '-') || ' ' || coalesce(c.reloptions::text, '-') from pg_class c where c.oid = 'dados.black_leads'::regclass)),
  ('view comment', md5(coalesce(obj_description('dados.black_leads'::regclass, 'pg_class'), ''))),
  ('view cols', md5((select string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' order by attnum) from pg_attribute where attrelid = 'dados.black_leads'::regclass and attnum > 0 and not attisdropped))),
  ('anon/auth select view', (has_table_privilege('anon', 'dados.black_leads', 'select') or has_table_privilege('authenticated', 'dados.black_leads', 'select'))::text),
  ('rpcs acl', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || md5(p.prosrc), ' ; ' order by p.proname) from pg_proc p
                 where p.oid in ('public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure, 'public.dados_black_perfil(text,date,date,boolean)'::regprocedure,
                                 'public.dados_black_leads(text,text[])'::regprocedure, 'dados.black_pertence(text,text,text)'::regprocedure)))
) x(k, v);
insert into pg_temp._z_view (fase, lead_id, us, canal, a_corrigir, resto)
select 'reversao', l.lead_id, lower(btrim(l.utm_source)), l.canal, l.a_corrigir, md5((to_jsonb(l) - 'canal' - 'a_corrigir')::text) from dados.black_leads l;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio espaco | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '12025602855058022a'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio letra | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221,'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no fim | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ',120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula no inicio | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '1,,2'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio virgula dupla | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', ''));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio vazio | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221' || chr(10)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio quebra de linha | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', repeat('1', 2001)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2001 chars | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 2000 - 1994)));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 2000 chars (105 ids) | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221'));
  insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V anuncio 1 id | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', repeat('x', 201)));
  insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta 201 chars | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'porta', 'valor', 'consultoria'));
  insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V porta consultoria | reversao', sqlstate); end $t$;
do $t$ declare v jsonb; begin v := dados.black_recorte_valido(jsonb_build_object('tipo', 'conjunto', 'valor', '120256028515140221'));
  insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('V conjunto 1 id | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;

insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'a_um_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'a_um_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'l_prova_a', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028720940221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'l_convite_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550540221,120256028550560221,120256028550580221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'l_dossie_b', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028714850221,120256028714890221,120256028714910221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'l_dois_criativos', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'conjunto', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"conjunto","valor":"120256028515140221"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_perfil (fase, lead_id, canal, a_corrigir, resto)
select 'reversao', p.lead_id, p.canal, p.a_corrigir, md5((to_jsonb(p) - 'pessoa_id' - 'canal' - 'a_corrigir')::text) from public.dados_black_perfil('black-friday-2026-10') p;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', '120256028550580221, 120256028720990221')))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | reversao', 'ok');
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte com espaço (M) | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, jsonb_build_object('tipo', 'anuncio', 'valor', rtrim(repeat('120256028550580221,', 105), ',') || repeat('1', 6))))::text;
  insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | reversao', 'ok:' || md5(v));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B RPC recorte 105 ids (M) | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | reversao', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo todo | reversao', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 1 id | reversao', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}''::jsonb)' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E grupo anuncio 2 criativos | reversao', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select count(*) from public.dados_black_perfil(''black-friday-2026-10'')' loop
    if l ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('E perfil todo | reversao', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"anuncio","valor":"120256028550580221,120256028720990221"}'::jsonb))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_dir (fase, caso, unicos, mql)
select 'reversao', r.caso, (select count(distinct l.pessoa_chave) from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ','))),
       (select count(*) from (select l.pessoa_chave, (array_agg(l.profissao_classe order by l.criado_em desc, l.lead_id desc) filter (where l.profissao_classe is not null))[1] c
                                from dados.black_leads l where not l.teste and l.anuncio_id = any (string_to_array(r.valor, ',')) group by 1) x
         where x.c in ('advogado', 'contador', 'estudante_direito'))
  from (values ('a_um_prova_a', '120256028720990221'), ('a_um_convite_b', '120256028550580221'), ('l_prova_a', '120256028720940221,120256028720990221'), ('l_convite_b', '120256028550540221,120256028550560221,120256028550580221'), ('l_dossie_b', '120256028714850221,120256028714890221,120256028714910221'), ('l_dois_criativos', '120256028550580221,120256028720990221')) r(caso, valor);
-- ===== COMPARAÇÕES =====
reset role;
create function pg_temp.z_num(r jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object('leads_unicos', r#>'{leads,unicos}', 'leads_mql', r#>'{leads,mql}',
    'adv', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'advogado'),
    'cont', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'contador'),
    'outros', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'outros'),
    'cruzados', (select jsonb_agg(g->'unicos_cruzados' order by g->>'segmento') from jsonb_array_elements(r->'grupos') g),
    'cruzados_mql', r->'unicos_cruzados_mql')
$f$;
insert into pg_temp._z_out (passo, linha) select 'M ' || k || ' | ' || fase, v from pg_temp._z_meta
 order by k, case fase when 'antes' then 1 when 'depois' then 2 else 3 end;
insert into pg_temp._z_out (passo, linha) select 'Z meta ' || a.k || ' reversao = antes', (a.v = r.v)::text
  from pg_temp._z_meta a join pg_temp._z_meta r on r.k = a.k and r.fase = 'reversao' where a.fase = 'antes' order by a.k;
insert into pg_temp._z_out (passo, linha) select 'Z meta ' || a.k || ' depois = antes', (a.v = d.v)::text
  from pg_temp._z_meta a join pg_temp._z_meta d on d.k = a.k and d.fase = 'depois' where a.fase = 'antes' and a.k not like 'md5 %' order by a.k;
insert into pg_temp._z_out (passo, linha) select 'N ' || a.caso || ' | ' || a.fase, pg_temp.z_num(a.r)::text from pg_temp._z_r a
 order by a.caso, case a.fase when 'antes' then 1 when 'depois' then 2 else 3 end;
insert into pg_temp._z_out (passo, linha) select 'D direto ' || d.caso || ' | ' || d.fase, jsonb_build_object('unicos', d.unicos, 'mql', d.mql)::text
  from pg_temp._z_dir d order by d.caso, case d.fase when 'antes' then 1 when 'depois' then 2 else 3 end;
-- (1) depois: leads do recorte de anúncio = contagem direta da view
insert into pg_temp._z_out (passo, linha)
select 'Z ' || r.caso || ' depois: RPC = direto', ((r.r#>>'{leads,unicos}')::int = d.unicos and (r.r#>>'{leads,mql}')::int = d.mql)::text
  from pg_temp._z_r r join pg_temp._z_dir d on d.caso = r.caso and d.fase = 'depois' where r.fase = 'depois' order by r.caso;
-- um id: depois = antes, inteiro
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.caso || ' depois = antes', (a.r = d.r)::text
  from pg_temp._z_r a join pg_temp._z_r d on d.caso = a.caso and d.fase = 'depois'
 where a.fase = 'antes' and a.caso in ('todo', '10a12', 'todo_com_teste', 'a_um_prova_a', 'a_um_convite_b', 'conjunto', 'consultoria') order by a.caso;
-- lista de um criativo: depois = o do anúncio que tem lead (os irmãos sem lead não somam ninguém), menos o eco do recorte
insert into pg_temp._z_out (passo, linha)
select 'Z ' || l.caso || ' depois = ' || u.caso || ' (fora o campo recorte)', ((l.r - 'recorte') = (u.r - 'recorte'))::text
  from pg_temp._z_r l join pg_temp._z_r u on u.fase = 'depois'
 where l.fase = 'depois' and (l.caso, u.caso) in (('l_prova_a', 'a_um_prova_a'), ('l_convite_b', 'a_um_convite_b'));
-- reversão = antes, inteiro, em todos os casos
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.caso || ' reversao = antes', (a.r = r.r)::text
  from pg_temp._z_r a join pg_temp._z_r r on r.caso = a.caso and r.fase = 'reversao' where a.fase = 'antes' order by a.caso;
-- (3) a view e o perfil linha a linha
insert into pg_temp._z_out (passo, linha)
select 'Q view depois x antes', jsonb_build_object(
  'linhas_antes', (select count(*) from pg_temp._z_view where fase = 'antes'),
  'linhas_depois', (select count(*) from pg_temp._z_view where fase = 'depois'),
  'sem_par', (select count(*) from ((select lead_id from pg_temp._z_view where fase = 'antes' except select lead_id from pg_temp._z_view where fase = 'depois')
                                  union all (select lead_id from pg_temp._z_view where fase = 'depois' except select lead_id from pg_temp._z_view where fase = 'antes')) x),
  'canal_mudou', (select count(*) from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.canal is distinct from d.canal),
  'canal_mudou_nao_metaads', (select count(*) from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.canal is distinct from d.canal and a.us is distinct from 'metaads'),
  'canal_mudou_para', (select string_agg(distinct coalesce(a.canal, 'null') || '->' || coalesce(d.canal, 'null'), ',') from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.canal is distinct from d.canal),
  'a_corrigir_mudou', (select count(*) from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.a_corrigir is distinct from d.a_corrigir),
  'a_corrigir_mudou_nao_metaads', (select count(*) from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.a_corrigir is distinct from d.a_corrigir and a.us is distinct from 'metaads'),
  'fora_padrao_antes', (select count(*) from pg_temp._z_view where fase = 'antes' and 'utm_campaign_fora_do_padrao' = any (a_corrigir)),
  'fora_padrao_depois', (select count(*) from pg_temp._z_view where fase = 'depois' and 'utm_campaign_fora_do_padrao' = any (a_corrigir)),
  'metaads_linhas', (select count(*) from pg_temp._z_view where fase = 'antes' and us = 'metaads'),
  'resto_mudou', (select count(*) from pg_temp._z_view a join pg_temp._z_view d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.resto <> d.resto),
  'canal_meta_antes', (select count(*) from pg_temp._z_view where fase = 'antes' and canal = 'meta'),
  'canal_meta_depois', (select count(*) from pg_temp._z_view where fase = 'depois' and canal = 'meta'))::text;
insert into pg_temp._z_out (passo, linha)
select 'Q view reversao = antes', (not exists (select a.lead_id, a.canal, a.a_corrigir, a.resto from pg_temp._z_view a where a.fase = 'antes'
   except select r.lead_id, r.canal, r.a_corrigir, r.resto from pg_temp._z_view r where r.fase = 'reversao')
  and (select count(*) from pg_temp._z_view where fase = 'antes') = (select count(*) from pg_temp._z_view where fase = 'reversao'))::text;
insert into pg_temp._z_out (passo, linha)
select 'Q perfil depois x antes', jsonb_build_object(
  'linhas_antes', (select count(*) from pg_temp._z_perfil where fase = 'antes'),
  'linhas_depois', (select count(*) from pg_temp._z_perfil where fase = 'depois'),
  'canal_mudou', (select count(*) from pg_temp._z_perfil a join pg_temp._z_perfil d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.canal is distinct from d.canal),
  'a_corrigir_mudou', (select count(*) from pg_temp._z_perfil a join pg_temp._z_perfil d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.a_corrigir is distinct from d.a_corrigir),
  'resto_mudou', (select count(*) from pg_temp._z_perfil a join pg_temp._z_perfil d on d.lead_id = a.lead_id and d.fase = 'depois' where a.fase = 'antes' and a.resto <> d.resto),
  'mudou_e_nao_metaads', (select count(*) from pg_temp._z_perfil a join pg_temp._z_perfil d on d.lead_id = a.lead_id and d.fase = 'depois'
      join pg_temp._z_view v on v.lead_id = a.lead_id and v.fase = 'antes'
     where a.fase = 'antes' and (a.canal is distinct from d.canal or a.a_corrigir is distinct from d.a_corrigir) and v.us is distinct from 'metaads'))::text;
insert into pg_temp._z_out (passo, linha)
select 'Q perfil reversao = antes', (not exists (select a.lead_id, a.canal, a.a_corrigir, a.resto from pg_temp._z_perfil a where a.fase = 'antes'
   except select r.lead_id, r.canal, r.a_corrigir, r.resto from pg_temp._z_perfil r where r.fase = 'reversao')
  and (select count(*) from pg_temp._z_perfil where fase = 'antes') = (select count(*) from pg_temp._z_perfil where fase = 'reversao'))::text;
-- travas e validações: antes / depois / reversão lado a lado
insert into pg_temp._z_out (passo, linha)
select 'T ' || split_part(a.passo, ' | ', 1), a.linha || ' / ' || d.linha || ' / ' || r.linha
  from pg_temp._z_out a join pg_temp._z_out d on d.passo = replace(a.passo, '| antes', '| depois') join pg_temp._z_out r on r.passo = replace(a.passo, '| antes', '| reversao')
 where a.passo ~ '^(B|V|G|E) .*\| antes$' order by a.em;
select passo, linha from pg_temp._z_out where passo !~ '^(B|V|G|E) ' or passo ~ '^E grupo anuncio 105' order by em;
rollback;
