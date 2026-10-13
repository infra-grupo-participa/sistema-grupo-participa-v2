-- 20261013225100: cadastros da consultoria que vieram do Respondi entram no dashboard da Black como CADASTRO
--
-- POR QUE: dados.black_leads só lia a página nova da consultoria (metodo.consultoria_aplicacoes, desde 12/10 18h14). As
-- aplicações pelo Respondi (form JmSmjBBS, workspace 3504, de 29/09 até 12/10 19h58) não entravam em nenhum número da tela.
-- O QUE FAZ (2ª versão, 13/10 noite, pedido do Maestro: a MESMA base da lista de disparo):
--  1. dados.black_leads ganha o ramo pagina = 'consultoria_respondi' (porta 'consultoria') com a mesma regra de
--     dados.black_base_pessoas: todo o JmSmjBBS do banco, SEM janela de data, com contato (e-mail ou telefone com 10+
--     dígitos); a resposta parcial segue o MESMO interruptor das listas (dados.black_lista_config.incluir_respondi_parcial,
--     hoje false). Sem UTM: canal sempre nulo, nunca é lead pago. campos.parcial diz se a resposta é parcial.
--  2. dados.black_base_pessoas e dados.black_lista_disparo_montar passam a ignorar esse ramo, porque já leem o Respondi
--     pelo ramo próprio: as listas da Mensageria e a planilha ficam iguais.
--  3. public.dados_black_grupo devolve 'grupo_consultoria' (decisão do Victor, 13/10: o card de ingresso fica só com o
--     grupo da Black e mostra à parte "no grupo da consultoria: X"): membros, leads_no_grupo e mql_no_grupo (pessoas do
--     recorte, o mesmo denominador do card). Só contagem, sem dado pessoal. Nenhuma chave existente muda.
-- DECISÕES DO VICTOR (13/10 noite): início do dashboard continua 04/10; parciais pelo interruptor das listas.
-- ATENÇÃO: as RPCs da tela filtram criado_em a partir de dados.dashboards.periodo_inicio (04/10); as respostas de 29/09
--   a 03/10 só aparecem com p_de anterior ou com o início do dashboard mudado (decisão do Victor, fora desta migration).
-- AS 5 PERGUNTAS: escala = + até 664 linhas (respondi.respostas por form_slug, índice respostas_form_idx; o form parou em
--   12/10, não cresce); índice = respostas_form_idx; frequência = a de cada RPC da tela (5 min com a aba aberta);
--   repetição = nenhuma consulta nova; reversão = 20261013225100_reversao.sql (view e as 2 funções voltam ao corpo anterior).

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if md5(pg_get_viewdef('dados.black_leads'::regclass)) <> '5ce616621e652aaf79445444620f9798'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure) <> '5c5662907874de3e301e6710adf6eb56'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '37f944836201dd0c7cbf15ce77539c16'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> 'd01f477c89b3aa735fd90f393bfbb26f' then
    raise exception '20261013225100: definição viva mudou (black_leads, black_base_pessoas, black_lista_disparo_montar ou dados_black_grupo). Reler.';
  end if;
end
$g$;

