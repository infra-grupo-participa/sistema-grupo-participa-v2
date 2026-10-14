-- APLICADA em 14/10/2026 com a versão gravada 20261014150135 (o arquivo se chamava 20261014160000; renomeado conforme o guia 6.3).
-- Ensaio do GRUPO B (fin e catálogos) sobre o banco com o grupo A JÁ aplicado (14/10/2026): 160000, 160100, 160400,
-- 160450, 160500, 160510 em sequência, numa transação DESFEITA, conferindo os leitores do financeiro e as reversões.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
create temp table _z_out (em serial, passo text, linha text);
create temp table _z_emails as select distinct lower(btrim(comprador_email)) e from fin.hotmart_transacoes where comprador_email is not null and conta = 'academy' order by 1 limit 40;
create temp table _z_assin as select p.oid::regprocedure::text f, pg_get_function_result(p.oid) r from pg_proc p where p.prosrc ~* 'fin\.eventos\M';
create temp table _z_traj as select md5(string_agg(t::text, '|' order by t::text)) h from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t;
insert into pg_temp._z_out(passo, linha) select '01 antes: fin.eventos', count(*)::text from fin.eventos;
-- ===== 20261014160000_fin_criar_chave_eventos.sql =====
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

-- ===== 20261014160100_vincular_catalogo_eventos.sql =====
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

-- ===== 20261014160400_pessoas_criar_oferta_tipo.sql =====
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

-- ===== 20261014160450_fin_criar_captacao_inicio.sql =====
-- 20261014160450: início da captação de cada evento, separado do dia do evento (fin.eventos.captacao_inicio)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014160000.
--   Mexe em fin.eventos (coluna nova e 1 linha): aplicar só com o aceite do JP (dono do fin) e o ok do Maestro.
--   Substitui a antiga 160600 (HT20 com inicio 01/01), descartada: no ensaio de impacto ela zerava os ingressos do HT18
--   nos funis do financeiro, porque `inicio` é o dia do evento e os funis ordenam por ele.
--
-- POR QUE: decisão do Victor, 14/10/2026 (censo-etapa2b.md, respostas): "HT20 começa em 01/01/2026" e "13/03 é o início
--   da captação do HT21" são datas de CAPTAÇÃO. Ficam em coluna própria; `inicio` continua sendo o dia do evento.
-- O QUE FAZ: coluna fin.eventos.captacao_inicio (date, nula, sem default).
--   HT20 (evento 57, dia do evento 14/03/2026, que fica): captação 01/01/2026 (Victor; public.ht_editions 20 event_start_date).
--   HT21 (evento 59, dia do evento 06 a 12/04/2026, que fica): captação 13/03/2026 (Victor; public.ht_editions 21
--   event_start_date; dashboard-ht SR_EDITIONS 'HT 21' começa em 2026-03-13).
--   Nenhum leitor do fin lê a coluna: nenhum número muda (provado no ensaio estrutural).
-- AS 5 PERGUNTAS: escala = 87 linhas, 2 preenchidas; índice = nenhum (ninguém filtra por ela); frequência = única;
--   repetição = nenhuma; reversão = 20261014160450_reversao.sql.

set local lock_timeout = '5s';

do $g$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'captacao_inicio') then
    raise exception '20261014160450: fin.eventos.captacao_inicio já existe.';
  end if;
  if (select nome || '|' || inicio from fin.eventos where id = 57) is distinct from 'Holding Total (HT20)|2026-03-14'
     or (select inicio || '|' || fim from fin.eventos where id = 59) is distinct from '2026-04-06|2026-04-12' then
    raise exception '20261014160450: eventos 57 ou 59 não estão como esperado. Reler.';
  end if;
end
$g$;

alter table fin.eventos add column captacao_inicio date;
comment on column fin.eventos.captacao_inicio is 'Início da captação do evento (não é o dia do evento: esse é `inicio`, que os funis usam para ordenar). '
  'Decisão do Victor, 14/10/2026.';
