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
