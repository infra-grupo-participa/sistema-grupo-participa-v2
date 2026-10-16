-- Contagem da fila de revisão por nível e por regra (20261017030000). SÓ LEITURA: não cria função, não grava, não toca em nada.
-- Roda o MESMO classificador da migration (com as regras novas) sobre as revisões pendentes. Sem dado pessoal na saída (só ids numéricos e códigos).
-- Funciona ANTES de aplicar a migration (não chama pessoas.revisao_classificar; traz o corpo dele inline). Precisa de 20261017020000 aplicada (arquivo.pessoas_nome_padrao_item).
-- Para ir devagar no banco pequeno: trocar o 0 (apos) e o 100000 (limite) abaixo e repetir a partir do último revisao_id lido.
with c as (
with rev as (
  select r.id rid, pessoas.atual(r.pessoa_id) p, r.motivo, r.candidatos
    from pessoas.revisao r
   where r.status = 'pendente' and r.id > 0::bigint and (null::bigint[] is null or r.id = any(null::bigint[]))
   order by r.id
   limit 100000
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
         (t.tp[1] is not null and t.tp[1] = t.tc[1]) nome_prim,
         (t.tp[1] is not null and t.tc[1] is not null and left(t.tp[1], 1) <> left(t.tc[1], 1)
            and position(t.tp[1] in t.tc[1]) = 0 and position(t.tc[1] in t.tp[1]) = 0
            and public.similarity(t.tp[1], t.tc[1]) < 0.3) prim_dif,
         -- 030000: teste/equipe dos dois lados: pessoas.teste = true, e-mail @advmais.com, ou o nome é de quem a lista de eq nomeia.
         -- Também vale o par em que a pessoa da revisão só tem telefone (sem nome e sem e-mail), o telefone é o mesmo e o candidato é de teste/equipe.
         (coalesce(ic.teste or exists (select 1 from unnest(ic.emails) em where em like '%@advmais.com%')
                   or n.nc = any(eq.nomes) or n.nc like any(eq.inicios), false)
          and coalesce(ip.teste or exists (select 1 from unnest(ip.emails) em where em like '%@advmais.com%')
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
              when s.tel and s.nome_sub then 'A4_telefone_nome_contido'
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
)
select 'por_nivel' k, acao a, null::text b, count(*) n from c group by acao
union all
select 'por_regra', acao, array_to_string(regras, ','), count(*) from c group by acao, regras
union all
select 'por_motivo', motivo, acao, count(*) from c group by motivo, acao
order by 1, 2, 3;
