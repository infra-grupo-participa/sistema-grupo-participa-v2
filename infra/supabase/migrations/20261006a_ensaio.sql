-- 20261006a: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da
--   20261005p e da 20261005r (as duas precisam estar aplicadas, ou rodar este arquivo logo depois do corpo delas na mesma
--   transação). Todo resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo. Se o cliente só mostra
--   o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode o "rollback;" em seguida.
--   NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006a_mkt_projetos_cadastro.sql, das guardas
-- até antes da REVERSÃO; se a migration mudar, gerar de novo). Depois dele, os testes criam DADOS FICTÍCIOS (projetos
-- ZW28 "Projeto Ensaio Cadastro", ZV28, ZU28, ZT28, ZS28, ZR28, ZM28, ZL28, ZN28 "… Ensaio", contas act_000661 e act_000662 "Conta Ensaio A/B",
-- campanhas 9000000006xx, especialista externo "Especialista Ensaio", etiquetas zz-ensaio-*, produtos 99906xx, item de checklist "Item Ensaio …") e chamam as funções como a
-- tela, a rotina (service_role) e quem não pode chamariam (JWT simulado). Nenhum dado real vai para a saída. Tudo some no
-- rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO". Cada linha diz o que conferiu.
--   1  estrutura, sementes (4 unidades, 5 tipos, 10 regras, 2 especialistas, 5 UTM, regra nova) e a migração da subárea
--   2  tipo de lançamento: regra por unidade na função E no banco (FK), Aurum preenchido sozinho, pago só na CSM
--   3  especialista: lista interna, externo cadastrado na hora e reaproveitado, tipo trocado recusado
--   4  contas do projeto: sugestões pela sigla, campanhas religadas ao criar o projeto, alerta conta_fora_projeto
--   5  caminho antigo (mkt_projeto_salvar da 20261005m, só a subárea): tipo e unidade acompanham
--   6  pacote: modelo vazio, salvar, aplicar, reaplicar, recusas
--   7  resumo: tipo, unidade, tipo de lançamento, contas; receita do externo "não se aplica"; etiquetas do ClickUp
--   9  períodos de captação e evento: projeto inteiro derivado, datas antigas mantidas, captação como padrão da receita e
--      da fase de captação
--   10 checklist de montagem: automáticos, externo, marcar/desmarcar com quem e quando, itens por tipo de lançamento
--   11 revisão de 06/10: linha opcional (projeto novo grava o nome; edição sem linha não mexe) e busca de etiqueta do
--      ClickUp (sem acento, sem maiúscula, as duas fontes, só no formato, igual ao digitado primeiro). Se kpi.medicao_tarefa
--      NÃO existe (banco local), o teste cria uma de mentira com etiquetas zz-ensaio-*; se existe (produção), só lê e
--      confere a forma da resposta (nenhuma etiqueta real vai para a saída, só contagens)
--   8  grants e recusa 42501 para sem perfil, operador (mesmo com a área), visualizador e anon
--   Qualquer ERRO no meio = a migration não serve como está: não aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('mkt.unidades') is not null or to_regprocedure('mkt_trafego.alertas_base()') is not null
     or to_regprocedure('mkt_trafego.resumo_receita(bigint)') is not null then
    raise exception '20261006a: já aplicada (mkt.unidades, alertas_base ou resumo_receita existe)';
  end if;
  if to_regclass('mkt.projetos') is null or not exists (select 1 from information_schema.columns
       where table_schema = 'mkt' and table_name = 'projetos' and column_name = 'subarea_trafego') then
    raise exception '20261006a: falta a 20261005m (mkt.projetos.subarea_trafego)';
  end if;
  if to_regclass('mkt_trafego.alerta_regras') is null or to_regprocedure('mkt_trafego.resumo_base(bigint)') is null
     or to_regprocedure('mkt_trafego.alertas()') is null or to_regprocedure('mkt_trafego.campanha_aplicar_leitura(bigint)') is null then
    raise exception '20261006a: falta a 20261005p ou a 20261005r (aplicar as duas antes)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('trafego_cadastro_listas', 'trafego_projeto_cadastro', 'trafego_projeto_salvar', 'trafego_pacote_salvar',
                                'trafego_pacote_apagar', 'trafego_pacote_aplicar', 'trafego_clickup_etiquetas_receber',
                                'trafego_checklist', 'trafego_checklist_marcar', 'trafego_checklist_item_salvar',
                                'trafego_clickup_etiquetas_buscar')) then
    raise exception '20261006a: já existem funções public.trafego_* desta migration';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'mkt' and table_name = 'projetos'
              and column_name in ('tipo', 'unidade', 'tipo_lancamento', 'especialista_id', 'captacao_inicio', 'captacao_fim',
                                  'evento_inicio', 'evento_fim')) then
    raise exception '20261006a: mkt.projetos já tem as colunas desta migration';
  end if;
  if to_regprocedure('mkt_trafego.periodo_padrao(bigint)') is null or to_regprocedure('mkt_trafego.periodo_receita(bigint)') is null then
    raise exception '20261006a: falta mkt_trafego.periodo_padrao/periodo_receita (20261005r atualizada em 06/10/2026)';
  end if;
end
$guarda$;

-- ─── 1. Listas do cadastro (mkt) ─────────────────────────────────────────────────────────────────────────────────────
create table mkt.unidades (
  codigo    text primary key check (codigo ~ '^[a-z][a-z_]{1,29}$'),
  tipo      text not null check (tipo in ('interno', 'externo')),
  nome      text not null check (length(btrim(nome)) between 2 and 60),
  descricao text check (descricao is null or length(descricao) <= 200),
  ordem     smallint not null,
  ativa     boolean not null default true,
  constraint unidades_codigo_tipo unique (codigo, tipo)
);
comment on table mkt.unidades is
  'Unidade do projeto dentro do tipo (Victor, 06/10/2026): interno = CSM (CSM Academy, o educacional) ou Escritório '
  '(escritório de advocacia); externo = Aurum ou Diamantes. Lista configurável por SQL. 20261006a.';

create table mkt.tipos_lancamento (
  codigo text primary key check (codigo ~ '^[a-z][a-z_]{1,39}$'),
  nome   text not null check (length(btrim(nome)) between 2 and 80),
  ordem  smallint not null,
  ativo  boolean not null default true
);
comment on table mkt.tipos_lancamento is
  'Tipos de lançamento do projeto (Victor, 06/10/2026): lançamento clássico, lançamento pago, LPSG, ATM, palestra. Quais valem '
  'em cada unidade: mkt.lancamento_regras. Configurável por SQL. 20261006a.';

create table mkt.lancamento_regras (
  unidade         text not null references mkt.unidades(codigo) on delete cascade,
  tipo_lancamento text not null references mkt.tipos_lancamento(codigo) on delete restrict,
  primary key (unidade, tipo_lancamento)
);
comment on table mkt.lancamento_regras is
  'Combinações válidas unidade × tipo de lançamento (lançamento pago e LPSG no interno só na CSM). O banco recusa projeto fora '
  'daqui (FK composta em mkt.projetos). '
  'Unidade com um tipo só (Aurum: palestra) = o gatilho preenche sozinho. Configurável por SQL. 20261006a.';

create table mkt.especialistas (
  id            bigint generated always as identity primary key,
  nome          text not null check (length(btrim(nome)) between 2 and 120),
  tipo          text not null check (tipo in ('interno', 'externo')),
  unidade       text references mkt.unidades(codigo) on delete set null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.perfis(id) on delete set null,
  constraint especialistas_id_tipo unique (id, tipo)
);
create unique index especialistas_nome_unico on mkt.especialistas (tipo, lower(nome));
comment on table mkt.especialistas is
  'Especialista do projeto. Interno: lista (semente: Marcio Carvalho de Sá, Elaine Montenegro; mais por SQL). Externo: a '
  'pessoa/cliente do Aurum ou Diamantes, cadastrada na hora pela tela do Tráfego. 20261006a.';

alter table mkt.unidades enable row level security;
alter table mkt.tipos_lancamento enable row level security;
alter table mkt.lancamento_regras enable row level security;
alter table mkt.especialistas enable row level security;
revoke all on mkt.unidades, mkt.tipos_lancamento, mkt.lancamento_regras, mkt.especialistas from public, anon, authenticated;

insert into mkt.unidades (codigo, tipo, nome, descricao, ordem) values
  ('csm', 'interno', 'CSM', 'CSM Academy (o educacional)', 1),
  ('escritorio', 'interno', 'Escritório', 'Escritório de advocacia', 2),
  ('aurum', 'externo', 'Aurum', null, 3),
  ('diamantes', 'externo', 'Diamantes', null, 4);
insert into mkt.tipos_lancamento (codigo, nome, ordem) values
  ('lancamento_classico', 'Lançamento clássico', 1),
  ('lancamento_pago', 'Lançamento pago', 2),
  ('lpsg', 'Lançamento pago semanal gravado (LPSG)', 3),
  ('atm', 'ATM', 4),
  ('palestra', 'Palestra', 5);
insert into mkt.lancamento_regras (unidade, tipo_lancamento) values
  ('csm', 'lancamento_classico'), ('csm', 'lancamento_pago'), ('csm', 'lpsg'), ('csm', 'atm'),
  ('escritorio', 'lancamento_classico'), ('escritorio', 'atm'),
  ('aurum', 'palestra'),
  ('diamantes', 'lancamento_classico'), ('diamantes', 'lancamento_pago');
insert into mkt.especialistas (nome, tipo) values ('Marcio Carvalho de Sá', 'interno'), ('Elaine Montenegro', 'interno');

-- ─── 2. Colunas novas em mkt.projetos (tabela da 20261005m, já aplicada) ────────────────────────────────────────────
alter table mkt.projetos
  add column tipo text check (tipo is null or tipo in ('interno', 'externo')),
  add column unidade text,
  add column tipo_lancamento text,
  add column especialista_id bigint,
  add column captacao_inicio date,
  add column captacao_fim date,
  add column evento_inicio date,
  add column evento_fim date;
alter table mkt.projetos
  add constraint projetos_captacao_datas check (captacao_fim is null or captacao_inicio is null or captacao_fim >= captacao_inicio),
  add constraint projetos_evento_datas check (evento_fim is null or evento_inicio is null or evento_fim >= evento_inicio);
alter table mkt.projetos
  add constraint projetos_unidade_do_tipo foreign key (unidade, tipo) references mkt.unidades(codigo, tipo) on delete restrict,
  add constraint projetos_lancamento_da_unidade foreign key (unidade, tipo_lancamento)
    references mkt.lancamento_regras(unidade, tipo_lancamento) on delete restrict,
  add constraint projetos_especialista_do_tipo foreign key (especialista_id, tipo) references mkt.especialistas(id, tipo) on delete restrict,
  add constraint projetos_unidade_precisa_tipo check (unidade is null or tipo is not null),
  add constraint projetos_lancamento_precisa_unidade check (tipo_lancamento is null or unidade is not null),
  add constraint projetos_especialista_precisa_tipo check (especialista_id is null or tipo is not null);
comment on column mkt.projetos.tipo is 'Interno ou externo (Victor, 06/10/2026). 20261006a.';
comment on column mkt.projetos.unidade is 'Unidade dentro do tipo (mkt.unidades): csm, escritorio (interno); aurum, diamantes (externo). 20261006a.';
comment on column mkt.projetos.tipo_lancamento is 'Tipo de lançamento (mkt.tipos_lancamento), só os que valem para a unidade (mkt.lancamento_regras). 20261006a.';
comment on column mkt.projetos.captacao_inicio is 'Início da captação (Victor, 06/10/2026). Padrão da fase de captação e da receita sem período. 20261006a.';
comment on column mkt.projetos.evento_inicio is 'Início do evento (Victor, 06/10/2026). 20261006a.';
comment on column mkt.projetos.inicio is
  'Início do projeto inteiro. Desde a 20261006a: derivado (o mais cedo entre captação e evento) quando algum dos dois é '
  'preenchido; senão, a data gravada como antes.';
comment on column mkt.projetos.especialista_id is 'Especialista do projeto (mkt.especialistas), do mesmo tipo do projeto. 20261006a.';
comment on column mkt.projetos.subarea_trafego is
  'DERIVADA desde a 20261006a (gatilho mkt.projetos_tipo_unidade): interno, aurum, diamante a partir de tipo e unidade. '
  'Quem ainda grava só a subárea (mkt_projeto_salvar da 20261005m) tem tipo e unidade acompanhando.';

-- Migração do que existe, sem perda: a subárea continua igual; tipo e unidade saem dela. Interno fica sem unidade.
update mkt.projetos
   set tipo = case when subarea_trafego is null then null when subarea_trafego = 'interno' then 'interno' else 'externo' end,
       unidade = case subarea_trafego when 'aurum' then 'aurum' when 'diamante' then 'diamantes' end;

-- Gatilho: subárea derivada de tipo/unidade; caminho antigo (só a subárea mudou) leva tipo e unidade junto; unidade com
-- um tipo de lançamento só preenche sozinho (Aurum: palestra).
create function mkt.projetos_tipo_unidade() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_legado boolean;
  v_n int;
  v_unico text;
