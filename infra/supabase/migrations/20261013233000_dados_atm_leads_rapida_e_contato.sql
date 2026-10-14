-- 20261013233000: dashboard do ATM mais rápido (dados.atm_leads) e dados_atm_leads com contato.ver
--
-- POR QUE: o modal de Leads e o refresh do dashboard do ATM 1 (grupoparticipa.app) demoravam. Medido em 13/10 (~23h30
-- UTC, como master, 2x): dados_atm_resumo, dados_atm_serie_diaria, dados_atm_leads, dados_atm_comparecimento e
-- dados_atm_pos_live ~4,8 s cada; dados_atm_grupo_numeros ~6,0 s. Todas passam por dados.atm_leads. O explain (analyze)
-- do corpo mostrou um LATERAL do grupo rodando 422 vezes a ~10,6 ms: o CTE l era embutido e controle.fone_key(telefone)
-- era recalculado no filtro do grupo para cada par lead x pessoa do grupo.
-- O QUE FAZ:
--  1. dados.atm_leads: "l as materialized" (uma palavra). O fone_key é calculado uma vez por lead. Resultado idêntico
--     (md5 das 423 linhas igual no ensaio); 4,8 s -> ~0,44 s.
--  2. public.dados_atm_leads: exige acesso.tem('contato.ver') (ressalva do pentester de 13/10: devolve nome, e-mail e
--     telefone) e teste só para master, como dados_atm_pre_checkout. A chave de serviço continua passando e com EXECUTE:
--     a TV do dashboard-ht usa (ver o explain).
--  3. public.dados_atm_grupo_numeros: o mesmo "l as materialized" (o fone_key era recalculado no exists por par).
-- AS 5 PERGUNTAS: escala = o custo deixa de ser leads x grupo (422 x 340) e passa a ser linear nos leads; índice = sem
--   índice novo (o ganho é o plano); frequência = a da tela (refresh e modais) e a da TV (cache 5 min), igual; repetição
--   = nenhuma chamada nova; reversão = 20261013233000_reversao.sql (corpos anteriores, com guarda de md5).

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_leads(text)'::regprocedure) <> 'cb6d5a5efd947cfb57d4b2eeb705706c'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_atm_leads(text,date,date,boolean)'::regprocedure) <> 'a5dd1aa19f61477e28b7c5b4f29a771f'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_atm_grupo_numeros(text,date,date,boolean)'::regprocedure) <> '1ca750e0306d2549f803f55960aff98b' then
    raise exception '20261013233000: corpo vivo de dados.atm_leads, dados_atm_leads ou dados_atm_grupo_numeros mudou. Reler a definição viva.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION dados.atm_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean, descarte_motivo text, descarte_lista text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000; teste marcado no evento em 20261008191000; saída da foto (>=) em 20261008200000
  -- 20261013233000: l MATERIALIZED. Sem isso o planner embutia o CTE e recalculava controle.fone_key(t.telefone) dentro
  -- do filtro do grupo para cada par (lead x pessoa do grupo): ~422 x 340 chamadas, 4,8 s. Resultado idêntico (md5).
  with d as (select * from dados.dashboards where chave = p_chave),
  l as materialized (
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
         case when tem.grupo then coalesce(gp.entrou_em is not null and gp.saiu_em >= gp.entrou_em, false) end,
         pf.instrucao is not null, pf.instrucao, pf.turma,
         case when not tem.listas then null
              when lm.l1 and lm.l2 then 'lista_1_e_2'
              when lm.l1 then 'lista_1' when lm.l2 then 'lista_2'
              when ds.motivo is not null then 'descartado'
              else 'fora_das_listas' end,
         case when lm.marcio and lm.elaine then 'marcio_e_elaine'
              when lm.marcio then 'marcio' when lm.elaine then 'elaine' end,
         exists (select 1 from pc where pc.email = l.email),
         case when (select oferta_codigo from d) is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id,
         l.teste or dados.teste_ativo(p_chave, l.email, l.fk),
         case when tem.listas and not coalesce(lm.l1 or lm.l2, false) then ds.motivo end,
         case when tem.listas and not coalesce(lm.l1 or lm.l2, false) then ds.lista end
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
    -- 20261008220000: fora das listas mas na aba Descartados: motivo exato da coluna "Por que saiu" (Lista 1 antes da 2)
    left join lateral (select x.motivo, x.lista from dados.lista_descartes x
                        where x.chave = p_chave
                          and (x.email_norm = l.email or (l.fk is not null and right(x.fone_key, 8) = right(l.fk, 8)))
                        order by x.lista, (x.email_norm = l.email) desc nulls last, x.id limit 1) ds on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
$function$;

revoke execute on function dados.atm_leads(text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dados_atm_leads(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean, descarte_motivo text, descarte_lista text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
-- 20261013233000: contato.ver para quem é usuário (nome, e-mail e telefone saem daqui) e teste só para master, como em
-- dados_atm_pre_checkout. A chave de serviço continua passando (dados.cadastro já a deixa passar): a TV do dashboard-ht
-- (api/seminario-atm.php, campo grupo_leads_sim) chama esta função com ela; tirar o service_role quebra o card da TV.
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_servico boolean := coalesce((select auth.role()), '') = 'service_role';
  v_ini timestamptz; v_fim timestamptz;
begin
  if not v_servico and not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if coalesce(p_incluir_teste, false) and not v_servico and not coalesce(acesso.eh_master(), false) then
    raise exception 'só master vê as pessoas marcadas como teste' using errcode = '42501';
  end if;
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select * from dados.atm_leads(d.chave) x
   where x.primeiro_em >= v_ini and x.primeiro_em < v_fim
     and (coalesce(p_incluir_teste, false) or not x.teste)
   order by x.primeiro_em desc, x.email;
end
$function$;

revoke execute on function public.dados_atm_leads(text, date, date, boolean) from public, anon;
grant execute on function public.dados_atm_leads(text, date, date, boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dados_atm_grupo_numeros(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false)
 RETURNS TABLE(fone_key text, nome text, entrou_em timestamp with time zone, saiu_em timestamp with time zone, no_grupo boolean, eh_lead boolean, teste boolean, teste_motivo text, entrada_aproximada boolean, grupos text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  -- 20261013233000: l MATERIALIZED (o fone_key era recalculado no exists para cada par grupo x lead)
  with l as materialized (select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id from dados.atm_leads(d.chave) x)
  select coalesce(p.fone_key, p.fone8), p.nome, p.entrou_em, p.saiu_em, p.no_grupo,
         exists (select 1 from l where l.fk8 = p.fone8 or (p.pessoa_id is not null and l.pessoa_id = p.pessoa_id)),
         p.teste,
         (select m.motivo from dados.marcacoes_teste m
           where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone' and m.valor = p.fone8),
         p.entrada_aproximada, p.grupos
    from dados.v_grupo_pessoas_todos p
   where p.chave = d.chave
     and p.entrou_em >= v_ini and p.entrou_em < v_fim
     and (coalesce(p_incluir_teste, false) or not p.teste)
   order by p.entrou_em desc, p.fone8;
end
$function$;

revoke execute on function public.dados_atm_grupo_numeros(text, date, date, boolean) from public, anon, service_role;
grant execute on function public.dados_atm_grupo_numeros(text, date, date, boolean) to authenticated;
