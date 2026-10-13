-- Ensaio de 20261013190752 (lista de vendas da Sessão de Viabilidade do ATM). Transação DESFEITA (rollback no fim).
-- Dado falso: um dashboard sintético 'zz-ensaio-sv-vendas' (cópia do cadastro do ATM com outra oferta do escritório, sem
-- dashboard próprio, mais uma oferta extra) e uma marcação de teste sintética para um comprador escolhido dentro do SQL.
-- Nenhum e-mail, nome, telefone ou id sai na saída: só contagens, sqlstate e plano.
-- Prova: (1) a função não existe antes; (2) migration roda com a pós-condição; (3) linhas = dados.atm_vendas_todas,
-- nome/telefone/status/oferta preenchidos e iguais à fonte; (4) teste marcado some com false e volta com true, e a
-- contagem com false = vendas de dados_atm_resumo; (5) ATM real: contagem = resumo; (6) sem equipe, sem contato.ver,
-- teste sem ser master, anon e service_role: 42501; outro modelo: P0002; (7) plano e tempo; (8) reversão apaga.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '240s';
create temp table _z_out (em serial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon, service_role;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon, service_role;
create temp table _z_ids (papel text primary key, id uuid, txt text) on commit drop;
grant select on pg_temp._z_ids to authenticated, anon, service_role;
create temp table _z_v (rodada text, transacao text, aprovado_em timestamptz, pedido_em timestamptz, dia_aprovado date,
                        nome text, email text, telefone text, valor_bruto numeric, valor_liquido numeric, moeda text,
                        status text, oferta_codigo text, teste boolean) on commit drop;
grant all on pg_temp._z_v to authenticated;

insert into pg_temp._z_out (passo, linha) values ('00 txid', txid_current()::text);
insert into pg_temp._z_out (passo, linha)
  select '01 antes: funcao existe', (to_regprocedure('public.dados_atm_sv_vendas(text,boolean)') is not null)::text;

-- ===== migration (corpo de 20261013190752_dados_atm_sv_vendas.sql, sem o notify) =====
-- 20261013190752: lista de vendas (histórico) da seção "Sessão de Viabilidade" do dashboard ATM
--
-- STATUS: APLICADA em 13/10/2026 (veja a migration). Este arquivo é só o ensaio, sempre desfeito (ROLLBACK).
-- Ensaio: 20261013190752_ensaio.sql. Reversão: 20261013190752_reversao.sql. Situação e prova: 20261013190752.explain.md.
-- Depende de 20261008191000 (marcação de teste) e 20261007180503 (schema acesso), já aplicadas.
--
-- POR QUE (card 17tya50ga3c, Seminário ATM, chave atm-elaine-1-2026-10)
--   A seção "Sessão de Viabilidade" precisa da LISTA das vendas, com nome e telefone, lida do banco. Hoje só existem
--   dados.atm_vendas_todas / dados.atm_vendas (internas, sem nome e telefone) e as contagens de public.dados_atm_resumo.
--   public.dados_presencial_vendas traz nome e telefone, mas é do modelo presencial-base, não corta vendas_desde, não
--   filtra pago/1ª cobrança e não trata teste. Não há RPC pública com a lista do ATM.
--
-- O QUE FAZ
--   public.dados_atm_sv_vendas(p_chave text, p_incluir_teste boolean default false), só leitura, nova (nenhuma função
--   existente muda). As linhas são EXATAMENTE as de dados.atm_vendas_todas (a regra de venda do dashboard fica num lugar
--   só: pagas, 1ª cobrança, desde vendas_desde, oferta do cadastro + ofertas_extra); nome, telefone e status vêm de
--   dados.transacoes pela transação; oferta_codigo é a da transação no espelho fin.hotmart_transacoes (quando o
--   dashboard não tem ofertas_extra, a única possível é a do cadastro). Com p_incluir_teste = false (padrão) as vendas
--   de comprador marcado como teste saem, igual às contagens de dados_atm_resumo.
--   Acesso, nesta ordem:
--     1. dados.atm_cadastro: equipe (@advmais ativo) e dashboard ativo do modelo seminario-atm (42501 / P0002), igual a
--        public.dados_atm_leads;
--     2. capacidade contato.ver (acesso.tem: master sempre; os outros por acesso_capacidade_definir), igual a
--        public.dados_black_lista; sem ela, 42501;
--     3. p_incluir_teste = true só para master (acesso.eh_master); os outros, 42501.
--   Grants: revoke de public, anon e service_role; execute só para authenticated; pós-condição no fim do arquivo.
--
-- AS 5 PERGUNTAS
--   escala: vendas de uma oferta por edição (ATM 1: 0 vendas pagas desde vendas_desde em 13/10; 16 transações na oferta).
--   índice: dados.transacoes lê fin.hotmart_transacoes por conta/oferta (hotmart_transacoes_oferta_idx); a oferta da
--           transação sai pela PK (hotmart_transacoes_pkey). Nada novo. O espelho é lido na forma exigida pela trava de
--           conta (fin.trava_conta_hotmart): (select * from fin.hotmart_transacoes where conta = v_conta).
--   frequência: uma chamada por abertura/atualização da seção (mesma cadência das outras RPCs do ATM).
--   repetição: dados.transacoes roda 2 vezes por chamada (uma dentro de atm_vendas_todas, uma para nome/telefone);
--              é o preço de não copiar a regra de venda. Medido no ensaio (ver explain.md).
--   reversão: 20261013190752_reversao.sql (drop da função; nada mais foi criado).
--
-- IDEMPOTENTE: create or replace; revoke/grant repetíveis.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['dados.atm_cadastro(text)', 'dados.atm_vendas_todas(text)', 'dados.transacoes(text,text)',
                           'acesso.tem(text)', 'acesso.eh_master()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regclass('fin.hotmart_transacoes') is null then
    raise exception 'premissa: falta fin.hotmart_transacoes';
  end if;
end
$g$;

-- 1. A lista
create or replace function public.dados_atm_sv_vendas(p_chave text, p_incluir_teste boolean default false)
returns table(transacao text, aprovado_em timestamp with time zone, pedido_em timestamp with time zone, dia_aprovado date,
              nome text, email text, telefone text, valor_bruto numeric, valor_liquido numeric, moeda text, status text,
              oferta_codigo text, teste boolean)
language plpgsql stable security definer set search_path = '' as $$
-- 20261013190752: vendas do ATM (regra de dados.atm_vendas_todas) com nome, telefone, status e oferta, para a seção
-- "Sessão de Viabilidade". Sem acesso ao dashboard ou sem contato.ver: 42501. Teste só para master.
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_teste boolean := coalesce(p_incluir_teste, false);
  v_conta text := d.conta_hotmart;   -- espelho lido na forma da trava de conta (fin.trava_conta_hotmart)
begin
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if v_teste and not coalesce(acesso.eh_master(), false) then
    raise exception 'só master vê as vendas marcadas como teste' using errcode = '42501';
  end if;
  return query
  select v.transacao, v.aprovado_em, v.pedido_em, v.dia_aprovado,
         t.nome, v.email, t.telefone,
         v.valor_bruto, v.valor_liquido, v.moeda, t.status,
         coalesce(h.oferta_codigo,
                  case when coalesce(cardinality(d.ofertas_extra), 0) = 0 then d.oferta_codigo end),
         v.teste
    from dados.atm_vendas_todas(d.chave) v
    left join dados.transacoes(d.conta_hotmart, d.oferta_codigo) t on t.transacao = v.transacao
    left join (select * from fin.hotmart_transacoes where conta = v_conta) h on h.transacao = v.transacao
   where v_teste or not v.teste
   order by v.aprovado_em desc nulls last, v.transacao;
end
$$;
comment on function public.dados_atm_sv_vendas(text, boolean) is
  'Lista de vendas do ATM (regra de dados.atm_vendas_todas) com nome, telefone, status e oferta. Acesso ao dashboard + contato.ver; p_incluir_teste só master. 20261013190752.';

revoke all on function public.dados_atm_sv_vendas(text, boolean) from public, anon, service_role;
grant execute on function public.dados_atm_sv_vendas(text, boolean) to authenticated;

-- pós-condição: authenticated executa; anon, service_role e PUBLIC não
do $p$
declare f constant text := 'public.dados_atm_sv_vendas(text,boolean)';
begin
  if not has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('anon', f, 'execute')
     or has_function_privilege('service_role', f, 'execute')
     or exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
                 where p.oid = f::regprocedure and a.grantee = 0) then
    raise exception 'pós-condição: grant errado em %', f;
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) then
    raise exception 'pós-condição: % não é security definer', f;
  end if;
