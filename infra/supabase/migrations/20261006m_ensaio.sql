-- 20261006m: ENSAIO (não aplica nada: termina em ROLLBACK). Rodar inteiro, como postgres, numa chamada só.
--   Pelo MCP (execute_sql) ou pelo aplica_sql.py: o bloco final levanta uma exceção com a saída (a transação aborta,
--   nada persiste); o rollback do fim cobre quem rodar sem o bloco.
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006m_crm_desempenho.sql, da guarda até antes
-- da REVERSÃO). Só contagens e tempos saem: nenhum nome, e-mail ou telefone.
-- Perfis reais por SELECT (gestor = admin ativo mais antigo; vendedores = crm.vendedor ativos; vis = perfil ativo fora
-- do Comercial), chamados como a tela chama: role authenticated + request.jwt.claims com o sub do perfil.
-- Esperado: nenhuma linha começando com "ERRADO".
--   0 fixtures e lista ANTIGA (crm_contatos)       1 dados_lote = pessoas.dados (todos os contatos)
--   2 lista nova = lista antiga (visibilidade, máscara, ordem, total) por perfil
--   3 resumo = contagem da lista antiga            4 por_ids = itens de crm_contatos (lista, busca, alheio, duplicados)
--   5 busca igual à de crm_contatos                6 métricas (abertos, lançamentos, última interação)
--   7 filtros e ordenação                          8 guardas e permissões
--   9 tempos (2×) e explain analyze (2×)

begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || coalesce(p_det, ''));
$$;
create function pg_temp.info(p_passo text, p_det text) returns void
language sql as $$ insert into pg_temp._z_out (passo, linha) values (p_passo, 'INFO    ' || coalesce(p_det, '')); $$;

create temp table _v (k text primary key, u uuid) on commit drop;
insert into _v select 'gestor', p.id from public.perfis p where p.cargo = 'admin' and p.status = 'ativo' order by p.criado_em limit 1;
insert into _v select 'vend_' || v.sigla, v.perfil_id from crm.vendedor v join public.perfis p on p.id = v.perfil_id
 where v.ativo and p.status = 'ativo' order by v.sigla;
insert into _v select 'vis', p.id from public.perfis p
 where p.status = 'ativo' and p.cargo not in ('admin', 'dev') and not ('comercial' = any(coalesce(p.areas, '{}')))
 order by p.criado_em limit 1;

-- chama como a tela: role authenticated + JWT do perfil. Erro vira {erro, estado}.
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;

-- tempo de uma chamada inteira (ms), como a tela
create function pg_temp.ms(p_perfil uuid, p_sql text) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); v jsonb;
begin
  v := pg_temp.chamar(p_perfil, p_sql);
  if v ? 'erro' then raise exception 'chamada falhou: %', v ->> 'erro'; end if;
  return round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1);
end $$;

-- ─── 0. Fixtures e a lista ANTIGA ───
select pg_temp.ok('0.fixtures', (select count(*) from _v where k = 'gestor') = 1 and (select count(*) from _v where k like 'vend_%') >= 2
                                and (select count(*) from _v where k = 'vis') = 1,
  format('gestor=%s vendedores=%s vis=%s', (select count(*) from _v where k = 'gestor'),
         (select count(*) from _v where k like 'vend_%'), (select count(*) from _v where k = 'vis')));
select pg_temp.ok('0.atalho_atual', (select count(*) from pessoas.pessoas where (situacao = 'mesclada') is distinct from (mesclada_em is not null)) = 0,
  format('situacao mesclada × mesclada_em divergentes: %s; mescladas: %s; contatos comerciais: %s',
         (select count(*) from pessoas.pessoas where (situacao = 'mesclada') is distinct from (mesclada_em is not null)),
         (select count(*) from pessoas.pessoas where mesclada_em is not null), (select count(*) from crm.pessoa_comercial)));

-- lista antiga inteira por perfil (lotes de 500, como o front de hoje), com o tempo total
create temp table _old (k text, o int, item jsonb) on commit drop;
create temp table _tempo (k text, rotulo text, ms numeric) on commit drop;
do $$
declare r record; v jsonb; o int; t0 timestamptz; n int;
begin
  for r in select k, u from _v where k <> 'vis' order by k loop
    o := 0; n := 0; t0 := clock_timestamp();
    loop
      v := pg_temp.chamar(r.u, format('select public.crm_contatos(null, 500, %s)', o));
      if v ? 'erro' then raise exception 'crm_contatos %: %', r.k, v ->> 'erro'; end if;
      insert into _old select r.k, o + e.i::int, e.item from jsonb_array_elements(v -> 'itens') with ordinality e(item, i);
      n := n + 1;
      exit when not (v ->> 'temMais')::boolean or o > 20000;
      o := o + 500;
    end loop;
    insert into _tempo values (r.k, format('antes: lista inteira (%s chamadas de 500)', n),
                               round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1));
  end loop;
end $$;
select pg_temp.info('0.antes', string_agg(format('%s: %s contatos (%s sem dono)', k, n, s), ' | ' order by k))
  from (select k, count(*) n, count(*) filter (where item ->> 'donoId' is null) s from _old group by k) x;

-- ═══ CORPO DA MIGRATION (copiado sem mudança) ═══
-- ─── Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  -- corpos VIVOS de onde as regras foram copiadas (pg_get_functiondef em 06/10/2026)
  if md5(pg_get_functiondef('public.crm_contatos(text,integer,integer)'::regprocedure)) <> '8b3de3f94f1dbe6b9150fdd3bded4923' then
    raise exception '20261006m: corpo vivo de public.crm_contatos mudou (md5); reler visibilidade/máscara/busca e regerar';
  end if;
  if md5(pg_get_functiondef('pessoas.dados(uuid)'::regprocedure)) <> 'c76ee58454e80d17d87c73b7596bdb89' then
    raise exception '20261006m: corpo vivo de pessoas.dados mudou (md5); regerar crm.dados_lote';
  end if;
  if md5(pg_get_functiondef('pessoas.grupo(uuid)'::regprocedure)) <> 'cd932218c18a97491ecd4ce52bb36c49' then
    raise exception '20261006m: corpo vivo de pessoas.grupo mudou (md5); regerar crm.grupo_lote';
  end if;
  if md5(pg_get_functiondef('pessoas.atual(uuid)'::regprocedure)) <> '2288eecebcef0238ca7df2f4eb644daf' then
    raise exception '20261006m: corpo vivo de pessoas.atual mudou (md5); reler o atalho mesclada_em is null';
  end if;
  if md5(pg_get_functiondef('public.crm_jornada(uuid,integer)'::regprocedure)) <> '7d9317afaaf6a6207a595a6fca4e6d46' then
    raise exception '20261006m: corpo vivo de public.crm_jornada mudou (md5); reler as fontes de lançamento/última interação';
  end if;
  if md5(pg_get_functiondef('crm.pessoas_negocio_meu()'::regprocedure)) <> '066e7c5bbd7a78305f79aebf92e6c3e7' then
    raise exception '20261006m: corpo vivo de crm.pessoas_negocio_meu mudou (md5)';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname = 'public' and p.proname in ('crm_contatos_pagina', 'crm_contatos_resumo', 'crm_contatos_por_ids'))
                 or (n.nspname = 'crm' and p.proname in ('grupo_lote', 'dados_lote', 'contatos_candidatos', 'contatos_visiveis',
                                                         'contatos_base', 'contatos_metricas', 'contatos_itens'))) then
    raise exception '20261006m: alguma função desta migration já existe (já rodou?)';
  end if;
  if not exists (select 1 from pg_collation where collname = 'pt-BR-x-icu') then
    raise exception '20261006m: collation pt-BR-x-icu ausente (ordenação por nome)';
  end if;
