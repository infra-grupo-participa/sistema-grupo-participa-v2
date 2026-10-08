# Mapa do Seminário ATM no dashboard-ht (referência para o dashboard do ATM 1 da Elaine)

Chave do projeto: `atm-elaine-1-2026-10` · card ClickUp 86aktf11y · live 13/10 19h30.
Autor: Estagiário (pesquisa e teste), 08/10/2026. Trabalho só de leitura: nenhum código foi editado e nada foi aplicado em banco.

**Para que serve.** O dashboard novo (Infra > Dashboards > Escritório > Seminário ATM) tem como referência visual e de regras o Seminário ATM do dashboard-ht. Este mapa diz, para cada número da referência, qual é a fórmula e de onde vem hoje (planilha), para o Galego e o JP reproduzirem lendo do **banco** e não de planilha. Onde a referência não tem o número pedido no briefing, está escrito **NÃO EXISTE NA REFERÊNCIA** (e então a regra é decisão nova, não cópia).

**Sobre as fontes.** Tudo abaixo foi lido no código do dashboard-ht (repo `jotacraq/dashboard-ht`, branch `main`, pasta `dashboard/dashboards-completo/dashboard-ht` do cérebro, commit `857100a`). Caminhos curtos usados nas citações:

| Abreviação | Arquivo |
|---|---|
| `OH` | `oficial.html` |
| `L1` | `api/sem-atm-leads.php` (ATM 1, julho) |
| `D1` | `api/sem-atm-disparos.php` (ATM 1) |
| `C1` | `api/sem-atm-comparecimento.php` (ATM 1) |
| `L2` | `api/sem-atm2-leads.php` (ATM 2, setembro) |
| `D2` | `api/sem-atm2-disparos.php` (ATM 2) |
| `R2` | `api/sem-atm2-retorno.php` (ATM 2) |

Existem **dois** modelos no dashboard-ht, e o dashboard novo deve seguir o **ATM 2**, que é o mais maduro (número único no grupo, regra do último evento, lista, aluno e professor no modal). O ATM 1 de julho só é a referência do **Comparecimento**, que o ATM 2 não tem. O que o "HT ATM" da Imersão (`api/ht-atm-set26.php`, `hta_atm_do_disparo`) faz é outro produto e não entra aqui.

## 0. Pontos de atenção (leia antes)

1. **Ciclo aberto x ciclo fechado de vendas: NÃO EXISTE NA REFERÊNCIA.** Nenhum campo, flag ou card nos três endpoints do ATM 2 nem no front. A janela de venda é única (a partir de 01/09/2026, `L2:47`, `R2:32`). A definição de "ciclo aberto" e "ciclo fechado" é decisão nova: precisa vir do Victor antes de modelar.
2. **PRÉ-CHECKOUT como card da Visão Geral: NÃO EXISTE NA REFERÊNCIA.** No ATM 2 o pré-checkout só aparece na home (`app.js:1115`) como "Abertura de Carrinho", e a conversão de checkout é `vendas ÷ pré-checkout × 100` (`app.js:1171`). Lá a contagem é de **linhas com nome** na aba `Pré checkout`, sem deduplicar (`L2:382-391`). No dashboard novo isso vira número vindo do banco (captura já existe na branch `victor-captura-pre-checkout`, migration `20261007220043`, conforme o briefing).
3. **Dois preços diferentes para o líquido por venda.** ATM 1: `1417.01` fixo no front (`OH:7050`, constante `NET_POR_VENDA`, sem fonte escrita em CLAUDE.md nem docs). ATM 2: bruto `1500.00` e líquido `1416.99`, no backend (`L2:61-62`), definidos pelo Victor em 09/09 e que **ignoram o valor da planilha de propósito**. O dashboard novo não pode herdar o preço fixo sem decisão: de onde vem o preço da venda e o líquido (Hotmart em `public.compras`?) é pergunta aberta.
4. **Evasão tem duas réguas.** ATM 1: `saídas ÷ ingressos` por linha de evento. ATM 2: **estado final de cada pessoa** (quem saiu e voltou não é evadido). Seguir a do ATM 2.
5. **Os dados do ATM de outubro ainda não existem no Drive.** Ver seção 8.
6. **Contradição de definição da Lista 2.** O briefing diz: "passou pelo pré-checkout da SV em algum momento, menos quem reagiu ao último ATM". A concepção do projeto (`gp-operacoes/projetos/2026-09-seminario-atm/concepcao.md` (repo gp-operacoes), seção 5) diz: quem **chegou ao checkout da Hotmart** nos seminários anteriores e **não comprou** a Sessão de Viabilidade. São duas fronteiras diferentes (pré-checkout x checkout, comprou x não comprou). Confirmar com o Victor antes de codar a regra.

