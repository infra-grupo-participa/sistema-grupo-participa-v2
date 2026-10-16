-- Ensaio de 20261017020000 numa transação DESFEITA (rollback). Sem dado pessoal: pessoas fictícias "Zzensaio" e e-mail .invalid.
-- Rodar: executor que só aceita arquivo terminado em rollback (aplica_sql.py ensaio) neste arquivo. NÃO foi rodado até a escrita (ver 20261017020000.explain.md).
-- O que ele prova: a migration cria tudo e fecha as permissões; o nome padrão vira NULL no resolver, na registrar e na casar_email; o resolver não abre so_nome
--   para nome padrão (e abre para nome comum, como controle); par já decidido 'diferente' não reabre no anexar, no resolver nem na casar_email;
--   a limpeza das pessoas reais com contagem antes e depois e explain analyze do 1º lote; o reverter devolve o estado exato (hash); a reversão completa
--   devolve os 4 corpos de 16/10/2026 e remove o que foi criado. Cada linha de saída diz o esperado no próprio texto.
-- O que ele NÃO prova: o COMMIT por passo da procedure nome_padrao_limpar (COMMIT não existe dentro de transação explícita): só os erros de guarda.
--   A procedure é provada na aplicação, com p_max pequeno. A limpeza real grava 2.508 linhas dentro da transação; o rollback as desfaz (deixa tuplas mortas pro autovacuum).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em serial, passo text, linha text);

-- ===== 20261017020000 (corpo da migration, sem begin/commit) =====
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

-- ===== ajuste só do ensaio: a migration fixa 60 s; aqui a limpeza das 2.508 e os explains podem demorar mais =====
set local statement_timeout = '300s';

-- ===== checagens de objetos =====
insert into pg_temp._z_out(passo, linha)
select '01 grants (esperado: tudo false)', jsonb_build_object(
  'anon_executa_nome_limpo', has_function_privilege('anon', 'pessoas.nome_limpo(text)', 'execute'),
  'authenticated_executa_nome_limpo', has_function_privilege('authenticated', 'pessoas.nome_limpo(text)', 'execute'),
  'service_role_executa_nome_limpo', has_function_privilege('service_role', 'pessoas.nome_limpo(text)', 'execute'),
  'authenticated_executa_par', has_function_privilege('authenticated', 'pessoas.revisao_par_ja_tem(uuid,uuid,text)', 'execute'),
  'authenticated_executa_passo', has_function_privilege('authenticated', 'pessoas.nome_padrao_passo(integer)', 'execute'),
  'authenticated_executa_reverter', has_function_privilege('authenticated', 'pessoas.nome_padrao_reverter(integer)', 'execute'),
  'authenticated_executa_limpar', has_function_privilege('authenticated', 'pessoas.nome_padrao_limpar(integer,integer,integer)', 'execute'),
  'service_role_executa_resolver', has_function_privilege('service_role', 'pessoas.resolver(text,text,text,text,boolean,uuid)', 'execute'),
  'authenticated_executa_anexar', has_function_privilege('authenticated', 'pessoas.anexar(uuid,text,text,text,text)', 'execute'),
  'anon_le_nome_padrao', has_table_privilege('anon', 'pessoas.nome_padrao', 'select'),
  'authenticated_escreve_nome_padrao', has_table_privilege('authenticated', 'pessoas.nome_padrao', 'insert'),
  'service_role_le_nome_padrao', has_table_privilege('service_role', 'pessoas.nome_padrao', 'select'),
  'authenticated_le_item', has_table_privilege('authenticated', 'arquivo.pessoas_nome_padrao_item', 'select'),
  'service_role_le_item', has_table_privilege('service_role', 'arquivo.pessoas_nome_padrao_item', 'select'))::text;
insert into pg_temp._z_out(passo, linha)
select '02 rls ligada nas duas tabelas (esperado: true, true)', (select relrowsecurity::text from pg_class where oid = 'pessoas.nome_padrao'::regclass) || ', '
    || (select relrowsecurity::text from pg_class where oid = 'arquivo.pessoas_nome_padrao_item'::regclass);
