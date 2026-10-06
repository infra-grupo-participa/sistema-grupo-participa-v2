-- 20261006144912: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006144912_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006144912_pa_troca_socio_direto_remocao.sql;
-- se a migration mudar, gerar de novo). ANTES do corpo: foto dos avisos de Slack pendentes dos casos reais (para provar
-- que nada muda para eles). DEPOIS do corpo: 7 alunos ZZ (@exemplo.invalid), três pedidos de troca aprovados pela
-- pa_decidir como o Victor (JWT simulado, role authenticated):
--   p1 sai sem compra própria                  -> direto em remoção
--   p2 sai com Aurum só no financeiro (ZZ…)    -> triagem
--   p3 sai com compra de HM em public.compras  -> triagem (e-mail de um comprador real, lido por subconsulta, nunca impresso)
-- Nada de dado real é impresso: só contagens, status, rótulos e os textos dos casos ZZ.
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select (select count(*) from public.thb_alunos where fonte = 'ensaio_20261006144912') alunos_zz,
--        (select count(*) from public.ra_casos where tipo = 'troca_socio') trocas,
--        (select count(*) from fin.hotmart_transacoes where transacao like 'ZZ144912%') fin_zz,
--        md5(pg_get_functiondef('public.pa_abrir_caso_remocao(bigint,uuid,text)'::regprocedure)) = '640c80606313bc915db85ae23cce9277' abrir_igual;

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

update crm.config set hotmart_ligado = false;  -- o ensaio grava uma linha falsa no financeiro (sócio de p2)

-- Segredo do Slack lido aqui dentro, nunca impresso.
create temp table _s on commit drop as select valor as s from public.ra_config where chave = 'slack_segredo';
create function pg_temp.pend() returns jsonb language sql as $$
  select coalesce((public.ra_slack_pendentes((select s from _s))::jsonb) -> 'mensagens', '[]'::jsonb) $$;
-- Foto ANTES da migration: avisos pendentes dos casos reais.
create temp table _antes_msgs on commit drop as
  select m ->> 'caso_id' caso_id, m ->> 'aviso' aviso, md5(m ->> 'texto') t from jsonb_array_elements(pg_temp.pend()) m;

-- ═══ CORPO DA MIGRATION (cópia sem mudança) ═══
set local lock_timeout = '5s';

-- ═══ 0. Guarda: o banco tem que estar como foi lido em 06/10/2026 ═══
do $guarda$
declare
  v_esperado jsonb := '{
    "public.pa_abrir_caso_remocao(bigint,uuid,text)": "640c80606313bc915db85ae23cce9277",
    "public.ra_slack_pendentes_base(text)": "d96b2f7b323d22b338b2e1aecb6678dd",
    "public.ra_desfazer_triagem(uuid)": "303671aee3c819e29c16cc7b99f2d375"
  }';
  k text; v text;
begin
  for k, v in select * from jsonb_each_text(v_esperado) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v then
      raise exception '20261006144912: corpo vivo de % mudou desde 06/10/2026 (md5 diferente): reler e regerar', k;
    end if;
  end loop;
  if to_regprocedure('public.ra_montar_sugestao(uuid,uuid,text,text,timestamp with time zone)') is null then
    raise exception '20261006144912: ra_montar_sugestao não existe (é a regra da compra própria)';
  end if;
end
$guarda$;

