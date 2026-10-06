-- 20261006160404: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006160404_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006160404_pa_historico_aluno.sql). Depois do
-- corpo: alunos ZZ e sete pedidos (consome 7 números da sequência de pa_pedidos):
--   p1 troca no titular 1: sai "Sai Um", entra "Entra Existente"          (pa_criar + pa_decidir, Victor)
--   p2 troca no titular 2: sai "Sai Dois", entra pessoa nova               (gravado direto, CPF 484.621.880-58 que
--      FALHA no dígito verificador, como no ensaio 20261006144913; decidido pela pa_decidir)
--   p3 titular 1: e-mail                                                   (pa_criar + pa_decidir)
--   p4 "Entra Existente": documento 111.111.111-11 → 222.222.222-22        (gravado direto já aplicado: a pa_normalizar
--      recusaria esses documentos inválidos, e o ensaio não usa documento de ninguém)
--   p5 titular 1: "outro" aplicado; p6 titular 1: e-mail recusado; p7 titular 1: e-mail pendente  → nenhum entra no histórico
-- Perfis usados: Victor (equipe, vê documento), um operador ativo da equipe sem permissão de ver documento
-- (6f0c31a2-…), e um uuid sem perfil (fora da equipe).
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select to_regprocedure('public.pa_historico_aluno(uuid)') is null sem_funcao,
--        (select count(*) from pg_indexes where indexname in ('pa_pedidos_aluno_idx','pa_pedidos_socio_sai_idx','pa_pedidos_socio_entra_idx')) indices,
--        (select count(*) from public.thb_alunos where fonte in ('ensaio_20261006160404', 'pedido_alteracao')) alunos_zz,
--        (select max(id) from public.pa_pedidos) max_pedido;

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || coalesce(p_det, ''));
$$;
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
-- Como anon (sem JWT): o caminho do n8n pelo PostgREST.
create function pg_temp.anon(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
-- Plano medido: cada linha do explain (analyze) vira uma linha da saída.
create function pg_temp.plano(p_passo text, p_sql text) returns void language plpgsql as $$
declare l text;
begin
  for l in execute 'explain (analyze, buffers, costs off) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, 'PLANO   ' || l);
  end loop;
end $$;

-- ═══ CORPO DA MIGRATION 20261006160404_pa_historico_aluno.sql (cópia sem mudança) ═══
-- 20261006160404: Pedidos de alteração (etapa 2), histórico de pedidos no card do aluno
--
-- STATUS: APLICADA em 06/10/2026 (pentester aprovou). Ensaio: 20261006160404_ensaio.sql (begin … rollback). Notas: 20261006160404.explain.md.
-- Independente das 20261006160401/02/03.
--
-- DECISÃO DO VICTOR (06/10/2026, noite): o histórico no card é lido de pa_pedidos aplicados (sem tabela nova, sem
-- backfill). Uma troca de sócio gera 3 textos, um para cada pessoa:
--   titular: "<titular> trocou o sócio <X> pelo sócio <Y> (pedido nº N, aprovado por <Fulano> em dd/mm/aaaa)"
--   sai:     "<X> saiu como sócio de <titular> (...)"
--   entra:   "<Y> entrou como sócio de <titular> (...)" + " (cadastro novo)" se a pessoa foi criada pelo pedido
--   alterar dado: "<Rótulo> alterado de <antes> para <depois> (...)", com pa_exibir (documento mascarado por
--   pa_pode_ver_doc(), turma pelo código, endereço numa linha).
--
-- CONTRATO COM A TELA (fixo):
--   pa_historico_aluno(p_aluno uuid) returns table(em timestamptz, pedido_id bigint, papel text, texto text)
--   papel ∈ 'titular' | 'sai' | 'entra' | 'aluno'; SECURITY DEFINER; só para gp_eh_equipe() (fora disso, 0 linhas);
--   ordem em desc.
--
-- ESCOLHAS DESTA MIGRATION (não estavam no plano; ficam registradas)
--   • Só pedidos `aplicado` dos tipos trocar_socio e alterar_dado. "outro" fica de fora: não tem texto estruturado.
--   • em = aplicado_em (cai para decidido_em se nulo). A data do texto é decidido_em, no fuso America/Sao_Paulo.
--   • Nomes vêm da foto do pedido (aluno_nome, socio_sai_nome, socio_entra_nome): é o nome na hora da troca.
--   • Rótulos = os da tela (CAMPOS_EDITAVEIS em web/modules/alunos/domain/pedidos-alteracao.ts), com concordância
--     ("Profissão alterada", "Turma alterada", "Instrução alterada", "Observação da Central alterada"). Valor vazio
--     aparece como "(vazio)", igual à tela.
--   • Aprovador sem perfil: "(aprovador não encontrado)".
--
-- AS 5 PERGUNTAS
--   escala: pa_pedidos tem dezenas de linhas e cresce dezenas por mês; cada chamada devolve os pedidos de 1 aluno.
--   índice: 3 novos, pa_pedidos(aluno_id), (socio_sai_id), (socio_entra_id), para não varrer a tabela quando ela
--     crescer (a ficha abre a cada clique num aluno). Parciais (where coluna is not null).
--   frequência: a cada abertura da aba de histórico na ficha (a tela guarda em cache por aluno).
--   repetição: leitura pura.
--   reversão: bloco REVERSÃO no fim (drop da função e dos 3 índices).
--
-- Quem lê fora do v2: ninguém (função nova; índices não mudam resultado de ninguém).

set local lock_timeout = '5s';

-- ═══ 0. Guarda ═══
do $guarda$
begin
  if to_regprocedure('public.pa_historico_aluno(uuid)') is not null then
    raise exception '20261006160404: pa_historico_aluno já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.pa_exibir(text,jsonb,boolean)') is null or to_regprocedure('public.pa_pode_ver_doc()') is null
     or to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261006160404: pa_exibir, pa_pode_ver_doc ou gp_eh_equipe ausente';
  end if;
