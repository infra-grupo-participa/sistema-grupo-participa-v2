-- 20261007i: base de pessoas — evento 'pre_checkout' e rastro da captura (chave do evento, sck, xcod, página)
--
-- STATUS: NÃO APLICADA. Precisa do ACEITE DO ARTHUR antes (o schema pessoas e a função pessoas.registrar são dele,
-- 20261005r). Ensaio escrito e NÃO rodado: 20261007i_ensaio.sql. Relatório: 20261007i.explain.md.
-- Quem chama: rota POST /api/captura/lead (web/app/api/captura/lead/route.ts), docs/captura-de-lead.md.
--
-- POR QUE
--   A página da Clínica de Miami (clinica-miami-2026-12) vai mandar o pré-checkout para a base de pessoas pela rota
--   /api/captura/lead → public.pessoas_registrar_lead → pessoas.registrar. Hoje o pré-checkout não cabe em dois lugares:
--     a) CHECK eventos_tipo_check de pessoas.eventos (lista da 20261006043612) não tem 'pre_checkout';
--     b) pessoas.registrar recusa evento fora de (lead, mql, nao_mql, cadastro) ANTES do insert: só mudar o CHECK
--        não basta (a função devolve "Evento inválido").
--   E a função não guarda chave do evento, sck, xcod nem página quando o projeto não é achado pela sigla
--   (mkt.projetos.sigla, ex.: PB26). A chave da casa (nome-curto-aaaa-mm) não é sigla: sem isto o lead chega sem dizer
--   de qual evento veio.
--
-- O QUE FAZ
--   1. eventos_tipo_check: a lista conferida (guarda) + 'pre_checkout'. Só ACRESCENTA.
--   2. pessoas.registrar (mesma assinatura, create or replace preserva dono e grants): duas mudanças, nada mais:
--      - aceita evento 'pre_checkout';
--      - acrescenta ao detalhe do evento, quando vierem: chave_evento (kebab-case, até 80), sck (até 200),
--        xcod (até 200), pagina (sem ?query e #fragmento, até 300). Nunca nome, e-mail, telefone ou documento.
--      O corpo novo parte do corpo da 20261005r, que a guarda confere por md5 (e082542b…): se o corpo vivo for outro,
--      a migration aborta e o corpo tem de ser refeito a partir do pg_get_functiondef (manual §3).
--   Nenhuma tabela, índice, grant ou policy novo. public.pessoas_registrar_lead não muda (só service_role executa).
--
-- QUEM LÊ pessoas.eventos.tipo (grep em infra/supabase/migrations, 07/10/2026): todos filtram por lista fechada
--   ('lead', 'mql', 'nao_mql', 'compra', 'checkout', 'reembolso'): o valor novo é ignorado, ninguém quebra. Efeito:
--   pré-checkout NÃO conta como lead no Tráfego (20261006g/20261006i contam tipo = 'lead') nem aparece na jornada do
--   CRM (20261007114831) até alguém decidir que deve.
--
-- AS 5 PERGUNTAS
--   escala: custo por lead (resolver por índice, igual à 20261005r); detalhe ganha até ~800 bytes por evento.
--   índice: nenhum novo. eventos_projeto_idx é parcial (projeto_id not null) e não cobre pré-checkout sem projeto;
--     ninguém filtra por esse tipo hoje. Quem passar a filtrar decide o índice.
--   frequência: 1 chamada por envio do formulário da página (dezenas a poucas centenas por dia).
--   repetição: 1 RPC por envio; nada por linha.
--   reversão: bloco REVERSÃO no fim (corpo antigo da 20261005r + CHECK antigo depois de reclassificar os eventos).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- 0. Guarda de premissa
do $guarda$
begin
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check')
     is distinct from
     'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text, ''checkout''::text, ''reembolso''::text])))'
  then
    raise exception '20261007i: eventos_tipo_check diferente do esperado (20261006043612). Releia pg_get_constraintdef.';
  end if;
  if to_regprocedure('pessoas.registrar(jsonb,text,uuid)') is null
     or to_regprocedure('public.pessoas_registrar_lead(jsonb)') is null then
    raise exception '20261007i: pessoas.registrar ou public.pessoas_registrar_lead ausente';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure)
     is distinct from 'e082542bde3f7abc431d562bb4e032e0' then
    raise exception '20261007i: corpo vivo de pessoas.registrar não é o da 20261005r (md5). Refazer a partir do pg_get_functiondef.';
  end if;
end
$guarda$;

-- 1. CHECK: só acrescenta 'pre_checkout' (pessoas.eventos ainda pequena; validação da tabela inteira, dentro do lock_timeout)
alter table pessoas.eventos drop constraint eventos_tipo_check;
alter table pessoas.eventos add constraint eventos_tipo_check check (tipo in ('lead', 'mql', 'nao_mql', 'cadastro', 'compra',
  'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso', 'pre_checkout'));

-- 2. pessoas.registrar: corpo da 20261005r + 'pre_checkout' + rastro da captura no detalhe
-- Entrada única de pessoa (formulário, CRM, importação). p: nome, email, telefone, cep, aluno_id, projeto (sigla),
-- pagina_id ou dominio+caminho, campanha, utm_*, fbclid/gclid, visitante (mkt_web), teste,
-- evento (lead|mql|nao_mql|cadastro|pre_checkout), chave_evento, sck, xcod, pagina (20261007i).
create or replace function pessoas.registrar(p jsonb, p_fonte text, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
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
$$;

-- 3. Pós-condição: CHECK novo, corpo novo, ACL intacta (nada novo executável por anon/authenticated)
do $confere$
begin
  if position('''pre_checkout''' in (select pg_get_constraintdef(c.oid) from pg_constraint c
                                      where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check')) = 0 then
    raise exception '20261007i: CHECK sem pre_checkout';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure)
     is distinct from '8f77b9fc25b84d526be4c9ebad528c2e' then
    raise exception '20261007i: corpo gravado de pessoas.registrar diferente do arquivo';
  end if;
  if has_function_privilege('anon', 'pessoas.registrar(jsonb,text,uuid)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.registrar(jsonb,text,uuid)', 'execute')
     or has_function_privilege('anon', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.pessoas_registrar_lead(jsonb)', 'execute') then
    raise exception '20261007i: permissões mudaram (registrar/registrar_lead)';
  end if;
end
$confere$;

-- REVERSÃO (numa transação). Antes, desligar a rota: apagar CAPTURA_LEAD_SECRET na Hostinger e reiniciar o app → 503.
-- 1. Corpo antigo: recriar pessoas.registrar com o corpo da 20261005r_pessoas_e_crm_fundacao.sql (md5 e082542b…).
-- 2. CHECK antigo só depois de tirar os eventos novos da lista (não apagar evento sem decisão do Arthur):
-- (atenção: virar 'lead' faz esses eventos passarem a contar como lead no Tráfego; decisão do Arthur)
-- update pessoas.eventos set tipo = 'lead', detalhe = detalhe || '{"era": "pre_checkout"}' where tipo = 'pre_checkout';
-- alter table pessoas.eventos drop constraint eventos_tipo_check;
-- alter table pessoas.eventos add constraint eventos_tipo_check check (tipo in ('lead', 'mql', 'nao_mql', 'cadastro', 'compra',
--   'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso'));
