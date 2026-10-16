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
