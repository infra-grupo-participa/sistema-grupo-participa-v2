# Dashboard Seminário ATM

## Escopo

Dashboard padronizado para ATMs em Infra > Dashboards > Escritório > Seminário ATM. A primeira edição registrada é **atm-elaine-1-2026-10**, live de 13/10 às 19h30. O caminho da tela é **/infra/dashboards/escritorio/atm/atm-elaine-1-2026-10**.

O registro em **web/modules/infra/atm/domain/registro.ts** fornece a chave, o rótulo e a data da edição. Para o próximo ATM, cadastre uma nova chave confirmada nesse registro e no banco, sem duplicar a tela nem criar valores específicos da edição no componente.

## Visão e fontes

Os cards aparecem na ordem do briefing:

1. Disparos
2. Leads
3. Ingresso no grupo
4. % ingresso no grupo
5. Taxa de evasão
6. CPL
7. Pré-checkout (abre a lista de pré-checkout)
8. Vendas (abre a lista de vendas da Sessão de Viabilidade)
9. Taxa de conversão do pré-checkout
10. CAC
11. Faturamento bruto
12. Faturamento líquido
13. ROAS

Antes deles vem o card Investimento geral (com as parcelas Disparo e Tráfego). O card "Custo com disparo" saiu em 13/10/2026 (ver "Funil com Pré-checkout e Vendas" abaixo).

O front lê somente RPCs Supabase com a chave do dashboard:

| Bloco | RPC |
|---|---|
| Cards | dados_atm_resumo |
| Evolução diária | dados_atm_serie_diaria |
| Modal de leads, evolução e resumo | dados_atm_leads e dados_atm_serie_diaria |
| Abas API, Grupo, SMS, Ligação e E-mail | dados_atm_disparos_canais |
| Lista detalhada de disparos | dados_atm_disparos_lista |
| Comparecimento | dados_atm_comparecimento |
| Ciclo aberto e fechado pós-live | dados_atm_pos_live |

Receita, custos, CPL, CAC e ROAS são apresentados conforme os valores devolvidos pelo banco. Desde a migration `20261009230000`, o resumo calcula CPL como investimento total (tráfego + disparo) ÷ leads sem teste; CAC e ROAS também usam o investimento total. Para ATM OUT/26, o Galego informou investimento de 112.050 centavos (103.208 de disparos + 8.842 de tráfego), 97 leads e CPL de 1.155 centavos (R$ 11,55). Não há preço de venda fixo no código. Custos em centavos são convertidos para reais na camada de dados. O modal mostra os campos de origem descritos no briefing; dado pessoal só é buscado ao abrir o modal.

Se a RPC ainda não existir ou não devolver dado, o bloco permanece disponível e mostra “sem dado ainda”. Zero numérico devolvido pelo banco é apresentado como zero medido. Falhas isoladas não impedem os demais blocos. Uma falha de atualização preserva o último dado carregado. Resumo e série atualizam a cada 60 segundos somente com a aba visível, sem sobrepor chamadas.

## Detalhe de disparos (09/10/2026)

A seção Disparos mantém o resumo por canal e, abaixo dele, mostra cada registro retornado por `dados_atm_disparos_lista`, filtrável por canal. A ordem vem da RPC: data e hora ascendente e, em empate, identificador ascendente. A data de referência é `coalesce(enviado_em, criado_em)`, exibida no fuso de São Paulo. O filtro de período da tela é enviado à mesma RPC.

O contrato está em [MODELO-DE-DADOS.md](./MODELO-DE-DADOS.md), seção “Lista de disparos”; a migration `20261009220000` foi aplicada pelo Galego em 09/10/2026. A tela chama a RPC com a sessão autenticada e não usa `service_role`.

Cada linha expansível mostra a campanha, canal, tipo quando houver, contagens de enviados, entregues, lidas, cliques e falhas, além do custo. Os detalhes incluem ferramenta, número remetente, lista e origem do público, origem do registro e horários de envio e retorno. O conteúdo integral aparece quando há texto; quando só existe link, a tela mostra um link seguro para abrir. O campo é rotulado como **Campanha** porque não há coluna de título ou assunto no contrato.

Nulos permanecem “Sem dado”, sem conversão para zero. Canais sem custo por disparo são identificados como tal. As taxas de entrega (entregues ÷ enviados), leitura (lidas ÷ entregues), cliques (cliques ÷ entregues) e custo por entregue são calculadas na tela, identificadas como cálculo; denominador nulo ou zero deixa o resultado como “Sem dado”. Uma falha da RPC preserva as linhas carregadas anteriormente e mostra o aviso. A RPC não está duplicada em outra chamada para cada linha.

## Investimento geral e tráfego (09/10/2026)

A aba **Esta edição** inicia com o card **Investimento geral**, alimentado por `investimento_total_centavos`; abaixo aparecem as parcelas `custo_disparo_centavos` e `custo_trafego_centavos`, todas convertidas de centavos para reais. Com campos ainda ausentes ou nulos, o card mostra “Sem dado”, sem estimar ou somar valores na tela.

Até `investimento_total_centavos` estar disponível, CPL, CAC e ROAS também ficam como “Sem dado”. Isso evita exibir os valores anteriores que consideravam apenas o custo de disparos e divergem da regra nova de investimento total.

O canal selecionado no topo do bloco Disparos filtra tanto os totais quanto a lista detalhada; há um único controle de canal.

