-- Ensaio ESTRUTURAL da ETAPA 2B: aplica a cadeia 160000 a 160300 (já ensaiada) e depois 160400, 160450, 160500 e 160510 (esta só pela guarda: falta a data do HT21),
-- confere, e reverte 160500 -> 160400 conferindo que voltam. Transação DESFEITA. Rápido (sem chamar os funis):
-- o efeito nos leitores do financeiro está no 20261014160500_ensaio_impacto.sql.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
-- [cadeia da ETAPA 2, igual ao 20261014160000_ensaio.sql] Ensaio de 20261014160000, 160100, 160200 e 160300 em sequência, numa transação DESFEITA (rollback), com o estado
-- antes, os testes, e depois as reversões na ordem inversa conferindo que tudo volta.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
-- (o runner troca o select final por um RAISE: a transação aborta e nada fica gravado).
-- Os índices da 160300 entram aqui SEM concurrently (dentro de transação não dá); a prova do on conflict é a mesma.
-- Esperados: 87 chaves; 42 turmas; 10 edições do HT; 1 projeto; 1 controle.evento; on conflict mantém 1 linha;
-- relação consigo mesma recusada; leitores do financeiro com a mesma assinatura e o mesmo resultado; reversões zeram tudo.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
create temp table _z_out (em serial, passo text, linha text);
create temp table _z_emails as select distinct lower(btrim(comprador_email)) e from fin.hotmart_transacoes
  where comprador_email is not null and conta = 'academy' order by 1 limit 40;
create temp table _z_assin as select p.oid::regprocedure::text f, pg_get_function_result(p.oid) r from pg_proc p where p.prosrc ~* 'fin\.eventos\M';
insert into pg_temp._z_out(passo, linha) select '01 antes: fin.eventos / pessoas.eventos / thb_turmas', (select count(*) from fin.eventos) || ' / ' || (select count(*) from pessoas.eventos) || ' / ' || (select count(*) from public.thb_turmas);
insert into pg_temp._z_out(passo, linha) select '02 antes: md5 trajetoria_nucleo(40 e-mails)', (select md5(string_agg(t::text, '|' order by t::text)) || ' (' || count(*) || ' linhas)' from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t);
create temp table _z_traj as select md5(string_agg(t::text, '|' order by t::text)) h from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t;

-- ===== 20261014160000 =====
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
--      Casos especiais: 16 ht-imersao-mundial, 59 ht21-ht22, 85 e 88 ht-atm, 66 live-hm, 67 reuniao-hm-ex-alunos.
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
    (59, 'ht21-ht22-2026-04'),
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

-- ===== 20261014160100 =====
-- 20261014160100: as outras tabelas de evento passam a apontar para o catálogo oficial (fin.eventos)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2), 14/10/2026. Depende de 20261014160000.
--   Ensaio: 20261014160000_ensaio.sql. Detalhe: 20261014160000.explain.md.
--
-- POR QUE: PLANO da pessoa única, decisão 3: as 6 tabelas de evento ganham vínculo para fin.eventos, sem apagar nada.
-- O QUE FAZ (só acrescenta; colunas nullable, FK NOT VALID):
--   mkt.projetos.evento_id      -> fin.eventos(id). Preenche só o que a fonte diz: CNFMIAMI26 (id 68) = evento 101
--                                  (fin.eventos.fonte cita "mkt.projetos CNFMIAMI26"). Os outros 6 projetos não têm
--                                  linha no catálogo: ficam nulos e viram pergunta.
--   public.ht_editions.evento_id -> fin.eventos(id). Casa pelo número da edição: fin.eventos de holding_total com
--                                  codigo 'HTn' ou nome com '(HTn)'. A edição só recebe se houver exatamente 1 evento
--                                  (21 e 22 caem no evento 59 "HT21/HT22" e ficam nulas: pergunta).
--   controle.evento.evento_id    -> fin.eventos(id). lancamento-parceria-ago-2026 = evento 72 (CNHF), mesmo dia de
--                                  início (aulas_inicio = inicio = 24/08/2026) e mesma categoria de lançamento.
--   ht.cohorts.evento_id         -> fin.eventos(id). Só a coluna: as 3 linhas (1 turma, 1 modelo, 1 teste) não têm
--                                  fonte que diga o evento. Pergunta.
--   public.thb_turmas.chave      -> chave da turma (thb-tN-aaaa-mm), única. Turma não é evento do catálogo (não tem
--                                  data de início e fim; incluir turmas em fin.eventos mudaria 16 leitores do
--                                  financeiro). Fonte do mês: aba "Datas das turmas" da planilha "Alunos T1-T42
--                                  Ativação" (T1 a T37 e T17R); "T29.2 Nov/24" (nome da aba da turma na mesma
--                                  planilha); T39, T40 e T41 = mês de sale_start_at da própria thb_turmas. Ficam nulas
--                                  (pergunta): T38 (aba diz Mar/26, sale_start_at diz 12/04/2026) e A1 a A10, A8R.
--   cs.eventos                   -> NÃO recebe coluna: as 5 linhas são linhas de produto (HT, SEM, HM, CNHF, ACELERA),
--                                  não edições. Pergunta ao Maestro.
--   dados.edicoes_historico      -> já tem chave; atm-1-2026-07 é a mesma string da chave do evento 68 (vínculo pelo
--                                  próprio texto, sem coluna nova).
-- AS 5 PERGUNTAS: escala = 7 + 21 + 1 + 3 + 54 linhas; índice = único em thb_turmas.chave (54 linhas); FKs sem índice
--   nas tabelas de 1 a 21 linhas (seq scan vence); frequência = única; repetição = nenhuma;
--   reversão = 20261014160100_reversao.sql.
-- LEITORES: as tabelas são lidas por select('*') no front (ht_editions, thb_turmas): coluna nova aparece no JSON e não
--   quebra nada. O ensaio confere que nenhuma view depende de * dessas tabelas.

set local lock_timeout = '5s';

