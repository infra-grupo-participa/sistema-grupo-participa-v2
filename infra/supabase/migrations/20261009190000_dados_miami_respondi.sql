-- 20261009190000: Clínica Miami (clinica-miami-2026-12): respostas do Respondi em tempo real (webhook) e RPCs das abas
-- "Diamantes" e "Fichas de interesse".
--
-- STATUS: ver 20261009190000.explain.md.
-- POR QUE: pedido do Victor (09/10/2026, .maestri/entregas/pedido-miami-clinica.md). As duas fichas já entram em
--   respondi.respostas pelo respondi-sync (1x ao dia, 09:10 UTC); o dashboard precisa delas na hora. O webhook do Respondi
--   (Edge respondi-webhook) grava na MESMA tabela, com o MESMO uuid (respondent_id do webhook = uuid da API, conferido
--   em 09/10 pelo ID das planilhas), então sync e webhook não duplicam.
-- O QUE FAZ:
--   1. dados.dashboard_formularios: qual formulário do Respondi é a ficha 'interesse' / 'diamantes' de cada dashboard.
--      É também a lista de formulários que o webhook aceita.
--   2. dados.dashboard_lista_pessoas: a Lista Diamantes (só nome, como na planilha); carga por script (dado pessoal
--      fora do repo), com casamento manual opcional (resposta_uuid_manual).
--   3. respondi.webhook_log (sem dado pessoal) e respondi.webhook_chave() (segredo da URL, Vault respondi_webhook_chave).
--   4. dados.nome_tokens(): casamento de nome igual ao da planilha (sem acento/maiúscula, partes omitidas).
--   5. public.dados_miami_diamantes(p_chave) e public.dados_miami_interesse(p_chave): só equipe com acesso ao dashboard
--      (dados.cadastro), GRANT a authenticated.
-- AS 5 PERGUNTAS: escala ~100 respostas e ~80 nomes por evento; índice PK/únicos novos + respondi.respostas(form_slug)
--   já existente; frequência: 1 gravação por resposta enviada, leitura a cada abertura da aba; repetição: on conflict
--   (uuid) no webhook; reversão: 20261009190000_reversao.sql.
-- IDEMPOTENTE: create if not exists / create or replace / on conflict.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- 1. formulário por dashboard
create table if not exists dados.dashboard_formularios (
  chave      text not null references dados.dashboards (chave) on update cascade on delete cascade,
  papel      text not null check (papel in ('interesse', 'diamantes')),
  form_slug  text not null references respondi.formularios (slug),
  criado_em  timestamptz not null default now(),
  primary key (chave, papel)
);
create index if not exists dashboard_formularios_slug on dados.dashboard_formularios (form_slug);
alter table dados.dashboard_formularios enable row level security;
revoke all on dados.dashboard_formularios from public, anon, authenticated;

insert into dados.dashboard_formularios (chave, papel, form_slug)
select 'clinica-miami-2026-12', x.papel, x.slug
  from (values ('interesse', 'xmaNmRIV'), ('diamantes', 'HFaSnLRf')) x (papel, slug)
 where exists (select 1 from dados.dashboards d where d.chave = 'clinica-miami-2026-12')
   and exists (select 1 from respondi.formularios f where f.slug = x.slug)
on conflict (chave, papel) do nothing;

-- 2. lista de pessoas (Lista Diamantes)
create table if not exists dados.dashboard_lista_pessoas (
  id                    bigserial primary key,
  chave                 text not null references dados.dashboards (chave) on update cascade on delete cascade,
  lista                 text not null check (lista in ('diamantes')),
  ordem                 int not null,
  nome                  text not null check (btrim(nome) <> '' and length(nome) <= 200),
  resposta_uuid_manual  uuid,
  importacao            text,
  criado_em             timestamptz not null default now(),
  unique (chave, lista, ordem)
);
alter table dados.dashboard_lista_pessoas enable row level security;
revoke all on dados.dashboard_lista_pessoas from public, anon, authenticated;
revoke all on sequence dados.dashboard_lista_pessoas_id_seq from public, anon, authenticated;

-- 3. webhook: log sem dado pessoal e segredo
create table if not exists respondi.webhook_log (
  id             bigserial primary key,
  recebido_em    timestamptz not null default now(),
  form_slug      text,
  resposta_uuid  uuid,
  resultado      text not null check (resultado in ('gravada', 'ignorada_formulario', 'invalida', 'erro')),
  detalhe        text check (length(detalhe) <= 300)
);
create index if not exists webhook_log_recebido on respondi.webhook_log (recebido_em desc);
alter table respondi.webhook_log enable row level security;
revoke all on respondi.webhook_log from public, anon, authenticated, service_role;
revoke all on sequence respondi.webhook_log_id_seq from public, anon, authenticated, service_role;

