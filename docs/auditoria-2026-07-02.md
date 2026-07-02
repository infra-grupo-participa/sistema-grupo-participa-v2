# Auditoria Geral — 2026-07-02

Auditoria completa do sistema (código `web/`, banco Supabase prod, UX, specs, segurança).
Itens marcados ✅ foram executados nesta mesma data; itens ⏳ ficam como backlog priorizado.

## Estado geral

- Typecheck limpo, ESLint limpo, 49/49 testes passando, `npm audit` sem vulnerabilidades.
- Sem TODO/FIXME pendurados, sem botões órfãos, sem rotas quebradas, sem service_role key vazada, sem `.env` no histórico git.
- Arquitetura de segurança da API madura: `bootstrapPublic`, rate limit, magic bytes em upload, slot-lock, escape em e-mails, gates server-side por cargo.

## P0 — Segurança (banco Supabase prod: 105 lints, 23 ERROR)

| # | Item | Status |
|---|------|--------|
| DB-01 | **21 tabelas sem RLS expostas via API** — 20 backups (`thb_alunos_bkp_*`, `_bak_*`, `_stg`) com PII de ~1.600 alunos + `hm_product_catalog`. Habilitar RLS (backups: sem policy = bloqueia API; app não os usa). | ✅ |
| DB-02 | **Políticas de escrita `USING (true)`** em `thb_placas_solicitacoes`, `thb_placas_auditoria`, `thb_placas_config`, `thb_placas_reprovacoes`, `thb_horarios_disponiveis`, `log_*`, `thb_system_events`, `tags_produtos` — qualquer autenticado (inclusive visualizador) escreve direto pela API. Restringir escrita por cargo. | ✅ (ver detalhe no rodapé) |
| DB-03 | Views SECURITY DEFINER: `vw_aluno_360`, `vw_gp_depoimentos_alunos` — avaliar `security_invoker` ou revogar SELECT direto (acesso já é via `fn_aluno_360_safe`). | ⏳ requer análise de grants antes de mexer |
| DB-04 | 19 funções SECURITY DEFINER executáveis por `anon` (inclui `fn_aluno_360*`, `sip.*`). Cuidado: funções `sip.check_login_rate_limit`/`record_login_attempt` provavelmente são chamadas pré-auth pelo SIP legado. Revogar EXECUTE caso a caso. | ⏳ |
| DB-05 | 13 funções sem `search_path` fixo (`function_search_path_mutable`). | ⏳ |
| DB-06 | Proteção contra senhas vazadas (HaveIBeenPwned) desabilitada no Auth. Ativar no dashboard Supabase → Auth → Passwords. | ⏳ manual (dashboard) |
| DB-07 | 17 tabelas do schema `sip` com RLS ligado e zero policies (acesso só via service_role — confirmar se intencional). | ⏳ pertence ao SIP legado |
| DB-08 | Limpeza: avaliar DROP das tabelas de backup antigas (jun/2026) após período de retenção — hoje são 15+ cópias de `thb_alunos`. | ⏳ decisão do dono |
| DB-09 | **Escalação de privilégio via `perfis`** (achado novo durante a execução): a policy `usuario_atualiza_proprio` limitava a linha mas não as colunas — qualquer autenticado podia elevar o próprio `cargo`/`nivel_hierarquia`/`eh_dev`. Corrigido com grants de coluna (UPDATE só em `nome`, `avatar_url`, `atualizado_em`). Migration `perfis_column_level_update`. | ✅ |
| DB-10 | **Dados inconsistentes em `perfis`**: 2 usuários com `cargo=admin` mas `nivel_hierarquia=visualizador` e 1 com `nivel=gestor`. O app trata como admin (cargo prevalece no `normalizeCargo`); `tem_permissao()` no banco nega. Alinhar os valores (o dono decide se são admins mesmo). | ⏳ decisão do dono |

## P0 — Segurança (código)

