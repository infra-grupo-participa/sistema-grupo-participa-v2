# CLAUDE.md — sistema-grupo-participa

Documento vivo do projeto. Atualizar sempre que descobrir um hurdle, padrão novo ou decisão arquitetural relevante. O agente lê isto antes de cada sessão.

> Reescrito em 05/10/2026 a partir do estado real do repo e do banco. A versão anterior descrevia o legado
> HTML/PHP (`app/`, FTP, `auth.js`/`config.js`), que **não existe mais**.

---

## Modo de Operação (SEMPRE ATIVO)

### Comunicação
- Zero enrolação. Resposta direta apenas.
- Frases curtas (3-6 palavras) quando possível.
- Código fala por si — não descreva o que o diff mostra.
- Se ação foi feita, diga resultado, não processo.

### Estratégia de Agentes
- **Busca rápida** (arquivo/classe específica) → Glob/Grep direto, sem agente.
- **Exploração ampla** do codebase → `Agent(Explore)`.
- **Planejamento** de implementação → `Agent(Plan)`.
- **Pesquisa complexa** multi-step → `Agent(general-purpose)`.
- **Tarefas independentes** → múltiplos Agents em paralelo.
- Não abra todos os docs nem spawne agentes sem necessidade real.

### Performance
- Máximo de tool calls paralelas quando independentes.
- Leia só o trecho necessário de arquivos grandes (use offset/limit).

---

## ⚠️ Regra obrigatória — banco de dados

**Todo pedido que passe pelo backend** (migration, função/RPC, view, trigger, policy/RLS, índice, cron, edge function
que escreve, ingestão, ou qualquer leitura/escrita de dado no Supabase) **começa lendo `docs/manual-banco-de-dados.md`**
e segue o ritual dele (seção 1), as 5 perguntas (seção 2) e o checklist de bolso (seção 11) antes de aplicar.
Na dúvida de critério de negócio: perguntar, não inventar.

## Documentação Complementar

| Arquivo | Quando ler |
|---------|-----------|
| `docs/manual-banco-de-dados.md` | **Obrigatório** antes de qualquer trabalho que toque o banco (ver regra acima) |
| `web/AGENTS.md` | Antes de codar Next: **"This is NOT the Next.js you know"** — consultar `web/node_modules/next/dist/docs/` |
| `web/ARCHITECTURE.md` | Camadas e regras de dependência (parcialmente desatualizado na lista de módulos) |
| `docs/central-de-dados.md` | Departamentos, rotas, redirects, como adicionar área, branches |
| `docs/projetos/placas/prd.md` | Qualquer trabalho no fluxo de Placas |
| `docs/projetos/depoimentos/` | Depoimentos (prd + spec) |
| `docs/pedidos-alteracao.md` | Pedidos de alteração / troca de sócio |
| `docs/remocao-acessos.md` | Remoção de Acessos |
| `docs/hm-ecosystem.md` | Holding Masters (HM), liberações, financeiro HM |
| `docs/ADR/0001-vigia-de-rotinas.md` | Qualquer cron novo |
| `.specs/features/identidade-visual/` | Tokens, cores, catálogo de componentes |
| `web/e2e/README.md` | E2E (somente leitura contra produção) |

`web/DEPLOY.md` ainda cita homologação e cut-over do legado — ignorar essas partes.

---

## Stack

| Camada | Tecnologia |
|--------|-----------|
| App | **Next.js 16** (App Router, Turbopack no dev) + React 19 + TypeScript |
| Estilo | Tailwind 4 — tokens em `web/app/globals.css` (`@theme inline`) |
| Auth + DB | Supabase (`@supabase/ssr`) — Postgres + Auth + Storage + Edge Functions (Deno) + pg_cron |
| Testes | vitest (`*.test.ts`, ambiente node) + Playwright (`web/e2e`) |
| Hospedagem | Hostinger — processo Node (`npm ci && npm run build && npm run start`) |
| Domínio | grupoparticipa.app.br |

---

## Ambientes e Deploy

