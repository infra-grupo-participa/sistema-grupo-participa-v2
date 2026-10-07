-- Ensaio de 20261007n_mkt_trafego_clinica_miami_oferta.sql: 2 passadas num só begin … rollback. Gerado a partir dos .sql
-- como estão. Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;

insert into pg_temp._z_out (passo, linha) select '1 antes', (select jsonb_build_object(
  'p68', (select jsonb_build_object('tipo', tipo, 'unidade', unidade, 'sub', subarea_trafego, 'tl', tipo_lancamento, 'ini', inicio, 'fim', fim) from mkt.projetos where id = 68),
  'conta_hotmart_68', mkt_trafego.conta_hotmart(68),
  'vinculos_68', (select jsonb_agg(conta || '/' || produto_id || '/' || coalesce(oferta_codigo, '') || '/' || oferta_exclusiva) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'produtos_hotmart_total', (select count(*) from mkt_trafego.produtos_hotmart),
  'receita_68', (select jsonb_build_object('linhas', count(*), 'bruto', sum(bruto)) from mkt_trafego.receita_vendas(68)),
  'receita_total_linhas', (select count(*) from mkt_trafego.receita_vendas(null))
))::text;

-- ===== PASSADA 1: 20261007n_mkt_trafego_clinica_miami_oferta.sql =====
-- 20261007n: Tráfego, a oferta mjzv4v0s da Hotmart ligada ao projeto da Clínica de Miami (68)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007n_ensaio.sql (begin … rollback, 2×). Relatório: 20261007n.explain.md.
--
-- POR QUE
--   Decisão do Victor Hugo (07/10/2026): a venda da Clínica de Miami (produto 6489980, oferta mjzv4v0s, conta academy)
--   é do projeto clinica-miami-2026-12 (mkt.projetos 68). Sem vínculo em mkt_trafego.produtos_hotmart, a receita do
--   projeto no Tráfego vem vazia. E mkt_trafego.conta_hotmart(68) só devolve a conta com tipo/unidade preenchidos:
--   hoje os dois estão nulos (a migration 20261007152825 deixou nulo porque a fonte não dizia).
--
-- O QUE FAZ
--   1. mkt.projetos 68: tipo 'interno', unidade 'csm' (mkt.unidades: csm/interno, "CSM Academy (o educacional)"; a
--      Clínica é do educacional e a conta Hotmart é academy). subarea_trafego sai 'interno' pelo gatilho
--      projetos_tipo_unidade. tipo_lancamento continua nulo (decisão 7 do Maestro: o Victor escolhe na tela).
--   2. mkt_trafego.produtos_hotmart: projeto 68, conta academy, produto 6489980, oferta mjzv4v0s, oferta_exclusiva.
--      Oferta exclusiva = nível 1 de mkt_trafego.receita_vendas (a venda da oferta é do projeto em qualquer data).
--
-- AS 5 PERGUNTAS
--   escala: 1 update e 1 insert. índice: únicos existentes (produtos_hotmart_unico, produtos_hotmart_oferta_exclusiva_unica).
--   frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim.
--
-- IDEMPOTENTE: tipo/unidade já iguais → não muda; vínculo igual já existe → não insere. tipo/unidade diferentes de nulo
--   e do esperado, ou oferta exclusiva já de outro projeto → aborta.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $n$
declare
  r record;
begin
  -- 0. Guarda de premissa
  select id, tipo, unidade, tipo_lancamento into r from mkt.projetos
   where id = 68 and etiqueta_clickup = 'clinica-miami-2026-12' and sigla = 'CNFMIAMI26';
  if not found then
    raise exception '20261007n: projeto 68 não é mais a Clínica de Miami (CNFMIAMI26). Conferir.';
  end if;
  if (r.tipo is not null or r.unidade is not null)
     and (r.tipo is distinct from 'interno' or r.unidade is distinct from 'csm') then
    raise exception '20261007n: projeto 68 já tem tipo % / unidade % (alguém mudou na tela). Conferir com o Victor.', r.tipo, r.unidade;
  end if;
  if not exists (select 1 from mkt.unidades where codigo = 'csm' and tipo = 'interno') then
    raise exception '20261007n: unidade csm/interno não existe em mkt.unidades';
  end if;
  if exists (select 1 from mkt_trafego.produtos_hotmart where conta = 'academy' and oferta_codigo = 'mjzv4v0s'
               and oferta_exclusiva and projeto_id <> 68) then
    raise exception '20261007n: a oferta mjzv4v0s já é exclusiva de outro projeto. Conferir com o Victor.';
  end if;

  -- 1. tipo e unidade (só se ainda nulos)
  update mkt.projetos set tipo = 'interno', unidade = 'csm', atualizado_em = now()
   where id = 68 and tipo is null and unidade is null;

  -- 2. vínculo da oferta (só se ainda não existe)
  insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva, obs)
  select 68, 'academy', '6489980', 'mjzv4v0s', true,
         'Clínica de Miami vendida no produto 6489980 ("Encontro Internacional com Diamantes"), oferta mjzv4v0s: decisão '
         || 'do Victor Hugo (07/10/2026). Migration 20261007n.'
   where not exists (select 1 from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
                       and produto_id = '6489980' and oferta_codigo = 'mjzv4v0s');

  -- 3. Pós-condição
  if mkt_trafego.conta_hotmart(68) is distinct from 'academy' then
    raise exception '20261007n: conta_hotmart(68) não deu academy';
  end if;
  if (select count(*) from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
        and produto_id = '6489980' and oferta_codigo = 'mjzv4v0s' and oferta_exclusiva) <> 1 then
    raise exception '20261007n: vínculo exclusivo de mjzv4v0s ao projeto 68 não ficou gravado';
  end if;