begin
  if tg_op = 'INSERT' then
    v_legado := new.tipo is null and new.subarea_trafego is not null;
  else
    v_legado := new.subarea_trafego is distinct from old.subarea_trafego
                and new.tipo is not distinct from old.tipo and new.unidade is not distinct from old.unidade;
  end if;
  if v_legado then
    new.tipo := case when new.subarea_trafego is null then null when new.subarea_trafego = 'interno' then 'interno' else 'externo' end;
    new.unidade := case new.subarea_trafego when 'aurum' then 'aurum' when 'diamante' then 'diamantes'
                     when 'interno' then case when tg_op = 'UPDATE' and old.tipo = 'interno' then old.unidade end end;
    if tg_op = 'UPDATE' then
      if new.unidade is distinct from old.unidade then new.tipo_lancamento := null; end if;
      if new.tipo is distinct from old.tipo then new.especialista_id := null; end if;
    end if;
  end if;
  if new.unidade is not null and new.tipo_lancamento is null then
    select count(*), min(r.tipo_lancamento) into v_n, v_unico
      from mkt.lancamento_regras r join mkt.tipos_lancamento t on t.codigo = r.tipo_lancamento and t.ativo
     where r.unidade = new.unidade;
    if v_n = 1 then new.tipo_lancamento := v_unico; end if;
  end if;
  new.subarea_trafego := case when new.tipo = 'interno' then 'interno' when new.unidade = 'aurum' then 'aurum'
                              when new.unidade = 'diamantes' then 'diamante' end;
  -- período do projeto inteiro a partir de captação e evento (sem nenhum dos dois: fica a data gravada)
  if num_nonnulls(new.captacao_inicio, new.captacao_fim, new.evento_inicio, new.evento_fim) > 0 then
    new.inicio := coalesce(least(new.captacao_inicio, new.evento_inicio), new.inicio);
    new.fim := coalesce(greatest(new.captacao_fim, new.evento_fim), new.fim);
  end if;
  return new;
end
$$;
create trigger projetos_tipo_unidade before insert or update on mkt.projetos
  for each row execute function mkt.projetos_tipo_unidade();

-- ─── 3. Tráfego: contas do projeto, pacote, UTM, etiquetas do ClickUp ───────────────────────────────────────────────
create table mkt_trafego.projeto_contas (
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  conta_id       bigint not null references mkt_trafego.contas(id) on delete restrict,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  primary key (projeto_id, conta_id)
);
create index projeto_contas_conta_idx on mkt_trafego.projeto_contas (conta_id);
comment on table mkt_trafego.projeto_contas is
  'Contas de anúncio do projeto (Victor, 06/10/2026). Sugerem campanhas da conta com a sigla no nome e alimentam a regra '
  'conta_fora_projeto do resumo do dia. Projeto sem conta ligada: a regra não avalia. 20261006a.';

create table mkt_trafego.pacote_modelos (
  id              bigint generated always as identity primary key,
  tipo_lancamento text not null references mkt.tipos_lancamento(codigo) on delete restrict,
  fase            text not null references mkt_trafego.fases(codigo) on delete restrict,
  ordem           smallint not null default 1,
  objetivos       text[] not null default '{}',
  pct_verba       numeric(5,2) check (pct_verba is null or pct_verba between 0 and 100),
  dias            smallint check (dias is null or dias between 1 and 366),
  obs             text check (obs is null or length(obs) <= 1000),
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null,
  constraint pacote_modelos_unico unique (tipo_lancamento, fase)
);
comment on table mkt_trafego.pacote_modelos is
  'Pacote da campanha: as fases (e objetivos esperados, % da verba e duração) que cada tipo de lançamento costuma ter. '
  'NASCE VAZIO: o conteúdo de cada pacote não foi definido (pergunta ao Victor). Aplicar = criar as fases que faltam. 20261006a.';

create table mkt_trafego.utm_parametros (
  plataforma text not null references mkt_trafego.plataformas(codigo) on delete cascade,
  parametro  text not null check (parametro ~ '^utm_[a-z]{2,20}$'),
  valor      text not null check (length(valor) between 1 and 200),
  ordem      smallint not null,
  primary key (plataforma, parametro)
);
comment on table mkt_trafego.utm_parametros is
  'Parâmetros de URL do gerador de UTM, por plataforma (padrão do gp-operacoes, Victor 06/10/2026). Muda por SQL. Meta: '
  'macros oficiais (Central de Ajuda do Meta, parâmetros de URL dinâmicos). Google: sem linha (fica como está). 20261006a.';
insert into mkt_trafego.utm_parametros (plataforma, parametro, valor, ordem) values
  ('meta', 'utm_source', 'metaads', 1),
  ('meta', 'utm_campaign', '{{campaign.name}}|{{campaign.id}}', 2),
  ('meta', 'utm_medium', '{{adset.name}}|{{adset.id}}', 3),
  ('meta', 'utm_content', '{{ad.name}}|{{ad.id}}', 4),
  ('meta', 'utm_term', '{{placement}}', 5);

create table mkt_trafego.clickup_etiquetas_vistas (
  etiqueta    text primary key check (etiqueta ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  coletado_em timestamptz not null default now()
);
comment on table mkt_trafego.clickup_etiquetas_vistas is
  'Etiquetas reais dos spaces do ClickUp (só as no formato da chave única), gravadas pela rotina trafego-clickup (só '
  'leitura no ClickUp). Vazia = a tela pede a etiqueta em texto. 20261006a.';

create table mkt_trafego.checklist_itens (
  id              bigint generated always as identity primary key,
  texto           text not null check (length(btrim(texto)) between 3 and 200),
  tipo_lancamento text references mkt.tipos_lancamento(codigo) on delete restrict,
  ordem           smallint not null default 1,
  ativo           boolean not null default true,
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null
);
create unique index checklist_itens_unico on mkt_trafego.checklist_itens (coalesce(tipo_lancamento, ''), lower(texto));
comment on table mkt_trafego.checklist_itens is
  'Itens MANUAIS do checklist de montagem do projeto (o que o sistema não confere sozinho). tipo_lancamento nulo = vale '
  'para todos. Desativar em vez de apagar (as marcas ficam). Semente: só o exemplo do Victor (06/10/2026). 20261006a.';
insert into mkt_trafego.checklist_itens (texto, ordem) values ('Automação de ingresso no grupo do WhatsApp configurada no SendFlow', 1);

create table mkt_trafego.checklist_marcas (
  projeto_id  bigint not null references mkt.projetos(id) on delete restrict,
  item_id     bigint not null references mkt_trafego.checklist_itens(id) on delete restrict,
  marcado_em  timestamptz not null default now(),
  marcado_por uuid references public.perfis(id) on delete set null,
  primary key (projeto_id, item_id)
);
comment on table mkt_trafego.checklist_marcas is 'Item manual marcado como pronto no projeto: quem e quando. Desmarcar apaga a linha. 20261006a.';

alter table mkt_trafego.checklist_itens enable row level security;
alter table mkt_trafego.checklist_marcas enable row level security;
revoke all on mkt_trafego.checklist_itens, mkt_trafego.checklist_marcas from public, anon, authenticated;

alter table mkt_trafego.projeto_contas enable row level security;
alter table mkt_trafego.pacote_modelos enable row level security;
alter table mkt_trafego.utm_parametros enable row level security;
alter table mkt_trafego.clickup_etiquetas_vistas enable row level security;
revoke all on mkt_trafego.projeto_contas, mkt_trafego.pacote_modelos, mkt_trafego.utm_parametros,
              mkt_trafego.clickup_etiquetas_vistas from public, anon, authenticated;

-- Regra nova do resumo do dia (os limiares das outras foram confirmados pelo Victor em 06/10/2026).
insert into mkt_trafego.alerta_regras (codigo, nome, ordem, limiar, unidade, gravidade, descricao) values
  ('conta_fora_projeto', 'Campanha do projeto em conta de fora', 8, 7, 'dias', 'media',
   'Campanha com a sigla do projeto no nome que gastou nos últimos limiar dias numa conta de anúncio que não é do projeto. '
   'Só avalia projeto com conta ligada.');

-- Checklist de montagem do projeto: automáticos (o que o banco confere) + manuais (marcados à mão). aplica = false
-- tira o item da conta (ex.: Hotmart em projeto externo; campanha sem fase quando não há campanha). feitos/total contam só
-- os que se aplicam.
create function mkt_trafego.checklist(p_projeto bigint) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_p mkt.projetos%rowtype;
  v_pl mkt_trafego.planejamento%rowtype;
  v_camp int; v_fora int; v_semfase int;
  v_auto jsonb; v_man jsonb;
begin
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return null; end if;
  select * into v_pl from mkt_trafego.planejamento where projeto_id = p_projeto;
  select count(*), count(*) filter (where c.fora_padrao),
         count(*) filter (where mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) is null)
    into v_camp, v_fora, v_semfase
    from mkt_trafego.campanhas c where c.projeto_id = p_projeto;
  select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'texto', x.texto, 'aplica', x.aplica, 'ok', x.aplica and x.ok, 'detalhe', x.detalhe)
                   order by x.ordem)
    into v_auto
    from (values
      (1, 'contas', 'Contas de anúncio vinculadas', true,
          exists (select 1 from mkt_trafego.projeto_contas pc where pc.projeto_id = p_projeto), null::text),
      (2, 'campanhas', 'Campanhas com a sigla encontradas', true, v_camp > 0, v_camp || ' campanha(s)'),
      (3, 'fora_padrao', 'Nenhuma campanha fora do padrão', v_camp > 0, v_fora = 0, case when v_fora > 0 then v_fora || ' fora do padrão' end),
      (4, 'fases_campanhas', 'Fase de cada campanha definida', v_camp > 0, v_semfase = 0, case when v_semfase > 0 then v_semfase || ' sem fase' end),
      (5, 'hotmart', 'Produtos da Hotmart vinculados', v_p.tipo is distinct from 'externo',
          exists (select 1 from mkt_trafego.produtos_hotmart h where h.projeto_id = p_projeto), null),
      (6, 'paginas', 'Páginas do projeto cadastradas', true,
          exists (select 1 from mkt.paginas pg where pg.projeto_id = p_projeto and pg.ativa), null),
      (7, 'etiqueta', 'Etiqueta do ClickUp preenchida', true, v_p.etiqueta_clickup is not null, null),
      (8, 'verba', 'Verba máxima preenchida', true, v_pl.verba_maxima is not null, null),
      (9, 'fases', 'Fases planejadas', true, exists (select 1 from mkt_trafego.projeto_fases f where f.projeto_id = p_projeto), null),
      (10, 'metas', 'Metas preenchidas (leads, receita ou CPL)', true,
           coalesce(v_pl.meta_leads, v_pl.meta_receita, v_pl.meta_cpl) is not null, null)
    ) x(ordem, codigo, texto, aplica, ok, detalhe);
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.texto, 'tipo_lancamento', i.tipo_lancamento, 'aplica', true,
                   'ok', m.item_id is not null, 'marcado_em', m.marcado_em, 'marcado_por', pf.nome) order by i.ordem, i.id), '[]'::jsonb)
    into v_man
    from mkt_trafego.checklist_itens i
    left join mkt_trafego.checklist_marcas m on m.item_id = i.id and m.projeto_id = p_projeto
    left join public.perfis pf on pf.id = m.marcado_por
   where i.ativo and (i.tipo_lancamento is null or i.tipo_lancamento = v_p.tipo_lancamento);
  return jsonb_build_object('automaticos', v_auto, 'manuais', v_man,
    'feitos', (select count(*) from jsonb_array_elements(v_auto || v_man) e where (e ->> 'aplica')::boolean and (e ->> 'ok')::boolean),
    'total', (select count(*) from jsonb_array_elements(v_auto || v_man) e where (e ->> 'aplica')::boolean));
end
$$;