do $g$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'chave') then
    raise exception '20261014160100: falta 20261014160000 (fin.eventos.chave).';
  end if;
  if (select count(*) from mkt.projetos) <> 7 or (select count(*) from public.ht_editions) <> 21
     or (select count(*) from controle.evento) <> 1 or (select count(*) from ht.cohorts) <> 3
     or (select count(*) from public.thb_turmas) <> 54 then
    raise exception '20261014160100: contagem das tabelas de evento mudou. Reler.';
  end if;
  if (select sigla from mkt.projetos where id = 68) is distinct from 'CNFMIAMI26'
     or (select slug from controle.evento) is distinct from 'lancamento-parceria-ago-2026'
     or (select chave from fin.eventos where id = 72) is distinct from 'cnhf-2026-08'
     or (select chave from fin.eventos where id = 101) is distinct from 'clinica-miami-2026-12' then
    raise exception '20261014160100: premissa de vínculo não confere. Reler.';
  end if;
end
$g$;

alter table mkt.projetos   add column evento_id bigint;
alter table mkt.projetos   add constraint projetos_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table public.ht_editions add column evento_id bigint;
alter table public.ht_editions add constraint ht_editions_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table controle.evento add column evento_id bigint;
alter table controle.evento add constraint evento_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table ht.cohorts     add column evento_id bigint;
alter table ht.cohorts     add constraint cohorts_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table public.thb_turmas add column chave text
  constraint thb_turmas_chave_padrao_check check (chave is null or chave ~ '^thb-[a-z0-9]+(-[a-z0-9]+)*-[0-9]{4}-(0[1-9]|1[0-2])$');
create unique index thb_turmas_chave_key on public.thb_turmas (chave);

comment on column mkt.projetos.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column public.ht_editions.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column controle.evento.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column ht.cohorts.evento_id is 'Evento oficial do catálogo (fin.eventos). Pessoa única, 14/10/2026.';
comment on column public.thb_turmas.chave is 'Chave da turma thb-tN-aaaa-mm (mês de abertura do carrinho). Pessoa única, 14/10/2026.';

update mkt.projetos set evento_id = 101 where id = 68 and evento_id is distinct from 101;
update controle.evento set evento_id = 72 where slug = 'lancamento-parceria-ago-2026' and evento_id is distinct from 72;

update public.ht_editions h
   set evento_id = m.evento_id
  from (
    select h2.id, min(e.id) evento_id
      from public.ht_editions h2
      join fin.eventos e
        on e.categoria = 'holding_total'
       and (e.codigo = 'HT' || h2.edition_number or e.nome ~ ('\mHT' || h2.edition_number || '\M'))
     group by h2.id
    having count(*) = 1
  ) m
 where h.id = m.id
   and h.evento_id is distinct from m.evento_id
   and h.edition_number not in (21, 22);   -- evento 59 junta HT21 e HT22: pergunta, não palpite

update public.thb_turmas t
   set chave = v.chave
  from (values
    ('T1', 'thb-t1-2019-10'),
    ('T2', 'thb-t2-2019-12'),
    ('T3', 'thb-t3-2020-01'),
    ('T4', 'thb-t4-2020-04'),
    ('T5', 'thb-t5-2020-06'),
    ('T6', 'thb-t6-2020-08'),
    ('T7', 'thb-t7-2020-11'),
    ('T8', 'thb-t8-2021-01'),
    ('T9', 'thb-t9-2021-03'),
    ('T10', 'thb-t10-2021-05'),
    ('T11', 'thb-t11-2021-08'),
    ('T12', 'thb-t12-2021-10'),
    ('T13', 'thb-t13-2021-12'),
    ('T14', 'thb-t14-2022-01'),
    ('T15', 'thb-t15-2022-03'),
    ('T16', 'thb-t16-2022-05'),
    ('T17', 'thb-t17-2022-07'),
    ('T17R', 'thb-t17r-2022-10'),
    ('T18', 'thb-t18-2022-12'),
    ('T19', 'thb-t19-2023-01'),
    ('T20', 'thb-t20-2023-04'),
    ('T21', 'thb-t21-2023-05'),
    ('T22', 'thb-t22-2023-08'),
    ('T23', 'thb-t23-2023-09'),
    ('T24', 'thb-t24-2023-11'),
    ('T25', 'thb-t25-2024-01'),
    ('T26', 'thb-t26-2024-03'),
    ('T27', 'thb-t27-2024-05'),
    ('T28', 'thb-t28-2024-08'),
    ('T29', 'thb-t29-2024-11'),
    ('T30', 'thb-t30-2025-02'),
    ('T31', 'thb-t31-2025-05'),
    ('T32', 'thb-t32-2025-07'),
    ('T33', 'thb-t33-2025-09'),
    ('T34', 'thb-t34-2025-10'),
    ('T35', 'thb-t35-2025-11'),
    ('T36', 'thb-t36-2026-01'),
    ('T37', 'thb-t37-2026-02'),
    ('T29.2', 'thb-t29-2-2024-11'),
    ('T39', 'thb-t39-2026-06'),
    ('T40', 'thb-t40-2026-07'),
    ('T41', 'thb-t41-2026-09')
  ) as v(codigo, chave)
 where t.codigo = v.codigo
   and t.chave is distinct from v.chave;

do $g$
begin
  if (select count(*) from public.thb_turmas where chave is not null) <> 42 then
    raise exception '20261014160100: esperava 42 turmas com chave.';
  end if;
  if (select count(*) from public.ht_editions where evento_id is not null) <> 10 then
    raise exception '20261014160100: esperava 10 edições do HT ligadas (20, 23 a 30 e 32).';
  end if;
end
$g$;

