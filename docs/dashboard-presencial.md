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

### 2.4 `dados_presencial_disparos` (1 linha por disparo, mais recente primeiro)

`disparo_id bigint, dia date, nome text, canal text, ferramenta text, tamanho_lista integer, entregues integer,
lidas integer, cliques integer, falhas integer, custo_centavos bigint, entrega_pct numeric, leitura_pct numeric,
clique_pct numeric`

- `mkt_mensageria.disparos` do projeto, não arquivados. `dia` = `enviado_em` em São Paulo; `nome` = `campanha`;
  `canal` = código (`whatsapp_api`, `email`, `sms`, `ligacao`, `grupo`); `ferramenta` = `mkt_mensageria.ferramentas.nome`.
- Não existe coluna "enviadas": a tela mostra `tamanho_lista` como "Tamanho da lista".
- Taxas: entregues ÷ tamanho; lidas ÷ entregues; cliques ÷ entregues. Divisor 0 ou nulo = `null`.
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
atualizar. No painel de rede, `dados_presencial_disparos`, `dados_presencial_leads` e `dados_presencial_vendas` não
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
- Disparos da Clínica com projeto 68 (hoje 0).

### Correção 09/10/2026: aba Diamantes não abria

`dados_miami_diamantes` devolve `n_respostas` nulo nas linhas `pendente`, porque a pessoa ainda não respondeu.
A tela chamava `n_respostas.toLocaleString()` e quebrava inteira ("This page couldn't load").

A correção foi feita na tela, e o banco não mudou:
- o tipo `DiamantePresencial.n_respostas` passou a `number | null`;
- a célula usa `inteiro()`, que mostra "sem dado".

Verificado com `tsc` e com o `vitest` de `modules/infra/dados`.
