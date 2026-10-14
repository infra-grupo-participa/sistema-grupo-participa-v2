-- 20261013225200: entrou_grupo_em do dashboard da Black passa a contar só os grupos da Black
--
-- POR QUE: public.dados_black_perfil lia dados.v_grupo_pessoas_todos, que junta TODOS os grupos da chave, inclusive o da
-- consultoria (dashboard_grupos.papel = 'lista', congelado, 464 pessoas). Tudo o que a tela calcula com entrou_grupo_em
-- (taxa de grupo em 48h, funil do criativo, Histórico, tabela de leads) contava a entrada no grupo da consultoria. Medido
-- em 13/10: 134 MQL "no grupo" pelo perfil x 97 só no grupo da Black. Migration aprovada pelo Victor em 13/10 (21h): o
-- grupo da consultoria não conta em nada; sem campo novo para ele.
-- O QUE FAZ: troca só o CTE g (a origem de entrou_grupo_em e entrada_grupo_aproximada) por grupos papel = 'dashboard',
-- com a mesma regra da view. Assinatura, colunas e ACL iguais.
-- AS 5 PERGUNTAS: escala = eventos do webhook dos 3 grupos da Black (tag) + foto dos 3 grupos (em vez da view de todos os
--   grupos da chave: lê menos); índice = os mesmos que a view usava (crm.evento_jornada por tag, grupo_participantes por
--   grupo); frequência e repetição = as da tela, nenhuma chamada nova; reversão = 20261013225200_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_perfil(text,date,date,boolean)'::regprocedure) <> '9813b62c190f3dfee29b8169008ca8da' then
    raise exception '20261013225200: corpo vivo de dados_black_perfil mudou. Reler a definição viva.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_perfil(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false)
 RETURNS TABLE(lead_id text, pessoa_id text, criado_em timestamp with time zone, primeira_porta boolean, pagina text, porta text, isca text, campanha_id text, conjunto_id text, anuncio_id text, canal text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, profissao text, profissao_bruta text, mql boolean, uf text, entrou_grupo_em timestamp with time zone, entrada_grupo_aproximada boolean, teste boolean, parece_teste boolean, a_corrigir text[], campos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);   -- 42501 sem acesso, P0002 fora do cadastro ou outro modelo
  v_de timestamptz := (coalesce(p_de, d.periodo_inicio)::timestamp at time zone 'America/Sao_Paulo');
  v_ate timestamptz := ((coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp at time zone 'America/Sao_Paulo');
  v_sal text := gen_random_uuid()::text;   -- pessoa_id só vale dentro desta resposta
begin
  return query
  with l as (
    select l.*, dados.teste_ativo(d.chave, l.email, l.whatsapp) as t,
           row_number() over (partition by l.pessoa_chave order by l.criado_em, l.lead_id) = 1 as primeira
      from dados.black_leads l
  ), g as (
    -- 20261013225200: só os grupos da Black (dashboard_grupos.papel = 'dashboard'). Antes lia dados.v_grupo_pessoas_todos,
    -- que junta todos os grupos da chave, e contava a entrada no grupo da consultoria (papel 'lista') como entrada no
    -- grupo (decisão do Victor, 13/10: o grupo da consultoria não conta em nada). Mesma regra da view: entrada pelo
    -- webhook; sem ela, a 1ª vez visto na foto (limitada pela saída do webhook) e marcada como aproximada.
    with gd as (
      select x.id, x.sendflow_campanha from dados.dashboard_grupos x where x.chave = d.chave and x.papel = 'dashboard'
    ), ev as (
      select right(j.fone_key, 8) as fone8,
             min(j.ocorreu_em) filter (where j.tipo = 'entrada') as entrou_em,
             max(j.ocorreu_em) filter (where j.tipo = 'saida') as saiu_em
        from crm.evento_jornada j join gd on gd.sendflow_campanha = j.tag
       where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null
       group by right(j.fone_key, 8)
    ), fo as (
      select p.fone8, min(p.visto_primeiro_em) as visto
        from dados.grupo_participantes p join gd on gd.id = p.grupo_id
       where p.fone8 is not null
       group by p.fone8
    ), u as (
      select coalesce(ev.fone8, fo.fone8) as fone8,
             coalesce(ev.entrou_em, case when fo.fone8 is not null then least(fo.visto, ev.saiu_em) end) as entrou_em,
             (ev.entrou_em is null and fo.visto is not null) as aprox
        from ev full join fo on fo.fone8 = ev.fone8
    )
    select u.fone8, u.entrou_em, case when u.entrou_em is not null then u.aprox end as aprox
      from u
  )
  select l.lead_id, md5(v_sal || l.pessoa_chave), l.criado_em, l.primeira, l.pagina, l.porta, l.isca,
         l.campanha_id, l.conjunto_id, l.anuncio_id, l.canal,
         l.utm_source, l.utm_medium, l.utm_campaign, l.utm_content, l.utm_term,
         l.profissao_classe, l.profissao, l.mql, l.uf,
         g.entrou_em, g.aprox,
         l.t, l.parece_teste, l.a_corrigir, l.campos
    from l
    left join g on g.fone8 = l.fone8
   where l.criado_em >= v_de and l.criado_em < v_ate
     and (p_incluir_teste or not l.t)
   order by l.criado_em, l.lead_id;
end
$function$;

revoke execute on function public.dados_black_perfil(text, date, date, boolean) from public, anon, service_role;
grant execute on function public.dados_black_perfil(text, date, date, boolean) to authenticated;
