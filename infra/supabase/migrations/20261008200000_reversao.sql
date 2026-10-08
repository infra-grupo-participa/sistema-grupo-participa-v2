-- Reversão de 20261008200000 (foto do grupo do SendFlow). Tira o job do pg_cron, volta views e RPCs ao corpo de
-- 20261008191000 (copiado daquele arquivo) e apaga fotos e participantes. A foto guarda telefone e nome do WhatsApp:
-- se o histórico importar, exportar dados.grupo_participantes antes. O segredo sendflow_api_key fica no Vault
-- (apagar à mão com delete from vault.secrets where name = 'sendflow_api_key', se for o caso).
-- Rodada dentro do ensaio 20261008200000_ensaio.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $c$ begin
  if exists (select 1 from cron.job where jobname = 'dados-grupo-foto') then
    perform cron.unschedule('dados-grupo-foto');
  end if;
end $c$;

drop function if exists public.dados_atm_resumo(text, date, date), public.dados_atm_grupo_numeros(text, date, date, boolean);

drop view if exists dados.v_grupo_pessoas;
create view dados.v_grupo_pessoas with (security_invoker = true) as
  SELECT chave, fone8,
    min(ocorreu_em) FILTER (WHERE (tipo = 'entrada'::text)) AS entrou_em,
    max(ocorreu_em) FILTER (WHERE (tipo = 'saida'::text)) AS saiu_em,
    ((array_agg(tipo ORDER BY ocorreu_em DESC, evento_id DESC))[1] = 'entrada'::text) AS no_grupo,
    (array_agg(pessoa_id ORDER BY ocorreu_em DESC) FILTER (WHERE (pessoa_id IS NOT NULL)))[1] AS pessoa_id
   FROM dados.v_grupo_eventos e
  GROUP BY chave, fone8;
revoke all on dados.v_grupo_pessoas from public, anon, authenticated;

create or replace function dados.atm_leads(p_chave text)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
              entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
              lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid,
              teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000; teste marcado no evento em 20261008191000
  with d as (select * from dados.dashboards where chave = p_chave),
  l as (
    select t.*, controle.fone_key(t.telefone) as fk
      from d cross join lateral dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t
  ),
  tem as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = p_chave) as grupo,
           exists (select 1 from dados.lista_membros m where m.chave = p_chave) as listas
  ),
  pc as (select y.email from d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  vd as (select distinct v.email from dados.atm_vendas(p_chave) v where v.email is not null)
  select l.email, l.nome, l.telefone, l.primeiro_em, l.fonte, l.utm_source, l.utm_medium, l.utm_campaign,
         l.utm_content, l.utm_term,
         left(l.fk, 2),
         case when l.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(l.fk, 2)), 'Outros') end,
         case when tem.grupo then coalesce(gp.entrou_em is not null, false) end,
         case when tem.grupo then coalesce(gp.entrou_em is not null and gp.saiu_em > gp.entrou_em, false) end,
         pf.instrucao is not null, pf.instrucao, pf.turma,
         case when not tem.listas then null
              when lm.l1 and lm.l2 then 'lista_1_e_2'
              when lm.l1 then 'lista_1' when lm.l2 then 'lista_2'
              else 'fora_das_listas' end,
         case when lm.marcio and lm.elaine then 'marcio_e_elaine'
              when lm.marcio then 'marcio' when lm.elaine then 'elaine' end,
         exists (select 1 from pc where pc.email = l.email),
         case when (select oferta_codigo from d) is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id,
         l.teste or dados.teste_ativo(p_chave, l.email, l.fk)
    from l cross join tem
    left join lateral (select g.entrou_em, g.saiu_em from dados.v_grupo_pessoas g
                        where g.chave = p_chave and g.entrou_em is not null
                          and ((l.fk is not null and g.fone8 = right(l.fk, 8)) or (l.pessoa_id is not null and g.pessoa_id = l.pessoa_id))
                        order by g.entrou_em limit 1) gp on true
    left join lateral (select bool_or(m.lista = 'lista_1') as l1, bool_or(m.lista = 'lista_2') as l2,
                              bool_or(m.seminario_origem in ('marcio', 'marcio_e_elaine')) as marcio,
                              bool_or(m.seminario_origem in ('elaine', 'marcio_e_elaine')) as elaine
                         from dados.lista_membros m
                        where m.chave = p_chave
                          and (m.email_norm = l.email or (l.fk is not null and right(m.fone_key, 8) = right(l.fk, 8)))) lm on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
$$;

create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
returns boolean language sql stable set search_path = '' as $$
  -- 20261008191000: trava a marcação a quem aparece no dashboard (pentester, M2). p_valor: e-mail minúsculo ou 8 dígitos
  select case p_tipo
    when 'email' then
         exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from dados.v_grupo_eventos_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$$;

