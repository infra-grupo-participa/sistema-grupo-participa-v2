-- Ensaio de 20261013200000 (lista do pré-checkout do ATM). Transação DESFEITA (rollback no fim).
-- Gerado com o corpo byte a byte de 20261013200000_dados_atm_pre_checkout.sql e de 20261013200000_reversao.sql (sem o notify).
-- Dado falso, tudo desfeito: (a) uma marcação de teste para a pessoa do pré-checkout do ATM, escolhida dentro do SQL;
-- (b) o lista_ac do dashboard do ATM trocado pelo lista_ac_leads, para o pré-checkout passar a ter ~400 pessoas que são
-- leads (prova de escala e de que os atributos saem iguais aos de dados.atm_leads). Sem trigger nem cron em dados.dashboards.
-- Nenhum e-mail, nome, telefone ou id sai na saída: só contagens, booleanos, sqlstate e plano.
-- Prova: (1) a função não existe antes; (2) migration roda com a pós-condição; (3) ATM real: lista = card
-- (dados.atm_pre_checkout) = dados_atm_resumo.pre_checkout_pessoas, no período; (4) marcada como teste: some com false,
-- volta com true e teste=true; resumo cai junto; (5) permissões; (6) plano 2x; (7) escala e atributos = atm_leads;
-- (8) reversão apaga.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '240s';
create temp table _z_out (em serial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon, service_role;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon, service_role;
create temp table _z_ids (papel text primary key, id uuid, txt text) on commit drop;
grant select on pg_temp._z_ids to authenticated, anon, service_role;
create temp table _z_p (rodada text, email text, nome text, telefone text, primeiro_em timestamptz, fonte text,
                        utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text,
                        estado text, entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text,
                        turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean,
                        pessoa_id uuid, teste boolean, descarte_motivo text, descarte_lista text, eh_lead boolean) on commit drop;
grant all on pg_temp._z_p to authenticated;
create temp table _z_res (janela text, pc int, de date, ate date) on commit drop;
grant all on pg_temp._z_res to authenticated;

insert into pg_temp._z_out (passo, linha) values ('00 txid', txid_current()::text);
insert into pg_temp._z_out (passo, linha)
  select '01 antes: funcao existe / marcacoes_teste total',
         (to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null)::text
         || ' / ' || (select count(*) from dados.marcacoes_teste)::text;

-- ===== migration (corpo de 20261013200000_dados_atm_pre_checkout.sql, sem o notify) =====
-- 20261013200000: lista de quem preencheu o pré-checkout da Sessão de Viabilidade (modal do card "Pré-checkout" do ATM)
--
-- STATUS: NÃO APLICADA. Escrita e ensaiada (BEGIN ... ROLLBACK) em 13/10/2026. Aplicar só com ok do Victor e do JP.
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
-- ===== fim da migration =====
insert into pg_temp._z_out (passo, linha)
  select '02 depois: existe / secdef / config / acl',
         (to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null)::text
         || ' / ' || p.prosecdef::text || ' / ' || array_to_string(p.proconfig, ',') || ' / ' || p.proacl::text
    from pg_proc p where p.oid = 'public.dados_atm_pre_checkout(text,date,date,boolean)'::regprocedure;
insert into pg_temp._z_out (passo, linha)
  select '02b contrato igual a dados_atm_leads + eh_lead (colunas e tipos, em ordem)',
         ((select array_agg(a.n || ':' || format_type(a.t, null) order by a.o)
             from pg_proc p, unnest(p.proargnames, p.proallargtypes, p.proargmodes) with ordinality a(n, t, m, o)
            where p.oid = 'public.dados_atm_leads(text,date,date,boolean)'::regprocedure and a.m = 't')
          || array['eh_lead:boolean']
          = (select array_agg(a.n || ':' || format_type(a.t, null) order by a.o)
               from pg_proc p, unnest(p.proargnames, p.proallargtypes, p.proargmodes) with ordinality a(n, t, m, o)
              where p.oid = 'public.dados_atm_pre_checkout(text,date,date,boolean)'::regprocedure and a.m = 't'))::text;

-- papéis (ids ficam só na tabela temporária)
insert into pg_temp._z_ids (papel, id)
  select 'master', m.perfil_id from acesso.master m join public.perfis p on p.id = m.perfil_id
   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1;
insert into pg_temp._z_ids (papel, id)
  select 'sem_contato', p.id from public.perfis p
   where p.status = 'ativo' and p.email ilike '%@advmais.com'
     and not exists (select 1 from acesso.master m where m.perfil_id = p.id)
     and not exists (select 1 from acesso.capacidade c where c.perfil_id = p.id and c.chave = 'contato.ver')
   order by p.id limit 1;
insert into pg_temp._z_ids (papel, id)
  select 'com_contato', p.id from public.perfis p
   where p.status = 'ativo' and p.email ilike '%@advmais.com'
     and not exists (select 1 from acesso.master m where m.perfil_id = p.id)
     and exists (select 1 from acesso.capacidade c where c.perfil_id = p.id and c.chave = 'contato.ver')
   order by p.id limit 1;
insert into pg_temp._z_ids (papel, id) values ('fora_equipe', '00000000-0000-4000-8000-0000000000e1');
insert into pg_temp._z_ids (papel, txt)
  select 'outro_modelo', d.chave from dados.dashboards d where d.ativo and d.modelo <> 'seminario-atm' order by d.chave limit 1;
insert into pg_temp._z_out (passo, linha)
  select '03 papeis achados', string_agg(papel, ',' order by papel) from pg_temp._z_ids;

-- (3) ATM real, como master
select set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_p select 'r1_false', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10') x;
insert into pg_temp._z_p select 'r1_true', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10', null, null, true) x;
insert into pg_temp._z_p select 'd12', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10', date '2026-10-12', date '2026-10-12') x;
insert into pg_temp._z_p select 'd13', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10', date '2026-10-13', date '2026-10-13') x;
insert into pg_temp._z_res select 'padrao', r.pre_checkout_pessoas, r.periodo_de, r.periodo_ate from public.dados_atm_resumo('atm-elaine-1-2026-10') r;
insert into pg_temp._z_res select 'd12', r.pre_checkout_pessoas, r.periodo_de, r.periodo_ate from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2026-10-12', date '2026-10-12') r;
insert into pg_temp._z_res select 'd13', r.pre_checkout_pessoas, r.periodo_de, r.periodo_ate from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2026-10-13', date '2026-10-13') r;
reset role;
insert into pg_temp._z_out (passo, linha)
  select '04 ATM real: false / true / card atm_pre_checkout no periodo / resumo pre_checkout_pessoas / periodo do resumo / mesmos e-mails do card',
         (select count(*) from pg_temp._z_p where rodada = 'r1_false')::text
         || ' / ' || (select count(*) from pg_temp._z_p where rodada = 'r1_true')::text
         || ' / ' || (select count(*) from dados.atm_pre_checkout('atm-elaine-1-2026-10') y, pg_temp._z_res r
                       where r.janela = 'padrao'
                         and y.primeiro_em >= r.de::timestamp at time zone 'America/Sao_Paulo'
                         and y.primeiro_em < (r.ate + 1)::timestamp at time zone 'America/Sao_Paulo')::text
         || ' / ' || (select pc from pg_temp._z_res where janela = 'padrao')::text
         || ' / ' || (select de || '..' || ate from pg_temp._z_res where janela = 'padrao')
         || ' / ' || (not exists ((select email from pg_temp._z_p where rodada = 'r1_false')
                                  except all (select y.email from dados.atm_pre_checkout('atm-elaine-1-2026-10') y))
                      and not exists ((select y.email from dados.atm_pre_checkout('atm-elaine-1-2026-10') y)
                                  except all (select email from pg_temp._z_p where rodada = 'r1_false')))::text;
insert into pg_temp._z_out (passo, linha)
  select '04b a linha: dominio @teste-vh.test / primeiro_em (Brasilia) / = quando do evento 27851 / eh_lead / no_pre_checkout / teste / fonte / ddd preenchido / estado preenchido / entrou_grupo / eh_aluno / lista_origem / comprou',
         string_agg((p.email like '%@teste-vh.test')::text
           || ' / ' || to_char(p.primeiro_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
           || ' / ' || coalesce((select (e.quando = p.primeiro_em and e.tipo = 'pre_checkout' and e.projeto_id = 75)::text
                                   from pessoas.eventos e where e.id = 27851), 'evento nao achado')
           || ' / ' || p.eh_lead::text || ' / ' || p.no_pre_checkout::text || ' / ' || p.teste::text
           || ' / ' || coalesce(p.fonte, 'nulo') || ' / ' || (p.ddd is not null)::text || ' / ' || (p.estado is not null)::text
           || ' / ' || coalesce(p.entrou_grupo::text, 'nulo') || ' / ' || coalesce(p.eh_aluno::text, 'nulo')
           || ' / ' || coalesce(p.lista_origem, 'nulo') || ' / ' || coalesce(p.comprou::text, 'nulo'), ' | ')
    from pg_temp._z_p p where p.rodada = 'r1_false';
insert into pg_temp._z_out (passo, linha)
  select '05 periodo: lista 12/10 / resumo 12/10 / lista 13/10 / resumo 13/10',
         (select count(*) from pg_temp._z_p where rodada = 'd12')::text || ' / ' || (select pc from pg_temp._z_res where janela = 'd12')::text
         || ' / ' || (select count(*) from pg_temp._z_p where rodada = 'd13')::text || ' / ' || (select pc from pg_temp._z_res where janela = 'd13')::text;

-- (4) marca a pessoa como teste (marcação sintética pelo e-mail, mecanismo de dados.teste_ativo)
insert into dados.marcacoes_teste (chave, tipo, valor, motivo)
  select 'atm-elaine-1-2026-10', 'email', p.email, 'teste' from pg_temp._z_p p where p.rodada = 'r1_false' order by p.email limit 1;
select set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_p select 'r2_false', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10') x;
insert into pg_temp._z_p select 'r2_true', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10', null, null, true) x;
insert into pg_temp._z_res select 'marcado', r.pre_checkout_pessoas, r.periodo_de, r.periodo_ate from public.dados_atm_resumo('atm-elaine-1-2026-10') r;
reset role;
insert into pg_temp._z_out (passo, linha)
  select '06 marcada: false / true / teste=true no true / resumo pre_checkout_pessoas / card atm_pre_checkout',
         (select count(*) from pg_temp._z_p where rodada = 'r2_false')::text
         || ' / ' || (select count(*) from pg_temp._z_p where rodada = 'r2_true')::text
         || ' / ' || (select count(*) from pg_temp._z_p where rodada = 'r2_true' and teste)::text
         || ' / ' || (select pc from pg_temp._z_res where janela = 'marcado')::text
         || ' / ' || (select count(*) from dados.atm_pre_checkout('atm-elaine-1-2026-10'))::text;

-- (5) permissões (a marcação de teste continua valendo aqui)
do $perm$
declare
  r record;
  n int;
  v_estado text;
  v_msg text;
begin
  for r in
    select * from (values
      (1, 'fora_equipe', 'authenticated', 'atm', false),
      (2, 'sem_contato', 'authenticated', 'atm', false),
      (3, 'com_contato', 'authenticated', 'atm', false),
      (4, 'com_contato', 'authenticated', 'atm', true),
      (5, 'master', 'authenticated', 'atm', true),
      (6, 'master', 'authenticated', 'outro_modelo', false),
      (7, 'master', 'authenticated', 'inexistente', false),
      (8, null, 'anon', 'atm', false),
      (9, null, 'service_role', 'atm', false)
    ) t(ordem, papel, papel_pg, chave, incluir_teste)
    order by ordem
  loop
    if r.papel is not null and not exists (select 1 from pg_temp._z_ids where papel = r.papel and id is not null) then
      insert into pg_temp._z_out (passo, linha) values ('07 perm ' || r.ordem || ' ' || r.papel, 'papel não achado, não testado');
      continue;
    end if;
    perform set_config('request.jwt.claims',
      case when r.papel is null then jsonb_build_object('role', r.papel_pg)::text
           else jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = r.papel), 'role', r.papel_pg)::text end, true);
    execute format('set local role %I', r.papel_pg);
    begin
      execute 'select count(*) from public.dados_atm_pre_checkout($1, null, null, $2)'
        into n
        using case r.chave when 'atm' then 'atm-elaine-1-2026-10'
                           when 'outro_modelo' then (select txt from pg_temp._z_ids where papel = 'outro_modelo')
                           else 'zz-nao-existe' end,
              r.incluir_teste;
      v_estado := 'ok'; v_msg := n || ' linhas';
    exception when others then
      v_estado := sqlstate; v_msg := sqlerrm;
    end;
    reset role;
    insert into pg_temp._z_out (passo, linha)
      values ('07 perm ' || r.ordem || ' ' || coalesce(r.papel, '-') || ' como ' || r.papel_pg || ' chave=' || r.chave || ' teste=' || r.incluir_teste,
              v_estado || ' (' || v_msg || ')');
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
end
$perm$;

