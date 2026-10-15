-- Ensaio de 20261015230200_dados_black_lives_importar_ausente_null.sql (transação desfeita, sobre produção).
-- Prova: (1) a migration não mexe em nenhum dado; (2) ANTES, ausente virava 0; DEPOIS, vira NULL; (3) reenviar os valores reais
-- dos 3 CSVs muda 0 linhas; (4) a leitura (lista e detalhe) trata NULL; (5) recusas e grants; (6) explain analyze; (7) reversão byte a byte.
-- Grava só em uma live sem minutos (dentro da transação, desfeita no fim). Nenhum dado pessoal.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create temp table _z_r (caso text, r jsonb);
grant all on pg_temp._z_r to authenticated;

do $pre$ begin
  if (select count(*) from dados.black_live_minuto where video_id = 'A9d6HjegnTk') <> 0 then raise exception 'live de teste A9d6HjegnTk já tem minutos'; end if;
end $pre$;
create temp table _z_antes as select md5(prosrc) h from pg_proc where oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure;
insert into pg_temp._z_out (passo, linha) select '0 ANTES: md5 do corpo (esperado 277d99ca683afb3d11c33663106ffb9a)', h from _z_antes;
create temp table _z_snap_antes as
  select video_id, origem, count(*) n, count(*) filter (where chat is null) chat_null, count(*) filter (where reacoes is null) rea_null,
         md5(string_agg(seg || ':' || coalesce(espectadores::text, 'n') || ':' || coalesce(chat::text, 'n') || ':' || coalesce(reacoes::text, 'n'), ',' order by seg)) h
    from dados.black_live_minuto group by video_id, origem;

-- ANTES: ausente vira 0
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_r select 'antes_grava', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50,"chat":3},{"seg":120,"espectadores":100,"reacoes":2},{"seg":180,"espectadores":95,"chat":0,"reacoes":0}]'::jsonb, true);
reset role;
insert into pg_temp._z_out (passo, linha) select '1 ANTES: gravado com chat/reações ausentes (seg:chat:reacoes)',
  (select string_agg(seg || ':' || coalesce(chat::text, 'NULL') || ':' || coalesce(reacoes::text, 'NULL'), ' ' order by seg) from dados.black_live_minuto where video_id = 'A9d6HjegnTk' and origem = 'studio');
delete from dados.black_live_minuto where video_id = 'A9d6HjegnTk';

-- ═══ migration inteira ═══
-- 20261015230200: importar o CSV do Studio grava NULL (e não 0) quando chat ou reações não vêm no arquivo.
--
-- POR QUE (correção pedida pelo orquestrador em 15/10/2026): dados_black_live_importar (20261015220000) fazia
-- coalesce(chat, 0) e coalesce(reacoes, 0). Coluna ausente ou célula vazia do CSV virava 0 no banco, e 0 é um número
-- ("ninguém escreveu no chat"), não a ausência do número. A tela somava esse 0 como dado. A regra do desenho é: ausência
-- é NULL (o mesmo que a origem 'api' já faz com reações). A leitura (dados_black_lives, dados_black_live_detalhe) já trata
-- NULL: sum() sem nenhuma linha preenchida devolve null e o detalhe devolve a chave com null.
--
-- O QUE FAZ (só o corpo de public.dados_black_live_importar; assinatura, grants, security definer e search_path não mudam)
--   a. Prévia e gravação: (e ->> 'chat')::int e (e ->> 'reacoes')::int, sem coalesce. Chave ausente = NULL.
--   b. A comparação da prévia (alteradas) já usava "is distinct from", que trata NULL: reenviar o mesmo arquivo continua
--      dando alteradas = 0; trocar 0 por ausente (ou o contrário) conta como alteração.
--   c. A validação não muda: chat e reacoes inteiros >= 0 ou ausentes. Um "chat": null explícito continua recusado (22023);
--      o front omite a chave.
--   d. Dados já gravados NÃO são tocados. Conferido em produção contra os 3 CSVs do Studio (6/10, 8/10 e 13/10): os arquivos
--      não têm nenhuma célula vazia de chat nem de reações (298 linhas, todas preenchidas), então os 0 gravados são 0 do
--      arquivo. Nada a corrigir.
--
-- AS 5 PERGUNTAS
--   escala: a importação é feita por um master, até 2.000 linhas por chamada, ~100 por live. Não cresce com a base.
--   índice: lê black_live_minuto pela PK (video_id, origem, seg); a consulta não muda de forma. Plano no .explain.md.
--   frequência: manual (botão de importar da aba Lives), poucas vezes por live.
--   repetição: uma chamada de prévia e uma de gravação por arquivo; idempotente.
--   reversão: 20261015230200_reversao.sql devolve o corpo anterior (md5 do prosrc 277d99ca683afb3d11c33663106ffb9a).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('public.dados_black_live_importar(text,text,jsonb,boolean)') is null then
    raise exception '20261015230200: aplique antes 20261015220000 (dados_black_live_importar ausente)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure)
       <> '277d99ca683afb3d11c33663106ffb9a' then
    raise exception '20261015230200: dados_black_live_importar não está no corpo esperado (alguém mudou depois da 20261015220000)';
  end if;