end
$p$;

-- ===== fim da migration =====
insert into pg_temp._z_out (passo, linha)
  select '02 depois: funcao existe / secdef / acl', (to_regprocedure('public.dados_atm_sv_vendas(text,boolean)') is not null)::text
         || ' / ' || p.prosecdef::text || ' / ' || p.proacl::text
    from pg_proc p where p.oid = 'public.dados_atm_sv_vendas(text,boolean)'::regprocedure;

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

-- dado falso: dashboard sintético com 2 ofertas do escritório que não são de nenhum dashboard e têm venda paga de 1ª cobrança
with o as (
  select h.oferta_codigo, count(*) as n from fin.hotmart_transacoes h
   where h.conta = 'escritorio' and h.status in ('APPROVED', 'COMPLETE') and coalesce(h.recorrencia, 1) = 1
     and h.oferta_codigo ~ '^[a-z0-9]{4,20}$'
     and not exists (select 1 from dados.dashboards d where d.oferta_codigo = h.oferta_codigo or h.oferta_codigo = any (d.ofertas_extra))
   group by 1 having count(*) between 3 and 200
   order by 2 desc, 1 limit 2
)
insert into pg_temp._z_ids (papel, txt) select 'oferta_' || row_number() over (order by n desc, oferta_codigo), oferta_codigo from o;
insert into dados.dashboards
  select (jsonb_populate_record(null::dados.dashboards,
            to_jsonb(d) || jsonb_build_object('chave', 'zz-ensaio-sv-vendas',
                                              'oferta_codigo', (select txt from pg_temp._z_ids where papel = 'oferta_1'),
                                              'ofertas_extra', jsonb_build_array((select txt from pg_temp._z_ids where papel = 'oferta_2')),
                                              'vendas_desde', null))).*
    from dados.dashboards d where d.chave = 'atm-elaine-1-2026-10';
