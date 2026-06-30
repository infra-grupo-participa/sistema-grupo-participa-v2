# Identidade Visual v2 Specification

> **Status:** Specify ✅ | Design ✅ | Tasks ✅ | Execute: pending
> **Created:** 2026-06-30
> **Owner:** Marcio (advmais)
> **Fonte:** `sistema-grupo-participa/app` (legado HTML/PHP+CSS) → `web/` (Next 16 + Tailwind v4)
> **Depende de:** nenhuma. Habilita: paridade visual de todas as features da v2.

## Problem Statement

O sistema legado tem uma identidade visual madura e validada por uso ("painel operacional âmbar
sobre quase-preto", denso e preciso), espalhada por `global.css` + ~17 páginas com CSS inline
duplicado (`ht21.css`, `projeto-central.css`, `relatorios/placas`, fluxos públicos). A v2 já portou
**parte** dos tokens e alguns componentes, mas: (1) o catálogo de componentes está incompleto, (2)
há **desvios** entre legado e v2 sem decisão registrada, (3) padrões ricos (timeline, calendar
picker, filtros, kanban, funil, formulário multi-step) não existem como componentes. Sem um design
system completo e fiel, cada tela nova recria estilo à mão — repetindo a dívida do legado (ARQ-01).

## Goals

- [ ] Tokens da identidade legada 100% portados e mapeados ao Tailwind v4 (`@theme`), tema claro+escuro.
- [ ] Catálogo de componentes React cobre todos os padrões compartilhados do legado (ver Design).
- [ ] Shell (Header/Sidebar/Tabs) com **paridade visual** e comportamento (colapso persistido, item ativo).
- [ ] Desvios legado↔v2 reconciliados e documentados no `system.md`.
- [ ] Zero hex hardcoded fora de `globals.css`; zero CSS duplicado entre telas.
- [ ] Fluxos públicos e telas internas migráveis usando só o catálogo (sem CSS inline novo).

## Out of Scope

| Item | Motivo |
| ---- | ------ |
| Padrões exclusivos de páginas legadas mortas (ht21 ads/activation 9-col) | Telas não previstas na v2; capturar só se a feature voltar. |
| Troca de Inter por outro tipo / ícones SVG no lugar de emoji | Mudaria a identidade; só sob pedido explícito. |
| Migração funcional (lógica/dados) das telas | Esta spec é **visual/UI**; lógica vive nos módulos da v2. |
| Redesign / novas telas | Objetivo é **manter** a identidade, não redesenhar. |
| Storybook / ferramenta de catálogo externa | Avaliar depois; catálogo vive no código + `system.md`. |

---

## User Stories

### P1: Tokens e fundação Tailwind ⭐ MVP

**User Story:** Como dev da v2, quero todos os tokens da identidade legada disponíveis como utilities
Tailwind e CSS vars temáticas, para construir qualquer tela fiel à marca sem hex solto.

**Why P1:** É a base de tudo — sem tokens completos, todo componente improvisa cor/raio/espaço.

**Acceptance Criteria:**

1. WHEN um componente precisa de cor/superfície/borda/raio/sombra/espaçamento THEN o sistema SHALL
   oferecer um token correspondente em `globals.css` espelhando `app/assets/css/global.css` do legado.
2. WHEN os tokens semânticos, de superfície, fg e acento existem THEN o sistema SHALL expô-los via
   `@theme inline` como utilities (`bg-surface-2`, `text-fg-2`, `border-border-gp`, `text-accent`…).
3. WHEN o usuário alterna o tema THEN o sistema SHALL trocar os valores via `html[data-theme]` sem
   recompilar classes, incluindo os refinamentos do tema claro (sombras pontuais, bordas mais fortes).
4. WHERE houver token, o componente SHALL usar a utility; `var(--x)` arbitrário SHALL ser exceção
   justificada e hex hardcoded SHALL ser proibido fora de `globals.css`.

**Independent Test:** Renderizar uma página com `bg-surface-0`/`text-fg`/`border-border-gp`,
alternar `data-theme="light"` e confirmar inversão correta sem rebuild.

---

### P1: Catálogo de componentes compartilhados ⭐ MVP

**User Story:** Como dev, quero os padrões visuais recorrentes do legado como componentes React
tipados, para montar telas por composição em vez de CSS inline.

**Why P1:** Elimina a duplicação (ARQ-01) e garante consistência da identidade.

**Acceptance Criteria:**

1. WHEN preciso de um padrão compartilhado (Button, Badge/NivelBadge, Card/StatCard, SectionTitle,
   EmptyState, Drawer, DataTable, Tabs, Modal, Toolbar/SearchInput, FilterSelect, Toggle,
   ProgressBar, Spinner, Timeline) THEN o sistema SHALL prover um componente em `shared/ui` cobrindo-o.
2. WHEN um componente tem variantes no legado (ex.: stat-card orange/green/yellow/gray; botão
   primary/ghost/danger/success/subtle; badge por tom semântico) THEN o componente SHALL expô-las por prop tipada.
3. WHEN um componente já existe na v2 mas diverge do legado (ver `context.md` D5) THEN ele SHALL ser
   reconciliado conforme decisão e a decisão SHALL constar no `system.md`.
4. WHEN um padrão é exclusivo de uma feature THEN ele SHALL viver no módulo, não em `shared/ui`.

**Independent Test:** Construir uma tela de exemplo usando só imports de `shared/ui` (KPIs + tabela +
badges + toolbar + drawer) sem nenhuma regra CSS local.

---

### P1: Shell com paridade visual e de comportamento ⭐ MVP

**User Story:** Como usuário, quero header e sidebar idênticos em identidade ao legado, com grupos
colapsáveis e item ativo destacado, para não perceber regressão visual na migração.

**Acceptance Criteria:**

1. WHEN a sidebar renderiza THEN ela SHALL ter marca (GP + cargo), grupos colapsáveis com estado
   persistido em `localStorage`, divisores e item ativo com assinatura de acento.
2. WHEN um item está ativo THEN o sistema SHALL aplicar a assinatura decidida (barra de acento à
   esquerda + tom âmbar), consistente em itens e subitens.
3. WHEN o header renderiza THEN ele SHALL ter logo, badge de cargo, nome/avatar, toggle de tema e sair.
4. WHEN a viewport ≤ 920px THEN o shell SHALL colapsar conforme os breakpoints do legado.

**Independent Test:** Comparar lado a lado shell v2 × screenshot do legado nos dois temas e em mobile.

---

### P2: Reconciliação e documentação do design system

**User Story:** Como mantenedor, quero os desvios legado↔v2 resolvidos e o `system.md` atualizado,
para que "manter a identidade" seja inequívoco.

**Acceptance Criteria:**

1. WHEN um desvio do `context.md` D5 é resolvido THEN o `system.md` SHALL registrar a decisão final.
2. WHEN o catálogo muda THEN o `system.md` SHALL listar o inventário atual de componentes e tokens.
3. WHEN um novo componente é criado THEN ele SHALL passar nos 4 checks do `system.md` (swap/squint/
   signature/token).

---

### P2: Paridade das telas já existentes na v2

**User Story:** Como usuário, quero que as telas já portadas (dashboard, Alunos, Placas, Depoimentos)
usem o catálogo final, para consistência total.

**Acceptance Criteria:**

1. WHEN uma tela existente é revisada THEN ela SHALL substituir CSS/estilo ad-hoc por componentes do catálogo.
2. WHEN a revisão termina THEN a tela SHALL não conter hex hardcoded nem classes utilitárias de cor crua.

---

### P3: Migração visual das telas ricas restantes

**User Story:** Como usuário, quero os fluxos públicos e telas internas ricas com a identidade v2.

**Why P3:** Alto valor mas depende de catálogo + componentes específicos (timeline, multi-step, calendar).

**Acceptance Criteria:**

1. WHEN `relatorios/placas` é migrado THEN ele SHALL reproduzir KPIs, filtros, tabela, timeline de
   auditoria e edit panels com componentes do catálogo.
2. WHEN `solicitar-placa` é migrado THEN ele SHALL reproduzir o multi-step (progress, transições,
   upload, CEP) com a identidade v2.
3. WHEN `usuarios` e `admin/depoimentos` são migrados THEN eles SHALL usar layout por área, cards,
   tabs e edit panels do catálogo.