end
$guarda$;

-- ═══ 1. Índices (pa_pedidos é pequena: o create index trava a tabela por milissegundos) ═══
create index if not exists pa_pedidos_aluno_idx on public.pa_pedidos (aluno_id) where aluno_id is not null;
create index if not exists pa_pedidos_socio_sai_idx on public.pa_pedidos (socio_sai_id) where socio_sai_id is not null;
create index if not exists pa_pedidos_socio_entra_idx on public.pa_pedidos (socio_entra_id) where socio_entra_id is not null;

-- ═══ 2. Histórico do aluno ═══
create function public.pa_historico_aluno(p_aluno uuid)
returns table (em timestamptz, pedido_id bigint, papel text, texto text)
language sql stable security definer set search_path = '' as $$
  with ped as (
    select x.id, x.tipo, x.campo, x.valor_atual, x.valor_aplicado, x.aluno_id, x.socio_sai_id, x.socio_entra_id,
           x.aluno_nome, x.socio_sai_nome,
           coalesce(x.socio_entra_nome, x.socio_entra_novo ->> 'nome') as entra_nome,
           coalesce((x.valor_aplicado ->> 'socio_novo')::boolean, false) as socio_novo,
           coalesce(x.aplicado_em, x.decidido_em) as quando,
           ' (pedido nº ' || x.id || ', aprovado por ' || coalesce(p.nome, '(aprovador não encontrado)') || ' em '
             || coalesce(to_char(x.decidido_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'), '?') || ')' as suf
      from public.pa_pedidos x
      left join public.perfis p on p.id = x.decidido_por
     where p_aluno is not null and public.gp_eh_equipe()
       and x.status = 'aplicado' and x.tipo in ('trocar_socio', 'alterar_dado')
       and (x.aluno_id = p_aluno or x.socio_sai_id = p_aluno or x.socio_entra_id = p_aluno)
  ), doc as (select public.pa_pode_ver_doc() as ver)
  select h.em, h.pedido_id, h.papel, h.texto from (
    select q.quando as em, q.id as pedido_id, 'titular'::text as papel,
           q.aluno_nome || ' trocou o sócio ' || coalesce(q.socio_sai_nome, '?') || ' pelo sócio '
             || coalesce(q.entra_nome, '?') || q.suf as texto
      from ped q where q.tipo = 'trocar_socio' and q.aluno_id = p_aluno
    union all
    select q.quando, q.id, 'sai', coalesce(q.socio_sai_nome, '?') || ' saiu como sócio de ' || q.aluno_nome || q.suf
      from ped q where q.tipo = 'trocar_socio' and q.socio_sai_id = p_aluno
    union all
    select q.quando, q.id, 'entra', coalesce(q.entra_nome, '?') || ' entrou como sócio de ' || q.aluno_nome || q.suf
             || case when q.socio_novo then ' (cadastro novo)' else '' end
      from ped q where q.tipo = 'trocar_socio' and q.socio_entra_id = p_aluno
    union all
    select q.quando, q.id, 'aluno',
           case q.campo when 'nome' then 'Nome alterado' when 'email' then 'E-mail alterado'
                        when 'telefone' then 'Telefone alterado' when 'telefone_profissional' then 'Telefone profissional alterado'
                        when 'documento' then 'Documento (CPF ou CNPJ) alterado' when 'endereco' then 'Endereço alterado'
                        when 'profissao' then 'Profissão alterada' when 'turma_id' then 'Turma alterada'
                        when 'instrucao' then 'Instrução alterada' when 'espaco_instrucao' then 'Espaço de instrução alterado'
                        when 'obs_central' then 'Observação da Central alterada'
                        else coalesce(q.campo, 'Campo') || ' alterado' end
           || ' de ' || coalesce(public.pa_exibir(q.campo, q.valor_atual, d.ver), '(vazio)')
           || ' para ' || coalesce(public.pa_exibir(q.campo, q.valor_aplicado, d.ver), '(vazio)') || q.suf
      from ped q cross join doc d where q.tipo = 'alterar_dado' and q.aluno_id = p_aluno
  ) h
  order by h.em desc, h.pedido_id desc;
$$;

revoke all on function public.pa_historico_aluno(uuid) from public, anon;
grant execute on function public.pa_historico_aluno(uuid) to authenticated;

-- ═══ 3. Conferência ═══
do $confere$
begin
  if has_function_privilege('anon', 'public.pa_historico_aluno(uuid)', 'execute') then
    raise exception '20261006160404: pa_historico_aluno exposta para anon';
  end if;
  if (select count(*) from pg_indexes where schemaname = 'public' and tablename = 'pa_pedidos'
        and indexname in ('pa_pedidos_aluno_idx', 'pa_pedidos_socio_sai_idx', 'pa_pedidos_socio_entra_idx')) <> 3 then
    raise exception '20261006160404: índices não criados';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- A aba de histórico da ficha passa a dar erro ao chamar a função: reverter junto com a tela.
-- Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- drop function if exists public.pa_historico_aluno(uuid);
-- drop index if exists public.pa_pedidos_socio_entra_idx;
-- drop index if exists public.pa_pedidos_socio_sai_idx;
-- drop index if exists public.pa_pedidos_aluno_idx;

-- ═══ ENSAIO: testes ═══════════════════════════════════════════════════════════════════════════

create temp table _p (k text primary key, n bigint, criar jsonb, decidir jsonb) on commit drop;
create function pg_temp.n(p_k text) returns bigint language sql as $$ select n from pg_temp._p where k = p_k $$;
create temp table _dia on commit drop as select to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') d;
create function pg_temp.suf(p_k text) returns text language sql as $$
  select ' (pedido nº ' || pg_temp.n(p_k) || ', aprovado por Victor Hugo em ' || (select d from pg_temp._dia) || ')' $$;
-- Histórico como um perfil: devolve [{papel, pedido, texto}] na ordem da função.
create function pg_temp.hist(p_perfil uuid, p_aluno uuid) returns jsonb language sql as $$
  select pg_temp.chamar(p_perfil, format(
    'select coalesce(jsonb_agg(jsonb_build_object(''papel'', papel, ''pedido'', pedido_id, ''texto'', texto)), ''[]'') from public.pa_historico_aluno(%L)',
    p_aluno)) $$;

insert into public.thb_alunos (id, nome, email, documento, instrucao, espaco_instrucao, data_expiracao, mes_expiracao,
                               ano_expiracao, num_socios, fonte, data_entrada_thb, turma_id)
values ('e0000000-0000-4000-8000-0000001604d0', 'ZZ Ensaio 160404 Titular Um', 'zz.160404.t1@exemplo.invalid', null,
        'THB', 'holding_masters', '2027-03-31', 3, 2027, 1, 'ensaio_20261006160404', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604d1', 'ZZ Ensaio 160404 Sai Um', 'zz.160404.sai1@exemplo.invalid', null,
        'THB - SÓCIO', 'holding_masters', '2027-03-31', 3, 2027, null, 'ensaio_20261006160404', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604d2', 'ZZ Ensaio 160404 Entra Existente', 'zz.160404.entra@exemplo.invalid', '11111111111',
        'THB', 'holding_masters', null, null, null, null, 'ensaio_20261006160404', '2024-05-05', 55),
       ('e0000000-0000-4000-8000-0000001604e0', 'ZZ Ensaio 160404 Titular Dois', 'zz.160404.t2@exemplo.invalid', null,
        'AURUM', 'aurum', '2026-12-31', 12, 2026, 1, 'ensaio_20261006160404', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604e1', 'ZZ Ensaio 160404 Sai Dois', 'zz.160404.sai2@exemplo.invalid', null,
        'AURUM - SÓCIO', 'aurum', '2026-12-31', 12, 2026, null, 'ensaio_20261006160404', '2025-01-10', 54);
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000001604d0',
       socio_de_nome = 'ZZ Ensaio 160404 Titular Um' where id = 'e0000000-0000-4000-8000-0000001604d1';
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000001604e0',
       socio_de_nome = 'ZZ Ensaio 160404 Titular Dois' where id = 'e0000000-0000-4000-8000-0000001604e1';

insert into _p (k, criar) values ('p1', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"trocar_socio",
   "aluno_id":"e0000000-0000-4000-8000-0000001604d0","socio_sai_id":"e0000000-0000-4000-8000-0000001604d1",
   "socio_entra_id":"e0000000-0000-4000-8000-0000001604d2","motivo":"ensaio da migration 20261006160404"}''::jsonb)::jsonb'));
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, valor_atual, socio_sai_id, socio_sai_nome, socio_entra_nome,
                                 socio_entra_novo, motivo, solicitado_por)
  select 'trocar_socio', t.id, t.nome, jsonb_build_object('socio_sai_vinculado', true, 'num_socios', t.num_socios),
         s.id, s.nome, 'ZZ Ensaio 160404 Novo',
         jsonb_build_object('nome', 'ZZ Ensaio 160404 Novo', 'email', 'zz.160404.novo@exemplo.invalid',
           'telefone', public.pa_telefone_pessoa('(21) 97777-0014', true), 'documento', '48462188058', 'tipo_documento', 'CPF',
           'profissao', 'Contadora', 'endereco_mantido', false,
           'endereco', public.pa_endereco('{"pais":"Brasil","cep":"20040-020","endereco_logradouro":"Av. Ensaio",
             "endereco_numero":"1","bairro":"Centro","cidade":"Rio de Janeiro","estado":"RJ"}'::jsonb, true)),
         'ensaio da migration 20261006160404', '81d2eaee-cce1-4058-8714-439b0fc6f970'
    from public.thb_alunos t, public.thb_alunos s
   where t.id = 'e0000000-0000-4000-8000-0000001604e0' and s.id = 'e0000000-0000-4000-8000-0000001604e1'
  returning id)
