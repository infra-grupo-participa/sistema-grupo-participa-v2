-- 20261006i: Marketing > Tráfego, fase 2 (resumo do dia, receita da Hotmart, atividades do ClickUp, coleta Meta Ads)
--
-- O QUE FAZ
--   Adianta o que não depende de decisão em aberto (05/10/2026, branch victor). Depende da 20261006g (NÃO aplicada).
--     1. Resumo do dia ("o que está pegando fogo"): public.trafego_alertas() lê o resumo da Central e devolve os alertas
--        de hoje (sobre o último dia completo, São Paulo): acima da verba diária, ritmo da fase acima/abaixo do
--        planejado, abaixo da meta de leads para a data, CPL acima da meta, % da verba perto do fim, campanhas fora do
--        padrão e campanhas sem fase. Os limiares ficam na tabela mkt_trafego.alerta_regras (nada de número mágico no
--        código); os valores iniciais são PROPOSTA, para o Victor confirmar. Projetos desativados em mkt.projetos ou
--        com status que não entra no resumo (em planejamento, inativo, encerrado: coluna status_projeto.entra_no_resumo_dia)
--        ficam fora.
--     2. Receita gerada (Hotmart): vínculo produto Hotmart → projeto (mkt_trafego.produtos_hotmart), CADASTRO À MÃO
--        (escolhido na lista de produtos que já venderam; nada pré-preenchido). A FONTE é fin.hotmart_transacoes, o
--        espelho da Hotmart do financeiro (20260927, já em produção), com as DUAS contas da Hotmart (coluna conta:
--        'academy' e 'escritorio'). O vínculo guarda a conta, e o casamento é por conta + produto_id (+ oferta, se
--        preenchida). Regra do financeiro (fin.vw_transacoes, 20260927b), seguida igual:
--          paga      = status APPROVED ou COMPLETE (o grupo 'pago' da view). Reembolso, chargeback e cancelamento: a
--                      Hotmart troca o status da própria transação, então ela sai da soma (inclusive de dias passados).
--          data      = aprovado_em, dia de São Paulo (o dia_aprovado da view, o mesmo do faturamento diário).
--          receita   = BRUTO = valor da oferta = coalesce(valor_base, bruto_json purchase.hotmart_fee.base, valor_cobrado):
--                      o "valor_oferta" da view, que o financeiro chama de bruto do negócio. NÃO é valor_cobrado (que
--                      inclui os juros do parcelamento que o cliente paga à Hotmart).
--          líquido   = coalesce(liquido_produtor, oferta − taxa_hotmart): o "liquido" da view (estimado quando a
--                      Hotmart não mandou a comissão; contado à parte). Vai como coluna extra (receita_liquida).
--        Período = de/até do vínculo, senão mkt_trafego.periodo_receita (fim vazio = até hoje); sem início = o vínculo
--        não soma. Sem vínculo = receita nula ("sem dado"). Só soma moeda BRL; transação em outra moeda é contada à
--        parte. Nada de valor é copiado: lido de fin.hotmart_transacoes na hora (a Hotmart manda no dinheiro).
--        RECEITA POR NÍVEL DE CERTEZA (decisão do Victor, 06/10/2026; docs/central-de-dados.md, seção "Receita do projeto:
--        oferta exclusiva e SCK"): cada venda paga conta UMA vez, no nível mais forte: 1 oferta exclusiva do projeto
--        (produtos_hotmart.oferta_exclusiva; uma oferta, por conta, só de um projeto: índice único), 2 SCK com o projeto
--        no campo campanha (formato DECIDIDO origem|meio|campanha|conteúdo|termo; chave = etiqueta do ClickUp ou sigla;
--        leitura só em mkt_trafego.sck_campanha), 3 comprador que foi lead do projeto antes da compra (base de pessoas do
--        Arthur, só leitura) em produto ligado no período, 4 só produto + período = ESTIMADA, à parte. A receita do
--        projeto (e qualquer ROAS) = níveis 1 a 3. Venda que casa com dois projetos no mesmo nível = disputa (não soma em
--        nenhum; lista na vida do projeto, public.trafego_receita).
--     3. Atividades do ClickUp na vida do projeto: espelho mínimo (mkt_trafego.clickup_tarefas: id, nome, status,
--        datas, responsáveis, etiquetas, url) gravado pela rotina trafego-clickup (Edge), que LÊ a API do ClickUp pela
--        etiqueta do projeto (mkt.projetos.etiqueta_clickup). Só leitura no ClickUp. Token no Vault
--        (clickup_api_token, a cadastrar: decisão do Victor); id do workspace em mkt_trafego.coleta_config.
--     4. Coleta Meta Ads: rotina trafego-meta (Edge) lê os insights por campanha e dia das contas Meta ativas de
--        mkt_trafego.contas e grava pelas funções de entrada da 20261006g (upsert idempotente; cliques_link =
--        inline_link_clicks, separado de cliques totais; leads da plataforma). Token no Vault: meta_ads_token (conta
--        centralizadora) OU um segredo por conta (coluna contas.token_vault): a decisão está em aberto e as duas formas
--        funcionam. AS ROTINAS NÃO SÃO AGENDADAS AQUI (ficam desligadas até o Victor decidir): ver o bloco LIGAR no fim.
--     5. Google Ads: só desenho (docs/central-de-dados.md) e esqueleto da leitura em infra/supabase/functions/trafego-google.
--   Fontes: plano-trafego.md e area-de-trafego.md no cérebro do Victor; docs/central-de-dados.md (seção Tráfego).
--
--   Padrão do repo (igual 20261005m/o/p/q): tabelas fechadas (RLS ligada, sem policy, revoke de anon/authenticated),
--   schema sem USAGE, acesso só por função public.trafego_* SECURITY DEFINER com search_path '' e a trava dentro
--   (mkt.pode_ver('mkt_trafego'): hoje só admin/dev). trafego_clickup_receber é só de service_role. As funções que leem
--   o Vault (credenciais das rotinas) não têm grant para ninguém: só o postgres (a Edge entra com SUPABASE_DB_URL).
--
-- O QUE CRIA
--   tabelas   mkt_trafego.alerta_regras, produtos_hotmart (com oferta_exclusiva e o índice único
--             produtos_hotmart_oferta_exclusiva_unica), clickup_tarefas, coleta_config, coletas
--   colunas   mkt_trafego.status_projeto.entra_no_resumo_dia, mkt_trafego.contas.token_vault
--   internas  mkt_trafego.resumo(bigint) NOVA (a da 20261006g vira resumo_base e esta acrescenta a receita),
--             receita(bigint), periodo_padrao(bigint), periodo_receita(bigint), hotmart_disponivel(), alertas(), coleta_chave(), meta_contas(), clickup_credenciais(),
--             clickup_etiquetas(), coleta_parametros(), coleta_registrar(text,boolean,jsonb,text),
--             chave_norm(text), sck_campanha(text), pessoas_disponivel(), receita_vendas(bigint)
--   public    trafego_alertas, trafego_produtos_listar, trafego_produto_salvar, trafego_produto_apagar,
--             trafego_hotmart_produtos, trafego_clickup, trafego_receita (authenticated); trafego_clickup_receber (service_role)
--   Vault     trafego_coleta_chave (header x-sync-chave das rotinas; aleatório, criado aqui se houver Vault)
--
-- AS 5 PERGUNTAS
--   escala: alertas = dezenas de projetos; produtos_hotmart = poucos por projeto; clickup_tarefas = centenas a poucos
--     milhares por ano; coletas = 200 por fonte (o resto é apagado).
--   índice: produtos_hotmart único (projeto, conta, produto, oferta) e (conta, produto_id); clickup_tarefas
--     gin(etiquetas); coletas (fonte, id desc). A receita lê fin.hotmart_transacoes por produto_id e faixa de
--     aprovado_em: o índice do financeiro hotmart_transacoes_produto_idx (produto_id, aprovado_em) já serve (conferido no
--     banco real em 06/10/2026: 57.877 linhas); conta e status são filtro residual (2 contas). Nenhum índice novo na
--     tabela do financeiro (não é nossa). A lista de produtos do seletor (trafego_hotmart_produtos) lê a tabela
--     inteira agrupada (57 mil linhas, só ao abrir o modal de ligar produto, admin/dev). O nível 2 da receita (SCK)
--     olha todas as vendas pagas com "|" no sck, de qualquer produto: no banco real (06/10/2026) 123 a 176 ms quente,
--     7,4 s frio; índice parcial RECOMENDADO ao dono do fin (não criado aqui): ver 20261006i.explain.md. O nível 3 lê
--     pessoas.eventos pelo índice eventos_projeto_idx e os identificadores/compradores/alunos pela chave.
--   frequência: trafego_alertas ao abrir a Central; trafego_clickup ao abrir a vida do projeto; coleta Meta 1x/dia (mais
--     leituras do dia corrente, se ligar); ClickUp 1x/dia.
--   repetição: o resumo do dia chama mkt_trafego.resumo uma vez; a receita é uma query só, agrupada por projeto.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261006i_ensaio.sql (begin … rollback). Explicação: 20261006i.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

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


-- ═══ LIGAR AS ROTINAS (NÃO rodar agora: decisão do Victor). Horário do cron em UTC ══════════════════════════════════════
-- Antes: publicar as Edges (supabase functions deploy trafego-meta / trafego-clickup; verify_jwt = false está no
-- config.toml), cadastrar o token no Vault e as contas em Marketing > Tráfego > Contas de anúncio.
--   Meta, conta centralizadora:  select vault.create_secret('<token>', 'meta_ads_token', 'Token Meta Ads (leitura de insights).');
--   Meta, token por conta:        select vault.create_secret('<token>', 'meta_ads_token_<nome>', '…');
--                                 update mkt_trafego.contas set token_vault = 'meta_ads_token_<nome>' where id = <id>;
--   ClickUp:                      select vault.create_secret('<token>', 'clickup_api_token', 'Token ClickUp (só leitura de tarefas).');
--                                 update mkt_trafego.coleta_config set valor = '<id do workspace>' where chave = 'clickup_team_id';
-- select cron.schedule('trafego-meta', '30 9 * * *', $c$
--   select ops.cron_post('trafego-meta',
--     url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-meta',
--     body := '{}'::jsonb,
--     headers := jsonb_build_object('Content-Type', 'application/json',
--       'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'trafego_coleta_chave')),
--     timeout_milliseconds := 150000)
-- $c$);
-- -- (opcional) leitura do dia corrente para o ritmo, de 3 em 3 horas das 09h às 21h SP: mesmo comando com '0 12-23/3 * * *'
-- --   e o job 'trafego-meta-hoje' (body '{"so_hoje": true}').
-- select cron.schedule('trafego-clickup', '0 10 * * *', $c$
--   select ops.cron_post('trafego-clickup',
--     url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-clickup',
--     body := '{}'::jsonb,
--     headers := jsonb_build_object('Content-Type', 'application/json',
--       'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'trafego_coleta_chave')),
--     timeout_milliseconds := 150000)
-- $c$);
-- Desligar: select cron.unschedule('trafego-meta'); select cron.unschedule('trafego-clickup');


-- ═══ REVERSÃO (numa transação; apaga vínculos de produto, espelho do ClickUp, regras e registro das coletas) ═══════════
-- begin;
-- select cron.unschedule(j) from unnest(array['trafego-meta', 'trafego-meta-hoje', 'trafego-clickup']) j
--  where exists (select 1 from cron.job where jobname = j);
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p
--             where (p.pronamespace = 'public'::regnamespace and p.proname in ('trafego_alertas', 'trafego_produtos_listar',
--                    'trafego_produto_salvar', 'trafego_produto_apagar', 'trafego_hotmart_produtos', 'trafego_clickup',
--                    'trafego_clickup_receber', 'trafego_receita'))
--                or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('resumo', 'receita', 'hotmart_disponivel',
--                    'alertas', 'segredo', 'coleta_chave', 'meta_contas', 'clickup_credenciais', 'clickup_etiquetas',
--                    'coleta_parametros', 'coleta_registrar', 'periodo_padrao', 'periodo_receita', 'chave_norm', 'sck_campanha',
--                    'pessoas_disponivel', 'receita_vendas'))
--   loop execute format('drop function %s', f); end loop; end $$;
-- alter function mkt_trafego.resumo_base(bigint) rename to resumo;
-- drop table mkt_trafego.alerta_regras, mkt_trafego.produtos_hotmart, mkt_trafego.clickup_tarefas, mkt_trafego.coleta_config,
--            mkt_trafego.coletas;
-- alter table mkt_trafego.status_projeto drop column entra_no_resumo_dia;
-- alter table mkt_trafego.contas drop column token_vault;
-- -- os segredos ficam no Vault (inofensivos sem as rotinas). Só o que esta migration criou pode sair:
-- -- delete from vault.secrets where name = 'trafego_coleta_chave';
-- -- (meta_ads_token e clickup_api_token foram cadastrados à mão: não apagar aqui)
-- commit;
