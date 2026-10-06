-- 20261006i: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da
--   20261006g (ela precisa estar aplicada, ou rodar este arquivo logo depois do corpo dela na mesma transação). Todo
--   resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo. Se o cliente só mostra o resultado do
--   ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode o "rollback;" em seguida. NÃO deixe a
--   transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006i_mkt_trafego_fase2.sql, das guardas
-- até antes do bloco LIGAR; se a migration mudar, gerar de novo). Depois dele, os testes criam DADOS FICTÍCIOS
-- (projetos ZZ28 "Projeto Ensaio Fase 2", ZY28 "Projeto Ensaio Encerrado", ZX28 "Projeto Ensaio Sem Datas"; conta
-- act_000555 "Conta Ensaio R"; campanhas 9000000001xx e 9000000002xx; transações HPENSAIO1…12 dos produtos 99900xx em
-- fin.hotmart_transacoes, SÓ no banco local; tarefas 86ensaio1…3 do ClickUp; um segredo fictício meta_ads_token_ensaio_zz no Vault; com a 20261005r_pessoas_e_crm_fundacao,
-- 30 pessoas "Pessoa Ensaio Fase2 …") e chamam as funções como a tela, a rotina (service_role/postgres) e quem não pode
-- chamariam (JWT simulado). Nenhum dado real vai para a saída. Tudo some no rollback. Atenção: o passo 3 só insere as
-- 12 transações fictícias em fin.hotmart_transacoes se a tabela NÃO tiver gatilho (banco local); em produção ela dispara
-- o CRM (zz_crm_hotmart_sync_ins) e o passo diz PULADO, e no lugar confere a receita de um produto REAL contra
-- fin.vw_transacoes (a view do financeiro), só lendo, com o vínculo num projeto fictício ZW28 "Projeto Ensaio Real".
--
-- Esperado: NENHUMA linha começando com "ERRADO". Cada linha diz o que conferiu. O que depende de outra migration diz
-- "PULADO" quando ela não está aplicada: leads e CPL (20261005r_pessoas_e_crm_fundacao), Vault e pg_cron (Supabase),
-- fin.hotmart_transacoes e fin.vw_transacoes (financeiro).
--   0  dados fictícios        1  estrutura, sementes (7 regras e limiares), rotinas NÃO agendadas, segredo do header
--   2  resumo do dia: acima da diária, ritmo da fase (acima e abaixo), % da verba, fora do padrão (com e sem projeto),
--      sem fase, leads abaixo da meta para a data e CPL acima da meta (com a base); projeto encerrado fora; limiares e
--      status mudam o resultado por configuração
--   3  receita (fin.hotmart_transacoes): sem vínculo = nula; pagas = APPROVED/COMPLETE, bruto = valor da oferta (não o
--      cobrado), líquido à parte, reembolso fora, sem aprovado_em fora, período do projeto ou do vínculo, conta separa
--      o mesmo id de produto, oferta, outra moeda à parte, venda contada uma vez só; avisos (produto em outro projeto,
--      sem período, sem vendas na conta) e recusas (sem conta, conta desconhecida); seletor por conta sem dado de
--      comprador; no Supabase, a mesma soma de fin.vw_transacoes para um produto real
--   3b receita por NÍVEL DE CERTEZA (decisão do Victor, 06/10/2026): produto + período vira estimada (à parte); oferta
--      exclusiva (nível 1, qualquer data, uma oferta um projeto: tela e índice único), SCK com o projeto no campo campanha
--      (nível 2, chave ou sigla, sem maiúscula e acento), comprador que foi lead do projeto antes da compra (nível 3: e-mail,
--      documento, telefone), nível mais forte vence, disputa no mesmo nível (não soma em nenhum), vendas em disputa e aviso
--      sem oferta exclusiva em public.trafego_receita. Só no banco local (transações fictícias)
--   4  ClickUp: espelho pela etiqueta, recusas, quem sumiu perde a etiqueta, lista na vida do projeto
--   5  credenciais das rotinas (conta centralizadora × token por conta), registro das coletas (200 por fonte)
--   6  o formato que a Edge trafego-meta manda (saída das fixtures do vitest) é aceito e é idempotente
--   7  grants         8  recusa 42501 para sem perfil, operador (mesmo com a área), visualizador e anon; o admin e o
--      service_role também não leem os tokens
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
  if to_regclass('mkt_trafego.alerta_regras') is not null or to_regprocedure('mkt_trafego.resumo_base(bigint)') is not null then
    raise exception '20261006i: já aplicada (mkt_trafego.alerta_regras ou mkt_trafego.resumo_base existe)';
  end if;
  if to_regnamespace('mkt_trafego') is null or to_regprocedure('mkt_trafego.resumo(bigint)') is null
     or to_regprocedure('public.trafego_campanhas_receber(jsonb)') is null
     or to_regprocedure('public.trafego_desempenho_receber(jsonb)') is null
     or to_regprocedure('mkt_trafego.fase_efetiva(text,text)') is null then
    raise exception '20261006i: falta a 20261006g (schema mkt_trafego, resumo, funções de entrada)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                                'trafego_hotmart_produtos', 'trafego_clickup', 'trafego_clickup_receber', 'trafego_receita')) then
    raise exception '20261006i: já existem funções public.trafego_* desta migration';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'mkt' and table_name = 'projetos' and column_name = 'etiqueta_clickup') then
    raise exception '20261006i: mkt.projetos.etiqueta_clickup ausente (20261005m)';
  end if;
end
$guarda$;

-- ─── 1. Resumo do dia: regras e limiares (configuráveis por SQL) ─────────────────────────────────────────────────────
create table mkt_trafego.alerta_regras (
  codigo     text primary key check (codigo ~ '^[a-z][a-z_]{1,39}$'),
  nome       text not null check (length(btrim(nome)) between 2 and 80),
  ordem      smallint not null,
  ligada     boolean not null default true,
  limiar     numeric(10,2) not null check (limiar >= 0),
  unidade    text not null check (unidade in ('pct', 'dias')),
  gravidade  text not null check (gravidade in ('alta', 'media')),
  descricao  text not null check (length(descricao) <= 600),
  atualizado_em timestamptz not null default now()
);
comment on table mkt_trafego.alerta_regras is
  'Resumo do dia da Central do Tráfego ("o que está pegando fogo"): uma linha por regra, com o limiar. Muda por SQL '
  '(update … set limiar = …). Valores iniciais = PROPOSTA da 20261006i, a confirmar com o Victor. 20261006i.';

insert into mkt_trafego.alerta_regras (codigo, nome, ordem, limiar, unidade, gravidade, descricao) values
  ('acima_verba_diaria', 'Acima da verba diária', 1, 0, 'pct', 'alta',
   'Gasto de ontem acima da verba diária + limiar %. 0 = qualquer real acima (a mesma regra do cartão "Ontem acima da verba diária" da 20261006g).'),
  ('cpl_acima_meta', 'CPL acima da meta', 2, 0, 'pct', 'alta',
   'CPL do projeto (investido ÷ leads da base) acima da meta de CPL + limiar %.'),
  ('leads_abaixo_meta', 'Abaixo da meta de leads para a data', 3, 20, 'pct', 'alta',
   'Leads da base abaixo do esperado para ontem em mais de limiar %. Esperado = meta de leads × dias passados ÷ dias do período; '
   'período = a fase de captação planejada (com início e fim), senão início e fim do projeto; sem período, não avalia.'),
  ('ritmo_fase', 'Ritmo da fase fora do planejado', 4, 20, 'pct', 'media',
   'Fase em andamento (início ≤ ontem ≤ fim, com verba): gasto das campanhas da fase desde o início acima ou abaixo do '
   'esperado em mais de limiar %. Esperado = verba da fase × dias passados ÷ dias da fase (a mesma conta do "deveria ter gasto" da tela).'),
  ('verba_perto_fim', '% da verba perto do fim', 5, 90, 'pct', 'media',
   '% da verba máxima já investido maior ou igual ao limiar.'),
  ('fora_padrao', 'Campanhas fora do padrão', 6, 7, 'dias', 'media',
   'Campanhas com nome fora do padrão que gastaram nos últimos limiar dias (inclui as sem projeto).'),
  ('sem_fase', 'Campanhas sem fase', 7, 7, 'dias', 'media',
   'Campanhas do projeto sem fase (sem regra pelo objetivo e sem correção à mão) que gastaram nos últimos limiar dias.');

alter table mkt_trafego.status_projeto add column entra_no_resumo_dia boolean not null default true;
comment on column mkt_trafego.status_projeto.entra_no_resumo_dia is
  'false = projeto com este status não aparece no resumo do dia. Semente da 20261006i: em planejamento (Victor, 06/10/2026), '
  'inativo e encerrado ficam fora (proposta).';
update mkt_trafego.status_projeto set entra_no_resumo_dia = false where codigo in ('em_planejamento', 'inativo', 'encerrado');

-- ─── 2. Receita: vínculo produto Hotmart → projeto (cadastro à mão) ─────────────────────────────────────────────────
create table mkt_trafego.produtos_hotmart (
  id             bigint generated always as identity primary key,
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  conta          text not null check (conta ~ '^[a-z][a-z0-9_]{1,29}$'),
  produto_id     text not null check (produto_id ~ '^[A-Za-z0-9_-]{1,40}$'),
  oferta_codigo  text check (oferta_codigo is null or oferta_codigo ~ '^[A-Za-z0-9_-]{1,40}$'),
  de             date,
  ate            date,
  obs            text check (obs is null or length(obs) <= 1000),
  oferta_exclusiva boolean not null default false,
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  constraint produtos_hotmart_datas_check check (ate is null or de is null or ate >= de),
  constraint produtos_hotmart_exclusiva_check check (not oferta_exclusiva or oferta_codigo is not null)
);
create unique index produtos_hotmart_unico on mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, coalesce(oferta_codigo, ''));
create index produtos_hotmart_produto_idx on mkt_trafego.produtos_hotmart (conta, produto_id);
-- Uma oferta (por conta da Hotmart) só pode ser exclusiva de UM projeto: o banco recusa a segunda (decisão do Victor, 06/10/2026).
create unique index produtos_hotmart_oferta_exclusiva_unica on mkt_trafego.produtos_hotmart (conta, oferta_codigo) where oferta_exclusiva;
comment on table mkt_trafego.produtos_hotmart is
  'Produto (e, se quiser, oferta) da Hotmart, de uma das contas, que gera receita para o projeto. CADASTRO À MÃO na tela '
  '(nada pré-preenchido). A receita é lida de fin.hotmart_transacoes (espelho do financeiro) na hora; aqui só o vínculo. 20261006i.';
comment on column mkt_trafego.produtos_hotmart.conta is
  'Conta da Hotmart, como em fin.hotmart_transacoes.conta (academy = CSM, escritorio). O casamento é por conta + produto.';
comment on column mkt_trafego.produtos_hotmart.produto_id is 'Id do produto na Hotmart, como em fin.hotmart_transacoes.produto_id (texto).';
comment on column mkt_trafego.produtos_hotmart.oferta_codigo is 'Código da oferta (fin.hotmart_transacoes.oferta_codigo). Nulo = todas as ofertas do produto.';
comment on column mkt_trafego.produtos_hotmart.de is 'Início do período que conta para este projeto. Nulo = início do projeto (mkt.projetos.inicio).';
comment on column mkt_trafego.produtos_hotmart.ate is 'Fim do período. Nulo = fim do projeto (mkt.projetos.fim), e sem fim = até hoje.';
comment on column mkt_trafego.produtos_hotmart.oferta_exclusiva is
  'true = esta OFERTA (oferta_codigo, obrigatório) é exclusiva do projeto: toda venda paga dela é do projeto, nível 1 da receita '
  '(certa), em qualquer data; só o de/até PRÓPRIO do vínculo limita (o período padrão não). Uma oferta, por conta, é exclusiva de um '
  'projeto só (índice produtos_hotmart_oferta_exclusiva_unica). Decisão do Victor, 06/10/2026: docs/central-de-dados.md, seção '
  '"Receita do projeto: oferta exclusiva e SCK".';

-- ─── 3. ClickUp: espelho mínimo das tarefas pela etiqueta do projeto ─────────────────────────────────────────────────
create table mkt_trafego.clickup_tarefas (
  tarefa_id     text primary key check (tarefa_id ~ '^[A-Za-z0-9_-]{1,40}$'),
  nome          text not null check (length(nome) between 1 and 500),
  status        text check (status is null or length(status) <= 60),
  criada_em     timestamptz,
  atualizada_em timestamptz,
  inicio        timestamptz,
  prazo         timestamptz,
  concluida_em  timestamptz,
  responsaveis  text[] not null default '{}',
  etiquetas     text[] not null check (cardinality(etiquetas) between 1 and 50),
  url           text check (url is null or url ~ '^https://app\.clickup\.com/'),
  coletado_em   timestamptz not null default now()
);
create index clickup_tarefas_etiquetas_idx on mkt_trafego.clickup_tarefas using gin (etiquetas);
comment on table mkt_trafego.clickup_tarefas is
  'Espelho MÍNIMO das tarefas do ClickUp que têm a etiqueta de algum projeto (mkt.projetos.etiqueta_clickup). Gravado pela '
  'rotina trafego-clickup (só leitura no ClickUp). Sem descrição, sem comentário, sem anexo. 20261006i.';
comment on column mkt_trafego.clickup_tarefas.responsaveis is 'Nome de usuário dos responsáveis no ClickUp (sem e-mail).';

create table mkt_trafego.coleta_config (
  chave     text primary key check (chave ~ '^[a-z][a-z_]{1,39}$'),
  valor     text check (valor is null or length(valor) <= 200),
  descricao text not null check (length(descricao) <= 600)
);
comment on table mkt_trafego.coleta_config is 'Parâmetros das rotinas de coleta do Tráfego (não secretos). Segredos ficam no Vault. 20261006i.';
insert into mkt_trafego.coleta_config (chave, valor, descricao) values
  ('meta_dias', '3', 'Quantos dias completos para trás a coleta Meta relê a cada rodada (o Meta ainda ajusta os números dos últimos dias), além de hoje.'),
  ('meta_api_versao', null, 'Versão da Graph API (ex.: v23.0). Nulo = a versão padrão escrita na Edge trafego-meta. Conferir a vigente antes de ligar.'),
  ('clickup_team_id', null, 'Id do workspace (team) do ClickUp de onde ler as tarefas. Nulo = a rotina não roda. Victor informa.');

create table mkt_trafego.coletas (
  id        bigint generated always as identity primary key,
  fonte     text not null check (fonte in ('meta', 'google', 'clickup')),
  em        timestamptz not null default now(),
  ok        boolean not null,
  resultado jsonb,
  erro      text check (erro is null or length(erro) <= 500)
);
create index coletas_fonte_idx on mkt_trafego.coletas (fonte, id desc);
comment on table mkt_trafego.coletas is 'Registro de cada rodada das rotinas de coleta (contagens e falhas, nunca token nem URL). 200 por fonte. 20261006i.';

alter table mkt_trafego.contas add column token_vault text
  check (token_vault is null or token_vault ~ '^[a-z][a-z0-9_]{2,59}$');
comment on column mkt_trafego.contas.token_vault is
  'Nome do segredo no Vault com o token desta conta (token por conta). Nulo = usa o token da conta centralizadora '
  '(Vault meta_ads_token). Muda só por SQL. Decisão em aberto (Victor): as duas formas funcionam. 20261006i.';

alter table mkt_trafego.alerta_regras enable row level security;
alter table mkt_trafego.produtos_hotmart enable row level security;
alter table mkt_trafego.clickup_tarefas enable row level security;
alter table mkt_trafego.coleta_config enable row level security;
alter table mkt_trafego.coletas enable row level security;
revoke all on mkt_trafego.alerta_regras, mkt_trafego.produtos_hotmart, mkt_trafego.clickup_tarefas,
              mkt_trafego.coleta_config, mkt_trafego.coletas from public, anon, authenticated;

-- ─── 4. Receita (internas) ───────────────────────────────────────────────────────────────────────────────────────────
-- fin.hotmart_transacoes (espelho do financeiro, 20260927 + conta da 20260930z89) existe com as colunas que a receita
-- usa? Num banco sem o financeiro a receita fica "sem fonte" (nula) e as funções compilam mesmo assim (SQL dinâmico).
create function mkt_trafego.hotmart_disponivel() returns boolean
language sql stable set search_path = '' as $$
  select count(*) = 12 from information_schema.columns
   where table_schema = 'fin' and table_name = 'hotmart_transacoes'
     and column_name in ('conta', 'produto_id', 'produto_nome', 'oferta_codigo', 'status', 'moeda', 'valor_base',
                         'valor_cobrado', 'taxa_hotmart', 'liquido_produtor', 'aprovado_em', 'bruto_json');
$$;

