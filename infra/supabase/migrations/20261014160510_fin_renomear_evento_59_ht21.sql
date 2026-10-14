-- 20261014160510: o evento 59 é o HT21 (06 a 12/04/2026)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 160000, 160100 e 160450.
--   Mexe em fin.eventos (nome de 1 linha): aplicar com o aceite do JP (dono do fin) e o ok do Maestro.
--
-- POR QUE: correção do Victor, 14/10/2026 ~15h10 (PEDIDO-ETAPA2B-respostas.md): o HT21 foi de 06 a 12/04/2026, "foi
--   onde começou o LPSG"; a captação começou em 13/03/2026 (gravada na 160450). Confere com a série do gp-operacoes
--   (serie-historica-holding-total.md: HT21 = 6 a 12/abr/26) e com a planilha "Mapeamento Histórico de Eventos"
--   (HT21 "Curso de Aplicação Prática", 06 a 12/04, confirmado). DIVERGÊNCIA registrada, sem mexer: public.ht_editions
--   e o SR_EDITIONS do dashboard-ht chamam esse período de HT22.
-- O QUE FAZ:
--   1. fin.eventos 59: nome "Holding Total (HT21/HT22, abr/2026)" -> "Holding Total (HT21)"; observação registra a
--      troca. Datas, codigo (T39/T40) e turma_hm (T39) ficam: o resolver de ofertas lê nome + código, e datas iguais =
--      funis iguais. A chave já nasce ht21-2026-04 na 160000.
--   2. public.ht_editions 21 e 22 -> evento 59 (PROPOSTA: a 21 tem o 13/03, que é a captação do HT21, e a 22 tem
--      06 a 12/04, que é o evento do HT21; pergunta no relatório). Nenhum nome do ht_editions muda.
-- O QUE NÃO FAZ: não cria HT22. A planilha "Mapeamento Histórico de Eventos" lista um "Holding Total – Edição HT22"
--   realizado (pasta "05) HT22 (T40 - ABR)", 25 ingressos), mas com a nota "NÃO IDENTIFICADO ... nenhum documento traz
--   a data própria". Sem data, não há linha: pergunta ao Victor.
-- AS 5 PERGUNTAS: escala = 1 linha em fin.eventos + 2 em ht_editions; índice = PK; frequência = única; repetição =
--   nenhuma; reversão = 20261014160510_reversao.sql. Funis: nenhuma data muda (o ensaio confere o md5 da trajetória).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select nome || '|' || inicio || '|' || fim || '|' || coalesce(chave, '') from fin.eventos where id = 59)
     is distinct from 'Holding Total (HT21/HT22, abr/2026)|2026-04-06|2026-04-12|ht21-2026-04' then
    raise exception '20261014160510: evento 59 não está como esperado (falta 160000?). Reler.';
  end if;
  if (select captacao_inicio from fin.eventos where id = 59) is distinct from date '2026-03-13' then
    raise exception '20261014160510: falta 20261014160450 (captação do HT21).';
  end if;
end
$g$;

update fin.eventos
   set nome = 'Holding Total (HT21)',
       observacao = 'Era "Holding Total (HT21/HT22, abr/2026)" com a nota "HT21 e HT22 no mesmo período; HT22: 25 ingressos". '
                    'Corrigido em 14/10/2026 (Victor): este é o HT21, evento de 06 a 12/04/2026, captação desde 13/03/2026. '
                    'public.ht_editions e o SR_EDITIONS chamam este período de HT22 (divergência registrada).'
 where id = 59
   and nome is distinct from 'Holding Total (HT21)';

update public.ht_editions
   set evento_id = 59
 where edition_number in (21, 22)
   and evento_id is distinct from 59;

do $g$
begin
  if (select count(*) from public.ht_editions where evento_id is not null) <> 12 then
    raise exception '20261014160510: esperava 12 edições do HT ligadas.';
  end if;
end
$g$;