insert into pg_temp._z_out (passo, linha)
  select '04 dashboard sintetico: vendas na regra (atm_vendas_todas) / teste',
         count(*)::text || ' / ' || count(*) filter (where v.teste)::text
    from dados.atm_vendas_todas('zz-ensaio-sv-vendas') v;

-- (3) como master
select set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_v select 'r1_false', x.* from public.dados_atm_sv_vendas('zz-ensaio-sv-vendas') x;
insert into pg_temp._z_v select 'r1_true', x.* from public.dados_atm_sv_vendas('zz-ensaio-sv-vendas', true) x;
reset role;
insert into pg_temp._z_out (passo, linha)
  select '05 sem marcacao: false / true / mesmas transacoes da regra / nome nulo / telefone nulo / status fora de pago / oferta difere do espelho / oferta fora do cadastro',
         (select count(*) from pg_temp._z_v where rodada = 'r1_false')::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r1_true')::text
         || ' / ' || (not exists ((select transacao from pg_temp._z_v where rodada = 'r1_true')
                                  except all (select transacao from dados.atm_vendas_todas('zz-ensaio-sv-vendas')))
                      and not exists ((select transacao from dados.atm_vendas_todas('zz-ensaio-sv-vendas'))
                                  except all (select transacao from pg_temp._z_v where rodada = 'r1_true')))::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r1_true' and nome is null)::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r1_true' and telefone is null)::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r1_true' and status not in ('APPROVED', 'COMPLETE'))::text
         || ' / ' || (select count(*) from pg_temp._z_v v left join fin.hotmart_transacoes h on h.transacao = v.transacao
                       where v.rodada = 'r1_true' and v.oferta_codigo is distinct from h.oferta_codigo)::text
         || ' / ' || (select count(*) from pg_temp._z_v v where v.rodada = 'r1_true'
                         and v.oferta_codigo not in (select txt from pg_temp._z_ids where papel in ('oferta_1', 'oferta_2')))::text;
