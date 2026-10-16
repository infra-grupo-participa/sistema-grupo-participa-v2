-- 20261016230200: corrige os eventos Hotmart já gravados na linha do tempo (duplicados, evento de educação em venda de escritório, setor)
--
-- STATUS: NÃO APLICADA. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Depende de 20261016230000 e 20261016230100.
-- REVISADA após o pentest de 16/10 (PENTEST-HOTMART-SETOR-2026-10-16.md): guarda de premissa exata, pós-condição, backup do passo 3 e
--   guarda de índice válido.
-- ORDEM: depois da 230100 (senão o webhook recria duplicata no meio da limpeza).
-- POR QUE (medido em 16/10/2026): 13 grupos de linhas com o mesmo ref_id e tipo (7 checkout, 6 reembolso; nenhum com pessoas diferentes,
--   nenhum com mais de 2 linhas); 2 linhas de venda de produto de escritório (família ESCRITORIO na academy) presas a evento de educação
--   (1 Croqui em encontro_thb, 1 em holding_total); 578 linhas de produto de escritório sem a marca de setor.
-- O QUE FAZ (só pessoas.eventos, 3 passos, reversível; cada linha tocada vai antes ao backup com um motivo):
--   1. Duplicados (motivo duplicado_removido): por (ref_id, tipo) de ref_tipo 'hotmart.transacao', fica UMA linha (a que tem fonte_id;
--      empate: a de menor id) e as outras saem.
--   2. Evento de educação em venda de escritório (motivo evento_educacao_em_escritorio): evento_id vira null. Não se atribui outro
--      evento: a regra do financeiro não tem evento de escritório para essa venda.
--   3. Setor (motivo setor_marcado): detalhe.setor = 'escritorio' nas linhas de produto de família ESCRITORIO/ESCRITORIO_SOLUCOES, com a
--      linha anterior guardada no backup (id e detalhe) para a reversão voltar SÓ essas linhas. UPDATE só do que difere.
-- GUARDA DE PREMISSA (aborta se qualquer uma falhar): índice eventos_hotmart_ref_idx válido e pronto; no máximo 13 grupos duplicados;
--   nenhum grupo com mais de uma pessoa ou mais de 2 linhas; exatamente 2 linhas de escritório com evento de educação; backup ainda não existe.
-- PÓS-CONDIÇÃO (aborta e desfaz tudo se falhar): sem grupo duplicado; backup com 13 duplicado_removido, 2 evento_educacao_em_escritorio e
--   tantas setor_marcado quantas linhas ficaram marcadas; nenhuma linha de escritório sem setor.
-- NÃO FAZ: não reclassifica o produto 3595938 (Holding Familiar, família OUTROS: a confirmar) nem o 1537308 (Croqui Estrutural para
--   Holding Familiar, família OUTROS, 0 transações); não toca em linha de outro tipo de evento; não mexe em pessoas nem identificadores.
-- AS 5 PERGUNTAS: escala = ~7,5 mil linhas Hotmart de 641 mil (índice parcial da 230000; o passo 3 lê a tabela inteira UMA vez, sem filtro
--   de índice); índice = eventos_hotmart_ref_idx; frequência = única; repetição = recusada pela guarda (o backup já existe) e, se o backup
--   for removido, os UPDATEs só tocam o que difere; reversão = 20261016230200_reversao.sql (reinsere do backup, restaura evento_id e o
--   detalhe das linhas marcadas pelo passo 3).
-- Backup: schema arquivo, dono Victor Hugo, prazo 90 dias (2027-01-14), RLS ligado e sem policy. Não é lido por função viva.
--   O prazo está só no comentário da tabela: falta o card que lembra de apagar (ver docs/pessoa-unica/hotmart-setor-e-idempotencia.md).
-- ENSAIO: 20261016230100_ensaio.sql. Detalhe: 20261016230200.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare v_grupos int; v_multi int; v_alvo2 int;
begin
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('pessoas.eventos_hotmart_ref_idx') and i.indisvalid and i.indisready)
     or to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016230200: falta o índice da 230000 (existente, válido e pronto) ou a função da 230100; aplicar nessa ordem';
  end if;
  select count(*), count(*) filter (where n > 2 or p > 1) into v_grupos, v_multi
    from (select count(*) n, count(distinct pessoa_id) p from pessoas.eventos
           where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  if v_grupos > 13 then
    raise exception '20261016230200: % grupos duplicados (medido: 13 em 16/10); a regra de limpeza precisa de revisão', v_grupos;
  end if;
  if v_multi > 0 then
    raise exception '20261016230200: % grupo(s) duplicado(s) com mais de 2 linhas ou com pessoas diferentes; a regra de limpeza não vale', v_multi;
  end if;
  select count(*) into v_alvo2 from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio';
  if v_alvo2 <> 2 then
    raise exception '20261016230200: % venda(s) de escritório com evento de educação (medido: exatamente 2 em 16/10)', v_alvo2;
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
  '20261016230200: linhas de pessoas.eventos tiradas ou alteradas na correção da Hotmart (motivo: duplicado_removido, evento_educacao_em_escritorio, setor_marcado). dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016230200_reversao.sql';

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

-- 3. setor pelo produto (aditivo): a linha anterior vai ao backup, para a reversão voltar só as linhas marcadas aqui
with alvo as (
  select e.id from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio'
     and e.detalhe ->> 'setor' is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'setor_marcado' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set detalhe = x.detalhe || jsonb_build_object('setor', 'escritorio')
  from salva where x.id = salva.id and x.detalhe ->> 'setor' is distinct from 'escritorio';

-- pós-condição: se qualquer número fugir do medido, a transação inteira é desfeita
do $p$
declare v_dup int; v_n1 int; v_n2 int; v_n3 int; v_total int; v_sem int;
begin
  select count(*) into v_dup from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  select count(*) filter (where motivo = 'duplicado_removido'), count(*) filter (where motivo = 'evento_educacao_em_escritorio'),
         count(*) filter (where motivo = 'setor_marcado'), count(*)
    into v_n1, v_n2, v_n3, v_total from arquivo.pessoas__eventos__20261016;
  select count(*) into v_sem from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio';
  if v_dup <> 0 then raise exception '20261016230200: ainda há % grupo(s) duplicado(s); desfeito', v_dup; end if;
  if v_n1 <> 13 or v_n2 <> 2 then
    raise exception '20261016230200: backup com % duplicado_removido e % evento_educacao_em_escritorio (esperado 13 e 2); desfeito', v_n1, v_n2;
  end if;
  if v_total <> 15 + v_n3 then raise exception '20261016230200: backup com % linhas (esperado 15 + % setor_marcado); desfeito', v_total, v_n3; end if;
  if v_sem <> 0 then raise exception '20261016230200: % linha(s) de escritório continuam sem setor; desfeito', v_sem; end if;
end $p$;
