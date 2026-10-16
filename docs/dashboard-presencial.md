# Dashboard de evento presencial para a base (banco)

Modelo `presencial-base`, primeiro uso: **Clínica de Miami** (`clinica-miami-2026-12`, sigla CNFMIAMI26, `mkt.projetos`
id 68). Pedido do Victor Hugo em 07/10/2026. A tela (Infra > Dashboards > CSM) está em
`docs/dashboard-presencial-tela.md`; este arquivo é o lado do banco.

**Situação (07/10/2026):** migrations APLICADAS em produção (seção 3).
Nada publicado: a tela e a rota de captura estão só na branch `victor-captura-pre-checkout`.

## 6. Abas de Diamantes e Fichas de interesse (09/10/2026)

Na branch `victor-miami-abas`, os cards do dashboard da Clínica Miami seguem a ordem: Pré-checkout, Vendas,
Conversão, Receita, CAC, Custo por disparo e Custo por pré-checkout. As abas **Diamantes** e **Fichas de interesse**
são exibidas somente para a chave `clinica-miami-2026-12` e carregam sob demanda pelas RPCs `dados_miami_diamantes`
e `dados_miami_interesse`. O banco aplicou as funções em `20261009190000` em 09/10/2026; a carga e publicação do
webhook do Respondi continuam com o Galego.

A aba Diamantes exibe a lista de nomes de Diamantes, totais de respostas por situação e as respostas de participação,
viagem e acompanhantes. A aba Fichas de interesse separa quem preencheu e comprou de quem preencheu e NÃO comprou; a
segunda lista fica destacada para acompanhamento do time. A compra é conferida por e-mail e telefone nas ofertas
indicadas no pedido.

Diamantes mostra uma linha por nome da lista oficial e uma por resposta que não casou com a lista, incluindo as
respostas mais recentes e os campos de viagem. Fichas de interesse separa `comprou = false` para a lista destacada
“Preencheram e NÃO compraram” (inclui ausência de transação ou status não pago) e `comprou = true` para as compras pagas das ofertas
`sju5pawn` e `mjzv4v0s`; o casamento vem pronto do banco por e-mail ou telefone. As duas visões exibem texto exato do
formulário e não consultam planilhas.

O front trata falha das RPCs sem derrubar o dashboard e preserva o último resultado válido. Formulário ainda não
cadastrado para a chave retorna zero linhas; erros de acesso e chave ausente são mostrados pela camada de dados.

Para testar localmente: `cd web && npm run dev -- -p 3001`, abra o dashboard com a chave acima e confira a ordem dos
cards e as abas. Nesta entrega usei a porta `3003` porque a `3001` já estava ocupada. O teste local com a conta QA
redirecionou para a página inicial porque o perfil estava sem acesso à Infra; ainda falta conferir a tela com uma
conta que tenha acesso ao dashboard.

## 1. Como funciona

- `dados.dashboards` guarda um dashboard por chave da casa (`mkt.projetos.etiqueta_clickup`): modelo, projeto, conta
  Hotmart, oferta e lista do ActiveCampaign. RLS ligada, sem policy, sem grant: ninguém lê direto pela API.
- As 5 funções `public.dados_presencial_*` são `security definer`, `search_path = ''`, executáveis só por
  `authenticated` (nem `anon`, nem `public`). Primeira coisa: quem não é equipe recebe 42501; chave fora de
  `dados.dashboards` ativa recebe P0002.
- Equipe = `public.gp_eh_equipe()` (perfil ativo com e-mail `@advmais.com`). Decisão do Victor: toda a equipe vê,
  inclusive nome, e-mail e telefone de lead e comprador, por enquanto.
- Ajudantes internos, sem grant: `dados.cadastro`, `dados.pode_ver`, `dados.transacoes`, `dados.pre_checkout`,
  `dados.perfil`.

### Cadastrar outro evento do mesmo modelo

```sql
insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac)
values ('<chave-da-casa>', 'presencial-base', <mkt.projetos.id>, 'academy', '<oferta Hotmart>', '<id da lista no AC>');
```

E a entrada no manifesto da tela (`web/modules/infra/dados/domain/registro.ts`). Nada de função nova.

## 2. Contrato (nomes, colunas e ordem exatos)

Todas recebem `p_chave text`. `null` = sem dado / não lançado / sem fonte; zero = zero medido. Dinheiro de venda em
reais `numeric(14,2)`; custo de disparo em centavos `bigint`; percentual `numeric(7,2)` de 0 a 100; dia em `date` no
fuso de São Paulo. E-mail sempre `lower(btrim())`. Pessoa = e-mail único.

### 2.1 `dados_presencial_resumo` (1 linha)

`chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, evento_inicio date, evento_fim date,
oferta_codigo text, disparos_qtd integer, disparos_sem_custo integer, custo_disparo_centavos bigint,
custo_completo boolean, pre_checkout_pessoas integer, custo_por_pre_checkout_centavos bigint, vendas integer,
vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pct numeric,
receita_bruta numeric, receita_liquida numeric, cac_centavos bigint, atualizado_em timestamptz`

- `custo_disparo_centavos`: soma de `mkt_mensageria.disparos.custo_centavos` dos disparos não arquivados do projeto;
  `null` se nenhum tem custo lançado. Custo estimado não entra.
- `custo_completo` = tem disparo e todos têm custo. Sem isso, `custo_por_pre_checkout_centavos` e `cac_centavos` vêm
  `null` (nunca número parcial).
- `vendas`: transações pagas (APPROVED, COMPLETE) da oferta, 1ª cobrança (`recorrencia` nula ou 1), qualquer moeda.
  `vendas_fora_brl`: dessas, quantas não são BRL.
- `compradores`: e-mails únicos com venda paga. `conversao_pct` = compradores ÷ pré-checkout × 100 (pedido do Victor);
  `compradores_no_pre_checkout` é o número alternativo (compradores que passaram pelo pré-checkout).
- `receita_bruta`/`receita_liquida`: só BRL, todas as cobranças pagas. Bruto = `coalesce(valor_base, bruto_json
  purchase.hotmart_fee.base, valor_cobrado)`; líquido = `coalesce(liquido_produtor, bruto - taxa_hotmart)` (mesma regra
  de `mkt_trafego.receita_vendas`).

### 2.2 `dados_presencial_leads` (1 linha por e-mail, `primeiro_em desc`)

`email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text, utm_medium text,
utm_campaign text, utm_content text, utm_term text, instrucao text, turma text, comprou boolean`

- Pré-checkout = evento `pre_checkout` em `pessoas.eventos` do projeto (`projeto_id` ou `detalhe.chave_evento` = chave)
  **mais** entrada na lista do ActiveCampaign do dashboard (`crm.evento_jornada.lista`, hoje `614`).
- `fonte`: `sistema`, `activecampaign` ou `ambos`.
- `nome`/`telefone`: o mais recente não vazio (telefone do lead vem de `pessoas.identificadores`; quem só entrou pelo
  ActiveCampaign e não tem telefone na base fica `null`).
- UTMs: da primeira passagem **pelo sistema** (`pessoas.origens`). O ActiveCampaign não traz UTM, então lead só do
  ActiveCampaign tem UTMs `null`.
- `instrucao`: `public.thb_alunos.instrucao`, string exata (`null` = não é aluno). `turma`: `public.thb_turmas.codigo`.
- `comprou`: tem venda paga da oferta.
- Fica de fora quem é teste: `pessoas.pessoas.teste = true` ou e-mail `@exemplo.invalid`. Teste interno feito sem
  essas marcas (ex.: colaborador entrando na lista 614 com o próprio e-mail) **conta**.
