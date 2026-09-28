-- 20260928z — Resultado de cada funil (evento) a partir da Hotmart (28/09/2026).
-- Validação feita antes (Jornadas 2021–2022, produto 446345): a Hotmart bate com as planilhas de debriefing da época —
-- T11 342=342 vendas, T14 626=626, T15 620×621, T13 59×60; líquido (incl. vendas estornadas depois) a menos de 1% da
-- "comissão" registrada. Onde a janela foi inferida (T9, T10, T16, T17) a diferença aponta data de carrinho a acertar.
--
-- fin.evento_produtos: o que cada categoria de funil vende — 'ingresso' (entrada no evento) e 'oferta' (o que se vende
-- no evento). Montado pelo nome dos produtos do catálogo (fin.hotmart_catalogo); ajustável sem deploy.
-- Janelas: oferta = [carrinho_inicio (ou inicio), venda_ate]; ingresso = (venda_ate do evento anterior da MESMA
-- categoria, venda_ate] — o ingresso da edição N é vendido desde o fim da edição N−1 (1ª edição: 60 dias antes).
-- Venda = 1ª cobrança da compra (recorrência nula ou 1); valor vendido = valor da oferta × parcelas quando é parcelamento
-- da Hotmart (cada parcela é uma transação); no produto antigo cada venda é uma transação com o valor cheio.
-- Escritório (seminários): a conta Hotmart do escritório não está no espelho (pendência da credencial) — conta_ausente.

create table if not exists fin.evento_produtos (
  categoria text not null,
  produto_id text not null,
  papel text not null check (papel in ('ingresso','oferta')),
  primary key (categoria, produto_id)
);
alter table fin.evento_produtos enable row level security;
revoke all on fin.evento_produtos from public, anon, authenticated;

insert into fin.evento_produtos (categoria, produto_id, papel)
select v.categoria, v.produto_id, v.papel from (values
  -- Jornadas 2020–2022: vendiam o Curso Prático (HM antigo)
  ('jornada','446345','oferta'),
  -- Holding Total: ingresso HT (+ VIP, garrafa, pacote) e oferta Holding Masters
  ('holding_total','1560865','ingresso'), ('holding_total','5022814','ingresso'), ('holding_total','1561551','ingresso'),
  ('holding_total','2414291','ingresso'), ('holding_total','7273256','ingresso'), ('holding_total','6992157','ingresso'),
  ('holding_total','6990981','ingresso'),
  ('holding_total','446345','oferta'), ('holding_total','5064314','oferta'), ('holding_total','3507214','oferta'),
  ('holding_total','4704945','oferta'), ('holding_total','5504569','oferta'), ('holding_total','1560882','oferta'),
  ('holding_total','2803705','oferta'), ('holding_total','6303351','oferta'),
  -- Lives "Direto ao Ponto" (base HT / ex-alunos HM): oferta Holding Masters
  ('live_hm','5064314','oferta'), ('live_hm','3507214','oferta'), ('live_hm','4704945','oferta'),
  -- Certificação Holding Pro (jan/2023)
  ('certificacao','1667058','oferta'), ('certificacao','1560845','oferta'), ('certificacao','446345','oferta'),
  -- Clínicas: ingresso Clínica e oferta Aurum
  ('clinica','5682989','ingresso'), ('clinica','4432826','ingresso'), ('clinica','4486307','ingresso'), ('clinica','5683121','ingresso'),
  ('clinica','3094405','oferta'), ('clinica','1639219','oferta'), ('clinica','1276296','oferta'), ('clinica','1761876','oferta'),
  -- Imersões presenciais
  ('imersao','1667133','ingresso'), ('imersao','3094405','oferta'), ('imersao','1639219','oferta'),
  -- Aurum+ / Conexão Aurum: oferta Aurum
  ('aurum_plus','3094405','oferta'), ('aurum_plus','1639219','oferta'), ('aurum_plus','1276296','oferta'), ('aurum_plus','1761876','oferta'),
  -- Encontros do THB
  ('encontro_thb','5951389','ingresso'), ('encontro_thb','3094386','ingresso'), ('encontro_thb','1560357','ingresso'),
  ('encontro_thb','1537162','ingresso'), ('encontro_thb','6792566','ingresso'),
  ('encontro_thb','3094405','oferta'), ('encontro_thb','1639219','oferta'),
  -- Congresso do THB
  ('congresso','4127018','ingresso'), ('congresso','1462622','ingresso'),
  -- Encontros de Diamantes: ingresso e Serviço Diamante
  ('diamantes','3400997','ingresso'), ('diamantes','6489980','ingresso'), ('diamantes','1462643','oferta'),
  ('diamantes','3094430','oferta'), ('diamantes','1667105','oferta'),
  -- Residência / Workshop da Residência
  ('residencia','6144501','ingresso'), ('workshop','6991585','ingresso'), ('workshop','6144501','oferta'),
  -- Curso Nacional (CNHF): Acelera Holding como backend
  ('lancamento_cnhf','8347288','ingresso'), ('lancamento_cnhf','8381847','oferta')
) v(categoria, produto_id, papel)
join fin.hotmart_catalogo c on c.produto_id = v.produto_id
on conflict do nothing;