-- ===== 20261014160200 =====
-- 20261014160200: linha do tempo da pessoa ligada ao evento oficial e à fonte; relação "sócio de"; mapa de ofertas
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2), 14/10/2026. Depende de 20261014160000 e 160100.
--   Ensaio: 20261014160000_ensaio.sql. Índices: 20261014160300 (CONCURRENTLY, arquivo próprio). Detalhe: 20261014160000.explain.md.
--
-- POR QUE: PLANO da pessoa única, decisões 4 e 5 (linha do tempo = pessoas.eventos, com vínculo ao evento oficial e à
--   fonte; carga repetível sem duplicar), desenho de sócios aprovado pelo Maestro em 14/10 (titular e cada sócio como
--   pessoa, vínculo "sócio de", casamento por e-mail/telefone, nunca CPF, ambíguo para revisão) e o dicionário,
--   item 1 (toda compra guarda a oferta exata; o catálogo diz produto e tipo: sinal, saldo, integral).
-- O QUE FAZ (só acrescenta):
--   1. pessoas.eventos ganha evento_id (-> fin.eventos), turma_id (-> public.thb_turmas), fonte_tabela e fonte_id
--      (tabela e id da linha de origem, ex.: 'fin.hotmart_transacoes' + código da transação). As duas juntas ou
--      nenhuma. A chave única (fonte_tabela, fonte_id, tipo) vem na 160300, com CONCURRENTLY. Os escritores ao vivo
--      (crm.hotmart_processar, pessoas.registrar, crm._clint_carregar) não preenchem as colunas novas e seguem iguais.
--      Valor, oferta e nome da oferta NÃO são copiados: a linha aponta para a transação (fonte_id) e o dinheiro continua
--      com um endereço só (fin.hotmart_transacoes, bruto = valor_cobrado, líquido = liquido_produtor).
--   2. CHECKs reescritos a partir da definição viva (guarda por md5): pessoas.eventos.tipo ganha 'resposta'
--      (formulário respondido); pessoas.eventos.fonte e pessoas.identificadores.origem ganham 'respondi'.
--   3. pessoas.relacoes: pessoa_id é sócio de relacionada_id (o titular), com o evento/turma e a linha de origem.
--      Única por (tipo, pessoa_id, relacionada_id, fonte_tabela, fonte_id). Nunca guarda CPF.
--   4. pessoas.vw_oferta: o mapa oferta -> nome exato -> produto -> tipo, sem tabela nova. Junta fin.ofertas (1.152
--      ofertas, nome exato da Hotmart), fin.produtos (família) e public.hm_product_catalog (categoria do HM/Aurum).
--      tipo: categoria 'sinal' = sinal, 'diferenca' = saldo, 'compra_cheia' = integral; o resto fica nulo
--      (reserva, renovação, sem categoria) e é pergunta ao Victor. fin.evento_ofertas (30 linhas) serve só para
--      oferta -> evento e continua sendo a fonte desse vínculo.
-- ACESSO: schema pessoas não exposto; pessoas.relacoes nasce com RLS ligada, sem policy e sem grant (igual às outras
--   tabelas de pessoas: só postgres). A view nasce sem grant para anon/authenticated/service_role.
-- AS 5 PERGUNTAS: escala = 22.125 linhas em pessoas.eventos hoje, ~250 mil depois da carga (ou ~750 mil com o AC);
--   colunas nulas não reescrevem a tabela; índice = 160300; frequência = única; repetição = nenhuma;
--   reversão = 20261014160200_reversao.sql.

set local lock_timeout = '5s';

do $g$
begin
  if (select chave from fin.eventos where id = 72) is distinct from 'cnhf-2026-08' then
    raise exception '20261014160200: falta 20261014160000.';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'thb_turmas' and column_name = 'chave') then
    raise exception '20261014160200: falta 20261014160100.';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'eventos' and column_name in ('evento_id', 'turma_id', 'fonte_tabela', 'fonte_id'))
     or to_regclass('pessoas.relacoes') is not null or to_regclass('pessoas.vw_oferta') is not null then
    raise exception '20261014160200: algo desta migration já existe.';
  end if;
  if (select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'eventos_tipo_check' and conrelid = 'pessoas.eventos'::regclass) <> '91031b2f966d7a7e32ef8e6fb8f2af4d'
     or (select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'eventos_fonte_check' and conrelid = 'pessoas.eventos'::regclass) <> 'b5102b8e47570f61d360e4efa34d5cbc'
     or (select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'identificadores_origem_check' and conrelid = 'pessoas.identificadores'::regclass) <> 'fd4711480e467c9cb0d161a7bd6f8dd5' then
    raise exception '20261014160200: CHECK vivo mudou desde 14/10. Reler com pg_get_constraintdef antes de reescrever.';
  end if;
end
$g$;

-- 1. vínculos na linha do tempo
alter table pessoas.eventos
  add column evento_id    bigint,
  add column turma_id     smallint,
  add column fonte_tabela text constraint eventos_fonte_tabela_check check (fonte_tabela is null or fonte_tabela ~ '^[a-z_]+\.[a-z_]+$'),
  add column fonte_id     text constraint eventos_fonte_id_check check (fonte_id is null or length(fonte_id) between 1 and 120),
  add constraint eventos_fonte_par_check check ((fonte_tabela is null) = (fonte_id is null));
alter table pessoas.eventos add constraint eventos_evento_id_fkey foreign key (evento_id) references fin.eventos(id) on delete restrict not valid;
alter table pessoas.eventos add constraint eventos_turma_id_fkey foreign key (turma_id) references public.thb_turmas(id) on delete restrict not valid;
comment on column pessoas.eventos.evento_id is 'Evento oficial (fin.eventos). Pessoa única, 14/10/2026.';
comment on column pessoas.eventos.turma_id is 'Turma THB/Aurum (public.thb_turmas) quando a linha é de matrícula, ativação ou sócio.';
comment on column pessoas.eventos.fonte_tabela is 'Tabela de origem da linha (schema.tabela). Com fonte_id e tipo, chave única da carga (índice 20261014160300).';
comment on column pessoas.eventos.fonte_id is 'Id da linha na tabela de origem (ex.: código da transação Hotmart, uuid da resposta do Respondi).';

-- 2. CHECKs: valores vivos + os novos
alter table pessoas.eventos drop constraint eventos_tipo_check;
alter table pessoas.eventos add constraint eventos_tipo_check check (tipo = any (array['lead', 'mql', 'nao_mql', 'cadastro',
  'compra', 'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso', 'pre_checkout', 'resposta']));
alter table pessoas.eventos drop constraint eventos_fonte_check;
alter table pessoas.eventos add constraint eventos_fonte_check check (fonte = any (array['formulario', 'crm', 'importacao',
  'sistema', 'hotmart', 'activecampaign', 'respondi']));
alter table pessoas.identificadores drop constraint identificadores_origem_check;
alter table pessoas.identificadores add constraint identificadores_origem_check check (origem = any (array['formulario', 'crm',
  'importacao', 'hotmart', 'activecampaign', 'respondi']));