- **Desde a `20261007220043` (§2.10):** a lista traz também quem é teste, com duas colunas novas no fim,
  `pessoa_id uuid, teste boolean`; os números continuam sem eles.

### 2.3 `dados_presencial_vendas` (1 linha por transação, `coalesce(dia_aprovado, dia_pedido) desc`)

`transacao text, status_grupo text, status_hotmart text, dia_pedido date, dia_aprovado date, moeda text,
valor_bruto numeric, valor_liquido numeric, email text, nome text, telefone text, estado text, instrucao text,
turma text, no_pre_checkout boolean, entrou_grupo boolean, grupo_fonte text`

- Todas as transações da oferta na conta do dashboard, todos os status (a tela filtra; padrão `pago`).
- `status_grupo`: `pago`, `estornado`, `atrasado`, `em_aberto`, `recusado`, `expirado`, `outro` (mesma régua de
  `fin.vw_transacoes_contas`). `status_hotmart`: status original.
- `valor_liquido` sai calculado mesmo fora de `pago` (bruto menos taxa); só vale como receita quando `pago`.
- `telefone` = `comprador_telefone`, `estado` = `comprador_uf` da Hotmart.
- `entrou_grupo` sempre `null` e `grupo_fonte` sempre `'sem_fonte'`: não há grupo da Clínica no banco.

### 2.4 `dados_presencial_disparos` (1 linha por disparo, mais recente primeiro) — SUBSTITUÍDA NA TELA em 16/10/2026

> A tela não chama mais esta função: a Visão de disparos passou a ler `dados_presencial_disparos_canais` e `dados_presencial_disparos_lista` (§2.13). A função antiga continua no banco, sem uso no front; reverter a tela é voltar o commit da §2.13.4.

`disparo_id bigint, dia date, nome text, canal text, ferramenta text, tamanho_lista integer, entregues integer,
lidas integer, cliques integer, falhas integer, custo_centavos bigint, entrega_pct numeric, leitura_pct numeric,
clique_pct numeric`

- `mkt_mensageria.disparos` do projeto, não arquivados. `dia` = `enviado_em` em São Paulo; `nome` = `campanha`;
  `canal` = código (`whatsapp_api`, `email`, `sms`, `ligacao`, `grupo`); `ferramenta` = `mkt_mensageria.ferramentas.nome`.
- Não existe coluna "enviadas": a tela mostra `tamanho_lista` como "Tamanho da lista".
- Taxas: entregues ÷ tamanho; lidas ÷ entregues; cliques ÷ entregues. Divisor 0 ou nulo = `null`.
- Formato do ATM para a tela: ver §2.13.
- Para o disparo entrar: projeto escolhido no cadastro manual da Mensageria ou campanha com `[CNFMIAMI26]` na integração.

### 2.5 `dados_presencial_serie_diaria` (1 linha por dia, sem buraco, do 1º dia com dado até hoje)

`dia date, pre_checkout integer, pedidos integer, vendas integer, abandonos integer`

- `pre_checkout`: e-mails que entraram pela primeira vez no dia. `pedidos`: e-mails únicos com transação da oferta
  criada no dia (qualquer status). `vendas`: vendas pagas pela data de aprovação.
- `abandonos` sempre `null`: o webhook da Hotmart não recebe o produto 6489980.
- Sem nenhum dado: 0 linhas.

### 2.6 Erros

| código | quando |
|---|---|
| `42501` | não é equipe (ou `anon`: "permission denied for function") |
| `P0002` | chave fora de `dados.dashboards` ativa |
| `PGRST202` | função não existe no banco (PostgREST) |

## 2.7 Oferta nova da Clínica de Miami (07/10/2026)

A Clínica vende em duas ofertas: `sju5pawn` ("Clínica de Holding Familiar - Miami", produto `5682989`, conta academy,
5014.2 BRL), a principal desde 07/10/2026, e `mjzv4v0s` (produto `6489980`), a antiga, com 1 pedido de teste.
`dados.dashboards` ganhou `ofertas_extra text[]`: as funções `dados_presencial_*` somam a `oferta_codigo` e as extras
(mesma conta). Contrato da tela sem mudança (o `resumo.oferta_codigo` passa a ser `sju5pawn`). Para um evento com mais de
uma oferta: `update dados.dashboards set ofertas_extra = array['<oferta>'] where chave = '<chave>'`. Migration
`20261007203803`.

## 2.8 Venda em tempo real (07/10/2026)

Antes, a venda só aparecia quando o `hotmart-sync` passava (de hora em hora, minuto 7): atraso medido de 28,9 min na
mediana e até 59,5 min. Desde a `20261007205017`, `dados.transacoes` também lê `cs.hotmart_eventos` (o log do webhook da
Hotmart, gravado em mediana 15 s depois da aprovação) para as transações das ofertas do dashboard que o espelho ainda não
tem. Quando o sync traz a transação, vale a linha do espelho: nada conta duas vezes. Contrato da tela sem mudança.

- Vale para a conta **academy** (a única que o webhook recebe). Pedido aguardando pagamento (Pix/boleto) não gera evento
  e continua vindo pelo sync.
- Nome, telefone e UF da linha do webhook vêm do checkout e podem mudar quando o sync passar.
- A tela refaz resumo e série diária a cada 60 s enquanto a aba do navegador está visível. Ao voltar para a aba,
  atualiza imediatamente. Assim a venda recebida pelo webhook aparece sem clique, depois da próxima leitura da tela.
  O polling não chama disparos, leads ou vendas, que são consultas mais pesadas. Uma leitura só começa depois de a
  anterior terminar. Em caso de falha, cada bloco mantém seu último dado válido e mostra aviso. O horário
  "Atualizado às HH:MM:SS" indica a última leitura em que resumo e série responderam com sucesso.

### Testar a atualização da tela

No repo, entrar em `web` e rodar `npm run dev -- -p 3001`. Abrir `/infra/dashboards/csm/clinica-miami-2026-12`
com uma conta autorizada. Conferir o horário, esperar 60 s com a aba visível e conferir novo horário sem piscar os
cards. Deixar a aba oculta por mais de 60 s: não deve haver leitura periódica; ao voltar, resumo e série devem
atualizar. No painel de rede, `dados_presencial_disparos_canais`, `dados_presencial_disparos_lista`, `dados_presencial_leads` e `dados_presencial_vendas` não
devem aparecer por causa do polling. Em falha de uma leitura, os dados anteriores daquele bloco devem continuar
visíveis com aviso; não substituir ausência por zero. O botão Atualizar continua permitindo recarregar também as abas
sob demanda.

Detalhe, tradução de status e ensaio: `infra/supabase/migrations/20261007205017.explain.md`.

## 2.9 Gráficos da "Visão geral de vendas" (migration `20261007212530`, APLICADA em 07/10/2026)

Seis funções novas, todas `p_chave text` (mais `p_grupo` no modal), mesmo gate e mesmos erros do §2.6 (42501 sem acesso,
P0002 chave fora do cadastro). As 5 de antes não mudam. Consideram as ofertas do dashboard (`oferta_codigo` +
`ofertas_extra`) e o caminho em tempo real do §2.8. Venda = paga e primeira cobrança; receita = bruto pago em BRL (iguais ao
resumo: os totais de cada gráfico batem com `dados_presencial_resumo`).

### 2.9.1 `dados_presencial_pagamentos(p_chave)` (1 linha por forma + parcelas, mais vendas primeiro)

`forma text, forma_nome text, parcelas integer, vendas integer, receita_bruta numeric`

