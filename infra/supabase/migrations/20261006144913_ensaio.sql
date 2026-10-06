-- 20261006144913: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006144913_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006144913_pa_socio_novo_entrada.sql; se a
-- migration mudar, gerar de novo). Depois do corpo: titular ZZ (entrada 10/01/2025, turma 54) com dois sócios; dois
-- pedidos de troca aprovados pela pa_decidir como o Victor (JWT simulado):
--   n1 entra PESSOA NOVA (CPF de teste válido, e-mail @exemplo.invalid) -> herda entrada e turma do titular
--   n2 entra pessoa EXISTENTE com entrada e turma próprias              -> não muda (controle)
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select (select count(*) from public.thb_alunos where fonte = 'ensaio_20261006144913' or email like 'zz.144913.%') alunos_zz,
--        (select max(id) from public.pa_pedidos) max_pedido,
--        md5(pg_get_functiondef('public.pa_decidir(bigint,text,text,jsonb,boolean)'::regprocedure)) = 'b574c318913596f5706025807b3a4f23' decidir_igual;

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

-- ═══ CORPO DA MIGRATION (cópia sem mudança) ═══

-- ═══ 0. Guarda: o banco tem que estar como foi lido em 06/10/2026 ═══
do $guarda$
begin
  if md5(pg_get_functiondef('public.pa_decidir(bigint,text,text,jsonb,boolean)'::regprocedure)) <> 'b574c318913596f5706025807b3a4f23' then
    raise exception '20261006144913: corpo vivo de pa_decidir mudou desde 06/10/2026 (md5 diferente): reler e regerar';
  end if;
end
$guarda$;

