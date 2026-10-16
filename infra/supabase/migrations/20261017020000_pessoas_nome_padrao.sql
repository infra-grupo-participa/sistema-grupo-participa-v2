-- 20261017020000: pessoa única, nome padrão não é nome (pessoas.nome_padrao) e par já decidido não reabre revisão
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-nome-padrao), ensaio escrito mas NÃO rodado, aguardando ok de um dos donos do banco.
--   Ensaio: 20261017020000_ensaio.sql (begin ... rollback). Reversão: 20261017020000_reversao.sql.
--   Detalhe, números lidos com data e hora, roteiro e riscos: 20261017020000.explain.md e docs/pessoa-unica/README.md (seção "Nome padrão").
--
-- POR QUE:
--   (1) "GUARDIAO DO LEGADO" está em 2.508 pessoas (vindas do ActiveCampaign) e não é nome de pessoa. Como tem mais de uma palavra, o
--       pessoas.candidatos_nome acha todas elas como homônimas e o pessoas.resolver abre revisão so_nome para cada lead novo com esse nome.
--   (2) O resolver, a casar_email e o anexar abriam de novo uma revisão para um par que já tem revisão decidida como 'diferente'
--       (ou que já está aberta com o mesmo motivo), porque nenhum dos três olhava pessoas.revisao antes de inserir.
-- O QUE CRIA (os dados só mudam quando alguém roda a limpeza; a migration em si não toca em nenhuma pessoa):
--   1. pessoas.nome_padrao: lista dos nomes que não são nome de pessoa (chave = pessoas.norm_nome). RLS ligada, sem permissão para ninguém.
--      Semente: GUARDIAO DO LEGADO. Para incluir outro: insert na tabela (a chave precisa ser o resultado de pessoas.norm_nome).
--   2. pessoas.nome_limpo(text): ponto único. Devolve NULL se o nome está na lista, senão o próprio nome.
--   3. pessoas.revisao_par_ja_tem(a, b, motivo): 'diferente' se o par (a, b) já tem revisão decidida como diferente, 'pendente' se já tem
--      revisão aberta com o mesmo motivo, senão NULL. Segue pessoas.atual e pessoas.grupo dos dois lados.
--   4. create or replace de pessoas.resolver, pessoas.casar_email, pessoas.registrar e pessoas.anexar, a partir do corpo vigente no banco
--      (guarda de md5 abaixo): o nome passa por nome_limpo na entrada; candidato com par já tem revisão sai da lista; lista vazia não abre revisão.
--      A lógica de casamento por e-mail, telefone e CPF não muda.
--   5. arquivo.pessoas_nome_padrao_item (cópia do nome antes de limpar), pessoas.nome_padrao_passo, pessoas.nome_padrao_limpar (PROCEDURE com
--      COMMIT por passo, teto, orçamento de segundos e chave pessoas.carga_chave 'nome_padrao_limpeza', que nasce DESLIGADA) e
--      pessoas.nome_padrao_reverter. Nada é executado aqui: a limpeza das 2.508 é um CALL manual, depois do ok.
-- NÃO MUDA: o status de nenhuma revisão pendente; as cópias do nome em pessoas.ac_contato, public.compradores e crm.negocio (ver .explain.md).
-- COMO VOLTAR: 20261017020000_reversao.sql (devolve os nomes pela cópia, restaura os 4 corpos antigos, remove o que criou; a tabela de cópia fica).
-- AS 5 PERGUNTAS: escala = 1 linha em nome_padrao; limpeza de 2.508 pessoas em passos de 500; revisao_par_ja_tem roda uma vez por candidato
--   (até 20) só quando o resolver já achou candidato; índice = pessoas_nome_norm_idx (já existe) para achar os nomes, revisao_pessoa_idx para o par,
--   PK de nome_padrao; nenhum índice novo; frequência = limpeza uma vez (CALL manual), guarda a cada entrada de lead; repetição = o passo só pega quem
--   ainda tem nome padrão e a cópia tem índice único por pessoa ativa; reversão = nome_padrao_reverter + reversão.sql.
-- DADO PESSOAL: a cópia guarda o nome padrão (texto de página, não é nome de pessoa), o id da pessoa e a data. Nenhum e-mail, telefone ou documento.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- guarda: só roda sobre o estado lido em 16/10/2026. Se algum corpo mudou desde então, a migration para e precisa ser refeita a partir do corpo vigente.
do $g$
declare r record;
begin
  if to_regclass('pessoas.nome_padrao') is not null or to_regprocedure('pessoas.nome_limpo(text)') is not null then
    raise exception '20261017020000: já aplicada.';
  end if;
  if to_regprocedure('pessoas.norm_nome(text)') is null or to_regprocedure('pessoas.atual(uuid)') is null or to_regprocedure('pessoas.grupo(uuid)') is null
     or to_regclass('pessoas.revisao') is null or to_regclass('pessoas.carga_chave') is null or to_regnamespace('arquivo') is null then
    raise exception '20261017020000: falta pessoas.norm_nome, pessoas.atual, pessoas.grupo, pessoas.revisao, pessoas.carga_chave ou o schema arquivo.';
  end if;
  for r in
    select v.f, v.esperado, md5(p.prosrc) atual
      from (values ('pessoas.resolver(text,text,text,text,boolean,uuid)', '40eaf91a3fbe23dda1dfd4585af79137'),
                   ('pessoas.casar_email(text,text,text,text)',           'fa42d0800e42ed4d025efaa93364beaa'),
                   ('pessoas.registrar(jsonb,text,uuid)',                 '8f77b9fc25b84d526be4c9ebad528c2e'),
                   ('pessoas.anexar(uuid,text,text,text,text)',           '4f6baa53f1e540b3334c64ba9a552100')) v(f, esperado)
      join pg_proc p on p.oid = to_regprocedure(v.f)
  loop
    if r.atual <> r.esperado then
      raise exception '20261017020000: % mudou depois da leitura de 16/10/2026 (md5 % em vez de %). Refazer o create or replace a partir do corpo vigente.', r.f, r.atual, r.esperado;
    end if;
  end loop;
  if (select count(*) from pg_proc where oid in (to_regprocedure('pessoas.resolver(text,text,text,text,boolean,uuid)'), to_regprocedure('pessoas.casar_email(text,text,text,text)'),
                                                 to_regprocedure('pessoas.registrar(jsonb,text,uuid)'), to_regprocedure('pessoas.anexar(uuid,text,text,text,text)'))) <> 4 then
    raise exception '20261017020000: falta uma das funções pessoas.resolver, casar_email, registrar ou anexar.';
  end if;