- `forma`: nome da Hotmart (`CREDIT_CARD`, `PIX`, `BILLET`, `HOTMART_INSTALLMENTS`, `FINANCED_BILLET`, `HYBRID`, `WALLET`,
  `APPLE_PAY`, `GOOGLE_PAY`, `SAMSUNG_PAY`, `PAYPAL`, `DIRECT_DEBIT`, `CASH_PAYMENT`; sem dado: `NAO_INFORMADO`).
- `forma_nome`: Cartão de crédito, Pix, Boleto, Parcelado Hotmart, Boleto financiado, Híbrido, Saldo Hotmart, Apple Pay,
  Google Pay, Samsung Pay, PayPal, Débito em conta, Pagamento em dinheiro, Não informado; forma nova sai com o nome da Hotmart.
- Rosca por forma = somar `vendas` por `forma`; `parcelas` serve para o detalhe (ex.: cartão em 12x).

### 2.9.2 `dados_presencial_compradores_perfil(p_chave)` (roscas de turma e instrução)

`dimensao text, valor text, compradores integer`

- `dimensao = 'turma'`: `valor` = código da turma (`T41`...), `Aluno sem turma` ou `Não é aluno`.
- `dimensao = 'instrucao'`: `valor` = `thb_alunos.instrucao` como está na base (THB, THB - SÓCIO, AURUM...), `Aluno sem
  instrução` ou `Não é aluno`. É o programa do aluno, não escolaridade (escolaridade não existe em nenhuma fonte).
- `dimensao = 'casamento'`: `email`, `documento`, `telefone` ou `nao_casou` (para mostrar como a base foi casada).
- Comprador único por e-mail. Casa com `public.thb_alunos` por e-mail, senão documento, senão telefone. A coluna
  `turma`/`instrucao` de `dados_presencial_vendas` casa só por e-mail: pode diferir para quem casou por documento ou telefone.

### 2.9.3 `dados_presencial_pendencias(p_chave)` (cards de não pago e canceladas)

`grupo text, categoria text, pessoas integer, transacoes integer`

- `grupo = 'nao_pago'` (boleto/pix gerado e não pago: `PRINTED_BILLET`, `WAITING_PAYMENT`): `categoria` `boleto`, `pix`,
  `outro` e `total`.
- `grupo = 'cancelada'` (`CANCELLED`, `REFUNDED`, `PARTIALLY_REFUNDED`, `CHARGEBACK`, `EXPIRED`): `categoria` = o status
  da Hotmart e `total`.
- Sempre vêm as duas linhas `total`, mesmo zeradas. `pessoas` = e-mails únicos; use a linha `total` no card (a mesma pessoa
  pode estar em duas categorias).
- Regra do Victor: quem pagou outra transação das ofertas do dashboard (mesmo e-mail ou mesmo documento) não entra.

### 2.9.4 `dados_presencial_pendencias_pessoas(p_chave, p_grupo)` (modal; único com dado pessoal)

`email text, nome text, telefone text, categorias text, transacoes integer, valor_bruto numeric, ultimo_em timestamptz`

- `p_grupo`: `'nao_pago'` ou `'cancelada'`; outro valor dá 22023. 1 linha por pessoa, mais recente primeiro.
- `categorias`: as categorias da pessoa separadas por vírgula; `valor_bruto` e `nome`/`telefone`: da transação mais
  recente. Número de linhas = `pessoas` da linha `total` do grupo.

### 2.9.5 `dados_presencial_serie_vendas(p_chave)` (1 linha por dia, mesmo intervalo da série diária)

`dia date, pre_checkout integer, vendas integer, receita_bruta numeric, vendas_acumuladas integer, receita_acumulada numeric,
conversao_pct numeric`

- `conversao_pct` = vendas do dia ÷ pré-checkout do dia × 100, 2 casas; `null` quando o dia não teve pré-checkout.
- Último `vendas_acumuladas` = `resumo.vendas`; último `receita_acumulada` = `resumo.receita_bruta`.

### 2.9.6 `dados_presencial_vendas_por_hora(p_chave)` (sempre 24 linhas, hora 0 a 23)

`hora integer, vendas integer, receita_bruta numeric`

- Hora da aprovação no fuso de São Paulo.

## 2.10 Marcar lead do pré-checkout como teste (migration `20261007220043`, APLICADA em 07/10/2026)

Card `17tya50fkx9`. Usa `pessoas.pessoas.teste` (o campo do sistema inteiro: quem é teste também sai das estratégias de
disparo do CRM e do resumo do Tráfego, que já liam esse campo).

### 2.10.1 `dados_presencial_leads(p_chave)` muda

Mesmas 13 colunas, mesma ordem, mais duas no fim: `pessoa_id uuid, teste boolean`.

- Lista **todo mundo**, inclusive quem é teste. A tela mostra a linha com `teste = true` apagada, com a etiqueta "teste",
  e não a soma em nada.
- `pessoa_id`: o id que a RPC recebe. `null` quando o lead não tem pessoa ligada (só pode acontecer com quem entrou pela
  lista do ActiveCampaign sem cadastro de pessoa): sem botão.
- `teste`: alguma pessoa ligada àquele e-mail está marcada.
- Pessoa mesclada: a lista devolve a pessoa final (`pessoas.atual`), e a RPC marca e loga sempre a final, mesmo recebendo o
  id antigo. A resposta da RPC traz o `pessoa_id` final.

### 2.10.2 `dados_presencial_marcar_teste(p_chave text, p_pessoa_id uuid, p_teste boolean)` (novo)

Retorna 1 linha: `pessoa_id uuid, teste boolean, alterado boolean`.

- Só master (`acesso.master`: hoje Victor, João Pedro, Arthur e a conta temporária de QA). Não master: 42501 "sem acesso";
  anon não executa.
- `p_teste = true` marca, `false` desmarca. `alterado = false` quando já estava assim (não grava nada).
- Erros: 42501 sem acesso; 22023 `p_pessoa_id` ou `p_teste` nulo; P0002 dashboard não cadastrado, pessoa que não é
  pré-checkout desse dashboard ou pessoa inexistente.
- Grava em `acesso.log` quem marcou (`autor`) e quando, `acao` `marcar_teste`/`desmarcar_teste`, sem dado pessoal.
- Depois de marcar, a tela recarrega o resumo, as séries e a lista.

### 2.10.3 O que para de contar quem é teste

`dados_presencial_resumo` (`pre_checkout_pessoas`, `compradores_no_pre_checkout`, `conversao_pct`,
`custo_por_pre_checkout_centavos`), `dados_presencial_serie_diaria` (`pre_checkout`), `dados_presencial_serie_vendas`
(`pre_checkout`, `conversao_pct`) e `dados_presencial_vendas` (`no_pre_checkout`). O e-mail marcado sai inteiro.

### 2.10.4 A tela (07/10/2026)

- Modal de pré-checkout, aba Leads: coluna **Ação** só para master (`gp_meu_acesso().master`, o mesmo `acesso.eh_master()`
  da RPC; com a flag v2 desligada a página lê `gp_meu_acesso` direto, em `getCurrentUserAccess`). Quem não é master não
  vê a coluna, e a RPC recusa de qualquer jeito (42501).
- **Marcar como teste** pede confirmação ("vale para o sistema todo"); **Desmarcar teste** é direto. Linha marcada fica
  apagada (opacidade 50%) com a etiqueta "teste" ao lado do nome. A aba Resumo do modal ignora quem é teste.
