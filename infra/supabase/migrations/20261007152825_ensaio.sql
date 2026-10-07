-- RESULTADO (07/10/2026, produção, rollback): 0 erro; depois1 = depois2. Tabela e explain em 20261007k.explain.md §5.
-- Regenerado depois só com mudança de comentário (STATUS) nos três .sql; o SQL executável é o mesmo que rodou.
-- Rodar como no padrão da casa: o `select … ; rollback;` final trocado por raise exception com o conteúdo de _z_out.
-- Ensaio da SEQUÊNCIA 20261007i -> 20261007j -> 20261007k, rodada 2x num só begin … rollback (revisão do Forja, 07/10).
-- Gerado a partir dos três .sql (conteúdo idêntico, colado como está). Nada persiste: termina em ROLLBACK
-- (pelo aplica_sql.py ensaio, o fim vira raise exception com a saída).
-- Esperado: '1 antes' = estado vivo; '2 depois1' e '3 depois2' iguais (2ª passada sem efeito);
--   casos da i: pre_checkout ok true com detalhe chave_evento/sck/xcod/pagina sem query; lead_sem_evento ok true tipo lead;
--   evento_invalido ok false 'Evento inválido (…pre_checkout)'; chave_invalida ok true e detalhe SEM chave_evento;
--   acl: registrar sem anon/authenticated; registrar_lead só service_role (e postgres).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role; grant all on sequence pg_temp._z_out_em_seq to service_role;

insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_build_object(
  'i_ck_tem_pre_checkout', position('''pre_checkout''' in (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check')) > 0,
  'i_md5_registrar', (select md5(p.prosrc) from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure),
  'i_eventos', (select count(*) from pessoas.eventos),
  'i_pre_checkout', (select count(*) from pessoas.eventos where tipo = 'pre_checkout'),
  'j_regra_614', (select string_agg(r.id || ':' || r.projeto, ',') from crm.catalogo_regra r where r.ativo and r.campo = 'ac_lista' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')),
  'j_massa_regra_ou_utm', (select count(*) from crm.pessoa_origem po where po.projeto_regra_id = (select r.id from crm.catalogo_regra r where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null) or (po.projeto is null and not po.projeto_manual and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))),
  'j_contatos_miami', (select count(*) from crm.pessoa_origem where projeto = 'miami-2026-12'),
  'j_contatos_clinica', (select count(*) from crm.pessoa_origem where projeto = 'clinica-miami-2026-12'),
  'j_ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '') where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign' and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))),
  'j_negocios_em_funil_miami', (select count(*) from crm.negocio n join crm.funil f on f.id = n.funil_id where f.projeto = 'miami-2026-12'),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'k_projetos', (select count(*) from mkt.projetos),
  'k_linha', (select jsonb_build_object('sigla', sigla, 'nome', nome, 'linha', linha, 'ano', ano, 'inicio', inicio, 'fim', fim, 'tipo', tipo, 'unidade', unidade, 'subarea', subarea_trafego, 'tl', tipo_lancamento, 'ativo', ativo) from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12')
)::text;

-- ===== PASSADA 1: 20261007i =====
-- 20261007i: base de pessoas — evento 'pre_checkout' e rastro da captura (chave do evento, sck, xcod, página)
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
-- Aceite do Arthur dado em 07/10/2026 (o schema pessoas e pessoas.registrar são dele, 20261005r). Relatório: 20261007i.explain.md.
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

-- 0. Guarda de premissa. Aceita dois estados e nenhum outro:
--    a) antes da 20261007i: CHECK da 20261006043612 e corpo da 20261005r (md5 e082542b…) → aplica;
--    b) depois da 20261007i: CHECK com 'pre_checkout' e corpo desta migration (md5 8f77b9fc…) → "já aplicada": os passos
--       1 e 2 regravam exatamente o mesmo CHECK e o mesmo corpo (sem efeito) e a pós-condição confere. Assim um segundo
--       `db push` antes de renomear o arquivo não aborta a cadeia (revisão do Forja, 07/10/2026; manual §3).
do $guarda$
declare v_ck text; v_md5 text;
begin
  if to_regprocedure('pessoas.registrar(jsonb,text,uuid)') is null
     or to_regprocedure('public.pessoas_registrar_lead(jsonb)') is null then
    raise exception '20261007i: pessoas.registrar ou public.pessoas_registrar_lead ausente';
  end if;
  select pg_get_constraintdef(c.oid) into v_ck from pg_constraint c
   where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check';
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure;
  if v_ck is not distinct from
       'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text, ''checkout''::text, ''reembolso''::text, ''pre_checkout''::text])))'
     and v_md5 is not distinct from '8f77b9fc25b84d526be4c9ebad528c2e' then
    raise notice '20261007i: já aplicada (CHECK com pre_checkout e corpo 8f77b9fc…). Os passos seguintes não mudam nada.';
  elsif v_ck is distinct from
       'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text, ''checkout''::text, ''reembolso''::text])))'
  then
    raise exception '20261007i: eventos_tipo_check diferente do esperado (20261006043612 ou pós-20261007i). Releia pg_get_constraintdef.';
  elsif v_md5 is distinct from 'e082542bde3f7abc431d562bb4e032e0' then
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

