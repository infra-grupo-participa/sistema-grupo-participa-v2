-- 20261006l: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da 20261006j
--   (e, por ela, da 20261006g e da 20261006i). Todo resultado vai para a tabela temporária _z_out; o penúltimo comando
--   mostra tudo. Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia,
--   e rode o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006l_mkt_trafego_modelos.sql, das guardas
-- até antes da REVERSÃO). Depois dele, os testes criam DADOS FICTÍCIOS (projetos ZD28 "Projeto Ensaio Modelo" e ZE28,
-- modelos "Modelo Ensaio …", conta act_000881 "Conta Ensaio D", campanhas 9000000008xx, itens "Item Ensaio …") e chamam
-- as funções como a tela e como quem não pode (JWT simulado). Tudo some no rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO".
--   1 estrutura e mockups: um exemplo rascunho e padrão por combinação válida, 100% de verba, SendFlow onde há captação
--     (grupo de leads com campanha LEADS, grupo de compradores com VENDAS),
--     pacote e checklist antigos fora
--   2 salvar modelo: novo padrão tira o padrão do exemplo; recusas (LPSG no Escritório, nome repetido, fase repetida)
--   3 duplicar e inativar
--   4 prévia e aplicar no projeto: datas relativas, verba pela verba máxima, fase que já existe só muda confirmando,
--     nada apagado, modelo de outra unidade recusado
--   5 checklist que leva à ação: momento e ação de cada item, campanhas esperadas × encontradas, itens do projeto
--   6 resumo do dia: em captação com checklist incompleto (e em planejamento fica fora)
--   7 listas e cadastro com "modelos"/"modelo"; grants e recusa 42501

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('mkt_trafego.modelos') is not null then raise exception '20261006l: já aplicada (mkt_trafego.modelos existe)'; end if;
  if to_regclass('mkt_trafego.pacote_modelos') is null or to_regclass('mkt_trafego.checklist_itens') is null
     or to_regprocedure('mkt_trafego.checklist(bigint)') is null or to_regclass('mkt.lancamento_regras') is null then
    raise exception '20261006l: falta a 20261006j (pacote_modelos, checklist_itens, checklist, lancamento_regras)';
  end if;
  if exists (select 1 from mkt_trafego.pacote_modelos) or exists (select 1 from mkt_trafego.checklist_marcas) then
    raise exception '20261006l: o pacote ou as marcas do checklist da 20261006j têm dado: migrar à mão antes (nada é apagado com dado)';
  end if;
  if exists (select 1 from mkt_trafego.checklist_itens
              where texto <> 'Automação de ingresso no grupo do WhatsApp configurada no SendFlow') then
    raise exception '20261006l: checklist_itens tem item além da semente da 20261006j: migrar à mão antes (nada é apagado com dado)';
  end if;
end
$guarda$;

-- ─── 1. Sai o pacote e o checklist manual global da 20261006j ────────────────────────────────────────────────────────
drop function public.trafego_pacote_salvar(jsonb);
drop function public.trafego_pacote_apagar(bigint);
drop function public.trafego_pacote_aplicar(bigint);
drop function public.trafego_checklist_marcar(bigint, bigint, boolean);
drop function public.trafego_checklist_item_salvar(jsonb);

-- ─── 2. Modelos ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt_trafego.modelos (
  id              bigint generated always as identity primary key,
  nome            text not null check (length(btrim(nome)) between 3 and 80),
  tipo_lancamento text not null references mkt.tipos_lancamento(codigo) on delete restrict,
  ativo           boolean not null default true,
  rascunho        boolean not null default false,
  meta_cpl        numeric(14,2) check (meta_cpl is null or meta_cpl > 0),
  meta_pct_mql    numeric(5,2) check (meta_pct_mql is null or meta_pct_mql between 0 and 100),
  obs             text check (obs is null or length(obs) <= 1000),
  criado_em       timestamptz not null default now(),
  criado_por      uuid references public.perfis(id) on delete set null,
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid references public.perfis(id) on delete set null,
  constraint modelos_id_tipo unique (id, tipo_lancamento)
);
create unique index modelos_nome_unico on mkt_trafego.modelos (lower(btrim(nome)));
comment on table mkt_trafego.modelos is
  'Modelo de lançamento (Victor, 06/10/2026): nome livre, tipo de lançamento, unidades (modelo_unidades), fases, campanhas '
  'esperadas, itens do checklist e metas padrão (CPL e % MQL). Vários por tipo; rascunho = exemplo a validar. 20261006l.';

create table mkt_trafego.modelo_unidades (
  modelo_id       bigint not null,
  tipo_lancamento text not null,
  unidade         text not null,
  padrao          boolean not null default false,
  primary key (modelo_id, unidade),
  constraint modelo_unidades_modelo_fk foreign key (modelo_id, tipo_lancamento)
    references mkt_trafego.modelos(id, tipo_lancamento) on delete cascade on update cascade,
  constraint modelo_unidades_regra_fk foreign key (unidade, tipo_lancamento)
    references mkt.lancamento_regras(unidade, tipo_lancamento) on delete restrict
);
create unique index modelo_unidades_padrao on mkt_trafego.modelo_unidades (tipo_lancamento, unidade) where padrao;
comment on table mkt_trafego.modelo_unidades is
  'Unidades a que o modelo se aplica. O banco recusa combinação tipo × unidade fora de mkt.lancamento_regras. padrao = o '
  'modelo sugerido primeiro para aquele tipo + unidade (no máximo um). 20261006l.';

create table mkt_trafego.modelo_fases (
  id          bigint generated always as identity primary key,
  modelo_id   bigint not null references mkt_trafego.modelos(id) on delete cascade,
  fase        text not null references mkt_trafego.fases(codigo) on delete restrict,
  ordem       smallint not null default 1,
  inicio_ref  text check (inicio_ref is null or inicio_ref in ('captacao_inicio', 'captacao_fim', 'evento_inicio', 'evento_fim')),
  inicio_dias smallint not null default 0 check (inicio_dias between -365 and 365),
  fim_ref     text check (fim_ref is null or fim_ref in ('captacao_inicio', 'captacao_fim', 'evento_inicio', 'evento_fim')),
  fim_dias    smallint not null default 0 check (fim_dias between -365 and 365),
  pct_verba   numeric(5,2) check (pct_verba is null or pct_verba between 0 and 100),
  obs         text check (obs is null or length(obs) <= 300),
  constraint modelo_fases_unica unique (modelo_id, fase)
);
comment on table mkt_trafego.modelo_fases is
  'Fases do modelo. Datas relativas: referência (início/fim da captação ou do evento do projeto) + N dias (negativo = antes). '
  'pct_verba = % da verba máxima do projeto. 20261006l.';