-- 3. relação entre pessoas
create table pessoas.relacoes (
  id             bigint generated always as identity primary key,
  tipo           text not null check (tipo in ('socio_de')),
  pessoa_id      uuid not null references pessoas.pessoas(id) on delete restrict,   -- o sócio
  relacionada_id uuid not null references pessoas.pessoas(id) on delete restrict,   -- o titular
  evento_id      bigint references fin.eventos(id) on delete restrict,
  turma_id       smallint references public.thb_turmas(id) on delete restrict,
  fonte_tabela   text not null check (fonte_tabela ~ '^[a-z_]+\.[a-z_]+$'),
  fonte_id       text not null check (length(fonte_id) between 1 and 120),
  criado_em      timestamptz not null default now(),
  constraint relacoes_propria_check check (pessoa_id <> relacionada_id),
  constraint relacoes_unica unique (tipo, pessoa_id, relacionada_id, fonte_tabela, fonte_id)
);
alter table pessoas.relacoes enable row level security;
create index relacoes_relacionada_idx on pessoas.relacoes (relacionada_id, tipo);
create index relacoes_pessoa_idx on pessoas.relacoes (pessoa_id, tipo);
revoke all on pessoas.relacoes from public, anon, authenticated, service_role;
comment on table pessoas.relacoes is 'Relação entre pessoas (hoje só socio_de: pessoa_id é sócio de relacionada_id). Vem de formulário '
  'de inclusão de sócios (Respondi) e das abas de sócios das planilhas. Casamento por e-mail/telefone, nunca CPF; ambíguo vai para pessoas.revisao.';

-- 4. mapa de ofertas (sem tabela nova)
create view pessoas.vw_oferta with (security_invoker = true) as
select o.oferta_codigo,
       o.nome          as oferta_nome,
       o.produto_id,
       p.nome          as produto_nome,
       p.familia,
       p.conta,
       hm.categoria    as categoria_hm,
       hm.papel        as papel_hm,
       case hm.categoria when 'sinal' then 'sinal' when 'diferenca' then 'saldo' when 'compra_cheia' then 'integral' end as tipo
  from fin.ofertas o
  left join fin.produtos p on p.produto_id = o.produto_id
  left join public.hm_product_catalog hm on hm.offer_code = o.oferta_codigo;
revoke all on pessoas.vw_oferta from public, anon, authenticated, service_role;
comment on view pessoas.vw_oferta is 'Oferta -> nome exato -> produto -> tipo (sinal, saldo, integral). tipo nulo = não classificado (pergunta ao Victor). '
  'Pessoa única, 14/10/2026.';

-- ===== 20261014160300 (sem concurrently) =====

create unique index eventos_fonte_unico on pessoas.eventos (fonte_tabela, fonte_id, tipo) where fonte_id is not null;
create index eventos_evento_idx on pessoas.eventos (evento_id, tipo, quando) where evento_id is not null;
create index eventos_turma_idx on pessoas.eventos (turma_id, tipo) where turma_id is not null;


-- ===== 20261014160400 =====
-- 20261014160400: tipo de cada oferta (sinal, saldo, integral, renovacao) para "pagou só o sinal" do HM e do Aurum
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 20261014160200 (pessoas.vw_oferta).
--   Ensaio: 20261014160400_ensaio.sql (cobre 160000 a 160600). Detalhe: 20261014160400.explain.md.
--
-- POR QUE: dicionário da pessoa única, itens 1 e 8 (decisões do Victor, 14/10/2026): sinal não é compra do produto, mas
--   fica registrado (hm_so_sinal, aurum_so_sinal); reserva = sinal; renovação = tipo próprio (não é sinal).
-- O QUE FAZ:
--   1. pessoas.oferta_tipo: o tipo de uma oferta que o public.hm_product_catalog não classifica. Uma linha por oferta,
--      com a regra que deu o tipo. Nasce com as 68 ofertas de HM/Aurum cujo NOME EXATO (fin.ofertas.nome) diz o tipo
--      sem ambiguidade (regra 'nome_da_oferta'): sinal/reserva/entrada = sinal; saldo/diferença/quitação = saldo;
--      renova = renovacao; integral/pacote cheio/à vista = integral. Nome que diz dois tipos ("sinal da Renovação"),
--      que não diz nada, ou oferta sem nome no fin: NÃO entra; vai para a lista de conferência humana (356 ofertas),
--      que volta como linhas com regra 'conferencia_humana'.
--   2. pessoas.vw_oferta passa a dar o tipo nesta ordem: pessoas.oferta_tipo; senão a categoria do HM
--      (sinal e reserva = sinal, diferenca = saldo, compra_cheia = integral, renovacao = renovacao); senão nulo.
--      O catálogo do HM não é copiado (um endereço só): a view lê dele.
-- ACESSO: tabela com RLS ligada, sem policy e sem grant (só postgres), igual ao resto do schema pessoas.
-- AS 5 PERGUNTAS: escala = 68 linhas, até ~430 com a conferência; índice = PK; frequência = única + inclusões manuais;
--   repetição = nenhuma; reversão = 20261014160400_reversao.sql.

set local lock_timeout = '5s';

do $g$
begin
  if to_regclass('pessoas.vw_oferta') is null then
    raise exception '20261014160400: falta 20261014160200 (pessoas.vw_oferta).';
  end if;
  if to_regclass('pessoas.oferta_tipo') is not null then
    raise exception '20261014160400: pessoas.oferta_tipo já existe.';
  end if;
end
$g$;

create table pessoas.oferta_tipo (
  oferta_codigo text primary key check (length(oferta_codigo) between 1 and 40),
  tipo          text not null check (tipo in ('sinal', 'saldo', 'integral', 'renovacao')),
  regra         text not null check (regra in ('nome_da_oferta', 'conferencia_humana')),
  conferido_por uuid references public.perfis(id) on delete set null,
  conferido_em  timestamptz,
  criado_em     timestamptz not null default now(),
  constraint oferta_tipo_conferencia_check check ((regra = 'conferencia_humana') = (conferido_em is not null))
);
alter table pessoas.oferta_tipo enable row level security;
revoke all on pessoas.oferta_tipo from public, anon, authenticated, service_role;
comment on table pessoas.oferta_tipo is 'Tipo da oferta (sinal, saldo, integral, renovacao) quando public.hm_product_catalog não diz. '
  'regra nome_da_oferta = o nome exato da Hotmart diz o tipo; conferencia_humana = alguém conferiu (conferido_por/em).';