## 1. Cards da Visão Geral: referência (ATM 2) x o que o briefing pede

Ordem pedida no briefing: disparos, leads, ingresso no grupo, % ingresso no grupo, taxa de evasão, custo com disparo, CPL, PRÉ-CHECKOUT, vendas, TAXA DE CONVERSÃO DO PRÉ-CHECKOUT, CAC, faturamento bruto, faturamento líquido, ROAS.

Formatação na referência: BRL com 2 casas, % com 1 casa, ROAS com 2 casas, valor ausente = traço longo na tela (`OH:7290-7327`, `renderSematm2VG`).

| # | Card pedido | Na referência | Fórmula da referência | Fonte hoje (planilha) | O que muda no banco |
|---|---|---|---|---|---|
| 1 | Disparos | Aparece como cards **dentro das abas de disparo** (Disparos, Enviados...). Não há card "Disparos" na Visão Geral do ATM 2 | contagem de linhas de disparo por canal (`D2`) | ver seção 4 | definir se o card soma os 5 canais; a referência não faz |
| 2 | Leads | "Leads" (abre o modal de leads) | `leads.total` = linhas com nome, e-mail ou data preenchidos. **Não deduplica** (`L2:259-269`) | planilha `1AL3eTrPwO8sISn54vDPN_L0PNy3fKMBtRXv3OXwM9mU`, aba `Leads Seminário ATM 2 - Set/26`, A:Z, colunas por cabeçalho (`L2:25`, `L2:39`) | decidir dedup (a referência conta linha, não pessoa) |
| 3 | Ingresso no grupo | "Ingressos no grupo", sub "Números únicos no log" | nº de **chaves únicas** com evento `group.updated.members.added` (`L2:341-356`) | aba `Ingressos Whatsapp - Seminario ATM 2 - Set/26`, A:F, mesma planilha (`L2:38`) | log do grupo vira tabela de eventos |
| 4 | % ingresso no grupo | "% de ingresso no grupo", sub "Ingressos ÷ Leads" | `ingressos.total ÷ leads.total × 100`, feito no front (`OH:7298`) | derivado | derivado |
| 5 | Taxa de evasão | "Taxa de evasão", sub "Saíram ÷ entraram" | `round(evadidos ÷ added × 100, 2)`, 0 se added = 0 (`L2:399`). **Evadido = chave cujo estado final é "fora"** (`L2:359-365`) | mesmo log | manter a regra do último evento |
| 6 | Custo com disparo | "Custo com disparos", sub "Aguardando planilha" se não disponível | `disparos.totals.custo_brl` = soma de custo de API, SMS e Ligue Lead (+ confirmação de inscrição) (`D2:520`, `D2:535`) | planilha de custos `1BgIF7dV82t6CyDgw2lKwhRtk6sH-h9BUsPJaLr9rz98`, aba `Custos de mensageria` (`D2:172-173`) | custo vem do banco; Grupo e E-mail não têm custo |
| 7 | CPL | "CPL", sub "Custo com disparos ÷ Leads" | `custo ÷ leads.total`; nulo se não houver lead ou custo. **Não é CPL de mídia** (`OH:7310`) | derivado | sem tráfego pago no ATM da Elaine, então esse CPL é o certo |
| 8 | PRÉ-CHECKOUT | **NÃO EXISTE** na Visão Geral | só na home: contagem de linhas com nome na aba `Pré checkout`, coluna C, linhas 2 a 2000 (`L2:382-391`) | planilha de vendas `1atIgGVuMoVt4zDRyL5E4jRERWN2U5O7Dj4JDiHY0YJg` | número novo, do banco (captura do pré-checkout) |
| 9 | Vendas | "Vendas", sub "Aprovadas, sem canceladas" (abre modal de compradores) | linha com col R `Status da Transação` = `APPROVED`, col AB `Cancelou?` diferente de `SIM` e col A (data) maior ou igual a 01/09/2026. **Sem dedup** (`L2:99-143`) | aba `Vendas Aprovadas`, A:AB | vendas vêm de `public.compras` (Hotmart), não de planilha |
| 10 | Taxa de conversão do pré-checkout | **NÃO EXISTE** como card | na home: `vendas ÷ pré-checkout × 100` (`app.js:1171`) | derivado | definir denominador (pessoas ou aberturas) |
| 11 | CAC | "CAC", sub "Custo com disparos ÷ Vendas" | `custo ÷ vendas`; nulo se vendas = 0 ou nulo (`OH:7306`) | derivado | derivado |
| 12 | Faturamento bruto | "Faturamento Bruto", sub "Vendas × R$ 1.500,00" | `round(vendas × 1500.00, 2)` (`L2:61`, `L2:418`) | preço fixo no código | ver ponto de atenção 3 |
| 13 | Faturamento líquido | "Faturamento Líquido", sub "Vendas × R$ 1.416,99" | `round(vendas × 1416.99, 2)` (`L2:62`, `L2:419`) | preço fixo no código | ver ponto de atenção 3 |
| 14 | ROAS | "ROAS", sub "Fat. Líquido ÷ Custo com disparos" | `fat_liquido ÷ custo` (`OH:7307`) | derivado | derivado |

