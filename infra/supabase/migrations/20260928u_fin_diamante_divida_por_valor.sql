-- 20260928u — Serviço Diamante: a dívida conta por VALOR, não por "existe um pagamento depois" (27/09/2026).
-- Medido nos dados:
--   * 7 pagamentos AGRUPADOS (R$ 11.200 além de uma mensalidade): a Hotmart cobra vários meses numa tentativa só
--     (Osvaldo Catena, 29/12/2025, Pix de R$ 3.200 = 4 meses de Disparos). Antes, só 1 mês ficava pago e 3 viravam dívida.
--   * 5 pagamentos de ofertas "… Vencido" (R$ 4.200): antes um deles quitava TODA a dívida anterior do serviço; agora
--     cada um abate o que pagou.
--   * aikfnv0t: 3 × R$ 9.733,33 (jul–set/2026) do Vitor Negrão, logo depois que os 6 serviços dele pararam em aberto —
--     tratado como ACORDO (abate as mensalidades em aberto de todos os serviços da pessoa). A confirmar com o João.
-- Crédito abate as mensalidades em aberto da MAIS ANTIGA para a mais nova. O que foi abatido aparece como "coberto"
-- (coberto_n/coberto_valor e o mês "coberto" na grade), nunca some.
-- Situação: pagando hoje com mês antigo em aberto = devendo (a dívida aparece, não se esconde atrás do "em dia").
alter table fin.diamante_ofertas drop constraint if exists diamante_ofertas_geracao_check;
alter table fin.diamante_ofertas add constraint diamante_ofertas_geracao_check
  check (geracao in ('legado','2025','regularizacao','pacote','acordo'));
insert into fin.diamante_ofertas (oferta_codigo, servico, geracao, mensalidade, nome_hotmart)
values ('aikfnv0t', 'acordo', 'acordo', 9733.33, 'provável acordo de dívida (Vitor Negrão, 3 × R$ 9.733,33) — confirmar')
on conflict (oferta_codigo) do update set servico = excluded.servico, geracao = excluded.geracao,
  mensalidade = excluded.mensalidade, nome_hotmart = excluded.nome_hotmart;

