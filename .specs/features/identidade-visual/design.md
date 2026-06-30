# Design — Identidade Visual v2

> Mapeia o "como": tokens → Tailwind, catálogo de componentes (existente + a construir), shell,
> tema e reconciliação de desvios. Fonte legado: `app/assets/css/global.css` (+ `projeto-central.css`,
> `ht21.css`, telas ricas). Alvo: `web/` (Next 16, React 19, Tailwind v4 CSS-first).

## 1. Arquitetura de tokens (Tailwind v4)

**Camada 1 — source of truth (`web/app/globals.css`):** CSS custom properties em `:root` (dark) e
`html[data-theme="light"]`. Espelha 1:1 os grupos do legado: Brand (`--accent*`), Semantic
(`--green/yellow/purple/red` + `-subtle`/`-border`), Surfaces (`--surface-0..4`), Borders
(`--border-faint/border/-strong/-accent`), Foreground (`--fg..--fg-4`), Spacing (`--space-1..10`),
Radius (`--r-sm..-pill`), Shadows (`--shadow-sm/md/lg`), Layout (`--header-height`,`--sidebar-width`),
Níveis (`--nivel-*`) e Interação (`--ring`, `--t-fast/-mid`).

**Camada 2 — exposição Tailwind (`@theme inline`):** mapear vars → cores/utilities. Hoje só há
surfaces/accent/fg parciais. **Ação:** completar o mapa.

| Grupo legado | CSS var | `@theme` token | Utility resultante |
|---|---|---|---|
| Acento | `--accent`,`--accent-dim`,`--accent-subtle`,`--accent-border` | `--color-accent*` | `bg-accent`,`text-accent`,`border-accent` |
| Superfície | `--surface-0..4` | `--color-surface-0..4` | `bg-surface-2`, `bg-surface-3` |
| Texto | `--fg..--fg-4` | `--color-fg..fg-4` | `text-fg`,`text-fg-2` |
| Borda | `--border*` | `--color-border-gp`,`-faint`,`-strong` | `border-border-gp` |
| Semântica | `--green/yellow/purple/red(+subtle/border)` | `--color-green*` … | `text-green`,`bg-green-subtle` |
| Nível | `--nivel-*` | `--color-nivel-*` | `text-nivel-ouro` |
| Raio | `--r-sm..-pill` | `--radius-sm..-pill` | `rounded-md`,`rounded-pill` |
| Espaço | `--space-*` | (usar escala Tailwind nativa 4px) | `p-4`,`gap-2` |

