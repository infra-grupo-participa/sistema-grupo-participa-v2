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