**Só existe produção.** Homologação foi descontinuada (jul/2026).

| Ambiente | URL | Supabase |
|----------|-----|---------|
| Produção | grupoparticipa.app.br | `mbvybujpkwuorhtdzcde` |

- **Push na `main` → deploy automático** do `web/` (integração git da Hostinger).
- **CI** (`.github/workflows/ci.yml`, push main + PR): `tsc --noEmit`, `lint:edge`, `lint:tokens`, `npm test`, `npm run build`. Não roda ESLint nem e2e.
- **Migrations e edge functions** sobem à parte (Supabase MCP/CLI), direto em produção.
- **Branches**: uma por pessoa a partir da `main` (`arthur`, `victor`, `joao-pedro`, `luis-fernando`) + `feat/*`. Antes de levar à main: `npx tsc --noEmit`, `npx vitest run`, `npm run build` verdes.

### Rodar local
```bash
cd web && npm install && npm run dev   # http://localhost:3000
```
- `web/.env.local` (gitignored) — modelo em `web/.env.example`. Mínimo: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (há fallback de produção em `shared/infrastructure/config/env.ts`).
- Sem `SUPABASE_SERVICE_ROLE_KEY`, fluxos públicos de placa, gestão de usuários e cron falham localmente.
- **O dev local aponta para o banco de PRODUÇÃO.** Tudo que for salvo é real.
- `npm install` costuma reescrever `package-lock.json` — não commitar isso por acidente.
- `.claude/launch.json` sobe o dev server no painel do app.

### Comandos (em `web/`)
| Comando | O que faz |
|---|---|
| `npm run dev` / `build` / `start` | Next |
| `npm test` | vitest |
| `npx tsc --noEmit` | tipos |
| `npm run lint` | eslint (fora do CI) |
| `npm run lint:tokens` | `scripts/check-hex.mjs` — falha com `#hex` cru fora dos arquivos isentos (exceção por linha: `/* hex-ok */`) |
| `npm run lint:edge` | `scripts/check-edge.mjs` — typecheck strict das edge functions |
| `npm run e2e` / `e2e:prod` | Playwright (precisa `E2E_FIN_EMAIL`/`E2E_FIN_SENHA`) |

---

## Estrutura do Repositório

```
/
├── web/                         ← O PRODUTO (Next.js)
│   ├── app/                     ← rotas, layouts, Route Handlers (camada fina)
│   │   ├── (admin)/             ← tudo autenticado; layout faz getCurrentUser() + AppShell
│   │   ├── api/                 ← Route Handlers (público, cron, admin, integrações)
│   │   ├── login/ definir-senha/ auth/confirm/
│   │   ├── solicitar-placa/ agendar-entrevista/   ← públicas (candidato de placa)
│   │   └── globals.css          ← ÚNICO lugar com cores hex (tokens)
│   ├── modules/<feature>/       ← domain/ application/ infrastructure/ ui/
│   ├── shared/                  ← domain, application, infrastructure, composition, ui
│   ├── proxy.ts                 ← "middleware" do Next 16 (sessão, domínio, rotas públicas)
│   ├── scripts/ e2e/ public/
├── infra/
│   ├── supabase/migrations/     ← SQL + _ensaio.sql + .explain.md
│   ├── supabase/functions/      ← edge functions Deno (só 6 das ~40 do projeto)
│   └── scripts/                 ← Python utilitários
├── docs/                        ← PRDs, specs, ADR, auditorias
└── .specs/                      ← specs de feature (identidade visual)
```

### Módulos (`web/modules/`)
`alunos`, `placas`, `depoimentos`, `financeiro`, `remocao-acessos`, `usuarios`, `marketing` (só esqueleto).

### Camadas (regra de dependência)
- **domain**: regra pura — sem Next, sem Supabase. Testável.
- **application**: casos de uso + `ports.ts` (interfaces).
- **infrastructure**: adapters (`supabase-*.ts`, `*.repository.ts`, Zoom, ViaCEP, Resend, Groq).
- **ui**: componentes React da feature.
- Referência boa: `modules/financeiro` (port + repository + `carregar-*`). `modules/alunos` desvia (data access em `ui/*-data.ts`) — não replicar.