-- ═══ 1. pa_decidir: pessoa nova herda data_entrada_thb e turma_id do titular ═══
CREATE OR REPLACE FUNCTION public.pa_decidir(p_pedido bigint, p_decisao text, p_motivo_recusa text DEFAULT NULL::text, p_valor_ajustado jsonb DEFAULT NULL::jsonb, p_confirmar_conflito boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_por uuid;
  r public.pa_pedidos%rowtype;
  v_origem text;
  v_agora jsonb;
  v_novo jsonb;
  v_t public.thb_alunos%rowtype;
  v_s2 uuid;
  v_nivel text;
  v_num int;
  v_caso uuid;
  v_k text;
  v_n int := 0;
  v_status_final text;
  v_sn jsonb;
  v_end jsonb;
  v_doc text;
begin
  if not public.pa_eh_aprovador() then
    return json_build_object('ok', false, 'msg', 'Só o aprovador decide pedidos de alteração.');
  end if;
  v_por := (select p.id from public.perfis p where p.id = v_uid);
  select * into r from public.pa_pedidos where id = p_pedido for update;
  if not found then return json_build_object('ok', false, 'msg', 'Pedido não encontrado.'); end if;
  if r.status not in ('pendente', 'erro') then
    return json_build_object('ok', false, 'msg', 'Este pedido já foi decidido.');
  end if;
  v_origem := 'pedido_alteracao:' || r.id;

  if p_decisao = 'recusar' then
    if length(btrim(coalesce(p_motivo_recusa, ''))) < 3 then
      return json_build_object('ok', false, 'msg', 'Informe o motivo da recusa.');
    end if;
    update public.pa_pedidos
       set status = 'recusado', decidido_por = v_uid, decidido_em = now(),
           motivo_recusa = left(btrim(p_motivo_recusa), 2000), erro_msg = null
     where id = r.id;
    insert into public.pa_historico (pedido_id, acao, por, detalhe)
    values (r.id, 'recusado', v_uid, jsonb_build_object('motivo', btrim(p_motivo_recusa)));
    return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' recusado.');
  elsif p_decisao <> 'aprovar' then
    return json_build_object('ok', false, 'msg', 'Decisão inválida.');
  end if;

  -- outro: não há o que aplicar automaticamente.
  if r.tipo = 'outro' then
    update public.pa_pedidos set status = 'aprovado', decidido_por = v_uid, decidido_em = now(), erro_msg = null where id = r.id;
    insert into public.pa_historico (pedido_id, acao, por) values (r.id, 'aprovado', v_uid);
    return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' aprovado. Faça a alteração e marque como aplicado.');
  end if;

  if r.aluno_id is null then
    return json_build_object('ok', false, 'msg', 'O aluno deste pedido não existe mais na base.');
  end if;

  begin
    if r.tipo = 'alterar_dado' then
      perform 1 from public.thb_alunos a where a.id = r.aluno_id and a.cancelado_em is null for update;
      if not found then raise exception 'O aluno deste pedido foi cancelado ou removido.' using errcode = '22023'; end if;
      v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
      if v_agora is distinct from r.valor_atual and not coalesce(p_confirmar_conflito, false) then
        return json_build_object('ok', false, 'conflito', true,
          'agora', public.pa_exibir(r.campo, v_agora, public.pa_pode_ver_doc()),
          'msg', 'O valor mudou desde o pedido. Confira e confirme para aplicar mesmo assim.');
      end if;
      v_novo := public.pa_normalizar(r.campo,
                  case when p_valor_ajustado is null then r.valor_novo
                       when r.campo = 'endereco' and jsonb_typeof(p_valor_ajustado) = 'object' then r.valor_novo || p_valor_ajustado
                       else p_valor_ajustado end);
      if r.campo = 'email' and exists (select 1 from public.thb_alunos o
                                        where o.id <> r.aluno_id and lower(btrim(o.email)) = lower(public.pa_txt(v_novo))) then
        raise exception 'Esse e-mail já é de outro aluno na base.' using errcode = '22023';
      end if;
      if r.campo = 'endereco' then
        foreach v_k in array public.pa_colunas_endereco() loop
          if public.pa_set_coluna(r.aluno_id, v_k, v_novo ->> v_k, v_origem, v_por) then v_n := v_n + 1; end if;
        end loop;
      else
        -- O e-mail antigo fica no audit (valor_anterior) e no próprio pedido (valor_atual), para achar a compra antiga.
        if public.pa_set_coluna(r.aluno_id, r.campo, public.pa_txt(v_novo), v_origem, v_por) then v_n := v_n + 1; end if;
      end if;
      update public.pa_pedidos
         set status = 'aplicado', decidido_por = v_uid, decidido_em = now(), aplicado_em = now(),
             valor_aplicado = v_novo, conflito_confirmado = (v_agora is distinct from r.valor_atual),
             planilha_status = 'pendente', erro_msg = null
       where id = r.id;

    else -- trocar_socio
      -- Trava as linhas envolvidas em ordem de id (dois aprovadores ao mesmo tempo não se travam).
      perform 1 from public.thb_alunos a
       where a.id in (r.aluno_id, r.socio_sai_id, coalesce(r.socio_entra_id, r.aluno_id))
       order by a.id for update;
      select * into v_t from public.thb_alunos where id = r.aluno_id and cancelado_em is null;
      if not found then raise exception 'O titular foi cancelado ou removido.' using errcode = '22023'; end if;
      if v_t.socio_de_aluno_id is not null or coalesce(v_t.eh_socio, false) then
        raise exception 'O titular virou sócio de alguém depois do pedido. Recuse e peça de novo.' using errcode = '22023';
      end if;
      if r.socio_sai_id is null or not exists (select 1 from public.thb_alunos where id = r.socio_sai_id) then
        raise exception 'O sócio que sai não existe mais na base.' using errcode = '22023';
      end if;
      v_agora := jsonb_build_object('socio_sai_vinculado', public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id));
      if not (v_agora ->> 'socio_sai_vinculado')::boolean and not coalesce(p_confirmar_conflito, false) then
        return json_build_object('ok', false, 'conflito', true, 'agora', 'O sócio que sai já não está vinculado a este titular.',
          'msg', 'O vínculo mudou desde o pedido. Confira e confirme para aplicar mesmo assim.');
      end if;

      v_nivel := public.pa_instrucao_canonica(v_t.instrucao, v_t.espaco_instrucao, false);
      if v_nivel is null then
        raise exception 'O titular está sem instrução e sem espaço: não dá para definir a instrução do sócio.' using errcode = '22023';
      end if;

      -- 1) Sai: só perde o vínculo. O acesso é tirado pelo caso de Remoção.
      perform public.pa_set_coluna(r.socio_sai_id, 'socio_de_aluno_id', null, v_origem, v_por);
      perform public.pa_set_coluna(r.socio_sai_id, 'socio_de_nome', null, v_origem, v_por);

      -- 2) Entra: existente ou novo.
      if r.socio_entra_id is not null then
        v_s2 := r.socio_entra_id;
        if not exists (select 1 from public.thb_alunos where id = v_s2 and cancelado_em is null) then
          raise exception 'O sócio que entra foi cancelado ou removido.' using errcode = '22023';
        end if;
        if exists (select 1 from public.thb_alunos where id = v_s2 and socio_de_aluno_id is not null and socio_de_aluno_id <> v_t.id) then
          raise exception 'O sócio que entra virou sócio de outro titular depois do pedido.' using errcode = '22023';
        end if;
        if exists (select 1 from public.thb_alunos o where o.socio_de_aluno_id = v_s2 and o.cancelado_em is null) then
          raise exception 'O sócio que entra é titular de outros sócios.' using errcode = '22023';
        end if;
      else
        if exists (select 1 from public.thb_alunos o where lower(btrim(o.email)) = lower(r.socio_entra_novo ->> 'email')) then
          raise exception 'O e-mail do sócio novo já entrou na base depois do pedido: recuse e peça com o sócio existente.' using errcode = '22023';
        end if;
        -- 20261005k: cadastro completo. Endereço = o do pedido (foto; "mantido" já é a cópia de quem saiu na hora do
        -- pedido). Pedido antigo sem endereço: colunas nulas e país 'Brasil' (default da coluna).
        v_sn := r.socio_entra_novo;
        v_end := case when jsonb_typeof(v_sn -> 'endereco') = 'object' then v_sn -> 'endereco' else '{}'::jsonb end;
        v_doc := nullif(regexp_replace(coalesce(v_sn ->> 'documento', ''), '\D', '', 'g'), '');
        if v_doc is not null and exists (select 1 from public.thb_alunos o
                                          where regexp_replace(coalesce(o.documento, ''), '\D', '', 'g') = v_doc) then
          raise exception 'O CPF/CNPJ do sócio novo já entrou na base depois do pedido: recuse e peça com o sócio existente.' using errcode = '22023';
        end if;
        insert into public.thb_alunos (nome, email, telefone, documento, tipo_documento, profissao,
                                       cep, endereco_logradouro, endereco_numero, endereco_complemento, bairro, cidade,
                                       estado, pais, fonte, atualizado_em, atualizado_por)
        values (v_sn ->> 'nome', v_sn ->> 'email', v_sn ->> 'telefone', v_doc,
                coalesce(v_sn ->> 'tipo_documento', case length(v_doc) when 11 then 'CPF' when 14 then 'CNPJ' end),
                public.pa_txt(v_sn -> 'profissao'),
                public.pa_txt(v_end -> 'cep'), public.pa_txt(v_end -> 'endereco_logradouro'),
                public.pa_txt(v_end -> 'endereco_numero'), public.pa_txt(v_end -> 'endereco_complemento'),
                public.pa_txt(v_end -> 'bairro'), public.pa_txt(v_end -> 'cidade'), public.pa_txt(v_end -> 'estado'),
                coalesce(public.pa_txt(v_end -> 'pais'), 'Brasil'),
                'pedido_alteracao', now(), v_por)
        returning id into v_s2;
        update public.pa_pedidos set socio_entra_id = v_s2 where id = r.id;
        -- 20261006144913: pessoa nova herda do titular a entrada no THB e a turma (decisão do Victor, 06/10/2026).
        -- Com auditoria, como as demais colunas; titular sem a informação deixa a coluna nula (pa_set_coluna é no-op).
        perform public.pa_set_coluna(v_s2, 'data_entrada_thb', v_t.data_entrada_thb::text, v_origem, v_por);
        perform public.pa_set_coluna(v_s2, 'turma_id', v_t.turma_id::text, v_origem, v_por);
      end if;
      perform public.pa_set_coluna(v_s2, 'eh_socio', 'true', v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'socio_de_aluno_id', v_t.id::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'socio_de_nome', v_t.nome, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'instrucao', v_nivel || ' - SÓCIO', v_origem, v_por);
      if v_t.espaco_instrucao is not null then
        perform public.pa_set_coluna(v_s2, 'espaco_instrucao', v_t.espaco_instrucao, v_origem, v_por);
      end if;
      perform public.pa_set_coluna(v_s2, 'data_expiracao', v_t.data_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'mes_expiracao', v_t.mes_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'ano_expiracao', v_t.ano_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'regra_acesso', 'Acompanha titular', v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'status_acesso_central', 'Acompanha titular', v_origem, v_por);

      -- 3) Titular: recontagem de sócios.
      v_num := public.pa_contar_socios(v_t.id);
      perform public.pa_set_coluna(v_t.id, 'num_socios', v_num::text, v_origem, v_por);

      -- 4) Caso de Remoção para quem saiu.
      v_caso := public.pa_abrir_caso_remocao(r.id, r.socio_sai_id, v_t.nome);

      update public.pa_pedidos
         set status = 'aplicado', decidido_por = v_uid, decidido_em = now(), aplicado_em = now(),
             valor_aplicado = jsonb_build_object('socio_sai_id', r.socio_sai_id, 'socio_entra_id', v_s2,
                                                 'instrucao', v_nivel || ' - SÓCIO', 'num_socios', v_num,
                                                 'socio_novo', r.socio_entra_id is null,
                                                 'endereco_mantido', coalesce((r.socio_entra_novo ->> 'endereco_mantido')::boolean, false)),
             conflito_confirmado = not (v_agora ->> 'socio_sai_vinculado')::boolean,
             ra_caso_id = v_caso, planilha_status = 'pendente', erro_msg = null
       where id = r.id;
      insert into public.pa_historico (pedido_id, acao, por, detalhe)
      values (r.id, 'caso_remocao_aberto', v_uid, jsonb_build_object('caso', v_caso, 'socio', r.socio_sai_id));
    end if;

    insert into public.pa_historico (pedido_id, acao, por, detalhe)
    values (r.id, 'aplicado', v_uid, jsonb_build_object('ajustado', p_valor_ajustado is not null,
                                                        'conflito_confirmado', coalesce(p_confirmar_conflito, false),
                                                        'colunas', v_n));
  exception
    when sqlstate '22023' then
      -- Validação: nada foi gravado, o pedido segue como estava para o aprovador ajustar ou recusar.
      return json_build_object('ok', false, 'msg', sqlerrm);
    when others then
      update public.pa_pedidos set status = 'erro', erro_msg = left(sqlerrm, 500) where id = r.id;
      insert into public.pa_historico (pedido_id, acao, por, detalhe)
      values (r.id, 'erro', v_uid, jsonb_build_object('sqlstate', sqlstate, 'msg', sqlerrm));
      return json_build_object('ok', false, 'msg', 'Erro ao aplicar (nada foi gravado no aluno): ' || sqlerrm);
  end;

  select status into v_status_final from public.pa_pedidos where id = r.id;
  return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' aplicado.'
    || case when v_caso is not null then ' Caso de Remoção de Acessos aberto para o sócio que saiu.' else '' end,
    'status', v_status_final, 'ra_caso_id', v_caso);
