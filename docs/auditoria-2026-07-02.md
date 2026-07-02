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

### Detalhe DB-02 (políticas aplicadas)

Escrita (INSERT/UPDATE/DELETE) nas tabelas operacionais passou a exigir cargo com permissão
(`tem_permissao`/cargo admin+), mantendo SELECT como estava. Fluxo público continua via
service_role (bypassa RLS) — sem impacto. Ver migration `tighten_write_policies` no Supabase.