**Conferido no código:** a ordem dos cards do ATM 2 é Leads, Ingressos, % ingresso, Evasão, Custo, CPL, Vendas, CAC, Fat. Bruto, Fat. Líquido, ROAS. A ordem pedida pelo briefing acrescenta Disparos, PRÉ-CHECKOUT e TAXA DE CONVERSÃO DO PRÉ-CHECKOUT.

**Regra de dado vazio da referência:** traço longo quando o número não existe, nunca zero fabricado. Se a leitura falha, o ATM 2 (retorno) segura o último número bom (`R2:134-139`).

## 2. Modal de leads (referência: ATM 2, `openSematm2LeadsModal`, `OH:7853-8077`)

- **Contador:** "N lead(s)"; com filtro, "X de N leads".
- **Aba "Leads"**, colunas na ordem (`OH:7885`): Data, Nome, E-mail, Telefone, Source, Medium, Campaign, Content, Term, Entrou no grupo?, Já é aluno?, Qual lista, Qual professor.
- **Aba "Evolução":** uma linha "Leads por dia" (`leads.byDay`). Com filtro, "Leads por dia (filtrado)".
- **Aba "Resumo":** 6 rosquinhas: Entrou no grupo?, Já é aluno?, UTM Source, Estado (por DDD), Qual lista, Qual professor. Estado mostra o top 5 mais "Outros".
- **Filtro cruzado:** clicar numa fatia filtra os outros gráficos, a tabela, a evolução e o contador. Filtros de campos diferentes se somam. O gráfico de origem não se filtra. Valor vazio vira "(não informado)". Cada abertura começa sem filtro.
- **UTM Medium e UTM Campaign** foram tirados do Resumo em 09/09 (`OH:7922`). O briefing pede só o tema do utm_source por enquanto, o que combina.

Regras de campo (todas em `L2`):

