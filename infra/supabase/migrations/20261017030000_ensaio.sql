-- Ensaio de 20261017030000 numa transação DESFEITA (rollback). Sem dado pessoal na saída: pessoas fictícias "Zz..." e telefones/e-mails .invalid.
-- Rodar: executor que só aceita arquivo terminado em rollback (aplica_sql.py ensaio) neste arquivo.
-- O que ele prova: a migration roda sobre o estado real; a chave termina DESLIGADA mesmo se estava ligada; anon/authenticated/service_role não executam nem leem;
--   as 11 regras são aceitas pela procedure; a contagem na fila REAL bate com a da contagem; um passo em toda a fila real (aplicar tudo) tem falhas = 0, e reverter
--   devolve o estado idêntico (hash); num cenário fictício cada regra nova acontece, passo -> passo de novo (idempotente) -> reverter (inclusive a revisão apagada de D1,
--   de volta idêntica) -> reverter de novo; e a reversão do arquivo _reversao.sql devolve os 4 corpos de 20261017010000 (md5 igual ao medido).
-- O que ele NÃO prova: o COMMIT por passo da procedure revisao_lote_rodar (COMMIT não existe dentro de transação explícita): só as guardas.
--   A procedure é provada na aplicação, com p_max_aplicadas pequeno.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '250s';
create temp table _z_out (em serial, passo text, linha text);
create temp table _z (k text primary key, v text);

-- estado de partida: chave LIGADA de propósito, para provar que a migration a deixa desligada
update pessoas.carga_chave set ligada = true, ate = current_date + 7, por = 'ensaio' where fonte = 'revisao_lote';
insert into pg_temp._z_out(passo, linha)
select '00 antes: fila real pendente e colunas (esperado: chave ligada=true so no ensaio; coluna duplicadas ausente)', jsonb_build_object(
  'pendentes', (select count(*) from pessoas.revisao where status = 'pendente'),
  'chave_ligada', (select ligada from pessoas.carga_chave where fonte = 'revisao_lote'),
  'tem_duplicadas', exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'revisao_lote' and column_name = 'duplicadas'),
  'compradores', (select count(*) from public.compradores), 'crm_negocio', (select count(*) from crm.negocio))::text;

-- ===== 20261017030000 (corpo da migration, sem begin/commit) =====
-- 20261017030000: pessoa única, regras automáticas novas para a fila de revisão (pessoas.revisao), sobre a máquina de 20261017010000
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-revisao-regras). Só foi rodado o ENSAIO (begin ... rollback) e a contagem (somente leitura).
--   A chave pessoas.carga_chave 'revisao_lote' continua DESLIGADA; esta migration só cria objetos e garante a chave desligada. Nada é executado sobre a fila.
--   Ensaio: 20261017030000_ensaio.sql. Contagem (só leitura): 20261017030000_contagem.sql. Reversão: 20261017030000_reversao.sql.
--   Detalhe, números e decisões: 20261017030000.explain.md e docs/pessoa-unica/README.md (seção "Revisão em lote").
--
-- POR QUE: depois do lote de 20261017010000 sobraram revisões que o Victor mandou decidir por regra: (a) so_nome sem nenhum sinal em comum fecha como diferente;
--   (b) telefone igual + primeiro nome igual + um nome contém o outro + só UMA candidata bate = juntar; (c) pares de teste/equipe fecham como diferente;
--   (d) deduplicar o H1 (email_conflito); (e) incluir as A1 que não rodaram; (f) os so_nome que só existiam por causa do nome padrão (20261017020000) fecham como diferente.
-- O QUE MUDA (sem tabela nova; nada é executado sobre a fila):
--   1. pessoas.revisao_lote ganha a coluna duplicadas; arquivo.pessoas_revisao_lote_item aceita acao 'duplicada' (CHECK alargado).
--   2. Linha marcador em pessoas.revisao_lote (motivo_fim 'marcador 20261017030000'): a reversão usa o id dela para saber quais lotes são desta migration.
--   3. pessoas.carga_chave 'revisao_lote': garantida DESLIGADA (não é criada aqui; já existe desde 20261017010000).
--   4. pessoas.revisao_classificar, revisao_lote_passo, revisao_lote_rodar, revisao_lote_reverter: create or replace, mesma assinatura.
-- REGRAS NOVAS (o CALL escolhe quais valem):
--   A4_telefone_nome_contido (juntar): telefone igual, os dois nomes com 2 palavras ou mais, primeira palavra igual e o conjunto de palavras de um contido no do outro,
--     E a diferença entre os dois conjuntos (o que o nome maior tem a mais) SEM sufixo de geração: JUNIOR, JR, FILHO, FILHA, NETO, NETA, SOBRINHO, SOBRINHA, SEGUNDO, TERCEIRO, II, III
--     (pai e filho dividem telefone; o par com sufixo vai para a fila humana). Lista CONSTANTE VISÍVEL no classificador (lateral sg).
--   B4_so_nome_sem_sinal (separar): motivo so_nome e nenhum sinal em comum (telefone, e-mail, parte local do e-mail, CPF).
--   B6_nome_padrao_sem_sinal (separar): igual à B4 e uma das pessoas já teve o nome padrão tirado (arquivo.pessoas_nome_padrao_item, não revertido). Vem antes da B4 só para o código dizer a causa.
--   B5_teste_ou_equipe (separar): os dois lados são teste/equipe: pessoas.teste, e-mail @advmais.com, ou nome na lista abaixo. Também bloqueia qualquer regra A.
--     A lista de equipe é CONSTANTE VISÍVEL no corpo do classificador (array 'ARTHUR GALVAO' e prefixos 'IROMAR %', 'ARTHUR GALVAO %', em MAIÚSCULAS, como pessoas.norm_nome devolve).
--   D1_revisao_duplicada (nova ação 'duplicada'): só motivo email_conflito; existe revisão pendente de id menor com o mesmo motivo, a mesma pessoa e o mesmo conjunto de candidatas.
--     A repetida é APAGADA depois de cópia completa (to_jsonb da linha) em arquivo.pessoas_revisao_lote_item; a reversão a insere de volta, com o mesmo id.
--     Motivo de apagar: pessoas.revisao não tem status 'duplicada' no CHECK, e mexer na tabela compartilhada seria pior do que apagar com cópia.
-- CORREÇÕES DO PENTEST (16/10/2026, mesma data; o pentester reprovou a primeira versão):
--   MÉDIO  A4 juntava pai e filho (diferença com FILHO, mesmo telefone): agora o sufixo de geração na diferença tira o par da A4.
--   BAIXO  e-mail interno casava '%@advmais.com%' (pegava advmais.com.br e afins): agora casa o domínio exato no fim, '%@advmais.com'.
--   BAIXO  D1 travava só a repetida; agora trava também a gêmea de id menor (for share, skip locked) antes de apagar.
--   BAIXO  ao forçar ligada = false, a chave também zera o 'ate' (data de fim), para que religar exija data nova.
-- A1_telefone_nome (já existia) só precisa entrar no CALL para as 3 que não rodaram.
-- NÃO MEXE em public.compradores nem em crm.negocio (decisão pendente do Victor).
-- COMO VOLTAR: 20261017030000_reversao.sql (reverte os lotes posteriores ao marcador e devolve os 4 corpos de 20261017010000). Coluna e CHECK alargado ficam (histórico).
-- AS 5 PERGUNTAS: escala = 429 revisões pendentes em 16/10/2026; passo de 25 revisões, até 20 candidatas por revisão;
--   índice = os de 20261017010000 (pessoa_id e (tipo,chave) em identificadores, PK de pessoas/thb_alunos/compradores, revisao_pessoa_idx) e o índice único parcial por revisão não revertida; nenhum índice novo.
--     A subconsulta de D1 usa revisao_pessoa_idx e roda só para revisões email_conflito (o AND de rev.motivo corta as demais antes).
--   medido: explain (analyze, buffers) do corpo do classificador novo com 25 revisões (um passo): 366 ms, 1.721 buffers (todos hit), nenhum Seq Scan, planejamento 30 ms; a fila inteira (429) leu em uma chamada só na contagem, sem timeout
--   frequência = manual (CALL), nunca job; repetição = idempotente (só lê revisão 'pendente'; a duplicada reconfere a gêmea com a linha travada);
--   reversão = função de reverter (agora com a ação 'duplicada') + chave desligada.
-- DADO PESSOAL: igual a 20261017010000. CPF só para comparar dentro da consulta, nunca grava nem devolve; a cópia (jsonb) guarda ids, motivo, candidatas e status.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare v_md5 text; v_sig text;
begin
  if to_regprocedure('pessoas.revisao_classificar(bigint,integer,bigint[])') is null
     or to_regprocedure('pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])') is null
     or to_regprocedure('pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)') is null
     or to_regprocedure('pessoas.revisao_lote_reverter(bigint,integer)') is null then
    raise exception '20261017030000: falta 20261017010000 (as 4 funções da revisão em lote).';
  end if;
  if to_regclass('arquivo.pessoas_nome_padrao_item') is null then
    raise exception '20261017030000: falta 20261017020000 (arquivo.pessoas_nome_padrao_item).';
  end if;
  if not exists (select 1 from pessoas.carga_chave where fonte = 'revisao_lote') then
    raise exception '20261017030000: falta a chave pessoas.carga_chave revisao_lote (criada em 20261017010000).';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'revisao_lote' and column_name = 'duplicadas') then
    raise exception '20261017030000: já aplicada.';
  end if;
  -- os 4 corpos vivos têm que ser exatamente os de 20261017010000 (a reversão devolve esses textos)
  for v_sig, v_md5 in select * from (values
    ('pessoas.revisao_classificar(bigint,integer,bigint[])', 'bc7856f4e664819acd4ba670aa999120'),
    ('pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])', 'e933cefbad9c3d2f1562ea5eaa7dd11a'),
    ('pessoas.revisao_lote_reverter(bigint,integer)', '12a996d61dac3a3868a29ce4ce26fb7d'),
    ('pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)', '2542beabe1f98051924a567f400e5b58')
  ) t(a, b) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v_sig)) is distinct from v_md5 then
      raise exception '20261017030000: o corpo de % não é o de 20261017010000 (alguém mexeu depois). Conferir antes de seguir.', v_sig;
    end if;
  end loop;
end
$g$;

-- ===================== 1. coluna, CHECK, marcador e chave =====================
alter table pessoas.revisao_lote add column if not exists duplicadas integer not null default 0;

alter table arquivo.pessoas_revisao_lote_item drop constraint pessoas_revisao_lote_item_acao_check;
alter table arquivo.pessoas_revisao_lote_item
  add constraint pessoas_revisao_lote_item_acao_check check (acao in ('mesma', 'diferente', 'duplicada'));

-- marcador: a reversão desfaz só os lotes com id maior que o dele
insert into pessoas.revisao_lote (regras, tamanho_passo, terminou_em, motivo_fim)
values (array[]::text[], 1, now(), 'marcador 20261017030000');