### `shared/`
- `domain/`: `auth/` (cargo, permissions, gp-user), `departamentos.ts`, nível de resultado, url-segura.
- `infrastructure/`: `supabase/` (clients + proxy-session), `config/env.ts` (único que lê `process.env`), `http/` (security, rate-limit, validation, session-cookie, upload), email, observability, ai.
- `composition/server-container.ts`: composition root (`getCurrentUser`, memoizado por request).
- `ui/`: design system (`components/`), `shell/` (AppShell, Header, Sidebar), `nav/` (config + `redirects.ts`), `pdf/`, `timeline/`, `departamentos/`.

---

## Rotas

### Autenticadas — `app/(admin)/`
- `/` — cards de departamento.
- **Educacional**: `/educacional`, `/educacional/alunos`, `/educacional/placas`, `/educacional/depoimentos` (+ `/biblioteca`), `/educacional/financeiro`, `/educacional/remocoes`, `/educacional/pedidos-alteracao`.
- **Marketing**: `/marketing` + `/marketing/{web,mensageria,trafego,audiovisual,social-media}` (em breve; gate admin/dev no layout).
- **Em breve**: `/comercial`, `/financeiro` (departamento ≠ módulo financeiro do Educacional), `/infra`.
- **Globais**: `/usuarios`, `/sistema/configuracoes`, `/sistema/admin-dev`.

### Públicas
`/login`, `/definir-senha`, `/auth/confirm`, `/solicitar-placa`, `/agendar-entrevista`, `/modelos/*`.

### Redirects (308)
Rotas antigas (`/sistema/alunos`, `/relatorios/placas|financeiro|remocoes`, `/depoimentos`) → `/educacional/...`. Tabela em `shared/ui/nav/redirects.ts`, aplicada no `next.config.ts`. **Nunca apagar entrada** — há links antigos no Slack.

### Route Handlers (`app/api/`)
| Tipo | Rotas | Proteção |
|---|---|---|
| Públicas | `placa`, `placa/upload`, `cep`, `agenda/hold`, `agenda/confirm` | `bootstrapPublic` (origin/método) + rate limit + token UUID no cookie `gp_placa_session` |
| Cron | `cron/interview-reminder`, `cron/placas-resumo` | Bearer `CRON_SECRET` |
| MCP + OAuth do Comercial | `mcp`, `oauth/registrar`, `oauth/token`, `/.well-known/oauth-*` (`docs/projetos/comercial/mcp.md`) | token `gpc_` (hash) / PKCE + código de uso único; consentimento em `/oauth/autorizar` (sessão + Comercial) |
| Servidor a servidor | `captura/lead` (`docs/captura-de-lead.md`) | Bearer `CAPTURA_LEAD_SECRET` em tempo constante, 503 sem segredo (fail-closed), bloqueio por IP após 10 falhas, corpo até 8 KB, service_role só no servidor |
| Autenticadas | `admin/usuarios`, `admin/placas/entrevista`, `email/status`, `depoimentos/*`, `sip/progresso` | `getCurrentUser()` + regra de permissão |
| Diagnóstico | `health` | checagem própria |

### `proxy.ts`
Delega para `shared/infrastructure/supabase/proxy-session.ts`: renova sessão; sessão de e-mail **não `@advmais.com`** = sem sessão (o `auth.users` é compartilhado com ~7 sistemas do grupo); candidato de placa fica restrito às rotas dele (escape: `/login?equipe=1`); sem sessão → `/login?redirect=` ou 401 JSON em `/api/*`. Arquivo novo não-imagem em `public/` precisa entrar em `PUBLIC_PREFIXES` (teste `proxy-dominio.test.ts`).

---

## Padrões de Código