| Campo | Regra |
|---|---|
| Estado | UF pelo DDD do telefone; "Outros" se o DDD for desconhecido (`L2:181-197`). Tira o DDI 55 só se o número tem 12 ou mais dígitos (`L1:90-106`) |
| Entrou no grupo? | na referência, SIM se a **coluna da planilha** disser SIM. É só referência (`entrou_coluna`, `L2:404`) e **pode não fechar com o card**, que usa o log. No dashboard novo, calcular pelo log/banco, nunca por coluna digitada |
| Já é aluno? | SIM ou NÃO; vazio vira "Não identificado", **nunca NÃO** (`L2:295-299`) |
| Qual lista | vazio ou "-" vira "Não identificado" (`L2:235-238`, `L2:290-291`) |
| Qual professor | idem. É o equivalente do "seminário de origem (Marcio ou Elaine)" do briefing |

Chave de cruzamento da referência: **DDD + 8 últimos dígitos do telefone**, depois de tirar o 55 se tiver mais de 11 dígitos; chaves com menos de 10 dígitos são descartadas (`L2:252-256`). A concepção do ATM pede cruzar por **e-mail OU últimos 8 dígitos** (`gp-operacoes/projetos/2026-09-seminario-atm/concepcao.md` (repo gp-operacoes) seção 5): usar os dois.

Nota fixa do Resumo (`OH:7900-7904`): "Não identificado" = pessoa inscrita com e-mail ou telefone diferente do da lista disparada.

## 3. Modal de ingresso no grupo (referência: ATM 2, `openSematm2IngModal`, `OH:8204-8348`)

Abre por três cards (Ingressos, % ingresso, Evasão), com título correspondente.

- **Contador:** "N entraram · N no grupo · N saíram".
- **Aba "Evolução"** com alternador Quantidade | Porcentagem. Séries de quantidade: Leads, Entraram, Saíram, No grupo. Séries de %: % ingresso (dia), % ingresso (acum.), % evasão (acum.). O eixo do tempo é a união dos dias com lead, entrada ou saída.
- **Tabela da Evolução:** Data, Leads, Entraram, Saíram, % ingresso (dia), % ingresso (acum.), % evasão (acum.), No grupo.
- **Fórmulas diárias** (`OH:8230-8246`):
  - % ingresso (dia) = ingressos do dia ÷ leads do dia × 100. Pode passar de 100%. Sem lead no dia, traço.
  - % ingresso (acum.) = ingressos acumulados ÷ leads acumulados × 100.
  - % evasão (acum.) = saídas acumuladas ÷ entradas acumuladas × 100.
  - No grupo = entradas acumuladas menos saídas acumuladas.
- **Aba "Quem entrou (N)":** Entrou em, Nome, E-mail, Telefone, Source, Status (No grupo ou Saiu), É lead? Uma linha por número único, fecha com o card. Quem entrou por link encaminhado fica com "É lead?" = NÃO.
- **Aviso âmbar** se a aba de ingressos tiver mais de uma campanha. Nada é filtrado, só sinalizado. O caso real: uma linha de 03/07 da campanha "ELAINE ATM", de outro evento.

**Regra do log do grupo (`L2:307-380`):**
- Colunas da aba: B = data em horário de Brasília, C = campanha, E = número, F = evento. A coluna A tem linhas em UTC e **não deve ser usada**.
- Entrada conta **uma vez por chave** (a primeira); estado vira "dentro".
- Saída só conta se a chave já tinha entrado e o estado atual não é "fora"; estado vira "fora".
- **Estado final é o do último evento.** Evadidos = chaves com estado final "fora". `membros ativos = added − removed`. Em 03/09 isso corrigiu a evasão do ATM 2 de 50% para 0%.
- `byDay_saidas` conta só a saída que muda o estado de dentro para fora, e pode somar diferente do total de saídas.
- A aba `Cópia de Ingressos Whatsapp` existe e **não deve ser usada**.

## 4. Abas de disparo: API, Grupo, SMS, Ligação (Ligue Lead), E-mail

Subabas logo abaixo dos cards (`SEMATM_CANAIS`, `OH:6996`; renderização `OH:7716-7840`).

**Cards por canal na referência ATM 2** (`OH:7753-7761`): Disparos, Enviados; Entregues e % Entrega, se existirem; Abertos, ou Lidas (quando não há entregues), ou Atendidas (Ligue Lead); Cliques; Falhas; Custo, se existir. **O ATM 2 não tem cards de % abertura nem % clique.** O ATM 1 tem "% Clique" (`OH:7099`).

