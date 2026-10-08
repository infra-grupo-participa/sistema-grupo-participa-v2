-- Reversão de 20261008191000 (marcar como teste e período). Volta funções e views ao corpo de 20261008161000, copiado
-- de pg_get_functiondef no banco em 08/10/2026 antes da aplicação. Apaga as marcações (a tabela inteira) e as colunas
-- de período: a auditoria de quem marcou se perde; EXPORTAR dados.marcacoes_teste antes de rodar (pentester, B4).
-- Rodada dentro do ensaio 20261008191000_ensaio.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                        public.dados_atm_leads(text, date, date, boolean), public.dados_atm_disparos_canais(text, date, date),
                        public.dados_atm_grupo_numeros(text, date, date, boolean),
                        public.dados_marcar_teste(text, text, text, text), public.dados_desmarcar_teste(text, text, text),
                        public.dados_testes(text);

create or replace view dados.v_grupo_eventos with (security_invoker = true) as
  SELECT g.chave, j.id AS evento_id, j.tipo, j.fone_key, "right"(j.fone_key, 8) AS fone8, j.ocorreu_em, j.pessoa_id
   FROM (crm.evento_jornada j JOIN dados.dashboard_grupos g ON ((g.sendflow_campanha = j.tag)))
  WHERE ((j.fonte = 'sendflow'::text) AND (j.tipo = ANY (ARRAY['entrada'::text, 'saida'::text])) AND (j.fone_key IS NOT NULL));
drop view if exists dados.v_grupo_eventos_todos;

