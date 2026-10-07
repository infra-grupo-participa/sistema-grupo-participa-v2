-- Ensaio de 20261007123627_crm_projeto_atm (ex-20261007d) — tudo numa transação que termina em ROLLBACK. Nada persiste.
-- JWT real: gestor do CRM 81d2eaee… (crm.eh_gestor() = true) e vendedor db6e59ea… (não gestor).
-- Esperado (tabela _r no fim):
--   base                   modelo_funil 10, modelo_projeto 6
--   modelos.depois         12 / 7; tipo atm → {atm_ativacao, atm_fechamento}
--   quem                   gestor eh_gestor true; vendedor eh_gestor false
--   criar.ht / criar.sv    ok true, 2 funilIds, msg "2 funis criados para …"
--   funis.ht / funis.sv    "<nome> · Ativação comercial (pré-checkout)" manual, 7 etapas (Lista recebida … Fechado na live),
--                          3 campanhas com a chave (API do caso, Base antiga, Grupo); "<nome> · Fechamento da live" hotmart,
--                          eventos {carrinho_abandonado,cartao_recusado,compra_em_aberto}, 5 etapas, 1 campanha hotmart com a chave;
--                          linha = ht / sv, projeto = chave
--   criar.repetido         ok false, "Já existe projeto com esse nome."
--   criar.vendedor         ok false, "Só o gestor cria projetos."
--   anon                   execute em crm_criar_projeto = false
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _r (k text, v jsonb) on commit drop;
grant all on _r to authenticated;
insert into _r select 'base', jsonb_build_object('modelo_funil', (select count(*) from crm.modelo_funil), 'modelo_projeto', (select count(*) from crm.modelo_projeto),
  'funil', (select count(*) from crm.funil), 'etapa', (select count(*) from crm.etapa_funil), 'campanha', (select count(*) from crm.campanha));

-- MIGRATION (conteúdo idêntico ao arquivo)
-- 20261007d_crm_projeto_atm — novo tipo de projeto "ATM (aula ao vivo de entrada)" no "Comecei um novo projeto" do CRM.
-- Pedido do Arthur em 07/10/2026. Fonte do playbook: gp-operacoes (glossario.md; projetos/2026-09-seminario-atm/
-- concepcao.md, oferta-do-fechamento.md, debriefing.md; decisoes/2026-09-09-cadencia-de-atm-e-seminario-a-cada-15-dias.md).
--
-- ATM = uma live só, sobre a base que já existe, sem captação paga; fechamento na própria live (condição especial até
-- 23h59 do mesmo dia). Serve a mais de um produto (ATM do HT, linha ht; Seminário ATM da Dra. Elaine, linha sv): o produto
-- é o p_linha que o gestor escolhe, como nos outros tipos.
--
-- Só DADO: +2 linhas em crm.modelo_funil (atm_ativacao, atm_fechamento) e +1 em crm.modelo_projeto (atm), geradas de
-- web/modules/comercial/domain/modelos.ts (mesmo formato camelCase da F1, 20261005s). Nenhum CHECK muda:
-- modelo_projeto.tipo aceita ^[a-z_]{3,40}$ e crm_criar_projeto lê o tipo da tabela (não há lista fixa de tipos no banco).
-- crm_criar_projeto NÃO é tocada. Não toca crm.hotmart_processar.
-- Reversão: delete das 3 linhas (funil criado não tem FK para modelo).

-- Guarda de premissa: modelos exatamente como lidos em 07/10/2026 e a RPC que os consome sem mudança.
do $g$
begin
  if (select count(*) from crm.modelo_funil) <> 10 or (select count(*) from crm.modelo_projeto) <> 6 then
    raise exception 'premissa: esperava 10 modelos de funil e 6 de projeto';
  end if;
  if exists (select 1 from crm.modelo_funil where id in ('atm_ativacao', 'atm_fechamento'))
     or exists (select 1 from crm.modelo_projeto where tipo = 'atm') then
    raise exception 'premissa: ATM já existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.crm_criar_projeto(text,text,uuid,text)'::regprocedure)
     <> '4528661f7ca9eb6d4d2a969ae63e4a10' then
    raise exception 'premissa: crm_criar_projeto mudou';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'modelo_projeto_tipo_check'
        and conrelid = 'crm.modelo_projeto'::regclass) <> 'CHECK ((tipo ~ ''^[a-z_]{3,40}$''::text))' then
    raise exception 'premissa: CHECK de modelo_projeto.tipo mudou';
  end if;