create or replace view dados.black_leads with (security_invoker = true) as
 WITH b AS (
         SELECT 'captacao'::text AS pagina,
            (r.id)::text AS id_fonte,
            r.criado_em,
            r.nome,
            r.email,
            r.whatsapp,
            r.profissao,
            r.utm_source,
            r.utm_medium,
            r.utm_campaign,
            r.utm_content,
            r.utm_term,
            jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal, 'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding)) AS campos
           FROM metodo.pesquisa_respostas r
          WHERE ((r.origem = 'metodo-perfeito'::text) AND (r.criado_em >= '2026-10-04 03:00:00+00'::timestamp with time zone))
        UNION ALL
         SELECT 'fluxograma'::text,
            (r.id)::text AS id,
            r.criado_em,
            r.nome,
            r.email,
            r.whatsapp,
            r.profissao,
            r.utm_source,
            r.utm_medium,
            r.utm_campaign,
            r.utm_content,
            r.utm_term,
            jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal, 'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding)) AS jsonb_strip_nulls
           FROM metodo.pesquisa_respostas r
          WHERE ((r.origem = 'fluxograma-holding-familiar'::text) AND (r.criado_em >= '2026-10-04 03:00:00+00'::timestamp with time zone))
        UNION ALL
         SELECT 'consultoria'::text,
            (c.id)::text AS id,
            c.criado_em,
            c.nome,
            c.email,
            c.whatsapp,
            c.profissao,
            c.utm_source,
            c.utm_medium,
            c.utm_campaign,
            c.utm_content,
            c.utm_term,
            jsonb_strip_nulls(jsonb_build_object('cursos', to_jsonb(c.cursos), 'momento', c.momento, 'dificuldade', c.dificuldade, 'quer_levar_caso', c.quer_levar_caso, 'participa_camera', c.participa_camera, 'nota_indicacao', c.nota_indicacao)) AS jsonb_strip_nulls
           FROM metodo.consultoria_aplicacoes c
          WHERE ((c.origem = 'consultoria-ao-vivo'::text) AND (c.criado_em >= '2026-10-04 03:00:00+00'::timestamp with time zone))
        UNION ALL
         SELECT 'checkup'::text,
            (g.id)::text AS id,
            g.criado_em,
            g.nome,
            g.email,
            g.whatsapp,
            g.profissao,
            g.utm_source,
            g.utm_medium,
            g.utm_campaign,
            g.utm_content,
            g.utm_term,
            jsonb_strip_nulls(jsonb_build_object('faixa', g.faixa, 'pontos_total', g.pontos_total, 'mql_fonte', g.mql)) AS jsonb_strip_nulls
           FROM rede.diagnosticos g
          WHERE (g.criado_em >= '2026-10-04 03:00:00+00'::timestamp with time zone)
        UNION ALL
         SELECT 'futurometro'::text,
            (f.id)::text AS id,
            f.criado_em,
            f.nome,
            f.email,
            f.whatsapp,
            f.profissao,
            f.utm_source,
            f.utm_medium,
            f.utm_campaign,
            f.utm_content,
            f.utm_term,
            jsonb_strip_nulls(jsonb_build_object('casos_ativos', f.casos_ativos, 'satisfeito', f.satisfeito)) AS jsonb_strip_nulls
           FROM rede.futurometros f
          WHERE (f.criado_em >= '2026-10-04 03:00:00+00'::timestamp with time zone)
        UNION ALL
         SELECT 'consultoria_respondi'::text,
            r.uuid::text AS id,
            r.respondido_em,
            NULLIF(btrim(r.dados ->> 'nome'::text), ''::text),
            r.email,
            COALESCE(r.dados ->> 'telefone'::text, r.telefone),
            r.dados ->> 'profissao'::text,
            NULL::text,
            NULL::text,
            NULL::text,
            NULL::text,
            NULL::text,
            jsonb_build_object('fonte', 'respondi', 'form', r.form_slug, 'parcial', COALESCE(((r.dados ->> 'parcial'::text))::boolean, false))
           FROM respondi.respostas r
          WHERE ((r.form_slug = 'JmSmjBBS'::text) AND ((NOT COALESCE(((r.dados ->> 'parcial'::text))::boolean, false)) OR COALESCE(( SELECT c.incluir_respondi_parcial
                   FROM dados.black_lista_config c
                  WHERE c.id), false)) AND ((NULLIF(btrim(r.email), ''::text) IS NOT NULL) OR (length(regexp_replace(COALESCE(r.dados ->> 'telefone'::text, r.telefone, ''::text), '[^0-9]'::text, ''::text, 'g'::text)) >= 10)))
        ), n AS (
         SELECT b.pagina,
            b.id_fonte,
            b.criado_em,
            b.nome,
            b.email,
            b.whatsapp,
            b.profissao,
            b.utm_source,
            b.utm_medium,
            b.utm_campaign,
            b.utm_content,
            b.utm_term,
            b.campos,
            NULLIF(lower(btrim(b.email)), ''::text) AS email_norm,
            controle.fone_key(b.whatsapp) AS fk,
            NULLIF(btrim(b.profissao), ''::text) AS prof,
            NULLIF(btrim(b.utm_source), ''::text) AS us,
            NULLIF(btrim(b.utm_medium), ''::text) AS um,
            NULLIF(btrim(b.utm_campaign), ''::text) AS uc,
            NULLIF(btrim(b.utm_content), ''::text) AS ut,
            NULLIF(btrim(b.utm_term), ''::text) AS ue
           FROM b
        )
 SELECT ((pagina || ':'::text) || id_fonte) AS lead_id,
    pagina,
    id_fonte,
    criado_em,
    nome,
    email_norm AS email,
    whatsapp,
    profissao,
        CASE
            WHEN (prof IS NULL) THEN NULL::text
            WHEN (prof = 'Advogado(a)'::text) THEN 'advogado'::text
            WHEN (prof = 'Contador(a)'::text) THEN 'contador'::text
            WHEN (prof = 'Estudante de Direito'::text) THEN 'estudante_direito'::text
            ELSE 'outros'::text
        END AS profissao_classe,
    COALESCE((prof = ANY (ARRAY['Advogado(a)'::text, 'Contador(a)'::text, 'Estudante de Direito'::text])), false) AS mql,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    "substring"(uc, '\|([0-9]+)$'::text) AS campanha_id,
    "substring"(um, '\|([0-9]+)$'::text) AS conjunto_id,
    "substring"(ut, '\|([0-9]+)$'::text) AS anuncio_id,
        CASE
            WHEN (pagina = 'captacao'::text) THEN 'inscricao_direta'::text
            WHEN (pagina = ANY (ARRAY['consultoria'::text, 'consultoria_respondi'::text])) THEN 'consultoria'::text
            ELSE 'isca'::text
        END AS porta,
        CASE pagina
            WHEN 'fluxograma'::text THEN 'Fluxograma'::text
            WHEN 'checkup'::text THEN 'Checkup'::text
            WHEN 'futurometro'::text THEN 'Futurômetro'::text
            ELSE NULL::text
        END AS isca,
        CASE
            WHEN (lower(us) = ANY (ARRAY['fb'::text, 'facebook'::text, 'ig'::text, 'instagram'::text, 'meta'::text, 'metaads'::text])) THEN 'meta'::text
            WHEN (lower(us) = ANY (ARRAY['google'::text, 'googleads'::text, 'google_ads'::text])) THEN 'google'::text
            ELSE NULL::text
        END AS canal,
    fk AS fone_key,
    "right"(fk, 8) AS fone8,
    "left"(fk, 2) AS ddd,
        CASE
            WHEN (fk IS NULL) THEN NULL::text
            ELSE COALESCE(( SELECT u.uf
               FROM dados.ddd_uf u
              WHERE (u.ddd = "left"(n.fk, 2))), 'Outros'::text)
        END AS uf,
    COALESCE(('f:'::text || "right"(fk, 8)), ('e:'::text || email_norm), ((('l:'::text || pagina) || ':'::text) || id_fonte)) AS pessoa_chave,
    dados.teste_ativo('black-friday-2026-10'::text, email_norm, whatsapp) AS teste,
    COALESCE(((email_norm ~~ '%teste%'::text) OR (nome ~~* '%teste%'::text) OR (email_norm ~~ '%@advmais.com%'::text)), false) AS parece_teste,
    array_remove(ARRAY[
        CASE
            WHEN (prof IS NULL) THEN 'profissao_vazia'::text
            ELSE NULL::text
        END,
        CASE
            WHEN ((us IS NULL) AND (um IS NULL) AND (uc IS NULL) AND (ut IS NULL) AND (ue IS NULL)) THEN 'sem_utm'::text
            ELSE NULL::text
        END,
        CASE
            WHEN ((NOT ((us IS NULL) AND (um IS NULL) AND (uc IS NULL) AND (ut IS NULL) AND (ue IS NULL))) AND (uc IS DISTINCT FROM 'black-friday-2026-10'::text) AND (NOT ((lower(COALESCE(us, ''::text)) = ANY (ARRAY['fb'::text, 'facebook'::text, 'ig'::text, 'instagram'::text, 'meta'::text, 'metaads'::text])) AND (uc ~ '\|[0-9]+$'::text)))) THEN 'utm_campaign_fora_do_padrao'::text
            ELSE NULL::text
        END], NULL::text) AS a_corrigir,
    campos
   FROM n;;

