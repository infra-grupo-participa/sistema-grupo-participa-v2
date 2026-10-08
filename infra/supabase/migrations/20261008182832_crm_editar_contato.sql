-- 20261008182832 crm_editar_contato — APLICADA em 08/10/2026 (md5 dos statements gravados = 5c7f2648241fd51ad1d501cc56c820ff = este arquivo SEM estas 4 linhas de cabeçalho).
-- Edição manual do contato (public.crm_editar_contato) com override em crm.contato_ajuste lido por cima da base central
-- (crm.dados_lote, crm.nome_pessoa, crm.contatos_itens, crm.contatos_candidatos). Escrita como 20261008ce.
-- Ensaio: 20261008182832_ensaio.sql · decisões e medidas: 20261008182832.explain.md
set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- Premissa: corpos vivos que esta migration recria são os lidos em 08/10/2026 (pg_get_functiondef) e a tabela é nova.
do $g$
declare r record;
begin
  for r in select * from (values
    ('crm.dados_lote(uuid[])', '239ff5b0270dda0f92ed1552a302fdbc'),
    ('crm.contatos_itens(uuid[],boolean)', '74382f2ee1c9d1efe21bf6f66b17ab73'),
    ('crm.nome_pessoa(uuid)', 'd420abe7f5bc94525128d82bce2a66d2'),
    ('crm.contatos_candidatos(text)', '56ff226a63d58cf5c1696f54e977ea1e')
  ) v(fn, esperado) loop
    if md5(pg_get_functiondef(r.fn::regprocedure)) <> r.esperado then
      raise exception 'premissa: % mudou (md5 vivo %, esperado %)', r.fn, md5(pg_get_functiondef(r.fn::regprocedure)), r.esperado;
    end if;
  end loop;
  if to_regclass('crm.contato_ajuste') is not null then raise exception 'premissa: crm.contato_ajuste já existe'; end if;
  if to_regprocedure('public.crm_editar_contato(uuid,jsonb)') is not null then
    raise exception 'premissa: public.crm_editar_contato já existe';
  end if;
  if to_regprocedure('crm.guarda_escrita()') is null or to_regprocedure('crm.pode_escrever_pessoa(uuid)') is null
     or to_regprocedure('crm.log_registrar(text,text,text,uuid,text,jsonb)') is null or to_regprocedure('pessoas.anexar(uuid,text,text,text,text)') is null then
    raise exception 'premissa: helpers do CRM/pessoas ausentes';
  end if;
end $g$;

