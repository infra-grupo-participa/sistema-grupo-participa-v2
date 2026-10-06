-- 20261006160401: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006160401_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006160401_pa_aprovador_isabela.sql; se a
-- migration mudar, gerar de novo). Antes do corpo: foto de pa_linha do pedido nº 9 (real, pendente) e da linha da Isabela
-- em pa_aprovadores (em produção ela JÁ está lá desde 06/10 19:08 UTC; o corpo não pode falhar nem duplicar). Depois do corpo:
-- aluno ZZ e dois pedidos (consome 2 números da sequência de pa_pedidos):
--   i1 a Isabela pede (alterar e-mail) e ELA aprova      -> autoaprovado = true
--   v1 o Victor pede (alterar profissão) e a Isabela aprova -> autoaprovado = false, decidido_por_nome = Isabela
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select (select count(*) from public.thb_alunos where fonte = 'ensaio_20261006160401') alunos_zz,
--        (select count(*) from public.pa_aprovadores) aprovadores,   -- 2 (Victor e Isabela, como antes do ensaio)
--        (select max(id) from public.pa_pedidos) max_pedido,
--        md5(pg_get_functiondef('public.pa_linha(bigint,boolean)'::regprocedure)) = '24124fa127d6d7ad158148fbc4aa8900' linha_igual;

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

-- ═══ ANTES DO CORPO (foto do estado) ═══

create temp table _antes on commit drop as select public.pa_linha(9, true)::jsonb as j;
create temp table _aprov_antes on commit drop as select perfil_id, criado_em from public.pa_aprovadores;

-- ═══ CORPO DA MIGRATION 20261006160401_pa_aprovador_isabela.sql (cópia sem mudança) ═══
-- 20261006160401: Pedidos de alteração (etapa 2), a Isabela aprova pela tela de pedidos e o pedido marca "autoaprovado"
--
-- STATUS: APLICADA em 06/10/2026 (pentester aprovou). Ensaio: 20261006160401_ensaio.sql (begin … rollback). Notas: 20261006160401.explain.md.
-- Independente das 20261006160402/03/04.
--
-- DECISÃO DO VICTOR (06/10/2026, noite): a Isabela Teixeira APROVA pela tela de pedidos (aba "Aprovar"), sem aviso no
-- Slack. Pode aprovar o próprio pedido; fica registrado quem aprovou e a tela mostra o selo "aprovou o próprio pedido".
-- Ela MANTÉM os acessos que já tem (é admin, vê a Central no sistema e edita a planilha): nada é fechado para ela.
--
-- ESTADO EM PRODUÇÃO: a Isabela JÁ FOI inserida em pa_aprovadores em 06/10/2026 19:08 UTC, por pedido direto do Victor
-- (insert … on conflict do nothing, fora desta migration). Por isso o passo 1 é idempotente e a guarda aceita as duas
-- situações (ela presente ou não).
--
-- O QUE FAZ
--   1. Garante a Isabela (perfil e1d2863d-c975-46bd-b35f-45b1039328e3) em pa_aprovadores (on conflict do nothing: em
--      produção ela já está lá desde 06/10 19:08 UTC). Com isso pa_eh_aprovador(),
--      pa_meu_papel().pode_aprovar, pa_fila, pa_decidir e pa_marcar_aplicado passam a valer para ela (nenhuma função
--      dessas muda). O aviso do Slack (20261006160402) NÃO lê pa_aprovadores: o destinatário é pa_config.slack_destinos.
--   2. pa_linha (portanto pa_fila e pa_meus_pedidos) devolve também `autoaprovado boolean`: true quando o pedido foi
--      aprovado (status aprovado ou aplicado) e decidido_por = solicitado_por. Recusa do próprio pedido não conta.
--      Os demais campos não mudam.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em pa_aprovadores; pa_linha lê 1 pedido por PK (a fila tem limite de 500, hoje 2 pedidos).
--   índice: nenhum novo; a comparação é na própria linha já lida.
--   frequência: a fila é lida ao abrir a aba; o insert roda uma vez.
--   repetição: o insert é idempotente (on conflict do nothing); rodar de novo para no md5 de pa_linha (que já mudou).
--   reversão: bloco REVERSÃO no fim (só o corpo vivo de pa_linha; a Isabela FICA como aprovadora, decisão do Victor).
--
-- BASE: pa_linha recriada a partir do corpo VIVO (pg_get_functiondef lido em 06/10/2026), conferido pelo md5 na guarda.
-- Quem lê fora do v2: ninguém (grep de pa_pedidos/pa_linha/pa_fila em disparos-thb, controle-de-eventos,
-- departamento-de-marketing, gp-operacoes e dashboard-ht sem ocorrência).