revoke all on dados.black_leads from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION dados.black_base_pessoas()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261013190000: base deduplicada dos leads da Black. Pessoa = componente ligado por telefone (8 últimos dígitos) OU
-- e-mail. Fora: teste (marcação, parece_teste; no grupo, telefone cujos registros de formulário são todos teste) e a
-- Turma Especial (dados.turma_especial_chaves). Devolve {resumo, pessoas[]}; cada pessoa traz nome, email, telefone,
-- profissão normalizada, situação em cada grupo e cada formulário preenchido. Mesma regra de dedup e de telefone de
-- dados.black_lista_disparo_montar (20261013174100).
declare
  v_chave constant text := 'black-friday-2026-10';
  v_mudou int;
  v_volta int := 0;
  r jsonb;
begin
  drop table if exists pg_temp._b, pg_temp._te, pg_temp._bt, pg_temp._bp;   -- 2ª chamada na mesma transação
  create temp table _b (
    id bigserial, fonte text not null, criado_em timestamptz, nome text, email text, prof text,
    bruto text, dig text, fone8 text, fk text, grupo_estado text, grupo_nome text, parcial boolean not null default false,
    teste boolean not null default false, comp bigint
  ) on commit drop;

  -- formulários da Black (view já normaliza e marca teste): captacao | fluxograma, checkup, futurometro (isca) | consultoria (página)
  insert into _b (fonte, criado_em, nome, email, prof, bruto, teste)
  select case when l.pagina in ('fluxograma', 'checkup', 'futurometro') then 'isca' when l.pagina = 'consultoria' then 'pagina_consultoria' else 'captacao' end,
         l.criado_em, nullif(btrim(l.nome), ''), l.email, l.profissao_classe, nullif(btrim(l.whatsapp), ''),
         coalesce(l.teste, false) or coalesce(l.parece_teste, false)
    from dados.black_leads l
   where l.pagina <> 'consultoria_respondi';   -- 20261013225100: o Respondi já entra pelo ramo próprio abaixo (listas iguais)

  -- Respondi da consultoria (JmSmjBBS), concluídas e parciais com contato
  insert into _b (fonte, criado_em, nome, email, prof, bruto, parcial, teste)
  select 'respondi_consultoria', x.respondido_em, nullif(btrim(x.dados->>'nome'), ''), nullif(lower(btrim(x.email)), ''),
         case btrim(x.dados->>'profissao') when 'Advogado(a)' then 'advogado' when 'Contador(a)' then 'contador'
              when 'Estudante de Direito' then 'estudante_direito' when '' then null
              else case when x.dados->>'profissao' is null then null else 'outros' end end,
         nullif(btrim(coalesce(x.dados->>'telefone', x.telefone)), ''),
         coalesce((x.dados->>'parcial')::boolean, false),
         dados.teste_ativo(v_chave, x.email, coalesce(x.dados->>'telefone', x.telefone))
         or coalesce(lower(x.email) like '%teste%' or x.dados->>'nome' ilike '%teste%' or lower(x.email) like '%@advmais.com%', false)
    from respondi.respostas x
   where x.form_slug = 'JmSmjBBS'
     -- 20261013183515: resposta incompleta do Respondi só entra com dados.black_lista_config.incluir_respondi_parcial (decisão do
     -- Victor, 13/10: "por enquanto não"); a pessoa continua se tiver outra fonte
     and (not coalesce((x.dados->>'parcial')::boolean, false)
          or coalesce((select c.incluir_respondi_parcial from dados.black_lista_config c where c.id), false))
     and (nullif(btrim(x.email), '') is not null or length(regexp_replace(coalesce(x.dados->>'telefone', x.telefone, ''), '[^0-9]', '', 'g')) >= 10);

  -- grupos: foto (número completo quando veio) e entrada do webhook que a foto nunca viu
  insert into _b (fonte, criado_em, bruto, fone8, fk, grupo_estado, grupo_nome)
  select case when g.papel = 'lista' then 'grupo_consultoria' else 'grupo_black' end, p.visto_primeiro_em, p.numero, p.fone8, p.fone_key,
         case when p.no_grupo then 'no_grupo' else 'saiu' end, coalesce(p.grupos, g.sendflow_campanha)
    from dados.grupo_participantes p
    join dados.dashboard_grupos g on g.id = p.grupo_id
   where g.chave = v_chave;
  insert into _b (fonte, criado_em, fone8, fk, grupo_estado, grupo_nome)
  select case when g.papel = 'lista' then 'grupo_consultoria' else 'grupo_black' end, min(j.ocorreu_em), right(j.fone_key, 8), max(j.fone_key),
         case when (array_agg(j.tipo order by j.ocorreu_em desc, j.id desc))[1] = 'entrada' then 'no_grupo' else 'saiu' end,
         g.sendflow_campanha
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.chave = v_chave and g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null
     and not exists (select 1 from dados.grupo_participantes p where p.grupo_id = g.id and p.fone8 = right(j.fone_key, 8))
   group by g.papel, g.sendflow_campanha, right(j.fone_key, 8);

  -- 20261013184806: "where true": o PostgREST do Supabase carrega a safeupdate, que recusa UPDATE sem WHERE (21000)
  update _b set dig = nullif(regexp_replace(coalesce(bruto, ''), '[^0-9]', '', 'g'), '') where true;
  update _b set fone8 = right(dig, 8) where fone8 is null and length(dig) >= 8;

  -- teste no grupo: telefone marcado, ou cujos registros de formulário são todos teste
  update _b g set teste = true
   where g.fonte like 'grupo_%'
     and (exists (select 1 from dados.marcacoes_teste m where m.chave = v_chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = g.fone8)
          or (exists (select 1 from _b f where f.fonte not like 'grupo_%' and f.fone8 = g.fone8)
              and not exists (select 1 from _b f where f.fonte not like 'grupo_%' and f.fone8 = g.fone8 and not f.teste)));

  -- pessoa = componente ligado por fone8 ou e-mail
  update _b set comp = id where true;
  loop
    with kf as (select fone8, min(comp) m from _b where fone8 is not null group by fone8),
         ke as (select email, min(comp) m from _b where email is not null group by email),
         novo as (
      select b.id, least(b.comp, coalesce(kf.m, b.comp), coalesce(ke.m, b.comp)) as m
        from _b b left join kf on kf.fone8 = b.fone8 left join ke on ke.email = b.email
    )
    update _b b set comp = novo.m from novo where novo.id = b.id and novo.m < b.comp;
    get diagnostics v_mudou = row_count;
    v_volta := v_volta + 1;
    exit when v_mudou = 0 or v_volta > 50;
  end loop;
  if v_mudou <> 0 then
    raise exception 'black_base_pessoas: dedup não convergiu em 50 voltas';
  end if;

  -- Turma Especial: a pessoa inteira sai se qualquer e-mail ou telefone dela casar
  create temp table _te on commit drop as
  select distinct b.comp from _b b
   where exists (select 1 from dados.turma_especial_chaves t where t.tipo = 'email' and b.email is not null
                   and t.hash = encode(extensions.digest(b.email, 'sha256'), 'hex'))
      or exists (select 1 from dados.turma_especial_chaves t where t.tipo = 'fone8' and b.fone8 is not null
                   and t.hash = encode(extensions.digest(b.fone8, 'sha256'), 'hex'));

  -- telefone: 55 + DDD válido + 8 ou 9 dígitos; 10/11 dígitos com DDD válido ganha o 55
  create temp table _bt on commit drop as
  select b.*,
         case
           when b.dig ~ '^55[0-9]{10,11}$' and u1.ddd is not null then b.dig
           when b.dig ~ '^[0-9]{10,11}$' and b.dig !~ '^55' and u2.ddd is not null then '55' || b.dig
         end as tel_ok,
         case
           when b.dig is null then null
           when b.dig ~ '^55[0-9]{10,11}$' and u1.ddd is not null then null
           when b.dig ~ '^[0-9]{10,11}$' and b.dig !~ '^55' and u2.ddd is not null then null
           when b.dig ~ '^55' and length(b.dig) in (12, 13) then 'DDD inválido'
           when length(b.dig) between 11 and 15 and b.dig !~ '^55' then 'DDI fora do Brasil (prefixo ' || left(b.dig, 3) || ')'
           else 'Número com ' || length(b.dig) || ' dígitos'
         end as motivo
    from _b b
    left join dados.ddd_uf u1 on u1.ddd = substr(b.dig, 3, 2)
    left join dados.ddd_uf u2 on u2.ddd = left(b.dig, 2);

  create temp table _bp on commit drop as
  with base as (select bt.* from _bt bt where not bt.teste and bt.comp not in (select comp from _te))
  select b.comp,
         (array_agg(b.nome order by b.criado_em desc nulls last, b.id desc) filter (where b.nome is not null))[1] as nome,
         (array_agg(b.email order by b.criado_em desc nulls last, b.id desc) filter (where b.email is not null))[1] as email,
         (array_agg(b.tel_ok order by (b.fonte like 'grupo_%'), b.criado_em desc nulls last, b.id desc) filter (where b.tel_ok is not null))[1] as telefone,
         (array_agg('55' || b.fk order by b.criado_em desc nulls last, b.id desc)
            filter (where b.dig is null and b.fk ~ '^[0-9]{10}$' and exists (select 1 from dados.ddd_uf u where u.ddd = left(b.fk, 2))))[1] as tel_incompleto,
         (array_agg(b.bruto order by b.criado_em desc nulls last, b.id desc) filter (where b.motivo is not null))[1] as fora_bruto,
         (array_agg(b.motivo order by b.criado_em desc nulls last, b.id desc) filter (where b.motivo is not null))[1] as fora_motivo,
         (array_agg(b.prof order by b.criado_em desc nulls last, b.id desc) filter (where b.prof is not null))[1] as prof,
         -- 'saiu' só se não está mais em nenhum grupo Black (pode ter saído de um subgrupo e estar em outro)
         case when bool_or(b.fonte = 'grupo_black' and b.grupo_estado = 'no_grupo') then 'no_grupo'
              when bool_or(b.fonte = 'grupo_black') then 'saiu' else 'nunca' end as grupo_black,
         case when bool_or(b.fonte = 'grupo_consultoria' and b.grupo_estado = 'no_grupo') then 'no_grupo'
              when bool_or(b.fonte = 'grupo_consultoria') then 'saiu' else 'nunca' end as grupo_consultoria,
         bool_or(b.fonte = 'captacao') as f_captacao,
         bool_or(b.fonte = 'isca') as f_isca,
         bool_or(b.fonte = 'respondi_consultoria' and not b.parcial) as f_respondi,
         bool_or(b.fonte = 'respondi_consultoria' and b.parcial) and not bool_or(b.fonte = 'respondi_consultoria' and not b.parcial) as f_respondi_so_parcial,
         bool_or(b.fonte = 'pagina_consultoria') as f_pagina,
         string_agg(distinct b.grupo_nome, ', ') filter (where b.fonte = 'grupo_black' and b.grupo_estado = 'saiu') as saiu_black_de,
         string_agg(distinct b.grupo_nome, ', ') filter (where b.fonte = 'grupo_consultoria' and b.grupo_estado = 'saiu') as saiu_consultoria_de,
         array_agg(distinct b.fonte order by b.fonte) as fontes,
         min(b.criado_em) as primeiro, max(b.criado_em) as ultimo
    from base b
   group by b.comp;

  select jsonb_build_object(
    'gerado_em', now(),
    'resumo', jsonb_build_object(
      'registros', (select count(*) from _bt),
      'registros_por_fonte', (select jsonb_object_agg(fonte, n) from (select fonte, count(*) n from _bt group by fonte) s),
      'pessoas_por_fonte', (select jsonb_object_agg(f, n) from (select f, count(*) n from _bp, unnest(fontes) f group by f) s),
      'registros_teste', (select count(*) from _bt where teste),
      'pessoas_so_teste', (select count(distinct comp) from _bt where comp not in (select comp from _bt where not teste)),
      'pessoas_turma_especial', (select count(*) from _te where comp in (select comp from _bt where not teste)),
      'pessoas', (select count(*) from _bp),
      'duplicados_fundidos', (select count(*) from _bt where not teste and comp not in (select comp from _te)) - (select count(*) from _bp),
      'telefone_padrao', (select count(*) from _bp where telefone is not null),
      'telefone_incompleto', (select count(*) from _bp where telefone is null and tel_incompleto is not null),
      'telefone_fora_do_padrao', (select count(*) from _bp where telefone is null and tel_incompleto is null and fora_motivo is not null),
      'sem_telefone', (select count(*) from _bp where telefone is null and tel_incompleto is null and fora_motivo is null),
      'segmento', (select jsonb_object_agg(p, n) from (select case when prof in ('advogado', 'estudante_direito') then 'advogado' when prof = 'contador' then 'contador' else 'outros' end p, count(*) n from _bp group by 1) s),
      'sem_profissao', (select count(*) from _bp where prof is null),
      'grupo_black', (select jsonb_object_agg(grupo_black, n) from (select grupo_black, count(*) n from _bp group by 1) s),
      'grupo_consultoria', (select jsonb_object_agg(grupo_consultoria, n) from (select grupo_consultoria, count(*) n from _bp group by 1) s),
      'ultimo_dado_em', (select max(criado_em) from _bt),
      'voltas_dedup', v_volta),
    'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', p.nome, 'email', p.email,
        'telefone', coalesce(p.telefone, p.tel_incompleto),
        'telefone_situacao', case when p.telefone is not null then 'padrao' when p.tel_incompleto is not null then 'incompleto'
                                  when p.fora_motivo is not null then 'fora_do_padrao' else 'sem_telefone' end,
        'telefone_como_veio', case when p.telefone is null then coalesce(p.fora_bruto, p.tel_incompleto) end,
        'motivo', case when p.telefone is not null then null
                       when p.tel_incompleto is not null then 'Número sem o 9 (o grupo só guardou DDD + 8 dígitos)'
                       when p.fora_motivo is not null then p.fora_motivo else 'Sem telefone' end,
        'segmento', case when p.prof in ('advogado', 'estudante_direito') then 'advogado' when p.prof = 'contador' then 'contador' else 'outros' end,
        'sem_profissao', p.prof is null,
        'profissao_detalhe', coalesce(p.prof, 'sem_dado'),
        'grupo_black', p.grupo_black, 'grupo_consultoria', p.grupo_consultoria,
        'saiu_black_de', p.saiu_black_de, 'saiu_consultoria_de', p.saiu_consultoria_de,
        'form_captacao', p.f_captacao, 'form_isca', p.f_isca, 'form_respondi_consultoria', p.f_respondi,
        'form_respondi_consultoria_parcial', p.f_respondi_so_parcial, 'form_pagina_consultoria', p.f_pagina,
        'fontes', to_jsonb(p.fontes), 'primeiro_contato', p.primeiro, 'ultimo_contato', p.ultimo
      ) order by p.primeiro, p.comp) from _bp p), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

