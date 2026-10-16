-- Ensaio de 20261017010000 numa transação DESFEITA (rollback). Sem dado pessoal: pessoas fictícias "Zzensaio" e e-mail .invalid.
-- Rodar: executor que só aceita arquivo terminado em rollback (aplica_sql.py ensaio) neste arquivo. NÃO foi rodado até a escrita (ver 20261017010000.explain.md).
-- O que ele prova: a migration cria tudo; anon/authenticated/service_role não executam nem leem; o classificador devolve contagens da fila
-- real; num cenário fictício, passo -> juntar/separar -> segundo passo (idempotente) -> reverter -> segundo reverter, com o estado igual ao de antes.
-- O que ele NÃO prova: o COMMIT por passo da procedure revisao_lote_rodar (COMMIT não existe dentro de transação explícita): só os dois
-- erros de guarda (chave desligada e parâmetro inválido). A procedure é provada na aplicação, com p_max_aplicadas pequeno.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em serial, passo text, linha text);

-- ===== 20261017010000 (corpo da migration, sem begin/commit) =====
-- 20261017010000: pessoa única, resolver em lote a fila de revisão (pessoas.revisao)
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-revisao-em-lote), ensaio escrito mas NÃO rodado, aguardando ok de um dos donos do banco.
--   Ensaio: 20261017010000_ensaio.sql (begin ... rollback). Só contagem, sem escrita: 20261017010000_contagem.sql. Reversão: 20261017010000_reversao.sql.
--   Detalhe, critérios e contagens: 20261017010000.explain.md e docs/pessoa-unica/README.md (seção "Revisão em lote").
--
-- POR QUE: pessoas.revisao guarda os casos em que o casamento (pessoas.resolver / pessoas.anexar) não teve certeza se duas pessoas são a mesma.
--   Só uma pessoa decide, um caso por vez (public.pessoas_revisao_decidir). Esta migration dá regras escritas para decidir em lote os casos em que o sinal
--   é forte, e deixa o resto para o humano.
-- O QUE CRIA (nada é executado sobre a fila; a migration só cria objetos e uma chave DESLIGADA):
--   1. pessoas.revisao_lote e arquivo.pessoas_revisao_lote_item: controle de cada rodada e a CÓPIA (jsonb) da linha de revisão e da pessoa antes de tocar.
--   2. pessoas.revisao_classificar(apos, limite, ids): só LEITURA; diz, para cada revisão pendente, 'mesma', 'diferente' ou 'humano' e a regra.
--   3. pessoas.revisao_lote_passo(...): aplica UM passo (poucas revisões). 'mesma' = pessoas.mesclar (alias, nunca apaga), 'diferente' = fecha a revisão.
--   4. pessoas.revisao_lote_rodar(...): PROCEDURE com COMMIT por passo, teto, orçamento de segundos e chave de desligar (pessoas.carga_chave 'revisao_lote').
--   5. pessoas.revisao_lote_reverter(lote, max): devolve revisão e pessoa ao estado copiado (mescla desfeita pela pessoas.desfazer_mescla).
-- REGRAS (códigos; o CALL escolhe quais valem): A1_telefone_nome, A2_email_digitado_errado_nome, A3_telefone_email_digitado_errado (juntar);
--   B1_documento_diferente, B2_telefone_nome_diferente, B3_homonimo_comum (manter separado). O resto fica 'humano' (códigos H*).
-- COMO VOLTAR: 20261017010000_reversao.sql (reverte as rodadas ainda não revertidas e remove as funções). As duas tabelas de cópia ficam (histórico).
-- AS 5 PERGUNTAS: escala = 822 revisões pendentes em 16/10/2026 ~10:30 (6.423 pares candidatos), passo de 25 revisões, até 20 candidatos por revisão;
--   índice = pessoa_id e (tipo,chave) em identificadores, PK de pessoas/thb_alunos/compradores, revisao_pessoa_idx; nenhum índice novo.
--   Medido (explain analyze do corpo do classificador, 30 revisões): 189 ms, 1.388 buffers, nenhum Seq Scan; a fila inteira leu em 28 chamadas de 30 sem timeout;
--   frequência = manual (CALL), nunca job; repetição = idempotente (só lê revisão 'pendente'; índice único parcial por revisão não revertida);
--   reversão = função de reverter + chave desligada.
-- DADO PESSOAL: o CPF (11 dígitos) é lido de thb_alunos/compradores só para COMPARAR dentro da consulta; não é gravado, não vai ao jsonb de cópia, não é devolvido.
--   Decisão registrada de 14/10 é "casar por e-mail, nunca por CPF": aqui o CPF NUNCA junta ninguém, só pode impedir (A* some) ou separar (B1).

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('pessoas.mesclar(uuid,uuid,uuid)') is null or to_regprocedure('pessoas.desfazer_mescla(uuid,uuid)') is null then
    raise exception '20261017010000: falta pessoas.mesclar / pessoas.desfazer_mescla.';
  end if;
  if to_regclass('pessoas.revisao') is null or to_regclass('pessoas.carga_chave') is null or to_regnamespace('arquivo') is null or to_regnamespace('controle') is null then
    raise exception '20261017010000: falta pessoas.revisao, pessoas.carga_chave ou o schema arquivo/controle.';
  end if;
  if to_regprocedure('pessoas.revisao_classificar(bigint,integer,bigint[])') is not null then
    raise exception '20261017010000: já aplicada.';
  end if;
