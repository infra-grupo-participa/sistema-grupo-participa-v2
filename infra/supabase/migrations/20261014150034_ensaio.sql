-- APLICADA em 14/10/2026 com a versão gravada 20261014150034 (o arquivo se chamava 20261014170000; renomeado conforme o guia 6.3).
-- Ensaio de 20261014170000 (estrutura da carga do ActiveCampaign) com a cadeia SÓ de pessoas: 20261014160200 e os índices
-- da 160300 (sem concurrently), numa transação DESFEITA. Nada do schema fin é alterado (160000/160100 não entram: esperam o
-- aceite do JP). Contatos FICTÍCIOS (e-mails @exemplo.invalid, sem dado pessoal), mais 1 contato que reaproveita um e-mail
-- que já existe em pessoas.identificadores (lido dentro da transação, nunca escrito aqui) para provar o casamento.
-- A prova com amostra REAL do AC fica no script: infra/scripts/pessoa-unica/carga_ac.py --ensaio 100.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '01 antes: fin.eventos tem chave? (esperado 0)', count(*)::text from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name = 'chave';
-- ===== 20261014160200 =====
-- 20261014160200: linha do tempo da pessoa ligada ao evento oficial e à fonte; relação "sócio de"; mapa de ofertas
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2), 14/10/2026. NÃO depende de 160000/160100 (desacoplada em
--   14/10 para a carga do AC poder rodar sem mexer no schema fin, que espera o aceite do JP). Só lê fin (FK e view).
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
-- ===== 20261014170000 =====
-- 20261014170000: estrutura da carga do ActiveCampaign completo para a pessoa única (estágio, controle, funções)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende SÓ de 20261014160200 e 160300 (pessoas.eventos.fonte_tabela/
--   fonte_id e o índice único eventos_fonte_unico, que o on conflict usa). Não depende de nada no schema fin.
--   Ensaio: 20261014170000_ensaio.sql (cadeia inteira + amostra real de 300 contatos, transação desfeita).
--   Script da carga: infra/scripts/pessoa-unica/carga_ac.py. Detalhe: 20261014170000.explain.md.
--
-- POR QUE: o Victor decidiu (14/10/2026) trazer os ~508 mil contatos do ActiveCampaign hoje à noite, em lotes, como no
--   estudo de capacidade (censo-capacidade-ac.md). Lição de 08/10: rajada derrubou o banco. Por isso: uma conexão só,
--   lotes de 1.000, chave de desligar no banco, retomada pelo cursor, registro de cada lote.
-- O QUE CRIA (tudo no schema pessoas, que não é exposto ao PostgREST):
--   pessoas.carga_execucao   uma linha por execução (fonte, fase, cursor, contadores, contagem antes/depois, status).
--   pessoas.carga_lote       uma linha por lote (cursor de/até, contadores, ms). É o rastro para retomar e auditar.
--   pessoas.carga_chave      chave de desligar por fonte: ligada = false e toda função de carga daquela fonte recusa o
--                            próximo lote (em ~2 s). Não usa pessoas.config (lá o valor tem de ser array: são as áreas).
--   pessoas.ac_catalogo      espelho do catálogo do AC (listas, tags e campos: id e nome exato). Estágio, não fonte.
--   pessoas.ac_campo_carga   quais campos personalizados entram em ac_contato.campos (perstag -> valor). CPF NÃO
--                            entra (decisão 7: a pessoa oficial não guarda CPF).
--   pessoas.ac_lista_papel   listas que viram linha na linha do tempo: as 8 de Sessão de Viabilidade (pré-checkout da
--                            SV, decisão do Victor de 14/10) e as 6 com "pré-checkout" no nome.
--   pessoas.ac_contato       estágio: uma linha por contato do AC (e-mail e telefone normalizados, nome, datas,
--                            listas [lista, status, data de inscrição, saiu_pela_pessoa], tags, campos, descadastro).
--   pessoas.casar_email()    casamento SÓ por e-mail (igual ao passo 1 do pessoas.resolver: identificadores, aluno,
--                            comprador), cria a pessoa se ninguém casar, anexa e-mail e telefone. NÃO procura por
--                            telefone nem por nome (em massa isso abriria dezenas de milhares de revisões); conflito de
--                            e-mail continua indo para pessoas.revisao.
--   pessoas.carga_*()        abrir/fechar execução, gravar catálogo, gravar lote no estágio, passar estágio -> pessoas.
-- REGRA DO DESCADASTRO (dicionário, item 4; censo-capacidade-ac.md): numa inscrição com status 2, "saiu pela pessoa" =
--   campaign ou message preenchido (link do e-mail) ou unsubreason preenchido. ac_contato.descadastrou = alguma inscrição
--   status 2 saiu pela pessoa (não pode disparar). desativado_empresa = alguma inscrição status 2 sem esses sinais
--   (inativo da empresa: continua disparável). A regra roda no script, que manda o booleano por inscrição.
-- LINHA DO TEMPO: cada contato vira 1 evento 'lead' (fonte activecampaign, fonte_tabela 'pessoas.ac_contato',
--   fonte_id = id do contato, quando = criação no AC); cada inscrição numa lista de ac_lista_papel vira 1 evento
--   'pre_checkout' (fonte_id = contato:lista, evento_id da lista quando houver, quando = data da inscrição). Repetir a
--   carga não duplica (on conflict no índice eventos_fonte_unico).
-- AS 5 PERGUNTAS: escala = 508 mil contatos (~130 MB no estágio, ~690 MB em pessoas; estudo de capacidade); índice =
--   PK do contato, parcial dos pendentes, e-mail e pessoa; e-mail via pessoas.identificadores (tipo, chave);
--   frequência = 1 carga (noite de 14/10) + recargas incrementais; repetição = idempotente (upsert com IS DISTINCT FROM,
--   on conflict nos eventos); reversão = 20261014170000_reversao.sql (o estágio sai; pessoas criadas pela carga ficam
--   identificadas por pessoas.ac_contato.pessoa_id ANTES da reversão: ver o explain).
-- ACESSO: tabelas com RLS ligada, sem policy e sem grant; funções sem execute para public, anon, authenticated e
--   service_role (só postgres, pelo script). Nada novo exposto. Pentester: revisar mesmo assim (dado pessoal em massa).

set local lock_timeout = '5s';

