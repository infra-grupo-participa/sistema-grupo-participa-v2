-- 20260928z3 — Serviço Diamante: produtos separados por serviço (set/2026) entram no board (28/09/2026).
-- A Hotmart ganhou um produto por serviço (Copywriter, Design, Edição, Redes Sociais, Tráfego, Automações,
-- Webdesign, Combo — 7086369…7086783). Até aqui ficavam A_CLASSIFICAR: a 1ª venda (Tráfego, 17/09, R$ 1.500/mês)
-- não aparecia na cobrança. Serviço sai do PRODUTO quando a oferta ainda não está em fin.diamante_ofertas.
-- Fora: 3094430 "Diamante" (programa/mentoria, R$ 1,78 mi — não é serviço), 1667105 "Diamante 2024",
-- 3400997/6489980 (Encontro Internacional — evento).
create table if not exists fin.diamante_produtos (
  produto_id text primary key references fin.produtos(produto_id),
  servico text not null,
  geracao text not null default '2026'
);
alter table fin.diamante_produtos enable row level security;
revoke all on fin.diamante_produtos from public, anon, authenticated;

alter table fin.diamante_ofertas drop constraint if exists diamante_ofertas_geracao_check;
alter table fin.diamante_ofertas add constraint diamante_ofertas_geracao_check
  check (geracao in ('legado','2025','2026','regularizacao','pacote','acordo'));

insert into fin.diamante_produtos (produto_id, servico) values
  ('7086369', 'copy'), ('7086430', 'design_grafico'), ('7086499', 'video'), ('7086549', 'social_media'),
  ('7086595', 'trafego'), ('7086636', 'automacao'), ('7086675', 'web_design'), ('7086783', 'pacote')
on conflict (produto_id) do update set servico = excluded.servico;

insert into fin.diamante_ofertas (oferta_codigo, servico, geracao, mensalidade, nome_hotmart)
values ('womggo65', 'trafego', '2026', 1500, 'Gestão de Tráfego Pago Diamante (produto 7086595)')
on conflict (oferta_codigo) do nothing;

update fin.produtos set familia = 'DIAMANTE', papel = 'servico', sincroniza = true
 where produto_id in (select produto_id from fin.diamante_produtos);

-- board: serviço pela oferta, senão pelo produto
do $do$
declare v text;
begin
  v := pg_get_functiondef('public.fn_fin_diamante_servicos()'::regprocedure);
  if position('diamante_produtos' in v) > 0 then return; end if;
  v := replace(v, $a$coalesce(o.servico, 'desconhecida') serv, o.geracao, (o.oferta_codigo is null) descon$a$,
                  $b$coalesce(o.servico, dp.servico, 'desconhecida') serv, coalesce(o.geracao, dp.geracao) geracao,
           (o.oferta_codigo is null and dp.produto_id is null) descon$b$);
  v := replace(v, $a$left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo$a$,
                  $b$left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo
      left join fin.diamante_produtos dp on dp.produto_id = t.produto_id$b$);
  if position('dp.servico' in v) = 0 or position('fin.diamante_produtos dp' in v) = 0 then raise exception 'troca falhou'; end if;
  execute v;
end $do$;
