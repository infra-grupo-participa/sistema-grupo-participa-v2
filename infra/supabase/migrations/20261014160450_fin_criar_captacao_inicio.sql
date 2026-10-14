-- 20261014160450: início da captação de cada evento, separado do dia do evento (fin.eventos.captacao_inicio)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014160000.
--   Mexe em fin.eventos (coluna nova e 1 linha): aplicar só com o aceite do JP (dono do fin) e o ok do Maestro.
--   Substitui a antiga 160600 (HT20 com inicio 01/01), descartada: no ensaio de impacto ela zerava os ingressos do HT18
--   nos funis do financeiro, porque `inicio` é o dia do evento e os funis ordenam por ele.
--
-- POR QUE: decisão do Victor, 14/10/2026 (censo-etapa2b.md, respostas): "HT20 começa em 01/01/2026" e "13/03 é o início
--   da captação do HT21" são datas de CAPTAÇÃO. Ficam em coluna própria; `inicio` continua sendo o dia do evento.
-- O QUE FAZ: coluna fin.eventos.captacao_inicio (date, nula, sem default) e HT20 (evento 57) = 01/01/2026
--   (fonte: public.ht_editions 20, event_start_date). O HT21 (13/03/2026) recebe a data na 20261014160510, quando o
--   evento existir. Nenhum leitor do fin lê a coluna: nenhum número muda (provado no ensaio estrutural).
-- AS 5 PERGUNTAS: escala = 87 linhas, 1 preenchida; índice = nenhum (ninguém filtra por ela); frequência = única;
--   repetição = nenhuma; reversão = 20261014160450_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'captacao_inicio') then
    raise exception '20261014160450: fin.eventos.captacao_inicio já existe.';
  end if;
  if (select nome || '|' || inicio from fin.eventos where id = 57) is distinct from 'Holding Total (HT20)|2026-03-14' then
    raise exception '20261014160450: evento 57 não está como esperado. Reler.';
  end if;
end
$g$;

alter table fin.eventos add column captacao_inicio date;
comment on column fin.eventos.captacao_inicio is 'Início da captação do evento (não é o dia do evento: esse é `inicio`, que os funis usam para ordenar). '
  'Decisão do Victor, 14/10/2026.';
update fin.eventos set captacao_inicio = date '2026-01-01' where id = 57 and captacao_inicio is distinct from date '2026-01-01';
