-- Dados de pagamento das compras da fila de Acesso HM, para exportação em CSV.
-- compras tem RLS restrito a is_ht_operator(); a fila (fn_hm_fila) já é SECURITY DEFINER
-- e não carrega esses campos para não pesar a listagem. Esta função é chamada só na exportação.

create or replace function public.fn_hm_pagamentos(p_compra_ids uuid[])
returns table (
  compra_id uuid,
  hotmart_transaction text,
  produto_nome text,
  oferta_codigo text,
  moeda text,
  preco numeric,
  preco_original numeric,
  desconto numeric,
  cupom text,
  metodo_pagamento text,
  parcelas smallint,
  status text,
  is_assinatura boolean,
  numero_recorrencia smallint,
  data_compra timestamptz,
  data_aprovacao timestamptz
)
language sql
security definer
set search_path to 'public'
as $$
  -- casts explícitos: as colunas são varchar e o retorno é text
  select c.id, c.hotmart_transaction::text, c.produto_nome::text, c.oferta_codigo::text, c.moeda::text,
         c.preco, c.preco_original, c.desconto, c.cupom::text, c.metodo_pagamento::text,
         c.parcelas, c.status::text, c.is_assinatura, c.numero_recorrencia,
         c.data_compra, c.data_aprovacao
  from compras c
  where c.id = any(p_compra_ids);
$$;

revoke all on function public.fn_hm_pagamentos(uuid[]) from public;
grant execute on function public.fn_hm_pagamentos(uuid[]) to authenticated;
