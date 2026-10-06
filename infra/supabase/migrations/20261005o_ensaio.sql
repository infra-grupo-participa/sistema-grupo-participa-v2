-- 20261005o: ENSAIO (não aplica nada: cada bloco termina abortado; nada fica gravado)
--
-- COMO RODAR: blocos INDEPENDENTES. Cada um vai de "-- ▶ BLOCO n" até "-- ◀ FIM DO BLOCO n" e é mandado INTEIRO numa
--   única chamada (SQL editor, psql ou Management API), como postgres. Cada bloco: begin; corpo da migration (cópia
--   exata de 20261005o_mkt_mensageria_precos_integracoes.sql); preparo; testes; aborto.
--   O último comando de cada bloco é um RAISE de propósito: a mensagem de erro É O RELATÓRIO e o aborto garante que
--   nada persiste (Vault, cron.job, ops.rotina, pausa do job 26: tudo volta), mesmo que o cliente ignore o "rollback;".
--     esperado:  ERROR  ENSAIO 20261005o BLOCO n CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.  + linhas
--     qualquer outro erro (… FALHOU …, 42501 inesperado, timeout) = a migration não serve como está: NÃO aplicar.
--   lock_timeout 3s, statement_timeout 25s. Admin achado por subselect (gp_is_admin); chave da fonte lida do Vault
--   DENTRO da transação abortada e nunca impressa. Projetos: os 2 primeiros de mkt.projetos (nada escrito lá).
--
-- GERADO: o corpo da migration é colado sem mudança em cada bloco. Se a migration mudar, gerar de novo.
--
-- BLOCO 1 (segurança e regras): S1–S3 acesso; P1/P1b preços; P2 custo estimado por vigência; I1–I3 API; T1–T2 tela;
--   L1 LGPD e bloqueios; R1 reconciliação; V1 saúde e vigia; H1 histórico; P3 cron antigo.
-- BLOCO 2 (volume): 10.000 disparos + 3.000 vigências de preço; E1..E4 = explain (analyze, buffers) + "usa <índice>";
--   V1..V3 tempo real de listar e saúde.
-- BLOCO 3 (API no teto): lote de 1.000 novo, repetido (idempotente) e com mudança; reconciliar 20.000 ids.


-- ▶ BLOCO 1 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005o_mkt_mensageria_precos_integracoes.sql) ═══
-- 20261005o: Marketing > Mensageria (etapa 3): preços e custo estimado, infra comum das integrações, pausa do cron antigo
--
-- STATUS: ESCRITA, NÃO APLICADA. Ensaio: 20261005o_ensaio.sql. Medições e contrato: 20261005o.explain.md.
--
-- O QUE FAZ
--   P1 Preços. mkt_mensageria.precos (por ferramenta, canal, tipo e vigência; não se edita nem apaga: preço errado é
--      ANULADO com motivo). Custo estimado calculado NA LEITURA por UMA função (mkt_mensageria.custo_estimado: preço
--      vigente no dia de enviado_em, em São Paulo). custo_centavos (real) sempre prevalece. Sem preço = 'sem_preco',
--      nunca 0 inventado. Seed copiado de controle.custo_mensagem (medido em 05/10; a guarda confere os valores).
--   P2 Integrações. fontes (ligar/desligar sem deploy), execucoes, recusas, reconciliacao; chave por fonte no Vault
--      (nasce aqui, aleatória); RPC public.mkt_msg_api_receber (só service_role) com upsert idempotente por
--      (origem_sistema, id_externo); projeto pela [SIGLA] no nome da campanha (sem sigla = entra sem projeto, pendência
--      'sem_projeto'); public.mkt_msg_integracoes_saude; uma checagem no pg_cron por fonte (ligada só com a fonte
--      ativa) cadastrada em ops.rotina para o vigia avisar no Slack quando passar 2× o intervalo sem execução ok.
--      Retenção: payload de recusa expurgado após 30 dias (job diário mensageria-recusas-expurgo, em ops.rotina).
--      Porteiro da rota: public.mkt_msg_api_chave_ok (confere a chave antes de a rota ler o corpo).
--   P3 Pausa o cron 'ingest-mensageria-hourly' (jobid conferido pelo nome) e silencia a rotina dele no vigia.
--      Nada é apagado: controle.mensageria_envio e as views vw_mensageria_* ficam congeladas (última linha 28/08).
--
-- O QUE MUDA NO QUE JÁ EXISTE (20261005n, conferido igual ao banco vivo por md5 na guarda)
--   disparos.projeto_id deixa de ser NOT NULL; CHECK novo exige projeto fora da origem 'api'. Coluna nova campanha.
--   disparos.anonimizado_em (LGPD: a API não regrava linha anonimizada). historico: coluna nova por_api.
--   create or replace (mesma assinatura, sem sobrecarga): mkt_msg_disparos_listar (só ACRESCENTA campos),
--   mkt_msg_disparo_salvar (linha da API: só projeto, tipo e custo), mkt_msg_disparo_lancar_retorno (recusa linha da
--   API), mkt_msg_historico (+por_api), mkt_msg_anonimizar_disparo (+recusas do mesmo id_externo), trg_historico.
--
-- AS 5 PERGUNTAS
--   escala: listar continua limitado ao período (≤ 366 dias) e 500 linhas; o custo estimado é um lookup por linha no
--     índice de preços (precos_vigencia_unica). api_receber: lote ≤ 1.000; um SELECT por item no índice único
--     (origem_sistema, id_externo) + UM insert…on conflict para o lote. saúde: 5 fontes × lookups em
--     execucoes (fonte, inicio desc). reconciliar: ≤ 20.000 ids, anti-join no índice único.
--   índice: precos (ferramenta_id, canal, coalesce(tipo,''), vigente_desde desc) where anulado_em is null;
--     execucoes (fonte, inicio desc); recusas (execucao_id), (fonte, id_externo); reconciliacao (fonte, dia desc).
--     Prova: 20261005o_ensaio.sql bloco 2.
--   frequência: n8n manda lote por fonte no intervalo dela (seed 1 h, ajustável); checagem do vigia a cada 30 min
--     por fonte ATIVA (inativa = job desligado, custo zero).
--   repetição: listar é uma query (CTE materializada); o estimado é calculado uma vez por linha e reaproveitado em
--     linhas, totais e por_canal.
--   reversão: fonte → update mkt_mensageria.fontes set ativa = false (desliga recepção e checagem, sem deploy).
--     Rota → revoke execute on function public.mkt_msg_api_receber(text,text,jsonb) from service_role.
--     Cron antigo → bloco REVERSÃO no fim (alter_job active true + silenciado_ate null).

set local lock_timeout = '3s';
set local statement_timeout = '25s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_esperado jsonb := jsonb_build_object(
    'mkt_msg_disparos_listar', 'a49e66a21ad0e99cd46e9ac15869e4f0',
    'mkt_msg_disparo_salvar', '38a25ac0ce35da08408d5338babf1733',
    'mkt_msg_disparo_lancar_retorno', '07d6e198f3f4b51ca6bf0b61b1c99cea',
    'mkt_msg_historico', '527fd822fb59722c27489527ff5181de',
    'mkt_msg_anonimizar_disparo', '769c74b6a37513d2cc94fd2bb81ae602',
    'trg_historico', '6d94581a614a2dfe05559c6cda64f7c8');
  k text;
  v_md5 text;
begin
  if to_regnamespace('mkt_mensageria') is null then
    raise exception '20261005o: schema mkt_mensageria ausente: aplicar 20261005n antes';
  end if;
  if to_regclass('mkt_mensageria.precos') is not null or to_regclass('mkt_mensageria.fontes') is not null then
    raise exception '20261005o: mkt_mensageria.precos/fontes já existe (migration já aplicada?)';
  end if;
  -- As 6 funções reescritas aqui têm que estar como a 20261005n deixou (senão a reescrita apagaria mudança viva).
  for k in select jsonb_object_keys(v_esperado) loop
    select md5(p.prosrc) into v_md5 from pg_proc p
     where p.proname = k and p.pronamespace in ('public'::regnamespace, 'mkt_mensageria'::regnamespace);
    if v_md5 is distinct from v_esperado ->> k then
      raise exception '20261005o: % no banco difere da 20261005n (md5 %): reler a definição viva antes', k, v_md5;
    end if;
  end loop;
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '20261005o: vault.create_secret / extensions.gen_random_bytes ausente';
  end if;
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    raise exception '20261005o: pg_cron sem alter_job/schedule';
  end if;
  if to_regclass('ops.rotina') is null or to_regclass('ops.rotina_estado') is null then
    raise exception '20261005o: vigia (ops.rotina, ops.rotina_estado) ausente: 20261001a..f';
  end if;
  if to_regprocedure('auth.role()') is null then
    raise exception '20261005o: auth.role() ausente';
  end if;
  if exists (select 1 from mkt_mensageria.disparos where origem = 'api') then
    raise exception '20261005o: já existem disparos de origem api (esperado 0 antes da integração)';
  end if;
  -- Seed de preços é cópia de controle.custo_mensagem medida em 05/10/2026. Mudou lá? Rever o seed antes de aplicar.
  if (select count(*) from controle.custo_mensagem c
       where (c.plataforma, c.categoria, c.preco_base * (1 + coalesce(c.margem_bsp, 0)), c.vigente_desde) in (
             ('api', 'utility', 0.08, date '2026-07-01'), ('api', 'marketing', 0.36, date '2026-07-01'),
             ('unnichat', 'utility', 0.08, date '2026-07-24'), ('unnichat', 'marketing', 0.36, date '2026-07-24'),
             ('sms', 'sms', 0.065, date '2026-07-01'), ('activecampaign', 'email', 0, date '2026-07-29'),
             ('grupo', 'grupo', 0, date '2026-07-01'))) <> 7 then
    raise exception '20261005o: controle.custo_mensagem mudou desde 05/10/2026: rever o seed de preços';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas
       where nome in ('Unichat', 'Ligue Lead', 'ActiveCampaign', 'SendFlow', 'Infobip')) <> 5 then
    raise exception '20261005o: ferramentas do seed ausentes (Unichat, Ligue Lead, ActiveCampaign, SendFlow, Infobip)';
  end if;
end
$guarda$;

-- ─── 1. Mudanças em disparos e historico ─────────────────────────────────────────────────────────────────────────────
-- Projeto: a integração grava sem projeto quando o nome da campanha não traz [SIGLA] cadastrada (fila 'sem_projeto').
-- Tela e planilha continuam obrigadas (disparo_validar + CHECK abaixo).
alter table mkt_mensageria.disparos alter column projeto_id drop not null;
alter table mkt_mensageria.disparos
  add constraint disparos_projeto_fora_da_api check (projeto_id is not null or origem = 'api');
alter table mkt_mensageria.disparos
  add column campanha text check (campanha is null or length(btrim(campanha)) between 1 and 300);
alter table mkt_mensageria.disparos add column anonimizado_em timestamptz;
comment on column mkt_mensageria.disparos.anonimizado_em is 'LGPD: quando mkt_msg_anonimizar_disparo limpou o conteúdo. A integração não toca mais a linha (nem métricas).';
comment on column mkt_mensageria.disparos.campanha is 'Nome da campanha na ferramenta de origem (integração). A [SIGLA] dentro dele define o projeto.';
comment on column mkt_mensageria.disparos.projeto_id is 'Projeto (mkt.projetos). Nulo só em origem api sem [SIGLA] cadastrada no nome da campanha: pendência sem_projeto.';

alter table mkt_mensageria.historico
  add column por_api text check (por_api is null or por_api ~ '^api:[a-z][a-z_]{1,39}$');
comment on column mkt_mensageria.historico.por_api is 'Autor quando a mudança veio da integração (auth.uid() nulo): api:<fonte>.';

-- ─── 2. Preços ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Sem default em nenhuma coluna de regra (canal, tipo, base, preço, vigência): um default desfaz a regra em silêncio no
-- próximo INSERT de vigência. criado_em é carimbo, não regra.
create table mkt_mensageria.precos (
  id              bigint generated always as identity primary key,
  ferramenta_id   bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  canal           text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  tipo            text check (tipo is null or tipo in ('utility', 'marketing')),
  base_cobranca   text not null check (base_cobranca in ('entregues', 'tamanho_lista', 'mensalidade')),
  preco_centavos  numeric(12, 4) not null check (preco_centavos >= 0 and preco_centavos <= 100000),
  vigente_desde   date not null check (vigente_desde between date '2020-01-01' and date '2100-12-31'),
  obs             text check (obs is null or length(obs) <= 500),
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,      -- nulo só no seed desta migration
  anulado_em      timestamptz,
  anulado_por     uuid references public.perfis(id) on delete set null,
  anulado_motivo  text check (anulado_motivo is null or length(btrim(anulado_motivo)) between 3 and 500),
  constraint precos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  -- mensalidade: o custo é o mensal da ferramenta; por disparo, 0.
  constraint precos_mensalidade_zero check (base_cobranca <> 'mensalidade' or preco_centavos = 0),
  constraint precos_anulacao_completa check ((anulado_em is null) = (anulado_motivo is null))
);
-- Uma vigência válida por (ferramenta, canal, tipo, data); é também o índice da busca do preço vigente
-- (… = … and vigente_desde <= dia order by vigente_desde desc limit 1). coalesce(tipo,'') porque tipo é nulo fora da API.
create unique index precos_vigencia_unica on mkt_mensageria.precos
  (ferramenta_id, canal, coalesce(tipo, ''), vigente_desde desc) where anulado_em is null;
comment on table mkt_mensageria.precos is 'Preço por mensagem (centavos, 4 casas) por ferramenta/canal/tipo e vigência. Não se edita nem apaga: anular com motivo e cadastrar outro.';

-- ─── 3. Integrações: fontes, execucoes, recusas, reconciliacao ───────────────────────────────────────────────────────
create table mkt_mensageria.fontes (
  chave               text primary key check (chave ~ '^[a-z][a-z_]{1,39}$'),
  nome                text not null check (length(btrim(nome)) between 2 and 60),
  ferramenta_id       bigint references mkt_mensageria.ferramentas(id) on delete restrict,   -- nulo: o item diz a ferramenta
  ativa               boolean not null,                     -- sem default: ligar/desligar é decisão explícita
  ativa_desde         timestamptz,                          -- trigger: carimba ao ligar, zera ao desligar
  intervalo_esperado  interval not null check (intervalo_esperado between interval '5 minutes' and interval '7 days'),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint fontes_ativa_desde check (ativa = (ativa_desde is not null))
);
comment on table mkt_mensageria.fontes is 'Sistemas que mandam disparos pela API. ativa=false recusa o lote e desliga a checagem do vigia (sem deploy). Chave no Vault: mkt_msg_fonte_<chave>.';

create table mkt_mensageria.execucoes (
  id           bigint generated always as identity primary key,
  fonte        text not null references mkt_mensageria.fontes(chave) on delete restrict,
  inicio       timestamptz not null,
  fim          timestamptz not null,
  lidos        integer not null check (lidos >= 0),
  inseridos    integer not null check (inseridos >= 0),
  atualizados  integer not null check (atualizados >= 0),
  inalterados  integer not null check (inalterados >= 0),
  recusados    integer not null check (recusados >= 0),
  status       text not null check (status in ('ok', 'inconsistente', 'fonte_inativa', 'lote_invalido')),
  detalhe      text check (detalhe is null or length(detalhe) <= 300),
  constraint execucoes_fim_depois check (fim >= inicio)
);
create index execucoes_fonte_inicio_idx on mkt_mensageria.execucoes (fonte, inicio desc);
comment on table mkt_mensageria.execucoes is 'Uma linha por lote recebido com chave válida. inconsistente = lidos ≠ inseridos+atualizados+inalterados+recusados. Só acréscimo.';

create table mkt_mensageria.recusas (
  id                  bigint generated always as identity primary key,
  execucao_id         bigint not null references mkt_mensageria.execucoes(id) on delete restrict,
  fonte               text not null references mkt_mensageria.fontes(chave) on delete restrict,
  posicao             integer not null check (posicao >= 1),
  id_externo          text check (id_externo is null or length(id_externo) <= 200),
  motivo              text not null check (length(motivo) between 3 and 500),
  payload             jsonb not null,
  criado_em           timestamptz not null default now(),
  anonimizado_em      timestamptz,
  anonimizado_por     uuid,
  anonimizado_motivo  text check (anonimizado_motivo is null or length(btrim(anonimizado_motivo)) between 3 and 500),
  expurgado_em        timestamptz                           -- retenção: payload trocado por {"expurgado":true} após 30 dias
);
create index recusas_execucao_idx on mkt_mensageria.recusas (execucao_id);
create index recusas_externo_idx on mkt_mensageria.recusas (fonte, id_externo) where id_externo is not null;
create index recusas_criado_idx on mkt_mensageria.recusas (criado_em desc);
comment on table mkt_mensageria.recusas is 'Item do lote que não entrou, com o motivo e o item recebido (payload). LGPD: mkt_msg_anonimizar_disparo (mesmo id_externo), mkt_msg_anonimizar_recusa e expurgo do payload após 30 dias (job mensageria-recusas-expurgo). Leitura sem payload: mkt_msg_recusas_listar (admin).';

create table mkt_mensageria.reconciliacao (
  id               bigint generated always as identity primary key,
  fonte            text not null references mkt_mensageria.fontes(chave) on delete restrict,
  dia              date not null,
  contagem_fonte   integer not null check (contagem_fonte >= 0),
  contagem_log     integer not null check (contagem_log >= 0),
  faltantes_total  integer not null check (faltantes_total >= 0),
  faltantes        jsonb not null check (jsonb_typeof(faltantes) = 'array'),   -- até 500 id_externo
  criado_em        timestamptz not null default now()
);
create index reconciliacao_fonte_dia_idx on mkt_mensageria.reconciliacao (fonte, dia desc, id desc);
comment on table mkt_mensageria.reconciliacao is 'Conferência diária: quantos a fonte diz que enviou x quantos estão no log, e os id_externo que faltam. Só acréscimo.';

alter table mkt_mensageria.precos enable row level security;
alter table mkt_mensageria.fontes enable row level security;
alter table mkt_mensageria.execucoes enable row level security;
alter table mkt_mensageria.recusas enable row level security;
alter table mkt_mensageria.reconciliacao enable row level security;
revoke all on mkt_mensageria.precos, mkt_mensageria.fontes, mkt_mensageria.execucoes, mkt_mensageria.recusas,
              mkt_mensageria.reconciliacao from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Funções internas (revoke de todos logo após cada create) ─────────────────────────────────────────────────────
create function mkt_mensageria.fonte_jobname(p_chave text) returns text
language sql immutable set search_path = '' as $$
  select 'mensageria-fonte-' || replace(p_chave, '_', '-');
$$;
revoke all on function mkt_mensageria.fonte_jobname(text) from public, anon, authenticated;

-- A ÚNICA regra de custo estimado. Preço vigente = a vigência não anulada mais recente com vigente_desde ≤ dia do
-- envio (São Paulo). entregues: entregues × preço (entregues nulo = sem estimativa); tamanho_lista: tamanho × preço;
-- mensalidade: 0 por disparo. Sem preço: centavos nulo e tem_preco = false (nunca 0 inventado).
create function mkt_mensageria.custo_estimado(p_ferramenta bigint, p_canal text, p_tipo text, p_enviado_em timestamptz,
                                              p_entregues integer, p_tamanho integer,
                                              out centavos bigint, out tem_preco boolean, out preco_id bigint)
language sql stable set search_path = '' as $$
  select case pv.base_cobranca
           when 'mensalidade' then 0::bigint
           when 'tamanho_lista' then round(p_tamanho * pv.preco_centavos)::bigint
           when 'entregues' then round(p_entregues * pv.preco_centavos)::bigint
         end,
         pv.id is not null,
         pv.id
    from (select 1) um
    left join lateral (
      select p.id, p.base_cobranca, p.preco_centavos
        from mkt_mensageria.precos p
       where p.ferramenta_id = p_ferramenta and p.canal = p_canal and coalesce(p.tipo, '') = coalesce(p_tipo, '')
         and p.vigente_desde <= (p_enviado_em at time zone 'America/Sao_Paulo')::date
         and p.anulado_em is null
       order by p.vigente_desde desc
       limit 1) pv on true;
$$;
revoke all on function mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer) from public, anon, authenticated;

-- Pendências (versão 2; a v1 mkt_mensageria.pendencias fica, sem uso). Ordem: as 3 antigas, depois as novas.
--   sem_custo: nem custo real nem estimado · sem_retorno: entregues ou lidas nulas (canal grupo dispensa)
--   conferir_zero_leitura: 0 lidas com custo (real ou estimado) > 0 · sem_preco: sem custo real e sem preço vigente
--   sem_projeto: entrou pela integração sem [SIGLA] cadastrada
create function mkt_mensageria.pendencias_v2(p_canal text, p_projeto bigint, p_entregues integer, p_lidas integer,
                                             p_custo integer, p_custo_estimado bigint, p_tem_preco boolean) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null and p_custo_estimado is null then 'sem_custo' end,
    case when p_canal <> 'grupo' and (p_entregues is null or p_lidas is null) then 'sem_retorno' end,
    case when p_lidas = 0 and coalesce(p_custo::bigint, p_custo_estimado) > 0 then 'conferir_zero_leitura' end,
    case when p_custo is null and not coalesce(p_tem_preco, false) then 'sem_preco' end,
    case when p_projeto is null then 'sem_projeto' end], null);
$$;
revoke all on function mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean) from public, anon, authenticated;

-- Atraso da fonte: tempo desde a última execução ok (ou desde que foi ligada). Atrasada = ativa e > 2× o intervalo.
-- Usada pela saúde e pela checagem do vigia (mesma regra nos dois).
create function mkt_mensageria.fonte_atraso(p_fonte text, out ativa boolean, out ultima_ok_em timestamptz,
                                            out atraso interval, out atrasada boolean)
language sql stable set search_path = '' as $$
  select f.ativa, u.fim,
         case when f.ativa then now() - greatest(u.fim, f.ativa_desde) end,
         coalesce(f.ativa and now() - greatest(u.fim, f.ativa_desde) > 2 * f.intervalo_esperado, false)
    from mkt_mensageria.fontes f
    left join lateral (select e.fim from mkt_mensageria.execucoes e
                        where e.fonte = f.chave and e.status = 'ok'
                        order by e.inicio desc limit 1) u on true
   where f.chave = p_fonte;
$$;
revoke all on function mkt_mensageria.fonte_atraso(text) from public, anon, authenticated;

-- Comando do pg_cron de cada fonte. Atrasada = erro (falha_sql) → o vigia abre incidente e avisa no Slack.
create function mkt_mensageria.vigiar_fonte(p_fonte text) returns text
language plpgsql stable set search_path = '' as $$
declare
  r record;
begin
  select * into r from mkt_mensageria.fonte_atraso(p_fonte);
  if r.ativa is null then
    raise exception 'Mensageria: fonte % não cadastrada', p_fonte;
  end if;
  if r.atrasada then
    raise exception 'Mensageria: fonte % sem execução ok há % (esperado a cada %)', p_fonte, date_trunc('minute', r.atraso),
      (select f.intervalo_esperado from mkt_mensageria.fontes f where f.chave = p_fonte);
  end if;
  return case when r.ativa then 'ok' else 'inativa' end;
end
$$;
revoke all on function mkt_mensageria.vigiar_fonte(text) from public, anon, authenticated;

-- Confere a chave da fonte contra o Vault (sha256: não vaza prefixo por tempo). Formato fixo antes de consultar.
create function mkt_mensageria.chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v text;
begin
  if p_fonte is null or p_chave is null or p_chave !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_' || p_fonte;
  if v is null then
    return false;
  end if;
  return sha256(convert_to(p_chave, 'UTF8')) = sha256(convert_to(v, 'UTF8'));
end
$$;
revoke all on function mkt_mensageria.chave_ok(text, text) from public, anon, authenticated;

-- Um item do lote → valores finais (já mesclados com o que está gravado) ou motivo da recusa.
-- Mescla: campo ausente/nulo no item = mantém o gravado (NULL da fonte nunca apaga). tipo e custo_centavos: o gravado
-- vence quando existe (a tela pode ter corrigido). Projeto: o gravado vence; senão a [SIGLA] da campanha.
-- Validação: a mesma da tela (disparo_validar), sobre o resultado da mescla; só o erro "projeto" é dispensado.
create function mkt_mensageria.api_item(p_fonte text, p_ferr_fixa bigint, p_item jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ext text;
  d mkt_mensageria.disparos%rowtype;
  v_existe boolean;
  v_campanha text;
  v_proj bigint;
  v_nproj integer;
  v_sigla text;
  v_ferr bigint;
  v_txt text;
  v_num bigint;
  v_canon jsonb;
  k text;
  r jsonb;
  v_motivo text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_object('motivo', 'Item não é um objeto JSON.');
  end if;
  v_ext := btrim(coalesce(p_item ->> 'id_externo', ''));
  if v_ext = '' or length(v_ext) > 200 then
    return jsonb_build_object('motivo', 'id_externo ausente ou com mais de 200 caracteres.');
  end if;

  select * into d from mkt_mensageria.disparos x where x.origem_sistema = p_fonte and x.id_externo = v_ext;
  v_existe := found;
  if v_existe and d.arquivado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- arquivado pela tela: a API não mexe
  end if;
  if v_existe and d.anonimizado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- LGPD: anonimizado, a API não regrava nada
  end if;

  v_campanha := nullif(left(btrim(coalesce(p_item ->> 'campanha', '')), 300), '');
  if v_campanha is null and v_existe then v_campanha := d.campanha; end if;
  -- [SIGLA]: o conteúdo de um colchete que seja sigla cadastrada. Nenhuma, ou duas siglas diferentes = sem projeto.
  select min(pr.id), count(distinct pr.id) into v_proj, v_nproj
    from regexp_matches(coalesce(v_campanha, ''), '\[([^][]{1,20})\]', 'g') m
    join mkt.projetos pr on pr.sigla = upper(btrim(m[1]));
  if v_nproj <> 1 then v_proj := null; end if;
  if v_existe and d.projeto_id is not null then v_proj := d.projeto_id; end if;
  select pr.sigla into v_sigla from mkt.projetos pr where pr.id = v_proj;

  if p_ferr_fixa is not null then
    v_ferr := p_ferr_fixa;
  else
    v_txt := btrim(coalesce(p_item ->> 'ferramenta', ''));
    if v_txt <> '' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
      if v_ferr is null then
        return jsonb_build_object('id_externo', v_ext, 'motivo', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.');
      end if;
    elsif v_existe then
      v_ferr := d.ferramenta_id;
    end if;
  end if;

  v_txt := regexp_replace(coalesce(p_item ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      return jsonb_build_object('id_externo', v_ext, 'motivo', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.');
    end if;
  elsif v_existe then
    v_num := d.numero_id;
  end if;

  v_canon := case when v_existe then jsonb_build_object(
      'enviado_em', d.enviado_em, 'canal', d.canal, 'tipo', d.tipo, 'copy_texto', d.copy_texto, 'copy_link', d.copy_link,
      'publico_lista', d.publico_lista, 'publico_origem', d.publico_origem, 'tamanho_lista', d.tamanho_lista,
      'entregues', d.entregues, 'lidas', d.lidas, 'cliques', d.cliques, 'falhas', d.falhas,
      'custo_centavos', d.custo_centavos, 'disparado_por', d.disparado_por)
    else '{}'::jsonb end;
  foreach k in array array['enviado_em', 'canal', 'tipo', 'copy_texto', 'copy_link', 'publico_lista', 'publico_origem',
                           'tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'disparado_por'] loop
    if jsonb_typeof(p_item -> k) is not null and jsonb_typeof(p_item -> k) <> 'null'
       and not (k in ('tipo', 'custo_centavos') and jsonb_typeof(v_canon -> k) is not null and jsonb_typeof(v_canon -> k) <> 'null') then
      v_canon := v_canon || jsonb_build_object(k, p_item -> k);
    end if;
  end loop;
  v_canon := v_canon || jsonb_build_object('projeto', coalesce(v_sigla, ''), 'ferramenta_id', v_ferr::text,
                                           'numero_id', v_num::text);
  if nullif(btrim(coalesce(v_canon ->> 'disparado_por', '')), '') is null then
    v_canon := v_canon || jsonb_build_object('disparado_por', 'api:' || p_fonte);
  end if;

  r := mkt_mensageria.disparo_validar(v_canon);
  select left(string_agg(x ->> 'campo' || ': ' || (x ->> 'msg'), '; '), 500) into v_motivo
    from jsonb_array_elements(r -> 'erros') x
   where x ->> 'campo' <> 'projeto';
  if v_motivo is not null then
    return jsonb_build_object('id_externo', v_ext, 'motivo', v_motivo);
  end if;
  return jsonb_build_object('id_externo', v_ext, 'existe', v_existe,
    'v', (r -> 'v') || jsonb_build_object('projeto_id', v_proj, 'campanha', v_campanha, 'id_externo', v_ext));
end
$$;
revoke all on function mkt_mensageria.api_item(text, bigint, jsonb) from public, anon, authenticated;

-- Upsert idempotente do lote por (origem_sistema, id_externo). Uma passada de validação + UM insert…on conflict.
-- UPDATE só quando algum valor muda (o WHERE do DO UPDATE); tipo, projeto e custo: o gravado vence na hora da escrita
-- (fecha a corrida com a tela). Lock por fonte: dois lotes da mesma fonte viram fila. Repetido no lote: vale o último.
-- Autor no histórico: 'api:<fonte>' (flag local à transação, lida pelo trg_historico quando auth.uid() é nulo).
create function mkt_mensageria.api_upsert(p_fonte text, p_lote jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_ferr_fixa bigint;
  v_res jsonb[];
  v_n integer;
  v_ins integer := 0;
  v_upd integer := 0;
  v_validos integer;
  v_arq integer;
  v_recusas jsonb;
begin
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    raise exception 'api_upsert: lote tem que ser array de até 1.000 itens' using errcode = '22023';
  end if;
  select f.ferramenta_id into v_ferr_fixa from mkt_mensageria.fontes f where f.chave = p_fonte;
  if not found then
    raise exception 'api_upsert: fonte % não cadastrada', p_fonte using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_lote);
  perform pg_advisory_xact_lock(hashtext('mkt_mensageria.api:' || p_fonte));
  perform set_config('mkt_mensageria.autor_api', 'api:' || p_fonte, true);

  select coalesce(array_agg(x.r order by x.pos), '{}') into v_res
    from (select t.pos,
                 case when t.ext is not null and t.rep > 1
                      then jsonb_build_object('pos', t.pos, 'id_externo', t.ext,
                                              'motivo', 'id_externo repetido no lote: vale a última ocorrência.')
                      else jsonb_build_object('pos', t.pos) || mkt_mensageria.api_item(p_fonte, v_ferr_fixa, t.item) end as r
            from (select e.item, e.pos::int as pos, nullif(btrim(e.item ->> 'id_externo'), '') as ext,
                         row_number() over (partition by nullif(btrim(e.item ->> 'id_externo'), '') order by e.pos desc) as rep
                    from jsonb_array_elements(p_lote) with ordinality e(item, pos)) t) x;

  with v as (
    select r -> 'v' as v from unnest(v_res) r where r ? 'v'
  ), up as (
    insert into mkt_mensageria.disparos as d (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, origem_sistema, id_externo, campanha)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'api', p_fonte, v ->> 'id_externo', v ->> 'campanha'
      from v
    on conflict (origem_sistema, id_externo) where id_externo is not null do update
       set enviado_em = excluded.enviado_em, projeto_id = coalesce(d.projeto_id, excluded.projeto_id),
           canal = excluded.canal, ferramenta_id = excluded.ferramenta_id, numero_id = excluded.numero_id,
           tipo = coalesce(d.tipo, excluded.tipo), copy_texto = excluded.copy_texto, copy_link = excluded.copy_link,
           publico_lista = excluded.publico_lista, publico_origem = excluded.publico_origem,
           tamanho_lista = excluded.tamanho_lista, entregues = excluded.entregues, lidas = excluded.lidas,
           cliques = excluded.cliques, falhas = excluded.falhas,
           custo_centavos = coalesce(d.custo_centavos, excluded.custo_centavos),
           disparado_por = excluded.disparado_por, campanha = excluded.campanha,
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from (excluded.entregues, excluded.lidas, excluded.cliques, excluded.falhas,
                                                    coalesce(d.custo_centavos, excluded.custo_centavos))
                             then now() else d.retorno_em end
     where d.arquivado_em is null and d.anonimizado_em is null
       and (d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
            d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
            d.custo_centavos, d.disparado_por, d.campanha)
           is distinct from
           (excluded.enviado_em, coalesce(d.projeto_id, excluded.projeto_id), excluded.canal, excluded.ferramenta_id,
            excluded.numero_id, coalesce(d.tipo, excluded.tipo), excluded.copy_texto, excluded.copy_link,
            excluded.publico_lista, excluded.publico_origem, excluded.tamanho_lista, excluded.entregues, excluded.lidas,
            excluded.cliques, excluded.falhas, coalesce(d.custo_centavos, excluded.custo_centavos),
            excluded.disparado_por, excluded.campanha)
    returning (d.xmax = 0) as inserido
  )
  select count(*) filter (where inserido), count(*) filter (where not inserido) into v_ins, v_upd from up;

  select count(*) filter (where r ? 'v'), count(*) filter (where r ? 'arquivado') into v_validos, v_arq from unnest(v_res) r;
  select coalesce(jsonb_agg(jsonb_build_object(
           'posicao', (r ->> 'pos')::int, 'id_externo', r ->> 'id_externo', 'motivo', r ->> 'motivo',
           'payload', case when r ->> 'id_externo' is not null and (
                                  exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = p_fonte
                                             and d.id_externo = r ->> 'id_externo' and d.anonimizado_em is not null)
                                  or exists (select 1 from mkt_mensageria.recusas x where x.fonte = p_fonte
                                             and x.id_externo = r ->> 'id_externo' and x.anonimizado_em is not null))
                           then jsonb_build_object('anonimizado', true)
                           when length((p_lote -> ((r ->> 'pos')::int - 1))::text) <= 20000 then p_lote -> ((r ->> 'pos')::int - 1)
                           else jsonb_build_object('truncado', true, 'tamanho', length((p_lote -> ((r ->> 'pos')::int - 1))::text)) end)
           order by (r ->> 'pos')::int), '[]'::jsonb)
    into v_recusas
    from unnest(v_res) r where r ? 'motivo';
  perform set_config('mkt_mensageria.autor_api', '', true);

  return jsonb_build_object('lidos', v_n, 'inseridos', v_ins, 'atualizados', v_upd,
                            'inalterados', v_validos - v_ins - v_upd + v_arq,
                            'recusados', jsonb_array_length(v_recusas), 'recusas', v_recusas);
end
$$;
revoke all on function mkt_mensageria.api_upsert(text, jsonb) from public, anon, authenticated;

-- Retenção LGPD das recusas: payload com mais de 30 dias vira {"expurgado":true} (motivo, id_externo e datas ficam).
-- Até 5.000 por execução (job diário). Grava: não pode ser stable.
create function mkt_mensageria.recusas_expurgar() returns integer
language plpgsql set search_path = '' as $$
declare
  v integer;
begin
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('expurgado', true), expurgado_em = now()
   where r.id in (select x.id from mkt_mensageria.recusas x
                   where x.criado_em < now() - interval '30 days' and x.expurgado_em is null and x.anonimizado_em is null
                   order by x.criado_em limit 5000);
  get diagnostics v = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  return v;
end
$$;
revoke all on function mkt_mensageria.recusas_expurgar() from public, anon, authenticated;

-- ─── 5. Triggers ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Histórico: igual à 20261005n + autor da integração (por_api) quando auth.uid() é nulo.
create or replace function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
  v_uid uuid := auth.uid();
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por, por_api)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, v_uid,
          case when v_uid is null then nullif(current_setting('mkt_mensageria.autor_api', true), '') end);
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Preço: só a anulação (uma vez, com motivo). Nada mais muda.
create function mkt_mensageria.trg_preco_anular() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.anulado_em is not null then
    raise exception 'mkt_mensageria.precos: preço já anulado não muda' using errcode = '42501';
  end if;
  if new.anulado_em is null
     or (new.id, new.ferramenta_id, new.canal, new.tipo, new.base_cobranca, new.preco_centavos, new.vigente_desde,
         new.obs, new.criado_em, new.criado_por)
        is distinct from (old.id, old.ferramenta_id, old.canal, old.tipo, old.base_cobranca, old.preco_centavos,
                          old.vigente_desde, old.obs, old.criado_em, old.criado_por) then
    raise exception 'mkt_mensageria.precos: preço não se edita (anule com motivo e cadastre outro)' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_preco_anular() from public, anon, authenticated;

-- Fonte: chave imutável; ativa_desde carimbado ao ligar e zerado ao desligar; liga/desliga junto a checagem do vigia.
create function mkt_mensageria.trg_fonte() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_job bigint;
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.ativa_desde := case when new.ativa then now() end;
  else
    if new.chave is distinct from old.chave then
      raise exception 'mkt_mensageria.fontes: a chave não muda' using errcode = '42501';
    end if;
    new.criado_em := old.criado_em;
    new.ativa_desde := case when not new.ativa then null when old.ativa then old.ativa_desde else now() end;
    if new.ativa is distinct from old.ativa then
      select j.jobid into v_job from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(new.chave);
      if v_job is not null then
        perform cron.alter_job(v_job, active := new.ativa);
      end if;
    end if;
  end if;
  new.atualizado_em := now();
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_fonte() from public, anon, authenticated;

-- Recusa: só a anonimização LGPD e o expurgo (flag local) mudam, e só payload + campos anonimizado_*/expurgado_em.
create function mkt_mensageria.trg_recusa_anonimizar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on'
     and (new.id, new.execucao_id, new.fonte, new.posicao, new.id_externo, new.motivo, new.criado_em)
         is not distinct from (old.id, old.execucao_id, old.fonte, old.posicao, old.id_externo, old.motivo, old.criado_em) then
    return new;
  end if;
  raise exception 'mkt_mensageria.recusas: UPDATE não é permitido (só a anonimização LGPD)' using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_recusa_anonimizar() from public, anon, authenticated;

create trigger a_anular before update on mkt_mensageria.precos
  for each row execute function mkt_mensageria.trg_preco_anular();
create trigger a_fonte before insert or update on mkt_mensageria.fontes
  for each row execute function mkt_mensageria.trg_fonte();
create trigger sem_update before update on mkt_mensageria.recusas
  for each row execute function mkt_mensageria.trg_recusa_anonimizar();
create trigger sem_update before update on mkt_mensageria.execucoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.reconciliacao
  for each row execute function mkt_mensageria.trg_bloqueio();
do $bloqueio$
declare t text;
begin
  foreach t in array array['precos', 'fontes', 'execucoes', 'recusas', 'reconciliacao'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;

-- ─── 6. Seeds ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Preços: cópia EXPLÍCITA de controle.custo_mensagem (05/10/2026; a guarda conferiu). Reais → centavos (× 100).
-- Base: WhatsApp e grupo por entregue e SMS por envio, como a vw_mensageria_envio cobrava (sms: qtd_sms/enviados).
-- E-mail e grupo: 0 por disparo (mensalidade). Infobip SMS: SEM preço (pendência: a listagem mostra 'sem_preco').
insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs)
select f.id, s.canal, s.tipo, s.base, s.preco, s.vig, s.obs
  from (values
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, marketing'),
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, marketing'),
    ('Ligue Lead', 'sms', null, 'tamanho_lista', 6.5000, date '2026-07-01', 'controle.custo_mensagem: plataforma sms'),
    ('ActiveCampaign', 'email', null, 'mensalidade', 0.0000, date '2026-07-29', 'controle.custo_mensagem: plataforma activecampaign'),
    ('SendFlow', 'grupo', null, 'mensalidade', 0.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma grupo')
  ) s(ferramenta, canal, tipo, base, preco, vig, obs)
  join mkt_mensageria.ferramentas f on f.nome = s.ferramenta;

-- Fontes: todas DESLIGADAS (nenhum fluxo do n8n existe ainda). Ligar: update … set ativa = true (como postgres).
-- Intervalo de 1 h é o do cron antigo (ingest-mensageria-hourly); ajustar por fonte quando o fluxo existir.
insert into mkt_mensageria.fontes (chave, nome, ferramenta_id, ativa, intervalo_esperado)
select s.chave, s.nome, (select f.id from mkt_mensageria.ferramentas f where f.nome = s.ferramenta), false, interval '1 hour'
  from (values ('activecampaign', 'ActiveCampaign', 'ActiveCampaign'), ('unichat', 'Unichat', 'Unichat'),
               ('infobip', 'Infobip', 'Infobip'), ('sendflow', 'SendFlow', 'SendFlow'),
               ('cs_disparos', 'Disparos do CS (cs.disparos)', null)) s(chave, nome, ferramenta);

-- Chave de cada fonte: nasce no Vault (32 bytes aleatórios, hex). Idempotente: não troca chave existente.
-- Para configurar o n8n, o dono lê: select decrypted_secret from vault.decrypted_secrets where name = 'mkt_msg_fonte_<chave>';
do $vault$
declare c text;
begin
  for c in select f.chave from mkt_mensageria.fontes f loop
    if not exists (select 1 from vault.secrets where name = 'mkt_msg_fonte_' || c) then
      perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mkt_msg_fonte_' || c,
                                  'Chave da fonte ' || c || ' da Mensageria (API mkt_msg_api_receber; gerada no banco)');
    end if;
  end loop;
end
$vault$;

-- Vigia: um job por fonte, criado DESLIGADO (liga junto com a fonte, pelo trg_fonte). Falha = fonte atrasada.
-- ops.rotina: 1 falha abre (a checagem já espera 2× o intervalo), 1 ok fecha.
do $vigia$
declare
  c text;
  v_job bigint;
begin
  for c in select f.chave from mkt_mensageria.fontes f order by f.chave loop
    if exists (select 1 from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(c)) then
      raise exception '20261005o: job % já existe', mkt_mensageria.fonte_jobname(c);
    end if;
    v_job := cron.schedule(mkt_mensageria.fonte_jobname(c), '*/30 * * * *',
                           format('select mkt_mensageria.vigiar_fonte(%L)', c));
    perform cron.alter_job(v_job, active := false);
    insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
    values (mkt_mensageria.fonte_jobname(c), 1, interval '3 hours', 1, interval '30 minutes', 'manual');
    insert into ops.rotina_estado (jobname) values (mkt_mensageria.fonte_jobname(c)) on conflict do nothing;
  end loop;
  -- Retenção das recusas: diário, 04:17 UTC. Mais de 26 h sem sucesso = alerta.
  if exists (select 1 from cron.job j where j.jobname = 'mensageria-recusas-expurgo') then
    raise exception '20261005o: job mensageria-recusas-expurgo já existe';
  end if;
  perform cron.schedule('mensageria-recusas-expurgo', '17 4 * * *', 'select mkt_mensageria.recusas_expurgar()');
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('mensageria-recusas-expurgo', 1, interval '26 hours', 1, interval '24 hours', 'manual');
  insert into ops.rotina_estado (jobname) values ('mensageria-recusas-expurgo') on conflict do nothing;
end
$vigia$;

-- ─── 7. P3: pausa o cron antigo (dependentes medidos em 05/10: só as views vw_mensageria_*; nenhuma função) ─────────
-- Estado antes (05/10/2026): jobid 26, '50 * * * *', active = true; ops.rotina silenciado_ate = null.
do $p3$
declare
  v_job bigint;
  v_ativo boolean;
begin
  select j.jobid, j.active into v_job, v_ativo from cron.job j where j.jobname = 'ingest-mensageria-hourly';
  if v_job is null then
    raise notice '20261005o: ingest-mensageria-hourly não existe: nada a pausar';
  elsif v_ativo then
    perform cron.alter_job(v_job, active := false);
  end if;
  update ops.rotina set silenciado_ate = 'infinity' where jobname = 'ingest-mensageria-hourly';
end
$p3$;

-- ─── 8. Funções públicas (RPC) ───────────────────────────────────────────────────────────────────────────────────────

-- Lista do período: igual à 20261005n + custo estimado, custo_fonte, campanha e pendências v2. Só ACRESCENTA campos.
-- Projeto em left join (linha da API pode vir sem projeto). Contrato em 20261005o.explain.md.
create or replace function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                                          p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, d.campanha, ce.centavos as custo_estimado,
             case when d.custo_centavos is not null then 'real'
                  when ce.centavos is not null then 'estimado'
                  when not ce.tem_preco then 'sem_preco' end as custo_fonte,
             mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos, ce.centavos,
                                          ce.tem_preco) as pendencias
        from mkt_mensageria.disparos d
        cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em, d.entregues,
                                                         d.tamanho_lista) ce
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias),
                 'campanha', b.campanha, 'custo_estimado_centavos', b.custo_estimado, 'custo_fonte', b.custo_fonte)
               order by b.enviado_em desc, b.id desc)
          from pagina b
          left join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)),
                 'custo_estimado_centavos', sum(b.custo_estimado) filter (where b.custo_centavos is null),
                 'com_estimativa', count(*) filter (where b.custo_centavos is null and b.custo_estimado is not null),
                 'custo_total_centavos', sum(coalesce(b.custo_centavos, b.custo_estimado)),
                 'sem_preco', count(*) filter (where 'sem_preco' = any(b.pendencias)),
                 'sem_projeto', count(*) filter (where 'sem_projeto' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo,
                 'custo_estimado_centavos', c.estimado, 'custo_total_centavos', c.total, 'sem_preco', c.sem_preco,
                 'sem_projeto', c.sem_projeto)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo,
                       count(*) filter (where 'sem_custo' = any(b.pendencias)) as sem_custo,
                       sum(b.custo_estimado) filter (where b.custo_centavos is null) as estimado,
                       sum(coalesce(b.custo_centavos, b.custo_estimado)) as total,
                       count(*) filter (where 'sem_preco' = any(b.pendencias)) as sem_preco,
                       count(*) filter (where 'sem_projeto' = any(b.pendencias)) as sem_projeto
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Igual à 20261005n + linha de origem 'api': só projeto, tipo e custo mudam aqui (o resto vem da fonte).
create or replace function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
  v_origem text;
  v_canal_api text;
  v_arq timestamptz;
  v_sigla text;
  v_proj bigint;
  v_tipo text;
  v_custo bigint;
  e jsonb := '[]'::jsonb;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;

  if v_id is not null then
    select d.origem, d.canal, d.arquivado_em into v_origem, v_canal_api, v_arq
      from mkt_mensageria.disparos d where d.id = v_id for update;
    if v_origem = 'api' then
      if v_arq is not null then
        return jsonb_build_object('ok', false, 'msg', 'Disparo arquivado: não pode ser editado.');
      end if;
      v_sigla := upper(btrim(coalesce(p ->> 'projeto', '')));
      if v_sigla = '' then
        e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
      else
        select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
        if v_proj is null then
          e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
        end if;
      end if;
      v_tipo := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
      if v_canal_api = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
      elsif v_canal_api <> 'whatsapp_api' and v_tipo is not null then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
      end if;
      v_custo := mkt_mensageria.inteiro(p ->> 'custo_centavos');
      if v_custo < 0 then
        e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
      end if;
      if jsonb_array_length(e) > 0 then
        return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
      end if;
      update mkt_mensageria.disparos d
         set projeto_id = v_proj, tipo = v_tipo, custo_centavos = v_custo::int,
             retorno_em = case when d.custo_centavos is distinct from v_custo::int then now() else d.retorno_em end
       where d.id = v_id;
      return jsonb_build_object('ok', true, 'id', v_id, 'campos', jsonb_build_array('projeto', 'tipo', 'custo_centavos'),
        'msg', 'Disparo da integração salvo: aqui mudam só projeto, tipo e custo; o resto vem da fonte.');
    end if;
  end if;

  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null and d.origem <> 'api';
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Igual à 20261005n + recusa linha da API (o retorno vem da fonte) + pendências v2 (com o custo estimado).
create or replace function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                                 p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
  v_origem text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista, d.origem into v_tam, v_origem
    from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if v_origem = 'api' then
    return jsonb_build_object('ok', false, 'msg',
      'Disparo da integração: o retorno vem da fonte. Projeto, tipo e custo se editam no próprio disparo.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
    'pendencias', (select to_jsonb(mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos,
                                                                ce.centavos, ce.tem_preco))
                     from mkt_mensageria.disparos d
                     cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em,
                                                                      d.entregues, d.tamanho_lista) ce
                    where d.id = p_id));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Igual à 20261005n + por_api; por_nome cai para 'api:<fonte>' quando a mudança veio da integração.