do $g$
begin
  if to_regclass('pessoas.ac_contato') is not null or to_regclass('pessoas.carga_execucao') is not null then
    raise exception '20261014170000: a estrutura da carga já existe.';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'eventos' and column_name = 'fonte_id') then
    raise exception '20261014170000: falta 20261014160200 (pessoas.eventos.fonte_id).';
  end if;
  if to_regclass('pessoas.eventos_fonte_unico') is null then
    raise exception '20261014170000: falta 20261014160300 (índice pessoas.eventos_fonte_unico).';
  end if;
  if (select nome from fin.eventos where id = 89) is distinct from 'Imersão Holding Total (HT32)'
     or (select nome from fin.eventos where id = 101) is distinct from 'Clínica Internacional de Holding Familiar' then
    raise exception '20261014170000: eventos 89/101 do catálogo mudaram. Reler as listas de pré-checkout.';
  end if;
end
$g$;

-- ===================== controle =====================
create table pessoas.carga_execucao (
  id              bigint generated always as identity primary key,
  fonte           text not null check (fonte ~ '^[a-z_]+$'),
  fase            text not null check (fase in ('catalogo', 'estagio', 'pessoas')),
  status          text not null default 'rodando' check (status in ('rodando', 'parada', 'ok', 'erro')),
  cursor          text,
  lotes           integer not null default 0,
  lidas           bigint not null default 0,
  inseridas       bigint not null default 0,
  atualizadas     bigint not null default 0,
  iguais          bigint not null default 0,
  contagem_antes  jsonb,
  contagem_depois jsonb,
  erro            text check (erro is null or length(erro) <= 2000),
  por             text check (por is null or length(por) <= 80),
  iniciada_em     timestamptz not null default now(),
  atualizada_em   timestamptz not null default now(),
  terminada_em    timestamptz
);
create unique index carga_execucao_aberta_unica on pessoas.carga_execucao (fonte, fase) where status in ('rodando', 'parada');
alter table pessoas.carga_execucao enable row level security;

create table pessoas.carga_lote (
  id          bigint generated always as identity primary key,
  execucao_id bigint not null references pessoas.carga_execucao(id) on delete restrict,
  cursor_de   text,
  cursor_ate  text,
  lidas       integer not null default 0,
  inseridas   integer not null default 0,
  atualizadas integer not null default 0,
  iguais      integer not null default 0,
  detalhe     jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object' and length(detalhe::text) <= 2000),
  ms          integer,
  em          timestamptz not null default now()
);
create index carga_lote_execucao_idx on pessoas.carga_lote (execucao_id, id);
alter table pessoas.carga_lote enable row level security;

create table pessoas.carga_chave (
  fonte  text primary key check (fonte ~ '^[a-z_]+$'),
  ligada boolean not null,
  ate    date,                     -- data de fim: depois dela a fonte fica desligada sozinha (rotina externa: regra do Victor)
  por    text check (por is null or length(por) <= 80),
  em     timestamptz not null default now()
);
alter table pessoas.carga_chave enable row level security;
comment on table pessoas.carga_chave is 'Chave de desligar das cargas da pessoa única: update pessoas.carga_chave set ligada = false where fonte = ''activecampaign''.';
insert into pessoas.carga_chave (fonte, ligada, por) values ('activecampaign', true, 'migration 20261014170000');

-- ===================== estágio do ActiveCampaign =====================
create table pessoas.ac_catalogo (
  tipo     text not null check (tipo in ('lista', 'tag', 'campo')),
  id       integer not null,
  nome     text not null check (length(nome) between 1 and 300),
  extra    jsonb not null default '{}' check (jsonb_typeof(extra) = 'object'),
  visto_em timestamptz not null default now(),
  primary key (tipo, id)
);
alter table pessoas.ac_catalogo enable row level security;
comment on table pessoas.ac_catalogo is 'Espelho do catálogo do ActiveCampaign (listas, tags, campos: id e nome exato), gravado pela carga. Estágio.';

create table pessoas.ac_campo_carga (
  field_id integer primary key,
  perstag  text not null check (perstag ~ '^[A-Z0-9_]+$'),
  titulo   text not null,
  motivo   text not null
);
alter table pessoas.ac_campo_carga enable row level security;
comment on table pessoas.ac_campo_carga is 'Campos personalizados do AC que entram em pessoas.ac_contato.campos. CPF (336) fica de fora por decisão (LGPD).';
insert into pessoas.ac_campo_carga (field_id, perstag, titulo, motivo) values
  (372, 'PESQUISAESTADO', 'pesquisa_estado', 'pesquisa da SV'),
  (373, 'PESQUISAIDADE', 'pesquisa_idade', 'pesquisa da SV'),
  (374, 'PESQUISAHERDEIROS', 'pesquisa_herdeiros', 'pesquisa da SV'),
  (375, 'PESQUISAIMOVEIS', 'pesquisa_imoveis', 'pesquisa da SV'),
  (376, 'PESQUISAVALOR', 'pesquisa_valor', 'pesquisa da SV'),
  (377, 'PESQUISAOBJETIVOS', 'pesquisa_objetivos', 'pesquisa da SV'),
  (379, 'DATA_PESQUISA', 'Data pesquisa', 'pesquisa da SV'),
  (231, 'SV_ORIGEM', '[SV] Origem', 'Sessão de Viabilidade'),
  (232, 'SV_STATUS_DA_COMPRA', '[SV] Status da compra', 'Sessão de Viabilidade'),
  (238, 'SV_DATA_DE_REEMBOLSO', '[SV] Data de reembolso', 'Sessão de Viabilidade'),
  (240, 'SV_DATA_DA_COMPRA_1', ' [SV] Data da compra', 'Sessão de Viabilidade'),
  (277, 'SV_DATA', ' [SV] Data ', 'Sessão de Viabilidade'),
  (192, 'PROFISSO', 'Profissão', 'perfil (MQL)'),
  (193, 'UTM_SOURCE', 'utm_source', 'origem'),
  (194, 'UTM_MEDIUM', ' utm_medium', 'origem'),
  (195, 'UTM_CAMPAIGN', ' utm_campaign', 'origem'),
  (196, 'UTM_CONTENT', ' utm_content', 'origem'),
  (197, 'UTM_TERM', ' utm_term', 'origem'),
  (261, 'WHATSAPP', 'Whatsapp', 'contato');