- Depois de marcar ou desmarcar, a lista é relida e os cards são atualizados na hora (sem esperar os 60 s).
- Lead sem `pessoa_id` não mostra o botão. Erros do banco viram mensagem na tela (`mensagemErroTeste`).
- Arquivos: `ModalPessoas.tsx`, `ModalPreCheckout.tsx`, `DashboardPresencialClient.tsx`, `presencial-data.ts`
  (`marcarLeadTeste`), `presencial.ts`, `server-container.ts`, `page.tsx` da rota. Começado pelo JP, terminado pelo
  Maestro quando o JP parou por limite de uso.
- Verificado: tsc, vitest (2403) e build. Não verificado: a marcação real pela tela (o Victor marca os 2 leads de teste dele).

## 2.11 Clínica Miami: abas "Diamantes" e "Fichas de interesse" (migrations `20261009190000` e `20261009190100`, APLICADAS em 09/10/2026)

Pedido do Victor de 09/10/2026. Detalhe técnico, ensaio e segurança: `infra/supabase/migrations/20261009190000.explain.md`.

**Fonte:** `respondi.respostas`. As respostas chegam pelo webhook do Respondi (Edge `respondi-webhook`, em tempo real)
e pelo `respondi-sync` (1x ao dia). Os dois usam o mesmo uuid, então não há duplicata. Os formulários de cada dashboard
ficam em `dados.dashboard_formularios` (`interesse` e `diamantes`), e a Lista Diamantes em `dados.dashboard_lista_pessoas`.

**Acesso e erros (iguais aos outros `dados_*`):**
- Só authenticated: 42501 "sem acesso" para quem não tem permissão do dashboard; P0002 "dashboard não cadastrado".
- Formulário não cadastrado para a chave: 0 linhas, sem erro.
- Textos de resposta: string exata do formulário (null quando a pergunta não foi respondida).

### 2.11.1 `dados_miami_diamantes(p_chave text)`

Uma linha por nome da Lista Diamantes (`respondeu` ou `pendente`) e uma por pessoa que respondeu e não casou com a
lista (`fora_da_lista`). Ordem: `lista_ordem`; as `fora_da_lista` vêm depois, por `respondido_em`.

| Coluna | Tipo | O quê |
|---|---|---|
| `lista_ordem` | int | posição na aba Lista Diamantes (null em `fora_da_lista`) |
| `lista_nome` | text | nome exato da lista (null em `fora_da_lista`) |
| `status` | text | `respondeu`, `pendente` ou `fora_da_lista` |
| `casamento` | text | `nome`, `manual` (por `resposta_uuid_manual`) ou null |
| `resposta_uuid`, `respondido_em` | uuid, timestamptz | resposta usada (a mais recente da pessoa) |
| `n_respostas` | int | quantas respostas a mesma pessoa mandou (por e-mail, senão telefone) |
| `nome_formulario`, `email`, `telefone`, `grupo` | text | como respondido |
| `situacao` | text | exato: "Já estou confirmado(a) e com a viagem organizada." / "Estou me organizando para participar, mas ainda não confirmado(a)." / "Já sei que não irei participar." |
| `situacao_codigo` | text | `confirmado`, `organizando`, `nao_vai` ou null |
| `chegada`, `retorno` | text | texto exato (dd/mm/aaaa) |
| `chegada_data`, `retorno_data` | date | a data, quando o texto é dd/mm/aaaa válido; senão null |
| `aeroporto`, `hospedagem`, `acompanhado`, `acompanhantes` | text | como respondido (`acompanhado`: "Sim" / "Não, irei sozinho(a)") |

Casamento de nome igual ao da planilha: sem acento e sem maiúscula, mesmo primeiro nome, nome menor com 2 ou mais partes
e todas contidas no maior. Quando não casar, preencha `dados.dashboard_lista_pessoas.resposta_uuid_manual` (só banco).

### 2.11.2 `dados_miami_interesse(p_chave text)`

Uma linha por pessoa (e-mail, senão telefone), com a resposta mais recente. Ordem: `comprou` (não comprou primeiro),
depois `respondido_em desc`.

| Coluna | Tipo | O quê |
|---|---|---|
| `resposta_uuid`, `respondido_em`, `n_respostas` | uuid, timestamptz, int | resposta usada e quantas a pessoa mandou |
| `nome`, `email`, `telefone`, `turma` | text | como respondido |
| `passaporte`, `visto`, `planos`, `comprou_passagem`, `data_passagem`, `confirma_pre_venda`, `deseja_programa` | text | textos exatos das perguntas do formulário |
| `comprou` | boolean | true = tem transação **paga** (`status_grupo = 'pago'`) nas ofertas do dashboard (`sju5pawn` e `mjzv4v0s`) |
| `compra_status` | text | null = nenhuma transação; senão o `status_grupo` da melhor: pago > em_aberto > atrasado > estornado > recusado > expirado > outro |
| `compra_transacao`, `compra_em` | text, timestamptz | da melhor transação (`aprovado_em`, senão `pedido_em`) |
| `casou_por` | text | `email`, `telefone` (últimos 8 dígitos) ou null |

"Preencheu e NÃO comprou" é `comprou = false`. Isso inclui sem transação (`compra_status` null) e boleto em aberto,
recusado ou estornado.

### 2.11.3 Webhook do Respondi

- **URL:** a completa, com o segredo, está só no `.env` do cérebro do Victor (`RESPONDI_MIAMI_WEBHOOK_URL`). Nunca no
  repo nem no chat.
- **Formulários a conectar:** "Aplicação Interesse Miami 2026" (`xmaNmRIV`) e "[MIAMI 2026] Dados iniciais"
  (`HFaSnLRf`). Outro formulário recebe 202 e nada é gravado.
- **Situação:** Edge `respondi-webhook` PUBLICADA em 09/10/2026 às 19:07 UTC (pentester APROVADO na 2ª rodada).
  - Testada em produção: sem chave e chave errada dão 401; GET dá 405; formulário fora da lista dá 202; JSON inválido
    dá 400; corpo grande dá 413.
  - Ficha fictícia: grava; o reenvio não duplica; uuid de outro formulário dá 409. A ficha fictícia foi apagada.
- **Como testar:** responder a ficha. Depois `select recebido_em, form_slug, resultado from respondi.webhook_log order
  by id desc limit 5` mostra `gravada`, e a linha aparece na RPC.
- **Números em 09/10/2026 19:05 UTC (depois da carga inicial):**
  - Diamantes: 42 da lista responderam, 34 pendentes e 3 fora da lista. Das 42: 24 confirmados, 6 se organizando e 12 não vão.
  - A planilha mostra 35 e 41 porque não recebeu 14 respostas que o Respondi tem (pela API).
  - Interesse: 31 pessoas, 3 com compra paga.

## 2.12 Clínica Miami: aba "Relatório" copiada da planilha (migrations `20261016240000` e `20261016240100` APLICADAS em 16/10/2026; Edge PUBLICADA)

Pedido do Victor de 16/10/2026 (card 17tya50h3b8): replicar no dashboard o relatório que o time mantém na aba `Relatório` da
planilha "Dados [MIAMI 2026]" (`1MjGDuk32NgcJ7N-ab0oPfk75kwu1pgHoJ3FkCURZCA0`). Detalhe técnico, ensaio e reversão:
`infra/supabase/migrations/20261016240000.explain.md`.

**Situação (16/10/2026, 13:20 a 13:27 UTC):** APLICADA em produção. `20261016240000` às 13:20 UTC, Edge `dados-planilha-relatorio` publicada (versão 1, `verify_jwt=false`), rodada manual com `erro` nulo, `20261016240100` (cron, jobid 361, a cada 5 min) às 13:21 UTC; as rodadas de 13:22 e 13:27 deram HTTP 200. Cópia conferida contra a planilha (Lista Diamantes 76, Compradores da Clínica 13, Presença por evento e Camisas idênticas); pares e `explain` em `infra/supabase/migrations/20261016240000.explain.md` §8 e §10. A tela (front) só aparece depois do push na `main`.