-- Período padrão do projeto para a meta de leads (sem fase de captação planejada com datas). Aqui: início e fim do
-- projeto. A 20261006j troca para o período de captação (Victor, 06/10/2026). Mudar a regra = só esta função.
create function mkt_trafego.periodo_padrao(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select p.inicio, p.fim from mkt.projetos p where p.id = p_projeto;
$$;

-- Período padrão da RECEITA (vínculo de produto sem "de"/"até"). Aqui: início e fim do projeto. A 20261006j troca para
-- início da captação até o fim do evento (Victor, 06/10/2026, PROVISÓRIO). Mudar a regra = só esta função.
create function mkt_trafego.periodo_receita(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select p.inicio, p.fim from mkt.projetos p where p.id = p_projeto;
$$;

-- ─── 4b. Receita do projeto por NÍVEL DE CERTEZA (decisão do Victor, 06/10/2026) ────────────────────────────────────
-- Produto + período não garante que a venda veio do projeto (o mesmo produto é vendido pelo comercial, pela recuperação
-- e por outros lançamentos ao mesmo tempo). Cada venda paga (regra do financeiro: status APPROVED ou COMPLETE, data =
-- aprovado_em, bruto = valor da oferta, só BRL na soma) conta UMA vez, no nível mais forte que atingir:
--   1 oferta exclusiva   a venda é de uma oferta marcada como exclusiva do projeto (produtos_hotmart.oferta_exclusiva).
--                        Certa. Qualquer data; só o de/até PRÓPRIO do vínculo limita.
--   2 SCK com o projeto  o campo campanha do origem_sck é a chave do projeto (etiqueta do ClickUp) ou a sigla. Certa.
--                        Qualquer produto, qualquer data.
--   3 lead do projeto    o comprador (e-mail, documento ou telefone, pela base de pessoas do Arthur, só leitura) tem
--                        evento 'lead' do projeto ANTES da compra, e a compra é de produto ligado ao projeto, no período
--                        do vínculo. Provável.
--   4 estimada           só produto ligado + período (a regra antiga). Mostrada À PARTE, nunca somada na receita.
-- Receita do projeto (coluna "Receita" da Central, e qualquer conta com receita, como ROAS) = níveis 1 a 3.
-- Venda que atinge o MESMO nível mais forte em mais de um projeto = DISPUTA: não soma em nenhum, aparece na lista
-- "vendas em disputa" da vida de cada projeto envolvido. Projeto que perdeu a venda para um nível mais forte de outro
-- projeto não conta a venda.

-- Texto normalizado para comparar chaves (sem diferença de maiúscula, acento e espaço nas pontas). Vazio = nulo.
create function mkt_trafego.chave_norm(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(lower(mkt.sem_acento(btrim(coalesce(p, '')))), '');
$$;

-- FORMATO DO SCK (DECIDIDO pelo Victor, 06/10/2026): os mesmos campos da UTM, na mesma ordem, separados por "|":
--   origem|meio|campanha|conteúdo|termo
-- e o campo CAMPANHA (o 3º) leva a chave do projeto (mkt.projetos.etiqueta_clickup, ex. seminario-conjunto-2026-11) ou
-- a sigla (ex. pb26). Vale para checkout de abertura de carrinho, API, grupo, SMS, e-mail e comercial; o tráfego pago
-- fica de fora (o checkout não recebe o sck do anúncio: ali valem a UTM e a oferta exclusiva). ESTE É O ÚNICO LUGAR
-- QUE LÊ O SCK: mudar o formato = só esta função. Devolve o campo campanha normalizado (nulo se o sck não tem "|").
create function mkt_trafego.sck_campanha(p_sck text) returns text
language sql immutable set search_path = '' as $$
  select case when position('|' in coalesce(p_sck, '')) > 0 then mkt_trafego.chave_norm(split_part(p_sck, '|', 3)) end;
$$;

-- A base de pessoas do Arthur (20261005r_pessoas_e_crm_fundacao) e as colunas do comprador no espelho da Hotmart
-- (20260927c2) existem? Sem elas o nível 3 não roda (fica zero) e o resto funciona.
create function mkt_trafego.pessoas_disponivel() returns boolean
language sql stable set search_path = '' as $$
  select to_regclass('pessoas.eventos') is not null and to_regclass('pessoas.identificadores') is not null
     and to_regclass('pessoas.pessoas') is not null and to_regprocedure('pessoas.atual(uuid)') is not null
     and to_regprocedure('pessoas.grupo(uuid)') is not null and to_regprocedure('pessoas.chave_telefone(text)') is not null
     and to_regclass('public.compradores') is not null and to_regclass('public.thb_alunos') is not null
     and (select count(*) = 3 from information_schema.columns
           where table_schema = 'fin' and table_name = 'hotmart_transacoes'
             and column_name in ('comprador_email', 'comprador_documento', 'comprador_telefone'));
$$;

-- Cada venda paga ligada a um projeto, já classificada: uma linha por (projeto, transação) no nível mais forte da
-- venda. disputa = o mesmo nível mais forte em mais de um projeto (projetos_disputa = todos eles). p_projeto filtra a
-- SAÍDA; a classificação é sempre feita com todos os projetos (a disputa precisa ver os outros). Vazia sem a fonte.
create function mkt_trafego.receita_vendas(p_projeto bigint default null)
returns table (projeto_id bigint, transacao text, nivel smallint, disputa boolean, projetos_disputa bigint[], conta text,
               produto_id text, oferta_codigo text, aprovado_em timestamptz, moeda text, bruto numeric, liquido numeric,
               liquido_estimado boolean)
language plpgsql stable set search_path = '' as $$
declare
  v_sql text;
  v_n3 text;
begin
  if not mkt_trafego.hotmart_disponivel() then return; end if;
  if mkt_trafego.pessoas_disponivel() then
    -- nível 3: chaves (e-mail, documento só dígitos, telefone pela chave da base) de quem foi lead do projeto, com a data
    -- do primeiro lead; a pessoa vale com as mescladas a ela (pessoas.atual + pessoas.grupo), e as chaves vêm dos
    -- identificadores e do comprador/aluno ligado. Só leitura na base do Arthur.
    v_n3 := $n3$
      with ld as (
        select e.projeto_id, pessoas.atual(e.pessoa_id) as pessoa, min(e.quando) as primeiro
          from pessoas.eventos e
         where e.tipo = 'lead' and e.projeto_id in (select c.projeto_id from cand c)
         group by 1, 2
      ), gp as (
        select ld.projeto_id, min(ld.primeiro) as primeiro, g.id as pid
          from ld cross join lateral unnest(pessoas.grupo(ld.pessoa)) g(id) group by 1, 3
      ), lp as (
        select gp.projeto_id, gp.primeiro, k.tipo, k.chave
          from gp
          join pessoas.pessoas p on p.id = gp.pid
          left join public.compradores co on co.id = p.comprador_id
          left join public.thb_alunos al on al.id = p.aluno_id
          cross join lateral (
            select i.tipo, i.chave from pessoas.identificadores i where i.pessoa_id = gp.pid and i.tipo in ('email', 'telefone')
            union all select 'email', lower(btrim(co.email::text))
            union all select 'documento', nullif(regexp_replace(coalesce(co.documento, ''), '[^0-9]', '', 'g'), '')
            union all select 'telefone', pessoas.chave_telefone(co.telefone::text)
            union all select 'email', lower(btrim(al.email))
            union all select 'documento', nullif(regexp_replace(coalesce(al.documento, ''), '[^0-9]', '', 'g'), '')
            union all select 'telefone', pessoas.chave_telefone(coalesce(al.telefone_e164, al.telefone))) k(tipo, chave)
         where k.chave is not null and k.chave <> ''
      )
      select distinct c.projeto_id, c.transacao
        from cand c
        cross join lateral (values ('email', lower(btrim(c.comprador_email))),
                                   ('documento', nullif(regexp_replace(coalesce(c.comprador_documento, ''), '[^0-9]', '', 'g'), '')),
                                   ('telefone', pessoas.chave_telefone(c.comprador_telefone))) k(tipo, chave)
        join lp on lp.projeto_id = c.projeto_id and lp.tipo = k.tipo and lp.chave = k.chave and lp.primeiro < c.aprovado_em
    $n3$;
  else
    v_n3 := 'select null::bigint as projeto_id, null::text as transacao where false';
  end if;

  -- SQL dinâmico: fin.hotmart_transacoes (e a base de pessoas) podem não existir num banco local. As faixas de
  -- aprovado_em viram timestamptz (meia-noite de São Paulo) para usar o índice (produto_id, aprovado_em) do financeiro.
  v_sql := $q$
    with vv as (
      select v.projeto_id, v.conta, v.produto_id, v.oferta_codigo, v.oferta_exclusiva,
             (coalesce(v.de, pp.inicio)::timestamp at time zone 'America/Sao_Paulo') as de_ts,
             ((coalesce(v.ate, pp.fim, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp
               at time zone 'America/Sao_Paulo') as ate_ts,
             (v.de::timestamp at time zone 'America/Sao_Paulo') as de_proprio_ts,
             ((v.ate + 1)::timestamp at time zone 'America/Sao_Paulo') as ate_proprio_ts
        from mkt_trafego.produtos_hotmart v cross join lateral mkt_trafego.periodo_receita(v.projeto_id) pp
    ), n1 as (
      -- nível 1: oferta exclusiva (qualquer data; só o de/até próprio do vínculo limita)
      select vv.projeto_id, t.transacao
        from vv join fin.hotmart_transacoes t
          on t.produto_id = vv.produto_id and t.conta = vv.conta and t.oferta_codigo = vv.oferta_codigo
       where vv.oferta_exclusiva and t.status in ('APPROVED', 'COMPLETE') and t.aprovado_em is not null
         and (vv.de_proprio_ts is null or t.aprovado_em >= vv.de_proprio_ts)
         and (vv.ate_proprio_ts is null or t.aprovado_em < vv.ate_proprio_ts)
    ), chaves as (
      select p.id as projeto_id, k.chave
        from mkt.projetos p
        cross join lateral (values (mkt_trafego.chave_norm(p.sigla)), (mkt_trafego.chave_norm(p.etiqueta_clickup))) k(chave)
       where k.chave is not null
    ), n2 as (
      -- nível 2: SCK com o projeto (campo campanha = chave ou sigla), qualquer produto e data
      select distinct ch.projeto_id, t.transacao
        from fin.hotmart_transacoes t
        join chaves ch on ch.chave = mkt_trafego.sck_campanha(t.origem_sck)
       where t.status in ('APPROVED', 'COMPLETE') and t.aprovado_em is not null and t.origem_sck like '%|%'
    ), cand as (
      -- candidatos dos níveis 3 e 4: produto ligado ao projeto (oferta, se o vínculo tiver), dentro do período do vínculo
      select distinct vv.projeto_id, t.transacao, t.aprovado_em, t.comprador_email, t.comprador_documento, t.comprador_telefone
        from vv join fin.hotmart_transacoes t
          on t.produto_id = vv.produto_id and t.conta = vv.conta
         and (vv.oferta_codigo is null or t.oferta_codigo = vv.oferta_codigo)
         and t.aprovado_em >= vv.de_ts and t.aprovado_em < vv.ate_ts
       where vv.de_ts is not null and t.status in ('APPROVED', 'COMPLETE')
    ), n3 as (
      /*NIVEL3*/
    ), niv as (
      select n1.projeto_id, n1.transacao, 1 as nivel from n1
      union all select n2.projeto_id, n2.transacao, 2 from n2
      union all select n3.projeto_id, n3.transacao, 3 from n3
      union all select cand.projeto_id, cand.transacao, 4 from cand
    ), por_projeto as (
      -- o nível mais forte da venda em cada projeto (a mesma venda por dois vínculos do projeto conta 1 vez)
      select niv.projeto_id, niv.transacao, min(niv.nivel) as nivel from niv group by 1, 2
    ), vencedores as (
      -- a venda fica só com o(s) projeto(s) do nível mais forte dela
      select x.projeto_id, x.transacao, x.nivel,
             count(*) over (partition by x.transacao) as n,
             array_agg(x.projeto_id) over (partition by x.transacao) as projs
        from (select pp.*, min(pp.nivel) over (partition by pp.transacao) as melhor from por_projeto pp) x
       where x.nivel = x.melhor
    )
    select w.projeto_id, w.transacao, w.nivel::smallint, w.n > 1,
           case when w.n > 1 then (select array_agg(distinct z order by z) from unnest(w.projs) z) end,
           t.conta, t.produto_id, t.oferta_codigo, t.aprovado_em, coalesce(t.moeda, 'BRL'),
           b.bruto, coalesce(t.liquido_produtor, b.bruto - coalesce(t.taxa_hotmart, 0)), t.liquido_produtor is null
      from vencedores w
      join fin.hotmart_transacoes t on t.transacao = w.transacao
      cross join lateral (select coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric,
                                          t.valor_cobrado) as bruto) b
     where $1 is null or w.projeto_id = $1
  $q$;
  return query execute replace(v_sql, '/*NIVEL3*/', v_n3) using p_projeto;
end
$$;

-- Receita por projeto: {"<projeto_id>": {...}}. Projeto sem vínculo e sem venda certa não aparece (a tela mostra "sem
-- dado"). Campos (bruto = valor da oferta, só BRL na soma; líquido = líquido do produtor):
--   receita, receita_liquida            níveis 1 a 3 (A RECEITA DO PROJETO). Nula = sem fonte, ou sem vínculo com
--                                       período, sem oferta exclusiva e sem venda certa.
--   receita_oferta/_sck/_lead           a quebra por nível (1, 2, 3); receita_compras_oferta/_sck/_lead as vendas
--   receita_estimada                    nível 4 (só produto + período), À PARTE; nula = sem vínculo com período
--   receita_compras                     vendas dos níveis 1 a 3 (todas as moedas); receita_compras_estimada as do nível 4
--   receita_disputa                     vendas em disputa com outro projeto (qualquer nível; não somam em nenhum)
--   receita_ofertas_exclusivas          ofertas exclusivas ligadas; receita_vinculos, receita_sem_periodo como antes
--   receita_liquido_estimado, receita_outras_moedas, receita_sem_valor: dos níveis 1 a 3
create function mkt_trafego.receita(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_vin jsonb;
  v_som jsonb := '{}'::jsonb;
  v_fonte boolean := mkt_trafego.hotmart_disponivel();
begin
  select coalesce(jsonb_object_agg(x.projeto_id::text, jsonb_build_object('vinculos', x.vinculos, 'sem_periodo', x.sem_periodo,
                                                                          'exclusivas', x.exclusivas)), '{}'::jsonb)
    into v_vin
    from (select v.projeto_id, count(*) as vinculos, count(*) filter (where coalesce(v.de, pp.inicio) is null) as sem_periodo,
                 count(*) filter (where v.oferta_exclusiva) as exclusivas
            from mkt_trafego.produtos_hotmart v cross join lateral mkt_trafego.periodo_receita(v.projeto_id) pp
           where p_projeto is null or v.projeto_id = p_projeto
           group by v.projeto_id) x;

  if v_fonte then
    select coalesce(jsonb_object_agg(x.projeto_id::text, to_jsonb(x) - 'projeto_id'), '{}'::jsonb)
      into v_som
      from (select m.projeto_id,
                   coalesce(sum(m.bruto) filter (where not m.disputa and m.nivel <= 3 and m.moeda = 'BRL'), 0) as certa,
                   coalesce(sum(m.liquido) filter (where not m.disputa and m.nivel <= 3 and m.moeda = 'BRL'), 0) as liquida,
                   coalesce(sum(m.bruto) filter (where not m.disputa and m.nivel = 1 and m.moeda = 'BRL'), 0) as n1,
                   coalesce(sum(m.bruto) filter (where not m.disputa and m.nivel = 2 and m.moeda = 'BRL'), 0) as n2,
                   coalesce(sum(m.bruto) filter (where not m.disputa and m.nivel = 3 and m.moeda = 'BRL'), 0) as n3,
                   coalesce(sum(m.bruto) filter (where not m.disputa and m.nivel = 4 and m.moeda = 'BRL'), 0) as n4,
                   count(*) filter (where not m.disputa and m.nivel = 1) as c1,
                   count(*) filter (where not m.disputa and m.nivel = 2) as c2,
                   count(*) filter (where not m.disputa and m.nivel = 3) as c3,
                   count(*) filter (where not m.disputa and m.nivel = 4) as c4,
                   count(*) filter (where not m.disputa and m.nivel <= 3) as compras,
                   count(*) filter (where not m.disputa and m.nivel <= 3 and m.moeda = 'BRL' and m.liquido_estimado) as estimado,
                   count(*) filter (where not m.disputa and m.nivel <= 3 and m.moeda <> 'BRL') as outras,
                   count(*) filter (where not m.disputa and m.nivel <= 3 and m.bruto is null) as sem_valor,
                   count(*) filter (where m.disputa) as disputa
              from mkt_trafego.receita_vendas(p_projeto) m
             group by m.projeto_id) x;
  end if;

  return (select coalesce(jsonb_object_agg(k.k, jsonb_build_object(
            'receita', case when k.tem then round(coalesce((v_som -> k.k ->> 'certa')::numeric, 0), 2) end,
            'receita_liquida', case when k.tem then round(coalesce((v_som -> k.k ->> 'liquida')::numeric, 0), 2) end,
            'receita_oferta', case when k.tem then round(coalesce((v_som -> k.k ->> 'n1')::numeric, 0), 2) end,
            'receita_sck', case when k.tem then round(coalesce((v_som -> k.k ->> 'n2')::numeric, 0), 2) end,
            'receita_lead', case when k.tem then round(coalesce((v_som -> k.k ->> 'n3')::numeric, 0), 2) end,
            'receita_estimada', case when v_fonte and k.com_periodo > 0 then round(coalesce((v_som -> k.k ->> 'n4')::numeric, 0), 2) end,
            'receita_compras_oferta', case when v_fonte then coalesce((v_som -> k.k ->> 'c1')::int, 0) end,
            'receita_compras_sck', case when v_fonte then coalesce((v_som -> k.k ->> 'c2')::int, 0) end,
            'receita_compras_lead', case when v_fonte then coalesce((v_som -> k.k ->> 'c3')::int, 0) end,
            'receita_compras_estimada', case when v_fonte then coalesce((v_som -> k.k ->> 'c4')::int, 0) end,
            'receita_disputa', case when v_fonte then coalesce((v_som -> k.k ->> 'disputa')::int, 0) end,
            'receita_liquido_estimado', case when v_fonte then coalesce((v_som -> k.k ->> 'estimado')::int, 0) end,
            'receita_compras', case when v_fonte then coalesce((v_som -> k.k ->> 'compras')::int, 0) end,
            'receita_outras_moedas', case when v_fonte then coalesce((v_som -> k.k ->> 'outras')::int, 0) end,
            'receita_sem_valor', case when v_fonte then coalesce((v_som -> k.k ->> 'sem_valor')::int, 0) end,
            'receita_vinculos', coalesce((v_vin -> k.k ->> 'vinculos')::int, 0),
            'receita_sem_periodo', coalesce((v_vin -> k.k ->> 'sem_periodo')::int, 0),
            'receita_ofertas_exclusivas', coalesce((v_vin -> k.k ->> 'exclusivas')::int, 0))), '{}'::jsonb)
            from (select y.k, y.com_periodo,
                         v_fonte and (y.com_periodo > 0 or coalesce((v_vin -> y.k ->> 'exclusivas')::int, 0) > 0
                                      or coalesce((v_som -> y.k ->> 'compras')::int, 0) > 0
                                      or coalesce((v_som -> y.k ->> 'disputa')::int, 0) > 0) as tem
                    from (select z.k, coalesce((v_vin -> z.k ->> 'vinculos')::int, 0) - coalesce((v_vin -> z.k ->> 'sem_periodo')::int, 0) as com_periodo
                            from (select jsonb_object_keys(v_vin) as k union select jsonb_object_keys(v_som)) z) y) k);
end
$$;

-- O resumo da 20261006g continua igual (vira resumo_base); o novo acrescenta a receita a cada linha. As funções da tela
-- (trafego_resumo, trafego_projeto) chamam mkt_trafego.resumo pelo nome e passam a ver a receita sem mudar.
alter function mkt_trafego.resumo(bigint) rename to resumo_base;
create function mkt_trafego.resumo(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_base jsonb := mkt_trafego.resumo_base(p_projeto);
  v_rec jsonb := mkt_trafego.receita(p_projeto);
  v_fonte boolean := mkt_trafego.hotmart_disponivel();
  v_pessoas boolean := mkt_trafego.pessoas_disponivel();
begin
  return (select coalesce(jsonb_agg(x.e || coalesce(v_rec -> (x.e ->> 'projeto_id'), jsonb_build_object(
                    'receita', null, 'receita_liquida', null, 'receita_liquido_estimado', null, 'receita_compras', null,
                    'receita_outras_moedas', null, 'receita_sem_valor', null, 'receita_vinculos', 0, 'receita_sem_periodo', 0,
                    'receita_oferta', null, 'receita_sck', null, 'receita_lead', null, 'receita_estimada', null,
                    'receita_compras_oferta', null, 'receita_compras_sck', null, 'receita_compras_lead', null,
                    'receita_compras_estimada', null, 'receita_disputa', null, 'receita_ofertas_exclusivas', 0))
                  || jsonb_build_object('receita_fonte', v_fonte, 'receita_base_pessoas', v_pessoas)
                  order by x.o), '[]'::jsonb)
            from jsonb_array_elements(v_base) with ordinality x(e, o));
end
$$;

-- ─── 5. Resumo do dia (interna) ──────────────────────────────────────────────────────────────────────────────────────
create function mkt_trafego.alertas() returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ontem date := mkt_trafego.ontem();
  v_res jsonb := mkt_trafego.resumo(null);
  v_alertas jsonb;
begin
  with rg as (
    select * from mkt_trafego.alerta_regras where ligada
  ), r as (
    select x.* from jsonb_to_recordset(v_res) as x(
      projeto_id bigint, sigla text, nome text, projeto_ativo boolean, status text, investido numeric, verba_maxima numeric,
      verba_diaria numeric, gasto_ontem numeric, ritmo_ontem numeric, pct_verba numeric, leads bigint, meta_leads integer,
      cpl numeric, meta_cpl numeric, inicio date, fim date)
  ), alvo as (
    select r.* from r left join mkt_trafego.status_projeto s on s.codigo = r.status
     where r.projeto_ativo and coalesce(s.entra_no_resumo_dia, true)
  ), lim as (
    select codigo, limiar from rg
  ),
  -- 1. acima da verba diária (ontem)
  a1 as (
    select 'acima_verba_diaria'::text as regra, a.projeto_id, a.gasto_ontem as valor, a.verba_diaria as referencia,
           jsonb_build_object('pct', a.ritmo_ontem) as detalhe
      from alvo a join lim l on l.codigo = 'acima_verba_diaria'
     where a.investido is not null and a.verba_diaria > 0 and a.gasto_ontem > a.verba_diaria * (1 + l.limiar / 100)
  ),
  -- 2. CPL acima da meta
  a2 as (
    select 'cpl_acima_meta'::text, a.projeto_id, a.cpl, a.meta_cpl::numeric,
           jsonb_build_object('pct', round(a.cpl / a.meta_cpl * 100, 1))
      from alvo a join lim l on l.codigo = 'cpl_acima_meta'
     where a.cpl is not null and a.meta_cpl > 0 and a.cpl > a.meta_cpl * (1 + l.limiar / 100)
  ),
  -- 3. abaixo da meta de leads para a data
  pl as (
    select a.projeto_id, a.leads, a.meta_leads,
           case when cap.inicio is not null and cap.fim is not null then cap.inicio else pp.inicio end as ini,
           case when cap.inicio is not null and cap.fim is not null then cap.fim else pp.fim end as fim,
           case when cap.inicio is not null and cap.fim is not null then 'captacao' else 'projeto' end as periodo
      from alvo a
      cross join lateral mkt_trafego.periodo_padrao(a.projeto_id) pp
      left join mkt_trafego.projeto_fases cap on cap.projeto_id = a.projeto_id and cap.fase = 'captacao'
     where a.leads is not null and a.meta_leads > 0
  ), pl2 as (
    select pl.*, round(pl.meta_leads * least(1, (v_ontem - pl.ini + 1)::numeric / (pl.fim - pl.ini + 1))) as esperado
      from pl where pl.ini is not null and pl.fim is not null and pl.ini <= v_ontem
  ), a3 as (
    select 'leads_abaixo_meta'::text, p.projeto_id, p.leads::numeric, p.esperado,
           jsonb_build_object('meta', p.meta_leads, 'periodo', p.periodo, 'inicio', p.ini, 'fim', p.fim,
                              'pct', case when p.esperado > 0 then round(p.leads / p.esperado * 100, 1) end)
      from pl2 p join lim l on l.codigo = 'leads_abaixo_meta'
     where p.esperado > 0 and p.leads < p.esperado * (1 - l.limiar / 100)
  ),
  -- 4. ritmo da fase em andamento
  fz as (
    select f.projeto_id, f.fase, fs.nome, f.verba, f.inicio, f.fim,
           round(f.verba * (v_ontem - f.inicio + 1)::numeric / (f.fim - f.inicio + 1), 2) as esperado,
           (select coalesce(sum(d.gasto), 0) from mkt_trafego.desempenho_dia d
              join mkt_trafego.campanhas c on c.id = d.campanha_id
             where c.projeto_id = f.projeto_id and mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) = f.fase
               and d.dia between f.inicio and v_ontem) as gasto
      from mkt_trafego.projeto_fases f
      join mkt_trafego.fases fs on fs.codigo = f.fase
      join alvo a on a.projeto_id = f.projeto_id
     where f.verba > 0 and f.inicio <= v_ontem and f.fim >= v_ontem and a.investido is not null
  ), a4 as (
    select 'ritmo_fase'::text, z.projeto_id, z.gasto, z.esperado,
           jsonb_build_object('fase', z.fase, 'fase_nome', z.nome, 'verba', z.verba, 'inicio', z.inicio, 'fim', z.fim,
                              'direcao', case when z.gasto > z.esperado then 'acima' else 'abaixo' end,
                              'pct', round(z.gasto / z.esperado * 100, 1))
      from fz z join lim l on l.codigo = 'ritmo_fase'
     where z.esperado > 0
       and (z.gasto > z.esperado * (1 + l.limiar / 100) or z.gasto < z.esperado * (1 - l.limiar / 100))
  ),
  -- 5. % da verba perto do fim
  a5 as (
    select 'verba_perto_fim'::text, a.projeto_id, a.pct_verba, l.limiar,
           jsonb_build_object('investido', a.investido, 'verba_maxima', a.verba_maxima)
      from alvo a join lim l on l.codigo = 'verba_perto_fim'
     where a.pct_verba is not null and a.pct_verba >= l.limiar
  ),
  -- 6 e 7. campanhas fora do padrão / sem fase que gastaram nos últimos N dias
  recentes as (
    select c.id, c.projeto_id, c.fora_padrao, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase,
           (select max(d.dia) from mkt_trafego.desempenho_dia d where d.campanha_id = c.id and d.gasto > 0) as ultimo_gasto
      from mkt_trafego.campanhas c
  ), a6 as (
    select 'fora_padrao'::text, x.projeto_id, count(*)::numeric, null::numeric,
           jsonb_build_object('dias', l.limiar)
      from recentes x join lim l on l.codigo = 'fora_padrao'
     where x.fora_padrao and x.ultimo_gasto > v_ontem - l.limiar::int
       and (x.projeto_id is null or x.projeto_id in (select projeto_id from alvo))
     group by x.projeto_id, l.limiar
  ), a7 as (
    select 'sem_fase'::text, x.projeto_id, count(*)::numeric, null::numeric,
           jsonb_build_object('dias', l.limiar)
      from recentes x join lim l on l.codigo = 'sem_fase'
     where x.fase is null and x.projeto_id in (select projeto_id from alvo) and x.ultimo_gasto > v_ontem - l.limiar::int
     group by x.projeto_id, l.limiar
  ), todos as (
    select * from a1 union all select * from a2 union all select * from a3 union all select * from a4
    union all select * from a5 union all select * from a6 union all select * from a7
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'regra', t.regra, 'nome', rg.nome, 'gravidade', rg.gravidade, 'limiar', rg.limiar, 'unidade', rg.unidade,
           'projeto_id', t.projeto_id, 'sigla', r.sigla, 'projeto_nome', r.nome,
           'valor', t.valor, 'referencia', t.referencia, 'detalhe', t.detalhe)
         order by case rg.gravidade when 'alta' then 0 else 1 end, rg.ordem, r.sigla nulls last), '[]'::jsonb)
    into v_alertas
    from todos t(regra, projeto_id, valor, referencia, detalhe)
    join rg on rg.codigo = t.regra
    left join r on r.projeto_id = t.projeto_id;

  return jsonb_build_object(
    'dia', v_ontem,
    'sem_coleta', not exists (select 1 from mkt_trafego.desempenho_dia),
    'base_pessoas', to_regclass('pessoas.eventos') is not null,
    'projetos_avaliados', (select count(*) from jsonb_to_recordset(v_res) as x(projeto_id bigint, projeto_ativo boolean, status text)
                             left join mkt_trafego.status_projeto s on s.codigo = x.status
                            where x.projeto_ativo and coalesce(s.entra_no_resumo_dia, true)),
    'alertas', v_alertas,
    'regras', (select coalesce(jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nome', g.nome, 'ligada', g.ligada,
                 'limiar', g.limiar, 'unidade', g.unidade, 'gravidade', g.gravidade, 'descricao', g.descricao) order by g.ordem), '[]'::jsonb)
                 from mkt_trafego.alerta_regras g),
    'coletas', (select coalesce(jsonb_object_agg(k.fonte, jsonb_build_object('em', k.em, 'ok', k.ok, 'erro', k.erro)), '{}'::jsonb)
                  from (select distinct on (c.fonte) c.fonte, c.em, c.ok, c.erro from mkt_trafego.coletas c
                         order by c.fonte, c.id desc) k));
end
$$;

-- ─── 6. Coleta: credenciais e parâmetros (internas, SEM grant: só o postgres, isto é, a Edge com SUPABASE_DB_URL) ────
-- Lê um segredo do Vault pelo nome. Sem Vault (banco local): nulo.
create function mkt_trafego.segredo(p_nome text) returns text
language plpgsql stable set search_path = '' as $$
declare v text;
begin
  if p_nome is null or to_regclass('vault.decrypted_secrets') is null then return null; end if;
  execute 'select s.decrypted_secret from vault.decrypted_secrets s where s.name = $1' into v using p_nome;
  return v;
end
$$;

create function mkt_trafego.coleta_chave() returns text
language sql stable set search_path = '' as $$ select mkt_trafego.segredo('trafego_coleta_chave') $$;

-- Contas Meta ativas e o token de cada uma: o segredo da própria conta (token_vault) ou, sem ele, o da conta
-- centralizadora (meta_ads_token). token nulo = segredo não cadastrado (a rotina registra "sem_token" para a conta).
create function mkt_trafego.meta_contas() returns table (conta_id bigint, conta_externa text, nome text, moeda text,
                                                         token_origem text, token text)
language sql stable set search_path = '' as $$
  select c.id, c.conta_externa, c.nome, c.moeda, coalesce(c.token_vault, 'meta_ads_token'),
         mkt_trafego.segredo(coalesce(c.token_vault, 'meta_ads_token'))
    from mkt_trafego.contas c
   where c.plataforma = 'meta' and c.ativa
   order by c.id
$$;

create function mkt_trafego.clickup_credenciais() returns table (token text, team_id text)
language sql stable set search_path = '' as $$
  select mkt_trafego.segredo('clickup_api_token'),
         (select nullif(btrim(k.valor), '') from mkt_trafego.coleta_config k where k.chave = 'clickup_team_id')
$$;

-- Etiquetas que a rotina do ClickUp lê: as dos projetos ATIVOS de mkt.projetos.
create function mkt_trafego.clickup_etiquetas() returns setof text
language sql stable set search_path = '' as $$
  select p.etiqueta_clickup from mkt.projetos p where p.ativo and p.etiqueta_clickup is not null order by p.etiqueta_clickup
$$;

create function mkt_trafego.coleta_parametros() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_object_agg(k.chave, k.valor), '{}'::jsonb) from mkt_trafego.coleta_config k
$$;

-- Registra uma rodada (contagens e falhas; a Edge nunca manda token nem URL). Mantém 200 por fonte.
create function mkt_trafego.coleta_registrar(p_fonte text, p_ok boolean, p_resultado jsonb, p_erro text) returns void
language plpgsql set search_path = '' as $$
begin
  insert into mkt_trafego.coletas (fonte, ok, resultado, erro) values (p_fonte, p_ok, p_resultado, left(p_erro, 500));
  delete from mkt_trafego.coletas c
   where c.fonte = p_fonte and c.id in (select x.id from mkt_trafego.coletas x where x.fonte = p_fonte order by x.id desc offset 200);
end
$$;

-- ─── 7. Funções públicas da tela (authenticated + mkt.pode_ver('mkt_trafego')) ───────────────────────────────────────
create function public.trafego_alertas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return mkt_trafego.alertas();
end
$$;

create function public.trafego_produtos_listar(p_projeto bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb; v_nomes jsonb := '{}'::jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  -- nome do produto: o mais recente que a Hotmart mandou para aquela conta (só para mostrar; o vínculo é pelo id)
  if mkt_trafego.hotmart_disponivel() then
    execute $q$
      select coalesce(jsonb_object_agg(x.chave, x.nome), '{}'::jsonb)
        from (select distinct on (v.conta, v.produto_id) v.conta || '/' || v.produto_id as chave, t.produto_nome as nome
                from mkt_trafego.produtos_hotmart v
                join fin.hotmart_transacoes t on t.produto_id = v.produto_id and t.conta = v.conta
               where ($1 is null or v.projeto_id = $1) and t.produto_nome is not null
               order by v.conta, v.produto_id, t.pedido_em desc nulls last) x
    $q$ into v_nomes using p_projeto;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
            'id', v.id, 'projeto_id', v.projeto_id, 'projeto_sigla', p.sigla, 'conta', v.conta, 'produto_id', v.produto_id,
            'produto_nome', v_nomes ->> (v.conta || '/' || v.produto_id),
            'oferta_codigo', v.oferta_codigo, 'oferta_exclusiva', v.oferta_exclusiva, 'de', v.de, 'ate', v.ate, 'obs', v.obs,
            'de_efetivo', coalesce(v.de, (mkt_trafego.periodo_receita(p.id)).inicio),
            'ate_efetivo', coalesce(v.ate, (mkt_trafego.periodo_receita(p.id)).fim),
            'atualizado_em', v.atualizado_em)
          order by p.sigla, v.conta, v.produto_id, v.oferta_codigo nulls first), '[]'::jsonb)
    into v
    from mkt_trafego.produtos_hotmart v join mkt.projetos p on p.id = v.projeto_id
   where p_projeto is null or v.projeto_id = p_projeto;
  return v;
