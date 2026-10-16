-- 20261016230200: corrige os eventos Hotmart já gravados na linha do tempo (duplicados, evento de educação em venda de escritório, setor)
--
-- STATUS: NÃO APLICADA. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Depende de 20261016230000 e 20261016230100.
-- ORDEM: depois da 230100 (senão o webhook recria duplicata no meio da limpeza).
-- POR QUE (medido em 16/10/2026): 13 grupos de linhas com o mesmo ref_id e tipo (7 checkout, 6 reembolso; nenhum com pessoas diferentes);
--   2 linhas de venda de produto de escritório (família ESCRITORIO na academy) presas a evento de educação (1 Croqui em encontro_thb,
--   1 em holding_total); 578 linhas de produto de escritório sem a marca de setor.
-- O QUE FAZ (só pessoas.eventos, 3 passos, reversível):
--   1. Duplicados: por (ref_id, tipo) de ref_tipo 'hotmart.transacao', fica UMA linha (a que tem fonte_id; empate: a de menor id) e as
--      outras saem. A linha que sai vai antes para o backup arquivo.pessoas__eventos__20261016 (coluna motivo = duplicado_removido).
--   2. Evento de educação em venda de escritório: evento_id vira null (a linha antes vai ao backup, motivo = evento_educacao_em_escritorio).
--      Não se atribui outro evento: a regra do financeiro não tem evento de escritório para essa venda.
--   3. Setor: detalhe.setor = 'escritorio' nas linhas de produto de família ESCRITORIO/ESCRITORIO_SOLUCOES (UPDATE só com IS DISTINCT FROM;
--      aditivo: reverter é tirar a chave).
-- NÃO FAZ: não reclassifica o produto 3595938 (Holding Familiar, família OUTROS: a confirmar) nem o 1537308 (Croqui Estrutural para
--   Holding Familiar, família OUTROS, 0 transações); não toca em linha de outro tipo de evento; não mexe em pessoas nem identificadores.
-- AS 5 PERGUNTAS: escala = ~7,5 mil linhas Hotmart de 641 mil (índice parcial da 230000; o passo 3 lê a tabela inteira UMA vez, sem filtro
--   de índice); índice = eventos_hotmart_ref_idx; frequência = única; repetição = idempotente (rodar de novo não acha nada a fazer);
--   reversão = 20261016230200_reversao.sql (reinsere do backup, restaura evento_id, tira a chave setor).
-- Backup: schema arquivo, dono Victor Hugo, prazo 90 dias (2027-01-14), RLS ligado e sem policy. Não é lido por função viva.
-- ENSAIO: 20261016230200_ensaio.sql. Detalhe: 20261016230200.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regclass('pessoas.eventos_hotmart_ref_idx') is null or to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016230200: falta o índice da 230000 ou a função da 230100; aplicar nessa ordem';
  end if;
  if (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x) > 100 then
    raise exception '20261016230200: mais de 100 grupos duplicados (medido: 13 em 16/10); a regra de limpeza precisa de revisão';
  end if;
  if to_regclass('arquivo.pessoas__eventos__20261016') is not null then
    raise exception '20261016230200: o backup arquivo.pessoas__eventos__20261016 já existe; esta migration já rodou?';
  end if;
end $g$;

create table arquivo.pessoas__eventos__20261016 as
  select e.*, null::text as motivo from pessoas.eventos e where false;
alter table arquivo.pessoas__eventos__20261016 enable row level security;
revoke all on arquivo.pessoas__eventos__20261016 from public, anon, authenticated;
comment on table arquivo.pessoas__eventos__20261016 is
  '20261016230200: linhas de pessoas.eventos tiradas ou alteradas na correção da Hotmart. dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016230200_reversao.sql';

-- 1. duplicados: sai a sobra, fica uma
with d as (
  select e.id,
         row_number() over (partition by e.ref_id, e.tipo order by (e.fonte_id is not null) desc, e.id) as rn
    from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao'
     and (e.ref_id, e.tipo) in (select ref_id, tipo from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1)
), apagadas as (
  delete from pessoas.eventos e using d where e.id = d.id and d.rn > 1 returning e.*
)
insert into arquivo.pessoas__eventos__20261016 select a.*, 'duplicado_removido' from apagadas a;

-- 2. evento de educação em venda de escritório: copia a linha para o backup e zera o evento_id
with alvo as (
  select e.id from pessoas.eventos e
    join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'evento_educacao_em_escritorio' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set evento_id = null from salva where x.id = salva.id and x.evento_id is not null;

-- 3. setor pelo produto (aditivo)
update pessoas.eventos x set detalhe = x.detalhe || jsonb_build_object('setor', 'escritorio')
 where x.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(x.detalhe ->> 'produto') = 'escritorio'
   and x.detalhe ->> 'setor' is distinct from 'escritorio';