end
$function$;

-- ═══ 2. Conferência: grants iguais aos de antes (create or replace não mexe neles) ═══
do $confere$
begin
  if not has_function_privilege('authenticated', 'public.pa_decidir(bigint,text,text,jsonb,boolean)', 'execute')
     or has_function_privilege('anon', 'public.pa_decidir(bigint,text,text,jsonb,boolean)', 'execute') then
    raise exception '20261006144913: grants de pa_decidir mudaram';
  end if;
  if position('''data_entrada_thb''' in pg_get_functiondef('public.pa_decidir(bigint,text,text,jsonb,boolean)'::regprocedure)) = 0 then
    raise exception '20261006144913: pa_decidir sem a herança de data_entrada_thb';
  end if;
end
$confere$;

-- ═══ ENSAIO: testes ════════════════════════════════════════════════════════════════════════════════════════════════
insert into public.thb_alunos (id, nome, email, instrucao, espaco_instrucao, data_expiracao, mes_expiracao, ano_expiracao,
                               num_socios, fonte, data_entrada_thb, turma_id)
values ('e0000000-0000-4000-8000-0000000144c0', 'ZZ Ensaio 144913 Titular', 'zz.144913.titular@exemplo.invalid',
        'AURUM', 'aurum', '2027-03-31', 3, 2027, 2, 'ensaio_20261006144913', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144c1', 'ZZ Ensaio 144913 Sai 1', 'zz.144913.sai1@exemplo.invalid',
        'AURUM - SÓCIO', 'aurum', '2027-03-31', 3, 2027, null, 'ensaio_20261006144913', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144c2', 'ZZ Ensaio 144913 Sai 2', 'zz.144913.sai2@exemplo.invalid',
        'AURUM - SÓCIO', 'aurum', '2027-03-31', 3, 2027, null, 'ensaio_20261006144913', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144d2', 'ZZ Ensaio 144913 Existente', 'zz.144913.existente@exemplo.invalid',
        'THB', 'holding_masters', null, null, null, null, 'ensaio_20261006144913', '2024-05-05', 55);
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000000144c0',
       socio_de_nome = 'ZZ Ensaio 144913 Titular'
 where id in ('e0000000-0000-4000-8000-0000000144c1', 'e0000000-0000-4000-8000-0000000144c2');

