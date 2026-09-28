-- 20260928z35 — Índice por documento (só dígitos) no espelho da Hotmart.
-- fin.nome_da_pessoa (z33) procura as compras da mesma pessoa pelo CPF; sem índice, o board foi de 0,35 s para 3,7 s.
-- Com o índice: 0,95 s (medido 28/09/2026).
create index if not exists hotmart_transacoes_documento_idx
  on fin.hotmart_transacoes ((regexp_replace(coalesce(comprador_documento, ''), '\D', '', 'g')));