-- Período padrão da meta de leads (sem fase de captação planejada) e da fase de captação: a captação do projeto; sem
-- captação preenchida, início e fim do projeto (a regra da 20261005r).
create or replace function mkt_trafego.periodo_padrao(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select case when p.captacao_inicio is not null then p.captacao_inicio else p.inicio end,
         case when p.captacao_inicio is not null then p.captacao_fim else p.fim end
    from mkt.projetos p where p.id = p_projeto;
$$;

-- Período padrão da RECEITA (vínculo de produto sem período próprio): do início da captação até o fim do EVENTO, para
-- pegar a abertura de carrinho (Victor, 06/10/2026). PROVISÓRIO, a confirmar depois pelo Victor: trocar = só esta
-- função. Sem captação: o início do evento, senão o do projeto; sem evento: o fim da captação, senão o do projeto.
create or replace function mkt_trafego.periodo_receita(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select coalesce(p.captacao_inicio, p.evento_inicio, p.inicio),
         case when num_nonnulls(p.captacao_inicio, p.evento_inicio) > 0 then coalesce(p.evento_fim, p.captacao_fim) else p.fim end
    from mkt.projetos p where p.id = p_projeto;
$$;

-- ─── 4. Resumo e resumo do dia (wrappers: as da 20261005r continuam, com outro nome) ────────────────────────────────
alter function mkt_trafego.resumo(bigint) rename to resumo_receita;
create function mkt_trafego.resumo(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_base jsonb := mkt_trafego.resumo_receita(p_projeto);
begin
  return (select coalesce(jsonb_agg(x.e || jsonb_build_object(
             'tipo', p.tipo, 'unidade', p.unidade, 'unidade_nome', u.nome, 'tipo_lancamento', p.tipo_lancamento,
             'tipo_lancamento_nome', t.nome, 'especialista', es.nome,
             'captacao_inicio', p.captacao_inicio, 'captacao_fim', p.captacao_fim, 'evento_inicio', p.evento_inicio, 'evento_fim', p.evento_fim,
             'contas_projeto', coalesce((select jsonb_agg(pc.conta_id order by pc.conta_id) from mkt_trafego.projeto_contas pc
                                          where pc.projeto_id = p.id), '[]'::jsonb),
             'receita_aplica', p.tipo is distinct from 'externo',
             'checklist_feitos', (ck.c ->> 'feitos')::int, 'checklist_total', (ck.c ->> 'total')::int)
           -- receita dos externos não entra por ora (Victor, 06/10/2026)
           || case when p.tipo = 'externo' then jsonb_build_object('receita', null, 'receita_compras', null,
                                                                   'receita_outras_moedas', null, 'receita_sem_valor', null)
                   else '{}'::jsonb end
           order by x.o), '[]'::jsonb)
            from jsonb_array_elements(v_base) with ordinality x(e, o)
            join mkt.projetos p on p.id = (x.e ->> 'projeto_id')::bigint
            left join mkt.unidades u on u.codigo = p.unidade
            left join mkt.tipos_lancamento t on t.codigo = p.tipo_lancamento
            left join mkt.especialistas es on es.id = p.especialista_id
            cross join lateral (select mkt_trafego.checklist(p.id) as c) ck);
end
$$;

alter function mkt_trafego.alertas() rename to alertas_base;
create function mkt_trafego.alertas() returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v jsonb := mkt_trafego.alertas_base();
  v_ontem date := mkt_trafego.ontem();
  v_extra jsonb;
begin
  -- conta_fora_projeto: campanha com a sigla do projeto no nome, gastando numa conta que não é do projeto
  select coalesce(jsonb_agg(jsonb_build_object(
           'regra', 'conta_fora_projeto', 'nome', rg.nome, 'gravidade', rg.gravidade, 'limiar', rg.limiar, 'unidade', rg.unidade,
           'projeto_id', x.projeto_id, 'sigla', x.sigla, 'projeto_nome', x.nome, 'valor', x.n, 'referencia', null,
           'detalhe', jsonb_build_object('dias', rg.limiar, 'contas', to_jsonb(x.contas)))), '[]'::jsonb)
    into v_extra
    from mkt_trafego.alerta_regras rg
    cross join lateral (
      select p.id as projeto_id, p.sigla, p.nome, count(distinct c.id)::numeric as n,
             array_agg(distinct ct.nome order by ct.nome) as contas
        from mkt.projetos p
        left join mkt_trafego.planejamento pl on pl.projeto_id = p.id
        left join mkt_trafego.status_projeto s on s.codigo = pl.status
        join mkt_trafego.campanhas c on c.leitura ->> 'projeto' = p.sigla
        join mkt_trafego.contas ct on ct.id = c.conta_id
       where p.ativo and coalesce(s.entra_no_resumo_dia, true)
         and exists (select 1 from mkt_trafego.projeto_contas pc where pc.projeto_id = p.id)
         and not exists (select 1 from mkt_trafego.projeto_contas pc where pc.projeto_id = p.id and pc.conta_id = c.conta_id)
         and (select max(d.dia) from mkt_trafego.desempenho_dia d where d.campanha_id = c.id and d.gasto > 0) > v_ontem - rg.limiar::int
       group by p.id, p.sigla, p.nome) x
   where rg.codigo = 'conta_fora_projeto' and rg.ligada;

  return v || jsonb_build_object('alertas', (
    select coalesce(jsonb_agg(a.e order by case a.e ->> 'gravidade' when 'alta' then 0 else 1 end, coalesce(rg.ordem, 99),
                                           a.e ->> 'sigla' nulls last, a.o), '[]'::jsonb)
      from jsonb_array_elements(coalesce(v -> 'alertas', '[]'::jsonb) || v_extra) with ordinality a(e, o)
      left join mkt_trafego.alerta_regras rg on rg.codigo = a.e ->> 'regra'));
end
$$;

-- ─── 5. Funções públicas da tela (authenticated + mkt.pode_ver('mkt_trafego'), hoje admin/dev) ─────────────────────
-- Listas do cadastro do projeto e do gerador de campanha.
create function public.trafego_cadastro_listas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'tipo', u.tipo, 'nome', u.nome, 'descricao', u.descricao)
                   order by u.ordem), '[]'::jsonb) from mkt.unidades u where u.ativa),
    'tipos_lancamento', (select coalesce(jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nome', t.nome) order by t.ordem), '[]'::jsonb)
                           from mkt.tipos_lancamento t where t.ativo),
    'regras', (select coalesce(jsonb_object_agg(x.unidade, x.tipos), '{}'::jsonb)
                 from (select r.unidade, jsonb_agg(r.tipo_lancamento order by t.ordem) as tipos
                         from mkt.lancamento_regras r join mkt.tipos_lancamento t on t.codigo = r.tipo_lancamento and t.ativo
                        group by r.unidade) x),
    'especialistas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'tipo', e.tipo, 'unidade', e.unidade)
                        order by e.tipo, e.nome), '[]'::jsonb) from mkt.especialistas e where e.ativo),
    'objetivos', (select coalesce(jsonb_agg(o.codigo order by o.codigo), '[]'::jsonb) from mkt.campanha_objetivos o where o.ativo),
    'utm', (select coalesce(jsonb_object_agg(x.plataforma, x.parametros), '{}'::jsonb)
              from (select u.plataforma, jsonb_agg(jsonb_build_object('parametro', u.parametro, 'valor', u.valor) order by u.ordem) as parametros
                      from mkt_trafego.utm_parametros u group by u.plataforma) x),
    'pacotes', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'tipo_lancamento', m.tipo_lancamento, 'fase', m.fase,
                   'ordem', m.ordem, 'objetivos', to_jsonb(m.objetivos), 'pct_verba', m.pct_verba, 'dias', m.dias, 'obs', m.obs)
                   order by m.tipo_lancamento, m.ordem, m.fase), '[]'::jsonb) from mkt_trafego.pacote_modelos m),
    'etiquetas_clickup', (select coalesce(jsonb_agg(e.etiqueta order by e.etiqueta), '[]'::jsonb) from mkt_trafego.clickup_etiquetas_vistas e),
    'checklist_itens', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.texto, 'tipo_lancamento', i.tipo_lancamento,
                          'ordem', i.ordem, 'ativo', i.ativo) order by i.ativo desc, i.ordem, i.id), '[]'::jsonb) from mkt_trafego.checklist_itens i));
end
$$;

-- Cadastro de um projeto para a tela (campos, gestores, contas, status, páginas, sugestões de campanha, pacote).
create function public.trafego_projeto_cadastro(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_p mkt.projetos%rowtype;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_p.id, 'sigla', v_p.sigla, 'nome', v_p.nome, 'linha', v_p.linha, 'etiqueta_clickup', v_p.etiqueta_clickup,
    'inicio', v_p.inicio, 'fim', v_p.fim, 'captacao_inicio', v_p.captacao_inicio, 'captacao_fim', v_p.captacao_fim,
    'evento_inicio', v_p.evento_inicio, 'evento_fim', v_p.evento_fim, 'ativo', v_p.ativo, 'tipo', v_p.tipo, 'unidade', v_p.unidade,
    'tipo_lancamento', v_p.tipo_lancamento, 'especialista_id', v_p.especialista_id,
    'especialista_nome', (select e.nome from mkt.especialistas e where e.id = v_p.especialista_id),
    'status', (select pl.status from mkt_trafego.planejamento pl where pl.projeto_id = v_p.id),
    'gestores', (select coalesce(jsonb_agg(g.gestor order by g.gestor), '[]'::jsonb) from mkt_trafego.projeto_gestores g where g.projeto_id = v_p.id),
    'contas', (select coalesce(jsonb_agg(c.conta_id order by c.conta_id), '[]'::jsonb) from mkt_trafego.projeto_contas c where c.projeto_id = v_p.id),
    'paginas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', pg.codigo, 'nome', pg.nome) order by pg.codigo), '[]'::jsonb)
                  from mkt.paginas pg where pg.projeto_id = v_p.id and pg.codigo is not null and pg.ativa),
    -- campanhas sem projeto, de uma conta do projeto, com a sigla no nome (palavra inteira): para ligar com um clique
    'sugestoes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'plataforma', c.plataforma,
                    'conta_id', c.conta_id, 'conta', ct.nome, 'status_plataforma', c.status_plataforma) order by c.nome), '[]'::jsonb)
                    from mkt_trafego.campanhas c join mkt_trafego.contas ct on ct.id = c.conta_id
                   where c.projeto_id is null
                     and c.conta_id in (select pc.conta_id from mkt_trafego.projeto_contas pc where pc.projeto_id = v_p.id)
                     and mkt.maiusculas(c.nome) ~ ('(^|[^A-Z0-9])' || v_p.sigla || '([^A-Z0-9]|$)')),
    'pacote_fases', (select count(*) from mkt_trafego.pacote_modelos m where m.tipo_lancamento = v_p.tipo_lancamento),
    'fases_planejadas', (select count(*) from mkt_trafego.projeto_fases f where f.projeto_id = v_p.id));
end
$$;

