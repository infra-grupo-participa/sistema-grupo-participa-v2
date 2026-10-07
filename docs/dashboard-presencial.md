# Dashboard de evento presencial para a base (banco)

Modelo `presencial-base`, primeiro uso: **Clínica de Miami** (`clinica-miami-2026-12`, sigla CNFMIAMI26, `mkt.projetos`
id 68). Pedido do Victor Hugo em 07/10/2026. A tela (Infra > Dados > Dashboards) está em
`docs/dashboard-presencial-tela.md`; este arquivo é o lado do banco.

**Situação (07/10/2026):** migrations APLICADAS em produção (seção 3).
Nada publicado: a tela e a rota de captura estão só na branch `victor-captura-pre-checkout`.

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
- **Depois da `20261007te` (NÃO APLICADA, §2.10):** a lista passa a trazer também quem é teste, com duas colunas novas
  no fim, `pessoa_id uuid, teste boolean`; os números continuam sem eles.

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

No repo, entrar em `web` e rodar `npm run dev -- -p 3001`. Abrir `/infra/dados/dashboards/clinica-miami-2026-12`
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

## 2.10 Marcar lead do pré-checkout como teste (migration `20261007te`, NÃO APLICADA: espera pentester)

Card `17tya50fkx9`. Usa `pessoas.pessoas.teste` (o campo do sistema inteiro: quem é teste também sai das estratégias de
disparo do CRM e do resumo do Tráfego, que já liam esse campo).

### 2.10.1 `dados_presencial_leads(p_chave)` muda

Mesmas 13 colunas, mesma ordem, mais duas no fim: `pessoa_id uuid, teste boolean`.

- Lista **todo mundo**, inclusive quem é teste. A tela mostra a linha com `teste = true` apagada, com a etiqueta "teste",
  e não a soma em nada.
- `pessoa_id`: o id que a RPC recebe. `null` quando o lead não tem pessoa ligada (só pode acontecer com quem entrou pela
  lista do ActiveCampaign sem cadastro de pessoa): sem botão.
- `teste`: alguma pessoa ligada àquele e-mail está marcada.

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
| `20261007te` (NÃO APLICADA) | `dashboard_lead_teste` | marcar/desmarcar lead do pré-checkout como teste (§2.10); espera pentester |
| `20261007171902` (APLICADA 07/10) | `crm_lista_614_todos` | regra 42 com `para_todos`: quem entra na lista 614 vira contato comercial e é catalogado na Clínica. Ensaio refeito antes da aplicação, igual ao esperado |

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
- O front novo de acesso continua atrás de `NEXT_PUBLIC_ACESSO_V2` (padrão desligado). O valor dela na Hostinger
  não foi conferido.
- `/api/captura/lead` responde 503 enquanto `CAPTURA_LEAD_SECRET` não estiver configurada (estado seguro).

## 5. O que falta

- Pentester e aplicação da `20261007te` (lead de teste); depois, o botão no modal de pré-checkout (JP).
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
