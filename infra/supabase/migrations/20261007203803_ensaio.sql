-- Ensaio de 20261007ma (oferta nova da Clínica de Miami): fotos como equipe antes/depois, 2 passadas, rollback.
-- Transação desfeita: nada persiste.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated; grant all on sequence pg_temp._z_out_em_seq to authenticated;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('oferta', r.oferta_codigo, 'vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0),
  'evento_ofertas', (select jsonb_agg(eo.oferta_codigo || '->' || e.id || ':' || e.categoria order by 1) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s')),
  'produtos_hotmart_68', (select jsonb_agg(produto_id || '/' || oferta_codigo || '/' || oferta_exclusiva order by 1) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'dashboard', (select to_jsonb(d) - 'criado_em' from dados.dashboards d where chave = 'clinica-miami-2026-12'),
  'receita_68', (select count(*) from mkt_trafego.receita_vendas(68)),
  'encontro_tem_oferta', (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria <> 'clinica')
))::text;
select set_config('request.jwt.claims', '{}', true);

-- ===== PASSADA 1 =====
-- 20261007ma: Clínica de Miami, venda na oferta NOVA sju5pawn do produto da Clínica (5682989), além da oferta antiga
-- mjzv4v0s (produto 6489980). Dashboard, Tráfego e Financeiro passam a contar as duas, sem contar nada duas vezes.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007ma_ensaio.sql (2 passadas, provas, rollback). Relatório: 20261007ma.explain.md.
--
-- POR QUE
--   O Victor Hugo criou em 07/10/2026 uma oferta nova num produto que é de fato da Clínica (checkout
--   pay.hotmart.com/B100244104O?off=sju5pawn). Provado pela API da Hotmart (hotmart-sync {"catalogo": true}, 07/10
--   20:34 UTC, gravado em fin.ofertas): oferta sju5pawn "Clínica de Holding Familiar - Miami", produto 5682989
--   "Clínica de Holding Familiar" (ACTIVE, família EVENTOS), conta academy, 5014.2 BRL, pagamento único.
--   A oferta antiga mjzv4v0s (produto 6489980 "Encontro Internacional com Diamantes") continua da Clínica: tem 1 pedido.
--
-- O QUE FAZ
--   1. fin.evento_ofertas: sju5pawn → evento 101 "Clínica Internacional de Holding Familiar" (clinica, 03 a 04/12/2026),
--      origem manual. mjzv4v0s continua no 101. O produto 5682989 já é ingresso da categoria clinica em
--      fin.evento_produtos (nada a mudar). Cada transação tem uma oferta só: nada conta duas vezes; o Encontro não ganha
--      nenhuma das duas.
--   2. mkt_trafego.produtos_hotmart: projeto 68 + academy + 5682989 + sju5pawn, oferta exclusiva (nível 1 da receita do
--      Tráfego). O vínculo antigo (6489980 + mjzv4v0s) fica.
--   3. dados.dashboards ganha a coluna ofertas_extra text[] (padrão vazio). A Clínica passa a ter oferta_codigo =
--      sju5pawn (a principal, que a tela mostra) e ofertas_extra = {mjzv4v0s}.
--   4. dados.transacoes (corpo vivo + 1 mudança): lê a oferta principal E as ofertas_extra do dashboard dessa oferta.
--      As 5 funções dados_presencial_* não mudam (nem assinatura, nem colunas, nem grants).
--   Sem GRANT, RLS nem policy.
--
-- AS 5 PERGUNTAS
--   escala: 2 linhas de vínculo, 1 coluna, 1 função. índice: hotmart_transacoes_oferta_idx serve às duas ofertas.
--   frequência: igual à de hoje. repetição: nenhuma. reversão: bloco REVERSÃO / rollback-oferta-nova.sql.
--
-- IDEMPOTENTE: inserts com where not exists; coluna if not exists; o corpo da função só é refeito se ainda for o vivo.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas
do $g$
declare v_ev bigint;
begin
  if not exists (select 1 from fin.ofertas where oferta_codigo = 'sju5pawn' and produto_id = '5682989') then
    raise exception '20261007ma: a oferta sju5pawn do produto 5682989 não está em fin.ofertas (rodar hotmart-sync catálogo)';
  end if;
  if not exists (select 1 from fin.produtos where produto_id = '5682989' and conta = 'academy') then
    raise exception '20261007ma: produto 5682989 não é da conta academy em fin.produtos';
  end if;
  select id into v_ev from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03'
     and nome = 'Clínica Internacional de Holding Familiar';
  if v_ev is null then raise exception '20261007ma: evento da Clínica de Miami (03/12/2026) não existe'; end if;
  if exists (select 1 from fin.evento_ofertas where oferta_codigo = 'sju5pawn' and evento_id <> v_ev) then
    raise exception '20261007ma: sju5pawn já está ligada a outro evento. Não sobrescrevo.';
  end if;
  if not exists (select 1 from fin.evento_ofertas where oferta_codigo = 'mjzv4v0s' and evento_id = v_ev) then
    raise exception '20261007ma: mjzv4v0s não está mais ligada à Clínica. Conferir antes.';
  end if;
  if exists (select 1 from mkt_trafego.produtos_hotmart where conta = 'academy' and oferta_codigo = 'sju5pawn'
               and oferta_exclusiva and projeto_id <> 68) then
    raise exception '20261007ma: sju5pawn já é exclusiva de outro projeto';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) <> 'bf26b0b37bb5302e42aa01df040a523a'
     and (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) !~ 'ofertas_extra' then
    raise exception '20261007ma: corpo vivo de dados.transacoes mudou. Reler.';
  end if;