create or replace function public.fn_fin_funis()
returns table (
  evento_id bigint, nome text, categoria text, setor text, inicio date, fim date, carrinho_inicio date, venda_ate date,
  ingresso_de date, ingressos int, ingressos_bruto numeric, ingressos_liquido numeric,
  oferta_vendas int, oferta_compradores int, oferta_estornos int, oferta_bruto numeric, oferta_liquido numeric,
  compradores int, bruto numeric, liquido numeric,
  ref_vendas int, ref_valor numeric, ref_tipo text, ref_fonte text, observacao text, conta_ausente boolean
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with ev as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    -- 1ª cobrança de cada compra, paga ou estornada depois; valor contratado quando é parcelamento Hotmart
    select t.transacao, t.produto_id, t.email, t.grupo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia,
           t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end valor,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
             * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end liq
      from fin.vw_transacoes t
     where t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1 and t.email is not null
  ), casado as (
    select e.id, p.papel, x.*
      from ev e
      join fin.evento_produtos p on p.categoria = e.categoria
      join tx x on x.produto_id = p.produto_id
       and ((p.papel = 'oferta'   and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
         or (p.papel = 'ingresso' and x.dia between e.ing_de and e.venda_ate))
  ), agg as (
    select c.id,
           count(*) filter (where c.papel = 'ingresso' and c.grupo = 'pago')::int ing_n,
           coalesce(sum(c.valor) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_b,
           coalesce(sum(c.liq) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_l,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_n,
           count(distinct c.email) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_p,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'estornado')::int of_e,
           coalesce(sum(c.valor) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_b,
           coalesce(sum(c.liq) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_l,
           count(distinct c.email) filter (where c.grupo = 'pago')::int pess
      from casado c group by c.id
  )
  select e.id, e.nome, e.categoria, e.setor, e.inicio, e.fim, e.carrinho_inicio, e.venda_ate, e.ing_de,
         coalesce(a.ing_n, 0), round(coalesce(a.ing_b, 0), 2), round(coalesce(a.ing_l, 0), 2),
         coalesce(a.of_n, 0), coalesce(a.of_p, 0), coalesce(a.of_e, 0), round(coalesce(a.of_b, 0), 2), round(coalesce(a.of_l, 0), 2),
         coalesce(a.pess, 0), round(coalesce(a.ing_b, 0) + coalesce(a.of_b, 0), 2), round(coalesce(a.ing_l, 0) + coalesce(a.of_l, 0), 2),
         e.ref_vendas, e.ref_valor, e.ref_tipo, e.ref_fonte, e.observacao, (e.setor = 'escritorio')
    from ev e left join agg a on a.id = e.id
   order by e.inicio desc;
end $$;
revoke all on function public.fn_fin_funis() from public, anon;
grant execute on function public.fn_fin_funis() to authenticated;

-- Quem pagou em cada funil (o "micro"): uma linha por compra, com telefone mascarado sem gp_pode_ver_cpf().
create or replace function public.fn_fin_funil_compradores(p_evento_id bigint)
returns table (papel text, produto text, oferta text, dia date, situacao text, valor numeric, liquido numeric,
               nome text, email text, telefone text, parcelas int)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with e as (
    select x.*, coalesce((select max(y.venda_ate) from fin.eventos y where y.categoria = x.categoria and y.inicio < x.inicio) + 1, x.inicio - 60) ing_de
      from fin.eventos x where x.id = p_evento_id
  )
  select p.papel, t.produto_nome, t.oferta_codigo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date,
         t.grupo,
         round(t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         round(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
               * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         fin.nome_proprio(t.nome), t.email,
         case when coalesce(public.gp_pode_ver_cpf(), false) then h.comprador_telefone
              when h.comprador_telefone is not null then '···' || right(h.comprador_telefone, 4) end,
         t.parcelas
    from e
    join fin.evento_produtos p on p.categoria = e.categoria
    join fin.vw_transacoes t on t.produto_id = p.produto_id and t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1
     and ((p.papel = 'oferta' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
       or (p.papel = 'ingresso' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))
    join fin.hotmart_transacoes h on h.transacao = t.transacao
   order by p.papel desc, t.aprovado_em;
end $$;
revoke all on function public.fn_fin_funil_compradores(bigint) from public, anon;
grant execute on function public.fn_fin_funil_compradores(bigint) to authenticated;

-- 20260928z2 (aplicada à parte): liquido_conferencia = líquido de TODAS as vendas da janela, incluindo as estornadas
-- depois — é como a planilha da época somava a "comissão" (T14: 626 vendas pagas e R$ 2.194.436 × R$ 2.185.557).
do $do$
declare v text;
begin
  v := pg_get_functiondef('public.fn_fin_funis()'::regprocedure);
  if position('liquido_conferencia' in v) > 0 then return; end if;
  v := replace(v, 'conta_ausente boolean', 'conta_ausente boolean, liquido_conferencia numeric');
  v := replace(v, $a$count(distinct c.email) filter (where c.grupo = 'pago')::int pess$a$,
    $b$count(distinct c.email) filter (where c.grupo = 'pago')::int pess,
           coalesce(sum(c.liq), 0) liq_conf$b$);
  v := replace(v, $a$e.observacao, (e.setor = 'escritorio')$a$, $b$e.observacao, (e.setor = 'escritorio'), round(coalesce(a.liq_conf, 0), 2)$b$);
  drop function public.fn_fin_funis();
  execute v;
  revoke all on function public.fn_fin_funis() from public, anon;
  grant execute on function public.fn_fin_funis() to authenticated;
end $do$;
