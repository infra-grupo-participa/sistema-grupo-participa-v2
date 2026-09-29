-- 20260929z81 — Ofertas da Hotmart (29/09/2026).
-- POR QUÊ: a venda (fin.hotmart_transacoes.oferta_codigo) só traz o código da oferta; ligar oferta -> evento sem humano
-- exige conhecer todas as ofertas (código, nome, preço) de cada produto. A Edge Function hotmart-sync, no modo
-- {"catalogo": true} (cron diário), lê GET /products/{ucode}/offers dos produtos com sincroniza = true e grava aqui.
-- Só leitura na Hotmart; nada mexe em tela nem em outra tabela.
-- ESCALA: centenas de linhas (ofertas de ~dezenas de produtos). PK por oferta_codigo; índice em produto_id p/ o join.
-- REVERSÃO: drop table fin.ofertas;  (nada depende dela; a função só passa a falhar no upsert, que é isolado por produto)
-- ACESSO: só service_role / conexão da Edge Function (postgres). Nenhum grant a anon/authenticated.
create table if not exists fin.ofertas (
  oferta_codigo text primary key,
  produto_id text not null,
  nome text,
  descricao text,
  preco numeric,
  moeda text,
  modo text,
  is_main_offer boolean,
  bruto_json jsonb,
  primeira_vez_em timestamptz not null default now(),
  visto_em timestamptz not null default now()
);
create index if not exists ofertas_produto_id_idx on fin.ofertas (produto_id);
alter table fin.ofertas enable row level security;
revoke all on fin.ofertas from public, anon, authenticated;