insert into pg_temp._z_out (passo, linha)
  select '05b ofertas presentes (oferta_1 / oferta_2)',
         (select count(*) from pg_temp._z_v v where v.rodada = 'r1_true' and v.oferta_codigo = (select txt from pg_temp._z_ids where papel = 'oferta_1'))::text
         || ' / ' || (select count(*) from pg_temp._z_v v where v.rodada = 'r1_true' and v.oferta_codigo = (select txt from pg_temp._z_ids where papel = 'oferta_2'))::text;

-- (4) marca um comprador como teste (marcação sintética)
insert into pg_temp._z_ids (papel, txt)
  select 'email_teste', v.email from pg_temp._z_v v where v.rodada = 'r1_true' and v.email like '%@%' order by v.transacao limit 1;
insert into dados.marcacoes_teste (chave, tipo, valor, motivo)
  select 'zz-ensaio-sv-vendas', 'email', txt, 'teste' from pg_temp._z_ids where papel = 'email_teste';
select set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into pg_temp._z_v select 'r2_false', x.* from public.dados_atm_sv_vendas('zz-ensaio-sv-vendas', false) x;
insert into pg_temp._z_v select 'r2_true', x.* from public.dados_atm_sv_vendas('zz-ensaio-sv-vendas', true) x;
create temp table _z_res on commit drop as
  select 'largo'::text as janela, r.vendas, r.vendas_teste
    from public.dados_atm_resumo('zz-ensaio-sv-vendas', date '2000-01-01', date '2100-12-31') r;
insert into _z_res select 'atm_padrao', r.vendas, r.vendas_teste from public.dados_atm_resumo('atm-elaine-1-2026-10') r;
insert into _z_res select 'atm_largo', r.vendas, r.vendas_teste
  from public.dados_atm_resumo('atm-elaine-1-2026-10', date '2000-01-01', date '2100-12-31') r;
insert into pg_temp._z_v select 'atm_false', x.* from public.dados_atm_sv_vendas('atm-elaine-1-2026-10') x;
reset role;
insert into pg_temp._z_out (passo, linha)
  select '06 marcado: vendas do e-mail (k) / false / true / linhas teste=true no true / e-mail marcado no false / resumo largo vendas / resumo largo vendas_teste',
         (select count(*) from pg_temp._z_v v where v.rodada = 'r1_true' and v.email = (select txt from pg_temp._z_ids where papel = 'email_teste'))::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r2_false')::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r2_true')::text
         || ' / ' || (select count(*) from pg_temp._z_v where rodada = 'r2_true' and teste)::text
         || ' / ' || (select count(*) from pg_temp._z_v v where v.rodada = 'r2_false' and v.email = (select txt from pg_temp._z_ids where papel = 'email_teste'))::text
         || ' / ' || (select vendas from _z_res where janela = 'largo')::text
         || ' / ' || (select vendas_teste from _z_res where janela = 'largo')::text;
insert into pg_temp._z_out (passo, linha)
  select '07 ATM real: lista false / no periodo do evento / resumo padrao vendas / resumo largo vendas',
         (select count(*) from pg_temp._z_v where rodada = 'atm_false')::text
         || ' / ' || (select count(*) from pg_temp._z_v v, dados.dashboards d
                       where v.rodada = 'atm_false' and d.chave = 'atm-elaine-1-2026-10'
                         and v.aprovado_em >= d.periodo_inicio::timestamp at time zone 'America/Sao_Paulo'
                         and v.aprovado_em < (d.periodo_fim + 1)::timestamp at time zone 'America/Sao_Paulo')::text
         || ' / ' || coalesce((select vendas from _z_res where janela = 'atm_padrao')::text, 'nulo')
         || ' / ' || coalesce((select vendas from _z_res where janela = 'atm_largo')::text, 'nulo');

-- (6) permissões
do $perm$
declare
  r record;
  n int;
  v_estado text;
  v_msg text;