insert into pg_temp._z_out(passo, linha)
select '03 semente (esperado: GUARDIAO DO LEGADO)', string_agg(chave, ' | ' order by chave) from pessoas.nome_padrao;
insert into pg_temp._z_out(passo, linha)
select '04 chave da limpeza nasce desligada (esperado: ligada=false, ate=null)', jsonb_build_object('ligada', ligada, 'ate', ate)::text
  from pessoas.carga_chave where fonte = 'nome_padrao_limpeza';
insert into pg_temp._z_out(passo, linha)
select '05 nome_limpo (esperado, na ordem: NULL | NULL | NULL | NULL | Zzensaio Maria Silvazz | Guardião do Legado Zzmais | vazio)',
       concat_ws(' | ',
         coalesce(pessoas.nome_limpo('GUARDIAO DO LEGADO'), 'NULL'),
         coalesce(pessoas.nome_limpo('Guardião do Legado'), 'NULL'),
         coalesce(pessoas.nome_limpo('  guardiao  do   legado! '), 'NULL'),
         coalesce(pessoas.nome_limpo(null), 'NULL'),
         coalesce(pessoas.nome_limpo('Zzensaio Maria Silvazz'), 'NULL'),
         coalesce(pessoas.nome_limpo('Guardião do Legado Zzmais'), 'NULL'),
         coalesce(pessoas.nome_limpo(''), 'NULL'));
insert into pg_temp._z_out(passo, linha)
select '06 corpo vigente das 4 funções tem as marcas novas (esperado: 4 linhas com true)', f || ' ' || (p.prosrc like '%20261017020000%')::text
  from (values ('pessoas.resolver(text,text,text,text,boolean,uuid)'), ('pessoas.casar_email(text,text,text,text)'),
               ('pessoas.registrar(jsonb,text,uuid)'), ('pessoas.anexar(uuid,text,text,text,text)')) v(f)
  join pg_proc p on p.oid = to_regprocedure(v.f);

do $t$
declare v1 text; v2 text; v3 text; v4 text;
begin
  begin call pessoas.nome_padrao_limpar(); v1 := 'SEM ERRO (errado)'; exception when others then v1 := sqlstate; end;
  begin call pessoas.nome_padrao_limpar(0); v2 := 'SEM ERRO (errado)'; exception when others then v2 := sqlstate; end;
  begin call pessoas.nome_padrao_limpar(500, 5000, 1); v3 := 'SEM ERRO (errado)'; exception when others then v3 := sqlstate; end;
  begin insert into pessoas.nome_padrao (chave, motivo, por) values ('Guardião do Legado', 'ensaio', 'ensaio'); v4 := 'SEM ERRO (errado)'; exception when others then v4 := sqlstate; end;
  insert into pg_temp._z_out(passo, linha)
  values ('07 guardas (esperado: 55000 chave desligada | 22023 passo zero | 22023 orçamento | 23514 chave fora do formato de norm_nome)', v1 || ' | ' || v2 || ' | ' || v3 || ' | ' || v4);
end
$t$;

-- ===== o estado real ANTES (só leitura) =====
create temp table _z (k text primary key, v text);
create temp table _z_antes as
  select p.id, p.nome, p.atualizado_em from pessoas.pessoas p
   where p.nome is not null and pessoas.norm_nome(p.nome) = any(array['GUARDIAO DO LEGADO']::text[]);
insert into pg_temp._z_out(passo, linha)
select '10 pessoas com nome padrão ANTES (esperado: 2508 em 16/10/2026 14:15 UTC, ou o número vigente se a carga andou)', count(*)::text from pg_temp._z_antes;
insert into pg_temp._z
select 'hash0', md5(coalesce(string_agg(id::text || '|' || nome || '|' || atualizado_em::text, ',' order by id), '')) from pg_temp._z_antes;
insert into pg_temp._z_out(passo, linha)
select '11 revisões pendentes que existem só pelo nome padrão ANTES (esperado: 19 em 16/10/2026 14:06 UTC, todas so_nome)', count(*)::text
  from pessoas.revisao r
 where r.status = 'pendente' and r.motivo = 'so_nome'
   and (select pessoas.nome_limpo(p.nome) is null and p.nome is not null from pessoas.pessoas p where p.id = pessoas.atual(r.pessoa_id))
   and not exists (select 1 from unnest(r.candidatos) c
                    where not coalesce((select pessoas.nome_limpo(p.nome) is null and p.nome is not null from pessoas.pessoas p where p.id = pessoas.atual(c)), false));