-- a chave continua (ou volta a ficar) DESLIGADA. Ligar: update pessoas.carga_chave set ligada = true, ate = current_date + 7, por = 'victor' where fonte = 'revisao_lote';
update pessoas.carga_chave set ligada = false, ate = null, por = 'migration 20261017030000', em = now() where fonte = 'revisao_lote';

-- ===================== 2. classificador (só leitura) =====================
-- acao: mesma | diferente | duplicada | humano. 'mesma' só se EXATAMENTE 1 candidata bate numa regra A e a pessoa só tem esta revisão pendente.
-- 'diferente' só se TODAS as candidatas batem numa regra B e nenhuma numa regra A. 'duplicada' só D1.
create or replace function pessoas.revisao_classificar(p_apos bigint, p_limite integer, p_ids bigint[] default null)
returns table (revisao_id bigint, pessoa_id uuid, motivo text, acao text, regras text[], alvo uuid, n_pares integer, n_a integer, n_b integer)
language sql stable set search_path to '' as $f$
with rev as (
  select r.id rid, pessoas.atual(r.pessoa_id) p, r.motivo, r.candidatos
    from pessoas.revisao r
   where r.status = 'pendente' and r.id > p_apos and (p_ids is null or r.id = any(p_ids))
   order by r.id
   limit p_limite
),
par as (
  select rev.rid, rev.p, rev.motivo, cardinality(rev.candidatos) ncand, k.c
    from rev
   cross join lateral (select distinct pessoas.atual(x) c from unnest(rev.candidatos) x) k
   where k.c is not null and k.c <> rev.p
),
pes as (select p x from rev union select c from par),
info as (
  select x.x, d.nome, d.eh_aluno, d.teste, d.padrao,
         array(select i.chave from pessoas.identificadores i where i.pessoa_id = any(d.g) and i.tipo = 'email') || d.emails_ref emails,
         array(select i.chave from pessoas.identificadores i where i.pessoa_id = any(d.g) and i.tipo = 'telefone') || d.fones_ref fones,
         d.cpfs
    from pes x
   cross join lateral (
     select g.g,
            coalesce((array_agg(a.nome order by pp.id = x.x desc) filter (where a.nome is not null))[1],
                     (array_agg(cp.nome::text order by pp.id = x.x desc) filter (where cp.nome is not null))[1],
                     (array_agg(pp.nome order by pp.id = x.x desc) filter (where pp.nome is not null))[1]) nome,
            coalesce(bool_or(pp.aluno_id is not null), false) eh_aluno,
            coalesce(bool_or(pp.teste), false) teste,
            -- 020000: a pessoa já teve o nome padrão tirado (cópia em arquivo.pessoas_nome_padrao_item, ainda não revertida)
            exists (select 1 from arquivo.pessoas_nome_padrao_item np where np.pessoa_id = any(g.g) and np.revertido_em is null) padrao,
            coalesce(array_agg(lower(btrim(a.email))) filter (where nullif(btrim(a.email), '') is not null), '{}')
              || coalesce(array_agg(lower(btrim(cp.email::text))) filter (where nullif(btrim(cp.email::text), '') is not null), '{}') emails_ref,
            coalesce(array_agg(controle.fone_key(coalesce(a.telefone_e164, a.telefone)))
                       filter (where controle.fone_key(coalesce(a.telefone_e164, a.telefone)) is not null), '{}')
              || coalesce(array_agg(controle.fone_key(cp.telefone::text))
                       filter (where controle.fone_key(cp.telefone::text) is not null), '{}') fones_ref,
            -- só CPF (11 dígitos), só para comparar; nunca sai desta consulta
            coalesce(array_agg(regexp_replace(a.documento::text, '\D', '', 'g'))
                       filter (where length(regexp_replace(a.documento::text, '\D', '', 'g')) = 11), '{}')
              || coalesce(array_agg(regexp_replace(cp.documento::text, '\D', '', 'g'))
                       filter (where length(regexp_replace(cp.documento::text, '\D', '', 'g')) = 11), '{}') cpfs
       from (select pessoas.grupo(x.x) g) g
       join pessoas.pessoas pp on pp.id = any(g.g)
       left join public.thb_alunos a on a.id = pp.aluno_id
       left join public.compradores cp on cp.id = pp.comprador_id
      group by g.g
   ) d
),
sin as (
  select par.rid, par.p, par.c, par.motivo, par.ncand,
         (ip.fones && ic.fones) tel,
         (ip.emails && ic.emails) email_igual,
         (ip.cpfs && ic.cpfs) doc_igual,
         (cardinality(ip.cpfs) > 0 and cardinality(ic.cpfs) > 0 and not ip.cpfs && ic.cpfs) doc_dif,
         (ip.eh_aluno and ic.eh_aluno) ambos_aluno,
         (ip.teste is distinct from ic.teste) teste_dif,
         (n.np is not null and n.np = n.nc and n.np like '% %') nome_igual,
         (coalesce(cardinality(t.tp), 0) >= 2 and coalesce(cardinality(t.tc), 0) >= 2 and t.tp[1] = t.tc[1]
            and (t.tp <@ t.tc or t.tc <@ t.tp)) nome_sub,
         -- 030000 (pentest): a diferença entre os dois conjuntos de palavras (o que o nome maior tem a mais) traz sufixo de geração
         -- (pai e filho, avô e neto costumam dividir telefone): a A4 NÃO vale e o par fica para o humano.
         exists (select 1 from unnest(case when t.tp <@ t.tc then t.tc else t.tp end) w
                  where w = any(sg.suf) and not (w = any(case when t.tp <@ t.tc then t.tp else t.tc end))) sufixo_geracao,
         (t.tp[1] is not null and t.tp[1] = t.tc[1]) nome_prim,
         (t.tp[1] is not null and t.tc[1] is not null and left(t.tp[1], 1) <> left(t.tc[1], 1)
            and position(t.tp[1] in t.tc[1]) = 0 and position(t.tc[1] in t.tp[1]) = 0
            and public.similarity(t.tp[1], t.tc[1]) < 0.3) prim_dif,
         -- 030000: teste/equipe dos dois lados: pessoas.teste = true, e-mail @advmais.com, ou o nome é de quem a lista de eq nomeia.
         -- Também vale o par em que a pessoa da revisão só tem telefone (sem nome e sem e-mail), o telefone é o mesmo e o candidato é de teste/equipe.
         (coalesce(ic.teste or exists (select 1 from unnest(ic.emails) em where em like '%@advmais.com')
                   or n.nc = any(eq.nomes) or n.nc like any(eq.inicios), false)
          and coalesce(ip.teste or exists (select 1 from unnest(ip.emails) em where em like '%@advmais.com')
                       or n.np = any(eq.nomes) or n.np like any(eq.inicios)
                       or (ip.nome is null and cardinality(ip.emails) = 0 and (ip.fones && ic.fones)), false)) interno_ambos,
         (ip.padrao or ic.padrao) padrao_algum,
         e.local_igual, e.typo
    from par
    join info ip on ip.x = par.p
    join info ic on ic.x = par.c
   cross join lateral (select pessoas.norm_nome(ip.nome) np, pessoas.norm_nome(ic.nome) nc) n
   cross join lateral (select string_to_array(n.np, ' ') tp, string_to_array(n.nc, ' ') tc) t
   cross join lateral (select array['ARTHUR GALVAO']::text[] nomes, array['IROMAR %', 'ARTHUR GALVAO %']::text[] inicios) eq
   -- 030000 (pentest): sufixos de geração, em MAIÚSCULAS como pessoas.norm_nome devolve
   cross join lateral (select array['JUNIOR', 'JR', 'FILHO', 'FILHA', 'NETO', 'NETA', 'SOBRINHO', 'SOBRINHA', 'SEGUNDO', 'TERCEIRO', 'II', 'III']::text[] suf) sg
   cross join lateral (
     select array['gmail.com','hotmail.com','hotmail.com.br','yahoo.com','yahoo.com.br','outlook.com','outlook.com.br',
                  'icloud.com','live.com','msn.com','bol.com.br','uol.com.br','terra.com.br','globo.com','ig.com.br','me.com','mail.com'] prov
   ) v
   cross join lateral (
     select exists (select 1 from unnest(ip.emails) a, unnest(ic.emails) b
                     where length(split_part(a, '@', 1)) >= 4 and split_part(a, '@', 1) = split_part(b, '@', 1)) local_igual,
            exists (select 1 from unnest(ip.emails) a, unnest(ic.emails) b
                     where length(split_part(a, '@', 1)) >= 4 and split_part(a, '@', 1) = split_part(b, '@', 1)
                       and length(split_part(a, '@', 2)) >= 4 and length(split_part(b, '@', 2)) >= 4
                       and split_part(a, '@', 2) <> split_part(b, '@', 2)
                       and not (split_part(a, '@', 2) = any(v.prov) and split_part(b, '@', 2) = any(v.prov))
                       and (public.similarity(split_part(a, '@', 2), split_part(b, '@', 2)) >= 0.5
                            or split_part(a, '@', 2) like split_part(b, '@', 2) || '%'
                            or split_part(b, '@', 2) like split_part(a, '@', 2) || '%')) typo
   ) e
),
cls as (
  select s.*,
         case when s.teste_dif or s.doc_dif or s.ambos_aluno or s.interno_ambos then null
              when s.tel and s.nome_igual then 'A1_telefone_nome'
              when s.typo and s.nome_igual then 'A2_email_digitado_errado_nome'
              when s.tel and s.typo and s.nome_prim then 'A3_telefone_email_digitado_errado'
              when s.tel and s.nome_sub and not s.sufixo_geracao then 'A4_telefone_nome_contido'
         end a_regra,
         case when s.doc_dif then 'B1_documento_diferente'
              when s.interno_ambos then 'B5_teste_ou_equipe'
              when s.tel and s.prim_dif and not s.local_igual and not s.nome_sub and not s.doc_igual then 'B2_telefone_nome_diferente'
              when s.motivo = 'so_nome' and s.ncand >= 20 and not s.tel and not s.local_igual and not s.doc_igual then 'B3_homonimo_comum'
              when s.motivo = 'so_nome' and s.padrao_algum and not s.tel and not s.email_igual and not s.local_igual and not s.doc_igual then 'B6_nome_padrao_sem_sinal'
              when s.motivo = 'so_nome' and not s.tel and not s.email_igual and not s.local_igual and not s.doc_igual then 'B4_so_nome_sem_sinal'
         end b_regra,
         (s.ambos_aluno and s.email_igual) h1
    from sin s
),
res as (
  select c.rid, c.p,
         count(*) n_pares,
         count(*) filter (where c.a_regra is not null) n_a,
         count(*) filter (where c.b_regra is not null) n_b,
         bool_or(c.h1) h1,
         (array_agg(c.c) filter (where c.a_regra is not null))[1] alvo,
         coalesce(array_agg(distinct c.a_regra) filter (where c.a_regra is not null), '{}') ra,
         coalesce(array_agg(distinct c.b_regra) filter (where c.b_regra is not null), '{}') rb
    from cls c
   group by c.rid, c.p
)
select rev.rid revisao_id, rev.p pessoa_id, rev.motivo,
       case when dup.eh then 'duplicada'
            when res.rid is null then 'humano'
            when res.n_a = 1 and nr.n = 1 then 'mesma'
            when res.n_a = 0 and res.n_b = res.n_pares then 'diferente'
            else 'humano' end acao,
       case when dup.eh then array['D1_revisao_duplicada']
            when res.rid is null then array['H0_sem_candidato']
            when res.n_a = 1 and nr.n = 1 then res.ra
            when res.n_a = 0 and res.n_b = res.n_pares then res.rb
            when res.n_a >= 2 then array['H2_varios_candidatos_iguais']
            when res.n_a = 1 then array['H3_pessoa_com_varias_revisoes']
            when res.h1 then array['H1_alunos_duplicados']
            else array['H9_sem_regra'] end regras,
       case when not dup.eh and res.n_a = 1 and nr.n = 1 then res.alvo end alvo,
       coalesce(res.n_pares, 0)::integer n_pares, coalesce(res.n_a, 0)::integer n_a, coalesce(res.n_b, 0)::integer n_b
  from rev
  left join res on res.rid = rev.rid
 cross join lateral (select count(*) n from pessoas.revisao x
                      where x.status = 'pendente' and x.pessoa_id = any(pessoas.grupo(rev.p))) nr
 -- 030000 (D1): só email_conflito. A mesma pergunta já está pendente com id menor (mesma pessoa, mesmo motivo, mesmo conjunto de candidatas)
 cross join lateral (
   select exists (
     select 1 from pessoas.revisao y
      where rev.motivo = 'email_conflito'
        and y.status = 'pendente' and y.id < rev.rid and y.motivo = rev.motivo
        and pessoas.atual(y.pessoa_id) = rev.p
        and (select array_agg(distinct pessoas.atual(z) order by pessoas.atual(z)) from unnest(y.candidatos) z)
            = (select array_agg(distinct pessoas.atual(z) order by pessoas.atual(z)) from unnest(rev.candidatos) z)) eh
 ) dup
 order by rev.rid
