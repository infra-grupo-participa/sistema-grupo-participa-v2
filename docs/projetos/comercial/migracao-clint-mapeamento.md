# Migração da Clint: mapeamento sugerido (lote `clint-20261006T105127`)

> Gerado em 06/10/2026 por `crm.clint_preparar_mapas()` sobre o staging real. **Nada foi confirmado** (`confirmado =
> false` em todos os mapas), **nada foi carregado** (só ensaio, que desfaz tudo) e `crm.config.clint_import_ligado`
> continua `false`. Sem dado pessoal: só nomes de funil/etapa/motivo/campo da Clint e contagens.
> Contexto e regras: `migracao-clint.md`.

## 1. O que está no staging

Escopo **recentes, 30 dias** (`clint_extrair.py --escopo recentes --dias 30`), lote **completo**: o que a API anunciou
bate com o que foi gravado.

| Tipo | Gravados | API anunciou |
|---|---|---|
| Negócios abertos (mexidos desde 06/09/2026) | 4.495 | 4.495 |
| Negócios ganhos (todos) | 5.121 | 5.121 |
| Negócios perdidos (todos) | 529 | 529 |
| Contatos desses negócios | 2.039 | 2.039 referenciados (0 sem cadastro) |
| Origens usadas por esses negócios | 203 (das 730) | todas as 203 encontradas |
| Grupos dessas origens | 42 | — |
| Atividades desses negócios | 555 (das 18.800 da conta) | — |
| Usuários / motivos / tags / campos da conta | 6 / 19 / 836 / 74 | 6 / 19 / 836 / — |

Extração: 261 requisições em 9,5 min. Histórico desligado; ligar `--com-historico` custaria cerca de 10 mil GETs,
algo como 1,4 h.

**Pontos de atenção:**
- **Muitos negócios por contato.** São 10.145 negócios para 2.039 contatos, e a maior parte da diferença vem das
  origens **arquivadas**. As 134 origens arquivadas (de 203) guardam 2.676 dos 4.495 abertos. Como só 464 pares
  (nome da origem, contato) são distintos, parecem cópias das mesmas pessoas em funis clonados por mês/turma
  ("Holding Total - SET/OUT/NOV/JAN…": 383 ganhos idênticos em cada "Compras em aberto"). Os 5.121 ganhos são de
  1.007 contatos.
- **A maioria dos negócios não tem dono.** Só 2.235 dos 10.145 têm usuário (ver §4).
- **Os ganhos parecem eventos da Hotmart.** 8.219 negócios trazem `product_id`, `transaction`, `purchase_status`
  etc. nos campos, e os 5.121 WON vão de 14/03 a 02/10/2026 (903 nos últimos 30 dias). Pela regra D-F6-1, só viram
  ganho os que casarem com 1 transação Hotmart aprovada. Antes disso é preciso vincular os produtos em
  `crm.produto_comercial`.

**Recomendação:** `importar = false` nas origens **arquivadas** (`arquivado_clint = true`) e nas de teste
("GRUPO PRODUTO EXEMPLO"). Assim ficam 69 origens ativas, com 1.819 abertos.

## 2. Origens (funis) e linha sugerida

### 2.1 Por linha sugerida

| Linha sugerida | Origens | Arquivadas | Negócios | Abertos | Ganhos | Perdidos | Abertos em origens ativas |
|---|---|---|---|---|---|---|---|
| `ht` | 47 | 30 | 6.041 | 2.380 | 3.568 | 93 | 814 |
| `hm` | 75 | 64 | 2.290 | 1.101 | 1.004 | 185 | 268 |
| `sv` | 31 | 19 | 1.127 | 970 | 111 | 46 | 702 |
| **sem linha** | 18 | 2 | 300 | 33 | 85 | 182 | 31 |
| `ethb` | 14 | 9 | 286 | 2 | 264 | 20 | 1 |
| `aurum` | 18 | 10 | 101 | 9 | 89 | 3 | 3 |
| **Total** | **203** | **134** | **10.145** | **4.495** | **5.121** | **529** | **1.819** |

**Sem linha (o gestor precisa escolher):** Imersão - POA (Cidades, Compras em aberto, Pop up, Grupo prime, Indicacoes e
HT24, Compras aprovadas, Cartão recusado), Imersão em Holding Familiar (4 origens), Curso Nacional de Formação em
Holding Familiar (2), Clínica - POA, Clínica de Holding - GO e GRUPO PRODUTO EXEMPLO (2, teste). A origem
"Imersão - POA / Cidades" tem 141 negócios, 133 deles perdidos.

