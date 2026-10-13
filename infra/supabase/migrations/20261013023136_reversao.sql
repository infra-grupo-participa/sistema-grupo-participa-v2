-- Reversão de 20261013023136. Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_black_grupo ao corpo exato gravado por 20261012234606 (lido no banco em 13/10/2026 ~02:30 UTC, md5
-- ab8582e6603773f480b4b7d0ef14fb27): o grupo volta a excluir só a marcação de teste do tipo fone. Não toca em dado.
-- Efeito na tela: o telefone cujos envios são todos teste (marcados por e-mail) volta a contar nos cards do grupo.
set local lock_timeout = '5s';

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
    raise exception 'reversão 20261013023136: corpo de dados_black_grupo não voltou ao de antes';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) then
    raise exception 'reversão 20261013023136: permissão de dados_black_grupo errada';
  end if;
end
$c$;