| # | Item | Status |
|---|------|--------|
| SEC-01 | **XSS refletido** em `web/public/modelos/declaracao-template.html` — query params injetados via `innerHTML` sem escape, mesmo origin do app autenticado. | ✅ |
| SEC-02 | **Sem headers de segurança globais** (CSP frame-ancestors, X-Frame-Options, HSTS, nosniff, Referrer-Policy) para páginas HTML — só APIs tinham. Adicionar `headers()` no `next.config.ts`. | ✅ |
| SEC-03 | `/api/email/status` sem rate limit (envia e-mail para qualquer endereço com gate `podeEditar('placas')`). | ✅ |
| SEC-04 | `sistema/configuracoes/page.tsx` só checa sessão, não cargo. **Reclassificado: por design** — a página edita apenas o próprio perfil; enforcement real é o RLS de `perfis` (linha própria + grants de coluna do DB-09). Documentado no código. | ✅ |
| SEC-05 | `env.ts:30-37` — URL + anon key de **produção** hardcoded como fallback (`\|\|`): build sem `NEXT_PUBLIC_*` aponta silenciosamente para prod; JWT expira em 2087 (rotação exige mudar código). Remover fallback exige garantir envs no servidor Hostinger antes — **não mexer sem validar o ambiente de deploy**. | ⏳ |
| SEC-06 | Rate limit e slot-lock em memória de processo único — se escalar horizontalmente, double-booking volta. Garantia definitiva: constraint `UNIQUE` no banco sobre (entrevista_data, entrevista_hora) confirmadas. | ⏳ |
| SEC-07 | `clientIp` confia em `x-forwarded-for` spoofável — rate limit dos endpoints públicos contornável. Confiar só no header do proxy real da Hostinger. | ⏳ |
| SEC-08 | `/api/health` público expõe booleans de env vars sensíveis (mapeamento de superfície). Reduzir a `{ok:true}` ou proteger. | ⏳ |
| SEC-09 | `/api/sip/progresso` sem rate limit (service_role, enumeração de e-mail por admin). | ⏳ baixo |
| SEC-10 | Webhooks Hotmart: comparação de `hottok` não é constant-time (risco teórico). | ⏳ opcional |

## P1 — Arquitetura e consistência

| # | Item | Status |
|---|------|--------|
| ARQ-01 | **Ports mortos** em `modules/placas/application/ports.ts` — 5 ports definidos e nunca implementados (`SolicitacaoRepository`, `AuditoriaRepository`, `HorariosRepository`, `AlunoBootstrapPort`, `PlacaMailer`). Implementar ou remover; alinhar ARCHITECTURE.md à realidade. | ⏳ |
| ARQ-02 | **Dois padrões de acesso a dados**: fluxos públicos via route handlers + adapters (correto); fluxos admin fazem CRUD e regra de negócio direto do browser (`alunos-data.ts`, `depoimentos-data.ts`, `placas-admin-data.ts`), dependendo 100% de RLS. Decidir padrão único. Mitigado parcialmente por DB-02. | ⏳ decisão de arquitetura |
| ARQ-03 | Route handlers instanciam adapters diretamente (`new SupabaseAgenda()` etc.) — composition root (`server-container.ts`) só provê `getCurrentUser`. | ⏳ junto com ARQ-01 |
| ARQ-04 | `alunos-data.ts` engole erros de query (sem `logQueryError`, diferente dos outros módulos); `updateAluno`/`saveDepoimento` vazam `error.message` cru. | ⏳ |
| ARQ-05 | `resolvePublicToken` (validation.ts) aparenta ser helper órfão (rotas usam `resolvePlacaToken`). | ⏳ |
| ARQ-06 | Allowlist de rotas públicas duplicada (`PUBLIC_PREFIXES` em proxy-session.ts + `matcher` em proxy.ts); `LEGACY_ORIGINS` inclui localhost. | ⏳ |
| ARQ-07 | **CLAUDE.md do repo descreve a estrutura PHP antiga** (app/, FTP, GitHub Actions) — desatualizado desde a migração Next.js. Reescrever. | ⏳ |
| TST-01 | **Zero testes no domínio de permissões** (`shared/domain/auth/permissions.ts`, `modules/usuarios/domain/cargos.ts`) — lógica de authz mais sensível do sistema. | ✅ |
| TST-02 | Zero testes de integração de rotas de API (auth/authz, rate limit, origem, slot-lock) e de adapters. | ⏳ |
| TST-03 | Sem testes E2E do funil crítico (login → solicitar placa → agendar → auditoria). | ⏳ |

## P2 — UX

