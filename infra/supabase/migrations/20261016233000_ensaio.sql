-- Ensaio de 20261016233000 numa transação DESFEITA (rollback). Sem dado pessoal: só contagens e somas.
-- Mede antes, depois da migration e depois da reversão: produto, linha do tempo, vw_transacoes, fn_fin_hotmart_funis,
-- fn_fin_hotmart_faturamento e fn_fin_funil_compradores (HT7 a HT11, Diamante, Clínica, ETHB 2024).
-- Rodar: python3 <executor que só aceita arquivo terminado em rollback> este arquivo. Resultado do ensaio de 16/10/2026: ver 20261016233000.explain.md
-- As funções fn_fin_* pedem perfil master em request.jwt.claims (o ensaio escolhe o primeiro de acesso.master).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em serial, passo text, linha text);

-- ===== foto: 00 antes =====
insert into pg_temp._z_out(passo, linha) select '00 antes produto', (select to_jsonb(p)::text from fin.produtos p where p.produto_id = '3595938');
insert into pg_temp._z_out(passo, linha) select '00 antes produtos_escritorio', (select count(*)::text from fin.produtos where familia = 'ESCRITORIO');
insert into pg_temp._z_out(passo, linha) select '00 antes hotmart_setor', coalesce(pessoas.hotmart_setor('3595938'), 'null');
insert into pg_temp._z_out(passo, linha) select '00 antes linha_do_tempo', (select jsonb_build_object(
    'linhas', count(*), 'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio'),
    'sem_setor', count(*) filter (where e.detalhe ->> 'setor' is distinct from 'escritorio'),
    'evento_id_nulo', count(*) filter (where e.evento_id is null),
    'com_evento_de_educacao', count(*) filter (where fe.setor is distinct from 'escritorio' and e.evento_id is not null))::text
  from pessoas.eventos e left join fin.eventos fe on fe.id = e.evento_id
 where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938');
insert into pg_temp._z_out(passo, linha) select '00 antes vw_transacoes ' || familia, jsonb_build_object('transacoes', count(*), 'pagas', count(*) filter (where grupo = 'pago'),
    'compradores_pagos', count(distinct email) filter (where grupo = 'pago'),
    'valor_oferta_pago', round(coalesce(sum(valor_oferta) filter (where grupo = 'pago'), 0), 2),
    'liquido_pago', round(coalesce(sum(liquido) filter (where grupo = 'pago'), 0), 2))::text
  from fin.vw_transacoes where familia in ('OUTROS', 'ESCRITORIO') group by familia;
select set_config('request.jwt.claims', json_build_object('sub', (select perfil_id from acesso.master limit 1), 'role', 'authenticated')::text, true);
insert into pg_temp._z_out(passo, linha) select '00 antes fn_fin_hotmart_funis ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta), 'liquido', sum(liquido),
    'estornos', sum(estornos), 'recusadas', sum(recusadas), 'compradores', sum(compradores))::text from public.fn_fin_hotmart_funis(f, null, null))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '00 antes fn_fin_hotmart_faturamento (2015-01-01 a hoje) ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta),
    'cobrado_cliente', sum(cobrado_cliente), 'liquido', sum(liquido))::text from public.fn_fin_hotmart_faturamento(f, date '2015-01-01', current_date))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '00 antes fn_fin_funil_compradores evento ' || e.id, (select jsonb_build_object('linhas', count(*), 'valor', round(coalesce(sum(t.valor), 0), 2))::text
    from public.fn_fin_funil_compradores(e.id) t)
  from fin.eventos e where e.id in (26, 27, 29, 30, 32, 34, 35, 36) order by e.id;

