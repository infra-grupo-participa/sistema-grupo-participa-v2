-- 20261006134133: Remoção de Acessos, linha ACELERA HOLDING (Hotmart, produto 8381847)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006134133_ensaio.sql (begin … rollback). Notas: 20261006134133.explain.md.
-- Aplicar ANTES da carga das 41 (20261006134134_ra_acelera_carga.sql), que depende desta.
--
-- O QUE FAZ
--   1. ra_casos ganha `linha` ('hm' | 'acelera', padrão 'hm') e `avisar_slack` (padrão true);
--      ra_itens_catalogo ganha `linha` (padrão 'hm'). Tudo o que já existe continua 'hm' e avisando.
--   2. Três itens novos do Acelera, todos do Thomas Henrique: Grupo de informes, Área de membros (Hotmart), Obvio.
--      Os itens do HM não mudam.
--   3. ra_criar_caso_acelera(p jsonb): reembolso/chargeback nasce `em_remocao` (decisao 'remover', sem triagem),
--      1 pessoa (titular, sem sócio, sem vínculo com aluno), os 3 itens criados, prazo de 1 dia útil como no HM.
--      Disputa/protesto: só `alerta`, sem itens. Reembolso/chargeback de quem ainda tem OUTRA compra válida do
--      Acelera (APPROVED/COMPLETE/COMPLETED, casando por e-mail, documento ou telefone, em fin.hotmart_transacoes e
--      public.compras) também vira só `alerta`, com o motivo e as transações válidas em sugestao (decisão do Victor).
--   4. ra_receber_hotmart aceita o 8381847 (vai para ra_criar_caso_acelera); o HM segue igual; o resto continua ignorado.
--   5. Reprocessa os eventos do 8381847 que o webhook já recebeu e ignorou antes desta migration
--      (o webhook do Acelera foi cadastrado na Hotmart em 06/10/2026). Viram casos novos com aviso normal no Slack.
--   6. ra_triar só cruza itens da linha 'hm' (crítico: senão o caso do HM ganharia os itens do Acelera);
--      ra_triar e ra_desfazer_triagem recusam caso do Acelera.
--   7. ra_fila, ra_caso e ra_responsaveis devolvem `linha`; ra_meu_papel devolve meus_itens como [{item, rotulo, linha}].
--   8. Slack: aviso `novo` do Acelera já pede a remoção e marca o responsável; `liberado` é só do HM; `concluido` do
--      Acelera só depois do `novo`; alerta diz Acelera Holding. Caso com avisar_slack = false não sai em
--      ra_slack_pendentes, nem no lembrete, nem chama o n8n (é o que a carga das 41 usa). Links passam a apontar
--      direto para /educacional/remocoes (o /relatorios/remocoes antigo continua redirecionando).
--
-- BASE: cada função recriada parte do corpo VIVO (pg_get_functiondef lido em 06/10/2026), conferido pelo md5 na guarda.
-- REVERSÃO: ver 20261006134133.explain.md, seção "Como desfazer".

set local lock_timeout = '5s';

-- ═══ 0. Guarda: o banco tem que estar como foi lido em 06/10/2026 ═══
do $guarda$
declare
  v_esperado jsonb := '{
    "public.ra_receber_hotmart(jsonb)": "9af9d16356ee125adc48983547edb1ff",
    "public.ra_triar(uuid,text,text,boolean,date,text)": "15bef586222239ed1aa683dd849600dc",
    "public.ra_desfazer_triagem(uuid)": "715a0ea41f568f37e25a837684fc8441",
    "public.ra_fila()": "f2f98cd40dfa3029e24083303ddac945",
    "public.ra_caso(uuid)": "f3d1e18aa23ae6a053448a2cafaf8f2d",
    "public.ra_responsaveis()": "5e0b00c839d0af1e728de663ea74682d",
    "public.ra_meu_papel()": "d5a839a2240f24e996b4c72b9657d703",
    "public.ra_slack_pendentes_base(text)": "3673f901dfbe9dcc61cd7842fbbfe477",
    "public.ra_slack_pendentes(text)": "36ac0451649303344242d27f86890445",
    "public.ra_slack_lembrete(text)": "bf6110bf8f2d005085240304cf50c492",
    "public.ra_fn_avisar_n8n()": "ae11798179fc50696cf98ab85d879454"
  }';
  k text; v text;
begin
  for k, v in select * from jsonb_each_text(v_esperado) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v then
      raise exception '20261006134133: corpo vivo de % mudou desde 06/10/2026 (md5 diferente): reler e regerar', k;
    end if;
  end loop;
  if not exists (select 1 from public.perfis where id = '998e69ce-0c71-409f-b267-b8409889b640' and status = 'ativo') then
    raise exception '20261006134133: perfil do Thomas Henrique (998e69ce…) não existe ou não está ativo';
  end if;
end
$guarda$;

-- ═══ 1. Colunas novas ═══
alter table public.ra_casos add column linha text not null default 'hm';
alter table public.ra_casos add constraint ra_casos_linha_check check (linha in ('hm', 'acelera'));
alter table public.ra_casos add column avisar_slack boolean not null default true;
alter table public.ra_itens_catalogo add column linha text not null default 'hm';
alter table public.ra_itens_catalogo add constraint ra_itens_catalogo_linha_check check (linha in ('hm', 'acelera'));