| # | Item | Status |
|---|------|--------|
| UX-01 | Radios do formulário público (`SolicitarPlacaSteps.tsx` — interesse/espaço/nível) sem input, sem foco, não operáveis por teclado/leitor de tela. | ✅ |
| UX-02 | Skeleton loader só existe no piloto (local em `RelatorioPlacasClient`); criar componente no barrel e aplicar em Alunos/Depoimentos/Usuários. | ✅ |
| UX-03 | `confirm()`/`prompt()` nativos em Depoimentos e DashboardAlunos em vez de `ConfirmDialog`/`Modal` do DS. | ✅ |
| UX-04 | Toast local reimplementado em `ConfiguracoesClient` (viola "NUNCA reimplementar toast local"). | ✅ |
| UX-05 | Botão só-ícone sem `aria-label` (excluir tag em Depoimentos). | ✅ |
| UX-06 | Headers âmbar públicos com texto branco (~1.9:1, abaixo de AA); decisão D5.1 do DS manda texto preto sobre âmbar. | ✅ |
| UX-07 | **Fluxos públicos rodam em design system paralelo** (solicitar-placa.css, 690 linhas, hex próprios `--orange`/`--muted`) — migrar para tokens/componentes do DS oficial. | ⏳ projeto próprio |
| UX-08 | `AlunoDrawer.tsx` (572 linhas) — dividir em orquestrador + painéis + `*-shared.ts` como o piloto; `SolicitacaoDrawer.tsx` (420) borderline. | ⏳ |
| UX-09 | Upload das etapas 4/5 sem indicador de progresso (só `busy` global). | ⏳ |
| UX-10 | `<input type="color">` cru em Depoimentos; datas relativas + `title` só no piloto. | ⏳ |

## P3 — Produto / funcional

| # | Item | Status |
|---|------|--------|
| PRD-01 | Aba "Desempenho no curso" da ficha 360 é **mock 100% zerado** (`curso-mock.ts`) — UI pronta, integração inexistente. Ligar à fonte real ou ocultar a aba. | ⏳ decisão do dono |
| PRD-02 | **Decisão de produto pendente**: as 27 specs em `sip/.specs/features` são todas da plataforma do aluno SIP (chamados, ciclos, trilhas, IG metrics, debriefing). O v2 só lê o SIP (ponte read-only). Definir: v2 absorve o SIP ou permanece console de gestão? | ⏳ decisão do dono |
| PRD-03 | Quick win viável hoje: visão "alunos Aurum aprovados sem primeiro acesso" (spec `alunos-sem-acesso`) usando a ponte `api/sip/progresso` existente. | ⏳ |
| PRD-04 | Zoom não configurado degrada silenciosamente ("link será enviado em breve") — confirmar se intencional ou configurar credenciais. | ⏳ |
| PRD-05 | Tabela `ativacoes` do banco virou `ativacoes_bak_20260701` — confirmar consolidação intencional dos dados de ativação. | ⏳ verificar |

---

## Refatoração de cargos (executada em 2026-07-02, após a auditoria)

Decisão do dono: manter os 5 cargos canônicos; fonte de verdade única = `perfis.cargo` + `areas`
(setores) + `funcoes`; perfis inconsistentes resolvidos preservando o comportamento efetivo do app
(`normalizeCargo` foi a regra de migração — inclui josue@ com `eh_dev=true` → `cargo='dev'`).

**Fase A (banco — migration `unifica_modelo_cargos_fase_a`)** ✅
- Constraint legada `perfis_cargo_check` (não permitia `dev`/`gestor` — a origem histórica do modelo
  duplo com `nivel_hierarquia`) substituída por `perfis_cargo_canonico` (5 valores).
- Nova coluna `perfis.funcoes text[]` (o app sempre exigiu funções para operador editar, mas a coluna
  não existia — operador nunca conseguia editar).
- Dados normalizados: cargo canônico, áreas `ativacao_ht/hm` → `ativacao`, `permissoes_usuario`
  migrada para `funcoes` (chaves `ativacao_*.x` → `ativacao.x`).
- Funções reescritas para ler só cargo/areas/funcoes: `gp_is_admin` (agora inclui dev),
  `gp_pode_editar`, `tem_permissao` (espelha `temFuncao` do app; sem tabelas auxiliares),
  `is_ht_operator` (não depende mais do cargo extinto `'ativacao'`), `handle_new_user` (sanitiza
  cargo do metadata para o conjunto canônico).
- `nivel_hierarquia`/`eh_dev`/`permissoes_usuario`/`templates_cargo` marcadas DEPRECATED (comments).

**Fase B (app)** ✅
- `normalizeCargo` lê só `cargo` (aliases legados mantidos por defesa); `PerfilData`/repositories/
  API admin não leem nem escrevem mais `nivel_hierarquia`/`eh_dev`; `funcoes` entrou no select.
- `FUNCAO_META` (catálogo de funções por setor) em `modules/usuarios/domain/cargos.ts`; EditDrawer
  de Usuários ganhou checkboxes de funções para operador (filtradas pelos setores marcados).
- Testes: normalizeCargo canônico + gramática do catálogo (chave prefixada pelo setor).

