-- Ensaio das 20261008210425 (z01) + 20261008210456 (z02) (Clínica Miami + roteamento Hotmart por oferta). Termina em ROLLBACK.
-- Esperado: termina com ERROR 'ENSAIO_OK {...}' (o raise final desfaz tudo) e cada passo S0..S8 confere o resultado.
begin;
-- 20261008z01: Comercial, linha "Clínica Internacional Diamante" (Miami) + roteamento da Hotmart por OFERTA ("opção A").
--
-- STATUS: (preenchido depois de aplicar)
--
-- PEDIDO: Arthur, 08/10/2026, ok explícito no chat da sessão principal.
--
-- POR QUE
--   crm.hotmart_processar escolhe a linha pelo PRODUTO (crm.produto_comercial). O checkout da pré-venda de Miami é a
--   oferta sju5pawn ("Clínica de Holding Familiar - Miami", R$ 5.014,20) do produto 5682989, que é COMPARTILHADO com as
--   Clínicas nacionais (9 outras ofertas em fin.ofertas). Colocar o produto inteiro no comercial jogaria toda Clínica
--   nacional no funil de Miami. Então: vínculo por OFERTA, com precedência sobre o do produto.
--
-- O QUE FAZ
--   1. crm.linha: chave clinica_miami (o CHECK linha_chave_check é '^[a-z0-9_]{2,20}$': hífen não passa, por isso
--      "clinica_miami" e não "clinica-miami"), escada B, ticket_ref 5014.20, ordem = última + 1, ativa.
--   2. crm.oferta_linha (nova): oferta_codigo (PK, FK fin.ofertas) → linha / agrupador / nome comercial, com flag ativo
--      (kill-switch por oferta, sem apagar). RLS: leitura = crm.eh_comercial() (igual a produto_comercial); escrita só
--      pela RPC. Log pelo crm.tg_log (entidade 'oferta').
--   3. public.crm_vincular_oferta(jsonb): RPC de escrita (crm.guarda_escrita + crm.eh_gestor), mesmo contrato de
--      crm_vincular_produto ({ok,msg}).
--   4. crm.hotmart_processar (remendo sobre o corpo VIVO, md5 conferido):
--      a) linha/agrupador: primeiro crm.oferta_linha (ativo) pelo oferta_codigo do evento; sem vínculo, produto_comercial
--         como antes;
--      b) "já comprou a linha em 30 dias": a compra da jornada vale pela linha da OFERTA (se vinculada) e senão pela do
--         produto. Compra de sju5pawn conta como clinica_miami, não como Clínica nacional;
--      c) fechar como ganho já era por negócio.linha = pc.linha; com (a), compra aprovada de sju5pawn fecha o negócio
--         aberto de Miami. Nada muda na ativação (crm.projeto_ativacao está vazia; a regra por produto fica igual).
--   5. crm.hotmart_norm_evento (remendo, md5 conferido): o webhook de carrinho abandonado (PURCHASE_OUT_OF_SHOPPING_CART)
--      traz a oferta em data.offer.code, não em data.purchase.offer.code. Medido: 5 de 5 carrinhos do webhook
--      gravados com oferta_codigo NULL. Sem isso o carrinho de sju5pawn nunca acharia o vínculo. Agora:
--      coalesce(purchase.offer.code, offer.code).
--      Efeito colateral (desejado e registrado): carrinho de HT/Acelera/HM/Aurum passa a gravar a oferta; valor do
--      negócio vem do preço da oferta (antes caía no ticket_ref da linha); oferta fora do catálogo passa a avisar no
--      Slack como já acontece em compra/boleto.
--   6. Vínculo sju5pawn → clinica_miami é feito na migration de dados seguinte (precisa do agrupador, criado pela RPC).
--
-- NÃO FAZ: não coloca o produto 5682989 em crm.produto_comercial; não toca crm.escolher_dono (contato com dono mantém o
--   dono); não toca crm.supressao_motivo nem crm.origem_catalogar (seguem pela linha do produto: anotado no explain).
--
-- AS 5 PERGUNTAS
--   escala: oferta_linha tem dezenas de linhas no máximo; lookup por PK. O "30 dias" já varria só os eventos 'compra'
--     da pessoa (grupo); agora são 2 lookups por PK por evento da pessoa em vez de 1 join.
--   índice: PK de oferta_linha e de produto_comercial; pessoas.eventos continua pelo índice da pessoa.
--   frequência: por evento Hotmart (o mesmo de hoje).
--   repetição: nenhuma.
--   reversão: update crm.oferta_linha set ativo = false (kill-switch por oferta, efeito imediato); corpo anterior das
--     2 funções no .explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- ─── 0. Guarda de premissa ─────────────────────────────────────────────────────────────────────────────────────────
do $g$
begin
  if md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) <> '61d6dc39b5e2030d3ea7546878da7277' then
    raise exception '20261008z01: crm.hotmart_processar mudou desde a leitura (md5 %)', md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure));
  end if;
  if md5(pg_get_functiondef('crm.hotmart_norm_evento(jsonb)'::regprocedure)) <> '7a12217d022bdc4284204c5b22ca961f' then
    raise exception '20261008z01: crm.hotmart_norm_evento mudou desde a leitura';
  end if;
  if exists (select 1 from crm.linha where chave = 'clinica_miami') then
    raise exception '20261008z01: linha clinica_miami já existe';
  end if;
  if to_regclass('crm.oferta_linha') is not null then raise exception '20261008z01: crm.oferta_linha já existe'; end if;
  if not exists (select 1 from fin.ofertas where oferta_codigo = 'sju5pawn' and produto_id = '5682989') then
    raise exception '20261008z01: oferta sju5pawn do produto 5682989 não está em fin.ofertas';
  end if;
  if exists (select 1 from crm.produto_comercial where produto_id = '5682989' and no_comercial) then
    raise exception '20261008z01: produto 5682989 já está no comercial; o desenho assume que não';
  end if;
