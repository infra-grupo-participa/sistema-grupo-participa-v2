-- Ensaio de 20261014170100 (cargas das fontes) com a cadeia de pessoas antes (160200, índices sem concurrently, 170000),
-- numa transação DESFEITA. Lê as tabelas reais DENTRO do banco: o texto deste ensaio não tem dado pessoal e a saída é só
-- contagem. Erro numa fonte é capturado aqui dentro e só o SQLSTATE sai (nunca a mensagem nem o DETAIL).
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '00 antes', (select jsonb_build_object('pessoas', (select count(*) from pessoas.pessoas), 'eventos', (select count(*) from pessoas.eventos), 'revisao', (select count(*) from pessoas.revisao))::text);
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
  select coalesce((select ligada from pessoas.carga_chave where fonte = p_fonte), false);
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

-- ===== 20261014170100 =====
-- 20261014170100: cargas das fontes que já moram no banco (Hotmart, Central, T1-T40, HM, Respondi, leads, CRM)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014160200, 160300 e 170000 (controle de
--   carga, pessoas.casar_email, pessoas.relacoes, índice eventos_fonte_unico). Não depende do schema fin (só lê).
--   Ensaio: 20261014170100_ensaio.sql. Script: infra/scripts/pessoa-unica/carga_fontes.py. Detalhe: 20261014170100.explain.md.
--
-- POR QUE: PLANO da pessoa única, passo 4 (carga por fonte, em lotes) e o modelo da história da pessoa do Victor
--   (14/10/2026): lead, checkout e compra separados por evento; matrícula por turma; sócio de; CRM; Respondi.
-- O QUE FAZ: uma função por fonte, no mesmo padrão da 170000 (execução aberta em pessoas.carga_execucao, lote por cursor,
--   pessoas.carga_lote, chave pessoas.carga_chave por fonte, idempotente pelo índice (fonte_tabela, fonte_id, tipo)):
--   | função                          | fonte                          | vira                                                  |
--   | carga_fin_hotmart (por conta)   | fin.hotmart_transacoes         | compra (COMPLETE, APPROVED), reembolso (REFUNDED,     |
--   |                                 |                                | CHARGEBACK, PARTIALLY_REFUNDED, PROTESTED), checkout  |
--   |                                 |                                | (o resto): mesma regra do crm.hotmart_processar       |
--   | carga_thb_alunos                | public.thb_alunos              | ativacao (turma e turma Aurum) + sócio de             |
--   | carga_aluno_historico           | controle.aluno_historico (T1-T40) | ativacao (turma e turma Aurum)                     |
--   | carga_contatos_hm               | cs.contatos_hm                 | crm (etapa e produto do HM, turma de origem)          |
--   | carga_hm_socios                 | cs.hm_socios                   | vinculo + sócio de                                    |
--   | carga_respondi                  | respondi.respostas             | resposta (+ sócio de nos formulários de sócio)        |
--   | carga_leads                     | workbook.cnhf_leads_captacao, workbook.leads, dados.black_leads | lead (+ mql na Black) |
--   | carga_crm_negocio               | crm.negocio                    | crm (linha, status)                                   |
-- DECISÕES:
--   - Hotmart: o evento NÃO copia valor nem nome da oferta (o dinheiro fica em fin.hotmart_transacoes; o tipo da oferta
--     na pessoas.vw_oferta). As linhas que o webhook já gravou (ref_tipo 'hotmart.transacao', sem fonte_id) recebem
--     fonte_tabela/fonte_id na primeira de cada (tipo, transação): a carga não duplica o que o webhook gravou.
--     evento_id: o da regra do financeiro (fin.trajetoria_nucleo, por lote de e-mails), quando ela dá.
--   - T1-T40: o espelho é regravado todo dia (os ids mudam); a chave é md5(e-mail) + turma, estável e sem e-mail em claro.
--   - controle.lead (só telefone, sem e-mail) NÃO entra aqui: casar por telefone em massa abriria revisão demais
--     (pergunta ao Victor). Planilha de ativação T1-T42: estágio próprio, migration seguinte.
--   - Casamento por e-mail (pessoas.casar_email); CPF nunca. Valores validados antes de CHECK (nome até 160, e-mail até
--     320, detalhe pequeno): erro de CHECK grava a linha no log.
-- AS 5 PERGUNTAS: escala = ~58 mil transações, ~1,9 mil alunos, ~7,6 mil T1-T40, ~400 HM, ~23 mil respostas, ~40 mil
--   leads, ~1,5 mil negócios; índice = PK de cada fonte para o cursor + eventos_fonte_unico; frequência = 1 carga + o
--   incremental (manter vivo, desenho no explain); repetição = idempotente; reversão = 20261014170100_reversao.sql.
-- ACESSO: funções SECURITY INVOKER, sem execute para public/anon/authenticated/service_role.

