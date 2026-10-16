-- Ensaio de 20261017020500 + 20261017020600 numa transação DESFEITA (rollback). Não grava nada em produção.
-- Prova: as duas funções nascem com as mesmas colunas das do ATM; a Clínica devolve os 7 disparos ligados, por canal e um por linha;
-- o período filtra; gate (equipe lê, chave inexistente P0002, dashboard de outro modelo P0002, fora da equipe 42501, anon 42501);
-- as funções do ATM não mudam (md5); explain (analyze, buffers); a reversão fecha limpa.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create temp table _z_md5 as select p.oid::regprocedure::text as f, md5(pg_get_functiondef(p.oid)) as m from pg_proc p
 where p.oid in ('public.dados_atm_disparos_canais(text,date,date)'::regprocedure, 'public.dados_atm_disparos_lista(text,date,date)'::regprocedure,
                 'public.dados_presencial_disparos(text)'::regprocedure, 'dados.presencial_cadastro(text)'::regprocedure, 'dados.atm_cadastro(text)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select '00 antes', jsonb_build_object(
  'funcoes_novas_existem', to_regprocedure('public.dados_presencial_disparos_canais(text,date,date)') is not null,
  'disparos_no_68', (select count(*) from mkt_mensageria.disparos where projeto_id = 68),
  'os_7_sem_projeto', (select count(*) from mkt_mensageria.disparos where id in (39935,41099,42695,44024,44512,39925,40560) and projeto_id is null))::text;