### 2.2 Origens com mais negócios (`grupo / origem`)

| Grupo / origem | Arquivada | Linha | Negócios | Abertos | Ganhos | Perdidos |
|---|---|---|---|---|---|---|
| Holding Total - Semanal / Compras em aberto | não | ht | 571 | 0 | 571 | 0 |
| [HT] Jornada / HT Recuperação de Venda | não | ht | 484 | 2 | 481 | 1 |
| Seminário - setembro/26 / MQLS | não | sv | 389 | 387 | 0 | 2 |
| Holding Total - OUT, NOV, SET, JAN-2026, MAR-2026, FEV-2026 / Compras em aberto (6 origens) | sim | ht | 383 cada | 0 | 383 cada | 0 |
| [HT] Jornada / Evento | não | ht | 346 | 344 | 1 | 1 |
| Holding Total - SET / Compras aprovadas (+ JAN, FEV, NOV, OUT, MAR: 6 origens) | sim | ht | 189–195 cada | 180 cada | 0 | 9–15 |
| Holding Total - Semanal / Compras aprovadas | não | ht | 194 | 180 | 0 | 14 |
| Holding Total - SET/26 / Compras aprovadas | não | ht | 166 | 162 | 0 | 4 |
| Imersão - POA / Cidades | não | — | 141 | 0 | 8 | 133 |
| Implementação Assistida / Recuperação – Saldo Implementação Assistida (HM) | não | hm | 139 | 138 | 1 | 0 |
| Holding Masters - Principal / Compras em aberto | não | hm | 108 | 0 | 108 | 0 |
| Seminário - setembro/26 / Interessados | não | sv | 102 | 102 | 0 | 0 |
| Holding Masters (Principal, OUT, NOV, T32) / Compras em aberto (5 origens) | sim | hm | 100 cada | 0 | 99–100 | 0–1 |
| Holding Total - Semanal / Abandono de carrinho | não | ht | 98 | 76 | 19 | 3 |
| Holding Total (OUT, MAR, SET, FEV, NOV, JAN) / Abandono de carrinho (6 origens) | sim | ht | 89 cada | 76 cada | 13 cada | 0 |
| Seminário - setembro/26 / RSVP - MQL | não | sv | 76 | 75 | 0 | 1 |
| Encontro do Time Holding Brasil / Compras em aberto | não | ethb | 73 | 0 | 73 | 0 |
| Holding Masters (vários) / Compras aprovadas (7 origens) | 6 sim, 1 não | hm | 63–66 cada | 39–40 | 0 | 23–27 |
| Sessão de Viabilidade (vários) / Abandono de carrinho (4 origens) | 3 sim | sv | 62 cada | 59 | 3 | 0 |
| Curso Nacional de Formação em Holding Familiar / Curso Nacional de Holding Familiar | não | — | 55 | 26 | 0 | 29 |
| Seminário - setembro/26 / SESSÃO 22/09 | não | sv | 47 | 47 | 0 | 0 |

As outras 140 origens têm 47 negócios ou menos cada uma. São sobretudo cópias por mês de "Cartão recusado",
"Assinaturas/Parcelex ativas/em atraso/canceladas", "Compras expiradas", "Reembolso/Chargeback" e "Pop up
pré-checkout" de HT, HM, SV, ETHB e Aurum.

## 3. Etapas e papel sugerido

Há 921 etapas nas 203 origens. Papel sugerido pelo nome (`crm._clint_papel_sugerido`):

| Papel sugerido | Etapas |
|---|---|
| **sem papel** (o gestor precisa escolher) | 397 |
| `primeiro_contato` | 250 |
| `fechado` | 154 |
| `qualificar` | 102 |
| `negociar` | 9 |
| `aguardar_pagamento` | 5 |
| `apresentar_oferta` | 4 |

Origens ativas com mais negócios (número = ordem; `[tipo na Clint]`; entre parênteses, os abertos que estão
nessa etapa hoje):

- **Holding Total - Semanal / Compras em aberto** (571): 1. Base [BASE] → primeiro_contato · 2. Prospecção → **—** ·
  3. Conexão → qualificar · 4. Aguardando compra → **—** (sugestão: aguardar_pagamento) · 5. Fechado [CLOSING] → fechado.