**De onde vêm os disparos (11/10/2026, migration `20261011120000`):** API, grupo, SMS e ligação vêm da planilha
`[SEMATM OUT/26] MENSAGERIA`, puxada sozinha a cada 10 minutos (ver `docs/central-de-dados.md`, "Sync da planilha de
mensageria"); o e-mail vem da integração do ActiveCampaign. Lançou custo ou disparo na planilha: aparece no dashboard em
até 10 minutos. Quando a planilha não traz ENVIADOS, o disparo entra com 0 enviados (e o custo) até alguém preencher.

**Aba GRUPO fora da sync (14/10/2026).**
- **O que aconteceu:** a aba `GRUPO` da planilha virou `GRUPO ANTIGOS` e `GRUPO NOVO`. A sync lê as abas num lote só, e o
  nome que deixou de existir derrubou o lote inteiro (`google_400`). Por isso API, SMS e LIGAÇÃO ficaram sem sincronizar de
  14:46 a 20:26 UTC.
- **Correção mínima (ok do Maestro, 14/10 20:24 UTC):** `GRUPO` saiu do mapa em `mkt_mensageria.planilhas` (id 1). A rodada
  das 20:26 UTC voltou `ok`, com API, SMS e LIGAÇÃO lidas.
- **O que ficou:** os 2 disparos de grupo que já tinham vindo da planilha continuam no banco. Os disparos de grupo que
  chegam pela API do SendFlow (campanha "ATM 10/26") não dependem da planilha.
- **Pendente, decisão do Victor:** mapear `GRUPO ANTIGOS` e `GRUPO NOVO`. Cuidados:
  - as linhas "Troca de nome do grupo" não têm hora e seriam recusadas;
  - os envios da planilha podem contar em dobro com os disparos de grupo da API do SendFlow.
- **Para voltar ao mapa antigo:** repor a aba `GRUPO` no mapa. Antes, a planilha precisa voltar a ter uma aba com esse
  nome.

### Aba Tráfego

A aba usa `dados_atm_trafego(p_chave, p_de, p_ate)`, que retorna JSON com período, coleta, totais, série diária e campanhas. A migration `20261009230000` e a coleta `trafego-meta` foram aplicadas/publicadas em 09/10/2026, conforme atualização do Galego. Para ATM OUT/26, ele informou 1.448 impressões, alcance 993, frequência 1,4582, 1.310 plays, 147 ThruPlay, engajamento 564 e nenhum clique no link. CTR informado 0,00; CPC, visualizações da página e cliques de saída vieram nulos porque a API não enviou esses campos. A tela preserva nulos como “Sem dado”.

**Frequência do dado de tráfego (09/10/2026, migration `20261009240000`):** o dia corrente é recoletado do Meta a cada 30 minutos (cron `trafego-meta-hoje`, nos minutos 15 e 45 de cada hora, UTC); os 3 dias anteriores são relidos uma vez por dia às 06h30 de São Paulo (cron `trafego-meta`), o que corrige a atribuição que o Meta ajusta depois. O campo `coletado_em` da RPC diz a hora da última coleta. O Meta pode levar alguns minutos para refletir o gasto, então o dado de hoje fica até ~30 min atrás do Gerenciador.

O funil segue a ordem gasto, impressões, alcance, frequência, vídeo, cliques no link e visualizações de página. CPM, CTR e CPC recebem o rótulo “cálculo” conforme a lista `calculados` da RPC. O gráfico diário mostra gasto; cada dia pode ser expandido para consultar todas as métricas devolvidas.

Alcance e frequência agregados só são exibidos quando `alcance_motivo` é nulo. Caso contrário, a tela mostra “Sem dado” e o motivo devolvido (`varias_campanhas`, `periodo_parcial` ou `sem_total`). Os valores diários de alcance e frequência são apresentados exatamente como vêm do banco; o front não soma esses campos. A lista de campanhas preserva nome, status, objetivo, conta, gasto e datas do JSON.

## Situação do banco

O contrato do front está descrito na migration **infra/supabase/migrations/20261008161000_dados_criar_modelo_seminario_atm.sql**. Ela e o cadastro inicial (**20261008161100_dados_cadastrar_atm_elaine_1.sql**, sigla `ATMEL126`) foram aplicados em produção em 08/10/2026; situação e pendências em `MODELO-DE-DADOS.md`. O front não aplica migrations nem lê planilhas.

## Teste local

1. Em **web/**, instale as dependências conforme o lockfile e configure o **.env.local** existente.
2. Rode **npm run dev -- -p 3001**.
3. Entre com um usuário autorizado a Infra e a **financeiro.ver**.
4. Abra Infra > Dashboards > Escritório > Seminário ATM.
5. Com a migration aplicada, confira Investimento geral, Disparo e Tráfego contra o resumo do banco. Para a leitura informada em 09/10/2026, o total foi R$ 1.120,50, CPL R$ 11,55 e 97 leads.
6. Com as RPCs aplicadas e dados cadastrados, confira a ordem dos cards, abra o modal de leads e navegue pelas cinco abas de disparo, comparecimento e ciclos pós-live.
7. Na seção Disparos, selecione cada canal e expanda registros para conferir contagens, taxas calculadas, valores nulos como “Sem dado” e conteúdo em texto ou link.
8. Confira que o seletor do resumo de Disparos também filtra a lista. Em **Esta edição**, confira o card Investimento geral e seus itens Disparo e Tráfego.
9. Confira a aba Tráfego, o motivo para alcance/frequência sem total, a série diária, as campanhas e os campos identificados como cálculo. A frequência do período é formatada com duas casas decimais na tela.
10. Verifique a atualização periódica e o rótulo de horário no cabeçalho.

Verificações do projeto:

    cd web
    npm run lint
    npx tsc --noEmit
    npx vitest run
    npm run build

## Teste em produção (08/10/2026)

- Merge `ba417ab` na main, CI verde. Teste logado em produção: card no Escritório, 14 cards zerados com "sem dado ainda", modal e abas ok, chave inexistente 404, sem rolagem horizontal em 374 e 377 px.
- **Acesso:** a tela usa o mesmo gate da Clínica (`csm/[chave]`). Com `acessoV2` desligado em produção, vale o modelo antigo: quem vê Infra vê a tela. O dado continua protegido no banco: as RPCs recusam quem não é da equipe (42501). Bloquear por `financeiro.ver` depende de ligar o `acessoV2`, que é outra frente.
- **Console:** enquanto a migration não for aplicada, as RPCs respondem PGRST202 (função inexistente). Desde este commit isso é tratado como "sem dado ainda", sem registrar erro.

## Resumo do modal de leads

A aba Resumo apresenta as mesmas seis categorias e contagens que antes apareciam em linhas: Entrou no grupo?, É aluno?, utm_source, Estado, Lista de origem e Seminário de origem. Valores booleanos aparecem como “Sim” e “Não”, sem texto `true`/`false`. Cada categoria usa o componente reutilizável RoscaCategorias, já adotado pela visão geral de vendas do dashboard presencial. A legenda conserva o rótulo e a quantidade de cada categoria; o centro mostra o total de leads da categoria. Em telas estreitas, a legenda fica abaixo da rosca para manter rótulo e valor legíveis.

Na rosca e na tabela, `lista_origem = 'descartado'` (estava na aba Descartados de uma das listas) aparece como **Outros**, pedido do Victor em 08/10/2026. O valor no banco continua `descartado`; a troca é só de rótulo, em `rotuloListaOrigem` (`web/modules/infra/atm/domain/dashboard.ts`).

## Período e marcação de teste

Contrato aplicado em produção em 08/10/2026, migration `20261008191000` e ajuste `20261008191100`. O detalhe de nomes, parâmetros e limites está em [MODELO-DE-DADOS.md](./MODELO-DE-DADOS.md), seção 0.

- O seletor oferece Período do evento, Hoje, Ontem, Últimos 3 dias e Últimos 7 dias. As datas relativas são calculadas em `America/Sao_Paulo`; Período do evento envia `p_de` e `p_ate` nulos para usar as datas da configuração do dashboard.
- Resumo, série, leads, canais e números do grupo recebem o período. Comparecimento e pós-live continuam no evento inteiro.
- Atualizar recarrega todos os blocos. O polling continua atualizando resumo e série a cada 60 segundos só com a aba visível. Falhas conservam o último resultado bom.
- O modal Leads ganhou a aba Grupo. Master pode marcar e desmarcar leads ou números do grupo; os controles não aparecem para outros perfis. A confirmação informa que a marcação vale para aquele evento.
- O banco exclui marcados dos indicadores. A tela não filtra resultados numéricos. Lead marcado permanece na lista master, esmaecido e com etiqueta “teste”. Números do grupo marcados também mostram a etiqueta e o motivo equipe quando aplicável.
- Se o banco devolver `leads_teste`, `grupo_teste`, `vendas_teste` ou `receita_teste_bruta` maior que zero, a tela apresenta um aviso para deixar claro o que foi excluído, inclusive quantidade de vendas e faturamento bruto.
- O aviso de itens excluídos por marcação de teste é decidido no servidor pelo UUID autenticado. A configuração única em `web/modules/infra/atm/domain/visibilidade-aviso-teste.ts` aponta para a conta do Victor; o cliente recebe só um booleano. Os dados marcados continuam fora dos indicadores para todos os usuários.
- As RPCs retornam `42501`, `P0002` e `22023` em situações de acesso, vínculo ao evento e validação. A tela apresenta mensagens legíveis e não registra identificadores pessoais nos logs.

Para validar: selecionar cada período, conferir as datas e os números, abrir Leads e Grupo, verificar as etiquetas de teste com um perfil master e confirmar que os outros perfis não recebem os controles. O aviso de exclusões aparece apenas para o Victor; confirme com sessão dele e com uma conta QA. O teste local não deve marcar ou desmarcar dados reais.

## Aba Histórico (09/10/2026, branch `victor-atm-historico`, não publicada)

Pedido do Victor de 09/10/2026 (card 17tya50ftxn). O dashboard ganhou duas abas no topo: **Esta edição** (tudo o que existia antes, sem mudança de comportamento) e **Histórico**. O histórico só é lido na primeira vez que a aba é aberta.

**Fonte.** Uma RPC só: `dados_historico_edicoes(p_familia)`, criada pela migration `20261009200000` (banco descrito no `.explain.md` dela). A família vem de `familia` no registro (`web/modules/infra/atm/domain/registro.ts`, hoje `seminario-atm`). A RPC devolve uma linha por edição com os números medidos, `fontes` (texto da fonte de cada número) e `provisorio` (métricas que ainda podem mudar). Dinheiro chega em centavos e vira reais em `infrastructure/historico-data.ts`. Enquanto a função não existir (PGRST202) a aba mostra "sem dado ainda", sem erro. Tempo limite de 15 s; falha conserva a última leitura, esmaece a tela e mostra a hora dela.

**Sub-abas.**
- **Comparativo geral:** métricas nas linhas, uma coluna por edição (rótulo exato do banco), em quatro blocos: Captação, Aulas, Vendas e Eficiência. A conversão sobre o pré-checkout é a linha principal, em destaque. A tabela rola por dentro em tela estreita.
- **Uma sub-aba por edição** devolvida pela RPC: cartão principal com a conversão sobre o pré-checkout, cards de receita líquida, ROAS, vendas, CAC, leads, ingressos no grupo, taxa de ingresso, investimento total (com tráfego e disparo) e CPL; gráfico dos picos D1 a D3 com retenção e comparativo; funil leads → grupo → pico na live (dia 1) → pré-checkout → vendas, com a passagem entre etapas e o percentual sobre os leads. Não há funil de investimento.

**Fórmulas (calculadas na tela, nunca gravadas), em `web/modules/infra/atm/domain/historico.ts`:**

| Métrica | Fórmula |
|---|---|
| Investimento total | tráfego + disparo (se uma das partes vier nula, o total fica "—") |
| CPL | investimento total ÷ leads |
| CAC | investimento total ÷ vendas |
| ROAS | receita líquida ÷ investimento total |
| Taxa de ingresso no grupo | grupo ÷ leads |
| Conversão (pré-checkout, grupo, leads) | vendas ÷ base |
| Retenção | pico da aula ÷ pico da aula anterior da mesma edição |
| Comparativo | pico da edição ÷ pico da mesma aula da edição anterior (anterior = a edição imediatamente antes pela `ordem`) |

Divisão por zero ou valor nulo aparece como "—". Dia 3 nulo (ATM JUL/26) mostra "—" e "sem dia 3", sem quebrar o layout. Cada número tem tooltip com a fonte (string do campo `fontes`) e, se for calculado, a fórmula; número provisório leva `*` e aviso. Para teclado e leitor de tela, o bloco "Fonte de cada número" lista as mesmas fontes.

**Como entra a próxima edição.** Basta a linha nova em `dados.edicoes_historico` com a mesma família e a `ordem` seguinte: a sub-aba e a coluna aparecem sozinhas, sem mexer na tela. Como a linha é preenchida está no `.explain.md` da migration `20261009200000`.

**Como testar.**
1. Em `web/`: `npx vitest run modules/infra/atm` (os testes de `historico.test.ts` conferem os dois ATMs: ROAS 4,86x e 6,02x; CAC R$ 291,42 e R$ 235,50; conversão sobre o pré-checkout 26,9% e 27,3%; retenção D2/D1 28,4% e 48,8%; comparativo D1 171,6% e D2 295,2%).
2. Com a migration aplicada, logado com usuário da equipe, abrir Infra > Dashboards > Escritório > Seminário ATM > Histórico e conferir cada número da tabela contra a seção "Números que valem" do pedido e contra a carga da migration.
3. Em 375 px: a página não pode rolar na horizontal; a tabela rola por dentro.
4. Sem a migration: a aba mostra "Histórico sem edições · sem dado ainda".

### Aprimoramento visual do histórico (branch `victor-atm-historico-visual`)

O comparativo abre com dez cards: Leads, Grupo, Taxa de ingresso, Pico D1, Pré-checkout, Vendas, Receita, CAC, ROAS e CPL. Cada card coloca as edições em linhas com valor e barra proporcional; a edição mais recente recebe destaque. A variação relativa compara a edição mais recente com a anterior. Aumento é favorável para as métricas de volume e receita; queda é favorável para CAC e CPL. Sem base válida, a variação aparece como "—". A tabela completa continua disponível em um bloco recolhível.

O comparativo também mostra um funil por etapa (Leads → Grupo → Pico D1 → Pré-checkout → Vendas), com uma barra por edição. Nas sub-abas, as barras de pico D1-D3 e as etapas do funil animam a entrada, contam os valores e respondem a foco e hover com destaque. As dicas mostram valor, passagem sobre a etapa anterior quando se aplica e fonte do dado. Trocar de sub-aba tem transição curta. `prefers-reduced-motion` desativa as animações e transições.

As visões usam exclusivamente as linhas da RPC `dados_historico_edicoes` e os indicadores definidos em `domain/historico.ts`; a variação é calculada a partir das duas edições exibidas e divisão com base nula ou zero resulta em "—". Os cards empilham em telas estreitas; a tabela completa permanece recolhida e rola em seu próprio contêiner.

**Como validar.** Rode `npx vitest run modules/infra/atm/domain/historico.test.ts modules/infra/atm/ui/historico-visual.test.ts`, `npx tsc --noEmit`, `npm run lint` e `npm run build`. Faça a inspeção visual com fixtures de teste em 1280 px e 375 px; confira que não aparece rolagem horizontal na página, que a tabela está recolhida no comparativo, que foco/hover exibe fonte e que `prefers-reduced-motion` desativa o movimento.

Na QA desta branch, a prévia visual usou uma rota temporária local que renderizava apenas `HistoricoAtmView` com os mesmos fixtures da suíte. A rota e a exceção temporária de autenticação foram removidas após a captura; não fazem parte do produto nem chamaram a RPC. As capturas 1280 px e 375 px ficam junto do relatório de entrega no cérebro.

### 09/10/2026: Escritório sem o selo "Em breve"

O cartão Escritório em Infra > Dashboards saiu do estado "Em breve" (`emBreve` removido em `web/app/(admin)/infra/dashboards/page.tsx`), porque a área já tem o Seminário ATM no ar. Pedido do Victor.

### 09/10/2026: aba Tráfego publicada (funil visual)

- A aba Tráfego abre com um funil em barras no padrão do Histórico: Impressões, Vídeo plays, 25%, 50%, 75%, 100%, Cliques no link e Visualizações de página. A base é a impressão; a passagem entre etapas e o "% das impressões" são cálculo da tela. Etapa sem dado na API aparece como "Sem dado" e não calcula passagem.
- Alcance e frequência ficam fora do funil (são pessoas, não ações) e aparecem nos cards, só quando a RPC não manda `alcance_motivo`.
- Publicado junto com o banco do Galego (branch `victor-atm-trafego-banco`) e a tela do JP (branch `victor-atm-trafego-tela`). Card ClickUp 17tya50fugc.

## Funil com Pré-checkout e Vendas (13/10/2026, 18h35, branch `victor-atm-funil-sv`)

**Pedido do Victor (13/10/2026, 18h35).** A seção separada "Sessão de Viabilidade" (barra com 3 cards e modal) não era o que ele queria. Decisões:

1. **Seção "Sessão de Viabilidade" removida da página.** O componente `SessaoViabilidade.tsx` foi apagado; a lista de vendas e a marcação de teste foram reaproveitadas no modal do card Vendas (`web/modules/infra/atm/ui/ModaisFunilAtm.tsx`).
2. **Cards Pré-checkout e Vendas do funil** continuam lendo `dados_atm_resumo.pre_checkout_pessoas` e `dados_atm_resumo.vendas`. Zero do banco aparece como zero; "Não lançado / sem dado ainda" só quando a coluna vem nula (vendas é nula quando o cadastro não tem `oferta_codigo`) ou quando o resumo não foi lido. Na primeira carga, enquanto o resumo não chega, os cards dizem "Carregando…" em vez de "Não lançado".
3. **Modais dos dois cards**, no padrão do card Leads (componente `Modal`, `DataTable`):
   - **Vendas:** lista de `public.dados_atm_sv_vendas` (Data da venda, Nome com a transação embaixo, E-mail, Telefone, Status, Bruto / líquido, Oferta; para master, Teste e Ação). "Incluir testes" e marcar/desmarcar teste só para master, pelo e-mail da linha. Sem `contato.ver` a RPC não é chamada e o modal mostra "Lista indisponível". A nota "N vendas de teste fora do total" (`vendas_teste`) aparece só para master. A lista não tem período; o modal avisa.
   - **Pré-checkout:** mostra o número do card e a tabela com as colunas pedidas (Data do pré-checkout, Nome, E-mail, Telefone, Comprou?, utm_source) no estado **"Lista ainda não ligada"**, sem linha e sem número inventado: não existe RPC pública com a lista de pré-checkout do ATM (ver MODELO-DE-DADOS.md). **Substituído às ~19h:** o modal passou a ler `dados_atm_pre_checkout` (a publicar); ver "Modais do funil lendo sozinhos" abaixo.
4. **Taxa de conversão do pré-checkout:** o card já existia e continua usando a regra do banco, `conversao_pre_checkout_pct` = **compradores distintos (e-mail) ÷ `pre_checkout_pessoas` × 100** (migration `20261009230000`). A hipótese do Victor era vendas ÷ pré-checkout, e a tela antiga da SV calculava vendas ÷ pré-checkouts únicos. **Diferença:** o banco conta pessoas que compraram (um e-mail com duas vendas conta 1), a hipótese conta transações (conta 2). Nenhuma das duas exige que o comprador tenha passado pelo pré-checkout (essa conta existe no banco como `compradores_no_pre_checkout`, sem card). A tela não recalcula: sem denominador (pré-checkout nulo ou 0) mostra "Não lançado / sem dado ainda", nunca 0% (`metricaDoCardAtm` em `domain/dashboard.ts`). A dica do card mostra a fórmula. Se o Victor quiser vendas ÷ pré-checkout, a mudança é no banco, não na tela.
5. **Card "Custo com disparo" removido.** Conferido antes na migration `20261009230000` (`dados_atm_resumo`): `investimento_total_centavos = coalesce(custo de disparo, 0) + custo de tráfego`, e CPL, CAC e ROAS são calculados sobre esse total. O custo de disparo continua visível como a parcela "Disparo" do card Investimento geral e na coluna "Custo disparo" da Evolução diária.

**Correção junto (achada no print):** o card ROAS dividia `roas_liquido` por 100 desde o commit `af9b51f` (era tratado como centavos). `roas_liquido` já vem em vezes (`numeric(10,2)`), então um ROAS de 4,82x aparecia como 0,05x. Corrigido em `carregarAtmResumo` (`infrastructure/atm-data.ts`), com teste.

**Situação:** não publicado. Nenhuma mudança de banco.

**Como testar.**
1. Em `web/`: `npx vitest run modules/infra/atm` (cards do funil, `metricaDoCardAtm`, zero contra nulo, ROAS), `npx tsc --noEmit`, `npx eslint modules/infra/atm`, `npm run lint:tokens`, `npm run build`.
2. Logado, abrir a chave `atm-elaine-1-2026-10`: não há seção "Sessão de Viabilidade" nem card "Custo com disparo"; Pré-checkout e Vendas mostram o número do resumo (13/10, 18h35: 1 e 0); a taxa mostra o `conversao_pre_checkout_pct` do banco.
3. Clicar em Vendas: a lista bate com o card no período do evento (descontadas as de teste). Como master, marcar e desmarcar uma venda de teste e ver o card mudar.
4. Clicar em Pré-checkout: aparece o número e "Lista ainda não ligada".
5. Logado sem `contato.ver`: os dois modais mostram "Lista indisponível" e não há chamada a `dados_atm_sv_vendas` na aba Rede.

**O que falta:** a RPC da lista de pré-checkout (banco) e, depois dela, ligar o modal.

## Modais do funil lendo sozinhos (13/10/2026, ~19h, branch `victor-atm-funil-sv`)

**Problema (Victor, 13/10, ~19h).** O card Leads mostrava 387 e o modal abria em "0 leads válidos · 07/10/2026 a 14/10/2026 · Leads indisponíveis, sem dado ainda"; o modal de Pré-checkout não trazia nem o lead de teste; o de Vendas não mostrava nada.

**O banco estava certo.** Conferido pelo Maestro no PostgREST, como master: `dados_atm_leads` 397 linhas com teste e 387 sem (~4,3 s), `dados_atm_grupo_numeros` 315 (~5,2 s), `dados_atm_resumo` com `leads` 387, `leads_teste` 10, `pre_checkout_pessoas` 1, `vendas` 0 (~4,4 s), `dados_atm_sv_vendas` 0 linhas.

**Causa (na tela).** Em `ui/SeminarioAtmClient.tsx` (commit `08c834d`), a lista de leads e a do grupo só eram pedidas dentro de `atualizar(true)`, junto das outras 6 leituras do refresh grande (linhas 177-180), e só quando o flag `modal` estava ligado (linhas 207-211). Se já havia refresh em curso (`emCurso`, linhas 150-153), o pedido virava `pedidoPendente` e só rodava depois do refresh inteiro. Durante todo esse tempo o estado inicial `{ data: [], semDado: true, erro: null }` (linhas 119-120) era desenhado pelo `ModalLeads` (linhas 104 e 110) como "0 leads válidos" e "Leads indisponíveis". Não existia estado "carregando". Reproduzido no harness com 4,5 s por leitura: o modal aberto logo depois do resumo ficou 8,8 s em "0 · indisponível" (pior caso, dois refresh seguidos, ~18 s).

**Correção (a classe, não a ocorrência).**
1. **Cada modal lê a sua lista sozinho**, na hora em que abre (e quando a chave muda: período, "Incluir testes"), fora do refresh grande. Leads e grupo saem em paralelo; cada aba aparece quando a sua lista chega. Arquivos: `ui/carregador-listas.ts` (regras, sem React, testadas) e `ui/useListaAtm.ts` (gancho). O refresh grande não lê mais leads nem grupo.
2. **Estados explícitos:** `carregando` (esqueleto na tabela, "Carregando…" no contador; nunca "0" nem "indisponível"), `pronto` (lista vazia de verdade vira vazio honesto com a hora da leitura), `erro` (mensagem da leitura), `naoPublicada` (só quando a RPC não existe, `PGRST202`), `semPermissao` (`42501`, limpa a lista).
3. **Cache por (RPC, evento, período, incluir teste)** enquanto a página está aberta: reabrir mostra a última lista na hora ("· atualizando…") e relê por trás; releitura que falha mantém a lista, esmaecida, com o erro e a hora. Duas aberturas da mesma chave fazem uma leitura só. O botão Atualizar e a marcação de teste relêem as listas abertas.
4. **Tempo limite** de 20 s nas listas de leads, grupo e pré-checkout (`TEMPO_LIMITE_LISTAS_MS`); vendas continua com 15 s.
5. **Um componente só para os três modais:** `ui/ModalPessoasAtm.tsx`, extraído do modal de Leads (decisão do Victor: a estrutura de abas do modal de Leads é o modelo). Abas `<pessoas>` · Grupo · Evolução · Resumo, em tabela, mesmo visual. `ui/ModaisFunilAtm.tsx` só configura cada um:
   - **Leads:** como antes (colunas, aba Grupo com os números do grupo no período e marcação de teste por número, roscas). A Evolução agora sai da própria lista (barras por dia do `primeiro_em`, sem teste), não mais da série do refresh grande; a soma das barras é o contador.
   - **Pré-checkout:** aba Pessoas (Data do pré-checkout, Nome, E-mail, Telefone, É lead?, Comprou?, utm_source), Grupo, Evolução por data do pré-checkout, Resumo (Entrou no grupo?, É lead?, É aluno?, Comprou?, utm_source, Estado, Lista de origem, Seminário de origem). Lê `dados_atm_pre_checkout` (**a publicar**, ver MODELO-DE-DADOS.md). Enquanto a função não existir, o modal diz "A lista de pré-checkout ainda não foi publicada no banco." Marcação de teste pelo e-mail (telefone só sem e-mail).
   - **Vendas:** aba Pessoas (colunas de antes), Grupo, Evolução por data de aprovação, Resumo (Status, Oferta, Entrou no grupo?). Sem venda: "Nenhuma venda da Sessão de Viabilidade registrada neste período" + hora da leitura, nas 4 abas.
   - **Grupo de Pré-checkout e Vendas:** cruza cada pessoa com `dados_atm_grupo_numeros` do **período do evento** pela chave de telefone (`chaveTelefone` de `modules/comercial/domain/regras.ts`, a mesma de `controle.fone_key`) nos **8 últimos dígitos**, que é a regra do banco (`fone8`). Sem telefone: "Sem telefone", nunca "Não".
6. **Card e modal batem** (`domain/modal-pessoas.ts`, `contadorDoModalAtm`): Leads = linhas sem teste = `resumo.leads`; Pré-checkout = linhas sem teste = `pre_checkout_pessoas`; Vendas = linhas sem teste com `aprovado_em` (São Paulo) no período aplicado = `resumo.vendas`. A lista de vendas não tem período no banco, então o recorte é feito na tela com a regra do banco (`dados.periodo`: de 00:00 até o fim do dia `ate`). Se o contador divergir do card, o modal mostra um aviso amarelo com os dois números.
7. **"Incluir testes"** (só master) passou a valer nos três modais (antes só no de Vendas; o de Leads pedia sempre com teste para master). Ligado por padrão para master, como antes.

**Decisões.** Evolução calculada da lista (para não depender do refresh grande e bater com o contador). Grupo de Pré-checkout/Vendas no período do evento (quem está ou esteve, qualquer que seja o período). Import de `chaveTelefone` do domínio `comercial` (domínio puro; já há precedente de domínio importando domínio de outro módulo). `useVendasSvAtm` saiu (substituído pelo carregador); `listaAposLeituraSv` continua no domínio, sem uso na tela.

**Situação:** não publicado. Nenhuma mudança de banco nesta frente. `dados_atm_pre_checkout` é de outra frente e ainda não está no banco.

**Como testar.**
1. Em `web/`: `npx vitest run modules/infra/atm` (carregador: carregando, erro, vazio, `PGRST202`, `42501`, cache/revalidação, troca de período, leitura única; contador = card para Leads, Pré-checkout e Vendas; contrato da RPC de pré-checkout), `npx tsc --noEmit`, `npx eslint modules/infra/atm`, `npm run lint:tokens`, `npm run build`.
2. Logado, chave `atm-elaine-1-2026-10`, abrir Leads logo ao carregar a página: aparece "Carregando…" e o esqueleto; ~5 s depois, "387 leads válidos" (o card diz 387). Fechar e reabrir: 387 na hora, com "· atualizando…".
3. Pré-checkout: antes da publicação da RPC, a mensagem de não publicada; depois, 1 pessoa (o lead de teste 27851, não marcado como teste), igual ao card.
4. Vendas: hoje "0 vendas válidas" e o vazio honesto nas 4 abas.
5. Prints do harness local (dados fictícios, 4,5 s por leitura) em `.maestri/entregas/atm-vendas-tempo-real/` no cérebro (fora do repo).

## Sessão de Viabilidade no ATM (substituída em 13/10/2026, 18h35)

Esta seção descreve a versão anterior, em seção separada, que saiu da página: ver "Funil com Pré-checkout e Vendas" acima. Card ClickUp 17tya50ga3c. Branch `victor-atm-sv-precheckout`. Componente `web/modules/infra/atm/ui/SessaoViabilidade.tsx`, regra pura em `web/modules/infra/atm/domain/sessao-viabilidade.ts`, leitura em `carregarAtmSvVendas` (`web/modules/infra/atm/infrastructure/atm-data.ts`).

### 13/10/2026: mockup inicial (JP, commit 672d728)

Seção **Sessão de Viabilidade** abaixo dos cards gerais, com três cards clicáveis (Pré-checkouts únicos, Total de vendas, Conversão do pré-checkout), modal no componente compartilhado, função `conversaoSessaoViabilidade` e a capacidade `contato.ver` passada pelo servidor (`podeVerContato`).

### 13/10/2026: vendas ligadas ao banco e pré-checkout em mockup

O que foi feito, continuando o mockup:

- **Total de vendas** (card): `dados_atm_resumo.vendas`, já carregado pelo dashboard e no período aplicado. A nota abaixo do número vem de `dados_atm_resumo.vendas_teste` ("N vendas de teste fora do total"); zero mostra "nenhuma venda de teste no período", nulo não afirma nada.
- **Histórico de vendas** (1ª aba do modal, "Vendas"): tabela ligada à RPC nova `public.dados_atm_sv_vendas(p_chave, p_incluir_teste)`. Colunas: Data da venda (decisão do Victor, 13/10: a venda usa a data da venda e o pré-checkout usa a data do pré-checkout; antes se chamava "Data do evento"; vem de `aprovado_em` em São Paulo, ou `dia_aprovado`), Nome, E-mail, Telefone, Status, Valor bruto, Valor líquido (na `moeda` da linha; sem moeda sai só o número), Oferta (`oferta_codigo`), Transação. Para master: colunas Teste e Ação.
- **Teste vale no banco**: o botão Marcar/Desmarcar teste chama as RPCs que já existem, `dados_marcar_teste` / `dados_desmarcar_teste`, só com o **e-mail** da linha (`p_telefone` vai nulo; grava em `dados.marcacoes_teste`). O ramo de telefone do banco (`dados.atm_pertence`) não consulta vendas (dá `P0002`) e casa pelos 8 últimos dígitos, podendo atingir outra pessoa; por isso a SV não o usa, o texto do diálogo diz que a marcação é pelo e-mail e venda sem e-mail mostra "Sem e-mail" no lugar do botão. O modal de leads não mudou. Marcar pede confirmação, como no modal de leads. Depois da ação, a lista e o resumo são relidos. Nenhum dado de teste foi criado.
- **Incluir testes**: alternador só para master (`Toggle` compartilhado), ligado por padrão, igual ao modal de leads (que pede `p_incluir_teste = isMaster`). Linha com `teste = true` aparece esmaecida, com o selo **TESTE**, e fica fora da contagem "vendas válidas na lista".
- **Dado pessoal**: sem `contato.ver`, a aba Vendas mostra "Lista indisponível" e a RPC **não é chamada** (o dado pessoal não chega ao navegador).
- **Pré-checkout**: aba "Pré-checkout · MOCKUP" e card "Pré-checkouts únicos" com o selo **MOCKUP** visível, sem número e sem contato. A regra pedida continua sendo pré-checkouts únicos por e-mail.
- **Conversão do pré-checkout** = vendas ÷ pré-checkouts únicos (`conversaoSessaoViabilidade`). Enquanto o pré-checkout for mockup (nulo), aparece "Sem dado".
- **Resumo** (3ª aba): Total de vendas, Vendas de teste fora, Pré-checkouts únicos (MOCKUP) e Conversão.

**Situação.** A RPC `dados_atm_sv_vendas` está **APLICADA** em produção desde 13/10/2026 (versão `20261013190752`). Se a função sumir (reversão), a tela degrada para "sem dado ainda": `PGRST202` (função inexistente) vira lista vazia sem mensagem de erro. Recusa do banco, falha de rede ou mais de 15 s sem resposta viram aviso amarelo, e a última lista lida continua na tela, esmaecida, com o horário da leitura. **Exceção:** se o banco recusar com `42501` (permissão perdida no meio da sessão), a lista é limpa e a tela mostra "Lista indisponível" com o aviso, para não deixar dado pessoal visível sem permissão (`listaAposLeituraSv`). **Tabela (master):** a largura mínima caiu (1120 px master, 1000 px sem Teste/Ação), Teste e Ação vêm antes de Transação, Nome e Oferta não quebram linha e Transação ficou por último, estreita e truncada com o valor completo no `title`. Não foi medido em navegador se Ação cabe sem rolagem em 1440 px; se não couber, a rolagem horizontal do contêiner aparece. Nada foi publicado.

**Como testar.**

1. Em `web/`: `npx vitest run modules/infra/atm` (domínio da SV e leitura da RPC: contrato, `PGRST202`, `42501`, rede e tempo limite), `npx tsc --noEmit`, `npx eslint modules/infra/atm`.
2. Antes da migration: abrir o dashboard da chave `atm-elaine-1-2026-10`, clicar em Total de vendas. A aba Vendas deve mostrar "sem dado ainda", sem quebrar; o card Total de vendas segue o resumo.
3. Depois da migration aplicada, logado como master com `contato.ver`: conferir a quantidade de linhas sem teste contra a fonte (Hotmart) e contra o card Total de vendas no período do evento; marcar uma venda como teste e conferir que o card cai em 1 e a nota "venda de teste fora do total" aparece; desmarcar e conferir a volta.
4. Logado sem `contato.ver`: a aba Vendas mostra "Lista indisponível" e, na aba Rede do navegador, não há chamada a `dados_atm_sv_vendas`.

**O que falta.**

- Aplicar a migration de `dados_atm_sv_vendas` (outra frente) e conferir a tela contra a fonte.
- A RPC não recebe período: a lista é a que a RPC devolver, e o card Total de vendas segue o período selecionado. A tela avisa isso. Se a lista e o card divergirem no período do evento, decidir qual manda antes de mostrar à liderança.
- Fonte própria dos pré-checkouts da Sessão de Viabilidade (e-mails únicos). `dados_atm_leads.no_pre_checkout` é da lista geral de leads e não deve ser usado como lista da SV. Sem essa fonte, o card, a aba e a conversão continuam em MOCKUP / "Sem dado".

## Lentidão do dashboard e `contato.ver` em `dados_atm_leads` (13/10/2026, migration `20261013233000`)

O refresh e o modal de Leads levavam ~5 s por RPC (`dados_atm_grupo_numeros` ~6 s). Causa: em `dados.atm_leads` e
`dados_atm_grupo_numeros`, o CTE `l` era embutido e `controle.fone_key` era recalculado para cada par lead x pessoa
do grupo. Correção: `l as materialized`; resultados idênticos (md5) e cada RPC abaixo de 0,5 s. Junto,
`dados_atm_leads` passa a exigir `contato.ver` e só master pede teste (como `dados_atm_pre_checkout`); a chave de
serviço segue com acesso por causa da TV do dashboard-ht. Detalhes, tempos e permissões em
`infra/supabase/migrations/20261013233000.explain.md`.

## Comparecimento do dia 1 do ATM 1 OUT/26 (14/10/2026)

**O que foi feito.** A seção Comparecimento do dashboard do ATM lê `dados_atm_comparecimento(p_chave)`, que vem de `dados.sessoes` (pico e equipe) e `dados.sessao_presencas` (relatório do Zoom, por pessoa). Só havia a sessão `live` de 13/10 22:30 UTC, sem pico nem equipe, então a seção ficava vazia. Foi lançado o pico do dia 1 e a tela passou a mostrar o comparecimento por pico.

**De onde veio o dado.** Planilha `[ATM 1 ELAINE - OUT/2026] LEADS SESSÃO DE VIABILIDADE`, aba `Comparecimento`, série por minuto do Zoom de 19:30 a 21:30 (25 pontos): máximo **73 às 20:25**. Eram **5 pessoas da equipe** na live, que não estavam lançadas na planilha (`equipe` vazia). A planilha calcula `pico = MÁXIMO(série) − equipe`, então o pico lançado é **73 − 5 = 68**, com `equipe_na_sala = 5`. Os dois números e a conta ficam em `dados.sessoes.obs` da sessão.

**Banco.** Sem migration: é dado, uma linha de `dados.sessoes` (`id 7fbe2cef-4e5f-4f45-85f5-f7772c5698d3`, chave `atm-elaine-1-2026-10`, tipo `live`). Estado anterior: `pico_audiencia`, `equipe_na_sala` e `obs` nulos. Depois: 68, 5 e o texto da fonte. O `UPDATE` só atua se pico e equipe ainda estiverem nulos. Como voltar: `update dados.sessoes set pico_audiencia = null, equipe_na_sala = null, obs = null where id = '7fbe2cef-4e5f-4f45-85f5-f7772c5698d3';`.

**Tela.** `web/modules/infra/atm/domain/comparecimento.ts` define os cards da seção (antes estavam soltos no componente). Os cards "Comparecimento dos leads" e "Comparecimento do grupo" liam `presentes_leads`/`presentes_grupo`, que dependem do relatório do Zoom por pessoa e continuam sem dado; agora leem `pico_sobre_leads_pct` (pico ÷ leads) e `pico_sobre_grupo_pct` (pico ÷ grupo), a mesma conta da planilha. A seção ganhou o texto de ajuda: o pico já está sem as pessoas da equipe, que não contam como comparecimento nem como pessoa única. Quando o relatório do Zoom por pessoa for carregado, `presentes*` voltam como cards próprios (decisão do Victor).

**Números do dia da implantação (leitura de 14/10 19:16 UTC):** pico 68, equipe 5, leads 442, grupo 362, comparecimento 15,38% dos leads e 18,78% do grupo, vendas 0. A planilha mostrava 434 leads e 329 no grupo (foto anterior) e 73 de pico sem descontar a equipe (16,82% e 22,19%), por isso os percentuais diferem.

**Como testar.** `npx vitest run modules/infra/atm` (inclui `domain/comparecimento.test.ts`), `npx tsc --noEmit`, `npx eslint` nos dois arquivos, `npm run lint:tokens`. Na tela: abrir Infra > Dashboards > Escritório > ATM (`atm-elaine-1-2026-10`) e conferir a seção Comparecimento. Rotina de conferência no banco: `select pico_audiencia, equipe_na_sala, pico_sobre_leads_pct, pico_sobre_grupo_pct from public.dados_atm_comparecimento('atm-elaine-1-2026-10')`.

**O que falta.** Replay (15/10) e triplay: cadastrar as sessões em `dados.sessoes` e lançar pico e equipe depois de cada uma; relatório do Zoom por pessoa em `dados.sessao_presencas`; a planilha continua sem a equipe lançada (`equipe` vazio na aba `Comparecimento`).

### Ordem dos cards do Comparecimento e "não lançado" (14/10/2026, pedido 2 do Victor)

- **Ordem e rótulos** (`domain/comparecimento.ts`, `CARDS_COMPARECIMENTO`), exatamente esta: Total de leads · Total no grupo · Pico da audiência · Pessoas da equipe na sala · Comparecimento do grupo · Comparecimento dos leads · Vendas · Conversão · Conversão no grupo · Conversão sobre pico. O teste fixa chaves e rótulos na ordem.
- **"Não lançado" nos dois comparecimentos:** o código do PR #32 já lê `pico_sobre_grupo_pct` e `pico_sobre_leads_pct`, que a RPC devolve preenchidos (18,78 e 15,38 com pico 68). A tela que o Victor viu era a versão anterior ao deploy, em que esses dois cards liam `presentes_grupo` e `presentes_leads` (relatório do Zoom por pessoa, nulos): com pico e equipe já lançados, o resto da seção aparecia e só esses dois ficavam "Não lançado". Conferência do deploy e do bundle no ar no relatório de entrega (`.maestri/entregas/atm-comparecimento/vh-2.md`).
