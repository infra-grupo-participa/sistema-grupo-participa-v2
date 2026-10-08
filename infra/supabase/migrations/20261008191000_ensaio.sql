-- Ensaio de 20261008191000 (marcar como teste + período). Transação desfeita: nada persiste.
-- Saída só com contagens, datas e md5: nenhum dado pessoal. Gerado por script a partir da migration e da reversão.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '240s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '01 antes resumo md5', ((select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;

insert into pg_temp._z_out (passo, linha) select '01 antes resumo', ((select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;

insert into pg_temp._z_out (passo, linha) select '01 antes serie', ((select jsonb_build_object('dias', count(*), 'de', min(dia), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')))::text;

insert into pg_temp._z_out (passo, linha) select '01 antes md5 leads/canais/comp/pos', (jsonb_build_object('leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_leads('atm-elaine-1-2026-10') x), 'canais', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10') x), 'comp', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_comparecimento('atm-elaine-1-2026-10') x), 'pos', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from (select ciclo, ate is null a, vendas, compradores, receita_bruta, conversao_pct from public.dados_atm_pos_live('atm-elaine-1-2026-10')) x)))::text;

insert into pg_temp._z_out (passo, linha) select '01 antes presencial', (jsonb_build_object('resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r), 'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x)))::text;

insert into pg_temp._z_out (passo, linha) select '01 direto 06/10', ((select jsonb_build_object('eventos', count(*), 'numeros', count(distinct right(fone_key,8))) from crm.evento_jornada where fonte='sendflow' and tag='ATM 10/26' and tipo='entrada' and (ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06'))::text;

select set_config('request.jwt.claims', '{}', true);

-- passada 1
-- 20261008191000: "marcar como teste" por evento e filtro de período nos dashboards do schema dados (primeiro uso: ATM)
--
-- STATUS: ver 20261008191000.explain.md (situação, ensaio, aplicação).
-- Ensaio: 20261008191000_ensaio.sql. Reversão: 20261008191000_reversao.sql. Contrato: docs/dashboard-atm/MODELO-DE-DADOS.md.
-- Depende de 20261008161000 (modelo seminario-atm), já aplicada.
--
-- POR QUE (pedido do Victor de 08/10/2026, .maestri/entregas/pedido-atm-teste-periodo.md)
--   1. Marcar como teste: um lead ou número do grupo marcado sai de TUDO daquele evento (leads, grupo, ingresso,
--      evasão, CPL, série, pré-checkout, vendas, comparecimento, pós-live). Escopo por chave do dashboard, casando por
--      e-mail e pelos últimos 8 dígitos do telefone. Guarda quem marcou e quando; desmarcar não apaga (guarda quem e
--      quando desmarcou). Só a equipe escreve, e só pela RPC.
--      A regra fica num lugar só: dados.v_grupo_eventos (grupo), dados.atm_leads (leads), dados.atm_pre_checkout e
--      dados.atm_vendas. Toda RPC do ATM lê por elas, então nenhum card precisa lembrar do teste.
--   2. Período: Hoje, Ontem, Últimos 3/7 dias e "Período do evento" (padrão). As datas do evento ficam na config
--      (dados.dashboards.periodo_inicio / periodo_fim), não no código. Intervalo combinado com o JP (08/10):
--      [p_de 00:00 America/Sao_Paulo, (p_ate + 1 dia) 00:00 America/Sao_Paulo), limite final exclusivo.
--
-- O QUE FAZ
--   a. dados.dashboards: colunas periodo_inicio, periodo_fim (date). ATM 1 da Elaine: 2026-10-07 a 2026-10-14
--      (captação desde 07/10; live 13/10 19h30; +1 dia = replay).
--   b. dados.marcacoes_teste (RLS ligada, sem policy, sem grant): chave, tipo ('email'|'fone'), valor (e-mail minúsculo
--      ou 8 últimos dígitos), motivo ('teste'|'equipe'), marcado_por/_email/_em, desmarcado_por/_email/_em.
--      Uma marcação ativa por (chave, tipo, valor).
--   c. dados.periodo(...): resolve p_de/p_ate (nulos = período do evento) nos dois limites timestamptz.
--   d. dados.teste_ativo(chave, email, fone): o teste de uma pessoa, usado por todas as leituras.
--   e. dados.v_grupo_eventos_todos (nova, com a coluna teste e o nome); dados.v_grupo_eventos passa a ser ela sem os
--      testes (mesmas colunas). dados.v_grupo_pessoas lê a v_grupo_eventos e herda o filtro sem mudar.
--   f. dados.atm_leads: teste = teste do cadastro de pessoas OU marcado. dados.atm_vendas: sem e-mail marcado.
--      dados.atm_pre_checkout (nova): pre_checkout sem e-mail marcado.
--   g. RPCs do ATM com período: dados_atm_resumo (+4 colunas no fim), dados_atm_serie_diaria, dados_atm_leads
--      (+p_incluir_teste), dados_atm_disparos_canais ganham p_de date, p_ate date (default null). A assinatura antiga
--      (só p_chave) sai e a nova aceita a mesma chamada. dados_atm_comparecimento e dados_atm_pos_live mantêm a
--      assinatura (são da live e do ciclo, evento inteiro) e passam a ler o pré-checkout sem teste e a ignorar presença
--      marcada.
--   h. RPCs novas: dados_atm_grupo_numeros (lista do grupo, para marcar número), dados_marcar_teste,
--      dados_desmarcar_teste, dados_testes (auditoria). A tabela é genérica por chave, mas as RPCs de escrita usam
--      dados.atm_cadastro (só o ATM lê a marcação hoje) e só aceitam e-mail/telefone que aparece no evento
--      (dados.atm_pertence: lead, pré-checkout, comprador, grupo ou presença). Ajuste do pentester (08/10).
--
-- AS 5 PERGUNTAS
--   escala: dezenas de marcações por evento; leads ~1 mil e eventos de grupo ~1 mil por ATM.
--   índice: único parcial (chave, tipo, valor) where desmarcado_em is null cobre a busca do teste.
--   frequência: leitura a cada abertura/atualização da tela; escrita só por clique.
--   repetição: o teste é um exists por índice, uma vez por linha.
--   reversão: 20261008191000_reversao.sql (volta as funções e a view ao corpo de 20261008161000 e apaga o resto).
--
-- IDEMPOTENTE: if not exists / create or replace / drop function if exists / on conflict.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['dados.atm_cadastro(text)', 'dados.atm_leads(text)', 'dados.atm_vendas(text)',
                           'dados.cadastro(text)', 'dados.pre_checkout(text,bigint,text)', 'controle.fone_key(text)',
                           'public.tg_carimbar_atualizado_em()', 'auth.uid()', 'auth.jwt()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regclass('dados.v_grupo_eventos') is null or to_regclass('dados.dashboard_grupos') is null then
    raise exception 'premissa: modelo seminario-atm (20261008161000) não aplicado';
  end if;
end
$g$;

-- a. Período do evento na config
alter table dados.dashboards add column if not exists periodo_inicio date;
alter table dados.dashboards add column if not exists periodo_fim date;
alter table dados.dashboards drop constraint if exists dashboards_periodo_check;
alter table dados.dashboards add constraint dashboards_periodo_check
  check (periodo_inicio is null or periodo_fim is null or periodo_inicio <= periodo_fim);
comment on column dados.dashboards.periodo_inicio is
  'Primeiro dia do "Período do evento" (America/Sao_Paulo), padrão do filtro de período. Nulo = sem limite. 20261008191000.';
comment on column dados.dashboards.periodo_fim is
  'Último dia (inclusive) do "Período do evento". Regra do ATM: 1 dia depois da live (replay). Nulo = até hoje. 20261008191000.';

update dados.dashboards
   set periodo_inicio = date '2026-10-07', periodo_fim = date '2026-10-14'
 where chave = 'atm-elaine-1-2026-10' and periodo_inicio is null and periodo_fim is null;

-- b. Marcações de teste
create table if not exists dados.marcacoes_teste (
  id                    bigint generated always as identity primary key,
  chave                 text not null references dados.dashboards(chave) on delete restrict,
  tipo                  text not null check (tipo in ('email', 'fone')),
  valor                 text not null,
  motivo                text not null default 'teste' check (motivo in ('teste', 'equipe')),
  marcado_por           uuid,
  marcado_por_email     text,
  marcado_em            timestamptz not null default now(),
  desmarcado_por        uuid,
  desmarcado_por_email  text,
  desmarcado_em         timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  check ((tipo = 'email' and valor = lower(btrim(valor)) and valor like '%@%')
      or (tipo = 'fone' and valor ~ '^[0-9]{8}$')),
  check (desmarcado_em is null or desmarcado_em >= marcado_em)
);
comment on table dados.marcacoes_teste is
  'Lead ou número do grupo marcado como teste/equipe num dashboard (chave). Ativo = desmarcado_em nulo. Sai de todas as leituras do evento. Escrita só por public.dados_marcar_teste / dados_desmarcar_teste. 20261008191000.';
create unique index if not exists marcacoes_teste_ativa_uk
  on dados.marcacoes_teste (chave, tipo, valor) where desmarcado_em is null;
create index if not exists marcacoes_teste_chave_idx on dados.marcacoes_teste (chave);
alter table dados.marcacoes_teste enable row level security;
revoke all on dados.marcacoes_teste from public, anon, authenticated;
drop trigger if exists marcacoes_teste_carimbar on dados.marcacoes_teste;
create trigger marcacoes_teste_carimbar before update on dados.marcacoes_teste
  for each row execute function public.tg_carimbar_atualizado_em();

-- c. Período
create or replace function dados.periodo(p_padrao_de date, p_padrao_ate date, p_de date, p_ate date,
                                         out de date, out ate date, out ini timestamptz, out fim timestamptz)
language plpgsql stable set search_path = '' as $$
-- 20261008191000: [de 00:00, ate + 1 dia 00:00) em America/Sao_Paulo; nulo = sem limite daquele lado
begin
  de  := coalesce(p_de, p_padrao_de);
  ate := coalesce(p_ate, p_padrao_ate);
  if de is not null and ate is not null and de > ate then
    raise exception 'período inválido: início depois do fim' using errcode = '22023';
  end if;
  ini := coalesce(de::timestamp at time zone 'America/Sao_Paulo', '-infinity'::timestamptz);
  fim := coalesce((ate + 1)::timestamp at time zone 'America/Sao_Paulo', 'infinity'::timestamptz);
end
$$;

-- d. Teste de uma pessoa no evento
create or replace function dados.teste_ativo(p_chave text, p_email text, p_fone text)
returns boolean language sql stable set search_path = '' as $$
  -- 20261008191000: p_email minúsculo; p_fone qualquer forma (casam os 8 últimos dígitos)
  select exists (select 1 from dados.marcacoes_teste m
                  where m.chave = p_chave and m.desmarcado_em is null
                    and ((m.tipo = 'email' and m.valor = lower(btrim(p_email)))
                      or (m.tipo = 'fone' and length(regexp_replace(coalesce(p_fone, ''), '[^0-9]', '', 'g')) >= 8
                          and m.valor = right(regexp_replace(p_fone, '[^0-9]', '', 'g'), 8))))
$$;

-- e. Grupo: todos os eventos (com teste) e a view de sempre sem os testes
create or replace view dados.v_grupo_eventos_todos with (security_invoker = true) as
  select g.chave, j.id as evento_id, j.tipo, j.fone_key, right(j.fone_key, 8) as fone8, j.ocorreu_em, j.pessoa_id,
         nullif(btrim(j.nome), '') as nome,
         exists (select 1 from dados.marcacoes_teste m
                  where m.chave = g.chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = right(j.fone_key, 8)) as teste
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null;
comment on view dados.v_grupo_eventos_todos is
  'Entradas/saídas do grupo do dashboard, com a marcação de teste (fone). Base da lista para marcar. 20261008191000.';

create or replace view dados.v_grupo_eventos with (security_invoker = true) as
  select e.chave, e.evento_id, e.tipo, e.fone_key, e.fone8, e.ocorreu_em, e.pessoa_id
    from dados.v_grupo_eventos_todos e
   where not e.teste;
comment on view dados.v_grupo_eventos is
  'Entradas/saídas do grupo do dashboard SEM os números marcados como teste. 20261008161000, filtro de teste em 20261008191000.';
revoke all on dados.v_grupo_eventos_todos, dados.v_grupo_eventos from public, anon, authenticated;

-- f. Leads, pré-checkout e vendas sem teste
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

create or replace function dados.atm_vendas_todas(p_chave text)
returns table(transacao text, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_aprovado date,
              moeda text, valor_bruto numeric, valor_liquido numeric, email text, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008191000: vendas do dashboard (regra de 20261008161000) com a marcação de teste do comprador
  select t.transacao, t.pedido_em, t.aprovado_em, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido, t.email,
         dados.teste_ativo(p_chave, t.email, null)
    from dados.dashboards d
    cross join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
   where d.chave = p_chave and d.oferta_codigo is not null
     and t.pago and t.primeira
     and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
$$;

create or replace function dados.atm_vendas(p_chave text)
returns table(transacao text, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_aprovado date,
              moeda text, valor_bruto numeric, valor_liquido numeric, email text)
language sql stable set search_path = '' as $$
  -- 20261008161000; sem comprador marcado como teste em 20261008191000
  select v.transacao, v.pedido_em, v.aprovado_em, v.dia_aprovado, v.moeda, v.valor_bruto, v.valor_liquido, v.email
    from dados.atm_vendas_todas(p_chave) v
   where not v.teste
$$;

create or replace function dados.atm_pre_checkout(p_chave text)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text)
language sql stable set search_path = '' as $$
  -- 20261008191000: dados.pre_checkout do dashboard sem quem está marcado como teste
  select y.*
    from dados.dashboards d
    cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
   where d.chave = p_chave
     and not dados.teste_ativo(p_chave, y.email, y.telefone)
$$;

-- f2. O identificador pertence ao evento? (lead, pré-checkout, comprador, grupo ou presença da live)
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

revoke all on function dados.periodo(date, date, date, date), dados.teste_ativo(text, text, text),
                       dados.atm_leads(text), dados.atm_vendas_todas(text), dados.atm_vendas(text),
                       dados.atm_pre_checkout(text), dados.atm_pertence(text, text, text)
  from public, anon, authenticated;

-- g. RPCs do ATM com período (a assinatura antiga sai; a nova aceita a mesma chamada só com p_chave)
drop function if exists public.dados_atm_resumo(text);
drop function if exists public.dados_atm_serie_diaria(text);
drop function if exists public.dados_atm_leads(text);
drop function if exists public.dados_atm_disparos_canais(text);

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

create or replace function public.dados_atm_leads(p_chave text, p_de date default null, p_ate date default null,
                                                  p_incluir_teste boolean default false)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
              entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
              lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid,
              teste boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select * from dados.atm_leads(d.chave) x
   where x.primeiro_em >= v_ini and x.primeiro_em < v_fim
     and (coalesce(p_incluir_teste, false) or not x.teste)
   order by x.primeiro_em desc, x.email;
end
$$;

create or replace function public.dados_atm_disparos_canais(p_chave text, p_de date default null, p_ate date default null)
returns table(canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
              falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
          and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   group by c.ordem, c.canal
   order by c.ordem;
end
$$;

-- comparecimento e pós-live: mesma assinatura; pré-checkout sem teste e presença marcada fora
create or replace function public.dados_atm_comparecimento(p_chave text)
returns table(sessao_id uuid, tipo text, inicio timestamp with time zone, fim timestamp with time zone,
              pico_audiencia integer, equipe_na_sala integer, total_leads integer, total_grupo integer,
              presentes integer, presentes_leads integer, presentes_grupo integer, pico_sobre_leads_pct numeric,
              pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric, vendas integer,
              conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
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
    -- presente = pessoa fora da equipe e não marcada como teste; é lead se casa por e-mail ou telefone; é do grupo se
    -- o telefone (dele ou do lead casado pelo e-mail) entrou no grupo
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
       and not dados.teste_ativo(d.chave, p.email_norm, p.fone_key)
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
$$;

create or replace function public.dados_atm_pos_live(p_chave text)
returns table(ciclo text, ate timestamp with time zone, vendas integer, compradores integer, receita_bruta numeric,
              receita_liquida numeric, conversao_pct numeric, conversao_grupo_pct numeric,
              conversao_pre_checkout_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select count(*)::int as n from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select case when v_tem_grupo then count(*)::int end as n
           from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  pc as (select count(*)::int as n from dados.atm_pre_checkout(d.chave) y),
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
$$;

-- h. RPCs novas
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

create or replace function public.dados_marcar_teste(p_chave text, p_email text default null, p_telefone text default null,
                                                     p_motivo text default 'teste')
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not dados.atm_pertence(d.chave, 'email', v_email) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$$;

create or replace function public.dados_desmarcar_teste(p_chave text, p_email text default null, p_telefone text default null)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$$;

create or replace function public.dados_testes(p_chave text)
returns table(id bigint, tipo text, valor text, motivo text, marcado_por_email text, marcado_em timestamp with time zone)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select m.id, m.tipo, m.valor, m.motivo, m.marcado_por_email, m.marcado_em
    from dados.marcacoes_teste m
   where m.chave = d.chave and m.desmarcado_em is null
   order by m.marcado_em desc, m.id desc;
end
$$;

revoke all on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                       public.dados_atm_leads(text, date, date, boolean), public.dados_atm_disparos_canais(text, date, date),
                       public.dados_atm_comparecimento(text), public.dados_atm_pos_live(text),
                       public.dados_atm_grupo_numeros(text, date, date, boolean),
                       public.dados_marcar_teste(text, text, text, text), public.dados_desmarcar_teste(text, text, text),
                       public.dados_testes(text)
  from public, anon, service_role;
grant execute on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                          public.dados_atm_leads(text, date, date, boolean), public.dados_atm_disparos_canais(text, date, date),
                          public.dados_atm_comparecimento(text), public.dados_atm_pos_live(text),
                          public.dados_atm_grupo_numeros(text, date, date, boolean),
                          public.dados_marcar_teste(text, text, text, text), public.dados_desmarcar_teste(text, text, text),
                          public.dados_testes(text)
  to authenticated;

-- pós-condição: authenticated executa, anon não
do $p$
declare f text;
begin
  foreach f in array array['public.dados_atm_resumo(text,date,date)', 'public.dados_atm_serie_diaria(text,date,date)',
                           'public.dados_atm_leads(text,date,date,boolean)', 'public.dados_atm_disparos_canais(text,date,date)',
                           'public.dados_atm_grupo_numeros(text,date,date,boolean)', 'public.dados_marcar_teste(text,text,text,text)',
                           'public.dados_desmarcar_teste(text,text,text)', 'public.dados_testes(text)',
                           'public.dados_atm_comparecimento(text)', 'public.dados_atm_pos_live(text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
      raise exception 'pós-condição: grant errado em %', f;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'dados.marcacoes_teste', 'select') then
    raise exception 'pós-condição: authenticated lê dados.marcacoes_teste';
  end if;
end
$p$;

-- (notify fora do ensaio)

-- passada 2 (idempotente)
-- 20261008191000: "marcar como teste" por evento e filtro de período nos dashboards do schema dados (primeiro uso: ATM)
--
-- STATUS: ver 20261008191000.explain.md (situação, ensaio, aplicação).
-- Ensaio: 20261008191000_ensaio.sql. Reversão: 20261008191000_reversao.sql. Contrato: docs/dashboard-atm/MODELO-DE-DADOS.md.
-- Depende de 20261008161000 (modelo seminario-atm), já aplicada.
--
-- POR QUE (pedido do Victor de 08/10/2026, .maestri/entregas/pedido-atm-teste-periodo.md)
--   1. Marcar como teste: um lead ou número do grupo marcado sai de TUDO daquele evento (leads, grupo, ingresso,
--      evasão, CPL, série, pré-checkout, vendas, comparecimento, pós-live). Escopo por chave do dashboard, casando por
--      e-mail e pelos últimos 8 dígitos do telefone. Guarda quem marcou e quando; desmarcar não apaga (guarda quem e
--      quando desmarcou). Só a equipe escreve, e só pela RPC.
--      A regra fica num lugar só: dados.v_grupo_eventos (grupo), dados.atm_leads (leads), dados.atm_pre_checkout e
--      dados.atm_vendas. Toda RPC do ATM lê por elas, então nenhum card precisa lembrar do teste.
--   2. Período: Hoje, Ontem, Últimos 3/7 dias e "Período do evento" (padrão). As datas do evento ficam na config
--      (dados.dashboards.periodo_inicio / periodo_fim), não no código. Intervalo combinado com o JP (08/10):
--      [p_de 00:00 America/Sao_Paulo, (p_ate + 1 dia) 00:00 America/Sao_Paulo), limite final exclusivo.
--
-- O QUE FAZ
--   a. dados.dashboards: colunas periodo_inicio, periodo_fim (date). ATM 1 da Elaine: 2026-10-07 a 2026-10-14
--      (captação desde 07/10; live 13/10 19h30; +1 dia = replay).
--   b. dados.marcacoes_teste (RLS ligada, sem policy, sem grant): chave, tipo ('email'|'fone'), valor (e-mail minúsculo
--      ou 8 últimos dígitos), motivo ('teste'|'equipe'), marcado_por/_email/_em, desmarcado_por/_email/_em.
--      Uma marcação ativa por (chave, tipo, valor).
--   c. dados.periodo(...): resolve p_de/p_ate (nulos = período do evento) nos dois limites timestamptz.
--   d. dados.teste_ativo(chave, email, fone): o teste de uma pessoa, usado por todas as leituras.
--   e. dados.v_grupo_eventos_todos (nova, com a coluna teste e o nome); dados.v_grupo_eventos passa a ser ela sem os
--      testes (mesmas colunas). dados.v_grupo_pessoas lê a v_grupo_eventos e herda o filtro sem mudar.
--   f. dados.atm_leads: teste = teste do cadastro de pessoas OU marcado. dados.atm_vendas: sem e-mail marcado.
--      dados.atm_pre_checkout (nova): pre_checkout sem e-mail marcado.
--   g. RPCs do ATM com período: dados_atm_resumo (+4 colunas no fim), dados_atm_serie_diaria, dados_atm_leads
--      (+p_incluir_teste), dados_atm_disparos_canais ganham p_de date, p_ate date (default null). A assinatura antiga
--      (só p_chave) sai e a nova aceita a mesma chamada. dados_atm_comparecimento e dados_atm_pos_live mantêm a
--      assinatura (são da live e do ciclo, evento inteiro) e passam a ler o pré-checkout sem teste e a ignorar presença
--      marcada.
--   h. RPCs novas: dados_atm_grupo_numeros (lista do grupo, para marcar número), dados_marcar_teste,
--      dados_desmarcar_teste, dados_testes (auditoria). A tabela é genérica por chave, mas as RPCs de escrita usam
--      dados.atm_cadastro (só o ATM lê a marcação hoje) e só aceitam e-mail/telefone que aparece no evento
--      (dados.atm_pertence: lead, pré-checkout, comprador, grupo ou presença). Ajuste do pentester (08/10).
--
-- AS 5 PERGUNTAS
--   escala: dezenas de marcações por evento; leads ~1 mil e eventos de grupo ~1 mil por ATM.
--   índice: único parcial (chave, tipo, valor) where desmarcado_em is null cobre a busca do teste.
--   frequência: leitura a cada abertura/atualização da tela; escrita só por clique.
--   repetição: o teste é um exists por índice, uma vez por linha.
--   reversão: 20261008191000_reversao.sql (volta as funções e a view ao corpo de 20261008161000 e apaga o resto).
--
-- IDEMPOTENTE: if not exists / create or replace / drop function if exists / on conflict.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['dados.atm_cadastro(text)', 'dados.atm_leads(text)', 'dados.atm_vendas(text)',
                           'dados.cadastro(text)', 'dados.pre_checkout(text,bigint,text)', 'controle.fone_key(text)',
                           'public.tg_carimbar_atualizado_em()', 'auth.uid()', 'auth.jwt()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regclass('dados.v_grupo_eventos') is null or to_regclass('dados.dashboard_grupos') is null then
    raise exception 'premissa: modelo seminario-atm (20261008161000) não aplicado';
  end if;
end
$g$;

-- a. Período do evento na config
alter table dados.dashboards add column if not exists periodo_inicio date;
alter table dados.dashboards add column if not exists periodo_fim date;
alter table dados.dashboards drop constraint if exists dashboards_periodo_check;
alter table dados.dashboards add constraint dashboards_periodo_check
  check (periodo_inicio is null or periodo_fim is null or periodo_inicio <= periodo_fim);
comment on column dados.dashboards.periodo_inicio is
  'Primeiro dia do "Período do evento" (America/Sao_Paulo), padrão do filtro de período. Nulo = sem limite. 20261008191000.';
comment on column dados.dashboards.periodo_fim is
  'Último dia (inclusive) do "Período do evento". Regra do ATM: 1 dia depois da live (replay). Nulo = até hoje. 20261008191000.';

update dados.dashboards
   set periodo_inicio = date '2026-10-07', periodo_fim = date '2026-10-14'
 where chave = 'atm-elaine-1-2026-10' and periodo_inicio is null and periodo_fim is null;

-- b. Marcações de teste
create table if not exists dados.marcacoes_teste (
  id                    bigint generated always as identity primary key,
  chave                 text not null references dados.dashboards(chave) on delete restrict,
  tipo                  text not null check (tipo in ('email', 'fone')),
  valor                 text not null,
  motivo                text not null default 'teste' check (motivo in ('teste', 'equipe')),
  marcado_por           uuid,
  marcado_por_email     text,
  marcado_em            timestamptz not null default now(),
  desmarcado_por        uuid,
  desmarcado_por_email  text,
  desmarcado_em         timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  check ((tipo = 'email' and valor = lower(btrim(valor)) and valor like '%@%')
      or (tipo = 'fone' and valor ~ '^[0-9]{8}$')),
  check (desmarcado_em is null or desmarcado_em >= marcado_em)
);
comment on table dados.marcacoes_teste is
  'Lead ou número do grupo marcado como teste/equipe num dashboard (chave). Ativo = desmarcado_em nulo. Sai de todas as leituras do evento. Escrita só por public.dados_marcar_teste / dados_desmarcar_teste. 20261008191000.';
create unique index if not exists marcacoes_teste_ativa_uk
  on dados.marcacoes_teste (chave, tipo, valor) where desmarcado_em is null;
create index if not exists marcacoes_teste_chave_idx on dados.marcacoes_teste (chave);
alter table dados.marcacoes_teste enable row level security;
revoke all on dados.marcacoes_teste from public, anon, authenticated;
drop trigger if exists marcacoes_teste_carimbar on dados.marcacoes_teste;
create trigger marcacoes_teste_carimbar before update on dados.marcacoes_teste
  for each row execute function public.tg_carimbar_atualizado_em();

-- c. Período
create or replace function dados.periodo(p_padrao_de date, p_padrao_ate date, p_de date, p_ate date,
                                         out de date, out ate date, out ini timestamptz, out fim timestamptz)
language plpgsql stable set search_path = '' as $$
-- 20261008191000: [de 00:00, ate + 1 dia 00:00) em America/Sao_Paulo; nulo = sem limite daquele lado
begin
  de  := coalesce(p_de, p_padrao_de);
  ate := coalesce(p_ate, p_padrao_ate);
  if de is not null and ate is not null and de > ate then
    raise exception 'período inválido: início depois do fim' using errcode = '22023';
  end if;
  ini := coalesce(de::timestamp at time zone 'America/Sao_Paulo', '-infinity'::timestamptz);
  fim := coalesce((ate + 1)::timestamp at time zone 'America/Sao_Paulo', 'infinity'::timestamptz);
end
$$;

-- d. Teste de uma pessoa no evento
create or replace function dados.teste_ativo(p_chave text, p_email text, p_fone text)
returns boolean language sql stable set search_path = '' as $$
  -- 20261008191000: p_email minúsculo; p_fone qualquer forma (casam os 8 últimos dígitos)
  select exists (select 1 from dados.marcacoes_teste m
                  where m.chave = p_chave and m.desmarcado_em is null
                    and ((m.tipo = 'email' and m.valor = lower(btrim(p_email)))
                      or (m.tipo = 'fone' and length(regexp_replace(coalesce(p_fone, ''), '[^0-9]', '', 'g')) >= 8
                          and m.valor = right(regexp_replace(p_fone, '[^0-9]', '', 'g'), 8))))
$$;

-- e. Grupo: todos os eventos (com teste) e a view de sempre sem os testes
create or replace view dados.v_grupo_eventos_todos with (security_invoker = true) as
  select g.chave, j.id as evento_id, j.tipo, j.fone_key, right(j.fone_key, 8) as fone8, j.ocorreu_em, j.pessoa_id,
         nullif(btrim(j.nome), '') as nome,
         exists (select 1 from dados.marcacoes_teste m
                  where m.chave = g.chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = right(j.fone_key, 8)) as teste
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null;
comment on view dados.v_grupo_eventos_todos is
  'Entradas/saídas do grupo do dashboard, com a marcação de teste (fone). Base da lista para marcar. 20261008191000.';

create or replace view dados.v_grupo_eventos with (security_invoker = true) as
  select e.chave, e.evento_id, e.tipo, e.fone_key, e.fone8, e.ocorreu_em, e.pessoa_id
    from dados.v_grupo_eventos_todos e
   where not e.teste;
comment on view dados.v_grupo_eventos is
  'Entradas/saídas do grupo do dashboard SEM os números marcados como teste. 20261008161000, filtro de teste em 20261008191000.';
revoke all on dados.v_grupo_eventos_todos, dados.v_grupo_eventos from public, anon, authenticated;

-- f. Leads, pré-checkout e vendas sem teste
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

create or replace function dados.atm_vendas_todas(p_chave text)
returns table(transacao text, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_aprovado date,
              moeda text, valor_bruto numeric, valor_liquido numeric, email text, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008191000: vendas do dashboard (regra de 20261008161000) com a marcação de teste do comprador
  select t.transacao, t.pedido_em, t.aprovado_em, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido, t.email,
         dados.teste_ativo(p_chave, t.email, null)
    from dados.dashboards d
    cross join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
   where d.chave = p_chave and d.oferta_codigo is not null
     and t.pago and t.primeira
     and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
$$;

create or replace function dados.atm_vendas(p_chave text)
returns table(transacao text, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_aprovado date,
              moeda text, valor_bruto numeric, valor_liquido numeric, email text)
language sql stable set search_path = '' as $$
  -- 20261008161000; sem comprador marcado como teste em 20261008191000
  select v.transacao, v.pedido_em, v.aprovado_em, v.dia_aprovado, v.moeda, v.valor_bruto, v.valor_liquido, v.email
    from dados.atm_vendas_todas(p_chave) v
   where not v.teste
$$;

create or replace function dados.atm_pre_checkout(p_chave text)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text)
language sql stable set search_path = '' as $$
  -- 20261008191000: dados.pre_checkout do dashboard sem quem está marcado como teste
  select y.*
    from dados.dashboards d
    cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
   where d.chave = p_chave
     and not dados.teste_ativo(p_chave, y.email, y.telefone)
$$;

-- f2. O identificador pertence ao evento? (lead, pré-checkout, comprador, grupo ou presença da live)
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

revoke all on function dados.periodo(date, date, date, date), dados.teste_ativo(text, text, text),
                       dados.atm_leads(text), dados.atm_vendas_todas(text), dados.atm_vendas(text),
                       dados.atm_pre_checkout(text), dados.atm_pertence(text, text, text)
  from public, anon, authenticated;

-- g. RPCs do ATM com período (a assinatura antiga sai; a nova aceita a mesma chamada só com p_chave)
drop function if exists public.dados_atm_resumo(text);
drop function if exists public.dados_atm_serie_diaria(text);
drop function if exists public.dados_atm_leads(text);
drop function if exists public.dados_atm_disparos_canais(text);

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

create or replace function public.dados_atm_leads(p_chave text, p_de date default null, p_ate date default null,
                                                  p_incluir_teste boolean default false)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
              entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
              lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid,
              teste boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select * from dados.atm_leads(d.chave) x
   where x.primeiro_em >= v_ini and x.primeiro_em < v_fim
     and (coalesce(p_incluir_teste, false) or not x.teste)
   order by x.primeiro_em desc, x.email;
end
$$;

create or replace function public.dados_atm_disparos_canais(p_chave text, p_de date default null, p_ate date default null)
returns table(canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
              falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
          and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   group by c.ordem, c.canal
   order by c.ordem;
end
$$;

-- comparecimento e pós-live: mesma assinatura; pré-checkout sem teste e presença marcada fora
create or replace function public.dados_atm_comparecimento(p_chave text)
returns table(sessao_id uuid, tipo text, inicio timestamp with time zone, fim timestamp with time zone,
              pico_audiencia integer, equipe_na_sala integer, total_leads integer, total_grupo integer,
              presentes integer, presentes_leads integer, presentes_grupo integer, pico_sobre_leads_pct numeric,
              pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric, vendas integer,
              conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
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
    -- presente = pessoa fora da equipe e não marcada como teste; é lead se casa por e-mail ou telefone; é do grupo se
    -- o telefone (dele ou do lead casado pelo e-mail) entrou no grupo
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
       and not dados.teste_ativo(d.chave, p.email_norm, p.fone_key)
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
$$;

create or replace function public.dados_atm_pos_live(p_chave text)
returns table(ciclo text, ate timestamp with time zone, vendas integer, compradores integer, receita_bruta numeric,
              receita_liquida numeric, conversao_pct numeric, conversao_grupo_pct numeric,
              conversao_pre_checkout_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select count(*)::int as n from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select case when v_tem_grupo then count(*)::int end as n
           from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  pc as (select count(*)::int as n from dados.atm_pre_checkout(d.chave) y),
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
$$;

-- h. RPCs novas
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

create or replace function public.dados_marcar_teste(p_chave text, p_email text default null, p_telefone text default null,
                                                     p_motivo text default 'teste')
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not dados.atm_pertence(d.chave, 'email', v_email) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$$;

create or replace function public.dados_desmarcar_teste(p_chave text, p_email text default null, p_telefone text default null)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$$;

create or replace function public.dados_testes(p_chave text)
returns table(id bigint, tipo text, valor text, motivo text, marcado_por_email text, marcado_em timestamp with time zone)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select m.id, m.tipo, m.valor, m.motivo, m.marcado_por_email, m.marcado_em
    from dados.marcacoes_teste m
   where m.chave = d.chave and m.desmarcado_em is null
   order by m.marcado_em desc, m.id desc;
end
$$;

revoke all on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                       public.dados_atm_leads(text, date, date, boolean), public.dados_atm_disparos_canais(text, date, date),
                       public.dados_atm_comparecimento(text), public.dados_atm_pos_live(text),
                       public.dados_atm_grupo_numeros(text, date, date, boolean),
                       public.dados_marcar_teste(text, text, text, text), public.dados_desmarcar_teste(text, text, text),
                       public.dados_testes(text)
  from public, anon, service_role;
grant execute on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                          public.dados_atm_leads(text, date, date, boolean), public.dados_atm_disparos_canais(text, date, date),
                          public.dados_atm_comparecimento(text), public.dados_atm_pos_live(text),
                          public.dados_atm_grupo_numeros(text, date, date, boolean),
                          public.dados_marcar_teste(text, text, text, text), public.dados_desmarcar_teste(text, text, text),
                          public.dados_testes(text)
  to authenticated;

-- pós-condição: authenticated executa, anon não
do $p$
declare f text;
begin
  foreach f in array array['public.dados_atm_resumo(text,date,date)', 'public.dados_atm_serie_diaria(text,date,date)',
                           'public.dados_atm_leads(text,date,date,boolean)', 'public.dados_atm_disparos_canais(text,date,date)',
                           'public.dados_atm_grupo_numeros(text,date,date,boolean)', 'public.dados_marcar_teste(text,text,text,text)',
                           'public.dados_desmarcar_teste(text,text,text)', 'public.dados_testes(text)',
                           'public.dados_atm_comparecimento(text)', 'public.dados_atm_pos_live(text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
      raise exception 'pós-condição: grant errado em %', f;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'dados.marcacoes_teste', 'select') then
    raise exception 'pós-condição: authenticated lê dados.marcacoes_teste';
  end if;
end
$p$;

-- (notify fora do ensaio)


insert into pg_temp._z_out (passo, linha) select '02 objetos', (jsonb_build_object('rls', (select relrowsecurity from pg_class where oid = 'dados.marcacoes_teste'::regclass), 'exec_service', (select count(*) from pg_proc p where p.proname in ('dados_marcar_teste','dados_desmarcar_teste','dados_testes') and has_function_privilege('service_role', p.oid, 'execute')), 'grants_tabela', (select count(*) from information_schema.role_table_grants where table_schema='dados' and table_name in ('marcacoes_teste','v_grupo_eventos_todos') and grantee in ('anon','authenticated')), 'invoker', (select reloptions from pg_class where oid='dados.v_grupo_eventos_todos'::regclass), 'exec_anon', (select count(*) from pg_proc p where (p.proname like 'dados_atm%' or p.proname in ('dados_marcar_teste','dados_desmarcar_teste','dados_testes')) and has_function_privilege('anon', p.oid, 'execute')), 'exec_auth', (select count(*) from pg_proc p where (p.proname like 'dados_atm%' or p.proname in ('dados_marcar_teste','dados_desmarcar_teste','dados_testes')) and has_function_privilege('authenticated', p.oid, 'execute')), 'sobrecargas', (select count(*) from pg_proc where proname like 'dados_atm%'), 'periodo', (select periodo_inicio || '..' || periodo_fim from dados.dashboards where chave = 'atm-elaine-1-2026-10')))::text;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '03 sem marca, tudo (md5 igual ao antes?)', (jsonb_build_object('md5', (select md5((to_jsonb(r) - 'atualizado_em' - 'periodo_de' - 'periodo_ate' - 'leads_teste' - 'grupo_teste' - 'vendas_teste' - 'receita_teste_bruta')::text) from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01') r), 'serie', (select jsonb_build_object('dias', count(*), 'de', min(dia), 'ate', max(dia), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10', null, (now() at time zone 'America/Sao_Paulo')::date)), 'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_leads('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01') x), 'canais', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01') x), 'comp', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_comparecimento('atm-elaine-1-2026-10') x), 'pos', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from (select ciclo, ate is null a, vendas, compradores, receita_bruta, conversao_pct from public.dados_atm_pos_live('atm-elaine-1-2026-10')) x)))::text;

insert into pg_temp._z_out (passo, linha) select '03 sem marca, periodo do evento', ((select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;

insert into pg_temp._z_out (passo, linha) select '03 sem marca, serie do evento', ((select jsonb_build_object('dias', count(*), 'de', min(dia), 'ate', max(dia), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')))::text;

insert into pg_temp._z_out (passo, linha) select '03 grupo_numeros', ((select jsonb_build_object('numeros', count(*), 'teste', count(*) filter (where teste), 'lead', count(*) filter (where eh_lead)) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01', true)))::text;

-- item 2: marca os números que entraram em 06/10 (horário de Brasília) como equipe
-- 20261008191100: marca como "equipe" os números que entraram no grupo do ATM 1 da Elaine em 06/10/2026
--
-- STATUS: ver 20261008191000.explain.md. Depende de 20261008191000.
-- POR QUE: pedido do Victor (08/10/2026): em 06/10 (horário de Brasília) entraram no grupo 'ATM 10/26' 11 eventos de
--   7 números únicos, entre 17:42 e 18:39, todos da equipe (antes de a captação começar em 07/10). Marcar, não apagar:
--   os eventos ficam em crm.evento_jornada e saem das contas do dashboard pela marcação.
-- Quem marcou: não há usuário logado numa migration; marcado_por fica nulo e marcado_por_email registra a origem.
-- PARA VOLTAR: update dados.marcacoes_teste set desmarcado_em = now(), desmarcado_por_email = 'reversão 20261008191100'
--              where chave = 'atm-elaine-1-2026-10' and marcado_por_email = 'migration 20261008191100' and desmarcado_em is null;
-- IDEMPOTENTE: on conflict do nothing (uma marcação ativa por número).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('dados.marcacoes_teste') is null then
    raise exception 'premissa: 20261008191000 não aplicada';
  end if;
  if (select count(distinct right(j.fone_key, 8)) from crm.evento_jornada j
       where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
         and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06') <> 7 then
    raise exception 'premissa: esperava 7 números em 06/10; conferir antes de marcar';
  end if;
end
$g$;

insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
select distinct 'atm-elaine-1-2026-10', 'fone', right(j.fone_key, 8), 'equipe', null::uuid, 'migration 20261008191100'
  from crm.evento_jornada j
 where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
   and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06'
on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;

-- 20261008191100: marca como "equipe" os números que entraram no grupo do ATM 1 da Elaine em 06/10/2026
--
-- STATUS: ver 20261008191000.explain.md. Depende de 20261008191000.
-- POR QUE: pedido do Victor (08/10/2026): em 06/10 (horário de Brasília) entraram no grupo 'ATM 10/26' 11 eventos de
--   7 números únicos, entre 17:42 e 18:39, todos da equipe (antes de a captação começar em 07/10). Marcar, não apagar:
--   os eventos ficam em crm.evento_jornada e saem das contas do dashboard pela marcação.
-- Quem marcou: não há usuário logado numa migration; marcado_por fica nulo e marcado_por_email registra a origem.
-- PARA VOLTAR: update dados.marcacoes_teste set desmarcado_em = now(), desmarcado_por_email = 'reversão 20261008191100'
--              where chave = 'atm-elaine-1-2026-10' and marcado_por_email = 'migration 20261008191100' and desmarcado_em is null;
-- IDEMPOTENTE: on conflict do nothing (uma marcação ativa por número).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('dados.marcacoes_teste') is null then
    raise exception 'premissa: 20261008191000 não aplicada';
  end if;
  if (select count(distinct right(j.fone_key, 8)) from crm.evento_jornada j
       where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
         and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06') <> 7 then
    raise exception 'premissa: esperava 7 números em 06/10; conferir antes de marcar';
  end if;
end
$g$;

insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
select distinct 'atm-elaine-1-2026-10', 'fone', right(j.fone_key, 8), 'equipe', null::uuid, 'migration 20261008191100'
  from crm.evento_jornada j
 where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
   and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06'
on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;

insert into pg_temp._z_out (passo, linha) select '04 marcados pela 20261008191100 (2 passadas)', ((select jsonb_build_object('ativas', count(*), 'equipe', count(*) filter (where motivo='equipe'), 'origem', min(marcado_por_email)) from dados.marcacoes_teste where chave = 'atm-elaine-1-2026-10'))::text;

do $m$ declare r record; n int := 0; begin
  for r in select distinct j.fone_key from crm.evento_jornada j where j.fonte='sendflow' and j.tag='ATM 10/26' and j.tipo='entrada' and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06' loop
    n := n + public.dados_marcar_teste('atm-elaine-1-2026-10', null, r.fone_key, 'equipe');
  end loop;
  insert into pg_temp._z_out (passo, linha) values ('04 remarcar (deve ser 0)', n::text);
end $m$;
insert into pg_temp._z_out (passo, linha) select '05 depois, periodo do evento', ((select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;

insert into pg_temp._z_out (passo, linha) select '05 depois, tudo', ((select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01') r))::text;

insert into pg_temp._z_out (passo, linha) select '05 depois, serie do evento', ((select jsonb_build_object('dias', count(*), 'de', min(dia), 'ate', max(dia), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')))::text;

insert into pg_temp._z_out (passo, linha) select '05 depois, serie 06/10', ((select jsonb_build_object('dias', count(*), 'de', min(dia), 'ate', max(dia), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10', date '2026-10-06', date '2026-10-06')))::text;

insert into pg_temp._z_out (passo, linha) select '05 grupo_numeros', ((select jsonb_build_object('sem_teste', (select count(*) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01')), 'com_teste', (select count(*) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01', true)), 'motivo_equipe', (select count(*) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', date '2000-01-01', date '2100-01-01', true) where teste_motivo = 'equipe'))))::text;

insert into pg_temp._z_out (passo, linha) select '05 testes', ((select jsonb_build_object('ativas', count(*), 'fone', count(*) filter (where tipo='fone')) from public.dados_testes('atm-elaine-1-2026-10')))::text;

-- lead: marca o lead mais antigo (e-mail + telefone), confere, desmarca
create temp table _z_l on commit drop as select x.email, x.telefone from public.dados_atm_leads('atm-elaine-1-2026-10') x order by x.primeiro_em, x.email limit 1;
insert into pg_temp._z_out (passo, linha) select '06 marcar lead', ((select public.dados_marcar_teste('atm-elaine-1-2026-10', l.email, l.telefone) from pg_temp._z_l l))::text;

insert into pg_temp._z_out (passo, linha) select '06 lead marcado', (jsonb_build_object('resumo', (select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10') r), 'leads_sem', (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10')), 'leads_com', (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, true)), 'teste_flag', (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, true) where teste)))::text;

insert into pg_temp._z_out (passo, linha) select '06 desmarcar lead', ((select public.dados_desmarcar_teste('atm-elaine-1-2026-10', l.email, l.telefone) from pg_temp._z_l l))::text;

insert into pg_temp._z_out (passo, linha) select '06 lead desmarcado', (jsonb_build_object('resumo', (select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10') r), 'historico', (select count(*) from dados.marcacoes_teste where desmarcado_em is not null)))::text;

-- períodos: confere com contagem direta por dia
insert into pg_temp._z_out (passo, linha) select '07 periodo 07/10', (jsonb_build_object('rpc', (select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2026-10-07', date '2026-10-07') r), 'direto_leads', (select count(*) from dados.atm_leads('atm-elaine-1-2026-10') x where not x.teste and (x.primeiro_em at time zone 'America/Sao_Paulo')::date = date '2026-10-07')))::text;

insert into pg_temp._z_out (passo, linha) select '07 periodo 08/10', (jsonb_build_object('rpc', (select jsonb_build_object('leads', r.leads, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct, 'evasao', r.evasao_pct, 'disparos', r.disparos_qtd, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'cpl', r.cpl_centavos, 'leads_teste', r.leads_teste, 'grupo_teste', r.grupo_teste, 'vendas_teste', r.vendas_teste, 'receita_teste', r.receita_teste_bruta, 'de', r.periodo_de, 'ate', r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2026-10-08', date '2026-10-08') r), 'direto_leads', (select count(*) from dados.atm_leads('atm-elaine-1-2026-10') x where not x.teste and (x.primeiro_em at time zone 'America/Sao_Paulo')::date = date '2026-10-08')))::text;

insert into pg_temp._z_out (passo, linha) select '07 limites', (jsonb_build_object('ini', (select ini from dados.periodo(null,null,date '2026-10-07',date '2026-10-07')), 'fim', (select fim from dados.periodo(null,null,date '2026-10-07',date '2026-10-07'))))::text;

do $rc$ declare r text := ''; begin
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', null, null); r := r || 'vazio=ok '; exception when others then r := r || 'vazio=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', 'a@b.c', null, 'outro'); r := r || 'motivo=ok '; exception when others then r := r || 'motivo=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', null, '123'); r := r || 'fone_curto=ok '; exception when others then r := r || 'fone_curto=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2026-10-09', date '2026-10-08'); r := r || 'periodo_invertido=ok '; exception when others then r := r || 'periodo_invertido=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('nao-existe-2026-01', 'a@b.c'); r := r || 'chave=ok '; exception when others then r := r || 'chave=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_serie_diaria('atm-elaine-1-2026-10', date '2000-01-01', null); r := r || 'serie_longa=ok '; exception when others then r := r || 'serie_longa=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', null, '1100000009'); r := r || 'fone_fora=ok '; exception when others then r := r || 'fone_fora=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('clinica-miami-2026-12', null, '1100000009'); r := r || 'outro_modelo=ok '; exception when others then r := r || 'outro_modelo=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('08 recusas equipe', r);
end $rc$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000e0510","role":"authenticated"}', true);
do $rc$ declare r text := ''; begin
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', 'a@b.c'); r := r || 'marcar=ok '; exception when others then r := r || 'marcar=' || sqlstate || ' '; end;
  begin perform public.dados_desmarcar_teste('atm-elaine-1-2026-10', 'a@b.c'); r := r || 'desmarcar=ok '; exception when others then r := r || 'desmarcar=' || sqlstate || ' '; end;
  begin perform * from public.dados_testes('atm-elaine-1-2026-10'); r := r || 'testes=ok '; exception when others then r := r || 'testes=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10'); r := r || 'grupo_numeros=ok '; exception when others then r := r || 'grupo_numeros=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_resumo('atm-elaine-1-2026-10'); r := r || 'resumo=ok '; exception when others then r := r || 'resumo=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('08 recusas nao equipe', r);
end $rc$;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $rc$ declare r text := ''; begin
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', 'a@b.c'); r := r || 'marcar=ok '; exception when others then r := r || 'marcar=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10'); r := r || 'grupo_numeros=ok '; exception when others then r := r || 'grupo_numeros=' || sqlstate || ' '; end;
  begin perform * from dados.marcacoes_teste; r := r || 'tabela=ok '; exception when others then r := r || 'tabela=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('08 recusas anon', r);
end $rc$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $rc$ declare r text := ''; begin
  begin perform * from dados.marcacoes_teste; r := r || 'tabela_direto=ok '; exception when others then r := r || 'tabela_direto=' || sqlstate || ' '; end;
  begin insert into dados.marcacoes_teste (chave, tipo, valor) values ('atm-elaine-1-2026-10', 'email', 'a@b.c'); r := r || 'insert_direto=ok '; exception when others then r := r || 'insert_direto=' || sqlstate || ' '; end;
  begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', 'zz-ensaio@exemplo.invalid'); r := r || 'marcar_fora_do_evento=ok '; exception when others then r := r || 'marcar_fora_do_evento=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('08 authenticated equipe', r);
end $rc$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '09 tempo ms', (jsonb_build_object('dados_atm_resumo', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_resumo('atm-elaine-1-2026-10')) c), 'dados_atm_leads', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10')) c), 'dados_atm_serie_diaria', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')) c), 'dados_atm_grupo_numeros', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10')) c), 'dados_atm_comparecimento', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_comparecimento('atm-elaine-1-2026-10')) c), 'dados_atm_pos_live', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_pos_live('atm-elaine-1-2026-10')) c)))::text;

insert into pg_temp._z_out (passo, linha) select '09 presencial depois', (jsonb_build_object('resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r), 'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x)))::text;

select set_config('request.jwt.claims', '{}', true);

-- reversão
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

-- (notify fora do ensaio)


select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '10 revertido resumo md5', ((select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;

insert into pg_temp._z_out (passo, linha) select '10 revertido objetos', (jsonb_build_object('tabela', to_regclass('dados.marcacoes_teste') is not null, 'todos', to_regclass('dados.v_grupo_eventos_todos') is not null, 'sobrecargas', (select count(*) from pg_proc where proname like 'dados_atm%'), 'marcar', (select count(*) from pg_proc where proname like 'dados_%marcar_teste'), 'cols', (select count(*) from information_schema.columns where table_schema='dados' and table_name='dashboards'), 'exec_auth', (select count(*) from pg_proc p where p.proname like 'dados_atm%' and has_function_privilege('authenticated', p.oid, 'execute')), 'exec_anon', (select count(*) from pg_proc p where p.proname like 'dados_atm%' and has_function_privilege('anon', p.oid, 'execute'))))::text;

insert into pg_temp._z_out (passo, linha) select '10 revertido md5 leads/canais/comp/pos', (jsonb_build_object('leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_leads('atm-elaine-1-2026-10') x), 'canais', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10') x), 'comp', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_atm_comparecimento('atm-elaine-1-2026-10') x), 'pos', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from (select ciclo, ate is null a, vendas, compradores, receita_bruta, conversao_pct from public.dados_atm_pos_live('atm-elaine-1-2026-10')) x)))::text;

insert into pg_temp._z_out (passo, linha) select '10 revertido presencial', (jsonb_build_object('resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r), 'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by to_jsonb(x)::text), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x)))::text;

select set_config('request.jwt.claims', '{}', true);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