end
$n$;

-- REVERSÃO (numa transação):
-- delete from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy' and produto_id = '6489980'
--    and oferta_codigo = 'mjzv4v0s';
-- update mkt.projetos set tipo = null, unidade = null, atualizado_em = now() where id = 68 and tipo_lancamento is null;

insert into pg_temp._z_out (passo, linha) select '2 depois1', (select jsonb_build_object(
  'p68', (select jsonb_build_object('tipo', tipo, 'unidade', unidade, 'sub', subarea_trafego, 'tl', tipo_lancamento, 'ini', inicio, 'fim', fim) from mkt.projetos where id = 68),
  'conta_hotmart_68', mkt_trafego.conta_hotmart(68),
  'vinculos_68', (select jsonb_agg(conta || '/' || produto_id || '/' || coalesce(oferta_codigo, '') || '/' || oferta_exclusiva) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'produtos_hotmart_total', (select count(*) from mkt_trafego.produtos_hotmart),
  'receita_68', (select jsonb_build_object('linhas', count(*), 'bruto', sum(bruto)) from mkt_trafego.receita_vendas(68)),
  'receita_total_linhas', (select count(*) from mkt_trafego.receita_vendas(null))
))::text;

-- ===== PASSADA 2: 20261007n_mkt_trafego_clinica_miami_oferta.sql =====
-- 20261007n: Tráfego, a oferta mjzv4v0s da Hotmart ligada ao projeto da Clínica de Miami (68)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007n_ensaio.sql (begin … rollback, 2×). Relatório: 20261007n.explain.md.
--
-- POR QUE
--   Decisão do Victor Hugo (07/10/2026): a venda da Clínica de Miami (produto 6489980, oferta mjzv4v0s, conta academy)
--   é do projeto clinica-miami-2026-12 (mkt.projetos 68). Sem vínculo em mkt_trafego.produtos_hotmart, a receita do
--   projeto no Tráfego vem vazia. E mkt_trafego.conta_hotmart(68) só devolve a conta com tipo/unidade preenchidos:
--   hoje os dois estão nulos (a migration 20261007152825 deixou nulo porque a fonte não dizia).
--
-- O QUE FAZ
--   1. mkt.projetos 68: tipo 'interno', unidade 'csm' (mkt.unidades: csm/interno, "CSM Academy (o educacional)"; a
--      Clínica é do educacional e a conta Hotmart é academy). subarea_trafego sai 'interno' pelo gatilho
--      projetos_tipo_unidade. tipo_lancamento continua nulo (decisão 7 do Maestro: o Victor escolhe na tela).
--   2. mkt_trafego.produtos_hotmart: projeto 68, conta academy, produto 6489980, oferta mjzv4v0s, oferta_exclusiva.
--      Oferta exclusiva = nível 1 de mkt_trafego.receita_vendas (a venda da oferta é do projeto em qualquer data).
--
-- AS 5 PERGUNTAS
--   escala: 1 update e 1 insert. índice: únicos existentes (produtos_hotmart_unico, produtos_hotmart_oferta_exclusiva_unica).
--   frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim.
--
-- IDEMPOTENTE: tipo/unidade já iguais → não muda; vínculo igual já existe → não insere. tipo/unidade diferentes de nulo
--   e do esperado, ou oferta exclusiva já de outro projeto → aborta.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $n$
declare
  r record;
begin
  -- 0. Guarda de premissa
  select id, tipo, unidade, tipo_lancamento into r from mkt.projetos
   where id = 68 and etiqueta_clickup = 'clinica-miami-2026-12' and sigla = 'CNFMIAMI26';
  if not found then
    raise exception '20261007n: projeto 68 não é mais a Clínica de Miami (CNFMIAMI26). Conferir.';
  end if;
  if (r.tipo is not null or r.unidade is not null)
     and (r.tipo is distinct from 'interno' or r.unidade is distinct from 'csm') then
    raise exception '20261007n: projeto 68 já tem tipo % / unidade % (alguém mudou na tela). Conferir com o Victor.', r.tipo, r.unidade;
  end if;
  if not exists (select 1 from mkt.unidades where codigo = 'csm' and tipo = 'interno') then
    raise exception '20261007n: unidade csm/interno não existe em mkt.unidades';
  end if;
  if exists (select 1 from mkt_trafego.produtos_hotmart where conta = 'academy' and oferta_codigo = 'mjzv4v0s'
               and oferta_exclusiva and projeto_id <> 68) then
    raise exception '20261007n: a oferta mjzv4v0s já é exclusiva de outro projeto. Conferir com o Victor.';
  end if;

  -- 1. tipo e unidade (só se ainda nulos)
  update mkt.projetos set tipo = 'interno', unidade = 'csm', atualizado_em = now()
   where id = 68 and tipo is null and unidade is null;

  -- 2. vínculo da oferta (só se ainda não existe)
  insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva, obs)
  select 68, 'academy', '6489980', 'mjzv4v0s', true,
         'Clínica de Miami vendida no produto 6489980 ("Encontro Internacional com Diamantes"), oferta mjzv4v0s: decisão '
         || 'do Victor Hugo (07/10/2026). Migration 20261007n.'
   where not exists (select 1 from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
                       and produto_id = '6489980' and oferta_codigo = 'mjzv4v0s');

  -- 3. Pós-condição
  if mkt_trafego.conta_hotmart(68) is distinct from 'academy' then
    raise exception '20261007n: conta_hotmart(68) não deu academy';
  end if;
  if (select count(*) from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
        and produto_id = '6489980' and oferta_codigo = 'mjzv4v0s' and oferta_exclusiva) <> 1 then
    raise exception '20261007n: vínculo exclusivo de mjzv4v0s ao projeto 68 não ficou gravado';
  end if;
