-- 20261006044653 (era 20261006c): ENSAIO da F5 — migration APLICADA em 06/10/2026 (ver .explain.md §9) (não aplica nada: tudo termina em ROLLBACK). Rodado em produção (mbvybujpkwuorhtdzcde) em
-- 06/10/2026, em partes (cada chamada do MCP abaixo de ~22 s, cada uma com seu begin … rollback), com F0, F1 e F2
-- aplicadas (a F2 foi aplicada às 04:16 UTC de 06/10, versão 20261006041654, durante esta preparação: por isso ela NÃO
-- entra no begin; com a F2 ainda não aplicada, colar o corpo de 20261005t_crm_f2_escrita.sql logo depois dos pré-índices):
--   PARTE A: pré-índices (sem concurrently) + corpo da F5 + provas como a tela/Edge chamam (authenticated +
--     request.jwt.claims de perfis REAIS: gestor = admin real "Jonathan…", vendedor A = mp, vendedor B = ro, visualizador;
--     service_role para a entrada do webhook). Segredos de webhook criados no Vault SÓ dentro da transação (aleatórios).
--   PARTE B (B1): dados REAIS só lidos (pessoas de referência criadas e desfeitas): regra do telefone na jornada, Respondi
--     sem e-mail, Unnichat legado, planos dos ramos novos (2×), tempo da jornada.
--   PARTE B2: fila com 5.000 pessoas fictícias (montar e ler).
--   Nas chamadas reais de B1/B2 o corpo da F5 foi enviado só com os objetos que cada parte usa (texto idêntico ao da
--   migration); a PARTE A rodou o corpo INTEIRO. Para a chamada caber no MCP, linhas só de comentário foram tiradas.
--   PARTE C: conferência separada de que nada persistiu.
-- Como rodar: cada parte inteira de uma vez (SQL editor, psql ou execute_sql), como postgres. Esperado: NENHUMA linha
-- começando com "ERRADO". Pessoas fictícias "Ensaio Fcinco …" (teste=true, e-mail @exemplo.invalid, DDD 99).
-- Saída só com ids/contagens/mensagens (nenhum e-mail/telefone real; literais de plano trocados por '…').
-- O arquivo é GERADO (corpo da F5 + provas): mudou uma migration, gerar de novo.

-- ═══ PARTE A ═════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;
-- pré-índices SEM concurrently (dentro da transação; rollback desfaz). Seguram lock de escrita em controle.unnichat_evento
-- (parada desde 08/09) e respondi.respostas (escrita 1×/dia 09:10) até o rollback: não rodar perto das 09:10.
create index ix_unnichat_evento_email on controle.unnichat_evento (lower(btrim((payload -> 'contact') ->> 'email')));
create index ix_respostas_fone_sem_email on respondi.respostas (controle.fone_key(telefone)) where email is null and telefone is not null;