create table mkt_trafego.modelo_campanhas (
  id        bigint generated always as identity primary key,
  modelo_id bigint not null references mkt_trafego.modelos(id) on delete cascade,
  objetivo  text not null references mkt.campanha_objetivos(codigo) on delete restrict on update cascade,
  fase      text references mkt_trafego.fases(codigo) on delete restrict,
  descricao text check (descricao is null or length(btrim(descricao)) between 1 and 120),
  pagina    text check (pagina is null or pagina ~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$'),
  ordem     smallint not null default 1
);
create index modelo_campanhas_modelo_idx on mkt_trafego.modelo_campanhas (modelo_id);
comment on table mkt_trafego.modelo_campanhas is
  'Campanhas esperadas do modelo (objetivo, fase, descrição sugerida, página opcional). O gerador de nome usa; o checklist '
  'compara com as campanhas do projeto. 20261006l.';

create table mkt_trafego.modelo_itens (
  id        bigint generated always as identity primary key,
  modelo_id bigint not null references mkt_trafego.modelos(id) on delete cascade,
  texto     text not null check (length(btrim(texto)) between 3 and 200),
  momento   text not null check (momento in ('antes', 'durante', 'encerramento')),
  ordem     smallint not null default 1
);
create unique index modelo_itens_unico on mkt_trafego.modelo_itens (modelo_id, lower(btrim(texto)));
comment on table mkt_trafego.modelo_itens is
  'Itens manuais do checklist do modelo, com o momento: antes de subir as campanhas, durante, encerramento. 20261006l.';

-- ─── 3. O que o projeto recebeu ──────────────────────────────────────────────────────────────────────────────────────
create table mkt_trafego.projeto_modelo (
  projeto_id   bigint primary key references mkt.projetos(id) on delete restrict,
  modelo_id    bigint references mkt_trafego.modelos(id) on delete set null,
  modelo_nome  text not null,
  aplicado_em  timestamptz not null default now(),
  aplicado_por uuid references public.perfis(id) on delete set null
);
comment on table mkt_trafego.projeto_modelo is 'Último modelo aplicado no projeto (o nome fica guardado mesmo se o modelo for apagado). 20261006l.';

create table mkt_trafego.projeto_campanhas_esperadas (
  id         bigint generated always as identity primary key,
  projeto_id bigint not null references mkt.projetos(id) on delete restrict,
  objetivo   text not null references mkt.campanha_objetivos(codigo) on delete restrict on update cascade,
  fase       text references mkt_trafego.fases(codigo) on delete restrict,
  descricao  text check (descricao is null or length(btrim(descricao)) between 1 and 120),
  pagina     text check (pagina is null or pagina ~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$'),
  ordem      smallint not null default 1,
  modelo_id  bigint references mkt_trafego.modelos(id) on delete set null,
  criado_em  timestamptz not null default now(),
  criado_por uuid references public.perfis(id) on delete set null
);
create index projeto_esperadas_projeto_idx on mkt_trafego.projeto_campanhas_esperadas (projeto_id);
comment on table mkt_trafego.projeto_campanhas_esperadas is
  'Campanhas que o projeto deve ter (copiadas do modelo ao aplicar; o projeto fica estável se o modelo mudar). Criada = há '
  'campanha do projeto com o mesmo objetivo (e a mesma página, se houver), contadas por objetivo. 20261006l.';

create table mkt_trafego.projeto_itens (
  id         bigint generated always as identity primary key,
  projeto_id bigint not null references mkt.projetos(id) on delete restrict,
  texto      text not null check (length(btrim(texto)) between 3 and 200),
  momento    text not null check (momento in ('antes', 'durante', 'encerramento')),
  ordem      smallint not null default 1,
  modelo_id  bigint references mkt_trafego.modelos(id) on delete set null,
  feito_em   timestamptz,
  feito_por  uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now(),
  criado_por uuid references public.perfis(id) on delete set null
);
create unique index projeto_itens_unico on mkt_trafego.projeto_itens (projeto_id, lower(btrim(texto)));
comment on table mkt_trafego.projeto_itens is
  'Itens manuais do checklist do projeto (do modelo ou criados na hora). feito_em/feito_por = marcado como pronto. 20261006l.';

alter table mkt_trafego.modelos enable row level security;
alter table mkt_trafego.modelo_unidades enable row level security;
alter table mkt_trafego.modelo_fases enable row level security;
alter table mkt_trafego.modelo_campanhas enable row level security;
alter table mkt_trafego.modelo_itens enable row level security;
alter table mkt_trafego.projeto_modelo enable row level security;
alter table mkt_trafego.projeto_campanhas_esperadas enable row level security;
alter table mkt_trafego.projeto_itens enable row level security;
revoke all on mkt_trafego.modelos, mkt_trafego.modelo_unidades, mkt_trafego.modelo_fases, mkt_trafego.modelo_campanhas,
              mkt_trafego.modelo_itens, mkt_trafego.projeto_modelo, mkt_trafego.projeto_campanhas_esperadas,
              mkt_trafego.projeto_itens from public, anon, authenticated;

-- o pacote e o checklist global saem (vazios: a guarda conferiu)
drop table mkt_trafego.checklist_marcas, mkt_trafego.checklist_itens, mkt_trafego.pacote_modelos;

-- ─── 4. Mockups: um modelo de EXEMPLO por combinação válida (rascunho a validar; números genéricos) ─────────────────
do $semente$
declare
  r record;
  v_id bigint;
begin
  for r in select lr.unidade, lr.tipo_lancamento, u.nome as unidade_nome, t.nome as tipo_nome
             from mkt.lancamento_regras lr
             join mkt.unidades u on u.codigo = lr.unidade
             join mkt.tipos_lancamento t on t.codigo = lr.tipo_lancamento
            order by u.ordem, t.ordem loop
    insert into mkt_trafego.modelos (nome, tipo_lancamento, rascunho, obs)
    values ('Exemplo: ' || r.tipo_nome || ' ' || r.unidade_nome, r.tipo_lancamento, true,
            'Modelo de EXEMPLO para editar: fases, datas e percentuais genéricos, não são decisão de ninguém. Validar antes de usar.')
    returning id into v_id;
    insert into mkt_trafego.modelo_unidades (modelo_id, tipo_lancamento, unidade, padrao) values (v_id, r.tipo_lancamento, r.unidade, true);
    -- fases: (fase, ordem, ref início, dias, ref fim, dias, %)
    insert into mkt_trafego.modelo_fases (modelo_id, fase, ordem, inicio_ref, inicio_dias, fim_ref, fim_dias, pct_verba)
    select v_id, f.fase, f.ordem, f.ir, f.id_, f.fr, f.fd, f.pct
      from (values
        ('lancamento_classico', 'aquecimento', 1, 'captacao_inicio', -7, 'captacao_inicio', -1, 10),
        ('lancamento_classico', 'captacao', 2, 'captacao_inicio', 0, 'captacao_fim', 0, 60),
        ('lancamento_classico', 'lembrete', 3, 'evento_inicio', -2, 'evento_inicio', 0, 10),
        ('lancamento_classico', 'remarketing', 4, 'captacao_inicio', 0, 'evento_fim', 0, 10),
        ('lancamento_classico', 'abertura_carrinho', 5, 'evento_fim', 0, 'evento_fim', 3, 10),
        ('lancamento_pago', 'aquecimento', 1, 'captacao_inicio', -7, 'captacao_inicio', -1, 10),
        ('lancamento_pago', 'captacao', 2, 'captacao_inicio', 0, 'captacao_fim', 0, 60),
        ('lancamento_pago', 'lembrete', 3, 'evento_inicio', -2, 'evento_inicio', 0, 10),
        ('lancamento_pago', 'remarketing', 4, 'captacao_inicio', 0, 'evento_fim', 0, 10),
        ('lancamento_pago', 'abertura_carrinho', 5, 'evento_fim', 0, 'evento_fim', 3, 10),
        ('lpsg', 'captacao', 1, 'captacao_inicio', 0, 'captacao_fim', 0, 70),
        ('lpsg', 'lembrete', 2, 'evento_inicio', -2, 'evento_inicio', 0, 10),
        ('lpsg', 'remarketing', 3, 'captacao_inicio', 0, 'evento_fim', 0, 10),
        ('lpsg', 'abertura_carrinho', 4, 'evento_fim', 0, 'evento_fim', 3, 10),
        ('atm', 'aquecimento', 1, 'evento_inicio', -7, 'evento_inicio', -1, 30),
        ('atm', 'abertura_carrinho', 2, 'evento_inicio', 0, 'evento_fim', 0, 50),
        ('atm', 'remarketing', 3, 'evento_inicio', 0, 'evento_fim', 0, 20),
        ('palestra', 'captacao', 1, 'captacao_inicio', 0, 'captacao_fim', 0, 70),
        ('palestra', 'lembrete', 2, 'evento_inicio', -2, 'evento_inicio', 0, 20),
        ('palestra', 'remarketing', 3, 'captacao_inicio', 0, 'evento_fim', 0, 10)
      ) f(tipo, fase, ordem, ir, id_, fr, fd, pct)
     where f.tipo = r.tipo_lancamento and exists (select 1 from mkt_trafego.fases x where x.codigo = f.fase);
    -- campanhas esperadas: um objetivo por fase (o mapa objetivo → fase que já existe; captação no pago e no LPSG = VENDAS)
    insert into mkt_trafego.modelo_campanhas (modelo_id, objetivo, fase, ordem)
    select v_id, o.objetivo, mf.fase, mf.ordem
      from mkt_trafego.modelo_fases mf
      cross join lateral (select case mf.fase
                                   when 'captacao' then case when r.tipo_lancamento in ('lancamento_pago', 'lpsg') then 'VENDAS' else 'LEADS' end
                                   when 'aquecimento' then 'AQUECIMENTO' when 'antecipacao' then 'ANTECIPAÇÃO' when 'lembrete' then 'LEMBRETE'
                                   when 'remarketing' then 'REMARKETING' when 'abertura_carrinho' then 'CARRINHO' end as objetivo) o
     where mf.modelo_id = v_id and exists (select 1 from mkt.campanha_objetivos co where co.codigo = o.objetivo and co.ativo);
    -- itens manuais do SendFlow (Victor, 06/10/2026: o grupo é uma etapa do funil; campanha de lead leva a pessoa a um
    -- grupo de leads, campanha de venda a um grupo de compradores): pela campanha esperada LEADS e/ou VENDAS do modelo
    insert into mkt_trafego.modelo_itens (modelo_id, texto, momento, ordem)
    select v_id, i.texto, 'antes', i.ordem
      from (values ('LEADS', 'Automação de ingresso no grupo de leads configurada no SendFlow', 1),
                   ('VENDAS', 'Automação de ingresso no grupo de compradores configurada no SendFlow', 2)) i(objetivo, texto, ordem)
     where exists (select 1 from mkt_trafego.modelo_campanhas mc where mc.modelo_id = v_id and mc.objetivo = i.objetivo);
  end loop;
end
$semente$;

-- Regra nova do resumo do dia
insert into mkt_trafego.alerta_regras (codigo, nome, ordem, limiar, unidade, gravidade, descricao) values
  ('checklist_incompleto', 'Em captação com checklist incompleto', 9, 0, 'dias', 'media',
   'Projeto em captação (hoje entre o início e o fim da captação) com item do checklist de "antes de subir as campanhas" '
   'ainda pendente, a partir de limiar dias do início da captação (0 = desde o primeiro dia).'),
  ('sem_oferta_exclusiva', 'Sem oferta exclusiva em captação ou carrinho', 10, 0, 'dias', 'alta',
   'Projeto interno em captação ou com o carrinho aberto (ontem entre o início e o fim da captação, do evento ou da fase '
   'abertura de carrinho) sem nenhuma oferta exclusiva ligada: a receita dele é só estimada. A partir de limiar dias do '
   'início do período (0 = desde o primeiro dia). Decisão do Victor, 06/10/2026.');

-- ─── 5. Funções internas ─────────────────────────────────────────────────────────────────────────────────────────────
-- Data de referência do projeto + dias. Nula se a referência não estiver preenchida.
create function mkt_trafego.data_ref(p_ref text, p_dias integer, p_ci date, p_cf date, p_ei date, p_ef date) returns date
language sql immutable set search_path = '' as $$
  select (case p_ref when 'captacao_inicio' then p_ci when 'captacao_fim' then p_cf
                     when 'evento_inicio' then p_ei when 'evento_fim' then p_ef end) + coalesce(p_dias, 0);
$$;

-- O modelo inteiro (para a tela).
create function mkt_trafego.modelo_json(p_id bigint) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', m.id, 'nome', m.nome, 'tipo_lancamento', m.tipo_lancamento, 'tipo_lancamento_nome', t.nome, 'ativo', m.ativo,
    'rascunho', m.rascunho, 'meta_cpl', m.meta_cpl, 'meta_pct_mql', m.meta_pct_mql, 'obs', m.obs, 'atualizado_em', m.atualizado_em,
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('unidade', u.unidade, 'padrao', u.padrao) order by un.ordem), '[]'::jsonb)
                   from mkt_trafego.modelo_unidades u join mkt.unidades un on un.codigo = u.unidade where u.modelo_id = m.id),
    'fases', (select coalesce(jsonb_agg(jsonb_build_object('fase', f.fase, 'ordem', f.ordem, 'inicio_ref', f.inicio_ref,
                'inicio_dias', f.inicio_dias, 'fim_ref', f.fim_ref, 'fim_dias', f.fim_dias, 'pct_verba', f.pct_verba, 'obs', f.obs)
                order by f.ordem, f.id), '[]'::jsonb) from mkt_trafego.modelo_fases f where f.modelo_id = m.id),
    'campanhas', (select coalesce(jsonb_agg(jsonb_build_object('objetivo', c.objetivo, 'fase', c.fase, 'descricao', c.descricao,
                    'pagina', c.pagina, 'ordem', c.ordem) order by c.ordem, c.id), '[]'::jsonb)
                    from mkt_trafego.modelo_campanhas c where c.modelo_id = m.id),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('texto', i.texto, 'momento', i.momento, 'ordem', i.ordem)
                order by case i.momento when 'antes' then 1 when 'durante' then 2 else 3 end, i.ordem, i.id), '[]'::jsonb)
                from mkt_trafego.modelo_itens i where i.modelo_id = m.id))
    from mkt_trafego.modelos m join mkt.tipos_lancamento t on t.codigo = m.tipo_lancamento
   where m.id = p_id;
$$;

-- Prévia de aplicar o modelo no projeto: o que seria criado e o que mudaria. Não grava nada.
create function mkt_trafego.modelo_previa(p_projeto bigint, p_modelo bigint) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_p mkt.projetos%rowtype;
  v_m mkt_trafego.modelos%rowtype;
  v_vmax numeric;
  v_fases jsonb; v_camp jsonb; v_itens jsonb;
  v_avisos text[] := '{}';