-- ===== PASSADA 1: 20261007j =====
-- 20261007j: Comercial, a regra da lista 614 do ActiveCampaign leva à CLÍNICA de Miami, não ao Encontro dos Diamantes.
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
-- Relatório: 20261007j.explain.md.
--
-- POR QUE
--   A 20261007141044_crm_catalogacao_origem (APLICADA) semeou em crm.catalogo_regra:
--     ('ac_lista', 'contem', 'Clínica Internacional Diamante Dez/26', 'miami-2026-12', 100, 'Lista 614 (confirmado 07/10)')
--   Decisão do Victor Hugo (07/10/2026): a lista 614 é da Clínica de Miami (chave clinica-miami-2026-12, 03 e 04/12),
--   não do Encontro Internacional dos Diamantes (miami-2026-12, 01 e 02/12). Migration aplicada não se edita: arquivo novo.
--
-- O QUE FAZ
--   1. Guarda: existe UMA regra ativa tipo 'projeto', campo 'ac_lista', operador 'contem', padrão "Clínica Internacional
--      Diamante Dez/26" (mesma expressão do índice único: lower(btrim(padrao))), sem janela de datas, com projeto
--      'miami-2026-12' (estado da 20261007141044) ou 'clinica-miami-2026-12' (já corrigida: roda de novo sem efeito).
--      Qualquer outro estado aborta. Aborta também se crm.origem_catalogar(uuid) não existir ou se a massa a recatalogar
--      passar de 1.000 contatos (~3 ms cada pelo explain da 20261007141044: acima disso, rodar em lotes).
--   2. Corrige a regra: projeto = 'clinica-miami-2026-12', nota com a origem da decisão, atualizado_em = now().
--      Padrão, operador, campo, tipo, datas e prioridade não mudam (o índice único catalogo_regra_uidx não é tocado; a
--      chave nova cabe no CHECK '^[a-z0-9][a-z0-9-]{1,79}$').
--   3. Recataloga com a função da própria 20261007141044 (crm.origem_catalogar, a mesma que crm_catalogo_reaplicar usa),
--      porque crm.pessoa_origem GUARDA o projeto copiado (coluna projeto + projeto_regra_id), não deriva na leitura:
--        a) quem tem projeto_regra_id = esta regra (veio por ela);
--        b) quem está sem projeto e tem utm_campaign = clinica-miami-2026-12 entre as chaves vistas: a chave passa a ser
--           "conhecida" (crm.projeto_conhecido lê crm.catalogo_regra.projeto) e o utm implícito passa a resolver.
--      Projeto definido à mão (projeto_manual) não muda: origem_catalogar já preserva.
--   NÃO cria o projeto em mkt.projetos (sigla pendente de confirmação), NÃO mexe em fin.produtos, NÃO mexe na Ativação.
--
-- QUEM LÊ (grep no repo, 07/10/2026): crm.catalogo_regra e crm.pessoa_origem só são lidas pelas funções da
--   20261007141044 (resolver, contatos_itens, crm_contatos_pagina/resumo, crm_catalogo, crm_contato_origem) e pela tela
--   do Comercial via RPC. Nenhum outro repo (disparos-thb, controle-de-eventos, gp-operacoes) lê essas tabelas.
--   A Ativação (20261007135415) chama crm.projeto_do_evento: daqui em diante, evento da lista 614 aponta para
--   clinica-miami-2026-12 (só entra se existir crm.projeto_ativacao com essa chave; sem ela, devolve 'projeto_fechado').
--   Entradas de Ativação já gravadas em miami-2026-12 vindas da lista 614 NÃO são movidas: a migration só conta e avisa
--   (raise notice); mover negócio é decisão do Victor/Arthur.
--
-- AS 5 PERGUNTAS
--   escala: 1 update de 1 linha + origem_catalogar por contato afetado (guarda de 1.000; esperado bem menos: lista de
--     pré-checkout de um evento). A busca do item b) varre crm.pessoa_origem uma vez (base de ~2.800 a 6.000 linhas).
--   índice: a) e b) não têm índice próprio (projeto_regra_id sem índice; chaves em jsonb). Seq scan único numa tabela de
--     milhares de linhas, uma vez. Não justifica índice novo.
--   frequência: uma vez.
--   repetição: nenhuma.
--   reversão: bloco REVERSÃO no fim (voltar o projeto da regra e recatalogar os mesmos contatos).

set local lock_timeout = '5s';

-- ─── 1. Guarda de premissa ────────────────────────────────────────────────────────────────────────────────────────
do $g$
declare v_n int; v_proj text; v_massa int;
begin
  if to_regclass('crm.catalogo_regra') is null or to_regclass('crm.pessoa_origem') is null then
    raise exception '20261007j: falta a 20261007141044 (crm.catalogo_regra / crm.pessoa_origem). Aplique antes.';
  end if;
  if to_regprocedure('crm.origem_catalogar(uuid)') is null then
    raise exception '20261007j: crm.origem_catalogar(uuid) não existe; a recatalogação depende dela (20261007141044).';
  end if;
  select count(*), min(r.projeto) into v_n, v_proj
    from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  if v_n <> 1 then
    raise exception '20261007j: esperava 1 regra ativa ac_lista contem "Clínica Internacional Diamante Dez/26", achei %. Releia crm.catalogo_regra.', v_n;
  end if;
  if v_proj is distinct from 'miami-2026-12' and v_proj is distinct from 'clinica-miami-2026-12' then
    raise exception '20261007j: a regra da lista 614 aponta para "%", nem miami-2026-12 nem clinica-miami-2026-12. Alguém mudou pela tela; conferir com o Victor.', coalesce(v_proj, '(sem projeto)');
  end if;
  select count(*) into v_massa
    from crm.pessoa_origem po
   where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                   and r.vale_de is null and r.vale_ate is null)
      or (po.projeto is null and not po.projeto_manual
          and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                       where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'));
  if v_massa > 1000 then
    raise exception '20261007j: % contatos a recatalogar (teto 1.000). Rodar em lotes antes de seguir.', v_massa;
  end if;
end
$g$;

-- ─── 2. Corrige a regra ───────────────────────────────────────────────────────────────────────────────────────────
update crm.catalogo_regra r
   set projeto = 'clinica-miami-2026-12',
       nota = 'Lista 614: Clínica de Miami, não o Encontro dos Diamantes (decisão do Victor Hugo, 07/10/2026; corrige a semente da 20261007141044)',
       atualizado_em = now()
 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
   and r.vale_de is null and r.vale_ate is null
   and r.projeto = 'miami-2026-12';

-- ─── 3. Recataloga quem a correção atinge (função da 20261007141044, não reimplementada) ─────────────────────────
do $r$
declare v uuid; v_id bigint; v_n int := 0; v_ativ int := 0;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  for v in
    select po.pessoa_id from crm.pessoa_origem po
     where po.projeto_regra_id = v_id
        or (po.projeto is null and not po.projeto_manual
            and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                         where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))
     order by po.pessoa_id
  loop
    perform crm.origem_catalogar(v);
    v_n := v_n + 1;
  end loop;
  raise notice '20261007j: % contatos recatalogados', v_n;

  -- Ativação: entradas já gravadas em miami-2026-12 vindas de lista que esta regra casa. Só conta (não move).
  if to_regclass('crm.ativacao_entrada') is not null then
    select count(*) into v_ativ
      from crm.ativacao_entrada ae
      join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
      left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
     where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
       and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista));
    if v_ativ > 0 then
      raise notice '20261007j: ATENÇÃO, % entradas de Ativação em miami-2026-12 vieram da lista da Clínica. Não foram movidas: levar ao Victor.', v_ativ;
    end if;
  end if;