-- Cria (sem "id") ou edita (com "id") o projeto pela Central do Tráfego. Campos: sigla, nome, linha (OPCIONAL: a tela não
-- pede mais; projeto novo sem linha grava o nome, edição sem linha não mexe), etiqueta_clickup,
-- captacao_inicio, captacao_fim, evento_inicio, evento_fim, inicio e fim (só os de antes, sem período novo), ativo, tipo, unidade, tipo_lancamento, especialista_id OU especialista_nome (só externo: acha pelo nome ou
-- cadastra), status, gestores (lista; ausente = não mexe), contas (lista de ids; ausente = não mexe). Projeto novo ou
-- sigla nova: relê as campanhas com a sigla (ligam pelo nome). Retorna {ok, msg, id, tipo_lancamento, campanhas_relidas, avisos}.
create function public.trafego_projeto_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint; v_inicio date; v_fim date; v_ativo boolean; v_esp bigint;
  v_ci date; v_cf date; v_ei date; v_ef date;
  v_sigla text := upper(btrim(coalesce(p ->> 'sigla', '')));
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_linha text := nullif(btrim(coalesce(p ->> 'linha', '')), '');
  v_etq text := nullif(lower(btrim(coalesce(p ->> 'etiqueta_clickup', ''))), '');
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo', ''))), '');
  v_uni text := nullif(lower(btrim(coalesce(p ->> 'unidade', ''))), '');
  v_lanc text := nullif(lower(btrim(coalesce(p ->> 'tipo_lancamento', ''))), '');
  v_esp_nome text := nullif(btrim(regexp_replace(coalesce(p ->> 'especialista_nome', ''), '\s+', ' ', 'g')), '');
  v_status text := nullif(lower(btrim(coalesce(p ->> 'status', ''))), '');
  v_gestores text[]; v_contas bigint[]; v_permitidos text[]; v_nomes text;
  v_sigla_antiga text;
  v_avisos text[] := '{}';
  v_con text; v_n int := 0; v_c bigint; v_novo boolean;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_inicio := nullif(btrim(coalesce(p ->> 'inicio', '')), '')::date;
    v_fim := nullif(btrim(coalesce(p ->> 'fim', '')), '')::date;
    v_ci := nullif(btrim(coalesce(p ->> 'captacao_inicio', '')), '')::date;
    v_cf := nullif(btrim(coalesce(p ->> 'captacao_fim', '')), '')::date;
    v_ei := nullif(btrim(coalesce(p ->> 'evento_inicio', '')), '')::date;
    v_ef := nullif(btrim(coalesce(p ->> 'evento_fim', '')), '')::date;
    v_ativo := coalesce((p ->> 'ativo')::boolean, true);
    v_esp := nullif(p ->> 'especialista_id', '')::bigint;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido (datas AAAA-MM-DD).');
  end;
  if v_id is not null and not exists (select 1 from mkt.projetos where id = v_id) then
    return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.');
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    return jsonb_build_object('ok', false, 'msg', 'Sigla inválida: letras maiúsculas seguidas de 2 a 4 dígitos (ex.: PB26, HT33, SEMSET26).');
  end if;
  if length(v_nome) < 2 or length(v_nome) > 120 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome do projeto.'); end if;
  if v_linha is not null and (length(v_linha) < 2 or length(v_linha) > 60) then
    return jsonb_build_object('ok', false, 'msg', 'Linha: de 2 a 60 letras (campo opcional).');
  end if;
  if v_inicio is not null and v_fim is not null and v_fim < v_inicio then
    return jsonb_build_object('ok', false, 'msg', 'O fim não pode ser antes do início.');
  end if;
  if (v_ci is not null and v_cf is not null and v_cf < v_ci) then
    return jsonb_build_object('ok', false, 'msg', 'Captação: o fim não pode ser antes do início.');
  end if;
  if (v_ei is not null and v_ef is not null and v_ef < v_ei) then
    return jsonb_build_object('ok', false, 'msg', 'Evento: o fim não pode ser antes do início.');
  end if;
  if (v_ci is null) <> (v_cf is null) or (v_ei is null) <> (v_ef is null) then
    return jsonb_build_object('ok', false, 'msg', 'Preencha início e fim do período (captação e evento), ou deixe os dois em branco.');
  end if;
  if v_etq is not null and v_etq !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    return jsonb_build_object('ok', false, 'msg', 'Etiqueta do ClickUp fora do formato da chave: minúsculas, números e hífen, sem acento (ex.: black-friday-2026-10).');
  end if;
  if v_tipo is null or v_tipo not in ('interno', 'externo') then
    return jsonb_build_object('ok', false, 'msg', 'Escolha se o projeto é interno ou externo.');
  end if;
  if v_uni is null or not exists (select 1 from mkt.unidades u where u.codigo = v_uni and u.tipo = v_tipo and u.ativa) then
    select string_agg(u.nome, ' ou ' order by u.ordem) into v_nomes from mkt.unidades u where u.tipo = v_tipo and u.ativa;
    return jsonb_build_object('ok', false, 'msg', 'Escolha a unidade do projeto ' || v_tipo || ': ' || coalesce(v_nomes, 'nenhuma cadastrada') || '.');
  end if;
  select array_agg(r.tipo_lancamento order by t.ordem), string_agg(t.nome, ', ' order by t.ordem) into v_permitidos, v_nomes
    from mkt.lancamento_regras r join mkt.tipos_lancamento t on t.codigo = r.tipo_lancamento and t.ativo
   where r.unidade = v_uni;
  if v_lanc is null and cardinality(v_permitidos) = 1 then v_lanc := v_permitidos[1]; end if;
  if v_lanc is not null and not (v_lanc = any (coalesce(v_permitidos, '{}'))) then
    return jsonb_build_object('ok', false, 'msg', 'Tipo de lançamento não vale para esta unidade. Vale: ' || coalesce(v_nomes, 'nenhum') || '.');
  end if;
  if v_esp is not null then
    if not exists (select 1 from mkt.especialistas e where e.id = v_esp and e.tipo = v_tipo and e.ativo) then
      return jsonb_build_object('ok', false, 'msg', 'Especialista fora da lista do projeto ' || v_tipo || '.');
    end if;
  elsif v_esp_nome is not null then
    if v_tipo = 'interno' then
      return jsonb_build_object('ok', false, 'msg', 'Especialista interno: escolha da lista (a lista muda por SQL em mkt.especialistas).');
    end if;
    if length(v_esp_nome) < 2 or length(v_esp_nome) > 120 then
      return jsonb_build_object('ok', false, 'msg', 'Nome do especialista: de 2 a 120 letras.');
    end if;
    select e.id into v_esp from mkt.especialistas e where e.tipo = 'externo' and lower(e.nome) = lower(v_esp_nome);
  end if;
  if v_status is not null and not exists (select 1 from mkt_trafego.status_projeto where codigo = v_status and ativo) then
    return jsonb_build_object('ok', false, 'msg', 'Status fora da lista.');
  end if;
  if p ? 'gestores' then
    if jsonb_typeof(p -> 'gestores') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'msg', 'Gestores: uma lista de siglas.');
    end if;
    select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_gestores
      from jsonb_array_elements_text(p -> 'gestores') x where btrim(x) <> '';
    if exists (select 1 from unnest(v_gestores) g where not exists (select 1 from mkt.campanha_gestores cg where cg.sigla = g and cg.ativo)) then
      return jsonb_build_object('ok', false, 'msg', 'Gestor fora da lista.');
    end if;
  end if;
  if p ? 'contas' then
    if jsonb_typeof(p -> 'contas') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'msg', 'Contas: uma lista de contas de anúncio.');
    end if;
    begin
      select coalesce(array_agg(distinct x::bigint), '{}') into v_contas from jsonb_array_elements_text(p -> 'contas') x;
    exception when others then
      return jsonb_build_object('ok', false, 'msg', 'Contas: uma lista de contas de anúncio.');
    end;
    if exists (select 1 from unnest(v_contas) c where not exists (select 1 from mkt_trafego.contas k where k.id = c)) then
      return jsonb_build_object('ok', false, 'msg', 'Conta de anúncio não encontrada.');
    end if;
  end if;
  -- chave única do gp-operacoes: edição com data termina em -aaaa-mm (aviso, não recusa: produto contínuo não tem data)
  if v_etq is not null and coalesce(v_cf, v_ef, v_fim) is not null and v_etq !~ '-[0-9]{4}-[0-9]{2}$' then
    v_avisos := array_append(v_avisos, 'etiqueta_sem_ano_mes');
  end if;

  begin
    if v_esp is null and v_esp_nome is not null then
      insert into mkt.especialistas (nome, tipo, unidade, criado_por) values (v_esp_nome, 'externo', v_uni, v_uid) returning id into v_esp;
      v_avisos := array_append(v_avisos, 'especialista_cadastrado');
    end if;
    v_novo := v_id is null;
    if v_novo then
      insert into mkt.projetos (sigla, nome, linha, etiqueta_clickup, tipo, unidade, tipo_lancamento, especialista_id, inicio, fim,
                                captacao_inicio, captacao_fim, evento_inicio, evento_fim, ativo, criado_por, atualizado_por)
      values (v_sigla, v_nome, coalesce(v_linha, btrim(left(v_nome, 60))), v_etq, v_tipo, v_uni, v_lanc, v_esp, v_inicio, v_fim, v_ci, v_cf, v_ei, v_ef, v_ativo, v_uid, v_uid)
      returning id into v_id;
    else
      select sigla into v_sigla_antiga from mkt.projetos where id = v_id for update;
      update mkt.projetos
         set sigla = v_sigla, nome = v_nome, linha = coalesce(v_linha, linha), etiqueta_clickup = v_etq, tipo = v_tipo, unidade = v_uni,
             tipo_lancamento = v_lanc, especialista_id = v_esp, inicio = v_inicio, fim = v_fim, captacao_inicio = v_ci,
             captacao_fim = v_cf, evento_inicio = v_ei, evento_fim = v_ef, ativo = v_ativo,
             atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
    end if;
  exception
    when unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', case when v_con like '%etiqueta%' then 'Já existe projeto com esta etiqueta do ClickUp.'
                                                         when v_con like '%especialista%' then 'Especialista já cadastrado com este nome.'
                                                         else 'Já existe projeto com a sigla ' || v_sigla || '.' end);
    when check_violation or foreign_key_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Combinação fora da regra (' || v_con || ').');
  end;

  if v_status is not null or exists (select 1 from mkt_trafego.planejamento where projeto_id = v_id) then
    insert into mkt_trafego.planejamento as pl (projeto_id, status, atualizado_por) values (v_id, v_status, v_uid)
    on conflict (projeto_id) do update set status = excluded.status, atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  end if;
  if v_gestores is not null then
    delete from mkt_trafego.projeto_gestores where projeto_id = v_id and gestor <> all (v_gestores);
    insert into mkt_trafego.projeto_gestores (projeto_id, gestor, atualizado_por)
    select v_id, g, v_uid from unnest(v_gestores) g on conflict (projeto_id, gestor) do nothing;
  end if;
  if v_contas is not null then
    delete from mkt_trafego.projeto_contas where projeto_id = v_id and conta_id <> all (v_contas);
    insert into mkt_trafego.projeto_contas (projeto_id, conta_id, atualizado_por)
    select v_id, c, v_uid from unnest(v_contas) c on conflict (projeto_id, conta_id) do nothing;
  end if;
  if v_novo or v_sigla_antiga is distinct from v_sigla then
    for v_c in select c.id from mkt_trafego.campanhas c
                where c.projeto_id = v_id or c.leitura ->> 'projeto' in (v_sigla, v_sigla_antiga) order by c.id loop
      if mkt_trafego.campanha_aplicar_leitura(v_c) then v_n := v_n + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Projeto ' || v_sigla || case when v_novo then ' criado.' else ' salvo.' end, 'id', v_id,
                            'tipo_lancamento', (select tipo_lancamento from mkt.projetos where id = v_id),
                            'campanhas_relidas', v_n, 'avisos', to_jsonb(v_avisos));
end
$$;

-- Pacote: cria (sem "id") ou edita (com "id") uma fase do modelo de um tipo de lançamento. Campos: tipo_lancamento, fase,
-- ordem, objetivos (lista do padrão de nome), pct_verba, dias, obs. Retorna {ok, msg, id, avisos}.
create function public.trafego_pacote_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint; v_ordem smallint; v_pct numeric; v_dias smallint;
  v_tipo text := lower(btrim(coalesce(p ->> 'tipo_lancamento', '')));
  v_fase text := lower(btrim(coalesce(p ->> 'fase', '')));
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_obj text[] := '{}';
  v_avisos text[] := '{}';
  v_soma numeric;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_ordem := coalesce(nullif(btrim(coalesce(p ->> 'ordem', '')), '')::smallint, 1);
    v_pct := nullif(btrim(coalesce(p ->> 'pct_verba', '')), '')::numeric;
    v_dias := nullif(btrim(coalesce(p ->> 'dias', '')), '')::smallint;
    if jsonb_typeof(p -> 'objetivos') = 'array' then
      select coalesce(array_agg(distinct mkt.maiusculas(btrim(x))) filter (where btrim(x) <> ''), '{}') into v_obj
        from jsonb_array_elements_text(p -> 'objetivos') x;
    end if;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Número em formato inválido.');
  end;
  if not exists (select 1 from mkt.tipos_lancamento where codigo = v_tipo and ativo) then
    return jsonb_build_object('ok', false, 'msg', 'Tipo de lançamento fora da lista.');
  end if;
  if not exists (select 1 from mkt_trafego.fases where codigo = v_fase and ativa) then
    return jsonb_build_object('ok', false, 'msg', 'Fase fora da lista.');
  end if;
  if exists (select 1 from unnest(v_obj) o where not exists (select 1 from mkt.campanha_objetivos co where co.codigo = o and co.ativo)) then
    return jsonb_build_object('ok', false, 'msg', 'Objetivo fora da lista do padrão de nome.');
  end if;
  if v_pct is not null and (v_pct < 0 or v_pct > 100) then return jsonb_build_object('ok', false, 'msg', '% da verba entre 0 e 100.'); end if;
  if v_dias is not null and (v_dias < 1 or v_dias > 366) then return jsonb_build_object('ok', false, 'msg', 'Duração entre 1 e 366 dias.'); end if;
  begin
    if v_id is null then
      insert into mkt_trafego.pacote_modelos (tipo_lancamento, fase, ordem, objetivos, pct_verba, dias, obs, atualizado_por)
      values (v_tipo, v_fase, v_ordem, v_obj, v_pct, v_dias, v_obs, v_uid) returning id into v_id;
    else
      update mkt_trafego.pacote_modelos
         set tipo_lancamento = v_tipo, fase = v_fase, ordem = v_ordem, objetivos = v_obj, pct_verba = v_pct, dias = v_dias, obs = v_obs,
             atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Fase do pacote não encontrada.'); end if;
    end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Este pacote já tem esta fase.');
  end;
  select sum(pct_verba) into v_soma from mkt_trafego.pacote_modelos where tipo_lancamento = v_tipo;
  if v_soma > 100 then v_avisos := array_append(v_avisos, 'pacote_acima_de_100'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Fase do pacote salva.', 'id', v_id, 'avisos', to_jsonb(v_avisos));
end
$$;

create function public.trafego_pacote_apagar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  delete from mkt_trafego.pacote_modelos where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Fase do pacote não encontrada.'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Fase do pacote apagada. Os projetos que já usaram o pacote não mudam.');
end
$$;

