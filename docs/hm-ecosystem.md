# Ecossistema Financeiro — Holding Masters (HM)

> Mapa autoritativo do ecossistema HM: modelo comercial, ofertas, fluxo de dados
> (Hotmart → webhook → compras → ativação → alunos → financeiro → placas) e as
> **invariantes** que não podem ser quebradas. Ler antes de mexer em qualquer parte
> do financeiro/ativação HM. **Não é um sistema, é um ecossistema** — uma mudança
> num ponto reverbera nos outros.
>
> Fonte do modelo comercial: Obsidian `Segundo-Cerebro-IAs → 11 Marketing HT/
> projetos/holding-total/Oferta-Holding-Masters.md` (transcrição literal da Aula 6,
> "é lei" por instrução do Arthur, 15/07/2026). Atualizar só a partir de nova
> transcrição/gravação, nunca de suposição.

---

## 1. Modelo comercial (autoritativo)

HM = **Programa de Implementação Assistida** / parceria com Contrato de Risco
("só lucro se você lucrar"). Honorário = **20% de R$150.000 = R$30.000**, em duas metades:

| Metade | Valor | Quando / Como |
|---|---|---|
| **1ª metade** | **R$15.000** | Paga no início. **NUNCA à vista → sempre 12× ~R$1.461** (12× já com juros ≈ R$17.532; base R$15.000). Cobre custos de implementação. |
| **2ª metade** | **R$15.000** | **CONDICIONAL** — só devida **depois** que o parceiro **faturar R$150.000** (em até 1 ano). Se não faturar, **não paga**. |

- **Sinal R$300** = reserva de vaga (segunda 7h / 6h45 p/ ficha de interesse). **Reembolsável** e **abatido** do total na Reunião de Contratação.
- **Garantia de risco zero:** seguindo o método e não recuperando a 1ª metade, o Marcio devolve.
- **Acesso anual ao curso / área de membros (renovação) é dimensão SEPARADA** das parcelas. Ver invariante I-1.

Funil: Seminário grátis → low-ticket "Holding Sem Improviso" / Holding Total **R$62** (produto `1560865`) → **HM** (produtos `5064314` core, `3507214` downsell/renovação) → comunidade THB.

---

## 2. Catálogo de ofertas (`public.hm_product_catalog`)

Toda oferta Hotmart do HM precisa estar catalogada por `offer_code` → `categoria`.
Oferta **sem categoria = furo**: escapa da esteira, da razão e da cascata.

### Categorias e o que significam
| categoria | Significado | Natureza na razão (`hm_pagamentos`) |
|---|---|---|
| `sinal` | Reserva de vaga (R$300 entrada, ou R$2k evento) | `sinal` |
| `compra_cheia` | Pacote pago "cheio" (não passou por sinal+saldo) | `saldo` (à vista) / `mensalidade` (parcelado) |
| `diferenca` | **Saldo** = pacote − sinal, pago à vista ou parcelado | `saldo` (à vista) / `mensalidade` (parcelado) |
| `renovacao` | Renovação real (produto `3507214`, ou `235hpjy9`) | — (não é parcela!) |
| `reserva` | Downsell reserva (~R$2k, produto `3507214`) | — |

### Ofertas de saldo dinâmicas
Cada aluno recebe uma oferta de **saldo** própria (`categoria=diferenca`) com o valor
exato do seu saldo (ex.: "Saldo HM R$ 12.772,68"), variante `(recorrente)` quando parcelado.
Product_id fica `NULL` (casam por `offer_code`). São geradas pela ativação — **se a geração
não registrar no catálogo, vira furo** (ver §7).

### Config
- Corte da esteira: `cs.hm_config.cutoff` (compras antes do corte não semeiam card).
- Turma atual: `cs.fn_hm_turma_atual()`.

---

## 3. Topologia do ecossistema (fluxo end-to-end)

