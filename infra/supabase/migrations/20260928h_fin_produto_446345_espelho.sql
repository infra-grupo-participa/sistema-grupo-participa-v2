-- 20260928h — Espelhar o "Curso Prático de Holding Familiar" (446345). Apurado em 27/09/2026.
-- O João estranhou "só R$ 10 mi de HM desde 2021". Na API da Hotmart, o 446345 vendeu R$ 31,0 mi líquidos
-- entre 2019 e 2024 e parou quando o "Holding Masters" (5064314) começou, em 02/2025. Em 2024 o ticket era de
-- ~R$ 13 mil em 12x, o mesmo patamar do HM.
-- Ele entra no espelho com a família 'A_CLASSIFICAR': nenhuma tela lê essa família, então nenhum total muda
-- até o João decidir se ele é HM. Para reverter: update fin.produtos set sincroniza = false.
insert into fin.produtos (produto_id, nome, familia, papel, sincroniza, nota)
values ('446345', 'Curso Prático de Holding Familiar', 'A_CLASSIFICAR', 'legado', true,
        'Candidato a HM antigo (2019–2024, ticket ~13k). Aguarda decisão do João.')
on conflict (produto_id) do nothing;

-- A história inteira em janelas de 60 dias. A 1ª venda é de 2019.
insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
select '446345', g::date, least(g::date + 59, (now() at time zone 'America/Sao_Paulo')::date), 'backfill'
  from generate_series(date '2019-01-01', (now() at time zone 'America/Sao_Paulo')::date, interval '60 days') g
on conflict do nothing;
