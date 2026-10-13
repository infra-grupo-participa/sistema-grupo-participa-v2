-- Ensaio de 20261013114630 (transação desfeita, REPEATABLE READ). Miniatura e conta no tráfego da Black.
-- Prova: (1) depois, o resultado de dados_black_trafego sem as 2 chaves novas (conta_externa, miniatura_caminho) é
-- idêntico ao de antes (todo o período e 10 a 12/10), e a reversão volta ao de antes; (2) as chaves novas batem com as
-- tabelas de origem e url_tags não aparece em lugar nenhum do retorno; (3) storage: antes ninguém (fora a service_role)
-- enxerga objeto do bucket trafego-miniaturas; depois a equipe enxerga exatamente as miniaturas dos anúncios da Black
-- (conjunto calculado direto das tabelas, sem a função nova) e mais nada; fora da equipe e anon continuam com 0; equipe
-- não grava, não altera e não apaga; (4) ATM: dados_atm_trafego com o mesmo md5 de retorno e de corpo nas 3 fases;
-- (5) travas da RPC (P0002, 42501) iguais nas 3 fases.
-- Só contagens, md5 e sqlstate. Gerado por um script a partir da migration e da reversão (texto sem mudança).
-- E (equipe) é buscado no banco (perfil ativo @advmais.com, a regra de gp_eh_equipe); o uid de fora da equipe é fictício.
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_r (fase text, periodo text, r jsonb) on commit drop;
create temp table _z_vis (fase text, nome text) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_r, pg_temp._z_vis to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('ensaio.e', coalesce((select p.id::text from public.perfis p
  where p.status = 'ativo' and p.email ilike '%@advmais.com' order by p.id limit 1), ''), true);
do $q$ begin
  if current_setting('ensaio.e') = '' then raise exception 'ensaio: nenhum perfil ativo da equipe no banco'; end if;
end $q$;
-- o retorno sem as 2 chaves novas
create function pg_temp.z_sem_novas(r jsonb) returns jsonb language sql immutable as $f$
  select r || jsonb_build_object(
    'campanhas', coalesce((select jsonb_agg(e - 'conta_externa' order by o) from jsonb_array_elements(r->'campanhas') with ordinality x(e, o)), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(e - 'miniatura_caminho' order by o) from jsonb_array_elements(r->'anuncios') with ordinality x(e, o)), '[]'::jsonb))
$f$;
-- miniaturas esperadas: objetos do bucket que são miniatura de um anúncio que a RPC (antes) devolve para a Black
create temp table _z_esperado on commit drop as
  select distinct o.name from storage.objects o join mkt_trafego.anuncios a on a.miniatura_caminho = o.name
   where o.bucket_id = 'trafego-miniaturas' and false;

