-- Ensaio de 20261013024435 (transação desfeita, REPEATABLE READ). dados_black_grupo: fora do grupo o telefone só de teste.
-- Prova: (1) depois, em cada grupo, sai exatamente o número de telefones do grupo cujos envios da Black são todos teste
-- (contado direto da origem, sem a RPC), e o telefone misto continua contando; (2) leads, cruzados (com recorte) e o
-- resultado com p_incluir_teste = true são idênticos ao de antes; (3) as travas (P0002, 42501) dão a mesma resposta;
-- (4) a reversão volta o corpo ao md5 de antes e o resultado ao de antes.
-- Só contagens, sqlstate e md5: nenhum dado pessoal sai do ensaio. Gerado por um script a partir da migration e da
-- reversão (o texto delas entra aqui sem mudança).
-- Aplicada em 13/10/2026 02:44:35 UTC: no banco de agora a guarda da migration (md5 ab8582e6…) recusa. Para reensaiar,
-- cole o texto de 20261013024435_reversao.sql logo depois do begin abaixo (volta o corpo de antes dentro desta transação).
-- M (master) é buscado no banco; o uid de "fora da equipe" é fictício de propósito.
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_r (fase text, caso text, r jsonb) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_r to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
-- M = um master ativo da equipe, buscado no banco (sem UUID gravado no arquivo)
select set_config('ensaio.m', coalesce((select m.perfil_id::text from acesso.master m join public.perfis p on p.id = m.perfil_id
  where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1), ''), true);
do $q$ begin
  if current_setting('ensaio.m') = '' then raise exception 'ensaio: nenhum master ativo da equipe no banco'; end if;
end $q$;
-- contas por grupo direto da origem, todo o período da Black (mesmas janelas e união webhook + foto da RPC)
create temp table _z_orig on commit drop as
with d as (select * from dados.dashboards where chave = 'black-friday-2026-10'),
per as (select (d.periodo_inicio::timestamp at time zone 'America/Sao_Paulo') de,
               (((now() at time zone 'America/Sao_Paulo')::date + 1)::timestamp at time zone 'America/Sao_Paulo') ate from d),
grp as (select g.id, g.sendflow_campanha,
               case when g.sendflow_campanha ~ ' - Advogados$' then 'advogado' when g.sendflow_campanha ~ ' - Contadores$' then 'contador'
                    when g.sendflow_campanha ~ ' - Outros$' then 'outros' end seg
          from dados.dashboard_grupos g where g.chave = 'black-friday-2026-10'),
wt as (select distinct grp.id gid, right(j.fone_key, 8) f8 from crm.evento_jornada j join grp on grp.sendflow_campanha = j.tag
        where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null),
u as (select distinct grp.id gid, right(j.fone_key, 8) f8 from crm.evento_jornada j join grp on grp.sendflow_campanha = j.tag, per
       where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null and j.ocorreu_em >= per.de and j.ocorreu_em < per.ate
      union
      select p.grupo_id, p.fone8 from dados.grupo_participantes p join grp on grp.id = p.grupo_id, per
       where p.visto_primeiro_em >= per.de and p.visto_primeiro_em < per.ate
         and not exists (select 1 from wt where wt.gid = p.grupo_id and wt.f8 = p.fone8)),
cls as (select l.fone8 f8, bool_and(l.teste) todos, bool_or(l.teste) algum from dados.black_leads l where l.fone8 is not null group by l.fone8),
mf as (select m.valor f8 from dados.marcacoes_teste m where m.chave = 'black-friday-2026-10' and m.desmarcado_em is null and m.tipo = 'fone')
select grp.seg,
       count(distinct u.f8) filter (where u.f8 not in (select f8 from mf)) uniao_sem_marcacao_fone,
       count(distinct u.f8) filter (where u.f8 in (select f8 from cls where todos) and u.f8 not in (select f8 from mf)) so_teste,
       count(distinct u.f8) filter (where u.f8 in (select f8 from cls where algum and not todos) and u.f8 not in (select f8 from mf)) misto
  from grp left join u on u.gid = grp.id group by grp.seg;
