-- 20261006144912: Pedidos de alteração, troca de sócio: quem sai sem compra própria entra DIRETO em remoção
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006144912_ensaio.sql (begin … rollback). Notas: 20261006144912.explain.md.
-- Independente da 20261006144913 (sócio novo herda entrada e turma do titular): as duas podem ir em qualquer ordem.
--
-- DECISÃO DO VICTOR (06/10/2026): o sócio que sai entra direto em remoção, salvo se tiver compra própria.
--
-- O QUE FAZ
--   1. pa_abrir_caso_remocao (mesma assinatura, chamada pela pa_decidir da 20261005k) passa a decidir na abertura:
--      - SEM compra própria: caso nasce `em_remocao`, `decisao = 'remover'`, `linha = 'hm'`, com os itens criados na
--        mesma transação pelo mesmo filtro do ra_triar com 'remover'
--        (ativo and fluxo = 'remocao' and linha = 'hm' and (not so_programa or eh_programa), on conflict do nothing).
--        triado_em e triado_por ficam nulos, como em ra_criar_caso_acelera. Histórico 'aberto' com
--        evento "direto em remoção pelo pedido nº N" (a ficha mostra o `evento` do 'aberto').
--      - COM compra própria: igual a hoje (`aguardando_triagem`, triagem do Victor), mas a sugestão passa a
--        'verificar' com as compras listadas em `compras_anteriores` (a ficha já mostra "Outras compras que dão acesso").
--      - Compra própria = a regra da triagem (ra_montar_sugestao: produtos 5064314 Holding Masters, 3507214
--        "Holding - Holding Masters" e 3094405 Aurum; status APPROVED/COMPLETED/COMPLETE; mesma pessoa por e-mail ou
--        documento; em public.compras) MAIS o mesmo filtro no financeiro da Hotmart (fin.hotmart_transacoes, conta
--        academy), porque public.compras começa em 14/03/2026 e o financeiro guarda desde 2023.
--      - Marcas na sugestão: `direto_remocao` (boolean), `pedido` (nº) e `titular` (nome). É por `direto_remocao` que o
--        Slack, o desfazer e a tela reconhecem a troca que nasceu em remoção.
--   2. ra_slack_pendentes_base: aviso `novo` próprio da troca direta (":scissors: *Troca de sócio no HM: remover
--      acessos*", Prazo, Pessoas com "sócio de <titular>", responsáveis via ra_slack_responsaveis, "Pedido de alteração
--      nº N", sem bloco Compra). A troca em triagem segue no ramo de sempre, com o título "Troca de sócio no HM,
--      triagem pendente" (antes saía initcap('troca_socio')). `liberado` nunca sai para a troca direta; `concluido`
--      sai depois do `novo`, como no Acelera. Nada muda para reembolso, chargeback, disputa e Acelera.
--   3. ra_desfazer_triagem recusa a troca que nasceu em remoção.
--
-- BASE: cada função recriada parte do corpo VIVO (pg_get_functiondef lido em 06/10/2026), conferido pelo md5 na guarda.
-- Quem lê fora do v2: ninguém (grep em disparos-thb, controle-de-eventos, departamento-de-marketing, gp-operacoes e
-- dashboard-ht sem ocorrência). O n8n só repassa o texto de ra_slack_reservar: o contrato (caso_id, aviso, thread_ts,
-- texto) não muda.
-- REVERSÃO: bloco comentado no fim deste arquivo (corpo vivo das três funções) e 20261006144912.explain.md.

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
  v_direto := jsonb_array_length(v_compras) = 0;

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
                                            else 'triagem: tem compra própria (pedido nº ' || p_pedido || ')' end));
  return v_caso;
end
$function$;

-- ═══ 2. ra_slack_pendentes_base: aviso próprio da troca que nasceu em remoção ═══
-- Corpo vivo + 4 mudanças, todas marcadas com 20261006144912:
--   a) ramo `novo` do HM (triagem) ignora a troca direta e dá título legível à troca em triagem;
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
           || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || coalesce(b.sugestao->>'motivo', '') || E'\n\n'
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

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Volta as três funções ao corpo vivo lido em 06/10/2026. Antes, conferir as trocas que nasceram em remoção: com o corpo
-- antigo elas passam a sair no ramo `novo` da triagem do Slack (se ainda não postaram) e o desfazer volta a aceitá-las:
--   select id, status, slack_avisos from public.ra_casos where tipo = 'troca_socio' and (sugestao ->> 'direto_remocao')::boolean;
-- Para reverter: tirar o "-- " das linhas abaixo e rodar o bloco inteiro numa transação.