create temp table _p (k text primary key, criar jsonb, decidir jsonb) on commit drop;
-- n1 (pessoa nova) é gravado direto em pa_pedidos, no mesmo formato da pa_criar (mesmas funções de normalização),
-- porque o documento do sócio novo é um CPF que FALHA no dígito verificador (484.621.880-58): assim o ensaio nunca usa
-- CPF que possa ser de alguém, e a pa_criar recusaria esse CPF. A pa_decidir só confere duplicidade de documento.
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, campo, valor_atual, valor_novo, socio_sai_id, socio_sai_nome,
                                 socio_entra_id, socio_entra_nome, socio_entra_novo, descricao, motivo, evidencia, solicitado_por)
  select 'trocar_socio', t.id, t.nome, null, jsonb_build_object('socio_sai_vinculado', true, 'num_socios', t.num_socios), null,
         s.id, s.nome, null, 'ZZ Ensaio 144913 Novo',
         jsonb_build_object('nome', 'ZZ Ensaio 144913 Novo', 'email', 'zz.144913.novo@exemplo.invalid',
           'telefone', public.pa_telefone_pessoa('(21) 97777-0013', true), 'documento', '48462188058', 'tipo_documento', 'CPF',
           'profissao', 'Contadora', 'endereco_mantido', false,
           'endereco', public.pa_endereco('{"pais":"Brasil","cep":"20040-020","endereco_logradouro":"Av. Ensaio",
             "endereco_numero":"1","bairro":"Centro","cidade":"Rio de Janeiro","estado":"RJ"}'::jsonb, true)),
         null, 'ensaio da migration 20261006144913', null, '81d2eaee-cce1-4058-8714-439b0fc6f970'
    from public.thb_alunos t, public.thb_alunos s
   where t.id = 'e0000000-0000-4000-8000-0000000144c0' and s.id = 'e0000000-0000-4000-8000-0000000144c1'
  returning id),