end
$r$;

-- ─── 4. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v_id bigint; v_res record;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null and r.projeto = 'clinica-miami-2026-12';
  if v_id is null then raise exception '20261007j: a regra não ficou com clinica-miami-2026-12'; end if;
  if exists (select 1 from crm.pessoa_origem po where po.projeto_regra_id = v_id and po.projeto is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007j: há contato ligado à regra da lista 614 com projeto diferente de clinica-miami-2026-12';
  end if;
  if not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007j: clinica-miami-2026-12 não ficou conhecida (crm.projeto_conhecido)';
  end if;
  -- nome da lista 614 como semeado em crm.ac_lista pela 20261007141044
  select * into v_res from crm.catalogo_resolver(
    jsonb_build_object('ac_lista', '614', 'ac_lista_nome', 'Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout'));
  if v_res.r_projeto is distinct from 'clinica-miami-2026-12' or v_res.r_motivo is distinct from 'regra' then
    raise exception '20261007j: o resolver leva a lista 614 para "%" (motivo %), não para clinica-miami-2026-12', v_res.r_projeto, v_res.r_motivo;
  end if;
end
$c$;

-- ─── REVERSÃO (manual, numa transação) ────────────────────────────────────────────────────────────────────────────
-- 1. update crm.catalogo_regra set projeto = 'miami-2026-12', nota = 'Lista 614 (confirmado 07/10)', atualizado_em = now()
--     where ativo and tipo = 'projeto' and campo = 'ac_lista' and operador = 'contem'
--       and lower(btrim(padrao)) = lower('Clínica Internacional Diamante Dez/26') and vale_de is null and vale_ate is null;
-- 2. Recatalogar os mesmos contatos: perform crm.origem_catalogar(pessoa_id) para quem tem projeto_regra_id = id da regra
--    e para quem tem projeto = 'clinica-miami-2026-12' com projeto_motivo = 'utm'.

-- ===== PASSADA 1: 20261007k =====
-- 20261007k: cadastro do projeto da Clínica de Miami em mkt.projetos (sigla CNFMIAMI26, chave clinica-miami-2026-12)
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
--
-- POR QUE
--   A chave clinica-miami-2026-12 (gp-operacoes/projetos/calendario.md, decisão do Victor Hugo de 07/10/2026) já é usada
--   pela regra da lista 614 do ActiveCampaign (20261007j) e pela captura de pré-checkout (20261007i), mas não tem linha
--   em mkt.projetos: a tela mostra a chave crua e o Tráfego não tem o projeto. Sigla CNFMIAMI26 aprovada pelo Victor
--   Hugo em 07/10/2026 (cabe no CHECK projetos_sigla_check ^[A-Z]{2,10}[0-9]{2,4}$).
--
-- DE ONDE VEM CADA VALOR (nada inventado)
--   sigla             CNFMIAMI26                                   aprovada pelo Victor Hugo (07/10/2026)
--   etiqueta_clickup  clinica-miami-2026-12                        gp-operacoes/projetos/calendario.md, linha 14 do calendário
--   nome              Clínica Internacional de Holding Familiar    idem (string exata do calendário)
--   linha             Clínica de Holding Familiar                  gp-operacoes/produtos-e-ofertas/infoprodutos/esteira-de-produtos.md
--                                                                  (coluna obrigatória; a CONFIRMAR com o Victor)
--   ano               2026                                         chave e calendário (03 e 04/12/2026)
--   evento_inicio/fim 2026-12-03 / 2026-12-04                      calendário ("03 e 04/12", Miami)
--   inicio/fim        derivados pelo gatilho projetos_tipo_unidade a partir das datas do evento
--   tipo, unidade, tipo_lancamento, subarea_trafego, especialista, captação: NULOS (fonte não diz; a CONFIRMAR com o Victor).
--     subarea_trafego é derivada pelo gatilho a partir de tipo/unidade: com os dois nulos, fica nula.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha numa tabela de 4. índice: únicos de sigla e etiqueta já existem. frequência: uma vez.
--   repetição: nenhuma. reversão: bloco REVERSÃO no fim (inativar, não apagar).
--
-- IDEMPOTENTE: se a linha (sigla + etiqueta) já existir, não insere de novo. Sigla ou etiqueta já usada por OUTRA linha
--   aborta (não sobrescreve cadastro de ninguém).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

-- 0. Guarda de premissa
do $g$
begin
  if to_regclass('mkt.projetos') is null then
    raise exception '20261007k: mkt.projetos não existe';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'mkt.projetos'::regclass and c.conname = 'projetos_sigla_check')
     is distinct from 'CHECK ((sigla ~ ''^[A-Z]{2,10}[0-9]{2,4}$''::text))' then
    raise exception '20261007k: projetos_sigla_check mudou. Releia pg_get_constraintdef.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007k: a sigla CNFMIAMI26 já existe com outra etiqueta. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12' and sigla <> 'CNFMIAMI26') then
    raise exception '20261007k: a etiqueta clinica-miami-2026-12 já está em outro projeto. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12') then
    raise notice '20261007k: projeto CNFMIAMI26 já cadastrado; nada a fazer.';
  end if;
