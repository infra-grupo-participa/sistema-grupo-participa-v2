-- 20261017040000: pessoa única, atributos calculados por pessoa (pessoas.atributos) sobre a linha do tempo (pessoas.eventos)
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-pessoas-atributos). Só foi rodado o ENSAIO (begin ... rollback).
--   Aplicar só depois do ok do Victor nas perguntas em aberto (20261017040000.explain.md, seção "Perguntas em aberto").
--   Ensaio: 20261017040000_ensaio.sql. Reversão: 20261017040000_reversao.sql. Detalhe e números: 20261017040000.explain.md.
--
-- POR QUE: passo 5 do PLANO da pessoa única (cérebro do Victor, Projetos/sistema-unico/pessoa-unica/PLANO.md): os atributos do
--   DICIONARIO-DE-ATRIBUTOS.md (aprovado pelo Victor em 14/10/2026, três rodadas) viram colunas calculadas, para que "quem é aluno ativo",
--   "quem foi ao checkout da SV e não comprou", "quem fez HT e nunca comprou HM" sejam um filtro e não uma planilha.
-- O QUE MUDA (só objetos novos; nenhuma tabela existente muda, nenhum job é criado):
--   1. Tabela pessoas.atributos: uma linha por pessoa ativa e não teste, com calculado_em. RLS ligada, sem policy, sem grant (só postgres lê).
--   2. View pessoas.vw_compra (security_invoker): cada compra Hotmart da linha do tempo com status atual da transação, família
--      (oferta, senão produto), tipo da oferta, conta, moeda, valores e a chave/categoria do evento.
--   3. View pessoas.vw_oferta_a_conferir (security_invoker): ofertas HM e Aurum vendidas sem tipo (decisão 8: vão para conferência humana).
--   4. Função pessoas.atributos_calcular(uuid[]): recalcula (upsert) as pessoas pedidas e apaga a linha de quem deixou de ser ativa.
--   5. Função pessoas.atributos_lote(uuid, integer): próximo lote por cursor de id; devolve o último id (null = acabou).
-- REGRAS (de onde vem cada atributo; nomes exatos das fontes):
--   compra aprovada = fin.hotmart_transacoes.status in ('COMPLETE','APPROVED') (o status atual já reflete reembolso e chargeback).
--   família = coalesce(pessoas.vw_oferta.familia, fin.produtos.familia); tipo = pessoas.vw_oferta.tipo (sinal, saldo, integral, renovacao).
--   hm = aprovada HM com tipo integral ou saldo (decisão 1: sinal não é compra), OU aprovada sem tipo do produto 446345 'Curso Prático de Holding
--      Familiar' (o antigo HM, Victor 16/10), OU qualquer aprovada HM de quem tem matrícula em public.thb_alunos (Victor 16/10: ligar pela matrícula).
--   aurum = aprovada AURUM com tipo integral ou saldo, OU qualquer aprovada AURUM de quem está em cs.vw_aurum_por_aluno (pelo aluno_id).
--   *_so_sinal = tem sinal e não é hm/aurum. *_renovou = aprovada com tipo renovacao (decisão 8: não conta como compra nova).
--   *_a_conferir = aprovada da família sem tipo e que nenhuma regra acima confirmou (vai para pessoas.vw_oferta_a_conferir).
--   ht_edicoes = chave do evento das compras aprovadas família HT em evento categoria holding_total.
--   ethb / clinica / imersao = chave do evento das compras aprovadas família EVENTOS em evento categoria encontro_thb / clinica / imersao.
--   seminario_edicoes = chave dos eventos seminario_elaine e seminario_marcio em que foi lead ou mql (cada chave é um produto; decisão do dicionário).
--   sv_checkout_sem_compra = linha activecampaign pre_checkout com detalhe papel 'sv_pre_checkout' (todas as listas SV e todo status, decisão 5) e nenhuma compra
--      aprovada dos produtos 'Sessão de Viabilidade' (5238525, 1663254, 1664749 em fin.produtos).
--   e_aluno_ativo = public.thb_alunos via pessoas.aluno_id com situacao_acesso in ('em_dia','a_vencer','acompanha_titular') e cancelado_em nulo;
--      sócio (eh_socio) só é ativo se o titular (socio_de_aluno_id) também estiver nessa situação.
--   e_socio = relação socio_de como sócio (pessoas.relacoes.pessoa_id), vínculo importado da aba 'Sócios...' ou thb_alunos.eh_socio.
--   e_ex_aluno_thb = não é aluno ativo e (comprou o produto 446345 'Curso Prático de Holding Familiar', ou tem matrícula própria em thb_alunos
--      que não é de sócio, ou ativação importada com programa 'thb' ou aba 'T<n>...' sem ser sócio). Sócio não conta como ex-aluno (Victor 16/10).
--   e_ex_socio = é sócio e não é aluno ativo (o titular saiu ou o acesso dele acabou).
--   turma_especial = sha256 do e-mail, dos 8 últimos dígitos do telefone ou do documento bate com dados.turma_especial_chaves.
--   pode_disparar = não turma_especial e nenhum contato do AC com descadastrou (decisões 4 e 6: desativado pela empresa continua disparável).
--   total_pago_bruto / _liquido = soma de valor_cobrado / liquido_produtor das aprovadas em BRL (decisão 3); compras_outra_moeda conta as demais
--      e total_outra_moeda guarda a soma de valor_cobrado por moeda ({"USD": 1234.5}), sem converter (decisão 3).
--   primeiro_contato / ultimo_contato = menor e maior quando da linha do tempo, sem a fonte 'sistema' (vínculo, mescla, revisão não são contato).
--   email_principal / telefone_principal = valor do identificador mais recente (criado_em, depois id).
-- COMO VOLTAR: 20261017040000_reversao.sql (apaga as 2 funções, as 2 views e a tabela; nada fora delas depende delas).
-- AS 5 PERGUNTAS: ver 20261017040000.explain.md (escala ~511 mil pessoas; índices existentes eventos(pessoa_id, quando), identificadores(pessoa_id, tipo, chave),
--   ac_contato(pessoa_id), relacoes(pessoa_id, tipo), PK de thb_alunos, hotmart_transacoes, ofertas, produtos, fin.eventos; manual por lote, nunca job;
--   idempotente (upsert); reversão = drop).
-- DADO PESSOAL: a tabela guarda e-mail e telefone principais (já estão em pessoas.identificadores); RLS ligada e sem grant, igual às demais de pessoas.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table if not exists pessoas.atributos (
  pessoa_id               uuid primary key references pessoas.pessoas(id) on delete cascade,
  e_lead                  boolean not null default false,
  e_comprador             boolean not null default false,
  e_comprador_escritorio  boolean not null default false,
  e_comprador_educacional boolean not null default false,
  e_aluno_ativo           boolean not null default false,
  e_ex_aluno_thb          boolean not null default false,
  e_socio                 boolean not null default false,
  e_ex_socio              boolean not null default false,
  turma_especial          boolean not null default false,
  eventos_lead            text[] not null default '{}',
  eventos_comprou         text[] not null default '{}',
  ht_edicoes              text[] not null default '{}',
  seminario_edicoes       text[] not null default '{}',
  ethb                    text[] not null default '{}',
  clinica                 text[] not null default '{}',
  imersao                 text[] not null default '{}',
  hm                      boolean not null default false,
  hm_so_sinal             boolean not null default false,
  hm_renovou              boolean not null default false,
  hm_a_conferir           boolean not null default false,
  aurum                   boolean not null default false,
  aurum_so_sinal          boolean not null default false,
  aurum_renovou           boolean not null default false,
  aurum_a_conferir        boolean not null default false,
  sv_checkout_sem_compra  boolean not null default false,
  total_pago_bruto        numeric not null default 0,
  total_pago_liquido      numeric not null default 0,
  qtd_compras             integer not null default 0,
  compras_outra_moeda     integer not null default 0,
  total_outra_moeda       jsonb not null default '{}',
  primeiro_contato        timestamptz,
  ultimo_contato          timestamptz,
  email_principal         text,
  telefone_principal      text,
  pode_disparar           boolean not null default true,
  calculado_em            timestamptz not null default now()
);
comment on table pessoas.atributos is 'Atributos calculados por pessoa (DICIONARIO-DE-ATRIBUTOS do Victor). Recalcular com pessoas.atributos_calcular / atributos_lote. Migration 20261017040000.';
alter table pessoas.atributos enable row level security;
revoke all on table pessoas.atributos from public, anon, authenticated, service_role;

