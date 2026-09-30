-- 20261003f — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada,
-- DEPOIS de 20261003a–e aplicadas. Grava de verdade em thb_alunos/audit/decisões DENTRO da transação e desfaz no fim.
-- Nenhum nome/e-mail sai no resultado: a ref é medida só por contagem.
-- Esperados:
--   0.eq_pode_editar          = t, t, f (equipe, editor, não SIP) — se f, as escritas abaixo dão 42501: trocar de perfil
--   1.self                    = 23514 · 1.titular_e_socio = 23514 (ou 'sem caso') · 1.socio_com_socios = 23514 (ou 'sem caso')
--   1.par_depois              = titular fk nula/eh_socio f; sócio fk = titular/eh_socio t; mutuos = 0
--   1.par_audit               = 2 a 4 linhas origem conciliacao_tela · 1.par_item_aberto = 0
--   1.mutuo_direto            = 23514 (trava da b) · 1.flip = mutuos 0 · 1.vira_titular = fk nula, eh_socio f
--   2.marcar_id               = id (bigint) · 2.marcado_aberto = 0 · 2.marcado_conferidos = t, bate t
--   2.marcar_de_novo / 2.marcar_inventado / 2.decisao_invalida / 2.decisao_incompativel = 22023
--   2.desmarcar = volta aberto 1 · 2.desmarcar_de_novo = P0002
--   2.muda_dado               = item antigo 0 aberto; item novo do mesmo aluno aberto ≥ 1 (ou 'sem caso')
--   3.ref_aberto              = linhas ≥ 1 com nome/email preenchidos (só contagem) · 3.ref_inventado/fechado/outro_tipo = 0
--   4.explain_*               = Execution Time (marcar e ref ≈ custo da conciliação, ≤ 1,5 s)
--   5.anon_* / 5.fora_* = 42501 · 5.equipe_direto_* = 42501
--
-- RESULTADO (30/09/2026, produção). O arquivo inteiro estoura os 60 s do MCP (~30 chamadas de ~1,7 s à conciliação),
-- então rodou em 3 partes, cada uma em begin … ZOUT (desfeita). A 20261003f foi APLICADA entre a parte 2 e a parte 3;
-- a parte 3 rodou contra as funções já aplicadas. Tudo conforme:
--   parte 1: self / titular_e_socio / socio_com_socios / mutuo_direto = 23514 · par resolvido, flip e vira_titular sem
--            erro, mútuos 0, item do par fechado, 8 linhas de audit origem conciliacao_tela
--   parte 2: marcar → id; aberto 0; conferidos t/bate t · marcar_de_novo, inventado, decisao_invalida/incompativel = 22023
--            desmarcar → aberto 1 · desmarcar_de_novo/inexistente = P0002 · pessoas_diferentes e manter_sem_acesso ok
--            muda_dado = (t,0,1): item antigo fechado, item novo aberto
--   parte 3: ref_aberto comprou_em_ativacao 1/1 · comprou_fora_da_base 3/3 · placa_sem_aluno 1 (sem valor) ·
--            sip_sem_aluno 1 (sem valor) · ref_inventado 0 · ref_outro_tipo 0 · ref_fechado (t,0)
--            explain: marcar 1.724 ms · ref 1.721 ms (= custo da conciliação) · definir 2,3 ms
--            grants: anon f / authenticated t nas 4 funções · anon_* = 42501 · fora_* = 42501 (guarda no corpo)
--            equipe_definir_ok sem erro · equipe_direto_select/update/insert = 42501

begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to authenticated, anon;
create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;
create function pg_temp.z_err(p_passo text, p_sql text) returns void language plpgsql as $f$
begin
  execute p_sql;
  insert into pg_temp._z_out (passo, linha) values (p_passo, 'SEM ERRO');
exception when others then
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;
create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;
grant execute on function pg_temp.z_q(text, text), pg_temp.z_err(text, text), pg_temp.z_explain(text, text) to authenticated, anon;
-- papéis: equipe (dev/admin @advmais) e não-equipe (perfil ativo que não passa em gp_eh_equipe)
select set_config('z.eq', (select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
                             and p.cargo in ('dev', 'admin') order by p.id limit 1), true);

-- ─── 0. ANTES ───────────────────────────────────────────────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select pg_temp.z_q('0.ja_existe', $q$select proname from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('fn_aluno_definir_titular','fn_aluno_conciliacao_marcar','fn_aluno_conciliacao_desmarcar','fn_aluno_conciliacao_ref')$q$);
select pg_temp.z_q('0.eq_pode_editar', $q$select public.gp_eh_equipe(), public.gp_pode_editar('centro_controle'), public.is_sip_user(auth.uid())$q$);
select pg_temp.z_q('0.audit_tela_antes', $q$select count(*) from public.thb_alunos_audit_log where origem = 'conciliacao_tela'$q$);