end
$guarda$;

-- ─── Ajudantes (crm, fora da API) ─────────────────────────────────────────────────────────────────────────────────

-- Grupo de alias em lote: para cada raiz, ela mesma + quem foi mesclado nela (recursivo). = pessoas.grupo(raiz).
create function crm.grupo_lote(p_ids uuid[])
returns table(raiz uuid, membro uuid)
language sql stable
set search_path = ''
as $$
  with recursive g(raiz, id) as (
    select x, x from unnest(p_ids) x where x is not null
    union
    select g.raiz, p.id from pessoas.pessoas p join g on p.mesclada_em = g.id
  )
  select g.raiz, g.id from g;
$$;

-- pessoas.dados() de várias pessoas de uma vez. Mesmas regras, num join único (era uma chamada por linha):
-- aluno/comprador/nome = o primeiro não nulo do grupo (a própria pessoa antes, depois a mais antiga); e-mail e telefone
-- = o do aluno, senão o do comprador, senão o identificador mais recente do grupo.
create function crm.dados_lote(p_ids uuid[])
returns table(d_pessoa uuid, d_nome text, d_email text, d_telefone text, d_aluno_id uuid, d_comprador_id uuid)
language sql stable
set search_path = ''
as $$
  with ids as (select distinct x from unnest(p_ids) x where x is not null),
  g as (select gl.raiz, gl.membro from crm.grupo_lote(array(select ids.x from ids)) gl),
  gp as (select g.raiz, p.id, p.aluno_id, p.comprador_id, p.nome, p.criado_em
           from g join pessoas.pessoas p on p.id = g.membro),
  r as (
    select gp.raiz,
           (array_agg(gp.aluno_id order by gp.id = gp.raiz desc, gp.criado_em) filter (where gp.aluno_id is not null))[1] aluno_id,
           (array_agg(gp.comprador_id order by gp.id = gp.raiz desc, gp.criado_em) filter (where gp.comprador_id is not null))[1] comprador_id,
           (array_agg(gp.nome order by gp.id = gp.raiz desc, gp.criado_em) filter (where gp.nome is not null))[1] nome
      from gp group by gp.raiz),
  ie as (select distinct on (g.raiz) g.raiz, i.valor
           from g join pessoas.identificadores i on i.pessoa_id = g.membro and i.tipo = 'email'
          order by g.raiz, i.id desc),
  it as (select distinct on (g.raiz) g.raiz, i.valor
           from g join pessoas.identificadores i on i.pessoa_id = g.membro and i.tipo = 'telefone'
          order by g.raiz, i.id desc)
  select ids.x,
         coalesce(a.nome, c.nome::text, r.nome),
         coalesce(pessoas.norm_email(a.email), pessoas.norm_email(c.email::text), ie.valor),
         coalesce(pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone)), pessoas.norm_telefone(c.telefone::text), it.valor),
         r.aluno_id,
         coalesce(r.comprador_id, a.comprador_id)
    from ids
    left join r on r.raiz = ids.x
    left join public.thb_alunos a on a.id = r.aluno_id
    left join public.compradores c on c.id = coalesce(r.comprador_id, a.comprador_id)
    left join ie on ie.raiz = ids.x
    left join it on it.raiz = ids.x;
$$;

-- Candidatos da busca (e-mail exato, chave de telefone ou parte do nome), já expandidos para o grupo de alias.
-- Bloco copiado SEM mudança de public.crm_contatos (md5 8b3de3f9…). Texto com menos de 3 letras: nenhum.
create function crm.contatos_candidatos(p_texto text)
returns uuid[]
language plpgsql stable
set search_path = ''
as $$
declare
  v_t text := nullif(btrim(coalesce(p_texto, '')), '');
  v_email text; v_fk text; v_like text; v_ids uuid[];
begin
  if v_t is null or length(v_t) < 3 then return '{}'::uuid[]; end if;
  v_email := pessoas.norm_email(v_t);
  v_fk := pessoas.chave_telefone(v_t);
  v_like := case when v_email is null and v_fk is null
                 then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_ids := array(
    select distinct pessoas.atual(s.x) from (
      select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
      union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
      union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
             where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
      union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
             where v_email is not null and lower(btrim((c.email)::text)) = v_email
      union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
             where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
      union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
             where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null
      union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
      union (select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
              where v_like is not null and a.nome ilike v_like limit 200)
    ) s);
  return array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
end
$$;

-- Quem a pessoa logada vê. Regra VIVA de public.crm_contatos (20261006191824), copiada:
--   gestor vê tudo; vendedor vê dono = eu, pessoa com negócio meu e, sem dono: na LISTA (p_ids nulo) só com negócio
--   aberto ou negócio sem dono; na BUSCA (p_ids = candidatos) todo sem dono. Alias: vale a linha da pessoa atual.
--   completo = vê e-mail/telefone inteiros (senão mascarados). Fora do Comercial: nenhuma linha.
-- pessoas.atual(x) = x quando mesclada_em é nulo (é o primeiro passo do laço de pessoas.atual): o atalho evita uma
-- chamada por linha e dá o mesmo resultado.
create function crm.contatos_visiveis(p_ids uuid[])
returns table(r_pessoa uuid, r_atual uuid, r_completo boolean, r_criado timestamptz)
language plpgsql stable
set search_path = ''
as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_meus uuid[];
begin
  if not coalesce(crm.eh_comercial(), false) then return; end if;
  v_meus := case when v_gestor then '{}'::uuid[] else array(select crm.pessoas_negocio_meu()) end;
  return query
  select pc0.pessoa_id, a.atual,
         coalesce(v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id = any(v_meus), false),
         pc0.criado_em
    from crm.pessoa_comercial pc0
    join pessoas.pessoas pp on pp.id = pc0.pessoa_id
   cross join lateral (select case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end atual) a
   where (p_ids is null or pc0.pessoa_id = any(p_ids))
     and (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id = any(v_meus)
          or (pc0.dono_id is null
              and (p_ids is not null
                   or exists (select 1 from crm.negocio n
                               where n.pessoa_id in (pc0.pessoa_id, a.atual)
                                 and (n.status = 'aberto' or n.dono_id is null)))))
     and (pp.situacao <> 'mesclada'
          or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = a.atual));
end
$$;

-- Lista visível com os filtros da tela e as chaves de ordenação (nome e dono em minúsculas).
--   p_dono_sem: só sem dono; p_dono: só deste dono; p_perfil: 'sem' = sem perfil; p_uf: sigla; p_tags: qualquer uma.
--   p_com_dados: monta nome/aluno/UF (crm.dados_lote, ~115 ms para 2.649). Sem ele (ordem por criação, sem filtro de
--   UF/aluno), b_nome/b_uf vêm nulos e b_aluno falso: os dados só são montados para a página (crm.contatos_itens).
create function crm.contatos_base(
  p_ids uuid[], p_dono_sem boolean, p_dono uuid, p_perfil text, p_uf text, p_tags text[], p_opt_out boolean, p_so_alunos boolean,
  p_com_dados boolean)
returns table(b_pid uuid, b_atual uuid, b_criado timestamptz, b_nome text, b_dono text, b_dono_nulo boolean,
              b_opt_out boolean, b_aluno boolean, b_uf text, b_tags text[])