-- ═══ CORPO DA F5 (20261006c_crm_f5_integracoes.sql, md5 45909f75927ad7817457bb8df9639dd9, copiado sem mudança; mudou a migration, gerar de novo) ═══
-- 20261006c: F5 do Comercial — integrações como FONTE DE EVENTO da jornada (ActiveCampaign, Unnichat, Respondi, SendFlow)
--            + filas de recuperação + links rastreáveis (UTM + SCK)
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Depende da F2 (20261005t, aplicada em 06/10 como versão 20261006041654
-- durante a preparação desta fase): a guarda aborta sem ela. Rodar antes, fora de transação: 20261006c_pre_indices.sql
-- (create index concurrently em tabelas de controle e respondi). Ensaio: 20261006c_ensaio.sql (begin … rollback, sobre a
-- F2 já aplicada; a F2 não entra no begin). Medidas, decisões e o que muda no
-- front: 20261006c.explain.md. Ao aplicar: renomear o arquivo para a versão gravada em supabase_migrations.schema_migrations.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §3.7, §5 (5.2, 5.3, 5.6), §6 (F5), §8. Pessoa = pessoas.pessoas
-- (convergencia-pessoas-crm.md), não crm.pessoa.
--
-- O QUE FAZ
--   1. REAPROVEITA o que já está no banco, sem copiar: controle.lead_active (lista AC), controle.grupo_evento_unificado
--      (SendFlow), respondi.respostas, controle.unnichat_evento (legado, parado desde 08/09) continuam sendo lidos NA HORA
--      pela jornada. Nada é duplicado em tabela do CRM.
--   2. crm.evento_jornada (nome escolhido para não colidir com crm.integracao_evento da F4 = caixa de entrada BRUTA do
--      WhatsApp): só o que NÃO existe no banco — evento de webhook (tag/lista/descadastro do AC, conversa
--      Unnichat, entrada em grupo SendFlow direto) — mínimo (sem payload bruto), idempotente por (fonte, id do evento),
--      já com a pessoa resolvida. Entrada única: public.crm_integracao_receber (só service_role; a Edge
--      crm-integracao-webhook chama). Token do webhook conferido CONTRA O VAULT (nome crm_webhook_<fonte>): o segredo
--      nunca fica em arquivo nem em env da Edge.
--      Casamento (manual §7, F0): e-mail primeiro (identificadores, thb_alunos e compradores, cada um pelo índice dele;
--      SEM criar pessoa nova: aluno/comprador ganham só a linha de referência, como pessoas.garantir). Sem e-mail:
--      telefone por controle.fone_key só com EXATAMENTE 1 candidato e nome compatível. Nome nunca casa. Sem casar =
--      evento guardado com resultado 'sem_pessoa'/'telefone_ambiguo' (dá para reprocessar quando a pessoa existir).
--      ActiveCampaign NÃO é CRM: só gera ponto de jornada; descadastro/bounce NÃO viram opt-out comercial (decisão).
--   3. Kill-switch por integração em crm.config (desliga em ~10 s): activecampaign_ligado, sendflow_ligado,
--      respondi_ligado e o novo unnichat_ligado. Desligado = o webhook não grava nada E a jornada pula a fonte.
--      Todos nascem/continuam FALSE (SendFlow sem chave: pronto e desligado).
--   4. public.crm_jornada recriada a partir do corpo VIVO (md5 conferido na guarda): + kill-switch por fonte; + pontos de
--      crm.evento_jornada; + Unnichat legado por e-mail; + Respondi sem e-mail por telefone; grupo (SendFlow) e
--      telefone só pela chave com 1 candidato (antes: qualquer pessoa com o mesmo fone_key via o grupo da outra).
--   5. Filas de recuperação: crm.fila, crm.fila_item (score/faixa = calcularScore/faixaDoScore do domínio), RPCs
--      crm_filas (leitura), crm_criar_fila / crm_encerrar_fila / crm_atribuir_item_fila (gestor),
--      crm_atualizar_item_fila (responsável ou gestor; C/D só com A/B zeradas; sem oferta vigente não se aborda;
--      "ganho" só com pagamento aprovado na Hotmart da linha da fila).
--   6. Links rastreáveis: crm.link_rastreavel + crm_links / crm_criar_link / crm_arquivar_link. SCK = montarSck do domínio
--      (linha-acao-AAAAMMDD-canal-sigla); URL real da oferta vigente (fin.ofertas.bruto_json.direct_offer_link_for_creator)
--      + sck + utm_source=comercial, utm_medium=canal, utm_campaign=projeto, utm_content=conteúdo.
--   7. Log: crm.tg_log (F0) em fila, fila_item (update/delete) e link. Evento de integração não vai para o log (é dado
--      de fonte, não ação de pessoa).
--
-- FORA: Manychat (fora do escopo); supressão de WhatsApp (F4); MQL do Respondi criando negócio (§5.6, depende de
--   critério por formulário: decisão); montagem automática da fila a partir de sinais (fica para depois: a F5 recebe
--   os itens prontos do gestor); Clint (F6). Nenhuma API externa é chamada pelo banco.
--
-- AS 5 PERGUNTAS (números em 20261006c.explain.md)
--   escala: evento_jornada cresce por evento de webhook (AC: dezenas a centenas/dia em lançamento); leitura sempre
--     por pessoa (índice pessoa_id) e com limite. Fila ≤ 5.000 itens por montagem; leitura ≤ 50 filas × 5.000 itens.
--   índice: jornada lê cada fonte pelo índice da expressão exata (guarda confere): ix_lead_active_email_lower,
--     ix_geu_fone, respostas_email_idx, ix_respostas_fone_sem_email (novo), ix_unnichat_evento_email (novo),
--     evento_jornada_pessoa_idx. Casamento por e-mail: thb_alunos_email_uidx, ix_compradores_email_lower_all,
--     identificadores (tipo, chave). Telefone: pessoas.candidatos_telefone (índices da F0).
--   frequência: webhook = 1 chamada por evento (sem cron novo). Jornada ao abrir a ficha. Sem polling.
--   repetição: 1 chamada de RPC por lote de eventos (até 100); crm_filas traz filas + itens numa chamada.
--   reversão: kill-switch por fonte (false = webhook ignora e jornada pula); escrita_ligada=false desliga fila/link;
--     bloco REVERSÃO no fim (tabelas novas sem FK de fora: drop; jornada volta ao corpo da F1).
--
-- PREMISSAS (guarda aborta se faltar): F2 aplicada (crm.guarda_escrita, crm.res, crm.erro_dados, crm.vendedor_ativo,
--   public.crm_mover_etapa); F5 não aplicada; corpo vivo de public.crm_jornada = o da F1 (md5); índices das fontes com a
--   expressão exata (inclui os 2 da pré); colunas das fontes; pessoas.candidatos_telefone/garantir/pessoa_do_aluno/
--   pessoa_do_comprador/nomes_compativeis; mkt.sem_acento; vault.decrypted_secrets.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  if to_regprocedure('crm.guarda_escrita()') is null or to_regprocedure('crm.res(boolean,text,jsonb)') is null
     or to_regprocedure('crm.erro_dados(text,text,text)') is null or to_regprocedure('crm.vendedor_ativo(uuid)') is null
     or to_regprocedure('crm.nome_pessoa(uuid)') is null or to_regprocedure('crm.nome_perfil(uuid)') is null
     or to_regprocedure('public.crm_mover_etapa(uuid,uuid)') is null then
    raise exception '20261006c: F2 (20261005t) não aplicada';
  end if;
  if to_regclass('crm.evento_jornada') is not null or to_regclass('crm.fila') is not null
     or to_regclass('crm.link_rastreavel') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                   and column_name = 'unnichat_ligado') then
    raise exception '20261006c: objetos da F5 já existem (migration já aplicada?)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                    and column_name in ('activecampaign_ligado', 'sendflow_ligado', 'respondi_ligado', 'escrita_ligada')
                  group by table_name having count(*) = 4) then
    raise exception '20261006c: crm.config sem os kill-switches da F0';
  end if;
  -- recriar a jornada a partir do corpo VIVO (manual §3): aborta se alguém mudou depois da F1
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.crm_jornada(uuid,integer)'))
     is distinct from '4e4cbddd4f9de648ab9ffc71441e8936' then
    raise exception '20261006c: corpo vivo de public.crm_jornada diferente do da F1: refazer a seção 4 a partir dele';
  end if;
  if to_regprocedure('pessoas.candidatos_telefone(text)') is null or to_regprocedure('pessoas.garantir(text[])') is null
     or to_regprocedure('pessoas.pessoa_do_aluno(uuid)') is null or to_regprocedure('pessoas.pessoa_do_comprador(uuid)') is null
     or to_regprocedure('pessoas.nomes_compativeis(text,text)') is null or to_regprocedure('pessoas.norm_email(text)') is null
     or to_regprocedure('pessoas.norm_telefone(text)') is null or to_regprocedure('pessoas.chave_telefone(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null or to_regclass('vault.decrypted_secrets') is null then
    raise exception '20261006c: funções da F0/mkt ou vault ausentes';
  end if;
  select string_agg(x.s || '.' || x.i, ', ') into v_falta
    from (values
      ('controle', 'ix_lead_active_email_lower',     '(lower(btrim(email)))'),
      ('controle', 'ix_geu_fone',                    '(fone_key)'),
      ('controle', 'ix_unnichat_evento_email',       '(lower(btrim(((payload -> ''contact''::text) ->> ''email''::text))))'),
      ('respondi', 'respostas_email_idx',            '(email)'),
      ('respondi', 'ix_respostas_fone_sem_email',    '(controle.fone_key(telefone)) WHERE ((email IS NULL) AND (telefone IS NOT NULL))'),
      ('public',   'thb_alunos_email_uidx',          'lower(TRIM(BOTH FROM email))) WHERE ((email IS NOT NULL) AND (email <> ''''::text))'),
      ('public',   'ix_compradores_email_lower_all', '(lower(btrim((email)::text)))'),
      ('fin',      'hotmart_transacoes_email_idx',   '(lower(TRIM(BOTH FROM comprador_email)))')
    ) x(s, i, trecho)
   where not exists (select 1 from pg_indexes pi
                       join pg_index ix on ix.indexrelid = to_regclass(quote_ident(pi.schemaname) || '.' || quote_ident(pi.indexname))
                      where pi.schemaname = x.s and pi.indexname = x.i and ix.indisvalid
                        and position(x.trecho in pi.indexdef) > 0);
  if v_falta is not null then
    raise exception '20261006c: índice ausente, inválido ou com expressão diferente: % (rodar 20261006c_pre_indices.sql antes)', v_falta;
  end if;
  select string_agg(x.s || '.' || x.t || '.' || x.c, ', ') into v_falta
    from (values ('controle','unnichat_evento','payload'), ('controle','unnichat_evento','tipo'),
                 ('controle','unnichat_evento','tag_nome'), ('controle','unnichat_evento','recebido_em'),
                 ('respondi','respostas','telefone'), ('respondi','respostas','respondido_em'),
                 ('fin','ofertas','bruto_json'), ('fin','hotmart_transacoes','origem_sck'),
                 ('fin','hotmart_transacoes','valor_cobrado'), ('crm','vendedor','sigla')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then raise exception '20261006c: colunas ausentes: %', v_falta; end if;
end
$guarda$;

-- ─── 1. Kill-switches ────────────────────────────────────────────────────────────────────────────────────────────────
alter table crm.config add column unnichat_ligado boolean not null default false;
comment on column crm.config.activecampaign_ligado is 'F5: false = webhook AC ignora (não grava) e a jornada não mostra lista/tag do AC.';
comment on column crm.config.sendflow_ligado is 'F5: false = webhook SendFlow ignora e a jornada não mostra grupos (controle.grupo_evento_unificado).';
comment on column crm.config.respondi_ligado is 'F5: false = a jornada não mostra respostas do Respondi (respondi.respostas).';
comment on column crm.config.unnichat_ligado is 'F5: false = webhook Unnichat ignora e a jornada não mostra Unnichat (legado + webhook).';

-- ─── 2. Eventos de integração (só o que não existe no banco) ─────────────────────────────────────────────────────────
-- Mínimo para a jornada: sem payload bruto (LGPD). E-mail e telefone guardados só como CHAVE normalizada (para casar e
-- reprocessar). nome só para a checagem de nome compatível no casamento por telefone.
create table crm.evento_jornada (
  id              bigint generated always as identity primary key,
  fonte           text not null check (fonte in ('activecampaign', 'unnichat', 'sendflow', 'respondi')),
  fonte_evento_id text not null check (length(fonte_evento_id) between 1 and 200),
  tipo            text not null check (tipo ~ '^[a-z0-9_.:-]{1,60}$'),
  ocorreu_em      timestamptz not null,
  recebido_em     timestamptz not null default now(),
  email_norm      text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key        text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  nome            text check (nome is null or length(nome) <= 160),
  lista           text check (lista is null or length(lista) <= 200),
  tag             text check (tag is null or length(tag) <= 200),
  dados           jsonb not null default '{}' check (jsonb_typeof(dados) = 'object' and length(dados::text) <= 4000),
  pessoa_id       uuid references pessoas.pessoas(id) on delete restrict,
  resultado       text not null default 'pendente'
                    check (resultado in ('pendente', 'anexado', 'sem_pessoa', 'telefone_ambiguo', 'sem_identificador')),
  processado_em   timestamptz,
  unique (fonte, fonte_evento_id),
  check ((resultado = 'anexado') = (pessoa_id is not null))
);
alter table crm.evento_jornada enable row level security;
create index evento_jornada_pessoa_idx on crm.evento_jornada (pessoa_id, ocorreu_em desc) where pessoa_id is not null;
create index evento_jornada_email_idx  on crm.evento_jornada (email_norm) where pessoa_id is null and email_norm is not null;
create index evento_jornada_fone_idx   on crm.evento_jornada (fone_key) where pessoa_id is null and email_norm is null and fone_key is not null;
create index evento_jornada_recebido_idx on crm.evento_jornada (recebido_em);
comment on table crm.evento_jornada is 'F5: eventos de webhook (AC, Unnichat, SendFlow) que viram ponto de jornada. Mínimo, '
  'idempotente por (fonte, fonte_evento_id), pessoa resolvida por e-mail (telefone só sem e-mail e 1 candidato). 20261006c.';

-- Pessoa pelo e-mail SEM criar pessoa nova (aluno/comprador ganham a linha de referência, como pessoas.garantir).
-- Mesma ordem do pessoas.resolver: aluno, comprador, identificador. Cada fonte pelo seu índice; valor já normalizado.
create function crm.pessoa_por_email(p_email text) returns uuid
language plpgsql set search_path = '' as $$
declare v_email text := pessoas.norm_email(p_email); v_lead uuid; v_aluno uuid; v_comprador uuid; v uuid;
begin
  if v_email is null then return null; end if;
  select a.id into v_aluno from public.thb_alunos a
   where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
  if v_aluno is not null then return pessoas.pessoa_do_aluno(v_aluno); end if;
  select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;
  if v_comprador is not null then return pessoas.pessoa_do_comprador(v_comprador); end if;
  select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
  return v_lead;
end
$$;

-- Resolve a pessoa de UM evento e grava o resultado. E-mail → pessoa_por_email. Sem e-mail: telefone com exatamente 1
-- candidato (pessoas.candidatos_telefone = pessoas + alunos ativos + compradores) e nome compatível. Nome sozinho nunca.
create function crm.anexar_integracao(p_id bigint) returns text
language plpgsql set search_path = '' as $$
declare e crm.evento_jornada%rowtype; v_pessoa uuid; v_res text; v_n int; v_ent text; v_nome_ent text;
begin
  select * into e from crm.evento_jornada where id = p_id for update;
  if not found then return null; end if;
  if e.email_norm is not null then
    v_pessoa := crm.pessoa_por_email(e.email_norm);
    v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
  elsif e.fone_key is not null then
    select count(*), min(t.ent), min(t.nome_ent) into v_n, v_ent, v_nome_ent from pessoas.candidatos_telefone(e.fone_key) t;
    if v_n = 0 then v_res := 'sem_pessoa';
    elsif v_n = 1 and pessoas.nomes_compativeis(e.nome, v_nome_ent) then
      v_pessoa := (pessoas.garantir(array[v_ent]))[1];
      v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
    else v_res := 'telefone_ambiguo';
    end if;
  else
    v_res := 'sem_identificador';
  end if;
  update crm.evento_jornada set pessoa_id = v_pessoa, resultado = v_res, processado_em = now() where id = p_id;
  return v_res;
end
$$;

-- Tipo de ponto + título do evento (para a jornada). Puro.
create function crm.ponto_integracao(p_fonte text, p_tipo text, p_lista text, p_tag text,
                                     out tipo_ponto text, out titulo text)
language sql immutable set search_path = '' as $$
  select case
           when p_fonte = 'activecampaign' then 'lista'
           when p_fonte = 'sendflow' then 'grupo'
           when p_fonte = 'respondi' then 'pesquisa'
           when p_fonte = 'unnichat' and p_tipo = 'template_enviado' then 'disparo'
           when p_fonte = 'unnichat' and p_tipo in ('convite_grupo', 'entrou_link') then 'grupo'
           else 'conversa' end,
         case
           when p_fonte = 'activecampaign' then case p_tipo
               when 'subscribe' then 'Entrou na lista'
               when 'unsubscribe' then 'Saiu da lista'
               when 'contact_tag_added' then 'Ganhou a tag'
               when 'contact_tag_removed' then 'Perdeu a tag'
               when 'bounce' then 'E-mail voltou (bounce)'
               else 'ActiveCampaign: ' || p_tipo end
             || coalesce(' · ' || nullif(p_tag, ''), ' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'sendflow' then case when p_tipo = 'saida' then 'Saiu do grupo' else 'Entrou no grupo' end
             || coalesce(' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'unnichat' then 'Unnichat: ' || coalesce(nullif(p_tag, ''), replace(p_tipo, '_', ' '))
           else 'Respondeu: ' || coalesce(nullif(p_lista, ''), 'formulário') end;
$$;

-- Entrada única dos webhooks (a Edge crm-integracao-webhook chama com a service role). Lote de até 100 eventos:
-- [{id, tipo, ocorreuEm, email, telefone, nome, lista, tag, utm:{source,medium,campaign,content}}].
-- p_chave = token que o provedor mandou; conferido contra o Vault 'crm_webhook_<fonte>' (sem segredo no Vault = recusa).
-- Kill-switch desligado = não grava nada. Reenvio do mesmo evento = no-op (duplicado).
create function public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ligado boolean; v_seg text; e jsonb; v_id bigint; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0;
  v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end
    into v_ligado from crm.config c;
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
    begin
      v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, now());
    exception when others then v_quando := null;
    end;
    if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
       or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > now() + interval '1 day' then
      v_inval := v_inval + 1; continue;
    end if;
    v_utm := jsonb_strip_nulls(jsonb_build_object(
               'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
               'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
    insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, fone_key, nome, lista, tag, dados)
    values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando,
            pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
            nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
            nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
            case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
    begin
      v_res := crm.anexar_integracao(v_id);
      if v_res = 'anexado' then v_anex := v_anex + 1; end if;
    exception when others then
      raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    end;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'invalidos', v_inval);
end
$$;

-- Reprocessa eventos que ainda não casaram (a pessoa pode ter aparecido depois). Lote limitado; só service_role
-- (rodar à mão ou por cron diário quando a fonte estiver ligada — NÃO agendado aqui).
create function public.crm_integracao_reprocessar(p_limite int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v_n int := 0; v_anex int := 0;
begin
  for r in select e.id from crm.evento_jornada e
            where e.pessoa_id is null and e.resultado in ('pendente', 'sem_pessoa', 'telefone_ambiguo')
            order by e.id limit least(greatest(coalesce(p_limite, 500), 1), 5000) loop
    v_n := v_n + 1;
    if crm.anexar_integracao(r.id) = 'anexado' then v_anex := v_anex + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'processados', v_n, 'anexados', v_anex);
end
$$;

-- ─── 3. E-mails da pessoa (grupo de alias + irmãos em fin.identidade). Mesma lógica da jornada (F1). ────────────────
create function crm.emails_da_pessoa(p_atual uuid) returns text[]
language plpgsql stable set search_path = '' as $$
declare v_g uuid[] := pessoas.grupo(pessoas.atual(p_atual)); v_compr uuid[]; v_emails text[];
begin
  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  return array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
end
$$;

-- ─── 4. Jornada: corpo vivo da F1 + fontes da F5 com kill-switch + telefone só com 1 candidato ──────────────────────
create or replace function public.crm_jornada(p_pessoa uuid, p_limite int default 500) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_atual uuid; v_g uuid[]; v_emails text[]; v_fks text[]; v_fks1 text[]; v_compr uuid[];
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
  v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is null or not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a esta pessoa.' using errcode = '42501';
  end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  v_atual := pessoas.atual(p_pessoa);
  v_g := pessoas.grupo(v_atual);

  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  -- e-mails irmãos pelo grafo fin.identidade (por chave, no momento da leitura; recalculado de hora em hora)
  v_emails := array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
  v_fks := array(
    select k from (
      select controle.fone_key(coalesce(a.telefone_e164, a.telefone)) k from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
       where p.id = any(v_g)
      union select controle.fone_key((c.telefone)::text) from public.compradores c where c.id = any(v_compr) and c.telefone is not null
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'telefone'
    ) s where k is not null limit 10);
  -- F5: evento só com telefone (grupo, Respondi sem e-mail) é da pessoa só se a chave tem EXATAMENTE 1 candidato
  -- (manual §7: telefone nunca junta duas pessoas). Calculado só se alguma fonte por telefone estiver ligada.
  if v_sf or v_rs then
    v_fks1 := array(select k from unnest(v_fks) k where (select count(*) from pessoas.candidatos_telefone(k)) = 1);
  else
    v_fks1 := '{}';
  end if;

  with pts as (
    -- inscrição (origem com a UTM daquela entrada)
    (select 'or-' || o.id id, 'inscricao' tipo, o.quando em,
            'Inscrição' || coalesce(' · ' || pr.sigla, '') titulo, o.campanha detalhe, 'formulario' fonte,
            lower(pr.sigla) lancamento, null::text produto,
            jsonb_build_object('source', o.utm_source, 'medium', o.utm_medium, 'campaign', o.utm_campaign, 'content', o.utm_content) utm,
            null::numeric valor, null::uuid negocio_id
       from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id
      where o.pessoa_id = any(v_g) order by o.quando desc limit v_lim)
    union all
    (select 'ev-' || e.id, 'pesquisa', e.quando, case e.tipo when 'mql' then 'Qualificou como MQL' else 'Não qualificou (MQL)' end,
            null, 'formulario', lower(pr.sigla), null, null, null, null
       from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id
      where e.pessoa_id = any(v_g) and e.tipo in ('mql', 'nao_mql') order by e.quando desc limit v_lim)
    union all
    -- Hotmart: compra, reembolso, checkout (índice hotmart_transacoes_email_idx = lower(btrim(comprador_email)))
    (select 'hm-' || h.transacao,
            case when h.status in ('APPROVED', 'COMPLETE') then 'compra'
                 when h.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED') then 'reembolso' else 'checkout' end,
            coalesce(h.aprovado_em, h.pedido_em),
            case when h.status in ('APPROVED', 'COMPLETE') then 'Compra aprovada'
                 when h.status in ('REFUNDED', 'PARTIALLY_REFUNDED') then 'Reembolso'
                 when h.status = 'CHARGEBACK' then 'Chargeback'
                 when h.status in ('WAITING_PAYMENT', 'PRINTED_BILLET') then 'Boleto/Pix gerado'
                 when h.status = 'EXPIRED' then 'Pagamento expirado'
                 when h.status = 'CANCELLED' then 'Compra cancelada'
                 else 'Checkout: ' || lower(h.status) end || coalesce(' · ' || h.produto_nome, ''),
            nullif(concat_ws(' · ', 'oferta ' || h.oferta_codigo, h.metodo), ''), 'hotmart', null, pcm.linha,
            case when h.origem_sck is not null then jsonb_build_object('sck', h.origem_sck) end,
            h.valor_cobrado, null
       from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
       left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id and pcm.no_comercial
      where lower(btrim(h.comprador_email)) = any(v_emails)
      order by coalesce(h.aprovado_em, h.pedido_em) desc nulls last limit v_lim)
    union all
    -- lista do ActiveCampaign (índice ix_lead_active_email_lower). F5: kill-switch activecampaign_ligado.
    (select 'ac-' || la.id, 'lista', coalesce(la.opt_in_at, la.atualizado_em), 'Entrou na lista' || coalesce(' · ' || la.origem, ''),
            la.segmento, 'activecampaign', null, null,
            jsonb_build_object('source', la.utm_source, 'campaign', la.utm_campaign, 'content', la.utm_content), null, null
       from controle.lead_active la
      where v_ac and lower(btrim(la.email)) = any(v_emails)
      order by coalesce(la.opt_in_at, la.atualizado_em) desc limit v_lim)
    union all
    -- grupos de WhatsApp (índice ix_geu_fone, chave controle.fone_key). F5: sendflow_ligado + chave com 1 candidato.
    (select 'gr-' || g.id, 'grupo', g.ocorreu_em,
            case g.tipo when 'entrada' then 'Entrou no grupo' else 'Saiu do grupo' end || coalesce(' · ' || g.group_name, ''),
            g.segmento, 'sendflow', null, null, null, null, null
       from controle.grupo_evento_unificado g
      where v_sf and g.fone_key = any(v_fks1)
      order by g.ocorreu_em desc limit v_lim)
    union all
    -- pesquisas/formulários (índice respostas_email_idx; e-mail já normalizado na fonte). Nunca cpf/respostas.
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            null, 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email = any(v_emails)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: resposta SEM e-mail, pelo telefone com 1 candidato (índice ix_respostas_fone_sem_email, predicado repetido)
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            'casado pelo telefone', 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email is null and r.telefone is not null and controle.fone_key(r.telefone) = any(v_fks1)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: Unnichat legado (controle.unnichat_evento, parado desde 08/09) pelo e-mail do contato (ix_unnichat_evento_email)
    (select 'un-' || u.id, (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).tipo_ponto, u.recebido_em,
            (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).titulo, null, 'unnichat', null, null, null, null, null
       from controle.unnichat_evento u
      where v_un and lower(btrim((u.payload -> 'contact') ->> 'email')) = any(v_emails)
      order by u.recebido_em desc limit v_lim)
    union all
    -- F5: eventos de webhook já casados com a pessoa (crm.evento_jornada), cada fonte com o seu kill-switch
    (select 'ie-' || ie.id, (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).tipo_ponto, ie.ocorreu_em,
            (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).titulo, null, ie.fonte, null, null,
            ie.dados -> 'utm', null, null
       from crm.evento_jornada ie
      where ie.pessoa_id = any(v_g)
        and ((ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
             or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs))
      order by ie.ocorreu_em desc limit v_lim)
    union all
    -- mini-CRM do CS (só leitura; D4 coexistir)
    (select 'cs-' || c.id, 'nota', coalesce(c.ultimo_contato_em, c.atualizado_em, c.criado_em),
            'CS: ' || coalesce(es.nome, 'sem estágio') || coalesce(' · ' || c.evento, ''),
            case when c.responsavel is not null then 'responsável: ' || c.responsavel end, 'crm', null, null, null, null, null
       from cs.contatos c left join cs.estagios es on es.id = c.estagio_id
      where c.comprador_id = any(v_compr))
    union all
    -- CRM: negócios (mesma regra da policy de negócio)
    (select 'ng-' || n.id, 'negocio', n.criado_em, 'Negócio criado · ' || f.nome, null, 'crm', f.projeto, n.linha,
            case when n.utm <> '{}'::jsonb then n.utm end, null, n.id
       from crm.negocio n join crm.funil f on f.id = n.funil_id
      where n.pessoa_id = any(v_g) and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by n.criado_em desc limit v_lim)
    union all
    (select 'lg-' || l.id, 'negocio', l.em,
            case l.acao when 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa')
                        when 'marcou_ganho' then 'Ganho' when 'marcou_perdido' then 'Perdido'
                        else 'Troca de dono' end || ' · ' || f.nome,
            l.resumo, 'crm', f.projeto, n.linha, null,
            case when l.acao = 'marcou_ganho' then n.valor end, n.id
       from crm.log l
       join crm.negocio n on n.id::text = l.entidade_id
       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g)
      order by nt.em desc limit v_lim)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'contatoId', v_atual, 'tipo', p.tipo, 'em', p.em, 'titulo', p.titulo, 'detalhe', p.detalhe,
           'fonte', p.fonte, 'lancamento', p.lancamento, 'produto', p.produto, 'utm', p.utm, 'valor', p.valor,
           'negocioId', p.negocio_id) order by p.em desc nulls last, p.id), '[]'::jsonb)
    into v
    from (select * from pts where pts.em is not null order by pts.em desc limit v_lim) p;
  return v;
end
$$;

-- ─── 5. Filas de recuperação (§3.7; processo montar-fila-de-recuperacao.md) ──────────────────────────────────────────
-- calcularScore do domínio (regras.ts): comportamento de compra conta só o maior (boleto 40 OU carrinho 24); teto 100.
create function crm.score_recuperacao(p_sinais text[]) returns smallint
language sql immutable set search_path = '' as $$
  select least(100,
           case when 'boleto_aberto' = any(p_sinais) then 40 when 'carrinho' = any(p_sinais) then 24 else 0 end
         + coalesce((select sum(case s when 'ficha_completa' then 20 when 'senhas' then 16 when 'chat' then 12
                                       when 'workbook' then 6 when 'apostila' then 4 when 'pesquisa' then 6
                                       when 'comunidade' then 4 when 'grupo' then 3 when 'advogado_contador' then 4
                                       when 'quer_parceria' then 6 else 0 end)
                       from (select distinct unnest(coalesce(p_sinais, '{}'))) x(s)), 0))::smallint;
$$;

create table crm.fila (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(btrim(nome)) between 1 and 120),
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,   -- sem oferta vigente não se aborda
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),
  criada_por    uuid references public.perfis(id) on delete restrict,
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz,
  encerrada_por uuid references public.perfis(id) on delete restrict
);
create index fila_criada_idx on crm.fila (criada_em desc);

create table crm.fila_item (
  id             uuid primary key default gen_random_uuid(),
  fila_id        uuid not null references crm.fila(id) on delete restrict,
  pessoa_id      uuid not null references pessoas.pessoas(id) on delete restrict,   -- leitura resolve pessoas.atual
  score          smallint not null check (score between 0 and 100),
  faixa          char(1) generated always as (case when score >= 60 then 'A' when score >= 40 then 'B'
                                                   when score >= 25 then 'C' else 'D' end) stored,
  sinais         text[] not null default '{}'
                   check (sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas','chat',
                                          'workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                          'quer_parceria','respondeu_sem_retorno']::text[]),
  status         text not null default 'a_abordar'
                   check (status in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                     'declinou','sem_interesse','numero_invalido')),
  responsavel_id uuid references crm.vendedor(perfil_id) on delete restrict,
  alterado_por   uuid references public.perfis(id) on delete restrict,
  alterado_em    timestamptz,
  criado_em      timestamptz not null default now(),
  unique (fila_id, pessoa_id)
);
create index fila_item_faixa_idx       on crm.fila_item (fila_id, faixa, status);
create index fila_item_responsavel_idx on crm.fila_item (responsavel_id) where responsavel_id is not null;
create index fila_item_pessoa_idx      on crm.fila_item (pessoa_id);

-- Oferta da fila ainda vigente? Devolve o texto que a tela mostra (null = não se aborda).
create function crm.oferta_vigente_texto(p_oferta text) returns text
language sql stable security definer set search_path = '' as $$
  select concat_ws(' · ', coalesce(pc.nome_comercial, o.nome), o.oferta_codigo, oc.condicao)
    from fin.ofertas o
    join crm.oferta_comercial oc on oc.oferta_codigo = o.oferta_codigo
    left join crm.produto_comercial pc on pc.produto_id = o.produto_id
   where o.oferta_codigo = p_oferta and oc.vigente
     and (oc.valida_ate is null or oc.valida_ate >= (now() at time zone 'America/Sao_Paulo')::date);
$$;

-- ─── 6. Links rastreáveis (§3.7; playbook seção 8) ───────────────────────────────────────────────────────────────────
-- Pedaço do SCK = limpa() de montarSck: sem acento, minúsculo, só [a-z0-9].
create function crm.limpa_sck(p text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(mkt.sem_acento(coalesce(p, '')), '[^A-Za-z0-9]+', '', 'g'));
$$;

create table crm.link_rastreavel (
  id            uuid primary key default gen_random_uuid(),
  vendedor_id   uuid not null references crm.vendedor(perfil_id) on delete restrict,
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text not null references fin.ofertas(oferta_codigo) on delete restrict,   -- link real, nunca "EXEMPLO"
  acao          text not null check (length(btrim(acao)) between 1 and 60),
  canal         text not null check (canal ~ '^[a-z0-9]{1,30}$'),
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),     -- utm_campaign
  conteudo      text check (conteudo is null or conteudo ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$'), -- utm_content
  sck           text not null unique check (sck ~ '^[a-z0-9_]+-[a-z0-9]+-[0-9]{8}-[a-z0-9]+-[a-z0-9]+$'),
  url           text not null check (url ~ '^https://pay\.hotmart\.com' and length(url) <= 1000),
  criado_por    uuid references public.perfis(id) on delete restrict,
  criado_em     timestamptz not null default now(),
  arquivado_em  timestamptz
);
create index link_vendedor_idx on crm.link_rastreavel (vendedor_id, criado_em desc);

-- ─── 7. Log (crm.tg_log da F0), RLS e policies ───────────────────────────────────────────────────────────────────────
create trigger fila_log_ins_del after insert or delete on crm.fila for each row execute function crm.tg_log('fila', 'id');
create trigger fila_log_upd after update on crm.fila for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
-- itens: só alteração/remoção (a montagem é 1 linha de log na fila, não 5.000)
create trigger fila_item_log_del after delete on crm.fila_item for each row execute function crm.tg_log('fila', 'id');
create trigger fila_item_log_upd after update on crm.fila_item for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
create trigger link_log_ins_del after insert or delete on crm.link_rastreavel for each row execute function crm.tg_log('link', 'id');
create trigger link_log_upd after update on crm.link_rastreavel for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('link', 'id');

do $rls$
declare t text;
begin
  foreach t in array array['fila', 'fila_item', 'link_rastreavel'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated', t);
    execute format('grant select on crm.%I to authenticated', t);
  end loop;
  -- evento_jornada: fechada (só as funções definer leem)
  revoke all on crm.evento_jornada from public, anon, authenticated;
end
$rls$;
create policy fila_ler on crm.fila for select to authenticated using ((select crm.eh_comercial()));
create policy fila_item_ler on crm.fila_item for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (responsavel_id = (select auth.uid()) or responsavel_id is null)));
create policy link_ler on crm.link_rastreavel for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and vendedor_id = (select auth.uid())));

-- ─── 8. RPCs de leitura ──────────────────────────────────────────────────────────────────────────────────────────────
-- Filas (FilaRecuperacao[]): DEFINER porque o texto da oferta vigente lê fin.ofertas; itens com a MESMA regra da
-- policy fila_item_ler. contatoId = pessoa atual (alias resolvido em lote).
create function public.crm_filas(p_incluir_encerradas boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with f as (
    select x.* from crm.fila x where coalesce(p_incluir_encerradas, false) or x.encerrada_em is null
     order by x.criada_em desc limit 50),
  it as (
    select i.*, row_number() over (partition by i.fila_id order by i.score desc, i.id) rn
      from crm.fila_item i
     where i.fila_id in (select f.id from f) and (v_gestor or i.responsavel_id = v_eu or i.responsavel_id is null)),
  al as (select * from crm.atual_de(array(select distinct it.pessoa_id from it where it.rn <= 5000)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'nome', f.nome, 'produto', f.linha, 'criadaEm', f.criada_em,
           'ofertaVigente', crm.oferta_vigente_texto(f.oferta_codigo), 'ofertaCodigo', f.oferta_codigo,
           'projeto', f.projeto, 'encerradaEm', f.encerrada_em,
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', it.id, 'contatoId', al.atual, 'score', it.score, 'faixa', it.faixa, 'sinais', to_jsonb(it.sinais),
                        'status', it.status, 'responsavelId', it.responsavel_id, 'alteradoPor', it.alterado_por,
                        'alteradoEm', it.alterado_em) order by it.score desc, it.id)
                       from it left join al on al.pessoa_id = it.pessoa_id
                      where it.fila_id = f.id and it.rn <= 5000), '[]'::jsonb))
           order by f.criada_em desc), '[]'::jsonb)
    into v from f;
  return v;
end
$$;

-- Links (LinkRastreavel[]): gestor vê todos, vendedor os seus. p_vendas = true soma as vendas Hotmart pelo SCK
-- (2 Seq Scans em fin.hotmart_transacoes sem índice em origem_sck: sob pedido, nunca ao abrir a tela).
create function public.crm_links(p_vendas boolean default false, p_incluir_arquivados boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with l as (
    select x.* from crm.link_rastreavel x
     where (v_gestor or x.vendedor_id = v_eu) and (coalesce(p_incluir_arquivados, false) or x.arquivado_em is null)
     order by x.criado_em desc limit 2000),
  vd as (
    select h.origem_sck sck, count(*) filter (where h.status in ('APPROVED', 'COMPLETE')) vendas,
           coalesce(sum(h.valor_cobrado) filter (where h.status in ('APPROVED', 'COMPLETE')), 0) receita
      from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
     where coalesce(p_vendas, false) and h.origem_sck = any(array(select l.sck from l))
     group by h.origem_sck)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'vendedorId', l.vendedor_id, 'produto', l.linha, 'acao', l.acao, 'url', l.url, 'sck', l.sck,
           'canal', l.canal, 'ofertaCodigo', l.oferta_codigo, 'projeto', l.projeto, 'conteudo', l.conteudo,
           'criadoEm', l.criado_em, 'arquivadoEm', l.arquivado_em,
           'vendas', case when coalesce(p_vendas, false) then coalesce(vd.vendas, 0) end,
           'receita', case when coalesce(p_vendas, false) then coalesce(vd.receita, 0) end) order by l.criado_em desc), '[]'::jsonb)
    into v
    from l left join vd on vd.sck = l.sck;
  return v;
end
$$;

-- ─── 9. RPCs de escrita: fila ────────────────────────────────────────────────────────────────────────────────────────
-- Itens de entrada da montagem: pessoa ATUAL (alias resolvido) + sinais sem repetição.
create function crm.fila_entrada(p_itens jsonb) returns table (pessoa uuid, sinais text[])
language sql stable set search_path = '' as $$
  select pessoas.atual(crm.uuid_ou_null(x ->> 'contatoId')),
         array(select distinct s from jsonb_array_elements_text(case when jsonb_typeof(x -> 'sinais') = 'array'
                                                                     then x -> 'sinais' else '[]'::jsonb end) s order by 1)
    from jsonb_array_elements(case when jsonb_typeof(p_itens) = 'array' then p_itens else '[]'::jsonb end) x;
$$;

-- Monta a fila (só gestor). p: {nome, produto, ofertaCodigo?, projeto?, itens:[{contatoId, sinais:[]}]} (≤ 5.000).
-- Score/faixa calculados no banco. Contato com opt-out fica fora (suprimidos); repetido (mesma pessoa atual) entra 1×.
create function public.crm_criar_fila(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_nome text; v_linha text; v_oferta text; v_projeto text; v_id uuid; v_n int; v_sup int; v_inval int;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor monta fila de recuperação.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_nome := btrim(coalesce(p ->> 'nome', ''));
  v_linha := p ->> 'produto';
  v_oferta := nullif(btrim(coalesce(p ->> 'ofertaCodigo', '')), '');
  v_projeto := nullif(lower(btrim(coalesce(p ->> 'projeto', ''))), '');
  if v_nome = '' then return crm.res(false, 'Dê um nome à fila.'); end if;
  if not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_oferta is not null and not exists (
       select 1 from fin.ofertas o join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial
        where o.oferta_codigo = v_oferta and pc.linha = v_linha) then
    return crm.res(false, 'Oferta não é deste produto.');
  end if;
  if jsonb_typeof(p -> 'itens') <> 'array' or jsonb_array_length(p -> 'itens') = 0 then
    return crm.res(false, 'Fila sem contatos.');
  end if;
  if jsonb_array_length(p -> 'itens') > 5000 then return crm.res(false, 'Fila com mais de 5.000 contatos: divida.'); end if;

  select count(*) filter (where e.pessoa is null or not exists (select 1 from pessoas.pessoas pp where pp.id = e.pessoa)
                            or not (e.sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas',
                                    'chat','workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                    'quer_parceria','respondeu_sem_retorno']::text[]))
    into v_inval from crm.fila_entrada(p -> 'itens') e;
  if v_inval > 0 then return crm.res(false, format('%s contato(s) inexistente(s) ou com sinal inválido.', v_inval)); end if;
  select count(distinct e.pessoa) into v_sup from crm.fila_entrada(p -> 'itens') e
   where exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(e.pessoa)) and pc.opt_out);

  perform set_config('crm.resumo', format('Montou a fila "%s" (%s)', v_nome, v_linha), true);
  insert into crm.fila (nome, linha, oferta_codigo, projeto, criada_por)
  values (v_nome, v_linha, v_oferta, v_projeto, auth.uid()) returning id into v_id;
  insert into crm.fila_item (fila_id, pessoa_id, score, sinais)
  select v_id, i.pessoa, crm.score_recuperacao(i.sinais), i.sinais
    from (select distinct on (e.pessoa) e.pessoa, e.sinais from crm.fila_entrada(p -> 'itens') e
           order by e.pessoa, cardinality(e.sinais) desc) i
   where not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(i.pessoa)) and pc.opt_out);
  get diagnostics v_n = row_count;
  return crm.res(true, format('Fila montada: %s contato(s)%s.', v_n,
                              case when v_sup > 0 then format(', %s fora por opt-out', v_sup) else '' end),
                 jsonb_build_object('filaId', v_id, 'itens', v_n, 'suprimidos', v_sup));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_encerrar_fila(p_fila uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor encerra fila.'); end if;
  select * into f from crm.fila x where x.id = p_fila for update;
  if not found then return crm.res(false, 'Fila não encontrada.'); end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila já encerrada.'); end if;
  perform set_config('crm.resumo', format('Encerrou a fila "%s"', f.nome), true);
  update crm.fila x set encerrada_em = now(), encerrada_por = auth.uid() where x.id = p_fila;
  return crm.res(true);
end
$$;

-- Gestor define o responsável de um item (null = devolve para a fila).
create function public.crm_atribuir_item_fila(p_fila uuid, p_item uuid, p_responsavel uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; it crm.fila_item%rowtype; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor distribui a fila.'); end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if p_responsavel is not null and not crm.vendedor_ativo(p_responsavel) then return crm.res(false, 'Vendedor inválido ou inativo.'); end if;
  if it.responsavel_id is not distinct from p_responsavel then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Fila "%s": %s passou para %s', f.nome, crm.nome_pessoa(it.pessoa_id),
                                          crm.nome_perfil(p_responsavel)), true);
  update crm.fila_item x set responsavel_id = p_responsavel, alterado_por = auth.uid(), alterado_em = now() where x.id = p_item;
  return crm.res(true);
end
$$;

-- atualizarItemFila do port. Mensagens no tom do mock. Regras do playbook:
--   responsável ou gestor (item sem responsável: o vendedor que mexe assume); fila encerrada não muda;
--   sem oferta vigente não se aborda; C/D só com A/B zeradas (pendentesAB = A/B ainda "a_abordar" na fila inteira);
--   opt-out não volta a ser abordado; "ganho" só com pagamento aprovado na Hotmart da linha desde a montagem.
create function public.crm_atualizar_item_fila(p_fila uuid, p_item uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false);
        it crm.fila_item%rowtype; f crm.fila%rowtype; v_pend int; v_emails text[]; v_resp uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_status is null or p_status not in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                          'declinou','sem_interesse','numero_invalido') then
    return crm.res(false, 'Status inválido.');
  end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if not (v_gestor or it.responsavel_id is not distinct from v_eu
          or (it.responsavel_id is null and coalesce(crm.eh_vendedor(), false))) then
    return crm.res(false, 'Este contato da fila é de outro vendedor.');
  end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if it.status = p_status then return crm.res(true); end if;
  if crm.oferta_vigente_texto(f.oferta_codigo) is null then
    return crm.res(false, 'Sem oferta vigente: não se aborda. O gestor define a oferta da fila.');
  end if;
  if it.faixa in ('C', 'D') then
    select count(*) into v_pend from crm.fila_item x where x.fila_id = p_fila and x.faixa in ('A', 'B') and x.status = 'a_abordar';
    if v_pend > 0 then return crm.res(false, format('Faixas C e D só depois de A e B zeradas (faltam %s).', v_pend)); end if;
  end if;
  if p_status in ('tentando_contato', 'em_conversa', 'vai_comprar')
     and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(it.pessoa_id))) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  if p_status = 'ganho' then
    v_emails := crm.emails_da_pessoa(it.pessoa_id);
    if not exists (
      select 1 from (select * from fin.hotmart_transacoes where conta = 'academy'
                     union all
                     select * from fin.hotmart_transacoes where conta = 'escritorio') h
        join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = f.linha
       where lower(btrim(h.comprador_email)) = any(v_emails) and h.status in ('APPROVED', 'COMPLETE')
         and h.aprovado_em >= f.criada_em) then
      return crm.res(false, 'Ganho só com pagamento aprovado na Hotmart (produto da fila, depois da montagem).');
    end if;
  end if;
  v_resp := coalesce(it.responsavel_id, case when not v_gestor then v_eu end);
  perform set_config('crm.resumo', format('Mudou %s na fila: %s → %s', crm.nome_pessoa(it.pessoa_id), it.status, p_status), true);
  update crm.fila_item x set status = p_status, responsavel_id = v_resp, alterado_por = v_eu, alterado_em = now()
   where x.id = p_item;
  return crm.res(true);
end
$$;

-- ─── 10. RPCs de escrita: link ───────────────────────────────────────────────────────────────────────────────────────
-- criarLink do port (+ opcionais). Vendedor só para si; gestor para qualquer vendedor ativo. Oferta: a informada (tem de
-- ser vigente e da linha) ou a ÚNICA vigente da linha. SCK = montarSck (linha-acao-AAAAMMDD-canal-sigla, data de São Paulo).
create function public.crm_criar_link(p_vendedor uuid, p_produto text, p_acao text, p_canal text,
                                      p_oferta text default null, p_projeto text default null, p_conteudo text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_sigla text; v_oferta text; v_n int; v_base text; v_sck text; v_canal text;
        v_projeto text := nullif(lower(btrim(coalesce(p_projeto, ''))), ''); v_conteudo text := nullif(btrim(coalesce(p_conteudo, '')), '');
        v_url text; v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_vendedor is null or btrim(coalesce(p_acao, '')) = '' or crm.limpa_sck(p_acao) = '' then
    return crm.res(false, 'Informe vendedor e ação.');
  end if;
  if not coalesce(crm.eh_gestor(), false) and p_vendedor is distinct from v_eu then
    return crm.res(false, 'Vendedor só cria link para si mesmo.');
  end if;
  select v.sigla into v_sigla from crm.vendedor v where v.perfil_id = p_vendedor;
  if v_sigla is null or not crm.vendedor_ativo(p_vendedor) then return crm.res(false, 'Informe vendedor e ação.'); end if;
  v_canal := crm.limpa_sck(p_canal);
  if v_canal = '' then return crm.res(false, 'Informe o canal (ex.: whatsapp).'); end if;
  if not exists (select 1 from crm.linha l where l.chave = p_produto and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_projeto is not null and v_projeto !~ '^[a-z0-9][a-z0-9_-]{0,59}$' then
    return crm.res(false, 'Chave do projeto inválida (letras minúsculas, números, - e _).');
  end if;
  if v_conteudo is not null and v_conteudo !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$' then
    return crm.res(false, 'Código do conteúdo inválido (letras, números, - e _).');
  end if;
  -- ofertas vigentes da linha
  select count(*), min(o.oferta_codigo) into v_n, v_oferta
    from fin.ofertas o
    join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial and pc.linha = p_produto
   where crm.oferta_vigente_texto(o.oferta_codigo) is not null
     and (p_oferta is null or o.oferta_codigo = p_oferta);
  if p_oferta is not null and v_n = 0 then return crm.res(false, 'Oferta não é deste produto ou não está vigente.'); end if;
  if v_n = 0 then return crm.res(false, 'Sem oferta vigente neste produto: o gestor define em Produtos e ofertas.'); end if;
  if v_n > 1 then return crm.res(false, 'Há mais de uma oferta vigente neste produto: escolha a oferta.'); end if;
  v_sck := p_produto || '-' || crm.limpa_sck(p_acao) || '-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD')
           || '-' || v_canal || '-' || crm.limpa_sck(v_sigla);
  if exists (select 1 from crm.link_rastreavel l where l.sck = v_sck) then return crm.res(false, 'Este link já existe.'); end if;
  select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
    into v_base from fin.ofertas o where o.oferta_codigo = v_oferta;
  v_url := v_base || case when position('?' in v_base) > 0 then '&' else '?' end
           || 'sck=' || v_sck || '&utm_source=comercial&utm_medium=' || v_canal
           || coalesce('&utm_campaign=' || v_projeto, '') || coalesce('&utm_content=' || v_conteudo, '');
  perform set_config('crm.resumo', format('Criou link rastreável %s', v_sck), true);
  insert into crm.link_rastreavel (vendedor_id, linha, oferta_codigo, acao, canal, projeto, conteudo, sck, url, criado_por)
  values (p_vendedor, p_produto, v_oferta, btrim(p_acao), v_canal, v_projeto, v_conteudo, v_sck, v_url, v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('linkId', v_id, 'sck', v_sck, 'url', v_url));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_arquivar_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; l crm.link_rastreavel%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into l from crm.link_rastreavel x where x.id = p_link for update;
  if not found then return crm.res(false, 'Link não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or l.vendedor_id = auth.uid()) then return crm.res(false, 'Este link não é seu.'); end if;
  if l.arquivado_em is not null then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Arquivou o link %s', l.sck), true);
  update crm.link_rastreavel x set arquivado_em = now() where x.id = p_link;
  return crm.res(true);
end
$$;

-- ─── 11. Grants e conferência ────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  -- internos: ninguém executa direto
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('pessoa_por_email','anexar_integracao','ponto_integracao','emails_da_pessoa','score_recuperacao',
                                'oferta_vigente_texto','limpa_sck','fila_entrada') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- entrada dos webhooks: só service_role (a Edge)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_integracao_receber', 'crm_integracao_reprocessar') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- telas: authenticated (guarda no corpo)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_filas','crm_links','crm_criar_fila','crm_encerrar_fila','crm_atribuir_item_fila',
                                'crm_atualizar_item_fila','crm_criar_link','crm_arquivar_link') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- crm_jornada foi recriada com create or replace: mantém o ACL, mas confere de novo
  revoke all on function public.crm_jornada(uuid, integer) from public, anon;
  grant execute on function public.crm_jornada(uuid, integer) to authenticated;
end
$grants$;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006c: função executável por anon/PUBLIC: %', v_aberto; end if;
  if has_function_privilege('authenticated', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'crm.anexar_integracao(bigint)', 'execute')
     or has_function_privilege('authenticated', 'crm.pessoa_por_email(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_atualizar_item_fila(uuid,uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_jornada(uuid,integer)', 'execute') then
    raise exception '20261006c: grants das funções fora do esperado';
  end if;
  select string_agg(table_name || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC')
          or (grantee = 'authenticated' and (privilege_type <> 'SELECT' or table_name = 'evento_jornada')));
  if v_aberto is not null then raise exception '20261006c: grant indevido em crm: %', v_aberto; end if;
  if coalesce((select c.activecampaign_ligado or c.sendflow_ligado or c.unnichat_ligado from crm.config c), true) then
    -- não liga nada: só confere que a migration não ligou (respondi_ligado pode já estar ligado pelo Arthur)
    raise exception '20261006c: kill-switch de AC/SendFlow/Unnichat ligado (esperado false ao aplicar)';
  end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamadas separadas; desliga do mesmo jeito com false) ════════════════════════
-- 1. Segredo de cada webhook no Vault (valor gerado na hora, nunca em arquivo/chat):
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_activecampaign', 'F5 webhook AC');
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_unnichat', 'F5 webhook Unnichat');
--      (SendFlow: só quando houver a chave/conta; até lá fica sem segredo = recusa tudo.)
-- 2. Deploy da Edge crm-integracao-webhook (verify_jwt = false) e cadastro da URL no AC/Unnichat.
-- 3. update crm.config set activecampaign_ligado = true;   -- e/ou respondi_ligado, unnichat_ligado, sendflow_ligado
-- 4. Reprocessar o que não casou (opcional): select public.crm_integracao_reprocessar(500);  -- como service_role/postgres

-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- update crm.config set activecampaign_ligado = false, sendflow_ligado = false, respondi_ligado = false, unnichat_ligado = false;
--   (desliga em ~10 s, sem deploy: preferir isto)
-- Desfazer de vez (tabelas novas; dado de fila/link escrito fica no crm.log):
-- drop function public.crm_integracao_receber(text,text,jsonb), public.crm_integracao_reprocessar(int),
--   public.crm_filas(boolean), public.crm_links(boolean,boolean), public.crm_criar_fila(jsonb), public.crm_encerrar_fila(uuid),
--   public.crm_atribuir_item_fila(uuid,uuid,uuid), public.crm_atualizar_item_fila(uuid,uuid,text),
--   public.crm_criar_link(uuid,text,text,text,text,text,text), public.crm_arquivar_link(uuid);
-- jornada: recriar public.crm_jornada com o corpo da 20261005s (md5 4e4cbddd4f9de648ab9ffc71441e8936).
-- drop table crm.fila_item, crm.fila, crm.link_rastreavel, crm.evento_jornada;
-- drop function crm.pessoa_por_email(text), crm.anexar_integracao(bigint), crm.ponto_integracao(text,text,text,text),
--   crm.emails_da_pessoa(uuid), crm.score_recuperacao(text[]), crm.oferta_vigente_texto(text), crm.limpa_sck(text),
--   crm.fila_entrada(jsonb);
-- alter table crm.config drop column unnichat_ligado;
-- drop index concurrently controle.ix_unnichat_evento_email; drop index concurrently respondi.ix_respostas_fone_sem_email;  -- à parte

-- ═══ FIM DOS CORPOS (F2 + F5) ═══════════════════════════════════════════════════════════════════════════════════════

-- ─── Fixtures: perfis reais (só ids em temp), pessoas fictícias (teste=true, domínio .invalid), produto/oferta reais ──
create temp table _v (k text primary key, u uuid, t text) on commit drop;
create function pg_temp.v(p text) returns uuid language sql as $$ select u from pg_temp._v where k = p $$;
create function pg_temp.t(p text) returns text language sql as $$ select t from pg_temp._v where k = p $$;
-- Chama SQL como authenticated + JWT do perfil (a tela). Erro vira {"erro": …}.
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
create function pg_temp.r(p_quem text, p_call text) returns jsonb language sql as $$
  select pg_temp.chamar(pg_temp.v(p_quem), 'select ' || p_call) $$;
-- Chama como service_role (a Edge).
create function pg_temp.svc(p_call text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  execute 'select ' || p_call into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
create function pg_temp.m(j jsonb) returns text language sql as $$ select coalesce(j ->> 'msg', j ->> 'erro', j::text) $$;
create function pg_temp.ev(p_id text, p_tipo text, p_email text, p_tel text, p_nome text, p_tag text default null) returns jsonb
language sql as $$ select jsonb_build_array(jsonb_build_object('id', p_id, 'tipo', p_tipo, 'ocorreuEm', now()::text, 'email', p_email,
  'telefone', p_tel, 'nome', p_nome, 'tag', p_tag, 'utm', jsonb_build_object('campaign', 'ensaio-f5'))) $$;

insert into _v (k, u) select 'gestor', p.id from public.perfis p
 where p.cargo = 'admin' and p.status = 'ativo' and p.nome ilike 'jonathan%' order by p.criado_em limit 1;
insert into _v (k, u) select 'mp', v.perfil_id from crm.vendedor v where v.sigla = 'mp';
insert into _v (k, u) select 'ro', v.perfil_id from crm.vendedor v where v.sigla = 'ro';
insert into _v (k, u) select 'vis', p.id from public.perfis p
 where p.status = 'ativo' and p.cargo not in ('dev', 'admin', 'gestor')
   and not exists (select 1 from crm.vendedor v where v.perfil_id = p.id) order by p.criado_em limit 1;
-- pessoas fictícias pela entrada única (pessoas.registrar), como o formulário faria
insert into _v (k, u) select 'p1', (pessoas.registrar('{"nome":"Ensaio Fcinco Um","email":"ensaio.f5.um@exemplo.invalid","teste":true}', 'crm', null) ->> 'pessoa_id')::uuid;
insert into _v (k, u) select 'p2', (pessoas.registrar('{"nome":"Ensaio Fcinco Dois","telefone":"(99) 99876-0001","teste":true}', 'crm', null) ->> 'pessoa_id')::uuid;
insert into _v (k, u) select 'p3', (pessoas.registrar('{"nome":"Ensaio Fcinco Tres","email":"ensaio.f5.tres@exemplo.invalid","telefone":"(99) 99876-0002","teste":true}', 'crm', null) ->> 'pessoa_id')::uuid;
insert into _v (k, u) select 'p4', (pessoas.registrar('{"nome":"Ensaio Fcinco Quatro","email":"ensaio.f5.quatro@exemplo.invalid","telefone":"(99) 99876-0002","teste":true}', 'crm', null) ->> 'pessoa_id')::uuid;
insert into _v (k, u) select 'p5', (pessoas.registrar('{"nome":"Ensaio Fcinco Cinco","email":"ensaio.f5.cinco@exemplo.invalid","teste":true}', 'crm', null) ->> 'pessoa_id')::uuid;
-- produto/oferta reais para a linha ht (camada comercial só dentro da transação)
insert into _v (k, t) select 'prod', p.produto_id from fin.produtos p
 where (select count(*) from fin.ofertas o where o.produto_id = p.produto_id) >= 2 order by p.produto_id limit 1;
insert into _v (k, t) select 'oferta', o.oferta_codigo from fin.ofertas o where o.produto_id = pg_temp.t('prod') order by o.oferta_codigo limit 1;
insert into _v (k, t) select 'oferta2', o.oferta_codigo from fin.ofertas o where o.produto_id = pg_temp.t('prod') order by o.oferta_codigo offset 1 limit 1;
select set_config('crm.canal', 'migracao', true);
insert into crm.produto_comercial (produto_id, no_comercial, nome_comercial, linha, escada) values (pg_temp.t('prod'), true, 'Ensaio F5', 'ht', 'B');
insert into crm.oferta_comercial (oferta_codigo, vigente, condicao) values (pg_temp.t('oferta'), true, 'condição de ensaio');
insert into crm.pessoa_comercial (pessoa_id, opt_out, opt_out_em, opt_out_motivo) values (pg_temp.v('p5'), true, now(), 'ensaio');
select set_config('crm.canal', '', true);
-- segredos de webhook SÓ dentro da transação (valor aleatório; rollback apaga)
insert into _v (k, t) values ('tok_ac', encode(extensions.gen_random_bytes(24), 'hex')), ('tok_un', encode(extensions.gen_random_bytes(24), 'hex'));
select vault.create_secret(pg_temp.t('tok_ac'), 'crm_webhook_activecampaign', 'ensaio F5 (rollback)');
select vault.create_secret(pg_temp.t('tok_un'), 'crm_webhook_unnichat', 'ensaio F5 (rollback)');

do $p0$ begin
  perform pg_temp.ok('0.fixtures', pg_temp.v('gestor') is not null and pg_temp.v('mp') is not null and pg_temp.v('ro') is not null
                     and pg_temp.v('vis') is not null and pg_temp.v('p1') is not null and pg_temp.v('p2') is not null
                     and pg_temp.v('p3') is not null and pg_temp.v('p4') is not null and pg_temp.t('oferta2') is not null,
                     'gestor (admin real), mp, ro, visualizador, 5 pessoas fictícias, produto com 2 ofertas reais');
  perform pg_temp.ok('0.telefone_unico', (select count(*) from pessoas.candidatos_telefone(pessoas.chave_telefone('(99) 99876-0001'))) = 1,
                     'telefone da p2 tem 1 candidato (a própria p2)');
  perform pg_temp.ok('0.telefone_dividido', (select count(*) from pessoas.candidatos_telefone(pessoas.chave_telefone('(99) 99876-0002'))) = 2,
                     'telefone de p3 e p4 tem 2 candidatos');
end $p0$;

-- ─── 1. Permissões ───────────────────────────────────────────────────────────────────────────────────────────────────
do $p1$
declare v_anon int; v_auth_int int; v_auth_tela int; v_svc int; x text;
begin
  select count(*) into v_anon from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.ok('1.anon_nada', v_anon = 0, format('%s funções crm executáveis por anon', v_anon));
  select count(*) into v_auth_int from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace and p.proname in ('pessoa_por_email','anexar_integracao','ponto_integracao','emails_da_pessoa',
          'score_recuperacao','oferta_vigente_texto','limpa_sck','fila_entrada'))
      or (p.pronamespace = 'public'::regnamespace and p.proname in ('crm_integracao_receber','crm_integracao_reprocessar'))
     and has_function_privilege('authenticated', p.oid, 'execute');
  select count(*) into v_auth_int from pg_proc p
   where ((p.pronamespace = 'crm'::regnamespace and p.proname in ('pessoa_por_email','anexar_integracao','ponto_integracao','emails_da_pessoa',
          'score_recuperacao','oferta_vigente_texto','limpa_sck','fila_entrada'))
      or (p.pronamespace = 'public'::regnamespace and p.proname in ('crm_integracao_receber','crm_integracao_reprocessar')))
     and has_function_privilege('authenticated', p.oid, 'execute');
  perform pg_temp.ok('1.internos_fechados', v_auth_int = 0, format('%s internos/entrada de webhook executáveis por authenticated', v_auth_int));
  select count(*) into v_auth_tela from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('crm_filas','crm_links','crm_criar_fila','crm_encerrar_fila','crm_atribuir_item_fila','crm_atualizar_item_fila',
                       'crm_criar_link','crm_arquivar_link','crm_jornada') and has_function_privilege('authenticated', p.oid, 'execute');
  perform pg_temp.ok('1.telas_authenticated', v_auth_tela = 9, format('%s de 9 RPCs de tela com execute para authenticated', v_auth_tela));
  select count(*) into v_svc from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('crm_integracao_receber','crm_integracao_reprocessar') and has_function_privilege('service_role', p.oid, 'execute');
  perform pg_temp.ok('1.service_role', v_svc = 2, format('%s de 2 entradas de webhook com execute para service_role', v_svc));
  perform pg_temp.ok('1.tabela_evento_fechada', not has_table_privilege('authenticated', 'crm.evento_jornada', 'select')
                     and not has_table_privilege('authenticated', 'crm.fila_item', 'update')
                     and not has_table_privilege('authenticated', 'crm.link_rastreavel', 'insert'), 'evento_jornada sem select; fila/link sem escrita direta');
  -- authenticated chamando a entrada do webhook de verdade → negado
  x := pg_temp.m(pg_temp.r('gestor', format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', pg_temp.t('tok_ac'), '[]')));
  perform pg_temp.ok('1.gestor_nao_chama_webhook', x like 'permission denied%', 'gestor → ' || x);
end $p1$;
do $p1b$
declare v text;
begin
  begin
    execute 'set local role anon';
    perform public.crm_filas();
    v := 'executou';
  exception when insufficient_privilege then v := 'negado';
  end;
  execute 'reset role';
  perform pg_temp.ok('1.anon_negado', v = 'negado', 'anon → crm_filas ' || v);
end $p1b$;

-- ─── 2. Webhook: token do Vault, kill-switch, idempotência, casamento ───────────────────────────────────────────────
do $p2$
declare j jsonb; v_n0 bigint; v_n int;
begin
  select count(*) into v_n0 from crm.evento_jornada;
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', 'token-errado',
                          pg_temp.ev('t1', 'subscribe', 'ensaio.f5.um@exemplo.invalid', null, null)::text));
  perform pg_temp.ok('2.token_errado', (j ->> 'autorizado') = 'false', 'token errado → ' || j::text);
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'sendflow', 'qualquer',
                          pg_temp.ev('t1', 'entrada', null, '(99) 99876-0001', null)::text));
  perform pg_temp.ok('2.sem_segredo_recusa', (j ->> 'autorizado') = 'false', 'SendFlow sem segredo no Vault → ' || j::text);
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', pg_temp.t('tok_ac'),
                          pg_temp.ev('t1', 'subscribe', 'ensaio.f5.um@exemplo.invalid', null, null)::text));
  perform pg_temp.ok('2.desligado_nao_grava', j ->> 'ignorado' = 'desligado' and (select count(*) from crm.evento_jornada) = v_n0,
                     'activecampaign_ligado=false → ' || j::text);
  update crm.config set activecampaign_ligado = true, unnichat_ligado = true;
  -- e-mail com maiúscula/espaço casa com o identificador da p1
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', pg_temp.t('tok_ac'),
                          pg_temp.ev('ac-1', 'contact_tag_added', '  Ensaio.F5.Um@Exemplo.INVALID ', null, null, 'pediu-contato')::text));
  perform pg_temp.ok('2.email_casa', (j ->> 'anexados')::int = 1
                     and exists (select 1 from crm.evento_jornada e where e.fonte_evento_id = 'ac-1' and e.pessoa_id = pg_temp.v('p1')),
                     'tag AC anexada à p1 → ' || j::text);
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', pg_temp.t('tok_ac'),
                          pg_temp.ev('ac-1', 'contact_tag_added', 'ensaio.f5.um@exemplo.invalid', null, null, 'pediu-contato')::text));
  perform pg_temp.ok('2.idempotente', (j ->> 'duplicados')::int = 1
                     and (select count(*) from crm.evento_jornada e where e.fonte = 'activecampaign' and e.fonte_evento_id = 'ac-1') = 1,
                     'reenvio → ' || j::text);
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'activecampaign', pg_temp.t('tok_ac'),
                          pg_temp.ev('ac-2', 'subscribe', 'ninguem.f5.zz@exemplo.invalid', '(99) 99876-0001', 'Ensaio')::text));
  perform pg_temp.ok('2.email_sem_pessoa_nao_usa_fone', (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'ac-2') = 'sem_pessoa'
                     and not exists (select 1 from pessoas.identificadores i where i.chave = 'ninguem.f5.zz@exemplo.invalid'),
                     'e-mail desconhecido: não casa pelo telefone e não cria pessoa → ' ||
                     (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'ac-2'));
  -- sem e-mail: telefone com 1 candidato e nome compatível casa; nome diferente não; 2 candidatos não
  j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'unnichat', pg_temp.t('tok_un'),
                          (pg_temp.ev('un-1', 'convite_grupo', null, '+55 99 99876-0001', 'Ensaio Qualquer')
                           || pg_temp.ev('un-2', 'convite_grupo', null, '99998760001', 'Zeca Outro')
                           || pg_temp.ev('un-3', 'convite_grupo', null, '(99) 99876-0002', 'Ensaio')
                           || jsonb_build_array(jsonb_build_object('tipo', 'x')))::text));
  perform pg_temp.ok('2.fone_1_candidato', (select e.pessoa_id from crm.evento_jornada e where e.fonte_evento_id = 'un-1') = pg_temp.v('p2'),
                     'telefone sem e-mail, 1 candidato → p2');
  perform pg_temp.ok('2.fone_nome_diferente', (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'un-2') = 'telefone_ambiguo',
                     'nome incompatível → ' || (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'un-2'));
  perform pg_temp.ok('2.fone_2_candidatos', (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'un-3') = 'telefone_ambiguo',
                     '2 candidatos → ' || (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'un-3'));
  perform pg_temp.ok('2.invalido_conta', (j ->> 'invalidos')::int = 1 and (j ->> 'novos')::int = 3, 'lote → ' || j::text);
  select count(*) into v_n from crm.evento_jornada e where e.dados ? 'utm' and e.dados #>> '{utm,campaign}' = 'ensaio-f5';
  perform pg_temp.ok('2.utm_guardada', v_n >= 4, format('%s eventos com a UTM da entrada', v_n));
  -- reprocessar: a pessoa do e-mail aparece depois
  perform pessoas.registrar('{"nome":"Ensaio Fcinco Seis","email":"ninguem.f5.zz@exemplo.invalid","teste":true}', 'crm', null);
  j := pg_temp.svc('public.crm_integracao_reprocessar(100)');
  perform pg_temp.ok('2.reprocessa', (select e.resultado from crm.evento_jornada e where e.fonte_evento_id = 'ac-2') = 'anexado',
                     'sem_pessoa → anexado depois que a pessoa existe → ' || j::text);
end $p2$;

-- ─── 3. Jornada: pontos novos + kill-switch + visualizador ──────────────────────────────────────────────────────────
do $p3$
declare j jsonb;
begin
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('p1')));
  perform pg_temp.ok('3.ponto_ac', exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'activecampaign'
                       and x ->> 'tipo' = 'lista' and x ->> 'titulo' = 'Ganhou a tag · pediu-contato' and x #>> '{utm,campaign}' = 'ensaio-f5'),
                     'p1 tem "Ganhou a tag" com a UTM');
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('p2')));
  perform pg_temp.ok('3.ponto_unnichat_fone', exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'unnichat' and x ->> 'tipo' = 'grupo'),
                     'p2 tem o convite de grupo do Unnichat (casado pelo telefone)');
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('p3')));
  perform pg_temp.ok('3.fone_dividido_fora', not exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'unnichat'),
                     'p3 (telefone dividido) não recebe o evento só-telefone');
  update crm.config set activecampaign_ligado = false;
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('p1')));
  perform pg_temp.ok('3.killswitch_jornada', not exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'activecampaign'),
                     'AC desligado: jornada pula a fonte');
  update crm.config set activecampaign_ligado = true;
  j := pg_temp.r('vis', format('public.crm_jornada(%L)', pg_temp.v('p1')));
  perform pg_temp.ok('3.visualizador', j ->> 'estado' = '42501', 'visualizador → ' || j::text);
  j := pg_temp.r('mp', format('public.crm_jornada(%L)', pg_temp.v('p1')));
  perform pg_temp.ok('3.vendedor_sem_vinculo', j ->> 'estado' = '42501', 'vendedor sem vínculo com a p1 → ' || j::text);
end $p3$;

-- ─── 4. Filas ────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p4$
declare j jsonb; v_fila uuid; v_fila2 uuid; v_ia uuid; v_id uuid; v_ic uuid; v_log bigint;
begin
  -- escrita desligada (estado real): recusa
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'x', 'produto', 'ht', 'itens', '[]'::jsonb)));
  perform pg_temp.ok('4.manutencao', pg_temp.m(j) = 'CRM em manutenção: escrita desligada.', pg_temp.m(j));
  update crm.config set escrita_ligada = true;
  j := pg_temp.r('mp', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'x', 'produto', 'ht', 'itens', '[]'::jsonb)));
  perform pg_temp.ok('4.vendedor_nao_monta', pg_temp.m(j) = 'Só o gestor monta fila de recuperação.', pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'Ensaio fila', 'produto', 'ht',
         'ofertaCodigo', pg_temp.t('oferta'), 'projeto', 'ensaio-f5', 'itens', jsonb_build_array(
           jsonb_build_object('contatoId', pg_temp.v('p1'), 'sinais', jsonb_build_array('boleto_aberto', 'ficha_completa')),
           jsonb_build_object('contatoId', pg_temp.v('p1'), 'sinais', jsonb_build_array('carrinho')),
           jsonb_build_object('contatoId', pg_temp.v('p2'), 'sinais', jsonb_build_array('carrinho')),
           jsonb_build_object('contatoId', pg_temp.v('p3'), 'sinais', jsonb_build_array('carrinho', 'chat')),
           jsonb_build_object('contatoId', pg_temp.v('p5'), 'sinais', jsonb_build_array('boleto_aberto'))))));
  v_fila := (j ->> 'filaId')::uuid;
  perform pg_temp.ok('4.monta', (j ->> 'ok')::boolean and (j ->> 'itens')::int = 3 and (j ->> 'suprimidos')::int = 1,
                     'p1 repetida entra 1×, p5 opt-out fora → ' || (j ->> 'msg'));
  select id into v_ia from crm.fila_item where fila_id = v_fila and pessoa_id = pg_temp.v('p1');
  select id into v_id from crm.fila_item where fila_id = v_fila and pessoa_id = pg_temp.v('p2');
  select id into v_ic from crm.fila_item where fila_id = v_fila and pessoa_id = pg_temp.v('p3');
  perform pg_temp.ok('4.score_faixa', (select score::text || faixa from crm.fila_item where id = v_ia) = '60A'
                     and (select score::text || faixa from crm.fila_item where id = v_id) = '24D'
                     and (select score::text || faixa from crm.fila_item where id = v_ic) = '36C', 'scores 60A / 24D / 36C = calcularScore');
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'x', 'produto', 'ht',
         'itens', jsonb_build_array(jsonb_build_object('contatoId', pg_temp.v('p1'), 'sinais', jsonb_build_array('inventado'))))));
  perform pg_temp.ok('4.sinal_invalido', pg_temp.m(j) like '1 contato(s)%', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_id, 'tentando_contato'));
  perform pg_temp.ok('4.cd_travada', pg_temp.m(j) = 'Faixas C e D só depois de A e B zeradas (faltam 1).', pg_temp.m(j));
  v_log := (select coalesce(max(id), 0) from crm.log);
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_ia, 'tentando_contato'));
  perform pg_temp.ok('4.vendedor_assume', (j ->> 'ok')::boolean
                     and (select responsavel_id from crm.fila_item where id = v_ia) = pg_temp.v('mp'), 'item A sem dono: mp assume → ' || j::text);
  perform pg_temp.ok('4.log', exists (select 1 from crm.log l where l.id > v_log and l.entidade = 'fila' and l.entidade_id = v_ia::text
                       and l.resumo like 'Mudou % na fila: a_abordar → tentando_contato' and l.autor_id = pg_temp.v('mp')),
                     'log com resumo e autor');
  j := pg_temp.r('ro', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_ia, 'em_conversa'));
  perform pg_temp.ok('4.outro_vendedor', pg_temp.m(j) = 'Este contato da fila é de outro vendedor.', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_id, 'tentando_contato'));
  perform pg_temp.ok('4.cd_liberada', (j ->> 'ok')::boolean, 'A/B zeradas: D liberada → ' || j::text);
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_ia, 'ganho'));
  perform pg_temp.ok('4.ganho_so_pagamento', pg_temp.m(j) like 'Ganho só com pagamento aprovado%', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_ia, 'inventado'));
  perform pg_temp.ok('4.status_invalido', pg_temp.m(j) = 'Status inválido.', pg_temp.m(j));
  -- leitura com a regra da policy
  j := pg_temp.r('mp', 'public.crm_filas()');
  perform pg_temp.ok('4.ler_mp', jsonb_array_length(j -> 0 -> 'itens') = 3, format('mp vê %s itens (2 dele + 1 sem responsável)', jsonb_array_length(j -> 0 -> 'itens')));
  j := pg_temp.r('ro', 'public.crm_filas()');
  perform pg_temp.ok('4.ler_ro', jsonb_array_length(j -> 0 -> 'itens') = 1 and (j -> 0 ->> 'ofertaVigente') like 'Ensaio F5 ·%',
                     format('ro vê %s item (o sem responsável)', jsonb_array_length(j -> 0 -> 'itens')));
  j := pg_temp.r('gestor', 'public.crm_filas()');
  perform pg_temp.ok('4.ler_gestor', jsonb_array_length(j -> 0 -> 'itens') = 3
                     and (select bool_and(x ->> 'contatoId' is not null and x ? 'faixa' and x ? 'sinais') from jsonb_array_elements(j -> 0 -> 'itens') x),
                     'gestor vê os 3, formato ItemFila');
  j := pg_temp.r('vis', 'public.crm_filas()');
  perform pg_temp.ok('4.ler_vis', j ->> 'estado' = '42501', 'visualizador → ' || j::text);
  j := pg_temp.r('gestor', format('public.crm_atribuir_item_fila(%L, %L, %L)', v_fila, v_ic, pg_temp.v('ro')));
  perform pg_temp.ok('4.gestor_atribui', (j ->> 'ok')::boolean and (select responsavel_id from crm.fila_item where id = v_ic) = pg_temp.v('ro'), j::text);
  j := pg_temp.r('mp', format('public.crm_atribuir_item_fila(%L, %L, %L)', v_fila, v_ic, pg_temp.v('mp')));
  perform pg_temp.ok('4.vendedor_nao_atribui', pg_temp.m(j) = 'Só o gestor distribui a fila.', pg_temp.m(j));
  -- fila sem oferta vigente: não se aborda
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'Ensaio sem oferta', 'produto', 'ht',
         'itens', jsonb_build_array(jsonb_build_object('contatoId', pg_temp.v('p4'), 'sinais', jsonb_build_array('boleto_aberto', 'senhas'))))));
  v_fila2 := (j ->> 'filaId')::uuid;
  j := pg_temp.r('gestor', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila2,
                 (select id from crm.fila_item where fila_id = v_fila2), 'tentando_contato'));
  perform pg_temp.ok('4.sem_oferta', pg_temp.m(j) like 'Sem oferta vigente%', pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'x', 'produto', 'aurum',
         'ofertaCodigo', pg_temp.t('oferta'), 'itens', jsonb_build_array(jsonb_build_object('contatoId', pg_temp.v('p4'))))));
  perform pg_temp.ok('4.oferta_de_outra_linha', pg_temp.m(j) = 'Oferta não é deste produto.', pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_encerrar_fila(%L)', v_fila));
  j := pg_temp.r('mp', format('public.crm_atualizar_item_fila(%L, %L, %L)', v_fila, v_ia, 'em_conversa'));
  perform pg_temp.ok('4.encerrada', pg_temp.m(j) = 'Fila encerrada.', pg_temp.m(j));
  j := pg_temp.r('gestor', 'public.crm_filas()');
  perform pg_temp.ok('4.encerrada_some', not exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::uuid = v_fila), 'fila encerrada sai da lista padrão');
end $p4$;

-- ─── 5. Links ────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p5$
declare j jsonb; v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD');
begin
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L)', pg_temp.v('mp'), 'ht', 'Recuperação', 'WhatsApp'));
  perform pg_temp.ok('5.cria', (j ->> 'ok')::boolean and j ->> 'sck' = 'ht-recuperacao-' || v_hoje || '-whatsapp-mp'
                     and j ->> 'url' like 'https://pay.hotmart.com%off=' || pg_temp.t('oferta') || '&sck=ht-recuperacao-%&utm_source=comercial&utm_medium=whatsapp',
                     'sck = montarSck; url real da oferta vigente → ' || coalesce(j ->> 'sck', pg_temp.m(j)));
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L)', pg_temp.v('mp'), 'ht', 'recuperacao', 'whatsapp'));
  perform pg_temp.ok('5.duplicado', pg_temp.m(j) = 'Este link já existe.', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L)', pg_temp.v('ro'), 'ht', 'abordagem', 'whatsapp'));
  perform pg_temp.ok('5.so_para_si', pg_temp.m(j) = 'Vendedor só cria link para si mesmo.', pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_criar_link(%L, %L, %L, %L, null, %L, %L)', pg_temp.v('ro'), 'ht', 'abordagem', 'whatsapp', 'ht34-meteorico', 'HT-ABD-20261006-01'));
  perform pg_temp.ok('5.gestor_para_ro', (j ->> 'ok')::boolean and j ->> 'url' like '%&utm_campaign=ht34-meteorico&utm_content=HT-ABD-20261006-01',
                     'gestor cria para ro com projeto e conteúdo → ' || coalesce(j ->> 'sck', pg_temp.m(j)));
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L)', pg_temp.v('mp'), 'aurum', 'abordagem', 'whatsapp'));
  perform pg_temp.ok('5.sem_oferta', pg_temp.m(j) like 'Sem oferta vigente neste produto%', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L, %L)', pg_temp.v('mp'), 'ht', 'outra', 'whatsapp', pg_temp.t('oferta2')));
  perform pg_temp.ok('5.oferta_nao_vigente', pg_temp.m(j) = 'Oferta não é deste produto ou não está vigente.', pg_temp.m(j));
  j := pg_temp.r('mp', format('public.crm_criar_link(%L, %L, %L, %L, null, %L)', pg_temp.v('mp'), 'ht', 'outra', 'whatsapp', 'Com Espaço'));
  perform pg_temp.ok('5.projeto_invalido', pg_temp.m(j) like 'Chave do projeto inválida%', pg_temp.m(j));
  j := pg_temp.r('mp', 'public.crm_links()');
  perform pg_temp.ok('5.ler_mp', jsonb_array_length(j) = 1 and j -> 0 ? 'sck' and j -> 0 ->> 'vendas' is null, format('mp vê %s link (o dele)', jsonb_array_length(j)));
  j := pg_temp.r('gestor', 'public.crm_links(true)');
  perform pg_temp.ok('5.ler_gestor_vendas', jsonb_array_length(j) = 2 and (j -> 0 ->> 'vendas') = '0', format('gestor vê %s, vendas por SCK = %s', jsonb_array_length(j), j -> 0 ->> 'vendas'));
  j := pg_temp.r('ro', format('public.crm_arquivar_link(%L)', (select id from crm.link_rastreavel where sck like '%-mp')));
  perform pg_temp.ok('5.arquivar_alheio', pg_temp.m(j) = 'Este link não é seu.', pg_temp.m(j));
  j := pg_temp.r('vis', 'public.crm_links()');
  perform pg_temp.ok('5.ler_vis', j ->> 'estado' = '42501', 'visualizador → ' || j::text);
end $p5$;

-- ─── 6. Tempo (2× cada, cache quente na 2ª): jornada, webhook, filas ────────────────────────────────────────────────
do $p6$
declare t0 timestamptz; i int; v_ms numeric[] := '{}'; j jsonb;
begin
  for i in 1..2 loop
    t0 := clock_timestamp(); j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('p2')));
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
  end loop;
  for i in 1..2 loop
    t0 := clock_timestamp();
    j := pg_temp.svc(format('public.crm_integracao_receber(%L, %L, %L::jsonb)', 'unnichat', pg_temp.t('tok_un'),
                            pg_temp.ev('tempo-' || i, 'workbook', null, '(99) 99876-0001', 'Ensaio')::text));
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
  end loop;
  for i in 1..2 loop
    t0 := clock_timestamp(); j := pg_temp.r('gestor', 'public.crm_filas(true)');
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
  end loop;
  perform pg_temp.ok('6.tempo', true, format('jornada p2 %s/%s ms; webhook 1 evento por telefone %s/%s ms; crm_filas %s/%s ms',
                     v_ms[1], v_ms[2], v_ms[3], v_ms[4], v_ms[5], v_ms[6]));
end $p6$;

select count(*) filter (where linha like 'OK%') ok, count(*) filter (where linha like 'ERRADO%') errado,
       string_agg(linha, E'\n') filter (where linha like 'ERRADO%' or passo = '6.tempo') detalhe from _z_out;
-- (para ver linha a linha: select linha from _z_out order by n;)
rollback;

-- ═══ PARTE B: dados reais (só leitura) + massa de fila (1 chamada, begin … rollback) ════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
-- pré-índices SEM concurrently (dentro da transação; rollback desfaz). Seguram lock de escrita em controle.unnichat_evento
-- (parada desde 08/09) e respondi.respostas (escrita 1×/dia 09:10) até o rollback: não rodar perto das 09:10.
create index ix_unnichat_evento_email on controle.unnichat_evento (lower(btrim((payload -> 'contact') ->> 'email')));
create index ix_respostas_fone_sem_email on respondi.respostas (controle.fone_key(telefone)) where email is null and telefone is not null;

-- ═══ CORPO DA F5 (20261006c_crm_f5_integracoes.sql, md5 45909f75927ad7817457bb8df9639dd9, copiado sem mudança; mudou a migration, gerar de novo) ═══
-- 20261006c: F5 do Comercial — integrações como FONTE DE EVENTO da jornada (ActiveCampaign, Unnichat, Respondi, SendFlow)
--            + filas de recuperação + links rastreáveis (UTM + SCK)
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Depende da F2 (20261005t, aplicada em 06/10 como versão 20261006041654
-- durante a preparação desta fase): a guarda aborta sem ela. Rodar antes, fora de transação: 20261006c_pre_indices.sql
-- (create index concurrently em tabelas de controle e respondi). Ensaio: 20261006c_ensaio.sql (begin … rollback, sobre a
-- F2 já aplicada; a F2 não entra no begin). Medidas, decisões e o que muda no
-- front: 20261006c.explain.md. Ao aplicar: renomear o arquivo para a versão gravada em supabase_migrations.schema_migrations.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §3.7, §5 (5.2, 5.3, 5.6), §6 (F5), §8. Pessoa = pessoas.pessoas
-- (convergencia-pessoas-crm.md), não crm.pessoa.
--
-- O QUE FAZ
--   1. REAPROVEITA o que já está no banco, sem copiar: controle.lead_active (lista AC), controle.grupo_evento_unificado
--      (SendFlow), respondi.respostas, controle.unnichat_evento (legado, parado desde 08/09) continuam sendo lidos NA HORA
--      pela jornada. Nada é duplicado em tabela do CRM.
--   2. crm.evento_jornada (nome escolhido para não colidir com crm.integracao_evento da F4 = caixa de entrada BRUTA do
--      WhatsApp): só o que NÃO existe no banco — evento de webhook (tag/lista/descadastro do AC, conversa
--      Unnichat, entrada em grupo SendFlow direto) — mínimo (sem payload bruto), idempotente por (fonte, id do evento),
--      já com a pessoa resolvida. Entrada única: public.crm_integracao_receber (só service_role; a Edge
--      crm-integracao-webhook chama). Token do webhook conferido CONTRA O VAULT (nome crm_webhook_<fonte>): o segredo
--      nunca fica em arquivo nem em env da Edge.
--      Casamento (manual §7, F0): e-mail primeiro (identificadores, thb_alunos e compradores, cada um pelo índice dele;
--      SEM criar pessoa nova: aluno/comprador ganham só a linha de referência, como pessoas.garantir). Sem e-mail:
--      telefone por controle.fone_key só com EXATAMENTE 1 candidato e nome compatível. Nome nunca casa. Sem casar =
--      evento guardado com resultado 'sem_pessoa'/'telefone_ambiguo' (dá para reprocessar quando a pessoa existir).
--      ActiveCampaign NÃO é CRM: só gera ponto de jornada; descadastro/bounce NÃO viram opt-out comercial (decisão).
--   3. Kill-switch por integração em crm.config (desliga em ~10 s): activecampaign_ligado, sendflow_ligado,
--      respondi_ligado e o novo unnichat_ligado. Desligado = o webhook não grava nada E a jornada pula a fonte.
--      Todos nascem/continuam FALSE (SendFlow sem chave: pronto e desligado).
--   4. public.crm_jornada recriada a partir do corpo VIVO (md5 conferido na guarda): + kill-switch por fonte; + pontos de
--      crm.evento_jornada; + Unnichat legado por e-mail; + Respondi sem e-mail por telefone; grupo (SendFlow) e
--      telefone só pela chave com 1 candidato (antes: qualquer pessoa com o mesmo fone_key via o grupo da outra).
--   5. Filas de recuperação: crm.fila, crm.fila_item (score/faixa = calcularScore/faixaDoScore do domínio), RPCs
--      crm_filas (leitura), crm_criar_fila / crm_encerrar_fila / crm_atribuir_item_fila (gestor),
--      crm_atualizar_item_fila (responsável ou gestor; C/D só com A/B zeradas; sem oferta vigente não se aborda;
--      "ganho" só com pagamento aprovado na Hotmart da linha da fila).
--   6. Links rastreáveis: crm.link_rastreavel + crm_links / crm_criar_link / crm_arquivar_link. SCK = montarSck do domínio
--      (linha-acao-AAAAMMDD-canal-sigla); URL real da oferta vigente (fin.ofertas.bruto_json.direct_offer_link_for_creator)
--      + sck + utm_source=comercial, utm_medium=canal, utm_campaign=projeto, utm_content=conteúdo.
--   7. Log: crm.tg_log (F0) em fila, fila_item (update/delete) e link. Evento de integração não vai para o log (é dado
--      de fonte, não ação de pessoa).
--
-- FORA: Manychat (fora do escopo); supressão de WhatsApp (F4); MQL do Respondi criando negócio (§5.6, depende de
--   critério por formulário: decisão); montagem automática da fila a partir de sinais (fica para depois: a F5 recebe
--   os itens prontos do gestor); Clint (F6). Nenhuma API externa é chamada pelo banco.
--
-- AS 5 PERGUNTAS (números em 20261006c.explain.md)
--   escala: evento_jornada cresce por evento de webhook (AC: dezenas a centenas/dia em lançamento); leitura sempre
--     por pessoa (índice pessoa_id) e com limite. Fila ≤ 5.000 itens por montagem; leitura ≤ 50 filas × 5.000 itens.
--   índice: jornada lê cada fonte pelo índice da expressão exata (guarda confere): ix_lead_active_email_lower,
--     ix_geu_fone, respostas_email_idx, ix_respostas_fone_sem_email (novo), ix_unnichat_evento_email (novo),
--     evento_jornada_pessoa_idx. Casamento por e-mail: thb_alunos_email_uidx, ix_compradores_email_lower_all,
--     identificadores (tipo, chave). Telefone: pessoas.candidatos_telefone (índices da F0).
--   frequência: webhook = 1 chamada por evento (sem cron novo). Jornada ao abrir a ficha. Sem polling.
--   repetição: 1 chamada de RPC por lote de eventos (até 100); crm_filas traz filas + itens numa chamada.
--   reversão: kill-switch por fonte (false = webhook ignora e jornada pula); escrita_ligada=false desliga fila/link;
--     bloco REVERSÃO no fim (tabelas novas sem FK de fora: drop; jornada volta ao corpo da F1).
--
-- PREMISSAS (guarda aborta se faltar): F2 aplicada (crm.guarda_escrita, crm.res, crm.erro_dados, crm.vendedor_ativo,
--   public.crm_mover_etapa); F5 não aplicada; corpo vivo de public.crm_jornada = o da F1 (md5); índices das fontes com a
--   expressão exata (inclui os 2 da pré); colunas das fontes; pessoas.candidatos_telefone/garantir/pessoa_do_aluno/
--   pessoa_do_comprador/nomes_compativeis; mkt.sem_acento; vault.decrypted_secrets.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  if to_regprocedure('crm.guarda_escrita()') is null or to_regprocedure('crm.res(boolean,text,jsonb)') is null
     or to_regprocedure('crm.erro_dados(text,text,text)') is null or to_regprocedure('crm.vendedor_ativo(uuid)') is null
     or to_regprocedure('crm.nome_pessoa(uuid)') is null or to_regprocedure('crm.nome_perfil(uuid)') is null
     or to_regprocedure('public.crm_mover_etapa(uuid,uuid)') is null then
    raise exception '20261006c: F2 (20261005t) não aplicada';
  end if;
  if to_regclass('crm.evento_jornada') is not null or to_regclass('crm.fila') is not null
     or to_regclass('crm.link_rastreavel') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                   and column_name = 'unnichat_ligado') then
    raise exception '20261006c: objetos da F5 já existem (migration já aplicada?)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                    and column_name in ('activecampaign_ligado', 'sendflow_ligado', 'respondi_ligado', 'escrita_ligada')
                  group by table_name having count(*) = 4) then
    raise exception '20261006c: crm.config sem os kill-switches da F0';
  end if;
  -- recriar a jornada a partir do corpo VIVO (manual §3): aborta se alguém mudou depois da F1
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.crm_jornada(uuid,integer)'))
     is distinct from '4e4cbddd4f9de648ab9ffc71441e8936' then
    raise exception '20261006c: corpo vivo de public.crm_jornada diferente do da F1: refazer a seção 4 a partir dele';
  end if;
  if to_regprocedure('pessoas.candidatos_telefone(text)') is null or to_regprocedure('pessoas.garantir(text[])') is null
     or to_regprocedure('pessoas.pessoa_do_aluno(uuid)') is null or to_regprocedure('pessoas.pessoa_do_comprador(uuid)') is null
     or to_regprocedure('pessoas.nomes_compativeis(text,text)') is null or to_regprocedure('pessoas.norm_email(text)') is null
     or to_regprocedure('pessoas.norm_telefone(text)') is null or to_regprocedure('pessoas.chave_telefone(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null or to_regclass('vault.decrypted_secrets') is null then
    raise exception '20261006c: funções da F0/mkt ou vault ausentes';
  end if;
  select string_agg(x.s || '.' || x.i, ', ') into v_falta
    from (values
      ('controle', 'ix_lead_active_email_lower',     '(lower(btrim(email)))'),
      ('controle', 'ix_geu_fone',                    '(fone_key)'),
      ('controle', 'ix_unnichat_evento_email',       '(lower(btrim(((payload -> ''contact''::text) ->> ''email''::text))))'),
      ('respondi', 'respostas_email_idx',            '(email)'),
      ('respondi', 'ix_respostas_fone_sem_email',    '(controle.fone_key(telefone)) WHERE ((email IS NULL) AND (telefone IS NOT NULL))'),
      ('public',   'thb_alunos_email_uidx',          'lower(TRIM(BOTH FROM email))) WHERE ((email IS NOT NULL) AND (email <> ''''::text))'),
      ('public',   'ix_compradores_email_lower_all', '(lower(btrim((email)::text)))'),
      ('fin',      'hotmart_transacoes_email_idx',   '(lower(TRIM(BOTH FROM comprador_email)))')
    ) x(s, i, trecho)
   where not exists (select 1 from pg_indexes pi
                       join pg_index ix on ix.indexrelid = to_regclass(quote_ident(pi.schemaname) || '.' || quote_ident(pi.indexname))
                      where pi.schemaname = x.s and pi.indexname = x.i and ix.indisvalid
                        and position(x.trecho in pi.indexdef) > 0);
  if v_falta is not null then
    raise exception '20261006c: índice ausente, inválido ou com expressão diferente: % (rodar 20261006c_pre_indices.sql antes)', v_falta;
  end if;
  select string_agg(x.s || '.' || x.t || '.' || x.c, ', ') into v_falta
    from (values ('controle','unnichat_evento','payload'), ('controle','unnichat_evento','tipo'),
                 ('controle','unnichat_evento','tag_nome'), ('controle','unnichat_evento','recebido_em'),
                 ('respondi','respostas','telefone'), ('respondi','respostas','respondido_em'),
                 ('fin','ofertas','bruto_json'), ('fin','hotmart_transacoes','origem_sck'),
                 ('fin','hotmart_transacoes','valor_cobrado'), ('crm','vendedor','sigla')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then raise exception '20261006c: colunas ausentes: %', v_falta; end if;
end
$guarda$;

-- ─── 1. Kill-switches ────────────────────────────────────────────────────────────────────────────────────────────────
alter table crm.config add column unnichat_ligado boolean not null default false;
comment on column crm.config.activecampaign_ligado is 'F5: false = webhook AC ignora (não grava) e a jornada não mostra lista/tag do AC.';
comment on column crm.config.sendflow_ligado is 'F5: false = webhook SendFlow ignora e a jornada não mostra grupos (controle.grupo_evento_unificado).';
comment on column crm.config.respondi_ligado is 'F5: false = a jornada não mostra respostas do Respondi (respondi.respostas).';
comment on column crm.config.unnichat_ligado is 'F5: false = webhook Unnichat ignora e a jornada não mostra Unnichat (legado + webhook).';

-- ─── 2. Eventos de integração (só o que não existe no banco) ─────────────────────────────────────────────────────────
-- Mínimo para a jornada: sem payload bruto (LGPD). E-mail e telefone guardados só como CHAVE normalizada (para casar e
-- reprocessar). nome só para a checagem de nome compatível no casamento por telefone.
create table crm.evento_jornada (
  id              bigint generated always as identity primary key,
  fonte           text not null check (fonte in ('activecampaign', 'unnichat', 'sendflow', 'respondi')),
  fonte_evento_id text not null check (length(fonte_evento_id) between 1 and 200),
  tipo            text not null check (tipo ~ '^[a-z0-9_.:-]{1,60}$'),
  ocorreu_em      timestamptz not null,
  recebido_em     timestamptz not null default now(),
  email_norm      text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key        text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  nome            text check (nome is null or length(nome) <= 160),
  lista           text check (lista is null or length(lista) <= 200),
  tag             text check (tag is null or length(tag) <= 200),
  dados           jsonb not null default '{}' check (jsonb_typeof(dados) = 'object' and length(dados::text) <= 4000),
  pessoa_id       uuid references pessoas.pessoas(id) on delete restrict,
  resultado       text not null default 'pendente'
                    check (resultado in ('pendente', 'anexado', 'sem_pessoa', 'telefone_ambiguo', 'sem_identificador')),
  processado_em   timestamptz,
  unique (fonte, fonte_evento_id),
  check ((resultado = 'anexado') = (pessoa_id is not null))
);
alter table crm.evento_jornada enable row level security;
create index evento_jornada_pessoa_idx on crm.evento_jornada (pessoa_id, ocorreu_em desc) where pessoa_id is not null;
create index evento_jornada_email_idx  on crm.evento_jornada (email_norm) where pessoa_id is null and email_norm is not null;
create index evento_jornada_fone_idx   on crm.evento_jornada (fone_key) where pessoa_id is null and email_norm is null and fone_key is not null;
create index evento_jornada_recebido_idx on crm.evento_jornada (recebido_em);
comment on table crm.evento_jornada is 'F5: eventos de webhook (AC, Unnichat, SendFlow) que viram ponto de jornada. Mínimo, '
  'idempotente por (fonte, fonte_evento_id), pessoa resolvida por e-mail (telefone só sem e-mail e 1 candidato). 20261006c.';

-- Pessoa pelo e-mail SEM criar pessoa nova (aluno/comprador ganham a linha de referência, como pessoas.garantir).
-- Mesma ordem do pessoas.resolver: aluno, comprador, identificador. Cada fonte pelo seu índice; valor já normalizado.
create function crm.pessoa_por_email(p_email text) returns uuid
language plpgsql set search_path = '' as $$
declare v_email text := pessoas.norm_email(p_email); v_lead uuid; v_aluno uuid; v_comprador uuid; v uuid;
begin
  if v_email is null then return null; end if;
  select a.id into v_aluno from public.thb_alunos a
   where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
  if v_aluno is not null then return pessoas.pessoa_do_aluno(v_aluno); end if;
  select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;
  if v_comprador is not null then return pessoas.pessoa_do_comprador(v_comprador); end if;
  select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
  return v_lead;
end
$$;

-- Resolve a pessoa de UM evento e grava o resultado. E-mail → pessoa_por_email. Sem e-mail: telefone com exatamente 1
-- candidato (pessoas.candidatos_telefone = pessoas + alunos ativos + compradores) e nome compatível. Nome sozinho nunca.
create function crm.anexar_integracao(p_id bigint) returns text
language plpgsql set search_path = '' as $$
declare e crm.evento_jornada%rowtype; v_pessoa uuid; v_res text; v_n int; v_ent text; v_nome_ent text;
begin
  select * into e from crm.evento_jornada where id = p_id for update;
  if not found then return null; end if;
  if e.email_norm is not null then
    v_pessoa := crm.pessoa_por_email(e.email_norm);
    v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
  elsif e.fone_key is not null then
    select count(*), min(t.ent), min(t.nome_ent) into v_n, v_ent, v_nome_ent from pessoas.candidatos_telefone(e.fone_key) t;
    if v_n = 0 then v_res := 'sem_pessoa';
    elsif v_n = 1 and pessoas.nomes_compativeis(e.nome, v_nome_ent) then
      v_pessoa := (pessoas.garantir(array[v_ent]))[1];
      v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
    else v_res := 'telefone_ambiguo';
    end if;
  else
    v_res := 'sem_identificador';
  end if;
  update crm.evento_jornada set pessoa_id = v_pessoa, resultado = v_res, processado_em = now() where id = p_id;
  return v_res;
end
$$;

-- Tipo de ponto + título do evento (para a jornada). Puro.
create function crm.ponto_integracao(p_fonte text, p_tipo text, p_lista text, p_tag text,
                                     out tipo_ponto text, out titulo text)
language sql immutable set search_path = '' as $$
  select case
           when p_fonte = 'activecampaign' then 'lista'
           when p_fonte = 'sendflow' then 'grupo'
           when p_fonte = 'respondi' then 'pesquisa'
           when p_fonte = 'unnichat' and p_tipo = 'template_enviado' then 'disparo'
           when p_fonte = 'unnichat' and p_tipo in ('convite_grupo', 'entrou_link') then 'grupo'
           else 'conversa' end,
         case
           when p_fonte = 'activecampaign' then case p_tipo
               when 'subscribe' then 'Entrou na lista'
               when 'unsubscribe' then 'Saiu da lista'
               when 'contact_tag_added' then 'Ganhou a tag'
               when 'contact_tag_removed' then 'Perdeu a tag'
               when 'bounce' then 'E-mail voltou (bounce)'
               else 'ActiveCampaign: ' || p_tipo end
             || coalesce(' · ' || nullif(p_tag, ''), ' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'sendflow' then case when p_tipo = 'saida' then 'Saiu do grupo' else 'Entrou no grupo' end
             || coalesce(' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'unnichat' then 'Unnichat: ' || coalesce(nullif(p_tag, ''), replace(p_tipo, '_', ' '))
           else 'Respondeu: ' || coalesce(nullif(p_lista, ''), 'formulário') end;
$$;

-- Entrada única dos webhooks (a Edge crm-integracao-webhook chama com a service role). Lote de até 100 eventos:
-- [{id, tipo, ocorreuEm, email, telefone, nome, lista, tag, utm:{source,medium,campaign,content}}].
-- p_chave = token que o provedor mandou; conferido contra o Vault 'crm_webhook_<fonte>' (sem segredo no Vault = recusa).
-- Kill-switch desligado = não grava nada. Reenvio do mesmo evento = no-op (duplicado).
create function public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ligado boolean; v_seg text; e jsonb; v_id bigint; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0;
  v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end
    into v_ligado from crm.config c;
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
    begin
      v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, now());
    exception when others then v_quando := null;
    end;
    if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
       or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > now() + interval '1 day' then
      v_inval := v_inval + 1; continue;
    end if;
    v_utm := jsonb_strip_nulls(jsonb_build_object(
               'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
               'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
    insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, fone_key, nome, lista, tag, dados)
    values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando,
            pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
            nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
            nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
            case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
    begin
      v_res := crm.anexar_integracao(v_id);
      if v_res = 'anexado' then v_anex := v_anex + 1; end if;
    exception when others then
      raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    end;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'invalidos', v_inval);
end
$$;

-- Reprocessa eventos que ainda não casaram (a pessoa pode ter aparecido depois). Lote limitado; só service_role
-- (rodar à mão ou por cron diário quando a fonte estiver ligada — NÃO agendado aqui).
create function public.crm_integracao_reprocessar(p_limite int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v_n int := 0; v_anex int := 0;
begin
  for r in select e.id from crm.evento_jornada e
            where e.pessoa_id is null and e.resultado in ('pendente', 'sem_pessoa', 'telefone_ambiguo')
            order by e.id limit least(greatest(coalesce(p_limite, 500), 1), 5000) loop
    v_n := v_n + 1;
    if crm.anexar_integracao(r.id) = 'anexado' then v_anex := v_anex + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'processados', v_n, 'anexados', v_anex);
end
$$;

-- ─── 3. E-mails da pessoa (grupo de alias + irmãos em fin.identidade). Mesma lógica da jornada (F1). ────────────────
create function crm.emails_da_pessoa(p_atual uuid) returns text[]
language plpgsql stable set search_path = '' as $$
declare v_g uuid[] := pessoas.grupo(pessoas.atual(p_atual)); v_compr uuid[]; v_emails text[];
begin
  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  return array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
end
$$;

-- ─── 4. Jornada: corpo vivo da F1 + fontes da F5 com kill-switch + telefone só com 1 candidato ──────────────────────
create or replace function public.crm_jornada(p_pessoa uuid, p_limite int default 500) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_atual uuid; v_g uuid[]; v_emails text[]; v_fks text[]; v_fks1 text[]; v_compr uuid[];
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
  v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is null or not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a esta pessoa.' using errcode = '42501';
  end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  v_atual := pessoas.atual(p_pessoa);
  v_g := pessoas.grupo(v_atual);

  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  -- e-mails irmãos pelo grafo fin.identidade (por chave, no momento da leitura; recalculado de hora em hora)
  v_emails := array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
  v_fks := array(
    select k from (
      select controle.fone_key(coalesce(a.telefone_e164, a.telefone)) k from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
       where p.id = any(v_g)
      union select controle.fone_key((c.telefone)::text) from public.compradores c where c.id = any(v_compr) and c.telefone is not null
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'telefone'
    ) s where k is not null limit 10);
  -- F5: evento só com telefone (grupo, Respondi sem e-mail) é da pessoa só se a chave tem EXATAMENTE 1 candidato
  -- (manual §7: telefone nunca junta duas pessoas). Calculado só se alguma fonte por telefone estiver ligada.
  if v_sf or v_rs then
    v_fks1 := array(select k from unnest(v_fks) k where (select count(*) from pessoas.candidatos_telefone(k)) = 1);
  else
    v_fks1 := '{}';
  end if;

  with pts as (
    -- inscrição (origem com a UTM daquela entrada)
    (select 'or-' || o.id id, 'inscricao' tipo, o.quando em,
            'Inscrição' || coalesce(' · ' || pr.sigla, '') titulo, o.campanha detalhe, 'formulario' fonte,
            lower(pr.sigla) lancamento, null::text produto,
            jsonb_build_object('source', o.utm_source, 'medium', o.utm_medium, 'campaign', o.utm_campaign, 'content', o.utm_content) utm,
            null::numeric valor, null::uuid negocio_id
       from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id
      where o.pessoa_id = any(v_g) order by o.quando desc limit v_lim)
    union all
    (select 'ev-' || e.id, 'pesquisa', e.quando, case e.tipo when 'mql' then 'Qualificou como MQL' else 'Não qualificou (MQL)' end,
            null, 'formulario', lower(pr.sigla), null, null, null, null
       from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id
      where e.pessoa_id = any(v_g) and e.tipo in ('mql', 'nao_mql') order by e.quando desc limit v_lim)
    union all
    -- Hotmart: compra, reembolso, checkout (índice hotmart_transacoes_email_idx = lower(btrim(comprador_email)))
    (select 'hm-' || h.transacao,
            case when h.status in ('APPROVED', 'COMPLETE') then 'compra'
                 when h.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED') then 'reembolso' else 'checkout' end,
            coalesce(h.aprovado_em, h.pedido_em),
            case when h.status in ('APPROVED', 'COMPLETE') then 'Compra aprovada'
                 when h.status in ('REFUNDED', 'PARTIALLY_REFUNDED') then 'Reembolso'
                 when h.status = 'CHARGEBACK' then 'Chargeback'
                 when h.status in ('WAITING_PAYMENT', 'PRINTED_BILLET') then 'Boleto/Pix gerado'
                 when h.status = 'EXPIRED' then 'Pagamento expirado'
                 when h.status = 'CANCELLED' then 'Compra cancelada'
                 else 'Checkout: ' || lower(h.status) end || coalesce(' · ' || h.produto_nome, ''),
            nullif(concat_ws(' · ', 'oferta ' || h.oferta_codigo, h.metodo), ''), 'hotmart', null, pcm.linha,
            case when h.origem_sck is not null then jsonb_build_object('sck', h.origem_sck) end,
            h.valor_cobrado, null
       from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
       left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id and pcm.no_comercial
      where lower(btrim(h.comprador_email)) = any(v_emails)
      order by coalesce(h.aprovado_em, h.pedido_em) desc nulls last limit v_lim)
    union all
    -- lista do ActiveCampaign (índice ix_lead_active_email_lower). F5: kill-switch activecampaign_ligado.
    (select 'ac-' || la.id, 'lista', coalesce(la.opt_in_at, la.atualizado_em), 'Entrou na lista' || coalesce(' · ' || la.origem, ''),
            la.segmento, 'activecampaign', null, null,
            jsonb_build_object('source', la.utm_source, 'campaign', la.utm_campaign, 'content', la.utm_content), null, null
       from controle.lead_active la
      where v_ac and lower(btrim(la.email)) = any(v_emails)
      order by coalesce(la.opt_in_at, la.atualizado_em) desc limit v_lim)
    union all
    -- grupos de WhatsApp (índice ix_geu_fone, chave controle.fone_key). F5: sendflow_ligado + chave com 1 candidato.
    (select 'gr-' || g.id, 'grupo', g.ocorreu_em,
            case g.tipo when 'entrada' then 'Entrou no grupo' else 'Saiu do grupo' end || coalesce(' · ' || g.group_name, ''),
            g.segmento, 'sendflow', null, null, null, null, null
       from controle.grupo_evento_unificado g
      where v_sf and g.fone_key = any(v_fks1)
      order by g.ocorreu_em desc limit v_lim)
    union all
    -- pesquisas/formulários (índice respostas_email_idx; e-mail já normalizado na fonte). Nunca cpf/respostas.
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            null, 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email = any(v_emails)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: resposta SEM e-mail, pelo telefone com 1 candidato (índice ix_respostas_fone_sem_email, predicado repetido)
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            'casado pelo telefone', 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email is null and r.telefone is not null and controle.fone_key(r.telefone) = any(v_fks1)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: Unnichat legado (controle.unnichat_evento, parado desde 08/09) pelo e-mail do contato (ix_unnichat_evento_email)
    (select 'un-' || u.id, (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).tipo_ponto, u.recebido_em,
            (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).titulo, null, 'unnichat', null, null, null, null, null
       from controle.unnichat_evento u
      where v_un and lower(btrim((u.payload -> 'contact') ->> 'email')) = any(v_emails)
      order by u.recebido_em desc limit v_lim)
    union all
    -- F5: eventos de webhook já casados com a pessoa (crm.evento_jornada), cada fonte com o seu kill-switch
    (select 'ie-' || ie.id, (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).tipo_ponto, ie.ocorreu_em,
            (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).titulo, null, ie.fonte, null, null,
            ie.dados -> 'utm', null, null
       from crm.evento_jornada ie
      where ie.pessoa_id = any(v_g)
        and ((ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
             or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs))
      order by ie.ocorreu_em desc limit v_lim)
    union all
    -- mini-CRM do CS (só leitura; D4 coexistir)
    (select 'cs-' || c.id, 'nota', coalesce(c.ultimo_contato_em, c.atualizado_em, c.criado_em),
            'CS: ' || coalesce(es.nome, 'sem estágio') || coalesce(' · ' || c.evento, ''),
            case when c.responsavel is not null then 'responsável: ' || c.responsavel end, 'crm', null, null, null, null, null
       from cs.contatos c left join cs.estagios es on es.id = c.estagio_id
      where c.comprador_id = any(v_compr))
    union all
    -- CRM: negócios (mesma regra da policy de negócio)
    (select 'ng-' || n.id, 'negocio', n.criado_em, 'Negócio criado · ' || f.nome, null, 'crm', f.projeto, n.linha,
            case when n.utm <> '{}'::jsonb then n.utm end, null, n.id
       from crm.negocio n join crm.funil f on f.id = n.funil_id
      where n.pessoa_id = any(v_g) and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by n.criado_em desc limit v_lim)
    union all
    (select 'lg-' || l.id, 'negocio', l.em,
            case l.acao when 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa')
                        when 'marcou_ganho' then 'Ganho' when 'marcou_perdido' then 'Perdido'
                        else 'Troca de dono' end || ' · ' || f.nome,
            l.resumo, 'crm', f.projeto, n.linha, null,
            case when l.acao = 'marcou_ganho' then n.valor end, n.id
       from crm.log l
       join crm.negocio n on n.id::text = l.entidade_id
       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g)
      order by nt.em desc limit v_lim)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'contatoId', v_atual, 'tipo', p.tipo, 'em', p.em, 'titulo', p.titulo, 'detalhe', p.detalhe,
           'fonte', p.fonte, 'lancamento', p.lancamento, 'produto', p.produto, 'utm', p.utm, 'valor', p.valor,
           'negocioId', p.negocio_id) order by p.em desc nulls last, p.id), '[]'::jsonb)
    into v
    from (select * from pts where pts.em is not null order by pts.em desc limit v_lim) p;
  return v;