-- ═══ 1. pa_abrir_caso_remocao: sem compra própria, direto em remoção ═══
-- Mesma assinatura e mesmo dono/grants (create or replace mantém postgres e service_role, sem authenticated).
-- Compra própria = a regra da triagem (ra_montar_sugestao: produtos 5064314, 3507214 e 3094405, status
-- APPROVED/COMPLETED/COMPLETE, mesma pessoa por e-mail ou documento, em public.compras) aplicada também ao financeiro
-- da Hotmart (conta academy), porque public.compras só começa em 14/03/2026 e o financeiro guarda desde 2023.
create or replace function public.pa_abrir_caso_remocao(p_pedido bigint, p_socio uuid, p_titular_nome text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_s public.thb_alunos%rowtype;
  v_turma text;
  v_caso uuid;
  v_transacao text := 'PEDIDO-ALTERACAO-' || p_pedido;
  v_email text;
  v_doc text;
  v_compras jsonb;
  v_direto boolean;
  v_programa boolean;
  v_titular text := coalesce(p_titular_nome, 'o titular');
  v_pessoa uuid;
  v_sem_id boolean;
begin
  select * into v_s from public.thb_alunos where id = p_socio;
  select t.codigo into v_turma from public.thb_turmas t where t.id = v_s.turma_id;
  v_programa := coalesce(v_s.espaco_instrucao = 'holding_masters_implementacao', false);

  -- 20261006144912: compra própria do sócio que sai (HM ou Aurum, válida). A lista vai para a ficha da triagem.
  v_email := lower(trim(coalesce(v_s.email, '')));
  v_doc := regexp_replace(coalesce(v_s.documento, ''), '\D', '', 'g');
  v_compras := coalesce(public.ra_montar_sugestao(null, v_s.id, v_s.email, v_s.documento, now()) -> 'compras_anteriores',
                        '[]'::jsonb);
  select v_compras || coalesce(jsonb_agg(jsonb_build_object(
           'transacao', h.transacao, 'produto', h.produto_nome, 'oferta', h.oferta_codigo, 'valor', h.valor_cobrado,
           'status', h.status, 'data', coalesce(h.aprovado_em, h.pedido_em))
           order by coalesce(h.aprovado_em, h.pedido_em), h.transacao), '[]'::jsonb)
    into v_compras
    from (select * from fin.hotmart_transacoes where conta = 'academy') h
   where h.status in ('APPROVED', 'COMPLETED', 'COMPLETE')
     and h.produto_id in ('5064314', '3507214', '3094405')
     and ((v_email <> '' and lower(trim(h.comprador_email)) = v_email)
          or (length(v_doc) >= 11 and regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = v_doc))
     and not exists (select 1 from jsonb_array_elements(v_compras) x where x ->> 'transacao' = h.transacao);
  -- Sem e-mail e sem documento (11+ dígitos) não dá para checar compra própria: vai para a triagem.
  v_sem_id := v_email = '' and length(v_doc) < 11;
  v_direto := jsonb_array_length(v_compras) = 0 and not v_sem_id;

  insert into public.ra_casos (
    compra_id, hotmart_transaction, tipo, status, produto_nome, aluno_id, nome, email, telefone, documento,
    ocorrido_em, prazo_em, eh_programa, sugestao, teste, origem, decisao, linha)
  values (
    null, v_transacao, 'troca_socio',
    case when v_direto then 'em_remocao' else 'aguardando_triagem' end,
    'Troca de sócio (pedido nº ' || p_pedido || ')',
    v_s.id, v_s.nome, v_s.email, v_s.telefone, v_s.documento,
    now(), public.ra_calcular_prazo(now()), v_programa,
    jsonb_build_object(
      'recomendacao', case when v_direto then 'remover' else 'verificar' end,
      'motivo', 'Troca de sócio, pedido nº ' || p_pedido || ': saiu do vínculo com ' || v_titular || '. '
                || case when v_direto
                        then 'Sem compra própria de Holding Masters ou Aurum: entrou direto em remoção, sem triagem.'
                        when v_sem_id
                        then 'Sem e-mail/documento para checar compra própria: conferir antes de remover.'
                        else 'Tem compra própria de Holding Masters ou Aurum: conferir se o acesso dela ainda vale antes de remover.' end,
      'compras_anteriores', v_compras,
      'aluno', jsonb_build_object('instrucao', v_s.instrucao, 'espaco', v_s.espaco_instrucao, 'turma', v_turma,
                                  'data_expiracao', v_s.data_expiracao, 'data_entrada_thb', v_s.data_entrada_thb,
                                  'status_central', v_s.status_acesso_central, 'eh_socio', v_s.eh_socio),
      'historico_expiracao', '[]'::jsonb,
      'aviso', 'Caso aberto pela aprovação de um pedido de alteração de cadastro, não pela Hotmart. Compra própria '
               || 'conferida em public.compras e no financeiro da Hotmart (conta academy).',
      'direto_remocao', v_direto,
      'pedido', p_pedido,
      'titular', p_titular_nome),
    false, 'pedido_alteracao',
    case when v_direto then 'remover' end,
    'hm')
  on conflict (hotmart_transaction, tipo) do nothing
  returning id into v_caso;

  if v_caso is null then
    select id into v_caso from public.ra_casos where hotmart_transaction = v_transacao and tipo = 'troca_socio';
    return v_caso;
  end if;
  insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
  values (v_caso, v_s.id, v_s.nome, v_s.email, 'socio', 0)
  returning id into v_pessoa;

  -- Mesmo filtro do ra_triar com 'remover'.
  if v_direto then
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select v_caso, v_pessoa, c.item, c.responsavel_id
      from public.ra_itens_catalogo c
     where c.ativo and c.fluxo = 'remocao' and c.linha = 'hm' and (not c.so_programa or v_programa)
    on conflict (pessoa_id, item) do nothing;
  end if;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (v_caso, 'aberto', (select p.id from public.perfis p where p.id = (select auth.uid())),
          jsonb_build_object('tipo', 'troca_socio', 'origem', 'pedido_alteracao', 'pedido', p_pedido,
                             'titular', p_titular_nome,
                             'status_inicial', case when v_direto then 'em_remocao' else 'aguardando_triagem' end,
                             'compras_proprias', jsonb_array_length(v_compras),
                             'evento', case when v_direto
                                            then 'direto em remoção pelo pedido nº ' || p_pedido
                                            when v_sem_id
                                            then 'triagem: sem e-mail/documento para checar compra própria (pedido nº ' || p_pedido || ')'
                                            else 'triagem: tem compra própria (pedido nº ' || p_pedido || ')' end));
  return v_caso;
end
$function$;

-- ═══ 2. ra_slack_pendentes_base: aviso próprio da troca que nasceu em remoção ═══
-- Corpo vivo + 4 mudanças, todas marcadas com 20261006144912:
--   a) ramo `novo` do HM (triagem) ignora a troca direta, dá título legível à troca em triagem e escapa o motivo;
--   b) ramo `novo` novo para a troca direta (marca quem remove, sem bloco Compra);
--   c) `liberado` nunca sai para a troca direta (ela já avisou no `novo`);
--   d) `concluido` da troca direta sai depois do `novo`, como no Acelera.
create or replace function public.ra_slack_pendentes_base(p_segredo text)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_out json;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;

  with base as (
    select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
           to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
           '<' || v_url || '/educacional/remocoes?caso=' || c.id || '|Abrir no sistema>' as link,
           -- 20261006144912: troca de sócio que nasceu em remoção (pa_abrir_caso_remocao), sem triagem.
           (c.tipo = 'troca_socio' and coalesce((c.sugestao ->> 'direto_remocao')::boolean, false)) as direta
      from public.ra_casos c
     where c.avisar_slack  -- 20261006134133: caso silencioso (carga) nunca vai para o Slack
  ),
  msgs as (
    -- Disputa: só alerta, marca o triador.
    select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts, 1 as ordem,
           ':warning: *Disputa aberta no HM*' || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || 'Ainda não é reembolso nem chargeback.' || E'\n' || b.link as texto
      from base b where b.linha = 'hm' and b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Acelera Holding: alerta (disputa, ou reembolso/chargeback de quem ainda tem outra compra válida). Marca o triador.
    select b.id, 'alerta', null, 1,
           case when b.tipo = 'disputa'
                then ':warning: *Disputa aberta no Acelera Holding*'
                when b.sugestao ? 'conflito_produto'
                then ':warning: *' || initcap(b.tipo) || ' chegou como Acelera Holding, mas a transação é de outro produto*'
                else ':warning: *' || initcap(b.tipo) || ' no Acelera Holding: a pessoa ainda tem outra compra válida do Acelera Holding*' end
           || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || case when b.tipo = 'disputa'
                   then 'Ainda não é reembolso nem chargeback.'
                   when b.sugestao ? 'conflito_produto'
                   then public.ra_slack_esc(coalesce(b.sugestao->>'motivo', ''))
                   else 'Outras compras válidas: '
                        || coalesce((select public.ra_slack_esc(string_agg(v->>'transacao', ', '))
                                       from jsonb_array_elements(b.sugestao->'compras_anteriores') v), 'sem detalhe')
                        || E'\n' || 'Não abrimos o checklist de remoção: confira antes de remover qualquer acesso.' end
           || E'\n' || b.link
      from base b where b.linha = 'acelera' and b.status = 'alerta' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo do HM: marca só o triador.
    select b.id, 'novo', null, 1,
           -- 20261006144912: título legível para a troca de sócio (antes saía initcap('troca_socio') = 'Troca_Socio').
           case when b.tipo = 'troca_socio'
                then ':rotating_light: *Troca de sócio no HM, triagem pendente*'
                else ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente*' end || E'\n'
           || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then E'\n' || 'Programa de Implementação' else '' end || E'\n\n'
           || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || public.ra_slack_esc(coalesce(b.sugestao->>'motivo', '')) || E'\n\n'  -- 20261006144912: escape
           || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n' || b.link
      from base b where b.linha = 'hm' and b.tipo <> 'disputa' and not b.direta and not (b.slack_avisos ? 'novo')
    union all
    -- 20261006144912: troca de sócio sem compra própria. Já é a remoção (sem triagem). Marca quem remove.
    select b.id, 'novo', null, 1,
           ':scissors: *Troca de sócio no HM: remover acessos*'
           || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n'
           || coalesce((select string_agg('• ' || public.ra_slack_esc(coalesce(p.nome, 'sem nome')) || ' · '
                                          || public.ra_slack_esc(coalesce(nullif(p.email, ''), 'sem e-mail'))
                                          || ' (sócio de ' || public.ra_slack_esc(coalesce(b.sugestao ->> 'titular', 'titular sem nome')) || ')',
                                          E'\n' order by p.ordem)
                          from public.ra_pessoas p where p.caso_id = b.id), 'sem pessoa') || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
           || 'Pedido de alteração nº ' || coalesce(b.sugestao ->> 'pedido', 'sem número') || E'\n'
           || 'Marquem no sistema quando removerem.' || E'\n' || b.link
      from base b where b.direta and b.status in ('em_remocao', 'concluido') and not (b.slack_avisos ? 'novo')
    union all
    -- Caso novo do Acelera Holding: já é a remoção (sem triagem). Marca quem remove.
    select b.id, 'novo', null, 1,
           ':scissors: *Reembolso/Chargeback no Acelera Holding: remover do Grupo de informes, da Área de membros (Hotmart) e do Obvio*'
           || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || initcap(b.tipo) || ' · ' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
           || 'Marque no sistema quando remover.' || E'\n' || b.link
      from base b where b.linha = 'acelera' and b.status in ('em_remocao', 'concluido') and not (b.slack_avisos ? 'novo')
    union all
    -- Triagem: manter acesso.
    select b.id, 'fechado', b.slack_ts, 2,
           ':white_check_mark: *Mantém o acesso antigo.* Nada a remover.'
           || coalesce(E'\n' || b.decisao_obs, '')
      from base b where b.linha = 'hm' and b.status = 'mantem_acesso' and b.slack_ts is not null and not (b.slack_avisos ? 'fechado')
    union all
    -- Triagem: não remover. Marca quem ajusta a expiração, com as datas.
    select b.id, 'ajuste', b.slack_ts, 2,
           ':white_check_mark: *Não remover acessos*' || E'\n'
           || 'A pessoa mantém o acesso antigo. Ninguém precisa remover nada.' || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || public.ra_slack_marca((select responsavel_id from public.ra_itens_catalogo where item = 'ajuste_central')) || E'\n'
           || 'Voltar a expiração na Central (planilha) e na Base de Alunos (sistema)' || E'\n'
           || coalesce(to_char(b.expiracao_atual, 'DD/MM/YYYY'), 'data atual') || ' → *' || to_char(b.expiracao_antiga, 'DD/MM/YYYY') || '*'
           || case when b.instrucao_antiga is not null and b.instrucao_antiga is distinct from b.instrucao_atual
                   then E'\n' || 'Instrução: ' || coalesce(b.instrucao_atual, 'sem instrução') || ' → *' || b.instrucao_antiga || '*'
                        || case when exists (select 1 from public.ra_pessoas p where p.caso_id = b.id and p.papel = 'socio')
                                then ' (sócios: ' || b.instrucao_antiga || ' - SÓCIO)' else '' end
                   else '' end
           || coalesce(E'\n\n' || b.decisao_obs, '') || E'\n\n'
           || 'Marque no sistema quando atualizar.' || E'\n' || b.link
      from base b where b.linha = 'hm' and b.decisao = 'manter' and b.status in ('ajustando_acesso', 'concluido')
                    and b.slack_ts is not null and not (b.slack_avisos ? 'ajuste')
    union all
    -- Triagem: remoção liberada (só HM). Pessoas uma vez, responsáveis uma vez.
    select b.id, 'liberado', b.slack_ts, 2,
           ':scissors: *Remover acessos*' || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
           || 'Marquem no sistema quando removerem.' || E'\n' || b.link
      from base b where b.linha = 'hm' and b.status in ('em_remocao', 'concluido') and coalesce(b.decisao, 'remover') = 'remover'
                    and not b.direta  -- 20261006144912: a troca direta já pediu a remoção no `novo`
                    and b.slack_ts is not null and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído. HM: depois do liberado/ajuste. Acelera e troca direta: depois do novo.
    select b.id, 'concluido', b.slack_ts, 3,
           case when b.decisao = 'manter' then ':white_check_mark: *Acesso ajustado*' else ':white_check_mark: *Acessos removidos*' end || E'\n\n'
           || (select string_agg('• ' || linha, E'\n') from (
                 select coalesce(mp.nome, 'sem nome') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
                   from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
                  where i.caso_id = b.id
                  group by mp.nome) z)
      from base b where b.status = 'concluido' and b.slack_ts is not null and not (b.slack_avisos ? 'concluido')
                    and ((b.linha = 'hm' and not b.direta and (b.slack_avisos ? 'liberado' or b.slack_avisos ? 'ajuste'))
                         or (b.linha = 'acelera' and b.slack_avisos ? 'novo')
                         or (b.direta and b.slack_avisos ? 'novo'))  -- 20261006144912
  )
  select json_build_object('ok', true, 'mensagens',
           coalesce(json_agg(json_build_object('caso_id', m.caso_id, 'aviso', m.aviso,
                                               'thread_ts', m.thread_ts, 'texto', m.texto) order by m.ordem), '[]'::json))
    into v_out from msgs m;
  return v_out;