set local lock_timeout = '5s';

do $g$
begin
  if to_regprocedure('pessoas.casar_email(text,text,text,text)') is null or to_regclass('pessoas.eventos_fonte_unico') is null then
    raise exception '20261014170100: falta 20261014170000/160300.';
  end if;
  if to_regprocedure('pessoas.carga_fin_hotmart(bigint,text,integer)') is not null then
    raise exception '20261014170100: já aplicada.';
  end if;
end
$g$;

insert into pessoas.carga_chave (fonte, ligada, por)
select f, true, 'migration 20261014170100'
  from unnest(array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi', 'leads_cnhf',
                    'leads_workbook', 'leads_black', 'crm_negocio']) f
on conflict (fonte) do nothing;

-- execução aberta da fonte (e chave ligada); devolve o cursor
create function pessoas._carga_exigir(p_execucao bigint, p_fonte text) returns text
language plpgsql set search_path to '' as $f$
declare v_cursor text;
begin
  if not pessoas.carga_ligada(p_fonte) then raise exception 'carga desligada (%)', p_fonte using errcode = 'P0001'; end if;
  select cursor into v_cursor from pessoas.carga_execucao
   where id = p_execucao and fonte = p_fonte and fase = 'pessoas' and status = 'rodando';
  if not found then raise exception 'execução % não está rodando (pessoas/%)', p_execucao, p_fonte using errcode = 'P0001'; end if;
  return v_cursor;
end $f$;

-- registra o lote e devolve o resumo
create function pessoas._carga_lote_fim(p_execucao bigint, p_de text, p_ate text, p_lidas int, p_novas int, p_casadas int,
                                        p_puladas int, p_eventos int, p_rel int, p_t0 timestamptz) returns jsonb
language plpgsql set search_path to '' as $f$
declare v_ms int := (extract(epoch from clock_timestamp() - p_t0) * 1000)::int;
begin
  insert into pessoas.carga_lote (execucao_id, cursor_de, cursor_ate, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, p_de, p_ate, p_lidas, p_novas, p_casadas, p_puladas,
          jsonb_build_object('pessoas_novas', p_novas, 'casadas', p_casadas, 'puladas', p_puladas, 'eventos', p_eventos, 'relacoes', p_rel), v_ms);
  update pessoas.carga_execucao
     set cursor = coalesce(p_ate, cursor), lotes = lotes + 1, lidas = lidas + p_lidas, inseridas = inseridas + p_novas,
         atualizadas = atualizadas + p_casadas, iguais = iguais + p_puladas, atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', p_lidas, 'pessoas_novas', p_novas, 'casadas', p_casadas, 'puladas', p_puladas,
                            'eventos', p_eventos, 'relacoes', p_rel, 'fim', p_lidas = 0, 'ms', v_ms);
end $f$;