$f$;

-- ===================== 3. um passo (aplica) =====================
-- Igual ao de 010000, mais a ação 'duplicada' (D1): a revisão repetida é APAGADA depois de copiada inteira em arquivo.pessoas_revisao_lote_item.
create or replace function pessoas.revisao_lote_passo(p_lote bigint, p_apos bigint, p_n integer, p_regras text[], p_ids bigint[] default null)
returns jsonb
language plpgsql set search_path to '' as $f$
declare
  r record; x record; v jsonb; v_pa jsonb; v_ultimo bigint := p_apos; v_gemea bigint;
  v_ex int := 0; v_m int := 0; v_d int := 0; v_dup int := 0; v_h int := 0; v_fora int := 0; v_f int := 0; v_erro text;
begin
  if p_lote is null or p_apos is null or p_n is null or p_n not between 1 and 100 or p_regras is null then
    raise exception 'parâmetros inválidos' using errcode = '22023';
  end if;
  for r in select * from pessoas.revisao_classificar(p_apos, p_n, p_ids) loop
    v_ultimo := r.revisao_id; v_ex := v_ex + 1;
    if r.acao = 'humano' then v_h := v_h + 1; continue; end if;
    if not (r.regras <@ p_regras) then v_fora := v_fora + 1; continue; end if;
    begin
      select * into x from pessoas.revisao where id = r.revisao_id and status = 'pendente' for update skip locked;
      if not found then continue; end if;   -- outra pessoa decidiu no meio
      select jsonb_build_object('id', p.id, 'situacao', p.situacao, 'mesclada_em', p.mesclada_em, 'atualizado_em', p.atualizado_em)
        into v_pa from pessoas.pessoas p where p.id = r.pessoa_id for update;
      if r.acao = 'duplicada' then
        -- confere de novo, já com a linha travada, e trava TAMBÉM a gêmea de id menor (for share): enquanto esta transação não termina, ninguém decide nem
        -- apaga a gêmea. Gêmea travada por outra sessão (skip locked) ou que já mudou: não apaga (conta como falha, fica para outra rodada).
        v_gemea := null;
        if x.motivo = 'email_conflito' then
          select y.id into v_gemea from pessoas.revisao y
           where y.status = 'pendente' and y.id < x.id and y.motivo = x.motivo and pessoas.atual(y.pessoa_id) = r.pessoa_id
             and (select array_agg(distinct pessoas.atual(z) order by pessoas.atual(z)) from unnest(y.candidatos) z)
                 = (select array_agg(distinct pessoas.atual(z) order by pessoas.atual(z)) from unnest(x.candidatos) z)
           order by y.id limit 1
             for share of y skip locked;
        end if;
        if v_gemea is null then
          v_f := v_f + 1; continue;
        end if;
        insert into arquivo.pessoas_revisao_lote_item (lote_id, revisao_id, pessoa_id, alvo, acao, regras, rev_antes, pessoa_antes)
        values (p_lote, x.id, r.pessoa_id, null, 'duplicada', r.regras, to_jsonb(x), v_pa);
        delete from pessoas.revisao where id = x.id;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
        values (r.pessoa_id, 'revisao', 'sistema', 'pessoas.revisao', x.id::text,
                jsonb_build_object('decisao', 'duplicada', 'motivo', x.motivo, 'lote', p_lote, 'regras', to_jsonb(r.regras)));
        insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
        values (null, 'revisar', r.pessoa_id, jsonb_build_object('revisao', x.id, 'decisao', 'duplicada', 'lote', p_lote));
        v_dup := v_dup + 1;
        continue;
      end if;
      if r.acao = 'mesma' then
        v := pessoas.mesclar(r.pessoa_id, r.alvo, null);
        if not coalesce((v->>'ok')::boolean, false) then v_f := v_f + 1; continue; end if;   -- ex.: dois alunos diferentes: mesclar recusa
      end if;
      insert into arquivo.pessoas_revisao_lote_item (lote_id, revisao_id, pessoa_id, alvo, acao, regras, rev_antes, pessoa_antes)
      values (p_lote, x.id, r.pessoa_id, r.alvo, r.acao, r.regras, to_jsonb(x), v_pa);
      update pessoas.revisao
         set status = r.acao, decidido_por = null, decidido_em = now(),
             detalhe = detalhe || jsonb_build_object('lote', p_lote, 'regras', to_jsonb(r.regras))
       where id = x.id;
      if r.acao = 'diferente' then
        update pessoas.pessoas set situacao = 'ativa', atualizado_em = now()
         where id = x.pessoa_id and situacao = 'revisar'
           and not exists (select 1 from pessoas.revisao y where y.pessoa_id = x.pessoa_id and y.status = 'pendente');
      end if;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
      values (coalesce(r.alvo, r.pessoa_id), 'revisao', 'sistema', 'pessoas.revisao', x.id::text,
              jsonb_build_object('decisao', r.acao, 'motivo', x.motivo, 'lote', p_lote, 'regras', to_jsonb(r.regras)));
      insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
      values (null, 'revisar', x.pessoa_id, jsonb_build_object('revisao', x.id, 'decisao', r.acao, 'alvo', r.alvo, 'lote', p_lote));
      if r.acao = 'mesma' then v_m := v_m + 1; else v_d := v_d + 1; end if;
    exception when others then
      v_f := v_f + 1; v_erro := coalesce(v_erro, sqlstate);   -- só o código; nunca a mensagem (pode ter dado pessoal)
    end;
  end loop;
  return jsonb_build_object('ultimo', v_ultimo, 'examinadas', v_ex, 'mesmas', v_m, 'diferentes', v_d, 'duplicadas', v_dup, 'humano', v_h,
                            'fora_das_regras', v_fora, 'falhas', v_f, 'primeiro_erro', v_erro);
end
$f$;

-- ===================== 4. a rodada (COMMIT por passo) =====================
-- CALL pessoas.revisao_lote_rodar(array['A1_telefone_nome', ...]);   Sem cláusula SET (ela proibiria o COMMIT).
create or replace procedure pessoas.revisao_lote_rodar(p_regras text[], p_passo integer default 25, p_max_aplicadas integer default 100,
                                                       p_orcamento_s integer default 40, p_apos bigint default 0)
language plpgsql as $p$
declare
  v_sp text := current_setting('search_path'); v_lote bigint; v_t0 timestamptz := clock_timestamp();
  v_ap bigint := p_apos; r jsonb; v_ex int := 0; v_m int := 0; v_d int := 0; v_dup int := 0; v_h int := 0; v_fora int := 0; v_f int := 0;
  v_fim text := 'fim da fila';
begin
  if p_regras is null or cardinality(p_regras) = 0 or p_passo is null or p_passo not between 1 and 100
     or p_max_aplicadas is null or p_max_aplicadas not between 1 and 2000
     or p_orcamento_s is null or p_orcamento_s not between 5 and 90 or p_apos is null or p_apos < 0 then
    raise exception 'revisao_lote: parâmetros inválidos' using errcode = '22023';
  end if;
  if not (p_regras <@ array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'A4_telefone_nome_contido',
                            'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum', 'B4_so_nome_sem_sinal',
                            'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal', 'D1_revisao_duplicada']) then
    raise exception 'revisao_lote: regra desconhecida' using errcode = '22023';
  end if;
  if not coalesce((select ligada and ate is not null and current_date <= ate from pessoas.carga_chave where fonte = 'revisao_lote'), false) then
    raise exception 'revisao_lote: chave desligada (ou sem data de fim). Ver o cabeçalho da migration.' using errcode = '55000';
  end if;
  perform set_config('search_path', '', false);
  insert into pessoas.revisao_lote (regras, tamanho_passo, ultima_revisao_id) values (p_regras, p_passo, p_apos) returning id into v_lote;
  commit;
  loop
    if clock_timestamp() - v_t0 > make_interval(secs => p_orcamento_s) then v_fim := 'orçamento de segundos'; exit; end if;
    if v_m + v_d + v_dup >= p_max_aplicadas then v_fim := 'teto de aplicadas'; exit; end if;
    r := pessoas.revisao_lote_passo(v_lote, v_ap, p_passo, p_regras);
    exit when (r->>'examinadas')::int = 0;
    v_ap := (r->>'ultimo')::bigint;
    v_ex := v_ex + (r->>'examinadas')::int; v_m := v_m + (r->>'mesmas')::int; v_d := v_d + (r->>'diferentes')::int;
    v_dup := v_dup + (r->>'duplicadas')::int;
    v_h := v_h + (r->>'humano')::int; v_fora := v_fora + (r->>'fora_das_regras')::int; v_f := v_f + (r->>'falhas')::int;
    update pessoas.revisao_lote
       set examinadas = v_ex, mesmas = v_m, diferentes = v_d, duplicadas = v_dup, humano = v_h, fora_das_regras = v_fora, falhas = v_f,
           ultima_revisao_id = v_ap, atualizado_em = now()
     where id = v_lote;
    commit;
  end loop;
  update pessoas.revisao_lote set terminou_em = now(), motivo_fim = v_fim, atualizado_em = now() where id = v_lote;
  commit;
  perform set_config('search_path', v_sp, false);
  raise notice 'revisao_lote %: % examinadas, % juntadas, % mantidas separadas, % duplicadas apagadas, % humano, % fora das regras, % falhas; parou por: %; recomeçar de %',
    v_lote, v_ex, v_m, v_d, v_dup, v_h, v_fora, v_f, v_fim, v_ap;