end $function$;

-- ═══ 3. ra_desfazer_triagem: a troca que nasceu em remoção não tem triagem para desfazer ═══
create or replace function public.ra_desfazer_triagem(p_caso uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_marcados int;
  v_avisou boolean;
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem pode desfazer.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.linha <> 'hm' then
    return json_build_object('ok', false, 'msg', 'Caso do Acelera Holding não tem triagem para desfazer.');
  end if;
  -- 20261006144912
  if v_caso.tipo = 'troca_socio' and coalesce((v_caso.sugestao ->> 'direto_remocao')::boolean, false) then
    return json_build_object('ok', false, 'msg', 'Troca de sócio sem compra própria entrou direto em remoção: não tem triagem para desfazer.');
  end if;
  if v_caso.status not in ('em_remocao', 'mantem_acesso', 'ajustando_acesso', 'concluido') then
    return json_build_object('ok', false, 'msg', 'Este caso não tem triagem para desfazer.');
  end if;

  select count(*) into v_marcados from public.ra_itens where caso_id = p_caso and situacao <> 'pendente';
  if v_marcados > 0 then
    return json_build_object('ok', false, 'msg',
      format('%s item(ns) já marcado(s). Desmarque antes de desfazer a triagem.', v_marcados));
  end if;

  delete from public.ra_itens where caso_id = p_caso;

  v_avisou := v_caso.slack_ts is not null
              and (v_caso.slack_avisos ? 'liberado' or v_caso.slack_avisos ? 'fechado' or v_caso.slack_avisos ? 'ajuste');
  update public.ra_casos
     set status = 'aguardando_triagem', triado_por = null, triado_em = null,
         decisao_obs = null, concluido_em = null, decisao = null,
         expiracao_atual = null, expiracao_antiga = null, instrucao_atual = null, instrucao_antiga = null,
         slack_avisos = (slack_avisos - 'liberado' - 'fechado' - 'ajuste' - 'concluido')
                        || case when v_avisou then '{"desfazer_pendente": true}'::jsonb else '{}'::jsonb end
   where id = p_caso;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem_desfeita', v_uid, jsonb_build_object('status_anterior', v_caso.status));
  return json_build_object('ok', true, 'msg', 'Triagem desfeita. O caso voltou para aguardando triagem.');
end $function$;

-- ═══ 4. Conferência: grants iguais aos de antes (create or replace não mexe neles) ═══
do $confere$
begin
  if has_function_privilege('authenticated', 'public.pa_abrir_caso_remocao(bigint,uuid,text)', 'execute')
     or has_function_privilege('anon', 'public.pa_abrir_caso_remocao(bigint,uuid,text)', 'execute') then
    raise exception '20261006144912: pa_abrir_caso_remocao ficou executável pela tela';
  end if;
  if has_function_privilege('authenticated', 'public.ra_slack_pendentes_base(text)', 'execute')
     or has_function_privilege('anon', 'public.ra_slack_pendentes_base(text)', 'execute') then
    raise exception '20261006144912: ra_slack_pendentes_base ficou executável pela tela';
  end if;
  if not has_function_privilege('authenticated', 'public.ra_desfazer_triagem(uuid)', 'execute') then
    raise exception '20261006144912: ra_desfazer_triagem perdeu o grant da tela';
  end if;
end
$confere$;


-- ═══ ENSAIO: testes ════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.msgs(p_caso uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(m), '[]'::jsonb) from jsonb_array_elements(pg_temp.pend()) m where (m ->> 'caso_id')::uuid = p_caso $$;
create function pg_temp.msg(p_caso uuid, p_aviso text) returns text language sql as $$
  select m ->> 'texto' from jsonb_array_elements(pg_temp.msgs(p_caso)) m where m ->> 'aviso' = p_aviso $$;
create function pg_temp.avisos(p_caso uuid) returns text language sql as $$
  select coalesce(string_agg(m ->> 'aviso', ',' order by m ->> 'aviso'), 'nenhum') from jsonb_array_elements(pg_temp.msgs(p_caso)) m $$;

-- Alunos de TESTE (somem no rollback): titular do Programa, 3 sócios que saem, 3 pessoas existentes que entram.
insert into public.thb_alunos (id, nome, email, instrucao, espaco_instrucao, data_expiracao, mes_expiracao, ano_expiracao,
                               num_socios, fonte, data_entrada_thb, turma_id)
values ('e0000000-0000-4000-8000-0000000144a0', 'ZZ Ensaio 144912 Titular', 'zz.144912.titular@exemplo.invalid',
        'THB IMPLEMENTAÇÃO', 'holding_masters_implementacao', '2027-03-31', 3, 2027, 3, 'ensaio_20261006144912', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144a1', 'ZZ Ensaio 144912 Sai Sem Compra', 'zz.144912.sai1@exemplo.invalid',
        'THB IMPLEMENTAÇÃO - SÓCIO', 'holding_masters_implementacao', '2027-03-31', 3, 2027, null, 'ensaio_20261006144912', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144a2', 'ZZ Ensaio 144912 Sai Compra Financeiro', 'zz.144912.sai2@exemplo.invalid',
        'THB IMPLEMENTAÇÃO - SÓCIO', 'holding_masters_implementacao', '2027-03-31', 3, 2027, null, 'ensaio_20261006144912', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144a3', 'ZZ Ensaio 144912 Sai Compra Sistema', 'zz.144912.sai3@exemplo.invalid',
        'THB IMPLEMENTAÇÃO - SÓCIO', 'holding_masters_implementacao', '2027-03-31', 3, 2027, null, 'ensaio_20261006144912', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144a4', 'ZZ Ensaio 144912 Sai Sem Email Nem Doc', null,
        'THB IMPLEMENTAÇÃO - SÓCIO', 'holding_masters_implementacao', '2027-03-31', 3, 2027, null, 'ensaio_20261006144912', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000000144b4', 'ZZ Ensaio 144912 Entra 4', 'zz.144912.entra4@exemplo.invalid',
        null, null, null, null, null, null, 'ensaio_20261006144912', null, null),
       ('e0000000-0000-4000-8000-0000000144b1', 'ZZ Ensaio 144912 Entra 1', 'zz.144912.entra1@exemplo.invalid',
        null, null, null, null, null, null, 'ensaio_20261006144912', null, null),
       ('e0000000-0000-4000-8000-0000000144b2', 'ZZ Ensaio 144912 Entra 2', 'zz.144912.entra2@exemplo.invalid',
        null, null, null, null, null, null, 'ensaio_20261006144912', null, null),
       ('e0000000-0000-4000-8000-0000000144b3', 'ZZ Ensaio 144912 Entra 3', 'zz.144912.entra3@exemplo.invalid',
        null, null, null, null, null, null, 'ensaio_20261006144912', null, null);
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000000144a0',
       socio_de_nome = 'ZZ Ensaio 144912 Titular'
 where id in ('e0000000-0000-4000-8000-0000000144a1', 'e0000000-0000-4000-8000-0000000144a2', 'e0000000-0000-4000-8000-0000000144a3',
              'e0000000-0000-4000-8000-0000000144a4');

-- Sócio de p2: compra própria SÓ no financeiro (Aurum 3094405 COMPLETE, transação falsa ZZ).
insert into fin.hotmart_transacoes (transacao, produto_id, produto_nome, status, comprador_email, aprovado_em, bruto_json, conta)
values ('ZZ144912AURUM', '3094405', 'Aurum ', 'COMPLETE', 'zz.144912.sai2@exemplo.invalid', '2025-07-22 12:00:00+00', '{}'::jsonb, 'academy');

-- Sócio de p3: compra própria em public.compras (o caminho da regra da triagem). E-mail de um comprador real de HM
-- aprovado que não está na base de alunos; nunca impresso, some no rollback.
create temp table _real on commit drop as
  select lower(trim(cp.email)) e
    from public.compras c join public.compradores cp on cp.id = c.comprador_id
   where c.status in ('APPROVED', 'COMPLETED', 'COMPLETE') and c.produto_id in ('5064314', '3507214', '3094405')
     and nullif(trim(cp.email), '') is not null
     and not exists (select 1 from public.thb_alunos a where lower(trim(a.email)) = lower(trim(cp.email)))
   order by c.data_compra desc nulls last limit 1;
update public.thb_alunos set email = (select e from _real) where id = 'e0000000-0000-4000-8000-0000000144a3';
select pg_temp.ok('0.cenario',
  (select count(*) from public.thb_alunos where fonte = 'ensaio_20261006144912') = 9 and (select count(*) from _real) = 1,
  '9 alunos ZZ; sócio de p3 com e-mail de comprador real de HM (não impresso)');

-- 1. Como o Victor (pede e aprova): três pedidos de troca, aprovados pela pa_decidir.
create temp table _p (k text primary key, criar jsonb, decidir jsonb) on commit drop;
insert into _p (k, criar)
select 'p' || x.n, pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_criar(%L::jsonb)::jsonb', jsonb_build_object('tipo', 'trocar_socio',
           'aluno_id', 'e0000000-0000-4000-8000-0000000144a0',
           'socio_sai_id', 'e0000000-0000-4000-8000-0000000144a' || x.n,
           'socio_entra_id', 'e0000000-0000-4000-8000-0000000144b' || x.n,
           'motivo', 'ensaio da migration 20261006144912')))
  from (values (1), (2), (3), (4)) x(n);
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint))
 where k = 'p1';
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint))
 where k = 'p2';
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint))
 where k = 'p3';
