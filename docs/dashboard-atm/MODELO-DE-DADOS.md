# Dashboard do Seminário ATM: modelo de dados (banco)

Modelo `seminario-atm`, primeiro uso: **ATM 1 da Dra. Elaine** (`atm-elaine-1-2026-10`, live 13/10/2026 19h30). Card
86aktf11y. Lugar na tela: Infra > Dashboards > Escritório > Seminário ATM. Vale para os próximos ATMs (27/10, 17/11)
só com cadastro pela chave, sem função nova.

**Situação (08/10/2026): migrations APLICADAS em produção** (161000, 161001, 161100) com ok do Victor. Projeto `ATMEL126`
(id 75), oferta `mqquvrtc` provisória, Listas 1 (131.515) e 2 (2.316) carregadas em `dados.lista_membros`.
**Grupo (08/10/2026, 18h UTC): caminho LIGADO no banco.** Segredo `crm_webhook_sendflow` criado no Vault,
`crm.config.sendflow_ligado = true`, campanha `ATM 10/26` cadastrada em `dados.dashboard_grupos`. Testado com POST na Edge
(token errado = 401; token certo = 1 evento gravado, apagado em seguida). **Falta o passo manual no painel do SendFlow:**
colar a URL `crm-integracao-webhook/sendflow?token=...` no SendHook da campanha `ATM 10/26` (o token não vai no repo).
Quem entrou antes do SendHook (43 participantes em 08/10, contando admins) não é contado: o webhook não olha para trás.
**Falta também** a fonte do pré-checkout; sem ela esse card fica "sem dado ainda".
Disparo só entra no dashboard se a campanha tiver `[ATMEL126]` no nome (ou for ligada à mão ao projeto 75).
Detalhe técnico, ensaio e reversão: `infra/supabase/migrations/20261008161000.explain.md`.

Regra de dado do briefing: nada lê planilha. Sem dado = **nulo** (a tela mostra "sem dado ainda"); zero = zero medido.
Nunca número inventado, nunca erro.

## 1. De onde vem cada número

| Card / coluna | Fonte no banco | Regra |
|---|---|---|
| Disparos, enviados, custo | `mkt_mensageria.disparos` do projeto, não arquivados | disparos = linhas; enviados = soma de `tamanho_lista`; custo = soma de `custo_centavos`, nulo se nenhum tem custo |
| Leads | lista do ActiveCampaign da edição (`lista_ac_leads`, hoje 615) + evento `lead` do projeto em `pessoas.eventos` | pessoa = e-mail único; teste (`pessoas.pessoas.teste`, `@exemplo.invalid`) não conta |
| Ingresso no grupo | `crm.evento_jornada` fonte `sendflow` com `tag` = campanha cadastrada em `dados.dashboard_grupos` | pessoas (telefone) que entraram, leads ou não; nulo sem campanha cadastrada |
| % ingresso no grupo | ingresso ÷ leads × 100 | |
| Taxa de evasão | saídas ÷ entradas × 100 | saída só conta para quem entrou e saiu depois de entrar |
| CPL | custo ÷ leads | só com custo completo (todos os disparos com custo); senão nulo |
| Pré-checkout | `dados.pre_checkout` (evento `pre_checkout` do projeto + lista do AC `lista_ac`) | o mesmo do dashboard presencial |
| Vendas | `fin.hotmart_transacoes` da oferta do cadastro (conta `escritorio`), pagas, 1ª cobrança, pedido a partir de `vendas_desde` | nulo enquanto a oferta não estiver no cadastro. Atualiza de hora em hora (o webhook em tempo real só cobre a conta academy) |
| Taxa de conversão do pré-checkout | compradores ÷ pré-checkout × 100 | mesma regra do presencial |
| CAC | custo ÷ vendas | só com custo completo |
| Faturamento bruto / líquido | vendas pagas em BRL | bruto = valor base; líquido = líquido do produtor (regra do presencial) |
| ROAS | faturamento ÷ custo | bruto (`roas`) e líquido (`roas_liquido`); custo = só disparo |
| Entrou no grupo? (lead) | telefone do lead (últimos 8 dígitos) ou pessoa casada no evento do grupo | |
| É aluno? | `public.thb_alunos` pelo e-mail | `instrucao` e `turma` na mesma linha |
| Estado | DDD do telefone em `dados.ddd_uf` (tabela do dashboard-ht) | DDD desconhecido = `Outros`; sem telefone = nulo |
| Lista de origem, seminário de origem | `dados.lista_membros` (carga dos CSVs da tarefa 86aktf117) | casa por e-mail ou últimos 8 dígitos do telefone |
| Pico, equipe na sala | `dados.sessoes` (lançado do Zoom) | |
| Presentes | `dados.sessao_presencas` (relatório de participantes do Zoom) | quem é da equipe não conta |

