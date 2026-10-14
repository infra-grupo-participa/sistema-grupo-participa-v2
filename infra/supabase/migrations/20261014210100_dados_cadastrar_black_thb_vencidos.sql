-- 20261014210100: cadastro da primeira ação do dashboard "Ações da Black Friday": THB com acesso vencido
-- (etiqueta black-thb-2026-10). Depende da 20261014210000.
--
-- STATUS: NÃO APLICADA. TRAVADA DE PROPÓSITO até alguém preencher a SIGLA (v_sigla abaixo). A sigla é decisão do Victor
-- (dono do padrão de nomenclatura), como foi a ATMEL126 do ATM, e tem de casar com '^[A-Z]{2,10}[0-9]{2,4}$'.
-- Ensaio: 20261014210000_ensaio.sql (com sigla fictícia só dentro da transação).
--
-- O QUE CADASTRA (cada valor com a fonte)
--   mkt.projetos ......... etiqueta black-thb-2026-10 (card 17tya50gmcm e PEDIDO); nome "Black do THB com acesso vencido"
--                          (nome da planilha de público citada na planilha de mensageria); linha 'Black Friday', tipo
--                          interno, unidade csm (iguais ao BF26, projeto 4); evento 16/10/2026 (reunião no Zoom).
--   dados.dashboards ..... modelo acao-black; conta academy (o Holding Masters vende na conta academy em
--                          fin.hotmart_transacoes); oferta_codigo NULO (a oferta ainda não existe; o Victor passa e entra
--                          por update de 1 linha); lista_ac NULA (pré-checkout); periodo_inicio 14/10/2026 (começo da
--                          captação pela /renovacao); vendas_desde 14/10/2026 00:00 de São Paulo.
--   dados.sessoes ........ live 16/10/2026 14:00 de São Paulo (Reunião Direto ao Ponto).
--   dados.dashboard_grupos campanha "Reunião Direto ao Ponto | 16/10 às 14h no Zoom" (R89eeAMF6pccfKbE9RYR), papel
--                          dashboard, SEM conta de export e sem foto_ate: o ingresso conta só o que chega pelo SendHook
--                          (decisão do Victor, 14/10). O papel dashboard também faz o disparo de grupo do SendFlow desta
--                          campanha herdar o projeto (20261014150000).
--   mkt_mensageria.planilhas  [BF26 THB VENCIDOS] MENSAGERIA, DESLIGADA (ativa = false): ligar é uma rotina lendo o
--                          Google Sheets a cada 10 min, só com ok do Victor. Abas API, E-MAIL, GRUPO DA REUNIÃO e LIGAÇÃO,
--                          com "ano" 2026 (a planilha escreve a data sem ano) e "hora_faixa" na LIGAÇÃO. Ferramentas pelo
--                          precedente do ATM: API = Infobip (8), LIGAÇÃO = Ligue Lead (10); E-MAIL = ActiveCampaign (3);
--                          GRUPO = SendFlow (1). A coluna TIPO desta planilha é DISPARO/AUTOMAÇÃO (não o tipo de template
--                          da API), então não entra no mapa; fica só na conferência do
--                          cabeçalho. Na API, o tipo vem da coluna CATEGORIA META (J), que tem de trazer utility ou marketing. Fora: GRUPOS THB (é lista de grupos, não registro de disparo) e SMS (não
--                          há aba de registro; só o link na aba LINKS).
--
-- PARA VOLTAR: 20261014210100_reversao.sql.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $c$
declare
  v_sigla   text := null;   -- PREENCHER com a sigla aprovada pelo Victor
  v_chave   text := 'black-thb-2026-10';
  v_proj    bigint;
  v_cab     jsonb := '{"B": "DATA", "C": "HORÁRIO", "D": "NOME DA MENSAGEM", "F": "LISTA/SEGMENTO", "G": "LINK", "H": "COPY (link do doc)"}';