**Como funciona (opção B):** a tela nunca lê a planilha. A Edge `dados-planilha-relatorio` lê a aba a cada 5 minutos com a conta de serviço
(só leitura), transforma em JSON por um leitor puro (`infra/supabase/functions/dados-planilha-relatorio/relatorio-miami.ts`) e guarda a cópia em
`dados.relatorio_planilha`. A tela chama a função `dados_miami_relatorio`. Leitura que falha (Google fora, aba renomeada, título ou cabeçalho
diferente) NÃO apaga a cópia: o banco mantém a anterior e grava o erro (`erro`, `tentado_em`).

**Conta de serviço:** é a do segredo `SHEETS_SA_B64`, `dashboard-eventos@valid-spark-491917-d1.iam.gserviceaccount.com`, a única com leitor
na planilha `[SEMATM OUT/26] MENSAGERIA` que a Edge `mensageria-planilha` já lê. Em 16/10/2026 o Victor compartilhou a planilha
`1MjGDuk32NgcJ7N-ab0oPfk75kwu1pgHoJ3FkCURZCA0` como **Leitor** com ela. Sem esse compartilhamento a leitura volta `google_leitura`.

**Decisão provisória (Victor, 16/10/2026): quem pode ver o dashboard vê e-mail e telefone.** A função só checa `dados.pode_ver`; NÃO filtra por
`contato.ver`. Provisório, a pedido do Victor em 16/10, até a revisão dos níveis de acesso. A resposta traz `contato_visivel = true` fixo para a
tela não precisar mudar quando o filtro voltar (nesse dia, a função passa a limpar e-mail e telefone e `contato_visivel` vira falso para quem não pode).

**Acesso e erros (iguais aos outros `dados_*`):** só authenticated (revoke de public e anon). 42501 `sem acesso` para quem não é da equipe ou não passa em
`dados.pode_ver`; P0002 `dashboard não cadastrado`. Sem cópia ainda (antes da 1ª leitura boa): devolve `disponivel = false`, sem erro.

### 2.12.1 `dados_miami_relatorio(p_chave text, p_md5 text default null)` devolve `jsonb`

Uma chamada por atualização da tela. Passe em `p_md5` o `md5` da resposta anterior: se a cópia não mudou, vem `igual = true` e `conteudo = null`
(a tela mantém o que já tem; o conteúdo tem dezenas de KB).

| Chave | Tipo | O quê |
|---|---|---|
| `disponivel` | boolean | há cópia boa (falso antes da 1ª leitura, ou sem planilha cadastrada) |
| `md5` | text ou null | identifica a cópia |
| `igual` | boolean | `p_md5` é o da cópia (então `conteudo` vem null) |
| `lido_em` | timestamptz ou null | última leitura boa da planilha |
| `tentado_em` | timestamptz ou null | última tentativa, boa ou ruim |
| `erro` | text ou null | código do erro da última tentativa; a cópia anterior continua valendo. Códigos do leitor: `aba_vazia`, `titulo_ausente:<bloco>`, `titulo_duplicado:<bloco>`, `rotulo_ausente:<bloco>:<n>`, `cabecalho_diferente:<bloco>:<n>`; da Edge: `sem_conta_de_servico`, `google_token`, `google_leitura`, `conteudo_invalido`, `banco` |
| `contato_visivel` | boolean | hoje sempre true (decisão provisória acima) |
| `conteudo` | jsonb ou null | ver abaixo |

`conteudo` (`versao` 1; valores sempre o texto formatado da planilha, "—" e "88,2%" ficam como texto, nunca viram número):

```
{ "versao": 1, "aba": "Relatório",
  "avisos": [ { "codigo": text, "texto": text } ],
  "blocos": {
    "dados_iniciais":  { "titulo": text, "itens": [ { "rotulo": text, "valor": text | null } ] },
    "time_formulario": { "titulo": text, "itens": [ ... ] },
    "participacao":    { "titulo": text, "itens": [ ... ] },
    "camisas":     { "titulo": text, "colunas": text[], "linhas": text[][] },
    "presenca":    { "titulo": text, "colunas": text[], "linhas": text[][] },
    "diamantes":   { "titulo": text, "colunas": text[], "linhas": text[][] },
    "compradores": { "titulo": text, "colunas": text[], "linhas": text[][] } } }
```

- Os rótulos de KPI se repetem entre blocos (`% de preenchimento`); ache sempre dentro do bloco. `valor` é null quando a célula está vazia
  (ex.: o rótulo `Situação de quem respondeu` é cabeçalho de um subgrupo e não tem valor).
- `linhas[i][k]` corresponde a `colunas[k]`; a ordem das colunas é a da planilha. `diamantes` tem 22 colunas e `compradores` 16 (as 2 colunas
  auxiliares da planilha ficam de fora). Linha sem valor numa célula vem string vazia, nunca null.
- `avisos`: `diamantes_linhas_menos_que_a_lista` e `compradores_linhas_menos_que_os_compradores` (a tabela por pessoa tem menos linhas do que a contagem do
  próprio relatório; pode haver gente fora da tabela na planilha), as variantes `_ilegivel`, `teto_linhas` (passou de 1.000 linhas por tabela) e `teto_celula`
  (célula acima de 500 caracteres foi cortada). A tela deve mostrar o aviso, não escondê-lo.
- Textos livres (ex.: `Quem acompanha`) vêm como a planilha tem e podem ter nomes de pessoas.

### 2.12.2 Como testar

- Leitor: `cd web && npx vitest run modules/infra/dados/infrastructure/relatorio-miami-parser.test.ts` (24 testes, dados inventados).
- Ensaio no banco (transação desfeita): `20261016240000_ensaio.sql`, pelo executor que só aceita arquivo terminado em `rollback`.
- Depois de aplicar e publicar: chamar a Edge uma vez à mão (`ops.cron_post` ou `curl` com o header `x-sync-chave`, a chave está no Vault
  `dados_relatorio_planilha_chave`; nunca no chat), conferir `select md5, lido_em, erro from dados.relatorio_planilha` e comparar 3 números da tela
  com a planilha (`Pessoas na Lista Diamantes`, `Compradores da Clínica` e uma contagem de `presenca`).

### 2.12.3 O que falta

- Banco e Edge: nada (aplicado em 16/10/2026, ver a situação acima).
- A tela (abas Relatório, Presença por evento, Diamantes e Compradores) está feita e depende do push na `main`; ver `docs/dashboard-presencial-tela.md` (seção "Clínica de Miami: abas da cópia da planilha").
- Revisar o gate de contato quando os níveis de acesso forem revistos (ver a decisão provisória).

## 2.13 Clínica Miami: disparos no formato do ATM (migrations `20261017020500` e `20261017020600`, APLICADAS em 16/10/2026)

Objetivo: a aba de disparos da Clínica reaproveita os componentes do ATM. Para isso o banco entrega a Clínica no mesmo formato.

### 2.13.1 Funções novas (só leitura, `authenticated`, gate `dados.presencial_cadastro`)

`public.dados_presencial_disparos_canais(p_chave text, p_de date default null, p_ate date default null)` devolve sempre 5 linhas
(whatsapp_api, grupo, sms, ligacao, email): `canal text, disparos integer, enviados integer, entregues integer, lidas integer,
cliques integer, falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean`.