comment on column public.ra_casos.linha is
  'Linha de produto do caso: hm (Holding Masters, com triagem) ou acelera (Acelera Holding, Hotmart 8381847, sem triagem).';
comment on column public.ra_casos.avisar_slack is
  'false = caso silencioso (carga de casos antigos): fora de ra_slack_pendentes, do lembrete e do gatilho do n8n.';
comment on column public.ra_itens_catalogo.linha is
  'Linha de produto do item: hm ou acelera. ra_triar só cruza itens hm; o caso do Acelera recebe os itens acelera.';

-- ═══ 2. Itens do Acelera (responsável: Thomas Henrique) ═══
insert into public.ra_itens_catalogo (item, rotulo, responsavel_id, ordem, so_programa, ativo, fluxo, linha) values
  ('acelera_grupo_informes', 'Grupo de informes',         '998e69ce-0c71-409f-b267-b8409889b640', 210, false, true, 'remocao', 'acelera'),
  ('acelera_area_membros',   'Área de membros (Hotmart)', '998e69ce-0c71-409f-b267-b8409889b640', 220, false, true, 'remocao', 'acelera'),
  ('acelera_obvio',          'Obvio',                     '998e69ce-0c71-409f-b267-b8409889b640', 230, false, true, 'remocao', 'acelera');

-- ═══ 3. Outra compra válida do Acelera (uma regra só: o webhook e a carga usam esta) ═══
-- Devolve as transações APPROVED/COMPLETE/COMPLETED do 8381847, diferentes de p_transacao, da mesma pessoa
-- (e-mail igual; ou documento com 11+ dígitos igual; ou telefone com 10+ dígitos igual, com ou sem o 55 na frente).
create or replace function public.ra_acelera_compras_validas(p_transacao text, p_email text, p_documento text, p_telefone text)
returns text[] language sql stable security definer set search_path to 'public' as $$
  with k as (
    select lower(trim(coalesce(p_email, ''))) as em,
           regexp_replace(coalesce(p_documento, ''), '\D', '', 'g') as doc,
           regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g') as fone
  ), cand as (
    select h.transacao, h.comprador_email as em, h.comprador_documento as doc, h.comprador_telefone as fone
      from (select * from fin.hotmart_transacoes where conta = 'academy') h  -- forma exigida pela trava de conta; o Acelera é da conta academy
     where h.produto_id = '8381847' and upper(h.status) in ('APPROVED', 'COMPLETE', 'COMPLETED')
    union all
    select c.hotmart_transaction::text, b.email, b.documento, b.telefone
      from public.compras c left join public.compradores b on b.id = c.comprador_id
     where c.produto_id = '8381847' and upper(c.status) in ('APPROVED', 'COMPLETE', 'COMPLETED')
  ), cand_n as (
    select x.transacao, lower(trim(coalesce(x.em, ''))) as em,
           regexp_replace(coalesce(x.doc, ''), '\D', '', 'g') as doc,
           regexp_replace(coalesce(x.fone, ''), '\D', '', 'g') as fone
      from cand x
  )
  select coalesce(array_agg(distinct c.transacao order by c.transacao), '{}'::text[])
    from cand_n c, k
   where c.transacao is distinct from p_transacao
     and ((k.em <> '' and c.em = k.em)
          or (length(k.doc) >= 11 and c.doc = k.doc)
          or (length(k.fone) >= 10 and length(c.fone) >= 10
              and (c.fone = k.fone or c.fone = '55' || k.fone or '55' || c.fone = k.fone)));
$$;