-- Aplica o pacote do tipo de lançamento do projeto: cria no planejamento as fases que ainda não existem (verba = % do
-- pacote × verba máxima, se houver as duas; fase de captação com o período de captação do projeto, as outras em branco).
-- Não mexe em fase já planejada.
create function public.trafego_pacote_aplicar(p_projeto bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_p mkt.projetos%rowtype;
  v_vmax numeric;
  v_total int; v_criadas int;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  if v_p.tipo_lancamento is null then
    return jsonb_build_object('ok', false, 'msg', 'Escolha o tipo de lançamento do projeto antes.');
  end if;
  select count(*) into v_total from mkt_trafego.pacote_modelos where tipo_lancamento = v_p.tipo_lancamento;
  if v_total = 0 then
    return jsonb_build_object('ok', false, 'msg', 'O pacote deste tipo de lançamento ainda não tem conteúdo (modelo vazio).');
  end if;
  select verba_maxima into v_vmax from mkt_trafego.planejamento where projeto_id = p_projeto;
  with novas as (
    insert into mkt_trafego.projeto_fases (projeto_id, fase, verba, inicio, fim, obs, atualizado_por)
    select p_projeto, m.fase, case when m.pct_verba is not null and v_vmax is not null then round(v_vmax * m.pct_verba / 100, 2) end,
           -- a fase de captação nasce com o período de captação do projeto; as outras, em branco
           case when m.fase = 'captacao' then v_p.captacao_inicio end, case when m.fase = 'captacao' then v_p.captacao_fim end,
           left('Do pacote' || case when cardinality(m.objetivos) > 0 then ': objetivos ' || array_to_string(m.objetivos, ', ') else '' end
                || case when m.dias is not null then '; ' || m.dias || ' dias' else '' end, 1000), v_uid
      from mkt_trafego.pacote_modelos m
     where m.tipo_lancamento = v_p.tipo_lancamento
       and not exists (select 1 from mkt_trafego.projeto_fases f where f.projeto_id = p_projeto and f.fase = m.fase)
    returning 1)
  select count(*) into v_criadas from novas;
  return jsonb_build_object('ok', true, 'msg', v_criadas || ' fase(s) criada(s) a partir do pacote; ' || (v_total - v_criadas) || ' já existia(m).',
                            'criadas', v_criadas, 'ja_existiam', v_total - v_criadas);
end
$$;

create function public.trafego_checklist(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return mkt_trafego.checklist(p_projeto);
end
$$;

-- Marca (p_feito true) ou desmarca um item manual do checklist no projeto. Guarda quem e quando.
create function public.trafego_checklist_marcar(p_projeto bigint, p_item bigint, p_feito boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_tl text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select tipo_lancamento into v_tl from mkt.projetos where id = p_projeto;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  if not exists (select 1 from mkt_trafego.checklist_itens i where i.id = p_item and i.ativo
                  and (i.tipo_lancamento is null or i.tipo_lancamento = v_tl)) then
    return jsonb_build_object('ok', false, 'msg', 'Item do checklist não vale para este projeto.');
  end if;
  if coalesce(p_feito, false) then
    insert into mkt_trafego.checklist_marcas (projeto_id, item_id, marcado_por) values (p_projeto, p_item, (select auth.uid()))
    on conflict (projeto_id, item_id) do nothing;
    return jsonb_build_object('ok', true, 'msg', 'Item marcado como pronto.');
  end if;
  delete from mkt_trafego.checklist_marcas where projeto_id = p_projeto and item_id = p_item;
  return jsonb_build_object('ok', true, 'msg', 'Item desmarcado.');
end
$$;

-- Item manual do checklist: cria (sem "id") ou edita (com "id"). Campos: texto, tipo_lancamento (vazio = todos), ordem,
-- ativo (desativar tira dos projetos sem apagar as marcas).
create function public.trafego_checklist_item_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint; v_ordem smallint; v_ativo boolean;
  v_texto text := btrim(regexp_replace(coalesce(p ->> 'texto', ''), '\s+', ' ', 'g'));
  v_tl text := nullif(lower(btrim(coalesce(p ->> 'tipo_lancamento', ''))), '');
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_ordem := coalesce(nullif(btrim(coalesce(p ->> 'ordem', '')), '')::smallint, 1);
    v_ativo := coalesce((p ->> 'ativo')::boolean, true);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido.');
  end;
  if length(v_texto) < 3 or length(v_texto) > 200 then return jsonb_build_object('ok', false, 'msg', 'Texto do item: de 3 a 200 letras.'); end if;
  if v_tl is not null and not exists (select 1 from mkt.tipos_lancamento where codigo = v_tl and ativo) then
    return jsonb_build_object('ok', false, 'msg', 'Tipo de lançamento fora da lista.');
  end if;
  begin
    if v_id is null then
      insert into mkt_trafego.checklist_itens (texto, tipo_lancamento, ordem, ativo, atualizado_por)
      values (v_texto, v_tl, v_ordem, v_ativo, (select auth.uid())) returning id into v_id;
    else
      update mkt_trafego.checklist_itens set texto = v_texto, tipo_lancamento = v_tl, ordem = v_ordem, ativo = v_ativo,
             atualizado_em = now(), atualizado_por = (select auth.uid())
       where id = v_id;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
    end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Já existe este item para este tipo de lançamento.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Item do checklist salvo.', 'id', v_id);
end
$$;

-- Busca de etiqueta do ClickUp para o cadastro do projeto (revisão do Victor, 06/10/2026). p_busca vazio = todas (até o
-- limite). Casa por "contém", sem acento e sem diferença de maiúscula. Só etiquetas no formato da chave (minúsculas,
-- números e hífen): as outras não podem ser gravadas no projeto. Fontes, juntas e sem repetição:
--   kpi      kpi.medicao_tarefa.etiquetas (o que o painel de KPIs já grava; lida só se a tabela e a coluna text[] existirem)
--   trafego  mkt_trafego.clickup_etiquetas_vistas e mkt_trafego.clickup_tarefas.etiquetas (rotina trafego-clickup)
-- Ordem: igual ao digitado, depois as que começam com ele, depois alfabética. Retorna {etiquetas: [{etiqueta, fontes}],
-- fonte_kpi: bool}.
create function public.trafego_clickup_etiquetas_buscar(p_busca text default null, p_limite integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_b text := lower(mkt.sem_acento(left(btrim(coalesce(p_busca, '')), 80)));
  v_lim int := least(greatest(coalesce(p_limite, 30), 1), 200);
  v_kpi boolean;
  v_fontes text := 'select e.etiqueta, ''trafego''::text from mkt_trafego.clickup_etiquetas_vistas e '
                   'union all select x, ''trafego'' from mkt_trafego.clickup_tarefas t cross join lateral unnest(t.etiquetas) x';
  v_sql text;
  v_res jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  v_kpi := exists (select 1 from pg_attribute a
                    where a.attrelid = to_regclass('kpi.medicao_tarefa') and a.attname = 'etiquetas' and not a.attisdropped
                      and a.atttypid = 'text[]'::regtype);
  v_sql := $q$
    select coalesce(jsonb_agg(jsonb_build_object('etiqueta', y.etiqueta, 'fontes', to_jsonb(y.fontes))
                              order by y.etiqueta = $1 desc, starts_with(y.etiqueta, $1) desc, y.etiqueta), '[]'::jsonb)
      from (select z.etiqueta, array_agg(distinct z.fonte order by z.fonte) as fontes
              from (select lower(btrim(f.etiqueta)) as etiqueta, f.fonte from (%s) f(etiqueta, fonte)) z
             where z.etiqueta ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and strpos(z.etiqueta, $1) > 0
             group by z.etiqueta
             order by z.etiqueta = $1 desc, starts_with(z.etiqueta, $1) desc, z.etiqueta
             limit $2) y
  $q$;
  if v_kpi then
    begin
      execute format(v_sql, v_fontes || ' union all select x, ''kpi'' from kpi.medicao_tarefa m cross join lateral unnest(m.etiquetas) x')
        into v_res using v_b, v_lim;
    exception when insufficient_privilege or undefined_table or undefined_column then
      v_kpi := false;   -- sem acesso à fonte do KPI: segue só com a do Tráfego
    end;
  end if;
  if not v_kpi then execute format(v_sql, v_fontes) into v_res using v_b, v_lim; end if;
  return jsonb_build_object('etiquetas', v_res, 'fonte_kpi', v_kpi);
end
$$;

-- ─── 6. Entrada da rotina do ClickUp: etiquetas reais dos spaces (só service_role) ─────────────────────────────────
-- p = {"etiquetas": ["…"]} com TODAS as etiquetas dos spaces do workspace. Grava as que estão no formato da chave (o
-- resto é contado em "fora_do_formato"); quem não veio sai. Retorna {ok, gravadas, removidas, fora_do_formato}.
create function public.trafego_clickup_etiquetas_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_lista text[];
  v_fora int;
  v_rem int;
begin
  if jsonb_typeof(p -> 'etiquetas') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava a lista "etiquetas".');
  end if;
  if jsonb_array_length(p -> 'etiquetas') > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000).');
  end if;
  select coalesce(array_agg(distinct lower(btrim(x))) filter (where lower(btrim(x)) ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), '{}'),
         count(*) filter (where not (lower(btrim(x)) ~ '^[a-z0-9]+(-[a-z0-9]+)*$'))
    into v_lista, v_fora
    from jsonb_array_elements_text(p -> 'etiquetas') x;
  with apagar as (delete from mkt_trafego.clickup_etiquetas_vistas where etiqueta <> all (v_lista) returning 1)
  select count(*) into v_rem from apagar;
  insert into mkt_trafego.clickup_etiquetas_vistas (etiqueta, coletado_em) select e, now() from unnest(v_lista) e
  on conflict (etiqueta) do update set coletado_em = now();
  return jsonb_build_object('ok', true, 'gravadas', cardinality(v_lista), 'removidas', v_rem, 'fora_do_formato', v_fora);
end
$$;

-- ─── 7. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'mkt'::regnamespace and p.proname = 'projetos_tipo_unidade')
               or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('resumo', 'alertas', 'checklist'))
               or (p.pronamespace = 'public'::regnamespace
                   and p.proname in ('trafego_cadastro_listas', 'trafego_projeto_cadastro', 'trafego_projeto_salvar', 'trafego_pacote_salvar',
                                     'trafego_pacote_apagar', 'trafego_pacote_aplicar', 'trafego_clickup_etiquetas_receber',
                                     'trafego_checklist', 'trafego_checklist_marcar', 'trafego_checklist_item_salvar',
                                     'trafego_clickup_etiquetas_buscar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end
$grants$;
grant execute on function
  public.trafego_cadastro_listas(), public.trafego_projeto_cadastro(bigint), public.trafego_projeto_salvar(jsonb),
  public.trafego_pacote_salvar(jsonb), public.trafego_pacote_apagar(bigint), public.trafego_pacote_aplicar(bigint),
  public.trafego_checklist(bigint), public.trafego_checklist_marcar(bigint, bigint, boolean), public.trafego_checklist_item_salvar(jsonb),
  public.trafego_clickup_etiquetas_buscar(text, integer)
  to authenticated;
grant execute on function public.trafego_clickup_etiquetas_receber(jsonb) to service_role;

-- ─── 8. Conferência (aborta se algo nasceu aberto, fora do padrão ou se a migração perdeu dado) ─────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_tela text[] := array['trafego_cadastro_listas', 'trafego_projeto_cadastro', 'trafego_projeto_salvar', 'trafego_pacote_salvar',
                         'trafego_pacote_apagar', 'trafego_pacote_aplicar', 'trafego_checklist', 'trafego_checklist_marcar',
                         'trafego_checklist_item_salvar', 'trafego_clickup_etiquetas_buscar'];
  v_novas text[] := v_tela || array['trafego_clickup_etiquetas_receber'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt', 'usage') or has_schema_privilege(r, 'mkt_trafego', 'usage') then
      raise exception '20261006a: % tem acesso a schema mkt/mkt_trafego', r;
    end if;
  end loop;
  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relkind = 'r' and ((c.relnamespace = 'mkt'::regnamespace
                    and c.relname in ('unidades', 'tipos_lancamento', 'lancamento_regras', 'especialistas', 'projetos'))
                 or (c.relnamespace = 'mkt_trafego'::regnamespace)) loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261006a: % tem privilégio em %', r, t.relname;
      end if;
    end loop;
    if not t.relrowsecurity then raise exception '20261006a: RLS desligada em %', t.relname; end if;
  end loop;
  if (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') <> 21 then
    raise exception '20261006a: esperava 21 tabelas em mkt_trafego (15 da 20261005r + 6)';
  end if;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_novas))
               or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('resumo', 'resumo_receita', 'alertas', 'alertas_base', 'checklist', 'periodo_padrao', 'periodo_receita'))
               or (p.pronamespace = 'mkt'::regnamespace and p.proname = 'projetos_tipo_unidade') loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006a: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006a: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006a: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any (v_tela)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006a: grant de authenticated errado em %', f.sig;
    end if;
    if f.pronamespace <> 'public'::regnamespace and has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006a: service_role executa a interna %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261006a: SECURITY DEFINER errado em % (públicas sim, internas não)', f.sig;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.trafego_clickup_etiquetas_receber(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.trafego_clickup_etiquetas_receber(jsonb)', 'execute') then
    raise exception '20261006a: grant de trafego_clickup_etiquetas_receber errado';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') <> 31 then
    raise exception '20261006a: esperava 31 funções public.trafego_* (20 da 20261005p/r + 11)';
  end if;
  if (select count(*) from mkt.unidades) <> 4 or (select count(*) from mkt.tipos_lancamento) <> 5
     or (select count(*) from mkt.lancamento_regras) <> 9 or (select count(*) from mkt.especialistas) <> 2
     or (select count(*) from mkt_trafego.utm_parametros) <> 5 or (select count(*) from mkt_trafego.pacote_modelos) <> 0
     or (select count(*) from mkt_trafego.projeto_contas) <> 0 or (select count(*) from mkt_trafego.alerta_regras) <> 8
     or (select count(*) from mkt_trafego.checklist_itens) <> 1 or (select count(*) from mkt_trafego.checklist_marcas) <> 0 then
    raise exception '20261006a: semente diferente do esperado (4 unidades, 5 tipos, 9 regras, 2 especialistas, 5 UTM, pacote e contas vazios, 8 regras, 1 item manual)';
  end if;
  -- migração sem perda: a subárea de todo projeto bate com o tipo/unidade derivados
  if exists (select 1 from mkt.projetos p
              where p.subarea_trafego is distinct from case when p.tipo = 'interno' then 'interno' when p.unidade = 'aurum' then 'aurum'
                                                             when p.unidade = 'diamantes' then 'diamante' end
                 or (p.subarea_trafego is not null and p.tipo is null)) then
    raise exception '20261006a: a migração da subárea para tipo/unidade não bate';
  end if;
end
$confere$;


-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Ajudantes (temporários, somem no fim da sessão)
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.adm(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end $$;
create function pg_temp.srv(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
  execute p_sql into v;
  reset role;
  return v;
end $$;
-- salvar projeto como a tela (admin)
create function pg_temp.salvar(p jsonb) returns jsonb language sql as $$
  select pg_temp.adm(format('select public.trafego_projeto_salvar(%L::jsonb)', p)) $$;
-- o SQLSTATE de um comando direto (como postgres), ou 'nenhum'
create function pg_temp.erro(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'nenhum';
exception when others then
  return sqlstate;
end $$;
grant execute on function pg_temp.ok(text, boolean, text) to public;
create function pg_temp.proj(p_sigla text) returns bigint language sql stable as $$ select id from mkt.projetos where sigla = p_sigla $$;
create function pg_temp.linha(p_sigla text) returns jsonb language sql stable as $$
  select e from jsonb_array_elements(mkt_trafego.resumo(null)) e where e ->> 'sigla' = p_sigla $$;
create function pg_temp.camp(p_ext text) returns bigint language sql stable as $$
  select id from mkt_trafego.campanhas where campanha_externa = p_ext $$;

-- ─── 1. Estrutura, sementes e a migração da subárea ──────────────────────────────────────────────────────────────────
select pg_temp.ok('1.sementes',
  (select count(*) from mkt.unidades) = 4 and (select count(*) from mkt.tipos_lancamento) = 5
  and (select count(*) from mkt.lancamento_regras) = 9 and (select count(*) from mkt_trafego.pacote_modelos) = 0
  and (select count(*) from mkt_trafego.checklist_itens) = 1
  and (select string_agg(nome, ', ' order by nome) from mkt.especialistas) = 'Elaine Montenegro, Marcio Carvalho de Sá'
  and (select string_agg(nome, ', ' order by ordem) from mkt.unidades) = 'CSM, Escritório, Aurum, Diamantes',
  '4 unidades (CSM, Escritório, Aurum, Diamantes), 5 tipos, 9 regras, 2 especialistas internos, pacote vazio');
select pg_temp.ok('1.regras por unidade',
  (select string_agg(unidade || '=' || tipos, ' ' order by unidade) from (select r.unidade, string_agg(r.tipo_lancamento, ',' order by t.ordem) tipos
     from mkt.lancamento_regras r join mkt.tipos_lancamento t on t.codigo = r.tipo_lancamento group by r.unidade) x)
  = 'aurum=palestra csm=lancamento_classico,lancamento_pago,lpsg,atm diamantes=lancamento_classico,lancamento_pago escritorio=lancamento_classico,atm',
  'CSM: clássico, pago, LPSG, ATM; Escritório: clássico, ATM (sem pago nem LPSG); Diamantes: clássico, pago; Aurum: palestra');
select pg_temp.ok('1.utm meta',
  (select string_agg(parametro || '=' || valor, '&' order by ordem) from mkt_trafego.utm_parametros where plataforma = 'meta')
  = 'utm_source=metaads&utm_campaign={{campaign.name}}|{{campaign.id}}&utm_medium={{adset.name}}|{{adset.id}}&utm_content={{ad.name}}|{{ad.id}}&utm_term={{placement}}',
  'linha de UTM do Meta com as macros oficiais');
select pg_temp.ok('1.regra nova', exists (select 1 from mkt_trafego.alerta_regras where codigo = 'conta_fora_projeto' and ligada and limiar = 7),
  'regra conta_fora_projeto (7 dias, média) na tabela; 8 regras');
select pg_temp.ok('1.migração',
  (select count(*) filter (where subarea_trafego is not null) = count(*) filter (where tipo is not null)
          and count(*) filter (where subarea_trafego = 'interno' and (tipo <> 'interno' or unidade is not null)) = 0
          and count(*) filter (where subarea_trafego = 'aurum' and unidade is distinct from 'aurum') = 0
          and count(*) filter (where subarea_trafego = 'diamante' and unidade is distinct from 'diamantes') = 0
     from mkt.projetos),
  (select count(*) from mkt.projetos)::text || ' projeto(s) migrados: subárea igual, interno sem unidade (CSM ou Escritório não está em fonte)');

-- ─── 2. Tipo de lançamento: regra na função e no banco ───────────────────────────────────────────────────────────────
do $t$
declare v jsonb;
begin
  v := pg_temp.salvar('{"sigla":"ZW28","nome":"Projeto Ensaio Cadastro","linha":"Ensaio","tipo":"interno","unidade":"csm","tipo_lancamento":"lancamento_pago","status":"ativo","gestores":["RS","CF"],"etiqueta_clickup":"zz-ensaio-cadastro-2026-10"}');
  perform pg_temp.ok('2.interno csm pago', (v ->> 'ok')::boolean and v ->> 'tipo_lancamento' = 'lancamento_pago'
    and (select string_agg(gestor, ',' order by gestor) from mkt_trafego.projeto_gestores where projeto_id = pg_temp.proj('ZW28')) = 'CF,RS'
    and (select status from mkt_trafego.planejamento where projeto_id = pg_temp.proj('ZW28')) = 'ativo'
    and (select subarea_trafego from mkt.projetos where sigla = 'ZW28') = 'interno', 'ZW28 criado (CSM, lançamento pago, gestores CF e RS, status ativo, subárea derivada)');
  v := pg_temp.salvar('{"sigla":"ZV28","nome":"Projeto Ensaio Escritório","linha":"Ensaio","tipo":"interno","unidade":"escritorio","tipo_lancamento":"lancamento_pago"}');
  perform pg_temp.ok('2.escritório pago', not (v ->> 'ok')::boolean and v ->> 'msg' like '%não vale%', 'Escritório com lançamento pago recusado: ' || (v ->> 'msg'));
  v := pg_temp.salvar('{"sigla":"ZV28","nome":"Projeto Ensaio Escritório","linha":"Ensaio","tipo":"interno","unidade":"escritorio","tipo_lancamento":"lpsg"}');
  perform pg_temp.ok('2.escritório lpsg', not (v ->> 'ok')::boolean, 'Escritório com LPSG recusado (LPSG só na CSM)');
  v := pg_temp.salvar('{"sigla":"ZV28","nome":"Projeto Ensaio Escritório","linha":"Ensaio","tipo":"interno","unidade":"escritorio","tipo_lancamento":"atm"}');
  perform pg_temp.ok('2.escritório atm', (v ->> 'ok')::boolean, 'Escritório com ATM aceito');
  perform pg_temp.ok('2.banco recusa', pg_temp.erro($$update mkt.projetos set tipo_lancamento = 'lancamento_pago' where sigla = 'ZV28'$$) = '23503'
    and pg_temp.erro($$update mkt.projetos set tipo_lancamento = 'lpsg' where sigla = 'ZV28'$$) = '23503'
    and pg_temp.erro($$update mkt.projetos set tipo_lancamento = 'palestra' where sigla = 'ZW28'$$) = '23503'
    and pg_temp.erro($$update mkt.projetos set tipo = 'externo' where sigla = 'ZW28'$$) = '23503'
    and pg_temp.erro($$insert into mkt.projetos (sigla, nome, linha, tipo, tipo_lancamento) values ('ZQ28', 'Ensaio', 'Ensaio', 'interno', 'atm')$$) = '23514',
    'SQL direto também recusa: pago e LPSG no Escritório e palestra na CSM (23503), CSM em projeto externo (23503), tipo sem unidade (23514)');
  v := pg_temp.salvar('{"sigla":"ZU28","nome":"Palestra Ensaio","linha":"Ensaio","tipo":"externo","unidade":"aurum"}');
  perform pg_temp.ok('2.aurum sozinho', (v ->> 'ok')::boolean and v ->> 'tipo_lancamento' = 'palestra', 'Aurum sem escolher: palestra preenchida sozinha');
  insert into mkt.projetos (sigla, nome, linha, tipo, unidade) values ('ZT28', 'Palestra Ensaio Direta', 'Ensaio', 'externo', 'aurum');
  perform pg_temp.ok('2.aurum gatilho', (select tipo_lancamento from mkt.projetos where sigla = 'ZT28') = 'palestra', 'insert direto no Aurum: o gatilho preenche palestra');
  v := pg_temp.salvar('{"sigla":"ZS28","nome":"Seminário Ensaio","linha":"Ensaio","tipo":"externo","unidade":"diamantes","tipo_lancamento":"palestra"}');
  perform pg_temp.ok('2.diamantes palestra', not (v ->> 'ok')::boolean, 'Diamantes com palestra recusado');
  v := pg_temp.salvar('{"sigla":"ZS28","nome":"Seminário Ensaio","linha":"Ensaio","tipo":"externo","unidade":"diamantes"}');
  perform pg_temp.ok('2.diamantes sem escolha', (v ->> 'ok')::boolean and v -> 'tipo_lancamento' = 'null'::jsonb, 'Diamantes sem tipo: fica em branco (tem 2 opções)');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZS28'), 'sigla', 'ZS28', 'nome', 'Seminário Ensaio', 'linha', 'Ensaio', 'tipo', 'externo', 'unidade', 'diamantes', 'tipo_lancamento', 'lancamento_classico'));
  perform pg_temp.ok('2.diamantes clássico', (v ->> 'ok')::boolean and v ->> 'tipo_lancamento' = 'lancamento_classico', 'Diamantes com lançamento clássico aceito');
  v := pg_temp.salvar('{"sigla":"ZP28","nome":"Ensaio","linha":"Ensaio","tipo":"externo","unidade":"csm"}');
  perform pg_temp.ok('2.unidade do tipo', not (v ->> 'ok')::boolean and v ->> 'msg' like '%Aurum ou Diamantes%', 'CSM em projeto externo recusado: ' || (v ->> 'msg'));
  v := pg_temp.salvar('{"sigla":"ZW28","nome":"Outro","linha":"Ensaio","tipo":"interno","unidade":"csm"}');
  perform pg_temp.ok('2.sigla única', not (v ->> 'ok')::boolean and v ->> 'msg' like '%sigla ZW28%', 'sigla repetida recusada');
end
$t$;

-- ─── 3. Especialista ─────────────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; v_marcio bigint := (select id from mkt.especialistas where nome = 'Marcio Carvalho de Sá'); v_ext bigint;
begin
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZW28'), 'sigla', 'ZW28', 'nome', 'Projeto Ensaio Cadastro', 'linha', 'Ensaio',
        'tipo', 'interno', 'unidade', 'csm', 'tipo_lancamento', 'lancamento_pago', 'especialista_id', v_marcio, 'status', 'ativo',
        'etiqueta_clickup', 'zz-ensaio-cadastro-2026-10'));
  perform pg_temp.ok('3.interno da lista', (v ->> 'ok')::boolean and (select especialista_id from mkt.projetos where sigla = 'ZW28') = v_marcio, 'especialista interno escolhido da lista');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZU28'), 'sigla', 'ZU28', 'nome', 'Palestra Ensaio', 'linha', 'Ensaio', 'tipo', 'externo',
        'unidade', 'aurum', 'especialista_nome', 'Especialista Ensaio'));
  v_ext := (select especialista_id from mkt.projetos where sigla = 'ZU28');
  perform pg_temp.ok('3.externo na hora', (v ->> 'ok')::boolean and v -> 'avisos' ? 'especialista_cadastrado'
    and (select tipo || '/' || unidade from mkt.especialistas where id = v_ext) = 'externo/aurum', 'externo cadastrado na hora (tipo externo, unidade Aurum)');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZS28'), 'sigla', 'ZS28', 'nome', 'Seminário Ensaio', 'linha', 'Ensaio', 'tipo', 'externo',
        'unidade', 'diamantes', 'tipo_lancamento', 'lancamento_classico', 'especialista_nome', 'especialista  ensaio'));
  perform pg_temp.ok('3.reaproveita', (v ->> 'ok')::boolean and not (v -> 'avisos' ? 'especialista_cadastrado')
    and (select especialista_id from mkt.projetos where sigla = 'ZS28') = v_ext
    and (select count(*) from mkt.especialistas where tipo = 'externo') = 1, 'mesmo nome (maiúscula e espaço diferentes): reaproveitado, sem duplicar');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZS28'), 'sigla', 'ZS28', 'nome', 'Seminário Ensaio', 'linha', 'Ensaio', 'tipo', 'externo',
        'unidade', 'diamantes', 'especialista_id', v_marcio));
  perform pg_temp.ok('3.tipo trocado', not (v ->> 'ok')::boolean, 'especialista interno em projeto externo recusado');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZW28'), 'sigla', 'ZW28', 'nome', 'Projeto Ensaio Cadastro', 'linha', 'Ensaio',
        'tipo', 'interno', 'unidade', 'csm', 'especialista_nome', 'Pessoa Ensaio Nova'));
  perform pg_temp.ok('3.interno só lista', not (v ->> 'ok')::boolean and (select count(*) from mkt.especialistas) = 3, 'interno não cadastra pelo nome');
  perform pg_temp.ok('3.banco recusa', pg_temp.erro(format('update mkt.projetos set especialista_id = %s where sigla = %L', v_ext, 'ZW28')) = '23503',
    'SQL direto: especialista externo em projeto interno recusado (23503)');