end
$g$;

-- 1. Cadastro (só se ainda não existe)
insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, evento_inicio, evento_fim, obs)
select 'CNFMIAMI26', 'Clínica Internacional de Holding Familiar', 'Clínica de Holding Familiar', 2026,
       'clinica-miami-2026-12', date '2026-12-03', date '2026-12-04',
       'Clínica de Miami (03 e 04/12/2026), paga. Não confundir com o Encontro Internacional dos Diamantes (miami-2026-12, '
       || '01 e 02/12). Cadastrado pela migration 20261007k a pedido do Victor Hugo (07/10/2026). Fonte: '
       || 'gp-operacoes/projetos/calendario.md. A confirmar: linha, tipo, unidade e tipo de lançamento.'
 where not exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' or etiqueta_clickup = 'clinica-miami-2026-12');

-- 2. Pós-condição
do $c$
declare r record;
begin
  select count(*) as n, min(nome) as nome, min(inicio) as ini, max(fim) as fim into r
    from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12';
  if r.n <> 1 then raise exception '20261007k: esperava 1 linha CNFMIAMI26, achei %', r.n; end if;
  if r.ini is distinct from date '2026-12-03' or r.fim is distinct from date '2026-12-04' then
    raise exception '20261007k: período derivado % a %, esperado 2026-12-03 a 2026-12-04', r.ini, r.fim;
  end if;
  if to_regprocedure('crm.projeto_conhecido(text)') is not null and not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007k: clinica-miami-2026-12 não ficou conhecida';
  end if;
end
$c$;

-- REVERSÃO (numa transação; inativar, nunca apagar: pessoas.eventos/origens podem apontar para o id):
-- update mkt.projetos set ativo = false, atualizado_em = now() where sigla = 'CNFMIAMI26';

insert into pg_temp._z_out (passo, linha) select '2 depois1', jsonb_build_object(
  'i_ck_tem_pre_checkout', position('''pre_checkout''' in (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check')) > 0,
  'i_md5_registrar', (select md5(p.prosrc) from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure),
  'i_eventos', (select count(*) from pessoas.eventos),
  'i_pre_checkout', (select count(*) from pessoas.eventos where tipo = 'pre_checkout'),
  'j_regra_614', (select string_agg(r.id || ':' || r.projeto, ',') from crm.catalogo_regra r where r.ativo and r.campo = 'ac_lista' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')),
  'j_massa_regra_ou_utm', (select count(*) from crm.pessoa_origem po where po.projeto_regra_id = (select r.id from crm.catalogo_regra r where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null) or (po.projeto is null and not po.projeto_manual and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))),
  'j_contatos_miami', (select count(*) from crm.pessoa_origem where projeto = 'miami-2026-12'),
  'j_contatos_clinica', (select count(*) from crm.pessoa_origem where projeto = 'clinica-miami-2026-12'),
  'j_ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '') where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign' and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))),
  'j_negocios_em_funil_miami', (select count(*) from crm.negocio n join crm.funil f on f.id = n.funil_id where f.projeto = 'miami-2026-12'),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'k_projetos', (select count(*) from mkt.projetos),
  'k_linha', (select jsonb_build_object('sigla', sigla, 'nome', nome, 'linha', linha, 'ano', ano, 'inicio', inicio, 'fim', fim, 'tipo', tipo, 'unidade', unidade, 'subarea', subarea_trafego, 'tl', tipo_lancamento, 'ativo', ativo) from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12')
)::text;

-- ===== PASSADA 2: 20261007i =====
-- 20261007i: base de pessoas — evento 'pre_checkout' e rastro da captura (chave do evento, sck, xcod, página)
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
-- Aceite do Arthur dado em 07/10/2026 (o schema pessoas e pessoas.registrar são dele, 20261005r). Relatório: 20261007i.explain.md.
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

-- 0. Guarda de premissa. Aceita dois estados e nenhum outro:
--    a) antes da 20261007i: CHECK da 20261006043612 e corpo da 20261005r (md5 e082542b…) → aplica;
--    b) depois da 20261007i: CHECK com 'pre_checkout' e corpo desta migration (md5 8f77b9fc…) → "já aplicada": os passos
--       1 e 2 regravam exatamente o mesmo CHECK e o mesmo corpo (sem efeito) e a pós-condição confere. Assim um segundo
--       `db push` antes de renomear o arquivo não aborta a cadeia (revisão do Forja, 07/10/2026; manual §3).
do $guarda$
declare v_ck text; v_md5 text;
begin
  if to_regprocedure('pessoas.registrar(jsonb,text,uuid)') is null
     or to_regprocedure('public.pessoas_registrar_lead(jsonb)') is null then
    raise exception '20261007i: pessoas.registrar ou public.pessoas_registrar_lead ausente';
  end if;
  select pg_get_constraintdef(c.oid) into v_ck from pg_constraint c
   where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check';
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure;
  if v_ck is not distinct from
       'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text, ''checkout''::text, ''reembolso''::text, ''pre_checkout''::text])))'
     and v_md5 is not distinct from '8f77b9fc25b84d526be4c9ebad528c2e' then
    raise notice '20261007i: já aplicada (CHECK com pre_checkout e corpo 8f77b9fc…). Os passos seguintes não mudam nada.';
  elsif v_ck is distinct from
       'CHECK ((tipo = ANY (ARRAY[''lead''::text, ''mql''::text, ''nao_mql''::text, ''cadastro''::text, ''compra''::text, ''ativacao''::text, ''crm''::text, ''vinculo''::text, ''mescla''::text, ''mescla_desfeita''::text, ''revisao''::text, ''checkout''::text, ''reembolso''::text])))'
  then
    raise exception '20261007i: eventos_tipo_check diferente do esperado (20261006043612 ou pós-20261007i). Releia pg_get_constraintdef.';
  elsif v_md5 is distinct from 'e082542bde3f7abc431d562bb4e032e0' then
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