-- ===== a entrada: nome padrão vira NULL e não abre so_nome =====
do $t$
declare r jsonb; n text; nid uuid;
begin
  insert into pessoas.pessoas (nome, teste) values ('Guardião do Legado', true);   -- legado: nome padrão já gravado, como as 2.508 antes da limpeza
  r := pessoas.resolver('GUARDIAO DO LEGADO', 'zzensaio.np1@exemplo.invalid', null, null, true);
  select p.nome into n from pessoas.pessoas p where p.id = (r->>'pessoa_id')::uuid;
  insert into pg_temp._z_out(passo, linha)
  values ('20 resolver com nome padrão (esperado: nova=true, revisao=null, nome_gravado=NULL; antes da migration abriria so_nome)',
          jsonb_build_object('nova', r->'nova', 'revisao', r->'revisao', 'nome_gravado', coalesce(n, 'NULL'))::text);
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('20 resolver com nome padrão: ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;
do $t$
declare r jsonb; n text;
begin
  insert into pessoas.pessoas (nome, teste) values ('Zzensaio Fulano Zzunico', true);
  r := pessoas.resolver('Zzensaio Fulano Zzunico', 'zzensaio.np2@exemplo.invalid', null, null, true);
  select p.nome into n from pessoas.pessoas p where p.id = (r->>'pessoa_id')::uuid;
  insert into pg_temp._z_out(passo, linha)
  values ('21 CONTROLE: nome comum igual a um já existente (esperado: nova=true, revisao=so_nome, nome_gravado=Zzensaio Fulano Zzunico; prova que o caminho do so_nome continua igual)',
          jsonb_build_object('nova', r->'nova', 'revisao', r->'revisao', 'nome_gravado', coalesce(n, 'NULL'))::text);
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('21 controle so_nome: ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;
do $t$
declare r jsonb; n text; nid text;
begin
  r := pessoas.registrar(jsonb_build_object('email', 'zzensaio.np3@exemplo.invalid', 'nome', 'GUARDIAO DO LEGADO', 'teste', true), 'formulario', null);
  select p.nome into n from pessoas.pessoas p join pessoas.identificadores i on i.pessoa_id = p.id
   where i.tipo = 'email' and i.chave = 'zzensaio.np3@exemplo.invalid';
  insert into pg_temp._z_out(passo, linha)
  values ('22 registrar com nome padrão (esperado: ok=true, nome_gravado=NULL)',
          jsonb_build_object('ok', r->'ok', 'nome_gravado', coalesce(n, 'NULL'))::text);
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('22 registrar com nome padrão: ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;
do $t$
declare r jsonb; n text;
begin
  r := pessoas.casar_email('GUARDIAO DO LEGADO', 'zzensaio.np4@exemplo.invalid', null, 'importacao');
  select p.nome into n from pessoas.pessoas p where p.id = (r->>'pessoa_id')::uuid;
  insert into pg_temp._z_out(passo, linha)
  values ('23 casar_email com nome padrão (esperado: nova=true, nome_gravado=NULL; pessoa_id nulo = e-mail descartado pela validação, trocar o domínio no ensaio)',
          jsonb_build_object('nova', r->'nova', 'pessoa_id_nulo', (r->>'pessoa_id') is null, 'nome_gravado', coalesce(n, 'NULL'))::text);
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('23 casar_email com nome padrão: ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;

-- ===== par já decidido não reabre =====
do $t$
declare a uuid; b uuid; c uuid; n0 int; n1 int; n2 int; rid bigint;
begin
  insert into pessoas.pessoas (nome, teste) values ('Zzensaio Par Zzaa', true) returning id into a;
  insert into pessoas.pessoas (nome, teste) values ('Zzensaio Par Zzbb', true) returning id into b;
  insert into pessoas.pessoas (nome, teste) values ('Zzensaio Par Zzcc', true) returning id into c;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem)
  values (a, 'email', 'zzensaio.par.a@exemplo.invalid', 'zzensaio.par.a@exemplo.invalid', 'importacao'),
         (b, 'email', 'zzensaio.par.b@exemplo.invalid', 'zzensaio.par.b@exemplo.invalid', 'importacao');
  -- 1) controle: b anexa o e-mail de a, a revisão email_conflito abre
  perform pessoas.anexar(b, 'email', 'zzensaio.par.a@exemplo.invalid', 'zzensaio.par.a@exemplo.invalid', 'importacao');
  select count(*) into n0 from pessoas.revisao r where r.pessoa_id = b and a = any(r.candidatos);
  -- 2) repetir com a revisão ainda pendente: não duplica
  perform pessoas.anexar(b, 'email', 'zzensaio.par.a@exemplo.invalid', 'zzensaio.par.a@exemplo.invalid', 'importacao');
  select count(*) into n1 from pessoas.revisao r where r.pessoa_id = b and a = any(r.candidatos);
  -- 3) decidir 'diferente' e repetir dos dois lados: não reabre
  update pessoas.revisao set status = 'diferente', decidido_por = null, decidido_em = now() where pessoa_id = b and a = any(candidatos) returning id into rid;
  perform pessoas.anexar(b, 'email', 'zzensaio.par.a@exemplo.invalid', 'zzensaio.par.a@exemplo.invalid', 'importacao');
  perform pessoas.anexar(a, 'email', 'zzensaio.par.b@exemplo.invalid', 'zzensaio.par.b@exemplo.invalid', 'importacao');
  select count(*) into n2 from pessoas.revisao r where (r.pessoa_id = b and a = any(r.candidatos)) or (r.pessoa_id = a and b = any(r.candidatos));
  insert into pg_temp._z_out(passo, linha)
  values ('30 anexar: par decidido diferente não reabre (esperado: 1 depois da primeira, 1 depois da repetida pendente, 1 depois de decidido e repetido dos dois lados)',
          n0 || ' | ' || n1 || ' | ' || n2);
  insert into pg_temp._z_out(passo, linha)
  select '31 revisao_par_ja_tem (esperado: diferente | diferente | NULL | NULL)',
         concat_ws(' | ', coalesce(pessoas.revisao_par_ja_tem(a, b, 'email_conflito'), 'NULL'), coalesce(pessoas.revisao_par_ja_tem(b, a, null), 'NULL'),
                          coalesce(pessoas.revisao_par_ja_tem(a, c, 'email_conflito'), 'NULL'), coalesce(pessoas.revisao_par_ja_tem(a, a, 'email_conflito'), 'NULL'));
  -- 4) pendente só conta com o mesmo motivo
  insert into pessoas.revisao (pessoa_id, motivo, candidatos) values (c, 'so_nome', array[a]);
  insert into pg_temp._z_out(passo, linha)
  select '32 pendente conta só com o mesmo motivo (esperado: pendente | NULL | NULL)',
         concat_ws(' | ', coalesce(pessoas.revisao_par_ja_tem(c, a, 'so_nome'), 'NULL'), coalesce(pessoas.revisao_par_ja_tem(c, a, 'email_conflito'), 'NULL'), coalesce(pessoas.revisao_par_ja_tem(c, a, null), 'NULL'));
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('30 par decidido (anexar): ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;
do $t$
declare cid uuid; pa uuid; pl uuid; r jsonb; n0 int; n1 int; n2 int; n3 int; m1 text; m2 text; m3 text; rid bigint;
begin
  -- comprador e lead com o mesmo e-mail: o resolver e a casar_email veem email_conflito entre a pessoa do comprador (pa) e a do lead (pl)
  insert into public.compradores (nome, email) values ('Zzensaio Comprador Zzpar', 'zzensaio.par.c@exemplo.invalid') returning id into cid;
  pa := pessoas.pessoa_do_comprador(cid);
  insert into pessoas.pessoas (nome, teste) values ('Zzensaio Lead Zzpar', true) returning id into pl;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem)
  values (pl, 'email', 'zzensaio.par.c@exemplo.invalid', 'zzensaio.par.c@exemplo.invalid', 'importacao') on conflict do nothing;
  r := pessoas.resolver('Zzensaio Comprador Zzpar', 'zzensaio.par.c@exemplo.invalid', null, null, true);
  m1 := coalesce(r->>'revisao', 'NULL');
  select count(*) into n0 from pessoas.revisao x where x.pessoa_id in (pa, pl) and (pa = any(x.candidatos) or pl = any(x.candidatos));
  update pessoas.revisao set status = 'diferente', decidido_por = null, decidido_em = now()
   where pessoa_id in (pa, pl) and (pa = any(candidatos) or pl = any(candidatos)) and status = 'pendente';
  r := pessoas.resolver('Zzensaio Comprador Zzpar', 'zzensaio.par.c@exemplo.invalid', null, null, true);
  m2 := coalesce(r->>'revisao', 'NULL');
  select count(*) into n1 from pessoas.revisao x where x.pessoa_id in (pa, pl) and (pa = any(x.candidatos) or pl = any(x.candidatos));
  r := pessoas.casar_email('Zzensaio Comprador Zzpar', 'zzensaio.par.c@exemplo.invalid', null, 'importacao');
  m3 := coalesce(r->>'motivo', 'NULL');
  select count(*) into n2 from pessoas.revisao x where x.pessoa_id in (pa, pl) and (pa = any(x.candidatos) or pl = any(x.candidatos));
  insert into pg_temp._z_out(passo, linha)
  values ('33 resolver e casar_email com par decidido diferente (esperado: resolver 1ª chamada=email_conflito e 1 revisão; depois de decidir: resolver revisao=NULL, casar_email motivo=NULL, e continua 1 revisão no par. Se a 1ª chamada vier NULL, o cenário não montou: ler o ERRO ou a linha)',
          jsonb_build_object('resolver_antes', m1, 'revisoes_antes', n0, 'resolver_depois', m2, 'revisoes_depois_resolver', n1, 'casar_email_depois', m3, 'revisoes_depois_casar', n2)::text);
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('33 par decidido (resolver, casar_email): ERRO', sqlstate || ' ' || sqlerrm);
end
$t$;

