-- Ensaio de 20261014160000, 160100, 160200 e 160300 em sequência, numa transação DESFEITA (rollback), com o estado
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
--      Casos especiais: 16 ht-imersao-mundial, 85 e 88 ht-atm, 66 live-hm, 67 reuniao-hm-ex-alunos.
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

-- ===== testes =====
insert into pg_temp._z_out(passo, linha) select '10 chaves em fin.eventos (distintas / total)', count(distinct chave) || ' / ' || count(*) from fin.eventos;
insert into pg_temp._z_out(passo, linha) select '11 turmas com chave', count(*)::text from public.thb_turmas where chave is not null;
insert into pg_temp._z_out(passo, linha) select '12 turmas SEM chave (pergunta)', string_agg(codigo, ',' order by id) from public.thb_turmas where chave is null;
insert into pg_temp._z_out(passo, linha) select '13 ht_editions -> evento', string_agg(h.edition_number || '=' || coalesce(e.chave, '-'), ' ' order by h.edition_number) from public.ht_editions h left join fin.eventos e on e.id = h.evento_id;
insert into pg_temp._z_out(passo, linha) select '14 mkt.projetos ligados / controle.evento ligado', (select string_agg(p.sigla || '=' || e.chave, ',') from mkt.projetos p join fin.eventos e on e.id = p.evento_id) || ' / ' || (select string_agg(c.slug || '=' || e.chave, ',') from controle.evento c join fin.eventos e on e.id = c.evento_id);
insert into pg_temp._z_out(passo, linha) select '15 assinaturas dos 16 leitores de fin.eventos iguais', (select count(*) from pg_temp._z_assin a join pg_proc p on p.oid = a.f::regprocedure where pg_get_function_result(p.oid) = a.r) || ' de ' || (select count(*) from pg_temp._z_assin);
insert into pg_temp._z_out(passo, linha) select '16 trajetoria_nucleo igual depois', ((select md5(string_agg(t::text, '|' order by t::text)) from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t) = (select h from pg_temp._z_traj))::text;
insert into pg_temp._z_out(passo, linha) select '17 fin.sincronizar_eventos_ht() roda (linhas novas)', fin.sincronizar_eventos_ht()::text;
insert into pg_temp._z_out(passo, linha) select '18 linhas novas de HT sem chave', count(*)::text from fin.eventos where chave is null;

-- carga repetível: a mesma linha de origem duas vezes vira 1
create temp table _z_p as select id from pessoas.pessoas where situacao = 'ativa' and not teste order by criado_em limit 2;
insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando)
select (select id from pg_temp._z_p limit 1), 'compra', 'hotmart', 53, 'fin.hotmart_transacoes', 'ENSAIO-TESTE-1', now()
on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando)
select (select id from pg_temp._z_p limit 1), 'compra', 'hotmart', 53, 'fin.hotmart_transacoes', 'ENSAIO-TESTE-1', now()
on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
insert into pg_temp._z_out(passo, linha) select '20 on conflict: linhas da mesma origem (esperado 1)', count(*)::text from pessoas.eventos where fonte_id = 'ENSAIO-TESTE-1';
do $t$ begin
  begin
    insert into pessoas.eventos (pessoa_id, tipo, fonte, fonte_tabela) select id, 'lead', 'importacao', 'controle.lead' from pg_temp._z_p limit 1;
    insert into pg_temp._z_out(passo, linha) values ('21 fonte_tabela sem fonte_id', 'ACEITOU (ERRO)');
  exception when check_violation then insert into pg_temp._z_out(passo, linha) values ('21 fonte_tabela sem fonte_id', 'recusado (ok)'); end;
  begin
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id) select id, 'lead', 'importacao', 999999 from pg_temp._z_p limit 1;
    insert into pg_temp._z_out(passo, linha) values ('22 evento_id inexistente', 'ACEITOU (ERRO)');
  exception when foreign_key_violation then insert into pg_temp._z_out(passo, linha) values ('22 evento_id inexistente', 'recusado (ok)'); end;
  begin
    insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, fonte_tabela, fonte_id) select 'socio_de', id, id, 'respondi.respostas', 'x' from pg_temp._z_p limit 1;
    insert into pg_temp._z_out(passo, linha) values ('23 sócio de si mesmo', 'ACEITOU (ERRO)');
  exception when check_violation then insert into pg_temp._z_out(passo, linha) values ('23 sócio de si mesmo', 'recusado (ok)'); end;
end $t$;
insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
select 'socio_de', (select id from pg_temp._z_p order by id limit 1), (select id from pg_temp._z_p order by id desc limit 1), 37, 'respondi.respostas', 'ENSAIO-UUID'
on conflict on constraint relacoes_unica do nothing;
insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
select 'socio_de', (select id from pg_temp._z_p order by id limit 1), (select id from pg_temp._z_p order by id desc limit 1), 37, 'respondi.respostas', 'ENSAIO-UUID'
on conflict on constraint relacoes_unica do nothing;
insert into pg_temp._z_out(passo, linha) select '24 relação sócio repetida (esperado 1)', count(*)::text from pessoas.relacoes;
insert into pg_temp._z_out(passo, linha) select '25 relacoes: anon/authenticated leem?', has_table_privilege('anon', 'pessoas.relacoes', 'select') || ' / ' || has_table_privilege('authenticated', 'pessoas.relacoes', 'select');
insert into pg_temp._z_out(passo, linha) select '26 vw_oferta por tipo', string_agg(coalesce(tipo, 'nulo') || ' ' || n, ', ' order by tipo) from (select tipo, count(*) n from pessoas.vw_oferta group by 1) x;
insert into pg_temp._z_out(passo, linha) select '27 vw_oferta HM/AURUM sem tipo (pergunta)', count(*)::text from pessoas.vw_oferta where familia in ('HM', 'AURUM') and tipo is null;
do $e$ declare r record; s text := ''; begin
  set local enable_seqscan = off;
  for r in execute 'explain (analyze, buffers, costs off, timing off) insert into pessoas.eventos (pessoa_id, tipo, fonte, fonte_tabela, fonte_id) select (select id from pg_temp._z_p limit 1), ''compra'', ''hotmart'', ''fin.hotmart_transacoes'', ''ENSAIO-TESTE-1'' on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing' loop s := s || r."QUERY PLAN" || ' | '; end loop;
  insert into pg_temp._z_out(passo, linha) values ('30 explain on conflict', s);
  s := '';
  for r in execute 'explain (analyze, buffers, costs off, timing off) select pessoa_id from pessoas.eventos where evento_id = 53 and tipo = ''compra''' loop s := s || r."QUERY PLAN" || ' | '; end loop;
  insert into pg_temp._z_out(passo, linha) values ('31 explain leitura por evento', s);
  reset enable_seqscan;