end
$g$;

-- ===================== 1. controle e cópia =====================
create table if not exists pessoas.revisao_lote (
  id            bigint generated always as identity primary key,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  regras        text[] not null,
  tamanho_passo integer not null,
  examinadas    integer not null default 0,
  mesmas        integer not null default 0,
  diferentes    integer not null default 0,
  humano        integer not null default 0,
  fora_das_regras integer not null default 0,
  falhas        integer not null default 0,
  ultima_revisao_id bigint not null default 0,
  terminou_em   timestamptz,
  motivo_fim    text
);
alter table pessoas.revisao_lote enable row level security;

create table if not exists arquivo.pessoas_revisao_lote_item (
  id            bigint generated always as identity primary key,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  lote_id       bigint not null references pessoas.revisao_lote(id),
  revisao_id    bigint not null,
  pessoa_id     uuid not null,      -- pessoa atual da revisão no momento (a que foi juntada ou liberada)
  alvo          uuid,               -- 'mesma': a pessoa que ficou
  acao          text not null check (acao in ('mesma', 'diferente')),
  regras        text[] not null,
  rev_antes     jsonb not null,     -- to_jsonb da linha de pessoas.revisao antes (sem dado pessoal: id, motivo, candidatos, status...)
  pessoa_antes  jsonb not null,     -- id, situacao, mesclada_em, atualizado_em da pessoa antes
  revertido_em  timestamptz
);
alter table arquivo.pessoas_revisao_lote_item enable row level security;
create unique index if not exists pessoas_revisao_lote_item_rev_ativa on arquivo.pessoas_revisao_lote_item (revisao_id) where revertido_em is null;
create index if not exists pessoas_revisao_lote_item_lote on arquivo.pessoas_revisao_lote_item (lote_id) where revertido_em is null;
revoke all on pessoas.revisao_lote, arquivo.pessoas_revisao_lote_item from public, anon, authenticated, service_role;

-- chave de desligar: nasce DESLIGADA. Ligar: update pessoas.carga_chave set ligada = true, ate = current_date + 7, por = 'victor' where fonte = 'revisao_lote';
insert into pessoas.carga_chave (fonte, ligada, ate, por)
select 'revisao_lote', false, null, 'migration 20261017010000'
 where not exists (select 1 from pessoas.carga_chave where fonte = 'revisao_lote');