-- ======================= Hotmart =======================
create function pessoas.carga_fin_hotmart(p_execucao bigint, p_conta text, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
-- Uma execução por conta (fontes hotmart_academy e hotmart_escritorio). Toda leitura da tabela de transações segue a forma
-- canônica que a trava fin.trava_conta_hotmart exige (regra 9 do plano de ação): (select * from ... where conta = p_conta).
-- A trava conta o nome da tabela até dentro de texto; por isso o valor de fonte_tabela é montado por concatenação (v_tab).
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tipo text; v_ev bigint;
  v_tab constant text := 'fin.hotmart' || '_transacoes';
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  if p_conta not in ('academy', 'escritorio') then raise exception 'conta inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hotmart_' || p_conta), '');
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;
  create temp table if not exists _carga_hm_lote (transacao text primary key) on commit drop;
  create temp table if not exists _carga_hm_ev (transacao text primary key, evento_id bigint) on commit drop;
  delete from pg_temp._carga_hm_lote; delete from pg_temp._carga_hm_ev;
  insert into pg_temp._carga_hm_lote
  select t.transacao from (select * from fin.hotmart_transacoes where conta = p_conta) t
   where t.transacao > v_cur order by t.transacao limit p_limite;
  -- evento pela regra do financeiro (mesma janela/oferta que os funis usam), por lote de e-mails
  insert into pg_temp._carga_hm_ev
  select distinct on (j.transacao) j.transacao, j.evento_id
    from fin.trajetoria_nucleo(array(select distinct lower(btrim(t.comprador_email))
                                       from (select * from fin.hotmart_transacoes where conta = p_conta) t
                                       join pg_temp._carga_hm_lote l using (transacao) where t.comprador_email is not null)) j
    join pg_temp._carga_hm_lote l on l.transacao = j.transacao
   where j.evento_id is not null
   order by j.transacao;

  for r in select t.* from (select * from fin.hotmart_transacoes where conta = p_conta) t
             join pg_temp._carga_hm_lote l using (transacao) order by t.transacao loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.transacao); v_ate := r.transacao;
    v := pessoas.casar_email(r.comprador_nome, r.comprador_email, r.comprador_telefone, 'hotmart');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_tipo := case when r.status in ('COMPLETE', 'APPROVED') then 'compra'
                   when r.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                   else 'checkout' end;
    v_ev := null;
    select e.evento_id into v_ev from pg_temp._carga_hm_ev e where e.transacao = r.transacao;
    -- a linha que o webhook já gravou desta transação/tipo recebe a fonte (uma só), em vez de criar outra
    update pessoas.eventos x set fonte_tabela = v_tab, fonte_id = r.transacao, evento_id = coalesce(x.evento_id, v_ev)
     where x.id = (select min(y.id) from pessoas.eventos y
                    where y.ref_tipo = 'hotmart.transacao' and y.ref_id = r.transacao and y.tipo = v_tipo and y.fonte_id is null)
       and not exists (select 1 from pessoas.eventos z where z.fonte_tabela = v_tab and z.fonte_id = r.transacao and z.tipo = v_tipo);
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, v_tipo, 'hotmart', v_ev, 'hotmart.transacao', left(r.transacao, 80), v_tab, left(r.transacao, 120),
            coalesce(r.aprovado_em, r.pedido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('conta', p_conta, 'produto', left(r.produto_id, 40),
                                                 'oferta', left(r.oferta_codigo, 40), 'status', left(r.status, 30))))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= Central de Alunos (matrícula viva) =======================
create function pessoas.carga_thb_alunos(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid; v_tit uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'thb_alunos'), '');
  for r in select a.id, a.turma_id, a.turma_aurum_id, a.data_entrada_thb, a.data_compra, a.situacao_acesso, a.eh_socio, a.socio_de_aluno_id
             from public.thb_alunos a where a.id::text > v_cur order by a.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := pessoas.pessoa_do_aluno(r.id);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao', r.turma_id, 'public.thb_alunos', r.id::text, 'public.thb_alunos', r.id::text,
            coalesce(r.data_entrada_thb::timestamp at time zone 'America/Sao_Paulo', r.data_compra, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'situacao_acesso', left(r.situacao_acesso, 30), 'socio', r.eh_socio)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if r.turma_aurum_id is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', r.turma_aurum_id, 'public.thb_alunos', r.id::text, 'public.thb_alunos', r.id::text || ':aurum',
              coalesce(r.data_compra, now()), jsonb_build_object('programa', 'aurum'))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
    if coalesce(r.eh_socio, false) and r.socio_de_aluno_id is not null and r.socio_de_aluno_id <> r.id then
      v_tit := pessoas.pessoa_do_aluno(r.socio_de_aluno_id);
      if v_tit is not null and v_tit <> v_p then
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_p, v_tit, r.turma_id, 'public.thb_alunos', r.id::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, 0, n_c, n_l - n_c, n_e, n_r, v_t0);
end $f$;