-- ===== a limpeza das pessoas reais (desfeita pelo rollback) =====
insert into pg_temp._z select 'pend0', count(*)::text from pessoas.revisao where status = 'pendente';
-- 1º lote com explain (analyze): o comando é o mesmo do corpo de pessoas.nome_padrao_passo
do $t$
declare l text;
begin
  for l in execute $e$
    explain (analyze, buffers, costs off, timing on)
    with alvo as (
      select p.id, p.nome, p.atualizado_em from pessoas.pessoas p
       where p.nome is not null and pessoas.norm_nome(p.nome) = any(array['GUARDIAO DO LEGADO']::text[])
       limit 500 for update of p),
    cop as (
      insert into arquivo.pessoas_nome_padrao_item (pessoa_id, chave, nome_antes, atualizado_em_antes)
      select a.id, pessoas.norm_nome(a.nome), a.nome, a.atualizado_em from alvo a returning pessoa_id),
    upd as (
      update pessoas.pessoas p set nome = null, atualizado_em = now() from cop where p.id = cop.pessoa_id returning 1)
    select count(*) from upd $e$
  loop
    insert into pg_temp._z_out(passo, linha) values ('40 explain analyze do 1º lote de 500 (grava de verdade, desfeito no rollback)', l);
  end loop;
end
$t$;
do $t$
declare n integer; tot integer := 0; passos integer := 1; ant integer;
begin
  select count(*) into ant from arquivo.pessoas_nome_padrao_item;   -- o lote do explain
  tot := ant;
  loop
    n := pessoas.nome_padrao_passo(500);
    exit when n = 0 or passos > 40;
    tot := tot + n; passos := passos + 1;
  end loop;
  insert into pg_temp._z_out(passo, linha)
  values ('41 limpeza: pessoas limpas no total e passos (esperado: total = linha 10, passos = teto(total/500) = 6 para 2508)', tot || ' | ' || passos);