-- números de um retorno
create function pg_temp.z_num(r jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object(
    'advogado', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'advogado'),
    'contador', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'contador'),
    'outros', (select (g->>'unicos')::int from jsonb_array_elements(r->'grupos') g where g->>'segmento' = 'outros'),
    'mql_grupo', (r->>'unicos_grupos_mql')::int, 'total_grupo', (r->>'unicos_grupos_total')::int,
    'cruzados', (select jsonb_agg(g->'unicos_cruzados' order by g->>'segmento') from jsonb_array_elements(r->'grupos') g),
    'cruzados_mql', r->'unicos_cruzados_mql', 'leads_mql', r#>'{leads,mql}', 'leads_unicos', r#>'{leads,unicos}')
$f$;
-- ===== 1. ANTES =====
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'antes', 'captacao', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb);
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | antes', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo | antes', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"porta","valor":"consultoria"}''::jsonb)' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo recorte | antes', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 2. MIGRATION (texto de 20261013024435_dados_black_grupo_teste_por_email.sql) =====
-- 20261013024435: dados_black_grupo tira do grupo o telefone cujos envios da Black são todos teste.
-- Auditoria de 13/10/2026 (só SELECT): a RPC só excluía do grupo a marcação de teste do tipo fone
-- (dados.marcacoes_teste.tipo = 'fone'), mas as marcações da Black são por e-mail. Resultado: telefone de teste
-- contado nos grupos (Advogados/Contadores/Outros 90/33/43 em vez de 87/30/40; únicos nos grupos de MQL 112 em vez de 109).
-- Muda só o CTE tst (telefones fora do grupo): além das marcações por fone, entra o telefone (8 últimos dígitos) cujos
-- envios em dados.black_leads são TODOS teste (dados.teste_ativo, a mesma regra que tira o envio dos leads). Olha todos os
-- envios da Black, não só os do período escolhido.
-- Telefone MISTO (um envio teste e outro não, ex.: mesmo telefone com dois e-mails) CONTINUA contando: é decisão do Victor
-- (docs/dashboard-black/README.md, "A corrigir"). Com p_incluir_teste = true nada muda (o filtro não se aplica).
-- Leads, recorte, cruzados, assinatura, dono, ACL, security definer e search_path iguais.
-- Pré-requisito: corpo vivo igual ao gravado por 20261012234606 (md5 conferido abaixo).
-- Ensaio: 20261013024435_ensaio.sql. Reversão: 20261013024435_reversao.sql. Detalhe: 20261013024435.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regclass('dados.black_leads') is null or to_regprocedure('dados.teste_ativo(text,text,text)') is null then
    raise exception '20261013024435: dados.black_leads ou dados.teste_ativo não existe.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> 'ab8582e6603773f480b4b7d0ef14fb27' then
    raise exception '20261013024435: corpo vivo de dados_black_grupo mudou. Reler.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_grupo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false, p_recorte jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d dados.dashboards := dados.black_evento(p_chave);
  v_rec jsonb := dados.black_recorte_valido(p_recorte);
  v_de timestamptz := (coalesce(p_de, d.periodo_inicio)::timestamp at time zone 'America/Sao_Paulo');
  v_ate timestamptz := ((coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp at time zone 'America/Sao_Paulo');
  r jsonb;
begin
  with grp as (
    select g.id, g.sendflow_campanha, g.sendflow_release_id,
           case when g.sendflow_campanha ~ ' - Advogados$' then 'advogado'
                when g.sendflow_campanha ~ ' - Contadores$' then 'contador'
                when g.sendflow_campanha ~ ' - Outros$' then 'outros' end as segmento
      from dados.dashboard_grupos g
     where g.chave = d.chave
  ), bl as materialized (   -- 20261013023136: telefone dos envios da Black, lido uma vez só
    select l.fone8, l.email, l.whatsapp from dados.black_leads l where l.fone8 is not null
  ), tst as (
    -- 20261013023136: fora do grupo, (1) o telefone marcado como teste e (2) o telefone cujos envios da Black são TODOS
    -- teste (dados.teste_ativo: marcação por e-mail ou por fone), olhando todos os envios da Black, não só os do período.
    -- Telefone misto (um envio teste e outro não) continua contando até decisão do Victor (docs/dashboard-black/README.md).
    -- teste_ativo só roda nos envios dos telefones candidatos (os que têm algum envio de e-mail marcado), não na base toda.
    select m.valor as fone8 from dados.marcacoes_teste m
     where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone'
    union
    select bl.fone8 from bl
     where bl.fone8 in (select c.fone8 from bl c
                          join dados.marcacoes_teste m on m.chave = d.chave and m.desmarcado_em is null
                                                      and m.tipo = 'email' and m.valor = c.email)
     group by bl.fone8
    having bool_and(dados.teste_ativo(d.chave, bl.email, bl.whatsapp))
  ), wh_todos as (   -- toda entrada que o webhook já viu (para saber quem a foto precisa cobrir)
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
  ), wh as (
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
       and j.ocorreu_em >= v_de and j.ocorreu_em < v_ate
  ), fo as (   -- foto: só quem o webhook nunca viu entrar naquele grupo
    select distinct p.grupo_id, p.fone8
      from dados.grupo_participantes p
      join grp on grp.id = p.grupo_id
     where p.visto_primeiro_em >= v_de and p.visto_primeiro_em < v_ate
       and not exists (select 1 from wh_todos w where w.grupo_id = p.grupo_id and w.fone8 = p.fone8)
  ), ent as (
    select x.grupo_id, x.fone8, bool_or(x.via = 'webhook') as via_webhook
      from (select grupo_id, fone8, 'webhook' as via from wh union all select grupo_id, fone8, 'foto' from fo) x
     where p_incluir_teste or x.fone8 not in (select fone8 from tst)
     group by x.grupo_id, x.fone8
  ), ld as (
    select l.*
      from dados.black_leads l
     where l.criado_em >= v_de and l.criado_em < v_ate
       and (p_incluir_teste or not dados.teste_ativo(d.chave, l.email, l.whatsapp))
       and dados.black_no_recorte(v_rec, l.porta, l.isca, l.campanha_id, l.conjunto_id, l.anuncio_id)
  ), pessoa as (   -- classe da pessoa = a do envio mais recente que tem profissão
    select ld.pessoa_chave,
           (array_agg(ld.profissao_classe order by ld.criado_em desc, ld.lead_id desc) filter (where ld.profissao_classe is not null))[1] as classe,
           max(ld.fone8) as fone8
      from ld group by ld.pessoa_chave
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('de', (v_de at time zone 'America/Sao_Paulo')::date, 'ate', ((v_ate at time zone 'America/Sao_Paulo')::date - 1)),
    'recorte', v_rec,
    'incluir_teste', p_incluir_teste,
    'grupos', coalesce((select jsonb_agg(jsonb_build_object(
        'campanha', grp.sendflow_campanha, 'segmento', grp.segmento,
        'unicos', (select count(*) from ent where ent.grupo_id = grp.id),
        'unicos_webhook', (select count(*) from ent where ent.grupo_id = grp.id and ent.via_webhook),
        'unicos_so_foto', (select count(*) from ent where ent.grupo_id = grp.id and not ent.via_webhook),
        'unicos_cruzados', case when v_rec is null then null else
            (select count(*) from pessoa pe where pe.fone8 is not null
                and exists (select 1 from ent where ent.grupo_id = grp.id and ent.fone8 = pe.fone8)) end
      ) order by grp.segmento, grp.sendflow_campanha) from grp), '[]'::jsonb),
    'unicos_grupos_mql', (select count(distinct ent.fone8) from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador')),
    'unicos_grupos_total', (select count(distinct ent.fone8) from ent),
    'unicos_cruzados_mql', case when v_rec is null then null else
        (select count(*) from pessoa pe where pe.fone8 is not null and exists
           (select 1 from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador') and ent.fone8 = pe.fone8)) end,
    'leads', jsonb_build_object(
        'unicos', (select count(*) from pessoa),
        'mql', (select count(*) from pessoa where classe in ('advogado', 'contador', 'estudante_direito')),
        'advogado', (select count(*) from pessoa where classe = 'advogado'),
        'estudante_direito', (select count(*) from pessoa where classe = 'estudante_direito'),
        'advogado_mais_estudante', (select count(*) from pessoa where classe in ('advogado', 'estudante_direito')),
        'contador', (select count(*) from pessoa where classe = 'contador'),
        'outros', (select count(*) from pessoa where classe = 'outros'),
        'sem_profissao', (select count(*) from pessoa where classe is null),
        'nao_mql', (select count(*) from pessoa where classe = 'outros' or classe is null)),
    'atualizado', jsonb_build_object(
        'ultimo_evento_webhook', (select max(j.ocorreu_em) from crm.evento_jornada j join grp on grp.sendflow_campanha = j.tag where j.fonte = 'sendflow'),
        'ultima_foto', (select max(p.visto_ultimo_em) from dados.grupo_participantes p join grp on grp.id = p.grupo_id))
  ) into r;
  return r;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_black_grupo(text, date, date, boolean, jsonb) from public, anon, service_role;
grant execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) to authenticated;

do $c$
begin
  if (select proacl::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure)
     or (select pg_get_userbyid(proowner) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> 'postgres'
     or (select proconfig::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '{"search_path=\"\""}' then
    raise exception '20261013024435: permissão, dono ou search_path de dados_black_grupo errado';
  end if;
end
$c$;

-- ===== fim da migration =====
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'depois', 'captacao', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb);
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | depois', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo | depois', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"porta","valor":"consultoria"}''::jsonb)' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo recorte | depois', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 3. REVERSÃO (texto de 20261013024435_reversao.sql) =====
-- Reversão de 20261013024435. Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_black_grupo ao corpo exato gravado por 20261012234606 (lido no banco em 13/10/2026 ~02:30 UTC, md5
-- ab8582e6603773f480b4b7d0ef14fb27): o grupo volta a excluir só a marcação de teste do tipo fone. Não toca em dado.
-- Efeito na tela: o telefone cujos envios são todos teste (marcados por e-mail) volta a contar nos cards do grupo.
-- Guarda (pedido do pentester): só roda se o corpo vivo for o gravado por 20261013024435 (md5 96b769d2…); se alguém
-- mudou a função depois, a reversão recusa em vez de apagar a mudança de outra pessoa.
set local lock_timeout = '5s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '96b769d2f4a22b557a3a0a4ed97ac470' then
    raise exception 'reversão 20261013024435: corpo vivo de dados_black_grupo não é o gravado por 20261013024435 (md5 96b769d2…). Reler antes de reverter.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_grupo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false, p_recorte jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d dados.dashboards := dados.black_evento(p_chave);
  v_rec jsonb := dados.black_recorte_valido(p_recorte);
  v_de timestamptz := (coalesce(p_de, d.periodo_inicio)::timestamp at time zone 'America/Sao_Paulo');
  v_ate timestamptz := ((coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp at time zone 'America/Sao_Paulo');
  r jsonb;
begin
  with grp as (
    select g.id, g.sendflow_campanha, g.sendflow_release_id,
           case when g.sendflow_campanha ~ ' - Advogados$' then 'advogado'
                when g.sendflow_campanha ~ ' - Contadores$' then 'contador'
                when g.sendflow_campanha ~ ' - Outros$' then 'outros' end as segmento
      from dados.dashboard_grupos g
     where g.chave = d.chave
  ), tst as (
    select m.valor as fone8 from dados.marcacoes_teste m
     where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone'
  ), wh_todos as (   -- toda entrada que o webhook já viu (para saber quem a foto precisa cobrir)
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
  ), wh as (
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
       and j.ocorreu_em >= v_de and j.ocorreu_em < v_ate
  ), fo as (   -- foto: só quem o webhook nunca viu entrar naquele grupo
    select distinct p.grupo_id, p.fone8
      from dados.grupo_participantes p
      join grp on grp.id = p.grupo_id
     where p.visto_primeiro_em >= v_de and p.visto_primeiro_em < v_ate
       and not exists (select 1 from wh_todos w where w.grupo_id = p.grupo_id and w.fone8 = p.fone8)
  ), ent as (
    select x.grupo_id, x.fone8, bool_or(x.via = 'webhook') as via_webhook
      from (select grupo_id, fone8, 'webhook' as via from wh union all select grupo_id, fone8, 'foto' from fo) x
     where p_incluir_teste or x.fone8 not in (select fone8 from tst)
     group by x.grupo_id, x.fone8
  ), ld as (
    select l.*
      from dados.black_leads l
     where l.criado_em >= v_de and l.criado_em < v_ate
       and (p_incluir_teste or not dados.teste_ativo(d.chave, l.email, l.whatsapp))
       and dados.black_no_recorte(v_rec, l.porta, l.isca, l.campanha_id, l.conjunto_id, l.anuncio_id)
  ), pessoa as (   -- classe da pessoa = a do envio mais recente que tem profissão
    select ld.pessoa_chave,
           (array_agg(ld.profissao_classe order by ld.criado_em desc, ld.lead_id desc) filter (where ld.profissao_classe is not null))[1] as classe,
           max(ld.fone8) as fone8
      from ld group by ld.pessoa_chave
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('de', (v_de at time zone 'America/Sao_Paulo')::date, 'ate', ((v_ate at time zone 'America/Sao_Paulo')::date - 1)),
    'recorte', v_rec,
    'incluir_teste', p_incluir_teste,
    'grupos', coalesce((select jsonb_agg(jsonb_build_object(
        'campanha', grp.sendflow_campanha, 'segmento', grp.segmento,
        'unicos', (select count(*) from ent where ent.grupo_id = grp.id),
        'unicos_webhook', (select count(*) from ent where ent.grupo_id = grp.id and ent.via_webhook),
        'unicos_so_foto', (select count(*) from ent where ent.grupo_id = grp.id and not ent.via_webhook),
        'unicos_cruzados', case when v_rec is null then null else
            (select count(*) from pessoa pe where pe.fone8 is not null
                and exists (select 1 from ent where ent.grupo_id = grp.id and ent.fone8 = pe.fone8)) end
      ) order by grp.segmento, grp.sendflow_campanha) from grp), '[]'::jsonb),
    'unicos_grupos_mql', (select count(distinct ent.fone8) from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador')),
    'unicos_grupos_total', (select count(distinct ent.fone8) from ent),
    'unicos_cruzados_mql', case when v_rec is null then null else
        (select count(*) from pessoa pe where pe.fone8 is not null and exists
           (select 1 from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador') and ent.fone8 = pe.fone8)) end,
    'leads', jsonb_build_object(
        'unicos', (select count(*) from pessoa),
        'mql', (select count(*) from pessoa where classe in ('advogado', 'contador', 'estudante_direito')),
        'advogado', (select count(*) from pessoa where classe = 'advogado'),
        'estudante_direito', (select count(*) from pessoa where classe = 'estudante_direito'),
        'advogado_mais_estudante', (select count(*) from pessoa where classe in ('advogado', 'estudante_direito')),
        'contador', (select count(*) from pessoa where classe = 'contador'),
        'outros', (select count(*) from pessoa where classe = 'outros'),
        'sem_profissao', (select count(*) from pessoa where classe is null),
        'nao_mql', (select count(*) from pessoa where classe = 'outros' or classe is null)),
    'atualizado', jsonb_build_object(
        'ultimo_evento_webhook', (select max(j.ocorreu_em) from crm.evento_jornada j join grp on grp.sendflow_campanha = j.tag where j.fonte = 'sendflow'),
        'ultima_foto', (select max(p.visto_ultimo_em) from dados.grupo_participantes p join grp on grp.id = p.grupo_id))
  ) into r;
  return r;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_black_grupo(text, date, date, boolean, jsonb) from public, anon, service_role;
grant execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) to authenticated;

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> 'ab8582e6603773f480b4b7d0ef14fb27' then
    raise exception 'reversão 20261013024435: corpo de dados_black_grupo não voltou ao de antes';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) then
    raise exception 'reversão 20261013024435: permissão de dados_black_grupo errada';
  end if;
end
$c$;

-- ===== fim da reversão =====
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('ensaio.m'), 'role', 'authenticated', 'email', 'ensaio@ensaio')::text, true);
set local role authenticated;
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'todo', public.dados_black_grupo('black-friday-2026-10', null, null, false, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', '10a12', public.dados_black_grupo('black-friday-2026-10', '2026-10-10', '2026-10-12', false, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'todo_com_teste', public.dados_black_grupo('black-friday-2026-10', null, null, true, null);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'consultoria', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"consultoria"}'::jsonb);
insert into pg_temp._z_r (fase, caso, r) select 'reversao', 'captacao', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb);
do $t$ declare v text; begin v := (public.dados_black_grupo('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM no grupo da Black (M) | reversao', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo | reversao', l); end if;
  end loop;
  for l in execute 'explain (analyze, timing) select public.dados_black_grupo(''black-friday-2026-10'', null, null, false, ''{"tipo":"porta","valor":"consultoria"}''::jsonb)' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain grupo recorte | reversao', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_grupo('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 4. COMPARAÇÕES =====
insert into pg_temp._z_out (passo, linha)
select 'N ' || a.caso || ' | ' || a.fase, pg_temp.z_num(a.r)::text from pg_temp._z_r a
 order by a.caso, case a.fase when 'antes' then 1 when 'depois' then 2 else 3 end;
insert into pg_temp._z_out (passo, linha)
select 'O origem ' || o.seg, jsonb_build_object('uniao', o.uniao_sem_marcacao_fone, 'so_teste', o.so_teste, 'misto', o.misto)::text
  from pg_temp._z_orig o order by o.seg;
-- (1) o que sai em cada grupo = telefones só de teste da origem; antes = união da origem; o misto segue dentro
insert into pg_temp._z_out (passo, linha)
select 'Z todo ' || o.seg || ' antes = origem e depois = origem - so_teste',
       ((pg_temp.z_num(a.r)->>o.seg)::int = o.uniao_sem_marcacao_fone
        and (pg_temp.z_num(d.r)->>o.seg)::int = o.uniao_sem_marcacao_fone - o.so_teste)::text
  from pg_temp._z_orig o, pg_temp._z_r a, pg_temp._z_r d
 where a.fase = 'antes' and a.caso = 'todo' and d.fase = 'depois' and d.caso = 'todo' order by o.seg;
-- (2) o que não pode mudar
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.caso || ' leads depois = antes', (a.r->'leads' = d.r->'leads')::text
  from pg_temp._z_r a join pg_temp._z_r d on d.caso = a.caso and d.fase = 'depois' where a.fase = 'antes' order by a.caso;
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.caso || ' cruzados depois = antes',
       ((pg_temp.z_num(a.r)->'cruzados') = (pg_temp.z_num(d.r)->'cruzados') and a.r->'unicos_cruzados_mql' = d.r->'unicos_cruzados_mql')::text
  from pg_temp._z_r a join pg_temp._z_r d on d.caso = a.caso and d.fase = 'depois' where a.fase = 'antes' and a.caso in ('consultoria', 'captacao') order by a.caso;
insert into pg_temp._z_out (passo, linha)
select 'Z todo_com_teste depois = antes', (a.r = d.r)::text
  from pg_temp._z_r a join pg_temp._z_r d on d.caso = a.caso and d.fase = 'depois' where a.fase = 'antes' and a.caso = 'todo_com_teste';
-- (4) reversão
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.caso || ' reversao = antes', (r.r = a.r)::text
  from pg_temp._z_r a join pg_temp._z_r r on r.caso = a.caso and r.fase = 'reversao' where a.fase = 'antes' order by a.caso;
-- (3) travas
insert into pg_temp._z_out (passo, linha)
select 'Z trava ' || split_part(a.passo, ' | ', 1), case when a.linha = d.linha and a.linha = r.linha then 'IGUAL ' || a.linha else 'DIFERENTE ' || a.linha || ' / ' || d.linha || ' / ' || r.linha end
  from pg_temp._z_out a join pg_temp._z_out d on d.passo = replace(a.passo, '| antes', '| depois') join pg_temp._z_out r on r.passo = replace(a.passo, '| antes', '| reversao')
 where a.passo like 'B %| antes';
select passo, linha from pg_temp._z_out where passo not like 'B %' order by em;
rollback;