end $e$;

-- ===== reversões, na ordem inversa =====
delete from pessoas.eventos where fonte_id = 'ENSAIO-TESTE-1';
drop index pessoas.eventos_fonte_unico; drop index pessoas.eventos_evento_idx; drop index pessoas.eventos_turma_idx;
-- Reversão de 20261014160200. Só depois de desfeita a carga que usa as colunas (linhas com fonte_tabela).
-- Os CHECKs voltam ao texto vivo de 14/10/2026; se já houver linha com tipo 'resposta' ou fonte/origem 'respondi',
-- o add constraint falha: apagar ou reclassificar essas linhas é decisão do Maestro, não desta reversão.
set local lock_timeout = '5s';
drop view if exists pessoas.vw_oferta;
drop table if exists pessoas.relacoes;
drop index if exists pessoas.eventos_fonte_unico;
drop index if exists pessoas.eventos_evento_idx;
drop index if exists pessoas.eventos_turma_idx;
alter table pessoas.eventos drop constraint if exists eventos_fonte_par_check;
alter table pessoas.eventos drop column if exists evento_id, drop column if exists turma_id,
  drop column if exists fonte_tabela, drop column if exists fonte_id;
alter table pessoas.eventos drop constraint eventos_tipo_check;
alter table pessoas.eventos add constraint eventos_tipo_check check (tipo = any (array['lead', 'mql', 'nao_mql', 'cadastro',
  'compra', 'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso', 'pre_checkout']));
alter table pessoas.eventos drop constraint eventos_fonte_check;
alter table pessoas.eventos add constraint eventos_fonte_check check (fonte = any (array['formulario', 'crm', 'importacao',
  'sistema', 'hotmart', 'activecampaign']));
alter table pessoas.identificadores drop constraint identificadores_origem_check;
alter table pessoas.identificadores add constraint identificadores_origem_check check (origem = any (array['formulario', 'crm',
  'importacao', 'hotmart', 'activecampaign']));
-- Reversão de 20261014160100 (vínculos com fin.eventos e chave das turmas). Reverter antes de 20261014160000.
set local lock_timeout = '5s';
alter table mkt.projetos      drop column if exists evento_id;
alter table public.ht_editions drop column if exists evento_id;
alter table controle.evento   drop column if exists evento_id;
alter table ht.cohorts        drop column if exists evento_id;
drop index if exists public.thb_turmas_chave_key;
alter table public.thb_turmas drop column if exists chave;
delete from fin.eventos where automatico and chave is null and id > 101;  -- só a linha que o teste 17 inseriu
-- Reversão de 20261014160000 (fin.eventos.chave). Nada mais lê a coluna até a 20261014160100 ser aplicada:
-- reverter 160100 e 160200 antes desta.
set local lock_timeout = '5s';
drop index if exists fin.eventos_chave_key;
alter table fin.eventos drop column if exists chave;

insert into pg_temp._z_out(passo, linha) select '90 depois das reversões: colunas novas restantes', count(*)::text from information_schema.columns where (table_schema, table_name, column_name) in (('fin','eventos','chave'),('mkt','projetos','evento_id'),('public','ht_editions','evento_id'),('controle','evento','evento_id'),('ht','cohorts','evento_id'),('public','thb_turmas','chave'),('pessoas','eventos','evento_id'),('pessoas','eventos','fonte_id'));
insert into pg_temp._z_out(passo, linha) select '91 depois: relacoes / vw_oferta existem', coalesce(to_regclass('pessoas.relacoes')::text, 'não') || ' / ' || coalesce(to_regclass('pessoas.vw_oferta')::text, 'não');
insert into pg_temp._z_out(passo, linha) select '92 depois: md5 dos CHECKs iguais aos de antes', ((select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'eventos_tipo_check' and conrelid = 'pessoas.eventos'::regclass) = '91031b2f966d7a7e32ef8e6fb8f2af4d'
  and (select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'eventos_fonte_check' and conrelid = 'pessoas.eventos'::regclass) = 'b5102b8e47570f61d360e4efa34d5cbc'
  and (select md5(pg_get_constraintdef(oid)) from pg_constraint where conname = 'identificadores_origem_check' and conrelid = 'pessoas.identificadores'::regclass) = 'fd4711480e467c9cb0d161a7bd6f8dd5')::text;
insert into pg_temp._z_out(passo, linha) select '93 depois: fin.eventos / pessoas.eventos', (select count(*) from fin.eventos) || ' / ' || (select count(*) from pessoas.eventos);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
