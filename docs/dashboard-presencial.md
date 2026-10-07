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

## 3. Migrations (ordem e versão gravada)

| Versão | Nome | O quê |
|---|---|---|
| `20261007161247` | `fin_evento_clinica_miami` | `fin.eventos` da Clínica 03 a 04/12/2026 e a oferta `mjzv4v0s` ligada a ela (não ao Encontro) |
| `20261007161809` | `dados_dashboard_presencial` | schema `dados`, cadastro, gate e as 5 funções |
| `20261007162432` | `mkt_trafego_clinica_miami_oferta` | projeto 68 `interno/csm` e oferta `mjzv4v0s` exclusiva do projeto no Tráfego (`conta_hotmart(68)` = academy) |
| `20261007162557` | `pessoas_registrar_lead_projeto_por_chave` | a fachada da captura resolve o projeto pela chave da casa (lead da página grava `projeto_id` 68) |
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

## 5. O que falta

- ~~Aplicar `crm_lista_614_todos`~~: aplicada em 07/10/2026, versão `20261007171902`.
- Efeito da `20261007171902` a saber: quem entra na 614 sem ser contato passa a aparecer no Comercial, sem dono e sem negócio.
- Webhook (`hotmart-events-webhook`): em produção roda a cópia do disparos-thb; o produto 6489980 não está mapeado
  (evento iria para `PRODUTO_NAO_MAPEADO`, sem `cs.compras`); 0 eventos dele recebidos até 07/10.
  `PURCHASE_OUT_OF_SHOPPING_CART` chega para outros produtos (fonte possível de abandonos se a oferta for mapeada).

- Abandono de checkout: depende de o webhook receber a oferta `mjzv4v0s` (decisão do Victor e do dono do disparos-thb).
- Grupo da Clínica no SendFlow ligado ao projeto.
- Disparos da Clínica com projeto 68 (hoje 0).