**Tabela:** Data, Campanha, Copy/Lista, Status, Enviados, [Entregues], Abertos/Lidas/Atendidas, Cliques, Falhas, [Custo]. Disparos agrupados por etapa (segmento), com subtotal de enviados e custo. A copy abre num modal.

**Totais** (`D2:326-337`), sempre recalculados pela soma, nunca pela porcentagem da planilha, com 1 casa:
- `pct_entrega = entregues ÷ enviados × 100`
- `pct_abertura = abertos ÷ enviados × 100`
- `pct_clique = cliques ÷ abertos × 100` (atenção: **denominador é abertos**, não enviados)
- Taxa nula se o denominador for 0.

| Canal | Fonte na referência ATM 2 | Observações |
|---|---|---|
| API | planilha de custos `1BgIF7dV82t6CyDgw2lKwhRtk6sH-h9BUsPJaLr9rz98`, aba `Custos de mensageria`, A1:Z200 (`D2:172-173`) | blocos detectados por título (`D2:203-228`). **Infobip e Unnichat viram o canal "api"** e mantêm o campo `provedor` (`D2:181-187`) |
| SMS | mesma aba | Ligue Lead com `Tipo` contendo "sms" vai para SMS (`D2:271-274`) |
| Ligação (Ligue Lead) | mesma aba | rótulos "Atendidas" e "% Atendidas" |
| Grupo | planilha `SEM ATM - SET26 - MENSAGERIA` `1eIGzhXQHZme4svWldjDsbmEzcc45lNutTypFhbNkssc`, aba `GRUPO` (`D2:43`, `D2:62-65`) | sem custo |
| E-mail | mesma planilha, aba `EMAIL` ou `EMAIIL` (a primeira com disparo vence) | sem custo |
| Confirmação de inscrição | abas `E-MAIL - CONFIRMAÇÃO DE INSCRIÇÃO` e `API - CONFIRMAÇÃO DE INSCRIÇÃO` (`D2:70-73`) | **entra no total de custo, mas não aparece nas abas de canal** (`D2:520`) |

- Colunas lidas **pelo nome do cabeçalho**: Data, Hora, Campanha ou Ação, Lista de destinatários, Copy, Template, Tipo, Enviadas/Enviado/Enviados/Leads, Entregues/Entregue/Processados, Lido/Lidas/Abertos, Clicado/Cliques, Falha/Falhas, Taxa de entrega, Custo (`D2:251-264`). Cabeçalho do Grupo e do E-mail é procurado nas linhas 1 a 8 (`D2:120-139`).
- A **copy** vem da anotação (nota) da célula, não do texto (`D2:277-279`).
- Recorte: disparos a partir de 01/09/2026 (`D2:46`, `D2:269`, `D2:409`). **Não existe recorte por ATM**: as planilhas são exclusivas de cada ATM. No dashboard novo o recorte é pela chave do projeto (`atm-elaine-1-2026-10`).
- Cache de 300 s; resultado vazio não é gravado (`D2:552`).

**Diferenças do ATM 1 (julho)** (`D1`): planilha `19kgntj4-jqkvTyfepekvC6DV-rhMZ3z3nVL_flfE9UQ`, abas `API`, `GRUPO`, `SMS`, `LIGAÇÃO`, `EMAIIL` (grafia com dois I) e as de confirmação, cabeçalho na linha 4 e dados da 5 em diante, colunas por posição (0 Data, 1 Evento, 2 Objetivo, 3 Lista, 4 Copy, 5 Horário, 6 Agendado, 7 Status, 8 Enviados, 9 Entregues, 10 %Entrega, 11 Abertos, 12 %Abertura, 13 Cliques, 14 %Clique, 15 Falhas, 17 Tipo). Custo por posição: API col 21, SMS col 20, LIGAÇÃO col 21. Sem recorte por data. No e-mail, os segmentos "Reativação" e "By the Way" viram uma linha-resumo por dia ("DIA N") com modal de Abriu/Clicou/Resto; nesse modal % abertura e % clique usam `entregues`, e o total do canal usa `enviados`, uma inconsistência da referência. O card "Custo com disparos" do ATM 1 diz "API e Ligação" no rótulo mas soma também SMS (`D1:37-41`, `D1:171`).