- **[HT] Jornada / HT Recuperação de Venda** (484): 1. Recuperado [BASE] → **—** · 2. Abandono de Carrinho → **—** ·
  3. Aguardando Pagto → aguardar_pagamento (1) · 4. PIX Expirado → aguardar_pagamento · 5. Cancelado/Cartão → **—** (1) ·
  6. Em Recuperação Ativa → **—** · 7. Não Recuperado [CLOSING] → **—**.
- **Seminário - setembro/26 / MQLS** (389): 1. MQLS [BASE] → **—** (387) · 2. Fechado [CLOSING] → fechado.
- **[HT] Jornada / Evento** (346): 1. Comprou Ingresso [BASE] → **fechado** ⚠️ (é a 1ª etapa; sugestão
  errada, deveria ser primeiro_contato) · 2. Em Onboarding → **—** (179) · 3. Dentro do Grupo · 4. Ativado ·
  5. Evento em Andamento · 6. Confirmado Domingo · 7. Aplicou Holding Masters · 8. Encaminhado ao Comercial (3) ·
  9. Disparo 2109 (162), da 3 à 9 todas **—** · 10. Fechado [CLOSING] → fechado. Com isso a origem fica com **2 etapas
  `fechado`**, e a carga recusa funil com mais de 1. É preciso corrigir antes de confirmar.
- **Holding Total - Semanal / Compras aprovadas** (194): 1. Base → primeiro_contato (179) · 2. Mensagem 1 · 3. Entrou
  no grupo/pesquisa · 4. Ligação → **—** · 5. Follow UP → negociar · 6. Confirma Domingo → **—** · 7. Fechado → fechado (1).
- **Holding Total - SET/26 / Compras aprovadas** (166): 1. Base → primeiro_contato (162) · 2. Onboarding · 3. On going →
  **—** · 4. Sucesso [CLOSING] → **—** (sugestão: fechado).
- **Imersão - POA / Cidades** (141): etapas por região (Porto Alegre e Região, Demais, PR, SC) → **—**; Follow up →
  negociar; Conexão → qualificar; Aguardando compra → **—**; "Perdido" é uma etapa CUSTOM → **—**; Fechado → fechado.
- **Implementação Assistida / Recuperação – Saldo (HM)** (139): 1. A contatar → primeiro_contato (138) · 2. Em contato →
  primeiro_contato · 3. Em negociação → negociar · 4. Link/boleto enviado → aguardar_pagamento · 5. Saldo acertado
  [CLOSING] → **—** (sugestão: fechado).
- **Seminário - setembro/26 / Interessados** (102): Base → primeiro_contato (102) · Fechado → fechado.
- **Seminário - setembro/26 / RSVP - MQL** (76): 1. Nova Etapa 2 → primeiro_contato · 2. "15/09" [CLOSING] → **—** (75).

Padrão que se repete nas cópias: "Base / Prospecção / Conexão / Aguardando compra / Fechado" e "Base / Mensagem /
Onboarding / … / Fechado". **Sugestão:** etapa com tipo `CLOSING` da Clint vira `fechado`; "Aguardando compra/pagto"
vira `aguardar_pagamento`; e etapas operacionais pós-compra (Onboarding, Grupo, Ativado, Confirmado Domingo) ficam de
fora, junto com a origem, quando o funil for de onboarding e não de venda.

## 4. Usuários da Clint (6)

O casamento é por e-mail com `perfis`. A tabela não mostra e-mail.

| Usuário Clint | Casou com perfil? | Cargo no sistema | Vendedor ativo no CRM? | Negócios no lote (abertos) |
|---|---|---|---|---|
| U1 | sim | admin | **não** | 1.954 (538) |
| U2 | sim | visualizador | **não** | 235 (78) |
| U3 | sim | operador | **sim** (vendedor Marcos) | 46 (46) |
| U4 | sim | visualizador, status pendente | não | 0 |
| U5 | **não** (sem perfil com o mesmo e-mail) | — | não | 0 |
| U6 | sim | operador | **sim** (vendedor Ronan) | 0 |

Só U3 vira dono de verdade: 46 negócios. Os 2.189 de U1 e U2 entrariam **sem dono**, porque esses perfis não estão
em `crm.vendedor` (D-F6-3). Os 7.910 restantes já não têm usuário na Clint. **Para decidir:** cadastrar U1 e U2 como
vendedores, ou fixar `perfil_id` no mapa, antes da carga real.