end
$t$;

-- ─── 4. Contas do projeto: sugestões, religar pelo nome, alerta de conta de fora ───────────────────────────────────
do $t$
declare v jsonb; v_a bigint; v_b bigint; o date := mkt_trafego.ontem(); x jsonb;
begin
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"act_000661","nome":"Conta Ensaio A","dono":"grupo"}')$$);
  v_a := (v ->> 'id')::bigint;
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"act_000662","nome":"Conta Ensaio B","dono":"grupo"}')$$);
  v_b := (v ->> 'id')::bigint;
  v := pg_temp.srv($j$select public.trafego_campanhas_receber('[
    {"plataforma":"meta","conta":"000661","id":"900000000000601","nome":"RS | ZR28 | LEADS | ENSAIO CONTA A","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000662","id":"900000000000602","nome":"RS | ZR28 | LEADS | ENSAIO CONTA B","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000661","id":"900000000000603","nome":"zr28 ensaio fora do padrão","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000661","id":"900000000000604","nome":"outra zr280 ensaio","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000662","id":"900000000000605","nome":"zr28 ensaio na conta b","status":"ACTIVE"}]')$j$);
  perform pg_temp.ok('4.campanhas', (v ->> 'novas')::int = 5 and pg_temp.camp('900000000000601') is not null
    and (select projeto_id from mkt_trafego.campanhas where campanha_externa = '900000000000601') is null, '5 campanhas fictícias; ZR28 ainda não existe: sem projeto');
  v := pg_temp.srv(format('select public.trafego_desempenho_receber(%L::jsonb)', jsonb_build_array(
    jsonb_build_object('plataforma', 'meta', 'campanha', '900000000000601', 'dia', o, 'gasto', 10, 'impressoes', 100, 'cliques_link', 1),
    jsonb_build_object('plataforma', 'meta', 'campanha', '900000000000602', 'dia', o, 'gasto', 50, 'impressoes', 100, 'cliques_link', 1))));
  v := pg_temp.salvar(jsonb_build_object('sigla', 'ZR28', 'nome', 'Projeto Ensaio Contas', 'linha', 'Ensaio', 'tipo', 'interno', 'unidade', 'csm',
        'contas', jsonb_build_array(v_a)));
  perform pg_temp.ok('4.religa pelo nome', (v ->> 'ok')::boolean and (v ->> 'campanhas_relidas')::int = 2
    and (select count(*) from mkt_trafego.campanhas where projeto_id = pg_temp.proj('ZR28')) = 2,
    'criar ZR28 liga sozinho as 2 campanhas no padrão com a sigla (das duas contas)');
  x := pg_temp.adm(format('select public.trafego_projeto_cadastro(%s)', pg_temp.proj('ZR28')));
  perform pg_temp.ok('4.sugestões', (select string_agg(e ->> 'nome', ',') from jsonb_array_elements(x -> 'sugestoes') e) = 'zr28 ensaio fora do padrão'
    and x -> 'contas' = jsonb_build_array(v_a),
    'sugestão = só a fora do padrão da conta A com a sigla (ZR280 não casa; a da conta B não é sugerida)');
  x := (select a from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') a
         where a ->> 'regra' = 'conta_fora_projeto' and a ->> 'sigla' = 'ZR28');
  perform pg_temp.ok('4.alerta conta de fora', (x ->> 'valor')::numeric = 1 and x -> 'detalhe' -> 'contas' = '["Conta Ensaio B"]'::jsonb
    and x ->> 'gravidade' = 'media', 'alerta: 1 campanha da ZR28 gastando na Conta Ensaio B (fora do projeto)');
  v := pg_temp.adm(format('select public.trafego_campanha_ajustar(%L::jsonb)', jsonb_build_object('id', pg_temp.camp('900000000000603'), 'projeto_id', pg_temp.proj('ZR28'))));
  x := pg_temp.adm(format('select public.trafego_projeto_cadastro(%s)', pg_temp.proj('ZR28')));
  perform pg_temp.ok('4.ligar sugestão', jsonb_array_length(x -> 'sugestoes') = 0, 'depois de ligar, a sugestão some');
  update mkt_trafego.alerta_regras set ligada = false where codigo = 'conta_fora_projeto';
  perform pg_temp.ok('4.regra desligada', not exists (select 1 from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') a
    where a ->> 'regra' = 'conta_fora_projeto'), 'regra desligada na tabela: sem o alerta');
  update mkt_trafego.alerta_regras set ligada = true where codigo = 'conta_fora_projeto';
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZR28'), 'sigla', 'ZR28', 'nome', 'Projeto Ensaio Contas', 'linha', 'Ensaio', 'tipo', 'interno',
        'unidade', 'csm', 'contas', '[]'::jsonb));
  perform pg_temp.ok('4.sem conta não avalia', (v ->> 'ok')::boolean and not exists (select 1 from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') a
    where a ->> 'regra' = 'conta_fora_projeto'), 'projeto sem conta ligada: a regra não avalia');
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZR28'), 'sigla', 'ZR28', 'nome', 'Projeto Ensaio Contas', 'linha', 'Ensaio', 'tipo', 'interno',
        'unidade', 'csm', 'contas', jsonb_build_array(v_a, v_b)));
  perform pg_temp.ok('4.duas contas', not exists (select 1 from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') a
    where a ->> 'regra' = 'conta_fora_projeto') and (select count(*) from mkt_trafego.projeto_contas where projeto_id = pg_temp.proj('ZR28')) = 2,
    'com as duas contas no projeto: sem alerta');
  v := pg_temp.salvar(jsonb_build_object('sigla', 'ZO28', 'nome', 'Ensaio', 'linha', 'Ensaio', 'tipo', 'interno', 'unidade', 'csm', 'contas', '[999999999]'::jsonb));
  perform pg_temp.ok('4.conta inexistente', not (v ->> 'ok')::boolean, 'conta que não existe recusada');