## 5. Comparecimento (referência: ATM 1 de julho)

Só o ATM 1 tem. Tela: aba interna "Comparecimento" do ATM 1 (`OH:8358-8417`). Endpoint `C1`.

**Fonte:** planilha `1RtcEbm9ybVIc7CVXgf3hzTRvsbpgEQsxYaUaFLMSY4E` ("[SEM ATM - JUL/2026] VENDAS SESSÃO DE VIABILIDADE"), abas `Comparecimento` (Dia 1) e `Comparecimento - Repeteco 17-07` (Dia 2). A planilha é **montada à mão** (`C1:6`) e o endpoint não calcula nada: ele lê pelos rótulos "leads", "grupo", "pico", "equipe", "vendas" o valor da linha de baixo (`C1:73-90`). **As fórmulas abaixo foram conferidas olhando as células da planilha** (modo fórmula), em 08/10:

| Número | Fórmula na planilha | Origem do valor |
|---|---|---|
| Leads (base) | valor digitado (célula C3) | **manual** |
| Grupo (base), "entraram no grupo" | valor digitado (célula D3) | **manual** |
| Equipe na sala | valor digitado (célula F3) | **manual** |
| Pico de audiência | `=MAX(J2:J15) - F3`: maior valor da série de audiência por minuto (coluna J) **menos a equipe** | série de audiência colada à mão |
| Vendas no evento | Dia 1: valor digitado (G3). Dia 2: `=COUNTIFS('Vendas Aprovadas'!A2:A; ">="&DATE(2026;7;17)+TIME(11;0;0))`, ou seja, vendas aprovadas com data a partir de 17/07 às 11h | Dia 1 manual; Dia 2 contado da aba de vendas |
| Comparecimento (leads) | `=E3/C3` = pico ÷ leads | derivado |
| Comparecimento (grupo) | `=E3/D3` = pico ÷ grupo | derivado |
| Conversão (leads) | `=G3/C3` = vendas ÷ leads | derivado |
| Conversão (grupo) | `=G3/D3` = vendas ÷ grupo | derivado |
| Conversão (pico) | `=G3/E3` = vendas ÷ pico | derivado |

- Na tela as taxas saem com 2 casas. O sub-rótulo de "Pico de audiência" mostra "máx. ao vivo", o maior valor da série calculado no front (`OH:8379`). **O pico da planilha (já descontada a equipe) e o máximo da série são dois números diferentes**, e a tela mostra os dois.
- A série tem linhas HH:MM; audiência na coluna seguinte e retenção (campo `variacao` na API) na próxima. Retenção verde se maior ou igual a 100, vermelha se menor (`C1:91-98`).
- Dia 1 e Dia 2 têm abas separadas. Cache de 30 min.
- **A venda do comparecimento vem da planilha de comparecimento (Dia 1 digitado, Dia 2 contado), não da Hotmart.**
- **No banco**, os insumos que hoje são digitados precisam de fonte: audiência por minuto (Zoom? YouTube? a referência não diz de onde vem a série; é colada à mão), pessoas da equipe na sala, e as janelas de venda do evento. Isso é decisão nova.

Cards na ordem da tela (nomes exatos): Pico de audiência · Comparecimento (leads) · Comparecimento (grupo) · Leads (base) · Grupo (base) · Equipe na sala · Vendas no evento · Conversão (leads) · Conversão (grupo) · Conversão (pico).

## 6. Vendas, retorno e home no ATM 2