-- ── 1. Ajuste manual do contato, lido POR CIMA da base central ──
-- A base central (pessoas.*) não tem fonte/prioridade para nome, cidade etc.: o nome vem de thb_alunos > compradores >
-- pessoas.nome, reescritos pela ingestão (Hotmart, alunos). Escrever lá corromperia outros sistemas e seria desfeito na
-- próxima carga. Aqui mora só o que a equipe comercial corrigiu à mão; nenhuma ingestão escreve nesta tabela.
-- E-mail/telefone novos TAMBÉM entram na base central como identificador de origem 'crm' (pessoas.anexar, o mecanismo
-- dela, nunca apaga); aqui fica só qual deles é o principal na tela do CRM.
create table crm.contato_ajuste (
  pessoa_id uuid primary key references pessoas.pessoas(id) on delete restrict,
  nome text check (nome is null or length(btrim(nome)) between 2 and 160),
  email text check (email is null or length(email) between 3 and 320),
  telefone text check (telefone is null or telefone ~ '^[0-9]{10,11}$'),
  cidade text check (cidade is null or length(btrim(cidade)) between 1 and 120),
  uf text check (uf is null or uf ~ '^[A-Z]{2}$'),
  empresa text check (empresa is null or length(btrim(empresa)) between 1 and 160),
  observacao text check (observacao is null or length(observacao) between 1 and 1000),
  atualizado_por uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table crm.contato_ajuste is
  'Correção manual do contato pelo Comercial (crm_editar_contato), lida por cima de pessoas.* em crm.dados_lote, crm.nome_pessoa e crm.contatos_itens. Nunca escrita por ingestão. Apagar a linha = voltar ao dado da base central.';
alter table crm.contato_ajuste enable row level security;
-- Sem policy e sem grant: só as funções SECURITY DEFINER do CRM leem/escrevem (o dado volta mascarado pelas regras de sempre).
revoke all on table crm.contato_ajuste from public, anon, authenticated;

-- ── 2. Leitura por cima: dados_lote (nome/e-mail/telefone de toda tela do CRM) ──
create or replace function crm.dados_lote(p_ids uuid[])
 returns table(d_pessoa uuid, d_nome text, d_email text, d_telefone text, d_aluno_id uuid, d_comprador_id uuid)
 language sql
 stable
 set search_path to ''
as $function$
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
          order by g.raiz, i.id desc),
  -- 20261008ce: correção manual do Comercial (crm.contato_ajuste) vence a base central, só na leitura do CRM.
  aj as (select distinct on (g.raiz) g.raiz, x.nome, x.email, x.telefone
           from g join crm.contato_ajuste x on x.pessoa_id = g.membro
          order by g.raiz, x.pessoa_id = g.raiz desc, x.atualizado_em desc)
  select ids.x,
         coalesce(aj.nome, a.nome, c.nome::text, r.nome),
         coalesce(aj.email, pessoas.norm_email(a.email), pessoas.norm_email(c.email::text), ie.valor),
         coalesce(aj.telefone, pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone)), pessoas.norm_telefone(c.telefone::text), it.valor),
         r.aluno_id,
         coalesce(r.comprador_id, a.comprador_id)
    from ids
    left join r on r.raiz = ids.x
    left join public.thb_alunos a on a.id = r.aluno_id
    left join public.compradores c on c.id = coalesce(r.comprador_id, a.comprador_id)
    left join ie on ie.raiz = ids.x
    left join it on it.raiz = ids.x
    left join aj on aj.raiz = ids.x;
$function$;

-- ── 3. nome_pessoa (resumos do log, mensagens do CRM) ──
create or replace function crm.nome_pessoa(p uuid)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- 20261008ce: nome corrigido no Comercial (crm.contato_ajuste) vence o da base central.
  select coalesce((select x.nome from crm.contato_ajuste x
                    where x.pessoa_id = any(pessoas.grupo(pessoas.atual(p))) and x.nome is not null
                    order by x.pessoa_id = pessoas.atual(p) desc, x.atualizado_em desc limit 1),
                  (select d.d_nome from pessoas.dados(pessoas.atual(p)) d), 'contato');
$function$;

-- ── 4. contatos_itens: cidade/UF corrigidas + empresa e observação ──
create or replace function crm.contatos_itens(p_pids uuid[], p_metricas boolean)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_leitor boolean := coalesce(crm.eh_leitor(), false);  -- 20261008lt: leitor vê tudo, e-mail/telefone mascarados
  v_meus uuid[]; v_atuais uuid[]; v jsonb;
begin
  if not coalesce(crm.eh_comercial(), false) or p_pids is null or cardinality(p_pids) = 0 then return '[]'::jsonb; end if;
  v_meus := case when v_gestor then '{}'::uuid[] else array(select crm.pessoas_negocio_meu()) end;
  v_atuais := array(select distinct case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end
                      from unnest(p_pids) u join pessoas.pessoas pp on pp.id = u);
  select coalesce(jsonb_agg(x.j order by x.o), '[]'::jsonb) into v from (
    -- 20261008ce: correção manual (crm.contato_ajuste) por grupo de alias
    with aj as (select distinct on (gl.raiz) gl.raiz, ca.cidade, ca.uf, ca.empresa, ca.observacao
                  from crm.grupo_lote(v_atuais) gl join crm.contato_ajuste ca on ca.pessoa_id = gl.membro
                 order by gl.raiz, ca.pessoa_id = gl.raiz desc, ca.atualizado_em desc)
    select u.o, jsonb_build_object(
             'id', a.atual, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when c.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when c.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(aj.cidade, al.cidade, cp.endereco_cidade::text),
             'uf', coalesce(aj.uf, case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end),
             'empresa', aj.empresa, 'observacao', aj.observacao,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em,
             'origem', case when po.pessoa_id is null then null
                            else jsonb_build_object('canal', po.canal_entrada, 'entrouEm', po.entrou_em, 'projeto', po.projeto,
                                                    'projetoNome', crm.projeto_nome(po.projeto), 'linha', po.linha,
                                                    'mqlDesde', po.mql_desde) end)
           || case when p_metricas
                   then jsonb_build_object('lancamentos', coalesce(m.m_lancamentos, 0), 'ultimaInteracaoEm', m.m_ultima,
                                           'abertos', coalesce(m.m_abertos, '[]'::jsonb))
                   else '{}'::jsonb end j
      from unnest(p_pids) with ordinality u(pid, o)
      join crm.pessoa_comercial pc on pc.pessoa_id = u.pid
      join pessoas.pessoas pp on pp.id = pc.pessoa_id
      left join crm.pessoa_origem po on po.pessoa_id = pc.pessoa_id
     cross join lateral (select case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end atual) a
     cross join lateral (select coalesce((v_gestor and not v_leitor) or pc.dono_id = v_eu or pc.pessoa_id = any(v_meus), false) completo) c
      left join crm.dados_lote(v_atuais) d on d.d_pessoa = a.atual
      left join aj on aj.raiz = a.atual
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id
      left join crm.contatos_metricas(case when p_metricas then v_atuais else '{}'::uuid[] end) m on m.m_id = a.atual
  ) x;
  return v;
