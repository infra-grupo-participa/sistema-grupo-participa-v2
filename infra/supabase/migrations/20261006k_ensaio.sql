-- 20261006k: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da 20261006j
--   (e, por ela, da 20261006g e da 20261006i). Todo resultado vai para a tabela temporária _z_out; o penúltimo comando
--   mostra tudo. Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia,
--   e rode o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006k_mkt_trafego_contas_meta.sql, das
-- guardas até antes da REVERSÃO). Depois dele, os testes conferem as 16 contas (nomes e ids reais das contas de anúncio,
-- que não são dado pessoal), a idempotência (rodar o insert de novo), a ordem da lista, a marcação pela tela e as recusas
-- 42501. Dado fictício: a conta act_000771 "Conta Ensaio B". Tudo some no rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO".

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'mkt_trafego' and table_name = 'contas'
              and column_name in ('unidade', 'principal')) then
    raise exception '20261006k: já aplicada (mkt_trafego.contas já tem unidade/principal)';
  end if;
  if to_regclass('mkt.unidades') is null or to_regclass('mkt_trafego.contas') is null
     or to_regprocedure('public.trafego_contas_listar()') is null then
    raise exception '20261006k: falta a 20261006j (e a 20261006g/r): aplicar antes';
  end if;
  if not exists (select 1 from mkt.unidades where codigo = 'csm') or not exists (select 1 from mkt.unidades where codigo = 'escritorio') then
    raise exception '20261006k: mkt.unidades sem csm/escritorio';
  end if;
  if to_regprocedure('public.trafego_conta_marcar(bigint,text,boolean)') is not null then
    raise exception '20261006k: public.trafego_conta_marcar já existe';
  end if;
end
$guarda$;

-- ─── 1. Colunas ──────────────────────────────────────────────────────────────────────────────────────────────────────
alter table mkt_trafego.contas
  add column unidade text references mkt.unidades(codigo) on delete restrict,
  add column principal boolean not null default false;
comment on column mkt_trafego.contas.unidade is
  'Unidade da conta (mkt.unidades: csm, escritorio, aurum, diamantes). Nulo = não classificada. Regra do Victor (06/10/2026) '
  'para as internas: Escritório = "Seminário" ou "Aurum" no nome; CSM = Marcio, Holding Total, CNF, Imersões, THB, Treinamento. 20261006k.';
comment on column mkt_trafego.contas.principal is 'Conta principal: aparece primeiro na seleção (todas continuam selecionáveis). 20261006k.';

-- ─── 2. As 16 contas (nome exato da API em 06/10/2026; id sem act_) ─────────────────────────────────────────────────
insert into mkt_trafego.contas as c (plataforma, conta_externa, nome, dono, moeda, ativa, unidade, principal)
select 'meta', v.id, v.nome, 'grupo', 'BRL', v.ativa, v.unidade, v.principal
  from (values
    ('686822108510130',  '1º Dr. Marcio Carvalho de Sá ADS',       'csm',        false, true),
    ('363803868960273',  '2ºDr. Marcio Carvalho de Sá - 2',        'csm',        false, true),
    ('2345107592642621', '3ª Dr. Marcio Carvalho de Sá',           'csm',        false, true),
    ('1230564179214484', '4º Dr. Marcio Carvalho de Sá',           'csm',        false, true),
    ('1467134847777565', '1º Holding Total 2.0',                   'csm',        true, true),
    ('919875374390968',  'Holding Total 2.0 - Dist. de Conteúdo',  'csm',        false, true),
    ('1570090828117070', 'CNF Holding Familiar',                   'csm',        true, true),
    ('1008535771830636', 'Imersões - Vendas',                      'csm',        false, true),
    ('1767572701045744', 'THB - Ads',                              'csm',        true, true),
    ('2634066567011997', 'Treinamento Participa',                  'csm',        true, true),
    ('187642820066112',  '1ºAurum',                                'escritorio', false, true),
    ('1060867594526201', '2ºAurum Teste',                          'escritorio', false, true),
    ('505773954864951',  '3ºAurum Tutorial',                       'escritorio', false, true),
    ('989935947003541',  'Seminário - Dist. de Cont.',             'escritorio', false, true),
    ('1190477699799714', 'Seminários - Leads',                     'escritorio', true, true),
    ('2423459874841639', 'CA - Tutorial',                          'csm',         false, false)
  ) v(id, nome, unidade, principal, ativa)