-- CREATE OR REPLACE FUNCTION public.pa_abrir_caso_remocao(p_pedido bigint, p_socio uuid, p_titular_nome text)
--  RETURNS uuid
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO ''
-- AS $function$
-- declare
--   v_s public.thb_alunos%rowtype;
--   v_turma text;
--   v_caso uuid;
--   v_transacao text := 'PEDIDO-ALTERACAO-' || p_pedido;
-- begin
--   select * into v_s from public.thb_alunos where id = p_socio;
--   select t.codigo into v_turma from public.thb_turmas t where t.id = v_s.turma_id;
--   insert into public.ra_casos (
--     compra_id, hotmart_transaction, tipo, status, produto_nome, aluno_id, nome, email, telefone, documento,
--     ocorrido_em, prazo_em, eh_programa, sugestao, teste, origem)
--   values (
--     null, v_transacao, 'troca_socio', 'aguardando_triagem', 'Troca de sócio (pedido nº ' || p_pedido || ')',
--     v_s.id, v_s.nome, v_s.email, v_s.telefone, v_s.documento,
--     now(), public.ra_calcular_prazo(now()), coalesce(v_s.espaco_instrucao = 'holding_masters_implementacao', false),
--     jsonb_build_object(
--       'recomendacao', 'remover',
--       'motivo', 'Troca de sócio, pedido nº ' || p_pedido || ': saiu do vínculo com ' || coalesce(p_titular_nome, 'o titular') || '.',
--       'compras_anteriores', '[]'::jsonb,
--       'aluno', jsonb_build_object('instrucao', v_s.instrucao, 'espaco', v_s.espaco_instrucao, 'turma', v_turma,
--                                   'data_expiracao', v_s.data_expiracao, 'data_entrada_thb', v_s.data_entrada_thb,
--                                   'status_central', v_s.status_acesso_central, 'eh_socio', v_s.eh_socio),
--       'historico_expiracao', '[]'::jsonb,
--       'aviso', 'Caso aberto pela aprovação de um pedido de alteração de cadastro, não pela Hotmart.'),
--     false, 'pedido_alteracao')
--   on conflict (hotmart_transaction, tipo) do nothing
--   returning id into v_caso;
--
--   if v_caso is null then
--     select id into v_caso from public.ra_casos where hotmart_transaction = v_transacao and tipo = 'troca_socio';
--     return v_caso;
--   end if;
--   insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
--   values (v_caso, v_s.id, v_s.nome, v_s.email, 'socio', 0);
--   insert into public.ra_historico (caso_id, acao, por, detalhe)
--   values (v_caso, 'aberto', (select p.id from public.perfis p where p.id = (select auth.uid())),
--           jsonb_build_object('tipo', 'troca_socio', 'origem', 'pedido_alteracao', 'pedido', p_pedido,
--                              'titular', p_titular_nome));
--   return v_caso;
-- end
-- $function$
-- ;

