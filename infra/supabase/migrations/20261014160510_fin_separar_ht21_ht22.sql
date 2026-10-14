-- 20261014160510: HT21 e HT22 viram dois eventos
--
-- ⚠ BLOQUEADA: com inicio 13/03/2026 o HT21 fica antes do HT20 (14/03) na ordem dos funis e o HT20 perde os
--   161 ingressos (ensaio de impacto, foto A->B). Precisa da data do EVENTO do HT21 (não da captação) ou de outra
--   decisão do Victor/JP antes de aplicar. Ver censo-etapa2b.md.
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 160000, 160100 e 160500.
--   MEXE NO FINANCEIRO (linhas de fin.eventos): aplicar só com o aceite do dono do fin (JP) e o ok do Maestro.
--   Ensaios: 20261014160400_ensaio.sql (estrutura) e 20261014160500_ensaio_impacto.sql (leitores do fin antes e depois; o ensaio de impacto aplica a 160500 e a 160510 juntas na foto B).
--
-- POR QUE (decisões do Victor, 14/10/2026, _contexto/decisoes/2026-10-pessoa-unica.md):
--   - "separar o evento 59 em dois": hoje o 59 se chama "Holding Total (HT21/HT22, abr/2026)".
-- O QUE FAZ:
--   1. Evento 59 vira só o HT22: nome "Holding Total (HT22)", chave ht22-2026-04. Datas ficam (06 a 12/04/2026 =
--      public.ht_editions 22, sale_start_at 06/04 e sale_end_at 12/04). `codigo` (T39/T40) e turma_hm ficam: são lidos
--      pelo financeiro (resolver de ofertas). fin.acoes 105 (T39, 06/04 a 01/05) continua apontando para o 59.
--   2. Evento novo HT21: inicio 13/03/2026 e fim 05/04/2026 (public.ht_editions 21 event_start_date = 13/03;
--      dashboard-ht api/slack-report.php SR_EDITIONS 'HT 21' 2026-03-13 a 2026-04-05; Victor: 13/03 é o início da
--      captação do HT21). venda_ate = 05/04 (A CONFIRMAR: nenhuma fonte dá o fim da venda do HT21). codigo 'HT21'
--      (padrão que o fin.sincronizar_eventos_ht lê; o máximo segue HT32). turma_hm nula (fontes divergem: fin.acoes
--      89 põe a janela 14/03 a 06/04 na T38; thb_turmas liga a T38 ao HT22). chave ht21-2026-03.
--   3. public.ht_editions 21 -> HT21 novo; 22 -> evento 59.
-- O QUE NÃO FAZ: não mexe em fin.acoes nem em fin.evento_ofertas. Hoje as vendas de 14/03 a 05/04 caem na ação 89
--   (HT20/T38); separar a atribuição do HT21 é decisão do dono do fin (pergunta no relatório).
-- AS 5 PERGUNTAS: escala = 1 update + 1 insert em 88 linhas; índice = PK e chave; frequência = única; repetição =
--   nenhuma; reversão = 20261014160510_reversao.sql. Efeito nos leitores do fin medido no ensaio de impacto.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select nome || '|' || inicio || '|' || fim || '|' || coalesce(chave, '') from fin.eventos where id = 59)
     is distinct from 'Holding Total (HT21/HT22, abr/2026)|2026-04-06|2026-04-12|ht21-ht22-2026-04' then
    raise exception '20261014160510: evento 59 não está como esperado. Reler.';
  end if;
  if exists (select 1 from fin.eventos where chave = 'ht21-2026-03' or (categoria = 'holding_total' and inicio = date '2026-03-13')) then
    raise exception '20261014160510: HT21 já existe.';
  end if;
end
$g$;

update fin.eventos
   set nome = 'Holding Total (HT22)',
       chave = 'ht22-2026-04',
       observacao = 'Era "Holding Total (HT21/HT22, abr/2026)" com a nota "HT21 e HT22 no mesmo período; HT22: 25 ingressos". '
                    'Separado em 14/10/2026 por decisão do Victor: este é o HT22; o HT21 virou evento próprio.'
 where id = 59;

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, observacao, automatico, chave)
values
  ('Holding Total (HT21)', 'holding_total', 'educacao', date '2026-03-13', date '2026-04-05', date '2026-04-05', 'HT21',
   'public.ht_editions 21 + dashboard-ht SR_EDITIONS + decisão do Victor 14/10/2026',
   'Separado do evento 59 em 14/10/2026. venda_ate sem fonte (igual ao fim): confirmar.', false, 'ht21-2026-03');

update public.ht_editions h
   set evento_id = e.id
  from fin.eventos e
 where (h.edition_number, e.chave) in ((21, 'ht21-2026-03'), (22, 'ht22-2026-04'))
   and h.evento_id is distinct from e.id;

do $g$
begin
  if (select count(*) from fin.eventos) <> 89 or (select count(*) from public.ht_editions where evento_id is not null) <> 12 then
    raise exception '20261014160510: contagem final não confere (89 eventos com o ATM de setembro, 12 edições ligadas).';
  end if;
end
$g$;