begin
  select * into v_p from mkt.projetos where id = p_projeto;
  select * into v_m from mkt_trafego.modelos where id = p_modelo;
  if v_p.id is null or v_m.id is null then return null; end if;
  if v_p.tipo_lancamento is distinct from v_m.tipo_lancamento then v_avisos := array_append(v_avisos, 'tipo_diferente'); end if;
  if v_p.unidade is null or not exists (select 1 from mkt_trafego.modelo_unidades u where u.modelo_id = v_m.id and u.unidade = v_p.unidade) then
    v_avisos := array_append(v_avisos, 'unidade_diferente');
  end if;
  if not v_m.ativo then v_avisos := array_append(v_avisos, 'modelo_inativo'); end if;
  select verba_maxima into v_vmax from mkt_trafego.planejamento where projeto_id = p_projeto;
  if v_vmax is null then v_avisos := array_append(v_avisos, 'sem_verba_maxima'); end if;
  if v_p.captacao_inicio is null and v_p.evento_inicio is null then v_avisos := array_append(v_avisos, 'sem_periodos'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'fase', x.fase, 'nome', x.nome, 'ordem', x.ordem, 'pct_verba', x.pct_verba,
           'inicio', case when x.invertida then null else x.ini end, 'fim', case when x.invertida then null else x.fim end,
           'verba', x.verba, 'existe', x.pf_id is not null,
           'atual', case when x.pf_id is not null then jsonb_build_object('verba', x.a_verba, 'inicio', x.a_ini, 'fim', x.a_fim) end,
           'muda', x.pf_id is not null and ((x.verba is not null and x.verba is distinct from x.a_verba)
                                          or (not x.invertida and x.ini is not null and x.ini is distinct from x.a_ini)
                                          or (not x.invertida and x.fim is not null and x.fim is distinct from x.a_fim)),
           'aviso', case when x.invertida then 'datas_invertidas' when (x.inicio_ref is not null and x.ini is null)
                                                                   or (x.fim_ref is not null and x.fim is null) then 'sem_data' end)
           order by x.ordem, x.fase), '[]'::jsonb)
    into v_fases
    from (select mf.fase, fs.nome, mf.ordem, mf.pct_verba, mf.inicio_ref, mf.fim_ref,
                 mkt_trafego.data_ref(mf.inicio_ref, mf.inicio_dias, v_p.captacao_inicio, v_p.captacao_fim, v_p.evento_inicio, v_p.evento_fim) as ini,
                 mkt_trafego.data_ref(mf.fim_ref, mf.fim_dias, v_p.captacao_inicio, v_p.captacao_fim, v_p.evento_inicio, v_p.evento_fim) as fim,
                 round(v_vmax * mf.pct_verba / 100, 2) as verba,
                 pf.id as pf_id, pf.verba as a_verba, pf.inicio as a_ini, pf.fim as a_fim,
                 coalesce(mkt_trafego.data_ref(mf.fim_ref, mf.fim_dias, v_p.captacao_inicio, v_p.captacao_fim, v_p.evento_inicio, v_p.evento_fim)
                          < mkt_trafego.data_ref(mf.inicio_ref, mf.inicio_dias, v_p.captacao_inicio, v_p.captacao_fim, v_p.evento_inicio, v_p.evento_fim), false) as invertida
            from mkt_trafego.modelo_fases mf
            join mkt_trafego.fases fs on fs.codigo = mf.fase
            left join mkt_trafego.projeto_fases pf on pf.projeto_id = p_projeto and pf.fase = mf.fase
           where mf.modelo_id = v_m.id) x;

  select coalesce(jsonb_agg(jsonb_build_object('objetivo', c.objetivo, 'fase', c.fase, 'descricao', c.descricao, 'pagina', c.pagina,
           'ja_existe', exists (select 1 from mkt_trafego.projeto_campanhas_esperadas e where e.projeto_id = p_projeto
                                  and e.objetivo = c.objetivo and coalesce(e.descricao, '') = coalesce(c.descricao, '')
                                  and coalesce(e.pagina, '') = coalesce(c.pagina, ''))) order by c.ordem, c.id), '[]'::jsonb)
    into v_camp from mkt_trafego.modelo_campanhas c where c.modelo_id = v_m.id;
  select coalesce(jsonb_agg(jsonb_build_object('texto', i.texto, 'momento', i.momento,
           'ja_existe', exists (select 1 from mkt_trafego.projeto_itens pi where pi.projeto_id = p_projeto
                                  and lower(btrim(pi.texto)) = lower(btrim(i.texto))))
           order by case i.momento when 'antes' then 1 when 'durante' then 2 else 3 end, i.ordem, i.id), '[]'::jsonb)
    into v_itens from mkt_trafego.modelo_itens i where i.modelo_id = v_m.id;

  return jsonb_build_object(
    'modelo', jsonb_build_object('id', v_m.id, 'nome', v_m.nome, 'rascunho', v_m.rascunho, 'ativo', v_m.ativo),
    'verba_maxima', v_vmax, 'fases', v_fases, 'campanhas', v_camp, 'itens', v_itens,
    'metas', jsonb_build_object('meta_cpl', v_m.meta_cpl, 'meta_pct_mql', v_m.meta_pct_mql,
              'atual_cpl', (select meta_cpl from mkt_trafego.planejamento where projeto_id = p_projeto),
              'atual_pct_mql', (select meta_pct_mql from mkt_trafego.planejamento where projeto_id = p_projeto)),
    'avisos', to_jsonb(v_avisos),
    'pode_aplicar', not (v_avisos && array['tipo_diferente', 'unidade_diferente', 'modelo_inativo']));
end
$$;

-- Checklist de montagem (refeita): automáticos com momento e ação, campanhas esperadas, itens manuais do projeto.
create or replace function mkt_trafego.checklist(p_projeto bigint) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_p mkt.projetos%rowtype;
  v_pl mkt_trafego.planejamento%rowtype;
  v_camp int; v_fora int; v_semfase int;
  v_esp int; v_criadas int;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_modelo jsonb;
  v_esperadas jsonb;
  v_auto jsonb; v_man jsonb;
begin
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return null; end if;
  select * into v_pl from mkt_trafego.planejamento where projeto_id = p_projeto;
  select count(*), count(*) filter (where c.fora_padrao),
         count(*) filter (where mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) is null)
    into v_camp, v_fora, v_semfase
    from mkt_trafego.campanhas c where c.projeto_id = p_projeto;
  select jsonb_build_object('id', pm.modelo_id, 'nome', pm.modelo_nome, 'aplicado_em', pm.aplicado_em) into v_modelo
    from mkt_trafego.projeto_modelo pm where pm.projeto_id = p_projeto;

  -- esperadas × encontradas: por objetivo (e página, se a esperada tiver), a n-ésima esperada está criada se há n campanhas
  with e as (select pe.*, row_number() over (partition by pe.objetivo, coalesce(pe.pagina, '') order by pe.ordem, pe.id) as n
               from mkt_trafego.projeto_campanhas_esperadas pe where pe.projeto_id = p_projeto),
       c as (select c.objetivo, pg.codigo as pagina, count(*) as n
               from mkt_trafego.campanhas c left join mkt.paginas pg on pg.id = c.pagina_id
              where c.projeto_id = p_projeto and c.objetivo is not null group by 1, 2)
  select count(*), count(*) filter (where x.criada),
         coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'objetivo', x.objetivo, 'fase', x.fase, 'descricao', x.descricao,
                  'pagina', x.pagina, 'criada', x.criada) order by x.ordem, x.id), '[]'::jsonb)
    into v_esp, v_criadas, v_esperadas
    from (select e.*, e.n <= coalesce((select sum(c.n) from c where c.objetivo = e.objetivo
                                          and (e.pagina is null or c.pagina = e.pagina)), 0) as criada
            from e) x;

  select jsonb_agg(jsonb_build_object('codigo', x.codigo, 'texto', x.texto, 'momento', x.momento, 'acao', x.acao, 'aplica', x.aplica,
                   'ok', coalesce(x.aplica and x.ok, false), 'detalhe', x.detalhe) order by x.ordem)
    into v_auto
    from (values
      (1, 'contas', 'Contas de anúncio vinculadas', 'antes', 'projeto', true,
          exists (select 1 from mkt_trafego.projeto_contas pc where pc.projeto_id = p_projeto), null::text),
      (2, 'etiqueta', 'Etiqueta do ClickUp preenchida', 'antes', 'projeto', true, v_p.etiqueta_clickup is not null, null),
      (3, 'paginas', 'Páginas do projeto cadastradas', 'antes', 'paginas', true,
          exists (select 1 from mkt.paginas pg where pg.projeto_id = p_projeto and pg.ativa), null),
      (4, 'hotmart', 'Produtos da Hotmart vinculados', 'antes', 'hotmart', v_p.tipo is distinct from 'externo',
          exists (select 1 from mkt_trafego.produtos_hotmart h where h.projeto_id = p_projeto), null),
      -- oferta exclusiva (decisão do Victor, 06/10/2026): sem ela a receita do projeto é só estimada. Vale para os tipos
      -- com venda que a Central conta (todos os internos; a receita dos externos não entra por ora).
      (5, 'oferta_exclusiva', 'Oferta exclusiva cadastrada na Hotmart e ligada ao projeto', 'antes', 'hotmart',
          v_p.tipo is distinct from 'externo',
          exists (select 1 from mkt_trafego.produtos_hotmart h where h.projeto_id = p_projeto and h.oferta_exclusiva),
          (select string_agg(h.oferta_codigo, ', ' order by h.oferta_codigo) from mkt_trafego.produtos_hotmart h
            where h.projeto_id = p_projeto and h.oferta_exclusiva)),
      (6, 'modelo', 'Modelo de lançamento aplicado', 'antes', 'modelo', true, v_modelo is not null, v_modelo ->> 'nome'),
      (7, 'verba', 'Verba máxima preenchida', 'antes', 'planejamento', true, v_pl.verba_maxima is not null, null),
      (8, 'fases', 'Fases planejadas', 'antes', 'fases', true,
          exists (select 1 from mkt_trafego.projeto_fases f where f.projeto_id = p_projeto), null),
      (9, 'metas', 'Metas preenchidas (leads, receita ou CPL)', 'antes', 'planejamento', true,
           coalesce(v_pl.meta_leads, v_pl.meta_receita, v_pl.meta_cpl) is not null, null),
      (10, 'campanhas', 'Campanhas com a sigla encontradas', 'durante', 'gerador', true, v_camp > 0, v_camp || ' campanha(s)'),
      (11, 'campanhas_esperadas', 'Campanhas esperadas criadas', 'durante', 'gerador', v_esp > 0, v_criadas = v_esp,
           v_criadas || ' de ' || v_esp),
      (12, 'fora_padrao', 'Nenhuma campanha fora do padrão', 'durante', 'campanhas', v_camp > 0, v_fora = 0,
           case when v_fora > 0 then v_fora || ' fora do padrão' end),
      (13, 'fases_campanhas', 'Fase de cada campanha definida', 'durante', 'campanhas', v_camp > 0, v_semfase = 0,
           case when v_semfase > 0 then v_semfase || ' sem fase' end),
      (14, 'encerrado', 'Status encerrado depois do fim do evento', 'encerramento', 'planejamento',
           v_p.evento_fim is not null and v_p.evento_fim < v_hoje, v_pl.status in ('encerrado', 'inativo'), null)
    ) x(ordem, codigo, texto, momento, acao, aplica, ok, detalhe);

  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.texto, 'momento', i.momento, 'aplica', true,
                   'ok', i.feito_em is not null, 'marcado_em', i.feito_em, 'marcado_por', pf.nome, 'do_modelo', i.modelo_id is not null)
                   order by case i.momento when 'antes' then 1 when 'durante' then 2 else 3 end, i.ordem, i.id), '[]'::jsonb)
    into v_man
    from mkt_trafego.projeto_itens i left join public.perfis pf on pf.id = i.feito_por
   where i.projeto_id = p_projeto;

  return jsonb_build_object('automaticos', v_auto, 'manuais', v_man, 'esperadas', v_esperadas, 'modelo', v_modelo,
    'feitos', (select count(*) from jsonb_array_elements(v_auto || v_man) e where (e ->> 'aplica')::boolean and (e ->> 'ok')::boolean),
    'total', (select count(*) from jsonb_array_elements(v_auto || v_man) e where (e ->> 'aplica')::boolean),
    'pendentes_antes', (select coalesce(jsonb_agg(e ->> 'texto'), '[]'::jsonb) from jsonb_array_elements(v_auto || v_man) e
                         where (e ->> 'aplica')::boolean and not (e ->> 'ok')::boolean and e ->> 'momento' = 'antes'));
end
$$;

-- Resumo do dia (refeita): a da 20261006j (conta_fora_projeto) mais checklist_incompleto e sem_oferta_exclusiva.
create or replace function mkt_trafego.alertas() returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v jsonb := mkt_trafego.alertas_base();
  v_ontem date := mkt_trafego.ontem();
  v_extra jsonb;
  v_ck jsonb;
  v_ox jsonb;