language sql stable
set search_path = ''
as $$
  with b0 as (
    select v.r_pessoa pid, v.r_atual atual, pc.criado_em, pc.dono_id, pc.opt_out, pc.tags
      from crm.contatos_visiveis(p_ids) v
      join crm.pessoa_comercial pc on pc.pessoa_id = v.r_pessoa
     where (not coalesce(p_dono_sem, false) or pc.dono_id is null)
       and (p_dono is null or pc.dono_id = p_dono)
       and (p_perfil is null or (p_perfil = 'sem' and nullif(pc.perfil, '') is null) or pc.perfil = p_perfil)
       and (p_tags is null or cardinality(p_tags) = 0 or pc.tags && p_tags)
       and (not coalesce(p_opt_out, false) or coalesce(pc.opt_out, false))),
  d as (select dl.* from crm.dados_lote(case when p_com_dados or p_uf is not null or coalesce(p_so_alunos, false)
                                              then array(select distinct b0.atual from b0) else '{}'::uuid[] end) dl)
  select b0.pid, b0.atual, b0.criado_em,
         case when d.d_pessoa is not null then lower(coalesce(d.d_nome, '(sem nome)')) end, lower(coalesce(pf.nome, '')), b0.dono_id is null,
         coalesce(b0.opt_out, false), d.d_aluno_id is not null, u.uf, coalesce(b0.tags, '{}'::text[])
    from b0
    left join d on d.d_pessoa = b0.atual
    left join public.thb_alunos al on al.id = d.d_aluno_id
    left join public.compradores cp on cp.id = d.d_comprador_id
    left join public.perfis pf on pf.id = b0.dono_id
   cross join lateral (select case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                                   then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end uf) u
   where (p_uf is null or u.uf = p_uf)
     and (not coalesce(p_so_alunos, false) or d.d_aluno_id is not null);
$$;

-- Negócios abertos, lançamentos e última interação de várias pessoas (ids atuais) de uma vez.
--   Negócio: mesma visibilidade da RLS negocio_ler e de crm_jornada (gestor, dono = eu ou sem dono).
--   Lançamentos = chaves distintas, como a ficha conta na jornada: sigla do projeto das inscrições (pessoas.origens) e
--     dos eventos MQL, projeto do funil dos negócios e das mudanças de negócio no crm.log.
--   Última interação = a mais recente entre inscrições, eventos de MQL/compra/checkout/reembolso (pessoas.eventos, o
--     espelho da Hotmart por pessoa), eventos de integração (crm.evento_jornada, com os interruptores), criação e
--     última interação dos negócios, mudanças de negócio, atividades concluídas e notas. Fica de fora o que a jornada
--     casa só por e-mail/telefone (lista do ActiveCampaign, grupos, Respondi, Unnichat legado, CS): caro em lote.
create function crm.contatos_metricas(p_ids uuid[])
returns table(m_id uuid, m_qtd_abertos integer, m_abertos jsonb, m_lancamentos integer, m_ultima timestamptz)
language plpgsql stable
set search_path = ''
as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
begin
  if not coalesce(crm.eh_comercial(), false) then return; end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  return query
  with ids as (select distinct x from unnest(p_ids) x where x is not null),
  g as (select gl.raiz, gl.membro from crm.grupo_lote(array(select ids.x from ids)) gl),
  neg as (select g.raiz, n.id, n.linha, n.status, n.criado_em, n.ultima_interacao_em, n.funil_id, n.etapa_id
            from g join crm.negocio n on n.pessoa_id = g.membro
           where v_gestor or n.dono_id = v_eu or n.dono_id is null),
  ab as (select neg.raiz, count(*)::int qtd,
                jsonb_agg(jsonb_build_object('id', neg.id, 'produto', neg.linha, 'etapaNome', e.nome)
                          order by neg.criado_em desc, neg.id) j
           from neg join crm.etapa_funil e on e.id = neg.etapa_id
          where neg.status = 'aberto'
          group by neg.raiz),
  lg as (select g.raiz, l.em, f.projeto
           from g
           join crm.log l on l.pessoa_id = g.membro
           join crm.negocio n on n.id::text = l.entidade_id
           join crm.funil f on f.id = n.funil_id
          where l.entidade = 'negocio' and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
            and (v_gestor or n.dono_id = v_eu or n.dono_id is null)),
  la as (select g.raiz, lower(pr.sigla) k
           from g join pessoas.origens o on o.pessoa_id = g.membro join mkt.projetos pr on pr.id = o.projeto_id
         union
         select g.raiz, lower(pr.sigla)
           from g join pessoas.eventos ev on ev.pessoa_id = g.membro and ev.tipo in ('mql', 'nao_mql')
           join mkt.projetos pr on pr.id = ev.projeto_id
         union
         select neg.raiz, f.projeto from neg join crm.funil f on f.id = neg.funil_id
         union
         select lg.raiz, lg.projeto from lg),
  lc as (select la.raiz, count(*)::int qtd from la where la.k is not null and la.k <> '' group by la.raiz),
  ul as (select s.raiz, max(s.em) em from (
           select g.raiz, o.quando em from g join pessoas.origens o on o.pessoa_id = g.membro
           union all
           select g.raiz, ev.quando from g join pessoas.eventos ev on ev.pessoa_id = g.membro
            where ev.tipo in ('mql', 'nao_mql', 'compra', 'checkout', 'reembolso')
           union all
           select g.raiz, ie.ocorreu_em from g join crm.evento_jornada ie on ie.pessoa_id = g.membro
            where (ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
               or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs)
           union all
           select neg.raiz, neg.criado_em from neg
           union all
           select neg.raiz, neg.ultima_interacao_em from neg
           union all
           select lg.raiz, lg.em from lg
           union all
           select g.raiz, a.concluida_em from g join crm.atividade a on a.pessoa_id = g.membro
            where a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
           union all
           select g.raiz, nt.em from g join crm.nota nt on nt.pessoa_id = g.membro
         ) s group by s.raiz)
  select ids.x, coalesce(ab.qtd, 0), coalesce(ab.j, '[]'::jsonb), coalesce(lc.qtd, 0), ul.em
    from ids
    left join ab on ab.raiz = ids.x
    left join lc on lc.raiz = ids.x
    left join ul on ul.raiz = ids.x;
end
$$;

-- Itens da lista, na ordem de p_pids (ids de crm.pessoa_comercial já filtrados por crm.contatos_visiveis: esta função
-- NÃO confere visibilidade, só a máscara). Mesmo jsonb de public.crm_contatos; com p_metricas, + lancamentos,
-- ultimaInteracaoEm e abertos.
create function crm.contatos_itens(p_pids uuid[], p_metricas boolean)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_meus uuid[]; v_atuais uuid[]; v jsonb;
begin
  if not coalesce(crm.eh_comercial(), false) or p_pids is null or cardinality(p_pids) = 0 then return '[]'::jsonb; end if;
  v_meus := case when v_gestor then '{}'::uuid[] else array(select crm.pessoas_negocio_meu()) end;
  v_atuais := array(select distinct case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end
                      from unnest(p_pids) u join pessoas.pessoas pp on pp.id = u);
  select coalesce(jsonb_agg(x.j order by x.o), '[]'::jsonb) into v from (
    select u.o, jsonb_build_object(
             'id', a.atual, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when c.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when c.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em)
           || case when p_metricas
                   then jsonb_build_object('lancamentos', coalesce(m.m_lancamentos, 0), 'ultimaInteracaoEm', m.m_ultima,
                                           'abertos', coalesce(m.m_abertos, '[]'::jsonb))
                   else '{}'::jsonb end j
      from unnest(p_pids) with ordinality u(pid, o)
      join crm.pessoa_comercial pc on pc.pessoa_id = u.pid
      join pessoas.pessoas pp on pp.id = pc.pessoa_id
     cross join lateral (select case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end atual) a
     cross join lateral (select coalesce(v_gestor or pc.dono_id = v_eu or pc.pessoa_id = any(v_meus), false) completo) c
      left join crm.dados_lote(v_atuais) d on d.d_pessoa = a.atual
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id
      left join crm.contatos_metricas(case when p_metricas then v_atuais else '{}'::uuid[] end) m on m.m_id = a.atual
  ) x;
  return v;