create or replace function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', coalesce(pf.nome, h.por_api),
             'por_api', h.por_api, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- Igual à 20261005n + limpa o payload das recusas do mesmo (fonte, id_externo). Retorno ganha recusas_limpas.
create or replace function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
  v_rec integer := 0;
  v_sis text;
  v_ext text;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  select d.origem_sistema, d.id_externo into v_sis, v_ext from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end,
         anonimizado_em = coalesce(d.anonimizado_em, now())
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  if v_ext is not null then
    update mkt_mensageria.recusas r
       set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
           anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
     where r.fonte = v_sis and r.id_externo = v_ext and r.anonimizado_em is null;
    get diagnostics v_rec = row_count;
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist, 'recusas_limpas', v_rec),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist,
                            'recusas_limpas', v_rec);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- LGPD de uma recusa que não virou disparo (só admin/dev, como a de disparo). Troca o payload; fica o motivo.
create function public.mkt_msg_anonimizar_recusa(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_n integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
         anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
   where r.id = p_id and r.anonimizado_em is null;
  get diagnostics v_n = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Recusa não encontrada ou já anonimizada.');
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Recusa anonimizada.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_anonimizar_recusa(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_recusa(bigint, text) to authenticated;

-- Preços: todos (inclusive anulados, para a trilha), com o vigente de hoje marcado.
create function public.mkt_msg_precos_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'precos', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'ferramenta_id', p.ferramenta_id, 'ferramenta', f.nome, 'canal', p.canal, 'tipo', p.tipo,
             'base_cobranca', p.base_cobranca, 'preco_centavos', p.preco_centavos, 'vigente_desde', p.vigente_desde,
             'obs', p.obs, 'criado_em', p.criado_em, 'criado_por_nome', pc.nome,
             'anulado_em', p.anulado_em, 'anulado_por_nome', pa.nome, 'anulado_motivo', p.anulado_motivo,
             'vigente_hoje', p.anulado_em is null and p.id = (mkt_mensageria.custo_estimado(p.ferramenta_id, p.canal, p.tipo,
                                                               now(), 0, 0)).preco_id)
           order by lower(f.nome), p.canal, p.tipo nulls first, p.vigente_desde desc, p.id desc), '[]'::jsonb)
      from mkt_mensageria.precos p
      join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id
      left join public.perfis pc on pc.id = p.criado_por
      left join public.perfis pa on pa.id = p.anulado_por));
end
$$;
revoke all on function public.mkt_msg_precos_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_precos_listar() to authenticated;

-- Cadastra uma vigência. Não edita (com "id" recusa). Campos: ferramenta_id, canal, tipo (só whatsapp_api, e lá
-- obrigatório), base_cobranca (entregues|tamanho_lista|mensalidade), preco_centavos ("8", "6,5", 0.36 → até 4 casas;
-- mensalidade = 0), vigente_desde (aaaa-mm-dd), obs?. Nenhum campo de regra tem valor assumido: faltou = erro.
create function public.mkt_msg_preco_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_base text := lower(btrim(coalesce(p ->> 'base_cobranca', '')));
  v_preco_txt text := replace(btrim(coalesce(p ->> 'preco_centavos', '')), ',', '.');
  v_preco numeric;
  v_vig_txt text := btrim(coalesce(p ->> 'vigente_desde', ''));
  v_vig date;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_id bigint;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do preço ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null then
    return jsonb_build_object('ok', false, 'msg', 'Preço não se edita: anule o errado (com motivo) e cadastre outro.');
  end if;
  if v_ferr_txt ~ '^[0-9]{1,18}$' then
    select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
  end if;
  if v_ferr is null then e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.'); end if;
  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  elsif v_canal = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal <> 'whatsapp_api' and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  end if;
  if v_base not in ('entregues', 'tamanho_lista', 'mensalidade') then
    e := e || jsonb_build_object('campo', 'base_cobranca', 'msg', 'Base de cobrança: por entregue, por tamanho da lista ou mensalidade.');
  end if;
  if v_preco_txt !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' then
    e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço em centavos, até 4 casas (ex.: 8 ou 6,5).');
  else
    v_preco := v_preco_txt::numeric;
    if v_preco > 100000 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço acima de R$ 1.000,00 por mensagem: confira.');
    elsif v_base = 'mensalidade' and v_preco <> 0 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg',
        'Na mensalidade o custo por disparo é 0: o valor mensal vai no cadastro da ferramenta.');
    end if;
  end if;
  if v_vig_txt ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    begin
      v_vig := v_vig_txt::date;
    exception when others then
      v_vig := null;
    end;
  end if;
  if v_vig is null or v_vig < date '2020-01-01' or v_vig > date '2100-12-31' then
    e := e || jsonb_build_object('campo', 'vigente_desde', 'msg', 'Vigente desde: data válida (aaaa-mm-dd).');
  end if;
  if length(v_obs) > 500 then e := e || jsonb_build_object('campo', 'obs', 'msg', 'Observação: até 500 caracteres.'); end if;
  if jsonb_array_length(e) > 0 then
    return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
  end if;
  begin
    insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs, criado_por)
    values (v_ferr, v_canal, v_tipo, v_base, v_preco, v_vig, v_obs, (select auth.uid()))
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg',
      'Já existe preço válido para esta ferramenta, canal e tipo com vigência em ' || to_char(v_vig, 'DD/MM/YYYY') || ': anule-o antes.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Preço cadastrado.', 'id', v_id);
end
$$;
revoke all on function public.mkt_msg_preco_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_salvar(jsonb) to authenticated;

create function public.mkt_msg_preco_anular(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anulação (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.precos set anulado_em = now(), anulado_por = (select auth.uid()), anulado_motivo = v_motivo
   where id = p_id and anulado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.precos where id = p_id) then 'Preço já anulado.' else 'Preço não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Preço anulado. O custo estimado dos disparos dessa vigência foi recalculado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_preco_anular(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_anular(bigint, text) to authenticated;

-- Porteiro barato da rota: confere fonte + chave ANTES de a rota ler o corpo (até 5 MB). Só service_role.
-- true = fonte cadastrada e chave certa (ativa ou não: a fonte desligada é recusada e registrada por api_receber).
create function public.mkt_msg_api_chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  return exists (select 1 from mkt_mensageria.fontes f where f.chave = v_fonte)
         and mkt_mensageria.chave_ok(v_fonte, p_chave);
end
$$;
revoke all on function public.mkt_msg_api_chave_ok(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_chave_ok(text, text) to service_role;

-- Recusas para a tela (só admin/dev): SEM o payload. Mais recentes primeiro, até 500.
create function public.mkt_msg_recusas_listar(p_fonte text default null, p_limite integer default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := nullif(btrim(coalesce(p_fonte, '')), '');
  v_lim integer := least(greatest(coalesce(p_limite, 200), 1), 500);
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'limite', v_lim, 'recusas', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'fonte', r.fonte, 'execucao_id', r.execucao_id, 'posicao', r.posicao, 'id_externo', r.id_externo,
             'motivo', r.motivo, 'criado_em', r.criado_em, 'anonimizada', r.anonimizado_em is not null,
             'anonimizado_em', r.anonimizado_em, 'expurgada', r.expurgado_em is not null)
           order by r.criado_em desc, r.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.recusas x
             where v_fonte is null or x.fonte = v_fonte
             order by x.criado_em desc, x.id desc limit v_lim) r));
end
$$;
revoke all on function public.mkt_msg_recusas_listar(text, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_recusas_listar(text, integer) to authenticated;

-- Recebe um lote da fonte (rota POST /api/mensageria/receber, com service_role). Só service_role executa.
-- Chave errada, fonte desconhecida ou inativa: {ok:false, erro:'nao_autorizado'} (a rota devolve 401 genérico).
-- Inativa com chave certa grava execução 'fonte_inativa'. Lote: array de até 1.000 itens; vazio = "rodei, nada novo".
create function public.mkt_msg_api_receber(p_fonte text, p_chave text, p_lote jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inicio timestamptz := clock_timestamp();
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  r jsonb;
  v_n integer;
  v_status text;
  v_exec bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if not v_ativa then
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'fonte_inativa', 'Fonte desligada em mkt_mensageria.fontes: lote não lido.');
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    v_n := case when jsonb_typeof(p_lote) = 'array' then jsonb_array_length(p_lote) end;
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'lote_invalido',
            case when v_n is null then 'Lote não é um array JSON.' else 'Lote de ' || v_n || ' itens (máximo 1.000).' end);
    return jsonb_build_object('ok', false, 'erro', case when v_n is null then 'lote_invalido' else 'lote_grande' end, 'limite', 1000);
  end if;

  r := mkt_mensageria.api_upsert(v_fonte, p_lote);
  v_status := case when (r ->> 'lidos')::int = (r ->> 'inseridos')::int + (r ->> 'atualizados')::int
                                              + (r ->> 'inalterados')::int + (r ->> 'recusados')::int
                   then 'ok' else 'inconsistente' end;
  insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status)
  values (v_fonte, v_inicio, clock_timestamp(), (r ->> 'lidos')::int, (r ->> 'inseridos')::int, (r ->> 'atualizados')::int,
          (r ->> 'inalterados')::int, (r ->> 'recusados')::int, v_status)
  returning id into v_exec;
  insert into mkt_mensageria.recusas (execucao_id, fonte, posicao, id_externo, motivo, payload)
  select v_exec, v_fonte, (x ->> 'posicao')::int, left(x ->> 'id_externo', 200), left(x ->> 'motivo', 500), x -> 'payload'
    from jsonb_array_elements(r -> 'recusas') x;
  return jsonb_build_object('ok', true, 'execucao_id', v_exec, 'status', v_status,
    'lidos', (r ->> 'lidos')::int, 'inseridos', (r ->> 'inseridos')::int, 'atualizados', (r ->> 'atualizados')::int,
    'inalterados', (r ->> 'inalterados')::int, 'recusados', (r ->> 'recusados')::int,
    'recusas', (select coalesce(jsonb_agg(x - 'payload'), '[]'::jsonb)
                  from (select x from jsonb_array_elements(r -> 'recusas') x limit 100) s));
end
$$;
revoke all on function public.mkt_msg_api_receber(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_receber(text, text, jsonb) to service_role;

-- Reconciliação diária: a fonte manda os id_externo que ela enviou no dia (São Paulo); grava quantos estão no log e
-- quais faltam (até 500). Mesma autenticação de api_receber; fonte inativa = nao_autorizado.
create function public.mkt_msg_api_reconciliar(p_fonte text, p_chave text, p_dia date, p_ids jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_fonte_qtd integer;
  v_log integer;
  v_falt_total integer;
  v_falt jsonb;
  v_id bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not v_ativa or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_dia is null or p_dia > v_hoje or p_dia < v_hoje - 400 then
    return jsonb_build_object('ok', false, 'erro', 'dia_invalido');
  end if;
  if p_ids is null or jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) > 20000 then
    return jsonb_build_object('ok', false, 'erro', 'ids_invalidos', 'limite', 20000);
  end if;
  with ids as (
    select distinct left(btrim(x), 200) as id from jsonb_array_elements_text(p_ids) x where btrim(x) <> ''
  ), falt as (
    select i.id from ids i
     where not exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = v_fonte and d.id_externo = i.id)
  )
  select (select count(*) from ids), (select count(*) from falt),
         (select coalesce(jsonb_agg(s.id order by s.id), '[]'::jsonb) from (select id from falt order by id limit 500) s)
    into v_fonte_qtd, v_falt_total, v_falt;
  select count(*) into v_log from mkt_mensageria.disparos d
   where d.enviado_em >= p_dia::timestamp at time zone 'America/Sao_Paulo'
     and d.enviado_em < (p_dia + 1)::timestamp at time zone 'America/Sao_Paulo'
     and d.origem_sistema = v_fonte and d.arquivado_em is null;
  insert into mkt_mensageria.reconciliacao (fonte, dia, contagem_fonte, contagem_log, faltantes_total, faltantes)
  values (v_fonte, p_dia, v_fonte_qtd, v_log, v_falt_total, v_falt)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'dia', p_dia, 'contagem_fonte', v_fonte_qtd, 'contagem_log', v_log,
                            'faltantes_total', v_falt_total, 'faltantes', v_falt);
end
$$;
revoke all on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) to service_role;

-- Saúde das integrações: uma linha por fonte. Atraso pela mesma regra do vigia (mkt_mensageria.fonte_atraso).
create function public.mkt_msg_integracoes_saude() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'agora', now(), 'fontes', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'chave', f.chave, 'nome', f.nome, 'ferramenta_id', f.ferramenta_id, 'ferramenta', fe.nome,
             'ativa', f.ativa, 'ativa_desde', f.ativa_desde,
             'intervalo_minutos', (extract(epoch from f.intervalo_esperado) / 60)::int,
             'ultima_execucao_em', ue.inicio, 'ultima_execucao_status', ue.status,
             'ultima_ok_em', a.ultima_ok_em,
             'atraso_minutos', (extract(epoch from a.atraso) / 60)::int, 'atrasada', a.atrasada,
             'execucoes_7d', s.execucoes, 'recusas_7d', s.recusas, 'inconsistentes_7d', s.inconsistentes,
             'negadas_7d', s.negadas,
             'chave_no_vault', exists (select 1 from vault.secrets v where v.name = 'mkt_msg_fonte_' || f.chave),
             'vigia_jobname', mkt_mensageria.fonte_jobname(f.chave),
             'ultima_reconciliacao', case when rc.id is not null then jsonb_build_object(
                'dia', rc.dia, 'contagem_fonte', rc.contagem_fonte, 'contagem_log', rc.contagem_log,
                'faltantes_total', rc.faltantes_total, 'em', rc.criado_em) end)
           order by f.chave), '[]'::jsonb)
      from mkt_mensageria.fontes f
      left join mkt_mensageria.ferramentas fe on fe.id = f.ferramenta_id
      cross join lateral mkt_mensageria.fonte_atraso(f.chave) a
      left join lateral (select e.inicio, e.status from mkt_mensageria.execucoes e
                          where e.fonte = f.chave order by e.inicio desc limit 1) ue on true
      left join lateral (select count(*) as execucoes, coalesce(sum(e.recusados), 0) as recusas,
                                count(*) filter (where e.status = 'inconsistente') as inconsistentes,
                                count(*) filter (where e.status in ('fonte_inativa', 'lote_invalido')) as negadas
                           from mkt_mensageria.execucoes e
                          where e.fonte = f.chave and e.inicio >= now() - interval '7 days') s on true
      left join lateral (select r.* from mkt_mensageria.reconciliacao r
                          where r.fonte = f.chave order by r.dia desc, r.id desc limit 1) rc on true));
end
$$;
revoke all on function public.mkt_msg_integracoes_saude() from public, anon, authenticated;
grant execute on function public.mkt_msg_integracoes_saude() to authenticated;

-- ─── 9. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  fn record;
  v_tela text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                         'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                         'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                         'mkt_msg_historico', 'mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa',
                         'mkt_msg_precos_listar', 'mkt_msg_preco_salvar', 'mkt_msg_preco_anular', 'mkt_msg_integracoes_saude',
                         'mkt_msg_recusas_listar'];
  v_api text[] := array['mkt_msg_api_receber', 'mkt_msg_api_reconciliar', 'mkt_msg_api_chave_ok'];
  v_admin text[] := array['mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa', 'mkt_msg_recusas_listar'];
