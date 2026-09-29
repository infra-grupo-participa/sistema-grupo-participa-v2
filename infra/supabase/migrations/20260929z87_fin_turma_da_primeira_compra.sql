-- 20260929z87 — Turma da PRIMEIRA compra vira função (fin.fn_turma_primeira_compra), para o banco da Ativação (cs) usar a
-- mesma regra que o Financeiro usa desde a z17. A view fin.vw_turma_origem_card passa a chamá-la; o resultado dela NÃO muda
-- (prova de zero diferença no fim: a migration aborta se uma linha sequer divergir).
--
-- Regra (Marcio, 29/09, vinculante e retroativa): "quem já foi de turma passada NÃO ganha turma nova: fica com a PRIMEIRA
-- turma dele". A primeira turma de quem nunca foi cadastrado na base vem da primeira compra HM/AURUM antes do marco do
-- Programa (25/06/2026 00h BRT), mapeada para a turma pelo calendário fin.acoes (produto HM). É a lógica da z17, só extraída.
--
-- AS 5 PERGUNTAS
--  1. Escala: custo por PESSOA (um e-mail), não por base. Caminho: fin.identidade (pk `no`, índice pessoa_chave) →
--     fin.hotmart_transacoes pelo índice hotmart_transacoes_email_idx (lower(trim(comprador_email))) → fin.acoes (~60 linhas).
--     Com 10x transações, cresce só com as compras DAQUELA pessoa.
--  2. Índice: a expressão do filtro é lower(TRIM(BOTH FROM comprador_email)) — a MESMA do índice (via fin.vw_transacoes.email).
--     explain (analyze) colado abaixo (Index Scan em hotmart_transacoes_email_idx).
--  3. Frequência: a view é lida pelo board do Financeiro (1 leitura por abertura de tela, já era assim). A função nova também é
--     chamada pelo gatilho de turma do card (cs, migration 0312 do repo disparos) só quando turma_origem está vazia —
--     dezenas de vezes por dia.
--  4. Repetição: a view chama 1x por card (385 cards) — medido abaixo, mesmo custo da view antiga (que já fazia o join por card).
--  5. Reversão: recriar a view com o corpo da z17 (está no arquivo 20260928z17_fin_turma_de_origem.sql) e `drop function
--     fin.fn_turma_primeira_compra(text)`. Nada grava dado.
--
-- MEDIÇÃO (29/09, produção, ensaio em begin…rollback):
--   explain (analyze, buffers, costs off) do corpo, e-mail de aluno com compra em 2021 (mascarado):
--     Nested Loop Left Join (actual time=0.140..0.143 rows=1) · Buffers: shared hit=34
--       Index Scan using identidade_pkey on identidade i            (Index Cond: no = 'e:<email>')
--       Index Scan using identidade_pessoa_idx on identidade i2     (Rows Removed by Filter: 2)
--       Index Scan using hotmart_transacoes_email_idx on hotmart_transacoes t
--             (Index Cond: lower(TRIM(BOTH FROM comprador_email)) = '<email>'; Rows Removed by Filter: 4)
--       Index Scan using produtos_pkey on produtos p
--       Seq Scan on acoes a (64 linhas; Rows Removed by Filter: 63 — tabela-calendário, Seq Scan é o certo)
--     Planning Time: 0.870 ms · Execution Time: 0.202 ms
--   select * from fin.vw_turma_origem_card (385 linhas): antiga 99,3 ms (+14,2 plan) · nova 108,5 ms (+6,4 plan) — empate.
--   Prova de igualdade (except nos dois sentidos): 0 só na antiga, 0 só na nova, de 385.

create or replace function fin.fn_turma_primeira_compra(p_email text)
returns table (turma text, aprovado_em timestamptz, dia_aprovado date, produto_nome text)
language sql
stable
set search_path = ''
as $$
  with emails as (
    select lower(trim(p_email)) as email
    union
    select substr(i2.no, 3)
      from fin.identidade i
      join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
     where i.no = 'e:' || lower(trim(p_email))
  ), primeira as (
    select t.aprovado_em, t.dia_aprovado, t.produto_nome
      from fin.vw_transacoes t
     where t.email in (select e.email from emails e)
       and t.familia in ('HM','AURUM')
       and t.grupo in ('pago','estornado')
       and t.aprovado_em < timestamptz '2026-06-25 03:00+00'
     order by t.aprovado_em, t.transacao
     limit 1
  )
  select tu.turma, p.aprovado_em, p.dia_aprovado, p.produto_nome
    from primeira p
    left join lateral (select a.turma from fin.acoes a
                        where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                          and p.aprovado_em >= a.inicio and p.aprovado_em < a.fim
                        order by a.prioridade desc, a.inicio desc limit 1) tu on true
$$;

revoke all on function fin.fn_turma_primeira_compra(text) from public, anon, authenticated;

-- Foto ANTES (para a prova de zero diferença).
create temp table z87_antes on commit drop as select * from fin.vw_turma_origem_card;

create or replace view fin.vw_turma_origem_card as
with card as (
  select b.contato_hm_id, lower(trim(b.email)) email, b.turma, b.turma_origem from cs.vw_fin_board b
)
select c.contato_hm_id,
       coalesce(c.turma_origem, p.turma, c.turma) turma,
       case when c.turma_origem is not null then 'cadastro'
            when p.turma is not null then 'primeira compra (' || p.produto_nome || ', ' || to_char(p.dia_aprovado, 'DD/MM/YYYY') || ')'
            else 'entrou pelo Programa' end regra,
       p.dia_aprovado primeira_compra
  from card c
  left join lateral fin.fn_turma_primeira_compra(c.email) p on true;

revoke all on fin.vw_turma_origem_card from public, anon, authenticated;

-- Prova: a view nova devolve exatamente o que a antiga devolvia. Uma linha de diferença = aborta tudo.
do $prova$
declare v_a int; v_b int; v_n int;
begin
  select count(*) into v_a from (select * from z87_antes except select * from fin.vw_turma_origem_card) x;
  select count(*) into v_b from (select * from fin.vw_turma_origem_card except select * from z87_antes) x;
  select count(*) into v_n from z87_antes;
  if v_a <> 0 or v_b <> 0 then
    raise exception 'z87: vw_turma_origem_card mudou de resultado (% linhas só na antiga, % só na nova, de %) — abortado', v_a, v_b, v_n;
  end if;
  raise notice 'z87: vw_turma_origem_card idêntica (% linhas)', v_n;
end $prova$;