begin
  -- conta_fora_projeto (igual à 20261006j)
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

  -- checklist_incompleto: em captação (ontem entre início e fim da captação) com item de "antes" pendente
  select coalesce(jsonb_agg(jsonb_build_object(
           'regra', 'checklist_incompleto', 'nome', rg.nome, 'gravidade', rg.gravidade, 'limiar', rg.limiar, 'unidade', rg.unidade,
           'projeto_id', y.id, 'sigla', y.sigla, 'projeto_nome', y.nome, 'valor', jsonb_array_length(y.ck -> 'pendentes_antes'),
           'referencia', null,
           'detalhe', jsonb_build_object('dias', v_ontem - y.captacao_inicio, 'itens', y.ck -> 'pendentes_antes'))), '[]'::jsonb)
    into v_ck
    from mkt_trafego.alerta_regras rg
    cross join lateral (
      select p.id, p.sigla, p.nome, p.captacao_inicio, mkt_trafego.checklist(p.id) as ck
        from mkt.projetos p
        left join mkt_trafego.planejamento pl on pl.projeto_id = p.id
        left join mkt_trafego.status_projeto s on s.codigo = pl.status
       where p.ativo and coalesce(s.entra_no_resumo_dia, true)
         and p.captacao_inicio is not null and p.captacao_inicio <= v_ontem and coalesce(p.captacao_fim, v_ontem) >= v_ontem
         and v_ontem - p.captacao_inicio >= rg.limiar::int) y
   where rg.codigo = 'checklist_incompleto' and rg.ligada and jsonb_array_length(y.ck -> 'pendentes_antes') > 0;

  -- sem_oferta_exclusiva: interno em captação ou carrinho (ontem dentro da captação, do evento ou da fase abertura de
  -- carrinho planejada) sem nenhuma oferta exclusiva ligada (a receita é só estimada; decisão do Victor, 06/10/2026).
  -- valor = 0 (ofertas exclusivas); a mesma regra em web/modules/marketing/trafego/domain/alertas.ts
  select coalesce(jsonb_agg(jsonb_build_object(
           'regra', 'sem_oferta_exclusiva', 'nome', rg.nome, 'gravidade', rg.gravidade, 'limiar', rg.limiar, 'unidade', rg.unidade,
           'projeto_id', z.id, 'sigla', z.sigla, 'projeto_nome', z.nome, 'valor', 0, 'referencia', null,
           'detalhe', jsonb_build_object('fase', z.fase, 'inicio', z.ini, 'dias', v_ontem - z.ini))), '[]'::jsonb)
    into v_ox
    from mkt_trafego.alerta_regras rg
    cross join lateral (
      select y.* from (
        select p.id, p.sigla, p.nome,
               case when p.captacao_inicio <= v_ontem and coalesce(p.captacao_fim, v_ontem) >= v_ontem then 'captacao'
                    when (p.evento_inicio <= v_ontem and coalesce(p.evento_fim, p.evento_inicio) >= v_ontem) or fc.inicio is not null
                      then 'abertura_carrinho' end as fase,
               case when p.captacao_inicio <= v_ontem and coalesce(p.captacao_fim, v_ontem) >= v_ontem then p.captacao_inicio
                    else least(case when p.evento_inicio <= v_ontem and coalesce(p.evento_fim, p.evento_inicio) >= v_ontem then p.evento_inicio end,
                               fc.inicio) end as ini
          from mkt.projetos p
          left join mkt_trafego.planejamento pl on pl.projeto_id = p.id
          left join mkt_trafego.status_projeto s on s.codigo = pl.status
          left join lateral (select min(f.inicio) as inicio from mkt_trafego.projeto_fases f
                              where f.projeto_id = p.id and f.fase = 'abertura_carrinho'
                                and f.inicio <= v_ontem and f.fim >= v_ontem) fc on true
         where p.ativo and coalesce(s.entra_no_resumo_dia, true) and p.tipo is distinct from 'externo'
           and not exists (select 1 from mkt_trafego.produtos_hotmart h where h.projeto_id = p.id and h.oferta_exclusiva)) y
       where y.fase is not null and v_ontem - y.ini >= rg.limiar::int) z
   where rg.codigo = 'sem_oferta_exclusiva' and rg.ligada;

  return v || jsonb_build_object('alertas', (
    select coalesce(jsonb_agg(a.e order by case a.e ->> 'gravidade' when 'alta' then 0 else 1 end, coalesce(rg.ordem, 99),
                                           a.e ->> 'sigla' nulls last, a.o), '[]'::jsonb)
      from jsonb_array_elements(coalesce(v -> 'alertas', '[]'::jsonb) || v_extra || v_ck || v_ox) with ordinality a(e, o)
      left join mkt_trafego.alerta_regras rg on rg.codigo = a.e ->> 'regra'));
end
$$;

-- ─── 6. Funções públicas da tela (authenticated + mkt.pode_ver('mkt_trafego'), hoje admin/dev) ─────────────────────
-- Listas do cadastro (refeita): "modelos" no lugar de "pacotes" e "checklist_itens".
create or replace function public.trafego_cadastro_listas() returns jsonb
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
    'modelos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome, 'tipo_lancamento', m.tipo_lancamento,
                   'ativo', m.ativo, 'rascunho', m.rascunho,
                   'unidades', (select coalesce(jsonb_agg(jsonb_build_object('unidade', u.unidade, 'padrao', u.padrao)), '[]'::jsonb)
                                  from mkt_trafego.modelo_unidades u where u.modelo_id = m.id))
                   order by m.tipo_lancamento, m.nome), '[]'::jsonb) from mkt_trafego.modelos m),
    'etiquetas_clickup', (select coalesce(jsonb_agg(e.etiqueta order by e.etiqueta), '[]'::jsonb) from mkt_trafego.clickup_etiquetas_vistas e));
end
$$;

-- Cadastro de um projeto (refeita): "modelo" (o aplicado) e "modelos_disponiveis" no lugar de "pacote_fases".
create or replace function public.trafego_projeto_cadastro(p_projeto bigint) returns jsonb
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
    'sugestoes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'plataforma', c.plataforma,
                    'conta_id', c.conta_id, 'conta', ct.nome, 'status_plataforma', c.status_plataforma) order by c.nome), '[]'::jsonb)
                    from mkt_trafego.campanhas c join mkt_trafego.contas ct on ct.id = c.conta_id
                   where c.projeto_id is null
                     and c.conta_id in (select pc.conta_id from mkt_trafego.projeto_contas pc where pc.projeto_id = v_p.id)
                     and mkt.maiusculas(c.nome) ~ ('(^|[^A-Z0-9])' || v_p.sigla || '([^A-Z0-9]|$)')),
    'modelo', (select jsonb_build_object('id', pm.modelo_id, 'nome', pm.modelo_nome, 'aplicado_em', pm.aplicado_em)
                 from mkt_trafego.projeto_modelo pm where pm.projeto_id = v_p.id),
    'modelos_disponiveis', (select count(*) from mkt_trafego.modelos m
                             where m.ativo and m.tipo_lancamento = v_p.tipo_lancamento
                               and exists (select 1 from mkt_trafego.modelo_unidades u where u.modelo_id = m.id and u.unidade = v_p.unidade)),
    'esperadas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'objetivo', e.objetivo, 'fase', e.fase, 'descricao', e.descricao,
                    'pagina', e.pagina) order by e.ordem, e.id), '[]'::jsonb)
                    from mkt_trafego.projeto_campanhas_esperadas e where e.projeto_id = v_p.id),
    'fases_planejadas', (select count(*) from mkt_trafego.projeto_fases f where f.projeto_id = v_p.id));
end
$$;

create function public.trafego_modelos_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(mkt_trafego.modelo_json(m.id) order by t.ordem, m.ativo desc, m.nome), '[]'::jsonb)
            from mkt_trafego.modelos m join mkt.tipos_lancamento t on t.codigo = m.tipo_lancamento);
end
$$;

-- Cria (sem "id") ou edita (com "id") o modelo inteiro. Campos: nome, tipo_lancamento, ativo, rascunho, meta_cpl,
-- meta_pct_mql, obs, unidades [{unidade, padrao}], fases [{fase, ordem, inicio_ref, inicio_dias, fim_ref, fim_dias,
-- pct_verba, obs}], campanhas [{objetivo, fase, descricao, pagina}], itens [{texto, momento}]. As listas substituem as
-- de antes (os projetos que já aplicaram o modelo não mudam). Marcar padrão tira o padrão de outro modelo da mesma
-- combinação. Retorna {ok, msg, id, avisos}.
create function public.trafego_modelo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint;
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_tipo text := nullif(lower(btrim(coalesce(p ->> 'tipo_lancamento', ''))), '');
  v_ativo boolean; v_rasc boolean; v_cpl numeric; v_mql numeric;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_soma numeric;
  v_avisos text[] := '{}';
  v_con text;
  e jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.'); end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_ativo := coalesce((p ->> 'ativo')::boolean, true);
    v_rasc := coalesce((p ->> 'rascunho')::boolean, false);
    v_cpl := nullif(btrim(coalesce(p ->> 'meta_cpl', '')), '')::numeric;
    v_mql := nullif(btrim(coalesce(p ->> 'meta_pct_mql', '')), '')::numeric;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Algum número do modelo está em formato inválido.');
  end;
  if v_id is not null and not exists (select 1 from mkt_trafego.modelos where id = v_id) then
    return jsonb_build_object('ok', false, 'msg', 'Modelo não encontrado.');
  end if;
  if length(v_nome) < 3 or length(v_nome) > 80 then return jsonb_build_object('ok', false, 'msg', 'Nome do modelo: de 3 a 80 letras.'); end if;
  if v_tipo is null or not exists (select 1 from mkt.tipos_lancamento where codigo = v_tipo and ativo) then
    return jsonb_build_object('ok', false, 'msg', 'Escolha o tipo de lançamento.');
  end if;
  foreach v_con in array array['unidades', 'fases', 'campanhas', 'itens'] loop
    if p ? v_con and jsonb_typeof(p -> v_con) <> 'array' then
      return jsonb_build_object('ok', false, 'msg', 'Lista "' || v_con || '" inválida.');
    end if;
  end loop;
  if jsonb_array_length(coalesce(p -> 'unidades', '[]')) = 0 then
    return jsonb_build_object('ok', false, 'msg', 'Marque pelo menos uma unidade.');
  end if;
  if exists (select 1 from jsonb_array_elements(p -> 'unidades') u
              where not exists (select 1 from mkt.lancamento_regras r where r.unidade = u ->> 'unidade' and r.tipo_lancamento = v_tipo)) then
    return jsonb_build_object('ok', false, 'msg', 'Unidade que não tem este tipo de lançamento (ex.: LPSG só na CSM).');
  end if;
  select sum((f ->> 'pct_verba')::numeric) into v_soma from jsonb_array_elements(coalesce(p -> 'fases', '[]')) f
   where nullif(f ->> 'pct_verba', '') is not null;
  if v_soma > 100 then v_avisos := array_append(v_avisos, 'fases_acima_de_100'); end if;

  begin
    if v_id is null then
      insert into mkt_trafego.modelos (nome, tipo_lancamento, ativo, rascunho, meta_cpl, meta_pct_mql, obs, criado_por, atualizado_por)
      values (v_nome, v_tipo, v_ativo, v_rasc, v_cpl, v_mql, v_obs, v_uid, v_uid) returning id into v_id;
    else
      delete from mkt_trafego.modelo_unidades where modelo_id = v_id;
      update mkt_trafego.modelos set nome = v_nome, tipo_lancamento = v_tipo, ativo = v_ativo, rascunho = v_rasc, meta_cpl = v_cpl,
             meta_pct_mql = v_mql, obs = v_obs, atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
      delete from mkt_trafego.modelo_fases where modelo_id = v_id;
      delete from mkt_trafego.modelo_campanhas where modelo_id = v_id;
      delete from mkt_trafego.modelo_itens where modelo_id = v_id;
    end if;
    -- padrão: só modelo ativo; tira o padrão de outro modelo da mesma combinação
    update mkt_trafego.modelo_unidades u set padrao = false
     where u.padrao and u.modelo_id <> v_id and u.tipo_lancamento = v_tipo and v_ativo
       and u.unidade in (select x ->> 'unidade' from jsonb_array_elements(p -> 'unidades') x where coalesce((x ->> 'padrao')::boolean, false));
    insert into mkt_trafego.modelo_unidades (modelo_id, tipo_lancamento, unidade, padrao)
    select distinct on (x ->> 'unidade') v_id, v_tipo, x ->> 'unidade', v_ativo and coalesce((x ->> 'padrao')::boolean, false)
      from jsonb_array_elements(p -> 'unidades') x;
    insert into mkt_trafego.modelo_fases (modelo_id, fase, ordem, inicio_ref, inicio_dias, fim_ref, fim_dias, pct_verba, obs)
    select v_id, f ->> 'fase', coalesce(nullif(f ->> 'ordem', '')::smallint, o::smallint),
           nullif(f ->> 'inicio_ref', ''), coalesce(nullif(f ->> 'inicio_dias', '')::smallint, 0),
           nullif(f ->> 'fim_ref', ''), coalesce(nullif(f ->> 'fim_dias', '')::smallint, 0),
           nullif(f ->> 'pct_verba', '')::numeric, nullif(btrim(coalesce(f ->> 'obs', '')), '')
      from jsonb_array_elements(coalesce(p -> 'fases', '[]')) with ordinality x(f, o);
    insert into mkt_trafego.modelo_campanhas (modelo_id, objetivo, fase, descricao, pagina, ordem)
    select v_id, mkt.maiusculas(btrim(c ->> 'objetivo')), nullif(c ->> 'fase', ''),
           nullif(btrim(regexp_replace(mkt.maiusculas(coalesce(c ->> 'descricao', '')), '\s*\|\s*', ' | ', 'g')), ''),
           nullif(lower(btrim(coalesce(c ->> 'pagina', ''))), ''), o::smallint
      from jsonb_array_elements(coalesce(p -> 'campanhas', '[]')) with ordinality x(c, o);
    insert into mkt_trafego.modelo_itens (modelo_id, texto, momento, ordem)
    select v_id, btrim(regexp_replace(i ->> 'texto', '\s+', ' ', 'g')), coalesce(nullif(i ->> 'momento', ''), 'antes'), o::smallint
      from jsonb_array_elements(coalesce(p -> 'itens', '[]')) with ordinality x(i, o);
  exception
    when unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', case when v_con like 'modelos_nome%' then 'Já existe modelo com este nome.'
                                                         when v_con like 'modelo_fases%' then 'A mesma fase duas vezes no modelo.'
                                                         when v_con like 'modelo_itens%' then 'O mesmo item duas vezes no modelo.'
                                                         else 'Há um valor repetido no modelo.' end);
    when check_violation or foreign_key_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
      get stacked diagnostics v_con = constraint_name;
      raise log 'trafego_modelo_salvar: regra % recusou', v_con;
      return jsonb_build_object('ok', false, 'msg', 'Algum campo fora da regra'
        || ': fase e objetivo da lista, página no formato AK1, % de 0 a 100, dias de -365 a 365, item de 3 a 200 letras.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Modelo salvo.', 'id', v_id, 'avisos', to_jsonb(v_avisos));