create or replace view pessoas.vw_compra with (security_invoker = true) as
select e.pessoa_id,
       e.id                                   as evento_linha_id,
       e.quando,
       t.transacao,
       t.status,
       t.status in ('COMPLETE', 'APPROVED')    as aprovada,
       t.conta,
       t.moeda,
       t.valor_cobrado,
       t.liquido_produtor,
       t.oferta_codigo,
       o.oferta_nome,
       t.produto_id,
       coalesce(o.produto_nome, p.nome, t.produto_nome) as produto_nome,
       coalesce(o.familia, p.familia)          as familia,
       o.tipo,
       fe.chave                                as evento_chave,
       fe.categoria                            as evento_categoria,
       nullif(regexp_replace(coalesce(t.comprador_documento, ''), '\D', '', 'g'), '') as documento
  from pessoas.eventos e
  join ((select * from fin.hotmart_transacoes where conta = 'academy')
        union all
        (select * from fin.hotmart_transacoes where conta = 'escritorio')) t on t.transacao = e.ref_id
  left join pessoas.vw_oferta o on o.oferta_codigo = t.oferta_codigo
  left join fin.produtos p on p.produto_id = t.produto_id
  left join fin.eventos fe on fe.id = e.evento_id
 where e.tipo = 'compra' and e.ref_tipo = 'hotmart.transacao';