end
$$;

-- ─── RPCs ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Lista paginada da tela Contatos. Filtros e ordem no servidor; total = quantos passam nos filtros.
--   p_busca: a partir de 3 letras, mesma busca de crm_contatos (vendedor alcança todo sem dono).
--   p_dono: null/'todos' | 'sem_dono' | uuid do dono. p_perfil: null/'todos' | 'sem' | perfil. p_uf: null/'todas' | sigla.
--   p_tags: tem qualquer uma. p_ordem: criado | nome | dono | negocios | lancamentos | ultima. p_dir: asc | desc.
--   Empate: criado → pessoa (igual a crm_contatos); demais → nome, pessoa. Última interação vazia vai para o fim.
--   p_limite: 1 a 200 (padrão 50).
create function public.crm_contatos_pagina(
  p_busca text default null, p_dono text default null, p_perfil text default null, p_uf text default null,
  p_tags text[] default null, p_opt_out boolean default false, p_so_alunos boolean default false,
  p_ordem text default 'criado', p_dir text default 'desc', p_limite integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limite, 50), 1), 200);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_ordem text := coalesce(nullif(btrim(coalesce(p_ordem, '')), ''), 'criado');
  v_dir text := lower(coalesce(nullif(btrim(coalesce(p_dir, '')), ''), 'desc'));
  v_dono text := nullif(nullif(btrim(coalesce(p_dono, '')), ''), 'todos');
  v_perfil text := nullif(nullif(btrim(coalesce(p_perfil, '')), ''), 'todos');
  v_uf text := nullif(nullif(upper(btrim(coalesce(p_uf, ''))), ''), 'TODAS');
  v_asc boolean; v_dono_id uuid; v_ids uuid[]; v_total int; v_pids uuid[]; v_com_dados boolean;
begin
  perform crm.exige_comercial();
  if v_ordem not in ('criado', 'nome', 'dono', 'negocios', 'lancamentos', 'ultima') then
    raise exception 'Ordem inválida.' using errcode = '22023';
  end if;
  if v_dir not in ('asc', 'desc') then raise exception 'Direção inválida.' using errcode = '22023'; end if;
  v_asc := v_dir = 'asc';
  -- nome/aluno/UF de toda a lista só quando a ordem ou o filtro precisa (ordem por criação: só a página)
  v_com_dados := v_ordem <> 'criado';
  if v_dono is not null and v_dono <> 'sem_dono' then
    begin
      v_dono_id := v_dono::uuid;
    exception when invalid_text_representation then
      raise exception 'Dono inválido.' using errcode = '22023';
    end;
  end if;
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'total', 0); end if;
    v_ids := crm.contatos_candidatos(v_t);
  end if;

  if v_ordem in ('negocios', 'lancamentos', 'ultima') then
    -- ordem por métrica: calcula as métricas de todos os que passam no filtro (em lote) e pagina
    with b as (select * from crm.contatos_base(v_ids, v_dono = 'sem_dono', v_dono_id, v_perfil, v_uf, p_tags, p_opt_out, p_so_alunos, v_com_dados)),
    m as (select * from crm.contatos_metricas(array(select distinct b.b_atual from b)))
    select count(*)::int,
           (array_agg(b.b_pid order by
              case when v_asc then k.chave end asc nulls last,
              case when not v_asc then k.chave end desc nulls last,
              b.b_nome collate "pt-BR-x-icu", b.b_pid))[v_off + 1 : v_off + v_lim]
      into v_total, v_pids
      from b
      left join m on m.m_id = b.b_atual
     cross join lateral (select case v_ordem when 'negocios' then coalesce(m.m_qtd_abertos, 0)::numeric
                                             when 'lancamentos' then coalesce(m.m_lancamentos, 0)::numeric
                                             else extract(epoch from m.m_ultima)::numeric end chave) k;
  else
    select count(*)::int,
           (array_agg(b.b_pid order by
              case when v_ordem = 'criado' and v_asc then b.b_criado end asc,
              case when v_ordem = 'criado' and not v_asc then b.b_criado end desc,
              case when v_ordem = 'nome' and v_asc then b.b_nome end collate "pt-BR-x-icu" asc,
              case when v_ordem = 'nome' and not v_asc then b.b_nome end collate "pt-BR-x-icu" desc,
              case when v_ordem = 'dono' and v_asc then b.b_dono end collate "pt-BR-x-icu" asc,
              case when v_ordem = 'dono' and not v_asc then b.b_dono end collate "pt-BR-x-icu" desc,
              case when v_ordem = 'criado' then b.b_pid end,
              b.b_nome collate "pt-BR-x-icu", b.b_pid))[v_off + 1 : v_off + v_lim]
      into v_total, v_pids
      from crm.contatos_base(v_ids, v_dono = 'sem_dono', v_dono_id, v_perfil, v_uf, p_tags, p_opt_out, p_so_alunos, v_com_dados) b;
  end if;

  return jsonb_build_object('itens', crm.contatos_itens(coalesce(v_pids, '{}'::uuid[]), true), 'total', coalesce(v_total, 0));
end
$$;

-- Números do topo da tela Contatos e opções dos filtros, sobre a LISTA visível (mesma regra de crm_contatos sem busca).
create function public.crm_contatos_resumo()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  with b as (select * from crm.contatos_base(null, false, null, null, null, null, false, false, true))
  select jsonb_build_object(
           'total', count(*), 'semDono', count(*) filter (where b.b_dono_nulo),
           'optOut', count(*) filter (where b.b_opt_out), 'alunos', count(*) filter (where b.b_aluno),
           'ufs', coalesce((select jsonb_agg(s.uf order by s.uf) from (select distinct b2.b_uf uf from b b2 where b2.b_uf is not null) s), '[]'::jsonb),
           'tags', coalesce((select jsonb_agg(s.t order by s.t collate "pt-BR-x-icu")
                               from (select distinct t from b b3, unnest(b3.b_tags) t where t is not null and t <> '') s), '[]'::jsonb))
    into v
    from b;
  return v;
end
$$;