end
$g$;

-- ===================== 1. a lista =====================
create table pessoas.nome_padrao (
  chave     text primary key check (chave = pessoas.norm_nome(chave)),   -- sempre o resultado de pessoas.norm_nome
  motivo    text not null,
  criado_em timestamptz not null default now(),
  por       text not null
);
alter table pessoas.nome_padrao enable row level security;
revoke all on pessoas.nome_padrao from public, anon, authenticated, service_role;
insert into pessoas.nome_padrao (chave, motivo, por)
values ('GUARDIAO DO LEGADO', 'nome padrão que veio do ActiveCampaign em 2.508 pessoas; não é nome de pessoa (decisão do Victor, 16/10/2026)', 'migration 20261017020000');

-- ===================== 2. o ponto único =====================
-- Toda entrada de nome passa por aqui. NULL entra, NULL sai. Nome da lista vira NULL. Outro nome sai igual.
create function pessoas.nome_limpo(p_nome text) returns text
language sql stable set search_path to '' as $f$
  select case when exists (select 1 from pessoas.nome_padrao n where n.chave = pessoas.norm_nome(p_nome)) then null else p_nome end;
$f$;

-- ===================== 3. o par já tem revisão? =====================
-- 'diferente': alguém já decidiu que são pessoas diferentes (qualquer motivo, qualquer lado). 'pendente': já existe revisão aberta COM O MESMO motivo.
-- Revisão aberta com outro motivo não conta: um sinal novo e diferente continua chegando ao humano. 'mesma' não precisa de teste: a mescla já faz atual() igual.
-- p_motivo nulo = só olha o que está decidido.
create function pessoas.revisao_par_ja_tem(p_a uuid, p_b uuid, p_motivo text default null) returns text
language sql stable set search_path to '' as $f$
  with g as (select pessoas.grupo(pessoas.atual(p_a)) ga, pessoas.grupo(pessoas.atual(p_b)) gb)
  select case when bool_or(x.status = 'diferente') then 'diferente' when bool_or(x.status = 'pendente') then 'pendente' end
    from g
   cross join lateral (
     select r.status from pessoas.revisao r
      where r.pessoa_id = any(g.ga) and r.candidatos && g.gb
        and (r.status = 'diferente' or (r.status = 'pendente' and r.motivo = p_motivo))
     union all
     select r.status from pessoas.revisao r
      where r.pessoa_id = any(g.gb) and r.candidatos && g.ga
        and (r.status = 'diferente' or (r.status = 'pendente' and r.motivo = p_motivo))) x;