update fin.eventos e
   set captacao_inicio = v.captacao
  from (values (57, date '2026-01-01'), (59, date '2026-03-13')) as v(id, captacao)
 where e.id = v.id and e.captacao_inicio is distinct from v.captacao;

-- ===== 20261014160500_fin_criar_evento_atm_set.sql =====
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

-- ===== 20261014160510_fin_renomear_evento_59_ht21.sql =====
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

insert into pg_temp._z_out(passo, linha) select '10 fin.eventos / chaves distintas', count(*) || ' / ' || count(distinct chave) from fin.eventos;
insert into pg_temp._z_out(passo, linha) select '11 HT20 / HT21 / ATM SET', string_agg(id || ' ' || nome || ' ' || chave || ' capt ' || coalesce(captacao_inicio::text, '-'), ' | ' order by inicio) from fin.eventos where id in (57, 59) or chave = 'atm-2-2026-09';
insert into pg_temp._z_out(passo, linha) select '12 ht_editions ligadas / turmas com chave', (select count(*) from public.ht_editions where evento_id is not null) || ' / ' || (select count(*) from public.thb_turmas where chave is not null);
insert into pg_temp._z_out(passo, linha) select '13 ofertas tipadas pelo nome / sem tipo HM-Aurum', (select count(*) from pessoas.oferta_tipo) || ' / ' || (select count(distinct t.oferta_codigo) from fin.hotmart_transacoes t join fin.produtos p using (produto_id) left join pessoas.vw_oferta v on v.oferta_codigo = t.oferta_codigo where p.familia in ('HM','AURUM') and v.tipo is null);
insert into pg_temp._z_out(passo, linha) select '14 leitores de fin.eventos com a mesma assinatura', (select count(*) from pg_temp._z_assin a join pg_proc p on p.oid = a.f::regprocedure where pg_get_function_result(p.oid) = a.r) || ' de ' || (select count(*) from pg_temp._z_assin);
insert into pg_temp._z_out(passo, linha) select '15 trajetoria_nucleo igual', ((select md5(string_agg(t::text, '|' order by t::text)) from fin.trajetoria_nucleo((select array_agg(e) from pg_temp._z_emails)) t) = (select h from pg_temp._z_traj))::text;
-- ===== reversões, na ordem inversa =====
-- Reversão de 20261014160510.
set local lock_timeout = '5s';
update public.ht_editions set evento_id = null where edition_number in (21, 22);
update fin.eventos set nome = 'Holding Total (HT21/HT22, abr/2026)', observacao = 'HT21 e HT22 no mesmo período; HT22: 25 ingressos'
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

-- Reversão de 20261014160100 (vínculos com fin.eventos e chave das turmas). Reverter antes de 20261014160000.
set local lock_timeout = '5s';
alter table mkt.projetos      drop column if exists evento_id;
alter table public.ht_editions drop column if exists evento_id;
alter table controle.evento   drop column if exists evento_id;
alter table ht.cohorts        drop column if exists evento_id;
drop index if exists public.thb_turmas_chave_key;
alter table public.thb_turmas drop column if exists chave;

-- Reversão de 20261014160000 (fin.eventos.chave). Nada mais lê a coluna até a 20261014160100 ser aplicada:
-- reverter 160100 e 160200 antes desta.
set local lock_timeout = '5s';
drop index if exists fin.eventos_chave_key;
alter table fin.eventos drop column if exists chave;

insert into pg_temp._z_out(passo, linha) select '90 depois das reversões: fin.eventos / colunas novas', (select count(*) from fin.eventos) || ' / ' || (select count(*) from information_schema.columns where (table_schema, table_name, column_name) in (('fin','eventos','chave'),('fin','eventos','captacao_inicio'),('public','thb_turmas','chave'),('public','ht_editions','evento_id')));
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
