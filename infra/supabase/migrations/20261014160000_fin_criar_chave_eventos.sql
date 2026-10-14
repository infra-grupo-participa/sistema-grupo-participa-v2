-- 20261014160000: chave da casa (nome-curto-aaaa-mm) no catálogo oficial de eventos, fin.eventos
--
-- STATUS: NÃO APLICADA. Escrita pelo terminal Censo (pessoa única, ETAPA 2) em 14/10/2026. Aplicar só com o ok do
--   Maestro. Ensaio: 20261014160000_ensaio.sql (cobre 160000, 160100 e 160200). Detalhe: 20261014160000.explain.md.
--
-- POR QUE: decisão do Victor de 14/10/2026 (Projetos/sistema-unico/pessoa-unica/PLANO.md, decisão 3; item C-03 do
--   plano de ação do banco): fin.eventos é o catálogo oficial de eventos e ganha a chave única da casa no padrão
--   nome-curto-aaaa-mm, a mesma string usada no ClickUp, no Slack, no Drive e no utm_campaign.
-- O QUE FAZ:
--   1. coluna fin.eventos.chave (text, nullable) com CHECK do padrão;
--   2. índice único na chave (a tabela tem 87 linhas: lock instantâneo, por isso dentro da transação e sem CONCURRENTLY);
--   3. preenche as 87 linhas. Regra (aaaa-mm = mês de `inicio`):
--      holding_total = htN (N do nome "(HTn)"); jornada = jornada-<turma_hm>; seminario_marcio = sem-marcio;
--      seminario_elaine = sem-elaine; encontro_thb = ethb; diamantes; clinica; imersao; aurum-plus; congresso-thb;
--      certificacao-holding-pro; encontro-acelera; cnhf; residencia; workshop-residencia.
--      Casos especiais: 16 ht-imersao-mundial, 85 e 88 ht-atm, 66 live-hm, 67 reuniao-hm-ex-alunos.
--      59 = ht21-2026-04 (correção do Victor, 14/10/2026: o 59, de 06 a 12/04, é o HT21).
--      Chave que já existe em outro catálogo é reaproveitada (cada fato tem um endereço só):
--      101 = clinica-miami-2026-12 (mkt.projetos.etiqueta_clickup do CNFMIAMI26), 68 = atm-1-2026-07
--      (dados.edicoes_historico). A lista é PROPOSTA ao Victor, dono do padrão de dados: ele aprova antes de aplicar.
-- O QUE NÃO FAZ: não mexe em `codigo` (o fin.resolver_ofertas_eventos usa nome + codigo para achar evento de oferta
--   e o fin.sincronizar_eventos_ht lê o padrão HTn: mudar codigo muda o financeiro). Não cria evento novo.
-- AS 5 PERGUNTAS: escala = 87 linhas, cresce ~2 por mês; índice = o único da chave; frequência = única (linha nova
--   nasce com chave nula até alguém preencher; ver pendência no explain); repetição = nenhuma; reversão =
--   20261014160000_reversao.sql (drop do índice e da coluna).
-- LEITORES: 16 funções leem fin.eventos (catálogo pg_proc); 5 usam e.* em CTE. O ensaio confere que a assinatura de
--   retorno delas não muda e que fin.trajetoria_nucleo devolve o mesmo resultado antes e depois.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select count(*) from fin.eventos) <> 87 then
    raise exception '20261014160000: fin.eventos não tem 87 linhas. Reler e refazer a lista de chaves.';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'chave') then
    raise exception '20261014160000: fin.eventos.chave já existe.';
  end if;
end
$g$;

alter table fin.eventos
  add column chave text
  constraint eventos_chave_padrao_check check (chave is null or chave ~ '^[a-z0-9]+(-[a-z0-9]+)*-[0-9]{4}-(0[1-9]|1[0-2])$');

create unique index eventos_chave_key on fin.eventos (chave);

comment on column fin.eventos.chave is 'Chave da casa nome-curto-aaaa-mm (decisão do Victor, 14/10/2026). Mesma string no ClickUp, Slack, Drive e utm_campaign. '
  'Única. Nula enquanto ninguém preencher (linha automática do fin.sincronizar_eventos_ht nasce sem chave).';