end
$g$;

create or replace function public.dados_black_live_importar(p_chave text, p_video_id text, p_linhas jsonb, p_confirmar boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);   -- 42501 se não for master, P0002 fora da Black
  v_n int; v_invalidas int; v_dup int; v_alt int; v_exist int;
  v_pico int; v_pico_seg int; v_dur int;
begin
  if not exists (select 1 from dados.black_lives l where l.video_id = p_video_id and l.chave = d.chave and l.ativo) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_linhas) is distinct from 'array' then
    raise exception 'p_linhas deve ser uma lista' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n < 1 or v_n > 2000 then
    raise exception 'p_linhas deve ter de 1 a 2000 linhas' using errcode = '22023';
  end if;
  -- toda linha: objeto com seg e espectadores inteiros >= 0; chat e reacoes inteiros >= 0 ou ausentes
  select count(*) into v_invalidas
    from jsonb_array_elements(p_linhas) e
   where jsonb_typeof(e) <> 'object'
      or jsonb_typeof(e -> 'seg') is distinct from 'number' or (e ->> 'seg') !~ '^[0-9]{1,7}$'
      or jsonb_typeof(e -> 'espectadores') is distinct from 'number' or (e ->> 'espectadores') !~ '^[0-9]{1,7}$'
      or (e ? 'chat' and (jsonb_typeof(e -> 'chat') is distinct from 'number' or (e ->> 'chat') !~ '^[0-9]{1,7}$'))
      or (e ? 'reacoes' and (jsonb_typeof(e -> 'reacoes') is distinct from 'number' or (e ->> 'reacoes') !~ '^[0-9]{1,7}$'));
  if v_invalidas > 0 then
    raise exception 'p_linhas tem % linha(s) inválida(s)', v_invalidas using errcode = '22023';
  end if;

  -- sem tabela temporária (a função roda mais de uma vez na mesma transação nos ensaios): o CTE "n" repete em cada consulta
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores
               from jsonb_array_elements(p_linhas) e)
  select count(*) - count(distinct seg), max(espectadores), max(seg) + 60,
         min(seg) filter (where espectadores = (select max(espectadores) from n))
    into v_dup, v_pico, v_dur, v_pico_seg from n;
  if v_dup > 0 then
    raise exception 'p_linhas tem seg repetido' using errcode = '22023';
  end if;
  select count(*) into v_exist from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores,
                    (e ->> 'chat')::int as chat, (e ->> 'reacoes')::int as reacoes
               from jsonb_array_elements(p_linhas) e)
  select count(*) into v_alt
    from n
    full join (select seg, espectadores, chat, reacoes from dados.black_live_minuto
                where video_id = p_video_id and origem = 'studio') o using (seg)
   where n.espectadores is null or o.espectadores is null
      or n.espectadores is distinct from o.espectadores or n.chat is distinct from o.chat or n.reacoes is distinct from o.reacoes;

  if p_confirmar is true and v_alt > 0 then
    delete from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
    insert into dados.black_live_minuto (video_id, origem, seg, espectadores, chat, reacoes)
    select p_video_id, 'studio', (e ->> 'seg')::int, (e ->> 'espectadores')::int,
           (e ->> 'chat')::int, (e ->> 'reacoes')::int
      from jsonb_array_elements(p_linhas) e;
    update dados.black_lives set atualizado_em = now() where video_id = p_video_id;
  end if;
  return jsonb_build_object('linhas', v_n, 'pico', v_pico, 'pico_seg', v_pico_seg, 'duracao_seg', v_dur,
                            'existentes', v_exist, 'alteradas', v_alt, 'gravado', (p_confirmar is true and v_alt > 0));