-- ─── Migration (cópia literal do corpo da 20261003f) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas (falham ANTES de gravar) ───────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  select string_agg(x.f, ', ') into v_falta
    from unnest(array['public.fn_aluno_conciliacao(uuid,boolean)', 'public.fn_aluno_compras_fora_base()',
                      'public.fn_aluno_pagamentos_programa()', 'public.fn_thb_alunos_trava_vinculo_socio()',
                      'public.gp_eh_equipe()', 'public.gp_pode_editar(text)', 'public.is_sip_user(uuid)',
                      'public.gp_pode_ver_financeiro()', 'fin.chave_opaca(text)']) x(f)
   where to_regprocedure(x.f) is null;
  if v_falta is not null then
    raise exception '20261003f: função ausente (aplicar a→e antes): %', v_falta;
  end if;
  if to_regclass('public.thb_aluno_conciliacao_decisao') is null then
    raise exception '20261003f: public.thb_aluno_conciliacao_decisao ausente (aplicar a 20261003e antes)';
  end if;
  -- a trava de vínculo (b) tem que estar ligada: definir_titular conta com ela contra par mútuo
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.thb_alunos'::regclass
                    and t.tgname = 'trg_thb_alunos_trava_vinculo_socio' and t.tgenabled <> 'D') then
    raise exception '20261003f: trigger trg_thb_alunos_trava_vinculo_socio ausente ou desligado (aplicar a 20261003b)';
  end if;
  select string_agg(format('%s.%s.%s', x.s, x.t, x.c), ', ') into v_falta
    from (values ('public','thb_alunos','eh_socio'), ('public','thb_alunos','socio_de_aluno_id'), ('public','thb_alunos','cancelado_em'),
                 ('public','thb_alunos','atualizado_em'), ('public','thb_alunos','atualizado_por'),
                 ('public','thb_alunos_audit_log','aluno_id'), ('public','thb_alunos_audit_log','campo'),
                 ('public','thb_alunos_audit_log','valor_anterior'), ('public','thb_alunos_audit_log','valor_novo'),
                 ('public','thb_alunos_audit_log','origem'),
                 ('sip','users','name'), ('sip','users','email'), ('sip','users','role'), ('sip','users','created_at'),
                 ('public','thb_placas_solicitacoes','nome'), ('public','thb_placas_solicitacoes','email'),
                 ('public','thb_placas_solicitacoes','nivel'), ('public','thb_placas_solicitacoes','created_at'),
                 ('fin','vw_transacoes','email'), ('fin','vw_transacoes','nome'), ('fin','vw_transacoes','produto_nome'),
                 ('fin','vw_transacoes','valor_cobrado'), ('fin','vw_transacoes','aprovado_em'),
                 ('fin','identidade','no'), ('fin','identidade','pessoa_chave')) x(s, t, c)
    left join information_schema.columns c on c.table_schema = x.s and c.table_name = x.t and c.column_name = x.c
   where c.column_name is null;
  if v_falta is not null then
    raise exception '20261003f: coluna ausente: %', v_falta;
  end if;
end $guarda$;