end
$t$;

-- ─── 5. Caminho antigo (mkt_projeto_salvar da 20261005m grava só a subárea) ──────────────────────────────────────────
do $t$
declare v jsonb;
  function_sql text := 'select public.mkt_projeto_salvar(%L::jsonb)';
begin
  v := pg_temp.adm(format(function_sql, (select jsonb_build_object('id', id, 'sigla', sigla, 'nome', nome, 'linha', linha, 'etiqueta_clickup', etiqueta_clickup,
        'subarea_trafego', subarea_trafego, 'ativo', true) from mkt.projetos where sigla = 'ZW28')));
  perform pg_temp.ok('5.mesma subárea', (v ->> 'ok')::boolean
    and (select unidade || '/' || tipo_lancamento from mkt.projetos where sigla = 'ZW28') = 'csm/lancamento_pago',
    'tela antiga salva com a mesma subárea: unidade e tipo de lançamento ficam');
  v := pg_temp.adm(format(function_sql, (select jsonb_build_object('id', id, 'sigla', sigla, 'nome', nome, 'linha', linha,
        'subarea_trafego', 'diamante', 'ativo', true) from mkt.projetos where sigla = 'ZU28')));
  perform pg_temp.ok('5.aurum para diamante', (v ->> 'ok')::boolean
    and (select tipo || '/' || unidade || '/' || coalesce(tipo_lancamento, 'nulo') || '/' || (especialista_id is not null) from mkt.projetos where sigla = 'ZU28')
        = 'externo/diamantes/nulo/true', 'subárea aurum → diamante pela tela antiga: Diamantes, palestra limpa, especialista externo mantido');
  v := pg_temp.adm(format(function_sql, (select jsonb_build_object('id', id, 'sigla', sigla, 'nome', nome, 'linha', linha,
        'subarea_trafego', 'interno', 'ativo', true) from mkt.projetos where sigla = 'ZU28')));
  perform pg_temp.ok('5.externo para interno', (v ->> 'ok')::boolean
    and (select tipo || '/' || coalesce(unidade, 'nulo') || '/' || coalesce(especialista_id::text, 'nulo') from mkt.projetos where sigla = 'ZU28') = 'interno/nulo/nulo',
    'subárea → interno: tipo interno, unidade em branco, especialista externo solto');
end
$t$;

-- ─── 6. Pacote da campanha (mecanismo; conteúdo não definido) ────────────────────────────────────────────────────────
do $t$
declare v jsonb; v_id bigint;
begin
  v := pg_temp.adm(format('select public.trafego_pacote_aplicar(%s)', pg_temp.proj('ZW28')));
  perform pg_temp.ok('6.vazio', not (v ->> 'ok')::boolean and v ->> 'msg' like '%modelo vazio%', 'aplicar com o pacote vazio: avisa e não cria nada');
  v := pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"captacao","ordem":2,"objetivos":["LEADS","vendas"],"pct_verba":"70","dias":"20"}')$$);
  perform pg_temp.ok('6.salvar', (v ->> 'ok')::boolean and (select objetivos::text from mkt_trafego.pacote_modelos where id = (v ->> 'id')::bigint) = '{LEADS,VENDAS}',
    'fase do pacote salva (objetivos na forma canônica)');
  v := pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"aquecimento","ordem":1,"objetivos":["AQUECIMENTO"],"pct_verba":"30"}')$$);
  perform pg_temp.ok('6.recusas',
    not (pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"lembrete","objetivos":["XYZ"]}')$$) ->> 'ok')::boolean
    and not (pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"xyz"}')$$) ->> 'ok')::boolean
    and not (pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"nao_existe","fase":"lembrete"}')$$) ->> 'ok')::boolean
    and not (pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"captacao"}')$$) ->> 'ok')::boolean,
    'objetivo, fase e tipo fora da lista recusados; fase repetida no pacote recusada');
  v := pg_temp.adm($$select public.trafego_pacote_salvar('{"tipo_lancamento":"lancamento_pago","fase":"lembrete","pct_verba":"5"}')$$);
  perform pg_temp.ok('6.aviso 100', v -> 'avisos' ? 'pacote_acima_de_100', 'soma de % acima de 100: aviso');
  v_id := (v ->> 'id')::bigint;
  v := pg_temp.adm(format('select public.trafego_pacote_apagar(%s)', v_id));
  v := pg_temp.adm(format('select public.trafego_planejamento_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZW28'), 'status', 'ativo', 'verba_maxima', '10000')));
  v := pg_temp.adm(format('select public.trafego_pacote_aplicar(%s)', pg_temp.proj('ZW28')));
  perform pg_temp.ok('6.aplicar', (v ->> 'criadas')::int = 2
    and (select string_agg(fase || '=' || verba, ',' order by fase) from mkt_trafego.projeto_fases where projeto_id = pg_temp.proj('ZW28')) = 'aquecimento=3000.00,captacao=7000.00'
    and (select string_agg(gestor, ',' order by gestor) from mkt_trafego.projeto_gestores where projeto_id = pg_temp.proj('ZW28')) = 'CF,RS',
    'aplicar: 2 fases com 30 % e 70 % da verba máxima (10.000); gestores intactos');
  v := pg_temp.adm(format('select public.trafego_pacote_aplicar(%s)', pg_temp.proj('ZW28')));
  perform pg_temp.ok('6.reaplicar', (v ->> 'criadas')::int = 0 and (v ->> 'ja_existiam')::int = 2, 'reaplicar não duplica nem mexe');
  v := pg_temp.adm(format('select public.trafego_pacote_aplicar(%s)', pg_temp.proj('ZV28')));
  perform pg_temp.ok('6.outro tipo', not (v ->> 'ok')::boolean, 'ATM sem pacote: modelo vazio');
end
$t$;

-- ─── 7. Resumo, receita do externo, etiquetas do ClickUp ─────────────────────────────────────────────────────────────
do $t$
declare v jsonb; l jsonb;
begin
  l := pg_temp.linha('ZW28');
  perform pg_temp.ok('7.resumo', l ->> 'tipo' = 'interno' and l ->> 'unidade_nome' = 'CSM' and l ->> 'tipo_lancamento_nome' = 'Lançamento pago'
    and l ->> 'especialista' = 'Marcio Carvalho de Sá' and (l ->> 'receita_aplica')::boolean and l ->> 'subarea' = 'interno'
    and pg_temp.linha('ZR28') -> 'contas_projeto' = (select jsonb_agg(conta_id order by conta_id) from mkt_trafego.projeto_contas where projeto_id = pg_temp.proj('ZR28')),
    'linha do resumo com tipo, unidade, tipo de lançamento, especialista e contas');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZS28'), 'produto_id', '9990601', 'de', '2026-01-01')));
  l := pg_temp.linha('ZS28');
  perform pg_temp.ok('7.receita externo', (v ->> 'ok')::boolean and l -> 'receita' = 'null'::jsonb and not (l ->> 'receita_aplica')::boolean
    and l ->> 'tipo' = 'externo', 'externo com produto ligado: receita nula e "não se aplica"');
  v := pg_temp.srv($$select public.trafego_clickup_etiquetas_receber('{"etiquetas":["zz-ensaio-b","ZZ-Ensaio-A","com espaço"," zz-ensaio-a"]}')$$);
  perform pg_temp.ok('7.etiquetas', (v ->> 'gravadas')::int = 2 and (v ->> 'fora_do_formato')::int = 1
    and pg_temp.adm('select public.trafego_cadastro_listas()') -> 'etiquetas_clickup' = '["zz-ensaio-a","zz-ensaio-b"]'::jsonb,
    'etiquetas dos spaces: 2 no formato (minúsculas, sem repetição), 1 fora do formato não entra');
  v := pg_temp.srv($$select public.trafego_clickup_etiquetas_receber('{"etiquetas":["zz-ensaio-b"]}')$$);
  perform pg_temp.ok('7.etiquetas some', (v ->> 'removidas')::int = 1 and (select count(*) from mkt_trafego.clickup_etiquetas_vistas) = 1, 'quem não veio sai da lista');
  v := pg_temp.salvar('{"sigla":"ZN28","nome":"Ensaio","linha":"Ensaio","tipo":"interno","unidade":"csm","etiqueta_clickup":"Etiqueta Errada"}');
  perform pg_temp.ok('7.etiqueta formato', not (v ->> 'ok')::boolean, 'etiqueta fora do formato da chave recusada');
  v := pg_temp.salvar('{"sigla":"ZN28","nome":"Ensaio","linha":"Ensaio","tipo":"interno","unidade":"csm","etiqueta_clickup":"zz-ensaio-sem-data","fim":"2026-12-31"}');
  perform pg_temp.ok('7.etiqueta sem ano-mês', (v ->> 'ok')::boolean and v -> 'avisos' ? 'etiqueta_sem_ano_mes', 'edição com fim e etiqueta sem -aaaa-mm: aceita com aviso');
  v := pg_temp.adm('select public.trafego_cadastro_listas()');
  perform pg_temp.ok('7.listas', jsonb_array_length(v -> 'unidades') = 4 and v -> 'regras' -> 'escritorio' = '["lancamento_classico","atm"]'::jsonb
    and jsonb_array_length(v -> 'utm' -> 'meta') = 5 and jsonb_array_length(v -> 'pacotes') = 2
    and jsonb_array_length(pg_temp.adm('select public.trafego_alertas()') -> 'regras') = 8, 'listas da tela (unidades, regras, UTM, pacote) e 8 regras no resumo do dia');
end
$t$;

-- ─── 9. Períodos de captação e evento ───────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; x jsonb;
begin
  v := pg_temp.salvar('{"sigla":"ZM28","nome":"Projeto Ensaio Períodos","linha":"Ensaio","tipo":"interno","unidade":"csm","tipo_lancamento":"lancamento_pago","captacao_inicio":"2026-11-01","captacao_fim":"2026-11-20","evento_inicio":"2026-11-25","evento_fim":"2026-11-27"}');
  perform pg_temp.ok('9.períodos', (v ->> 'ok')::boolean
    and (select inicio || '/' || fim from mkt.projetos where sigla = 'ZM28') = '2026-11-01/2026-11-27'
    and (select inicio || '/' || fim from mkt_trafego.periodo_padrao(pg_temp.proj('ZM28'))) = '2026-11-01/2026-11-20',
    'captação 01 a 20/11 e evento 25 a 27/11: projeto 01 a 27/11; período padrão = a captação');
  insert into mkt.projetos (sigla, nome, linha, inicio, fim) values ('ZL28', 'Projeto Ensaio Datas Antigas', 'Ensaio', '2026-03-01', '2026-03-31');
  perform pg_temp.ok('9.datas antigas', (select inicio || '/' || fim from mkt.projetos where sigla = 'ZL28') = '2026-03-01/2026-03-31'
    and (select inicio || '/' || fim from mkt_trafego.periodo_padrao(pg_temp.proj('ZL28'))) = '2026-03-01/2026-03-31',
    'projeto só com início/fim de antes: datas mantidas e usadas como período padrão (nada se perde)');
  v := pg_temp.salvar('{"sigla":"ZK28","nome":"Ensaio","linha":"Ensaio","tipo":"interno","unidade":"csm","captacao_inicio":"2026-11-01"}');
  perform pg_temp.ok('9.período pela metade', not (v ->> 'ok')::boolean, 'captação só com início recusada');
  v := pg_temp.salvar('{"sigla":"ZK28","nome":"Ensaio","linha":"Ensaio","tipo":"interno","unidade":"csm","evento_inicio":"2026-11-10","evento_fim":"2026-11-01"}');
  perform pg_temp.ok('9.evento invertido', not (v ->> 'ok')::boolean, 'evento com fim antes do início recusado');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZM28'), 'produto_id', '9990602')));
  x := pg_temp.adm(format('select public.trafego_produtos_listar(%s)', pg_temp.proj('ZM28'))) -> 0;
  perform pg_temp.ok('9.receita padrão', (v ->> 'ok')::boolean and not (v -> 'avisos' ? 'sem_periodo')
    and x ->> 'de_efetivo' = '2026-11-01' and x ->> 'ate_efetivo' = '2026-11-27'
    and (select inicio || '/' || fim from mkt_trafego.periodo_receita(pg_temp.proj('ZL28'))) = '2026-03-01/2026-03-31',
    'produto sem período: do início da captação (01/11) ao fim do evento (27/11); projeto só com datas antigas usa as antigas');
  v := pg_temp.adm(format('select public.trafego_pacote_aplicar(%s)', pg_temp.proj('ZM28')));
  perform pg_temp.ok('9.fase de captação', (v ->> 'criadas')::int = 2
    and (select inicio || '/' || fim from mkt_trafego.projeto_fases where projeto_id = pg_temp.proj('ZM28') and fase = 'captacao') = '2026-11-01/2026-11-20'
    and (select inicio from mkt_trafego.projeto_fases where projeto_id = pg_temp.proj('ZM28') and fase = 'aquecimento') is null,
    'pacote aplicado: a fase de captação nasce com o período de captação; a outra em branco');
  x := pg_temp.linha('ZM28');
  perform pg_temp.ok('9.resumo', x ->> 'captacao_inicio' = '2026-11-01' and x ->> 'evento_fim' = '2026-11-27', 'resumo com os dois períodos');