create or replace function respondi.webhook_chave()
 returns text
 language sql
 stable security definer
 set search_path to ''
as $f$
  select decrypted_secret from vault.decrypted_secrets where name = 'respondi_webhook_chave';
$f$;
revoke all on function respondi.webhook_chave() from public, anon, authenticated, service_role;

-- 4. nome em partes, sem acento, minúsculo, sem conectivos (como a coluna B do Relatório da planilha)
create or replace function dados.nome_tokens(p text)
 returns text[]
 language sql
 immutable
 set search_path to ''
as $f$
  select coalesce(array_agg(t order by o), '{}')
    from unnest(regexp_split_to_array(
           btrim(regexp_replace(translate(lower(coalesce(p, '')),
                  'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'), '[^a-z ]+', ' ', 'g')), '\s+'))
         with ordinality u (t, o)
   where t <> '' and t not in ('de', 'da', 'do', 'das', 'dos', 'e');
$f$;

-- casa quando o 1º nome é igual, o nome menor tem 2+ partes e todas estão no maior
create or replace function dados.nome_casa(a text[], b text[])
 returns boolean
 language sql
 immutable
 set search_path to ''
as $f$
  select cardinality(a) >= 1 and cardinality(b) >= 1 and a[1] = b[1]
     and least(cardinality(a), cardinality(b)) >= 2
     and (a <@ b or b <@ a);
$f$;

-- resposta de uma pergunta pelo começo do texto da pergunta (texto exato do formulário)
create or replace function dados.respondi_valor(p_respostas jsonb, p_pergunta text)
 returns text
 language sql
 immutable
 set search_path to ''
as $f$
  select nullif(x ->> 'v', '')
    from jsonb_array_elements(coalesce(p_respostas, '[]'::jsonb)) x
   where left(x ->> 'p', length(p_pergunta)) = p_pergunta
   limit 1;
$f$;

create or replace function dados.data_br(p text)
 returns date
 language plpgsql
 immutable
 set search_path to ''
as $f$
begin
  if p ~ '^\d{2}/\d{2}/\d{4}$' then
    return to_date(p, 'DD/MM/YYYY');
  end if;
  return null;
exception when others then
  return null;
end
$f$;

revoke all on function dados.nome_tokens(text), dados.nome_casa(text[], text[]), dados.respondi_valor(jsonb, text),
  dados.data_br(text) from public, anon;

-- 5a. aba Diamantes
drop function if exists public.dados_miami_diamantes(text);
create function public.dados_miami_diamantes(p_chave text)
 returns table (lista_ordem int, lista_nome text, status text, casamento text, resposta_uuid uuid,
                respondido_em timestamptz, n_respostas int, nome_formulario text, email text, telefone text,
                grupo text, situacao text, situacao_codigo text, chegada text, chegada_data date, retorno text,
                retorno_data date, aeroporto text, hospedagem text, acompanhado text, acompanhantes text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'diamantes');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (  -- uma linha por pessoa: a resposta mais recente
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n,
           dados.respondi_valor(r.respostas, 'Nome completo') as nome_f
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  l as (
    select lp.ordem, lp.nome, lp.resposta_uuid_manual, dados.nome_tokens(lp.nome) as tk
      from dados.dashboard_lista_pessoas lp
     where lp.chave = d.chave and lp.lista = 'diamantes'
  ),
  par as (  -- cada nome da lista com a sua resposta (manual vence; senão a mais recente que casa pelo nome)
    select l.ordem, l.nome, m.uuid, m.casamento
      from l
      left join lateral (
        select p.uuid, case when p.uuid = l.resposta_uuid_manual then 'manual' else 'nome' end as casamento
          from p
         where p.uuid = l.resposta_uuid_manual
            or (l.resposta_uuid_manual is null and dados.nome_casa(l.tk, dados.nome_tokens(p.nome_f)))
         order by (p.uuid = l.resposta_uuid_manual) desc, p.respondido_em desc
         limit 1) m on true
  ),
  linhas as (
    select par.ordem, par.nome, case when par.uuid is null then 'pendente' else 'respondeu' end as st, par.casamento, par.uuid
      from par
    union all
    select null, null, 'fora_da_lista', null, p.uuid
      from p
     where not exists (select 1 from par where par.uuid = p.uuid)
  )
  select li.ordem, li.nome, li.st, li.casamento, p.uuid, p.respondido_em, p.n, p.nome_f, p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é o seu grupo'),
         v.sit,
         case when v.sit like 'Já estou confirmado%' then 'confirmado'
              when v.sit like 'Estou me organizando%' then 'organizando'
              when v.sit like 'Já sei que não%' then 'nao_vai' end,
         v.cheg, dados.data_br(v.cheg), v.ret, dados.data_br(v.ret),
         dados.respondi_valor(p.respostas, 'Em qual aeroporto você chegará'),
         dados.respondi_valor(p.respostas, 'Onde você ficará hospedado'),
         dados.respondi_valor(p.respostas, 'Você estará acompanhado'),
         dados.respondi_valor(p.respostas, 'Quantas pessoas irão com você')
    from linhas li
    left join p on p.uuid = li.uuid
    left join lateral (select dados.respondi_valor(p.respostas, 'Acerca dos eventos internacionais') as sit,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de chegada') as cheg,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de retorno') as ret) v on true
   order by li.ordem nulls last, p.respondido_em, p.uuid;