update _p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
         format('select public.pa_decidir(%s, ''aprovar'')::jsonb', (criar ->> 'numero')::bigint))
 where k = 'p4';
select pg_temp.ok('1.pedido_' || k,
  (decidir ->> 'ok')::boolean and (decidir ->> 'ra_caso_id') is not null
  and (select ra_caso_id from public.pa_pedidos where id = (criar ->> 'numero')::bigint) = (decidir ->> 'ra_caso_id')::uuid,
  coalesce(decidir ->> 'msg', decidir ->> 'erro', criar ->> 'msg', criar ->> 'erro'))
  from _p order by k;
create function pg_temp.caso(p_k text) returns uuid language sql as $$ select (decidir ->> 'ra_caso_id')::uuid from _p where k = p_k $$;
create function pg_temp.num(p_k text) returns text language sql as $$ select criar ->> 'numero' from _p where k = p_k $$;

-- 2. Sem compra própria: direto em remoção, com os itens do mesmo filtro do ra_triar, sem triagem.
select pg_temp.ok('2.caso_direto',
  c.status = 'em_remocao' and c.decisao = 'remover' and c.linha = 'hm' and c.tipo = 'troca_socio'
  and c.eh_programa and c.triado_em is null and c.triado_por is null and c.prazo_em is not null and c.avisar_slack
  and (c.sugestao ->> 'direto_remocao')::boolean and c.sugestao ->> 'recomendacao' = 'remover'
  and jsonb_array_length(c.sugestao -> 'compras_anteriores') = 0,
  'status=' || c.status || ' decisao=' || c.decisao || ' linha=' || c.linha || ' programa=' || c.eh_programa
  || ' triado_em=' || coalesce(c.triado_em::text, 'nulo') || ' | motivo: ' || (c.sugestao ->> 'motivo'))
  from public.ra_casos c where c.id = pg_temp.caso('p1');