end
$g$;

-- 1. Financeiro: a oferta nova na Clínica
insert into fin.evento_ofertas (evento_id, oferta_codigo, origem, observacao)
select e.id, 'sju5pawn', 'manual',
       'Oferta nova da Clínica de Miami no produto 5682989 (Clínica de Holding Familiar), criada pelo Victor Hugo em '
       || '07/10/2026; a mjzv4v0s (produto 6489980) continua neste evento. Migration 20261007ma.'
  from fin.eventos e
 where e.categoria = 'clinica' and e.inicio = date '2026-12-03' and e.nome = 'Clínica Internacional de Holding Familiar'
   and not exists (select 1 from fin.evento_ofertas where oferta_codigo = 'sju5pawn');

-- 2. Tráfego: oferta exclusiva do projeto 68
insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva, obs)
select 68, 'academy', '5682989', 'sju5pawn', true,
       'Oferta nova da Clínica de Miami (produto da Clínica), 07/10/2026. Migration 20261007ma.'
 where not exists (select 1 from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
                     and produto_id = '5682989' and oferta_codigo = 'sju5pawn');

-- 3. Dashboard: oferta principal nova + a antiga como extra
alter table dados.dashboards add column if not exists ofertas_extra text[] not null default '{}';
comment on column dados.dashboards.ofertas_extra is
  'Outras ofertas do mesmo evento, na mesma conta, somadas à oferta_codigo pelas funções dados_presencial_* (20261007ma).';
update dados.dashboards set oferta_codigo = 'sju5pawn', ofertas_extra = array['mjzv4v0s']
 where chave = 'clinica-miami-2026-12' and (oferta_codigo, ofertas_extra) is distinct from ('sju5pawn', array['mjzv4v0s']);

-- 4. dados.transacoes lê a principal e as extras (corpo vivo, corpo anterior guardado)
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007ma'
  from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure
on conflict do nothing;
do $t$
declare v_def text;
begin
  if (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) ~ 'ofertas_extra' then
    return;  -- já aplicada
  end if;
  v_def := pg_get_functiondef('dados.transacoes(text,text)'::regprocedure);
  if position('where t.oferta_codigo = p_oferta;' in v_def) = 0 then
    raise exception '20261007ma: dados.transacoes não tem mais o filtro esperado';
  end if;
  v_def := replace(v_def, 'where t.oferta_codigo = p_oferta;',
    'where t.oferta_codigo = p_oferta
      or t.oferta_codigo = any (coalesce((select d.ofertas_extra from dados.dashboards d   -- 20261007ma: ofertas_extra
                                          where d.conta_hotmart = p_conta and d.oferta_codigo = p_oferta and d.ativo
                                          limit 1), ''{}''::text[]));');
  execute v_def;
end
$t$;

-- 5. Pós-condição
do $c$
begin
  if (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id
       where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria = 'clinica' and e.inicio = date '2026-12-03') <> 2 then
    raise exception '20261007ma: as duas ofertas têm de estar na Clínica de Miami';
  end if;
  if mkt_trafego.conta_hotmart(68) is distinct from 'academy' then
    raise exception '20261007ma: conta do projeto 68 mudou';
  end if;
  if (select oferta_codigo from dados.dashboards where chave = 'clinica-miami-2026-12') <> 'sju5pawn' then
    raise exception '20261007ma: dashboard não ficou na oferta nova';
  end if;
  if (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) !~ 'ofertas_extra' then
    raise exception '20261007ma: dados.transacoes não lê as ofertas extras';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/clinica-miami/rollback-oferta-nova.sql (cérebro), ensaiado em 20261007ma_ensaio.sql.

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois1', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('oferta', r.oferta_codigo, 'vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0),
  'evento_ofertas', (select jsonb_agg(eo.oferta_codigo || '->' || e.id || ':' || e.categoria order by 1) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s')),
  'produtos_hotmart_68', (select jsonb_agg(produto_id || '/' || oferta_codigo || '/' || oferta_exclusiva order by 1) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'dashboard', (select to_jsonb(d) - 'criado_em' from dados.dashboards d where chave = 'clinica-miami-2026-12'),
  'receita_68', (select count(*) from mkt_trafego.receita_vendas(68)),
  'encontro_tem_oferta', (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria <> 'clinica')
))::text;
select set_config('request.jwt.claims', '{}', true);

-- ===== PASSADA 2 =====
-- 20261007ma: Clínica de Miami, venda na oferta NOVA sju5pawn do produto da Clínica (5682989), além da oferta antiga
-- mjzv4v0s (produto 6489980). Dashboard, Tráfego e Financeiro passam a contar as duas, sem contar nada duas vezes.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007ma_ensaio.sql (2 passadas, provas, rollback). Relatório: 20261007ma.explain.md.
--
-- POR QUE
--   O Victor Hugo criou em 07/10/2026 uma oferta nova num produto que é de fato da Clínica (checkout
--   pay.hotmart.com/B100244104O?off=sju5pawn). Provado pela API da Hotmart (hotmart-sync {"catalogo": true}, 07/10
--   20:34 UTC, gravado em fin.ofertas): oferta sju5pawn "Clínica de Holding Familiar - Miami", produto 5682989
--   "Clínica de Holding Familiar" (ACTIVE, família EVENTOS), conta academy, 5014.2 BRL, pagamento único.
--   A oferta antiga mjzv4v0s (produto 6489980 "Encontro Internacional com Diamantes") continua da Clínica: tem 1 pedido.
--
-- O QUE FAZ
--   1. fin.evento_ofertas: sju5pawn → evento 101 "Clínica Internacional de Holding Familiar" (clinica, 03 a 04/12/2026),
--      origem manual. mjzv4v0s continua no 101. O produto 5682989 já é ingresso da categoria clinica em
--      fin.evento_produtos (nada a mudar). Cada transação tem uma oferta só: nada conta duas vezes; o Encontro não ganha
--      nenhuma das duas.
--   2. mkt_trafego.produtos_hotmart: projeto 68 + academy + 5682989 + sju5pawn, oferta exclusiva (nível 1 da receita do
--      Tráfego). O vínculo antigo (6489980 + mjzv4v0s) fica.
--   3. dados.dashboards ganha a coluna ofertas_extra text[] (padrão vazio). A Clínica passa a ter oferta_codigo =
--      sju5pawn (a principal, que a tela mostra) e ofertas_extra = {mjzv4v0s}.
--   4. dados.transacoes (corpo vivo + 1 mudança): lê a oferta principal E as ofertas_extra do dashboard dessa oferta.
--      As 5 funções dados_presencial_* não mudam (nem assinatura, nem colunas, nem grants).
--   Sem GRANT, RLS nem policy.
--
-- AS 5 PERGUNTAS
--   escala: 2 linhas de vínculo, 1 coluna, 1 função. índice: hotmart_transacoes_oferta_idx serve às duas ofertas.
--   frequência: igual à de hoje. repetição: nenhuma. reversão: bloco REVERSÃO / rollback-oferta-nova.sql.
--
-- IDEMPOTENTE: inserts com where not exists; coluna if not exists; o corpo da função só é refeito se ainda for o vivo.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas
do $g$
declare v_ev bigint;
begin
  if not exists (select 1 from fin.ofertas where oferta_codigo = 'sju5pawn' and produto_id = '5682989') then
    raise exception '20261007ma: a oferta sju5pawn do produto 5682989 não está em fin.ofertas (rodar hotmart-sync catálogo)';
  end if;
  if not exists (select 1 from fin.produtos where produto_id = '5682989' and conta = 'academy') then
    raise exception '20261007ma: produto 5682989 não é da conta academy em fin.produtos';
  end if;
  select id into v_ev from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03'
     and nome = 'Clínica Internacional de Holding Familiar';
  if v_ev is null then raise exception '20261007ma: evento da Clínica de Miami (03/12/2026) não existe'; end if;
  if exists (select 1 from fin.evento_ofertas where oferta_codigo = 'sju5pawn' and evento_id <> v_ev) then
    raise exception '20261007ma: sju5pawn já está ligada a outro evento. Não sobrescrevo.';
  end if;
  if not exists (select 1 from fin.evento_ofertas where oferta_codigo = 'mjzv4v0s' and evento_id = v_ev) then
    raise exception '20261007ma: mjzv4v0s não está mais ligada à Clínica. Conferir antes.';
  end if;
  if exists (select 1 from mkt_trafego.produtos_hotmart where conta = 'academy' and oferta_codigo = 'sju5pawn'
               and oferta_exclusiva and projeto_id <> 68) then
    raise exception '20261007ma: sju5pawn já é exclusiva de outro projeto';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) <> 'bf26b0b37bb5302e42aa01df040a523a'
     and (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) !~ 'ofertas_extra' then
    raise exception '20261007ma: corpo vivo de dados.transacoes mudou. Reler.';
  end if;