end
$function$;
revoke all on function public.dados_miami_diamantes(text) from public, anon;
grant execute on function public.dados_miami_diamantes(text) to authenticated;

-- 5b. aba Fichas de interesse
drop function if exists public.dados_miami_interesse(text);
create function public.dados_miami_interesse(p_chave text)
 returns table (resposta_uuid uuid, respondido_em timestamptz, n_respostas int, nome text, email text, telefone text,
                turma text, passaporte text, visto text, planos text, comprou_passagem text, data_passagem text,
                confirma_pre_venda text, deseja_programa text, comprou boolean, compra_status text,
                compra_transacao text, compra_em timestamptz, casou_por text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'interesse');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  t as (
    select tr.transacao, tr.status_grupo, coalesce(tr.aprovado_em, tr.pedido_em) as em,
           lower(btrim(tr.email)) as email, right(regexp_replace(coalesce(tr.telefone, ''), '\D', '', 'g'), 8) as fone8,
           case tr.status_grupo when 'pago' then 1 when 'em_aberto' then 2 when 'atrasado' then 3 when 'estornado' then 4
                                when 'recusado' then 5 when 'expirado' then 6 else 7 end as prio
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) tr
     where v_slug is not null
  )
  select p.uuid, p.respondido_em, p.n,
         dados.respondi_valor(p.respostas, 'Qual é o seu nome completo'), p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é a sua turma'),
         dados.respondi_valor(p.respostas, 'Você tem passaporte válido'),
         dados.respondi_valor(p.respostas, 'Você tem visto americano válido'),
         dados.respondi_valor(p.respostas, 'Quais são os seus planos para a viagem'),
         dados.respondi_valor(p.respostas, 'Você já comprou a sua passagem'),
         dados.respondi_valor(p.respostas, 'Qual é a data da sua passagem'),
         dados.respondi_valor(p.respostas, 'Você confirma que fará a inscrição na pré-venda'),
         dados.respondi_valor(p.respostas, 'Você deseja participar do programa Holding Trip Miami'),
         coalesce(c.status_grupo = 'pago', false), c.status_grupo, c.transacao, c.em, c.por
    from p
    left join lateral (
      select t.transacao, t.status_grupo, t.em,
             case when t.email = nullif(lower(btrim(p.email)), '') then 'email' else 'telefone' end as por
        from t
       where t.email = nullif(lower(btrim(p.email)), '')
          or (length(t.fone8) = 8 and length(coalesce(p.telefone, '')) >= 10 and t.fone8 = right(p.telefone, 8))
       order by t.prio, (t.email = nullif(lower(btrim(p.email)), '')) desc, t.em desc nulls last, t.transacao
       limit 1) c on true
   order by coalesce(c.status_grupo = 'pago', false), p.respondido_em desc, p.uuid;
end
$function$;
revoke all on function public.dados_miami_interesse(text) from public, anon;
grant execute on function public.dados_miami_interesse(text) to authenticated;

do $c$
begin
  if not has_function_privilege('authenticated', 'public.dados_miami_diamantes(text)', 'execute')
     or has_function_privilege('anon', 'public.dados_miami_interesse(text)', 'execute')
     or has_table_privilege('authenticated', 'dados.dashboard_lista_pessoas', 'select')
     or has_function_privilege('service_role', 'respondi.webhook_chave()', 'execute') then
    raise exception '20261009190000: permissões erradas';
  end if;
end
$c$;
