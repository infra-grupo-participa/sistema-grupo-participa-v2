-- 20260928z37 — Uma pessoa, um card por produto (polimento de 28/09).
-- Medido: 2 pessoas tinham DOIS cards do mesmo produto — mesmo CPF na Hotmart, dois cadastros (e-mails diferentes).
-- Num dos casos o sinal estava num card e o saldo no outro; somados, davam o pacote inteiro (a pessoa estava quitada e
-- o board mostrava as duas metades como dívida).
-- Mesmo mecanismo da 0105 do disparos: alias gêmeo → canônico (o card com mais dinheiro lançado; empate: o mais
-- antigo), e o razão do gêmeo passa para o canônico (UPDATE de comprador_id com observação — reversível). Nada é apagado.
-- Regra (sem dado pessoal no repositório, que é público): pares de cards do MESMO produto cujos cadastros caem no
-- mesmo CPF do grafo fin.identidade.
-- Classe: o board financeiro não lista card de cadastro que tem alias para outro cadastro com card do mesmo produto
-- (fn_fin_board — ver z44/z49, que reescrevem a função com esse filtro).
with card as (
  select ch.id, ch.comprador_id, ch.produto, ch.criado_em, i.pessoa_chave,
         (select coalesce(sum(p.valor), 0) from cs.hm_pagamentos p where p.comprador_id = ch.comprador_id) pago
    from cs.contatos_hm ch
    join public.compradores c on c.id = ch.comprador_id
    join fin.identidade i on i.no = 'e:' || lower(btrim(c.email))
   where i.pessoa_chave ~ '^d:\d{11}$'
), par as (
  select k.*, row_number() over (partition by k.pessoa_chave, k.produto order by k.pago desc, k.criado_em) ordem,
         count(*) over (partition by k.pessoa_chave, k.produto) n
    from card k
)
insert into cs.hm_comprador_alias (comprador_id, canonico_id, motivo)
select g.comprador_id, c.comprador_id,
       'Mesma pessoa (mesmo CPF na Hotmart), dois cards do mesmo produto — cadastro gêmeo aponta para o card canônico '
       || '(financeiro z37, 28/09/2026).'
  from par g join par c on c.pessoa_chave = g.pessoa_chave and c.produto = g.produto and c.ordem = 1
 where g.n > 1 and g.ordem > 1 and g.comprador_id <> c.comprador_id
on conflict (comprador_id) do nothing;

update cs.hm_pagamentos p
   set comprador_id = al.canonico_id,
       obs = coalesce(p.obs || ' · ', '') || 'Movido do cadastro gêmeo ' || al.comprador_id || ' (z37)'
  from cs.hm_comprador_alias al
 where al.comprador_id = p.comprador_id
   and al.motivo like '%(financeiro z37,%';
