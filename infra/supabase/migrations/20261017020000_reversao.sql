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