$f$;

-- ===================== 4. as quatro funções que gravam nome ou abrem revisão =====================
-- Cada corpo é o vigente no banco em 16/10/2026 (pg_get_functiondef) mais as linhas marcadas com 20261017020000.

CREATE OR REPLACE FUNCTION pessoas.resolver(p_nome text, p_email text, p_telefone text, p_cep text, p_teste boolean DEFAULT false, p_por uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_email text := pessoas.norm_email(p_email);
  v_fk    text := pessoas.chave_telefone(p_telefone);
  v_pessoa uuid; v_como text; v_motivo text; v_nova boolean := false;
  v_cands uuid[] := '{}';
  v_lead uuid; v_aluno uuid; v_comprador uuid; v_pa uuid; v_pc uuid; v_x uuid;
  v_ents text[] := '{}'; v_compat text[] := '{}';
  r record;
begin
  -- 20261017020000: nome padrão das páginas (pessoas.nome_padrao) é nome vazio: nunca casa, nunca vira revisão so_nome/nome_cep, nunca é gravado
  p_nome := pessoas.nome_limpo(p_nome);
  -- concorrência: o mesmo lead chegando 2× ao mesmo tempo não vira 2 pessoas
  perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || coalesce(v_email, v_fk, pessoas.norm_nome(p_nome), '')));

  -- 1. E-MAIL (cada fonte pelo seu índice; valor normalizado na variável)
  if v_email is not null then
    select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
    select a.id into v_aluno from public.thb_alunos a
     where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
    select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;

    v_pa := (select pessoas.atual(p.id) from pessoas.pessoas p where v_aluno is not null and p.aluno_id = v_aluno);
    v_pc := (select pessoas.atual(p.id) from pessoas.pessoas p where v_comprador is not null and p.comprador_id = v_comprador);
    v_pessoa := coalesce(v_pa, v_pc, v_lead);
    v_cands := array(select distinct x from unnest(array[v_pa, v_pc, v_lead]) x where x is not null and x <> v_pessoa);
    if cardinality(v_cands) > 0 then v_motivo := 'email_conflito'; end if;   -- duplicata antiga: humano decide

    if v_pessoa is null then
      if v_aluno is not null then v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
      elsif v_comprador is not null then v_pessoa := pessoas.pessoa_do_comprador(v_comprador); end if;
    end if;

    if v_pessoa is not null and v_motivo is null then
      -- o lead que virou aluno/comprador: liga a referência que ainda não tem pessoa
      if v_aluno is not null and v_pa is null then
        select p.aluno_id into v_x from pessoas.pessoas p
         where p.id = any(pessoas.grupo(v_pessoa)) and p.aluno_id is not null limit 1;
        if v_x is null then
          update pessoas.pessoas set aluno_id = v_aluno, atualizado_em = now() where id = v_pessoa;
          insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.thb_alunos', v_aluno::text);
        elsif v_x <> v_aluno then
          v_cands := v_cands || pessoas.pessoa_do_aluno(v_aluno); v_motivo := 'email_conflito';
        end if;
      end if;
      if v_comprador is not null and v_pc is null and v_motivo is null then
        v_x := null;
        select p.comprador_id into v_x from pessoas.pessoas p
         where p.id = any(pessoas.grupo(v_pessoa)) and p.comprador_id is not null limit 1;
        if v_x is null then
          update pessoas.pessoas set comprador_id = v_comprador, atualizado_em = now() where id = v_pessoa;
          insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.compradores', v_comprador::text);
        elsif v_x <> v_comprador then
          v_cands := v_cands || pessoas.pessoa_do_comprador(v_comprador); v_motivo := 'email_conflito';
        end if;
      end if;
    end if;
    if v_pessoa is not null then v_como := 'email'; end if;
  end if;

  -- 2. TELEFONE: só sem e-mail, só com exatamente 1 candidato e nome compatível
  if v_pessoa is null and v_email is null and v_fk is not null then
    for r in select * from pessoas.candidatos_telefone(v_fk) loop
      v_ents := v_ents || r.ent;
      if pessoas.nomes_compativeis(p_nome, r.nome_ent) then v_compat := v_compat || r.ent; end if;
    end loop;
    if cardinality(v_ents) = 1 and cardinality(v_compat) = 1 then
      v_pessoa := (pessoas.garantir(v_compat))[1];
      v_como := 'telefone';
    elsif cardinality(v_ents) > 0 then
      v_cands := pessoas.garantir(v_ents);
      v_motivo := case when cardinality(v_compat) = 0 then 'telefone_nome_diferente' else 'telefone_varios' end;
    end if;
  end if;

  -- 3. Ninguém casou: pessoa nova. Telefone de outra pessoa (com e-mail diferente) ou nome igual → revisão.
  if v_pessoa is null then
    if v_motivo is null and v_email is not null and v_fk is not null then
      select coalesce(array_agg(t.ent), '{}') into v_ents from pessoas.candidatos_telefone(v_fk) t;
      if cardinality(v_ents) > 0 then
        v_cands := pessoas.garantir(v_ents);
        v_motivo := 'telefone_email_diferente';
      end if;
    end if;
    if v_motivo is null then
      select coalesce(array_agg(t.ent), '{}'), min(t.motivo) into v_ents, v_motivo from pessoas.candidatos_nome(p_nome, p_cep) t;
      if cardinality(v_ents) > 0 then v_cands := pessoas.garantir(v_ents); else v_motivo := null; end if;
    end if;
    v_cands := array(select distinct s from unnest(v_cands) s where s is not null);
    insert into pessoas.pessoas (nome, situacao, teste, criado_por)
    values (case when length(btrim(coalesce(p_nome, ''))) >= 2 then left(btrim(p_nome), 160) end,
            case when cardinality(v_cands) > 0 then 'revisar' else 'ativa' end, coalesce(p_teste, false), p_por)
    returning id into v_pessoa;
    v_como := 'nova'; v_nova := true;
  end if;

  v_pessoa := pessoas.atual(v_pessoa);
  v_cands := array(select distinct s from unnest(v_cands) s where s is not null and pessoas.atual(s) <> v_pessoa);
  -- 20261017020000: par que já tem revisão decidida como 'diferente' (ou já aberta com o mesmo motivo) não abre outra. Pessoa nova nunca tem par.
  if not v_nova and cardinality(v_cands) > 0 then
    v_cands := array(select s from unnest(v_cands) s where pessoas.revisao_par_ja_tem(v_pessoa, s, v_motivo) is null);
  end if;
  if cardinality(v_cands) > 0 then
    insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
    values (v_pessoa, v_motivo, v_cands, jsonb_build_object('casou_por', v_como));
  else
    v_motivo := null;
  end if;
  return jsonb_build_object('pessoa_id', v_pessoa, 'como', v_como, 'nova', v_nova, 'revisao', v_motivo);