end
$function$;

do $conf$
declare v_src text; v_acl text;
begin
  select p.prosrc, p.proacl::text into v_src, v_acl from pg_proc p
   where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure;
  if v_src ~ 'coalesce' then
    raise exception '20261015230200: o corpo novo ainda tem coalesce';
  end if;
  if has_function_privilege('anon', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute')
     or has_function_privilege('service_role', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute') then
    raise exception '20261015230200: grants de dados_black_live_importar mudaram';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure
                    and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception '20261015230200: dados_black_live_importar perdeu security definer ou search_path vazio';
  end if;
end
$conf$;

-- ═══ fim da migration ═══

create temp table _z_snap_depois as
  select video_id, origem, count(*) n, count(*) filter (where chat is null) chat_null, count(*) filter (where reacoes is null) rea_null,
         md5(string_agg(seg || ':' || coalesce(espectadores::text, 'n') || ':' || coalesce(chat::text, 'n') || ':' || coalesce(reacoes::text, 'n'), ',' order by seg)) h
    from dados.black_live_minuto group by video_id, origem;
insert into pg_temp._z_out (passo, linha) select '2 DEPOIS: dados dos 3 CSVs intactos (linhas e md5 iguais; esperado true)',
  (select (select count(*) from _z_snap_antes) = (select count(*) from _z_snap_depois)
      and not exists (select 1 from _z_snap_antes a full join _z_snap_depois d using (video_id, origem) where a.h is distinct from d.h or a.n is distinct from d.n))::text;
insert into pg_temp._z_out (passo, linha) select '2 DEPOIS: linhas studio com chat NULL / reações NULL em produção (esperado 0 / 0)',
  coalesce(sum(chat_null) filter (where origem = 'studio'), 0) || ' / ' || coalesce(sum(rea_null) filter (where origem = 'studio'), 0) from _z_snap_depois;

-- DEPOIS: ausente vira NULL
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_r select 'prev_ausente', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50,"chat":3},{"seg":120,"espectadores":100,"reacoes":2},{"seg":180,"espectadores":95,"chat":0,"reacoes":0}]'::jsonb, false);
reset role;
set local role authenticated;
insert into pg_temp._z_r select 'grava_ausente', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50,"chat":3},{"seg":120,"espectadores":100,"reacoes":2},{"seg":180,"espectadores":95,"chat":0,"reacoes":0}]'::jsonb, true);
reset role;
set local role authenticated;
insert into pg_temp._z_r select 'regrava_ausente', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50,"chat":3},{"seg":120,"espectadores":100,"reacoes":2},{"seg":180,"espectadores":95,"chat":0,"reacoes":0}]'::jsonb, true);
reset role;
insert into pg_temp._z_out (passo, linha) select '3 DEPOIS: gravado com chat/reações ausentes (seg:chat:reacoes; esperado NULL onde ausente, 0 onde veio 0)',
  (select string_agg(seg || ':' || coalesce(chat::text, 'NULL') || ':' || coalesce(reacoes::text, 'NULL'), ' ' order by seg) from dados.black_live_minuto where video_id = 'A9d6HjegnTk' and origem = 'studio');
