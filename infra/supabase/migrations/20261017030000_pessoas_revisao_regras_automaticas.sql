-- 20261017030000: pessoa única, regras automáticas novas para a fila de revisão (pessoas.revisao), sobre a máquina de 20261017010000
--
-- STATUS: APLICADA em 16/10/2026 (branch victor-revisao-regras), depois do ensaio (begin ... rollback) e da contagem (somente leitura). Lotes rodados: ver 20261017030000.explain.md.
--   Esta migration só cria objetos e garante a chave pessoas.carga_chave 'revisao_lote' desligada; a chave foi ligada só para a rodada e desligada de novo.
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