create or replace function public.dados_atm_resumo(p_chave text, p_de date default null, p_ate date default null)
returns table(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text,
              disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean,
              grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric,
              custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint,
              pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer,
              compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint,
              receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric,
              atualizado_em timestamp with time zone,
              periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer,
              receita_teste_bruta numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  lt as (select * from dados.atm_leads(d.chave) x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em is not null and g.saiu_em > g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(distinct e.fone8)::int as n from dados.v_grupo_eventos_todos e
     where e.chave = d.chave and e.teste and e.tipo = 'entrada' and e.ocorreu_em >= v_ini and e.ocorreu_em < v_fim
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  k as (select (disp.qtd > 0 and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta from disp)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         case when k.completo and ag.leads > 0 then round(disp.custo::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.bruta * 100 / disp.custo, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.liq * 100 / disp.custo, 2)::numeric(10,2) end,
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
   where pr.id = d.projeto_id;
end
$$;

create or replace function public.dados_atm_serie_diaria(p_chave text, p_de date default null, p_ate date default null)
returns table(dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer, vendas integer,
              receita_bruta numeric, custo_disparo_centavos bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  if v_de is not null and least(coalesce(v_ate, v_hoje), v_hoje) - v_de > 400 then
    raise exception 'período longo demais para a série (máximo 400 dias)' using errcode = '22023';
  end if;
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x
               where not x.teste and x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em >= v_ini and g.entrou_em < v_fim),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em > g.entrou_em
            and g.saiu_em >= v_ini and g.saiu_em < v_fim),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_pre_checkout(d.chave) y
          where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda
           from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ds as (select (coalesce(x.enviado_em, x.criado_em) at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x
          where x.projeto_id = d.projeto_id and x.arquivado_em is null
            and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim),
  lim as (
    select coalesce(v_de, least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                                (select min(dia) from tx), (select min(dia) from ds))) as de,
           least(coalesce(v_ate, v_hoje), v_hoje) as ate
  )
  select s::date,
         (select count(*)::int from ld where ld.dia = s::date),
         case when v_tem_grupo then (select count(*)::int from ge where ge.dia = s::date) end,
         case when v_tem_grupo then (select count(*)::int from gs where gs.dia = s::date) end,
         (select count(*)::int from pc where pc.dia = s::date),
         case when d.oferta_codigo is not null then (select count(*)::int from tx where tx.dia = s::date) end,
         case when d.oferta_codigo is not null then
           (select coalesce(sum(tx.valor_bruto), 0)::numeric(14,2) from tx where tx.dia = s::date and tx.moeda = 'BRL') end,
         (select case when count(*) filter (where ds.custo_centavos is null) = 0 then sum(ds.custo_centavos)::bigint end
            from ds where ds.dia = s::date having count(*) > 0)
    from lim
    cross join lateral generate_series(lim.de, lim.ate, interval '1 day') s
   where lim.de is not null and lim.de <= lim.ate
   order by 1;
end
$$;

create or replace function public.dados_atm_grupo_numeros(p_chave text, p_de date default null, p_ate date default null,
                                                          p_incluir_teste boolean default false)
returns table(fone_key text, nome text, entrou_em timestamp with time zone, saiu_em timestamp with time zone,
              no_grupo boolean, eh_lead boolean, teste boolean, teste_motivo text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with p as (
    select e.fone8,
           (array_agg(e.fone_key order by e.ocorreu_em desc, e.evento_id desc))[1] as fone_key,
           (array_agg(e.nome order by e.ocorreu_em desc) filter (where e.nome is not null))[1] as nome,
           min(e.ocorreu_em) filter (where e.tipo = 'entrada') as entrou_em,
           max(e.ocorreu_em) filter (where e.tipo = 'saida') as saiu_em,
           (array_agg(e.tipo order by e.ocorreu_em desc, e.evento_id desc))[1] = 'entrada' as no_grupo,
           (array_agg(e.pessoa_id order by e.ocorreu_em desc) filter (where e.pessoa_id is not null))[1] as pessoa_id,
           bool_or(e.teste) as teste
      from dados.v_grupo_eventos_todos e
     where e.chave = d.chave
     group by e.fone8
  ),
  l as (select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id from dados.atm_leads(d.chave) x)
  select p.fone_key, p.nome, p.entrou_em, p.saiu_em, p.no_grupo,
         exists (select 1 from l where l.fk8 = p.fone8 or (p.pessoa_id is not null and l.pessoa_id = p.pessoa_id)),
         p.teste,
         (select m.motivo from dados.marcacoes_teste m
           where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone' and m.valor = p.fone8)
    from p
   where p.entrou_em >= v_ini and p.entrou_em < v_fim
     and (coalesce(p_incluir_teste, false) or not p.teste)
   order by p.entrou_em desc, p.fone_key;
end
$$;

drop view if exists dados.v_grupo_pessoas_todos;
drop function if exists dados.grupo_foto_ciclo(), dados.grupo_foto_processar(bigint, text);
drop table if exists dados.grupo_participantes;
drop table if exists dados.grupo_fotos;
alter table dados.dashboard_grupos drop column if exists sendflow_conta_id;
alter table dados.dashboard_grupos drop column if exists sendflow_release_id;

revoke all on function dados.atm_leads(text), dados.atm_pertence(text, text, text) from public, anon, authenticated;
revoke all on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                       public.dados_atm_grupo_numeros(text, date, date, boolean)
  from public, anon, service_role;
grant execute on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                          public.dados_atm_grupo_numeros(text, date, date, boolean)
  to authenticated;

notify pgrst, 'reload schema';
