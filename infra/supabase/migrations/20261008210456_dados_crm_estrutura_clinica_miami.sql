-- 20261008210456 (escrita como 20261008z02): Comercial, estrutura da Clínica Internacional Diamante (Miami): agrupador, 2 funis, distribuição própria
-- e vínculo da oferta sju5pawn. Tudo pelas RPCs oficiais com o JWT do Arthur (arthur@advmais.com), para o Registro
-- (crm.log) mostrar o autor. Depende da 20261008z01 (linha clinica_miami, crm.oferta_linha, crm_vincular_oferta).
--
-- STATUS: APLICADA em produção em 08/10/2026, versão 20261008210456 (nome dados_crm_estrutura_clinica_miami, era 20261008z02)
--   via apply_migration. SQL aplicado = este arquivo com o cabeçalho encurtado (corpo idêntico); md5 gravado =
--   6a0a2f02d62370349e36954f68a9223f. Agrupador 5d08a797-59af-4dff-80d0-41a1c54a79d0; funil a
--   19c7f316-0d66-49f1-bf46-db5f75521c32; funil b a6247a03-5144-4add-9ebc-fac9aceef97c.
--
-- O QUE CRIA
--   agrupador "Clínica Internacional Diamante" (linha clinica_miami)            → public.crm_criar_agrupador
--   funil a) "Venda ativa · Clínica Miami" (manual, ícone gem)                   → public.crm_salvar_funil
--   funil b) "Checkout e recuperação · Clínica Miami" (hotmart, ícone zap)       → public.crm_salvar_funil
--     os dois: projeto clinica-miami-2026-12, distribuição própria Jonathan Mendes 50% + Marcos Paulo 50%
--   vínculo sju5pawn → clinica_miami / agrupador novo                             → public.crm_vincular_oferta
--   "Apresentar a oferta" usa o papel apresentar_oferta (existe no CHECK etapa_funil_papel_check).
--   Etapas do funil b = cópia das etapas ativas de "Checkout e recuperação · HT" (nomes, papéis, cores, SLAs,
--   campos obrigatórios e critérios), lidas em 08/10/2026.
--
-- NÃO FAZ: não importa lead; não cria campanha; não mexe na distribuição geral (funil_id null).
-- REVERSÃO: crm_arquivar_funil nos 2 funis; crm_vincular_oferta com ativo=false (ou update crm.oferta_linha set ativo=false).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if not exists (select 1 from crm.linha where chave = 'clinica_miami') or to_regclass('crm.oferta_linha') is null then
    raise exception '20261008z02: falta a 20261008z01';
  end if;
  if exists (select 1 from crm.agrupador where lower(btrim(nome)) = lower('Clínica Internacional Diamante') and arquivado_em is null) then
    raise exception '20261008z02: agrupador já existe';
  end if;
  if exists (select 1 from crm.funil where projeto = 'clinica-miami-2026-12' and ativo) then
    raise exception '20261008z02: já há funil ativo do projeto clinica-miami-2026-12';
  end if;
  if not (crm.vendedor_ativo('bd5361bc-3c3f-4f85-8b5a-f21433d040e3') and crm.vendedor_ativo('9d347183-5395-434e-9e96-2a65dde1a3cd')) then
    raise exception '20261008z02: Jonathan ou Marcos não passa em crm.vendedor_ativo';
  end if;
  if (select id from public.perfis where email = 'arthur@advmais.com') is distinct from '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid
     or (select id from public.perfis where email = 'jonathan@advmais.com') is distinct from 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3'::uuid
     or (select id from public.perfis where email = 'marcospaulo@advmais.com') is distinct from '9d347183-5395-434e-9e96-2a65dde1a3cd'::uuid then
    raise exception '20261008z02: ids de perfis não batem com os e-mails';
  end if;
end $g$;

select set_config('request.jwt.claims',
  '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated","email":"arthur@advmais.com"}', true);
set local role authenticated;

do $d$
declare r jsonb; v_ag uuid; v_fa uuid; v_fb uuid;
        v_dist jsonb := '[{"vendedorId":"bd5361bc-3c3f-4f85-8b5a-f21433d040e3","percentual":50},
                          {"vendedorId":"9d347183-5395-434e-9e96-2a65dde1a3cd","percentual":50}]';