-- Contatos pelo id (fichas e telas que só precisam do nome dos contatos que mostram). Visibilidade e máscara da BUSCA
-- de crm_contatos: o que a busca acharia, esta função devolve; o que a pessoa não vê, some (nunca erro por item).
-- Ordem: criado_em desc, como crm_contatos. Id de alias resolve para a pessoa atual.
create function public.crm_contatos_por_ids(p_ids uuid[], p_duplicados boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_ids uuid[]; v_pids uuid[]; v jsonb;
begin
  perform crm.exige_comercial();
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('itens', '[]'::jsonb); end if;
  if cardinality(p_ids) > 1000 then raise exception 'No máximo 1.000 contatos por chamada.' using errcode = '22023'; end if;
  v_ids := array(select distinct gl.membro
                   from crm.grupo_lote(array(select distinct pessoas.atual(u) from unnest(p_ids) u where u is not null)) gl);
  v_pids := array(select cv.r_pessoa from crm.contatos_visiveis(v_ids) cv order by cv.r_criado desc, cv.r_pessoa);
  v := crm.contatos_itens(v_pids, false);
  if coalesce(p_duplicados, false) and cardinality(p_ids) <= 20 then
    select coalesce(jsonb_agg(e.item || jsonb_build_object('duplicados', dup.ids) order by e.o), '[]'::jsonb) into v
      from jsonb_array_elements(v) with ordinality e(item, o)
     cross join lateral (
       select coalesce(jsonb_agg(distinct cv.r_atual), '[]'::jsonb) ids
         from crm.dados_lote(array[(e.item->>'id')::uuid]) dl
        cross join lateral crm.contatos_visiveis(
                     case when pessoas.chave_telefone(dl.d_telefone) is not null
                          then crm.contatos_candidatos(dl.d_telefone) else '{}'::uuid[] end) cv
        where cv.r_atual <> (e.item->>'id')::uuid) dup;
  end if;
  return jsonb_build_object('itens', v);
end
$$;

-- ─── Permissões ───────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function crm.grupo_lote(uuid[]) from public, anon, authenticated, service_role;
revoke all on function crm.dados_lote(uuid[]) from public, anon, authenticated, service_role;
revoke all on function crm.contatos_candidatos(text) from public, anon, authenticated, service_role;
revoke all on function crm.contatos_visiveis(uuid[]) from public, anon, authenticated, service_role;
revoke all on function crm.contatos_base(uuid[], boolean, uuid, text, text, text[], boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function crm.contatos_metricas(uuid[]) from public, anon, authenticated, service_role;
revoke all on function crm.contatos_itens(uuid[], boolean) from public, anon, authenticated, service_role;

revoke all on function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer) from public, anon;
revoke all on function public.crm_contatos_resumo() from public, anon;
revoke all on function public.crm_contatos_por_ids(uuid[], boolean) from public, anon;
grant execute on function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer) to authenticated, service_role;
grant execute on function public.crm_contatos_resumo() to authenticated, service_role;
grant execute on function public.crm_contatos_por_ids(uuid[], boolean) to authenticated, service_role;

notify pgrst, 'reload schema';


-- ═══ FIM DO CORPO DA MIGRATION ═══

-- ─── 1. dados_lote = pessoas.dados (todos os contatos comerciais, como postgres) ───
with ids as (select distinct case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end id
               from crm.pessoa_comercial pc join pessoas.pessoas pp on pp.id = pc.pessoa_id),
a as (select * from crm.dados_lote(array(select id from ids))),
b as (select ids.id, d.* from ids cross join lateral pessoas.dados(ids.id) d)
select pg_temp.ok('1.dados_lote', count(*) filter (where (a.d_nome, a.d_email, a.d_telefone, a.d_aluno_id, a.d_comprador_id)
                                                     is distinct from (b.d_nome, b.d_email, b.d_telefone, b.d_aluno_id, b.d_comprador_id)) = 0
                                  and count(*) = (select count(*) from a),
  format('pessoas comparadas=%s, diferentes=%s, linhas do lote=%s', count(*),
         count(*) filter (where (a.d_nome, a.d_email, a.d_telefone, a.d_aluno_id, a.d_comprador_id)
                                is distinct from (b.d_nome, b.d_email, b.d_telefone, b.d_aluno_id, b.d_comprador_id)),
         (select count(*) from a)))
  from b left join a on a.d_pessoa = b.id;

-- ─── 2. Lista nova (pagina, ordem criado desc, lotes de 200) = lista antiga, item a item, por perfil ───
create temp table _new (k text, o int, item jsonb, total int) on commit drop;
do $$
declare r record; v jsonb; o int;
begin
  for r in select k, u from _v where k <> 'vis' order by k loop
    o := 0;
    loop
      v := pg_temp.chamar(r.u, format('select public.crm_contatos_pagina(p_ordem => ''criado'', p_dir => ''desc'', p_limite => 200, p_offset => %s)', o));
      if v ? 'erro' then raise exception 'pagina %: %', r.k, v ->> 'erro'; end if;
      insert into _new select r.k, o + e.i::int, e.item, (v ->> 'total')::int from jsonb_array_elements(v -> 'itens') with ordinality e(item, i);
      exit when jsonb_array_length(v -> 'itens') < 200 or o > 20000;
      o := o + 200;
    end loop;
  end loop;
end $$;
select pg_temp.ok('2.lista_' || x.k, x.n_old = x.n_new and x.total = x.n_old and x.dif = 0,
  format('antiga=%s nova=%s total=%s posições diferentes=%s mascarados=%s', x.n_old, x.n_new, x.total, x.dif, x.masc))
  from (select v.k,
               (select count(*) from _old o where o.k = v.k) n_old,
               (select count(*) from _new n where n.k = v.k) n_new,
               (select max(total) from _new n where n.k = v.k) total,
               (select count(*) from _old o full join _new n on n.k = o.k and n.o = o.o
                 where coalesce(o.k, n.k) = v.k
                   and (o.item is distinct from (n.item - 'lancamentos' - 'ultimaInteracaoEm' - 'abertos'))) dif,
               (select count(*) from _new n where n.k = v.k and n.item ->> 'email' like '%***@%') masc
          from _v v where v.k <> 'vis') x;

-- ─── 3. Resumo = contagem da lista antiga ───
create temp table _res (k text, r jsonb) on commit drop;
insert into _res select k, pg_temp.chamar(u, 'select public.crm_contatos_resumo()') from _v where k <> 'vis';
select pg_temp.ok('3.resumo_' || r.k,
       (r.r ->> 'total')::int = x.total and (r.r ->> 'semDono')::int = x.sem and (r.r ->> 'optOut')::int = x.opt
       and (r.r ->> 'alunos')::int = x.alu and r.r -> 'ufs' = x.ufs and r.r -> 'tags' = x.tags,
  format('total %s/%s semDono %s/%s optOut %s/%s alunos %s/%s ufs %s tags %s (resumo/antiga)',
         r.r ->> 'total', x.total, r.r ->> 'semDono', x.sem, r.r ->> 'optOut', x.opt, r.r ->> 'alunos', x.alu,
         jsonb_array_length(r.r -> 'ufs'), jsonb_array_length(r.r -> 'tags')))
  from _res r
  cross join lateral (
    select count(*)::int total, count(*) filter (where o.item ->> 'donoId' is null)::int sem,
           count(*) filter (where (o.item ->> 'optOut')::boolean)::int opt,
           count(*) filter (where (o.item ->> 'ehAluno')::boolean)::int alu,
           coalesce((select jsonb_agg(u order by u) from (select distinct o2.item ->> 'uf' u from _old o2 where o2.k = r.k and o2.item ->> 'uf' is not null) s), '[]') ufs,
           coalesce((select jsonb_agg(t order by t collate "pt-BR-x-icu") from (select distinct t from _old o3, jsonb_array_elements_text(o3.item -> 'tags') t
                      where o3.k = r.k and t <> '') s), '[]') tags
      from _old o where o.k = r.k) x;

-- ─── 4. por_ids = itens de crm_contatos ───
-- 4a. todos os ids da lista antiga (lotes de 1000): mesmos itens
create temp table _pid (k text, item jsonb) on commit drop;
do $$
declare r record; v jsonb; lote uuid[]; i int;
begin
  for r in select k, u from _v where k <> 'vis' order by k loop
    i := 0;
    loop
      lote := array(select (item ->> 'id')::uuid from _old where k = r.k order by o offset i limit 1000);
      exit when cardinality(lote) = 0;
      v := pg_temp.chamar(r.u, format('select public.crm_contatos_por_ids(%L::uuid[])', lote));
      if v ? 'erro' then raise exception 'por_ids %: %', r.k, v ->> 'erro'; end if;
      insert into _pid select r.k, e from jsonb_array_elements(v -> 'itens') e;
      i := i + 1000;
    end loop;
  end loop;