insert into pessoas.oferta_tipo (oferta_codigo, tipo, regra)
select v.oferta_codigo, v.tipo, 'nome_da_oferta'
  from (values
    ('0s6mlgas', 'saldo'),
    ('0wneuje4', 'renovacao'),
    ('1ftay6zh', 'sinal'),
    ('23los89e', 'saldo'),
    ('2bec4bxo', 'saldo'),
    ('2dst5ju4', 'saldo'),
    ('3taeyvt3', 'sinal'),
    ('4m2ln3iw', 'integral'),
    ('4plyg6ei', 'renovacao'),
    ('55hj74ys', 'saldo'),
    ('5qke41uk', 'renovacao'),
    ('5wpx0hji', 'renovacao'),
    ('5zbthigt', 'renovacao'),
    ('68te95i1', 'renovacao'),
    ('6h96z5wv', 'renovacao'),
    ('6lvgk55u', 'sinal'),
    ('823es8mt', 'saldo'),
    ('84tahfxy', 'saldo'),
    ('89k5nv1x', 'saldo'),
    ('9kugv3z1', 'saldo'),
    ('aldz0394', 'saldo'),
    ('bmp6tero', 'renovacao'),
    ('bzteqfhb', 'saldo'),
    ('cb3jeikd', 'sinal'),
    ('cetwlrjh', 'sinal'),
    ('d1gubzkk', 'renovacao'),
    ('e124zjn2', 'renovacao'),
    ('e4v27969', 'renovacao'),
    ('fydbjzpw', 'sinal'),
    ('gi9o06gl', 'renovacao'),
    ('hhlbnlsu', 'saldo'),
    ('hz22748u', 'sinal'),
    ('io2b58sn', 'renovacao'),
    ('ip17vk5p', 'saldo'),
    ('ipggxypl', 'saldo'),
    ('ixo7iu9u', 'renovacao'),
    ('j0eukg9z', 'sinal'),
    ('jae1if7p', 'sinal'),
    ('jiybgcmq', 'saldo'),
    ('k68nkbta', 'saldo'),
    ('l1q5624c', 'sinal'),
    ('l6qaj4o7', 'saldo'),
    ('lllte9zh', 'renovacao'),
    ('m2216g54', 'sinal'),
    ('mvkucwhf', 'renovacao'),
    ('n9rya8rz', 'saldo'),
    ('nw7zv9sq', 'sinal'),
    ('o45n4ydj', 'sinal'),
    ('ocgcc4qw', 'renovacao'),
    ('ot5o2qun', 'saldo'),
    ('otpi1sst', 'saldo'),
    ('p3d4f86p', 'sinal'),
    ('p6te2ohm', 'sinal'),
    ('r3ezbu9g', 'sinal'),
    ('shrintw5', 'saldo'),
    ('t5ra9110', 'renovacao'),
    ('tgk0ej0j', 'sinal'),
    ('tjareocy', 'sinal'),
    ('tycp384w', 'sinal'),
    ('ukhe6ubp', 'renovacao'),
    ('vq7zaz3u', 'sinal'),
    ('wcs98pas', 'renovacao'),
    ('xtq2rgis', 'integral'),
    ('yfwjy4ew', 'renovacao'),
    ('yi8ugzs7', 'saldo'),
    ('z8l9j2qt', 'sinal'),
    ('zqc1031u', 'renovacao'),
    ('zz546vjw', 'sinal')
  ) as v(oferta_codigo, tipo)
on conflict (oferta_codigo) do nothing;

create or replace view pessoas.vw_oferta with (security_invoker = true) as
select o.oferta_codigo,
       o.nome          as oferta_nome,
       o.produto_id,
       p.nome          as produto_nome,
       p.familia,
       p.conta,
       hm.categoria    as categoria_hm,
       hm.papel        as papel_hm,
       coalesce(ot.tipo,
         case hm.categoria when 'sinal' then 'sinal' when 'reserva' then 'sinal' when 'diferenca' then 'saldo'
                           when 'compra_cheia' then 'integral' when 'renovacao' then 'renovacao' end) as tipo,
       case when ot.tipo is not null then ot.regra
            when hm.categoria in ('sinal', 'reserva', 'diferenca', 'compra_cheia', 'renovacao') then 'catalogo_hm' end as regra_tipo
  from fin.ofertas o
  left join fin.produtos p on p.produto_id = o.produto_id
  left join public.hm_product_catalog hm on hm.offer_code = o.oferta_codigo
  left join pessoas.oferta_tipo ot on ot.oferta_codigo = o.oferta_codigo;
revoke all on pessoas.vw_oferta from public, anon, authenticated, service_role;

do $g$
begin
  if (select count(*) from pessoas.oferta_tipo) <> 68 then
    raise exception '20261014160400: esperava 68 ofertas classificadas pelo nome.';
  end if;
end
$g$;

insert into pg_temp._z_out(passo, linha) select '40 oferta_tipo pelo nome', string_agg(tipo || ' ' || n, ', ' order by tipo) from (select tipo, count(*) n from pessoas.oferta_tipo group by 1) x;
insert into pg_temp._z_out(passo, linha) select '41 vw_oferta por tipo e regra', string_agg(coalesce(tipo,'nulo') || '/' || coalesce(regra_tipo,'-') || ' ' || n, ', ' order by tipo, regra_tipo) from (select tipo, regra_tipo, count(*) n from pessoas.vw_oferta group by 1,2) x;
insert into pg_temp._z_out(passo, linha) select '42 ofertas HM/AURUM vendidas sem tipo (conferência humana)', count(distinct t.oferta_codigo)::text from fin.hotmart_transacoes t join fin.produtos p using (produto_id) left join pessoas.vw_oferta v on v.oferta_codigo = t.oferta_codigo where p.familia in ('HM','AURUM') and v.tipo is null;
do $t$ begin
  begin insert into pessoas.oferta_tipo (oferta_codigo, tipo, regra) values ('ENSAIO', 'sinal', 'conferencia_humana');
    insert into pg_temp._z_out(passo, linha) values ('43 conferência humana sem data', 'ACEITOU (ERRO)');
  exception when check_violation then insert into pg_temp._z_out(passo, linha) values ('43 conferência humana sem data', 'recusado (ok)'); end;
end $t$;
-- ===== 20261014160450 =====
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