end
$function$;

CREATE OR REPLACE FUNCTION pessoas.casar_email(p_nome text, p_email text, p_telefone text, p_origem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_email text := pessoas.norm_email(p_email);
  v_tel   text := pessoas.norm_telefone(p_telefone);
  v_nome  text := pessoas.nome_limpo(nullif(left(btrim(coalesce(p_nome, '')), 160), ''));   -- 20261017020000: nome padrão = vazio
  v_lead uuid; v_aluno uuid; v_comprador uuid; v_pa uuid; v_pc uuid; v_pessoa uuid; v_x uuid;
  v_cands uuid[] := '{}'; v_nova boolean := false; v_motivo text;
begin
  if v_email is null then return jsonb_build_object('pessoa_id', null, 'nova', false, 'motivo', 'sem_email'); end if;
  perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || v_email));   -- mesma chave do pessoas.resolver

  select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
  select a.id into v_aluno from public.thb_alunos a where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
  select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;
  v_pa := (select pessoas.atual(p.id) from pessoas.pessoas p where v_aluno is not null and p.aluno_id = v_aluno);
  v_pc := (select pessoas.atual(p.id) from pessoas.pessoas p where v_comprador is not null and p.comprador_id = v_comprador);
  v_pessoa := coalesce(v_pa, v_pc, v_lead);
  v_cands := array(select distinct x from unnest(array[v_pa, v_pc, v_lead]) x where x is not null and x <> v_pessoa);
  if cardinality(v_cands) > 0 then v_motivo := 'email_conflito'; end if;

  if v_pessoa is null then
    if v_aluno is not null then v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
    elsif v_comprador is not null then v_pessoa := pessoas.pessoa_do_comprador(v_comprador); end if;
  end if;

  -- o lead que virou aluno/comprador: liga a referência que ainda não tem pessoa (igual ao pessoas.resolver)
  if v_pessoa is not null and v_motivo is null then
    if v_aluno is not null and v_pa is null then
      select p.aluno_id into v_x from pessoas.pessoas p where p.id = any(pessoas.grupo(v_pessoa)) and p.aluno_id is not null limit 1;
      if v_x is null then
        update pessoas.pessoas set aluno_id = v_aluno, atualizado_em = now() where id = v_pessoa;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.thb_alunos', v_aluno::text);
      elsif v_x <> v_aluno then
        v_cands := v_cands || pessoas.pessoa_do_aluno(v_aluno); v_motivo := 'email_conflito';
      end if;
    end if;
    if v_comprador is not null and v_pc is null and v_motivo is null then
      v_x := null;
      select p.comprador_id into v_x from pessoas.pessoas p where p.id = any(pessoas.grupo(v_pessoa)) and p.comprador_id is not null limit 1;
      if v_x is null then
        update pessoas.pessoas set comprador_id = v_comprador, atualizado_em = now() where id = v_pessoa;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.compradores', v_comprador::text);
      elsif v_x <> v_comprador then
        v_cands := v_cands || pessoas.pessoa_do_comprador(v_comprador); v_motivo := 'email_conflito';
      end if;
    end if;
  end if;

  if v_pessoa is null then
    insert into pessoas.pessoas (nome) values (case when length(coalesce(v_nome, '')) >= 2 then v_nome end) returning id into v_pessoa;
    v_nova := true;
  else
    update pessoas.pessoas set nome = v_nome, atualizado_em = now()
     where id = v_pessoa and nome is null and aluno_id is null and comprador_id is null and length(coalesce(v_nome, '')) >= 2;
  end if;

  v_pessoa := pessoas.atual(v_pessoa);
  v_cands := array(select distinct s from unnest(v_cands) s where s is not null and pessoas.atual(s) <> v_pessoa);
  -- 20261017020000: par que já tem revisão decidida como 'diferente' (ou já aberta com o mesmo motivo) não abre outra. Pessoa nova nunca tem par.
  if not v_nova and cardinality(v_cands) > 0 then
    v_cands := array(select s from unnest(v_cands) s where pessoas.revisao_par_ja_tem(v_pessoa, s, 'email_conflito') is null);
  end if;
  if cardinality(v_cands) > 0 then
    insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
    values (v_pessoa, 'email_conflito', v_cands, jsonb_build_object('casou_por', 'email', 'carga', p_origem));
  else
    v_motivo := null;
  end if;

  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, p_origem);
  perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), p_origem);
  return jsonb_build_object('pessoa_id', v_pessoa, 'nova', v_nova, 'motivo', v_motivo);