end
$$;

-- Cria (sem "id") ou edita (com "id"). Campos: projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva (true/false),
-- de, ate, obs. Retorna {ok, msg, id, avisos}. Conta: tem de existir em fin.hotmart_contas (o cadastro de contas do
-- financeiro); sem o financeiro neste banco, só o formato. Oferta exclusiva: exige a oferta, e a oferta (por conta) não
-- pode ser exclusiva de outro projeto (recusa com a sigla dele; o índice único garante). Avisos: produto_em_outro_projeto
-- (a mesma conta e produto ligados a outro projeto com período que se cruza: a venda que casar com os dois no mesmo
-- nível fica em disputa e não soma em nenhum), produto_sem_compras (nenhuma transação desta conta e produto em
-- fin.hotmart_transacoes), sem_periodo (sem "de" e o projeto sem início: não soma até ter data; a oferta exclusiva soma
-- mesmo assim), sem_oferta_exclusiva (o projeto ainda não tem nenhuma oferta exclusiva: a receita dele é só estimada).
create function public.trafego_produto_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint; v_proj bigint; v_de date; v_ate date;
  v_conta text := btrim(coalesce(p ->> 'conta', ''));
  v_prod text := btrim(coalesce(p ->> 'produto_id', ''));
  v_oferta text := nullif(btrim(coalesce(p ->> 'oferta_codigo', '')), '');
  v_exclusiva boolean;
  v_dono text;
  v_restricao text;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_pr mkt.projetos%rowtype;
  v_atual mkt_trafego.produtos_hotmart%rowtype;
  v_pp record;
  v_avisos text[] := '{}';
  v_tem boolean;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_proj := nullif(p ->> 'projeto_id', '')::bigint;
    v_de := nullif(btrim(coalesce(p ->> 'de', '')), '')::date;
    v_ate := nullif(btrim(coalesce(p ->> 'ate', '')), '')::date;
    v_exclusiva := coalesce(nullif(btrim(coalesce(p ->> 'oferta_exclusiva', '')), '')::boolean, false);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido (datas AAAA-MM-DD; oferta exclusiva true ou false).');
  end;
  select * into v_pr from mkt.projetos where id = v_proj;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  if v_conta !~ '^[a-z][a-z0-9_]{1,29}$' then
    return jsonb_build_object('ok', false, 'msg', 'Escolha a conta da Hotmart.');
  end if;
  if to_regclass('fin.hotmart_contas') is not null then
    execute 'select exists (select 1 from fin.hotmart_contas c where c.conta = $1)' into v_tem using v_conta;
    if not v_tem then return jsonb_build_object('ok', false, 'msg', 'Conta da Hotmart desconhecida: ' || v_conta || '.'); end if;
  end if;
  if v_prod !~ '^[A-Za-z0-9_-]{1,40}$' then
    return jsonb_build_object('ok', false, 'msg', 'Id do produto na Hotmart inválido (só letras, números, - e _).');
  end if;
  if v_oferta is not null and v_oferta !~ '^[A-Za-z0-9_-]{1,40}$' then
    return jsonb_build_object('ok', false, 'msg', 'Código da oferta inválido.');
  end if;
  if v_de is not null and v_ate is not null and v_ate < v_de then
    return jsonb_build_object('ok', false, 'msg', 'O fim não pode ser antes do início.');
  end if;
  if v_exclusiva and v_oferta is null then
    return jsonb_build_object('ok', false, 'msg', 'Oferta exclusiva precisa da oferta: escolha a oferta criada na Hotmart só para este projeto.');
  end if;
  if v_exclusiva then
    select pr.sigla into v_dono
      from mkt_trafego.produtos_hotmart o join mkt.projetos pr on pr.id = o.projeto_id
     where o.oferta_exclusiva and o.conta = v_conta and o.oferta_codigo = v_oferta and o.id is distinct from v_id
     limit 1;
    if v_dono is not null then
      return jsonb_build_object('ok', false, 'msg', 'A oferta ' || v_oferta || ' (' || v_conta || ') já é exclusiva de ' || v_dono
                                || '. Uma oferta só pode ser exclusiva de um projeto: crie outra oferta na Hotmart.');
    end if;
  end if;

  begin
    if v_id is null then
      insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva, de, ate, obs, criado_por, atualizado_por)
      values (v_proj, v_conta, v_prod, v_oferta, v_exclusiva, v_de, v_ate, v_obs, v_uid, v_uid) returning id into v_id;
    else
      select * into v_atual from mkt_trafego.produtos_hotmart where id = v_id for update;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Vínculo não encontrado.'); end if;
      if v_atual.projeto_id <> v_proj then return jsonb_build_object('ok', false, 'msg', 'O vínculo é de outro projeto.'); end if;
      update mkt_trafego.produtos_hotmart
         set conta = v_conta, produto_id = v_prod, oferta_codigo = v_oferta, oferta_exclusiva = v_exclusiva, de = v_de, ate = v_ate,
             obs = v_obs, atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
    end if;
  exception when unique_violation then
    get stacked diagnostics v_restricao = constraint_name;
    if v_restricao = 'produtos_hotmart_oferta_exclusiva_unica' then
      return jsonb_build_object('ok', false, 'msg', 'A oferta ' || v_oferta || ' (' || v_conta || ') já é exclusiva de outro projeto. '
                                || 'Uma oferta só pode ser exclusiva de um projeto.');
    end if;
    return jsonb_build_object('ok', false, 'msg', 'Este produto (conta e oferta) já está ligado a este projeto.');
  end;

  select * into v_pp from mkt_trafego.periodo_receita(v_proj);
  if exists (select 1 from mkt_trafego.produtos_hotmart o cross join lateral mkt_trafego.periodo_receita(o.projeto_id) op
              where o.conta = v_conta and o.produto_id = v_prod and o.projeto_id <> v_proj
                and (o.oferta_codigo is null or v_oferta is null or o.oferta_codigo = v_oferta)
                and coalesce(o.de, op.inicio, '-infinity'::date) <= coalesce(v_ate, v_pp.fim, 'infinity'::date)
                and coalesce(v_de, v_pp.inicio, '-infinity'::date) <= coalesce(o.ate, op.fim, 'infinity'::date)) then
    v_avisos := array_append(v_avisos, 'produto_em_outro_projeto');
  end if;
  if coalesce(v_de, v_pp.inicio) is null then v_avisos := array_append(v_avisos, 'sem_periodo'); end if;
  if mkt_trafego.hotmart_disponivel() then
    execute 'select exists (select 1 from fin.hotmart_transacoes t where t.produto_id = $1 and t.conta = $2)' into v_tem using v_prod, v_conta;
    if not v_tem then v_avisos := array_append(v_avisos, 'produto_sem_compras'); end if;
  end if;
  if not exists (select 1 from mkt_trafego.produtos_hotmart o where o.projeto_id = v_proj and o.oferta_exclusiva) then
    v_avisos := array_append(v_avisos, 'sem_oferta_exclusiva');
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Produto ' || v_prod || ' (' || v_conta || ') ligado a ' || v_pr.sigla
                            || case when v_exclusiva then ' como oferta exclusiva (' || v_oferta || ')' else '' end || '.', 'id', v_id,
                            'avisos', to_jsonb(v_avisos));