end $$;
select pg_temp.ok('4.por_ids_' || v.k,
       (select count(*) from _pid p where p.k = v.k) = (select count(*) from _old o where o.k = v.k)
       and not exists (select 1 from _old o where o.k = v.k
                        and not exists (select 1 from _pid p where p.k = v.k and p.item = o.item)),
  format('pedidos=%s devolvidos=%s iguais=%s', (select count(*) from _old o where o.k = v.k), (select count(*) from _pid p where p.k = v.k),
         (select count(*) from _old o where o.k = v.k and exists (select 1 from _pid p where p.k = v.k and p.item = o.item))))
  from _v v where v.k <> 'vis';

-- 4b. contato fora da LISTA do vendedor (sem dono, sem negócio aberto/sem dono) com e-mail: por_ids = busca de crm_contatos
create temp table _esc on commit drop as
select pc.pessoa_id, d.d_email email
  from crm.pessoa_comercial pc cross join lateral pessoas.dados(pc.pessoa_id) d
 where pc.dono_id is null and d.d_email is not null
   and not exists (select 1 from crm.negocio n where n.pessoa_id = pc.pessoa_id)
 order by pc.criado_em, pc.pessoa_id limit 1;
-- 4c. contato de outro vendedor, sem negócio do vendedor de teste: nem busca nem por_ids devolvem
create temp table _alheio on commit drop as
select pc.pessoa_id, d.d_email email, v.k
  from _v v
  join crm.pessoa_comercial pc on pc.dono_id is not null and pc.dono_id <> v.u
 cross join lateral pessoas.dados(pc.pessoa_id) d
 where v.k = (select min(k) from _v where k like 'vend_%') and d.d_email is not null
   and not exists (select 1 from crm.negocio n where n.pessoa_id = pc.pessoa_id and n.dono_id = v.u)
 order by pc.criado_em, pc.pessoa_id limit 1;
select pg_temp.ok('4.fora_da_lista_' || v.k,
       e.pessoa_id is not null
       and not exists (select 1 from _old o where o.k = v.k and (o.item ->> 'id')::uuid = e.pessoa_id)
       and pid.r -> 'itens' = bus.r -> 'itens' and jsonb_array_length(pid.r -> 'itens') = 1,
  format('fora da lista; por_ids=%s item(ns), busca=%s, iguais=%s, e-mail mascarado=%s',
         jsonb_array_length(pid.r -> 'itens'), jsonb_array_length(bus.r -> 'itens'), pid.r -> 'itens' = bus.r -> 'itens',
         pid.r -> 'itens' -> 0 ->> 'email' like '%***@%'))
  from _v v cross join _esc e
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos_por_ids(array[%L]::uuid[])', e.pessoa_id)) r) pid
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos(%L, 50, 0)', e.email)) r) bus
 where v.k like 'vend_%';
select pg_temp.ok('4.alheio_' || a.k, a.pessoa_id is not null and jsonb_array_length(pid.r -> 'itens') = 0 and jsonb_array_length(bus.r -> 'itens') = 0,
  format('contato de outro dono: por_ids=%s, busca=%s', jsonb_array_length(pid.r -> 'itens'), jsonb_array_length(bus.r -> 'itens')))
  from _alheio a join _v v on v.k = a.k
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos_por_ids(array[%L]::uuid[])', a.pessoa_id)) r) pid
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos(%L, 50, 0)', a.email)) r) bus;
-- 4d. duplicados: contatos com a mesma chave de telefone (gestor), pela regra do banco
create temp table _dup on commit drop as
select k.chave, array_agg(k.id order by k.id) ids
  from (select dl.d_pessoa id, controle.fone_key(dl.d_telefone) chave
          from crm.dados_lote(array(select pessoa_id from crm.pessoa_comercial)) dl) k
 where k.chave is not null group by k.chave having count(*) > 1;
select pg_temp.info('4.duplicados_base', format('chaves de telefone repetidas entre contatos: %s (%s contatos)',
                    count(*), coalesce(sum(cardinality(ids)), 0))) from _dup;
select pg_temp.ok('4.duplicados_gestor', (select count(*) from _dup) = 0 or x.achou,
  format('primeira chave repetida: por_ids(duplicados) devolveu os outros = %s', x.achou))
  from (select coalesce((select (r.v -> 'itens' -> 0 -> 'duplicados') @> to_jsonb(d.ids[2:]) or (r.v -> 'itens' -> 0 -> 'duplicados') @> to_jsonb(d.ids[1:1])
                           from (select * from _dup order by chave limit 1) d
                          cross join lateral (select pg_temp.chamar((select u from _v where k = 'gestor'),
                                     format('select public.crm_contatos_por_ids(array[%L]::uuid[], true)', d.ids[1])) v) r), false) achou) x;

-- ─── 5. Busca igual à de crm_contatos (e-mail, telefone, nome) ───
create temp table _termos (rot text, t text) on commit drop;
insert into _termos select 'email', email from _esc;
insert into _termos select 'telefone', right(d.d_telefone, 8) from crm.pessoa_comercial pc cross join lateral pessoas.dados(pc.pessoa_id) d
 where d.d_telefone is not null order by pc.criado_em desc, pc.pessoa_id limit 1;
insert into _termos select 'telefone_completo', d.d_telefone from crm.pessoa_comercial pc cross join lateral pessoas.dados(pc.pessoa_id) d
 where d.d_telefone is not null order by pc.criado_em desc, pc.pessoa_id limit 1;
insert into _termos select 'nome', lower(left(split_part(d.d_nome, ' ', 1), 4)) from crm.pessoa_comercial pc cross join lateral pessoas.dados(pc.pessoa_id) d
 where length(split_part(d.d_nome, ' ', 1)) >= 4 order by pc.criado_em desc, pc.pessoa_id limit 1;
select pg_temp.ok('5.busca_' || t.rot || '_' || v.k, a.ids = b.ids,
  format('crm_contatos=%s pagina=%s total=%s iguais=%s', cardinality(a.ids), cardinality(b.ids), b.total, a.ids = b.ids))
  from _termos t cross join _v v
 cross join lateral (select array(select e ->> 'id' from jsonb_array_elements(pg_temp.chamar(v.u, format('select public.crm_contatos(%L, 500, 0)', t.t)) -> 'itens') e order by 1) ids) a
 cross join lateral (select r ->> 'total' total, array(select e ->> 'id' from jsonb_array_elements(r -> 'itens') e order by 1) ids
                       from (select pg_temp.chamar(v.u, format('select public.crm_contatos_pagina(p_busca => %L, p_limite => 200)', t.t)) r) z) b
 where v.k in ('gestor', (select min(k) from _v where k like 'vend_%'));

-- ─── 6. Métricas ───
-- 6a. negócios abertos por contato = crm_negocios (status aberto) visto pelo mesmo perfil
create temp table _ab (k text, contato text, n int) on commit drop;
insert into _ab select v.k, e ->> 'contatoId', count(*)
  from _v v cross join lateral jsonb_array_elements(pg_temp.chamar(v.u, 'select public.crm_negocios(null, ''aberto'', null, 2000, 0)')) e
 where v.k <> 'vis' group by 1, 2;
select pg_temp.ok('6.abertos_' || v.k, x.dif = 0,
  format('contatos com negócio aberto=%s, diferenças entre pagina e crm_negocios=%s', x.com, x.dif))
  from _v v cross join lateral (
    select count(*) filter (where coalesce(jsonb_array_length(n.item -> 'abertos'), 0) > 0) com,
           count(*) filter (where coalesce(jsonb_array_length(n.item -> 'abertos'), 0) <> coalesce(a.n, 0)) dif
      from _new n left join _ab a on a.k = n.k and a.contato = n.item ->> 'id' where n.k = v.k) x
 where v.k <> 'vis';