select pg_temp.ok('2.itens_direto',
  (select string_agg(i.item || '>' || i.responsavel_id, ',' order by i.item) from public.ra_itens i where i.caso_id = pg_temp.caso('p1'))
  = (select string_agg(k.item || '>' || k.responsavel_id, ',' order by k.item) from public.ra_itens_catalogo k
      where k.ativo and k.fluxo = 'remocao' and k.linha = 'hm')
  and not exists (select 1 from public.ra_itens where caso_id = pg_temp.caso('p1') and situacao <> 'pendente'),
  (select string_agg(k.rotulo, ' | ' order by k.ordem) from public.ra_itens i join public.ra_itens_catalogo k on k.item = i.item
    where i.caso_id = pg_temp.caso('p1')) || ' (todos pendentes; Programa, então inclui o item só do Programa)');
select pg_temp.ok('2.historico_direto',
  h.detalhe ->> 'evento' = 'direto em remoção pelo pedido nº ' || pg_temp.num('p1'),
  h.acao || ': ' || (h.detalhe ->> 'evento') || ' · status_inicial=' || (h.detalhe ->> 'status_inicial'))
  from public.ra_historico h where h.caso_id = pg_temp.caso('p1') and h.acao = 'aberto';

-- 3. Slack da troca direta: um aviso só, `novo`, com o texto novo e todos os responsáveis.
select pg_temp.ok('3.slack_um_aviso', pg_temp.avisos(pg_temp.caso('p1')) = 'novo', 'avisos pendentes: ' || pg_temp.avisos(pg_temp.caso('p1')));
select pg_temp.ok('3.slack_texto',
  t like ':scissors: *Troca de sócio no HM: remover acessos*' || E'\n' || '*Prazo:* %'
  and t like '%*Pessoas*' || E'\n' || '• ZZ Ensaio 144912 Sai Sem Compra · zz.144912.sai1@exemplo.invalid (sócio de ZZ Ensaio 144912 Titular)%'
  and t like '%Pedido de alteração nº ' || pg_temp.num('p1') || E'\n' || 'Marquem no sistema quando removerem.%'
  and t not like '%*Compra*%' and t not like '%triagem%'
  and (select bool_and(t like '%' || public.ra_slack_marca(r) || '%')
         from (select distinct responsavel_id r from public.ra_itens_catalogo where ativo and fluxo = 'remocao' and linha = 'hm') x),
  E'texto abaixo (os <@...> são as marcas dos responsáveis)\n' || t)
  from (select pg_temp.msg(pg_temp.caso('p1'), 'novo') t) z;

