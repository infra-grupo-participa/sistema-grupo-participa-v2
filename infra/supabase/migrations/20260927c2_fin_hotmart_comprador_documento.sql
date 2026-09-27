-- 20260927c2 — Dados do comprador no espelho (sales/users, papel BUYER), lidos status a status
-- pela Edge Function hotmart-sync v4. Base do grafo de identidade (20260927d).
alter table fin.hotmart_transacoes
  add column if not exists comprador_documento text,        -- só dígitos (CPF ou CNPJ), de sales/users (role BUYER)
  add column if not exists comprador_documento_tipo text,
  add column if not exists comprador_telefone text,         -- só dígitos
  add column if not exists comprador_cidade text,
  add column if not exists comprador_uf text,
  add column if not exists participantes jsonb;             -- papéis da venda (BUYER, PRODUCER, AFFILIATE, COPRODUCER…) sem dado pessoal de terceiros
-- (índice hotmart_transacoes_doc_idx criado e removido em 27/09: 0 idx_scan medido — o grafo junta por 'd:'||documento.)