`utm_source`: só existe para lead que entrou pela rota `/api/captura/lead`; quem veio só pelo ActiveCampaign tem UTM nula
(o webhook do AC não traz UTM).

## 2. Contrato das RPCs (nomes, colunas e ordem exatos)

Todas: `public.<nome>(p_chave text)`, só `authenticated`. Erros: `42501` não é equipe (ou anon); `P0002` chave fora do
cadastro ativo ou de outro modelo; `PGRST202` função ainda não aplicada. Dinheiro de venda em reais `numeric(14,2)`;
custo em centavos `bigint`; percentual `numeric(7,2)` de 0 a 100; ROAS `numeric(10,2)` (vezes); dia `date` em São Paulo.

### 2.1 `dados_atm_resumo` (1 linha; os cards da visão geral)

`chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer,
disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer,
grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean,
cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer,
compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric,
receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamptz`

Cards na ordem do briefing: disparos (`disparos_qtd`), leads, ingresso no grupo (`grupo_entradas`), % ingresso
(`grupo_pct`), evasão (`evasao_pct`), custo (`custo_disparo_centavos`), CPL (`cpl_centavos`), pré-checkout
(`pre_checkout_pessoas`), vendas, conversão do pré-checkout (`conversao_pre_checkout_pct`), CAC (`cac_centavos`),
faturamento bruto (`receita_bruta`), líquido (`receita_liquida`), ROAS (`roas`).
`grupo_tem_fonte = false` → todos os campos de grupo nulos. `oferta_codigo` nulo → vendas, compradores, receita, CAC,
ROAS nulos. `custo_completo = false` → CPL, CAC, ROAS nulos (a tela pode avisar quantos disparos estão sem custo).

### 2.2 `dados_atm_leads` (modal de leads; 1 linha por e-mail, `primeiro_em desc`)

`email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text, utm_medium text,
utm_campaign text, utm_content text, utm_term text, ddd text, estado text, entrou_grupo boolean, saiu_grupo boolean,
eh_aluno boolean, instrucao text, turma text, lista_origem text, seminario_origem text, no_pre_checkout boolean,
comprou boolean, pessoa_id uuid, teste boolean`

- `fonte`: `activecampaign`, `sistema` ou `ambos`.
- `entrou_grupo`/`saiu_grupo`: nulo sem campanha do SendFlow cadastrada.
- `lista_origem`: `lista_1`, `lista_2`, `lista_1_e_2`, `fora_das_listas`; nulo enquanto nenhuma lista foi carregada.
- `seminario_origem`: `marcio`, `elaine`, `marcio_e_elaine` ou nulo.
- `comprou`: nulo sem oferta no cadastro.
- Traz também quem é teste (`teste = true`, para mostrar apagado); os números do resumo e da série não contam.
- Evolução diária e resumo do modal: usar `dados_atm_serie_diaria` (coluna `leads`) e `dados_atm_resumo`.

### 2.3 `dados_atm_serie_diaria` (1 linha por dia, sem buraco, do 1º dia com dado até hoje)

`dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer, vendas integer,
receita_bruta numeric, custo_disparo_centavos bigint`

Leads pelo 1º dia de cada e-mail; grupo pelo dia da 1ª entrada e da saída; vendas pelo dia de aprovação. Grupo nulo sem
fonte; vendas e receita nulas sem oferta; custo do dia nulo se algum disparo do dia está sem custo. Sem nenhum dado:
0 linhas.

### 2.4 `dados_atm_disparos_canais` (sempre 5 linhas, ordem das abas)

`canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer, falhas integer,
custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean`

Ordem e rótulo da aba: `whatsapp_api` (API), `grupo` (Grupo), `sms` (SMS), `ligacao` (Ligação, Ligue Lead), `email`
(E-mail). Canal sem disparo: `disparos = 0` e o resto nulo.
**Lista de disparos de cada aba:** `dados_presencial_disparos(p_chave)` (já aplicada, serve para qualquer chave; colunas em
`docs/dashboard-presencial.md` §2.4), filtrando `canal` na tela.

### 2.5 `dados_atm_comparecimento` (1 linha por sessão, ordem de início)

