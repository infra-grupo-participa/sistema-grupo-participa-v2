-- =====================================================================
-- 20260916_remocao_acessos_webhook
-- Webhook próprio da Remoção de Acessos (Edge Function remocao-acessos-webhook).
--
-- Pedido do Victor (16/09/2026): testar com dados da Hotmart sem passar pelo
-- webhook geral, que grava compra, mexe no financeiro e avisa o canal do time.
--
-- • A Hotmart manda reembolso/chargeback/protesto do HM direto para cá.
-- • O caso nasce do PAYLOAD. Se a transação já existe em compras, ela é ligada.
-- • O gatilho em compras continua como rede de segurança: o que chegar pelos
--   dois caminhos vira um caso só (unique transação + tipo).
-- • ra_config.webhook_modo = 'teste': caso cuja transação não existe em compras
--   (ou do produto 0, o de teste da Hotmart) nasce marcado como TESTE (aceita qualquer produto, aparece com selo, pode ser
--   apagado, e o Slack avisa que é teste). Em 'producao', só HM e nada é teste.
-- =====================================================================

alter table public.ra_casos alter column compra_id drop not null;
alter table public.ra_casos add column if not exists teste boolean not null default false;
alter table public.ra_casos add column if not exists origem text not null default 'compras';

create table if not exists public.ra_webhook_eventos (
  id bigserial primary key,
  recebido_em timestamptz not null default now(),
  evento text,
  transacao text,
  produto_id text,
  resultado text,
  caso_id uuid,
  payload jsonb not null
);
create index if not exists idx_ra_webhook_eventos_em on public.ra_webhook_eventos (recebido_em desc);
alter table public.ra_webhook_eventos enable row level security;
revoke all on public.ra_webhook_eventos from anon, authenticated;

insert into public.ra_config (chave, valor) values ('webhook_modo', 'teste')
on conflict (chave) do nothing;