end
$$;

-- Duplica o modelo: nome "… (cópia)", ativo, sem padrão, o mesmo rascunho, todas as fases, campanhas e itens. Retorna {ok, msg, id}.
create function public.trafego_modelo_duplicar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  m mkt_trafego.modelos%rowtype;
  v_nome text; v_id bigint; n int := 1;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into m from mkt_trafego.modelos where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Modelo não encontrado.'); end if;
  v_nome := left(m.nome, 70) || ' (cópia)';
  while exists (select 1 from mkt_trafego.modelos where lower(btrim(nome)) = lower(v_nome)) loop
    n := n + 1; v_nome := left(m.nome, 66) || ' (cópia ' || n || ')';
  end loop;
  insert into mkt_trafego.modelos (nome, tipo_lancamento, ativo, rascunho, meta_cpl, meta_pct_mql, obs, criado_por, atualizado_por)
  values (v_nome, m.tipo_lancamento, true, m.rascunho, m.meta_cpl, m.meta_pct_mql, m.obs, v_uid, v_uid) returning id into v_id;
  insert into mkt_trafego.modelo_unidades (modelo_id, tipo_lancamento, unidade, padrao)
  select v_id, u.tipo_lancamento, u.unidade, false from mkt_trafego.modelo_unidades u where u.modelo_id = p_id;
  insert into mkt_trafego.modelo_fases (modelo_id, fase, ordem, inicio_ref, inicio_dias, fim_ref, fim_dias, pct_verba, obs)
  select v_id, f.fase, f.ordem, f.inicio_ref, f.inicio_dias, f.fim_ref, f.fim_dias, f.pct_verba, f.obs from mkt_trafego.modelo_fases f where f.modelo_id = p_id;
  insert into mkt_trafego.modelo_campanhas (modelo_id, objetivo, fase, descricao, pagina, ordem)
  select v_id, c.objetivo, c.fase, c.descricao, c.pagina, c.ordem from mkt_trafego.modelo_campanhas c where c.modelo_id = p_id;
  insert into mkt_trafego.modelo_itens (modelo_id, texto, momento, ordem)
  select v_id, i.texto, i.momento, i.ordem from mkt_trafego.modelo_itens i where i.modelo_id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Modelo duplicado: ' || v_nome || '.', 'id', v_id);
end
$$;

-- Ativa ou inativa. Inativo deixa de ser padrão e some do "Aplicar modelo" (os projetos que já aplicaram não mudam).
create function public.trafego_modelo_ativar(p_id bigint, p_ativo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  update mkt_trafego.modelos set ativo = coalesce(p_ativo, true), atualizado_em = now(), atualizado_por = (select auth.uid())
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Modelo não encontrado.'); end if;
  if not coalesce(p_ativo, true) then update mkt_trafego.modelo_unidades set padrao = false where modelo_id = p_id; end if;
  return jsonb_build_object('ok', true, 'msg', case when coalesce(p_ativo, true) then 'Modelo ativado.' else 'Modelo inativado (deixou de ser padrão).' end);
end
$$;

-- Os modelos que valem para o projeto (ativos, do tipo de lançamento e da unidade dele, padrão primeiro), cada um com a
-- prévia; p_modelo preenchido = só a prévia daquele (mesmo inativo ou de outra combinação, com o aviso).
create function public.trafego_modelo_previa(p_projeto bigint, p_modelo bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_p mkt.projetos%rowtype;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return null; end if;
  if p_modelo is not null then return jsonb_build_array(mkt_trafego.modelo_previa(p_projeto, p_modelo)); end if;
  return (select coalesce(jsonb_agg(mkt_trafego.modelo_previa(p_projeto, m.id) || jsonb_build_object('padrao', u.padrao)
                                    order by u.padrao desc, m.rascunho, m.nome), '[]'::jsonb)
            from mkt_trafego.modelos m join mkt_trafego.modelo_unidades u on u.modelo_id = m.id and u.unidade = v_p.unidade
           where m.ativo and m.tipo_lancamento = v_p.tipo_lancamento);
end
$$;

-- Aplica o modelo no projeto: cria as fases que faltam (datas e verba calculadas), as campanhas esperadas e os itens
-- que faltam, e as metas do modelo onde o projeto não tem meta. Fase que já existe e ficaria diferente: só muda com
-- p_substituir (a tela confirma); a meta que já existe também. NADA é apagado. Retorna {ok, msg, criadas, atualizadas,
-- mantidas, esperadas, itens}.
create function public.trafego_modelo_aplicar(p_projeto bigint, p_modelo bigint, p_substituir boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v jsonb;
  m mkt_trafego.modelos%rowtype;
  f jsonb;
  v_cri int := 0; v_atu int := 0; v_man int := 0; v_esp int; v_it int;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  v := mkt_trafego.modelo_previa(p_projeto, p_modelo);
  if v is null then return jsonb_build_object('ok', false, 'msg', 'Projeto ou modelo não encontrado.'); end if;
  if not (v ->> 'pode_aplicar')::boolean then
    return jsonb_build_object('ok', false, 'msg', 'Este modelo não vale para o projeto (tipo de lançamento, unidade ou modelo inativo).');
  end if;
  select * into m from mkt_trafego.modelos where id = p_modelo;

  for f in select * from jsonb_array_elements(v -> 'fases') loop
    if not (f ->> 'existe')::boolean then
      insert into mkt_trafego.projeto_fases (projeto_id, fase, verba, inicio, fim, obs, atualizado_por)
      values (p_projeto, f ->> 'fase', (f ->> 'verba')::numeric, (f ->> 'inicio')::date, (f ->> 'fim')::date,
              left('Do modelo ' || m.nome, 1000), v_uid);
      v_cri := v_cri + 1;
    elsif (f ->> 'muda')::boolean and coalesce(p_substituir, false) then
      update mkt_trafego.projeto_fases
         set verba = coalesce((f ->> 'verba')::numeric, verba), inicio = coalesce((f ->> 'inicio')::date, inicio),
             fim = coalesce((f ->> 'fim')::date, fim), atualizado_em = now(), atualizado_por = v_uid
       where projeto_id = p_projeto and fase = f ->> 'fase';
      v_atu := v_atu + 1;
    else
      v_man := v_man + 1;
    end if;
  end loop;

  insert into mkt_trafego.projeto_campanhas_esperadas (projeto_id, objetivo, fase, descricao, pagina, ordem, modelo_id, criado_por)
  select p_projeto, c.objetivo, c.fase, c.descricao, c.pagina, c.ordem, p_modelo, v_uid
    from mkt_trafego.modelo_campanhas c
   where c.modelo_id = p_modelo
     and not exists (select 1 from mkt_trafego.projeto_campanhas_esperadas e where e.projeto_id = p_projeto and e.objetivo = c.objetivo
                       and coalesce(e.descricao, '') = coalesce(c.descricao, '') and coalesce(e.pagina, '') = coalesce(c.pagina, ''));
  get diagnostics v_esp = row_count;
  insert into mkt_trafego.projeto_itens (projeto_id, texto, momento, ordem, modelo_id, criado_por)
  select p_projeto, i.texto, i.momento, i.ordem, p_modelo, v_uid
    from mkt_trafego.modelo_itens i
   where i.modelo_id = p_modelo
     and not exists (select 1 from mkt_trafego.projeto_itens x where x.projeto_id = p_projeto and lower(btrim(x.texto)) = lower(btrim(i.texto)));
  get diagnostics v_it = row_count;

  if m.meta_cpl is not null or m.meta_pct_mql is not null then
    insert into mkt_trafego.planejamento as pl (projeto_id, meta_cpl, meta_pct_mql, atualizado_por)
    values (p_projeto, m.meta_cpl, m.meta_pct_mql, v_uid)
    on conflict (projeto_id) do update
      set meta_cpl = case when coalesce(p_substituir, false) then coalesce(excluded.meta_cpl, pl.meta_cpl) else coalesce(pl.meta_cpl, excluded.meta_cpl) end,
          meta_pct_mql = case when coalesce(p_substituir, false) then coalesce(excluded.meta_pct_mql, pl.meta_pct_mql) else coalesce(pl.meta_pct_mql, excluded.meta_pct_mql) end,
          atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  end if;

  insert into mkt_trafego.projeto_modelo (projeto_id, modelo_id, modelo_nome, aplicado_por) values (p_projeto, p_modelo, m.nome, v_uid)
  on conflict (projeto_id) do update set modelo_id = excluded.modelo_id, modelo_nome = excluded.modelo_nome, aplicado_em = now(),
                                         aplicado_por = excluded.aplicado_por;

  return jsonb_build_object('ok', true, 'criadas', v_cri, 'atualizadas', v_atu, 'mantidas', v_man, 'esperadas', v_esp, 'itens', v_it,
    'msg', 'Modelo ' || m.nome || ' aplicado: ' || v_cri || ' fase(s) criada(s), ' || v_atu || ' atualizada(s), ' || v_man
           || ' mantida(s) como estavam; ' || v_esp || ' campanha(s) esperada(s) e ' || v_it || ' item(ns) do checklist acrescentado(s).');
end
$$;

-- Item manual do checklist do projeto: cria (sem "id") ou edita (com "id"). Campos: projeto_id, texto, momento.
create function public.trafego_projeto_item_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint; v_proj bigint;
  v_texto text := btrim(regexp_replace(coalesce(p ->> 'texto', ''), '\s+', ' ', 'g'));
  v_mom text := coalesce(nullif(p ->> 'momento', ''), 'antes');
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint; v_proj := nullif(p ->> 'projeto_id', '')::bigint;
  exception when others then return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.');
  end;
  if length(v_texto) < 3 or length(v_texto) > 200 then return jsonb_build_object('ok', false, 'msg', 'Texto do item: de 3 a 200 letras.'); end if;
  if v_mom not in ('antes', 'durante', 'encerramento') then return jsonb_build_object('ok', false, 'msg', 'Momento: antes, durante ou encerramento.'); end if;
  begin
    if v_id is null then
      if not exists (select 1 from mkt.projetos where id = v_proj) then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
      insert into mkt_trafego.projeto_itens (projeto_id, texto, momento, ordem, criado_por)
      values (v_proj, v_texto, v_mom, coalesce((select max(ordem) + 1 from mkt_trafego.projeto_itens where projeto_id = v_proj), 1), (select auth.uid()))
      returning id into v_id;
    else
      update mkt_trafego.projeto_itens set texto = v_texto, momento = v_mom where id = v_id;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
    end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Este item já está no checklist do projeto.');
  end;
  return jsonb_build_object('ok', true, 'msg', 'Item do checklist salvo.', 'id', v_id);
end
$$;

create function public.trafego_projeto_item_marcar(p_item bigint, p_feito boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  update mkt_trafego.projeto_itens
     set feito_em = case when coalesce(p_feito, false) then now() end, feito_por = case when coalesce(p_feito, false) then (select auth.uid()) end
   where id = p_item;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  return jsonb_build_object('ok', true, 'msg', case when coalesce(p_feito, false) then 'Item marcado como pronto.' else 'Item desmarcado.' end);
end
$$;

create function public.trafego_projeto_item_apagar(p_item bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  delete from mkt_trafego.projeto_itens where id = p_item;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Item tirado do checklist do projeto.');
end
$$;

create function public.trafego_projeto_esperada_apagar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  delete from mkt_trafego.projeto_campanhas_esperadas where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Campanha esperada não encontrada.'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Campanha esperada tirada do projeto.');
end
$$;

-- ─── 7. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('data_ref', 'modelo_json', 'modelo_previa', 'checklist', 'alertas'))
               or (p.pronamespace = 'public'::regnamespace
                   and p.proname in ('trafego_cadastro_listas', 'trafego_projeto_cadastro', 'trafego_modelos_listar', 'trafego_modelo_salvar',
                                     'trafego_modelo_duplicar', 'trafego_modelo_ativar', 'trafego_modelo_previa', 'trafego_modelo_aplicar',
                                     'trafego_projeto_item_salvar', 'trafego_projeto_item_marcar', 'trafego_projeto_item_apagar',
                                     'trafego_projeto_esperada_apagar')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end
$grants$;
grant execute on function
  public.trafego_cadastro_listas(), public.trafego_projeto_cadastro(bigint), public.trafego_modelos_listar(),
  public.trafego_modelo_salvar(jsonb), public.trafego_modelo_duplicar(bigint), public.trafego_modelo_ativar(bigint, boolean),
  public.trafego_modelo_previa(bigint, bigint), public.trafego_modelo_aplicar(bigint, bigint, boolean),
  public.trafego_projeto_item_salvar(jsonb), public.trafego_projeto_item_marcar(bigint, boolean), public.trafego_projeto_item_apagar(bigint),
  public.trafego_projeto_esperada_apagar(bigint)
  to authenticated;

-- ─── 8. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_tela text[] := array['trafego_cadastro_listas', 'trafego_projeto_cadastro', 'trafego_modelos_listar', 'trafego_modelo_salvar',
                         'trafego_modelo_duplicar', 'trafego_modelo_ativar', 'trafego_modelo_previa', 'trafego_modelo_aplicar',
                         'trafego_projeto_item_salvar', 'trafego_projeto_item_marcar', 'trafego_projeto_item_apagar',
                         'trafego_projeto_esperada_apagar'];
begin
  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relkind = 'r' and c.relnamespace = 'mkt_trafego'::regnamespace loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261006l: % tem privilégio em %', r, t.relname;
      end if;
    end loop;
    if not t.relrowsecurity then raise exception '20261006l: RLS desligada em %', t.relname; end if;
  end loop;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_tela))
               or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('data_ref', 'modelo_json', 'modelo_previa', 'checklist', 'alertas')) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006l: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006l: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006l: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006l: grant de authenticated errado em %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261006l: SECURITY DEFINER errado em %', f.sig;
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('trafego_pacote_salvar', 'trafego_pacote_apagar', 'trafego_pacote_aplicar', 'trafego_checklist_marcar',
                                'trafego_checklist_item_salvar')) then
    raise exception '20261006l: sobrou função do pacote ou do checklist antigo';
  end if;
  if (select count(*) from mkt_trafego.modelos where rascunho) <> (select count(*) from mkt.lancamento_regras)
     or (select count(*) from mkt_trafego.modelo_unidades where padrao) <> (select count(*) from mkt.lancamento_regras)
     or (select count(*) from mkt_trafego.projeto_itens) <> 0 or (select count(*) from mkt_trafego.projeto_modelo) <> 0
     or exists (select 1 from mkt_trafego.modelos m where (select sum(mf.pct_verba) from mkt_trafego.modelo_fases mf where mf.modelo_id = m.id) <> 100)
     or not exists (select 1 from mkt_trafego.alerta_regras where codigo = 'checklist_incompleto')
     or not exists (select 1 from mkt_trafego.alerta_regras where codigo = 'sem_oferta_exclusiva') then
    raise exception '20261006l: semente diferente do esperado (um exemplo rascunho e padrão por combinação, 100%% de verba em cada, nada nos projetos)';
  end if;
  -- SendFlow: grupo de leads onde há campanha esperada LEADS, grupo de compradores onde há VENDAS, nada genérico
  if exists (select 1 from mkt_trafego.modelo_itens where texto ilike '%grupo do WhatsApp%')
     or (select count(*) from mkt_trafego.modelo_itens where texto = 'Automação de ingresso no grupo de leads configurada no SendFlow')
        <> (select count(distinct modelo_id) from mkt_trafego.modelo_campanhas where objetivo = 'LEADS')
     or (select count(*) from mkt_trafego.modelo_itens where texto = 'Automação de ingresso no grupo de compradores configurada no SendFlow')
        <> (select count(distinct modelo_id) from mkt_trafego.modelo_campanhas where objetivo = 'VENDAS') then
    raise exception '20261006l: itens do SendFlow diferentes do esperado (grupo de leads com LEADS, grupo de compradores com VENDAS)';
  end if;