-- ===================== 2. classificador (só leitura) =====================
-- Uma linha por revisão pendente com id > p_apos (ordem do id, no máximo p_limite). acao: mesma | diferente | humano.
-- 'mesma' só se EXATAMENTE 1 candidato bate numa regra A e a pessoa só tem esta revisão pendente.
-- 'diferente' só se TODOS os candidatos batem numa regra B e nenhum numa regra A.
create function pessoas.revisao_classificar(p_apos bigint, p_limite integer, p_ids bigint[] default null)
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
create function pessoas.revisao_lote_passo(p_lote bigint, p_apos bigint, p_n integer, p_regras text[], p_ids bigint[] default null)
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
create procedure pessoas.revisao_lote_rodar(p_regras text[], p_passo integer default 25, p_max_aplicadas integer default 100,
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
create function pessoas.revisao_lote_reverter(p_lote bigint default null, p_max integer default 500) returns jsonb
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

-- ===================== 6. permissões =====================
revoke all on function pessoas.revisao_classificar(bigint, integer, bigint[]), pessoas.revisao_lote_passo(bigint, bigint, integer, text[], bigint[]),
  pessoas.revisao_lote_reverter(bigint, integer) from public, anon, authenticated, service_role;
revoke all on procedure pessoas.revisao_lote_rodar(text[], integer, integer, integer, bigint) from public, anon, authenticated, service_role;


-- ===== checagens =====
insert into pg_temp._z_out(passo, linha)
select '01 grants (esperado: tudo false)', jsonb_build_object(
  'anon_executa_classificar', has_function_privilege('anon', 'pessoas.revisao_classificar(bigint,integer,bigint[])', 'execute'),
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
select '03 chave nasce desligada (esperado: ligada=false)', jsonb_build_object('ligada', ligada, 'ate', ate)::text
  from pessoas.carga_chave where fonte = 'revisao_lote';

-- guardas da procedure (erro antes de qualquer COMMIT, então cabe na transação do ensaio)
do $t$
declare v1 text; v2 text; v3 text;
begin
  begin call pessoas.revisao_lote_rodar(array['A1_telefone_nome']); v1 := 'SEM ERRO (errado)'; exception when others then v1 := sqlstate; end;
  begin call pessoas.revisao_lote_rodar(null); v2 := 'SEM ERRO (errado)'; exception when others then v2 := sqlstate; end;
  begin call pessoas.revisao_lote_rodar(array['X_inventada']); v3 := 'SEM ERRO (errado)'; exception when others then v3 := sqlstate; end;
  insert into pg_temp._z_out(passo, linha)
  values ('04 guardas da procedure (esperado: 55000 chave desligada, 22023 nulo, 22023 regra desconhecida)', v1 || ', ' || v2 || ', ' || v3);
end
$t$;

-- ===== contagem na fila REAL (só leitura) =====
insert into pg_temp._z_out(passo, linha)
select '10 fila real por nível', coalesce(jsonb_object_agg(acao, n)::text, '{}')
  from (select acao, count(*) n from pessoas.revisao_classificar(0, 100000) group by acao) x;
insert into pg_temp._z_out(passo, linha)
select '11 fila real por regra', acao || ' | ' || array_to_string(regras, ',') || ' | ' || n
  from (select acao, regras, count(*) n from pessoas.revisao_classificar(0, 100000) group by acao, regras) x;

-- ===== cenário fictício, isolado por p_ids =====
create temp table _z (k text primary key, v text);
do $t$
declare
  a1 uuid; p1 uuid; a2 uuid; p2 uuid; c3a uuid; c3b uuid; p3 uuid; a4 uuid; p4 uuid; a5 uuid; p5 uuid;
  r1 bigint; r2 bigint; r3 bigint; r4 bigint; r5 bigint;
begin
  insert into pessoas.pessoas (nome) values ('Zzensaio Maria Silvazz') returning id into a1;
  insert into pessoas.pessoas (nome, situacao) values ('Zzensaio Maria Silvazz', 'revisar') returning id into p1;
  insert into pessoas.pessoas (nome) values ('Carlos Zzlima') returning id into a2;
  insert into pessoas.pessoas (nome, situacao) values ('Marta Zzsouza', 'revisar') returning id into p2;
  insert into pessoas.pessoas (nome) values ('Zzensaio Joao Pereirazz') returning id into c3a;
  insert into pessoas.pessoas (nome) values ('Zzensaio Joao Pereirazz') returning id into c3b;
  insert into pessoas.pessoas (nome, situacao) values ('Zzensaio Joao Pereirazz', 'revisar') returning id into p3;
  insert into pessoas.pessoas (nome) values ('Zzensaio Ana Zzprimeiro') returning id into a4;
  insert into pessoas.pessoas (nome, situacao) values ('Zzensaio Ana Zzsegundo', 'revisar') returning id into p4;
  insert into pessoas.pessoas (nome) values ('Zzensaio Paula Teixeirazz') returning id into a5;
  insert into pessoas.pessoas (nome, situacao) values ('Zzensaio Paula Teixeirazz', 'revisar') returning id into p5;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem) values
    (a1, 'telefone', '5599900000001', '5599900000001', 'importacao'), (p1, 'telefone', '5599900000001', '5599900000001', 'importacao'),
    (a2, 'telefone', '5599900000002', '5599900000002', 'importacao'), (p2, 'telefone', '5599900000002', '5599900000002', 'importacao'),
    (c3a, 'telefone', '5599900000003', '5599900000003', 'importacao'), (c3b, 'telefone', '5599900000003', '5599900000003', 'importacao'),
    (p3, 'telefone', '5599900000003', '5599900000003', 'importacao'),
    (a5, 'email', 'zzensaio5@exemplo.invalid', 'zzensaio5@exemplo.invalid', 'importacao'),
    (p5, 'email', 'zzensaio5@exemplo.invali', 'zzensaio5@exemplo.invali', 'importacao');
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p1, 'telefone_email_diferente', array[a1]) returning id into r1;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p2, 'telefone_nome_diferente', array[a2]) returning id into r2;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p3, 'telefone_varios', array[c3a, c3b]) returning id into r3;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p4, 'so_nome', array[a4]) returning id into r4;
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (p5, 'email_conflito', array[a5]) returning id into r5;
  insert into pg_temp._z values ('ids', array[r1, r2, r3, r4, r5]::text), ('a1', a1::text), ('p1', p1::text), ('p2', p2::text), ('p3', p3::text),
    ('p4', p4::text), ('p5', p5::text), ('a5', a5::text), ('r1', r1::text), ('r2', r2::text), ('r5', r5::text);
