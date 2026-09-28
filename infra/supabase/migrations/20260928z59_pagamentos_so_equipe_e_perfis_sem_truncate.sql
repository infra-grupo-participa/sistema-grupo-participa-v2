-- 20260928z59 — SEGURANÇA (residuais do kirad, 28/09):
--   [MÉDIO] public.fn_hm_pagamentos: sem guarda para quem está logado. O cadastro do Auth é aberto e confirma sozinho,
--           então "logado" não é "equipe". Passa a exigir public.gp_eh_equipe(). Chamador: aba "Liberação Holding
--           Masters" (web/modules/alunos/ui/acesso-hm-data.ts), usada pela equipe.
--   [BAIXO] TRUNCATE em public.perfis concedido a anon/authenticated (RLS não vale para TRUNCATE; sem porta de entrada
--           hoje — REST não expõe e pg_graphql está desligado — mas é privilégio sem uso). Revogado.
-- tem_permissao (BAIXO, mapear permissões de logados) fica como está: é lida por outras funções e pode ter chamador
-- de outro sistema; registrado como pendência.
--
-- REVERSÃO: recriar fn_hm_pagamentos sem o "(select public.gp_eh_equipe()) and"; grant truncate on public.perfis to anon, authenticated;
create or replace function public.fn_hm_pagamentos(p_compra_ids uuid[])
 returns table(compra_id uuid, hotmart_transaction text, produto_nome text, oferta_codigo text, moeda text, preco numeric,
               preco_original numeric, desconto numeric, cupom text, metodo_pagamento text, parcelas smallint, status text,
               is_assinatura boolean, numero_recorrencia smallint, data_compra timestamp with time zone,
               data_aprovacao timestamp with time zone)
 language sql security definer set search_path to 'public'
as $function$
  select c.id, c.hotmart_transaction::text, c.produto_nome::text, c.oferta_codigo::text, c.moeda::text,
         c.preco, c.preco_original, c.desconto, c.cupom::text, c.metodo_pagamento::text,
         c.parcelas, c.status::text, c.is_assinatura, c.numero_recorrencia,
         c.data_compra, c.data_aprovacao
  from compras c
  where (select public.gp_eh_equipe())  -- z59: só equipe
    and c.id = any(p_compra_ids);
$function$;
revoke all on function public.fn_hm_pagamentos(uuid[]) from public, anon;
grant execute on function public.fn_hm_pagamentos(uuid[]) to authenticated, service_role;

revoke truncate on public.perfis from anon, authenticated;