- **Tela**: `page.tsx` (Server Component) faz o gate de acesso → renderiza `<Feature>Client.tsx` (Client Component).
- **Dados**: o client lê/grava via supabase-js do browser (REST/RPC sob RLS). Route Handlers só para fluxo público, cron, service role e integrações externas.
- **Não há server actions** (`'use server'`) no projeto — não introduzir sem decisão.
- **Validação**: manual (`shared/infrastructure/http/validation.ts`, `sanitize-form.ts`) + no banco (RPCs SECURITY DEFINER retornando `{ok, msg}`). `zod` está no package.json mas não é usado.
- **Clients Supabase** (`shared/infrastructure/supabase/`):
  - `createBrowserSupabase()` — Client Components; anon key; RLS manda.
  - `createServerSupabase()` — servidor com JWT do usuário (padrão no servidor).
  - `createAdminSupabase()` — service role, ignora RLS. **Nunca no browser.** Só após autorizar.
- **Env**: só `shared/infrastructure/config/env.ts` lê `process.env`.
- **Cores**: nunca `#hex` fora de `app/globals.css` (e isentos do `check-hex`). Usar tokens/classes do tema e componentes de `shared/ui/components`.
- **Imports**: alias `@/` = raiz de `web/`.
- **Nomenclatura**: arquivos kebab-case; componentes PascalCase `.tsx`; domínio em português (`podeVer`, `podeEditar`, `temFuncao`, `ehAdminOuAcima`); casos de uso com verbo (`carregar-board.ts`, `enviar-email-placa.ts`); regra de acesso do módulo em `domain/acesso.ts`.
- **Testes**: `*.test.ts` ao lado do arquivo (inclusive `route.test.ts`); `*.fumaca.test.ts` para fumaça. Sem teste de componente `.tsx`.
- **Faturamento**: bigint no banco; exibir com `toLocaleString('pt-BR')`.
- **`nivel_resultado`**: nunca fallback para um nível (`|| 'diamante'`). Tratar `null` explicitamente.

---

## Controle de Acesso

- **Cargos** (`shared/domain/auth/cargo.ts`, fonte `perfis.cargo`): `dev` > `admin` > `gestor` > `operador` > `visualizador`.
- **Setores** (`perfis.areas[]`): placas, depoimentos, centro_controle, financeiro, remocao_acessos, pedidos_alteracao (+ ativacao, social_media).
- **Funções** (`perfis.funcoes[]`): `setor.funcao` (ex.: `placas.hm_liberar`).
- `GetCurrentUser` → `null` se sem perfil, e-mail fora de `@advmais.com` ou status ≠ `ativo`.
- Regras puras em `shared/domain/auth/permissions.ts`: `podeVer`, `podeEditar`, `temFuncao`, `ehAdminOuAcima`, `podeVerCpf`, `mascarar` (LGPD).
- ⚠️ `podeVer` libera `visualizador` em qualquer setor → módulos sensíveis (Financeiro, Remoção) têm regra própria em `domain/acesso.ts`.
- Departamentos: `shared/domain/departamentos.ts` (`DEPARTAMENTOS`, `MODULO_DEPARTAMENTO`, `podeVerDepartamento`). Não há tabela de departamento no banco.
- **Defesa em camadas**: login recusa domínio externo → proxy → gate em `page.tsx`/`route.ts` → RLS. Layout e page renderizam em paralelo: page com dado sensível **também** chama a regra.

---

## Banco de Dados (Supabase produção)

> Antes de mexer: `docs/manual-banco-de-dados.md` (ritual, ensaio em `begin … rollback`, `explain analyze`, revoke de
> PUBLIC/anon em função nova, RLS provada com `set local role`, migration renomeada para a versão gravada).

### Schemas
- **Expostos à API**: `public` (núcleo deste sistema), `central`, `gps`, `rede`, `metodo`, `sip`, `workbook`, `kpi` — vários são de **outros sistemas do grupo** que compartilham o projeto Supabase e o `auth.users`.
- **Fechados** (acesso só via função): `ops` (vigia de rotinas), `controle`, `cs`, `fin`, `mkt`, `mkt_web`, `respondi`, `rsvp`, `ht`.
- `arquivo`: backups (sem acesso da API). Backups/staging novos vão aqui, não em `public`.