end
$n$;

-- REVERSÃO (numa transação):
-- delete from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy' and produto_id = '6489980'
--    and oferta_codigo = 'mjzv4v0s';
-- update mkt.projetos set tipo = null, unidade = null, atualizado_em = now() where id = 68 and tipo_lancamento is null;

insert into pg_temp._z_out (passo, linha) select '3 depois2', (select jsonb_build_object(
  'p68', (select jsonb_build_object('tipo', tipo, 'unidade', unidade, 'sub', subarea_trafego, 'tl', tipo_lancamento, 'ini', inicio, 'fim', fim) from mkt.projetos where id = 68),
  'conta_hotmart_68', mkt_trafego.conta_hotmart(68),
  'vinculos_68', (select jsonb_agg(conta || '/' || produto_id || '/' || coalesce(oferta_codigo, '') || '/' || oferta_exclusiva) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'produtos_hotmart_total', (select count(*) from mkt_trafego.produtos_hotmart),
  'receita_68', (select jsonb_build_object('linhas', count(*), 'bruto', sum(bruto)) from mkt_trafego.receita_vendas(68)),
  'receita_total_linhas', (select count(*) from mkt_trafego.receita_vendas(null))
))::text;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select * from mkt_trafego.receita_vendas(68)' loop
    if l like '%Execution Time%' then insert into pg_temp._z_out (passo, linha) values ('x receita_vendas(68) 1', l); end if; end loop;
  for l in execute 'explain (analyze, buffers) select * from mkt_trafego.receita_vendas(68)' loop
    if l like '%Execution Time%' then insert into pg_temp._z_out (passo, linha) values ('x receita_vendas(68) 2', l); end if; end loop;
end $x$;

set local statement_timeout = '60s';
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