-- ===== PASSADA 2: 20261007j =====
-- 20261007j: Comercial, a regra da lista 614 do ActiveCampaign leva à CLÍNICA de Miami, não ao Encontro dos Diamantes.
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
-- Relatório: 20261007j.explain.md.
--
-- POR QUE
--   A 20261007141044_crm_catalogacao_origem (APLICADA) semeou em crm.catalogo_regra:
--     ('ac_lista', 'contem', 'Clínica Internacional Diamante Dez/26', 'miami-2026-12', 100, 'Lista 614 (confirmado 07/10)')
--   Decisão do Victor Hugo (07/10/2026): a lista 614 é da Clínica de Miami (chave clinica-miami-2026-12, 03 e 04/12),
--   não do Encontro Internacional dos Diamantes (miami-2026-12, 01 e 02/12). Migration aplicada não se edita: arquivo novo.
--
-- O QUE FAZ
--   1. Guarda: existe UMA regra ativa tipo 'projeto', campo 'ac_lista', operador 'contem', padrão "Clínica Internacional
--      Diamante Dez/26" (mesma expressão do índice único: lower(btrim(padrao))), sem janela de datas, com projeto
--      'miami-2026-12' (estado da 20261007141044) ou 'clinica-miami-2026-12' (já corrigida: roda de novo sem efeito).
--      Qualquer outro estado aborta. Aborta também se crm.origem_catalogar(uuid) não existir ou se a massa a recatalogar
--      passar de 1.000 contatos (~3 ms cada pelo explain da 20261007141044: acima disso, rodar em lotes).
--   2. Corrige a regra: projeto = 'clinica-miami-2026-12', nota com a origem da decisão, atualizado_em = now().
--      Padrão, operador, campo, tipo, datas e prioridade não mudam (o índice único catalogo_regra_uidx não é tocado; a
--      chave nova cabe no CHECK '^[a-z0-9][a-z0-9-]{1,79}$').
--   3. Recataloga com a função da própria 20261007141044 (crm.origem_catalogar, a mesma que crm_catalogo_reaplicar usa),
--      porque crm.pessoa_origem GUARDA o projeto copiado (coluna projeto + projeto_regra_id), não deriva na leitura:
--        a) quem tem projeto_regra_id = esta regra (veio por ela);
--        b) quem está sem projeto e tem utm_campaign = clinica-miami-2026-12 entre as chaves vistas: a chave passa a ser
--           "conhecida" (crm.projeto_conhecido lê crm.catalogo_regra.projeto) e o utm implícito passa a resolver.
--      Projeto definido à mão (projeto_manual) não muda: origem_catalogar já preserva.
--   NÃO cria o projeto em mkt.projetos (sigla pendente de confirmação), NÃO mexe em fin.produtos, NÃO mexe na Ativação.
--
-- QUEM LÊ (grep no repo, 07/10/2026): crm.catalogo_regra e crm.pessoa_origem só são lidas pelas funções da
--   20261007141044 (resolver, contatos_itens, crm_contatos_pagina/resumo, crm_catalogo, crm_contato_origem) e pela tela
--   do Comercial via RPC. Nenhum outro repo (disparos-thb, controle-de-eventos, gp-operacoes) lê essas tabelas.
--   A Ativação (20261007135415) chama crm.projeto_do_evento: daqui em diante, evento da lista 614 aponta para
--   clinica-miami-2026-12 (só entra se existir crm.projeto_ativacao com essa chave; sem ela, devolve 'projeto_fechado').
--   Entradas de Ativação já gravadas em miami-2026-12 vindas da lista 614 NÃO são movidas: a migration só conta e avisa
--   (raise notice); mover negócio é decisão do Victor/Arthur.
--
-- AS 5 PERGUNTAS
--   escala: 1 update de 1 linha + origem_catalogar por contato afetado (guarda de 1.000; esperado bem menos: lista de
--     pré-checkout de um evento). A busca do item b) varre crm.pessoa_origem uma vez (base de ~2.800 a 6.000 linhas).
--   índice: a) e b) não têm índice próprio (projeto_regra_id sem índice; chaves em jsonb). Seq scan único numa tabela de
--     milhares de linhas, uma vez. Não justifica índice novo.
--   frequência: uma vez.
--   repetição: nenhuma.
--   reversão: bloco REVERSÃO no fim (voltar o projeto da regra e recatalogar os mesmos contatos).

set local lock_timeout = '5s';