end
$p$;

-- ===================== 5. reverter =====================
create or replace function pessoas.revisao_lote_reverter(p_lote bigint default null, p_max integer default 500) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  i record; p record; v jsonb; v_ok int := 0; v_pul int := 0;
begin
  if p_max is null or p_max not between 1 and 5000 then raise exception 'p_max entre 1 e 5.000' using errcode = '22023'; end if;
  for i in select * from arquivo.pessoas_revisao_lote_item
            where revertido_em is null and (p_lote is null or lote_id = p_lote)
            order by id desc limit p_max for update loop
    begin
      if i.acao = 'duplicada' then
        -- a revisão foi apagada: devolve a linha inteira, com o mesmo id, a partir da cópia
        if exists (select 1 from pessoas.revisao r where r.id = i.revisao_id) then v_pul := v_pul + 1; continue; end if;
        insert into pessoas.revisao overriding system value
        select * from jsonb_populate_record(null::pessoas.revisao, i.rev_antes);
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
        values (i.pessoa_id, 'revisao', 'sistema', 'pessoas.revisao', i.revisao_id::text,
                jsonb_build_object('decisao', 'reaberta', 'lote', i.lote_id));
        insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
        values (null, 'revisar', i.pessoa_id, jsonb_build_object('revisao', i.revisao_id, 'decisao', 'reaberta', 'lote', i.lote_id));
        update arquivo.pessoas_revisao_lote_item set revertido_em = now(), atualizado_em = now() where id = i.id;
        v_ok := v_ok + 1;
        continue;
      end if;
      -- só desfaz o que o lote gravou e que ninguém mexeu depois
      if not exists (select 1 from pessoas.revisao r where r.id = i.revisao_id and r.status = i.acao and r.detalhe->>'lote' = i.lote_id::text) then
        v_pul := v_pul + 1; continue;
      end if;
      if i.acao = 'mesma' then
        select pp.situacao, pp.mesclada_em into p from pessoas.pessoas pp where pp.id = i.pessoa_id for update;
        if p.situacao is distinct from 'mesclada' or p.mesclada_em is distinct from i.alvo then v_pul := v_pul + 1; continue; end if;
        v := pessoas.desfazer_mescla(i.pessoa_id, null);
        if not coalesce((v->>'ok')::boolean, false) then v_pul := v_pul + 1; continue; end if;
        update pessoas.pessoas set situacao = i.pessoa_antes->>'situacao', atualizado_em = (i.pessoa_antes->>'atualizado_em')::timestamptz
         where id = i.pessoa_id;
      elsif i.pessoa_antes->>'situacao' = 'revisar' then
        update pessoas.pessoas set situacao = 'revisar', atualizado_em = (i.pessoa_antes->>'atualizado_em')::timestamptz
         where id = i.pessoa_id and situacao = 'ativa';
      end if;
      update pessoas.revisao
         set status = i.rev_antes->>'status', decidido_por = nullif(i.rev_antes->>'decidido_por', '')::uuid,
             decidido_em = nullif(i.rev_antes->>'decidido_em', '')::timestamptz, detalhe = i.rev_antes->'detalhe'
       where id = i.revisao_id;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
      values (coalesce(i.alvo, i.pessoa_id), 'revisao', 'sistema', 'pessoas.revisao', i.revisao_id::text,
              jsonb_build_object('decisao', 'reaberta', 'lote', i.lote_id));
      insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
      values (null, case when i.acao = 'mesma' then 'desfazer_mescla' else 'revisar' end, i.pessoa_id,
              jsonb_build_object('revisao', i.revisao_id, 'decisao', 'reaberta', 'lote', i.lote_id));
      update arquivo.pessoas_revisao_lote_item set revertido_em = now(), atualizado_em = now() where id = i.id;
      v_ok := v_ok + 1;
    exception when others then
      v_pul := v_pul + 1;
    end;
  end loop;
  return jsonb_build_object('revertidas', v_ok, 'puladas', v_pul);
end
$f$;

-- ===================== 6. permissões =====================
revoke all on function pessoas.revisao_classificar(bigint, integer, bigint[]), pessoas.revisao_lote_passo(bigint, bigint, integer, text[], bigint[]),
  pessoas.revisao_lote_reverter(bigint, integer) from public, anon, authenticated, service_role;
revoke all on procedure pessoas.revisao_lote_rodar(text[], integer, integer, integer, bigint) from public, anon, authenticated, service_role;


set local statement_timeout = '250s';   -- a migration acima baixou para 60s; o dry-run na fila real precisa de mais

-- ===== checagens =====
insert into pg_temp._z_out(passo, linha)
select '01 grants (esperado: tudo false)', jsonb_build_object(
  'anon_executa_classificar', has_function_privilege('anon', 'pessoas.revisao_classificar(bigint,integer,bigint[])', 'execute'),
  'authenticated_executa_classificar', has_function_privilege('authenticated', 'pessoas.revisao_classificar(bigint,integer,bigint[])', 'execute'),
  'authenticated_executa_passo', has_function_privilege('authenticated', 'pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])', 'execute'),
  'authenticated_executa_reverter', has_function_privilege('authenticated', 'pessoas.revisao_lote_reverter(bigint,integer)', 'execute'),
  'authenticated_executa_rodar', has_function_privilege('authenticated', 'pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)', 'execute'),
  'service_role_executa_passo', has_function_privilege('service_role', 'pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])', 'execute'),
  'anon_le_item', has_table_privilege('anon', 'arquivo.pessoas_revisao_lote_item', 'select'),
  'authenticated_le_lote', has_table_privilege('authenticated', 'pessoas.revisao_lote', 'select'))::text;
insert into pg_temp._z_out(passo, linha)
select '02 rls ligada (esperado: true, true)', (select relrowsecurity::text from pg_class where oid = 'pessoas.revisao_lote'::regclass) || ', '
    || (select relrowsecurity::text from pg_class where oid = 'arquivo.pessoas_revisao_lote_item'::regclass);
insert into pg_temp._z_out(passo, linha)
select '03 chave depois da migration (esperado: ligada=false, ate=null mesmo com a chave ligada com data antes, por=migration 20261017030000)', jsonb_build_object('ligada', ligada, 'ate', ate, 'por', por)::text
  from pessoas.carga_chave where fonte = 'revisao_lote';
insert into pg_temp._z_out(passo, linha)
select '03b coluna, CHECK e marcador (esperado: duplicadas existe; check cita duplicada; 1 marcador)', jsonb_build_object(
  'tem_duplicadas', exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'revisao_lote' and column_name = 'duplicadas'),
  'check_cita_duplicada', (select pg_get_constraintdef(oid) like '%duplicada%' from pg_constraint where conname = 'pessoas_revisao_lote_item_acao_check'),
  'marcadores', (select count(*) from pessoas.revisao_lote where motivo_fim = 'marcador 20261017030000'))::text;

do $t$
declare v1 text; v2 text; v3 text; v4 text;
begin
  begin call pessoas.revisao_lote_rodar(array['A4_telefone_nome_contido']); v1 := 'SEM ERRO (errado)'; exception when others then v1 := sqlstate; end;
  begin call pessoas.revisao_lote_rodar(array['D1_revisao_duplicada', 'B4_so_nome_sem_sinal', 'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal']); v2 := 'SEM ERRO (errado)'; exception when others then v2 := sqlstate; end;
  begin call pessoas.revisao_lote_rodar(null); v3 := 'SEM ERRO (errado)'; exception when others then v3 := sqlstate; end;
  begin call pessoas.revisao_lote_rodar(array['X_inventada']); v4 := 'SEM ERRO (errado)'; exception when others then v4 := sqlstate; end;
  insert into pg_temp._z_out(passo, linha)
  values ('04 guardas da procedure (esperado: 55000 A4 aceita e chave desligada, 55000 D1/B4/B5/B6 aceitas, 22023 nulo, 22023 regra desconhecida)', v1 || ', ' || v2 || ', ' || v3 || ', ' || v4);
end
$t$;

-- ===== contagem na fila REAL (só leitura) =====
insert into pg_temp._z_out(passo, linha)
select '10 fila real por nível', coalesce(jsonb_object_agg(acao, n)::text, '{}')
  from (select acao, count(*) n from pessoas.revisao_classificar(0, 100000) group by acao) x;
insert into pg_temp._z_out(passo, linha)
select '11 fila real por regra', acao || ' | ' || array_to_string(regras, ',') || ' | ' || n
  from (select acao, regras, count(*) n from pessoas.revisao_classificar(0, 100000) group by acao, regras) x order by 1;

-- ===== dry-run na fila REAL: aplica TUDO (tudo será desfeito), confere falhas = 0 e reverte =====
create temp table _z_h0 as
select 'revisao' k, md5(coalesce(string_agg(to_jsonb(r)::text, '|' order by r.id), '')) v from pessoas.revisao r
union all select 'pessoas', md5(coalesce(string_agg(p.id::text || coalesce(p.situacao, '') || coalesce(p.mesclada_em::text, '') || p.atualizado_em::text, '|' order by p.id), '')) from pessoas.pessoas p
union all select 'identificadores', count(*)::text from pessoas.identificadores
union all select 'thb_alunos', count(*)::text from public.thb_alunos
union all select 'compradores', count(*)::text from public.compradores
union all select 'crm_negocio', count(*)::text from crm.negocio;
do $t$
declare
  v_lote bigint; v_ap bigint := 0; r jsonb; v_ex int := 0; v_m int := 0; v_d int := 0; v_dup int := 0; v_h int := 0; v_fora int := 0; v_f int := 0;
  v_regras text[] := array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'A4_telefone_nome_contido', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum', 'B4_so_nome_sem_sinal', 'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal', 'D1_revisao_duplicada'];
