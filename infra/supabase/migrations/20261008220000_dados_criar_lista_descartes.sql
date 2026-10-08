-- 20261008220000: motivo do descarte na "Lista de origem" do dashboard ATM
--
-- STATUS: ver 20261008220000.explain.md. Depende de 20261008161000 e seguintes (aplicadas).
-- Reversão: 20261008220000_reversao.sql. Ensaio: 20261008220000_ensaio.sql.
--
-- POR QUE (pedido do Victor, 08/10/2026): "20 leads sem identificar de que base é? confere isso". A conferência do
--   Maestro deu 0 divergência entre lista_origem e as Listas 1/2; parte dos "fora_das_listas" está na aba Descartados
--   de uma das listas, com o motivo na coluna "Por que saiu". O dashboard passa a mostrar esse motivo.
--
-- O QUE FAZ
--   a. dados.lista_descartes (RLS, sem grant): chave, lista (lista_1 | lista_2), motivo (string EXATA de "Por que saiu"),
--      email_norm, fone_key, importacao. Sem nome. Carga dos JSON das abas Descartados fora do repo (dado pessoal),
--      por service_role/postgres, registrada no explain.
--   b. dados.atm_leads: lista_origem ganha o valor 'descartado' (fora das Listas 1 e 2, mas em Descartados);
--      'fora_das_listas' fica só para quem não está em nenhuma. Duas colunas novas no FIM: descarte_motivo (texto exato)
--      e descarte_lista (lista_1 | lista_2). Se o lead estiver nos Descartados das duas, vale o da Lista 1.
--   c. public.dados_atm_leads: mesmas 2 colunas no fim (mesma assinatura, mesmo grant).
--
-- AS 5 PERGUNTAS
--   escala: ~6 mil linhas por edição; leads ~1 mil. índice: (chave, email_norm) e (chave, right(fone_key, 8)).
--   frequência: leitura do modal. repetição: 1 lateral por lead. reversão: 20261008220000_reversao.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regclass('dados.lista_membros') is null or to_regprocedure('public.dados_atm_leads(text,date,date,boolean)') is null then
    raise exception 'premissa: modelo seminario-atm com período (20261008191000) não aplicado';
  end if;
end
$g$;

create table if not exists dados.lista_descartes (
  id             bigint generated always as identity primary key,
  chave          text not null references dados.dashboards(chave) on delete restrict,
  lista          text not null check (lista in ('lista_1', 'lista_2')),
  motivo         text not null check (length(btrim(motivo)) between 1 and 200),
  email_norm     text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key       text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  importacao     text not null check (length(btrim(importacao)) between 3 and 120),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null)
);
comment on table dados.lista_descartes is
  'Aba Descartados das Listas 1 e 2 de cada edição: quem saiu da lista e o motivo (texto exato da coluna "Por que saiu"). Sem nome. Lida por dados.atm_leads para a lista de origem. 20261008220000.';
create index if not exists lista_descartes_email_idx on dados.lista_descartes (chave, email_norm);
create index if not exists lista_descartes_fone_idx on dados.lista_descartes (chave, right(fone_key, 8));
alter table dados.lista_descartes enable row level security;
revoke all on dados.lista_descartes from public, anon, authenticated;
drop trigger if exists lista_descartes_carimbar on dados.lista_descartes;
create trigger lista_descartes_carimbar before update on dados.lista_descartes
  for each row execute function public.tg_carimbar_atualizado_em();

-- b/c. leitura (a assinatura das RPCs não muda; o tipo de retorno ganha 2 colunas no fim)
drop function if exists public.dados_atm_leads(text, date, date, boolean);
drop function if exists dados.atm_leads(text);
create or replace function dados.atm_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean, descarte_motivo text, descarte_lista text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000; teste marcado no evento em 20261008191000; saída da foto (>=) em 20261008200000
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
$function$
;

create or replace function public.dados_atm_leads(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid, teste boolean, descarte_motivo text, descarte_lista text)
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
  select * from dados.atm_leads(d.chave) x
   where x.primeiro_em >= v_ini and x.primeiro_em < v_fim
     and (coalesce(p_incluir_teste, false) or not x.teste)
   order by x.primeiro_em desc, x.email;
end
$function$
;

revoke all on function dados.atm_leads(text) from public, anon, authenticated;
revoke all on function public.dados_atm_leads(text, date, date, boolean) from public, anon, service_role;
grant execute on function public.dados_atm_leads(text, date, date, boolean) to authenticated;

do $p$
begin
  if not has_function_privilege('authenticated', 'public.dados_atm_leads(text,date,date,boolean)', 'execute')
     or has_function_privilege('anon', 'public.dados_atm_leads(text,date,date,boolean)', 'execute')
     or has_table_privilege('authenticated', 'dados.lista_descartes', 'select') then
    raise exception 'pós-condição: grant errado';
  end if;
end
$p$;

notify pgrst, 'reload schema';