set local lock_timeout = '5s';

-- ═══ 0. Guarda: o banco tem que estar como foi lido em 06/10/2026 ═══
do $guarda$
begin
  if md5(pg_get_functiondef('public.pa_linha(bigint,boolean)'::regprocedure)) <> '24124fa127d6d7ad158148fbc4aa8900' then
    raise exception '20261006160401: corpo vivo de pa_linha mudou desde 06/10/2026 (md5 diferente): reler e regerar';
  end if;
  if not exists (select 1 from public.perfis
                  where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and nome = 'Isabela Teixeira' and status = 'ativo') then
    raise exception '20261006160401: perfil da Isabela Teixeira não encontrado ou inativo';
  end if;
end
$guarda$;

-- ═══ 1. Isabela aprova (em produção ela já está; não duplica nem falha) ═══
insert into public.pa_aprovadores (perfil_id) values ('e1d2863d-c975-46bd-b35f-45b1039328e3')
on conflict (perfil_id) do nothing;

-- ═══ 2. pa_linha com `autoaprovado` ═══
CREATE OR REPLACE FUNCTION public.pa_linha(p_id bigint, p_aprovador boolean)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r public.pa_pedidos%rowtype;
  v_doc boolean := public.pa_pode_ver_doc();
  v_agora jsonb;
  v_conflito boolean := false;
  v_sai_vinculado boolean;
