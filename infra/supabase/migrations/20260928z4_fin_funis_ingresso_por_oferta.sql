-- 20260928z4 — Funis: ingresso amarrado à OFERTA quando o mesmo produto vende eventos sobrepostos (28/09/2026).
-- O produto 5682989 "Clínica de Holding Familiar" vende todas as clínicas; cada clínica tem oferta própria e a
-- pré-venda de uma corre durante a outra. Por data, a "Clínica SP mar/2026" levava 48 ingressos que eram de
-- Goiânia, e Goiânia ficava com 18. Medido: oferta 3dg69mg2 = 66 pagos (09/03–18/04/2026) = planilha de Goiânia (66);
-- glgqcro3 = 88 pagos (29/04–08/06) = planilha de POA (88). Oferta presente aqui só conta no evento dela, sem janela.
create table if not exists fin.evento_ofertas (
  evento_id bigint not null references fin.eventos(id),
  oferta_codigo text not null,
  observacao text,
  primary key (evento_id, oferta_codigo)
);
create unique index if not exists evento_ofertas_oferta_uq on fin.evento_ofertas (oferta_codigo);
alter table fin.evento_ofertas enable row level security;
revoke all on fin.evento_ofertas from public, anon, authenticated;

insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao)
select e.id, o.oferta, o.obs
  from (values
    ('clinica', date '2025-07-14', '8sxu5pkw', 'Rio jul/2025 — R$ 3.000'),
    ('clinica', date '2025-07-14', '4ta6bv36', 'Rio jul/2025 — R$ 2.500'),
    ('clinica', date '2025-07-14', 'q2wdgg7m', 'Rio jul/2025 — R$ 2.500'),
    ('clinica', date '2025-07-14', 'q7zdn712', 'Rio jul/2025 — R$ 500'),
    ('clinica', date '2025-07-14', 'm4yuvi0a', 'Rio jul/2025 — R$ 2.500'),
    ('clinica', date '2025-07-14', 'tn2jua0u', 'Rio jul/2025 — R$ 2.500'),
    ('clinica', date '2026-04-19', '3dg69mg2', 'Goiânia — 66 pagos = planilha'),
    ('clinica', date '2026-06-09', 'glgqcro3', 'Porto Alegre — 88 pagos = planilha')
  ) o(categoria, inicio, oferta, obs)
  join fin.eventos e on e.categoria = o.categoria and e.inicio = o.inicio
on conflict do nothing;

update fin.eventos set observacao = 'Nenhum ingresso identificado no espelho: a oferta vendida em 09–14/03/2026 (3dg69mg2) é a pré-venda da Clínica Goiânia'
 where categoria = 'clinica' and inicio = '2026-03-09';

do $do$
declare v text;
begin
  -- resultado por evento
  v := pg_get_functiondef('public.fn_fin_funis()'::regprocedure);
  if position('evento_ofertas' in v) = 0 then
    v := replace(v, 'select t.transacao, t.produto_id, t.email,', 'select t.transacao, t.produto_id, t.oferta_codigo, t.email,');
    v := replace(v, $a$or (p.papel = 'ingresso' and x.dia between e.ing_de and e.venda_ate))$a$,
      $b$or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
                                            and x.dia between e.ing_de and e.venda_ate))))$b$);
    if position('evento_ofertas' in v) = 0 or position('t.oferta_codigo, t.email' in v) = 0 then raise exception 'fn_fin_funis: troca falhou'; end if;
    execute v;
  end if;
  -- quem pagou
  v := pg_get_functiondef('public.fn_fin_funil_compradores(bigint)'::regprocedure);
  if position('evento_ofertas' in v) = 0 then
    v := replace(v, $a$or (p.papel = 'ingresso' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))$a$,
      $b$or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))))$b$);
    if position('evento_ofertas' in v) = 0 then raise exception 'fn_fin_funil_compradores: troca falhou'; end if;
    execute v;
  end if;
end $do$;