## 5. Motivos de perda (19 + "sem motivo")

| Motivo na Clint | Sugerido no CRM | Perdidos no lote |
|---|---|---|
| (perdido sem motivo na Clint) | **—** | **509** |
| Duplicado | ja_atendido_outro_vendedor | 8 |
| Número Inválido ou Errado | contato_invalido | 3 |
| Sem dinheiro | sem_condicao_financeira | 2 |
| Sem interesse | sem_interesse | 2 |
| Já é Aluno | **—** (sugestão: comprou_outro_produto) | 1 |
| Já tinha Comprado | **—** (sugestão: comprou_outro_produto) | 1 |
| Sem perfil | fora_do_perfil | 1 |
| VISTO | **—** | 1 |
| Vitalício HM | **—** (sugestão: comprou_outro_produto) | 1 |
| Comprou com outra empresa | comprou_outro_produto ⚠️ (no CRM é "outro produto **da casa**"; o sentido é o oposto) | 0 |
| Tentativas esgotadas | tentativas_esgotadas | 0 |
| Não é o tomador de decisão | **—** (sugestão: fora_do_perfil) | 0 |
| Sem limite no cartão | **—** (sugestão: sem_condicao_financeira) | 0 |
| Tem Compromisso na data | **—** (sugestão: nao_e_o_momento) | 0 |
| Próxima Turma Aurum | **—** (sugestão: nao_e_o_momento) | 0 |
| Queria Gravação | **—** | 0 |
| Renovação Aurum | **—** | 0 |
| HT - out/24 | **—** | 0 |
| acessogratisethb | **—** | 0 |

Motivos do CRM: comprou_outro_produto, contato_invalido, fora_do_perfil, ja_atendido_outro_vendedor,
nao_e_o_momento, pediu_sem_contato, sem_condicao_financeira, sem_interesse, tentativas_esgotadas.
**Decisão principal:** 509 dos 529 perdidos não têm motivo na Clint. Sem um `motivo_chave` confirmado para
"sem_motivo", todos ficam `pendente_motivo` e não entram.

## 6. Campos e destino sugerido

São 121 chaves (40 de contato e 81 de negócio). Destino sugerido hoje: **nota** em quase todas;
`campo:origem` em origem_do_checkout (contato, 109) e origem_do_lead (negócio, 0); `campo:perfil_profissional` em
profissao (77); `campo:produto_interesse` em produto_comprado (186); `campo:objecao_principal` (2);
`campo:atua_com_holding` em aplicou_holding_mais (0); `ignorar` em subscription_next_charge_at.

Contato (preenchidos entre os 2.039):

| Chave | Rótulo | Preenchidos | Sugerido | Recomendação |
|---|---|---|---|---|
| doc | — | **707** | nota | ⚠️ **ignorar**: provável CPF/documento (regra: CPF nunca entra); o sugeridor não pegou porque não há rótulo |
| tags | — | 320 | nota | `tag` (as tags do contato já entram por `tags[]`) |
| role | — | 242 | nota | nota |
| notes | Notas do contato | 234 | nota | nota |
| origem_do_checkout | Origem Do Checkout | 109 | campo:origem | conferir os valores aceitos |
| profissao | Profissão | 77 | campo:perfil_profissional | ok |
| data_da_compra | Data da Compra | 76 | nota | nota |
| email_2, email_3, contactEmail, contactName, contactPhone, whatsapp_number | — | 75 / 4 / 27 / 27 / 27 / 3 | nota | **ignorar** (dado pessoal duplicado; o contato já tem e-mail e telefone) |
| turma, copy1–4, lpsg_*, palavra_chave, confirmou_presenca_a* | — | ≤ 40 | nota | nota ou ignorar |
| em_qual_faixa_esta_o, por_que_voce_deseja | perguntas de qualificação (patrimônio, motivação) | 27 / 21 | nota | nota |
| outras 14 chaves | — | 0–1 | nota | ignorar |

Negócio (preenchidos entre os 10.145):