end
$$;

-- ─── 5. Filas de recuperação (§3.7; processo montar-fila-de-recuperacao.md) ──────────────────────────────────────────
-- calcularScore do domínio (regras.ts): comportamento de compra conta só o maior (boleto 40 OU carrinho 24); teto 100.
create function crm.score_recuperacao(p_sinais text[]) returns smallint
language sql immutable set search_path = '' as $$
  select least(100,
           case when 'boleto_aberto' = any(p_sinais) then 40 when 'carrinho' = any(p_sinais) then 24 else 0 end
         + coalesce((select sum(case s when 'ficha_completa' then 20 when 'senhas' then 16 when 'chat' then 12
                                       when 'workbook' then 6 when 'apostila' then 4 when 'pesquisa' then 6
                                       when 'comunidade' then 4 when 'grupo' then 3 when 'advogado_contador' then 4
                                       when 'quer_parceria' then 6 else 0 end)
                       from (select distinct unnest(coalesce(p_sinais, '{}'))) x(s)), 0))::smallint;
$$;

create table crm.fila (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(btrim(nome)) between 1 and 120),
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,   -- sem oferta vigente não se aborda
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),
  criada_por    uuid references public.perfis(id) on delete restrict,
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz,
  encerrada_por uuid references public.perfis(id) on delete restrict
);
create index fila_criada_idx on crm.fila (criada_em desc);