drop function if exists public.fn_fin_diamante_servicos();
create or replace function public.fn_fin_diamante_servicos()
returns table (
  pessoa_chave text, nome text, nome_compra text, nome_empresa boolean, cliente_cadastro boolean,
  email text, emails text[], telefone text, nivel text,
  servico text, ofertas text[], desconhecida boolean,
  primeira_paga date, ultima_paga date, pagamentos int, total_pago numeric, liquido numeric, mensalidade numeric,
  devendo_n int, devendo_valor numeric, devendo_desde date, antigo_n int, antigo_valor numeric, antigo_desde date,
  coberto_n int, coberto_valor numeric, estornos int, tentativas int, ultima_tentativa date, meses jsonb, situacao text
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with base as (
    select t.*, ip.pessoa_chave grafo,
           coalesce(o.servico, 'desconhecida') serv, o.geracao, (o.oferta_codigo is null) descon
      from fin.vw_transacoes t
      join fin.produtos p on p.produto_id = t.produto_id and p.papel = 'servico'
      left join fin.identidade ip on ip.no = 'e:' || t.email
      left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo
     where t.email is not null
  ), cli_grafo as (
    -- cliente do cadastro alcançado por OUTRO e-mail da mesma pessoa no grafo — só se for um cliente só
    select i.pessoa_chave grafo, min(dc.cliente_slug) slug
      from fin.identidade i join fin.diamante_clientes dc on 'e:' || dc.email = i.no
     group by i.pessoa_chave having count(distinct dc.cliente_slug) = 1
  ), tx as (
    select coalesce('c:' || dc.cliente_slug, 'c:' || cg.slug, b.grafo, 'e:' || b.email) pessoa, b.*
      from base b
      left join fin.diamante_clientes dc on dc.email = b.email
      left join cli_grafo cg on cg.grafo = b.grafo
  ), parc as (
    -- uma linha por mensalidade (e-mail × oferta × recorrência): OVERDUE é por tentativa. valor = 1ª tentativa do mês.
    select x.pessoa, x.serv, x.geracao, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao) parcela,
           bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'pago') paga, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde,
           (array_agg(x.valor_oferta order by x.pedido_em))[1] valor
      from tx x
     group by x.pessoa, x.serv, x.geracao, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), extra as (
    -- pagamento AGRUPADO: a Hotmart cobra N meses numa tentativa (Osvaldo, 29/12/2025: R$ 3.200 = 4 × R$ 800).
    -- O que passa de uma mensalidade é crédito para os meses em aberto do mesmo serviço.
    select x.pessoa, x.serv, sum(x.valor_oferta - p.valor) valor
      from tx x
      join parc p on p.pessoa = x.pessoa and p.email = x.email and p.oferta_codigo = x.oferta_codigo
                 and p.parcela = coalesce(x.recorrencia::text, 't:' || x.transacao)
     where x.grupo = 'pago' and x.valor_oferta > 1.5 * p.valor and coalesce(x.geracao, '') not in ('regularizacao','acordo')
     group by x.pessoa, x.serv
  ), cred_serv as (
    -- crédito por serviço = excedente dos agrupados + ofertas "… Vencido" pagas (cada uma vale o que pagou, não "tudo")
    select c.pessoa, c.serv, sum(c.valor) valor from (
      select e.pessoa, e.serv, e.valor from extra e
      union all
      select x.pessoa, x.serv, x.valor_oferta from tx x where x.grupo = 'pago' and x.geracao = 'regularizacao'
    ) c group by c.pessoa, c.serv
  ), cred_acordo as (
    -- acordo (ex.: aikfnv0t do Vitor Negrão): vale para as mensalidades em aberto de TODOS os serviços da pessoa
    select x.pessoa, sum(x.valor_oferta) valor from tx x where x.grupo = 'pago' and x.geracao = 'acordo' group by x.pessoa
  ), aberta as (
    -- mensalidade que atrasou e nunca foi paga nem estornada (as tentativas de "Vencido"/acordo não são dívida nova)
    select p.*, sum(p.valor) over (partition by p.pessoa, p.serv order by p.desde, p.parcela rows unbounded preceding) acum_serv
      from parc p
     where p.atrasou and not p.quitada and coalesce(p.geracao, '') not in ('regularizacao','acordo')
  ), aberta2 as (
    select a.*, (a.acum_serv <= coalesce(cs.valor, 0) + 0.01) coberta_serv
      from aberta a left join cred_serv cs on cs.pessoa = a.pessoa and cs.serv = a.serv
  ), aberta3 as (
    select a.*, sum(case when a.coberta_serv then 0 else a.valor end)
                  over (partition by a.pessoa order by a.desde, a.serv, a.parcela rows unbounded preceding) acum_pessoa
      from aberta2 a
  ), aberta4 as (
    select a.*, (a.coberta_serv or a.acum_pessoa <= coalesce(ca.valor, 0) + 0.01) coberta
      from aberta3 a left join cred_acordo ca on ca.pessoa = a.pessoa
  ), devida as (
    select a.* from aberta4 a where not a.coberta
  ), cob as (
    select a.pessoa, a.serv, count(*)::int n, sum(a.valor) valor from aberta4 a where a.coberta group by a.pessoa, a.serv
  ), div as (
    select d.pessoa, d.serv,
           count(*) filter (where d.desde >= now() - interval '120 days')::int n,
           coalesce(sum(d.valor) filter (where d.desde >= now() - interval '120 days'), 0) valor,
           min(d.desde) filter (where d.desde >= now() - interval '120 days') desde,
           count(*) filter (where d.desde < now() - interval '120 days')::int an,
           coalesce(sum(d.valor) filter (where d.desde < now() - interval '120 days'), 0) avalor,
           min(d.desde) filter (where d.desde < now() - interval '120 days') adesde
      from devida d group by d.pessoa, d.serv
  ), mes as (
    -- grade de adimplência: mês em que a cobrança nasceu → pior estado daquele mês no serviço
    select m.pessoa, m.serv, jsonb_object_agg(m.mes, m.estado) meses
      from (select p.pessoa, p.serv, to_char(p.desde at time zone 'America/Sao_Paulo', 'YYYY-MM') mes,
                   case when bool_or(dv.parcela is not null) then 'atrasado'
                        when bool_or(p.paga) then 'pago'
                        when bool_or(cb.parcela is not null) then 'coberto'
                        when bool_or(p.quitada) then 'estornado'
                        else 'tentativa' end estado
              from parc p
              left join devida dv on dv.pessoa = p.pessoa and dv.serv = p.serv and dv.email = p.email
                                 and dv.oferta_codigo = p.oferta_codigo and dv.parcela = p.parcela
              left join aberta4 cb on cb.coberta and cb.pessoa = p.pessoa and cb.serv = p.serv and cb.email = p.email
                                 and cb.oferta_codigo = p.oferta_codigo and cb.parcela = p.parcela
             where p.desde >= now() - interval '24 months'
             group by 1, 2, 3) m
     group by m.pessoa, m.serv
  ), agg as (
    select x.pessoa, x.serv,
           array_agg(distinct x.oferta_codigo) ofertas,
           bool_or(x.descon) descon,
           min(x.dia_aprovado) filter (where x.grupo = 'pago') prim,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult,
           count(*) filter (where x.grupo = 'pago')::int pagos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) total,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           (array_agg(x.valor_oferta order by x.aprovado_em desc) filter (where x.grupo = 'pago' and coalesce(x.geracao, '') <> 'regularizacao'))[1] mens,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           count(*)::int tentativas,
           max(x.dia_pedido) ult_tent
      from tx x
     group by x.pessoa, x.serv
  ), ems as (
    -- todos os e-mails da pessoa: os das compras + os do grafo + os do cadastro Diamante
    select distinct z.pessoa, z.email from (
      select x.pessoa, x.email from tx x
      union select x.pessoa, substr(i.no, 3) from tx x join fin.identidade i on i.pessoa_chave = x.grafo and i.no like 'e:%'
      union select 'c:' || dc.cliente_slug, dc.email from fin.diamante_clientes dc
    ) z where z.pessoa in (select pessoa from tx)
  ), aluno as (
    select e.pessoa,
           (array_agg(a.nivel_resultado order by array_position(
              array['diamante_vermelho','diamante','platina','ouro','profissional','em_formacao','pessoal','iniciante'], a.nivel_resultado)
              ) filter (where a.nivel_resultado is not null))[1] nivel,
           (array_agg(a.nome order by (a.nivel_resultado is null), a.nome))[1] nome
      from ems e join public.thb_alunos a on lower(trim(a.email)) = e.email
     group by e.pessoa
  ), pes as (
    select x.pessoa,
           (array_agg(x.nome order by x.pedido_em desc))[1] nome_hotmart,
           (array_agg(x.email order by x.pedido_em desc))[1] email,
           (array_agg(h.comprador_telefone order by x.pedido_em desc) filter (where h.comprador_telefone is not null))[1] tel
      from tx x join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), cad as (
    select 'c:' || dc.cliente_slug pessoa, min(dc.nome) nome from fin.diamante_clientes dc group by dc.cliente_slug
  )
  select a.pessoa,
         fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart)),
         case when fin.nome_proprio(pe.nome_hotmart) is distinct from fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart))
              then fin.nome_proprio(pe.nome_hotmart) end,
         fin.nome_de_empresa(coalesce(cd.nome, al.nome, pe.nome_hotmart)),
         (cd.nome is not null),
         pe.email,
         (select array_agg(e.email order by e.email) from ems e where e.pessoa = a.pessoa),
         case when coalesce(public.gp_pode_ver_cpf(), false) then pe.tel
              when pe.tel is not null then '···' || right(regexp_replace(pe.tel, '\D', '', 'g'), 4) end,
         al.nivel,
         a.serv, a.ofertas, a.descon,
         a.prim, a.ult, a.pagos, a.total, a.liq, a.mens,
         coalesce(d.n, 0), coalesce(d.valor, 0), (d.desde at time zone 'America/Sao_Paulo')::date,
         coalesce(d.an, 0), coalesce(d.avalor, 0), (d.adesde at time zone 'America/Sao_Paulo')::date,
         coalesce(cb.n, 0), coalesce(cb.valor, 0), a.estornos, a.tentativas, a.ult_tent, coalesce(ms.meses, '{}'::jsonb),
         -- pagando hoje mas com mês antigo sem pagar = devendo (a dívida aparece); parou com dívida = parou_devendo
         case when coalesce(d.n, 0) > 0 then 'devendo'
              when a.pagos = 0 then 'nunca_pagou'
              when a.ult >= v_hoje - 40 then case when coalesce(d.an, 0) > 0 then 'devendo' else 'em_dia' end
              when coalesce(d.an, 0) > 0 then 'parou_devendo'
              else 'encerrado' end
    from agg a
    join pes pe on pe.pessoa = a.pessoa
    left join cad cd on cd.pessoa = a.pessoa
    left join aluno al on al.pessoa = a.pessoa
    left join div d on d.pessoa = a.pessoa and d.serv = a.serv
    left join cob cb on cb.pessoa = a.pessoa and cb.serv = a.serv
    left join mes ms on ms.pessoa = a.pessoa and ms.serv = a.serv;
end $$;
revoke all on function public.fn_fin_diamante_servicos() from public, anon;
grant execute on function public.fn_fin_diamante_servicos() to authenticated;
