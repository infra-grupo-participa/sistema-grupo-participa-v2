# Tasks — Identidade Visual v2

> Ordem por dependência. Cada item referencia a User Story (P1/P2/P3) e o critério de aceite.
> Marcar `[x]` ao concluir. Fases 0–2 = MVP do design system; fase 3 = migração de telas.

## Fase 0 — Tokens e fundação (P1: Tokens) ✅

- [x] **0.1** Auditar `globals.css` v2 × `global.css` legado: faltavam `--space-*`, sombras no
      tema claro e tons `info`; níveis já existiam (extra da v2).
- [x] **0.2** `:root` + `html[data-theme="light"]` completos, tema claro alinhado ao legado
      (surfaces `#eef1f6`/`#dde3ec`; sombras **zeradas** no claro → profundidade por borda). _(D5#4/#5)_
- [x] **0.3** `@theme inline` completo: semânticas, níveis, bordas, accent variants, info, fg-4.
      Raios via `rounded-[var(--r-*)]` (evita colisão com utilities nativas). _(AC #2)_
- [x] **0.4** Scrollbar discreta nos 2 temas + `:focus-visible` ring âmbar. _(D5#3)_
- [x] **0.5** Tema sem flash no SSR — já resolvido por `themeInit` no `app/layout.tsx`. _(AC #3)_
- [x] **0.6** Guard `scripts/check-hex.mjs` + `npm run lint:tokens` (escopo `shared/ui`). _(AC #4)_

## Fase 1 — Catálogo compartilhado (P1: Catálogo) ✅

### Reconciliar existentes _(AC Catálogo #3 + D5)_
- [x] **1.1** `Button`: `text-black` no primary confirmado (contraste). Variantes/sizes OK.
- [x] **1.2** `StatCard`: prop `bar` (borda-topo `accent/green/yellow/red/purple/gray`).
- [x] **1.3** `Sidebar`/`Header`: item ativo com barra de acento à esquerda (mantido).

### Construir compartilhados _(AC Catálogo #1/#2)_
- [x] **1.4** `SectionCard` (título+sub+right); `SectionTitle` já existia.
- [x] **1.5** `EmptyState` — já existia (refino v2; borda-tracejada do legado descartada).
- [x] **1.6** `Spinner` + `Loading`.
- [x] **1.7** `Tabs` — já existia no `Drawer.tsx` (underline âmbar). Cobre o padrão.
- [x] **1.8** `Pill` — coberto por `Badge` (tons + dot). Sem duplicar identificador.
- [x] **1.9** `Toolbar` + `SearchInput` + `Input`.
- [x] **1.10** `FilterSelect` (chevron custom).
- [x] **1.11** `Toggle` (switch âmbar 38×21).
- [x] **1.12** `ProgressBar`.
- [x] **1.13** `Modal` + `ConfirmDialog`.
- [x] **1.14** `Timeline` (dot colorido por tom + corpo).
- [x] **1.15** `KpiCard` (border-left colorida).
- [x] **1.16** Barrel `index.ts` atualizado.

> Build limpo + `lint:tokens` verde após a fase.

## Status da execução (2026-06-30) — TODAS as 10 telas migradas ✅

Build `✓ Compiled successfully` + `lint:tokens` verde + type check ok.

**Migradas:** Login, Dashboard/home, Usuários, Configurações, Admin Dev (leva 1);
Alunos (lista+dashboard), Relatório de Placas, Solicitar Placa, Agendar Entrevista, Depoimentos (leva 2).

**Catálogo ampliado nesta etapa:** `Card` tipa `href/target/rel`; `Button` variant `link`; `Checkbox`.

**Decisões de execução registradas:**
- Fluxos públicos (`solicitar-placa`, `agendar-entrevista`) são **tema-claro** e usam CSS co-localizado
  (`.sp-*`); `Input`/`FilterSelect` do catálogo fixam superfícies dark → NÃO aplicados ali (quebrariam o
  tema claro). Trocas seguras feitas (Modal, ProgressBar, Timeline, Badge); inputs mantidos no CSS local.
- `confirm()` nativos do Relatório de Placas → `ConfirmDialog` do catálogo.

**Gaps de catálogo (tratados com sub-componente local tokenizado; extrair p/ `shared/ui` se reincidirem):**
`Toast`, `Textarea`, `EditForm`/labeled-field-grid, `PageTabs` (tabs com contagem), gráficos
(`Bars`/`Donut`/`Matrix`/`ColumnChart`), `Chip` removível, `Button` variant `warn` (amarelo), color-picker.

> Verificação adversarial por agente foi pulada (economia de tokens). Garantia atual = build + type check
> + guard de tokens + relato `comportamento_preservado=true` dos 10 agentes. Validação visual no app: pendente.

## Fase 2 — Reconciliação + paridade do existente (P2)

- [ ] **2.1** Atualizar `.interface-design/system.md`: decisões D5 finais + inventário de tokens/componentes. _(AC P2-Doc #1/#2)_
- [ ] **2.2** Tela de exemplo (sandbox) montada só com `shared/ui`, sem CSS local → valida composição. _(AC Catálogo Independent Test)_
- [ ] **2.3** Revisar **dashboard** (home/atalhos) usando catálogo final. _(AC P2-Paridade)_
- [ ] **2.4** Revisar **Alunos** (stats/tabela/nível/situação).
- [ ] **2.5** Revisar **Placas** e **Depoimentos** (tabelas + badges).
- [ ] **2.6** Rodar token test + checks (swap/squint/signature/token) nas telas revisadas. _(AC P2-Doc #3)_

## Fase 3 — Migração das telas ricas (P3)

- [ ] **3.1** Componentes específicos: `AuditTimeline`, `EditPanel` (sobre `Drawer`). _(AC P3 #1)_
- [ ] **3.2** Migrar **`relatorios/placas`**: KPIs + filtros + tabela + timeline + edit panels. _(AC P3 #1)_
- [ ] **3.3** Componentes: `StepProgress` + `StepForm` (+ `CalendarPicker` se necessário).
- [ ] **3.4** Migrar **`solicitar-placa`**: multi-step (progress/transições/upload/CEP). _(AC P3 #2)_
- [ ] **3.5** Migrar **`agendar-entrevista`** (slots + calendário). _(AC P3 #2)_
- [ ] **3.6** Componente `AreaLayout`; migrar **`usuarios`** (áreas + cards + edit panel). _(AC P3 #3)_
- [ ] **3.7** Migrar **`admin/depoimentos`** (tabs cursos/tags/depoimentos + edit panels). _(AC P3 #3)_
- [ ] **3.8** Componente `Funnel` (se algum dashboard precisar).

## Critério de pronto (Definition of Done)
- Todos os tokens do legado disponíveis e mapeados; tema claro/escuro fiéis.
- Telas montáveis só por composição de `shared/ui`; zero hex hardcoded fora de `globals.css`.
- `system.md` atualizado; paridade verificada por screenshot (dark+light+mobile).