-- ===== 20261016233000 =====
insert into pg_temp._z_out(passo, linha) select '10 migration início', clock_timestamp()::text;
-- 20261016233000: produto Hotmart 3595938 "Holding Familiar" (conta academy) passa de OUTROS para ESCRITORIO
--
-- STATUS: NÃO APLICADA. Escrita e ensaiada (transação desfeita) em 16/10/2026 por back-end-sr, branch victor-holding-familiar-escritorio.
--   Decisão do Victor em 16/10/2026: o 3595938 é do ESCRITÓRIO (como SV 1663254, Croqui 1542521 e SV Elaine 1664749). O 1537308 (Croqui
--   Estrutural para Holding Familiar, 0 transações) NÃO entra: continua sem decisão. Depende de 20261016230100 (pessoas.hotmart_setor) e
--   de 20261016230200 (aplicada), nessa ordem.
-- POR QUE (medido em 16/10/2026): o produto está em fin.produtos com familia 'OUTROS' e sincroniza = false; 44 transações (23 COMPLETE,
--   18 CANCELLED, 1 CHARGEBACK, 1 REFUNDED, 1 EXPIRED; 1ª venda aprovada em 2023-12-07, última em 2024-12-11). Na linha do tempo
--   (pessoas.eventos, ref_tipo 'hotmart.transacao') há 44 linhas do produto, nenhuma com detalhe.setor, e 14 delas presas a evento de
--   educação (diamantes-2023-11 3, ht7-2024-01 2, ht8-2024-03 2, ht9-2024-05 2, ht10-2024-08 1, ht11-2024-11 1, clinica-2024-11 1,
--   ethb-2024-12 2). Esse vínculo é heurística de data (o produto não está em fin.evento_produtos nem em fin.evento_ofertas).
-- O QUE FAZ (3 passos, reversível; cada linha tocada vai antes ao backup, com um motivo):
--   1. fin.produtos: familia 'OUTROS' -> 'ESCRITORIO' e nota atualizada, só do produto 3595938 (motivo familia_alterada). NÃO mexe em
--      sincroniza. Com isso pessoas.hotmart_setor('3595938') passa a devolver 'escritorio' e o webhook e a carga (230100) tratam as vendas
--      novas do produto como escritório (setor marcado, sem evento de educação).
--   2. pessoas.eventos do produto 3595938 com evento de educação: evento_id vira null (motivo evento_educacao_em_escritorio), a mesma
--      regra da 230200. A informação "vendido no HT8" não se perde: fica no backup e continua calculável pela data em fin.trajetoria_nucleo.
--   3. pessoas.eventos do produto 3595938: detalhe.setor = 'escritorio' (motivo setor_marcado), só onde difere.
-- GUARDA DE PREMISSA (aborta se qualquer uma falhar): hotmart_setor existe; o produto existe na conta academy com familia 'OUTROS';
--   exatamente 3 produtos já em ESCRITORIO; exatamente 14 linhas do produto com evento de educação; os dois backups ainda não existem.
-- PÓS-CONDIÇÃO (aborta e desfaz tudo se falhar): produto em ESCRITORIO e sincroniza inalterado; 4 produtos em ESCRITORIO; hotmart_setor
--   devolve 'escritorio'; backups com 1 familia_alterada, 14 evento_educacao_em_escritorio e tantas setor_marcado quantas linhas ficaram
--   marcadas; nenhuma linha do produto sem setor nem com evento de educação.
-- NÃO FAZ: não toca em sincroniza; não reclassifica o 1537308; não altera função, view, grant nem o front (FamiliaHotmart em
--   web/modules/financeiro/domain/hotmart.ts não tem ESCRITORIO: nenhuma tela do Financeiro lista essa família); não toca em linha de
--   outro produto; não mexe em pessoas nem identificadores.
-- AS 5 PERGUNTAS: escala = 1 linha em fin.produtos; as linhas do produto em pessoas.eventos (44 de 641 mil, achadas pelo índice parcial
--   eventos_hotmart_ref_idx); índice = esse índice (ver o explain); frequência = única; repetição = a guarda recusa (o produto já não é
--   OUTROS e os backups existem); reversão = 20261016233000_reversao.sql (volta familia e nota pelo backup, restaura evento_id e tira
--   o setor só das linhas marcadas aqui, por id).
-- Backups: schema arquivo, dono Victor Hugo, prazo 90 dias (2027-01-14), RLS ligado e sem policy. Não são lidos por função viva.
-- ENSAIO: 20261016233000_ensaio.sql. Detalhe e números: 20261016233000.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare v_educ int;
begin
  if to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016233000: falta pessoas.hotmart_setor (20261016230100); aplicar nessa ordem';
  end if;
  if (select count(*) from fin.produtos where produto_id = '3595938' and conta = 'academy' and familia = 'OUTROS' and nome = 'Holding Familiar') <> 1 then
    raise exception '20261016233000: o produto 3595938 não está como Holding Familiar / academy / OUTROS em fin.produtos; esta migration já rodou ou o catálogo mudou';
  end if;
  if (select count(*) from fin.produtos where familia = 'ESCRITORIO') <> 3 then
    raise exception '20261016233000: esperava exatamente 3 produtos em ESCRITORIO (medido em 16/10: SV, Croqui e SV Elaine); revisar antes de aplicar';
  end if;
  select count(*) into v_educ from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938' and fe.setor is distinct from 'escritorio';
  if v_educ <> 14 then
    raise exception '20261016233000: % linha(s) do produto 3595938 com evento de educação (medido: exatamente 14 em 16/10); medir de novo e revisar', v_educ;
  end if;
  if to_regclass('arquivo.fin_produtos__20261016') is not null or to_regclass('arquivo.pessoas__eventos__20261016_233000') is not null then
    raise exception '20261016233000: um dos backups (arquivo.fin_produtos__20261016, arquivo.pessoas__eventos__20261016_233000) já existe; esta migration já rodou?';
  end if;