begin
  if v_sigla is null then
    raise exception '20261014210100: sigla do projeto não definida. Preencher v_sigla com a sigla aprovada pelo Victor.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261014210100: sigla % fora do padrão de mkt.projetos', v_sigla;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'dashboards_modelo_check'
                  and pg_get_constraintdef(oid) like '%acao-black%') then
    raise exception '20261014210100: aplicar antes a 20261014210000';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_chave) then
    raise exception '20261014210100: a sigla % já existe com outra etiqueta', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave and sigla <> v_sigla) then
    raise exception '20261014210100: % já cadastrada com outra sigla', v_chave;
  end if;
  if exists (select 1 from mkt_mensageria.planilhas where planilha_id = '1J5QFTBEALI1TiqQ6FiAcbEtgTRB0OxhXo75zyAI9R2Q') then
    raise exception '20261014210100: a planilha de mensageria já está cadastrada; revisar';
  end if;

  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, evento_inicio, evento_fim, obs)
  select v_sigla, 'Black do THB com acesso vencido', 'Black Friday', 2026, v_chave, 'interno', 'csm',
         date '2026-10-16', date '2026-10-16',
         'Ação da Black Friday para o THB com acesso vencido; Reunião Direto ao Ponto 16/10 14h. Card 17tya50gmcm. 20261014210100.'
   where not exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave);
  select id into v_proj from mkt.projetos where etiqueta_clickup = v_chave;

  insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads,
                                periodo_inicio, vendas_desde)
  values (v_chave, 'acao-black', v_proj, 'academy', null, null, null,
          date '2026-10-14', timestamptz '2026-10-14 00:00:00-03')
  on conflict (chave) do nothing;

  insert into dados.sessoes (chave, tipo, inicio)
  values (v_chave, 'live', timestamptz '2026-10-16 14:00:00-03')
  on conflict (chave, tipo, inicio) do nothing;

  insert into dados.dashboard_grupos (chave, sendflow_campanha, sendflow_release_id, papel)
  values (v_chave, 'Reunião Direto ao Ponto | 16/10 às 14h no Zoom', 'R89eeAMF6pccfKbE9RYR', 'dashboard')
  on conflict (chave, sendflow_campanha) do nothing;

  insert into mkt_mensageria.planilhas (planilha_id, nome, projeto_id, desde, abas, ativa)
  values ('1J5QFTBEALI1TiqQ6FiAcbEtgTRB0OxhXo75zyAI9R2Q', '[BF26 THB VENCIDOS] MENSAGERIA', v_proj, date '2026-10-14',
    jsonb_build_array(
      jsonb_build_object('aba', 'API', 'canal', 'whatsapp_api', 'ferramenta_id', 8, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "N",
                     "tamanho_lista": "O", "entregues": "P", "lidas": "R", "cliques": "T", "falhas": "V",
                     "tipo": "J", "custo": "Y"}'::jsonb,
        'cabecalho', v_cab || '{"J": "CATEGORIA META", "N": "STATUS", "O": "ENVIADOS", "P": "ENTREGUES", "R": "ABERTOS/LIDAS", "T": "CLIQUES",
                                "V": "FALHAS", "X": "TIPO (DISPARO ou AUTOMAÇÃO)", "Y": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'E-MAIL', 'canal', 'email', 'ferramenta_id', 3, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "lidas": "P", "cliques": "R", "falhas": "T",
                     "custo": "W"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "ENVIADOS", "N": "ENTREGUES", "P": "ABERTOS/LIDAS", "R": "CLIQUES",
                                "T": "FALHAS", "V": "TIPO (DISPARO ou AUTOMAÇÃO)", "W": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'GRUPO DA REUNIÃO', 'canal', 'grupo', 'ferramenta_id', 1, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "lidas": "P", "cliques": "R", "falhas": "T",
                     "custo": "W"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "ENVIADOS", "N": "ENTREGUES", "P": "ABERTOS/LIDAS", "R": "CLIQUES",
                                "T": "FALHAS", "V": "TIPO (DISPARO ou AUTOMAÇÃO)", "W": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'LIGAÇÃO', 'canal', 'ligacao', 'ferramenta_id', 10, 'cabecalho_linha', 1, 'ano', 2026,
        'hora_faixa', true,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "custo": "S"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "QTD LIGAÇÕES", "N": "ATENDIDOS", "S": "CUSTO (R$)"}'::jsonb)
    ), false);
end
$c$;