update fin.eventos e
   set chave = v.chave
  from (values
    (1, 'jornada-t5-2020-06'),
    (2, 'jornada-t6-2020-08'),
    (3, 'jornada-t7-2020-11'),
    (4, 'jornada-t8-2021-02'),
    (5, 'jornada-t9-2021-03'),
    (6, 'jornada-t10-2021-05'),
    (7, 'jornada-t11-2021-08'),
    (8, 'jornada-t14-2022-01'),
    (9, 'sem-marcio-2022-02'),
    (10, 'jornada-t15-2022-03'),
    (11, 'sem-marcio-2022-04'),
    (12, 'jornada-t16-2022-05'),
    (13, 'sem-marcio-2022-06'),
    (14, 'jornada-t17-2022-07'),
    (15, 'sem-marcio-2022-10'),
    (16, 'ht-imersao-mundial-2022-12'),
    (17, 'certificacao-holding-pro-2023-01'),
    (18, 'sem-marcio-2023-02'),
    (19, 'ht2-2023-03'),
    (20, 'ht3-2023-05'),
    (21, 'ethb-2023-07'),
    (22, 'ht4-2023-08'),
    (23, 'ht5-2023-09'),
    (24, 'sem-marcio-2023-10'),
    (25, 'ht6-2023-11'),
    (26, 'diamantes-2023-11'),
    (27, 'ht7-2024-01'),
    (28, 'sem-marcio-2024-02'),
    (29, 'ht8-2024-03'),
    (30, 'ht9-2024-05'),
    (31, 'ethb-2024-07'),
    (32, 'ht10-2024-08'),
    (33, 'sem-marcio-2024-09'),
    (34, 'ht11-2024-11'),
    (35, 'clinica-2024-11'),
    (36, 'ethb-2024-12'),
    (37, 'ht12-2025-02'),
    (38, 'sem-marcio-2025-03'),
    (39, 'ht13-2025-05'),
    (40, 'ht14-2025-07'),
    (41, 'clinica-2025-07'),
    (42, 'aurum-plus-2025-07'),
    (43, 'congresso-thb-2025-07'),
    (44, 'sem-elaine-2025-08'),
    (45, 'ht15-2025-09'),
    (46, 'sem-elaine-2025-09'),
    (47, 'ht16-2025-10'),
    (48, 'residencia-2025-10'),
    (49, 'aurum-plus-2025-11'),
    (50, 'ht17-2025-11'),
    (51, 'diamantes-2025-12'),
    (52, 'ethb-2025-12'),
    (53, 'ht18-2026-01'),
    (54, 'sem-marcio-2026-02'),
    (55, 'ht19-2026-02'),
    (56, 'clinica-2026-03'),
    (57, 'ht20-2026-03'),
    (58, 'workshop-residencia-2026-04'),
    (59, 'ht21-2026-04'),
    (60, 'imersao-2026-04'),
    (61, 'clinica-2026-04'),
    (62, 'sem-elaine-2026-04'),
    (63, 'imersao-2026-06'),
    (64, 'clinica-2026-06'),
    (65, 'sem-elaine-2026-06'),
    (66, 'live-hm-2026-06'),
    (67, 'reuniao-hm-ex-alunos-2026-07'),
    (68, 'atm-1-2026-07'),
    (69, 'aurum-plus-2026-07'),
    (70, 'sem-elaine-2026-07'),
    (71, 'ethb-2026-08'),
    (72, 'cnhf-2026-08'),
    (73, 'jornada-t12-2021-10'),
    (74, 'jornada-t13-2021-12'),
    (85, 'ht-atm-2026-07'),
    (86, 'ht29-2026-07'),
    (87, 'ht30-2026-08'),
    (88, 'ht-atm-2026-08'),
    (89, 'ht32-2026-09'),
    (90, 'ht23-2026-04'),
    (91, 'ht24-2026-04'),
    (92, 'ht25-2026-05'),
    (93, 'ht26-2026-05'),
    (94, 'ht27-2026-06'),
    (95, 'ht28-2026-06'),
    (96, 'encontro-acelera-2026-09'),
    (101, 'clinica-miami-2026-12')
  ) as v(id, chave)
 where e.id = v.id
   and e.chave is distinct from v.chave;

do $g$
begin
  if (select count(*) from fin.eventos where chave is not null) <> 87 then
    raise exception '20261014160000: nem todas as 87 linhas receberam chave.';
  end if;
end
$g$;