on conflict (plataforma, conta_externa) do update
   set nome = excluded.nome, unidade = excluded.unidade, principal = excluded.principal,
       ativa = case when excluded.ativa then c.ativa else false end, atualizado_em = now();

-- ─── 3. Funções da tela ──────────────────────────────────────────────────────────────────────────────────────────────
-- A lista da 20261006g, agora com unidade e principal; principais primeiro (dentro de ativa e plataforma).
create or replace function public.trafego_contas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'plataforma', c.plataforma, 'conta_externa', c.conta_externa, 'nome', c.nome, 'dono', c.dono,
            'cliente', c.cliente, 'moeda', c.moeda, 'ativa', c.ativa, 'obs', c.obs, 'atualizado_em', c.atualizado_em,
            'unidade', c.unidade, 'principal', c.principal,
            'campanhas', (select count(*) from mkt_trafego.campanhas k where k.conta_id = c.id))
          order by c.ativa desc, c.principal desc, c.plataforma, c.nome), '[]'::jsonb)
            from mkt_trafego.contas c);
end
$$;

-- Unidade e principal de uma conta (a tela chama depois de salvar a conta). p_unidade vazio = sem unidade. A unidade
-- precisa combinar com o dono: grupo → unidade interna (CSM, Escritório); aurum → Aurum; diamante → Diamantes.
create function public.trafego_conta_marcar(p_conta bigint, p_unidade text, p_principal boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uni text := nullif(lower(btrim(coalesce(p_unidade, ''))), '');
  v_dono text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select dono into v_dono from mkt_trafego.contas where id = p_conta for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Conta não encontrada.'); end if;
  if v_uni is not null and not exists (select 1 from mkt.unidades u where u.codigo = v_uni and u.ativa
       and case v_dono when 'grupo' then u.tipo = 'interno' when 'aurum' then u.codigo = 'aurum' when 'diamante' then u.codigo = 'diamantes' else false end) then
    return jsonb_build_object('ok', false, 'msg', 'Unidade não combina com o dono da conta (Grupo: CSM ou Escritório; Aurum; Diamantes).');
  end if;
  update mkt_trafego.contas
     set unidade = v_uni, principal = coalesce(p_principal, false), atualizado_em = now(), atualizado_por = (select auth.uid())
   where id = p_conta;
  return jsonb_build_object('ok', true, 'msg', 'Unidade e principal da conta salvos.');
end
$$;

revoke all on function public.trafego_conta_marcar(bigint, text, boolean) from public, anon, authenticated, service_role;
grant execute on function public.trafego_conta_marcar(bigint, text, boolean) to authenticated;

-- ─── 4. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.prosecdef, p.proconfig, p.proacl from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('trafego_contas_listar', 'trafego_conta_marcar') loop
    if not (f.proconfig @> array['search_path=""']) or not f.prosecdef then raise exception '20261006k: % fora do padrão', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') or not has_function_privilege('authenticated', f.sig, 'execute')
       or has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006k: grant errado em %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006k: PUBLIC executa %', f.sig;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'mkt_trafego.contas', 'select') or has_table_privilege('anon', 'mkt_trafego.contas', 'select') then
    raise exception '20261006k: mkt_trafego.contas aberta';
  end if;
  if (select count(*) from mkt_trafego.contas where plataforma = 'meta' and conta_externa in (
        '686822108510130', '363803868960273', '2345107592642621', '1230564179214484', '1467134847777565', '919875374390968',
        '1570090828117070', '1008535771830636', '1767572701045744', '2634066567011997', '187642820066112', '1060867594526201',
        '505773954864951', '989935947003541', '1190477699799714', '2423459874841639')) <> 16 then
    raise exception '20261006k: esperava as 16 contas do Meta';
  end if;
  if (select count(*) filter (where unidade = 'csm') || '/' || count(*) filter (where unidade = 'escritorio') || '/'
             || count(*) filter (where unidade is null) || '/' || count(*) filter (where principal) || '/' || count(*) filter (where not ativa)
        from mkt_trafego.contas where plataforma = 'meta' and dono = 'grupo'
         and conta_externa in ('686822108510130', '363803868960273', '2345107592642621', '1230564179214484', '1467134847777565',
           '919875374390968', '1570090828117070', '1008535771830636', '1767572701045744', '2634066567011997', '187642820066112',
           '1060867594526201', '505773954864951', '989935947003541', '1190477699799714', '2423459874841639')) <> '11/5/0/5/1' then
    raise exception '20261006k: unidades/principais diferentes do esperado (11 CSM, 5 Escritório, 5 principais, 1 inativa)';
  end if;
  -- sem pg_cron (banco local) a checagem não se aplica
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname in ('trafego-meta', 'trafego-meta-hoje')) then
      raise exception '20261006k: coleta do Meta agendada (deveria continuar desligada)';
    end if;
  end if;