**Fase C (pendente — rodar após janela de validação de ~1-2 semanas)** ⏳
```sql
ALTER TABLE public.perfis DROP COLUMN nivel_hierarquia;
ALTER TABLE public.perfis DROP COLUMN eh_dev;
DROP TABLE public.permissoes_usuario;
DROP TABLE public.templates_cargo;
```
Antes de rodar: confirmar que nada no SIP legado lê essas colunas/tabelas e que nenhum erro novo
apareceu em `/sistema/admin-dev`.

---

## Caça-bugs pré-produção (executada em 2026-07-02, 3 agentes + fixes)

**Fluxo público (corrigidos ✅):** agendar exigia só `em_auditoria` (candidato pulava a aprovação
de docs e a auditoria saltava 0→2) → agora exige `docs_aprovados`, com a mesma guarda no hold
(que também deixava candidato bloqueado "envenenar" slots); e-mail com casing diferente criava
solicitação duplicada (matching agora ilike); blur de duplicidade divergia do save (rascunhos);
upload travava reenvio legítimo ao voltar etapas (agora: rascunho/correção liberam, resto bloqueia);
gcalLink estourava em slots 23:xx e ignorava fuso; double-booking agora tem garantia no banco
(índice único `uq_entrevista_slot` + 409 amigável).

**Admin (corrigidos ✅):** `avancarEtapa` não-atômico podia travar o processo para sempre e perder
o e-mail de agendamento (agora sequencial: solicitação → auditoria, e-mail após sucesso);
`voltarEtapa` não recomputava status (badge "Placa enviada" com etapa atrás); `aprovarReenvio`/
`marcarNaoCompareceu` retornavam sucesso mesmo com RLS negando; `bootstrapAuditoria` zerava
histórico de carimbos ao reprocessar (agora idempotente), casava e-mail case-sensitive (criava
aluno duplicado) e agora gera `protocolo` (PL-ANO-XXXXXXXX); `excluirSolicitacao` deixava
`placa_solicitacao_id` órfão; export vazava rascunhos (fallback para step do formulário);
slots duplicados quebravam a remoção automática.

**Completude do fluxo (corrigidos ✅):** rejeição era inatingível (função sem botão) → botão
"Rejeitar" com motivo + e-mail `solicitacao_rejeitada` + tela própria no acompanhamento do
cliente (antes mostrava progresso falso); conclusão (step 6) agora seta `encerrado=true`
(dispara o write-back oficial de nível via `fn_sync_placa_nivel`, agora SECURITY DEFINER) e
envia e-mail `placa_recebida`; submit final envia `solicitacao_recebida`; fluxo curto
(não-elegível) envia `nivel_registrado`; os 3 novos templates são editáveis na Config.

**Regressão da unificação de cargos (corrigida ✅):** policies de `thb_alunos`/`ht_editions`/
`gp_rate_limit_log` checavam `cargo='admin'` literal — dev não escrevia. Padronizadas em
`gp_is_admin()`/`gp_pode_editar()`. Triggers de write-back viraram SECURITY DEFINER.

**Backlog não bloqueante:** agenda recorrente (PRD prevê `dia_semana`; hoje só slot avulso);
campo "faturamento comprovado" sem UI própria (admin edita só o declarado); config de e-mails
com last-write-wins em edição concorrente; rate limit em memória (single-process por premissa).

## Checklist de go-live (cut-over do domínio)

1. **Envs na Hostinger** (painel → Node app): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
   `NEXT_PUBLIC_APP_URL=https://grupoparticipa.app.br`, `APP_ALLOWED_ORIGINS` — o /api/health
   (logado como dev) mostra o que falta; hoje o app roda no fallback hardcoded (SEC-05).
2. **Supabase Auth**: ativar "Leaked password protection" (dashboard → Auth → Passwords) e conferir
   Site URL/Redirect URLs para o domínio final.
3. **Resend/e-mails**: conferir `MAIL_FROM` no domínio verificado e `ADMIN_EMAIL`.
4. **Trocar o document root** do domínio para o app Node (DEPLOY.md §Cut-over) e testar:
   login, /solicitar-placa (wizard completo), /agendar-entrevista, /relatorios/placas, e-mails.
5. **Pós-cut-over**: dropar backups antigos do banco (DB-08) e rodar a Fase C dos cargos após a
   janela de validação; agendar `/security-review` periódico.

---

### Detalhe DB-02 (políticas aplicadas)

Escrita (INSERT/UPDATE/DELETE) nas tabelas operacionais passou a exigir cargo com permissão
(`tem_permissao`/cargo admin+), mantendo SELECT como estava. Fluxo público continua via
service_role (bypassa RLS) — sem impacto. Ver migration `tighten_write_policies` no Supabase.