-- ---------------------------------------------------------------------
-- Sugestão: agora também para caso sem compra no banco (dados do payload).
-- ---------------------------------------------------------------------
drop function if exists public.ra_montar_sugestao(uuid, uuid);
create or replace function public.ra_montar_sugestao(
  p_compra_id uuid, p_aluno_id uuid,
  p_email text default null, p_documento text default null, p_data timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_compra public.compras%rowtype;
  v_comprador public.compradores%rowtype;
  v_email text;
  v_doc text;
  v_data timestamptz;
  v_aluno public.thb_alunos%rowtype;
  v_turma text;
  v_anteriores jsonb;
  v_historico jsonb := '[]'::jsonb;
  v_aluno_json jsonb;
  v_recomendacao text;
  v_motivo text;
begin
  if p_compra_id is not null then
    select * into v_compra from public.compras where id = p_compra_id;
    select * into v_comprador from public.compradores where id = v_compra.comprador_id;
  end if;
  v_email := lower(trim(coalesce(v_comprador.email, p_email, '')));
  v_doc := regexp_replace(coalesce(v_comprador.documento, p_documento, ''), '\D', '', 'g');
  v_data := coalesce(v_compra.data_compra, p_data, now());

  -- Outras compras que dão acesso ao THB (HM e Aurum; ingresso de HT não conta).
  select coalesce(jsonb_agg(jsonb_build_object(
           'transacao', c.hotmart_transaction, 'produto', c.produto_nome, 'oferta', c.oferta_codigo,
           'valor', c.preco, 'status', c.status, 'data', c.data_compra) order by c.data_compra), '[]'::jsonb)
    into v_anteriores
    from public.compras c
    join public.compradores cp on cp.id = c.comprador_id
   where c.id is distinct from p_compra_id
     and c.status in ('APPROVED', 'COMPLETED', 'COMPLETE')
     and c.produto_id in ('5064314', '3507214', '3094405')
     and ((v_compra.comprador_id is not null and c.comprador_id = v_compra.comprador_id)
          or (v_email <> '' and lower(trim(cp.email)) = v_email)
          or (length(v_doc) >= 11 and regexp_replace(coalesce(cp.documento, ''), '\D', '', 'g') = v_doc));

  if p_aluno_id is not null then
    select * into v_aluno from public.thb_alunos where id = p_aluno_id;
    select t.codigo into v_turma from public.thb_turmas t where t.id = v_aluno.turma_id;
    v_aluno_json := jsonb_build_object(
      'instrucao', v_aluno.instrucao, 'espaco', v_aluno.espaco_instrucao, 'turma', v_turma,
      'data_expiracao', v_aluno.data_expiracao, 'data_entrada_thb', v_aluno.data_entrada_thb,
      'status_central', v_aluno.status_acesso_central, 'eh_socio', v_aluno.eh_socio);
    select coalesce(jsonb_agg(jsonb_build_object('de', l.valor_anterior, 'para', l.valor_novo,
             'origem', l.origem, 'em', l.criado_em) order by l.criado_em desc), '[]'::jsonb)
      into v_historico
      from (select * from public.thb_alunos_audit_log
             where aluno_id = p_aluno_id and campo = 'data_expiracao'
             order by criado_em desc limit 5) l;
  end if;

  if jsonb_array_length(v_anteriores) > 0
     or (v_aluno.data_entrada_thb is not null
         and v_aluno.data_entrada_thb < (v_data at time zone 'America/Sao_Paulo')::date) then
    v_recomendacao := 'verificar';
    v_motivo := 'Já era aluno antes desta compra: conferir se o acesso antigo ainda vale hoje.';
  elsif p_aluno_id is null then
    v_recomendacao := 'remover';
    v_motivo := 'Não há aluno na base nem outra compra de HM ou Aurum no sistema.';
  else
    v_recomendacao := 'remover';
    v_motivo := 'Entrou por esta compra e não há outra compra de HM ou Aurum no sistema.';
  end if;

  return jsonb_build_object(
    'recomendacao', v_recomendacao,
    'motivo', v_motivo,
    'compras_anteriores', v_anteriores,
    'aluno', v_aluno_json,
    'historico_expiracao', v_historico,
    'aviso', 'O histórico de compras do sistema começa em 13/03/2026. Compras anteriores estão na Central (planilha).'
  );
end $$;

-- ---------------------------------------------------------------------
-- Núcleo: cria o caso a partir de um conjunto de dados, venha de onde vier.
-- p: compra_id, transacao, tipo, produto_nome, oferta, valor, comprador_id,
--    nome, email, telefone, documento, ocorrido_em, teste, origem, detalhe
-- ---------------------------------------------------------------------
create or replace function public.ra_criar_caso(p jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_tipo text := p->>'tipo';
  v_comprador uuid := nullif(p->>'comprador_id', '')::uuid;
  v_email text := lower(trim(coalesce(p->>'email', '')));
  v_doc text := regexp_replace(coalesce(p->>'documento', ''), '\D', '', 'g');
  v_quando timestamptz := coalesce(nullif(p->>'ocorrido_em', '')::timestamptz, now());
  v_titular public.thb_alunos%rowtype;
  v_caso uuid;
  v_ordem int := 1;
  r record;
begin
  -- Titular: pelo comprador, depois e-mail, depois documento.
  select a.* into v_titular
    from public.thb_alunos a
   where (v_comprador is not null and a.comprador_id = v_comprador)
      or (v_email <> '' and lower(trim(a.email)) = v_email)
      or (length(v_doc) >= 11 and regexp_replace(coalesce(a.documento, ''), '\D', '', 'g') = v_doc)
   order by (a.comprador_id is not distinct from v_comprador and v_comprador is not null) desc,
            (coalesce(a.status_acesso_central, '') in ('Ativo','Ativo (cortesia)','A vencer','Vencido','Acompanha titular','Verificar')) desc,
            a.eh_socio asc nulls first
   limit 1;

  insert into public.ra_casos (
    compra_id, hotmart_transaction, tipo, status, produto_nome, oferta_codigo, valor,
    comprador_id, aluno_id, nome, email, telefone, documento, ocorrido_em, prazo_em,
    eh_programa, sugestao, teste, origem)
  values (
    nullif(p->>'compra_id', '')::uuid, p->>'transacao', v_tipo,
    case when v_tipo = 'disputa' then 'alerta' else 'aguardando_triagem' end,
    p->>'produto_nome', p->>'oferta', nullif(p->>'valor', '')::numeric,
    v_comprador, v_titular.id,
    coalesce(v_titular.nome, p->>'nome'), coalesce(nullif(p->>'email', ''), v_titular.email),
    coalesce(nullif(p->>'telefone', ''), v_titular.telefone), coalesce(nullif(p->>'documento', ''), v_titular.documento),
    v_quando,
    case when v_tipo = 'disputa' then null else public.ra_calcular_prazo(v_quando) end,
    -- Programa de Implementação = espaço do titular na base (ajustável na triagem).
    coalesce(v_titular.espaco_instrucao = 'holding_masters_implementacao', false),
    public.ra_montar_sugestao(nullif(p->>'compra_id', '')::uuid, v_titular.id, p->>'email', p->>'documento', v_quando),
    coalesce((p->>'teste')::boolean, false),
    coalesce(p->>'origem', 'compras'))
  on conflict (hotmart_transaction, tipo) do nothing
  returning id into v_caso;

  if v_caso is null then return null; end if;

  insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
  values (v_caso, v_titular.id, coalesce(v_titular.nome, p->>'nome'),
          coalesce(v_titular.email, p->>'email'), 'titular', 0);

  if v_titular.id is not null then
    for r in
      select s.id, s.nome, s.email
        from public.thb_alunos s
       where s.id <> v_titular.id
         and coalesce(s.status_acesso_central, '') in ('Ativo','Ativo (cortesia)','A vencer','Vencido','Acompanha titular','Verificar')
         and (s.socio_de_aluno_id = v_titular.id
              or (s.eh_socio and s.socio_de_aluno_id is null
                  and lower(trim(coalesce(s.socio_de_nome, ''))) = lower(trim(v_titular.nome))))
       order by s.nome
    loop
      insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
      values (v_caso, r.id, r.nome, r.email, 'socio', v_ordem);
      v_ordem := v_ordem + 1;
    end loop;
  end if;

  insert into public.ra_historico (caso_id, acao, detalhe)
  values (v_caso, 'aberto', coalesce(p->'detalhe', '{}'::jsonb)
                            || jsonb_build_object('tipo', v_tipo, 'origem', coalesce(p->>'origem', 'compras'),
                                                  'teste', coalesce((p->>'teste')::boolean, false)));
  return v_caso;
end $$;

-- Caminho do gatilho em compras: monta os dados a partir da compra.
create or replace function public.ra_abrir_caso(p_compra_id uuid, p_tipo text)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_compra public.compras%rowtype;
  v_comprador public.compradores%rowtype;
begin
  select * into v_compra from public.compras where id = p_compra_id;
  if not found then return null; end if;
  select * into v_comprador from public.compradores where id = v_compra.comprador_id;
  return public.ra_criar_caso(jsonb_build_object(
    'compra_id', v_compra.id, 'transacao', v_compra.hotmart_transaction, 'tipo', p_tipo,
    'produto_nome', v_compra.produto_nome, 'oferta', v_compra.oferta_codigo, 'valor', v_compra.preco,
    'comprador_id', v_compra.comprador_id, 'nome', v_comprador.nome, 'email', v_comprador.email,
    'telefone', v_comprador.telefone, 'documento', v_comprador.documento,
    'ocorrido_em', coalesce(v_compra.atualizado_em, now()), 'origem', 'compras',
    'detalhe', jsonb_build_object('status_compra', v_compra.status, 'evento', v_compra.hotmart_event)));
end $$;

-- ---------------------------------------------------------------------
-- Entrada do webhook próprio. Chamada só pela Edge Function (service_role).
-- ---------------------------------------------------------------------
create or replace function public.ra_receber_hotmart(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
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
end $$;

-- ---------------------------------------------------------------------
-- Tela: selo de teste e botão de apagar caso de teste (só o triador).
-- ---------------------------------------------------------------------
create or replace function public.ra_apagar_teste(p_caso uuid)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem apaga casos de teste.');
  end if;
  delete from public.ra_casos where id = p_caso and teste;
  if not found then return json_build_object('ok', false, 'msg', 'Só casos de teste podem ser apagados.'); end if;
  return json_build_object('ok', true, 'msg', 'Caso de teste apagado.');
end $$;

create or replace function public.ra_fila()
returns setof json language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := (select auth.uid()); v_doc boolean;
begin
  if not public.ra_pode_ver() then return; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  return query
    select to_json(x) from (
      select c.id, c.tipo, c.status, c.nome, c.email, c.produto_nome, c.oferta_codigo, c.valor,
             c.hotmart_transaction, c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.teste, c.origem,
             public.mask_sensivel(c.documento, v_doc) as documento,
             c.sugestao->>'recomendacao' as recomendacao,
             (select count(*) from public.ra_pessoas p where p.caso_id = c.id) as pessoas,
             (select count(*) from public.ra_itens i where i.caso_id = c.id) as itens_total,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao <> 'pendente') as itens_feitos,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao = 'pendente'
                and i.responsavel_id = v_uid) as meus_pendentes
        from public.ra_casos c
       order by case c.status when 'aguardando_triagem' then 0 when 'em_remocao' then 1 when 'alerta' then 2 else 3 end,
                c.prazo_em nulls last, c.ocorrido_em desc
    ) x;
end $$;

create or replace function public.ra_caso(p_caso uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $$
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
                        c.decisao_obs, c.triado_em, tp.nome as triado_por_nome, c.aluno_id, c.teste, c.origem
                   from public.ra_casos c left join public.perfis tp on tp.id = c.triado_por
                  where c.id = p_caso) y),
      'pessoas', coalesce((select json_agg(json_build_object(
                    'id', p.id, 'nome', p.nome, 'email', p.email, 'papel', p.papel, 'aluno_id', p.aluno_id,
                    'itens', coalesce((select json_agg(json_build_object(
                                'id', i.id, 'item', i.item, 'rotulo', k.rotulo, 'situacao', i.situacao,
                                'responsavel', rp.nome, 'marcado_por', mp.nome, 'marcado_em', i.marcado_em,
                                'corrigido', i.corrigido, 'obs', i.obs,
                                'pode_marcar', (i.responsavel_id = v_uid or v_triador)) order by k.ordem)
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
end $$;

-- Slack: caso de teste sai com selo. Reaproveita a função existente e só
-- acrescenta o prefixo, para a regra das mensagens continuar num lugar só.
alter function public.ra_slack_pendentes(text) rename to ra_slack_pendentes_base;
create or replace function public.ra_slack_pendentes(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare v_base json;
begin
  v_base := public.ra_slack_pendentes_base(p_segredo);
  if coalesce((v_base->>'ok')::boolean, false) is not true then return v_base; end if;
  return json_build_object('ok', true, 'mensagens', coalesce((
    select json_agg(json_build_object(
             'caso_id', m->>'caso_id', 'aviso', m->>'aviso', 'thread_ts', m->>'thread_ts',
             'texto', case when c.teste and m->>'thread_ts' is null
                           then ':test_tube: *TESTE (webhook da remoção de acessos)*' || E'\n' || (m->>'texto')
                           else m->>'texto' end))
      from json_array_elements(v_base->'mensagens') m
      join public.ra_casos c on c.id = (m->>'caso_id')::uuid), '[]'::json));
end $$;

revoke all on function public.ra_slack_pendentes_base(text) from public, anon, authenticated;
revoke all on function public.ra_slack_pendentes(text) from public;
grant execute on function public.ra_slack_pendentes(text) to anon, authenticated;

revoke all on function public.ra_montar_sugestao(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.ra_criar_caso(jsonb) from public, anon, authenticated;
revoke all on function public.ra_receber_hotmart(jsonb) from public, anon, authenticated;
grant execute on function public.ra_receber_hotmart(jsonb) to service_role;
revoke all on function public.ra_apagar_teste(uuid) from public, anon;
grant execute on function public.ra_apagar_teste(uuid) to authenticated;