create table crm.fila_item (
  id             uuid primary key default gen_random_uuid(),
  fila_id        uuid not null references crm.fila(id) on delete restrict,
  pessoa_id      uuid not null references pessoas.pessoas(id) on delete restrict,   -- leitura resolve pessoas.atual
  score          smallint not null check (score between 0 and 100),
  faixa          char(1) generated always as (case when score >= 60 then 'A' when score >= 40 then 'B'
                                                   when score >= 25 then 'C' else 'D' end) stored,
  sinais         text[] not null default '{}'
                   check (sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas','chat',
                                          'workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                          'quer_parceria','respondeu_sem_retorno']::text[]),
  status         text not null default 'a_abordar'
                   check (status in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                     'declinou','sem_interesse','numero_invalido')),
  responsavel_id uuid references crm.vendedor(perfil_id) on delete restrict,
  alterado_por   uuid references public.perfis(id) on delete restrict,
  alterado_em    timestamptz,
  criado_em      timestamptz not null default now(),
  unique (fila_id, pessoa_id)
);
create index fila_item_faixa_idx       on crm.fila_item (fila_id, faixa, status);
create index fila_item_responsavel_idx on crm.fila_item (responsavel_id) where responsavel_id is not null;
create index fila_item_pessoa_idx      on crm.fila_item (pessoa_id);