| Chaves | Preenchidos | Sugerido | Recomendação |
|---|---|---|---|
| checkout_app, event, event_key, product_id, product_name, purchase_*, transaction, payment_type, payment_installments_number, commissions_producer, subscription_count/installments, currency | 7.200–8.219 | nota | **ignorar** ou só nota curta: é o webhook da Hotmart copiado, e a transação real já está em `fin.hotmart_transacoes` |
| payment_pix_code, payment_pix_url, payment_billet_barcode, payment_billet_url | 4.643 / 563 | nota | **ignorar** (código de pagamento) |
| purchase_origin_sck | 6.649 | nota | nota (ou utm_content) |
| parameters_utm_source / medium / campaign | 21 / 14 / 21 | nota | **utm_source / utm_medium / utm_campaign** (o sugeridor não reconheceu o prefixo `parameters_`) |
| codigo_da_oferta, data_da_compra, id_transacao_hotmart, valor_da_compra | 186 | nota | nota |
| produto_comprado | 186 | campo:produto_interesse | conferir os valores aceitos |
| subscription_status/id/plan_name/canceled_at, payment_refusal_reason | 10–451 | nota | nota |
| objecao_principal | 2 | campo:objecao_principal | ok |
| 47 chaves de formulário/pesquisa (assistiu_a_aula_*, recup_*, score_temperatura, sla_primeiro_contato…) | 0 | nota | não importam neste lote |

## 7. Ensaio da carga (`crm.clint_carregar(lote, true, 2000)`, desfeito)

Uma chamada levou 16 s com limite de 2.000. Com os mapas **sem confirmação**, o ensaio só mostra o efeito sobre os
**contatos**:

| Resultado | Quantidade |
|---|---|
| Contatos processados | 2.000 de 2.039 |
| Casados por e-mail (aluno, comprador ou pessoa já existente) | 1.288 |
| Casados por telefone | 2 |
| Criados (pessoa nova) | 677 |
| Em revisão (`pessoas.revisao`) | 33 |
| Negócios | 2.000 → `pendente_mapa` (nenhum funil confirmado) |
| Atividades | 554 `pendente_contato` + 1 concluída, que vai para o histórico |

Depois do ensaio, a conferência deu `arquivo.clint_resultado` = 0, funis "Clint · …" = 0, `crm.log` com canal
clint_import = 0 e `clint_import_ligado` = false. Repetir o ensaio dá o mesmo resultado, porque ele desfaz tudo e
recomeça pelos mesmos 2.000. O efeito sobre negócios (abertos, duplicados, ganhos casados com Hotmart, perdidos) só
aparece depois de confirmar os mapas.

## 8. Próximos passos (decisões do Arthur)

1. Origens: `importar = false` nas arquivadas e nas de teste; escolher a linha das 18 "sem linha" (Imersão, Curso
   Nacional, Clínica).
2. Etapas: papel das 397 sem papel; corrigir "Comprou Ingresso → fechado"; uma única etapa `fechado` por origem.
3. Usuários: tornar U1 e U2 vendedores (ou fixar o perfil) para não entrarem sem dono.
4. Motivos: escolher um motivo para os 509 "sem motivo"; revisar "Comprou com outra empresa".
5. Campos: `doc` → ignorar; códigos de pagamento e dados duplicados de contato → ignorar; `parameters_utm_*` → utm_*.
6. Vincular os produtos Hotmart às linhas em `crm.produto_comercial`, sem o que nenhum WON vira ganho.
7. Confirmar os mapas, rodar o ensaio de novo e conferir negócios por status e ganhos casados. Só então ligar o
   kill-switch e fazer a carga real.

## 9. Carga real (06/10/2026), com as decisões do Arthur

**Decisões aplicadas aos mapas (só no staging):**
- **Origens:** 12 de trabalho do time com `importar = true` e `confirmado = true`: HT Recuperação de Venda, Evento,
  Direto ao ponto, Recuperacao _HM ([HT] Jornada); MQLS, Interessados, RSVP - MQL, SESSÃO 22/09 (Seminário set/26);
  Seminário - Julho/26; Recuperação – Saldo Implementação Assistida (HM); Leads recuperação e leads disparo
  relacionamento (HT Semanal). As outras 191 ficaram com `importar = false`: as arquivadas, a de teste, os espelhos da
  Hotmart (compras, carrinho, cartão, assinaturas, reembolso, pop-up), as que só trazem campos de transação Hotmart
  (compradores ETHB, Lista Geral, Indicacoes e HT24) e as que não têm linha.
