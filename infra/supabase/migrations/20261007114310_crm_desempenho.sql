-- 20261006m: CRM Comercial: desempenho da base de contatos (passo 2 do diagnóstico de 06/10/2026).
--
-- STATUS: NÃO APLICADA. Ensaiada em begin … rollback no banco de produção (mbvybujpkwuorhtdzcde) em 06/10/2026:
--   20261006m_ensaio.sql. Notas, números e decisões: 20261006m.explain.md.
--   Doc: docs/projetos/comercial/ajuste-rapido-2026-10-06.md (seção final, "passo 2").
--
-- O PROBLEMA: 9 telas do Comercial baixam a lista INTEIRA de contatos (2.649 em 06/10/2026, em lotes de 500), e cada
--   lote de crm_contatos custa ~400 ms porque monta cada contato com pessoas.dados() linha a linha (CTE recursiva +
--   2 subconsultas por linha). A tela Contatos ainda filtra, ordena e conta no navegador.
--
-- O QUE FAZ (só cria; NENHUMA função existente é alterada):
--   Ajudantes no schema crm (fora da API; sem execute para public/anon/authenticated/service_role; só rodam dentro
--   das RPCs SECURITY DEFINER abaixo):
--     crm.grupo_lote(uuid[])            grupo de alias de várias pessoas de uma vez (mesma regra de pessoas.grupo)
--     crm.dados_lote(uuid[])            pessoas.dados() de várias pessoas num join único (saída provada igual)
--     crm.contatos_candidatos(text)     candidatos da busca por e-mail/telefone/nome (bloco copiado de crm_contatos)
--     crm.contatos_visiveis(uuid[])     quem a pessoa logada vê, com a regra VIVA de crm_contatos (20261006191824):
--                                       null = regra da LISTA; ids = regra da BUSCA (vendedor alcança todo sem dono)
--     crm.contatos_base(...)            lista visível com os filtros da tela e as chaves de ordenação
--     crm.contatos_metricas(uuid[])     negócios abertos, lançamentos e última interação, em lote
--     crm.contatos_itens(uuid[], bool)  o item da lista (mesmo jsonb de crm_contatos, mesma máscara)
--   RPCs novas (SECURITY DEFINER, guarda crm.exige_comercial, execute para authenticated e service_role, como
--   crm_contatos):
--     public.crm_contatos_pagina(busca, dono, perfil, uf, tags, opt_out, so_alunos, ordem, dir, limite, offset)
--         → {itens, total}: filtro, ordenação e paginação no servidor. Cada item = item de crm_contatos +
--           lancamentos, ultimaInteracaoEm e abertos [{id, produto, etapaNome}].
--     public.crm_contatos_resumo()      → {total, semDono, optOut, alunos, ufs[], tags[]} (números do topo e filtros)
--     public.crm_contatos_por_ids(uuid[], duplicados)
--         → {itens}: contatos pelo id, com a visibilidade e a máscara da BUSCA de crm_contatos (até 1.000 ids).
--           Com duplicados = true (até 20 ids), cada item traz 'duplicados': ids de outros contatos visíveis com a
--           mesma chave de telefone (DDD + últimos 8 dígitos, controle.fone_key).
--
-- O QUE NÃO FAZ: não toca crm_contatos, crm_negocios, crm_atividades, crm_jornada, pessoas.dados, RLS nem dado.
--   Filtro por funil/status em crm_negocios JÁ EXISTE (p_funil, p_status, p_pessoa): nada a mudar no banco.
--   crm_atividades sem filtro novo (0 atividades em 06/10). Nenhum índice novo: os que estas funções usam já existem
--   (ver 20261006m.explain.md, seção Índices).
--
-- REVERSÃO: bloco comentado no fim (drop das 3 RPCs e dos 7 ajudantes). O front volta sozinho ao caminho antigo quando
--   a RPC não existe (erro 42883/PGRST202).

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

-- ─── REVERSÃO (não roda; copiar e executar se precisar desfazer) ──────────────────────────────────────────────────
-- drop function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer);
-- drop function public.crm_contatos_resumo();
-- drop function public.crm_contatos_por_ids(uuid[], boolean);
-- drop function crm.contatos_itens(uuid[], boolean);
-- drop function crm.contatos_metricas(uuid[]);
-- drop function crm.contatos_base(uuid[], boolean, uuid, text, text, text[], boolean, boolean, boolean);
-- drop function crm.contatos_visiveis(uuid[]);
-- drop function crm.contatos_candidatos(text);
-- drop function crm.dados_lote(uuid[]);
-- drop function crm.grupo_lote(uuid[]);
-- notify pgrst, 'reload schema';