-- ===== 20261017020500 =====
-- 20261017020500: disparos da Clínica de Miami no mesmo formato do ATM (por canal e um por linha)
--
-- STATUS: ver 20261017020500.explain.md.
-- POR QUE: pedido do Victor (16/10/2026, card 17tya50h3b7): a aba de disparos da Clínica reaproveita os componentes do ATM
--   (canais + lista), que leem dados_atm_disparos_canais e dados_atm_disparos_lista. Essas duas só aceitam dashboard do
--   modelo seminário (dados.atm_cadastro). A existente dados_presencial_disparos(p_chave) tem outro formato (14 colunas).
-- O QUE FAZ: cria public.dados_presencial_disparos_canais(p_chave, p_de, p_ate) e public.dados_presencial_disparos_lista(p_chave,
--   p_de, p_ate), com EXATAMENTE as colunas e os tipos de retorno das duas do ATM (conferido contra pg_get_functiondef em
--   16/10/2026) e o mesmo corpo. Única diferença: o gate é dados.presencial_cadastro (só modelo presencial-base; 42501 sem acesso,
--   P0002 chave fora do cadastro). Período por dados.periodo(periodo_inicio, periodo_fim, p_de, p_ate): o cadastro da Clínica
--   tem os dois nulos, então sem p_de/p_ate não há limite (mesma regra de sempre: nulo = sem limite daquele lado).
--   Não altera dados.atm_cadastro, nem dados_atm_*, nem dados_presencial_disparos.
-- GRANTS: só authenticated; revoke de public, anon e service_role. Sem service_role.
-- AS 5 PERGUNTAS: escala = dezenas de disparos por projeto; índice = disparos_projeto_enviado_idx (projeto_id, enviado_em desc);
--   frequência = a cada abertura da aba; repetição = leitura pura (stable); reversão = 20261017020500_reversao.sql.
-- IDEMPOTENTE: create or replace.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.dados_presencial_disparos_canais(p_chave text, p_de date default null, p_ate date default null)
 returns table (canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
                falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- só o modelo presencial-base
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
$function$;

create or replace function public.dados_presencial_disparos_lista(p_chave text, p_de date default null, p_ate date default null)
 returns table (disparo_id bigint, data_hora timestamptz, enviado_em timestamptz, canal text, canal_pago boolean,
                tipo text, ferramenta text, numero text, campanha text, publico_lista text, publico_origem text,
                copy_texto text, copy_link text, tamanho_lista integer, entregues integer, lidas integer, cliques integer,
                falhas integer, custo_centavos integer, origem text, retorno_em timestamptz)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- só o modelo presencial-base
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select x.id, coalesce(x.enviado_em, x.criado_em), x.enviado_em, x.canal, x.canal not in ('email', 'grupo'),
         x.tipo, f.nome, n.numero, x.campanha, x.publico_lista, x.publico_origem,
         x.copy_texto, x.copy_link, x.tamanho_lista, x.entregues, x.lidas, x.cliques,
         x.falhas, x.custo_centavos, x.origem, x.retorno_em
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
    left join mkt_mensageria.numeros n on n.id = x.numero_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
     and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   order by coalesce(x.enviado_em, x.criado_em), x.id;
end
$function$;

revoke all on function public.dados_presencial_disparos_canais(text, date, date) from public, anon, service_role;
revoke all on function public.dados_presencial_disparos_lista(text, date, date) from public, anon, service_role;
grant execute on function public.dados_presencial_disparos_canais(text, date, date) to authenticated;
grant execute on function public.dados_presencial_disparos_lista(text, date, date) to authenticated;

do $c$
declare f text;
begin
  foreach f in array array['public.dados_presencial_disparos_canais(text,date,date)', 'public.dados_presencial_disparos_lista(text,date,date)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('service_role', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute') then
      raise exception '20261017020500: permissões erradas em %', f;
    end if;
  end loop;
end
$c$;

-- ===== 20261017020600 =====
-- 20261017020600: liga ao projeto 68 (CNFMIAMI26, Clínica Internacional de Holding Familiar) os 7 disparos da Clínica que a
--   integração gravou sem projeto (campanha sem [SIGLA] no nome => projeto nulo, origem 'api').
-- STATUS: ver 20261017020600.explain.md.
-- O QUE FAZ: update de projeto_id (null -> 68) em 7 ids, conferidos um a um (canal, campanha, origem, sistema, projeto nulo, não
--   arquivado). 5 e-mails do ActiveCampaign ("[Clínica] Carrinho aberto", "(2)", "(3)", "[Clínica] Último dia", "[Clínica] Faltam 3 horas")
--   e 2 WhatsApp API do Unichat (clinica_carrinhoaberto, clinica_miami_inscricao_pendente_util; os mesmos 2 da aba API da planilha da
--   Clínica, com o mesmo tamanho de base 1478 e 1467).
-- O QUE NÃO FAZ: não apaga (o banco bloqueia), não mexe em custo, copy, origem nem nos outros 2 disparos com "clinica" no nome
--   ("[CLINICA-INT] Compra Aprovada - v2" 50162 e clinica_compraaprovada_v2 50132: pós-compra, fora do pedido; decisão do Victor).
--   Não toca nos grupos "ALUNOS ATIVOS" do SendFlow (nome reaproveitado por outros eventos; entram pela planilha).
-- AVISO (ver explain): quando a planilha da Clínica for ativada com a aba API, desligar o vínculo dos ids 39925 e 40560
--   (projeto_id = null), senão a mesma mensagem conta duas vezes (a planilha insere linha nova de origem 'planilha').
-- AS 5 PERGUNTAS: escala 7 linhas; índice = a PK (id); frequência = uma vez; repetição = idempotente (where projeto_id is null);
--   reversão = 20261017020600_reversao.sql.
-- Sem grant, RLS ou auth.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select count(*) from mkt_mensageria.disparos
       where origem = 'api' and projeto_id is null and arquivado_em is null and (id, canal, campanha, origem_sistema) in (
         (39935, 'email', '[Clínica] Carrinho aberto', 'activecampaign'),
         (41099, 'email', '[Clínica] Carrinho aberto (2)', 'activecampaign'),
         (42695, 'email', '[Clínica] Carrinho aberto (3)', 'activecampaign'),
         (44024, 'email', '[Clínica] Último dia', 'activecampaign'),
         (44512, 'email', '[Clínica] Faltam 3 horas', 'activecampaign'),
         (39925, 'whatsapp_api', 'clinica_carrinhoaberto', 'unichat'),
         (40560, 'whatsapp_api', 'clinica_miami_inscricao_pendente_util', 'unichat'))) <> 7 then
    raise exception '20261017020600: os 7 disparos da Clínica não estão no estado esperado (sem projeto, ativos, mesmo nome)';
  end if;
  if not exists (select 1 from mkt.projetos where id = 68 and sigla = 'CNFMIAMI26') then
    raise exception '20261017020600: projeto 68 (CNFMIAMI26) não existe';
  end if;