begin
  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind in ('r', 'S') loop
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if (select c.relkind from pg_class c where c.oid = t::regclass) = 'r'
         and has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005o: % tem privilégio em %', r, t;
      end if;
    end loop;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005o: PUBLIC tem privilégio em %', t;
    end if;
    if (select c.relkind = 'r' and not c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005o: RLS desligada em %', t;
    end if;
  end loop;

  for fn in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (fn.proconfig @> array['search_path=""']) then
      raise exception '20261005o: % sem search_path vazio', fn.sig;
    end if;
    if has_function_privilege('anon', fn.sig, 'execute') then
      raise exception '20261005o: anon executa %', fn.sig;
    end if;
    if fn.proacl is null or exists (select 1 from aclexplode(fn.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005o: PUBLIC executa %', fn.sig;
    end if;
    if (fn.pronamespace = 'public'::regnamespace and fn.proname = any(v_tela)) <> has_function_privilege('authenticated', fn.sig, 'execute') then
      raise exception '20261005o: grant de authenticated errado em %', fn.sig;
    end if;
    if fn.proname = any(v_api) and not has_function_privilege('service_role', fn.sig, 'execute') then
      raise exception '20261005o: service_role não executa %', fn.sig;
    end if;
    if fn.pronamespace = 'public'::regnamespace and not fn.prosecdef then
      raise exception '20261005o: % deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.pronamespace = 'mkt_mensageria'::regnamespace and fn.prosecdef then
      raise exception '20261005o: interna % não deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.proname = any(v_tela) and not (fn.proname = any(v_admin))
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda mkt.pode_ver', fn.sig;
    end if;
    if fn.proname = any(v_admin) and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda gp_is_admin', fn.sig;
    end if;
    if fn.proname = any(v_api) and position('if coalesce(auth.role(), '''') <> ''service_role'' then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda de service_role', fn.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 20
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_tela || v_api)) <> 20 then
    raise exception '20261005o: esperava exatamente 20 funções public.mkt_msg_* (sobrecarga?)';
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria'
                and ((table_name = 'precos' and column_name in ('ferramenta_id', 'canal', 'tipo', 'base_cobranca', 'preco_centavos', 'vigente_desde'))
                  or (table_name = 'fontes' and column_name in ('ativa', 'intervalo_esperado', 'ferramenta_id'))
                  or (table_name = 'disparos' and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'projeto_id')))
                and column_default is not null) then
    raise exception '20261005o: coluna de regra com default';
  end if;
  if (select count(*) from mkt_mensageria.precos) <> 7
     or exists (select 1 from mkt_mensageria.precos p join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id where f.nome = 'Infobip') then
    raise exception '20261005o: seed de preços diferente do esperado (7 linhas, Infobip sem preço)';
  end if;
  if (select count(*) from mkt_mensageria.fontes where not ativa) <> 5 or (select count(*) from mkt_mensageria.fontes) <> 5 then
    raise exception '20261005o: seed de fontes diferente do esperado (5, todas desligadas)';
  end if;
  if (select count(*) from vault.secrets s join mkt_mensageria.fontes f on s.name = 'mkt_msg_fonte_' || f.chave) <> 5 then
    raise exception '20261005o: faltou chave no Vault';
  end if;
  if (select count(*) from cron.job j join mkt_mensageria.fontes f on j.jobname = mkt_mensageria.fonte_jobname(f.chave)
       where not j.active) <> 5
     or (select count(*) from ops.rotina o join mkt_mensageria.fontes f on o.jobname = mkt_mensageria.fonte_jobname(f.chave)) <> 5 then
    raise exception '20261005o: jobs do vigia das fontes (5 desligados + 5 em ops.rotina) diferente do esperado';
  end if;
  if not exists (select 1 from cron.job j join ops.rotina o using (jobname) where j.jobname = 'mensageria-recusas-expurgo' and j.active) then
    raise exception '20261005o: job de expurgo das recusas ausente (cron.job ativo + ops.rotina)';
  end if;
  if exists (select 1 from cron.job where jobname = 'ingest-mensageria-hourly' and active) then
    raise exception '20261005o: ingest-mensageria-hourly continua ativo';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação) ═══════════════════════════════════════════════════════════════════════════════════════
-- Só o cron antigo (P3), sem mexer no resto:
--   select cron.alter_job((select jobid from cron.job where jobname = 'ingest-mensageria-hourly'), active := true);
--   update ops.rotina set silenciado_ate = null where jobname = 'ingest-mensageria-hourly';
-- Desligar uma fonte sem deploy: update mkt_mensageria.fontes set ativa = false where chave = '<fonte>';
-- Tudo (exportar antes recusas/execucoes; disparos de origem api precisam de projeto antes de voltar o NOT NULL):
-- begin;
-- select cron.unschedule(j.jobname) from cron.job j where j.jobname like 'mensageria-fonte-%' or j.jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina_estado where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from vault.secrets where name like 'mkt\_msg\_fonte\_%';
-- drop function public.mkt_msg_api_receber(text, text, jsonb), public.mkt_msg_api_reconciliar(text, text, date, jsonb),
--   public.mkt_msg_integracoes_saude(), public.mkt_msg_precos_listar(), public.mkt_msg_preco_salvar(jsonb),
--   public.mkt_msg_preco_anular(bigint, text), public.mkt_msg_anonimizar_recusa(bigint, text),
--   public.mkt_msg_api_chave_ok(text, text), public.mkt_msg_recusas_listar(text, integer);
-- -- reaplicar da 20261005n: mkt_msg_disparos_listar, mkt_msg_disparo_salvar, mkt_msg_disparo_lancar_retorno,
-- --   mkt_msg_historico, mkt_msg_anonimizar_disparo, mkt_mensageria.trg_historico (create or replace)
-- drop table mkt_mensageria.recusas, mkt_mensageria.reconciliacao, mkt_mensageria.execucoes, mkt_mensageria.fontes,
--   mkt_mensageria.precos;
-- drop function mkt_mensageria.api_upsert(text, jsonb), mkt_mensageria.api_item(text, bigint, jsonb),
--   mkt_mensageria.chave_ok(text, text), mkt_mensageria.vigiar_fonte(text), mkt_mensageria.fonte_atraso(text),
--   mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean),
--   mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer), mkt_mensageria.fonte_jobname(text),
--   mkt_mensageria.trg_preco_anular(), mkt_mensageria.trg_fonte(), mkt_mensageria.trg_recusa_anonimizar(),
--   mkt_mensageria.recusas_expurgar();
-- alter table mkt_mensageria.historico drop column por_api;
-- alter table mkt_mensageria.disparos drop column campanha, drop column anonimizado_em, drop constraint disparos_projeto_fora_da_api;
-- alter table mkt_mensageria.disparos alter column projeto_id set not null;   -- falha se houver linha da API sem projeto
-- commit;

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito; chave nunca impressa) ═════
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projetos (2 siglas reais), ferramentas e a chave da fonte unichat (lida do Vault DENTRO da transação abortada).
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as proj1,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla1,
         (select pr.sigla from mkt.projetos pr order by pr.id offset 1 limit 1) as sigla2,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Unichat') as unichat,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Infobip') as infobip,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Ligue Lead') as liguelead,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Clint') as clint,
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_unichat') as chave;
grant all on _z_ref to public;
create temp table _z_ids (nome text primary key, id bigint) on commit drop;
grant all on _z_ids to public;
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
-- Como a rota chama: PostgREST com a service_role key (role service_role, claims role = service_role).
create function pg_temp.como_servico() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;
-- Item de lote da API (unichat, WhatsApp). p_extra sobrepõe/acrescenta campos.
create function pg_temp.item(p_id text, p_campanha text, p_extra jsonb default '{}') returns jsonb language sql as $f$
  select jsonb_build_object('id_externo', p_id, 'campanha', p_campanha, 'canal', 'whatsapp_api', 'tipo', 'marketing',
           'enviado_em', '2026-09-15T10:00:00-03:00', 'copy_texto', 'Copy ' || p_id, 'publico_lista', 'Lista ' || p_id,
           'tamanho_lista', 100, 'entregues', 90, 'lidas', 50) || p_extra
$f$;

-- ═══ BLOCO 1: segurança, preços, integração, tela, LGPD, vigia, P3 ═════════════════════════════════════════════════
-- S1/S2. anon e authenticated NÃO-admin: 42501 nas funções novas/alteradas; API: só service_role (admin também 42501)
do $s1$
declare
  c text;
  v_r text;
  v_tela text[] := array[
    'select public.mkt_msg_disparos_listar(current_date - 30, current_date)',
    'select public.mkt_msg_disparo_salvar(''{}'')',
    'select public.mkt_msg_disparo_lancar_retorno(1, 1, 1, 1, 0, 100)',
    'select public.mkt_msg_historico(''disparos'', ''1'')',
    'select public.mkt_msg_anonimizar_disparo(1, ''teste'')',
    'select public.mkt_msg_anonimizar_recusa(1, ''teste'')',
    'select public.mkt_msg_precos_listar()',
    'select public.mkt_msg_preco_salvar(''{}'')',
    'select public.mkt_msg_preco_anular(1, ''teste'')',
    'select public.mkt_msg_integracoes_saude()',
    'select public.mkt_msg_recusas_listar()'];
  v_api text[] := array[
    'select public.mkt_msg_api_receber(''unichat'', repeat(''a'', 64), ''[]'')',
    'select public.mkt_msg_api_reconciliar(''unichat'', repeat(''a'', 64), current_date, ''[]'')',
    'select public.mkt_msg_api_chave_ok(''unichat'', repeat(''a'', 64))'];
begin
  foreach v_r in array array['anon', 'authenticated'] loop
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000ff","role":"' || v_r || '"}', true);
    foreach c in array v_tela || v_api loop
      execute format('set local role %I', v_r);
      begin
        execute c;
        reset role;
        raise exception 'S1 FALHOU: % executou %', v_r, c;
      exception when insufficient_privilege then
        reset role;
      end;
    end loop;
  end loop;
  -- admin logado (authenticated) também não chama a API
  foreach c in array v_api loop
    perform pg_temp.como_admin();
    begin
      execute c;
      reset role;
      raise exception 'S2 FALHOU: admin (authenticated) executou %', c;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;
  -- postgres sem claims de service_role: a guarda interna recusa
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.mkt_msg_api_receber('unichat', repeat('a', 64), '[]');
    raise exception 'S2 FALHOU: api_receber sem role service_role passou';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.ok('S1', 'anon e authenticated não-admin: 42501 em 11 funções de tela + 3 de API');
  perform pg_temp.ok('S2', 'admin logado: 42501 na API; postgres sem claim service_role: 42501 (guarda interna)');
end
$s1$;

-- S3. Tabelas novas: sem privilégio para anon/authenticated/service_role; select direto como service_role = 42501
do $s3$
declare
  r text;
  t text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach t in array array['precos', 'fontes', 'execucoes', 'recusas', 'reconciliacao'] loop
      if has_table_privilege(r, 'mkt_mensageria.' || t, 'select, insert, update, delete, truncate') then
        raise exception 'S3 FALHOU: % tem privilégio em %', r, t;
      end if;
    end loop;
    execute format('set local role %I', r);
    begin
      perform 1 from mkt_mensageria.fontes limit 1;
      reset role;
      raise exception 'S3 FALHOU: % leu mkt_mensageria.fontes direto', r;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;
  perform pg_temp.ok('S3', 'precos/fontes/execucoes/recusas/reconciliacao: sem privilégio (anon, authenticated, service_role); select direto = 42501');
end
$s3$;

-- P1. Preços: validações de mkt_msg_preco_salvar e imutabilidade
select pg_temp.como_admin();
do $p1$
declare
  r jsonb;
  v_base jsonb := jsonb_build_object('ferramenta_id', (select unichat from pg_temp._z_ref), 'canal', 'whatsapp_api',
                                     'base_cobranca', 'entregues', 'vigente_desde', '2026-09-01');
begin
  r := public.mkt_msg_preco_salvar(v_base || '{"preco_centavos":"40"}');
  if (r ->> 'ok')::boolean or r ->> 'msg' <> 'Na API do WhatsApp, informe o tipo: utility ou marketing.' then
    raise exception 'P1 FALHOU: whatsapp sem tipo: %', r;
  end if;
  r := public.mkt_msg_preco_salvar(jsonb_build_object('ferramenta_id', (select activecampaign from pg_temp._z_ref), 'canal', 'email',
                                   'base_cobranca', 'mensalidade', 'preco_centavos', 5, 'vigente_desde', '2026-09-01'));
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Na mensalidade o custo por disparo é 0%' then
    raise exception 'P1 FALHOU: mensalidade com preço: %', r;
  end if;
  r := public.mkt_msg_preco_salvar(v_base || '{"tipo":"marketing"}');
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Preço em centavos%' then
    raise exception 'P1 FALHOU: sem preço não pode virar 0: %', r;
  end if;
  r := public.mkt_msg_preco_salvar(v_base || '{"tipo":"marketing","preco_centavos":"40","id":"1"}');
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Preço não se edita%' then
    raise exception 'P1 FALHOU: edição de preço: %', r;
  end if;
  r := public.mkt_msg_preco_salvar(v_base || '{"tipo":"marketing","preco_centavos":"40,5"}');
  if not (r ->> 'ok')::boolean then raise exception 'P1 FALHOU: salvar 40,5: %', r; end if;
  insert into pg_temp._z_ids values ('preco_set', (r ->> 'id')::bigint);
  r := public.mkt_msg_preco_salvar(v_base || '{"tipo":"marketing","preco_centavos":"41"}');
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Já existe preço válido%' then
    raise exception 'P1 FALHOU: vigência duplicada: %', r;
  end if;
  if (select count(*) from jsonb_array_elements(public.mkt_msg_precos_listar() -> 'precos') x where (x ->> 'vigente_hoje')::boolean) <> 5 then
    raise exception 'P1 FALHOU: vigentes hoje ≠ 5 (Unichat utility 07-24, Unichat marketing 09-01, LigueLead, AC, SendFlow): %',
      public.mkt_msg_precos_listar();
  end if;
  perform pg_temp.ok('P1', 'preco_salvar: whatsapp sem tipo, mensalidade ≠ 0, preço vazio, edição e vigência duplicada recusados; 40,5 aceito; 5 vigentes hoje');
end
$p1$;
reset role;
do $p1b$
begin
  begin
    update mkt_mensageria.precos set preco_centavos = 1 where id = (select id from pg_temp._z_ids where nome = 'preco_set');
    raise exception 'P1b FALHOU: UPDATE de preço passou';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from mkt_mensageria.precos where id = (select id from pg_temp._z_ids where nome = 'preco_set');
    raise exception 'P1b FALHOU: DELETE de preço passou';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into mkt_mensageria.precos (ferramenta_id, canal, base_cobranca, preco_centavos, vigente_desde)
    values ((select clint from pg_temp._z_ref), 'ligacao', 'entregues', 1, null);
    raise exception 'P1b FALHOU: vigência nula aceita';
  exception when not_null_violation then null;
  end;
  perform pg_temp.ok('P1b', 'precos: UPDATE e DELETE diretos = 42501; vigência nula = 23502 (sem default)');
end
$p1b$;

-- P2. Custo estimado por data, real prevalece, sem preço, mensalidade, grupo sem sem_retorno
select pg_temp.como_admin();
do $p2$
declare
  r jsonb;
  v_ac bigint := (select activecampaign from pg_temp._z_ref);
  v_base jsonb := jsonb_build_object('projeto', (select sigla1 from pg_temp._z_ref), 'copy_texto', 'Copy do ensaio',
                    'publico_lista', 'Lista do ensaio', 'tamanho_lista', 100, 'disparado_por', 'Ensaio');
  n text;
  x jsonb;
  function_ok boolean;
begin
  -- A/B/C: Unichat marketing, 100 entregues, em 3 vigências (07-01 36 · 07-24 36 · 09-01 40,5)
  foreach n in array array['A:2026-07-10T10:00', 'B:2026-08-10T10:00', 'C:2026-09-10T10:00'] loop
    r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', split_part(n, ':', 2) || ':' || split_part(n, ':', 3),
           'canal', 'whatsapp_api', 'tipo', 'marketing', 'ferramenta_id', (select unichat from pg_temp._z_ref),
           'entregues', 100, 'lidas', 40));
    if not (r ->> 'ok')::boolean then raise exception 'P2 FALHOU: salvar %: %', n, r; end if;
    insert into pg_temp._z_ids values (split_part(n, ':', 1), (r ->> 'id')::bigint);
  end loop;
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T10:00', 'canal', 'sms',
         'ferramenta_id', (select infobip from pg_temp._z_ref), 'entregues', 90, 'lidas', 0));
  insert into pg_temp._z_ids values ('D_infobip', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T11:00', 'canal', 'email', 'ferramenta_id', v_ac));
  insert into pg_temp._z_ids values ('E_email', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T12:00', 'canal', 'whatsapp_api',
         'tipo', 'utility', 'ferramenta_id', (select unichat from pg_temp._z_ref)));
  insert into pg_temp._z_ids values ('F_sem_entregues', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T13:00', 'canal', 'grupo',
         'ferramenta_id', (select sendflow from pg_temp._z_ref)));
  insert into pg_temp._z_ids values ('G_grupo', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T14:00', 'canal', 'whatsapp_api',
         'tipo', 'marketing', 'ferramenta_id', (select unichat from pg_temp._z_ref), 'entregues', 10, 'lidas', 5, 'custo_centavos', 500));
  insert into pg_temp._z_ids values ('H_real', (r ->> 'id')::bigint);
  r := public.mkt_msg_disparo_salvar(v_base || jsonb_build_object('enviado_em', '2026-09-11T15:00', 'canal', 'sms',
         'ferramenta_id', (select liguelead from pg_temp._z_ref), 'entregues', 80, 'lidas', 10));
  insert into pg_temp._z_ids values ('I_liguelead', (r ->> 'id')::bigint);
  if (select count(*) from pg_temp._z_ids where id is null) > 0 then raise exception 'P2 FALHOU: algum salvar falhou'; end if;

  r := public.mkt_msg_disparos_listar(date '2026-07-01', date '2026-09-30');
  -- esperado por nome: custo_estimado_centavos, custo_fonte, pendencias
  for n, x in select i.nome, jsonb_build_object('est', l -> 'custo_estimado_centavos', 'fonte', l -> 'custo_fonte', 'pend', l -> 'pendencias')
                from jsonb_array_elements(r -> 'linhas') l join pg_temp._z_ids i on i.id = (l ->> 'id')::bigint loop
    if x <> (case n
         when 'A' then '{"est":3600,"fonte":"estimado","pend":[]}'::jsonb
         when 'B' then '{"est":3600,"fonte":"estimado","pend":[]}'::jsonb
         when 'C' then '{"est":4050,"fonte":"estimado","pend":[]}'::jsonb
         when 'D_infobip' then '{"est":null,"fonte":"sem_preco","pend":["sem_custo","sem_preco"]}'::jsonb
         when 'E_email' then '{"est":0,"fonte":"estimado","pend":["sem_retorno"]}'::jsonb
         when 'F_sem_entregues' then '{"est":null,"fonte":null,"pend":["sem_custo","sem_retorno"]}'::jsonb
         when 'G_grupo' then '{"est":0,"fonte":"estimado","pend":[]}'::jsonb
         when 'H_real' then '{"est":405,"fonte":"real","pend":[]}'::jsonb
         when 'I_liguelead' then '{"est":650,"fonte":"estimado","pend":[]}'::jsonb end) then
      raise exception 'P2 FALHOU: % veio %', n, x;
    end if;
  end loop;
  if (r -> 'totais' ->> 'qtd')::int <> 9 or (r -> 'totais' ->> 'custo_centavos')::int <> 500
     or (r -> 'totais' ->> 'custo_estimado_centavos')::int <> 3600 + 3600 + 4050 + 650
     or (r -> 'totais' ->> 'custo_total_centavos')::int <> 3600 + 3600 + 4050 + 650 + 500
     or (r -> 'totais' ->> 'sem_preco')::int <> 1 or (r -> 'totais' ->> 'sem_custo')::int <> 2
     or (r -> 'totais' ->> 'sem_projeto')::int <> 0 or (r -> 'totais' ->> 'com_estimativa')::int <> 6 then
    raise exception 'P2 FALHOU: totais %', r -> 'totais';
  end if;
  -- campos antigos continuam (só acréscimo)
  if not ((r -> 'linhas' -> 0) ?& array['id', 'enviado_em', 'projeto_id', 'projeto', 'canal', 'ferramenta_id', 'ferramenta',
          'numero_id', 'numero', 'tipo', 'copy_texto', 'copy_link', 'publico_lista', 'publico_origem', 'tamanho_lista',
          'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'disparado_por', 'retorno_em', 'origem',
          'origem_sistema', 'id_externo', 'importacao_id', 'atualizado_em', 'pendencias'])
     or not ((r -> 'totais') ?& array['qtd', 'tamanho', 'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos',
          'com_custo', 'sem_custo', 'sem_retorno', 'conferir_zero_leitura'])
     or not ((r -> 'por_canal' -> 0) ?& array['canal', 'qtd', 'tamanho', 'entregues', 'lidas', 'cliques', 'falhas',
          'custo_centavos', 'sem_custo']) then
    raise exception 'P2 FALHOU: campo antigo sumiu do retorno de listar';
  end if;
  -- anula a vigência 09-01: C volta para 36 (vigência 07-24)
  r := public.mkt_msg_preco_anular((select id from pg_temp._z_ids where nome = 'preco_set'), 'Ensaio: preço digitado errado');
  if not (r ->> 'ok')::boolean then raise exception 'P2 FALHOU: anular: %', r; end if;
  r := public.mkt_msg_preco_anular((select id from pg_temp._z_ids where nome = 'preco_set'), 'de novo');
  if r ->> 'msg' <> 'Preço já anulado.' then raise exception 'P2 FALHOU: anular 2x: %', r; end if;
  r := public.mkt_msg_disparos_listar(date '2026-09-10', date '2026-09-10');
  if (r -> 'linhas' -> 0 ->> 'custo_estimado_centavos')::int <> 3600 then
    raise exception 'P2 FALHOU: depois de anular, C deveria ser 3600: %', r -> 'linhas' -> 0;
  end if;
  -- lancar_retorno (manual) devolve pendências v2
  r := public.mkt_msg_disparo_lancar_retorno((select id from pg_temp._z_ids where nome = 'F_sem_entregues'), 50, 20, null, null, null);
  if r -> 'pendencias' <> '[]'::jsonb then raise exception 'P2 FALHOU: lancar_retorno pendências v2: %', r; end if;
  perform pg_temp.ok('P2', 'estimado por vigência: 07-10=3600, 08-10=3600, 09-10=4050 → anulada 09-01 → 3600; real 500 prevalece (estimado 405); Infobip sem_preco (nunca 0); e-mail/grupo mensalidade=0; sem entregues = sem estimativa + sem_retorno; grupo sem sem_retorno; SMS LigueLead 100×6,5=650; campos antigos intactos');
end
$p2$;
reset role;

-- I1. API: chave errada, fonte desconhecida, fonte inativa (grava execução), ativar liga o job do vigia, lote grande
do $i1$
declare
  r jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
  v_grande jsonb := (select jsonb_agg(pg_temp.item('G' || i, 'x')) from generate_series(1, 1001) i);
begin
  if v_chave !~ '^[0-9a-f]{64}$' then raise exception 'I1 FALHOU: chave da fonte não nasceu no Vault com 64 hex'; end if;
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', repeat('a', 64), jsonb_build_array(pg_temp.item('X1', 'x')));
  if r <> '{"ok":false,"erro":"nao_autorizado"}'::jsonb then reset role; raise exception 'I1 FALHOU: chave errada: %', r; end if;
  r := public.mkt_msg_api_receber('naoexiste', v_chave, '[]');
  if r <> '{"ok":false,"erro":"nao_autorizado"}'::jsonb then reset role; raise exception 'I1 FALHOU: fonte desconhecida: %', r; end if;
  r := public.mkt_msg_api_receber('sendflow', v_chave, '[]');   -- chave de outra fonte
  if r <> '{"ok":false,"erro":"nao_autorizado"}'::jsonb then reset role; raise exception 'I1 FALHOU: chave de outra fonte: %', r; end if;
  r := public.mkt_msg_api_receber('unichat', v_chave, '[]');     -- certa, mas fonte desligada
  if r <> '{"ok":false,"erro":"nao_autorizado"}'::jsonb then reset role; raise exception 'I1 FALHOU: fonte inativa: %', r; end if;
  reset role;
  if (select count(*) from mkt_mensageria.execucoes) <> 1
     or (select status from mkt_mensageria.execucoes) <> 'fonte_inativa' then
    raise exception 'I1 FALHOU: só a fonte inativa (chave certa) grava execução';
  end if;
  update mkt_mensageria.fontes set ativa = true where chave = 'unichat';
  if not (select active from cron.job where jobname = 'mensageria-fonte-unichat')
     or (select ativa_desde from mkt_mensageria.fontes where chave = 'unichat') is null then
    raise exception 'I1 FALHOU: ligar a fonte não ligou o job do vigia / ativa_desde';
  end if;
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, v_grande);
  reset role;
  if r ->> 'erro' <> 'lote_grande' or (select count(*) from mkt_mensageria.execucoes where status = 'lote_invalido') <> 1 then
    raise exception 'I1 FALHOU: lote de 1.001: %', r;
  end if;
  perform pg_temp.ok('I1', 'chave errada, fonte desconhecida, chave de outra fonte = nao_autorizado sem gravar; fonte inativa = nao_autorizado + execução fonte_inativa; ativar liga o job mensageria-fonte-unichat; 1.001 itens = lote_grande + execução lote_invalido');
end
$i1$;

-- I2. Lote: sigla casa / não casa / ambígua, recusa por regra, repetido no lote (vale o último); 2ª vez idempotente
do $i2$
declare
  r jsonb;
  r2 jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
  s1 text := (select sigla1 from pg_temp._z_ref);
  s2 text := (select sigla2 from pg_temp._z_ref);
  v_lote jsonb;
  v_hist bigint;
begin
  v_lote := jsonb_build_array(
    pg_temp.item('U5', 'primeira', '{"tamanho_lista":10,"entregues":5,"lidas":1}'),
    pg_temp.item('U1', '[' || lower(s1) || '] Lembrete aula'),
    pg_temp.item('U2', 'Sem sigla [1 BASE ANTIGA + 1 HORA]', '{"tipo":"utility","entregues":null,"lidas":null,"tamanho_lista":50}'),
    pg_temp.item('U3', '[' || s1 || ']', '{"entregues":10,"lidas":60}'),
    pg_temp.item('U4', '[' || s1 || '][' || s2 || '] ambígua'),
    pg_temp.item('U5', 'segunda', '{"tamanho_lista":20,"entregues":5,"lidas":1}'));
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, v_lote);
  reset role;
  if not (r ->> 'ok')::boolean or (r ->> 'lidos')::int <> 6 or (r ->> 'inseridos')::int <> 4 or (r ->> 'atualizados')::int <> 0
     or (r ->> 'inalterados')::int <> 0 or (r ->> 'recusados')::int <> 2 or r ->> 'status' <> 'ok' then
    raise exception 'I2 FALHOU: 1ª chamada: %', r;
  end if;
  if (select string_agg(x ->> 'posicao' || ':' || (x ->> 'id_externo'), ',' order by (x ->> 'posicao')::int)
        from jsonb_array_elements(r -> 'recusas') x) <> '1:U5,4:U3'
     or r -> 'recusas' -> 0 ->> 'motivo' not like 'id_externo repetido no lote%'
     or r -> 'recusas' -> 1 ->> 'motivo' <> 'lidas: Lidas (60) não pode passar de entregues (10).' then
    raise exception 'I2 FALHOU: recusas: %', r -> 'recusas';
  end if;
  if (select projeto_id from mkt_mensageria.disparos where id_externo = 'U1') <> (select pr.id from mkt.projetos pr where pr.sigla = s1)
     or (select projeto_id from mkt_mensageria.disparos where id_externo = 'U2') is not null
     or (select projeto_id from mkt_mensageria.disparos where id_externo = 'U4') is not null
     or (select tamanho_lista from mkt_mensageria.disparos where id_externo = 'U5') <> 20
     or (select disparado_por || '/' || origem || '/' || origem_sistema || '/' || campanha from mkt_mensageria.disparos where id_externo = 'U1')
        <> 'api:unichat/api/unichat/[' || lower(s1) || '] Lembrete aula' then
    raise exception 'I2 FALHOU: valores gravados';
  end if;
  if (select count(*) from mkt_mensageria.recusas) <> 2 or (select count(*) from mkt_mensageria.recusas where payload ? 'id_externo') <> 2 then
    raise exception 'I2 FALHOU: recusas não gravadas com payload';
  end if;
  if (select count(*) from mkt_mensageria.historico h join mkt_mensageria.disparos d on h.registro_id = d.id::text and h.tabela = 'disparos'
       where d.origem = 'api' and h.por is null and h.por_api = 'api:unichat' and h.acao = 'inserir') <> 4 then
    raise exception 'I2 FALHOU: histórico sem autor api:unichat';
  end if;
  select count(*) into v_hist from mkt_mensageria.historico;
  perform pg_temp.como_servico();
  r2 := public.mkt_msg_api_receber('unichat', v_chave, v_lote);
  reset role;
  if (r2 ->> 'inseridos')::int <> 0 or (r2 ->> 'atualizados')::int <> 0 or (r2 ->> 'inalterados')::int <> 4
     or (r2 ->> 'recusados')::int <> 2 or (select count(*) from mkt_mensageria.historico) <> v_hist
     or (select count(*) from mkt_mensageria.disparos where origem = 'api') <> 4 then
    raise exception 'I2 FALHOU: 2ª chamada não idempotente: %', r2;
  end if;
  perform pg_temp.ok('I2', '6 itens → 4 inseridos, 2 recusados (repetido no lote, lidas>entregues); sigla minúscula casa; sem sigla e 2 siglas = projeto nulo; repetido vale o último (tamanho 20); histórico por=null, por_api=api:unichat');
  perform pg_temp.ok('I2b', '2ª chamada igual: 0 inseridos, 0 atualizados, 4 inalterados, 2 recusados; histórico sem linha nova (UPDATE só quando muda)');
end
$i2$;

-- I3. NULL da fonte não apaga; mudança real atualiza (retorno_em + histórico 'alterar' api); listar mostra sem_projeto
do $i3$
declare
  r jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
begin
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, jsonb_build_array(
         jsonb_build_object('id_externo', 'U1', 'entregues', null, 'lidas', null, 'copy_texto', null),
         jsonb_build_object('id_externo', 'U2', 'entregues', 40, 'lidas', 20)));
  reset role;
  if (r ->> 'inalterados')::int <> 1 or (r ->> 'atualizados')::int <> 1 or (r ->> 'recusados')::int <> 0 then
    raise exception 'I3 FALHOU: %', r;
  end if;
  if (select entregues || '/' || lidas || '/' || copy_texto from mkt_mensageria.disparos where id_externo = 'U1') <> '90/50/Copy U1' then
    raise exception 'I3 FALHOU: NULL da fonte apagou valor de U1';
  end if;
  if (select entregues || '/' || lidas || '/' || (retorno_em is not null)::text from mkt_mensageria.disparos where id_externo = 'U2') <> '40/20/true'
     or not exists (select 1 from mkt_mensageria.historico h join mkt_mensageria.disparos d on h.registro_id = d.id::text
                     where d.id_externo = 'U2' and h.acao = 'alterar' and h.por_api = 'api:unichat') then
    raise exception 'I3 FALHOU: atualização de U2';
  end if;
  perform pg_temp.como_admin();
  r := public.mkt_msg_disparos_listar(date '2026-09-15', date '2026-09-15');
  reset role;
  if (r -> 'totais' ->> 'sem_projeto')::int <> 3 or (r -> 'totais' ->> 'qtd')::int <> 4
     or (select count(*) from jsonb_array_elements(r -> 'linhas') l where l -> 'projeto' = 'null'::jsonb and l -> 'pendencias' ? 'sem_projeto') <> 3 then
    raise exception 'I3 FALHOU: listar sem_projeto: %', r -> 'totais';
  end if;
  perform pg_temp.ok('I3', 'item só com id e nulos: U1 intacto (90/50/copy); U2 entregues 40 → atualizado, retorno_em carimbado, histórico alterar por api:unichat; listar traz as 3 sem projeto (U2, U4, U5; left join) com pendência sem_projeto');
end
$i3$;

-- T1. Tela em linha da API: só projeto/tipo/custo; lançar retorno recusado; a API não desfaz o que a tela corrigiu; arquivada não volta
do $t1$
declare
  r jsonb;
  v_u2 bigint := (select id from mkt_mensageria.disparos where id_externo = 'U2');
  v_u4 bigint := (select id from mkt_mensageria.disparos where id_externo = 'U4');
  v_chave text := (select chave from pg_temp._z_ref);
  s1 text := (select sigla1 from pg_temp._z_ref);
begin
  perform pg_temp.como_admin();
  r := public.mkt_msg_disparo_salvar(jsonb_build_object('id', v_u2, 'projeto', s1, 'tipo', 'marketing', 'custo_centavos', 777,
                                     'copy_texto', 'TENTATIVA DE MUDAR', 'tamanho_lista', 1));
  if not (r ->> 'ok')::boolean then reset role; raise exception 'T1 FALHOU: salvar linha api: %', r; end if;
  r := public.mkt_msg_disparo_salvar(jsonb_build_object('id', v_u2, 'projeto', s1, 'tipo', null, 'custo_centavos', 1));
  if (r ->> 'ok')::boolean then reset role; raise exception 'T1 FALHOU: whatsapp sem tipo aceito na linha api'; end if;
  r := public.mkt_msg_disparo_lancar_retorno(v_u2, 1, 1, 1, 1, 1);
  if (r ->> 'ok')::boolean or r ->> 'msg' not like 'Disparo da integração%' then reset role; raise exception 'T1 FALHOU: lancar_retorno em linha api: %', r; end if;
  r := public.mkt_msg_disparo_arquivar(v_u4, 'Ensaio: duplicado');
  reset role;
  if (select projeto_id || '/' || tipo || '/' || custo_centavos || '/' || copy_texto || '/' || tamanho_lista from mkt_mensageria.disparos where id = v_u2)
     <> (select pr.id from mkt.projetos pr where pr.sigla = s1) || '/marketing/777/Copy U2/50' then
    raise exception 'T1 FALHOU: linha api após a tela';
  end if;
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, jsonb_build_array(
         jsonb_build_object('id_externo', 'U2', 'campanha', 'sem sigla', 'tipo', 'utility', 'custo_centavos', 100),
         pg_temp.item('U4', 'volta?')));
  reset role;
  if (select projeto_id || '/' || tipo || '/' || custo_centavos from mkt_mensageria.disparos where id = v_u2)
       <> (select pr.id from mkt.projetos pr where pr.sigla = s1) || '/marketing/777'
     or (select arquivado_em is null from mkt_mensageria.disparos where id = v_u4)
     or (r ->> 'atualizados')::int <> 1 or (r ->> 'inalterados')::int <> 1 then
    raise exception 'T1 FALHOU: API desfez correção da tela ou ressuscitou arquivada: %', r;
  end if;
  perform pg_temp.ok('T1', 'linha api pela tela: muda só projeto/tipo/custo (copy e tamanho ignorados); lancar_retorno recusado; reenvio da API não desfaz projeto/tipo/custo (só a campanha mudou); arquivada fica arquivada');
end
$t1$;

-- T2. Manual continua exigindo projeto (RPC e CHECK); importação sem mudança
do $t2$
declare r jsonb;
begin
  perform pg_temp.como_admin();
  r := public.mkt_msg_disparo_salvar(jsonb_build_object('enviado_em', '2026-09-20T10:00', 'canal', 'email',
         'ferramenta_id', (select activecampaign from pg_temp._z_ref), 'copy_texto', 'c', 'publico_lista', 'l',
         'tamanho_lista', 1, 'disparado_por', 'Ensaio'));
  reset role;
  if (r ->> 'ok')::boolean or r ->> 'msg' <> 'Escolha o projeto.' then raise exception 'T2 FALHOU: manual sem projeto: %', r; end if;
  begin
    insert into mkt_mensageria.disparos (enviado_em, canal, ferramenta_id, copy_texto, publico_lista, tamanho_lista, disparado_por)
    values (now(), 'email', (select activecampaign from pg_temp._z_ref), 'c', 'l', 1, 'x');
    raise exception 'T2 FALHOU: insert manual sem projeto passou';
  exception when check_violation then
    if sqlerrm not like '%disparos_projeto_fora_da_api%' then raise; end if;
  end;
  perform pg_temp.ok('T2', 'manual/planilha sem projeto: RPC "Escolha o projeto." e CHECK disparos_projeto_fora_da_api');
end
$t2$;

-- L1. LGPD: anonimizar disparo limpa recusas do mesmo id_externo; anonimizar recusa avulsa; UPDATE/DELETE direto = 42501
do $l1$
declare
  r jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
  v_u6 bigint;
  v_rec bigint := null;
begin
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, jsonb_build_array(pg_temp.item('U6', 'x', '{"publico_lista":null}')));
  r := public.mkt_msg_api_receber('unichat', v_chave, jsonb_build_array(pg_temp.item('U6', 'x', '{"publico_lista":"Fulano da Silva"}')));
  reset role;
  v_u6 := (select id from mkt_mensageria.disparos where id_externo = 'U6');
  if v_u6 is null or (select count(*) from mkt_mensageria.recusas where id_externo = 'U6') <> 1 then
    raise exception 'L1 FALHOU: preparo U6 %', r;
  end if;
  v_rec := (select id from mkt_mensageria.recusas where id_externo = 'U3' order by id limit 1);
  perform pg_temp.como_admin();
  r := public.mkt_msg_anonimizar_disparo(v_u6, 'Ensaio LGPD');
  if (r ->> 'recusas_limpas')::int <> 1 then reset role; raise exception 'L1 FALHOU: anonimizar_disparo: %', r; end if;
  r := public.mkt_msg_anonimizar_recusa(v_rec, 'Ensaio LGPD');
  if not (r ->> 'ok')::boolean then reset role; raise exception 'L1 FALHOU: anonimizar_recusa: %', r; end if;
  r := public.mkt_msg_anonimizar_recusa(v_rec, 'de novo');
  reset role;
  if (r ->> 'ok')::boolean then raise exception 'L1 FALHOU: anonimizar recusa 2x'; end if;
  if (select payload from mkt_mensageria.recusas where id_externo = 'U6') <> '{"anonimizado": true}'::jsonb
     or (select publico_lista from mkt_mensageria.disparos where id = v_u6) <> '[anonimizado]' then
    raise exception 'L1 FALHOU: conteúdo não anonimizado';
  end if;
  begin
    update mkt_mensageria.recusas set motivo = 'x' || motivo;
    raise exception 'L1 FALHOU: UPDATE em recusas passou';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from mkt_mensageria.execucoes;
    raise exception 'L1 FALHOU: DELETE em execucoes passou';
  exception when insufficient_privilege then null;
  end;
  begin
    update mkt_mensageria.execucoes set lidos = lidos;
    raise exception 'L1 FALHOU: UPDATE em execucoes passou';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from mkt_mensageria.fontes where chave = 'infobip';
    raise exception 'L1 FALHOU: DELETE em fontes passou';
  exception when insufficient_privilege then null;
  end;
  begin
    update mkt_mensageria.fontes set chave = 'outra' where chave = 'infobip';
    raise exception 'L1 FALHOU: chave da fonte mudou';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.ok('L1', 'anonimizar_disparo limpa a recusa do mesmo id_externo (recusas_limpas=1); anonimizar_recusa avulsa ok, 2ª vez recusada; UPDATE recusas, DELETE/UPDATE execucoes, DELETE fontes e troca de chave = 42501');
end
$l1$;

-- L2. Reenvio de disparo anonimizado: a fonte manda o dado pessoal de novo (2× no lote, para forçar uma recusa)
do $l2$
declare
  r jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
  v_lote jsonb := jsonb_build_array(pg_temp.item('U6', 'Fulano', '{"publico_lista":"Fulano da Silva","copy_texto":"Oi Fulano","entregues":99}'),
                                    pg_temp.item('U6', 'Fulano', '{"publico_lista":"Fulano da Silva","copy_texto":"Oi Fulano","entregues":99}'));
begin
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_receber('unichat', v_chave, v_lote);
  reset role;
  if (r ->> 'inalterados')::int <> 1 or (r ->> 'recusados')::int <> 1 or (r ->> 'atualizados')::int <> 0 then
    raise exception 'L2 FALHOU: %', r;
  end if;
  if (select publico_lista || '/' || copy_texto || '/' || entregues || '/' || (anonimizado_em is not null)::text
        from mkt_mensageria.disparos where id_externo = 'U6') <> '[anonimizado]/[anonimizado]/90/true' then
    raise exception 'L2 FALHOU: reenvio regravou disparo anonimizado';
  end if;
  if exists (select 1 from mkt_mensageria.recusas where payload::text like '%Fulano%')
     or (select payload from mkt_mensageria.recusas where id_externo = 'U6' order by id desc limit 1) <> '{"anonimizado": true}'::jsonb then
    raise exception 'L2 FALHOU: recusa guardou o dado de id anonimizado';
  end if;
  perform pg_temp.ok('L2', 'reenvio de U6 anonimizado com "Fulano da Silva": linha intacta ([anonimizado], métricas não mudam), 1 inalterado; a recusa (repetido no lote) gravou {"anonimizado":true}; nenhuma recusa contém "Fulano"');
end
$l2$;

-- X1. Retenção: payload de recusa com mais de 30 dias expurgado; recente intacto; listagem admin sem payload
do $x1$
declare
  r jsonb;
  v_n integer;
  v_velha bigint;
begin
  insert into mkt_mensageria.recusas (execucao_id, fonte, posicao, id_externo, motivo, payload, criado_em)
  values ((select max(id) from mkt_mensageria.execucoes), 'unichat', 1, 'VELHA', 'Ensaio: recusa antiga',
          '{"publico_lista":"Beltrano"}', now() - interval '31 days')
  returning id into v_velha;
  v_n := mkt_mensageria.recusas_expurgar();
  if v_n <> 1 or (select payload from mkt_mensageria.recusas where id = v_velha) <> '{"expurgado": true}'::jsonb
     or (select expurgado_em from mkt_mensageria.recusas where id = v_velha) is null
     or exists (select 1 from mkt_mensageria.recusas where id <> v_velha and expurgado_em is not null) then
    raise exception 'X1 FALHOU: expurgo (%)', v_n;
  end if;
  perform pg_temp.como_admin();
  r := public.mkt_msg_recusas_listar('unichat', 50);
  reset role;
  if r::text like '%payload%' or r::text like '%Beltrano%' or r::text like '%Fulano%'
     or not exists (select 1 from jsonb_array_elements(r -> 'recusas') x where (x ->> 'expurgada')::boolean and x ->> 'id_externo' = 'VELHA')
     or not exists (select 1 from jsonb_array_elements(r -> 'recusas') x where (x ->> 'anonimizada')::boolean) then
    raise exception 'X1 FALHOU: recusas_listar %', r;
  end if;
  if (select active from cron.job where jobname = 'mensageria-recusas-expurgo') is not true
     or (select n_falhas || '/' || janela from ops.rotina where jobname = 'mensageria-recusas-expurgo') <> '1/26:00:00' then
    raise exception 'X1 FALHOU: job de expurgo / ops.rotina';
  end if;
  perform pg_temp.ok('X1', 'recusa de 31 dias: payload → {"expurgado":true}, recentes intactas; recusas_listar (admin) sem payload, com expurgada/anonimizada; job diário mensageria-recusas-expurgo ativo e em ops.rotina (1 falha, 26 h)');
end
$x1$;

-- K1. Porteiro da rota: mkt_msg_api_chave_ok
do $k1$
declare
  v_chave text := (select chave from pg_temp._z_ref);
  a boolean; b boolean; c boolean; d boolean;
begin
  perform pg_temp.como_servico();
  a := public.mkt_msg_api_chave_ok('unichat', v_chave);
  b := public.mkt_msg_api_chave_ok('unichat', repeat('a', 64));
  c := public.mkt_msg_api_chave_ok('naoexiste', v_chave);
  d := public.mkt_msg_api_chave_ok('sendflow', v_chave);
  reset role;
  if not a or b or c or d then raise exception 'K1 FALHOU: % % % %', a, b, c, d; end if;
  perform pg_temp.ok('K1', 'api_chave_ok: certa=true; errada, fonte desconhecida e chave de outra fonte = false');
end
$k1$;

-- R1. Reconciliação: faltante achado; contagem do log do dia
do $r1$
declare
  r jsonb;
  v_chave text := (select chave from pg_temp._z_ref);
  v_log integer := (select count(*) from mkt_mensageria.disparos where origem_sistema = 'unichat' and arquivado_em is null
                     and (enviado_em at time zone 'America/Sao_Paulo')::date = date '2026-09-15');
begin
  perform pg_temp.como_servico();
  r := public.mkt_msg_api_reconciliar('unichat', v_chave, date '2026-09-15', '["U1","U2","X9"," U1 "]');
  reset role;
  if not (r ->> 'ok')::boolean or (r ->> 'contagem_fonte')::int <> 3 or r -> 'faltantes' <> '["X9"]'::jsonb
     or (r ->> 'contagem_log')::int <> v_log or (select count(*) from mkt_mensageria.reconciliacao) <> 1 then
    raise exception 'R1 FALHOU: % (log esperado %)', r, v_log;
  end if;
  perform pg_temp.ok('R1', 'reconciliar: 3 ids distintos, faltante ["X9"], contagem_log=' || v_log || ' (bate com a contagem direta)');
end
$r1$;

-- V1. Saúde e vigia: unichat em dia; fonte ligada há 3 h sem execução ok (intervalo 1 h) = atrasada e o job falha
do $v1$
declare
  r jsonb;
  u jsonb;
  s jsonb;
  v_erro text;
begin
  update mkt_mensageria.fontes set ativa = true where chave = 'sendflow';
  alter table mkt_mensageria.fontes disable trigger a_fonte;
  update mkt_mensageria.fontes set ativa_desde = now() - interval '3 hours' where chave = 'sendflow';
  alter table mkt_mensageria.fontes enable trigger a_fonte;
  perform pg_temp.como_admin();
  r := public.mkt_msg_integracoes_saude();
  reset role;
  select x into u from jsonb_array_elements(r -> 'fontes') x where x ->> 'chave' = 'unichat';
  select x into s from jsonb_array_elements(r -> 'fontes') x where x ->> 'chave' = 'sendflow';
  if jsonb_array_length(r -> 'fontes') <> 5 or not (u ->> 'ativa')::boolean or (u ->> 'atrasada')::boolean
     or u ->> 'ultima_ok_em' is null or (u ->> 'recusas_7d')::int < 3 or (u ->> 'negadas_7d')::int <> 2
     or not (u ->> 'chave_no_vault')::boolean or (u -> 'ultima_reconciliacao' ->> 'faltantes_total')::int <> 1
     or not (s ->> 'atrasada')::boolean or (s ->> 'atraso_minutos')::int < 179 then
    raise exception 'V1 FALHOU: saúde %', r;
  end if;
  if mkt_mensageria.vigiar_fonte('unichat') <> 'ok' or mkt_mensageria.vigiar_fonte('infobip') <> 'inativa' then
    raise exception 'V1 FALHOU: vigiar_fonte em dia/inativa';
  end if;
  begin
    perform mkt_mensageria.vigiar_fonte('sendflow');
    raise exception 'V1 FALHOU: sendflow atrasada não falhou';
  exception when raise_exception then
    get stacked diagnostics v_erro = message_text;
    if v_erro not like 'Mensageria: fonte sendflow sem execução ok há%' then raise; end if;
  end;
  update mkt_mensageria.fontes set ativa = false where chave = 'sendflow';
  if (select active from cron.job where jobname = 'mensageria-fonte-sendflow')
     or (select ativa_desde from mkt_mensageria.fontes where chave = 'sendflow') is not null then
    raise exception 'V1 FALHOU: desligar a fonte não desligou o job';
  end if;
  if (select n_falhas || '/' || k_ok || '/' || intervalo from ops.rotina where jobname = 'mensageria-fonte-unichat') <> '1/1/00:30:00'
     or (select command from cron.job where jobname = 'mensageria-fonte-unichat') <> 'select mkt_mensageria.vigiar_fonte(''unichat'')' then
    raise exception 'V1 FALHOU: cadastro no vigia';
  end if;
  perform pg_temp.ok('V1', 'saúde: 5 fontes; unichat em dia (recusas_7d, negadas_7d=2, chave no Vault, última reconciliação); sendflow ligada há 3 h sem ok = atrasada; vigiar_fonte: ok / inativa / erro "' || left(v_erro, 60) || '…"; desligar a fonte desliga o job; ops.rotina 1 falha/1 ok/30 min');
end
$v1$;

-- H1. Histórico pela tela mostra o autor da integração
do $h1$
declare
  r jsonb;
  v_u1 text := (select id from mkt_mensageria.disparos where id_externo = 'U1')::text;
begin
  perform pg_temp.como_admin();
  r := public.mkt_msg_historico('disparos', v_u1);
  reset role;
  if r -> 'itens' -> 0 ->> 'por_nome' <> 'api:unichat' or r -> 'itens' -> 0 ->> 'por_api' <> 'api:unichat' then
    raise exception 'H1 FALHOU: %', r;
  end if;
  perform pg_temp.ok('H1', 'mkt_msg_historico: por_nome = por_api = api:unichat na linha da integração');
end
$h1$;

-- P3. Cron antigo pausado e silenciado; nada apagado
do $p3t$
begin
  if exists (select 1 from cron.job where jobname = 'ingest-mensageria-hourly' and active)
     or (select silenciado_ate from ops.rotina where jobname = 'ingest-mensageria-hourly') <> 'infinity'
     or to_regclass('controle.mensageria_envio') is null or to_regclass('controle.vw_mensageria_envio') is null then
    raise exception 'P3 FALHOU: ingest-mensageria-hourly não pausado/silenciado ou algo sumiu';
  end if;
  perform pg_temp.ok('P3', 'ingest-mensageria-hourly active=false, ops.rotina silenciado_ate=infinity; controle.mensageria_envio e vw_mensageria_envio intactas (' ||
    (select count(*) from controle.mensageria_envio) || ' linhas)');
end
$p3t$;

-- Fim do bloco 1: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005o BLOCO 1 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.
'
    || (select string_agg(passo || ' | ' || linha, E'
' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 1

-- ▶ BLOCO 2 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005o_mkt_mensageria_precos_integracoes.sql) ═══
-- 20261005o: Marketing > Mensageria (etapa 3): preços e custo estimado, infra comum das integrações, pausa do cron antigo
--
-- STATUS: ESCRITA, NÃO APLICADA. Ensaio: 20261005o_ensaio.sql. Medições e contrato: 20261005o.explain.md.
--
-- O QUE FAZ
--   P1 Preços. mkt_mensageria.precos (por ferramenta, canal, tipo e vigência; não se edita nem apaga: preço errado é
--      ANULADO com motivo). Custo estimado calculado NA LEITURA por UMA função (mkt_mensageria.custo_estimado: preço
--      vigente no dia de enviado_em, em São Paulo). custo_centavos (real) sempre prevalece. Sem preço = 'sem_preco',
--      nunca 0 inventado. Seed copiado de controle.custo_mensagem (medido em 05/10; a guarda confere os valores).
--   P2 Integrações. fontes (ligar/desligar sem deploy), execucoes, recusas, reconciliacao; chave por fonte no Vault
--      (nasce aqui, aleatória); RPC public.mkt_msg_api_receber (só service_role) com upsert idempotente por
--      (origem_sistema, id_externo); projeto pela [SIGLA] no nome da campanha (sem sigla = entra sem projeto, pendência
--      'sem_projeto'); public.mkt_msg_integracoes_saude; uma checagem no pg_cron por fonte (ligada só com a fonte
--      ativa) cadastrada em ops.rotina para o vigia avisar no Slack quando passar 2× o intervalo sem execução ok.
--      Retenção: payload de recusa expurgado após 30 dias (job diário mensageria-recusas-expurgo, em ops.rotina).
--      Porteiro da rota: public.mkt_msg_api_chave_ok (confere a chave antes de a rota ler o corpo).
--   P3 Pausa o cron 'ingest-mensageria-hourly' (jobid conferido pelo nome) e silencia a rotina dele no vigia.
--      Nada é apagado: controle.mensageria_envio e as views vw_mensageria_* ficam congeladas (última linha 28/08).
--
-- O QUE MUDA NO QUE JÁ EXISTE (20261005n, conferido igual ao banco vivo por md5 na guarda)
--   disparos.projeto_id deixa de ser NOT NULL; CHECK novo exige projeto fora da origem 'api'. Coluna nova campanha.
--   disparos.anonimizado_em (LGPD: a API não regrava linha anonimizada). historico: coluna nova por_api.
--   create or replace (mesma assinatura, sem sobrecarga): mkt_msg_disparos_listar (só ACRESCENTA campos),
--   mkt_msg_disparo_salvar (linha da API: só projeto, tipo e custo), mkt_msg_disparo_lancar_retorno (recusa linha da
--   API), mkt_msg_historico (+por_api), mkt_msg_anonimizar_disparo (+recusas do mesmo id_externo), trg_historico.
--
-- AS 5 PERGUNTAS
--   escala: listar continua limitado ao período (≤ 366 dias) e 500 linhas; o custo estimado é um lookup por linha no
--     índice de preços (precos_vigencia_unica). api_receber: lote ≤ 1.000; um SELECT por item no índice único
--     (origem_sistema, id_externo) + UM insert…on conflict para o lote. saúde: 5 fontes × lookups em
--     execucoes (fonte, inicio desc). reconciliar: ≤ 20.000 ids, anti-join no índice único.
--   índice: precos (ferramenta_id, canal, coalesce(tipo,''), vigente_desde desc) where anulado_em is null;
--     execucoes (fonte, inicio desc); recusas (execucao_id), (fonte, id_externo); reconciliacao (fonte, dia desc).
--     Prova: 20261005o_ensaio.sql bloco 2.
--   frequência: n8n manda lote por fonte no intervalo dela (seed 1 h, ajustável); checagem do vigia a cada 30 min
--     por fonte ATIVA (inativa = job desligado, custo zero).
--   repetição: listar é uma query (CTE materializada); o estimado é calculado uma vez por linha e reaproveitado em
--     linhas, totais e por_canal.
--   reversão: fonte → update mkt_mensageria.fontes set ativa = false (desliga recepção e checagem, sem deploy).
--     Rota → revoke execute on function public.mkt_msg_api_receber(text,text,jsonb) from service_role.
--     Cron antigo → bloco REVERSÃO no fim (alter_job active true + silenciado_ate null).

set local lock_timeout = '3s';
set local statement_timeout = '25s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_esperado jsonb := jsonb_build_object(
    'mkt_msg_disparos_listar', 'a49e66a21ad0e99cd46e9ac15869e4f0',
    'mkt_msg_disparo_salvar', '38a25ac0ce35da08408d5338babf1733',
    'mkt_msg_disparo_lancar_retorno', '07d6e198f3f4b51ca6bf0b61b1c99cea',
    'mkt_msg_historico', '527fd822fb59722c27489527ff5181de',
    'mkt_msg_anonimizar_disparo', '769c74b6a37513d2cc94fd2bb81ae602',
    'trg_historico', '6d94581a614a2dfe05559c6cda64f7c8');
  k text;
  v_md5 text;
begin
  if to_regnamespace('mkt_mensageria') is null then
    raise exception '20261005o: schema mkt_mensageria ausente: aplicar 20261005n antes';
  end if;
  if to_regclass('mkt_mensageria.precos') is not null or to_regclass('mkt_mensageria.fontes') is not null then
    raise exception '20261005o: mkt_mensageria.precos/fontes já existe (migration já aplicada?)';
  end if;
  -- As 6 funções reescritas aqui têm que estar como a 20261005n deixou (senão a reescrita apagaria mudança viva).
  for k in select jsonb_object_keys(v_esperado) loop
    select md5(p.prosrc) into v_md5 from pg_proc p
     where p.proname = k and p.pronamespace in ('public'::regnamespace, 'mkt_mensageria'::regnamespace);
    if v_md5 is distinct from v_esperado ->> k then
      raise exception '20261005o: % no banco difere da 20261005n (md5 %): reler a definição viva antes', k, v_md5;
    end if;
  end loop;
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '20261005o: vault.create_secret / extensions.gen_random_bytes ausente';
  end if;
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    raise exception '20261005o: pg_cron sem alter_job/schedule';
  end if;
  if to_regclass('ops.rotina') is null or to_regclass('ops.rotina_estado') is null then
    raise exception '20261005o: vigia (ops.rotina, ops.rotina_estado) ausente: 20261001a..f';
  end if;
  if to_regprocedure('auth.role()') is null then
    raise exception '20261005o: auth.role() ausente';
  end if;
  if exists (select 1 from mkt_mensageria.disparos where origem = 'api') then
    raise exception '20261005o: já existem disparos de origem api (esperado 0 antes da integração)';
  end if;
  -- Seed de preços é cópia de controle.custo_mensagem medida em 05/10/2026. Mudou lá? Rever o seed antes de aplicar.
  if (select count(*) from controle.custo_mensagem c
       where (c.plataforma, c.categoria, c.preco_base * (1 + coalesce(c.margem_bsp, 0)), c.vigente_desde) in (
             ('api', 'utility', 0.08, date '2026-07-01'), ('api', 'marketing', 0.36, date '2026-07-01'),
             ('unnichat', 'utility', 0.08, date '2026-07-24'), ('unnichat', 'marketing', 0.36, date '2026-07-24'),
             ('sms', 'sms', 0.065, date '2026-07-01'), ('activecampaign', 'email', 0, date '2026-07-29'),
             ('grupo', 'grupo', 0, date '2026-07-01'))) <> 7 then
    raise exception '20261005o: controle.custo_mensagem mudou desde 05/10/2026: rever o seed de preços';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas
       where nome in ('Unichat', 'Ligue Lead', 'ActiveCampaign', 'SendFlow', 'Infobip')) <> 5 then
    raise exception '20261005o: ferramentas do seed ausentes (Unichat, Ligue Lead, ActiveCampaign, SendFlow, Infobip)';
  end if;
end
$guarda$;

-- ─── 1. Mudanças em disparos e historico ─────────────────────────────────────────────────────────────────────────────
-- Projeto: a integração grava sem projeto quando o nome da campanha não traz [SIGLA] cadastrada (fila 'sem_projeto').
-- Tela e planilha continuam obrigadas (disparo_validar + CHECK abaixo).
alter table mkt_mensageria.disparos alter column projeto_id drop not null;
alter table mkt_mensageria.disparos
  add constraint disparos_projeto_fora_da_api check (projeto_id is not null or origem = 'api');
alter table mkt_mensageria.disparos
  add column campanha text check (campanha is null or length(btrim(campanha)) between 1 and 300);
alter table mkt_mensageria.disparos add column anonimizado_em timestamptz;
comment on column mkt_mensageria.disparos.anonimizado_em is 'LGPD: quando mkt_msg_anonimizar_disparo limpou o conteúdo. A integração não toca mais a linha (nem métricas).';
comment on column mkt_mensageria.disparos.campanha is 'Nome da campanha na ferramenta de origem (integração). A [SIGLA] dentro dele define o projeto.';
comment on column mkt_mensageria.disparos.projeto_id is 'Projeto (mkt.projetos). Nulo só em origem api sem [SIGLA] cadastrada no nome da campanha: pendência sem_projeto.';

alter table mkt_mensageria.historico
  add column por_api text check (por_api is null or por_api ~ '^api:[a-z][a-z_]{1,39}$');
comment on column mkt_mensageria.historico.por_api is 'Autor quando a mudança veio da integração (auth.uid() nulo): api:<fonte>.';

-- ─── 2. Preços ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Sem default em nenhuma coluna de regra (canal, tipo, base, preço, vigência): um default desfaz a regra em silêncio no
-- próximo INSERT de vigência. criado_em é carimbo, não regra.
create table mkt_mensageria.precos (
  id              bigint generated always as identity primary key,
  ferramenta_id   bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  canal           text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  tipo            text check (tipo is null or tipo in ('utility', 'marketing')),
  base_cobranca   text not null check (base_cobranca in ('entregues', 'tamanho_lista', 'mensalidade')),
  preco_centavos  numeric(12, 4) not null check (preco_centavos >= 0 and preco_centavos <= 100000),
  vigente_desde   date not null check (vigente_desde between date '2020-01-01' and date '2100-12-31'),
  obs             text check (obs is null or length(obs) <= 500),
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,      -- nulo só no seed desta migration
  anulado_em      timestamptz,
  anulado_por     uuid references public.perfis(id) on delete set null,
  anulado_motivo  text check (anulado_motivo is null or length(btrim(anulado_motivo)) between 3 and 500),
  constraint precos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  -- mensalidade: o custo é o mensal da ferramenta; por disparo, 0.
  constraint precos_mensalidade_zero check (base_cobranca <> 'mensalidade' or preco_centavos = 0),
  constraint precos_anulacao_completa check ((anulado_em is null) = (anulado_motivo is null))
);
-- Uma vigência válida por (ferramenta, canal, tipo, data); é também o índice da busca do preço vigente
-- (… = … and vigente_desde <= dia order by vigente_desde desc limit 1). coalesce(tipo,'') porque tipo é nulo fora da API.
create unique index precos_vigencia_unica on mkt_mensageria.precos
  (ferramenta_id, canal, coalesce(tipo, ''), vigente_desde desc) where anulado_em is null;
comment on table mkt_mensageria.precos is 'Preço por mensagem (centavos, 4 casas) por ferramenta/canal/tipo e vigência. Não se edita nem apaga: anular com motivo e cadastrar outro.';

-- ─── 3. Integrações: fontes, execucoes, recusas, reconciliacao ───────────────────────────────────────────────────────
create table mkt_mensageria.fontes (
  chave               text primary key check (chave ~ '^[a-z][a-z_]{1,39}$'),
  nome                text not null check (length(btrim(nome)) between 2 and 60),
  ferramenta_id       bigint references mkt_mensageria.ferramentas(id) on delete restrict,   -- nulo: o item diz a ferramenta
  ativa               boolean not null,                     -- sem default: ligar/desligar é decisão explícita
  ativa_desde         timestamptz,                          -- trigger: carimba ao ligar, zera ao desligar
  intervalo_esperado  interval not null check (intervalo_esperado between interval '5 minutes' and interval '7 days'),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint fontes_ativa_desde check (ativa = (ativa_desde is not null))
);
comment on table mkt_mensageria.fontes is 'Sistemas que mandam disparos pela API. ativa=false recusa o lote e desliga a checagem do vigia (sem deploy). Chave no Vault: mkt_msg_fonte_<chave>.';

create table mkt_mensageria.execucoes (
  id           bigint generated always as identity primary key,
  fonte        text not null references mkt_mensageria.fontes(chave) on delete restrict,
  inicio       timestamptz not null,
  fim          timestamptz not null,
  lidos        integer not null check (lidos >= 0),
  inseridos    integer not null check (inseridos >= 0),
  atualizados  integer not null check (atualizados >= 0),
  inalterados  integer not null check (inalterados >= 0),
  recusados    integer not null check (recusados >= 0),
  status       text not null check (status in ('ok', 'inconsistente', 'fonte_inativa', 'lote_invalido')),
  detalhe      text check (detalhe is null or length(detalhe) <= 300),
  constraint execucoes_fim_depois check (fim >= inicio)
);
create index execucoes_fonte_inicio_idx on mkt_mensageria.execucoes (fonte, inicio desc);
comment on table mkt_mensageria.execucoes is 'Uma linha por lote recebido com chave válida. inconsistente = lidos ≠ inseridos+atualizados+inalterados+recusados. Só acréscimo.';

create table mkt_mensageria.recusas (
  id                  bigint generated always as identity primary key,
  execucao_id         bigint not null references mkt_mensageria.execucoes(id) on delete restrict,
  fonte               text not null references mkt_mensageria.fontes(chave) on delete restrict,
  posicao             integer not null check (posicao >= 1),
  id_externo          text check (id_externo is null or length(id_externo) <= 200),
  motivo              text not null check (length(motivo) between 3 and 500),
  payload             jsonb not null,
  criado_em           timestamptz not null default now(),
  anonimizado_em      timestamptz,
  anonimizado_por     uuid,
  anonimizado_motivo  text check (anonimizado_motivo is null or length(btrim(anonimizado_motivo)) between 3 and 500),
  expurgado_em        timestamptz                           -- retenção: payload trocado por {"expurgado":true} após 30 dias
);
create index recusas_execucao_idx on mkt_mensageria.recusas (execucao_id);
create index recusas_externo_idx on mkt_mensageria.recusas (fonte, id_externo) where id_externo is not null;
create index recusas_criado_idx on mkt_mensageria.recusas (criado_em desc);
comment on table mkt_mensageria.recusas is 'Item do lote que não entrou, com o motivo e o item recebido (payload). LGPD: mkt_msg_anonimizar_disparo (mesmo id_externo), mkt_msg_anonimizar_recusa e expurgo do payload após 30 dias (job mensageria-recusas-expurgo). Leitura sem payload: mkt_msg_recusas_listar (admin).';

create table mkt_mensageria.reconciliacao (
  id               bigint generated always as identity primary key,
  fonte            text not null references mkt_mensageria.fontes(chave) on delete restrict,
  dia              date not null,
  contagem_fonte   integer not null check (contagem_fonte >= 0),
  contagem_log     integer not null check (contagem_log >= 0),
  faltantes_total  integer not null check (faltantes_total >= 0),
  faltantes        jsonb not null check (jsonb_typeof(faltantes) = 'array'),   -- até 500 id_externo
  criado_em        timestamptz not null default now()
);
create index reconciliacao_fonte_dia_idx on mkt_mensageria.reconciliacao (fonte, dia desc, id desc);
comment on table mkt_mensageria.reconciliacao is 'Conferência diária: quantos a fonte diz que enviou x quantos estão no log, e os id_externo que faltam. Só acréscimo.';

alter table mkt_mensageria.precos enable row level security;
alter table mkt_mensageria.fontes enable row level security;
alter table mkt_mensageria.execucoes enable row level security;
alter table mkt_mensageria.recusas enable row level security;
alter table mkt_mensageria.reconciliacao enable row level security;
revoke all on mkt_mensageria.precos, mkt_mensageria.fontes, mkt_mensageria.execucoes, mkt_mensageria.recusas,
              mkt_mensageria.reconciliacao from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Funções internas (revoke de todos logo após cada create) ─────────────────────────────────────────────────────
create function mkt_mensageria.fonte_jobname(p_chave text) returns text
language sql immutable set search_path = '' as $$
  select 'mensageria-fonte-' || replace(p_chave, '_', '-');
$$;
revoke all on function mkt_mensageria.fonte_jobname(text) from public, anon, authenticated;

-- A ÚNICA regra de custo estimado. Preço vigente = a vigência não anulada mais recente com vigente_desde ≤ dia do
-- envio (São Paulo). entregues: entregues × preço (entregues nulo = sem estimativa); tamanho_lista: tamanho × preço;
-- mensalidade: 0 por disparo. Sem preço: centavos nulo e tem_preco = false (nunca 0 inventado).
create function mkt_mensageria.custo_estimado(p_ferramenta bigint, p_canal text, p_tipo text, p_enviado_em timestamptz,
                                              p_entregues integer, p_tamanho integer,
                                              out centavos bigint, out tem_preco boolean, out preco_id bigint)
language sql stable set search_path = '' as $$
  select case pv.base_cobranca
           when 'mensalidade' then 0::bigint
           when 'tamanho_lista' then round(p_tamanho * pv.preco_centavos)::bigint
           when 'entregues' then round(p_entregues * pv.preco_centavos)::bigint
         end,
         pv.id is not null,
         pv.id
    from (select 1) um
    left join lateral (
      select p.id, p.base_cobranca, p.preco_centavos
        from mkt_mensageria.precos p
       where p.ferramenta_id = p_ferramenta and p.canal = p_canal and coalesce(p.tipo, '') = coalesce(p_tipo, '')
         and p.vigente_desde <= (p_enviado_em at time zone 'America/Sao_Paulo')::date
         and p.anulado_em is null
       order by p.vigente_desde desc
       limit 1) pv on true;
$$;
revoke all on function mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer) from public, anon, authenticated;

-- Pendências (versão 2; a v1 mkt_mensageria.pendencias fica, sem uso). Ordem: as 3 antigas, depois as novas.
--   sem_custo: nem custo real nem estimado · sem_retorno: entregues ou lidas nulas (canal grupo dispensa)
--   conferir_zero_leitura: 0 lidas com custo (real ou estimado) > 0 · sem_preco: sem custo real e sem preço vigente
--   sem_projeto: entrou pela integração sem [SIGLA] cadastrada
create function mkt_mensageria.pendencias_v2(p_canal text, p_projeto bigint, p_entregues integer, p_lidas integer,
                                             p_custo integer, p_custo_estimado bigint, p_tem_preco boolean) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null and p_custo_estimado is null then 'sem_custo' end,
    case when p_canal <> 'grupo' and (p_entregues is null or p_lidas is null) then 'sem_retorno' end,
    case when p_lidas = 0 and coalesce(p_custo::bigint, p_custo_estimado) > 0 then 'conferir_zero_leitura' end,
    case when p_custo is null and not coalesce(p_tem_preco, false) then 'sem_preco' end,
    case when p_projeto is null then 'sem_projeto' end], null);
$$;
revoke all on function mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean) from public, anon, authenticated;

-- Atraso da fonte: tempo desde a última execução ok (ou desde que foi ligada). Atrasada = ativa e > 2× o intervalo.
-- Usada pela saúde e pela checagem do vigia (mesma regra nos dois).
create function mkt_mensageria.fonte_atraso(p_fonte text, out ativa boolean, out ultima_ok_em timestamptz,
                                            out atraso interval, out atrasada boolean)
language sql stable set search_path = '' as $$
  select f.ativa, u.fim,
         case when f.ativa then now() - greatest(u.fim, f.ativa_desde) end,
         coalesce(f.ativa and now() - greatest(u.fim, f.ativa_desde) > 2 * f.intervalo_esperado, false)
    from mkt_mensageria.fontes f
    left join lateral (select e.fim from mkt_mensageria.execucoes e
                        where e.fonte = f.chave and e.status = 'ok'
                        order by e.inicio desc limit 1) u on true
   where f.chave = p_fonte;
$$;
revoke all on function mkt_mensageria.fonte_atraso(text) from public, anon, authenticated;

-- Comando do pg_cron de cada fonte. Atrasada = erro (falha_sql) → o vigia abre incidente e avisa no Slack.
create function mkt_mensageria.vigiar_fonte(p_fonte text) returns text
language plpgsql stable set search_path = '' as $$
declare
  r record;
begin
  select * into r from mkt_mensageria.fonte_atraso(p_fonte);
  if r.ativa is null then
    raise exception 'Mensageria: fonte % não cadastrada', p_fonte;
  end if;
  if r.atrasada then
    raise exception 'Mensageria: fonte % sem execução ok há % (esperado a cada %)', p_fonte, date_trunc('minute', r.atraso),
      (select f.intervalo_esperado from mkt_mensageria.fontes f where f.chave = p_fonte);
  end if;
  return case when r.ativa then 'ok' else 'inativa' end;
end
$$;
revoke all on function mkt_mensageria.vigiar_fonte(text) from public, anon, authenticated;

-- Confere a chave da fonte contra o Vault (sha256: não vaza prefixo por tempo). Formato fixo antes de consultar.
create function mkt_mensageria.chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v text;
begin
  if p_fonte is null or p_chave is null or p_chave !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_' || p_fonte;
  if v is null then
    return false;
  end if;
  return sha256(convert_to(p_chave, 'UTF8')) = sha256(convert_to(v, 'UTF8'));
end
$$;
revoke all on function mkt_mensageria.chave_ok(text, text) from public, anon, authenticated;

-- Um item do lote → valores finais (já mesclados com o que está gravado) ou motivo da recusa.
-- Mescla: campo ausente/nulo no item = mantém o gravado (NULL da fonte nunca apaga). tipo e custo_centavos: o gravado
-- vence quando existe (a tela pode ter corrigido). Projeto: o gravado vence; senão a [SIGLA] da campanha.
-- Validação: a mesma da tela (disparo_validar), sobre o resultado da mescla; só o erro "projeto" é dispensado.
create function mkt_mensageria.api_item(p_fonte text, p_ferr_fixa bigint, p_item jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ext text;
  d mkt_mensageria.disparos%rowtype;
  v_existe boolean;
  v_campanha text;
  v_proj bigint;
  v_nproj integer;
  v_sigla text;
  v_ferr bigint;
  v_txt text;
  v_num bigint;
  v_canon jsonb;
  k text;
  r jsonb;
  v_motivo text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_object('motivo', 'Item não é um objeto JSON.');
  end if;
  v_ext := btrim(coalesce(p_item ->> 'id_externo', ''));
  if v_ext = '' or length(v_ext) > 200 then
    return jsonb_build_object('motivo', 'id_externo ausente ou com mais de 200 caracteres.');
  end if;

  select * into d from mkt_mensageria.disparos x where x.origem_sistema = p_fonte and x.id_externo = v_ext;
  v_existe := found;
  if v_existe and d.arquivado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- arquivado pela tela: a API não mexe
  end if;
  if v_existe and d.anonimizado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- LGPD: anonimizado, a API não regrava nada
  end if;

  v_campanha := nullif(left(btrim(coalesce(p_item ->> 'campanha', '')), 300), '');
  if v_campanha is null and v_existe then v_campanha := d.campanha; end if;
  -- [SIGLA]: o conteúdo de um colchete que seja sigla cadastrada. Nenhuma, ou duas siglas diferentes = sem projeto.
  select min(pr.id), count(distinct pr.id) into v_proj, v_nproj
    from regexp_matches(coalesce(v_campanha, ''), '\[([^][]{1,20})\]', 'g') m
    join mkt.projetos pr on pr.sigla = upper(btrim(m[1]));
  if v_nproj <> 1 then v_proj := null; end if;
  if v_existe and d.projeto_id is not null then v_proj := d.projeto_id; end if;
  select pr.sigla into v_sigla from mkt.projetos pr where pr.id = v_proj;

  if p_ferr_fixa is not null then
    v_ferr := p_ferr_fixa;
  else
    v_txt := btrim(coalesce(p_item ->> 'ferramenta', ''));
    if v_txt <> '' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
      if v_ferr is null then
        return jsonb_build_object('id_externo', v_ext, 'motivo', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.');
      end if;
    elsif v_existe then
      v_ferr := d.ferramenta_id;
    end if;
  end if;

  v_txt := regexp_replace(coalesce(p_item ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      return jsonb_build_object('id_externo', v_ext, 'motivo', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.');
    end if;
  elsif v_existe then
    v_num := d.numero_id;
  end if;

  v_canon := case when v_existe then jsonb_build_object(
      'enviado_em', d.enviado_em, 'canal', d.canal, 'tipo', d.tipo, 'copy_texto', d.copy_texto, 'copy_link', d.copy_link,
      'publico_lista', d.publico_lista, 'publico_origem', d.publico_origem, 'tamanho_lista', d.tamanho_lista,
      'entregues', d.entregues, 'lidas', d.lidas, 'cliques', d.cliques, 'falhas', d.falhas,
      'custo_centavos', d.custo_centavos, 'disparado_por', d.disparado_por)
    else '{}'::jsonb end;
  foreach k in array array['enviado_em', 'canal', 'tipo', 'copy_texto', 'copy_link', 'publico_lista', 'publico_origem',
                           'tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'disparado_por'] loop
    if jsonb_typeof(p_item -> k) is not null and jsonb_typeof(p_item -> k) <> 'null'
       and not (k in ('tipo', 'custo_centavos') and jsonb_typeof(v_canon -> k) is not null and jsonb_typeof(v_canon -> k) <> 'null') then
      v_canon := v_canon || jsonb_build_object(k, p_item -> k);
    end if;
  end loop;
  v_canon := v_canon || jsonb_build_object('projeto', coalesce(v_sigla, ''), 'ferramenta_id', v_ferr::text,
                                           'numero_id', v_num::text);
  if nullif(btrim(coalesce(v_canon ->> 'disparado_por', '')), '') is null then
    v_canon := v_canon || jsonb_build_object('disparado_por', 'api:' || p_fonte);
  end if;

  r := mkt_mensageria.disparo_validar(v_canon);
  select left(string_agg(x ->> 'campo' || ': ' || (x ->> 'msg'), '; '), 500) into v_motivo
    from jsonb_array_elements(r -> 'erros') x
   where x ->> 'campo' <> 'projeto';
  if v_motivo is not null then
    return jsonb_build_object('id_externo', v_ext, 'motivo', v_motivo);
  end if;
  return jsonb_build_object('id_externo', v_ext, 'existe', v_existe,
    'v', (r -> 'v') || jsonb_build_object('projeto_id', v_proj, 'campanha', v_campanha, 'id_externo', v_ext));
end
$$;
revoke all on function mkt_mensageria.api_item(text, bigint, jsonb) from public, anon, authenticated;

-- Upsert idempotente do lote por (origem_sistema, id_externo). Uma passada de validação + UM insert…on conflict.
-- UPDATE só quando algum valor muda (o WHERE do DO UPDATE); tipo, projeto e custo: o gravado vence na hora da escrita
-- (fecha a corrida com a tela). Lock por fonte: dois lotes da mesma fonte viram fila. Repetido no lote: vale o último.
-- Autor no histórico: 'api:<fonte>' (flag local à transação, lida pelo trg_historico quando auth.uid() é nulo).
create function mkt_mensageria.api_upsert(p_fonte text, p_lote jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_ferr_fixa bigint;
  v_res jsonb[];
  v_n integer;
  v_ins integer := 0;
  v_upd integer := 0;
  v_validos integer;
  v_arq integer;
  v_recusas jsonb;
begin
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    raise exception 'api_upsert: lote tem que ser array de até 1.000 itens' using errcode = '22023';
  end if;
  select f.ferramenta_id into v_ferr_fixa from mkt_mensageria.fontes f where f.chave = p_fonte;
  if not found then
    raise exception 'api_upsert: fonte % não cadastrada', p_fonte using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_lote);
  perform pg_advisory_xact_lock(hashtext('mkt_mensageria.api:' || p_fonte));
  perform set_config('mkt_mensageria.autor_api', 'api:' || p_fonte, true);

  select coalesce(array_agg(x.r order by x.pos), '{}') into v_res
    from (select t.pos,
                 case when t.ext is not null and t.rep > 1
                      then jsonb_build_object('pos', t.pos, 'id_externo', t.ext,
                                              'motivo', 'id_externo repetido no lote: vale a última ocorrência.')
                      else jsonb_build_object('pos', t.pos) || mkt_mensageria.api_item(p_fonte, v_ferr_fixa, t.item) end as r
            from (select e.item, e.pos::int as pos, nullif(btrim(e.item ->> 'id_externo'), '') as ext,
                         row_number() over (partition by nullif(btrim(e.item ->> 'id_externo'), '') order by e.pos desc) as rep
                    from jsonb_array_elements(p_lote) with ordinality e(item, pos)) t) x;

  with v as (
    select r -> 'v' as v from unnest(v_res) r where r ? 'v'
  ), up as (
    insert into mkt_mensageria.disparos as d (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, origem_sistema, id_externo, campanha)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'api', p_fonte, v ->> 'id_externo', v ->> 'campanha'
      from v
    on conflict (origem_sistema, id_externo) where id_externo is not null do update
       set enviado_em = excluded.enviado_em, projeto_id = coalesce(d.projeto_id, excluded.projeto_id),
           canal = excluded.canal, ferramenta_id = excluded.ferramenta_id, numero_id = excluded.numero_id,
           tipo = coalesce(d.tipo, excluded.tipo), copy_texto = excluded.copy_texto, copy_link = excluded.copy_link,
           publico_lista = excluded.publico_lista, publico_origem = excluded.publico_origem,
           tamanho_lista = excluded.tamanho_lista, entregues = excluded.entregues, lidas = excluded.lidas,
           cliques = excluded.cliques, falhas = excluded.falhas,
           custo_centavos = coalesce(d.custo_centavos, excluded.custo_centavos),
           disparado_por = excluded.disparado_por, campanha = excluded.campanha,
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from (excluded.entregues, excluded.lidas, excluded.cliques, excluded.falhas,
                                                    coalesce(d.custo_centavos, excluded.custo_centavos))
                             then now() else d.retorno_em end
     where d.arquivado_em is null and d.anonimizado_em is null
       and (d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
            d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
            d.custo_centavos, d.disparado_por, d.campanha)
           is distinct from
           (excluded.enviado_em, coalesce(d.projeto_id, excluded.projeto_id), excluded.canal, excluded.ferramenta_id,
            excluded.numero_id, coalesce(d.tipo, excluded.tipo), excluded.copy_texto, excluded.copy_link,
            excluded.publico_lista, excluded.publico_origem, excluded.tamanho_lista, excluded.entregues, excluded.lidas,
            excluded.cliques, excluded.falhas, coalesce(d.custo_centavos, excluded.custo_centavos),
            excluded.disparado_por, excluded.campanha)
    returning (d.xmax = 0) as inserido
  )
  select count(*) filter (where inserido), count(*) filter (where not inserido) into v_ins, v_upd from up;

  select count(*) filter (where r ? 'v'), count(*) filter (where r ? 'arquivado') into v_validos, v_arq from unnest(v_res) r;
  select coalesce(jsonb_agg(jsonb_build_object(
           'posicao', (r ->> 'pos')::int, 'id_externo', r ->> 'id_externo', 'motivo', r ->> 'motivo',
           'payload', case when r ->> 'id_externo' is not null and (
                                  exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = p_fonte
                                             and d.id_externo = r ->> 'id_externo' and d.anonimizado_em is not null)
                                  or exists (select 1 from mkt_mensageria.recusas x where x.fonte = p_fonte
                                             and x.id_externo = r ->> 'id_externo' and x.anonimizado_em is not null))
                           then jsonb_build_object('anonimizado', true)
                           when length((p_lote -> ((r ->> 'pos')::int - 1))::text) <= 20000 then p_lote -> ((r ->> 'pos')::int - 1)
                           else jsonb_build_object('truncado', true, 'tamanho', length((p_lote -> ((r ->> 'pos')::int - 1))::text)) end)
           order by (r ->> 'pos')::int), '[]'::jsonb)
    into v_recusas
    from unnest(v_res) r where r ? 'motivo';
  perform set_config('mkt_mensageria.autor_api', '', true);

  return jsonb_build_object('lidos', v_n, 'inseridos', v_ins, 'atualizados', v_upd,
                            'inalterados', v_validos - v_ins - v_upd + v_arq,
                            'recusados', jsonb_array_length(v_recusas), 'recusas', v_recusas);
end
$$;
revoke all on function mkt_mensageria.api_upsert(text, jsonb) from public, anon, authenticated;

-- Retenção LGPD das recusas: payload com mais de 30 dias vira {"expurgado":true} (motivo, id_externo e datas ficam).
-- Até 5.000 por execução (job diário). Grava: não pode ser stable.
create function mkt_mensageria.recusas_expurgar() returns integer
language plpgsql set search_path = '' as $$
declare
  v integer;
begin
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('expurgado', true), expurgado_em = now()
   where r.id in (select x.id from mkt_mensageria.recusas x
                   where x.criado_em < now() - interval '30 days' and x.expurgado_em is null and x.anonimizado_em is null
                   order by x.criado_em limit 5000);
  get diagnostics v = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  return v;
end
$$;
revoke all on function mkt_mensageria.recusas_expurgar() from public, anon, authenticated;

-- ─── 5. Triggers ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Histórico: igual à 20261005n + autor da integração (por_api) quando auth.uid() é nulo.
create or replace function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
  v_uid uuid := auth.uid();
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por, por_api)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, v_uid,
          case when v_uid is null then nullif(current_setting('mkt_mensageria.autor_api', true), '') end);
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Preço: só a anulação (uma vez, com motivo). Nada mais muda.
create function mkt_mensageria.trg_preco_anular() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.anulado_em is not null then
    raise exception 'mkt_mensageria.precos: preço já anulado não muda' using errcode = '42501';
  end if;
  if new.anulado_em is null
     or (new.id, new.ferramenta_id, new.canal, new.tipo, new.base_cobranca, new.preco_centavos, new.vigente_desde,
         new.obs, new.criado_em, new.criado_por)
        is distinct from (old.id, old.ferramenta_id, old.canal, old.tipo, old.base_cobranca, old.preco_centavos,
                          old.vigente_desde, old.obs, old.criado_em, old.criado_por) then
    raise exception 'mkt_mensageria.precos: preço não se edita (anule com motivo e cadastre outro)' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_preco_anular() from public, anon, authenticated;

-- Fonte: chave imutável; ativa_desde carimbado ao ligar e zerado ao desligar; liga/desliga junto a checagem do vigia.
create function mkt_mensageria.trg_fonte() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_job bigint;
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.ativa_desde := case when new.ativa then now() end;
  else
    if new.chave is distinct from old.chave then
      raise exception 'mkt_mensageria.fontes: a chave não muda' using errcode = '42501';
    end if;
    new.criado_em := old.criado_em;
    new.ativa_desde := case when not new.ativa then null when old.ativa then old.ativa_desde else now() end;
    if new.ativa is distinct from old.ativa then
      select j.jobid into v_job from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(new.chave);
      if v_job is not null then
        perform cron.alter_job(v_job, active := new.ativa);
      end if;
    end if;
  end if;
  new.atualizado_em := now();
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_fonte() from public, anon, authenticated;

-- Recusa: só a anonimização LGPD e o expurgo (flag local) mudam, e só payload + campos anonimizado_*/expurgado_em.
create function mkt_mensageria.trg_recusa_anonimizar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on'
     and (new.id, new.execucao_id, new.fonte, new.posicao, new.id_externo, new.motivo, new.criado_em)
         is not distinct from (old.id, old.execucao_id, old.fonte, old.posicao, old.id_externo, old.motivo, old.criado_em) then
    return new;
  end if;
  raise exception 'mkt_mensageria.recusas: UPDATE não é permitido (só a anonimização LGPD)' using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_recusa_anonimizar() from public, anon, authenticated;

create trigger a_anular before update on mkt_mensageria.precos
  for each row execute function mkt_mensageria.trg_preco_anular();
create trigger a_fonte before insert or update on mkt_mensageria.fontes
  for each row execute function mkt_mensageria.trg_fonte();
create trigger sem_update before update on mkt_mensageria.recusas
  for each row execute function mkt_mensageria.trg_recusa_anonimizar();
create trigger sem_update before update on mkt_mensageria.execucoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.reconciliacao
  for each row execute function mkt_mensageria.trg_bloqueio();
do $bloqueio$
declare t text;
begin
  foreach t in array array['precos', 'fontes', 'execucoes', 'recusas', 'reconciliacao'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;

-- ─── 6. Seeds ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Preços: cópia EXPLÍCITA de controle.custo_mensagem (05/10/2026; a guarda conferiu). Reais → centavos (× 100).
-- Base: WhatsApp e grupo por entregue e SMS por envio, como a vw_mensageria_envio cobrava (sms: qtd_sms/enviados).
-- E-mail e grupo: 0 por disparo (mensalidade). Infobip SMS: SEM preço (pendência: a listagem mostra 'sem_preco').
insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs)
select f.id, s.canal, s.tipo, s.base, s.preco, s.vig, s.obs
  from (values
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, marketing'),
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, marketing'),
    ('Ligue Lead', 'sms', null, 'tamanho_lista', 6.5000, date '2026-07-01', 'controle.custo_mensagem: plataforma sms'),
    ('ActiveCampaign', 'email', null, 'mensalidade', 0.0000, date '2026-07-29', 'controle.custo_mensagem: plataforma activecampaign'),
    ('SendFlow', 'grupo', null, 'mensalidade', 0.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma grupo')
  ) s(ferramenta, canal, tipo, base, preco, vig, obs)
  join mkt_mensageria.ferramentas f on f.nome = s.ferramenta;

-- Fontes: todas DESLIGADAS (nenhum fluxo do n8n existe ainda). Ligar: update … set ativa = true (como postgres).
-- Intervalo de 1 h é o do cron antigo (ingest-mensageria-hourly); ajustar por fonte quando o fluxo existir.
insert into mkt_mensageria.fontes (chave, nome, ferramenta_id, ativa, intervalo_esperado)
select s.chave, s.nome, (select f.id from mkt_mensageria.ferramentas f where f.nome = s.ferramenta), false, interval '1 hour'
  from (values ('activecampaign', 'ActiveCampaign', 'ActiveCampaign'), ('unichat', 'Unichat', 'Unichat'),
               ('infobip', 'Infobip', 'Infobip'), ('sendflow', 'SendFlow', 'SendFlow'),
               ('cs_disparos', 'Disparos do CS (cs.disparos)', null)) s(chave, nome, ferramenta);

-- Chave de cada fonte: nasce no Vault (32 bytes aleatórios, hex). Idempotente: não troca chave existente.
-- Para configurar o n8n, o dono lê: select decrypted_secret from vault.decrypted_secrets where name = 'mkt_msg_fonte_<chave>';
do $vault$
declare c text;
begin
  for c in select f.chave from mkt_mensageria.fontes f loop
    if not exists (select 1 from vault.secrets where name = 'mkt_msg_fonte_' || c) then
      perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mkt_msg_fonte_' || c,
                                  'Chave da fonte ' || c || ' da Mensageria (API mkt_msg_api_receber; gerada no banco)');
    end if;
  end loop;
end
$vault$;

-- Vigia: um job por fonte, criado DESLIGADO (liga junto com a fonte, pelo trg_fonte). Falha = fonte atrasada.
-- ops.rotina: 1 falha abre (a checagem já espera 2× o intervalo), 1 ok fecha.
do $vigia$
declare
  c text;
  v_job bigint;
begin
  for c in select f.chave from mkt_mensageria.fontes f order by f.chave loop
    if exists (select 1 from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(c)) then
      raise exception '20261005o: job % já existe', mkt_mensageria.fonte_jobname(c);
    end if;
    v_job := cron.schedule(mkt_mensageria.fonte_jobname(c), '*/30 * * * *',
                           format('select mkt_mensageria.vigiar_fonte(%L)', c));
    perform cron.alter_job(v_job, active := false);
    insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
    values (mkt_mensageria.fonte_jobname(c), 1, interval '3 hours', 1, interval '30 minutes', 'manual');
    insert into ops.rotina_estado (jobname) values (mkt_mensageria.fonte_jobname(c)) on conflict do nothing;
  end loop;
  -- Retenção das recusas: diário, 04:17 UTC. Mais de 26 h sem sucesso = alerta.
  if exists (select 1 from cron.job j where j.jobname = 'mensageria-recusas-expurgo') then
    raise exception '20261005o: job mensageria-recusas-expurgo já existe';
  end if;
  perform cron.schedule('mensageria-recusas-expurgo', '17 4 * * *', 'select mkt_mensageria.recusas_expurgar()');
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('mensageria-recusas-expurgo', 1, interval '26 hours', 1, interval '24 hours', 'manual');
  insert into ops.rotina_estado (jobname) values ('mensageria-recusas-expurgo') on conflict do nothing;
end
$vigia$;

-- ─── 7. P3: pausa o cron antigo (dependentes medidos em 05/10: só as views vw_mensageria_*; nenhuma função) ─────────
-- Estado antes (05/10/2026): jobid 26, '50 * * * *', active = true; ops.rotina silenciado_ate = null.
do $p3$
declare
  v_job bigint;
  v_ativo boolean;
begin
  select j.jobid, j.active into v_job, v_ativo from cron.job j where j.jobname = 'ingest-mensageria-hourly';
  if v_job is null then
    raise notice '20261005o: ingest-mensageria-hourly não existe: nada a pausar';
  elsif v_ativo then
    perform cron.alter_job(v_job, active := false);
  end if;
  update ops.rotina set silenciado_ate = 'infinity' where jobname = 'ingest-mensageria-hourly';
end
$p3$;

-- ─── 8. Funções públicas (RPC) ───────────────────────────────────────────────────────────────────────────────────────

-- Lista do período: igual à 20261005n + custo estimado, custo_fonte, campanha e pendências v2. Só ACRESCENTA campos.
-- Projeto em left join (linha da API pode vir sem projeto). Contrato em 20261005o.explain.md.
create or replace function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                                          p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, d.campanha, ce.centavos as custo_estimado,
             case when d.custo_centavos is not null then 'real'
                  when ce.centavos is not null then 'estimado'
                  when not ce.tem_preco then 'sem_preco' end as custo_fonte,
             mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos, ce.centavos,
                                          ce.tem_preco) as pendencias
        from mkt_mensageria.disparos d
        cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em, d.entregues,
                                                         d.tamanho_lista) ce
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias),
                 'campanha', b.campanha, 'custo_estimado_centavos', b.custo_estimado, 'custo_fonte', b.custo_fonte)
               order by b.enviado_em desc, b.id desc)
          from pagina b
          left join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)),
                 'custo_estimado_centavos', sum(b.custo_estimado) filter (where b.custo_centavos is null),
                 'com_estimativa', count(*) filter (where b.custo_centavos is null and b.custo_estimado is not null),
                 'custo_total_centavos', sum(coalesce(b.custo_centavos, b.custo_estimado)),
                 'sem_preco', count(*) filter (where 'sem_preco' = any(b.pendencias)),
                 'sem_projeto', count(*) filter (where 'sem_projeto' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo,
                 'custo_estimado_centavos', c.estimado, 'custo_total_centavos', c.total, 'sem_preco', c.sem_preco,
                 'sem_projeto', c.sem_projeto)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo,
                       count(*) filter (where 'sem_custo' = any(b.pendencias)) as sem_custo,
                       sum(b.custo_estimado) filter (where b.custo_centavos is null) as estimado,
                       sum(coalesce(b.custo_centavos, b.custo_estimado)) as total,
                       count(*) filter (where 'sem_preco' = any(b.pendencias)) as sem_preco,
                       count(*) filter (where 'sem_projeto' = any(b.pendencias)) as sem_projeto
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Igual à 20261005n + linha de origem 'api': só projeto, tipo e custo mudam aqui (o resto vem da fonte).
create or replace function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
  v_origem text;
  v_canal_api text;
  v_arq timestamptz;
  v_sigla text;
  v_proj bigint;
  v_tipo text;
  v_custo bigint;
  e jsonb := '[]'::jsonb;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;

  if v_id is not null then
    select d.origem, d.canal, d.arquivado_em into v_origem, v_canal_api, v_arq
      from mkt_mensageria.disparos d where d.id = v_id for update;
    if v_origem = 'api' then
      if v_arq is not null then
        return jsonb_build_object('ok', false, 'msg', 'Disparo arquivado: não pode ser editado.');
      end if;
      v_sigla := upper(btrim(coalesce(p ->> 'projeto', '')));
      if v_sigla = '' then
        e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
      else
        select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
        if v_proj is null then
          e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
        end if;
      end if;
      v_tipo := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
      if v_canal_api = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
      elsif v_canal_api <> 'whatsapp_api' and v_tipo is not null then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
      end if;
      v_custo := mkt_mensageria.inteiro(p ->> 'custo_centavos');
      if v_custo < 0 then
        e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
      end if;
      if jsonb_array_length(e) > 0 then
        return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
      end if;
      update mkt_mensageria.disparos d
         set projeto_id = v_proj, tipo = v_tipo, custo_centavos = v_custo::int,
             retorno_em = case when d.custo_centavos is distinct from v_custo::int then now() else d.retorno_em end
       where d.id = v_id;
      return jsonb_build_object('ok', true, 'id', v_id, 'campos', jsonb_build_array('projeto', 'tipo', 'custo_centavos'),
        'msg', 'Disparo da integração salvo: aqui mudam só projeto, tipo e custo; o resto vem da fonte.');
    end if;
  end if;

  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null and d.origem <> 'api';
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Igual à 20261005n + recusa linha da API (o retorno vem da fonte) + pendências v2 (com o custo estimado).
create or replace function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                                 p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
  v_origem text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista, d.origem into v_tam, v_origem
    from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if v_origem = 'api' then
    return jsonb_build_object('ok', false, 'msg',
      'Disparo da integração: o retorno vem da fonte. Projeto, tipo e custo se editam no próprio disparo.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
    'pendencias', (select to_jsonb(mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos,
                                                                ce.centavos, ce.tem_preco))
                     from mkt_mensageria.disparos d
                     cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em,
                                                                      d.entregues, d.tamanho_lista) ce
                    where d.id = p_id));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Igual à 20261005n + por_api; por_nome cai para 'api:<fonte>' quando a mudança veio da integração.
create or replace function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', coalesce(pf.nome, h.por_api),
             'por_api', h.por_api, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- Igual à 20261005n + limpa o payload das recusas do mesmo (fonte, id_externo). Retorno ganha recusas_limpas.
create or replace function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
  v_rec integer := 0;
  v_sis text;
  v_ext text;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  select d.origem_sistema, d.id_externo into v_sis, v_ext from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end,
         anonimizado_em = coalesce(d.anonimizado_em, now())
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  if v_ext is not null then
    update mkt_mensageria.recusas r
       set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
           anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
     where r.fonte = v_sis and r.id_externo = v_ext and r.anonimizado_em is null;
    get diagnostics v_rec = row_count;
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist, 'recusas_limpas', v_rec),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist,
                            'recusas_limpas', v_rec);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- LGPD de uma recusa que não virou disparo (só admin/dev, como a de disparo). Troca o payload; fica o motivo.
create function public.mkt_msg_anonimizar_recusa(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_n integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
         anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
   where r.id = p_id and r.anonimizado_em is null;
  get diagnostics v_n = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Recusa não encontrada ou já anonimizada.');
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Recusa anonimizada.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_anonimizar_recusa(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_recusa(bigint, text) to authenticated;

-- Preços: todos (inclusive anulados, para a trilha), com o vigente de hoje marcado.
create function public.mkt_msg_precos_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'precos', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'ferramenta_id', p.ferramenta_id, 'ferramenta', f.nome, 'canal', p.canal, 'tipo', p.tipo,
             'base_cobranca', p.base_cobranca, 'preco_centavos', p.preco_centavos, 'vigente_desde', p.vigente_desde,
             'obs', p.obs, 'criado_em', p.criado_em, 'criado_por_nome', pc.nome,
             'anulado_em', p.anulado_em, 'anulado_por_nome', pa.nome, 'anulado_motivo', p.anulado_motivo,
             'vigente_hoje', p.anulado_em is null and p.id = (mkt_mensageria.custo_estimado(p.ferramenta_id, p.canal, p.tipo,
                                                               now(), 0, 0)).preco_id)
           order by lower(f.nome), p.canal, p.tipo nulls first, p.vigente_desde desc, p.id desc), '[]'::jsonb)
      from mkt_mensageria.precos p
      join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id
      left join public.perfis pc on pc.id = p.criado_por
      left join public.perfis pa on pa.id = p.anulado_por));
end
$$;
revoke all on function public.mkt_msg_precos_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_precos_listar() to authenticated;

-- Cadastra uma vigência. Não edita (com "id" recusa). Campos: ferramenta_id, canal, tipo (só whatsapp_api, e lá
-- obrigatório), base_cobranca (entregues|tamanho_lista|mensalidade), preco_centavos ("8", "6,5", 0.36 → até 4 casas;
-- mensalidade = 0), vigente_desde (aaaa-mm-dd), obs?. Nenhum campo de regra tem valor assumido: faltou = erro.
create function public.mkt_msg_preco_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_base text := lower(btrim(coalesce(p ->> 'base_cobranca', '')));
  v_preco_txt text := replace(btrim(coalesce(p ->> 'preco_centavos', '')), ',', '.');
  v_preco numeric;
  v_vig_txt text := btrim(coalesce(p ->> 'vigente_desde', ''));
  v_vig date;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_id bigint;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do preço ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null then
    return jsonb_build_object('ok', false, 'msg', 'Preço não se edita: anule o errado (com motivo) e cadastre outro.');
  end if;
  if v_ferr_txt ~ '^[0-9]{1,18}$' then
    select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
  end if;
  if v_ferr is null then e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.'); end if;
  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  elsif v_canal = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal <> 'whatsapp_api' and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  end if;
  if v_base not in ('entregues', 'tamanho_lista', 'mensalidade') then
    e := e || jsonb_build_object('campo', 'base_cobranca', 'msg', 'Base de cobrança: por entregue, por tamanho da lista ou mensalidade.');
  end if;
  if v_preco_txt !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' then
    e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço em centavos, até 4 casas (ex.: 8 ou 6,5).');
  else
    v_preco := v_preco_txt::numeric;
    if v_preco > 100000 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço acima de R$ 1.000,00 por mensagem: confira.');
    elsif v_base = 'mensalidade' and v_preco <> 0 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg',
        'Na mensalidade o custo por disparo é 0: o valor mensal vai no cadastro da ferramenta.');
    end if;
  end if;
  if v_vig_txt ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    begin
      v_vig := v_vig_txt::date;
    exception when others then
      v_vig := null;
    end;
  end if;
  if v_vig is null or v_vig < date '2020-01-01' or v_vig > date '2100-12-31' then
    e := e || jsonb_build_object('campo', 'vigente_desde', 'msg', 'Vigente desde: data válida (aaaa-mm-dd).');
  end if;
  if length(v_obs) > 500 then e := e || jsonb_build_object('campo', 'obs', 'msg', 'Observação: até 500 caracteres.'); end if;
  if jsonb_array_length(e) > 0 then
    return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
  end if;
  begin
    insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs, criado_por)
    values (v_ferr, v_canal, v_tipo, v_base, v_preco, v_vig, v_obs, (select auth.uid()))
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg',
      'Já existe preço válido para esta ferramenta, canal e tipo com vigência em ' || to_char(v_vig, 'DD/MM/YYYY') || ': anule-o antes.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Preço cadastrado.', 'id', v_id);
end
$$;
revoke all on function public.mkt_msg_preco_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_salvar(jsonb) to authenticated;

create function public.mkt_msg_preco_anular(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anulação (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.precos set anulado_em = now(), anulado_por = (select auth.uid()), anulado_motivo = v_motivo
   where id = p_id and anulado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.precos where id = p_id) then 'Preço já anulado.' else 'Preço não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Preço anulado. O custo estimado dos disparos dessa vigência foi recalculado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_preco_anular(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_anular(bigint, text) to authenticated;

-- Porteiro barato da rota: confere fonte + chave ANTES de a rota ler o corpo (até 5 MB). Só service_role.
-- true = fonte cadastrada e chave certa (ativa ou não: a fonte desligada é recusada e registrada por api_receber).
create function public.mkt_msg_api_chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  return exists (select 1 from mkt_mensageria.fontes f where f.chave = v_fonte)
         and mkt_mensageria.chave_ok(v_fonte, p_chave);
end
$$;
revoke all on function public.mkt_msg_api_chave_ok(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_chave_ok(text, text) to service_role;

-- Recusas para a tela (só admin/dev): SEM o payload. Mais recentes primeiro, até 500.
create function public.mkt_msg_recusas_listar(p_fonte text default null, p_limite integer default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := nullif(btrim(coalesce(p_fonte, '')), '');
  v_lim integer := least(greatest(coalesce(p_limite, 200), 1), 500);
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'limite', v_lim, 'recusas', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'fonte', r.fonte, 'execucao_id', r.execucao_id, 'posicao', r.posicao, 'id_externo', r.id_externo,
             'motivo', r.motivo, 'criado_em', r.criado_em, 'anonimizada', r.anonimizado_em is not null,
             'anonimizado_em', r.anonimizado_em, 'expurgada', r.expurgado_em is not null)
           order by r.criado_em desc, r.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.recusas x
             where v_fonte is null or x.fonte = v_fonte
             order by x.criado_em desc, x.id desc limit v_lim) r));
end
$$;
revoke all on function public.mkt_msg_recusas_listar(text, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_recusas_listar(text, integer) to authenticated;

-- Recebe um lote da fonte (rota POST /api/mensageria/receber, com service_role). Só service_role executa.
-- Chave errada, fonte desconhecida ou inativa: {ok:false, erro:'nao_autorizado'} (a rota devolve 401 genérico).
-- Inativa com chave certa grava execução 'fonte_inativa'. Lote: array de até 1.000 itens; vazio = "rodei, nada novo".
create function public.mkt_msg_api_receber(p_fonte text, p_chave text, p_lote jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inicio timestamptz := clock_timestamp();
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  r jsonb;
  v_n integer;
  v_status text;
  v_exec bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if not v_ativa then
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'fonte_inativa', 'Fonte desligada em mkt_mensageria.fontes: lote não lido.');
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    v_n := case when jsonb_typeof(p_lote) = 'array' then jsonb_array_length(p_lote) end;
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'lote_invalido',
            case when v_n is null then 'Lote não é um array JSON.' else 'Lote de ' || v_n || ' itens (máximo 1.000).' end);
    return jsonb_build_object('ok', false, 'erro', case when v_n is null then 'lote_invalido' else 'lote_grande' end, 'limite', 1000);
  end if;

  r := mkt_mensageria.api_upsert(v_fonte, p_lote);
  v_status := case when (r ->> 'lidos')::int = (r ->> 'inseridos')::int + (r ->> 'atualizados')::int
                                              + (r ->> 'inalterados')::int + (r ->> 'recusados')::int
                   then 'ok' else 'inconsistente' end;
  insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status)
  values (v_fonte, v_inicio, clock_timestamp(), (r ->> 'lidos')::int, (r ->> 'inseridos')::int, (r ->> 'atualizados')::int,
          (r ->> 'inalterados')::int, (r ->> 'recusados')::int, v_status)
  returning id into v_exec;
  insert into mkt_mensageria.recusas (execucao_id, fonte, posicao, id_externo, motivo, payload)
  select v_exec, v_fonte, (x ->> 'posicao')::int, left(x ->> 'id_externo', 200), left(x ->> 'motivo', 500), x -> 'payload'
    from jsonb_array_elements(r -> 'recusas') x;
  return jsonb_build_object('ok', true, 'execucao_id', v_exec, 'status', v_status,
    'lidos', (r ->> 'lidos')::int, 'inseridos', (r ->> 'inseridos')::int, 'atualizados', (r ->> 'atualizados')::int,
    'inalterados', (r ->> 'inalterados')::int, 'recusados', (r ->> 'recusados')::int,
    'recusas', (select coalesce(jsonb_agg(x - 'payload'), '[]'::jsonb)
                  from (select x from jsonb_array_elements(r -> 'recusas') x limit 100) s));
end
$$;
revoke all on function public.mkt_msg_api_receber(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_receber(text, text, jsonb) to service_role;

-- Reconciliação diária: a fonte manda os id_externo que ela enviou no dia (São Paulo); grava quantos estão no log e
-- quais faltam (até 500). Mesma autenticação de api_receber; fonte inativa = nao_autorizado.
create function public.mkt_msg_api_reconciliar(p_fonte text, p_chave text, p_dia date, p_ids jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_fonte_qtd integer;
  v_log integer;
  v_falt_total integer;
  v_falt jsonb;
  v_id bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not v_ativa or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_dia is null or p_dia > v_hoje or p_dia < v_hoje - 400 then
    return jsonb_build_object('ok', false, 'erro', 'dia_invalido');
  end if;
  if p_ids is null or jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) > 20000 then
    return jsonb_build_object('ok', false, 'erro', 'ids_invalidos', 'limite', 20000);
  end if;
  with ids as (
    select distinct left(btrim(x), 200) as id from jsonb_array_elements_text(p_ids) x where btrim(x) <> ''
  ), falt as (
    select i.id from ids i
     where not exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = v_fonte and d.id_externo = i.id)
  )
  select (select count(*) from ids), (select count(*) from falt),
         (select coalesce(jsonb_agg(s.id order by s.id), '[]'::jsonb) from (select id from falt order by id limit 500) s)
    into v_fonte_qtd, v_falt_total, v_falt;
  select count(*) into v_log from mkt_mensageria.disparos d
   where d.enviado_em >= p_dia::timestamp at time zone 'America/Sao_Paulo'
     and d.enviado_em < (p_dia + 1)::timestamp at time zone 'America/Sao_Paulo'
     and d.origem_sistema = v_fonte and d.arquivado_em is null;
  insert into mkt_mensageria.reconciliacao (fonte, dia, contagem_fonte, contagem_log, faltantes_total, faltantes)
  values (v_fonte, p_dia, v_fonte_qtd, v_log, v_falt_total, v_falt)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'dia', p_dia, 'contagem_fonte', v_fonte_qtd, 'contagem_log', v_log,
                            'faltantes_total', v_falt_total, 'faltantes', v_falt);
end
$$;
revoke all on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) to service_role;

-- Saúde das integrações: uma linha por fonte. Atraso pela mesma regra do vigia (mkt_mensageria.fonte_atraso).
create function public.mkt_msg_integracoes_saude() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'agora', now(), 'fontes', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'chave', f.chave, 'nome', f.nome, 'ferramenta_id', f.ferramenta_id, 'ferramenta', fe.nome,
             'ativa', f.ativa, 'ativa_desde', f.ativa_desde,
             'intervalo_minutos', (extract(epoch from f.intervalo_esperado) / 60)::int,
             'ultima_execucao_em', ue.inicio, 'ultima_execucao_status', ue.status,
             'ultima_ok_em', a.ultima_ok_em,
             'atraso_minutos', (extract(epoch from a.atraso) / 60)::int, 'atrasada', a.atrasada,
             'execucoes_7d', s.execucoes, 'recusas_7d', s.recusas, 'inconsistentes_7d', s.inconsistentes,
             'negadas_7d', s.negadas,
             'chave_no_vault', exists (select 1 from vault.secrets v where v.name = 'mkt_msg_fonte_' || f.chave),
             'vigia_jobname', mkt_mensageria.fonte_jobname(f.chave),
             'ultima_reconciliacao', case when rc.id is not null then jsonb_build_object(
                'dia', rc.dia, 'contagem_fonte', rc.contagem_fonte, 'contagem_log', rc.contagem_log,
                'faltantes_total', rc.faltantes_total, 'em', rc.criado_em) end)
           order by f.chave), '[]'::jsonb)
      from mkt_mensageria.fontes f
      left join mkt_mensageria.ferramentas fe on fe.id = f.ferramenta_id
      cross join lateral mkt_mensageria.fonte_atraso(f.chave) a
      left join lateral (select e.inicio, e.status from mkt_mensageria.execucoes e
                          where e.fonte = f.chave order by e.inicio desc limit 1) ue on true
      left join lateral (select count(*) as execucoes, coalesce(sum(e.recusados), 0) as recusas,
                                count(*) filter (where e.status = 'inconsistente') as inconsistentes,
                                count(*) filter (where e.status in ('fonte_inativa', 'lote_invalido')) as negadas
                           from mkt_mensageria.execucoes e
                          where e.fonte = f.chave and e.inicio >= now() - interval '7 days') s on true
      left join lateral (select r.* from mkt_mensageria.reconciliacao r
                          where r.fonte = f.chave order by r.dia desc, r.id desc limit 1) rc on true));
end
$$;
revoke all on function public.mkt_msg_integracoes_saude() from public, anon, authenticated;
grant execute on function public.mkt_msg_integracoes_saude() to authenticated;

-- ─── 9. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  fn record;
  v_tela text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                         'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                         'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                         'mkt_msg_historico', 'mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa',
                         'mkt_msg_precos_listar', 'mkt_msg_preco_salvar', 'mkt_msg_preco_anular', 'mkt_msg_integracoes_saude',
                         'mkt_msg_recusas_listar'];
  v_api text[] := array['mkt_msg_api_receber', 'mkt_msg_api_reconciliar', 'mkt_msg_api_chave_ok'];
  v_admin text[] := array['mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa', 'mkt_msg_recusas_listar'];
begin
  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind in ('r', 'S') loop
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if (select c.relkind from pg_class c where c.oid = t::regclass) = 'r'
         and has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005o: % tem privilégio em %', r, t;
      end if;
    end loop;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005o: PUBLIC tem privilégio em %', t;
    end if;
    if (select c.relkind = 'r' and not c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005o: RLS desligada em %', t;
    end if;
  end loop;

  for fn in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (fn.proconfig @> array['search_path=""']) then
      raise exception '20261005o: % sem search_path vazio', fn.sig;
    end if;
    if has_function_privilege('anon', fn.sig, 'execute') then
      raise exception '20261005o: anon executa %', fn.sig;
    end if;
    if fn.proacl is null or exists (select 1 from aclexplode(fn.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005o: PUBLIC executa %', fn.sig;
    end if;
    if (fn.pronamespace = 'public'::regnamespace and fn.proname = any(v_tela)) <> has_function_privilege('authenticated', fn.sig, 'execute') then
      raise exception '20261005o: grant de authenticated errado em %', fn.sig;
    end if;
    if fn.proname = any(v_api) and not has_function_privilege('service_role', fn.sig, 'execute') then
      raise exception '20261005o: service_role não executa %', fn.sig;
    end if;
    if fn.pronamespace = 'public'::regnamespace and not fn.prosecdef then
      raise exception '20261005o: % deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.pronamespace = 'mkt_mensageria'::regnamespace and fn.prosecdef then
      raise exception '20261005o: interna % não deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.proname = any(v_tela) and not (fn.proname = any(v_admin))
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda mkt.pode_ver', fn.sig;
    end if;
    if fn.proname = any(v_admin) and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda gp_is_admin', fn.sig;
    end if;
    if fn.proname = any(v_api) and position('if coalesce(auth.role(), '''') <> ''service_role'' then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda de service_role', fn.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 20
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_tela || v_api)) <> 20 then
    raise exception '20261005o: esperava exatamente 20 funções public.mkt_msg_* (sobrecarga?)';
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria'
                and ((table_name = 'precos' and column_name in ('ferramenta_id', 'canal', 'tipo', 'base_cobranca', 'preco_centavos', 'vigente_desde'))
                  or (table_name = 'fontes' and column_name in ('ativa', 'intervalo_esperado', 'ferramenta_id'))
                  or (table_name = 'disparos' and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'projeto_id')))
                and column_default is not null) then
    raise exception '20261005o: coluna de regra com default';
  end if;
  if (select count(*) from mkt_mensageria.precos) <> 7
     or exists (select 1 from mkt_mensageria.precos p join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id where f.nome = 'Infobip') then
    raise exception '20261005o: seed de preços diferente do esperado (7 linhas, Infobip sem preço)';
  end if;
  if (select count(*) from mkt_mensageria.fontes where not ativa) <> 5 or (select count(*) from mkt_mensageria.fontes) <> 5 then
    raise exception '20261005o: seed de fontes diferente do esperado (5, todas desligadas)';
  end if;
  if (select count(*) from vault.secrets s join mkt_mensageria.fontes f on s.name = 'mkt_msg_fonte_' || f.chave) <> 5 then
    raise exception '20261005o: faltou chave no Vault';
  end if;
  if (select count(*) from cron.job j join mkt_mensageria.fontes f on j.jobname = mkt_mensageria.fonte_jobname(f.chave)
       where not j.active) <> 5
     or (select count(*) from ops.rotina o join mkt_mensageria.fontes f on o.jobname = mkt_mensageria.fonte_jobname(f.chave)) <> 5 then
    raise exception '20261005o: jobs do vigia das fontes (5 desligados + 5 em ops.rotina) diferente do esperado';
  end if;
  if not exists (select 1 from cron.job j join ops.rotina o using (jobname) where j.jobname = 'mensageria-recusas-expurgo' and j.active) then
    raise exception '20261005o: job de expurgo das recusas ausente (cron.job ativo + ops.rotina)';
  end if;
  if exists (select 1 from cron.job where jobname = 'ingest-mensageria-hourly' and active) then
    raise exception '20261005o: ingest-mensageria-hourly continua ativo';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação) ═══════════════════════════════════════════════════════════════════════════════════════