`public.dados_presencial_disparos_lista(p_chave text, p_de date default null, p_ate date default null)` devolve 1 linha por disparo:
`disparo_id bigint, data_hora timestamptz, enviado_em timestamptz, canal text, canal_pago boolean, tipo text, ferramenta text,
numero text, campanha text, publico_lista text, publico_origem text, copy_texto text, copy_link text, tamanho_lista integer,
entregues integer, lidas integer, cliques integer, falhas integer, custo_centavos integer, origem text, retorno_em timestamptz`.

Iguais, em colunas e tipos, às `dados_atm_disparos_canais` e `dados_atm_disparos_lista` (comparado no ensaio). O ATM chama
`rpc(nome, { p_chave, p_de, p_ate })`; a tela da Clínica chama só com `p_chave` (§2.13.4). Chave de outro modelo ou inexistente: P0002; sem acesso: 42501. A
`dados_presencial_disparos(p_chave)` da §2.4 continua como está.

### 2.13.2 Ligação dos disparos já gravados ao projeto 68

Ligados (era `projeto_id` nulo, origem `api`): e-mails do ActiveCampaign ids 39935, 41099, 42695, 44024, 44512 e WhatsApp API ids
39925 e 40560. **A ferramenta do WhatsApp API é o Unichat (id 2), não o Infobip:** é o que está gravado. Ficaram de fora os 2 de
"Compra Aprovada" (ids 50162 e 50132, pós-compra) e os grupos `ALUNOS ATIVOS` do SendFlow.

Medido em produção depois de aplicar (chave `clinica-miami-2026-12`, como equipe): whatsapp_api 2 disparos e 2.945 enviados;
email 5 disparos, 7.827 enviados, 7.814 entregues, 1.078 lidas, 23 cliques, 13 falhas; grupo, sms e ligacao 0. Sem custo
lançado: `custo_completo = false`.

### 2.13.3 Planilha de mensageria da Clínica (NÃO cadastrada ainda)

Fonte: `[CLINICA INTERNACIONAL DIAMANTES] MENSAGERIA.xlsx` no Drive (id `142Piu91iZH6PXYWw06j5lWMA4RhvAfKl`), abas GRUPO (18),
API (2, com "Custo (R$) - ESTIMADO") e EMAIL (5). O arquivo é XLSX: o sync lê Google Sheets, então precisa ser **convertido** antes
(Arquivo, Salvar como Planilhas Google). Cabeçalho e letras abaixo valem só depois da conversão e têm que ser conferidos na planilha convertida.

Por que não cadastrei: falta o ID da planilha convertida, falta a coluna de hora (o Thomas cria), falta o texto de `lista_fixa`
(obrigatório) e falta confirmar a ferramenta dos grupos. Nada disso eu invento.

Mapa proposto:

| Aba | canal | ferramenta | data | campanha | tipo | status | tamanho_lista | entregues | lidas | falhas | custo |
|---|---|---|---|---|---|---|---|---|---|---|---|
| API | `whatsapp_api` | 2 (Unichat) | A | B (Nome) | D (Marketing/Utilidade) | E | F (Contatos na base) | H | I | J | M (Custo (R$) - ESTIMADO) |
| GRUPO | `grupo` | 1 (SendFlow, a confirmar) | A | B | sem coluna | D | F (Participantes) | G | H | sem coluna | sem coluna |

- A coluna E da aba GRUPO (COPY, "MENSAGERIA (PROVISÓRIO)") **não** é mapeada. A aba EMAIL **não** é lida (e-mail vem do ActiveCampaign).
- `tamanho_lista` é obrigatório no mapa: a regra `entregues + falhas <= tamanho_lista` do banco exige.
- Custo precisa estar formatado como R$ com 2 casas (o sync lê o valor formatado).

SQL pronto (colunas de `mkt_mensageria.planilhas` conferidas na `20261011120000`: `planilha_id, nome, projeto_id, desde, ate, abas, ativa`;
formato de `abas` e opção `lista_fixa` como na `20261014210100`). Cabeçalhos copiados da planilha XLSX em 16/10/2026. Marcadores `<...>`
são o que falta. Entra com `ativa = false`:

```sql
insert into mkt_mensageria.planilhas (planilha_id, nome, projeto_id, desde, ate, abas, ativa)
values ('<ID DO GOOGLE SHEETS CONVERTIDO>', '[CLINICA INTERNACIONAL DIAMANTES] MENSAGERIA', 68, date '<DESDE, A CONFIRMAR>', null, $j$[
  {"aba": "API", "canal": "whatsapp_api", "ferramenta_id": 2, "cabecalho_linha": 1,
   "lista_fixa": "<TEXTO A FORNECER PELO VICTOR OU THOMAS>",
   "colunas": {"data": "A", "hora": "<LETRA DA COLUNA DE HORA>", "campanha": "B", "tipo": "D", "status": "E",
               "tamanho_lista": "F", "entregues": "H", "lidas": "I", "falhas": "J", "custo": "M"},
   "cabecalho": {"A": "Data", "B": "Nome", "D": "Categoria do template (inferida)", "E": "Status",
                 "F": "Contatos na base", "H": "Entregues", "I": "Lidos", "J": "Falhas", "M": "Custo (R$) - ESTIMADO"}},
  {"aba": "GRUPO", "canal": "grupo", "ferramenta_id": 1, "cabecalho_linha": 1,
   "lista_fixa": "<TEXTO A FORNECER PELO VICTOR OU THOMAS>",
   "colunas": {"data": "A", "hora": "<LETRA DA COLUNA DE HORA>", "campanha": "B", "status": "D",
               "tamanho_lista": "F", "entregues": "G", "lidas": "H"},
   "cabecalho": {"A": "Data", "B": "Campanha", "D": "Status", "F": "Participantes",
                 "G": "Entregues (painel)", "H": "Visualizações (painel)"}}
]$j$::jsonb, false);
```

Dúvidas que o SQL carrega: os nomes de campo (`data`, `hora`, `campanha`, `tipo`, `status`, `tamanho_lista`, `entregues`, `lidas`, `falhas`,
`custo`, `lista_fixa`) foram copiados do precedente do ATM; o valor aceito em `tipo` ("Marketing"/"Utilidade") e se `hora` é obrigatória
devem ser conferidos no ensaio da migration que cadastrar, antes de aplicar. No XLSX a data vem como número de série (46304 = 09/10/2026);
o sync lê `FORMATTED_VALUE`, então só vale depois da conversão para Planilhas Google com a coluna formatada como data.

Ao **ativar** (`ativa = true`), na mesma migration, desligar o vínculo das 2 mensagens de WhatsApp que a aba API já traz, senão contam em
dobro (o sync cria linha nova de origem `planilha` e a adoção só casa disparo `manual` ou `planilha`, não `api`):

```sql
update mkt_mensageria.disparos set projeto_id = null
 where id in (39925, 40560) and projeto_id = 68 and origem = 'api';
```

### 2.13.4 A tela: visão de disparos igual à do Seminário ATM e à das Ações da Black (16/10/2026)

**Situação:** banco aplicado em produção (§2.13.1 a 2.13.3), tela pronta e testada na branch `victor-miami-disparos-tela`, **merge na `main` pendente**
(sem push até aqui).

**Validação com dado real (16/10/2026): a tela NÃO foi aberta logada.** Não há sessão de conta da equipe neste ambiente, e o `.env.local` do v2 só tem a URL e a
chave `anon` do Supabase (sem service role), então também não li as linhas do banco. O que foi provado: os números medidos em produção (§2.13.2,
anotados em `20261017020500.explain.md`) passam pelo render da `AbaDisparos` em teste (`ui/AbaDisparos.test.ts`) e saem como esperado: API 2 disparos e 2.945 enviados,
o resto "Sem dado"; E-mail 5, 7.827, 7.814, 1.078, 23 e 13; Grupo, SMS e Ligação 0. As linhas desse teste são **montadas à mão a partir dessas anotações**,
não lidas do banco; a lista (`traduzirDisparosLista`) foi testada com uma linha fictícia. A conferência com dado real fica para quem abrir a rota logado.

