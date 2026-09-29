-- 20260929z86 — Índice em fin.hotmart_transacoes(oferta_codigo)
--
-- Por quê: a z85 fez fn_fin_funil_compradores ler as vendas das ofertas ligadas ao evento (fin.evento_ofertas)
-- e o resolvedor busca transações por oferta; sem índice era Seq Scan de 57.276 linhas (108 MB) por clique.
-- APLICADO FORA DE TRANSAÇÃO em 29/09 pelo orquestrador (create index concurrently não roda dentro de migration);
-- este arquivo registra o objeto para o repo. Medido (explain analyze, colado em 20260929z85.explain.md):
--   fn_fin_funil_compradores(96 — 2º Encontro)  2.603,660 ms -> 27,049 ms
--   fn_fin_funil_compradores(89 — HT32)         1.762,509 ms -> 1.041,164 ms
--   fin.resolver_ofertas_eventos(false)           619,387 ms -> 148,890 ms
-- Custo de escrita: 1 índice btree a mais no sync da Hotmart (upsert por transação), desprezível no volume atual.
-- Reversão: drop index concurrently if exists fin.hotmart_transacoes_oferta_idx;

create index concurrently if not exists hotmart_transacoes_oferta_idx on fin.hotmart_transacoes (oferta_codigo);