insert into pg_temp._z_out (passo, linha) select '3 prévia (esperado alteradas=4, gravado=false)', r::text from pg_temp._z_r where caso = 'prev_ausente';
insert into pg_temp._z_out (passo, linha) select '3 grava (esperado alteradas=4, gravado=true)', r::text from pg_temp._z_r where caso = 'grava_ausente';
insert into pg_temp._z_out (passo, linha) select '3 regrava o mesmo (esperado alteradas=0, gravado=false)', r::text from pg_temp._z_r where caso = 'regrava_ausente';
-- trocar 0 por ausente conta como alteração: seg 180 vira ausente
set local role authenticated;
insert into pg_temp._z_r select 'muda_0_para_ausente', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50,"chat":3},{"seg":120,"espectadores":100,"reacoes":2},{"seg":180,"espectadores":95}]'::jsonb, false);
reset role;
insert into pg_temp._z_out (passo, linha) select '3 trocar 0 por ausente em 1 minuto (esperado alteradas=1)', r ->> 'alteradas' from pg_temp._z_r where caso = 'muda_0_para_ausente';

-- reenviar os valores reais das 3 lives (lidos da própria tabela): nada muda
do $real$ declare v record; j jsonb; r jsonb;
begin
  for v in select distinct video_id from dados.black_live_minuto where origem = 'studio' and video_id <> 'A9d6HjegnTk' order by 1 loop
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('seg', seg, 'espectadores', espectadores, 'chat', chat, 'reacoes', reacoes)) order by seg) into j
      from dados.black_live_minuto where video_id = v.video_id and origem = 'studio';
    perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
    set local role authenticated;
    r := public.dados_black_live_importar('black-friday-2026-10', v.video_id, j, false);
    reset role;
    insert into pg_temp._z_out (passo, linha) values ('4 reenvio dos valores reais (esperado alteradas=0, gravado=false): linhas=' || (r ->> 'linhas'), (r ->> 'alteradas') || ' ' || (r ->> 'gravado'));
  end loop;
end $real$;

-- leitura com NULL (a live de teste tem chat e reações em parte dos minutos; ver também uma só com NULL)
set local role authenticated;
insert into pg_temp._z_r select 'so_espectadores', public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":10},{"seg":60,"espectadores":50}]'::jsonb, true);
reset role;
set local role authenticated;
insert into pg_temp._z_r select 'lista', public.dados_black_lives('black-friday-2026-10');
insert into pg_temp._z_r select 'detalhe', public.dados_black_live_detalhe('black-friday-2026-10', 'A9d6HjegnTk');
reset role;
insert into pg_temp._z_out (passo, linha) select '5 lista: live só com espectadores (esperado chat_total=null reacoes_total=null pico=50)',
  'chat_total=' || coalesce(x ->> 'chat_total', 'null') || ' reacoes_total=' || coalesce(x ->> 'reacoes_total', 'null') || ' pico=' || coalesce(x ->> 'pico', 'null')
  from pg_temp._z_r, jsonb_array_elements(r -> 'lives') x where caso = 'lista' and x ->> 'video_id' = 'A9d6HjegnTk';
insert into pg_temp._z_out (passo, linha) select '5 detalhe: minutos (esperado chat e reacoes null nos 2)', (r -> 'minutos')::text from pg_temp._z_r where caso = 'detalhe';