-- CREATE OR REPLACE FUNCTION public.ra_slack_pendentes_base(p_segredo text)
--  RETURNS json
--  LANGUAGE plpgsql
--  STABLE SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- declare
--   v_url text := (select valor from public.ra_config where chave = 'app_url');
--   v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
--   v_out json;
-- begin
--   if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
--
--   with base as (
--     select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
--            to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
--            '<' || v_url || '/educacional/remocoes?caso=' || c.id || '|Abrir no sistema>' as link
--       from public.ra_casos c
--      where c.avisar_slack  -- 20261006134133: caso silencioso (carga) nunca vai para o Slack
--   ),
--   msgs as (
--     -- Disputa: só alerta, marca o triador.
--     select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts, 1 as ordem,
--            ':warning: *Disputa aberta no HM*' || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
--            || 'Ainda não é reembolso nem chargeback.' || E'\n' || b.link as texto
--       from base b where b.linha = 'hm' and b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
--     union all
--     -- Acelera Holding: alerta (disputa, ou reembolso/chargeback de quem ainda tem outra compra válida). Marca o triador.
--     select b.id, 'alerta', null, 1,
--            case when b.tipo = 'disputa'
--                 then ':warning: *Disputa aberta no Acelera Holding*'
--                 when b.sugestao ? 'conflito_produto'
--                 then ':warning: *' || initcap(b.tipo) || ' chegou como Acelera Holding, mas a transação é de outro produto*'
--                 else ':warning: *' || initcap(b.tipo) || ' no Acelera Holding: a pessoa ainda tem outra compra válida do Acelera Holding*' end
--            || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
--            || case when b.tipo = 'disputa'
--                    then 'Ainda não é reembolso nem chargeback.'
--                    when b.sugestao ? 'conflito_produto'
--                    then public.ra_slack_esc(coalesce(b.sugestao->>'motivo', ''))
--                    else 'Outras compras válidas: '
--                         || coalesce((select public.ra_slack_esc(string_agg(v->>'transacao', ', '))
--                                        from jsonb_array_elements(b.sugestao->'compras_anteriores') v), 'sem detalhe')
--                         || E'\n' || 'Não abrimos o checklist de remoção: confira antes de remover qualquer acesso.' end
--            || E'\n' || b.link
--       from base b where b.linha = 'acelera' and b.status = 'alerta' and not (b.slack_avisos ? 'alerta')
--     union all
--     -- Caso novo do HM: marca só o triador.
--     select b.id, 'novo', null, 1,
--            ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente*' || E'\n'
--            || public.ra_slack_marca(v_triador) || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || '*Compra*' || E'\n' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
--            || case when b.eh_programa then E'\n' || 'Programa de Implementação' else '' end || E'\n\n'
--            || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || coalesce(b.sugestao->>'motivo', '') || E'\n\n'
--            || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n' || b.link
--       from base b where b.linha = 'hm' and b.tipo <> 'disputa' and not (b.slack_avisos ? 'novo')
--     union all
--     -- Caso novo do Acelera Holding: já é a remoção (sem triagem). Marca quem remove.
--     select b.id, 'novo', null, 1,
--            ':scissors: *Reembolso/Chargeback no Acelera Holding: remover do Grupo de informes, da Área de membros (Hotmart) e do Obvio*'
--            || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || '*Compra*' || E'\n' || initcap(b.tipo) || ' · ' || public.ra_slack_esc(coalesce(b.produto_nome, '')) || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
--            || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
--            || 'Marque no sistema quando remover.' || E'\n' || b.link
--       from base b where b.linha = 'acelera' and b.status in ('em_remocao', 'concluido') and not (b.slack_avisos ? 'novo')
--     union all
--     -- Triagem: manter acesso.
--     select b.id, 'fechado', b.slack_ts, 2,
--            ':white_check_mark: *Mantém o acesso antigo.* Nada a remover.'
--            || coalesce(E'\n' || b.decisao_obs, '')
--       from base b where b.linha = 'hm' and b.status = 'mantem_acesso' and b.slack_ts is not null and not (b.slack_avisos ? 'fechado')
--     union all
--     -- Triagem: não remover. Marca quem ajusta a expiração, com as datas.
--     select b.id, 'ajuste', b.slack_ts, 2,
--            ':white_check_mark: *Não remover acessos*' || E'\n'
--            || 'A pessoa mantém o acesso antigo. Ninguém precisa remover nada.' || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || public.ra_slack_marca((select responsavel_id from public.ra_itens_catalogo where item = 'ajuste_central')) || E'\n'
--            || 'Voltar a expiração na Central (planilha) e na Base de Alunos (sistema)' || E'\n'
--            || coalesce(to_char(b.expiracao_atual, 'DD/MM/YYYY'), 'data atual') || ' → *' || to_char(b.expiracao_antiga, 'DD/MM/YYYY') || '*'
--            || case when b.instrucao_antiga is not null and b.instrucao_antiga is distinct from b.instrucao_atual
--                    then E'\n' || 'Instrução: ' || coalesce(b.instrucao_atual, 'sem instrução') || ' → *' || b.instrucao_antiga || '*'
--                         || case when exists (select 1 from public.ra_pessoas p where p.caso_id = b.id and p.papel = 'socio')
--                                 then ' (sócios: ' || b.instrucao_antiga || ' - SÓCIO)' else '' end
--                    else '' end
--            || coalesce(E'\n\n' || b.decisao_obs, '') || E'\n\n'
--            || 'Marque no sistema quando atualizar.' || E'\n' || b.link
--       from base b where b.linha = 'hm' and b.decisao = 'manter' and b.status in ('ajustando_acesso', 'concluido')
--                     and b.slack_ts is not null and not (b.slack_avisos ? 'ajuste')
--     union all
--     -- Triagem: remoção liberada (só HM). Pessoas uma vez, responsáveis uma vez.
--     select b.id, 'liberado', b.slack_ts, 2,
--            ':scissors: *Remover acessos*' || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
--            || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
--            || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
--            || 'Marquem no sistema quando removerem.' || E'\n' || b.link
--       from base b where b.linha = 'hm' and b.status in ('em_remocao', 'concluido') and coalesce(b.decisao, 'remover') = 'remover'
--                     and b.slack_ts is not null and not (b.slack_avisos ? 'liberado')
--     union all
--     -- Concluído. HM: depois do liberado/ajuste. Acelera: depois do novo.
--     select b.id, 'concluido', b.slack_ts, 3,
--            case when b.decisao = 'manter' then ':white_check_mark: *Acesso ajustado*' else ':white_check_mark: *Acessos removidos*' end || E'\n\n'
--            || (select string_agg('• ' || linha, E'\n') from (
--                  select coalesce(mp.nome, 'sem nome') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
--                    from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
--                   where i.caso_id = b.id
--                   group by mp.nome) z)
--       from base b where b.status = 'concluido' and b.slack_ts is not null and not (b.slack_avisos ? 'concluido')
--                     and ((b.linha = 'hm' and (b.slack_avisos ? 'liberado' or b.slack_avisos ? 'ajuste'))
--                          or (b.linha = 'acelera' and b.slack_avisos ? 'novo'))
--   )
--   select json_build_object('ok', true, 'mensagens',
--            coalesce(json_agg(json_build_object('caso_id', m.caso_id, 'aviso', m.aviso,
--                                                'thread_ts', m.thread_ts, 'texto', m.texto) order by m.ordem), '[]'::json))
--     into v_out from msgs m;
--   return v_out;
-- end $function$
-- ;