-- Só o cron antigo (P3), sem mexer no resto:
--   select cron.alter_job((select jobid from cron.job where jobname = 'ingest-mensageria-hourly'), active := true);
--   update ops.rotina set silenciado_ate = null where jobname = 'ingest-mensageria-hourly';
-- Desligar uma fonte sem deploy: update mkt_mensageria.fontes set ativa = false where chave = '<fonte>';
-- Tudo (exportar antes recusas/execucoes; disparos de origem api precisam de projeto antes de voltar o NOT NULL):
-- begin;
-- select cron.unschedule(j.jobname) from cron.job j where j.jobname like 'mensageria-fonte-%' or j.jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina_estado where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from vault.secrets where name like 'mkt\_msg\_fonte\_%';
-- drop function public.mkt_msg_api_receber(text, text, jsonb), public.mkt_msg_api_reconciliar(text, text, date, jsonb),
--   public.mkt_msg_integracoes_saude(), public.mkt_msg_precos_listar(), public.mkt_msg_preco_salvar(jsonb),
--   public.mkt_msg_preco_anular(bigint, text), public.mkt_msg_anonimizar_recusa(bigint, text),
--   public.mkt_msg_api_chave_ok(text, text), public.mkt_msg_recusas_listar(text, integer);
-- -- reaplicar da 20261005n: mkt_msg_disparos_listar, mkt_msg_disparo_salvar, mkt_msg_disparo_lancar_retorno,
-- --   mkt_msg_historico, mkt_msg_anonimizar_disparo, mkt_mensageria.trg_historico (create or replace)
-- drop table mkt_mensageria.recusas, mkt_mensageria.reconciliacao, mkt_mensageria.execucoes, mkt_mensageria.fontes,
--   mkt_mensageria.precos;
-- drop function mkt_mensageria.api_upsert(text, jsonb), mkt_mensageria.api_item(text, bigint, jsonb),
--   mkt_mensageria.chave_ok(text, text), mkt_mensageria.vigiar_fonte(text), mkt_mensageria.fonte_atraso(text),
--   mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean),
--   mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer), mkt_mensageria.fonte_jobname(text),
--   mkt_mensageria.trg_preco_anular(), mkt_mensageria.trg_fonte(), mkt_mensageria.trg_recusa_anonimizar(),
--   mkt_mensageria.recusas_expurgar();
-- alter table mkt_mensageria.historico drop column por_api;
-- alter table mkt_mensageria.disparos drop column campanha, drop column anonimizado_em, drop constraint disparos_projeto_fora_da_api;
-- alter table mkt_mensageria.disparos alter column projeto_id set not null;   -- falha se houver linha da API sem projeto
-- commit;

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito; chave nunca impressa) ═════
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projetos (2 siglas reais), ferramentas e a chave da fonte unichat (lida do Vault DENTRO da transação abortada).
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as proj1,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla1,
         (select pr.sigla from mkt.projetos pr order by pr.id offset 1 limit 1) as sigla2,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Unichat') as unichat,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Infobip') as infobip,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Ligue Lead') as liguelead,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Clint') as clint,
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_unichat') as chave;
grant all on _z_ref to public;
create temp table _z_ids (nome text primary key, id bigint) on commit drop;
grant all on _z_ids to public;
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
-- Como a rota chama: PostgREST com a service_role key (role service_role, claims role = service_role).
create function pg_temp.como_servico() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;
-- Item de lote da API (unichat, WhatsApp). p_extra sobrepõe/acrescenta campos.
create function pg_temp.item(p_id text, p_campanha text, p_extra jsonb default '{}') returns jsonb language sql as $f$
  select jsonb_build_object('id_externo', p_id, 'campanha', p_campanha, 'canal', 'whatsapp_api', 'tipo', 'marketing',
           'enviado_em', '2026-09-15T10:00:00-03:00', 'copy_texto', 'Copy ' || p_id, 'publico_lista', 'Lista ' || p_id,
           'tamanho_lista', 100, 'entregues', 90, 'lidas', 50) || p_extra