end
$t$;
insert into pg_temp._z_out(passo, linha)
select '42 DEPOIS (esperado: ainda com nome padrão=0 | itens ativos = linha 10 | das pessoas da linha 10 com nome nulo = linha 10)',
       (select count(*) from pessoas.pessoas p where p.nome is not null and pessoas.norm_nome(p.nome) = any(array['GUARDIAO DO LEGADO']::text[]))::text
       || ' | ' || (select count(*) from arquivo.pessoas_nome_padrao_item where revertido_em is null)::text
       || ' | ' || (select count(*) from pg_temp._z_antes a join pessoas.pessoas p on p.id = a.id where p.nome is null)::text;
insert into pg_temp._z_out(passo, linha)
select '43 repetir o passo (esperado: 0, nada a fazer)', pessoas.nome_padrao_passo(500)::text;
insert into pg_temp._z_out(passo, linha)
select '44 revisões pendentes antes | depois da limpeza (esperado: iguais; nenhuma revisão muda de status)',
       (select v from pg_temp._z where k = 'pend0') || ' | ' || (select count(*) from pessoas.revisao where status = 'pendente')::text;

-- ===== reversão pelo reverter =====
insert into pg_temp._z_out(passo, linha)
select '50 reverter (esperado: revertidos = linha 10, pulados 0, restam 0)', pessoas.nome_padrao_reverter(5000)::text;
insert into pg_temp._z_out(passo, linha)
select '51 estado igual ao ANTES (esperado: true)',
       (md5(coalesce(string_agg(p.id::text || '|' || p.nome || '|' || p.atualizado_em::text, ',' order by p.id), '')) = (select v from pg_temp._z where k = 'hash0'))::text
  from pessoas.pessoas p join pg_temp._z_antes a on a.id = p.id;