`sessao_id uuid, tipo text, inicio timestamptz, fim timestamptz, pico_audiencia integer, equipe_na_sala integer,
total_leads integer, total_grupo integer, presentes integer, presentes_leads integer, presentes_grupo integer,
pico_sobre_leads_pct numeric, pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric,
vendas integer, conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric`

- `tipo`: `live`, `replay`, `triplay`.
- `presentes*` nulos enquanto o relatório do Zoom não for carregado; `pico_audiencia`/`equipe_na_sala` nulos até
  lançados.
- `vendas` da sessão: aprovadas entre o início dela e o início da próxima (a última vai até `ciclo_fecha_em` ou agora).
- Conversão = vendas ÷ leads; no grupo = vendas ÷ grupo; sobre o pico = vendas ÷ pico.
- **A confirmar com o Victor:** qual comparecimento a tela mostra (pico ÷ leads, como parece ser a planilha de julho, ou
  presentes ÷ leads, medido por pessoa). As duas colunas vêm prontas.

### 2.6 `dados_atm_pos_live` (2 linhas: `fechado`, `aberto`)

`ciclo text, ate timestamptz, vendas integer, compradores integer, receita_bruta numeric, receita_liquida numeric,
conversao_pct numeric, conversao_grupo_pct numeric, conversao_pre_checkout_pct numeric`

- `fechado`: vendas aprovadas até `ciclo_fecha_em` (fim do triplay). Nulo enquanto a data não for cadastrada.
- `aberto`: vendas aprovadas até agora (inclui o fechado). A diferença é o que entrou depois do triplay.
- Conversão sobre compradores: ÷ leads, ÷ grupo, ÷ pré-checkout. **A confirmar com o Victor** (regra tirada do
  debriefing do ATM de setembro).

Lista de vendas, se a tela quiser: `dados_presencial_vendas(p_chave)` serve para qualquer chave, mas **não aplica o corte
`vendas_desde`** (mostra todas as transações da oferta).

## 3. Situação de cada card no ATM 1 (08/10/2026)

| Card | Hoje | Falta |
|---|---|---|
| Leads | 54 em 08/10 (lista 615, webhook do AC, automático) | nada |
| Disparos, custo, CPL, CAC, ROAS | projeto 75 (`ATMEL126`) | `[ATMEL126]` no nome das campanhas; custo lançado |
| Grupo, % ingresso, evasão | banco pronto (08/10) | colar a URL no SendHook da campanha `ATM 10/26` |
| Pré-checkout | sem fonte | lista do gateway Guardiões do Legado ou a rota de captura |
| Vendas, faturamento | oferta `mqquvrtc` (provisória) | confirmar a oferta definitiva (Arthur, 86aktf1c3) |
| Lista e seminário de origem | carregadas (131.515 e 2.316) | nada |
| Comparecimento | só a live cadastrada | hora do replay e do triplay; pico, equipe e relatório do Zoom depois da live |

## 4. Como cadastrar o próximo ATM (ou completar este)

Tudo por SQL de 1 linha, rodado por quem tem acesso de dono (hoje o JP), documentado no diário do banco.

```sql
-- projeto (sigla aprovada pelo Victor, formato ^[A-Z]{2,10}[0-9]{2,4}$)
insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, especialista_id, evento_inicio, evento_fim)
values ('<SIGLA>', '<nome>', 'Seminário', 2026, '<chave>', 'interno', 'escritorio', <1 Marcio | 2 Elaine>, '<data>', '<data>');

-- dashboard
insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads, vendas_desde)
values ('<chave>', 'seminario-atm', <id do projeto>, 'escritorio', '<oferta ou null>', '<lista pré-checkout ou null>',
        '<lista de leads do AC>', '<início da reativação>');

-- completar depois
update dados.dashboards set oferta_codigo = '<oferta>' where chave = '<chave>';
update dados.dashboards set ciclo_fecha_em = '<fim do triplay>' where chave = '<chave>';
insert into dados.dashboard_grupos (chave, sendflow_campanha) values ('<chave>', '<nome exato da campanha no SendFlow>');
insert into dados.sessoes (chave, tipo, inicio) values ('<chave>', 'replay', '<início>');
update dados.sessoes set pico_audiencia = <n>, equipe_na_sala = <n> where chave = '<chave>' and tipo = 'live';
```

Carga das listas e da presença: por `service_role`, só com a chave normalizada (`pessoas.norm_email(email)` e
`controle.fone_key(telefone)`), `importacao` = rótulo do lote sem dado pessoal. O CSV não entra no repo.
E a entrada no manifesto da tela (`web/modules/infra/dados/domain/registro.ts`), como no presencial.