$f$;

-- ═══ BLOCO 2: volume + explain (analyze, buffers) das consultas quentes ════════════════════════════════════════════
-- 10.000 disparos (um a cada 52 min, ≈ 361 dias), ferramenta coerente com o canal (Unichat, ActiveCampaign, Ligue Lead
-- ou Infobip, Clint, SendFlow), 1/10 de origem api sem projeto. 3.000 vigências sintéticas de preço (3 ferramentas ×
-- 2 canais × 500 dias) para o índice de preço ter o que filtrar. 10.000 execuções (2.000 por fonte).
insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, tipo, copy_texto, publico_lista,
       tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por, origem, origem_sistema, id_externo, campanha)
select now() - i * interval '52 minutes',
       case when i % 10 = 0 then null else pr.ids[1 + i % array_length(pr.ids, 1)] end,
       c.canal,
       case c.canal when 'whatsapp_api' then r.unichat when 'email' then r.activecampaign
                    when 'sms' then case when i % 2 = 0 then r.liguelead else r.infobip end
                    when 'ligacao' then r.clint else r.sendflow end,
       case when c.canal = 'whatsapp_api' then (array['utility', 'marketing'])[1 + (i / 5) % 2] end,
       'Copy sintética ' || i, 'Lista ' || (i % 37), 100 + i % 900,
       case when i % 7 = 0 then null else 50 + i % 50 end,
       case when i % 7 = 0 then null else i % 50 end,
       case when i % 7 = 0 then null else i % 10 end,
       case when i % 7 = 0 then null else i % 5 end,
       case when i % 3 = 0 then i % 2000 end,
       'Ensaio',
       case when i % 10 = 0 then 'api' else 'manual' end,
       case when i % 10 = 0 then 'unichat' end,
       case when i % 10 = 0 then 'E' || i end,
       case when i % 10 = 0 then 'Campanha ' || i end
  from generate_series(1, 10000) i
  cross join lateral (select (array['whatsapp_api', 'email', 'sms', 'ligacao', 'grupo'])[1 + i % 5] as canal) c
  cross join (select array_agg(id order by id) as ids from mkt.projetos) pr
  cross join pg_temp._z_ref r;

insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs)
select f.id, c.canal, null, 'entregues', (d % 50)::numeric / 10, date '2025-01-01' + d, 'Ensaio'
  from (select id from mkt_mensageria.ferramentas where nome in ('n8n', 'Google Drive', 'Slack')) f
  cross join (values ('sms'), ('ligacao')) c(canal)
  cross join generate_series(0, 499) d;

insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status)
select f.chave, now() - i * interval '1 hour', now() - i * interval '1 hour' + interval '2 seconds', 10, 5, 3, 1, 1,
       case when i % 50 = 0 then 'inconsistente' else 'ok' end
  from mkt_mensageria.fontes f cross join generate_series(1, 2000) i;

insert into mkt_mensageria.recusas (execucao_id, fonte, posicao, id_externo, motivo, payload, criado_em)
select (select max(id) from mkt_mensageria.execucoes), 'unichat', 1, 'R' || i, 'Ensaio: recusa sintética', '{"x":1}',
       now() - i * interval '6 minutes'
  from generate_series(1, 20000) i;   -- ≈ 83 dias de recusas, uma a cada 6 min
analyze mkt_mensageria.recusas;
analyze mkt_mensageria.disparos;
analyze mkt_mensageria.precos;
analyze mkt_mensageria.execucoes;
analyze mkt_mensageria.historico;

create function pg_temp.plano(p_passo text, p_sql text, p_indice text) returns void language plpgsql as $f$
declare
  l text;
  v text := '';
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
    v := v || l || E'\n';
  end loop;
  if v !~ p_indice then
    raise exception '% FALHOU: o plano não usa %:%', p_passo, p_indice, E'\n' || v;
  end if;
  if v ~ 'Seq Scan on (disparos|precos|execucoes)' then
    raise exception '% FALHOU: Seq Scan numa tabela quente:%', p_passo, E'\n' || v;
  end if;
  perform pg_temp.ok(p_passo, 'usa ' || substring(v from p_indice));
end
$f$;

do $e$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  -- MESMO texto do corpo de mkt_msg_disparos_listar (20261005o), com os valores no lugar das variáveis
  v_q text := $q$
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, d.campanha, ce.centavos as custo_estimado,
             case when d.custo_centavos is not null then 'real'
                  when ce.centavos is not null then 'estimado'
                  when not ce.tem_preco then 'sem_preco' end as custo_fonte,
             mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos, ce.centavos,
                                          ce.tem_preco) as pendencias
        from mkt_mensageria.disparos d
        cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em, d.entregues,
                                                         d.tamanho_lista) ce
       where d.enviado_em >= %1$L::timestamptz and d.enviado_em < %2$L::timestamptz
         and d.arquivado_em is null
         and (%3$L::bigint is null or d.projeto_id = %3$L::bigint)
         and (null::text is null)
         and (null::bigint is null)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object('id', b.id, 'projeto', pr.sigla, 'ferramenta', f.nome, 'numero', nu.numero,
                 'pendencias', to_jsonb(b.pendencias), 'campanha', b.campanha, 'custo_estimado_centavos', b.custo_estimado,
                 'custo_fonte', b.custo_fonte) order by b.enviado_em desc, b.id desc)
          from pagina b
          left join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (select jsonb_build_object('qtd', count(*), 'custo_total_centavos', sum(coalesce(b.custo_centavos, b.custo_estimado)),
                        'sem_preco', count(*) filter (where 'sem_preco' = any(b.pendencias))) from base b),
      'por_canal', (select jsonb_agg(c) from (select b.canal, count(*), sum(b.custo_estimado) from base b group by b.canal) c))
  $q$;
  v_ini timestamptz := (v_hoje - 29)::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (v_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  perform pg_temp.plano('E1 listar 30 dias', format(v_q, v_ini, v_fim, null), 'disparos_enviado_idx');
  perform pg_temp.plano('E1b listar 366 dias + projeto', format(v_q, (v_hoje - 365)::timestamp at time zone 'America/Sao_Paulo', v_fim,
                        (select proj1 from pg_temp._z_ref)), 'disparos_(projeto_)?enviado_idx');
  -- Corpo de mkt_mensageria.custo_estimado com valores reais (Unichat, marketing, hoje)
  perform pg_temp.plano('E2 preço vigente (Unichat)', format($q$
    select p.id, p.base_cobranca, p.preco_centavos
      from mkt_mensageria.precos p
     where p.ferramenta_id = %1$s and p.canal = 'whatsapp_api' and coalesce(p.tipo, '') = coalesce('marketing', '')
       and p.vigente_desde <= (now() at time zone 'America/Sao_Paulo')::date and p.anulado_em is null
     order by p.vigente_desde desc limit 1 $q$, (select unichat from pg_temp._z_ref)), 'precos_vigencia_unica');
  perform pg_temp.plano('E2b preço vigente (500 vigências)', format($q$
    select p.id, p.base_cobranca, p.preco_centavos
      from mkt_mensageria.precos p
     where p.ferramenta_id = %1$s and p.canal = 'sms' and coalesce(p.tipo, '') = coalesce(null::text, '')
       and p.vigente_desde <= date '2025-08-01' and p.anulado_em is null
     order by p.vigente_desde desc limit 1 $q$, (select id from mkt_mensageria.ferramentas where nome = 'Slack')), 'precos_vigencia_unica');
  -- api_item: o lookup por (origem_sistema, id_externo)
  perform pg_temp.plano('E3 api_item lookup', $q$
    select * from mkt_mensageria.disparos x where x.origem_sistema = 'unichat' and x.id_externo = 'E5000' $q$, 'disparos_externo_unico');
  -- saúde/vigia: última execução ok da fonte
  perform pg_temp.plano('E4 última execução ok', $q$
    select e.fim from mkt_mensageria.execucoes e where e.fonte = 'unichat' and e.status = 'ok'
     order by e.inicio desc limit 1 $q$, 'execucoes_fonte_inicio_idx');
  -- recusas_listar (admin): as 200 mais recentes
  perform pg_temp.plano('E5 recusas_listar', $q$
    select * from mkt_mensageria.recusas x where null::text is null or x.fonte = null::text
     order by x.criado_em desc, x.id desc limit 200 $q$, 'recusas_criado_idx');
  -- expurgo: as 5.000 mais antigas com mais de 30 dias
  perform pg_temp.plano('E6 expurgo (seleção)', $q$
    select x.id from mkt_mensageria.recusas x
     where x.criado_em < now() - interval '30 days' and x.expurgado_em is null and x.anonimizado_em is null
     order by x.criado_em limit 5000 $q$, 'recusas_criado_idx');
end
$e$;

-- Tempo real das funções, chamadas como a tela chama (admin logado). Teto do PostgREST: statement_timeout 8 s.
select pg_temp.como_admin();
do $t$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t0 timestamptz;
  r jsonb;
begin
  t0 := clock_timestamp(); r := public.mkt_msg_disparos_listar(v_hoje - 29, v_hoje);
  perform pg_temp.ok('V1 listar 30 dias', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'linhas') || ' linhas, qtd=' || (r -> 'totais' ->> 'qtd') || ', sem_preco=' || (r -> 'totais' ->> 'sem_preco')
    || ', sem_projeto=' || (r -> 'totais' ->> 'sem_projeto') || ', com_estimativa=' || (r -> 'totais' ->> 'com_estimativa')
    || ', ' || pg_size_pretty(length(r::text)::bigint));
  t0 := clock_timestamp(); r := public.mkt_msg_disparos_listar(v_hoje - 365, v_hoje);
  perform pg_temp.ok('V2 listar 366 dias (pior caso)', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'linhas') || ' linhas, qtd=' || (r -> 'totais' ->> 'qtd') || ', truncado=' || (r ->> 'truncado')
    || ', ' || pg_size_pretty(length(r::text)::bigint));
  if (r -> 'totais' ->> 'qtd')::int < 9000 or jsonb_array_length(r -> 'linhas') <> 500 then
    raise exception 'V2 FALHOU: qtd=% linhas=%', r -> 'totais' ->> 'qtd', jsonb_array_length(r -> 'linhas');
  end if;
  t0 := clock_timestamp(); r := public.mkt_msg_integracoes_saude();
  perform pg_temp.ok('V3 integracoes_saude', round(extract(epoch from clock_timestamp() - t0) * 1000, 1) || ' ms, '
    || jsonb_array_length(r -> 'fontes') || ' fontes, inconsistentes_7d(unichat)='
    || (select x ->> 'inconsistentes_7d' from jsonb_array_elements(r -> 'fontes') x where x ->> 'chave' = 'unichat'));
end
$t$;
reset role;

-- V4. Custo isolado do estimado por linha (10.000 linhas): varredura pura × varredura + custo_estimado
do $v4$
declare
  t0 timestamptz;
  a numeric;
  b numeric;
  n bigint;
begin
  t0 := clock_timestamp();
  select count(*) into n from mkt_mensageria.disparos d where d.enviado_em >= now() - interval '366 days' and d.arquivado_em is null;
  a := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  t0 := clock_timestamp();
  select count(ce.centavos) into n from mkt_mensageria.disparos d
   cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em, d.entregues, d.tamanho_lista) ce
   where d.enviado_em >= now() - interval '366 days' and d.arquivado_em is null;
  b := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.ok('V4 custo do estimado', 'varredura 10.000 linhas ' || a || ' ms; com custo_estimado por linha ' || b
    || ' ms (' || n || ' com estimativa)');
end
$v4$;

-- V5. Expurgo real (até 5.000 por execução) com 20.000 recusas
do $v5$
declare t0 timestamptz; n integer;
begin
  t0 := clock_timestamp(); n := mkt_mensageria.recusas_expurgar();
  perform pg_temp.ok('V5 recusas_expurgar', round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, ' || n || ' expurgadas (teto 5.000)');
end
$v5$;

-- Fim do bloco 2: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005o BLOCO 2 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.
'
    || (select string_agg(passo || ' | ' || linha, E'
' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 2

-- ▶ BLOCO 3 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
-- ═══ CORPO DA MIGRATION (cópia exata de 20261005o_mkt_mensageria_precos_integracoes.sql) ═══
-- 20261005o: Marketing > Mensageria (etapa 3): preços e custo estimado, infra comum das integrações, pausa do cron antigo
--
-- STATUS: ESCRITA, NÃO APLICADA. Ensaio: 20261005o_ensaio.sql. Medições e contrato: 20261005o.explain.md.
--
-- O QUE FAZ
--   P1 Preços. mkt_mensageria.precos (por ferramenta, canal, tipo e vigência; não se edita nem apaga: preço errado é
--      ANULADO com motivo). Custo estimado calculado NA LEITURA por UMA função (mkt_mensageria.custo_estimado: preço
--      vigente no dia de enviado_em, em São Paulo). custo_centavos (real) sempre prevalece. Sem preço = 'sem_preco',
--      nunca 0 inventado. Seed copiado de controle.custo_mensagem (medido em 05/10; a guarda confere os valores).
--   P2 Integrações. fontes (ligar/desligar sem deploy), execucoes, recusas, reconciliacao; chave por fonte no Vault
--      (nasce aqui, aleatória); RPC public.mkt_msg_api_receber (só service_role) com upsert idempotente por
--      (origem_sistema, id_externo); projeto pela [SIGLA] no nome da campanha (sem sigla = entra sem projeto, pendência
--      'sem_projeto'); public.mkt_msg_integracoes_saude; uma checagem no pg_cron por fonte (ligada só com a fonte
--      ativa) cadastrada em ops.rotina para o vigia avisar no Slack quando passar 2× o intervalo sem execução ok.
--      Retenção: payload de recusa expurgado após 30 dias (job diário mensageria-recusas-expurgo, em ops.rotina).
--      Porteiro da rota: public.mkt_msg_api_chave_ok (confere a chave antes de a rota ler o corpo).
--   P3 Pausa o cron 'ingest-mensageria-hourly' (jobid conferido pelo nome) e silencia a rotina dele no vigia.
--      Nada é apagado: controle.mensageria_envio e as views vw_mensageria_* ficam congeladas (última linha 28/08).
--
-- O QUE MUDA NO QUE JÁ EXISTE (20261005n, conferido igual ao banco vivo por md5 na guarda)
--   disparos.projeto_id deixa de ser NOT NULL; CHECK novo exige projeto fora da origem 'api'. Coluna nova campanha.
--   disparos.anonimizado_em (LGPD: a API não regrava linha anonimizada). historico: coluna nova por_api.
--   create or replace (mesma assinatura, sem sobrecarga): mkt_msg_disparos_listar (só ACRESCENTA campos),
--   mkt_msg_disparo_salvar (linha da API: só projeto, tipo e custo), mkt_msg_disparo_lancar_retorno (recusa linha da
--   API), mkt_msg_historico (+por_api), mkt_msg_anonimizar_disparo (+recusas do mesmo id_externo), trg_historico.
--
-- AS 5 PERGUNTAS
--   escala: listar continua limitado ao período (≤ 366 dias) e 500 linhas; o custo estimado é um lookup por linha no
--     índice de preços (precos_vigencia_unica). api_receber: lote ≤ 1.000; um SELECT por item no índice único
--     (origem_sistema, id_externo) + UM insert…on conflict para o lote. saúde: 5 fontes × lookups em
--     execucoes (fonte, inicio desc). reconciliar: ≤ 20.000 ids, anti-join no índice único.
--   índice: precos (ferramenta_id, canal, coalesce(tipo,''), vigente_desde desc) where anulado_em is null;
--     execucoes (fonte, inicio desc); recusas (execucao_id), (fonte, id_externo); reconciliacao (fonte, dia desc).
--     Prova: 20261005o_ensaio.sql bloco 2.
--   frequência: n8n manda lote por fonte no intervalo dela (seed 1 h, ajustável); checagem do vigia a cada 30 min
--     por fonte ATIVA (inativa = job desligado, custo zero).
--   repetição: listar é uma query (CTE materializada); o estimado é calculado uma vez por linha e reaproveitado em
--     linhas, totais e por_canal.
--   reversão: fonte → update mkt_mensageria.fontes set ativa = false (desliga recepção e checagem, sem deploy).
--     Rota → revoke execute on function public.mkt_msg_api_receber(text,text,jsonb) from service_role.
--     Cron antigo → bloco REVERSÃO no fim (alter_job active true + silenciado_ate null).

set local lock_timeout = '3s';
set local statement_timeout = '25s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_esperado jsonb := jsonb_build_object(
    'mkt_msg_disparos_listar', 'a49e66a21ad0e99cd46e9ac15869e4f0',
    'mkt_msg_disparo_salvar', '38a25ac0ce35da08408d5338babf1733',
    'mkt_msg_disparo_lancar_retorno', '07d6e198f3f4b51ca6bf0b61b1c99cea',
    'mkt_msg_historico', '527fd822fb59722c27489527ff5181de',
    'mkt_msg_anonimizar_disparo', '769c74b6a37513d2cc94fd2bb81ae602',
    'trg_historico', '6d94581a614a2dfe05559c6cda64f7c8');
  k text;
  v_md5 text;
begin
  if to_regnamespace('mkt_mensageria') is null then
    raise exception '20261005o: schema mkt_mensageria ausente: aplicar 20261005n antes';
  end if;
  if to_regclass('mkt_mensageria.precos') is not null or to_regclass('mkt_mensageria.fontes') is not null then
    raise exception '20261005o: mkt_mensageria.precos/fontes já existe (migration já aplicada?)';
  end if;
  -- As 6 funções reescritas aqui têm que estar como a 20261005n deixou (senão a reescrita apagaria mudança viva).
  for k in select jsonb_object_keys(v_esperado) loop
    select md5(p.prosrc) into v_md5 from pg_proc p
     where p.proname = k and p.pronamespace in ('public'::regnamespace, 'mkt_mensageria'::regnamespace);
    if v_md5 is distinct from v_esperado ->> k then
      raise exception '20261005o: % no banco difere da 20261005n (md5 %): reler a definição viva antes', k, v_md5;
    end if;
  end loop;
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '20261005o: vault.create_secret / extensions.gen_random_bytes ausente';
  end if;
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    raise exception '20261005o: pg_cron sem alter_job/schedule';
  end if;
  if to_regclass('ops.rotina') is null or to_regclass('ops.rotina_estado') is null then
    raise exception '20261005o: vigia (ops.rotina, ops.rotina_estado) ausente: 20261001a..f';
  end if;
  if to_regprocedure('auth.role()') is null then
    raise exception '20261005o: auth.role() ausente';
  end if;
  if exists (select 1 from mkt_mensageria.disparos where origem = 'api') then
    raise exception '20261005o: já existem disparos de origem api (esperado 0 antes da integração)';
  end if;
  -- Seed de preços é cópia de controle.custo_mensagem medida em 05/10/2026. Mudou lá? Rever o seed antes de aplicar.
  if (select count(*) from controle.custo_mensagem c
       where (c.plataforma, c.categoria, c.preco_base * (1 + coalesce(c.margem_bsp, 0)), c.vigente_desde) in (
             ('api', 'utility', 0.08, date '2026-07-01'), ('api', 'marketing', 0.36, date '2026-07-01'),
             ('unnichat', 'utility', 0.08, date '2026-07-24'), ('unnichat', 'marketing', 0.36, date '2026-07-24'),
             ('sms', 'sms', 0.065, date '2026-07-01'), ('activecampaign', 'email', 0, date '2026-07-29'),
             ('grupo', 'grupo', 0, date '2026-07-01'))) <> 7 then
    raise exception '20261005o: controle.custo_mensagem mudou desde 05/10/2026: rever o seed de preços';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas
       where nome in ('Unichat', 'Ligue Lead', 'ActiveCampaign', 'SendFlow', 'Infobip')) <> 5 then
    raise exception '20261005o: ferramentas do seed ausentes (Unichat, Ligue Lead, ActiveCampaign, SendFlow, Infobip)';
  end if;
end
$guarda$;

-- ─── 1. Mudanças em disparos e historico ─────────────────────────────────────────────────────────────────────────────
-- Projeto: a integração grava sem projeto quando o nome da campanha não traz [SIGLA] cadastrada (fila 'sem_projeto').
-- Tela e planilha continuam obrigadas (disparo_validar + CHECK abaixo).
alter table mkt_mensageria.disparos alter column projeto_id drop not null;
alter table mkt_mensageria.disparos
  add constraint disparos_projeto_fora_da_api check (projeto_id is not null or origem = 'api');
alter table mkt_mensageria.disparos
  add column campanha text check (campanha is null or length(btrim(campanha)) between 1 and 300);
alter table mkt_mensageria.disparos add column anonimizado_em timestamptz;
comment on column mkt_mensageria.disparos.anonimizado_em is 'LGPD: quando mkt_msg_anonimizar_disparo limpou o conteúdo. A integração não toca mais a linha (nem métricas).';
comment on column mkt_mensageria.disparos.campanha is 'Nome da campanha na ferramenta de origem (integração). A [SIGLA] dentro dele define o projeto.';
comment on column mkt_mensageria.disparos.projeto_id is 'Projeto (mkt.projetos). Nulo só em origem api sem [SIGLA] cadastrada no nome da campanha: pendência sem_projeto.';

alter table mkt_mensageria.historico
  add column por_api text check (por_api is null or por_api ~ '^api:[a-z][a-z_]{1,39}$');
comment on column mkt_mensageria.historico.por_api is 'Autor quando a mudança veio da integração (auth.uid() nulo): api:<fonte>.';

-- ─── 2. Preços ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Sem default em nenhuma coluna de regra (canal, tipo, base, preço, vigência): um default desfaz a regra em silêncio no
-- próximo INSERT de vigência. criado_em é carimbo, não regra.
create table mkt_mensageria.precos (
  id              bigint generated always as identity primary key,
  ferramenta_id   bigint not null references mkt_mensageria.ferramentas(id) on delete restrict,
  canal           text not null check (canal in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo')),
  tipo            text check (tipo is null or tipo in ('utility', 'marketing')),
  base_cobranca   text not null check (base_cobranca in ('entregues', 'tamanho_lista', 'mensalidade')),
  preco_centavos  numeric(12, 4) not null check (preco_centavos >= 0 and preco_centavos <= 100000),
  vigente_desde   date not null check (vigente_desde between date '2020-01-01' and date '2100-12-31'),
  obs             text check (obs is null or length(obs) <= 500),
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,      -- nulo só no seed desta migration
  anulado_em      timestamptz,
  anulado_por     uuid references public.perfis(id) on delete set null,
  anulado_motivo  text check (anulado_motivo is null or length(btrim(anulado_motivo)) between 3 and 500),
  constraint precos_tipo_so_na_api check ((canal = 'whatsapp_api') = (tipo is not null)),
  -- mensalidade: o custo é o mensal da ferramenta; por disparo, 0.
  constraint precos_mensalidade_zero check (base_cobranca <> 'mensalidade' or preco_centavos = 0),
  constraint precos_anulacao_completa check ((anulado_em is null) = (anulado_motivo is null))
);
-- Uma vigência válida por (ferramenta, canal, tipo, data); é também o índice da busca do preço vigente
-- (… = … and vigente_desde <= dia order by vigente_desde desc limit 1). coalesce(tipo,'') porque tipo é nulo fora da API.
create unique index precos_vigencia_unica on mkt_mensageria.precos
  (ferramenta_id, canal, coalesce(tipo, ''), vigente_desde desc) where anulado_em is null;
comment on table mkt_mensageria.precos is 'Preço por mensagem (centavos, 4 casas) por ferramenta/canal/tipo e vigência. Não se edita nem apaga: anular com motivo e cadastrar outro.';

-- ─── 3. Integrações: fontes, execucoes, recusas, reconciliacao ───────────────────────────────────────────────────────
create table mkt_mensageria.fontes (
  chave               text primary key check (chave ~ '^[a-z][a-z_]{1,39}$'),
  nome                text not null check (length(btrim(nome)) between 2 and 60),
  ferramenta_id       bigint references mkt_mensageria.ferramentas(id) on delete restrict,   -- nulo: o item diz a ferramenta
  ativa               boolean not null,                     -- sem default: ligar/desligar é decisão explícita
  ativa_desde         timestamptz,                          -- trigger: carimba ao ligar, zera ao desligar
  intervalo_esperado  interval not null check (intervalo_esperado between interval '5 minutes' and interval '7 days'),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint fontes_ativa_desde check (ativa = (ativa_desde is not null))
);
comment on table mkt_mensageria.fontes is 'Sistemas que mandam disparos pela API. ativa=false recusa o lote e desliga a checagem do vigia (sem deploy). Chave no Vault: mkt_msg_fonte_<chave>.';

create table mkt_mensageria.execucoes (
  id           bigint generated always as identity primary key,
  fonte        text not null references mkt_mensageria.fontes(chave) on delete restrict,
  inicio       timestamptz not null,
  fim          timestamptz not null,
  lidos        integer not null check (lidos >= 0),
  inseridos    integer not null check (inseridos >= 0),
  atualizados  integer not null check (atualizados >= 0),
  inalterados  integer not null check (inalterados >= 0),
  recusados    integer not null check (recusados >= 0),
  status       text not null check (status in ('ok', 'inconsistente', 'fonte_inativa', 'lote_invalido')),
  detalhe      text check (detalhe is null or length(detalhe) <= 300),
  constraint execucoes_fim_depois check (fim >= inicio)
);
create index execucoes_fonte_inicio_idx on mkt_mensageria.execucoes (fonte, inicio desc);
comment on table mkt_mensageria.execucoes is 'Uma linha por lote recebido com chave válida. inconsistente = lidos ≠ inseridos+atualizados+inalterados+recusados. Só acréscimo.';

create table mkt_mensageria.recusas (
  id                  bigint generated always as identity primary key,
  execucao_id         bigint not null references mkt_mensageria.execucoes(id) on delete restrict,
  fonte               text not null references mkt_mensageria.fontes(chave) on delete restrict,
  posicao             integer not null check (posicao >= 1),
  id_externo          text check (id_externo is null or length(id_externo) <= 200),
  motivo              text not null check (length(motivo) between 3 and 500),
  payload             jsonb not null,
  criado_em           timestamptz not null default now(),
  anonimizado_em      timestamptz,
  anonimizado_por     uuid,
  anonimizado_motivo  text check (anonimizado_motivo is null or length(btrim(anonimizado_motivo)) between 3 and 500),
  expurgado_em        timestamptz                           -- retenção: payload trocado por {"expurgado":true} após 30 dias
);
create index recusas_execucao_idx on mkt_mensageria.recusas (execucao_id);
create index recusas_externo_idx on mkt_mensageria.recusas (fonte, id_externo) where id_externo is not null;
create index recusas_criado_idx on mkt_mensageria.recusas (criado_em desc);
comment on table mkt_mensageria.recusas is 'Item do lote que não entrou, com o motivo e o item recebido (payload). LGPD: mkt_msg_anonimizar_disparo (mesmo id_externo), mkt_msg_anonimizar_recusa e expurgo do payload após 30 dias (job mensageria-recusas-expurgo). Leitura sem payload: mkt_msg_recusas_listar (admin).';

create table mkt_mensageria.reconciliacao (
  id               bigint generated always as identity primary key,
  fonte            text not null references mkt_mensageria.fontes(chave) on delete restrict,
  dia              date not null,
  contagem_fonte   integer not null check (contagem_fonte >= 0),
  contagem_log     integer not null check (contagem_log >= 0),
  faltantes_total  integer not null check (faltantes_total >= 0),
  faltantes        jsonb not null check (jsonb_typeof(faltantes) = 'array'),   -- até 500 id_externo
  criado_em        timestamptz not null default now()
);
create index reconciliacao_fonte_dia_idx on mkt_mensageria.reconciliacao (fonte, dia desc, id desc);
comment on table mkt_mensageria.reconciliacao is 'Conferência diária: quantos a fonte diz que enviou x quantos estão no log, e os id_externo que faltam. Só acréscimo.';

alter table mkt_mensageria.precos enable row level security;
alter table mkt_mensageria.fontes enable row level security;
alter table mkt_mensageria.execucoes enable row level security;
alter table mkt_mensageria.recusas enable row level security;
alter table mkt_mensageria.reconciliacao enable row level security;
revoke all on mkt_mensageria.precos, mkt_mensageria.fontes, mkt_mensageria.execucoes, mkt_mensageria.recusas,
              mkt_mensageria.reconciliacao from public, anon, authenticated;
revoke all on all sequences in schema mkt_mensageria from public, anon, authenticated;

-- ─── 4. Funções internas (revoke de todos logo após cada create) ─────────────────────────────────────────────────────
create function mkt_mensageria.fonte_jobname(p_chave text) returns text
language sql immutable set search_path = '' as $$
  select 'mensageria-fonte-' || replace(p_chave, '_', '-');
$$;
revoke all on function mkt_mensageria.fonte_jobname(text) from public, anon, authenticated;

-- A ÚNICA regra de custo estimado. Preço vigente = a vigência não anulada mais recente com vigente_desde ≤ dia do
-- envio (São Paulo). entregues: entregues × preço (entregues nulo = sem estimativa); tamanho_lista: tamanho × preço;
-- mensalidade: 0 por disparo. Sem preço: centavos nulo e tem_preco = false (nunca 0 inventado).
create function mkt_mensageria.custo_estimado(p_ferramenta bigint, p_canal text, p_tipo text, p_enviado_em timestamptz,
                                              p_entregues integer, p_tamanho integer,
                                              out centavos bigint, out tem_preco boolean, out preco_id bigint)
language sql stable set search_path = '' as $$
  select case pv.base_cobranca
           when 'mensalidade' then 0::bigint
           when 'tamanho_lista' then round(p_tamanho * pv.preco_centavos)::bigint
           when 'entregues' then round(p_entregues * pv.preco_centavos)::bigint
         end,
         pv.id is not null,
         pv.id
    from (select 1) um
    left join lateral (
      select p.id, p.base_cobranca, p.preco_centavos
        from mkt_mensageria.precos p
       where p.ferramenta_id = p_ferramenta and p.canal = p_canal and coalesce(p.tipo, '') = coalesce(p_tipo, '')
         and p.vigente_desde <= (p_enviado_em at time zone 'America/Sao_Paulo')::date
         and p.anulado_em is null
       order by p.vigente_desde desc
       limit 1) pv on true;
$$;
revoke all on function mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer) from public, anon, authenticated;

-- Pendências (versão 2; a v1 mkt_mensageria.pendencias fica, sem uso). Ordem: as 3 antigas, depois as novas.
--   sem_custo: nem custo real nem estimado · sem_retorno: entregues ou lidas nulas (canal grupo dispensa)
--   conferir_zero_leitura: 0 lidas com custo (real ou estimado) > 0 · sem_preco: sem custo real e sem preço vigente
--   sem_projeto: entrou pela integração sem [SIGLA] cadastrada
create function mkt_mensageria.pendencias_v2(p_canal text, p_projeto bigint, p_entregues integer, p_lidas integer,
                                             p_custo integer, p_custo_estimado bigint, p_tem_preco boolean) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_custo is null and p_custo_estimado is null then 'sem_custo' end,
    case when p_canal <> 'grupo' and (p_entregues is null or p_lidas is null) then 'sem_retorno' end,
    case when p_lidas = 0 and coalesce(p_custo::bigint, p_custo_estimado) > 0 then 'conferir_zero_leitura' end,
    case when p_custo is null and not coalesce(p_tem_preco, false) then 'sem_preco' end,
    case when p_projeto is null then 'sem_projeto' end], null);
$$;
revoke all on function mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean) from public, anon, authenticated;

-- Atraso da fonte: tempo desde a última execução ok (ou desde que foi ligada). Atrasada = ativa e > 2× o intervalo.
-- Usada pela saúde e pela checagem do vigia (mesma regra nos dois).
create function mkt_mensageria.fonte_atraso(p_fonte text, out ativa boolean, out ultima_ok_em timestamptz,
                                            out atraso interval, out atrasada boolean)
language sql stable set search_path = '' as $$
  select f.ativa, u.fim,
         case when f.ativa then now() - greatest(u.fim, f.ativa_desde) end,
         coalesce(f.ativa and now() - greatest(u.fim, f.ativa_desde) > 2 * f.intervalo_esperado, false)
    from mkt_mensageria.fontes f
    left join lateral (select e.fim from mkt_mensageria.execucoes e
                        where e.fonte = f.chave and e.status = 'ok'
                        order by e.inicio desc limit 1) u on true
   where f.chave = p_fonte;
$$;
revoke all on function mkt_mensageria.fonte_atraso(text) from public, anon, authenticated;

-- Comando do pg_cron de cada fonte. Atrasada = erro (falha_sql) → o vigia abre incidente e avisa no Slack.
create function mkt_mensageria.vigiar_fonte(p_fonte text) returns text
language plpgsql stable set search_path = '' as $$
declare
  r record;
begin
  select * into r from mkt_mensageria.fonte_atraso(p_fonte);
  if r.ativa is null then
    raise exception 'Mensageria: fonte % não cadastrada', p_fonte;
  end if;
  if r.atrasada then
    raise exception 'Mensageria: fonte % sem execução ok há % (esperado a cada %)', p_fonte, date_trunc('minute', r.atraso),
      (select f.intervalo_esperado from mkt_mensageria.fontes f where f.chave = p_fonte);
  end if;
  return case when r.ativa then 'ok' else 'inativa' end;
end
$$;
revoke all on function mkt_mensageria.vigiar_fonte(text) from public, anon, authenticated;

-- Confere a chave da fonte contra o Vault (sha256: não vaza prefixo por tempo). Formato fixo antes de consultar.
create function mkt_mensageria.chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v text;
begin
  if p_fonte is null or p_chave is null or p_chave !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_' || p_fonte;
  if v is null then
    return false;
  end if;
  return sha256(convert_to(p_chave, 'UTF8')) = sha256(convert_to(v, 'UTF8'));
end
$$;
revoke all on function mkt_mensageria.chave_ok(text, text) from public, anon, authenticated;