CREATE OR REPLACE FUNCTION dados.black_lista_disparo_montar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261013172751: lista de disparo da Black. Um registro por envio/participante, de 5 fontes; pessoa = componente
-- ligado por telefone (8 últimos dígitos) OU e-mail. Teste sai (marcação ou parece_teste). A Turma Especial NÃO sai aqui:
-- é o Apps Script que tira (a planilha da Isabela não entra no banco). Devolve {resumo, pessoas[]}.
declare
  v_chave constant text := 'black-friday-2026-10';
  v_mudou int;
  v_volta int := 0;
  r jsonb;
begin
  drop table if exists pg_temp._r, pg_temp._t, pg_temp._p, pg_temp._k, pg_temp._te;   -- 20261013190000: 2ª chamada na transação
  create temp table _r (
    id bigserial, fonte text not null, criado_em timestamptz, nome text, email text,
    bruto text, dig text, fone8 text, fk text, teste boolean not null default false, comp bigint
  ) on commit drop;

  -- 1. formulários da Black (captação, iscas, página nova da consultoria): a view já normaliza e marca teste
  insert into _r (fonte, criado_em, nome, email, bruto, teste)
  select 'lead:' || l.pagina, l.criado_em, nullif(btrim(l.nome), ''), l.email, nullif(btrim(l.whatsapp), ''),
         coalesce(l.teste, false) or coalesce(l.parece_teste, false)
    from dados.black_leads l
   where l.pagina <> 'consultoria_respondi';   -- 20261013225100: o Respondi já entra pelo ramo próprio abaixo (listas iguais)

  -- 2. Respondi da consultoria (JmSmjBBS); mesma regra de teste da view
  insert into _r (fonte, criado_em, nome, email, bruto, teste)
  select 'respondi:consultoria', x.respondido_em, nullif(btrim(x.dados->>'nome'), ''), nullif(lower(btrim(x.email)), ''),
         nullif(btrim(coalesce(x.dados->>'telefone', x.telefone)), ''),
         dados.teste_ativo(v_chave, x.email, coalesce(x.dados->>'telefone', x.telefone))
         or coalesce(lower(x.email) like '%teste%' or x.dados->>'nome' ilike '%teste%' or lower(x.email) like '%@advmais.com%', false)
    from respondi.respostas x
   where x.form_slug = 'JmSmjBBS'
     -- 20261013183515: resposta incompleta do Respondi só entra com dados.black_lista_config.incluir_respondi_parcial (decisão do
     -- Victor, 13/10: "por enquanto não"); a pessoa continua se tiver outra fonte
     and (not coalesce((x.dados->>'parcial')::boolean, false)
          or coalesce((select c.incluir_respondi_parcial from dados.black_lista_config c where c.id), false));

  -- 3. grupos (os 3 da Black e o da consultoria): foto do SendFlow (número completo quando a foto já o trouxe) ...
  insert into _r (fonte, criado_em, bruto, fone8, fk)
  select case when g.papel = 'lista' then 'grupo:consultoria' else 'grupo:black' end, p.visto_primeiro_em,
         p.numero, p.fone8, p.fone_key
    from dados.grupo_participantes p
    join dados.dashboard_grupos g on g.id = p.grupo_id
   where g.chave = v_chave;
  -- ... e entrada do webhook que a foto nunca viu (só DDD + 8 dígitos)
  insert into _r (fonte, criado_em, fone8, fk)
  select case when g.papel = 'lista' then 'grupo:consultoria' else 'grupo:black' end, min(j.ocorreu_em), right(j.fone_key, 8),
         max(j.fone_key)
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.chave = v_chave and g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
     and not exists (select 1 from dados.grupo_participantes p where p.grupo_id = g.id and p.fone8 = right(j.fone_key, 8))
   group by g.papel, g.sendflow_campanha, right(j.fone_key, 8);

  -- 20261013184806: "where true": o PostgREST do Supabase carrega a safeupdate, que recusa UPDATE sem WHERE (21000)
  update _r set dig = nullif(regexp_replace(coalesce(bruto, ''), '[^0-9]', '', 'g'), '') where true;
  update _r set fone8 = right(dig, 8) where fone8 is null and length(dig) >= 8;

  -- 4. teste no grupo: telefone marcado como teste, ou cujos registros de formulário são TODOS teste (mesma regra do card)
  update _r g set teste = true
   where g.fonte like 'grupo:%'
     and (exists (select 1 from dados.marcacoes_teste m where m.chave = v_chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = g.fone8)
          or (exists (select 1 from _r f where f.fonte not like 'grupo:%' and f.fone8 = g.fone8)
              and not exists (select 1 from _r f where f.fonte not like 'grupo:%' and f.fone8 = g.fone8 and not f.teste)));

  -- 5. pessoa = componente ligado por fone8 ou e-mail (propagação do menor id até parar)
  update _r set comp = id where true;
  loop
    with kf as (select fone8, min(comp) m from _r where fone8 is not null group by fone8),
         ke as (select email, min(comp) m from _r where email is not null group by email),
         novo as (
      select r.id, least(r.comp, coalesce(kf.m, r.comp), coalesce(ke.m, r.comp)) as m
        from _r r left join kf on kf.fone8 = r.fone8 left join ke on ke.email = r.email
    )
    update _r r set comp = novo.m from novo where novo.id = r.id and novo.m < r.comp;
    get diagnostics v_mudou = row_count;
    v_volta := v_volta + 1;
    exit when v_mudou = 0 or v_volta > 50;
  end loop;
  if v_mudou <> 0 then
    raise exception 'black_lista_disparo: dedup não convergiu em 50 voltas';
  end if;

  -- 6. telefone: padrão = 55 + DDD válido + 8 ou 9 dígitos. Sem DDI (10/11 dígitos com DDD válido) ganha o 55.
  --    Foto antiga ou webhook (só DDD + 8): 55 + DDD + 8, marcado como incompleto. O resto vai para "fora do padrão".
  create temp table _t on commit drop as
  select r.*,
         case
           when r.dig is null then null
           when r.dig ~ '^55[0-9]{10,11}$' and exists (select 1 from dados.ddd_uf u where u.ddd = substr(r.dig, 3, 2)) then r.dig
           when r.dig ~ '^[0-9]{10,11}$' and r.dig !~ '^55' and exists (select 1 from dados.ddd_uf u where u.ddd = left(r.dig, 2)) then '55' || r.dig
         end as tel_ok,
         case
           when r.dig is null then null
           when r.dig ~ '^55[0-9]{10,11}$' and exists (select 1 from dados.ddd_uf u where u.ddd = substr(r.dig, 3, 2)) then null
           when r.dig ~ '^[0-9]{10,11}$' and r.dig !~ '^55' and exists (select 1 from dados.ddd_uf u where u.ddd = left(r.dig, 2)) then null
           when r.dig ~ '^55' and length(r.dig) in (12, 13) then 'DDD inválido'
           when length(r.dig) between 11 and 15 and r.dig !~ '^55' then 'DDI fora do Brasil (prefixo ' || left(r.dig, 3) || ')'
           else 'Número com ' || length(r.dig) || ' dígitos'
         end as motivo
    from _r r;

  -- uma passada por agregação (sem subconsulta por linha): custo linear no volume
  -- 20261013190000: Turma Especial sai aqui também (antes só no Apps Script): a pessoa inteira, por e-mail ou telefone
  create temp table _te on commit drop as
  select distinct t.comp from _t t
   where exists (select 1 from dados.turma_especial_chaves k where k.tipo = 'email' and t.email is not null
                   and k.hash = encode(extensions.digest(t.email, 'sha256'), 'hex'))
      or exists (select 1 from dados.turma_especial_chaves k where k.tipo = 'fone8' and t.fone8 is not null
                   and k.hash = encode(extensions.digest(t.fone8, 'sha256'), 'hex'));
  create temp table _p on commit drop as
  with base as (select * from _t where not teste and comp not in (select comp from _te))
  select b.comp,
         (array_agg(b.nome order by b.criado_em desc nulls last, b.id desc) filter (where b.nome is not null))[1] as nome,
         (array_agg(b.email order by b.criado_em desc nulls last, b.id desc) filter (where b.email is not null))[1] as email,
         -- telefone completo de formulário > completo do grupo > incompleto (só DDD + 8) do grupo
         (array_agg(b.tel_ok order by (b.fonte like 'grupo:%'), b.criado_em desc nulls last, b.id desc)
            filter (where b.tel_ok is not null))[1] as telefone,
         (array_agg(b.bruto || '|' || b.motivo order by b.criado_em desc nulls last, b.id desc)
            filter (where b.motivo is not null))[1] as fora,
         (array_agg('55' || b.fk order by b.criado_em desc nulls last, b.id desc)
            filter (where b.dig is null and b.fk ~ '^[0-9]{10}$' and u.ddd is not null))[1] as tel_incompleto,
         array_agg(distinct b.fonte order by b.fonte) as fontes,
         min(b.criado_em) as primeiro
    from base b
    left join dados.ddd_uf u on u.ddd = left(b.fk, 2)
   group by b.comp;
  create temp table _k on commit drop as
  select comp, array_agg(distinct email) filter (where email is not null) as emails,
         array_agg(distinct fone8) filter (where fone8 is not null) as fones8
    from _t group by comp;

  select jsonb_build_object(
    'gerado_em', now(),
    'resumo', jsonb_build_object(
      'registros', (select count(*) from _t),
      'registros_por_fonte', (select jsonb_object_agg(fonte, n) from (select fonte, count(*) n from _t group by fonte) s),
      'pessoas_por_fonte', (select jsonb_object_agg(f, n) from (select f, count(*) n from _p, unnest(fontes) f group by f) s),
      'registros_teste', (select count(*) from _t where teste),
      'pessoas_so_teste', (select count(distinct comp) from _t where comp not in (select comp from _t where not teste)),
      'turma_especial', (select count(*) from _te where comp in (select comp from _t where not teste)),
      'registros_validos', (select count(*) from _t where not teste),
      'pessoas', (select count(*) from _p),
      'duplicados_fundidos', (select count(*) from _t where not teste and comp not in (select comp from _te)) - (select count(*) from _p),
      'lista', (select count(*) from _p where telefone is not null or tel_incompleto is not null or fora is null),
      'fora_do_padrao', (select count(*) from _p where telefone is null and tel_incompleto is null and fora is not null),
      'telefone_incompleto', (select count(*) from _p where telefone is null and tel_incompleto is not null),
      'sem_telefone', (select count(*) from _p where telefone is null and tel_incompleto is null and fora is null),
      'voltas_dedup', v_volta),
    'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
        'aba', case when p.telefone is null and p.tel_incompleto is null and p.fora is not null then 'fora' else 'lista' end,
        'nome', coalesce(p.nome, ''), 'email', coalesce(p.email, ''),
        'telefone', coalesce(p.telefone, p.tel_incompleto, ''),
        'telefone_como_veio', coalesce(split_part(p.fora, '|', 1), ''),
        'motivo', coalesce(split_part(p.fora, '|', 2), ''),
        'emails', coalesce(to_jsonb(k.emails), '[]'::jsonb), 'fones8', coalesce(to_jsonb(k.fones8), '[]'::jsonb),
        'fontes', to_jsonb(p.fontes)) order by p.primeiro, p.comp) from _p p join _k k on k.comp = p.comp), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