end
$g$;

insert into crm.modelo_funil (id, nome, descricao, icone, tipo, eventos_hotmart, etapas, campanhas, ordem) values
  ('atm_ativacao', 'Ativação comercial (pré-checkout)', 'Régua de pré-checkout do ATM: quem foi ao checkout em eventos anteriores e não comprou recebe a API do caso; o comercial liga (recebeu? assistiu?) e convida para a live.', 'phone', 'manual', array[]::text[], '[{"nome":"Lista recebida","papel":"primeiro_contato","cor":"neutral","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Ligação feita: recebeu a API do caso?","camposObrigatorios":[]},{"nome":"Contato feito","papel":"qualificar","cor":"info","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Recebeu e assistiu ao caso; convite para a live feito","camposObrigatorios":["perfil_profissional","atua_com_holding","produto_interesse"]},{"nome":"Convidado para a live","papel":"qualificar","cor":"cyan","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Confirmou que vai à live","camposObrigatorios":[]},{"nome":"Presença confirmada","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Esteve na live e ouviu a oferta","camposObrigatorios":[]},{"nome":"Ofertado no fechamento","papel":"negociar","cor":"accent","slaAtencaoMin":120,"slaCriticoMin":360,"criterio":"Escolheu a forma de pagamento até 23h59 do dia da live","camposObrigatorios":[]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Fechado na live","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"API do caso {chave}","canal":"disparo","regra":"Pré-checkout de {chave}: foi ao checkout em eventos anteriores, não comprou e recebeu a API com o estudo de caso","ativa":true},{"nome":"Base antiga {chave}","canal":"disparo","regra":"Reativação da base antiga (e-mail e grupos antigos) para a live de {chave}, sem quem reagiu ao último ATM","ativa":true},{"nome":"Grupo {chave}","canal":"formulario","regra":"Inscrito no formulário de {chave} que entrou no grupo de WhatsApp da live","ativa":true}]'::jsonb, 11),
  ('atm_fechamento', 'Fechamento da live', 'Nasce sozinho da Hotmart: checkout da oferta da live. A condição especial vale até 23h59 do mesmo dia, então a ligação é na hora.', 'hourglass', 'hotmart', array['carrinho_abandonado','cartao_recusado','compra_em_aberto']::text[], '[{"nome":"Ligar agora (vale até 23h59)","papel":"primeiro_contato","cor":"red","slaAtencaoMin":5,"slaCriticoMin":15,"criterio":"Atendeu ou respondeu","camposObrigatorios":[]},{"nome":"Em conversa","papel":"qualificar","cor":"cyan","slaAtencaoMin":30,"slaCriticoMin":120,"criterio":"Entendeu o que travou","camposObrigatorios":[]},{"nome":"Link da condição enviado","papel":"negociar","cor":"accent","slaAtencaoMin":60,"slaCriticoMin":180,"criterio":"Escolheu a forma de pagamento antes das 23h59","camposObrigatorios":[]},{"nome":"Aguardar pagamento","papel":"aguardar_pagamento","cor":"yellow","slaAtencaoMin":720,"slaCriticoMin":1440,"criterio":"Pagamento aprovado","camposObrigatorios":["forma_pagamento"]},{"nome":"Recuperado","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Oferta da live {chave}","canal":"hotmart","regra":"Checkout da oferta da live de {chave}: condição especial com escassez até 23h59 do dia da live","ativa":true}]'::jsonb, 12);

insert into crm.modelo_projeto (tipo, nome, descricao, icone, funis, checklist, ordem) values
  ('atm', 'ATM (aula ao vivo de entrada)', 'Uma live sobre a base que já existe, sem captação paga; fechamento na própria live.', 'mic', array['atm_ativacao','atm_fechamento']::text[], array['Replay e treplay são internos: não divulgar o replay para a base','Excluir da lista quem reagiu ao último ATM','Não colidir com o Seminário: ATM e Seminário a cada 15 dias, alternando semana a semana','Ligações do comercial para a lista de pré-checkout a partir de D-5','Oferta, condição especial e escassez (até 23h59 do dia) prontas antes da live','Teto de 30 a 50 conversas novas por dia por número na Meta']::text[], 7);