end $function$;

CREATE OR REPLACE FUNCTION pessoas.registrar(p jsonb, p_fonte text, p_por uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_tel text := pessoas.norm_telefone(p->>'telefone');
  v_email text := pessoas.norm_email(p->>'email');
  v_nome text := pessoas.nome_limpo(nullif(left(btrim(coalesce(p->>'nome', '')), 160), ''));   -- 20261017020000: nome padrão = vazio
  v_res jsonb; v_pessoa uuid;
  v_projeto bigint; v_pagina bigint; v_campanha text; v_trad jsonb; v_origem bigint; v_evento text;
  v_ref text; v_aluno uuid; v_tem_origem boolean;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.'); end if;
  v_evento := coalesce(nullif(p->>'evento', ''), case when p_fonte = 'formulario' then 'lead' else 'cadastro' end);
  if v_evento not in ('lead', 'mql', 'nao_mql', 'cadastro', 'pre_checkout') then
    return jsonb_build_object('ok', false, 'msg', 'Evento inválido (lead, mql, nao_mql, cadastro ou pre_checkout).');
  end if;

  if nullif(p->>'aluno_id', '') is not null then
    begin v_aluno := (p->>'aluno_id')::uuid; exception when others then return jsonb_build_object('ok', false, 'msg', 'Aluno inválido.'); end;
    v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
    if v_pessoa is null then return jsonb_build_object('ok', false, 'msg', 'Aluno não encontrado.'); end if;
    v_res := jsonb_build_object('pessoa_id', v_pessoa, 'como', 'aluno', 'nova', false, 'revisao', null);
  else
    if v_tel is null and v_email is null then
      return jsonb_build_object('ok', false, 'msg', 'Informe um e-mail ou um telefone (com DDD) válido.');
    end if;
    v_res := pessoas.resolver(v_nome, v_email, v_tel, p->>'cep', coalesce((p->>'teste')::boolean, false), p_por);
    v_pessoa := (v_res->>'pessoa_id')::uuid;

    update pessoas.pessoas set nome = v_nome, atualizado_em = now()
     where id = v_pessoa and nome is null and aluno_id is null and comprador_id is null and length(coalesce(v_nome, '')) >= 2;

    perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, p_fonte);
    perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), p_fonte);
    perform pessoas.anexar(v_pessoa, 'nome_cep', pessoas.chave_nome_cep(v_nome, p->>'cep'), pessoas.chave_nome_cep(v_nome, p->>'cep'), p_fonte);
  end if;

  -- origem: projeto pela sigla, ou pelo nome de campanha (GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA)
  v_campanha := nullif(left(btrim(coalesce(p->>'campanha', '')), 300), '');
  if v_campanha is not null then v_trad := mkt.campanha_traduzir(v_campanha); end if;
  select id into v_projeto from mkt.projetos where sigla = upper(btrim(coalesce(p->>'projeto', '')));
  v_projeto := coalesce(v_projeto, (v_trad->>'projeto_id')::bigint);
  if nullif(p->>'pagina_id', '') is not null then
    select id into v_pagina from mkt.paginas where id = (p->>'pagina_id')::bigint and (v_projeto is null or projeto_id = v_projeto);
  elsif nullif(p->>'caminho', '') is not null and v_projeto is not null then
    select id into v_pagina from mkt.paginas
     where projeto_id = v_projeto and dominio = regexp_replace(lower(coalesce(p->>'dominio', '')), '^www\.', '')
       and caminho = p->>'caminho';
  end if;
  v_pagina := coalesce(v_pagina, (v_trad->>'pagina_id')::bigint);
  if v_pagina is not null and v_projeto is null then select projeto_id into v_projeto from mkt.paginas where id = v_pagina; end if;

  v_tem_origem := v_projeto is not null or v_campanha is not null
                  or coalesce(p->>'utm_source', p->>'utm_medium', p->>'utm_campaign', p->>'utm_content', p->>'utm_term') is not null;
  if v_tem_origem then
    insert into pessoas.origens (pessoa_id, projeto_id, pagina_id, campanha, campanha_padrao, utm_source, utm_medium,
                                 utm_campaign, utm_content, utm_term, de_anuncio, fonte)
    values (v_pessoa, v_projeto, v_pagina, v_campanha, (v_trad->>'padrao')::boolean,
            nullif(left(p->>'utm_source', 300), ''), nullif(left(p->>'utm_medium', 300), ''),
            nullif(left(p->>'utm_campaign', 300), ''), nullif(left(p->>'utm_content', 300), ''),
            nullif(left(p->>'utm_term', 300), ''),
            coalesce(nullif(p->>'fbclid', ''), nullif(p->>'gclid', '')) is not null, p_fonte)
    returning id into v_origem;
  end if;

  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, origem_id, fonte, detalhe, por)
  values (v_pessoa, v_evento, v_projeto, v_origem, p_fonte,
          jsonb_build_object('como', v_res->>'como') || case when v_res->>'revisao' is not null
                                                              then jsonb_build_object('revisao', v_res->>'revisao') else '{}' end
          -- 20261007i: rastro da captura (chave do evento, sck, xcod, página sem query). Nunca dado pessoal.
          || jsonb_strip_nulls(jsonb_build_object(
               'chave_evento', case when p->>'chave_evento' ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(p->>'chave_evento') <= 80
                                    then p->>'chave_evento' end,
               'sck', nullif(left(btrim(coalesce(p->>'sck', '')), 200), ''),
               'xcod', nullif(left(btrim(coalesce(p->>'xcod', '')), 200), ''),
               'pagina', nullif(left(btrim(split_part(split_part(coalesce(p->>'pagina', ''), '?', 1), '#', 1)), 300), ''))),
          p_por);

  select ref into v_ref from pessoas.pessoas where id = v_pessoa;

  -- a Web guarda só a referência opaca (se a coleta da Web, 20261005n, estiver aplicada)
  if nullif(p->>'visitante', '') is not null and v_projeto is not null and to_regclass('mkt_web.visitantes') is not null
     and p->>'visitante' ~ '^[A-Za-z0-9]{8,40}$' then
    execute 'update mkt_web.visitantes set lead_ref = $1 where projeto_id = $2 and id = $3 and lead_ref is null'
      using v_ref, v_projeto, p->>'visitante';
  end if;

  return jsonb_build_object('ok', true, 'pessoa_id', v_pessoa, 'ref', v_ref, 'como', v_res->>'como',
                            'nova', coalesce((v_res->>'nova')::boolean, false), 'revisao', v_res->>'revisao',
                            'situacao', (select situacao from pessoas.pessoas where id = v_pessoa),
                            'projeto_id', v_projeto, 'origem_id', v_origem);