comment on view pessoas.vw_compra is 'Compras Hotmart da linha do tempo com status atual, família, tipo de oferta e evento. Migration 20261017040000.';
revoke all on table pessoas.vw_compra from public, anon, authenticated, service_role;

create or replace view pessoas.vw_oferta_a_conferir with (security_invoker = true) as
select c.familia, c.oferta_codigo, c.oferta_nome, c.produto_id, c.produto_nome,
       count(*) as compras_aprovadas, count(distinct c.pessoa_id) as pessoas,
       round(avg(c.valor_cobrado) filter (where c.moeda = 'BRL'), 2) as valor_medio_brl
  from pessoas.vw_compra c
 where c.aprovada and c.familia in ('HM', 'AURUM') and c.tipo is null
 group by 1, 2, 3, 4, 5;
comment on view pessoas.vw_oferta_a_conferir is 'Ofertas HM e Aurum vendidas sem tipo (sinal, saldo, integral, renovacao): conferência humana, decisão 8 do dicionário. Migration 20261017040000.';
revoke all on table pessoas.vw_oferta_a_conferir from public, anon, authenticated, service_role;

create or replace function pessoas.atributos_calcular(p_ids uuid[])
returns integer
language plpgsql set search_path to '' as $f$
declare
  n integer;
begin
  -- quem deixou de ser ativa (mesclada, revisar) ou virou teste perde a linha
  delete from pessoas.atributos a
   using pessoas.pessoas p
   where a.pessoa_id = any(p_ids) and p.id = a.pessoa_id
     and (p.situacao <> 'ativa' or coalesce(p.teste, false));

  with alvo as (
    select p.id, p.aluno_id
      from pessoas.pessoas p
     where p.id = any(p_ids) and p.situacao = 'ativa' and not coalesce(p.teste, false)
  ),
  ev as (
    select e.pessoa_id,
           bool_or(e.tipo = 'lead') as e_lead,
           coalesce(array_agg(distinct fe.chave order by fe.chave) filter (where e.tipo in ('lead', 'mql') and fe.chave is not null), '{}') as eventos_lead,
           coalesce(array_agg(distinct fe.chave order by fe.chave) filter (where e.tipo in ('lead', 'mql') and fe.categoria in ('seminario_elaine', 'seminario_marcio')), '{}') as seminario_edicoes,
           bool_or(e.tipo = 'pre_checkout' and e.fonte = 'activecampaign' and e.detalhe->>'papel' = 'sv_pre_checkout') as sv_pre_checkout,
           bool_or(e.fonte = 'importacao' and e.tipo = 'ativacao' and (e.detalhe->>'programa' = 'thb' or e.detalhe->>'aba' ~ '^T[0-9]')) as thb_importado,
           bool_or(e.fonte = 'importacao' and e.tipo = 'vinculo' and e.detalhe->>'aba' like 'Sócios%') as socio_importado,
           min(e.quando) filter (where e.fonte <> 'sistema') as primeiro_contato,
           max(e.quando) filter (where e.fonte <> 'sistema') as ultimo_contato
      from alvo a
      join pessoas.eventos e on e.pessoa_id = a.id
      left join fin.eventos fe on fe.id = e.evento_id
     group by e.pessoa_id
  ),
  co as (
    select c.pessoa_id,
           bool_or(c.aprovada) as e_comprador,
           bool_or(c.aprovada and c.conta = 'escritorio') as e_comprador_escritorio,
           bool_or(c.aprovada and c.conta = 'academy') as e_comprador_educacional,
           coalesce(array_agg(distinct c.evento_chave order by c.evento_chave) filter (where c.aprovada and c.evento_chave is not null), '{}') as eventos_comprou,
           coalesce(array_agg(distinct c.evento_chave order by c.evento_chave) filter (where c.aprovada and c.familia = 'HT' and c.evento_categoria = 'holding_total'), '{}') as ht_edicoes,
           coalesce(array_agg(distinct c.evento_chave order by c.evento_chave) filter (where c.aprovada and c.familia = 'EVENTOS' and c.evento_categoria = 'encontro_thb'), '{}') as ethb,
           coalesce(array_agg(distinct c.evento_chave order by c.evento_chave) filter (where c.aprovada and c.familia = 'EVENTOS' and c.evento_categoria = 'clinica'), '{}') as clinica,
           coalesce(array_agg(distinct c.evento_chave order by c.evento_chave) filter (where c.aprovada and c.familia = 'EVENTOS' and c.evento_categoria = 'imersao'), '{}') as imersao,
           bool_or(c.aprovada and c.familia = 'HM' and (c.tipo in ('integral', 'saldo') or (c.tipo is null and c.produto_id = '446345'))) as hm_tipado,
           bool_or(c.aprovada and c.familia = 'HM') as hm_qualquer,
           bool_or(c.aprovada and c.produto_id = '446345') as curso_pratico,
           bool_or(c.aprovada and c.familia = 'HM' and c.tipo = 'sinal') as hm_sinal,
           bool_or(c.aprovada and c.familia = 'HM' and c.tipo = 'renovacao') as hm_renovou,
           bool_or(c.aprovada and c.familia = 'HM' and c.tipo is null) as hm_a_conferir,
           bool_or(c.aprovada and c.familia = 'AURUM' and c.tipo in ('integral', 'saldo')) as aurum_tipado,
           bool_or(c.aprovada and c.familia = 'AURUM') as aurum_qualquer,
           bool_or(c.aprovada and c.familia = 'AURUM' and c.tipo = 'sinal') as aurum_sinal,
           bool_or(c.aprovada and c.familia = 'AURUM' and c.tipo = 'renovacao') as aurum_renovou,
           bool_or(c.aprovada and c.familia = 'AURUM' and c.tipo is null) as aurum_a_conferir,
           bool_or(c.aprovada and c.produto_id in ('5238525', '1663254', '1664749')) as sv_comprou,
           coalesce(sum(c.valor_cobrado) filter (where c.aprovada and c.moeda = 'BRL'), 0) as total_pago_bruto,
           coalesce(sum(c.liquido_produtor) filter (where c.aprovada and c.moeda = 'BRL'), 0) as total_pago_liquido,
           (count(*) filter (where c.aprovada))::integer as qtd_compras,
           (count(*) filter (where c.aprovada and coalesce(c.moeda, '') <> 'BRL'))::integer as compras_outra_moeda,
           array_agg(distinct c.documento) filter (where c.documento is not null) as documentos
      from alvo a
      join pessoas.vw_compra c on c.pessoa_id = a.id
     group by c.pessoa_id
  ),
  al as (
    select a.id as pessoa_id,
           (t.situacao_acesso in ('em_dia', 'a_vencer', 'acompanha_titular') and t.cancelado_em is null
            and (not coalesce(t.eh_socio, false) or t.socio_de_aluno_id is null
                 or (ti.situacao_acesso in ('em_dia', 'a_vencer', 'acompanha_titular') and ti.cancelado_em is null))) as ativo,
           coalesce(t.eh_socio, false) as eh_socio,
           nullif(regexp_replace(coalesce(t.documento, ''), '\D', '', 'g'), '') as documento
      from alvo a
      join public.thb_alunos t on t.id = a.aluno_id
      left join public.thb_alunos ti on ti.id = t.socio_de_aluno_id
  ),
  om as (
    select x.pessoa_id, jsonb_object_agg(x.moeda, x.total order by x.moeda) as total_outra_moeda
      from (select c.pessoa_id, coalesce(c.moeda, '?') as moeda, sum(c.valor_cobrado) as total
              from alvo a
              join pessoas.vw_compra c on c.pessoa_id = a.id
             where c.aprovada and coalesce(c.moeda, '') <> 'BRL'
             group by 1, 2) x
     group by x.pessoa_id
  ),
  au as (
    select distinct a.id as pessoa_id
      from alvo a
      join cs.vw_aurum_por_aluno v on v.aluno_id = a.aluno_id
  ),
  so as (
    select distinct r.pessoa_id
      from alvo a
      join pessoas.relacoes r on r.pessoa_id = a.id and r.tipo = 'socio_de'
  ),
  te as (
    select distinct a.id as pessoa_id
      from alvo a
     where exists (
             select 1
               from pessoas.identificadores i
               join dados.turma_especial_chaves k
                 on (i.tipo = 'email' and k.tipo = 'email' and k.hash = encode(sha256(convert_to(i.chave, 'UTF8')), 'hex'))
                 or (i.tipo = 'telefone' and k.tipo = 'fone8' and k.hash = encode(sha256(convert_to(right(i.chave, 8), 'UTF8')), 'hex'))
              where i.pessoa_id = a.id)
        or exists (
             select 1
               from dados.turma_especial_chaves k
              where k.tipo = 'documento'
                and k.hash in (select encode(sha256(convert_to(d, 'UTF8')), 'hex')
                                 from (select al.documento as d from al where al.pessoa_id = a.id
                                       union
                                       select unnest(co.documentos) from co where co.pessoa_id = a.id) dd
                                where d is not null))
  ),
  ds as (
    select distinct ac.pessoa_id
      from alvo a
      join pessoas.ac_contato ac on ac.pessoa_id = a.id and ac.descadastrou
  ),
  idf as (
    select a.id as pessoa_id,
           (select i.valor from pessoas.identificadores i where i.pessoa_id = a.id and i.tipo = 'email' order by i.criado_em desc nulls last, i.id desc limit 1) as email_principal,
           (select i.valor from pessoas.identificadores i where i.pessoa_id = a.id and i.tipo = 'telefone' order by i.criado_em desc nulls last, i.id desc limit 1) as telefone_principal
      from alvo a
  ),
  linha as (
    select a.id as pessoa_id,
           coalesce(ev.e_lead, false) as e_lead,
           coalesce(co.e_comprador, false) as e_comprador,
           coalesce(co.e_comprador_escritorio, false) as e_comprador_escritorio,
           coalesce(co.e_comprador_educacional, false) as e_comprador_educacional,
           coalesce(al.ativo, false) as e_aluno_ativo,
           (not coalesce(al.ativo, false)
            and (coalesce(co.curso_pratico, false)
                 or (al.pessoa_id is not null and not al.eh_socio)
                 or (coalesce(ev.thb_importado, false) and not (so.pessoa_id is not null or coalesce(ev.socio_importado, false) or coalesce(al.eh_socio, false))))) as e_ex_aluno_thb,
           (so.pessoa_id is not null or coalesce(ev.socio_importado, false) or coalesce(al.eh_socio, false)) as e_socio,
           ((so.pessoa_id is not null or coalesce(ev.socio_importado, false) or coalesce(al.eh_socio, false)) and not coalesce(al.ativo, false)) as e_ex_socio,
           (te.pessoa_id is not null) as turma_especial,
           coalesce(ev.eventos_lead, '{}') as eventos_lead,
           coalesce(co.eventos_comprou, '{}') as eventos_comprou,
           coalesce(co.ht_edicoes, '{}') as ht_edicoes,
           coalesce(ev.seminario_edicoes, '{}') as seminario_edicoes,
           coalesce(co.ethb, '{}') as ethb,
           coalesce(co.clinica, '{}') as clinica,
           coalesce(co.imersao, '{}') as imersao,
           coalesce(co.hm_tipado or (al.pessoa_id is not null and co.hm_qualquer), false) as hm,
           (coalesce(co.hm_sinal, false) and not coalesce(co.hm_tipado or (al.pessoa_id is not null and co.hm_qualquer), false)) as hm_so_sinal,
           coalesce(co.hm_renovou, false) as hm_renovou,
           (coalesce(co.hm_a_conferir, false) and not coalesce(co.hm_tipado or (al.pessoa_id is not null and co.hm_qualquer), false)) as hm_a_conferir,
           coalesce(co.aurum_tipado or (au.pessoa_id is not null and co.aurum_qualquer), false) as aurum,
           (coalesce(co.aurum_sinal, false) and not coalesce(co.aurum_tipado or (au.pessoa_id is not null and co.aurum_qualquer), false)) as aurum_so_sinal,
           coalesce(co.aurum_renovou, false) as aurum_renovou,
           (coalesce(co.aurum_a_conferir, false) and not coalesce(co.aurum_tipado or (au.pessoa_id is not null and co.aurum_qualquer), false)) as aurum_a_conferir,
           (coalesce(ev.sv_pre_checkout, false) and not coalesce(co.sv_comprou, false)) as sv_checkout_sem_compra,
           coalesce(co.total_pago_bruto, 0) as total_pago_bruto,
           coalesce(co.total_pago_liquido, 0) as total_pago_liquido,
           coalesce(co.qtd_compras, 0) as qtd_compras,
           coalesce(co.compras_outra_moeda, 0) as compras_outra_moeda,
           coalesce(om.total_outra_moeda, '{}') as total_outra_moeda,
           ev.primeiro_contato,
           ev.ultimo_contato,
           idf.email_principal,
           idf.telefone_principal,
           (te.pessoa_id is null and ds.pessoa_id is null) as pode_disparar
      from alvo a
      left join ev  on ev.pessoa_id = a.id
      left join co  on co.pessoa_id = a.id
      left join al  on al.pessoa_id = a.id
      left join so  on so.pessoa_id = a.id
      left join te  on te.pessoa_id = a.id
      left join ds  on ds.pessoa_id = a.id
      left join idf on idf.pessoa_id = a.id
      left join om  on om.pessoa_id = a.id
      left join au  on au.pessoa_id = a.id
  )
  insert into pessoas.atributos as x (
    pessoa_id, e_lead, e_comprador, e_comprador_escritorio, e_comprador_educacional, e_aluno_ativo, e_ex_aluno_thb, e_socio, e_ex_socio, turma_especial,
    eventos_lead, eventos_comprou, ht_edicoes, seminario_edicoes, ethb, clinica, imersao,
    hm, hm_so_sinal, hm_renovou, hm_a_conferir, aurum, aurum_so_sinal, aurum_renovou, aurum_a_conferir,
    sv_checkout_sem_compra, total_pago_bruto, total_pago_liquido, qtd_compras, compras_outra_moeda, total_outra_moeda,
    primeiro_contato, ultimo_contato, email_principal, telefone_principal, pode_disparar, calculado_em)
  select l.*, now() from linha l
  on conflict (pessoa_id) do update set
    e_lead = excluded.e_lead, e_comprador = excluded.e_comprador, e_comprador_escritorio = excluded.e_comprador_escritorio,
    e_comprador_educacional = excluded.e_comprador_educacional, e_aluno_ativo = excluded.e_aluno_ativo, e_ex_aluno_thb = excluded.e_ex_aluno_thb,
    e_socio = excluded.e_socio, e_ex_socio = excluded.e_ex_socio, turma_especial = excluded.turma_especial,
    eventos_lead = excluded.eventos_lead, eventos_comprou = excluded.eventos_comprou, ht_edicoes = excluded.ht_edicoes,
    seminario_edicoes = excluded.seminario_edicoes, ethb = excluded.ethb, clinica = excluded.clinica, imersao = excluded.imersao,
    hm = excluded.hm, hm_so_sinal = excluded.hm_so_sinal, hm_renovou = excluded.hm_renovou, hm_a_conferir = excluded.hm_a_conferir,
    aurum = excluded.aurum, aurum_so_sinal = excluded.aurum_so_sinal, aurum_renovou = excluded.aurum_renovou, aurum_a_conferir = excluded.aurum_a_conferir,
    sv_checkout_sem_compra = excluded.sv_checkout_sem_compra, total_pago_bruto = excluded.total_pago_bruto,
    total_pago_liquido = excluded.total_pago_liquido, qtd_compras = excluded.qtd_compras, compras_outra_moeda = excluded.compras_outra_moeda,
    total_outra_moeda = excluded.total_outra_moeda,
    primeiro_contato = excluded.primeiro_contato, ultimo_contato = excluded.ultimo_contato,
    email_principal = excluded.email_principal, telefone_principal = excluded.telefone_principal,
    pode_disparar = excluded.pode_disparar, calculado_em = excluded.calculado_em;
  get diagnostics n = row_count;
  return n;