-- 6b. lançamentos e última interação x jornada da ficha (crm_jornada + última interação dos negócios), amostra do gestor
create temp table _amostra on commit drop as
(select (item ->> 'id')::uuid id from _new where k = 'gestor' and jsonb_array_length(item -> 'abertos') > 0 order by o limit 8)
union (select (item ->> 'id')::uuid from _new where k = 'gestor' and (item ->> 'ehAluno')::boolean order by o limit 8)
union (select (item ->> 'id')::uuid from _new where k = 'gestor' order by o desc limit 8);
create temp table _cmp on commit drop as
select a.id, (n.item ->> 'lancamentos')::int lanc_novo, (n.item ->> 'ultimaInteracaoEm')::timestamptz ult_novo,
       (select count(distinct p ->> 'lancamento') from jsonb_array_elements(j.r) p where coalesce(p ->> 'lancamento', '') <> '') lanc_ficha,
       greatest((select max((p ->> 'em')::timestamptz) from jsonb_array_elements(j.r) p),
                (select max(nn.ultima_interacao_em) from crm.negocio nn where nn.pessoa_id = a.id)) ult_ficha
  from _amostra a
  join _new n on n.k = 'gestor' and (n.item ->> 'id')::uuid = a.id
 cross join lateral (select pg_temp.chamar((select u from _v where k = 'gestor'), format('select public.crm_jornada(%L)', a.id)) r) j;
select pg_temp.ok('6.lancamentos_amostra', count(*) filter (where lanc_novo <> lanc_ficha) = 0,
  format('amostra=%s, lançamentos iguais à ficha=%s, com lançamento=%s', count(*), count(*) filter (where lanc_novo = lanc_ficha),
         count(*) filter (where lanc_ficha > 0))) from _cmp;
select pg_temp.info('6.ultima_amostra',
  format('amostra=%s, última interação igual à ficha=%s, diferente=%s (maior diferença: %s)', count(*),
         count(*) filter (where ult_novo is not distinct from ult_ficha), count(*) filter (where ult_novo is distinct from ult_ficha),
         max(abs(extract(epoch from ult_novo - ult_ficha))) filter (where ult_novo is distinct from ult_ficha) || ' s')) from _cmp;

-- ─── 7. Filtros e ordenação (gestor e 1º vendedor) ───
select pg_temp.ok('7.filtros_' || v.k,
       (f.sem ->> 'total')::int = (select count(*) from _old o where o.k = v.k and o.item ->> 'donoId' is null)
       and (f.opt ->> 'total')::int = (select count(*) from _old o where o.k = v.k and (o.item ->> 'optOut')::boolean)
       and (f.alu ->> 'total')::int = (select count(*) from _old o where o.k = v.k and (o.item ->> 'ehAluno')::boolean)
       and (f.uf ->> 'total')::int = (select count(*) from _old o where o.k = v.k and o.item ->> 'uf' = x.uf)
       and (f.sper ->> 'total')::int = (select count(*) from _old o where o.k = v.k and coalesce(o.item ->> 'perfil', '') = '')
       and (f.dono ->> 'total')::int = (select count(*) from _old o where o.k = v.k and o.item ->> 'donoId' = v.u::text),
  format('sem dono %s, opt-out %s, alunos %s, uf %s, sem perfil %s, dono=eu %s', f.sem ->> 'total', f.opt ->> 'total', f.alu ->> 'total',
         f.uf ->> 'total', f.sper ->> 'total', f.dono ->> 'total'))
  from _v v
 cross join lateral (select coalesce((select o.item ->> 'uf' from _old o where o.k = v.k and o.item ->> 'uf' is not null limit 1), 'SP') uf) x
 cross join lateral (select
     pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_dono => ''sem_dono'', p_limite => 1)') sem,
     pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_opt_out => true, p_limite => 1)') opt,
     pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_so_alunos => true, p_limite => 1)') alu,
     pg_temp.chamar(v.u, format('select public.crm_contatos_pagina(p_uf => %L, p_limite => 1)', x.uf)) uf,
     pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_perfil => ''sem'', p_limite => 1)') sper,
     pg_temp.chamar(v.u, format('select public.crm_contatos_pagina(p_dono => %L, p_limite => 1)', v.u)) dono) f
 where v.k in ('gestor', (select min(k) from _v where k like 'vend_%'));
-- ordem: última interação desc (vazias no fim), negócios desc, nome asc, página 2 continua a 1
create temp table _ord (rot text, o int, item jsonb) on commit drop;
insert into _ord select 'ultima', e.i, e.item from jsonb_array_elements(pg_temp.chamar((select u from _v where k = 'gestor'),
  'select public.crm_contatos_pagina(p_ordem => ''ultima'', p_dir => ''desc'', p_limite => 200)') -> 'itens') with ordinality e(item, i);
insert into _ord select 'negocios', e.i, e.item from jsonb_array_elements(pg_temp.chamar((select u from _v where k = 'gestor'),
  'select public.crm_contatos_pagina(p_ordem => ''negocios'', p_dir => ''desc'', p_limite => 200)') -> 'itens') with ordinality e(item, i);
insert into _ord select 'nome', e.i, e.item from jsonb_array_elements(pg_temp.chamar((select u from _v where k = 'gestor'),
  'select public.crm_contatos_pagina(p_ordem => ''nome'', p_dir => ''asc'', p_limite => 200)') -> 'itens') with ordinality e(item, i);
select pg_temp.ok('7.ordem',
       not exists (select 1 from _ord a join _ord b on b.rot = a.rot and b.o = a.o + 1 where a.rot = 'ultima'
                    and ((a.item ->> 'ultimaInteracaoEm') is null and (b.item ->> 'ultimaInteracaoEm') is not null
                         or (a.item ->> 'ultimaInteracaoEm')::timestamptz < (b.item ->> 'ultimaInteracaoEm')::timestamptz))
       and not exists (select 1 from _ord a join _ord b on b.rot = a.rot and b.o = a.o + 1 where a.rot = 'negocios'
                        and jsonb_array_length(a.item -> 'abertos') < jsonb_array_length(b.item -> 'abertos'))
       and not exists (select 1 from _ord a join _ord b on b.rot = a.rot and b.o = a.o + 1 where a.rot = 'nome'
                        and lower(a.item ->> 'nome') collate "pt-BR-x-icu" > lower(b.item ->> 'nome') collate "pt-BR-x-icu"),
  format('200 primeiros: última desc, negócios desc e nome asc em ordem; maior qtd de abertos=%s; itens=%s',
         (select max(jsonb_array_length(item -> 'abertos')) from _ord where rot = 'negocios'), (select count(*) from _ord)));
select pg_temp.ok('7.paginas_sem_sobra', (select count(distinct item ->> 'id') from _new where k = 'gestor') = (select count(*) from _new where k = 'gestor'),
  'páginas de 200 da lista do gestor sem repetição');

-- ─── 8. Guardas e permissões ───
select pg_temp.ok('8.visualizador_barrado',
       a.r ->> 'estado' = '42501' and b.r ->> 'estado' = '42501' and c.r ->> 'estado' = '42501',
  format('pagina=%s resumo=%s por_ids=%s', a.r ->> 'estado', b.r ->> 'estado', c.r ->> 'estado'))
  from _v v
 cross join lateral (select pg_temp.chamar(v.u, 'select public.crm_contatos_pagina()') r) a
 cross join lateral (select pg_temp.chamar(v.u, 'select public.crm_contatos_resumo()') r) b
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos_por_ids(array[%L]::uuid[])', (select item ->> 'id' from _new limit 1))) r) c
 where v.k = 'vis';
