-- 20261013200000: lista de quem preencheu o pré-checkout da Sessão de Viabilidade (modal do card "Pré-checkout" do ATM)
--
-- STATUS: APLICADA em produção em 13/10/2026 (ok do Victor), versão 20261013200000, com a linha em
-- supabase_migrations.schema_migrations na mesma transação; md5 gravado = 5a68a9a110ec297553210d03df8a3347 = este arquivo antes desta
-- troca de STATUS. Escrita e ensaiada (BEGIN ... ROLLBACK) em 13/10/2026.
-- Ensaio: 20261013200000_ensaio.sql. Reversão: 20261013200000_reversao.sql. Situação e prova: 20261013200000.explain.md.
-- Depende de 20261008191000 (marcação de teste), 20261008161000 (dados.atm_leads) e 20261007180503 (schema acesso), já aplicadas.
-- Ao aplicar pelo MCP, a versão é gravada pelo relógio: renomear os 4 arquivos para a versão de schema_migrations.
--
-- POR QUE (Seminário ATM, chave atm-elaine-1-2026-10)
--   O card "Pré-checkout" mostra dados_atm_resumo.pre_checkout_pessoas, mas não há RPC com a LISTA dessas pessoas.
--   O modal precisa das mesmas abas do modal de Leads (pessoas, grupo, evolução, resumo), então o contrato é o de
--   public.dados_atm_leads, mais eh_lead (a pessoa está na lista de leads da edição, dados.leads_todos).
--
-- O QUE FAZ
--   public.dados_atm_pre_checkout(p_chave text, p_de date, p_ate date, p_incluir_teste boolean), só leitura, nova
--   (nenhuma função existente muda, nenhuma tabela nova).
--   Linhas: dados.pre_checkout_todos(chave, projeto_id, lista_ac), a mesma fonte do card (dados.atm_pre_checkout =
--   dados.pre_checkout = pre_checkout_todos sem pessoa teste, menos dados.teste_ativo). Uma linha por e-mail.
--   primeiro_em, nome, telefone, fonte, utm_*, pessoa_id: os do pré-checkout (não os da captação do lead).
--   teste = pessoa teste OR dados.teste_ativo(chave, email, telefone), igual ao corte do card; p_incluir_teste=false
--   tira essas linhas, e a contagem no período = dados_atm_resumo.pre_checkout_pessoas.
--   ddd, estado, entrou_grupo, saiu_grupo, eh_aluno, instrucao, turma, lista_origem, seminario_origem, comprou,
--   descarte_motivo, descarte_lista: as MESMAS expressões de dados.atm_leads (20261008161000/191000/200000/220000),
--   aplicadas à pessoa do pré-checkout pelo telefone (controle.fone_key), pessoa_id e e-mail. São fatos da pessoa, não
--   do cadastro como lead, por isso valem também para quem não é lead. no_pre_checkout é sempre true.
--   Período como dados_atm_leads (dados.periodo; nulos = período do cadastro), filtro por primeiro_em.
--   Ordem: primeiro_em desc, email.
--   Acesso, nesta ordem (igual a public.dados_atm_sv_vendas):
--     1. dados.atm_cadastro: equipe e dashboard ativo do modelo seminario-atm (42501 / P0002);
--     2. acesso.tem('contato.ver'): sem ela, 42501 (a linha tem nome, e-mail e telefone);
--     3. p_incluir_teste = true só para master (acesso.eh_master); os outros, 42501.
--   Grants: revoke de public, anon e service_role; execute só para authenticated; pós-condição no fim do arquivo.
--
-- AS 5 PERGUNTAS
--   escala: custo fixo de dados.leads_todos (~130 ms, 399 leads em 13/10) e dados.pre_checkout_todos, mais os laterais
--           por pessoa (listas, descartes, perfil). O grupo é lido 1 vez (CTE materializada) em vez de por linha.
--           Medido no ensaio (2x): ATM 1 hoje, 1 pessoa, 141 ms; com 400 pessoas no pré-checkout, 331 ms
--           (dados_atm_leads, mesma massa, 4.298 ms). Ver explain.md.
--   índice: nada novo. Listas usam lista_membros_email_idx + lista_membros_fone8_idx (BitmapOr, plano medido, 142 ms
--           para 400 pessoas); descartes tem lista_descartes_email_idx/fone_idx (42 ms para 400, plano não colado).
--   frequência: uma chamada por abertura/atualização do modal (mesma cadência de dados_atm_leads).
--   repetição: leads_todos roda 1 vez por chamada (CTE), não por linha.
--   reversão: 20261013200000_reversao.sql (drop da função; nada mais foi criado).
--
-- IDEMPOTENTE: create or replace; revoke/grant repetíveis.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['dados.atm_cadastro(text)', 'dados.periodo(date,date,date,date)',
                           'dados.pre_checkout_todos(text,bigint,text)', 'dados.leads_todos(text,bigint,text)',
                           'dados.atm_vendas(text)', 'dados.teste_ativo(text,text,text)', 'dados.perfil(text)',
                           'controle.fone_key(text)', 'acesso.tem(text)', 'acesso.eh_master()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  foreach v in array array['dados.dashboard_grupos', 'dados.v_grupo_pessoas', 'dados.lista_membros',
                           'dados.lista_descartes', 'dados.ddd_uf'] loop
    if to_regclass(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null
     and not exists (select 1 from pg_description c
                      where c.objoid = to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)')
                        and c.description like '%20261013200000%') then
    raise exception 'premissa: public.dados_atm_pre_checkout já existe e não é desta migration';
  end if;
