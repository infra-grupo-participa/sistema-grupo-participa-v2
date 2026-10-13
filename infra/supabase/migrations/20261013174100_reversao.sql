-- Reversão de 20261013174100: volta dados_black_grupo e dados.grupo_foto_processar aos corpos de antes (md5 96b769d2… e
-- a0f65f0f…), tira a porta, a montagem, o registro de leituras, o grupo da consultoria (com as fotos e os participantes
-- dele), as colunas papel e numero e o hash da chave. Rodar com aplica_sql.py aplicar (tudo ou nada).
-- Depois: desligar o gatilho do Apps Script na planilha (Extensões > Apps Script > Acionadores) ou ele falha a cada hora.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> 'd01f477c89b3aa735fd90f393bfbb26f'
     or (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> '19441b5142b9eaa32cc61a1f242b0e53' then
    raise exception 'reversão 20261013174100: corpo vivo não é o desta migration. Reler.';
  end if;
end
$g$;

drop function if exists public.black_lista_disparo(text);
drop function if exists dados.black_lista_disparo_montar();
drop table if exists dados.black_lista_leituras;
drop table if exists dados.black_lista_config;

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

revoke all on function public.dados_black_grupo(text, date, date, boolean, jsonb) from public, anon, service_role;
grant execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) to authenticated;

CREATE OR REPLACE FUNCTION dados.grupo_foto_processar(p_foto_id bigint, p_csv text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261008200000: CSV "Posição;Grupo;Nome;Número;Saiu" (o nome pode ter ';': nome = campos do meio).
-- As linhas de dado vêm com ';' no fim e CRLF (o cabeçalho não): tira os dois antes de separar.
-- Devolve quantos números estão no grupo nesta foto. Aborta (sem mexer em nada) se o cabeçalho não bater.
declare
  f dados.grupo_fotos;
  v_agora timestamptz := now();
  v_cab text;
  v_linhas int;
  v_no int;
  v_sairam int;
begin
  select * into f from dados.grupo_fotos where id = p_foto_id;
  if not found then
    raise exception 'foto % não existe', p_foto_id;
  end if;
  if length(coalesce(p_csv, '')) > 5000000 then
    raise exception 'CSV do SendFlow acima de 5 MB (% caracteres)', length(p_csv);
  end if;
  v_cab := split_part(replace(replace(coalesce(p_csv, ''), chr(65279), ''), chr(13), ''), chr(10), 1);
  if v_cab <> 'Posição;Grupo;Nome;Número;Saiu' then
    -- sem o conteúdo da linha na mensagem (pode ser um participante): só tamanho e md5
    raise exception 'cabeçalho inesperado no CSV do SendFlow (% caracteres, md5 %)', length(v_cab), md5(v_cab);
  end if;

  create temp table if not exists pg_temp._foto (fone8 text, fone_key text, nome text, grupo text, no_grupo boolean) on commit drop;
  truncate pg_temp._foto;
  insert into pg_temp._foto (fone8, fone_key, nome, grupo, no_grupo)
  select right(controle.fone_key(a[array_length(a, 1) - 1]), 8),
         controle.fone_key(a[array_length(a, 1) - 1]),
         left(nullif(btrim(array_to_string(a[3:array_length(a, 1) - 2], ';')), ''), 200),
         left(nullif(btrim(a[2]), ''), 100),
         lower(btrim(a[array_length(a, 1)])) <> 'sim'
    from (select string_to_array(regexp_replace(l, ';\s*$', ''), ';') as a
            from unnest(string_to_array(replace(replace(p_csv, chr(65279), ''), chr(13), ''), chr(10))) with ordinality as t(l, n)
           where t.n > 1 and btrim(t.l) <> '') x
   where array_length(a, 1) >= 5 and controle.fone_key(a[array_length(a, 1) - 1]) is not null;
  get diagnostics v_linhas = row_count;

  with agg as (
    select fone8, max(fone_key) as fone_key,
           (array_agg(nome order by no_grupo desc) filter (where nome is not null))[1] as nome,
           left(string_agg(distinct grupo, ', ' order by grupo) filter (where no_grupo), 500) as grupos,
           bool_or(no_grupo) as no_grupo
      from pg_temp._foto group by fone8
  )
  insert into dados.grupo_participantes as p (grupo_id, fone8, fone_key, nome, grupos, no_grupo, visto_primeiro_em,
                                              visto_ultimo_em, saiu_em, primeira_foto_id, ultima_foto_id)
  select f.grupo_id, a.fone8, a.fone_key, a.nome, a.grupos, a.no_grupo, v_agora,
         case when a.no_grupo then v_agora end, case when not a.no_grupo then v_agora end, f.id, f.id
    from agg a
  on conflict (grupo_id, fone8) do update
     set fone_key        = coalesce(excluded.fone_key, p.fone_key),
         nome            = coalesce(excluded.nome, p.nome),
         grupos          = coalesce(excluded.grupos, p.grupos),
         no_grupo        = excluded.no_grupo,
         visto_ultimo_em = case when excluded.no_grupo then v_agora else p.visto_ultimo_em end,
         saiu_em         = case when excluded.no_grupo then null
                                when p.no_grupo then v_agora
                                else coalesce(p.saiu_em, v_agora) end,
         ultima_foto_id  = f.id;

  -- quem estava no grupo e sumiu da foto: saiu agora
  update dados.grupo_participantes p
     set no_grupo = false, saiu_em = v_agora, ultima_foto_id = f.id
   where p.grupo_id = f.grupo_id and p.no_grupo
     and not exists (select 1 from pg_temp._foto x where x.fone8 = p.fone8);

  select count(*) filter (where no_grupo), count(*) filter (where not no_grupo) into v_no, v_sairam
    from dados.grupo_participantes where grupo_id = f.grupo_id;
  update dados.grupo_fotos
     set etapa = 'feito', concluido_em = v_agora, linhas = v_linhas, numeros_no_grupo = v_no, numeros_sairam = v_sairam,
         erro = null
   where id = f.id;
  return v_no;
end
$function$;

revoke all on function dados.grupo_foto_processar(bigint, text) from public, anon, authenticated, service_role;

delete from dados.grupo_participantes where grupo_id in (select id from dados.dashboard_grupos where sendflow_release_id = '55zPFLZLHRg7JbXtkPeJ');
delete from dados.grupo_fotos where grupo_id in (select id from dados.dashboard_grupos where sendflow_release_id = '55zPFLZLHRg7JbXtkPeJ');
delete from dados.dashboard_grupos where sendflow_release_id = '55zPFLZLHRg7JbXtkPeJ';
alter table dados.dashboard_grupos drop column if exists papel;
alter table dados.grupo_participantes drop column if exists numero;

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '96b769d2f4a22b557a3a0a4ed97ac470'
     or (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> 'a0f65f0f4bd1aa7c8da22d4e163ea87f' then
    raise exception 'reversão 20261013174100: corpo não voltou ao de antes';
  end if;
end
$c$;