end
$t$;

-- ─── 10. Checklist de montagem ───────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; c jsonb; v_item bigint := (select id from mkt_trafego.checklist_itens limit 1); v_novo bigint;
begin
  perform pg_temp.ok('10.semente', (select texto from mkt_trafego.checklist_itens) = 'Automação de ingresso no grupo do WhatsApp configurada no SendFlow'
    and (select tipo_lancamento from mkt_trafego.checklist_itens) is null, 'semente manual: só o exemplo do Victor, para todos os tipos');
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZR28')));
  perform pg_temp.ok('10.automáticos',
    (select string_agg(e ->> 'codigo' || '=' || (e ->> 'ok'), ',' order by e ->> 'codigo') from jsonb_array_elements(c -> 'automaticos') e)
      = 'campanhas=true,contas=true,etiqueta=false,fases=false,fases_campanhas=false,fora_padrao=false,hotmart=false,metas=false,paginas=false,verba=false'
    and (c ->> 'feitos')::int = 2 and (c ->> 'total')::int = 11,
    'ZR28: contas e campanhas ok; 1 fora do padrão e sem fase; o resto vazio; 2 de 11');
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZS28')));
  perform pg_temp.ok('10.externo', (c ->> 'total')::int = 8
    and not ((select e from jsonb_array_elements(c -> 'automaticos') e where e ->> 'codigo' = 'hotmart') ->> 'aplica')::boolean,
    'externo sem campanha: Hotmart, fora do padrão e fase das campanhas não se aplicam (8 itens)');
  v := pg_temp.adm(format('select public.trafego_checklist_marcar(%s, %s, true)', pg_temp.proj('ZR28'), v_item));
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZR28')));
  perform pg_temp.ok('10.marcar', (v ->> 'ok')::boolean and (c ->> 'feitos')::int = 3
    and (c -> 'manuais' -> 0 ->> 'marcado_por') = 'Victor (local)' and c -> 'manuais' -> 0 ->> 'marcado_em' is not null
    and (pg_temp.linha('ZR28') ->> 'checklist_feitos')::int = 3 and (pg_temp.linha('ZR28') ->> 'checklist_total')::int = 11,
    'item manual marcado: quem e quando guardados; 3 de 11 também no resumo');
  v := pg_temp.adm(format('select public.trafego_checklist_marcar(%s, %s, false)', pg_temp.proj('ZR28'), v_item));
  perform pg_temp.ok('10.desmarcar', (pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZR28'))) ->> 'feitos')::int = 2, 'desmarcado: volta a 2');
  v := pg_temp.adm($$select public.trafego_checklist_item_salvar('{"texto":"Item Ensaio do lançamento pago","tipo_lancamento":"lancamento_pago","ordem":2}')$$);
  v_novo := (v ->> 'id')::bigint;
  perform pg_temp.ok('10.por tipo', (v ->> 'ok')::boolean
    and jsonb_array_length(pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZW28'))) -> 'manuais') = 2
    and jsonb_array_length(pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZV28'))) -> 'manuais') = 1
    and not (pg_temp.adm(format('select public.trafego_checklist_marcar(%s, %s, true)', pg_temp.proj('ZV28'), v_novo)) ->> 'ok')::boolean,
    'item do lançamento pago: aparece no ZW28 (pago), não no ZV28 (ATM), e não se marca lá');
  perform pg_temp.ok('10.recusas', not (pg_temp.adm($$select public.trafego_checklist_item_salvar('{"texto":"Item Ensaio do lançamento pago","tipo_lancamento":"lancamento_pago"}')$$) ->> 'ok')::boolean
    and not (pg_temp.adm($$select public.trafego_checklist_item_salvar('{"texto":"ab"}')$$) ->> 'ok')::boolean
    and not (pg_temp.adm($$select public.trafego_checklist_item_salvar('{"texto":"Outro item","tipo_lancamento":"xyz"}')$$) ->> 'ok')::boolean,
    'item repetido, texto curto e tipo fora da lista recusados');
  v := pg_temp.adm(format('select public.trafego_checklist_item_salvar(%L::jsonb)', jsonb_build_object('id', v_novo, 'texto', 'Item Ensaio do lançamento pago', 'tipo_lancamento', 'lancamento_pago', 'ativo', false)));
  perform pg_temp.ok('10.desativar', jsonb_array_length(pg_temp.adm(format('select public.trafego_checklist(%s)', pg_temp.proj('ZW28'))) -> 'manuais') = 1,
    'item desativado sai do checklist');
end
$t$;

-- ─── 11. Revisão de 06/10: linha opcional e busca de etiqueta do ClickUp ────────────────────────────────────────────
do $t$
declare v jsonb; v_real boolean := to_regclass('kpi.medicao_tarefa') is not null;
begin
  v := pg_temp.salvar('{"sigla":"ZJ28","nome":"Projeto Ensaio Sem Linha","tipo":"interno","unidade":"csm"}');
  perform pg_temp.ok('11.sem linha', (v ->> 'ok')::boolean and (select linha from mkt.projetos where sigla = 'ZJ28') = 'Projeto Ensaio Sem Linha',
    'projeto novo sem linha: aceito, a linha (obrigatória na 20261005m) grava o nome');
  update mkt.projetos set linha = 'Linha Ensaio' where sigla = 'ZJ28';
  v := pg_temp.salvar(jsonb_build_object('id', pg_temp.proj('ZJ28'), 'sigla', 'ZJ28', 'nome', 'Projeto Ensaio Renomeado', 'tipo', 'interno', 'unidade', 'csm'));
  perform pg_temp.ok('11.edição sem linha', (v ->> 'ok')::boolean and (select linha || '/' || nome from mkt.projetos where sigla = 'ZJ28') = 'Linha Ensaio/Projeto Ensaio Renomeado',
    'edição sem linha: a linha de antes fica');
  v := pg_temp.salvar('{"sigla":"ZI28","nome":"Ensaio","linha":"X","tipo":"interno","unidade":"csm"}');
  perform pg_temp.ok('11.linha curta', not (v ->> 'ok')::boolean, 'linha mandada com 1 letra: recusada (quem ainda manda, manda certo)');

  if not v_real then
    create schema if not exists kpi;
    create table kpi.medicao_tarefa (id int, etiquetas text[]);
    insert into kpi.medicao_tarefa values (1, array['zz-ensaio-seminario-atm', 'zz-ensaio-seminario-conjunto']),
      (2, array['zz-ensaio-seminario-conjunto', 'ZZ-Ensaio-Seminario-Zanella', 'zz ensaio fora do formato']), (3, '{}');
  end if;
  insert into mkt_trafego.clickup_etiquetas_vistas (etiqueta) values ('zz-ensaio-seminario-conjunto'), ('zz-ensaio-so-trafego')
  on conflict do nothing;
  v := pg_temp.adm($$select public.trafego_clickup_etiquetas_buscar('ZZ-Ensaio-SEMINÁRIO')$$);
  perform pg_temp.ok('11.busca', (v ->> 'fonte_kpi')::boolean
    and not exists (select 1 from jsonb_array_elements(v -> 'etiquetas') e
                     where strpos(e ->> 'etiqueta', 'zz-ensaio-seminario') = 0 or e ->> 'etiqueta' !~ '^[a-z0-9]+(-[a-z0-9]+)*$')
    and (v_real or (select string_agg(e ->> 'etiqueta' || ':' || (e -> 'fontes')::text, ' ' order by o)
                      from jsonb_array_elements(v -> 'etiquetas') with ordinality x(e, o))
                   = 'zz-ensaio-seminario-atm:["kpi"] zz-ensaio-seminario-conjunto:["kpi", "trafego"] zz-ensaio-seminario-zanella:["kpi"]'),
    '"ZZ-Ensaio-SEMINÁRIO" acha as que contêm, sem acento e sem maiúscula, das duas fontes, sem repetir; fora do formato não entra'
    || case when v_real then ' (kpi.medicao_tarefa real: ' || jsonb_array_length(v -> 'etiquetas') || ' achadas)' else '' end);
  v := pg_temp.adm($$select public.trafego_clickup_etiquetas_buscar('zz-ensaio-seminario-conjunto')$$);
  perform pg_temp.ok('11.igual primeiro', v -> 'etiquetas' -> 0 ->> 'etiqueta' = 'zz-ensaio-seminario-conjunto', 'a igual ao digitado vem primeiro');
  v := pg_temp.adm($$select public.trafego_clickup_etiquetas_buscar('zz-ensaio-nao-existe')$$);
  perform pg_temp.ok('11.não achou', v -> 'etiquetas' = '[]'::jsonb, 'etiqueta que não está no ClickUp: lista vazia (a tela avisa e deixa salvar)');
  v := pg_temp.adm($$select public.trafego_clickup_etiquetas_buscar('', 2)$$);
  perform pg_temp.ok('11.limite', jsonb_array_length(v -> 'etiquetas') <= 2, 'busca vazia respeita o limite');
  v := pg_temp.adm($$select public.trafego_clickup_etiquetas_buscar('zz-ensaio-so-trafego')$$);
  perform pg_temp.ok('11.só tráfego', v -> 'etiquetas' -> 0 -> 'fontes' = '["trafego"]'::jsonb, 'a do espelho do ClickUp do Tráfego também entra');
end
$t$;

-- ─── 8. Grants e recusas ─────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('8.grants',
  not has_function_privilege('anon', 'public.trafego_projeto_salvar(jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.trafego_projeto_salvar(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.trafego_clickup_etiquetas_receber(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.trafego_clickup_etiquetas_receber(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'mkt_trafego.alertas()', 'execute')
  and not has_table_privilege('authenticated', 'mkt.unidades', 'select'),
  'anon nada; tela authenticated; etiquetas_receber só service_role; internas e tabelas fechadas');
do $t$
declare
  c text; u text; v_papel text;
  v_chamadas text[] := array[
    'select public.trafego_cadastro_listas()',
    'select public.trafego_projeto_cadastro(1)',
    'select public.trafego_projeto_salvar(''{}'')',
    'select public.trafego_pacote_salvar(''{}'')',
    'select public.trafego_pacote_apagar(1)',
    'select public.trafego_pacote_aplicar(1)',
    'select public.trafego_clickup_etiquetas_receber(''{}'')',
    'select public.trafego_checklist(1)',
    'select public.trafego_checklist_marcar(1, 1, true)',
    'select public.trafego_checklist_item_salvar(''{}'')',
    'select public.trafego_clickup_etiquetas_buscar(''seminario'')',
    'select count(*) from mkt_trafego.checklist_marcas',
    'select count(*) from mkt.unidades',
    'select count(*) from mkt.especialistas',
    'select count(*) from mkt_trafego.projeto_contas',
    'select count(*) from mkt_trafego.pacote_modelos'];
  v_ok int; v_errado text;
begin
  foreach u in array array['00000000-0000-4000-8000-0000000000ff:authenticated', '22222222-2222-4222-8222-222222222222:authenticated',
                           '33333333-3333-4333-8333-333333333333:authenticated', '00000000-0000-4000-8000-0000000000ff:anon'] loop
    v_papel := split_part(u, ':', 2);
    perform set_config('request.jwt.claims', '{"sub":"' || split_part(u, ':', 1) || '","role":"' || v_papel || '"}', true);
    v_ok := 0; v_errado := null;
    foreach c in array v_chamadas loop
      begin
        execute format('set local role %I', v_papel);
        execute c;
        reset role;
        v_errado := concat_ws(', ', v_errado, c);
      exception when insufficient_privilege then
        reset role;
        v_ok := v_ok + 1;
      end;
    end loop;
    perform pg_temp.ok('8.' || case split_part(u, ':', 1) when '33333333-3333-4333-8333-333333333333' then 'visualizador'
                                 when '22222222-2222-4222-8222-222222222222' then 'operador'
                                 else 'sem perfil' end || ' ' || v_papel,
                       v_errado is null, v_ok || ' recusas 42501' || coalesce(' / PASSOU: ' || v_errado, ''));
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
