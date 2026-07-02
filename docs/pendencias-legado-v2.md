# Pendências Legado → V2 — Verificação profunda (2026-07-02)

Varredura botão a botão do código legado (`../sistema-grupo-participa/app`) contra o v2 (`web/`),
por 4 agentes (admin de placas, fluxo público, alunos/usuários/login/admin-dev, depoimentos+APIs).
Diferenças puramente visuais ignoradas. Ganhos do v2 sem paralelo no legado não listados.

## 🔴 ALTO impacto operacional (falta de verdade)

| # | Pendência | Origem no legado | Nota |
|---|-----------|------------------|------|
| L-01 | **Lembrete de entrevista 4h antes (cron)** — e-mail `lembrete_entrevista` + janela 3h57–4h03 + `reminder_sent_at`. No v2 o campo existe no tipo mas nada o usa; sem cron, sem disparo manual. Impacto direto em no-show. | `api/send-interview-reminder.php` (cron Hostinger c/ CRON_SECRET) | Precisa de rota + agendador (Vercel cron / cron Hostinger) |
| L-02 | **Reenviar e-mail de agendamento** — cliente que perdeu o e-mail de docs_aprovados fica travado; admin não tem botão de reenvio no v2 (o drawer só diz "aguardando o cliente agendar"). | `relatorios.html:4629,5096` | Botão no drawer chamando `/api/email/status` tipo docs_aprovados |
| L-03 | **Agendamento manual pelo admin** — definir data/hora/link da entrevista e gerar Zoom sem depender do candidato. | `relatorios.html:8479-8481,8525` | Campos de entrevista no EditarDados + gerar Zoom |
| L-04 | **Criar depoimento novo + buscar/vincular aluno** — o v2 só edita depoimentos existentes; não há caminho de UI para cadastrar. **Maior gap de Depoimentos.** | `api/depoimentos/buscar-aluno.php` + `index.php POST` | Botão "+ Novo" + autocomplete de aluno + insert |
| L-05 | **Excluir depoimento** — sem DELETE no drawer do v2. | `api/depoimentos/index.php DELETE` | |
| L-06 | **Gestão de Turmas HM** (criar turma, datas de abertura/fechamento de carrinho, link do grupo, membros) — o webhook Hotmart depende dessas datas para classificar turma; sem UI no v2. | `sistema/alunos/js/app.js:164-402,1502-1533` | |
| L-07 | **Gestão de Edições HT** (criar/editar edição, data início vendas, status, carrinho, notas). | `app.js:1535-1711` | |
| L-08 | **Dashboard Financeiro & Renovações** (saldo a receber, inadimplentes, vencidos, vencem 90d, funil de renovação, top devedores) + **drill-down com export CSV para disparos de cobrança**. | `app.js:2276-2334, 2433-2595` | |
| L-09 | **Reset de senha de terceiros** pelo admin (campo "Nova senha" na edição de usuário). | `usuarios/index.html:943,2269` | via `admin.auth.admin.updateUserById` |
| L-10 | **Excluir usuário** (com checagem de dependências) — v2 não tem DELETE em /api/admin/usuarios. | `admin-proxy.php delete-user/user-dependencies` | |

## 🟡 MÉDIO impacto