insert into pg_temp._z_out(passo, linha)
select '52 reverter de novo (esperado: revertidos 0, pulados 0, restam 0)', pessoas.nome_padrao_reverter(5000)::text;

-- ===== reversão completa (20261017020000_reversao.sql) depois de limpar de novo =====
do $t$
declare n integer; tot integer := 0;
begin
  loop n := pessoas.nome_padrao_passo(1000); exit when n = 0; tot := tot + n; end loop;
  insert into pg_temp._z_out(passo, linha) values ('60 limpou de novo antes da reversão completa (esperado: = linha 10)', tot::text);
end
$t$;

-- ===== 20261017020000_reversao.sql (corpo, sem begin/commit) =====
-- Reversão de 20261017020000: devolve os nomes pela cópia, restaura o corpo de 16/10/2026 das 4 funções e remove o que a migration criou.
-- Os nomes voltam pelo arquivo.pessoas_nome_padrao_item (nome e atualizado_em exatos). A tabela de cópia FICA (histórico, nunca se apaga).
-- Tudo ou nada: aborta sem mexer em nada se (a) alguma das 4 funções já não é a desta migration (alguém mexeu depois) ou
-- (b) sobrar nome sem devolver (a pessoa já recebeu outro nome depois da limpeza): olhar à mão.
-- Revisão que deixou de ser aberta por causa da guarda não volta a existir (nunca houve linha para voltar); status de revisão nenhum foi mudado pela migration.
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $r$
declare v jsonb; n int; r record;
begin
  if to_regclass('pessoas.nome_padrao') is null or to_regprocedure('pessoas.nome_padrao_reverter(integer)') is null then
    raise exception '20261017020000: reversão sem efeito, a migration não está aplicada.';
  end if;
  for r in
    select v.f, v.esperado, md5(p.prosrc) atual
      from (values ('pessoas.resolver(text,text,text,text,boolean,uuid)', '5a0e5974c1dbcff5c71127029d03b28d'),
                   ('pessoas.casar_email(text,text,text,text)',           'c0e438cd285fe189bc8e30e1b1072a85'),
                   ('pessoas.registrar(jsonb,text,uuid)',                 'b42694f0ffb337dfe665d8b7a5693bc3'),
                   ('pessoas.anexar(uuid,text,text,text,text)',           '81ad41050134f7400f0ad61be1a53961')) v(f, esperado)
      join pg_proc p on p.oid = to_regprocedure(v.f)
  loop
    if r.atual <> r.esperado then
      raise exception '20261017020000: % foi alterada depois desta migration (md5 % em vez de %). Reverter à mão, para não apagar a mudança posterior.', r.f, r.atual, r.esperado;
    end if;
  end loop;
  v := pessoas.nome_padrao_reverter(5000);
  select count(*) into n from arquivo.pessoas_nome_padrao_item where revertido_em is null;
  if n > 0 then
    raise exception '20261017020000: % item(ns) sem reverter (resultado: %). Nada foi desfeito; conferir à mão.', n, v;
  end if;
  update pessoas.carga_chave set ligada = false, por = 'reversao 20261017020000', em = now() where fonte = 'nome_padrao_limpeza';
