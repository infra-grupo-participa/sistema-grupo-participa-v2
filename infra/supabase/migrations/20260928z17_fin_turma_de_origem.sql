-- 20260928z17 — Turma de ORIGEM (regra do João, 28/09): "se a pessoa já foi da T10, parou de pagar e voltou comprando de
-- novo, ainda é da T10. T39 é só para quem nunca teve contato com o Time Holding Brasil e pagou para entrar."
-- Medido: dos 183 cards do board em T39/T40/T41 (turma_origem vazia no cadastro), 117 já tinham comprado HM/Aurum antes
-- (Curso Prático 2019–2024 na maioria). O cadastro (cs.contatos_hm) NÃO é tocado — alimenta grupos e disparos; o
-- financeiro calcula a turma de origem em fin.vw_turma_origem_card e o board passa a exibi-la (z18).
insert into fin.acoes (produto, nome, canal, turma, inicio, fim, sck_regex, prioridade, fonte)
select 'HM', v.turma || ' · Curso Prático de Holding Familiar — ' || to_char(v.ini, 'MM/YYYY'), 'Jornada', v.turma,
       (v.ini::timestamp at time zone 'America/Sao_Paulo'), (v.fim::timestamp at time zone 'America/Sao_Paulo'), null, 50,
       'Drive [HT] Catálogo de Ofertas (turma × data)'
  from (values ('T1', date '2019-10-11', date '2019-12-10'), ('T2', date '2019-12-10', date '2020-01-21'),
               ('T3', date '2020-01-21', date '2020-04-12'), ('T4', date '2020-04-12', date '2020-06-01')) v(turma, ini, fim)
 where not exists (select 1 from fin.acoes a where a.produto = 'HM' and a.turma = v.turma and a.prioridade = 50);

create or replace view fin.vw_turma_origem_card as
with card as (
  select b.contato_hm_id, lower(trim(b.email)) email, b.turma, b.turma_origem from cs.vw_fin_board b
), emails as (
  select c.contato_hm_id, coalesce(substr(i2.no, 3), c.email) email
    from card c
    left join fin.identidade i on i.no = 'e:' || c.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
), primeira as (
  select distinct on (e.contato_hm_id) e.contato_hm_id, t.aprovado_em, t.dia_aprovado, t.produto_nome
    from emails e
    join fin.vw_transacoes t on t.email = e.email and t.familia in ('HM','AURUM') and t.grupo in ('pago','estornado')
   where t.aprovado_em < timestamptz '2026-06-25 03:00+00'
   order by e.contato_hm_id, t.aprovado_em
)
select c.contato_hm_id,
       coalesce(c.turma_origem, tu.turma, c.turma) turma,
       case when c.turma_origem is not null then 'cadastro'
            when tu.turma is not null then 'primeira compra (' || p.produto_nome || ', ' || to_char(p.dia_aprovado, 'DD/MM/YYYY') || ')'
            else 'entrou pelo Programa' end regra,
       p.dia_aprovado primeira_compra
  from card c
  left join primeira p on p.contato_hm_id = c.contato_hm_id
  left join lateral (select a.turma from fin.acoes a
                      where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                        and p.aprovado_em >= a.inicio and p.aprovado_em < a.fim
                      order by a.prioridade desc, a.inicio desc limit 1) tu on true;
revoke all on fin.vw_turma_origem_card from public, anon, authenticated;
