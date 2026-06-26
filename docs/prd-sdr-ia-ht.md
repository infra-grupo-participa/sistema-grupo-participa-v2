# PRD + Spec — CRM SDR: Kanban HT (IA) + Kanban HM (Comercial)

**Versão:** 2.0  
**Data:** 2026-04-15  
**Status:** Draft — aguardando validação

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Problema e Contexto](#2-problema-e-contexto)
3. [Objetivos](#3-objetivos)
4. [Arquitetura do Sistema](#4-arquitetura-do-sistema)
5. [Funil de Etapas (Kanban)](#5-funil-de-etapas-kanban)
6. [Fluxo de Conversa da IA](#6-fluxo-de-conversa-da-ia)
7. [Regras de Transição](#7-regras-de-transição)
8. [Recuperação e Reativação](#8-recuperação-e-reativação)
9. [Integração com Sistema Existente](#9-integração-com-sistema-existente)
10. [Spec Técnica — Banco de Dados](#10-spec-técnica--banco-de-dados)
11. [Spec Técnica — Agentes IA no Banco](#11-spec-técnica--agentes-ia-no-banco)
12. [Spec Técnica — ManyChat](#12-spec-técnica--manychat)
13. [Spec Técnica — Make.com](#13-spec-técnica--makecom)
14. [Spec Técnica — Kanban no Sistema](#14-spec-técnica--kanban-no-sistema)
15. [Spec Técnica — Painel de Agentes no Sistema](#15-spec-técnica--painel-de-agentes-no-sistema)
16. [Cronograma de Implementação](#16-cronograma-de-implementação)
17. [Riscos e Mitigações](#17-riscos-e-mitigações)

---

## 1. Visão Geral

Sistema de CRM com dois Kanbans integrados ao sistema Grupo Participa:

| Kanban | Produto | Operado por | Modelo |
|--------|---------|-------------|--------|
| **Kanban HT** | Holding Total | **IA (SDR automatizado)** | Inbound — lead inicia conversa via link wa.me |
| **Kanban HM** | Holding Masters | **Equipe Comercial (humano)** | Contato íntimo e pessoal |

A IA conduz o lead desde a compra do HT até a conversão no HM. Quando converte, o lead **conclui no Kanban HT** e **entra no Kanban HM**, onde o comercial humano assume.

**Trigger chave:** Abertura de carrinho do HM (pós-live do Dr. Márcio, domingo/segunda) → dispara notificação via IA para todos os leads qualificados do HT (3+ aulas assistidas).

**Critério de qualificação:** Lead com **3 ou mais aulas assistidas** é considerado qualificado para receber oferta do HM.

---

## 2. Problema e Contexto

### Situação atual
- Lead compra HT → cai em `ativacoes` com `ht_status = fazer_onboarding`
- Operadores (cargo `ativacao`) acompanham manualmente: ligação, mensagem padrão, SMS, email
- Ações registradas em `ht_ativacao_logs`
- 5 etapas de ativação já existem (compra → contato → grupo/pesquisa → aulas → ativado)
- Sem automação de conversas — tudo manual

### Dores
- Operadores não escalam para centenas de leads por edição
- Leads esfriam entre a compra e o consumo das aulas
- Carrinhos abandonados do HM não são perseguidos ativamente
- Sem visibilidade unificada do estado de cada lead no funil comercial

---

## 3. Objetivos

| Objetivo | Métrica |
|----------|---------|
| Automatizar primeiro contato pós-compra | 100% dos leads contatados em < 5 min |
| Garantir engajamento nas aulas ao longo da semana | % de leads que reportam ter assistido |
| Recuperar leads desengajados antes de escalar ao comercial | Taxa de recuperação pela IA vs. total desengajados |
| Converter leads para HM via SDR IA | Taxa de conversão HT → HM |
| Visibilidade completa em tempo real | Kanban operacional no sistema |

---

## 4. Arquitetura do Sistema

```
┌──────────────────────────────────────────────────────────────────┐
│                        HOTMART                                    │
│  Lead compra HT → Webhook PURCHASE_APPROVED                      │
└──────────────┬───────────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────┐
│   Edge Function (existe) │
│   hotmart-webhook        │
│   → upsertComprador      │
│   → syncThbAluno         │
│   → insert ativacoes     │
│   → notify Slack         │
└──────────┬───────────────┘
           │ NOVO: webhook para Make.com
           ▼
┌──────────────────────────┐     ┌─────────────────────────┐
│   Make.com               │     │   ManyChat               │
│   Cenário: Nova Compra   │────▶│   (Carteiro — só envia   │
│   → cria lead SDR no DB  │     │    e recebe mensagens)   │
│   → dispara ManyChat     │     │                          │
│                          │     │   Recebe resposta lead   │
│   Cenário: Atualização   │◀────│   → webhook → Make.com   │
│   ← webhook do ManyChat  │     └─────────────────────────┘
│   → busca prompt no DB   │
│   → envia para LLM       │──────────────────────┐
│   → resposta → ManyChat  │                      │
│   → update Supabase      │                      ▼
└──────────┬───────────────┘         ┌─────────────────────┐
           │                         │   OpenAI / Claude    │
           │                         │   API (LLM)          │
           │                         │   ← prompt do banco  │
           │                         │   ← contexto do lead │
           │                         │   → resposta gerada  │
           │                         └─────────────────────┘
           ▼
┌──────────────────────────────────────────────────────────────────┐
│   SUPABASE                                                        │
│   ┌─────────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│   │ ht_sdr_leads    │  │ ativacoes    │  │ ht_sdr_messages   │   │
│   │ (estado funil)  │  │ (já existe)  │  │ (log conversas)   │   │
│   └─────────────────┘  └──────────────┘  └───────────────────┘   │
│   ┌─────────────────┐  ┌──────────────────────┐                  │
│   │ ht_sdr_agentes  │  │ ht_sdr_knowledge     │                  │
│   │ (prompts/config)│  │ (base conhecimento)  │                  │
│   └─────────────────┘  └──────────────────────┘                  │
└──────────────────────────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────────┐
│   SISTEMA GRUPO PARTICIPA                                         │
│   /holding-total/ativacao/                                        │
│   [Dashboard]  [Compradores]  [SDR IA]  [Agentes]  ← novas abas  │
│                                                                    │
│   SDR IA: Kanban visual com colunas por etapa                     │
│   Agentes: Painel de gestão de prompts, tom, base de conhecimento │
└──────────────────────────────────────────────────────────────────┘
```

### Fluxo resumido

1. **Hotmart** → webhook → Edge Function (já existe) → `ativacoes` criada
2. **Edge Function** → POST para Make.com (novo) → cria `ht_sdr_leads` + dispara ManyChat
3. **Email/SMS pós-compra** contém link `wa.me/55XX?text=Oi` → lead inicia conversa
4. **ManyChat** captura → envia webhook para Make.com (ManyChat é só o carteiro)
5. **Make.com** → busca prompt da etapa em `ht_sdr_agentes` → envia para LLM (OpenAI/Claude) com contexto do lead → resposta volta pro ManyChat → envia pro lead
6. **Make.com** → atualiza `ht_sdr_leads`, `ativacoes`, `ht_sdr_messages` no Supabase
7. **Sistema** → aba "SDR IA" lê `ht_sdr_leads` em tempo real → Kanban
8. **Sistema** → aba "Agentes" permite admin editar prompts, tom, knowledge base

### Mudança arquitetural chave

**Antes (v1.0):** ManyChat tinha o AI Step nativo — inteligência acoplada ao canal.

**Agora (v1.1):** ManyChat é apenas o **carteiro** (envia/recebe WhatsApp). A inteligência vive no **Supabase** (prompts, config, knowledge base) e é executada via **LLM externo** (OpenAI/Claude) orquestrado pelo **Make.com**.

**Vantagens:**
- Trocar ManyChat por outra ferramenta = zero retrabalho de IA
- Editar comportamento da IA = UPDATE no banco, sem abrir ManyChat
- A/B test de prompts = duas versões na tabela, flag `ativo`
- Audit trail completo = tudo logado em `ht_sdr_messages`
- Knowledge base versionado e editável pelo admin

---

## 5. Funil de Etapas (Kanban)

### 5.1 Fluxo Principal (Happy Path)

```
┌─────────┐   ┌───────────┐   ┌───────────┐   ┌───────────┐   ┌──────────┐   ┌────────────┐   ┌───────────┐
│  NOVO   │──▶│  GRUPO    │──▶│ ENGAJADO  │──▶│  AULAS    │──▶│ CHECKOUT │──▶│  SDR HM    │──▶│CONVERTIDO │
│  LEAD   │   │  ENVIADO  │   │           │   │ COMPLETAS │   │          │   │            │   │           │
└─────────┘   └───────────┘   └───────────┘   └───────────┘   └──────────┘   └────────────┘   └───────────┘
     │              │               │               │               │              │
     ▼              ▼               ▼               ▼               ▼              ▼
  [RECUP.]      [RECUP.]       [RECUP.]        [RECUP.]       [RECUP.]       [COMERCIAL]
```

### 5.2 Definição das Etapas

| # | Etapa (slug) | Label | Descrição | Quem atua |
|---|-------------|-------|-----------|-----------|
| 0 | `novo_lead` | Novo Lead | Compra confirmada, aguardando lead iniciar contato | Sistema (email com link wa.me) |
| 1 | `grupo_enviado` | Grupo Enviado | IA enviou link do grupo WhatsApp + canal de atendimento | IA |
| 2 | `engajado` | Engajado | Lead respondeu positivamente, está ativo | IA |
| 3 | `aulas_acompanhando` | Acompanhando Aulas | Lead está assistindo aulas e fazendo desafios | IA |
| 4 | `aulas_completas` | Aulas Completas | Lead completou todas as aulas da semana | IA |
| 5 | `checkout_aberto` | Checkout Aberto | Lead recebeu oferta do HM, acessou checkout | IA |
| 6 | `sdr_hm` | SDR HM | Carrinho abandonado — IA tentando recuperar venda | IA (SDR) |
| 7 | `convertido` | Convertido | Lead comprou o HM | Sistema (webhook) |
| 8 | `comercial` | Comercial | IA esgotou tentativas — humano assume | Equipe comercial |
| 9 | `abandonou` | Abandonou | Lead não respondeu/desistiu após todas tentativas | — |
| 10 | `reativacao` | Reativação | Lead de edição anterior sendo reativado para próximo HT | IA |

### 5.3 Fluxo de Recuperação (a cada etapa)

```
Lead sai de rota em qualquer etapa
  → IA envia mensagem de recuperação (#1)
  → Aguarda 24h
  → IA envia mensagem de recuperação (#2 — abordagem diferente)
  → Aguarda 24h
  → IA envia mensagem de recuperação (#3 — última tentativa)
  → Aguarda 48h
  → Se não respondeu → etapa "comercial" (humano assume)
  → Se respondeu → volta ao fluxo principal
```

**Critério de "saiu de rota":**
- Não respondeu em 24h após mensagem da IA
- Respondeu que não assistiu aula e não se comprometeu com data
- Respondeu negativamente sobre interesse
- Não completou desafio após 48h

---

## 5A. Funil de Etapas — Kanban HM (Comercial Humano)

### 5A.1 Fluxo Principal

```
┌───────────┐   ┌──────────┐   ┌────────────────┐   ┌───────────┐   ┌────────────────┐   ┌────────┐   ┌───────────┐
│ NOVO      │──▶│ CONTATO  │──▶│ EM             │──▶│ ENGAJADO  │──▶│ RENOVAÇÃO/     │──▶│ ATIVO  │   │ CANCELADO │
│ ALUNO HM  │   │ INICIAL  │   │ ACOMPANHAMENTO │   │           │   │ UPSELL         │   │        │   │           │
└───────────┘   └──────────┘   └────────────────┘   └───────────┘   └────────────────┘   └────────┘   └───────────┘
      │                                                                                                      │
      ▼                                                                                                      │
  [Automático]        [Comercial move manualmente cada etapa]                                         [Automático]
```

### 5A.2 Definição das Etapas HM

| # | Etapa (slug) | Label | Descrição | Quem move |
|---|-------------|-------|-----------|-----------|
| 0 | `novo_aluno_hm` | Novo Aluno HM | Compra HM confirmada via webhook | Automático |
| 1 | `contato_inicial` | Contato Inicial | Comercial fez primeiro contato | Comercial |
| 2 | `em_acompanhamento` | Em Acompanhamento | Comercial acompanhando o aluno | Comercial |
| 3 | `engajado_hm` | Engajado | Aluno engajado com o programa | Comercial |
| 4 | `renovacao_upsell` | Renovação/Upsell | Oportunidade de upgrade de plano ou renovação | Comercial |
| 5 | `ativo_hm` | Ativo | Aluno plenamente ativo no HM | Comercial |
| 6 | `risco` | Risco | Aluno desengajou — atenção do comercial | Comercial |
| 7 | `cancelado_hm` | Cancelado | Refund/cancelamento confirmado | Automático (webhook) |

### 5A.3 Diferenças HT vs HM

| Aspecto | Kanban HT | Kanban HM |
|---------|-----------|-----------|
| Operação | IA automatizada | Comercial humano |
| Transições | Automáticas (LLM decide) | Manuais (comercial arrasta/clica) |
| Recuperação | IA tenta 3x, depois escala | Comercial decide livremente |
| Foco | Engajar com aulas + converter pra HM | Reter, acompanhar, renovar |
| Volume | Alto (dezenas/centenas por edição) | Baixo (high-ticket, poucos por turma) |
| Comunicação | WhatsApp via ManyChat + LLM | Pessoal — WhatsApp/telefone direto |

### 5A.4 Tabela `hm_sdr_leads`

```sql
CREATE TABLE hm_sdr_leads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ativacao_id     uuid REFERENCES ativacoes(id) ON DELETE CASCADE,
  comprador_id    uuid REFERENCES compradores(id) ON DELETE CASCADE,
  turma_id        integer REFERENCES thb_turmas(id),
  
  -- Estado no funil
  etapa           text NOT NULL DEFAULT 'novo_aluno_hm',
  etapa_anterior  text,
  etapa_changed_at timestamptz DEFAULT now(),
  
  -- Comercial responsável
  responsavel_id  uuid REFERENCES perfis(id),
  responsavel_nome text,
  
  -- Plano
  hm_plano        text,          -- '5k' | '12k' | '24k'
  
  -- Acompanhamento
  ultimo_contato  timestamptz,
  total_contatos  integer DEFAULT 0,
  
  -- Conversão (vindo do HT)
  ht_sdr_lead_id  uuid REFERENCES ht_sdr_leads(id),  -- de onde veio no Kanban HT
  data_entrada    timestamptz DEFAULT now(),
  
  -- Observações
  obs             text,
  
  -- Metadata
  criado_em       timestamptz DEFAULT now(),
  atualizado_em   timestamptz DEFAULT now(),
  
  CONSTRAINT etapa_hm_valida CHECK (etapa IN (
    'novo_aluno_hm', 'contato_inicial', 'em_acompanhamento',
    'engajado_hm', 'renovacao_upsell', 'ativo_hm', 'risco', 'cancelado_hm'
  )),
  CONSTRAINT unique_ativacao_turma UNIQUE (ativacao_id, turma_id)
);

CREATE INDEX idx_hm_sdr_etapa ON hm_sdr_leads(etapa);
CREATE INDEX idx_hm_sdr_turma ON hm_sdr_leads(turma_id);
CREATE INDEX idx_hm_sdr_responsavel ON hm_sdr_leads(responsavel_id);

ALTER TABLE hm_sdr_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ht_operator_select" ON hm_sdr_leads
  FOR SELECT TO authenticated USING (is_ht_operator());
CREATE POLICY "ht_operator_update" ON hm_sdr_leads
  FOR UPDATE TO authenticated USING (is_ht_operator());
CREATE POLICY "admin_all" ON hm_sdr_leads
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND cargo = 'admin' AND status = 'ativo')
  );
```

---

## 5B. Abertura de Carrinho HM — Trigger de Notificação

### 5B.1 Contexto

Toda semana (ou quando houver edição), após a live do Dr. Márcio (geralmente domingo ou segunda), o carrinho do Holding Masters é aberto. Nesse momento, todos os **leads qualificados do HT** devem receber uma notificação via WhatsApp.

### 5B.2 Critério de qualificação

```
Lead qualificado = ht_sdr_leads com:
  - 3 ou mais aulas assistidas (count de ativacoes.ht_aulas[*].assistiu = true >= 3)
  - etapa IN ('aulas_acompanhando', 'aulas_completas')
  - opt_out = false
  - convertido = false
```

### 5B.3 Mecanismo: botão manual + fallback automático

A `ht_editions` ganha 2 campos novos:

```sql
ALTER TABLE ht_editions ADD COLUMN data_abertura_carrinho_hm timestamptz;
ALTER TABLE ht_editions ADD COLUMN carrinho_hm_aberto boolean DEFAULT false;
```

| Mecanismo | Como funciona |
|-----------|---------------|
| **Botão manual** | Admin clica "Abrir Carrinho HM" na aba SDR IA → `carrinho_hm_aberto = true` → Make.com dispara notificação imediatamente |
| **Fallback automático** | Make.com verifica diariamente: se `data_abertura_carrinho_hm <= now()` e `carrinho_hm_aberto = false` → dispara automaticamente |
| **O que ocorrer primeiro vence** | Se admin clicou, o fallback não roda. Se não clicou, o fallback garante. |

### 5B.4 Fluxo do disparo

```
Admin clica "Abrir Carrinho HM" (ou fallback automático)
  │
  ├─ UPDATE ht_editions SET carrinho_hm_aberto = true WHERE id = edição_atual
  │
  ├─ Make.com busca leads qualificados:
  │   SELECT l.*, c.telefone, c.nome
  │   FROM ht_sdr_leads l
  │   JOIN compradores c ON c.id = l.comprador_id
  │   JOIN ativacoes a ON a.id = l.ativacao_id
  │   WHERE l.ht_edition_id = edição_atual
  │     AND l.opt_out = false
  │     AND l.convertido = false
  │     AND l.etapa IN ('aulas_acompanhando', 'aulas_completas', 'engajado')
  │     AND (contagem de aulas assistidas em a.ht_aulas) >= 3
  │
  ├─ Para cada lead:
  │   ├─ Busca agente slug = 'oferta_hm' em ht_sdr_agentes
  │   ├─ Monta prompt com contexto do lead + knowledge base
  │   ├─ Chama LLM → gera mensagem personalizada
  │   ├─ Envia via ManyChat API
  │   ├─ UPDATE ht_sdr_leads SET etapa = 'checkout_aberto'
  │   └─ INSERT ht_sdr_messages (registro do envio)
  │
  └─ Notifica Slack: "🔥 Carrinho HM aberto — {N} leads notificados"
```

### 5B.5 Mensagem da IA (exemplo)

```
"{nome}, acabou de sair! 🔥

O Dr. Márcio apresentou o Holding Masters na live de hoje.
O carrinho está aberto e as vagas são limitadas.

Você já assistiu {aulas_assistidas} aulas e fez {desafios_feitos} desafios 
— tá mais que preparado pro próximo passo.

Quer ver as condições especiais? 👇
{link_checkout_hm}"
```

### 5B.6 UI — Botão no sistema

Na aba "SDR IA", na barra de filtros, ao lado do seletor de edição:

```
[Edição: HT23 ▾]  [Buscar lead...]  [🔥 Abrir Carrinho HM]
                                      ↑ só aparece se carrinho_hm_aberto = false
                                      ↑ admin only
```

Após clicar:
- Confirmação: "Isso vai notificar X leads qualificados. Confirmar?"
- Botão muda para: "✅ Carrinho HM aberto" (desabilitado, verde)

---

## 5C. Transição HT → HM (Conversão)

### 5C.1 O que acontece quando o lead compra o HM

```
Webhook Hotmart PURCHASE_APPROVED do HM
  │
  ├─ Edge Function hotmart-hm-webhook (já existe)
  │   → upsertComprador, syncThbAluno, insert compra, insert ativação HM
  │
  ├─ NOVO: Make.com Cenário 3 (Conversão)
  │   │
  │   ├─ Kanban HT: UPDATE ht_sdr_leads
  │   │   SET etapa = 'convertido', convertido = true, data_conversao = now()
  │   │
  │   ├─ Kanban HM: INSERT hm_sdr_leads
  │   │   {ativacao_id, comprador_id, turma_id, etapa: 'novo_aluno_hm',
  │   │    hm_plano, ht_sdr_lead_id (referência de onde veio)}
  │   │
  │   ├─ IA envia mensagem de parabéns no WhatsApp (último contato da IA)
  │   │
  │   └─ Notifica Slack: "🎉 {nome} converteu HT→HM (plano {plano})"
  │
  └─ A partir daqui: comercial humano assume no Kanban HM
```

### 5C.2 Rastreabilidade

O campo `hm_sdr_leads.ht_sdr_lead_id` cria o link entre os dois Kanbans. No drawer do Kanban HM, o operador pode ver:
- "Veio do HT23"
- Quantas aulas assistiu
- Quantas interações teve com a IA
- Quanto tempo levou da compra HT até a conversão HM

---

## 6. Fluxo de Conversa da IA

### 6.1 Onboarding (Etapas 0 → 1 → 2)

**Trigger:** Lead envia mensagem no WhatsApp (via link wa.me)

```
IA: "Oi, {nome}! 🎉 Bem-vindo ao Holding Total {edição}!
     Sou o assistente do Grupo Participa.
     
     Primeiro passo: entre no nosso grupo de avisos 👇
     {grupo_link}
     
     E nosso canal de atendimento fica aqui: {canal_atendimento_link}
     
     Me avisa quando entrar no grupo que eu te passo os próximos passos!"

Lead: "Entrei"

IA: "Perfeito! ✅ Agora vou te acompanhar durante toda a semana.
     As aulas serão liberadas no nosso canal do YouTube.
     Vou te avisar quando cada aula estiver disponível.
     
     Posso te enviar os avisos aqui pelo WhatsApp?"

Lead: "Pode sim"

→ Etapa avança para "engajado"
→ Webhook → Make.com → Supabase (ht_sdr_leads.etapa = 'engajado')
→ Atualiza ativacoes.entrou_grupo_whatsapp = true
```

### 6.2 Acompanhamento de Aulas (Etapas 2 → 3 → 4)

**Trigger:** Timer/delay no ManyChat (alinhado ao calendário de aulas da edição)

Para cada aula (1 a 6, conforme `ht_editions.yt_aulas`):

```
IA: "E aí, {nome}! A aula {N} já está disponível 🔥
     {link_aula}
     
     Você vai assistir ao vivo ou fica pro replay?"

[Opções interativas — botões ManyChat]
→ "Vou ao vivo" → registra aula N: ao_vivo = true
→ "Vejo o replay" → registra aula N: replay = true
→ [Não responde em 24h] → Recuperação #1

---

Após assistir:

IA: "Show! E o desafio da aula {N}, já fez?"

→ "Sim, fiz!" → registra aula N: desafio = true
→ "Ainda não" → IA incentiva + agenda lembrete 24h
→ [Não responde] → Recuperação #1
```

**Atualização no banco a cada interação:**
```
ativacoes.ht_aulas[N] = { assistiu: true, ao_vivo: true/false, replay: true/false, desafio: true/false }
ht_sdr_leads.etapa = 'aulas_acompanhando' (se < todas) ou 'aulas_completas' (se todas)
```

### 6.3 Oferta HM (Etapas 4 → 5)

**Trigger:** Lead completou aulas (ou está na última aula)

```
IA: "{nome}, parabéns por ter concluído as aulas! 🏆
     
     Você tá pronto pro próximo passo. O Holding Masters é onde 
     os resultados realmente acontecem — é o programa completo 
     com mentoria e acompanhamento.
     
     Quer saber mais sobre as condições especiais dessa edição?"

→ "Quero" → IA apresenta planos (5k/12k) + link checkout
→ "Agora não" → IA agenda follow-up 24h
→ [Não responde] → Recuperação #1
```

### 6.4 SDR Carrinho Abandonado (Etapas 5 → 6)

**Trigger:** Webhook Hotmart `PURCHASE_WAITING_PAYMENT` ou `ABANDONED_CART` + tempo sem `PURCHASE_APPROVED` do HM

```
IA: "{nome}, vi que você começou a garantir sua vaga no 
     Holding Masters mas não finalizou. 
     
     Aconteceu alguma coisa? Posso te ajudar com alguma dúvida 
     sobre os planos?"

→ Lead responde dúvida → IA resolve (knowledge base com FAQ HM)
→ Lead pede desconto → IA escala para comercial (flag)
→ Lead ignora → Recuperação #2 (48h) → Recuperação #3 (48h)
→ Esgotou tentativas → etapa 'comercial'
```

### 6.5 Conversão (Etapa 7)

**Trigger:** Webhook Hotmart `PURCHASE_APPROVED` do HM

```
→ Automático: etapa = 'convertido', data_conversao = now()
→ IA envia mensagem de parabéns (opcional)
→ Lead sai do funil SDR IA do HT
→ A partir daqui, equipe comercial HM assume (fase posterior)
```

---

## 7. Regras de Transição

### 7.1 Transições Automáticas (sistema/webhook)

| De | Para | Gatilho |
|----|------|---------|
| — | `novo_lead` | Webhook `PURCHASE_APPROVED` do HT |
| `novo_lead` | `grupo_enviado` | Lead inicia conversa no WhatsApp + IA envia grupo |
| `engajado` | `aulas_acompanhando` | Lead reporta ter assistido pelo menos 1 aula |
| `aulas_acompanhando` | `aulas_completas` | Todas as aulas da edição assistidas |
| `aulas_completas` | `checkout_aberto` | IA apresentou oferta HM + lead demonstrou interesse |
| `checkout_aberto` | `sdr_hm` | Webhook carrinho abandonado ou timeout 48h sem compra |
| Qualquer | `convertido` | Webhook `PURCHASE_APPROVED` do HM |
| Qualquer | `abandonou` | IA esgotou tentativas + comercial não converteu |
| `abandonou` | `reativacao` | 3 dias antes do próximo HT (automático) |

### 7.2 Transições Manuais (operador)

| Ação | Quem |
|------|------|
| Mover para `comercial` a qualquer momento | Admin / Ativação |
| Mover de `comercial` → `convertido` | Admin |
| Mover de `comercial` → `abandonou` | Admin |
| Forçar qualquer transição | Admin |
| Adicionar observação/nota | Admin / Ativação |

### 7.3 Regras de Recuperação

```
tentativas_recuperacao: máximo 3 por etapa
intervalo_entre_tentativas: 24h (exceto última: 48h)
tempo_total_maximo_por_etapa: 5 dias (após isso → comercial)
tempo_total_funil: duração do HT (1 semana padrão) + 7 dias pós
```

**A IA não persiste após:**
- Lead pedir explicitamente para parar (opt-out) → etapa `abandonou`
- Lead já estar em `comercial` → humano assume
- Lead já ter convertido → `convertido`

---

## 8. Recuperação e Reativação

### 8.1 Recuperação dentro do HT ativo

Quando o lead sai de rota em qualquer etapa, a IA segue este protocolo:

| Tentativa | Tempo | Abordagem |
|-----------|-------|-----------|
| #1 | +24h | Mensagem amigável, pergunta se precisa de ajuda |
| #2 | +24h | Mensagem com senso de urgência (aula expirando, turma avançando) |
| #3 | +48h | Última tentativa — proposta direta ou pergunta se quer parar |
| Escalada | +0h | Move para `comercial`, notifica time no Slack |

### 8.2 Reativação entre edições

```
Lead abandonou no HT23
  → ht_sdr_leads.etapa = 'abandonou'
  → ht_sdr_leads.edicao_abandonou = 'HT23'
  
3 dias antes do HT25 abrir:
  → Sistema cria nova entrada ht_sdr_leads para HT25
  → ht_sdr_leads.etapa = 'reativacao'
  → ht_sdr_leads.edicao_origem = 'HT23'
  → Make.com dispara ManyChat flow de reativação

IA: "Oi, {nome}! Tudo bem? 
     Faz um tempo que a gente se falou. 
     O Holding Total {nova_edição} começa em {data}. 
     Essa pode ser a sua vez de dar o próximo passo. 
     Quer garantir sua vaga?"

→ "Quero" → volta ao fluxo principal (etapa 'novo_lead' da nova edição)
→ Ignora → 2 tentativas → 'abandonou' definitivo (não reativa mais para este lead)
```

### 8.3 Critério de reativação

| Critério | Valor |
|----------|-------|
| Tempo antes do próximo HT | 3 dias |
| Máximo de reativações por lead | 2 (após isso, descarta) |
| Ignora se já converteu HM | Sim (verificar via webhook) |
| Ignora se pediu opt-out | Sim |

---

## 9. Integração com Sistema Existente

### 9.1 O que já existe e se mantém

| Componente | Status | Ação |
|------------|--------|------|
| `ativacoes` (tabela) | Existe | Mantém — SDR lê e atualiza campos existentes |
| `ht_ativacao_logs` (tabela) | Existe | Mantém — SDR IA registra ações como tipo `sdr_ia_*` |
| `ht_editions` (tabela) | Existe | Mantém — SDR lê `grupo_link`, `yt_aulas` |
| `compradores` (tabela) | Existe | Mantém — SDR lê `telefone` para WhatsApp |
| Webhook Hotmart → Edge Function | Existe | Estende — adiciona POST para Make.com |
| Aba Dashboard em ativação | Existe | Mantém |
| Aba Compradores em ativação | Existe | Mantém |
| Drawer com fluxo 5 etapas | Existe | Mantém — SDR atualiza os mesmos campos |

### 9.2 O que é novo

| Componente | Descrição |
|------------|-----------|
| `ht_sdr_leads` (tabela) | Estado do lead no funil SDR IA |
| `ht_sdr_messages` (tabela) | Log de mensagens trocadas com a IA |
| `ht_sdr_agentes` (tabela) | Prompts, tom, regras de transição, modelo LLM por etapa |
| `ht_sdr_knowledge` (tabela) | Base de conhecimento (FAQ, objeções, depoimentos) |
| Aba "SDR IA" na ativação | Kanban visual com colunas por etapa |
| Aba "Agentes" na ativação | Painel admin para editar prompts, knowledge base, testar IA |
| Cenários Make.com | Orquestração: ManyChat ↔ LLM ↔ Supabase |
| Flows no ManyChat | Simplificados — só carteiro (Default Reply → webhook, Send Message, Opt-Out) |

### 9.3 Sincronização com `ativacoes`

O SDR IA **atualiza** campos que já existem em `ativacoes`:

| Campo em `ativacoes` | Quando o SDR atualiza |
|----------------------|----------------------|
| `entrou_grupo_whatsapp` | Lead confirma que entrou no grupo |
| `data_entrada_whatsapp` | Timestamp da confirmação |
| `ht_respondeu_pesquisa` | Lead responde pesquisa via bot |
| `ht_data_pesquisa` | Timestamp da resposta |
| `ht_aulas[N].assistiu` | Lead reporta que assistiu aula N |
| `ht_aulas[N].ao_vivo` | Lead diz que assistiu ao vivo |
| `ht_aulas[N].replay` | Lead diz que assistiu replay |
| `ht_aulas[N].desafio` | Lead confirma que fez desafio |
| `ht_status` | Avança para `em_ativacao` ou `ativado` |
| `ht_data_ativacao` | Quando ativado |
| `ultima_movimentacao` | A cada interação |

### 9.4 Novos tipos de ação em `ht_ativacao_logs`

| `tipo_acao` | Descrição |
|-------------|-----------|
| `sdr_ia_onboarding` | IA enviou mensagem de boas-vindas |
| `sdr_ia_grupo` | IA enviou link do grupo |
| `sdr_ia_aula_lembrete` | IA lembrou sobre aula |
| `sdr_ia_aula_confirmacao` | Lead confirmou que assistiu |
| `sdr_ia_desafio` | Lead confirmou desafio |
| `sdr_ia_oferta_hm` | IA apresentou oferta HM |
| `sdr_ia_recuperacao` | IA tentou recuperar lead |
| `sdr_ia_escalacao` | IA escalou para comercial |

---

## 10. Spec Técnica — Banco de Dados

### 10.1 Tabela `ht_sdr_leads`

```sql
CREATE TABLE ht_sdr_leads (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ativacao_id   uuid REFERENCES ativacoes(id) ON DELETE CASCADE,
  comprador_id  uuid REFERENCES compradores(id) ON DELETE CASCADE,
  ht_edition_id integer REFERENCES ht_editions(id),
  
  -- Estado no funil
  etapa         text NOT NULL DEFAULT 'novo_lead',
  etapa_anterior text,
  etapa_changed_at timestamptz DEFAULT now(),
  
  -- Recuperação
  tentativas_recuperacao integer DEFAULT 0,
  max_tentativas integer DEFAULT 3,
  proxima_tentativa_em timestamptz,
  
  -- ManyChat
  manychat_subscriber_id text,
  manychat_flow_id text,
  whatsapp_phone text,         -- telefone normalizado E.164
  
  -- Acompanhamento
  ultimo_contato_ia timestamptz,
  ultima_resposta_lead timestamptz,
  total_mensagens_ia integer DEFAULT 0,
  total_respostas_lead integer DEFAULT 0,
  
  -- Flags
  opt_out boolean DEFAULT false,
  escalado_comercial boolean DEFAULT false,
  data_escalacao timestamptz,
  
  -- Conversão
  convertido boolean DEFAULT false,
  data_conversao timestamptz,
  hm_compra_id uuid,           -- FK para compra do HM se converteu
  
  -- Reativação
  reativacao_count integer DEFAULT 0,
  edicao_origem text,           -- de qual edição foi reativado (ex: 'HT23')
  
  -- Observações
  obs text,
  
  -- Metadata
  criado_em timestamptz DEFAULT now(),
  atualizado_em timestamptz DEFAULT now(),
  
  -- Constraints
  CONSTRAINT etapa_valida CHECK (etapa IN (
    'novo_lead', 'grupo_enviado', 'engajado', 
    'aulas_acompanhando', 'aulas_completas',
    'checkout_aberto', 'sdr_hm', 
    'convertido', 'comercial', 'abandonou', 'reativacao'
  )),
  CONSTRAINT unique_ativacao_edition UNIQUE (ativacao_id, ht_edition_id)
);

-- Indexes
CREATE INDEX idx_sdr_leads_etapa ON ht_sdr_leads(etapa);
CREATE INDEX idx_sdr_leads_edition ON ht_sdr_leads(ht_edition_id);
CREATE INDEX idx_sdr_leads_comprador ON ht_sdr_leads(comprador_id);
CREATE INDEX idx_sdr_leads_manychat ON ht_sdr_leads(manychat_subscriber_id) WHERE manychat_subscriber_id IS NOT NULL;
CREATE INDEX idx_sdr_leads_proxima_tentativa ON ht_sdr_leads(proxima_tentativa_em) WHERE proxima_tentativa_em IS NOT NULL;

-- RLS
ALTER TABLE ht_sdr_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ht_operator_select" ON ht_sdr_leads
  FOR SELECT TO authenticated USING (is_ht_operator());

CREATE POLICY "ht_operator_update" ON ht_sdr_leads
  FOR UPDATE TO authenticated USING (is_ht_operator());

CREATE POLICY "admin_all" ON ht_sdr_leads
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND cargo = 'admin' AND status = 'ativo')
  );

-- Service role (Make.com) precisa de acesso irrestrito via service_role key
```

### 10.2 Tabela `ht_sdr_messages`

```sql
CREATE TABLE ht_sdr_messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sdr_lead_id   uuid REFERENCES ht_sdr_leads(id) ON DELETE CASCADE,
  
  direcao       text NOT NULL,  -- 'ia_para_lead' | 'lead_para_ia'
  conteudo      text,           -- texto da mensagem
  tipo          text,           -- 'onboarding' | 'aula_lembrete' | 'recuperacao' | 'oferta' | 'resposta' | 'opt_out'
  
  -- ManyChat metadata
  manychat_message_id text,
  manychat_flow_step text,
  
  -- Resultado da IA (quando interpreta resposta do lead)
  ia_interpretacao text,        -- 'positivo' | 'negativo' | 'duvida' | 'opt_out' | 'irrelevante'
  ia_acao_tomada text,          -- 'avancou_etapa' | 'enviou_recuperacao' | 'escalou_comercial'
  
  criado_em timestamptz DEFAULT now()
);

CREATE INDEX idx_sdr_messages_lead ON ht_sdr_messages(sdr_lead_id);
CREATE INDEX idx_sdr_messages_direcao ON ht_sdr_messages(direcao);

ALTER TABLE ht_sdr_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ht_operator_select" ON ht_sdr_messages
  FOR SELECT TO authenticated USING (is_ht_operator());
```

### 10.3 Alterações em tabelas existentes

```sql
-- Nenhuma alteração de schema em tabelas existentes.
-- O SDR usa campos que já existem em ativacoes (ht_aulas, entrou_grupo_whatsapp, etc.)
-- Novos tipos de ação são apenas strings em ht_ativacao_logs.tipo_acao (sem constraint)
```

---

## 11. Spec Técnica — Agentes IA no Banco

### 11.1 Conceito

A inteligência do SDR **não vive no ManyChat**. Vive no Supabase. O ManyChat é apenas o **carteiro** — envia e recebe mensagens no WhatsApp. Quem decide o que dizer é o prompt armazenado no banco, executado por um LLM externo (OpenAI/Claude) via Make.com.

```
Lead responde no WhatsApp
  → ManyChat recebe → webhook → Make.com
  → Make.com busca ht_sdr_agentes WHERE etapa = etapa_atual AND ativo = true
  → Make.com monta payload: { system: prompt_sistema, context: dados_lead, user: mensagem_lead }
  → Make.com chama OpenAI/Claude API
  → Resposta do LLM → Make.com envia via ManyChat API → lead recebe
  → Make.com avalia se muda etapa (via regras no prompt ou resposta estruturada do LLM)
  → Make.com atualiza Supabase (ht_sdr_leads, ht_sdr_messages, ativacoes)
```

### 11.2 Tabela `ht_sdr_agentes`

```sql
CREATE TABLE ht_sdr_agentes (
  id              serial PRIMARY KEY,
  
  -- Identificação
  nome            text NOT NULL,              -- "Onboarding HT23", "Recuperação Aula", etc.
  slug            text NOT NULL UNIQUE,       -- 'onboarding', 'aula_lembrete', 'recuperacao', etc.
  etapa           text NOT NULL,              -- etapa do funil onde este agente atua
  
  -- Prompt
  prompt_sistema  text NOT NULL,              -- system prompt enviado ao LLM
  prompt_mensagem text,                       -- template de mensagem (com placeholders {nome}, {grupo_link}, etc.)
  
  -- Comportamento
  tom             text DEFAULT 'amigavel',    -- 'amigavel' | 'urgente' | 'direto' | 'motivacional'
  temperatura     numeric(2,1) DEFAULT 0.7,   -- temperatura do LLM (0.0 a 1.0)
  modelo_llm      text DEFAULT 'gpt-4o-mini', -- modelo a usar: 'gpt-4o-mini', 'gpt-4o', 'claude-sonnet-4-6'
  max_tokens      integer DEFAULT 300,        -- limite de tokens na resposta
  
  -- Recuperação
  max_tentativas  integer DEFAULT 3,          -- tentativas antes de escalar
  intervalo_horas integer DEFAULT 24,         -- horas entre tentativas
  
  -- Regras de transição (JSON)
  regras_transicao jsonb DEFAULT '[]'::jsonb,
  -- Exemplo: [
  --   {"condicao": "resposta_positiva", "acao": "avancar_etapa", "nova_etapa": "engajado"},
  --   {"condicao": "sem_resposta_24h", "acao": "recuperacao", "tentativa": 1},
  --   {"condicao": "opt_out", "acao": "encerrar"},
  --   {"condicao": "esgotou_tentativas", "acao": "escalar_comercial"}
  -- ]
  
  -- Escopo
  ht_edition_id   integer REFERENCES ht_editions(id),  -- NULL = global, preenchido = por edição
  ativo           boolean DEFAULT true,
  versao          integer DEFAULT 1,
  
  -- Metadata
  criado_em       timestamptz DEFAULT now(),
  atualizado_em   timestamptz DEFAULT now(),
  criado_por      uuid REFERENCES perfis(id)
);

CREATE INDEX idx_sdr_agentes_etapa ON ht_sdr_agentes(etapa);
CREATE INDEX idx_sdr_agentes_ativo ON ht_sdr_agentes(ativo) WHERE ativo = true;
CREATE INDEX idx_sdr_agentes_edition ON ht_sdr_agentes(ht_edition_id);

ALTER TABLE ht_sdr_agentes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_all" ON ht_sdr_agentes
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND cargo = 'admin' AND status = 'ativo')
  );

CREATE POLICY "ht_operator_select" ON ht_sdr_agentes
  FOR SELECT TO authenticated USING (is_ht_operator());
```

### 11.3 Tabela `ht_sdr_knowledge`

Base de conhecimento que a IA consulta para responder dúvidas dos leads.

```sql
CREATE TABLE ht_sdr_knowledge (
  id              serial PRIMARY KEY,
  
  -- Conteúdo
  titulo          text NOT NULL,              -- "O que é o Holding Masters?", "Planos HM", etc.
  categoria       text NOT NULL,              -- 'produto_ht' | 'produto_hm' | 'pagamento' | 'suporte' | 'objecoes'
  conteudo        text NOT NULL,              -- texto completo da resposta/informação
  tags            text[] DEFAULT '{}',        -- tags para busca: {'preco', 'plano', '5k', '12k'}
  
  -- Escopo
  ht_edition_id   integer REFERENCES ht_editions(id),  -- NULL = global
  ativo           boolean DEFAULT true,
  prioridade      integer DEFAULT 0,          -- maior = mais relevante quando múltiplos matches
  
  -- Metadata
  criado_em       timestamptz DEFAULT now(),
  atualizado_em   timestamptz DEFAULT now(),
  criado_por      uuid REFERENCES perfis(id)
);

CREATE INDEX idx_sdr_knowledge_categoria ON ht_sdr_knowledge(categoria);
CREATE INDEX idx_sdr_knowledge_tags ON ht_sdr_knowledge USING gin(tags);
CREATE INDEX idx_sdr_knowledge_ativo ON ht_sdr_knowledge(ativo) WHERE ativo = true;

ALTER TABLE ht_sdr_knowledge ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_all" ON ht_sdr_knowledge
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND cargo = 'admin' AND status = 'ativo')
  );

CREATE POLICY "ht_operator_select" ON ht_sdr_knowledge
  FOR SELECT TO authenticated USING (is_ht_operator());
```

### 11.4 Agentes pré-configurados

| Slug | Etapa | Tom | Prompt (resumo) |
|------|-------|-----|-----------------|
| `onboarding` | `novo_lead` → `grupo_enviado` | Amigável | Boas-vindas, envia grupo, canal atendimento |
| `engajamento` | `grupo_enviado` → `engajado` | Amigável | Confirma que entrou no grupo, apresenta semana |
| `aula_lembrete` | `engajado` → `aulas_acompanhando` | Motivacional | Avisa sobre aula disponível, pergunta se assistiu |
| `aula_desafio` | `aulas_acompanhando` | Motivacional | Pergunta se fez desafio, incentiva |
| `aula_completa` | `aulas_acompanhando` → `aulas_completas` | Amigável | Parabeniza por completar todas as aulas |
| `oferta_hm` | `aulas_completas` → `checkout_aberto` | Direto | Apresenta HM, planos, link de checkout |
| `sdr_carrinho` | `checkout_aberto` → `sdr_hm` | Urgente | Recupera carrinho abandonado, resolve dúvidas |
| `recuperacao_leve` | Qualquer (tentativa 1) | Amigável | "Tá tudo bem? Posso te ajudar?" |
| `recuperacao_media` | Qualquer (tentativa 2) | Urgente | "A turma já tá avançando, não fica pra trás!" |
| `recuperacao_final` | Qualquer (tentativa 3) | Direto | "Última chance antes de eu te passar pro time" |
| `reativacao` | `reativacao` | Amigável | Convida lead dormido para nova edição |

### 11.5 Prompt completo — Exemplo (Onboarding)

```
[SYSTEM]
Você é o assistente comercial do Grupo Participa. Seu nome é GP.
Você acompanha alunos do Holding Total na jornada de aprendizado.

PERSONALIDADE:
- Tom: {tom} (amigável/urgente/direto/motivacional)
- Mensagens curtas: máximo 3 parágrafos
- Use o nome do lead: {nome}
- Emojis com moderação: 1-2 por mensagem
- Nunca invente dados sobre o curso

CONTEXTO DO LEAD:
- Nome: {nome}
- Edição: {edicao}
- Etapa atual: {etapa}
- Aulas assistidas: {aulas_assistidas}/6
- Desafios feitos: {desafios_feitos}/6
- Entrou no grupo: {entrou_grupo}
- Tentativas de recuperação: {tentativas}/{max_tentativas}
- Histórico recente: {ultimas_3_mensagens}

KNOWLEDGE BASE (consulte para dúvidas):
{knowledge_base_relevante}

REGRAS:
1. Se o lead confirmar que entrou no grupo → responda com próximos passos e atualize: entrou_grupo = true
2. Se o lead perguntar algo que você não sabe → diga que vai encaminhar pro suporte
3. Se o lead pedir para parar → respeite imediatamente, diga "Sem problemas, {nome}. Qualquer coisa é só chamar!"
4. Nunca fale de preço do HM a menos que o lead pergunte
5. Nunca prometa desconto

FORMATO DA RESPOSTA (JSON):
{
  "mensagem": "texto para enviar ao lead",
  "interpretacao": "positivo|negativo|duvida|opt_out|irrelevante",
  "acao": "avancar_etapa|manter|recuperacao|escalar_comercial|encerrar",
  "nova_etapa": "slug da nova etapa (se acao = avancar_etapa)",
  "atualizar_campos": {
    "entrou_grupo_whatsapp": true,
    "ht_aulas": {"1": {"assistiu": true, "ao_vivo": true}}
  }
}

[USER]
Mensagem do lead: {mensagem_do_lead}
```

### 11.6 Fluxo de resolução do agente

```
1. Make.com recebe webhook do ManyChat (lead respondeu)
2. Busca ht_sdr_leads pelo subscriber_id → pega etapa atual
3. Busca ht_sdr_agentes WHERE etapa = etapa_atual AND ativo = true
   → Se ht_edition_id preenchido E match → usa esse (específico da edição)
   → Se não → usa WHERE ht_edition_id IS NULL (global)
4. Busca ht_sdr_knowledge WHERE categoria IN (categorias relevantes) AND ativo = true
5. Monta prompt com placeholders preenchidos
6. Chama LLM API (OpenAI/Claude)
7. Parseia resposta JSON
8. Executa ação:
   - avancar_etapa → UPDATE ht_sdr_leads.etapa
   - recuperacao → incrementa tentativas, agenda próxima
   - escalar_comercial → etapa = 'comercial', notifica Slack
   - encerrar → etapa = 'abandonou', opt_out = true
9. Envia mensagem via ManyChat API
10. Loga tudo em ht_sdr_messages
```

### 11.7 Versionamento e A/B Testing

```sql
-- Para A/B test: dois agentes ativos para mesma etapa, mesmo edition
-- Make.com escolhe aleatoriamente (ou por regra: lead_id par/ímpar)

SELECT * FROM ht_sdr_agentes 
WHERE etapa = 'recuperacao_leve' 
  AND ativo = true 
  AND (ht_edition_id = 23 OR ht_edition_id IS NULL)
ORDER BY ht_edition_id DESC NULLS LAST, versao DESC
LIMIT 1;  -- prioriza edição específica, depois global, depois versão mais recente
```

Para rodar A/B test real:
```sql
-- Agente A (controle)
INSERT INTO ht_sdr_agentes (slug, etapa, nome, prompt_sistema, tom, versao, ativo)
VALUES ('recuperacao_leve_a', 'engajado', 'Recuperação Leve A', '...prompt amigável...', 'amigavel', 1, true);

-- Agente B (variante)
INSERT INTO ht_sdr_agentes (slug, etapa, nome, prompt_sistema, tom, versao, ativo)
VALUES ('recuperacao_leve_b', 'engajado', 'Recuperação Leve B', '...prompt urgente...', 'urgente', 1, true);

-- Make.com: se lead_id hash % 2 == 0 → agente A, senão → agente B
-- Resultados: comparar taxa de resposta por agente em ht_sdr_messages
```

---

## 12. Spec Técnica — ManyChat

### 12.1 Setup

| Item | Configuração |
|------|-------------|
| Canal | WhatsApp Business API (número a definir) |
| AI Step | **Desabilitado** — IA roda via Make.com + LLM externo |
| Keyword Trigger | Qualquer mensagem (Default Reply) → webhook para Make.com |
| Custom Fields | Ver 12.2 |

### 12.2 Custom Fields no ManyChat

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `gp_comprador_id` | Text | UUID do comprador no Supabase |
| `gp_ativacao_id` | Text | UUID da ativação no Supabase |
| `gp_sdr_lead_id` | Text | UUID do ht_sdr_leads no Supabase |
| `gp_edicao` | Text | Label da edição (ex: "HT23") |
| `gp_etapa` | Text | Etapa atual no funil |
| `gp_nome` | Text | Nome do lead |
| `gp_grupo_link` | Text | Link do grupo WhatsApp da edição |
| `gp_aulas_assistidas` | Number | Contador de aulas assistidas |
| `gp_desafios_feitos` | Number | Contador de desafios feitos |
| `gp_tentativas_recuperacao` | Number | Tentativas de recuperação nesta etapa |
| `gp_opt_out` | Boolean | Lead pediu para parar |

### 12.3 Flows no ManyChat

O ManyChat agora funciona como **carteiro** — os flows são simples:

| Flow | Trigger | O que faz |
|------|---------|-----------|
| **Default Reply** | Qualquer mensagem recebida | Envia webhook para Make.com com {phone, text, subscriber_id} |
| **Send Message** | External Trigger (Make.com) | Recebe texto do Make.com → envia pro lead |
| **Opt-Out** | Keyword "parar/sair/cancelar" | Webhook para Make.com + para automações |

> **Nota:** AI Step do ManyChat **desabilitado**. Toda inteligência vem do LLM externo via Make.com, usando prompts do `ht_sdr_agentes`.

### 12.4 Webhooks ManyChat → Make.com

Cada Custom Action no ManyChat envia POST para Make.com com:

```json
{
  "event": "etapa_changed",
  "subscriber_id": "{{manychat_subscriber_id}}",
  "phone": "{{phone}}",
  "gp_sdr_lead_id": "{{gp_sdr_lead_id}}",
  "gp_ativacao_id": "{{gp_ativacao_id}}",
  "gp_comprador_id": "{{gp_comprador_id}}",
  "nova_etapa": "engajado",
  "dados_extras": {
    "aula_numero": 3,
    "assistiu": true,
    "ao_vivo": false,
    "desafio": true
  }
}
```

---

## 13. Spec Técnica — Make.com

### 13.1 Cenários necessários

#### Cenário 1: Nova Compra HT → Inicia SDR

```
Trigger: Webhook (POST de Edge Function hotmart-webhook)
  │
  ├─ Step 1: Supabase — INSERT ht_sdr_leads
  │   {ativacao_id, comprador_id, ht_edition_id, etapa: 'novo_lead', whatsapp_phone}
  │
  ├─ Step 2: Supabase — SELECT ht_editions (pega grupo_link, yt_aulas)
  │
  ├─ Step 3: ManyChat API — Set Custom Fields
  │   POST /subscriber/{phone}/setCustomFields
  │   {gp_comprador_id, gp_ativacao_id, gp_sdr_lead_id, gp_edicao, gp_grupo_link}
  │
  └─ Step 4: (Opcional) Enviar email/SMS com link wa.me para lead iniciar contato
```

#### Cenário 2: Lead Responde → LLM Processa → Responde + Atualiza

**Este é o cenário central.** Toda mensagem do lead passa por aqui.

```
Trigger: Webhook (POST do ManyChat — lead enviou mensagem)
  │
  ├─ Step 1: Supabase — SELECT ht_sdr_leads WHERE manychat_subscriber_id = X
  │   (pega etapa atual, tentativas, ativacao_id, comprador_id)
  │
  ├─ Step 2: Supabase — SELECT ht_sdr_agentes 
  │   WHERE etapa = etapa_atual AND ativo = true
  │   ORDER BY ht_edition_id DESC NULLS LAST, versao DESC LIMIT 1
  │
  ├─ Step 3: Supabase — SELECT ht_sdr_knowledge
  │   WHERE ativo = true (monta knowledge base como contexto)
  │
  ├─ Step 4: Supabase — SELECT ht_sdr_messages 
  │   WHERE sdr_lead_id = X ORDER BY criado_em DESC LIMIT 5
  │   (últimas mensagens para contexto de conversa)
  │
  ├─ Step 5: Montar prompt (prompt_sistema + contexto_lead + knowledge + mensagem_lead)
  │
  ├─ Step 6: OpenAI/Claude API — POST /chat/completions
  │   {model: agente.modelo_llm, temperature: agente.temperatura, max_tokens: agente.max_tokens}
  │   → Recebe JSON: {mensagem, interpretacao, acao, nova_etapa, atualizar_campos}
  │
  ├─ Step 7: ManyChat API — Envia resposta pro lead
  │
  ├─ Step 8: Supabase — INSERT ht_sdr_messages (mensagem do lead + resposta da IA)
  │
  ├─ Step 9: Router (baseado em resposta.acao):
  │   ├─ "avancar_etapa" → UPDATE ht_sdr_leads.etapa + UPDATE ativacoes (campos)
  │   ├─ "recuperacao" → UPDATE tentativas_recuperacao + agenda proxima_tentativa_em
  │   ├─ "escalar_comercial" → UPDATE etapa = 'comercial' + POST Slack
  │   ├─ "encerrar" → UPDATE etapa = 'abandonou', opt_out = true
  │   └─ "manter" → apenas loga, sem mudança de etapa
  │
  └─ Step 10: Supabase — INSERT ht_ativacao_logs
      {tipo_acao: 'sdr_ia_*', ativacao_id, comprador_id, ht_edition_id}
```

#### Cenário 3: Webhook HM → Converte HT + Cria HM

```
Trigger: Webhook (POST de Edge Function hotmart-hm-webhook)
  │
  ├─ Step 1: Supabase — SELECT ht_sdr_leads WHERE comprador_id = X
  │
  ├─ Condition: se encontrou lead SDR ativo no HT
  │
  ├─ Step 2: Kanban HT — UPDATE ht_sdr_leads
  │   {etapa: 'convertido', convertido: true, data_conversao: now()}
  │
  ├─ Step 3: Kanban HM — INSERT hm_sdr_leads
  │   {ativacao_id, comprador_id, turma_id, hm_plano,
  │    etapa: 'novo_aluno_hm', ht_sdr_lead_id: lead_ht.id}
  │
  ├─ Step 4: ManyChat API — Envia mensagem de parabéns (último contato IA)
  │
  └─ Step 5: Slack — "🎉 {nome} converteu HT→HM (plano {plano})"
```

#### Cenário 4: Carrinho Abandonado HM → Dispara SDR

```
Trigger: Webhook (Hotmart ABANDONED_CART ou WAITING_PAYMENT sem APPROVED após 2h)
  │
  ├─ Step 1: Supabase — SELECT ht_sdr_leads WHERE comprador_id = X
  │
  ├─ Condition: se lead existe e etapa IN ('checkout_aberto', 'aulas_completas')
  │
  ├─ Step 2: Supabase — UPDATE ht_sdr_leads {etapa: 'sdr_hm'}
  │
  └─ Step 3: ManyChat API — Trigger flow "06 - SDR Carrinho"
```

#### Cenário 5: Reativação (Agendado)

```
Trigger: Schedule (diário, verifica ht_editions com event_start_date em 3 dias)
  │
  ├─ Step 1: Supabase — SELECT ht_editions WHERE event_start_date = today() + 3 days
  │
  ├─ Condition: se existe edição em 3 dias
  │
  ├─ Step 2: Supabase — SELECT ht_sdr_leads 
  │   WHERE etapa = 'abandonou' AND reativacao_count < 2 AND opt_out = false
  │
  ├─ Step 3: Iterator — para cada lead
  │   ├─ INSERT novo ht_sdr_leads {etapa: 'reativacao', edicao_origem: edição antiga}
  │   └─ ManyChat API — Trigger flow "07 - Reativação"
```

#### Cenário 6: Abertura de Carrinho HM → Notifica Qualificados

```
Trigger: Webhook (POST do sistema quando admin clica "Abrir Carrinho HM")
  OU Schedule (diário, verifica data_abertura_carrinho_hm)
  │
  ├─ Step 1: Supabase — SELECT ht_editions WHERE id = edição AND carrinho_hm_aberto = false
  │
  ├─ Step 2: Supabase — UPDATE ht_editions SET carrinho_hm_aberto = true
  │
  ├─ Step 3: Supabase — SELECT leads qualificados:
  │   ht_sdr_leads l JOIN ativacoes a ON a.id = l.ativacao_id
  │   WHERE l.ht_edition_id = edição
  │     AND l.opt_out = false AND l.convertido = false
  │     AND l.etapa IN ('aulas_acompanhando', 'aulas_completas', 'engajado')
  │     AND (count aulas assistidas em a.ht_aulas) >= 3
  │
  ├─ Step 4: Busca agente slug = 'oferta_hm' em ht_sdr_agentes
  │
  ├─ Step 5: Iterator — para cada lead qualificado:
  │   ├─ Monta prompt com contexto do lead
  │   ├─ Chama LLM → gera mensagem personalizada
  │   ├─ ManyChat API → envia mensagem
  │   ├─ UPDATE ht_sdr_leads SET etapa = 'checkout_aberto'
  │   └─ INSERT ht_sdr_messages
  │
  └─ Step 6: Slack — "🔥 Carrinho HM aberto — {N} leads notificados"
```

### 13.2 Variáveis de ambiente Make.com

| Variável | Valor |
|----------|-------|
| `SUPABASE_URL` | `https://mbvybujpkwuorhtdzcde.supabase.co` |
| `SUPABASE_SERVICE_KEY` | Service role key (do .env servidor) |
| `MANYCHAT_API_TOKEN` | Token API do ManyChat |
| `MAKE_WEBHOOK_SDR_NEW` | URL do webhook cenário 1 |
| `MAKE_WEBHOOK_SDR_UPDATE` | URL do webhook cenário 2 |
| `MAKE_WEBHOOK_SDR_HM` | URL do webhook cenário 3 |
| `MAKE_WEBHOOK_SDR_CART` | URL do webhook cenário 4 |
| `SLACK_WEBHOOK_ATIVACAO` | Já existe |

---

## 14. Spec Técnica — Kanban no Sistema

### 14.0 Reaproveitamento da infraestrutura existente

O sistema já tem padrões maduros que reutilizamos **sem reinventar**:

| Padrão existente | Onde está | Como reutilizar |
|------------------|-----------|----------------|
| Tab system (`data-tab-btn` + `data-tab-pane`) | HT/HM ativação | Adicionar abas "SDR IA" e "Agentes" ao tab system existente |
| Drawer (overlay 900 + panel 901, 520px) | HT/HM drawer.js | Reutilizar estrutura, sub-abas dentro do drawer |
| Store pattern (`HT.store` com listeners) | HT store.js | Estender com `sdrLeads`, `sdrAgentes`, `sdrKnowledge` |
| Normalizer (`row()`, `flow()`) | HT normalizer.js | Adicionar `sdrRow()` para normalizar ht_sdr_leads |
| API pattern (`HT.api`) | HT api.js | Adicionar `getSdrLeads()`, `updateSdrLead()`, `getSdrAgentes()` |
| Real-time subscription | CC app.js | Reutilizar `.channel().on('postgres_changes')` com debounce |
| Toast | HT utils.js | Reutilizar `HT.utils.showToast()` |
| Config constants | HT config.js | Adicionar `SDR_ETAPAS`, `SDR_ETAPAS_HM` |
| Edition selector | HT main.js | Já existe — filtra por edição selecionada |
| Namespace pattern (`window.HT`) | Todos os JS | Adicionar `HT.sdr`, `HT.agentes`, `HT.knowledge` |
| Modal CRUD (Edições HT / Turmas HM) | CC app.js | Reutilizar padrão para modal de agentes e knowledge |
| CSS tokens (`:root` vars) | base.css | Reutilizar — adicionar `--sdr-*` e `--ag-*` |
| RLS com `is_ht_operator()` | Várias tabelas | Reutilizar para novas tabelas SDR |

**O que NÃO reutilizamos:**
- A tabela de compradores (fica como está, Kanban é uma camada acima)
- O drawer existente de compradores (o Kanban terá seu próprio drawer)
- O flow de 5 etapas de ativação (vive em paralelo — SDR atualiza os mesmos campos)

### 14.0.1 Kanban HM — localização

```
/holding-masters/ativacao/index.php

Tabs existentes: [Dashboard]  [Compradores]
Novas:                                       [CRM]
```

O Kanban HM segue o **mesmo padrão** do HT, com namespace `HM.sdr` em vez de `HT.sdr`.
CSS e lógica de kanban são compartilhados via arquivo `sdr-shared.js` / `sdr-shared.css`.

### 14.1 Localização — Kanban HT

```
/holding-total/ativacao/index.php

Tabs existentes: [Dashboard]  [Compradores]
Novas:                                       [SDR IA]  [Agentes]
                                    ↑ NOVO
```

### 14.2 Estrutura da aba

```html
<div id="sdr-tab" class="tab-content" style="display:none">
  <!-- Filtros -->
  <div class="sdr-filters">
    <select id="sdr-edition-filter"><!-- edições --></select>
    <input id="sdr-search" type="text" placeholder="Buscar lead...">
    <div class="sdr-stats">
      <span class="stat">Total: <b>127</b></span>
      <span class="stat">Engajados: <b>89</b></span>
      <span class="stat">Convertidos: <b>23</b></span>
      <span class="stat">Comercial: <b>8</b></span>
    </div>
  </div>

  <!-- Kanban Board -->
  <div class="sdr-kanban">
    <div class="kanban-col" data-etapa="novo_lead">
      <div class="kanban-col-header">
        <span>Novo Lead</span>
        <span class="count-badge">12</span>
      </div>
      <div class="kanban-col-body">
        <!-- Cards -->
        <div class="kanban-card" data-id="uuid">
          <div class="card-name">João Silva</div>
          <div class="card-phone">📱 (11) 99999-1234</div>
          <div class="card-meta">
            <span class="card-last-contact">Último contato: 2h atrás</span>
          </div>
          <div class="card-flags">
            <span class="flag flag-engajado">Engajado</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Repetir para cada etapa -->
  </div>
</div>
```

### 14.3 Colunas do Kanban (visíveis)

| Coluna | Cor | Etapas incluídas |
|--------|-----|-----------------|
| Novo Lead | Cinza | `novo_lead` |
| Grupo Enviado | Azul | `grupo_enviado` |
| Engajado | Verde claro | `engajado` |
| Aulas | Amarelo | `aulas_acompanhando`, `aulas_completas` |
| Checkout | Laranja | `checkout_aberto` |
| SDR HM | Vermelho | `sdr_hm` |
| Convertido | Verde | `convertido` |
| Comercial | Roxo | `comercial` |
| Abandonou | Cinza escuro | `abandonou`, `reativacao` |

### 14.4 Card — Informações

| Campo | Fonte |
|-------|-------|
| Nome | `compradores.nome` |
| Telefone | `compradores.telefone` (formatado BR) |
| Etapa atual | `ht_sdr_leads.etapa` |
| Último contato IA | `ht_sdr_leads.ultimo_contato_ia` (relative time) |
| Última resposta lead | `ht_sdr_leads.ultima_resposta_lead` (relative time) |
| Tentativas recuperação | `ht_sdr_leads.tentativas_recuperacao` / `max_tentativas` |
| Flag: engajado | `etapa IN ('engajado', 'aulas_acompanhando', 'aulas_completas')` |
| Flag: em recuperação | `tentativas_recuperacao > 0` |
| Flag: opt-out | `opt_out = true` |
| Flag: convertido | `convertido = true` |
| Aulas assistidas | `count de ativacoes.ht_aulas[*].assistiu = true` |

### 14.5 Ações do card (ao clicar)

- Abre drawer lateral (reutiliza padrão existente)
- Mostra timeline completa de mensagens (`ht_sdr_messages`)
- Botão: "Mover para Comercial"
- Botão: "Marcar como Abandonou"
- Botão: "Adicionar Observação"
- Botão: "Ver no Compradores" (link para aba compradores com filtro)

### 14.6 Arquivos JS novos

| Arquivo | Responsabilidade |
|---------|-----------------|
| `js/sdr.js` | Kanban render, drag (visual only), filtros, real-time subscribe |
| `js/sdr-drawer.js` | Drawer do card SDR com timeline de mensagens |

### 14.7 CSS

Arquivo `css/sdr.css` com prefixo `--sdr-` para tokens.

### 14.8 Real-time

```javascript
// Subscribe a mudanças em ht_sdr_leads da edição selecionada
db.channel('sdr-leads')
  .on('postgres_changes', {
    event: '*',
    schema: 'public',
    table: 'ht_sdr_leads',
    filter: `ht_edition_id=eq.${edicaoSel}`
  }, handleSdrChange)
  .subscribe();
```

---

## 15. Spec Técnica — Painel de Agentes no Sistema

### 15.1 Localização

Aba "Agentes" na página de ativação HT. Acesso: **somente admin**.

```
/holding-total/ativacao/index.php

Tabs: [Dashboard]  [Compradores]  [SDR IA]  [Agentes]
                                               ↑ admin only
```

### 15.2 Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ Agentes SDR                                        [+ Novo Agente] │
├─────────────────────────────────────────────────────────────────┤
│ Filtros: [Etapa ▾] [Tom ▾] [Status: Ativo/Inativo]             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ┌─ Agente Card ──────────────────────────────────────────────┐  │
│ │ 🟢 Onboarding HT23              v1    amigável   gpt-4o-mini │
│ │ Etapa: novo_lead → grupo_enviado                            │  │
│ │ Tentativas: 3 | Intervalo: 24h | Temp: 0.7                 │  │
│ │                                          [Editar] [Testar]  │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│ ┌─ Agente Card ──────────────────────────────────────────────┐  │
│ │ 🟢 Recuperação Leve              v2    amigável   claude     │
│ │ Etapa: * (qualquer, tentativa 1)                            │  │
│ │ Tentativas: 1 | Intervalo: 24h | Temp: 0.5                 │  │
│ │                                          [Editar] [Testar]  │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 15.3 Modal "Editar Agente"

Ao clicar em [Editar], abre drawer lateral com:

| Seção | Campos |
|-------|--------|
| **Identificação** | Nome, Slug (readonly se já usado), Etapa (select), Edição (select ou "Global") |
| **Modelo LLM** | Select: gpt-4o-mini, gpt-4o, claude-sonnet-4-6 |
| **Comportamento** | Tom (select), Temperatura (slider 0.0-1.0), Max tokens (input), Max tentativas (input), Intervalo horas (input) |
| **Prompt Sistema** | Textarea grande com syntax highlighting básico, placeholders destacados ({nome}, {grupo_link}, etc.) |
| **Prompt Mensagem** | Textarea para template de mensagem (opcional) |
| **Regras de Transição** | Editor JSON visual — cada regra como card removível: condição → ação → nova_etapa |
| **Status** | Toggle ativo/inativo + versão (auto-increment ao salvar) |

### 15.4 Botão "Testar"

Abre modal de teste onde o admin pode:

1. Simular uma mensagem de lead (input de texto)
2. Selecionar um lead real do `ht_sdr_leads` como contexto (ou usar dados fictícios)
3. Clicar "Enviar para LLM"
4. Ver a resposta da IA em tempo real (mensagem + interpretação + ação sugerida)
5. **Não afeta dados reais** — apenas chama a API com o prompt e mostra o resultado

```
┌─ Testar Agente: Onboarding HT23 ────────────────────────┐
│                                                           │
│ Contexto:  [Lead real ▾] João Silva - HT23               │
│                                                           │
│ Mensagem do lead:                                         │
│ ┌───────────────────────────────────────────────────────┐ │
│ │ Oi, acabei de comprar o curso                         │ │
│ └───────────────────────────────────────────────────────┘ │
│                                          [Enviar para LLM] │
│                                                           │
│ ── Resposta da IA ──────────────────────────────────────  │
│ Mensagem: "Oi, João! 🎉 Bem-vindo ao Holding Total..."  │
│ Interpretação: positivo                                   │
│ Ação: avancar_etapa → grupo_enviado                      │
│ Campos: { entrou_grupo_whatsapp: false }                 │
│ Tokens usados: 187 | Custo: $0.003                       │
└───────────────────────────────────────────────────────────┘
```

### 15.5 Aba "Knowledge Base"

Sub-aba dentro de Agentes para gerenciar a base de conhecimento.

```
┌─────────────────────────────────────────────────────────────────┐
│ [Agentes]  [Knowledge Base]                                      │
├─────────────────────────────────────────────────────────────────┤
│ Filtros: [Categoria ▾] [Tags] [Status]          [+ Novo Item]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ┌─ Knowledge Card ───────────────────────────────────────────┐  │
│ │ O que é o Holding Masters?                produto_hm  🟢   │  │
│ │ Tags: hm, programa, mentoria                               │  │
│ │ "O Holding Masters é o programa completo com mentoria..."  │  │
│ │                                          [Editar] [Excluir] │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│ ┌─ Knowledge Card ───────────────────────────────────────────┐  │
│ │ Planos e preços HM                        pagamento  🟢    │  │
│ │ Tags: preco, 5k, 12k, 24k, plano                          │  │
│ │ "O HM tem 3 planos: Starter (5k), Pro (12k)..."           │  │
│ │                                          [Editar] [Excluir] │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 15.6 Categorias do Knowledge Base

| Categoria | Uso |
|-----------|-----|
| `produto_ht` | Informações sobre o Holding Total |
| `produto_hm` | Informações sobre o Holding Masters |
| `pagamento` | Planos, preços, formas de pagamento, parcelamento |
| `suporte` | Problemas técnicos, acesso, plataforma |
| `objecoes` | Respostas para objeções comuns ("é caro", "não tenho tempo") |
| `depoimentos` | Cases de sucesso para a IA usar como argumento |

### 15.7 Arquivos JS novos

| Arquivo | Responsabilidade |
|---------|-----------------|
| `js/agentes.js` | CRUD de agentes, render da lista, modal editar, teste LLM |
| `js/knowledge.js` | CRUD de knowledge base, filtros, categorias |

### 15.8 CSS

Reutiliza `css/components.css` existente + classes específicas com prefixo `--ag-`.

---

## 16. Cronograma de Implementação

### Fase 1 — Fundação: Banco + Kanban HT + Kanban HM (1 semana)

| Task | Descrição |
|------|-----------|
| 1.1 | Criar tabelas `ht_sdr_leads`, `ht_sdr_messages`, `ht_sdr_agentes`, `ht_sdr_knowledge`, `hm_sdr_leads` no Supabase (prod) |
| 1.2 | Adicionar campos `data_abertura_carrinho_hm` e `carrinho_hm_aberto` em `ht_editions` |
| 1.3 | Criar RLS policies para todas as tabelas |
| 1.4 | Popular `ht_sdr_agentes` com os 11 agentes pré-configurados |
| 1.5 | Popular `ht_sdr_knowledge` com FAQ básico (produto HT, produto HM, pagamento, objeções) |
| 1.6 | Criar aba "SDR IA" no `/holding-total/ativacao/` — Kanban HT com colunas, cards, filtros, real-time |
| 1.7 | Criar aba "CRM" no `/holding-masters/ativacao/` — Kanban HM com colunas manuais, responsável, obs |
| 1.8 | Criar `sdr-shared.js` e `sdr-shared.css` — componentes de Kanban compartilhados entre HT e HM |
| 1.9 | Implementar drawer do Kanban (timeline de mensagens no HT, log de contatos no HM) |
| 1.10 | Botão "Abrir Carrinho HM" na aba SDR IA com confirmação |

### Fase 2 — Painel de Agentes + Knowledge Base (1 semana)

| Task | Descrição |
|------|-----------|
| 2.1 | Criar aba "Agentes" na ativação HT (admin only) |
| 2.2 | Implementar `agentes.js` — CRUD de agentes, lista, drawer de edição |
| 2.3 | Implementar `knowledge.js` — CRUD de knowledge base |
| 2.4 | Implementar modal "Testar Agente" com chamada ao LLM |
| 2.5 | Criar endpoint PHP ou Edge Function para proxy de chamada ao LLM (evitar expor API key) |

### Fase 3 — ManyChat + Make.com (1 semana)

| Task | Descrição |
|------|-----------|
| 3.1 | Configurar WhatsApp Business no ManyChat |
| 3.2 | Criar Custom Fields no ManyChat |
| 3.3 | Criar flows simplificados (Default Reply → webhook, Send Message, Opt-Out) |
| 3.4 | Criar cenário Make.com 1: Nova Compra → SDR |
| 3.5 | Criar cenário Make.com 2: Lead Responde → LLM → Responde + Atualiza (cenário central) |
| 3.6 | Criar cenário Make.com 3: Webhook HM → Converte HT + Cria HM |
| 3.7 | Criar cenário Make.com 4: Carrinho Abandonado |
| 3.8 | Criar cenário Make.com 5: Reativação agendada |
| 3.9 | Criar cenário Make.com 6: Abertura de Carrinho HM → notifica qualificados |
| 3.10 | Estender Edge Functions (HT e HM) para POST Make.com |

### Fase 4 — Testes e Go-Live (1 semana)

| Task | Descrição |
|------|-----------|
| 4.1 | Testar fluxo completo HT com lead fictício (número de teste) |
| 4.2 | Testar conversão HT → HM (lead aparece no Kanban HM automaticamente) |
| 4.3 | Testar abertura de carrinho HM (botão + fallback automático) |
| 4.4 | Testar critério de qualificação (3+ aulas = recebe notificação) |
| 4.5 | Ajustar prompts dos agentes via painel com base nas respostas |
| 4.6 | Testar recuperação, escalada, opt-out e reativação entre edições |
| 4.7 | Testar Kanban HM — comercial movendo etapas manualmente |
| 4.8 | Deploy em homologação |
| 4.9 | Validar com leads reais do HT23/HT25 |

---

## 17. Riscos e Mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| ManyChat bloqueia conta | Alto | Modelo inbound (lead inicia) + respeitar opt-out + volume gradual |
| IA envia informação errada | Médio | Knowledge base restritivo + prompts com regras rígidas + testar antes de ativar |
| Lead se irrita com bot | Médio | Máx 3 tentativas + opt-out imediato + tom configurável por agente |
| Make.com fora do ar | Médio | Retry automático (nativo) + logs no Supabase para reprocessar |
| Custo de API LLM alto | Médio | gpt-4o-mini como default (barato), monitorar tokens via ht_sdr_messages |
| Prompt mal configurado pelo admin | Médio | Modal de teste obrigatório antes de ativar + versionamento |
| WhatsApp Business API muda regras | Médio | ManyChat é só carteiro — trocar canal não afeta IA/prompts/banco |
| Dados dessincronizados | Médio | Webhook bidirecional + real-time no kanban + reconciliação manual |
| LLM retorna JSON inválido | Baixo | Parser com fallback + retry 1x + log de erro + escala pro comercial |

---

## Apêndice A — Diagrama de Estados

```
                    ┌──────────────┐
                    │  novo_lead   │◀─────────────────────────────┐
                    └──────┬───────┘                              │
                           │ lead inicia conversa                 │
                           ▼                                      │
                    ┌──────────────┐                              │
                    │grupo_enviado │                              │
                    └──────┬───────┘                              │
                           │ lead confirma                        │
                           ▼                                      │
                    ┌──────────────┐                              │
                    │  engajado    │                              │
                    └──────┬───────┘                              │
                           │ assistiu 1+ aula                     │
                           ▼                                      │
                    ┌────────────────────┐                        │
                    │aulas_acompanhando  │                        │
                    └──────┬─────────────┘                        │
                           │ todas aulas feitas                   │
                           ▼                                      │
                    ┌──────────────┐                              │
                    │aulas_completas│                             │
                    └──────┬───────┘                              │
                           │ oferta HM aceita                     │
                           ▼                                      │
                    ┌────────────────┐                            │
                    │checkout_aberto │                            │
                    └──────┬─────────┘                            │
                           │ carrinho abandonado                  │
                           ▼                                      │
                    ┌──────────────┐                              │
                    │   sdr_hm     │                              │
                    └──────┬───────┘                              │
                           │                                      │
              ┌────────────┼────────────┐                         │
              ▼            ▼            ▼                         │
       ┌───────────┐┌───────────┐┌───────────┐                   │
       │convertido ││ comercial ││ abandonou  │───reativação────▶│
       └───────────┘└───────────┘└───────────┘                   │
                                                                  
  *** De QUALQUER etapa, se webhook HM APPROVED → convertido ***
  *** De QUALQUER etapa, operador pode mover → comercial ***
  *** Recuperação (3 tentativas) acontece DENTRO de cada etapa ***
```

---

## Apêndice B — Campos `ht_editions.yt_aulas` (jsonb)

Estrutura esperada para o SDR alimentar links de aulas no ManyChat:

```json
{
  "1": { "titulo": "Aula 1 - Fundamentos", "url": "https://youtube.com/...", "data_liberacao": "2026-04-13" },
  "2": { "titulo": "Aula 2 - Estratégia", "url": "https://youtube.com/...", "data_liberacao": "2026-04-14" },
  "3": { "titulo": "Aula 3 - Execução", "url": "https://youtube.com/...", "data_liberacao": "2026-04-15" },
  "4": { "titulo": "Aula 4 - Escala", "url": "https://youtube.com/...", "data_liberacao": "2026-04-16" },
  "5": { "titulo": "Aula 5 - Mentalidade", "url": "https://youtube.com/...", "data_liberacao": "2026-04-17" },
  "6": { "titulo": "Aula 6 - Encerramento + Oferta HM", "url": "https://youtube.com/...", "data_liberacao": "2026-04-18" }
}
```

O Make.com lê este campo para saber quando disparar o flow "02 - Aula Disponível" no ManyChat.

---

## Apêndice C — Glossário

| Termo | Definição |
|-------|-----------|
| **HT** | Holding Total — curso de entrada (menor valor) |
| **HM** | Holding Masters — programa completo (high-ticket: 5k/12k/24k) |
| **SDR** | Sales Development Representative — quem qualifica e avança o lead |
| **Edição** | Ciclo de vendas do HT (ex: HT23, HT24, HT25) |
| **Inbound** | Lead inicia a conversa (vs. outbound onde o bot inicia) |
| **Opt-out** | Lead pede para não receber mais mensagens |
| **Knowledge Base** | Base de conhecimento que a IA consulta para responder dúvidas |
| **External Trigger** | Forma de iniciar um flow no ManyChat via API externa |
| **Custom Field** | Campo personalizado no ManyChat vinculado ao subscriber |