### Tabelas centrais (`public`)
- **`thb_alunos`** — hub. Toda feature de aluno aponta para cá (~30 FKs). `nivel_resultado` (8 níveis ou null — ~metade é null e não aparece na lista por padrão), `turma_id` (FK → `thb_turmas`), `comprador_id` (FK → `compradores`), `plano`, `status_acesso`.
- `thb_turmas` — `codigo` (T1…, A1…), `tipo` (`thb`|`aurum`).
- `compradores` (Hotmart, ~27k) e `compras`; `hm_liberacoes`, `hm_product_catalog`, `ht_product_catalog`, `ht_editions`.
- `perfis` — usuários do sistema (cargo, status, areas[], funcoes[]).
- Prefixos por domínio:
  - `thb_placas_*` — solicitacoes, auditoria, ciclos, reprovacoes, agendamento_logs, config; `thb_horarios_disponiveis`.
  - `gp_*` — depoimentos, cursos, tags.
  - `pa_*` — pedidos de alteração.
  - `ra_*` — remoção de acessos (casos, itens, marcadores, Slack).
  - `thb_alunos_historico`, `thb_alunos_audit_log`, `thb_system_events`.
- `vw_aluno_360` + **`fn_aluno_360` / `fn_aluno_360_safe`** (SECURITY DEFINER, filtra por `gp_eh_equipe()`) — ficha consolidada.

### Placas
- `thb_placas_solicitacoes`: uma linha por aluno, identificada por `token` UUID. Status reais: `rascunho`, `enviado`, `em_auditoria`, `docs_aprovados`, `cadastro_concluido`, `placa_postada`, `concluido`, `rejeitado` (sem CHECK no banco). `step_index` 0–9.
- RLS ligado: leitura `gp_eh_equipe()`, escrita `gp_pode_editar('placas')`. Fluxo público passa pelos Route Handlers com service role.
- **Refazer processo** ("subiu de nível"): `POST /api/placa` action `refazer` → RPC `fn_placas_refazer(p_token)`. Aceita `concluido` ou `cadastro_concluido`; reseta a mesma linha para `rascunho` (token preservado), grava `nivel_anterior`; só `concluido` faz snapshot em `thb_placas_ciclos` e incrementa `ciclo`. Bloqueio de nível em `nivelRefazerBlockReason()` (`form-progress.ts`), validado no client **e** no servidor.
- `step_index` 7 ainda é agendamento — entrevista concluída é `>= 8`.

### Padrões de banco
- **Nomenclatura**: snake_case, português, `*_id` para FK, `criado_em`/`atualizado_em` (preferir em tabelas novas — há legado com `created_at`), `fn_*` RPC, `vw_*` view, `trg_*` trigger.
- **Autorização** (helpers SECURITY DEFINER): `gp_eh_equipe()`, `gp_is_admin()`, `gp_pode_editar(setor)`, `tem_permissao(uid, 'area.acao')`, `is_ht_operator()`.
- **RLS em toda tabela nova exposta, com policy por helper.** Nunca `USING (true)` para `authenticated` — o login é compartilhado com outros sistemas (rede, metodo, workbook…). Policies RESTRICTIVE de bloqueio (`gps_block_aluno`, `sip_block_*`) existem em quase toda tabela.
- **RPC de escrita**: SECURITY DEFINER, `SET search_path`, guard interno de permissão, retorno `{ok, msg}`.
- **Write-back**: feature de aluno cria tabela própria com FK → `thb_alunos.id`, atualiza `vw_aluno_360` e propaga ao aluno via trigger.

### Migrations
- Arquivo: `infra/supabase/migrations/YYYYMMDD<letra>_snake_case.sql` (letra = ordem no dia; série longa `z##`).
- Acompanham: `<id>_ensaio.sql` (roda o cenário e termina em **ROLLBACK**, esperados no cabeçalho) e `<id>.explain.md` (o que foi testado, decisões, status de aplicação).
- Aplicar via `apply_migration` (fica no histórico). Evitar DDL por `execute_sql` — gera divergência entre repo e histórico.
- Commit/explain devem dizer se a migration foi **APLICADA** ou não.