-- Oferta da fila ainda vigente? Devolve o texto que a tela mostra (null = não se aborda).
create function crm.oferta_vigente_texto(p_oferta text) returns text
language sql stable security definer set search_path = '' as $$
  select concat_ws(' · ', coalesce(pc.nome_comercial, o.nome), o.oferta_codigo, oc.condicao)
    from fin.ofertas o
    join crm.oferta_comercial oc on oc.oferta_codigo = o.oferta_codigo
    left join crm.produto_comercial pc on pc.produto_id = o.produto_id
   where o.oferta_codigo = p_oferta and oc.vigente
     and (oc.valida_ate is null or oc.valida_ate >= (now() at time zone 'America/Sao_Paulo')::date);
$$;

-- ─── 6. Links rastreáveis (§3.7; playbook seção 8) ───────────────────────────────────────────────────────────────────
-- Pedaço do SCK = limpa() de montarSck: sem acento, minúsculo, só [a-z0-9].
create function crm.limpa_sck(p text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(mkt.sem_acento(coalesce(p, '')), '[^A-Za-z0-9]+', '', 'g'));
$$;

create table crm.link_rastreavel (
  id            uuid primary key default gen_random_uuid(),
  vendedor_id   uuid not null references crm.vendedor(perfil_id) on delete restrict,
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text not null references fin.ofertas(oferta_codigo) on delete restrict,   -- link real, nunca "EXEMPLO"
  acao          text not null check (length(btrim(acao)) between 1 and 60),
  canal         text not null check (canal ~ '^[a-z0-9]{1,30}$'),
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),     -- utm_campaign
  conteudo      text check (conteudo is null or conteudo ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$'), -- utm_content
  sck           text not null unique check (sck ~ '^[a-z0-9_]+-[a-z0-9]+-[0-9]{8}-[a-z0-9]+-[a-z0-9]+$'),
  url           text not null check (url ~ '^https://pay\.hotmart\.com' and length(url) <= 1000),
  criado_por    uuid references public.perfis(id) on delete restrict,
  criado_em     timestamptz not null default now(),
  arquivado_em  timestamptz
);
create index link_vendedor_idx on crm.link_rastreavel (vendedor_id, criado_em desc);

-- ─── 7. Log (crm.tg_log da F0), RLS e policies ───────────────────────────────────────────────────────────────────────
create trigger fila_log_ins_del after insert or delete on crm.fila for each row execute function crm.tg_log('fila', 'id');
create trigger fila_log_upd after update on crm.fila for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
-- itens: só alteração/remoção (a montagem é 1 linha de log na fila, não 5.000)
create trigger fila_item_log_del after delete on crm.fila_item for each row execute function crm.tg_log('fila', 'id');
create trigger fila_item_log_upd after update on crm.fila_item for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
create trigger link_log_ins_del after insert or delete on crm.link_rastreavel for each row execute function crm.tg_log('link', 'id');
create trigger link_log_upd after update on crm.link_rastreavel for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('link', 'id');

do $rls$
declare t text;
begin
  foreach t in array array['fila', 'fila_item', 'link_rastreavel'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated', t);
    execute format('grant select on crm.%I to authenticated', t);
  end loop;
  -- evento_jornada: fechada (só as funções definer leem)
  revoke all on crm.evento_jornada from public, anon, authenticated;
end
$rls$;
create policy fila_ler on crm.fila for select to authenticated using ((select crm.eh_comercial()));
create policy fila_item_ler on crm.fila_item for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (responsavel_id = (select auth.uid()) or responsavel_id is null)));
create policy link_ler on crm.link_rastreavel for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and vendedor_id = (select auth.uid())));

-- ─── 8. RPCs de leitura ──────────────────────────────────────────────────────────────────────────────────────────────
-- Filas (FilaRecuperacao[]): DEFINER porque o texto da oferta vigente lê fin.ofertas; itens com a MESMA regra da
-- policy fila_item_ler. contatoId = pessoa atual (alias resolvido em lote).
create function public.crm_filas(p_incluir_encerradas boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with f as (
    select x.* from crm.fila x where coalesce(p_incluir_encerradas, false) or x.encerrada_em is null
     order by x.criada_em desc limit 50),
  it as (
    select i.*, row_number() over (partition by i.fila_id order by i.score desc, i.id) rn
      from crm.fila_item i
     where i.fila_id in (select f.id from f) and (v_gestor or i.responsavel_id = v_eu or i.responsavel_id is null)),
  al as (select * from crm.atual_de(array(select distinct it.pessoa_id from it where it.rn <= 5000)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'nome', f.nome, 'produto', f.linha, 'criadaEm', f.criada_em,
           'ofertaVigente', crm.oferta_vigente_texto(f.oferta_codigo), 'ofertaCodigo', f.oferta_codigo,
           'projeto', f.projeto, 'encerradaEm', f.encerrada_em,
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', it.id, 'contatoId', al.atual, 'score', it.score, 'faixa', it.faixa, 'sinais', to_jsonb(it.sinais),
                        'status', it.status, 'responsavelId', it.responsavel_id, 'alteradoPor', it.alterado_por,
                        'alteradoEm', it.alterado_em) order by it.score desc, it.id)
                       from it left join al on al.pessoa_id = it.pessoa_id
                      where it.fila_id = f.id and it.rn <= 5000), '[]'::jsonb))
           order by f.criada_em desc), '[]'::jsonb)
    into v from f;
  return v;
end
$$;

-- Links (LinkRastreavel[]): gestor vê todos, vendedor os seus. p_vendas = true soma as vendas Hotmart pelo SCK
-- (2 Seq Scans em fin.hotmart_transacoes sem índice em origem_sck: sob pedido, nunca ao abrir a tela).
create function public.crm_links(p_vendas boolean default false, p_incluir_arquivados boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with l as (
    select x.* from crm.link_rastreavel x
     where (v_gestor or x.vendedor_id = v_eu) and (coalesce(p_incluir_arquivados, false) or x.arquivado_em is null)
     order by x.criado_em desc limit 2000),
  vd as (
    select h.origem_sck sck, count(*) filter (where h.status in ('APPROVED', 'COMPLETE')) vendas,
           coalesce(sum(h.valor_cobrado) filter (where h.status in ('APPROVED', 'COMPLETE')), 0) receita
      from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
     where coalesce(p_vendas, false) and h.origem_sck = any(array(select l.sck from l))
     group by h.origem_sck)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'vendedorId', l.vendedor_id, 'produto', l.linha, 'acao', l.acao, 'url', l.url, 'sck', l.sck,
           'canal', l.canal, 'ofertaCodigo', l.oferta_codigo, 'projeto', l.projeto, 'conteudo', l.conteudo,
           'criadoEm', l.criado_em, 'arquivadoEm', l.arquivado_em,
           'vendas', case when coalesce(p_vendas, false) then coalesce(vd.vendas, 0) end,
           'receita', case when coalesce(p_vendas, false) then coalesce(vd.receita, 0) end) order by l.criado_em desc), '[]'::jsonb)
    into v
    from l left join vd on vd.sck = l.sck;
  return v;
end
$$;

-- ─── 9. RPCs de escrita: fila ────────────────────────────────────────────────────────────────────────────────────────
-- Itens de entrada da montagem: pessoa ATUAL (alias resolvido) + sinais sem repetição.
create function crm.fila_entrada(p_itens jsonb) returns table (pessoa uuid, sinais text[])
language sql stable set search_path = '' as $$
  select pessoas.atual(crm.uuid_ou_null(x ->> 'contatoId')),
         array(select distinct s from jsonb_array_elements_text(case when jsonb_typeof(x -> 'sinais') = 'array'
                                                                     then x -> 'sinais' else '[]'::jsonb end) s order by 1)
    from jsonb_array_elements(case when jsonb_typeof(p_itens) = 'array' then p_itens else '[]'::jsonb end) x;
$$;

-- Monta a fila (só gestor). p: {nome, produto, ofertaCodigo?, projeto?, itens:[{contatoId, sinais:[]}]} (≤ 5.000).
-- Score/faixa calculados no banco. Contato com opt-out fica fora (suprimidos); repetido (mesma pessoa atual) entra 1×.
create function public.crm_criar_fila(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_nome text; v_linha text; v_oferta text; v_projeto text; v_id uuid; v_n int; v_sup int; v_inval int;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor monta fila de recuperação.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_nome := btrim(coalesce(p ->> 'nome', ''));
  v_linha := p ->> 'produto';
  v_oferta := nullif(btrim(coalesce(p ->> 'ofertaCodigo', '')), '');
  v_projeto := nullif(lower(btrim(coalesce(p ->> 'projeto', ''))), '');
  if v_nome = '' then return crm.res(false, 'Dê um nome à fila.'); end if;
  if not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_oferta is not null and not exists (
       select 1 from fin.ofertas o join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial
        where o.oferta_codigo = v_oferta and pc.linha = v_linha) then
    return crm.res(false, 'Oferta não é deste produto.');
  end if;
  if jsonb_typeof(p -> 'itens') <> 'array' or jsonb_array_length(p -> 'itens') = 0 then
    return crm.res(false, 'Fila sem contatos.');
  end if;
  if jsonb_array_length(p -> 'itens') > 5000 then return crm.res(false, 'Fila com mais de 5.000 contatos: divida.'); end if;

  select count(*) filter (where e.pessoa is null or not exists (select 1 from pessoas.pessoas pp where pp.id = e.pessoa)
                            or not (e.sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas',
                                    'chat','workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                    'quer_parceria','respondeu_sem_retorno']::text[]))
    into v_inval from crm.fila_entrada(p -> 'itens') e;
  if v_inval > 0 then return crm.res(false, format('%s contato(s) inexistente(s) ou com sinal inválido.', v_inval)); end if;
  select count(distinct e.pessoa) into v_sup from crm.fila_entrada(p -> 'itens') e
   where exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(e.pessoa)) and pc.opt_out);

  perform set_config('crm.resumo', format('Montou a fila "%s" (%s)', v_nome, v_linha), true);
  insert into crm.fila (nome, linha, oferta_codigo, projeto, criada_por)
  values (v_nome, v_linha, v_oferta, v_projeto, auth.uid()) returning id into v_id;
  insert into crm.fila_item (fila_id, pessoa_id, score, sinais)
  select v_id, i.pessoa, crm.score_recuperacao(i.sinais), i.sinais
    from (select distinct on (e.pessoa) e.pessoa, e.sinais from crm.fila_entrada(p -> 'itens') e
           order by e.pessoa, cardinality(e.sinais) desc) i
   where not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(i.pessoa)) and pc.opt_out);
  get diagnostics v_n = row_count;
  return crm.res(true, format('Fila montada: %s contato(s)%s.', v_n,
                              case when v_sup > 0 then format(', %s fora por opt-out', v_sup) else '' end),
                 jsonb_build_object('filaId', v_id, 'itens', v_n, 'suprimidos', v_sup));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_encerrar_fila(p_fila uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor encerra fila.'); end if;
  select * into f from crm.fila x where x.id = p_fila for update;
  if not found then return crm.res(false, 'Fila não encontrada.'); end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila já encerrada.'); end if;
  perform set_config('crm.resumo', format('Encerrou a fila "%s"', f.nome), true);
  update crm.fila x set encerrada_em = now(), encerrada_por = auth.uid() where x.id = p_fila;
  return crm.res(true);
end
$$;

-- Gestor define o responsável de um item (null = devolve para a fila).
create function public.crm_atribuir_item_fila(p_fila uuid, p_item uuid, p_responsavel uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; it crm.fila_item%rowtype; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor distribui a fila.'); end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if p_responsavel is not null and not crm.vendedor_ativo(p_responsavel) then return crm.res(false, 'Vendedor inválido ou inativo.'); end if;
  if it.responsavel_id is not distinct from p_responsavel then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Fila "%s": %s passou para %s', f.nome, crm.nome_pessoa(it.pessoa_id),
                                          crm.nome_perfil(p_responsavel)), true);
  update crm.fila_item x set responsavel_id = p_responsavel, alterado_por = auth.uid(), alterado_em = now() where x.id = p_item;
  return crm.res(true);
end
$$;

-- atualizarItemFila do port. Mensagens no tom do mock. Regras do playbook:
--   responsável ou gestor (item sem responsável: o vendedor que mexe assume); fila encerrada não muda;
--   sem oferta vigente não se aborda; C/D só com A/B zeradas (pendentesAB = A/B ainda "a_abordar" na fila inteira);
--   opt-out não volta a ser abordado; "ganho" só com pagamento aprovado na Hotmart da linha desde a montagem.
create function public.crm_atualizar_item_fila(p_fila uuid, p_item uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false);
        it crm.fila_item%rowtype; f crm.fila%rowtype; v_pend int; v_emails text[]; v_resp uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_status is null or p_status not in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                          'declinou','sem_interesse','numero_invalido') then
    return crm.res(false, 'Status inválido.');
  end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if not (v_gestor or it.responsavel_id is not distinct from v_eu
          or (it.responsavel_id is null and coalesce(crm.eh_vendedor(), false))) then
    return crm.res(false, 'Este contato da fila é de outro vendedor.');
  end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if it.status = p_status then return crm.res(true); end if;
  if crm.oferta_vigente_texto(f.oferta_codigo) is null then
    return crm.res(false, 'Sem oferta vigente: não se aborda. O gestor define a oferta da fila.');
  end if;
  if it.faixa in ('C', 'D') then
    select count(*) into v_pend from crm.fila_item x where x.fila_id = p_fila and x.faixa in ('A', 'B') and x.status = 'a_abordar';
    if v_pend > 0 then return crm.res(false, format('Faixas C e D só depois de A e B zeradas (faltam %s).', v_pend)); end if;
  end if;
  if p_status in ('tentando_contato', 'em_conversa', 'vai_comprar')
     and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(it.pessoa_id))) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  if p_status = 'ganho' then
    v_emails := crm.emails_da_pessoa(it.pessoa_id);
    if not exists (
      select 1 from (select * from fin.hotmart_transacoes where conta = 'academy'
                     union all
                     select * from fin.hotmart_transacoes where conta = 'escritorio') h
        join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = f.linha
       where lower(btrim(h.comprador_email)) = any(v_emails) and h.status in ('APPROVED', 'COMPLETE')
         and h.aprovado_em >= f.criada_em) then
      return crm.res(false, 'Ganho só com pagamento aprovado na Hotmart (produto da fila, depois da montagem).');
    end if;
  end if;
  v_resp := coalesce(it.responsavel_id, case when not v_gestor then v_eu end);
  perform set_config('crm.resumo', format('Mudou %s na fila: %s → %s', crm.nome_pessoa(it.pessoa_id), it.status, p_status), true);
  update crm.fila_item x set status = p_status, responsavel_id = v_resp, alterado_por = v_eu, alterado_em = now()
   where x.id = p_item;
  return crm.res(true);