-- Um item do lote → valores finais (já mesclados com o que está gravado) ou motivo da recusa.
-- Mescla: campo ausente/nulo no item = mantém o gravado (NULL da fonte nunca apaga). tipo e custo_centavos: o gravado
-- vence quando existe (a tela pode ter corrigido). Projeto: o gravado vence; senão a [SIGLA] da campanha.
-- Validação: a mesma da tela (disparo_validar), sobre o resultado da mescla; só o erro "projeto" é dispensado.
create function mkt_mensageria.api_item(p_fonte text, p_ferr_fixa bigint, p_item jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ext text;
  d mkt_mensageria.disparos%rowtype;
  v_existe boolean;
  v_campanha text;
  v_proj bigint;
  v_nproj integer;
  v_sigla text;
  v_ferr bigint;
  v_txt text;
  v_num bigint;
  v_canon jsonb;
  k text;
  r jsonb;
  v_motivo text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_object('motivo', 'Item não é um objeto JSON.');
  end if;
  v_ext := btrim(coalesce(p_item ->> 'id_externo', ''));
  if v_ext = '' or length(v_ext) > 200 then
    return jsonb_build_object('motivo', 'id_externo ausente ou com mais de 200 caracteres.');
  end if;

  select * into d from mkt_mensageria.disparos x where x.origem_sistema = p_fonte and x.id_externo = v_ext;
  v_existe := found;
  if v_existe and d.arquivado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- arquivado pela tela: a API não mexe
  end if;
  if v_existe and d.anonimizado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- LGPD: anonimizado, a API não regrava nada
  end if;

  v_campanha := nullif(left(btrim(coalesce(p_item ->> 'campanha', '')), 300), '');
  if v_campanha is null and v_existe then v_campanha := d.campanha; end if;
  -- [SIGLA]: o conteúdo de um colchete que seja sigla cadastrada. Nenhuma, ou duas siglas diferentes = sem projeto.
  select min(pr.id), count(distinct pr.id) into v_proj, v_nproj
    from regexp_matches(coalesce(v_campanha, ''), '\[([^][]{1,20})\]', 'g') m
    join mkt.projetos pr on pr.sigla = upper(btrim(m[1]));
  if v_nproj <> 1 then v_proj := null; end if;
  if v_existe and d.projeto_id is not null then v_proj := d.projeto_id; end if;
  select pr.sigla into v_sigla from mkt.projetos pr where pr.id = v_proj;

  if p_ferr_fixa is not null then
    v_ferr := p_ferr_fixa;
  else
    v_txt := btrim(coalesce(p_item ->> 'ferramenta', ''));
    if v_txt <> '' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
      if v_ferr is null then
        return jsonb_build_object('id_externo', v_ext, 'motivo', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.');
      end if;
    elsif v_existe then
      v_ferr := d.ferramenta_id;
    end if;
  end if;

  v_txt := regexp_replace(coalesce(p_item ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      return jsonb_build_object('id_externo', v_ext, 'motivo', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.');
    end if;
  elsif v_existe then
    v_num := d.numero_id;
  end if;

  v_canon := case when v_existe then jsonb_build_object(
      'enviado_em', d.enviado_em, 'canal', d.canal, 'tipo', d.tipo, 'copy_texto', d.copy_texto, 'copy_link', d.copy_link,
      'publico_lista', d.publico_lista, 'publico_origem', d.publico_origem, 'tamanho_lista', d.tamanho_lista,
      'entregues', d.entregues, 'lidas', d.lidas, 'cliques', d.cliques, 'falhas', d.falhas,
      'custo_centavos', d.custo_centavos, 'disparado_por', d.disparado_por)
    else '{}'::jsonb end;
  foreach k in array array['enviado_em', 'canal', 'tipo', 'copy_texto', 'copy_link', 'publico_lista', 'publico_origem',
                           'tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'disparado_por'] loop
    if jsonb_typeof(p_item -> k) is not null and jsonb_typeof(p_item -> k) <> 'null'
       and not (k in ('tipo', 'custo_centavos') and jsonb_typeof(v_canon -> k) is not null and jsonb_typeof(v_canon -> k) <> 'null') then
      v_canon := v_canon || jsonb_build_object(k, p_item -> k);
    end if;
  end loop;
  v_canon := v_canon || jsonb_build_object('projeto', coalesce(v_sigla, ''), 'ferramenta_id', v_ferr::text,
                                           'numero_id', v_num::text);
  if nullif(btrim(coalesce(v_canon ->> 'disparado_por', '')), '') is null then
    v_canon := v_canon || jsonb_build_object('disparado_por', 'api:' || p_fonte);
  end if;

  r := mkt_mensageria.disparo_validar(v_canon);
  select left(string_agg(x ->> 'campo' || ': ' || (x ->> 'msg'), '; '), 500) into v_motivo
    from jsonb_array_elements(r -> 'erros') x
   where x ->> 'campo' <> 'projeto';
  if v_motivo is not null then
    return jsonb_build_object('id_externo', v_ext, 'motivo', v_motivo);
  end if;
  return jsonb_build_object('id_externo', v_ext, 'existe', v_existe,
    'v', (r -> 'v') || jsonb_build_object('projeto_id', v_proj, 'campanha', v_campanha, 'id_externo', v_ext));
end
$$;
revoke all on function mkt_mensageria.api_item(text, bigint, jsonb) from public, anon, authenticated;

-- Upsert idempotente do lote por (origem_sistema, id_externo). Uma passada de validação + UM insert…on conflict.
-- UPDATE só quando algum valor muda (o WHERE do DO UPDATE); tipo, projeto e custo: o gravado vence na hora da escrita
-- (fecha a corrida com a tela). Lock por fonte: dois lotes da mesma fonte viram fila. Repetido no lote: vale o último.
-- Autor no histórico: 'api:<fonte>' (flag local à transação, lida pelo trg_historico quando auth.uid() é nulo).
create function mkt_mensageria.api_upsert(p_fonte text, p_lote jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_ferr_fixa bigint;
  v_res jsonb[];
  v_n integer;
  v_ins integer := 0;
  v_upd integer := 0;
  v_validos integer;
  v_arq integer;
  v_recusas jsonb;
begin
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    raise exception 'api_upsert: lote tem que ser array de até 1.000 itens' using errcode = '22023';
  end if;
  select f.ferramenta_id into v_ferr_fixa from mkt_mensageria.fontes f where f.chave = p_fonte;
  if not found then
    raise exception 'api_upsert: fonte % não cadastrada', p_fonte using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_lote);
  perform pg_advisory_xact_lock(hashtext('mkt_mensageria.api:' || p_fonte));
  perform set_config('mkt_mensageria.autor_api', 'api:' || p_fonte, true);

  select coalesce(array_agg(x.r order by x.pos), '{}') into v_res
    from (select t.pos,
                 case when t.ext is not null and t.rep > 1
                      then jsonb_build_object('pos', t.pos, 'id_externo', t.ext,
                                              'motivo', 'id_externo repetido no lote: vale a última ocorrência.')
                      else jsonb_build_object('pos', t.pos) || mkt_mensageria.api_item(p_fonte, v_ferr_fixa, t.item) end as r
            from (select e.item, e.pos::int as pos, nullif(btrim(e.item ->> 'id_externo'), '') as ext,
                         row_number() over (partition by nullif(btrim(e.item ->> 'id_externo'), '') order by e.pos desc) as rep
                    from jsonb_array_elements(p_lote) with ordinality e(item, pos)) t) x;

  with v as (
    select r -> 'v' as v from unnest(v_res) r where r ? 'v'
  ), up as (
    insert into mkt_mensageria.disparos as d (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
           copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
           disparado_por, retorno_em, origem, origem_sistema, id_externo, campanha)
    select (v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
           (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
           v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
           (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
           case when coalesce(v ->> 'entregues', v ->> 'lidas', v ->> 'cliques', v ->> 'falhas', v ->> 'custo_centavos') is not null
                then now() end,
           'api', p_fonte, v ->> 'id_externo', v ->> 'campanha'
      from v
    on conflict (origem_sistema, id_externo) where id_externo is not null do update
       set enviado_em = excluded.enviado_em, projeto_id = coalesce(d.projeto_id, excluded.projeto_id),
           canal = excluded.canal, ferramenta_id = excluded.ferramenta_id, numero_id = excluded.numero_id,
           tipo = coalesce(d.tipo, excluded.tipo), copy_texto = excluded.copy_texto, copy_link = excluded.copy_link,
           publico_lista = excluded.publico_lista, publico_origem = excluded.publico_origem,
           tamanho_lista = excluded.tamanho_lista, entregues = excluded.entregues, lidas = excluded.lidas,
           cliques = excluded.cliques, falhas = excluded.falhas,
           custo_centavos = coalesce(d.custo_centavos, excluded.custo_centavos),
           disparado_por = excluded.disparado_por, campanha = excluded.campanha,
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from (excluded.entregues, excluded.lidas, excluded.cliques, excluded.falhas,
                                                    coalesce(d.custo_centavos, excluded.custo_centavos))
                             then now() else d.retorno_em end
     where d.arquivado_em is null and d.anonimizado_em is null
       and (d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
            d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
            d.custo_centavos, d.disparado_por, d.campanha)
           is distinct from
           (excluded.enviado_em, coalesce(d.projeto_id, excluded.projeto_id), excluded.canal, excluded.ferramenta_id,
            excluded.numero_id, coalesce(d.tipo, excluded.tipo), excluded.copy_texto, excluded.copy_link,
            excluded.publico_lista, excluded.publico_origem, excluded.tamanho_lista, excluded.entregues, excluded.lidas,
            excluded.cliques, excluded.falhas, coalesce(d.custo_centavos, excluded.custo_centavos),
            excluded.disparado_por, excluded.campanha)
    returning (d.xmax = 0) as inserido
  )
  select count(*) filter (where inserido), count(*) filter (where not inserido) into v_ins, v_upd from up;

  select count(*) filter (where r ? 'v'), count(*) filter (where r ? 'arquivado') into v_validos, v_arq from unnest(v_res) r;
  select coalesce(jsonb_agg(jsonb_build_object(
           'posicao', (r ->> 'pos')::int, 'id_externo', r ->> 'id_externo', 'motivo', r ->> 'motivo',
           'payload', case when r ->> 'id_externo' is not null and (
                                  exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = p_fonte
                                             and d.id_externo = r ->> 'id_externo' and d.anonimizado_em is not null)
                                  or exists (select 1 from mkt_mensageria.recusas x where x.fonte = p_fonte
                                             and x.id_externo = r ->> 'id_externo' and x.anonimizado_em is not null))
                           then jsonb_build_object('anonimizado', true)
                           when length((p_lote -> ((r ->> 'pos')::int - 1))::text) <= 20000 then p_lote -> ((r ->> 'pos')::int - 1)
                           else jsonb_build_object('truncado', true, 'tamanho', length((p_lote -> ((r ->> 'pos')::int - 1))::text)) end)
           order by (r ->> 'pos')::int), '[]'::jsonb)
    into v_recusas
    from unnest(v_res) r where r ? 'motivo';
  perform set_config('mkt_mensageria.autor_api', '', true);

  return jsonb_build_object('lidos', v_n, 'inseridos', v_ins, 'atualizados', v_upd,
                            'inalterados', v_validos - v_ins - v_upd + v_arq,
                            'recusados', jsonb_array_length(v_recusas), 'recusas', v_recusas);
end
$$;
revoke all on function mkt_mensageria.api_upsert(text, jsonb) from public, anon, authenticated;

-- Retenção LGPD das recusas: payload com mais de 30 dias vira {"expurgado":true} (motivo, id_externo e datas ficam).
-- Até 5.000 por execução (job diário). Grava: não pode ser stable.
create function mkt_mensageria.recusas_expurgar() returns integer
language plpgsql set search_path = '' as $$
declare
  v integer;
begin
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('expurgado', true), expurgado_em = now()
   where r.id in (select x.id from mkt_mensageria.recusas x
                   where x.criado_em < now() - interval '30 days' and x.expurgado_em is null and x.anonimizado_em is null
                   order by x.criado_em limit 5000);
  get diagnostics v = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  return v;
end
$$;
revoke all on function mkt_mensageria.recusas_expurgar() from public, anon, authenticated;

-- ─── 5. Triggers ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Histórico: igual à 20261005n + autor da integração (por_api) quando auth.uid() é nulo.
create or replace function mkt_mensageria.trg_historico() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_antes jsonb;
  v_depois jsonb := to_jsonb(new);
  v_acao text := 'inserir';
  v_uid uuid := auth.uid();
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    if (v_antes - 'atualizado_em' - 'atualizado_por') = (v_depois - 'atualizado_em' - 'atualizado_por') then
      return null;
    end if;
    v_acao := case when v_antes ->> 'arquivado_em' is null and v_depois ->> 'arquivado_em' is not null
                   then 'arquivar' else 'alterar' end;
  end if;
  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por, por_api)
  values (tg_table_name, v_depois ->> 'id', v_acao, v_antes, v_depois, v_uid,
          case when v_uid is null then nullif(current_setting('mkt_mensageria.autor_api', true), '') end);
  return null;
end
$$;
revoke all on function mkt_mensageria.trg_historico() from public, anon, authenticated;

-- Preço: só a anulação (uma vez, com motivo). Nada mais muda.
create function mkt_mensageria.trg_preco_anular() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.anulado_em is not null then
    raise exception 'mkt_mensageria.precos: preço já anulado não muda' using errcode = '42501';
  end if;
  if new.anulado_em is null
     or (new.id, new.ferramenta_id, new.canal, new.tipo, new.base_cobranca, new.preco_centavos, new.vigente_desde,
         new.obs, new.criado_em, new.criado_por)
        is distinct from (old.id, old.ferramenta_id, old.canal, old.tipo, old.base_cobranca, old.preco_centavos,
                          old.vigente_desde, old.obs, old.criado_em, old.criado_por) then
    raise exception 'mkt_mensageria.precos: preço não se edita (anule com motivo e cadastre outro)' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_preco_anular() from public, anon, authenticated;

-- Fonte: chave imutável; ativa_desde carimbado ao ligar e zerado ao desligar; liga/desliga junto a checagem do vigia.
create function mkt_mensageria.trg_fonte() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_job bigint;
begin
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.ativa_desde := case when new.ativa then now() end;
  else
    if new.chave is distinct from old.chave then
      raise exception 'mkt_mensageria.fontes: a chave não muda' using errcode = '42501';
    end if;
    new.criado_em := old.criado_em;
    new.ativa_desde := case when not new.ativa then null when old.ativa then old.ativa_desde else now() end;
    if new.ativa is distinct from old.ativa then
      select j.jobid into v_job from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(new.chave);
      if v_job is not null then
        perform cron.alter_job(v_job, active := new.ativa);
      end if;
    end if;
  end if;
  new.atualizado_em := now();
  return new;
end
$$;
revoke all on function mkt_mensageria.trg_fonte() from public, anon, authenticated;

-- Recusa: só a anonimização LGPD e o expurgo (flag local) mudam, e só payload + campos anonimizado_*/expurgado_em.
create function mkt_mensageria.trg_recusa_anonimizar() returns trigger
language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('mkt_mensageria.anonimizar', true), '') = 'on'
     and (new.id, new.execucao_id, new.fonte, new.posicao, new.id_externo, new.motivo, new.criado_em)
         is not distinct from (old.id, old.execucao_id, old.fonte, old.posicao, old.id_externo, old.motivo, old.criado_em) then
    return new;
  end if;
  raise exception 'mkt_mensageria.recusas: UPDATE não é permitido (só a anonimização LGPD)' using errcode = '42501';
end
$$;
revoke all on function mkt_mensageria.trg_recusa_anonimizar() from public, anon, authenticated;

create trigger a_anular before update on mkt_mensageria.precos
  for each row execute function mkt_mensageria.trg_preco_anular();
create trigger a_fonte before insert or update on mkt_mensageria.fontes
  for each row execute function mkt_mensageria.trg_fonte();
create trigger sem_update before update on mkt_mensageria.recusas
  for each row execute function mkt_mensageria.trg_recusa_anonimizar();
create trigger sem_update before update on mkt_mensageria.execucoes
  for each row execute function mkt_mensageria.trg_bloqueio();
create trigger sem_update before update on mkt_mensageria.reconciliacao
  for each row execute function mkt_mensageria.trg_bloqueio();
do $bloqueio$
declare t text;
begin
  foreach t in array array['precos', 'fontes', 'execucoes', 'recusas', 'reconciliacao'] loop
    execute format('create trigger sem_delete before delete on mkt_mensageria.%I for each row execute function mkt_mensageria.trg_bloqueio()', t);
    execute format('create trigger sem_truncate before truncate on mkt_mensageria.%I for each statement execute function mkt_mensageria.trg_bloqueio()', t);
  end loop;
end
$bloqueio$;

-- ─── 6. Seeds ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Preços: cópia EXPLÍCITA de controle.custo_mensagem (05/10/2026; a guarda conferiu). Reais → centavos (× 100).
-- Base: WhatsApp e grupo por entregue e SMS por envio, como a vw_mensageria_envio cobrava (sms: qtd_sms/enviados).
-- E-mail e grupo: 0 por disparo (mensalidade). Infobip SMS: SEM preço (pendência: a listagem mostra 'sem_preco').
insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs)
select f.id, s.canal, s.tipo, s.base, s.preco, s.vig, s.obs
  from (values
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma api, marketing'),
    ('Unichat', 'whatsapp_api', 'utility', 'entregues', 8.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, utility'),
    ('Unichat', 'whatsapp_api', 'marketing', 'entregues', 36.0000, date '2026-07-24', 'controle.custo_mensagem: plataforma unnichat, marketing'),
    ('Ligue Lead', 'sms', null, 'tamanho_lista', 6.5000, date '2026-07-01', 'controle.custo_mensagem: plataforma sms'),
    ('ActiveCampaign', 'email', null, 'mensalidade', 0.0000, date '2026-07-29', 'controle.custo_mensagem: plataforma activecampaign'),
    ('SendFlow', 'grupo', null, 'mensalidade', 0.0000, date '2026-07-01', 'controle.custo_mensagem: plataforma grupo')
  ) s(ferramenta, canal, tipo, base, preco, vig, obs)
  join mkt_mensageria.ferramentas f on f.nome = s.ferramenta;

-- Fontes: todas DESLIGADAS (nenhum fluxo do n8n existe ainda). Ligar: update … set ativa = true (como postgres).
-- Intervalo de 1 h é o do cron antigo (ingest-mensageria-hourly); ajustar por fonte quando o fluxo existir.
insert into mkt_mensageria.fontes (chave, nome, ferramenta_id, ativa, intervalo_esperado)
select s.chave, s.nome, (select f.id from mkt_mensageria.ferramentas f where f.nome = s.ferramenta), false, interval '1 hour'
  from (values ('activecampaign', 'ActiveCampaign', 'ActiveCampaign'), ('unichat', 'Unichat', 'Unichat'),
               ('infobip', 'Infobip', 'Infobip'), ('sendflow', 'SendFlow', 'SendFlow'),
               ('cs_disparos', 'Disparos do CS (cs.disparos)', null)) s(chave, nome, ferramenta);

-- Chave de cada fonte: nasce no Vault (32 bytes aleatórios, hex). Idempotente: não troca chave existente.
-- Para configurar o n8n, o dono lê: select decrypted_secret from vault.decrypted_secrets where name = 'mkt_msg_fonte_<chave>';
do $vault$
declare c text;
begin
  for c in select f.chave from mkt_mensageria.fontes f loop
    if not exists (select 1 from vault.secrets where name = 'mkt_msg_fonte_' || c) then
      perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mkt_msg_fonte_' || c,
                                  'Chave da fonte ' || c || ' da Mensageria (API mkt_msg_api_receber; gerada no banco)');
    end if;
  end loop;
end
$vault$;

-- Vigia: um job por fonte, criado DESLIGADO (liga junto com a fonte, pelo trg_fonte). Falha = fonte atrasada.
-- ops.rotina: 1 falha abre (a checagem já espera 2× o intervalo), 1 ok fecha.
do $vigia$
declare
  c text;
  v_job bigint;
begin
  for c in select f.chave from mkt_mensageria.fontes f order by f.chave loop
    if exists (select 1 from cron.job j where j.jobname = mkt_mensageria.fonte_jobname(c)) then
      raise exception '20261005o: job % já existe', mkt_mensageria.fonte_jobname(c);
    end if;
    v_job := cron.schedule(mkt_mensageria.fonte_jobname(c), '*/30 * * * *',
                           format('select mkt_mensageria.vigiar_fonte(%L)', c));
    perform cron.alter_job(v_job, active := false);
    insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
    values (mkt_mensageria.fonte_jobname(c), 1, interval '3 hours', 1, interval '30 minutes', 'manual');
    insert into ops.rotina_estado (jobname) values (mkt_mensageria.fonte_jobname(c)) on conflict do nothing;
  end loop;
  -- Retenção das recusas: diário, 04:17 UTC. Mais de 26 h sem sucesso = alerta.
  if exists (select 1 from cron.job j where j.jobname = 'mensageria-recusas-expurgo') then
    raise exception '20261005o: job mensageria-recusas-expurgo já existe';
  end if;
  perform cron.schedule('mensageria-recusas-expurgo', '17 4 * * *', 'select mkt_mensageria.recusas_expurgar()');
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('mensageria-recusas-expurgo', 1, interval '26 hours', 1, interval '24 hours', 'manual');
  insert into ops.rotina_estado (jobname) values ('mensageria-recusas-expurgo') on conflict do nothing;
end
$vigia$;

-- ─── 7. P3: pausa o cron antigo (dependentes medidos em 05/10: só as views vw_mensageria_*; nenhuma função) ─────────
-- Estado antes (05/10/2026): jobid 26, '50 * * * *', active = true; ops.rotina silenciado_ate = null.
do $p3$
declare
  v_job bigint;
  v_ativo boolean;
begin
  select j.jobid, j.active into v_job, v_ativo from cron.job j where j.jobname = 'ingest-mensageria-hourly';
  if v_job is null then
    raise notice '20261005o: ingest-mensageria-hourly não existe: nada a pausar';
  elsif v_ativo then
    perform cron.alter_job(v_job, active := false);
  end if;
  update ops.rotina set silenciado_ate = 'infinity' where jobname = 'ingest-mensageria-hourly';
end
$p3$;

-- ─── 8. Funções públicas (RPC) ───────────────────────────────────────────────────────────────────────────────────────

-- Lista do período: igual à 20261005n + custo estimado, custo_fonte, campanha e pendências v2. Só ACRESCENTA campos.
-- Projeto em left join (linha da API pode vir sem projeto). Contrato em 20261005o.explain.md.
create or replace function public.mkt_msg_disparos_listar(p_de date, p_ate date, p_projeto text default null,
                                                          p_canal text default null, p_ferramenta bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_proj bigint;
  v_canal text := nullif(lower(btrim(coalesce(p_canal, ''))), '');
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_de is null or p_ate is null then
    return jsonb_build_object('ok', false, 'msg', 'Informe o período (de e até).');
  end if;
  if p_ate < p_de then
    return jsonb_build_object('ok', false, 'msg', 'A data final é antes da inicial.');
  end if;
  if p_ate - p_de + 1 > 366 then
    return jsonb_build_object('ok', false, 'msg', 'Período máximo: 366 dias.');
  end if;
  if nullif(btrim(coalesce(p_projeto, '')), '') is not null then
    select pr.id into v_proj from mkt.projetos pr where pr.sigla = upper(btrim(p_projeto));
    if v_proj is null then
      return jsonb_build_object('ok', false, 'msg', 'Projeto ' || upper(btrim(p_projeto)) || ' não cadastrado.');
    end if;
  end if;
  if v_canal is not null and v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    return jsonb_build_object('ok', false, 'msg', 'Canal inválido.');
  end if;
  v_ini := p_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo';

  return (
    with base as materialized (
      select d.id, d.enviado_em, d.projeto_id, d.canal, d.ferramenta_id, d.numero_id, d.tipo, d.copy_texto, d.copy_link,
             d.publico_lista, d.publico_origem, d.tamanho_lista, d.entregues, d.lidas, d.cliques, d.falhas,
             d.custo_centavos, d.disparado_por, d.retorno_em, d.origem, d.origem_sistema, d.id_externo, d.importacao_id,
             d.atualizado_em, d.campanha, ce.centavos as custo_estimado,
             case when d.custo_centavos is not null then 'real'
                  when ce.centavos is not null then 'estimado'
                  when not ce.tem_preco then 'sem_preco' end as custo_fonte,
             mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos, ce.centavos,
                                          ce.tem_preco) as pendencias
        from mkt_mensageria.disparos d
        cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em, d.entregues,
                                                         d.tamanho_lista) ce
       where d.enviado_em >= v_ini and d.enviado_em < v_fim
         and d.arquivado_em is null
         and (v_proj is null or d.projeto_id = v_proj)
         and (v_canal is null or d.canal = v_canal)
         and (p_ferramenta is null or d.ferramenta_id = p_ferramenta)
    ),
    pagina as (select * from base order by enviado_em desc, id desc limit 500)
    select jsonb_build_object(
      'ok', true, 'de', p_de, 'ate', p_ate, 'limite', 500,
      'truncado', (select count(*) > 500 from base),
      'linhas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'enviado_em', b.enviado_em, 'projeto_id', b.projeto_id, 'projeto', pr.sigla,
                 'canal', b.canal, 'ferramenta_id', b.ferramenta_id, 'ferramenta', f.nome,
                 'numero_id', b.numero_id, 'numero', nu.numero, 'tipo', b.tipo,
                 'copy_texto', b.copy_texto, 'copy_link', b.copy_link,
                 'publico_lista', b.publico_lista, 'publico_origem', b.publico_origem, 'tamanho_lista', b.tamanho_lista,
                 'entregues', b.entregues, 'lidas', b.lidas, 'cliques', b.cliques, 'falhas', b.falhas,
                 'custo_centavos', b.custo_centavos, 'disparado_por', b.disparado_por, 'retorno_em', b.retorno_em,
                 'origem', b.origem, 'origem_sistema', b.origem_sistema, 'id_externo', b.id_externo,
                 'importacao_id', b.importacao_id, 'atualizado_em', b.atualizado_em, 'pendencias', to_jsonb(b.pendencias),
                 'campanha', b.campanha, 'custo_estimado_centavos', b.custo_estimado, 'custo_fonte', b.custo_fonte)
               order by b.enviado_em desc, b.id desc)
          from pagina b
          left join mkt.projetos pr on pr.id = b.projeto_id
          join mkt_mensageria.ferramentas f on f.id = b.ferramenta_id
          left join mkt_mensageria.numeros nu on nu.id = b.numero_id), '[]'::jsonb),
      'totais', (
        select jsonb_build_object(
                 'qtd', count(*), 'tamanho', sum(b.tamanho_lista),
                 'entregues', sum(b.entregues), 'lidas', sum(b.lidas), 'cliques', sum(b.cliques), 'falhas', sum(b.falhas),
                 'custo_centavos', sum(b.custo_centavos), 'com_custo', count(b.custo_centavos),
                 'sem_custo', count(*) filter (where 'sem_custo' = any(b.pendencias)),
                 'sem_retorno', count(*) filter (where 'sem_retorno' = any(b.pendencias)),
                 'conferir_zero_leitura', count(*) filter (where 'conferir_zero_leitura' = any(b.pendencias)),
                 'custo_estimado_centavos', sum(b.custo_estimado) filter (where b.custo_centavos is null),
                 'com_estimativa', count(*) filter (where b.custo_centavos is null and b.custo_estimado is not null),
                 'custo_total_centavos', sum(coalesce(b.custo_centavos, b.custo_estimado)),
                 'sem_preco', count(*) filter (where 'sem_preco' = any(b.pendencias)),
                 'sem_projeto', count(*) filter (where 'sem_projeto' = any(b.pendencias)))
          from base b),
      'por_canal', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal', c.canal, 'qtd', c.qtd, 'tamanho', c.tamanho, 'entregues', c.entregues, 'lidas', c.lidas,
                 'cliques', c.cliques, 'falhas', c.falhas, 'custo_centavos', c.custo, 'sem_custo', c.sem_custo,
                 'custo_estimado_centavos', c.estimado, 'custo_total_centavos', c.total, 'sem_preco', c.sem_preco,
                 'sem_projeto', c.sem_projeto)
               order by c.canal)
          from (select b.canal, count(*) as qtd, sum(b.tamanho_lista) as tamanho, sum(b.entregues) as entregues,
                       sum(b.lidas) as lidas, sum(b.cliques) as cliques, sum(b.falhas) as falhas,
                       sum(b.custo_centavos) as custo,
                       count(*) filter (where 'sem_custo' = any(b.pendencias)) as sem_custo,
                       sum(b.custo_estimado) filter (where b.custo_centavos is null) as estimado,
                       sum(coalesce(b.custo_centavos, b.custo_estimado)) as total,
                       count(*) filter (where 'sem_preco' = any(b.pendencias)) as sem_preco,
                       count(*) filter (where 'sem_projeto' = any(b.pendencias)) as sem_projeto
                  from base b group by b.canal) c), '[]'::jsonb))
  );
end
$$;
revoke all on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparos_listar(date, date, text, text, bigint) to authenticated;

-- Igual à 20261005n + linha de origem 'api': só projeto, tipo e custo mudam aqui (o resto vem da fonte).
create or replace function public.mkt_msg_disparo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  r jsonb;
  v jsonb;
  v_con text;
  v_ret boolean;
  v_origem text;
  v_canal_api text;
  v_arq timestamptz;
  v_sigla text;
  v_proj bigint;
  v_tipo text;
  v_custo bigint;
  e jsonb := '[]'::jsonb;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do disparo ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null and (p ->> 'id') !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Disparo inválido.');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;

  if v_id is not null then
    select d.origem, d.canal, d.arquivado_em into v_origem, v_canal_api, v_arq
      from mkt_mensageria.disparos d where d.id = v_id for update;
    if v_origem = 'api' then
      if v_arq is not null then
        return jsonb_build_object('ok', false, 'msg', 'Disparo arquivado: não pode ser editado.');
      end if;
      v_sigla := upper(btrim(coalesce(p ->> 'projeto', '')));
      if v_sigla = '' then
        e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Escolha o projeto.');
      else
        select pr.id into v_proj from mkt.projetos pr where pr.sigla = v_sigla;
        if v_proj is null then
          e := e || jsonb_build_object('campo', 'projeto', 'msg', 'Projeto ' || v_sigla || ' não cadastrado em Projetos.');
        end if;
      end if;
      v_tipo := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
      if v_canal_api = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
      elsif v_canal_api <> 'whatsapp_api' and v_tipo is not null then
        e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
      end if;
      v_custo := mkt_mensageria.inteiro(p ->> 'custo_centavos');
      if v_custo < 0 then
        e := e || jsonb_build_object('campo', 'custo_centavos', 'msg', 'Custo: valor ≥ 0, ou vazio se ainda não lançado.');
      end if;
      if jsonb_array_length(e) > 0 then
        return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
      end if;
      update mkt_mensageria.disparos d
         set projeto_id = v_proj, tipo = v_tipo, custo_centavos = v_custo::int,
             retorno_em = case when d.custo_centavos is distinct from v_custo::int then now() else d.retorno_em end
       where d.id = v_id;
      return jsonb_build_object('ok', true, 'id', v_id, 'campos', jsonb_build_array('projeto', 'tipo', 'custo_centavos'),
        'msg', 'Disparo da integração salvo: aqui mudam só projeto, tipo e custo; o resto vem da fonte.');
    end if;
  end if;

  r := mkt_mensageria.disparo_validar(p);
  if jsonb_array_length(r -> 'erros') > 0 then
    return jsonb_build_object('ok', false, 'msg', r -> 'erros' -> 0 ->> 'msg', 'erros', r -> 'erros');
  end if;
  v := r -> 'v';
  v_ret := (v ->> 'entregues') is not null or (v ->> 'lidas') is not null or (v ->> 'cliques') is not null
           or (v ->> 'falhas') is not null or (v ->> 'custo_centavos') is not null;

  begin
    if v_id is null then
      insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, numero_id, tipo, copy_texto,
             copy_link, publico_lista, publico_origem, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos,
             disparado_por, retorno_em, origem)
      values ((v ->> 'enviado_em')::timestamptz, (v ->> 'projeto_id')::bigint, v ->> 'canal', (v ->> 'ferramenta_id')::bigint,
             (v ->> 'numero_id')::bigint, v ->> 'tipo', v ->> 'copy_texto', v ->> 'copy_link', v ->> 'publico_lista',
             v ->> 'publico_origem', (v ->> 'tamanho_lista')::int, (v ->> 'entregues')::int, (v ->> 'lidas')::int,
             (v ->> 'cliques')::int, (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int, v ->> 'disparado_por',
             case when v_ret then now() end, 'manual')
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Disparo registrado.', 'id', v_id);
    end if;

    update mkt_mensageria.disparos d
       set enviado_em = (v ->> 'enviado_em')::timestamptz, projeto_id = (v ->> 'projeto_id')::bigint, canal = v ->> 'canal',
           ferramenta_id = (v ->> 'ferramenta_id')::bigint, numero_id = (v ->> 'numero_id')::bigint, tipo = v ->> 'tipo',
           copy_texto = v ->> 'copy_texto', copy_link = v ->> 'copy_link', publico_lista = v ->> 'publico_lista',
           publico_origem = v ->> 'publico_origem', tamanho_lista = (v ->> 'tamanho_lista')::int,
           entregues = (v ->> 'entregues')::int, lidas = (v ->> 'lidas')::int, cliques = (v ->> 'cliques')::int,
           falhas = (v ->> 'falhas')::int, custo_centavos = (v ->> 'custo_centavos')::int,
           disparado_por = v ->> 'disparado_por',
           retorno_em = case when (d.entregues, d.lidas, d.cliques, d.falhas, d.custo_centavos)
                                  is distinct from ((v ->> 'entregues')::int, (v ->> 'lidas')::int, (v ->> 'cliques')::int,
                                                    (v ->> 'falhas')::int, (v ->> 'custo_centavos')::int)
                             then case when v_ret then now() end
                             else d.retorno_em end
     where d.id = v_id and d.arquivado_em is null and d.origem <> 'api';
    if not found then
      return jsonb_build_object('ok', false, 'msg', case
        when exists (select 1 from mkt_mensageria.disparos d where d.id = v_id) then 'Disparo arquivado: não pode ser editado.'
        else 'Disparo não encontrado.' end);
    end if;
    return jsonb_build_object('ok', true, 'msg', 'Disparo salvo.', 'id', v_id);
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || coalesce(v_con, 'dados') || ').');
  end;
end
$$;
revoke all on function public.mkt_msg_disparo_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_salvar(jsonb) to authenticated;

-- Igual à 20261005n + recusa linha da API (o retorno vem da fonte) + pendências v2 (com o custo estimado).
create or replace function public.mkt_msg_disparo_lancar_retorno(p_id bigint, p_entregues integer, p_lidas integer,
                                                                 p_cliques integer, p_falhas integer, p_custo_centavos integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tam integer;
  v_origem text;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select d.tamanho_lista, d.origem into v_tam, v_origem
    from mkt_mensageria.disparos d where d.id = p_id and d.arquivado_em is null for update;
  if v_tam is null then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado ou arquivado.');
  end if;
  if v_origem = 'api' then
    return jsonb_build_object('ok', false, 'msg',
      'Disparo da integração: o retorno vem da fonte. Projeto, tipo e custo se editam no próprio disparo.');
  end if;
  if p_entregues < 0 or p_lidas < 0 or p_cliques < 0 or p_falhas < 0 or p_custo_centavos < 0 then
    return jsonb_build_object('ok', false, 'msg', 'Valores de retorno e custo não podem ser negativos.');
  end if;
  if coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0) > v_tam then
    return jsonb_build_object('ok', false, 'msg',
      'Entregues + falhas (' || (coalesce(p_entregues, 0)::bigint + coalesce(p_falhas, 0)) || ') passa do tamanho da lista (' || v_tam || ').');
  end if;
  if p_lidas > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Lidas (' || p_lidas || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  if p_cliques > p_entregues then
    return jsonb_build_object('ok', false, 'msg', 'Cliques (' || p_cliques || ') não pode passar de entregues (' || p_entregues || ').');
  end if;
  update mkt_mensageria.disparos
     set entregues = p_entregues, lidas = p_lidas, cliques = p_cliques, falhas = p_falhas, custo_centavos = p_custo_centavos,
         retorno_em = case when coalesce(p_entregues, p_lidas, p_cliques, p_falhas, p_custo_centavos) is null then null else now() end
   where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Retorno lançado.', 'id', p_id,
    'pendencias', (select to_jsonb(mkt_mensageria.pendencias_v2(d.canal, d.projeto_id, d.entregues, d.lidas, d.custo_centavos,
                                                                ce.centavos, ce.tem_preco))
                     from mkt_mensageria.disparos d
                     cross join lateral mkt_mensageria.custo_estimado(d.ferramenta_id, d.canal, d.tipo, d.enviado_em,
                                                                      d.entregues, d.tamanho_lista) ce
                    where d.id = p_id));
