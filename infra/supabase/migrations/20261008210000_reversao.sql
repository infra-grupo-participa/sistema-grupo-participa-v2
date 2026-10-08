-- Reversão de 20261008210000 e 20261008210100 (UTM do AC). Tira o job e o gatilho, volta dados.leads_todos ao corpo de
-- 20261008161000 (copiado do banco em 08/10/2026) e apaga fila, UTMs e a coluna de campos.
-- Rodada dentro do ensaio 20261008210000_ensaio.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $c$ begin
  if exists (select 1 from cron.job where jobname = 'dados-ac-utm') then
    perform cron.unschedule('dados-ac-utm');
  end if;
end $c$;

drop trigger if exists evento_jornada_ac_utm on crm.evento_jornada;

create or replace function dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000
  with passagens as (
    -- sistema (rota /api/captura/lead -> pessoas.registrar, tipo lead)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'lead'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista de leads da edição)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.fonte = 'activecampaign' and j.lista = p_lista and j.email_norm is not null
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term, x.pessoa_id, x.teste
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term,
         (select y.pessoa_id from limpo y where y.email = l.email and y.pessoa_id is not null
           order by y.teste desc, y.quando desc limit 1),
         bool_or(l.teste)
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y where y.email = l.email and y.fonte = 'sistema'
                        order by y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$function$
;
revoke all on function dados.leads_todos(text, bigint, text) from public, anon, authenticated;

drop function if exists dados.ac_utm_ciclo(), dados.tg_ac_utm_enfileirar();
drop table if exists dados.ac_utm_fila;
drop table if exists dados.ac_utm;
alter table dados.dashboards drop column if exists ac_campos_utm;
drop function if exists dados.ac_campos_validos(jsonb);