```
Hotmart (evento)
   │  hottok
   ▼
hotmart-events-webhook (Edge Function, v58)
   ├─ arquiva payload bruto ....................... cs.hotmart_eventos (todos os eventos)
   ├─ Slack #compras-* (SÓ em PURCHASE_APPROVED) .. métrica de vendas do time
   └─ persistPurchase (upsert) ................... public.compras
          │  (guarda anti-rebaixamento: pendente<pago<estorno)
          │  cascata: preco(bruto) · valor_com_impostos(cliente pagou) ·
          │           taxa_parcelamento(juros) · valor_liquido · taxa_processamento
          ▼
      TRIGGERS em public.compras (ver §4)
          ├─ trg_seed_contato_hm (INSERT) ......... cria card se aprovado
          ├─ trg_seed_contato_hm_upd (UPDATE→pago)  cria card no pagamento (boleto)
          ├─ trg_z_hm_compra_para_razao ........... lança na razão (se tem card)
          └─ trg_hm_compra_cancelada (→refund) .... cancela card + aluno
          ▼
   cs.contatos_hm (esteira/ativação HM) ── fn_hm_provisionar_aluno ──▶ public.thb_alunos
          │                                          (âncora anual = 1ª compra + 365)
          ▼
   cs.hm_pagamentos (razão financeira)
          │  líquido/cascata derivados via JOIN a public.compras
          ▼
   FINANCEIRO (web/modules/financeiro)
     ├─ fn_fin_faturamento_diario (fuso America/Sao_Paulo + cascata)
     ├─ fn_fin_contas_receber / cs.vw_fin_contas_receber (status, saldo, pacote)
     ├─ fn_fin_extrato / fn_fin_compras_aluno (histórico + boletos)
     └─ 2ª metade condicional (§6)

   PLACAS (thb_placas_auditoria.faturamento) ── confirma faturamento do aluno ──▶ gatilho da 2ª metade
```

---

## 4. Triggers em `public.compras` (ordem alfabética = ordem de disparo)

| Trigger | Evento | Função | O que faz |
|---|---|---|---|
| `trg_seed_contato` | INSERT | `cs.fn_seed_contato` | Semeia contato genérico |
| `trg_seed_contato_hm` | INSERT | `cs.fn_seed_contato_hm` | Cria card HM se compra já entra aprovada (sinal/compra_cheia ≥ cutoff) |
| `trg_seed_contato_hm_upd` | UPDATE→pago | `cs.fn_seed_contato_hm` | **Boleto que aprova via UPDATE** cria o card no momento do pagamento |
| `trg_hm_compra_cancelada` | UPDATE→estorno | `cs.fn_hm_compra_cancelada` | REFUNDED/CHARGEBACK/CANCELED → cancela card + marca aluno cancelado + move p/ "Solicitou Cancelamento" |
| `trg_z_hm_compra_para_razao` | INSERT/UPDATE | `cs.fn_hm_compra_para_razao` → `fn_hm_lancar_compra` | Lança pagamento na razão (exige card; nome com 'z' garante rodar DEPOIS do seed) |

`fn_seed_contato_hm` para `compra_cheia`/`diferenca` chama `fn_hm_provisionar_aluno`, que
cria/atualiza o `thb_alunos` e **vincula** `contatos_hm.aluno_id`.

---

## 5. Cascata do dinheiro (reconcilia com o painel Hotmart)

Cada compra tem 5 valores. **Guardar todos** (webhook v58 capta do payload):

```
Cliente pagou (full_price / valor_com_impostos)
  − Juros de parcelamento (taxa_parcelamento)  → ficam com a Hotmart, NÃO é receita
  = Faturamento bruto (price.value / preco)     → o que declaramos
  − Taxa Hotmart (taxa_processamento, comissão MARKETPLACE)
  = Líquido recebido (valor_liquido, comissão PRODUCER)
```