-- 4. Com compra própria só no financeiro: triagem como hoje, título legível, sugestão 'verificar' com a compra.
select pg_temp.ok('4.caso_triagem_financeiro',
  c.status = 'aguardando_triagem' and c.decisao is null and c.linha = 'hm'
  and not (c.sugestao ->> 'direto_remocao')::boolean and c.sugestao ->> 'recomendacao' = 'verificar'
  and jsonb_array_length(c.sugestao -> 'compras_anteriores') = 1
  and c.sugestao -> 'compras_anteriores' -> 0 ->> 'transacao' = 'ZZ144912AURUM'
  and not exists (select 1 from public.ra_itens where caso_id = c.id),
  'status=' || c.status || ' itens=0 compras=' || (c.sugestao -> 'compras_anteriores')::text)
  from public.ra_casos c where c.id = pg_temp.caso('p2');
select pg_temp.ok('4.historico_triagem',
  h.detalhe ->> 'evento' = 'triagem: tem compra própria (pedido nº ' || pg_temp.num('p2') || ')', h.detalhe ->> 'evento')
  from public.ra_historico h where h.caso_id = pg_temp.caso('p2') and h.acao = 'aberto';
select pg_temp.ok('4.slack_triagem',
  pg_temp.avisos(pg_temp.caso('p2')) = 'novo'
  and split_part(pg_temp.msg(pg_temp.caso('p2'), 'novo'), E'\n', 1) = ':rotating_light: *Troca de sócio no HM, triagem pendente*'
  and pg_temp.msg(pg_temp.caso('p2'), 'novo') like
      '%' || public.ra_slack_marca('81d2eaee-cce1-4058-8714-439b0fc6f970') || '%*Sugestão:* verificar%',
  split_part(pg_temp.msg(pg_temp.caso('p2'), 'novo'), E'\n', 1) || ' (marca o triador; sugestão verificar)');