-- recusas e grants
do $rec$ declare s text;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  begin perform public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":1}]'::jsonb, true); s := 'sem erro'; exception when others then s := sqlstate; end;
  reset role; insert into pg_temp._z_out (passo, linha) values ('6 anon importa (esperado 42501)', s);
  perform set_config('request.jwt.claims', '{"sub":"e303b8d1-e31a-4539-a450-259a8cb1d71a","role":"authenticated"}', true);
  set local role authenticated;
  begin perform public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":1}]'::jsonb, true); s := 'sem erro'; exception when others then s := sqlstate; end;
  reset role; insert into pg_temp._z_out (passo, linha) values ('6 não master importa (esperado 42501)', s);
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  begin perform public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":1,"chat":null}]'::jsonb, false); s := 'sem erro'; exception when others then s := sqlstate; end;
  reset role; insert into pg_temp._z_out (passo, linha) values ('6 "chat": null explícito (esperado 22023, como antes)', s);
  set local role authenticated;
  begin perform public.dados_black_live_importar('black-friday-2026-10', 'A9d6HjegnTk', '[{"seg":0,"espectadores":1,"chat":-1}]'::jsonb, false); s := 'sem erro'; exception when others then s := sqlstate; end;
  reset role; insert into pg_temp._z_out (passo, linha) values ('6 chat negativo (esperado 22023)', s);
end $rec$;
insert into pg_temp._z_out (passo, linha) select '6 grants: anon / authenticated / service_role (esperado false / true / false)',
  has_function_privilege('anon', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute') || ' / ' ||
  has_function_privilege('authenticated', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute') || ' / ' ||
  has_function_privilege('service_role', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute');

-- explain (analyze, buffers) da consulta de comparação da prévia, com as linhas reais da maior live (121) (como postgres; 2 execuções)
create temp table _z_j as
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('seg', seg, 'espectadores', espectadores, 'chat', chat, 'reacoes', reacoes)) order by seg) j
    from dados.black_live_minuto where video_id = (select video_id from dados.black_live_minuto where origem = 'studio' group by video_id order by count(*) desc, video_id limit 1) and origem = 'studio';
grant select on pg_temp._z_j to authenticated;
do $x$ declare r record; n int; v_id text;
begin
  select video_id into v_id from dados.black_live_minuto where origem = 'studio' group by video_id order by count(*) desc, video_id limit 1;
  for n in 1..2 loop
    for r in execute format($q$explain (analyze, buffers)
      with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores,
                        (e ->> 'chat')::int as chat, (e ->> 'reacoes')::int as reacoes
                   from jsonb_array_elements((select j from pg_temp._z_j)) e)
      select count(*) from n
        full join (select seg, espectadores, chat, reacoes from dados.black_live_minuto where video_id = %L and origem = 'studio') o using (seg)
       where n.espectadores is null or o.espectadores is null
          or n.espectadores is distinct from o.espectadores or n.chat is distinct from o.chat or n.reacoes is distinct from o.reacoes$q$, v_id) loop
      if r."QUERY PLAN" ~ '(Scan|Execution Time|Planning Time|Buffers: shared|Join)' then insert into pg_temp._z_out (passo, linha) values ('7 explain comparação da prévia ' || n, r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
do $y$ declare r record; n int; v_id text;
begin
  select video_id into v_id from dados.black_live_minuto where origem = 'studio' group by video_id order by count(*) desc, video_id limit 1;
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  for n in 1..2 loop
    for r in execute format($q$explain (analyze, buffers) select public.dados_black_live_importar('black-friday-2026-10', %L, (select j from pg_temp._z_j), false)$q$, v_id) loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time|Buffers: shared)' then insert into pg_temp._z_out (passo, linha) values ('7 explain RPC inteira (prévia, linhas reais da maior live) ' || n, r."QUERY PLAN"); end if;
    end loop;
  end loop;
  reset role;
end $y$;

-- reversão ensaiada: o corpo antigo volta byte a byte
-- Reversão de 20261015230200: devolve o corpo anterior de public.dados_black_live_importar (ausente vira 0 de novo).
-- Os dados já gravados não mudam (a reversão só troca a função). md5 do prosrc anterior: 277d99ca683afb3d11c33663106ffb9a.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.dados_black_live_importar(p_chave text, p_video_id text, p_linhas jsonb, p_confirmar boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);   -- 42501 se não for master, P0002 fora da Black
  v_n int; v_invalidas int; v_dup int; v_alt int; v_exist int;
  v_pico int; v_pico_seg int; v_dur int;