-- ─── 1. Definir titular (resolve par, cadeia, órfão e vínculo sem marcação) ─────────────────────────────────────────
create or replace function public.fn_aluno_definir_titular(p_socio uuid, p_titular uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_s   record;
  v_t   record;
  v_por uuid;
begin
  -- guarda = policy UPDATE viva de thb_alunos (thb_alunos_update_editores + sip_block_thb_alunos)
  if not (coalesce(public.gp_pode_editar('centro_controle'), false)
          and not coalesce(public.is_sip_user(auth.uid()), false)) then
    raise exception 'fn_aluno_definir_titular: sem permissão de edição de alunos' using errcode = '42501';
  end if;
  if p_socio is null then
    raise exception 'fn_aluno_definir_titular: aluno não informado' using errcode = '22023';
  end if;
  if p_titular = p_socio then
    raise exception 'Vínculo de sócio inválido: o aluno não pode ser sócio de si mesmo.'
      using errcode = '23514', detail = 'caso=autorreferencia';
  end if;

  -- lock das duas linhas em ordem de id (dois cliques cruzados não se travam)
  perform 1 from public.thb_alunos a where a.id in (p_socio, p_titular) order by a.id for update;

  select a.id, a.eh_socio, a.socio_de_aluno_id as fk, a.cancelado_em into v_s from public.thb_alunos a where a.id = p_socio;
  if not found or v_s.cancelado_em is not null then
    raise exception 'fn_aluno_definir_titular: aluno inexistente ou cancelado' using errcode = 'P0002';
  end if;
  v_por := (select p.id from public.perfis p where p.id = auth.uid());   -- FK de atualizado_por → perfis

  if p_titular is null then
    -- p_socio vira titular
    update public.thb_alunos a
       set socio_de_aluno_id = null, eh_socio = false, atualizado_em = now(), atualizado_por = v_por
     where a.id = p_socio and (a.socio_de_aluno_id is not null or a.eh_socio);
    insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
    select p_socio, c.campo, c.ant, c.novo, 'conciliacao_tela'
      from (values ('socio_de_aluno_id', v_s.fk::text, null::text), ('eh_socio', v_s.eh_socio::text, 'false')) c(campo, ant, novo)
     where c.ant is distinct from c.novo;
    return;
  end if;

  select a.id, a.eh_socio, a.socio_de_aluno_id as fk, a.cancelado_em into v_t from public.thb_alunos a where a.id = p_titular;
  if not found or v_t.cancelado_em is not null then
    raise exception 'fn_aluno_definir_titular: titular inexistente ou cancelado' using errcode = 'P0002';
  end if;
  if v_t.fk is not null and v_t.fk <> p_socio then
    raise exception 'Vínculo de sócio inválido: o titular escolhido é sócio de outro aluno.'
      using errcode = '23514', detail = 'caso=titular_e_socio';
  end if;
  if exists (select 1 from public.thb_alunos a
              where a.socio_de_aluno_id = p_socio and a.id <> p_titular and a.cancelado_em is null) then
    raise exception 'Vínculo de sócio inválido: este aluno é titular de outros sócios; defina o titular deles antes.'
      using errcode = '23514', detail = 'caso=socio_com_socios';
  end if;

  -- 1º o titular (perde a FK do par mútuo, se houver, e a marcação de sócio); 2º o sócio
  update public.thb_alunos a
     set socio_de_aluno_id = null, eh_socio = false, atualizado_em = now(), atualizado_por = v_por
   where a.id = p_titular and (a.socio_de_aluno_id is not null or a.eh_socio);
  update public.thb_alunos a
     set socio_de_aluno_id = p_titular, eh_socio = true, atualizado_em = now(), atualizado_por = v_por
   where a.id = p_socio and (a.socio_de_aluno_id is distinct from p_titular or not a.eh_socio);

  insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
  select c.aluno_id, c.campo, c.ant, c.novo, 'conciliacao_tela'
    from (values (p_titular, 'socio_de_aluno_id', v_t.fk::text, null::text),
                 (p_titular, 'eh_socio', v_t.eh_socio::text, 'false'),
                 (p_socio, 'socio_de_aluno_id', v_s.fk::text, p_titular::text),
                 (p_socio, 'eh_socio', v_s.eh_socio::text, 'true')) c(aluno_id, campo, ant, novo)
   where c.ant is distinct from c.novo;
end;
$fn$;

comment on function public.fn_aluno_definir_titular(uuid, uuid) is
  '20261003f: define o titular de um sócio (p_titular nulo = vira titular). Resolve par mútuo na mesma chamada; recusa '
  'autorreferência e cadeia (23514). Guarda = policy UPDATE de thb_alunos. Audit origem conciliacao_tela.';

revoke all on function public.fn_aluno_definir_titular(uuid, uuid) from public, anon;
grant execute on function public.fn_aluno_definir_titular(uuid, uuid) to authenticated;

-- ─── 2. Marcar decisão (item aberto agora) ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_conciliacao_marcar(p_item text, p_decisao text, p_obs text default null)
returns bigint
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_tipo  text;
  v_aluno uuid;
  v_id    bigint;
begin
  if not (coalesce(public.gp_eh_equipe(), false)
          and coalesce(public.gp_pode_editar('centro_controle'), false)
          and not coalesce(public.is_sip_user(auth.uid()), false)) then
    raise exception 'fn_aluno_conciliacao_marcar: sem permissão' using errcode = '42501';
  end if;
  if p_decisao is null or p_decisao not in ('conferido', 'pessoas_diferentes', 'manter_sem_acesso') then
    raise exception 'fn_aluno_conciliacao_marcar: decisão inválida' using errcode = '22023';
  end if;

  select c.tipo, c.aluno_id into v_tipo, v_aluno
    from public.fn_aluno_conciliacao(null, false) c
   where c.item = p_item
   order by c.aluno_id nulls last
   limit 1;
  if v_tipo is null then
    raise exception 'fn_aluno_conciliacao_marcar: item não está aberto (já decidido, resolvido ou inexistente)' using errcode = '22023';
  end if;
  if (p_decisao = 'pessoas_diferentes' and v_tipo <> 'possivel_duplicado')
     or (p_decisao = 'manter_sem_acesso' and v_tipo <> 'revogado_com_vigencia') then
    raise exception 'fn_aluno_conciliacao_marcar: decisão % não se aplica a %', p_decisao, v_tipo using errcode = '22023';
  end if;

  begin
    insert into public.thb_aluno_conciliacao_decisao (item, tipo, aluno_id, decisao, observacao, decidido_por)
    values (p_item, v_tipo, v_aluno, p_decisao, nullif(btrim(p_obs), ''), auth.uid())
    returning id into v_id;
  exception when unique_violation then
    raise exception 'fn_aluno_conciliacao_marcar: item já decidido por outra pessoa' using errcode = '23505';
  end;
  return v_id;
end;
$fn$;

comment on function public.fn_aluno_conciliacao_marcar(text, text, text) is
  '20261003f: grava a decisão de um item ABERTO da conciliação e devolve o id (o "Desfazer" passa esse id). Só equipe editora.';

revoke all on function public.fn_aluno_conciliacao_marcar(text, text, text) from public, anon;
grant execute on function public.fn_aluno_conciliacao_marcar(text, text, text) to authenticated;

-- ─── 3. Desfazer decisão ────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_conciliacao_desmarcar(p_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not (coalesce(public.gp_eh_equipe(), false)
          and coalesce(public.gp_pode_editar('centro_controle'), false)
          and not coalesce(public.is_sip_user(auth.uid()), false)) then
    raise exception 'fn_aluno_conciliacao_desmarcar: sem permissão' using errcode = '42501';
  end if;
  update public.thb_aluno_conciliacao_decisao d
     set revertido_em = now(), revertido_por = auth.uid()
   where d.id = p_id and d.revertido_em is null;
  if not found then
    raise exception 'fn_aluno_conciliacao_desmarcar: decisão inexistente ou já desfeita' using errcode = 'P0002';
  end if;
end;
$fn$;

comment on function public.fn_aluno_conciliacao_desmarcar(bigint) is
  '20261003f: desfaz uma decisão (revertido_em). Nunca DELETE. Só equipe editora.';

revoke all on function public.fn_aluno_conciliacao_desmarcar(bigint) from public, anon;
grant execute on function public.fn_aluno_conciliacao_desmarcar(bigint) to authenticated;

-- ─── 4. Dado de referência sob clique (só item aberto de fora_base) ─────────────────────────────────────────────────
create or replace function public.fn_aluno_conciliacao_ref(p_item text)
returns table (fonte text, nome text, email text, produto text, data timestamptz, valor numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
declare
  v_tipo  text;
  v_ref   text;
  v_fin   boolean;
  v_chave text;
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_conciliacao_ref: acesso restrito à equipe' using errcode = '42501';
  end if;

  select c.tipo, c.ref_externa into v_tipo, v_ref
    from public.fn_aluno_conciliacao(null, false) c
   where c.item = p_item
     and c.tipo in ('comprou_fora_da_base', 'comprou_em_ativacao', 'sip_sem_aluno', 'placa_sem_aluno')
   limit 1;
  if v_ref is null then
    return;   -- fechado, inventado ou de outro tipo: nada (sem oráculo)
  end if;
  v_fin := coalesce(public.gp_pode_ver_financeiro(), false);

  if v_tipo = 'sip_sem_aluno' then
    return query
    select 'sip'::text, u.name, u.email, u.role, u.created_at, null::numeric
      from sip.users u where u.id = v_ref::uuid;
  elsif v_tipo = 'placa_sem_aluno' then
    return query
    select 'placa'::text, s.nome, s.email, s.nivel, s.created_at, null::numeric
      from public.thb_placas_solicitacoes s where s.id = v_ref::uuid;
  else
    select f.pessoa_chave into v_chave
      from public.fn_aluno_compras_fora_base() f
     where fin.chave_opaca(f.pessoa_chave) = v_ref
     limit 1;
    if v_chave is null then
      return;
    end if;
    return query
    with em as (
      select substr(i.no, 3) as email from fin.identidade i where i.pessoa_chave = v_chave and i.no like 'e:%'
      union
      select substr(v_chave, 8) where v_chave like '#email:%'
    )
    select 'hotmart'::text, t.nome, t.email, t.produto_nome, coalesce(t.aprovado_em, t.pedido_em),
           case when v_fin then t.valor_cobrado end
      from fin.vw_transacoes t
      left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
     where t.email in (select em.email from em)
       and t.grupo = 'pago'
       and ((t.familia = 'HM' and t.produto_id <> '446345' and coalesce(t.produto_nome, '') not ilike '%curso pr_tico%')
            or c.categoria is not null
            or t.familia in ('AURUM', 'PROGRAMA_DIAMANTE'))
     order by coalesce(t.aprovado_em, t.pedido_em) desc nulls last
     limit 5;
  end if;
end;
$fn$;

comment on function public.fn_aluno_conciliacao_ref(text) is
  '20261003f: nome/e-mail/produto/data de quem está fora da base (compra, SIP ou placa), só para item ABERTO destes tipos. '
  'valor só com gp_pode_ver_financeiro(). 1 chamada por clique. Só equipe.';

revoke all on function public.fn_aluno_conciliacao_ref(text) from public, anon;
grant execute on function public.fn_aluno_conciliacao_ref(text) to authenticated;

-- ─── 5. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if exists (select 1 from unnest(array['public.fn_aluno_definir_titular(uuid,uuid)', 'public.fn_aluno_conciliacao_marcar(text,text,text)',
                                        'public.fn_aluno_conciliacao_desmarcar(bigint)', 'public.fn_aluno_conciliacao_ref(text)']) f
              where has_function_privilege('anon', f, 'execute')
                 or not has_function_privilege('authenticated', f, 'execute')
                 or not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                                   and p.proconfig @> array['search_path=public, pg_temp'])
                 or exists (select 1 from pg_proc p, aclexplode(p.proacl) g
                             where p.oid = f::regprocedure and g.grantee = 0 and g.privilege_type = 'EXECUTE')) then
    raise exception '20261003f: grants/definer das funções de escrita fora do esperado';
  end if;
  if pg_get_function_result('public.fn_aluno_conciliacao_marcar(text,text,text)'::regprocedure) <> 'bigint' then
    raise exception '20261003f: fn_aluno_conciliacao_marcar não devolve bigint';
  end if;
  -- a tabela continua fechada para acesso direto
  if has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'select')
     or has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'insert')
     or has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'update') then
    raise exception '20261003f: thb_aluno_conciliacao_decisao acessível direto por authenticated';
  end if;