-- 5. Com compra própria em public.compras: triagem, e a mesma transação não entra duas vezes (sistema + financeiro).
select pg_temp.ok('5.caso_triagem_sistema',
  c.status = 'aguardando_triagem' and c.sugestao ->> 'recomendacao' = 'verificar'
  and jsonb_array_length(c.sugestao -> 'compras_anteriores') >= 1
  and (select count(*) = count(distinct x ->> 'transacao') from jsonb_array_elements(c.sugestao -> 'compras_anteriores') x),
  'status=' || c.status || ' compras=' || jsonb_array_length(c.sugestao -> 'compras_anteriores') || ', sem repetida (transações não impressas)')
  from public.ra_casos c where c.id = pg_temp.caso('p3');

-- 5b. Sem e-mail e sem documento: não dá para checar compra própria, vai para a triagem.
select pg_temp.ok('5b.caso_sem_identificador',
  c.status = 'aguardando_triagem' and c.decisao is null and c.sugestao ->> 'recomendacao' = 'verificar'
  and not (c.sugestao ->> 'direto_remocao')::boolean
  and c.sugestao ->> 'motivo' like '%Sem e-mail/documento para checar compra própria%'
  and not exists (select 1 from public.ra_itens where caso_id = c.id)
  and (select h.detalhe ->> 'evento' from public.ra_historico h where h.caso_id = c.id and h.acao = 'aberto')
      = 'triagem: sem e-mail/documento para checar compra própria (pedido nº ' || pg_temp.num('p4') || ')',
  'status=' || c.status || ' | motivo: ' || (c.sugestao ->> 'motivo'))
  from public.ra_casos c where c.id = pg_temp.caso('p4');

-- 5c. Escape do motivo no aviso de triagem: & < > viram entidades (mesmo ra_slack_esc do resto do texto).
update public.ra_casos set sugestao = jsonb_set(sugestao, '{motivo}', '"ZZ <b>teste</b> & <@U000> motivo"')
 where id = pg_temp.caso('p4');