end
$g$;

-- 1. A lista
create or replace function public.dados_atm_pre_checkout(p_chave text, p_de date default null, p_ate date default null,
                                                         p_incluir_teste boolean default false)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
              entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text,
              seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean,
              descarte_motivo text, descarte_lista text, eh_lead boolean)
language plpgsql stable security definer set search_path = '' as $$
-- 20261013200000: quem preencheu o pré-checkout (fonte do card), com os atributos de dados.atm_leads e eh_lead.
-- Sem acesso ao dashboard ou sem contato.ver: 42501. Teste só para master.
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_teste boolean := coalesce(p_incluir_teste, false);
  v_ini timestamptz; v_fim timestamptz;
begin
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if v_teste and not coalesce(acesso.eh_master(), false) then
    raise exception 'só master vê as pessoas marcadas como teste' using errcode = '42501';
  end if;
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with pc as materialized (
    -- mesmo corte de teste de dados.atm_pre_checkout (pessoa teste; marcação pelo e-mail ou pelo telefone como veio)
    -- materialized: fone_key calculado 1 vez por pessoa (inlinado, era recalculado dentro do filtro do grupo, por linha)
    select y.email, y.nome, y.telefone, y.primeiro_em, y.fonte, y.utm_source, y.utm_medium, y.utm_campaign,
           y.utm_content, y.utm_term, y.pessoa_id, controle.fone_key(y.telefone) as fk,
           coalesce(y.teste, false) or coalesce(dados.teste_ativo(d.chave, y.email, y.telefone), false) as eh_teste
      from dados.pre_checkout_todos(d.chave, d.projeto_id, d.lista_ac) y
     where y.primeiro_em >= v_ini and y.primeiro_em < v_fim
  ),
  l as (select * from pc where v_teste or not pc.eh_teste),
  tem as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as grupo,
           exists (select 1 from dados.lista_membros m where m.chave = d.chave) as listas
  ),
  -- grupo lido 1 vez por chamada (em dados.atm_leads a view é refeita por linha: ~10 ms por pessoa, medido no ensaio);
  -- o predicado e a ordem do lateral abaixo são os de dados.atm_leads
  gq as materialized (
    select g.fone8, g.pessoa_id, g.entrou_em, g.saiu_em from dados.v_grupo_pessoas g
     where g.chave = d.chave and g.entrou_em is not null
  ),
  ld as (select distinct x.email from dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) x),
  vd as (select distinct v.email from dados.atm_vendas(d.chave) v where v.email is not null)
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
         true,
         case when d.oferta_codigo is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id,
         l.eh_teste,
         case when tem.listas and not coalesce(lm.l1 or lm.l2, false) then ds.motivo end,
         case when tem.listas and not coalesce(lm.l1 or lm.l2, false) then ds.lista end,
         exists (select 1 from ld where ld.email = l.email)
    from l cross join tem
    left join lateral (select g.entrou_em, g.saiu_em from gq g
                        where ((l.fk is not null and g.fone8 = right(l.fk, 8)) or (l.pessoa_id is not null and g.pessoa_id = l.pessoa_id))
                        order by g.entrou_em limit 1) gp on true
    left join lateral (select bool_or(m.lista = 'lista_1') as l1, bool_or(m.lista = 'lista_2') as l2,
                              bool_or(m.seminario_origem in ('marcio', 'marcio_e_elaine')) as marcio,
                              bool_or(m.seminario_origem in ('elaine', 'marcio_e_elaine')) as elaine
                         from dados.lista_membros m
                        where m.chave = d.chave
                          and (m.email_norm = l.email or (l.fk is not null and right(m.fone_key, 8) = right(l.fk, 8)))) lm on true
    left join lateral (select x.motivo, x.lista from dados.lista_descartes x
                        where x.chave = d.chave
                          and (x.email_norm = l.email or (l.fk is not null and right(x.fone_key, 8) = right(l.fk, 8)))
                        order by x.lista, (x.email_norm = l.email) desc nulls last, x.id limit 1) ds on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
   order by l.primeiro_em desc, l.email;
end
$$;
comment on function public.dados_atm_pre_checkout(text, date, date, boolean) is
  'Lista de quem preencheu o pré-checkout do ATM (fonte do card pre_checkout_pessoas) com o contrato de dados_atm_leads + eh_lead. Acesso ao dashboard + contato.ver; p_incluir_teste só master. 20261013200000.';

revoke all on function public.dados_atm_pre_checkout(text, date, date, boolean) from public, anon, service_role;
grant execute on function public.dados_atm_pre_checkout(text, date, date, boolean) to authenticated;

-- pós-condição: authenticated executa; anon, service_role e PUBLIC não; security definer com search_path vazio
do $p$
declare f constant text := 'public.dados_atm_pre_checkout(text,date,date,boolean)';
begin
  if not has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('anon', f, 'execute')
     or has_function_privilege('service_role', f, 'execute')
     or exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
                 where p.oid = f::regprocedure and a.grantee = 0) then
    raise exception 'pós-condição: grant errado em %', f;
  end if;
  if not (select p.prosecdef and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = f::regprocedure) then
    raise exception 'pós-condição: % não é security definer com search_path vazio', f;
  end if;
end
$p$;

notify pgrst, 'reload schema';