end
$$;

-- ─── 10. RPCs de escrita: link ───────────────────────────────────────────────────────────────────────────────────────
-- criarLink do port (+ opcionais). Vendedor só para si; gestor para qualquer vendedor ativo. Oferta: a informada (tem de
-- ser vigente e da linha) ou a ÚNICA vigente da linha. SCK = montarSck (linha-acao-AAAAMMDD-canal-sigla, data de São Paulo).
create function public.crm_criar_link(p_vendedor uuid, p_produto text, p_acao text, p_canal text,
                                      p_oferta text default null, p_projeto text default null, p_conteudo text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_sigla text; v_oferta text; v_n int; v_base text; v_sck text; v_canal text;
        v_projeto text := nullif(lower(btrim(coalesce(p_projeto, ''))), ''); v_conteudo text := nullif(btrim(coalesce(p_conteudo, '')), '');
        v_url text; v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_vendedor is null or btrim(coalesce(p_acao, '')) = '' or crm.limpa_sck(p_acao) = '' then
    return crm.res(false, 'Informe vendedor e ação.');
  end if;
  if not coalesce(crm.eh_gestor(), false) and p_vendedor is distinct from v_eu then
    return crm.res(false, 'Vendedor só cria link para si mesmo.');
  end if;
  select v.sigla into v_sigla from crm.vendedor v where v.perfil_id = p_vendedor;
  if v_sigla is null or not crm.vendedor_ativo(p_vendedor) then return crm.res(false, 'Informe vendedor e ação.'); end if;
  v_canal := crm.limpa_sck(p_canal);
  if v_canal = '' then return crm.res(false, 'Informe o canal (ex.: whatsapp).'); end if;
  if not exists (select 1 from crm.linha l where l.chave = p_produto and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_projeto is not null and v_projeto !~ '^[a-z0-9][a-z0-9_-]{0,59}$' then
    return crm.res(false, 'Chave do projeto inválida (letras minúsculas, números, - e _).');
  end if;
  if v_conteudo is not null and v_conteudo !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$' then
    return crm.res(false, 'Código do conteúdo inválido (letras, números, - e _).');
  end if;
  -- ofertas vigentes da linha
  select count(*), min(o.oferta_codigo) into v_n, v_oferta
    from fin.ofertas o
    join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial and pc.linha = p_produto
   where crm.oferta_vigente_texto(o.oferta_codigo) is not null
     and (p_oferta is null or o.oferta_codigo = p_oferta);
  if p_oferta is not null and v_n = 0 then return crm.res(false, 'Oferta não é deste produto ou não está vigente.'); end if;
  if v_n = 0 then return crm.res(false, 'Sem oferta vigente neste produto: o gestor define em Produtos e ofertas.'); end if;
  if v_n > 1 then return crm.res(false, 'Há mais de uma oferta vigente neste produto: escolha a oferta.'); end if;
  v_sck := p_produto || '-' || crm.limpa_sck(p_acao) || '-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD')
           || '-' || v_canal || '-' || crm.limpa_sck(v_sigla);
  if exists (select 1 from crm.link_rastreavel l where l.sck = v_sck) then return crm.res(false, 'Este link já existe.'); end if;
  select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
    into v_base from fin.ofertas o where o.oferta_codigo = v_oferta;
  v_url := v_base || case when position('?' in v_base) > 0 then '&' else '?' end
           || 'sck=' || v_sck || '&utm_source=comercial&utm_medium=' || v_canal
           || coalesce('&utm_campaign=' || v_projeto, '') || coalesce('&utm_content=' || v_conteudo, '');
  perform set_config('crm.resumo', format('Criou link rastreável %s', v_sck), true);
  insert into crm.link_rastreavel (vendedor_id, linha, oferta_codigo, acao, canal, projeto, conteudo, sck, url, criado_por)
  values (p_vendedor, p_produto, v_oferta, btrim(p_acao), v_canal, v_projeto, v_conteudo, v_sck, v_url, v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('linkId', v_id, 'sck', v_sck, 'url', v_url));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_arquivar_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; l crm.link_rastreavel%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into l from crm.link_rastreavel x where x.id = p_link for update;
  if not found then return crm.res(false, 'Link não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or l.vendedor_id = auth.uid()) then return crm.res(false, 'Este link não é seu.'); end if;
  if l.arquivado_em is not null then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Arquivou o link %s', l.sck), true);
  update crm.link_rastreavel x set arquivado_em = now() where x.id = p_link;
  return crm.res(true);
end
$$;

-- ─── 11. Grants e conferência ────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  -- internos: ninguém executa direto
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('pessoa_por_email','anexar_integracao','ponto_integracao','emails_da_pessoa','score_recuperacao',
                                'oferta_vigente_texto','limpa_sck','fila_entrada') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- entrada dos webhooks: só service_role (a Edge)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_integracao_receber', 'crm_integracao_reprocessar') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- telas: authenticated (guarda no corpo)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_filas','crm_links','crm_criar_fila','crm_encerrar_fila','crm_atribuir_item_fila',
                                'crm_atualizar_item_fila','crm_criar_link','crm_arquivar_link') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- crm_jornada foi recriada com create or replace: mantém o ACL, mas confere de novo
  revoke all on function public.crm_jornada(uuid, integer) from public, anon;
  grant execute on function public.crm_jornada(uuid, integer) to authenticated;
end
$grants$;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006c: função executável por anon/PUBLIC: %', v_aberto; end if;
  if has_function_privilege('authenticated', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'crm.anexar_integracao(bigint)', 'execute')
     or has_function_privilege('authenticated', 'crm.pessoa_por_email(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_atualizar_item_fila(uuid,uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_jornada(uuid,integer)', 'execute') then
    raise exception '20261006c: grants das funções fora do esperado';
  end if;
  select string_agg(table_name || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC')
          or (grantee = 'authenticated' and (privilege_type <> 'SELECT' or table_name = 'evento_jornada')));
  if v_aberto is not null then raise exception '20261006c: grant indevido em crm: %', v_aberto; end if;
  if coalesce((select c.activecampaign_ligado or c.sendflow_ligado or c.unnichat_ligado from crm.config c), true) then
    -- não liga nada: só confere que a migration não ligou (respondi_ligado pode já estar ligado pelo Arthur)
    raise exception '20261006c: kill-switch de AC/SendFlow/Unnichat ligado (esperado false ao aplicar)';
  end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamadas separadas; desliga do mesmo jeito com false) ════════════════════════
-- 1. Segredo de cada webhook no Vault (valor gerado na hora, nunca em arquivo/chat):
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_activecampaign', 'F5 webhook AC');
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_unnichat', 'F5 webhook Unnichat');
--      (SendFlow: só quando houver a chave/conta; até lá fica sem segredo = recusa tudo.)
-- 2. Deploy da Edge crm-integracao-webhook (verify_jwt = false) e cadastro da URL no AC/Unnichat.
-- 3. update crm.config set activecampaign_ligado = true;   -- e/ou respondi_ligado, unnichat_ligado, sendflow_ligado
-- 4. Reprocessar o que não casou (opcional): select public.crm_integracao_reprocessar(500);  -- como service_role/postgres

-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- update crm.config set activecampaign_ligado = false, sendflow_ligado = false, respondi_ligado = false, unnichat_ligado = false;
--   (desliga em ~10 s, sem deploy: preferir isto)
-- Desfazer de vez (tabelas novas; dado de fila/link escrito fica no crm.log):
-- drop function public.crm_integracao_receber(text,text,jsonb), public.crm_integracao_reprocessar(int),
--   public.crm_filas(boolean), public.crm_links(boolean,boolean), public.crm_criar_fila(jsonb), public.crm_encerrar_fila(uuid),
--   public.crm_atribuir_item_fila(uuid,uuid,uuid), public.crm_atualizar_item_fila(uuid,uuid,text),
--   public.crm_criar_link(uuid,text,text,text,text,text,text), public.crm_arquivar_link(uuid);
-- jornada: recriar public.crm_jornada com o corpo da 20261005s (md5 4e4cbddd4f9de648ab9ffc71441e8936).
-- drop table crm.fila_item, crm.fila, crm.link_rastreavel, crm.evento_jornada;
-- drop function crm.pessoa_por_email(text), crm.anexar_integracao(bigint), crm.ponto_integracao(text,text,text,text),
--   crm.emails_da_pessoa(uuid), crm.score_recuperacao(text[]), crm.oferta_vigente_texto(text), crm.limpa_sck(text),
--   crm.fila_entrada(jsonb);
-- alter table crm.config drop column unnichat_ligado;
-- drop index concurrently controle.ix_unnichat_evento_email; drop index concurrently respondi.ix_respostas_fone_sem_email;  -- à parte

-- ═══ FIM DOS CORPOS (F2 + F5) ═══════════════════════════════════════════════════════════════════════════════════════
create temp table _v (k text primary key, u uuid, t text) on commit drop;
create function pg_temp.v(p text) returns uuid language sql as $$ select u from pg_temp._v where k = p $$;
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
create function pg_temp.r(p_quem text, p_call text) returns jsonb language sql as $$
  select pg_temp.chamar(pg_temp.v(p_quem), 'select ' || p_call) $$;
-- explain (analyze, buffers) como postgres; devolve só as linhas do plano (sem valores de dado)
create function pg_temp.explica(p_sql text) returns setof text language plpgsql as $$
declare l text;
begin
  for l in execute 'explain (analyze, buffers, costs off) ' || p_sql loop return next l; end loop;
end $$;
create function pg_temp.ms(p_quem text, p_call text) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); j jsonb;
begin
  j := pg_temp.r(p_quem, p_call);
  if j ? 'erro' then raise exception 'ms: %', j ->> 'erro'; end if;
  return round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
end $$;

insert into _v (k, u) select 'gestor', p.id from public.perfis p
 where p.cargo = 'admin' and p.status = 'ativo' and p.nome ilike 'jonathan%' order by p.criado_em limit 1;
update crm.config set activecampaign_ligado = true, sendflow_ligado = true, respondi_ligado = true, unnichat_ligado = true;

-- B1: pessoa REAL (só referência, rollback) cujo telefone está em grupos e tem 1 candidato
do $b1$
declare r record; v_n int;
begin
  for r in select distinct g.fone_key from controle.grupo_evento_unificado g order by g.fone_key limit 300 loop
    select count(*) into v_n from pessoas.candidatos_telefone(r.fone_key);
    if v_n = 1 and not exists (select 1 from _v where k = 'g1') then
      insert into _v (k, u, t) select 'g1', (pessoas.garantir(array[t.ent]))[1], r.fone_key from pessoas.candidatos_telefone(r.fone_key) t;
    elsif v_n >= 2 and not exists (select 1 from _v where k = 'g2') then
      insert into _v (k, u, t) select 'g2', (pessoas.garantir(array[(select min(t.ent) from pessoas.candidatos_telefone(r.fone_key) t)]))[1], r.fone_key;
    end if;
    exit when exists (select 1 from _v where k = 'g1') and exists (select 1 from _v where k = 'g2');
  end loop;
end $b1$;
-- B2: resposta Respondi SEM e-mail cujo telefone tem 1 candidato
do $b2$
declare r record; v_n int;
begin
  for r in select distinct controle.fone_key(x.telefone) fk from respondi.respostas x
            where x.email is null and x.telefone is not null and controle.fone_key(x.telefone) is not null limit 300 loop
    select count(*) into v_n from pessoas.candidatos_telefone(r.fk);
    if v_n = 1 then
      insert into _v (k, u, t) select 'r1', (pessoas.garantir(array[t.ent]))[1], r.fk from pessoas.candidatos_telefone(r.fk) t;
      exit;
    end if;
  end loop;
end $b2$;
-- B3: contato do Unnichat legado cujo e-mail é de comprador
insert into _v (k, u) select 'u1', crm.pessoa_por_email(u.payload -> 'contact' ->> 'email')
  from controle.unnichat_evento u
 where exists (select 1 from public.compradores c where lower(btrim((c.email)::text)) = lower(btrim(u.payload -> 'contact' ->> 'email')))
 limit 1;

create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, '')) $$;

do $b4$
declare j jsonb; v_geu int;
begin
  perform pg_temp.ok('B0.fixtures', (select count(*) from _v where k in ('g1','g2','r1','u1') and u is not null) = 4,
                     (select string_agg(k || '=' || (u is not null)::text, ' ') from _v where k <> 'gestor'));
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('g1')));
  perform pg_temp.ok('B4.grupo_1_candidato', exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'sendflow'),
                     format('pessoa real com telefone de 1 candidato: %s pontos de grupo',
                            (select count(*) from jsonb_array_elements(j) x where x ->> 'fonte' = 'sendflow')));
  select count(*) into v_geu from controle.grupo_evento_unificado g where g.fone_key = (select t from _v where k = 'g2');
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('g2')));
  perform pg_temp.ok('B4.grupo_dividido', v_geu > 0 and not exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'sendflow'),
                     format('telefone com 2+ candidatos: %s eventos de grupo na fonte, 0 na jornada (a F1 mostraria)', v_geu));
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('r1')));
  perform pg_temp.ok('B4.respondi_por_fone', exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'respondi' and x ->> 'detalhe' = 'casado pelo telefone'),
                     'resposta sem e-mail entra pelo telefone de 1 candidato');
  j := pg_temp.r('gestor', format('public.crm_jornada(%L)', pg_temp.v('u1')));
  perform pg_temp.ok('B4.unnichat_legado', exists (select 1 from jsonb_array_elements(j) x where x ->> 'fonte' = 'unnichat'),
                     format('Unnichat legado por e-mail: %s pontos', (select count(*) from jsonb_array_elements(j) x where x ->> 'fonte' = 'unnichat')));
  perform pg_temp.ok('B5.tempo_jornada', true, format('crm_jornada (todas as fontes ligadas) g1 %s/%s ms, u1 %s/%s ms, r1 %s/%s ms',
     pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('g1'))), pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('g1'))),
     pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('u1'))), pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('u1'))),
     pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('r1'))), pg_temp.ms('gestor', format('public.crm_jornada(%L)', pg_temp.v('r1')))));
end $b4$;

-- B6: os ramos novos usam o índice (2× cada; valores reais só dentro do plano como parâmetro → trocados por $)
insert into _z_out (passo, linha) select 'B6.respondi_fone', regexp_replace(l, '''[^'']*''', '''…''', 'g')
  from pg_temp.explica(format('select r.uuid from respondi.respostas r where r.email is null and r.telefone is not null and controle.fone_key(r.telefone) = any(%L::text[])',
                              array[(select t from _v where k = 'r1')])) l;
insert into _z_out (passo, linha) select 'B6.unnichat_email', regexp_replace(l, '''[^'']*''', '''…''', 'g')
  from pg_temp.explica(format('select u.id from controle.unnichat_evento u where lower(btrim((u.payload -> ''contact'') ->> ''email'')) = any(%L::text[])',
                              crm.emails_da_pessoa(pg_temp.v('u1')))) l;
insert into _z_out (passo, linha) select 'B6.unnichat_email_2', regexp_replace(l, '''[^'']*''', '''…''', 'g')
  from pg_temp.explica(format('select u.id from controle.unnichat_evento u where lower(btrim((u.payload -> ''contact'') ->> ''email'')) = any(%L::text[])',
                              crm.emails_da_pessoa(pg_temp.v('u1')))) l where l like '%Execution Time%';

select passo, linha from _z_out order by n;
rollback;

-- ═══ PARTE B2: fila com 5.000 contatos (1 chamada, begin … rollback) ═══
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
-- pré-índices SEM concurrently (dentro da transação; rollback desfaz). Seguram lock de escrita em controle.unnichat_evento
-- (parada desde 08/09) e respondi.respostas (escrita 1×/dia 09:10) até o rollback: não rodar perto das 09:10.
create index ix_unnichat_evento_email on controle.unnichat_evento (lower(btrim((payload -> 'contact') ->> 'email')));
create index ix_respostas_fone_sem_email on respondi.respostas (controle.fone_key(telefone)) where email is null and telefone is not null;