insert into pg_temp._z_out(passo, linha) select '45 captacao_inicio preenchida', string_agg(id || '=' || captacao_inicio, ',') from fin.eventos where captacao_inicio is not null;
insert into pg_temp._z_out(passo, linha) select '46 assinaturas dos leitores de fin.eventos iguais (com captacao_inicio)', (select count(*) from pg_temp._z_assin a join pg_proc p on p.oid = a.f::regprocedure where pg_get_function_result(p.oid) = a.r) || ' de ' || (select count(*) from pg_temp._z_assin);
insert into pg_temp._z_out(passo, linha) select '47 trajetoria_nucleo igual (com captacao_inicio)', ((select md5(string_agg(t::text, '|' order by t::text)) from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t) = (select h from pg_temp._z_traj))::text;
-- ===== 20261014160500 =====
-- 20261014160500: o Seminário ATM de setembro de 2026 entra no catálogo oficial de eventos
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 20261014160000.
--   Linha nova em fin.eventos: aplicar com o aceite do dono do fin (JP) e o ok do Maestro.
--   Ensaios: 20261014160400_ensaio.sql (estrutura) e 20261014160500_ensaio_impacto.sql (leitores do fin).
--
-- POR QUE: o Victor lembrou de um ATM em setembro (14/10/2026), edição diferente do de julho (atm-1-2026-07) e do de
--   outubro (atm-elaine-1-2026-10). Achado na fonte: gp-operacoes projetos/2026-09-seminario-atm e
--   dados.edicoes_historico ('atm-2-2026-09', rótulo "ATM SET/26").
-- O QUE FAZ: insere o evento. categoria seminario_elaine (como o 68, "Seminário ATM (Dra. Elaine)"; quem conduz é a
--   Dra. Elaine, oferta-do-fechamento.md), setor escritorio, inicio 09/09/2026 (live), fim 11/09/2026 (treplay),
--   concepcao.md "3. Cronograma". venda_ate 11/09 (a condição encerra às 23h59 do dia de cada exibição; A CONFIRMAR).
--   chave atm-2-2026-09 = a mesma de dados.edicoes_historico. Divergência registrada: a pasta do gp-operacoes usa a
--   chave seminario-atm-2026-09 e a etiqueta antiga do ClickUp era sem-atm-set-2026.
-- PROVA (ensaio de impacto): o fn_fin_funis passa a mostrar 9 compradores e R$ 13.500 brutos no evento, igual às 9
--   vendas de Sessão de Viabilidade do debriefing (dados.edicoes_historico.vendas = 9); nenhum outro evento muda.
-- AS 5 PERGUNTAS: escala = 1 linha; índice = PK e chave; frequência = única; repetição = nenhuma;
--   reversão = 20261014160500_reversao.sql.

set local lock_timeout = '5s';

do $g$
begin
  if exists (select 1 from fin.eventos where chave = 'atm-2-2026-09' or (categoria = 'seminario_elaine' and inicio = date '2026-09-09')) then
    raise exception '20261014160500: o ATM de setembro já existe.';
  end if;
end
$g$;

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, observacao, automatico, chave)
values ('Seminário ATM (Dra. Elaine, set/2026)', 'seminario_elaine', 'escritorio', date '2026-09-09', date '2026-09-11', date '2026-09-11', null,
        'gp-operacoes projetos/2026-09-seminario-atm (concepcao.md, oferta-do-fechamento.md)',
        'Live 09/09 19h, replay 10/09 e treplay 11/09 (internos). venda_ate = última exibição: confirmar.', false, 'atm-2-2026-09');

-- ===== 20261014160510 com os valores nulos: a guarda tem que abortar =====
do $t$ begin
  begin
    execute $sql$-- 20261014160510: HT21 e HT22 viram dois eventos
--
-- ⚠ ESPERANDO A DATA DO EVENTO DO HT21 (Victor, 14/10/2026: "não inventar, deixar a migration esperando esse valor").
--   Preencher os 3 valores no bloco "VALORES A PREENCHER" abaixo (dia do evento, fim e fim da venda) e rodar o ensaio
--   de impacto de novo antes de aplicar: o HT21 precisa ficar DEPOIS do HT20 (14/03) e ANTES do HT22 (06/04) na ordem
--   por `inicio`, senão os funis do financeiro trocam ingressos de evento (ensaio de 14/10: com 13/03 o HT20 ia a 0).
--   Enquanto os valores estiverem nulos, a guarda aborta.
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 160000, 160100, 160450 e 160500.
--   MEXE NO FINANCEIRO (linhas de fin.eventos): aplicar só com o aceite do dono do fin (JP) e o ok do Maestro.
--   Ensaios: 20261014160400_ensaio.sql (estrutura) e 20261014160500_ensaio_impacto.sql (leitores do fin antes e depois; o ensaio de impacto aplica a 160500 e a 160510 juntas na foto B).
--
-- POR QUE (decisões do Victor, 14/10/2026, _contexto/decisoes/2026-10-pessoa-unica.md):
--   - "separar o evento 59 em dois": hoje o 59 se chama "Holding Total (HT21/HT22, abr/2026)".
-- O QUE FAZ:
--   1. Evento 59 vira só o HT22: nome "Holding Total (HT22)", chave ht22-2026-04. Datas ficam (06 a 12/04/2026 =
--      public.ht_editions 22, sale_start_at 06/04 e sale_end_at 12/04). `codigo` (T39/T40) e turma_hm ficam: são lidos
--      pelo financeiro (resolver de ofertas). fin.acoes 105 (T39, 06/04 a 01/05) continua apontando para o 59.
--   2. Evento novo HT21: inicio, fim e venda_ate = A PREENCHER (dia do evento; nenhuma fonte dá hoje).
--      captacao_inicio = 13/03/2026 (public.ht_editions 21 event_start_date; dashboard-ht SR_EDITIONS 'HT 21' de
--      2026-03-13 a 2026-04-05; Victor: 13/03 é o início da captação do HT21). codigo 'HT21'
--      (padrão que o fin.sincronizar_eventos_ht lê; o máximo segue HT32). turma_hm nula (fontes divergem: fin.acoes
--      89 põe a janela 14/03 a 06/04 na T38; thb_turmas liga a T38 ao HT22). chave ht21-<aaaa-mm do dia do evento>.
--   3. public.ht_editions 21 -> HT21 novo; 22 -> evento 59.
-- O QUE NÃO FAZ: não mexe em fin.acoes nem em fin.evento_ofertas. Hoje as vendas de 14/03 a 05/04 caem na ação 89
--   (HT20/T38); separar a atribuição do HT21 é decisão do dono do fin (pergunta no relatório).
-- AS 5 PERGUNTAS: escala = 1 update + 1 insert em 88 linhas; índice = PK e chave; frequência = única; repetição =
--   nenhuma; reversão = 20261014160510_reversao.sql. Efeito nos leitores do fin medido no ensaio de impacto.