| # | Pendência | Origem |
|---|-----------|--------|
| L-11 | **Filtros da fila de placas**: Nível, Turma, UF, Cidade, Status (5 selects) + ordenação clicável por coluna + paginação. V2 tem só busca textual + 4 gavetas. | `relatorios.html:6274-6390,6353,4287` |
| L-12 | **Edição da auditoria**: obs/anotações, protocolo, faturamento COMPROVADO (≠ declarado), datas manuais dos carimbos — painel B do legado inteiro sem porta. | `relatorios.html:2849,2998-2999,8248-8250` |
| L-13 | **Cancelar entrevista** (reset para vazio — candidato ou admin; hoje só "não compareceu"). | `api/reset-entrevista.php` |
| L-14 | **Recuperação automática de sessão** na etapa 1 do formulário público ("Sessão encontrada — continuar?" proativo ao digitar e-mail+documento). | `solicitar-placa/index.html:2845-2873` |
| L-15 | **Copiar link de agendamento por candidato** + **copiar dados logísticos** (bloco pronto para expedição). | `relatorios.html:4583-4597,4662` |
| L-16 | **Presença online no drawer da solicitação** (Instagram/Facebook/YouTube/site/tel profissional — nem exibe nem edita). | `relatorios.html:8470-8473` |
| L-17 | **E-mail de confirmação de redefinição de senha** (segurança: horário + IP) + tela dedicada de "definir nova senha" pós-link. | `api/password-reset-confirmation.php`; `login/index.html:192-202` |
| L-18 | **Paginação da lista de alunos** (legado 50/pág; v2 corta em 500) + botão Atualizar + realtime (canais cc-*). | `app.js:624-647,1725-1749` |
| L-19 | **Filtro financeiro granular** (em_atraso, só_sinal, reembolsado, cancelada, quitado — colapsado em "inadimplente") + seção financeira de LEITURA no drawer (pago/total/saldo/% quitado). | `index.php:59-68; app.js:990-1029` |
| L-20 | **Construtor de filtros avançados no-code** (30 campos, E/OU) + visões salvas na LISTA de alunos (v2 só tem no dashboard). | `app.js:1754-1975` |
| L-21 | **Resumo executivo do dashboard**: donut de situação de acesso, KPIs de adimplência, "vencem em 30d", seção "Ação necessária". | `app.js:2188-2274` |
| L-22 | **Painel de logs**: logs de agendamento na tela de placas (com limpar) e consulta Axiom no admin-dev. | `relatorios.html:4089-4210; api/admin-dev-logs.php` |
| L-23 | "Rejeitar" do v2 não seta `auditoria.encerrado=true` (legado `encerrarSolicitacao` setava). | `relatorios.html:6151` |
| L-24 | Export XLSX de placas ignora a gaveta ativa (legado respeitava todos os filtros). | `relatorios.html:4715` |
| L-25 | Filtro por nível na biblioteca de depoimentos + toggle ativo/inativo de curso. | `api/depoimentos/index.php?nivel=; cursos.php` |

## 🟢 BAIXO impacto / polish

- Tracking do cliente: tela comemorativa 🏆 no `concluido`, botão copiar rastreio, "Salvar na agenda",
  destaque "acessar sala" <2h, aviso de spam, botão "verificar andamento"/polling 15s. (`solicitar-placa/index.html:2628-2826`)
- Agendamento: polling do link Zoom pendente (40×5s), CTA "Falar com a Secretaria" nos estados vazios,
  variante comemorativa do "concluído". (`agendar-entrevista/index.html:283-326,1017-1052`)
- Máscara de moeda sem lock de cursor; botão manual de CEP + toast; KPI "com rastreio" nos finalizados.

## ✅ Cortado de propósito (sem ação de dev)

- Telas: Projetos/Ativação HT-HM, Social Media, Jarvis, Serviços Especializados (documentado em `web/shared/ui/nav/config.ts:1-2`).
- APIs satélites: `hotmart-sales`, `holding-masters-socios`, `social-media-meta`, `clickup-proxy`, `slack-notify`, `purge` (LiteSpeed).
- Auto-cadastro no login (v2 é só-convite, decisão coerente); campo País (fixo "Brasil" interno); fallback de e-mail genérico.
- `create-calendly-meeting.php` **não era Calendly** — sempre foi Zoom; já portado.
- `team-structure.php` → coberto pela tela de Usuários do v2.

## ⚠️ Ação operacional externa (não é código)

- **Desligar o cenário do SendFlow** que ainda posta em `sendflow-webhook.php` do legado — quando o
  legado sair do ar, o webhook 404. O v2 não precisa de porta (Ativação HT-HM descontinuada).
- Configurar o **cron** do lembrete de entrevista (L-01) na infra escolhida quando implementado.

## Sugestão de ordem de ataque

1. **Sprint go-live** (destrava operação diária): L-01, L-02, L-03, L-13, L-11 (filtros+sort), L-23.
2. **Sprint depoimentos**: L-04, L-05, L-25.
3. **Sprint gestão**: L-06, L-07, L-09, L-10, L-12.
4. **Sprint financeiro**: L-08, L-19, L-21.
5. Polish contínuo: itens 🟢.
