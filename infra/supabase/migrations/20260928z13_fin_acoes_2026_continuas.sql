-- 20260928z13 — janelas de captação do HM em 2026 sem buraco: cada ação vale até o início da seguinte
-- (3 cards compraram entre dois eventos — 30/06, 05/07, 21/07 — e caíam em "fora de evento").
update fin.acoes a set fim = x.prox
  from (select id, lead(inicio) over (order by inicio, prioridade) prox
          from fin.acoes where produto = 'HM' and prioridade <> 50 and inicio is not null and fim is not null) x
 where a.id = x.id and x.prox is not null and x.prox > a.inicio and a.fim < x.prox;