**Pedido do Victor:** a aba "Visão de disparos" da Clínica tem que ficar igual (Ctrl+C Ctrl+V) à visão de disparos do Seminário ATM
(`web/modules/infra/atm/ui/SeminarioAtmClient.tsx`) e à das Ações da Black (`web/modules/infra/acoes/ui/DashboardAcoesBlackClient.tsx`).
O custo estimado entra, e o rótulo do card de Custo fica "Custo", igual ao ATM.

**Contrato usado:** `dados_presencial_disparos_canais(p_chave, p_de, p_ate)` e `dados_presencial_disparos_lista(p_chave, p_de, p_ate)` (§2.13.1).
A tela chama só com `p_chave`: a Clínica não tem filtro de período e, com `p_de` e `p_ate` nulos, o banco não limita (o cadastro da Clínica
tem `periodo_inicio` e `periodo_fim` nulos).

**O que a tela mostra** (`web/modules/infra/dados/ui/AbaDisparos.tsx`):
- abas por canal, com `CANAIS_DISPARO_ATM` (API, Grupo, SMS, Ligação, E-mail), o mesmo `Tabs` da Black;
- os 7 cards: Disparos, Enviados, Entregues, Lidas / atendidas, Cliques, Falhas, Custo (`custo_centavos` ÷ 100). Valor nulo vira "Sem dado", não zero;
- canal sem resumo: o `EmptyState` "Sem dados para este canal" do ATM;
- a lista de disparos é o `DisparosDetalhe` do ATM, importado sem cópia: abrir um disparo mostra as taxas e todas as métricas. Lista vazia diz "Nenhum disparo registrado"
  (prop opcional `semFiltroPeriodo`, falsa por padrão: ATM e Black continuam com "Nenhum disparo no período").
O canal "API" é a linha `whatsapp_api` do banco, como no ATM e na Black.

**Como foi feito:**
- `atm/infrastructure/atm-data.ts`: a tradução das linhas da lista saiu de `carregarAtmDisparosLista` para a função pura exportada
  `traduzirDisparosLista`; o ATM e a Black seguem chamando `carregarAtmDisparosLista` com o mesmo resultado de antes. Foram exportados também
  o tipo `Linha`, `comTempoLimite` e a leitura `rpc` (com o nome `lerRpcDisparos`), para a Clínica ter o mesmo tratamento de erro do ATM
  (`42501`, `PGRST202`, falha de rede).
- `dados/infrastructure/presencial-data.ts`: `carregarDisparosCanais` e `carregarDisparosLista`, que devolvem o `Resultado` do ATM
  (`{ data, semDado, erro }`), com tempo limite de 20 s por leitura (`TEMPO_LIMITE_LISTAS_MS`). `carregarDisparos` e o tipo `DisparoPresencial` saíram.
- `dados/ui/DashboardPresencialClient.tsx`: as duas leituras rodam juntas na **primeira abertura da aba** e no botão **Atualizar**,
  fora do polling de 60 s. Leitura que falha mantém a última lista e troca só o aviso (`manterUltimaLeituraAtm`, em `application/ultimo-dado.ts`).

**Por que vale para todos os eventos presenciais:** a rota `/infra/dashboards/csm/[chave]` renderiza o mesmo `DashboardPresencialClient` para
qualquer chave; as RPCs novas recebem `p_chave`, então a nova visão serve a todos sem ramificar por evento. Hoje só a Clínica de Miami usa o modelo
`presencial-base`. Nenhuma outra aba mudou.

**Como testar:**
1. `cd web && npx vitest run modules/infra/dados modules/infra/atm modules/infra/acoes` e `npx tsc --noEmit`.
2. Abrir `/infra/dashboards/csm/clinica-miami-2026-12`, aba "Visão de disparos". Esperado (medido em §2.13.2): API 2 disparos e 2.945 enviados
   (o resto "Sem dado"); E-mail 5 disparos, 7.827 enviados, 7.814 entregues, 1.078 lidas, 23 cliques, 13 falhas; Grupo, SMS e Ligação 0.
   Abrir um disparo e conferir as métricas.
3. No painel de rede: as duas RPCs aparecem na primeira abertura da aba e ao clicar em Atualizar, nunca a cada 60 s.

**O que falta:**
- Merge da branch `victor-miami-disparos-tela` na `main` (checklist de subida) e deploy.
- Teste visual em navegador, com conta da equipe.
- Cadastrar a planilha de mensageria da Clínica (§2.13.3), que trará os grupos e o custo estimado do WhatsApp.

### 2.13.5 Risco conhecido, não alterado

`dados_presencial_resumo` calcula `custo_completo` com todos os canais, e e-mail não tem custo. Com os 5 e-mails ligados,
CAC e custo por pré-checkout da Clínica seguem nulos mesmo com o WhatsApp todo custeado (já eram nulos com 0 disparos). A
`dados_atm_resumo` conta só canal pago. Alinhar é uma migration à parte, a decidir pelo Victor.

### 2.13.6 Divergência a confirmar

A planilha diz Clínica em 1 e 2/12; `mkt.projetos` 68 e esta doc dizem 03 e 04/12.

## 3. Migrations (ordem e versão gravada)

| Versão | Nome | O quê |
|---|---|---|
| `20261007161247` | `fin_evento_clinica_miami` | `fin.eventos` da Clínica 03 a 04/12/2026 e a oferta `mjzv4v0s` ligada a ela (não ao Encontro) |
| `20261007161809` | `dados_dashboard_presencial` | schema `dados`, cadastro, gate e as 5 funções |
| `20261007162432` | `mkt_trafego_clinica_miami_oferta` | projeto 68 `interno/csm` e oferta `mjzv4v0s` exclusiva do projeto no Tráfego (`conta_hotmart(68)` = academy) |
| `20261007162557` | `pessoas_registrar_lead_projeto_por_chave` | a fachada da captura resolve o projeto pela chave da casa (lead da página grava `projeto_id` 68) |
| `20261007203803` | `clinica_miami_oferta_nova` | oferta `sju5pawn` (produto 5682989) na Clínica: Financeiro, Tráfego e dashboard; `ofertas_extra` |
| `20261007205017` | `dashboard_vendas_tempo_real` | `dados.transacoes` soma o que o webhook da Hotmart já recebeu e o sync ainda não trouxe (venda em segundos, academy) |
| `20261007212530` | `dashboard_graficos_vendas` | as 6 funções dos gráficos da Visão geral de vendas (§2.9), aprovadas pelo pentester |
| `20261007220043` | `dashboard_lead_teste` | marcar/desmarcar lead do pré-checkout como teste (§2.10), aprovada pelo pentester |
| `20261007171902` (APLICADA 07/10) | `crm_lista_614_todos` | regra 42 com `para_todos`: quem entra na lista 614 vira contato comercial e é catalogado na Clínica. Ensaio refeito antes da aplicação, igual ao esperado |
| `20261009190000` | `dados_miami_respondi` | fichas do Respondi por dashboard, Lista Diamantes, webhook, RPCs `dados_miami_diamantes` e `dados_miami_interesse` |
| `20261009190100` | `respondi_carga_mesmo_formulario` | `fn_respondi_carga` não atualiza resposta de outro formulário (pentester) |
| `20261016240000` (APLICADA 16/10/2026) | `dados_miami_relatorio_planilha` | cópia da aba Relatório da planilha Dados [MIAMI 2026] (`dados.relatorio_planilha`), funções internas e `dados_miami_relatorio` (§2.12) |
| `20261016240100` (APLICADA 16/10/2026) | `dados_miami_relatorio_cron` | cron `dados-relatorio-planilha-sync` (a cada 5 min) e linha do vigia; aplicada depois da Edge publicada |
| `20261017020500` (APLICADA 16/10/2026) | `dados_presencial_disparos_canais_lista` | `dados_presencial_disparos_canais` e `_lista`, no formato do ATM (§2.13) |
| `20261017020600` (APLICADA 16/10/2026) | `mkt_msg_clinica_liga_disparos_projeto_68` | liga ao projeto 68 os 5 e-mails e os 2 WhatsApp API da Clínica (§2.13.2) |