select pg_temp.ok('5c.motivo_escapado',
  pg_temp.msg(pg_temp.caso('p4'), 'novo') like '%ZZ &lt;b&gt;teste&lt;/b&gt; &amp; &lt;@U000&gt; motivo%'
  and pg_temp.msg(pg_temp.caso('p4'), 'novo') not like '%<b>teste%',
  (select l from regexp_split_to_table(pg_temp.msg(pg_temp.caso('p4'), 'novo'), E'\n') l where l like 'ZZ %'));

-- 6. Desfazer: recusa a troca direta; a troca triada continua podendo desfazer.
create temp table _r (k text primary key, r jsonb) on commit drop;
insert into _r select 'desfazer_p1', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
  format('select public.ra_desfazer_triagem(%L::uuid)::jsonb', pg_temp.caso('p1')));
insert into _r select 'triar_p2', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
  format('select public.ra_triar(%L::uuid, ''remover'')::jsonb', pg_temp.caso('p2')));
insert into _r select 'desfazer_p2', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
  format('select public.ra_desfazer_triagem(%L::uuid)::jsonb', pg_temp.caso('p2')));
select pg_temp.ok('6.desfazer_direto_recusa',
  not ((select r from _r where k = 'desfazer_p1') ->> 'ok')::boolean
  and (select status from public.ra_casos where id = pg_temp.caso('p1')) = 'em_remocao'
  and (select count(*) from public.ra_itens where caso_id = pg_temp.caso('p1'))
      = (select count(*) from public.ra_itens_catalogo where ativo and fluxo = 'remocao' and linha = 'hm'),
  coalesce((select r from _r where k = 'desfazer_p1') ->> 'msg', (select r::text from _r where k = 'desfazer_p1')));
select pg_temp.ok('6.desfazer_triada_ok',
  ((select r from _r where k = 'triar_p2') ->> 'ok')::boolean and ((select r from _r where k = 'desfazer_p2') ->> 'ok')::boolean
  and (select status from public.ra_casos where id = pg_temp.caso('p2')) = 'aguardando_triagem',
  coalesce((select r from _r where k = 'triar_p2') ->> 'msg', '') || ' / ' || coalesce((select r from _r where k = 'desfazer_p2') ->> 'msg', ''));

-- 7. Sem aviso duplicado: postado o `novo`, não sai `liberado`; ao concluir, sai `concluido` uma vez.
select public.ra_slack_confirmar((select s from _s), pg_temp.caso('p1'), 'novo', 'ZZ.144912');
select pg_temp.ok('7.sem_liberado', pg_temp.avisos(pg_temp.caso('p1')) = 'nenhum',
  'pendentes depois de postar o novo: ' || pg_temp.avisos(pg_temp.caso('p1')));
insert into _r select 'marcar_' || i.item, pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
  format('select public.ra_marcar_item(%L::uuid, ''feito'', ''ensaio'')::jsonb', i.id))
  from public.ra_itens i where i.caso_id = pg_temp.caso('p1');
select pg_temp.ok('7.concluido',
  (select status from public.ra_casos where id = pg_temp.caso('p1')) = 'concluido'
  and (select bool_and((r ->> 'ok')::boolean) from _r where k like 'marcar\_%')
  and pg_temp.avisos(pg_temp.caso('p1')) = 'concluido'
  and pg_temp.msg(pg_temp.caso('p1'), 'concluido') like ':white_check_mark: *Acessos removidos*%',
  'status=' || (select status from public.ra_casos where id = pg_temp.caso('p1')) || ' avisos=' || pg_temp.avisos(pg_temp.caso('p1')));
select public.ra_slack_confirmar((select s from _s), pg_temp.caso('p1'), 'concluido', null);
select pg_temp.ok('7.fim', pg_temp.avisos(pg_temp.caso('p1')) = 'nenhum', 'nada mais a postar para a troca direta');

-- 8. Casos reais: os avisos pendentes são os mesmos de antes da migration (caso, aviso e texto).
select pg_temp.ok('8.casos_reais',
  not exists (
    (select caso_id, aviso, t from _antes_msgs
     except
     select m ->> 'caso_id', m ->> 'aviso', md5(m ->> 'texto') from jsonb_array_elements(pg_temp.pend()) m)
    union all
    (select m ->> 'caso_id', m ->> 'aviso', md5(m ->> 'texto') from jsonb_array_elements(pg_temp.pend()) m
      where (m ->> 'caso_id')::uuid not in (select pg_temp.caso(k) from _p)
     except
     select caso_id, aviso, t from _antes_msgs)),
  'avisos pendentes de casos reais: ' || (select count(*) from _antes_msgs) || ' antes, mesmos textos depois');

-- 9. Grants
select pg_temp.ok('9.grants',
  not has_function_privilege('authenticated', 'public.pa_abrir_caso_remocao(bigint,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.pa_abrir_caso_remocao(bigint,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.ra_slack_pendentes_base(text)', 'execute')
  and has_function_privilege('authenticated', 'public.ra_desfazer_triagem(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.ra_desfazer_triagem(uuid)', 'execute'),
  'pa_abrir_caso_remocao e ra_slack_pendentes_base fora da tela; ra_desfazer_triagem só authenticated');

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