end
$function$;

CREATE OR REPLACE FUNCTION pessoas.anexar(p_pessoa uuid, p_tipo text, p_valor text, p_chave text, p_origem text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_dono uuid; r record;
begin
  if p_chave is null then return; end if;
  select a.email a_email, controle.fone_key(coalesce(a.telefone_e164, a.telefone)) a_fk, a.nome a_nome, a.cep a_cep,
         c.email::text c_email, controle.fone_key((c.telefone)::text) c_fk
    into r
    from pessoas.pessoas p
    left join public.thb_alunos a on a.id = p.aluno_id
    left join public.compradores c on c.id = p.comprador_id
   where p.id = p_pessoa;
  if (p_tipo = 'email' and p_chave in (lower(btrim(r.a_email)), lower(btrim(r.c_email))))
     or (p_tipo = 'telefone' and p_chave in (r.a_fk, r.c_fk))
     or (p_tipo = 'nome_cep' and pessoas.chave_nome_cep(r.a_nome, r.a_cep) = p_chave) then
    return;   -- referência basta
  end if;
  if p_tipo = 'email' then
    select pessoa_id into v_dono from pessoas.identificadores where tipo = 'email' and chave = p_chave;
    if found then
      if pessoas.atual(v_dono) <> pessoas.atual(p_pessoa)
         and not exists (select 1 from pessoas.revisao where status = 'pendente' and pessoa_id = p_pessoa and v_dono = any(candidatos))
         and pessoas.revisao_par_ja_tem(p_pessoa, v_dono, 'email_conflito') is null then   -- 20261017020000: par já decidido 'diferente' (ou já aberto, por qualquer lado) não reabre
        insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
        values (p_pessoa, 'email_conflito', array[v_dono], jsonb_build_object('casou_por', 'anexar'));
      end if;
      return;
    end if;
  end if;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem)
  values (p_pessoa, p_tipo, p_valor, p_chave, p_origem)
  on conflict do nothing;
