-- 20261008210425 (escrita como 20261008z01): Comercial, linha "Clínica Internacional Diamante" (Miami) + roteamento da Hotmart por OFERTA ("opção A").
--
-- STATUS: APLICADA em produção em 08/10/2026, versão 20261008210425 (nome crm_oferta_linha_clinica_miami, era 20261008z01)
--   via apply_migration. SQL aplicado = este arquivo com o cabeçalho de comentários encurtado (corpo idêntico);
--   md5(array_to_string(statements, ';')) gravado = 5726c0832dc6f5b898961dfa016e4950. md5 vivo depois:
--   crm.hotmart_processar e2d10ce361948047c941c70b22bc3560, crm.hotmart_norm_evento 185dce8d10df8f258e92a17abb6f0d2c.
--   Relatório: 20261008210425.explain.md.
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