end $confere$;

-- auxiliar: executa um SQL escalar, guarda o valor num GUC local e registra valor ou erro (o ensaio não aborta)
create function pg_temp.z_set(p_passo text, p_nome text, p_sql text) returns void language plpgsql as $f$
declare v text;
begin
  execute p_sql into v;
  perform set_config(p_nome, coalesce(v, ''), true);
  insert into pg_temp._z_out (passo, linha) values (p_passo, coalesce(v, '(null)'));
exception when others then
  perform set_config(p_nome, '', true);
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;

create function pg_temp.z_explain_s(p_passo text, p_sql text) returns void language plpgsql as $f$
begin
  perform pg_temp.z_explain(p_passo, p_sql);
exception when others then
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;

-- ─── 1. Definir titular (como postgres, com o JWT de equipe: as guardas leem auth.uid()) ────────────────────────────
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
create temp table _z_c on commit drop as select * from public.fn_aluno_conciliacao(null, false);
select set_config('z.pitem', coalesce((select item from _z_c where tipo = 'socio_par_mutuo' order by item limit 1), ''), true);
select set_config('z.pa', coalesce((select least(aluno_id, ref_aluno_id)::text from _z_c where item = current_setting('z.pitem') limit 1), ''), true);
select set_config('z.pb', coalesce((select greatest(aluno_id, ref_aluno_id)::text from _z_c where item = current_setting('z.pitem') limit 1), ''), true);
-- s = titular "limpo" (ativo, sem FK, não sócio, ninguém aponta para ele)
select set_config('z.s', coalesce((select a.id::text from public.thb_alunos a where a.cancelado_em is null and a.socio_de_aluno_id is null
   and not a.eh_socio and not exists (select 1 from public.thb_alunos b where b.socio_de_aluno_id = a.id) order by a.id limit 1), ''), true);