insert into _p (k, criar) select 'p2', jsonb_build_object('ok', true, 'numero', id) from ins;
insert into _p (k, criar) values ('p3', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604d0","campo":"email","valor_novo":"zz.160404.t1.novo@exemplo.invalid",
   "motivo":"ensaio da migration 20261006160404"}''::jsonb)::jsonb'));
update _p set n = (criar ->> 'numero')::bigint;
do $$ declare v_k text; begin
  for v_k in select x.k from pg_temp._p x order by x.n loop
    update pg_temp._p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
           format('select public.pa_decidir(%s, ''aprovar'')::jsonb', n)) where _p.k = v_k;
  end loop; end $$;
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, campo, valor_atual, valor_novo, valor_aplicado, motivo, status,
                                 solicitado_por, decidido_por, decidido_em, aplicado_em, planilha_status)
  values ('alterar_dado', 'e0000000-0000-4000-8000-0000001604d2', 'ZZ Ensaio 160404 Entra Existente', 'documento',
          '"11111111111"', '"22222222222"', '"22222222222"', 'ensaio da migration 20261006160404', 'aplicado',
          '81d2eaee-cce1-4058-8714-439b0fc6f970', '81d2eaee-cce1-4058-8714-439b0fc6f970', now(), now(), 'pendente')
  returning id)