- **Modal de vendas:** abas Compradores e Resumo. Colunas: Data, Nome, E-mail, Telefone, Cidade, UF, SCK, Pagamento (`OH:8112`). Donuts "SCK (origem da venda)" e "Estado (UF)". Colunas de origem na planilha: B nome, D e-mail, E+F telefone, H cidade, I estado, Q oferta, S pagamento, Y SCK (`L2:128-137`). SCK vazio ou "-" vira "Não identificado". Estado por extenso vira sigla (`L2:84-97`).
- **Tela de retorno** (`retorno-sematm.html`, usa `R2`): cards Vendas e Faturamento líquido. `bruto = vendas × 1500`, `liquido = vendas × 1416.99`, `ticket = 1416.99` (`R2:125-127`). `compradores` = CPFs únicos (coluna C, só dígitos), com fallback para o nº de vendas (`R2:103`, `R2:120`). O feed mostra as 12 últimas vendas como "Primeiro nome + inicial do sobrenome" e estado. Cache de 5 s.
- **Home (SV):** `app.js:1085-1190`. Investimento = custo de disparos; faturamento = líquido; CAC = investimento ÷ vendas. Forma de pagamento classificada por texto: PIX, BILLET/BOLETO, o resto vira crédito. Os "picos das lives" `[127, 62, 40]` estão **fixos no código** (`app.js:1117`) e a fonte não foi encontrada.
- **Zoom:** só o ATM 2 tem o botão "Sala do Zoom". Não registrei dados de acesso.

## 7. Diferenças entre ATM 1 (julho) e ATM 2 (setembro)

| Tema | ATM 1 | ATM 2 |
|---|---|---|
| Leads | aba `Leads`, conta linhas (`L1:122`, `L1:141-151`) | aba `Leads Seminário ATM 2 - Set/26`, mesma planilha, conta linhas |
| Ingresso | conta **linhas** do log (`L1:185-196`) | conta **números únicos** |
| Evasão | `removidos ÷ added` por linha (`L1:204`) | estado final / último evento |
| "No grupo (por lead)" | vem da coluna digitada, não fecha com o card | corrigido para fechar com o log |
| Planilha de vendas | `1RtcEbm9...` | `1atIgGVu...` |
| Faturamento | só líquido, front, `1417.01` | bruto `1500.00` e líquido `1416.99`, backend |
| Cards | sem CPL e sem Bruto | com CPL e com Bruto |
| Comparecimento | tem | não tem |
| Retorno | não tem | tem |
| Modal de leads | sem aluno, lista, professor, filtro | com os três e filtro cruzado |

## 8. O que existe no Drive do ATM de outubro (só leitura, 08/10/2026)

Pasta `1SAbapDpb8Ll6XxguMNKV3OSlRQcMU1Wb` ("Seminário ATM 1 - Outubro"). Estrutura de pastas: `00 - DOCUMENTAÇÃO`, `01 - PRÉ-EVENTO` (`01.1 - AUDIOVISUAL`, `01.2 - TRÁFEGO`, `01.3 - WEB`, `01.4 - DISPAROS`, `01.5 - VENDAS`), `02 - EVENTO`, `03 - PÓS-EVENTO`. Só `00`, `01.1` e `01.4` têm arquivos.