-- ─── 1. Guarda de premissa ────────────────────────────────────────────────────────────────────────────────────────
do $g$
declare v_n int; v_proj text; v_massa int;
begin
  if to_regclass('crm.catalogo_regra') is null or to_regclass('crm.pessoa_origem') is null then
    raise exception '20261007j: falta a 20261007141044 (crm.catalogo_regra / crm.pessoa_origem). Aplique antes.';
  end if;
  if to_regprocedure('crm.origem_catalogar(uuid)') is null then
    raise exception '20261007j: crm.origem_catalogar(uuid) não existe; a recatalogação depende dela (20261007141044).';
  end if;
  select count(*), min(r.projeto) into v_n, v_proj
    from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  if v_n <> 1 then
    raise exception '20261007j: esperava 1 regra ativa ac_lista contem "Clínica Internacional Diamante Dez/26", achei %. Releia crm.catalogo_regra.', v_n;
  end if;
  if v_proj is distinct from 'miami-2026-12' and v_proj is distinct from 'clinica-miami-2026-12' then
    raise exception '20261007j: a regra da lista 614 aponta para "%", nem miami-2026-12 nem clinica-miami-2026-12. Alguém mudou pela tela; conferir com o Victor.', coalesce(v_proj, '(sem projeto)');
  end if;
  select count(*) into v_massa
    from crm.pessoa_origem po
   where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                   and r.vale_de is null and r.vale_ate is null)
      or (po.projeto is null and not po.projeto_manual
          and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                       where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'));
  if v_massa > 1000 then
    raise exception '20261007j: % contatos a recatalogar (teto 1.000). Rodar em lotes antes de seguir.', v_massa;
  end if;
end
$g$;

-- ─── 2. Corrige a regra ───────────────────────────────────────────────────────────────────────────────────────────
update crm.catalogo_regra r
   set projeto = 'clinica-miami-2026-12',
       nota = 'Lista 614: Clínica de Miami, não o Encontro dos Diamantes (decisão do Victor Hugo, 07/10/2026; corrige a semente da 20261007141044)',
       atualizado_em = now()
 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
   and r.vale_de is null and r.vale_ate is null
   and r.projeto = 'miami-2026-12';

-- ─── 3. Recataloga quem a correção atinge (função da 20261007141044, não reimplementada) ─────────────────────────
do $r$
declare v uuid; v_id bigint; v_n int := 0; v_ativ int := 0;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  for v in
    select po.pessoa_id from crm.pessoa_origem po
     where po.projeto_regra_id = v_id
        or (po.projeto is null and not po.projeto_manual
            and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                         where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))
     order by po.pessoa_id
  loop
    perform crm.origem_catalogar(v);
    v_n := v_n + 1;
  end loop;
  raise notice '20261007j: % contatos recatalogados', v_n;

  -- Ativação: entradas já gravadas em miami-2026-12 vindas de lista que esta regra casa. Só conta (não move).
  if to_regclass('crm.ativacao_entrada') is not null then
    select count(*) into v_ativ
      from crm.ativacao_entrada ae
      join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
      left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
     where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
       and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista));
    if v_ativ > 0 then
      raise notice '20261007j: ATENÇÃO, % entradas de Ativação em miami-2026-12 vieram da lista da Clínica. Não foram movidas: levar ao Victor.', v_ativ;
    end if;
  end if;
end
$r$;

-- ─── 4. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v_id bigint; v_res record;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null and r.projeto = 'clinica-miami-2026-12';
  if v_id is null then raise exception '20261007j: a regra não ficou com clinica-miami-2026-12'; end if;
  if exists (select 1 from crm.pessoa_origem po where po.projeto_regra_id = v_id and po.projeto is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007j: há contato ligado à regra da lista 614 com projeto diferente de clinica-miami-2026-12';
  end if;
  if not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007j: clinica-miami-2026-12 não ficou conhecida (crm.projeto_conhecido)';
  end if;
  -- nome da lista 614 como semeado em crm.ac_lista pela 20261007141044
  select * into v_res from crm.catalogo_resolver(
    jsonb_build_object('ac_lista', '614', 'ac_lista_nome', 'Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout'));
  if v_res.r_projeto is distinct from 'clinica-miami-2026-12' or v_res.r_motivo is distinct from 'regra' then
    raise exception '20261007j: o resolver leva a lista 614 para "%" (motivo %), não para clinica-miami-2026-12', v_res.r_projeto, v_res.r_motivo;
  end if;
end
$c$;

-- ─── REVERSÃO (manual, numa transação) ────────────────────────────────────────────────────────────────────────────
-- 1. update crm.catalogo_regra set projeto = 'miami-2026-12', nota = 'Lista 614 (confirmado 07/10)', atualizado_em = now()
--     where ativo and tipo = 'projeto' and campo = 'ac_lista' and operador = 'contem'
--       and lower(btrim(padrao)) = lower('Clínica Internacional Diamante Dez/26') and vale_de is null and vale_ate is null;
-- 2. Recatalogar os mesmos contatos: perform crm.origem_catalogar(pessoa_id) para quem tem projeto_regra_id = id da regra
--    e para quem tem projeto = 'clinica-miami-2026-12' com projeto_motivo = 'utm'.

-- ===== PASSADA 2: 20261007k =====
-- 20261007k: cadastro do projeto da Clínica de Miami em mkt.projetos (sigla CNFMIAMI26, chave clinica-miami-2026-12)
--
-- STATUS: NÃO APLICADA. Ensaio RODADO em produção em 07/10/2026 (begin … rollback): sequência i → j → k 2× em
-- 20261007k_ensaio.sql, resultado em 20261007k.explain.md §5. Aplicar parou: acesso negado à sessão do agente.
--
-- POR QUE
--   A chave clinica-miami-2026-12 (gp-operacoes/projetos/calendario.md, decisão do Victor Hugo de 07/10/2026) já é usada
--   pela regra da lista 614 do ActiveCampaign (20261007j) e pela captura de pré-checkout (20261007i), mas não tem linha
--   em mkt.projetos: a tela mostra a chave crua e o Tráfego não tem o projeto. Sigla CNFMIAMI26 aprovada pelo Victor
--   Hugo em 07/10/2026 (cabe no CHECK projetos_sigla_check ^[A-Z]{2,10}[0-9]{2,4}$).
--
-- DE ONDE VEM CADA VALOR (nada inventado)
--   sigla             CNFMIAMI26                                   aprovada pelo Victor Hugo (07/10/2026)
--   etiqueta_clickup  clinica-miami-2026-12                        gp-operacoes/projetos/calendario.md, linha 14 do calendário
--   nome              Clínica Internacional de Holding Familiar    idem (string exata do calendário)
--   linha             Clínica de Holding Familiar                  gp-operacoes/produtos-e-ofertas/infoprodutos/esteira-de-produtos.md
--                                                                  (coluna obrigatória; a CONFIRMAR com o Victor)
--   ano               2026                                         chave e calendário (03 e 04/12/2026)
--   evento_inicio/fim 2026-12-03 / 2026-12-04                      calendário ("03 e 04/12", Miami)
--   inicio/fim        derivados pelo gatilho projetos_tipo_unidade a partir das datas do evento
--   tipo, unidade, tipo_lancamento, subarea_trafego, especialista, captação: NULOS (fonte não diz; a CONFIRMAR com o Victor).
--     subarea_trafego é derivada pelo gatilho a partir de tipo/unidade: com os dois nulos, fica nula.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha numa tabela de 4. índice: únicos de sigla e etiqueta já existem. frequência: uma vez.
--   repetição: nenhuma. reversão: bloco REVERSÃO no fim (inativar, não apagar).
--
-- IDEMPOTENTE: se a linha (sigla + etiqueta) já existir, não insere de novo. Sigla ou etiqueta já usada por OUTRA linha
--   aborta (não sobrescreve cadastro de ninguém).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

-- 0. Guarda de premissa
do $g$
begin
  if to_regclass('mkt.projetos') is null then
    raise exception '20261007k: mkt.projetos não existe';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'mkt.projetos'::regclass and c.conname = 'projetos_sigla_check')
     is distinct from 'CHECK ((sigla ~ ''^[A-Z]{2,10}[0-9]{2,4}$''::text))' then
    raise exception '20261007k: projetos_sigla_check mudou. Releia pg_get_constraintdef.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007k: a sigla CNFMIAMI26 já existe com outra etiqueta. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12' and sigla <> 'CNFMIAMI26') then
    raise exception '20261007k: a etiqueta clinica-miami-2026-12 já está em outro projeto. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12') then
    raise notice '20261007k: projeto CNFMIAMI26 já cadastrado; nada a fazer.';
  end if;