end
$confere$;


-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
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
grant execute on function pg_temp.ok(text, boolean, text) to public;
create function pg_temp.proj(p_sigla text) returns bigint language sql stable as $$ select id from mkt.projetos where sigla = p_sigla $$;
create function pg_temp.modelo(p_nome text) returns bigint language sql stable as $$ select id from mkt_trafego.modelos where nome = p_nome $$;
create function pg_temp.fase(p_proj bigint, p_fase text) returns text language sql stable as $$
  select coalesce(verba::text, '-') || ' ' || coalesce(inicio::text, '-') || '/' || coalesce(fim::text, '-')
    from mkt_trafego.projeto_fases where projeto_id = p_proj and fase = p_fase $$;

-- ─── 1. Estrutura e mockups ─────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('1.mockups', (select count(*) from mkt_trafego.modelos where rascunho and nome like 'Exemplo: %') = 9
  and (select count(*) from mkt_trafego.modelo_unidades where padrao) = 9
  and (select string_agg(m.nome, ' / ' order by m.id) from mkt_trafego.modelos m)
      = 'Exemplo: Lançamento clássico CSM / Exemplo: Lançamento pago CSM / Exemplo: Lançamento pago semanal gravado (LPSG) CSM / Exemplo: ATM CSM / '
        || 'Exemplo: Lançamento clássico Escritório / Exemplo: ATM Escritório / Exemplo: Palestra Aurum / Exemplo: Lançamento clássico Diamantes / '
        || 'Exemplo: Lançamento pago Diamantes',
  '9 exemplos (CSM 4, Escritório 2, Aurum 1, Diamantes 2), rascunho e padrão da sua combinação');
select pg_temp.ok('1.verba e itens', not exists (select 1 from mkt_trafego.modelos m
                                                   where (select sum(pct_verba) from mkt_trafego.modelo_fases f where f.modelo_id = m.id) <> 100)
  and (select count(*) from mkt_trafego.modelo_itens where texto like '%SendFlow%' and momento = 'antes') = 7
  and (select string_agg(m.nome, ' / ' order by m.id) from mkt_trafego.modelo_itens i join mkt_trafego.modelos m on m.id = i.modelo_id
        where i.texto = 'Automação de ingresso no grupo de leads configurada no SendFlow')
      = 'Exemplo: Lançamento clássico CSM / Exemplo: Lançamento clássico Escritório / Exemplo: Palestra Aurum / Exemplo: Lançamento clássico Diamantes'
  and (select string_agg(m.nome, ' / ' order by m.id) from mkt_trafego.modelo_itens i join mkt_trafego.modelos m on m.id = i.modelo_id
        where i.texto = 'Automação de ingresso no grupo de compradores configurada no SendFlow')
      = 'Exemplo: Lançamento pago CSM / Exemplo: Lançamento pago semanal gravado (LPSG) CSM / Exemplo: Lançamento pago Diamantes'
  and not exists (select 1 from mkt_trafego.modelo_itens where texto ilike '%grupo do WhatsApp%')
  and not exists (select 1 from mkt_trafego.modelo_itens i join mkt_trafego.modelos m on m.id = i.modelo_id where m.tipo_lancamento = 'atm')
  and (select count(*) from mkt_trafego.modelo_campanhas) = (select count(*) from mkt_trafego.modelo_fases)
  and (select string_agg(c.objetivo, ',' order by c.ordem) from mkt_trafego.modelo_campanhas c where c.modelo_id = pg_temp.modelo('Exemplo: Lançamento pago CSM'))
      = 'AQUECIMENTO,VENDAS,LEMBRETE,REMARKETING,CARRINHO'
  and (select count(*) from mkt_trafego.modelos where meta_cpl is not null or meta_pct_mql is not null) = 0,
  'cada exemplo soma 100% da verba; SendFlow nos 7 com captação (ATM fora): grupo de leads nos 4 com LEADS, grupo de compradores nos 3 com VENDAS; uma campanha esperada por fase (pago: VENDAS na captação); nenhuma meta semeada');
select pg_temp.ok('1.antigos fora', to_regclass('mkt_trafego.pacote_modelos') is null and to_regclass('mkt_trafego.checklist_itens') is null
  and to_regprocedure('public.trafego_pacote_aplicar(bigint)') is null and to_regprocedure('public.trafego_checklist(bigint)') is not null,
  'pacote, itens globais e as funções antigas fora; trafego_checklist continua');