| Item | Situação |
|---|---|
| `[ATM 1 - OUT/2026] CONCEPÇÃO E CRONOGRAMA` (Doc, id `1v72nnT9uOx6Ktj0TESY4uf4L6PbLAj0iyvFqkYucHLA`) | existe; **não li o conteúdo**. A cópia da concepção no cérebro é `gp-operacoes/projetos/2026-10-atm-elaine-1/concepcao.md` (repo gp-operacoes) |
| `[SEM ATM - OUT/26] Lista 1 - Base fria` (planilha `1a3zFoWDqqr__9LYFvgK8IRtPDnnnLa4WgJAoLG2ReVM` + CSV) | existe. Abas `Resumo` (Etapa, Pessoas), `Contatos` e `Descartados`. Cabeçalho de `Contatos`: Nome, E-mail, Telefone, Base, Lista, Seminário, Edição (o campo **Seminário** é o "seminário de origem") |
| `[SEM ATM - OUT/26] Lista 2 - Base quente (by the way)` (planilha `1HtTnGdkEOmkoxdMbSL4bto5o535uK_YQnqATS9p56aw` + CSV) | existe. Abas `Resumo`, `Todos contatos`, `Contatos com telefone válido` e `Descartados`; mesmo cabeçalho |
| `Seminário ATM - OUT/26` (planilha `1Fru8SXmEUHVb5qe6OmMJ5roTvGxmnPvq3y9669EXPMs`) | é a planilha de DISPARO citada no briefing. Abas `Custos de mensageria`, `e-mail`, `Grupos (SendFlow)` e `Grupos antigos (SendFlow)`. **Confirmado: o conteúdo é de SET/26** (títulos "SEM ATM SET/26", datas de 03 a 08/09/2026). Nada de outubro lançado ainda |
| `[SEMATM OUT/26] MENSAGERIA` (planilha `16OpTLTYBTlfaZZx93O6w-XUpQHhqOWIlWagTwiwqhP0`) | **não citada no briefing.** Modelo da mensageria do dashboard-ht, com abas `DASHBOARD`, `GRUPO`, `EMAIIL`, `API`, `LIGAÇÃO`, `SMS`, `EMAIL`, `LINKS`, `LOG_SENDHOOK`, `CAMPANHAS_CONFIG`, `SENDFLOW_CONFIG`. **Os dados são de JUL/26** (datas de junho e julho), então é um template reaproveitado, não o ATM de outubro |
| Leads da captura (planilha `1jp6c6elF0Po85aWp1xY9D5ndt_j6SFomWBnC4iZFDzQ`, aba `Leads`) | citada no briefing; **não está nessa pasta** e não foi aberta por mim |
| Pastas `01.2 - TRÁFEGO`, `01.3 - WEB`, `01.5 - VENDAS`, `02 - EVENTO`, `03 - PÓS-EVENTO` | vazias |
| `01.1 - AUDIOVISUAL` | vídeos (estudo de caso e a playlist "CPLs de Setembro") |

Conclusão: **não existe ainda nenhum dado do ATM de outubro** (disparo, comparecimento, vendas, leads) no Drive do projeto. Só as duas listas de público e os documentos de concepção. As planilhas de mensageria existentes carregam dados de julho e setembro, com o risco de o dashboard novo ler o evento errado se o recorte pela chave do projeto não for aplicado.

Não toquei em nenhum arquivo do Drive.

## 9. Pendências e perguntas para o Victor (decisões novas, não cópia)

1. Definição de **ciclo aberto** e **ciclo fechado** de vendas (ponto 0.1).
2. Definição da **Lista 2** (pré-checkout x checkout, ponto 0.6) e de "menos quem reagiu ao último ATM": qual é a base "reagiu" e qual é o ATM anterior.
3. **Preço da venda**: bruto e líquido vêm de onde (ponto 0.3).
4. Card "Disparos" na Visão Geral: soma de quais canais.
5. **Denominador** da taxa de conversão do pré-checkout: pessoas únicas ou aberturas.
6. **Fonte do comparecimento**: série de audiência por minuto, pessoas da equipe e janela de venda do evento. Na referência tudo isso é digitado à mão.
7. Dedup de leads: a referência conta linha, não pessoa.

## 10. Inconsistências da referência que não devem ser copiadas

- `L1`, `D1`, `OH:3167-3169` e comentários do `L2` ainda falam de "planilha ainda não criada" ou citam a planilha antiga, mas o código já usa as planilhas atuais.
- % abertura do modal de e-mail do ATM 1 usa `entregues` e o total usa `enviados`.
- Rótulo "API e Ligação" no custo do ATM 1 não bate com o que é somado (inclui SMS).
- Os totais de saída diária (`byDay_saidas`) podem diferir do total de saídas por causa de quem saiu e voltou.

## Situação deste documento

Só documentação. Nenhuma migration escrita, nenhum banco tocado, nenhum arquivo da referência alterado. Os números de linha citados são do commit `857100a` do dashboard-ht e podem se deslocar se o repo mudar.
