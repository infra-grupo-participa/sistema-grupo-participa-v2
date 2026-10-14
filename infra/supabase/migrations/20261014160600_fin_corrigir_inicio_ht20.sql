-- 20261014160600: HT20 começa em 01/01/2026 (evento 57)
--
-- ⚠ NÃO RECOMENDADA COMO ESTÁ: os funis do financeiro ordenam por `inicio`. Com 01/01 o HT20 passa à frente do HT18 e
--   do HT19; no ensaio de impacto o HT18 cai de 365 ingressos para 0 e o HT20 sobe de 0 para 769. Ver censo-etapa2b.md.
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 160000.
--   MEXE NO RESULTADO DO FINANCEIRO: ver o ensaio de impacto (20261014160500_ensaio_impacto.sql) e o relatório
--   censo-etapa2b.md. Aplicar só com o aceite do dono do fin (JP).
--
-- POR QUE: decisão do Victor, 14/10/2026: "HT20 começa em 01/01/2026. O 13/03 do evento 57 é o início da captação do
--   HT21". Fonte do 01/01: public.ht_editions 20 (event_start_date 2026-01-01).
-- O QUE FAZ: fin.eventos 57: inicio 14/03/2026 -> 01/01/2026; chave ht20-2026-03 -> ht20-2026-01 (a chave usa o mês
--   do início). fim (15/03) e venda_ate (18/03) ficam.
-- EFEITO CONHECIDO: fn_fin_funis e fin.trajetoria_nucleo ordenam os eventos da categoria por `inicio` e abrem a janela de
--   ingresso de cada um no fim da venda do anterior (lag(venda_ate) + 1). Com o HT20 começando antes do HT18 (13/01) e
--   do HT19 (24/02), a ordem dos três muda e as janelas também. Números no relatório.
-- AS 5 PERGUNTAS: escala = 1 linha; índice = PK; frequência = única; repetição = nenhuma;
--   reversão = 20261014160600_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select inicio || '|' || chave from fin.eventos where id = 57) is distinct from '2026-03-14|ht20-2026-03' then
    raise exception '20261014160600: evento 57 não está como esperado. Reler.';
  end if;
end
$g$;

update fin.eventos
   set inicio = date '2026-01-01',
       chave = 'ht20-2026-01',
       observacao = concat_ws(' ', nullif(observacao, ''), 'Início corrigido de 14/03 para 01/01/2026 em 14/10/2026 (decisão do Victor; fonte public.ht_editions 20).')
 where id = 57;
