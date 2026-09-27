-- 20260928n2 — Refino de fin.vw_acao_card (mesmo dia da 20260928n), medido no board:
--  * a compra que abriu o card: sinal/cheio do catálogo primeiro; senão a 1ª compra de 2026; só depois a mais antiga
--    (antes, quem tinha compra antiga caía em "Base antiga" mesmo tendo comprado o Programa em 2026);
--  * card sem compra paga usa a DATA DE ENTRADA no board para achar o evento;
--  * canal "Não classificado"/vazio herda o canal da ação — inclusive das ações vindas da janela antiga.
-- Resultado (27/09): 341 cards, 0 sem ação, 0 "Não classificado"; valores do board iguais.
create or replace view fin.vw_acao_card as
with card as (
  select b.contato_hm_id, b.origem, b.acao_nome, b.acao_data, lower(trim(b.email)) email, ch.criado_em entrada
    from cs.vw_fin_board b
    join cs.contatos_hm ch on ch.id = b.contato_hm_id
), emails as (
  select c.contato_hm_id, coalesce(substr(i2.no, 3), c.email) email
    from card c
    left join fin.identidade i on i.no = 'e:' || c.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
), primeira as (
  select distinct on (c.contato_hm_id) c.contato_hm_id, t.aprovado_em, t.dia_aprovado, t.origem_sck
    from card c
    join emails e on e.contato_hm_id = c.contato_hm_id
    join fin.vw_transacoes t on t.email = e.email and t.familia = c.origem and t.grupo = 'pago'
    left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
   order by c.contato_hm_id, (cat.categoria in ('sinal','compra_cheia')) desc nulls last,
            (t.dia_aprovado >= date '2026-01-01') desc, t.aprovado_em
), base as (
  select c.*, p.aprovado_em, p.dia_aprovado, p.origem_sck,
         coalesce(p.aprovado_em, c.entrada) quando,
         (p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%') comercial
    from card c left join primeira p on p.contato_hm_id = c.contato_hm_id
)
select b.contato_hm_id,
       coalesce(b.acao_nome, s.nome, j.nome,
                case when b.comercial then 'Comercial (venda direta)' end,
                case when b.dia_aprovado < date '2026-01-01' then 'Base antiga (antes de 2026)' end,
                case when b.aprovado_em is null then 'Sem pagamento ainda' end,
                'Base (fora de evento)') acao_nome,
       coalesce(b.acao_data, s.inicio, j.inicio, b.quando) acao_data,
       case when b.acao_nome is not null then 'janela do evento'
            when s.nome is not null then 'link de venda'
            when j.nome is not null and b.aprovado_em is null then 'data de entrada no board'
            when j.nome is not null then 'data da compra'
            when b.comercial then 'link do comercial'
            when b.aprovado_em is null then 'sem compra paga'
            else 'data da compra' end acao_regra,
       coalesce(n.canal, s.canal, j.canal,
                case when b.comercial then 'Comercial' end,
                case when b.dia_aprovado < date '2026-01-01' then 'Base antiga' end,
                case when b.aprovado_em is null then 'Sem pagamento ainda' end,
                'Base (fora de evento)') acao_canal,
       b.dia_aprovado captado_em,
       b.origem_sck captado_sck
  from base b
  left join lateral (select a.canal from fin.acoes a where a.produto = b.origem and a.nome = b.acao_nome limit 1) n on true
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = b.origem and a.sck_regex is not null and b.origem_sck ~* a.sck_regex
                      order by a.prioridade, a.id limit 1) s on true
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = b.origem and a.inicio is not null and b.quando >= a.inicio and b.quando < a.fim
                      order by a.prioridade, a.id limit 1) j on true;
revoke all on fin.vw_acao_card from public, anon, authenticated;