-- ======================= T1-T40 (espelho da planilha "Alunos e sócios T1 - T40") =======================
create function pessoas.carga_aluno_historico(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_chave text; v_quando timestamptz;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'aluno_historico'), '');
  -- cursor = md5(e-mail):turma (o espelho é regravado todo dia e os ids mudam)
  for r in select md5(h.email_norm) || ':' || coalesce(h.turma, '') k, h.*
             from controle.aluno_historico h
            where h.email_norm is not null and md5(h.email_norm) || ':' || coalesce(h.turma, '') > v_cur
            order by 1 limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas.casar_email(r.nome, r.email_norm, null, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_quando := case when r.primeira_compra ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                          and pg_input_is_valid(substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2), 'date')
                     then (substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2))::date::timestamp at time zone 'America/Sao_Paulo' end;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao',
            (select t.id from public.thb_turmas t where t.codigo = replace(r.turma, '.R', 'R')),
            'controle.aluno_historico', r.k, coalesce(v_quando, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'turma_fonte', left(r.turma, 20), 'data_estimada', v_quando is null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if nullif(btrim(r.turma_aurum), '') is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', (select t.id from public.thb_turmas t where t.codigo = btrim(r.turma_aurum)),
              'controle.aluno_historico', md5(r.email_norm) || ':' || left(btrim(r.turma_aurum), 20), coalesce(v_quando, now()),
              jsonb_build_object('programa', 'aurum', 'turma_fonte', left(btrim(r.turma_aurum), 20)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= Operação HM =======================
create function pessoas.carga_contatos_hm(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'contatos_hm'), '');
  for r in select c.id, c.comprador_id, c.aluno_id, c.produto, c.turma_origem, c.estagio_id, c.entrada_em, c.criado_em,
                  c.quitado_em, c.cancelamento_efetivado_em
             from cs.contatos_hm c where c.id::text > v_cur order by c.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := coalesce(case when r.aluno_id is not null then pessoas.pessoa_do_aluno(r.aluno_id) end,
                    case when r.comprador_id is not null then pessoas.pessoa_do_comprador(r.comprador_id) end);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'crm', 'importacao', (select t.id from public.thb_turmas t where t.codigo = r.turma_origem),
            'cs.contatos_hm', r.id::text, coalesce(r.entrada_em, r.criado_em, now()),
            jsonb_strip_nulls(jsonb_build_object('produto', left(r.produto, 40), 'estagio_id', r.estagio_id,
                                                 'turma_origem', left(r.turma_origem, 20), 'quitado', r.quitado_em is not null,
                                                 'cancelado', r.cancelamento_efetivado_em is not null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, 0, n_c, n_l - n_c, n_e, 0, v_t0);
end $f$;

create function pessoas.carga_hm_socios(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tit uuid;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hm_socios'), '');
  for r in select s.id, s.nome, s.email, s.telefone, s.aluno_id, s.criado_em, c.comprador_id t_comprador, c.aluno_id t_aluno, c.turma_origem
             from cs.hm_socios s left join cs.contatos_hm c on c.id = s.contato_hm_id
            where s.id::text > v_cur order by s.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    if r.aluno_id is not null then
      v_p := pessoas.pessoa_do_aluno(r.aluno_id); n_c := n_c + 1;
    else
      v := pessoas.casar_email(r.nome, r.email, r.telefone, 'importacao');
      v_p := (v->>'pessoa_id')::uuid;
      if v_p is null then n_s := n_s + 1; continue; end if;
      if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    end if;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'vinculo', 'importacao', 'cs.hm_socios', r.id::text, coalesce(r.criado_em, now()), jsonb_build_object('relacao', 'socio_de', 'programa', 'hm'))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    v_tit := coalesce(case when r.t_aluno is not null then pessoas.pessoa_do_aluno(r.t_aluno) end,
                      case when r.t_comprador is not null then pessoas.pessoa_do_comprador(r.t_comprador) end);
    if v_tit is not null and v_tit <> v_p then
      insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
      values ('socio_de', v_p, v_tit, (select t.id from public.thb_turmas t where t.codigo = r.turma_origem), 'cs.hm_socios', r.id::text)
      on conflict on constraint relacoes_unica do nothing;
      get diagnostics n_x = row_count; n_r := n_r + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

-- ======================= Respondi =======================
create function pessoas.carga_respondi(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_s uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'respondi'), '');
  for r in select x.uuid, x.form_slug, x.respondido_em, x.email, x.telefone, x.dados, f.familia, f.turma_codigo f_turma
             from respondi.respostas x left join respondi.formularios f on f.slug = x.form_slug
            where x.uuid::text > v_cur order by x.uuid::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.uuid::text); v_ate := r.uuid::text;
    v := pessoas.casar_email(r.dados->>'nome', coalesce(r.email, r.dados->>'email'), coalesce(r.telefone, r.dados->>'telefone'), 'respondi');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = coalesce(r.f_turma, r.dados->>'turma_codigo'));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'resposta', 'respondi', v_turma, 'respondi.respostas', r.uuid::text, coalesce(r.respondido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('formulario', left(r.form_slug, 40), 'familia', left(r.familia, 40),
                                                 'parcial', case when r.dados->>'parcial' = 'true' then true end)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    -- formulário de sócio: o sócio vira pessoa (por e-mail) e "sócio de" quem respondeu (o titular)
    if pessoas.norm_email(r.dados->>'socio_email') is not null then
      v := pessoas.casar_email(r.dados->>'socio_nome', r.dados->>'socio_email', r.dados->>'socio_telefone', 'respondi');
      v_s := (v->>'pessoa_id')::uuid;
      if v_s is not null and v_s <> v_p then
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
        values (v_s, 'vinculo', 'respondi', v_turma, 'respondi.respostas', r.uuid::text || ':socio', coalesce(r.respondido_em, now()),
                jsonb_build_object('relacao', 'socio_de', 'formulario', left(r.form_slug, 40)))
        on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
        get diagnostics n_x = row_count; n_e := n_e + n_x;
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_s, v_p, v_turma, 'respondi.respostas', r.uuid::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

-- ======================= leads de evento =======================
create function pessoas.carga_leads(p_execucao bigint, p_fonte text, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
  v_cnhf bigint := (select e.id from fin.eventos e where e.id = 72 and e.categoria = 'lancamento_cnhf');
begin
  if p_fonte not in ('leads_cnhf', 'leads_workbook', 'leads_black') then raise exception 'fonte de lead inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, p_fonte), '');
  for r in
    select x.id::text k, x.email, coalesce(x.telefone_e164, x.telefone) tel, x.nome, x.captado_em quando, false mql,
           jsonb_strip_nulls(jsonb_build_object('edicao', left(x.edicao, 40), 'utm_campaign', left(x.utm_campaign, 120), 'pagina', left(x.pagina, 120))) det,
           'workbook.cnhf_leads_captacao' tab, v_cnhf ev
      from workbook.cnhf_leads_captacao x where p_fonte = 'leads_cnhf' and x.id::text > v_cur
    union all
    select x.id::text, x.email, x.telefone, x.nome, x.criado_em, false,
           jsonb_strip_nulls(jsonb_build_object('origem', left(x.origem, 120))), 'workbook.leads', null::bigint
      from workbook.leads x where p_fonte = 'leads_workbook' and x.id::text > v_cur
    union all
    select x.lead_id, x.email, x.whatsapp, x.nome, x.criado_em, coalesce(x.mql, false),
           jsonb_strip_nulls(jsonb_build_object('pagina', left(x.pagina, 120), 'utm_campaign', left(x.utm_campaign, 120))), 'dados.black_leads', null::bigint
      from dados.black_leads x where p_fonte = 'leads_black' and x.lead_id > v_cur and not coalesce(x.teste, false) and not coalesce(x.parece_teste, false)
    order by 1 limit p_limite
  loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas.casar_email(r.nome, r.email, r.tel, 'formulario');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'lead', 'formulario', r.ev, r.tab, left(r.k, 120), coalesce(r.quando, now()), r.det)
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if r.mql then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'mql', 'formulario', r.ev, r.tab, left(r.k, 120), coalesce(r.quando, now()), r.det)
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= CRM =======================
create function pessoas.carga_crm_negocio(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'crm_negocio'), '');
  for r in select n.id, n.pessoa_id, n.linha, n.status, n.origem, n.criado_em
             from crm.negocio n where n.id::text > v_cur order by n.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := pessoas.atual(r.pessoa_id);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'crm', 'crm', 'crm.negocio', r.id::text, 'crm.negocio', r.id::text, coalesce(r.criado_em, now()),
            jsonb_strip_nulls(jsonb_build_object('linha', left(r.linha, 40), 'status', left(r.status, 20), 'origem', left(r.origem, 60))))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, v_ate, n_l, 0, n_c, n_l - n_c, n_e, 0, v_t0);