end $g$;

create table arquivo.fin_produtos__20261016 as
  select p.*, null::text as motivo from fin.produtos p where false;
alter table arquivo.fin_produtos__20261016 enable row level security;
revoke all on arquivo.fin_produtos__20261016 from public, anon, authenticated;
comment on table arquivo.fin_produtos__20261016 is
  '20261016233000: linha de fin.produtos antes de mudar o 3595938 Holding Familiar de OUTROS para ESCRITORIO (motivo: familia_alterada). dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016233000_reversao.sql';

create table arquivo.pessoas__eventos__20261016_233000 as
  select e.*, null::text as motivo from pessoas.eventos e where false;
alter table arquivo.pessoas__eventos__20261016_233000 enable row level security;
revoke all on arquivo.pessoas__eventos__20261016_233000 from public, anon, authenticated;
comment on table arquivo.pessoas__eventos__20261016_233000 is
  '20261016233000: linhas de pessoas.eventos do produto 3595938 alteradas ao virar escritório (motivo: evento_educacao_em_escritorio, setor_marcado). dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016233000_reversao.sql';

-- 1. a família do produto (decisão do Victor, 16/10/2026); sincroniza fica como está
with salva as (
  insert into arquivo.fin_produtos__20261016
    select p.*, 'familia_alterada' from fin.produtos p where p.produto_id = '3595938' and p.familia = 'OUTROS' returning produto_id
)
update fin.produtos x
   set familia = 'ESCRITORIO', nota = 'Decisão do Victor em 16/10/2026: produto do escritório (migration 20261016233000).'
  from salva where x.produto_id = salva.produto_id and x.familia = 'OUTROS';