end
$confere$;


-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.adm(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end $$;
grant execute on function pg_temp.ok(text, boolean, text) to public;
create function pg_temp.conta(p_ext text) returns mkt_trafego.contas language sql stable as $$
  select * from mkt_trafego.contas where plataforma = 'meta' and conta_externa = p_ext $$;

-- 1. as 16 contas
select pg_temp.ok('1.contas', (select count(*) from mkt_trafego.contas where plataforma = 'meta') = 16
  and (select count(*) from mkt_trafego.contas where plataforma = 'meta' and (dono <> 'grupo' or moeda <> 'BRL' or conta_externa like 'act%')) = 0,
  '16 contas Meta, internas (grupo), BRL, id sem act_');
select pg_temp.ok('1.nomes exatos', (pg_temp.conta('363803868960273')).nome = '2ºDr. Marcio Carvalho de Sá - 2'
  and (pg_temp.conta('2345107592642621')).nome = '3ª Dr. Marcio Carvalho de Sá' and (pg_temp.conta('187642820066112')).nome = '1ºAurum'
  and (pg_temp.conta('989935947003541')).nome = 'Seminário - Dist. de Cont.', 'nomes exatos (º, ª, espaços e acentos como na API)');
select pg_temp.ok('1.unidades', (select string_agg(coalesce(unidade, '-'), ',' order by nome) from mkt_trafego.contas
    where nome ~ '(Seminário|Aurum)') = 'escritorio,escritorio,escritorio,escritorio,escritorio'
  and (select count(*) from mkt_trafego.contas where nome ~ '(Marcio|Holding Total|CNF|Imersões|THB|Treinamento)' and unidade = 'csm') = 10,
  'Escritório = Seminário/Aurum (5); CSM = Marcio, Holding Total, CNF, Imersões, THB, Treinamento (10)');
select pg_temp.ok('1.principais', (select string_agg(nome, ', ' order by nome) from mkt_trafego.contas where principal)
  = '1º Holding Total 2.0, CNF Holding Familiar, Seminários - Leads, THB - Ads, Treinamento Participa', '5 principais');
select pg_temp.ok('1.CA - Tutorial', (pg_temp.conta('2423459874841639')).unidade = 'csm' and not (pg_temp.conta('2423459874841639')).ativa,
  'CA - Tutorial: CSM e inativa');
select pg_temp.ok('1.fora da coleta', (select count(*) from mkt_trafego.meta_contas()) = 15
  and not exists (select 1 from mkt_trafego.meta_contas() m where m.conta_externa = '2423459874841639'),
  'a coleta (meta_contas) lê 15: a inativa fica fora');
do $t$
declare v boolean := true;
begin
  if to_regclass('cron.job') is not null then
    execute $q$select not exists (select 1 from cron.job where jobname like 'trafego-meta%')$q$ into v;
  end if;
  perform pg_temp.ok('1.coleta desligada', v, 'nenhuma rotina do Meta agendada' || case when to_regclass('cron.job') is null then ' (sem pg_cron neste banco)' else '' end);
end
$t$;

-- 2. idempotência: o insert de novo não duplica; a conta reativada à mão não volta a ficar ativa; a CA continua inativa
do $t$
begin
  update mkt_trafego.contas set ativa = false, obs = 'obs do ensaio' where conta_externa = '1767572701045744';
  update mkt_trafego.contas set nome = 'Nome Antigo Ensaio' where conta_externa = '1570090828117070';
  insert into mkt_trafego.contas as c (plataforma, conta_externa, nome, dono, moeda, ativa, unidade, principal)
  select 'meta', v.id, v.nome, 'grupo', 'BRL', v.ativa, v.unidade, v.principal
    from (values ('1767572701045744', 'THB - Ads', 'csm', true, true), ('1570090828117070', 'CNF Holding Familiar', 'csm', true, true),
                 ('2423459874841639', 'CA - Tutorial', 'csm', false, false)) v(id, nome, unidade, principal, ativa)
  on conflict (plataforma, conta_externa) do update
     set nome = excluded.nome, unidade = excluded.unidade, principal = excluded.principal,
         ativa = case when excluded.ativa then c.ativa else false end, atualizado_em = now();
  perform pg_temp.ok('2.idempotente', (select count(*) from mkt_trafego.contas where plataforma = 'meta') = 16
    and not (pg_temp.conta('1767572701045744')).ativa and (pg_temp.conta('1767572701045744')).obs = 'obs do ensaio'
    and (pg_temp.conta('1570090828117070')).nome = 'CNF Holding Familiar',
    'reaplicar o insert: 16 contas; nome volta ao exato; ativa e obs mexidas à mão ficam');
  update mkt_trafego.contas set ativa = true, obs = null where conta_externa = '1767572701045744';
end
$t$;

-- 3. lista da tela e marcação
do $t$
declare v jsonb; l jsonb; v_b bigint;
begin
  l := pg_temp.adm('select public.trafego_contas_listar()');
  perform pg_temp.ok('3.ordem', (select string_agg(e ->> 'nome', ' | ' order by o) from jsonb_array_elements(l) with ordinality x(e, o) where o <= 5)
      = '1º Holding Total 2.0 | CNF Holding Familiar | Seminários - Leads | THB - Ads | Treinamento Participa'
    and l -> -1 ->> 'nome' = 'CA - Tutorial' and l -> 0 ->> 'unidade' = 'csm' and (l -> 0 ->> 'principal')::boolean,
    'lista: ativas primeiro, principais no topo; a inativa por último; unidade e principal na resposta');
  v := pg_temp.adm(format('select public.trafego_conta_marcar(%s, %L, true)', (pg_temp.conta('2423459874841639')).id, 'escritorio'));
  perform pg_temp.ok('3.marcar', (v ->> 'ok')::boolean and (pg_temp.conta('2423459874841639')).unidade = 'escritorio'
    and (pg_temp.conta('2423459874841639')).principal, 'tela marca unidade e principal');
  v := pg_temp.adm(format('select public.trafego_conta_marcar(%s, %L, false)', (pg_temp.conta('2423459874841639')).id, 'aurum'));
  perform pg_temp.ok('3.recusa', not (v ->> 'ok')::boolean, 'conta do Grupo com unidade Aurum recusada (só CSM ou Escritório)');
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"act_000771","nome":"Conta Ensaio B","dono":"diamante"}')$$);
  v_b := (v ->> 'id')::bigint;
  perform pg_temp.ok('3.dono diamante', (pg_temp.adm(format('select public.trafego_conta_marcar(%s, %L, false)', v_b, 'diamantes')) ->> 'ok')::boolean
    and not (pg_temp.adm(format('select public.trafego_conta_marcar(%s, %L, false)', v_b, 'csm')) ->> 'ok')::boolean
    and (pg_temp.adm(format('select public.trafego_conta_marcar(%s, null, false)', v_b)) ->> 'ok')::boolean,
    'conta de Diamante: Diamantes aceita, CSM recusada, sem unidade aceita');