select pg_temp.ok('8.parametros_invalidos',
       a.r ->> 'estado' = '22023' and b.r ->> 'estado' = '22023' and c.r ->> 'estado' = '22023' and d.r ->> 'estado' = '22023',
  format('ordem=%s dir=%s dono=%s por_ids>1000=%s', a.r ->> 'estado', b.r ->> 'estado', c.r ->> 'estado', d.r ->> 'estado'))
  from _v v
 cross join lateral (select pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_ordem => ''x'')') r) a
 cross join lateral (select pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_dir => ''x'')') r) b
 cross join lateral (select pg_temp.chamar(v.u, 'select public.crm_contatos_pagina(p_dono => ''x'')') r) c
 cross join lateral (select pg_temp.chamar(v.u, format('select public.crm_contatos_por_ids(%L::uuid[])',
                       array(select gen_random_uuid() from generate_series(1, 1001))) ) r) d
 where v.k = 'gestor';
select pg_temp.ok('8.anon_sem_execute',
       not has_function_privilege('anon', 'public.crm_contatos_pagina(text,text,text,text,text[],boolean,boolean,text,text,integer,integer)', 'execute')
       and not has_function_privilege('anon', 'public.crm_contatos_resumo()', 'execute')
       and not has_function_privilege('anon', 'public.crm_contatos_por_ids(uuid[],boolean)', 'execute')
       and has_function_privilege('authenticated', 'public.crm_contatos_pagina(text,text,text,text,text[],boolean,boolean,text,text,integer,integer)', 'execute'),
  'anon sem execute nas 3 RPCs; authenticated com');
select pg_temp.ok('8.ajudantes_fechados',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'crm' and p.proname in ('grupo_lote', 'dados_lote', 'contatos_candidatos', 'contatos_visiveis',
                                                              'contatos_base', 'contatos_metricas', 'contatos_itens')
                      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                           or has_function_privilege('service_role', p.oid, 'execute'))),
  (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '(padrão)'), ' | ' order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm' and p.proname in ('grupo_lote', 'dados_lote', 'contatos_candidatos', 'contatos_visiveis',
                                              'contatos_base', 'contatos_metricas', 'contatos_itens')));
select pg_temp.info('8.proacl_rpcs', (select string_agg(p.proname || ' ' || p.proacl::text || ' definer=' || p.prosecdef, ' | ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('crm_contatos_pagina', 'crm_contatos_resumo', 'crm_contatos_por_ids')));

-- ─── 9. Tempos (chamada inteira como a tela, 2×) e explain analyze (2×) ───
do $$
declare g uuid := (select u from _v where k = 'gestor'); vd uuid := (select u from _v where k = (select min(k) from _v where k like 'vend_%'));
        ids200 text := (select array(select item ->> 'id' from _new where k = 'gestor' order by o limit 200))::text;
        i int;
begin
  for i in 1..2 loop
    insert into _tempo values ('gestor', 'antes: crm_contatos(null,500,0) #' || i, pg_temp.ms(g, 'select public.crm_contatos(null, 500, 0)'));
    insert into _tempo values ('vend', 'antes: crm_contatos(null,500,0) #' || i, pg_temp.ms(vd, 'select public.crm_contatos(null, 500, 0)'));
    insert into _tempo values ('gestor', 'depois: pagina 50 criado #' || i, pg_temp.ms(g, 'select public.crm_contatos_pagina()'));
    insert into _tempo values ('vend', 'depois: pagina 50 criado #' || i, pg_temp.ms(vd, 'select public.crm_contatos_pagina()'));
    insert into _tempo values ('gestor', 'depois: pagina 50 ultima desc #' || i, pg_temp.ms(g, 'select public.crm_contatos_pagina(p_ordem => ''ultima'')'));
    insert into _tempo values ('vend', 'depois: pagina 50 ultima desc #' || i, pg_temp.ms(vd, 'select public.crm_contatos_pagina(p_ordem => ''ultima'')'));
    insert into _tempo values ('gestor', 'depois: pagina 50 nome asc #' || i, pg_temp.ms(g, 'select public.crm_contatos_pagina(p_ordem => ''nome'', p_dir => ''asc'')'));
    insert into _tempo values ('gestor', 'depois: resumo #' || i, pg_temp.ms(g, 'select public.crm_contatos_resumo()'));
    insert into _tempo values ('vend', 'depois: resumo #' || i, pg_temp.ms(vd, 'select public.crm_contatos_resumo()'));
    insert into _tempo values ('gestor', 'depois: por_ids 200 #' || i, pg_temp.ms(g, format('select public.crm_contatos_por_ids(%L::uuid[])', ids200)));
    insert into _tempo values ('gestor', 'depois: por_ids 1 + duplicados #' || i,
      pg_temp.ms(g, format('select public.crm_contatos_por_ids(array[%L]::uuid[], true)', (select item ->> 'id' from _new where k = 'gestor' order by o limit 1))));
  end loop;
end $$;
select pg_temp.info('9.tempo', format('%s | %s: %s ms', k, rotulo, ms)) from _tempo order by rotulo, k;

-- explain analyze (2×) da RPC inteira como a tela (authenticated + JWT) e do miolo (dados em lote × linha a linha)
create temp table _plano (rot text, n int, linha text) on commit drop;
-- as linhas do plano ficam num array até voltar a postgres (authenticated não grava na temp)
create function pg_temp.explica(p_rot text, p_perfil uuid, p_sql text) returns void language plpgsql as $$
declare r record; v_linhas text[] := '{}';
begin
  if p_perfil is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
  for r in execute 'explain (analyze, buffers) ' || p_sql loop
    v_linhas := v_linhas || r."QUERY PLAN";
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into _plano select p_rot, t.n, t.l from unnest(v_linhas) with ordinality t(l, n);
end $$;
select pg_temp.explica('pagina_gestor_' || i, (select u from _v where k = 'gestor'), 'select public.crm_contatos_pagina()') from generate_series(1, 2) i;
select pg_temp.explica('pagina_ultima_gestor_' || i, (select u from _v where k = 'gestor'), 'select public.crm_contatos_pagina(p_ordem => ''ultima'')') from generate_series(1, 2) i;
select pg_temp.explica('pagina_vend_' || i, (select u from _v where k = (select min(k) from _v where k like 'vend_%')), 'select public.crm_contatos_pagina()') from generate_series(1, 2) i;
select pg_temp.explica('resumo_gestor_' || i, (select u from _v where k = 'gestor'), 'select public.crm_contatos_resumo()') from generate_series(1, 2) i;
select pg_temp.explica('antigo_gestor_' || i, (select u from _v where k = 'gestor'), 'select public.crm_contatos(null, 500, 0)') from generate_series(1, 2) i;
select pg_temp.explica('miolo_dados_linha_a_linha_' || i, null,
  'select d.* from crm.pessoa_comercial pc cross join lateral pessoas.dados(pc.pessoa_id) d') from generate_series(1, 2) i;
select pg_temp.explica('miolo_dados_lote_' || i, null,
  'select * from crm.dados_lote(array(select pessoa_id from crm.pessoa_comercial))') from generate_series(1, 2) i;
select pg_temp.info('9.explain_' || rot, string_agg(btrim(linha), ' ‖ ' order by n))
  from _plano where linha ~ '(Execution Time|Planning Time|^\S|Function Scan|Seq Scan|Buffers)' group by rot order by rot;

-- ─── Saída: a exceção aborta a transação (nada persiste) e devolve as linhas ───
do $saida$
begin
  raise exception E'ENSAIO 20261006m (rollback)\n%', (select string_agg(passo || ' = ' || linha, E'\n' order by em) from _z_out);
end
$saida$;
rollback;