end
$g$;

update mkt_mensageria.disparos set projeto_id = 68
 where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id is null and origem = 'api';

do $c$
begin
  if (select count(*) from mkt_mensageria.disparos where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id = 68) <> 7 then
    raise exception '20261017020600: nem todos os 7 foram ligados ao projeto 68';
  end if;
end
$c$;

-- ===== PROVAS =====
insert into pg_temp._z_out (passo, linha) select '10 colunas iguais às do ATM (canais)', jsonb_build_object(
  'atm', (select pg_get_function_result('public.dados_atm_disparos_canais(text,date,date)'::regprocedure)),
  'iguais', pg_get_function_result('public.dados_atm_disparos_canais(text,date,date)'::regprocedure) = pg_get_function_result('public.dados_presencial_disparos_canais(text,date,date)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '11 colunas iguais às do ATM (lista)', jsonb_build_object(
  'iguais', pg_get_function_result('public.dados_atm_disparos_lista(text,date,date)'::regprocedure) = pg_get_function_result('public.dados_presencial_disparos_lista(text,date,date)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '12 os 7 ligados', (select count(*) from mkt_mensageria.disparos where id in (39935,41099,42695,44024,44512,39925,40560) and projeto_id = 68)::text;
insert into pg_temp._z_out (passo, linha) select '13 historico da ligação (7 linhas alterar)', (select count(*) from mkt_mensageria.historico
  where tabela = 'disparos' and acao = 'alterar' and registro_id in ('39935','41099','42695','44024','44512','39925','40560') and em >= now())::text;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '20 canais da Clínica (equipe) ' || x.canal, to_jsonb(x)::text from public.dados_presencial_disparos_canais('clinica-miami-2026-12') x;
insert into pg_temp._z_out (passo, linha) select '21 lista da Clínica (equipe) ' || lpad(row_number() over (order by data_hora, disparo_id)::text, 2, '0'),
  jsonb_build_object('id', disparo_id, 'canal', canal, 'pago', canal_pago, 'ferramenta', ferramenta, 'campanha', campanha, 'tipo', tipo, 'enviados', tamanho_lista,
                     'entregues', entregues, 'lidas', lidas, 'falhas', falhas, 'custo', custo_centavos, 'origem', origem)::text
  from public.dados_presencial_disparos_lista('clinica-miami-2026-12') x;
insert into pg_temp._z_out (passo, linha) select '22 período 10/10 a 11/10: lista', (select count(*) from public.dados_presencial_disparos_lista('clinica-miami-2026-12', date '2026-10-10', date '2026-10-11'))::text;
insert into pg_temp._z_out (passo, linha) select '23 período 10/10 a 11/10: canais', (select jsonb_object_agg(canal, disparos) from public.dados_presencial_disparos_canais('clinica-miami-2026-12', date '2026-10-10', date '2026-10-11'))::text;
do $t$ begin perform * from public.dados_presencial_disparos_canais('clinica-miami-2026-12', date '2026-10-12', date '2026-10-10');
  insert into pg_temp._z_out (passo, linha) values ('24 período invertido', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('24 período invertido', sqlstate); end $t$;
do $t$ begin perform * from public.dados_presencial_disparos_canais('nao-existe');
  insert into pg_temp._z_out (passo, linha) values ('25 chave inexistente', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('25 chave inexistente', sqlstate); end $t$;
do $t$ begin perform * from public.dados_presencial_disparos_lista('atm-elaine-1-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('26 chave de outro modelo (ATM) na lista presencial', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('26 chave de outro modelo (ATM) na lista presencial', sqlstate); end $t$;
do $t$ begin perform * from public.dados_atm_disparos_lista('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('27 chave da Clínica na lista do ATM (segue recusando)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('27 chave da Clínica na lista do ATM (segue recusando)', sqlstate); end $t$;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select * from public.dados_presencial_disparos_canais(''clinica-miami-2026-12'')' loop
    insert into pg_temp._z_out (passo, linha) values ('30 explain canais (equipe)', l);
  end loop;
  for l in execute 'explain (analyze, buffers) select * from public.dados_presencial_disparos_lista(''clinica-miami-2026-12'')' loop
    insert into pg_temp._z_out (passo, linha) values ('31 explain lista (equipe)', l);
  end loop;
end $x$;
reset role;
-- o que a função faz por dentro, como postgres (o índice do projeto)
do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select x.id from mkt_mensageria.disparos x where x.projeto_id = 68 and x.arquivado_em is null order by coalesce(x.enviado_em, x.criado_em), x.id' loop
    insert into pg_temp._z_out (passo, linha) values ('32 explain da leitura por projeto', l);
  end loop;
end $x$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform * from public.dados_presencial_disparos_canais('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('40 authenticated fora da equipe (canais)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('40 authenticated fora da equipe (canais)', sqlstate); end $t$;
do $t$ begin perform * from public.dados_presencial_disparos_lista('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('41 authenticated fora da equipe (lista)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('41 authenticated fora da equipe (lista)', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin perform * from public.dados_presencial_disparos_canais('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('42 anon (canais)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('42 anon (canais)', sqlstate); end $t$;
do $t$ begin perform * from public.dados_presencial_disparos_lista('clinica-miami-2026-12');
  insert into pg_temp._z_out (passo, linha) values ('43 anon (lista)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('43 anon (lista)', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '50 funções existentes intactas (md5 igual)', coalesce(string_agg(a.f, ',') filter (where a.m is distinct from md5(pg_get_functiondef(a.f::regprocedure))), 'todas iguais') from pg_temp._z_md5 a;
insert into pg_temp._z_out (passo, linha) select '51 acl', jsonb_build_object(
  'anon', has_function_privilege('anon', 'public.dados_presencial_disparos_canais(text,date,date)', 'execute'),
  'service_role', has_function_privilege('service_role', 'public.dados_presencial_disparos_lista(text,date,date)', 'execute'),
  'authenticated', has_function_privilege('authenticated', 'public.dados_presencial_disparos_lista(text,date,date)', 'execute'))::text;

-- ===== REVERSÃO (dentro do rollback: prova que fecha limpa) =====
set local lock_timeout = '5s';
set local statement_timeout = '30s';

update mkt_mensageria.disparos set projeto_id = null
 where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id = 68 and origem = 'api';

do $c$
begin
  if exists (select 1 from mkt_mensageria.disparos where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id is not null) then
    raise exception 'reversão de 20261017020600 incompleta';
  end if;
end
$c$;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

drop function if exists public.dados_presencial_disparos_canais(text, date, date);
drop function if exists public.dados_presencial_disparos_lista(text, date, date);

do $c$
begin
  if to_regprocedure('public.dados_presencial_disparos_canais(text,date,date)') is not null
     or to_regprocedure('public.dados_presencial_disparos_lista(text,date,date)') is not null then
    raise exception 'reversão de 20261017020500 incompleta';
  end if;
end
$c$;
insert into pg_temp._z_out (passo, linha) select '60 depois da reversão', jsonb_build_object(
  'funcoes_novas', to_regprocedure('public.dados_presencial_disparos_canais(text,date,date)') is not null or to_regprocedure('public.dados_presencial_disparos_lista(text,date,date)') is not null,
  'disparos_no_68', (select count(*) from mkt_mensageria.disparos where projeto_id = 68))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