insert into _p (k, n) select 'p4', id from ins;
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, descricao, motivo, status, solicitado_por, decidido_por, decidido_em, aplicado_em)
  values ('outro', 'e0000000-0000-4000-8000-0000001604d0', 'ZZ Ensaio 160404 Titular Um', 'ensaio 160404: outro aplicado',
          'ensaio da migration 20261006160404', 'aplicado', '81d2eaee-cce1-4058-8714-439b0fc6f970',
          '81d2eaee-cce1-4058-8714-439b0fc6f970', now(), now())
  returning id)
insert into _p (k, n) select 'p5', id from ins;
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, campo, valor_atual, valor_novo, motivo, status, motivo_recusa,
                                 solicitado_por, decidido_por, decidido_em)
  values ('alterar_dado', 'e0000000-0000-4000-8000-0000001604d0', 'ZZ Ensaio 160404 Titular Um', 'profissao', 'null',
          '"Recusada"', 'ensaio da migration 20261006160404', 'recusado', 'ensaio 160404',
          '81d2eaee-cce1-4058-8714-439b0fc6f970', '81d2eaee-cce1-4058-8714-439b0fc6f970', now())
  returning id)
insert into _p (k, n) select 'p6', id from ins;
insert into _p (k, criar) values ('p7', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604d0","campo":"profissao","valor_novo":"Pendente",
   "motivo":"ensaio da migration 20261006160404"}''::jsonb)::jsonb'));