-- ─── 2. Salvar modelo ───────────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; v_id bigint;
begin
  v := pg_temp.adm(format('select public.trafego_modelo_salvar(%L::jsonb)', jsonb_build_object(
    'nome', 'Modelo Ensaio LPSG', 'tipo_lancamento', 'lpsg', 'unidades', jsonb_build_array(jsonb_build_object('unidade', 'csm', 'padrao', true)),
    'meta_cpl', '12.5', 'meta_pct_mql', '30',
    'fases', jsonb_build_array(
      jsonb_build_object('fase', 'captacao', 'inicio_ref', 'captacao_inicio', 'inicio_dias', 0, 'fim_ref', 'captacao_fim', 'fim_dias', 0, 'pct_verba', 80),
      jsonb_build_object('fase', 'remarketing', 'inicio_ref', 'evento_inicio', 'inicio_dias', -3, 'fim_ref', 'evento_fim', 'fim_dias', 0, 'pct_verba', 30)),
    'campanhas', jsonb_build_array(jsonb_build_object('objetivo', 'vendas', 'fase', 'captacao', 'descricao', 'ingresso | frio', 'pagina', 'AK1')),
    'itens', jsonb_build_array(jsonb_build_object('texto', 'Item Ensaio pixel conferido', 'momento', 'antes')))));
  v_id := (v ->> 'id')::bigint;
  perform pg_temp.ok('2.salvar', (v ->> 'ok')::boolean and v -> 'avisos' ? 'fases_acima_de_100'
    and (select padrao from mkt_trafego.modelo_unidades where modelo_id = v_id and unidade = 'csm')
    and not (select padrao from mkt_trafego.modelo_unidades where modelo_id = pg_temp.modelo('Exemplo: Lançamento pago semanal gravado (LPSG) CSM'))
    and (select descricao || ' ' || pagina || ' ' || objetivo from mkt_trafego.modelo_campanhas where modelo_id = v_id) = 'INGRESSO | FRIO ak1 VENDAS',
    'modelo novo padrão do LPSG na CSM: o exemplo deixa de ser padrão; aviso de % acima de 100; descrição e página normalizadas');
  v := pg_temp.adm(format('select public.trafego_modelo_salvar(%L::jsonb)', jsonb_build_object(
    'nome', 'Modelo Ensaio Errado', 'tipo_lancamento', 'lpsg', 'unidades', jsonb_build_array(jsonb_build_object('unidade', 'escritorio')))));
  perform pg_temp.ok('2.combinação', not (v ->> 'ok')::boolean, 'LPSG no Escritório recusado: ' || (v ->> 'msg'));
  v := pg_temp.adm(format('select public.trafego_modelo_salvar(%L::jsonb)', jsonb_build_object(
    'nome', 'modelo ensaio lpsg', 'tipo_lancamento', 'lpsg', 'unidades', jsonb_build_array(jsonb_build_object('unidade', 'csm')))));
  perform pg_temp.ok('2.nome', not (v ->> 'ok')::boolean and v ->> 'msg' like '%nome%', 'nome repetido (sem diferença de maiúscula) recusado');
  v := pg_temp.adm(format('select public.trafego_modelo_salvar(%L::jsonb)', jsonb_build_object('id', v_id,
    'nome', 'Modelo Ensaio LPSG', 'tipo_lancamento', 'lpsg', 'unidades', jsonb_build_array(jsonb_build_object('unidade', 'csm', 'padrao', true)),
    'fases', jsonb_build_array(jsonb_build_object('fase', 'captacao'), jsonb_build_object('fase', 'captacao')))));
  perform pg_temp.ok('2.fase repetida', not (v ->> 'ok')::boolean
    and (select count(*) from mkt_trafego.modelo_fases where modelo_id = v_id) = 2, 'fase repetida recusada e o modelo fica como estava');
  v := pg_temp.adm(format('select public.trafego_modelo_salvar(%L::jsonb)', jsonb_build_object(
    'nome', 'Modelo Ensaio Objetivo', 'tipo_lancamento', 'atm', 'unidades', jsonb_build_array(jsonb_build_object('unidade', 'csm')),
    'campanhas', jsonb_build_array(jsonb_build_object('objetivo', 'TOPO')))));
  perform pg_temp.ok('2.objetivo', not (v ->> 'ok')::boolean, 'objetivo fora da lista recusado');
end
$t$;

-- ─── 3. Duplicar e inativar ─────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; v_id bigint;
begin
  v := pg_temp.adm(format('select public.trafego_modelo_duplicar(%s)', pg_temp.modelo('Modelo Ensaio LPSG')));
  v_id := (v ->> 'id')::bigint;
  perform pg_temp.ok('3.duplicar', (v ->> 'ok')::boolean
    and (select nome from mkt_trafego.modelos where id = v_id) = 'Modelo Ensaio LPSG (cópia)'
    and not (select padrao from mkt_trafego.modelo_unidades where modelo_id = v_id)
    and (select count(*) from mkt_trafego.modelo_fases where modelo_id = v_id) = 2
    and (select count(*) from mkt_trafego.modelo_campanhas where modelo_id = v_id) = 1
    and (select count(*) from mkt_trafego.modelo_itens where modelo_id = v_id) = 1
    and (select meta_cpl from mkt_trafego.modelos where id = v_id) = 12.5,
    'cópia com fases, campanhas, itens e metas; sem padrão');
  v := pg_temp.adm(format('select public.trafego_modelo_duplicar(%s)', pg_temp.modelo('Modelo Ensaio LPSG')));
  perform pg_temp.ok('3.duplicar de novo', (select nome from mkt_trafego.modelos where id = (v ->> 'id')::bigint) = 'Modelo Ensaio LPSG (cópia 2)', 'segunda cópia ganha número');
  v := pg_temp.adm(format('select public.trafego_modelo_ativar(%s, false)', pg_temp.modelo('Modelo Ensaio LPSG')));
  perform pg_temp.ok('3.inativar', (v ->> 'ok')::boolean and not (select ativo from mkt_trafego.modelos where nome = 'Modelo Ensaio LPSG')
    and not (select padrao from mkt_trafego.modelo_unidades where modelo_id = pg_temp.modelo('Modelo Ensaio LPSG')),
    'inativo deixa de ser padrão');
end
$t$;

-- ─── 4. Prévia e aplicar ────────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; x jsonb; v_p bigint; v_ex bigint := pg_temp.modelo('Exemplo: Lançamento clássico CSM');
begin
  v := pg_temp.adm(format('select public.trafego_projeto_salvar(%L::jsonb)', jsonb_build_object('sigla', 'ZD28', 'nome', 'Projeto Ensaio Modelo',
    'tipo', 'interno', 'unidade', 'csm', 'tipo_lancamento', 'lancamento_classico', 'status', 'ativo',
    'captacao_inicio', '2026-11-01', 'captacao_fim', '2026-11-20', 'evento_inicio', '2026-11-25', 'evento_fim', '2026-11-27')));
  v_p := pg_temp.proj('ZD28');
  v := pg_temp.adm(format('select public.trafego_planejamento_salvar(%L::jsonb)', jsonb_build_object('projeto_id', v_p, 'status', 'ativo', 'verba_maxima', '10000', 'meta_cpl', '20')));
  v := pg_temp.adm(format('select public.trafego_fase_salvar(%L::jsonb)', jsonb_build_object('projeto_id', v_p, 'fase', 'captacao', 'verba', '5000')));
  v := pg_temp.adm(format('select public.trafego_projeto_item_salvar(%L::jsonb)', jsonb_build_object('projeto_id', v_p, 'texto', 'Item Ensaio feito à mão', 'momento', 'durante')));
  v := pg_temp.adm(format('select public.trafego_modelo_previa(%s)', v_p));
  perform pg_temp.ok('4.lista', jsonb_array_length(v) = 1 and v -> 0 -> 'modelo' ->> 'nome' = 'Exemplo: Lançamento clássico CSM'
    and (v -> 0 ->> 'padrao')::boolean and (v -> 0 ->> 'pode_aplicar')::boolean,
    'só os modelos ativos do tipo e da unidade do projeto (padrão primeiro)');
  x := (select e from jsonb_array_elements(v -> 0 -> 'fases') e where e ->> 'fase' = 'captacao');
  perform pg_temp.ok('4.prévia', (select string_agg(e ->> 'fase' || ' ' || coalesce(e ->> 'verba', '-') || ' ' || coalesce(e ->> 'inicio', '-') || '/' || coalesce(e ->> 'fim', '-'), '; ' order by (e ->> 'ordem')::int)
                                    from jsonb_array_elements(v -> 0 -> 'fases') e)
      = 'aquecimento 1000.00 2026-10-25/2026-10-31; captacao 6000.00 2026-11-01/2026-11-20; lembrete 1000.00 2026-11-23/2026-11-25; remarketing 1000.00 2026-11-01/2026-11-27; abertura_carrinho 1000.00 2026-11-27/2026-11-30'
    and (x ->> 'existe')::boolean and (x ->> 'muda')::boolean and x -> 'atual' ->> 'verba' = '5000.00',
    'datas pelas referências (captação 01 a 20/11, evento 25 a 27/11) e verba = % × 10.000; captação já existe com 5.000 e mudaria');
  v := pg_temp.adm(format('select public.trafego_modelo_aplicar(%s, %s)', v_p, v_ex));
  perform pg_temp.ok('4.aplicar', (v ->> 'ok')::boolean and (v ->> 'criadas')::int = 4 and (v ->> 'mantidas')::int = 1 and (v ->> 'esperadas')::int = 5
    and (v ->> 'itens')::int = 1 and pg_temp.fase(v_p, 'captacao') = '5000.00 -/-' and pg_temp.fase(v_p, 'lembrete') = '1000.00 2026-11-23/2026-11-25'
    and (select modelo_nome from mkt_trafego.projeto_modelo where projeto_id = v_p) = 'Exemplo: Lançamento clássico CSM'
    and exists (select 1 from mkt_trafego.projeto_itens where projeto_id = v_p and texto = 'Item Ensaio feito à mão'),
    'sem confirmar: 4 fases criadas, a captação editada à mão fica (5.000), 5 esperadas, SendFlow; o item à mão continua');
  v := pg_temp.adm(format('select public.trafego_modelo_aplicar(%s, %s, true)', v_p, v_ex));
  perform pg_temp.ok('4.substituir', (v ->> 'ok')::boolean and (v ->> 'criadas')::int = 0 and (v ->> 'atualizadas')::int = 1
    and (v ->> 'esperadas')::int = 0 and (v ->> 'itens')::int = 0 and pg_temp.fase(v_p, 'captacao') = '6000.00 2026-11-01/2026-11-20'
    and (select count(*) from mkt_trafego.projeto_fases where projeto_id = v_p) = 5,
    'confirmando: a captação vira a do modelo; nada duplicado nem apagado');
  v := pg_temp.adm(format('select public.trafego_modelo_aplicar(%s, %s)', v_p, pg_temp.modelo('Exemplo: ATM Escritório')));
  perform pg_temp.ok('4.outra unidade', not (v ->> 'ok')::boolean, 'modelo de outro tipo/unidade recusado');
  -- metas: projeto com meta de CPL 20 e modelo com 12,5: sem confirmar não troca
  v := pg_temp.adm(format('select public.trafego_projeto_salvar(%L::jsonb)', jsonb_build_object('sigla', 'ZE28', 'nome', 'Projeto Ensaio Metas',
    'tipo', 'interno', 'unidade', 'csm', 'tipo_lancamento', 'lpsg')));
  perform pg_temp.adm(format('select public.trafego_modelo_ativar(%s, true)', pg_temp.modelo('Modelo Ensaio LPSG')));
  v := pg_temp.adm(format('select public.trafego_modelo_aplicar(%s, %s)', pg_temp.proj('ZE28'), pg_temp.modelo('Modelo Ensaio LPSG')));
  perform pg_temp.ok('4.metas e sem datas', (v ->> 'ok')::boolean
    and (select meta_cpl || '/' || meta_pct_mql from mkt_trafego.planejamento where projeto_id = pg_temp.proj('ZE28')) = '12.50/30.00'
    and pg_temp.fase(pg_temp.proj('ZE28'), 'captacao') = '- -/-',
    'projeto sem meta recebe as metas do modelo; sem períodos nem verba, a fase nasce sem data e sem verba');
end
$t$;