end
$r$;

-- corpos de 16/10/2026 (pg_get_functiondef do banco antes da migration)

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
  v_nome  text := nullif(left(btrim(coalesce(p_nome, '')), 160), '');
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
  v_nome text := nullif(left(btrim(coalesce(p->>'nome', '')), 160), '');
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
         and not exists (select 1 from pessoas.revisao where status = 'pendente' and pessoa_id = p_pessoa and v_dono = any(candidatos)) then
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

drop procedure if exists pessoas.nome_padrao_limpar(integer, integer, integer);
drop function if exists pessoas.nome_padrao_reverter(integer);
drop function if exists pessoas.nome_padrao_passo(integer);
drop function if exists pessoas.nome_limpo(text);
drop function if exists pessoas.revisao_par_ja_tem(uuid, uuid, text);
delete from pessoas.carga_chave where fonte = 'nome_padrao_limpeza';
drop table if exists pessoas.nome_padrao;

-- ===== depois da reversão completa =====
insert into pg_temp._z_out(passo, linha)
select '70 estado das pessoas igual ao ANTES (esperado: true)',
       (md5(coalesce(string_agg(p.id::text || '|' || p.nome || '|' || p.atualizado_em::text, ',' order by p.id), '')) = (select v from pg_temp._z where k = 'hash0'))::text
  from pessoas.pessoas p join pg_temp._z_antes a on a.id = p.id;
insert into pg_temp._z_out(passo, linha)
select '71 objetos removidos (esperado: NULL em todos)',
       concat_ws(' | ', coalesce(to_regclass('pessoas.nome_padrao')::text, 'NULL'), coalesce(to_regprocedure('pessoas.nome_limpo(text)')::text, 'NULL'),
                        coalesce(to_regprocedure('pessoas.revisao_par_ja_tem(uuid,uuid,text)')::text, 'NULL'), coalesce(to_regprocedure('pessoas.nome_padrao_passo(integer)')::text, 'NULL'),
                        coalesce(to_regprocedure('pessoas.nome_padrao_reverter(integer)')::text, 'NULL'), coalesce(to_regprocedure('pessoas.nome_padrao_limpar(integer,integer,integer)')::text, 'NULL'));
insert into pg_temp._z_out(passo, linha)
select '72 corpo das 4 funções voltou ao de 16/10/2026 (esperado: 4 linhas com true)', f || ' ' || (md5(p.prosrc) = v.md5)::text
  from (values ('pessoas.resolver(text,text,text,text,boolean,uuid)', '40eaf91a3fbe23dda1dfd4585af79137'),
               ('pessoas.casar_email(text,text,text,text)', 'fa42d0800e42ed4d025efaa93364beaa'),
               ('pessoas.registrar(jsonb,text,uuid)', '8f77b9fc25b84d526be4c9ebad528c2e'),
               ('pessoas.anexar(uuid,text,text,text,text)', '4f6baa53f1e540b3334c64ba9a552100')) v(f, md5)
  join pg_proc p on p.oid = to_regprocedure(v.f);
insert into pg_temp._z_out(passo, linha)
select '73 a cópia ficou (esperado: itens = 2 x linha 10 | todos revertidos = o mesmo número)',
       count(*)::text || ' | ' || count(*) filter (where revertido_em is not null)::text from arquivo.pessoas_nome_padrao_item;
insert into pg_temp._z_out(passo, linha)
select '74 chave da limpeza removida (esperado: 0)', count(*)::text from pessoas.carga_chave where fonte = 'nome_padrao_limpeza';

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