-- Pós-condição: payload que crm_criar_projeto vai copiar passa nas regras de etapa (uma de ganho, a última; SLA em par).
do $p$
declare m record;
begin
  if (select count(*) from crm.modelo_funil) <> 12 or (select count(*) from crm.modelo_projeto) <> 7 then
    raise exception 'pós: contagem errada';
  end if;
  for m in select id, etapas from crm.modelo_funil where id in ('atm_ativacao', 'atm_fechamento') loop
    if (select count(*) from crm.etapas_payload(m.etapas) e where e.papel = 'fechado') <> 1
       or (select e.papel from crm.etapas_payload(m.etapas) e order by e.ord desc limit 1) <> 'fechado'
       or exists (select 1 from crm.etapas_payload(m.etapas) e
                   where e.papel not in ('primeiro_contato','qualificar','apresentar_oferta','negociar','aguardar_pagamento','fechado')
                      or (e.sla_a is null) <> (e.sla_c is null) or e.sla_c <= e.sla_a) then
      raise exception 'pós: etapas inválidas em %', m.id;
    end if;
  end loop;
end
$p$;
-- FIM DA MIGRATION

insert into _r select 'modelos.depois', jsonb_build_object('modelo_funil', (select count(*) from crm.modelo_funil), 'modelo_projeto', (select count(*) from crm.modelo_projeto),
  'atm', (select to_jsonb(funis) from crm.modelo_projeto where tipo = 'atm'));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('quem.gestor', to_jsonb(crm.eh_gestor()));
insert into _r values ('criar.ht', public.crm_criar_projeto('atm', 'ENSAIO ATM HT 20261007d', 'b6c39c9f-01d3-4092-8c1a-ce04da73e2d0', 'ht'));
insert into _r values ('criar.sv', public.crm_criar_projeto('atm', 'ENSAIO Seminario ATM 20261007d', 'e429660b-25ba-4c95-b837-ea0fbd8b36fc', 'sv'));
insert into _r values ('criar.repetido', public.crm_criar_projeto('atm', 'ENSAIO ATM HT 20261007d', 'b6c39c9f-01d3-4092-8c1a-ce04da73e2d0', 'ht'));
reset role;
select set_config('request.jwt.claims', '{"sub":"db6e59ea-bb47-4d92-a169-a08ee4c30260","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('quem.vendedor', to_jsonb(crm.eh_gestor()));
insert into _r values ('criar.vendedor', public.crm_criar_projeto('atm', 'ENSAIO ATM vend 20261007d', 'b6c39c9f-01d3-4092-8c1a-ce04da73e2d0', 'ht'));
reset role;

insert into _r select 'funis.' || f.linha, jsonb_agg(jsonb_build_object('nome', f.nome, 'tipo', f.tipo, 'linha', f.linha, 'projeto', f.projeto,
    'icone', f.icone, 'eventos', f.eventos_hotmart,
    'etapas', (select jsonb_agg(e.nome || ' [' || e.papel || ']' order by e.ordem) from crm.etapa_funil e where e.funil_id = f.id),
    'campanhas', (select jsonb_agg(c.canal || ': ' || c.nome || ' | ' || c.regra order by c.criado_em, c.nome) from crm.campanha c where c.funil_id = f.id))
    order by f.criado_em, f.nome)
  from crm.funil f where f.nome like 'ENSAIO % 20261007d%' group by f.linha;
insert into _r values ('anon', to_jsonb(has_function_privilege('anon', 'public.crm_criar_projeto(text,text,uuid,text)', 'execute')));
-- O MCP não devolve o SELECT de uma transação desfeita: o resultado sai na mensagem do erro, que também desfaz tudo.
do $fim$ begin raise exception 'RESULTADO %', (select jsonb_object_agg(k, v) from _r); end $fim$;
rollback;