-- w = sócio ativo com FK para um titular ativo y (y ≠ w)
select set_config('z.w', coalesce((select x.id::text from public.thb_alunos x join public.thb_alunos y on y.id = x.socio_de_aluno_id
   where x.cancelado_em is null and y.cancelado_em is null and x.socio_de_aluno_id <> x.id
     and x.id::text not in (current_setting('z.pa'), current_setting('z.pb'))
     and y.id::text not in (current_setting('z.pa'), current_setting('z.pb')) order by x.id limit 1), ''), true);
select set_config('z.y', coalesce((select socio_de_aluno_id::text from public.thb_alunos where id = nullif(current_setting('z.w'), '')::uuid), ''), true);
select pg_temp.z_q('1.casos', $q$select current_setting('z.pitem') <> '' tem_par, current_setting('z.s') <> '' tem_s,
  current_setting('z.w') <> '' tem_w, current_setting('z.y') <> '' tem_y$q$);

select pg_temp.z_err('1.self', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.s'), '')::uuid, nullif(current_setting('z.s'), '')::uuid)$q$);
-- titular escolhido (w) é sócio de outro (y ≠ s)
select pg_temp.z_err('1.titular_e_socio', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.s'), '')::uuid, nullif(current_setting('z.w'), '')::uuid)$q$);
-- y tem sócio (w); fazer y sócio de s criaria cadeia w → y → s
select pg_temp.z_err('1.socio_com_socios', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.y'), '')::uuid, nullif(current_setting('z.s'), '')::uuid)$q$);
select pg_temp.z_q('1.recusas_sem_efeito', $q$select count(*) from public.thb_alunos_audit_log where origem = 'conciliacao_tela'$q$);

-- par mútuo resolvido numa chamada: pb vira sócio de pa
select pg_temp.z_err('1.par_resolve', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.pb'), '')::uuid, nullif(current_setting('z.pa'), '')::uuid)$q$);
select pg_temp.z_q('1.par_depois', $q$select case when a.id::text = current_setting('z.pa') then 'titular' else 'socio' end papel,
  a.socio_de_aluno_id::text = current_setting('z.pa') fk_para_titular, a.socio_de_aluno_id is null fk_nula, a.eh_socio,
  a.atualizado_por::text = current_setting('z.eq') atualizado_por_ok
  from public.thb_alunos a where a.id::text in (current_setting('z.pa'), current_setting('z.pb')) order by 1 desc$q$);
select pg_temp.z_q('1.par_mutuos', $q$select count(*) from public.thb_alunos x join public.thb_alunos y on y.id = x.socio_de_aluno_id and y.socio_de_aluno_id = x.id
  where x.id::text in (current_setting('z.pa'), current_setting('z.pb'))$q$);
select pg_temp.z_q('1.par_audit', $q$select campo, valor_anterior is not null tinha, valor_novo, count(*) from public.thb_alunos_audit_log
  where origem = 'conciliacao_tela' and aluno_id::text in (current_setting('z.pa'), current_setting('z.pb')) group by 1, 2, 3 order by 1, 2, 3$q$);
select pg_temp.z_q('1.par_item_aberto', $q$select count(*) from public.fn_aluno_conciliacao(null, false) where item = current_setting('z.pitem')$q$);
-- mútuo direto (fora da função) segue barrado pela trava da 20261003b
select pg_temp.z_err('1.mutuo_direto', $q$update public.thb_alunos set socio_de_aluno_id = nullif(current_setting('z.pb'), '')::uuid
  where id = nullif(current_setting('z.pa'), '')::uuid and current_setting('z.pb') <> ''$q$);
-- inverter a decisão (pa vira sócio de pb): a função limpa pb antes; nunca nasce mútuo
select pg_temp.z_err('1.flip', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.pa'), '')::uuid, nullif(current_setting('z.pb'), '')::uuid)$q$);
select pg_temp.z_q('1.flip_depois', $q$select
  (select count(*) from public.thb_alunos x join public.thb_alunos y on y.id = x.socio_de_aluno_id and y.socio_de_aluno_id = x.id
    where x.id::text in (current_setting('z.pa'), current_setting('z.pb'))) mutuos,
  (select socio_de_aluno_id::text = current_setting('z.pb') from public.thb_alunos where id::text = current_setting('z.pa')) pa_socio_de_pb$q$);
select pg_temp.z_err('1.vira_titular', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.pa'), '')::uuid, null)$q$);
select pg_temp.z_q('1.vira_titular_depois', $q$select socio_de_aluno_id is null fk_nula, eh_socio from public.thb_alunos where id::text = current_setting('z.pa')$q$);
select pg_temp.z_q('1.audit_tela_total', $q$select count(*) from public.thb_alunos_audit_log where origem = 'conciliacao_tela'$q$);

-- ─── 2. Marcar / desmarcar ──────────────────────────────────────────────────────────────────────────────────────────
-- i1, i2 = itens abertos de tipos que o passo 1 não mexe (fora vínculo), de alunos fora do par
select set_config('z.i1', coalesce((select item from _z_c where grupo in ('cadastro', 'programa', 'identidade') and tipo <> 'possivel_duplicado'
   and coalesce(aluno_id::text, '') not in (current_setting('z.pa'), current_setting('z.pb')) order by item limit 1), ''), true);
select set_config('z.i2', coalesce((select item from _z_c where grupo in ('cadastro', 'programa', 'identidade') and tipo <> 'possivel_duplicado'
   and coalesce(aluno_id::text, '') not in (current_setting('z.pa'), current_setting('z.pb')) and item <> current_setting('z.i1')
   order by item limit 1), ''), true);
select pg_temp.z_set('2.marcar_id', 'z.d1', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i1'), 'conferido', 'ENSAIO 20261003f')::text$q$);
select pg_temp.z_q('2.marcar_tipo_retorno', $q$select pg_get_function_result('public.fn_aluno_conciliacao_marcar(text,text,text)'::regprocedure)$q$);
select pg_temp.z_q('2.marcado_aberto', $q$select count(*) from public.fn_aluno_conciliacao(null, false) where item = current_setting('z.i1')$q$);
select pg_temp.z_q('2.marcado_conferidos', $q$select conferido, decisao_id = nullif(current_setting('z.d1'), '')::bigint bate, count(*)
  from public.fn_aluno_conciliacao(null, true) where item = current_setting('z.i1') group by 1, 2$q$);
select pg_temp.z_q('2.marcado_linha', $q$select tipo, decisao, observacao, decidido_por::text = current_setting('z.eq') autor_ok, revertido_em is null vigente
  from public.thb_aluno_conciliacao_decisao where id = nullif(current_setting('z.d1'), '')::bigint$q$);
select pg_temp.z_err('2.marcar_de_novo', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i1'), 'conferido', null)$q$);
select pg_temp.z_err('2.marcar_inventado', $q$select public.fn_aluno_conciliacao_marcar(md5('inventado'), 'conferido', null)$q$);
select pg_temp.z_err('2.decisao_invalida', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i2'), 'apagar', null)$q$);
select pg_temp.z_err('2.decisao_incompativel', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i2'), 'pessoas_diferentes', null)$q$);
select pg_temp.z_err('2.decisao_incompativel_acesso', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i2'), 'manter_sem_acesso', null)$q$);
select pg_temp.z_err('2.desmarcar', $q$select public.fn_aluno_conciliacao_desmarcar(nullif(current_setting('z.d1'), '')::bigint)$q$);
select pg_temp.z_q('2.desmarcado_aberto', $q$select count(*), count(*) filter (where decisao_id is null) sem_decisao
  from public.fn_aluno_conciliacao(null, false) where item = current_setting('z.i1')$q$);
select pg_temp.z_q('2.desmarcado_linha', $q$select revertido_em is not null revertido, revertido_por::text = current_setting('z.eq') autor_ok
  from public.thb_aluno_conciliacao_decisao where id = nullif(current_setting('z.d1'), '')::bigint$q$);
select pg_temp.z_err('2.desmarcar_de_novo', $q$select public.fn_aluno_conciliacao_desmarcar(nullif(current_setting('z.d1'), '')::bigint)$q$);
select pg_temp.z_err('2.desmarcar_inexistente', $q$select public.fn_aluno_conciliacao_desmarcar(-1)$q$);
-- decisões específicas nos tipos certos (se houver item aberto do tipo)
select pg_temp.z_set('2.pessoas_diferentes', 'z.d2', $q$select public.fn_aluno_conciliacao_marcar(
  (select item from _z_c where tipo = 'possivel_duplicado' order by item limit 1), 'pessoas_diferentes', 'ENSAIO 20261003f')::text$q$);
select pg_temp.z_set('2.manter_sem_acesso', 'z.d3', $q$select public.fn_aluno_conciliacao_marcar(
  (select item from _z_c where tipo = 'revogado_com_vigencia' order by item limit 1), 'manter_sem_acesso', 'ENSAIO 20261003f')::text$q$);
-- dado muda → item volta: sócio que diverge do titular no plano; conferir e depois trocar o plano do sócio
select set_config('z.i3', coalesce((select item from _z_c where tipo = 'socio_diverge_titular' and detalhe->'campos' ? 'plano'
   and aluno_id::text not in (current_setting('z.pa'), current_setting('z.pb'))
   and ref_aluno_id::text not in (current_setting('z.pa'), current_setting('z.pb')) order by item limit 1), ''), true);
select set_config('z.x3', coalesce((select aluno_id::text from _z_c where item = current_setting('z.i3') limit 1), ''), true);
select pg_temp.z_set('2.muda_dado_marcar', 'z.d4', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i3'), 'conferido', 'ENSAIO 20261003f')::text$q$);
update public.thb_alunos x
   set plano = (select p from unnest(array['aluno', 'diamante', 'platina', 'super_diamante', 'aurum']) p
                 where p <> x.plano and p <> (select y.plano from public.thb_alunos y where y.id = x.socio_de_aluno_id) limit 1)
 where x.id = nullif(current_setting('z.x3'), '')::uuid;
select pg_temp.z_q('2.muda_dado', $q$select current_setting('z.i3') <> '' tem_caso,
  (select count(*) from public.fn_aluno_conciliacao(null, false) where item = current_setting('z.i3')) item_antigo_aberto,
  (select count(*) from public.fn_aluno_conciliacao(null, false)
    where tipo = 'socio_diverge_titular' and aluno_id = nullif(current_setting('z.x3'), '')::uuid) item_novo_aberto$q$);

-- ─── 3. Referência sob clique (só contagem: nenhum nome/e-mail no resultado do ensaio) ─────────────────────────────
create temp table _z_c2 on commit drop as select * from public.fn_aluno_conciliacao(null, false);
select pg_temp.z_q('3.ref_aberto', $q$select t.tipo, x.n, x.nomes, x.emails, x.produtos, x.datas, x.valores
  from (select distinct on (tipo) tipo, item from _z_c2
         where tipo in ('comprou_fora_da_base', 'comprou_em_ativacao', 'sip_sem_aluno', 'placa_sem_aluno') order by tipo, item) t
  cross join lateral (select count(*) n, count(r.nome) nomes, count(r.email) emails, count(r.produto) produtos,
                             count(r.data) datas, count(r.valor) valores from public.fn_aluno_conciliacao_ref(t.item) r) x
  order by 1$q$);
select pg_temp.z_q('3.ref_inventado', $q$select count(*) from public.fn_aluno_conciliacao_ref(md5('inventado'))$q$);
select pg_temp.z_q('3.ref_outro_tipo', $q$select count(*) from public.fn_aluno_conciliacao_ref(current_setting('z.i2'))$q$);
select set_config('z.i4', coalesce((select item from _z_c2 where tipo in ('comprou_fora_da_base', 'comprou_em_ativacao', 'sip_sem_aluno', 'placa_sem_aluno')
   order by item limit 1), ''), true);
select pg_temp.z_set('3.ref_fecha', 'z.d5', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i4'), 'conferido', 'ENSAIO 20261003f')::text$q$);
select pg_temp.z_q('3.ref_fechado', $q$select current_setting('z.i4') <> '' tem_caso, count(*) from public.fn_aluno_conciliacao_ref(current_setting('z.i4'))$q$);

-- ─── 4. Custo (dentro da transação: o marcar do explain grava e é desfeito no rollback) ─────────────────────────────
select pg_temp.z_explain_s('4.explain_marcar', $q$select public.fn_aluno_conciliacao_marcar('$q$ || current_setting('z.i2') || $q$', 'conferido', 'ENSAIO explain')$q$);
select pg_temp.z_explain_s('4.explain_ref', $q$select count(*) from public.fn_aluno_conciliacao_ref('$q$ || current_setting('z.i4') || $q$')$q$);
select pg_temp.z_explain_s('4.explain_definir', $q$select public.fn_aluno_definir_titular('$q$ || coalesce(nullif(current_setting('z.s'), ''), gen_random_uuid()::text) || $q$'::uuid, null)$q$);

-- ─── 5. Permissões ──────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('5.grants', $q$select f, r, has_function_privilege(r, f, 'execute') from unnest(array['public.fn_aluno_definir_titular(uuid,uuid)',
  'public.fn_aluno_conciliacao_marcar(text,text,text)', 'public.fn_aluno_conciliacao_desmarcar(bigint)', 'public.fn_aluno_conciliacao_ref(text)']) f,
  unnest(array['anon', 'authenticated']) r order by 1, 2$q$);
-- anon
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select pg_temp.z_err('5.anon_definir', $q$select public.fn_aluno_definir_titular(gen_random_uuid(), null)$q$);
select pg_temp.z_err('5.anon_marcar', $q$select public.fn_aluno_conciliacao_marcar('x', 'conferido', null)$q$);
select pg_temp.z_err('5.anon_desmarcar', $q$select public.fn_aluno_conciliacao_desmarcar(1)$q$);
select pg_temp.z_err('5.anon_ref', $q$select count(*) from public.fn_aluno_conciliacao_ref('x')$q$);
reset role;
-- authenticated sem perfil (uuid inexistente: não é equipe nem editor)
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
select pg_temp.z_err('5.fora_definir', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.s'), '')::uuid, null)$q$);
select pg_temp.z_err('5.fora_marcar', $q$select public.fn_aluno_conciliacao_marcar(current_setting('z.i2'), 'conferido', null)$q$);
select pg_temp.z_err('5.fora_desmarcar', $q$select public.fn_aluno_conciliacao_desmarcar(nullif(current_setting('z.d4'), '')::bigint)$q$);
select pg_temp.z_err('5.fora_ref', $q$select count(*) from public.fn_aluno_conciliacao_ref(current_setting('z.i4'))$q$);
-- authenticated de equipe: a função passa; a tabela direto não
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select pg_temp.z_err('5.equipe_definir_ok', $q$select public.fn_aluno_definir_titular(nullif(current_setting('z.s'), '')::uuid, null)$q$);
select pg_temp.z_err('5.equipe_direto_select', 'select count(*) from public.thb_aluno_conciliacao_decisao');
select pg_temp.z_err('5.equipe_direto_update', 'update public.thb_aluno_conciliacao_decisao set revertido_em = now()');
select pg_temp.z_err('5.equipe_direto_insert', $q$insert into public.thb_aluno_conciliacao_decisao (item, tipo, decisao) values ('x', 'x', 'conferido')$q$);
reset role;

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003f',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