-- ═══ 4. Criação do caso do Acelera ═══
-- p: transacao, tipo (reembolso|chargeback|disputa), produto_nome, oferta, valor, nome, email, telefone, documento,
--    ocorrido_em, teste, origem (webhook|carga), avisar_slack (padrão true), com_prazo (padrão true), motivo, detalhe.
create or replace function public.ra_criar_caso_acelera(p jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_tipo text := p->>'tipo';
  v_transacao text := nullif(trim(coalesce(p->>'transacao', '')), '');
  v_quando timestamptz := coalesce(nullif(p->>'ocorrido_em', '')::timestamptz, now());
  v_origem text := coalesce(nullif(p->>'origem', ''), 'webhook');
  v_avisar boolean := coalesce((p->>'avisar_slack')::boolean, true);
  v_com_prazo boolean := coalesce((p->>'com_prazo')::boolean, true);
  v_teste boolean := coalesce((p->>'teste')::boolean, false);
  v_validas text[] := '{}';
  v_status text;
  v_decisao text;
  v_prazo timestamptz;
  v_sugestao jsonb;
  v_caso uuid;
  v_pessoa uuid;
begin
  if v_tipo is null or v_tipo not in ('reembolso', 'chargeback', 'disputa') then
    raise exception 'ra_criar_caso_acelera: tipo inválido (%)', coalesce(v_tipo, 'nulo');
  end if;
  if v_transacao is null then
    raise exception 'ra_criar_caso_acelera: transação vazia';
  end if;

  if v_tipo = 'disputa' then
    v_status := 'alerta';
    v_sugestao := jsonb_build_object(
      'motivo', 'Disputa aberta na Hotmart no Acelera Holding. Ainda não é reembolso nem chargeback: nada a remover por enquanto.',
      'compras_validas', '[]'::jsonb);
  else
    v_validas := public.ra_acelera_compras_validas(v_transacao, p->>'email', p->>'documento', p->>'telefone');
    if cardinality(v_validas) > 0 then
      v_status := 'alerta';
      v_sugestao := jsonb_build_object(
        'motivo', initcap(v_tipo) || ' no Acelera Holding, mas a pessoa ainda tem outra compra válida do Acelera Holding '
                  || '(aprovada ou completa): ' || array_to_string(v_validas, ', ')
                  || '. Não abrimos o checklist de remoção: confira antes de remover qualquer acesso.',
        'recompra', true,
        'compras_validas', to_jsonb(v_validas));
    else
      v_status := 'em_remocao';
      v_decisao := 'remover';
      v_prazo := case when v_com_prazo then public.ra_calcular_prazo(v_quando) end;
      v_sugestao := jsonb_build_object(
        'recomendacao', 'remover',
        'motivo', coalesce(nullif(p->>'motivo', ''),
                           initcap(v_tipo) || ' no Acelera Holding sem outra compra válida do Acelera: remover do Grupo de informes, '
                           || 'da Área de membros (Hotmart) e do Obvio.'),
        'compras_validas', '[]'::jsonb);
    end if;
  end if;

  insert into public.ra_casos (
    compra_id, hotmart_transaction, tipo, status, produto_nome, oferta_codigo, valor,
    comprador_id, aluno_id, nome, email, telefone, documento, ocorrido_em, prazo_em,
    eh_programa, sugestao, teste, origem, decisao, linha, avisar_slack)
  values (
    null, v_transacao, v_tipo, v_status, coalesce(nullif(p->>'produto_nome', ''), 'Acelera Holding'),
    nullif(p->>'oferta', ''), nullif(p->>'valor', '')::numeric,
    null, null, nullif(trim(coalesce(p->>'nome', '')), ''), nullif(trim(coalesce(p->>'email', '')), ''),
    nullif(trim(coalesce(p->>'telefone', '')), ''), nullif(trim(coalesce(p->>'documento', '')), ''),
    v_quando, v_prazo, false, v_sugestao, v_teste, v_origem, v_decisao, 'acelera', v_avisar)
  on conflict (hotmart_transaction, tipo) do nothing
  returning id into v_caso;

  if v_caso is null then return null; end if;

  insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
  values (v_caso, null, nullif(trim(coalesce(p->>'nome', '')), ''), nullif(trim(coalesce(p->>'email', '')), ''), 'titular', 0)
  returning id into v_pessoa;

  if v_status = 'em_remocao' then
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select v_caso, v_pessoa, c.item, c.responsavel_id
      from public.ra_itens_catalogo c
     where c.ativo and c.fluxo = 'remocao' and c.linha = 'acelera'
    on conflict (pessoa_id, item) do nothing;
  end if;

  insert into public.ra_historico (caso_id, acao, detalhe)
  values (v_caso, 'aberto', coalesce(p->'detalhe', '{}'::jsonb)
                            || jsonb_build_object('tipo', v_tipo, 'origem', v_origem, 'teste', v_teste, 'linha', 'acelera',
                                                  'status_inicial', v_status, 'avisar_slack', v_avisar,
                                                  'compras_validas', to_jsonb(v_validas)));
  return v_caso;
end $$;

-- Payload do webhook da Hotmart → ra_criar_caso_acelera. Usado pelo webhook e pelo reprocessamento abaixo.
create or replace function public.ra_acelera_de_payload(p_payload jsonb, p_teste boolean, p_recebido_em timestamptz)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_evento text := coalesce(p_payload->>'event', '');
  v_d jsonb := coalesce(p_payload->'data', '{}'::jsonb);
  v_ms bigint := nullif(p_payload->>'creation_date', '')::bigint;
  v_tipo text := case v_evento
                   when 'PURCHASE_REFUNDED' then 'reembolso'
                   when 'PURCHASE_CHARGEBACK' then 'chargeback'
                   when 'PURCHASE_PROTEST' then 'disputa'
                   else null end;
begin
  if v_tipo is null or nullif(trim(v_d->'purchase'->>'transaction'), '') is null then return null; end if;
  return public.ra_criar_caso_acelera(jsonb_build_object(
    'transacao', trim(v_d->'purchase'->>'transaction'),
    'tipo', v_tipo,
    'produto_nome', v_d->'product'->>'name',
    'oferta', v_d->'purchase'->'offer'->>'code',
    'valor', v_d->'purchase'->'price'->>'value',
    'nome', v_d->'buyer'->>'name',
    'email', v_d->'buyer'->>'email',
    'telefone', nullif(trim(coalesce(v_d->'buyer'->>'checkout_phone_code', '') || coalesce(v_d->'buyer'->>'checkout_phone', '')), ''),
    'documento', v_d->'buyer'->>'document',
    'ocorrido_em', case when v_ms is not null then to_timestamp(v_ms / 1000.0) else coalesce(p_recebido_em, now()) end,
    'teste', coalesce(p_teste, false),
    'origem', 'webhook',
    'detalhe', jsonb_build_object('evento', v_evento, 'status_compra', v_d->'purchase'->>'status',
                                  'produto_id', v_d->'product'->>'id')));
end $$;

revoke all on function public.ra_acelera_compras_validas(text, text, text, text) from public, anon, authenticated;
revoke all on function public.ra_criar_caso_acelera(jsonb) from public, anon, authenticated;
revoke all on function public.ra_acelera_de_payload(jsonb, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.ra_acelera_compras_validas(text, text, text, text) to service_role;
grant execute on function public.ra_criar_caso_acelera(jsonb) to service_role;
grant execute on function public.ra_acelera_de_payload(jsonb, boolean, timestamptz) to service_role;

-- ═══ 5. Webhook: aceita o Acelera (corpo vivo + o desvio do 8381847; o HM não muda) ═══
CREATE OR REPLACE FUNCTION public.ra_receber_hotmart(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_evento text := coalesce(p_payload->>'event', '');
  v_tipo text;
  v_d jsonb := coalesce(p_payload->'data', '{}'::jsonb);
  v_transacao text := nullif(trim(v_d->'purchase'->>'transaction'), '');
  v_produto text := nullif(v_d->'product'->>'id', '');
  v_modo text := coalesce((select valor from public.ra_config where chave = 'webhook_modo'), 'producao');
  v_compra public.compras%rowtype;
  v_teste boolean;
  v_quando timestamptz;
  v_ms bigint;
  v_caso uuid;
  v_resultado text;
  v_log bigint;
  v_fone text;
begin
  insert into public.ra_webhook_eventos (evento, transacao, produto_id, payload)
  values (v_evento, v_transacao, v_produto, p_payload)
  returning id into v_log;

  v_tipo := case v_evento
              when 'PURCHASE_REFUNDED' then 'reembolso'
              when 'PURCHASE_CHARGEBACK' then 'chargeback'
              when 'PURCHASE_PROTEST' then 'disputa'
              else null end;

  if v_tipo is null then
    v_resultado := 'ignorado: evento fora do escopo';
  elsif v_transacao is null then
    v_resultado := 'ignorado: sem transação';
  elsif coalesce(v_produto, '') = '8381847' then
    -- 20261006134133: Acelera Holding. Em modo teste, transação que a Hotmart nunca mandou para o financeiro
    -- vira caso de teste (e reenviar recria), igual ao HM.
    v_teste := v_modo = 'teste' and not exists (select 1 from fin.hotmart_transacoes where conta = 'academy' and transacao = v_transacao);
    if v_teste then
      delete from public.ra_casos where hotmart_transaction = v_transacao and tipo = v_tipo and teste;
    end if;
    v_caso := public.ra_acelera_de_payload(p_payload, v_teste, now());
    v_resultado := case when v_caso is null then 'já existia caso para esta transação'
                        when v_teste then 'caso de teste criado (Acelera Holding)' else 'caso criado (Acelera Holding)' end;
  else
    select * into v_compra from public.compras where hotmart_transaction = v_transacao;
    -- Teste = transação desconhecida OU produto 0, que é o produto fictício do teste
    -- da Hotmart (a transação dele, HP16015479281022, já está em compras desde 14/04
    -- por um teste antigo no webhook geral). Caso de teste não se liga a compra.
    v_teste := v_modo = 'teste' and (v_compra.id is null or coalesce(v_produto, '') = '0');
    if v_teste then v_compra := null; end if;

    if not v_teste and coalesce(v_produto, v_compra.produto_id, '') not in ('5064314', '3507214') then
      v_resultado := 'ignorado: produto não é Holding Masters';
    else
      -- Teste repetido com a mesma transação: refaz o caso de teste do zero.
      if v_teste then
        delete from public.ra_casos where hotmart_transaction = v_transacao and tipo = v_tipo and teste;
      end if;

      v_ms := nullif(p_payload->>'creation_date', '')::bigint;
      v_quando := case when v_ms is not null then to_timestamp(v_ms / 1000.0) else now() end;
      v_fone := nullif(trim(coalesce(v_d->'buyer'->>'checkout_phone_code', '') || coalesce(v_d->'buyer'->>'checkout_phone', '')), '');

      v_caso := public.ra_criar_caso(jsonb_build_object(
        'compra_id', v_compra.id,
        'transacao', v_transacao,
        'tipo', v_tipo,
        'produto_nome', coalesce(v_d->'product'->>'name', v_compra.produto_nome),
        'oferta', coalesce(v_d->'purchase'->'offer'->>'code', v_compra.oferta_codigo),
        'valor', coalesce(v_d->'purchase'->'price'->>'value', v_compra.preco::text),
        'comprador_id', v_compra.comprador_id,
        -- Com compra no banco, vale o cadastro do sistema (o nome do checkout às vezes é lixo).
        'nome', coalesce((select nome from public.compradores where id = v_compra.comprador_id), v_d->'buyer'->>'name'),
        'email', coalesce((select email from public.compradores where id = v_compra.comprador_id), v_d->'buyer'->>'email'),
        'telefone', v_fone,
        'documento', v_d->'buyer'->>'document',
        'ocorrido_em', v_quando,
        'teste', v_teste,
        'origem', 'webhook',
        'detalhe', jsonb_build_object('evento', v_evento, 'status_compra', v_d->'purchase'->>'status',
                                      'produto_id', v_produto)));
      v_resultado := case when v_caso is null then 'já existia caso para esta transação'
                          when v_teste then 'caso de teste criado' else 'caso criado' end;
    end if;
  end if;

  update public.ra_webhook_eventos set resultado = v_resultado, caso_id = v_caso where id = v_log;
  return jsonb_build_object('ok', true, 'resultado', v_resultado, 'caso', v_caso, 'teste', coalesce(v_teste, false));
end $function$;

-- ═══ 6. Triagem: só HM ═══
CREATE OR REPLACE FUNCTION public.ra_triar(p_caso uuid, p_decisao text, p_obs text DEFAULT NULL::text, p_programa boolean DEFAULT NULL::boolean, p_expiracao_antiga date DEFAULT NULL::date, p_instrucao_antiga text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_caso public.ra_casos%rowtype;
  v_aluno public.thb_alunos%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem decide este passo.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.linha <> 'hm' then
    return json_build_object('ok', false, 'msg', 'Caso do Acelera Holding não passa por triagem.');
  end if;
  if v_caso.status <> 'aguardando_triagem' then
    return json_build_object('ok', false, 'msg', 'Este caso já foi triado.');
  end if;
  if p_programa is not null and p_programa is distinct from v_caso.eh_programa then
    update public.ra_casos set eh_programa = p_programa where id = p_caso;
    v_caso.eh_programa := p_programa;
  end if;

  if p_decisao = 'manter' then
    if p_expiracao_antiga is null then
      return json_build_object('ok', false, 'msg', 'Informe a data de expiração antiga (a que volta a valer).');
    end if;
    if v_caso.aluno_id is not null then
      select * into v_aluno from public.thb_alunos where id = v_caso.aluno_id;
    end if;
    update public.ra_casos
       set status = 'ajustando_acesso', decisao = 'manter', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), ''),
           expiracao_atual = v_aluno.data_expiracao, expiracao_antiga = p_expiracao_antiga,
           instrucao_atual = v_aluno.instrucao,
           instrucao_antiga = nullif(trim(coalesce(p_instrucao_antiga, '')), '')
     where id = p_caso;
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select p_caso, p.id, c.item, c.responsavel_id
      from public.ra_pessoas p cross join public.ra_itens_catalogo c
     where p.caso_id = p_caso and c.ativo and c.fluxo = 'ajuste' and c.linha = 'hm'
    on conflict (pessoa_id, item) do nothing;
  elsif p_decisao = 'remover' then
    update public.ra_casos
       set status = 'em_remocao', decisao = 'remover', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), '')
     where id = p_caso;
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select p_caso, p.id, c.item, c.responsavel_id
      from public.ra_pessoas p cross join public.ra_itens_catalogo c
     where p.caso_id = p_caso and c.ativo and c.fluxo = 'remocao' and c.linha = 'hm' and (not c.so_programa or v_caso.eh_programa)
    on conflict (pessoa_id, item) do nothing;
  else
    return json_build_object('ok', false, 'msg', 'Decisão inválida.');
  end if;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem', v_uid, jsonb_build_object('decisao', p_decisao, 'obs', p_obs, 'programa', v_caso.eh_programa,
          'expiracao_antiga', p_expiracao_antiga, 'instrucao_antiga', p_instrucao_antiga));
  return json_build_object('ok', true, 'msg', case when p_decisao = 'manter'
    then 'Não remover: falta ajustar a expiração na Central e na Base de Alunos.'
    else 'Remoção liberada para os responsáveis.' end);
