-- 20261007p: schema dados, cadastro de dashboards e as 5 funções do modelo "evento presencial para a base"
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007161809 (nome dados_dashboard_presencial, era 20261007p), pelo aplica_sql.py aplicar
-- + insert em supabase_migrations.schema_migrations na mesma transação. md5 gravado = f5fd92e174d158e1f159f1a2e01a3b6c = este arquivo
-- antes desta troca de STATUS. Ensaio: 20261007161809_ensaio.sql. Relatório: 20261007161809.explain.md.
-- Contrato com a tela (pacote B): docs/dashboard-presencial.md §2. Mudar coluna, tipo ou ordem quebra a tela.
--
-- POR QUE
--   O Victor Hugo pediu (07/10/2026) o dashboard da Clínica de Miami em Infra > Dados, e que ele vire o modelo de evento
--   presencial vendido para a base: o próximo evento ganha a tela com um insert em dados.dashboards, sem código novo.
--   Fontes: pré-checkout (pessoas.eventos tipo pre_checkout + crm.evento_jornada da lista do ActiveCampaign), vendas da
--   oferta na Hotmart (fin.hotmart_transacoes na forma da trava fin.trava_conta_hotmart), disparos (mkt_mensageria),
--   instrução e turma (public.thb_alunos, public.thb_turmas). Não usa o schema kpi (é do Painel).
--
-- O QUE FAZ
--   1. schema dados (sem uso para anon/authenticated: só as funções public.dados_presencial_* leem, como dono).
--   2. dados.dashboards (RLS ligada, sem policy, sem grant) + o cadastro da Clínica (clinica-miami-2026-12, projeto 68,
--      conta academy, oferta mjzv4v0s, lista 614).
--   3. dados.pode_ver(chave): dashboard ativo + public.gp_eh_equipe() (perfil ativo @advmais.com; decisão do Victor:
--      toda a equipe por enquanto).
--   4. Ajudantes internos (sem grant): dados.transacoes, dados.pre_checkout, dados.perfil.
--   5. public.dados_presencial_resumo/leads/vendas/disparos/serie_diaria(p_chave): security definer, search_path '',
--      execute só para authenticated. Ordem: não é equipe → 42501; chave fora de dados.dashboards ativa → P0002.
--
-- REGRAS (de onde vem cada número; detalhe em docs/dashboard-presencial.md)
--   pessoa = e-mail único (lower(btrim)). Teste fica de fora: pessoas.pessoas.teste = true e e-mail @exemplo.invalid.
--   pré-checkout: evento pre_checkout do projeto (projeto_id ou detalhe.chave_evento = chave) + entrada na lista do
--     ActiveCampaign (crm.evento_jornada.lista, qualquer tipo). UTMs: da primeira passagem PELO SISTEMA (o ActiveCampaign
--     não traz UTM), via pessoas.origens.
--   venda paga: status APPROVED/COMPLETE (grupo pago, igual a fin.vw_transacoes_contas), 1ª cobrança (recorrencia nula
--     ou 1). Receita: só BRL, bruto = coalesce(valor_base, bruto_json base, valor_cobrado) e líquido =
--     coalesce(liquido_produtor, bruto - taxa_hotmart), como mkt_trafego.receita_vendas.
--   custo: só mkt_mensageria.disparos.custo_centavos (real). Nulo = não lançado; custo estimado não entra.
--
-- AS 5 PERGUNTAS
--   escala: hoje 1 lead, 1 pedido, 0 disparo do projeto. Com milhares de leads, as funções agregam por 1 projeto,
--     1 oferta e 1 lista; os índices usados estão no explain. frequência: dezenas de aberturas por dia, sem refresh
--     automático. repetição: 2 chamadas ao abrir (resumo, serie_diaria); leads/vendas/disparos sob demanda.
--   índice: nenhum novo nesta migration (explain no relatório).
--   reversão: bloco REVERSÃO no fim (drop das funções e do schema).
--
-- IDEMPOTENTE: create … if not exists / create or replace / on conflict do nothing. Guarda aborta se dados.dashboards
--   existir com colunas diferentes ou se as funções de apoio (gp_eh_equipe) sumirem.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- 0. Guarda de premissa
do $g$
begin
  if to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261007p: public.gp_eh_equipe() não existe';
  end if;
  if (select id from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12') is distinct from 68 then
    raise exception '20261007p: clinica-miami-2026-12 não é mais o projeto 68. Conferir.';
  end if;
  if to_regclass('dados.dashboards') is not null and (
       select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
        where table_schema = 'dados' and table_name = 'dashboards')
     is distinct from 'chave,modelo,projeto_id,conta_hotmart,oferta_codigo,lista_ac,ativo,criado_em' then
    raise exception '20261007p: dados.dashboards já existe com outras colunas. Conferir.';
  end if;
end
$g$;

-- 1. Schema
create schema if not exists dados;
revoke all on schema dados from public, anon, authenticated;
comment on schema dados is 'Dashboards por modelo (Infra > Dados). Só as funções public.dados_* leem. 20261007p.';

-- 2. Cadastro dos dashboards
create table if not exists dados.dashboards (
  chave          text primary key check (chave ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  modelo         text not null check (modelo in ('presencial-base')),
  projeto_id     bigint not null references mkt.projetos(id),
  conta_hotmart  text not null check (conta_hotmart in ('academy', 'escritorio')),
  oferta_codigo  text not null check (oferta_codigo ~ '^[a-z0-9]{4,20}$'),
  lista_ac       text,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now()
);
alter table dados.dashboards enable row level security;
revoke all on dados.dashboards from public, anon, authenticated;
comment on table dados.dashboards is 'Um dashboard por chave da casa (mkt.projetos.etiqueta_clickup). Novo evento do mesmo modelo = 1 insert. 20261007p.';

insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, ativo)
values ('clinica-miami-2026-12', 'presencial-base', 68, 'academy', 'mjzv4v0s', '614', true)
on conflict (chave) do nothing;

-- 3. Gate
create or replace function dados.pode_ver(p_chave text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  select exists (select 1 from dados.dashboards d where d.chave = p_chave and d.ativo)
         and coalesce(public.gp_eh_equipe(), false)
$f$;
revoke all on function dados.pode_ver(text) from public, anon, authenticated;

-- 4. Ajudantes internos (rodam como o dono, chamados só pelas funções públicas)

-- 4.1 Transações da oferta na conta do dashboard (forma exigida pela trava do Financeiro: conta = variável)
create or replace function dados.transacoes(p_conta text, p_oferta text)
returns table (transacao text, status text, status_grupo text, pago boolean, primeira boolean, pedido_em timestamptz,
               aprovado_em timestamptz, dia_pedido date, dia_aprovado date, moeda text, valor_bruto numeric,
               valor_liquido numeric, email text, nome text, telefone text, estado text)
language plpgsql
stable
set search_path = ''
as $f$
#variable_conflict use_column
declare
  v_conta text := p_conta;
begin
  return query
  select t.transacao, t.status,
         case when t.status in ('APPROVED', 'COMPLETE') then 'pago'
              when t.status in ('REFUNDED', 'PARTIALLY_REFUNDED', 'CHARGEBACK') then 'estornado'
              when t.status in ('OVERDUE', 'PROTESTED') then 'atrasado'
              when t.status in ('PRINTED_BILLET', 'WAITING_PAYMENT', 'UNDER_ANALISYS', 'STARTED') then 'em_aberto'
              when t.status in ('CANCELLED', 'NO_FUNDS', 'BLOCKED') then 'recusado'
              when t.status = 'EXPIRED' then 'expirado'
              else 'outro' end,
         t.status in ('APPROVED', 'COMPLETE'),
         coalesce(t.recorrencia, 1) = 1,
         t.pedido_em, t.aprovado_em,
         (t.pedido_em at time zone 'America/Sao_Paulo')::date,
         (t.aprovado_em at time zone 'America/Sao_Paulo')::date,
         coalesce(t.moeda, 'BRL'),
         b.bruto::numeric(14,2),
         coalesce(t.liquido_produtor, b.bruto - coalesce(t.taxa_hotmart, 0))::numeric(14,2),
         nullif(lower(btrim(t.comprador_email)), ''),
         nullif(btrim(t.comprador_nome), ''),
         nullif(btrim(t.comprador_telefone), ''),
         nullif(btrim(t.comprador_uf), '')
    from (select * from fin.hotmart_transacoes where conta = v_conta) t
    cross join lateral (select coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric,
                                        t.valor_cobrado) as bruto) b
   where t.oferta_codigo = p_oferta;
end
$f$;
revoke all on function dados.transacoes(text, text) from public, anon, authenticated;

-- 4.2 Pré-checkout: uma linha por e-mail
create or replace function dados.pre_checkout(p_chave text, p_projeto_id bigint, p_lista text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text)
language sql
stable
set search_path = ''
as $f$
  with passagens as (
    -- sistema (rota /api/captura/lead → pessoas.registrar)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = e.pessoa_id and not p.teste
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
           null, null, null, null, null
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = j.pessoa_id
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id = j.pessoa_id and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.lista = p_lista and j.email_norm is not null
       and not coalesce(p.teste, false)
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y where y.email = l.email and y.fonte = 'sistema'
                        order by y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$f$;
revoke all on function dados.pre_checkout(text, bigint, text) from public, anon, authenticated;

-- 4.3 Instrução e turma do aluno pelo e-mail (null = não é aluno)
create or replace function dados.perfil(p_email text)
returns table (instrucao text, turma text)
language sql
stable
set search_path = ''
as $f$
  select a.instrucao, tu.codigo
    from public.thb_alunos a
    left join public.thb_turmas tu on tu.id = a.turma_id
   where lower(btrim(a.email)) = p_email and a.email is not null and a.email <> ''
   limit 1
$f$;
revoke all on function dados.perfil(text) from public, anon, authenticated;

-- 4.4 Cabeçalho comum: confere acesso e devolve o cadastro
create or replace function dados.cadastro(p_chave text)
returns dados.dashboards
language plpgsql
stable
set search_path = ''
as $f$
declare
  r dados.dashboards;
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  select * into r from dados.dashboards d where d.chave = p_chave and d.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  if not dados.pode_ver(p_chave) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return r;
end
$f$;
revoke all on function dados.cadastro(text) from public, anon, authenticated;

-- 5. Funções públicas (contrato da tela)

-- 5.1 Resumo: 1 linha (os 7 cards)
create or replace function public.dados_presencial_resumo(p_chave text)
returns table (chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, evento_inicio date, evento_fim date,
               oferta_codigo text, disparos_qtd integer, disparos_sem_custo integer, custo_disparo_centavos bigint,
               custo_completo boolean, pre_checkout_pessoas integer, custo_por_pre_checkout_centavos bigint,
               vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer,
               conversao_pct numeric(7,2), receita_bruta numeric(14,2), receita_liquida numeric(14,2),
               cac_centavos bigint, atualizado_em timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ), pc as (
    select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
  ), tx as (
    select t.* from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago
  ), ag as (
    select (select count(*)::int from pc) as pessoas,
           (select count(*)::int from tx where tx.primeira) as vendas,
           (select count(*)::int from tx where tx.primeira and tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  )
  select d.chave, pr.id, pr.sigla, pr.nome, pr.evento_inicio, pr.evento_fim, d.oferta_codigo,
         disp.qtd, disp.sem, disp.custo, (disp.qtd > 0 and disp.sem = 0), ag.pessoas,
         case when disp.qtd > 0 and disp.sem = 0 and ag.pessoas > 0 then round(disp.custo::numeric / ag.pessoas)::bigint end,
         ag.vendas, ag.fora, ag.comp, ag.comp_pc,
         case when ag.pessoas > 0 then round(ag.comp::numeric * 100 / ag.pessoas, 2)::numeric(7,2) end,
         ag.bruta, ag.liq,
         case when disp.qtd > 0 and disp.sem = 0 and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         now()
    from mkt.projetos pr cross join disp cross join ag
   where pr.id = d.projeto_id;
end
$f$;

-- 5.2 Leads do pré-checkout: 1 linha por e-mail
create or replace function public.dados_presencial_leads(p_chave text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, instrucao text, turma text,
               comprou boolean)
language plpgsql
stable
security definer
set search_path = ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with pagos as (select distinct t.email from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago)
  select pc.email, pc.nome, pc.telefone, pc.primeiro_em, pc.fonte, pc.utm_source, pc.utm_medium, pc.utm_campaign,
         pc.utm_content, pc.utm_term, pf.instrucao, pf.turma,
         exists (select 1 from pagos g where g.email = pc.email)
    from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) pc
    left join lateral dados.perfil(pc.email) pf on true
   order by pc.primeiro_em desc;
end
$f$;

-- 5.3 Vendas: 1 linha por transação da oferta (todos os status; a tela filtra)
create or replace function public.dados_presencial_vendas(p_chave text)
returns table (transacao text, status_grupo text, status_hotmart text, dia_pedido date, dia_aprovado date, moeda text,
               valor_bruto numeric(14,2), valor_liquido numeric(14,2), email text, nome text, telefone text,
               estado text, instrucao text, turma text, no_pre_checkout boolean, entrou_grupo boolean,
               grupo_fonte text)
language plpgsql
stable
security definer
set search_path = ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with pc as (select x.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x)
  select t.transacao, t.status_grupo, t.status, t.dia_pedido, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido,
         t.email, t.nome, t.telefone, t.estado, pf.instrucao, pf.turma,
         exists (select 1 from pc where pc.email = t.email),
         null::boolean, 'sem_fonte'::text
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join lateral dados.perfil(t.email) pf on true
   order by coalesce(t.dia_aprovado, t.dia_pedido) desc, t.transacao;
end
$f$;

-- 5.4 Disparos do projeto: 1 linha por disparo
create or replace function public.dados_presencial_disparos(p_chave text)
returns table (disparo_id bigint, dia date, nome text, canal text, ferramenta text, tamanho_lista integer,
               entregues integer, lidas integer, cliques integer, falhas integer, custo_centavos bigint,
               entrega_pct numeric(7,2), leitura_pct numeric(7,2), clique_pct numeric(7,2))
language plpgsql
stable
security definer
set search_path = ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  select x.id, (x.enviado_em at time zone 'America/Sao_Paulo')::date, x.campanha, x.canal, f.nome,
         x.tamanho_lista, x.entregues, x.lidas, x.cliques, x.falhas, x.custo_centavos::bigint,
         case when x.tamanho_lista > 0 then round(x.entregues::numeric * 100 / x.tamanho_lista, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.lidas::numeric * 100 / x.entregues, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.cliques::numeric * 100 / x.entregues, 2)::numeric(7,2) end
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
   order by x.enviado_em desc, x.id desc;
end
$f$;

-- 5.5 Série diária, sem buraco, do primeiro dia com dado até hoje
create or replace function public.dados_presencial_serie_diaria(p_chave text)
returns table (dia date, pre_checkout integer, pedidos integer, vendas integer, abandonos integer)
language plpgsql
stable
security definer
set search_path = ''
as $f$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ped as (select t.dia_pedido as dia, count(distinct t.email)::int as n from tx t group by 1),
       ven as (select t.dia_aprovado as dia, count(*)::int as n from tx t where t.pago and t.primeira group by 1),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0)
  select g.dia::date,
         (select count(*)::int from pc where pc.dia = g.dia),
         coalesce((select ped.n from ped where ped.dia = g.dia), 0),
         coalesce((select ven.n from ven where ven.dia = g.dia), 0),
         null::integer
    from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
   where ini.d0 is not null
   order by 1;
end
$f$;

revoke all on function public.dados_presencial_resumo(text), public.dados_presencial_leads(text),
  public.dados_presencial_vendas(text), public.dados_presencial_disparos(text), public.dados_presencial_serie_diaria(text)
  from public, anon;
grant execute on function public.dados_presencial_resumo(text), public.dados_presencial_leads(text),
  public.dados_presencial_vendas(text), public.dados_presencial_disparos(text), public.dados_presencial_serie_diaria(text)
  to authenticated;

-- 6. Pós-condição
do $c$
declare
  f text;
begin
  if not exists (select 1 from dados.dashboards where chave = 'clinica-miami-2026-12' and projeto_id = 68
                   and conta_hotmart = 'academy' and oferta_codigo = 'mjzv4v0s') then
    raise exception '20261007p: cadastro da Clínica ausente';
  end if;
  foreach f in array array['resumo', 'leads', 'vendas', 'disparos', 'serie_diaria'] loop
    if not has_function_privilege('authenticated', format('public.dados_presencial_%s(text)', f), 'execute')
       or has_function_privilege('anon', format('public.dados_presencial_%s(text)', f), 'execute') then
      raise exception '20261007p: permissão errada em dados_presencial_%', f;
    end if;
  end loop;
  if has_schema_privilege('anon', 'dados', 'usage') or has_schema_privilege('authenticated', 'dados', 'usage')
     or has_table_privilege('authenticated', 'dados.dashboards', 'select') then
    raise exception '20261007p: schema dados ou dados.dashboards exposto';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- drop function if exists public.dados_presencial_resumo(text), public.dados_presencial_leads(text),
--   public.dados_presencial_vendas(text), public.dados_presencial_disparos(text), public.dados_presencial_serie_diaria(text);
-- drop schema dados cascade;
