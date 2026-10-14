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
set local statement_timeout = '30s';

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