end $function$;

CREATE OR REPLACE FUNCTION public.ra_desfazer_triagem(p_caso uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

-- ═══ 7. Leitura da tela: linha do caso e do item ═══
CREATE OR REPLACE FUNCTION public.ra_fila()
 RETURNS SETOF json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := (select auth.uid()); v_doc boolean;
begin
  if not public.ra_pode_ver() then return; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  return query
    select to_json(x) from (
      select c.id, c.tipo, c.status, c.nome, c.email, c.produto_nome, c.oferta_codigo, c.valor,
             c.hotmart_transaction, c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.teste, c.origem, c.decisao, c.expiracao_antiga,
             c.linha,
             public.mask_sensivel(c.documento, v_doc) as documento,
             c.sugestao->>'recomendacao' as recomendacao,
             (select count(*) from public.ra_pessoas p where p.caso_id = c.id) as pessoas,
             (select count(*) from public.ra_itens i where i.caso_id = c.id) as itens_total,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao <> 'pendente') as itens_feitos,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao = 'pendente'
                and i.responsavel_id = v_uid) as meus_pendentes
        from public.ra_casos c
       order by case c.status when 'aguardando_triagem' then 0 when 'em_remocao' then 1 when 'ajustando_acesso' then 1 when 'alerta' then 2 else 3 end,
                c.prazo_em nulls last, c.ocorrido_em desc
    ) x;