end
$g$;

-- 1. Cadastro (só se ainda não existe)
insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, evento_inicio, evento_fim, obs)
select 'CNFMIAMI26', 'Clínica Internacional de Holding Familiar', 'Clínica de Holding Familiar', 2026,
       'clinica-miami-2026-12', date '2026-12-03', date '2026-12-04',
       'Clínica de Miami (03 e 04/12/2026), paga. Não confundir com o Encontro Internacional dos Diamantes (miami-2026-12, '
       || '01 e 02/12). Cadastrado pela migration 20261007k a pedido do Victor Hugo (07/10/2026). Fonte: '
       || 'gp-operacoes/projetos/calendario.md. A confirmar: linha, tipo, unidade e tipo de lançamento.'
 where not exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' or etiqueta_clickup = 'clinica-miami-2026-12');

-- 2. Pós-condição
do $c$
declare r record;
begin
  select count(*) as n, min(nome) as nome, min(inicio) as ini, max(fim) as fim into r
    from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12';
  if r.n <> 1 then raise exception '20261007k: esperava 1 linha CNFMIAMI26, achei %', r.n; end if;
  if r.ini is distinct from date '2026-12-03' or r.fim is distinct from date '2026-12-04' then
    raise exception '20261007k: período derivado % a %, esperado 2026-12-03 a 2026-12-04', r.ini, r.fim;
  end if;
  if to_regprocedure('crm.projeto_conhecido(text)') is not null and not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007k: clinica-miami-2026-12 não ficou conhecida';
  end if;
end
$c$;

-- REVERSÃO (numa transação; inativar, nunca apagar: pessoas.eventos/origens podem apontar para o id):
-- update mkt.projetos set ativo = false, atualizado_em = now() where sigla = 'CNFMIAMI26';

insert into pg_temp._z_out (passo, linha) select '3 depois2', jsonb_build_object(
  'i_ck_tem_pre_checkout', position('''pre_checkout''' in (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'pessoas.eventos'::regclass and c.conname = 'eventos_tipo_check')) > 0,
  'i_md5_registrar', (select md5(p.prosrc) from pg_proc p where p.oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure),
  'i_eventos', (select count(*) from pessoas.eventos),
  'i_pre_checkout', (select count(*) from pessoas.eventos where tipo = 'pre_checkout'),
  'j_regra_614', (select string_agg(r.id || ':' || r.projeto, ',') from crm.catalogo_regra r where r.ativo and r.campo = 'ac_lista' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')),
  'j_massa_regra_ou_utm', (select count(*) from crm.pessoa_origem po where po.projeto_regra_id = (select r.id from crm.catalogo_regra r where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null) or (po.projeto is null and not po.projeto_manual and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))),
  'j_contatos_miami', (select count(*) from crm.pessoa_origem where projeto = 'miami-2026-12'),
  'j_contatos_clinica', (select count(*) from crm.pessoa_origem where projeto = 'clinica-miami-2026-12'),
  'j_ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '') where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign' and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))),
  'j_negocios_em_funil_miami', (select count(*) from crm.negocio n join crm.funil f on f.id = n.funil_id where f.projeto = 'miami-2026-12'),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'k_projetos', (select count(*) from mkt.projetos),
  'k_linha', (select jsonb_build_object('sigla', sigla, 'nome', nome, 'linha', linha, 'ano', ano, 'inicio', inicio, 'fim', fim, 'tipo', tipo, 'unidade', unidade, 'subarea', subarea_trafego, 'tl', tipo_lancamento, 'ativo', ativo) from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12')
)::text;