end
$$;

create function public.trafego_produto_apagar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt_trafego.produtos_hotmart where id = p_id) then
    return jsonb_build_object('ok', false, 'msg', 'Vínculo não encontrado.');
  end if;
  delete from mkt_trafego.produtos_hotmart where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Vínculo apagado. A receita do projeto deixa de contar este produto.');
end
$$;

-- Receita do projeto por nível de certeza, para a vida do projeto: a quebra (oferta exclusiva, SCK, lead do projeto,
-- estimada à parte), as vendas em disputa (até 200, as mais recentes; sem dado do comprador) e o que falta para a
-- receita deixar de ser só estimada. Regra: seção 4b (mkt_trafego.receita_vendas). Nulo = projeto não existe.
create function public.trafego_receita(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_p mkt.projetos%rowtype;
  v_r jsonb;
  v_disp jsonb := '[]'::jsonb;
  v_ndisp int := 0;
  v_vinc int; v_excl int;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into v_p from mkt.projetos where id = p_projeto;
  if not found then return null; end if;
  v_r := mkt_trafego.receita(p_projeto) -> p_projeto::text;
  select count(*), count(*) filter (where v.oferta_exclusiva) into v_vinc, v_excl
    from mkt_trafego.produtos_hotmart v where v.projeto_id = p_projeto;
  select count(*), coalesce(jsonb_agg(jsonb_build_object(
           'transacao', d.transacao, 'dia', (d.aprovado_em at time zone 'America/Sao_Paulo')::date, 'conta', d.conta,
           'produto_id', d.produto_id, 'oferta_codigo', d.oferta_codigo, 'nivel', d.nivel, 'valor', d.bruto, 'moeda', d.moeda,
           'projetos', (select coalesce(jsonb_agg(pr.sigla order by pr.sigla), '[]'::jsonb) from mkt.projetos pr
                         where pr.id = any (d.projetos_disputa)))
           order by d.aprovado_em desc, d.transacao) filter (where d.ordem <= 200), '[]'::jsonb)
    into v_ndisp, v_disp
    from (select m.*, row_number() over (order by m.aprovado_em desc, m.transacao) as ordem
            from mkt_trafego.receita_vendas(p_projeto) m where m.disputa) d;
  return jsonb_build_object(
    'projeto_id', p_projeto,
    'fonte', mkt_trafego.hotmart_disponivel(),
    'base_pessoas', mkt_trafego.pessoas_disponivel(),
    'receita', v_r,
    'vinculos', v_vinc,
    'ofertas_exclusivas', v_excl,
    -- o aviso grande da vida do projeto: tem produto ligado e nenhuma oferta exclusiva = a receita é só estimada
    'sem_oferta_exclusiva', v_vinc > 0 and v_excl = 0,
    'sck_formato', 'origem|meio|campanha|conteúdo|termo',
    'sck_chaves', to_jsonb(array_remove(array[lower(v_p.etiqueta_clickup), lower(v_p.sigla)], null)),
    'disputas_total', v_ndisp,
    'disputas', v_disp);
end
$$;

-- Produtos que já apareceram em fin.hotmart_transacoes, por conta, para o seletor do cadastro (nada é ligado sozinho).
-- Cada produto traz as ofertas vistas (até 60, as mais recentes), com exclusiva_de = sigla do projeto de quem a oferta
-- já é exclusiva (nulo = de ninguém). Sem dado pessoal. Pagas = APPROVED ou COMPLETE.
create function public.trafego_hotmart_produtos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not mkt_trafego.hotmart_disponivel() then return '[]'::jsonb; end if;
  execute $q$
    with o as (
      select t.conta, t.produto_id, t.oferta_codigo,
             count(*) filter (where t.status in ('APPROVED', 'COMPLETE')) as pagas,
             max(coalesce(t.aprovado_em, t.pedido_em)) as ultima_ts
        from fin.hotmart_transacoes t
       where coalesce(t.produto_id, '') <> ''
       group by 1, 2, 3
    ), nomes as (
      select distinct on (t.conta, t.produto_id) t.conta, t.produto_id, t.produto_nome
        from fin.hotmart_transacoes t
       where t.produto_nome is not null
       order by t.conta, t.produto_id, t.pedido_em desc nulls last
    ), pr as (
      select o.conta, o.produto_id, sum(o.pagas) as pagas,
             (max(o.ultima_ts) at time zone 'America/Sao_Paulo')::date as ultima,
             coalesce(jsonb_agg(jsonb_build_object('codigo', o.oferta_codigo, 'pagas', o.pagas,
                                                   'ultima', (o.ultima_ts at time zone 'America/Sao_Paulo')::date,
                                                   'exclusiva_de', (select pr.sigla from mkt_trafego.produtos_hotmart x
                                                                      join mkt.projetos pr on pr.id = x.projeto_id
                                                                     where x.oferta_exclusiva and x.conta = o.conta
                                                                       and x.oferta_codigo = o.oferta_codigo))
                                order by o.ultima_ts desc nulls last) filter (where o.oferta_codigo is not null), '[]'::jsonb) as ofertas
        from o group by o.conta, o.produto_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'conta', pr.conta, 'produto_id', pr.produto_id, 'nome', n.produto_nome, 'aprovadas', pr.pagas,
             'ultima', pr.ultima,
             'ofertas', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(pr.ofertas) e limit 60) z))
           order by pr.conta, pr.ultima desc nulls last), '[]'::jsonb)
      from pr left join nomes n on n.conta = pr.conta and n.produto_id = pr.produto_id
  $q$ into v;
  return v;
end
$$;

-- Atividades do ClickUp do projeto (pela etiqueta), as mais recentes primeiro (até 300).
create function public.trafego_clickup(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_etq text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt.projetos where id = p_projeto) then return null; end if;
  select etiqueta_clickup into v_etq from mkt.projetos where id = p_projeto;
  return jsonb_build_object(
    'etiqueta', v_etq,
    'configurado', exists (select 1 from mkt_trafego.coleta_config where chave = 'clickup_team_id' and nullif(btrim(valor), '') is not null),
    'ultima_coleta', (select jsonb_build_object('em', c.em, 'ok', c.ok, 'erro', c.erro) from mkt_trafego.coletas c
                       where c.fonte = 'clickup' order by c.id desc limit 1),
    'tarefas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', t.tarefa_id, 'nome', t.nome, 'status', t.status, 'criada_em', t.criada_em, 'atualizada_em', t.atualizada_em,
                  'inicio', t.inicio, 'prazo', t.prazo, 'concluida_em', t.concluida_em, 'responsaveis', to_jsonb(t.responsaveis),
                  'url', t.url) order by t.ref desc nulls last, t.tarefa_id), '[]'::jsonb)
                  from (select x.*, coalesce(x.concluida_em, x.prazo, x.inicio, x.criada_em) as ref
                          from mkt_trafego.clickup_tarefas x
                         where v_etq is not null and x.etiquetas @> array[v_etq]
                         order by ref desc nulls last limit 300) t));
end
$$;

-- ─── 8. Entrada da rotina do ClickUp (só service_role; a Edge entra como postgres) ──────────────────────────────────
-- p = {"etiqueta": "<etiqueta do projeto>", "tarefas": [{id, nome, status, criada_em, atualizada_em, inicio, prazo,
-- concluida_em, responsaveis: [..], etiquetas: [..], url}]} com TODAS as tarefas que têm a etiqueta hoje (a rotina só
-- chama depois de ler todas as páginas). Upsert por id; quem tinha a etiqueta e não veio perde a etiqueta (e some se
-- ficar sem nenhuma). Datas em ISO 8601. Retorna {ok, gravadas, removidas, recusas}.
create function public.trafego_clickup_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_etq text := btrim(coalesce(p ->> 'etiqueta', ''));
  e jsonb;
  v_ids text[] := '{}';
  v_id text; v_nome text; v_etqs text[]; v_resp text[];
  v_cri timestamptz; v_atu timestamptz; v_ini timestamptz; v_prazo timestamptz; v_fim timestamptz;
  v_url text;
  v_n int := 0; v_rem int := 0;
  v_recusas jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from mkt.projetos where etiqueta_clickup = v_etq) then
    return jsonb_build_object('ok', false, 'msg', 'Etiqueta de nenhum projeto.');
  end if;
  if jsonb_typeof(p -> 'tarefas') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava a lista "tarefas".');
  end if;
  if jsonb_array_length(p -> 'tarefas') > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por etiqueta).');
  end if;
  for e in select * from jsonb_array_elements(p -> 'tarefas') loop
    v_id := btrim(coalesce(e ->> 'id', ''));
    v_nome := left(btrim(coalesce(e ->> 'nome', '')), 500);
    if v_id !~ '^[A-Za-z0-9_-]{1,40}$' then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'id_invalido'); continue;
    end if;
    if v_nome = '' then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'nome_vazio'); continue;
    end if;
    begin
      v_cri := nullif(e ->> 'criada_em', '')::timestamptz;
      v_atu := nullif(e ->> 'atualizada_em', '')::timestamptz;
      v_ini := nullif(e ->> 'inicio', '')::timestamptz;
      v_prazo := nullif(e ->> 'prazo', '')::timestamptz;
      v_fim := nullif(e ->> 'concluida_em', '')::timestamptz;
      select coalesce(array_agg(distinct lower(btrim(x))) filter (where btrim(x) <> ''), '{}') into v_etqs
        from jsonb_array_elements_text(case when jsonb_typeof(e -> 'etiquetas') = 'array' then e -> 'etiquetas' else '[]'::jsonb end) x;
      select coalesce(array_agg(left(btrim(x), 80)) filter (where btrim(x) <> ''), '{}') into v_resp
        from (select x from jsonb_array_elements_text(case when jsonb_typeof(e -> 'responsaveis') = 'array' then e -> 'responsaveis' else '[]'::jsonb end) x limit 20) y;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'formato_invalido'); continue;
    end;
    if not (v_etq = any (v_etqs)) then v_etqs := array_append(v_etqs, v_etq); end if;
    v_etqs := v_etqs[1:50];
    v_url := case when coalesce(e ->> 'url', '') ~ '^https://app\.clickup\.com/' then left(e ->> 'url', 300) end;
    insert into mkt_trafego.clickup_tarefas as t (tarefa_id, nome, status, criada_em, atualizada_em, inicio, prazo, concluida_em,
                                                   responsaveis, etiquetas, url, coletado_em)
    values (v_id, v_nome, nullif(left(btrim(coalesce(e ->> 'status', '')), 60), ''), v_cri, v_atu, v_ini, v_prazo, v_fim,
            v_resp, v_etqs, v_url, now())
    on conflict (tarefa_id) do update
       set nome = excluded.nome, status = excluded.status, criada_em = excluded.criada_em, atualizada_em = excluded.atualizada_em,
           inicio = excluded.inicio, prazo = excluded.prazo, concluida_em = excluded.concluida_em,
           responsaveis = excluded.responsaveis, etiquetas = excluded.etiquetas, url = excluded.url, coletado_em = now();
    v_ids := array_append(v_ids, v_id);
    v_n := v_n + 1;
  end loop;

  -- quem tinha a etiqueta e não veio: tira a etiqueta; sem nenhuma, sai do espelho
  with tirar as (
    update mkt_trafego.clickup_tarefas t set etiquetas = array_remove(t.etiquetas, v_etq), coletado_em = now()
     where t.etiquetas @> array[v_etq] and not (t.tarefa_id = any (v_ids)) and cardinality(t.etiquetas) > 1
    returning 1
  ) select count(*) into v_rem from tirar;
  with apagar as (
    delete from mkt_trafego.clickup_tarefas t
     where t.etiquetas = array[v_etq] and not (t.tarefa_id = any (v_ids))
    returning 1
  ) select v_rem + count(*) into v_rem from apagar;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'removidas', v_rem, 'recusas', v_recusas);