**Regra:** componentes preferem utilities mapeadas; `[var(--x)]` arbitrário só quando não há token
(ex.: `info` #60a5fa). Hex hardcoded proibido fora de `globals.css`.

## 2. Tema claro/escuro

- Default dark (`color-scheme: dark`). `html[data-theme="light"]` redefine as vars.
- Portar do legado: tema claro com `--surface-0:#eef1f6`, cards brancos com `--shadow-sm`, bordas
  mais presentes, accent mais escuro (`#E07F10`). **Alinhar valores ao legado** (D5#4/#5).
- `use-theme.ts` já alterna; garantir SSR sem flash (classe no `<html>` antes da hidratação).

## 3. Catálogo de componentes

### 3.1 Já existem (revisar/reconciliar)
| Componente | Estado | Ação |
|---|---|---|
| `Button` | primary/ghost/danger/success/subtle, sm/md | Reconciliar contraste primary (`text-black` vs legado `#fff`) — **manter preto**, registrar. |
| `Badge` / `NivelBadge` | tons + dot; nível por metal/pedra | OK. Confirmar paleta `info`. |
| `Card` / `StatCard` | número tabular + label + tom | Adicionar variante de borda-topo colorida (`orange/green/yellow/gray`) do legado. |
| `Drawer` | overlay + painel deslizante + header sticky | OK. Base p/ edit panels. |
| `Table` (DataTable/Th/Tr/Td) | header sticky, sort, tabular | OK. Base p/ tabelas ricas. |
| `AppShell`/`Header`/`Sidebar` | shell completo | Reconciliar item ativo (barra à esquerda — **manter**) e scrollbar (D5#2/#3). |

### 3.2 A construir — compartilhados (`web/shared/ui/components`)
| Componente | Origem legado | Notas de design |
|---|---|---|
| `SectionTitle` / `SectionCard` | `.section-title/.section-sub/.section-card` | título 18/700 + sub `fg-2` + card `rounded-xl` `border` `p-8`. |
| `EmptyState` | `.empty-state` | borda tracejada `accent-border`, bg `accent-subtle`, texto âmbar. |
| `Spinner` / `Loading` | `.spinner/.loading-wrap` | track `surface-4`, top `accent`, `loading-wrap` em card. |
| `Tabs` | `.tab-btn/.tab-pane` | underline âmbar no ativo, `fadeIn` no pane. |
| `Pill` / `PillRow` | `.pill(.orange/.green/.purple)` | variante de Badge h-28, usar tom semântico. |
| `Toolbar` + `SearchInput` | `.toolbar/.search-wrap/.search-icon` | input com ícone overlay, dark. |
| `FilterSelect` | `.filter-select` (ht21) | select com chevron SVG custom, estados coloridos opcionais. |
| `Toggle` | `.toggle/.toggle-slider` (ht21) | switch 38×21, checked translateX(17), accent. |
| `ProgressBar` | `.progress-bar/.vg-progress-bar` | trilho fino 3–6px, fill âmbar (gradient opcional). |
| `Modal` / `ConfirmDialog` | `.modal*`,`#confirm-*` (ht21) | overlay `rgba(0,0,0,.72)`, box `surface-2`, `slideUp`; Confirm binário. |
| `Timeline` | `.historico-*` (ht21) + auditoria placas | item com ícone circular colorido por ação + corpo. |
| `KpiCard` (border-left) | `.vg-kpi-card/.ht21-info-card` | variante de StatCard com borda-esquerda 4px colorida. |

### 3.3 A construir — específicos de feature (no módulo)
| Componente | Feature | Origem |
|---|---|---|
| `StepProgress` + `StepForm` | `solicitar-placa` | multi-step com progress + transições + upload + CEP. |
| `AuditTimeline` + `EditPanel` | `placas` (relatório) | steps de auditoria + painel de edição (usa `Drawer`). |
| `CalendarPicker` | `agendar-entrevista`/placas | date picker custom (range, hoje, seleção âmbar) — só se necessário. |
| `Funnel` | dashboards | linhas com barra de cor + label + valor + separador (pills). |
| `AreaLayout` | `usuarios` | layout por área + cards de usuário + edit panel. |

## 4. Reconciliação de desvios (decisões D5 → finais)

1. **Botão primário:** `text-black` sobre âmbar (melhor contraste). Registrar no `system.md`.
2. **Sidebar ativo:** barra de acento à esquerda + `text-fg`/tom âmbar sutil (refino v2 mantido).
3. **Scrollbar:** padrão único = discreta (thin) nos dois temas. Remover regra "oculta" do legado.
4. **Surfaces tema claro:** alinhar aos valores do legado (`#eef1f6`/`#dde3ec`).
5. **Sombras tema claro:** zerar globais e aplicar `--shadow-sm` pontual em cards (comportamento legado).

## 5. Tipografia e ícones
- **Inter** via `next/font/google` (remove CDN do legado, evita FOUT). `font-feature-settings:'cv11','ss01'`.
- Números: classe `.tabular` (`tabular-nums`) em KPIs/tabelas.
- Ícones de navegação: **emoji** (identidade atual). Eventual set SVG = fora de escopo.

## 6. Estrutura de arquivos (alvo)
```
web/
  app/globals.css                 ← tokens + @theme (completar mapa)
  shared/ui/
    components/                   ← catálogo compartilhado (3.1 + 3.2)
      index.ts                    ← barrel export
    shell/                        ← Header/Sidebar/AppShell (reconciliar)
    nav/config.ts
  modules/<feature>/ui/           ← componentes específicos (3.3)
  .interface-design/system.md     ← atualizar (decisões + inventário)
```

## 7. Estratégia de verificação
- **Paridade:** screenshot legado × v2 por componente/tela, dark+light, desktop+mobile.
- **Token test:** `grep` por hex hardcoded fora de `globals.css` → deve dar vazio.
- **Composição:** tela de exemplo montada só com imports de `shared/ui`, sem CSS local.
- **Checks do `system.md`:** swap / squint / signature / token antes de aprovar cada componente.