-- 2. evento de educação em venda de escritório: copia a linha para o backup e zera o evento_id
with alvo as (
  select e.id from pessoas.eventos e
    join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938'
     and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016_233000 select e.*, 'evento_educacao_em_escritorio' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set evento_id = null from salva where x.id = salva.id and x.evento_id is not null;

-- 3. setor pelo produto (aditivo): a linha anterior vai ao backup, para a reversão voltar só as linhas marcadas aqui
with alvo as (
  select e.id from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938'
     and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016_233000 select e.*, 'setor_marcado' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set detalhe = x.detalhe || jsonb_build_object('setor', 'escritorio')
  from salva where x.id = salva.id and x.detalhe ->> 'setor' is distinct from 'escritorio';

-- pós-condição: se qualquer número fugir do medido, a transação inteira é desfeita
do $p$
declare v_prod int; v_esc int; v_sinc boolean; v_setor text; v_n1 int; v_n2 int; v_n3 int; v_sem int; v_educ int;
begin
  select count(*) into v_prod from arquivo.fin_produtos__20261016 where motivo = 'familia_alterada' and familia = 'OUTROS' and produto_id = '3595938';
  select count(*) into v_esc from fin.produtos where familia = 'ESCRITORIO';
  select (select sincroniza from fin.produtos where produto_id = '3595938' and familia = 'ESCRITORIO') = (select b.sincroniza from arquivo.fin_produtos__20261016 b where b.produto_id = '3595938')
    into v_sinc;
  v_setor := pessoas.hotmart_setor('3595938');
  select count(*) filter (where motivo = 'evento_educacao_em_escritorio'), count(*) filter (where motivo = 'setor_marcado'), count(*)
    into v_n2, v_n3, v_n1 from arquivo.pessoas__eventos__20261016_233000;
  select count(*) into v_sem from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938' and e.detalhe ->> 'setor' is distinct from 'escritorio';
  select count(*) into v_educ from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938' and fe.setor is distinct from 'escritorio';
  if v_prod <> 1 then raise exception '20261016233000: backup de fin.produtos com % linha(s) (esperado 1); desfeito', v_prod; end if;
  if v_esc <> 4 then raise exception '20261016233000: % produtos em ESCRITORIO (esperado 4); desfeito', v_esc; end if;
  if v_sinc is distinct from true then raise exception '20261016233000: sincroniza do produto mudou; desfeito'; end if;
  if v_setor is distinct from 'escritorio' then raise exception '20261016233000: hotmart_setor(3595938) devolveu %; desfeito', coalesce(v_setor, 'null'); end if;
  if v_n2 <> 14 then raise exception '20261016233000: backup com % evento_educacao_em_escritorio (esperado 14); desfeito', v_n2; end if;
  if v_n1 <> 14 + v_n3 then raise exception '20261016233000: backup de pessoas.eventos com % linhas (esperado 14 + % setor_marcado); desfeito', v_n1, v_n3; end if;
  if v_sem <> 0 then raise exception '20261016233000: % linha(s) do produto continuam sem setor; desfeito', v_sem; end if;
  if v_educ <> 0 then raise exception '20261016233000: % linha(s) do produto continuam com evento de educação; desfeito', v_educ; end if;
end $p$;

insert into pg_temp._z_out(passo, linha) select '10 migration fim', clock_timestamp()::text;

-- ===== foto: 20 depois =====
insert into pg_temp._z_out(passo, linha) select '20 depois produto', (select to_jsonb(p)::text from fin.produtos p where p.produto_id = '3595938');
insert into pg_temp._z_out(passo, linha) select '20 depois produtos_escritorio', (select count(*)::text from fin.produtos where familia = 'ESCRITORIO');
insert into pg_temp._z_out(passo, linha) select '20 depois hotmart_setor', coalesce(pessoas.hotmart_setor('3595938'), 'null');
insert into pg_temp._z_out(passo, linha) select '20 depois linha_do_tempo', (select jsonb_build_object(
    'linhas', count(*), 'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio'),
    'sem_setor', count(*) filter (where e.detalhe ->> 'setor' is distinct from 'escritorio'),
    'evento_id_nulo', count(*) filter (where e.evento_id is null),
    'com_evento_de_educacao', count(*) filter (where fe.setor is distinct from 'escritorio' and e.evento_id is not null))::text
  from pessoas.eventos e left join fin.eventos fe on fe.id = e.evento_id
 where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938');
insert into pg_temp._z_out(passo, linha) select '20 depois vw_transacoes ' || familia, jsonb_build_object('transacoes', count(*), 'pagas', count(*) filter (where grupo = 'pago'),
    'compradores_pagos', count(distinct email) filter (where grupo = 'pago'),
    'valor_oferta_pago', round(coalesce(sum(valor_oferta) filter (where grupo = 'pago'), 0), 2),
    'liquido_pago', round(coalesce(sum(liquido) filter (where grupo = 'pago'), 0), 2))::text
  from fin.vw_transacoes where familia in ('OUTROS', 'ESCRITORIO') group by familia;
select set_config('request.jwt.claims', json_build_object('sub', (select perfil_id from acesso.master limit 1), 'role', 'authenticated')::text, true);
insert into pg_temp._z_out(passo, linha) select '20 depois fn_fin_hotmart_funis ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta), 'liquido', sum(liquido),
    'estornos', sum(estornos), 'recusadas', sum(recusadas), 'compradores', sum(compradores))::text from public.fn_fin_hotmart_funis(f, null, null))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '20 depois fn_fin_hotmart_faturamento (2015-01-01 a hoje) ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta),
    'cobrado_cliente', sum(cobrado_cliente), 'liquido', sum(liquido))::text from public.fn_fin_hotmart_faturamento(f, date '2015-01-01', current_date))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '20 depois fn_fin_funil_compradores evento ' || e.id, (select jsonb_build_object('linhas', count(*), 'valor', round(coalesce(sum(t.valor), 0), 2))::text
    from public.fn_fin_funil_compradores(e.id) t)
  from fin.eventos e where e.id in (26, 27, 29, 30, 32, 34, 35, 36) order by e.id;

-- ===== 20261016233000_reversao.sql =====
-- Reversão de 20261016233000: devolve o produto 3595938 a OUTROS (com a nota anterior), restaura o evento_id e tira o setor SÓ das linhas
-- que o passo 3 marcou. Lê arquivo.fin_produtos__20261016 e arquivo.pessoas__eventos__20261016_233000 (não apaga os backups: valem até 2027-01-14).
-- Linhas que o webhook ou a carga gravaram depois NÃO são tocadas: o setor só volta nas linhas com motivo setor_marcado, por id, e só a chave setor.
-- Ordem: se a 20261016230200 também for revertida, reverter esta ANTES.
set local lock_timeout = '5s';
set local statement_timeout = '60s';
update fin.produtos x set familia = b.familia, nota = b.nota
  from arquivo.fin_produtos__20261016 b
 where b.motivo = 'familia_alterada' and b.produto_id = '3595938' and x.produto_id = b.produto_id
   and (x.familia is distinct from b.familia or x.nota is distinct from b.nota);