end $function$;

CREATE OR REPLACE FUNCTION public.ra_caso(p_caso uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := (select auth.uid()); v_doc boolean; v_triador boolean;
begin
  if not public.ra_pode_ver() then return null; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  v_triador := public.ra_eh_triador();
  return (
    select json_build_object(
      'caso', (select to_json(y) from (
                 select c.id, c.tipo, c.status, c.nome, c.email, c.telefone,
                        public.mask_sensivel(c.documento, v_doc) as documento,
                        c.produto_nome, c.oferta_codigo, c.valor, c.hotmart_transaction,
                        c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.sugestao,
                        c.decisao_obs, c.triado_em, tp.nome as triado_por_nome, c.aluno_id, c.teste, c.origem, c.decisao,
                        c.expiracao_atual, c.expiracao_antiga, c.instrucao_atual, c.instrucao_antiga,
                        c.linha
                   from public.ra_casos c left join public.perfis tp on tp.id = c.triado_por
                  where c.id = p_caso) y),
      'pessoas', coalesce((select json_agg(json_build_object(
                    'id', p.id, 'nome', p.nome, 'email', p.email, 'papel', p.papel, 'aluno_id', p.aluno_id,
                    'itens', coalesce((select json_agg(json_build_object(
                                'id', i.id, 'item', i.item, 'rotulo', k.rotulo, 'situacao', i.situacao,
                                'responsavel', rp.nome, 'marcado_por', mp.nome, 'marcado_em', i.marcado_em,
                                'corrigido', i.corrigido, 'obs', i.obs, 'linha', k.linha,
                                'pode_marcar', (i.responsavel_id = v_uid or public.ra_pode_marcar_tudo())) order by k.ordem)
                              from public.ra_itens i
                              join public.ra_itens_catalogo k on k.item = i.item
                              left join public.perfis rp on rp.id = i.responsavel_id
                              left join public.perfis mp on mp.id = i.marcado_por
                             where i.pessoa_id = p.id), '[]'::json)) order by p.ordem)
                  from public.ra_pessoas p where p.caso_id = p_caso), '[]'::json),
      'historico', coalesce((select json_agg(json_build_object(
                      'acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em)
                    from public.ra_historico h left join public.perfis hp on hp.id = h.por
                   where h.caso_id = p_caso), '[]'::json),
      'pode_triar', v_triador
    )
  );
end $function$;

CREATE OR REPLACE FUNCTION public.ra_responsaveis()
 RETURNS SETOF json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.ra_pode_ver() then return; end if;
  return query
    select to_json(x) from (
      select c.item, c.rotulo, c.ordem, c.so_programa, c.fluxo, c.ativo, c.linha, c.responsavel_id, p.nome as responsavel, p.email
        from public.ra_itens_catalogo c left join public.perfis p on p.id = c.responsavel_id
       order by c.ordem) x;
end $function$;

-- meus_itens: era lista de rótulos; vira lista de {item, rotulo, linha} (o Thomas tem "Obvio" no HM e no Acelera).
CREATE OR REPLACE FUNCTION public.ra_meu_papel()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'pode_ver', public.ra_pode_ver(),
    'pode_triar', public.ra_eh_triador(),
    'pode_configurar', public.gp_is_admin(),
    'meus_itens', coalesce((select json_agg(json_build_object('item', c.item, 'rotulo', c.rotulo, 'linha', c.linha) order by c.ordem)
                              from public.ra_itens_catalogo c
                             where c.ativo and c.responsavel_id = (select auth.uid())), '[]'::json));
$function$;

-- ═══ 8. Slack ═══
CREATE OR REPLACE FUNCTION public.ra_slack_pendentes_base(p_segredo text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_out json;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;

  with base as (
    select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
           to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
           '<' || v_url || '/educacional/remocoes?caso=' || c.id || '|Abrir no sistema>' as link
      from public.ra_casos c
     where c.avisar_slack  -- 20261006134133: caso silencioso (carga) nunca vai para o Slack
  ),
  msgs as (
    -- Disputa: só alerta, marca o triador.
    select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts, 1 as ordem,
           ':warning: *Disputa aberta no HM*' || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || 'Ainda não é reembolso nem chargeback.' || E'\n' || b.link as texto
      from base b where b.linha = 'hm' and b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Acelera Holding: alerta (disputa, ou reembolso/chargeback de quem ainda tem outra compra válida). Marca o triador.
    select b.id, 'alerta', null, 1,
           case when b.tipo = 'disputa'
                then ':warning: *Disputa aberta no Acelera Holding*'
                else ':warning: *' || initcap(b.tipo) || ' no Acelera Holding: a pessoa ainda tem outra compra válida do Acelera Holding*' end
           || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || case when b.tipo = 'disputa'
                   then 'Ainda não é reembolso nem chargeback.'
                   else 'Outras compras válidas: '
                        || coalesce((select string_agg(v, ', ') from jsonb_array_elements_text(b.sugestao->'compras_validas') v), 'sem detalhe')
                        || E'\n' || 'Não abrimos o checklist de remoção: confira antes de remover qualquer acesso.' end
           || E'\n' || b.link
      from base b where b.linha = 'acelera' and b.status = 'alerta' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo do HM: marca só o triador.
    select b.id, 'novo', null, 1,
           ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente*' || E'\n'
           || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then E'\n' || 'Programa de Implementação' else '' end || E'\n\n'
           || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || coalesce(b.sugestao->>'motivo', '') || E'\n\n'
           || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n' || b.link
      from base b where b.linha = 'hm' and b.tipo <> 'disputa' and not (b.slack_avisos ? 'novo')
    union all
    -- Caso novo do Acelera Holding: já é a remoção (sem triagem). Marca quem remove.
    select b.id, 'novo', null, 1,
           ':scissors: *Reembolso/Chargeback no Acelera Holding: remover do Grupo de informes, da Área de membros (Hotmart) e do Obvio*'
           || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || initcap(b.tipo) || ' · ' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
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
                    and b.slack_ts is not null and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído. HM: depois do liberado/ajuste. Acelera: depois do novo.
    select b.id, 'concluido', b.slack_ts, 3,
           case when b.decisao = 'manter' then ':white_check_mark: *Acesso ajustado*' else ':white_check_mark: *Acessos removidos*' end || E'\n\n'
           || (select string_agg('• ' || linha, E'\n') from (
                 select coalesce(mp.nome, 'sem nome') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
                   from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
                  where i.caso_id = b.id
                  group by mp.nome) z)
      from base b where b.status = 'concluido' and b.slack_ts is not null and not (b.slack_avisos ? 'concluido')
                    and ((b.linha = 'hm' and (b.slack_avisos ? 'liberado' or b.slack_avisos ? 'ajuste'))
                         or (b.linha = 'acelera' and b.slack_avisos ? 'novo'))
  )
  select json_build_object('ok', true, 'mensagens',
           coalesce(json_agg(json_build_object('caso_id', m.caso_id, 'aviso', m.aviso,
                                               'thread_ts', m.thread_ts, 'texto', m.texto) order by m.ordem), '[]'::json))
    into v_out from msgs m;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION public.ra_slack_pendentes(p_segredo text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_base json;
begin
  v_base := public.ra_slack_pendentes_base(p_segredo);
  if coalesce((v_base->>'ok')::boolean, false) is not true then return v_base; end if;
  return json_build_object('ok', true, 'mensagens', coalesce((
    select json_agg(x order by ord) from (
      -- Desfeita vem antes: numa triagem refeita no mesmo tick, a ordem na thread fica certa.
      select json_build_object('caso_id', c.id, 'aviso', 'desfeito', 'thread_ts', c.slack_ts,
               'texto', ':leftwards_arrow_with_hook: *Triagem desfeita.* O caso voltou para aguardando triagem; desconsiderem o aviso anterior.') x, 0 as ord
        from public.ra_casos c
       where c.slack_avisos ? 'desfazer_pendente' and c.slack_ts is not null and c.avisar_slack
      union all
      select json_build_object(
               'caso_id', m->>'caso_id', 'aviso', m->>'aviso', 'thread_ts', m->>'thread_ts',
               'texto', case when c.teste and m->>'thread_ts' is null
                             then ':test_tube: *TESTE (webhook da remoção de acessos)*' || E'\n' || (m->>'texto')
                             else m->>'texto' end), 1
        from json_array_elements(v_base->'mensagens') m
        join public.ra_casos c on c.id = (m->>'caso_id')::uuid
    ) t), '[]'::json));
end $function$;

CREATE OR REPLACE FUNCTION public.ra_slack_lembrete(p_segredo text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_casos int;
  v_atrasados int;
  v_corpo text;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'texto', null); end if;

  select count(*), count(*) filter (where prazo_em < now())
    into v_casos, v_atrasados
    from public.ra_casos where status in ('aguardando_triagem', 'em_remocao', 'ajustando_acesso') and avisar_slack;
  if v_casos = 0 then return json_build_object('ok', true, 'texto', null); end if;

  with pend as (
    -- Uma linha por (responsável, caso, pessoa) com os itens que faltam.
    select i.responsavel_id, c.id caso_id, c.prazo_em, c.teste, p.ordem pordem,
           coalesce(p.nome, 'sem nome') || case when p.papel = 'socio' then ' (sócio)' else '' end as pessoa,
           case when c.decisao = 'manter'
                then 'voltar a expiração para ' || coalesce(to_char(c.expiracao_antiga, 'DD/MM/YYYY'), 'a data antiga')
                     || ' (' || string_agg(case k.item when 'ajuste_central' then 'Central' else 'Base de Alunos' end, ' e ' order by k.ordem) || ')'
                else string_agg(k.rotulo, ', ' order by k.ordem) end itens, min(k.ordem) kordem,
           c.linha as linha_prod
      from public.ra_itens i
      join public.ra_casos c on c.id = i.caso_id and c.status in ('em_remocao', 'ajustando_acesso') and c.avisar_slack
      join public.ra_pessoas p on p.id = i.pessoa_id
      join public.ra_itens_catalogo k on k.item = i.item
     where i.situacao = 'pendente'
     group by i.responsavel_id, c.id, c.prazo_em, c.teste, c.decisao, c.expiracao_antiga, c.linha, p.id, p.ordem, p.nome, p.papel
    union all
    -- Triagem pendente: conta para o triador, uma linha por caso (titular).
    select v_triador, c.id, c.prazo_em, c.teste, 0,
           coalesce(c.nome, 'sem nome'), 'triagem', 0, c.linha as linha_prod
      from public.ra_casos c where c.status = 'aguardando_triagem' and c.avisar_slack
  ), linhas as (
    select responsavel_id, prazo_em, caso_id, pordem, kordem,
           '• <' || v_url || '/educacional/remocoes?caso=' || caso_id || '|' || pessoa || '>: '
           || regexp_replace(itens, ', ([^,]*)$', ' e \1')
           || case when linha_prod = 'acelera' then ' · Acelera Holding' else '' end
           || case when prazo_em < now() then ' · :red_circle: atrasado'
                   when (prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje
                     then ' · :large_yellow_circle: vence hoje ' || to_char(prazo_em at time zone 'America/Sao_Paulo', 'HH24:MI')
                   else ' · prazo ' || coalesce(to_char(prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), 'sem prazo') end
           || case when teste then ' · teste' else '' end as linha
      from pend
  ), por_resp as (
    select responsavel_id, min(kordem) kordem,
           public.ra_slack_marca(responsavel_id) || E'\n'
           || string_agg(linha, E'\n' order by prazo_em nulls last, caso_id, pordem) as bloco
      from linhas group by responsavel_id
  )
  -- Linha em branco dupla entre responsáveis, para cada bloco ficar separado.
  select string_agg(bloco, E'\n\n\n' order by kordem) into v_corpo from por_resp;

  return json_build_object('ok', true, 'texto',
    ':alarm_clock: *Remoção de acessos: ' || v_casos || ' caso(s) em aberto'
    || case when v_atrasados > 0 then ', ' || v_atrasados || ' atrasado(s)' else '' end || '*'
    || E'\n\n' || coalesce(v_corpo, 'Nada pendente.'));
end $function$;

CREATE OR REPLACE FUNCTION public.ra_fn_avisar_n8n()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_url text;
begin
  -- 20261006134133: caso silencioso (carga) não chama o n8n.
  if not new.avisar_slack then return new; end if;
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.decisao is not distinct from old.decisao
     and not (new.slack_avisos ? 'desfazer_pendente' and not (old.slack_avisos ? 'desfazer_pendente'))
     and not (new.slack_ts is not null and old.slack_ts is null) then
    return new;
  end if;
  select valor into v_url from public.ra_config where chave = 'n8n_webhook_url';
  if v_url is null then return new; end if;
  begin
    perform net.http_post(url := v_url,
                          body := jsonb_build_object('caso', new.id, 'status', new.status),
                          headers := '{"Content-Type": "application/json"}'::jsonb,
                          timeout_milliseconds := 10000);
  exception when others then
    raise warning 'ra_fn_avisar_n8n: %', sqlerrm;
  end;
  return new;
end $function$;

-- ═══ 9. Reprocessa o que o webhook recebeu do Acelera antes desta migration ═══
-- Eventos do 8381847 gravados como "ignorado: produto não é Holding Masters" viram casos (aviso normal no Slack).
-- Mesma transação + tipo nunca duplica (unique de ra_casos): Hotmart reenviando o mesmo evento vira "já existia".
do $reprocessa$
declare
  r record;
  v_caso uuid;
  v_tipo text;
  n_criados int := 0;
  n_existentes int := 0;
  n_sem_tipo int := 0;
begin
  for r in
    select e.id, e.evento, e.transacao, e.payload, e.recebido_em
      from public.ra_webhook_eventos e
     where e.produto_id = '8381847' and e.resultado = 'ignorado: produto não é Holding Masters'
     order by e.id
  loop
    v_tipo := case r.evento when 'PURCHASE_REFUNDED' then 'reembolso' when 'PURCHASE_CHARGEBACK' then 'chargeback'
                            when 'PURCHASE_PROTEST' then 'disputa' else null end;
    if v_tipo is null or r.transacao is null then n_sem_tipo := n_sem_tipo + 1; continue; end if;
    v_caso := public.ra_acelera_de_payload(r.payload, false, r.recebido_em);
    if v_caso is not null then
      n_criados := n_criados + 1;
      update public.ra_webhook_eventos
         set resultado = 'reprocessado em 20261006134133: caso criado (Acelera Holding)', caso_id = v_caso
       where id = r.id;
    else
      n_existentes := n_existentes + 1;
      update public.ra_webhook_eventos
         set resultado = 'reprocessado em 20261006134133: já existia caso para esta transação',
             caso_id = (select c.id from public.ra_casos c where c.hotmart_transaction = r.transacao and c.tipo = v_tipo)
       where id = r.id;
    end if;
  end loop;
  raise notice '20261006134133 reprocessamento Acelera: % caso(s) criado(s), % já existia(m), % fora do escopo',
    n_criados, n_existentes, n_sem_tipo;
end
$reprocessa$;

-- ═══ 10. Conferência ═══
do $confere$
begin
  if (select count(*) from public.ra_itens_catalogo where linha = 'acelera') <> 3
     or exists (select 1 from public.ra_itens_catalogo where linha = 'acelera'
                 and responsavel_id is distinct from '998e69ce-0c71-409f-b267-b8409889b640') then
    raise exception '20261006134133: itens do Acelera não ficaram 3 do Thomas';
  end if;
  if exists (select 1 from public.ra_itens_catalogo where linha <> 'hm' and item not like 'acelera\_%') then
    raise exception '20261006134133: item do HM mudou de linha';
  end if;
  if has_function_privilege('anon', 'public.ra_criar_caso_acelera(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.ra_criar_caso_acelera(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.ra_acelera_de_payload(jsonb,boolean,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.ra_acelera_de_payload(jsonb,boolean,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.ra_acelera_compras_validas(text,text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.ra_acelera_compras_validas(text,text,text,text)', 'execute') then
    raise exception '20261006134133: função nova do Acelera executável por anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.ra_criar_caso_acelera(jsonb)', 'execute') then
    raise exception '20261006134133: service_role sem execute em ra_criar_caso_acelera';
  end if;
  if position('c.linha = ''hm''' in pg_get_functiondef('public.ra_triar(uuid,text,text,boolean,date,text)'::regprocedure)) = 0 then
    raise exception '20261006134133: ra_triar sem o filtro de linha hm';
  end if;
end
$confere$;