end $g$;

-- ─── 1. linha ──────────────────────────────────────────────────────────────────────────────────────────────────────
insert into crm.linha (chave, nome, escada, ticket_ref, ordem, ativo)
select 'clinica_miami', 'Clínica Internacional Diamante', 'B', 5014.20, coalesce(max(l.ordem), 0) + 1, true from crm.linha l;

-- ─── 2. vínculo por oferta ─────────────────────────────────────────────────────────────────────────────────────────
create table crm.oferta_linha (
  oferta_codigo  text primary key references fin.ofertas(oferta_codigo) on delete restrict,
  linha          text not null references crm.linha(chave) on delete restrict,
  agrupador_id   uuid references crm.agrupador(id) on delete restrict,
  nome_comercial text check (nome_comercial is null or length(btrim(nome_comercial)) between 1 and 120),
  ativo          boolean not null default true,
  vinculado_por  uuid references public.perfis(id) on delete restrict,
  vinculado_em   timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table crm.oferta_linha is
  'Vínculo de uma OFERTA Hotmart a uma linha comercial. Precedência sobre crm.produto_comercial em crm.hotmart_processar. ativo=false desliga (kill-switch). 20261008z01.';
alter table crm.oferta_linha enable row level security;
revoke all on crm.oferta_linha from public, anon, authenticated;
grant select on crm.oferta_linha to authenticated;
grant all on crm.oferta_linha to service_role;
create policy oferta_linha_ler on crm.oferta_linha for select to authenticated using ((select crm.eh_comercial()));
create trigger oferta_linha_log_ins_del after insert or delete on crm.oferta_linha
  for each row execute function crm.tg_log('oferta', 'oferta_codigo');
create trigger oferta_linha_log_upd after update on crm.oferta_linha
  for each row when (old.* is distinct from new.*) execute function crm.tg_log('oferta', 'oferta_codigo');

-- ─── 3. RPC de escrita ─────────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_vincular_oferta(p_oferta jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_cod text := btrim(coalesce(p_oferta ->> 'ofertaCodigo', ''));
        v_linha text := nullif(p_oferta ->> 'produtoKey', ''); v_ag uuid := crm.uuid_ou_null(p_oferta ->> 'agrupadorId');
        v_nome text := nullif(btrim(coalesce(p_oferta ->> 'nomeComercial', '')), '');
        v_ativo boolean := coalesce((p_oferta ->> 'ativo')::boolean, true); v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor vincula ofertas.'); end if;
  if not exists (select 1 from fin.ofertas o where o.oferta_codigo = v_cod) then
    return crm.res(false, 'Oferta não veio da Hotmart. Ela aparece depois da sincronização.');
  end if;
  if v_linha is null or not exists (select 1 from crm.linha l where l.chave = v_linha) then return crm.res(false, 'Produto inválido.'); end if;
  if nullif(p_oferta ->> 'agrupadorId', '') is not null
     and (v_ag is null or not exists (select 1 from crm.agrupador a where a.id = v_ag and a.arquivado_em is null)) then
    return crm.res(false, 'Agrupador não encontrado.');
  end if;
  perform set_config('crm.resumo', format('%s a oferta %s (%s)', case when v_ativo then 'Vinculou' else 'Desligou o vínculo da' end,
                                          v_cod, v_linha), true);
  insert into crm.oferta_linha (oferta_codigo, linha, agrupador_id, nome_comercial, ativo, vinculado_por)
  values (v_cod, v_linha, v_ag, v_nome, v_ativo, v_eu)
  on conflict (oferta_codigo) do update
     set linha = excluded.linha, agrupador_id = excluded.agrupador_id,
         nome_comercial = coalesce(excluded.nome_comercial, crm.oferta_linha.nome_comercial),
         ativo = excluded.ativo, atualizado_em = now()
   where (crm.oferta_linha.linha, crm.oferta_linha.agrupador_id, crm.oferta_linha.nome_comercial, crm.oferta_linha.ativo)
         is distinct from (excluded.linha, excluded.agrupador_id, coalesce(excluded.nome_comercial, crm.oferta_linha.nome_comercial),
                           excluded.ativo);
  return crm.res(true, case when v_ativo then 'Oferta vinculada ao comercial.' else 'Vínculo da oferta desligado.' end);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke execute on function public.crm_vincular_oferta(jsonb) from public, anon;
grant execute on function public.crm_vincular_oferta(jsonb) to authenticated, service_role;

-- ─── 4 e 5. remendos sobre os corpos vivos ─────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.remendar(p_fn regprocedure, p_md5 text, p_pares jsonb) returns void
language plpgsql as $f$
declare v text := pg_get_functiondef(p_fn); par jsonb; n int;
begin
  if md5(v) <> p_md5 then raise exception 'premissa: % mudou (md5 vivo %, esperado %)', p_fn, md5(v), p_md5; end if;
  for par in select x from jsonb_array_elements(p_pares) x loop
    n := (length(v) - length(replace(v, par ->> 0, ''))) / length(par ->> 0);
    if n <> 1 then raise exception 'premissa: trecho aparece % vez(es) em %: %', n, p_fn, left(par ->> 0, 120); end if;
    v := replace(v, par ->> 0, par ->> 1);
  end loop;
  execute v;
end $f$;

select pg_temp.remendar('crm.hotmart_processar(jsonb)', '61d6dc39b5e2030d3ea7546878da7277', jsonb_build_array(
  jsonb_build_array(
$a$  select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  if not found then$a$,
$b$  -- 20261008z01: vínculo por OFERTA (crm.oferta_linha, ativo) tem precedência sobre o do produto
  select p ->> 'produto_id', true, ol.nome_comercial, ol.linha, l.escada, ol.agrupador_id, ol.vinculado_por, ol.vinculado_em
    into pc
    from crm.oferta_linha ol join crm.linha l on l.chave = ol.linha
   where ol.oferta_codigo = p ->> 'oferta_codigo' and ol.ativo;
  if not found then
    select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  end if;
  if not found then$b$),
  jsonb_build_array(
$a$       or exists (select 1 from pessoas.eventos e
                    join crm.produto_comercial y on y.produto_id = e.detalhe ->> 'produto' and y.no_comercial and y.linha = pc.linha
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days') then$a$,
$b$       or exists (select 1 from pessoas.eventos e
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days'
                     -- 20261008z01: a compra conta pela linha da OFERTA (se vinculada), senão pela do produto
                     and coalesce((select ol.linha from crm.oferta_linha ol where ol.oferta_codigo = e.detalhe ->> 'oferta' and ol.ativo),
                                  (select y.linha from crm.produto_comercial y
                                    where y.produto_id = e.detalhe ->> 'produto' and y.no_comercial)) = pc.linha) then$b$)));

select pg_temp.remendar('crm.hotmart_norm_evento(jsonb)', '7a12217d022bdc4284204c5b22ca961f', jsonb_build_array(
  jsonb_build_array(
$a$    'oferta_codigo', nullif(d -> 'purchase' -> 'offer' ->> 'code', ''),$a$,
$b$    -- 20261008z01: carrinho abandonado traz a oferta em data.offer.code
    'oferta_codigo', nullif(coalesce(d -> 'purchase' -> 'offer' ->> 'code', d -> 'offer' ->> 'code'), ''),$b$)));

-- ─── 6. conferência ────────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v text;
begin
  select proacl::text into v from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure;
  if v <> '{postgres=X/postgres}' then raise exception '20261008z01: acl de hotmart_processar mudou: %', v; end if;
  if position('crm.oferta_linha' in (select prosrc from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure)) = 0 then
    raise exception '20261008z01: remendo de hotmart_processar não entrou';
  end if;
  select proacl::text into v from pg_proc where oid = 'public.crm_vincular_oferta(jsonb)'::regprocedure;
  if v ~ '(^|[{,])=X' or v ~ 'anon=' then raise exception '20261008z01: crm_vincular_oferta aberta a PUBLIC/anon: %', v; end if;
end $c$;

notify pgrst, 'reload schema';
-- 20261008z02: Comercial, estrutura da Clínica Internacional Diamante (Miami): agrupador, 2 funis, distribuição própria
-- e vínculo da oferta sju5pawn. Tudo pelas RPCs oficiais com o JWT do Arthur (arthur@advmais.com), para o Registro
-- (crm.log) mostrar o autor. Depende da 20261008z01 (linha clinica_miami, crm.oferta_linha, crm_vincular_oferta).
--
-- STATUS: (preenchido depois de aplicar)
--
-- O QUE CRIA
--   agrupador "Clínica Internacional Diamante" (linha clinica_miami)            → public.crm_criar_agrupador
--   funil a) "Venda ativa · Clínica Miami" (manual, ícone gem)                   → public.crm_salvar_funil
--   funil b) "Checkout e recuperação · Clínica Miami" (hotmart, ícone zap)       → public.crm_salvar_funil
--     os dois: projeto clinica-miami-2026-12, distribuição própria Jonathan Mendes 50% + Marcos Paulo 50%
--   vínculo sju5pawn → clinica_miami / agrupador novo                             → public.crm_vincular_oferta
--   "Apresentar a oferta" usa o papel apresentar_oferta (existe no CHECK etapa_funil_papel_check).
--   Etapas do funil b = cópia das etapas ativas de "Checkout e recuperação · HT" (nomes, papéis, cores, SLAs,
--   campos obrigatórios e critérios), lidas em 08/10/2026.
--
-- NÃO FAZ: não importa lead; não cria campanha; não mexe na distribuição geral (funil_id null).
-- REVERSÃO: crm_arquivar_funil nos 2 funis; crm_vincular_oferta com ativo=false (ou update crm.oferta_linha set ativo=false).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if not exists (select 1 from crm.linha where chave = 'clinica_miami') or to_regclass('crm.oferta_linha') is null then
    raise exception '20261008z02: falta a 20261008z01';
  end if;
  if exists (select 1 from crm.agrupador where lower(btrim(nome)) = lower('Clínica Internacional Diamante') and arquivado_em is null) then
    raise exception '20261008z02: agrupador já existe';
  end if;
  if exists (select 1 from crm.funil where projeto = 'clinica-miami-2026-12' and ativo) then
    raise exception '20261008z02: já há funil ativo do projeto clinica-miami-2026-12';
  end if;
  if not (crm.vendedor_ativo('bd5361bc-3c3f-4f85-8b5a-f21433d040e3') and crm.vendedor_ativo('9d347183-5395-434e-9e96-2a65dde1a3cd')) then
    raise exception '20261008z02: Jonathan ou Marcos não passa em crm.vendedor_ativo';
  end if;
  if (select id from public.perfis where email = 'arthur@advmais.com') is distinct from '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid
     or (select id from public.perfis where email = 'jonathan@advmais.com') is distinct from 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3'::uuid
     or (select id from public.perfis where email = 'marcospaulo@advmais.com') is distinct from '9d347183-5395-434e-9e96-2a65dde1a3cd'::uuid then
    raise exception '20261008z02: ids de perfis não batem com os e-mails';
  end if;
end $g$;

select set_config('request.jwt.claims',
  '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated","email":"arthur@advmais.com"}', true);
set local role authenticated;

do $d$
declare r jsonb; v_ag uuid; v_fa uuid; v_fb uuid;
        v_dist jsonb := '[{"vendedorId":"bd5361bc-3c3f-4f85-8b5a-f21433d040e3","percentual":50},
                          {"vendedorId":"9d347183-5395-434e-9e96-2a65dde1a3cd","percentual":50}]';