-- ===== 1. ANTES =====
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'antes', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'antes', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_atm_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | antes', sqlstate); end $t$;
insert into pg_temp._z_vis (fase, nome) select 'antes', o.name from storage.objects o where o.bucket_id = 'trafego-miniaturas';
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | antes', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | antes', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.trafego_miniatura_pode_ver('meta/1/1.jpg'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | antes', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | antes', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego anon | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego anon | antes', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | antes', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'B md5 prosrc dados_atm_trafego | antes', md5(prosrc) from pg_proc where oid = 'public.dados_atm_trafego(text,date,date)'::regprocedure;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select name from storage.objects where bucket_id = ''trafego-miniaturas''' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain objetos do bucket (E) | antes', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_esperado
  select distinct o.name from pg_temp._z_r z cross join lateral jsonb_array_elements(z.r->'anuncios') e
    join mkt_trafego.anuncios a on a.id::text = e->>'id'
    join storage.objects o on o.bucket_id = 'trafego-miniaturas' and o.name = a.miniatura_caminho
   where z.fase = 'antes' and z.periodo = 'todo';

-- ===== 2. MIGRATION (texto de 20261013114630_dados_black_trafego_miniatura.sql) =====
-- 20261013114630: miniatura e conta no tráfego da Black (cartões de criativo: miniatura e "Abrir no Gerenciador").
-- Pedido do Maestro (13/10/2026), branch victor-black-miniatura. Muda só isto:
--   1. public.dados_black_trafego: cada item de "anuncios" ganha "miniatura_caminho" (mkt_trafego.anuncios.miniatura_caminho,
--      caminho no bucket privado trafego-miniaturas, nunca URL); cada item de "campanhas" ganha "conta_externa"
--      (mkt_trafego.contas.conta_externa, id da conta no Meta). url_tags continua FORA. Nenhuma outra chave, filtro, junção
--      ou total muda (o ensaio prova: resultado sem as 2 chaves novas = resultado de antes).
--   2. public.trafego_miniatura_pode_ver(text) (security definer, só authenticated) + policy trafego_miniaturas_ler
--      (SELECT em storage.objects, só authenticated, só bucket_id = 'trafego-miniaturas'): a equipe lê só as miniaturas
--      dos anúncios das campanhas do dashboard que ela vê. O navegador assina a URL (curta) com a sessão do usuário,
--      como o crm-midia (20261007140044). Gravar e apagar no bucket continua só com a service_role (sem policy).
-- Dono, ACL, security definer e search_path de dados_black_trafego iguais. Pré-requisito: corpo vivo = o gravado por
-- 20261013021259 (md5 conferido abaixo). Reversão: 20261013114630_reversao.sql. Explicação e números: 20261013114630.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> 'fed8b153787d04164174610ec917e5e4' then
    raise exception '20261013114630: corpo vivo de dados_black_trafego mudou. Reler.';
  end if;
  if to_regprocedure('public.trafego_miniatura_pode_ver(text)') is not null then
    raise exception '20261013114630: public.trafego_miniatura_pode_ver(text) já existe.';
  end if;
  if not exists (select 1 from storage.buckets b where b.id = 'trafego-miniaturas' and not b.public) then
    raise exception '20261013114630: bucket trafego-miniaturas não existe ou é público.';
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
              and (p.policyname = 'trafego_miniaturas_ler'
                   or coalesce(p.qual, '') || coalesce(p.with_check, '') like '%trafego-miniaturas%')) then
    raise exception '20261013114630: já existe policy trafego_miniaturas_ler ou citando o bucket trafego-miniaturas.';
  end if;
  -- Mesma conferência C11 de 20261012212726: nenhuma policy PERMISSIVA em storage.objects para anon, authenticated ou
  -- public sem filtro de bucket_id (abriria o bucket por fora desta regra).
  if exists (select 1 from pg_policies p
              where p.schemaname = 'storage' and p.tablename = 'objects' and p.permissive = 'PERMISSIVE'
                and (p.roles && array['anon', 'authenticated', 'public']::name[])
                and ((p.qual is null and p.with_check is null)
                     or (p.qual is not null and p.qual not like '%bucket_id%')
                     or (p.with_check is not null and p.with_check not like '%bucket_id%'))) then
    raise exception '20261013114630: policy em storage.objects para anon/authenticated/public sem filtro de bucket_id (C11).';
  end if;
end
$g$;

-- 1. dados_black_trafego com miniatura_caminho (anúncios) e conta_externa (campanhas)
CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d dados.dashboards := dados.black_cadastro(p_chave);
  v_de date; v_ate date;
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    -- 20261013100000: campanhas do projeto do cadastro; a campanha sem projeto_id (o CPF01 hoje; ver o explain) entra
    -- quando um dos termos entre barras do nome é a sigla do projeto (BF26). O termo vem do cadastro, não fica fixo aqui.
    select c.id, c.nome, c.plataforma, c.status_plataforma, c.objetivo, c.projeto_id, ct.nome as conta,
           c.campanha_externa,   -- 20261013014209: id da campanha no Meta (recorte do grupo por campanha)
           ct.conta_externa,     -- id da conta no Meta (link "Abrir no Gerenciador" do criativo)
           e.etapa, e.subtipo, e.conflito
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao, j.conjunto_externa   -- 20261013014209
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id,
                a.miniatura_caminho   -- caminho no bucket privado trafego-miniaturas (url_tags continua fora)
           from mkt_trafego.anuncios a join cj on cj.id = a.conjunto_id),
  dc as (select x.* from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  da as (select x.* from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date))
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL',
    'coletado_em', greatest((select max(coletado_em) from dc), (select max(coletado_em) from da)),
    -- primeiro dia com quebra por anúncio, em qualquer data (antes dele só existe o número por campanha)
    'anuncio_desde', (select min(x.dia) from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'plataforma', c.plataforma, 'status', c.status_plataforma, 'objetivo', c.objetivo,
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito,
      'campanha_externa', c.campanha_externa, 'conta_externa', c.conta_externa
    ) order by c.nome) from c), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao, 'conjunto_externa', j.conjunto_externa
    ) order by j.nome, j.id) from cj j), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'conjunto_id', a.conjunto_id, 'nome', a.nome, 'status', a.status_plataforma,
      'anuncio_externa', a.anuncio_externa, 'video_id', a.video_id, 'miniatura_caminho', a.miniatura_caminho
    ) order by a.nome, a.id) from an a), '[]'::jsonb),
    'dias_campanha', coalesce((select jsonb_agg(jsonb_build_object(
      'campanha_id', x.campanha_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.campanha_id) from dc x), '[]'::jsonb),
    'dias_anuncio', coalesce((select jsonb_agg(jsonb_build_object(
      'anuncio_id', x.anuncio_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.anuncio_id) from da x), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_black_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_black_trafego(text, date, date) to authenticated;

-- 2. leitura das miniaturas pela equipe
create function public.trafego_miniatura_pode_ver(p_nome text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  -- Quem pode ler (e portanto assinar a URL de) uma miniatura do bucket trafego-miniaturas: a equipe (a mesma checagem
  -- de dados.cadastro, que todas as dados_* usam) e só o objeto que é miniatura de um anúncio de campanha de um
  -- dashboard jornada-captacao ativo que ela pode ver (mesma regra de campanha de dados_black_trafego: projeto do
  -- cadastro, ou projeto nulo com a sigla do projeto entre barras no nome; conta em BRL).
  select coalesce(p_nome is not null
     and coalesce(public.gp_eh_equipe(), false)
     and exists (
       select 1
         from mkt_trafego.anuncios a
         join mkt_trafego.conjuntos j on j.id = a.conjunto_id
         join mkt_trafego.campanhas c on c.id = j.campanha_id
         join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
         join dados.dashboards d on d.ativo and d.modelo = 'jornada-captacao'
         join mkt.projetos p on p.id = d.projeto_id
        where a.miniatura_caminho = p_nome
          and dados.pode_ver(d.chave)
          and (c.projeto_id = d.projeto_id
               or (c.projeto_id is null
                   and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla))))), false)
$function$;
revoke all on function public.trafego_miniatura_pode_ver(text) from public, anon, service_role;
grant execute on function public.trafego_miniatura_pode_ver(text) to authenticated;

create policy trafego_miniaturas_ler on storage.objects for select to authenticated
  using (bucket_id = 'trafego-miniaturas' and public.trafego_miniatura_pode_ver(name));

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '4ecabc5c67e683f8f5523c2fe739d00c' then
    raise exception '20261013114630: corpo de dados_black_trafego diferente do arquivo';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) then
    raise exception '20261013114630: permissão de dados_black_trafego errada';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.trafego_miniatura_pode_ver(text)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.trafego_miniatura_pode_ver(text)'::regprocedure) then
    raise exception '20261013114630: permissão de trafego_miniatura_pode_ver errada';
  end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
         and coalesce(qual, '') || coalesce(with_check, '') like '%trafego-miniaturas%') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'trafego_miniaturas_ler'
                      and cmd = 'SELECT' and roles = array['authenticated']::name[] and permissive = 'PERMISSIVE') then
    raise exception '20261013114630: policy do bucket trafego-miniaturas diferente do esperado';
  end if;
end
$c$;

-- ===== fim da migration =====
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'depois', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'depois', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_atm_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | depois', sqlstate); end $t$;
insert into pg_temp._z_vis (fase, nome) select 'depois', o.name from storage.objects o where o.bucket_id = 'trafego-miniaturas';
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | depois', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | depois', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.trafego_miniatura_pode_ver('meta/1/1.jpg'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | depois', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | depois', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego anon | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego anon | depois', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | depois', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'B md5 prosrc dados_atm_trafego | depois', md5(prosrc) from pg_proc where oid = 'public.dados_atm_trafego(text,date,date)'::regprocedure;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select name from storage.objects where bucket_id = ''trafego-miniaturas''' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain objetos do bucket (E) | depois', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- equipe não grava, não altera nem apaga no bucket (sem policy de INSERT/UPDATE/DELETE)
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
do $t$ declare n bigint; begin
  update storage.objects set metadata = metadata where bucket_id = 'trafego-miniaturas'; get diagnostics n = row_count;
  insert into pg_temp._z_out (passo, linha) values ('W equipe update no bucket (linhas)', n::text);
exception when others then insert into pg_temp._z_out (passo, linha) values ('W equipe update no bucket (linhas)', sqlstate); end $t$;
do $t$ declare n bigint; begin
  delete from storage.objects where bucket_id = 'trafego-miniaturas'; get diagnostics n = row_count;
  insert into pg_temp._z_out (passo, linha) values ('W equipe delete no bucket (linhas)', n::text);
exception when others then insert into pg_temp._z_out (passo, linha) values ('W equipe delete no bucket (linhas)', sqlstate); end $t$;
do $t$ begin
  insert into storage.objects (bucket_id, name) values ('trafego-miniaturas', 'meta/1/1.jpg');
  insert into pg_temp._z_out (passo, linha) values ('W equipe insert no bucket', 'GRAVOU');
exception when others then insert into pg_temp._z_out (passo, linha) values ('W equipe insert no bucket', sqlstate); end $t$;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.trafego_miniatura_pode_ver('meta/1/1.jpg'))::text;
  insert into pg_temp._z_out (passo, linha) values ('W anon chama trafego_miniatura_pode_ver', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('W anon chama trafego_miniatura_pode_ver', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'F acl e secdef dados_black_trafego', (select proacl::text || ' secdef=' || prosecdef from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select 'F acl e secdef trafego_miniatura_pode_ver', (select proacl::text || ' secdef=' || prosecdef from pg_proc where oid = 'public.trafego_miniatura_pode_ver(text)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select 'F policies citando o bucket', (select string_agg(policyname || ':' || cmd || ':' || roles::text, ', ') from pg_policies where schemaname = 'storage' and tablename = 'objects' and coalesce(qual, '') || coalesce(with_check, '') like '%trafego-miniaturas%');

-- ===== 3. REVERSÃO (texto de 20261013114630_reversao.sql) =====
-- Reversão de 20261013114630. Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_black_trafego ao corpo exato gravado por 20261013021259 (lido no banco em 13/10/2026 ~11:45 UTC, md5
-- fed8b153787d04164174610ec917e5e4): anúncios sem miniatura_caminho, campanhas sem conta_externa. Apaga a policy trafego_miniaturas_ler e a
-- função public.trafego_miniatura_pode_ver: o bucket trafego-miniaturas volta a ser só da service_role. Não toca em dado
-- nem nos arquivos do bucket. Efeito na tela: os cartões voltam à miniatura fictícia e "Abrir no Gerenciador" fica
-- desligado ("sem link na fonte").
-- Guarda: só roda se o corpo vivo for o gravado por 20261013114630 (md5 4ecabc5c…); se alguém mudou a função depois, recusa.
set local lock_timeout = '5s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '4ecabc5c67e683f8f5523c2fe739d00c' then
    raise exception 'reversão 20261013114630: corpo vivo de dados_black_trafego não é o gravado por 20261013114630 (md5 4ecabc5c…). Reler antes de reverter.';
  end if;
end
$g$;

drop policy trafego_miniaturas_ler on storage.objects;
drop function public.trafego_miniatura_pode_ver(text);

CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d dados.dashboards := dados.black_cadastro(p_chave);
  v_de date; v_ate date;
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    -- 20261013100000: campanhas do projeto do cadastro; a campanha sem projeto_id (o CPF01 hoje; ver o explain) entra
    -- quando um dos termos entre barras do nome é a sigla do projeto (BF26). O termo vem do cadastro, não fica fixo aqui.
    select c.id, c.nome, c.plataforma, c.status_plataforma, c.objetivo, c.projeto_id, ct.nome as conta,
           c.campanha_externa,   -- 20261013014209: id da campanha no Meta (recorte do grupo por campanha)
           e.etapa, e.subtipo, e.conflito
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao, j.conjunto_externa   -- 20261013014209
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id
           from mkt_trafego.anuncios a join cj on cj.id = a.conjunto_id),
  dc as (select x.* from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  da as (select x.* from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date))
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL',
    'coletado_em', greatest((select max(coletado_em) from dc), (select max(coletado_em) from da)),
    -- primeiro dia com quebra por anúncio, em qualquer data (antes dele só existe o número por campanha)
    'anuncio_desde', (select min(x.dia) from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'plataforma', c.plataforma, 'status', c.status_plataforma, 'objetivo', c.objetivo,
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito,
      'campanha_externa', c.campanha_externa
    ) order by c.nome) from c), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao, 'conjunto_externa', j.conjunto_externa
    ) order by j.nome, j.id) from cj j), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'conjunto_id', a.conjunto_id, 'nome', a.nome, 'status', a.status_plataforma,
      'anuncio_externa', a.anuncio_externa, 'video_id', a.video_id
    ) order by a.nome, a.id) from an a), '[]'::jsonb),
    'dias_campanha', coalesce((select jsonb_agg(jsonb_build_object(
      'campanha_id', x.campanha_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.campanha_id) from dc x), '[]'::jsonb),
    'dias_anuncio', coalesce((select jsonb_agg(jsonb_build_object(
      'anuncio_id', x.anuncio_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.anuncio_id) from da x), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

revoke all on function public.dados_black_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_black_trafego(text, date, date) to authenticated;

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> 'fed8b153787d04164174610ec917e5e4' then
    raise exception 'reversão 20261013114630: corpo de dados_black_trafego não voltou ao de antes';
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
              and coalesce(p.qual, '') || coalesce(p.with_check, '') like '%trafego-miniaturas%') then
    raise exception 'reversão 20261013114630: ainda há policy no bucket trafego-miniaturas';
  end if;
end
$c$;

-- ===== fim da reversão =====
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'reversao', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'reversao', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_atm_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM dados_atm_trafego (E) | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (E) | reversao', sqlstate); end $t$;
insert into pg_temp._z_vis (fase, nome) select 'reversao', o.name from storage.objects o where o.bucket_id = 'trafego-miniaturas';
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | reversao', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis (E) | reversao', sqlstate); end $t$;
do $t$ declare v text; begin v := (public.trafego_miniatura_pode_ver('meta/1/1.jpg'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B pode_ver caminho inexistente (E) | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego fora da equipe | reversao', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | reversao', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis fora da equipe | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B trafego anon | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B trafego anon | reversao', sqlstate); end $t$;
do $t$ declare v bigint; begin select count(*) into v from storage.objects where bucket_id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | reversao', 'ok:' || v);
exception when others then insert into pg_temp._z_out (passo, linha) values ('B objetos visiveis anon | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'B md5 prosrc dados_atm_trafego | reversao', md5(prosrc) from pg_proc where oid = 'public.dados_atm_trafego(text,date,date)'::regprocedure;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.e'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | reversao', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select name from storage.objects where bucket_id = ''trafego-miniaturas''' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain objetos do bucket (E) | reversao', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 4. COMPARAÇÕES =====
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' depois sem as chaves novas = antes', (pg_temp.z_sem_novas(d.r) = a.r)::text
  from pg_temp._z_r a join pg_temp._z_r d on d.periodo = a.periodo and d.fase = 'depois' where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' reversao = antes', (r.r = a.r)::text
  from pg_temp._z_r a join pg_temp._z_r r on r.periodo = a.periodo and r.fase = 'reversao' where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || d.periodo || ' chaves novas', jsonb_build_object(
   'campanhas', jsonb_array_length(d.r->'campanhas'),
   'conta_externa_bate_com_a_tabela', (select count(*) from jsonb_array_elements(d.r->'campanhas') e
        join mkt_trafego.campanhas c on c.id::text = e->>'id' join mkt_trafego.contas ct on ct.id = c.conta_id and ct.conta_externa = e->>'conta_externa'),
   'anuncios', jsonb_array_length(d.r->'anuncios'),
   'anuncios_com_miniatura', (select count(*) from jsonb_array_elements(d.r->'anuncios') e where nullif(e->>'miniatura_caminho', '') is not null),
   'miniatura_bate_com_a_tabela', (select count(*) from jsonb_array_elements(d.r->'anuncios') e
        join mkt_trafego.anuncios a on a.id::text = e->>'id' and a.miniatura_caminho is not distinct from e->>'miniatura_caminho'),
   'url_tags_no_retorno', position('url_tags' in d.r::text) > 0,
   'chaves_campanha', (select jsonb_agg(k order by k) from jsonb_object_keys(d.r->'campanhas'->0) k),
   'chaves_anuncio', (select jsonb_agg(k order by k) from jsonb_object_keys(d.r->'anuncios'->0) k))::text
  from pg_temp._z_r d where d.fase = 'depois';
insert into pg_temp._z_out (passo, linha)
select 'Z url_tags em algum retorno', bool_or(position('url_tags' in r::text) > 0)::text from pg_temp._z_r;
insert into pg_temp._z_out (passo, linha)
select 'Z storage: equipe depois enxerga exatamente as miniaturas da Black',
  jsonb_build_object(
    'esperado', (select count(*) from pg_temp._z_esperado),
    'visivel_depois', (select count(*) from pg_temp._z_vis where fase = 'depois'),
    'iguais', not exists (select name from pg_temp._z_esperado except select nome from pg_temp._z_vis where fase = 'depois')
          and not exists (select nome from pg_temp._z_vis where fase = 'depois' except select name from pg_temp._z_esperado),
    'objetos_no_bucket', (select count(*) from storage.objects where bucket_id = 'trafego-miniaturas'),
    'visivel_antes', (select count(*) from pg_temp._z_vis where fase = 'antes'),
    'visivel_reversao', (select count(*) from pg_temp._z_vis where fase = 'reversao'))::text;
insert into pg_temp._z_out (passo, linha)
select 'Z trava ' || split_part(a.passo, ' | ', 1), case when a.linha = d.linha and a.linha = r.linha then 'IGUAL ' || a.linha else 'DIFERENTE ' || a.linha || ' / ' || d.linha || ' / ' || r.linha end
  from pg_temp._z_out a join pg_temp._z_out d on d.passo = replace(a.passo, '| antes', '| depois') join pg_temp._z_out r on r.passo = replace(a.passo, '| antes', '| reversao')
 where a.passo like 'B %| antes';
insert into pg_temp._z_out (passo, linha)
select 'D ' || a.passo, a.linha from pg_temp._z_out a where a.passo like 'B %';
select passo, linha from pg_temp._z_out where passo not like 'B %' order by em;
rollback;