end
$function$;

-- ===================== 5. a limpeza das pessoas que já têm o nome padrão =====================
-- Cópia antes de tocar (reversível). Só a coluna nome e atualizado_em de pessoas.pessoas muda; nenhuma revisão, mescla ou vínculo é tocado.
create table if not exists arquivo.pessoas_nome_padrao_item (
  id                  bigint generated always as identity primary key,
  criado_em           timestamptz not null default now(),
  pessoa_id           uuid not null,
  chave               text not null,          -- a chave de pessoas.nome_padrao que casou
  nome_antes          text not null,          -- o texto exato que estava em pessoas.pessoas.nome
  atualizado_em_antes timestamptz not null,
  revertido_em        timestamptz
);
alter table arquivo.pessoas_nome_padrao_item enable row level security;
create unique index if not exists pessoas_nome_padrao_item_ativa on arquivo.pessoas_nome_padrao_item (pessoa_id) where revertido_em is null;
revoke all on arquivo.pessoas_nome_padrao_item from public, anon, authenticated, service_role;

-- chave de desligar: nasce DESLIGADA. Ligar: update pessoas.carga_chave set ligada = true, ate = current_date + 1, por = 'victor' where fonte = 'nome_padrao_limpeza';
insert into pessoas.carga_chave (fonte, ligada, ate, por)
select 'nome_padrao_limpeza', false, null, 'migration 20261017020000'
 where not exists (select 1 from pessoas.carga_chave where fonte = 'nome_padrao_limpeza');