begin
  insert into pessoas.revisao_lote (regras, tamanho_passo) values (v_regras, 25) returning id into v_lote;
  insert into pg_temp._z values ('lote_real', v_lote::text);
  loop
    r := pessoas.revisao_lote_passo(v_lote, v_ap, 25, v_regras);
    exit when (r->>'examinadas')::int = 0;
    v_ap := (r->>'ultimo')::bigint;
    v_ex := v_ex + (r->>'examinadas')::int; v_m := v_m + (r->>'mesmas')::int; v_d := v_d + (r->>'diferentes')::int; v_dup := v_dup + (r->>'duplicadas')::int;
    v_h := v_h + (r->>'humano')::int; v_fora := v_fora + (r->>'fora_das_regras')::int; v_f := v_f + (r->>'falhas')::int;
  end loop;
  insert into pg_temp._z_out(passo, linha)
  values ('12 dry-run na fila real, todas as regras (esperado: falhas 0; diferentes 257, duplicadas 64; mesmas 36 e humano 72 (A4 32 depois do pentest), porque 1 revisão humana vira A1 depois que as outras fecham: o classificador lê o estado vivo a cada passo)',
          jsonb_build_object('examinadas', v_ex, 'mesmas', v_m, 'diferentes', v_d, 'duplicadas', v_dup, 'humano', v_h, 'fora_das_regras', v_fora, 'falhas', v_f)::text);
end
$t$;
insert into pg_temp._z_out(passo, linha)
select '13 fila que sobra depois do dry-run (esperado: 72 pendentes, 1 mesma A1 + 71 humano: precisa de uma segunda rodada)', jsonb_build_object(
  'pendentes', (select count(*) from pessoas.revisao where status = 'pendente'),
  'por_nivel', (select coalesce(jsonb_object_agg(acao, n), '{}') from (select acao, count(*) n from pessoas.revisao_classificar(0, 100000) group by acao) x),
  'por_regra', (select coalesce(jsonb_object_agg(r, n), '{}') from (select array_to_string(regras, ',') r, count(*) n from pessoas.revisao_classificar(0, 100000) group by regras) x),
  'itens_de_copia', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote_real')))::text;
insert into pg_temp._z_out(passo, linha)
select '14 reverter o dry-run (esperado: puladas 0, revertidas = 357 = 36 + 257 + 64)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote_real'), 5000)::text;
create temp table _z_h1 as
select 'revisao' k, md5(coalesce(string_agg(to_jsonb(r)::text, '|' order by r.id), '')) v from pessoas.revisao r
union all select 'pessoas', md5(coalesce(string_agg(p.id::text || coalesce(p.situacao, '') || coalesce(p.mesclada_em::text, '') || p.atualizado_em::text, '|' order by p.id), '')) from pessoas.pessoas p
union all select 'identificadores', count(*)::text from pessoas.identificadores
union all select 'thb_alunos', count(*)::text from public.thb_alunos
union all select 'compradores', count(*)::text from public.compradores
union all select 'crm_negocio', count(*)::text from crm.negocio;
insert into pg_temp._z_out(passo, linha)
select '15 estado depois de reverter o dry-run, comparado com o de antes (esperado: nenhum item diferente; itens nao revertidos 0)', jsonb_build_object(
  'diferentes', (select coalesce(jsonb_agg(a.k), '[]') from pg_temp._z_h0 a join pg_temp._z_h1 b using (k) where a.v is distinct from b.v),
  'itens_nao_revertidos', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote_real') and revertido_em is null))::text;

-- ===== cenário fictício, isolado por p_ids =====
do $t$
declare
  a1 uuid; p1 uuid; c2a uuid; c2b uuid; p2 uuid; a3 uuid; p3 uuid; a3b uuid; p3b uuid; a4 uuid; p4 uuid; a5 uuid; p5 uuid; a6 uuid; p6 uuid;
  a7 uuid; p7 uuid; a8 uuid; p8 uuid; a9 uuid; p9 uuid; a10 uuid; p10 uuid; a11 uuid; p11 uuid; a12 uuid; p12 uuid; a13 uuid; p13 uuid;
  r1 bigint; r2 bigint; r3 bigint; r3b bigint; r4 bigint; r5 bigint; r6 bigint; r7a bigint; r7b bigint; r8a bigint; r8b bigint; r9a bigint; r9b bigint; r10 bigint; r11 bigint; r12 bigint; r13 bigint;
begin
  -- 1 A4: mesmo telefone, 'Zzmaria Silva' contido em 'Zzmaria Silva Souza'
  insert into pessoas.pessoas (nome) values ('Zzmaria Silva Souza') returning id into a1;
  insert into pessoas.pessoas (nome, situacao) values ('Zzmaria Silva', 'revisar') returning id into p1;
  -- 2 A4 com DUAS candidatas que batem: vira H2. (A segunda era 'Lima Neto'; com a regra de sufixo de geração do pentest 'Neto' tira o par da A4,
  --   então a segunda candidata válida passou a ser 'Santos'. O 'Neto' ficou provado nos cenários 9 a 11.)
  insert into pessoas.pessoas (nome) values ('Zzjoao Pereira Lima') returning id into c2a;
  insert into pessoas.pessoas (nome) values ('Zzjoao Pereira Santos') returning id into c2b;
  insert into pessoas.pessoas (nome, situacao) values ('Zzjoao Pereira', 'revisar') returning id into p2;
  -- 3 B4: so_nome sem nenhum sinal
  insert into pessoas.pessoas (nome) values ('Zzcarla Bastos Lima') returning id into a3;
  insert into pessoas.pessoas (nome, situacao) values ('Zzcarla Bastos', 'revisar') returning id into p3;
  -- 3b negativo: so_nome COM telefone igual e nomes que não se contêm: não vira B4 (humano H9)
  insert into pessoas.pessoas (nome) values ('Zzpedro Alves') returning id into a3b;
  insert into pessoas.pessoas (nome, situacao) values ('Zzpedro Costa', 'revisar') returning id into p3b;
  -- 4 B6: so_nome sem sinal e a pessoa já teve o nome padrão tirado
  insert into pessoas.pessoas (nome) values ('Zzclara Dias Neto') returning id into a4;
  insert into pessoas.pessoas (nome, situacao) values ('Zzclara Dias', 'revisar') returning id into p4;
  insert into arquivo.pessoas_nome_padrao_item (pessoa_id, chave, nome_antes, atualizado_em_antes) values (p4, 'zzensaio-padrao', 'Zzclara Dias', now());
  -- 5 B5 por pessoas.teste dos dois lados, mesmo telefone
  insert into pessoas.pessoas (nome, teste) values ('Zzteste Um', true) returning id into a5;
  insert into pessoas.pessoas (nome, situacao, teste) values ('Zzteste Dois', 'revisar', true) returning id into p5;
  -- 6 B5 por prefixo de nome da lista (IROMAR), sem a marca teste, mesmo telefone
  insert into pessoas.pessoas (nome) values ('Iromar Zzum') returning id into a6;
  insert into pessoas.pessoas (nome, situacao) values ('Iromar Zzdois', 'revisar') returning id into p6;
  -- 7 D1: duas revisões email_conflito idênticas (a de id maior é a duplicada)
  insert into pessoas.pessoas (nome) values ('Zzdup Candidato') returning id into a7;
  insert into pessoas.pessoas (nome, situacao) values ('Zzdup Pessoa', 'revisar') returning id into p7;
  -- 8 escopo da D1: duas so_nome idênticas NÃO são duplicata (as duas viram B4)
  insert into pessoas.pessoas (nome) values ('Zzrita Neves Dantas') returning id into a8;
  insert into pessoas.pessoas (nome, situacao) values ('Zzrita Neves', 'revisar') returning id into p8;
  -- 9 (pentest) A4 NÃO vale: a diferença entre os nomes é 'Filho' (provável pai e filho, mesmo telefone): humano H9
  insert into pessoas.pessoas (nome) values ('Zzpaulo Mendes Filho') returning id into a9;
  insert into pessoas.pessoas (nome, situacao) values ('Zzpaulo Mendes', 'revisar') returning id into p9;
  -- 10 (pentest) A4 NÃO vale, no sentido contrário: a pessoa da revisão é a de nome maior ('Junior'): humano H9
  insert into pessoas.pessoas (nome) values ('Zzlucas Reis') returning id into a10;
  insert into pessoas.pessoas (nome, situacao) values ('Zzlucas Reis Junior', 'revisar') returning id into p10;
  -- 11 (pentest) o sufixo está nos DOIS nomes: a diferença é só 'Silva', A4 vale: mesma
  insert into pessoas.pessoas (nome) values ('Zzrui Lopes Neto Silva') returning id into a11;
  insert into pessoas.pessoas (nome, situacao) values ('Zzrui Lopes Neto', 'revisar') returning id into p11;
  -- 12 (pentest) e-mail @advmais.com.br NÃO é interno (domínio exato): não vira B5, A4 vale: mesma
  insert into pessoas.pessoas (nome) values ('Zzana Moura Reis') returning id into a12;
  insert into pessoas.pessoas (nome, situacao) values ('Zzana Moura', 'revisar') returning id into p12;
  -- 13 (pentest) e-mail @advmais.com exato dos dois lados: interno, B5 bloqueia a A4: diferente
  insert into pessoas.pessoas (nome) values ('Zzbia Souza Lima') returning id into a13;
  insert into pessoas.pessoas (nome, situacao) values ('Zzbia Souza', 'revisar') returning id into p13;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values
    (a1, 'telefone', '5599900030001', '5599900030001', 'importacao'), (p1, 'telefone', '5599900030001', '5599900030001', 'importacao'),
    (c2a, 'telefone', '5599900030002', '5599900030002', 'importacao'), (c2b, 'telefone', '5599900030002', '5599900030002', 'importacao'),
    (p2, 'telefone', '5599900030002', '5599900030002', 'importacao'),
    (a3b, 'telefone', '5599900030003', '5599900030003', 'importacao'), (p3b, 'telefone', '5599900030003', '5599900030003', 'importacao'),
    (a5, 'telefone', '5599900030005', '5599900030005', 'importacao'), (p5, 'telefone', '5599900030005', '5599900030005', 'importacao'),
    (a6, 'telefone', '5599900030006', '5599900030006', 'importacao'), (p6, 'telefone', '5599900030006', '5599900030006', 'importacao'),
    (a9, 'telefone', '5599900030009', '5599900030009', 'importacao'), (p9, 'telefone', '5599900030009', '5599900030009', 'importacao'),
    (a10, 'telefone', '5599900030010', '5599900030010', 'importacao'), (p10, 'telefone', '5599900030010', '5599900030010', 'importacao'),
    (a11, 'telefone', '5599900030011', '5599900030011', 'importacao'), (p11, 'telefone', '5599900030011', '5599900030011', 'importacao'),
    (a12, 'telefone', '5599900030012', '5599900030012', 'importacao'), (p12, 'telefone', '5599900030012', '5599900030012', 'importacao'),
    (a13, 'telefone', '5599900030013', '5599900030013', 'importacao'), (p13, 'telefone', '5599900030013', '5599900030013', 'importacao'),
    (a12, 'email', 'zzana1@advmais.com.br', 'zzana1@advmais.com.br', 'importacao'), (p12, 'email', 'zzana2@advmais.com.br', 'zzana2@advmais.com.br', 'importacao'),
    (a13, 'email', 'zzbia1@advmais.com', 'zzbia1@advmais.com', 'importacao'), (p13, 'email', 'zzbia2@advmais.com', 'zzbia2@advmais.com', 'importacao');
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p1, 'telefone_nome_diferente', array[a1]) returning id into r1;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p2, 'telefone_varios', array[c2a, c2b]) returning id into r2;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p3, 'so_nome', array[a3]) returning id into r3;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p3b, 'so_nome', array[a3b]) returning id into r3b;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p4, 'so_nome', array[a4]) returning id into r4;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p5, 'telefone_varios', array[a5]) returning id into r5;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p6, 'telefone_varios', array[a6]) returning id into r6;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p7, 'email_conflito', array[a7]) returning id into r7a;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p7, 'email_conflito', array[a7]) returning id into r7b;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p8, 'so_nome', array[a8]) returning id into r8a;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p8, 'so_nome', array[a8]) returning id into r8b;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p9, 'telefone_nome_diferente', array[a9]) returning id into r9a;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p10, 'telefone_nome_diferente', array[a10]) returning id into r10;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p11, 'telefone_nome_diferente', array[a11]) returning id into r11;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p12, 'telefone_nome_diferente', array[a12]) returning id into r12;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p13, 'telefone_nome_diferente', array[a13]) returning id into r13;
  insert into pg_temp._z values ('ids', array[r1, r2, r3, r3b, r4, r5, r6, r7a, r7b, r8a, r8b, r9a, r10, r11, r12, r13]::text),
    ('r1', r1::text), ('r7b', r7b::text), ('r7a', r7a::text), ('p1', p1::text), ('a1', a1::text);