Cada uma tem `.explain.md` com ensaio, explain e reversão.

## 3.1 Segurança: achado CRÍTICO (pentester, 07/10/2026), corrigido no banco

O gate `public.gp_eh_equipe()` (perfil ativo `@advmais.com`) **pode ser contornado** fora desta mudança: o cadastro do
Supabase Auth está aberto (`disable_signup = false`, `mailer_autoconfirm = true`, sem captcha) e o gatilho
`public.handle_new_user()` grava `perfis.status` e `perfis.cargo` a partir do `raw_user_meta_data` escolhido por quem se
cadastra. No ensaio (rollback), um cadastro forjado com e-mail `@advmais.com` e `{status: ativo, cargo: admin}` passou no
gate e leu leads e vendas com telefone. O mesmo caminho abre `gp_pode_ver_cpf` e `crm.pode_catalogar` para qualquer
domínio. A correção mora no Auth e no `handle_new_user` (dono do `perfis`: v2/João; configuração do Auth: Victor), não
nas funções `dados_presencial_*`. Desligar o dashboard na hora, se o Victor decidir:
`update dados.dashboards set ativo = false where chave = 'clinica-miami-2026-12'` (as funções passam a dar P0002).
Hoje a tela expõe 1 lead e 1 pedido, ambos teste interno; o risco cresce quando a captação começar.

**Correção APLICADA em 07/10/2026** (versão `20261007174525`, conferida no banco depois; reteste do pentester na sequência): migration `infra/supabase/migrations/20261007174525_auth_perfil_sem_autodeclaracao.sql`
(ensaio `20261007174525_ensaio.sql`, relatório e comando de aplicação em `20261007174525.explain.md`).
- `handle_new_user` passa a criar todo perfil novo como `pendente`/`visualizador`; ativar e dar cargo fica só com o
  admin (tela Usuários, `/api/admin/usuarios`, que já faz isso depois do convite).
- `gp_is_admin` passa a exigir `@advmais.com`, como o `gp_eh_equipe` (o ensaio mostrou que um cadastro forjado de
  **qualquer** domínio virava admin). Nenhum admin/dev ativo perde acesso (22 antes, 22 depois).
- `perfis`: `anon` perde todos os grants; `authenticated` perde INSERT, DELETE, TRUNCATE, REFERENCES e TRIGGER.
- Ensaio em produção com rollback, 2 rodadas iguais: cadastro forjado (dentro e fora do domínio) nasce pendente e
  todas as portas (`gp_eh_equipe`, `gp_is_admin`, `gp_pode_ver_cpf`, `crm.pode_catalogar`) dão false; convite ativado
  pelo admin continua entrando.
- **Não mexido:** configuração do Auth (o cadastro público é usado por outros sistemas do mesmo projeto; fechar ou
  exigir confirmação de e-mail quebraria esses cadastros) e a policy `todos_auth_podem_ler` (há leitura de perfis de
  terceiros por usuário autenticado de origem não identificada).
- **Resta (aberto):** com `mailer_autoconfirm = true`, alguém ainda cria conta pendente com um e-mail
  `@advmais.com` que não é dele. O admin não deve ativar conta que não veio de convite.

## 4. Provisório (decisões reversíveis do Maestro, 07/10/2026, para o Victor revisar)

- `fin.eventos` da Clínica: `venda_ate` 2026-12-04 (fim do evento).
- "Enviadas" = `tamanho_lista`.
- "Checkout" da série = pedidos na Hotmart, qualquer status.
- Telefone completo para toda a equipe.
- Receita só BRL; a tela avisa quantas vendas ficaram fora.
- Grupo: sem fonte.

## 4.1 Subida para a main (07/10/2026, pedido do Victor)

- A branch `victor-captura-pre-checkout` foi levada inteira para a `main` (merge `--no-ff`), porque o dashboard
  depende de `departamentos.ts` e da `Sidebar.tsx`, que os commits de acesso também mexem. Antes, a `main` foi
  trazida para a branch sem conflito.
- Checklist de `subir-para-a-main`: `npx tsc --noEmit` ok, `npx vitest run` ok (2403 passaram, 2 pulados),
  `npm run build` ok.
- Push na `main` = deploy automático da Hostinger.
- **Não aplicada junto:** a migration `y2` (autor no log de acesso). Ela só pode ir depois que o código da `main`
  manda `p_autor`, ou seja, depois deste merge e do deploy.
- O front novo de acesso continua atrás de `NEXT_PUBLIC_ACESSO_V2`. **Atualização de 08/10/2026:** a flag foi ligada
  na Hostinger e a y2 aplicada (`20261008205705`); ver `docs/niveis-de-acesso-front.md`.
- `/api/captura/lead` responde 503 enquanto `CAPTURA_LEAD_SECRET` não estiver configurada (estado seguro).

## 5. O que falta

- Botão de teste no modal de pré-checkout (JP), sobre a RPC já aplicada (§2.10).
- ~~Tela dos gráficos da Visão geral de vendas~~: feita (commit `a876bd5`).
- Conferir os números dos gráficos novos contra a produção e abrir o modal de pendências com dado real.
- Confirmar uma venda real da Clínica atravessando webhook, banco e próxima leitura automática da tela.
- ~~Aplicar `crm_lista_614_todos`~~: aplicada em 07/10/2026, versão `20261007171902`.
- Efeito da `20261007171902` a saber: quem entra na 614 sem ser contato passa a aparecer no Comercial, sem dono e sem negócio.
- Webhook (`hotmart-events-webhook`): em produção roda a cópia do disparos-thb; o produto 6489980 não está mapeado
  (evento iria para `PRODUTO_NAO_MAPEADO`, sem `cs.compras`); 0 eventos dele recebidos até 07/10.
  `PURCHASE_OUT_OF_SHOPPING_CART` chega para outros produtos (fonte possível de abandonos se a oferta for mapeada).

- Abandono de checkout: depende de o webhook receber a oferta `mjzv4v0s` (decisão do Victor e do dono do disparos-thb).
- Grupo da Clínica no SendFlow ligado ao projeto.
- Disparos da Clínica com projeto 68: ligados 7 em 16/10/2026 (§2.13). Falta cadastrar a planilha de mensageria (ID convertido, hora, `lista_fixa`). A tela da aba está pronta (§2.13.4), merge na `main` pendente.

### Correção 09/10/2026: aba Diamantes não abria

`dados_miami_diamantes` devolve `n_respostas` nulo nas linhas `pendente`, porque a pessoa ainda não respondeu.
A tela chamava `n_respostas.toLocaleString()` e quebrava inteira ("This page couldn't load").

A correção foi feita na tela, e o banco não mudou:
- o tipo `DiamantePresencial.n_respostas` passou a `number | null`;
- a célula usa `inteiro()`, que mostra "sem dado".

Verificado com `tsc` e com o `vitest` de `modules/infra/dados`.