-- Um passo: até p_limite pessoas, cópia e UPDATE no mesmo comando (ou as duas coisas acontecem, ou nenhuma). Devolve quantas limpou.
-- O índice pessoas_nome_norm_idx (norm_nome(nome) onde nome não é nulo) acha as linhas; "= any(array)" e o "nome is not null" são o que o fazem entrar no índice.
create function pessoas.nome_padrao_passo(p_limite integer) returns integer
language plpgsql set search_path to '' as $f$
declare v_chaves text[]; v_n integer;
begin
  if p_limite is null or p_limite not between 1 and 2000 then raise exception 'nome_padrao_passo: p_limite entre 1 e 2.000' using errcode = '22023'; end if;
  select array_agg(chave) into v_chaves from pessoas.nome_padrao;
  if v_chaves is null then return 0; end if;
  with alvo as (
    select p.id, p.nome, p.atualizado_em
      from pessoas.pessoas p
     where p.nome is not null and pessoas.norm_nome(p.nome) = any(v_chaves)
     limit p_limite
       for update of p),
  cop as (
    insert into arquivo.pessoas_nome_padrao_item (pessoa_id, chave, nome_antes, atualizado_em_antes)
    select a.id, pessoas.norm_nome(a.nome), a.nome, a.atualizado_em from alvo a
    returning pessoa_id),
  upd as (
    update pessoas.pessoas p set nome = null, atualizado_em = now()
      from cop where p.id = cop.pessoa_id
    returning 1)
  select count(*) into v_n from upd;
  return v_n;
end
$f$;

-- A rodada: CALL pessoas.nome_padrao_limpar();  Sem cláusula SET (ela proibiria o COMMIT). COMMIT a cada passo. Falha fechada pela chave.
create procedure pessoas.nome_padrao_limpar(p_passo integer default 500, p_max integer default 5000, p_orcamento_s integer default 40)
language plpgsql as $p$
declare
  v_sp text := current_setting('search_path'); v_t0 timestamptz := clock_timestamp();
  v_tot integer := 0; v_n integer; v_fim text := 'nada mais a limpar';
begin
  if p_passo is null or p_passo not between 1 and 1000 or p_max is null or p_max not between 1 and 20000
     or p_orcamento_s is null or p_orcamento_s not between 5 and 90 then
    raise exception 'nome_padrao_limpar: parâmetros inválidos' using errcode = '22023';
  end if;
  if not coalesce((select ligada and ate is not null and current_date <= ate from pessoas.carga_chave where fonte = 'nome_padrao_limpeza'), false) then
    raise exception 'nome_padrao_limpar: chave desligada (ou sem data de fim). Ver o cabeçalho da migration.' using errcode = '55000';
  end if;
  perform set_config('search_path', '', false);
  loop
    if clock_timestamp() - v_t0 > make_interval(secs => p_orcamento_s) then v_fim := 'orçamento de segundos'; exit; end if;
    if v_tot >= p_max then v_fim := 'teto de pessoas'; exit; end if;
    v_n := pessoas.nome_padrao_passo(least(p_passo, p_max - v_tot));
    exit when v_n = 0;
    v_tot := v_tot + v_n;
    commit;
  end loop;
  commit;
  perform set_config('search_path', v_sp, false);
  raise notice 'nome_padrao_limpar: % pessoas limpas; parou por: %', v_tot, v_fim;
end
$p$;

-- Devolve o nome e o atualizado_em copiados. Só mexe em quem ainda está sem nome: se alguém já pôs outro nome na pessoa, pula e conta.
create function pessoas.nome_padrao_reverter(p_max integer default 5000) returns jsonb
language plpgsql set search_path to '' as $f$
declare i record; v_n integer; v_ok integer := 0; v_pul integer := 0;
begin
  if p_max is null or p_max not between 1 and 5000 then raise exception 'p_max entre 1 e 5.000' using errcode = '22023'; end if;
  for i in select * from arquivo.pessoas_nome_padrao_item where revertido_em is null order by id limit p_max loop
    update pessoas.pessoas p set nome = i.nome_antes, atualizado_em = i.atualizado_em_antes where p.id = i.pessoa_id and p.nome is null;
    get diagnostics v_n = row_count;
    if v_n = 1 then
      update arquivo.pessoas_nome_padrao_item set revertido_em = now() where id = i.id;
      v_ok := v_ok + 1;
    else
      v_pul := v_pul + 1;
    end if;
  end loop;
  return jsonb_build_object('revertidos', v_ok, 'pulados', v_pul,
                            'restam', (select count(*) from arquivo.pessoas_nome_padrao_item where revertido_em is null));
end
$f$;

-- ===================== 6. permissões =====================
-- As quatro funções de cima já eram só do postgres (ACL preservada pelo create or replace). As novas nascem fechadas.
revoke all on function pessoas.nome_limpo(text) from public, anon, authenticated, service_role;
revoke all on function pessoas.revisao_par_ja_tem(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function pessoas.nome_padrao_passo(integer) from public, anon, authenticated, service_role;
revoke all on function pessoas.nome_padrao_reverter(integer) from public, anon, authenticated, service_role;
revoke all on procedure pessoas.nome_padrao_limpar(integer, integer, integer) from public, anon, authenticated, service_role;