create table pessoas.ac_lista_papel (
  lista_id  integer primary key,
  papel     text not null check (papel in ('sv_pre_checkout', 'pre_checkout')),
  evento_id bigint references fin.eventos(id) on delete restrict,
  fonte     text not null check (length(fonte) between 1 and 300)
);
alter table pessoas.ac_lista_papel enable row level security;
comment on table pessoas.ac_lista_papel is 'Listas do AC cuja inscrição vira evento pre_checkout na linha do tempo. Nome exato no pessoas.ac_catalogo.';
insert into pessoas.ac_lista_papel (lista_id, papel, evento_id, fonte) values
  (412, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (454, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (486, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (504, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (539, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (555, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (607, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (623, 'sv_pre_checkout', null, 'Victor 14/10/2026: todas as listas de Sessão de Viabilidade contam'),
  (582, 'pre_checkout', null, 'nome da lista diz pré-checkout'),
  (584, 'pre_checkout', null, 'nome da lista diz pré-checkout'),
  (590, 'pre_checkout', 89, 'nome da lista diz pré-checkout e HT/SET26; fin.eventos 89 = Imersão Holding Total (HT32)'),
  (593, 'pre_checkout', 89, 'nome da lista diz pré-checkout e HT 32; fin.eventos 89 = Imersão Holding Total (HT32)'),
  (608, 'pre_checkout', null, 'nome da lista diz pré-checkout'),
  (614, 'pre_checkout', 101, 'nome da lista diz pré-checkout e Clínica Dez/26; fin.eventos 101 = Clínica Internacional de Holding Familiar; migration 20261007152751');

create table pessoas.ac_contato (
  contact_id         integer primary key,
  email              text check (email is null or length(email) <= 320),
  telefone           text check (telefone is null or telefone ~ '^[0-9]{10,11}$'),
  nome               text check (nome is null or length(nome) <= 160),
  criado_em_ac       timestamptz,
  atualizado_em_ac   timestamptz,
  bounced_hard       smallint,
  listas             jsonb not null default '[]' check (jsonb_typeof(listas) = 'array'),
  tags               integer[] not null default '{}',
  campos             jsonb not null default '{}' check (jsonb_typeof(campos) = 'object'),
  descadastrou       boolean not null default false,
  desativado_empresa boolean not null default false,
  pendente           boolean not null default true,
  pessoa_id          uuid references pessoas.pessoas(id) on delete restrict,
  pessoa_nova        boolean,            -- true = a pessoa foi criada por esta carga (a reversão usa)
  nota               text check (nota is null or nota in ('sem_email')),
  carregado_em       timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  processado_em      timestamptz
);
alter table pessoas.ac_contato enable row level security;
create index ac_contato_pendente_idx on pessoas.ac_contato (contact_id) where pendente;
create index ac_contato_email_idx on pessoas.ac_contato (email) where email is not null;
create index ac_contato_pessoa_idx on pessoas.ac_contato (pessoa_id) where pessoa_id is not null;
comment on table pessoas.ac_contato is 'Estágio: um contato do ActiveCampaign por linha. listas = [[lista_id, status, data_inscricao, saiu_pela_pessoa], ...] '
  '(status 1 ativo, 2 descadastrado, 3 bounce, 0 não confirmado). descadastrou = saiu pela pessoa (não dispara); desativado_empresa = '
  'inativo da empresa (dispara). pendente = falta passar para pessoas.';

revoke all on pessoas.carga_chave, pessoas.carga_execucao, pessoas.carga_lote, pessoas.ac_catalogo, pessoas.ac_campo_carga, pessoas.ac_lista_papel,
  pessoas.ac_contato from public, anon, authenticated, service_role;

-- ===================== funções =====================
create function pessoas.carga_ligada(p_fonte text) returns boolean
language sql stable set search_path to '' as $f$
  select coalesce((select ligada and (ate is null or current_date <= ate) from pessoas.carga_chave where fonte = p_fonte), false);
$f$;

create function pessoas.carga_contagem() returns jsonb
language sql stable set search_path to '' as $f$
  select jsonb_build_object(
    'pessoas', (select count(*) from pessoas.pessoas),
    'identificadores', (select count(*) from pessoas.identificadores),
    'eventos', (select count(*) from pessoas.eventos),
    'revisao_pendente', (select count(*) from pessoas.revisao where status = 'pendente'),
    'ac_contato', (select count(*) from pessoas.ac_contato),
    'ac_pendente', (select count(*) from pessoas.ac_contato where pendente));
$f$;

-- abre (ou retoma) a execução de uma fonte/fase; devolve id e cursor de onde parou
create function pessoas.carga_abrir(p_fonte text, p_fase text, p_por text default null) returns jsonb
language plpgsql set search_path to '' as $f$
declare v pessoas.carga_execucao;
begin
  if not pessoas.carga_ligada(p_fonte) then raise exception 'carga desligada (pessoas.carga_chave)' using errcode = 'P0001'; end if;
  select * into v from pessoas.carga_execucao where fonte = p_fonte and fase = p_fase and status in ('rodando', 'parada') for update;
  if found then
    update pessoas.carga_execucao set status = 'rodando', atualizada_em = now(), erro = null where id = v.id;
    return jsonb_build_object('execucao', v.id, 'cursor', v.cursor, 'retomada', true, 'lotes', v.lotes);
  end if;
  insert into pessoas.carga_execucao (fonte, fase, por, contagem_antes)
  values (p_fonte, p_fase, left(p_por, 80), pessoas.carga_contagem())
  returning * into v;
  return jsonb_build_object('execucao', v.id, 'cursor', null, 'retomada', false, 'lotes', 0);
end $f$;

-- fecha: ok (terminou), parada (vai retomar) ou erro
create function pessoas.carga_fechar(p_execucao bigint, p_status text, p_erro text default null) returns jsonb
language plpgsql set search_path to '' as $f$
begin
  if p_status not in ('ok', 'parada', 'erro') then raise exception 'status inválido' using errcode = '22023'; end if;
  update pessoas.carga_execucao
     set status = p_status, erro = left(p_erro, 2000), atualizada_em = now(),
         terminada_em = case when p_status = 'ok' then now() end,
         contagem_depois = pessoas.carga_contagem()
   where id = p_execucao;
  return (select to_jsonb(e) - 'erro' from pessoas.carga_execucao e where e.id = p_execucao);
end $f$;

-- grava o catálogo (listas, tags, campos) que veio da API
create function pessoas.carga_ac_catalogo(p_itens jsonb) returns integer
language plpgsql set search_path to '' as $f$
declare n integer;
begin
  if not pessoas.carga_ligada('activecampaign') then raise exception 'carga desligada' using errcode = 'P0001'; end if;
  insert into pessoas.ac_catalogo (tipo, id, nome, extra)
  select x.tipo, (x.id)::integer, left(btrim(x.nome), 300), case when jsonb_typeof(x.extra) = 'object' then x.extra else '{}' end
    from jsonb_to_recordset(p_itens) as x(tipo text, id text, nome text, extra jsonb)
   where length(btrim(coalesce(x.nome, ''))) > 0 and x.tipo in ('lista', 'tag', 'campo') and x.id ~ '^[0-9]{1,9}$'
  on conflict (tipo, id) do update set nome = excluded.nome, extra = excluded.extra, visto_em = now()
   where (pessoas.ac_catalogo.nome, pessoas.ac_catalogo.extra) is distinct from (excluded.nome, excluded.extra);
  get diagnostics n = row_count;
  -- regra do Victor (14/10/2026): TODA lista de Sessão de Viabilidade do AC é pré-checkout da SV, inclusive as que forem
  -- criadas depois. Lista nova com esse nome entra sozinha em ac_lista_papel (as que já estão lá não mudam).
  insert into pessoas.ac_lista_papel (lista_id, papel, fonte)
  select c.id, 'sv_pre_checkout', 'regra: nome da lista contém Sessão de Viabilidade (Victor 14/10/2026)'
    from pessoas.ac_catalogo c
   where c.tipo = 'lista' and c.nome ~* 'sess(ã|a)o de viabilidade'
  on conflict (lista_id) do nothing;
  return n;
end $f$;

-- grava um lote de contatos no estágio (idempotente). p_lote = [{id, email, telefone, nome, cdate, udate, bounced_hard,
-- listas: [[lista, status, 'aaaa-mm-dd', saiu_pela_pessoa]], tags: [id...], campos: {PERSTAG: valor}}]
create function pessoas.carga_ac_estagio(p_execucao bigint, p_lote jsonb, p_cursor text) returns jsonb
language plpgsql set search_path to '' as $f$
declare v_t0 timestamptz := clock_timestamp(); v_lidas int; v_ins int; v_upd int; v_de text; v_sem_id int; v_desc_email int; v_validas int; v_iguais int;
begin
  if not pessoas.carga_ligada('activecampaign') then raise exception 'carga desligada' using errcode = 'P0001'; end if;
  if not exists (select 1 from pessoas.carga_execucao where id = p_execucao and fonte = 'activecampaign' and fase = 'estagio' and status = 'rodando') then
    raise exception 'execução % não está rodando (estagio/activecampaign)', p_execucao using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 2000 then
    raise exception 'lote inválido (array de até 2.000 contatos)' using errcode = '22023';
  end if;
  v_lidas := jsonb_array_length(p_lote);
  select cursor into v_de from pessoas.carga_execucao where id = p_execucao;

  -- Cada valor do lote é validado ANTES de chegar a um CHECK ou a um cast (achado do pentester, 14/10/2026): erro de CHECK
  -- grava a linha inteira no DETAIL do log, e erro de cast grava o valor na mensagem. O que não passa vira nulo/vazio e é
  -- contado em 'descartados' (só contagem). pg_input_is_valid (PG 16+) valida sem bloco de exceção.
  with e as (
    select el from jsonb_array_elements(p_lote) el where jsonb_typeof(el) = 'object'
  ), x0 as (
    select case when el->>'id' ~ '^[0-9]{1,9}$' then (el->>'id')::integer end id,
           case when jsonb_typeof(el->'email') = 'string' then pessoas.norm_email(left(el->>'email', 1000)) end email0,
           (jsonb_typeof(el->'email') = 'string' and btrim(el->>'email') <> '') tinha_email,
           case when jsonb_typeof(el->'telefone') = 'string' then pessoas.norm_telefone(left(el->>'telefone', 40)) end telefone,
           case when jsonb_typeof(el->'nome') = 'string' then nullif(left(btrim(el->>'nome'), 160), '') end nome,
           case when pg_input_is_valid(el->>'cdate', 'timestamptz') then (el->>'cdate')::timestamptz end cdate,
           case when pg_input_is_valid(el->>'udate', 'timestamptz') then (el->>'udate')::timestamptz end udate,
           case when el->>'bounced_hard' ~ '^[0-9]{1,4}$' then (el->>'bounced_hard')::smallint end bounced_hard,
           coalesce((select jsonb_agg(jsonb_build_array((l->>0)::integer, (l->>1)::integer,
                                                        case when pg_input_is_valid(l->>2, 'date') then l->>2 end,
                                                        coalesce(l->3 = 'true'::jsonb, false)))
                       from jsonb_array_elements(case when jsonb_typeof(el->'listas') = 'array' then el->'listas' else '[]' end) l
                      where jsonb_typeof(l) = 'array' and l->>0 ~ '^[0-9]{1,9}$' and l->>1 ~ '^[0-9]$'), '[]') listas,
           coalesce(array(select v::integer
                            from jsonb_array_elements_text(case when jsonb_typeof(el->'tags') = 'array' then el->'tags' else '[]' end) v
                           where v ~ '^[0-9]{1,9}$'), '{}') tags,
           case when jsonb_typeof(el->'campos') = 'object' then el->'campos' else '{}' end campos
      from e
  ), x as (
    select distinct on (id) id, case when length(email0) <= 320 then email0 end email,
           tinha_email and (email0 is null or length(email0) > 320) email_descartado,
           telefone, nome, cdate, udate, bounced_hard, listas, tags, campos
      from x0 where id is not null order by id
  ), y as (
    select x.*,
           exists (select 1 from jsonb_array_elements(x.listas) l where l->>1 = '2' and l->3 = 'true'::jsonb) descadastrou,
           exists (select 1 from jsonb_array_elements(x.listas) l where l->>1 = '2' and l->3 = 'false'::jsonb) desativado_empresa
      from x
  ), up as (
    insert into pessoas.ac_contato as c (contact_id, email, telefone, nome, criado_em_ac, atualizado_em_ac, bounced_hard, listas, tags,
                                         campos, descadastrou, desativado_empresa)
    select id, email, telefone, nome, cdate, udate, bounced_hard, listas, tags, campos, descadastrou, desativado_empresa from y
    on conflict (contact_id) do update
       set email = excluded.email, telefone = excluded.telefone, nome = excluded.nome, criado_em_ac = excluded.criado_em_ac,
           atualizado_em_ac = excluded.atualizado_em_ac, bounced_hard = excluded.bounced_hard, listas = excluded.listas,
           tags = excluded.tags, campos = excluded.campos, descadastrou = excluded.descadastrou,
           desativado_empresa = excluded.desativado_empresa, pendente = true, atualizado_em = now()
     where (c.email, c.telefone, c.nome, c.criado_em_ac, c.bounced_hard, c.listas, c.tags, c.campos)
           is distinct from (excluded.email, excluded.telefone, excluded.nome, excluded.criado_em_ac, excluded.bounced_hard,
                             excluded.listas, excluded.tags, excluded.campos)
    returning (xmax = 0) inserida
  )
  select count(*) filter (where inserida), count(*) filter (where not inserida) into v_ins, v_upd from up;
  -- contagem do que foi descartado (refaz só a parte barata da leitura; nunca devolve valor)
  select count(distinct el->>'id') filter (where el->>'id' ~ '^[0-9]{1,9}$'),
         count(*) filter (where el->>'id' is null or el->>'id' !~ '^[0-9]{1,9}$'),
         count(*) filter (where jsonb_typeof(el->'email') = 'string' and btrim(el->>'email') <> ''
                            and (pessoas.norm_email(left(el->>'email', 1000)) is null or length(pessoas.norm_email(left(el->>'email', 1000))) > 320))
    into v_validas, v_sem_id, v_desc_email
    from jsonb_array_elements(p_lote) el where jsonb_typeof(el) = 'object';
  v_iguais := v_validas - v_ins - v_upd;

  insert into pessoas.carga_lote (execucao_id, cursor_de, cursor_ate, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, v_de, p_cursor, v_lidas, v_ins, v_upd, v_iguais,
          jsonb_build_object('descartados_sem_id', v_sem_id, 'emails_descartados', v_desc_email, 'repetidos_ou_invalidos', v_lidas - v_validas),
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
  update pessoas.carga_execucao
     set cursor = p_cursor, lotes = lotes + 1, lidas = lidas + v_lidas, inseridas = inseridas + v_ins,
         atualizadas = atualizadas + v_upd, iguais = iguais + v_iguais, atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', v_lidas, 'inseridas', v_ins, 'atualizadas', v_upd, 'iguais', v_iguais,
                            'descartados_sem_id', v_sem_id, 'emails_descartados', v_desc_email, 'repetidos_ou_invalidos', v_lidas - v_validas,
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;

-- casamento SÓ por e-mail (passo 1 do pessoas.resolver, mesmas expressões de índice); cria a pessoa se ninguém casar
create function pessoas.casar_email(p_nome text, p_email text, p_telefone text, p_origem text) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_email text := pessoas.norm_email(p_email);
  v_tel   text := pessoas.norm_telefone(p_telefone);
  v_nome  text := nullif(left(btrim(coalesce(p_nome, '')), 160), '');
  v_lead uuid; v_aluno uuid; v_comprador uuid; v_pa uuid; v_pc uuid; v_pessoa uuid; v_x uuid;
  v_cands uuid[] := '{}'; v_nova boolean := false; v_motivo text;
begin
  if v_email is null then return jsonb_build_object('pessoa_id', null, 'nova', false, 'motivo', 'sem_email'); end if;
  perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || v_email));   -- mesma chave do pessoas.resolver

  select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
  select a.id into v_aluno from public.thb_alunos a where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
  select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;
  v_pa := (select pessoas.atual(p.id) from pessoas.pessoas p where v_aluno is not null and p.aluno_id = v_aluno);
  v_pc := (select pessoas.atual(p.id) from pessoas.pessoas p where v_comprador is not null and p.comprador_id = v_comprador);
  v_pessoa := coalesce(v_pa, v_pc, v_lead);
  v_cands := array(select distinct x from unnest(array[v_pa, v_pc, v_lead]) x where x is not null and x <> v_pessoa);
  if cardinality(v_cands) > 0 then v_motivo := 'email_conflito'; end if;

  if v_pessoa is null then
    if v_aluno is not null then v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
    elsif v_comprador is not null then v_pessoa := pessoas.pessoa_do_comprador(v_comprador); end if;
  end if;

  -- o lead que virou aluno/comprador: liga a referência que ainda não tem pessoa (igual ao pessoas.resolver)
  if v_pessoa is not null and v_motivo is null then
    if v_aluno is not null and v_pa is null then
      select p.aluno_id into v_x from pessoas.pessoas p where p.id = any(pessoas.grupo(v_pessoa)) and p.aluno_id is not null limit 1;
      if v_x is null then
        update pessoas.pessoas set aluno_id = v_aluno, atualizado_em = now() where id = v_pessoa;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.thb_alunos', v_aluno::text);
      elsif v_x <> v_aluno then
        v_cands := v_cands || pessoas.pessoa_do_aluno(v_aluno); v_motivo := 'email_conflito';
      end if;
    end if;
    if v_comprador is not null and v_pc is null and v_motivo is null then
      v_x := null;
      select p.comprador_id into v_x from pessoas.pessoas p where p.id = any(pessoas.grupo(v_pessoa)) and p.comprador_id is not null limit 1;
      if v_x is null then
        update pessoas.pessoas set comprador_id = v_comprador, atualizado_em = now() where id = v_pessoa;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.compradores', v_comprador::text);
      elsif v_x <> v_comprador then
        v_cands := v_cands || pessoas.pessoa_do_comprador(v_comprador); v_motivo := 'email_conflito';
      end if;
    end if;
  end if;

  if v_pessoa is null then
    insert into pessoas.pessoas (nome) values (case when length(coalesce(v_nome, '')) >= 2 then v_nome end) returning id into v_pessoa;
    v_nova := true;
  else
    update pessoas.pessoas set nome = v_nome, atualizado_em = now()
     where id = v_pessoa and nome is null and aluno_id is null and comprador_id is null and length(coalesce(v_nome, '')) >= 2;
  end if;

  v_pessoa := pessoas.atual(v_pessoa);
  v_cands := array(select distinct s from unnest(v_cands) s where s is not null and pessoas.atual(s) <> v_pessoa);
  if cardinality(v_cands) > 0 then
    insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
    values (v_pessoa, 'email_conflito', v_cands, jsonb_build_object('casou_por', 'email', 'carga', p_origem));
  else
    v_motivo := null;
  end if;

  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, p_origem);
  perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), p_origem);
  return jsonb_build_object('pessoa_id', v_pessoa, 'nova', v_nova, 'motivo', v_motivo);
end $f$;

-- passa os próximos p_limite contatos pendentes do estágio para pessoas (pessoa + identificadores + linha do tempo)
create function pessoas.carga_ac_pessoas(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); r record; v jsonb; v_p uuid;
  n_lidas int := 0; n_novas int := 0; n_casadas int := 0; n_sem int := 0; n_rev int := 0; n_ev int := 0; n_x int;
  v_de text; v_ate text;
begin
  if not pessoas.carga_ligada('activecampaign') then raise exception 'carga desligada' using errcode = 'P0001'; end if;
  if not exists (select 1 from pessoas.carga_execucao where id = p_execucao and fonte = 'activecampaign' and fase = 'pessoas' and status = 'rodando') then
    raise exception 'execução % não está rodando (pessoas/activecampaign)', p_execucao using errcode = 'P0001';
  end if;
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;

  for r in select * from pessoas.ac_contato where pendente order by contact_id limit p_limite for update skip locked loop
    n_lidas := n_lidas + 1;
    v_de := coalesce(v_de, r.contact_id::text); v_ate := r.contact_id::text;
    if r.email is null then
      update pessoas.ac_contato set pendente = false, processado_em = now(), nota = 'sem_email' where contact_id = r.contact_id;
      n_sem := n_sem + 1;
      continue;
    end if;
    v := pessoas.casar_email(r.nome, r.email, r.telefone, 'activecampaign');
    v_p := (v->>'pessoa_id')::uuid;
    if (v->>'nova')::boolean then n_novas := n_novas + 1; else n_casadas := n_casadas + 1; end if;
    if v->>'motivo' is not null then n_rev := n_rev + 1; end if;

    insert into pessoas.eventos (pessoa_id, tipo, fonte, fonte_tabela, fonte_id, quando)
    values (v_p, 'lead', 'activecampaign', 'pessoas.ac_contato', r.contact_id::text, coalesce(r.criado_em_ac, now()))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_ev := n_ev + n_x;

    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando, detalhe)
    select v_p, 'pre_checkout', 'activecampaign', lp.evento_id, 'pessoas.ac_contato', r.contact_id || ':' || lp.lista_id,
           coalesce(case when pg_input_is_valid(l->>2, 'date') then ((l->>2)::date)::timestamp at time zone 'America/Sao_Paulo' end, r.criado_em_ac, now()),
           jsonb_build_object('lista_id', lp.lista_id, 'papel', lp.papel, 'status', (l->>1)::int)
      from jsonb_array_elements(r.listas) l
      join pessoas.ac_lista_papel lp on l->>0 ~ '^[0-9]{1,9}$' and lp.lista_id = (l->>0)::int
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_ev := n_ev + n_x;

    update pessoas.ac_contato set pessoa_id = v_p, pessoa_nova = coalesce(pessoa_nova, (v->>'nova')::boolean), pendente = false,
           processado_em = now(), nota = null where contact_id = r.contact_id;
  end loop;

  insert into pessoas.carga_lote (execucao_id, cursor_de, cursor_ate, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, v_de, v_ate, n_lidas, n_novas, n_casadas, n_sem,
          jsonb_build_object('pessoas_novas', n_novas, 'casadas', n_casadas, 'sem_email', n_sem, 'revisao', n_rev, 'eventos', n_ev),
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
  update pessoas.carga_execucao
     set cursor = coalesce(v_ate, cursor), lotes = lotes + 1, lidas = lidas + n_lidas, inseridas = inseridas + n_novas,
         atualizadas = atualizadas + n_casadas, iguais = iguais + n_sem, atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', n_lidas, 'pessoas_novas', n_novas, 'casadas', n_casadas, 'sem_email', n_sem,
                            'revisao', n_rev, 'eventos', n_ev, 'restam', (select count(*) from pessoas.ac_contato where pendente),
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;


-- ensaio com dado REAL sem gravar e sem erro no log: roda estágio (2×) e pessoas num bloco interno que sempre volta atrás
-- (subtransação desfeita, o erro é capturado aqui dentro) e devolve só contagens. O lote chega como parâmetro ligado
-- ($1 da Management API), então não vai para o texto do SQL nem para o log. Achado do pentester de 14/10/2026.
create function pessoas.carga_ensaio(p_lote jsonb) returns jsonb
language plpgsql set search_path to '' as $f$
declare v_saida jsonb; v_e bigint; v_p bigint; v_antes jsonb; r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
begin
  if jsonb_typeof(p_lote) <> 'array' or jsonb_array_length(p_lote) > 500 then
    raise exception 'ensaio: lote de até 500 contatos' using errcode = '22023';
  end if;
  if exists (select 1 from pessoas.carga_execucao where fonte = 'activecampaign' and status = 'rodando') then
    raise exception 'ensaio: há carga rodando; esperar ou parar antes' using errcode = 'P0001';
  end if;
  v_antes := pessoas.carga_contagem();
  begin
    v_e := (pessoas.carga_abrir('activecampaign', 'estagio', 'ensaio')->>'execucao')::bigint;
    r1 := pessoas.carga_ac_estagio(v_e, p_lote, 'ensaio');
    r2 := pessoas.carga_ac_estagio(v_e, p_lote, 'ensaio');
    perform pessoas.carga_fechar(v_e, 'parada');
    v_p := (pessoas.carga_abrir('activecampaign', 'pessoas', 'ensaio')->>'execucao')::bigint;
    r3 := pessoas.carga_ac_pessoas(v_p, 2000);
    update pessoas.ac_contato set pendente = true where contact_id in (select (x->>'id')::int from jsonb_array_elements(p_lote) x where x->>'id' ~ '^[0-9]{1,9}$');
    r4 := pessoas.carga_ac_pessoas(v_p, 2000);
    v_saida := jsonb_build_object(
      'antes', v_antes, 'estagio_1a', r1, 'estagio_2a_igual', r2, 'pessoas', r3 - 'restam', 'reprocessar', r4 - 'restam',
      'eventos_por_tipo', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato' group by 1) x),
      'descadastrou', (select count(*) from pessoas.ac_contato where descadastrou),
      'desativado_empresa', (select count(*) from pessoas.ac_contato where desativado_empresa),
      'depois_dentro', pessoas.carga_contagem());
    raise exception using errcode = 'P0E01', message = 'ensaio: desfazer';   -- capturado logo abaixo: nada fica gravado
  exception when sqlstate 'P0E01' then
    null;
  end;
  return v_saida || jsonb_build_object('depois_fora', pessoas.carga_contagem());
end $f$;

revoke all on function pessoas.carga_ligada(text), pessoas.carga_contagem(), pessoas.carga_abrir(text, text, text),
  pessoas.carga_fechar(bigint, text, text), pessoas.carga_ac_catalogo(jsonb), pessoas.carga_ac_estagio(bigint, jsonb, text),
  pessoas.casar_email(text, text, text, text), pessoas.carga_ac_pessoas(bigint, integer), pessoas.carga_ensaio(jsonb)
  from public, anon, authenticated, service_role;

do $g$
begin
  if exists (select 1 from pg_proc p where p.pronamespace = 'pessoas'::regnamespace
               and p.proname in ('carga_ligada', 'carga_contagem', 'carga_abrir', 'carga_fechar', 'carga_ac_catalogo', 'carga_ac_estagio', 'casar_email', 'carga_ac_pessoas', 'carga_ensaio')
               and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '20261014170000: função de carga ficou executável por anon/authenticated.';
  end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'pessoas'::regnamespace
               and c.relname in ('carga_chave', 'carga_execucao', 'carga_lote', 'ac_catalogo', 'ac_campo_carga', 'ac_lista_papel', 'ac_contato')
               and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select')
                    or has_table_privilege('service_role', c.oid, 'select'))) then
    raise exception '20261014170000: tabela da carga ficou legível por anon/authenticated/service_role.';
  end if;
end
$g$;

-- ===== testes =====
create temp table _z_lote as
select jsonb_agg(jsonb_build_object(
         'id', 900000000 + g,
         'email', case when g = 5 then null else 'ensaio-' || g || '@exemplo.invalid' end,
         'telefone', case when g % 2 = 0 then '1199' || lpad(g::text, 7, '0') end,
         'nome', 'Pessoa Ensaio ' || g,
         'cdate', '2026-01-0' || (1 + g % 9) || 'T10:00:00-03:00',
         'listas', case when g = 1 then '[[412, 1, "2026-03-10", false]]'::jsonb
                        when g = 2 then '[[412, 2, "2026-03-11", true]]'::jsonb
                        when g = 3 then '[[100, 2, "2025-01-01", false]]'::jsonb else '[]'::jsonb end,
         'tags', '[1, 2]'::jsonb,
         'campos', case when g = 1 then '{"PESQUISAVALOR": "x"}'::jsonb else '{}'::jsonb end)) j
  from generate_series(1, 10) g;
-- contato 11: mesmo e-mail de alguém que já está em pessoas (casa, não cria)
update pg_temp._z_lote set j = j || jsonb_build_array(jsonb_build_object('id', 900000011, 'nome', 'Ensaio Existente',
  'email', (select i.chave from pessoas.identificadores i join pessoas.pessoas p on p.id = i.pessoa_id
             where i.tipo = 'email' and p.situacao = 'ativa' and not p.teste order by i.id limit 1)));
create temp table _z_e as select (pessoas.carga_abrir('activecampaign', 'estagio', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '10 estágio 1ª passada (11)', pessoas.carga_ac_estagio((select id from pg_temp._z_e), (select j from pg_temp._z_lote), '900000011')::text;
insert into pg_temp._z_out(passo, linha) select '11 estágio 2ª passada (11 iguais)', pessoas.carga_ac_estagio((select id from pg_temp._z_e), (select j from pg_temp._z_lote), '900000011')::text;
insert into pg_temp._z_out(passo, linha) select '12 descadastrou (esperado 1: contato 2) / desativado_empresa (esperado 1: contato 3)', count(*) filter (where descadastrou) || ' / ' || count(*) filter (where desativado_empresa) from pessoas.ac_contato;
insert into pg_temp._z_out(passo, linha) select '14 lote hostil (esperado: sem erro; 2 sem id, 1 e-mail longo + 1 inválido descartados)', pessoas.carga_ac_estagio((select id from pg_temp._z_e), jsonb_build_array(
  jsonb_build_object('id', 900000101, 'email', repeat('a', 330) || '@exemplo.invalid', 'nome', repeat('n', 400), 'telefone', repeat('9', 60)),
  jsonb_build_object('id', 900000102, 'email', 'nao-e-email', 'cdate', '2026-13-45', 'udate', 'ontem', 'bounced_hard', 'x',
                     'listas', '[[412, 1, "2026-02-30", "talvez"], ["x", 2], 5, [607, 99, null, true]]'::jsonb, 'tags', '[1, "a", 99999999999]'::jsonb, 'campos', '[1]'::jsonb),
  jsonb_build_object('id', 'abc', 'email', 'ensaio-sem-id@exemplo.invalid'),
  jsonb_build_object('email', 'ensaio-sem-id2@exemplo.invalid'),
  '"nem objeto"'::jsonb,
  jsonb_build_object('id', 900000101, 'email', 'ensaio-dup@exemplo.invalid')), 'hostil')::text;
insert into pg_temp._z_out(passo, linha) select '15 lote hostil gravado: e-mail nulo / nome <= 160 / listas válidas / campos {}', (select (email is null)::text || ' / ' || (length(coalesce(nome,'')) <= 160)::text from pessoas.ac_contato where contact_id = 900000101) || ' / ' || (select listas::text || ' / ' || campos::text || ' / ' || tags::text from pessoas.ac_contato where contact_id = 900000102);
delete from pessoas.ac_contato where contact_id in (900000101, 900000102);
create temp table _z_cat as select pessoas.carga_ac_catalogo('[{"tipo":"lista","id":999001,"nome":"Sessão de Viabilidade ENSAIO"},{"tipo":"lista","id":999002,"nome":"Outra lista"},{"tipo":"lista","id":412,"nome":"Sessão de Viabilidade"}]'::jsonb) n;
insert into pg_temp._z_out(passo, linha) select '16 catálogo: lista nova de SV entra como pré-checkout sozinha (esperado 999001 = sv_pre_checkout, 999002 = nenhum, 15 listas)',
  (select n from pg_temp._z_cat)::text || ' gravados / 999001: ' || coalesce((select papel from pessoas.ac_lista_papel where lista_id = 999001), 'nenhum')
  || ' / 999002: ' || coalesce((select papel from pessoas.ac_lista_papel where lista_id = 999002), 'nenhum')
  || ' / listas com papel: ' || (select count(*) from pessoas.ac_lista_papel);
insert into pg_temp._z_out(passo, linha) select '13 retomada: carga_abrir de novo devolve o cursor', pessoas.carga_abrir('activecampaign', 'estagio', 'ensaio')::text;
select pessoas.carga_fechar((select id from pg_temp._z_e), 'ok');
create temp table _z_p as select (pessoas.carga_abrir('activecampaign', 'pessoas', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '20 pessoas (esperado: 9 novas, 1 casada, 1 sem e-mail)', pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 1000)::text;
update pessoas.ac_contato set pendente = true;
insert into pg_temp._z_out(passo, linha) select '21 reprocessar (0 novas, 0 eventos)', pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 1000)::text;
insert into pg_temp._z_out(passo, linha) select '22 eventos (esperado lead 10, pre_checkout 2)', string_agg(tipo || ' ' || n, ', ') from (select tipo, count(*) n from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato' group by 1 order by 1) x;
insert into pg_temp._z_out(passo, linha) select '23 identificadores da carga (e-mail 9 + telefone 5)', string_agg(tipo || ' ' || n, ', ') from (select i.tipo, count(*) n from pessoas.identificadores i where i.chave like 'ensaio-%' or (i.tipo = 'telefone' and i.chave like '11%' and i.pessoa_id in (select pessoa_id from pessoas.ac_contato)) group by 1) x;
insert into pg_temp._z_out(passo, linha) select '24 contato 11 casou com a pessoa que já existia (nova = false)', (select (not pessoa_nova)::text from pessoas.ac_contato where contact_id = 900000011);
update pessoas.carga_chave set ligada = true;
select pessoas.carga_fechar((select id from pg_temp._z_p), 'ok');
create temp table _z_c as select pessoas.carga_contagem() c;
create temp table _z_en as select pessoas.carga_ensaio((select j from pg_temp._z_lote) || jsonb_build_array(jsonb_build_object('id', 900000099, 'email', 'ensaio-99@exemplo.invalid', 'listas', '[[607, 1, "2026-09-01", false]]'::jsonb))) r;
insert into pg_temp._z_out(passo, linha) select '29 carga_ensaio: estágio 2ª passada / pessoas / reprocessar', (select (r->'estagio_2a_igual'->>'iguais') || ' iguais / ' || (r->'pessoas'->>'pessoas_novas') || ' novas / ' || (r->'reprocessar'->>'pessoas_novas') || ' novas' from pg_temp._z_en);
insert into pg_temp._z_out(passo, linha) select '30 carga_ensaio desfez tudo (contagem igual antes e depois)', ((select r->'depois_fora' from pg_temp._z_en) = (select c from pg_temp._z_c))::text || ' (dentro: ' || (select r->'depois_dentro'->>'ac_contato' from pg_temp._z_en) || ' no estágio)';
do $t$ begin
  begin perform pessoas.carga_ensaio((select jsonb_agg(jsonb_build_object('id', g)) from generate_series(1, 501) g));
    insert into pg_temp._z_out(passo, linha) values ('32 lote de 501 no ensaio', 'ACEITOU (ERRO)');
  exception when invalid_parameter_value then insert into pg_temp._z_out(passo, linha) values ('32 lote de 501 no ensaio', 'recusado (ok)'); end;
end $t$;
update pessoas.carga_chave set ate = current_date - 1 where fonte = 'activecampaign';
insert into pg_temp._z_out(passo, linha) select '33 data de fim vencida desliga sozinha', (not pessoas.carga_ligada('activecampaign'))::text;
update pessoas.carga_chave set ate = null where fonte = 'activecampaign';
update pessoas.carga_chave set ligada = false;
do $t$ begin
  begin perform pessoas.carga_ac_estagio((select id from pg_temp._z_e), '[]'::jsonb, 'x');
    insert into pg_temp._z_out(passo, linha) values ('25 chave desligada', 'RODOU (ERRO)');
  exception when raise_exception then insert into pg_temp._z_out(passo, linha) values ('25 chave desligada', 'recusou (ok)'); end;
end $t$;
insert into pg_temp._z_out(passo, linha) select '26 funções executáveis por anon/authenticated', count(*)::text from pg_proc p where p.pronamespace = 'pessoas'::regnamespace and (p.proname like 'carga%' or p.proname = 'casar_email') and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
insert into pg_temp._z_out(passo, linha) select '27 tabelas novas legíveis por anon/authenticated', count(*)::text from pg_class c where c.relnamespace = 'pessoas'::regnamespace and c.relname in ('carga_chave','carga_execucao','carga_lote','ac_catalogo','ac_campo_carga','ac_lista_papel','ac_contato') and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'));
-- ===== reversão =====
-- Reversão de 20261014170000 (estrutura da carga do ActiveCampaign).
-- ANTES de rodar, se a carga já tiver rodado, decidir o que fazer com o que ela gravou FORA do estágio (a reversão NÃO
-- apaga pessoa: pessoa nunca se apaga, regra I-03). Para medir:
--   select count(*) from pessoas.ac_contato where pessoa_nova;                       -- pessoas criadas pela carga
--   select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato';  -- linhas do tempo da carga
--   select count(*) from pessoas.identificadores where origem = 'activecampaign';    -- (inclui as do webhook de antes)
-- Os eventos da carga apontam para pessoas.ac_contato por texto (fonte_tabela/fonte_id), sem FK: a reversão não os toca.
set local lock_timeout = '5s';
drop function if exists pessoas.carga_ac_pessoas(bigint, integer);
drop function if exists pessoas.casar_email(text, text, text, text);
drop function if exists pessoas.carga_ac_estagio(bigint, jsonb, text);
drop function if exists pessoas.carga_ac_catalogo(jsonb);
drop function if exists pessoas.carga_fechar(bigint, text, text);
drop function if exists pessoas.carga_abrir(text, text, text);
drop function if exists pessoas.carga_contagem();
drop function if exists pessoas.carga_ligada(text);
drop table if exists pessoas.ac_contato;
drop table if exists pessoas.ac_lista_papel;
drop table if exists pessoas.ac_campo_carga;
drop table if exists pessoas.ac_catalogo;
drop table if exists pessoas.carga_lote;
drop table if exists pessoas.carga_execucao;
drop table if exists pessoas.carga_chave;

insert into pg_temp._z_out(passo, linha) select '28 schema fin intocado (chave, captacao_inicio)', count(*)::text from information_schema.columns where table_schema = 'fin' and table_name = 'eventos' and column_name in ('chave', 'captacao_inicio');
insert into pg_temp._z_out(passo, linha) select '90 depois da reversão: objetos da carga que sobram', count(*)::text from pg_class where relnamespace = 'pessoas'::regnamespace and relname in ('carga_chave','carga_execucao','carga_lote','ac_catalogo','ac_campo_carga','ac_lista_papel','ac_contato');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
