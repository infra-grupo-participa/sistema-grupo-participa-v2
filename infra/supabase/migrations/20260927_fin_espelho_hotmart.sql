-- 20260927 — Espelho da Hotmart (schema fin): a fonte oficial do dinheiro do HM.
--
-- Pedido do João (27/09/2026): organizar o financeiro do Holding Masters por
-- completo — bruto e líquido de verdade, histórico de cada pessoa (inclusive o que
-- ela TENTOU comprar), quem deve, quem está pagando, quem cancelou/reembolsou.
--
-- 🔑 CAMADA NOVA, AO LADO. Nada aqui altera public.compras, cs.contatos_hm,
-- cs.hm_pagamentos nem qualquer valor que o board já mostra ("não quero que afete o
-- valor atual"). O espelho é preenchido pela Edge Function `hotmart-sync` lendo a API
-- oficial (só GET). O webhook continua sendo o caminho em tempo real; o espelho é a
-- conferência e a fonte do líquido (o webhook parou de trazer o líquido em ~18/08).
--
-- Acesso: schema fora do PostgREST; sem grant a anon/authenticated. Leitura para a
-- tela vem por RPC SECURITY DEFINER com guarda de financeiro (outra migração).

create schema if not exists fin;
revoke all on schema fin from public, anon, authenticated;

-- Uma linha por transação da Hotmart (a recorrência/parcela de assinatura é outra transação).
create table if not exists fin.hotmart_transacoes (
  transacao            text primary key,
  produto_id           text not null,
  produto_nome         text,
  oferta_codigo        text,
  oferta_modo          text,            -- UNIQUE_PAYMENT, SUBSCRIPTION, SMART_INSTALLMENT…
  status               text not null,   -- APPROVED, COMPLETE, CANCELLED, PRINTED_BILLET, REFUNDED, CHARGEBACK, OVERDUE, EXPIRED…
  eh_assinatura        boolean,
  recorrencia          integer,
  metodo               text,            -- CREDIT_CARD_VISA, PIX, BILLET…
  tipo_pagamento       text,            -- CREDIT_CARD, PIX, BILLET…
  parcelas             integer,
  moeda                text,
  valor_cobrado        numeric(12,2),   -- o que o CLIENTE pagou (inclui juros do parcelamento)
  valor_base           numeric(12,2),   -- preço da oferta (price/details.base)
  juros_parcelamento   numeric(12,2),   -- price/details.fee (pago pelo cliente)
  taxa_hotmart         numeric(12,2),   -- purchase.hotmart_fee.total
  liquido_produtor     numeric(12,2),   -- commissions: source = PRODUCER
  comissoes            jsonb,           -- todas as comissões (coprodutor, afiliado…)
  pedido_em            timestamptz,
  aprovado_em          timestamptz,
  garantia_ate         timestamptz,
  origem_sck           text,
  comprador_email      text,
  comprador_nome       text,
  comprador_ucode      text,
  bruto_json           jsonb not null,  -- item cru de sales/history (auditoria)
  detalhes_em          timestamptz,     -- quando preço/comissão foram trazidos
  primeiro_visto_em    timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
-- Casa com a view (email = lower(trim(comprador_email))).
create index if not exists hotmart_transacoes_email_idx   on fin.hotmart_transacoes (lower(trim(comprador_email)));
create index if not exists hotmart_transacoes_produto_idx on fin.hotmart_transacoes (produto_id, aprovado_em);
create index if not exists hotmart_transacoes_status_idx  on fin.hotmart_transacoes (status);
create index if not exists hotmart_transacoes_pedido_idx  on fin.hotmart_transacoes (pedido_em);

-- Fila de janelas a sincronizar (backfill e rotina de hora em hora usam a mesma fila).
create table if not exists fin.hotmart_sync_fila (
  id          bigserial primary key,
  produto_id  text not null,
  inicio      date not null,
  fim         date not null,
  tipo        text not null default 'backfill' check (tipo in ('backfill','rotina')),
  status      text not null default 'pendente' check (status in ('pendente','processando','feito','erro')),
  tentativas  int  not null default 0,
  itens       int,
  erro        text,
  criado_em   timestamptz not null default now(),
  feito_em    timestamptz,
  iniciado_em timestamptz,         -- janela presa em 'processando' há 5+ min volta para a fila
  check (fim >= inicio and fim - inicio <= 300)
);
create unique index if not exists hotmart_sync_fila_uk on fin.hotmart_sync_fila (produto_id, inicio, fim, tipo) where status <> 'feito';

-- Produtos acompanhados e a família a que pertencem (o que é "HM").
create table if not exists fin.produtos (
  produto_id  text primary key,
  nome        text not null,
  familia     text not null,        -- HM, AURUM, ACELERA, HT, OUTRO
  papel       text,                 -- principal, renovacao, complemento, legado
  sincroniza  boolean not null default true,
  nota        text
);
insert into fin.produtos (produto_id, nome, familia, papel, nota) values
 ('5064314','Holding Masters','HM','principal','Produto atual do HM (sinal, saldo, cheio 15k).'),
 ('3507214','Holding - Holding Masters','HM','renovacao','Renovação real do HM (anual/recorrência).'),
 ('4704945','Holding Masters Complemento','HM','complemento',null),
 ('1560882','Holding Masters - Acesso Extra','HM','legado','Pausado.'),
 ('6303351','Holding Masters - Nível 1','HM','legado','Pausado.'),
 ('5504569','Holding Masters - Plano Starter','HM','legado','Pausado.'),
 ('2803705','Treinamento Holding Masters 2023','HM','legado','Pausado.')
on conflict (produto_id) do nothing;

revoke all on all tables in schema fin from public, anon, authenticated;
revoke all on all sequences in schema fin from public, anon, authenticated;

-- A Edge Function roda com service_role; ela lê as credenciais do Vault por esta função.
create or replace function fin.hotmart_credenciais()
returns table (basic text, chave_sync text)
language sql security definer set search_path = ''
as $$
  select (select decrypted_secret from vault.decrypted_secrets where name = 'hotmart_hm_basic'),
         (select decrypted_secret from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave');
$$;
revoke all on function fin.hotmart_credenciais() from public, anon, authenticated;
grant usage on schema fin to service_role;
grant execute on function fin.hotmart_credenciais() to service_role;
grant select, insert, update on fin.hotmart_transacoes, fin.hotmart_sync_fila to service_role;
grant select on fin.produtos to service_role;
grant usage on sequence fin.hotmart_sync_fila_id_seq to service_role;
