-- 20261003f — Conciliação da base de alunos: escrita pela tela (desenho 1.6)
--
-- O QUE FAZ (4 funções SECURITY DEFINER, search_path = public, pg_temp; revoke public/anon; grant authenticated)
--   1. public.fn_aluno_definir_titular(p_socio uuid, p_titular uuid) returns void
--      p_titular nulo = p_socio vira titular (FK nula, eh_socio=false). Senão: p_titular ≠ p_socio, os dois ativos,
--      titular sem FK (exceto a FK que aponta para p_socio: é o par mútuo, resolvido aqui na mesma chamada — o titular
--      perde a FK ANTES de o sócio ganhar a dele, e a trava da 20261003b não dispara), nenhum outro ativo aponta para
--      p_socio (senão viraria cadeia). Titular fica eh_socio=false; sócio fica FK=p_titular, eh_socio=true.
--      Lock das duas linhas em ordem de id (sem deadlock entre dois cliques cruzados). atualizado_em/atualizado_por.
--      Audit em thb_alunos_audit_log, origem 'conciliacao_tela', 1 linha por campo que mudou (reversão pelo audit).
--      Guarda = predicado da policy UPDATE viva de thb_alunos: gp_pode_editar('centro_controle') e não usuário SIP.
--   2. public.fn_aluno_conciliacao_marcar(p_item text, p_decisao text, p_obs text) returns bigint (id da decisão)
--      Só aceita item ABERTO agora (lido de fn_aluno_conciliacao(null, false)): item inventado/fechado = 22023.
--      pessoas_diferentes só em possivel_duplicado; manter_sem_acesso só em revogado_com_vigencia; conferido em todos.
--   3. public.fn_aluno_conciliacao_desmarcar(p_id bigint) returns void — revertido_em/revertido_por; nunca DELETE.
--      Decisão inexistente ou já revertida = P0002.
--      Guarda de 2 e 3 = equipe (gp_eh_equipe) E a guarda de escrita de 1.
--   4. public.fn_aluno_conciliacao_ref(p_item text) returns table (fonte, nome, email, produto, data, valor)
--      Leitura sob clique (gp_eh_equipe). SÓ para item aberto dos tipos comprou_fora_da_base, comprou_em_ativacao,
--      sip_sem_aluno, placa_sem_aluno; qualquer outro item (fechado, inventado, de outro tipo) = 0 linhas — sem oráculo
--      sobre os compradores. valor só com gp_pode_ver_financeiro() (senão null). Compra: até 5 pagamentos de programa
--      (regra da 20261003a) dos e-mails da pessoa, mais recentes primeiro.
--
-- AS 5 PERGUNTAS
--   escala: definir_titular toca 2 linhas por PK; marcar/ref leem fn_aluno_conciliacao 1× (≤ 1,5 s medido na e);
--     ref lê fin.vw_transacoes por e-mail (hotmart_transacoes_email_idx, provado na 20261002e).
--   índice: nenhum novo. thb_alunos_pkey; thb_aluno_conciliacao_decisao_vigente_uidx (e); sip.users_pkey; placas_pkey.
--   frequência: 1 chamada por clique (definir, marcar, desfazer, ver comprador). Nada em laço, nada em cron.
--   repetição: "item aberto" = a própria fn_aluno_conciliacao (nenhuma cópia do cálculo de item aqui).
--   reversão: drop das 4 funções (bloco no fim). Dados: decisões por revertido_em; titulares pelo audit_log com
--     origem 'conciliacao_tela' (valor_anterior). Nenhum DELETE.
--
-- ENSAIO: infra/supabase/migrations/20261003f_ensaio.sql.
-- ORDEM: depois de 20261003a–e (lê fn_aluno_conciliacao, fn_aluno_compras_fora_base e a tabela de decisões da e).

set local lock_timeout = '3s';

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

-- ─── REVERSÃO (NÃO executar junto) ────────────────────────────────────────────────────────────────────────────────
-- Funções (a tela para de escrever; a flag NEXT_PUBLIC_ALUNO_CONCILIACAO=off esconde a área antes):
-- drop function if exists public.fn_aluno_conciliacao_ref(text);
-- drop function if exists public.fn_aluno_conciliacao_desmarcar(bigint);
-- drop function if exists public.fn_aluno_conciliacao_marcar(text, text, text);
-- drop function if exists public.fn_aluno_definir_titular(uuid, uuid);
-- Dados de vínculo mudados pela tela: valor_anterior em thb_alunos_audit_log (origem conciliacao_tela), aluno a
-- aluno, na ordem inversa de id (a trava da 20261003b recusa voltar a um par mútuo — é o comportamento esperado).
-- Decisões: fn_aluno_conciliacao_desmarcar / revertido_em. Nenhum DELETE.