-- ─── 5. Checklist que leva à ação ───────────────────────────────────────────────────────────────────────────────────
do $t$
declare c jsonb; v jsonb; v_p bigint := pg_temp.proj('ZD28'); v_conta bigint; v_item bigint;
begin
  insert into mkt_trafego.contas (plataforma, conta_externa, nome, dono) values ('meta', '000881', 'Conta Ensaio D', 'grupo') returning id into v_conta;
  insert into mkt_trafego.campanhas (plataforma, conta_id, campanha_externa, nome, leitura, fora_padrao)
  values ('meta', v_conta, '900000000000881', 'RS | ZD28 | LEADS | ENSAIO', '{}', true),
         ('meta', v_conta, '900000000000882', 'RS | ZD28 | LEADS | ENSAIO B', '{}', true),
         ('meta', v_conta, '900000000000883', 'RS | ZD28 | LEMBRETE | ENSAIO', '{}', true);
  perform mkt_trafego.campanha_aplicar_leitura(id) from mkt_trafego.campanhas where campanha_externa like '90000000000088%';
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', v_p));
  perform pg_temp.ok('5.momento e ação', (select string_agg(e ->> 'codigo' || ':' || (e ->> 'momento') || ':' || (e ->> 'acao'), ',' order by e ->> 'codigo')
                                            from jsonb_array_elements(c -> 'automaticos') e)
      = 'campanhas:durante:gerador,campanhas_esperadas:durante:gerador,contas:antes:projeto,encerrado:encerramento:planejamento,etiqueta:antes:projeto,'
        || 'fases:antes:fases,fases_campanhas:durante:campanhas,fora_padrao:durante:campanhas,hotmart:antes:hotmart,metas:antes:planejamento,'
        || 'modelo:antes:modelo,oferta_exclusiva:antes:hotmart,paginas:antes:paginas,verba:antes:planejamento',
    'cada item automático diz o momento e onde se resolve');
  perform pg_temp.ok('5.esperadas', (select e ->> 'detalhe' from jsonb_array_elements(c -> 'automaticos') e where e ->> 'codigo' = 'campanhas_esperadas') = '2 de 5'
    and (select string_agg(e ->> 'objetivo' || '=' || (e ->> 'criada'), ',' order by (e ->> 'id')::bigint) from jsonb_array_elements(c -> 'esperadas') e)
        = 'AQUECIMENTO=false,LEADS=true,LEMBRETE=true,REMARKETING=false,CARRINHO=false'
    and (select e ->> 'ok' from jsonb_array_elements(c -> 'automaticos') e where e ->> 'codigo' = 'modelo') = 'true'
    and not ((select e from jsonb_array_elements(c -> 'automaticos') e where e ->> 'codigo' = 'encerrado') ->> 'aplica')::boolean,
    '2 LEADS e 1 LEMBRETE encontrados: LEADS e LEMBRETE criadas (2 de 5); modelo aplicado ok; encerramento ainda não se aplica');
  v_item := (select id from mkt_trafego.projeto_itens where projeto_id = v_p and texto like '%SendFlow%');
  v := pg_temp.adm(format('select public.trafego_projeto_item_marcar(%s, true)', v_item));
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', v_p));
  perform pg_temp.ok('5.marcar', (v ->> 'ok')::boolean
    and (select e ->> 'marcado_por' from jsonb_array_elements(c -> 'manuais') e where (e ->> 'id')::bigint = v_item) = 'Victor (local)'
    and (select (e ->> 'do_modelo')::boolean from jsonb_array_elements(c -> 'manuais') e where (e ->> 'id')::bigint = v_item)
    and not (c -> 'pendentes_antes' ? 'Automação de ingresso no grupo de leads configurada no SendFlow'),
    'item do modelo marcado: quem e quando; sai dos pendentes de "antes"');
  v := pg_temp.adm(format('select public.trafego_projeto_item_salvar(%L::jsonb)', jsonb_build_object('projeto_id', v_p, 'texto', 'item ensaio FEITO À MÃO', 'momento', 'antes')));
  perform pg_temp.ok('5.item repetido', not (v ->> 'ok')::boolean, 'item repetido no projeto (sem diferença de maiúscula) recusado');
  v := pg_temp.adm(format('select public.trafego_projeto_item_apagar(%s)', (select id from mkt_trafego.projeto_itens where projeto_id = v_p and texto = 'Item Ensaio feito à mão')));
  v := pg_temp.adm(format('select public.trafego_projeto_esperada_apagar(%s)', (select id from mkt_trafego.projeto_campanhas_esperadas where projeto_id = v_p and objetivo = 'CARRINHO')));
  c := pg_temp.adm(format('select public.trafego_checklist(%s)', v_p));
  perform pg_temp.ok('5.apagar', (v ->> 'ok')::boolean and jsonb_array_length(c -> 'esperadas') = 4 and jsonb_array_length(c -> 'manuais') = 1,
    'item e campanha esperada tirados do projeto pela tela');
end
$t$;

-- ─── 6. Resumo do dia ───────────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; a jsonb; v_p bigint := pg_temp.proj('ZD28');
begin
  update mkt.projetos set captacao_inicio = mkt_trafego.ontem() - 2, captacao_fim = mkt_trafego.ontem() + 5,
                          evento_inicio = mkt_trafego.ontem() + 8, evento_fim = mkt_trafego.ontem() + 9 where id = v_p;
  v := pg_temp.adm('select public.trafego_alertas()');
  a := (select e from jsonb_array_elements(v -> 'alertas') e where e ->> 'regra' = 'checklist_incompleto' and e ->> 'sigla' = 'ZD28');
  perform pg_temp.ok('6.alerta', a is not null and (a ->> 'valor')::int = jsonb_array_length(a -> 'detalhe' -> 'itens')
    and (a -> 'detalhe' ->> 'dias')::int = 2 and a -> 'detalhe' -> 'itens' ? 'Etiqueta do ClickUp preenchida'
    and a -> 'detalhe' -> 'itens' ? 'Oferta exclusiva cadastrada na Hotmart e ligada ao projeto'
    and jsonb_array_length(v -> 'regras') = 10,
    'em captação há 2 dias com ' || coalesce(a ->> 'valor', '?') || ' pendente(s) de "antes" (inclusive a oferta exclusiva): alerta; 10 regras no resumo');
  -- oferta exclusiva (decisão do Victor, 06/10/2026): interno em captação sem nenhuma oferta exclusiva = alerta
  a := (select e from jsonb_array_elements(v -> 'alertas') e where e ->> 'regra' = 'sem_oferta_exclusiva' and e ->> 'sigla' = 'ZD28');
  perform pg_temp.ok('6.sem oferta exclusiva', a is not null and a ->> 'gravidade' = 'alta' and a -> 'detalhe' ->> 'fase' = 'captacao'
    and (a -> 'detalhe' ->> 'dias')::int = 2,
    'ZD28 em captação há 2 dias sem oferta exclusiva: alerta alto "Sem oferta exclusiva em captação ou carrinho"');
  update mkt.projetos set captacao_inicio = mkt_trafego.ontem() - 12, captacao_fim = mkt_trafego.ontem() - 3,
                          evento_inicio = mkt_trafego.ontem() - 1, evento_fim = mkt_trafego.ontem() + 1 where id = v_p;
  v := pg_temp.adm('select public.trafego_alertas()');
  a := (select e from jsonb_array_elements(v -> 'alertas') e where e ->> 'regra' = 'sem_oferta_exclusiva' and e ->> 'sigla' = 'ZD28');
  perform pg_temp.ok('6.carrinho', a is not null and a -> 'detalhe' ->> 'fase' = 'abertura_carrinho' and (a -> 'detalhe' ->> 'dias')::int = 1,
    'com a captação encerrada e o evento (carrinho) em andamento, o alerta continua, como abertura de carrinho');
  insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva)
  values (v_p, 'academy', '9990801', 'OFZD28', true);
  v := pg_temp.adm('select public.trafego_alertas()');
  perform pg_temp.ok('6.com oferta exclusiva', not exists (select 1 from jsonb_array_elements(v -> 'alertas') e
                                                            where e ->> 'regra' = 'sem_oferta_exclusiva' and e ->> 'sigla' = 'ZD28')
    and exists (select 1 from jsonb_array_elements(pg_temp.adm(format('select public.trafego_checklist(%s)', v_p)) -> 'automaticos') e
                 where e ->> 'codigo' = 'oferta_exclusiva' and (e ->> 'ok')::boolean and e ->> 'detalhe' = 'OFZD28'),
    'com a oferta exclusiva ligada: o alerta some e o item do checklist fica pronto (detalhe = a oferta)');
  update mkt.projetos set captacao_inicio = mkt_trafego.ontem() - 2, captacao_fim = mkt_trafego.ontem() + 5,
                          evento_inicio = mkt_trafego.ontem() + 8, evento_fim = mkt_trafego.ontem() + 9 where id = v_p;
  update mkt_trafego.planejamento set status = 'em_planejamento' where projeto_id = v_p;
  v := pg_temp.adm('select public.trafego_alertas()');
  perform pg_temp.ok('6.em planejamento', not exists (select 1 from jsonb_array_elements(v -> 'alertas') e where e ->> 'sigla' = 'ZD28'),
    'em planejamento: fora do resumo do dia');
end
$t$;

-- ─── 7. Listas, cadastro, grants e recusas ──────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb;
begin
  v := pg_temp.adm('select public.trafego_cadastro_listas()');
  perform pg_temp.ok('7.listas', v ? 'modelos' and not v ? 'pacotes' and not v ? 'checklist_itens' and jsonb_array_length(v -> 'modelos') >= 9,
    'listas com "modelos" (sem "pacotes" e "checklist_itens")');
  v := pg_temp.adm(format('select public.trafego_projeto_cadastro(%s)', pg_temp.proj('ZD28')));
  perform pg_temp.ok('7.cadastro', v -> 'modelo' ->> 'nome' = 'Exemplo: Lançamento clássico CSM' and (v ->> 'modelos_disponiveis')::int = 1
    and jsonb_array_length(v -> 'esperadas') = 4 and not v ? 'pacote_fases', 'cadastro do projeto com o modelo aplicado e as esperadas');
  v := pg_temp.adm('select public.trafego_modelos_listar()');
  perform pg_temp.ok('7.modelos', (select count(*) from jsonb_array_elements(v) e where (e ->> 'rascunho')::boolean) >= 9
    and (select jsonb_array_length(e -> 'fases') from jsonb_array_elements(v) e where e ->> 'nome' = 'Exemplo: ATM CSM') = 3,
    'lista de modelos com fases, campanhas e itens');
end
$t$;
select pg_temp.ok('7.grants',
  not has_function_privilege('anon', 'public.trafego_modelo_salvar(jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.trafego_modelo_aplicar(bigint, bigint, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'mkt_trafego.modelo_previa(bigint, bigint)', 'execute')
  and not has_table_privilege('authenticated', 'mkt_trafego.modelos', 'select'),
  'anon nada; tela authenticated; internas e tabelas fechadas');
do $t$
declare
  c text; u text; v_papel text;
  v_chamadas text[] := array[
    'select public.trafego_modelos_listar()', 'select public.trafego_modelo_salvar(''{}'')', 'select public.trafego_modelo_duplicar(1)',
    'select public.trafego_modelo_ativar(1, false)', 'select public.trafego_modelo_previa(1)', 'select public.trafego_modelo_aplicar(1, 1)',
    'select public.trafego_projeto_item_salvar(''{}'')', 'select public.trafego_projeto_item_marcar(1, true)',
    'select public.trafego_projeto_item_apagar(1)', 'select public.trafego_projeto_esperada_apagar(1)',
    'select public.trafego_cadastro_listas()', 'select public.trafego_projeto_cadastro(1)',
    'select count(*) from mkt_trafego.modelos', 'select count(*) from mkt_trafego.projeto_itens'];
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
    perform pg_temp.ok('7.' || case split_part(u, ':', 1) when '33333333-3333-4333-8333-333333333333' then 'visualizador'
                                 when '22222222-2222-4222-8222-222222222222' then 'operador'
                                 else 'sem perfil' end || ' ' || v_papel,
                       v_errado is null, v_ok || ' recusas 42501' || coalesce(' / PASSOU: ' || v_errado, ''));
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