update pessoas.eventos x set evento_id = a.evento_id
  from arquivo.pessoas__eventos__20261016_233000 a
 where a.motivo = 'evento_educacao_em_escritorio' and a.id = x.id and x.evento_id is distinct from a.evento_id;
update pessoas.eventos x
   set detalhe = case when a.detalhe ? 'setor' then x.detalhe || jsonb_build_object('setor', a.detalhe -> 'setor') else x.detalhe - 'setor' end
  from arquivo.pessoas__eventos__20261016_233000 a
 where a.motivo = 'setor_marcado' and a.id = x.id and x.detalhe -> 'setor' is distinct from a.detalhe -> 'setor';


-- ===== foto: 30 depois da reversão =====
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão produto', (select to_jsonb(p)::text from fin.produtos p where p.produto_id = '3595938');
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão produtos_escritorio', (select count(*)::text from fin.produtos where familia = 'ESCRITORIO');
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão hotmart_setor', coalesce(pessoas.hotmart_setor('3595938'), 'null');
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão linha_do_tempo', (select jsonb_build_object(
    'linhas', count(*), 'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio'),
    'sem_setor', count(*) filter (where e.detalhe ->> 'setor' is distinct from 'escritorio'),
    'evento_id_nulo', count(*) filter (where e.evento_id is null),
    'com_evento_de_educacao', count(*) filter (where fe.setor is distinct from 'escritorio' and e.evento_id is not null))::text
  from pessoas.eventos e left join fin.eventos fe on fe.id = e.evento_id
 where e.ref_tipo = 'hotmart.transacao' and e.detalhe ->> 'produto' = '3595938');
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão vw_transacoes ' || familia, jsonb_build_object('transacoes', count(*), 'pagas', count(*) filter (where grupo = 'pago'),
    'compradores_pagos', count(distinct email) filter (where grupo = 'pago'),
    'valor_oferta_pago', round(coalesce(sum(valor_oferta) filter (where grupo = 'pago'), 0), 2),
    'liquido_pago', round(coalesce(sum(liquido) filter (where grupo = 'pago'), 0), 2))::text
  from fin.vw_transacoes where familia in ('OUTROS', 'ESCRITORIO') group by familia;
select set_config('request.jwt.claims', json_build_object('sub', (select perfil_id from acesso.master limit 1), 'role', 'authenticated')::text, true);
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão fn_fin_hotmart_funis ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta), 'liquido', sum(liquido),
    'estornos', sum(estornos), 'recusadas', sum(recusadas), 'compradores', sum(compradores))::text from public.fn_fin_hotmart_funis(f, null, null))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão fn_fin_hotmart_faturamento (2015-01-01 a hoje) ' || f, (select jsonb_build_object('vendas', sum(vendas), 'valor_oferta', sum(valor_oferta),
    'cobrado_cliente', sum(cobrado_cliente), 'liquido', sum(liquido))::text from public.fn_fin_hotmart_faturamento(f, date '2015-01-01', current_date))
  from unnest(array['OUTROS', 'ESCRITORIO']) f;
insert into pg_temp._z_out(passo, linha) select '30 depois da reversão fn_fin_funil_compradores evento ' || e.id, (select jsonb_build_object('linhas', count(*), 'valor', round(coalesce(sum(t.valor), 0), 2))::text
    from public.fn_fin_funil_compradores(e.id) t)
  from fin.eventos e where e.id in (26, 27, 29, 30, 32, 34, 35, 36) order by e.id;

-- backups (contagem por motivo) antes de desfazer
insert into pg_temp._z_out(passo, linha) select '40 backup pessoas.eventos', coalesce((select jsonb_object_agg(motivo, n)::text from (select motivo, count(*) n from arquivo.pessoas__eventos__20261016_233000 group by 1) z), '{}');
insert into pg_temp._z_out(passo, linha) select '40 backup fin.produtos', coalesce((select jsonb_object_agg(motivo, n)::text from (select motivo, count(*) n from arquivo.fin_produtos__20261016 group by 1) z), '{}');
select passo, linha from pg_temp._z_out order by em;
rollback;