begin
  r := public.crm_criar_agrupador('Clínica Internacional Diamante', 'clinica_miami');
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'agrupador: %', r; end if;
  v_ag := (r -> 'dados' ->> 'agrupadorId')::uuid;
  if v_ag is null then v_ag := (r ->> 'agrupadorId')::uuid; end if;

  r := public.crm_salvar_funil(jsonb_build_object(
    'nome', 'Venda ativa · Clínica Miami', 'icone', 'gem', 'projeto', 'clinica-miami-2026-12', 'agrupadorId', v_ag,
    'produto', 'clinica_miami', 'tipo', 'manual', 'eventosHotmart', '[]'::jsonb, 'distribuicao', v_dist,
    'etapas', '[
      {"nome":"Fazer primeiro contato","papel":"primeiro_contato","cor":"red","slaAtencaoMin":5,"slaCriticoMin":15,"criterio":"O lead respondeu"},
      {"nome":"Qualificar","papel":"qualificar","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Tags de Miami preenchidas: passaporte, visto, passagem, plano de viagem e turma"},
      {"nome":"Apresentar a oferta","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":2880,"slaCriticoMin":4320,"criterio":"Oferta apresentada e o lead pediu condição ou link"},
      {"nome":"Negociar","papel":"negociar","cor":"accent","slaAtencaoMin":4320,"slaCriticoMin":10080,"criterio":"Lead escolheu a forma de pagamento"},
      {"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"camposObrigatorios":["forma_pagamento"],"criterio":"Pagamento aprovado na Hotmart"},
      {"nome":"Fechado","papel":"fechado","cor":"green","criterio":"Ganho só com pagamento aprovado"}]'::jsonb));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'funil a: %', r; end if;
  v_fa := coalesce(r -> 'dados' ->> 'funilId', r ->> 'funilId')::uuid;

  r := public.crm_salvar_funil(jsonb_build_object(
    'nome', 'Checkout e recuperação · Clínica Miami', 'icone', 'zap', 'projeto', 'clinica-miami-2026-12', 'agrupadorId', v_ag,
    'produto', 'clinica_miami', 'tipo', 'hotmart',
    'eventosHotmart', '["carrinho_abandonado","cartao_recusado","compra_em_aberto","expirada","compra_aprovada"]'::jsonb,
    'distribuicao', v_dist,
    'etapas', '[
      {"nome":"Ligar em até 15 min","papel":"primeiro_contato","cor":"red","slaAtencaoMin":10,"slaCriticoMin":15,"criterio":"Atendeu ou respondeu"},
      {"nome":"Em conversa","papel":"qualificar","cor":"cyan","slaAtencaoMin":240,"slaCriticoMin":1440,"criterio":"Entendeu o que travou"},
      {"nome":"Link novo enviado","papel":"negociar","cor":"accent","slaAtencaoMin":720,"slaCriticoMin":2880,"criterio":"Escolheu a forma de pagamento"},
      {"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"camposObrigatorios":["forma_pagamento"],"criterio":"Pagamento aprovado"},
      {"nome":"Recuperado","papel":"fechado","cor":"green","criterio":""}]'::jsonb));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'funil b: %', r; end if;
  v_fb := coalesce(r -> 'dados' ->> 'funilId', r ->> 'funilId')::uuid;

  r := public.crm_vincular_oferta(jsonb_build_object('ofertaCodigo', 'sju5pawn', 'produtoKey', 'clinica_miami', 'agrupadorId', v_ag,
                                                     'nomeComercial', 'Clínica Internacional Diamante · pré-venda (R$ 5.014,20)'));
  if not coalesce((r ->> 'ok')::boolean, false) then raise exception 'oferta: %', r; end if;

  perform set_config('miami.ag', v_ag::text, true);
  perform set_config('miami.fa', v_fa::text, true);
  perform set_config('miami.fb', v_fb::text, true);
end $d$;

reset role;

-- a soma da distribuição (constraint trigger DEFERRED) é conferida agora, não só no commit
set constraints all immediate;

do $c$
declare v_fa uuid := current_setting('miami.fa')::uuid; v_fb uuid := current_setting('miami.fb')::uuid; v_ag uuid := current_setting('miami.ag')::uuid;
begin
  if v_fa is null or v_fb is null or v_ag is null then raise exception 'ids não capturados'; end if;
  if (select count(*) from crm.etapa_funil where funil_id = v_fa and arquivada_em is null) <> 6 then raise exception 'funil a sem 6 etapas'; end if;
  if (select count(*) from crm.etapa_funil where funil_id = v_fb and arquivada_em is null) <> 5 then raise exception 'funil b sem 5 etapas'; end if;
  if (select count(*) from crm.distribuicao where funil_id in (v_fa, v_fb) and ativo and percentual = 50) <> 4 then
    raise exception 'distribuição própria incompleta';
  end if;
  if not exists (select 1 from crm.funil where id in (v_fa, v_fb) and distribuicao_propria and criado_por = '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'
                 having count(*) = 2) then
    raise exception 'funis sem distribuição própria ou sem autor';
  end if;
  if not exists (select 1 from crm.oferta_linha where oferta_codigo = 'sju5pawn' and linha = 'clinica_miami' and agrupador_id = v_ag and ativo) then
    raise exception 'vínculo sju5pawn não gravado';
  end if;
  raise notice '20261008z02: agrupador % · funil a % · funil b %', v_ag, v_fa, v_fb;
end $c$;
