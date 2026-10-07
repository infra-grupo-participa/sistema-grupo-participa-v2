-- 20261007m: Financeiro, evento da Clínica de Miami (12/2026) e a oferta mjzv4v0s ligada a ele (não ao Encontro)
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007161247 (nome fin_evento_clinica_miami, era 20261007m), pelo aplica_sql.py aplicar
-- + insert em supabase_migrations.schema_migrations na mesma transação. md5 gravado = b608083c33a74a4bad59da0309e2f947 = este arquivo
-- antes desta troca de STATUS. Ensaio: 20261007161247_ensaio.sql. Relatório: 20261007161247.explain.md.
--
-- POR QUE
--   O Victor Hugo criou a venda da Clínica de Miami no produto Hotmart 6489980 ("Encontro Internacional com Diamantes"),
--   oferta mjzv4v0s, conta academy, e decidiu em 07/10/2026 usar assim mesmo, atribuindo à Clínica
--   (clinica-miami-2026-12, CNFMIAMI26, mkt.projetos id 68). O produto 6489980 está em fin.evento_produtos como ingresso
--   da categoria diamantes: sem vínculo explícito, o resolvedor (cron fin-oferta-evento-resolver, minuto 25) pode ligar a
--   oferta ao Encontro na primeira venda paga e o dinheiro cair no evento errado. Oferta ligada em fin.evento_ofertas
--   conta só no evento dela (índice único evento_ofertas_oferta_uq), então ligar mjzv4v0s à Clínica tira a oferta do
--   Encontro sem levar as outras 3 ofertas do produto (0rdheycy, 5o0ci6lf, qkfonqez, de 2025).
--
-- O QUE FAZ
--   1. fin.eventos: Clínica de 03 a 04/12/2026, categoria clinica, setor educacao. Nome = mkt.projetos.nome do id 68
--      (string exata, conferida na guarda). venda_ate = 2026-12-04, PROVISÓRIO (decisão 1 do Maestro, 07/10/2026,
--      reversível): muda a janela do funil da categoria clinica.
--   2. fin.evento_ofertas: mjzv4v0s -> esse evento, origem 'manual'.
--   NÃO mexe em fin.evento_produtos (6489980 continua só na categoria diamantes).
--
-- EFEITO NO FUNIL (fn_fin_funis): a Clínica nova é o próximo evento da categoria clinica depois da de Porto Alegre
--   (venda_ate 2026-06-13): o ingresso_de dela fica 2026-06-14 e ela passa a contar as vendas pagas do produto da
--   Clínica (5682989) desse dia em diante que não têm oferta ligada a outro evento. Hoje: 1 venda (contagem no explain).
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em fin.eventos (~60) e 1 em fin.evento_ofertas. índice: únicos existentes (categoria, inicio) e
--   (oferta_codigo). frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim.
--
-- IDEMPOTENTE: evento igual já existe → reaproveita; vínculo igual já existe → nada a fazer. Oferta já ligada a OUTRO
--   evento, ou evento clinica em 2026-12-03 com outro nome → aborta (não sobrescreve).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $m$
declare
  v_nome  constant text := 'Clínica Internacional de Holding Familiar';
  v_oc    constant text := 'mjzv4v0s';
  v_ev    bigint;
  v_outro record;
begin
  -- 0. Guarda de premissa
  if to_regclass('fin.eventos') is null or to_regclass('fin.evento_ofertas') is null then
    raise exception '20261007m: fin.eventos ou fin.evento_ofertas não existe';
  end if;
  if (select nome from mkt.projetos where id = 68 and etiqueta_clickup = 'clinica-miami-2026-12' and sigla = 'CNFMIAMI26')
     is distinct from v_nome then
    raise exception '20261007m: mkt.projetos 68 não é mais a Clínica "%". Conferir.', v_nome;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'fin.evento_ofertas'::regclass and contype = 'c'
                  and pg_get_constraintdef(oid) like '%''manual''::text%') then
    raise exception '20261007m: origem ''manual'' não está mais no CHECK de fin.evento_ofertas';
  end if;
  if exists (select 1 from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03' and nome <> v_nome) then
    raise exception '20261007m: já existe evento clinica em 2026-12-03 com outro nome. Conferir com o Victor.';
  end if;
  select eo.evento_id, e.nome, e.categoria, eo.origem into v_outro
    from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id
   where eo.oferta_codigo = v_oc;
  if found and not (v_outro.categoria = 'clinica' and v_outro.nome = v_nome) then
    raise exception '20261007m: a oferta % já está ligada ao evento % "%" (%, origem %). Não sobrescrevo: decidir com o Victor.',
      v_oc, v_outro.evento_id, v_outro.nome, v_outro.categoria, v_outro.origem;
  end if;

  -- 1. Evento (só se ainda não existe)
  insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, fonte, observacao)
  select v_nome, 'clinica', 'educacao', date '2026-12-03', date '2026-12-04', date '2026-12-04',
         'mkt.projetos CNFMIAMI26 (clinica-miami-2026-12), decisão do Victor Hugo 07/10/2026',
         'Clínica de Miami (03 e 04/12/2026). Vendida no produto 6489980 "Encontro Internacional com Diamantes", oferta '
         || 'mjzv4v0s, conta academy (produto criado errado na Hotmart; o Victor decidiu usar assim e atribuir à Clínica). '
         || 'venda_ate 2026-12-04 PROVISÓRIO. Migration 20261007m.'
   where not exists (select 1 from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03');
  select id into v_ev from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03' and nome = v_nome;

  -- 2. Vínculo da oferta (só se ainda não existe)
  insert into fin.evento_ofertas (evento_id, oferta_codigo, origem, observacao)
  select v_ev, v_oc, 'manual',
         'Oferta da Clínica de Miami no produto 6489980 (que é ingresso da categoria diamantes): ligada à Clínica por decisão '
         || 'do Victor Hugo (07/10/2026). Migration 20261007m.'
   where not exists (select 1 from fin.evento_ofertas where oferta_codigo = v_oc);

  -- 3. Pós-condição
  if (select count(*) from fin.evento_ofertas where oferta_codigo = v_oc and evento_id = v_ev) <> 1 then
    raise exception '20261007m: vínculo de % ao evento % não ficou gravado', v_oc, v_ev;
  end if;
  if (select count(*) from fin.eventos where id = v_ev and venda_ate = date '2026-12-04' and fim = date '2026-12-04'
        and setor = 'educacao') <> 1 then
    raise exception '20261007m: evento % com datas/setor diferentes do esperado', v_ev;
  end if;
  if exists (select 1 from fin.evento_produtos where categoria = 'clinica' and produto_id::text = '6489980') then
    raise exception '20261007m: 6489980 apareceu na categoria clinica (não pode: levaria as 3 ofertas do Encontro)';
  end if;
end
$m$;

-- REVERSÃO (numa transação; antes, conferir que nenhuma venda paga de mjzv4v0s depende do vínculo em relatório fechado):
-- delete from fin.evento_ofertas where oferta_codigo = 'mjzv4v0s'
--    and evento_id = (select id from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03');
-- delete from fin.eventos where categoria = 'clinica' and inicio = date '2026-12-03'
--    and nome = 'Clínica Internacional de Holding Familiar'
--    and not exists (select 1 from fin.evento_ofertas eo where eo.evento_id = fin.eventos.id);