end
$t$;
insert into pg_temp._z_out(passo, linha)
select '20 classificação do cenário (esperado: r1 mesma A1; r2 diferente B2; r3 humano H2; r4 humano H9; r5 mesma A2 ou humano H9 conforme a similaridade do domínio)',
       revisao_id || ' | ' || acao || ' | ' || array_to_string(regras, ',')
  from pessoas.revisao_classificar(0, 100, (select v::bigint[] from pg_temp._z where k = 'ids')) order by revisao_id;

create temp table _z_antes as
select r.id, to_jsonb(r) j from pessoas.revisao r where r.id = any((select v::bigint[] from pg_temp._z where k = 'ids'));
create temp table _z_pantes as
select p.id, p.situacao, p.mesclada_em from pessoas.pessoas p where p.id in (select v::uuid from pg_temp._z where k in ('a1', 'p1', 'p2', 'p3', 'p4', 'p5', 'a5'));

insert into pessoas.revisao_lote (regras, tamanho_passo) values (array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum'], 50);
insert into pg_temp._z select 'lote', max(id)::text from pessoas.revisao_lote;

insert into pg_temp._z_out(passo, linha)
select '21 passo só com a regra B2 (esperado: diferentes 1, mesmas 0; as A ficam em fora_das_regras)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['B2_telefone_nome_diferente'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '21b passo com todas as regras (esperado: mesmas 1 ou 2, diferentes 0, humano 2 ou 3, falhas 0)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50,
         array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;
insert into pg_temp._z_out(passo, linha)
select '22 estado depois dos passos 21 e 21b', jsonb_build_object(
  'r1_status', (select status from pessoas.revisao where id = (select v::bigint from pg_temp._z where k = 'r1')),
  'p1_mesclada_na_a1', (select mesclada_em = (select v::uuid from pg_temp._z where k = 'a1') from pessoas.pessoas where id = (select v::uuid from pg_temp._z where k = 'p1')),
  'r2_status', (select status from pessoas.revisao where id = (select v::bigint from pg_temp._z where k = 'r2')),
  'p2_situacao', (select situacao from pessoas.pessoas where id = (select v::uuid from pg_temp._z where k = 'p2')),
  'r3_r4_ainda_pendentes', (select count(*) from pessoas.revisao where status = 'pendente' and id = any((select v::bigint[] from pg_temp._z where k = 'ids')) and id not in
                             ((select v::bigint from pg_temp._z where k = 'r1'), (select v::bigint from pg_temp._z where k = 'r2'), (select v::bigint from pg_temp._z where k = 'r5'))),
  'itens_de_copia', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote')),
  'copia_sem_cpf_e_email', (select count(*) from arquivo.pessoas_revisao_lote_item where rev_antes::text ~ '@' or pessoa_antes::text ~ '@'))::text;
insert into pg_temp._z_out(passo, linha)
select '23 passo 2 igual (idempotente; esperado: mesmas 0, diferentes 0)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50,
         array['A1_telefone_nome', 'A2_email_digitado_errado_nome', 'A3_telefone_email_digitado_errado', 'B1_documento_diferente', 'B2_telefone_nome_diferente', 'B3_homonimo_comum'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;

insert into pg_temp._z_out(passo, linha)
select '30 reverter (esperado: revertidas = itens do passo 1)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote'), 100)::text;
insert into pg_temp._z_out(passo, linha)
select '31 estado depois de reverter, comparado com o de antes (esperado: revisoes_diferentes_do_antes = 0, pessoas_diferentes_do_antes = 0)', jsonb_build_object(
  'revisoes_diferentes_do_antes', (select count(*) from pg_temp._z_antes z join pessoas.revisao r on r.id = z.id where to_jsonb(r) is distinct from z.j),
  'pessoas_diferentes_do_antes', (select count(*) from pg_temp._z_pantes z join pessoas.pessoas p on p.id = z.id
                                   where p.situacao is distinct from z.situacao or p.mesclada_em is distinct from z.mesclada_em),
  'itens_nao_revertidos', (select count(*) from arquivo.pessoas_revisao_lote_item where lote_id = (select v::bigint from pg_temp._z where k = 'lote') and revertido_em is null))::text;
insert into pg_temp._z_out(passo, linha)
select '32 reverter de novo (esperado: revertidas 0)', pessoas.revisao_lote_reverter((select v::bigint from pg_temp._z where k = 'lote'), 100)::text;
insert into pg_temp._z_out(passo, linha)
select '33 depois de reverter, aplicar de novo funciona (esperado: aplicadas > 0 e item novo com índice único parcial livre)',
       pessoas.revisao_lote_passo((select v::bigint from pg_temp._z where k = 'lote'), 0, 50, array['A1_telefone_nome', 'B2_telefone_nome_diferente'],
         (select v::bigint[] from pg_temp._z where k = 'ids'))::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