begin
  if not exists (select 1 from dados.black_lives l where l.video_id = p_video_id and l.chave = d.chave and l.ativo) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_linhas) is distinct from 'array' then
    raise exception 'p_linhas deve ser uma lista' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n < 1 or v_n > 2000 then
    raise exception 'p_linhas deve ter de 1 a 2000 linhas' using errcode = '22023';
  end if;
  -- toda linha: objeto com seg e espectadores inteiros >= 0; chat e reacoes inteiros >= 0 ou ausentes
  select count(*) into v_invalidas
    from jsonb_array_elements(p_linhas) e
   where jsonb_typeof(e) <> 'object'
      or jsonb_typeof(e -> 'seg') is distinct from 'number' or (e ->> 'seg') !~ '^[0-9]{1,7}$'
      or jsonb_typeof(e -> 'espectadores') is distinct from 'number' or (e ->> 'espectadores') !~ '^[0-9]{1,7}$'
      or (e ? 'chat' and (jsonb_typeof(e -> 'chat') is distinct from 'number' or (e ->> 'chat') !~ '^[0-9]{1,7}$'))
      or (e ? 'reacoes' and (jsonb_typeof(e -> 'reacoes') is distinct from 'number' or (e ->> 'reacoes') !~ '^[0-9]{1,7}$'));
  if v_invalidas > 0 then
    raise exception 'p_linhas tem % linha(s) inválida(s)', v_invalidas using errcode = '22023';
  end if;

  -- sem tabela temporária (a função roda mais de uma vez na mesma transação nos ensaios): o CTE "n" repete em cada consulta
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores
               from jsonb_array_elements(p_linhas) e)
  select count(*) - count(distinct seg), max(espectadores), max(seg) + 60,
         min(seg) filter (where espectadores = (select max(espectadores) from n))
    into v_dup, v_pico, v_dur, v_pico_seg from n;
  if v_dup > 0 then
    raise exception 'p_linhas tem seg repetido' using errcode = '22023';
  end if;
  select count(*) into v_exist from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores,
                    coalesce((e ->> 'chat')::int, 0) as chat, coalesce((e ->> 'reacoes')::int, 0) as reacoes
               from jsonb_array_elements(p_linhas) e)
  select count(*) into v_alt
    from n
    full join (select seg, espectadores, chat, reacoes from dados.black_live_minuto
                where video_id = p_video_id and origem = 'studio') o using (seg)
   where n.espectadores is null or o.espectadores is null
      or n.espectadores is distinct from o.espectadores or n.chat is distinct from o.chat or n.reacoes is distinct from o.reacoes;

  if p_confirmar is true and v_alt > 0 then
    delete from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
    insert into dados.black_live_minuto (video_id, origem, seg, espectadores, chat, reacoes)
    select p_video_id, 'studio', (e ->> 'seg')::int, (e ->> 'espectadores')::int,
           coalesce((e ->> 'chat')::int, 0), coalesce((e ->> 'reacoes')::int, 0)
      from jsonb_array_elements(p_linhas) e;
    update dados.black_lives set atualizado_em = now() where video_id = p_video_id;
  end if;
  return jsonb_build_object('linhas', v_n, 'pico', v_pico, 'pico_seg', v_pico_seg, 'duracao_seg', v_dur,
                            'existentes', v_exist, 'alteradas', v_alt, 'gravado', (p_confirmar is true and v_alt > 0));
end
$function$;

do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure)
       <> '277d99ca683afb3d11c33663106ffb9a' then
    raise exception 'reversão de 20261015230200 incompleta (corpo diferente do original)';
  end if;
  if has_function_privilege('anon', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute') then
    raise exception 'reversão de 20261015230200: grants mudaram';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '8 depois da reversão: corpo igual ao de antes (esperado true)', (select md5(prosrc) = a.h from pg_proc, _z_antes a where oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure)::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