-- dados.atm_leads (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION dados.atm_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000
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
         l.pessoa_id, l.teste
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
$function$
;

-- dados.atm_vendas (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION dados.atm_vendas(p_chave text)
 RETURNS TABLE(transacao text, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_aprovado date, moeda text, valor_bruto numeric, valor_liquido numeric, email text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000
  select t.transacao, t.pedido_em, t.aprovado_em, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido, t.email
    from dados.dashboards d
    cross join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
   where d.chave = p_chave and d.oferta_codigo is not null
     and t.pago and t.primeira
     and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
$function$
;

-- public.dados_atm_resumo (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_resumo(p_chave text)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ),
  ld as (select * from dados.atm_leads(d.chave) where not teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em is not null)::int as entradas,
           count(*) filter (where g.entrou_em is not null and g.saiu_em > g.entrou_em)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  pc as (select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  ag as (
    select (select count(*)::int from ld) as leads,
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
         now()
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join k
   where pr.id = d.projeto_id;
end
$function$
;

-- public.dados_atm_serie_diaria (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_serie_diaria(p_chave text)
 RETURNS TABLE(dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer, vendas integer, receita_bruta numeric, custo_disparo_centavos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x where not x.teste),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em > g.entrou_em),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
           from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda from dados.atm_vendas(d.chave) v),
  ds as (select (x.enviado_em at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x where x.projeto_id = d.projeto_id and x.arquivado_em is null),
  lim as (
    select least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                 (select min(dia) from tx), (select min(dia) from ds)) as de
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
    cross join lateral generate_series(lim.de, (now() at time zone 'America/Sao_Paulo')::date, interval '1 day') s
   where lim.de is not null
   order by 1;
end
$function$
;

-- public.dados_atm_leads (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query select * from dados.atm_leads(d.chave) x order by x.primeiro_em desc, x.email;
end
$function$
;

-- public.dados_atm_disparos_canais (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_disparos_canais(p_chave text)
 RETURNS TABLE(canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer, falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
   group by c.ordem, c.canal
   order by c.ordem;
end
$function$
;

-- public.dados_atm_comparecimento (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_comparecimento(p_chave text)
 RETURNS TABLE(sessao_id uuid, tipo text, inicio timestamp with time zone, fim timestamp with time zone, pico_audiencia integer, equipe_na_sala integer, total_leads integer, total_grupo integer, presentes integer, presentes_leads integer, presentes_grupo integer, pico_sobre_leads_pct numeric, pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric, vendas integer, conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select x.email, controle.fone_key(x.telefone) as fk from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select g.fone8 from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  tot as (select (select count(*)::int from ld) as leads,
                 case when v_tem_grupo then (select count(*)::int from gp) end as grupo),
  ss as (
    select s.*, lead(s.inicio) over (order by s.inicio) as proxima
      from dados.sessoes s where s.chave = d.chave
  ),
  pr as (
    -- presente = pessoa fora da equipe; é lead se casa por e-mail ou telefone; é do grupo se o telefone (dele ou do
    -- lead casado pelo e-mail) entrou no grupo
    select p.sessao_id,
           count(*)::int as presentes,
           count(*) filter (where m.eh_lead)::int as p_leads,
           count(*) filter (where exists (select 1 from gp where gp.fone8 = coalesce(right(p.fone_key, 8), m.fk8)))::int as p_grupo
      from dados.sessao_presencas p
      left join lateral (select true as eh_lead, right(ld.fk, 8) as fk8 from ld
                          where ld.email = p.email_norm
                             or (p.fone_key is not null and right(ld.fk, 8) = right(p.fone_key, 8))
                          order by (ld.email = p.email_norm) desc nulls last limit 1) m on true
     where p.sessao_id in (select id from ss) and not p.eh_equipe
     group by p.sessao_id
  ),
  tx as (select v.aprovado_em from dados.atm_vendas(d.chave) v)
  select ss.id, ss.tipo, ss.inicio, ss.fim, ss.pico_audiencia, ss.equipe_na_sala, tot.leads, tot.grupo,
         pr.presentes, pr.p_leads, case when v_tem_grupo then pr.p_grupo end,
         case when tot.leads > 0 then round(ss.pico_audiencia::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(ss.pico_audiencia::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when tot.leads > 0 then round(pr.p_leads::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when v_tem_grupo and tot.grupo > 0 then round(pr.p_grupo::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         vs.n,
         case when tot.leads > 0 then round(vs.n::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(vs.n::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when ss.pico_audiencia > 0 then round(vs.n::numeric * 100 / ss.pico_audiencia, 2)::numeric(7,2) end
    from ss cross join tot
    left join pr on pr.sessao_id = ss.id
    cross join lateral (
      select case when d.oferta_codigo is null then null
                  else (select count(*)::int from tx
                         where tx.aprovado_em >= ss.inicio
                           and tx.aprovado_em < coalesce(ss.proxima, d.ciclo_fecha_em, now())) end as n
    ) vs
   order by ss.inicio;
end
$function$
;

-- public.dados_atm_pos_live (corpo de 20261008161000)
CREATE OR REPLACE FUNCTION public.dados_atm_pos_live(p_chave text)
 RETURNS TABLE(ciclo text, ate timestamp with time zone, vendas integer, compradores integer, receita_bruta numeric, receita_liquida numeric, conversao_pct numeric, conversao_grupo_pct numeric, conversao_pre_checkout_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select count(*)::int as n from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select case when v_tem_grupo then count(*)::int end as n
           from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  pc as (select count(*)::int as n from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  c as (select 'fechado'::text as ciclo, 1 as ordem, d.ciclo_fecha_em as ate
        union all select 'aberto', 2, now())
  select c.ciclo, c.ate, a.vendas, a.comp, a.bruta, a.liq,
         case when ld.n > 0 then round(a.comp::numeric * 100 / ld.n, 2)::numeric(7,2) end,
         case when gp.n > 0 then round(a.comp::numeric * 100 / gp.n, 2)::numeric(7,2) end,
         case when pc.n > 0 then round(a.comp::numeric * 100 / pc.n, 2)::numeric(7,2) end
    from c cross join ld cross join gp cross join pc
    cross join lateral (
      select case when d.oferta_codigo is null or c.ate is null then null else count(*)::int end as vendas,
             case when d.oferta_codigo is null or c.ate is null then null else count(distinct tx.email)::int end as comp,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_bruto) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as bruta,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_liquido) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as liq
        from tx where c.ate is not null and tx.aprovado_em <= c.ate
    ) a
   order by c.ordem;
end
$function$
;

drop function if exists dados.atm_pertence(text, text, text), dados.atm_vendas_todas(text),
                        dados.atm_pre_checkout(text), dados.teste_ativo(text, text, text),
                        dados.periodo(date, date, date, date);
drop table if exists dados.marcacoes_teste;
alter table dados.dashboards drop constraint if exists dashboards_periodo_check;
alter table dados.dashboards drop column if exists periodo_fim;
alter table dados.dashboards drop column if exists periodo_inicio;

revoke all on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                       public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                       public.dados_atm_pos_live(text) from public, anon;
grant execute on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                          public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                          public.dados_atm_pos_live(text) to authenticated;
revoke all on function dados.atm_leads(text), dados.atm_vendas(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
