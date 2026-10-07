-- Ensaio de 20261007te (marcar lead do pré-checkout como teste): foto antes, 2 passadas, marcar/desmarcar como master,
-- recusas (não master, anon, pessoa de fora, nulo), reversão. Transação desfeita: nada persiste.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_build_object(
  'resumo_pc', (select r.pre_checkout_pessoas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'resumo_conv', (select r.conversao_pct from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select count(*) from public.dados_presencial_leads('clinica-miami-2026-12')),
  'leads_cols', (select md5(string_agg((to_jsonb(x) - 'pessoa_id' - 'teste')::text, '|' order by x.email)) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  
  'serie_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'vendas_no_pc', (select count(*) filter (where v.no_pre_checkout) from public.dados_presencial_vendas('clinica-miami-2026-12') v),
  'log', (select count(*) from acesso.log where tabela = 'pessoas.pessoas'),
  'pessoas_teste', (select count(*) from pessoas.pessoas where teste))::text;
select set_config('request.jwt.claims', '{}', true);

-- passada 1
-- 20261007te: marcar/desmarcar lead do pré-checkout como TESTE pelo dashboard presencial (card 17tya50fkx9).
--
-- STATUS: NÃO APLICADA. Cria RPC com GRANT e escreve em pessoas.pessoas: só aplica depois do pentester e da ordem do Maestro.
--
-- POR QUE
--   Pedido do Victor Hugo (07/10/2026, noite): no modal de pré-checkout da Clínica de Miami, marcar a pessoa como teste
--   para ela parar de contar em tudo que tem pré-checkout no dashboard, sem sumir da lista (aparece apagada, para
--   desmarcar). Usa o campo que já existe, pessoas.pessoas.teste (decisão do Victor: vale para o sistema inteiro).
--
-- COMO O PRÉ-CHECKOUT LIGA À PESSOA (fonte)
--   dados.pre_checkout junta duas passagens: pessoas.eventos (tipo pre_checkout, coluna pessoa_id, sempre preenchida) e
--   crm.evento_jornada (entrada na lista do ActiveCampaign do dashboard, coluna pessoa_id, pode ser nula). A lista agrupa
--   por e-mail. Na Clínica (07/10): 2 pré-checkouts, os 2 do ActiveCampaign (lista 614), os 2 com pessoa_id.
--
-- O QUE FAZ
--   1. dados.pre_checkout_todos(chave, projeto, lista): as mesmas linhas de dados.pre_checkout, SEM tirar teste, mais
--      pessoa_id e teste. teste = alguma pessoa ligada àquele e-mail está marcada; pessoa_id = a marcada (se houver),
--      senão a da passagem mais recente. Sem pessoa ligada: pessoa_id nulo (não dá para marcar pela tela).
--   2. dados.pre_checkout (assinatura e colunas iguais) passa a ser: pre_checkout_todos sem quem é teste. Quem já usa
--      (resumo, série diária, série de vendas, lista de vendas) passa a ignorar o e-mail inteiro marcado.
--      Antes, só a passagem da pessoa marcada saía; o e-mail ainda contava se tivesse outra passagem de pessoa não marcada.
--   3. public.dados_presencial_leads ganha, no fim, pessoa_id uuid e teste boolean (drop + create: muda o tipo de
--      retorno; colunas anteriores iguais e na mesma ordem; grants refeitos iguais).
--   4. public.dados_presencial_marcar_teste(chave, pessoa_id, teste): só master (acesso.eh_master()), senão 42501.
--      A pessoa tem de ser um pré-checkout desse dashboard (P0002 se não for). Atualiza pessoas.pessoas.teste e grava em
--      acesso.log (autor = quem marcou, quando, antes/depois só com id e teste, sem dado pessoal). Reversível: teste=false.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha por clique. índice: pessoas.pessoas pela PK; prova de pertença pelas mesmas tabelas do pré-checkout.
--   frequência: clique manual de master. repetição: idempotente (mesmo valor não grava nem loga). reversão: desmarcar pela
--   própria RPC; a migration volta pelo rollback-teste.sql.
--
-- IDEMPOTENTE: create or replace; drop if exists só da dados_presencial_leads (recriada na mesma transação).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.pre_checkout(text,bigint,text)') is null or to_regprocedure('acesso.eh_master()') is null
     or to_regprocedure('acesso.eu()') is null or to_regclass('acesso.log') is null then
    raise exception '20261007te: premissas ausentes (dados.pre_checkout, acesso.eh_master, acesso.eu, acesso.log)';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'pessoas' and table_name = 'pessoas'
        and column_name in ('id', 'teste', 'atualizado_em')) <> 3 then
    raise exception '20261007te: pessoas.pessoas sem id/teste/atualizado_em';
  end if;
end
$g$;

-- 0. Corpos de antes guardados
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007te'
  from pg_proc p
 where p.oid in ('dados.pre_checkout(text,bigint,text)'::regprocedure, 'public.dados_presencial_leads(text)'::regprocedure)
   and p.prosrc !~ '20261007te'
on conflict do nothing;

-- 1. Pré-checkout com pessoa e marca de teste (sem filtrar)
create or replace function dados.pre_checkout_todos(p_chave text, p_projeto_id bigint, p_lista text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261007te
  with passagens as (
    -- sistema (rota /api/captura/lead → pessoas.registrar)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = e.pessoa_id
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id = e.pessoa_id and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id = e.pessoa_id and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'pre_checkout'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista do dashboard)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = j.pessoa_id
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id = j.pessoa_id and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.lista = p_lista and j.email_norm is not null
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
$function$;
revoke all on function dados.pre_checkout_todos(text, bigint, text) from public, anon, authenticated, service_role;

-- 2. O pré-checkout que conta: sem quem é teste (assinatura igual)
create or replace function dados.pre_checkout(p_chave text, p_projeto_id bigint, p_lista text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text)
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261007te: pre_checkout_todos sem quem está marcado como teste
  select t.email, t.nome, t.telefone, t.primeiro_em, t.fonte, t.utm_source, t.utm_medium, t.utm_campaign, t.utm_content,
         t.utm_term
    from dados.pre_checkout_todos(p_chave, p_projeto_id, p_lista) t
   where not t.teste
$function$;
revoke all on function dados.pre_checkout(text, bigint, text) from public, anon, authenticated, service_role;

-- 3. Lista do modal: todo mundo, com pessoa_id e teste no fim
drop function if exists public.dados_presencial_leads(text);
create function public.dados_presencial_leads(p_chave text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, instrucao text, turma text,
               comprou boolean, pessoa_id uuid, teste boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  -- 20261007te: quem é teste continua na lista (teste = true) e não conta nos números
  return query
  with pagos as (select distinct t.email from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago)
  select pc.email, pc.nome, pc.telefone, pc.primeiro_em, pc.fonte, pc.utm_source, pc.utm_medium, pc.utm_campaign,
         pc.utm_content, pc.utm_term, pf.instrucao, pf.turma,
         exists (select 1 from pagos g where g.email = pc.email),
         pc.pessoa_id, pc.teste
    from dados.pre_checkout_todos(d.chave, d.projeto_id, d.lista_ac) pc
    left join lateral dados.perfil(pc.email) pf on true
   order by pc.primeiro_em desc;
end
$function$;
revoke all on function public.dados_presencial_leads(text) from public, anon;
grant execute on function public.dados_presencial_leads(text) to authenticated, service_role;

-- 4. Marcar/desmarcar (só master)
create or replace function public.dados_presencial_marcar_teste(p_chave text, p_pessoa_id uuid, p_teste boolean)
 returns table(pessoa_id uuid, teste boolean, alterado boolean)
 language plpgsql
 volatile security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_autor uuid := acesso.eu();
  d dados.dashboards;
  v_antes boolean;
begin
  if v_autor is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_pessoa_id is null or p_teste is null then
    raise exception 'pessoa e teste são obrigatórios' using errcode = '22023';
  end if;
  select * into d from dados.dashboards x where x.chave = p_chave and x.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  -- a pessoa tem de ser um pré-checkout deste dashboard (mesmas duas fontes de dados.pre_checkout_todos)
  if not exists (select 1 from pessoas.eventos e
                  where e.pessoa_id = p_pessoa_id and e.tipo = 'pre_checkout'
                    and (e.projeto_id = d.projeto_id or e.detalhe ->> 'chave_evento' = d.chave))
     and not exists (select 1 from crm.evento_jornada j
                      where j.pessoa_id = p_pessoa_id and d.lista_ac is not null and j.lista = d.lista_ac) then
    raise exception 'pessoa não é pré-checkout deste dashboard' using errcode = 'P0002';
  end if;

  select p.teste into v_antes from pessoas.pessoas p where p.id = p_pessoa_id for update;
  if not found then
    raise exception 'pessoa não encontrada' using errcode = 'P0002';
  end if;
  if coalesce(v_antes, false) = p_teste then
    return query select p_pessoa_id, p_teste, false;
    return;
  end if;

  update pessoas.pessoas p set teste = p_teste, atualizado_em = now() where p.id = p_pessoa_id;
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values (v_autor, 'pessoas.pessoas', case when p_teste then 'marcar_teste' else 'desmarcar_teste' end, null,
          jsonb_build_object('pessoa_id', p_pessoa_id, 'teste', coalesce(v_antes, false)),
          jsonb_build_object('pessoa_id', p_pessoa_id, 'teste', p_teste, 'dashboard', d.chave, 'via', 'dados_presencial_marcar_teste'));
  return query select p_pessoa_id, p_teste, true;
end
$function$;
revoke all on function public.dados_presencial_marcar_teste(text, uuid, boolean) from public, anon, service_role;
grant execute on function public.dados_presencial_marcar_teste(text, uuid, boolean) to authenticated;

-- Pós-condição
do $c$
begin
  if has_function_privilege('anon', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or has_function_privilege('anon', 'public.dados_presencial_leads(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_presencial_leads(text)', 'execute')
     or not has_function_privilege('service_role', 'public.dados_presencial_leads(text)', 'execute')
     or has_function_privilege('service_role', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or has_function_privilege('authenticated', 'dados.pre_checkout_todos(text,bigint,text)', 'execute')
     or has_function_privilege('anon', 'dados.pre_checkout_todos(text,bigint,text)', 'execute') then
    raise exception '20261007te: permissões erradas';
  end if;
  if not (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
           where p.oid = 'public.dados_presencial_marcar_teste(text,uuid,boolean)'::regprocedure) then
    raise exception '20261007te: marcar_teste sem security definer/search_path';
  end if;
end
$c$;

-- passada 2
-- 20261007te: marcar/desmarcar lead do pré-checkout como TESTE pelo dashboard presencial (card 17tya50fkx9).
--
-- STATUS: NÃO APLICADA. Cria RPC com GRANT e escreve em pessoas.pessoas: só aplica depois do pentester e da ordem do Maestro.
--
-- POR QUE
--   Pedido do Victor Hugo (07/10/2026, noite): no modal de pré-checkout da Clínica de Miami, marcar a pessoa como teste
--   para ela parar de contar em tudo que tem pré-checkout no dashboard, sem sumir da lista (aparece apagada, para
--   desmarcar). Usa o campo que já existe, pessoas.pessoas.teste (decisão do Victor: vale para o sistema inteiro).
--
-- COMO O PRÉ-CHECKOUT LIGA À PESSOA (fonte)
--   dados.pre_checkout junta duas passagens: pessoas.eventos (tipo pre_checkout, coluna pessoa_id, sempre preenchida) e
--   crm.evento_jornada (entrada na lista do ActiveCampaign do dashboard, coluna pessoa_id, pode ser nula). A lista agrupa
--   por e-mail. Na Clínica (07/10): 2 pré-checkouts, os 2 do ActiveCampaign (lista 614), os 2 com pessoa_id.
--
-- O QUE FAZ
--   1. dados.pre_checkout_todos(chave, projeto, lista): as mesmas linhas de dados.pre_checkout, SEM tirar teste, mais
--      pessoa_id e teste. teste = alguma pessoa ligada àquele e-mail está marcada; pessoa_id = a marcada (se houver),
--      senão a da passagem mais recente. Sem pessoa ligada: pessoa_id nulo (não dá para marcar pela tela).
--   2. dados.pre_checkout (assinatura e colunas iguais) passa a ser: pre_checkout_todos sem quem é teste. Quem já usa
--      (resumo, série diária, série de vendas, lista de vendas) passa a ignorar o e-mail inteiro marcado.
--      Antes, só a passagem da pessoa marcada saía; o e-mail ainda contava se tivesse outra passagem de pessoa não marcada.
--   3. public.dados_presencial_leads ganha, no fim, pessoa_id uuid e teste boolean (drop + create: muda o tipo de
--      retorno; colunas anteriores iguais e na mesma ordem; grants refeitos iguais).
--   4. public.dados_presencial_marcar_teste(chave, pessoa_id, teste): só master (acesso.eh_master()), senão 42501.
--      A pessoa tem de ser um pré-checkout desse dashboard (P0002 se não for). Atualiza pessoas.pessoas.teste e grava em
--      acesso.log (autor = quem marcou, quando, antes/depois só com id e teste, sem dado pessoal). Reversível: teste=false.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha por clique. índice: pessoas.pessoas pela PK; prova de pertença pelas mesmas tabelas do pré-checkout.
--   frequência: clique manual de master. repetição: idempotente (mesmo valor não grava nem loga). reversão: desmarcar pela
--   própria RPC; a migration volta pelo rollback-teste.sql.
--
-- IDEMPOTENTE: create or replace; drop if exists só da dados_presencial_leads (recriada na mesma transação).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.pre_checkout(text,bigint,text)') is null or to_regprocedure('acesso.eh_master()') is null
     or to_regprocedure('acesso.eu()') is null or to_regclass('acesso.log') is null then
    raise exception '20261007te: premissas ausentes (dados.pre_checkout, acesso.eh_master, acesso.eu, acesso.log)';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'pessoas' and table_name = 'pessoas'
        and column_name in ('id', 'teste', 'atualizado_em')) <> 3 then
    raise exception '20261007te: pessoas.pessoas sem id/teste/atualizado_em';
  end if;
end
$g$;

-- 0. Corpos de antes guardados
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007te'
  from pg_proc p
 where p.oid in ('dados.pre_checkout(text,bigint,text)'::regprocedure, 'public.dados_presencial_leads(text)'::regprocedure)
   and p.prosrc !~ '20261007te'
on conflict do nothing;

-- 1. Pré-checkout com pessoa e marca de teste (sem filtrar)
create or replace function dados.pre_checkout_todos(p_chave text, p_projeto_id bigint, p_lista text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261007te
  with passagens as (
    -- sistema (rota /api/captura/lead → pessoas.registrar)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = e.pessoa_id
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id = e.pessoa_id and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id = e.pessoa_id and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'pre_checkout'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista do dashboard)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = j.pessoa_id
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id = j.pessoa_id and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.lista = p_lista and j.email_norm is not null
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
$function$;
revoke all on function dados.pre_checkout_todos(text, bigint, text) from public, anon, authenticated, service_role;

-- 2. O pré-checkout que conta: sem quem é teste (assinatura igual)
create or replace function dados.pre_checkout(p_chave text, p_projeto_id bigint, p_lista text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text)
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261007te: pre_checkout_todos sem quem está marcado como teste
  select t.email, t.nome, t.telefone, t.primeiro_em, t.fonte, t.utm_source, t.utm_medium, t.utm_campaign, t.utm_content,
         t.utm_term
    from dados.pre_checkout_todos(p_chave, p_projeto_id, p_lista) t
   where not t.teste
$function$;
revoke all on function dados.pre_checkout(text, bigint, text) from public, anon, authenticated, service_role;

-- 3. Lista do modal: todo mundo, com pessoa_id e teste no fim
drop function if exists public.dados_presencial_leads(text);
create function public.dados_presencial_leads(p_chave text)
 returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, instrucao text, turma text,
               comprou boolean, pessoa_id uuid, teste boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  -- 20261007te: quem é teste continua na lista (teste = true) e não conta nos números
  return query
  with pagos as (select distinct t.email from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago)
  select pc.email, pc.nome, pc.telefone, pc.primeiro_em, pc.fonte, pc.utm_source, pc.utm_medium, pc.utm_campaign,
         pc.utm_content, pc.utm_term, pf.instrucao, pf.turma,
         exists (select 1 from pagos g where g.email = pc.email),
         pc.pessoa_id, pc.teste
    from dados.pre_checkout_todos(d.chave, d.projeto_id, d.lista_ac) pc
    left join lateral dados.perfil(pc.email) pf on true
   order by pc.primeiro_em desc;
end
$function$;
revoke all on function public.dados_presencial_leads(text) from public, anon;
grant execute on function public.dados_presencial_leads(text) to authenticated, service_role;

-- 4. Marcar/desmarcar (só master)
create or replace function public.dados_presencial_marcar_teste(p_chave text, p_pessoa_id uuid, p_teste boolean)
 returns table(pessoa_id uuid, teste boolean, alterado boolean)
 language plpgsql
 volatile security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_autor uuid := acesso.eu();
  d dados.dashboards;
  v_antes boolean;
begin
  if v_autor is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_pessoa_id is null or p_teste is null then
    raise exception 'pessoa e teste são obrigatórios' using errcode = '22023';
  end if;
  select * into d from dados.dashboards x where x.chave = p_chave and x.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  -- a pessoa tem de ser um pré-checkout deste dashboard (mesmas duas fontes de dados.pre_checkout_todos)
  if not exists (select 1 from pessoas.eventos e
                  where e.pessoa_id = p_pessoa_id and e.tipo = 'pre_checkout'
                    and (e.projeto_id = d.projeto_id or e.detalhe ->> 'chave_evento' = d.chave))
     and not exists (select 1 from crm.evento_jornada j
                      where j.pessoa_id = p_pessoa_id and d.lista_ac is not null and j.lista = d.lista_ac) then
    raise exception 'pessoa não é pré-checkout deste dashboard' using errcode = 'P0002';
  end if;

  select p.teste into v_antes from pessoas.pessoas p where p.id = p_pessoa_id for update;
  if not found then
    raise exception 'pessoa não encontrada' using errcode = 'P0002';
  end if;
  if coalesce(v_antes, false) = p_teste then
    return query select p_pessoa_id, p_teste, false;
    return;
  end if;

  update pessoas.pessoas p set teste = p_teste, atualizado_em = now() where p.id = p_pessoa_id;
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values (v_autor, 'pessoas.pessoas', case when p_teste then 'marcar_teste' else 'desmarcar_teste' end, null,
          jsonb_build_object('pessoa_id', p_pessoa_id, 'teste', coalesce(v_antes, false)),
          jsonb_build_object('pessoa_id', p_pessoa_id, 'teste', p_teste, 'dashboard', d.chave, 'via', 'dados_presencial_marcar_teste'));
  return query select p_pessoa_id, p_teste, true;
end
$function$;
revoke all on function public.dados_presencial_marcar_teste(text, uuid, boolean) from public, anon, service_role;
grant execute on function public.dados_presencial_marcar_teste(text, uuid, boolean) to authenticated;

-- Pós-condição
do $c$
begin
  if has_function_privilege('anon', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or has_function_privilege('anon', 'public.dados_presencial_leads(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_presencial_leads(text)', 'execute')
     or not has_function_privilege('service_role', 'public.dados_presencial_leads(text)', 'execute')
     or has_function_privilege('service_role', 'public.dados_presencial_marcar_teste(text,uuid,boolean)', 'execute')
     or has_function_privilege('authenticated', 'dados.pre_checkout_todos(text,bigint,text)', 'execute')
     or has_function_privilege('anon', 'dados.pre_checkout_todos(text,bigint,text)', 'execute') then
    raise exception '20261007te: permissões erradas';
  end if;
  if not (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
           where p.oid = 'public.dados_presencial_marcar_teste(text,uuid,boolean)'::regprocedure) then
    raise exception '20261007te: marcar_teste sem security definer/search_path';
  end if;
end
$c$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois (ninguém marcado)', jsonb_build_object(
  'resumo_pc', (select r.pre_checkout_pessoas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'resumo_conv', (select r.conversao_pct from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select count(*) from public.dados_presencial_leads('clinica-miami-2026-12')),
  'leads_cols', (select md5(string_agg((to_jsonb(x) - 'pessoa_id' - 'teste')::text, '|' order by x.email)) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_teste', (select count(*) filter (where x.teste) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_com_pessoa', (select count(x.pessoa_id) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'serie_vendas_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout || ':' || coalesce(s.conversao_pct::text, 'null')) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'serie_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'vendas_no_pc', (select count(*) filter (where v.no_pre_checkout) from public.dados_presencial_vendas('clinica-miami-2026-12') v),
  'log', (select count(*) from acesso.log where tabela = 'pessoas.pessoas'),
  'pessoas_teste', (select count(*) from pessoas.pessoas where teste))::text;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
create temp table _z_a (id uuid) on commit drop; insert into _z_a select (select x.pessoa_id from public.dados_presencial_leads('clinica-miami-2026-12') x order by x.primeiro_em limit 1);
create temp table _z_fora (id uuid) on commit drop; insert into _z_fora select p.id from pessoas.pessoas p where p.id not in (select pessoa_id from crm.evento_jornada where lista='614' and pessoa_id is not null) and not exists (select 1 from pessoas.eventos e where e.pessoa_id=p.id and e.tipo='pre_checkout') limit 1;
grant all on pg_temp._z_a, pg_temp._z_fora to authenticated, anon;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"b65dc9c1-8edb-4e7a-ae07-681555523093","role":"authenticated"}', true);
create temp table if not exists _z_alvo (id uuid) on commit drop;
set local role authenticated;
do $t$ declare r text; begin
  begin perform * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), true); r := 'passou'; exception when others then r := sqlstate || ' ' || sqlerrm; end;
  insert into pg_temp._z_out (passo, linha) values ('3 não master (esperado 42501)', r);
end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"role":"anon"}', true);
create temp table if not exists _z_alvo (id uuid) on commit drop;
set local role anon;
do $t$ declare r text; begin
  begin perform * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), true); r := 'passou'; exception when others then r := sqlstate || ' ' || sqlerrm; end;
  insert into pg_temp._z_out (passo, linha) values ('4 anon (esperado 42501)', r);
end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
create temp table if not exists _z_alvo (id uuid) on commit drop;
set local role authenticated;
do $t$ declare r text; begin
  begin perform * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_fora), true); r := 'passou'; exception when others then r := sqlstate || ' ' || sqlerrm; end;
  insert into pg_temp._z_out (passo, linha) values ('5 pessoa de fora do dashboard (esperado P0002)', r);