-- ===== VALORES A PREENCHER (dia do evento do HT21; a chave sai do mês de `inicio`) =====
create temp table _ht21 on commit drop as
select null::date as inicio, null::date as fim, null::date as venda_ate;

do $g$
begin
  if (select nome || '|' || inicio || '|' || fim || '|' || coalesce(chave, '') from fin.eventos where id = 59)
     is distinct from 'Holding Total (HT21/HT22, abr/2026)|2026-04-06|2026-04-12|ht21-ht22-2026-04' then
    raise exception '20261014160510: evento 59 não está como esperado. Reler.';
  end if;
  if (select inicio is null or fim is null or venda_ate is null from pg_temp._ht21) then
    raise exception '20261014160510: falta a data do evento do HT21 (inicio, fim, venda_ate). Pedir ao Victor; não inventar.';
  end if;
  if not (select inicio > date '2026-03-14' and inicio < date '2026-04-06' and fim >= inicio and venda_ate >= inicio from pg_temp._ht21) then
    raise exception '20261014160510: o dia do HT21 precisa ficar entre o HT20 (14/03) e o HT22 (06/04), com fim e venda_ate depois dele.';
  end if;
  if exists (select 1 from fin.eventos where chave ~ '^ht21-[0-9]{4}-[0-9]{2}$' or codigo = 'HT21') then
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

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, captacao_inicio, codigo, fonte, observacao, automatico, chave)
select 'Holding Total (HT21)', 'holding_total', 'educacao', h.inicio, h.fim, h.venda_ate, date '2026-03-13', 'HT21',
       'public.ht_editions 21 + dashboard-ht SR_EDITIONS + decisão do Victor 14/10/2026',
       'Separado do evento 59 em 14/10/2026. captacao_inicio 13/03/2026.', false, 'ht21-' || to_char(h.inicio, 'YYYY-MM')
  from pg_temp._ht21 h;

update public.ht_editions h
   set evento_id = e.id
  from fin.eventos e
 where (h.edition_number = 21 and e.codigo = 'HT21' and e.categoria = 'holding_total') or (h.edition_number = 22 and e.chave = 'ht22-2026-04')
   and h.evento_id is distinct from e.id;

do $g$
begin
  if (select count(*) from fin.eventos) <> 89 or (select count(*) from public.ht_editions where evento_id is not null) <> 12 then
    raise exception '20261014160510: contagem final não confere (89 eventos com o ATM de setembro, 12 edições ligadas).';
  end if;
end
$g$;
$sql$;
    insert into pg_temp._z_out(passo, linha) values ('55 160510 sem a data do HT21', 'RODOU (ERRO)');
  exception when raise_exception then insert into pg_temp._z_out(passo, linha) values ('55 160510 sem a data do HT21', 'abortou pela guarda (ok): ' || left(sqlerrm, 60));
  end;
end $t$;
drop table if exists pg_temp._ht21;
-- ===== 20261014160510 com DATA FICTÍCIA (só para provar o caminho; não é dado) =====
-- 20261014160510: HT21 e HT22 viram dois eventos
--
-- ⚠ ESPERANDO A DATA DO EVENTO DO HT21 (Victor, 14/10/2026: "não inventar, deixar a migration esperando esse valor").
--   Preencher os 3 valores no bloco "VALORES A PREENCHER" abaixo (dia do evento, fim e fim da venda) e rodar o ensaio
--   de impacto de novo antes de aplicar: o HT21 precisa ficar DEPOIS do HT20 (14/03) e ANTES do HT22 (06/04) na ordem
--   por `inicio`, senão os funis do financeiro trocam ingressos de evento (ensaio de 14/10: com 13/03 o HT20 ia a 0).
--   Enquanto os valores estiverem nulos, a guarda aborta.
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 160000, 160100, 160450 e 160500.
--   MEXE NO FINANCEIRO (linhas de fin.eventos): aplicar só com o aceite do dono do fin (JP) e o ok do Maestro.
--   Ensaios: 20261014160400_ensaio.sql (estrutura) e 20261014160500_ensaio_impacto.sql (leitores do fin antes e depois; o ensaio de impacto aplica a 160500 e a 160510 juntas na foto B).
--
-- POR QUE (decisões do Victor, 14/10/2026, _contexto/decisoes/2026-10-pessoa-unica.md):
--   - "separar o evento 59 em dois": hoje o 59 se chama "Holding Total (HT21/HT22, abr/2026)".
-- O QUE FAZ:
--   1. Evento 59 vira só o HT22: nome "Holding Total (HT22)", chave ht22-2026-04. Datas ficam (06 a 12/04/2026 =
--      public.ht_editions 22, sale_start_at 06/04 e sale_end_at 12/04). `codigo` (T39/T40) e turma_hm ficam: são lidos
--      pelo financeiro (resolver de ofertas). fin.acoes 105 (T39, 06/04 a 01/05) continua apontando para o 59.
--   2. Evento novo HT21: inicio, fim e venda_ate = A PREENCHER (dia do evento; nenhuma fonte dá hoje).
--      captacao_inicio = 13/03/2026 (public.ht_editions 21 event_start_date; dashboard-ht SR_EDITIONS 'HT 21' de
--      2026-03-13 a 2026-04-05; Victor: 13/03 é o início da captação do HT21). codigo 'HT21'
--      (padrão que o fin.sincronizar_eventos_ht lê; o máximo segue HT32). turma_hm nula (fontes divergem: fin.acoes
--      89 põe a janela 14/03 a 06/04 na T38; thb_turmas liga a T38 ao HT22). chave ht21-<aaaa-mm do dia do evento>.
--   3. public.ht_editions 21 -> HT21 novo; 22 -> evento 59.
-- O QUE NÃO FAZ: não mexe em fin.acoes nem em fin.evento_ofertas. Hoje as vendas de 14/03 a 05/04 caem na ação 89
--   (HT20/T38); separar a atribuição do HT21 é decisão do dono do fin (pergunta no relatório).
-- AS 5 PERGUNTAS: escala = 1 update + 1 insert em 88 linhas; índice = PK e chave; frequência = única; repetição =
--   nenhuma; reversão = 20261014160510_reversao.sql. Efeito nos leitores do fin medido no ensaio de impacto.

set local lock_timeout = '5s';

