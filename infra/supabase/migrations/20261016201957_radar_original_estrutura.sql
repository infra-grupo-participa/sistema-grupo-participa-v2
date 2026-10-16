-- Radar (sistema original) no banco do Grupo Participa: a ESTRUTURA (16/10/2026).
-- Gerado por SistemaWEB/sistemas/radar/migracao-participa/gera_estrutura.py a partir do banco vivo do Radar
-- (Supabase pessoal txqzqmagktrcemyavpmy), pelo gestor Luis Fernando, com o aval do Victor Hugo.
--
-- O QUE FAZ: so cria coisa nova e nao toca em nada que ja existe.
--   schemas radar (57 tabelas do Radar) e radar_crm (o crm do Radar com outro nome: o Grupo ja tem o crm do Comercial),
--   189 funcoes neles e 22 funcoes public.radar_* (a crm_receber do Radar vira radar_crm_receber).
-- TUDO FECHADO: RLS ligada sem policy (como no Radar), sem execute para public/anon/authenticated, sem grant de tabela,
--   sem cron e sem segredo do vault. Nada aqui e chamavel pela API. A abertura (grants do gravador, rotinas, segredos,
--   revisao das funcoes que mexem no auth compartilhado) e outra migration, depois da copia e da conferencia dos dados.
-- IDENTIFICACAO: cada schema, tabela e funcao publica leva o comentario "Radar (sistema original)".
-- REVERSAO: drop schema radar cascade; drop schema radar_crm cascade; drop das funcoes public.radar_* (lista no fim).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local check_function_bodies = off;
select pg_catalog.set_config('search_path', '', true);

-- guarda de premissa: nada com esses nomes pode existir
do $guarda$
begin
  if exists (select 1 from pg_namespace where nspname in ('radar', 'radar_crm')) then
    raise exception 'radar: o schema radar ou radar_crm ja existe; nada foi feito';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any (array['radar_acessos', 'radar_api', 'radar_chaves', 'radar_coletar', 'radar_crm', 'radar_crm_receber', 'radar_equipe', 'radar_eu', 'radar_externo', 'radar_feedback', 'radar_gravacoes', 'radar_integracoes', 'radar_minha_chave', 'radar_minha_senha', 'radar_primeiro_acesso', 'radar_primeiro_acesso_aberto', 'radar_rotina', 'radar_salvar_projeto', 'radar_salvar_publicacoes', 'radar_sendflow', 'radar_split_contar', 'radar_split_regras'])) then
    raise exception 'radar: ja existe funcao public.radar_* com o mesmo nome; nada foi feito';
  end if;
end $guarda$;
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6


--
-- Name: crm; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA radar_crm;


--
-- Name: radar; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA radar;


--
-- Name: apagar(jsonb, uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.apagar(f jsonb, p_quem uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_id uuid;
  v_p radar_crm.pessoas;
begin
  begin v_id := (f ->> 'id')::uuid; exception when others then v_id := null; end;
  select * into v_p from radar_crm.pessoas where id = v_id;
  if v_p.id is null then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
  insert into radar_crm.exclusoes (quem, projeto, email_sha256, motivo)
  values (p_quem, v_p.projeto, encode(sha256(convert_to(v_p.email, 'UTF8')), 'hex'), left(coalesce(f ->> 'motivo', ''), 200));
  insert into radar_crm.aberturas (quem, pessoa, acao) values (p_quem, v_p.id, 'apagar');
  delete from radar_crm.pessoas where id = v_p.id;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: api_conferencia(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_conferencia(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with par as (
    select f ->> 'projeto' as projeto,
           coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de,
           coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate,
           nullif(f ->> 'pagina', '') as pagina
  ), cfg as (
    select array(select jsonb_array_elements_text(coalesce(p.config -> 'eventos_lead', '[]'::jsonb))) as leads,
           -- 071: o servidor do funil anota o Active (o contrato diz radar_crm.active = false quando quem grava e a funcao do funil)
           coalesce(p.config -> 'crm' ->> 'active', '') <> 'false' as anota_active
    from radar.projetos p, par where p.id = par.projeto
  ), desde as (
    select min(e.quando) as q from radar_crm.envios e, par where e.projeto = par.projeto and e.via <> 'importado'
  ), nav as (
    select ev.dia, ev.sessao, min(ev.quando) as quando
    from radar.eventos_funil ev join radar.sessoes s on s.id = ev.sessao, par, cfg
    where ev.projeto = par.projeto and ev.dia between par.de and par.ate and ev.nome = any (cfg.leads) and not s.teste
      and (par.pagina is null or ev.pagina = par.pagina)
    group by 1, 2
  ), falhou as (
    select ev.dia, count(distinct ev.sessao) as n
    from radar.eventos_funil ev join radar.sessoes s on s.id = ev.sessao, par
    where ev.projeto = par.projeto and ev.dia between par.de and par.ate and ev.nome = 'envio_falhou' and not s.teste
      and (par.pagina is null or ev.pagina = par.pagina)
    group by 1
  ), ent as (
    select (e.quando at time zone 'America/Sao_Paulo')::date as dia, e.*
    from radar_crm.envios e join radar_crm.pessoas p on p.id = e.pessoa, par
    where e.projeto = par.projeto and e.tipo in ('inscricao', 'captura') and not p.teste and not e.teste
      and (e.quando at time zone 'America/Sao_Paulo')::date between par.de and par.ate
      and (par.pagina is null or e.pagina = par.pagina)
  ), cand as (
    -- 057: o que nao chegou ao Active e vale um reenvio, de todas as etapas (a pesquisa da pessoa conta na pagina por
    -- onde ela entrou)
    select c.envio, c.tipo, c.quando, c.pessoa, e.sessao
    from par cross join lateral radar_crm.reenvios_candidatos(par.projeto) c join radar_crm.envios e on e.id = c.envio
    join radar_crm.pessoas p on p.id = c.pessoa
    where (c.quando at time zone 'America/Sao_Paulo')::date between par.de and par.ate
      and (par.pagina is null or e.pagina = par.pagina or (c.tipo not in ('inscricao', 'captura') and p.pagina_primeira = par.pagina))
  ), novas as (
    select (p.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, count(*) as n
    from radar_crm.pessoas p, par where p.projeto = par.projeto and not p.teste and (par.pagina is null or p.pagina_primeira = par.pagina) group by 1
  ), dias as (
    select d::date as dia from par, generate_series(par.de, par.ate, interval '1 day') d
  ), faltas as (
    select * from (
      select 'sem_servidor' as tipo, n.quando, null::uuid as pessoa, n.sessao, null::uuid as envio, null::text as etapa
      from nav n, desde where desde.q is not null and n.quando >= desde.q
        and not exists (select 1 from radar_crm.envios e where e.sessao = n.sessao)
      union all
      select 'active_erro', c.quando, c.pessoa, nullif(c.sessao, ''), c.envio, c.tipo from cand c
      union all
      select 'active_pendente', ent.quando, ent.pessoa, nullif(ent.sessao, ''), ent.id, ent.tipo
      from ent where ent.via <> 'importado' and coalesce(ent.active ->> 'situacao', 'pendente') = 'pendente' and ent.quando < now() - interval '15 minutes'
        and (select anota_active from cfg)
      union all
      select 'planilha_erro', ent.quando, ent.pessoa, nullif(ent.sessao, ''), ent.id, ent.tipo from ent where ent.planilha ->> 'situacao' = 'erro'
    ) x order by quando desc limit 200
  )
  select jsonb_build_object(
    'desde_servidor', (select q from desde),
    'pagina', (select pagina from par),
    'dias', coalesce((select jsonb_agg(jsonb_build_object(
      'dia', d.dia::text,
      'navegador', (select count(*) from nav where nav.dia = d.dia),
      'navegador_com_servidor', (select count(*) from nav where nav.dia = d.dia and exists (select 1 from radar_crm.envios e where e.sessao = nav.sessao)),
      'falhou_no_navegador', coalesce((select n from falhou where falhou.dia = d.dia), 0),
      'servidor', (select count(*) from ent where ent.dia = d.dia),
      'importados', (select count(*) from ent where ent.dia = d.dia and ent.via = 'importado'),
      'com_visita', (select count(*) from ent where ent.dia = d.dia and ent.sessao <> ''),
      'pessoas_novas', coalesce((select n from novas where novas.dia = d.dia), 0),
      'active_novo', (select count(*) from ent where ent.dia = d.dia and ent.active ->> 'situacao' = 'novo'),
      'active_existente', (select count(*) from ent where ent.dia = d.dia and ent.active ->> 'situacao' = 'existente'),
      'active_erro', (select count(*) from ent where ent.dia = d.dia and ent.active ->> 'situacao' = 'erro'),
      'active_pendente', (select count(*) from ent where ent.dia = d.dia and ent.via <> 'importado' and coalesce(ent.active ->> 'situacao', 'pendente') = 'pendente'
                          and (select anota_active from cfg)),
      'active_sem_informacao', (select count(*) from ent where ent.dia = d.dia and ent.via = 'importado' and coalesce(ent.active ->> 'situacao', '') = ''),
      'active_reenviado', (select count(*) from ent where ent.dia = d.dia and ent.active ? 'reenvio' and ent.active ->> 'situacao' in ('novo', 'existente')),
      'planilha_ok', (select count(*) from ent where ent.dia = d.dia and ent.planilha ->> 'situacao' = 'ok'),
      'planilha_erro', (select count(*) from ent where ent.dia = d.dia and ent.planilha ->> 'situacao' = 'erro'),
      'planilha_navegador', (select count(*) from ent where ent.dia = d.dia and ent.planilha ->> 'situacao' = 'navegador'))
      order by d.dia desc) from dias d), '[]'::jsonb),
    'faltas', coalesce((select jsonb_agg(jsonb_build_object(
      'tipo', fa.tipo, 'quando', fa.quando, 'sessao', fa.sessao, 'pessoa', fa.pessoa, 'etapa', fa.etapa,
      'nome', (select p.nome from radar_crm.pessoas p where p.id = fa.pessoa),
      -- 057: o reenvio daquele envio (pendente ou desistiu), quando ha
      'reenvio', (select r.situacao from radar_crm.reenvios r where r.envio = fa.envio order by r.id desc limit 1)) order by fa.quando desc) from faltas fa), '[]'::jsonb))
$$;


--
-- Name: api_exportacoes(jsonb, text[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_exportacoes(f jsonb, p_projetos text[] DEFAULT NULL::text[]) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  select jsonb_build_object('itens', coalesce((
    select jsonb_agg(jsonb_build_object('id', e.id, 'quando', e.quando, 'quem', coalesce(nullif(m.nome, ''), m.email, 'sem nome'),
                                        'projeto', e.projeto, 'filtro', e.filtro, 'quantas', e.quantas) order by e.quando desc)
    from (select * from radar_crm.exportacoes
          where (coalesce(f ->> 'projeto', '') = '' or projeto = f ->> 'projeto')
            and (p_projetos is null or projeto = any (p_projetos))
          order by quando desc limit 100) e
    left join radar.membros m on m.usuario = e.quem), '[]'::jsonb))
$$;


--
-- Name: api_ficha(jsonb, uuid, bigint); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_ficha(f jsonb, p_quem uuid, p_chave bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_id uuid;
  v_p radar_crm.pessoas;
begin
  begin v_id := (f ->> 'id')::uuid; exception when others then v_id := null; end;
  select * into v_p from radar_crm.pessoas where id = v_id;
  if v_p.id is null then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
  insert into radar_crm.aberturas (quem, pessoa, acao, via, chave) values (p_quem, v_p.id, 'ficha', case when p_chave is null then 'tela' else 'chave' end, p_chave);
  return jsonb_build_object(
    'ok', true,
    'pessoa', to_jsonb(v_p),
    'envios', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'quando', e.quando, 'tipo', e.tipo, 'pagina', e.pagina, 'dados', e.dados,
                                          'sessao', nullif(e.sessao, ''), 'servidor_ms', e.servidor_ms, 'active', e.active,
                                          'planilha', e.planilha, 'via', e.via) order by e.quando, e.recebido_em)
      from radar_crm.envios e where e.pessoa = v_p.id), '[]'::jsonb),
    'visitas', coalesce((
      select jsonb_agg(jsonb_build_object('sessao', s.id, 'inicio', s.inicio, 'fim', s.fim, 'dispositivo', s.dispositivo,
                                          'sistema', s.sistema, 'app', s.app, 'navegador', s.navegador, 'paginas', s.paginas,
                                          'primeira_pagina', s.primeira_pagina, 'ultima_pagina', s.ultima_pagina,
                                          'visivel_ms', s.visivel_ms, 'lead', s.lead, 'gravada', s.gravada,
                                          'utm_source', s.utm_source, 'utm_campaign', s.utm_campaign, 'ad_id', s.ad_id,
                                          'cidade', s.cidade, 'estado', s.estado,
                                          'do_envio', s.id in (select e.sessao from radar_crm.envios e where e.pessoa = v_p.id))
                       order by s.inicio desc)
      from (select * from radar.sessoes s
            where s.projeto = v_p.projeto
              and (s.id in (select e.sessao from radar_crm.envios e where e.pessoa = v_p.id and e.sessao <> '')
                   or (v_p.visitante <> '' and s.visitante = v_p.visitante))
            order by s.inicio desc limit 30) s), '[]'::jsonb));
end $$;


--
-- Name: api_lista(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_lista(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with par as (
    select least(greatest(radar.inteiro(f ->> 'limite', 50), 1), 200)::int as lim,
           greatest(radar.inteiro(f ->> 'pag', 1), 1)::int as pag
  ), base as (
    -- 044: o filtro mora em radar_crm.filtradas (o mesmo da exportacao)
    select * from radar_crm.filtradas(f)
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'por_mql', coalesce((select jsonb_object_agg(mql, n) from (select mql, count(*) as n from base group by mql) x), '{}'::jsonb),
    'pag', (select pag from par), 'limite', (select lim from par),
    'linhas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'nome', b.nome, 'email', b.email, 'telefone', b.telefone,
        'primeiro_em', b.primeiro_em, 'ultimo_em', b.ultimo_em, 'pagina', b.pagina_primeira, 'plataforma', b.plataforma,
        'campanha', b.origem_primeira ->> 'utm_campaign', 'anuncio', coalesce(b.origem_primeira ->> 'ad_id', b.origem_primeira ->> 'utm_content'),
        'parou_em', b.parou_em, 'mql', b.mql, 'inscricoes', b.inscricoes, 'active', b.active, 'active_novo', b.active_novo,
        'planilha', b.planilha, 'teste', b.teste, 'intencao', b.respostas ->> 'intencao', 'via', b.pesquisa_via) order by b.primeiro_em desc)
      from (select base.* from base, par order by base.primeiro_em desc limit (select lim from par) offset ((select pag from par) - 1) * (select lim from par)) b), '[]'::jsonb))
$$;


--
-- Name: api_reenvio(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_reenvio(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with c as (select * from radar_crm.reenvios_candidatos(f ->> 'projeto')),
  fila as (select r.* from radar_crm.reenvios r where r.projeto = f ->> 'projeto'),
  ultima as (select distinct on (envio) * from fila order by envio, id desc)
  select jsonb_build_object(
    'ok', true,
    'active_ligado', exists (select 1 from radar.integracoes i where i.id = 'active' and i.ligada),
    'automatico_desde', (select p.valor #>> '{}' from radar_crm.parametros p where p.chave = 'reenvio_automatico_desde'),
    'faltam', jsonb_build_object(
      'envios', (select count(*) from c),
      'pessoas', (select count(distinct c.pessoa) from c),
      'pessoas_fora', (select count(distinct c.pessoa) from c join radar_crm.pessoas p on p.id = c.pessoa where p.active = 'erro'),
      'por_tipo', coalesce((select jsonb_object_agg(x.tipo, x.n) from (select c.tipo, count(*) as n from c group by 1) x), '{}'::jsonb)),
    'na_fila', (select count(*) from fila where situacao = 'pendente'),
    'na_vez', (select count(*) from fila where situacao = 'pendente' and proxima_em <= now()),
    'proxima', (select min(proxima_em) from fila where situacao = 'pendente'),
    'chegaram', (select count(*) from fila where situacao = 'ok' and resultado in ('novo', 'existente')),
    'chegaram_sozinhos', (select count(*) from fila where situacao = 'ok' and resultado in ('novo', 'existente') and automatico),
    'nao_encontrados', (select count(*) from fila where situacao = 'ok' and resultado = 'nao_encontrado'),
    'desistiu', (select count(*) from ultima where situacao = 'desistiu'),
    'ultimo', (select max(feito_em) from fila),
    'ultimo_pedido', (select max(pedido_em) from fila where not automatico),
    'ultimo_http', (select u.ultimo_http from fila u where u.ultimo_http is not null order by coalesce(u.feito_em, u.pedido_em) desc, u.id desc limit 1))
$$;


--
-- Name: api_resumo(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.api_resumo(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with par as (select f ->> 'projeto' as projeto, radar.hoje() as hoje),
  p as (select radar_crm.pessoas.* from radar_crm.pessoas, par where radar_crm.pessoas.projeto = par.projeto and not radar_crm.pessoas.teste),
  e as (select radar_crm.envios.* from radar_crm.envios join radar_crm.pessoas pp on pp.id = radar_crm.envios.pessoa, par
        where radar_crm.envios.projeto = par.projeto and radar_crm.envios.tipo in ('inscricao', 'captura') and not pp.teste)
  select jsonb_build_object(
    'hoje', jsonb_build_object(
      'inscricoes', (select count(*) from e, par where (e.quando at time zone 'America/Sao_Paulo')::date = par.hoje),
      'pessoas_novas', (select count(*) from p, par where (p.primeiro_em at time zone 'America/Sao_Paulo')::date = par.hoje),
      'mql', (select count(*) from p, par where (p.pesquisa_em at time zone 'America/Sao_Paulo')::date = par.hoje and p.mql = 'sim')),
    'ontem', jsonb_build_object(
      'inscricoes', (select count(*) from e, par where (e.quando at time zone 'America/Sao_Paulo')::date = par.hoje - 1),
      'pessoas_novas', (select count(*) from p, par where (p.primeiro_em at time zone 'America/Sao_Paulo')::date = par.hoje - 1),
      'mql', (select count(*) from p, par where (p.pesquisa_em at time zone 'America/Sao_Paulo')::date = par.hoje - 1 and p.mql = 'sim')),
    'pessoas', (select count(*) from p),
    'desde', (select min(primeiro_em) from p))
$$;


--
-- Name: chave_criar(text, text[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.chave_criar(p_nome text, p_projetos text[]) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_chave text := 'crm_' || substr(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 1, 48);
begin
  if coalesce(btrim(p_nome), '') = '' then raise exception 'nome'; end if;
  if exists (select 1 from unnest(coalesce(p_projetos, '{}')) x where not exists (select 1 from radar.projetos where id = x)) then
    raise exception 'projeto';
  end if;
  insert into radar_crm.chaves_servidor (nome, prefixo, hash, projetos)
  values (left(btrim(p_nome), 80), left(v_chave, 10), encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'), p_projetos);
  return v_chave;
end $$;


--
-- Name: eh_teste(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.eh_teste(p_email text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(p_email ~ '(advmais|advmenos|advmaiss)', false)
$$;


--
-- Name: email_limpo(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.email_limpo(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case when lower(btrim(coalesce(t, ''))) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then left(lower(btrim(t)), 200) end
$_$;


--
-- Name: exportar(jsonb, uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.exportar(f jsonb, p_quem uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_ids uuid[];
  v_n int;
begin
  select coalesce(array_agg(x.id), '{}'), count(*)::int into v_ids, v_n from (select id from radar_crm.filtradas(f) limit 10001) x;
  if v_n > 10000 then return jsonb_build_object('ok', false, 'erro', 'grande', 'limite', 10000); end if;
  insert into radar_crm.exportacoes (quem, projeto, filtro, quantas, pessoas)
  values (p_quem, f ->> 'projeto', f - 'pag' - 'limite', v_n, v_ids);
  return jsonb_build_object('ok', true, 'n', v_n, 'linhas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome', p.nome, 'telefone', p.telefone, 'email', p.email, 'entrou_em', p.primeiro_em, 'pagina', p.pagina_primeira,
      'plataforma', p.plataforma, 'campanha', p.origem_primeira ->> 'utm_campaign',
      'anuncio', coalesce(p.origem_primeira ->> 'ad_id', p.origem_primeira ->> 'utm_content'),
      'parou_em', p.parou_em, 'via', p.pesquisa_via, 'mql', p.mql, 'intencao', p.respostas ->> 'intencao',
      -- 059: o numero pronto para a ferramenta de WhatsApp, a situacao do telefone, se ele se repete e o grupo
      'whatsapp', radar_crm.whatsapp(p.telefone), 'telefone_situacao', radar_crm.telefone_situacao(p.telefone),
      'telefone_repetido', p.telefone in (select r.telefone from radar_crm.telefones_repetidos(f ->> 'projeto') r),
      'grupo', g.situacao,
      -- 064: a entrada e a saida do grupo pelo SendFlow
      'grupo_entrou_em', p.grupo_entrou_em, 'grupo_saiu_em', p.grupo_saiu_em) order by p.primeiro_em desc)
    from radar_crm.pessoas p left join radar_crm.grupo_das(f ->> 'projeto') g on g.pessoa = p.id
    where p.id = any (v_ids)), '[]'::jsonb));
end $$;




--
-- Name: pessoas; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.pessoas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    projeto text NOT NULL,
    email text NOT NULL,
    nome text DEFAULT ''::text NOT NULL,
    telefone text DEFAULT ''::text NOT NULL,
    primeiro_em timestamp with time zone NOT NULL,
    ultimo_em timestamp with time zone NOT NULL,
    pagina_primeira text DEFAULT ''::text NOT NULL,
    pagina_ultima text DEFAULT ''::text NOT NULL,
    origem_primeira jsonb DEFAULT '{}'::jsonb NOT NULL,
    origem_ultima jsonb DEFAULT '{}'::jsonb NOT NULL,
    plataforma text,
    inscricoes integer DEFAULT 0 NOT NULL,
    envios integer DEFAULT 0 NOT NULL,
    parou_em text DEFAULT ''::text NOT NULL,
    mql text DEFAULT 'indefinido'::text NOT NULL,
    respostas jsonb DEFAULT '{}'::jsonb NOT NULL,
    pesquisa_via text DEFAULT ''::text NOT NULL,
    pesquisa_em timestamp with time zone,
    active text DEFAULT ''::text NOT NULL,
    active_novo boolean,
    active_id text DEFAULT ''::text NOT NULL,
    planilha text DEFAULT ''::text NOT NULL,
    visitante text DEFAULT ''::text NOT NULL,
    teste boolean DEFAULT false NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    grupo_entrou_em timestamp with time zone,
    grupo_saiu_em timestamp with time zone,
    grupo_campanha text DEFAULT ''::text NOT NULL,
    CONSTRAINT pessoas_active_check CHECK ((active = ANY (ARRAY[''::text, 'ok'::text, 'erro'::text, 'pendente'::text]))),
    CONSTRAINT pessoas_email_check CHECK (((email = lower(btrim(email))) AND (POSITION(('@'::text) IN (email)) > 1))),
    CONSTRAINT pessoas_mql_check CHECK ((mql = ANY (ARRAY['sim'::text, 'nao'::text, 'indefinido'::text]))),
    CONSTRAINT pessoas_parou_em_check CHECK ((parou_em = ANY (ARRAY[''::text, 'inscricao'::text, 'captura'::text, 'pesquisa_parcial'::text, 'pesquisa'::text]))),
    CONSTRAINT pessoas_pesquisa_via_check CHECK ((pesquisa_via = ANY (ARRAY[''::text, 'pagina'::text, 'link'::text]))),
    CONSTRAINT pessoas_planilha_check CHECK ((planilha = ANY (ARRAY[''::text, 'ok'::text, 'erro'::text, 'navegador'::text])))
);


--
-- Name: filtradas(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.filtradas(f jsonb) RETURNS SETOF radar_crm.pessoas
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  select p.* from radar_crm.pessoas p
  where p.projeto = f ->> 'projeto'
    and (p.primeiro_em at time zone 'America/Sao_Paulo')::date
        between coalesce(radar.data(f ->> 'de'), radar.hoje() - 29) and coalesce(radar.data(f ->> 'ate'), radar.hoje())
    and (coalesce(f ->> 'teste', '') = 'sim' or not p.teste)
    and (coalesce(f ->> 'pagina', '') = '' or p.pagina_primeira = f ->> 'pagina')
    -- as paginas de uma entrada do contrato, separadas por virgula (a AK1 e a raiz)
    and (coalesce(f ->> 'paginas', '') = '' or p.pagina_primeira = any (string_to_array(f ->> 'paginas', ',')))
    and (coalesce(f ->> 'plataforma', '') = '' or coalesce(nullif(p.plataforma, ''), 'sem') = f ->> 'plataforma')
    and (coalesce(f ->> 'mql', '') = '' or p.mql = f ->> 'mql')
    -- onde parou (inscricao, captura, pesquisa_parcial, pesquisa) e o caminho da pesquisa (pagina, link, nenhuma)
    and (coalesce(f ->> 'parou', '') = '' or p.parou_em = any (string_to_array(f ->> 'parou', ',')))
    and (coalesce(f ->> 'via', '') = '' or coalesce(nullif(p.pesquisa_via, ''), 'nenhuma') = any (string_to_array(f ->> 'via', ',')))
    -- 055: o anuncio do primeiro envio (o Trafego › Campanhas e anuncios leva cada linha as pessoas dela). Nomes de UTM,
    -- para nao confundir com os filtros "campanha" e "criativo" da barra, que valem para as visitas
    and (coalesce(f ->> 'utm_campaign', '') = '' or coalesce(p.origem_primeira ->> 'utm_campaign', '') = f ->> 'utm_campaign')
    and (coalesce(f ->> 'utm_term', '') = '' or coalesce(p.origem_primeira ->> 'utm_term', '') = f ->> 'utm_term')
    and (coalesce(f ->> 'utm_content', '') = '' or coalesce(p.origem_primeira ->> 'utm_content', '') = f ->> 'utm_content')
    -- a intencao respondida: igual a uma (o profissional) ou diferente dela (os outros)
    and (coalesce(f ->> 'intencao', '') = '' or coalesce(nullif(p.respostas ->> 'intencao', ''), p.respostas ->> 'nivel', '') = f ->> 'intencao')
    and (coalesce(f ->> 'intencao_nao', '') = '' or coalesce(nullif(p.respostas ->> 'intencao', ''), p.respostas ->> 'nivel', '') <> f ->> 'intencao_nao')
    -- 059: o grupo do WhatsApp (foi, nao, sem), pelo gravador no obrigado
    -- 064: entrou (o SendFlow confirmou) e nao_entrou (inscrito desde a primeira entrada do SendFlow no projeto, sem entrada)
    and (coalesce(f ->> 'grupo', '') = ''
         or (f ->> 'grupo' = 'entrou' and p.grupo_entrou_em is not null)
         or (f ->> 'grupo' = 'nao_entrou' and p.grupo_entrou_em is null and p.primeiro_em >= radar_crm.grupo_desde(f ->> 'projeto'))
         or (f ->> 'grupo' in ('foi', 'nao', 'sem')
             and p.id in (select g.pessoa from radar_crm.grupo_das(f ->> 'projeto') g where g.situacao = f ->> 'grupo')))
    -- 059: o telefone para o WhatsApp: pronto (celular de um numero so dele), problema (o resto), repetido ou a situacao
    and (coalesce(f ->> 'telefone', '') = ''
         or (f ->> 'telefone' = 'pronto' and radar_crm.telefone_situacao(p.telefone) in ('ok', 'sem_9')
             and p.telefone not in (select r.telefone from radar_crm.telefones_repetidos(f ->> 'projeto') r))
         or (f ->> 'telefone' = 'problema' and (radar_crm.telefone_situacao(p.telefone) not in ('ok', 'sem_9')
             or p.telefone in (select r.telefone from radar_crm.telefones_repetidos(f ->> 'projeto') r)))
         or (f ->> 'telefone' = 'repetido' and p.telefone in (select r.telefone from radar_crm.telefones_repetidos(f ->> 'projeto') r))
         or radar_crm.telefone_situacao(p.telefone) = f ->> 'telefone')
    and (coalesce(f ->> 'falta', '') = ''
         or (f ->> 'falta' = 'active' and p.active in ('erro', 'pendente'))
         or (f ->> 'falta' = 'planilha' and p.planilha = 'erro'))
    and (btrim(coalesce(f ->> 'busca', '')) = ''
         or strpos(lower(p.nome || ' ' || p.email), lower(btrim(f ->> 'busca'))) > 0
         or (length(regexp_replace(coalesce(f ->> 'busca', ''), '\D', '', 'g')) >= 4
             and strpos(p.telefone, regexp_replace(coalesce(f ->> 'busca', ''), '\D', '', 'g')) > 0))
$$;


--
-- Name: grupo_aplicar(text, text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_aplicar(p_projeto text, p_chave text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
declare g record; n int;
begin
  if coalesce(p_chave, '') = '' then return 0; end if;
  select * into g from radar_crm.grupo_do_telefone(p_projeto, p_chave);
  update radar_crm.pessoas p set grupo_entrou_em = g.entrou_em, grupo_saiu_em = g.saiu_em, grupo_campanha = coalesce(g.campanha, '')
  where p.projeto = p_projeto and p.telefone <> '' and radar_crm.telefone_chave(p.telefone) = p_chave
    and (p.grupo_entrou_em, p.grupo_saiu_em, p.grupo_campanha) is distinct from (g.entrou_em, g.saiu_em, coalesce(g.campanha, ''));
  get diagnostics n = row_count;
  return n;
end $$;


--
-- Name: grupo_cache_atualizar(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_cache_atualizar() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_proj text;
  v_n int;
  v_mudou int := 0;
begin
  for v_proj in select p.id from radar.projetos p where jsonb_typeof(p.config -> 'fluxo' -> 'grupo') = 'object' loop
    insert into radar_crm.grupo_cache (pessoa, projeto, situacao, calculado_em)
      select g.pessoa, v_proj, g.situacao, now() from radar_crm.grupo_calcular(v_proj, null) g
    on conflict (pessoa) do update set situacao = excluded.situacao, projeto = excluded.projeto, calculado_em = excluded.calculado_em
      where radar_crm.grupo_cache.situacao is distinct from excluded.situacao or radar_crm.grupo_cache.projeto is distinct from excluded.projeto;
    get diagnostics v_n = row_count;
    v_mudou := v_mudou + v_n;
  end loop;
  -- quem virou teste ou o projeto que perdeu o grupo no contrato: fora da tabela
  delete from radar_crm.grupo_cache c
  where not exists (select 1 from radar_crm.pessoas p join radar.projetos x on x.id = p.projeto
                    where p.id = c.pessoa and not p.teste and jsonb_typeof(x.config -> 'fluxo' -> 'grupo') = 'object');
  return jsonb_build_object('ok', true, 'mudou', v_mudou);
end $$;


--
-- Name: grupo_calcular(text, uuid[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_calcular(p_projeto text, p_ids uuid[]) RETURNS TABLE(pessoa uuid, situacao text, entrou boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with
  par as (
    -- 071: varias paginas de obrigado (paginas: a Black tem um obrigado por area); sem a lista, a pagina de antes
    select case when jsonb_typeof(g -> 'paginas') = 'array' and jsonb_array_length(g -> 'paginas') > 0
                then array(select jsonb_array_elements_text(g -> 'paginas'))
                else array[coalesce(g ->> 'pagina', 'obrigado')] end as paginas,
           coalesce(g ->> 'vista', 'obrigado_vista') as vista,
           array(select jsonb_array_elements_text(case when jsonb_typeof(g -> 'eventos') = 'array' then g -> 'eventos' else '[]'::jsonb end)) as eventos,
           coalesce(g ->> 'cta', '') as cta
    from (select p.config -> 'fluxo' -> 'grupo' as g from radar.projetos p where p.id = p_projeto) x
    where jsonb_typeof(g) = 'object'),
  gente as (
    select p.id, p.visitante, (p.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, p.grupo_entrou_em is not null as entrou
    from radar_crm.pessoas p where p.projeto = p_projeto and not p.teste and exists (select 1 from par)
      -- 072: so as pessoas pedidas (nulo: todas, como a grupo_das)
      and (p_ids is null or p.id in (select unnest(p_ids)))),
  -- as visitas de cada pessoa: as dos envios dela e as do mesmo visitante desde a vespera da entrada
  ses as (
    select e.pessoa, e.sessao from radar_crm.envios e join gente g on g.id = e.pessoa where e.sessao <> ''
    union
    select g.id, s.id from gente g
    join radar.sessoes s on s.projeto = p_projeto and s.visitante = g.visitante and s.dia >= g.dia - 1 and not s.teste
    where g.visitante <> ''),
  viu as (
    select distinct x.pessoa from ses x cross join par
    join radar.eventos_funil e on e.sessao = x.sessao and e.pagina = any (par.paginas) and e.nome = par.vista),
  foi as (
    select distinct x.pessoa from ses x cross join par
    where exists (select 1 from radar.eventos_funil e where e.sessao = x.sessao and e.nome = any (par.eventos))
       or (par.cta <> '' and exists (select 1 from radar.cliques c where c.sessao = x.sessao and c.pagina = any (par.paginas)
                                     and strpos(c.seletor, '[data-cta="' || par.cta || '"]') > 0)))
  select g.id, case when g.id in (select f.pessoa from foi f) then 'foi' when g.id in (select v.pessoa from viu v) then 'nao' else 'sem' end,
         g.entrou
  from gente g
$$;


--
-- Name: grupo_das(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_das(p_projeto text) RETURNS TABLE(pessoa uuid, situacao text, entrou boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  select g.pessoa, g.situacao, g.entrou from radar_crm.grupo_de(p_projeto, null) g
$$;


--
-- Name: grupo_de(text, uuid[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_de(p_projeto text, p_ids uuid[]) RETURNS TABLE(pessoa uuid, situacao text, entrou boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with
  pedidas as materialized (
    select p.id, p.grupo_entrou_em is not null as entrou
    from radar_crm.pessoas p
    where p.projeto = p_projeto and not p.teste
      and (p_ids is null or p.id in (select unnest(p_ids)))
      and exists (select 1 from radar.projetos x where x.id = p_projeto and jsonb_typeof(x.config -> 'fluxo' -> 'grupo') = 'object')),
  guardadas as materialized (
    select c.pessoa, c.situacao from radar_crm.grupo_cache c join pedidas q on q.id = c.pessoa where c.projeto = p_projeto),
  -- quem ainda nao esta guardado (inscrito depois da ultima rodada): a conta na hora, so dessas pessoas
  faltam as materialized (
    select coalesce(array_agg(q.id), '{}'::uuid[]) as ids from pedidas q where not exists (select 1 from guardadas g where g.pessoa = q.id))
  select q.id, g.situacao, q.entrou from pedidas q join guardadas g on g.pessoa = q.id
  union all
  select c.pessoa, c.situacao, c.entrou from faltam f cross join lateral radar_crm.grupo_calcular(p_projeto, f.ids) c
  where cardinality(f.ids) > 0
$$;


--
-- Name: grupo_desde(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_desde(p_projeto text) RETURNS timestamp with time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
  select min(quando) from radar_crm.grupo_eventos where projeto = p_projeto and acao in ('entrou', 'saiu')
$$;


--
-- Name: grupo_do_telefone(text, text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_do_telefone(p_projeto text, p_chave text) RETURNS TABLE(entrou_em timestamp with time zone, saiu_em timestamp with time zone, campanha text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
  with e as (select * from radar_crm.grupo_eventos where projeto = p_projeto and telefone_chave = p_chave and acao in ('entrou', 'saiu')),
  x as (select min(quando) filter (where acao = 'entrou') as primeira, max(quando) filter (where acao = 'entrou') as ultima,
               max(quando) filter (where acao = 'saiu') as saiu from e)
  select x.primeira,
         case when x.saiu is not null and (x.ultima is null or x.saiu > x.ultima) then x.saiu end,
         coalesce((select coalesce(nullif(e.campanha, ''), e.grupo) from e where e.acao = 'entrou' order by e.quando limit 1), '')
  from x
$$;


--
-- Name: grupo_eventos_depois(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.grupo_eventos_depois() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
begin
  if new.acao in ('entrou', 'saiu') then perform radar_crm.grupo_aplicar(new.projeto, new.telefone_chave); end if;
  return null;
end $$;


--
-- Name: guardar_envio(jsonb, text[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.guardar_envio(p jsonb, p_projetos text[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $_$
declare
  v_id uuid;
  v_proj text := p ->> 'projeto';
  v_email text := radar_crm.email_limpo(p ->> 'email');
  v_tipo text := p ->> 'tipo';
  v_quando timestamptz;
  v_pessoa uuid;
  v_dados jsonb;
  v_sessao text := split_part(coalesce(p ->> 'sessao', ''), '.', 1);
  v_visitante text := coalesce(p ->> 'visitante', '');
  v_via text := coalesce(nullif(p ->> 'via', ''), 'servidor');
  v_active jsonb := coalesce(p -> 'active', '{}'::jsonb);
  v_planilha jsonb := coalesce(p -> 'planilha', '{}'::jsonb);
begin
  begin v_id := (p ->> 'id')::uuid; exception when others then v_id := null; end;
  if v_id is null then return jsonb_build_object('ok', false, 'erro', 'id'); end if;
  if v_proj is null or not exists (select 1 from radar.projetos where id = v_proj) then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
  if not (v_proj = any (coalesce(p_projetos, '{}'))) then return jsonb_build_object('ok', false, 'erro', 'projeto_fora_da_chave'); end if;
  if v_email is null then return jsonb_build_object('ok', false, 'erro', 'email'); end if;
  if v_tipo is null or v_tipo not in ('inscricao', 'captura', 'pesquisa_parcial', 'pesquisa', 'pesquisa_link') then
    return jsonb_build_object('ok', false, 'erro', 'tipo');
  end if;
  begin v_quando := (p ->> 'quando')::timestamptz; exception when others then v_quando := null; end;
  if v_quando is null or v_quando > now() + interval '1 hour' or v_quando < timestamptz '2026-09-01' then v_quando := now(); end if;
  if v_sessao !~ '^[A-Za-z0-9]{8,40}$' then v_sessao := ''; end if;
  if v_visitante !~ '^[A-Za-z0-9]{8,40}$' then v_visitante := ''; end if;
  if v_via not in ('servidor', 'fila', 'importado') then v_via := 'servidor'; end if;
  if jsonb_typeof(v_active) <> 'object' then v_active := '{}'; end if;
  if jsonb_typeof(v_planilha) <> 'object' then v_planilha := '{}'; end if;
  v_dados := jsonb_strip_nulls(jsonb_build_object(
    'nome', nullif(left(regexp_replace(btrim(coalesce(p ->> 'nome', '')), '\s+', ' ', 'g'), 120), ''),
    'telefone', nullif(radar_crm.telefone_limpo(p ->> 'telefone'), ''),
    'origem', nullif(radar_crm.origem_limpa(coalesce(p -> 'origem', '{}'::jsonb)), '{}'::jsonb),
    'respostas', nullif(radar_crm.respostas_limpas(coalesce(p -> 'respostas', '{}'::jsonb)), '{}'::jsonb),
    'mql', case when p ->> 'mql' in ('sim', 'nao') then p ->> 'mql' end,
    'caixinha', case when p ->> 'caixinha' in ('sim', 'nao') then p ->> 'caixinha' end,
    'lead_id', nullif(left(coalesce(p ->> 'lead_id', ''), 64), ''),
    'pagina_origem', nullif(left(coalesce(p ->> 'pagina_origem', ''), 120), '')));

  -- o envio que ja existe continua com a pessoa dele; o novo acha (ou cria) a pessoa pelo e-mail
  select e.pessoa into v_pessoa from radar_crm.envios e where e.id = v_id;
  if v_pessoa is null then
    insert into radar_crm.pessoas (projeto, email, primeiro_em, ultimo_em)
    values (v_proj, v_email, v_quando, v_quando)
    on conflict (projeto, email) do update set atualizado_em = now()
    returning id into v_pessoa;
  end if;

  insert into radar_crm.envios (id, pessoa, projeto, quando, tipo, pagina, dados, sessao, visitante, servidor_ms, active, planilha, via, teste)
  values (v_id, v_pessoa, v_proj, v_quando, v_tipo, left(coalesce(p ->> 'pagina', ''), 120), v_dados, v_sessao, v_visitante,
          case when coalesce(p ->> 'servidor_ms', '') ~ '^\d{1,7}$' then (p ->> 'servidor_ms')::int end,
          v_active, v_planilha, v_via, coalesce(p ->> 'teste', '') in ('1', 'true', 'sim'))
  on conflict (id) do update set
    dados = excluded.dados || radar_crm.envios.dados,
    sessao = case when radar_crm.envios.sessao = '' then excluded.sessao else radar_crm.envios.sessao end,
    visitante = case when radar_crm.envios.visitante = '' then excluded.visitante else radar_crm.envios.visitante end,
    servidor_ms = coalesce(radar_crm.envios.servidor_ms, excluded.servidor_ms),
    active = case when excluded.active <> '{}'::jsonb then excluded.active else radar_crm.envios.active end,
    planilha = case when excluded.planilha <> '{}'::jsonb then excluded.planilha else radar_crm.envios.planilha end,
    atualizado_em = now()
  returning pessoa into v_pessoa;

  perform radar_crm.recalcular(v_pessoa);
  return jsonb_build_object('ok', true, 'id', v_id);
end $_$;


--
-- Name: ingresso(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.ingresso(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
with
par as (select radar_crm.grupo_desde(f ->> 'projeto') as desde,
               coalesce(radar.data(f ->> 'de'), radar.hoje() - 29) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate),
seg as materialized (select p.id, p.primeiro_em, p.grupo_entrou_em, p.grupo_saiu_em from radar_crm.filtradas(f - 'busca') p),
gr as materialized (select g.pessoa, g.situacao from radar_crm.grupo_de(f ->> 'projeto', (select array_agg(s.id) from seg s)) g),
med as materialized (  -- so quem se inscreveu desde que o SendFlow conta
  select s.*, coalesce(g.situacao, 'sem') as situacao from seg s left join gr g on g.pessoa = s.id cross join par
  where par.desde is not null and s.primeiro_em >= par.desde),
ev as (
  select (e.quando at time zone 'America/Sao_Paulo')::date as dia, e.acao, e.telefone_chave
  from radar_crm.grupo_eventos e cross join par
  where e.projeto = f ->> 'projeto' and e.acao in ('entrou', 'saiu')
    and (e.quando at time zone 'America/Sao_Paulo')::date between par.de and par.ate),
dias as (
  select dia, count(distinct telefone_chave) filter (where acao = 'entrou') as entradas,
         count(distinct telefone_chave) filter (where acao = 'saiu') as saidas
  from ev group by dia)
select jsonb_build_object(
  'ok', true,
  'desde', (select desde from par),
  'pessoas', (select count(*) from seg),
  -- as pessoas que o SendFlow pode medir (inscritas desde o primeiro evento) e os tres degraus delas
  'medidas', (select count(*) from med),
  'viu_obrigado', (select count(*) from med where situacao in ('foi', 'nao')),
  'foi_levado', (select count(*) from med where situacao = 'foi'),
  'entrou_de_fato', (select count(*) from med where grupo_entrou_em is not null),
  'entrou_dos_que_viram', (select count(*) from med where situacao in ('foi', 'nao') and grupo_entrou_em is not null),
  'entrou_sem_registro', (select count(*) from med where situacao = 'sem' and grupo_entrou_em is not null),
  'no_grupo_agora', (select count(*) from med where grupo_entrou_em is not null and grupo_saiu_em is null),
  -- entrou / viu o obrigado; nulo sem base
  'taxa_ingresso', (select round(count(*) filter (where grupo_entrou_em is not null)::numeric / nullif(count(*), 0), 4)
                    from med where situacao in ('foi', 'nao')),
  'taxa_encaminhamento', (select round(count(*) filter (where situacao = 'foi')::numeric / nullif(count(*), 0), 4)
                          from med where situacao in ('foi', 'nao')),
  -- pelo SendFlow, por dia (telefones distintos; casados ou nao com o CRM)
  'por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', dia, 'entradas', entradas, 'saidas', saidas) order by dia) from dias), '[]'::jsonb),
  'casadas', (select count(distinct e.telefone_chave) from ev e where e.acao = 'entrou' and exists (
                select 1 from radar_crm.pessoas p where p.projeto = f ->> 'projeto' and p.telefone <> ''
                  and radar_crm.telefone_chave(p.telefone) = e.telefone_chave)),
  'entradas', (select count(distinct telefone_chave) from ev where acao = 'entrou'))
$$;


--
-- Name: ligar_recentes(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.ligar_recentes() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_proj text;
  n int := 0;
begin
  for v_proj in
    select distinct e.projeto from radar_crm.envios e
    where e.quando >= now() - interval '2 days' and e.sessao = '' and e.tipo in ('inscricao', 'captura') and e.via <> 'importado'
  loop
    n := n + radar_crm.ligar_visitas(v_proj, now() - interval '2 days');
  end loop;
  return n;
end $$;


--
-- Name: ligar_visitas(text, timestamp with time zone); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.ligar_visitas(p_projeto text, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_leads text[];
  v_dia date := coalesce((p_desde at time zone 'America/Sao_Paulo')::date - 1, '2000-01-01'::date);
  n int := 0;
  r record;
begin
  select array(select jsonb_array_elements_text(coalesce(config -> 'eventos_lead', '[]'::jsonb))) into v_leads
  from radar.projetos where id = p_projeto;
  for r in
    with ev as (
      select e.sessao, min(e.quando) as quando, min(e.pagina) as pagina
      from radar.eventos_funil e join radar.sessoes s on s.id = e.sessao
      where e.projeto = p_projeto and e.dia >= v_dia and e.nome = any (v_leads) and not s.teste
        and not exists (select 1 from radar_crm.envios x where x.sessao = e.sessao)
      group by 1
    ), cand as (
      select en.id as envio, en.pessoa, ev.sessao
      from radar_crm.envios en join ev on ev.quando between en.quando - interval '90 seconds' and en.quando + interval '90 seconds'
                                  and ev.pagina = en.pagina
      where en.projeto = p_projeto and en.sessao = '' and en.tipo in ('inscricao', 'captura')
        and (p_desde is null or en.quando >= p_desde)
    ), unicos as (
      select c.* from cand c
      where (select count(*) from cand c2 where c2.envio = c.envio) = 1
        and (select count(*) from cand c3 where c3.sessao = c.sessao) = 1
    )
    select u.envio, u.pessoa, u.sessao, s.visitante from unicos u join radar.sessoes s on s.id = u.sessao
  loop
    update radar_crm.envios set sessao = r.sessao, visitante = case when visitante = '' then r.visitante else visitante end, atualizado_em = now()
    where id = r.envio and sessao = '';
    perform radar_crm.recalcular(r.pessoa);
    n := n + 1;
  end loop;
  return n;
end $$;


--
-- Name: manter(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.manter() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
declare
  n int;
  k int;
  l int;
begin
  delete from radar_crm.aberturas where quando < now() - interval '400 days';
  get diagnostics n = row_count;
  -- 044: as exportacoes ficam o mesmo tempo
  delete from radar_crm.exportacoes where quando < now() - interval '400 days';
  get diagnostics k = row_count;
  -- 045: e as listas lidas pela chave pessoal
  delete from radar_crm.leituras_porta where quando < now() - interval '400 days';
  get diagnostics l = row_count;
  return n + k + l;
end $$;


--
-- Name: origem_limpa(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.origem_limpa(j jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  select jsonb_strip_nulls(jsonb_build_object(
    'utm_source', nullif(left(btrim(coalesce(c.u ->> 'utm_source', '')), 200), ''),
    'utm_medium', nullif(left(btrim(coalesce(c.u ->> 'utm_medium', '')), 200), ''),
    'utm_campaign', nullif(left(btrim(coalesce(c.u ->> 'utm_campaign', '')), 200), ''),
    'utm_content', nullif(left(btrim(coalesce(c.u ->> 'utm_content', '')), 200), ''),
    'utm_term', nullif(left(btrim(coalesce(c.u ->> 'utm_term', '')), 200), ''),
    'campaign_id', nullif(left(btrim(coalesce(c.u ->> 'campaign_id', '')), 40), ''),
    'adset_id', nullif(left(btrim(coalesce(c.u ->> 'adset_id', '')), 40), ''),
    'ad_id', nullif(left(btrim(coalesce(c.u ->> 'ad_id', '')), 40), ''),
    'fbclid', case when coalesce(c.u ->> 'fbclid', '') in ('', '0', 'false') then null else true end,
    'gclid', case when coalesce(c.u ->> 'gclid', '') in ('', '0', 'false') then null else true end))
  -- 071: no padrao da casa antes de limpar (as UTMs nome|id viram os ids); a do PB passa igual
  from (select radar.utm_canonica(j) as u) c
$$;


--
-- Name: pessoas_das_visitas(text, text[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.pessoas_das_visitas(p_projeto text, p_sessoes text[]) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
  with s as (
    select s.id, s.visitante from radar.sessoes s
    where s.projeto = p_projeto and s.id = any ((coalesce(p_sessoes, '{}'::text[]))[1:100])
  ), pe as (
    select distinct on (e.sessao) e.sessao, e.pessoa from radar_crm.envios e join s on s.id = e.sessao
    where e.projeto = p_projeto and e.pessoa is not null
    order by e.sessao, e.quando
  ), pv as (
    select distinct on (s.id) s.id as sessao, x.id as pessoa from s
    join radar_crm.pessoas x on x.projeto = p_projeto and x.visitante <> '' and x.visitante = s.visitante
    order by s.id, x.primeiro_em
  )
  select coalesce(jsonb_object_agg(s.id, coalesce(pe.pessoa, pv.pessoa)) filter (where coalesce(pe.pessoa, pv.pessoa) is not null), '{}'::jsonb)
  from s left join pe on pe.sessao = s.id left join pv on pv.sessao = s.id
$$;


--
-- Name: pessoas_grupo(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.pessoas_grupo() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
declare g record; v_chave text := radar_crm.telefone_chave(new.telefone);
begin
  if v_chave = '' then
    new.grupo_entrou_em := null; new.grupo_saiu_em := null; new.grupo_campanha := '';
    return new;
  end if;
  select * into g from radar_crm.grupo_do_telefone(new.projeto, v_chave);
  new.grupo_entrou_em := g.entrou_em; new.grupo_saiu_em := g.saiu_em; new.grupo_campanha := coalesce(g.campanha, '');
  return new;
end $$;


--
-- Name: plano_active(uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.plano_active(p_envio uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_plano jsonb := radar_crm.plano_active_bruto(p_envio);
  v_depois jsonb;
  v_tirar text[];
  v_contato jsonb;
begin
  if not coalesce((v_plano ->> 'ok')::boolean, false) then return v_plano; end if;
  select coalesce(jsonb_agg(radar_crm.plano_active_bruto(l.id) -> 'contato'), '[]'::jsonb) into v_depois
  from radar_crm.envios e join radar_crm.envios l on l.pessoa = e.pessoa and l.id <> e.id and (l.quando, l.id::text) > (e.quando, e.id::text)
  where e.id = p_envio;
  select coalesce(array_agg(distinct f ->> 'field'), '{}') into v_tirar
  from jsonb_array_elements(v_depois) c, jsonb_array_elements(coalesce(c -> 'fieldValues', '[]'::jsonb)) f;
  v_contato := v_plano -> 'contato';
  v_contato := jsonb_set(v_contato, '{fieldValues}', coalesce((
    select jsonb_agg(f.v order by f.n) from jsonb_array_elements(v_contato -> 'fieldValues') with ordinality f(v, n)
    where not (f.v ->> 'field' = any (v_tirar))), '[]'::jsonb));
  if exists (select 1 from jsonb_array_elements(v_depois) c where c ? 'firstName') then v_contato := v_contato - 'firstName' - 'lastName'; end if;
  if exists (select 1 from jsonb_array_elements(v_depois) c where c ? 'phone') then v_contato := v_contato - 'phone'; end if;
  return v_plano || jsonb_build_object('contato', v_contato, 'deixou_de_fora', to_jsonb(v_tirar));
end $$;


--
-- Name: plano_active_bruto(uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.plano_active_bruto(p_envio uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $_$
declare
  e radar_crm.envios;
  v_email text;
  d jsonb;
  o jsonb;
  r jsonb;
  v_nome text;
  v_primeiro text;
  v_resto text;
  v_tel text;
  v_quando text;
  v_mql boolean;
  v_prof boolean;
  v_campos jsonb;
  v_contato jsonb;
  v_passos jsonb := '[]'::jsonb;
  v_dest int;
begin
  select * into e from radar_crm.envios where id = p_envio;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
  if e.projeto <> 'patrimonio-brasil' then return jsonb_build_object('ok', false, 'erro', 'sem_receita'); end if;
  select p.email into v_email from radar_crm.pessoas p where p.id = e.pessoa;
  d := e.dados;
  o := coalesce(d -> 'origem', '{}'::jsonb);
  r := coalesce(d -> 'respostas', '{}'::jsonb);
  v_nome := btrim(coalesce(d ->> 'nome', ''));
  -- como o preg_split('/\s+/', $nome, 2) do servidor: a primeira palavra e o resto
  v_primeiro := coalesce(substring(v_nome from '^\S+'), '');
  v_resto := case when v_nome ~ '\s' then regexp_replace(v_nome, '^\S+\s+', '') else '' end;
  -- o servidor so manda telefone de 10 ou 11 numeros, com o 55 na frente
  v_tel := coalesce(d ->> 'telefone', '');
  if v_tel !~ '^55[0-9]{10,11}$' then v_tel := ''; end if;
  v_quando := to_char(e.quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
  v_mql := d ->> 'mql' = 'sim';
  v_prof := coalesce(r ->> 'intencao', '') = 'Atuo ou quero atuar profissionalmente na área';

  if e.tipo = 'inscricao' then
    -- api/submit.php: todos os campos, mesmo vazios. A 884 so quando foi a caixinha (outra faixa o CRM nao guarda)
    v_campos := jsonb_build_array(
      jsonb_build_object('field', '877', 'value', coalesce(o ->> 'utm_source', '')),
      jsonb_build_object('field', '878', 'value', coalesce(o ->> 'utm_medium', '')),
      jsonb_build_object('field', '879', 'value', coalesce(o ->> 'utm_campaign', '')),
      jsonb_build_object('field', '880', 'value', coalesce(o ->> 'utm_content', '')),
      jsonb_build_object('field', '881', 'value', coalesce(o ->> 'utm_term', '')),
      jsonb_build_object('field', '882', 'value', coalesce(d ->> 'pagina_origem', '')),
      jsonb_build_object('field', '883', 'value', v_quando));
    if d ->> 'caixinha' = 'sim' then
      v_campos := v_campos || jsonb_build_array(jsonb_build_object('field', '884', 'value', 'Acima de R$ 1 milhão (declarado na caixinha)'));
    end if;
    v_contato := jsonb_build_object('email', v_email, 'firstName', v_primeiro, 'lastName', v_resto);
    if v_tel <> '' then v_contato := v_contato || jsonb_build_object('phone', v_tel); end if;
    v_contato := v_contato || jsonb_build_object('fieldValues', v_campos);
    return jsonb_build_object('ok', true, 'tipo', e.tipo, 'contato', v_contato,
      'passos', '[{"o": "lista", "id": 603}, {"o": "lista", "id": 609}, {"o": "tag", "id": 844}]'::jsonb);
  end if;

  -- api/pesquisa.php: so o que tem valor (uma etapa nunca apaga o que a anterior gravou), na ordem do servidor
  select coalesce(jsonb_agg(jsonb_build_object('field', x.f, 'value', x.v) order by x.n), '[]'::jsonb) into v_campos
  from (values
    (1, '901', d ->> 'lead_id'),
    (2, '877', case when e.tipo = 'captura' then o ->> 'utm_source' end),
    (3, '878', case when e.tipo = 'captura' then o ->> 'utm_medium' end),
    (4, '879', case when e.tipo = 'captura' then o ->> 'utm_campaign' end),
    (5, '880', case when e.tipo = 'captura' then o ->> 'utm_content' end),
    (6, '881', case when e.tipo = 'captura' then o ->> 'utm_term' end),
    (7, '882', case when e.tipo = 'captura' then d ->> 'pagina_origem' end),
    (8, '883', case when e.tipo = 'captura' then v_quando end),
    (9, '906', case when e.tipo = 'captura' then o ->> 'campaign_id' end),
    (10, '907', case when e.tipo = 'captura' then o ->> 'adset_id' end),
    (11, '908', case when e.tipo = 'captura' then o ->> 'ad_id' end),
    (12, '902', case when e.tipo <> 'captura' then r ->> 'sucessao' end),
    (13, '903', case when e.tipo <> 'captura' then r ->> 'imoveis' end),
    (14, '884', case when e.tipo <> 'captura' then r ->> 'patrimonio' end),
    (15, '904', case when e.tipo <> 'captura' then r ->> 'intencao' end),
    (16, '927', case when e.tipo <> 'captura' and v_prof then r ->> 'profissao' end),
    (17, '905', case when e.tipo <> 'captura' then v_quando end),
    (18, '885', case when e.tipo = 'pesquisa' then case when v_mql then 'MQL' else 'nao MQL' end end),
    (19, '918', case when e.tipo = 'pesquisa_link' then case when v_mql then 'MQL' else 'nao MQL' end end),
    (20, '885', case when e.tipo = 'pesquisa_link' then case when v_mql then 'MQL' else 'nao MQL' end end)
  ) x(n, f, v)
  where coalesce(x.v, '') <> '';
  v_contato := jsonb_build_object('email', v_email);
  -- a pesquisa pelo link nunca troca o nome nem o telefone (o servidor tira os dois)
  if e.tipo <> 'pesquisa_link' then
    if v_nome <> '' then v_contato := v_contato || jsonb_build_object('firstName', v_primeiro, 'lastName', v_resto); end if;
    if v_tel <> '' then v_contato := v_contato || jsonb_build_object('phone', v_tel); end if;
  end if;
  v_contato := v_contato || jsonb_build_object('fieldValues', v_campos);

  if e.tipo = 'captura' then
    v_passos := '[{"o": "lista", "id": 603}, {"o": "tag", "id": 844}]'::jsonb;
  elsif e.tipo = 'pesquisa' then
    v_dest := case when v_prof then 612 when v_mql then 610 else 609 end;
    v_passos := jsonb_build_array(jsonb_build_object('o', 'lista', 'id', 603), jsonb_build_object('o', 'tag', 'id', 844),
      jsonb_build_object('o', 'tag', 'id', case when v_mql then 845 else 846 end), jsonb_build_object('o', 'lista', 'id', v_dest),
      jsonb_build_object('o', 'sai_resultado', 'fica', v_dest));
    if v_prof then v_passos := v_passos || jsonb_build_array(jsonb_build_object('o', 'tag', 'id', 871)); end if;
  elsif e.tipo = 'pesquisa_link' then
    v_passos := jsonb_build_array(jsonb_build_object('o', 'tag', 'id', 856), jsonb_build_object('o', 'tag', 'id', case when v_mql then 845 else 846 end),
      jsonb_build_object('o', 'tira_tag', 'id', case when v_mql then 846 else 845 end));
    if v_mql then v_passos := v_passos || jsonb_build_array(jsonb_build_object('o', 'lista', 'id', 610)); end if;
    if v_prof then v_passos := v_passos || jsonb_build_array(jsonb_build_object('o', 'tag', 'id', 871)); end if;
  end if;
  return jsonb_build_object('ok', true, 'tipo', e.tipo, 'contato', v_contato, 'passos', v_passos);
end $_$;


--
-- Name: recalcular(uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.recalcular(p_pessoa uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  r record;
begin
  with e as (
    select * from radar_crm.envios where pessoa = p_pessoa
  ), ent as (
    select * from e where tipo in ('inscricao', 'captura')
  ), pesq as (
    select * from e where tipo in ('pesquisa', 'pesquisa_link') and coalesce(dados ->> 'mql', '') in ('sim', 'nao')
    order by quando, recebido_em limit 1
  ), prim as (
    select * from (select * from ent union all select * from e where not exists (select 1 from ent)) x order by quando, recebido_em limit 1
  ), ult as (
    select * from (select * from ent union all select * from e where not exists (select 1 from ent)) x order by quando desc, recebido_em desc limit 1
  ),
  -- 071: o contrato do projeto da pessoa. A regua do MQL na inscricao (mql_na_inscricao: o campo das respostas e os
  -- valores que sao MQL; o campo tem de ser uma das chaves que o CRM guarda, radar_crm.respostas_limpas). Vale a primeira entrada
  -- da pessoa que tem o campo: valor na lista e MQL, outro valor e nao MQL. Projeto sem a regua (o PB): nada muda
  cfgp as (
    select pr.config as c from radar_crm.pessoas pp join radar.projetos pr on pr.id = pp.projeto where pp.id = p_pessoa
  ), rg as (
    select x.c -> 'mql_na_inscricao' ->> 'campo' as campo, array(select btrim(v) from jsonb_array_elements_text(x.c -> 'mql_na_inscricao' -> 'sim') v) as sim
    from cfgp x
    where jsonb_typeof(x.c -> 'mql_na_inscricao') = 'object' and coalesce(x.c -> 'mql_na_inscricao' ->> 'campo', '') <> ''
      and jsonb_typeof(x.c -> 'mql_na_inscricao' -> 'sim') = 'array'
  ), insc as (
    select case when btrim(ent.dados -> 'respostas' ->> rg.campo) = any (rg.sim) then 'sim' else 'nao' end as mql
    from ent cross join rg
    where coalesce(btrim(ent.dados -> 'respostas' ->> rg.campo), '') <> ''
    order by ent.quando, ent.recebido_em limit 1
  )
  select
    (select min(quando) from e) as primeiro_em,
    (select max(quando) from e) as ultimo_em,
    coalesce((select dados ->> 'nome' from e where coalesce(dados ->> 'nome', '') <> '' order by quando, recebido_em limit 1), '') as nome,
    coalesce((select dados ->> 'telefone' from e where coalesce(dados ->> 'telefone', '') <> '' order by quando, recebido_em limit 1), '') as telefone,
    coalesce((select pagina from prim), '') as pagina_primeira,
    coalesce((select pagina from ult), '') as pagina_ultima,
    coalesce((select dados -> 'origem' from prim), '{}'::jsonb) as origem_primeira,
    coalesce((select dados -> 'origem' from ult), '{}'::jsonb) as origem_ultima,
    (select count(*) from ent)::int as inscricoes,
    (select count(*) from e)::int as envios,
    case
      when exists (select 1 from pesq) then 'pesquisa'
      when exists (select 1 from e where tipo = 'pesquisa_parcial') then 'pesquisa_parcial'
      when exists (select 1 from e where tipo = 'captura') then 'captura'
      when exists (select 1 from e where tipo = 'inscricao') then 'inscricao'
      else '' end as parou_em,
    -- 071: sem pesquisa com MQL, a regua da inscricao (quando o contrato tem)
    coalesce((select dados ->> 'mql' from pesq), (select mql from insc), 'indefinido') as mql,
    coalesce((select dados -> 'respostas' from pesq),
             (select dados -> 'respostas' from e where dados -> 'respostas' <> '{}'::jsonb order by quando desc, recebido_em desc limit 1),
             '{}'::jsonb) as respostas,
    coalesce((select case when tipo = 'pesquisa_link' then 'link' else 'pagina' end from pesq), '') as pesquisa_via,
    (select quando from pesq) as pesquisa_em,
    case
      when exists (select 1 from e where active ->> 'situacao' in ('novo', 'existente')) then 'ok'
      when exists (select 1 from e where active ->> 'situacao' = 'erro') then 'erro'
      -- 071: o servidor do funil nao anota o Active (contrato radar_crm.active = false: quem grava no Active e a funcao do funil,
      -- e o Radar nao ve a resposta): a pessoa fica sem situacao, nunca "esperando"
      when (select coalesce(x.c -> 'crm' ->> 'active', '') = 'false' from cfgp x) then ''
      when exists (select 1 from e where tipo <> 'pesquisa_link' and via <> 'importado') then 'pendente'
      else '' end as active,
    (select case active ->> 'situacao' when 'novo' then true when 'existente' then false end
       from ent where active ->> 'situacao' in ('novo', 'existente') order by quando, recebido_em limit 1) as active_novo,
    coalesce((select active ->> 'id' from e where coalesce(active ->> 'id', '') <> '' order by quando desc, recebido_em desc limit 1), '') as active_id,
    case
      when exists (select 1 from e where planilha ->> 'situacao' = 'ok') then 'ok'
      when exists (select 1 from e where planilha ->> 'situacao' = 'erro') then 'erro'
      when exists (select 1 from e where planilha ->> 'situacao' = 'navegador') then 'navegador'
      else '' end as planilha,
    coalesce((select visitante from e where visitante <> '' order by quando, recebido_em limit 1), '') as visitante,
    coalesce((select bool_or(teste) from e), false) as teste_envio
  into r;
  update radar_crm.pessoas p set
    primeiro_em = coalesce(r.primeiro_em, p.primeiro_em), ultimo_em = coalesce(r.ultimo_em, p.ultimo_em),
    nome = r.nome, telefone = r.telefone, pagina_primeira = r.pagina_primeira, pagina_ultima = r.pagina_ultima,
    origem_primeira = r.origem_primeira, origem_ultima = r.origem_ultima,
    plataforma = radar.plataforma(r.origem_primeira ->> 'utm_source', r.origem_primeira ->> 'utm_medium',
                                  coalesce((r.origem_primeira ->> 'fbclid')::boolean, false), coalesce((r.origem_primeira ->> 'gclid')::boolean, false),
                                  r.origem_primeira ->> 'ad_id', r.origem_primeira ->> 'campaign_id',
                                  r.origem_primeira ->> 'utm_campaign', r.origem_primeira ->> 'utm_content'),
    inscricoes = r.inscricoes, envios = r.envios, parou_em = r.parou_em, mql = r.mql, respostas = r.respostas,
    pesquisa_via = r.pesquisa_via, pesquisa_em = r.pesquisa_em, active = r.active, active_novo = r.active_novo,
    active_id = r.active_id, planilha = r.planilha, visitante = r.visitante,
    teste = radar_crm.eh_teste(p.email) or r.teste_envio, atualizado_em = now()
  where p.id = p_pessoa;
end $$;


--
-- Name: reenviar_ciclo(); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenviar_ciclo() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_desde timestamptz;
  v_proj text;
begin
  if not exists (select 1 from radar.integracoes i where i.id = 'active' and i.ligada) then
    return jsonb_build_object('ok', false, 'erro', 'active_desligado');
  end if;
  select (p.valor #>> '{}')::timestamptz into v_desde from radar_crm.parametros p where p.chave = 'reenvio_automatico_desde';
  if v_desde is not null then
    for v_proj in
      select distinct e.projeto from radar_crm.envios e
      where (e.active ->> 'situacao') in ('erro', 'nao_encontrado') and e.quando >= v_desde and e.quando < now() - interval '5 minutes'
    loop
      insert into radar_crm.reenvios (envio, pessoa, projeto, automatico)
      select c.envio, c.pessoa, v_proj, true
      from radar_crm.reenvios_candidatos(v_proj) c
      where c.quando >= v_desde and c.quando < now() - interval '5 minutes'
        and not exists (select 1 from radar_crm.reenvios r where r.envio = c.envio)
      on conflict do nothing;
    end loop;
  end if;
  if not exists (select 1 from radar_crm.reenvios r where r.situacao = 'pendente' and r.proxima_em <= now()) then
    return jsonb_build_object('ok', true, 'feitos', 0);
  end if;
  return radar_crm.reenviar_processar(clock_timestamp() + interval '45 seconds');
end $$;


--
-- Name: reenviar_marcar(text, uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenviar_marcar(p_projeto text, p_quem uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
declare
  v_novos int;
  v_ja int;
begin
  update radar_crm.reenvios r set proxima_em = now(), tentativas = 0, automatico = false, pedido_por = p_quem, pedido_em = now()
  where r.projeto = p_projeto and r.situacao = 'pendente';
  get diagnostics v_ja = row_count;
  insert into radar_crm.reenvios (envio, pessoa, projeto, automatico, pedido_por)
  select c.envio, c.pessoa, p_projeto, false, p_quem
  from radar_crm.reenvios_candidatos(p_projeto) c
  where not exists (select 1 from radar_crm.reenvios r where r.envio = c.envio and r.situacao = 'pendente')
  on conflict do nothing;
  get diagnostics v_novos = row_count;
  return jsonb_build_object('ok', true, 'na_fila', v_novos + v_ja);
end $$;


--
-- Name: reenviar_processar(timestamp with time zone); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenviar_processar(p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $_$
declare
  v_ate timestamptz := coalesce(p_ate, clock_timestamp() + interval '45 seconds');
  q record;
  v_res jsonb;
  v_sit text;
  v_http int;
  v_feitos int := 0;
  v_chegaram int := 0;
  v_parou text;
begin
  if not exists (select 1 from radar.integracoes i where i.id = 'active' and i.ligada) then
    return jsonb_build_object('ok', false, 'erro', 'active_desligado');
  end if;
  for q in
    select r.id, r.envio, r.pessoa, r.projeto, r.tentativas, r.automatico, r.pedido_por, e.tipo, e.quando, e.active as antes
    from radar_crm.reenvios r join radar_crm.envios e on e.id = r.envio
    where r.situacao = 'pendente' and r.proxima_em <= now()
    order by e.quando, r.id
    limit 40
    for update of r skip locked
  loop
    if clock_timestamp() > v_ate then v_parou := 'prazo'; exit; end if;
    v_res := radar_crm.reenviar_um(q.envio, v_ate, 8000);
    v_sit := v_res ->> 'situacao';
    v_http := case when coalesce(v_res ->> 'http', '') ~ '^\d+$' then (v_res ->> 'http')::int end;
    if v_sit = 'prazo' then
      -- o minuto acabou no meio: o proximo refaz do comeco; nao conta como tentativa
      update radar_crm.reenvios set passos = v_res -> 'passos' where id = q.id;
      v_parou := 'prazo';
      exit;
    end if;
    if v_sit = 'erro' and v_http = 429 then
      -- o Active pediu calma: para e volta em 2 minutos; nao conta como tentativa
      update radar_crm.reenvios set proxima_em = now() + interval '2 minutes', ultimo_http = 429, passos = v_res -> 'passos' where id = q.id;
      v_parou := 'active_pediu_calma';
      exit;
    end if;
    v_feitos := v_feitos + 1;
    if v_sit in ('novo', 'existente', 'nao_encontrado') then
      if v_sit <> 'nao_encontrado' then v_chegaram := v_chegaram + 1; end if;
      -- 200 porque um envio seguinte da mesma pessoa ja criou o contato: na hora deste, ela era nova
      if v_sit = 'existente' and q.tipo in ('inscricao', 'captura') and exists (
           select 1 from radar_crm.envios x where x.pessoa = q.pessoa and x.id <> q.envio and x.active ->> 'situacao' = 'novo' and x.quando > q.quando) then
        v_sit := 'novo';
      end if;
      update radar_crm.envios set active = jsonb_strip_nulls(jsonb_build_object('situacao', v_sit, 'http', v_http, 'id', v_res ->> 'id',
               'reenvio', jsonb_build_object('em', now(), 'tentativa', q.tentativas + 1, 'automatico', q.automatico,
                                             'antes', q.antes ->> 'situacao',
                                             'http_antes', case when coalesce(q.antes ->> 'http', '') ~ '^\d+$' then (q.antes ->> 'http')::int end))),
             atualizado_em = now()
       where id = q.envio;
      update radar_crm.reenvios set situacao = 'ok', resultado = v_sit, tentativas = tentativas + 1, ultimo_http = v_http,
             passos = v_res -> 'passos', feito_em = now()
       where id = q.id;
      -- a inscricao chegou: a pesquisa pelo link da mesma pessoa que nao tinha achado o contato vai em seguida
      if q.tipo in ('inscricao', 'captura') and v_sit in ('novo', 'existente') then
        insert into radar_crm.reenvios (envio, pessoa, projeto, automatico, pedido_por)
        select c.envio, c.pessoa, q.projeto, q.automatico, q.pedido_por
        from radar_crm.reenvios_candidatos(q.projeto, q.pessoa) c
        where c.tipo = 'pesquisa_link' and not exists (select 1 from radar_crm.reenvios r where r.envio = c.envio and r.situacao = 'pendente')
        on conflict do nothing;
      end if;
    else
      update radar_crm.reenvios set tentativas = tentativas + 1, ultimo_http = v_http, passos = v_res -> 'passos',
             situacao = case when tentativas + 1 >= 5 then 'desistiu' else 'pendente' end,
             proxima_em = now() + (array[interval '5 minutes', interval '15 minutes', interval '45 minutes', interval '2 hours'])[least(tentativas + 1, 4)],
             feito_em = case when tentativas + 1 >= 5 then now() end
       where id = q.id;
    end if;
    perform radar_crm.recalcular(q.pessoa);
  end loop;
  return jsonb_strip_nulls(jsonb_build_object('ok', true, 'feitos', v_feitos, 'chegaram', v_chegaram, 'parou', v_parou,
                                              'faltam', (select count(*) from radar_crm.reenvios where situacao = 'pendente')));
end $_$;


--
-- Name: reenviar_um(uuid, timestamp with time zone, integer); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenviar_um(p_envio uuid, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_teto_ms integer DEFAULT 8000) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $_$
declare
  v_plano jsonb := radar_crm.plano_active(p_envio);
  v_tipo text := v_plano ->> 'tipo';
  v_ate timestamptz := coalesce(p_ate, clock_timestamp() + interval '40 seconds');
  v_r jsonb;
  v_sync int;
  v_id text;
  v_sit text;
  v_p jsonb;
  v_x jsonb;
  v_vals jsonb;
  v_passos jsonb := '[]'::jsonb;
begin
  if not coalesce((v_plano ->> 'ok')::boolean, false) then
    return jsonb_build_object('situacao', 'erro', 'erro', v_plano ->> 'erro', 'passos', v_passos);
  end if;

  if v_tipo = 'pesquisa_link' then
    -- acha o contato pelo e-mail da inscricao; o link nunca cria contato
    v_r := radar_crm.reenvio_chamar('GET', 'contacts?email=' || radar.url_codificar(v_plano -> 'contato' ->> 'email'), null, 'achar o contato', p_teto_ms);
    v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
    if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
    v_id := v_r -> 'corpo' -> 'contacts' -> 0 ->> 'id';
    if v_id is null then return jsonb_build_object('situacao', 'nao_encontrado', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
    if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
    -- vale a primeira resposta: quem ja concluiu uma pesquisa (918, ou 885 com 904) so ganha a 856
    v_r := radar_crm.reenvio_chamar('GET', 'contacts/' || v_id || '/fieldValues', null, 'ler os campos', p_teto_ms);
    v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
    if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
    select coalesce(jsonb_object_agg(x ->> 'field', btrim(coalesce(x ->> 'value', ''))), '{}'::jsonb) into v_vals
    from jsonb_array_elements(coalesce(v_r -> 'corpo' -> 'fieldValues', '[]'::jsonb)) x
    where x ->> 'field' is not null;
    if coalesce(v_vals ->> '918', '') <> '' or (coalesce(v_vals ->> '885', '') <> '' and coalesce(v_vals ->> '904', '') <> '') then
      if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
      v_r := radar_crm.reenvio_chamar('POST', 'contactTags', jsonb_build_object('contactTag', jsonb_build_object('contact', v_id, 'tag', 856)),
                                'tag 856 (ja tinha respondido)', p_teto_ms);
      v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
      if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
      return jsonb_build_object('situacao', 'existente', 'http', 200, 'id', v_id, 'ja_respondida', true, 'passos', v_passos);
    end if;
    if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
  end if;

  -- o contato primeiro; sem ele, nada mais (como o servidor)
  v_r := radar_crm.reenvio_chamar('POST', 'contact/sync', jsonb_build_object('contact', v_plano -> 'contato'), 'contato', p_teto_ms);
  v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
  v_sync := (v_r ->> 'http')::int;
  if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', v_sync, 'passos', v_passos); end if;
  if v_tipo = 'pesquisa_link' then
    v_sit := 'existente';
  else
    v_id := v_r -> 'corpo' -> 'contact' ->> 'id';
    if v_id is null then return jsonb_build_object('situacao', 'erro', 'http', v_sync, 'erro', 'sem_id', 'passos', v_passos); end if;
    v_sit := case when v_sync = 201 then 'novo' else 'existente' end;
  end if;

  for v_p in select * from jsonb_array_elements(coalesce(v_plano -> 'passos', '[]'::jsonb)) loop
    if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
    if v_p ->> 'o' = 'lista' then
      v_r := radar_crm.reenvio_chamar('POST', 'contactLists', jsonb_build_object('contactList',
               jsonb_build_object('list', (v_p ->> 'id')::int, 'contact', v_id, 'status', 1)), 'lista ' || (v_p ->> 'id'), p_teto_ms);
    elsif v_p ->> 'o' = 'tag' then
      v_r := radar_crm.reenvio_chamar('POST', 'contactTags', jsonb_build_object('contactTag',
               jsonb_build_object('contact', v_id, 'tag', (v_p ->> 'id')::int)), 'tag ' || (v_p ->> 'id'), p_teto_ms);
    elsif v_p ->> 'o' = 'sai_resultado' then
      -- refez a pesquisa com outro resultado: sai das outras listas de resultado (610, 611 e 612), menos a de agora
      v_r := radar_crm.reenvio_chamar('GET', 'contacts/' || v_id || '/contactLists', null, 'ler as listas', p_teto_ms);
      v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
      if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
      for v_x in select * from jsonb_array_elements(coalesce(v_r -> 'corpo' -> 'contactLists', '[]'::jsonb)) loop
        if coalesce(v_x ->> 'list', '') ~ '^\d+$' and (v_x ->> 'list')::int in (610, 611, 612) and (v_x ->> 'list')::int <> (v_p ->> 'fica')::int
           and coalesce(v_x ->> 'status', '') = '1' then
          if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
          v_r := radar_crm.reenvio_chamar('POST', 'contactLists', jsonb_build_object('contactList',
                   jsonb_build_object('list', (v_x ->> 'list')::int, 'contact', v_id, 'status', 2)), 'sai da lista ' || (v_x ->> 'list'), p_teto_ms);
          v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
          if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
        end if;
      end loop;
      continue;
    elsif v_p ->> 'o' = 'tira_tag' then
      -- fica so uma das duas (845 MQL ou 846 nao MQL)
      v_r := radar_crm.reenvio_chamar('GET', 'contacts/' || v_id || '/contactTags', null, 'ler as tags', p_teto_ms);
      v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
      if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
      for v_x in select * from jsonb_array_elements(coalesce(v_r -> 'corpo' -> 'contactTags', '[]'::jsonb)) loop
        if coalesce(v_x ->> 'tag', '') ~ '^\d+$' and (v_x ->> 'tag')::int = (v_p ->> 'id')::int and coalesce(v_x ->> 'id', '') ~ '^\d+$' then
          if clock_timestamp() > v_ate then return jsonb_build_object('situacao', 'prazo', 'passos', v_passos); end if;
          v_r := radar_crm.reenvio_chamar('DELETE', 'contactTags/' || (v_x ->> 'id'), null, 'tira a tag ' || (v_p ->> 'id'), p_teto_ms);
          v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
          if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
        end if;
      end loop;
      continue;
    else
      continue;
    end if;
    v_passos := v_passos || jsonb_build_array(v_r - 'corpo');
    if not (v_r ->> 'ok')::boolean then return jsonb_build_object('situacao', 'erro', 'http', (v_r ->> 'http')::int, 'passos', v_passos); end if;
  end loop;
  return jsonb_build_object('situacao', v_sit, 'http', v_sync, 'id', v_id, 'passos', v_passos);
end $_$;


--
-- Name: reenvio_chamar(text, text, jsonb, text, integer); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenvio_chamar(p_metodo text, p_caminho text, p_corpo jsonb, p_passo text, p_teto_ms integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_r jsonb := radar.active_enviar(p_metodo, p_caminho, p_corpo, p_teto_ms);
  v_http int := coalesce((v_r ->> 'status')::int, 0);
begin
  return jsonb_build_object('passo', p_passo, 'http', v_http, 'corpo', v_r -> 'corpo',
    'ok', v_http between 200 and 299
          or (v_http = 422 and p_metodo = 'POST' and p_caminho in ('contactTags', 'contactLists'))
          or (v_http = 404 and p_metodo = 'DELETE'));
end $$;


--
-- Name: reenvios_candidatos(text, uuid); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.reenvios_candidatos(p_projeto text, p_pessoa uuid DEFAULT NULL::uuid) RETURNS TABLE(envio uuid, pessoa uuid, tipo text, quando timestamp with time zone, http integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $_$
  select e.id, e.pessoa, e.tipo, e.quando, case when coalesce(e.active ->> 'http', '') ~ '^\d+$' then (e.active ->> 'http')::int end
  from radar_crm.envios e join radar_crm.pessoas p on p.id = e.pessoa
  where e.projeto = p_projeto and (p_pessoa is null or e.pessoa = p_pessoa)
    and (e.active ->> 'situacao') in ('erro', 'nao_encontrado')
    and not e.teste and not p.teste and e.via <> 'importado'
    and (e.active ->> 'situacao' = 'erro'
         or (e.tipo = 'pesquisa_link' and exists (
               select 1 from radar_crm.envios x where x.pessoa = e.pessoa and x.tipo <> 'pesquisa_link'
                 and (x.active ->> 'situacao' = 'erro'
                      or (x.active ->> 'situacao' in ('novo', 'existente')
                          and (not (e.active ? 'reenvio')
                               or (x.active -> 'reenvio' ->> 'em')::timestamptz > (e.active -> 'reenvio' ->> 'em')::timestamptz))))))
    and (e.tipo in ('inscricao', 'captura')
         or (e.tipo in ('pesquisa', 'pesquisa_link') and not exists (
               select 1 from radar_crm.envios x where x.pessoa = e.pessoa and x.tipo in ('pesquisa', 'pesquisa_link')
                 and (x.quando, x.id::text) > (e.quando, e.id::text)))
         or (e.tipo = 'pesquisa_parcial' and not exists (
               select 1 from radar_crm.envios x where x.pessoa = e.pessoa and x.tipo in ('pesquisa_parcial', 'pesquisa', 'pesquisa_link')
                 and (x.quando, x.id::text) > (e.quando, e.id::text))))
$_$;


--
-- Name: respostas_limpas(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.respostas_limpas(j jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  select jsonb_strip_nulls(jsonb_build_object(
    'sucessao', nullif(left(btrim(coalesce(j ->> 'sucessao', '')), 300), ''),
    'imoveis', nullif(left(btrim(coalesce(j ->> 'imoveis', '')), 120), ''),
    'patrimonio', nullif(left(btrim(coalesce(j ->> 'patrimonio', '')), 120), ''),
    'intencao', nullif(left(btrim(coalesce(j ->> 'intencao', '')), 200), ''),
    'profissao', nullif(left(btrim(coalesce(j ->> 'profissao', '')), 120), ''),
    -- 074: a pesquisa da Black
    'atuacao', nullif(left(btrim(coalesce(j ->> 'atuacao', '')), 120), ''),
    'faixa_etaria', nullif(left(btrim(coalesce(j ->> 'faixa_etaria', '')), 60), ''),
    'renda_mensal', nullif(left(btrim(coalesce(j ->> 'renda_mensal', '')), 60), ''),
    'aluno', nullif(left(btrim(coalesce(j ->> 'aluno', '')), 20), ''),
    'aluno_programa', nullif(left(btrim(coalesce(j ->> 'aluno_programa', '')), 60), ''),
    'holding', nullif(left(btrim(coalesce(j ->> 'holding', '')), 120), ''),
    'nivel', nullif(left(btrim(coalesce(j ->> 'nivel', '')), 40), '')))
$$;


--
-- Name: sendflow_chave_criar(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.sendflow_chave_criar(p_projeto text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  v_chave text := 'sfw_' || substr(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 1, 48);
begin
  if not exists (select 1 from radar.projetos where id = p_projeto) then raise exception 'projeto'; end if;
  insert into radar_crm.sendflow_chaves (projeto, prefixo, hash)
  values (p_projeto, left(v_chave, 10), encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'));
  return v_chave;
end $$;


--
-- Name: sendflow_guardar(text, bigint, jsonb, text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.sendflow_guardar(p_projeto text, p_log bigint, c jsonb, p_origem text DEFAULT 'webhook'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  d jsonb := case when jsonb_typeof(c -> 'data') = 'object' then c -> 'data' else c end;
  v_evento text := lower(radar_crm.sf_texto(c, array['event', 'type', 'evento']));
  v_acao text;
  v_release text;
  v_campanha text := '';
  v_jid text;
  v_grupo text;
  v_id text;
  v_hora timestamptz;
  v_do_payload boolean;
  v_tel text;
  v_chave text;
  v_ass text;
  v_novas int := 0;
  v_repetidas int := 0;
  v_ruins int := 0;
  -- 071: a campanha diz o projeto (um segredo so serve para todos); sem campanha conhecida, o do segredo
  v_projeto text := p_projeto;
  v_dono text;
begin
  v_acao := case
    when v_evento like '%members.added%' or v_evento like '%member.added%' then 'entrou'
    when v_evento like '%members.removed%' or v_evento like '%member.removed%' or v_evento like '%left%' then 'saiu'
    -- entrada com aprovacao (release.join-request.created): o pedido ainda nao e membro; fica como "pedido" para
    -- conferir com o payload real se a aprovacao depois gera um members.added (e so ele conta como entrou)
    when v_evento like '%join-request%' or v_evento like '%join_request%' then 'pedido'
    else null end;
  if v_acao is null then return jsonb_build_object('resultado', 'ignorado', 'linhas', 0); end if;

  v_release := coalesce(nullif(radar_crm.sf_texto(d, array['releaseId', 'release_id', 'campaignId']), ''),
                        nullif(radar_crm.sf_texto(c, array['releaseId', 'release_id', 'campaignId']), ''),
                        radar_crm.sf_texto(d -> 'release', array['id']), '');
  v_jid := coalesce(nullif(radar_crm.sf_texto(d, array['groupJid', 'groupId', 'jid', 'group_jid']), ''), radar_crm.sf_texto(d -> 'group', array['jid', 'id']), '');
  v_grupo := coalesce(nullif(radar_crm.sf_texto(d, array['groupName', 'group_name', 'grupo']), ''), radar_crm.sf_texto(d -> 'group', array['name', 'subject']), '');
  if v_release = '' and v_jid <> '' then select g.release into v_release from radar_crm.sendflow_grupos g where g.jid = v_jid; end if;
  v_release := coalesce(v_release, '');
  if v_release <> '' then select s.nome, s.projeto into v_campanha, v_dono from radar_crm.sendflow_campanhas s where s.release = v_release; end if;
  v_projeto := coalesce(v_dono, p_projeto);
  v_campanha := coalesce(v_campanha, '');

  v_id := coalesce(nullif(radar_crm.sf_texto(c, array['id', 'eventId', 'event_id', 'webhookId']), ''), radar_crm.sf_texto(d, array['eventId', 'event_id']), '');
  v_hora := radar_crm.sf_hora(coalesce(nullif(radar_crm.sf_texto(d, array['date', 'createdAt', 'created_at', 'timestamp', 'time', 'eventDate']), ''),
                                 radar_crm.sf_texto(c, array['date', 'createdAt', 'created_at', 'timestamp', 'time', 'eventDate'])));
  v_do_payload := v_hora is not null;
  v_hora := coalesce(v_hora, now());

  for v_tel in select radar_crm.sf_telefones(d) loop
    v_chave := radar_crm.telefone_chave(v_tel);
    if v_chave = '' then v_ruins := v_ruins + 1; continue; end if;
    -- a idempotencia: com o id do evento, ele; com a hora do payload, a hora; sem nenhum dos dois (a hora e a da
    -- chegada), a mesma pessoa, acao e grupo dentro de 10 minutos e o mesmo evento repetido pelo SendFlow
    v_ass := encode(sha256(convert_to(concat_ws('|', v_projeto, v_acao, v_chave, coalesce(nullif(v_jid, ''), v_grupo),
               case when v_id <> '' then 'id:' || v_id
                    when v_do_payload then 'h:' || extract(epoch from v_hora)::bigint::text
                    else 'c:' || (extract(epoch from v_hora)::bigint / 600)::text end), 'UTF8')), 'hex');
    perform pg_advisory_xact_lock(hashtext(v_projeto || v_acao || v_chave));
    if exists (select 1 from radar_crm.grupo_eventos e where e.assinatura = v_ass)
       or (v_id = '' and not v_do_payload and exists (
             select 1 from radar_crm.grupo_eventos e where e.projeto = v_projeto and e.telefone_chave = v_chave and e.acao = v_acao
               and e.jid = v_jid and e.grupo = v_grupo and not e.quando_do_payload and e.quando > v_hora - interval '10 minutes')) then
      v_repetidas := v_repetidas + 1;
      continue;
    end if;
    insert into radar_crm.grupo_eventos (projeto, telefone_chave, telefone, acao, release, campanha, jid, grupo, quando, quando_do_payload, origem, assinatura, log)
    values (v_projeto, v_chave, left(regexp_replace(split_part(v_tel, '@', 1), '[^0-9]', '', 'g'), 20), v_acao, left(v_release, 60), left(v_campanha, 120),
            left(v_jid, 80), left(v_grupo, 160), v_hora, v_do_payload, p_origem, v_ass, p_log)
    on conflict (assinatura) do nothing;
    if found then v_novas := v_novas + 1; else v_repetidas := v_repetidas + 1; end if;
  end loop;

  return jsonb_build_object(
    'resultado', case when v_novas > 0 then 'gravado' when v_repetidas > 0 then 'repetido' else 'sem_telefone' end,
    'acao', v_acao, 'linhas', v_novas, 'repetidas', v_repetidas, 'telefones_ruins', v_ruins,
    'hora_do_payload', v_do_payload, 'campanha', v_campanha <> '', 'projeto', v_projeto);
end $$;


--
-- Name: sf_hora(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.sf_hora(v text) RETURNS timestamp with time zone
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
declare n numeric; t timestamptz;
begin
  if coalesce(btrim(v), '') = '' then return null; end if;
  if v ~ '^[0-9]{9,13}(\.[0-9]+)?$' then
    n := v::numeric;
    if n > 100000000000 then n := n / 1000; end if;
    t := to_timestamp(n);
  else
    begin t := v::timestamptz; exception when others then return null; end;
  end if;
  -- hora absurda (antes de 2024 ou mais de um dia no futuro) nao vale: fica a da chegada
  if t < '2024-01-01'::timestamptz or t > now() + interval '1 day' then return null; end if;
  return t;
end $_$;


--
-- Name: sf_telefones(jsonb); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.sf_telefones(d jsonb) RETURNS SETOF text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select distinct x from (
    select d ->> k as x from unnest(array['number', 'phone', 'telefone', 'participant']) k where jsonb_typeof(d -> k) in ('string', 'number')
    union all
    select case when jsonb_typeof(e) = 'object' then coalesce(e ->> 'number', e ->> 'phone', e ->> 'id', e ->> 'jid') else e #>> '{}' end
    from unnest(array['number', 'numbers', 'participants', 'members']) k
    cross join lateral jsonb_array_elements(case when jsonb_typeof(d -> k) = 'array' then d -> k else '[]'::jsonb end) e
  ) t where coalesce(btrim(x), '') <> ''
$$;


--
-- Name: sf_texto(jsonb, text[]); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.sf_texto(j jsonb, chaves text[]) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select coalesce((select btrim(j ->> k) from unnest(chaves) with ordinality u (k, i)
                   where jsonb_typeof(j -> k) in ('string', 'number') and btrim(j ->> k) <> '' order by i limit 1), '')
$$;


--
-- Name: telefone_chave(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.telefone_chave(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  with d as (select regexp_replace(split_part(coalesce(t, ''), '@', 1), '[^0-9]', '', 'g') as n),
  s as (select case when length(n) in (12, 13) and left(n, 2) = '55' then substr(n, 3) else n end as n from d)
  select case when n ~ '^[1-9][1-9]9[0-9]{8}$' or n ~ '^[1-9][1-9][2-9][0-9]{7}$' then left(n, 2) || right(n, 8) else '' end from s
$_$;


--
-- Name: telefone_limpo(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.telefone_limpo(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  with d as (select regexp_replace(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '^0+', '') as n),
       l as (select case when length(n) between 12 and 13 and left(n, 2) = '55' then substr(n, 3) else n end as n from d)
  select case when length(n) between 10 and 11 then '55' || n else '' end from l
$$;


--
-- Name: telefone_situacao(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.telefone_situacao(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  select case
    when coalesce(t, '') = '' then 'vazio'
    when t !~ '^55[0-9]{10,11}$' then 'invalido'
    when radar.uf_do_ddd(substr(t, 3, 2)) is null then 'ddd'
    -- o mesmo digito do comeco ao fim (99999-9999, 0000-0000): numero de mentira
    when substr(t, 5) ~ '^([0-9])\1+$' then 'invalido'
    when length(t) = 13 and substr(t, 5, 1) = '9' then 'ok'
    -- 8 digitos comecando por 6 a 9: celular de antes do nono digito
    when length(t) = 12 and substr(t, 5, 1) between '6' and '9' then 'sem_9'
    when length(t) = 12 then 'fixo'
    -- 11 digitos que nao comecam por 9: nao existe celular assim (um digito a mais, quase sempre)
    else 'invalido'
  end
$_$;


--
-- Name: telefones_repetidos(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.telefones_repetidos(p_projeto text) RETURNS TABLE(telefone text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm'
    AS $$
  select p.telefone from radar_crm.pessoas p
  where p.projeto = p_projeto and not p.teste and p.telefone <> ''
  group by p.telefone having count(*) > 1
$$;


--
-- Name: whatsapp(text); Type: FUNCTION; Schema: radar_crm; Owner: -
--

CREATE FUNCTION radar_crm.whatsapp(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case radar_crm.telefone_situacao(t)
    when 'ok' then t
    when 'sem_9' then substr(t, 1, 4) || '9' || substr(t, 5)
    else '' end
$$;


--
-- Name: active_chamar(text, text, text, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.active_chamar(p_caminho text, p_url text DEFAULT NULL::text, p_chave text DEFAULT NULL::text, p_teto_ms integer DEFAULT 15000) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_url text := coalesce(p_url, (select i.config ->> 'url' from radar.integracoes i where i.id = 'active'));
  v_chave text := p_chave;
  v_status int;
  v_corpo text;
begin
  if v_chave is null then
    select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'radar_active_chave';
  end if;
  if coalesce(v_url, '') = '' or coalesce(v_chave, '') = '' then raise exception 'active_sem_chave'; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', least(greatest(coalesce(p_teto_ms, 15000), 1000), 30000)::text);
  select r.status, r.content into v_status, v_corpo
  from extensions.http(('GET', rtrim(v_url, '/') || '/api/3/' || p_caminho,
                        array[extensions.http_header('Api-Token', v_chave), extensions.http_header('Accept', 'application/json')],
                        null, null)::extensions.http_request) r;
  if v_status in (401, 403) then raise exception 'active_chave_recusada'; end if;
  if v_status = 429 then raise exception 'active_muitas_chamadas'; end if;
  if v_status is null or v_status >= 400 then raise exception 'active_respondeu %', coalesce(v_status, 0); end if;
  return v_corpo::jsonb;
end $$;


--
-- Name: active_enviar(text, text, jsonb, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.active_enviar(p_metodo text, p_caminho text, p_corpo jsonb DEFAULT NULL::jsonb, p_teto_ms integer DEFAULT 8000) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  v_metodo text := upper(coalesce(p_metodo, ''));
  v_url text;
  v_chave text;
  v_status int;
  v_corpo text;
begin
  if v_metodo not in ('GET', 'POST', 'DELETE') then raise exception 'metodo_invalido'; end if;
  if coalesce(p_caminho, '') !~ '^(contact/sync|contactLists|contactTags|contactTags/[0-9]+|contacts\?email=[A-Za-z0-9._~%-]+|contacts/[0-9]+/(contactLists|contactTags|fieldValues))$' then
    raise exception 'caminho_fora_da_lista';
  end if;
  select i.config ->> 'url' into v_url from radar.integracoes i where i.id = 'active' and i.ligada;
  select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'radar_active_chave';
  if coalesce(v_url, '') = '' or coalesce(v_chave, '') = '' then raise exception 'active_sem_chave'; end if;
  -- um terco de segundo antes de cada chamada: o Radar fica abaixo de 3 por segundo
  perform pg_sleep(0.3);
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', least(greatest(coalesce(p_teto_ms, 8000), 1000), 30000)::text);
  begin
    select r.status, r.content into v_status, v_corpo
    from extensions.http((v_metodo::extensions.http_method, rtrim(v_url, '/') || '/api/3/' || p_caminho,
                          array[extensions.http_header('Api-Token', v_chave), extensions.http_header('Accept', 'application/json')],
                          case when p_corpo is null then null else 'application/json' end,
                          case when p_corpo is null then null else p_corpo::text end)::extensions.http_request) r;
  exception when others then
    return jsonb_build_object('status', 0, 'erro', left(sqlerrm, 160));
  end;
  return jsonb_build_object('status', coalesce(v_status, 0), 'corpo', radar.json_ou_nulo(v_corpo));
end $_$;


--
-- Name: active_sincronizar(timestamp with time zone); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.active_sincronizar(p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_tipos constant text[] := array['listas', 'tags', 'campos', 'automacoes'];
  v_rotas constant text[] := array['lists', 'tags', 'fields', 'automations'];
  v_nomes constant text[] := array['name', 'tag', 'title', 'name'];
  v_ate timestamptz := coalesce(p_ate, clock_timestamp() + interval '100 seconds');
  v_teto int := case when p_ate is null then 15000 else 3500 end;
  v_and jsonb;
  v_ini timestamptz;
  v_i int;
  v_off int;
  v_pag jsonb;
  v_itens jsonb;
  v_total int;
  v_cont jsonb;
begin
  select i.andamento into v_and from radar.integracoes i where i.id = 'active' and i.ligada;
  if not found then return jsonb_build_object('ok', false, 'erro', 'active_desligado'); end if;
  -- a volta pela metade continua de onde parou; sem ela, comeca uma nova
  if v_and is not null and (v_and ->> 'i')::int between 1 and 4 then
    v_ini := (v_and ->> 'ini')::timestamptz; v_i := (v_and ->> 'i')::int; v_off := greatest((v_and ->> 'off')::int, 0);
  else
    v_ini := clock_timestamp(); v_i := 1; v_off := 0;
  end if;
  begin
    while v_i <= 4 loop
      v_pag := radar.active_chamar(v_rotas[v_i] || '?limit=100&offset=' || v_off, null, null, v_teto);
      v_itens := case when jsonb_typeof(v_pag -> v_rotas[v_i]) = 'array' then v_pag -> v_rotas[v_i] else '[]'::jsonb end;
      v_total := coalesce(radar.inteiro(v_pag -> 'meta' ->> 'total', 0)::int, 0);
      insert into radar.active_catalogo as c (tipo, id, nome, extra, visto_em)
      select v_tipos[v_i], x ->> 'id', left(coalesce(x ->> v_nomes[v_i], ''), 300),
             case v_tipos[v_i] when 'campos' then jsonb_build_object('tipo', x ->> 'type', 'perstag', x ->> 'perstag')
                               when 'automacoes' then jsonb_build_object('ativa', x ->> 'status' = '1')
                               when 'listas' then jsonb_build_object('stringid', x ->> 'stringid')
                               else '{}'::jsonb end,
             v_ini
      from jsonb_array_elements(v_itens) x
      where coalesce(x ->> 'id', '') <> ''
      on conflict (tipo, id) do update set nome = excluded.nome, extra = excluded.extra, visto_em = greatest(c.visto_em, excluded.visto_em);
      v_off := v_off + 100;
      if v_off >= v_total or v_off >= 5000 or jsonb_array_length(v_itens) = 0 then
        v_i := v_i + 1; v_off := 0;
      end if;
      exit when v_i > 4;
      -- o prazo: guarda onde parou e volta (a proxima chamada continua daqui)
      if clock_timestamp() >= v_ate then
        update radar.integracoes set andamento = jsonb_build_object('ini', v_ini, 'i', v_i, 'off', v_off) where id = 'active';
        return jsonb_build_object('ok', true, 'continua', true,
                                  'andamento', jsonb_build_object('tipo', v_tipos[v_i], 'feitos', v_i - 1, 'de', 4));
      end if;
      perform pg_sleep(0.25);
    end loop;
    select jsonb_object_agg(t.tipo, (select count(*) from radar.active_catalogo c where c.tipo = t.tipo and c.visto_em >= v_ini))
      into v_cont from unnest(v_tipos) t(tipo);
    delete from radar.active_catalogo where visto_em < v_ini;
    update radar.integracoes set sincronizada_em = now(), contagens = v_cont, erro = null, erro_em = null, andamento = null
    where id = 'active';
    return jsonb_build_object('ok', true, 'contagens', v_cont);
  exception when others then
    update radar.integracoes set erro = left(sqlerrm, 200), erro_em = now(), andamento = null where id = 'active';
    return jsonb_build_object('ok', false, 'erro', left(sqlerrm, 200));
  end;
end $$;


--
-- Name: alertas_de(text[], jsonb, boolean); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.alertas_de(p_lista text[], f jsonb, p_sistema boolean) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('alertas',
    coalesce((select jsonb_agg(a.value)
              from radar.projetos p
              cross join lateral jsonb_array_elements(radar.alertas_do_projeto(f || jsonb_build_object('projeto', p.id)) -> 'alertas') a
              where p.id = any (p_lista) and coalesce(p.config ->> 'demonstracao', '') <> 'true'), '[]'::jsonb)
    || case when p_sistema then radar.alertas_sistema() else '[]'::jsonb end)
$$;


--
-- Name: alertas_do_projeto(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.alertas_do_projeto(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_set(a, '{alertas}', coalesce(a -> 'alertas', '[]'::jsonb) || radar.alertas_guardiao(f))
  from (select radar.api_alertas(f) as a) x
$$;


--
-- Name: alertas_guardiao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.alertas_guardiao(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'projeto', f ->> 'projeto', 'tipo', 'velocidade_publicacao', 'pagina', r ->> 'pagina',
           'gravidade', case when ((r ->> 'piorou_em') in ('lcp', 'lcp_inp') and (r -> 'depois' ->> 'lcp')::numeric > 2500)
                               or ((r ->> 'piorou_em') in ('inp', 'lcp_inp') and (r -> 'depois' ->> 'inp')::numeric > 200) then 'alto' else 'medio' end,
           'agora', (r -> 'depois') || jsonb_build_object('dispositivo', r ->> 'dispositivo', 'horas', r -> 'horas_depois'),
           'antes', r -> 'antes',
           'publicacao', jsonb_build_object('quando', r -> 'inicio', 'publicacoes', r -> 'publicacoes', 'resumo', r ->> 'resumo'),
           'piorou_em', r ->> 'piorou_em')), '[]'::jsonb)
  from jsonb_array_elements(radar.api_guardiao(f) -> 'rodadas') r
  where (r ->> 'ultima')::boolean and r ->> 'veredito' = 'piorou' and (r ->> 'fim')::bigint >= radar.ms(now() - interval '7 days')
$$;


--
-- Name: alertas_sistema(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.alertas_sistema() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce((select jsonb_agg(a) from (
    select jsonb_build_object('projeto', null, 'tipo', 'dominio', 'pagina', null, 'gravidade', 'medio',
             'agora', jsonb_build_object('dominio', detalhe, 'pacotes', sum(vezes))) as a
    from radar.recusas where motivo = 'dominio' and dia >= radar.hoje() - 1 and detalhe not in ('', '(sem origem)')
    group by detalhe having sum(vezes) >= 20
    union all
    select jsonb_build_object('projeto', null, 'tipo', 'coleta', 'pagina', null, 'gravidade', 'alto',
             'agora', jsonb_build_object('falhas', count(*), 'ultima', max(mensagem)))
    from radar.falhas where quando >= now() - interval '24 hours' having count(*) >= 5
    union all
    select jsonb_build_object('projeto', null, 'tipo', 'espaco', 'pagina', null, 'gravidade', 'alto', 'agora', jsonb_build_object('estado', valor))
    from radar.config where chave = 'espaco_estado' and valor <> 'ok'
    union all
    -- 026: o aviso antes de pausar qualquer coisa
    select jsonb_build_object('projeto', null, 'tipo', 'espaco', 'pagina', null, 'gravidade', 'medio',
             'agora', jsonb_build_object('estado', 'aviso', 'total_mb', (e.valor::jsonb ->> 'total_mb')::numeric,
                                         'limite_mb', (e.valor::jsonb ->> 'limite_mb')::numeric))
    from radar.config e
    where e.chave = 'espaco'
      and coalesce((select valor from radar.config where chave = 'espaco_estado'), 'ok') = 'ok'
      and (e.valor::jsonb ->> 'limite_mb')::numeric > 0
      and (e.valor::jsonb ->> 'total_mb')::numeric >= 0.7 * (e.valor::jsonb ->> 'limite_mb')::numeric) x), '[]'::jsonb)
$$;


--
-- Name: anotar_tempo(text, text, numeric); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.anotar_tempo(p_rota text, p_origem text, p_ms numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_novo boolean;
  v_ms int := least(greatest(round(coalesce(p_ms, 0)), 0), 2000000000)::int;
begin
  insert into radar.tempos_api as t (dia, rota, origem, chamadas, total_ms, max_ms, lentas)
  values (radar.hoje(), left(coalesce(p_rota, '?'), 40), p_origem, 1, v_ms, v_ms, case when v_ms >= 2000 then 1 else 0 end)
  on conflict (dia, rota, origem) do update
    set chamadas = t.chamadas + 1, total_ms = t.total_ms + excluded.total_ms,
        max_ms = greatest(t.max_ms, excluded.max_ms), lentas = t.lentas + excluded.lentas
  returning (xmax = 0) into v_novo;
  -- a primeira chamada de cada dia limpa o que passou de 60 dias
  if v_novo then delete from radar.tempos_api where dia < radar.hoje() - 60; end if;
exception when others then
  null;
end $$;


--
-- Name: api(text, jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api(rota text, f jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
begin
  f := coalesce(f, '{}'::jsonb);
  case rota
    when 'projetos' then return radar.api_projetos(true, '{}');
    when 'valores' then return radar.api_valores(f);
    when 'resumo' then return radar.api_resumo(f);
    when 'inicio' then return radar.api_inicio(f);
    when 'apelidos' then return radar.api_apelidos(f);
    when 'captura' then return radar.api_captura(f);
    when 'pagina' then return radar.api_pagina(f);
    when 'sessoes' then return radar.api_sessoes(f);
    when 'sessao' then return radar.api_sessao(f);
    when 'gravacao' then return radar.api_gravacao(f);
    when 'guardadas' then return radar.api_guardadas(f);
    when 'mapa' then return radar.api_mapa(f);
    when 'insights' then return radar.api_insights(f);
    when 'desempenho' then return radar.api_desempenho(f);
    when 'laboratorio' then return radar.api_laboratorio(f);
    when 'relatorio' then return radar.api_relatorio(f);
    when 'leitura' then return radar.api_leitura(f);
    when 'oportunidades' then return radar.api_oportunidades(f);
    when 'leads_mql' then return radar.api_leads_mql(f);
    when 'testes' then return radar.api_testes(f);
    -- 076: o split (as versoes lado a lado, com as entregas do porteiro)
    when 'splits' then return radar.api_splits(f);
    -- 034: a memoria dos achados, o diario e o guardiao da velocidade
    when 'achados' then return radar.api_achados(f);
    when 'diario' then return radar.api_diario(f);
    when 'guardiao' then return radar.api_guardiao(f);
    -- 038: a Visao geral do Trafego e o Fluxo da mensageria (so numeros somados)
    when 'trafego' then return radar.api_trafego(f);
    when 'fluxo' then return radar.api_fluxo(f);
    -- 040: a regua de leads (servidor e navegador por dia e pagina)
    when 'leads_paginas' then return radar.api_leads_paginas(f);
    -- 046: o catalogo do Active (ids e nomes de listas, tags e campos)
    when 'active_catalogo' then return radar.api_active_catalogo();
    -- 050: os resultados das pesquisas (o cadastro mora no contrato do funil)
    when 'pesquisas' then return radar.api_pesquisas(f);
    -- 052: o Trafego › Quando e onde (horario, dia, lugar, estado e o app de quem veio do anuncio)
    when 'trafego_quando' then return radar.api_trafego_quando(f);
    -- 054: o ranking e o funil por anuncio pelo servidor (Trafego › Campanhas e anuncios)
    when 'trafego_anuncios' then return radar.api_trafego_anuncios(f);
    -- 059: o segmento do Fluxo (melhor horario, grupo do WhatsApp e telefones; so somas)
    when 'fluxo_segmento' then return radar.api_fluxo_segmento(f);
    -- 060: as publicacoes do periodo, para marcar nos graficos por dia (Funil, Trafego, Leads)
    when 'publicacoes' then return radar.api_publicacoes(f);
    -- 062: o que cada pagina capta, com o peso de cada uma no banco (Configuracoes › Instalacao)
    when 'captacao' then return radar.api_captacao(f);
    when 'alertas' then
      if coalesce(f ->> 'projeto', '') = '' then
        return radar.alertas_de(array(select id from radar.projetos), f, true);
      end if;
      return radar.alertas_do_projeto(f);
    else raise exception 'rota_desconhecida: %', rota;
  end case;
end $$;


--
-- Name: api_achados(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_achados(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  with reg as (select max(dia) as dia from radar.achados_registros where projeto = f ->> 'projeto')
  select jsonb_build_object(
    'registro', (select jsonb_build_object('dia', r.dia::text, 'fonte', r.fonte, 'quantos', r.quantos, 'em', radar.ms(r.em))
                 from radar.achados_registros r where r.projeto = f ->> 'projeto' order by r.dia desc limit 1),
    'achados', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chave', a.chave, 'tipo', a.tipo, 'aprendizado', a.aprendizado, 'pagina', a.pagina, 'titulo', a.titulo, 'fazer', a.fazer,
               'numeros', a.numeros, 'confianca', a.confianca, 'ganho', a.ganho, 'primeiro_dia', a.primeiro_dia::text,
               'ultimo_dia', a.ultimo_dia::text, 'dias_visto', a.dias_visto, 'estado', a.estado, 'estado_em', radar.ms(a.estado_em),
               'estado_por', (select coalesce(nullif(m.nome, ''), m.email) from radar.membros m where m.usuario = a.estado_por),
               'nota', a.nota, 'teste_id', a.teste_id,
               'situacao', case when a.estado <> 'aberto' then a.estado
                                when a.ultimo_dia < reg.dia then 'sumiu'
                                when a.primeiro_dia >= reg.dia then 'novo'
                                else 'continua' end)
             order by (a.estado <> 'aberto'), a.ultimo_dia desc, a.ganho desc)
      from radar.achados a, reg
      where a.projeto = f ->> 'projeto' and (a.estado <> 'aberto' or a.ultimo_dia >= radar.hoje() - 45)), '[]'::jsonb))
$$;


--
-- Name: api_active_catalogo(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_active_catalogo() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object(
    'ligada', coalesce((select i.ligada from radar.integracoes i where i.id = 'active'), false),
    'sincronizada_em', (select radar.ms(i.sincronizada_em) from radar.integracoes i where i.id = 'active'),
    'itens', coalesce((select jsonb_agg(jsonb_build_array(c.tipo, c.id, c.nome) order by c.tipo, c.id)
                       from (select * from radar.active_catalogo where tipo in ('listas', 'tags', 'campos') limit 5000) c), '[]'::jsonb))
$$;


--
-- Name: api_alertas(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_alertas(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
hoje as (select radar.hoje() as d),
ss as materialized (
  select s.id, s.dia, s.primeira_pagina, s.lead, s.fbclid, s.gclid, s.utm_source,
         radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u,
         (s.engajada or radar.encerrada(s.recebido_em)) as conta, (not s.engajada and radar.encerrada(s.recebido_em)) as rejeitou
  from radar.sessoes s, hoje
  where s.projeto = f ->> 'projeto' and s.dia >= hoje.d - 15 and (coalesce(f ->> 'teste', '') = '1' or not s.teste)
    and coalesce(s.visivel_ms, 0) > 0),
-- entradas e rejeicoes por sessao (a regua da rejeicao); unidades e leads em visitas unicas (a taxa de lead)
e as (
  select dia, primeira_pagina as pagina, count(*) filter (where conta) as entradas,
         count(*) filter (where rejeitou) as rejeicoes,
         count(distinct u) filter (where conta) as unidades, count(distinct u) filter (where conta and lead) as leads
  from ss group by 1, 2),
jan as (
  select w.n as janela, e.pagina,
         coalesce(sum(e.entradas) filter (where e.dia between hoje.d - w.n and hoje.d - 1), 0) as e1,
         coalesce(sum(e.unidades) filter (where e.dia between hoje.d - w.n and hoje.d - 1), 0) as u1,
         coalesce(sum(e.leads) filter (where e.dia between hoje.d - w.n and hoje.d - 1), 0) as l1,
         coalesce(sum(e.rejeicoes) filter (where e.dia between hoje.d - w.n and hoje.d - 1), 0) as r1,
         coalesce(sum(e.entradas) filter (where e.dia between hoje.d - w.n - 7 and hoje.d - 8), 0) as e0,
         coalesce(sum(e.unidades) filter (where e.dia between hoje.d - w.n - 7 and hoje.d - 8), 0) as u0,
         coalesce(sum(e.leads) filter (where e.dia between hoje.d - w.n - 7 and hoje.d - 8), 0) as l0,
         coalesce(sum(e.rejeicoes) filter (where e.dia between hoje.d - w.n - 7 and hoje.d - 8), 0) as r0
  from e, hoje, (values (1), (3)) w(n)
  group by w.n, e.pagina),
quedas as (
  select distinct on (pagina, tipo) tipo, janela, pagina, e1, u1, l1, r1, e0, u0, l0, r0
  from (
    select 'queda_lead' as tipo, janela, pagina, e1, u1, l1, r1, e0, u0, l0, r0,
           (l1 / u1 - l0 / u0) / nullif(sqrt(((l1 + l0) / (u1 + u0)) * (1 - (l1 + l0) / (u1 + u0)) * (1.0 / u1 + 1.0 / u0)), 0) as z
    from jan where u1 >= 30 and u0 >= 30 and l0 > 0 and l1 / u1 <= (l0 / u0) * 0.7
    union all
    select 'rejeicao', janela, pagina, e1, u1, l1, r1, e0, u0, l0, r0,
           (r0 / e0 - r1 / e1) / nullif(sqrt(((r1 + r0) / (e1 + e0)) * (1 - (r1 + r0) / (e1 + e0)) * (1.0 / e1 + 1.0 / e0)), 0)
    from jan where e1 >= 30 and e0 >= 30 and r1 / e1 - r0 / e0 >= 0.10) x
  where z <= -1.64
  order by pagina, tipo, janela),
vis as (
  select v.pagina,
         count(distinct ss.u) filter (where v.inicio >= now() - interval '24 hours') as v1,
         count(distinct ss.u) filter (where v.inicio < now() - interval '24 hours') as v0,
         count(v.lcp_ms) filter (where v.inicio >= now() - interval '24 hours') as m1,
         count(v.lcp_ms) filter (where v.inicio < now() - interval '24 hours') as m0,
         percentile_disc(0.75) within group (order by v.lcp_ms) filter (where v.inicio >= now() - interval '24 hours') as lcp1,
         percentile_disc(0.75) within group (order by v.lcp_ms) filter (where v.inicio < now() - interval '24 hours') as lcp0
  from radar.visualizacoes v join ss on ss.id = v.sessao
  where v.inicio >= now() - interval '8 days' group by v.pagina),
er as (
  select x.pagina, count(distinct ss.u) filter (where x.quando >= now() - interval '24 hours') as agora,
         count(distinct ss.u) filter (where x.quando < now() - interval '24 hours') as antes
  from radar.erros x join ss on ss.id = x.sessao
  -- so erro da pagina (025): o de fora (app, outro site, extensao, aviso do navegador) nao abre alerta
  where x.quando >= now() - interval '8 days' and x.origem = 'pagina' group by x.pagina),
pago as (
  select count(*) filter (where fbclid or gclid) as pagos, count(*) filter (where (fbclid or gclid) and utm_source is null) as sem
  from ss, hoje where ss.dia >= hoje.d - 1)
select jsonb_build_object('projeto', f ->> 'projeto', 'alertas', coalesce((select jsonb_agg(a) from (
  select jsonb_build_object('projeto', f ->> 'projeto', 'tipo', tipo, 'pagina', pagina, 'janela', janela,
           'gravidade', case when tipo = 'queda_lead' and l1 / u1 <= (l0 / u0) * 0.5 then 'alto' when tipo = 'rejeicao' and r1 / e1 - r0 / e0 >= 0.2 then 'alto' else 'medio' end,
           'agora', jsonb_build_object('entradas', case when tipo = 'queda_lead' then u1 else e1 end, 'leads', l1, 'rejeicoes', r1),
           'antes', jsonb_build_object('entradas', case when tipo = 'queda_lead' then u0 else e0 end, 'leads', l0, 'rejeicoes', r0)) as a
  from quedas
  union all
  select jsonb_build_object('projeto', f ->> 'projeto', 'tipo', 'erro', 'pagina', er.pagina, 'gravidade', 'alto',
           'agora', jsonb_build_object('sessoes', er.agora, 'visitas', vis.v1), 'antes', jsonb_build_object('sessoes', er.antes, 'visitas', vis.v0))
  from er join vis on vis.pagina = er.pagina
  where er.agora >= 5 and er.agora >= vis.v1 * 0.03 and (er.antes = 0 or vis.v0 = 0 or er.agora::numeric / greatest(vis.v1, 1) >= 3 * er.antes::numeric / vis.v0)
  union all
  select jsonb_build_object('projeto', f ->> 'projeto', 'tipo', 'lenta', 'pagina', pagina, 'gravidade', case when lcp1 > 4000 then 'alto' else 'medio' end,
           'agora', jsonb_build_object('lcp', lcp1, 'medidas', m1), 'antes', jsonb_build_object('lcp', lcp0, 'medidas', m0))
  from vis where m1 >= 20 and m0 >= 20 and lcp1 > 2500 and lcp1 >= lcp0 * 1.4
  union all
  select jsonb_build_object('projeto', f ->> 'projeto', 'tipo', 'sem_visitas', 'pagina', pagina, 'gravidade', 'alto',
           'agora', jsonb_build_object('visitas', v1), 'antes', jsonb_build_object('visitas', v0, 'por_dia', round(v0 / 7.0)))
  from vis where v0 >= 140 and v1 * 10 <= v0 / 7.0
  union all
  select jsonb_build_object('projeto', f ->> 'projeto', 'tipo', 'sem_utm', 'pagina', null, 'gravidade', 'medio',
           'agora', jsonb_build_object('sem', sem, 'pagos', pagos))
  from pago where sem >= 10 and sem >= pagos * 0.10) y), '[]'::jsonb))
$$;


--
-- Name: api_apelidos(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_apelidos(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object(
    'campanha', coalesce((select jsonb_object_agg(valor, nome) from radar.apelidos where projeto = f ->> 'projeto' and tipo = 'campanha'), '{}'::jsonb),
    'conjunto', coalesce((select jsonb_object_agg(valor, nome) from radar.apelidos where projeto = f ->> 'projeto' and tipo = 'conjunto'), '{}'::jsonb),
    'anuncio', coalesce((select jsonb_object_agg(valor, nome) from radar.apelidos where projeto = f ->> 'projeto' and tipo = 'anuncio'), '{}'::jsonb))
$$;


--
-- Name: api_captacao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_captacao(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
pj as (select p.id, p.config, p.retencao_gravacao_dias, p.retencao_cliques_dias, p.retencao_sessoes_meses
       from radar.projetos p where p.id = f ->> 'projeto'),
pg as (
  select x.v ->> 'id' as id, x.v ->> 'nome' as nome, x.v ->> 'caminho' as caminho, x.v ->> 'tipo' as tipo, x.n::int as ordem
  from pj, jsonb_array_elements(coalesce(pj.config -> 'paginas', '[]'::jsonb)) with ordinality x(v, n)
  where coalesce(x.v ->> 'id', '') <> ''
),
-- os dois ultimos dias inteiros (o video fica 3 dias: o terceiro ja comecou a sair)
d as (select radar.hoje() - 2 as de, radar.hoje() - 1 as ate),
vistas as (
  select v.pagina, count(*)::int as n, count(distinct v.dia)::int as dias
  from d, radar.visualizacoes v join radar.sessoes s on s.id = v.sessao
  where v.projeto = f ->> 'projeto' and v.dia between d.de and d.ate and not s.teste
  group by v.pagina
),
ultima as (
  select v.pagina, max(v.inicio) as em
  from radar.visualizacoes v join radar.sessoes s on s.id = v.sessao
  where v.projeto = f ->> 'projeto' and v.dia >= radar.hoje() - 14 and not s.teste
  group by v.pagina
),
video as (
  select v.pagina, sum(g.bytes)::bigint as bytes, count(distinct g.dia)::int as dias
  from d, radar.gravacoes g join radar.visualizacoes v on v.id = g.visualizacao join radar.sessoes s on s.id = g.sessao
  where g.projeto = f ->> 'projeto' and g.dia between d.de and d.ate and not s.teste
  group by v.pagina
),
linhas as (
  select pg.id, pg.nome, pg.caminho, pg.tipo, pg.ordem, c.video, c.cliques, c.leitura, c.velocidade, c.erros, c.atualizado_em, c.atualizado_por,
         coalesce(vi.n, 0) as n, greatest(coalesce(vi.dias, 0), 1) as dias, u.em as ultima_em,
         coalesce(vd.bytes, 0) as v_bytes, greatest(coalesce(vd.dias, 0), 1) as v_dias
  from pg
  left join radar.captacao c on c.projeto = f ->> 'projeto' and c.pagina = pg.id
  left join vistas vi on vi.pagina = pg.id
  left join ultima u on u.pagina = pg.id
  left join video vd on vd.pagina = pg.id
),
-- o video por pagina vista nas paginas que gravam: a conta do "se gravasse todas" da pagina que ainda nao grava
media as (select coalesce(sum(v_bytes)::numeric / nullif(sum(n) filter (where v_bytes > 0), 0), 0) as bytes_vista from linhas),
esp as (select valor::jsonb as e from radar.config where chave = 'espaco'),
tot as (select coalesce(sum(n::numeric / dias), 0) as vistas_dia from linhas)
select jsonb_build_object(
  'projeto', pj.id,
  'paginas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'nome', l.nome, 'caminho', l.caminho, 'tipo', l.tipo,
      'video', coalesce(l.video, 1), 'cliques', coalesce(l.cliques, true), 'leitura', coalesce(l.leitura, true),
      'velocidade', coalesce(l.velocidade, true), 'erros', coalesce(l.erros, true),
      'mudou_em', radar.ms(l.atualizado_em),
      'mudou_por', (select coalesce(nullif(m.nome, ''), 'Administrador') from radar.membros m where m.usuario = l.atualizado_por),
      'ultima_visita', radar.ms(l.ultima_em),
      'vistas_dia', round(l.n::numeric / l.dias),
      'video_mb_dia', round(l.v_bytes::numeric / l.v_dias / 1048576, 1),
      'video_mb_dia_todas', round(l.n::numeric / l.dias * (select bytes_vista from media) / 1048576, 1)
    ) order by l.ordem) from linhas l), '[]'::jsonb),
  -- o resto (tudo o que nao e video, o CRM incluso) que o banco ganha por dia, dividido pelas paginas vistas por dia
  'resto_kb_vista', round((select (e -> 'previsao' ->> 'resto_mb_dia')::numeric from esp) * 1024 / nullif((select vistas_dia from tot), 0), 1),
  'video_kb_vista', round((select bytes_vista from media) / 1024, 1),
  'retencao', jsonb_build_object('video_dias', pj.retencao_gravacao_dias, 'cliques_dias', pj.retencao_cliques_dias,
                                 'visitas_meses', pj.retencao_sessoes_meses),
  'espaco', (select e from esp)
)
from pj
$$;


--
-- Name: api_captura(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_captura(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
cfg as (select config from radar.projetos where id = f ->> 'projeto'),
tipos as (
  select pg ->> 'id' as id, pg ->> 'tipo' as tipo
  from cfg, jsonb_array_elements(coalesce(cfg.config -> 'paginas', '[]'::jsonb)) pg),
s as materialized (
  select s.dia, s.lead, radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u, coalesce(t.tipo, '') as tipo,
         coalesce(radar.plataforma(s.utm_source, s.utm_medium, s.fbclid, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content),
                  'sem_anuncio') as plat
  from radar.filtradas(f) s left join tipos t on t.id = s.primeira_pagina),
tot as (
  select count(distinct u)::int as visitas,
         (count(distinct u) filter (where tipo = 'captura'))::int as captura,
         (count(distinct u) filter (where tipo = 'captura' and lead))::int as leads_captura,
         (count(distinct u) filter (where lead))::int as leads,
         (count(distinct u) filter (where tipo = 'obrigado'))::int as direto_obrigado
  from s)
select jsonb_build_object(
  'visitas', tot.visitas, 'captura', tot.captura, 'leads_captura', tot.leads_captura, 'leads', tot.leads,
  'direto_obrigado', tot.direto_obrigado,
  'por_dia', coalesce((
    select jsonb_agg(jsonb_build_object('dia', dia::text, 'captura', c, 'leads_captura', l) order by dia)
    from (select dia, (count(distinct u) filter (where tipo = 'captura'))::int as c,
                 (count(distinct u) filter (where tipo = 'captura' and lead))::int as l
          from s group by dia) x), '[]'::jsonb),
  'por_plataforma', coalesce((
    select jsonb_agg(jsonb_build_object('plataforma', plat, 'captura', c, 'leads_captura', l) order by c desc, plat)
    from (select plat, (count(distinct u) filter (where tipo = 'captura'))::int as c,
                 (count(distinct u) filter (where tipo = 'captura' and lead))::int as l
          from s group by plat) y), '[]'::jsonb))
from tot
$$;


--
-- Name: api_desempenho(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_desempenho(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
s as materialized (select * from radar.filtradas(f)),
b as materialized (
  select v.*, s.dispositivo, s.lead, s.engajada, s.recebido_em, coalesce(s.sistema, '') as sistema, coalesce(s.app, '') as app,
         case when v.lcp_ms is null then null when v.lcp_ms <= 2500 then 'bom' when v.lcp_ms <= 4000 then 'medio' else 'ruim' end as faixa_lcp
  from radar.visualizacoes v join s on s.id = v.sessao),
grupos as (
  select pagina, coalesce(dispositivo, 'todos') as dispositivo,
         count(*) as visitas, count(lcp_ms) as medidas,
         percentile_disc(0.75) within group (order by lcp_ms) as lcp,
         percentile_disc(0.75) within group (order by inp_ms) as inp,
         round((percentile_disc(0.75) within group (order by cls))::numeric, 3) as cls,
         percentile_disc(0.75) within group (order by fcp_ms) as fcp,
         percentile_disc(0.75) within group (order by ttfb_ms) as ttfb,
         percentile_disc(0.75) within group (order by carga_ms) as carga,
         percentile_disc(0.75) within group (order by peso_kb) as peso,
         count(*) filter (where lcp_ms <= 2500) as lcp_bom, count(*) filter (where lcp_ms > 2500 and lcp_ms <= 4000) as lcp_medio,
         count(*) filter (where lcp_ms > 4000) as lcp_ruim,
         count(*) filter (where inp_ms <= 200) as inp_bom, count(*) filter (where inp_ms > 200 and inp_ms <= 500) as inp_medio,
         count(*) filter (where inp_ms > 500) as inp_ruim,
         count(*) filter (where cls <= 0.1) as cls_bom, count(*) filter (where cls > 0.1 and cls <= 0.25) as cls_medio,
         count(*) filter (where cls > 0.25) as cls_ruim,
         count(*) filter (where ordem = 1 and (engajada or radar.encerrada(recebido_em))) as entradas,
         count(*) filter (where ordem = 1 and not engajada and radar.encerrada(recebido_em)) as rejeicoes
  from b group by grouping sets ((pagina, dispositivo), (pagina)))
select jsonb_build_object(
  'paginas', coalesce((select jsonb_agg(to_jsonb(g) order by g.pagina, g.dispositivo) from grupos g), '[]'::jsonb),
  'faixas_lcp', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'faixa', faixa_lcp, 'entradas', n, 'rejeicoes', r, 'leads', leads) order by pagina, faixa_lcp)
     from (select pagina, faixa_lcp, count(*) filter (where engajada or radar.encerrada(recebido_em)) as n,
                  count(*) filter (where not engajada and radar.encerrada(recebido_em)) as r,
                  count(*) filter (where lead and (engajada or radar.encerrada(recebido_em))) as leads
           from b where ordem = 1 and faixa_lcp is not null group by 1, 2) x), '[]'::jsonb),
  -- 032: o INP do dia e as aberturas, alem do LCP
  'por_dia', coalesce((
     select jsonb_agg(jsonb_build_object('dia', dia::text, 'pagina', pagina, 'lcp_p75', lcp, 'medidas', n,
                                         'inp_p75', inp, 'medidas_inp', ni, 'visitas', v) order by dia, pagina)
     from (select dia, pagina, percentile_disc(0.75) within group (order by lcp_ms) as lcp, count(lcp_ms) as n,
                  percentile_disc(0.75) within group (order by inp_ms) as inp, count(inp_ms) as ni, count(*) as v
           from b where lcp_ms is not null or inp_ms is not null group by 1, 2) x), '[]'::jsonb),
  -- 032: o quadro por sistema e aplicativo ('' = navegador comum), de cada pagina
  'por_grupo', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'sistema', sistema, 'app', app, 'visitas', v,
                                         'lcp_p75', lcp, 'medidas', n, 'inp_p75', inp, 'medidas_inp', ni) order by pagina, v desc)
     from (select pagina, sistema, app, count(*) as v,
                  percentile_disc(0.75) within group (order by lcp_ms) as lcp, count(lcp_ms) as n,
                  percentile_disc(0.75) within group (order by inp_ms) as inp, count(inp_ms) as ni
           from b group by 1, 2, 3) x), '[]'::jsonb),
  -- 032: as publicacoes do periodo, para marcar no grafico por dia
  'publicacoes', coalesce((
     select jsonb_agg(jsonb_build_object('quando', radar.ms(p.quando), 'dia', (p.quando at time zone 'America/Sao_Paulo')::date::text,
                                         'pagina', p.pagina, 'resumo', p.resumo) order by p.quando)
     from radar.publicacoes p
     where p.projeto = f ->> 'projeto'
       and (p.quando at time zone 'America/Sao_Paulo')::date between coalesce(radar.data(f ->> 'de'), radar.hoje() - 6)
                                                                  and coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)), '[]'::jsonb),
  'laboratorio', coalesce((
     select jsonb_agg(jsonb_build_object('id', l.id, 'pagina', l.pagina, 'url', l.url, 'estrategia', l.estrategia, 'nota', l.nota,
                                         'notas', l.notas, 'lcp_ms', l.lcp_ms, 'fcp_ms', l.fcp_ms, 'tbt_ms', l.tbt_ms, 'si_ms', l.si_ms,
                                         'cls', l.cls, 'medido_em', radar.ms(l.medido_em), 'nota_anterior', l.nota_anterior,
                                         'tem_relatorio', l.tem_relatorio) order by l.pagina, l.estrategia)
     from (select distinct on (pagina, estrategia) id, pagina, url, estrategia, nota, notas, lcp_ms, fcp_ms, tbt_ms, si_ms, cls,
                  medido_em, relatorio is not null as tem_relatorio,
                  lead(nota) over (partition by pagina, estrategia order by medido_em desc, id desc) as nota_anterior
           from radar.velocidade_lab where projeto = f ->> 'projeto'
           order by pagina, estrategia, medido_em desc, id desc) l), '[]'::jsonb))
$$;


--
-- Name: api_diario(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_diario(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('diarios', coalesce((
    select jsonb_agg(jsonb_build_object('dia', d.dia::text, 'texto', d.texto, 'cortadas', d.cortadas, 'gerado_em', radar.ms(d.gerado_em),
                                        'gerado_por', d.gerado_por) order by d.dia desc)
    from (select * from radar.diarios where projeto = f ->> 'projeto' and (radar.data(f ->> 'dia') is null or dia = radar.data(f ->> 'dia'))
          order by dia desc limit 30) d), '[]'::jsonb))
$$;


--
-- Name: api_fluxo(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_fluxo(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
q as (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate),
gente as materialized (
  select x.pagina_primeira as pagina, x.pesquisa_via as via, x.parou_em as parou, x.mql,
         coalesce(nullif(x.respostas ->> 'intencao', ''), x.respostas ->> 'nivel', '') as intencao,   -- 075: o nivel do MQL (a Black) quando nao ha intencao
         -- 044: a plataforma do primeiro clique (as raizes da arvore) e o dia em que a pessoa entrou (o crescer dia a dia)
         nullif(x.plataforma, '') as plataforma,
         (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia,
         radar.situacao_active(ent.active, ent.via) as sit_entrada,
         radar.situacao_active(pq.active, pq.via) as sit_pesquisa
  from radar_crm.pessoas x
  cross join q
  -- a inscricao (ou cadastro) da pessoa: a primeira
  left join lateral (
    select e.active, e.via from radar_crm.envios e
    where e.pessoa = x.id and e.tipo in ('inscricao', 'captura') order by e.quando, e.recebido_em limit 1) ent on true
  -- a pesquisa que deu o resultado: a primeira concluida (a mesma regra da radar_crm.recalcular)
  left join lateral (
    select e.active, e.via from radar_crm.envios e
    where e.pessoa = x.id and e.tipo in ('pesquisa', 'pesquisa_link') and coalesce(e.dados ->> 'mql', '') in ('sim', 'nao')
    order by e.quando, e.recebido_em limit 1) pq on true
  where x.projeto = f ->> 'projeto' and not x.teste
    and (x.primeiro_em at time zone 'America/Sao_Paulo')::date between q.de and q.ate
    and (coalesce(f ->> 'pagina', '') = '' or x.pagina_primeira = f ->> 'pagina')
    and radar.canal_crm(x.plataforma, f ->> 'canal'))
select jsonb_build_object(
  'de', q.de::text, 'ate', q.ate::text,
  'crm', exists (select 1 from radar_crm.pessoas x where x.projeto = f ->> 'projeto' and not x.teste),
  'desde', radar.crm_desde(f ->> 'projeto')::text,   -- 044: o comeco pelo volume, como na 042
  'desde_servidor', (select min(e.quando) from radar_crm.envios e where e.projeto = f ->> 'projeto' and e.via <> 'importado' and not e.teste),
  'contrato', (select p.config -> 'fluxo' from radar.projetos p where p.id = f ->> 'projeto'),
  'grupos', coalesce((select jsonb_agg(jsonb_build_object('pagina', g.pagina, 'via', g.via, 'parou', g.parou, 'mql', g.mql, 'intencao', g.intencao,
                                                          'sit_entrada', g.sit_entrada, 'sit_pesquisa', g.sit_pesquisa, 'n', g.n) order by g.n desc)
                      from (select pagina, via, parou, mql, intencao, sit_entrada, sit_pesquisa, count(*) as n
                            from gente group by 1, 2, 3, 4, 5, 6, 7) g), '[]'::jsonb),
  -- 044: a arvore, em linhas curtas [dia, pagina, via, parou, mql, intencao, plataforma, n]
  'arvore', coalesce((select jsonb_agg(jsonb_build_array(a.dia::text, a.pagina, a.via, a.parou, a.mql, a.intencao, a.plataforma, a.n)
                                       order by a.dia, a.n desc)
                      from (select dia, pagina, via, parou, mql, intencao, plataforma, count(*)::int as n
                            from gente group by 1, 2, 3, 4, 5, 6, 7) a), '[]'::jsonb))
from q
$$;


--
-- Name: api_fluxo_segmento(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_fluxo_segmento(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'radar_crm'
    AS $$
with
-- 061: a busca (nome, e-mail ou telefone) nao vale aqui: so numeros somados, sem achar uma pessoa
seg as materialized (select p.id, p.telefone, p.primeiro_em, p.grupo_entrou_em, p.pagina_primeira from radar_crm.filtradas(f - 'busca') p),
-- todas as pessoas novas do mesmo periodo, pagina e plataforma: a regua do horario
todos as materialized (
  select p.primeiro_em from radar_crm.filtradas(jsonb_strip_nulls(jsonb_build_object(
    'projeto', f ->> 'projeto', 'de', f ->> 'de', 'ate', f ->> 'ate', 'pagina', f ->> 'pagina', 'plataforma', f ->> 'plataforma'))) p),
rep as materialized (select r.telefone from radar_crm.telefones_repetidos(f ->> 'projeto') r),
tel as materialized (select radar_crm.telefone_situacao(s.telefone) as sit, s.telefone in (select r.telefone from rep r) as repetido from seg s),
gr as materialized (select g.situacao, s.primeiro_em, s.grupo_entrou_em, s.pagina_primeira from seg s join radar_crm.grupo_de(f ->> 'projeto', (select array_agg(s2.id) from seg s2)) g on g.pessoa = s.id),
-- 065: os fluxos do contrato (fluxo.entradas: id, nome e as paginas de entrada), na ordem do contrato
fx as (
  select e.ordem, e.v ->> 'id' as id, coalesce(e.v ->> 'nome', e.v ->> 'id') as nome,
         array(select jsonb_array_elements_text(case when jsonb_typeof(e.v -> 'paginas') = 'array' then e.v -> 'paginas' else '[]'::jsonb end)) as paginas
  from radar.projetos p
  cross join lateral jsonb_array_elements(case when jsonb_typeof(p.config -> 'fluxo' -> 'entradas') = 'array' then p.config -> 'fluxo' -> 'entradas' else '[]'::jsonb end)
    with ordinality e (v, ordem)
  where p.id = f ->> 'projeto' and coalesce(e.v ->> 'id', '') <> ''),
-- 064: desde quando o SendFlow conta no projeto (nulo: o webhook ainda nao mandou nada)
sf as (select radar_crm.grupo_desde(f ->> 'projeto') as desde),
horas as (
  select 'seg' as quem, extract(hour from s.primeiro_em at time zone 'America/Sao_Paulo')::int as h, count(*)::int as n from seg s group by 2
  union all
  select 'todos', extract(hour from t.primeiro_em at time zone 'America/Sao_Paulo')::int, count(*)::int from todos t group by 2)
select jsonb_build_object(
  'ok', true,
  'n', (select count(*) from seg),
  -- as inscricoes por hora de Brasilia, de 0 a 23: do segmento e de todas as pessoas novas do periodo
  'horas', (select jsonb_agg(coalesce(h.n, 0) order by k.k) from generate_series(0, 23) k (k) left join horas h on h.quem = 'seg' and h.h = k.k),
  'horas_todos', (select jsonb_agg(coalesce(h.n, 0) order by k.k) from generate_series(0, 23) k (k) left join horas h on h.quem = 'todos' and h.h = k.k),
  -- o grupo: nulo quando o contrato do funil nao tem o bloco fluxo.grupo
  'grupo', case when exists (select 1 from radar.projetos p where p.id = f ->> 'projeto' and jsonb_typeof(p.config -> 'fluxo' -> 'grupo') = 'object')
    then jsonb_build_object('foi', (select count(*) from gr where situacao = 'foi'), 'nao', (select count(*) from gr where situacao = 'nao'),
                            'sem', (select count(*) from seg) - (select count(*) from gr where situacao in ('foi', 'nao')),
                            -- 064: o que o SendFlow confirmou, so de quem se inscreveu desde o primeiro evento dele (nulo antes)
                            'ingresso', (select case when sf.desde is null then null else jsonb_build_object(
                              'desde', sf.desde,
                              'viu', (select count(*) from gr where situacao in ('foi', 'nao') and primeiro_em >= sf.desde),
                              'foi', (select count(*) from gr where situacao = 'foi' and primeiro_em >= sf.desde),
                              'entrou', (select count(*) from gr where situacao in ('foi', 'nao') and primeiro_em >= sf.desde and grupo_entrou_em is not null),
                              'entrou_sem_registro', (select count(*) from seg s where s.primeiro_em >= sf.desde and s.grupo_entrou_em is not null)
                                - (select count(*) from gr where situacao in ('foi', 'nao') and primeiro_em >= sf.desde and grupo_entrou_em is not null),
                              'medidas', (select count(*) from seg s where s.primeiro_em >= sf.desde),
                              -- 065: o mesmo, fluxo a fluxo (a pagina do primeiro envio da pessoa numa das paginas do fluxo).
                              -- leads: as pessoas do fluxo medidas (desde o primeiro evento), a base da taxa sobre os leads.
                              -- Fluxo sem ninguem no segmento nao vem (o segmento ja de um fluxo so traz so ele)
                              'por_fluxo', coalesce((select jsonb_agg(jsonb_build_object(
                                  'id', x.id, 'nome', x.nome, 'leads', x.leads, 'viu', x.viu, 'foi', x.foi, 'entrou', x.entrou,
                                  'entrou_de_fato', x.entrou_de_fato) order by x.ordem)
                                from (select fx.ordem, fx.id, fx.nome,
                                        (select count(*) from seg s where s.primeiro_em >= sf.desde and s.pagina_primeira = any (fx.paginas)) as leads,
                                        (select count(*) from gr where situacao in ('foi', 'nao') and primeiro_em >= sf.desde and pagina_primeira = any (fx.paginas)) as viu,
                                        (select count(*) from gr where situacao = 'foi' and primeiro_em >= sf.desde and pagina_primeira = any (fx.paginas)) as foi,
                                        (select count(*) from gr where situacao in ('foi', 'nao') and primeiro_em >= sf.desde and grupo_entrou_em is not null
                                           and pagina_primeira = any (fx.paginas)) as entrou,
                                        (select count(*) from seg s where s.primeiro_em >= sf.desde and s.grupo_entrou_em is not null
                                           and s.pagina_primeira = any (fx.paginas)) as entrou_de_fato
                                      from fx) x where x.leads > 0), '[]'::jsonb)) end from sf)) end,
  'telefones', (select jsonb_build_object(
    'ok', count(*) filter (where sit = 'ok'), 'sem_9', count(*) filter (where sit = 'sem_9'), 'fixo', count(*) filter (where sit = 'fixo'),
    'ddd', count(*) filter (where sit = 'ddd'), 'invalido', count(*) filter (where sit = 'invalido'), 'vazio', count(*) filter (where sit = 'vazio'),
    'repetido', count(*) filter (where repetido),
    -- pronto: celular (com o 9 ou sem, que a exportacao poe) de um numero so dele; o resto pede atencao
    'pronto', count(*) filter (where sit in ('ok', 'sem_9') and not repetido)) from tel))
$$;


--
-- Name: api_gravacao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_gravacao(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('pedacos', coalesce(jsonb_agg(jsonb_build_object('f', g.formato, 'd', translate(encode(g.dados, 'base64'), E'\n', ''))
                                                          order by v.ordem, g.seq), '[]'::jsonb))
  from radar.sessoes s
  cross join lateral (
    select gg.visualizacao, gg.seq, gg.formato, gg.dados from radar.gravacoes_guardadas gg where gg.sessao = s.id
    union all
    select g.visualizacao, g.seq, g.formato, g.dados from radar.gravacoes g
    where g.dia = s.dia and g.sessao = s.id
      and not exists (select 1 from radar.gravacoes_guardadas gg
                      where gg.sessao = g.sessao and gg.visualizacao = g.visualizacao and gg.seq = g.seq)) g
  join radar.visualizacoes v on v.id = g.visualizacao
  where s.id = f ->> 'sessao' and (coalesce(f ->> 'pv', '') = '' or g.visualizacao = f ->> 'pv')
$$;


--
-- Name: api_gravacao_foto(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_gravacao_foto(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('foto', true,
           'pedacos', coalesce(jsonb_agg(jsonb_build_object('f', x.formato, 'd', translate(encode(x.dados, 'base64'), E'\n', '')) order by x.seq), '[]'::jsonb))
  from (
    select g.seq, g.formato, g.dados
    from radar.sessoes s
    cross join lateral (
      select gg.seq, gg.formato, gg.dados from radar.gravacoes_guardadas gg where gg.sessao = s.id and gg.visualizacao = f ->> 'pv'
      union all
      select g.seq, g.formato, g.dados from radar.gravacoes g
      where g.dia = s.dia and g.sessao = s.id and g.visualizacao = f ->> 'pv'
        and not exists (select 1 from radar.gravacoes_guardadas gg
                        where gg.sessao = g.sessao and gg.visualizacao = g.visualizacao and gg.seq = g.seq)) g
    where s.id = f ->> 'sessao'
    order by g.seq
    limit 2) x
$$;


--
-- Name: api_guardadas(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_guardadas(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object(
    'teto', 200,
    'no_banco', (select count(*) from radar.guardadas),
    'total', (select count(*) from radar.guardadas k where k.projeto = f ->> 'projeto'),
    'sessoes', coalesce((
       select jsonb_agg(radar.sessao_json(x) || jsonb_build_object(
                'caminho', coalesce((select jsonb_agg(v.pagina order by v.ordem) from radar.visualizacoes v where v.sessao = x.id), '[]'::jsonb),
                'guardada_em', radar.ms(k.guardada_em),
                'guardada_por', (select coalesce(nullif(trim(m.nome), ''), split_part(m.email, '@', 1)) from radar.membros m where m.usuario = k.guardada_por))
              order by k.guardada_em desc)
       from radar.guardadas k join radar.sessoes x on x.id = k.sessao
       where k.projeto = f ->> 'projeto'), '[]'::jsonb))
$$;


--
-- Name: api_guardiao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_guardiao(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
pr as (select p.id, p.config from radar.projetos p where p.id = f ->> 'projeto'),
pags as (select x ->> 'id' as pagina from pr, jsonb_array_elements(coalesce(pr.config -> 'paginas', '[]'::jsonb)) x),
pubs as (
  select p.quando, p.resumo, case when p.pagina = '*' then g.pagina else p.pagina end as pagina
  from radar.publicacoes p
  left join pags g on p.pagina = '*'
  where p.projeto = f ->> 'projeto' and p.quando >= now() - interval '14 days' and (p.pagina <> '*' or g.pagina is not null)),
marcadas as (
  select pagina, quando, resumo,
         case when lag(quando) over (partition by pagina order by quando) is null
                or quando - lag(quando) over (partition by pagina order by quando) > interval '2 hours' then 1 else 0 end as nova
  from pubs),
numeradas as (select *, sum(nova) over (partition by pagina order by quando) as rodada from marcadas),
rodadas as materialized (
  select pagina, rodada, min(quando) as ini, max(quando) as fim, count(*) as n,
         (array_agg(resumo order by quando))[1] as resumo
  from numeradas group by pagina, rodada),
janelas as materialized (
  select r.*, lead(r.ini) over (partition by r.pagina order by r.ini) as proxima,
         least(r.fim + interval '72 hours', coalesce(lead(r.ini) over (partition by r.pagina order by r.ini), 'infinity'::timestamptz), now()) as depois_ate
  from rodadas r),
s as materialized (select id, dispositivo from radar.filtradas(jsonb_build_object('projeto', f ->> 'projeto', 'de', (radar.hoje() - 17)::text))),
v as materialized (
  select vv.pagina, vv.inicio, vv.lcp_ms, vv.inp_ms, s.dispositivo
  from radar.visualizacoes vv join s on s.id = vv.sessao
  where vv.inicio >= now() - interval '17 days' and vv.pagina in (select pagina from janelas)
    and (vv.lcp_ms is not null or vv.inp_ms is not null) and s.dispositivo in ('mobile', 'desktop')),
medidas as (
  select j.pagina, j.rodada, j.ini, j.fim, j.n, j.resumo, j.proxima, j.depois_ate, d.dispositivo,
         count(v.lcp_ms) filter (where v.inicio < j.ini) as n_a,
         percentile_disc(0.75) within group (order by v.lcp_ms) filter (where v.inicio < j.ini) as lcp_a,
         count(v.inp_ms) filter (where v.inicio < j.ini) as ni_a,
         percentile_disc(0.75) within group (order by v.inp_ms) filter (where v.inicio < j.ini) as inp_a,
         count(v.lcp_ms) filter (where v.inicio >= j.fim) as n_d,
         percentile_disc(0.75) within group (order by v.lcp_ms) filter (where v.inicio >= j.fim) as lcp_d,
         count(v.inp_ms) filter (where v.inicio >= j.fim) as ni_d,
         percentile_disc(0.75) within group (order by v.inp_ms) filter (where v.inicio >= j.fim) as inp_d
  from janelas j
  cross join (values ('mobile'), ('desktop')) d(dispositivo)
  left join v on v.pagina = j.pagina and v.dispositivo = d.dispositivo and v.inicio >= j.ini - interval '72 hours' and v.inicio < j.depois_ate
                 and (v.inicio < j.ini or v.inicio >= j.fim)
  group by j.pagina, j.rodada, j.ini, j.fim, j.n, j.resumo, j.proxima, j.depois_ate, d.dispositivo),
julgadas as (
  select m.*,
         (m.n_a >= 50 and m.n_d >= 50) as da_para,
         (m.n_a >= 50 and m.n_d >= 50 and m.lcp_d >= m.lcp_a * 1.25 and m.lcp_d - m.lcp_a >= 400) as lcp_piorou,
         (m.ni_a >= 30 and m.ni_d >= 30 and m.inp_d >= m.inp_a * 1.25 and m.inp_d - m.inp_a >= 100) as inp_piorou,
         (m.n_a >= 50 and m.n_d >= 50 and m.lcp_d <= m.lcp_a * 0.8 and m.lcp_a - m.lcp_d >= 300) as lcp_melhorou,
         (m.ni_a >= 30 and m.ni_d >= 30 and m.inp_d <= m.inp_a * 0.8 and m.inp_a - m.inp_d >= 100) as inp_melhorou
  from medidas m)
select jsonb_build_object('rodadas', coalesce((
  select jsonb_agg(jsonb_build_object(
           'pagina', pagina, 'inicio', radar.ms(ini), 'fim', radar.ms(fim), 'publicacoes', n, 'resumo', resumo, 'dispositivo', dispositivo,
           'antes', jsonb_build_object('lcp', lcp_a, 'medidas', n_a, 'inp', inp_a, 'medidas_inp', ni_a),
           'depois', jsonb_build_object('lcp', lcp_d, 'medidas', n_d, 'inp', inp_d, 'medidas_inp', ni_d),
           'horas_depois', round(extract(epoch from depois_ate - fim) / 3600.0, 1), 'proxima', radar.ms(proxima),
           'ultima', proxima is null,
           'veredito', case when not da_para then 'pouco_dado'
                            when lcp_piorou or inp_piorou then 'piorou'
                            when lcp_melhorou or inp_melhorou then 'melhorou' else 'igual' end,
           'piorou_em', case when lcp_piorou and inp_piorou then 'lcp_inp' when lcp_piorou then 'lcp' when inp_piorou then 'inp' end)
         order by ini desc, pagina, dispositivo)
  from julgadas where n_a > 0 or n_d > 0), '[]'::jsonb))
$$;


--
-- Name: api_inicio(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_inicio(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
cfg as (select config from radar.projetos where id = f ->> 'projeto'),
tipos as (
  select pg ->> 'id' as id, pg ->> 'tipo' as tipo
  from cfg, jsonb_array_elements(coalesce(cfg.config -> 'paginas', '[]'::jsonb)) pg),
-- todas as visitas dos 9 dias (inclusive teste, escondida e equipe): a conta usa so as que valem; a linha de coleta e o
-- "fora da conta" olham o resto
b as materialized (
  select s.dia, s.lead, s.utm_source, s.utm_content, s.recebido_em, s.teste, s.interna, coalesce(s.visivel_ms, 0) > 0 as viu,
         radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u, coalesce(t.tipo, '') as tipo
  from radar.sessoes s left join tipos t on t.id = s.primeira_pagina
  where s.projeto = f ->> 'projeto' and s.dia between radar.hoje() - 8 and radar.hoje()),
s as materialized (select * from b where viu and (coalesce(f ->> 'teste', '') = '1' or not teste)),
dias as (select g::date as dia from generate_series(radar.hoje() - 8, radar.hoje(), interval '1 day') g),
pd as (
  select d.dia,
         count(distinct s.u) as visitas,
         count(distinct s.u) filter (where s.tipo = 'captura') as captura,
         count(distinct s.u) filter (where s.tipo = 'obrigado') as direto_obrigado,
         count(distinct s.u) filter (where s.lead) as leads,
         count(distinct s.u) filter (where s.lead and s.tipo = 'captura') as leads_captura
  from dias d left join s on s.dia = d.dia
  group by d.dia),
dia_json as (
  select dia, jsonb_build_object('dia', dia::text, 'visitas', visitas, 'captura', captura, 'direto_obrigado', direto_obrigado,
                                 'leads', leads, 'leads_captura', leads_captura) as j
  from pd),
-- cada anuncio de ontem, e por lugar onde apareceu (o mesmo anuncio roda no Instagram e no Facebook). A unidade ja leva o
-- anuncio: quem viu pelo Instagram e pelo Facebook conta uma vez no anuncio
ads_lugar as (
  select utm_content as id, coalesce(utm_source, '(direto)') as origem, count(distinct u) filter (where tipo = 'captura') as e
  from s where dia = radar.hoje() - 1 and utm_content is not null group by 1, 2),
ads as (
  select a.id, a.e, a.l, (select jsonb_object_agg(x.origem, x.e) filter (where x.e > 0) from ads_lugar x where x.id = a.id) as origens
  from (select utm_content as id, (count(distinct u) filter (where tipo = 'captura'))::int as e,
               (count(distinct u) filter (where lead and tipo = 'captura'))::int as l
        from s where dia = radar.hoje() - 1 and utm_content is not null group by 1) a),
cand as (select * from ads where e >= 30),
melhor as (select * from cand order by l::float / e desc, e desc, id limit 1),
pior as (select * from cand order by l::float / e asc, e desc, id limit 1),
-- teste de duas proporcoes entre o melhor e o pior (a tela chama de confiavel acima de 1,96)
teste as (
  select case when m.id = w.id or m.l + w.l = 0 or m.l + w.l = m.e + w.e then null
              else ((m.l::float / m.e) - (w.l::float / w.e))
                   / sqrt(((m.l + w.l)::float / (m.e + w.e)) * (1 - (m.l + w.l)::float / (m.e + w.e)) * (1.0 / m.e + 1.0 / w.e)) end as z
  from melhor m, pior w),
anuncio_json as (select id, jsonb_build_object('id', id, 'e', e, 'l', l, 'origens', origens) as j from cand),
-- o que ficou fora da conta, em sessoes do dia: carga que nunca apareceu e visitas da equipe
fora as (
  select dia, count(*) filter (where not viu and not interna and (coalesce(f ->> 'teste', '') = '1' or not teste)) as escondidas,
         count(*) filter (where interna and (coalesce(f ->> 'teste', '') <> '1' or not viu)) as equipe
  from b where dia >= radar.hoje() - 1 group by dia)
select jsonb_build_object(
  'hoje_dia', radar.hoje()::text,
  'coleta', (select jsonb_build_object('ultima', radar.ms(max(recebido_em)),
                                       'minutos', floor(extract(epoch from (now() - max(recebido_em))) / 60)::int)
             from b where coalesce(f ->> 'teste', '') = '1' or not teste),
  'ontem', (select j from dia_json where dia = radar.hoje() - 1),
  'semana_passada', (select j from dia_json where dia = radar.hoje() - 8),
  'hoje', (select j || jsonb_build_object('ultima', (select radar.ms(max(recebido_em)) from s where dia = radar.hoje()))
           from dia_json where dia = radar.hoje()),
  'media7', (select jsonb_build_object('dias_com_dado', count(*) filter (where captura > 0),
                                       'captura', round(avg(captura) filter (where captura > 0)),
                                       'leads_captura', round(avg(leads_captura) filter (where captura > 0), 1))
             from pd where dia between radar.hoje() - 8 and radar.hoje() - 2),
  'serie', (select jsonb_agg(j order by dia) from dia_json),
  'origens_ontem', coalesce((
     select jsonb_agg(jsonb_build_object('origem', origem, 'captura', captura, 'leads', leads) order by captura desc)
     from (select coalesce(utm_source, '(direto)') as origem, count(distinct u) filter (where tipo = 'captura') as captura,
                  count(distinct u) filter (where lead and tipo = 'captura') as leads
           from s where dia = radar.hoje() - 1 group by 1 order by 2 desc limit 6) x), '[]'::jsonb),
  'anuncios', jsonb_build_object(
     'melhor', (select a.j from anuncio_json a join melhor m on m.id = a.id),
     'pior', (select a.j from anuncio_json a join pior w on w.id = a.id),
     'z', (select round(z::numeric, 2) from teste),
     'candidatos', (select count(*) from cand),
     'total', (select count(*) from ads)),
  'fora_da_conta', jsonb_build_object(
     'ontem', (select jsonb_build_object('escondidas', coalesce(max(escondidas), 0), 'equipe', coalesce(max(equipe), 0)) from fora where dia = radar.hoje() - 1),
     'hoje', (select jsonb_build_object('escondidas', coalesce(max(escondidas), 0), 'equipe', coalesce(max(equipe), 0)) from fora where dia = radar.hoje())))
$$;


--
-- Name: api_insights(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_insights(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
s as materialized (select * from radar.filtradas(f)),
-- raiva e mortos, e os cliques automaticos (so para a contagem da aba "De fora")
cl as materialized (
  select c.* from radar.cliques c join s on s.id = c.sessao
  where (c.raiva or c.morto or c.automatico)
    and c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)),
-- os erros do recorte com a origem (025); os de fora ganham o tipo pela regra, com os dominios do projeto
er as materialized (
  select e.pagina, e.mensagem, e.arquivo, e.linha, e.sessao, e.origem from radar.erros e join s on s.id = e.sessao),
fora as materialized (
  select er.pagina, er.mensagem, er.sessao,
         coalesce(radar.erro_de_fora_tipo(er.mensagem, er.arquivo, (select p.dominios from radar.projetos p where p.id = f ->> 'projeto')), 'outro') as tipo
  from er where er.origem = 'fora')
select jsonb_build_object(
  'raiva', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'sel', seletor, 'txt', txt, 'n', n, 'sessoes', ses) order by n desc)
     from (select pagina, seletor, max(texto) as txt, count(*) as n, count(distinct sessao) as ses
           from cl where raiva and not automatico group by 1, 2 order by n desc limit 20) x), '[]'::jsonb),
  'mortos', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'sel', seletor, 'txt', txt, 'n', n, 'sessoes', ses) order by n desc)
     from (select pagina, seletor, max(texto) as txt, count(*) as n, count(distinct sessao) as ses
           from cl where morto and not automatico group by 1, 2 order by n desc limit 20) x), '[]'::jsonb),
  -- so os erros da pagina (os de fora vem em erros_fora)
  'erros', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'msg', mensagem, 'onde', onde, 'n', n, 'sessoes', ses) order by n desc)
     from (select pagina, mensagem, max(jsonb_build_object('arq', coalesce(arquivo, ''), 'linha', coalesce(linha, 0))::text) as onde,
                  count(*) as n, count(distinct sessao) as ses
           from er where origem = 'pagina' group by 1, 2 order by n desc limit 20) x), '[]'::jsonb),
  -- os de fora por tipo: o nome da tela, quantas vezes, em quantas sessoes, a mensagem mais comum e as paginas
  'erros_fora', coalesce((
     select jsonb_agg(jsonb_build_object('tipo', tipo, 'nome', radar.erro_de_fora_nome(tipo), 'n', n, 'sessoes', ses, 'msg', msg,
                                         'paginas', to_jsonb(pgs)) order by n desc)
     from (select tipo, count(*) as n, count(distinct sessao) as ses, mode() within group (order by mensagem) as msg,
                  array_agg(distinct pagina order by pagina) as pgs
           from fora group by tipo) x), '[]'::jsonb),
  'contagem_erros', (
     select jsonb_build_object(
              'pagina', jsonb_build_object('n', count(*) filter (where origem = 'pagina'), 'sessoes', count(distinct sessao) filter (where origem = 'pagina')),
              'fora', jsonb_build_object('n', count(*) filter (where origem = 'fora'), 'sessoes', count(distinct sessao) filter (where origem = 'fora')))
     from er),
  'cliques_automaticos', (select jsonb_build_object('n', count(*), 'sessoes', count(distinct sessao)) from cl where automatico),
  'saidas', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'visitas', n, 'rapidas', r, 'rolagem', rol) order by n desc)
     from (select v.pagina, count(*) as n, count(*) filter (where v.visivel_ms < 3000) as r, round(avg(v.rolagem), 1) as rol
           from radar.visualizacoes v join s on s.id = v.sessao group by 1) x), '[]'::jsonb))
$$;


--
-- Name: api_laboratorio(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_laboratorio(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('historico', coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'url', url, 'estrategia', estrategia, 'nota', nota, 'notas', notas, 'lcp_ms', lcp_ms, 'fcp_ms', fcp_ms,
           'tbt_ms', tbt_ms, 'si_ms', si_ms, 'cls', cls, 'medido_em', radar.ms(medido_em), 'tem_relatorio', relatorio is not null)
           order by medido_em desc, id desc), '[]'::jsonb))
    from radar.velocidade_lab
   where projeto = f ->> 'projeto' and pagina = f ->> 'pagina'
$$;


--
-- Name: api_leads_mql(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_leads_mql(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
-- so as colunas que a tela usa; u = a visita unica, em ordem "C" (contar diferentes fica barato); nu = quantas sessoes
-- a unidade tem no recorte (quase sempre 1: ai contar sessoes ja e contar unidades)
s as materialized (
  select y.*, count(*) over (partition by y.u) as nu
  from (select x.id, radar.unidade(x.visitante, x.ad_id, x.utm_content) collate "C" as u, x.projeto, x.visitante, x.inicio, x.fim,
               x.dispositivo, x.app, x.lead, x.resultado, x.paginas, x.cliques, x.raiva, x.utm_source, x.utm_campaign, x.utm_content,
               x.primeira_pagina
        from radar.filtradas(f) x) y),
-- a pagina de entrada de cada sessao, o tempo ativo somado e o caminho
pv as materialized (
  select v.sessao,
         max(v.rolagem) filter (where v.ordem = 1) as rolagem,
         max(v.rolagem_30s) filter (where v.ordem = 1) as rolagem_30s,
         max(v.lcp_ms) filter (where v.ordem = 1) as lcp_ms,
         sum(coalesce(v.ativo_ms, 0)) as ativo_ms, bool_or(v.ativo_ms is not null) as tem_ativo,
         array_agg(v.pagina order by v.ordem) as caminho
  from radar.visualizacoes v join s on s.id = v.sessao group by v.sessao),
-- o primeiro clique e o primeiro clique num botao (data-cta) de cada sessao
cq as (
  select c.sessao, min(c.quando) as primeiro, min(c.quando) filter (where c.seletor like '%data-cta=%') as primeiro_cta
  from radar.cliques c join s on s.id = c.sessao
  where c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)
  group by c.sessao),
-- "voltou": o mesmo navegador ja tinha uma visita que apareceu antes desta
base as materialized (
  select s.id, s.u, s.nu, s.projeto, s.visitante, s.inicio, s.fim, s.dispositivo, s.app, s.lead, (s.resultado = 'mql') is true as mql,
         s.paginas, s.cliques, s.raiva, s.utm_source, s.utm_campaign, s.utm_content, s.primeira_pagina,
         pv.rolagem, pv.rolagem_30s, pv.lcp_ms, pv.ativo_ms, coalesce(pv.tem_ativo, false) as tem_ativo, pv.caminho,
         (cq.primeiro is not null and cq.primeiro <= s.inicio + interval '30 seconds') as clicou_30,
         (cq.primeiro_cta is not null and cq.primeiro_cta <= s.inicio + interval '30 seconds') as cta_30,
         exists (select 1 from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante and x.inicio < s.inicio
                                                 and coalesce(x.visivel_ms, 0) > 0) as voltou
  from s left join pv on pv.sessao = s.id left join cq on cq.sessao = s.id),
-- cada sessao em ate 3 grupos (todos; lead ou nao; MQL ou lead que nao qualificou)
gb as materialized (
  select g.grupo, b.*
  from base b
  cross join lateral (values ('todos'), (case when b.lead then 'lead' else 'nao_lead' end),
                             (case when b.mql then 'mql' when b.lead then 'lead_nao_mql' end)) g(grupo)
  where g.grupo is not null),
-- a visita tipica de cada grupo (medianas e medias): por sessao; sessoes_brutas = as sessoes
gs as (
  select grupo, count(*) as sessoes_brutas,
         round(percentile_cont(0.5) within group (order by extract(epoch from (fim - inicio)) * 1000)) as duracao_ms,
         round(percentile_cont(0.5) within group (order by ativo_ms) filter (where tem_ativo)) as ativo_ms,
         round(avg(rolagem), 1) as rolagem, round(avg(paginas), 2) as paginas, round(avg(cliques), 2) as cliques
  from gb group by grupo),
-- quantas visitas unicas em cada grupo, e quantas delas tiveram raiva, ja tinham vindo, estavam no celular ou num app
-- (a unidade tem o sinal se alguma sessao dela no grupo tem). Mesmo resultado de count(distinct) com filtro, mais barato:
-- unidade de uma sessao so conta direto; so as de varias sessoes viram uma linha por grupo e unidade (bool_or) antes
gu as (
  select grupo, sum(n)::bigint as sessoes, sum(raiva)::bigint as com_raiva, sum(voltou)::bigint as voltaram,
         sum(celular)::bigint as celular, sum(em_app)::bigint as em_app
  from (select grupo, count(*) as n, count(*) filter (where raiva > 0) as raiva, count(*) filter (where voltou) as voltou,
               count(*) filter (where dispositivo = 'mobile') as celular, count(*) filter (where app is not null) as em_app
        from gb where nu = 1 group by grupo
        union all
        select grupo, count(*), count(*) filter (where raiva), count(*) filter (where voltou), count(*) filter (where celular),
               count(*) filter (where em_app)
        from (select grupo, u, bool_or(raiva > 0) as raiva, bool_or(voltou) as voltou, bool_or(dispositivo = 'mobile') as celular,
                     bool_or(app is not null) as em_app
              from gb where nu > 1 group by grupo, u) x
        group by grupo) y
  group by grupo),
grupos as (
  select gs.grupo, gu.sessoes, gs.sessoes_brutas, gs.duracao_ms, gs.ativo_ms, gs.rolagem, gs.paginas, gs.cliques,
         gu.com_raiva, gu.voltaram, gu.celular, gu.em_app
  from gs join gu on gu.grupo = gs.grupo),
-- sinais do comeco da visita: quem tem o sinal converte mais do que quem nao tem? (em visitas unicas, do mesmo jeito)
bx as not materialized (
  select x.sinal, x.tem, b.u, b.nu, b.lead, b.mql
  from base b
  cross join lateral (values ('rolou_30', b.rolagem_30s >= 25), ('clicou_30', b.clicou_30), ('cta_30', b.cta_30),
                             ('rapida', b.lcp_ms <= 2500), ('voltou', b.voltou), ('celular', b.dispositivo = 'mobile'),
                             ('em_app', b.app is not null)) x(sinal, tem)
  where x.tem is not null),
sinais as (
  select sinal, tem, sum(n)::bigint as sessoes, sum(l)::bigint as leads, sum(m)::bigint as mql
  from (select sinal, tem, count(*) as n, count(*) filter (where lead) as l, count(*) filter (where mql) as m
        from bx where nu = 1 group by 1, 2
        union all
        select sinal, tem, count(*), count(*) filter (where lead), count(*) filter (where mql)
        from (select sinal, tem, u, bool_or(lead) as lead, bool_or(mql) as mql from bx where nu > 1 group by 1, 2, 3) z
        group by 1, 2) y
  group by 1, 2),
-- a jornada de quem virou lead no periodo: a primeira visita daquele navegador (quem abre) e a que converteu (quem fecha).
-- Por pessoa (navegador), de proposito: a jornada pode passar por varios anuncios. So visitas que apareceram
ld as (select distinct on (b.visitante) b.* from base b where b.lead order by b.visitante, b.inicio),
jor as materialized (
  select ld.id, ld.mql, ld.inicio,
         coalesce(ld.utm_source, '(direto)') as f_origem, coalesce(ld.utm_campaign, '') as f_campanha, coalesce(ld.utm_content, '') as f_criativo,
         coalesce(p.utm_source, '(direto)') as a_origem, coalesce(p.utm_campaign, '') as a_campanha, coalesce(p.utm_content, '') as a_criativo,
         p.inicio as a_inicio,
         (select count(*) from radar.sessoes x where x.projeto = ld.projeto and x.visitante = ld.visitante and x.inicio <= ld.inicio
                                               and coalesce(x.visivel_ms, 0) > 0) as visitas
  from ld
  cross join lateral (select x.utm_source, x.utm_campaign, x.utm_content, x.inicio from radar.sessoes x
                      where x.projeto = ld.projeto and x.visitante = ld.visitante and x.inicio <= ld.inicio
                        and coalesce(x.visivel_ms, 0) > 0 order by x.inicio limit 1) p)
select jsonb_build_object(
  'grupos', coalesce((select jsonb_object_agg(grupo, to_jsonb(g) - 'grupo') from grupos g), '{}'::jsonb),
  'sinais', coalesce((select jsonb_agg(jsonb_build_object('sinal', sinal, 'tem', tem, 'sessoes', sessoes, 'leads', leads, 'mql', mql) order by sinal, tem desc) from sinais), '[]'::jsonb),
  'caminhos', jsonb_build_object(
     'lead', coalesce((select jsonb_agg(jsonb_build_object('caminho', to_jsonb(caminho), 'sessoes', n) order by n desc)
                       from (select caminho, count(*) as n from (select distinct caminho, u from base where lead and caminho is not null) y group by 1 order by n desc limit 6) x), '[]'::jsonb),
     'mql', coalesce((select jsonb_agg(jsonb_build_object('caminho', to_jsonb(caminho), 'sessoes', n) order by n desc)
                      from (select caminho, count(*) as n from (select distinct caminho, u from base where mql and caminho is not null) y group by 1 order by n desc limit 6) x), '[]'::jsonb),
     'nao_lead', coalesce((select jsonb_agg(jsonb_build_object('caminho', to_jsonb(caminho), 'sessoes', n) order by n desc)
                           from (select caminho, count(*) as n from (select distinct caminho, u from base where not lead and caminho is not null) y group by 1 order by n desc limit 6) x), '[]'::jsonb)),
  'jornada', jsonb_build_object(
     'leads', (select count(*) from jor),
     'mql', (select count(*) from jor where mql),
     'visitas', (select jsonb_build_array(count(*) filter (where visitas = 1), count(*) filter (where visitas = 2),
                                          count(*) filter (where visitas = 3), count(*) filter (where visitas >= 4)) from jor),
     'dias', (select jsonb_build_array(count(*) filter (where inicio - a_inicio < interval '1 day'),
                                       count(*) filter (where inicio - a_inicio >= interval '1 day' and inicio - a_inicio < interval '4 days'),
                                       count(*) filter (where inicio - a_inicio >= interval '4 days' and inicio - a_inicio < interval '8 days'),
                                       count(*) filter (where inicio - a_inicio >= interval '8 days')) from jor),
     'trocaram', (select count(*) from jor where visitas > 1 and (a_origem, a_campanha, a_criativo) is distinct from (f_origem, f_campanha, f_criativo)),
     'abre', coalesce((select jsonb_agg(jsonb_build_object('origem', a_origem, 'campanha', a_campanha, 'criativo', a_criativo, 'leads', n, 'mql', m, 'depois', d) order by n desc)
                       from (select a_origem, a_campanha, a_criativo, count(*) as n, count(*) filter (where mql) as m, count(*) filter (where visitas > 1) as d
                             from jor group by 1, 2, 3 order by n desc limit 10) x), '[]'::jsonb),
     'fecha', coalesce((select jsonb_agg(jsonb_build_object('origem', f_origem, 'campanha', f_campanha, 'criativo', f_criativo, 'leads', n, 'mql', m, 'depois', d) order by n desc)
                        from (select f_origem, f_campanha, f_criativo, count(*) as n, count(*) filter (where mql) as m, count(*) filter (where visitas > 1) as d
                              from jor group by 1, 2, 3 order by n desc limit 10) x), '[]'::jsonb)))
$$;


--
-- Name: api_leads_paginas(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_leads_paginas(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
q as (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate),
srv as (
  select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, x.pagina_primeira as pagina, nullif(x.plataforma, '') as plataforma,
         count(*)::int as n,
         -- 060: o MQL e quem respondeu a pesquisa (como estao hoje), para o Inicio e o Diario
         (count(*) filter (where x.mql = 'sim'))::int as mql,
         (count(*) filter (where x.mql in ('sim', 'nao')))::int as resp
  from radar_crm.pessoas x, q
  where x.projeto = f ->> 'projeto' and not x.teste
    and (x.primeiro_em at time zone 'America/Sao_Paulo')::date between q.de and q.ate
    and (coalesce(f ->> 'pagina', '') = '' or x.pagina_primeira = f ->> 'pagina')
    and radar.canal_crm(nullif(x.plataforma, ''), f ->> 'canal')
    -- 041: origem, campanha e anuncio, pela origem do primeiro clique (os mesmos filtros da visita)
    and radar.casa(nullif(x.origem_primeira ->> 'utm_source', ''), f ->> 'utm_source')
    and radar.casa(nullif(x.origem_primeira ->> 'utm_campaign', ''), f ->> 'utm_campaign')
    and radar.casa(nullif(x.origem_primeira ->> 'utm_content', ''), f ->> 'utm_content')
  group by 1, 2, 3),
nav as (
  select s.dia, s.primeira_pagina as pagina,
         (count(distinct radar.unidade(s.visitante, s.ad_id, s.utm_content)) filter (where s.lead))::int as leads,
         count(distinct radar.unidade(s.visitante, s.ad_id, s.utm_content))::int as visitas
  from radar.filtradas(f) s
  group by 1, 2)
select jsonb_build_object(
  'de', q.de::text, 'ate', q.ate::text,
  'crm', exists (select 1 from radar_crm.pessoas x where x.projeto = f ->> 'projeto' and not x.teste),
  'desde', radar.crm_desde(f ->> 'projeto')::text,   -- 042: o primeiro dia com o volume de verdade
  'servidor', coalesce((select jsonb_agg(jsonb_build_object('dia', s.dia::text, 'pagina', s.pagina, 'plataforma', s.plataforma, 'n', s.n,
                                                              'mql', s.mql, 'resp', s.resp)
                                         order by s.dia, s.pagina, s.plataforma) from srv s), '[]'::jsonb),
  'navegador', coalesce((select jsonb_agg(jsonb_build_object('dia', n.dia::text, 'pagina', n.pagina, 'leads', n.leads, 'visitas', n.visitas) order by n.dia, n.pagina)
                         from nav n), '[]'::jsonb))
from q
$$;


--
-- Name: api_leitura(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_leitura(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
s as materialized (select * from radar.filtradas(f)),
cfg as (select array(select jsonb_array_elements_text(coalesce(config -> 'eventos_lead', '[]'::jsonb))) as leads from radar.projetos where id = f ->> 'projeto'),
m as (select coalesce(pm.secoes, '{}') as secoes, coalesce(pm.ctas, '{}') as ctas, coalesce(pm.campos, '{}') as campos
      from (select 1) um left join radar.paginas_mapa pm on pm.projeto = f ->> 'projeto' and pm.pagina = f ->> 'pagina_alvo'),
b as materialized (
  select v.id, v.sessao, v.inicio, v.visivel_ms, v.secoes, v.ctas, v.form, s.dispositivo, s.lead, (s.resultado = 'mql') is true as mql,
         -- a visita unica (radar.unidade da 021): a mesma pessoa pelo mesmo anuncio, ou sem anuncio, conta 1
         s.visitante || '|' || coalesce(nullif(s.ad_id, ''), nullif(s.utm_content, ''), '') as unidade
  from radar.visualizacoes v join s on s.id = v.sessao
  -- a visita que nunca apareceu na tela fica fora; o projeto deixa o banco ir direto pelo indice da pagina
  where v.projeto = f ->> 'projeto' and v.pagina = f ->> 'pagina_alvo' and coalesce(s.visivel_ms, 0) > 0),
-- o momento (no relogio do navegador, o mesmo dos cliques) em que cada sessao virou lead
lead_ev as (
  select e.sessao, min(e.quando) as quando
  from radar.eventos_funil e join s on s.id = e.sessao cross join cfg
  where e.projeto = f ->> 'projeto' and e.nome = any (cfg.leads) group by e.sessao),
-- secoes: uma linha por pagina vista e secao em que a pessoa parou 1 s ou mais
sv as materialized (
  select b.id, b.lead, b.mql, e.key as secao, radar.inteiro(e.value, 0) as seg, coalesce(array_position(m.secoes, e.key), 999) as ordem
  from b cross join m cross join lateral jsonb_each_text(b.secoes) e
  where b.secoes is not null),
fundo as (select id, max(ordem) filter (where ordem < 999) as ate from sv group by id),
nomes_s as (
  select secao, min(ordem) as ordem
  from (select x.secao, x.o::int as ordem from m, unnest(m.secoes) with ordinality x(secao, o)
        union all select secao, ordem from sv) y
  group by secao),
-- botoes: se apareceram na tela, quem clicou e o ultimo clicado antes de virar lead
cv as materialized (
  select b.id, e.key as cta, radar.inteiro(e.value, 0) as visto
  from b cross join lateral jsonb_each_text(b.ctas) e where b.ctas is not null),
cl as materialized (
  select c.sessao, c.quando, substring(c.seletor from 'data-cta="([^"]+)"') as cta
  from radar.cliques c join s on s.id = c.sessao
  where c.pagina = f ->> 'pagina_alvo' and c.seletor like '%data-cta=%'
    and c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)),
ult as (
  select distinct on (cl.sessao) cl.sessao, cl.cta
  from cl join lead_ev le on le.sessao = cl.sessao cross join m
  where cl.cta = any (m.ctas) and cl.quando <= le.quando + interval '2 seconds'
  order by cl.sessao, cl.quando desc),
nomes_c as (
  select cta, min(ordem) as ordem
  from (select x.cta, x.o::int as ordem from m, unnest(m.ctas) with ordinality x(cta, o)
        union all select cta, 999 from cv) y
  group by cta),
-- o primeiro botao da pagina, por pagina vista: apareceu? a pessoa ficou (10 s ou mais na tela)?
pc as (
  select b.dispositivo, b.lead, (b.visivel_ms >= 10000) as ficou, radar.inteiro(b.ctas ->> m.ctas[1], 0) > 0 as viu
  from b cross join m where b.ctas is not null and cardinality(m.ctas) > 0),
-- formulario: as paginas vistas em que a pagina avisou que abriu o formulario
ab as (
  select distinct e.visualizacao as id
  from radar.eventos_funil e join s on s.id = e.sessao
  where e.projeto = f ->> 'projeto' and e.nome in ('abriu_formulario', 'abriu_form', 'form_aberto', 'formulario_aberto')
    and e.pagina = f ->> 'pagina_alvo'),
-- uma linha por pagina vista e campo (os numeros do campo; o valor digitado nunca chega ao banco)
fc0 as materialized (
  select b.id, c.key as campo, radar.inteiro(c.value ->> 0, 0) as focos, radar.inteiro(c.value ->> 1, 0) as seg,
         radar.inteiro(c.value ->> 2, 0) as preenchido, radar.inteiro(c.value ->> 3, 0) as erros
  from b cross join lateral jsonb_each(case when jsonb_typeof(b.form -> 'c') = 'object' then b.form -> 'c' else '{}'::jsonb end) c
  where b.form is not null),
fcs as (select id, bool_or(preenchido > 0 or erros > 0) as mexeu, bool_or(focos > 0) as entrou from fc0 group by id),
-- os sinais de cada pagina vista: viu, abriu, mexeu (preencheu ou errou), entrou em campo, virou lead depois de abrir
fs as (
  select b.id, b.inicio, b.unidade, b.dispositivo, radar.inteiro(b.form ->> 't', 0) as tempo, b.form ->> 'u' as ultimo,
         radar.inteiro(b.form ->> 'v', 0) > 0 as viu, ab.id is not null as abriu,
         coalesce(fcs.mexeu, false) as mexeu, coalesce(fcs.entrou, false) as entrou,
         coalesce(le.quando >= b.inicio - interval '5 seconds', false) as lead_depois
  from b left join ab on ab.id = b.id left join fcs on fcs.id = b.id left join lead_ev le on le.sessao = b.sessao
  where b.form is not null),
-- o degrau de cada pagina vista: 4 enviou, 3 comecou, 2 abriu, 1 viu, 0 so tinha campo na pagina (escondido)
fm as materialized (
  select fs.*,
         case when fs.lead_depois and (fs.viu or fs.abriu or fs.mexeu or fs.entrou) then 4
              when fs.mexeu then 3
              when fs.abriu or fs.entrou then 2
              when fs.viu then 1
              else 0 end as nivel
  from fs),
-- a visita unica fica com a pagina vista em que foi mais longe (no empate, a mais recente)
fu as materialized (
  select distinct on (unidade) unidade, dispositivo, nivel, ultimo
  from fm order by unidade, nivel desc, inicio desc),
-- tocou: preencheu, deu erro ou entrou no campo numa pagina vista em que comecou (o foco que a pagina da sozinha nao conta)
fct as (
  select fm.unidade, fc0.campo, fc0.focos, fc0.seg, fc0.preenchido, fc0.erros,
         (fc0.preenchido > 0 or fc0.erros > 0 or (fc0.focos > 0 and fm.nivel >= 3)) as tocou
  from fc0 join fm on fm.id = fc0.id),
campos_a as (
  select campo, count(distinct unidade) filter (where tocou) as tocaram, count(distinct unidade) filter (where focos > 0) as focaram,
         count(distinct unidade) filter (where preenchido > 0) as preencheram, count(distinct unidade) filter (where erros > 0) as com_erro,
         round(avg(seg) filter (where tocou), 1) as tempo
  from fct group by campo),
parou as (select ultimo as campo, count(*) as n from fu where nivel = 3 and coalesce(ultimo, '') <> '' group by ultimo),
nomes_f as (
  select y.campo, min(y.ordem) as ordem
  from (select x.campo, x.o::int as ordem from m, unnest(m.campos) with ordinality x(campo, o)
        union all select campo, 999 from campos_a union all select campo, 999 from parou) y
  where exists (select 1 from campos_a a where a.campo = y.campo and a.tocaram > 0) or exists (select 1 from parou p where p.campo = y.campo)
  group by y.campo)
select jsonb_build_object(
  'pagina', f ->> 'pagina_alvo',
  'visitas', (select count(*) from b),
  -- secoes
  'medidas', (select count(*) from b where secoes is not null),
  'medidas_lead', (select count(*) from b where secoes is not null and lead),
  'medidas_mql', (select count(*) from b where secoes is not null and mql),
  'medidas_nao_lead', (select count(*) from b where secoes is not null and not lead),
  'secoes', coalesce((
     select jsonb_agg(jsonb_build_object(
              'secao', n.secao, 'ordem', n.ordem, 'viram', coalesce(a.viram, 0), 'tempo_s', coalesce(a.tempo, 0),
              'chegaram', (select count(*) from fundo x where x.ate >= n.ordem),
              'viram_lead', coalesce(a.vl, 0), 'viram_mql', coalesce(a.vm, 0), 'viram_nao_lead', coalesce(a.vn, 0))
            order by n.ordem, n.secao)
     from nomes_s n
     left join (select secao, count(*) as viram, round(avg(seg), 1) as tempo, count(*) filter (where lead) as vl,
                       count(*) filter (where mql) as vm, count(*) filter (where not lead) as vn
                from sv group by secao) a on a.secao = n.secao), '[]'::jsonb),
  -- botoes
  'medidas_ctas', (select count(*) from b where ctas is not null),
  'primeiro_cta', coalesce((
     select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'medidas', n, 'viram', viu, 'ficaram', ficaram,
                                         'ficaram_sem_ver', sem_ver, 'leads_de_quem_viu', leads_viu) order by n desc)
     from (select dispositivo, count(*) as n, count(*) filter (where viu) as viu, count(*) filter (where ficou) as ficaram,
                  count(*) filter (where ficou and not viu) as sem_ver, count(*) filter (where ficou and viu and lead) as leads_viu
           from pc group by 1) x), '[]'::jsonb),
  'ctas', coalesce((
     select jsonb_agg(jsonb_build_object(
              'cta', n.cta, 'ordem', n.ordem, 'medidas', coalesce(a.medidas, 0), 'viram', coalesce(a.viram, 0),
              'clicaram', (select count(distinct sessao) from cl where cl.cta = n.cta),
              'leads', (select count(*) from ult where ult.cta = n.cta))
            order by n.ordem, n.cta)
     from nomes_c n
     left join (select cta, count(*) as medidas, count(*) filter (where visto > 0) as viram from cv group by cta) a on a.cta = n.cta), '[]'::jsonb),
  'leads_com_botao', (select count(*) from ult),
  -- formulario: quatro degraus por visita unica e os campos que alguem tocou
  'form', jsonb_build_object(
     'medidas', (select count(*) from fm),
     'visitas_unicas', (select count(distinct unidade) from b),
     'viram', (select count(*) from fu where nivel >= 1),
     'abriram', (select count(*) from fu where nivel >= 2),
     'comecaram', (select count(*) from fu where nivel >= 3),
     'enviaram', (select count(*) from fu where nivel >= 4),
     'tempo_mediano_s', (select percentile_disc(0.5) within group (order by tempo) from fm where nivel = 4),
     'por_aparelho', coalesce((
        select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'viram', v, 'abriram', a, 'comecaram', c, 'enviaram', e) order by v desc, dispositivo)
        from (select dispositivo, count(*) filter (where nivel >= 1) as v, count(*) filter (where nivel >= 2) as a,
                     count(*) filter (where nivel >= 3) as c, count(*) filter (where nivel >= 4) as e
              from fu group by 1) x where v > 0), '[]'::jsonb),
     'campos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'campo', n.campo, 'ordem', n.ordem, 'tocaram', coalesce(a.tocaram, 0), 'focaram', coalesce(a.focaram, 0),
                 'preencheram', coalesce(a.preencheram, 0), 'com_erro', coalesce(a.com_erro, 0), 'tempo_s', coalesce(a.tempo, 0),
                 'pararam', coalesce(p.n, 0))
               order by n.ordem, n.campo)
        from nomes_f n
        left join campos_a a on a.campo = n.campo
        left join parou p on p.campo = n.campo), '[]'::jsonb)))
$$;


--
-- Name: api_mapa(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_mapa(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
ff as (select f || jsonb_build_object(
                'dispositivo', coalesce(nullif(f ->> 'dispositivo', ''), 'mobile'),
                'pagina_mapa', coalesce(nullif(f ->> 'pagina_mapa', ''), f ->> 'pagina_alvo', '')) as f),
alvo as (select (select f from ff) ->> 'pagina_mapa' as pg),
s as materialized (select * from radar.filtradas((select f from ff))),
vv as materialized (
  select v.* from radar.visualizacoes v join s on s.id = v.sessao
  where v.projeto = f ->> 'projeto' and v.pagina = (select pg from alvo)),
-- cada clique com a altura da pagina da visita em que aconteceu (busca pela chave da pagina vista); o clique automatico
-- (025) fica fora de tudo: pontos, contagem e os mais clicados
cl as materialized (
  select c.id, c.x_pct, c.y_px, c.seletor, c.texto, c.raiva, c.morto, c.fixo, pv.altura_doc
  from radar.cliques c join s on s.id = c.sessao
  left join radar.visualizacoes pv on pv.id = c.visualizacao
  where c.projeto = f ->> 'projeto' and c.pagina = (select pg from alvo) and not c.automatico
    and c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)),
-- os desenhaveis: fora dos fixos e com a altura da pagina conhecida
des as materialized (select * from cl where not fixo and altura_doc > 0),
-- o dicionario dos elementos dos pontos (um indice por seletor, do mais clicado para o menos)
el as materialized (
  select seletor, max(texto) as txt, (row_number() over (order by count(*) desc, seletor) - 1)::int as i
  from des group by seletor),
pts as materialized (
  select d.x_pct, d.y_px, d.altura_doc, d.raiva, d.morto, e.i
  from (select * from des order by hashtext(id::text) limit 20000) d join el e on e.seletor = d.seletor),
-- 041: os candidatos a fundo, as paginas vistas com video ainda guardado. A tela redesenha a pagina pelo primeiro retrato
-- da gravacao: a visita ainda em andamento ou aberta por meio segundo no app as vezes nao tem esse retrato
fc as materialized (
  select vv.id, vv.sessao, vv.largura, vv.altura_doc, vv.inicio, coalesce(vv.visivel_ms, 0) as vis, radar.encerrada(s.recebido_em) as encerrada
  from vv join s on s.id = vv.sessao
  where vv.gravada and s.inicio > now() - radar.retencao_video(s.projeto)),
-- a largura do meio entre as que ficaram 3 segundos na tela, e a altura do meio entre as dessa largura (15% para cada lado)
fl as (select percentile_disc(0.5) within group (order by largura) as l from fc where vis >= 3000 and largura > 0),
fa as (select percentile_disc(0.5) within group (order by fc.altura_doc) as a
       from fc, fl where fc.vis >= 3000 and fc.altura_doc > 0 and abs(fc.largura - fl.l) <= fl.l * 0.15),
-- as boas: encerradas, 3 segundos na tela, largura e altura perto das do meio; uma por visita, as 5 mais recentes
fb as (
  select * from (
    select distinct on (fc.sessao) fc.* from fc, fl, fa
    where fc.encerrada and fc.vis >= 3000 and abs(fc.largura - fl.l) <= fl.l * 0.15 and abs(fc.altura_doc - fa.a) <= fa.a * 0.25
    order by fc.sessao, fc.inicio desc) x
  order by x.inicio desc limit 5)
select jsonb_build_object(
  'versao', 2,
  'cliques', jsonb_build_object(
     'pontos', coalesce((select jsonb_agg(jsonb_build_array(round(x_pct::numeric, 1), round(least(y_px::numeric / altura_doc, 1), 4),
                                                            raiva::int + 2 * morto::int, i)) from pts), '[]'::jsonb),
     'elementos', coalesce((select jsonb_agg(jsonb_build_array(seletor, txt) order by i) from el), '[]'::jsonb)),
  'contagem', jsonb_build_object(
     'pagina', (select jsonb_build_object('cliques', count(*), 'raiva', count(*) filter (where raiva), 'mortos', count(*) filter (where morto))
                from cl where not fixo),
     'fixos', (select jsonb_build_object('cliques', count(*), 'raiva', count(*) filter (where raiva), 'mortos', count(*) filter (where morto))
               from cl where fixo)),
  'amostra', (select count(*) > 20000 from des),
  'visitas', (select count(*) from vv),
  'rolagem_alcance', (select jsonb_agg((select count(*) from vv where rolagem >= p) order by p) from generate_series(0, 100, 5) p),
  -- 041: o fundo e a visita encerrada mais recente que ficou na tela, na largura e altura comuns; as outras vao junto
  'fundo', coalesce(
     (select jsonb_build_object('id', a.id, 'sessao', a.sessao, 'largura', a.largura, 'altura_doc', a.altura_doc,
               'outros', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'sessao', b.sessao, 'largura', b.largura, 'altura_doc', b.altura_doc)
                                                    order by b.inicio desc)
                                   from fb b where b.id <> a.id), '[]'::jsonb))
      from (select * from fb order by inicio desc limit 1) a),
     (select jsonb_build_object('id', v.id, 'sessao', v.sessao, 'largura', v.largura, 'altura_doc', v.altura_doc)
      from fc v order by v.inicio desc limit 1)),
  'top', coalesce((
     select jsonb_agg(jsonb_build_object('sel', seletor, 'txt', txt, 'n', n, 'raiva', rv, 'morto', mt) order by n desc)
     from (select seletor, max(texto) as txt, count(*) as n, count(*) filter (where raiva) as rv, count(*) filter (where morto) as mt
           from cl where not fixo group by 1 order by n desc limit 15) x), '[]'::jsonb),
  'top_fixos', coalesce((
     select jsonb_agg(jsonb_build_object('sel', seletor, 'txt', txt, 'n', n, 'raiva', rv, 'morto', mt) order by n desc)
     from (select seletor, max(texto) as txt, count(*) as n, count(*) filter (where raiva) as rv, count(*) filter (where morto) as mt
           from cl where fixo group by 1 order by n desc limit 15) x), '[]'::jsonb))
$$;


--
-- Name: api_oportunidades(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_oportunidades(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_base jsonb;
  v_leituras jsonb := '[]'::jsonb;
  v_pubs jsonb := '[]'::jsonb;
  pg record;
begin
  with
  s as materialized (select * from radar.filtradas(f)),
  v as materialized (select v.id, v.sessao, v.pagina, v.ordem, v.lcp_ms from radar.visualizacoes v join s on s.id = v.sessao),
  -- quem passou por cada pagina, e em quantos dias do recorte ela foi vista (a base do "por semana" da tela)
  pass as (
    select v.pagina, count(*) as visitas, count(distinct v.sessao) as sessoes,
           count(distinct v.sessao) filter (where s.lead) as leads, count(distinct v.sessao) filter (where s.resultado = 'mql') as mql,
           count(distinct s.dia) as dias
    from v join s on s.id = v.sessao group by v.pagina),
  -- quem entrou por cada pagina (a visita ainda aberta que nao engajou nao conta)
  ent as materialized (
    select s.primeira_pagina as pagina, s.id, s.dispositivo, s.lead, (s.resultado = 'mql') is true as mql,
           coalesce(s.utm_campaign, '(sem campanha)') as campanha, coalesce(s.utm_content, '') as criativo,
           (s.engajada or radar.encerrada(s.recebido_em)) as conta, (not s.engajada and radar.encerrada(s.recebido_em)) as rejeitou
    from s),
  ent_pg as (
    select pagina, count(*) filter (where conta) as entradas, count(*) filter (where rejeitou) as rejeicoes,
           count(*) filter (where conta and lead) as leads, count(*) filter (where conta and mql) as mql
    from ent group by pagina),
  -- friccao: entre as sessoes engajadas que passaram pela pagina, quem teve clique de raiva ou erro nela (so sinal de
  -- verdade, 025: sem o clique automatico e sem o erro de fora da pagina)
  fr_cl as (
    select c.pagina, c.sessao, bool_or(c.raiva) as raiva, bool_or(c.morto) as morto
    from radar.cliques c join s on s.id = c.sessao
    where (c.raiva or c.morto) and not c.automatico
      and c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)
    group by 1, 2),
  fr_er as (select distinct e.pagina, e.sessao from radar.erros e join s on s.id = e.sessao where e.origem = 'pagina'),
  fr as (
    select p.pagina, s.lead, coalesce(c.raiva, false) as raiva, coalesce(c.morto, false) as morto, (e.sessao is not null) as erro
    from (select distinct pagina, sessao from v) p
    join s on s.id = p.sessao and s.engajada
    left join fr_cl c on c.pagina = p.pagina and c.sessao = p.sessao
    left join fr_er e on e.pagina = p.pagina and e.sessao = p.sessao),
  fr_pg as (
    select pagina,
           count(*) filter (where raiva) as com_raiva, count(*) filter (where raiva and lead) as raiva_leads,
           count(*) filter (where morto) as com_morto, count(*) filter (where morto and lead) as morto_leads,
           count(*) filter (where erro) as com_erro, count(*) filter (where erro and lead) as erro_leads,
           count(*) filter (where raiva or erro) as com_friccao, count(*) filter (where (raiva or erro) and lead) as friccao_leads,
           count(*) filter (where not (raiva or erro)) as sem_friccao, count(*) filter (where not (raiva or erro) and lead) as sem_leads
    from fr group by pagina)
  select jsonb_build_object(
    'sessoes', (select count(*) from s),
    'leads', (select count(*) from s where lead),
    'dias', (select count(distinct dia) from s),
    'paginas', coalesce((
       select jsonb_agg(jsonb_build_object(
                'pagina', p.pagina, 'visitas', p.visitas, 'sessoes', p.sessoes, 'leads', p.leads, 'mql', p.mql, 'dias', p.dias,
                'entradas', coalesce(e.entradas, 0), 'rejeicoes', coalesce(e.rejeicoes, 0),
                'leads_entrada', coalesce(e.leads, 0), 'mql_entrada', coalesce(e.mql, 0),
                'por_aparelho', coalesce((
                   select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'entradas', n, 'rejeicoes', r, 'leads', l) order by n desc)
                   from (select dispositivo, count(*) filter (where conta) as n, count(*) filter (where rejeitou) as r, count(*) filter (where conta and lead) as l
                         from ent where ent.pagina = p.pagina group by 1) x where n > 0), '[]'::jsonb),
                'por_criativo', coalesce((
                   select jsonb_agg(jsonb_build_object('campanha', campanha, 'criativo', criativo, 'entradas', n, 'rejeicoes', r, 'leads', l) order by n desc)
                   from (select campanha, criativo, count(*) filter (where conta) as n, count(*) filter (where rejeitou) as r, count(*) filter (where conta and lead) as l
                         from ent where ent.pagina = p.pagina group by 1, 2 order by 3 desc limit 10) x where n > 0), '[]'::jsonb),
                'friccao', (select to_jsonb(fp) - 'pagina' from fr_pg fp where fp.pagina = p.pagina),
                'lcp', coalesce((
                   select jsonb_agg(jsonb_build_object('faixa', faixa, 'entradas', n, 'rejeicoes', r, 'leads', l) order by faixa)
                   from (select case when v.lcp_ms <= 2500 then 'bom' when v.lcp_ms <= 4000 then 'medio' else 'ruim' end as faixa,
                                count(*) filter (where ent.conta) as n, count(*) filter (where ent.rejeitou) as r, count(*) filter (where ent.conta and ent.lead) as l
                         from v join ent on ent.id = v.sessao
                         where v.pagina = p.pagina and v.ordem = 1 and v.lcp_ms is not null group by 1) x), '[]'::jsonb))
              order by p.sessoes desc)
       from pass p left join ent_pg e on e.pagina = p.pagina), '[]'::jsonb))
  into v_base;

  if coalesce(f ->> 'leve', '') = '1' then return v_base; end if;

  -- a leitura (secoes, botoes, formulario) das paginas com visitas no periodo
  for pg in select x ->> 'pagina' as pagina from jsonb_array_elements(v_base -> 'paginas') x where radar.inteiro(x ->> 'visitas', 0) > 0 limit 40 loop
    v_leituras := v_leituras || jsonb_build_array(radar.api_leitura(f || jsonb_build_object('pagina_alvo', pg.pagina)));
  end loop;

  -- antes e depois de cada publicacao dos ultimos 45 dias (uma por pagina e por dia: a ultima do dia).
  -- A janela e de 7 dias; publicacao mais nova que isso compara o que ja passou com o mesmo tanto antes.
  with
  sp as materialized (
    select s.primeira_pagina, s.inicio, s.lead, (s.resultado = 'mql') is true as mql,
           (s.engajada or radar.encerrada(s.recebido_em)) as conta, (not s.engajada and radar.encerrada(s.recebido_em)) as rejeitou
    from radar.filtradas(f || jsonb_build_object('de', (radar.hoje() - 60)::text, 'ate', (radar.hoje() + 1)::text)) s),
  pubs as (
    select distinct on (pu.pagina, (pu.quando at time zone 'America/Sao_Paulo')::date) pu.id, pu.pagina, pu.quando, pu.resumo
    from radar.publicacoes pu
    where pu.projeto = f ->> 'projeto' and pu.quando >= now() - interval '45 days' and pu.quando <= now()
    order by pu.pagina, (pu.quando at time zone 'America/Sao_Paulo')::date, pu.quando desc)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'pagina', p.pagina, 'quando', radar.ms(p.quando), 'resumo', p.resumo,
           'janela_h', round(extract(epoch from w.w) / 3600)::int, 'antes', a.j, 'depois', d.j) order by p.quando desc), '[]'::jsonb)
  into v_pubs
  from pubs p
  cross join lateral (select least(interval '7 days', now() - p.quando) as w) w
  cross join lateral (
    select jsonb_build_object('entradas', count(*) filter (where conta), 'rejeicoes', count(*) filter (where rejeitou),
                              'leads', count(*) filter (where conta and lead), 'mql', count(*) filter (where conta and mql)) as j
    from sp where (p.pagina = '*' or sp.primeira_pagina = p.pagina) and sp.inicio >= p.quando - w.w and sp.inicio < p.quando) a
  cross join lateral (
    select jsonb_build_object('entradas', count(*) filter (where conta), 'rejeicoes', count(*) filter (where rejeitou),
                              'leads', count(*) filter (where conta and lead), 'mql', count(*) filter (where conta and mql)) as j
    from sp where (p.pagina = '*' or sp.primeira_pagina = p.pagina) and sp.inicio >= p.quando and sp.inicio < p.quando + w.w) d;

  return v_base || jsonb_build_object('leituras', v_leituras, 'publicacoes', v_pubs);
end $$;


--
-- Name: api_pagina(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_pagina(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
s as materialized (select x.*, radar.unidade(x.visitante, x.ad_id, x.utm_content) collate "C" as u from radar.filtradas(f) x),
todas as materialized (select v.* from radar.visualizacoes v join s on s.id = v.sessao),
ult as (select sessao, max(ordem) as m from todas group by sessao),
b as materialized (
  select v.*, s.u, s.dispositivo, s.lead, s.resultado, s.utm_source, s.utm_campaign, s.utm_content, s.engajada, s.recebido_em,
         s.app, s.navegador, s.sistema,
         (v.ordem = 1) as entrada, (v.ordem = ul.m) as saida
  from todas v join s on s.id = v.sessao join ult ul on ul.sessao = v.sessao
  where v.pagina = f ->> 'pagina_alvo'),
-- uma linha por visita unica que abriu a pagina (021): o tempo somado das aberturas dela, a maior rolagem, se entrou ou
-- saiu do site por aqui e se virou lead. As contas de "quantas visitas" e as faixas saem daqui (as porcentagens da tela
-- sao sobre visitas)
pu as materialized (
  select u, max(dispositivo) as dispositivo, max(app) as app, coalesce(max(navegador), '(sem informação)') as navegador,
         sum(visivel_ms) as tempo, max(rolagem) as rolagem, bool_or(entrada) as entrou, bool_or(saida) as saiu,
         bool_or(lead) as lead, bool_or(coalesce(resultado = 'mql', false)) as mql
  from b group by u),
ent as materialized (
  select b.*, (b.engajada or radar.encerrada(b.recebido_em)) as conta, (not b.engajada and radar.encerrada(b.recebido_em)) as rejeitou
  from b where b.entrada),
cl as materialized (
  select c.* from radar.cliques c join s on s.id = c.sessao
  where c.pagina = f ->> 'pagina_alvo' and not c.automatico   -- o clique automatico fica fora (025)
    and c.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) and c.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1))
select jsonb_build_object(
  'pagina', f ->> 'pagina_alvo',
  'visitas', (select count(*) from pu),
  'sessoes', (select count(*) from pu),
  'sessoes_brutas', (select count(distinct sessao) from b),
  'aberturas', (select count(*) from b),
  'entradas', (select count(*) from pu where entrou),
  'saidas', (select count(*) from pu where saiu),
  'tempo_medio_ms', coalesce((select round(avg(tempo)) from pu), 0),
  'tempo_mediano_ms', coalesce((select percentile_disc(0.5) within group (order by tempo) from pu), 0),
  'rolagem_media', coalesce((select round(avg(rolagem), 1) from pu), 0),
  'rapidas', (select count(*) from pu where tempo < 3000),
  'chegaram_fim', (select count(*) from pu where rolagem >= 90),
  'leads', (select count(*) from pu where lead),
  'mql', (select count(*) from pu where mql),
  'por_dia', coalesce((
     select jsonb_agg(jsonb_build_object('dia', dia::text, 'visitas', n, 'entradas', e) order by dia)
     from (select dia, count(distinct u) as n, count(distinct u) filter (where entrada) as e from b group by dia) x), '[]'::jsonb),
  'tempo_faixas', (select jsonb_build_array(
       count(*) filter (where tempo < 10000),
       count(*) filter (where tempo >= 10000 and tempo < 30000),
       count(*) filter (where tempo >= 30000 and tempo < 60000),
       count(*) filter (where tempo >= 60000 and tempo < 180000),
       count(*) filter (where tempo >= 180000 and tempo < 600000),
       count(*) filter (where tempo >= 600000)) from pu),
  'rolagem_alcance', (select jsonb_agg((select count(*) from pu where rolagem >= p) order by p) from generate_series(0, 100, 10) p),
  'saida_faixas', (select jsonb_agg((select count(*) from b where saida and least(9, rolagem / 10) = i) order by i) from generate_series(0, 9) i),
  'proximas', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'n', n) order by n desc)
     from (select coalesce(nx.pagina, '(saiu)') as pagina, count(distinct b.u) as n
           from b left join todas nx on nx.sessao = b.sessao and nx.ordem = b.ordem + 1
           group by 1 order by n desc limit 8) x), '[]'::jsonb),
  'origens', coalesce((
     select jsonb_agg(jsonb_build_object('origem', origem, 'sessoes', n, 'leads', leads, 'mql', mql) order by n desc)
     from (select coalesce(utm_source, '(direto)') as origem, count(distinct u) as n,
                  count(distinct u) filter (where lead) as leads, count(distinct u) filter (where resultado = 'mql') as mql
           from b group by 1 order by n desc limit 8) x), '[]'::jsonb),
  'campanhas', coalesce((
     select jsonb_agg(jsonb_build_object('campanha', campanha, 'criativo', criativo, 'sessoes', n, 'leads', leads) order by n desc)
     from (select coalesce(utm_campaign, '(sem campanha)') as campanha, coalesce(utm_content, '') as criativo,
                  count(distinct u) as n, count(distinct u) filter (where lead) as leads
           from b group by 1, 2 order by n desc limit 10) x), '[]'::jsonb),
  'aparelhos', coalesce((
     select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'visitas', n, 'tempo', tempo, 'rolagem', rol, 'leads', leads, 'sessoes', n) order by n desc)
     from (select dispositivo, count(*) as n, round(avg(tempo)) as tempo, round(avg(rolagem), 1) as rol, count(*) filter (where lead) as leads
           from pu group by 1) x), '[]'::jsonb),
  'eventos', coalesce((
     select jsonb_agg(jsonb_build_object('nome', nome, 'sessoes', n) order by n desc)
     from (select e.nome, count(distinct s.u) as n from radar.eventos_funil e join s on s.id = e.sessao
           where e.pagina = f ->> 'pagina_alvo' group by 1) x), '[]'::jsonb),
  'cliques', (select jsonb_build_object('total', count(*), 'raiva', count(*) filter (where raiva), 'mortos', count(*) filter (where morto)) from cl),
  'top', coalesce((
     select jsonb_agg(jsonb_build_object('sel', seletor, 'txt', txt, 'n', n, 'raiva', rv, 'morto', mt) order by n desc)
     from (select seletor, max(texto) as txt, count(*) as n, count(*) filter (where raiva) as rv, count(*) filter (where morto) as mt
           from cl where not fixo group by 1 order by n desc limit 8) x), '[]'::jsonb),
  -- rejeicao de quem entrou por esta pagina, e aberta por aparelho e por criativo (a promessa do anuncio x a pagina)
  'rejeicao', jsonb_build_object(
     'entradas', (select count(*) from ent where conta),
     'rejeicoes', (select count(*) from ent where rejeitou),
     'por_aparelho', coalesce((
        select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'entradas', n, 'rejeicoes', r) order by n desc)
        from (select dispositivo, count(*) filter (where conta) as n, count(*) filter (where rejeitou) as r from ent group by 1) x where n > 0), '[]'::jsonb),
     'por_criativo', coalesce((
        select jsonb_agg(jsonb_build_object('campanha', campanha, 'criativo', criativo, 'entradas', n, 'rejeicoes', r, 'leads', leads) order by n desc)
        from (select coalesce(utm_campaign, '(sem campanha)') as campanha, coalesce(utm_content, '') as criativo,
                     count(*) filter (where conta) as n, count(*) filter (where rejeitou) as r, count(*) filter (where conta and lead) as leads
              from ent group by 1, 2 order by n desc limit 12) x where n > 0), '[]'::jsonb)),
  -- velocidade real desta pagina (p75, como o Google avalia)
  'vitais', (select jsonb_build_object(
       'medidas', count(lcp_ms),
       'lcp_p75', percentile_disc(0.75) within group (order by lcp_ms),
       'inp_p75', percentile_disc(0.75) within group (order by inp_ms),
       'cls_p75', round((percentile_disc(0.75) within group (order by cls))::numeric, 3),
       'fcp_p75', percentile_disc(0.75) within group (order by fcp_ms),
       'ttfb_p75', percentile_disc(0.75) within group (order by ttfb_ms)) from b))
  -- onde abriram: dentro do app (Instagram, Facebook...) ou no navegador, em visitas unicas, com a rejeicao de quem
  -- entrou (por sessao) e o lead
  || jsonb_build_object('navegadores', coalesce((
     select jsonb_agg(jsonb_build_object('app', x.app, 'navegador', x.navegador, 'visitas', x.n, 'tempo', x.tempo, 'rolagem', x.rol,
                                         'leads', x.leads, 'sessoes', x.n, 'entradas', coalesce(r.ent, 0), 'rejeicoes', coalesce(r.rej, 0)) order by x.n desc)
     from (select app, navegador, count(*) as n, round(avg(tempo)) as tempo, round(avg(rolagem), 1) as rol, count(*) filter (where lead) as leads
           from pu group by 1, 2 order by n desc limit 12) x
     left join (select app, coalesce(navegador, '(sem informação)') as navegador,
                       count(*) filter (where entrada and (engajada or radar.encerrada(recebido_em))) as ent,
                       count(*) filter (where entrada and not engajada and radar.encerrada(recebido_em)) as rej
                from b group by 1, 2) r on r.app is not distinct from x.app and r.navegador = x.navegador), '[]'::jsonb))
$$;


--
-- Name: api_pesquisas(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_pesquisas(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'radar_crm'
    AS $$
with
par as (
  select f ->> 'projeto' as projeto,
         coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de,
         coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate,
         nullif(f ->> 'plataforma', '') as plataforma
),
cfg as (select pr.config from radar.projetos pr, par where pr.id = par.projeto),
cad as (
  select x as p, ord from cfg, jsonb_array_elements(coalesce(cfg.config -> 'pesquisas', '[]'::jsonb)) with ordinality as t(x, ord)
),
-- a escolhida: a do pedido ou, sem ela (ou com um id que nao existe), a primeira do cadastro
esc as (
  select p from (select coalesce((select c.p from cad c where c.p ->> 'id' = f ->> 'pesquisa'),
                                 (select c.p from cad c order by c.ord limit 1)) as p) e
  where p is not null
),
-- o profissional: a intencao do resultado "profissional" do Fluxo
prof as (
  select coalesce((select r ->> 'intencao' from cfg, jsonb_array_elements(coalesce(cfg.config -> 'fluxo' -> 'resultados', '[]'::jsonb)) r
                   where r ->> 'id' = 'profissional' limit 1), '') as rotulo
),
-- o publico: as paginas da entrada do Fluxo que a pesquisa aponta
ent as (
  select e ->> 'id' as id, e ->> 'nome' as nome, array(select jsonb_array_elements_text(coalesce(e -> 'paginas', '[]'::jsonb))) as paginas
  from cfg, esc, jsonb_array_elements(coalesce(cfg.config -> 'fluxo' -> 'entradas', '[]'::jsonb)) e
  where e ->> 'id' = esc.p ->> 'entrada'
),
gente as materialized (
  select pe.id, pe.pagina_primeira, coalesce(nullif(pe.plataforma, ''), 'sem') as plataforma, pe.parou_em, pe.mql, pe.respostas,
         pe.pesquisa_via, (pe.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
  from radar_crm.pessoas pe, par
  where pe.projeto = par.projeto and not pe.teste
    and (pe.primeiro_em at time zone 'America/Sao_Paulo')::date between par.de and par.ate
    and (par.plataforma is null or coalesce(nullif(pe.plataforma, ''), 'sem') = par.plataforma)
),
resp as materialized (
  select g.*,
         case when (select rotulo from prof) <> '' and g.respostas ->> 'intencao' = (select rotulo from prof) then 'profissional'
              when g.mql = 'sim' then 'mql' when g.mql = 'nao' then 'nao_mql' else 'sem' end as resultado
  from gente g, esc where g.pesquisa_via = esc.p ->> 'via'
),
pub as materialized (select g.* from gente g, ent where g.pagina_primeira = any (ent.paginas)),
passo as (select coalesce((esc.p ->> 'passo_a_passo')::boolean, false) as sim from esc),
-- quem parou no meio: so na pesquisa que grava passo a passo; as respostas da pessoa sao as do ultimo passo
pararam as (select g.* from pub g, passo where passo.sim and g.parou_em = 'pesquisa_parcial'),
onde as (
  select coalesce(pq.chave, 'fim') as chave, coalesce(pq.ordem, 999) as ordem
  from pararam r
  left join lateral (
    select q ->> 'chave' as chave, qi as ordem
    from esc, jsonb_array_elements(esc.p -> 'perguntas') with ordinality as t(q, qi)
    where coalesce(r.respostas ->> (q ->> 'chave'), '') = ''
      and (q -> 'condicao' is null or r.respostas ->> (q -> 'condicao' ->> 'chave') = q -> 'condicao' ->> 'valor')
    order by qi limit 1) pq on true
),
-- 051: pelo gravador do Radar, desde que ele entrou na pagina da pesquisa (na /quase-la/ e na /pesquisa/ do Patrimonio
-- Brasil, 04/10/2026): as pessoas (o navegador) que abriram a pagina no periodo, quem comecou (respondeu alguma
-- pergunta), quem terminou (o evento de conclusao da pesquisa) e onde parou quem comecou e nao terminou (a primeira
-- pergunta sem resposta na pagina vista em que a pessoa foi mais longe; a da profissao so conta para quem chegou a
-- ela). O gravador nunca le o que a pessoa respondeu: so se cada campo ficou preenchido. Sem as visitas de teste e da
-- equipe e sem a pagina que nunca apareceu na tela, como no resto do Radar; o filtro de plataforma vale pela origem
-- da visita.
passos as (
  select array(select q ->> 'chave' from esc, jsonb_array_elements(esc.p -> 'perguntas') with ordinality as t(q, n) order by n)
         || case when coalesce((select (p ->> 'pede_email')::boolean from esc), false) then array['email'] else array[]::text[] end as chaves
),
fim_ev as materialized (
  select distinct e.visualizacao
  from radar.eventos_funil e, par, esc
  where e.projeto = par.projeto and e.nome = esc.p ->> 'evento_concluiu' and e.dia between par.de and par.ate + 1
),
vis as materialized (
  select s.visitante, v.form, v.id in (select visualizacao from fim_ev) as concluiu
  from radar.visualizacoes v
  join radar.sessoes s on s.id = v.sessao
  cross join par cross join esc
  where v.projeto = par.projeto and v.pagina = esc.p ->> 'pagina' and v.dia between par.de and par.ate
    and not coalesce(s.teste, false) and not coalesce(s.interna, false) and coalesce(v.visivel_ms, 0) > 0
    and (par.plataforma is null
         or coalesce(radar.plataforma(s.utm_source, s.utm_medium, s.fbclid, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content), 'sem') = par.plataforma)
),
vis_passo as (
  select x.visitante, x.concluiu,
         (select count(*) from passos, unnest(passos.chaves) as k where coalesce(x.form -> 'c' -> k ->> 2, '0') = '1') as feitas,
         (select t.k from passos, unnest(passos.chaves) with ordinality as t(k, n)
          where coalesce(x.form -> 'c' -> t.k ->> 2, '0') <> '1' and (t.k <> 'profissao' or coalesce((x.form -> 'c') ? 'profissao', false))
          order by t.n limit 1) as parou
  from vis x
),
pessoa_vis as (
  select visitante, bool_or(concluiu) as terminou, max(feitas) as feitas, (array_agg(parou order by feitas desc))[1] as parou
  from vis_passo group by visitante
)
select jsonb_build_object(
  'ok', true,
  'de', (select de from par), 'ate', (select ate from par),
  'pesquisas', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.p ->> 'id', 'nome', c.p ->> 'nome', 'descricao', c.p ->> 'descricao', 'pagina', c.p ->> 'pagina',
             'via', c.p ->> 'via', 'passo_a_passo', coalesce((c.p ->> 'passo_a_passo')::boolean, false), 'entrada', c.p ->> 'entrada',
             'responderam', (select count(*) from gente g where g.pesquisa_via = c.p ->> 'via'),
             'mql', (select count(*) from gente g where g.pesquisa_via = c.p ->> 'via' and g.mql = 'sim')) order by c.ord)
    from cad c), '[]'::jsonb),
  'pesquisa', (select p ->> 'id' from esc),
  'perguntas', coalesce((select p -> 'perguntas' from esc), '[]'::jsonb),
  'profissional', (select rotulo from prof),
  'entrada', (select jsonb_build_object('id', id, 'nome', nome, 'paginas', to_jsonb(paginas)) from ent),
  'numeros', jsonb_build_object(
    'publico', (select count(*) from pub),
    'responderam', (select count(*) from resp),
    'responderam_publico', (select count(*) from pub g, esc where g.pesquisa_via = esc.p ->> 'via'),
    'mql', (select count(*) from resp where resultado = 'mql'),
    'nao_mql', (select count(*) from resp where resultado = 'nao_mql'),
    'profissional', (select count(*) from resp where resultado = 'profissional'),
    -- 075: os niveis do MQL do contrato (fluxo.resultados com "nivel"; a Black: Super MQL e MQL 55+), na ordem do contrato
    'niveis', coalesce((select jsonb_agg(jsonb_build_object('id', r ->> 'id', 'nome', r ->> 'nome', 'nivel', r ->> 'nivel',
                         'n', (select count(*) from resp x where x.mql = 'sim' and x.respostas ->> 'nivel' = r ->> 'nivel')) order by o)
                       from cfg, jsonb_array_elements(coalesce(cfg.config -> 'fluxo' -> 'resultados', '[]'::jsonb)) with ordinality t(r, o)
                       where coalesce(r ->> 'nivel', '') <> ''), '[]'::jsonb),
    'pararam', (select count(*) from pararam),
    'so_cadastro', (select count(*) from pub g, passo where passo.sim and g.parou_em = 'captura'),
    'sem_resposta', (select count(*) from pub where pesquisa_via = ''),
    'outra', (select count(*) from pub g, esc where g.pesquisa_via not in ('', esc.p ->> 'via')),
    'de_novo', (select count(*) from gente g, esc where g.pesquisa_via not in ('', esc.p ->> 'via')
                  and exists (select 1 from radar_crm.envios e where e.pessoa = g.id and e.tipo = esc.p ->> 'envio'))),
  'dias', coalesce((
    select jsonb_agg(jsonb_build_object('dia', d.dia, 'responderam', d.n, 'mql', d.mql) order by d.dia)
    from (select dia, count(*) as n, count(*) filter (where resultado = 'mql') as mql from resp group by dia) d), '[]'::jsonb),
  'plataformas', coalesce((
    select jsonb_agg(jsonb_build_object('plataforma', x.plataforma, 'publico', x.publico, 'responderam', x.responderam, 'mql', x.mql)
                     order by x.responderam desc, x.publico desc, x.plataforma)
    from (select plataforma, sum(pu)::int as publico, sum(re)::int as responderam, sum(mq)::int as mql
          from (select plataforma, 1 as pu, 0 as re, 0 as mq from pub
                union all
                select plataforma, 0, 1, case when resultado = 'mql' then 1 else 0 end from resp) u
          group by plataforma) x), '[]'::jsonb),
  -- como cada pergunta foi respondida: na de varias opcoes, cada opcao conta quem a marcou
  'respostas', coalesce((
    select jsonb_agg(jsonb_build_object(
             'chave', q ->> 'chave',
             'total', (select count(*) from resp r where coalesce(r.respostas ->> (q ->> 'chave'), '') <> ''),
             'opcoes', (select coalesce(jsonb_agg(jsonb_build_object('rotulo', o, 'n', (
                          select count(*) from resp r
                          where case when q ->> 'tipo' = 'multipla' then strpos(coalesce(r.respostas ->> (q ->> 'chave'), ''), o) > 0
                                     else r.respostas ->> (q ->> 'chave') = o end)) order by oi), '[]'::jsonb)
                        from jsonb_array_elements_text(coalesce(q -> 'opcoes', '[]'::jsonb)) with ordinality as t2(o, oi))) order by qi)
    from esc, jsonb_array_elements(esc.p -> 'perguntas') with ordinality as t(q, qi)), '[]'::jsonb),
  'pararam_em', coalesce((
    select jsonb_agg(jsonb_build_object('chave', w.chave, 'n', w.n) order by w.ordem)
    from (select chave, min(ordem) as ordem, count(*) as n from onde group by chave) w), '[]'::jsonb),
  -- 051: pelo gravador (so as pessoas que abriram a pagina da pesquisa; "desde" e o primeiro dia que o gravador viu a pagina)
  'visitas', jsonb_build_object(
    'desde', (select min(v.dia) from radar.visualizacoes v, par, esc where v.projeto = par.projeto and v.pagina = esc.p ->> 'pagina'),
    'abriram', (select count(*) from pessoa_vis),
    'comecaram', (select count(*) from pessoa_vis where feitas > 0 or terminou),
    'terminaram', (select count(*) from pessoa_vis where terminou),
    'pararam_em', coalesce((
      select jsonb_agg(jsonb_build_object('chave', w.chave, 'n', w.n) order by w.ordem)
      from (select z.chave, min(z.ordem) as ordem, count(*) as n
            from (select coalesce(pv.parou, 'fim') as chave,
                         coalesce((select t.n from passos, unnest(passos.chaves) with ordinality as t(k, n) where t.k = pv.parou), 999) as ordem
                  from pessoa_vis pv where not pv.terminou and pv.feitas > 0) z
            group by z.chave) w), '[]'::jsonb)))
$$;


--
-- Name: api_projetos(boolean, text[]); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_projetos(p_todos boolean, p_lista text[]) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nome', p.nome, 'descricao', coalesce(p.config ->> 'descricao', ''),
           -- 033: de quem e o projeto (Grupo Participa, um Diamante...), para agrupar no seletor e nos acessos
           'cliente', coalesce(p.config ->> 'cliente', ''),
           -- ativo = chegou visita de verdade, que apareceu na tela, nos ultimos 7 dias; demonstracao = funil de dados ficticios
           'situacao', case when coalesce(p.config ->> 'demonstracao', '') = 'true' then 'demonstracao'
                            when exists (select 1 from radar.sessoes s where s.projeto = p.id and not s.teste and s.dia >= radar.hoje() - 7
                                                                         and coalesce(s.visivel_ms, 0) > 0) then 'ativo'
                            when p.situacao = 'demonstracao' then 'nao_instalado' else p.situacao end,
           'dominios', coalesce((select jsonb_agg(d) from unnest(p.dominios) d where d like '%.%' and d !~ '^[0-9]'), '[]'::jsonb),
           'paginas', coalesce(p.config -> 'paginas', '[]'::jsonb), 'funis', coalesce(p.config -> 'funis', '[]'::jsonb),
           'resultados', coalesce(p.config -> 'resultados', '[]'::jsonb), 'eventos_lead', coalesce(p.config -> 'eventos_lead', '[]'::jsonb),
           'retencao_video_dias', p.retencao_gravacao_dias, 'engajamento_segundos', p.engajamento_segundos)
           -- 071: a regua do MQL na inscricao, so no projeto que tem (sem a chave nos outros)
           || case when jsonb_typeof(p.config -> 'mql_na_inscricao') = 'object'
                   then jsonb_build_object('mql_na_inscricao', jsonb_build_object('campo', p.config -> 'mql_na_inscricao' -> 'campo',
                                                                                  'sim', p.config -> 'mql_na_inscricao' -> 'sim'))
                   else '{}'::jsonb end
           -- 071: o que o servidor do funil anota no CRM (o Active e a planilha), so no projeto que diz
           || case when jsonb_typeof(p.config -> 'crm') = 'object'
                   then jsonb_build_object('crm', jsonb_build_object('active', coalesce(p.config -> 'crm' ->> 'active', '') <> 'false',
                                                                     'planilha', coalesce(p.config -> 'crm' ->> 'planilha', '') <> 'false'))
                   else '{}'::jsonb end
         order by radar.inteiro(p.config ->> 'ordem', 99), p.id), '[]'::jsonb)
  from radar.projetos p
  where p_todos or p.id = any (p_lista)
$$;


--
-- Name: api_publicacoes(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_publicacoes(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('publicacoes', coalesce((
    select jsonb_agg(jsonb_build_object('quando', radar.ms(p.quando), 'dia', (p.quando at time zone 'America/Sao_Paulo')::date::text,
                                        'pagina', p.pagina, 'resumo', p.resumo) order by p.quando)
    from radar.publicacoes p
    where p.projeto = f ->> 'projeto'
      and (p.quando at time zone 'America/Sao_Paulo')::date between coalesce(radar.data(f ->> 'de'), radar.hoje() - 6)
                                                                 and coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)
      -- com a pagina escolhida, as dela e as do site todo
      and (coalesce(f ->> 'pagina', '') = '' or p.pagina in (f ->> 'pagina', '*'))), '[]'::jsonb))
$$;


--
-- Name: api_relatorio(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_relatorio(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object('id', id, 'projeto', projeto, 'pagina', pagina, 'url', url, 'estrategia', estrategia, 'nota', nota,
                            'notas', notas, 'medido_em', radar.ms(medido_em), 'relatorio', relatorio, 'imagens', imagens)
    from radar.velocidade_lab
   where id = radar.id_lab(f ->> 'id')
$$;


--
-- Name: api_resumo(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_resumo(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
-- so as colunas que o resumo usa (a linha inteira da visita tem 50 colunas e ia para o disco a cada leitura).
-- u = a visita unica (radar.unidade): a mesma pessoa pelo mesmo anuncio conta uma vez no recorte. u e visitante em
-- ordem "C" (compara byte a byte): contar diferentes fica bem mais barato do que na ordem do idioma do banco.
-- sid = um numero por visita, para as contas por visita nao compararem o codigo em texto
s as materialized (
  select x.id, row_number() over () as sid, x.visitante collate "C" as visitante,
         radar.unidade(x.visitante, x.ad_id, x.utm_content) collate "C" as u,
         x.dia, x.inicio, x.fim, x.gravada, x.raiva, x.erros, x.mortos, x.paginas, x.lead, x.resultado,
         x.utm_source, x.utm_campaign, x.utm_content, x.primeira_pagina, x.ultima_pagina, x.engajada, x.recebido_em
  from radar.filtradas(f) x),
cfg as (select config from radar.projetos where id = f ->> 'projeto'),
-- o resultado (MQL...) e a unidade vem junto, para a conta por funil nao precisar cruzar de novo com as visitas
v as materialized (select s.sid, v.pagina, v.rolagem, v.visivel_ms, s.resultado, s.u from radar.visualizacoes v join s on s.id = v.sessao),
etapas as (
  select fu.value ->> 'id' as fid, et.value ->> 'nome' as enome, et.eo,
         array(select jsonb_array_elements_text(coalesce(et.value -> 'pagina', '[]'::jsonb))) as epags,
         array(select jsonb_array_elements_text(coalesce(et.value -> 'evento', '[]'::jsonb))) as eevs
  from cfg, jsonb_array_elements(coalesce(cfg.config -> 'funis', '[]'::jsonb)) fu(value),
       jsonb_array_elements(coalesce(fu.value -> 'etapas', '[]'::jsonb)) with ordinality et(value, eo)),
-- uma linha por pagina e por evento que contam para cada etapa
ep as (select fid, eo, p from etapas, unnest(epags) p),
ee as (select fid, eo, n from etapas, unnest(eevs) n),
-- etapas cumpridas por visita (pela pagina vista ou pelo evento do dataLayer). "union all": a mesma etapa repetida nao
-- muda o bit_or da mascara, entao nao precisa da ordenacao que tirava as repetidas
cumpridas as (
  select ep.fid, v.sid, v.u, v.resultado, ep.eo from v join ep on ep.p = v.pagina
  union all
  select ee.fid, s.sid, s.u, s.resultado, ee.eo from radar.eventos_funil e join s on s.id = e.sessao join ee on ee.n = e.nome),
-- um bit por etapa cumprida, por visita e por funil (o resultado e a unidade sao da visita)
mascara as materialized (
  select fid, sid, min(u) as u, min(resultado) as resultado, bit_or(1::bigint << (eo::int - 1)) as m from cumpridas group by fid, sid),
-- funil por visita unica (021): de cada visita, so as etapas seguidas desde a primeira ((~m & (m + 1)) - 1 deixa
-- ligados os bits ate o primeiro buraco: 1011 -> 0011, a regra da 017); de cada unidade, a visita que foi mais longe
-- (mascara de prefixo cresce com o numero de etapas, entao a maior e a mais longa). Etapas de visitas diferentes nao
-- se somam. O caso de 63 etapas todas cumpridas fica de fora da conta de bits (m + 1 estouraria)
uni as (
  select fid, u, max(case when m = 9223372036854775807 then m else ((~m) & (m + 1)) - 1 end) as p
  from mascara group by fid, u),
-- quantas unidades pararam em cada prefixo (poucas linhas por funil), e so entao as etapas: chegou na etapa k = a
-- visita mais longa da unidade tem os k primeiros bits. "materialized": conta uma vez so, nao uma vez por funil
uni_n as (select fid, p, count(*) as n from uni group by fid, p),
contagem as materialized (
  select et.fid, et.eo, (sum(k.n) filter (where k.p & (1::bigint << (et.eo::int - 1)) <> 0))::bigint as n
  from etapas et join uni_n k on k.fid = et.fid
  group by et.fid, et.eo),
res_funil as materialized (
  select fid, jsonb_object_agg(resultado, n) as j
  from (select fid, resultado, count(distinct u) as n from mascara where m & 1 = 1 and resultado is not null group by 1, 2) x
  group by fid)
select jsonb_build_object(
  'sessoes', (select count(distinct u) from s),
  'sessoes_brutas', (select count(*) from s),
  'pessoas', (select count(distinct visitante) from s),
  -- os dias de video do projeto, lidos uma vez (antes, uma vez por visita)
  'gravadas', (select count(*) from s where s.gravada and s.inicio > now() - (select radar.retencao_video(f ->> 'projeto'))),
  'duracao_media_ms', coalesce((select round(avg(extract(epoch from (fim - inicio)) * 1000)) from s), 0),
  'duracao_tipica_ms', coalesce((select round(percentile_cont(0.5) within group (order by extract(epoch from (fim - inicio)) * 1000)) from s), 0),
  'com_raiva', (select count(*) from s where raiva > 0),
  'com_erro', (select count(*) from s where erros > 0),
  'com_clique_morto', (select count(*) from s where mortos > 0),
  'paginas_vistas', coalesce((select sum(paginas) from s), 0),
  'leads', (select count(distinct u) from s where lead),
  'funis', coalesce((
     select jsonb_agg(jsonb_build_object(
              'id', fu.value ->> 'id', 'nome', fu.value ->> 'nome',
              'etapas', coalesce((select jsonb_agg(jsonb_build_object('nome', et.enome, 'sessoes', coalesce(c.n, 0)) order by et.eo)
                                  from etapas et left join contagem c on c.fid = et.fid and c.eo = et.eo
                                  where et.fid = fu.value ->> 'id'), '[]'::jsonb),
              'resultados', coalesce((select j from res_funil r where r.fid = fu.value ->> 'id'), '{}'::jsonb))
            order by fo)
     from cfg, jsonb_array_elements(coalesce(cfg.config -> 'funis', '[]'::jsonb)) with ordinality fu(value, fo)), '[]'::jsonb),
  'resultados', coalesce((select jsonb_object_agg(k, n) from (select coalesce(resultado, '(sem resultado)') as k, count(distinct u) as n from s group by 1) x), '{}'::jsonb),
  -- visitas = visitas unicas que abriram a pagina; sessoes = sessoes que abriram; aberturas = cada vez que ela abriu
  -- (recarregar, voltar, o app reabrir a aba). Rolagem e tempo continuam a media por abertura.
  'por_pagina', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', pagina, 'visitas', n, 'sessoes', ses, 'aberturas', ab, 'rolagem', rol, 'tempo', tempo) order by n desc)
     from (select pagina, count(distinct u) as n, count(distinct sid) as ses, count(*) as ab, round(avg(rolagem), 1) as rol, round(avg(visivel_ms)) as tempo
           from v group by pagina) x), '[]'::jsonb),
  'origens', coalesce((
     select jsonb_agg(jsonb_build_object('origem', origem, 'sessoes', n, 'mql', mql, 'leads', leads, 'duracao', dur) order by n desc)
     from (select coalesce(utm_source, '(direto)') as origem, count(distinct u) as n, count(distinct u) filter (where resultado = 'mql') as mql,
                  count(distinct u) filter (where lead) as leads, round(avg(extract(epoch from (fim - inicio)) * 1000)) as dur
           from s group by 1 order by n desc limit 50) x), '[]'::jsonb),
  'campanhas', coalesce((
     select jsonb_agg(jsonb_build_object('origem', origem, 'campanha', campanha, 'criativo', criativo, 'sessoes', n, 'mql', mql, 'leads', leads) order by n desc)
     from (select coalesce(utm_source, '(direto)') as origem, coalesce(utm_campaign, '(sem campanha)') as campanha, coalesce(utm_content, '') as criativo,
                  count(distinct u) as n, count(distinct u) filter (where resultado = 'mql') as mql, count(distinct u) filter (where lead) as leads
           from s group by 1, 2, 3 order by n desc limit 500) x), '[]'::jsonb),
  'por_dia', coalesce((
     select jsonb_agg(jsonb_build_object('dia', dia::text, 'sessoes', n, 'mql', mql, 'leads', leads) order by dia)
     from (select dia, count(distinct u) as n, count(distinct u) filter (where resultado = 'mql') as mql, count(distinct u) filter (where lead) as leads
           from s group by dia) x), '[]'::jsonb),
  'entradas', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', primeira_pagina, 'sessoes', n) order by n desc)
     from (select primeira_pagina, count(*) as n from s group by 1) x), '[]'::jsonb),
  'saidas', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', ultima_pagina, 'sessoes', n) order by n desc)
     from (select ultima_pagina, count(*) as n from s group by 1) x), '[]'::jsonb),
  'rejeicao', coalesce((
     select jsonb_agg(jsonb_build_object('pagina', primeira_pagina, 'entradas', entradas, 'rejeicoes', rejeicoes) order by entradas desc)
     from (select primeira_pagina,
                  count(*) filter (where engajada or radar.encerrada(recebido_em)) as entradas,
                  count(*) filter (where not engajada and radar.encerrada(recebido_em)) as rejeicoes
           from s group by 1) x), '[]'::jsonb))
$$;


--
-- Name: api_sessao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_sessao(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select case when s.id is null then null else jsonb_build_object(
    'sessao', radar.sessao_json(s),
    -- 030: guardada por quem e quando (a nota vem na sessao)
    'guardada', (select jsonb_build_object('em', radar.ms(k.guardada_em), 'com_video', k.com_video::int,
                                           'por', (select coalesce(nullif(trim(m.nome), ''), split_part(m.email, '@', 1)) from radar.membros m where m.usuario = k.guardada_por))
                 from radar.guardadas k where k.sessao = s.id),
    -- a pessoa: desde quando vem, qual visita e esta, se ja tinha virado lead e as outras visitas dela
    'visitante_info', (
       select jsonb_build_object(
         'primeira_vez', radar.ms(vi.primeira_vez), 'sessoes', vi.sessoes,
         'esta_e', (select count(*) from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante and x.inicio <= s.inicio),
         'lead_antes', exists (select 1 from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante
                                                         and x.inicio < s.inicio and x.lead),
         'outras', coalesce((
            select jsonb_agg(jsonb_build_object('id', x.id, 'inicio', radar.ms(x.inicio), 'fim', radar.ms(x.fim), 'paginas', x.paginas,
                                                'lead', x.lead::int, 'resultado', x.resultado,
                                                'gravada', ((x.gravada and x.inicio > now() - radar.retencao_video(x.projeto))
                                                            or exists (select 1 from radar.guardadas k where k.sessao = x.id and k.com_video))::int)
                             order by x.inicio desc)
            from (select * from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante and x.id <> s.id
                  order by x.inicio desc limit 10) x), '[]'::jsonb))
       from radar.visitantes vi where vi.projeto = s.projeto and vi.id = s.visitante),
    -- voltou rapido: foi para outra pagina, ficou menos de 5 s e voltou para a anterior
    'voltou_rapido', (
       select count(*) from (
         select visivel_ms, lag(pagina) over w as antes, lead(pagina) over w as depois
         from radar.visualizacoes where sessao = s.id window w as (order by ordem)) z
       where z.antes is not null and z.depois = z.antes and z.visivel_ms < 5000),
    'pageviews', coalesce((
       select jsonb_agg(jsonb_build_object(
                'id', v.id, 'sessao', v.sessao, 'caminho', v.caminho, 'pagina', v.pagina, 'inicio', radar.ms(v.inicio),
                'fim', radar.ms(v.fim), 'largura', v.largura, 'altura', v.altura, 'altura_doc', v.altura_doc,
                'rolagem', v.rolagem, 'visivel_ms', v.visivel_ms, 'dispositivo', s.dispositivo,
                'gravada', (v.gravada and (s.inicio > now() - radar.retencao_video(s.projeto)
                                           or exists (select 1 from radar.guardadas k where k.sessao = s.id and k.com_video)))::int,
                'titulo', coalesce(v.titulo, ''),
                'lcp_ms', v.lcp_ms, 'inp_ms', v.inp_ms, 'cls', v.cls, 'fcp_ms', v.fcp_ms, 'ttfb_ms', v.ttfb_ms,
                'vaivem', v.vaivem, 'ativo_ms', v.ativo_ms, 'rede', v.rede)
              order by v.ordem)
       from radar.visualizacoes v where v.sessao = s.id), '[]'::jsonb),
    'eventos', coalesce((
       select jsonb_agg(ev order by (ev ->> 'quando')::bigint)
       from (
         select jsonb_build_object('tipo', 'pagina', 'quando', radar.ms(v.inicio), 'pagina', v.pagina, 'nome', v.pagina,
                                   'dados', null, 'sel', null, 'txt', null, 'raiva', null, 'morto', null) as ev
         from radar.visualizacoes v where v.sessao = s.id
         union all
         select jsonb_build_object('tipo', 'clique', 'quando', radar.ms(c.quando), 'pagina', c.pagina, 'nome', null, 'dados', null,
                                   'sel', c.seletor, 'txt', c.texto, 'raiva', c.raiva::int, 'morto', c.morto::int)
         from radar.cliques c where c.sessao = s.id and c.dia = s.dia
         union all
         select jsonb_build_object('tipo', 'funil', 'quando', radar.ms(e.quando), 'pagina', e.pagina, 'nome', e.nome,
                                   'dados', e.dados::text, 'sel', null, 'txt', null, 'raiva', null, 'morto', null)
         from radar.eventos_funil e where e.sessao = s.id
         union all
         select jsonb_build_object('tipo', 'erro', 'quando', radar.ms(e.quando), 'pagina', e.pagina, 'nome', e.mensagem,
                                   'dados', jsonb_build_object('arq', coalesce(e.arquivo, ''), 'linha', coalesce(e.linha, 0))::text,
                                   'sel', null, 'txt', null, 'raiva', null, 'morto', null)
         from radar.erros e where e.sessao = s.id
       ) x), '[]'::jsonb)) end
  from (select 1) um left join radar.sessoes s on s.id = f ->> 'id'
$$;


--
-- Name: api_sessoes(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_sessoes(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
s as (select * from radar.filtradas(f)),
q as (select lower(trim(coalesce(f ->> 'busca', ''))) as b, coalesce(f ->> 'ordem', '') as ordem,
             least(greatest(radar.inteiro(f ->> 'limite', 50), 1), 200) as lim,
             greatest(radar.inteiro(f ->> 'pagina_lista', 0), 0) as pag),
sel as materialized (
  select s.* from s, q
  where q.b = ''
     or position(q.b in lower(s.id)) > 0 or position(q.b in lower(s.visitante)) > 0
     or position(q.b in lower(coalesce(s.utm_source, ''))) > 0 or position(q.b in lower(coalesce(s.utm_campaign, ''))) > 0
     or position(q.b in lower(coalesce(s.utm_content, ''))) > 0 or position(q.b in lower(coalesce(s.referrer, ''))) > 0
     or position(q.b in lower(s.primeira_pagina)) > 0
     or position(q.b in lower(concat_ws(' ', s.app, s.navegador, s.sistema, s.modelo, s.cidade, s.estado, s.pais))) > 0
     or exists (select 1 from radar.visualizacoes bp where bp.sessao = s.id and position(q.b in lower(bp.pagina)) > 0)),
ord as (
  select sel.id, row_number() over (order by
    case when q.ordem = 'antigas' then sel.inicio end asc,
    case when q.ordem = 'longas' then sel.fim - sel.inicio end desc,
    case when q.ordem = 'curtas' then sel.fim - sel.inicio end asc,
    case when q.ordem = 'paginas' then sel.paginas end desc,
    case when q.ordem = 'cliques' then sel.cliques end desc,
    case when q.ordem = 'sinais' then sel.raiva + sel.mortos + sel.erros end desc,
    sel.inicio desc) as rn
  from sel, q),
pag as (select ord.id, ord.rn from ord, q where ord.rn > q.lim * q.pag and ord.rn <= q.lim * (q.pag + 1))
select jsonb_build_object(
  'total', (select count(*) from sel),
  'sessoes', coalesce((
     select jsonb_agg(radar.sessao_json(x) || jsonb_build_object('caminho',
              coalesce((select jsonb_agg(v.pagina order by v.ordem) from radar.visualizacoes v where v.sessao = x.id), '[]'::jsonb))
            order by pag.rn)
     from pag join radar.sessoes x on x.id = pag.id), '[]'::jsonb))
$$;


--
-- Name: api_splits(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_splits(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_proj text := f ->> 'projeto';
  v_de date := coalesce(radar.data(f ->> 'de'), radar.hoje() - 6);
  v_ate date := coalesce(radar.data(f ->> 'ate'), radar.hoje());
  v_teste boolean := coalesce(f ->> 'teste', '') = '1';
  v_disp text := coalesce(f ->> 'dispositivo', '');
  g jsonb;
  v_eventos text[];
  v_paginas text[];
  v_cta text := '';
  v_res jsonb;
begin
  if radar.sim(f ->> 'leve') then
    return jsonb_build_object('splits', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'estado', t.estado) order by t.id)
      from radar.testes t where t.projeto = v_proj and t.tipo = 'split'), '[]'::jsonb));
  end if;
  select p.config -> 'fluxo' -> 'grupo' into g from radar.projetos p where p.id = v_proj;
  if jsonb_typeof(g) = 'object' then
    v_eventos := array(select jsonb_array_elements_text(case when jsonb_typeof(g -> 'eventos') = 'array' then g -> 'eventos' else '[]'::jsonb end));
    v_paginas := case when jsonb_typeof(g -> 'paginas') = 'array' and jsonb_array_length(g -> 'paginas') > 0
                      then array(select jsonb_array_elements_text(g -> 'paginas'))
                      else array[coalesce(g ->> 'pagina', 'obrigado')] end;
    v_cta := coalesce(g ->> 'cta', '');
  end if;

  with
  t as materialized (select * from radar.testes where projeto = v_proj and tipo = 'split'),
  -- as visitas marcadas com a versao (o script da pagina manda o split_visto com o cookie radar_split)
  vistos as materialized (
    select distinct e.sessao, e.dados ->> 'versao' as chave
    from radar.eventos_funil e
    where e.projeto = v_proj and e.nome = 'split_visto' and e.dia between v_de and v_ate
      and split_part(e.dados ->> 'versao', ':', 1) in (select t.id::text from t)),
  vs0 as materialized (
    select distinct on (s.id) s.id, split_part(v.chave, ':', 1)::bigint as teste, split_part(v.chave, ':', 2) as versao,
           s.dia, s.visitante, radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u, s.lead, s.resultado
    from vistos v join radar.sessoes s on s.id = v.sessao
    where s.projeto = v_proj and (v_teste or not s.teste) and coalesce(s.visivel_ms, 0) > 0
      and (v_disp = '' or s.dispositivo = v_disp)
    order by s.id, v.chave),
  -- o resultado da pesquisa do lead: o da visita ou, quando a pesquisa veio depois noutra visita (a pesquisa pelo link do
  -- PB), o primeiro do mesmo navegador ate 7 dias depois
  vs as materialized (
    select vs0.id, vs0.teste, vs0.versao, vs0.dia, vs0.visitante, vs0.u, vs0.lead,
           coalesce(vs0.resultado, case when vs0.lead then (
             select x.resultado from radar.sessoes x
             where x.projeto = v_proj and x.visitante = vs0.visitante and x.dia between vs0.dia and vs0.dia + 7 and x.resultado is not null
             order by x.resultado_em nulls last, x.inicio limit 1) end) as resultado
    from vs0),
  -- dos leads, quem foi levado ao grupo (mesma regra da radar_crm.grupo_calcular)
  gr as materialized (
    select vs.id, exists (
      select 1 from radar.sessoes x
      where x.projeto = v_proj and x.visitante = vs.visitante and x.dia between vs.dia and vs.dia + 1
        and (exists (select 1 from radar.eventos_funil e where e.sessao = x.id and e.nome = any (v_eventos))
             or (v_cta <> '' and exists (select 1 from radar.cliques c where c.sessao = x.id and c.pagina = any (v_paginas)
                                         and strpos(c.seletor, '[data-cta="' || v_cta || '"]') > 0)))) as foi
    from vs where vs.lead and v_eventos is not null),
  pv as (
    select vs.teste, vs.versao, count(distinct vs.u)::int as visitas, count(distinct vs.u) filter (where vs.lead)::int as leads,
           count(distinct vs.u) filter (where gr.foi)::int as grupo
    from vs left join gr on gr.id = vs.id group by 1, 2),
  -- pelo servidor (o CRM): as pessoas inscritas que tem o navegador de um lead da versao, e quantas sao MQL (radar_crm.pessoas.mql)
  srv as (
    select vs.teste, vs.versao, count(distinct p.id)::int as pessoas, count(distinct p.id) filter (where p.mql = 'sim')::int as mql
    from vs join radar_crm.pessoas p on p.visitante = vs.visitante and p.projeto = v_proj and not p.teste
    where vs.lead and vs.visitante <> '' group by 1, 2),
  pr as (
    select teste, versao, jsonb_object_agg(resultado, n) as resultados
    from (select teste, versao, resultado, count(distinct u)::int as n from vs where resultado is not null group by 1, 2, 3) x
    group by 1, 2),
  ent as (
    select e.teste, e.versao, e.dia, sum(e.n)::int as n
    from radar.split_entregas e where e.teste in (select id from t) and e.dia between v_de and v_ate group by 1, 2, 3),
  ent_tot as (select teste, dia, sum(n) as n from ent group by 1, 2),
  gasto as (
    select t.id as teste, m.dia, sum(m.gasto) as gasto
    from t join radar.meta_anuncios_dia m on m.projeto = t.projeto and m.dia between v_de and v_ate
    where jsonb_array_length(t.anuncios) > 0
      and (m.anuncio_id in (select jsonb_array_elements_text(t.anuncios))
           or m.conjunto_id in (select jsonb_array_elements_text(t.anuncios))
           or m.campanha_id in (select jsonb_array_elements_text(t.anuncios)))
    group by 1, 2),
  custo as (
    select e.teste, e.versao, sum(gs.gasto * e.n / tt.n) as custo
    from ent e join ent_tot tt on tt.teste = e.teste and tt.dia = e.dia join gasto gs on gs.teste = e.teste and gs.dia = e.dia
    where tt.n > 0 group by 1, 2),
  dias as (
    select teste, versao, dia, sum(ent)::int as entregas, sum(vis)::int as visitas, sum(lea)::int as leads
    from (select teste, versao, dia, n as ent, 0 as vis, 0 as lea from ent
          union all
          select teste, versao, dia, 0, count(distinct u), count(distinct u) filter (where lead) from vs group by 1, 2, 3) x
    group by 1, 2, 3)
  select jsonb_build_object(
    'de', v_de::text, 'ate', v_ate::text, 'hoje', radar.hoje()::text, 'tem_grupo', v_eventos is not null,
    'splits', coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'nome', t.nome, 'hipotese', t.hipotese, 'estado', t.estado, 'dominio_split', t.dominio_split, 'entrada', t.entrada,
      'versoes', t.versoes, 'promovida', t.promovida, 'anuncios', t.anuncios, 'historico', t.historico,
      'inicio', t.inicio::text, 'fim', t.fim::text, 'criado_em', radar.ms(t.criado_em),
      'rodou', exists (select 1 from jsonb_array_elements(t.historico) h where h ->> 'acao' = 'rodar'),
      -- dias corridos desde que ligou ate hoje (ou ate o fim)
      'dias', case when exists (select 1 from jsonb_array_elements(t.historico) h where h ->> 'acao' = 'rodar')
                   then greatest(0, least(coalesce(t.fim, radar.hoje()), radar.hoje()) - t.inicio + 1) else 0 end,
      'numeros', coalesce((
         select jsonb_agg(jsonb_build_object(
                  'versao', vv.id,
                  'entregas', coalesce((select sum(e.n) from ent e where e.teste = t.id and e.versao = vv.id), 0),
                  'visitas', coalesce(pv.visitas, 0), 'leads', coalesce(pv.leads, 0),
                  'grupo', case when v_eventos is not null then coalesce(pv.grupo, 0) end,
                  'resultados', coalesce(pr.resultados, '{}'::jsonb),
                  'servidor', jsonb_build_object('pessoas', coalesce(srv.pessoas, 0), 'mql', coalesce(srv.mql, 0)),
                  'custo', case when jsonb_array_length(t.anuncios) > 0 then round(coalesce(c.custo, 0), 2) end)
                order by vv.id)
         from (select x ->> 'id' as id from jsonb_array_elements(t.versoes) x) vv
         left join pv on pv.teste = t.id and pv.versao = vv.id
         left join pr on pr.teste = t.id and pr.versao = vv.id
         left join srv on srv.teste = t.id and srv.versao = vv.id
         left join custo c on c.teste = t.id and c.versao = vv.id), '[]'::jsonb),
      -- visitas com uma versao que o teste nao tem mais (cookie antigo): so para conferir
      'fora', coalesce((select sum(pv.visitas) from pv where pv.teste = t.id
                          and pv.versao <> all (array(select x ->> 'id' from jsonb_array_elements(t.versoes) x))), 0),
      'gasto', case when jsonb_array_length(t.anuncios) > 0 then jsonb_build_object(
         'total', coalesce((select round(sum(gs.gasto), 2) from gasto gs where gs.teste = t.id), 0),
         'sem_entrega', coalesce((select round(sum(gs.gasto), 2) from gasto gs where gs.teste = t.id
                                    and not exists (select 1 from ent_tot tt where tt.teste = gs.teste and tt.dia = gs.dia and tt.n > 0)), 0)) end,
      'por_dia', coalesce((
         select jsonb_agg(jsonb_build_object('dia', d.dia::text, 'versao', d.versao, 'entregas', d.entregas, 'visitas', d.visitas, 'leads', d.leads)
                          order by d.dia, d.versao)
         from dias d where d.teste = t.id), '[]'::jsonb))
      order by case t.estado when 'rodando' then 0 when 'pausado' then 1 when 'rascunho' then 2 else 3 end, t.criado_em desc, t.id desc), '[]'::jsonb))
  into v_res
  from t;
  return v_res;
end $$;


--
-- Name: api_tempos(integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_tempos(p_dias integer) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object(
    'dias', least(greatest(p_dias, 1), 60),
    'rotas', coalesce((
      select jsonb_agg(jsonb_build_object('rota', rota, 'origem', origem, 'chamadas', n, 'media_ms', media, 'max_ms', pior, 'lentas', lentas)
                       order by pior desc)
      from (select rota, origem, sum(chamadas)::int n, round(sum(total_ms)::numeric / nullif(sum(chamadas), 0))::int media,
                   max(max_ms) pior, sum(lentas)::int lentas
            from radar.tempos_api
            where dia > radar.hoje() - least(greatest(p_dias, 1), 60)
            group by rota, origem) x), '[]'::jsonb),
    'por_dia', coalesce((
      select jsonb_agg(jsonb_build_object('dia', dia::text, 'chamadas', n, 'max_ms', pior, 'lentas', lentas) order by dia)
      from (select dia, sum(chamadas)::int n, max(max_ms) pior, sum(lentas)::int lentas
            from radar.tempos_api
            where dia > radar.hoje() - least(greatest(p_dias, 1), 60)
            group by dia) y), '[]'::jsonb))
$$;


--
-- Name: api_testes(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_testes(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
t as (select * from radar.testes where projeto = f ->> 'projeto' and tipo = 'ab'),   -- 076: o split mora na rota splits
-- quem entrou por uma das duas paginas de cada teste, do inicio ao fim (ou ate hoje), so visitas que apareceram
d as materialized (
  select t.id, t.metrica, s.dia, case when s.primeira_pagina = t.pagina_a then 'a' else 'b' end as braco,
         radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u,
         coalesce(s.utm_source, '(direto)') as origem, s.lead, (s.resultado = 'mql') is true as mql,
         (s.engajada or radar.encerrada(s.recebido_em)) as conta, (not s.engajada and radar.encerrada(s.recebido_em)) as rejeitou
  from t
  join radar.sessoes s on s.projeto = t.projeto and s.dia >= t.inicio and s.dia <= coalesce(t.fim, radar.hoje() + 1)
                      and s.primeira_pagina in (t.pagina_a, t.pagina_b)
  where (coalesce(f ->> 'teste', '') = '1' or not s.teste)
    and coalesce(s.visivel_ms, 0) > 0
    and (coalesce(f ->> 'dispositivo', '') = '' or s.dispositivo = f ->> 'dispositivo')),
-- entradas e conversoes em visitas unicas (a taxa do teste); rejeicoes por sessao
bracos as (
  select id, braco, count(distinct u) filter (where conta) as entradas, count(*) filter (where rejeitou) as rejeicoes,
         count(distinct u) filter (where conta and case when metrica = 'mql' then mql else lead end) as conversoes
  from d group by id, braco)
select jsonb_build_object('testes', coalesce((
  select jsonb_agg(jsonb_build_object(
    'id', t.id, 'nome', t.nome, 'hipotese', t.hipotese, 'pagina_a', t.pagina_a, 'pagina_b', t.pagina_b, 'metrica', t.metrica,
    'efeito', t.efeito, 'inicio', t.inicio::text, 'fim', t.fim::text, 'criado_em', radar.ms(t.criado_em),
    -- dias corridos de teste ate hoje (ou ate o fim)
    'dias', greatest(0, least(coalesce(t.fim, radar.hoje()), radar.hoje()) - t.inicio + 1),
    -- o primeiro dia fechado com visita de verdade por uma das versoes: dai em diante a regra do teste trava (024).
    -- Nao olha teste, equipe nem aparelho: e a mesma pergunta que o salvar_teste faz
    'travado_desde', (select min(s.dia)::text from radar.sessoes s
                      where s.projeto = t.projeto and s.primeira_pagina in (t.pagina_a, t.pagina_b)
                        and s.dia >= t.inicio and s.dia < radar.hoje() and (t.fim is null or s.dia <= t.fim)
                        and not s.teste and coalesce(s.visivel_ms, 0) > 0),
    'a', coalesce((select jsonb_build_object('entradas', entradas, 'rejeicoes', rejeicoes, 'conversoes', conversoes) from bracos b where b.id = t.id and b.braco = 'a'),
                  jsonb_build_object('entradas', 0, 'rejeicoes', 0, 'conversoes', 0)),
    'b', coalesce((select jsonb_build_object('entradas', entradas, 'rejeicoes', rejeicoes, 'conversoes', conversoes) from bracos b where b.id = t.id and b.braco = 'b'),
                  jsonb_build_object('entradas', 0, 'rejeicoes', 0, 'conversoes', 0)),
    'por_dia', coalesce((
       select jsonb_agg(jsonb_build_object('dia', dia::text, 'a', a, 'b', b, 'ca', ca, 'cb', cb) order by dia)
       from (select dia, count(distinct u) filter (where braco = 'a' and conta) as a, count(distinct u) filter (where braco = 'b' and conta) as b,
                    count(distinct u) filter (where braco = 'a' and conta and case when metrica = 'mql' then mql else lead end) as ca,
                    count(distinct u) filter (where braco = 'b' and conta and case when metrica = 'mql' then mql else lead end) as cb
             from d where d.id = t.id group by dia) x), '[]'::jsonb),
    -- a mistura de origens de cada versao em cada semana do teste: se muda no meio, o teste perde a validade
    'origens', coalesce((
       select jsonb_agg(jsonb_build_object('semana', semana, 'braco', braco, 'origem', origem, 'n', n) order by semana, braco, n desc)
       from (select (d.dia - t.inicio) / 7 as semana, braco, origem, count(distinct u) as n
             from d where d.id = t.id and conta group by 1, 2, 3) x), '[]'::jsonb))
    order by (t.fim is not null and t.fim < radar.hoje()), t.inicio desc, t.id desc)
  from t), '[]'::jsonb))
$$;


--
-- Name: api_trafego(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_trafego(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
q as (
  select x.de, x.ate, x.de - (x.ate - x.de + 1) as ant_de, x.de - 1 as ant_ate,
         x.hoje - 2 as j3_de, x.hoje as j3_ate, x.hoje - 9 as j7_de, x.hoje - 3 as j7_ate
  from (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate,
               radar.hoje() as hoje) x),
-- as pessoas novas do CRM (o servidor) no periodo e no anterior, com o anuncio do primeiro envio
gente as materialized (
  select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, x.pagina_primeira as pagina,
         coalesce(x.origem_primeira ->> 'utm_content', '') as anuncio, coalesce(x.origem_primeira ->> 'utm_campaign', '') as campanha,
         x.plataforma, x.mql, x.active_novo
  from radar_crm.pessoas x, q
  where x.projeto = f ->> 'projeto' and not x.teste
    and (x.primeiro_em at time zone 'America/Sao_Paulo')::date between q.ant_de and q.ate
    and (coalesce(f ->> 'pagina', '') = '' or x.pagina_primeira = f ->> 'pagina')
    and radar.canal_crm(x.plataforma, f ->> 'canal')),
-- as visitas dos anuncios (o navegador), em visita unica (radar.unidade), do comeco do periodo anterior (ou da janela
-- de 7 dias, o que vier antes) ate hoje; sem filtro de trafego, so as que vieram de anuncio; 053: so as que comecaram numa
-- pagina de entrada (a /quase-la/ depois da BL2 nao e visita de anuncio)
vis as materialized (
  select s.dia, coalesce(s.utm_content, '') as anuncio, coalesce(s.utm_campaign, '') as campanha, s.lead,
         radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u
  from q, radar.filtradas(f || jsonb_build_object('de', least(q.ant_de, q.j7_de)::text, 'ate', greatest(q.ate, q.j3_ate)::text,
                                                  'canal', coalesce(nullif(f ->> 'canal', ''), 'pago'), 'entrada', '1')) s),
crm_ad as (
  select g.anuncio, mode() within group (order by g.campanha) as campanha, mode() within group (order by g.pagina) as pagina,
         mode() within group (order by g.plataforma) as plataforma,
         count(*) filter (where g.dia between q.de and q.ate) as leads,
         count(*) filter (where g.dia between q.de and q.ate and g.mql in ('sim', 'nao')) as responderam,
         count(*) filter (where g.dia between q.de and q.ate and g.mql = 'sim') as mql,
         count(*) filter (where g.dia between q.de and q.ate and g.active_novo) as novos,
         count(*) filter (where g.dia between q.de and q.ate and g.active_novo = false) as existiam
  from gente g, q group by g.anuncio),
nav_ad as (
  select v.anuncio, mode() within group (order by v.campanha) as campanha,
         count(distinct v.u) filter (where v.dia between q.de and q.ate) as visitas,
         count(distinct v.u) filter (where v.dia between q.de and q.ate and v.lead) as leads_nav,
         count(distinct v.u) filter (where v.dia between q.j3_de and q.j3_ate) as visitas_3d,
         count(distinct v.u) filter (where v.dia between q.j3_de and q.j3_ate and v.lead) as leads_3d,
         count(distinct v.u) filter (where v.dia between q.j7_de and q.j7_ate) as visitas_7d,
         count(distinct v.u) filter (where v.dia between q.j7_de and q.j7_ate and v.lead) as leads_7d
  from vis v, q group by v.anuncio),
ads as (
  select coalesce(c.anuncio, n.anuncio) as anuncio, coalesce(nullif(c.campanha, ''), n.campanha, '') as campanha,
         c.pagina, c.plataforma,
         coalesce(c.leads, 0) as leads, coalesce(c.responderam, 0) as responderam, coalesce(c.mql, 0) as mql,
         coalesce(c.novos, 0) as novos, coalesce(c.existiam, 0) as existiam,
         coalesce(n.visitas, 0) as visitas, coalesce(n.leads_nav, 0) as leads_nav,
         coalesce(n.visitas_3d, 0) as visitas_3d, coalesce(n.leads_3d, 0) as leads_3d,
         coalesce(n.visitas_7d, 0) as visitas_7d, coalesce(n.leads_7d, 0) as leads_7d
  from crm_ad c full join nav_ad n on n.anuncio = c.anuncio),
numeros as (
  select jsonb_build_object(
    'atual', jsonb_build_object('leads', count(*) filter (where g.dia between q.de and q.ate),
             'responderam', count(*) filter (where g.dia between q.de and q.ate and g.mql in ('sim', 'nao')),
             'mql', count(*) filter (where g.dia between q.de and q.ate and g.mql = 'sim'),
             'novos', count(*) filter (where g.dia between q.de and q.ate and g.active_novo),
             'existiam', count(*) filter (where g.dia between q.de and q.ate and g.active_novo = false)),
    'anterior', jsonb_build_object('leads', count(*) filter (where g.dia between q.ant_de and q.ant_ate),
             'responderam', count(*) filter (where g.dia between q.ant_de and q.ant_ate and g.mql in ('sim', 'nao')),
             'mql', count(*) filter (where g.dia between q.ant_de and q.ant_ate and g.mql = 'sim'),
             'novos', count(*) filter (where g.dia between q.ant_de and q.ant_ate and g.active_novo),
             'existiam', count(*) filter (where g.dia between q.ant_de and q.ant_ate and g.active_novo = false))) as j
  from q left join gente g on true)
select jsonb_build_object(
  'de', q.de::text, 'ate', q.ate::text, 'anterior_de', q.ant_de::text, 'anterior_ate', q.ant_ate::text,
  'janela_3', jsonb_build_object('de', q.j3_de::text, 'ate', q.j3_ate::text),
  'janela_7', jsonb_build_object('de', q.j7_de::text, 'ate', q.j7_ate::text),
  'crm', exists (select 1 from radar_crm.pessoas x where x.projeto = f ->> 'projeto' and not x.teste),
  'desde', radar.crm_desde(f ->> 'projeto')::text,   -- 042: o primeiro dia com o volume de verdade
  'desde_novo', (select min((x.primeiro_em at time zone 'America/Sao_Paulo')::date)::text from radar_crm.pessoas x
                 where x.projeto = f ->> 'projeto' and not x.teste and x.active_novo is not null),
  'atual', (select j -> 'atual' from numeros),
  'anterior', (select j -> 'anterior' from numeros),
  'visitas', (select jsonb_build_object(
                'atual', count(distinct v.u) filter (where v.dia between q.de and q.ate),
                'leads', count(distinct v.u) filter (where v.dia between q.de and q.ate and v.lead),
                'anterior', count(distinct v.u) filter (where v.dia between q.ant_de and q.ant_ate),
                'leads_anterior', count(distinct v.u) filter (where v.dia between q.ant_de and q.ant_ate and v.lead))
              from vis v),
  'dias', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia::text, 'leads', d.leads, 'responderam', d.resp, 'mql', d.mql) order by d.dia)
                    from (select g.dia, count(*) as leads, count(*) filter (where g.mql in ('sim', 'nao')) as resp,
                                 count(*) filter (where g.mql = 'sim') as mql
                          from gente g where g.dia between q.de and q.ate group by g.dia) d), '[]'::jsonb),
  'anuncios', coalesce((select jsonb_agg(to_jsonb(a) order by a.visitas + a.leads desc)
                        from (select * from ads order by visitas + leads desc limit 300) a), '[]'::jsonb))
from q
$$;


--
-- Name: api_trafego_anuncios(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_trafego_anuncios(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
q as (
  select x.de, x.ate, x.hoje - 2 as j3_de, x.hoje as j3_ate, x.hoje - 9 as j7_de, x.hoje - 3 as j7_ate,
         -- 067: o periodo anterior, do mesmo tamanho, logo antes (o custo contra o anterior)
         x.de - (x.ate - x.de + 1) as a_de, x.de - 1 as a_ate,
         -- 070: os dois cortes do dia corrente. O gasto e os cliques de hoje sao os da ultima rodada do robo do Meta (066,
         -- minuto 12 de cada hora), e o proprio Meta ainda completa os cliques da ultima hora (medido em 14/10: cortando as
         -- chegadas na hora da rodada, a BL2 ficava em 101,5% e 101,8%, contra 95,2% do dia fechado).
         -- - corte_conexao (o connect rate, chegadas contra cliques): a hora cheia anterior a da rodada (a rodada das 12h12
         --   corta as 11h00), nunca antes do comeco de hoje (a rodada das 0h12 corta a 0h00: os dias passados nao mudam);
         -- - corte_custo (o custo por visita, por lead e por MQL): a propria hora da rodada, o mesmo relogio do gasto.
         -- So com hoje no periodo e no canal do Meta; sem rodada de hoje, sem corte (hoje nao tem clique nem gasto)
         case when rd.rodada is not null
              then greatest(date_trunc('hour', rd.rodada, 'America/Sao_Paulo') - interval '1 hour',
                            x.hoje::timestamp at time zone 'America/Sao_Paulo') end as corte_conexao,
         rd.rodada as corte_custo
  from (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate,
               radar.hoje() as hoje) x
  cross join lateral (
    select case when x.ate >= x.hoje and coalesce(nullif(f ->> 'canal', ''), 'pago') in ('pago', 'meta')
                then (select max(r.quando) from radar.meta_rodadas r
                      where r.erro is null and r.chamadas > 0 and x.hoje between r.de and r.ate
                        and r.quando > now() - interval '1 day') end as rodada) rd),
-- as pessoas novas do CRM no periodo e nas janelas, com o anuncio do primeiro envio
gente as materialized (
  select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, coalesce(x.pagina_primeira, '') as pagina, x.plataforma,
         coalesce(x.origem_primeira ->> 'utm_campaign', '') as campanha, coalesce(x.origem_primeira ->> 'utm_term', '') as conjunto,
         coalesce(x.origem_primeira ->> 'utm_content', '') as anuncio, x.mql, x.active_novo
  from radar_crm.pessoas x, q
  where x.projeto = f ->> 'projeto' and not x.teste
    and (x.primeiro_em at time zone 'America/Sao_Paulo')::date between least(q.de, q.j7_de, q.a_de) and greatest(q.ate, q.j3_ate)
    and (coalesce(f ->> 'pagina', '') = '' or x.pagina_primeira = f ->> 'pagina')
    and radar.canal_crm(x.plataforma, f ->> 'canal')
    -- 070: hoje, os leads, as respostas e o MQL so ate a rodada do Meta (o relogio do gasto)
    and (q.corte_custo is null or x.primeiro_em <= q.corte_custo)),
srv as (
  select g.campanha, g.conjunto, g.anuncio,
         mode() within group (order by g.pagina) as pagina, mode() within group (order by g.plataforma) as plataforma,
         count(*) filter (where g.dia between q.de and q.ate) as leads,
         count(*) filter (where g.dia between q.de and q.ate and g.mql in ('sim', 'nao')) as responderam,
         count(*) filter (where g.dia between q.de and q.ate and g.mql = 'sim') as mql,
         count(*) filter (where g.dia between q.de and q.ate and g.active_novo) as novos,
         count(*) filter (where g.dia between q.de and q.ate and g.active_novo = false) as existiam,
         count(*) filter (where g.dia between q.j3_de and q.j3_ate) as leads_3d,
         count(*) filter (where g.dia between q.j3_de and q.j3_ate and g.mql in ('sim', 'nao')) as responderam_3d,
         count(*) filter (where g.dia between q.j3_de and q.j3_ate and g.mql = 'sim') as mql_3d,
         count(*) filter (where g.dia between q.j7_de and q.j7_ate) as leads_7d,
         count(*) filter (where g.dia between q.j7_de and q.j7_ate and g.mql in ('sim', 'nao')) as responderam_7d,
         count(*) filter (where g.dia between q.j7_de and q.j7_ate and g.mql = 'sim') as mql_7d
  from gente g, q group by 1, 2, 3),
-- as visitas unicas dos anuncios que entraram por uma pagina de entrada (o gravador), no periodo
-- 070: vis_todas leva todas as chegadas, com depois_custo (chegou hoje depois da rodada) e depois_conexao (depois do corte
-- do connect rate). vis (visitas, sessoes, a taxa da pagina, o custo por visita) fica com as de ate a rodada; as sessoes
-- do connect rate (sessoes_par), so com as de ate o corte dele. Que a pagina tinha o gravador no dia, e qual a pagina do
-- anuncio, vem de todas (e um fato do dia: sem isso, os cliques de hoje sairiam da base antes da primeira chegada)
vis_todas as materialized (
  select coalesce(s.utm_campaign, '') as campanha, coalesce(s.utm_term, '') as conjunto, coalesce(s.utm_content, '') as anuncio, s.lead,
         s.primeira_pagina, radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u,
         -- 068: o dia da sessao (o connect rate por dia)
         (s.inicio at time zone 'America/Sao_Paulo')::date as dia,
         -- 070: os cortes sao de hoje: o que passa deles e sempre de hoje
         q.corte_custo is not null and s.inicio > q.corte_custo as depois_custo,
         q.corte_conexao is not null and s.inicio > q.corte_conexao as depois_conexao
  from q, radar.filtradas(f || jsonb_build_object('de', q.de::text, 'ate', q.ate::text,
                                                  'canal', coalesce(nullif(f ->> 'canal', ''), 'pago'), 'entrada', '1')) s),
vis as (select v.* from vis_todas v where not v.depois_custo),
nav as (
  select v.campanha, v.conjunto, v.anuncio, count(distinct v.u) as visitas, count(distinct v.u) filter (where v.lead) as leads_nav,
         -- 068: as sessoes (cada chegada pelo anuncio, contada como o clique conta: a mesma pessoa duas vezes conta duas)
         count(*) as sessoes,
         -- 067: a pagina de entrada das visitas (o anuncio sem lead tambem tem pagina)
         mode() within group (order by v.primeira_pagina) as pagina_nav
  from vis v group by 1, 2, 3),
-- 056: o que o Meta mede de cada anuncio no periodo (a tabela radar.meta_anuncios_dia, que o robo do Meta enche quando a
-- integracao for ligada). So no canal de anuncio do Meta: com o canal Google ou organico, fica de fora
met as (
  select m.anuncio_id as anuncio, max(m.campanha_id) as campanha, max(m.conjunto_id) as conjunto,
         max(m.campanha_nome) as campanha_nome, max(m.conjunto_nome) as conjunto_nome, max(m.anuncio_nome) as anuncio_nome,
         max(m.miniatura) as miniatura, sum(m.gasto) as gasto, sum(m.impressoes) as impressoes, sum(m.cliques_link) as cliques
  from radar.meta_anuncios_dia m, q
  where m.projeto = f ->> 'projeto' and m.dia between q.de and q.ate
    and coalesce(nullif(f ->> 'canal', ''), 'pago') in ('pago', 'meta')
  group by 1),
linhas as (
  select coalesce(s.campanha, n.campanha, m.campanha, '') as campanha, coalesce(s.conjunto, n.conjunto, m.conjunto, '') as conjunto,
         coalesce(s.anuncio, n.anuncio, m.anuncio) as anuncio,
         s.pagina, s.plataforma,
         coalesce(s.leads, 0) as leads, coalesce(s.responderam, 0) as responderam, coalesce(s.mql, 0) as mql,
         coalesce(s.novos, 0) as novos, coalesce(s.existiam, 0) as existiam,
         coalesce(s.leads_3d, 0) as leads_3d, coalesce(s.responderam_3d, 0) as responderam_3d, coalesce(s.mql_3d, 0) as mql_3d,
         coalesce(s.leads_7d, 0) as leads_7d, coalesce(s.responderam_7d, 0) as responderam_7d, coalesce(s.mql_7d, 0) as mql_7d,
         n.visitas, n.leads_nav, n.pagina_nav, n.sessoes,
         -- 056: o Meta (nulo enquanto a integracao nao estiver ligada), ligado pelo codigo do anuncio (o utm_content e o id dele)
         m.gasto, m.impressoes, m.cliques, m.campanha_nome, m.conjunto_nome, m.anuncio_nome, m.miniatura
  from srv s
  full join nav n on n.campanha = s.campanha and n.conjunto = s.conjunto and n.anuncio = s.anuncio
  full join met m on m.anuncio = coalesce(s.anuncio, n.anuncio)
  -- com a pagina de entrada escolhida, o anuncio so do Meta (sem lead nem visita nela) fica de fora: o Meta nao sabe a pagina
  where coalesce(f ->> 'pagina', '') = '' or s.anuncio is not null or n.anuncio is not null),
-- 067: o custo contra o periodo anterior e por dia, com a mesma regua do topo do Trafego: o gasto dos anuncios do Meta
-- e os leads, as respostas e o MQL (pelo servidor) desses mesmos anuncios. Com a pagina escolhida no topo, so os
-- anuncios que trouxeram gente por ela
com_gasto as (select l.anuncio from linhas l where l.gasto is not null),
met_ant as (
  select m.anuncio_id as anuncio, sum(m.gasto) as gasto
  from radar.meta_anuncios_dia m, q
  where m.projeto = f ->> 'projeto' and m.dia between q.a_de and q.a_ate
    and coalesce(nullif(f ->> 'canal', ''), 'pago') in ('pago', 'meta')
    and (coalesce(f ->> 'pagina', '') = '' or m.anuncio_id in (select g.anuncio from gente g))
  group by 1),
ant as (
  select (select coalesce(sum(a.gasto), 0) from met_ant a) as gasto,
         count(*) filter (where g.dia between q.a_de and q.a_ate) as leads,
         count(*) filter (where g.dia between q.a_de and q.a_ate and g.mql in ('sim', 'nao')) as responderam,
         count(*) filter (where g.dia between q.a_de and q.a_ate and g.mql = 'sim') as mql
  from q left join gente g on g.anuncio in (select a.anuncio from met_ant a)),
gasto_dia as (
  select m.dia, sum(m.gasto) as gasto
  from radar.meta_anuncios_dia m, q
  where m.projeto = f ->> 'projeto' and m.dia between q.de and q.ate and m.anuncio_id in (select c.anuncio from com_gasto c)
  group by 1),
-- 068: o connect rate (sessoes que chegaram na pagina / cliques no link do Meta), com a mesma base nas duas pontas: so os
-- anuncios com gasto cuja pagina de entrada tem o gravador (a pagina das pessoas e das visitas do anuncio; o gravador, as
-- paginas em que ele viu visita de anuncio no periodo ou no anterior). Anuncio que leva a pagina sem gravador fica fora
vis_ant as materialized (
  select coalesce(s.utm_content, '') as anuncio, s.primeira_pagina, (s.inicio at time zone 'America/Sao_Paulo')::date as dia
  from q, radar.filtradas(f || jsonb_build_object('de', q.a_de::text, 'ate', q.a_ate::text,
                                                  'canal', coalesce(nullif(f ->> 'canal', ''), 'pago'), 'entrada', '1')) s),
-- a pagina com o gravador DIA A DIA: o clique so conta no dia em que a pagina do anuncio ja tinha o gravador (a BL2 so
-- ganhou o gravador em 05/10/2026; contar os cliques dela antes disso, sem as visitas, derrubava o connect rate)
pag_dia as materialized (select distinct v.primeira_pagina as pagina, v.dia from vis_todas v where v.primeira_pagina is not null
            union select v.primeira_pagina, v.dia from vis_ant v where v.primeira_pagina is not null),
ad_pag as materialized (
  select x.anuncio, mode() within group (order by x.pagina) as pagina
  from (select g.anuncio, g.pagina from gente g where g.pagina <> ''
        union all select v.anuncio, v.primeira_pagina from vis_todas v where v.primeira_pagina is not null
        union all select v.anuncio, v.primeira_pagina from vis_ant v where v.primeira_pagina is not null) x
  group by 1),
-- os cliques de cada anuncio com gasto em cada dia em que a pagina dele tinha o gravador (periodo e anterior juntos)
cliques_base as materialized (
  select m.dia, m.anuncio_id as anuncio, m.cliques_link as cliques,
         -- 069: as visualizacoes da pagina de destino do Meta (nulo antes da carga da 069)
         m.lpv
  from q
  join radar.meta_anuncios_dia m on m.projeto = f ->> 'projeto' and m.dia between q.a_de and q.ate
  join ad_pag p on p.anuncio = m.anuncio_id
  join pag_dia pd on pd.pagina = p.pagina and pd.dia = m.dia
  where coalesce(nullif(f ->> 'canal', ''), 'pago') in ('pago', 'meta')
    and (m.anuncio_id in (select c.anuncio from com_gasto c) or m.anuncio_id in (select a.anuncio from met_ant a))),
cliques_dia as (
  select cb.dia, sum(cb.cliques) as cliques,
         -- 069: o connect rate do Meta nos mesmos cliques: as LPV e os cliques so das linhas que ja tem a LPV
         sum(cb.lpv) as lpv, sum(cb.cliques) filter (where cb.lpv is not null) as cliques_lpv
  from cliques_base cb, q
  where cb.dia between q.de and q.ate and cb.anuncio in (select c.anuncio from com_gasto c) group by 1),
-- as sessoes dos mesmos anuncios (so existem nos dias com o gravador)
-- as sessoes so nos pares anuncio-dia que tem clique na base (ressalva 1 do Grilo: a sessao de um dia sem clique do
-- anuncio, ou sem gravador, nao entra no numerador sem o clique correspondente)
sessoes_par as materialized (
  select v.anuncio, v.dia, count(*) as sessoes from vis v
  join cliques_base cb on cb.anuncio = v.anuncio and cb.dia = v.dia
  -- 070: hoje, so as chegadas ate o corte do connect rate
  where not v.depois_conexao
  group by 1, 2),
sessoes_dia as (select sp.dia, sum(sp.sessoes) as sessoes from sessoes_par sp group by 1),
leads_dia as (
  select g.dia, count(*) as leads, count(*) filter (where g.mql = 'sim') as mql
  from gente g, q where g.dia between q.de and q.ate and g.anuncio in (select c.anuncio from com_gasto c)
  group by 1)
select jsonb_build_object(
  'ok', true, 'de', q.de::text, 'ate', q.ate::text,
  -- 070: os cortes usados em hoje (nulos sem hoje no periodo): a tela mostra "parcial ate 11h" no connect rate e
  -- "parcial ate 12h" nos custos
  'corte_conexao', q.corte_conexao, 'corte_custo', q.corte_custo,
  'janela_3', jsonb_build_object('de', q.j3_de::text, 'ate', q.j3_ate::text),
  'janela_7', jsonb_build_object('de', q.j7_de::text, 'ate', q.j7_ate::text),
  'crm', exists (select 1 from radar_crm.pessoas x where x.projeto = f ->> 'projeto' and not x.teste),
  'desde', radar.crm_desde(f ->> 'projeto')::text,
  -- as paginas de entrada em que o gravador viu visita de anuncio no periodo (as outras nao tem a coluna de visitas)
  -- 067: os fluxos de entrada do contrato (fluxo.entradas: id, nome, paginas), na ordem dele: o custo por fluxo do
  -- Trafego agrupa os anuncios pela pagina de entrada, como o Fluxo
  'fluxos', coalesce((select jsonb_agg(jsonb_build_object('id', x.e ->> 'id', 'nome', x.e ->> 'nome', 'paginas', coalesce(x.e -> 'paginas', '[]'::jsonb))
                                       order by x.o)
                      from radar.projetos p, jsonb_array_elements(case when jsonb_typeof(p.config -> 'fluxo' -> 'entradas') = 'array'
                                                                       then p.config -> 'fluxo' -> 'entradas' else '[]'::jsonb end) with ordinality x(e, o)
                      where p.id = f ->> 'projeto'), '[]'::jsonb),
  'gravador', coalesce((select jsonb_agg(distinct v.primeira_pagina) from vis_todas v where v.primeira_pagina is not null), '[]'::jsonb),
  -- 056: a integracao do Meta: ligada (ja tem dado do projeto), o ultimo dia com dado e a ultima atualizacao
  'meta', (select jsonb_build_object('ligado', count(*) > 0, 'ultimo_dia', max(m.dia)::text, 'atualizado_em', max(m.atualizado_em), 'moeda', max(m.moeda),
             -- 067: o primeiro dia com dado do Meta (antes dele, o periodo anterior nao tem gasto para comparar)
             'primeiro_dia', min(m.dia)::text,
             -- 067: o periodo anterior (gasto e os leads, respostas e MQL dos anuncios com gasto nele)
             'anterior', (select jsonb_build_object('de', q.a_de::text, 'ate', q.a_ate::text, 'gasto', a.gasto, 'leads', a.leads,
                                                    'responderam', a.responderam, 'mql', a.mql,
                                                    -- 068: o connect rate do anterior, com a mesma regua
                                                    'cliques', (select coalesce(sum(cb.cliques), 0) from cliques_base cb
                                                                where cb.dia between q.a_de and q.a_ate and cb.anuncio in (select a2.anuncio from met_ant a2)),
                                                    -- 069: o connect rate do Meta do anterior (nulo sem LPV)
                                                    'lpv', (select sum(cb.lpv) from cliques_base cb
                                                            where cb.dia between q.a_de and q.a_ate and cb.anuncio in (select a2.anuncio from met_ant a2)),
                                                    'cliques_lpv', (select sum(cb.cliques) filter (where cb.lpv is not null) from cliques_base cb
                                                                    where cb.dia between q.a_de and q.a_ate and cb.anuncio in (select a2.anuncio from met_ant a2)),
                                                    'sessoes', (select count(*) from vis_ant v
                                                                join cliques_base cb on cb.anuncio = v.anuncio and cb.dia = v.dia
                                                                where cb.anuncio in (select a2.anuncio from met_ant a2)))
                          from ant a),
             -- 068: o connect rate do periodo (as duas pontas dos mesmos anuncios)
             'conexao', jsonb_build_object('cliques', (select coalesce(sum(cd.cliques), 0) from cliques_dia cd),
                                           'sessoes', (select coalesce(sum(sd.sessoes), 0) from sessoes_dia sd),
                                           -- 069: as LPV do Meta e os cliques das linhas que ja tem a LPV (nulos antes da carga)
                                           'lpv', (select sum(cd.lpv) from cliques_dia cd),
                                           'cliques_lpv', (select sum(cd.cliques_lpv) from cliques_dia cd),
                                           'anuncios', (select count(distinct cb.anuncio) from cliques_base cb where cb.dia between q.de and q.ate)),
             -- 067: o gasto, os leads e o MQL por dia (dos anuncios com gasto no periodo)
             'dias', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia::text, 'gasto', coalesce(gd.gasto, 0), 'leads', coalesce(ld.leads, 0),
                                                                   'mql', coalesce(ld.mql, 0),
                                                                   -- 068: as duas pontas do connect rate do dia
                                                                   'cliques', coalesce(cd.cliques, 0), 'sessoes', coalesce(sd.sessoes, 0),
                                                                   -- 069: as LPV do Meta do dia (nulo sem LPV)
                                                                   'lpv', cd.lpv, 'cliques_lpv', cd.cliques_lpv) order by d.dia)
                               from generate_series(q.de, q.ate, interval '1 day') d0(d)
                               cross join lateral (select d0.d::date as dia) d
                               left join gasto_dia gd on gd.dia = d.dia left join leads_dia ld on ld.dia = d.dia
                               left join cliques_dia cd on cd.dia = d.dia left join sessoes_dia sd on sd.dia = d.dia), '[]'::jsonb),
             -- 067: a ultima rodada do robo que trouxe dado (para a tela avisar quando ficar velho) e se a ultima falhou
             'rodada', (select jsonb_build_object('quando', max(r.quando) filter (where r.erro is null and r.chamadas > 0),
                                                  'falhou', (array_agg(r.erro is not null order by r.id desc))[1])
                        from radar.meta_rodadas r where r.quando > now() - interval '7 days'))
           from radar.meta_anuncios_dia m where m.projeto = f ->> 'projeto'),
  -- 068: em cada anuncio, cliques_conexao: os cliques no link so dos dias em que a pagina dele tinha o gravador (a ponta de
  -- cima do connect rate da linha; as sessoes ja so existem nesses dias)
  'anuncios', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object('cliques_conexao',
                                           (select sum(cb.cliques) from cliques_base cb where cb.anuncio = l.anuncio and cb.dia between q.de and q.ate),
                                           -- as sessoes do connect rate: so nos pares anuncio-dia com clique na base
                                           'sessoes_conexao', (select sum(sp.sessoes) from sessoes_par sp where sp.anuncio = l.anuncio),
                                           -- 069: as LPV do Meta nos mesmos cliques, e os cliques das linhas com LPV
                                           'lpv_conexao', (select sum(cb.lpv) from cliques_base cb where cb.anuncio = l.anuncio and cb.dia between q.de and q.ate),
                                           'cliques_lpv', (select sum(cb.cliques) filter (where cb.lpv is not null) from cliques_base cb
                                                           where cb.anuncio = l.anuncio and cb.dia between q.de and q.ate))
                                         order by l.leads desc, coalesce(l.visitas, 0) desc, l.anuncio)
                        from (select * from linhas where leads > 0 or coalesce(visitas, 0) > 0 or leads_3d > 0 or coalesce(gasto, 0) > 0
                              order by leads desc, coalesce(visitas, 0) desc limit 500) l), '[]'::jsonb))
from q
$$;


--
-- Name: api_trafego_quando(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_trafego_quando(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
with
q as (
  select x.de, x.ate, greatest(x.ate - 13, coalesce(radar.crm_desde(f ->> 'projeto'), x.ate - 13)) as h_de
  from (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate) x),
-- as pessoas novas do CRM no periodo e na janela do horario, com o lugar do anuncio e o estado pelo DDD (o telefone fica aqui)
gente as materialized (
  select x.primeiro_em at time zone 'America/Sao_Paulo' as quando, x.mql, x.active_novo, coalesce(x.pagina_primeira, '') as pagina,
         case when x.plataforma = 'google' then 'google'
              when x.plataforma = 'meta' then
                case lower(coalesce(x.origem_primeira ->> 'utm_source', ''))
                  when 'ig' then 'instagram' when 'instagram' then 'instagram'
                  when 'fb' then 'facebook' when 'facebook' then 'facebook'
                  when 'th' then 'threads' when 'threads' then 'threads'
                  when 'an' then 'audience' when 'msg' then 'messenger' when 'messenger' then 'messenger'
                  else 'meta' end
              when x.plataforma is null then 'sem'
              else 'outro' end as lugar,
         -- o DDD: o servidor guarda o telefone sempre como 55 + DDD + numero (radar_crm.telefone_limpo, regra da casa)
         radar.uf_do_ddd(case when length(t.d) in (12, 13) and t.d like '55%' then substr(t.d, 3, 2)
                              when length(t.d) in (10, 11) then substr(t.d, 1, 2) end) as uf
  from radar_crm.pessoas x
  cross join q
  cross join lateral (select regexp_replace(coalesce(x.telefone, ''), '\D', '', 'g') as d) t
  where x.projeto = f ->> 'projeto' and not x.teste
    and (x.primeiro_em at time zone 'America/Sao_Paulo')::date between least(q.de, q.h_de) and q.ate
    and (coalesce(f ->> 'pagina', '') = '' or x.pagina_primeira = f ->> 'pagina')
    and radar.canal_crm(x.plataforma, f ->> 'canal')),
per as (select g.* from gente g, q where g.quando::date between q.de and q.ate),
-- as visitas unicas dos anuncios (o navegador, so as paginas com o gravador) por app e aparelho, com o LCP da pagina de entrada;
-- 053: so as visitas que comecaram numa pagina de entrada
vis as materialized (
  select coalesce(nullif(s.app, ''), 'navegador') as app, coalesce(nullif(s.dispositivo, ''), 'mobile') as dispositivo, s.lead,
         radar.unidade(s.visitante, s.ad_id, s.utm_content) collate "C" as u,
         (select v.lcp_ms from radar.visualizacoes v where v.sessao = s.id order by v.ordem limit 1) as lcp
  from q, radar.filtradas(f || jsonb_build_object('de', q.de::text, 'ate', q.ate::text, 'canal', coalesce(nullif(f ->> 'canal', ''), 'pago'), 'entrada', '1')) s)
select jsonb_build_object(
  'ok', true, 'de', q.de::text, 'ate', q.ate::text,
  'crm', exists (select 1 from radar_crm.pessoas x where x.projeto = f ->> 'projeto' and not x.teste),
  'desde', radar.crm_desde(f ->> 'projeto')::text,
  -- a janela do horario e quantos dias de cada dia da semana (segunda = 1) ela tem, para a media por dia
  'janela_horario', jsonb_build_object('de', q.h_de::text, 'ate', q.ate::text,
    'dias', (select jsonb_agg(coalesce(n.n, 0) order by w.d)
             from generate_series(1, 7) w(d)
             left join (select extract(isodow from g)::int as d, count(*) as n
                        from generate_series(q.h_de::timestamp, q.ate::timestamp, interval '1 day') g group by 1) n on n.d = w.d)),
  'horas', coalesce((select jsonb_agg(jsonb_build_object('pagina', h.pagina, 'd', h.d, 'h', h.h, 'leads', h.leads, 'responderam', h.resp, 'mql', h.mql)
                                       order by h.pagina, h.d, h.h)
                     from (select g.pagina, extract(isodow from g.quando)::int as d, extract(hour from g.quando)::int as h, count(*) as leads,
                                  count(*) filter (where g.mql in ('sim', 'nao')) as resp, count(*) filter (where g.mql = 'sim') as mql
                           from gente g where g.quando::date between q.h_de and q.ate group by 1, 2, 3) h), '[]'::jsonb),
  'lugares', coalesce((select jsonb_agg(jsonb_build_object('pagina', l.pagina, 'lugar', l.lugar, 'leads', l.leads, 'responderam', l.resp, 'mql', l.mql,
                                                           'novos', l.novos, 'existiam', l.existiam) order by l.leads desc, l.lugar, l.pagina)
                       from (select p.pagina, p.lugar, count(*) as leads, count(*) filter (where p.mql in ('sim', 'nao')) as resp,
                                    count(*) filter (where p.mql = 'sim') as mql, count(*) filter (where p.active_novo) as novos,
                                    count(*) filter (where p.active_novo = false) as existiam
                             from per p group by 1, 2) l), '[]'::jsonb),
  'regioes', coalesce((select jsonb_agg(jsonb_build_object('pagina', r.pagina, 'uf', r.uf, 'leads', r.leads, 'responderam', r.resp, 'mql', r.mql)
                                       order by r.leads desc, r.uf, r.pagina)
                       from (select p.pagina, coalesce(p.uf, 'sem') as uf, count(*) as leads, count(*) filter (where p.mql in ('sim', 'nao')) as resp,
                                    count(*) filter (where p.mql = 'sim') as mql
                             from per p group by 1, 2) r), '[]'::jsonb),
  'apps', coalesce((select jsonb_agg(jsonb_build_object('app', a.app, 'dispositivo', a.dispositivo, 'visitas', a.visitas, 'leads', a.leads,
                                                        'lcp_p75', a.lcp, 'com_lcp', a.com_lcp) order by a.visitas desc, a.app)
                    from (select v.app, v.dispositivo, count(distinct v.u) as visitas, count(distinct v.u) filter (where v.lead) as leads,
                                 round(percentile_cont(0.75) within group (order by v.lcp) filter (where v.lcp > 0))::int as lcp,
                                 count(*) filter (where v.lcp > 0) as com_lcp
                          from vis v group by 1, 2) a), '[]'::jsonb))
from q
$$;


--
-- Name: api_valores(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.api_valores(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  with s as (select utm_source, utm_campaign, utm_content, sistema, app, estado from radar.sessoes
             where projeto = f ->> 'projeto' and dia >= radar.hoje() - 400)
  select jsonb_build_object(
    'utm_source', coalesce((select jsonb_agg(x order by x) from (select distinct utm_source x from s where utm_source is not null) a), '[]'::jsonb),
    'utm_campaign', coalesce((select jsonb_agg(x order by x) from (select distinct utm_campaign x from s where utm_campaign is not null) a), '[]'::jsonb),
    'utm_content', coalesce((select jsonb_agg(x order by x) from (select distinct utm_content x from s where utm_content is not null) a), '[]'::jsonb),
    'sistema', coalesce((select jsonb_agg(x order by x) from (select distinct sistema x from s where sistema is not null) a), '[]'::jsonb),
    'app', coalesce((select jsonb_agg(x order by x) from (select distinct app x from s where app is not null) a), '[]'::jsonb),
    'estado', coalesce((select jsonb_agg(x order by x) from (select distinct estado x from s where estado is not null) a), '[]'::jsonb))
$$;


--
-- Name: areas_da_rota(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.areas_da_rota(p_rota text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select case p_rota
    when 'resumo' then array['funil', 'trafego', 'problemas']
    when 'captura' then array['funil', 'leads']
    when 'pagina' then array['pagina']
    when 'leitura' then array['pagina', 'leads']
    when 'oportunidades' then array['pagina', 'melhorias']
    when 'achados' then array['pagina', 'melhorias']
    when 'registrar_achados' then array['melhorias']
    when 'marcar_achado' then array['melhorias']
    when 'fluxo' then array['fluxo', 'crm']
    when 'trafego' then array['trafego', 'melhorias']
    when 'leads_mql' then array['leads']
    when 'sessoes' then array['gravacoes', 'leads', 'instalacao']
    when 'sessao' then array['gravacoes', 'leads']
    when 'gravacao' then array['gravacoes', 'leads', 'mapa']
    when 'guardadas' then array['gravacoes']
    when 'guardar_gravacao' then array['gravacoes', 'leads']
    when 'desguardar_gravacao' then array['gravacoes', 'leads']
    when 'mapa' then array['mapa']
    when 'insights' then array['problemas']
    when 'desempenho' then array['velocidade']
    when 'guardiao' then array['velocidade']
    when 'laboratorio' then array['velocidade']
    when 'relatorio' then array['velocidade']
    when 'salvar_laboratorio' then array['velocidade']
    when 'testes' then array['melhorias']
    when 'salvar_teste' then array['melhorias']
    when 'encerrar_teste' then array['melhorias']
    when 'remover_teste' then array['melhorias']
    -- 076: o split, com os testes (a area 'testes' nao existe na matriz das funcoes)
    when 'splits' then array['melhorias']
    when 'salvar_split' then array['melhorias']
    when 'estado_split' then array['melhorias']
    when 'remover_split' then array['melhorias']
    when 'crm_resumo' then array['crm']
    when 'crm_lista' then array['crm']
    when 'crm_ficha' then array['crm']
    -- 046: o catalogo do Active, para o dicionario do Fluxo
    when 'active_catalogo' then array['fluxo', 'crm']
    -- 050: os resultados das pesquisas
    when 'pesquisas' then array['pesquisas']
    -- 052: o Quando e onde do Trafego (as hipoteses dela tambem aparecem em Melhorias)
    when 'trafego_quando' then array['trafego', 'melhorias']
    -- 054: o ranking e o funil por anuncio
    when 'trafego_anuncios' then array['trafego', 'melhorias']
    -- 059: o segmento do Fluxo, com quem ve o Fluxo
    when 'fluxo_segmento' then array['fluxo', 'crm']
    -- 060: as publicacoes nos graficos por dia, para quem ve uma tela com grafico por dia
    when 'publicacoes' then array['funil', 'trafego', 'leads', 'velocidade', 'pagina', 'melhorias']
    -- 062: o que cada pagina capta (ler: Projetos e instalacao; mudar: so o administrador, conferido na public.radar_api)
    when 'captacao' then array['instalacao']
    when 'salvar_captacao' then array['instalacao']
    else null
  end
$$;


--
-- Name: todas_as_areas(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.todas_as_areas() RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select array['funil', 'pagina', 'fluxo', 'trafego', 'leads', 'crm', 'pesquisas', 'gravacoes', 'mapa', 'problemas', 'velocidade',
               'melhorias', 'instalacao']
$$;


--
-- Name: membros; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.membros (
    usuario uuid NOT NULL,
    nome text NOT NULL,
    email text NOT NULL,
    papel text DEFAULT 'leitor'::text NOT NULL,
    projetos text[] DEFAULT '{}'::text[] NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_por uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    nivel text DEFAULT 'agregado'::text NOT NULL,
    funcao text,
    areas text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT membros_funcao_check CHECK ((((papel = 'equipe'::text) = (funcao IS NOT NULL)) AND ((funcao IS NULL) OR (funcao = ANY (ARRAY['web'::text, 'trafego'::text, 'mensageria'::text, 'projetos'::text, 'dados'::text]))) AND (areas <@ radar.todas_as_areas()))),
    CONSTRAINT membros_nivel_check CHECK ((nivel = ANY (ARRAY['agregado'::text, 'sessoes'::text]))),
    CONSTRAINT membros_papel_check CHECK ((papel = ANY (ARRAY['admin'::text, 'equipe'::text, 'leitor'::text])))
);


--
-- Name: areas_de(radar.membros); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.areas_de(m radar.membros) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(array(select a from unnest(radar.todas_as_areas()) with ordinality x(a, i) where radar.ve_area(m, a) order by i), '{}')
$$;


--
-- Name: arquivo_limpo(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.arquivo_limpo(arquivo text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$
  select left(regexp_replace(arquivo, '[?#].*$', ''), 80)
$_$;


--
-- Name: bloqueia_cadastro_aberto(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.bloqueia_cadastro_aberto() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if coalesce(current_setting('radar.criando_usuario', true), '') = '1' then return new; end if;
  if new.email_confirmed_at is not null then return new; end if;
  raise exception 'cadastro fechado: o acesso ao Radar e criado pelo administrador';
end $$;


--
-- Name: canal_crm(text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.canal_crm(p_plataforma text, p_canal text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  select case coalesce(p_canal, '')
    when 'meta' then p_plataforma = 'meta'
    when 'google' then p_plataforma = 'google'
    when 'pago' then p_plataforma is not null
    when 'organico' then p_plataforma is null
    else true
  end
$$;


--
-- Name: captacao; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.captacao (
    projeto text NOT NULL,
    pagina text NOT NULL,
    video real DEFAULT 1 NOT NULL,
    cliques boolean DEFAULT true NOT NULL,
    leitura boolean DEFAULT true NOT NULL,
    velocidade boolean DEFAULT true NOT NULL,
    erros boolean DEFAULT true NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT captacao_video_check CHECK (((video >= (0)::double precision) AND (video <= (1)::double precision)))
);


--
-- Name: captacao_filtra(jsonb, radar.captacao); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.captacao_filtra(p jsonb, c radar.captacao) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
begin
  if not c.cliques or not c.erros then
    p := jsonb_set(p, '{eventos}', coalesce((
      select jsonb_agg(x.e order by x.n)
      from jsonb_array_elements(case when jsonb_typeof(p -> 'eventos') = 'array' then p -> 'eventos' else '[]'::jsonb end) with ordinality x(e, n)
      where not ((x.e ->> 't' = 'clique' and not c.cliques) or (x.e ->> 't' = 'erro' and not c.erros))), '[]'::jsonb));
  end if;
  if not c.leitura then p := jsonb_set(p, '{pv}', (p -> 'pv') - 'secoes' - 'ctas' - 'form' - 'r30' - 'mapa'); end if;
  if not c.velocidade then p := jsonb_set(p, '{pv}', (p -> 'pv') - 'vitais'); end if;
  return p;
end $$;


--
-- Name: casa(text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.casa(valor text, filtro text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select case when coalesce(filtro, '') = '' then true when filtro = '(nenhum)' then valor is null else valor = filtro end
$$;


--
-- Name: chave_criar(text, text[], text, boolean, integer, uuid, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.chave_criar(p_nome text, p_projetos text[], p_nivel text DEFAULT 'agregado'::text, p_todos boolean DEFAULT false, p_dias integer DEFAULT NULL::integer, p_por uuid DEFAULT NULL::uuid, p_limite integer DEFAULT 60) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_nome text := left(trim(coalesce(p_nome, '')), 60);
  v_lista text[] := coalesce(array(select distinct trim(x) from unnest(coalesce(p_projetos, '{}')) x where trim(x) <> '' order by 1), '{}');
  v_chave text := 'rdr_' || substr(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 1, 48);
  v_falta text;
  v_id bigint;
begin
  if length(v_nome) < 2 then return jsonb_build_object('erro', 'nome_curto'); end if;
  if coalesce(p_nivel, '') not in ('agregado', 'sessoes') then return jsonb_build_object('erro', 'nivel_invalido'); end if;
  if not coalesce(p_todos, false) and cardinality(v_lista) = 0 then return jsonb_build_object('erro', 'sem_funil'); end if;
  select x into v_falta from unnest(v_lista) x where not exists (select 1 from radar.projetos p where p.id = x) limit 1;
  if v_falta is not null then return jsonb_build_object('erro', 'funil_desconhecido', 'funil', v_falta); end if;
  if p_dias is not null and (p_dias < 1 or p_dias > 730) then return jsonb_build_object('erro', 'prazo_invalido'); end if;
  if coalesce(p_limite, 60) < 1 or coalesce(p_limite, 60) > 600 then return jsonb_build_object('erro', 'limite_invalido'); end if;
  insert into radar.chaves (nome, prefixo, hash, projetos, todos, nivel, limite_minuto, criada_por, expira_em)
  values (v_nome, left(v_chave, 10), encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'),
          case when coalesce(p_todos, false) then '{}' else v_lista end, coalesce(p_todos, false), p_nivel, coalesce(p_limite, 60), p_por,
          case when p_dias is not null then now() + make_interval(days => p_dias) end)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'chave', v_chave, 'prefixo', left(v_chave, 10), 'nome', v_nome, 'nivel', p_nivel,
                            'todos', coalesce(p_todos, false), 'projetos', to_jsonb(case when coalesce(p_todos, false) then '{}'::text[] else v_lista end));
end $$;


--
-- Name: clique_automatico(real, integer, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.clique_automatico(x_pct real, y_px integer, seletor text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$
  select coalesce(x_pct = 0 and (y_px = 0 or seletor ~ '(^|> )(input|select|textarea)([^a-z>][^>]*)?$'), false)
$_$;


--
-- Name: contagens(jsonb, integer, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.contagens(j jsonb, maximo integer, limite integer DEFAULT 30) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select case when jsonb_typeof(j) = 'object' then coalesce((
    select jsonb_object_agg(k, v)
    from (select radar.nome_curto(e.key) as k, max(least(greatest(radar.inteiro(e.value #>> '{}', 0), 0), maximo))::int as v
          from jsonb_each(j) e group by 1 order by 1 limit limite) x
    where k <> ''), '{}'::jsonb) end
$$;


--
-- Name: criar_particoes(integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.criar_particoes(dias integer DEFAULT 7) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  d date;
  m date;
  nome text;
  criadas int := 0;
begin
  for d in select generate_series(radar.hoje() - 1, radar.hoje() + dias, interval '1 day')::date loop
    nome := 'gravacoes_' || to_char(d, 'YYYYMMDD');
    if to_regclass('radar.' || nome) is null then
      execute format('create table radar.%I partition of radar.gravacoes for values from (%L) to (%L)', nome, d, d + 1);
      criadas := criadas + 1;
    end if;
  end loop;
  for m in select generate_series(date_trunc('month', radar.hoje() - 31), date_trunc('month', radar.hoje() + 40), interval '1 month')::date loop
    nome := 'cliques_' || to_char(m, 'YYYYMM');
    if to_regclass('radar.' || nome) is null then
      execute format('create table radar.%I partition of radar.cliques for values from (%L) to (%L)', nome, m, (m + interval '1 month')::date);
      criadas := criadas + 1;
    end if;
  end loop;
  return criadas;
end $$;


--
-- Name: criar_usuario(text, text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.criar_usuario(p_email text, p_senha text, p_nome text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'extensions'
    AS $_$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'email_invalido'; end if;
  if length(coalesce(p_senha, '')) < 8 then raise exception 'senha_curta'; end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then raise exception 'email_ja_existe'; end if;
  perform set_config('radar.criando_usuario', '1', true);
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change,
                          email_change_token_current, phone_change, phone_change_token, reauthentication_token,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin, created_at, updated_at,
                          is_sso_user, is_anonymous)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          crypt(p_senha, gen_salt('bf', 10)), now(),
          '', '', '', '', '', '', '', '',
          jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
          jsonb_build_object('nome', left(coalesce(p_nome, ''), 80)), false, now(), now(), false, false);
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_id::text, v_id,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
          'email', null, now(), now());
  perform set_config('radar.criando_usuario', '', true);
  return v_id;
end $_$;


--
-- Name: crm_desde(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.crm_desde(p_projeto text) RETURNS date
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  with d as (
    select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia, count(*) as n
    from radar_crm.pessoas x where x.projeto = p_projeto and not x.teste group by 1),
  ref as (select percentile_cont(0.5) within group (order by n) as m from (select n from d order by dia desc limit 14) u)
  select min(d.dia) from d, ref where d.n >= greatest(1, ref.m * 0.2)
$$;


--
-- Name: data(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.data(t text) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
begin
  if t ~ '^\d{4}-\d{2}-\d{2}$' then return t::date; end if;
  return null;
exception when others then
  return null;
end $_$;


--
-- Name: decimal(text, double precision); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar."decimal"(t text, padrao double precision DEFAULT 0) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case when t ~ '^-?[0-9]{1,12}(\.[0-9]+)?$' then t::double precision else padrao end
$_$;


--
-- Name: diario_config(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.diario_config() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce((select c.valor::jsonb from radar.config c where c.chave = 'diario'), '{"ligado": true, "hora": 7, "maquina": "pc"}'::jsonb)
         || jsonb_build_object('ultimo', (select radar.ms(max(d.gerado_em)) from radar.diarios d))
$$;


--
-- Name: eh_pago(text, boolean, text, text, text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.eh_pago(p_medium text, p_gclid boolean, p_ad_id text, p_campaign_id text, p_utm_campaign text, p_utm_content text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  select coalesce(p_gclid, false)
      or nullif(p_ad_id, '') is not null
      or nullif(p_campaign_id, '') is not null
      -- o codigo do Meta no link do anuncio ({{campaign.id}}, {{ad.id}}): 12 digitos ou mais
      or coalesce(p_utm_campaign, '') ~ '^[0-9]{12,}$'
      or coalesce(p_utm_content, '') ~ '^[0-9]{12,}$'
      or lower(coalesce(p_medium, '')) in ('paid', 'cpc', 'ppc', 'cpm', 'cpv', 'paid_social', 'paidsocial', 'paid-social',
                                           'ads', 'ad', 'pago', 'pagos', 'trafego_pago', 'trafego-pago', 'midia_paga')
$_$;


--
-- Name: encerrada(timestamp with time zone); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.encerrada(recebido timestamp with time zone) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$ select recebido < now() - interval '30 minutes' $$;


--
-- Name: encerrar_teste(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.encerrar_teste(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
begin
  update radar.testes set fim = case when radar.sim(f ->> 'reabrir') then null else greatest(inicio, radar.hoje()) end
   where id = radar.inteiro(f ->> 'id', 0) and projeto = f ->> 'projeto' and tipo = 'ab';   -- 076: so o A/B
  return jsonb_build_object('ok', found, 'erro', case when found then null else 'nao_existe' end);
end $$;


--
-- Name: erro_de_fora(text, text, text[]); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.erro_de_fora(mensagem text, arquivo text, dominios text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  select radar.erro_de_fora_tipo(mensagem, arquivo, dominios) is not null
$$;


--
-- Name: erro_de_fora_nome(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.erro_de_fora_nome(tipo text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  select case tipo
    when 'app_android' then 'Script do app do Facebook (Android)'
    when 'app_iphone' then 'Script do app no iPhone'
    when 'sem_detalhe' then 'Script de outro site sem detalhe'
    when 'extensao' then 'Extensão do navegador'
    when 'aviso' then 'Aviso inofensivo do navegador'
    when 'outro_site' then 'Script de outro site'
    else 'Outro erro de fora da página'
  end
$$;


--
-- Name: erro_de_fora_tipo(text, text, text[]); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.erro_de_fora_tipo(mensagem text, arquivo text, dominios text[]) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$
  select case
    -- app do Facebook (e do Instagram) no Android: o script navigation_performance_logger_android, que o app injeta em
    -- toda pagina aberta por dentro dele, quebra quando o app fecha o navegador ("Error invoking postMessage: Java
    -- object is gone")
    when coalesce(arquivo, '') ~* 'navigation_performance_logger' or mensagem ~* 'java object is gone' then 'app_android'
    -- app no iPhone: a ponte que o app poe na pagina. webkit.messageHandlers (Facebook e Instagram, que injetam o
    -- script no proprio documento: o arquivo vem como o endereco da pagina), _AutofillCallbackHandler (o preenchimento
    -- automatico do app do Facebook), __gCrWeb (Chrome do iPhone), instantSearchSDKJSBridge (app do Bing e do Edge),
    -- __firefox__ (Firefox do iPhone)
    when mensagem ~* 'webkit\.messagehandlers|_autofillcallbackhandler|__gcrweb|instantsearchsdkjsbridge|__firefox__' then 'app_iphone'
    -- extensao do navegador (bloqueador, tradutor, gerenciador de senha): o endereco do script comeca pelo esquema da
    -- extensao, e o Safari esconde o dela como webkit-masked-url. O gravador de hoje manda so o fim do caminho do
    -- arquivo (split('/').pop()), entao a regra pega pelo texto da mensagem e fica pronta para o arquivo inteiro
    when (coalesce(mensagem, '') || ' ' || coalesce(arquivo, '')) ~* '(chrome|moz|safari|safari-web|ms-browser)-extension:|webkit-masked-url:' then 'extensao'
    -- "Script error." sem arquivo: o navegador esconde o detalhe do erro de script de outro dominio (pixel, anuncio,
    -- app). Com arquivo, nao e esse caso e fica como da pagina
    when mensagem ~* '^\s*script error\.?\s*$' and coalesce(arquivo, '') = '' then 'sem_detalhe'
    -- aviso inofensivo do navegador: "ResizeObserver loop limit exceeded" e "... completed with undelivered notifications"
    when mensagem ~* 'resizeobserver loop' then 'aviso'
    -- arquivo com endereco de outro dominio (fora dos dominios do projeto, radar.projetos.dominios, os mesmos do
    -- projetos/<id>.json). Sem a lista de dominios nao da para julgar e o erro fica como da pagina
    when cardinality(dominios) > 0
         and lower(substring(arquivo from '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)')) <> all (dominios) then 'outro_site'
  end
$_$;


--
-- Name: estado_split(jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.estado_split(f jsonb, p_quem text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  t radar.testes;
  v_acao text := coalesce(f ->> 'acao', '');
  v_versao text;
  v_linha jsonb;
begin
  select * into t from radar.testes where id = radar.inteiro(f ->> 'id', 0) and projeto = f ->> 'projeto' and tipo = 'split' for update;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_existe'); end if;
  if v_acao = 'rodar' then
    if t.estado not in ('rascunho', 'pausado') then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
    if (select coalesce(sum((v ->> 'peso')::int), 0) from jsonb_array_elements(t.versoes) v) <> 100 then
      return jsonb_build_object('ok', false, 'erro', 'pesos');
    end if;
    v_linha := radar.split_linha(p_quem, 'rodar', case when t.estado = 'rascunho' then 'Ligou o teste (' else 'Voltou a rodar (' end
                                   || radar.split_divisao(t.versoes) || ')', t.versoes);
    begin
      update radar.testes set estado = 'rodando', promovida = null, fim = null,
             inicio = case when exists (select 1 from jsonb_array_elements(t.historico) h where h ->> 'acao' = 'rodar') then inicio else radar.hoje() end,
             historico = historico || v_linha
       where id = t.id;
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'erro', 'ocupada');
    end;
  elsif v_acao = 'pausar' then
    if t.estado <> 'rodando' then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
    update radar.testes set estado = 'pausado',
           historico = historico || radar.split_linha(p_quem, 'pausar', 'Pausou: todo mundo vai para a versão A', t.versoes)
     where id = t.id;
  elsif v_acao like 'promover:%' then
    v_versao := substr(v_acao, 10);
    if t.estado not in ('rodando', 'pausado') then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
    if not exists (select 1 from jsonb_array_elements(t.versoes) v where v ->> 'id' = v_versao) then
      return jsonb_build_object('ok', false, 'erro', 'versao');
    end if;
    update radar.testes set estado = 'pausado', promovida = v_versao,
           historico = historico || radar.split_linha(p_quem, 'promover', 'Promoveu a versão ' || upper(v_versao) || ': todo mundo vai para ela', t.versoes)
     where id = t.id;
  elsif v_acao = 'encerrar' then
    if t.estado not in ('rodando', 'pausado') then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
    update radar.testes set estado = 'encerrado', fim = greatest(inicio, radar.hoje()),
           historico = historico || radar.split_linha(p_quem, 'encerrar', 'Encerrou o teste'
                          || case when t.promovida is not null then ' (com a versão ' || upper(t.promovida) || ' promovida)' else '' end, t.versoes)
     where id = t.id;
  else
    return jsonb_build_object('ok', false, 'erro', 'acao');
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;


--
-- Name: excluir_gravacao(text, uuid, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.excluir_gravacao(p_sessao text, p_quem uuid, p_motivo text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  s radar.sessoes;
  v_pedacos int := 0;
  v_bytes bigint := 0;
  v_g int := 0;
  v_gb bigint := 0;
  v_guardada boolean;
begin
  select * into s from radar.sessoes where id = p_sessao;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
  -- os pedacos ficam na particao do dia da visita (002)
  with x as (delete from radar.gravacoes g where g.dia = s.dia and g.sessao = s.id returning g.bytes)
  select count(*), coalesce(sum(bytes), 0) into v_pedacos, v_bytes from x;
  v_guardada := exists (select 1 from radar.guardadas k where k.sessao = s.id);
  with x as (delete from radar.gravacoes_guardadas gg where gg.sessao = s.id returning gg.bytes)
  select count(*), coalesce(sum(bytes), 0) into v_g, v_gb from x;
  delete from radar.guardadas k where k.sessao = s.id;
  update radar.sessoes set gravada = false where id = s.id and gravada;
  update radar.visualizacoes set gravada = false where sessao = s.id and gravada;
  insert into radar.gravacoes_excluidas (quem, projeto, sessao, pedacos, bytes, guardada, motivo)
  values (p_quem, s.projeto, s.id, v_pedacos + v_g, v_bytes + v_gb, v_guardada, left(btrim(coalesce(p_motivo, '')), 300));
  return jsonb_build_object('ok', true, 'pedacos', v_pedacos + v_g, 'bytes', v_bytes + v_gb, 'guardada', v_guardada);
end $$;


--
-- Name: fatia(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.fatia(t text) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select ('x' || substr(md5(coalesce(t, '')), 1, 8))::bit(32)::bigint / 4294967296.0
$$;


--
-- Name: sessoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.sessoes (
    id text NOT NULL,
    projeto text NOT NULL,
    visitante text NOT NULL,
    dia date NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fim timestamp with time zone NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    dispositivo text NOT NULL,
    teste boolean DEFAULT false NOT NULL,
    utm_source text,
    utm_medium text,
    utm_campaign text,
    utm_content text,
    utm_term text,
    campaign_id text,
    adset_id text,
    ad_id text,
    fbclid boolean DEFAULT false NOT NULL,
    gclid boolean DEFAULT false NOT NULL,
    referrer text,
    primeira_pagina text NOT NULL,
    ultima_pagina text NOT NULL,
    paginas integer DEFAULT 0 NOT NULL,
    cliques integer DEFAULT 0 NOT NULL,
    raiva integer DEFAULT 0 NOT NULL,
    mortos integer DEFAULT 0 NOT NULL,
    erros integer DEFAULT 0 NOT NULL,
    eventos_funil integer DEFAULT 0 NOT NULL,
    visivel_ms bigint DEFAULT 0 NOT NULL,
    engajada boolean DEFAULT false NOT NULL,
    engajou_em timestamp with time zone,
    engajou_por text,
    lead boolean DEFAULT false NOT NULL,
    lead_em timestamp with time zone,
    resultado text,
    resultado_em timestamp with time zone,
    gravada boolean DEFAULT false NOT NULL,
    sistema text,
    sistema_versao text,
    navegador text,
    navegador_versao text,
    app text,
    modelo text,
    tela text,
    idioma text,
    fuso text,
    toque boolean,
    pais text,
    estado text,
    cidade text,
    interna boolean DEFAULT false NOT NULL,
    CONSTRAINT sessoes_dispositivo_check CHECK ((dispositivo = ANY (ARRAY['mobile'::text, 'tablet'::text, 'desktop'::text]))),
    CONSTRAINT sessoes_engajou_por_check CHECK ((engajou_por = ANY (ARRAY['tempo'::text, 'clique'::text, 'evento'::text, 'paginas'::text])))
);


--
-- Name: filtradas(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.filtradas(f jsonb) RETURNS SETOF radar.sessoes
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select s.*
  from radar.sessoes s
  where s.projeto = f ->> 'projeto'
    and s.dia >= coalesce(radar.data(f ->> 'de'), radar.hoje() - 6)
    and s.dia <= coalesce(radar.data(f ->> 'ate'), radar.hoje() + 1)
    and (coalesce(f ->> 'teste', '') = '1' or not s.teste)
    -- so visitas que apareceram na tela (021): a carga escondida (o app abriu a pagina por tras e ninguem viu) fica fora
    -- de toda conta; escondidas = '1' traz as duas, para o diagnostico
    and (coalesce(f ->> 'escondidas', '') = '1' or coalesce(s.visivel_ms, 0) > 0)
    and (coalesce(f ->> 'dispositivo', '') = '' or s.dispositivo = f ->> 'dispositivo')
    -- onde abriu: app = dentro de qualquer app (Instagram, Facebook...), navegador = fora de app, ou um app
    and (coalesce(f ->> 'app', '') = '' or (f ->> 'app' = 'app' and s.app is not null)
         or (f ->> 'app' = 'navegador' and s.app is null) or s.app = f ->> 'app')
    -- trafego (026 e 027): pago = veio de anuncio; organico = sem anuncio; meta e google = anuncio daquela plataforma
    and case coalesce(f ->> 'canal', '')
          when 'pago' then radar.eh_pago(s.utm_medium, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content)
          when 'organico' then not radar.eh_pago(s.utm_medium, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content)
          when 'meta' then radar.plataforma(s.utm_source, s.utm_medium, s.fbclid, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content) = 'meta'
          when 'google' then radar.plataforma(s.utm_source, s.utm_medium, s.fbclid, s.gclid, s.ad_id, s.campaign_id, s.utm_campaign, s.utm_content) = 'google'
          else true
        end
    and radar.casa(s.sistema, f ->> 'sistema')
    and radar.casa(s.estado, f ->> 'estado')
    and case coalesce(f ->> 'visitante', '')
          when 'novo' then not exists (select 1 from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante and x.inicio < s.inicio and coalesce(x.visivel_ms, 0) > 0)
          when 'recorrente' then exists (select 1 from radar.sessoes x where x.projeto = s.projeto and x.visitante = s.visitante and x.inicio < s.inicio and coalesce(x.visivel_ms, 0) > 0)
          else true
        end
    and radar.casa(s.utm_source, f ->> 'utm_source')
    and radar.casa(s.utm_campaign, f ->> 'utm_campaign')
    and radar.casa(s.utm_content, f ->> 'utm_content')
    and radar.casa(s.resultado, f ->> 'resultado')
    and (coalesce(f ->> 'pagina', '') = ''
         or exists (select 1 from radar.visualizacoes v where v.sessao = s.id and v.pagina = f ->> 'pagina'))
    -- 053: entrada = '1' so traz a visita que comecou numa pagina de entrada. Quem chega na pesquisa ou num obrigado vindo
    -- de uma pagina sem o gravador (a BL2 leva a /quase-la/ com o anuncio na URL) continua uma visita que o Radar nao viu
    -- comecar: nao e visita de anuncio na conta da taxa de lead. Sem o "entrada", nada muda (a pagina conta a visita)
    and (coalesce(f ->> 'entrada', '') <> '1'
         or coalesce(s.primeira_pagina, '') <> all (array(
              select x ->> 'id' from radar.projetos p, jsonb_array_elements(coalesce(p.config -> 'paginas', '[]'::jsonb)) x
              where p.id = f ->> 'projeto' and x ->> 'tipo' in ('pesquisa', 'obrigado') and x ->> 'id' is not null)))
    and case coalesce(f ->> 'com', '')
          when 'raiva' then s.raiva > 0
          when 'erro' then s.erros > 0
          when 'morto' then s.mortos > 0
          -- 030: a guardada com video tambem tem video (a copia nao vence)
          when 'gravada' then (s.gravada and s.inicio > now() - radar.retencao_video(s.projeto))
                              or exists (select 1 from radar.guardadas k where k.sessao = s.id and k.com_video)
          when 'lead' then s.lead
          -- 029: quase lead = abriu o formulario e nao virou lead (a fila "Vale assistir" das Gravacoes)
          when 'quase' then not s.lead and exists (
            select 1 from radar.eventos_funil e
            where e.sessao = s.id and e.nome in ('abriu_formulario', 'abriu_form', 'form_aberto', 'formulario_aberto'))
          else true
        end
    -- 030: parou na etapa k de um funil (a conta e feita uma vez, so com o filtro ligado)
    and (coalesce(f ->> 'parou', '') = '' or s.id in (select radar.parados(f)))
$$;


--
-- Name: form_limpo(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.form_limpo(j jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select case when jsonb_typeof(j) = 'object' then jsonb_build_object(
    'v', least(greatest(radar.inteiro(j ->> 'v', 0), 0), 1),
    't', least(greatest(radar.inteiro(j ->> 't', 0), 0), 86400),
    's', least(greatest(radar.inteiro(j ->> 's', 0), 0), 100),
    'u', radar.nome_curto(j ->> 'u'),
    'c', coalesce((
       select jsonb_object_agg(k, v)
       from (select radar.nome_curto(e.key) as k,
                    jsonb_build_array(least(greatest(radar.inteiro(e.value ->> 0, 0), 0), 1000), least(greatest(radar.inteiro(e.value ->> 1, 0), 0), 86400),
                                      least(greatest(radar.inteiro(e.value ->> 2, 0), 0), 1), least(greatest(radar.inteiro(e.value ->> 3, 0), 0), 1000)) as v
             from jsonb_each(case when jsonb_typeof(j -> 'c') = 'object' then j -> 'c' else '{}'::jsonb end) e
             where jsonb_typeof(e.value) = 'array' limit 30) x
       where k <> ''), '{}'::jsonb)) end
$$;


--
-- Name: guardar_gravacao(jsonb, uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.guardar_gravacao(f jsonb, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  s radar.sessoes;
  v_teto constant int := 200;
  v_nota text := left(regexp_replace(trim(coalesce(f ->> 'nota', '')), '\s+', ' ', 'g'), 500);
  v_pedacos int := 0;
begin
  select * into s from radar.sessoes where id = f ->> 'sessao';
  if s.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao_nao_encontrada'); end if;
  if exists (select 1 from radar.guardadas where sessao = s.id) then
    if f ? 'nota' then update radar.guardadas set nota = v_nota, atualizada_em = now() where sessao = s.id; end if;
  else
    -- dois cliques ao mesmo tempo nao passam do teto
    perform pg_advisory_xact_lock(hashtext('radar.guardadas'));
    if (select count(*) from radar.guardadas) >= v_teto then
      return jsonb_build_object('ok', false, 'erro', 'teto', 'teto', v_teto);
    end if;
    insert into radar.guardadas (sessao, projeto, nota, guardada_por) values (s.id, s.projeto, v_nota, p_usuario);
    insert into radar.gravacoes_guardadas (sessao, visualizacao, seq, formato, bytes, dados)
    select g.sessao, g.visualizacao, g.seq, g.formato, g.bytes, g.dados
    from radar.gravacoes g where g.dia = s.dia and g.sessao = s.id
    on conflict do nothing;
    get diagnostics v_pedacos = row_count;
    if v_pedacos > 0 then update radar.guardadas set com_video = true where sessao = s.id; end if;
  end if;
  return (select jsonb_build_object('ok', true, 'guardada', 1, 'nota', k.nota, 'com_video', k.com_video::int,
                                    'guardadas', (select count(*) from radar.guardadas), 'teto', v_teto)
          from radar.guardadas k where k.sessao = s.id);
end $$;


--
-- Name: guardar_info(jsonb, jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.guardar_info(p jsonb, cab jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  i jsonb := case when jsonb_typeof(p -> 'sessao' -> 'info') = 'object' then p -> 'sessao' -> 'info' end;
  v_pais text := upper(coalesce(cab ->> 'cf-ipcountry', ''));
begin
  if i is null then return; end if;
  if v_pais !~ '^[A-Z]{2}$' or v_pais in ('XX', 'T1') then v_pais := null; end if;
  update radar.sessoes set
    sistema = coalesce(radar.texto(i ->> 'sis', 20), sistema),
    sistema_versao = coalesce(radar.texto(i ->> 'sisv', 16), sistema_versao),
    navegador = coalesce(radar.texto(i ->> 'nav', 24), navegador),
    navegador_versao = coalesce(radar.texto(i ->> 'navv', 16), navegador_versao),
    app = coalesce(case when i ->> 'app' ~ '^[a-z]{2,20}$' then i ->> 'app' end, app),
    modelo = coalesce(radar.texto(i ->> 'modelo', 40), modelo),
    tela = coalesce(case when i ->> 'tela' ~ '^[0-9]{2,5}x[0-9]{2,5}$' then i ->> 'tela' end, tela),
    idioma = coalesce(radar.texto(i ->> 'idioma', 16), idioma),
    fuso = coalesce(radar.texto(i ->> 'fuso', 40), fuso),
    toque = coalesce(case when i ? 'toque' then radar.sim(i ->> 'toque') end, toque),
    pais = coalesce(pais, v_pais, case when upper(i ->> 'pais') ~ '^[A-Z]{2}$' then upper(i ->> 'pais') end),
    estado = coalesce(radar.texto(i ->> 'estado', 40), estado),
    cidade = coalesce(radar.texto(i ->> 'cidade', 60), cidade)
  where id = p -> 'sessao' ->> 'id';
end $_$;


--
-- Name: guardar_mapa(text, text, jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.guardar_mapa(p_projeto text, p_pagina text, m jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_s text[] := radar.nomes(m -> 's', 30);
  v_c text[] := radar.nomes(m -> 'c', 20);
  v_f text[] := radar.nomes(m -> 'f', 30);
begin
  if cardinality(v_s) + cardinality(v_c) + cardinality(v_f) = 0 then return; end if;
  insert into radar.paginas_mapa as pm (projeto, pagina, secoes, ctas, campos) values (p_projeto, p_pagina, v_s, v_c, v_f)
  on conflict (projeto, pagina) do update set
    secoes = radar.juntar_nomes(pm.secoes, excluded.secoes), ctas = radar.juntar_nomes(pm.ctas, excluded.ctas),
    campos = radar.juntar_nomes(pm.campos, excluded.campos), atualizado_em = now()
  where radar.juntar_nomes(pm.secoes, excluded.secoes) is distinct from pm.secoes
     or radar.juntar_nomes(pm.ctas, excluded.ctas) is distinct from pm.ctas
     or radar.juntar_nomes(pm.campos, excluded.campos) is distinct from pm.campos;
end $$;


--
-- Name: guardar_vitais(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.guardar_vitais(p jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  vt jsonb := case when jsonb_typeof(p -> 'pv' -> 'vitais') = 'object' then p -> 'pv' -> 'vitais' else '{}'::jsonb end;
  ms_ate constant bigint := 300000;
  lim_lcp int; lim_inp int; lim_fcp int; lim_ttfb int; lim_carga int; lim_peso int; v_cls real; v_vaivem int; v_ativo int; v_r30 int;
  v_secoes jsonb := radar.contagens(p -> 'pv' -> 'secoes', 32767);
  v_ctas jsonb := radar.contagens(p -> 'pv' -> 'ctas', 1, 20);
  v_form jsonb := radar.form_limpo(p -> 'pv' -> 'form');
  v_mapa jsonb := case when jsonb_typeof(p -> 'pv' -> 'mapa') = 'object' then p -> 'pv' -> 'mapa' end;
  v_projeto text;
  v_pagina text;
begin
  lim_lcp := nullif(least(greatest(radar.inteiro(vt ->> 'lcp', -1), -1), ms_ate), -1);
  lim_inp := nullif(least(greatest(radar.inteiro(vt ->> 'inp', -1), -1), 60000), -1);
  lim_fcp := nullif(least(greatest(radar.inteiro(vt ->> 'fcp', -1), -1), ms_ate), -1);
  lim_ttfb := nullif(least(greatest(radar.inteiro(vt ->> 'ttfb', -1), -1), 120000), -1);
  lim_carga := nullif(least(greatest(radar.inteiro(vt ->> 'carga', -1), -1), ms_ate), -1);
  lim_peso := nullif(least(greatest(radar.inteiro(vt ->> 'peso', -1), -1), 1000000), -1);
  v_cls := case when vt ? 'cls' then least(greatest(radar.decimal(vt ->> 'cls', 0), 0), 10)::real end;
  v_vaivem := nullif(least(greatest(radar.inteiro(p -> 'pv' ->> 'vaivem', -1), -1), 1000), -1);
  v_ativo := nullif(least(greatest(radar.inteiro(p -> 'pv' ->> 'ativo_ms', -1), -1), 86400000), -1);
  v_r30 := nullif(least(greatest(radar.inteiro(p -> 'pv' ->> 'r30', -1), -1), 100), -1);
  if lim_lcp is null and lim_inp is null and lim_fcp is null and lim_ttfb is null and lim_carga is null and lim_peso is null
     and v_cls is null and v_vaivem is null and v_ativo is null and not (vt ? 'rede')
     and v_r30 is null and v_secoes is null and v_ctas is null and v_form is null and v_mapa is null then
    return;
  end if;
  update radar.visualizacoes set
    lcp_ms = greatest(lcp_ms, lim_lcp),
    inp_ms = greatest(inp_ms, lim_inp),
    cls = greatest(cls, v_cls),
    fcp_ms = coalesce(fcp_ms, lim_fcp),
    ttfb_ms = coalesce(ttfb_ms, lim_ttfb),
    carga_ms = coalesce(carga_ms, lim_carga),
    peso_kb = greatest(peso_kb, lim_peso),
    rede = coalesce(rede, case when vt ->> 'rede' in ('slow-2g', '2g', '3g', '4g') then vt ->> 'rede' end),
    vaivem = greatest(vaivem, v_vaivem::smallint),
    ativo_ms = greatest(ativo_ms, v_ativo),
    rolagem_30s = greatest(rolagem_30s, v_r30::smallint),
    secoes = case when v_secoes is not null and radar.peso(v_secoes) >= radar.peso(secoes) then v_secoes else secoes end,
    ctas = case when v_ctas is not null and radar.peso(v_ctas) >= radar.peso(ctas) then v_ctas else ctas end,
    form = case when v_form is not null and radar.peso(v_form) >= radar.peso(form) then v_form else form end
  where id = p -> 'pv' ->> 'id'
  returning projeto, pagina into v_projeto, v_pagina;
  if v_mapa is not null and v_projeto is not null then
    perform radar.guardar_mapa(v_projeto, v_pagina, v_mapa);
  end if;
end $$;


--
-- Name: hoje(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.hoje() RETURNS date
    LANGUAGE sql STABLE
    AS $$ select (now() at time zone 'America/Sao_Paulo')::date $$;


--
-- Name: id_lab(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.id_lab(v text) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  select case when v ~ '^[0-9]{1,18}$' then v::bigint end
$_$;


--
-- Name: ingerir(jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ingerir(p jsonb, origem text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  cfg radar.projetos;
  s jsonb := coalesce(p -> 'sessao', '{}'::jsonb);
  v jsonb := coalesce(p -> 'pv', '{}'::jsonb);
  -- 071: a origem no padrao da casa (as UTMs nome|id viram os ids, radar.utm_canonica); a do PB passa igual
  o jsonb := radar.utm_canonica(coalesce(p -> 'sessao' -> 'origem', '{}'::jsonb));
  eventos jsonb := case when jsonb_typeof(p -> 'eventos') = 'array' then p -> 'eventos' else '[]'::jsonb end;
  v_sid text := coalesce(s ->> 'id', '');
  v_pvid text := coalesce(v ->> 'id', '');
  v_vis text := coalesce(s ->> 'visitante', '');
  v_seq int := least(radar.inteiro(p ->> 'seq', 0), 1000000)::int;
  v_agora timestamptz := now();
  v_host text;
  v_ini timestamptz;
  v_fim timestamptz;
  v_maior_ts bigint := 0;
  v_ts timestamptz;
  v_pag text;
  v_nova boolean;
  v_sess radar.sessoes;
  v_permitidas text[];
  v_lead_evs text[];
  e jsonb;
  r jsonb;
  v_dados jsonb;
  v_resultado text;
  v_lead boolean := false;
  n_cl int := 0; n_rv int := 0; n_mt int := 0; n_er int := 0; n_fu int := 0;
  v_bin bytea;
  v_formato text;
  v_gravou boolean := false;
  v_por text;
  v_x real;
  v_y int;
  v_sel text;
  v_auto boolean;
  v_msg text;
  v_arq text;
  v_fora boolean;
begin
  select * into cfg from radar.projetos where id = p ->> 'projeto';
  if not found then return radar.recusa('projeto', left(p ->> 'projeto', 40)); end if;

  -- o navegador manda o Origin: so vale o que vem dos dominios do projeto
  v_host := lower(substring(coalesce(origem, '') from '^[a-zA-Z]+://([^/:?#]+)'));
  if v_host is null or not (v_host = any (cfg.dominios)) then return radar.recusa('dominio', coalesce(v_host, '(sem origem)')); end if;
  if v_sid !~ '^[A-Za-z0-9]{8,40}$' or v_pvid !~ '^[A-Za-z0-9]{8,40}$' or v_vis !~ '^[A-Za-z0-9]{8,40}$' then
    return radar.recusa('identificador');
  end if;

  -- o mesmo pacote reenviado nao conta duas vezes
  insert into radar.pacotes (visualizacao, seq, dia) values (v_pvid, v_seq, radar.hoje()) on conflict do nothing;
  if not found then return 'repetido'; end if;

  -- relogio: o do navegador ordena a visita; se estiver mais de 1 dia errado, vale o do servidor
  v_ini := to_timestamp(radar.inteiro(v ->> 'inicio', 0) / 1000.0);
  if abs(extract(epoch from v_ini - v_agora)) > 86400 then v_ini := v_agora; end if;
  select coalesce(max(least(greatest(radar.inteiro(x ->> 'ts', 0), 0), 86400000)), 0) into v_maior_ts from jsonb_array_elements(eventos) x;
  v_fim := v_ini + make_interval(secs => greatest(v_maior_ts, least(greatest(radar.inteiro(v ->> 'visivel_ms', 0), 0), 86400000)) / 1000.0);
  v_pag := radar.pagina_id(cfg.config, left(v ->> 'caminho', 200));

  -- sessao (a primeira pagina e a origem valem para a visita toda)
  insert into radar.sessoes (id, projeto, visitante, dia, inicio, fim, recebido_em, dispositivo, teste,
                             utm_source, utm_medium, utm_campaign, utm_content, utm_term, campaign_id, adset_id, ad_id,
                             fbclid, gclid, referrer, primeira_pagina, ultima_pagina)
  values (v_sid, cfg.id, v_vis, (v_ini at time zone 'America/Sao_Paulo')::date, v_ini, v_fim, v_agora,
          case when s ->> 'dispositivo' in ('mobile', 'tablet', 'desktop') then s ->> 'dispositivo' else 'desktop' end,
          radar.sim(s ->> 'teste'),
          left(nullif(o ->> 'utm_source', ''), 120), left(nullif(o ->> 'utm_medium', ''), 120), left(nullif(o ->> 'utm_campaign', ''), 120),
          left(nullif(o ->> 'utm_content', ''), 120), left(nullif(o ->> 'utm_term', ''), 120),
          left(nullif(o ->> 'campaign_id', ''), 60), left(nullif(o ->> 'adset_id', ''), 60), left(nullif(o ->> 'ad_id', ''), 60),
          radar.sim(o ->> 'fbclid'), radar.sim(o ->> 'gclid'), left(nullif(o ->> 'referrer', ''), 120), v_pag, v_pag)
  on conflict (id) do nothing;
  v_nova := found;
  select * into v_sess from radar.sessoes where id = v_sid for update;
  if v_sess.projeto <> cfg.id then return radar.recusa('sessao de outro projeto'); end if;

  insert into radar.visitantes (projeto, id, primeira_vez, ultima_vez, sessoes) values (cfg.id, v_vis, v_agora, v_agora, 1)
  on conflict (projeto, id) do update
    set ultima_vez = excluded.ultima_vez, sessoes = radar.visitantes.sessoes + case when v_nova then 1 else 0 end;

  -- pagina vista: nova ou atualizada (fim, rolagem e tempo so crescem)
  insert into radar.visualizacoes (id, sessao, projeto, dia, pagina, caminho, titulo, ordem, inicio, fim,
                                   largura, altura, altura_doc, rolagem, visivel_ms)
  values (v_pvid, v_sid, cfg.id, v_sess.dia, v_pag, left(coalesce(v ->> 'caminho', '/'), 200), left(v ->> 'titulo', 120),
          (select coalesce(max(ordem), 0) + 1 from radar.visualizacoes where sessao = v_sid),
          v_ini, v_fim,
          least(greatest(radar.inteiro(v ->> 'largura', 0), 0), 20000), least(greatest(radar.inteiro(v ->> 'altura', 0), 0), 20000),
          least(greatest(radar.inteiro(v ->> 'altura_doc', 0), 0), 500000),
          least(greatest(radar.inteiro(v ->> 'rolagem', 0), 0), 100), least(greatest(radar.inteiro(v ->> 'visivel_ms', 0), 0), 86400000))
  on conflict (id) do update set
    fim = greatest(radar.visualizacoes.fim, excluded.fim),
    rolagem = greatest(radar.visualizacoes.rolagem, excluded.rolagem),
    visivel_ms = greatest(radar.visualizacoes.visivel_ms, excluded.visivel_ms),
    altura_doc = greatest(coalesce(radar.visualizacoes.altura_doc, 0), coalesce(excluded.altura_doc, 0))
  where radar.visualizacoes.sessao = excluded.sessao;

  -- eventos: cliques, funil (so as chaves permitidas no projeto), erros
  v_permitidas := array(select jsonb_array_elements_text(coalesce(cfg.config -> 'chaves_datalayer_permitidas', '[]'::jsonb)));
  v_lead_evs := array(select jsonb_array_elements_text(coalesce(cfg.config -> 'eventos_lead', '[]'::jsonb)));
  for e in select value from jsonb_array_elements(eventos) limit 500 loop
    v_ts := v_ini + make_interval(secs => least(greatest(radar.inteiro(e ->> 'ts', 0), 0), 86400000) / 1000.0);
    if e ->> 't' = 'clique' then
      -- clique automatico (025): o navegador ou o app clicou por codigo, nao a pessoa. Fica guardado com a marca e fora
      -- dos contadores da visita (cliques, raiva e mortos contam so clique de gente; o engajamento por clique tambem)
      v_x := least(greatest(radar.decimal(e ->> 'x', 0), 0), 100);
      v_y := least(greatest(radar.inteiro(e ->> 'y', 0), 0), 500000)::int;
      v_sel := left(coalesce(e ->> 'sel', ''), 200);
      v_auto := radar.clique_automatico(v_x, v_y, v_sel);
      insert into radar.cliques (sessao, visualizacao, projeto, dia, pagina, dispositivo, quando, x_pct, y_px, seletor, texto, raiva, morto, fixo, automatico)
      values (v_sid, v_pvid, cfg.id, v_sess.dia, v_pag, v_sess.dispositivo, v_ts, v_x, v_y, v_sel, left(coalesce(e ->> 'txt', ''), 40),
              radar.sim(e ->> 'raiva'), radar.sim(e ->> 'morto'), radar.sim(e ->> 'fixo'), v_auto);
      if not v_auto then
        n_cl := n_cl + 1;
        if radar.sim(e ->> 'raiva') then n_rv := n_rv + 1; end if;
        if radar.sim(e ->> 'morto') then n_mt := n_mt + 1; end if;
      end if;
    elsif e ->> 't' = 'funil' and coalesce(e ->> 'nome', '') <> '' then
      select coalesce(jsonb_object_agg(k, left(e ->> k, 60)), '{}'::jsonb) into v_dados from unnest(v_permitidas) k where e ? k;
      insert into radar.eventos_funil (sessao, visualizacao, projeto, dia, pagina, quando, nome, dados)
      values (v_sid, v_pvid, cfg.id, v_sess.dia, v_pag, v_ts, left(e ->> 'nome', 60), v_dados);
      n_fu := n_fu + 1;
      if (e ->> 'nome') = any (v_lead_evs) then v_lead := true; end if;
      -- resultado da pesquisa (mql, nao_mql...): o evento e, quando o projeto pede, o motivo
      for r in select value from jsonb_array_elements(coalesce(cfg.config -> 'resultados', '[]'::jsonb)) loop
        if (e ->> 'nome') in (select jsonb_array_elements_text(coalesce(r -> 'evento', '[]'::jsonb)))
           and (r ->> 'motivo' is null or r ->> 'motivo' = v_dados ->> 'motivo') then
          v_resultado := r ->> 'id';
          exit;
        end if;
      end loop;
    elsif e ->> 't' = 'erro' then
      -- erro de fora da pagina (025: app, outro site, extensao, aviso do navegador): fica guardado com a origem e fora do
      -- contador da visita. O arquivo vai sem a query string e sem o # (o fbclid nao fica guardado)
      v_msg := left(coalesce(e ->> 'msg', ''), 160);
      v_arq := radar.arquivo_limpo(e ->> 'arq');
      v_fora := radar.erro_de_fora(v_msg, v_arq, cfg.dominios);
      insert into radar.erros (sessao, visualizacao, projeto, dia, pagina, quando, mensagem, arquivo, linha, origem)
      values (v_sid, v_pvid, cfg.id, v_sess.dia, v_pag, v_ts, v_msg, v_arq,
              least(greatest(radar.inteiro(e ->> 'linha', 0), 0), 10000000)::int, case when v_fora then 'fora' else 'pagina' end);
      if not v_fora then n_er := n_er + 1; end if;
    end if;
  end loop;

  -- pedaco da gravacao: gzip do navegador (base64) ou texto puro; acima de 4 MB nao entra
  if coalesce(p ->> 'gravacao_gz', '') <> '' then
    begin
      v_bin := decode(p ->> 'gravacao_gz', 'base64');
      v_formato := 'gzip';
    exception when others then
      v_bin := null;
    end;
  elsif jsonb_typeof(p -> 'gravacao') = 'array' and jsonb_array_length(p -> 'gravacao') > 0 then
    v_bin := convert_to((p -> 'gravacao')::text, 'UTF8');
    v_formato := 'json';
  end if;
  if v_bin is not null and octet_length(v_bin) between 1 and 4194304 then
    begin
      insert into radar.gravacoes (sessao, visualizacao, seq, projeto, dia, formato, bytes, dados)
      values (v_sid, v_pvid, v_seq, cfg.id, v_sess.dia, v_formato, octet_length(v_bin), v_bin);
      v_gravou := true;
    exception when others then
      -- sem particao para o dia (visita muito antiga) ou pedaco repetido: perde so esse pedaco do video
      v_gravou := false;
    end;
  end if;
  if v_gravou then update radar.visualizacoes set gravada = true where id = v_pvid and not gravada; end if;

  -- sessao: contadores, lead, resultado e engajamento
  update radar.sessoes set
    fim = greatest(fim, v_fim),
    recebido_em = v_agora,
    paginas = (select count(*) from radar.visualizacoes where sessao = v_sid),
    ultima_pagina = (select pagina from radar.visualizacoes where sessao = v_sid order by ordem desc limit 1),
    visivel_ms = (select coalesce(sum(visivel_ms), 0) from radar.visualizacoes where sessao = v_sid),
    cliques = cliques + n_cl, raiva = raiva + n_rv, mortos = mortos + n_mt, erros = erros + n_er, eventos_funil = eventos_funil + n_fu,
    lead = lead or v_lead,
    lead_em = case when v_lead and lead_em is null then v_agora else lead_em end,
    resultado = coalesce(v_resultado, resultado),
    resultado_em = case when v_resultado is not null then v_agora else resultado_em end,
    gravada = gravada or v_gravou
  where id = v_sid
  returning * into v_sess;

  if not v_sess.engajada then
    v_por := case
      -- "abriu outra pagina": paginas DIFERENTES. A mesma pagina carregada duas vezes (o navegador do Facebook faz isso
      -- sozinho) nao e engajar
      when (select count(distinct pagina) from radar.visualizacoes where sessao = v_sid) >= 2 then 'paginas'
      when v_sess.eventos_funil > 0 then 'evento'
      when v_sess.cliques > 0 then 'clique'
      when v_sess.visivel_ms >= cfg.engajamento_segundos * 1000 then 'tempo'
    end;
    if v_por is not null then
      update radar.sessoes set engajada = true, engajou_em = v_agora, engajou_por = v_por where id = v_sid;
    end if;
  end if;
  return 'ok';
end $_$;


--
-- Name: inteiro(text, bigint); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.inteiro(t text, padrao bigint DEFAULT 0) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case when t ~ '^-?[0-9]{1,15}$' then t::bigint else padrao end
$_$;


--
-- Name: ip_da_chamada(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ip_da_chamada(cab jsonb) RETURNS inet
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
  select case when t <> '' and position('/' in t) = 0 and pg_input_is_valid(t, 'inet') then t::inet end
  from (select left(trim(coalesce(nullif(trim(cab ->> 'cf-connecting-ip'), ''),
                                  split_part(coalesce(cab ->> 'x-forwarded-for', ''), ',', 1))), 64) as t) x
$$;


--
-- Name: json_ou_nulo(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.json_ou_nulo(t text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
  if t is null or btrim(t) !~ '^[\[{]' then return null; end if;
  return t::jsonb;
exception when others then
  return null;
end $$;


--
-- Name: juntar_nomes(text[], text[]); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.juntar_nomes(antigo text[], novo text[]) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case when coalesce(cardinality(novo), 0) = 0 then coalesce(antigo, '{}')
              when coalesce(antigo, '{}') <@ novo then novo
              else antigo || array(select n from unnest(novo) with ordinality x(n, o) where not (n = any (antigo)) order by o) end
$$;


--
-- Name: limpar_gravacoes(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.limpar_gravacoes() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  t record;
  apagados bigint := 0;
  n bigint;
  vazia boolean;
  particoes int := 0;
  p record;
  copiados bigint := 0;
  limite_dia date := radar.hoje() - (select coalesce(max(retencao_gravacao_dias), 5) from radar.projetos) - 1;
begin
  insert into radar.gravacoes_guardadas (sessao, visualizacao, seq, formato, bytes, dados)
  select g.sessao, g.visualizacao, g.seq, g.formato, g.bytes, g.dados
  from radar.guardadas k
  join radar.sessoes s on s.id = k.sessao
  join radar.gravacoes g on g.dia = s.dia and g.sessao = k.sessao
  where not exists (select 1 from radar.gravacoes_guardadas gg
                    where gg.sessao = g.sessao and gg.visualizacao = g.visualizacao and gg.seq = g.seq)
  on conflict do nothing;
  get diagnostics copiados = row_count;
  if copiados > 0 then
    update radar.guardadas k set com_video = true
    where not k.com_video and exists (select 1 from radar.gravacoes_guardadas gg where gg.sessao = k.sessao);
  end if;
  for p in select id, retencao_gravacao_dias from radar.projetos loop
    delete from radar.gravacoes
     where projeto = p.id
       and dia <= radar.hoje() - p.retencao_gravacao_dias + 1
       and recebido_em < now() - make_interval(days => p.retencao_gravacao_dias);
    get diagnostics n = row_count;
    apagados := apagados + n;
  end loop;
  for t in
    select c.relname as nome
    from pg_inherits i
    join pg_class c on c.oid = i.inhrelid
    join pg_class pai on pai.oid = i.inhparent
    join pg_namespace ns on ns.oid = pai.relnamespace
    where ns.nspname = 'radar' and pai.relname = 'gravacoes' and c.relname ~ '^gravacoes_[0-9]{8}$'
  loop
    if to_date(right(t.nome, 8), 'YYYYMMDD') <= limite_dia then
      execute format('select not exists (select 1 from radar.%I)', t.nome) into vazia;
      if vazia then
        execute format('drop table radar.%I', t.nome);
        particoes := particoes + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('pedacos_apagados', apagados, 'particoes_apagadas', particoes, 'pedacos_guardados', copiados);
end $_$;


--
-- Name: manter(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.manter() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  t record;
  limite_cliq date := radar.hoje() - (select coalesce(max(retencao_cliques_dias), 90) from radar.projetos);
  criadas int;
  cliques_apagados int := 0;
  sessoes_apagadas int := 0;
  leituras_soltas int := 0;
  video jsonb;
begin
  criadas := radar.criar_particoes(7);
  video := radar.limpar_gravacoes();
  for t in
    select c.relname as nome
    from pg_inherits i
    join pg_class c on c.oid = i.inhrelid
    join pg_class pai on pai.oid = i.inhparent
    join pg_namespace n on n.oid = pai.relnamespace
    where n.nspname = 'radar' and pai.relname = 'cliques' and c.relname ~ '^cliques_[0-9]{6}$'
  loop
    if (to_date(right(t.nome, 6), 'YYYYMM') + interval '1 month')::date <= limite_cliq then
      execute format('drop table radar.%I', t.nome);
      cliques_apagados := cliques_apagados + 1;
    end if;
  end loop;
  update radar.visualizacoes v set secoes = null, ctas = null, form = null
    from radar.projetos p
   where v.projeto = p.id and v.dia < radar.hoje() - p.retencao_cliques_dias
     and (v.secoes is not null or v.ctas is not null or v.form is not null);
  get diagnostics leituras_soltas = row_count;
  delete from radar.sessoes s using radar.projetos p
   where s.projeto = p.id and s.dia < (radar.hoje() - make_interval(months => p.retencao_sessoes_meses))::date;
  get diagnostics sessoes_apagadas = row_count;
  delete from radar.visitantes v using radar.projetos p
   where v.projeto = p.id and v.ultima_vez < now() - make_interval(months => p.retencao_sessoes_meses);
  delete from radar.pacotes where dia < radar.hoje() - 2;
  delete from radar.recusas where dia < radar.hoje() - 30;
  delete from radar.falhas where quando < now() - interval '14 days';
  return jsonb_build_object('particoes_criadas', criadas, 'video', video, 'meses_de_cliques_apagados', cliques_apagados,
                            'sessoes_apagadas', sessoes_apagadas, 'leituras_soltas', leituras_soltas);
end $_$;


--
-- Name: marcar_achado(jsonb, uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.marcar_achado(f jsonb, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  v_estado text := case when f ->> 'estado' in ('aberto', 'feito', 'dispensado', 'teste') then f ->> 'estado' end;
  v_chave text := left(coalesce(f ->> 'chave', ''), 300);
  v_proj text := f ->> 'projeto';
begin
  if v_estado is null then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
  if v_chave not like v_proj || '|%' then return jsonb_build_object('ok', false, 'erro', 'chave'); end if;
  insert into radar.achados (projeto, chave, tipo, aprendizado, pagina, titulo, fazer, numeros, confianca, ganho, primeiro_dia, ultimo_dia)
  values (v_proj, v_chave, left(coalesce(f ->> 'tipo', ''), 40), radar.sim(f ->> 'aprendizado'), left(coalesce(f ->> 'pagina', ''), 80),
          left(coalesce(f ->> 'titulo', ''), 400), left(coalesce(f ->> 'fazer', ''), 600), left(coalesce(f ->> 'numeros', ''), 900),
          left(coalesce(f ->> 'confianca', ''), 20),
          case when coalesce(f ->> 'ganho', '') ~ '^[0-9]+(\.[0-9]+)?$' then (f ->> 'ganho')::numeric else 0 end, radar.hoje(), radar.hoje())
  on conflict (projeto, chave) do nothing;
  update radar.achados set
    estado = v_estado,
    estado_em = case when v_estado = 'aberto' then null else now() end,
    estado_por = case when v_estado = 'aberto' then null else p_usuario end,
    nota = case when f ? 'nota' then left(trim(coalesce(f ->> 'nota', '')), 300) when v_estado = 'aberto' then '' else nota end,
    teste_id = case when v_estado = 'teste' then radar.inteiro(f ->> 'teste_id', 0)::bigint else null end,
    atualizado_em = now()
  where projeto = v_proj and chave = v_chave;
  return jsonb_build_object('ok', true, 'estado', v_estado);
end $_$;


--
-- Name: medir_espaco(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.medir_espaco() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  v_total numeric;
  v_medida text := 'supabase';
  v_radar numeric := round(coalesce((
    select sum(pg_total_relation_size(c.oid)) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'radar' and c.relkind in ('r', 'm')), 0) / 1048576.0, 1);
  v_video numeric := round(coalesce((
    select sum(pg_total_relation_size(c.oid)) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'radar' and c.relname like 'gravacoes%' and c.relkind = 'r'), 0) / 1048576.0, 1);
  v_limite numeric := coalesce((select valor::numeric from radar.config where chave = 'limite_banco_mb' and valor ~ '^[0-9]+(\.[0-9]+)?$'), 500);
  v_manual text := coalesce((select valor from radar.config where chave = 'coleta_manual'), 'ligada');
  v_estado text;
  v_previsao jsonb;
  v_espaco jsonb;
begin
  -- a conta do painel do Supabase: todos os bancos do servidor (o postgres e os bancos-modelo); se um dia faltar
  -- permissao para ler os outros, mede so este banco e diz que a medida e a antiga
  begin
    select round(sum(pg_database_size(d.oid)) / 1048576.0, 1) into v_total from pg_database d;
  exception when others then
    v_total := round(pg_database_size(current_database()) / 1048576.0, 1);
    v_medida := 'banco';
  end;
  v_estado := case when v_manual = 'pausada' or v_total >= v_limite * 0.90 then 'coleta_pausada'
                   when v_total >= v_limite * 0.80 then 'video_pausado'
                   else 'ok' end;
  insert into radar.espaco_diario (dia, total_mb, video_mb, radar_mb, medida, medido_em)
  values (radar.hoje(), v_total, v_video, v_radar, v_medida, now())
  on conflict (dia) do update set total_mb = excluded.total_mb, video_mb = excluded.video_mb, radar_mb = excluded.radar_mb,
                                  medida = excluded.medida, medido_em = excluded.medido_em;
  delete from radar.espaco_diario where dia < radar.hoje() - 400;
  begin
    v_previsao := radar.prever_espaco(v_total, v_video, v_limite);
  exception when others then
    -- a previsao nunca pode impedir a protecao de funcionar
    insert into radar.falhas (onde, mensagem) values ('previsao_espaco', left(sqlerrm, 300));
    v_previsao := null;
  end;
  v_espaco := jsonb_build_object('total_mb', v_total, 'radar_mb', v_radar, 'video_mb', v_video,
                                 'fora_mb', greatest(0, v_total - v_radar), 'medida', v_medida,
                                 'limite_mb', v_limite, 'estado', v_estado, 'manual', v_manual,
                                 'medido_em', radar.ms(now()), 'previsao', v_previsao);
  insert into radar.config (chave, valor) values ('espaco_estado', v_estado)
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  insert into radar.config (chave, valor) values ('espaco', v_espaco::text)
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  return v_espaco;
end $_$;


--
-- Name: membro_atual(); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.membro_atual() RETURNS radar.membros
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select m.*
  from radar.membros m
  join auth.users u on u.id = m.usuario
  where m.usuario = auth.uid() and m.ativo and u.deleted_at is null
    and (u.banned_until is null or u.banned_until < now())
$$;


--
-- Name: membro_de(uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.membro_de(p_usuario uuid) RETURNS radar.membros
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select m.*
  from radar.membros m
  join auth.users u on u.id = m.usuario
  where m.usuario = p_usuario and m.ativo and u.deleted_at is null
    and (u.banned_until is null or u.banned_until < now())
$$;


--
-- Name: meta_acao(jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_acao(p_lista jsonb, p_tipo text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select (x ->> 'value')::numeric::int
  from jsonb_array_elements(case when jsonb_typeof(p_lista) = 'array' then p_lista else '[]'::jsonb end) x
  where x ->> 'action_type' = p_tipo limit 1
$$;


--
-- Name: meta_chamar(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_chamar(p_url text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET statement_timeout TO '70s'
    AS $$
declare
  v_token text;
  v_status int;
  v_corpo text;
  v_app text;
  v_buc text;
  v_uso jsonb;
begin
  select s.decrypted_secret into v_token from vault.decrypted_secrets s where s.name = 'radar_meta_token';
  if coalesce(v_token, '') = '' then raise exception 'meta_sem_token'; end if;
  if p_url !~ '^https://graph\.facebook\.com/v26\.0/' then raise exception 'meta_endereco_estranho'; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '60000');
  -- os cabecalhos de limite saem na mesma consulta (sem variavel do tipo da extensao: a funcao compila mesmo sem ela)
  select r.status, r.content,
         (select h.value from unnest(r.headers) h where lower(h.field) = 'x-app-usage' limit 1),
         (select h.value from unnest(r.headers) h where lower(h.field) = 'x-business-use-case-usage' limit 1)
    into v_status, v_corpo, v_app, v_buc
  from extensions.http(('GET', p_url, array[extensions.http_header('Authorization', 'Bearer ' || v_token),
                                            extensions.http_header('Accept', 'application/json')], null, null)::extensions.http_request) r;
  v_uso := radar.meta_uso(v_app, v_buc);
  return jsonb_build_object('status', coalesce(v_status, 0), 'uso', v_uso -> 'uso', 'espera', v_uso -> 'espera',
                            'corpo', case when v_corpo ~ '^\s*[{\[]' then v_corpo::jsonb else to_jsonb(left(radar.meta_limpo(v_corpo), 300)) end);
end $$;


--
-- Name: meta_endereco(text, date, date); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_endereco(p_conta text, p_de date, p_ate date) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select 'https://graph.facebook.com/v26.0/' || p_conta || '/insights?level=ad&time_increment=1&limit=500'
      || '&time_range=%7B%22since%22%3A%22' || p_de::text || '%22%2C%22until%22%3A%22' || p_ate::text || '%22%7D'
      || '&fields=account_currency,campaign_id,campaign_name,adset_id,adset_name,ad_id,ad_name,spend,impressions,reach,clicks,'
      || 'inline_link_clicks,actions,video_thruplay_watched_actions,video_p25_watched_actions,video_p50_watched_actions,'
      || 'video_p75_watched_actions,video_p100_watched_actions'
$$;


--
-- Name: meta_guardar(text, text, jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_guardar(p_projeto text, p_conta text, p_dados jsonb, p_contem text DEFAULT ''::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_n int;
begin
  insert into radar.meta_anuncios_dia as m (projeto, dia, conta, campanha_id, campanha_nome, conjunto_id, conjunto_nome, anuncio_id,
                                            anuncio_nome, moeda, gasto, impressoes, alcance, cliques, cliques_link, lpv, video_3s,
                                            video_thruplay, video_p25, video_p50, video_p75, video_p100, atualizado_em)
  select p_projeto, (x ->> 'date_start')::date, p_conta, coalesce(x ->> 'campaign_id', ''), x ->> 'campaign_name',
         coalesce(x ->> 'adset_id', ''), x ->> 'adset_name', x ->> 'ad_id', x ->> 'ad_name', coalesce(x ->> 'account_currency', 'BRL'),
         coalesce((x ->> 'spend')::numeric, 0), coalesce((x ->> 'impressions')::numeric, 0)::int, (x ->> 'reach')::numeric::int,
         coalesce((x ->> 'clicks')::numeric, 0)::int, coalesce((x ->> 'inline_link_clicks')::numeric, 0)::int,
         -- 069: as visualizacoes da pagina de destino (o PageView do Pixel). O Meta omite a acao zerada: com clique no link e
         -- sem a acao, e 0 de verdade (o anuncio com LPV zero aparece como 0%); sem clique e sem a acao, nulo. Assim nulo
         -- quer dizer so "ainda nao carregado" (Rodada 2, decisao do Maestro)
         coalesce(radar.meta_acao(x -> 'actions', 'landing_page_view'),
                  case when coalesce((x ->> 'inline_link_clicks')::numeric, 0) > 0 then 0 end),
         radar.meta_acao(x -> 'actions', 'video_view'), radar.meta_acao(x -> 'video_thruplay_watched_actions', 'video_view'),
         radar.meta_acao(x -> 'video_p25_watched_actions', 'video_view'), radar.meta_acao(x -> 'video_p50_watched_actions', 'video_view'),
         radar.meta_acao(x -> 'video_p75_watched_actions', 'video_view'), radar.meta_acao(x -> 'video_p100_watched_actions', 'video_view'),
         now()
  from jsonb_array_elements(case when jsonb_typeof(p_dados) = 'array' then p_dados else '[]'::jsonb end) x
  where coalesce(x ->> 'ad_id', '') <> '' and coalesce(x ->> 'date_start', '') <> ''
    and (coalesce(p_contem, '') = '' or position(lower(p_contem) in lower(coalesce(x ->> 'campaign_name', ''))) > 0)
  on conflict (projeto, dia, anuncio_id) do update set
    conta = excluded.conta, campanha_id = excluded.campanha_id, campanha_nome = excluded.campanha_nome,
    conjunto_id = excluded.conjunto_id, conjunto_nome = excluded.conjunto_nome, anuncio_nome = excluded.anuncio_nome,
    moeda = excluded.moeda, gasto = excluded.gasto, impressoes = excluded.impressoes, alcance = excluded.alcance,
    cliques = excluded.cliques, cliques_link = excluded.cliques_link, lpv = excluded.lpv, video_3s = excluded.video_3s,
    video_thruplay = excluded.video_thruplay, video_p25 = excluded.video_p25, video_p50 = excluded.video_p50,
    video_p75 = excluded.video_p75, video_p100 = excluded.video_p100, atualizado_em = excluded.atualizado_em;
  get diagnostics v_n = row_count;
  return v_n;
end $$;


--
-- Name: meta_limpo(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_limpo(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select regexp_replace(regexp_replace(coalesce(p, ''), 'access_token=[^&\s"'',;]*', 'access_token=***', 'gi'),
                        'Bearer\s+[A-Za-z0-9._\-]+', 'Bearer ***', 'gi')
$$;


--
-- Name: meta_sincronizar(text, date, date); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_sincronizar(p_tipo text DEFAULT 'hora'::text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET statement_timeout TO '280s'
    AS $_$
declare
  v_hoje date := radar.hoje();
  v_pausa timestamptz;
  v_rod bigint;
  p record;
  v_conta text;
  v_url text;
  v_r jsonb;
  v_de date;
  v_ate date;
  v_cham int := 0;
  v_lin int := 0;
  v_pag int;
  v_uso int;
  v_cod int;
  v_espera int := 0;
  v_alto boolean := false;
  v_aviso text;
  v_erro text;
begin
  if not exists (select 1 from radar.integracoes i where i.id = 'meta' and i.ligada) then
    return jsonb_build_object('ok', false, 'erro', 'meta_desligado');
  end if;
  -- a Meta pediu para esperar (limite, uso alto ou token recusado): nenhuma chamada ate la
  select max(r.pausa_ate) into v_pausa from radar.meta_rodadas r where r.pausa_ate > now();
  if v_pausa is not null then return jsonb_build_object('ok', false, 'erro', 'meta_em_pausa', 'ate', v_pausa); end if;
  -- a ultima rodada que chamou a Meta saiu com uso alto ha menos de 30 minutos: tambem nao chama
  if exists (select 1 from (select r.uso, r.quando from radar.meta_rodadas r where r.chamadas > 0 order by r.id desc limit 1) u
             where u.uso >= 75 and u.quando > now() - interval '30 minutes') then
    return jsonb_build_object('ok', false, 'erro', 'meta_uso_alto_recente');
  end if;

  insert into radar.meta_rodadas (tipo) values (p_tipo) returning id into v_rod;
  begin
    <<projetos>>
    for p in select x.id, x.config -> 'meta' as m from radar.projetos x
             where jsonb_typeof(x.config -> 'meta' -> 'contas') = 'array' order by x.id loop
      v_de := case p_tipo when 'hora' then v_hoje when 'madrugada' then v_hoje - 3
                          when 'carga' then coalesce(radar.data(p.m ->> 'desde'), v_hoje - 6) else p_de end;
      v_ate := case p_tipo when 'hora' then v_hoje when 'madrugada' then v_hoje - 1 when 'carga' then v_hoje else p_ate end;
      if v_de is null or v_ate is null or v_de > v_ate then raise exception 'meta_periodo_invalido'; end if;
      -- a carga nunca volta antes do "desde" do contrato
      v_de := greatest(v_de, coalesce(radar.data(p.m ->> 'desde'), v_de));
      update radar.meta_rodadas set de = least(coalesce(de, v_de), v_de), ate = greatest(coalesce(ate, v_ate), v_ate) where id = v_rod;
      for v_conta in select jsonb_array_elements_text(p.m -> 'contas') loop
        if v_conta !~ '^act_[0-9]+$' then raise exception 'meta_conta_estranha'; end if;
        v_url := radar.meta_endereco(v_conta, v_de, v_ate);
        v_pag := 0;
        while v_url is not null loop
          v_r := radar.meta_chamar(v_url);
          v_cham := v_cham + 1;
          v_pag := v_pag + 1;
          v_uso := (v_r ->> 'uso')::int;
          v_espera := coalesce((v_r ->> 'espera')::int, 0);
          update radar.meta_rodadas set chamadas = v_cham, uso = v_uso where id = v_rod;
          if (v_r ->> 'status')::int >= 400 or jsonb_typeof(v_r -> 'corpo') <> 'object' then
            v_cod := radar.inteiro(v_r -> 'corpo' -> 'error' ->> 'code', 0)::int;
            if v_cod in (4, 17, 32, 613) or v_cod between 80000 and 80014 then
              raise exception 'meta_limite % (uso %)', v_cod, v_uso;
            end if;
            if v_cod = 190 then
              raise exception 'meta_token_recusado (190): o Meta recusou o token; gere outro do usuario do sistema Radar WEB e rode o meta/liga.py';
            end if;
            raise exception 'meta_respondeu % %', v_r ->> 'status', left(radar.meta_limpo(v_r -> 'corpo' -> 'error' ->> 'message'), 200);
          end if;
          v_lin := v_lin + radar.meta_guardar(p.id, v_conta, v_r -> 'corpo' -> 'data', coalesce(p.m ->> 'campanha_contem', ''));
          v_url := v_r -> 'corpo' -> 'paging' ->> 'next';
          -- nunca segue um "next" para fora da Graph API v26.0
          if v_url is not null and v_url !~ '^https://graph\.facebook\.com/v26\.0/' then v_url := null; end if;
          -- uso alto depois de qualquer chamada, com ou sem proxima pagina: o que veio fica, a pausa e gravada e a rodada
          -- nao chama mais nada (nem a proxima pagina, nem a proxima conta)
          if v_uso >= 75 then
            v_alto := true;
            v_aviso := 'uso_alto ' || v_uso || '%' || case when v_url is not null then ': parou antes da pagina ' || (v_pag + 1) else '' end;
            exit projetos;
          end if;
          if v_pag >= 20 and v_url is not null then
            v_aviso := concat_ws(' · ', v_aviso, 'teto de 20 paginas em ' || v_conta || ': o resto do periodo ficou para a proxima rodada');
            exit;
          end if;
        end loop;
      end loop;
    end loop;
    update radar.meta_rodadas set linhas = v_lin, aviso = v_aviso,
                                  pausa_ate = case when v_alto then now() + make_interval(mins => greatest(v_espera, 30)) end
    where id = v_rod;
    update radar.integracoes set sincronizada_em = now(), erro = null, erro_em = null,
                                 contagens = jsonb_build_object('linhas', v_lin, 'chamadas', v_cham, 'uso', v_uso, 'aviso', v_aviso) where id = 'meta';
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'chamadas', v_cham, 'linhas', v_lin, 'uso', v_uso, 'aviso', v_aviso));
  exception when others then
    v_erro := left(radar.meta_limpo(sqlerrm), 300);
    -- a excecao desfez o que esta rodada gravou na tabela e no registro: anota de novo, fora do bloco. No limite, a pausa
    -- e o tempo que a Meta pediu, com o piso de 60 minutos; com o token recusado, 6 horas
    update radar.meta_rodadas set erro = v_erro, chamadas = v_cham, uso = v_uso,
                                  pausa_ate = case when v_erro like 'meta_limite%' then now() + make_interval(mins => greatest(v_espera, 60))
                                                   when v_erro like 'meta_token_recusado%' then now() + interval '6 hours' end
    where id = v_rod;
    update radar.integracoes set erro = v_erro, erro_em = now() where id = 'meta';
    return jsonb_build_object('ok', false, 'erro', v_erro, 'chamadas', v_cham);
  end;
end $_$;


--
-- Name: meta_uso(text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.meta_uso(p_app text, p_buc text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
declare
  v_uso int := 0;
  v_espera int := 0;
  a jsonb;
  x jsonb;
  k text;
begin
  begin
    a := coalesce(nullif(p_app, ''), '{}')::jsonb;
    foreach k in array array['call_count', 'total_cputime', 'total_time'] loop
      v_uso := greatest(v_uso, coalesce((a ->> k)::numeric, 0)::int);
    end loop;
  exception when others then null;
  end;
  begin
    for x in select e from jsonb_each(coalesce(nullif(p_buc, ''), '{}')::jsonb) j, jsonb_array_elements(j.value) e loop
      foreach k in array array['call_count', 'total_cputime', 'total_time'] loop
        v_uso := greatest(v_uso, coalesce((x ->> k)::numeric, 0)::int);
      end loop;
      v_espera := greatest(v_espera, coalesce((x ->> 'estimated_time_to_regain_access')::numeric, 0)::int);
    end loop;
  exception when others then null;
  end;
  return jsonb_build_object('uso', v_uso, 'espera', v_espera);
end $$;


--
-- Name: ms(timestamp with time zone); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ms(t timestamp with time zone) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    AS $$ select (extract(epoch from t) * 1000)::bigint $$;


--
-- Name: nome_curto(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.nome_curto(v text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select left(btrim(regexp_replace(lower(coalesce(v, '')), '[^a-z0-9_-]+', '-', 'g'), '-'), 40)
$$;


--
-- Name: nomes(jsonb, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.nomes(j jsonb, limite integer) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce(array_agg(n order by o), '{}')
  from (select n, min(o) as o
        from (select radar.nome_curto(e.v) as n, e.o
              from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end) with ordinality e(v, o)
              where e.o <= limite) x
        where n <> '' group by n) y
$$;


--
-- Name: pagina_id(jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.pagina_id(cfg jsonb, caminho text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  c text := regexp_replace(coalesce(nullif(caminho, ''), '/'), 'index\.html?$', '');
  pg jsonb;
  melhor text;
  tam int := 0;
begin
  if right(c, 1) <> '/' then c := c || '/'; end if;
  for pg in select value from jsonb_array_elements(coalesce(cfg -> 'paginas', '[]'::jsonb)) loop
    if c = pg ->> 'caminho' then return pg ->> 'id'; end if;
    if pg ->> 'caminho' <> '/' and left(c, length(pg ->> 'caminho')) = pg ->> 'caminho' and length(pg ->> 'caminho') > tam then
      melhor := pg ->> 'id';
      tam := length(pg ->> 'caminho');
    end if;
  end loop;
  return left(coalesce(melhor, nullif(trim(both '/' from c), ''), 'raiz'), 80);
end $_$;


--
-- Name: parados(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.parados(f jsonb) RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
with
alvo as (
  select substring(coalesce(f ->> 'parou', '') from '^(.+)\.[0-9]{1,2}$') as fid,
         radar.inteiro(substring(coalesce(f ->> 'parou', '') from '\.([0-9]{1,2})$'), 0)::int as k),
-- as visitas do periodo com os outros filtros: sem o parou (nao chama a si mesma) e sem a fila (031: ate onde a pessoa
-- chegou e da pessoa inteira; a fila escolhe depois, na radar.filtradas, quais visitas aparecem)
base as materialized (
  select x.id, radar.unidade(x.visitante, x.ad_id, x.utm_content) collate "C" as u
  from radar.filtradas((f - 'parou') - 'com') x),
etapas as (
  select et.eo,
         array(select jsonb_array_elements_text(coalesce(et.value -> 'pagina', '[]'::jsonb))) as epags,
         array(select jsonb_array_elements_text(coalesce(et.value -> 'evento', '[]'::jsonb))) as eevs
  from radar.projetos p, alvo,
       jsonb_array_elements(coalesce(p.config -> 'funis', '[]'::jsonb)) fu(value),
       jsonb_array_elements(coalesce(fu.value -> 'etapas', '[]'::jsonb)) with ordinality et(value, eo)
  where p.id = f ->> 'projeto' and fu.value ->> 'id' = alvo.fid),
ep as (select eo, p from etapas, unnest(epags) p),
ee as (select eo, n from etapas, unnest(eevs) n),
cumpridas as (
  select b.id, b.u, ep.eo from base b join radar.visualizacoes v on v.sessao = b.id join ep on ep.p = v.pagina
  union all
  select b.id, b.u, ee.eo from base b join radar.eventos_funil e on e.sessao = b.id join ee on ee.n = e.nome),
mascara as (select id, min(u) as u, bit_or(1::bigint << (eo::int - 1)) as m from cumpridas group by id),
-- so as etapas seguidas desde a primeira (1011 -> 0011), como no Funil
pref as materialized (
  select id, u, case when m = 9223372036854775807 then m else ((~m) & (m + 1)) - 1 end as p from mascara),
-- de cada pessoa (por anuncio), a visita que foi mais longe
uni as materialized (select u, max(p) as p from pref group by u),
k as (select case when alvo.k between 1 and 62 then (1::bigint << alvo.k) - 1 end as m from alvo)
select pref.id from pref join uni on uni.u = pref.u cross join k
where pref.p = k.m and uni.p = k.m
$_$;


--
-- Name: periodos(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.periodos(f jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with p as (select coalesce(radar.data(f ->> 'de'), radar.hoje() - 6) as de, coalesce(radar.data(f ->> 'ate'), radar.hoje()) as ate)
  select jsonb_build_object('de', de::text, 'ate', ate::text,
                            'anterior_de', (de - (ate - de + 1))::text, 'anterior_ate', (de - 1)::text, 'dias', ate - de + 1)
  from p
$$;


--
-- Name: peso(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.peso(j jsonb) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
  select coalesce((select sum((x #>> '{}')::numeric) from jsonb_path_query(coalesce(j, 'null'::jsonb), '$.** ? (@.type() == "number")') x), 0)
$_$;


--
-- Name: plataforma(text, text, boolean, boolean, text, text, text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.plataforma(p_source text, p_medium text, p_fbclid boolean, p_gclid boolean, p_ad_id text, p_campaign_id text, p_utm_campaign text, p_utm_content text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select case
    when not radar.eh_pago(p_medium, p_gclid, p_ad_id, p_campaign_id, p_utm_campaign, p_utm_content) then null
    when coalesce(p_gclid, false)
      or lower(coalesce(p_source, '')) in ('google', 'youtube', 'yt', 'gads', 'google_ads', 'google-ads', 'adwords') then 'google'
    when lower(coalesce(p_source, '')) in ('ig', 'fb', 'an', 'th', 'msg', 'instagram', 'facebook', 'meta', 'threads', 'messenger',
                                           'audience_network', 'audiencenetwork', 'facebook_ads', 'meta_ads', 'fb_ads')
      or (coalesce(p_fbclid, false) and coalesce(p_source, '') = '') then 'meta'
    else 'outro'
  end
$$;


--
-- Name: pode_split(radar.membros); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.pode_split(m radar.membros) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(m.usuario is not null and (m.papel = 'admin'
    or (m.papel = 'equipe' and m.funcao = 'web' and radar.ve_area(m, 'melhorias'))), false)
$$;


--
-- Name: pode_ver(radar.membros, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.pode_ver(m radar.membros, p_projeto text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(m.usuario is not null and (m.papel = 'admin' or p_projeto = any (coalesce(m.projetos, '{}'))), false)
$$;


--
-- Name: prever_espaco(numeric, numeric, numeric); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.prever_espaco(p_total numeric, p_video numeric, p_limite numeric) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_ret int := greatest(1, coalesce((select max(retencao_gravacao_dias) from radar.projetos), 3));
  v_resto numeric := p_total - p_video;
  v_dias int;
  v_ini record;
  v_span numeric;
  v_r numeric;
  v_vd numeric;
  v_vdias int;
  v_teto numeric;
  v_cap numeric;
  v_t1 numeric := 0;
  v_conf text;
  v_marcas jsonb := '[]'::jsonb;
  v_pct int;
  v_alvo numeric;
  t numeric;
begin
  -- o resto (total menos video): da primeira medida dos ultimos 14 dias ate agora
  select count(*) into v_dias from radar.espaco_diario e where e.dia >= radar.hoje() - 14;
  select e.dia, e.medido_em, e.total_mb - e.video_mb as resto into v_ini
  from radar.espaco_diario e where e.dia >= radar.hoje() - 14 and e.dia < radar.hoje() order by e.dia limit 1;
  v_span := case when v_ini.dia is null then 0 else extract(epoch from (now() - v_ini.medido_em)) / 86400.0 end;
  v_r := case when v_span >= 0.5 then (v_resto - v_ini.resto) / v_span end;
  -- o video que entra num dia completo: as particoes de ontem para tras, dentro da guarda, que ainda tem pedaco
  -- (a do dia que esta saindo fica do tamanho cheio ate cair; a de um dia sem coleta nao entra na media)
  select count(*), coalesce(avg(pg_total_relation_size(c.oid)), 0) / 1048576.0 into v_vdias, v_vd
  from generate_series(1, v_ret) i
  join pg_class c on c.relname = 'gravacoes_' || to_char(radar.hoje() - i, 'YYYYMMDD') and c.relkind = 'r'
                 and c.relnamespace = 'radar'::regnamespace
  where exists (select 1 from radar.gravacoes g where g.dia = radar.hoje() - i);
  v_teto := v_vd * (v_ret + 1);
  v_cap := greatest(v_teto, p_video);
  if v_vd > 0 and v_cap > p_video then v_t1 := (v_cap - p_video) / v_vd; end if;
  v_conf := case when v_r is null then 'sem' when v_dias < 7 then 'fraca' else 'boa' end;

  foreach v_pct in array array[70, 80, 90, 100] loop
    v_alvo := p_limite * v_pct / 100.0;
    t := null;
    if p_total >= v_alvo then
      t := 0;
    elsif v_r is null then
      t := null;
    elsif v_pct <= 80 then
      -- video ligado: o resto cresce e o video sobe ate o teto do bloco
      if v_r + v_vd > 0.01 and p_total + (v_r + v_vd) * v_t1 >= v_alvo then
        t := (v_alvo - p_total) / (v_r + v_vd);
      elsif v_r > 0.01 then
        t := v_t1 + (v_alvo - (v_resto + v_r * v_t1 + v_cap)) / v_r;
      end if;
    elsif v_r > 0.01 then
      -- do 80% em diante o video nao fica guardado: conta o resto sozinho
      t := (v_alvo - v_resto) / v_r;
    end if;
    if t > 3650 then t := null; end if;
    v_marcas := v_marcas || jsonb_build_object(
      'pct', v_pct, 'mb', round(v_alvo, 1), 'video', v_pct <= 80,
      'dias', round(t, 1),
      'data', case when t is not null then (((now() + make_interval(secs => (t * 86400)::double precision)) at time zone 'America/Sao_Paulo')::date)::text end);
  end loop;

  return jsonb_build_object(
    'confianca', v_conf,
    'dias_de_medida', v_dias,
    'desde', v_ini.dia::text,
    'resto_mb_dia', round(v_r, 2),
    'video_mb_dia', round(v_vd, 1),
    'dias_de_video', v_vdias,
    'video_teto_mb', round(v_teto, 1),
    'retencao_video_dias', v_ret,
    'marcas', v_marcas);
end $$;


--
-- Name: recusa(text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.recusa(p_motivo text, p_detalhe text DEFAULT ''::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
begin
  insert into radar.recusas as r (dia, motivo, detalhe, vezes) values (radar.hoje(), p_motivo, left(coalesce(p_detalhe, ''), 120), 1)
  on conflict (dia, motivo, detalhe) do update set vezes = r.vezes + 1;
  return p_motivo;
end $$;


--
-- Name: rejeicao_por_pagina(text, date, date, boolean); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.rejeicao_por_pagina(p_projeto text, p_de date, p_ate date, inclui_teste boolean DEFAULT false) RETURNS TABLE(pagina text, entradas bigint, rejeicoes bigint, taxa numeric)
    LANGUAGE sql STABLE
    AS $$
  select e.pagina,
         count(*) filter (where e.conta) as entradas,
         count(*) filter (where e.rejeitou) as rejeicoes,
         round(count(*) filter (where e.rejeitou)::numeric / nullif(count(*) filter (where e.conta), 0), 4) as taxa
  from radar.entradas e
  where e.projeto = p_projeto and e.dia between p_de and p_ate and (inclui_teste or not e.teste)
  group by e.pagina
  order by entradas desc
$$;


--
-- Name: remover_split(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.remover_split(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  t radar.testes;
begin
  select * into t from radar.testes where id = radar.inteiro(f ->> 'id', 0) and projeto = f ->> 'projeto' and tipo = 'split' for update;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_existe'); end if;
  if t.estado <> 'rascunho' then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
  delete from radar.testes where id = t.id;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: remover_teste(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.remover_teste(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
begin
  delete from radar.testes where id = radar.inteiro(f ->> 'id', 0) and projeto = f ->> 'projeto' and tipo = 'ab';   -- 076: so o A/B
  return jsonb_build_object('ok', found, 'erro', case when found then null else 'nao_existe' end);
end $$;


--
-- Name: retencao_video(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.retencao_video(p_projeto text) RETURNS interval
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select make_interval(days => coalesce((select retencao_gravacao_dias from radar.projetos where id = p_projeto), 5))
$$;


--
-- Name: robo(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.robo(ua text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    -- o teste do Google usa "moto g power (2022)" com Chrome novo; Chrome de verdade no Android nao manda mais o
    -- modelo (manda "K"), e navegador de app manda o modelo seguido de "Build/...; wv", que nao casa aqui
    when coalesce(ua, '') ~ 'moto g power \(2022\)\) AppleWebKit' then 'teste-do-google'
    else lower(substring(coalesce(ua, '') from '(?i)(googlebot|adsbot-google|mediapartners-google|google-inspectiontool|googleother|storebot-google|feedfetcher-google|google page speed|chrome-lighthouse|bingbot|bingpreview|msnbot|yandexbot|yandexmobilebot|baiduspider|duckduckbot|applebot|petalbot|seznambot|ahrefsbot|semrushbot|mj12bot|dotbot|dataforseobot|rogerbot|screaming frog|gptbot|oai-searchbot|chatgpt-user|claudebot|claude-web|anthropic-ai|perplexitybot|bytespider|amazonbot|ccbot|facebookexternalhit|facebookcatalog|meta-externalagent|meta-externalfetcher|telegrambot|twitterbot|linkedinbot|slackbot|discordbot|pinterestbot|headlesschrome|phantomjs|ptst/|gtmetrix|pingdom|uptimerobot|statuscake|site24x7|python-requests|python-urllib|curl/|wget/|go-http-client|node-fetch|axios/)'))
  end
$$;


--
-- Name: rotas_da_pessoa(radar.membros); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.rotas_da_pessoa(o radar.membros) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
  select array(select r from unnest(radar.rotas_externas(case when radar.ve_visitas(o) then 'sessoes' else 'agregado' end)
                                    || array['crm_resumo', 'crm_lista', 'crm_ficha']) r
               where radar.ve_alguma(o, radar.areas_da_rota(r)))
$$;


--
-- Name: rotas_externas(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.rotas_externas(p_nivel text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select array['eu', 'projetos', 'valores', 'resumo', 'inicio', 'captura', 'pagina', 'mapa', 'insights', 'desempenho', 'laboratorio',
               'leitura', 'oportunidades', 'leads_mql', 'testes', 'alertas', 'achados', 'diario', 'guardiao', 'apelidos',
               'trafego', 'fluxo', 'leads_paginas',
               -- 060: as leituras das telas da 050 a 059, so numeros somados, e as publicacoes
               'pesquisas', 'trafego_quando', 'trafego_anuncios', 'fluxo_segmento', 'publicacoes']
         || case when p_nivel = 'sessoes' then array['sessoes', 'sessao', 'guardadas'] else '{}'::text[] end
$$;


--
-- Name: salvar_achados(text, date, jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_achados(p_projeto text, p_dia date, p_lista jsonb, p_fonte text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_n int;
begin
  if p_projeto is null or not exists (select 1 from radar.projetos where id = p_projeto) then
    return jsonb_build_object('ok', false, 'erro', 'projeto');
  end if;
  if p_dia is null or p_dia > radar.hoje() or p_dia < radar.hoje() - 3 then return jsonb_build_object('ok', false, 'erro', 'dia'); end if;
  if jsonb_typeof(p_lista) <> 'array' or jsonb_array_length(p_lista) > 300 then return jsonb_build_object('ok', false, 'erro', 'lista'); end if;
  with n as (
    select distinct on (left(x.chave, 300)) left(x.chave, 300) as chave, left(coalesce(x.tipo, ''), 40) as tipo,
           coalesce(x.aprendizado, false) as aprendizado, left(coalesce(x.pagina, ''), 80) as pagina,
           left(coalesce(x.titulo, ''), 400) as titulo, left(coalesce(x.fazer, ''), 600) as fazer, left(coalesce(x.numeros, ''), 900) as numeros,
           left(coalesce(x.confianca, ''), 20) as confianca, greatest(coalesce(x.ganho, 0), 0) as ganho
    from jsonb_to_recordset(p_lista) as x(chave text, tipo text, aprendizado boolean, pagina text, titulo text, fazer text, numeros text,
                                          confianca text, ganho numeric)
    where coalesce(x.chave, '') like p_projeto || '|%'),
  memoria as (
    insert into radar.achados as a (projeto, chave, tipo, aprendizado, pagina, titulo, fazer, numeros, confianca, ganho,
                                    primeiro_dia, ultimo_dia, dias_visto, atualizado_em)
    select p_projeto, n.chave, n.tipo, n.aprendizado, n.pagina, n.titulo, n.fazer, n.numeros, n.confianca, n.ganho, p_dia, p_dia, 1, now()
    from n
    on conflict (projeto, chave) do update set
      tipo = excluded.tipo, aprendizado = excluded.aprendizado, pagina = excluded.pagina, titulo = excluded.titulo,
      fazer = excluded.fazer, numeros = excluded.numeros, confianca = excluded.confianca, ganho = excluded.ganho,
      primeiro_dia = least(a.primeiro_dia, excluded.primeiro_dia),
      dias_visto = a.dias_visto + case when excluded.ultimo_dia > a.ultimo_dia then 1 else 0 end,
      ultimo_dia = greatest(a.ultimo_dia, excluded.ultimo_dia),
      atualizado_em = now()
    returning 1),
  do_dia as (
    insert into radar.achados_dia (projeto, dia, chave, ganho, confianca)
    select p_projeto, p_dia, n.chave, n.ganho, n.confianca from n
    on conflict (projeto, dia, chave) do update set ganho = excluded.ganho, confianca = excluded.confianca
    returning 1)
  select count(*) into v_n from memoria;

  insert into radar.achados_registros as r (projeto, dia, fonte, quantos, em) values (p_projeto, p_dia, left(coalesce(p_fonte, ''), 20), v_n, now())
  on conflict (projeto, dia) do update set fonte = excluded.fonte, quantos = excluded.quantos, em = now();

  delete from radar.achados_dia where dia < radar.hoje() - 400;
  delete from radar.achados_registros where dia < radar.hoje() - 400;
  -- o que ficou aberto e nao aparece ha mais de 90 dias sai da memoria (o que a casa marcou fica)
  delete from radar.achados where estado = 'aberto' and ultimo_dia < radar.hoje() - 90;
  return jsonb_build_object('ok', true, 'guardados', v_n, 'dia', p_dia::text);
end $$;


--
-- Name: salvar_apelido(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_apelido(f jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_tipo text := coalesce(f ->> 'tipo', '');
  v_valor text := trim(coalesce(f ->> 'valor', ''));
  v_nome text := regexp_replace(trim(coalesce(f ->> 'nome', '')), '\s+', ' ', 'g');
begin
  if v_tipo not in ('campanha', 'conjunto', 'anuncio') then return jsonb_build_object('ok', false, 'erro', 'tipo_invalido'); end if;
  if v_valor = '' or length(v_valor) > 200 then return jsonb_build_object('ok', false, 'erro', 'codigo_invalido'); end if;
  if length(v_nome) > 120 then return jsonb_build_object('ok', false, 'erro', 'nome_longo'); end if;
  if v_nome = '' then
    delete from radar.apelidos where projeto = f ->> 'projeto' and tipo = v_tipo and valor = v_valor;
  else
    insert into radar.apelidos (projeto, tipo, valor, nome) values (f ->> 'projeto', v_tipo, v_valor, v_nome)
    on conflict (projeto, tipo, valor) do update set nome = excluded.nome, atualizado_em = now();
  end if;
  return jsonb_build_object('ok', true, 'apelidos', radar.api_apelidos(f));
end $$;


--
-- Name: salvar_captacao(jsonb, uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_captacao(f jsonb, quem uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_proj text := f ->> 'projeto';
  v_pag text := f ->> 'pagina';
  v_video real;
  k text;
begin
  if not exists (select 1 from radar.projetos p, jsonb_array_elements(coalesce(p.config -> 'paginas', '[]'::jsonb)) x
                 where p.id = v_proj and x ->> 'id' = v_pag) then
    return jsonb_build_object('ok', false, 'erro', 'pagina');
  end if;
  if f ? 'video' then
    if jsonb_typeof(f -> 'video') <> 'number' or (f ->> 'video')::numeric < 0 or (f ->> 'video')::numeric > 1 then
      return jsonb_build_object('ok', false, 'erro', 'video');
    end if;
    v_video := (f ->> 'video')::real;
  end if;
  foreach k in array array['cliques', 'leitura', 'velocidade', 'erros'] loop
    if f ? k and jsonb_typeof(f -> k) <> 'boolean' then return jsonb_build_object('ok', false, 'erro', k); end if;
  end loop;
  insert into radar.captacao as c (projeto, pagina, video, cliques, leitura, velocidade, erros, atualizado_em, atualizado_por)
  values (v_proj, v_pag, coalesce(v_video, 1), coalesce((f ->> 'cliques')::boolean, true), coalesce((f ->> 'leitura')::boolean, true),
          coalesce((f ->> 'velocidade')::boolean, true), coalesce((f ->> 'erros')::boolean, true), now(), quem)
  on conflict (projeto, pagina) do update set
    video = coalesce(v_video, c.video),
    cliques = coalesce((f ->> 'cliques')::boolean, c.cliques),
    leitura = coalesce((f ->> 'leitura')::boolean, c.leitura),
    velocidade = coalesce((f ->> 'velocidade')::boolean, c.velocidade),
    erros = coalesce((f ->> 'erros')::boolean, c.erros),
    atualizado_em = now(), atualizado_por = quem;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: salvar_diario(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_diario(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_proj text := p ->> 'projeto';
  v_dia date := radar.data(p ->> 'dia');
  v_texto jsonb;
begin
  if v_proj is null or not exists (select 1 from radar.projetos where id = v_proj) then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
  if v_dia is null or v_dia > radar.hoje() or v_dia < radar.hoje() - 7 then return jsonb_build_object('ok', false, 'erro', 'dia'); end if;
  -- so as tres partes, cada uma com ate 5 frases curtas, em texto puro
  select jsonb_object_agg(k, coalesce((select jsonb_agg(left(trim(x), 400)) from (
           select x from jsonb_array_elements_text(case when jsonb_typeof(p -> 'texto' -> k) = 'array' then p -> 'texto' -> k else '[]'::jsonb end) x
           where trim(x) <> '' limit 5) y), '[]'::jsonb))
  into v_texto from unnest(array['aconteceu', 'porque', 'fazer']) k;
  if (select sum(jsonb_array_length(v)) from jsonb_each(v_texto) e(k, v)) = 0 then return jsonb_build_object('ok', false, 'erro', 'vazio'); end if;
  insert into radar.diarios as d (projeto, dia, texto, fatos, cortadas, gerado_em, gerado_por)
  values (v_proj, v_dia, v_texto, case when jsonb_typeof(p -> 'fatos') = 'object' and length((p -> 'fatos')::text) < 200000 then p -> 'fatos' end,
          greatest(radar.inteiro(p ->> 'cortadas', 0)::int, 0), now(), left(coalesce(p ->> 'gerado_por', 'claude'), 60))
  on conflict (projeto, dia) do update set texto = excluded.texto, fatos = excluded.fatos, cortadas = excluded.cortadas,
                                           gerado_em = now(), gerado_por = excluded.gerado_por;
  delete from radar.diarios where dia < radar.hoje() - 400;
  return jsonb_build_object('ok', true, 'projeto', v_proj, 'dia', v_dia::text);
end $$;


--
-- Name: salvar_laboratorio(jsonb, uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_laboratorio(f jsonb, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  v_id bigint;
  v_rel jsonb := case when jsonb_typeof(f -> 'relatorio') = 'object' and length((f -> 'relatorio')::text) <= 800000 then f -> 'relatorio' end;
  v_img jsonb := case when jsonb_typeof(f -> 'imagens') = 'object' and length((f -> 'imagens')::text) <= 4000000 then f -> 'imagens' end;
  v_notas jsonb;
begin
  if coalesce(f ->> 'pagina', '') = '' or f ->> 'estrategia' not in ('mobile', 'desktop') or coalesce(f ->> 'url', '') !~ '^https://' then
    return jsonb_build_object('ok', false, 'erro', 'dados');
  end if;
  if jsonb_typeof(f -> 'notas') = 'object' then
    select jsonb_object_agg(k, least(greatest(radar.inteiro(f -> 'notas' ->> k, 0), 0), 100)) into v_notas
      from unnest(array['desempenho', 'acessibilidade', 'praticas', 'seo']) k
     where coalesce(f -> 'notas' ->> k, '') ~ '^[0-9]{1,3}$';
  end if;
  insert into radar.velocidade_lab (projeto, pagina, url, estrategia, nota, lcp_ms, fcp_ms, tbt_ms, si_ms, cls, medido_por, notas, relatorio, imagens)
  values (f ->> 'projeto', left(f ->> 'pagina', 80), left(f ->> 'url', 300), f ->> 'estrategia',
          least(greatest(radar.inteiro(f ->> 'nota', 0), 0), 100),
          nullif(radar.inteiro(f ->> 'lcp_ms', -1), -1), nullif(radar.inteiro(f ->> 'fcp_ms', -1), -1),
          nullif(radar.inteiro(f ->> 'tbt_ms', -1), -1), nullif(radar.inteiro(f ->> 'si_ms', -1), -1),
          case when f ? 'cls' then least(greatest(radar.decimal(f ->> 'cls', 0), 0), 10)::real end, p_usuario,
          v_notas, v_rel, v_img)
  returning id into v_id;
  -- 30 testes por pagina e aparelho; o relatorio fica nos 10 mais recentes e as imagens so no ultimo
  with ordem as (
    select id, row_number() over (order by medido_em desc, id desc) as n
      from radar.velocidade_lab
     where projeto = f ->> 'projeto' and pagina = left(f ->> 'pagina', 80) and estrategia = f ->> 'estrategia'),
  apaga as (delete from radar.velocidade_lab l using ordem o where l.id = o.id and o.n > 30 returning l.id)
  update radar.velocidade_lab l
     set relatorio = case when o.n > 10 then null else l.relatorio end,
         imagens = case when o.n > 1 then null else l.imagens end
    from ordem o
   where l.id = o.id and o.n <= 30 and ((o.n > 10 and l.relatorio is not null) or (o.n > 1 and l.imagens is not null));
  return jsonb_build_object('ok', true, 'id', v_id);
end $_$;


--
-- Name: salvar_split(jsonb, uuid, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_split(f jsonb, p_usuario uuid, p_quem text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  v_id bigint := nullif(radar.inteiro(f ->> 'id', 0), 0);
  cfg jsonb;
  v_dominios text[];
  v_raizes text[];
  v_nome text := left(btrim(coalesce(f ->> 'nome', '')), 80);
  v_hip text := left(btrim(coalesce(f ->> 'hipotese', '')), 600);
  v_dom text := lower(btrim(coalesce(f ->> 'dominio_split', '')));
  v_ent text := lower(btrim(coalesce(f ->> 'entrada', ''), ' /'));
  v_vers jsonb := f -> 'versoes';
  v_anu jsonb := coalesce(f -> 'anuncios', '[]'::jsonb);
  v_limpo jsonb := '[]'::jsonb;
  v_anu_limpo jsonb := '[]'::jsonb;
  v jsonb;
  v_vid text; v_pag text; v_url text; v_host text; v_vnome text; v_peso int;
  v_ids text[] := '{}';
  v_pags text[] := '{}';
  v_soma int := 0;
  v_pag_a text; v_pag_b text;
  t radar.testes;
  v_rodou boolean;
  v_hist jsonb;
  v_mudou text[] := '{}';
begin
  select p.config, array(select lower(d) from unnest(p.dominios) d) into cfg, v_dominios from radar.projetos p where p.id = f ->> 'projeto';
  if cfg is null then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
  if v_nome = '' then return jsonb_build_object('ok', false, 'erro', 'nome'); end if;
  -- o subdominio do split: um nome de verdade, debaixo de um dominio do projeto, e nao o proprio dominio do funil
  v_raizes := array(select distinct regexp_replace(d, '^www\.', '') from unnest(v_dominios) d where d like '%.%' and d !~ '^[0-9.]+$');
  if v_dom !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' or length(v_dom) > 200
     or v_dom = any (v_dominios)
     or not exists (select 1 from unnest(v_raizes) r where right(v_dom, length(r) + 1) = '.' || r) then
    return jsonb_build_object('ok', false, 'erro', 'dominio');
  end if;
  if v_ent !~ '^[a-z0-9-]{1,40}$' then return jsonb_build_object('ok', false, 'erro', 'entrada'); end if;
  -- as versoes: de 2 a 5, letras de a a e (a 'a' e a atual), uma pagina do contrato cada (sem obrigado), endereco https
  -- num dominio do projeto, peso inteiro de 0 a 100, somando 100
  if jsonb_typeof(v_vers) <> 'array' or jsonb_array_length(v_vers) not between 2 and 5 then
    return jsonb_build_object('ok', false, 'erro', 'versoes');
  end if;
  for v in select value from jsonb_array_elements(v_vers) loop
    if jsonb_typeof(v) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'versoes'); end if;
    v_vid := lower(btrim(coalesce(v ->> 'id', '')));
    if v_vid !~ '^[a-e]$' or v_vid = any (v_ids) then return jsonb_build_object('ok', false, 'erro', 'versoes'); end if;
    v_pag := coalesce(v ->> 'pagina', '');
    if v_pag = any (v_pags) or not exists (
         select 1 from jsonb_array_elements(coalesce(cfg -> 'paginas', '[]'::jsonb)) pg
         where pg ->> 'id' = v_pag and coalesce(pg ->> 'tipo', '') <> 'obrigado') then
      return jsonb_build_object('ok', false, 'erro', 'pagina', 'versao', v_vid);
    end if;
    v_url := btrim(coalesce(v ->> 'url', ''));
    v_host := lower(substring(v_url from '^https://([^/:?#]+)'));
    if length(v_url) > 500 or v_host is null or v_host <> all (v_dominios) or v_host in ('localhost', '127.0.0.1') or v_url ~ '\s' then
      return jsonb_build_object('ok', false, 'erro', 'url', 'versao', v_vid);
    end if;
    if coalesce(v ->> 'peso', '') !~ '^[0-9]{1,3}$' or (v ->> 'peso')::int > 100 then
      return jsonb_build_object('ok', false, 'erro', 'pesos');
    end if;
    v_peso := (v ->> 'peso')::int;
    v_vnome := left(btrim(coalesce(v ->> 'nome', '')), 40);
    if v_vnome = '' then v_vnome := 'Versão ' || upper(v_vid); end if;
    v_soma := v_soma + v_peso;
    v_ids := v_ids || v_vid;
    v_pags := v_pags || v_pag;
    v_limpo := v_limpo || jsonb_build_object('id', v_vid, 'nome', v_vnome, 'pagina', v_pag, 'url', v_url, 'peso', v_peso);
  end loop;
  if not ('a' = any (v_ids)) then return jsonb_build_object('ok', false, 'erro', 'versoes'); end if;
  if v_soma <> 100 then return jsonb_build_object('ok', false, 'erro', 'pesos'); end if;
  select coalesce(jsonb_agg(x order by x ->> 'id'), '[]'::jsonb) into v_limpo from jsonb_array_elements(v_limpo) x;
  -- as colunas do A/B continuam preenchidas (nao nulas): a pagina da 'a' e a da primeira outra versao
  select x ->> 'pagina' into v_pag_a from jsonb_array_elements(v_limpo) x where x ->> 'id' = 'a';
  select x ->> 'pagina' into v_pag_b from jsonb_array_elements(v_limpo) x where x ->> 'id' <> 'a' order by x ->> 'id' limit 1;
  -- os anuncios para ratear o custo (opcional): ids do Meta (anuncio, conjunto ou campanha), ate 50
  if jsonb_typeof(v_anu) <> 'array' or jsonb_array_length(v_anu) > 50 then return jsonb_build_object('ok', false, 'erro', 'anuncios'); end if;
  for v in select value from jsonb_array_elements(v_anu) loop
    if jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^[0-9]{5,30}$' then return jsonb_build_object('ok', false, 'erro', 'anuncios'); end if;
    if not v_anu_limpo @> jsonb_build_array(v #>> '{}') then v_anu_limpo := v_anu_limpo || jsonb_build_array(v #>> '{}'); end if;
  end loop;

  if v_id is null then
    insert into radar.testes (projeto, nome, hipotese, pagina_a, pagina_b, metrica, efeito, inicio, criado_por,
                              tipo, estado, dominio_split, entrada, versoes, anuncios, historico)
    values (f ->> 'projeto', v_nome, v_hip, v_pag_a, v_pag_b, 'lead', 0.2, radar.hoje(), p_usuario,
            'split', 'rascunho', v_dom, v_ent, v_limpo, v_anu_limpo,
            jsonb_build_array(radar.split_linha(p_quem, 'criou', 'Criou o teste (' || radar.split_divisao(v_limpo) || ')', v_limpo)))
    returning id into v_id;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;

  select * into t from radar.testes where id = v_id and projeto = f ->> 'projeto' and tipo = 'split' for update;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_existe'); end if;
  if t.estado not in ('rascunho', 'pausado') then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
  v_rodou := exists (select 1 from jsonb_array_elements(t.historico) h where h ->> 'acao' = 'rodar');
  -- depois de rodar: endereco e versoes (letra e pagina) ficam como estao
  if v_rodou and ((v_dom, v_ent) is distinct from (t.dominio_split, t.entrada)
       or (select jsonb_agg(jsonb_build_array(x ->> 'id', x ->> 'pagina') order by x ->> 'id') from jsonb_array_elements(v_limpo) x)
          is distinct from (select jsonb_agg(jsonb_build_array(x ->> 'id', x ->> 'pagina') order by x ->> 'id') from jsonb_array_elements(t.versoes) x)) then
    return jsonb_build_object('ok', false, 'erro', 'travado');
  end if;
  -- o que mudou vai para o historico
  v_hist := t.historico;
  if radar.split_divisao(v_limpo) <> radar.split_divisao(t.versoes) then
    v_hist := v_hist || radar.split_linha(p_quem, 'pesos', 'Mudou a divisão: ' || radar.split_divisao(t.versoes) || ' para ' || radar.split_divisao(v_limpo), v_limpo);
  end if;
  for v in select value from jsonb_array_elements(v_limpo) loop
    if exists (select 1 from jsonb_array_elements(t.versoes) o where o ->> 'id' = v ->> 'id' and o ->> 'url' <> v ->> 'url') then
      v_hist := v_hist || radar.split_linha(p_quem, 'endereco', 'Mudou o endereço da versão ' || upper(v ->> 'id') || ' para ' || (v ->> 'url'), v_limpo);
    end if;
  end loop;
  if v_nome <> t.nome then v_mudou := v_mudou || 'o nome'; end if;
  if v_hip <> t.hipotese then v_mudou := v_mudou || 'a hipótese'; end if;
  if v_anu_limpo <> t.anuncios then v_mudou := v_mudou || 'os anúncios'; end if;
  if not v_rodou and ((v_dom, v_ent) is distinct from (t.dominio_split, t.entrada)) then v_mudou := v_mudou || 'o endereço do anúncio'; end if;
  if not v_rodou and (select jsonb_agg(jsonb_build_array(x ->> 'id', x ->> 'pagina') order by x ->> 'id') from jsonb_array_elements(v_limpo) x)
                     is distinct from (select jsonb_agg(jsonb_build_array(x ->> 'id', x ->> 'pagina') order by x ->> 'id') from jsonb_array_elements(t.versoes) x) then
    v_mudou := v_mudou || 'as versões';
  end if;
  if cardinality(v_mudou) > 0 then
    v_hist := v_hist || radar.split_linha(p_quem, 'editou', 'Mudou ' || array_to_string(v_mudou, ', '), v_limpo);
  end if;
  -- o historico guarda as 200 linhas mais recentes
  if jsonb_array_length(v_hist) > 200 then
    select jsonb_agg(h order by n) into v_hist from jsonb_array_elements(v_hist) with ordinality x(h, n) where n > jsonb_array_length(v_hist) - 200;
  end if;
  update radar.testes set nome = v_nome, hipotese = v_hip, dominio_split = v_dom, entrada = v_ent, versoes = v_limpo, anuncios = v_anu_limpo,
         pagina_a = v_pag_a, pagina_b = v_pag_b, historico = v_hist
   where id = v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $_$;


--
-- Name: salvar_teste(jsonb, uuid); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.salvar_teste(f jsonb, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  v_id bigint := nullif(radar.inteiro(f ->> 'id', 0), 0);
  v_inicio date := coalesce(radar.data(f ->> 'inicio'), radar.hoje());
  v_fim date := radar.data(f ->> 'fim');
  v_efeito numeric := round(radar.decimal(f ->> 'efeito', 0.2)::numeric, 3);
  v_metrica text := coalesce(nullif(f ->> 'metrica', ''), 'lead');
  cfg jsonb;
  t radar.testes;
begin
  select config into cfg from radar.projetos where id = f ->> 'projeto';
  if cfg is null then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
  if coalesce(btrim(f ->> 'nome'), '') = '' then return jsonb_build_object('ok', false, 'erro', 'nome'); end if;
  if coalesce(f ->> 'pagina_a', '') = coalesce(f ->> 'pagina_b', '')
     or (select count(*) from jsonb_array_elements(coalesce(cfg -> 'paginas', '[]'::jsonb)) pg where pg ->> 'id' in (f ->> 'pagina_a', f ->> 'pagina_b')) <> 2 then
    return jsonb_build_object('ok', false, 'erro', 'paginas');
  end if;
  if v_metrica not in ('lead', 'mql') then return jsonb_build_object('ok', false, 'erro', 'metrica'); end if;
  if v_efeito < 0.02 or v_efeito > 2 then return jsonb_build_object('ok', false, 'erro', 'efeito'); end if;
  if v_fim is not null and v_fim < v_inicio then return jsonb_build_object('ok', false, 'erro', 'datas'); end if;
  if v_id is null then
    insert into radar.testes (projeto, nome, hipotese, pagina_a, pagina_b, metrica, efeito, inicio, fim, criado_por)
    values (f ->> 'projeto', left(btrim(f ->> 'nome'), 80), left(coalesce(btrim(f ->> 'hipotese'), ''), 400), f ->> 'pagina_a', f ->> 'pagina_b',
            v_metrica, v_efeito, v_inicio, v_fim, p_usuario)
    returning id into v_id;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select * into t from radar.testes where id = v_id and projeto = f ->> 'projeto' and tipo = 'ab' for update;   -- 076: so o A/B
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_existe'); end if;
  -- a trava: ja tem um dia fechado com visita de verdade entrando por uma das versoes (usa o indice sessoes_entrada)
  if exists (select 1 from radar.sessoes s
             where s.projeto = t.projeto and s.primeira_pagina in (t.pagina_a, t.pagina_b)
               and s.dia >= t.inicio and s.dia < radar.hoje() and (t.fim is null or s.dia <= t.fim)
               and not s.teste and coalesce(s.visivel_ms, 0) > 0) then
    if (f ->> 'pagina_a', f ->> 'pagina_b', v_metrica, v_efeito, v_inicio) is distinct from (t.pagina_a, t.pagina_b, t.metrica, t.efeito, t.inicio) then
      return jsonb_build_object('ok', false, 'erro', 'travado');
    end if;
    update radar.testes set nome = left(btrim(f ->> 'nome'), 80), hipotese = left(coalesce(btrim(f ->> 'hipotese'), ''), 400) where id = v_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'travado', true);
  end if;
  update radar.testes set nome = left(btrim(f ->> 'nome'), 80), hipotese = left(coalesce(btrim(f ->> 'hipotese'), ''), 400),
         pagina_a = f ->> 'pagina_a', pagina_b = f ->> 'pagina_b', metrica = v_metrica, efeito = v_efeito, inicio = v_inicio, fim = v_fim
   where id = v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;


--
-- Name: sessao_json(radar.sessoes); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.sessao_json(s radar.sessoes) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select jsonb_build_object(
    'id', s.id, 'projeto', s.projeto, 'visitante', s.visitante, 'inicio', radar.ms(s.inicio), 'fim', radar.ms(s.fim),
    'dispositivo', s.dispositivo, 'teste', s.teste::int,
    'utm_source', s.utm_source, 'utm_medium', s.utm_medium, 'utm_campaign', s.utm_campaign, 'utm_content', s.utm_content,
    'utm_term', s.utm_term, 'referrer', s.referrer, 'paginas', s.paginas, 'cliques', s.cliques, 'raiva', s.raiva,
    'mortos', s.mortos, 'erros', s.erros, 'resultado', s.resultado, 'primeira_pagina', s.primeira_pagina,
    'gravada', ((s.gravada and s.inicio > now() - radar.retencao_video(s.projeto)) or coalesce(k.com_video, false))::int,
    'video_apagado', (s.gravada and s.inicio <= now() - radar.retencao_video(s.projeto) and not coalesce(k.com_video, false))::int,
    'lead', s.lead::int, 'engajada', s.engajada::int, 'engajou_por', s.engajou_por)
  -- quem e a pessoa (aparelho, navegador, lugar) e o resto da visita, como no Clarity
  || jsonb_build_object(
    'sistema', s.sistema, 'sistema_versao', s.sistema_versao, 'navegador', s.navegador, 'navegador_versao', s.navegador_versao,
    'app', s.app, 'modelo', s.modelo, 'tela', s.tela, 'idioma', s.idioma, 'fuso', s.fuso, 'toque', s.toque::int,
    'pais', s.pais, 'estado', s.estado, 'cidade', s.cidade, 'visivel_ms', s.visivel_ms, 'ultima_pagina', s.ultima_pagina,
    'campaign_id', s.campaign_id, 'adset_id', s.adset_id, 'ad_id', s.ad_id, 'fbclid', s.fbclid::int, 'gclid', s.gclid::int,
    'lead_em', radar.ms(s.lead_em), 'resultado_em', radar.ms(s.resultado_em), 'engajou_em', radar.ms(s.engajou_em))
  -- 030: guardada (com a nota) e, para o video que ainda vai vencer, quando (o inicio mais os dias de video do projeto)
  || jsonb_build_object(
    'guardada', (k.sessao is not null)::int, 'nota', k.nota,
    'vence_em', case when s.gravada and k.sessao is null and s.inicio > now() - radar.retencao_video(s.projeto)
                     then radar.ms(s.inicio + radar.retencao_video(s.projeto)) end)
  from (select 1) um left join radar.guardadas k on k.sessao = s.id
$$;


--
-- Name: sim(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.sim(t text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$ select coalesce(t, '') in ('1', 'true') $$;


--
-- Name: situacao_active(jsonb, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.situacao_active(p_active jsonb, p_via text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  select case
    when p_via is null then ''
    when p_active ->> 'situacao' in ('novo', 'existente') then 'ok'
    when p_active ->> 'situacao' in ('erro', 'nao_encontrado') then p_active ->> 'situacao'
    when p_via = 'importado' then 'historico'
    else 'pendente'
  end
$$;


--
-- Name: split_divisao(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.split_divisao(p_versoes jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(string_agg(upper(v ->> 'id') || ' ' || (v ->> 'peso') || '%', ' · ' order by v ->> 'id'), '')
  from jsonb_array_elements(p_versoes) v
$$;


--
-- Name: split_linha(text, text, text, jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.split_linha(p_quem text, p_acao text, p_frase text, p_versoes jsonb) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object('quando', radar.ms(now()), 'dia', radar.hoje()::text, 'quem', coalesce(nullif(p_quem, ''), 'alguém'),
    'acao', p_acao, 'o_que', p_frase,
    'pesos', coalesce((select jsonb_object_agg(v ->> 'id', (v ->> 'peso')::int) from jsonb_array_elements(p_versoes) v), '{}'::jsonb))
$$;


--
-- Name: texto(text, integer); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.texto(v text, n integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select left(nullif(btrim(regexp_replace(coalesce(v, ''), '[[:cntrl:]<>"`]', '', 'g')), ''), n)
$$;


--
-- Name: trocar_senha(uuid, text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.trocar_senha(p_usuario uuid, p_senha text, p_manter_sessao text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'extensions'
    AS $$
begin
  if length(coalesce(p_senha, '')) < 8 then raise exception 'senha_curta'; end if;
  update auth.users set encrypted_password = crypt(p_senha, gen_salt('bf', 10)), updated_at = now() where id = p_usuario;
  if not found then raise exception 'usuario_nao_existe'; end if;
  delete from auth.sessions where user_id = p_usuario and id::text is distinct from p_manter_sessao;
end $$;


--
-- Name: uf_do_ddd(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.uf_do_ddd(d text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select case
    when d between '11' and '19' then 'SP'
    when d in ('21', '22', '24') then 'RJ'
    when d in ('27', '28') then 'ES'
    when d in ('31', '32', '33', '34', '35', '37', '38') then 'MG'
    when d in ('41', '42', '43', '44', '45', '46') then 'PR'
    when d in ('47', '48', '49') then 'SC'
    when d in ('51', '53', '54', '55') then 'RS'
    when d = '61' then 'DF'
    when d in ('62', '64') then 'GO'
    when d = '63' then 'TO'
    when d in ('65', '66') then 'MT'
    when d = '67' then 'MS'
    when d = '68' then 'AC'
    when d = '69' then 'RO'
    when d in ('71', '73', '74', '75', '77') then 'BA'
    when d = '79' then 'SE'
    when d in ('81', '87') then 'PE'
    when d = '82' then 'AL'
    when d = '83' then 'PB'
    when d = '84' then 'RN'
    when d in ('85', '88') then 'CE'
    when d in ('86', '89') then 'PI'
    when d in ('91', '93', '94') then 'PA'
    when d in ('92', '97') then 'AM'
    when d = '95' then 'RR'
    when d = '96' then 'AP'
    when d in ('98', '99') then 'MA'
  end
$$;


--
-- Name: unidade(text, text, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.unidade(visitante text, ad_id text, utm_content text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
  select visitante || '|' || coalesce(nullif(ad_id, ''), nullif(utm_content, ''), '')
$$;


--
-- Name: url_codificar(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.url_codificar(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select coalesce(string_agg(case when s.c ~ '^[A-Za-z0-9._~-]$' then s.c else
           (select string_agg('%' || upper(lpad(to_hex(get_byte(convert_to(s.c, 'UTF8'), i)), 2, '0')), '' order by i)
            from generate_series(0, octet_length(convert_to(s.c, 'UTF8')) - 1) i) end, '' order by s.n), '')
  from regexp_split_to_table(coalesce(t, ''), '') with ordinality as s(c, n)
$_$;


--
-- Name: utm_canonica(jsonb); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.utm_canonica(o jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select case
    when jsonb_typeof(o) is distinct from 'object' then o
    when not radar.utm_fonte_meta(o ->> 'utm_source') then o
    when radar.utm_id(o ->> 'utm_campaign') is null and radar.utm_id(o ->> 'utm_content') is null then o
    else o || jsonb_strip_nulls(jsonb_build_object(
      'utm_campaign', radar.utm_id(o ->> 'utm_campaign'),
      'utm_content', radar.utm_id(o ->> 'utm_content'),
      'utm_term', radar.utm_id(o ->> 'utm_medium'),
      'utm_source', case when lower(btrim(coalesce(o ->> 'utm_source', ''))) in
                               ('metaads', 'meta_ads', 'meta-ads', 'meta', 'facebookads', 'facebook_ads', 'facebook-ads', 'fb_ads', 'fbads')
                         then coalesce(radar.utm_lugar(o ->> 'utm_term'), 'meta') end))
  end
$$;


--
-- Name: utm_fonte_meta(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.utm_fonte_meta(t text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $$
  select lower(btrim(coalesce(t, ''))) in ('metaads', 'meta_ads', 'meta-ads', 'meta ads', 'meta', 'facebookads', 'facebook_ads', 'facebook-ads',
    'facebook ads', 'facebook', 'fb', 'fb_ads', 'fbads', 'fb-ads', 'instagram', 'instagramads', 'instagram_ads', 'ig', 'an', 'audience_network',
    'audiencenetwork', 'audience-network', 'msg', 'messenger', 'th', 'threads')
$$;


--
-- Name: utm_id(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.utm_id(t text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $_$
  select (regexp_match(coalesce(t, ''), '\|\s*([0-9]{6,})\s*$'))[1]
$_$;


--
-- Name: utm_lugar(text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.utm_lugar(t text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $$
  select case
    when lower(coalesce(t, '')) like 'instagram%' then 'ig'
    when lower(coalesce(t, '')) like 'facebook%' then 'fb'
    when lower(coalesce(t, '')) like 'threads%' then 'th'
    when lower(coalesce(t, '')) like 'messenger%' then 'msg'
    when lower(coalesce(t, '')) like 'audience%' or lower(coalesce(t, '')) like 'an\_%' then 'an'
  end
$$;


--
-- Name: ve_alguma(radar.membros, text[]); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ve_alguma(m radar.membros, p_areas text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(m.usuario is not null and (p_areas is null or exists (select 1 from unnest(p_areas) a where radar.ve_area(m, a))), false)
$$;


--
-- Name: ve_area(radar.membros, text); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ve_area(m radar.membros, p_area text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(m.usuario is not null and p_area = any (radar.todas_as_areas()) and (
    m.papel = 'admin'
    or (m.papel = 'equipe' and p_area = any (coalesce(m.areas, '{}')))
    or (m.papel = 'leitor' and p_area <> all (array['fluxo', 'crm', 'pesquisas', 'instalacao'])
        and (p_area <> 'gravacoes' or m.nivel = 'sessoes'))), false)
$$;


--
-- Name: ve_visitas(radar.membros); Type: FUNCTION; Schema: radar; Owner: -
--

CREATE FUNCTION radar.ve_visitas(m radar.membros) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select radar.ve_area(m, 'gravacoes')
$$;


--
-- Name: aberturas; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.aberturas (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    pessoa uuid,
    acao text NOT NULL,
    via text DEFAULT 'tela'::text NOT NULL,
    chave bigint,
    CONSTRAINT aberturas_acao_check CHECK ((acao = ANY (ARRAY['ficha'::text, 'apagar'::text])))
);


--
-- Name: aberturas_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.aberturas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.aberturas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chaves_servidor; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.chaves_servidor (
    id bigint NOT NULL,
    nome text NOT NULL,
    prefixo text NOT NULL,
    hash text NOT NULL,
    projetos text[] DEFAULT '{}'::text[] NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    revogada_em timestamp with time zone,
    ultimo_uso timestamp with time zone,
    usos bigint DEFAULT 0 NOT NULL
);


--
-- Name: chaves_servidor_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.chaves_servidor ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.chaves_servidor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: envios; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.envios (
    id uuid NOT NULL,
    pessoa uuid NOT NULL,
    projeto text NOT NULL,
    quando timestamp with time zone NOT NULL,
    tipo text NOT NULL,
    pagina text DEFAULT ''::text NOT NULL,
    dados jsonb DEFAULT '{}'::jsonb NOT NULL,
    sessao text DEFAULT ''::text NOT NULL,
    visitante text DEFAULT ''::text NOT NULL,
    servidor_ms integer,
    active jsonb DEFAULT '{}'::jsonb NOT NULL,
    planilha jsonb DEFAULT '{}'::jsonb NOT NULL,
    via text DEFAULT 'servidor'::text NOT NULL,
    teste boolean DEFAULT false NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT envios_tipo_check CHECK ((tipo = ANY (ARRAY['inscricao'::text, 'captura'::text, 'pesquisa_parcial'::text, 'pesquisa'::text, 'pesquisa_link'::text]))),
    CONSTRAINT envios_via_check CHECK ((via = ANY (ARRAY['servidor'::text, 'fila'::text, 'importado'::text])))
);


--
-- Name: exclusoes; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.exclusoes (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    projeto text NOT NULL,
    email_sha256 text NOT NULL,
    motivo text DEFAULT ''::text NOT NULL
);


--
-- Name: exclusoes_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.exclusoes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.exclusoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exportacoes; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.exportacoes (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    projeto text NOT NULL,
    filtro jsonb DEFAULT '{}'::jsonb NOT NULL,
    quantas integer DEFAULT 0 NOT NULL,
    pessoas uuid[] DEFAULT '{}'::uuid[] NOT NULL
);


--
-- Name: exportacoes_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.exportacoes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.exportacoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupo_cache; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.grupo_cache (
    pessoa uuid NOT NULL,
    projeto text NOT NULL,
    situacao text NOT NULL,
    calculado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: grupo_eventos; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.grupo_eventos (
    id bigint NOT NULL,
    projeto text NOT NULL,
    telefone_chave text NOT NULL,
    telefone text DEFAULT ''::text NOT NULL,
    acao text NOT NULL,
    release text DEFAULT ''::text NOT NULL,
    campanha text DEFAULT ''::text NOT NULL,
    jid text DEFAULT ''::text NOT NULL,
    grupo text DEFAULT ''::text NOT NULL,
    quando timestamp with time zone NOT NULL,
    quando_do_payload boolean DEFAULT false NOT NULL,
    origem text DEFAULT 'webhook'::text NOT NULL,
    assinatura text NOT NULL,
    log bigint,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT grupo_eventos_acao_check CHECK ((acao = ANY (ARRAY['entrou'::text, 'saiu'::text, 'pedido'::text]))),
    CONSTRAINT grupo_eventos_origem_check CHECK ((origem = ANY (ARRAY['webhook'::text, 'sync'::text]))),
    CONSTRAINT grupo_eventos_telefone_chave_check CHECK ((telefone_chave ~ '^[0-9]{10}$'::text))
);


--
-- Name: grupo_eventos_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.grupo_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.grupo_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: leituras_porta; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.leituras_porta (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    chave bigint,
    projeto text NOT NULL,
    filtro jsonb DEFAULT '{}'::jsonb NOT NULL,
    quantas integer DEFAULT 0 NOT NULL,
    pessoas uuid[] DEFAULT '{}'::uuid[] NOT NULL
);


--
-- Name: leituras_porta_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.leituras_porta ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.leituras_porta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parametros; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.parametros (
    chave text NOT NULL,
    valor jsonb NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: reenvios; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.reenvios (
    id bigint NOT NULL,
    envio uuid NOT NULL,
    pessoa uuid NOT NULL,
    projeto text NOT NULL,
    automatico boolean DEFAULT false NOT NULL,
    pedido_por uuid,
    pedido_em timestamp with time zone DEFAULT now() NOT NULL,
    situacao text DEFAULT 'pendente'::text NOT NULL,
    resultado text,
    tentativas integer DEFAULT 0 NOT NULL,
    proxima_em timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_http integer,
    passos jsonb,
    feito_em timestamp with time zone,
    CONSTRAINT reenvios_situacao_check CHECK ((situacao = ANY (ARRAY['pendente'::text, 'ok'::text, 'desistiu'::text])))
);


--
-- Name: reenvios_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.reenvios ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.reenvios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sendflow_campanhas; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.sendflow_campanhas (
    release text NOT NULL,
    projeto text NOT NULL,
    nome text DEFAULT ''::text NOT NULL
);


--
-- Name: sendflow_chaves; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.sendflow_chaves (
    id bigint NOT NULL,
    projeto text NOT NULL,
    prefixo text NOT NULL,
    hash text NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    revogada_em timestamp with time zone,
    ultimo_uso timestamp with time zone,
    usos bigint DEFAULT 0 NOT NULL
);


--
-- Name: sendflow_chaves_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_chaves ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.sendflow_chaves_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sendflow_grupos; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.sendflow_grupos (
    jid text NOT NULL,
    release text NOT NULL,
    nome text DEFAULT ''::text NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sendflow_log; Type: TABLE; Schema: radar_crm; Owner: -
--

CREATE TABLE radar_crm.sendflow_log (
    id bigint NOT NULL,
    projeto text NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    evento text DEFAULT ''::text NOT NULL,
    resultado text DEFAULT 'recebido'::text NOT NULL,
    linhas integer DEFAULT 0 NOT NULL,
    erro text DEFAULT ''::text NOT NULL,
    payload jsonb NOT NULL
);


--
-- Name: sendflow_log_id_seq; Type: SEQUENCE; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar_crm.sendflow_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: achados; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.achados (
    projeto text NOT NULL,
    chave text NOT NULL,
    tipo text DEFAULT ''::text NOT NULL,
    aprendizado boolean DEFAULT false NOT NULL,
    pagina text DEFAULT ''::text NOT NULL,
    titulo text DEFAULT ''::text NOT NULL,
    fazer text DEFAULT ''::text NOT NULL,
    numeros text DEFAULT ''::text NOT NULL,
    confianca text DEFAULT ''::text NOT NULL,
    ganho numeric DEFAULT 0 NOT NULL,
    primeiro_dia date NOT NULL,
    ultimo_dia date NOT NULL,
    dias_visto integer DEFAULT 1 NOT NULL,
    estado text DEFAULT 'aberto'::text NOT NULL,
    estado_em timestamp with time zone,
    estado_por uuid,
    nota text DEFAULT ''::text NOT NULL,
    teste_id bigint,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT achados_estado_check CHECK ((estado = ANY (ARRAY['aberto'::text, 'feito'::text, 'dispensado'::text, 'teste'::text])))
);


--
-- Name: achados_dia; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.achados_dia (
    projeto text NOT NULL,
    dia date NOT NULL,
    chave text NOT NULL,
    ganho numeric DEFAULT 0 NOT NULL,
    confianca text DEFAULT ''::text NOT NULL
);


--
-- Name: achados_registros; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.achados_registros (
    projeto text NOT NULL,
    dia date NOT NULL,
    fonte text NOT NULL,
    quantos integer DEFAULT 0 NOT NULL,
    em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: active_catalogo; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.active_catalogo (
    tipo text NOT NULL,
    id text NOT NULL,
    nome text NOT NULL,
    extra jsonb DEFAULT '{}'::jsonb NOT NULL,
    visto_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT active_catalogo_tipo_check CHECK ((tipo = ANY (ARRAY['listas'::text, 'tags'::text, 'campos'::text, 'automacoes'::text])))
);


--
-- Name: apelidos; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.apelidos (
    projeto text NOT NULL,
    tipo text NOT NULL,
    valor text NOT NULL,
    nome text NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT apelidos_nome_check CHECK (((length(nome) >= 1) AND (length(nome) <= 120))),
    CONSTRAINT apelidos_tipo_check CHECK ((tipo = ANY (ARRAY['campanha'::text, 'conjunto'::text, 'anuncio'::text])))
);


--
-- Name: chaves; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.chaves (
    id bigint NOT NULL,
    nome text NOT NULL,
    prefixo text NOT NULL,
    hash text NOT NULL,
    projetos text[] DEFAULT '{}'::text[] NOT NULL,
    todos boolean DEFAULT false NOT NULL,
    nivel text DEFAULT 'agregado'::text NOT NULL,
    limite_minuto integer DEFAULT 60 NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    criada_por uuid,
    expira_em timestamp with time zone,
    revogada_em timestamp with time zone,
    ultimo_uso timestamp with time zone,
    usos bigint DEFAULT 0 NOT NULL,
    limite_dia integer DEFAULT 500 NOT NULL,
    avisos_sistema boolean DEFAULT false NOT NULL,
    dono uuid,
    pessoal boolean DEFAULT false NOT NULL,
    CONSTRAINT chaves_limite_dia_check CHECK (((limite_dia >= 1) AND (limite_dia <= 100000))),
    CONSTRAINT chaves_limite_minuto_check CHECK (((limite_minuto >= 1) AND (limite_minuto <= 600))),
    CONSTRAINT chaves_nivel_check CHECK ((nivel = ANY (ARRAY['agregado'::text, 'sessoes'::text])))
);


--
-- Name: chaves_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.chaves ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.chaves_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chaves_ritmo; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.chaves_ritmo (
    chave bigint NOT NULL,
    minuto timestamp with time zone NOT NULL,
    chamadas integer DEFAULT 0 NOT NULL
);


--
-- Name: chaves_uso; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.chaves_uso (
    chave bigint NOT NULL,
    dia date NOT NULL,
    rota text NOT NULL,
    chamadas integer DEFAULT 0 NOT NULL,
    ultimo timestamp with time zone
);


--
-- Name: cliques; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.cliques (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    dispositivo text NOT NULL,
    quando timestamp with time zone NOT NULL,
    x_pct real NOT NULL,
    y_px integer NOT NULL,
    seletor text DEFAULT ''::text NOT NULL,
    texto text DEFAULT ''::text NOT NULL,
    raiva boolean DEFAULT false NOT NULL,
    morto boolean DEFAULT false NOT NULL,
    fixo boolean DEFAULT false NOT NULL,
    automatico boolean DEFAULT false NOT NULL
)
PARTITION BY RANGE (dia);


--
-- Name: cliques_202608; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.cliques_202608 (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    dispositivo text NOT NULL,
    quando timestamp with time zone NOT NULL,
    x_pct real NOT NULL,
    y_px integer NOT NULL,
    seletor text DEFAULT ''::text NOT NULL,
    texto text DEFAULT ''::text NOT NULL,
    raiva boolean DEFAULT false NOT NULL,
    morto boolean DEFAULT false NOT NULL,
    fixo boolean DEFAULT false NOT NULL,
    automatico boolean DEFAULT false NOT NULL
);


--
-- Name: cliques_202609; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.cliques_202609 (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    dispositivo text NOT NULL,
    quando timestamp with time zone NOT NULL,
    x_pct real NOT NULL,
    y_px integer NOT NULL,
    seletor text DEFAULT ''::text NOT NULL,
    texto text DEFAULT ''::text NOT NULL,
    raiva boolean DEFAULT false NOT NULL,
    morto boolean DEFAULT false NOT NULL,
    fixo boolean DEFAULT false NOT NULL,
    automatico boolean DEFAULT false NOT NULL
);


--
-- Name: cliques_202610; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.cliques_202610 (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    dispositivo text NOT NULL,
    quando timestamp with time zone NOT NULL,
    x_pct real NOT NULL,
    y_px integer NOT NULL,
    seletor text DEFAULT ''::text NOT NULL,
    texto text DEFAULT ''::text NOT NULL,
    raiva boolean DEFAULT false NOT NULL,
    morto boolean DEFAULT false NOT NULL,
    fixo boolean DEFAULT false NOT NULL,
    automatico boolean DEFAULT false NOT NULL
);


--
-- Name: cliques_202611; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.cliques_202611 (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    dispositivo text NOT NULL,
    quando timestamp with time zone NOT NULL,
    x_pct real NOT NULL,
    y_px integer NOT NULL,
    seletor text DEFAULT ''::text NOT NULL,
    texto text DEFAULT ''::text NOT NULL,
    raiva boolean DEFAULT false NOT NULL,
    morto boolean DEFAULT false NOT NULL,
    fixo boolean DEFAULT false NOT NULL,
    automatico boolean DEFAULT false NOT NULL
);


--
-- Name: cliques_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.cliques ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.cliques_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: config; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.config (
    chave text NOT NULL,
    valor text NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: diarios; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.diarios (
    projeto text NOT NULL,
    dia date NOT NULL,
    texto jsonb NOT NULL,
    fatos jsonb,
    cortadas integer DEFAULT 0 NOT NULL,
    gerado_em timestamp with time zone DEFAULT now() NOT NULL,
    gerado_por text DEFAULT ''::text NOT NULL
);


--
-- Name: entradas; Type: VIEW; Schema: radar; Owner: -
--

CREATE VIEW radar.entradas AS
 SELECT projeto,
    dia,
    primeira_pagina AS pagina,
    dispositivo,
    teste,
    utm_source,
    utm_campaign,
    utm_content,
    id AS sessao,
    engajada,
    engajou_por,
    (recebido_em < (now() - '00:30:00'::interval)) AS encerrada,
    (engajada OR (recebido_em < (now() - '00:30:00'::interval))) AS conta,
    ((NOT engajada) AND (recebido_em < (now() - '00:30:00'::interval))) AS rejeitou
   FROM radar.sessoes s;


--
-- Name: erros; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.erros (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    quando timestamp with time zone NOT NULL,
    mensagem text NOT NULL,
    arquivo text,
    linha integer,
    origem text DEFAULT 'pagina'::text NOT NULL,
    CONSTRAINT erros_origem_check CHECK ((origem = ANY (ARRAY['pagina'::text, 'fora'::text])))
);


--
-- Name: erros_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.erros ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.erros_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: espaco_diario; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.espaco_diario (
    dia date NOT NULL,
    total_mb numeric(10,1) NOT NULL,
    video_mb numeric(10,1) NOT NULL,
    medido_em timestamp with time zone DEFAULT now() NOT NULL,
    radar_mb numeric(10,1),
    medida text DEFAULT 'supabase'::text NOT NULL
);


--
-- Name: eventos_funil; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.eventos_funil (
    id bigint NOT NULL,
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    quando timestamp with time zone NOT NULL,
    nome text NOT NULL,
    dados jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: eventos_funil_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.eventos_funil ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.eventos_funil_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: falhas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.falhas (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    onde text NOT NULL,
    mensagem text NOT NULL
);


--
-- Name: falhas_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.falhas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.falhas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: feedback; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.feedback (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid NOT NULL,
    tipo text NOT NULL,
    tela text DEFAULT ''::text NOT NULL,
    texto text NOT NULL,
    estado text DEFAULT 'novo'::text NOT NULL,
    resposta text DEFAULT ''::text NOT NULL,
    respondido_em timestamp with time zone,
    respondido_por uuid,
    CONSTRAINT feedback_estado_check CHECK ((estado = ANY (ARRAY['novo'::text, 'visto'::text, 'feito'::text, 'descartado'::text]))),
    CONSTRAINT feedback_tipo_check CHECK ((tipo = ANY (ARRAY['bug'::text, 'faltou'::text, 'ruim'::text, 'ideia'::text])))
);


--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

CREATE SEQUENCE radar.feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: radar; Owner: -
--

ALTER SEQUENCE radar.feedback_id_seq OWNED BY radar.feedback.id;


--
-- Name: funcoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.funcoes (
    id text NOT NULL,
    nome text NOT NULL,
    ordem integer NOT NULL,
    areas text[] NOT NULL
);


--
-- Name: gravacoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
)
PARTITION BY RANGE (dia);


--
-- Name: gravacoes_20261013; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261013 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261014; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261014 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261015; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261015 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261016; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261016 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261017; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261017 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261018; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261018 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261019; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261019 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261020; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261020 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261021; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261021 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261022; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261022 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_20261023; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_20261023 (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    recebido_em timestamp with time zone DEFAULT now() NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: gravacoes_excluidas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_excluidas (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    projeto text NOT NULL,
    sessao text NOT NULL,
    pedacos integer DEFAULT 0 NOT NULL,
    bytes bigint DEFAULT 0 NOT NULL,
    guardada boolean DEFAULT false NOT NULL,
    motivo text DEFAULT ''::text NOT NULL,
    CONSTRAINT gravacoes_excluidas_motivo_check CHECK ((length(motivo) <= 300))
);


--
-- Name: gravacoes_excluidas_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.gravacoes_excluidas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.gravacoes_excluidas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gravacoes_guardadas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.gravacoes_guardadas (
    sessao text NOT NULL,
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    formato text NOT NULL,
    bytes integer NOT NULL,
    dados bytea NOT NULL,
    CONSTRAINT gravacoes_guardadas_formato_check CHECK ((formato = ANY (ARRAY['gzip'::text, 'json'::text])))
);


--
-- Name: guardadas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.guardadas (
    sessao text NOT NULL,
    projeto text NOT NULL,
    nota text DEFAULT ''::text NOT NULL,
    com_video boolean DEFAULT false NOT NULL,
    guardada_por uuid,
    guardada_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizada_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT guardadas_nota_check CHECK ((length(nota) <= 500))
);


--
-- Name: integracoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.integracoes (
    id text NOT NULL,
    ligada boolean DEFAULT false NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    segredo_fim text,
    atualizada_em timestamp with time zone,
    atualizada_por uuid,
    sincronizada_em timestamp with time zone,
    contagens jsonb DEFAULT '{}'::jsonb NOT NULL,
    erro text,
    erro_em timestamp with time zone,
    andamento jsonb
);


--
-- Name: integracoes_registro; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.integracoes_registro (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    quem uuid,
    integracao text NOT NULL,
    acao text NOT NULL,
    detalhe text
);


--
-- Name: integracoes_registro_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.integracoes_registro ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.integracoes_registro_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: meta_anuncios_dia; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.meta_anuncios_dia (
    projeto text NOT NULL,
    dia date NOT NULL,
    conta text DEFAULT ''::text NOT NULL,
    campanha_id text DEFAULT ''::text NOT NULL,
    campanha_nome text,
    conjunto_id text DEFAULT ''::text NOT NULL,
    conjunto_nome text,
    anuncio_id text NOT NULL,
    anuncio_nome text,
    miniatura text,
    moeda text DEFAULT 'BRL'::text NOT NULL,
    gasto numeric(12,2) DEFAULT 0 NOT NULL,
    impressoes integer DEFAULT 0 NOT NULL,
    alcance integer,
    cliques integer DEFAULT 0 NOT NULL,
    cliques_link integer DEFAULT 0 NOT NULL,
    video_3s integer,
    video_thruplay integer,
    video_p25 integer,
    video_p50 integer,
    video_p75 integer,
    video_p100 integer,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    lpv integer
);


--
-- Name: meta_rodadas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.meta_rodadas (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    tipo text NOT NULL,
    de date,
    ate date,
    chamadas integer DEFAULT 0 NOT NULL,
    linhas integer DEFAULT 0 NOT NULL,
    uso integer,
    pausa_ate timestamp with time zone,
    erro text,
    aviso text
);


--
-- Name: meta_rodadas_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.meta_rodadas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.meta_rodadas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: migracoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.migracoes (
    arquivo text NOT NULL,
    aplicado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pacotes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.pacotes (
    visualizacao text NOT NULL,
    seq integer NOT NULL,
    dia date NOT NULL
);


--
-- Name: paginas_mapa; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.paginas_mapa (
    projeto text NOT NULL,
    pagina text NOT NULL,
    secoes text[] DEFAULT '{}'::text[] NOT NULL,
    ctas text[] DEFAULT '{}'::text[] NOT NULL,
    campos text[] DEFAULT '{}'::text[] NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: projetos; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.projetos (
    id text NOT NULL,
    nome text NOT NULL,
    situacao text DEFAULT 'nao_instalado'::text NOT NULL,
    dominios text[] DEFAULT '{}'::text[] NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    engajamento_segundos integer DEFAULT 10 NOT NULL,
    retencao_gravacao_dias integer DEFAULT 3 NOT NULL,
    retencao_cliques_dias integer DEFAULT 90 NOT NULL,
    retencao_sessoes_meses integer DEFAULT 13 NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT projetos_engajamento_segundos_check CHECK (((engajamento_segundos >= 1) AND (engajamento_segundos <= 120))),
    CONSTRAINT projetos_id_check CHECK ((id ~ '^[a-z0-9-]{2,40}$'::text)),
    CONSTRAINT projetos_retencao_cliques_dias_check CHECK (((retencao_cliques_dias >= 7) AND (retencao_cliques_dias <= 400))),
    CONSTRAINT projetos_retencao_gravacao_dias_check CHECK (((retencao_gravacao_dias >= 1) AND (retencao_gravacao_dias <= 90))),
    CONSTRAINT projetos_retencao_sessoes_meses_check CHECK (((retencao_sessoes_meses >= 1) AND (retencao_sessoes_meses <= 36))),
    CONSTRAINT projetos_situacao_check CHECK ((situacao = ANY (ARRAY['ativo'::text, 'demonstracao'::text, 'nao_instalado'::text])))
);


--
-- Name: publicacoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.publicacoes (
    id bigint NOT NULL,
    projeto text NOT NULL,
    pagina text NOT NULL,
    url text NOT NULL,
    quando timestamp with time zone NOT NULL,
    resumo text DEFAULT ''::text NOT NULL
);


--
-- Name: publicacoes_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.publicacoes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.publicacoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recusas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.recusas (
    dia date NOT NULL,
    motivo text NOT NULL,
    detalhe text DEFAULT ''::text NOT NULL,
    vezes integer DEFAULT 0 NOT NULL
);


--
-- Name: redes_internas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.redes_internas (
    id bigint NOT NULL,
    rede cidr NOT NULL,
    nome text DEFAULT ''::text NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    criada_por uuid
);


--
-- Name: redes_internas_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.redes_internas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.redes_internas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: split_entregas; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.split_entregas (
    teste bigint NOT NULL,
    versao text NOT NULL,
    dia date NOT NULL,
    hora smallint NOT NULL,
    n integer DEFAULT 0 NOT NULL,
    CONSTRAINT split_entregas_hora_check CHECK (((hora >= 0) AND (hora <= 23))),
    CONSTRAINT split_entregas_n_check CHECK ((n >= 0))
);


--
-- Name: tempos_api; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.tempos_api (
    dia date NOT NULL,
    rota text NOT NULL,
    origem text NOT NULL,
    chamadas integer DEFAULT 0 NOT NULL,
    total_ms bigint DEFAULT 0 NOT NULL,
    max_ms integer DEFAULT 0 NOT NULL,
    lentas integer DEFAULT 0 NOT NULL,
    CONSTRAINT tempos_api_origem_check CHECK ((origem = ANY (ARRAY['tela'::text, 'porta'::text])))
);


--
-- Name: testes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.testes (
    id bigint NOT NULL,
    projeto text NOT NULL,
    nome text NOT NULL,
    hipotese text DEFAULT ''::text NOT NULL,
    pagina_a text NOT NULL,
    pagina_b text NOT NULL,
    metrica text DEFAULT 'lead'::text NOT NULL,
    efeito numeric DEFAULT 0.20 NOT NULL,
    inicio date NOT NULL,
    fim date,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tipo text DEFAULT 'ab'::text NOT NULL,
    estado text DEFAULT 'rascunho'::text NOT NULL,
    dominio_split text,
    entrada text,
    versoes jsonb DEFAULT '[]'::jsonb NOT NULL,
    promovida text,
    anuncios jsonb DEFAULT '[]'::jsonb NOT NULL,
    historico jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT testes_check CHECK ((pagina_a <> pagina_b)),
    CONSTRAINT testes_check1 CHECK (((fim IS NULL) OR (fim >= inicio))),
    CONSTRAINT testes_efeito_check CHECK (((efeito >= 0.02) AND (efeito <= (2)::numeric))),
    CONSTRAINT testes_entrada_check CHECK (((entrada IS NULL) OR (entrada ~ '^[a-z0-9-]{1,40}$'::text))),
    CONSTRAINT testes_estado_check CHECK ((estado = ANY (ARRAY['rascunho'::text, 'rodando'::text, 'pausado'::text, 'encerrado'::text]))),
    CONSTRAINT testes_metrica_check CHECK ((metrica = ANY (ARRAY['lead'::text, 'mql'::text]))),
    CONSTRAINT testes_split_endereco_check CHECK (((tipo <> 'split'::text) OR ((dominio_split IS NOT NULL) AND (entrada IS NOT NULL) AND (jsonb_typeof(versoes) = 'array'::text)))),
    CONSTRAINT testes_tipo_check CHECK ((tipo = ANY (ARRAY['ab'::text, 'split'::text])))
);


--
-- Name: testes_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.testes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.testes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: velocidade_lab; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.velocidade_lab (
    id bigint NOT NULL,
    projeto text NOT NULL,
    pagina text NOT NULL,
    url text NOT NULL,
    estrategia text NOT NULL,
    nota smallint,
    lcp_ms integer,
    fcp_ms integer,
    tbt_ms integer,
    si_ms integer,
    cls real,
    medido_em timestamp with time zone DEFAULT now() NOT NULL,
    medido_por uuid,
    notas jsonb,
    relatorio jsonb,
    imagens jsonb,
    CONSTRAINT velocidade_lab_estrategia_check CHECK ((estrategia = ANY (ARRAY['mobile'::text, 'desktop'::text]))),
    CONSTRAINT velocidade_lab_nota_check CHECK (((nota >= 0) AND (nota <= 100)))
);


--
-- Name: velocidade_lab_id_seq; Type: SEQUENCE; Schema: radar; Owner: -
--

ALTER TABLE radar.velocidade_lab ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME radar.velocidade_lab_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: visitantes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.visitantes (
    projeto text NOT NULL,
    id text NOT NULL,
    primeira_vez timestamp with time zone DEFAULT now() NOT NULL,
    ultima_vez timestamp with time zone DEFAULT now() NOT NULL,
    sessoes integer DEFAULT 0 NOT NULL,
    lead_ref text
);


--
-- Name: visitantes_internos; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.visitantes_internos (
    projeto text NOT NULL,
    visitante text NOT NULL,
    desde timestamp with time zone DEFAULT now() NOT NULL,
    rede_id bigint
);


--
-- Name: visualizacoes; Type: TABLE; Schema: radar; Owner: -
--

CREATE TABLE radar.visualizacoes (
    id text NOT NULL,
    sessao text NOT NULL,
    projeto text NOT NULL,
    dia date NOT NULL,
    pagina text NOT NULL,
    caminho text NOT NULL,
    titulo text,
    ordem smallint NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fim timestamp with time zone NOT NULL,
    largura integer,
    altura integer,
    altura_doc integer,
    rolagem smallint DEFAULT 0 NOT NULL,
    visivel_ms integer DEFAULT 0 NOT NULL,
    gravada boolean DEFAULT false NOT NULL,
    lcp_ms integer,
    inp_ms integer,
    cls real,
    fcp_ms integer,
    ttfb_ms integer,
    carga_ms integer,
    peso_kb integer,
    rede text,
    vaivem smallint,
    ativo_ms integer,
    secoes jsonb,
    ctas jsonb,
    form jsonb,
    rolagem_30s smallint,
    CONSTRAINT visualizacoes_rolagem_check CHECK (((rolagem >= 0) AND (rolagem <= 100)))
);


--
-- Name: cliques_202608; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques ATTACH PARTITION radar.cliques_202608 FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');


--
-- Name: cliques_202609; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques ATTACH PARTITION radar.cliques_202609 FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');


--
-- Name: cliques_202610; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques ATTACH PARTITION radar.cliques_202610 FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');


--
-- Name: cliques_202611; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques ATTACH PARTITION radar.cliques_202611 FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');


--
-- Name: gravacoes_20261013; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261013 FOR VALUES FROM ('2026-10-13') TO ('2026-10-14');


--
-- Name: gravacoes_20261014; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261014 FOR VALUES FROM ('2026-10-14') TO ('2026-10-15');


--
-- Name: gravacoes_20261015; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261015 FOR VALUES FROM ('2026-10-15') TO ('2026-10-16');


--
-- Name: gravacoes_20261016; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261016 FOR VALUES FROM ('2026-10-16') TO ('2026-10-17');


--
-- Name: gravacoes_20261017; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261017 FOR VALUES FROM ('2026-10-17') TO ('2026-10-18');


--
-- Name: gravacoes_20261018; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261018 FOR VALUES FROM ('2026-10-18') TO ('2026-10-19');


--
-- Name: gravacoes_20261019; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261019 FOR VALUES FROM ('2026-10-19') TO ('2026-10-20');


--
-- Name: gravacoes_20261020; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261020 FOR VALUES FROM ('2026-10-20') TO ('2026-10-21');


--
-- Name: gravacoes_20261021; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261021 FOR VALUES FROM ('2026-10-21') TO ('2026-10-22');


--
-- Name: gravacoes_20261022; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261022 FOR VALUES FROM ('2026-10-22') TO ('2026-10-23');


--
-- Name: gravacoes_20261023; Type: TABLE ATTACH; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes ATTACH PARTITION radar.gravacoes_20261023 FOR VALUES FROM ('2026-10-23') TO ('2026-10-24');


--
-- Name: feedback id; Type: DEFAULT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.feedback ALTER COLUMN id SET DEFAULT nextval('radar.feedback_id_seq'::regclass);


--
-- Name: aberturas aberturas_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.aberturas
    ADD CONSTRAINT aberturas_pkey PRIMARY KEY (id);


--
-- Name: chaves_servidor chaves_servidor_hash_key; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.chaves_servidor
    ADD CONSTRAINT chaves_servidor_hash_key UNIQUE (hash);


--
-- Name: chaves_servidor chaves_servidor_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.chaves_servidor
    ADD CONSTRAINT chaves_servidor_pkey PRIMARY KEY (id);


--
-- Name: envios envios_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.envios
    ADD CONSTRAINT envios_pkey PRIMARY KEY (id);


--
-- Name: exclusoes exclusoes_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.exclusoes
    ADD CONSTRAINT exclusoes_pkey PRIMARY KEY (id);


--
-- Name: exportacoes exportacoes_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.exportacoes
    ADD CONSTRAINT exportacoes_pkey PRIMARY KEY (id);


--
-- Name: grupo_cache grupo_cache_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.grupo_cache
    ADD CONSTRAINT grupo_cache_pkey PRIMARY KEY (pessoa);


--
-- Name: grupo_eventos grupo_eventos_assinatura_key; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.grupo_eventos
    ADD CONSTRAINT grupo_eventos_assinatura_key UNIQUE (assinatura);


--
-- Name: grupo_eventos grupo_eventos_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.grupo_eventos
    ADD CONSTRAINT grupo_eventos_pkey PRIMARY KEY (id);


--
-- Name: leituras_porta leituras_porta_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.leituras_porta
    ADD CONSTRAINT leituras_porta_pkey PRIMARY KEY (id);


--
-- Name: parametros parametros_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.parametros
    ADD CONSTRAINT parametros_pkey PRIMARY KEY (chave);


--
-- Name: pessoas pessoas_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.pessoas
    ADD CONSTRAINT pessoas_pkey PRIMARY KEY (id);


--
-- Name: pessoas pessoas_projeto_email_key; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.pessoas
    ADD CONSTRAINT pessoas_projeto_email_key UNIQUE (projeto, email);


--
-- Name: reenvios reenvios_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.reenvios
    ADD CONSTRAINT reenvios_pkey PRIMARY KEY (id);


--
-- Name: sendflow_campanhas sendflow_campanhas_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_campanhas
    ADD CONSTRAINT sendflow_campanhas_pkey PRIMARY KEY (release);


--
-- Name: sendflow_chaves sendflow_chaves_hash_key; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_chaves
    ADD CONSTRAINT sendflow_chaves_hash_key UNIQUE (hash);


--
-- Name: sendflow_chaves sendflow_chaves_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_chaves
    ADD CONSTRAINT sendflow_chaves_pkey PRIMARY KEY (id);


--
-- Name: sendflow_grupos sendflow_grupos_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_grupos
    ADD CONSTRAINT sendflow_grupos_pkey PRIMARY KEY (jid);


--
-- Name: sendflow_log sendflow_log_pkey; Type: CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_log
    ADD CONSTRAINT sendflow_log_pkey PRIMARY KEY (id);


--
-- Name: achados_dia achados_dia_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados_dia
    ADD CONSTRAINT achados_dia_pkey PRIMARY KEY (projeto, dia, chave);


--
-- Name: achados achados_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados
    ADD CONSTRAINT achados_pkey PRIMARY KEY (projeto, chave);


--
-- Name: achados_registros achados_registros_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados_registros
    ADD CONSTRAINT achados_registros_pkey PRIMARY KEY (projeto, dia);


--
-- Name: active_catalogo active_catalogo_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.active_catalogo
    ADD CONSTRAINT active_catalogo_pkey PRIMARY KEY (tipo, id);


--
-- Name: apelidos apelidos_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.apelidos
    ADD CONSTRAINT apelidos_pkey PRIMARY KEY (projeto, tipo, valor);


--
-- Name: captacao captacao_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.captacao
    ADD CONSTRAINT captacao_pkey PRIMARY KEY (projeto, pagina);


--
-- Name: chaves chaves_hash_key; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves
    ADD CONSTRAINT chaves_hash_key UNIQUE (hash);


--
-- Name: chaves chaves_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves
    ADD CONSTRAINT chaves_pkey PRIMARY KEY (id);


--
-- Name: chaves_ritmo chaves_ritmo_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves_ritmo
    ADD CONSTRAINT chaves_ritmo_pkey PRIMARY KEY (chave, minuto);


--
-- Name: chaves_uso chaves_uso_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves_uso
    ADD CONSTRAINT chaves_uso_pkey PRIMARY KEY (chave, dia, rota);


--
-- Name: cliques cliques_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques
    ADD CONSTRAINT cliques_pkey PRIMARY KEY (dia, id);


--
-- Name: cliques_202608 cliques_202608_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques_202608
    ADD CONSTRAINT cliques_202608_pkey PRIMARY KEY (dia, id);


--
-- Name: cliques_202609 cliques_202609_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques_202609
    ADD CONSTRAINT cliques_202609_pkey PRIMARY KEY (dia, id);


--
-- Name: cliques_202610 cliques_202610_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques_202610
    ADD CONSTRAINT cliques_202610_pkey PRIMARY KEY (dia, id);


--
-- Name: cliques_202611 cliques_202611_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.cliques_202611
    ADD CONSTRAINT cliques_202611_pkey PRIMARY KEY (dia, id);


--
-- Name: config config_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.config
    ADD CONSTRAINT config_pkey PRIMARY KEY (chave);


--
-- Name: diarios diarios_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.diarios
    ADD CONSTRAINT diarios_pkey PRIMARY KEY (projeto, dia);


--
-- Name: erros erros_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.erros
    ADD CONSTRAINT erros_pkey PRIMARY KEY (id);


--
-- Name: espaco_diario espaco_diario_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.espaco_diario
    ADD CONSTRAINT espaco_diario_pkey PRIMARY KEY (dia);


--
-- Name: eventos_funil eventos_funil_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.eventos_funil
    ADD CONSTRAINT eventos_funil_pkey PRIMARY KEY (id);


--
-- Name: falhas falhas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.falhas
    ADD CONSTRAINT falhas_pkey PRIMARY KEY (id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: funcoes funcoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.funcoes
    ADD CONSTRAINT funcoes_pkey PRIMARY KEY (id);


--
-- Name: gravacoes gravacoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes
    ADD CONSTRAINT gravacoes_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261013 gravacoes_20261013_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261013
    ADD CONSTRAINT gravacoes_20261013_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261014 gravacoes_20261014_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261014
    ADD CONSTRAINT gravacoes_20261014_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261015 gravacoes_20261015_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261015
    ADD CONSTRAINT gravacoes_20261015_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261016 gravacoes_20261016_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261016
    ADD CONSTRAINT gravacoes_20261016_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261017 gravacoes_20261017_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261017
    ADD CONSTRAINT gravacoes_20261017_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261018 gravacoes_20261018_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261018
    ADD CONSTRAINT gravacoes_20261018_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261019 gravacoes_20261019_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261019
    ADD CONSTRAINT gravacoes_20261019_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261020 gravacoes_20261020_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261020
    ADD CONSTRAINT gravacoes_20261020_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261021 gravacoes_20261021_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261021
    ADD CONSTRAINT gravacoes_20261021_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261022 gravacoes_20261022_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261022
    ADD CONSTRAINT gravacoes_20261022_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_20261023 gravacoes_20261023_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_20261023
    ADD CONSTRAINT gravacoes_20261023_pkey PRIMARY KEY (dia, sessao, visualizacao, seq);


--
-- Name: gravacoes_excluidas gravacoes_excluidas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_excluidas
    ADD CONSTRAINT gravacoes_excluidas_pkey PRIMARY KEY (id);


--
-- Name: gravacoes_guardadas gravacoes_guardadas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_guardadas
    ADD CONSTRAINT gravacoes_guardadas_pkey PRIMARY KEY (sessao, visualizacao, seq);


--
-- Name: guardadas guardadas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.guardadas
    ADD CONSTRAINT guardadas_pkey PRIMARY KEY (sessao);


--
-- Name: integracoes integracoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.integracoes
    ADD CONSTRAINT integracoes_pkey PRIMARY KEY (id);


--
-- Name: integracoes_registro integracoes_registro_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.integracoes_registro
    ADD CONSTRAINT integracoes_registro_pkey PRIMARY KEY (id);


--
-- Name: membros membros_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.membros
    ADD CONSTRAINT membros_pkey PRIMARY KEY (usuario);


--
-- Name: meta_anuncios_dia meta_anuncios_dia_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.meta_anuncios_dia
    ADD CONSTRAINT meta_anuncios_dia_pkey PRIMARY KEY (projeto, dia, anuncio_id);


--
-- Name: meta_rodadas meta_rodadas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.meta_rodadas
    ADD CONSTRAINT meta_rodadas_pkey PRIMARY KEY (id);


--
-- Name: migracoes migracoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.migracoes
    ADD CONSTRAINT migracoes_pkey PRIMARY KEY (arquivo);


--
-- Name: pacotes pacotes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.pacotes
    ADD CONSTRAINT pacotes_pkey PRIMARY KEY (visualizacao, seq);


--
-- Name: paginas_mapa paginas_mapa_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.paginas_mapa
    ADD CONSTRAINT paginas_mapa_pkey PRIMARY KEY (projeto, pagina);


--
-- Name: projetos projetos_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.projetos
    ADD CONSTRAINT projetos_pkey PRIMARY KEY (id);


--
-- Name: publicacoes publicacoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.publicacoes
    ADD CONSTRAINT publicacoes_pkey PRIMARY KEY (id);


--
-- Name: publicacoes publicacoes_projeto_pagina_quando_key; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.publicacoes
    ADD CONSTRAINT publicacoes_projeto_pagina_quando_key UNIQUE (projeto, pagina, quando);


--
-- Name: recusas recusas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.recusas
    ADD CONSTRAINT recusas_pkey PRIMARY KEY (dia, motivo, detalhe);


--
-- Name: redes_internas redes_internas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.redes_internas
    ADD CONSTRAINT redes_internas_pkey PRIMARY KEY (id);


--
-- Name: redes_internas redes_internas_rede_key; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.redes_internas
    ADD CONSTRAINT redes_internas_rede_key UNIQUE (rede);


--
-- Name: sessoes sessoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.sessoes
    ADD CONSTRAINT sessoes_pkey PRIMARY KEY (id);


--
-- Name: split_entregas split_entregas_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.split_entregas
    ADD CONSTRAINT split_entregas_pkey PRIMARY KEY (teste, versao, dia, hora);


--
-- Name: tempos_api tempos_api_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.tempos_api
    ADD CONSTRAINT tempos_api_pkey PRIMARY KEY (dia, rota, origem);


--
-- Name: testes testes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.testes
    ADD CONSTRAINT testes_pkey PRIMARY KEY (id);


--
-- Name: velocidade_lab velocidade_lab_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.velocidade_lab
    ADD CONSTRAINT velocidade_lab_pkey PRIMARY KEY (id);


--
-- Name: visitantes_internos visitantes_internos_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.visitantes_internos
    ADD CONSTRAINT visitantes_internos_pkey PRIMARY KEY (projeto, visitante);


--
-- Name: visitantes visitantes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.visitantes
    ADD CONSTRAINT visitantes_pkey PRIMARY KEY (projeto, id);


--
-- Name: visualizacoes visualizacoes_pkey; Type: CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.visualizacoes
    ADD CONSTRAINT visualizacoes_pkey PRIMARY KEY (id);


--
-- Name: aberturas_quando; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX aberturas_quando ON radar_crm.aberturas USING btree (quando);


--
-- Name: envios_active_falhou; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX envios_active_falhou ON radar_crm.envios USING btree (projeto, quando) WHERE ((active ->> 'situacao'::text) = ANY (ARRAY['erro'::text, 'nao_encontrado'::text]));


--
-- Name: envios_pessoa; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX envios_pessoa ON radar_crm.envios USING btree (pessoa, quando);


--
-- Name: envios_quando; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX envios_quando ON radar_crm.envios USING btree (projeto, quando);


--
-- Name: envios_sessao; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX envios_sessao ON radar_crm.envios USING btree (sessao) WHERE (sessao <> ''::text);


--
-- Name: exportacoes_quando; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX exportacoes_quando ON radar_crm.exportacoes USING btree (quando DESC);


--
-- Name: grupo_cache_projeto; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX grupo_cache_projeto ON radar_crm.grupo_cache USING btree (projeto);


--
-- Name: grupo_eventos_dia; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX grupo_eventos_dia ON radar_crm.grupo_eventos USING btree (projeto, quando);


--
-- Name: grupo_eventos_tel; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX grupo_eventos_tel ON radar_crm.grupo_eventos USING btree (projeto, telefone_chave, quando);


--
-- Name: leituras_porta_quando; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX leituras_porta_quando ON radar_crm.leituras_porta USING btree (quando);


--
-- Name: pessoas_primeiro; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX pessoas_primeiro ON radar_crm.pessoas USING btree (projeto, primeiro_em DESC);


--
-- Name: pessoas_telefone_chave; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX pessoas_telefone_chave ON radar_crm.pessoas USING btree (projeto, radar_crm.telefone_chave(telefone)) WHERE (telefone <> ''::text);


--
-- Name: pessoas_visitante; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX pessoas_visitante ON radar_crm.pessoas USING btree (visitante) WHERE (visitante <> ''::text);


--
-- Name: reenvios_envio; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX reenvios_envio ON radar_crm.reenvios USING btree (envio);


--
-- Name: reenvios_fila; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX reenvios_fila ON radar_crm.reenvios USING btree (proxima_em) WHERE (situacao = 'pendente'::text);


--
-- Name: reenvios_projeto; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX reenvios_projeto ON radar_crm.reenvios USING btree (projeto, pedido_em DESC);


--
-- Name: reenvios_um_pendente; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE UNIQUE INDEX reenvios_um_pendente ON radar_crm.reenvios USING btree (envio) WHERE (situacao = 'pendente'::text);


--
-- Name: sendflow_log_quando; Type: INDEX; Schema: radar_crm; Owner: -
--

CREATE INDEX sendflow_log_quando ON radar_crm.sendflow_log USING btree (recebido_em);


--
-- Name: chaves_dono; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX chaves_dono ON radar.chaves USING btree (dono) WHERE (dono IS NOT NULL);


--
-- Name: cliques_mapa; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_mapa ON ONLY radar.cliques USING btree (projeto, pagina, dispositivo, dia);


--
-- Name: cliques_202608_projeto_pagina_dispositivo_dia_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202608_projeto_pagina_dispositivo_dia_idx ON radar.cliques_202608 USING btree (projeto, pagina, dispositivo, dia);


--
-- Name: cliques_sessao; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_sessao ON ONLY radar.cliques USING btree (sessao);


--
-- Name: cliques_202608_sessao_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202608_sessao_idx ON radar.cliques_202608 USING btree (sessao);


--
-- Name: cliques_202609_projeto_pagina_dispositivo_dia_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202609_projeto_pagina_dispositivo_dia_idx ON radar.cliques_202609 USING btree (projeto, pagina, dispositivo, dia);


--
-- Name: cliques_202609_sessao_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202609_sessao_idx ON radar.cliques_202609 USING btree (sessao);


--
-- Name: cliques_202610_projeto_pagina_dispositivo_dia_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202610_projeto_pagina_dispositivo_dia_idx ON radar.cliques_202610 USING btree (projeto, pagina, dispositivo, dia);


--
-- Name: cliques_202610_sessao_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202610_sessao_idx ON radar.cliques_202610 USING btree (sessao);


--
-- Name: cliques_202611_projeto_pagina_dispositivo_dia_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202611_projeto_pagina_dispositivo_dia_idx ON radar.cliques_202611 USING btree (projeto, pagina, dispositivo, dia);


--
-- Name: cliques_202611_sessao_idx; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX cliques_202611_sessao_idx ON radar.cliques_202611 USING btree (sessao);


--
-- Name: erros_projeto_dia; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX erros_projeto_dia ON radar.erros USING btree (projeto, dia);


--
-- Name: erros_sessao; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX erros_sessao ON radar.erros USING btree (sessao);


--
-- Name: eventos_funil_nome; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX eventos_funil_nome ON radar.eventos_funil USING btree (projeto, nome, dia);


--
-- Name: eventos_funil_sessao; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX eventos_funil_sessao ON radar.eventos_funil USING btree (sessao);


--
-- Name: feedback_quando; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX feedback_quando ON radar.feedback USING btree (quando DESC);


--
-- Name: feedback_quem; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX feedback_quem ON radar.feedback USING btree (quem, quando DESC);


--
-- Name: gravacoes_excluidas_quando; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX gravacoes_excluidas_quando ON radar.gravacoes_excluidas USING btree (projeto, quando DESC);


--
-- Name: guardadas_projeto; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX guardadas_projeto ON radar.guardadas USING btree (projeto, guardada_em DESC);


--
-- Name: integracoes_registro_quando; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX integracoes_registro_quando ON radar.integracoes_registro USING btree (quando);


--
-- Name: membros_email; Type: INDEX; Schema: radar; Owner: -
--

CREATE UNIQUE INDEX membros_email ON radar.membros USING btree (lower(email));


--
-- Name: meta_rodadas_quando; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX meta_rodadas_quando ON radar.meta_rodadas USING btree (quando);


--
-- Name: pacotes_dia; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX pacotes_dia ON radar.pacotes USING btree (dia);


--
-- Name: sessoes_entrada; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX sessoes_entrada ON radar.sessoes USING btree (projeto, primeira_pagina, dia);


--
-- Name: sessoes_internas; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX sessoes_internas ON radar.sessoes USING btree (dia) WHERE interna;


--
-- Name: sessoes_projeto_dia; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX sessoes_projeto_dia ON radar.sessoes USING btree (projeto, dia);


--
-- Name: sessoes_projeto_inicio; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX sessoes_projeto_inicio ON radar.sessoes USING btree (projeto, inicio DESC);


--
-- Name: sessoes_visitante; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX sessoes_visitante ON radar.sessoes USING btree (projeto, visitante);


--
-- Name: testes_projeto; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX testes_projeto ON radar.testes USING btree (projeto, inicio DESC);


--
-- Name: testes_split_dominio; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX testes_split_dominio ON radar.testes USING btree (dominio_split) WHERE (tipo = 'split'::text);


--
-- Name: testes_split_unico; Type: INDEX; Schema: radar; Owner: -
--

CREATE UNIQUE INDEX testes_split_unico ON radar.testes USING btree (dominio_split, entrada) WHERE ((tipo = 'split'::text) AND (estado = ANY (ARRAY['rodando'::text, 'pausado'::text])));


--
-- Name: velocidade_lab_pagina; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX velocidade_lab_pagina ON radar.velocidade_lab USING btree (projeto, pagina, estrategia, medido_em DESC);


--
-- Name: visualizacoes_pagina; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX visualizacoes_pagina ON radar.visualizacoes USING btree (projeto, pagina, dia);


--
-- Name: visualizacoes_sessao; Type: INDEX; Schema: radar; Owner: -
--

CREATE INDEX visualizacoes_sessao ON radar.visualizacoes USING btree (sessao, ordem);


--
-- Name: cliques_202608_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_pkey ATTACH PARTITION radar.cliques_202608_pkey;


--
-- Name: cliques_202608_projeto_pagina_dispositivo_dia_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_mapa ATTACH PARTITION radar.cliques_202608_projeto_pagina_dispositivo_dia_idx;


--
-- Name: cliques_202608_sessao_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_sessao ATTACH PARTITION radar.cliques_202608_sessao_idx;


--
-- Name: cliques_202609_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_pkey ATTACH PARTITION radar.cliques_202609_pkey;


--
-- Name: cliques_202609_projeto_pagina_dispositivo_dia_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_mapa ATTACH PARTITION radar.cliques_202609_projeto_pagina_dispositivo_dia_idx;


--
-- Name: cliques_202609_sessao_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_sessao ATTACH PARTITION radar.cliques_202609_sessao_idx;


--
-- Name: cliques_202610_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_pkey ATTACH PARTITION radar.cliques_202610_pkey;


--
-- Name: cliques_202610_projeto_pagina_dispositivo_dia_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_mapa ATTACH PARTITION radar.cliques_202610_projeto_pagina_dispositivo_dia_idx;


--
-- Name: cliques_202610_sessao_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_sessao ATTACH PARTITION radar.cliques_202610_sessao_idx;


--
-- Name: cliques_202611_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_pkey ATTACH PARTITION radar.cliques_202611_pkey;


--
-- Name: cliques_202611_projeto_pagina_dispositivo_dia_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_mapa ATTACH PARTITION radar.cliques_202611_projeto_pagina_dispositivo_dia_idx;


--
-- Name: cliques_202611_sessao_idx; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.cliques_sessao ATTACH PARTITION radar.cliques_202611_sessao_idx;


--
-- Name: gravacoes_20261013_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261013_pkey;


--
-- Name: gravacoes_20261014_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261014_pkey;


--
-- Name: gravacoes_20261015_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261015_pkey;


--
-- Name: gravacoes_20261016_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261016_pkey;


--
-- Name: gravacoes_20261017_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261017_pkey;


--
-- Name: gravacoes_20261018_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261018_pkey;


--
-- Name: gravacoes_20261019_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261019_pkey;


--
-- Name: gravacoes_20261020_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261020_pkey;


--
-- Name: gravacoes_20261021_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261021_pkey;


--
-- Name: gravacoes_20261022_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261022_pkey;


--
-- Name: gravacoes_20261023_pkey; Type: INDEX ATTACH; Schema: radar; Owner: -
--

ALTER INDEX radar.gravacoes_pkey ATTACH PARTITION radar.gravacoes_20261023_pkey;


--
-- Name: grupo_eventos grupo_eventos_depois; Type: TRIGGER; Schema: radar_crm; Owner: -
--

CREATE TRIGGER grupo_eventos_depois AFTER INSERT ON radar_crm.grupo_eventos FOR EACH ROW EXECUTE FUNCTION radar_crm.grupo_eventos_depois();


--
-- Name: pessoas pessoas_grupo_novo; Type: TRIGGER; Schema: radar_crm; Owner: -
--

CREATE TRIGGER pessoas_grupo_novo BEFORE INSERT ON radar_crm.pessoas FOR EACH ROW EXECUTE FUNCTION radar_crm.pessoas_grupo();


--
-- Name: pessoas pessoas_grupo_telefone; Type: TRIGGER; Schema: radar_crm; Owner: -
--

CREATE TRIGGER pessoas_grupo_telefone BEFORE UPDATE OF telefone, projeto ON radar_crm.pessoas FOR EACH ROW WHEN (((new.telefone IS DISTINCT FROM old.telefone) OR (new.projeto IS DISTINCT FROM old.projeto))) EXECUTE FUNCTION radar_crm.pessoas_grupo();


--
-- Name: envios envios_pessoa_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.envios
    ADD CONSTRAINT envios_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES radar_crm.pessoas(id) ON DELETE CASCADE;


--
-- Name: grupo_cache grupo_cache_pessoa_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.grupo_cache
    ADD CONSTRAINT grupo_cache_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES radar_crm.pessoas(id) ON DELETE CASCADE;


--
-- Name: grupo_eventos grupo_eventos_projeto_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.grupo_eventos
    ADD CONSTRAINT grupo_eventos_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: pessoas pessoas_projeto_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.pessoas
    ADD CONSTRAINT pessoas_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE RESTRICT;


--
-- Name: reenvios reenvios_envio_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.reenvios
    ADD CONSTRAINT reenvios_envio_fkey FOREIGN KEY (envio) REFERENCES radar_crm.envios(id) ON DELETE CASCADE;


--
-- Name: reenvios reenvios_pessoa_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.reenvios
    ADD CONSTRAINT reenvios_pessoa_fkey FOREIGN KEY (pessoa) REFERENCES radar_crm.pessoas(id) ON DELETE CASCADE;


--
-- Name: sendflow_campanhas sendflow_campanhas_projeto_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_campanhas
    ADD CONSTRAINT sendflow_campanhas_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: sendflow_chaves sendflow_chaves_projeto_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_chaves
    ADD CONSTRAINT sendflow_chaves_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: sendflow_grupos sendflow_grupos_release_fkey; Type: FK CONSTRAINT; Schema: radar_crm; Owner: -
--

ALTER TABLE ONLY radar_crm.sendflow_grupos
    ADD CONSTRAINT sendflow_grupos_release_fkey FOREIGN KEY (release) REFERENCES radar_crm.sendflow_campanhas(release) ON DELETE CASCADE;


--
-- Name: achados_dia achados_dia_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados_dia
    ADD CONSTRAINT achados_dia_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: achados achados_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados
    ADD CONSTRAINT achados_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: achados_registros achados_registros_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.achados_registros
    ADD CONSTRAINT achados_registros_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: apelidos apelidos_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.apelidos
    ADD CONSTRAINT apelidos_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: captacao captacao_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.captacao
    ADD CONSTRAINT captacao_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: chaves chaves_dono_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves
    ADD CONSTRAINT chaves_dono_fkey FOREIGN KEY (dono) REFERENCES radar.membros(usuario) ON DELETE SET NULL;


--
-- Name: chaves_ritmo chaves_ritmo_chave_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves_ritmo
    ADD CONSTRAINT chaves_ritmo_chave_fkey FOREIGN KEY (chave) REFERENCES radar.chaves(id) ON DELETE CASCADE;


--
-- Name: chaves_uso chaves_uso_chave_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.chaves_uso
    ADD CONSTRAINT chaves_uso_chave_fkey FOREIGN KEY (chave) REFERENCES radar.chaves(id) ON DELETE CASCADE;


--
-- Name: cliques cliques_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE radar.cliques
    ADD CONSTRAINT cliques_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.sessoes(id) ON DELETE CASCADE;


--
-- Name: diarios diarios_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.diarios
    ADD CONSTRAINT diarios_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: erros erros_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.erros
    ADD CONSTRAINT erros_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.sessoes(id) ON DELETE CASCADE;


--
-- Name: eventos_funil eventos_funil_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.eventos_funil
    ADD CONSTRAINT eventos_funil_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.sessoes(id) ON DELETE CASCADE;


--
-- Name: gravacoes_guardadas gravacoes_guardadas_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.gravacoes_guardadas
    ADD CONSTRAINT gravacoes_guardadas_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.guardadas(sessao) ON DELETE CASCADE;


--
-- Name: guardadas guardadas_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.guardadas
    ADD CONSTRAINT guardadas_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: guardadas guardadas_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.guardadas
    ADD CONSTRAINT guardadas_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.sessoes(id) ON DELETE CASCADE;


--
-- Name: membros membros_usuario_fk; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.membros
    ADD CONSTRAINT membros_usuario_fk FOREIGN KEY (usuario) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: meta_anuncios_dia meta_anuncios_dia_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.meta_anuncios_dia
    ADD CONSTRAINT meta_anuncios_dia_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: paginas_mapa paginas_mapa_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.paginas_mapa
    ADD CONSTRAINT paginas_mapa_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: publicacoes publicacoes_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.publicacoes
    ADD CONSTRAINT publicacoes_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: sessoes sessoes_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.sessoes
    ADD CONSTRAINT sessoes_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: split_entregas split_entregas_teste_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.split_entregas
    ADD CONSTRAINT split_entregas_teste_fkey FOREIGN KEY (teste) REFERENCES radar.testes(id) ON DELETE CASCADE;


--
-- Name: testes testes_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.testes
    ADD CONSTRAINT testes_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: velocidade_lab velocidade_lab_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.velocidade_lab
    ADD CONSTRAINT velocidade_lab_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: visitantes visitantes_projeto_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.visitantes
    ADD CONSTRAINT visitantes_projeto_fkey FOREIGN KEY (projeto) REFERENCES radar.projetos(id) ON DELETE CASCADE;


--
-- Name: visualizacoes visualizacoes_sessao_fkey; Type: FK CONSTRAINT; Schema: radar; Owner: -
--

ALTER TABLE ONLY radar.visualizacoes
    ADD CONSTRAINT visualizacoes_sessao_fkey FOREIGN KEY (sessao) REFERENCES radar.sessoes(id) ON DELETE CASCADE;


--
-- Name: aberturas; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.aberturas ENABLE ROW LEVEL SECURITY;

--
-- Name: chaves_servidor; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.chaves_servidor ENABLE ROW LEVEL SECURITY;

--
-- Name: envios; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.envios ENABLE ROW LEVEL SECURITY;

--
-- Name: exclusoes; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.exclusoes ENABLE ROW LEVEL SECURITY;

--
-- Name: exportacoes; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.exportacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: grupo_cache; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.grupo_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: grupo_eventos; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.grupo_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: leituras_porta; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.leituras_porta ENABLE ROW LEVEL SECURITY;

--
-- Name: parametros; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.parametros ENABLE ROW LEVEL SECURITY;

--
-- Name: pessoas; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.pessoas ENABLE ROW LEVEL SECURITY;

--
-- Name: reenvios; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.reenvios ENABLE ROW LEVEL SECURITY;

--
-- Name: sendflow_campanhas; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_campanhas ENABLE ROW LEVEL SECURITY;

--
-- Name: sendflow_chaves; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_chaves ENABLE ROW LEVEL SECURITY;

--
-- Name: sendflow_grupos; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_grupos ENABLE ROW LEVEL SECURITY;

--
-- Name: sendflow_log; Type: ROW SECURITY; Schema: radar_crm; Owner: -
--

ALTER TABLE radar_crm.sendflow_log ENABLE ROW LEVEL SECURITY;

--
-- Name: achados; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.achados ENABLE ROW LEVEL SECURITY;

--
-- Name: achados_dia; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.achados_dia ENABLE ROW LEVEL SECURITY;

--
-- Name: achados_registros; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.achados_registros ENABLE ROW LEVEL SECURITY;

--
-- Name: active_catalogo; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.active_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: apelidos; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.apelidos ENABLE ROW LEVEL SECURITY;

--
-- Name: captacao; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.captacao ENABLE ROW LEVEL SECURITY;

--
-- Name: chaves; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.chaves ENABLE ROW LEVEL SECURITY;

--
-- Name: chaves_ritmo; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.chaves_ritmo ENABLE ROW LEVEL SECURITY;

--
-- Name: chaves_uso; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.chaves_uso ENABLE ROW LEVEL SECURITY;

--
-- Name: cliques; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.cliques ENABLE ROW LEVEL SECURITY;

--
-- Name: config; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.config ENABLE ROW LEVEL SECURITY;

--
-- Name: diarios; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.diarios ENABLE ROW LEVEL SECURITY;

--
-- Name: erros; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.erros ENABLE ROW LEVEL SECURITY;

--
-- Name: espaco_diario; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.espaco_diario ENABLE ROW LEVEL SECURITY;

--
-- Name: eventos_funil; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.eventos_funil ENABLE ROW LEVEL SECURITY;

--
-- Name: falhas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.falhas ENABLE ROW LEVEL SECURITY;

--
-- Name: feedback; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.feedback ENABLE ROW LEVEL SECURITY;

--
-- Name: funcoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.funcoes ENABLE ROW LEVEL SECURITY;

--
-- Name: gravacoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.gravacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: gravacoes_excluidas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.gravacoes_excluidas ENABLE ROW LEVEL SECURITY;

--
-- Name: gravacoes_guardadas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.gravacoes_guardadas ENABLE ROW LEVEL SECURITY;

--
-- Name: guardadas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.guardadas ENABLE ROW LEVEL SECURITY;

--
-- Name: integracoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.integracoes ENABLE ROW LEVEL SECURITY;

--
-- Name: integracoes_registro; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.integracoes_registro ENABLE ROW LEVEL SECURITY;

--
-- Name: membros; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.membros ENABLE ROW LEVEL SECURITY;

--
-- Name: meta_anuncios_dia; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.meta_anuncios_dia ENABLE ROW LEVEL SECURITY;

--
-- Name: meta_rodadas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.meta_rodadas ENABLE ROW LEVEL SECURITY;

--
-- Name: migracoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.migracoes ENABLE ROW LEVEL SECURITY;

--
-- Name: pacotes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.pacotes ENABLE ROW LEVEL SECURITY;

--
-- Name: paginas_mapa; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.paginas_mapa ENABLE ROW LEVEL SECURITY;

--
-- Name: projetos; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.projetos ENABLE ROW LEVEL SECURITY;

--
-- Name: publicacoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.publicacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: recusas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.recusas ENABLE ROW LEVEL SECURITY;

--
-- Name: redes_internas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.redes_internas ENABLE ROW LEVEL SECURITY;

--
-- Name: sessoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.sessoes ENABLE ROW LEVEL SECURITY;

--
-- Name: split_entregas; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.split_entregas ENABLE ROW LEVEL SECURITY;

--
-- Name: tempos_api; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.tempos_api ENABLE ROW LEVEL SECURITY;

--
-- Name: testes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.testes ENABLE ROW LEVEL SECURITY;

--
-- Name: velocidade_lab; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.velocidade_lab ENABLE ROW LEVEL SECURITY;

--
-- Name: visitantes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.visitantes ENABLE ROW LEVEL SECURITY;

--
-- Name: visitantes_internos; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.visitantes_internos ENABLE ROW LEVEL SECURITY;

--
-- Name: visualizacoes; Type: ROW SECURITY; Schema: radar; Owner: -
--

ALTER TABLE radar.visualizacoes ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--



--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--




--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--




--
-- Name: crm_receber(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_crm_receber(p_chave text, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  k radar_crm.chaves_servidor;
  v_res jsonb := '[]'::jsonb;
  item jsonb;
begin
  select * into k from radar_crm.chaves_servidor
  where hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') and revogada_em is null;
  if k.id is null then raise exception 'sem_acesso' using errcode = '42501'; end if;
  update radar_crm.chaves_servidor set ultimo_uso = now(), usos = usos + 1 where id = k.id;
  if jsonb_typeof(p) = 'array' then
    if jsonb_array_length(p) > 200 then return jsonb_build_object('ok', false, 'erro', 'lote_grande'); end if;
    for item in select * from jsonb_array_elements(p) loop
      v_res := v_res || jsonb_build_array(radar_crm.guardar_envio(item, k.projetos));
    end loop;
    return jsonb_build_object('ok', true, 'lote', v_res);
  end if;
  if jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'vazio'); end if;
  return radar_crm.guardar_envio(p, k.projetos);
end $$;


--
-- Name: radar_acessos(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_acessos(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'extensions'
    AS $_$
declare
  eu radar.membros := radar.membro_atual();
  v_id uuid;
  v_alvo uuid := case when coalesce(p ->> 'usuario', '') ~ '^[0-9a-f-]{36}$' then (p ->> 'usuario')::uuid end;
  v_papel text := case when p ->> 'papel' in ('admin', 'equipe', 'leitor') then p ->> 'papel' end;
  v_projetos text[] := case when jsonb_typeof(p -> 'projetos') = 'array'
                            then array(select jsonb_array_elements_text(p -> 'projetos')) end;
  v_nivel text := case when p ->> 'nivel' in ('agregado', 'sessoes') then p ->> 'nivel' end;
  v_funcao text := case when exists (select 1 from radar.funcoes fx where fx.id = p ->> 'funcao') then p ->> 'funcao' end;
  v_areas text[] := case when jsonb_typeof(p -> 'areas') = 'array'
                         then array(select distinct x from jsonb_array_elements_text(p -> 'areas') x) end;
  v_admins int;
  alvo radar.membros;
  v_novo_papel text;
  v_nova_funcao text;
  v_novas_areas text[];
begin
  if eu.usuario is null or eu.papel <> 'admin' then
    raise exception 'sem_acesso' using errcode = '42501';
  end if;

  -- 045: as funcoes, com as areas que cada uma traz marcadas
  if p_acao = 'funcoes' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', fx.id, 'nome', fx.nome, 'areas', to_jsonb(fx.areas)) order by fx.ordem)
                     from radar.funcoes fx), '[]'::jsonb);
  end if;

  if p_acao = 'listar' then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
               'usuario', u.id, 'email', u.email, 'nome', coalesce(m.nome, u.raw_user_meta_data ->> 'nome', ''),
               'papel', m.papel, 'projetos', to_jsonb(coalesce(m.projetos, '{}')), 'nivel', coalesce(m.nivel, 'agregado'),
               -- 045: a funcao, as areas marcadas, a chave do Claude da pessoa e o que ela abriu no CRM nos ultimos 7 dias
               'funcao', m.funcao, 'areas', to_jsonb(coalesce(m.areas, '{}')),
               'chave', (select jsonb_build_object('id', c.id, 'prefixo', c.prefixo, 'criada_em', radar.ms(c.criada_em),
                                                   'expira_em', radar.ms(c.expira_em), 'ultimo_uso', radar.ms(c.ultimo_uso))
                         from radar.chaves c
                         where c.dono = u.id and c.pessoal and c.revogada_em is null and (c.expira_em is null or c.expira_em > now())
                         order by c.criada_em desc limit 1),
               'crm_7d', jsonb_build_object(
                 'fichas', (select count(*) from radar_crm.aberturas a where a.quem = u.id and a.acao = 'ficha' and a.quando >= now() - interval '7 days'),
                 'exportacoes', (select count(*) from radar_crm.exportacoes e where e.quem = u.id and e.quando >= now() - interval '7 days')),
               'ativo', coalesce(m.ativo, false),
               'membro', m.usuario is not null, 'criado_em', u.created_at, 'ultimo_acesso', u.last_sign_in_at,
               'bloqueado', u.banned_until is not null and u.banned_until > now(), 'eu', u.id = eu.usuario)
             order by (m.usuario is null), m.papel, lower(coalesce(m.nome, u.email)))
      from auth.users u left join radar.membros m on m.usuario = u.id
      where u.deleted_at is null), '[]'::jsonb);
  end if;

  -- 033: projeto marcado tem de existir; 045: area e funcao tambem
  if exists (select 1 from unnest(coalesce(v_projetos, '{}')) x where not exists (select 1 from radar.projetos pr where pr.id = x)) then
    return jsonb_build_object('ok', false, 'erro', 'projeto_desconhecido');
  end if;
  if exists (select 1 from unnest(coalesce(v_areas, '{}')) x where not (x = any (radar.todas_as_areas()))) then
    return jsonb_build_object('ok', false, 'erro', 'area_desconhecida');
  end if;
  if coalesce(p ->> 'funcao', '') <> '' and v_funcao is null then
    return jsonb_build_object('ok', false, 'erro', 'funcao_desconhecida');
  end if;

  if p_acao = 'criar' then
    -- 033: leitor so ve os projetos marcados; 045: a equipe tambem, e com a funcao escolhida
    if coalesce(v_papel, 'leitor') <> 'admin' and cardinality(coalesce(v_projetos, '{}')) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'leitor_sem_projeto');
    end if;
    if v_papel = 'equipe' and v_funcao is null then return jsonb_build_object('ok', false, 'erro', 'sem_funcao'); end if;
    begin
      v_id := radar.criar_usuario(p ->> 'email', p ->> 'senha', p ->> 'nome');
    exception when raise_exception then
      return jsonb_build_object('ok', false, 'erro', sqlerrm);
    end;
    insert into radar.membros (usuario, nome, email, papel, projetos, nivel, ativo, criado_por, funcao, areas)
    values (v_id, coalesce(nullif(trim(p ->> 'nome'), ''), split_part(lower(trim(p ->> 'email')), '@', 1)),
            lower(trim(p ->> 'email')), coalesce(v_papel, 'leitor'), coalesce(v_projetos, '{}'), coalesce(v_nivel, 'agregado'), true, eu.usuario,
            case when v_papel = 'equipe' then v_funcao end,
            case when v_papel = 'equipe' then coalesce(v_areas, (select fx.areas from radar.funcoes fx where fx.id = v_funcao)) else '{}' end);
    return jsonb_build_object('ok', true, 'usuario', v_id);
  end if;

  if v_alvo is null or not exists (select 1 from auth.users where id = v_alvo) then
    return jsonb_build_object('ok', false, 'erro', 'usuario_nao_existe');
  end if;
  select * into alvo from radar.membros where usuario = v_alvo;
  select count(*) into v_admins from radar.membros where papel = 'admin' and ativo;

  if p_acao = 'senha' then
    begin
      perform radar.trocar_senha(v_alvo, p ->> 'senha');
    exception when raise_exception then
      return jsonb_build_object('ok', false, 'erro', sqlerrm);
    end;
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'dar_acesso' then
    if coalesce(v_papel, 'leitor') <> 'admin' and cardinality(coalesce(v_projetos, '{}')) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'leitor_sem_projeto');
    end if;
    if v_papel = 'equipe' and v_funcao is null then return jsonb_build_object('ok', false, 'erro', 'sem_funcao'); end if;
    insert into radar.membros (usuario, nome, email, papel, projetos, nivel, ativo, criado_por, funcao, areas)
    select u.id, coalesce(nullif(trim(p ->> 'nome'), ''), u.raw_user_meta_data ->> 'nome', split_part(u.email, '@', 1)), lower(u.email),
           coalesce(v_papel, 'leitor'), coalesce(v_projetos, '{}'), coalesce(v_nivel, 'agregado'), true, eu.usuario,
           case when v_papel = 'equipe' then v_funcao end,
           case when v_papel = 'equipe' then coalesce(v_areas, (select fx.areas from radar.funcoes fx where fx.id = v_funcao)) else '{}' end
    from auth.users u where u.id = v_alvo
    on conflict (usuario) do update set papel = excluded.papel, projetos = excluded.projetos, nivel = excluded.nivel,
      funcao = excluded.funcao, areas = excluded.areas, ativo = true, atualizado_em = now();
    update auth.users set banned_until = null, email_confirmed_at = coalesce(email_confirmed_at, now()) where id = v_alvo;
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'atualizar' then
    if alvo.usuario is null then return jsonb_build_object('ok', false, 'erro', 'sem_acesso_ainda'); end if;
    if v_alvo = eu.usuario and ((v_papel is not null and v_papel <> 'admin') or (p ? 'ativo' and not radar.sim(p ->> 'ativo'))) then
      return jsonb_build_object('ok', false, 'erro', 'nao_pode_si_mesmo');
    end if;
    if alvo.papel = 'admin' and alvo.ativo and v_admins <= 1
       and ((v_papel is not null and v_papel <> 'admin') or (p ? 'ativo' and not radar.sim(p ->> 'ativo'))) then
      return jsonb_build_object('ok', false, 'erro', 'ultimo_admin');
    end if;
    v_novo_papel := coalesce(v_papel, alvo.papel);
    -- 045: na equipe, a funcao (a nova ou a de antes) e as areas (as pedidas; trocando de funcao sem dizer as areas, as da
    -- funcao nova); fora da equipe, sem funcao e sem areas
    if v_novo_papel = 'equipe' then
      v_nova_funcao := coalesce(v_funcao, alvo.funcao);
      if v_nova_funcao is null then return jsonb_build_object('ok', false, 'erro', 'sem_funcao'); end if;
      v_novas_areas := coalesce(v_areas, case when alvo.papel = 'equipe' and v_nova_funcao = alvo.funcao then alvo.areas
                                              else (select fx.areas from radar.funcoes fx where fx.id = v_nova_funcao) end);
    else
      v_nova_funcao := null;
      v_novas_areas := '{}';
    end if;
    -- 033: so confere quando muda o papel ou os projetos (desativar um leitor antigo sem projeto continua valendo)
    if (v_papel is not null or v_projetos is not null)
       and v_novo_papel <> 'admin' and cardinality(coalesce(v_projetos, alvo.projetos, '{}')) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'leitor_sem_projeto');
    end if;
    update radar.membros set
      nome = coalesce(nullif(trim(p ->> 'nome'), ''), nome),
      papel = v_novo_papel,
      projetos = coalesce(v_projetos, projetos),
      nivel = coalesce(v_nivel, nivel),
      funcao = v_nova_funcao,
      areas = v_novas_areas,
      ativo = case when p ? 'ativo' then radar.sim(p ->> 'ativo') else ativo end,
      atualizado_em = now()
    where usuario = v_alvo
    returning * into alvo;
    -- desativado nao entra (o login fica bloqueado e as sessoes caem); reativado volta a entrar
    if alvo.ativo then
      update auth.users set banned_until = null where id = v_alvo;
    else
      update auth.users set banned_until = now() + interval '100 years' where id = v_alvo;
      delete from auth.sessions where user_id = v_alvo;
      -- 045: e a chave do Claude dele para de valer
      update radar.chaves set revogada_em = now() where dono = v_alvo and pessoal and revogada_em is null;
    end if;
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'remover' then
    if v_alvo = eu.usuario then return jsonb_build_object('ok', false, 'erro', 'nao_pode_si_mesmo'); end if;
    if alvo.papel = 'admin' and alvo.ativo and v_admins <= 1 then
      return jsonb_build_object('ok', false, 'erro', 'ultimo_admin');
    end if;
    -- 045: a chave do Claude da pessoa sai junto
    update radar.chaves set revogada_em = now() where dono = v_alvo and pessoal and revogada_em is null;
    delete from auth.users where id = v_alvo;
    return jsonb_build_object('ok', true);
  end if;

  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $_$;


--
-- Name: radar_api(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_api(rota text, f jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET work_mem TO '8MB'
    AS $_$
declare
  m radar.membros := radar.membro_atual();
  v_proj text;
  v_ini timestamptz := clock_timestamp();
  v_res jsonb;
begin
  if m.usuario is null then raise exception 'sem_acesso' using errcode = '42501'; end if;
  f := coalesce(f, '{}'::jsonb);
  -- 045: o que nao esta marcado para a pessoa, o banco recusa (o administrador ve todas as areas)
  if not radar.ve_alguma(m, radar.areas_da_rota(rota)) then raise exception 'sem_acesso' using errcode = '42501'; end if;
  if rota = 'projetos' then return radar.api_projetos(m.papel = 'admin', m.projetos); end if;
  -- 046: o catalogo do Active (ids e nomes, de todos os projetos)
  if rota = 'active_catalogo' then return radar.api_active_catalogo(); end if;
  if rota = 'config' then
    return jsonb_build_object(
      'pagespeed_chave', case when m.papel = 'admin' then (select valor from radar.config where chave = 'pagespeed_chave') end,
      'espaco', (select valor::jsonb from radar.config where chave = 'espaco'),
      'espaco_historico', coalesce((
         select jsonb_agg(jsonb_build_object('dia', d.dia::text, 'total_mb', d.total_mb, 'video_mb', d.video_mb) order by d.dia)
         from radar.espaco_diario d where d.dia >= radar.hoje() - 60), '[]'::jsonb));
  end if;
  if rota = 'tempos' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return radar.api_tempos(radar.inteiro(f ->> 'dias', 7)::int);
  end if;
  if rota = 'salvar_config' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    if f ? 'pagespeed_chave' then
      if coalesce(f ->> 'pagespeed_chave', '') = '' then
        delete from radar.config where chave = 'pagespeed_chave';
      else
        insert into radar.config (chave, valor) values ('pagespeed_chave', left(trim(f ->> 'pagespeed_chave'), 200))
        on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
      end if;
    end if;
    if f ? 'coleta_manual' then
      insert into radar.config (chave, valor) values ('coleta_manual', case when f ->> 'coleta_manual' = 'pausada' then 'pausada' else 'ligada' end)
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    end if;
    if coalesce(f ->> 'limite_banco_mb', '') ~ '^[0-9]{3,6}$' then
      insert into radar.config (chave, valor) values ('limite_banco_mb', f ->> 'limite_banco_mb')
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    end if;
    if f ? 'coleta_manual' or f ? 'limite_banco_mb' then perform radar.medir_espaco(); end if;
    return jsonb_build_object('ok', true);
  end if;
  -- 033: no nivel "so numeros", nada de visita uma a uma (conferido antes de procurar a visita)
  if rota in ('sessoes', 'sessao', 'guardadas', 'guardar_gravacao', 'desguardar_gravacao') and not radar.ve_visitas(m) then
    raise exception 'sem_acesso' using errcode = '42501';
  end if;
  -- alertas de todos os funis que a pessoa ve; os avisos do sistema, so para o administrador
  if rota = 'alertas' and coalesce(f ->> 'projeto', '') = '' then
    v_res := radar.alertas_de(array(select p.id from radar.projetos p where radar.pode_ver(m, p.id)), f, m.papel = 'admin');
    perform radar.anotar_tempo('alertas', 'tela', extract(epoch from clock_timestamp() - v_ini) * 1000);
    return v_res;
  end if;
  if rota = 'sessao' then
    select projeto into v_proj from radar.sessoes where id = f ->> 'id';
    if v_proj is null then return null; end if;
  elsif rota = 'gravacao' then
    select projeto into v_proj from radar.sessoes where id = f ->> 'sessao';
    if v_proj is null then return jsonb_build_object('pedacos', '[]'::jsonb); end if;
  elsif rota in ('guardar_gravacao', 'desguardar_gravacao') then
    select projeto into v_proj from radar.sessoes where id = f ->> 'sessao';
    if v_proj is null then return jsonb_build_object('ok', false, 'erro', 'sessao_nao_encontrada'); end if;
  elsif rota = 'relatorio' then
    select projeto into v_proj from radar.velocidade_lab where id = radar.id_lab(f ->> 'id');
    if v_proj is null then return null; end if;
  else
    v_proj := f ->> 'projeto';
  end if;
  if v_proj is null or not radar.pode_ver(m, v_proj) then raise exception 'sem_acesso' using errcode = '42501'; end if;
  -- 033: no nivel "so numeros", a gravacao e so o retrato de uma pagina vista (o fundo do mapa de calor)
  if rota = 'gravacao' and not radar.ve_visitas(m) then
    if coalesce(f ->> 'pv', '') = '' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return radar.api_gravacao_foto(f);
  end if;
  -- 033: teste do Google novo, so o administrador (e quem tem a chave)
  if rota = 'salvar_laboratorio' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return radar.salvar_laboratorio(f, m.usuario);
  end if;
  -- os nomes dos codigos do Meta (026): so o administrador da nome
  if rota = 'salvar_apelido' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return radar.salvar_apelido(f);
  end if;
  -- 062: o que cada pagina capta: ler e da radar.api (quem tem a area de Projetos e instalacao); mudar, so o administrador
  if rota = 'salvar_captacao' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return radar.salvar_captacao(f, m.usuario);
  end if;
  -- 034: guardar o que as regras acharam hoje (a tela, no periodo padrao) e marcar um achado: o administrador
  if rota in ('registrar_achados', 'marcar_achado') then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    if rota = 'registrar_achados' then return radar.salvar_achados(v_proj, radar.hoje(), f -> 'achados', 'tela'); end if;
    return radar.marcar_achado(f, m.usuario);
  end if;
  -- 030: guardar (ou trocar a nota) e tirar uma gravacao: quem ve o projeto da visita (e, desde a 033, abre visita)
  if rota = 'guardar_gravacao' then return radar.guardar_gravacao(f, m.usuario); end if;
  if rota = 'desguardar_gravacao' then
    delete from radar.guardadas where sessao = f ->> 'sessao';
    return jsonb_build_object('ok', true, 'guardadas', (select count(*) from radar.guardadas));
  end if;
  -- os testes: qualquer um que ve o funil acompanha; criar, encerrar e apagar e do administrador
  if rota in ('salvar_teste', 'encerrar_teste', 'remover_teste') then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    if rota = 'salvar_teste' then return radar.salvar_teste(f, m.usuario); end if;
    if rota = 'encerrar_teste' then return radar.encerrar_teste(f); end if;
    return radar.remover_teste(f);
  end if;
  -- 076: o split. Acompanhar e da radar.api (quem tem a area de Melhorias); criar, mudar, ligar, pausar, promover, encerrar e
  -- apagar: o administrador e o web designer (radar.pode_split)
  if rota in ('salvar_split', 'estado_split', 'remover_split') then
    if not radar.pode_split(m) then raise exception 'sem_acesso' using errcode = '42501'; end if;
    if rota = 'salvar_split' then return radar.salvar_split(f, m.usuario, coalesce(nullif(m.nome, ''), m.email)); end if;
    if rota = 'estado_split' then return radar.estado_split(f, coalesce(nullif(m.nome, ''), m.email)); end if;
    return radar.remover_split(f);
  end if;
  v_res := radar.api(rota, f);
  perform radar.anotar_tempo(rota, 'tela', extract(epoch from clock_timestamp() - v_ini) * 1000);
  return v_res;
end $_$;


--
-- Name: radar_chaves(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_chaves(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  eu radar.membros := radar.membro_atual();
  v_id bigint := case when coalesce(p ->> 'id', '') ~ '^[0-9]{1,15}$' then (p ->> 'id')::bigint end;
  v_projetos text[] := case when jsonb_typeof(p -> 'projetos') = 'array' then array(select jsonb_array_elements_text(p -> 'projetos')) else '{}'::text[] end;
  v_res jsonb;
begin
  if eu.usuario is null or eu.papel <> 'admin' then
    raise exception 'sem_acesso' using errcode = '42501';
  end if;
  p := coalesce(p, '{}'::jsonb);

  if p_acao = 'listar' then
    return jsonb_build_object('chaves', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'nome', c.nome, 'prefixo', c.prefixo, 'nivel', c.nivel, 'todos', c.todos, 'projetos', to_jsonb(c.projetos),
               'limite_minuto', c.limite_minuto, 'criada_em', radar.ms(c.criada_em), 'avisos_sistema', c.avisos_sistema,
               'criada_por', (select coalesce(nullif(m.nome, ''), m.email) from radar.membros m where m.usuario = c.criada_por),
               -- 045: a chave pessoal (do Claude de uma pessoa) e de quem e
               'pessoal', c.pessoal, 'dono', (select coalesce(nullif(m.nome, ''), m.email) from radar.membros m where m.usuario = c.dono),
               'expira_em', radar.ms(c.expira_em), 'revogada_em', radar.ms(c.revogada_em), 'ultimo_uso', radar.ms(c.ultimo_uso),
               'usos', c.usos,
               'usos_7d', coalesce((select sum(u.chamadas) from radar.chaves_uso u where u.chave = c.id and u.dia >= radar.hoje() - 6), 0),
               'situacao', case when c.revogada_em is not null then 'revogada'
                                when c.expira_em is not null and c.expira_em <= now() then 'vencida' else 'ativa' end)
             order by (c.revogada_em is not null), c.criada_em desc)
      from radar.chaves c), '[]'::jsonb));
  end if;

  if p_acao = 'criar' then
    v_res := radar.chave_criar(p ->> 'nome', v_projetos, coalesce(nullif(p ->> 'nivel', ''), 'agregado'), radar.sim(p ->> 'todos'),
                               case when coalesce(p ->> 'dias', '') ~ '^[0-9]{1,4}$' then (p ->> 'dias')::int end,
                               eu.usuario, radar.inteiro(p ->> 'limite', 60)::int);
    if radar.sim(p ->> 'avisos_sistema') and coalesce(v_res ->> 'id', '') ~ '^[0-9]+$' then
      update radar.chaves set avisos_sistema = true where id = (v_res ->> 'id')::bigint;
      v_res := v_res || jsonb_build_object('avisos_sistema', true);
    end if;
    return v_res;
  end if;

  -- 034: ligar ou desligar os avisos do sistema de uma chave que ja existe
  if p_acao = 'avisos' then
    update radar.chaves set avisos_sistema = radar.sim(p ->> 'ligado') where id = v_id and revogada_em is null;
    if not found then return jsonb_build_object('ok', false, 'erro', 'nao_encontrada'); end if;
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'revogar' then
    update radar.chaves set revogada_em = now() where id = v_id and revogada_em is null;
    if not found then return jsonb_build_object('ok', false, 'erro', 'nao_encontrada'); end if;
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'uso' then
    return jsonb_build_object('uso', coalesce((
      select jsonb_agg(jsonb_build_object('dia', u.dia::text, 'rota', u.rota, 'chamadas', u.chamadas, 'ultimo', radar.ms(u.ultimo)) order by u.dia desc, u.chamadas desc)
      from radar.chaves_uso u where u.chave = v_id and u.dia >= radar.hoje() - 30), '[]'::jsonb));
  end if;

  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $_$;


--
-- Name: radar_coletar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_coletar(text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  p jsonb;
  cab jsonb;
  origem text;
  r text;
  v_estado text;
  v_robo text;
  v_ip inet;
  v_rede boolean := false;
  v_rede_id bigint;
  v_lista boolean := false;
  v_novo boolean := false;
  v_cap radar.captacao;
  v_sem_video boolean := false;
begin
  -- protecao de espaco (radar.medir_espaco, a cada 10 min): perto do limite do plano o video para (80%) e depois a
  -- coleta toda (90%), sem escrever nada, antes que o Supabase trave o banco em "so leitura" (500 MB no gratis)
  select valor into v_estado from radar.config where chave = 'espaco_estado';
  if v_estado = 'coleta_pausada' then return 'pausado'; end if;
  if $1 is null or length($1) > 6000000 then return radar.recusa('tamanho'); end if;
  begin
    p := $1::jsonb;
  exception when others then
    return radar.recusa('json');
  end;
  begin
    cab := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  exception when others then
    cab := '{}'::jsonb;
  end;
  origem := cab ->> 'origin';
  -- robo nao e visita (a visita marcada como teste passa: e o robo de conferencia do proprio Radar)
  v_robo := radar.robo(cab ->> 'user-agent');
  if v_robo is not null and not radar.sim(p -> 'sessao' ->> 'teste') then
    perform radar.recusa('robo', v_robo);
    return 'pausado';
  end if;
  if v_estado = 'video_pausado' then p := p - 'gravacao' - 'gravacao_gz'; end if;
  -- 062: o que cada pagina capta (Configuracoes › Instalacao). O que a pagina nao capta sai do pacote antes de gravar,
  -- para qualquer versao do gravador; pagina sem linha capta tudo. Video desligado na pagina (ou fora da parte dela)
  -- responde "sem_video_pagina" no fim
  begin
    if jsonb_typeof(p -> 'pv') = 'object' and exists (select 1 from radar.captacao c where c.projeto = p ->> 'projeto') then
      select c.* into v_cap from radar.captacao c
       where c.projeto = p ->> 'projeto'
         and c.pagina = radar.pagina_id((select x.config from radar.projetos x where x.id = p ->> 'projeto'), left(p -> 'pv' ->> 'caminho', 200));
      if found then
        p := radar.captacao_filtra(p, v_cap);
        v_sem_video := v_cap.video <= 0 or (v_cap.video < 1 and radar.fatia(p -> 'sessao' ->> 'id') >= v_cap.video);
        if v_sem_video then p := p - 'gravacao' - 'gravacao_gz'; end if;
      end if;
    end if;
  exception when others then
    insert into radar.falhas (onde, mensagem) values ('captacao', left(sqlerrm, 300));
  end;
  -- equipe (021): rede da equipe ou navegador da equipe. A visita ja nasce teste (o pacote chega marcado ao ingerir)
  begin
    if jsonb_typeof(p -> 'sessao') = 'object' then
      v_ip := radar.ip_da_chamada(cab);
      if v_ip is not null then
        select id into v_rede_id from radar.redes_internas where rede >>= v_ip order by masklen(rede) desc, id limit 1;
      end if;
      v_rede := v_rede_id is not null;
      v_lista := exists (select 1 from radar.visitantes_internos
                         where projeto = p ->> 'projeto' and visitante = p -> 'sessao' ->> 'visitante');
      if v_rede or v_lista then p := jsonb_set(p, '{sessao,teste}', '1'::jsonb); end if;
    end if;
  exception when others then
    insert into radar.falhas (onde, mensagem) values ('equipe', left(sqlerrm, 300));
    v_rede := false;
    v_lista := false;
  end;
  r := radar.ingerir(p, origem);
  if r = 'ok' then
    begin
      perform radar.guardar_vitais(p);
    exception when others then
      insert into radar.falhas (onde, mensagem) values ('vitais', left(sqlerrm, 300));
    end;
    begin
      perform radar.guardar_info(p, cab);
    exception when others then
      insert into radar.falhas (onde, mensagem) values ('info', left(sqlerrm, 300));
    end;
    if v_rede or v_lista then
      begin
        -- navegador novo na rede da equipe: entra na lista e todas as visitas dele no projeto saem da conta (o passado
        -- incluso). Visita que outro pacote esta gravando agora fica para ele (skip locked: sem espera nem impasse)
        if v_rede and not v_lista then
          insert into radar.visitantes_internos (projeto, visitante, rede_id) values (p ->> 'projeto', p -> 'sessao' ->> 'visitante', v_rede_id)
          on conflict do nothing;
          v_novo := found;
        end if;
        if v_novo then
          update radar.sessoes set teste = true, interna = true
          where id in (select x.id from radar.sessoes x
                       where x.projeto = p ->> 'projeto' and x.visitante = p -> 'sessao' ->> 'visitante' and not x.interna
                       for update skip locked);
        else
          -- ja estava na lista: so a visita deste pacote (escreve uma vez, no primeiro pacote dela)
          update radar.sessoes set teste = true, interna = true where id = p -> 'sessao' ->> 'id' and not interna;
        end if;
      exception when others then
        insert into radar.falhas (onde, mensagem) values ('equipe', left(sqlerrm, 300));
      end;
    end if;
  end if;
  -- o gravador para de mandar video quando ouve "sem_video" (a visita continua sendo contada)
  if r = 'ok' and v_estado = 'video_pausado' then return 'sem_video'; end if;
  -- 062: so esta pagina fica sem video; as outras paginas da visita seguem com o que elas captam
  if r = 'ok' and v_sem_video then return 'sem_video_pagina'; end if;
  return r;
exception when others then
  insert into radar.falhas (onde, mensagem) values ('coletar', left(sqlerrm, 300));
  return 'erro';
end $_$;


--
-- Name: radar_crm(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_crm(acao text, f jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    SET work_mem TO '8MB'
    AS $$
declare
  m radar.membros := radar.membro_atual();
  v_id uuid;
  v_proj text;
begin
  if m.usuario is null or not radar.ve_area(m, 'crm') then raise exception 'sem_acesso' using errcode = '42501'; end if;
  -- 057: mandar reenviar escreve no Active: so o administrador, como apagar
  if acao in ('apagar', 'reenviar') and m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
  f := coalesce(f, '{}'::jsonb);
  if acao in ('lista', 'conferencia', 'resumo', 'exportar', 'reenvio', 'reenviar', 'pessoas_das_visitas') then
    if coalesce(f ->> 'projeto', '') = '' then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
    v_proj := f ->> 'projeto';
  elsif acao in ('ficha', 'apagar') then
    begin v_id := (f ->> 'id')::uuid; exception when others then v_id := null; end;
    select p.projeto into v_proj from radar_crm.pessoas p where p.id = v_id;
    if v_proj is null then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
  elsif acao = 'exportacoes' then
    v_proj := nullif(f ->> 'projeto', '');
  end if;
  if v_proj is not null and not radar.pode_ver(m, v_proj) then raise exception 'sem_acesso' using errcode = '42501'; end if;
  case acao
    when 'lista' then return radar_crm.api_lista(f);
    when 'ficha' then return radar_crm.api_ficha(f, m.usuario);
    when 'conferencia' then return radar_crm.api_conferencia(f);
    when 'resumo' then return radar_crm.api_resumo(f);
    when 'apagar' then return radar_crm.apagar(f, m.usuario);
    -- 044: exportar a lista do filtro (fica registrado) e ver as exportacoes
    when 'exportar' then return radar_crm.exportar(f, m.usuario);
    when 'exportacoes' then return radar_crm.api_exportacoes(f, case when m.papel = 'admin' then null else coalesce(m.projetos, '{}') end);
    -- 057: o reenvio ao Active (o andamento; e o botao, que poe na fila: o Radar refaz a cada minuto)
    when 'reenvio' then return radar_crm.api_reenvio(f);
    when 'reenviar' then return radar_crm.reenviar_marcar(v_proj, m.usuario);
    -- 060: de cada visita do gravador, a pessoa do CRM (so o id; abrir a ficha continua registrado em radar_crm.aberturas)
    when 'pessoas_das_visitas' then
      return jsonb_build_object('ok', true, 'pessoas', radar_crm.pessoas_das_visitas(v_proj,
        array(select jsonb_array_elements_text(case when jsonb_typeof(f -> 'sessoes') = 'array' then f -> 'sessoes' else '[]'::jsonb end))));
    else return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
  end case;
end $$;


--
-- Name: radar_equipe(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_equipe(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  eu radar.membros := radar.membro_atual();
  cab jsonb;
  v_ip inet;
  v_rede cidr;
  v_txt text;
  v_id bigint;
  v_erro text;
  v_devolvidas bigint := 0;
begin
  if eu.usuario is null or eu.papel <> 'admin' then
    raise exception 'sem_acesso' using errcode = '42501';
  end if;
  p := coalesce(p, '{}'::jsonb);
  begin
    cab := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  exception when others then
    cab := '{}'::jsonb;
  end;
  v_ip := radar.ip_da_chamada(cab);

  if p_acao = 'adicionar' then
    v_txt := left(trim(coalesce(p ->> 'rede', '')), 64);
    if v_txt <> '' then
      if pg_input_is_valid(v_txt, 'cidr') then
        v_rede := v_txt::cidr;
      elsif pg_input_is_valid(v_txt, 'inet') then
        -- "200.142.100.70/24" (bits ligados depois da mascara): vale a faixa
        v_rede := network(v_txt::inet);
      else
        v_erro := 'rede_invalida';
      end if;
    elsif v_ip is not null then
      v_rede := set_masklen(v_ip, case when family(v_ip) = 4 then 32 else 128 end)::cidr;
    else
      v_erro := 'sem_ip';
    end if;
    -- faixa grande demais tiraria da conta gente de fora (uma operadora inteira, um bairro)
    if v_erro is null and masklen(v_rede) < (case when family(v_rede) = 4 then 24 else 56 end) then v_erro := 'rede_grande'; end if;
    if v_erro is null then
      insert into radar.redes_internas (rede, nome, criada_por)
      values (v_rede, coalesce(nullif(left(trim(coalesce(p ->> 'nome', '')), 60), ''), 'Rede da equipe'), eu.usuario)
      on conflict (rede) do update set nome = coalesce(nullif(left(trim(coalesce(p ->> 'nome', '')), 60), ''), radar.redes_internas.nome);
    end if;
  elsif p_acao = 'remover' then
    v_id := case when coalesce(p ->> 'id', '') ~ '^[0-9]{1,15}$' then (p ->> 'id')::bigint end;
    if v_id is not null and exists (select 1 from radar.redes_internas where id = v_id) then
      -- desfaz o que a rede fez: os navegadores que entraram por ela saem da lista e as visitas deles voltam a contar
      -- (rede cadastrada por engano, como o IP do 4G, nao tira gente de fora da conta para sempre)
      with sai as (delete from radar.visitantes_internos where rede_id = v_id returning projeto, visitante)
      update radar.sessoes s set interna = false, teste = false
      from sai where s.projeto = sai.projeto and s.visitante = sai.visitante and s.interna;
      get diagnostics v_devolvidas = row_count;
      delete from radar.redes_internas where id = v_id;
    else
      v_erro := 'nao_encontrada';
    end if;
  elsif p_acao <> 'listar' then
    v_erro := 'acao_desconhecida';
  end if;

  return jsonb_build_object(
    'ok', v_erro is null,
    'meu_ip', host(v_ip),
    'redes', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'rede', r.rede::text, 'nome', r.nome, 'criada_em', radar.ms(r.criada_em),
                                          'minha', coalesce(v_ip is not null and r.rede >>= v_ip, false))
             order by r.criada_em, r.id)
      from radar.redes_internas r), '[]'::jsonb),
    'navegadores', (select count(*) from radar.visitantes_internos),
    'sessoes_7d', (select count(*) from radar.sessoes where interna and dia >= radar.hoje() - 6))
    || case when p_acao = 'remover' and v_erro is null then jsonb_build_object('devolvidas', v_devolvidas) else '{}'::jsonb end
    || case when v_erro is not null then jsonb_build_object('erro', v_erro) else '{}'::jsonb end;
end $_$;


--
-- Name: radar_eu(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_eu() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  m radar.membros := radar.membro_atual();
begin
  if m.usuario is null then return null; end if;
  return jsonb_build_object('usuario', m.usuario, 'email', m.email, 'nome', m.nome, 'papel', m.papel, 'projetos', to_jsonb(m.projetos),
                            'nivel', case when radar.ve_visitas(m) then 'sessoes' else 'agregado' end,
                            'funcao', m.funcao, 'areas', to_jsonb(radar.areas_de(m)));
end $$;


--
-- Name: radar_externo(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_externo(chave text, rota text DEFAULT 'eu'::text, f jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET statement_timeout TO '15s'
    SET work_mem TO '8MB'
    AS $$
-- "chave" e "rota" sao nomes dos parametros (e o que o sistema de fora manda) e tambem de colunas das tabelas de uso:
-- dentro de um comando SQL vale a coluna; o parametro e chamado pelo nome inteiro (radar_externo.chave)
#variable_conflict use_column
declare
  k radar.chaves;
  o radar.membros;
  v_rotas text[];
  v_nivel text;
  v_avisos boolean;
  v_todos boolean;
  v_lista text[];
  v_proj text;
  v_id uuid;
  v_n int;
  v_dia int;
  v_res jsonb;
  v_per jsonb;
  v_rota text := coalesce(nullif(trim(radar_externo.rota), ''), 'eu');
  v_ini timestamptz := clock_timestamp();
begin
  -- a chave: existe, nao foi revogada e nao venceu
  select c.* into k from radar.chaves c
  where c.hash = encode(sha256(convert_to(coalesce(radar_externo.chave, ''), 'UTF8')), 'hex')
    and c.revogada_em is null and (c.expira_em is null or c.expira_em > now());
  if k.id is null then raise exception 'chave_invalida' using errcode = '42501'; end if;
  -- 045: a chave pessoal vale enquanto a pessoa estiver ativa, e ve o que ela ve agora
  if k.pessoal then
    o := radar.membro_de(k.dono);
    if o.usuario is null then raise exception 'chave_invalida' using errcode = '42501'; end if;
  end if;

  -- o limite por minuto (a recusa desfaz a soma, entao a conta para no limite ate o minuto virar)
  insert into radar.chaves_ritmo as r (chave, minuto, chamadas) values (k.id, date_trunc('minute', now()), 1)
  on conflict (chave, minuto) do update set chamadas = r.chamadas + 1
  returning r.chamadas into v_n;
  if v_n > k.limite_minuto then raise exception 'limite_por_minuto' using errcode = 'P0001', hint = 'espere o minuto virar'; end if;

  -- o teto do dia (026): chamadas atendidas hoje, no relogio de Brasilia
  select coalesce(sum(u.chamadas), 0)::int into v_dia from radar.chaves_uso u where u.chave = k.id and u.dia = radar.hoje();
  if v_dia >= k.limite_dia then raise exception 'limite_por_dia' using errcode = 'P0001', hint = 'o teto zera a meia-noite de Brasilia'; end if;

  if k.pessoal then
    v_nivel := case when radar.ve_visitas(o) then 'sessoes' else 'agregado' end;
    v_rotas := radar.rotas_da_pessoa(o);
    v_todos := o.papel = 'admin';
    v_lista := case when v_todos then array(select p.id from radar.projetos p) else coalesce(o.projetos, '{}') end;
    v_avisos := o.papel = 'admin';
  else
    v_nivel := k.nivel;
    v_rotas := radar.rotas_externas(k.nivel);
    v_todos := k.todos;
    v_lista := case when k.todos then array(select p.id from radar.projetos p) else k.projetos end;
    v_avisos := k.avisos_sistema;
  end if;
  if not (v_rota = any (v_rotas)) then
    raise exception 'rota_nao_liberada: %', left(v_rota, 40) using errcode = '42501';
  end if;

  f := coalesce(f, '{}'::jsonb);
  if jsonb_typeof(f) <> 'object' then f := '{}'::jsonb; end if;

  if v_rota = 'eu' then
    -- quem e esta chave e o que ela alcanca (a primeira coisa que um sistema novo pergunta)
    v_res := jsonb_build_object('nome', k.nome, 'nivel', v_nivel, 'todos_os_funis', v_todos, 'funis', to_jsonb(v_lista),
                                'rotas', to_jsonb(v_rotas), 'limite_por_minuto', k.limite_minuto,
                                'limite_por_dia', k.limite_dia, 'usadas_hoje', v_dia, 'avisos_do_sistema', v_avisos,
                                'expira_em', radar.ms(k.expira_em), 'so_leitura', true, 'pessoal', k.pessoal)
             || case when k.pessoal then jsonb_build_object('dono', coalesce(nullif(o.nome, ''), o.email), 'papel', o.papel, 'funcao', o.funcao,
                                                            'areas', to_jsonb(radar.areas_de(o)), 'crm', radar.ve_area(o, 'crm'))
                     else '{}'::jsonb end;
  elsif v_rota = 'projetos' then
    v_res := radar.api_projetos(false, v_lista);
  elsif v_rota = 'alertas' and coalesce(f ->> 'projeto', '') = '' then
    -- alertas dos funis da chave; os avisos do sistema (espaco, coleta), so para a chave marcada para isso (034) ou do administrador
    v_res := radar.alertas_de(v_lista, f, v_avisos);
  elsif v_rota in ('crm_resumo', 'crm_lista', 'crm_ficha') then
    -- 045: o CRM pela chave pessoal, so dos projetos da pessoa; a lista vem em paginas de no maximo 50; cada lista fica em
    -- radar_crm.leituras_porta e cada ficha em radar_crm.aberturas, com a chave
    if v_rota = 'crm_ficha' then
      begin v_id := (f ->> 'id')::uuid; exception when others then v_id := null; end;
      select p.projeto into v_proj from radar_crm.pessoas p where p.id = v_id;
      if v_proj is null then raise exception 'pessoa_nao_encontrada' using errcode = 'P0001'; end if;
    else
      v_proj := f ->> 'projeto';
    end if;
    if v_proj is null or not (v_proj = any (v_lista)) then
      raise exception 'funil_nao_liberado' using errcode = '42501', hint = 'a rota projetos lista os funis desta chave';
    end if;
    if v_rota = 'crm_resumo' then
      v_res := radar_crm.api_resumo(f);
    elsif v_rota = 'crm_lista' then
      v_res := radar_crm.api_lista((f - 'limite') || jsonb_build_object('limite', least(greatest(radar.inteiro(f ->> 'limite', 20), 1), 50)));
      insert into radar_crm.leituras_porta (quem, chave, projeto, filtro, quantas, pessoas)
      values (o.usuario, k.id, v_proj, f - 'pag' - 'limite', jsonb_array_length(coalesce(v_res -> 'linhas', '[]'::jsonb)),
              array(select (x ->> 'id')::uuid from jsonb_array_elements(coalesce(v_res -> 'linhas', '[]'::jsonb)) x));
    else
      v_res := radar_crm.api_ficha(f, o.usuario, k.id);
    end if;
  else
    if v_rota = 'sessao' then
      select s.projeto into v_proj from radar.sessoes s where s.id = f ->> 'id';
      if v_proj is null then raise exception 'sessao_nao_encontrada' using errcode = 'P0001'; end if;
    else
      v_proj := f ->> 'projeto';
    end if;
    if v_proj is null or not (v_proj = any (v_lista)) then
      raise exception 'funil_nao_liberado' using errcode = '42501', hint = 'a rota projetos lista os funis desta chave';
    end if;
    -- a lista de visitas vem em paginas de no maximo 100
    if v_rota = 'sessoes' then f := f || jsonb_build_object('limite', least(greatest(radar.inteiro(f ->> 'limite', 50), 1), 100)); end if;
    if radar.sim(f ->> 'comparar') and v_rota in ('resumo', 'pagina', 'insights', 'desempenho', 'captura', 'leitura', 'leads_mql', 'oportunidades') then
      -- 034: o periodo pedido e o anterior de mesmo tamanho numa chamada so
      v_per := radar.periodos(f);
      v_res := jsonb_build_object(
        'periodo', jsonb_build_object('de', v_per ->> 'de', 'ate', v_per ->> 'ate', 'dias', v_per -> 'dias'),
        'periodo_anterior', jsonb_build_object('de', v_per ->> 'anterior_de', 'ate', v_per ->> 'anterior_ate'),
        'atual', radar.api(v_rota, (f - 'comparar') || jsonb_build_object('de', v_per ->> 'de', 'ate', v_per ->> 'ate')),
        'anterior', radar.api(v_rota, (f - 'comparar') || jsonb_build_object('de', v_per ->> 'anterior_de', 'ate', v_per ->> 'anterior_ate')));
    else
      v_res := radar.api(v_rota, f - 'comparar');
    end if;
    -- do mapa de calor ficam os elementos mais clicados e a rolagem; os pontos crus e o fundo (video) nao saem
    if v_rota = 'mapa' and v_res is not null then v_res := (v_res - 'cliques') - 'fundo'; end if;
    -- 034: os nomes que a casa deu aos codigos de anuncio e campanha, junto da resposta que mostra codigos (045: e o trafego)
    if v_rota in ('resumo', 'inicio', 'captura', 'pagina', 'oportunidades', 'achados', 'insights', 'trafego') and jsonb_typeof(v_res) = 'object' then
      v_res := v_res || jsonb_build_object('nomes_dos_anuncios', radar.api_apelidos(jsonb_build_object('projeto', v_proj)));
    end if;
  end if;

  -- o uso
  update radar.chaves set ultimo_uso = now(), usos = usos + 1 where id = k.id;
  insert into radar.chaves_uso as u (chave, dia, rota, chamadas, ultimo) values (k.id, radar.hoje(), v_rota, 1, now())
  on conflict (chave, dia, rota) do update set chamadas = u.chamadas + 1, ultimo = now();
  delete from radar.chaves_ritmo where minuto < now() - interval '1 hour';
  delete from radar.chaves_uso where dia < radar.hoje() - 400;
  perform radar.anotar_tempo(v_rota, 'porta', extract(epoch from clock_timestamp() - v_ini) * 1000);
  return v_res;
end $$;


--
-- Name: radar_feedback(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_feedback(acao text, f jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  m radar.membros := radar.membro_atual();
  v_id bigint;
begin
  if m.usuario is null then raise exception 'sem_acesso' using errcode = '42501'; end if;
  f := coalesce(f, '{}'::jsonb);
  if acao = 'lista' then
    -- cada pessoa ve os seus; o administrador ve todos, com o nome de quem mandou
    return jsonb_build_object(
      'admin', m.papel = 'admin',
      'novos', case when m.papel = 'admin' then (select count(*) from radar.feedback where estado = 'novo') end,
      'itens', coalesce((
        select jsonb_agg(jsonb_build_object('id', x.id, 'quando', x.quando, 'tipo', x.tipo, 'tela', x.tela, 'texto', x.texto,
                 'estado', x.estado, 'resposta', x.resposta, 'respondido_em', x.respondido_em, 'meu', x.quem = m.usuario,
                 'quem', case when m.papel = 'admin' then coalesce(nullif(mb.nome, ''), mb.email) end) order by x.quando desc)
        from (select * from radar.feedback where m.papel = 'admin' or quem = m.usuario order by quando desc limit 200) x
        left join radar.membros mb on mb.usuario = x.quem), '[]'::jsonb));
  elsif acao = 'enviar' then
    if coalesce(f ->> 'tipo', '') not in ('bug', 'faltou', 'ruim', 'ideia') then return jsonb_build_object('ok', false, 'erro', 'tipo'); end if;
    if length(btrim(coalesce(f ->> 'texto', ''))) < 3 then return jsonb_build_object('ok', false, 'erro', 'texto'); end if;
    if (select count(*) from radar.feedback where quem = m.usuario and quando > now() - interval '1 day') >= 30 then
      return jsonb_build_object('ok', false, 'erro', 'limite');
    end if;
    insert into radar.feedback (quem, tipo, tela, texto)
    values (m.usuario, f ->> 'tipo', left(coalesce(f ->> 'tela', ''), 80), left(btrim(f ->> 'texto'), 4000))
    returning id into v_id;
    return jsonb_build_object('ok', true, 'id', v_id);
  elsif acao = 'marcar' then
    if m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
    if coalesce(f ->> 'estado', '') not in ('novo', 'visto', 'feito', 'descartado') then return jsonb_build_object('ok', false, 'erro', 'estado'); end if;
    update radar.feedback set
      estado = f ->> 'estado',
      resposta = case when f ? 'resposta' then left(btrim(coalesce(f ->> 'resposta', '')), 2000) else resposta end,
      respondido_em = case when f ? 'resposta' then now() else respondido_em end,
      respondido_por = case when f ? 'resposta' then m.usuario else respondido_por end
    where id = radar.inteiro(f ->> 'id', 0);
    if not found then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'acao_desconhecida: %', acao;
end $$;


--
-- Name: radar_gravacoes(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_gravacoes(acao text, f jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET work_mem TO '8MB'
    AS $$
declare
  m radar.membros := radar.membro_atual();
  v_ids text[];
  v_id text;
  v_proj text;
  r jsonb;
  v_ok int := 0;
  v_pedacos int := 0;
  v_bytes bigint := 0;
begin
  if m.usuario is null or m.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
  f := coalesce(f, '{}'::jsonb);
  if acao = 'excluir' then
    v_ids := case when jsonb_typeof(f -> 'sessoes') = 'array' then array(select jsonb_array_elements_text(f -> 'sessoes'))
                  when coalesce(f ->> 'sessao', '') <> '' then array[f ->> 'sessao'] else '{}' end;
    if cardinality(v_ids) = 0 then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
    if cardinality(v_ids) > 200 then return jsonb_build_object('ok', false, 'erro', 'muitas'); end if;
    foreach v_id in array v_ids loop
      select s.projeto into v_proj from radar.sessoes s where s.id = v_id;
      if v_proj is null then continue; end if;
      if not radar.pode_ver(m, v_proj) then raise exception 'sem_acesso' using errcode = '42501'; end if;
      r := radar.excluir_gravacao(v_id, m.usuario, f ->> 'motivo');
      if coalesce((r ->> 'ok')::boolean, false) then
        v_ok := v_ok + 1; v_pedacos := v_pedacos + (r ->> 'pedacos')::int; v_bytes := v_bytes + (r ->> 'bytes')::bigint;
      end if;
    end loop;
    if v_ok = 0 then return jsonb_build_object('ok', false, 'erro', 'nao_achou'); end if;
    return jsonb_build_object('ok', true, 'excluidas', v_ok, 'pedacos', v_pedacos, 'bytes', v_bytes);
  elsif acao = 'excluidas' then
    if coalesce(f ->> 'projeto', '') = '' then return jsonb_build_object('ok', false, 'erro', 'projeto'); end if;
    if not radar.pode_ver(m, f ->> 'projeto') then raise exception 'sem_acesso' using errcode = '42501'; end if;
    return jsonb_build_object('ok', true, 'excluidas', coalesce((
      select jsonb_agg(jsonb_build_object('quando', x.quando, 'sessao', x.sessao, 'pedacos', x.pedacos, 'bytes', x.bytes, 'guardada', x.guardada,
                                          'motivo', x.motivo, 'quem', coalesce(nullif(mb.nome, ''), 'alguem da equipe')) order by x.quando desc)
      from (select * from radar.gravacoes_excluidas e where e.projeto = f ->> 'projeto' order by e.quando desc limit 100) x
      left join radar.membros mb on mb.usuario = x.quem), '[]'::jsonb));
  end if;
  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $$;


--
-- Name: radar_integracoes(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_integracoes(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  eu radar.membros := radar.membro_atual();
  v_url text;
  v_chave text;
  v_id uuid;
  v_sinc jsonb;
  v_cfg jsonb;
begin
  if eu.usuario is null or eu.papel <> 'admin' then raise exception 'sem_acesso' using errcode = '42501'; end if;
  p := coalesce(p, '{}'::jsonb);

  if p_acao = 'listar' then
    return jsonb_build_object(
      'active', (select jsonb_build_object(
                   'ligada', i.ligada, 'url', i.config ->> 'url', 'chave_fim', i.segredo_fim,
                   'atualizada_em', radar.ms(i.atualizada_em),
                   'atualizada_por', (select coalesce(nullif(m.nome, ''), m.email) from radar.membros m where m.usuario = i.atualizada_por),
                   'sincronizada_em', radar.ms(i.sincronizada_em), 'contagens', i.contagens, 'erro', i.erro, 'erro_em', radar.ms(i.erro_em),
                   'andamento', case when i.andamento is not null then jsonb_build_object('feitos', (i.andamento ->> 'i')::int - 1, 'de', 4) end)
                 from radar.integracoes i where i.id = 'active'),
      'diario', radar.diario_config(),
      'registro', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'quando', radar.ms(r.quando), 'integracao', r.integracao, 'acao', r.acao, 'detalhe', r.detalhe,
                 'quem', (select coalesce(nullif(m.nome, ''), m.email) from radar.membros m where m.usuario = r.quem)) order by r.quando desc)
        from (select * from radar.integracoes_registro order by quando desc limit 20) r), '[]'::jsonb));
  end if;

  if p_acao = 'ligar_active' then
    v_url := rtrim(lower(trim(coalesce(p ->> 'url', ''))), '/');
    v_chave := trim(coalesce(p ->> 'chave', ''));
    if v_url !~ '^https://[a-z0-9-]+\.(api-us[0-9]+\.com|activehosted\.com)$' then
      return jsonb_build_object('ok', false, 'erro', 'active_url');
    end if;
    if v_chave !~ '^[A-Za-z0-9]{40,100}$' then return jsonb_build_object('ok', false, 'erro', 'active_chave_formato'); end if;
    -- o Active confere antes: chave recusada nao entra no cofre
    begin
      perform radar.active_chamar('users/me', v_url, v_chave, 3500);
    exception when others then
      return jsonb_build_object('ok', false, 'erro', case when sqlerrm like 'active_chave_recusada%' then 'active_chave_recusada' else 'active_sem_resposta' end);
    end;
    select s.id into v_id from vault.secrets s where s.name = 'radar_active_chave';
    if v_id is null then
      perform vault.create_secret(v_chave, 'radar_active_chave', 'Chave da API do ActiveCampaign (Radar, banco 046)');
    else
      perform vault.update_secret(v_id, v_chave);
    end if;
    insert into radar.integracoes (id, ligada, config, segredo_fim, atualizada_em, atualizada_por)
    values ('active', true, jsonb_build_object('url', v_url), right(v_chave, 4), now(), eu.usuario)
    on conflict (id) do update set ligada = true, config = excluded.config, segredo_fim = excluded.segredo_fim,
      atualizada_em = now(), atualizada_por = eu.usuario, erro = null, erro_em = null, andamento = null;
    insert into radar.integracoes_registro (quem, integracao, acao, detalhe)
    values (eu.usuario, 'active', case when v_id is null then 'ligou' else 'trocou a chave' end, v_url);
    -- o catalogo comeca agora so se sobrar tempo nesta chamada; a tela continua com atualizar_active
    if clock_timestamp() < statement_timestamp() + interval '2.5 seconds' then
      v_sinc := radar.active_sincronizar(statement_timestamp() + interval '3 seconds');
    else
      v_sinc := jsonb_build_object('ok', true, 'continua', true, 'andamento', jsonb_build_object('tipo', 'listas', 'feitos', 0, 'de', 4));
    end if;
    return jsonb_build_object('ok', true, 'sincronizacao', v_sinc);
  end if;

  if p_acao = 'atualizar_active' then
    if not radar.sim(p ->> 'continuar') then
      insert into radar.integracoes_registro (quem, integracao, acao) values (eu.usuario, 'active', 'atualizou');
    end if;
    return radar.active_sincronizar(statement_timestamp() + interval '3 seconds');
  end if;

  if p_acao = 'desligar_active' then
    delete from vault.secrets where name = 'radar_active_chave';
    update radar.integracoes set ligada = false, segredo_fim = null, atualizada_em = now(), atualizada_por = eu.usuario,
      contagens = '{}', erro = null, erro_em = null, andamento = null where id = 'active';
    delete from radar.active_catalogo;
    insert into radar.integracoes_registro (quem, integracao, acao) values (eu.usuario, 'active', 'desligou');
    return jsonb_build_object('ok', true);
  end if;

  if p_acao = 'diario' then
    v_cfg := jsonb_build_object('ligado', radar.sim(p ->> 'ligado'),
                                'hora', least(greatest(radar.inteiro(p ->> 'hora', 7)::int, 6), 10),
                                'maquina', case when p ->> 'maquina' in ('pc', 'mac') then p ->> 'maquina' else 'pc' end);
    insert into radar.config (chave, valor) values ('diario', v_cfg::text)
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    insert into radar.integracoes_registro (quem, integracao, acao, detalhe)
    values (eu.usuario, 'diario', 'configurou',
            case when (v_cfg ->> 'ligado')::boolean then 'ligado, ' || (v_cfg ->> 'hora') || 'h, ' || case when v_cfg ->> 'maquina' = 'mac' then 'Mac' else 'PC do escritório' end
                 else 'desligado' end);
    return jsonb_build_object('ok', true, 'diario', radar.diario_config());
  end if;

  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $_$;


--
-- Name: radar_minha_chave(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_minha_chave(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  eu radar.membros := radar.membro_atual();
  v_chave text;
  v_id bigint;
  v_expira timestamptz := now() + interval '90 days';
begin
  if eu.usuario is null then raise exception 'sem_acesso' using errcode = '42501'; end if;
  if p_acao = 'ver' then
    return jsonb_build_object(
      'chave', (select jsonb_build_object('id', c.id, 'prefixo', c.prefixo, 'criada_em', radar.ms(c.criada_em), 'expira_em', radar.ms(c.expira_em),
                                          'ultimo_uso', radar.ms(c.ultimo_uso),
                                          'usos_7d', coalesce((select sum(u.chamadas) from radar.chaves_uso u where u.chave = c.id and u.dia >= radar.hoje() - 6), 0))
                from radar.chaves c
                where c.dono = eu.usuario and c.pessoal and c.revogada_em is null and (c.expira_em is null or c.expira_em > now())
                order by c.criada_em desc limit 1),
      'rotas', to_jsonb(radar.rotas_da_pessoa(eu)), 'crm', radar.ve_area(eu, 'crm'));
  end if;
  if p_acao = 'criar' then
    update radar.chaves set revogada_em = now() where dono = eu.usuario and pessoal and revogada_em is null;
    v_chave := 'rdr_' || substr(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 1, 48);
    insert into radar.chaves (nome, prefixo, hash, projetos, todos, nivel, limite_minuto, criada_por, expira_em, dono, pessoal)
    values (left('Claude de ' || coalesce(nullif(trim(eu.nome), ''), split_part(eu.email, '@', 1)), 60), left(v_chave, 10),
            encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'), '{}', false, 'agregado', 60, eu.usuario, v_expira, eu.usuario, true)
    returning id into v_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'chave', v_chave, 'prefixo', left(v_chave, 10), 'expira_em', radar.ms(v_expira));
  end if;
  if p_acao = 'revogar' then
    update radar.chaves set revogada_em = now() where dono = eu.usuario and pessoal and revogada_em is null;
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $$;


--
-- Name: radar_minha_senha(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_minha_senha(p_atual text, p_nova text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'extensions'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_hash text;
  v_sessao text;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'erro', 'sem_login'); end if;
  select encrypted_password into v_hash from auth.users where id = v_uid;
  if v_hash is null or crypt(coalesce(p_atual, ''), v_hash) <> v_hash then
    return jsonb_build_object('ok', false, 'erro', 'senha_atual');
  end if;
  if length(coalesce(p_nova, '')) < 8 then return jsonb_build_object('ok', false, 'erro', 'senha_curta'); end if;
  begin
    v_sessao := current_setting('request.jwt.claims', true)::jsonb ->> 'session_id';
  exception when others then
    v_sessao := null;
  end;
  perform radar.trocar_senha(v_uid, p_nova, v_sessao);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: radar_primeiro_acesso(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_primeiro_acesso(p_senha_painel text, p_email text, p_senha text, p_nome text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar', 'extensions'
    AS $$
declare
  h text;
  v_id uuid;
  v_email text := lower(trim(coalesce(p_email, '')));
  tentativas int;
begin
  if exists (select 1 from radar.membros where papel = 'admin' and ativo) then
    return jsonb_build_object('ok', false, 'erro', 'ja_existe_admin');
  end if;
  select vezes into tentativas from radar.recusas where dia = radar.hoje() and motivo = 'primeiro_acesso' and detalhe = '';
  if coalesce(tentativas, 0) >= 20 then return jsonb_build_object('ok', false, 'erro', 'tentativas'); end if;
  select valor into h from radar.config where chave = 'primeiro_acesso';
  if h is null then return jsonb_build_object('ok', false, 'erro', 'nao_preparado'); end if;
  if crypt(coalesce(p_senha_painel, ''), h) <> h then
    perform radar.recusa('primeiro_acesso');
    return jsonb_build_object('ok', false, 'erro', 'senha_painel');
  end if;
  begin
    select id into v_id from auth.users where lower(email) = v_email;
    if v_id is null then
      v_id := radar.criar_usuario(v_email, p_senha, p_nome);
    else
      -- o login ja existia (criado no painel do Supabase): vale a senha digitada agora
      perform radar.trocar_senha(v_id, p_senha);
      update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()), banned_until = null where id = v_id;
    end if;
  exception when raise_exception then
    return jsonb_build_object('ok', false, 'erro', sqlerrm);
  end;
  insert into radar.membros (usuario, nome, email, papel, projetos, ativo)
  values (v_id, coalesce(nullif(trim(p_nome), ''), split_part(v_email, '@', 1)), v_email, 'admin', '{}', true)
  on conflict (usuario) do update set papel = 'admin', ativo = true, atualizado_em = now();
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: radar_primeiro_acesso_aberto(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_primeiro_acesso_aberto() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select not exists (select 1 from radar.membros where papel = 'admin' and ativo)
     and exists (select 1 from radar.config where chave = 'primeiro_acesso')
$$;


--
-- Name: radar_rotina(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_rotina(p_acao text, p jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    SET work_mem TO '8MB'
    AS $$
begin
  p := coalesce(p, '{}'::jsonb);
  if p_acao = 'projetos' then return radar.api_projetos(true, '{}'); end if;
  if p_acao = 'api' then
    -- 043: a regua de leads (o Diario conta os leads pelo servidor, como as telas)
    if coalesce(p ->> 'rota', '') not in ('resumo', 'inicio', 'apelidos', 'captura', 'pagina', 'insights', 'desempenho', 'leitura',
                                          'oportunidades', 'leads_mql', 'testes', 'alertas', 'achados', 'diario', 'guardiao',
                                          'leads_paginas') then
      return jsonb_build_object('ok', false, 'erro', 'rota');
    end if;
    return radar.api(p ->> 'rota', coalesce(p -> 'f', '{}'::jsonb));
  end if;
  if p_acao = 'salvar_achados' then return radar.salvar_achados(p ->> 'projeto', radar.data(p ->> 'dia'), p -> 'achados', 'rotina'); end if;
  if p_acao = 'salvar_diario' then return radar.salvar_diario(p); end if;
  if p_acao = 'diario_vez' then
    return radar.diario_config() || jsonb_build_object(
      'feito', exists (select 1 from radar.diarios d where d.dia = radar.hoje() - 1),
      'hora_agora', extract(hour from now() at time zone 'America/Sao_Paulo')::int);
  end if;
  return jsonb_build_object('ok', false, 'erro', 'acao_desconhecida');
end $$;


--
-- Name: radar_salvar_projeto(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_salvar_projeto(cfg jsonb) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
begin
  if coalesce(cfg ->> 'id', '') !~ '^[a-z0-9-]{2,40}$' then raise exception 'id do projeto invalido'; end if;
  insert into radar.projetos (id, nome, situacao, dominios, config, engajamento_segundos, retencao_gravacao_dias, atualizado_em)
  values (cfg ->> 'id', coalesce(cfg ->> 'nome', cfg ->> 'id'), coalesce(cfg ->> 'situacao', 'nao_instalado'),
          array(select lower(jsonb_array_elements_text(coalesce(cfg -> 'dominios', '[]'::jsonb)))), cfg,
          coalesce(radar.inteiro(cfg ->> 'engajamento_segundos', 10), 10)::int,
          least(greatest(coalesce(radar.inteiro(cfg ->> 'retencao_video_dias', 3), 3), 1), 90)::int, now())
  on conflict (id) do update set
    nome = excluded.nome, situacao = excluded.situacao, dominios = excluded.dominios, config = excluded.config,
    engajamento_segundos = excluded.engajamento_segundos, retencao_gravacao_dias = excluded.retencao_gravacao_dias,
    atualizado_em = now();
  return cfg ->> 'id';
end $_$;


--
-- Name: radar_salvar_publicacoes(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_salvar_publicacoes(lista jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
declare
  e jsonb;
  pr radar.projetos;
  v_host text;
  v_caminho text;
  v_pagina text;
  v_quando timestamptz;
  novas int := 0;
  fora int := 0;
  n int;
begin
  for e in select value from jsonb_array_elements(case when jsonb_typeof(lista) = 'array' then lista else '[]'::jsonb end) loop
    v_host := lower(substring(coalesce(e ->> 'url', '') from '^[a-zA-Z]+://([^/:?#]+)'));
    select * into pr from radar.projetos where v_host = any (dominios) limit 1;
    begin
      v_quando := (e ->> 'quando')::timestamptz;
    exception when others then
      v_quando := null;
    end;
    if pr.id is null or v_quando is null then fora := fora + 1; continue; end if;
    if e ->> 'caminho' = '*' then
      v_pagina := '*';
    else
      v_caminho := coalesce(substring(e ->> 'url' from '^[a-zA-Z]+://[^/]+(/[^?#]*)'), '/') || coalesce(e ->> 'caminho', '');
      v_pagina := radar.pagina_id(pr.config, regexp_replace(v_caminho, '/+', '/', 'g'));
      -- so as paginas que o funil conhece
      if not exists (select 1 from jsonb_array_elements(coalesce(pr.config -> 'paginas', '[]'::jsonb)) pg where pg ->> 'id' = v_pagina) then
        fora := fora + 1; continue;
      end if;
    end if;
    insert into radar.publicacoes (projeto, pagina, url, quando, resumo)
    values (pr.id, v_pagina, left(e ->> 'url', 300), v_quando, left(coalesce(e ->> 'resumo', ''), 200))
    on conflict (projeto, pagina, quando) do update set resumo = excluded.resumo where radar.publicacoes.resumo = '';
    get diagnostics n = row_count;
    novas := novas + n;
  end loop;
  return jsonb_build_object('gravadas', novas, 'fora_dos_funis', fora);
end $$;


--
-- Name: radar_sendflow(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_sendflow(p_segredo text, p_corpo jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar_crm', 'radar'
    AS $$
declare
  k radar_crm.sendflow_chaves;
  v_log bigint;
  v_r jsonb;
begin
  select * into k from radar_crm.sendflow_chaves
  where hash = encode(sha256(convert_to(coalesce(p_segredo, ''), 'UTF8')), 'hex') and revogada_em is null;
  if k.id is null then raise exception 'sem_acesso' using errcode = '42501'; end if;
  update radar_crm.sendflow_chaves set ultimo_uso = now(), usos = usos + 1 where id = k.id;
  if p_corpo is null or jsonb_typeof(p_corpo) <> 'object' then
    p_corpo := jsonb_build_object('_bruto', p_corpo);
  end if;
  if length(p_corpo::text) > 200000 then
    return jsonb_build_object('ok', false, 'resultado', 'grande');
  end if;

  insert into radar_crm.sendflow_log (projeto, evento, payload)
  values (k.projeto, left(radar_crm.sf_texto(p_corpo, array['event', 'type', 'evento']), 120), p_corpo)
  returning id into v_log;

  begin
    v_r := radar_crm.sendflow_guardar(k.projeto, v_log, p_corpo, 'webhook');
    update radar_crm.sendflow_log set resultado = v_r ->> 'resultado', linhas = coalesce((v_r ->> 'linhas')::int, 0) where id = v_log;
  exception when others then
    update radar_crm.sendflow_log set resultado = 'erro_mapeamento', erro = left(sqlerrm, 300) where id = v_log;
    v_r := jsonb_build_object('resultado', 'erro_mapeamento');
  end;

  -- o log guarda 30 dias (tem telefone); a limpeza vem de carona, de vez em quando
  if random() < 0.02 then delete from radar_crm.sendflow_log where recebido_em < now() - interval '30 days'; end if;

  return jsonb_build_object('ok', true, 'log', v_log) || v_r;
end $$;


--
-- Name: radar_split_contar(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_split_contar(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $_$
declare
  t radar.testes;
  v_versao text := left(coalesce(p ->> 'versao', ''), 5);
  v_n int;
begin
  if coalesce(p ->> 'teste', '') !~ '^[0-9]{1,18}$' then return jsonb_build_object('ok', false, 'erro', 'teste'); end if;
  if coalesce(p ->> 'n', '') = '' then v_n := 1;
  elsif (p ->> 'n') ~ '^[0-9]{1,3}$' then v_n := (p ->> 'n')::int;
  else return jsonb_build_object('ok', false, 'erro', 'n');
  end if;
  if v_n < 1 or v_n > 500 then return jsonb_build_object('ok', false, 'erro', 'n'); end if;
  select * into t from radar.testes where id = (p ->> 'teste')::bigint and tipo = 'split' and estado in ('rodando', 'pausado');
  if not found then return jsonb_build_object('ok', false, 'erro', 'teste'); end if;
  if not exists (select 1 from jsonb_array_elements(t.versoes) v where v ->> 'id' = v_versao) then
    return jsonb_build_object('ok', false, 'erro', 'versao');
  end if;
  insert into radar.split_entregas (teste, versao, dia, hora, n)
  values (t.id, v_versao, radar.hoje(), extract(hour from now() at time zone 'America/Sao_Paulo')::smallint, v_n)
  on conflict (teste, versao, dia, hora) do update set n = radar.split_entregas.n + excluded.n;
  return jsonb_build_object('ok', true);
end $_$;


--
-- Name: radar_split_regras(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radar_split_regras(p_dominio text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'radar'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'entrada', t.entrada, 'estado', t.estado, 'promovida', t.promovida,
           'versoes', coalesce((select jsonb_agg(jsonb_build_object('id', v ->> 'id', 'url', v ->> 'url', 'peso', (v ->> 'peso')::int) order by v ->> 'id')
                                from jsonb_array_elements(t.versoes) v), '[]'::jsonb))
         order by t.entrada), '[]'::jsonb)
  from radar.testes t
  where t.tipo = 'split' and t.estado in ('rodando', 'pausado')
    and t.dominio_split = lower(btrim(left(coalesce(p_dominio, ''), 200)))
$$;


--
-- PostgreSQL database dump complete
--



-- identificacao: tudo o que e do Radar diz que e do Radar
comment on schema radar is 'Radar (sistema original): gravacoes, mapa de calor, funil, trafego, testes e split. Migrado em 16/10/2026; o Radar segue usando o banco completo e o sistema do Participa le os dados principais.';
comment on schema radar_crm is 'Radar (sistema original): o CRM do Radar (pessoas, envios, grupo do WhatsApp, reenvio ao Active). Era o schema crm no Supabase do Radar; nao confundir com o crm do Comercial. Migrado em 16/10/2026.';
comment on table radar_crm.pessoas is 'Radar (sistema original)';
comment on table radar.membros is 'Radar (sistema original)';
comment on table radar.captacao is 'Radar (sistema original)';
comment on table radar.sessoes is 'Radar (sistema original)';
comment on table radar_crm.aberturas is 'Radar (sistema original)';
comment on table radar_crm.chaves_servidor is 'Radar (sistema original)';
comment on table radar_crm.envios is 'Radar (sistema original)';
comment on table radar_crm.exclusoes is 'Radar (sistema original)';
comment on table radar_crm.exportacoes is 'Radar (sistema original)';
comment on table radar_crm.grupo_cache is 'Radar (sistema original)';
comment on table radar_crm.grupo_eventos is 'Radar (sistema original)';
comment on table radar_crm.leituras_porta is 'Radar (sistema original)';
comment on table radar_crm.parametros is 'Radar (sistema original)';
comment on table radar_crm.reenvios is 'Radar (sistema original)';
comment on table radar_crm.sendflow_campanhas is 'Radar (sistema original)';
comment on table radar_crm.sendflow_chaves is 'Radar (sistema original)';
comment on table radar_crm.sendflow_grupos is 'Radar (sistema original)';
comment on table radar_crm.sendflow_log is 'Radar (sistema original)';
comment on table radar.achados is 'Radar (sistema original)';
comment on table radar.achados_dia is 'Radar (sistema original)';
comment on table radar.achados_registros is 'Radar (sistema original)';
comment on table radar.active_catalogo is 'Radar (sistema original)';
comment on table radar.apelidos is 'Radar (sistema original)';
comment on table radar.chaves is 'Radar (sistema original)';
comment on table radar.chaves_ritmo is 'Radar (sistema original)';
comment on table radar.chaves_uso is 'Radar (sistema original)';
comment on table radar.cliques is 'Radar (sistema original)';
comment on table radar.cliques_202608 is 'Radar (sistema original)';
comment on table radar.cliques_202609 is 'Radar (sistema original)';
comment on table radar.cliques_202610 is 'Radar (sistema original)';
comment on table radar.cliques_202611 is 'Radar (sistema original)';
comment on table radar.config is 'Radar (sistema original)';
comment on table radar.diarios is 'Radar (sistema original)';
comment on table radar.erros is 'Radar (sistema original)';
comment on table radar.espaco_diario is 'Radar (sistema original)';
comment on table radar.eventos_funil is 'Radar (sistema original)';
comment on table radar.falhas is 'Radar (sistema original)';
comment on table radar.feedback is 'Radar (sistema original)';
comment on table radar.funcoes is 'Radar (sistema original)';
comment on table radar.gravacoes is 'Radar (sistema original)';
comment on table radar.gravacoes_20261013 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261014 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261015 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261016 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261017 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261018 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261019 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261020 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261021 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261022 is 'Radar (sistema original)';
comment on table radar.gravacoes_20261023 is 'Radar (sistema original)';
comment on table radar.gravacoes_excluidas is 'Radar (sistema original)';
comment on table radar.gravacoes_guardadas is 'Radar (sistema original)';
comment on table radar.guardadas is 'Radar (sistema original)';
comment on table radar.integracoes is 'Radar (sistema original)';
comment on table radar.integracoes_registro is 'Radar (sistema original)';
comment on table radar.meta_anuncios_dia is 'Radar (sistema original)';
comment on table radar.meta_rodadas is 'Radar (sistema original)';
comment on table radar.migracoes is 'Radar (sistema original)';
comment on table radar.pacotes is 'Radar (sistema original)';
comment on table radar.paginas_mapa is 'Radar (sistema original)';
comment on table radar.projetos is 'Radar (sistema original)';
comment on table radar.publicacoes is 'Radar (sistema original)';
comment on table radar.recusas is 'Radar (sistema original)';
comment on table radar.redes_internas is 'Radar (sistema original)';
comment on table radar.split_entregas is 'Radar (sistema original)';
comment on table radar.tempos_api is 'Radar (sistema original)';
comment on table radar.testes is 'Radar (sistema original)';
comment on table radar.velocidade_lab is 'Radar (sistema original)';
comment on table radar.visitantes is 'Radar (sistema original)';
comment on table radar.visitantes_internos is 'Radar (sistema original)';
comment on table radar.visualizacoes is 'Radar (sistema original)';
comment on function public.radar_crm_receber(p_chave text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_acessos(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_api(rota text, f jsonb) is 'Radar (sistema original)';
comment on function public.radar_chaves(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_coletar(text) is 'Radar (sistema original)';
comment on function public.radar_crm(acao text, f jsonb) is 'Radar (sistema original)';
comment on function public.radar_equipe(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_eu() is 'Radar (sistema original)';
comment on function public.radar_externo(chave text, rota text, f jsonb) is 'Radar (sistema original)';
comment on function public.radar_feedback(acao text, f jsonb) is 'Radar (sistema original)';
comment on function public.radar_gravacoes(acao text, f jsonb) is 'Radar (sistema original)';
comment on function public.radar_integracoes(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_minha_chave(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_minha_senha(p_atual text, p_nova text) is 'Radar (sistema original)';
comment on function public.radar_primeiro_acesso(p_senha_painel text, p_email text, p_senha text, p_nome text) is 'Radar (sistema original)';
comment on function public.radar_primeiro_acesso_aberto() is 'Radar (sistema original)';
comment on function public.radar_rotina(p_acao text, p jsonb) is 'Radar (sistema original)';
comment on function public.radar_salvar_projeto(cfg jsonb) is 'Radar (sistema original)';
comment on function public.radar_salvar_publicacoes(lista jsonb) is 'Radar (sistema original)';
comment on function public.radar_sendflow(p_segredo text, p_corpo jsonb) is 'Radar (sistema original)';
comment on function public.radar_split_contar(p jsonb) is 'Radar (sistema original)';
comment on function public.radar_split_regras(p_dominio text) is 'Radar (sistema original)';

-- tudo fechado (o Supabase da permissao padrao no public para anon e authenticated)
revoke all on all tables in schema radar, radar_crm from public, anon, authenticated;
revoke all on all sequences in schema radar, radar_crm from public, anon, authenticated;
revoke all on all functions in schema radar, radar_crm from public, anon, authenticated;
-- as particoes (cliques por mes, gravacoes por dia) tambem com RLS, como toda tabela nova no banco do Grupo
do $rls$ declare t regclass; begin for t in select c.oid::regclass from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('radar', 'radar_crm') and c.relkind = 'r' and not c.relrowsecurity loop execute format('alter table %s enable row level security', t); end loop; end $rls$;
revoke all on function public.radar_crm_receber(p_chave text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_acessos(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_api(rota text, f jsonb) from public, anon, authenticated;
revoke all on function public.radar_chaves(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_coletar(text) from public, anon, authenticated;
revoke all on function public.radar_crm(acao text, f jsonb) from public, anon, authenticated;
revoke all on function public.radar_equipe(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_eu() from public, anon, authenticated;
revoke all on function public.radar_externo(chave text, rota text, f jsonb) from public, anon, authenticated;
revoke all on function public.radar_feedback(acao text, f jsonb) from public, anon, authenticated;
revoke all on function public.radar_gravacoes(acao text, f jsonb) from public, anon, authenticated;
revoke all on function public.radar_integracoes(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_minha_chave(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_minha_senha(p_atual text, p_nova text) from public, anon, authenticated;
revoke all on function public.radar_primeiro_acesso(p_senha_painel text, p_email text, p_senha text, p_nome text) from public, anon, authenticated;
revoke all on function public.radar_primeiro_acesso_aberto() from public, anon, authenticated;
revoke all on function public.radar_rotina(p_acao text, p jsonb) from public, anon, authenticated;
revoke all on function public.radar_salvar_projeto(cfg jsonb) from public, anon, authenticated;
revoke all on function public.radar_salvar_publicacoes(lista jsonb) from public, anon, authenticated;
revoke all on function public.radar_sendflow(p_segredo text, p_corpo jsonb) from public, anon, authenticated;
revoke all on function public.radar_split_contar(p jsonb) from public, anon, authenticated;
revoke all on function public.radar_split_regras(p_dominio text) from public, anon, authenticated;

-- conferencia (o que tem de sair: 72 tabelas, 189 funcoes nos dois schemas, 22 funcoes publicas, 0 executavel por anon)
select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname in ('radar', 'radar_crm') and c.relkind in ('r', 'p')) as tabelas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('radar', 'radar_crm')) as funcoes,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'radar%') as funcoes_publicas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('radar', 'radar_crm', 'public') and (n.nspname <> 'public' or p.proname like 'radar%')
           and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) as abertas,
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname in ('radar', 'radar_crm') and c.relkind = 'r' and not c.relrowsecurity) as sem_rls;
commit;