end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
create temp table if not exists _z_alvo (id uuid) on commit drop;
set local role authenticated;
do $t$ declare r text; begin
  begin perform * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), null); r := 'passou'; exception when others then r := sqlstate || ' ' || sqlerrm; end;
  insert into pg_temp._z_out (passo, linha) values ('6 teste nulo (esperado 22023)', r);
end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '7 marcar como master', (select to_jsonb(x) - 'pessoa_id' from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), true) x)::text;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '8 depois de marcar', jsonb_build_object(
  'resumo_pc', (select r.pre_checkout_pessoas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'resumo_conv', (select r.conversao_pct from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select count(*) from public.dados_presencial_leads('clinica-miami-2026-12')),
  'leads_cols', (select md5(string_agg((to_jsonb(x) - 'pessoa_id' - 'teste')::text, '|' order by x.email)) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_teste', (select count(*) filter (where x.teste) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_com_pessoa', (select count(x.pessoa_id) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'serie_vendas_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout || ':' || coalesce(s.conversao_pct::text, 'null')) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'serie_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'vendas_no_pc', (select count(*) filter (where v.no_pre_checkout) from public.dados_presencial_vendas('clinica-miami-2026-12') v),
  'log', (select count(*) from acesso.log where tabela = 'pessoas.pessoas'),
  'pessoas_teste', (select count(*) from pessoas.pessoas where teste))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select '8b log', (select jsonb_build_object('autor_e_victor', l.autor = '81d2eaee-cce1-4058-8714-439b0fc6f970', 'acao', l.acao, 'antes', l.antes - 'pessoa_id', 'depois', l.depois - 'pessoa_id', 'mesma_pessoa', (l.depois->>'pessoa_id')::uuid = (select id from pg_temp._z_a), 'tem_quando', l.quando is not null) from acesso.log l where l.tabela='pessoas.pessoas' order by l.id desc limit 1)::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '9 marcar de novo (sem mudança)', (select to_jsonb(x) - 'pessoa_id' from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), true) x)::text;
insert into pg_temp._z_out (passo, linha) select '10 desmarcar', (select to_jsonb(x) - 'pessoa_id' from public.dados_presencial_marcar_teste('clinica-miami-2026-12', (select id from pg_temp._z_a), false) x)::text;
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '11 depois de desmarcar', jsonb_build_object(
  'resumo_pc', (select r.pre_checkout_pessoas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'resumo_conv', (select r.conversao_pct from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select count(*) from public.dados_presencial_leads('clinica-miami-2026-12')),
  'leads_cols', (select md5(string_agg((to_jsonb(x) - 'pessoa_id' - 'teste')::text, '|' order by x.email)) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_teste', (select count(*) filter (where x.teste) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'leads_com_pessoa', (select count(x.pessoa_id) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'serie_vendas_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout || ':' || coalesce(s.conversao_pct::text, 'null')) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'serie_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'vendas_no_pc', (select count(*) filter (where v.no_pre_checkout) from public.dados_presencial_vendas('clinica-miami-2026-12') v),
  'log', (select count(*) from acesso.log where tabela = 'pessoas.pessoas'),
  'pessoas_teste', (select count(*) from pessoas.pessoas where teste))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select 'desmarcar volta igual (menos o log)', ((select linha::jsonb - 'log' from pg_temp._z_out where passo='2 depois (ninguém marcado)') = (select linha::jsonb - 'log' from pg_temp._z_out where passo='11 depois de desmarcar'))::text;
insert into pg_temp._z_out (passo, linha) select 'acoes no log', (select jsonb_agg(acao order by id) from acesso.log where tabela='pessoas.pessoas')::text;
-- reversão da migration
-- o log é só acréscimo (acesso.tg_log_imutavel): as linhas de marcação ficam como histórico
do $r$ begin
  drop function if exists public.dados_presencial_marcar_teste(text, uuid, boolean);
  drop function if exists public.dados_presencial_leads(text);
  execute (select definicao from acesso.corpo_antes where migration = '20261007te' and alvo in ('public.dados_presencial_leads(text)', 'dados_presencial_leads(text)'));
  revoke all on function public.dados_presencial_leads(text) from public, anon;
  grant execute on function public.dados_presencial_leads(text) to authenticated, service_role;
  execute (select definicao from acesso.corpo_antes where migration = '20261007te' and alvo = 'dados.pre_checkout(text,bigint,text)');
  drop function if exists dados.pre_checkout_todos(text, bigint, text);
  delete from acesso.corpo_antes where migration = '20261007te';
end $r$;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '12 depois da reversão', jsonb_build_object(
  'resumo_pc', (select r.pre_checkout_pessoas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'resumo_conv', (select r.conversao_pct from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select count(*) from public.dados_presencial_leads('clinica-miami-2026-12')),
  'leads_cols', (select md5(string_agg((to_jsonb(x) - 'pessoa_id' - 'teste')::text, '|' order by x.email)) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  
  'serie_pc', (select jsonb_agg(s.dia || ':' || s.pre_checkout) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pre_checkout > 0),
  'vendas_no_pc', (select count(*) filter (where v.no_pre_checkout) from public.dados_presencial_vendas('clinica-miami-2026-12') v),
  'log', (select count(*) from acesso.log where tabela = 'pessoas.pessoas'),
  'pessoas_teste', (select count(*) from pessoas.pessoas where teste))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select 'reversão volta igual', ((select linha::jsonb - 'log' from pg_temp._z_out where passo='1 antes') = (select linha::jsonb - 'log' from pg_temp._z_out where passo='12 depois da reversão'))::text;
insert into pg_temp._z_out (passo, linha) select 'grant leads depois da reversão', (select array_to_string(proacl, ',') from pg_proc where oid='public.dados_presencial_leads(text)'::regprocedure);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