-- (6) plano e tempo da RPC inteira, 2x (ATM real, como master, com a pessoa marcada: teste=true para devolver a linha)
do $ex$
declare r record; i int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
  set local role authenticated;
  for i in 1..2 loop
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_pre_checkout(''atm-elaine-1-2026-10'', null, null, true)' loop
      insert into pg_temp._z_out (passo, linha) values ('08 explain rpc atm ' || i, r."QUERY PLAN");
    end loop;
  end loop;
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
end
$ex$;

-- (7) escala e atributos: o pré-checkout do ATM passa a ler a lista de leads do AC (~400 pessoas, quase todas leads)
update dados.dashboards set lista_ac = lista_ac_leads where chave = 'atm-elaine-1-2026-10';
create temp table _z_al on commit drop as select * from dados.atm_leads('atm-elaine-1-2026-10');
do $esc$
declare r record; i int; t0 timestamptz;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
  set local role authenticated;
  t0 := clock_timestamp();
  insert into pg_temp._z_p select 'esc', x.* from public.dados_atm_pre_checkout('atm-elaine-1-2026-10', date '2000-01-01', date '2100-12-31', true) x;
  insert into pg_temp._z_out (passo, linha) values ('09 escala: ms da chamada', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  for i in 1..2 loop
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_pre_checkout(''atm-elaine-1-2026-10'', ''2000-01-01'', ''2100-12-31'', true)' loop
      insert into pg_temp._z_out (passo, linha) values ('09 explain escala ' || i, r."QUERY PLAN");
    end loop;
  end loop;
  t0 := clock_timestamp();
  perform count(*) from public.dados_atm_leads('atm-elaine-1-2026-10', date '2000-01-01', date '2100-12-31', true);
  insert into pg_temp._z_out (passo, linha) values ('09 referencia: ms de dados_atm_leads (mesmo periodo)', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
end
$esc$;
insert into pg_temp._z_out (passo, linha)
  select '10 escala: linhas / eh_lead=true / e-mail esta em atm_leads / eh_lead bate com atm_leads / no_pre_checkout todos true / leads com mesmo telefone',
         count(*)::text
         || ' / ' || count(*) filter (where p.eh_lead)::text
         || ' / ' || count(a.email)::text
         || ' / ' || (count(*) filter (where p.eh_lead is distinct from (a.email is not null)) = 0)::text
         || ' / ' || bool_and(p.no_pre_checkout)::text
         || ' / ' || count(*) filter (where a.email is not null and a.telefone is not distinct from p.telefone)::text
    from pg_temp._z_p p left join pg_temp._z_al a on a.email = p.email
   where p.rodada = 'esc';
insert into pg_temp._z_out (passo, linha)
  select '11 divergencias com atm_leads nos leads de mesmo telefone: ddd / estado / entrou_grupo / saiu_grupo / eh_aluno / instrucao / turma / lista_origem / seminario_origem / comprou / pessoa_id / descarte_motivo / descarte_lista / teste',
         count(*) filter (where p.ddd is distinct from a.ddd)::text
         || ' / ' || count(*) filter (where p.estado is distinct from a.estado)::text
         || ' / ' || count(*) filter (where p.entrou_grupo is distinct from a.entrou_grupo)::text
         || ' / ' || count(*) filter (where p.saiu_grupo is distinct from a.saiu_grupo)::text
         || ' / ' || count(*) filter (where p.eh_aluno is distinct from a.eh_aluno)::text
         || ' / ' || count(*) filter (where p.instrucao is distinct from a.instrucao)::text
         || ' / ' || count(*) filter (where p.turma is distinct from a.turma)::text
         || ' / ' || count(*) filter (where p.lista_origem is distinct from a.lista_origem)::text
         || ' / ' || count(*) filter (where p.seminario_origem is distinct from a.seminario_origem)::text
         || ' / ' || count(*) filter (where p.comprou is distinct from a.comprou)::text
         || ' / ' || count(*) filter (where p.pessoa_id is distinct from a.pessoa_id)::text
         || ' / ' || count(*) filter (where p.descarte_motivo is distinct from a.descarte_motivo)::text
         || ' / ' || count(*) filter (where p.descarte_lista is distinct from a.descarte_lista)::text
         || ' / ' || count(*) filter (where p.teste is distinct from a.teste)::text
    from pg_temp._z_p p join pg_temp._z_al a on a.email = p.email
   where p.rodada = 'esc' and a.telefone is not distinct from p.telefone;
insert into pg_temp._z_out (passo, linha)
  select '12 cobertura dos atributos no teste de escala: entrou_grupo=true / eh_aluno=true / lista_origem preenchida / descarte preenchido / estado preenchido',
         count(*) filter (where p.entrou_grupo)::text || ' / ' || count(*) filter (where p.eh_aluno)::text
         || ' / ' || count(*) filter (where p.lista_origem is not null)::text
         || ' / ' || count(*) filter (where p.descarte_motivo is not null)::text
         || ' / ' || count(*) filter (where p.estado is not null)::text
    from pg_temp._z_p p where p.rodada = 'esc';

-- (8) reversão (corpo de 20261013200000_reversao.sql, sem o notify)
-- Reversão de 20261013200000 (lista do pré-checkout da Sessão de Viabilidade do ATM).
-- A migration só criou public.dados_atm_pre_checkout(text, date, date, boolean); nenhuma função, view ou tabela existente mudou.
-- Depois de reverter, o modal do card "Pré-checkout" deixa de ter a lista (a chamada dá 404 no PostgREST); o card continua,
-- porque o número vem de public.dados_atm_resumo.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_atm_pre_checkout(text, date, date, boolean);

do $p$
begin
  if to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null then
    raise exception 'reversão: public.dados_atm_pre_checkout ainda existe';
  end if;
end
$p$;
insert into pg_temp._z_out (passo, linha)
  select '13 revertido: funcao existe', (to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null)::text;

select set_config('request.jwt.claims', '{}', true);
select passo, linha from pg_temp._z_out order by em;
rollback;
