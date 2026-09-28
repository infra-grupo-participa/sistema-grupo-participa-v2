-- 20260928x — Catálogo de funis (eventos) 2020→2026 (João, 28/09/2026): "mapear todos os funis e o resultado desses
-- funis… o quanto a gente recebeu por cada funil, quantas pessoas pagaram, quem pagou".
-- Fonte do CALENDÁRIO: Drive › "Mapeamento Histórico de Eventos" (planilha da Jéssica, 19–25/08/2026, com a fonte de
-- cada data na coluna Observação). Fonte do DINHEIRO: o espelho da Hotmart — nada de valor é digitado aqui.
-- Só entram eventos "Realizado" com data; os "Não confirmado"/"Cancelado"/futuros ficam fora até terem data.
-- setor: 'educacao' (Holding Masters, Aurum, Serviço Diamante, Acelera, eventos do THB) × 'escritorio' (seminários de
-- Planejamento/Estruturação Patrimonial: vendem Sessão de Viabilidade → Croqui → Holding, na conta Hotmart do escritório,
-- que ainda não está no espelho — pendência da credencial).
-- venda_ate = fim do carrinho quando a planilha diz (ex.: T11 fechou 02/09; T17 fechou 02/08); senão fim + 3 dias.
create table if not exists fin.eventos (
  id bigserial primary key,
  nome text not null,
  categoria text not null,
  setor text not null check (setor in ('educacao','escritorio')),
  inicio date not null,
  fim date not null,
  venda_ate date not null,
  codigo text,
  fonte text,
  observacao text,
  unique (categoria, inicio)
);
alter table fin.eventos enable row level security;
revoke all on fin.eventos from public, anon, authenticated;

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, observacao) values
 -- 2020 — lançamentos do Curso Prático de Holding Familiar (HM antigo)
 ('II Curso Gratuito de Holding Familiar (2º CGHF)', 'jornada', 'educacao', '2020-06-01', '2020-06-07', '2020-06-10', 'Lançamento 5', 'Mapeamento Histórico', 'datas por e-mail reaproveitado — evidência indireta'),
 ('I Jornada de Holding Familiar', 'jornada', 'educacao', '2020-08-03', '2020-08-11', '2020-08-14', 'Lançamento 6', 'Mapeamento Histórico', 'carrinho do Curso Prático fechou 14/08/2020'),
 ('II Jornada — Programa de Imersão Gratuito', 'jornada', 'educacao', '2020-11-04', '2020-11-10', '2020-11-13', 'Lançamento 7', 'Mapeamento Histórico', 'carrinho 10–13/11'),
 -- 2021
 ('Jornada de Holding Familiar (Lançamento Interno, T8)', 'jornada', 'educacao', '2021-02-01', '2021-02-08', '2021-02-08', 'T8', 'Mapeamento Histórico', 'debriefing: 120 vendas, R$ 456.294,68; fim ~08/02 não confirmado'),
 ('Jornada de Holding Familiar (T9)', 'jornada', 'educacao', '2021-03-25', '2021-03-30', '2021-03-30', 'T9', 'Mapeamento Histórico', 'debriefing: 369 vendas; fim ~30/03 inferido'),
 ('Jornada de Holding Familiar (T10)', 'jornada', 'educacao', '2021-05-11', '2021-05-27', '2021-05-27', 'T10', 'Mapeamento Histórico', 'debriefing: 463 vendas, R$ 2.105.562,70'),
 ('Jornada de Holding Familiar (T11)', 'jornada', 'educacao', '2021-08-17', '2021-09-04', '2021-09-04', 'T11', 'Mapeamento Histórico', 'carrinho fechou 02/09; downsell 04/09'),
 -- 2022
 ('Jornada de Holding Familiar (T14)', 'jornada', 'educacao', '2022-01-24', '2022-01-28', '2022-01-31', 'T14', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (1ª ed. 2022)', 'seminario_marcio', 'escritorio', '2022-02-15', '2022-02-17', '2022-02-18', 'Sem-PPF.1.FEV', 'Mapeamento Histórico', 'sessões de viabilidade a partir de 17–18/02'),
 ('Jornada de Holding Familiar (T15)', 'jornada', 'educacao', '2022-03-21', '2022-03-25', '2022-03-28', 'T15', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (2ª ed. 2022)', 'seminario_marcio', 'escritorio', '2022-04-12', '2022-04-15', '2022-04-18', 'Sem-PPF.2.ABR', 'Mapeamento Histórico', null),
 ('Jornada de Holding Familiar (T16)', 'jornada', 'educacao', '2022-05-30', '2022-06-03', '2022-06-06', 'T16', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (3ª ed. 2022)', 'seminario_marcio', 'escritorio', '2022-06-21', '2022-06-24', '2022-06-27', 'Sem-PPF.3.JUN', 'Mapeamento Histórico', null),
 ('Jornada de Holding Familiar (T17)', 'jornada', 'educacao', '2022-07-25', '2022-07-30', '2022-08-02', 'T17', 'Mapeamento Histórico', 'carrinho fechou 02/08'),
 ('Seminário de Planejamento Patrimonial da Família (5ª ed. 2022)', 'seminario_marcio', 'escritorio', '2022-10-25', '2022-10-28', '2022-11-01', 'Sem-PPF.5.OUT', 'Mapeamento Histórico', 'carrinho 27/10–01/11'),
 ('Holding Total — imersão mundial (T18)', 'holding_total', 'educacao', '2022-12-03', '2022-12-04', '2022-12-07', 'T18', 'Mapeamento Histórico', 'primeira edição com o nome Holding Total'),
 -- 2023
 ('Certificação Holding Pro', 'certificacao', 'educacao', '2023-01-23', '2023-01-27', '2023-01-31', 'T19', 'Mapeamento Histórico', 'matrículas fecharam 31/01'),
 ('Seminário de Planejamento Patrimonial da Família (1ª ed. 2023)', 'seminario_marcio', 'escritorio', '2023-02-28', '2023-03-03', '2023-03-06', 'Sem-PPF.1.FEV', 'Mapeamento Histórico', null),
 ('Holding Total (HT2)', 'holding_total', 'educacao', '2023-03-31', '2023-04-02', '2023-04-05', 'T20', 'Mapeamento Histórico', null),
 ('Holding Total (HT3)', 'holding_total', 'educacao', '2023-05-19', '2023-05-21', '2023-05-24', 'T21', 'Mapeamento Histórico', null),
 ('Encontro do Time Holding Brasil (ed. 1)', 'encontro_thb', 'educacao', '2023-07-07', '2023-07-09', '2023-07-12', 'ETHB.1', 'Mapeamento Histórico', null),
 ('Holding Total (HT4)', 'holding_total', 'educacao', '2023-08-04', '2023-08-06', '2023-08-09', 'T22', 'Mapeamento Histórico', 'reagendado de 21–23/07'),
 ('Holding Total (HT5)', 'holding_total', 'educacao', '2023-09-15', '2023-09-17', '2023-09-20', 'T23', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (2ª ed. 2023)', 'seminario_marcio', 'escritorio', '2023-10-17', '2023-10-20', '2023-10-23', 'Sem-PPF.2.OUT', 'Mapeamento Histórico', null),
 ('Holding Total (HT6)', 'holding_total', 'educacao', '2023-11-10', '2023-11-12', '2023-11-15', 'T24', 'Mapeamento Histórico', null),
 ('Encontro Internacional do Diamante (Miami)', 'diamantes', 'educacao', '2023-11-20', '2023-11-24', '2023-11-24', null, 'Mapeamento Histórico', '67 presentes'),
 -- 2024
 ('Holding Total (HT7)', 'holding_total', 'educacao', '2024-01-12', '2024-01-14', '2024-01-17', 'T25', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (fev/2024)', 'seminario_marcio', 'escritorio', '2024-02-27', '2024-02-29', '2024-03-03', 'SEM FEV24', 'Mapeamento Histórico', null),
 ('Holding Total (HT8)', 'holding_total', 'educacao', '2024-03-07', '2024-03-09', '2024-03-12', 'T26', 'Mapeamento Histórico', null),
 ('Holding Total (HT9)', 'holding_total', 'educacao', '2024-05-03', '2024-05-05', '2024-05-08', 'T27', 'Mapeamento Histórico', null),
 ('Encontro do Time Holding Brasil 1 (2024)', 'encontro_thb', 'educacao', '2024-07-05', '2024-07-07', '2024-07-10', 'ETHB-1', 'Mapeamento Histórico', null),
 ('Holding Total (HT10)', 'holding_total', 'educacao', '2024-08-01', '2024-08-03', '2024-08-06', 'T28', 'Mapeamento Histórico', null),
 ('Seminário de Planejamento Patrimonial da Família (set/2024)', 'seminario_marcio', 'escritorio', '2024-09-17', '2024-09-19', '2024-09-22', 'SEM SET24', 'Mapeamento Histórico', null),
 ('Holding Total (HT11)', 'holding_total', 'educacao', '2024-11-01', '2024-11-03', '2024-11-06', 'T29', 'Mapeamento Histórico', null),
 ('Clínica de Holding Familiar (Miami Beach)', 'clinica', 'educacao', '2024-11-15', '2024-11-17', '2024-11-20', null, 'Mapeamento Histórico', null),
 ('Encontro do Time Holding Brasil 2 (2024)', 'encontro_thb', 'educacao', '2024-12-06', '2024-12-08', '2024-12-11', 'ETHB-2', 'Mapeamento Histórico', null),
 -- 2025
 ('Holding Total (HT12)', 'holding_total', 'educacao', '2025-02-07', '2025-02-09', '2025-02-12', 'T30', 'Mapeamento Histórico', null),
 ('Seminário Online de Planejamento Patrimonial (Márcio, mar/2025)', 'seminario_marcio', 'escritorio', '2025-03-18', '2025-03-20', '2025-03-24', 'SEM 1 MARCIO', 'Mapeamento Histórico', 'tira-dúvidas 21 e 24/03'),
 ('Holding Total (HT13)', 'holding_total', 'educacao', '2025-05-23', '2025-05-25', '2025-05-28', 'T31', 'Mapeamento Histórico', null),
 ('Holding Total (HT14)', 'holding_total', 'educacao', '2025-07-04', '2025-07-06', '2025-07-09', 'T32', 'Mapeamento Histórico', null),
 ('Clínica de Holding Familiar (Rio, jul/2025)', 'clinica', 'educacao', '2025-07-14', '2025-07-14', '2025-07-17', null, 'Mapeamento Histórico', 'Vogue Square, Barra da Tijuca'),
 ('Conexão Aurum (jul/2025)', 'aurum_plus', 'educacao', '2025-07-15', '2025-07-15', '2025-07-18', null, 'Mapeamento Histórico', null),
 ('Congresso do Time Holding Brasil (2025)', 'congresso', 'educacao', '2025-07-25', '2025-07-27', '2025-07-30', null, 'Mapeamento Histórico', 'online'),
 ('Seminário Online de Planejamento Patrimonial (Elaine, 2º ciclo 2025)', 'seminario_elaine', 'escritorio', '2025-08-12', '2025-08-14', '2025-08-17', 'SEM 2 ELAINE', 'Mapeamento Histórico', null),
 ('Holding Total (HT15)', 'holding_total', 'educacao', '2025-09-05', '2025-09-07', '2025-09-10', 'T33', 'Mapeamento Histórico', null),
 ('Seminário Online de Planejamento Patrimonial (Elaine, 3º ciclo 2025)', 'seminario_elaine', 'escritorio', '2025-09-23', '2025-09-25', '2025-09-28', 'SEM 3 ELAINE', 'Mapeamento Histórico', null),
 ('Holding Total (HT16)', 'holding_total', 'educacao', '2025-10-03', '2025-10-05', '2025-10-08', 'T34', 'Mapeamento Histórico', null),
 ('Programa de Residência em Holding Familiar', 'residencia', 'educacao', '2025-10-09', '2025-10-12', '2025-10-15', null, 'Mapeamento Histórico', 'presencial híbrido, Barra First Class'),
 ('Aurum+ 2025.02', 'aurum_plus', 'educacao', '2025-11-22', '2025-11-23', '2025-11-26', null, 'Mapeamento Histórico', null),
 ('Holding Total (HT17)', 'holding_total', 'educacao', '2025-11-27', '2025-11-29', '2025-12-02', 'T35', 'Mapeamento Histórico', 'deslocado pela Black Friday'),
 ('Encontro Internacional com os Diamantes (Fort Lauderdale)', 'diamantes', 'educacao', '2025-12-02', '2025-12-03', '2025-12-03', null, 'Mapeamento Histórico', null),
 ('Encontro do Time Holding Brasil 2025 (ETHB)', 'encontro_thb', 'educacao', '2025-12-14', '2025-12-16', '2025-12-19', 'ETHB 2025', 'Mapeamento Histórico', 'Grand Hyatt Barra'),
 -- 2026
 ('Holding Total (HT18)', 'holding_total', 'educacao', '2026-01-13', '2026-01-15', '2026-01-18', 'T36', 'Mapeamento Histórico', null),
 ('Seminário de Estruturação Patrimonial e de Negócios (Márcio, fev/2026)', 'seminario_marcio', 'escritorio', '2026-02-02', '2026-02-04', '2026-02-06', 'SEM 2026-1', 'Mapeamento Histórico', 'vendas até 06/02; planilha de métricas: 4 SV, 1 reembolsada'),
 ('Holding Total (HT19)', 'holding_total', 'educacao', '2026-02-24', '2026-02-26', '2026-03-01', 'T37', 'Mapeamento Histórico', null),
 ('Clínica de Holding Familiar (São Paulo)', 'clinica', 'educacao', '2026-03-09', '2026-03-11', '2026-03-14', null, 'Mapeamento Histórico', null),
 ('Holding Total (HT20)', 'holding_total', 'educacao', '2026-03-14', '2026-03-15', '2026-03-18', 'T38', 'Mapeamento Histórico', null),
 ('Workshop da Residência (SV Matadora e Croqui Estrutural)', 'workshop', 'educacao', '2026-04-02', '2026-04-02', '2026-04-05', null, 'Mapeamento Histórico', null),
 ('Holding Total (HT21/HT22, abr/2026)', 'holding_total', 'educacao', '2026-04-06', '2026-04-12', '2026-04-15', 'T39/T40', 'Mapeamento Histórico', 'HT21 e HT22 no mesmo período; HT22: 25 ingressos'),
 ('Imersão em Holding Familiar (Goiânia)', 'imersao', 'educacao', '2026-04-18', '2026-04-18', '2026-04-18', null, 'Mapeamento Histórico', 'combinada com a Clínica de Goiânia'),
 ('Clínica de Holding Familiar (Goiânia)', 'clinica', 'educacao', '2026-04-19', '2026-04-20', '2026-04-23', null, 'Mapeamento Histórico', 'métricas: 66 ingressos, 11 sinais de Aurum'),
 ('Seminário de Estruturação Patrimonial (Elaine, abr/2026)', 'seminario_elaine', 'escritorio', '2026-04-27', '2026-04-30', '2026-05-03', 'SEM 2026-2', 'Mapeamento Histórico', 'métricas: 13 SV'),
 ('Imersão Presencial Holding Sem Improviso (Porto Alegre)', 'imersao', 'educacao', '2026-06-08', '2026-06-08', '2026-06-08', null, 'Mapeamento Histórico', null),
 ('Clínica de Holding Familiar (Porto Alegre)', 'clinica', 'educacao', '2026-06-09', '2026-06-10', '2026-06-13', null, 'Mapeamento Histórico', 'métricas: 88 ingressos, 8 vendas Aurum'),
 ('Seminário de Estruturação Patrimonial (Elaine, jun/2026)', 'seminario_elaine', 'escritorio', '2026-06-15', '2026-06-17', '2026-06-23', 'SEM 2026-3', 'Mapeamento Histórico', 'carrinho fechou 23/06; métricas: 15 SV (R$ 18.000)'),
 ('Live Direto ao Ponto — base Holding Total (lançamento HM)', 'live_hm', 'educacao', '2026-06-25', '2026-06-25', '2026-06-28', null, 'Mapeamento Histórico', null),
 ('Reunião Direto ao Ponto — ex-alunos Holding Masters', 'live_hm', 'educacao', '2026-07-13', '2026-07-13', '2026-07-16', null, 'Mapeamento Histórico', 'métricas: 44 vendas'),
 ('Seminário ATM (Dra. Elaine)', 'seminario_elaine', 'escritorio', '2026-07-16', '2026-07-16', '2026-07-19', 'SEM ATM', 'Mapeamento Histórico', 'métricas: 7 SV'),
 ('Aurum+ (jul/2026)', 'aurum_plus', 'educacao', '2026-07-24', '2026-07-25', '2026-07-28', null, 'Mapeamento Histórico', null),
 ('Seminário de Estruturação Patrimonial (Elaine, jul/2026)', 'seminario_elaine', 'escritorio', '2026-07-28', '2026-07-30', '2026-08-02', 'SEM 2026-4', 'Mapeamento Histórico', 'métricas provisórias: 26 SV, 6 croquis'),
 ('Encontro do Time Holding Brasil (2026)', 'encontro_thb', 'educacao', '2026-08-04', '2026-08-06', '2026-08-09', null, 'Mapeamento Histórico', null),
 ('Curso Nacional de Formação em Holding Familiar — Turma 2026/2', 'lancamento_cnhf', 'educacao', '2026-08-24', '2026-08-26', '2026-08-28', 'CNHF', 'Mapeamento Histórico', 'carrinho abre 26/08, fecha 28/08')
on conflict (categoria, inicio) do update set nome = excluded.nome, fim = excluded.fim, venda_ate = excluded.venda_ate,
  codigo = excluded.codigo, observacao = excluded.observacao, setor = excluded.setor;