end
$f$;
comment on function pessoas.atributos_calcular(uuid[]) is 'Recalcula pessoas.atributos para os ids pedidos (upsert) e apaga a linha de quem deixou de ser ativa. Migration 20261017040000.';

create or replace function pessoas.atributos_lote(p_apos uuid, p_limite integer default 2000)
returns uuid
language plpgsql set search_path to '' as $f$
declare
  v_ids uuid[];
begin
  if p_limite is null or p_limite < 1 or p_limite > 10000 then
    raise exception 'p_limite fora de 1..10000: %', p_limite;
  end if;
  select array_agg(id order by id) into v_ids
    from (select p.id from pessoas.pessoas p
           where p_apos is null or p.id > p_apos
           order by p.id limit p_limite) s;
  if v_ids is null then
    return null;
  end if;
  perform pessoas.atributos_calcular(v_ids);
  return v_ids[array_length(v_ids, 1)];
end
$f$;
comment on function pessoas.atributos_lote(uuid, integer) is 'Recalcula o próximo lote de pessoas por ordem de id depois de p_apos; devolve o último id (null = acabou). Manual, nunca job. Migration 20261017040000.';

revoke all on function pessoas.atributos_calcular(uuid[]), pessoas.atributos_lote(uuid, integer) from public, anon, authenticated, service_role;