begin
  select * into r from public.pa_pedidos where id = p_id;
  if not found then return null; end if;
  if p_aprovador and r.status in ('pendente', 'erro') then
    if r.tipo = 'alterar_dado' and r.aluno_id is not null then
      v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
      v_conflito := v_agora is distinct from r.valor_atual;
    elsif r.tipo = 'trocar_socio' then
      v_sai_vinculado := r.aluno_id is not null and r.socio_sai_id is not null
                         and public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id);
      v_conflito := not v_sai_vinculado;
    end if;
  end if;
  return json_build_object(
    'id', r.id, 'tipo', r.tipo, 'status', r.status,
    'aluno_id', r.aluno_id, 'aluno_nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
    'aluno', case when p_aprovador and r.aluno_id is not null then public.pa_resumo_aluno(r.aluno_id) end,
    'campo', r.campo,
    'de', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, r.valor_atual, v_doc) end,
    'para', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, coalesce(r.valor_aplicado, r.valor_novo), v_doc) end,
    'agora', case when p_aprovador and r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, v_agora, v_doc) end,
    'valor_novo', case when p_aprovador and (r.campo <> 'documento' or v_doc) then r.valor_novo end,
    'conflito', v_conflito,
    'socio_sai_id', r.socio_sai_id, 'socio_sai_nome', r.socio_sai_nome,
    'socio_sai_vinculado', v_sai_vinculado,
    'socio_entra_id', r.socio_entra_id, 'socio_entra_nome', r.socio_entra_nome,
    'socio_entra_novo', case when r.socio_entra_novo is null then null
                             else r.socio_entra_novo || jsonb_build_object('documento',
                                    public.pa_mascara_doc(r.socio_entra_novo ->> 'documento', v_doc)) end,
    'descricao', r.descricao, 'motivo', r.motivo, 'evidencia', r.evidencia,
    'solicitado_em', r.solicitado_em,
    'solicitado_por_nome', (select p.nome from public.perfis p where p.id = r.solicitado_por),
    'decidido_em', r.decidido_em,
    'decidido_por_nome', (select p.nome from public.perfis p where p.id = r.decidido_por),
    'motivo_recusa', r.motivo_recusa, 'conflito_confirmado', r.conflito_confirmado,
    -- 20261006160401: quem decidiu é quem pediu (a Isabela pode aprovar o próprio pedido). Só aprovação conta.
    'autoaprovado', coalesce(r.status in ('aprovado', 'aplicado') and r.decidido_por = r.solicitado_por, false),
    'aplicado_em', r.aplicado_em, 'erro_msg', r.erro_msg,
    'planilha_status', r.planilha_status, 'planilha_em', r.planilha_em, 'planilha_erro', r.planilha_erro,
    'ra_caso_id', r.ra_caso_id,
    'historico', case when p_aprovador then coalesce((
       select json_agg(json_build_object('acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em, h.id)
         from public.pa_historico h left join public.perfis hp on hp.id = h.por
        where h.pedido_id = r.id), '[]'::json) end);
end
$function$;

-- ═══ 3. Conferência: grants iguais aos de antes (create or replace não mexe neles) e campo novo presente ═══
do $confere$
begin
  if has_function_privilege('authenticated', 'public.pa_linha(bigint,boolean)', 'execute')
     or has_function_privilege('anon', 'public.pa_linha(bigint,boolean)', 'execute') then
    raise exception '20261006160401: pa_linha ficou exposta para anon/authenticated';
  end if;
  if position('''autoaprovado''' in pg_get_functiondef('public.pa_linha(bigint,boolean)'::regprocedure)) = 0 then
    raise exception '20261006160401: pa_linha sem o campo autoaprovado';
  end if;
  if (select count(*) from public.pa_aprovadores
       where perfil_id in ('e1d2863d-c975-46bd-b35f-45b1039328e3', '81d2eaee-cce1-4058-8714-439b0fc6f970')) <> 2 then
    raise exception '20261006160401: aprovadores diferentes do esperado (Victor e Isabela)';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Volta pa_linha ao corpo vivo lido em 06/10/2026: a tela deixa de receber `autoaprovado` (o selo some).
-- A Isabela NÃO sai de pa_aprovadores: ela continua aprovadora (decisão do Victor, 06/10/2026; foi inserida em produção
-- antes desta migration). Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- CREATE OR REPLACE FUNCTION public.pa_linha(p_id bigint, p_aprovador boolean)
--  RETURNS json
--  LANGUAGE plpgsql
--  STABLE SECURITY DEFINER
--  SET search_path TO ''
-- AS $function$
-- declare
--   r public.pa_pedidos%rowtype;
--   v_doc boolean := public.pa_pode_ver_doc();
--   v_agora jsonb;
--   v_conflito boolean := false;
--   v_sai_vinculado boolean;
-- begin
--   select * into r from public.pa_pedidos where id = p_id;
--   if not found then return null; end if;
--   if p_aprovador and r.status in ('pendente', 'erro') then
--     if r.tipo = 'alterar_dado' and r.aluno_id is not null then
--       v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
--       v_conflito := v_agora is distinct from r.valor_atual;
--     elsif r.tipo = 'trocar_socio' then
--       v_sai_vinculado := r.aluno_id is not null and r.socio_sai_id is not null
--                          and public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id);
--       v_conflito := not v_sai_vinculado;
--     end if;
--   end if;
--   return json_build_object(
--     'id', r.id, 'tipo', r.tipo, 'status', r.status,
--     'aluno_id', r.aluno_id, 'aluno_nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
--     'aluno', case when p_aprovador and r.aluno_id is not null then public.pa_resumo_aluno(r.aluno_id) end,
--     'campo', r.campo,
--     'de', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, r.valor_atual, v_doc) end,
--     'para', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, coalesce(r.valor_aplicado, r.valor_novo), v_doc) end,
--     'agora', case when p_aprovador and r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, v_agora, v_doc) end,
--     'valor_novo', case when p_aprovador and (r.campo <> 'documento' or v_doc) then r.valor_novo end,
--     'conflito', v_conflito,
--     'socio_sai_id', r.socio_sai_id, 'socio_sai_nome', r.socio_sai_nome,
--     'socio_sai_vinculado', v_sai_vinculado,
--     'socio_entra_id', r.socio_entra_id, 'socio_entra_nome', r.socio_entra_nome,
--     'socio_entra_novo', case when r.socio_entra_novo is null then null
--                              else r.socio_entra_novo || jsonb_build_object('documento',
--                                     public.pa_mascara_doc(r.socio_entra_novo ->> 'documento', v_doc)) end,
--     'descricao', r.descricao, 'motivo', r.motivo, 'evidencia', r.evidencia,
--     'solicitado_em', r.solicitado_em,
--     'solicitado_por_nome', (select p.nome from public.perfis p where p.id = r.solicitado_por),
--     'decidido_em', r.decidido_em,
--     'decidido_por_nome', (select p.nome from public.perfis p where p.id = r.decidido_por),
--     'motivo_recusa', r.motivo_recusa, 'conflito_confirmado', r.conflito_confirmado,
--     'aplicado_em', r.aplicado_em, 'erro_msg', r.erro_msg,
--     'planilha_status', r.planilha_status, 'planilha_em', r.planilha_em, 'planilha_erro', r.planilha_erro,
--     'ra_caso_id', r.ra_caso_id,
--     'historico', case when p_aprovador then coalesce((
--        select json_agg(json_build_object('acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em, h.id)
--          from public.pa_historico h left join public.perfis hp on hp.id = h.por
--         where h.pedido_id = r.id), '[]'::json) end);
-- end
-- $function$;

-- ═══ ENSAIO: testes ═══════════════════════════════════════════════════════════════════════════

-- 0. Isabela já presente: o corpo passou, sem duplicar e sem mexer na linha que existia
select pg_temp.ok('0.isabela_ja_estava',
  (select count(*) from pg_temp._aprov_antes where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') = 1
  and (select count(*) from public.pa_aprovadores) = (select count(*) from pg_temp._aprov_antes)
  and (select criado_em from public.pa_aprovadores where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3')
      = (select criado_em from pg_temp._aprov_antes where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3'),
  'antes do corpo: ' || (select count(*) from pg_temp._aprov_antes) || ' aprovadores (Isabela incluída); depois: '
  || (select count(*) from public.pa_aprovadores) || '; criado_em da Isabela inalterado');

-- 1. Papel da Isabela
select pg_temp.ok('1.papel_isabela',
  (v ->> 'pode_aprovar')::boolean and (v ->> 'pode_pedir')::boolean,
  'pa_meu_papel como Isabela: pode_pedir=' || coalesce(v ->> 'pode_pedir', v ->> 'erro') || ' pode_aprovar=' || coalesce(v ->> 'pode_aprovar', '?'))
  from (select pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3', 'select public.pa_meu_papel()::jsonb') v) x;

-- 2. Cenário: aluno ZZ e dois pedidos
insert into public.thb_alunos (id, nome, email, instrucao, espaco_instrucao, profissao, fonte)
values ('e0000000-0000-4000-8000-000000160401', 'ZZ Ensaio 160401 Aluno', 'zz.160401.aluno@exemplo.invalid',
        'THB', 'holding_masters', 'Advogada', 'ensaio_20261006160401');

create temp table _p (k text primary key, criar jsonb, decidir jsonb) on commit drop;
insert into _p (k, criar) values
 ('i1', pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-000000160401","campo":"email","valor_novo":"zz.160401.novo@exemplo.invalid",
   "motivo":"ensaio da migration 20261006160401"}''::jsonb)::jsonb')),
 ('v1', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-000000160401","campo":"profissao","valor_novo":"Contadora",
   "motivo":"ensaio da migration 20261006160401"}''::jsonb)::jsonb'));
update _p set decidir = pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint));
select pg_temp.ok('2.decidir_' || k, (decidir ->> 'ok')::boolean and decidir ->> 'status' = 'aplicado',
  coalesce(decidir ->> 'msg', decidir ->> 'erro', criar ->> 'msg', criar ->> 'erro')) from _p order by k;

-- 3. A Isabela aprovou o próprio: autoaprovado = true, nos três caminhos (pa_linha, pa_fila, pa_meus_pedidos)
select pg_temp.ok('3.autoaprovado_proprio',
  (l ->> 'autoaprovado')::boolean and (f ->> 'autoaprovado')::boolean and (m ->> 'autoaprovado')::boolean
  and l ->> 'decidido_por_nome' = 'Isabela Teixeira' and l ->> 'solicitado_por_nome' = 'Isabela Teixeira',
  'pedido nº ' || n || ': pa_linha=' || coalesce(l ->> 'autoaprovado', 'nulo') || ' pa_fila=' || coalesce(f ->> 'autoaprovado', f ->> 'erro', 'nulo')
  || ' pa_meus_pedidos=' || coalesce(m ->> 'autoaprovado', m ->> 'erro', 'nulo')
  || ' | pediu ' || coalesce(l ->> 'solicitado_por_nome', '?') || ', decidiu ' || coalesce(l ->> 'decidido_por_nome', '?'))
  from (select n,
               public.pa_linha(n, true)::jsonb l,
               pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3',
                 format('select (select x::jsonb from public.pa_fila(true) x where (x ->> ''id'')::bigint = %s)', n)) f,
               pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3',
                 format('select (select x::jsonb from public.pa_meus_pedidos() x where (x ->> ''id'')::bigint = %s)', n)) m
          from (select (criar ->> 'numero')::bigint n from _p where k = 'i1') y) x;