-- ===== CASOS da 20261007i (como service_role, igual à rota) =====

set local role service_role;
insert into pg_temp._z_out (passo, linha) select 'i.caso pre_checkout', (select jsonb_build_object('ok', r->'ok', 'msg', r->'msg', 'como', r->'como') from (select public.pessoas_registrar_lead(jsonb_build_object(
  'nome', 'Ensaio Captura', 'email', 'ensaio-20261007i-a@exemplo.invalid', 'telefone', '5521999990000',
  'evento', 'pre_checkout', 'chave_evento', 'clinica-miami-2026-12', 'sck', 'ensaio_sck', 'xcod', 'ensaio_xcod',
  'pagina', 'https://clinica.timeholdingbrasil.com.br/miami/?email=nao-pode-gravar#topo',
  'utm_source', 'ensaio', 'utm_campaign', 'clinica-miami-2026-12', 'teste', true)) r) s)::text;
insert into pg_temp._z_out (passo, linha) select 'i.caso lead_sem_evento', (select jsonb_build_object('ok', r->'ok', 'msg', r->'msg') from (select public.pessoas_registrar_lead(jsonb_build_object(
  'nome', 'Ensaio Captura B', 'email', 'ensaio-20261007i-b@exemplo.invalid', 'teste', true)) r) s)::text;
insert into pg_temp._z_out (passo, linha) select 'i.caso evento_invalido', (select jsonb_build_object('ok', r->'ok', 'msg', r->'msg') from (select public.pessoas_registrar_lead(jsonb_build_object(
  'nome', 'Ensaio Captura C', 'email', 'ensaio-20261007i-c@exemplo.invalid', 'evento', 'xpto', 'teste', true)) r) s)::text;
insert into pg_temp._z_out (passo, linha) select 'i.caso chave_invalida', (select jsonb_build_object('ok', r->'ok', 'msg', r->'msg') from (select public.pessoas_registrar_lead(jsonb_build_object(
  'nome', 'Ensaio Captura D', 'email', 'ensaio-20261007i-d@exemplo.invalid', 'evento', 'pre_checkout',
  'chave_evento', 'Clinica Miami!', 'teste', true)) r) s)::text;
reset role;
insert into pg_temp._z_out (passo, linha) select 'i.eventos do ensaio', coalesce(jsonb_agg(jsonb_build_object('caso', right(split_part(i.chave, '@', 1), 1), 'tipo', e.tipo, 'fonte', e.fonte, 'projeto_id', e.projeto_id, 'detalhe', e.detalhe) order by i.chave), '[]')::text
  from pessoas.identificadores i join pessoas.eventos e on e.pessoa_id = i.pessoa_id
 where i.tipo = 'email' and i.chave like 'ensaio-20261007i-%@exemplo.invalid';
insert into pg_temp._z_out (passo, linha) select 'i.acl', jsonb_agg(jsonb_build_object(p.oid::regprocedure::text, p.proacl::text) order by p.proname)::text
  from pg_proc p where p.oid in (to_regprocedure('pessoas.registrar(jsonb,text,uuid)'), to_regprocedure('public.pessoas_registrar_lead(jsonb)'));

-- ===== EXPLAIN (analyze, buffers), 2x cada =====

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select public.pessoas_registrar_lead(jsonb_build_object(''email'', ''ensaio-20261007i-x1@exemplo.invalid'', ''evento'', ''pre_checkout'', ''chave_evento'', ''clinica-miami-2026-12'', ''teste'', true))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.i rpc 1', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select public.pessoas_registrar_lead(jsonb_build_object(''email'', ''ensaio-20261007i-x2@exemplo.invalid'', ''evento'', ''pre_checkout'', ''chave_evento'', ''clinica-miami-2026-12'', ''teste'', true))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.i rpc 2', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select po.pessoa_id from crm.pessoa_origem po where po.projeto_regra_id = 42 or (po.projeto is null and not po.projeto_manual and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> ''chaves'', ''[]''::jsonb)) k where k ->> ''campo'' = ''utm_campaign'' and lower(btrim(k ->> ''valor'')) = ''clinica-miami-2026-12''))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.j busca 1', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select po.pessoa_id from crm.pessoa_origem po where po.projeto_regra_id = 42 or (po.projeto is null and not po.projeto_manual and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> ''chaves'', ''[]''::jsonb)) k where k ->> ''campo'' = ''utm_campaign'' and lower(btrim(k ->> ''valor'')) = ''clinica-miami-2026-12''))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.j busca 2', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select crm.origem_catalogar((select pessoa_id from crm.pessoa_origem order by pessoa_id limit 1))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.j catalogar 1', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select crm.origem_catalogar((select pessoa_id from crm.pessoa_origem order by pessoa_id limit 1))' loop
    insert into pg_temp._z_out (passo, linha) values ('x.j catalogar 2', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select crm.projeto_conhecido(''clinica-miami-2026-12'')' loop
    insert into pg_temp._z_out (passo, linha) values ('x.k conhecido 1', l);
  end loop;
end $x$;

do $x$ declare l text; begin
  for l in execute 'explain (analyze, buffers) select crm.projeto_conhecido(''clinica-miami-2026-12'')' loop
    insert into pg_temp._z_out (passo, linha) values ('x.k conhecido 2', l);
  end loop;
end $x$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
