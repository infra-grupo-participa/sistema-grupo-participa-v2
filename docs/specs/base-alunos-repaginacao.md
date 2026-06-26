# Spec — Repaginação Executiva da Base de Alunos

> Fluxo spec-driven. Status: **APROVADA (2026-06-24)** — em execução.
> Criado em 2026-06-24 · Módulo `/sistema/alunos`
>
> Decisões fechadas: (1) Turma×Nível **removida** do dashboard; (2) KPI-herói financeiro = **Saldo a receber (R$)**; (3) sub-abas = **Resumo · Financeiro & Renovações · Engajamento**.

## 1. Problema (estado atual)

A Base de Alunos cresceu organicamente. O **Dashboard** tem hoje **4 sub-abas** (Visão geral · Pagamentos · Renovações · Curso) somando **~20 cards**. Sintomas:

- **Métrica repetida** em vários lugares: "situação de acesso" aparece em 3 sub-abas.
- **Assuntos irmãos separados**: Pagamentos e Renovações são o mesmo tema (dinheiro + acesso no tempo) em duas abas.
- **Gráficos densos / pouco executivos**: matriz Turma×Nível, donut por turma no topo.
- **Falta uma tela que conte a história do negócio num olhar** — hoje precisa passear por 4 abas pra ter o panorama.

## 2. Objetivo

Repaginar para algo **executivo, simples e fácil de entender**:
1. Uma tela-resumo que responde "como está o negócio?" em um olhar.
2. Reunir o que é do mesmo assunto.
3. Menos cards, mais hierarquia e clareza.

## 3. Estrutura proposta — Dashboard de **4 → 3 sub-abas**

### 3.1 `Resumo` (executivo) — nova landing (substitui "Visão geral")
Uma tela que conta tudo:
- **Faixa de 5 KPIs-herói:** Total de alunos · Ativos (em dia) · Vencidos · Vencem em 90 dias · **Saldo a receber (R$)**.
- **Composição por Espaço** — Holding Masters / Aurum / Mastermind Diamante, com titular vs sócio.
- **Situação de acesso** (donut: em dia / a vencer / vencido / acompanha titular) — clicável → lista.
- **Novos alunos por mês** (crescimento no tempo).
- **Renovações — próximos 3 meses** (mini-timeline; "ver tudo" → Financeiro).

### 3.2 `Financeiro & Renovações` — funde Pagamentos + Renovações
Tudo de dinheiro/acesso ao longo do tempo num só lugar:
- **KPIs:** Saldo a receber · Inadimplentes · Vencidos · Vencem 60d / 90d · Assinaturas em risco.
- **Vencimentos por mês** (timeline segmentada — âncora da aba).
- **Saldo devedor por espaço**.
- **Funil de renovação por espaço** (Ativos / A vencer / Vencidos).
- **Maiores saldos devedores** (lista clicável → card, para agir).
- **Saúde de assinaturas** (ativa / histórico insuficiente / possível inadimplência).

### 3.3 `Engajamento` — mantém o Curso (renomeado)
Consumo do curso (presença, conclusão, churn, funil). Sub-aba "Curso" → **"Engajamento"** (mais executivo). Sem mudança estrutural.

### O que sai / é demovido
- Matriz **Turma × Nível** → fora do executivo (turma é detalhe operacional; vive na aba Turmas).
- **Distribuição por nível** (hbars) → absorvida no card "Composição" do Resumo.
- **Donut por turma** no topo → removido.
- **Situação de acesso** deixa de repetir em 3 abas → 1× no Resumo + detalhe no Financeiro.

## 4. Princípios executivos (regras do redesign)

- **Máx. 5 KPIs por tela.** Número grande + 1 submétrica.
- **Cores semânticas fixas:** verde = em dia · amarelo = a vencer · vermelho = vencido/dívida · cinza = acompanha.
- **Tudo clicável leva à lista** (drill-down `ccDrill` já existe).
- **R$ sempre visível** onde há dinheiro (saldo a receber é KPI-herói).
- Hierarquia por tela: KPIs → 1 gráfico-âncora → detalhes.

## 5. Layout

Grid de 4 colunas (já padronizado). KPIs em faixa horizontal (grid responsivo já feito). Reusa tokens `--cc-*` e componentes (`cc-stat`, `cc-donut`, `cc-hbars`, `cc-dash-table`, timeline de vencimentos).

## 6. Arquitetura (zero dado novo, zero migração)

Tudo client-side sobre `state.alunos` (a RPC `fn_aluno_360_safe` já entrega: `espaco_instrucao`, `nivel_resultado`, `eh_socio`, `situacao_acesso`, `saldo_devedor`, `data_expiracao`, `status_pagamento`, `status_acesso_central`, `data_compra_importada`).

- `index.php`: reorganizar sub-abas (geral→`resumo`, fundir pgto+renov→`financeiro`, curso→`engajamento`) e containers dos cards.
- `app.js`:
  - **novo** `renderDashResumo()` — compõe os 5 KPIs-herói + 4 cards.
  - **fundir** `renderDashPagamentos` + `renderDashRenovacoes` → `renderDashFinanceiro()`.
  - **manter** `renderDashCurso()` (rótulo Engajamento).
  - `applyDashTab()` ajustado para `resumo | financeiro | engajamento`.
- Reaproveita 100% dos helpers de gráfico existentes. Sem libs.

## 7. Fora de escopo (v1)

Export PDF; comparação período-a-período; metas/targets de renovação; preencher telefones via aba Assinaturas (tarefa de dados separada); qualquer dado novo.

## 8. Decisões abertas (pré-aprovação)

1. **Matriz Turma×Nível**: remover de vez do dashboard, ou guardar num card "detalhe" recolhível?
2. **"Saldo a receber" como KPI-herói** no Resumo — confirma que é a métrica financeira nº1 pro nível executivo?
3. **Nomes das sub-abas**: `Resumo` · `Financeiro & Renovações` · `Engajamento` — ok, ou prefere outros rótulos?