select pg_temp.ok('3.decidido_por_gravado',
  (select decidido_por = solicitado_por and decidido_por = 'e1d2863d-c975-46bd-b35f-45b1039328e3'
     from public.pa_pedidos where id = (select (criar ->> 'numero')::bigint from _p where k = 'i1')),
  'pa_pedidos.decidido_por = solicitado_por = perfil da Isabela');

-- 4. A Isabela aprovou o pedido do Victor: autoaprovado = false
select pg_temp.ok('4.aprovou_de_outro',
  not (l ->> 'autoaprovado')::boolean and l ->> 'decidido_por_nome' = 'Isabela Teixeira' and l ->> 'solicitado_por_nome' = 'Victor Hugo',
  'pedido nº ' || (l ->> 'id') || ': autoaprovado=' || coalesce(l ->> 'autoaprovado', 'nulo') || ' | pediu '
  || coalesce(l ->> 'solicitado_por_nome', '?') || ', decidiu ' || coalesce(l ->> 'decidido_por_nome', '?'))
  from (select public.pa_linha((criar ->> 'numero')::bigint, true)::jsonb l from _p where k = 'v1') x;

-- 5. Campos que já existiam não mudam (pedido nº 9, real, pendente): mesmo json sem a chave nova
select pg_temp.ok('5.campos_iguais',
  (public.pa_linha(9, true)::jsonb - 'autoaprovado') = (select j from _antes)
  and (public.pa_linha(9, true)::jsonb ->> 'autoaprovado') = 'false'
  and (select count(*) from jsonb_object_keys(public.pa_linha(9, true)::jsonb)) = (select count(*) from jsonb_object_keys((select j from _antes))) + 1,
  'pa_linha(9): ' || (select count(*) from jsonb_object_keys((select j from _antes))) || ' campos antes, iguais depois + autoaprovado=false');