end $f$;

revoke all on function pessoas._carga_exigir(bigint, text),
  pessoas._carga_lote_fim(bigint, text, text, int, int, int, int, int, int, timestamptz),
  pessoas.carga_fin_hotmart(bigint, text, integer), pessoas.carga_thb_alunos(bigint, integer),
  pessoas.carga_aluno_historico(bigint, integer), pessoas.carga_contatos_hm(bigint, integer),
  pessoas.carga_hm_socios(bigint, integer), pessoas.carga_respondi(bigint, integer),
  pessoas.carga_leads(bigint, text, integer), pessoas.carga_crm_negocio(bigint, integer)
  from public, anon, authenticated, service_role;

do $g$
begin
  if exists (select 1 from pg_proc p where p.pronamespace = 'pessoas'::regnamespace
               and (p.proname like 'carga%' or p.proname like '\_carga%')
               and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '20261014170100: função de carga ficou executável por anon/authenticated.';
  end if;
end
$g$;

-- ===== testes: cada fonte, 200 linhas reais, depois a MESMA faixa de novo (idempotente) =====
do $t$
declare f text; v_e bigint; r1 jsonb; r2 jsonb; t0 timestamptz;
begin
  foreach f in array array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio'] loop
    begin
      t0 := clock_timestamp();
      v_e := (pessoas.carga_abrir(f, 'pessoas', 'ensaio')->>'execucao')::bigint;
      r1 := case f when 'hotmart_academy' then pessoas.carga_fin_hotmart(v_e, 'academy', 200) when 'hotmart_escritorio' then pessoas.carga_fin_hotmart(v_e, 'escritorio', 200) when 'thb_alunos' then pessoas.carga_thb_alunos(v_e, 200)
                   when 'aluno_historico' then pessoas.carga_aluno_historico(v_e, 200) when 'contatos_hm' then pessoas.carga_contatos_hm(v_e, 200)
                   when 'hm_socios' then pessoas.carga_hm_socios(v_e, 200) when 'respondi' then pessoas.carga_respondi(v_e, 200)
                   when 'crm_negocio' then pessoas.carga_crm_negocio(v_e, 200) else pessoas.carga_leads(v_e, f, 200) end;
      update pessoas.carga_execucao set cursor = null where id = v_e;   -- volta ao começo: mesma faixa
      r2 := case f when 'hotmart_academy' then pessoas.carga_fin_hotmart(v_e, 'academy', 200) when 'hotmart_escritorio' then pessoas.carga_fin_hotmart(v_e, 'escritorio', 200) when 'thb_alunos' then pessoas.carga_thb_alunos(v_e, 200)
                   when 'aluno_historico' then pessoas.carga_aluno_historico(v_e, 200) when 'contatos_hm' then pessoas.carga_contatos_hm(v_e, 200)
                   when 'hm_socios' then pessoas.carga_hm_socios(v_e, 200) when 'respondi' then pessoas.carga_respondi(v_e, 200)
                   when 'crm_negocio' then pessoas.carga_crm_negocio(v_e, 200) else pessoas.carga_leads(v_e, f, 200) end;
      perform pessoas.carga_fechar(v_e, 'ok');
      insert into pg_temp._z_out(passo, linha) values ('10 ' || f, '1ª: ' || (r1 - 'ms')::text || ' | 2ª (mesma faixa): eventos ' || (r2->>'eventos') || ', novas ' || (r2->>'pessoas_novas') || ', relações ' || (r2->>'relacoes') || ' | ' || (extract(epoch from clock_timestamp() - t0) * 1000)::int || ' ms');
    exception when others then
      insert into pg_temp._z_out(passo, linha) values ('10 ' || f, 'ERRO ' || sqlstate);
    end;
  end loop;
end $t$;
insert into pg_temp._z_out(passo, linha) select '20 eventos por fonte e tipo', string_agg(fonte_tabela || '/' || tipo || ' ' || n, ', ' order by fonte_tabela, tipo) from (select fonte_tabela, tipo, count(*) n from pessoas.eventos where fonte_tabela is not null group by 1, 2) x;
insert into pg_temp._z_out(passo, linha) select '21 hotmart: com evento do catálogo / linhas do webhook que ganharam fonte (sem duplicar)', (select count(*) from pessoas.eventos where fonte_tabela = 'fin.hotmart_transacoes' and evento_id is not null) || ' / ' || (select count(*) from pessoas.eventos where fonte_tabela = 'fin.hotmart_transacoes' and fonte = 'hotmart' and detalhe ? 'classe');
insert into pg_temp._z_out(passo, linha) select '22 relações sócio de', count(*)::text from pessoas.relacoes;
insert into pg_temp._z_out(passo, linha) select '23 revisões novas', (select count(*) from pessoas.revisao)::text;
insert into pg_temp._z_out(passo, linha) select '24 funções executáveis por anon/authenticated', count(*)::text from pg_proc p where p.pronamespace = 'pessoas'::regnamespace and (p.proname like 'carga%' or p.proname like '\_carga%' or p.proname = 'casar_email') and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
-- ===== reversão da 170100 =====
-- Reversão de 20261014170100 (cargas das fontes). NÃO apaga pessoa nem evento já carregado (regra I-03): os eventos das
-- cargas ficam identificados por fonte_tabela; medir antes com
--   select fonte_tabela, count(*) from pessoas.eventos where fonte_tabela is not null group by 1;
set local lock_timeout = '5s';
drop function if exists pessoas.carga_crm_negocio(bigint, integer);
drop function if exists pessoas.carga_leads(bigint, text, integer);
drop function if exists pessoas.carga_respondi(bigint, integer);
drop function if exists pessoas.carga_hm_socios(bigint, integer);
drop function if exists pessoas.carga_contatos_hm(bigint, integer);
drop function if exists pessoas.carga_aluno_historico(bigint, integer);
drop function if exists pessoas.carga_thb_alunos(bigint, integer);
drop function if exists pessoas.carga_fin_hotmart(bigint, text, integer);
drop function if exists pessoas._carga_lote_fim(bigint, text, text, int, int, int, int, int, int, timestamptz);
drop function if exists pessoas._carga_exigir(bigint, text);
delete from pessoas.carga_chave where fonte in ('hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi',
  'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio') and por = 'migration 20261014170100';

insert into pg_temp._z_out(passo, linha) select '90 depois da reversão: funções da 170100 que sobram', count(*)::text from pg_proc where pronamespace = 'pessoas'::regnamespace and proname in ('carga_fin_hotmart','carga_thb_alunos','carga_aluno_historico','carga_contatos_hm','carga_hm_socios','carga_respondi','carga_leads','carga_crm_negocio','_carga_exigir','_carga_lote_fim');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