end
$function$;

-- ── 5. Busca acha o nome corrigido ──
create or replace function crm.contatos_candidatos(p_texto text)
 returns uuid[]
 language plpgsql
 stable
 set search_path to ''
as $function$
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
      -- 20261008ce: nome corrigido no Comercial
      union (select x.pessoa_id from crm.contato_ajuste x where v_like is not null and x.nome ilike v_like limit 200)
    ) s);
  return array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
end
$function$;

-- ── 6. RPC de escrita ──
create function public.crm_editar_contato(p_contato uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
-- 20261008ce: edição manual do contato pela ficha. Guarda do leitor (crm.guarda_escrita) + crm.pode_escrever_pessoa
-- (gestor; vendedor dono do contato ou de negócio da pessoa — espelho de podeEscreverContato). Só as chaves presentes em
-- p_dados mudam. Nome/cidade/UF/empresa/observação e o e-mail/telefone principal vão para crm.contato_ajuste (lido por
-- cima da base central); e-mail/telefone novos entram também em pessoas.identificadores (origem 'crm', nunca apaga);
-- perfil e holding são do próprio CRM (crm.pessoa_comercial). O log registra QUAIS campos mudaram, nunca o valor.
declare
  v_r jsonb; v_eu uuid := auth.uid();
  v_atual uuid; v_pc uuid; v_grupo uuid[]; v_aj crm.contato_ajuste%rowtype; v_tem_aj boolean;
  v_pc_perfil text; v_pc_holding text;
  v_nome text; v_email text; v_tel text; v_cidade text; v_uf text; v_empresa text; v_obs text; v_perfil text; v_holding text;
  v_campos text[] := '{}'; v_mexe_aj boolean := false; v_mexe_pc boolean := false; v_outros uuid[];
  v_s text; v_c text; v_m text;
begin
  perform crm.exige_comercial();
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_contato is null then return crm.res(false, 'Contato inválido.'); end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;

  v_atual := pessoas.atual(p_contato);
  if v_atual is null or not exists (select 1 from pessoas.pessoas where id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if not coalesce(crm.pode_escrever_pessoa(v_atual), false) then
    return crm.res(false, 'Este contato não é seu: só o dono ou o gestor edita.');
  end if;
  v_grupo := pessoas.grupo(v_atual);
  v_pc := crm.garantir_pc(v_atual);
  select * into v_aj from crm.contato_ajuste where pessoa_id = v_pc;
  v_tem_aj := found;
  if not v_tem_aj then v_aj.pessoa_id := v_pc; end if;
  select pc.perfil, pc.atua_com_holding into v_pc_perfil, v_pc_holding from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;

  -- nome: obrigatório quando enviado (não dá para "apagar" o nome)
  if p_dados ? 'nome' then
    v_nome := nullif(btrim(coalesce(p_dados ->> 'nome', '')), '');
    if v_nome is null or length(v_nome) < 2 then return crm.res(false, 'Informe o nome.'); end if;
    if length(v_nome) > 160 then return crm.res(false, 'Nome longo demais (até 160 caracteres).'); end if;
    if v_nome is distinct from v_aj.nome and v_nome is distinct from crm.nome_pessoa(v_atual) then
      v_aj.nome := v_nome; v_campos := array_append(v_campos, 'nome'::text); v_mexe_aj := true;
    end if;
  end if;

  -- e-mail: vazio = volta ao da base; novo = valida, confere duplicidade, anexa à base central e marca como principal
  if p_dados ? 'email' then
    v_email := nullif(btrim(coalesce(p_dados ->> 'email', '')), '');
    if v_email is not null then
      v_email := pessoas.norm_email(v_email);
      if v_email is null then return crm.res(false, 'E-mail inválido.'); end if;
    end if;
    if v_email is distinct from v_aj.email then
      if v_email is not null then
        v_outros := array(select distinct pessoas.atual(x) from unnest(crm.contatos_candidatos(v_email)) x
                           where not (x = any(v_grupo)) and pessoas.atual(x) <> v_atual);
        if cardinality(v_outros) > 0 then
          return crm.res(false, 'Esse e-mail já é de outro contato. Abra a ficha dele ou peça ao gestor para unificar.',
                         jsonb_build_object('duplicado', 'email'));
        end if;
        perform pessoas.anexar(v_atual, 'email', v_email, v_email, 'crm');
      end if;
      v_aj.email := v_email; v_campos := array_append(v_campos, 'e-mail'::text); v_mexe_aj := true;
    end if;
  end if;

  -- telefone: mesma regra (chave de telefone da base central: pessoas.chave_telefone → controle.fone_key)
  if p_dados ? 'telefone' then
    v_tel := nullif(btrim(coalesce(p_dados ->> 'telefone', '')), '');
    if v_tel is not null then
      v_tel := pessoas.norm_telefone(v_tel);
      if v_tel is null then return crm.res(false, 'Telefone inválido: use DDD + número (celular com 9).'); end if;
    end if;
    if v_tel is distinct from v_aj.telefone then
      if v_tel is not null then
        v_outros := array(select distinct pessoas.atual(x) from unnest(crm.contatos_candidatos(v_tel)) x
                           where not (x = any(v_grupo)) and pessoas.atual(x) <> v_atual);
        if cardinality(v_outros) > 0 then
          return crm.res(false, 'Esse telefone já é de outro contato. Confira em "Possíveis duplicados" ou peça ao gestor para unificar.',
                         jsonb_build_object('duplicado', 'telefone'));
        end if;
        perform pessoas.anexar(v_atual, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'crm');
      end if;
      v_aj.telefone := v_tel; v_campos := array_append(v_campos, 'telefone'::text); v_mexe_aj := true;
    end if;
  end if;

  if p_dados ? 'cidade' then
    v_cidade := nullif(btrim(coalesce(p_dados ->> 'cidade', '')), '');
    if length(v_cidade) > 120 then return crm.res(false, 'Cidade longa demais (até 120 caracteres).'); end if;
    if v_cidade is distinct from v_aj.cidade then v_aj.cidade := v_cidade; v_campos := array_append(v_campos, 'cidade'::text); v_mexe_aj := true; end if;
  end if;
  if p_dados ? 'uf' then
    v_uf := upper(nullif(btrim(coalesce(p_dados ->> 'uf', '')), ''));
    if v_uf is not null and v_uf !~ '^[A-Z]{2}$' then return crm.res(false, 'UF inválida: use a sigla (ex.: SP).'); end if;
    if v_uf is distinct from v_aj.uf then v_aj.uf := v_uf; v_campos := array_append(v_campos, 'UF'::text); v_mexe_aj := true; end if;
  end if;
  if p_dados ? 'empresa' then
    v_empresa := nullif(btrim(coalesce(p_dados ->> 'empresa', '')), '');
    if length(v_empresa) > 160 then return crm.res(false, 'Empresa longa demais (até 160 caracteres).'); end if;
    if v_empresa is distinct from v_aj.empresa then v_aj.empresa := v_empresa; v_campos := array_append(v_campos, 'empresa'::text); v_mexe_aj := true; end if;
  end if;
  if p_dados ? 'observacao' then
    v_obs := nullif(btrim(coalesce(p_dados ->> 'observacao', '')), '');
    if length(v_obs) > 1000 then return crm.res(false, 'Observação longa demais (até 1.000 caracteres).'); end if;
    if v_obs is distinct from v_aj.observacao then v_aj.observacao := v_obs; v_campos := array_append(v_campos, 'observação'::text); v_mexe_aj := true; end if;
  end if;
  if p_dados ? 'perfil' then
    v_perfil := nullif(btrim(coalesce(p_dados ->> 'perfil', '')), '');
    if v_perfil is not null and v_perfil not in ('advogado', 'contador', 'outro') then return crm.res(false, 'Perfil inválido.'); end if;
    if v_perfil is distinct from v_pc_perfil then v_campos := array_append(v_campos, 'perfil'::text); v_mexe_pc := true; else v_perfil := v_pc_perfil; end if;
  else
    v_perfil := v_pc_perfil;
  end if;
  if p_dados ? 'atuaComHolding' then
    v_holding := nullif(btrim(coalesce(p_dados ->> 'atuaComHolding', '')), '');
    if v_holding is not null and v_holding not in ('sim', 'nao', 'comecando') then return crm.res(false, 'Holding inválido.'); end if;
    if v_holding is distinct from v_pc_holding then v_campos := array_append(v_campos, 'holding'::text); v_mexe_pc := true; else v_holding := v_pc_holding; end if;
  else
    v_holding := v_pc_holding;
  end if;

  if cardinality(v_campos) = 0 then
    return crm.res(true, 'Nada mudou.', jsonb_build_object('contatoId', v_atual, 'campos', '[]'::jsonb));
  end if;

  if v_mexe_aj then
    insert into crm.contato_ajuste as x (pessoa_id, nome, email, telefone, cidade, uf, empresa, observacao, atualizado_por)
    values (v_pc, v_aj.nome, v_aj.email, v_aj.telefone, v_aj.cidade, v_aj.uf, v_aj.empresa, v_aj.observacao, v_eu)
    on conflict (pessoa_id) do update
       set nome = excluded.nome, email = excluded.email, telefone = excluded.telefone, cidade = excluded.cidade,
           uf = excluded.uf, empresa = excluded.empresa, observacao = excluded.observacao,
           atualizado_por = excluded.atualizado_por, atualizado_em = now();
  end if;

  -- Registro: só QUAIS campos (nunca o valor). Com perfil/holding, o próprio crm.tg_log de pessoa_comercial grava a linha
  -- (com este resumo); sem eles, grava pela crm.log_registrar. Uma linha por edição.
  if v_mexe_pc then
    perform set_config('crm.resumo', 'Editou ' || array_to_string(v_campos, ', '), true);
    update crm.pessoa_comercial x set perfil = v_perfil, atua_com_holding = v_holding, atualizado_em = now()
     where x.pessoa_id = v_pc;
    perform set_config('crm.resumo', '', true);
  else
    perform crm.log_registrar('editou', 'contato', v_pc::text, v_pc, 'Editou ' || array_to_string(v_campos, ', '),
                              jsonb_build_object('campos', to_jsonb(v_campos)));
  end if;

  -- Aviso em tempo real para as telas abertas (Conversas, funil, base): payload sem dado pessoal; quem ouve recarrega
  -- pelas RPCs de sempre. Falha do Realtime não desfaz a edição.
  begin
    perform realtime.send(jsonb_build_object('t', 'contato'), 'mudou', 'crm:caixa', true);
  exception when others then
    raise warning 'crm_editar_contato: aviso realtime falhou: %', sqlerrm;
  end;

  return crm.res(true, 'Contato atualizado.', jsonb_build_object('contatoId', v_atual, 'campos', to_jsonb(v_campos)));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or numeric_value_out_of_range or string_data_right_truncation
             or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;
revoke execute on function public.crm_editar_contato(uuid, jsonb) from public, anon;
grant execute on function public.crm_editar_contato(uuid, jsonb) to authenticated, service_role;