revoke execute on function dados.black_base_pessoas() from public, anon, authenticated, service_role;
revoke execute on function dados.black_lista_disparo_montar() from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dados_black_grupo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false, p_recorte jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013225100: devolve também 'grupo_consultoria' (pessoas do recorte que estão no grupo da consultoria, linha à parte do card).
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
  ), gcg as (   -- 20261013225100: grupo da consultoria (papel 'lista', congelado); fica FORA do card, vira linha à parte
    select g.id, g.sendflow_campanha from dados.dashboard_grupos g where g.chave = d.chave and g.papel = 'lista'
  ), gc as (     -- quem está ou esteve no grupo da consultoria, em qualquer data (foto ou entrada do webhook)
    select x.fone8 from (
      select p.fone8 from dados.grupo_participantes p join gcg on gcg.id = p.grupo_id where p.fone8 is not null
      union
      select right(j.fone_key, 8) from crm.evento_jornada j join gcg on gcg.sendflow_campanha = j.tag
       where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null) x
     where p_incluir_teste or x.fone8 not in (select fone8 from tst)
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
    -- 20261013225100: pessoas do recorte (mesmo denominador do card) que estão ou estiveram no grupo da consultoria
    'grupo_consultoria', case when not exists (select 1 from gcg) then null else jsonb_build_object(
        'campanhas', (select jsonb_agg(gcg.sendflow_campanha order by gcg.sendflow_campanha) from gcg),
        'membros', (select count(*) from gc),
        'leads_no_grupo', (select count(*) from pessoa pe where pe.fone8 in (select gc.fone8 from gc)),
        'mql_no_grupo', (select count(*) from pessoa pe where pe.classe in ('advogado', 'contador', 'estudante_direito')
                            and pe.fone8 in (select gc.fone8 from gc))) end,
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

revoke execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) from public, anon, service_role;
grant execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) to authenticated;