end
$t$;
insert into pg_temp._z_out(passo, linha)
select '20 classificação do cenário (esperado por ordem: mesma A4; humano H2; diferente B4; humano H9 (so_nome com telefone); diferente B6; diferente B5; diferente B5; humano H9 (primeira email_conflito); duplicada D1 (a de id maior); diferente B4; diferente B4; humano H9 (A4 barrada por FILHO); humano H9 (A4 barrada por JUNIOR); mesma A4 (sufixo nos dois nomes); mesma A4 (advmais.com.br não é interno); diferente B5 (advmais.com exato))',
       revisao_id - (select min(x) from (select unnest(v::bigint[]) x from pg_temp._z where k = 'ids') m) + 1 || ' | ' || acao || ' | ' || array_to_string(regras, ',')
  from pessoas.revisao_classificar(0, 100, (select v::bigint[] from pg_temp._z where k = 'ids')) order by revisao_id;

create temp table _z_antes as
select r.id, to_jsonb(r) j from pessoas.revisao r where r.id in (select unnest(v::bigint[]) from pg_temp._z where k = 'ids');
create temp table _z_pantes as
select p.id, p.situacao, p.mesclada_em, p.atualizado_em from pessoas.pessoas p where p.nome like 'Zz%' or p.nome like 'Iromar Zz%';
create temp table _z_h2 as
select 'revisao' k, md5(coalesce(string_agg(to_jsonb(r)::text, '|' order by r.id), '')) v from pessoas.revisao r
union all select 'pessoas', md5(coalesce(string_agg(p.id::text || coalesce(p.situacao, '') || coalesce(p.mesclada_em::text, '') || p.atualizado_em::text, '|' order by p.id), '')) from pessoas.pessoas p
union all select 'identificadores', count(*)::text from pessoas.identificadores
union all select 'thb_alunos', count(*)::text from public.thb_alunos
union all select 'compradores', count(*)::text from public.compradores
union all select 'crm_negocio', count(*)::text from crm.negocio;

insert into pessoas.revisao_lote (regras, tamanho_passo) values (array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'A4_telefone_nome_contido', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum', 'B4_so_nome_sem_sinal', 'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal', 'D1_revisao_duplicada'], 50);
insert into pg_temp._z select 'lote', max(id)::text from pessoas.revisao_lote;

insert into pg_temp._z_out(passo, linha)
select '21 passo só com a regra B4 (esperado: diferentes 3 (r3 e as duas so_nome iguais), mesmas 0, duplicadas 0; o resto em fora_das_regras ou humano)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['B4_so_nome_sem_sinal'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '21b passo com todas as regras (esperado: mesmas 3 (A4 de r1, r11, r12), diferentes 4 (B6, B5, B5, B5 de r13), duplicadas 1, humano 5 (H2, H9 do so_nome com telefone, H9 da primeira email_conflito, H9 de FILHO, H9 de JUNIOR), falhas 0)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'A4_telefone_nome_contido', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum', 'B4_so_nome_sem_sinal', 'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal', 'D1_revisao_duplicada'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '22 estado depois dos passos 21 e 21b', jsonb_build_object(
  'status_por_revisao', (select jsonb_agg(status order by id) from pessoas.revisao where id in (select unnest(v::bigint[]) from pg_temp._z where k = 'ids')),
  'r7b_existe', exists (select 1 from pessoas.revisao where id = (select v::bigint from pg_temp._z where k = 'r7b')),
  'r7a_pendente', exists (select 1 from pessoas.revisao where status = 'pendente' and id = (select v::bigint from pg_temp._z where k = 'r7a')),
  'p1_mesclada_na_a1', (select mesclada_em = (select v::uuid from pg_temp._z where k = 'a1') from pessoas.pessoas where id = (select v::uuid from pg_temp._z where k = 'p1')),
  'itens_de_copia', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote')),
  'itens_duplicada', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote') and acao = 'duplicada'),
  'copia_com_arroba', (select count(*) from arquivo.pessoas_revisao_lote_item where rev_antes::text ~ '@' or pessoa_antes::text ~ '@'))::text;
insert into pg_temp._z_out(passo, linha)
select '23 passo de novo, mesmas regras (idempotente; esperado: mesmas 0, diferentes 0, duplicadas 0, falhas 0)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'A4_telefone_nome_contido', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum', 'B4_so_nome_sem_sinal', 'B5_teste_ou_equipe', 'B6_nome_padrao_sem_sinal', 'D1_revisao_duplicada'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '24 regra fora do CALL fica de fora (esperado: so D1 pedida, nada pendente é D1 agora: duplicadas 0)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['D1_revisao_duplicada'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;

insert into pg_temp._z_out(passo, linha)
select '30 reverter (esperado: revertidas = 11 = 3 B4 + 3 mesmas + 4 diferentes + 1 duplicada, puladas 0)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote'), 100)::text;
insert into pg_temp._z_out(passo, linha)
select '31 estado depois de reverter, comparado com o de antes (esperado: revisoes_diferentes 0, pessoas_diferentes 0, hash global sem diferença, nao revertidos 0)', jsonb_build_object(
  'revisoes_diferentes_do_antes', (select count(*) from pg_temp._z_antes z left join pessoas.revisao r on r.id = z.id where to_jsonb(r) is distinct from z.j),
  'pessoas_diferentes_do_antes', (select count(*) from pg_temp._z_pantes z left join pessoas.pessoas p on p.id = z.id
                                   where p.situacao is distinct from z.situacao or p.mesclada_em is distinct from z.mesclada_em or p.atualizado_em is distinct from z.atualizado_em),
  'hash_global_diferente', (select coalesce(jsonb_agg(a.k), '[]') from pg_temp._z_h2 a join (
        select 'revisao' k, md5(coalesce(string_agg(to_jsonb(r)::text, '|' order by r.id), '')) v from pessoas.revisao r
        union all select 'pessoas', md5(coalesce(string_agg(p.id::text || coalesce(p.situacao, '') || coalesce(p.mesclada_em::text, '') || p.atualizado_em::text, '|' order by p.id), '')) from pessoas.pessoas p
        union all select 'identificadores', count(*)::text from pessoas.identificadores
        union all select 'thb_alunos', count(*)::text from public.thb_alunos
        union all select 'compradores', count(*)::text from public.compradores
        union all select 'crm_negocio', count(*)::text from crm.negocio) b using (k) where a.v is distinct from b.v),
  'itens_nao_revertidos', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote') and revertido_em is null))::text;
insert into pg_temp._z_out(passo, linha)
select '32 reverter de novo (esperado: revertidas 0, puladas 0)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote'), 100)::text;
insert into pg_temp._z_out(passo, linha)
select '33 depois de reverter, aplicar de novo funciona (esperado: duplicadas 1, mesmas 3; índice único parcial livre)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['A4_telefone_nome_contido', 'D1_revisao_duplicada'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '34 reverter o passo 33 (esperado: revertidas 4)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote'), 100)::text;

-- ===== reversão (20261017030000_reversao.sql) dentro do ensaio =====
-- Reversão de 20261017030000: desfaz os lotes feitos DEPOIS desta migration e devolve os 4 corpos de 20261017010000.
-- Os lotes anteriores (de 20261017010000) não são tocados. Coluna pessoas.revisao_lote.duplicadas e o CHECK alargado FICAM (histórico, nunca se apaga).
-- Aborta, sem trocar nenhum corpo, se sobrar item que não deu para reverter (alguém mexeu na revisão ou na pessoa depois do lote): olhar à mão.
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $r$
declare v_marc bigint; l record; v jsonb; n int;
begin
  select id into v_marc from pessoas.revisao_lote where motivo_fim = 'marcador 20261017030000' order by id limit 1;
  if v_marc is null then
    raise exception '20261017030000: reversão sem efeito, a migration não está aplicada (sem marcador).';
  end if;
  for l in select id from pessoas.revisao_lote where id > v_marc order by id desc loop
    v := pessoas.revisao_lote_reverter(l.id, 5000);
  end loop;
  select count(*) into n from arquivo.pessoas_revisao_lote_item where lote_id > v_marc and revertido_em is null;
  if n > 0 then
    raise exception '20261017030000: % item(ns) sem reverter. Nada foi trocado; conferir à mão.', n;
  end if;
  update pessoas.carga_chave set ligada = false, ate = null, por = 'reversao 20261017030000', em = now() where fonte = 'revisao_lote';
end
$r$;