end
$g$;

-- 1. Financeiro: a oferta nova na Clínica
insert into fin.evento_ofertas (evento_id, oferta_codigo, origem, observacao)
select e.id, 'sju5pawn', 'manual',
       'Oferta nova da Clínica de Miami no produto 5682989 (Clínica de Holding Familiar), criada pelo Victor Hugo em '
       || '07/10/2026; a mjzv4v0s (produto 6489980) continua neste evento. Migration 20261007ma.'
  from fin.eventos e
 where e.categoria = 'clinica' and e.inicio = date '2026-12-03' and e.nome = 'Clínica Internacional de Holding Familiar'
   and not exists (select 1 from fin.evento_ofertas where oferta_codigo = 'sju5pawn');

-- 2. Tráfego: oferta exclusiva do projeto 68
insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva, obs)
select 68, 'academy', '5682989', 'sju5pawn', true,
       'Oferta nova da Clínica de Miami (produto da Clínica), 07/10/2026. Migration 20261007ma.'
 where not exists (select 1 from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy'
                     and produto_id = '5682989' and oferta_codigo = 'sju5pawn');

-- 3. Dashboard: oferta principal nova + a antiga como extra
alter table dados.dashboards add column if not exists ofertas_extra text[] not null default '{}';
comment on column dados.dashboards.ofertas_extra is
  'Outras ofertas do mesmo evento, na mesma conta, somadas à oferta_codigo pelas funções dados_presencial_* (20261007ma).';
update dados.dashboards set oferta_codigo = 'sju5pawn', ofertas_extra = array['mjzv4v0s']
 where chave = 'clinica-miami-2026-12' and (oferta_codigo, ofertas_extra) is distinct from ('sju5pawn', array['mjzv4v0s']);

-- 4. dados.transacoes lê a principal e as extras (corpo vivo, corpo anterior guardado)
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007ma'
  from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure
on conflict do nothing;
do $t$
declare v_def text;
begin
  if (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) ~ 'ofertas_extra' then
    return;  -- já aplicada
  end if;
  v_def := pg_get_functiondef('dados.transacoes(text,text)'::regprocedure);
  if position('where t.oferta_codigo = p_oferta;' in v_def) = 0 then
    raise exception '20261007ma: dados.transacoes não tem mais o filtro esperado';
  end if;
  v_def := replace(v_def, 'where t.oferta_codigo = p_oferta;',
    'where t.oferta_codigo = p_oferta
      or t.oferta_codigo = any (coalesce((select d.ofertas_extra from dados.dashboards d   -- 20261007ma: ofertas_extra
                                          where d.conta_hotmart = p_conta and d.oferta_codigo = p_oferta and d.ativo
                                          limit 1), ''{}''::text[]));');
  execute v_def;
end
$t$;

-- 5. Pós-condição
do $c$
begin
  if (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id
       where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria = 'clinica' and e.inicio = date '2026-12-03') <> 2 then
    raise exception '20261007ma: as duas ofertas têm de estar na Clínica de Miami';
  end if;
  if mkt_trafego.conta_hotmart(68) is distinct from 'academy' then
    raise exception '20261007ma: conta do projeto 68 mudou';
  end if;
  if (select oferta_codigo from dados.dashboards where chave = 'clinica-miami-2026-12') <> 'sju5pawn' then
    raise exception '20261007ma: dashboard não ficou na oferta nova';
  end if;
  if (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) !~ 'ofertas_extra' then
    raise exception '20261007ma: dados.transacoes não lê as ofertas extras';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/clinica-miami/rollback-oferta-nova.sql (cérebro), ensaiado em 20261007ma_ensaio.sql.

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '3 depois2', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('oferta', r.oferta_codigo, 'vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0),
  'evento_ofertas', (select jsonb_agg(eo.oferta_codigo || '->' || e.id || ':' || e.categoria order by 1) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s')),
  'produtos_hotmart_68', (select jsonb_agg(produto_id || '/' || oferta_codigo || '/' || oferta_exclusiva order by 1) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'dashboard', (select to_jsonb(d) - 'criado_em' from dados.dashboards d where chave = 'clinica-miami-2026-12'),
  'receita_68', (select count(*) from mkt_trafego.receita_vendas(68)),
  'encontro_tem_oferta', (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria <> 'clinica')
))::text;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'resolvedor simulado sju5pawn', coalesce((select jsonb_agg(jsonb_build_object('decisao', r.decisao, 'sinal', r.sinal))::text from fin.resolver_ofertas_eventos(false, 45, array['sju5pawn'], 'academy') r), '[]');

-- ===== ROLLBACK =====
-- Rollback da migration 20261007ma_clinica_miami_oferta_nova. Numa transação (aplica_sql.py aplicar).
-- Antes, conferir se já há venda paga da sju5pawn: tirar o vínculo deixa essa venda sem evento no Financeiro e fora do
-- dashboard (os dados da Hotmart continuam em fin.hotmart_transacoes).
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $v$ declare r record; begin
  for r in select * from acesso.corpo_antes where migration = '20261007ma' and tipo = 'funcao' loop execute r.definicao; end loop;
end $v$;
update dados.dashboards set oferta_codigo = 'mjzv4v0s', ofertas_extra = '{}' where chave = 'clinica-miami-2026-12';
alter table dados.dashboards drop column if exists ofertas_extra;
delete from mkt_trafego.produtos_hotmart where projeto_id = 68 and conta = 'academy' and produto_id = '5682989' and oferta_codigo = 'sju5pawn';
delete from fin.evento_ofertas where oferta_codigo = 'sju5pawn'
   and evento_id = (select id from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03');
do $c$ begin
  if (select prosrc from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) ~ 'ofertas_extra' then
    raise exception 'rollback oferta nova: dados.transacoes não voltou';
  end if;
end $c$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '4 depois do rollback', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('oferta', r.oferta_codigo, 'vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0),
  'evento_ofertas', (select jsonb_agg(eo.oferta_codigo || '->' || e.id || ':' || e.categoria order by 1) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s')),
  'produtos_hotmart_68', (select jsonb_agg(produto_id || '/' || oferta_codigo || '/' || oferta_exclusiva order by 1) from mkt_trafego.produtos_hotmart where projeto_id = 68),
  'dashboard', (select to_jsonb(d) - 'criado_em' from dados.dashboards d where chave = 'clinica-miami-2026-12'),
  'receita_68', (select count(*) from mkt_trafego.receita_vendas(68)),
  'encontro_tem_oferta', (select count(*) from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id where eo.oferta_codigo in ('sju5pawn', 'mjzv4v0s') and e.categoria <> 'clinica')
))::text;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'rollback volta igual', ((select linha from pg_temp._z_out where passo='1 antes') = (select linha from pg_temp._z_out where passo='4 depois do rollback'))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