end
$t$;

-- 4. recusas
do $t$
declare u text; v_papel text; c text; v_ok int; v_errado text;
begin
  foreach u in array array['00000000-0000-4000-8000-0000000000ff:authenticated', '22222222-2222-4222-8222-222222222222:authenticated',
                           '33333333-3333-4333-8333-333333333333:authenticated', '00000000-0000-4000-8000-0000000000ff:anon'] loop
    v_papel := split_part(u, ':', 2);
    perform set_config('request.jwt.claims', '{"sub":"' || split_part(u, ':', 1) || '","role":"' || v_papel || '"}', true);
    v_ok := 0; v_errado := null;
    foreach c in array array['select public.trafego_contas_listar()', 'select public.trafego_conta_marcar(1, null, false)',
                             'select count(*) from mkt_trafego.contas'] loop
      begin
        execute format('set local role %I', v_papel);
        execute c;
        reset role;
        v_errado := concat_ws(', ', v_errado, c);
      exception when insufficient_privilege then
        reset role;
        v_ok := v_ok + 1;
      end;
    end loop;
    perform pg_temp.ok('4.' || case split_part(u, ':', 1) when '33333333-3333-4333-8333-333333333333' then 'visualizador'
                                 when '22222222-2222-4222-8222-222222222222' then 'operador' else 'sem perfil' end || ' ' || v_papel,
                       v_errado is null, v_ok || ' recusas 42501' || coalesce(' / PASSOU: ' || v_errado, ''));
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
