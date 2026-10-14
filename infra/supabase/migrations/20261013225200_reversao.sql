-- Reversão de 20261013225200: dados_black_perfil volta a ler dados.v_grupo_pessoas_todos (todos os grupos da chave).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  -- pentester 13/10: só reverte se o corpo vivo ainda for o desta migration (senão sobrescreveria outra mudança)
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_perfil(text,date,date,boolean)'::regprocedure) <> 'f6aadcc5a8ceebad73d0c4a291c3daf1' then
    raise exception 'reversão de 20261013225200: corpo vivo de dados_black_perfil não é o desta migration. Reler.';
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
    select e.fone8, min(e.entrou_em) as entrou_em, bool_or(e.entrada_aproximada) filter (where e.entrou_em is not null) as aprox
      from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave
     group by e.fone8
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