end
$$;

-- ─── 9. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'mkt_trafego'::regnamespace
                   and p.proname in ('resumo', 'receita', 'hotmart_disponivel', 'alertas', 'segredo', 'coleta_chave', 'meta_contas',
                                     'clickup_credenciais', 'clickup_etiquetas', 'coleta_parametros', 'coleta_registrar', 'periodo_padrao', 'periodo_receita',
                                     'chave_norm', 'sck_campanha', 'pessoas_disponivel', 'receita_vendas'))
               or (p.pronamespace = 'public'::regnamespace
                   and p.proname in ('trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                                     'trafego_hotmart_produtos', 'trafego_clickup', 'trafego_clickup_receber', 'trafego_receita')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end
$grants$;
grant execute on function
  public.trafego_alertas(), public.trafego_produtos_listar(bigint), public.trafego_produto_salvar(jsonb),
  public.trafego_produto_apagar(bigint), public.trafego_hotmart_produtos(), public.trafego_clickup(bigint),
  public.trafego_receita(bigint)
  to authenticated;
grant execute on function public.trafego_clickup_receber(jsonb) to service_role;

-- ─── 10. Header das rotinas no Vault (aleatório). Sem Vault (banco local): aviso. As rotinas NÃO são agendadas ──────
do $vault$
begin
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261006i: Vault ausente; segredo trafego_coleta_chave NÃO criado';
    return;
  end if;
  if not exists (select 1 from vault.secrets where name = 'trafego_coleta_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'trafego_coleta_chave', 'Header x-sync-chave das rotinas trafego-meta e trafego-clickup (as Edges conferem). 20261006i.');
  end if;
end
$vault$;

-- ─── 11. Conferência (aborta se algo nasceu aberto ou fora do padrão) ────────────────────────────────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_tela text[] := array['trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                         'trafego_hotmart_produtos', 'trafego_clickup', 'trafego_receita'];
  v_novas text[] := v_tela || array['trafego_clickup_receber'];
  v_internas text[] := array['resumo', 'resumo_base', 'receita', 'hotmart_disponivel', 'alertas', 'segredo', 'coleta_chave',
                             'meta_contas', 'clickup_credenciais', 'clickup_etiquetas', 'coleta_parametros', 'coleta_registrar',
                             'periodo_padrao', 'periodo_receita', 'chave_norm', 'sck_campanha', 'pessoas_disponivel', 'receita_vendas'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_trafego', 'usage') then raise exception '20261006i: % tem acesso ao schema mkt_trafego', r; end if;
  end loop;
  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261006i: % tem privilégio em mkt_trafego.%', r, t.relname;
      end if;
    end loop;
    if not t.relrowsecurity then raise exception '20261006i: RLS desligada em mkt_trafego.%', t.relname; end if;
  end loop;
  if (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') <> 15 then
    raise exception '20261006i: esperava 15 tabelas em mkt_trafego (10 da 20261006g + 5)';
  end if;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_novas))
               or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname = any (v_internas)) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006i: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006i: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006i: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any (v_tela)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006i: grant de authenticated errado em %', f.sig;
    end if;
    if f.pronamespace = 'mkt_trafego'::regnamespace and has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006i: service_role executa a interna %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261006i: SECURITY DEFINER errado em % (públicas sim, internas não)', f.sig;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.trafego_clickup_receber(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.trafego_clickup_receber(jsonb)', 'execute') then
    raise exception '20261006i: grant de trafego_clickup_receber errado';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') <> 21 then
    raise exception '20261006i: esperava 21 funções public.trafego_* (13 da 20261006g + 8)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'mkt_trafego'::regnamespace and p.proname = any (v_internas)) <> 18 then
    raise exception '20261006i: esperava 18 funções internas novas ou renomeadas';
  end if;
  if to_regclass('mkt_trafego.produtos_hotmart_oferta_exclusiva_unica') is null then
    raise exception '20261006i: falta o índice único da oferta exclusiva (uma oferta, um projeto)';
  end if;
  if (select count(*) from mkt_trafego.alerta_regras) <> 7 or (select count(*) from mkt_trafego.produtos_hotmart) <> 0
     or (select count(*) from mkt_trafego.clickup_tarefas) <> 0
     or (select count(*) from mkt_trafego.status_projeto where not entra_no_resumo_dia) <> 3 then
    raise exception '20261006i: semente diferente do esperado (7 regras, 3 status fora do resumo, vínculos e tarefas vazios)';
  end if;
  -- sem pg_cron (banco local) a checagem da rotina não se aplica
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname in ('trafego-meta', 'trafego-meta-hoje', 'trafego-clickup')) then
      raise exception '20261006i: rotina do Tráfego agendada (deveria nascer desligada)';
    end if;
  end if;
end
$confere$;



-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Ajudantes (temporários, somem no fim da sessão)
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.diz(p_passo text, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_info);
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
grant execute on function pg_temp.ok(text, boolean, text), pg_temp.diz(text, text) to public;
create function pg_temp.proj(p_sigla text) returns bigint language sql stable as $$ select id from mkt.projetos where sigla = p_sigla $$;
create function pg_temp.linha(p_sigla text) returns jsonb language sql stable as $$
  select e from jsonb_array_elements(mkt_trafego.resumo(null)) e where e ->> 'sigla' = p_sigla $$;
-- alertas do projeto (ou sem projeto, p_sigla nulo), como a tela recebe
create function pg_temp.alertas(p_sigla text) returns jsonb language sql as $$
  select coalesce(jsonb_agg(a), '[]'::jsonb) from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') a
   where a ->> 'sigla' is not distinct from p_sigla $$;
create function pg_temp.regras(p_sigla text) returns text language sql as $$
  select coalesce(string_agg(a ->> 'regra' || coalesce(':' || (a -> 'detalhe' ->> 'direcao'), ''), ',' order by a ->> 'regra', a -> 'detalhe' ->> 'direcao'), '')
    from jsonb_array_elements(pg_temp.alertas(p_sigla)) a $$;

-- ─── 0. Dados fictícios: 3 projetos, 1 conta, 6 campanhas, gasto inventado (ontem = O) ────────────────────────────────
--   ZZ28 "Projeto Ensaio Fase 2" (O-9 a O+20, etiqueta zz-ensaio-r), ZY28 "Projeto Ensaio Encerrado" (O-30 a O+5),
--   ZX28 "Projeto Ensaio Sem Datas". Campanhas 9000000001xx na conta act_000555.
do $t$
declare v jsonb; o date := mkt_trafego.ontem();
begin
  insert into mkt.projetos (sigla, nome, linha, etiqueta_clickup, subarea_trafego, inicio, fim) values
    ('ZZ28', 'Projeto Ensaio Fase 2', 'Ensaio', 'zz-ensaio-r', 'interno', o - 9, o + 20),
    ('ZY28', 'Projeto Ensaio Encerrado', 'Ensaio', null, 'interno', o - 30, o + 5),
    ('ZX28', 'Projeto Ensaio Sem Datas', 'Ensaio', null, null, null, null);
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"act_000555","nome":"Conta Ensaio R","dono":"grupo"}')$$);
  v := pg_temp.srv($j$select public.trafego_campanhas_receber('[
    {"plataforma":"meta","conta":"000555","id":"900000000000101","nome":"RS | ZZ28 | LEADS | ENSAIO A","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000102","nome":"RS | ZZ28 | DISTRIBUIÇÃO | ENSAIO B","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000103","nome":"Campanha ensaio fora do padrão sem projeto","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000104","nome":"CF | ZY28 | LEADS | ENSAIO C","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000106","nome":"zz28 ensaio fora do padrão recente","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000107","nome":"zz28 ensaio fora do padrão antiga","status":"PAUSED"}]')$j$);
  perform pg_temp.ok('0.dados', (v ->> 'novas')::int = 6, '6 campanhas fictícias recebidas');
  v := pg_temp.adm(format('select public.trafego_campanha_ajustar(%L::jsonb)', jsonb_build_object('id', (select id from mkt_trafego.campanhas where campanha_externa = '900000000000106'), 'projeto_id', pg_temp.proj('ZZ28'))));
  v := pg_temp.adm(format('select public.trafego_campanha_ajustar(%L::jsonb)', jsonb_build_object('id', (select id from mkt_trafego.campanhas where campanha_externa = '900000000000107'), 'projeto_id', pg_temp.proj('ZZ28'))));
  -- gasto: 101 = 100/dia de O-9 a O-1 e 310 em O; 102 = 20 em O; 103 = 50 em O; 104 = 999 em O; 106 = 30 em O-1; 107 = 50 em O-20
  v := pg_temp.srv(format('select public.trafego_desempenho_receber(%L::jsonb)', (
    select jsonb_agg(jsonb_build_object('plataforma', 'meta', 'campanha', x.c, 'dia', x.d, 'gasto', x.g, 'impressoes', 1000, 'cliques_link', 10))
      from (select '900000000000101' as c, o - k as d, 100 as g from generate_series(1, 9) k
            union all values ('900000000000101', o, 310), ('900000000000102', o, 20), ('900000000000103', o, 50),
                             ('900000000000104', o, 999), ('900000000000106', o - 1, 30), ('900000000000107', o - 20, 50)) x)));
  perform pg_temp.ok('0.dados', (v ->> 'gravadas')::int = 15, '15 dias de gasto fictício gravados');
  v := pg_temp.adm(format('select public.trafego_planejamento_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'),
         'status', 'ativo', 'verba_maxima', 1400, 'verba_diaria', 250, 'meta_leads', 100, 'meta_cpl', 10)));
  v := pg_temp.adm(format('select public.trafego_planejamento_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZY28'),
         'status', 'encerrado', 'verba_maxima', 100, 'verba_diaria', 100, 'meta_cpl', 1)));
  -- fases de ZZ28: captação O-9..O+10 (20 dias, 2000); aquecimento O-5..O+4 (10 dias, 500, sem campanha); lembrete no futuro
  v := pg_temp.adm(format('select public.trafego_fase_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'fase', 'captacao', 'verba', 2000, 'inicio', o - 9, 'fim', o + 10)));
  v := pg_temp.adm(format('select public.trafego_fase_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'fase', 'aquecimento', 'verba', 500, 'inicio', o - 5, 'fim', o + 4)));
  v := pg_temp.adm(format('select public.trafego_fase_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'fase', 'lembrete', 'verba', 300, 'inicio', o + 11, 'fim', o + 15)));
  perform pg_temp.ok('0.dados', (select count(*) from mkt_trafego.projeto_fases where projeto_id = pg_temp.proj('ZZ28')) = 3, 'ZZ28 com 3 fases planejadas');
  -- com a base de pessoas (20261005r_pessoas_e_crm_fundacao): 30 leads fictícios em ZZ28
  if to_regclass('pessoas.eventos') is not null then
    execute $q$
      with p as (insert into pessoas.pessoas (nome) select 'Pessoa Ensaio Fase2 ' || chr(64 + k) || chr(64 + k) from generate_series(1, 30) k returning id)
      insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte) select p.id, 'lead', $1, 'formulario' from p
    $q$ using pg_temp.proj('ZZ28');
    perform pg_temp.ok('0.dados', (pg_temp.linha('ZZ28') ->> 'leads')::int = 30, '30 leads fictícios na base de pessoas para ZZ28');
  end if;
end
$t$;

-- ─── 1. Estrutura e semente ──────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('1.estrutura',
  (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') = 15
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') = 21
  and to_regprocedure('mkt_trafego.resumo_base(bigint)') is not null and to_regprocedure('mkt_trafego.resumo(bigint)') is not null
  and to_regclass('mkt_trafego.produtos_hotmart_oferta_exclusiva_unica') is not null,
  '15 tabelas em mkt_trafego, 21 funções public.trafego_* (com trafego_receita), resumo da 20261006g guardado como resumo_base, '
  || 'índice único da oferta exclusiva');
select pg_temp.ok('1.semente',
  (select string_agg(codigo || '=' || limiar::int || unidade, ',' order by ordem) from mkt_trafego.alerta_regras)
    = 'acima_verba_diaria=0pct,cpl_acima_meta=0pct,leads_abaixo_meta=20pct,ritmo_fase=20pct,verba_perto_fim=90pct,fora_padrao=7dias,sem_fase=7dias'
  and (select string_agg(codigo, ',' order by ordem) from mkt_trafego.status_projeto where not entra_no_resumo_dia) = 'em_planejamento,inativo,encerrado'
  and (select string_agg(chave || '=' || coalesce(valor, 'nulo'), ',' order by chave) from mkt_trafego.coleta_config)
    = 'clickup_team_id=nulo,meta_api_versao=nulo,meta_dias=3',
  '7 regras com os limiares propostos; em planejamento, inativo e encerrado fora do resumo do dia; coleta_config sem workspace do ClickUp');
do $t$
begin
  if to_regclass('cron.job') is null then
    perform pg_temp.diz('1.rotinas', 'PULADO (sem pg_cron neste banco)');
  else
    perform pg_temp.ok('1.rotinas', not exists (select 1 from cron.job where jobname like 'trafego-%'), 'nenhuma rotina trafego-* agendada (nascem desligadas)');
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    perform pg_temp.diz('1.vault', 'PULADO (sem Vault: trafego_coleta_chave não criado, as credenciais voltam nulas)');
    perform pg_temp.ok('1.vault', mkt_trafego.coleta_chave() is null, 'sem Vault: coleta_chave() nulo, sem erro');
  else
    perform pg_temp.ok('1.vault', length(mkt_trafego.coleta_chave()) = 64, 'trafego_coleta_chave criado no Vault (64 caracteres aleatórios)');
  end if;
end
$t$;

-- ─── 2. Resumo do dia ────────────────────────────────────────────────────────────────────────────────────────────────
do $t$
declare a jsonb; v jsonb; o date := mkt_trafego.ontem(); x jsonb; v_base boolean := to_regclass('pessoas.eventos') is not null;
begin
  v := pg_temp.adm('select public.trafego_alertas()');
  perform pg_temp.ok('2.forma', (v ->> 'dia')::date = o and (v ->> 'sem_coleta')::boolean = false
                     and jsonb_array_length(v -> 'regras') = 7 and v ? 'coletas' and (v ->> 'base_pessoas')::boolean = v_base,
                     'dia = ontem, há coleta, 7 regras, base_pessoas=' || (v ->> 'base_pessoas'));
  -- ZZ28 (sem a base de pessoas: sem CPL nem leads)
  perform pg_temp.ok('2.ZZ28 regras', pg_temp.regras('ZZ28') = case when v_base
                       then 'acima_verba_diaria,cpl_acima_meta,fora_padrao,leads_abaixo_meta,ritmo_fase:abaixo,ritmo_fase:acima,sem_fase,verba_perto_fim'
                       else 'acima_verba_diaria,fora_padrao,ritmo_fase:abaixo,ritmo_fase:acima,sem_fase,verba_perto_fim' end,
                     'ZZ28: ' || pg_temp.regras('ZZ28'));
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'acima_verba_diaria';
  perform pg_temp.ok('2.verba diária', (x ->> 'valor')::numeric = 330 and (x ->> 'referencia')::numeric = 250
                     and (x -> 'detalhe' ->> 'pct')::numeric = 132.0 and x ->> 'gravidade' = 'alta',
                     'ontem 330 (310 + 20) contra 250 de diária = 132,0%, gravidade alta');
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e -> 'detalhe' ->> 'direcao' = 'acima';
  perform pg_temp.ok('2.ritmo captação', x -> 'detalhe' ->> 'fase' = 'captacao' and (x ->> 'valor')::numeric = 1210
                     and (x ->> 'referencia')::numeric = 1000.00 and (x -> 'detalhe' ->> 'pct')::numeric = 121.0,
                     'captação: gastou 1210 (900 + 310) contra 1000 esperados (2000 × 10/20 dias) = 121,0% (> 120%)');
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e -> 'detalhe' ->> 'direcao' = 'abaixo';
  perform pg_temp.ok('2.ritmo aquecimento', x -> 'detalhe' ->> 'fase' = 'aquecimento' and (x ->> 'valor')::numeric = 0
                     and (x ->> 'referencia')::numeric = 300.00,
                     'aquecimento sem campanha: 0 contra 300 esperados (500 × 6/10 dias); lembrete (futuro) não avalia');
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'verba_perto_fim';
  perform pg_temp.ok('2.verba', (x ->> 'valor')::numeric = 93.6 and (x ->> 'referencia')::numeric = 90,
                     '% da verba 93,6 (1310 de 1400: 1210 + 20 + 30 + 50 de O-20) contra limiar 90');
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'fora_padrao';
  perform pg_temp.ok('2.fora do padrão', (x ->> 'valor')::int = 1, 'ZZ28: 1 campanha fora do padrão com gasto nos últimos 7 dias (a antiga, de O-20, não conta)');
  select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'sem_fase';
  perform pg_temp.ok('2.sem fase', (x ->> 'valor')::int = 2, 'ZZ28: 2 campanhas sem fase com gasto recente (DISTRIBUIÇÃO e a fora do padrão recente)');
  perform pg_temp.ok('2.sem projeto', exists (select 1 from jsonb_array_elements(pg_temp.alertas(null)) e
                                               where e ->> 'regra' = 'fora_padrao' and (e ->> 'valor')::int >= 1),
                     'campanhas fora do padrão sem projeto também entram (projeto nulo)');
  perform pg_temp.ok('2.encerrado', pg_temp.regras('ZY28') = '', 'ZY28 encerrado: nenhum alerta, mesmo com 999 de gasto contra 100 de diária');
  perform pg_temp.ok('2.ordem', (select e ->> 'gravidade' from jsonb_array_elements(pg_temp.adm('select public.trafego_alertas()') -> 'alertas') e limit 1) = 'alta',
                     'alertas de gravidade alta primeiro');
  if v_base then
    select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'leads_abaixo_meta';
    perform pg_temp.ok('2.leads', (x ->> 'valor')::int = 30 and (x ->> 'referencia')::numeric = 50 and x -> 'detalhe' ->> 'periodo' = 'captacao'
                       and (x -> 'detalhe' ->> 'pct')::numeric = 60.0,
                       '30 leads contra 50 esperados (meta 100 × 10/20 dias da captação) = 60,0% (< 80%)');
    select e into x from jsonb_array_elements(pg_temp.alertas('ZZ28')) e where e ->> 'regra' = 'cpl_acima_meta';
    perform pg_temp.ok('2.cpl', (x ->> 'valor')::numeric = 43.67 and (x ->> 'referencia')::numeric = 10,
                       'CPL 43,67 (1310 ÷ 30) contra meta 10');
  else
    perform pg_temp.diz('2.leads', 'PULADO (20261005r_pessoas_e_crm_fundacao não aplicada: sem leads da base, CPL e meta de leads não avaliam)');
  end if;

  -- limiares mudam o resultado (configuração, não código)
  update mkt_trafego.alerta_regras set limiar = 50 where codigo = 'ritmo_fase';
  update mkt_trafego.alerta_regras set ligada = false where codigo = 'sem_fase';
  update mkt_trafego.alerta_regras set limiar = 40 where codigo = 'acima_verba_diaria';
  perform pg_temp.ok('2.limiares', pg_temp.regras('ZZ28') not like '%ritmo_fase:acima%' and pg_temp.regras('ZZ28') like '%ritmo_fase:abaixo%'
                     and pg_temp.regras('ZZ28') not like '%sem_fase%' and pg_temp.regras('ZZ28') not like '%acima_verba_diaria%',
                     'ritmo 50%: só o aquecimento (0%) fica; sem_fase desligada some; diária +40% (350) não dispara com 330');
  update mkt_trafego.alerta_regras set limiar = 20 where codigo = 'ritmo_fase';
  update mkt_trafego.alerta_regras set ligada = true where codigo = 'sem_fase';
  update mkt_trafego.alerta_regras set limiar = 0 where codigo = 'acima_verba_diaria';
  -- status que entra ou não
  update mkt_trafego.status_projeto set entra_no_resumo_dia = true where codigo = 'encerrado';
  perform pg_temp.ok('2.status', pg_temp.regras('ZY28') like '%acima_verba_diaria%', 'encerrado volta a entrar se a configuração mandar');
  -- sem nenhum lead na base: leads "sem dado" (nulo) e nem "abaixo da meta de leads" nem "CPL acima" disparam (auditoria 06/10)
  update mkt_trafego.planejamento set meta_leads = 100 where projeto_id = pg_temp.proj('ZY28');
  if v_base then
    perform pg_temp.ok('2.sem lead', pg_temp.linha('ZY28') -> 'leads' = 'null'::jsonb and pg_temp.linha('ZY28') -> 'cpl' = 'null'::jsonb
                       and pg_temp.regras('ZY28') not like '%leads_abaixo_meta%' and pg_temp.regras('ZY28') not like '%cpl_acima_meta%',
                       'ZY28 com meta de 100 leads e meta de CPL, gastando, mas sem nenhum lead na base: leads e CPL "sem dado", nenhum alerta de leads nem de CPL');
  else
    perform pg_temp.ok('2.sem lead', pg_temp.regras('ZY28') not like '%leads_abaixo_meta%', 'sem a base: leads nulos, sem alerta de leads');
  end if;
  update mkt_trafego.planejamento set meta_leads = null where projeto_id = pg_temp.proj('ZY28');
  update mkt_trafego.status_projeto set entra_no_resumo_dia = false where codigo = 'encerrado';
end
$t$;

-- ─── 3. Receita (Hotmart → projeto, fonte fin.hotmart_transacoes) ───────────────────────────────────────────────────
do $t$
declare v jsonb; r jsonb; o date := mkt_trafego.ontem(); v_id bigint; v_gatilho boolean;
  v_conta text; v_prod text; v_esperado numeric; v_esperado_liq numeric;
  v_soma numeric; v_soma_liq numeric;
begin
  -- sem vínculo = sem dado
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3.sem vínculo', r ? 'receita' and r -> 'receita' = 'null'::jsonb and r -> 'receita_liquida' = 'null'::jsonb
                     and (r ->> 'receita_vinculos')::int = 0,
                     'sem vínculo cadastrado: receita e líquido nulos ("sem dado"), 0 vínculos');
  if not mkt_trafego.hotmart_disponivel() then
    v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990001')));
    r := pg_temp.linha('ZZ28');
    perform pg_temp.ok('3.sem fonte', (v ->> 'ok')::boolean and r -> 'receita' = 'null'::jsonb and (r ->> 'receita_vinculos')::int = 1
                       and (r ->> 'receita_fonte')::boolean = false and pg_temp.adm('select public.trafego_hotmart_produtos()') = '[]'::jsonb,
                       'sem fin.hotmart_transacoes: vínculo salvo, receita nula com receita_fonte=false, lista de produtos vazia');
    perform pg_temp.diz('3.receita', 'PULADO (fin.hotmart_transacoes, o espelho do financeiro, não existe neste banco)');
    return;
  end if;

  -- recusas (não dependem de transação)
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'produto_id', '9990001')));
  perform pg_temp.ok('3.sem conta', not (v ->> 'ok')::boolean, 'vínculo sem conta da Hotmart recusado: ' || (v ->> 'msg'));
  if to_regclass('fin.hotmart_contas') is not null then
    v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'conta_ensaio_zz', 'produto_id', '9990001')));
    perform pg_temp.ok('3.conta', not (v ->> 'ok')::boolean, 'conta fora de fin.hotmart_contas recusada: ' || (v ->> 'msg'));
  end if;
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '99 01')));
  perform pg_temp.ok('3.id', not (v ->> 'ok')::boolean, 'id de produto fora do formato recusado');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990004', 'de', o, 'ate', o - 1)));
  perform pg_temp.ok('3.datas', not (v ->> 'ok')::boolean, 'fim antes do início recusado');
  v := pg_temp.adm($$select public.trafego_produto_salvar('{"projeto_id": -1, "conta": "academy", "produto_id": "1"}')$$);
  perform pg_temp.ok('3.projeto', not (v ->> 'ok')::boolean, 'projeto inexistente recusado');

  -- conferência com o FINANCEIRO (banco real): a receita bruta de um produto real da conta academy é a mesma soma do
  -- valor_oferta das vendas 'pago' de fin.vw_transacoes (a view do financeiro, só academy) no mesmo período, em BRL.
  -- Só leitura das transações reais; o vínculo é com um projeto fictício (ZW28) e some no rollback.
  if to_regclass('fin.vw_transacoes') is null then
    perform pg_temp.diz('3.financeiro', 'PULADO (sem fin.vw_transacoes neste banco: a conferência com a view do financeiro só roda no Supabase)');
  else
    execute $q$select t.conta, t.produto_id from fin.hotmart_transacoes t
                where t.conta = 'academy' and t.status in ('APPROVED', 'COMPLETE') and t.aprovado_em >= now() - interval '60 days'
                group by 1, 2 order by count(*) desc, 2 limit 1$q$ into v_conta, v_prod;
    if v_prod is null then
      perform pg_temp.diz('3.financeiro', 'PULADO (nenhuma venda paga da conta academy nos últimos 60 dias)');
    else
      insert into mkt.projetos (sigla, nome, linha, subarea_trafego, inicio, fim) values ('ZW28', 'Projeto Ensaio Real', 'Ensaio', 'interno', o - 59, o);
      v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZW28'), 'conta', v_conta, 'produto_id', v_prod)));
      execute $q$select coalesce(sum(w.valor_oferta), 0), coalesce(sum(w.liquido), 0)
                   from fin.vw_transacoes w join fin.hotmart_transacoes t on t.transacao = w.transacao
                  where w.grupo = 'pago' and w.produto_id = $1 and w.conta = $2 and coalesce(t.moeda, 'BRL') = 'BRL'
                    and w.dia_aprovado between $3 - 59 and $3$q$ into v_esperado, v_esperado_liq using v_prod, v_conta, o;
      r := pg_temp.linha('ZW28');
      -- desde a decisão de 06/10/2026 (receita por nível) o vínculo sem oferta exclusiva dá ESTIMADA; vendas do mesmo
      -- produto com SCK de um projeto real (nível 2) ficam com ele. Estimada de ZW28 + essas = a soma do financeiro.
      select coalesce(sum(m.bruto) filter (where m.projeto_id = pg_temp.proj('ZW28') and m.nivel = 4), 0)
               + coalesce(sum(m.bruto) filter (where m.projeto_id <> pg_temp.proj('ZW28')), 0),
             coalesce(sum(m.liquido) filter (where m.projeto_id = pg_temp.proj('ZW28') and m.nivel = 4), 0)
               + coalesce(sum(m.liquido) filter (where m.projeto_id <> pg_temp.proj('ZW28')), 0)
        into v_soma, v_soma_liq
        from mkt_trafego.receita_vendas(null) m
       where m.produto_id = v_prod and m.conta = v_conta and m.moeda = 'BRL' and not m.disputa
         and (m.aprovado_em at time zone 'America/Sao_Paulo')::date between o - 59 and o;
      perform pg_temp.ok('3.financeiro', (v ->> 'ok')::boolean and round(v_soma, 2) = round(v_esperado, 2)
                         and round(v_soma_liq, 2) = round(v_esperado_liq, 2)
                         and (r ->> 'receita_estimada')::numeric <= round(v_esperado, 2),
                         'produto real de maior venda da academy nos últimos 60 dias: estimada de ZW28 + as vendas que o SCK dá a um projeto '
                         || 'real = bruto e líquido de fin.vw_transacoes (valor_oferta e liquido, grupo pago) no período');
    end if;
  end if;

  -- transações fictícias: só onde a tabela não tem gatilho (em produção, fin.hotmart_transacoes dispara o CRM do Arthur
  -- a cada insert: zz_crm_hotmart_sync_ins; não inserimos lá nem dentro do rollback).
  select exists (select 1 from pg_trigger g where g.tgrelid = 'fin.hotmart_transacoes'::regclass and not g.tgisinternal) into v_gatilho;
  if v_gatilho then
    perform pg_temp.diz('3.receita', 'PULADO (fin.hotmart_transacoes tem gatilho neste banco: as transações fictícias rodam só no banco local)');
    return;
  end if;
  begin
    execute $q$
      insert into fin.hotmart_transacoes (transacao, conta, produto_id, produto_nome, oferta_codigo, status, moeda, valor_base,
                                          valor_cobrado, taxa_hotmart, liquido_produtor, pedido_em, aprovado_em, bruto_json)
      select 'HPENSAIO' || x.n, x.conta, x.prod, x.nome, x.oferta, x.status, x.moeda, x.base, x.cobrado, x.taxa, x.liq,
             (($1 - x.k) + time '11:00') at time zone 'America/Sao_Paulo',
             case when x.aprovada then (($1 - x.k) + time '12:00') at time zone 'America/Sao_Paulo' end,
             x.bruto::jsonb
        from (values
          (1, 'academy', '9990001', 'Produto Ensaio A', 'OFX', 'APPROVED', 'BRL', 100, 110, 5, 90, 5, true, '{}'),
          (2, 'academy', '9990001', 'Produto Ensaio A novo nome', null, 'COMPLETE', 'BRL', 200, 200, 9, null, 0, true, '{}'),
          (3, 'academy', '9990001', 'Produto Ensaio A', null, 'REFUNDED', 'BRL', 300, 300, 13, 287, 3, true, '{}'),
          (4, 'academy', '9990001', 'Produto Ensaio A', null, 'APPROVED', 'BRL', 400, 400, 17, 383, 30, true, '{}'),
          (5, 'academy', '9990001', 'Produto Ensaio A', null, 'APPROVED', 'USD', 50, 50, 3, 47, 2, true, '{}'),
          (6, 'academy', '9990002', 'Produto Ensaio B', null, 'APPROVED', 'BRL', 500, 500, 21, 479, 2, true, '{}'),
          (7, 'academy', '9990001', 'Produto Ensaio A', null, 'COMPLETE', 'BRL', 25, 25, 2, 23, 1, false, '{}'),
          (8, 'academy', '9990003', 'Produto Ensaio C', 'OFZ1', 'APPROVED', 'BRL', 70, 70, 4, 66, 0, true, '{}'),
          (9, 'academy', '9990003', 'Produto Ensaio C', 'OFZ2', 'APPROVED', 'BRL', 80, 80, 4, 76, 0, true, '{}'),
          (10, 'academy', '9990003', 'Produto Ensaio C', 'OFZ1', 'APPROVED', 'BRL', 90, 90, 5, 85, 4, true, '{}'),
          (11, 'escritorio', '9990001', 'Produto Ensaio A do escritório', null, 'APPROVED', 'BRL', 1000, 1000, 41, 959, 1, true, '{}'),
          (12, 'academy', '9990001', 'Produto Ensaio A', null, 'APPROVED', 'BRL', null, 66, 3, 55, 1, true,
               '{"purchase": {"hotmart_fee": {"base": 60}}}')
        ) x(n, conta, prod, nome, oferta, status, moeda, base, cobrado, taxa, liq, k, aprovada, bruto)
    $q$ using o;
  exception when not_null_violation or foreign_key_violation or check_violation or unique_violation then
    perform pg_temp.diz('3.receita', 'PULADO (fin.hotmart_transacoes recusou a transação fictícia: ' || sqlstate || ')');
    return;
  end;

  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990001')));
  perform pg_temp.ok('3.vínculo', (v ->> 'ok')::boolean and v -> 'avisos' = '["sem_oferta_exclusiva"]'::jsonb,
                     'ZZ28 ← academy/9990001 (todas as ofertas, período do projeto), só o aviso sem_oferta_exclusiva');
  r := pg_temp.linha('ZZ28');
  -- produto + período = nível 4 (ESTIMADA, à parte): a receita do projeto (níveis 1 a 3) fica 0, não nula (tem vínculo)
  perform pg_temp.ok('3.estimada', (r ->> 'receita_estimada')::numeric = 360 and (r ->> 'receita_compras_estimada')::int = 4
                     and (r ->> 'receita')::numeric = 0 and (r ->> 'receita_compras')::int = 0 and (r ->> 'receita_fonte')::boolean,
                     'só produto + período: estimada 360,00 = 100 (APPROVED, valor da oferta e não os 110 cobrados) + 200 (COMPLETE) + '
                     || '60 (sem valor_base: hotmart_fee.base do bruto_json); REFUNDED, a de antes do início, a sem aprovado_em e a do '
                     || 'escritório fora; a de USD contada mas fora da soma (4 vendas); a receita do projeto (níveis 1 a 3) fica 0,00');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'escritorio', 'produto_id', '9990001')));
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3.conta', (v ->> 'ok')::boolean and (r ->> 'receita_estimada')::numeric = 1360,
                     'mesmo id de produto na conta escritorio é outro vínculo: + 1000 = 1360,00 estimada (a conta separa)');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990003', 'oferta_codigo', 'OFZ1', 'de', o - 1)));
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990001', 'oferta_codigo', 'OFX')));
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3.oferta e período', (r ->> 'receita_estimada')::numeric = 1430 and (r ->> 'receita_vinculos')::int = 4,
                     'bruto 1430,00: + 70 da oferta OFZ1 a partir de O-1 (a OFZ2 e a OFZ1 de O-4 fora); o vínculo 9990001/OFX não conta a mesma venda duas vezes');
  r := pg_temp.adm(format('select public.trafego_projeto(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('3.vida do projeto', (r -> 'resumo' ->> 'receita_estimada')::numeric = 1430, 'a vida do projeto mostra a mesma estimada');
  -- avisos
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZY28'), 'conta', 'academy', 'produto_id', '9990001')));
  perform pg_temp.ok('3.outro projeto', (v ->> 'ok')::boolean and v -> 'avisos' ? 'produto_em_outro_projeto',
                     'mesma conta e produto em ZY28 com período que se cruza: salva, com aviso');
  r := pg_temp.linha('ZY28');
  perform pg_temp.ok('3.ZY28', (r ->> 'receita_estimada')::numeric = 400 and (r ->> 'receita_disputa')::int = 4,
                     'ZY28 (O-30 a O+5): as 4 vendas que também casam com ZZ28 no mesmo nível (estimada) ficam em DISPUTA e não somam '
                     || 'em nenhum; sobra a de O-30 = 400,00');
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3.disputa', (r ->> 'receita_estimada')::numeric = 1070 and (r ->> 'receita_disputa')::int = 4,
                     'ZZ28 perde as mesmas 4 para a disputa: 1430 − 360 = 1070,00 estimada (escritório 1000 + OFZ1 70)');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZY28'), 'conta', 'escritorio', 'produto_id', '9990002')));
  perform pg_temp.ok('3.sem compras na conta', (v ->> 'ok')::boolean and v -> 'avisos' ? 'produto_sem_compras',
                     '9990002 só vendeu na academy: ligado pelo escritório, salva com aviso produto_sem_compras');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZX28'), 'conta', 'academy', 'produto_id', '9990009')));
  r := pg_temp.linha('ZX28');
  perform pg_temp.ok('3.sem período', (v ->> 'ok')::boolean and v -> 'avisos' ? 'sem_periodo' and v -> 'avisos' ? 'produto_sem_compras'
                     and r -> 'receita' = 'null'::jsonb and (r ->> 'receita_sem_periodo')::int = 1,
                     'projeto sem datas e produto sem vendas: salva com 2 avisos; receita nula (sem período)');
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZZ28'), 'conta', 'academy', 'produto_id', '9990001')));
  perform pg_temp.ok('3.duplicado', not (v ->> 'ok')::boolean, 'mesma conta, produto e oferta no mesmo projeto: ' || (v ->> 'msg'));
  v := pg_temp.adm(format('select public.trafego_produtos_listar(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('3.listar', jsonb_array_length(v) = 4 and (v -> 0 ->> 'de_efetivo')::date = o - 9
                     and exists (select 1 from jsonb_array_elements(v) e where e ->> 'conta' = 'academy' and e ->> 'produto_id' = '9990001'
                                   and e ->> 'produto_nome' = 'Produto Ensaio A novo nome'),
                     'ZZ28: 4 vínculos com a conta; "de" vazio mostra o início do projeto; nome do produto = o mais recente da Hotmart');
  v := pg_temp.adm('select public.trafego_hotmart_produtos()');
  perform pg_temp.ok('3.produtos vistos', exists (select 1 from jsonb_array_elements(v) e where e ->> 'conta' = 'academy' and e ->> 'produto_id' = '9990001'
                       and (e ->> 'aprovadas')::int = 6 and e ->> 'nome' = 'Produto Ensaio A novo nome' and not e ? 'email'
                       and e -> 'ofertas' @> '[{"codigo": "OFX"}]'::jsonb)
                     and exists (select 1 from jsonb_array_elements(v) e where e ->> 'conta' = 'escritorio' and e ->> 'produto_id' = '9990001'
                       and (e ->> 'aprovadas')::int = 1 and e ->> 'nome' = 'Produto Ensaio A do escritório'),
                     'seletor por conta: academy/9990001 com 6 pagas (APPROVED/COMPLETE), o nome mais recente e a oferta OFX; '
                     || 'escritorio/9990001 à parte; sem dado de comprador');
  select id into v_id from mkt_trafego.produtos_hotmart where produto_id = '9990003';
  v := pg_temp.adm(format('select public.trafego_produto_apagar(%s)', v_id));
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3.apagar', (v ->> 'ok')::boolean and (r ->> 'receita_estimada')::numeric = 1000, 'apagar o vínculo 9990003: estimada volta a 1000,00');
end
$t$;

-- ─── 3b. Receita por nível de certeza (decisão do Victor, 06/10/2026): oferta exclusiva, SCK, lead do projeto, disputa ─
-- Continua do passo 3 (só no banco local, com as transações fictícias). Estado de partida: ZZ28 com academy/9990001
-- (todas), escritorio/9990001 e academy/9990001/OFX; ZY28 com academy/9990001 e escritorio/9990002. Transações novas
-- HPENSAIO13…20 (fictícias) e, com a base de pessoas, 4 pessoas "Comprador Ensaio Nivel3 …" e 1 comprador fictício.
do $t$
declare v jsonb; r jsonb; o date := mkt_trafego.ontem(); v_id bigint; v_p uuid; v_falhou boolean;
begin
  if not mkt_trafego.hotmart_disponivel() then
    perform pg_temp.diz('3b.níveis', 'PULADO (fin.hotmart_transacoes, o espelho do financeiro, não existe neste banco)');
    return;
  end if;
  if not exists (select 1 from fin.hotmart_transacoes where transacao = 'HPENSAIO1') then
    perform pg_temp.diz('3b.níveis', 'PULADO (sem as transações fictícias do passo 3: só no banco local)');
    return;
  end if;
  perform pg_temp.ok('3b.sck formato', mkt_trafego.sck_campanha('sendflow|grupo|Seminário-Conjunto-2026-11||') = 'seminario-conjunto-2026-11'
                     and mkt_trafego.sck_campanha(' a | b | PB26 |c|d') = 'pb26' and mkt_trafego.sck_campanha('pb26') is null
                     and mkt_trafego.sck_campanha('a|b') is null,
                     'leitura do SCK num lugar só: 3º campo (campanha), sem maiúscula, acento nem espaço; sem "|" ou sem 3º campo = nada');

  -- recusas da oferta exclusiva
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZY28'),
         'conta', 'academy', 'produto_id', '9990002', 'oferta_exclusiva', true)));
  perform pg_temp.ok('3b.exclusiva sem oferta', not (v ->> 'ok')::boolean, 'oferta exclusiva sem oferta recusada: ' || (v ->> 'msg'));
  perform pg_temp.ok('3b.check', (select count(*) from mkt_trafego.produtos_hotmart where oferta_exclusiva) = 0, 'nada gravado');

  -- nível 1: o vínculo OFX de ZZ28 vira oferta exclusiva
  select id into v_id from mkt_trafego.produtos_hotmart where projeto_id = pg_temp.proj('ZZ28') and oferta_codigo = 'OFX';
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('id', v_id, 'projeto_id', pg_temp.proj('ZZ28'),
         'conta', 'academy', 'produto_id', '9990001', 'oferta_codigo', 'OFX', 'oferta_exclusiva', true)));
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3b.nível 1', (v ->> 'ok')::boolean and not (v -> 'avisos' ? 'sem_oferta_exclusiva')
                     and (r ->> 'receita_oferta')::numeric = 100 and (r ->> 'receita')::numeric = 100
                     and (r ->> 'receita_liquida')::numeric = 90 and (r ->> 'receita_compras_oferta')::int = 1
                     and (r ->> 'receita_estimada')::numeric = 1000 and (r ->> 'receita_disputa')::int = 3
                     and (r ->> 'receita_ofertas_exclusivas')::int = 1,
                     'OFX exclusiva de ZZ28: a venda de 100,00 (que estava em disputa no nível estimado com ZY28) é CERTA de ZZ28 '
                     || '(nível 1 vence o 4): receita 100,00, líquido 90,00; estimada 1000,00; 3 em disputa');
  r := pg_temp.linha('ZY28');
  perform pg_temp.ok('3b.perde para o nível 1', (r ->> 'receita_estimada')::numeric = 400 and (r ->> 'receita_disputa')::int = 3
                     and (r ->> 'receita')::numeric = 0,
                     'ZY28 não conta a venda da OFX (outro projeto tem nível mais forte): estimada 400,00, 3 em disputa, receita 0,00');

  -- uma oferta, um projeto: pela tela (mensagem com a sigla) e direto na tabela (o banco recusa)
  v := pg_temp.adm(format('select public.trafego_produto_salvar(%L::jsonb)', jsonb_build_object('projeto_id', pg_temp.proj('ZY28'),
         'conta', 'academy', 'produto_id', '9990001', 'oferta_codigo', 'OFX', 'oferta_exclusiva', true)));
  perform pg_temp.ok('3b.uma oferta, um projeto', not (v ->> 'ok')::boolean and v ->> 'msg' like '%ZZ28%',
                     'a mesma oferta exclusiva em ZY28 recusada: ' || (v ->> 'msg'));
  begin
    insert into mkt_trafego.produtos_hotmart (projeto_id, conta, produto_id, oferta_codigo, oferta_exclusiva)
    values (pg_temp.proj('ZY28'), 'academy', '9990001', 'OFX', true);
    v_falhou := false;
  exception when unique_violation then v_falhou := true;
  end;
  perform pg_temp.ok('3b.índice', v_falhou, 'insert direto da segunda oferta exclusiva recusado pelo banco (índice único)');
  v := pg_temp.adm(format('select public.trafego_hotmart_produtos()'));
  perform pg_temp.ok('3b.seletor', exists (select 1 from jsonb_array_elements(v) e, jsonb_array_elements(e -> 'ofertas') x
                                            where e ->> 'produto_id' = '9990001' and e ->> 'conta' = 'academy'
                                              and x ->> 'codigo' = 'OFX' and x ->> 'exclusiva_de' = 'ZZ28'),
                     'o seletor de ofertas mostra que a OFX já é exclusiva de ZZ28');
  v := pg_temp.adm(format('select public.trafego_produtos_listar(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('3b.listar', exists (select 1 from jsonb_array_elements(v) e where e ->> 'oferta_codigo' = 'OFX' and (e ->> 'oferta_exclusiva')::boolean),
                     'a lista de vínculos traz a marca oferta_exclusiva');

  -- transações novas: 13 = OFX fora do período padrão (O-60); 14 e 15 = SCK com o projeto; 16 = sigla fora do campo campanha
  insert into fin.hotmart_transacoes (transacao, conta, produto_id, produto_nome, oferta_codigo, status, moeda, valor_base, valor_cobrado,
                                      taxa_hotmart, liquido_produtor, pedido_em, aprovado_em, origem_sck, bruto_json)
  select 'HPENSAIO' || x.n, 'academy', x.prod, 'Produto Ensaio', x.oferta, 'APPROVED', 'BRL', x.base, x.base, 0, x.base,
         (o - x.k) + time '11:00', ((o - x.k) + time '12:00') at time zone 'America/Sao_Paulo', x.sck, '{}'::jsonb
    from (values (13, '9990001', 'OFX', 300, 60, null),
                 (14, '9990002', null, 250, 3, 'sendflow|grupo|ZZ-ENSÁIO-R||'),
                 (15, '9990001', null, 120, 2, 'youtube|live|zz28||cpl-1'),
                 (16, '9990002', null, 999, 2, 'zz28|grupo|outra||')) x(n, prod, oferta, base, k, sck);
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3b.nível 1 sem período', (r ->> 'receita_oferta')::numeric = 400,
                     'venda da oferta exclusiva antes do período padrão (O-60) conta: oferta exclusiva vale em qualquer data');
  perform pg_temp.ok('3b.nível 2', (r ->> 'receita_sck')::numeric = 370 and (r ->> 'receita_compras_sck')::int = 2
                     and (r ->> 'receita')::numeric = 770 and (r ->> 'receita_estimada')::numeric = 1000,
                     'SCK com a chave (ZZ-ENSÁIO-R, maiúscula e acento) em produto NÃO ligado (250) e com a sigla (zz28) em produto que '
                     || 'ZY28 estimava (120; nível 2 vence o 4): SCK 370,00; receita = 400 + 370 = 770,00; a sigla fora do campo '
                     || 'campanha não conta');
  perform pg_temp.ok('3b.ninguém', not exists (select 1 from mkt_trafego.receita_vendas(null) m where m.transacao = 'HPENSAIO16'),
                     'zz28 no 1º campo do SCK (não é o campo campanha) e produto sem vínculo naquela conta: a venda não é de ninguém');
  r := pg_temp.linha('ZY28');
  perform pg_temp.ok('3b.ZY28 sem a do SCK', (r ->> 'receita_estimada')::numeric = 400, 'ZY28 não estima a venda que tem SCK de ZZ28');

  -- disputa no nível 2: ZV28 com a etiqueta "zz28" (igual à sigla de ZZ28)
  insert into mkt.projetos (sigla, nome, linha, etiqueta_clickup, subarea_trafego, inicio, fim) values ('ZV28', 'Projeto Ensaio Disputa', 'Ensaio', 'zz28', 'interno', o - 9, o);
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3b.disputa nível 2', (r ->> 'receita_sck')::numeric = 250 and (r ->> 'receita')::numeric = 650
                     and (r ->> 'receita_disputa')::int = 4 and (pg_temp.linha('ZV28') ->> 'receita')::numeric = 0
                     and (pg_temp.linha('ZV28') ->> 'receita_disputa')::int = 1,
                     'o SCK "zz28" casa com ZZ28 (sigla) e ZV28 (etiqueta) no mesmo nível: a venda de 120 não soma em nenhum '
                     || '(ZZ28 650,00; ZV28 0,00 com 1 em disputa)');
  v := pg_temp.adm(format('select public.trafego_receita(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('3b.vendas em disputa', (v ->> 'disputas_total')::int = 4
                     and exists (select 1 from jsonb_array_elements(v -> 'disputas') d where d ->> 'transacao' = 'HPENSAIO15'
                                   and (d ->> 'nivel')::int = 2 and d -> 'projetos' = '["ZV28", "ZZ28"]'::jsonb)
                     and exists (select 1 from jsonb_array_elements(v -> 'disputas') d where d ->> 'transacao' = 'HPENSAIO2'
                                   and (d ->> 'nivel')::int = 4 and d -> 'projetos' = '["ZY28", "ZZ28"]'::jsonb)
                     and not (v -> 'disputas' -> 0 ? 'email') and not (v ->> 'sem_oferta_exclusiva')::boolean
                     and v -> 'sck_chaves' = '["zz-ensaio-r", "zz28"]'::jsonb and (v -> 'receita' ->> 'receita')::numeric = 650,
                     'vida do projeto: 4 vendas em disputa (a do SCK com ZV28 no nível 2, as estimadas com ZY28 no nível 4), sem dado '
                     || 'do comprador; com oferta exclusiva, sem o aviso; as chaves aceitas no SCK');
  v := pg_temp.adm(format('select public.trafego_receita(%s)', pg_temp.proj('ZY28')));
  perform pg_temp.ok('3b.aviso sem oferta exclusiva', (v ->> 'sem_oferta_exclusiva')::boolean and (v ->> 'ofertas_exclusivas')::int = 0,
                     'ZY28 tem produto ligado e nenhuma oferta exclusiva: aviso "sem oferta exclusiva, a receita é só estimada"');
  update mkt.projetos set etiqueta_clickup = null where sigla = 'ZV28';
  perform pg_temp.ok('3b.fim da disputa', (pg_temp.linha('ZZ28') ->> 'receita')::numeric = 770, 'sem a etiqueta repetida, ZZ28 volta a 770,00');

  -- nível 3: comprador que foi lead do projeto ANTES da compra (base de pessoas do Arthur, só leitura nas funções)
  if not mkt_trafego.pessoas_disponivel() then
    perform pg_temp.diz('3b.nível 3', 'PULADO (sem a base de pessoas 20261005r ou sem as colunas do comprador em fin.hotmart_transacoes)');
    return;
  end if;
  -- pessoa A: e-mail nos identificadores, lead de ZY28 em O-20, compra em O-10 (fora do período de ZZ28)
  insert into pessoas.pessoas (nome) values ('Comprador Ensaio Nivel3 A') returning id into v_p;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values (v_p, 'email', 'comprador.ensaio3@exemplo.invalid', 'comprador.ensaio3@exemplo.invalid', 'formulario');
  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, quando) values (v_p, 'lead', pg_temp.proj('ZY28'), 'formulario', (o - 20) + time '10:00');
  -- pessoa B: telefone, lead de ZY28 DEPOIS da compra (O vs O-12): não vale
  insert into pessoas.pessoas (nome) values ('Comprador Ensaio Nivel3 B') returning id into v_p;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values (v_p, 'telefone', '11988887777', pessoas.chave_telefone('11988887777'), 'formulario');
  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, quando) values (v_p, 'lead', pg_temp.proj('ZY28'), 'formulario', o + time '10:00');
  -- pessoa C: comprador ligado (documento com máscara), lead de ZY28 em O-25, compra em O-8 (dentro dos DOIS períodos)
  insert into public.compradores (nome, email, documento) values ('Comprador Ensaio Nivel3 C', 'comprador.c@exemplo.invalid', '123.456.789-01');
  insert into pessoas.pessoas (comprador_id) select id from public.compradores where email = 'comprador.c@exemplo.invalid' returning id into v_p;
  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, quando) values (v_p, 'lead', pg_temp.proj('ZY28'), 'formulario', (o - 25) + time '10:00');
  -- pessoa D: telefone nos identificadores, lead de ZY28 em O-15, compra em O-6 com o telefone noutro formato
  insert into pessoas.pessoas (nome) values ('Comprador Ensaio Nivel3 D') returning id into v_p;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values (v_p, 'telefone', '21997776655', pessoas.chave_telefone('21997776655'), 'formulario');
  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, quando) values (v_p, 'lead', pg_temp.proj('ZY28'), 'formulario', (o - 15) + time '10:00');
  insert into fin.hotmart_transacoes (transacao, conta, produto_id, produto_nome, status, moeda, valor_base, valor_cobrado, taxa_hotmart,
                                      liquido_produtor, pedido_em, aprovado_em, comprador_email, comprador_telefone, comprador_documento, bruto_json)
  select 'HPENSAIO' || x.n, 'academy', '9990001', 'Produto Ensaio', 'APPROVED', 'BRL', x.base, x.base, 0, x.base,
         (o - x.k) + time '11:00', ((o - x.k) + time '12:00') at time zone 'America/Sao_Paulo', x.em, x.tel, x.doc, '{}'::jsonb
    from (values (17, 330, 10, ' Comprador.Ensaio3@Exemplo.invalid ', null, null),
                 (18, 440, 12, null, '5511988887777', null),
                 (19, 210, 8, null, null, '12345678901'),
                 (20, 150, 6, null, '+55 (21) 99777-6655', null)) x(n, base, k, em, tel, doc);
  r := pg_temp.linha('ZY28');
  perform pg_temp.ok('3b.nível 3', (r ->> 'receita_lead')::numeric = 690 and (r ->> 'receita_compras_lead')::int = 3
                     and (r ->> 'receita')::numeric = 690 and (r ->> 'receita_estimada')::numeric = 840
                     and (r ->> 'receita_base_pessoas')::boolean,
                     'ZY28: lead antes da compra pelo e-mail (330, maiúscula e espaço), pelo documento do comprador ligado (210) e pelo '
                     || 'telefone noutro formato (150) = nível 3, 690,00; o lead DEPOIS da compra (440, telefone) fica só estimada: '
                     || '400 + 440 = 840,00');
  r := pg_temp.linha('ZZ28');
  perform pg_temp.ok('3b.nível 3 vence o 4', (r ->> 'receita_estimada')::numeric = 1000 and (r ->> 'receita')::numeric = 770,
                     'as compras de 210 (O-8) e 150 (O-6) também caem no período de ZZ28, mas lá são só estimadas: ficam com ZY28 '
                     || '(nível 3), ZZ28 não muda');