end
$$;
revoke all on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_disparo_lancar_retorno(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Igual à 20261005n + por_api; por_nome cai para 'api:<fonte>' quando a mudança veio da integração.
create or replace function public.mkt_msg_historico(p_tabela text, p_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tab text := lower(btrim(coalesce(p_tabela, '')));
  v_id text := btrim(coalesce(p_id, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_tab not in ('disparos', 'numeros', 'ferramentas') then
    return jsonb_build_object('ok', false, 'msg', 'Tabela inválida: disparos, numeros ou ferramentas.');
  end if;
  if v_id !~ '^[0-9]{1,18}$' then
    return jsonb_build_object('ok', false, 'msg', 'Registro inválido.');
  end if;
  return jsonb_build_object('ok', true, 'itens', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', h.id, 'acao', h.acao, 'em', h.em, 'por', h.por, 'por_nome', coalesce(pf.nome, h.por_api),
             'por_api', h.por_api, 'antes', h.antes, 'depois', h.depois)
           order by h.em desc, h.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.historico h
             where h.tabela = v_tab and h.registro_id = v_id
             order by h.em desc, h.id desc limit 200) h
      left join public.perfis pf on pf.id = h.por));
end
$$;
revoke all on function public.mkt_msg_historico(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_historico(text, text) to authenticated;

-- Igual à 20261005n + limpa o payload das recusas do mesmo (fonte, id_externo). Retorno ganha recusas_limpas.
create or replace function public.mkt_msg_anonimizar_disparo(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_marca constant text := '[anonimizado]';
  v_hist integer;
  v_rec integer := 0;
  v_sis text;
  v_ext text;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  select d.origem_sistema, d.id_externo into v_sis, v_ext from mkt_mensageria.disparos d where d.id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Disparo não encontrado.');
  end if;

  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.disparos d
     set copy_texto = case when d.copy_texto is not null then v_marca end,
         publico_lista = v_marca,
         publico_origem = case when d.publico_origem is not null then v_marca end,
         anonimizado_em = coalesce(d.anonimizado_em, now())
   where d.id = p_id;
  update mkt_mensageria.historico h
     set antes = case when h.antes is null then null else h.antes || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.antes ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.antes ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.antes ->> 'publico_origem' is not null then v_marca end)) end,
         depois = case when h.depois is null then null else h.depois || jsonb_strip_nulls(jsonb_build_object(
                   'copy_texto', case when h.depois ->> 'copy_texto' is not null then v_marca end,
                   'publico_lista', case when h.depois ->> 'publico_lista' is not null then v_marca end,
                   'publico_origem', case when h.depois ->> 'publico_origem' is not null then v_marca end)) end
   where h.tabela = 'disparos' and h.registro_id = p_id::text;
  get diagnostics v_hist = row_count;
  if v_ext is not null then
    update mkt_mensageria.recusas r
       set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
           anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
     where r.fonte = v_sis and r.id_externo = v_ext and r.anonimizado_em is null;
    get diagnostics v_rec = row_count;
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);

  insert into mkt_mensageria.historico (tabela, registro_id, acao, antes, depois, por)
  values ('disparos', p_id::text, 'anonimizar', null,
          jsonb_build_object('campos', jsonb_build_array('copy_texto', 'publico_lista', 'publico_origem'),
                             'motivo', v_motivo, 'linhas_de_historico_limpas', v_hist, 'recusas_limpas', v_rec),
          (select auth.uid()));
  return jsonb_build_object('ok', true, 'msg', 'Disparo anonimizado.', 'id', p_id, 'historico_limpo', v_hist,
                            'recusas_limpas', v_rec);
end
$$;
revoke all on function public.mkt_msg_anonimizar_disparo(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_disparo(bigint, text) to authenticated;

-- LGPD de uma recusa que não virou disparo (só admin/dev, como a de disparo). Troca o payload; fica o motivo.
create function public.mkt_msg_anonimizar_recusa(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_n integer;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anonimização (3 a 500 caracteres).');
  end if;
  perform set_config('mkt_mensageria.anonimizar', 'on', true);
  update mkt_mensageria.recusas r
     set payload = jsonb_build_object('anonimizado', true), anonimizado_em = now(),
         anonimizado_por = (select auth.uid()), anonimizado_motivo = v_motivo
   where r.id = p_id and r.anonimizado_em is null;
  get diagnostics v_n = row_count;
  perform set_config('mkt_mensageria.anonimizar', 'off', true);
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Recusa não encontrada ou já anonimizada.');
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Recusa anonimizada.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_anonimizar_recusa(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_anonimizar_recusa(bigint, text) to authenticated;

-- Preços: todos (inclusive anulados, para a trilha), com o vigente de hoje marcado.
create function public.mkt_msg_precos_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'hoje', v_hoje, 'precos', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'ferramenta_id', p.ferramenta_id, 'ferramenta', f.nome, 'canal', p.canal, 'tipo', p.tipo,
             'base_cobranca', p.base_cobranca, 'preco_centavos', p.preco_centavos, 'vigente_desde', p.vigente_desde,
             'obs', p.obs, 'criado_em', p.criado_em, 'criado_por_nome', pc.nome,
             'anulado_em', p.anulado_em, 'anulado_por_nome', pa.nome, 'anulado_motivo', p.anulado_motivo,
             'vigente_hoje', p.anulado_em is null and p.id = (mkt_mensageria.custo_estimado(p.ferramenta_id, p.canal, p.tipo,
                                                               now(), 0, 0)).preco_id)
           order by lower(f.nome), p.canal, p.tipo nulls first, p.vigente_desde desc, p.id desc), '[]'::jsonb)
      from mkt_mensageria.precos p
      join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id
      left join public.perfis pc on pc.id = p.criado_por
      left join public.perfis pa on pa.id = p.anulado_por));
end
$$;
revoke all on function public.mkt_msg_precos_listar() from public, anon, authenticated;
grant execute on function public.mkt_msg_precos_listar() to authenticated;

-- Cadastra uma vigência. Não edita (com "id" recusa). Campos: ferramenta_id, canal, tipo (só whatsapp_api, e lá
-- obrigatório), base_cobranca (entregues|tamanho_lista|mensalidade), preco_centavos ("8", "6,5", 0.36 → até 4 casas;
-- mensalidade = 0), vigente_desde (aaaa-mm-dd), obs?. Nenhum campo de regra tem valor assumido: faltou = erro.
create function public.mkt_msg_preco_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb := '[]'::jsonb;
  v_ferr_txt text := btrim(coalesce(p ->> 'ferramenta_id', ''));
  v_ferr bigint;
  v_canal text := lower(btrim(coalesce(p ->> 'canal', '')));
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_base text := lower(btrim(coalesce(p ->> 'base_cobranca', '')));
  v_preco_txt text := replace(btrim(coalesce(p ->> 'preco_centavos', '')), ',', '.');
  v_preco numeric;
  v_vig_txt text := btrim(coalesce(p ->> 'vigente_desde', ''));
  v_vig date;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_id bigint;
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('ok', false, 'msg', 'Dados do preço ausentes.');
  end if;
  if nullif(p ->> 'id', '') is not null then
    return jsonb_build_object('ok', false, 'msg', 'Preço não se edita: anule o errado (com motivo) e cadastre outro.');
  end if;
  if v_ferr_txt ~ '^[0-9]{1,18}$' then
    select f.id into v_ferr from mkt_mensageria.ferramentas f where f.id = v_ferr_txt::bigint;
  end if;
  if v_ferr is null then e := e || jsonb_build_object('campo', 'ferramenta_id', 'msg', 'Escolha a ferramenta.'); end if;
  if v_canal not in ('whatsapp_api', 'email', 'sms', 'ligacao', 'grupo') then
    e := e || jsonb_build_object('campo', 'canal', 'msg', 'Canal inválido: API WhatsApp, e-mail, SMS, ligação ou grupo.');
  elsif v_canal = 'whatsapp_api' and (v_tipo is null or v_tipo not in ('utility', 'marketing')) then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Na API do WhatsApp, informe o tipo: utility ou marketing.');
  elsif v_canal <> 'whatsapp_api' and v_tipo is not null then
    e := e || jsonb_build_object('campo', 'tipo', 'msg', 'Tipo só existe na API do WhatsApp: deixe vazio neste canal.');
  end if;
  if v_base not in ('entregues', 'tamanho_lista', 'mensalidade') then
    e := e || jsonb_build_object('campo', 'base_cobranca', 'msg', 'Base de cobrança: por entregue, por tamanho da lista ou mensalidade.');
  end if;
  if v_preco_txt !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' then
    e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço em centavos, até 4 casas (ex.: 8 ou 6,5).');
  else
    v_preco := v_preco_txt::numeric;
    if v_preco > 100000 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg', 'Preço acima de R$ 1.000,00 por mensagem: confira.');
    elsif v_base = 'mensalidade' and v_preco <> 0 then
      e := e || jsonb_build_object('campo', 'preco_centavos', 'msg',
        'Na mensalidade o custo por disparo é 0: o valor mensal vai no cadastro da ferramenta.');
    end if;
  end if;
  if v_vig_txt ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    begin
      v_vig := v_vig_txt::date;
    exception when others then
      v_vig := null;
    end;
  end if;
  if v_vig is null or v_vig < date '2020-01-01' or v_vig > date '2100-12-31' then
    e := e || jsonb_build_object('campo', 'vigente_desde', 'msg', 'Vigente desde: data válida (aaaa-mm-dd).');
  end if;
  if length(v_obs) > 500 then e := e || jsonb_build_object('campo', 'obs', 'msg', 'Observação: até 500 caracteres.'); end if;
  if jsonb_array_length(e) > 0 then
    return jsonb_build_object('ok', false, 'msg', e -> 0 ->> 'msg', 'erros', e);
  end if;
  begin
    insert into mkt_mensageria.precos (ferramenta_id, canal, tipo, base_cobranca, preco_centavos, vigente_desde, obs, criado_por)
    values (v_ferr, v_canal, v_tipo, v_base, v_preco, v_vig, v_obs, (select auth.uid()))
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg',
      'Já existe preço válido para esta ferramenta, canal e tipo com vigência em ' || to_char(v_vig, 'DD/MM/YYYY') || ': anule-o antes.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Preço cadastrado.', 'id', v_id);
end
$$;
revoke all on function public.mkt_msg_preco_salvar(jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_salvar(jsonb) to authenticated;

create function public.mkt_msg_preco_anular(p_id bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_motivo) < 3 or length(v_motivo) > 500 then
    return jsonb_build_object('ok', false, 'msg', 'Informe o motivo da anulação (3 a 500 caracteres).');
  end if;
  update mkt_mensageria.precos set anulado_em = now(), anulado_por = (select auth.uid()), anulado_motivo = v_motivo
   where id = p_id and anulado_em is null;
  if not found then
    return jsonb_build_object('ok', false, 'msg', case
      when exists (select 1 from mkt_mensageria.precos where id = p_id) then 'Preço já anulado.' else 'Preço não encontrado.' end);
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Preço anulado. O custo estimado dos disparos dessa vigência foi recalculado.', 'id', p_id);
end
$$;
revoke all on function public.mkt_msg_preco_anular(bigint, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_preco_anular(bigint, text) to authenticated;

-- Porteiro barato da rota: confere fonte + chave ANTES de a rota ler o corpo (até 5 MB). Só service_role.
-- true = fonte cadastrada e chave certa (ativa ou não: a fonte desligada é recusada e registrada por api_receber).
create function public.mkt_msg_api_chave_ok(p_fonte text, p_chave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  return exists (select 1 from mkt_mensageria.fontes f where f.chave = v_fonte)
         and mkt_mensageria.chave_ok(v_fonte, p_chave);
end
$$;
revoke all on function public.mkt_msg_api_chave_ok(text, text) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_chave_ok(text, text) to service_role;

-- Recusas para a tela (só admin/dev): SEM o payload. Mais recentes primeiro, até 500.
create function public.mkt_msg_recusas_listar(p_fonte text default null, p_limite integer default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fonte text := nullif(btrim(coalesce(p_fonte, '')), '');
  v_lim integer := least(greatest(coalesce(p_limite, 200), 1), 500);
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'limite', v_lim, 'recusas', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'fonte', r.fonte, 'execucao_id', r.execucao_id, 'posicao', r.posicao, 'id_externo', r.id_externo,
             'motivo', r.motivo, 'criado_em', r.criado_em, 'anonimizada', r.anonimizado_em is not null,
             'anonimizado_em', r.anonimizado_em, 'expurgada', r.expurgado_em is not null)
           order by r.criado_em desc, r.id desc), '[]'::jsonb)
      from (select * from mkt_mensageria.recusas x
             where v_fonte is null or x.fonte = v_fonte
             order by x.criado_em desc, x.id desc limit v_lim) r));
end
$$;
revoke all on function public.mkt_msg_recusas_listar(text, integer) from public, anon, authenticated;
grant execute on function public.mkt_msg_recusas_listar(text, integer) to authenticated;

-- Recebe um lote da fonte (rota POST /api/mensageria/receber, com service_role). Só service_role executa.
-- Chave errada, fonte desconhecida ou inativa: {ok:false, erro:'nao_autorizado'} (a rota devolve 401 genérico).
-- Inativa com chave certa grava execução 'fonte_inativa'. Lote: array de até 1.000 itens; vazio = "rodei, nada novo".
create function public.mkt_msg_api_receber(p_fonte text, p_chave text, p_lote jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inicio timestamptz := clock_timestamp();
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  r jsonb;
  v_n integer;
  v_status text;
  v_exec bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if not v_ativa then
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'fonte_inativa', 'Fonte desligada em mkt_mensageria.fontes: lote não lido.');
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_lote is null or jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 1000 then
    v_n := case when jsonb_typeof(p_lote) = 'array' then jsonb_array_length(p_lote) end;
    insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status, detalhe)
    values (v_fonte, v_inicio, clock_timestamp(), 0, 0, 0, 0, 0, 'lote_invalido',
            case when v_n is null then 'Lote não é um array JSON.' else 'Lote de ' || v_n || ' itens (máximo 1.000).' end);
    return jsonb_build_object('ok', false, 'erro', case when v_n is null then 'lote_invalido' else 'lote_grande' end, 'limite', 1000);
  end if;

  r := mkt_mensageria.api_upsert(v_fonte, p_lote);
  v_status := case when (r ->> 'lidos')::int = (r ->> 'inseridos')::int + (r ->> 'atualizados')::int
                                              + (r ->> 'inalterados')::int + (r ->> 'recusados')::int
                   then 'ok' else 'inconsistente' end;
  insert into mkt_mensageria.execucoes (fonte, inicio, fim, lidos, inseridos, atualizados, inalterados, recusados, status)
  values (v_fonte, v_inicio, clock_timestamp(), (r ->> 'lidos')::int, (r ->> 'inseridos')::int, (r ->> 'atualizados')::int,
          (r ->> 'inalterados')::int, (r ->> 'recusados')::int, v_status)
  returning id into v_exec;
  insert into mkt_mensageria.recusas (execucao_id, fonte, posicao, id_externo, motivo, payload)
  select v_exec, v_fonte, (x ->> 'posicao')::int, left(x ->> 'id_externo', 200), left(x ->> 'motivo', 500), x -> 'payload'
    from jsonb_array_elements(r -> 'recusas') x;
  return jsonb_build_object('ok', true, 'execucao_id', v_exec, 'status', v_status,
    'lidos', (r ->> 'lidos')::int, 'inseridos', (r ->> 'inseridos')::int, 'atualizados', (r ->> 'atualizados')::int,
    'inalterados', (r ->> 'inalterados')::int, 'recusados', (r ->> 'recusados')::int,
    'recusas', (select coalesce(jsonb_agg(x - 'payload'), '[]'::jsonb)
                  from (select x from jsonb_array_elements(r -> 'recusas') x limit 100) s));
end
$$;
revoke all on function public.mkt_msg_api_receber(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_receber(text, text, jsonb) to service_role;

-- Reconciliação diária: a fonte manda os id_externo que ela enviou no dia (São Paulo); grava quantos estão no log e
-- quais faltam (até 500). Mesma autenticação de api_receber; fonte inativa = nao_autorizado.
create function public.mkt_msg_api_reconciliar(p_fonte text, p_chave text, p_dia date, p_ids jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_fonte text := btrim(coalesce(p_fonte, ''));
  v_ativa boolean;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_fonte_qtd integer;
  v_log integer;
  v_falt_total integer;
  v_falt jsonb;
  v_id bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'acesso negado' using errcode = '42501'; end if;
  select f.ativa into v_ativa from mkt_mensageria.fontes f where f.chave = v_fonte;
  if v_ativa is null or not v_ativa or not mkt_mensageria.chave_ok(v_fonte, p_chave) then
    return jsonb_build_object('ok', false, 'erro', 'nao_autorizado');
  end if;
  if p_dia is null or p_dia > v_hoje or p_dia < v_hoje - 400 then
    return jsonb_build_object('ok', false, 'erro', 'dia_invalido');
  end if;
  if p_ids is null or jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) > 20000 then
    return jsonb_build_object('ok', false, 'erro', 'ids_invalidos', 'limite', 20000);
  end if;
  with ids as (
    select distinct left(btrim(x), 200) as id from jsonb_array_elements_text(p_ids) x where btrim(x) <> ''
  ), falt as (
    select i.id from ids i
     where not exists (select 1 from mkt_mensageria.disparos d where d.origem_sistema = v_fonte and d.id_externo = i.id)
  )
  select (select count(*) from ids), (select count(*) from falt),
         (select coalesce(jsonb_agg(s.id order by s.id), '[]'::jsonb) from (select id from falt order by id limit 500) s)
    into v_fonte_qtd, v_falt_total, v_falt;
  select count(*) into v_log from mkt_mensageria.disparos d
   where d.enviado_em >= p_dia::timestamp at time zone 'America/Sao_Paulo'
     and d.enviado_em < (p_dia + 1)::timestamp at time zone 'America/Sao_Paulo'
     and d.origem_sistema = v_fonte and d.arquivado_em is null;
  insert into mkt_mensageria.reconciliacao (fonte, dia, contagem_fonte, contagem_log, faltantes_total, faltantes)
  values (v_fonte, p_dia, v_fonte_qtd, v_log, v_falt_total, v_falt)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'dia', p_dia, 'contagem_fonte', v_fonte_qtd, 'contagem_log', v_log,
                            'faltantes_total', v_falt_total, 'faltantes', v_falt);
end
$$;
revoke all on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) from public, anon, authenticated;
grant execute on function public.mkt_msg_api_reconciliar(text, text, date, jsonb) to service_role;

-- Saúde das integrações: uma linha por fonte. Atraso pela mesma regra do vigia (mkt_mensageria.fonte_atraso).
create function public.mkt_msg_integracoes_saude() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(mkt.pode_ver('mkt_mensageria'), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'agora', now(), 'fontes', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'chave', f.chave, 'nome', f.nome, 'ferramenta_id', f.ferramenta_id, 'ferramenta', fe.nome,
             'ativa', f.ativa, 'ativa_desde', f.ativa_desde,
             'intervalo_minutos', (extract(epoch from f.intervalo_esperado) / 60)::int,
             'ultima_execucao_em', ue.inicio, 'ultima_execucao_status', ue.status,
             'ultima_ok_em', a.ultima_ok_em,
             'atraso_minutos', (extract(epoch from a.atraso) / 60)::int, 'atrasada', a.atrasada,
             'execucoes_7d', s.execucoes, 'recusas_7d', s.recusas, 'inconsistentes_7d', s.inconsistentes,
             'negadas_7d', s.negadas,
             'chave_no_vault', exists (select 1 from vault.secrets v where v.name = 'mkt_msg_fonte_' || f.chave),
             'vigia_jobname', mkt_mensageria.fonte_jobname(f.chave),
             'ultima_reconciliacao', case when rc.id is not null then jsonb_build_object(
                'dia', rc.dia, 'contagem_fonte', rc.contagem_fonte, 'contagem_log', rc.contagem_log,
                'faltantes_total', rc.faltantes_total, 'em', rc.criado_em) end)
           order by f.chave), '[]'::jsonb)
      from mkt_mensageria.fontes f
      left join mkt_mensageria.ferramentas fe on fe.id = f.ferramenta_id
      cross join lateral mkt_mensageria.fonte_atraso(f.chave) a
      left join lateral (select e.inicio, e.status from mkt_mensageria.execucoes e
                          where e.fonte = f.chave order by e.inicio desc limit 1) ue on true
      left join lateral (select count(*) as execucoes, coalesce(sum(e.recusados), 0) as recusas,
                                count(*) filter (where e.status = 'inconsistente') as inconsistentes,
                                count(*) filter (where e.status in ('fonte_inativa', 'lote_invalido')) as negadas
                           from mkt_mensageria.execucoes e
                          where e.fonte = f.chave and e.inicio >= now() - interval '7 days') s on true
      left join lateral (select r.* from mkt_mensageria.reconciliacao r
                          where r.fonte = f.chave order by r.dia desc, r.id desc limit 1) rc on true));
end
$$;
revoke all on function public.mkt_msg_integracoes_saude() from public, anon, authenticated;
grant execute on function public.mkt_msg_integracoes_saude() to authenticated;

-- ─── 9. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  fn record;
  v_tela text[] := array['mkt_msg_disparos_listar', 'mkt_msg_disparo_salvar', 'mkt_msg_disparo_arquivar',
                         'mkt_msg_disparo_lancar_retorno', 'mkt_msg_importar', 'mkt_msg_numeros_listar',
                         'mkt_msg_numero_salvar', 'mkt_msg_ferramentas_listar', 'mkt_msg_ferramenta_salvar',
                         'mkt_msg_historico', 'mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa',
                         'mkt_msg_precos_listar', 'mkt_msg_preco_salvar', 'mkt_msg_preco_anular', 'mkt_msg_integracoes_saude',
                         'mkt_msg_recusas_listar'];
  v_api text[] := array['mkt_msg_api_receber', 'mkt_msg_api_reconciliar', 'mkt_msg_api_chave_ok'];
  v_admin text[] := array['mkt_msg_anonimizar_disparo', 'mkt_msg_anonimizar_recusa', 'mkt_msg_recusas_listar'];
begin
  for t in select c.oid::regclass::text from pg_class c
            where c.relnamespace = 'mkt_mensageria'::regnamespace and c.relkind in ('r', 'S') loop
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if (select c.relkind from pg_class c where c.oid = t::regclass) = 'r'
         and has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005o: % tem privilégio em %', r, t;
      end if;
    end loop;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a where c.oid = t::regclass and a.grantee = 0) then
      raise exception '20261005o: PUBLIC tem privilégio em %', t;
    end if;
    if (select c.relkind = 'r' and not c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005o: RLS desligada em %', t;
    end if;
  end loop;

  for fn in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl, p.prosrc
             from pg_proc p
            where p.pronamespace = 'mkt_mensageria'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') loop
    if not (fn.proconfig @> array['search_path=""']) then
      raise exception '20261005o: % sem search_path vazio', fn.sig;
    end if;
    if has_function_privilege('anon', fn.sig, 'execute') then
      raise exception '20261005o: anon executa %', fn.sig;
    end if;
    if fn.proacl is null or exists (select 1 from aclexplode(fn.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005o: PUBLIC executa %', fn.sig;
    end if;
    if (fn.pronamespace = 'public'::regnamespace and fn.proname = any(v_tela)) <> has_function_privilege('authenticated', fn.sig, 'execute') then
      raise exception '20261005o: grant de authenticated errado em %', fn.sig;
    end if;
    if fn.proname = any(v_api) and not has_function_privilege('service_role', fn.sig, 'execute') then
      raise exception '20261005o: service_role não executa %', fn.sig;
    end if;
    if fn.pronamespace = 'public'::regnamespace and not fn.prosecdef then
      raise exception '20261005o: % deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.pronamespace = 'mkt_mensageria'::regnamespace and fn.prosecdef then
      raise exception '20261005o: interna % não deveria ser SECURITY DEFINER', fn.sig;
    end if;
    if fn.proname = any(v_tela) and not (fn.proname = any(v_admin))
       and position('if not coalesce(mkt.pode_ver(''mkt_mensageria''), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda mkt.pode_ver', fn.sig;
    end if;
    if fn.proname = any(v_admin) and position('if not coalesce(public.gp_is_admin(), false) then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda gp_is_admin', fn.sig;
    end if;
    if fn.proname = any(v_api) and position('if coalesce(auth.role(), '''') <> ''service_role'' then raise exception' in fn.prosrc) = 0 then
      raise exception '20261005o: % sem a guarda de service_role', fn.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_msg\_%') <> 20
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_tela || v_api)) <> 20 then
    raise exception '20261005o: esperava exatamente 20 funções public.mkt_msg_* (sobrecarga?)';
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'mkt_mensageria'
                and ((table_name = 'precos' and column_name in ('ferramenta_id', 'canal', 'tipo', 'base_cobranca', 'preco_centavos', 'vigente_desde'))
                  or (table_name = 'fontes' and column_name in ('ativa', 'intervalo_esperado', 'ferramenta_id'))
                  or (table_name = 'disparos' and column_name in ('entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'projeto_id')))
                and column_default is not null) then
    raise exception '20261005o: coluna de regra com default';
  end if;
  if (select count(*) from mkt_mensageria.precos) <> 7
     or exists (select 1 from mkt_mensageria.precos p join mkt_mensageria.ferramentas f on f.id = p.ferramenta_id where f.nome = 'Infobip') then
    raise exception '20261005o: seed de preços diferente do esperado (7 linhas, Infobip sem preço)';
  end if;
  if (select count(*) from mkt_mensageria.fontes where not ativa) <> 5 or (select count(*) from mkt_mensageria.fontes) <> 5 then
    raise exception '20261005o: seed de fontes diferente do esperado (5, todas desligadas)';
  end if;
  if (select count(*) from vault.secrets s join mkt_mensageria.fontes f on s.name = 'mkt_msg_fonte_' || f.chave) <> 5 then
    raise exception '20261005o: faltou chave no Vault';
  end if;
  if (select count(*) from cron.job j join mkt_mensageria.fontes f on j.jobname = mkt_mensageria.fonte_jobname(f.chave)
       where not j.active) <> 5
     or (select count(*) from ops.rotina o join mkt_mensageria.fontes f on o.jobname = mkt_mensageria.fonte_jobname(f.chave)) <> 5 then
    raise exception '20261005o: jobs do vigia das fontes (5 desligados + 5 em ops.rotina) diferente do esperado';
  end if;
  if not exists (select 1 from cron.job j join ops.rotina o using (jobname) where j.jobname = 'mensageria-recusas-expurgo' and j.active) then
    raise exception '20261005o: job de expurgo das recusas ausente (cron.job ativo + ops.rotina)';
  end if;
  if exists (select 1 from cron.job where jobname = 'ingest-mensageria-hourly' and active) then
    raise exception '20261005o: ingest-mensageria-hourly continua ativo';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação) ═══════════════════════════════════════════════════════════════════════════════════════
-- Só o cron antigo (P3), sem mexer no resto:
--   select cron.alter_job((select jobid from cron.job where jobname = 'ingest-mensageria-hourly'), active := true);
--   update ops.rotina set silenciado_ate = null where jobname = 'ingest-mensageria-hourly';
-- Desligar uma fonte sem deploy: update mkt_mensageria.fontes set ativa = false where chave = '<fonte>';
-- Tudo (exportar antes recusas/execucoes; disparos de origem api precisam de projeto antes de voltar o NOT NULL):
-- begin;
-- select cron.unschedule(j.jobname) from cron.job j where j.jobname like 'mensageria-fonte-%' or j.jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina_estado where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from ops.rotina where jobname like 'mensageria-fonte-%' or jobname = 'mensageria-recusas-expurgo';
-- delete from vault.secrets where name like 'mkt\_msg\_fonte\_%';
-- drop function public.mkt_msg_api_receber(text, text, jsonb), public.mkt_msg_api_reconciliar(text, text, date, jsonb),
--   public.mkt_msg_integracoes_saude(), public.mkt_msg_precos_listar(), public.mkt_msg_preco_salvar(jsonb),
--   public.mkt_msg_preco_anular(bigint, text), public.mkt_msg_anonimizar_recusa(bigint, text),
--   public.mkt_msg_api_chave_ok(text, text), public.mkt_msg_recusas_listar(text, integer);
-- -- reaplicar da 20261005n: mkt_msg_disparos_listar, mkt_msg_disparo_salvar, mkt_msg_disparo_lancar_retorno,
-- --   mkt_msg_historico, mkt_msg_anonimizar_disparo, mkt_mensageria.trg_historico (create or replace)
-- drop table mkt_mensageria.recusas, mkt_mensageria.reconciliacao, mkt_mensageria.execucoes, mkt_mensageria.fontes,
--   mkt_mensageria.precos;
-- drop function mkt_mensageria.api_upsert(text, jsonb), mkt_mensageria.api_item(text, bigint, jsonb),
--   mkt_mensageria.chave_ok(text, text), mkt_mensageria.vigiar_fonte(text), mkt_mensageria.fonte_atraso(text),
--   mkt_mensageria.pendencias_v2(text, bigint, integer, integer, integer, bigint, boolean),
--   mkt_mensageria.custo_estimado(bigint, text, text, timestamptz, integer, integer), mkt_mensageria.fonte_jobname(text),
--   mkt_mensageria.trg_preco_anular(), mkt_mensageria.trg_fonte(), mkt_mensageria.trg_recusa_anonimizar(),
--   mkt_mensageria.recusas_expurgar();
-- alter table mkt_mensageria.historico drop column por_api;
-- alter table mkt_mensageria.disparos drop column campanha, drop column anonimizado_em, drop constraint disparos_projeto_fora_da_api;
-- alter table mkt_mensageria.disparos alter column projeto_id set not null;   -- falha se houver linha da API sem projeto
-- commit;

-- ═══ PREPARO DO ENSAIO (saída em _z_out; admin real achado por subselect, sem uid escrito; chave nunca impressa) ═════
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create temp table _z_admin (id uuid) on commit drop;
grant all on _z_admin to public;
do $admin$
declare c uuid;
begin
  for c in select p.id from public.perfis p order by p.id limit 5000 loop
    perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    if coalesce(public.gp_is_admin(), false) then
      insert into pg_temp._z_admin values (c);
      exit;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if not exists (select 1 from pg_temp._z_admin) then
    raise exception 'ENSAIO: nenhum perfil com gp_is_admin() = true';
  end if;
end
$admin$;
-- Projetos (2 siglas reais), ferramentas e a chave da fonte unichat (lida do Vault DENTRO da transação abortada).
create temp table _z_ref on commit drop as
  select (select pr.id from mkt.projetos pr order by pr.id limit 1) as proj1,
         (select pr.sigla from mkt.projetos pr order by pr.id limit 1) as sigla1,
         (select pr.sigla from mkt.projetos pr order by pr.id offset 1 limit 1) as sigla2,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Unichat') as unichat,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'ActiveCampaign') as activecampaign,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'SendFlow') as sendflow,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Infobip') as infobip,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Ligue Lead') as liguelead,
         (select f.id from mkt_mensageria.ferramentas f where f.nome = 'Clint') as clint,
         (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'mkt_msg_fonte_unichat') as chave;
grant all on _z_ref to public;
create temp table _z_ids (nome text primary key, id bigint) on commit drop;
grant all on _z_ids to public;
create function pg_temp.como_admin() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp._z_admin), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end
$f$;
-- Como a rota chama: PostgREST com a service_role key (role service_role, claims role = service_role).
create function pg_temp.como_servico() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end
$f$;
create function pg_temp.ok(p_passo text, p_linha text) returns void language plpgsql as $f$
begin
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_linha);
  raise notice '% PASSOU: %', p_passo, p_linha;
end
$f$;
-- Item de lote da API (unichat, WhatsApp). p_extra sobrepõe/acrescenta campos.
create function pg_temp.item(p_id text, p_campanha text, p_extra jsonb default '{}') returns jsonb language sql as $f$
  select jsonb_build_object('id_externo', p_id, 'campanha', p_campanha, 'canal', 'whatsapp_api', 'tipo', 'marketing',
           'enviado_em', '2026-09-15T10:00:00-03:00', 'copy_texto', 'Copy ' || p_id, 'publico_lista', 'Lista ' || p_id,
           'tamanho_lista', 100, 'entregues', 90, 'lidas', 50) || p_extra
$f$;

-- ═══ BLOCO 3: API no teto (lote de 1.000) e reconciliação de 20.000 ids. Teto do PostgREST: 8 s por chamada ═══════
update mkt_mensageria.fontes set ativa = true where chave = 'unichat';
create temp table _z_lote on commit drop as
  select jsonb_agg(pg_temp.item('L' || i, case when i % 2 = 0 then '[' || (select sigla1 from pg_temp._z_ref) || '] lote' else 'lote sem sigla' end,
                                jsonb_build_object('copy_texto', repeat('x', 300) || i, 'tamanho_lista', 100 + i % 50)) order by i) as novo,
         jsonb_agg(jsonb_build_object('id_externo', 'L' || i, 'entregues', 95, 'lidas', 60) order by i) as mudanca
    from generate_series(1, 1000) i;
grant all on _z_lote to public;

do $a$
declare
  v_chave text := (select chave from pg_temp._z_ref);
  v_novo jsonb := (select novo from pg_temp._z_lote);
  v_mud jsonb := (select mudanca from pg_temp._z_lote);
  t0 timestamptz;
  r jsonb;
  v_ids jsonb := (select jsonb_agg('L' || i) from generate_series(1, 20000) i);
begin
  perform pg_temp.como_servico();
  t0 := clock_timestamp(); r := public.mkt_msg_api_receber('unichat', v_chave, v_novo);
  perform pg_temp.ok('A1 lote 1.000 novos', round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, inseridos='
    || (r ->> 'inseridos') || ', recusados=' || (r ->> 'recusados') || ', status=' || (r ->> 'status')
    || ', corpo ' || pg_size_pretty(length(v_novo::text)::bigint));
  if (r ->> 'inseridos')::int <> 1000 then reset role; raise exception 'A1 FALHOU: %', r - 'recusas'; end if;
  t0 := clock_timestamp(); r := public.mkt_msg_api_receber('unichat', v_chave, v_novo);
  perform pg_temp.ok('A2 mesmo lote de novo', round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, inalterados='
    || (r ->> 'inalterados') || ', atualizados=' || (r ->> 'atualizados'));
  if (r ->> 'inalterados')::int <> 1000 then reset role; raise exception 'A2 FALHOU: %', r - 'recusas'; end if;
  t0 := clock_timestamp(); r := public.mkt_msg_api_receber('unichat', v_chave, v_mud);
  perform pg_temp.ok('A3 1.000 com retorno novo', round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, atualizados='
    || (r ->> 'atualizados'));
  if (r ->> 'atualizados')::int <> 1000 then reset role; raise exception 'A3 FALHOU: %', r - 'recusas'; end if;
  t0 := clock_timestamp(); r := public.mkt_msg_api_reconciliar('unichat', v_chave, date '2026-09-15', v_ids);
  perform pg_temp.ok('A4 reconciliar 20.000 ids', round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, contagem_fonte='
    || (r ->> 'contagem_fonte') || ', contagem_log=' || (r ->> 'contagem_log') || ', faltantes_total=' || (r ->> 'faltantes_total'));
  if (r ->> 'faltantes_total')::int <> 19000 then reset role; raise exception 'A4 FALHOU: %', r - 'faltantes'; end if;
  reset role;
  perform pg_temp.ok('A5 contagens', (select count(*) from mkt_mensageria.disparos where origem = 'api') || ' disparos api, '
    || (select count(*) from mkt_mensageria.disparos where origem = 'api' and projeto_id is null) || ' sem projeto, '
    || (select count(*) from mkt_mensageria.historico where por_api = 'api:unichat') || ' linhas de histórico api:unichat, '
    || (select count(*) from mkt_mensageria.execucoes where status = 'ok') || ' execuções ok');
end
$a$;

-- Fim do bloco 3: aborta de propósito (nada fica gravado) e devolve o relatório na mensagem.
reset role;
do $fim$
begin
  raise exception '%', E'ENSAIO 20261005o BLOCO 3 CONCLUÍDO: tudo passou. Aborto proposital, nada foi gravado.
'
    || (select string_agg(passo || ' | ' || linha, E'
' order by em) from pg_temp._z_out);
end
$fim$;
rollback;
-- ◀ FIM DO BLOCO 3