begin
  for r in
    select * from (values
      (1, 'fora_equipe', 'authenticated', 'zz-ensaio-sv-vendas', false),
      (2, 'sem_contato', 'authenticated', 'zz-ensaio-sv-vendas', false),
      (3, 'com_contato', 'authenticated', 'zz-ensaio-sv-vendas', false),
      (4, 'com_contato', 'authenticated', 'zz-ensaio-sv-vendas', true),
      (5, 'master', 'authenticated', 'zz-ensaio-sv-vendas', true),
      (6, 'master', 'authenticated', 'outro_modelo', false),
      (7, null, 'anon', 'zz-ensaio-sv-vendas', false),
      (8, null, 'service_role', 'zz-ensaio-sv-vendas', false)
    ) t(ordem, papel, papel_pg, chave, incluir_teste)
    order by ordem
  loop
    if r.papel is not null and not exists (select 1 from pg_temp._z_ids where papel = r.papel and id is not null) then
      insert into pg_temp._z_out (passo, linha) values ('08 perm ' || r.ordem || ' ' || r.papel, 'papel não achado, não testado');
      continue;
    end if;
    perform set_config('request.jwt.claims',
      case when r.papel is null then jsonb_build_object('role', r.papel_pg)::text
           else jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = r.papel), 'role', r.papel_pg)::text end, true);
    execute format('set local role %I', r.papel_pg);
    begin
      execute 'select count(*) from public.dados_atm_sv_vendas($1, $2)'
        into n
        using case when r.chave = 'outro_modelo' then (select txt from pg_temp._z_ids where papel = 'outro_modelo') else r.chave end,
              r.incluir_teste;
      v_estado := 'ok'; v_msg := n || ' linhas';
    exception when others then
      v_estado := sqlstate; v_msg := sqlerrm;
    end;
    reset role;
    insert into pg_temp._z_out (passo, linha)
      values ('08 perm ' || r.ordem || ' ' || coalesce(r.papel, '-') || ' como ' || r.papel_pg || ' teste=' || r.incluir_teste,
              v_estado || ' (' || v_msg || ')');
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
end
$perm$;

-- (7) plano e tempo
do $ex$
declare r record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from pg_temp._z_ids where papel = 'master'), 'role', 'authenticated')::text, true);
  set local role authenticated;
  for r in execute 'explain (analyze, buffers) select * from public.dados_atm_sv_vendas(''zz-ensaio-sv-vendas'', true)' loop
    insert into pg_temp._z_out (passo, linha) values ('09 explain rpc sintetico', r."QUERY PLAN");
  end loop;
  for r in execute 'explain (analyze, buffers) select * from public.dados_atm_sv_vendas(''atm-elaine-1-2026-10'')' loop
    insert into pg_temp._z_out (passo, linha) values ('09 explain rpc atm', r."QUERY PLAN");
  end loop;
  reset role;
  for r in execute $q$explain (analyze, buffers)
    select v.transacao, t.nome, t.telefone, t.status, h.oferta_codigo, v.teste
      from dados.dashboards d
      cross join lateral dados.atm_vendas_todas(d.chave) v
      left join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t on t.transacao = v.transacao
      left join lateral (select * from fin.hotmart_transacoes x where x.conta = d.conta_hotmart) h on h.transacao = v.transacao
     where d.chave = 'zz-ensaio-sv-vendas'$q$ loop
    insert into pg_temp._z_out (passo, linha) values ('09 explain corpo sintetico', r."QUERY PLAN");
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
end
$ex$;

-- (8) reversão (corpo de 20261013190752_reversao.sql, sem o notify)
-- Reversão de 20261013190752 (lista de vendas da Sessão de Viabilidade do ATM).
-- A migration só criou public.dados_atm_sv_vendas(text, boolean); nenhuma função, view ou tabela existente mudou.
-- Depois de reverter, a seção "Sessão de Viabilidade" do front deixa de ter a lista (a chamada dá 404 no PostgREST).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_atm_sv_vendas(text, boolean);

do $p$
begin
  if to_regprocedure('public.dados_atm_sv_vendas(text,boolean)') is not null then
    raise exception 'reversão: public.dados_atm_sv_vendas ainda existe';
  end if;
end
$p$;

insert into pg_temp._z_out (passo, linha)
  select '10 revertido: funcao existe', (to_regprocedure('public.dados_atm_sv_vendas(text,boolean)') is not null)::text;

select set_config('request.jwt.claims', '{}', true);
select passo, linha from pg_temp._z_out order by em;
rollback;