begin
  r := public.crm_criar_agrupador('Clínica Internacional Diamante', 'clinica_miami');
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'agrupador: %', r; end if;
  v_ag := (r -> 'dados' ->> 'agrupadorId')::uuid;
  if v_ag is null then v_ag := (r ->> 'agrupadorId')::uuid; end if;

  r := public.crm_salvar_funil(jsonb_build_object(
    'nome', 'Venda ativa · Clínica Miami', 'icone', 'gem', 'projeto', 'clinica-miami-2026-12', 'agrupadorId', v_ag,
    'produto', 'clinica_miami', 'tipo', 'manual', 'eventosHotmart', '[]'::jsonb, 'distribuicao', v_dist,
    'etapas', '[
      {"nome":"Fazer primeiro contato","papel":"primeiro_contato","cor":"red","slaAtencaoMin":5,"slaCriticoMin":15,"criterio":"O lead respondeu"},
      {"nome":"Qualificar","papel":"qualificar","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Tags de Miami preenchidas: passaporte, visto, passagem, plano de viagem e turma"},
      {"nome":"Apresentar a oferta","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":2880,"slaCriticoMin":4320,"criterio":"Oferta apresentada e o lead pediu condição ou link"},
      {"nome":"Negociar","papel":"negociar","cor":"accent","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Lead escolheu a forma de pagamento"},
      {"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"camposObrigatorios":["forma_pagamento"],"criterio":"Pagamento aprovado na Hotmart"},
      {"nome":"Fechado","papel":"fechado","cor":"green","criterio":"Ganho só com pagamento aprovado"}]'::jsonb));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'funil a: %', r; end if;
  v_fa := coalesce(r -> 'dados' ->> 'funilId', r ->> 'funilId')::uuid;

  r := public.crm_salvar_funil(jsonb_build_object(
    'nome', 'Checkout e recuperação · Clínica Miami', 'icone', 'zap', 'projeto', 'clinica-miami-2026-12', 'agrupadorId', v_ag,
    'produto', 'clinica_miami', 'tipo', 'hotmart',
    'eventosHotmart', '["carrinho_abandonado","cartao_recusado","compra_em_aberto","expirada","compra_aprovada"]'::jsonb,
    'distribuicao', v_dist,
    'etapas', '[
      {"nome":"Ligar em até 15 min","papel":"primeiro_contato","cor":"red","slaAtencaoMin":10,"slaCriticoMin":15,"criterio":"Atendeu ou respondeu"},
      {"nome":"Em conversa","papel":"qualificar","cor":"cyan","slaAtencaoMin":240,"slaCriticoMin":1440,"criterio":"Entendeu o que travou"},
      {"nome":"Link novo enviado","papel":"negociar","cor":"accent","slaAtencaoMin":720,"slaCriticoMin":2880,"criterio":"Escolheu a forma de pagamento"},
      {"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"camposObrigatorios":["forma_pagamento"],"criterio":"Pagamento aprovado"},
      {"nome":"Recuperado","papel":"fechado","cor":"green","criterio":""}]'::jsonb));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'funil b: %', r; end if;
  v_fb := coalesce(r -> 'dados' ->> 'funilId', r ->> 'funilId')::uuid;

  r := public.crm_vincular_oferta(jsonb_build_object('ofertaCodigo', 'sju5pawn', 'produtoKey', 'clinica_miami', 'agrupadorId', v_ag,
                                                     'nomeComercial', 'Clínica Internacional Diamante · pré-venda (R$ 5.014,20)'));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'oferta: %', r; end if;

  perform set_config('miami.ag', v_ag::text, true);
  perform set_config('miami.fa', v_fa::text, true);
  perform set_config('miami.fb', v_fb::text, true);
end $d$;

reset role;

-- a soma da distribuição (constraint trigger DEFERRED) é conferida agora, não só no commit
set constraints all immediate;

do $c$
declare v_fa uuid := current_setting('miami.fa')::uuid; v_fb uuid := current_setting('miami.fb')::uuid; v_ag uuid := current_setting('miami.ag')::uuid;
begin
  if v_fa is null or v_fb is null or v_ag is null then raise exception 'ids não capturados'; end if;
  if (select count(*) from crm.etapa_funil where funil_id = v_fa and arquivada_em is null) <> 6 then raise exception 'funil a sem 6 etapas'; end if;
  if (select count(*) from crm.etapa_funil where funil_id = v_fb and arquivada_em is null) <> 5 then raise exception 'funil b sem 5 etapas'; end if;
  if (select count(*) from crm.distribuicao where funil_id in (v_fa, v_fb) and ativo and percentual = 50) <> 4 then
    raise exception 'distribuição própria incompleta';
  end if;
  if not exists (select 1 from crm.funil where id in (v_fa, v_fb) and distribuicao_propria and criado_por = '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'
                 having count(*) = 2) then
    raise exception 'funis sem distribuição própria ou sem autor';
  end if;
  if not exists (select 1 from crm.oferta_linha where oferta_codigo = 'sju5pawn' and linha = 'clinica_miami' and agrupador_id = v_ag and ativo) then
    raise exception 'vínculo sju5pawn não gravado';
  end if;
  raise notice '20261008z02: agrupador % · funil a % · funil b %', v_ag, v_fa, v_fb;
end $c$;

-- ─── simulação de eventos (nada sai: tudo é desfeito no fim) ───────────────────────────────────────────────────────
do $s$
declare fb uuid := current_setting('miami.fb')::uuid; fa uuid := current_setting('miami.fa')::uuid;
        v_ht uuid := '0f7ec2d7-5053-42be-849f-f0d0c22efe09';
        J uuid := 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3'; M uuid := '9d347183-5395-434e-9e96-2a65dde1a3cd';
        v_ms text := ((extract(epoch from now()) * 1000)::bigint)::text; r text; raw jsonb; v_neg uuid; n crm.negocio%rowtype;
        res jsonb := '{}';
begin
  -- 0. normalização: carrinho com a oferta em data.offer.code
  raw := jsonb_build_object('id', 'ensaio-z01-a', 'evento', 'PURCHASE_OUT_OF_SHOPPING_CART', 'payload', jsonb_build_object(
           'id', 'ensaio-z01-a', 'creation_date', v_ms, 'data', jsonb_build_object(
             'buyer', jsonb_build_object('email', 'ensaio.z01.a@example.com', 'name', 'Ensaio Miami A'),
             'offer', jsonb_build_object('code', 'sju5pawn'), 'product', jsonb_build_object('id', 5682989, 'name', 'Clínica'))));
  r := crm.hotmart_norm_evento(raw) ->> 'oferta_codigo';
  if r is distinct from 'sju5pawn' then raise exception 'S0 norm: %', r; end if;
  res := res || jsonb_build_object('s0_norm_oferta', r);

  -- 1. carrinho abandonado sju5pawn → negócio no funil b, dono Jonathan ou Marcos
  r := crm.hotmart_entrada(crm.hotmart_norm_evento(raw));
  select h.negocio_id into v_neg from crm.hotmart_processado h where h.chave = 'ev:ensaio-z01-a';
  select * into n from crm.negocio x where x.id = v_neg;
  if r <> 'negocio_criado: 1' or n.funil_id is distinct from fb or n.linha <> 'clinica_miami' or n.dono_id not in (J, M)
     or n.oferta_codigo is distinct from 'sju5pawn' then
    raise exception 'S1: % funil % linha % dono %', r, n.funil_id, n.linha, n.dono_id;
  end if;
  res := res || jsonb_build_object('s1_carrinho_sju5pawn', r, 's1_dono', crm.nome_perfil(n.dono_id), 's1_valor', n.valor);

  -- 2. carrinho de outra oferta do 5682989 (Clínica RS) → nada no comercial
  raw := jsonb_set(jsonb_set(jsonb_set(raw, '{payload,id}', '"ensaio-z01-b"'), '{payload,data,offer,code}', '"glgqcro3"'),
                   '{payload,data,buyer,email}', '"ensaio.z01.b@example.com"');
  r := crm.hotmart_entrada(crm.hotmart_norm_evento(raw));
  if r <> 'jornada: produto fora do comercial'
     or exists (select 1 from crm.negocio x join crm.hotmart_processado h on h.pessoa_id = x.pessoa_id where h.chave = 'ev:ensaio-z01-b') then
    raise exception 'S2: %', r;
  end if;
  res := res || jsonb_build_object('s2_carrinho_clinica_nacional', r);

  -- 3. compra aprovada sju5pawn da pessoa A → fecha o negócio de Miami como ganho
  r := crm.hotmart_entrada(jsonb_build_object('fonte', 'sync', 'ref', 'ensaio', 'classe', 'aprovada', 'conta', 'academy',
         'transacao', 'HPENSAIOZ01A', 'chave', 'tx:academy:HPENSAIOZ01A:aprovada', 'email', 'ensaio.z01.a@example.com',
         'produto_id', '5682989', 'oferta_codigo', 'sju5pawn', 'valor', 5014.20, 'quando', now()));
  select * into n from crm.negocio x where x.id = v_neg;
  if r <> 'ganho' or n.status <> 'ganho' or n.transacao_ganho <> 'HPENSAIOZ01A'
     or (select e.papel from crm.etapa_funil e where e.id = n.etapa_id) <> 'fechado' then
    raise exception 'S3: % status %', r, n.status;
  end if;
  res := res || jsonb_build_object('s3_aprovada_sju5pawn', r, 's3_etapa', (select e.nome from crm.etapa_funil e where e.id = n.etapa_id));

  -- 4. compra aprovada da Clínica nacional (pessoa B) → fora do comercial
  r := crm.hotmart_entrada(jsonb_build_object('fonte', 'sync', 'ref', 'ensaio', 'classe', 'aprovada', 'conta', 'academy',
         'transacao', 'HPENSAIOZ01B', 'chave', 'tx:academy:HPENSAIOZ01B:aprovada', 'email', 'ensaio.z01.b@example.com',
         'produto_id', '5682989', 'oferta_codigo', 'glgqcro3', 'valor', 1900, 'quando', now()));
  if r <> 'jornada: produto fora do comercial' then raise exception 'S4: %', r; end if;
  res := res || jsonb_build_object('s4_aprovada_clinica_nacional', r);

  -- 5. pessoa C compra sju5pawn sem negócio → não cria ganho; carrinho sju5pawn depois → "já comprou a linha"
  r := crm.hotmart_entrada(jsonb_build_object('fonte', 'sync', 'ref', 'ensaio', 'classe', 'aprovada', 'conta', 'academy',
         'transacao', 'HPENSAIOZ01C', 'chave', 'tx:academy:HPENSAIOZ01C:aprovada', 'email', 'ensaio.z01.c@example.com',
         'produto_id', '5682989', 'oferta_codigo', 'sju5pawn', 'valor', 5014.20, 'quando', now()));
  if r <> 'jornada: compra sem negócio aberto (não cria ganho)' then raise exception 'S5a: %', r; end if;
  raw := jsonb_set(jsonb_set(raw, '{payload,id}', '"ensaio-z01-c"'), '{payload,data,buyer,email}', '"ensaio.z01.c@example.com"');
  raw := jsonb_set(raw, '{payload,data,offer,code}', '"sju5pawn"');
  r := crm.hotmart_entrada(crm.hotmart_norm_evento(raw));
  if r <> 'jornada: já comprou a linha em 30 dias' then raise exception 'S5b: %', r; end if;
  res := res || jsonb_build_object('s5_carrinho_depois_de_comprar_miami', r);

  -- 6. a mesma pessoa C abandona carrinho de HT → vai ao funil HT (compra de Miami não conta como HT)
  raw := jsonb_set(jsonb_set(jsonb_set(raw, '{payload,id}', '"ensaio-z01-d"'), '{payload,data,offer,code}', '"pwhpom5m"'),
                   '{payload,data,product,id}', '7273256');
  r := crm.hotmart_entrada(crm.hotmart_norm_evento(raw));
  select * into n from crm.negocio x where x.id = (select h.negocio_id from crm.hotmart_processado h where h.chave = 'ev:ensaio-z01-d');
  if r <> 'negocio_criado: 1' or n.funil_id is distinct from v_ht or n.linha <> 'ht' then raise exception 'S6: % %', r, n.funil_id; end if;
  res := res || jsonb_build_object('s6_carrinho_ht', r, 's6_dono', crm.nome_perfil(n.dono_id), 's6_oferta', n.oferta_codigo);

  -- 7. HT no formato antigo (sem oferta em lugar nenhum), pessoa E → funil HT como antes
  raw := jsonb_build_object('id', 'ensaio-z01-e', 'evento', 'PURCHASE_OUT_OF_SHOPPING_CART', 'payload', jsonb_build_object(
           'id', 'ensaio-z01-e', 'creation_date', v_ms, 'data', jsonb_build_object(
             'buyer', jsonb_build_object('email', 'ensaio.z01.e@example.com', 'name', 'Ensaio HT'),
             'product', jsonb_build_object('id', 7273256, 'name', 'HT'))));
  r := crm.hotmart_entrada(crm.hotmart_norm_evento(raw));
  select * into n from crm.negocio x where x.id = (select h.negocio_id from crm.hotmart_processado h where h.chave = 'ev:ensaio-z01-e');
  if r <> 'negocio_criado: 1' or n.funil_id is distinct from v_ht or n.oferta_codigo is not null then raise exception 'S7: %', r; end if;
  res := res || jsonb_build_object('s7_carrinho_ht_sem_oferta', r, 's7_valor', n.valor);

  -- 8. funil a (manual) não recebe nada da Hotmart
  if exists (select 1 from crm.negocio x where x.funil_id = fa) then raise exception 'S8: funil manual recebeu negócio'; end if;

  -- 9. RPC nova recusa quem não é gestor (anônimo sem JWT cai em guarda_escrita/eh_gestor)
  res := res || jsonb_build_object('ids', jsonb_build_object('linha', 'clinica_miami', 'agrupador', current_setting('miami.ag'), 'funil_a', fa, 'funil_b', fb));
  raise exception 'ENSAIO_OK %', res;
end $s$;

rollback;