hist as (
  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  select id, 'criado', '81d2eaee-cce1-4058-8714-439b0fc6f970', '{"tipo":"trocar_socio","campo":null}'::jsonb from ins)
insert into _p (k, criar) select 'n1', jsonb_build_object('ok', true, 'numero', id) from ins;
insert into _p (k, criar) values
 ('n2', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"trocar_socio",
   "aluno_id":"e0000000-0000-4000-8000-0000000144c0","socio_sai_id":"e0000000-0000-4000-8000-0000000144c2",
   "socio_entra_id":"e0000000-0000-4000-8000-0000000144d2","motivo":"ensaio da migration 20261006144913"}''::jsonb)::jsonb'));
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint)) where k = 'n1';
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint)) where k = 'n2';
select pg_temp.ok('1.pedido_' || k, (decidir ->> 'ok')::boolean,
  coalesce(decidir ->> 'msg', decidir ->> 'erro', criar ->> 'msg', criar ->> 'erro')) from _p order by k;

-- 2. Pessoa nova: entrada e turma iguais às do titular, com auditoria.
select pg_temp.ok('2.novo_herda',
  a.data_entrada_thb = t.data_entrada_thb and a.turma_id = t.turma_id and a.socio_de_aluno_id = t.id
  and a.fonte = 'pedido_alteracao',
  'novo: entrada=' || coalesce(a.data_entrada_thb::text, 'nula') || ' turma=' || coalesce(a.turma_id::text, 'nula')
  || ' (' || coalesce((select codigo from public.thb_turmas where id = a.turma_id), 'sem turma') || ')'
  || ' | titular: entrada=' || t.data_entrada_thb || ' turma=' || t.turma_id || ' | instrucao=' || a.instrucao)
  from public.thb_alunos a, public.thb_alunos t
 where a.email = 'zz.144913.novo@exemplo.invalid' and t.id = 'e0000000-0000-4000-8000-0000000144c0';