update _p set n = (criar ->> 'numero')::bigint where k = 'p7';
select pg_temp.ok('1.pedido_' || k, case when k in ('p1', 'p2', 'p3') then (decidir ->> 'ok')::boolean and decidir ->> 'status' = 'aplicado'
                                         else n is not null end,
  'nº ' || coalesce(n::text, '?') || ': ' || coalesce(decidir ->> 'msg', decidir ->> 'erro', criar ->> 'msg', criar ->> 'erro', 'gravado direto'))
  from _p order by k;
create temp table _novo on commit drop as select id from public.thb_alunos where email = 'zz.160404.novo@exemplo.invalid';

-- 2. Titular 1: a troca e o e-mail (o mais recente primeiro); "outro", recusado e pendente fora
select pg_temp.ok('2.titular', h = jsonb_build_array(
    jsonb_build_object('papel', 'aluno', 'pedido', pg_temp.n('p3'), 'texto',
      'E-mail alterado de zz.160404.t1@exemplo.invalid para zz.160404.t1.novo@exemplo.invalid' || pg_temp.suf('p3')),
    jsonb_build_object('papel', 'titular', 'pedido', pg_temp.n('p1'), 'texto',
      'ZZ Ensaio 160404 Titular Um trocou o sócio ZZ Ensaio 160404 Sai Um pelo sócio ZZ Ensaio 160404 Entra Existente' || pg_temp.suf('p1'))),
  coalesce(h ->> 'erro', jsonb_array_length(h) || ' linhas: ' || (select string_agg(x ->> 'papel' || ' nº ' || (x ->> 'pedido') || ': ' || (x ->> 'texto'), ' | ')
                                                            from jsonb_array_elements(h) x)))
  from (select pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', 'e0000000-0000-4000-8000-0000001604d0') h) x;

-- 3. Quem sai e quem entra: cada um com o próprio texto
select pg_temp.ok('3.sai', h = jsonb_build_array(jsonb_build_object('papel', 'sai', 'pedido', pg_temp.n('p1'), 'texto',
      'ZZ Ensaio 160404 Sai Um saiu como sócio de ZZ Ensaio 160404 Titular Um' || pg_temp.suf('p1'))),
  coalesce(h ->> 'erro', (select string_agg(x ->> 'papel' || ': ' || (x ->> 'texto'), ' | ') from jsonb_array_elements(h) x)))
  from (select pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', 'e0000000-0000-4000-8000-0000001604d1') h) x;
select pg_temp.ok('3.entra_existente', h = jsonb_build_array(
    jsonb_build_object('papel', 'aluno', 'pedido', pg_temp.n('p4'), 'texto',
      'Documento (CPF ou CNPJ) alterado de 11111111111 para 22222222222' || pg_temp.suf('p4')),
    jsonb_build_object('papel', 'entra', 'pedido', pg_temp.n('p1'), 'texto',
      'ZZ Ensaio 160404 Entra Existente entrou como sócio de ZZ Ensaio 160404 Titular Um' || pg_temp.suf('p1'))),
  coalesce(h ->> 'erro', (select string_agg(x ->> 'papel' || ': ' || (x ->> 'texto'), ' | ') from jsonb_array_elements(h) x)))
  from (select pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', 'e0000000-0000-4000-8000-0000001604d2') h) x;
select pg_temp.ok('3.entra_cadastro_novo', h = jsonb_build_array(jsonb_build_object('papel', 'entra', 'pedido', pg_temp.n('p2'), 'texto',
      'ZZ Ensaio 160404 Novo entrou como sócio de ZZ Ensaio 160404 Titular Dois' || pg_temp.suf('p2') || ' (cadastro novo)')),
  coalesce(h ->> 'erro', (select string_agg(x ->> 'papel' || ': ' || (x ->> 'texto'), ' | ') from jsonb_array_elements(h) x)))
  from (select pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', (select id from _novo)) h) x;
select pg_temp.ok('3.titular_dois_e_sai_dois',
  (select string_agg(x ->> 'papel', ',') from jsonb_array_elements(pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', 'e0000000-0000-4000-8000-0000001604e0')) x) = 'titular'
  and (select string_agg(x ->> 'papel', ',') from jsonb_array_elements(pg_temp.hist('81d2eaee-cce1-4058-8714-439b0fc6f970', 'e0000000-0000-4000-8000-0000001604e1')) x) = 'sai',
  'titular 2 -> só "titular"; sai 2 -> só "sai" (a mesma troca, um texto para cada pessoa)');

-- 4. Documento mascarado para quem não pode ver
select pg_temp.ok('4.doc_mascarado', h -> 0 ->> 'texto' = 'Documento (CPF ou CNPJ) alterado de *******1111 para *******2222' || pg_temp.suf('p4'),
  coalesce(h ->> 'erro', h -> 0 ->> 'texto'))
  from (select pg_temp.hist('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'e0000000-0000-4000-8000-0000001604d2') h) x;

-- 5. Fora da equipe: nada. Anon: sem permissão.
select pg_temp.ok('5.fora_da_equipe', h = '[]'::jsonb, 'uuid sem perfil -> ' || h::text)
  from (select pg_temp.hist('00000000-0000-4000-8000-000000000404', 'e0000000-0000-4000-8000-0000001604d0') h) x;
select pg_temp.ok('5.anon', v ->> 'estado' = '42501', 'anon -> ' || coalesce(v ->> 'erro', v::text))
  from (select pg_temp.anon('select to_jsonb(h) from public.pa_historico_aluno(''e0000000-0000-4000-8000-0000001604d0'') h limit 1') v) x;

-- 6. Plano: como fica hoje (tabela pequena) e com seq scan desligado (prova de que os 3 índices servem)
select pg_temp.plano('6.explain_hoje', $q$
select x.id from public.pa_pedidos x
 where x.status = 'aplicado' and x.tipo in ('trocar_socio', 'alterar_dado')
   and (x.aluno_id = 'e0000000-0000-4000-8000-0000001604d0' or x.socio_sai_id = 'e0000000-0000-4000-8000-0000001604d0'
        or x.socio_entra_id = 'e0000000-0000-4000-8000-0000001604d0') $q$);
set local enable_seqscan = off;
select pg_temp.plano('6.explain_sem_seqscan', $q$
select x.id from public.pa_pedidos x
 where x.status = 'aplicado' and x.tipo in ('trocar_socio', 'alterar_dado')
   and (x.aluno_id = 'e0000000-0000-4000-8000-0000001604d0' or x.socio_sai_id = 'e0000000-0000-4000-8000-0000001604d0'
        or x.socio_entra_id = 'e0000000-0000-4000-8000-0000001604d0') $q$);
reset enable_seqscan;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