-- ===== VALORES A PREENCHER (dia do evento do HT21; a chave sai do mês de `inicio`) =====
create temp table _ht21 on commit drop as
select date '2026-04-04' as inicio, date '2026-04-05' as fim, date '2026-04-05' as venda_ate;  -- DATA FICTÍCIA SÓ DO ENSAIO (prova o caminho)

do $g$
begin
  if (select nome || '|' || inicio || '|' || fim || '|' || coalesce(chave, '') from fin.eventos where id = 59)
     is distinct from 'Holding Total (HT21/HT22, abr/2026)|2026-04-06|2026-04-12|ht21-ht22-2026-04' then
    raise exception '20261014160510: evento 59 não está como esperado. Reler.';
  end if;
  if (select inicio is null or fim is null or venda_ate is null from pg_temp._ht21) then
    raise exception '20261014160510: falta a data do evento do HT21 (inicio, fim, venda_ate). Pedir ao Victor; não inventar.';
  end if;
  if not (select inicio > date '2026-03-14' and inicio < date '2026-04-06' and fim >= inicio and venda_ate >= inicio from pg_temp._ht21) then
    raise exception '20261014160510: o dia do HT21 precisa ficar entre o HT20 (14/03) e o HT22 (06/04), com fim e venda_ate depois dele.';
  end if;
  if exists (select 1 from fin.eventos where chave ~ '^ht21-[0-9]{4}-[0-9]{2}$' or codigo = 'HT21') then
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

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, captacao_inicio, codigo, fonte, observacao, automatico, chave)
select 'Holding Total (HT21)', 'holding_total', 'educacao', h.inicio, h.fim, h.venda_ate, date '2026-03-13', 'HT21',
       'public.ht_editions 21 + dashboard-ht SR_EDITIONS + decisão do Victor 14/10/2026',
       'Separado do evento 59 em 14/10/2026. captacao_inicio 13/03/2026.', false, 'ht21-' || to_char(h.inicio, 'YYYY-MM')
  from pg_temp._ht21 h;

update public.ht_editions h
   set evento_id = e.id
  from fin.eventos e
 where (h.edition_number = 21 and e.codigo = 'HT21' and e.categoria = 'holding_total') or (h.edition_number = 22 and e.chave = 'ht22-2026-04')
   and h.evento_id is distinct from e.id;

do $g$
begin
  if (select count(*) from fin.eventos) <> 89 or (select count(*) from public.ht_editions where evento_id is not null) <> 12 then
    raise exception '20261014160510: contagem final não confere (89 eventos com o ATM de setembro, 12 edições ligadas).';
  end if;
end
$g$;

insert into pg_temp._z_out(passo, linha) select '56 [data fictícia] eventos HT20/HT21/HT22/ATM', string_agg(id || ' ' || chave || ' ' || inicio || ' capt ' || coalesce(captacao_inicio::text,'-'), ' | ' order by inicio) from fin.eventos where chave in ('ht20-2026-03','ht22-2026-04','atm-2-2026-09') or codigo = 'HT21';
insert into pg_temp._z_out(passo, linha) select '57 [data fictícia] ht_editions 20/21/22', string_agg(h.edition_number || '=' || coalesce(e.chave,'-'), ' ' order by h.edition_number) from public.ht_editions h left join fin.eventos e on e.id = h.evento_id where h.edition_number in (20,21,22);
insert into pg_temp._z_out(passo, linha) select '58 fin.eventos total / chaves distintas', count(*) || ' / ' || count(distinct chave) from fin.eventos;
-- ===== reversões 160510 -> 160400 =====
-- Reversão de 20261014160510. Só funciona se nada apontar para o HT21 novo (FK restrict).
set local lock_timeout = '5s';
update public.ht_editions set evento_id = null where edition_number in (21, 22);
delete from fin.eventos where categoria = 'holding_total' and codigo = 'HT21' and chave ~ '^ht21-[0-9]{4}-[0-9]{2}$';
update fin.eventos set nome = 'Holding Total (HT21/HT22, abr/2026)', chave = 'ht21-ht22-2026-04',
       observacao = 'HT21 e HT22 no mesmo período; HT22: 25 ingressos'
 where id = 59;
-- Reversão de 20261014160500. Só funciona se nada apontar para o evento (FK restrict).
set local lock_timeout = '5s';
delete from fin.eventos where chave = 'atm-2-2026-09';
-- Reversão de 20261014160450.
set local lock_timeout = '5s';
alter table fin.eventos drop column if exists captacao_inicio;
-- Reversão de 20261014160400: a view volta à definição da 20261014160200; a tabela sai (com as conferências humanas
-- que tiver: exportar antes se já houver linhas com regra 'conferencia_humana').
set local lock_timeout = '5s';
drop view pessoas.vw_oferta;  -- create or replace não remove a coluna regra_tipo (42P16, pego no ensaio)
create view pessoas.vw_oferta with (security_invoker = true) as
select o.oferta_codigo, o.nome as oferta_nome, o.produto_id, p.nome as produto_nome, p.familia, p.conta,
       hm.categoria as categoria_hm, hm.papel as papel_hm,
       case hm.categoria when 'sinal' then 'sinal' when 'diferenca' then 'saldo' when 'compra_cheia' then 'integral' end as tipo
  from fin.ofertas o
  left join fin.produtos p on p.produto_id = o.produto_id
  left join public.hm_product_catalog hm on hm.offer_code = o.oferta_codigo;
revoke all on pessoas.vw_oferta from public, anon, authenticated, service_role;
drop table if exists pessoas.oferta_tipo;

insert into pg_temp._z_out(passo, linha) select '90 depois das reversões: 57 / 59 / total', (select inicio || ' ' || chave from fin.eventos where id = 57) || ' / ' || (select nome || ' ' || chave from fin.eventos where id = 59) || ' / ' || (select count(*) from fin.eventos);
insert into pg_temp._z_out(passo, linha) select '91 depois: oferta_tipo / captacao_inicio / vw_oferta colunas', coalesce(to_regclass('pessoas.oferta_tipo')::text, 'não') || ' / ' || (select count(*) from information_schema.columns where table_schema='fin' and table_name='eventos' and column_name='captacao_inicio') || ' / ' || (select count(*) from information_schema.columns where table_schema='pessoas' and table_name='vw_oferta');
insert into pg_temp._z_out(passo, linha) select '92 depois: ht_editions ligadas', count(*)::text from public.ht_editions where evento_id is not null;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