select pg_temp.ok('2.novo_auditoria',
  (select string_agg(l.campo || '=' || l.valor_novo, ', ' order by l.campo) from public.thb_alunos_audit_log l
    where l.aluno_id = (select id from public.thb_alunos where email = 'zz.144913.novo@exemplo.invalid')
      and l.campo in ('data_entrada_thb', 'turma_id') and l.origem = 'pedido_alteracao:' || (select criar ->> 'numero' from _p where k = 'n1'))
  = 'data_entrada_thb=2025-01-10, turma_id=54',
  coalesce((select string_agg(l.campo || '=' || l.valor_novo || ' (' || l.origem || ')', ', ' order by l.campo)
              from public.thb_alunos_audit_log l
             where l.aluno_id = (select id from public.thb_alunos where email = 'zz.144913.novo@exemplo.invalid')
               and l.campo in ('data_entrada_thb', 'turma_id')), 'sem auditoria'));

-- 3. Pessoa existente: mantém a entrada e a turma dela (a herança é só para pessoa nova).
select pg_temp.ok('3.existente_mantem',
  a.data_entrada_thb = '2024-05-05' and a.turma_id = 55 and a.socio_de_aluno_id = 'e0000000-0000-4000-8000-0000000144c0',
  'existente: entrada=' || a.data_entrada_thb || ' turma=' || a.turma_id || ' (vinculada ao titular)')
  from public.thb_alunos a where a.id = 'e0000000-0000-4000-8000-0000000144d2';

-- 4. Grants
select pg_temp.ok('4.grants',
  has_function_privilege('authenticated', 'public.pa_decidir(bigint,text,text,jsonb,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.pa_decidir(bigint,text,text,jsonb,boolean)', 'execute'),
  'pa_decidir: authenticated sim, anon não');

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