Regras: `cliente_pagou = bruto + juros`; `liquido = bruto − taxa`. À vista (PIX/boleto/1x):
juros=0, cliente_pagou=bruto. **Parcelamento HOTMART_INSTALLMENTS** é o único que gera juros
Hotmart na cascata. Ex. real (Teresa, 12×): 1.142,65 = 994,73 + 147,92; líquido 953,94 = 994,73 − 40,79.

---

## 6. 2ª metade condicional × Placas

- **Hoje (informativo):** card no dashboard mostra R$15.000 × parceiros ativos, fora das contas a receber correntes.
- **Gatilho de "devida":** `thb_placas_auditoria.faturamento` (em **centavos**, valor **confirmado** pelo admin na auditoria) **≥ R$150.000 (= 15.000.000)**. Casa por `aluno_id`.
- **Exemplo validado:** Leandro Francatto — 1ª metade quitada + faturamento confirmado R$1.264.500 → 2ª metade **devida**.
- **Pendente de definição:** como registrar o **pagamento** da 2ª metade (oferta Hotmart nova? lançamento manual?).

---

## 7. Invariantes (guarda-corpos — quebrar = erro no ecossistema)

- **I-1. Parcela ≠ renovação.** Parcela do pacote HM **nunca** renova o anual do curso nem rotula "Renovação". Anual = **1ª compra + 365** (estável). Renovação real = produto `3507214` / oferta de renovação. Aplicado em `fn_hm_provisionar_aluno`, `fn_aluno_360_safe.num_renovacoes`, webhook `isRenovacao`.
- **I-2. Sinal-only = reserva, não aluno.** Quem pagou só o sinal (R$300) é **reserva de vaga** — não vira `thb_alunos` até pagar saldo. No financeiro aparece com badge "Reserva de vaga".
- **I-3. Reembolso propaga.** Compra que vira REFUNDED/CHARGEBACK/CANCELED **cancela** card + aluno automaticamente (`trg_hm_compra_cancelada`). Nunca deixar reembolso só na compra.
- **I-4. Boleto confirma no pagamento.** Card e razão nascem quando o boleto **aprova** (UPDATE→pago), não quando é gerado. Slack só dispara no aprovado.
- **I-5. Toda oferta HM catalogada.** `offer_code` sem linha em `hm_product_catalog` = furo. A geração de oferta de saldo da ativação **deve** registrar no catálogo.
- **I-6. Cascata sempre completa.** Gravar os 5 valores (cliente pagou/juros/bruto/taxa/líquido). Nunca declarar só o bruto sem o full_price quando houver parcelamento.
- **I-7. Fuso BRT.** Agregados diários agrupam em `America/Sao_Paulo` (banco é UTC).
- **I-8. Uma fonte de "quitado".** Base de alunos e financeiro devem concordar; tolerância de centavos (|saldo| < R$1 = quitado) absorve resíduo das 12×.

---

## 8. Furos conhecidos (status em 16/07/2026)

| Furo | Status |
|---|---|
| Boleto aprovado via UPDATE não criava card | ✅ corrigido (`trg_seed_contato_hm_upd`) |
| Reembolso não propagava p/ card/aluno | ✅ corrigido (`trg_hm_compra_cancelada`) |
| Parcela contava como renovação | ✅ corrigido (I-1) |
| Cascata (full_price/juros) não capturada | ✅ webhook v58 + backfill |
| 4 alunos pagaram saldo mas sem ficha vinculada | ✅ vinculados |
| Oferta `e4vq6dyu` fora do catálogo | ✅ catalogada (diferenca) |
| Oferta `6qxsk9kq` (R$2.497, 3 alunos) fora do catálogo | ⏳ **confirmar categoria** (reserva? sinal? compra_cheia?) |
| Geração de oferta de saldo não registra no catálogo | ⏳ investigar o fluxo da ativação |
| 6 `HOTMART_INSTALLMENTS` antigos sem payload (cascata incompleta) | ⏳ só via CSV Hotmart |
| Pagamento da 2ª metade condicional | ⏳ definir registro |
```
