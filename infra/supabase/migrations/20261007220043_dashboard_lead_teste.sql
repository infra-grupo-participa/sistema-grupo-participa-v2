-- 20261007te: marcar/desmarcar lead do pré-checkout como TESTE pelo dashboard presencial (card 17tya50fkx9).
--
-- STATUS: APLICADA em produção em 07/10/2026 às 22:00 UTC, versão 20261007220043 (nome dashboard_lead_teste, era
-- 20261007te), depois da aprovação do pentester e dos ajustes dele, com a linha em supabase_migrations.schema_migrations na
-- mesma transação; md5 gravado = 7c94ffd507ab723430c72d063f459c6c = este arquivo antes desta troca de STATUS.
-- Ensaio: 20261007220043_ensaio.sql. Relatório: 20261007220043.explain.md.
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
--   AJUSTES DO PENTESTER (07/10, antes de aplicar): pessoas.atual() nos dois joins do pré-checkout e na RPC (pessoa
--   mesclada: marca, loga e lista na pessoa final); prova de pertença do ActiveCampaign com os filtros da lista.
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
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)   -- pessoa final, se foi mesclada
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'pre_checkout'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista do dashboard)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)   -- pessoa final, se foi mesclada
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
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
  v_pessoa uuid;
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
  v_pessoa := pessoas.atual(p_pessoa_id);   -- marca e loga na pessoa final, se foi mesclada
  -- a pessoa tem de ser um pré-checkout deste dashboard (mesmas duas fontes e filtros de dados.pre_checkout_todos)
  if not exists (select 1 from pessoas.eventos e
                  where e.tipo = 'pre_checkout'
                    and (e.projeto_id = d.projeto_id or e.detalhe ->> 'chave_evento' = d.chave)
                    and pessoas.atual(e.pessoa_id) = v_pessoa)
     and not exists (select 1 from crm.evento_jornada j
                      where d.lista_ac is not null and j.lista = d.lista_ac
                        and j.email_norm is not null and nullif(btrim(j.email_norm), '') is not null
                        and lower(btrim(j.email_norm)) not like '%@exemplo.invalid'
                        and pessoas.atual(j.pessoa_id) = v_pessoa) then
    raise exception 'pessoa não é pré-checkout deste dashboard' using errcode = 'P0002';
  end if;

  select p.teste into v_antes from pessoas.pessoas p where p.id = v_pessoa for update;
  if not found then
    raise exception 'pessoa não encontrada' using errcode = 'P0002';
  end if;
  if coalesce(v_antes, false) = p_teste then
    return query select v_pessoa, p_teste, false;
    return;
  end if;

  update pessoas.pessoas p set teste = p_teste, atualizado_em = now() where p.id = v_pessoa;
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values (v_autor, 'pessoas.pessoas', case when p_teste then 'marcar_teste' else 'desmarcar_teste' end, null,
          jsonb_build_object('pessoa_id', v_pessoa, 'teste', coalesce(v_antes, false)),
          jsonb_build_object('pessoa_id', v_pessoa, 'pessoa_id_recebido', p_pessoa_id, 'teste', p_teste, 'dashboard', d.chave, 'via', 'dados_presencial_marcar_teste'));
  return query select v_pessoa, p_teste, true;
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
