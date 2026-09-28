-- 20260928z47 — Renovação de acesso (6qxsk9kq, R$ 2.497) é pacote fechado: quem pagou está quitado (polimento, rodada 4).
-- O próprio catálogo manda: "produto de ACESSO/downsell (NÃO é o programa R$15k). Comprador é quitado nesse valor, não
-- deve saldo. Cravar valor_total=2497 no card." Foi feito à mão em 1 card e esquecido em 2,
-- que apareciam sem pacote e "sem acordo".
-- 1) Crava nos 2 cards (só onde valor_total é nulo e o único dinheiro do HM é a renovação) e recalcula.
-- 2) Classe: o ramo 6qxsk9kq de cs.fn_seed_contato_hm passa a cravar o valor pago quando CRIA o card. Card que já
--    existia (pessoa já no Programa) não é tocado.
-- Descartados: regra genérica "papel renovacao = quitado" (o sinal de R$ 2.000 dos ex-alunos também tem papel
-- 'renovacao' — 5 cards ficariam quitados por engano) e pacote_cheio na oferta (o card de quem renovou e depois comprou o
-- Programa, ganharia um alerta falso de "pacote travado diverge da regra").
do $do$
declare r record;
begin
  for r in
    select ch.id, ch.comprador_id, sum(p.valor) pago
      from cs.contatos_hm ch
      join cs.hm_pagamentos p on p.comprador_id = ch.comprador_id and cs.fn_hm_pagamento_do_produto(p.oferta_codigo, 'HM')
     where coalesce(ch.produto, 'HM') = 'HM' and ch.valor_total is null
     group by ch.id, ch.comprador_id
    having bool_and(p.oferta_codigo = '6qxsk9kq')
  loop
    update cs.contatos_hm set valor_total = r.pago where id = r.id;
    insert into cs.interacoes (contato_hm_id, tipo, descricao, autor)
    values (r.id, 'sistema', 'Pacote cravado em R$ ' || trim(to_char(r.pago, '999G990D00'))
            || ': renovação de acesso (6qxsk9kq) é pacote fechado — regra do catálogo (financeiro, z47)', 'financeiro');
    perform cs.fn_hm_recalcular_financeiro(r.comprador_id);
  end loop;
end $do$;

do $do$
declare d text;
  a1 text := E'    insert into cs.contatos_hm (comprador_id, produto, estagio_id, turma, plano, categoria_entrada, apto_ativacao)\n    values (v_comprador, v_produto, v_pend, v_turma, coalesce(v_notes,''Acesso ETHB''), v_cat, true)\n    on conflict (comprador_id, produto) do update\n      set apto_ativacao = true, atualizado_em = now();';
begin
  d := pg_get_functiondef('cs.fn_seed_contato_hm()'::regprocedure);
  if position('renovacao_cravada' in d) = 0 then
    if position(a1 in d) = 0 then raise exception 'z47: ramo 6qxsk9kq não encontrado'; end if;
    d := replace(d, a1,
      E'    -- renovacao_cravada (z47): renovação de acesso é pacote fechado — crava o valor pago\n'
      || E'    insert into cs.contatos_hm (comprador_id, produto, estagio_id, turma, plano, categoria_entrada, apto_ativacao, valor_total)\n'
      || E'    values (v_comprador, v_produto, v_pend, v_turma, coalesce(v_notes,''Acesso ETHB''), v_cat, true, nullif(new.preco, 0))\n'
      || E'    on conflict (comprador_id, produto) do update\n'
      || E'      set apto_ativacao = true, atualizado_em = now();');
    execute d;
  end if;
end $do$;