-- CREATE OR REPLACE FUNCTION public.ra_desfazer_triagem(p_caso uuid)
--  RETURNS json
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- declare
--   v_caso public.ra_casos%rowtype;
--   v_uid uuid := (select auth.uid());
--   v_marcados int;
--   v_avisou boolean;
-- begin
--   if not public.ra_eh_triador() then
--     return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem pode desfazer.');
--   end if;
--   select * into v_caso from public.ra_casos where id = p_caso for update;
--   if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
--   if v_caso.linha <> 'hm' then
--     return json_build_object('ok', false, 'msg', 'Caso do Acelera Holding não tem triagem para desfazer.');
--   end if;
--   if v_caso.status not in ('em_remocao', 'mantem_acesso', 'ajustando_acesso', 'concluido') then
--     return json_build_object('ok', false, 'msg', 'Este caso não tem triagem para desfazer.');
--   end if;
--
--   select count(*) into v_marcados from public.ra_itens where caso_id = p_caso and situacao <> 'pendente';
--   if v_marcados > 0 then
--     return json_build_object('ok', false, 'msg',
--       format('%s item(ns) já marcado(s). Desmarque antes de desfazer a triagem.', v_marcados));
--   end if;
--
--   delete from public.ra_itens where caso_id = p_caso;
--
--   v_avisou := v_caso.slack_ts is not null
--               and (v_caso.slack_avisos ? 'liberado' or v_caso.slack_avisos ? 'fechado' or v_caso.slack_avisos ? 'ajuste');
--   update public.ra_casos
--      set status = 'aguardando_triagem', triado_por = null, triado_em = null,
--          decisao_obs = null, concluido_em = null, decisao = null,
--          expiracao_atual = null, expiracao_antiga = null, instrucao_atual = null, instrucao_antiga = null,
--          slack_avisos = (slack_avisos - 'liberado' - 'fechado' - 'ajuste' - 'concluido')
--                         || case when v_avisou then '{"desfazer_pendente": true}'::jsonb else '{}'::jsonb end
--    where id = p_caso;
--
--   insert into public.ra_historico (caso_id, acao, por, detalhe)
--   values (p_caso, 'triagem_desfeita', v_uid, jsonb_build_object('status_anterior', v_caso.status));
--   return json_build_object('ok', true, 'msg', 'Triagem desfeita. O caso voltou para aguardando triagem.');
-- end $function$
-- ;
