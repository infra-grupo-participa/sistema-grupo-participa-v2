# Spec — Dashboard / Indicadores (Centro de Controle)

> Fluxo spec-driven (aiox). Fase 1 = esta spec. Status: **aguardando aprovação** antes da execução.

## 1. Objetivo

Aba **Dashboard** dentro do Centro de Controle (`/sistema/alunos`) que replica em código os 2 painéis do Time Holding Brasil (visão **Alunos** e visão **Sócios**), porém mais rápido e customizável: KPIs com submétricas, funil por nível, distribuição por turma, ingresso no tempo, proporção por instrução/nível, com filtros e visões rápidas.

Tudo **client-side** sobre os ~1967 registros já carregados (`fn_aluno_360_safe` → `state.alunos`). Sem libs externas (padrão inline do projeto): gráficos em **SVG/CSS puro**.

## 2. Decisão-chave — dimensão de classificação

O BI atual classifica por **"Instrução" (tier de associação da planilha**: THB / Aurum / Platina / Diamante / DV). Esse tier **não é** o `nivel_resultado` (nível de *resultado/faturamento*) e **não existe como coluna limpa** no acervo. Por isso os números divergem:

| Métrica | BI atual | Acervo (dado limpo) |
|---|---|---|
| Diamante Vermelho | 16 | `nivel_resultado='diamante_vermelho'` = **1** |
| Holding Masters | 958 | `tem_hm` = 1600 |
| Alunos ativos | 1.148 | `status in (renovado,vigente)` = 1492 |
| Aurum | 123 | `turma_aurum_id` = 188 |

→ **Opção A (recomendada, code-native):** dashboard sobre o dado limpo do acervo. Dimensão principal = `nivel_resultado` (8 níveis) + **Aurum** (`turma_aurum_id`) e **Sócio** (`eh_socio`) como segmentos. Números reais do acervo; o dashboard vira a nova fonte de verdade.

→ **Opção B (paridade BI):** adicionar coluna `instrucao_tier` (THB/Aurum/Platina/Diamante/DV) derivada da planilha + alinhar a definição de "ativo", pra bater com o painel antigo. Requer passo de dados antes da UI.

## 3. Fontes & derivações (client-side, sobre `state.alunos`)

Campos disponíveis: `nivel_resultado`, `turma_codigo`, `turma_aurum_id`, `eh_socio`, `status_acesso`, `estado`, `cidade`, `profissao`, `data_compra_importada`, `tem_ht`, `tem_hm`, `hm_plano`, `cs_estagio`, `sip_registrado`.

Definições propostas (Opção A):
- **Ativo** = `status_acesso ∈ {renovado, vigente}` *(decisão a confirmar)*
- **Sócio** = `eh_socio = true`
- **Tier/Nível** = `nivel_resultado` (iniciante…diamante_vermelho); "Sem nível" agrupado à parte
- **Aurum** = `turma_aurum_id != null`
- **Período de entrada** = `data_compra_importada` (fallback `data_compra_ht/hm`)
- **Instrução** (filtro) = mapeado para Tier/Nível (Opção A) ou `instrucao_tier` (Opção B)

## 4. Toggle de visão

`[ Alunos ]  [ Sócios ]` — Sócios filtra `eh_socio=true`; Alunos = todos. Mesma estrutura de KPIs/gráficos nas duas.

## 5. KPIs (cards com submétricas)

Cada card: valor principal + 2-3 submétricas (Δ, % do total, ativos).
- **Total** (alunos ou sócios) — sub: ativos, % ativos
- **Aurum** — sub: % do total, ativos
- **Platina / Diamante / Diamante Vermelho** — sub: % do total
- **Holding Masters / Holding Total** — sub: ativados (ativacao_status)

## 6. Visualizações

1. **Funil por nível** (Ouro→DV ou tiers) — barras CSS empilhadas (reaproveita estética do mock).
2. **Distribuição por turma** — donut SVG (top N + "outros"), legenda lateral.
3. **Ingresso no tempo** — série (barras/linha SVG) por mês de `data_compra_importada`.
4. **Proporção por instrução/nível** — barras horizontais.
5. **Tabela turma × nível** — matriz com heat (contagens por turma e nível).

## 7. Filtros

`Instrução/Nível`, `Turma`, `Estado`, `Período (entrada)`. Reaproveitam o `advNorm` (acento/caixa). Aplicam a todos os cards/gráficos simultaneamente.

## 8. Visões rápidas

Botões salváveis (localStorage, reusa padrão `cc_adv_views`): ex. "Sócios ativos · Platina+", "Ingressos 2026". Um clique reconfigura toggle+filtros.

## 9. Layout

Grid responsivo: linha de KPIs (5 cards) → funil + ingresso + donut → tabela. Tokens `--cc-*` existentes. Nova aba `Dashboard` ao lado de Alunos/Turmas/Edições.

## 10. Arquitetura técnica

- Nova tab `cc-panel-dashboard` em `index.php` + botão na `.cc-tabs`.
- `js/app.js`: módulo `dashboard` — `computeMetrics(alunos, {view, filtros})` puro; render de KPIs + gráficos SVG/CSS. Recalcula on-filter (memoizado).
- Sem dependência de rede: usa `state.alunos` já carregado. Lazy: só renderiza quando a aba abre.
- Gráficos: helpers `svgDonut()`, `svgBars()`, `cssFunnel()` — sem libs.

## 11. Performance

1967 registros → agregações O(n) por filtro, instantâneas. Recompute só no change de filtro/toggle (debounce). Render incremental.

## 12. Fora de escopo (v1)

Export PDF dos gráficos; drill-down clicável célula→lista (pode entrar v2); comparação temporal período-a-período.