-- 6. Fila da Isabela enxerga os pendentes reais (9 e 10), sem aviso de Slack (nada em pa_aprovadores é lido pelo aviso)
select pg_temp.ok('6.fila_isabela',
  (v ->> 'n')::int >= 2,
  'pa_fila(false) como Isabela: ' || coalesce(v ->> 'n', v ->> 'erro') || ' pedidos (pendente/erro/aprovado)')
  from (select pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3',
          'select jsonb_build_object(''n'', (select count(*) from public.pa_fila(false)))') v) x;

-- 7. Grants
select pg_temp.ok('7.grants',
  not has_function_privilege('authenticated', 'public.pa_linha(bigint,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.pa_linha(bigint,boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.pa_fila(boolean)', 'execute')
  and not has_function_privilege('anon', 'public.pa_fila(boolean)', 'execute')
  and not has_table_privilege('authenticated', 'public.pa_aprovadores', 'select'),
  'pa_linha interna; pa_fila só authenticated; pa_aprovadores fechada');

-- 8. Plano da fila como a Isabela a lê (pa_fila(true) = 90 dias)
select pg_temp.plano('8.explain_fila', 'select x.id from public.pa_pedidos x where x.status in (''pendente'', ''erro'', ''aprovado'') or x.solicitado_em >= now() - interval ''90 days'' order by case x.status when ''pendente'' then 0 when ''erro'' then 1 when ''aprovado'' then 2 else 3 end, x.id desc limit 500');

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