end
$t$;

-- ─── 4. ClickUp: espelho pela etiqueta ───────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb; r jsonb;
begin
  v := pg_temp.srv($j$select public.trafego_clickup_receber('{"etiqueta": "zz-ensaio-r", "tarefas": [
    {"id": "86ensaio1", "nome": "Subir campanhas (ENSAIO)", "status": "complete", "criada_em": "2026-09-27T19:06:40Z", "concluida_em": "2026-10-02T10:13:20Z",
     "prazo": "2026-10-02T09:00:00Z", "responsaveis": ["Responsável Ensaio"], "etiquetas": ["zz-ensaio-r"], "url": "https://app.clickup.com/t/86ensaio1"},
    {"id": "86ensaio2", "nome": "Trocar criativo (ENSAIO)", "status": "em andamento", "inicio": "2026-10-01T06:26:40Z", "prazo": "2099-10-08T05:06:40Z",
     "responsaveis": [], "etiquetas": ["zz-ensaio-r", "outra-etq"], "url": "https://app.clickup.com/t/86ensaio2"},
    {"id": "86ensaio3", "nome": "Revisar verba (ENSAIO)", "status": "to do", "criada_em": "2026-09-30T02:40:00Z", "responsaveis": ["Outro Ensaio"],
     "etiquetas": [], "url": "https://exemplo.invalid/fora"},
    {"id": "a b", "nome": "id ruim"},
    {"id": "86ensaio9", "nome": "data ruim", "prazo": "amanhã"}]}')$j$);
  perform pg_temp.ok('4.receber', (v ->> 'gravadas')::int = 3 and jsonb_array_length(v -> 'recusas') = 2,
                     '3 gravadas; id fora do formato e data inválida recusados: ' || (v -> 'recusas')::text);
  perform pg_temp.ok('4.etiqueta', (select etiquetas from mkt_trafego.clickup_tarefas where tarefa_id = '86ensaio3') = array['zz-ensaio-r']
                     and (select url from mkt_trafego.clickup_tarefas where tarefa_id = '86ensaio3') is null,
                     'a etiqueta lida entra mesmo se a tarefa vier sem ela; url de fora do ClickUp não é guardada');
  r := pg_temp.adm(format('select public.trafego_clickup(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('4.vida do projeto', r ->> 'etiqueta' = 'zz-ensaio-r' and jsonb_array_length(r -> 'tarefas') = 3
                     and r -> 'tarefas' -> 0 ->> 'id' = '86ensaio2' and (r ->> 'configurado')::boolean = false,
                     'ZZ28: 3 tarefas, a de prazo mais adiante primeiro; workspace não configurado');
  v := pg_temp.srv($j$select public.trafego_clickup_receber('{"etiqueta": "zz-ensaio-r", "tarefas": [
    {"id": "86ensaio3", "nome": "Revisar verba (ENSAIO)", "status": "complete", "etiquetas": ["zz-ensaio-r"]}]}')$j$);
  perform pg_temp.ok('4.sumiu', (v ->> 'removidas')::int = 2 and not exists (select 1 from mkt_trafego.clickup_tarefas where tarefa_id = '86ensaio1')
                     and (select etiquetas from mkt_trafego.clickup_tarefas where tarefa_id = '86ensaio2') = array['outra-etq']
                     and (select status from mkt_trafego.clickup_tarefas where tarefa_id = '86ensaio3') = 'complete',
                     'reenvio sem 2 tarefas: a só desta etiqueta sai; a com outra etiqueta perde só esta; a que veio é atualizada');
  r := pg_temp.adm(format('select public.trafego_clickup(%s)', pg_temp.proj('ZZ28')));
  perform pg_temp.ok('4.lista', jsonb_array_length(r -> 'tarefas') = 1, 'vida do projeto: 1 tarefa');
  v := pg_temp.srv($j$select public.trafego_clickup_receber('{"etiqueta": "etiqueta-de-ninguem", "tarefas": []}')$j$);
  perform pg_temp.ok('4.etiqueta estranha', not (v ->> 'ok')::boolean, 'etiqueta que não é de projeto recusada');
  r := pg_temp.adm(format('select public.trafego_clickup(%s)', pg_temp.proj('ZX28')));
  perform pg_temp.ok('4.sem etiqueta', r -> 'etiqueta' = 'null'::jsonb and r -> 'tarefas' = '[]'::jsonb, 'projeto sem etiqueta: lista vazia');
  perform pg_temp.ok('4.etiquetas lidas', array(select mkt_trafego.clickup_etiquetas()) @> array['zz-ensaio-r'], 'a rotina lê a etiqueta dos projetos ativos');
end
$t$;

-- ─── 5. Credenciais das rotinas (só postgres) e registro das coletas ─────────────────────────────────────────────────
do $t$
declare v_n int; r record;
begin
  select * into r from mkt_trafego.meta_contas() where conta_externa = '000555';
  perform pg_temp.ok('5.conta central', r.token_origem = 'meta_ads_token', 'conta sem token próprio usa o da conta centralizadora (meta_ads_token)');
  update mkt_trafego.contas set token_vault = 'meta_ads_token_ensaio_zz' where conta_externa = '000555';
  if to_regclass('vault.decrypted_secrets') is not null then
    perform vault.create_secret('token-ficticio-ensaio', 'meta_ads_token_ensaio_zz', 'ensaio 20261006i');
    select * into r from mkt_trafego.meta_contas() where conta_externa = '000555';
    perform pg_temp.ok('5.token por conta', r.token_origem = 'meta_ads_token_ensaio_zz' and r.token = 'token-ficticio-ensaio',
                       'conta com token_vault lê o próprio segredo (fictício) do Vault');
  else
    select * into r from mkt_trafego.meta_contas() where conta_externa = '000555';
    perform pg_temp.ok('5.token por conta', r.token_origem = 'meta_ads_token_ensaio_zz' and r.token is null, 'sem Vault: token nulo, sem erro');
  end if;
  begin
    update mkt_trafego.contas set token_vault = 'Token Errado' where conta_externa = '000555';
    perform pg_temp.ok('5.nome do segredo', false, 'nome de segredo fora do formato deveria ser recusado');
  exception when check_violation then
    perform pg_temp.ok('5.nome do segredo', true, 'nome de segredo fora do formato recusado pelo banco (23514)');
  end;
  perform pg_temp.ok('5.clickup', (select team_id from mkt_trafego.clickup_credenciais()) is null, 'ClickUp sem workspace configurado: nulo');
  for v_n in 1..205 loop
    perform mkt_trafego.coleta_registrar('google', true, jsonb_build_object('ensaio', v_n), null);
  end loop;
  perform pg_temp.ok('5.registro', (select count(*) from mkt_trafego.coletas where fonte = 'google') = 200
                     and (pg_temp.adm('select public.trafego_alertas()') -> 'coletas' -> 'google' ->> 'ok')::boolean,
                     'registro guarda as 200 últimas por fonte; o resumo do dia mostra a última');
end
$t$;

-- ─── 6. O formato que a Edge trafego-meta manda é aceito pelas entradas da 20261006g (fixtures do vitest) ──────────
-- As listas abaixo são a SAÍDA de paraCampanhas/paraDesempenho sobre as fixtures (coleta.test.ts confere a mesma coisa).
do $t$
declare v jsonb;
begin
  v := pg_temp.srv($j$select public.trafego_campanhas_receber('[
    {"plataforma":"meta","conta":"000555","id":"900000000000201","nome":"RS | ZZ28 | LEADS | ENSAIO PÚBLICO FRIO | AK1","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000202","nome":"CF | ZZ28 | REMARKETING | ENSAIO","status":"PAUSED"},
    {"plataforma":"meta","conta":"000555","id":"900000000000203","nome":"Campanha ENSAIO fora do padrão","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000555","id":"900000000000209","nome":"RS | ZZ28 | LEADS | ENSAIO APAGADA","status":null}]')$j$);
  perform pg_temp.ok('6.campanhas', (v ->> 'novas')::int = 4 and v -> 'recusas' = '[]'::jsonb, '4 campanhas no formato da Edge, sem recusa');
  v := pg_temp.srv($j$select public.trafego_desempenho_receber('[
    {"plataforma":"meta","campanha":"900000000000201","dia":"2026-10-03","gasto":150.25,"impressoes":12000,"cliques_link":180,"cliques_total":260,"leads":12},
    {"plataforma":"meta","campanha":"900000000000201","dia":"2026-10-04","gasto":149.75,"impressoes":11000,"cliques_link":170,"cliques_total":240,"leads":9},
    {"plataforma":"meta","campanha":"900000000000202","dia":"2026-10-04","gasto":20,"impressoes":3000,"cliques_link":0,"cliques_total":15,"leads":null},
    {"plataforma":"meta","campanha":"900000000000209","dia":"2026-10-03","gasto":5.5,"impressoes":400,"cliques_link":3,"cliques_total":null,"leads":null}]')$j$);
  perform pg_temp.ok('6.desempenho', (v ->> 'gravadas')::int = 4 and v -> 'recusas' = '[]'::jsonb
                     and (select cliques_total from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                           where c.campanha_externa = '900000000000209') is null
                     and (select leads_plataforma from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                           where c.campanha_externa = '900000000000201' and d.dia = '2026-10-03') = 12,
                     '4 dias no formato da Edge; cliques totais e leads nulos quando o Meta não informa');
  v := pg_temp.srv($j$select public.trafego_desempenho_receber('[
    {"plataforma":"meta","campanha":"900000000000201","dia":"2026-10-03","gasto":150.25,"impressoes":12000,"cliques_link":180,"cliques_total":260,"leads":12}]')$j$);
  perform pg_temp.ok('6.idempotente', (select count(*) from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                                        where c.campanha_externa like '90000000000020%') = 4, 'rodar de novo não duplica (upsert por campanha e dia)');
end
$t$;

-- ─── 7. Grants ───────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('7.tabelas', not exists (select 1 from information_schema.role_table_grants
                                            where table_schema = 'mkt_trafego' and grantee in ('anon', 'authenticated', 'PUBLIC')),
                  'nenhuma tabela de mkt_trafego com grant para anon/authenticated');
select pg_temp.ok('7.funcoes',
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute')) from pg_proc p
    where (p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') or p.pronamespace = 'mkt_trafego'::regnamespace)
  and (select bool_and(not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute'))
         from pg_proc p where p.pronamespace = 'mkt_trafego'::regnamespace)
  and has_function_privilege('authenticated', 'public.trafego_alertas()', 'execute')
  and has_function_privilege('authenticated', 'public.trafego_clickup(bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.trafego_receita(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.trafego_clickup_receber(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.trafego_clickup_receber(jsonb)', 'execute'),
  'anon nada; internas (inclusive as que leem o Vault) fechadas até para service_role; tela authenticated; clickup_receber só service_role');

-- ─── 8. Recusas: sem perfil, operador (mesmo com a área), visualizador, anon; e o admin nas internas ─────────────────
do $t$
declare
  c text; u text; v_papel text;
  v_chamadas text[] := array[
    'select public.trafego_alertas()',
    'select public.trafego_produtos_listar()',
    'select public.trafego_produto_salvar(''{}'')',
    'select public.trafego_produto_apagar(1)',
    'select public.trafego_hotmart_produtos()',
    'select public.trafego_clickup(1)',
    'select public.trafego_receita(1)',
    'select public.trafego_clickup_receber(''{}'')',
    'select count(*) from mkt_trafego.meta_contas()'];
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
        v_errado := concat_ws(', ', v_errado, split_part(split_part(c, '(', 1), '.', 2));
      exception when insufficient_privilege then
        reset role;
        v_ok := v_ok + 1;
      end;
    end loop;
    begin
      execute format('set local role %I', v_papel);
      perform 1 from mkt_trafego.produtos_hotmart limit 1;
      reset role;
      v_errado := concat_ws(', ', v_errado, 'select direto');
    exception when insufficient_privilege then
      reset role;
      v_ok := v_ok + 1;
    end;
    perform pg_temp.ok('8.' || case split_part(u, ':', 1) when '33333333-3333-4333-8333-333333333333' then 'visualizador'
                                 when '22222222-2222-4222-8222-222222222222' then 'operador'
                                 else 'sem perfil' end || ' ' || v_papel,
                       v_errado is null, v_ok || ' recusas 42501' || coalesce(' / PASSOU: ' || v_errado, ''));
  end loop;
  -- o ADMIN também não lê as credenciais das rotinas (só o postgres, isto é, a Edge)
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  v_ok := 0; v_errado := null;
  foreach c in array array['select count(*) from mkt_trafego.meta_contas()', 'select mkt_trafego.coleta_chave()',
                           'select count(*) from mkt_trafego.clickup_credenciais()', 'select mkt_trafego.segredo(''meta_ads_token'')'] loop
    begin
      set local role authenticated;
      execute c;
      reset role;
      v_errado := concat_ws(', ', v_errado, c);
    exception when insufficient_privilege then
      reset role;
      v_ok := v_ok + 1;
    end;
  end loop;
  perform pg_temp.ok('8.admin internas', v_errado is null, v_ok || ' recusas 42501 para o admin nas funções que leem o Vault' || coalesce(' / PASSOU: ' || v_errado, ''));
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  begin
    set local role service_role;
    perform count(*) from mkt_trafego.meta_contas();
    reset role;
    perform pg_temp.ok('8.service_role internas', false, 'service_role leu mkt_trafego.meta_contas');
  exception when insufficient_privilege then
    reset role;
    perform pg_temp.ok('8.service_role internas', true, 'service_role também não lê os tokens (42501)');
  end;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