-- devolve os 4 corpos de 20261017010000 (texto copiado da migration, create or replace)
-- ===================== 2. classificador (só leitura) =====================
-- Uma linha por revisão pendente com id > p_apos (ordem do id, no máximo p_limite). acao: mesma | diferente | humano.
-- 'mesma' só se EXATAMENTE 1 candidato bate numa regra A e a pessoa só tem esta revisão pendente.
-- 'diferente' só se TODOS os candidatos batem numa regra B e nenhum numa regra A.
create or replace function pessoas.revisao_classificar(p_apos bigint, p_limite integer, p_ids bigint[] default null)
returns table (revisao_id bigint, pessoa_id uuid, motivo text, acao text, regras text[], alvo uuid, n_pares integer, n_a integer, n_b integer)
language sql stable set search_path to '' as $f$
with rev as (
  select r.id rid, pessoas.atual(r.pessoa_id) p, r.motivo, r.candidatos
    from pessoas.revisao r
   where r.status = 'pendente' and r.id > p_apos and (p_ids is null or r.id = any(p_ids))
   order by r.id
   limit p_limite
),
par as (
  select rev.rid, rev.p, rev.motivo, cardinality(rev.candidatos) ncand, k.c
    from rev
   cross join lateral (select distinct pessoas.atual(x) c from unnest(rev.candidatos) x) k
   where k.c is not null and k.c <> rev.p
),
pes as (select p x from rev union select c from par),
info as (
  select x.x, d.nome, d.eh_aluno, d.teste,
         array(select i.chave from pessoas.identificadores i where i.pessoa_id = any(d.g) and i.tipo = 'email') || d.emails_ref emails,
         array(select i.chave from pessoas.identificadores i where i.pessoa_id = any(d.g) and i.tipo = 'telefone') || d.fones_ref fones,
         d.cpfs
    from pes x
   cross join lateral (
     select g.g,
            coalesce((array_agg(a.nome order by pp.id = x.x desc) filter (where a.nome is not null))[1],
                     (array_agg(cp.nome::text order by pp.id = x.x desc) filter (where cp.nome is not null))[1],
                     (array_agg(pp.nome order by pp.id = x.x desc) filter (where pp.nome is not null))[1]) nome,
            coalesce(bool_or(pp.aluno_id is not null), false) eh_aluno,
            coalesce(bool_or(pp.teste), false) teste,
            coalesce(array_agg(lower(btrim(a.email))) filter (where nullif(btrim(a.email), '') is not null), '{}')
              || coalesce(array_agg(lower(btrim(cp.email::text))) filter (where nullif(btrim(cp.email::text), '') is not null), '{}') emails_ref,
            coalesce(array_agg(controle.fone_key(coalesce(a.telefone_e164, a.telefone)))
                       filter (where controle.fone_key(coalesce(a.telefone_e164, a.telefone)) is not null), '{}')
              || coalesce(array_agg(controle.fone_key(cp.telefone::text))
                       filter (where controle.fone_key(cp.telefone::text) is not null), '{}') fones_ref,
            -- só CPF (11 dígitos), só para comparar; nunca sai desta consulta
            coalesce(array_agg(regexp_replace(a.documento::text, '\D', '', 'g'))
                       filter (where length(regexp_replace(a.documento::text, '\D', '', 'g')) = 11), '{}')
              || coalesce(array_agg(regexp_replace(cp.documento::text, '\D', '', 'g'))
                       filter (where length(regexp_replace(cp.documento::text, '\D', '', 'g')) = 11), '{}') cpfs
       from (select pessoas.grupo(x.x) g) g
       join pessoas.pessoas pp on pp.id = any(g.g)
       left join public.thb_alunos a on a.id = pp.aluno_id
       left join public.compradores cp on cp.id = pp.comprador_id
      group by g.g
   ) d
),
sin as (
  select par.rid, par.p, par.c, par.motivo, par.ncand,
         (ip.fones && ic.fones) tel,
         (ip.emails && ic.emails) email_igual,
         (ip.cpfs && ic.cpfs) doc_igual,
         (cardinality(ip.cpfs) > 0 and cardinality(ic.cpfs) > 0 and not ip.cpfs && ic.cpfs) doc_dif,
         (ip.eh_aluno and ic.eh_aluno) ambos_aluno,
         (ip.teste is distinct from ic.teste) teste_dif,
         (n.np is not null and n.np = n.nc and n.np like '% %') nome_igual,
         (coalesce(cardinality(t.tp), 0) >= 2 and coalesce(cardinality(t.tc), 0) >= 2 and t.tp[1] = t.tc[1]
            and (t.tp <@ t.tc or t.tc <@ t.tp)) nome_sub,
         (t.tp[1] is not null and t.tp[1] = t.tc[1]) nome_prim,
         (t.tp[1] is not null and t.tc[1] is not null and left(t.tp[1], 1) <> left(t.tc[1], 1)
            and position(t.tp[1] in t.tc[1]) = 0 and position(t.tc[1] in t.tp[1]) = 0
            and public.similarity(t.tp[1], t.tc[1]) < 0.3) prim_dif,
         e.local_igual, e.typo
    from par
    join info ip on ip.x = par.p
    join info ic on ic.x = par.c
   cross join lateral (select pessoas.norm_nome(ip.nome) np, pessoas.norm_nome(ic.nome) nc) n
   cross join lateral (select string_to_array(n.np, ' ') tp, string_to_array(n.nc, ' ') tc) t
   cross join lateral (
     select array['gmail.com','hotmail.com','hotmail.com.br','yahoo.com','yahoo.com.br','outlook.com','outlook.com.br',
                  'icloud.com','live.com','msn.com','bol.com.br','uol.com.br','terra.com.br','globo.com','ig.com.br','me.com','mail.com'] prov
   ) v
   cross join lateral (
     select exists (select 1 from unnest(ip.emails) a, unnest(ic.emails) b
                     where length(split_part(a, '@', 1)) >= 4 and split_part(a, '@', 1) = split_part(b, '@', 1)) local_igual,
            exists (select 1 from unnest(ip.emails) a, unnest(ic.emails) b
                     where length(split_part(a, '@', 1)) >= 4 and split_part(a, '@', 1) = split_part(b, '@', 1)
                       and length(split_part(a, '@', 2)) >= 4 and length(split_part(b, '@', 2)) >= 4
                       and split_part(a, '@', 2) <> split_part(b, '@', 2)
                       and not (split_part(a, '@', 2) = any(v.prov) and split_part(b, '@', 2) = any(v.prov))
                       and (public.similarity(split_part(a, '@', 2), split_part(b, '@', 2)) >= 0.5
                            or split_part(a, '@', 2) like split_part(b, '@', 2) || '%'
                            or split_part(b, '@', 2) like split_part(a, '@', 2) || '%')) typo
   ) e
),
cls as (
  select s.*,
         case when s.teste_dif or s.doc_dif or s.ambos_aluno then null
              when s.tel and s.nome_igual then 'A1_telefone_nome'
              when s.typo and s.nome_igual then 'A2_email_digitado_errado_nome'
              when s.tel and s.typo and s.nome_prim then 'A3_telefone_email_digitado_errado'
         end a_regra,
         case when s.doc_dif then 'B1_documento_diferente'
              when s.tel and s.prim_dif and not s.local_igual and not s.nome_sub and not s.doc_igual then 'B2_telefone_nome_diferente'
              when s.motivo = 'so_nome' and s.ncand >= 20 and not s.tel and not s.local_igual and not s.doc_igual then 'B3_homonimo_comum'
         end b_regra,
         (s.ambos_aluno and s.email_igual) h1
    from sin s
),
res as (
  select c.rid, c.p,
         count(*) n_pares,
         count(*) filter (where c.a_regra is not null) n_a,
         count(*) filter (where c.b_regra is not null) n_b,
         bool_or(c.h1) h1,
         (array_agg(c.c) filter (where c.a_regra is not null))[1] alvo,
         coalesce(array_agg(distinct c.a_regra) filter (where c.a_regra is not null), '{}') ra,
         coalesce(array_agg(distinct c.b_regra) filter (where c.b_regra is not null), '{}') rb
    from cls c
   group by c.rid, c.p
)
select rev.rid revisao_id, rev.p pessoa_id, rev.motivo,
       case when res.rid is null then 'humano'
            when res.n_a = 1 and nr.n = 1 then 'mesma'
            when res.n_a = 0 and res.n_b = res.n_pares then 'diferente'
            else 'humano' end acao,
       case when res.rid is null then array['H0_sem_candidato']
            when res.n_a = 1 and nr.n = 1 then res.ra
            when res.n_a = 0 and res.n_b = res.n_pares then res.rb
            when res.n_a >= 2 then array['H2_varios_candidatos_iguais']
            when res.n_a = 1 then array['H3_pessoa_com_varias_revisoes']
            when res.h1 then array['H1_alunos_duplicados']
            else array['H9_sem_regra'] end regras,
       case when res.n_a = 1 and nr.n = 1 then res.alvo end alvo,
       coalesce(res.n_pares, 0)::integer n_pares, coalesce(res.n_a, 0)::integer n_a, coalesce(res.n_b, 0)::integer n_b
  from rev
  left join res on res.rid = rev.rid
 cross join lateral (select count(*) n from pessoas.revisao x
                      where x.status = 'pendente' and x.pessoa_id = any(pessoas.grupo(rev.p))) nr
 order by rev.rid
$f$;
comment on function pessoas.revisao_classificar(bigint, integer, bigint[]) is
  'Só leitura. Classifica revisões pendentes: mesma | diferente | humano, com o código da regra. Não grava nada.';

-- ===================== 3. um passo (aplica) =====================
create or replace function pessoas.revisao_lote_passo(p_lote bigint, p_apos bigint, p_n integer, p_regras text[], p_ids bigint[] default null)
returns jsonb
language plpgsql set search_path to '' as $f$
declare
  r record; x record; v jsonb; v_pa jsonb; v_ultimo bigint := p_apos;
  v_ex int := 0; v_m int := 0; v_d int := 0; v_h int := 0; v_fora int := 0; v_f int := 0; v_erro text;
