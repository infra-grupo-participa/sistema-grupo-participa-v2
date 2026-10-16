-- 20261017050000: liga as duas ofertas do checkout do /renov à ação "THB vencidos" (chave black-thb-2026-10) no cadastro dados.dashboards.
--   Principal nv5f10zq (Renovação Holding Masters) e extra wftji6dl (Upgrade Implementação Assistida), mesmo produto L97981750T, conta academy.
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-renov-padrao). Só foi rodado o ENSAIO (begin ... rollback).
--   Ensaio: 20261017050000_ensaio.sql. Reversão: 20261017050000_reversao.sql. Detalhe e números: 20261017050000.explain.md.
--
-- POR QUE: black-thb-2026-10 está com oferta_codigo nulo. dados_atm_resumo só mostra Vendas, Receita e ROAS quando a oferta existe
--   (k.tem_oferta = d.oferta_codigo is not null), então os cards de venda ficam "aguardando oferta" mesmo com venda no checkout.
--   As duas ofertas são venda da ação (pedido do Victor, 16/10/2026): as duas têm que entrar em Vendas, Receita e ROAS.
-- O QUE FAZ (só dado, uma linha; nenhuma função, tabela, view, grant ou policy muda):
--   dados.dashboards where chave = 'black-thb-2026-10': oferta_codigo = 'nv5f10zq', ofertas_extra = {'wftji6dl'}.
-- POR QUE BASTA (corpo vivo lido em 16/10/2026): dados.transacoes(conta, oferta) monta a lista de ofertas como
--   array[oferta principal] || ofertas_extra do dashboard dessa conta+oferta e lê as duas em fin.hotmart_transacoes (e no webhook
--   cs.hotmart_eventos, para o que o sync ainda não trouxe). dados.atm_vendas_todas aplica pago, primeira parcela, vendas_desde e a
--   marcação de teste; dados_atm_resumo e dados_atm_serie_diaria leem dados.atm_vendas. Mesmo desenho da Clínica de Miami
--   (clinica-miami-2026-12: principal sju5pawn, extra mjzv4v0s), aplicado em 07/10/2026.
-- NÃO FAZ: fin.evento_ofertas e mkt_trafego.produtos_hotmart (receita do Tráfego e do Financeiro por evento) não são tocados aqui;
--   se a ação precisar entrar nessas leituras, é decisão e migration à parte (ver .explain.md).
-- COMO VOLTAR: 20261017050000_reversao.sql (devolve oferta_codigo = null e ofertas_extra = {}, só se ainda estiverem como esta migration deixou).
-- AS 5 PERGUNTAS: escala = 1 linha; as leituras novas são as vendas das 2 ofertas (índice hotmart_transacoes_oferta_idx por oferta_codigo);
--   hoje 0 transações nelas. índice = o existente serve às duas ofertas. frequência = uma vez; o efeito aparece em cada leitura do
--   dashboard (a mesma que já existe). repetição = idempotente por guarda (a premissa "oferta nula" aborta se já estiver ligada).
--   reversão = arquivo de reversão.
-- DADO PESSOAL: nenhum.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
declare r dados.dashboards;
begin
  select * into r from dados.dashboards where chave = 'black-thb-2026-10';
  if not found then
    raise exception '20261017050000: dashboard black-thb-2026-10 não existe';
  end if;
  if r.modelo is distinct from 'acao-black' or r.conta_hotmart is distinct from 'academy' or not r.ativo then
    raise exception '20261017050000: black-thb-2026-10 não é acao-black ativo da conta academy (modelo %, conta %, ativo %)', r.modelo, r.conta_hotmart, r.ativo;
  end if;
  if r.oferta_codigo is not null or coalesce(cardinality(r.ofertas_extra), 0) <> 0 then
    raise exception '20261017050000: black-thb-2026-10 já tem oferta (principal %, extras %); revisar antes de sobrescrever', r.oferta_codigo, r.ofertas_extra;
  end if;
  -- uma oferta não pode ser de dois dashboards da mesma conta: dados.transacoes acha o dashboard pela oferta principal
  if exists (select 1 from dados.dashboards x
              where x.chave <> r.chave and x.conta_hotmart = r.conta_hotmart
                and (x.oferta_codigo in ('nv5f10zq', 'wftji6dl') or x.ofertas_extra && array['nv5f10zq', 'wftji6dl'])) then
    raise exception '20261017050000: nv5f10zq ou wftji6dl já pertence a outro dashboard da conta academy';
  end if;
  -- premissa de que isto basta: dados.transacoes lê oferta principal + ofertas_extra (corpo de 20261007ma/20261013av)
  if to_regprocedure('dados.transacoes(text,text)') is null
     or (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) <> 'efbd212fc50a114fa307b4681454e1a9' then
    raise exception '20261017050000: dados.transacoes mudou desde a leitura de 16/10/2026 (md5 do corpo diferente); reconferir que ela ainda soma ofertas_extra';
  end if;
end
$g$;

update dados.dashboards
   set oferta_codigo = 'nv5f10zq', ofertas_extra = array['wftji6dl']
 where chave = 'black-thb-2026-10' and oferta_codigo is null and coalesce(cardinality(ofertas_extra), 0) = 0;

do $v$
begin
  if not exists (select 1 from dados.dashboards
                  where chave = 'black-thb-2026-10' and oferta_codigo = 'nv5f10zq' and ofertas_extra = array['wftji6dl']) then
    raise exception '20261017050000: a linha de black-thb-2026-10 não ficou com as duas ofertas';
  end if;
end
$v$;
