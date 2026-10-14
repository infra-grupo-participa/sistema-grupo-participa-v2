begin;
create temp table _z_out (em serial, passo text, linha text);
do $a$ declare v text; begin select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id=m.perfil_id where p.status='ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1; perform set_config('request.jwt.claims', json_build_object('sub',v,'role','authenticated')::text, true); end $a$;
create temp table _z_a as select (public.dados_black_grupo('black-friday-2026-10', null, null, false, null) - 'atualizado') as s, (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb) - 'atualizado') as r;
insert into pg_temp._z_out(passo, linha) select '1 antes: total / leads unicos / leads em algum grupo', (s ->> 'unicos_grupos_total') || ' / ' || (s -> 'leads' ->> 'unicos') || ' / ' || (s ->> 'leads_em_algum_grupo') from pg_temp._z_a;
-- 20261014220000: dados_black_grupo devolve 'ingresso_geral' = números únicos nos grupos da campanha ÷ leads únicos
-- (regra do Victor, 14/10, sem cruzar telefone de membro com o de lead). Os campos que já existiam não mudam.
-- O ATM (dados_atm_resumo.grupo_pct = entradas no grupo ÷ leads) e as Ações da Black (mesmas RPCs do ATM) já seguem a regra.
-- Reversão: 20261014220000_reversao.sql. Ver 20261014220000.explain.md.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure)
      is distinct from '176807b27eb545b159d812308c746019' then
    raise exception '20261014220000: corpo vivo de dados_black_grupo mudou; revisar';
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
       and g.papel = 'dashboard'   -- 20261013172751: grupo só de lista de disparo (ex.: consultoria) fica fora dos cards
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
  ), pent as (   -- 20261014190100: lead (pessoa) × grupo em que entrou, com a classe da pessoa (sempre, com ou sem recorte)
    select pe.pessoa_chave, pe.classe, ent.grupo_id
      from pessoa pe join ent on ent.fone8 = pe.fone8
     where pe.fone8 is not null
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
                and exists (select 1 from ent where ent.grupo_id = grp.id and ent.fone8 = pe.fone8)) end,
        -- 20261014190100 (Black V5): leads (pessoas do recorte) que entraram neste grupo, a classe deles e o denominador do
        -- segmento (advogado = advogado + estudante de direito; contador; outros). Sem profissão fica fora dos denominadores.
        'leads_no_grupo', (select count(distinct x.pessoa_chave) from pent x where x.grupo_id = grp.id),
        'leads_no_grupo_por_classe', (select jsonb_build_object(
            'advogado', count(distinct x.pessoa_chave) filter (where x.classe = 'advogado'),
            'estudante_direito', count(distinct x.pessoa_chave) filter (where x.classe = 'estudante_direito'),
            'contador', count(distinct x.pessoa_chave) filter (where x.classe = 'contador'),
            'outros', count(distinct x.pessoa_chave) filter (where x.classe = 'outros'),
            'sem_profissao', count(distinct x.pessoa_chave) filter (where x.classe is null))
          from pent x where x.grupo_id = grp.id),
        'leads_do_segmento', case grp.segmento
            when 'advogado' then (select count(*) from pessoa where classe in ('advogado', 'estudante_direito'))
            when 'contador' then (select count(*) from pessoa where classe = 'contador')
            when 'outros' then (select count(*) from pessoa where classe = 'outros') end
      ) order by grp.segmento, grp.sendflow_campanha) from grp), '[]'::jsonb),
    'unicos_grupos_mql', (select count(distinct ent.fone8) from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador')),
    'unicos_grupos_total', (select count(distinct ent.fone8) from ent),
    -- 20261014220000 (regra do Victor, 14/10): taxa GERAL de ingresso = números únicos que entraram nos grupos da campanha
    -- (sem os telefones de teste/equipe marcados) ÷ leads únicos, SEM exigir que o telefone do membro cruze com o do lead
    -- (a pessoa erra dígito ou entra com outro número). Só sem recorte: recorte por pessoa (MQL, canal) segue cruzado.
    'ingresso_geral', case when v_rec is null then (
        select jsonb_build_object('numeros_unicos_no_grupo', n.g, 'leads_unicos', n.l,
                                  'pct', case when n.l > 0 then round(n.g * 100.0 / n.l, 1) end)
          from (select (select count(distinct ent.fone8) from ent) as g, (select count(*) from pessoa) as l) n) end,
    -- 20261014190100: leads em algum grupo e em mais de um (a soma por grupo passa do total por esses)
    'leads_em_algum_grupo', (select count(distinct x.pessoa_chave) from pent x),
    'leads_em_mais_de_um_grupo', (select count(*) from (select x.pessoa_chave from pent x group by 1 having count(distinct x.grupo_id) > 1) z),
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

insert into pg_temp._z_out(passo, linha) select '2 ingresso_geral (sem recorte)', (public.dados_black_grupo('black-friday-2026-10', null, null, false, null) -> 'ingresso_geral')::text;
insert into pg_temp._z_out(passo, linha) select '2b campos antigos iguais (sem recorte / com recorte)', ((public.dados_black_grupo('black-friday-2026-10', null, null, false, null) - 'atualizado' - 'ingresso_geral') = s)::text || ' / ' || ((public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb) - 'atualizado' - 'ingresso_geral') = r)::text from pg_temp._z_a;
insert into pg_temp._z_out(passo, linha) select '2c com recorte: ingresso_geral', coalesce((public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}'::jsonb) -> 'ingresso_geral')::text, 'nulo');
insert into pg_temp._z_out(passo, linha) select '2d período 14/10', (public.dados_black_grupo('black-friday-2026-10', date '2026-10-14', date '2026-10-14', false, null) -> 'ingresso_geral')::text;
insert into pg_temp._z_out(passo, linha) select '2e md5 novo', md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure;
-- Reversão da 20261014220000: volta dados_black_grupo ao corpo 176807b2 (sem 'ingresso_geral').
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure)
      is distinct from 'ba8aa00327f698734271a682b6c02cf9' then
    raise exception 'reversão 20261014220000: corpo vivo não é o da 220000; revisar';
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
       and g.papel = 'dashboard'   -- 20261013172751: grupo só de lista de disparo (ex.: consultoria) fica fora dos cards
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
  ), pent as (   -- 20261014190100: lead (pessoa) × grupo em que entrou, com a classe da pessoa (sempre, com ou sem recorte)
    select pe.pessoa_chave, pe.classe, ent.grupo_id
      from pessoa pe join ent on ent.fone8 = pe.fone8
     where pe.fone8 is not null
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
                and exists (select 1 from ent where ent.grupo_id = grp.id and ent.fone8 = pe.fone8)) end,
        -- 20261014190100 (Black V5): leads (pessoas do recorte) que entraram neste grupo, a classe deles e o denominador do
        -- segmento (advogado = advogado + estudante de direito; contador; outros). Sem profissão fica fora dos denominadores.
        'leads_no_grupo', (select count(distinct x.pessoa_chave) from pent x where x.grupo_id = grp.id),
        'leads_no_grupo_por_classe', (select jsonb_build_object(
            'advogado', count(distinct x.pessoa_chave) filter (where x.classe = 'advogado'),
            'estudante_direito', count(distinct x.pessoa_chave) filter (where x.classe = 'estudante_direito'),
            'contador', count(distinct x.pessoa_chave) filter (where x.classe = 'contador'),
            'outros', count(distinct x.pessoa_chave) filter (where x.classe = 'outros'),
            'sem_profissao', count(distinct x.pessoa_chave) filter (where x.classe is null))
          from pent x where x.grupo_id = grp.id),
        'leads_do_segmento', case grp.segmento
            when 'advogado' then (select count(*) from pessoa where classe in ('advogado', 'estudante_direito'))
            when 'contador' then (select count(*) from pessoa where classe = 'contador')
            when 'outros' then (select count(*) from pessoa where classe = 'outros') end
      ) order by grp.segmento, grp.sendflow_campanha) from grp), '[]'::jsonb),
    'unicos_grupos_mql', (select count(distinct ent.fone8) from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador')),
    'unicos_grupos_total', (select count(distinct ent.fone8) from ent),
    -- 20261014190100: leads em algum grupo e em mais de um (a soma por grupo passa do total por esses)
    'leads_em_algum_grupo', (select count(distinct x.pessoa_chave) from pent x),
    'leads_em_mais_de_um_grupo', (select count(*) from (select x.pessoa_chave from pent x group by 1 having count(distinct x.grupo_id) > 1) z),
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


insert into pg_temp._z_out(passo, linha) select '3 depois da reversão: md5 / sem ingresso_geral', md5(prosrc) || ' / ' || (not (public.dados_black_grupo('black-friday-2026-10', null, null, false, null) ? 'ingresso_geral'))::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '4 ATM hoje: entradas / leads / grupo_pct', (select r.grupo_entradas || ' / ' || r.leads || ' / ' || r.grupo_pct from public.dados_atm_resumo('atm-elaine-1-2026-10', null, null) r);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