- **Origens de trabalho sem linha (fora por enquanto):**

  | Origem | Abertos |
  |---|---|
  | Curso Nacional de Formação em Holding Familiar / Curso Nacional de Holding Familiar | 26 |
  | Curso Nacional de Formação em Holding Familiar / Ficha de Reserva de Vaga | 2 |
  | Imersão - POA / Cidades | 0 (133 perdidos) |
  | Imersão - POA / Grupo prime | 0 (7 perdidos) |

  As origens de Clínica (POA, GO) são arquivadas. As de Imersão em Holding Familiar são espelhos da Hotmart.
- **Etapas:** 61 confirmadas, no máximo 1 `fechado` por origem e nenhum aberto em etapa `fechado`. A regra usada:
  - `BASE` vira primeiro_contato.
  - "Fechado" e "Saldo acertado" viram fechado.
  - Aguardando, PIX expirado e link/boleto viram aguardar_pagamento.
  - Follow-up, negociação, recuperação e cancelado viram negociar.
  - "Aplicou HM", "Encaminhado ao Comercial" e "Disparo" viram apresentar_oferta.
  - Prospecção, ligações e contato viram primeiro_contato.
  - O resto vira qualificar. "Comprou Ingresso" virou primeiro_contato, e "15/09" (RSVP) virou qualificar.
- **Motivos:** foi criado o motivo "Sem motivo (Clint)" (`sem_motivo_clint`), pela RPC `crm_salvar_motivo_perda`
  com o perfil admin do Arthur. `sem_motivo` aponta para ele. "Comprou com outra empresa" foi corrigido para
  sem_interesse. Os 20 motivos estão mapeados, e os 6 usados pelos perdidos importados estão confirmados.
- **Campos:** `doc`, contato duplicado (email_2/3, contactEmail/Name/Phone, whatsapp_number), transação Hotmart
  (purchase_*, payment_*, subscription_*, transaction, product_*, event*, checkout_app, commissions, currency,
  código/valor/data/ID da compra) e recup_* foram para `ignorar`. `parameters_utm_*` foi para utm_*. Os 121 estão
  confirmados.
- **Usuários:** só os 2 que casam com vendedor ativo estão confirmados. Os outros entram sem dono.
- **Antes da carga:** os 5.121 WON ficaram como `ignorado` com `{"motivo":"ganho_hotmart_fonte"}`, e os 1.189 contatos
  sem negócio importado também ficaram `ignorado`.

**Ensaio completo** (o núcleo da carga 6 vezes em `begin … rollback`): 0 erros, o mesmo resultado da carga real.

**Carga real.** Uma transação liga `clint_import_ligado`, faz 4 chamadas com limite de 2.000 (7,9 s, 4,2 s, 1,1 s e
0,3 s) e desliga o kill-switch. Ele terminou em `false`.

| Prova | Resultado |
|---|---|
| Funis "Clint · …" criados | 12 (ht 6, sv 5, hm 2… ver acima) |
| Negócios criados | 960: 933 abertos e 27 perdidos (`crm.negocio` foi de 2.645 para 3.605) |
| Por linha | sv 611 abertos e 6 perdidos · ht 184 abertos e 11 perdidos · hm 138 abertos e 10 perdidos |
| Dono | 46 com dono (vendedor casado, todos em hm); 914 sem dono |
| Duplicados (2º aberto da mesma pessoa no mesmo funil) | 162, sem negócio novo; ficam ligados ao existente |
| Ignorados | 9.023 negócios (5.121 WON e o resto em origens fora do escopo); 555 atividades (de negócios que não entraram) |
| Contatos | 850 processados: 368 casados por e-mail, 476 criados, 6 em revisão (4 telefone_email_diferente, 1 email_conflito, 1 so_nome) |
| Casados com a base | 349 casam com `compradores` (Hotmart) e 215 com `thb_alunos` (por e-mail) |
| `pessoas.pessoas` | de 2.926 para 3.438 (+512: 476 novas e o resto pessoas criadas por referência a comprador/aluno) |
| Notificações | 0 |
| `crm.log` com canal clint_import | 3.414 linhas, todas com autor_tipo = integracao |
| Notas de importação | 960 (1 por negócio) |
| Erros | 0 |
| Duplicidade com a Hotmart | 0 transações repetidas, 0 no mesmo funil; 3 abertos hm de pessoas que também têm aberto hm vindo da Hotmart (funis diferentes) |