begin
  if p_lote is null or p_apos is null or p_n is null or p_n not between 1 and 100 or p_regras is null then
    raise exception 'parâmetros inválidos' using errcode = '22023';
  end if;
  for r in select * from pessoas.revisao_classificar(p_apos, p_n, p_ids) loop
    v_ultimo := r.revisao_id; v_ex := v_ex + 1;
    if r.acao = 'humano' then v_h := v_h + 1; continue; end if;
    if not (r.regras <@ p_regras) then v_fora := v_fora + 1; continue; end if;
    begin
      select * into x from pessoas.revisao where id = r.revisao_id and status = 'pendente' for update skip locked;
      if not found then continue; end if;   -- outra pessoa decidiu no meio
      select jsonb_build_object('id', p.id, 'situacao', p.situacao, 'mesclada_em', p.mesclada_em, 'atualizado_em', p.atualizado_em)
        into v_pa from pessoas.pessoas p where p.id = r.pessoa_id for update;
      if r.acao = 'mesma' then
        v := pessoas.mesclar(r.pessoa_id, r.alvo, null);
        if not coalesce((v->>'ok')::boolean, false) then v_f := v_f + 1; continue; end if;   -- ex.: dois alunos diferentes: mesclar recusa
      end if;
      insert into arquivo.pessoas_revisao_lote_item (lote_id, revisao_id, pessoa_id, alvo, acao, regras, rev_antes, pessoa_antes)
      values (p_lote, x.id, r.pessoa_id, r.alvo, r.acao, r.regras, to_jsonb(x), v_pa);
      update pessoas.revisao
         set status = r.acao, decidido_por = null, decidido_em = now(),
             detalhe = detalhe || jsonb_build_object('lote', p_lote, 'regras', to_jsonb(r.regras))
       where id = x.id;
      if r.acao = 'diferente' then
        update pessoas.pessoas set situacao = 'ativa', atualizado_em = now()
         where id = x.pessoa_id and situacao = 'revisar'
           and not exists (select 1 from pessoas.revisao y where y.pessoa_id = x.pessoa_id and y.status = 'pendente');
      end if;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
      values (coalesce(r.alvo, r.pessoa_id), 'revisao', 'sistema', 'pessoas.revisao', x.id::text,
              jsonb_build_object('decisao', r.acao, 'motivo', x.motivo, 'lote', p_lote, 'regras', to_jsonb(r.regras)));
      insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
      values (null, 'revisar', x.pessoa_id, jsonb_build_object('revisao', x.id, 'decisao', r.acao, 'alvo', r.alvo, 'lote', p_lote));
      if r.acao = 'mesma' then v_m := v_m + 1; else v_d := v_d + 1; end if;
    exception when others then
      v_f := v_f + 1; v_erro := coalesce(v_erro, sqlstate);   -- só o código; nunca a mensagem (pode ter dado pessoal)
    end;
  end loop;
  return jsonb_build_object('ultimo', v_ultimo, 'examinadas', v_ex, 'mesmas', v_m, 'diferentes', v_d, 'humano', v_h,
                            'fora_das_regras', v_fora, 'falhas', v_f, 'primeiro_erro', v_erro);
end
$f$;

-- ===================== 4. a rodada (COMMIT por passo) =====================
-- CALL pessoas.revisao_lote_rodar(array['A1_telefone_nome', ...]);   Sem cláusula SET (ela proibiria o COMMIT).
create or replace procedure pessoas.revisao_lote_rodar(p_regras text[], p_passo integer default 25, p_max_aplicadas integer default 100,
                                            p_orcamento_s integer default 40, p_apos bigint default 0)
language plpgsql as $p$
declare
  v_sp text := current_setting('search_path'); v_lote bigint; v_t0 timestamptz := clock_timestamp();
  v_ap bigint := p_apos; r jsonb; v_ex int := 0; v_m int := 0; v_d int := 0; v_h int := 0; v_fora int := 0; v_f int := 0; v_fim text := 'fim da fila';
begin
  if p_regras is null or cardinality(p_regras) = 0 or p_passo is null or p_passo not between 1 and 100
     or p_max_aplicadas is null or p_max_aplicadas not between 1 and 2000
     or p_orcamento_s is null or p_orcamento_s not between 5 and 90 or p_apos is null or p_apos < 0 then
    raise exception 'revisao_lote: parâmetros inválidos' using errcode = '22023';
  end if;
  if not (p_regras <@ array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado',
                            'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum']) then
    raise exception 'revisao_lote: regra desconhecida' using errcode = '22023';
  end if;
  if not coalesce((select ligada and ate is not null and current_date <= ate from pessoas.carga_chave where fonte = 'revisao_lote'), false) then
    raise exception 'revisao_lote: chave desligada (ou sem data de fim). Ver o cabeçalho da migration.' using errcode = '55000';
  end if;
  perform set_config('search_path', '', false);
  insert into pessoas.revisao_lote (regras, tamanho_passo, ultima_revisao_id) values (p_regras, p_passo, p_apos) returning id into v_lote;
  commit;
  loop
    if clock_timestamp() - v_t0 > make_interval(secs => p_orcamento_s) then v_fim := 'orçamento de segundos'; exit; end if;
    if v_m + v_d >= p_max_aplicadas then v_fim := 'teto de aplicadas'; exit; end if;
    r := pessoas.revisao_lote_passo(v_lote, v_ap, p_passo, p_regras);
    exit when (r->>'examinadas')::int = 0;
    v_ap := (r->>'ultimo')::bigint;
    v_ex := v_ex + (r->>'examinadas')::int; v_m := v_m + (r->>'mesmas')::int; v_d := v_d + (r->>'diferentes')::int;
    v_h := v_h + (r->>'humano')::int; v_fora := v_fora + (r->>'fora_das_regras')::int; v_f := v_f + (r->>'falhas')::int;
    update pessoas.revisao_lote
       set examinadas = v_ex, mesmas = v_m, diferentes = v_d, humano = v_h, fora_das_regras = v_fora, falhas = v_f,
           ultima_revisao_id = v_ap, atualizado_em = now()
     where id = v_lote;
    commit;
  end loop;
  update pessoas.revisao_lote set terminou_em = now(), motivo_fim = v_fim, atualizado_em = now() where id = v_lote;
  commit;
  perform set_config('search_path', v_sp, false);
  raise notice 'revisao_lote %: % examinadas, % juntadas, % mantidas separadas, % humano, % fora das regras, % falhas; parou por: %; recomeçar de %',
    v_lote, v_ex, v_m, v_d, v_h, v_fora, v_f, v_fim, v_ap;
end
$p$;

-- ===================== 5. reverter =====================
create or replace function pessoas.revisao_lote_reverter(p_lote bigint default null, p_max integer default 500) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  i record; p record; v jsonb; v_ok int := 0; v_pul int := 0;
begin
  if p_max is null or p_max not between 1 and 5000 then raise exception 'p_max entre 1 e 5.000' using errcode = '22023'; end if;
  for i in select * from arquivo.pessoas_revisao_lote_item
            where revertido_em is null and (p_lote is null or lote_id = p_lote)
            order by id desc limit p_max for update loop
    begin
      -- só desfaz o que o lote gravou e que ninguém mexeu depois
      if not exists (select 1 from pessoas.revisao r where r.id = i.revisao_id and r.status = i.acao and r.detalhe->>'lote' = i.lote_id::text) then
        v_pul := v_pul + 1; continue;
      end if;
      if i.acao = 'mesma' then
        select pp.situacao, pp.mesclada_em into p from pessoas.pessoas pp where pp.id = i.pessoa_id for update;
        if p.situacao is distinct from 'mesclada' or p.mesclada_em is distinct from i.alvo then v_pul := v_pul + 1; continue; end if;
        v := pessoas.desfazer_mescla(i.pessoa_id, null);
        if not coalesce((v->>'ok')::boolean, false) then v_pul := v_pul + 1; continue; end if;
        update pessoas.pessoas set situacao = i.pessoa_antes->>'situacao', atualizado_em = (i.pessoa_antes->>'atualizado_em')::timestamptz
         where id = i.pessoa_id;
      elsif i.pessoa_antes->>'situacao' = 'revisar' then
        update pessoas.pessoas set situacao = 'revisar', atualizado_em = (i.pessoa_antes->>'atualizado_em')::timestamptz
         where id = i.pessoa_id and situacao = 'ativa';
      end if;
      update pessoas.revisao
         set status = i.rev_antes->>'status', decidido_por = nullif(i.rev_antes->>'decidido_por', '')::uuid,
             decidido_em = nullif(i.rev_antes->>'decidido_em', '')::timestamptz, detalhe = i.rev_antes->'detalhe'
       where id = i.revisao_id;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe)
      values (coalesce(i.alvo, i.pessoa_id), 'revisao', 'sistema', 'pessoas.revisao', i.revisao_id::text,
              jsonb_build_object('decisao', 'reaberta', 'lote', i.lote_id));
      insert into pessoas.acessos (por, acao, pessoa_id, detalhe)
      values (null, case when i.acao = 'mesma' then 'desfazer_mescla' else 'revisar' end, i.pessoa_id,
              jsonb_build_object('revisao', i.revisao_id, 'decisao', 'reaberta', 'lote', i.lote_id));
      update arquivo.pessoas_revisao_lote_item set revertido_em = now(), atualizado_em = now() where id = i.id;
      v_ok := v_ok + 1;
    exception when others then
      v_pul := v_pul + 1;
    end;
  end loop;
  return jsonb_build_object('revertidas', v_ok, 'puladas', v_pul);
end
$f$;

revoke all on function pessoas.revisao_classificar(bigint, integer, bigint[]), pessoas.revisao_lote_passo(bigint, bigint, integer, text[], bigint[]),
  pessoas.revisao_lote_reverter(bigint, integer) from public, anon, authenticated, service_role;
revoke all on procedure pessoas.revisao_lote_rodar(text[], integer, integer, integer, bigint) from public, anon, authenticated, service_role;


-- ===== depois da reversão do arquivo =====
insert into pg_temp._z_out(passo, linha)
select '40 corpos devolvidos (esperado: os 4 md5 iguais aos de 20261017010000; coluna duplicadas continua; marcador continua; chave desligada)', jsonb_build_object(
  'md5_iguais', (select jsonb_object_agg(sig, ok) from (values
    ('pessoas.revisao_classificar(bigint,integer,bigint[])', (select md5(p.prosrc) = 'bc7856f4e664819acd4ba670aa999120' from pg_proc p where p.oid = to_regprocedure('pessoas.revisao_classificar(bigint,integer,bigint[])'))),
    ('pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])', (select md5(p.prosrc) = 'e933cefbad9c3d2f1562ea5eaa7dd11a' from pg_proc p where p.oid = to_regprocedure('pessoas.revisao_lote_passo(bigint,bigint,integer,text[],bigint[])'))),
    ('pessoas.revisao_lote_reverter(bigint,integer)', (select md5(p.prosrc) = '12a996d61dac3a3868a29ce4ce26fb7d' from pg_proc p where p.oid = to_regprocedure('pessoas.revisao_lote_reverter(bigint,integer)'))),
    ('pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)', (select md5(p.prosrc) = '2542beabe1f98051924a567f400e5b58' from pg_proc p where p.oid = to_regprocedure('pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)')))
  ) t(sig, ok)),
  'tem_duplicadas', exists (select 1 from information_schema.columns where table_schema = 'pessoas' and table_name = 'revisao_lote' and column_name = 'duplicadas'),
  'marcadores', (select count(*) from pessoas.revisao_lote where motivo_fim = 'marcador 20261017030000'),
  'chave_ligada', (select ligada from pessoas.carga_chave where fonte = 'revisao_lote'),
  'chave_ate', (select ate from pessoas.carga_chave where fonte = 'revisao_lote'))::text;
insert into pg_temp._z_out(passo, linha)
select '41 grants depois da reversão (esperado: tudo false)', jsonb_build_object(
  'anon_executa_classificar', has_function_privilege('anon', 'pessoas.revisao_classificar(bigint,integer,bigint[])', 'execute'),
  'authenticated_executa_rodar', has_function_privilege('authenticated', 'pessoas.revisao_lote_rodar(text[],integer,integer,integer,bigint)', 'execute'))::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