-- ═══ CORPO DA F5 (20261006c_crm_f5_integracoes.sql, md5 45909f75927ad7817457bb8df9639dd9, copiado sem mudança; mudou a migration, gerar de novo) ═══
-- 20261006c: F5 do Comercial — integrações como FONTE DE EVENTO da jornada (ActiveCampaign, Unnichat, Respondi, SendFlow)
--            + filas de recuperação + links rastreáveis (UTM + SCK)
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Depende da F2 (20261005t, aplicada em 06/10 como versão 20261006041654
-- durante a preparação desta fase): a guarda aborta sem ela. Rodar antes, fora de transação: 20261006c_pre_indices.sql
-- (create index concurrently em tabelas de controle e respondi). Ensaio: 20261006c_ensaio.sql (begin … rollback, sobre a
-- F2 já aplicada; a F2 não entra no begin). Medidas, decisões e o que muda no
-- front: 20261006c.explain.md. Ao aplicar: renomear o arquivo para a versão gravada em supabase_migrations.schema_migrations.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §3.7, §5 (5.2, 5.3, 5.6), §6 (F5), §8. Pessoa = pessoas.pessoas
-- (convergencia-pessoas-crm.md), não crm.pessoa.
--
-- O QUE FAZ
--   1. REAPROVEITA o que já está no banco, sem copiar: controle.lead_active (lista AC), controle.grupo_evento_unificado
--      (SendFlow), respondi.respostas, controle.unnichat_evento (legado, parado desde 08/09) continuam sendo lidos NA HORA
--      pela jornada. Nada é duplicado em tabela do CRM.
--   2. crm.evento_jornada (nome escolhido para não colidir com crm.integracao_evento da F4 = caixa de entrada BRUTA do
--      WhatsApp): só o que NÃO existe no banco — evento de webhook (tag/lista/descadastro do AC, conversa
--      Unnichat, entrada em grupo SendFlow direto) — mínimo (sem payload bruto), idempotente por (fonte, id do evento),
--      já com a pessoa resolvida. Entrada única: public.crm_integracao_receber (só service_role; a Edge
--      crm-integracao-webhook chama). Token do webhook conferido CONTRA O VAULT (nome crm_webhook_<fonte>): o segredo
--      nunca fica em arquivo nem em env da Edge.
--      Casamento (manual §7, F0): e-mail primeiro (identificadores, thb_alunos e compradores, cada um pelo índice dele;
--      SEM criar pessoa nova: aluno/comprador ganham só a linha de referência, como pessoas.garantir). Sem e-mail:
--      telefone por controle.fone_key só com EXATAMENTE 1 candidato e nome compatível. Nome nunca casa. Sem casar =
--      evento guardado com resultado 'sem_pessoa'/'telefone_ambiguo' (dá para reprocessar quando a pessoa existir).
--      ActiveCampaign NÃO é CRM: só gera ponto de jornada; descadastro/bounce NÃO viram opt-out comercial (decisão).
--   3. Kill-switch por integração em crm.config (desliga em ~10 s): activecampaign_ligado, sendflow_ligado,
--      respondi_ligado e o novo unnichat_ligado. Desligado = o webhook não grava nada E a jornada pula a fonte.
--      Todos nascem/continuam FALSE (SendFlow sem chave: pronto e desligado).
--   4. public.crm_jornada recriada a partir do corpo VIVO (md5 conferido na guarda): + kill-switch por fonte; + pontos de
--      crm.evento_jornada; + Unnichat legado por e-mail; + Respondi sem e-mail por telefone; grupo (SendFlow) e
--      telefone só pela chave com 1 candidato (antes: qualquer pessoa com o mesmo fone_key via o grupo da outra).
--   5. Filas de recuperação: crm.fila, crm.fila_item (score/faixa = calcularScore/faixaDoScore do domínio), RPCs
--      crm_filas (leitura), crm_criar_fila / crm_encerrar_fila / crm_atribuir_item_fila (gestor),
--      crm_atualizar_item_fila (responsável ou gestor; C/D só com A/B zeradas; sem oferta vigente não se aborda;
--      "ganho" só com pagamento aprovado na Hotmart da linha da fila).
--   6. Links rastreáveis: crm.link_rastreavel + crm_links / crm_criar_link / crm_arquivar_link. SCK = montarSck do domínio
--      (linha-acao-AAAAMMDD-canal-sigla); URL real da oferta vigente (fin.ofertas.bruto_json.direct_offer_link_for_creator)
--      + sck + utm_source=comercial, utm_medium=canal, utm_campaign=projeto, utm_content=conteúdo.
--   7. Log: crm.tg_log (F0) em fila, fila_item (update/delete) e link. Evento de integração não vai para o log (é dado
--      de fonte, não ação de pessoa).
--
-- FORA: Manychat (fora do escopo); supressão de WhatsApp (F4); MQL do Respondi criando negócio (§5.6, depende de
--   critério por formulário: decisão); montagem automática da fila a partir de sinais (fica para depois: a F5 recebe
--   os itens prontos do gestor); Clint (F6). Nenhuma API externa é chamada pelo banco.
--
-- AS 5 PERGUNTAS (números em 20261006c.explain.md)
--   escala: evento_jornada cresce por evento de webhook (AC: dezenas a centenas/dia em lançamento); leitura sempre
--     por pessoa (índice pessoa_id) e com limite. Fila ≤ 5.000 itens por montagem; leitura ≤ 50 filas × 5.000 itens.
--   índice: jornada lê cada fonte pelo índice da expressão exata (guarda confere): ix_lead_active_email_lower,
--     ix_geu_fone, respostas_email_idx, ix_respostas_fone_sem_email (novo), ix_unnichat_evento_email (novo),
--     evento_jornada_pessoa_idx. Casamento por e-mail: thb_alunos_email_uidx, ix_compradores_email_lower_all,
--     identificadores (tipo, chave). Telefone: pessoas.candidatos_telefone (índices da F0).
--   frequência: webhook = 1 chamada por evento (sem cron novo). Jornada ao abrir a ficha. Sem polling.
--   repetição: 1 chamada de RPC por lote de eventos (até 100); crm_filas traz filas + itens numa chamada.
--   reversão: kill-switch por fonte (false = webhook ignora e jornada pula); escrita_ligada=false desliga fila/link;
--     bloco REVERSÃO no fim (tabelas novas sem FK de fora: drop; jornada volta ao corpo da F1).
--
-- PREMISSAS (guarda aborta se faltar): F2 aplicada (crm.guarda_escrita, crm.res, crm.erro_dados, crm.vendedor_ativo,
--   public.crm_mover_etapa); F5 não aplicada; corpo vivo de public.crm_jornada = o da F1 (md5); índices das fontes com a
--   expressão exata (inclui os 2 da pré); colunas das fontes; pessoas.candidatos_telefone/garantir/pessoa_do_aluno/
--   pessoa_do_comprador/nomes_compativeis; mkt.sem_acento; vault.decrypted_secrets.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  if to_regprocedure('crm.guarda_escrita()') is null or to_regprocedure('crm.res(boolean,text,jsonb)') is null
     or to_regprocedure('crm.erro_dados(text,text,text)') is null or to_regprocedure('crm.vendedor_ativo(uuid)') is null
     or to_regprocedure('crm.nome_pessoa(uuid)') is null or to_regprocedure('crm.nome_perfil(uuid)') is null
     or to_regprocedure('public.crm_mover_etapa(uuid,uuid)') is null then
    raise exception '20261006c: F2 (20261005t) não aplicada';
  end if;
  if to_regclass('crm.evento_jornada') is not null or to_regclass('crm.fila') is not null
     or to_regclass('crm.link_rastreavel') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                   and column_name = 'unnichat_ligado') then
    raise exception '20261006c: objetos da F5 já existem (migration já aplicada?)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                    and column_name in ('activecampaign_ligado', 'sendflow_ligado', 'respondi_ligado', 'escrita_ligada')
                  group by table_name having count(*) = 4) then
    raise exception '20261006c: crm.config sem os kill-switches da F0';
  end if;
  -- recriar a jornada a partir do corpo VIVO (manual §3): aborta se alguém mudou depois da F1
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.crm_jornada(uuid,integer)'))
     is distinct from '4e4cbddd4f9de648ab9ffc71441e8936' then
    raise exception '20261006c: corpo vivo de public.crm_jornada diferente do da F1: refazer a seção 4 a partir dele';
  end if;
  if to_regprocedure('pessoas.candidatos_telefone(text)') is null or to_regprocedure('pessoas.garantir(text[])') is null
     or to_regprocedure('pessoas.pessoa_do_aluno(uuid)') is null or to_regprocedure('pessoas.pessoa_do_comprador(uuid)') is null
     or to_regprocedure('pessoas.nomes_compativeis(text,text)') is null or to_regprocedure('pessoas.norm_email(text)') is null
     or to_regprocedure('pessoas.norm_telefone(text)') is null or to_regprocedure('pessoas.chave_telefone(text)') is null
     or to_regprocedure('mkt.sem_acento(text)') is null or to_regclass('vault.decrypted_secrets') is null then
    raise exception '20261006c: funções da F0/mkt ou vault ausentes';
  end if;
  select string_agg(x.s || '.' || x.i, ', ') into v_falta
    from (values
      ('controle', 'ix_lead_active_email_lower',     '(lower(btrim(email)))'),
      ('controle', 'ix_geu_fone',                    '(fone_key)'),
      ('controle', 'ix_unnichat_evento_email',       '(lower(btrim(((payload -> ''contact''::text) ->> ''email''::text))))'),
      ('respondi', 'respostas_email_idx',            '(email)'),
      ('respondi', 'ix_respostas_fone_sem_email',    '(controle.fone_key(telefone)) WHERE ((email IS NULL) AND (telefone IS NOT NULL))'),
      ('public',   'thb_alunos_email_uidx',          'lower(TRIM(BOTH FROM email))) WHERE ((email IS NOT NULL) AND (email <> ''''::text))'),
      ('public',   'ix_compradores_email_lower_all', '(lower(btrim((email)::text)))'),
      ('fin',      'hotmart_transacoes_email_idx',   '(lower(TRIM(BOTH FROM comprador_email)))')
    ) x(s, i, trecho)
   where not exists (select 1 from pg_indexes pi
                       join pg_index ix on ix.indexrelid = to_regclass(quote_ident(pi.schemaname) || '.' || quote_ident(pi.indexname))
                      where pi.schemaname = x.s and pi.indexname = x.i and ix.indisvalid
                        and position(x.trecho in pi.indexdef) > 0);
  if v_falta is not null then
    raise exception '20261006c: índice ausente, inválido ou com expressão diferente: % (rodar 20261006c_pre_indices.sql antes)', v_falta;
  end if;
  select string_agg(x.s || '.' || x.t || '.' || x.c, ', ') into v_falta
    from (values ('controle','unnichat_evento','payload'), ('controle','unnichat_evento','tipo'),
                 ('controle','unnichat_evento','tag_nome'), ('controle','unnichat_evento','recebido_em'),
                 ('respondi','respostas','telefone'), ('respondi','respostas','respondido_em'),
                 ('fin','ofertas','bruto_json'), ('fin','hotmart_transacoes','origem_sck'),
                 ('fin','hotmart_transacoes','valor_cobrado'), ('crm','vendedor','sigla')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then raise exception '20261006c: colunas ausentes: %', v_falta; end if;
end
$guarda$;

-- ─── 1. Kill-switches ────────────────────────────────────────────────────────────────────────────────────────────────
alter table crm.config add column unnichat_ligado boolean not null default false;
comment on column crm.config.activecampaign_ligado is 'F5: false = webhook AC ignora (não grava) e a jornada não mostra lista/tag do AC.';
comment on column crm.config.sendflow_ligado is 'F5: false = webhook SendFlow ignora e a jornada não mostra grupos (controle.grupo_evento_unificado).';
comment on column crm.config.respondi_ligado is 'F5: false = a jornada não mostra respostas do Respondi (respondi.respostas).';
comment on column crm.config.unnichat_ligado is 'F5: false = webhook Unnichat ignora e a jornada não mostra Unnichat (legado + webhook).';

-- ─── 2. Eventos de integração (só o que não existe no banco) ─────────────────────────────────────────────────────────
-- Mínimo para a jornada: sem payload bruto (LGPD). E-mail e telefone guardados só como CHAVE normalizada (para casar e
-- reprocessar). nome só para a checagem de nome compatível no casamento por telefone.
create table crm.evento_jornada (
  id              bigint generated always as identity primary key,
  fonte           text not null check (fonte in ('activecampaign', 'unnichat', 'sendflow', 'respondi')),
  fonte_evento_id text not null check (length(fonte_evento_id) between 1 and 200),
  tipo            text not null check (tipo ~ '^[a-z0-9_.:-]{1,60}$'),
  ocorreu_em      timestamptz not null,
  recebido_em     timestamptz not null default now(),
  email_norm      text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key        text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  nome            text check (nome is null or length(nome) <= 160),
  lista           text check (lista is null or length(lista) <= 200),
  tag             text check (tag is null or length(tag) <= 200),
  dados           jsonb not null default '{}' check (jsonb_typeof(dados) = 'object' and length(dados::text) <= 4000),
  pessoa_id       uuid references pessoas.pessoas(id) on delete restrict,
  resultado       text not null default 'pendente'
                    check (resultado in ('pendente', 'anexado', 'sem_pessoa', 'telefone_ambiguo', 'sem_identificador')),
  processado_em   timestamptz,
  unique (fonte, fonte_evento_id),
  check ((resultado = 'anexado') = (pessoa_id is not null))
);
alter table crm.evento_jornada enable row level security;
create index evento_jornada_pessoa_idx on crm.evento_jornada (pessoa_id, ocorreu_em desc) where pessoa_id is not null;
create index evento_jornada_email_idx  on crm.evento_jornada (email_norm) where pessoa_id is null and email_norm is not null;
create index evento_jornada_fone_idx   on crm.evento_jornada (fone_key) where pessoa_id is null and email_norm is null and fone_key is not null;
create index evento_jornada_recebido_idx on crm.evento_jornada (recebido_em);
comment on table crm.evento_jornada is 'F5: eventos de webhook (AC, Unnichat, SendFlow) que viram ponto de jornada. Mínimo, '
  'idempotente por (fonte, fonte_evento_id), pessoa resolvida por e-mail (telefone só sem e-mail e 1 candidato). 20261006c.';

-- Pessoa pelo e-mail SEM criar pessoa nova (aluno/comprador ganham a linha de referência, como pessoas.garantir).
-- Mesma ordem do pessoas.resolver: aluno, comprador, identificador. Cada fonte pelo seu índice; valor já normalizado.
create function crm.pessoa_por_email(p_email text) returns uuid
language plpgsql set search_path = '' as $$
declare v_email text := pessoas.norm_email(p_email); v_lead uuid; v_aluno uuid; v_comprador uuid; v uuid;
begin
  if v_email is null then return null; end if;
  select a.id into v_aluno from public.thb_alunos a
   where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
  if v_aluno is not null then return pessoas.pessoa_do_aluno(v_aluno); end if;
  select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;
  if v_comprador is not null then return pessoas.pessoa_do_comprador(v_comprador); end if;
  select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
  return v_lead;
end
$$;

-- Resolve a pessoa de UM evento e grava o resultado. E-mail → pessoa_por_email. Sem e-mail: telefone com exatamente 1
-- candidato (pessoas.candidatos_telefone = pessoas + alunos ativos + compradores) e nome compatível. Nome sozinho nunca.
create function crm.anexar_integracao(p_id bigint) returns text
language plpgsql set search_path = '' as $$
declare e crm.evento_jornada%rowtype; v_pessoa uuid; v_res text; v_n int; v_ent text; v_nome_ent text;
begin
  select * into e from crm.evento_jornada where id = p_id for update;
  if not found then return null; end if;
  if e.email_norm is not null then
    v_pessoa := crm.pessoa_por_email(e.email_norm);
    v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
  elsif e.fone_key is not null then
    select count(*), min(t.ent), min(t.nome_ent) into v_n, v_ent, v_nome_ent from pessoas.candidatos_telefone(e.fone_key) t;
    if v_n = 0 then v_res := 'sem_pessoa';
    elsif v_n = 1 and pessoas.nomes_compativeis(e.nome, v_nome_ent) then
      v_pessoa := (pessoas.garantir(array[v_ent]))[1];
      v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
    else v_res := 'telefone_ambiguo';
    end if;
  else
    v_res := 'sem_identificador';
  end if;
  update crm.evento_jornada set pessoa_id = v_pessoa, resultado = v_res, processado_em = now() where id = p_id;
  return v_res;
end
$$;

-- Tipo de ponto + título do evento (para a jornada). Puro.
create function crm.ponto_integracao(p_fonte text, p_tipo text, p_lista text, p_tag text,
                                     out tipo_ponto text, out titulo text)
language sql immutable set search_path = '' as $$
  select case
           when p_fonte = 'activecampaign' then 'lista'
           when p_fonte = 'sendflow' then 'grupo'
           when p_fonte = 'respondi' then 'pesquisa'
           when p_fonte = 'unnichat' and p_tipo = 'template_enviado' then 'disparo'
           when p_fonte = 'unnichat' and p_tipo in ('convite_grupo', 'entrou_link') then 'grupo'
           else 'conversa' end,
         case
           when p_fonte = 'activecampaign' then case p_tipo
               when 'subscribe' then 'Entrou na lista'
               when 'unsubscribe' then 'Saiu da lista'
               when 'contact_tag_added' then 'Ganhou a tag'
               when 'contact_tag_removed' then 'Perdeu a tag'
               when 'bounce' then 'E-mail voltou (bounce)'
               else 'ActiveCampaign: ' || p_tipo end
             || coalesce(' · ' || nullif(p_tag, ''), ' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'sendflow' then case when p_tipo = 'saida' then 'Saiu do grupo' else 'Entrou no grupo' end
             || coalesce(' · ' || nullif(p_lista, ''), '')
           when p_fonte = 'unnichat' then 'Unnichat: ' || coalesce(nullif(p_tag, ''), replace(p_tipo, '_', ' '))
           else 'Respondeu: ' || coalesce(nullif(p_lista, ''), 'formulário') end;
$$;

-- Entrada única dos webhooks (a Edge crm-integracao-webhook chama com a service role). Lote de até 100 eventos:
-- [{id, tipo, ocorreuEm, email, telefone, nome, lista, tag, utm:{source,medium,campaign,content}}].
-- p_chave = token que o provedor mandou; conferido contra o Vault 'crm_webhook_<fonte>' (sem segredo no Vault = recusa).
-- Kill-switch desligado = não grava nada. Reenvio do mesmo evento = no-op (duplicado).
create function public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ligado boolean; v_seg text; e jsonb; v_id bigint; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0;
  v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end
    into v_ligado from crm.config c;
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
    begin
      v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, now());
    exception when others then v_quando := null;
    end;
    if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
       or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > now() + interval '1 day' then
      v_inval := v_inval + 1; continue;
    end if;
    v_utm := jsonb_strip_nulls(jsonb_build_object(
               'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
               'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
    insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, fone_key, nome, lista, tag, dados)
    values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando,
            pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
            nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
            nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
            case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
    begin
      v_res := crm.anexar_integracao(v_id);
      if v_res = 'anexado' then v_anex := v_anex + 1; end if;
    exception when others then
      raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    end;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'invalidos', v_inval);
end
$$;

-- Reprocessa eventos que ainda não casaram (a pessoa pode ter aparecido depois). Lote limitado; só service_role
-- (rodar à mão ou por cron diário quando a fonte estiver ligada — NÃO agendado aqui).
create function public.crm_integracao_reprocessar(p_limite int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v_n int := 0; v_anex int := 0;
begin
  for r in select e.id from crm.evento_jornada e
            where e.pessoa_id is null and e.resultado in ('pendente', 'sem_pessoa', 'telefone_ambiguo')
            order by e.id limit least(greatest(coalesce(p_limite, 500), 1), 5000) loop
    v_n := v_n + 1;
    if crm.anexar_integracao(r.id) = 'anexado' then v_anex := v_anex + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'processados', v_n, 'anexados', v_anex);
end
$$;

-- ─── 3. E-mails da pessoa (grupo de alias + irmãos em fin.identidade). Mesma lógica da jornada (F1). ────────────────
create function crm.emails_da_pessoa(p_atual uuid) returns text[]
language plpgsql stable set search_path = '' as $$
declare v_g uuid[] := pessoas.grupo(pessoas.atual(p_atual)); v_compr uuid[]; v_emails text[];
begin
  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  return array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
end
$$;

-- ─── 4. Jornada: corpo vivo da F1 + fontes da F5 com kill-switch + telefone só com 1 candidato ──────────────────────
create or replace function public.crm_jornada(p_pessoa uuid, p_limite int default 500) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_atual uuid; v_g uuid[]; v_emails text[]; v_fks text[]; v_fks1 text[]; v_compr uuid[];
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
  v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is null or not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a esta pessoa.' using errcode = '42501';
  end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  v_atual := pessoas.atual(p_pessoa);
  v_g := pessoas.grupo(v_atual);

  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  -- e-mails irmãos pelo grafo fin.identidade (por chave, no momento da leitura; recalculado de hora em hora)
  v_emails := array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
  v_fks := array(
    select k from (
      select controle.fone_key(coalesce(a.telefone_e164, a.telefone)) k from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
       where p.id = any(v_g)
      union select controle.fone_key((c.telefone)::text) from public.compradores c where c.id = any(v_compr) and c.telefone is not null
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'telefone'
    ) s where k is not null limit 10);
  -- F5: evento só com telefone (grupo, Respondi sem e-mail) é da pessoa só se a chave tem EXATAMENTE 1 candidato
  -- (manual §7: telefone nunca junta duas pessoas). Calculado só se alguma fonte por telefone estiver ligada.
  if v_sf or v_rs then
    v_fks1 := array(select k from unnest(v_fks) k where (select count(*) from pessoas.candidatos_telefone(k)) = 1);
  else
    v_fks1 := '{}';
  end if;

  with pts as (
    -- inscrição (origem com a UTM daquela entrada)
    (select 'or-' || o.id id, 'inscricao' tipo, o.quando em,
            'Inscrição' || coalesce(' · ' || pr.sigla, '') titulo, o.campanha detalhe, 'formulario' fonte,
            lower(pr.sigla) lancamento, null::text produto,
            jsonb_build_object('source', o.utm_source, 'medium', o.utm_medium, 'campaign', o.utm_campaign, 'content', o.utm_content) utm,
            null::numeric valor, null::uuid negocio_id
       from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id
      where o.pessoa_id = any(v_g) order by o.quando desc limit v_lim)
    union all
    (select 'ev-' || e.id, 'pesquisa', e.quando, case e.tipo when 'mql' then 'Qualificou como MQL' else 'Não qualificou (MQL)' end,
            null, 'formulario', lower(pr.sigla), null, null, null, null
       from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id
      where e.pessoa_id = any(v_g) and e.tipo in ('mql', 'nao_mql') order by e.quando desc limit v_lim)
    union all
    -- Hotmart: compra, reembolso, checkout (índice hotmart_transacoes_email_idx = lower(btrim(comprador_email)))
    (select 'hm-' || h.transacao,
            case when h.status in ('APPROVED', 'COMPLETE') then 'compra'
                 when h.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED') then 'reembolso' else 'checkout' end,
            coalesce(h.aprovado_em, h.pedido_em),
            case when h.status in ('APPROVED', 'COMPLETE') then 'Compra aprovada'
                 when h.status in ('REFUNDED', 'PARTIALLY_REFUNDED') then 'Reembolso'
                 when h.status = 'CHARGEBACK' then 'Chargeback'
                 when h.status in ('WAITING_PAYMENT', 'PRINTED_BILLET') then 'Boleto/Pix gerado'
                 when h.status = 'EXPIRED' then 'Pagamento expirado'
                 when h.status = 'CANCELLED' then 'Compra cancelada'
                 else 'Checkout: ' || lower(h.status) end || coalesce(' · ' || h.produto_nome, ''),
            nullif(concat_ws(' · ', 'oferta ' || h.oferta_codigo, h.metodo), ''), 'hotmart', null, pcm.linha,
            case when h.origem_sck is not null then jsonb_build_object('sck', h.origem_sck) end,
            h.valor_cobrado, null
       from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
       left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id and pcm.no_comercial
      where lower(btrim(h.comprador_email)) = any(v_emails)
      order by coalesce(h.aprovado_em, h.pedido_em) desc nulls last limit v_lim)
    union all
    -- lista do ActiveCampaign (índice ix_lead_active_email_lower). F5: kill-switch activecampaign_ligado.
    (select 'ac-' || la.id, 'lista', coalesce(la.opt_in_at, la.atualizado_em), 'Entrou na lista' || coalesce(' · ' || la.origem, ''),
            la.segmento, 'activecampaign', null, null,
            jsonb_build_object('source', la.utm_source, 'campaign', la.utm_campaign, 'content', la.utm_content), null, null
       from controle.lead_active la
      where v_ac and lower(btrim(la.email)) = any(v_emails)
      order by coalesce(la.opt_in_at, la.atualizado_em) desc limit v_lim)
    union all
    -- grupos de WhatsApp (índice ix_geu_fone, chave controle.fone_key). F5: sendflow_ligado + chave com 1 candidato.
    (select 'gr-' || g.id, 'grupo', g.ocorreu_em,
            case g.tipo when 'entrada' then 'Entrou no grupo' else 'Saiu do grupo' end || coalesce(' · ' || g.group_name, ''),
            g.segmento, 'sendflow', null, null, null, null, null
       from controle.grupo_evento_unificado g
      where v_sf and g.fone_key = any(v_fks1)
      order by g.ocorreu_em desc limit v_lim)
    union all
    -- pesquisas/formulários (índice respostas_email_idx; e-mail já normalizado na fonte). Nunca cpf/respostas.
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            null, 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email = any(v_emails)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: resposta SEM e-mail, pelo telefone com 1 candidato (índice ix_respostas_fone_sem_email, predicado repetido)
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            'casado pelo telefone', 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email is null and r.telefone is not null and controle.fone_key(r.telefone) = any(v_fks1)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: Unnichat legado (controle.unnichat_evento, parado desde 08/09) pelo e-mail do contato (ix_unnichat_evento_email)
    (select 'un-' || u.id, (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).tipo_ponto, u.recebido_em,
            (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).titulo, null, 'unnichat', null, null, null, null, null
       from controle.unnichat_evento u
      where v_un and lower(btrim((u.payload -> 'contact') ->> 'email')) = any(v_emails)
      order by u.recebido_em desc limit v_lim)
    union all
    -- F5: eventos de webhook já casados com a pessoa (crm.evento_jornada), cada fonte com o seu kill-switch
    (select 'ie-' || ie.id, (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).tipo_ponto, ie.ocorreu_em,
            (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).titulo, null, ie.fonte, null, null,
            ie.dados -> 'utm', null, null
       from crm.evento_jornada ie
      where ie.pessoa_id = any(v_g)
        and ((ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
             or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs))
      order by ie.ocorreu_em desc limit v_lim)
    union all
    -- mini-CRM do CS (só leitura; D4 coexistir)
    (select 'cs-' || c.id, 'nota', coalesce(c.ultimo_contato_em, c.atualizado_em, c.criado_em),
            'CS: ' || coalesce(es.nome, 'sem estágio') || coalesce(' · ' || c.evento, ''),
            case when c.responsavel is not null then 'responsável: ' || c.responsavel end, 'crm', null, null, null, null, null
       from cs.contatos c left join cs.estagios es on es.id = c.estagio_id
      where c.comprador_id = any(v_compr))
    union all
    -- CRM: negócios (mesma regra da policy de negócio)
    (select 'ng-' || n.id, 'negocio', n.criado_em, 'Negócio criado · ' || f.nome, null, 'crm', f.projeto, n.linha,
            case when n.utm <> '{}'::jsonb then n.utm end, null, n.id
       from crm.negocio n join crm.funil f on f.id = n.funil_id
      where n.pessoa_id = any(v_g) and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by n.criado_em desc limit v_lim)
    union all
    (select 'lg-' || l.id, 'negocio', l.em,
            case l.acao when 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa')
                        when 'marcou_ganho' then 'Ganho' when 'marcou_perdido' then 'Perdido'
                        else 'Troca de dono' end || ' · ' || f.nome,
            l.resumo, 'crm', f.projeto, n.linha, null,
            case when l.acao = 'marcou_ganho' then n.valor end, n.id
       from crm.log l
       join crm.negocio n on n.id::text = l.entidade_id
       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g)
      order by nt.em desc limit v_lim)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'contatoId', v_atual, 'tipo', p.tipo, 'em', p.em, 'titulo', p.titulo, 'detalhe', p.detalhe,
           'fonte', p.fonte, 'lancamento', p.lancamento, 'produto', p.produto, 'utm', p.utm, 'valor', p.valor,
           'negocioId', p.negocio_id) order by p.em desc nulls last, p.id), '[]'::jsonb)
    into v
    from (select * from pts where pts.em is not null order by pts.em desc limit v_lim) p;
  return v;
end
$$;

-- ─── 5. Filas de recuperação (§3.7; processo montar-fila-de-recuperacao.md) ──────────────────────────────────────────
-- calcularScore do domínio (regras.ts): comportamento de compra conta só o maior (boleto 40 OU carrinho 24); teto 100.
create function crm.score_recuperacao(p_sinais text[]) returns smallint
language sql immutable set search_path = '' as $$
  select least(100,
           case when 'boleto_aberto' = any(p_sinais) then 40 when 'carrinho' = any(p_sinais) then 24 else 0 end
         + coalesce((select sum(case s when 'ficha_completa' then 20 when 'senhas' then 16 when 'chat' then 12
                                       when 'workbook' then 6 when 'apostila' then 4 when 'pesquisa' then 6
                                       when 'comunidade' then 4 when 'grupo' then 3 when 'advogado_contador' then 4
                                       when 'quer_parceria' then 6 else 0 end)
                       from (select distinct unnest(coalesce(p_sinais, '{}'))) x(s)), 0))::smallint;
$$;

create table crm.fila (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(btrim(nome)) between 1 and 120),
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,   -- sem oferta vigente não se aborda
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),
  criada_por    uuid references public.perfis(id) on delete restrict,
  criada_em     timestamptz not null default now(),
  encerrada_em  timestamptz,
  encerrada_por uuid references public.perfis(id) on delete restrict
);
create index fila_criada_idx on crm.fila (criada_em desc);

create table crm.fila_item (
  id             uuid primary key default gen_random_uuid(),
  fila_id        uuid not null references crm.fila(id) on delete restrict,
  pessoa_id      uuid not null references pessoas.pessoas(id) on delete restrict,   -- leitura resolve pessoas.atual
  score          smallint not null check (score between 0 and 100),
  faixa          char(1) generated always as (case when score >= 60 then 'A' when score >= 40 then 'B'
                                                   when score >= 25 then 'C' else 'D' end) stored,
  sinais         text[] not null default '{}'
                   check (sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas','chat',
                                          'workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                          'quer_parceria','respondeu_sem_retorno']::text[]),
  status         text not null default 'a_abordar'
                   check (status in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                     'declinou','sem_interesse','numero_invalido')),
  responsavel_id uuid references crm.vendedor(perfil_id) on delete restrict,
  alterado_por   uuid references public.perfis(id) on delete restrict,
  alterado_em    timestamptz,
  criado_em      timestamptz not null default now(),
  unique (fila_id, pessoa_id)
);
create index fila_item_faixa_idx       on crm.fila_item (fila_id, faixa, status);
create index fila_item_responsavel_idx on crm.fila_item (responsavel_id) where responsavel_id is not null;
create index fila_item_pessoa_idx      on crm.fila_item (pessoa_id);

-- Oferta da fila ainda vigente? Devolve o texto que a tela mostra (null = não se aborda).
create function crm.oferta_vigente_texto(p_oferta text) returns text
language sql stable security definer set search_path = '' as $$
  select concat_ws(' · ', coalesce(pc.nome_comercial, o.nome), o.oferta_codigo, oc.condicao)
    from fin.ofertas o
    join crm.oferta_comercial oc on oc.oferta_codigo = o.oferta_codigo
    left join crm.produto_comercial pc on pc.produto_id = o.produto_id
   where o.oferta_codigo = p_oferta and oc.vigente
     and (oc.valida_ate is null or oc.valida_ate >= (now() at time zone 'America/Sao_Paulo')::date);
$$;

-- ─── 6. Links rastreáveis (§3.7; playbook seção 8) ───────────────────────────────────────────────────────────────────
-- Pedaço do SCK = limpa() de montarSck: sem acento, minúsculo, só [a-z0-9].
create function crm.limpa_sck(p text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(mkt.sem_acento(coalesce(p, '')), '[^A-Za-z0-9]+', '', 'g'));
$$;

create table crm.link_rastreavel (
  id            uuid primary key default gen_random_uuid(),
  vendedor_id   uuid not null references crm.vendedor(perfil_id) on delete restrict,
  linha         text not null references crm.linha(chave) on delete restrict,
  oferta_codigo text not null references fin.ofertas(oferta_codigo) on delete restrict,   -- link real, nunca "EXEMPLO"
  acao          text not null check (length(btrim(acao)) between 1 and 60),
  canal         text not null check (canal ~ '^[a-z0-9]{1,30}$'),
  projeto       text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9_-]{0,59}$'),     -- utm_campaign
  conteudo      text check (conteudo is null or conteudo ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$'), -- utm_content
  sck           text not null unique check (sck ~ '^[a-z0-9_]+-[a-z0-9]+-[0-9]{8}-[a-z0-9]+-[a-z0-9]+$'),
  url           text not null check (url ~ '^https://pay\.hotmart\.com' and length(url) <= 1000),
  criado_por    uuid references public.perfis(id) on delete restrict,
  criado_em     timestamptz not null default now(),
  arquivado_em  timestamptz
);
create index link_vendedor_idx on crm.link_rastreavel (vendedor_id, criado_em desc);

-- ─── 7. Log (crm.tg_log da F0), RLS e policies ───────────────────────────────────────────────────────────────────────
create trigger fila_log_ins_del after insert or delete on crm.fila for each row execute function crm.tg_log('fila', 'id');
create trigger fila_log_upd after update on crm.fila for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
-- itens: só alteração/remoção (a montagem é 1 linha de log na fila, não 5.000)
create trigger fila_item_log_del after delete on crm.fila_item for each row execute function crm.tg_log('fila', 'id');
create trigger fila_item_log_upd after update on crm.fila_item for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('fila', 'id');
create trigger link_log_ins_del after insert or delete on crm.link_rastreavel for each row execute function crm.tg_log('link', 'id');
create trigger link_log_upd after update on crm.link_rastreavel for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('link', 'id');

do $rls$
declare t text;
begin
  foreach t in array array['fila', 'fila_item', 'link_rastreavel'] loop
    execute format('alter table crm.%I enable row level security', t);
    execute format('revoke all on crm.%I from public, anon, authenticated', t);
    execute format('grant select on crm.%I to authenticated', t);
  end loop;
  -- evento_jornada: fechada (só as funções definer leem)
  revoke all on crm.evento_jornada from public, anon, authenticated;
end
$rls$;
create policy fila_ler on crm.fila for select to authenticated using ((select crm.eh_comercial()));
create policy fila_item_ler on crm.fila_item for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (responsavel_id = (select auth.uid()) or responsavel_id is null)));
create policy link_ler on crm.link_rastreavel for select to authenticated using (
  (select crm.eh_gestor()) or ((select crm.eh_vendedor()) and vendedor_id = (select auth.uid())));

-- ─── 8. RPCs de leitura ──────────────────────────────────────────────────────────────────────────────────────────────
-- Filas (FilaRecuperacao[]): DEFINER porque o texto da oferta vigente lê fin.ofertas; itens com a MESMA regra da
-- policy fila_item_ler. contatoId = pessoa atual (alias resolvido em lote).
create function public.crm_filas(p_incluir_encerradas boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with f as (
    select x.* from crm.fila x where coalesce(p_incluir_encerradas, false) or x.encerrada_em is null
     order by x.criada_em desc limit 50),
  it as (
    select i.*, row_number() over (partition by i.fila_id order by i.score desc, i.id) rn
      from crm.fila_item i
     where i.fila_id in (select f.id from f) and (v_gestor or i.responsavel_id = v_eu or i.responsavel_id is null)),
  al as (select * from crm.atual_de(array(select distinct it.pessoa_id from it where it.rn <= 5000)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'nome', f.nome, 'produto', f.linha, 'criadaEm', f.criada_em,
           'ofertaVigente', crm.oferta_vigente_texto(f.oferta_codigo), 'ofertaCodigo', f.oferta_codigo,
           'projeto', f.projeto, 'encerradaEm', f.encerrada_em,
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', it.id, 'contatoId', al.atual, 'score', it.score, 'faixa', it.faixa, 'sinais', to_jsonb(it.sinais),
                        'status', it.status, 'responsavelId', it.responsavel_id, 'alteradoPor', it.alterado_por,
                        'alteradoEm', it.alterado_em) order by it.score desc, it.id)
                       from it left join al on al.pessoa_id = it.pessoa_id
                      where it.fila_id = f.id and it.rn <= 5000), '[]'::jsonb))
           order by f.criada_em desc), '[]'::jsonb)
    into v from f;
  return v;
end
$$;

-- Links (LinkRastreavel[]): gestor vê todos, vendedor os seus. p_vendas = true soma as vendas Hotmart pelo SCK
-- (2 Seq Scans em fin.hotmart_transacoes sem índice em origem_sck: sob pedido, nunca ao abrir a tela).
create function public.crm_links(p_vendas boolean default false, p_incluir_arquivados boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with l as (
    select x.* from crm.link_rastreavel x
     where (v_gestor or x.vendedor_id = v_eu) and (coalesce(p_incluir_arquivados, false) or x.arquivado_em is null)
     order by x.criado_em desc limit 2000),
  vd as (
    select h.origem_sck sck, count(*) filter (where h.status in ('APPROVED', 'COMPLETE')) vendas,
           coalesce(sum(h.valor_cobrado) filter (where h.status in ('APPROVED', 'COMPLETE')), 0) receita
      from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
     where coalesce(p_vendas, false) and h.origem_sck = any(array(select l.sck from l))
     group by h.origem_sck)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'vendedorId', l.vendedor_id, 'produto', l.linha, 'acao', l.acao, 'url', l.url, 'sck', l.sck,
           'canal', l.canal, 'ofertaCodigo', l.oferta_codigo, 'projeto', l.projeto, 'conteudo', l.conteudo,
           'criadoEm', l.criado_em, 'arquivadoEm', l.arquivado_em,
           'vendas', case when coalesce(p_vendas, false) then coalesce(vd.vendas, 0) end,
           'receita', case when coalesce(p_vendas, false) then coalesce(vd.receita, 0) end) order by l.criado_em desc), '[]'::jsonb)
    into v
    from l left join vd on vd.sck = l.sck;
  return v;
end
$$;

-- ─── 9. RPCs de escrita: fila ────────────────────────────────────────────────────────────────────────────────────────
-- Itens de entrada da montagem: pessoa ATUAL (alias resolvido) + sinais sem repetição.
create function crm.fila_entrada(p_itens jsonb) returns table (pessoa uuid, sinais text[])
language sql stable set search_path = '' as $$
  select pessoas.atual(crm.uuid_ou_null(x ->> 'contatoId')),
         array(select distinct s from jsonb_array_elements_text(case when jsonb_typeof(x -> 'sinais') = 'array'
                                                                     then x -> 'sinais' else '[]'::jsonb end) s order by 1)
    from jsonb_array_elements(case when jsonb_typeof(p_itens) = 'array' then p_itens else '[]'::jsonb end) x;
$$;

-- Monta a fila (só gestor). p: {nome, produto, ofertaCodigo?, projeto?, itens:[{contatoId, sinais:[]}]} (≤ 5.000).
-- Score/faixa calculados no banco. Contato com opt-out fica fora (suprimidos); repetido (mesma pessoa atual) entra 1×.
create function public.crm_criar_fila(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_nome text; v_linha text; v_oferta text; v_projeto text; v_id uuid; v_n int; v_sup int; v_inval int;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor monta fila de recuperação.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_nome := btrim(coalesce(p ->> 'nome', ''));
  v_linha := p ->> 'produto';
  v_oferta := nullif(btrim(coalesce(p ->> 'ofertaCodigo', '')), '');
  v_projeto := nullif(lower(btrim(coalesce(p ->> 'projeto', ''))), '');
  if v_nome = '' then return crm.res(false, 'Dê um nome à fila.'); end if;
  if not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_oferta is not null and not exists (
       select 1 from fin.ofertas o join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial
        where o.oferta_codigo = v_oferta and pc.linha = v_linha) then
    return crm.res(false, 'Oferta não é deste produto.');
  end if;
  if jsonb_typeof(p -> 'itens') <> 'array' or jsonb_array_length(p -> 'itens') = 0 then
    return crm.res(false, 'Fila sem contatos.');
  end if;
  if jsonb_array_length(p -> 'itens') > 5000 then return crm.res(false, 'Fila com mais de 5.000 contatos: divida.'); end if;

  select count(*) filter (where e.pessoa is null or not exists (select 1 from pessoas.pessoas pp where pp.id = e.pessoa)
                            or not (e.sinais <@ array['boleto_aberto','carrinho','cartao_recusado','ficha_completa','senhas',
                                    'chat','workbook','apostila','pesquisa','comunidade','grupo','advogado_contador',
                                    'quer_parceria','respondeu_sem_retorno']::text[]))
    into v_inval from crm.fila_entrada(p -> 'itens') e;
  if v_inval > 0 then return crm.res(false, format('%s contato(s) inexistente(s) ou com sinal inválido.', v_inval)); end if;
  select count(distinct e.pessoa) into v_sup from crm.fila_entrada(p -> 'itens') e
   where exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(e.pessoa)) and pc.opt_out);

  perform set_config('crm.resumo', format('Montou a fila "%s" (%s)', v_nome, v_linha), true);
  insert into crm.fila (nome, linha, oferta_codigo, projeto, criada_por)
  values (v_nome, v_linha, v_oferta, v_projeto, auth.uid()) returning id into v_id;
  insert into crm.fila_item (fila_id, pessoa_id, score, sinais)
  select v_id, i.pessoa, crm.score_recuperacao(i.sinais), i.sinais
    from (select distinct on (e.pessoa) e.pessoa, e.sinais from crm.fila_entrada(p -> 'itens') e
           order by e.pessoa, cardinality(e.sinais) desc) i
   where not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(i.pessoa)) and pc.opt_out);
  get diagnostics v_n = row_count;
  return crm.res(true, format('Fila montada: %s contato(s)%s.', v_n,
                              case when v_sup > 0 then format(', %s fora por opt-out', v_sup) else '' end),
                 jsonb_build_object('filaId', v_id, 'itens', v_n, 'suprimidos', v_sup));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_encerrar_fila(p_fila uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor encerra fila.'); end if;
  select * into f from crm.fila x where x.id = p_fila for update;
  if not found then return crm.res(false, 'Fila não encontrada.'); end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila já encerrada.'); end if;
  perform set_config('crm.resumo', format('Encerrou a fila "%s"', f.nome), true);
  update crm.fila x set encerrada_em = now(), encerrada_por = auth.uid() where x.id = p_fila;
  return crm.res(true);
end
$$;

-- Gestor define o responsável de um item (null = devolve para a fila).
create function public.crm_atribuir_item_fila(p_fila uuid, p_item uuid, p_responsavel uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; it crm.fila_item%rowtype; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor distribui a fila.'); end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if p_responsavel is not null and not crm.vendedor_ativo(p_responsavel) then return crm.res(false, 'Vendedor inválido ou inativo.'); end if;
  if it.responsavel_id is not distinct from p_responsavel then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Fila "%s": %s passou para %s', f.nome, crm.nome_pessoa(it.pessoa_id),
                                          crm.nome_perfil(p_responsavel)), true);
  update crm.fila_item x set responsavel_id = p_responsavel, alterado_por = auth.uid(), alterado_em = now() where x.id = p_item;
  return crm.res(true);
end
$$;

-- atualizarItemFila do port. Mensagens no tom do mock. Regras do playbook:
--   responsável ou gestor (item sem responsável: o vendedor que mexe assume); fila encerrada não muda;
--   sem oferta vigente não se aborda; C/D só com A/B zeradas (pendentesAB = A/B ainda "a_abordar" na fila inteira);
--   opt-out não volta a ser abordado; "ganho" só com pagamento aprovado na Hotmart da linha desde a montagem.
create function public.crm_atualizar_item_fila(p_fila uuid, p_item uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_gestor(), false);
        it crm.fila_item%rowtype; f crm.fila%rowtype; v_pend int; v_emails text[]; v_resp uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_status is null or p_status not in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                          'declinou','sem_interesse','numero_invalido') then
    return crm.res(false, 'Status inválido.');
  end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if not (v_gestor or it.responsavel_id is not distinct from v_eu
          or (it.responsavel_id is null and coalesce(crm.eh_vendedor(), false))) then
    return crm.res(false, 'Este contato da fila é de outro vendedor.');
  end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if it.status = p_status then return crm.res(true); end if;
  if crm.oferta_vigente_texto(f.oferta_codigo) is null then
    return crm.res(false, 'Sem oferta vigente: não se aborda. O gestor define a oferta da fila.');
  end if;
  if it.faixa in ('C', 'D') then
    select count(*) into v_pend from crm.fila_item x where x.fila_id = p_fila and x.faixa in ('A', 'B') and x.status = 'a_abordar';
    if v_pend > 0 then return crm.res(false, format('Faixas C e D só depois de A e B zeradas (faltam %s).', v_pend)); end if;
  end if;
  if p_status in ('tentando_contato', 'em_conversa', 'vai_comprar')
     and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(it.pessoa_id))) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  if p_status = 'ganho' then
    v_emails := crm.emails_da_pessoa(it.pessoa_id);
    if not exists (
      select 1 from (select * from fin.hotmart_transacoes where conta = 'academy'
                     union all
                     select * from fin.hotmart_transacoes where conta = 'escritorio') h
        join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = f.linha
       where lower(btrim(h.comprador_email)) = any(v_emails) and h.status in ('APPROVED', 'COMPLETE')
         and h.aprovado_em >= f.criada_em) then
      return crm.res(false, 'Ganho só com pagamento aprovado na Hotmart (produto da fila, depois da montagem).');
    end if;
  end if;
  v_resp := coalesce(it.responsavel_id, case when not v_gestor then v_eu end);
  perform set_config('crm.resumo', format('Mudou %s na fila: %s → %s', crm.nome_pessoa(it.pessoa_id), it.status, p_status), true);
  update crm.fila_item x set status = p_status, responsavel_id = v_resp, alterado_por = v_eu, alterado_em = now()
   where x.id = p_item;
  return crm.res(true);
end
$$;

-- ─── 10. RPCs de escrita: link ───────────────────────────────────────────────────────────────────────────────────────
-- criarLink do port (+ opcionais). Vendedor só para si; gestor para qualquer vendedor ativo. Oferta: a informada (tem de
-- ser vigente e da linha) ou a ÚNICA vigente da linha. SCK = montarSck (linha-acao-AAAAMMDD-canal-sigla, data de São Paulo).
create function public.crm_criar_link(p_vendedor uuid, p_produto text, p_acao text, p_canal text,
                                      p_oferta text default null, p_projeto text default null, p_conteudo text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_eu uuid := auth.uid(); v_sigla text; v_oferta text; v_n int; v_base text; v_sck text; v_canal text;
        v_projeto text := nullif(lower(btrim(coalesce(p_projeto, ''))), ''); v_conteudo text := nullif(btrim(coalesce(p_conteudo, '')), '');
        v_url text; v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_vendedor is null or btrim(coalesce(p_acao, '')) = '' or crm.limpa_sck(p_acao) = '' then
    return crm.res(false, 'Informe vendedor e ação.');
  end if;
  if not coalesce(crm.eh_gestor(), false) and p_vendedor is distinct from v_eu then
    return crm.res(false, 'Vendedor só cria link para si mesmo.');
  end if;
  select v.sigla into v_sigla from crm.vendedor v where v.perfil_id = p_vendedor;
  if v_sigla is null or not crm.vendedor_ativo(p_vendedor) then return crm.res(false, 'Informe vendedor e ação.'); end if;
  v_canal := crm.limpa_sck(p_canal);
  if v_canal = '' then return crm.res(false, 'Informe o canal (ex.: whatsapp).'); end if;
  if not exists (select 1 from crm.linha l where l.chave = p_produto and l.ativo) then return crm.res(false, 'Produto inválido.'); end if;
  if v_projeto is not null and v_projeto !~ '^[a-z0-9][a-z0-9_-]{0,59}$' then
    return crm.res(false, 'Chave do projeto inválida (letras minúsculas, números, - e _).');
  end if;
  if v_conteudo is not null and v_conteudo !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$' then
    return crm.res(false, 'Código do conteúdo inválido (letras, números, - e _).');
  end if;
  -- ofertas vigentes da linha
  select count(*), min(o.oferta_codigo) into v_n, v_oferta
    from fin.ofertas o
    join crm.produto_comercial pc on pc.produto_id = o.produto_id and pc.no_comercial and pc.linha = p_produto
   where crm.oferta_vigente_texto(o.oferta_codigo) is not null
     and (p_oferta is null or o.oferta_codigo = p_oferta);
  if p_oferta is not null and v_n = 0 then return crm.res(false, 'Oferta não é deste produto ou não está vigente.'); end if;
  if v_n = 0 then return crm.res(false, 'Sem oferta vigente neste produto: o gestor define em Produtos e ofertas.'); end if;
  if v_n > 1 then return crm.res(false, 'Há mais de uma oferta vigente neste produto: escolha a oferta.'); end if;
  v_sck := p_produto || '-' || crm.limpa_sck(p_acao) || '-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD')
           || '-' || v_canal || '-' || crm.limpa_sck(v_sigla);
  if exists (select 1 from crm.link_rastreavel l where l.sck = v_sck) then return crm.res(false, 'Este link já existe.'); end if;
  select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
    into v_base from fin.ofertas o where o.oferta_codigo = v_oferta;
  v_url := v_base || case when position('?' in v_base) > 0 then '&' else '?' end
           || 'sck=' || v_sck || '&utm_source=comercial&utm_medium=' || v_canal
           || coalesce('&utm_campaign=' || v_projeto, '') || coalesce('&utm_content=' || v_conteudo, '');
  perform set_config('crm.resumo', format('Criou link rastreável %s', v_sck), true);
  insert into crm.link_rastreavel (vendedor_id, linha, oferta_codigo, acao, canal, projeto, conteudo, sck, url, criado_por)
  values (p_vendedor, p_produto, v_oferta, btrim(p_acao), v_canal, v_projeto, v_conteudo, v_sck, v_url, v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('linkId', v_id, 'sck', v_sck, 'url', v_url));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_arquivar_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; l crm.link_rastreavel%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into l from crm.link_rastreavel x where x.id = p_link for update;
  if not found then return crm.res(false, 'Link não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or l.vendedor_id = auth.uid()) then return crm.res(false, 'Este link não é seu.'); end if;
  if l.arquivado_em is not null then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Arquivou o link %s', l.sck), true);
  update crm.link_rastreavel x set arquivado_em = now() where x.id = p_link;
  return crm.res(true);
end
$$;

-- ─── 11. Grants e conferência ────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  -- internos: ninguém executa direto
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('pessoa_por_email','anexar_integracao','ponto_integracao','emails_da_pessoa','score_recuperacao',
                                'oferta_vigente_texto','limpa_sck','fila_entrada') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- entrada dos webhooks: só service_role (a Edge)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_integracao_receber', 'crm_integracao_reprocessar') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- telas: authenticated (guarda no corpo)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_filas','crm_links','crm_criar_fila','crm_encerrar_fila','crm_atribuir_item_fila',
                                'crm_atualizar_item_fila','crm_criar_link','crm_arquivar_link') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- crm_jornada foi recriada com create or replace: mantém o ACL, mas confere de novo
  revoke all on function public.crm_jornada(uuid, integer) from public, anon;
  grant execute on function public.crm_jornada(uuid, integer) to authenticated;
end
$grants$;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006c: função executável por anon/PUBLIC: %', v_aberto; end if;
  if has_function_privilege('authenticated', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.crm_integracao_receber(text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'crm.anexar_integracao(bigint)', 'execute')
     or has_function_privilege('authenticated', 'crm.pessoa_por_email(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_atualizar_item_fila(uuid,uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_jornada(uuid,integer)', 'execute') then
    raise exception '20261006c: grants das funções fora do esperado';
  end if;
  select string_agg(table_name || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC')
          or (grantee = 'authenticated' and (privilege_type <> 'SELECT' or table_name = 'evento_jornada')));
  if v_aberto is not null then raise exception '20261006c: grant indevido em crm: %', v_aberto; end if;
  if coalesce((select c.activecampaign_ligado or c.sendflow_ligado or c.unnichat_ligado from crm.config c), true) then
    -- não liga nada: só confere que a migration não ligou (respondi_ligado pode já estar ligado pelo Arthur)
    raise exception '20261006c: kill-switch de AC/SendFlow/Unnichat ligado (esperado false ao aplicar)';
  end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamadas separadas; desliga do mesmo jeito com false) ════════════════════════
-- 1. Segredo de cada webhook no Vault (valor gerado na hora, nunca em arquivo/chat):
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_activecampaign', 'F5 webhook AC');
--      select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_webhook_unnichat', 'F5 webhook Unnichat');
--      (SendFlow: só quando houver a chave/conta; até lá fica sem segredo = recusa tudo.)
-- 2. Deploy da Edge crm-integracao-webhook (verify_jwt = false) e cadastro da URL no AC/Unnichat.
-- 3. update crm.config set activecampaign_ligado = true;   -- e/ou respondi_ligado, unnichat_ligado, sendflow_ligado
-- 4. Reprocessar o que não casou (opcional): select public.crm_integracao_reprocessar(500);  -- como service_role/postgres

-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- update crm.config set activecampaign_ligado = false, sendflow_ligado = false, respondi_ligado = false, unnichat_ligado = false;
--   (desliga em ~10 s, sem deploy: preferir isto)
-- Desfazer de vez (tabelas novas; dado de fila/link escrito fica no crm.log):
-- drop function public.crm_integracao_receber(text,text,jsonb), public.crm_integracao_reprocessar(int),
--   public.crm_filas(boolean), public.crm_links(boolean,boolean), public.crm_criar_fila(jsonb), public.crm_encerrar_fila(uuid),
--   public.crm_atribuir_item_fila(uuid,uuid,uuid), public.crm_atualizar_item_fila(uuid,uuid,text),
--   public.crm_criar_link(uuid,text,text,text,text,text,text), public.crm_arquivar_link(uuid);
-- jornada: recriar public.crm_jornada com o corpo da 20261005s (md5 4e4cbddd4f9de648ab9ffc71441e8936).
-- drop table crm.fila_item, crm.fila, crm.link_rastreavel, crm.evento_jornada;
-- drop function crm.pessoa_por_email(text), crm.anexar_integracao(bigint), crm.ponto_integracao(text,text,text,text),
--   crm.emails_da_pessoa(uuid), crm.score_recuperacao(text[]), crm.oferta_vigente_texto(text), crm.limpa_sck(text),
--   crm.fila_entrada(jsonb);
-- alter table crm.config drop column unnichat_ligado;
-- drop index concurrently controle.ix_unnichat_evento_email; drop index concurrently respondi.ix_respostas_fone_sem_email;  -- à parte

-- ═══ FIM DOS CORPOS (F2 + F5) ═══════════════════════════════════════════════════════════════════════════════════════
create temp table _v (k text primary key, u uuid, t text) on commit drop;
create function pg_temp.v(p text) returns uuid language sql as $$ select u from pg_temp._v where k = p $$;
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
create function pg_temp.r(p_quem text, p_call text) returns jsonb language sql as $$
  select pg_temp.chamar(pg_temp.v(p_quem), 'select ' || p_call) $$;
-- explain (analyze, buffers) como postgres; devolve só as linhas do plano (sem valores de dado)
create function pg_temp.explica(p_sql text) returns setof text language plpgsql as $$
declare l text;
begin
  for l in execute 'explain (analyze, buffers, costs off) ' || p_sql loop return next l; end loop;
end $$;
create function pg_temp.ms(p_quem text, p_call text) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); j jsonb;
begin
  j := pg_temp.r(p_quem, p_call);
  if j ? 'erro' then raise exception 'ms: %', j ->> 'erro'; end if;
  return round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
end $$;

create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, '')) $$;
insert into _v (k, u) select 'gestor', p.id from public.perfis p
 where p.cargo = 'admin' and p.status = 'ativo' and p.nome ilike 'jonathan%' order by p.criado_em limit 1;
update crm.config set escrita_ligada = true;
-- B7: fila com 5.000 contatos (pessoas fictícias) → montar e ler
create temp table _p on commit drop as
  select gen_random_uuid() id, g rn from generate_series(1, 5000) g;
insert into pessoas.pessoas (id, nome, teste) select id, 'Ensaio Fcinco Massa ' || rn, true from _p;
do $b7$
declare t0 timestamptz; j jsonb; v_m1 numeric; v_l1 numeric; v_l2 numeric;
begin
  t0 := clock_timestamp();
  j := pg_temp.r('gestor', format('public.crm_criar_fila(%L::jsonb)', jsonb_build_object('nome', 'Ensaio massa', 'produto', 'ht',
         'itens', (select jsonb_agg(jsonb_build_object('contatoId', id, 'sinais',
                     case rn % 4 when 0 then '["boleto_aberto","ficha_completa"]'::jsonb when 1 then '["carrinho"]'::jsonb
                                 when 2 then '["carrinho","chat","grupo"]'::jsonb else '["senhas","pesquisa"]'::jsonb end)) from _p))));
  v_m1 := round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
  v_l1 := pg_temp.ms('gestor', 'public.crm_filas()');
  v_l2 := pg_temp.ms('gestor', 'public.crm_filas()');
  perform pg_temp.ok('B7.fila_5000', (j ->> 'itens')::int = 5000, format('montar 5.000: %s ms (%s); crm_filas %s/%s ms; log da montagem: %s linha(s); faixas %s',
                     v_m1, coalesce(j ->> 'msg', j ->> 'erro'), v_l1, v_l2,
                     (select count(*) from crm.log l where l.entidade = 'fila' and l.entidade_id = j ->> 'filaId'),
                     (select string_agg(faixa || '=' || n, ' ' order by faixa) from (select faixa, count(*) n from crm.fila_item group by 1) x)));
end $b7$;

select passo, linha from _z_out order by n;
rollback;

-- ═══ PARTE C: nada persistiu (chamada separada, só leitura) ════════════════════════════════════════════════════════
select to_regclass('crm.evento_jornada') evento_jornada, to_regclass('crm.fila') fila, to_regclass('crm.link_rastreavel') link,
       to_regprocedure('public.crm_mover_etapa(uuid,uuid)') rpc_f2, to_regprocedure('public.crm_integracao_receber(text,text,jsonb)') rpc_f5,
       (select md5(prosrc) from pg_proc where oid = 'public.crm_jornada(uuid,integer)'::regprocedure) jornada_md5,
       exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'unnichat_ligado') col_unnichat,
       (select row_to_json(c) from (select escrita_ligada, activecampaign_ligado, sendflow_ligado, respondi_ligado from crm.config) c) config,
       to_regclass('controle.ix_unnichat_evento_email') idx_unnichat, to_regclass('respondi.ix_respostas_fone_sem_email') idx_respondi,
       (select count(*) from vault.secrets where name like 'crm\_webhook\_%') segredos, (select count(*) from pessoas.pessoas) pessoas,
       (select count(*) from crm.pessoa_comercial) pc, (select count(*) from crm.produto_comercial) prod,
       (select count(*) from crm.oferta_comercial) ofertas;

-- ═══ RESULTADO (06/10/2026, produção, F0+F1+F2 aplicadas) ═══════════════════════════════════════════════════════════
-- PARTE A: 62 OK, 0 ERRADO (rodada 2×: antes e depois de renomear a tabela para crm.evento_jornada). Destaques: anon 0 funções; entrada do webhook só service_role (gestor → permission denied);
--   token errado / sem segredo no Vault → autorizado=false; kill-switch desligado → não grava; e-mail com maiúscula/
--   espaço casa; reenvio = duplicado (1 linha); e-mail desconhecido não casa pelo telefone nem cria pessoa; telefone sem
--   e-mail: 1 candidato casa, nome incompatível e 2 candidatos → telefone_ambiguo; reprocessar anexa quando a pessoa
--   aparece; jornada mostra o ponto com a UTM e some com o kill-switch; visualizador/vendedor sem vínculo → 42501;
--   fila: scores 60A/24D/36C, opt-out fora, C/D travadas até A/B zeradas, vendedor assume item sem dono, outro vendedor
--   recusado, ganho sem pagamento recusado, sem oferta vigente não se aborda, encerrada não muda; RLS de leitura
--   mp 3 / ro 1 / gestor 3; link: sck ht-recuperacao-20261006-whatsapp-mp + URL real da oferta, duplicado recusado,
--   vendedor só para si, gestor para outro com utm_campaign/utm_content, sem oferta vigente e oferta não vigente
--   recusadas. Tempos (2ª rodada): jornada 8,5/12,7 ms; webhook (casamento por telefone) 5,7/5,0 ms; crm_filas 2,0/2,2 ms.
-- PARTE B1/B2 rodaram antes da troca de nome (crm.integracao_evento → crm.evento_jornada; só o nome mudou).
-- PARTE B1: 6 OK. Pessoa real com telefone de 1 candidato: 2 pontos de grupo; telefone com 2+ candidatos: 1 evento na
--   fonte e 0 na jornada (a F1 mostraria); Respondi sem e-mail entra pelo telefone; Unnichat legado por e-mail: 3 pontos.
--   crm_jornada com todas as fontes ligadas: 10,2/14,8 ms, 9,7/9,2 ms, 8,7/8,8 ms.
--   Index Scan using ix_respostas_fone_sem_email (0,023 ms, 3 buffers); Index Scan using ix_unnichat_evento_email
--   (0,027 / 0,025 ms, 5 buffers).
-- PARTE B2: 1 OK. Montar 5.000: 1.026 ms, 1 linha de log; crm_filas com 5.000 itens: 177,8/170,4 ms.
-- PARTE C (conferida depois de cada rodada; a última depois da Parte A final): evento_jornada/fila/link/RPCs = null; jornada md5 = 4e4cbddd… (F1); coluna unnichat_ligado ausente;
--   kill-switches e escrita_ligada false; índices novos ausentes; 0 segredos crm_webhook_*; 0 pessoas; 0 camada
--   comercial/produto/oferta; 0 linhas de log de fila/link. Nada persistiu.