### Cron e edge functions
- Cron HTTP usa **`ops.cron_post('<jobname>', url := ..., headers := ..., body := ...)`**, nunca `net.http_post` direto. Segredo de header lido do Vault no command. Ver ADR 0001.
- Edge functions: pasta kebab-case com `index.ts` em `infra/supabase/functions/`; `verify_jwt = false` e auth dentro da função (`X-Hotmart-Hottok`, `x-sync-chave` do Vault). Funções `sip-*`, `gps`, `workbook-*` etc. são de outros repos.

---

## Common Hurdles

1. **RLS bloqueia tabela nova (403)** — RLS vem ligado; sem policy ninguém acessa. Criar policy com helper (`gp_eh_equipe()` / `gp_pode_editar(setor)`), nunca `true`.
2. **Perfil novo fica `pendente`/`visualizador`** — trigger cria assim. Ativar via `/usuarios` ou `UPDATE perfis SET cargo=..., status='ativo'`. Conferir perfil órfão por e-mail antes de inserir.
3. **E-mail fora de `@advmais.com`** — login recusa e proxy trata como sem sessão. Não é bug.
4. **Fluxo público de placa** — `confirm`/`hold` validam slot ativo, travam concorrência e aplicam rate limit; e-mails aceitam só origem dos domínios oficiais. Links de retorno: origem permitida ou token validado, nunca `Host` cru nem campo do payload.
5. **CEP/rastreio sem refresh** — CEP via `/api/cep` (debounce + validação server antes do ViaCEP); rastreio reflete em tempo real/polling.
6. **Rota nova esquecida no proxy** — página pública nova precisa entrar em `PUBLIC_PREFIXES`.
7. **Hex no código quebra o CI** (`lint:tokens`) — usar token do tema.
8. **Next 16 difere do que você conhece** — `middleware` virou `proxy.ts`; ler `node_modules/next/dist/docs/` antes.
9. **Gate só no layout não basta** — layout e page renderizam em paralelo; page com dado chama a regra também.
10. **Site URL do Supabase é de outro sistema** (`sip.timeholdingbrasil.com.br`) — links/telas que o Supabase Auth monta a partir do Site URL (ex.: consentimento do OAuth server dele) não caem aqui. Por isso o OAuth do MCP do Comercial é próprio (`docs/projetos/comercial/mcp.md`).

---

## Dívidas Conhecidas (varredura 05/10/2026)

| Severidade | Item |
|---|---|
| 🔴 | `thb_alunos` (2 policies) e `perfis` leem com `USING (true)` p/ `authenticated` — usuários de rede/metodo/workbook conseguem ler |
| 🔴 | Migrations `20261005j/k/l` aplicadas sem registro no histórico |
| 🟠 | Triggers de sync duplicados em `compradores` e `gp_depoimentos` |
| 🟠 | `thb_alunos.comprador_id` com 2 FKs para `compradores` |
| 🟠 | Bucket `documentos` (comprovantes de placa) público |
| 🟠 | 33 funções SECURITY DEFINER em `public` executáveis por `anon` — conferir guard interno |
| 🟠 | `thb_placas_solicitacoes.status`/`step_index` sem CHECK |
| 🟡 | Tabelas de backup/staging soltas em `public` (`_dedup_map_*`, `*_backup_*`) |
| 🟡 | Timestamps misturados (`criado_em` × `created_at`); `updated_at` com várias funções de trigger diferentes |
| 🟡 | Nomes de cron mentem a frequência (`ingest-active-5min` roda a cada 15 min etc.) |
| 🟡 | `modules/alunos` sem application/infrastructure; `zod` instalado e não usado |
| 🟡 | `web/DEPLOY.md`, `web/ARCHITECTURE.md` e `README.md` desatualizados |
