# Context — Identidade Visual v2 (Decisões — Auto Mode)

Capturado em: 2026-06-30
Modo: Auto (decisões registradas para o usuário revisar antes do Design)

> Objetivo: portar **toda a identidade visual** do sistema legado (`sistema-grupo-participa/app`,
> HTML/PHP + CSS) para a v2 (`web/`, Next.js 16 + React 19 + Tailwind v4), **mantendo a originalidade
> da UX/visual** e melhorando a arquitetura (componentes tipados, tokens únicos, zero duplicação).
> Cada decisão abaixo é override-able: revise antes de aprovar o Design.

---

## D1 — Qual é a fonte canônica da identidade?

**Decisão:** `app/assets/css/global.css` do legado é a **fonte de verdade** dos tokens e dos
componentes de shell/base. `ht21.css` (62KB) e `projeto-central.css` (16KB) são **referência
secundária** — extrair só padrões reutilizáveis (tabelas ricas, timeline, modais, filtros), não copiar.

**Por quê:** `global.css` é o design system real do legado; os outros são CSS de página acumulado.
O `system.md` da v2 já declara "porta de `global.css`".

**Alternativa rejeitada:** reproduzir `ht21.css` inteiro — traria dívida e padrões inconsistentes.

---

## D2 — Como os tokens vivem no Tailwind v4?

**Decisão:** Manter as **CSS custom properties** (`--accent`, `--surface-*`, `--fg-*`, `--r-*`…) em
`globals.css` como source of truth, e expô-las ao Tailwind via `@theme inline`. Componentes usam
utilities (`bg-surface-2`, `text-fg-2`, `rounded-lg`) sempre que houver token mapeado; `var(--x)`
arbitrário só quando não houver utility. **Proibido hex hardcoded** fora de `globals.css`.

**Por quê:** preserva tema claro/escuro por `data-theme` (troca de valores das vars) sem recompilar
classes, e dá DX de Tailwind. É a extensão natural do que já existe em `globals.css`.

**Alternativa rejeitada:** mover tudo para `tailwind.config` em JS — Tailwind v4 é CSS-first; quebraria
o theming por `data-theme`.

---

## D3 — Tema claro + escuro

**Decisão:** Manter **ambos**, escuro como padrão, via `html[data-theme]`. Portar os refinamentos do
tema claro do legado (sombras, bordas mais presentes, accent mais escuro para contraste AA).

**Por quê:** o legado entrega os dois temas; o toggle já existe na v2 (`use-theme.ts`).

---

## D4 — Estratégia de componentização

**Decisão:** Cada padrão visual do legado vira **componente React tipado** em `web/shared/ui/components`
(transversais) ou no módulo (específicos). Paridade visual ~1:1 com o legado, mas **refinada** — não
copiar pixel a pixel onde a v2 já melhorou. A v2 já tem: `Badge/NivelBadge`, `Button`, `Card/StatCard`,
`Drawer`, `Table`, `AppShell/Header/Sidebar`. Esta spec **completa o catálogo** e **reconcilia desvios**.

**Por quê:** elimina o copy-paste de ~17 páginas do legado (ARQ-01) e centraliza a identidade.

---

## D5 — Desvios já detectados entre legado e v2 (a reconciliar no Design)

| # | Onde | Legado | v2 atual | Resolver |
|---|------|--------|----------|----------|
| 1 | Botão primário | `color:#fff` sobre âmbar | `text-black` | Definir contraste oficial (preto lê melhor sobre #F29725 → manter v2, registrar no system) |
| 2 | Sidebar item ativo | `color: var(--accent)` (texto âmbar) | `text-fg` + barra âmbar à esquerda | Decidir assinatura única (barra à esquerda é refino bom → manter v2) |
| 3 | Scrollbar | oculta nos dois temas | discreta (thin, thumb visível) | Escolher um padrão global |
| 4 | Surfaces tema claro | `--surface-0:#eef1f6` | `--surface-0:#f4f5f7` | Alinhar valores (legado é a referência) |
| 5 | Sombras tema claro | `--shadow-*: none` + sombra pontual em cards | v2 não zera sombras no claro | Portar comportamento do legado |

**Por quê:** sem reconciliar, "manter identidade" fica ambíguo. Default: **legado decide cor/forma**,
**v2 decide refinamentos de craft** já validados.

---

## D6 — Escopo de aplicação

**Decisão:** A spec entrega (a) **camada de design system** (tokens + catálogo de componentes + shell)
e (b) **paridade visual** das telas já existentes na v2. A **migração tela-a-tela** (incl. fluxos
públicos `solicitar-placa`/`agendar-entrevista` e drawers/formulários internos) entra como **backlog
priorizado** em `tasks.md`, não tudo neste lote.

**Por quê:** "todo o estilo visual" é grande; o valor destrava primeiro com tokens+catálogo sólidos.

---

## D7 — Tipografia e ícones

**Decisão:** Manter **Inter** (via `next/font`, não CDN) e **emoji** como ícones de navegação (como o
legado). Avaliar troca por set SVG só se o usuário pedir (fora de escopo agora).

**Por quê:** preserva a identidade exata; `next/font` remove a dependência de CDN do legado.
