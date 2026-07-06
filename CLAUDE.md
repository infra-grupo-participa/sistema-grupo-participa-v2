# CLAUDE.md — sistema-grupo-participa

Documento vivo do projeto. Atualizar sempre que descobrir um hurdle, padrão novo ou decisão arquitetural relevante. O agente lê isto antes de cada sessão.

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
- Para tarefas substanciais: faça stack routing mental (owner, consulted, skipped, critical path) antes de executar.
- Não abra todos os docs nem spawne agentes sem necessidade real.

### Performance
- Máximo de tool calls paralelas quando independentes.
- Leia só o trecho necessário de arquivos grandes (use offset/limit).
- Evite ler o mesmo arquivo duas vezes na mesma conversa.

---

## Documentação Complementar

| Arquivo | Quando ler |
|---------|-----------|
| `docs/prd-placas.md` | Qualquer trabalho no fluxo de Placas (`solicitar-placa`, `agendar-entrevista`, `relatorios/placas`) |

---

## Estrutura do Repositório

```
sistema-grupo-participa/
├── app/                    ← DEPLOY: Frontend + API PHP (espelhado para /public_html/)
│   ├── api/                ← Backend PHP (proxy, webhooks)
│   ├── assets/             ← CSS/JS compartilhados
│   │   ├── css/global.css
│   │   └── js/ (auth.js, config.js)
│   ├── components/         ← PHP includes reutilizáveis
│   ├── login/
│   ├── projeto/            ← Uma pasta por projeto (kebab-case)
│   │   └── _template/      ← Template para novos projetos
│   ├── relatorios/
│   ├── sistema/
│   ├── usuarios/
│   ├── env-loader.php      ← Carrega .env (sem Composer)
│   ├── health.php          ← Health check endpoint
│   └── .htaccess
├── infra/                  ← NÃO DEPLOY: infraestrutura
│   ├── scripts/            ← Scripts Python utilitários
│   └── supabase/           ← Edge Functions
├── docs/                   ← NÃO DEPLOY: documentação e agentes
│   └── base-de-conhecimento/
├── .github/workflows/      ← CI/CD
├── CLAUDE.md               ← Este arquivo
└── README.md
```

## Convenções

- **Nomes de pasta:** sempre `kebab-case`
- **Projetos:** uma pasta por projeto em `app/projeto/`
- **PHP backend:** tudo em `app/api/`
- **Scripts não-deploy:** em `infra/scripts/`
- **Secrets:** nunca no código — usar `.env` (server-side) ou GitHub Secrets

---

## Visão Geral

Sistema interno do **Grupo Participa** para gestão de alunos, projetos e processos operacionais. Frontend estático (HTML/CSS/JS) servido via FTP em hospedagem Hostinger, com Supabase como backend (auth + banco de dados).

---

## Stack Tecnológico

| Camada | Tecnologia |
|--------|-----------|
| Frontend | HTML + CSS + JS vanilla (sem framework) |
| Auth + DB | Supabase (PostgreSQL + Auth) |
| Hospedagem | Hostinger (FTP deploy via lftp) |
| CI/CD | GitHub Actions |
| DNS/Domínio | grupoparticipa.app.br |

---

## Ambientes

**Só existe produção.** O ambiente de homologação foi descontinuado (jul/2026) — não há mais branch `homologacao`, deploy de homolog, nem clone de banco. Mudanças de banco vão direto no Supabase de produção.

| Ambiente | URL | Supabase |
|----------|-----|---------|
| Produção | grupoparticipa.app.br | `https://mbvybujpkwuorhtdzcde.supabase.co` |

### Deploy
- **Produção**: push para `main` → deploy automático do `web/` via git da Hostinger.

---

## Estrutura de Diretórios

```
app/
  index.html                    ← Dashboard principal
  relatorios/placas/relatorios.html  ← Relatório de Placas
  projeto/
    clinica-go/index.html
    clinica-sp/index.html
    holding-total-21/index.html
    holding-total-22/index.html
    imersao-go/index.html
    imersao-hf-sp/index.html
    palestra-01/index.html
    rio-inner-circle-03/index.html
    seminario-02/index.html
    workshop-online/index.html
    _template/index.php         ← Template para novos projetos
  sistema/
    alunos/index.php              ← Centro de Controle (ficha 360° do aluno)
    jarvis/index.html
    servicos-especializados/*/index.html
  usuarios/index.html
  api/
    admin-proxy.php
    sendflow-webhook.php
    purge.php
  assets/css/global.css
  assets/js/auth.js
  assets/js/config.js
  components/ (head, header, sidebar, scripts).php
  env-loader.php
  health.php
infra/scripts/*.py
infra/supabase/functions/*/index.ts
.github/workflows/
  deploy.yml                    ← Deploy prod (push main)
```

---

## Padrão de Páginas

Todas as páginas seguem o mesmo padrão (ver `clinica-go/index.html` como referência canônica):

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <!-- Google Fonts Inter -->
  <!-- Supabase JS CDN -->
  <style>/* CSS inline — sem arquivos externos */</style>
</head>
<body>
  <div id="app">
    <header><!-- logo + user info + logout --></header>
    <div id="body-wrap">
      <aside><!-- sidebar com grupos colapsáveis --></aside>
      <div id="content-area">
        <main><!-- conteúdo da página --></main>
      </div>
    </div>
  </div>
  <script>/* JS inline — sem arquivos externos */</script>
</body>
</html>
```

- **Sem arquivos externos** de CSS ou JS — tudo inline no HTML
- **Sidebar** tem grupos colapsáveis (`data-group`) com estado salvo em `localStorage`
- **Auth** verificada via `checkAuth()` em todo `init()` — redireciona para `/login` se sem sessão

---

## Banco de Dados — Tabelas Principais

### `perfis`
Perfis de usuários do sistema. Criado automaticamente via trigger ao registrar no Supabase Auth.
- `id` (uuid, FK → auth.users)
- `nome`, `email`, `cargo` (`admin` | `visualizador`), `status` (`ativo` | `pendente`)

### `thb_alunos`
**Hub central do sistema** — toda feature aponta para esta tabela.
- `id`, `nome`, `email`, `telefone`, `documento`, `estado`, `cidade`
- `nivel_resultado` — nível do aluno: `iniciante` | `pessoal` | `em_formacao` | `profissional` | `ouro` | `platina` | `diamante` | `diamante_vermelho`
- `turma_id` (FK → `thb_turmas.id`) — **sem constraint FK declarada no banco ainda**
- `comprador_id` (uuid, FK → `compradores.id`, ON DELETE SET NULL) — vincula ao universo transacional Hotmart
- Index em `comprador_id` (WHERE NOT NULL) e em `lower(trim(email))`

### `compradores`
Compradores do Hotmart (criados automaticamente via webhooks).
- `id`, `hotmart_ucode`, `nome`, `email` (UNIQUE index em `lower(trim(email))`), `telefone`, `documento`
- Endereço completo, `atualizado_em`
- **RLS restrito a `is_ht_operator()`** — acesso geral via `fn_aluno_360()` SECURITY DEFINER

### `vw_aluno_360` (VIEW)
Visão consolidada do aluno com flags derivadas de todas as tabelas:
- `tem_ht`, `tem_hm`, `data_compra_ht/hm` — via `compras`
- `ativacao_ht_status`, `ativacao_hm_status`, `hm_plano` — via `ativacoes`
- `tem_placa`, `placa_step`, `placa_encerrada` — via `thb_placas_auditoria`
- `tem_depoimento`, `total_depoimentos` — via `gp_depoimentos`
- `hotmart_ucode`, `turma_codigo` — via JOINs
- **Acesso**: via função `fn_aluno_360(uuid)` (SECURITY DEFINER, GRANT TO authenticated)

### `thb_turmas`
Turmas do programa.
- `id` (smallint), `codigo` (text: T1, T2… A1, A2…), `tipo` (`thb` | `aurum`)

### `thb_placas_auditoria`
Estado e histórico do processo de entrega de placas por aluno (workflow interno, operado pelo admin).
- `id`, `aluno_id` (UNIQUE FK → thb_alunos), `step_index`, `encerrado`, `dates` (jsonb), `obs`, `faturamento` (bigint), `protocolo`
- **RLS ativo** — requer políticas para acesso de usuários autenticados (ver hurdle abaixo)

### `thb_placas_solicitacoes`
Solicitações de placa via formulário público. Uma linha por aluno, identificado por `token` UUID.
- `id`, `token` (UNIQUE uuid), `email`, `nome`, `telefone`, `turma`
- `interesse`, `espaco_instrucao`, `nivel`, `faturamento_declarado` (bigint)
- `proof_url`, `declaracao_url` — URLs do Supabase Storage (bucket `documentos`)
- `cep`, `logradouro`, `numero`, `complemento`, `bairro`, `cidade`, `estado_uf`
- `documento_nf`, `email_entrega`
- `step_index` (0–9), `status` (`rascunho`|`enviado`|`em_auditoria`|`docs_aprovados`|`concluido`|`rejeitado`)
- `entrevista_data`, `entrevista_hora`, `entrevista_link`, `meet_link`
- `ciclo` (smallint, default 1), `nivel_anterior` (piso de bloqueio ao refazer) — ver "Refazer processo" abaixo
- **RLS desabilitado** — acesso público controlado pelo token UUID
- Ver detalhes completos em `docs/prd-placas.md`

### `thb_placas_ciclos`
Snapshot **imutável** de cada ciclo de placa concluído (arquivado ao refazer). Uma linha por conclusão.
- `solicitacao_id`, `aluno_id`, `ciclo`, `nivel`, `faturamento_declarado`, `faturamento_comprovado`
- `protocolo`, `codigo_rastreio`, `turma`, `espaco_instrucao`, `dates` (jsonb), `endereco` (jsonb), `concluido_em`
- **RLS ativo**: SELECT para `authenticated`; escrita só via `fn_placas_refazer` (SECURITY DEFINER) / service_role

### Refazer processo — "subiu de nível" (feature dentro de Placas)
Aluno com placa **`concluido`** (nível ≥ Ouro) pode refazer o processo por evolução de nível:
- Gatilho: CTA na tela de acompanhamento pública (`TrackingCard`) → `POST /api/placa` action `refazer`.
- **RPC atômica `fn_placas_refazer(p_token uuid)`** (SECURITY DEFINER, espelha `fn_placas_reprovar`):
  faz snapshot em `thb_placas_ciclos` **antes** do reset destrutivo da **mesma linha** (token/sessão/cookie
  preservados → o relatório continua associado à pessoa). Reseta solicitação p/ `rascunho`, incrementa `ciclo`,
  grava `nivel_anterior` (= nível concluído) e reseta a auditoria. `nivel_resultado` do aluno só muda quando a
  nova placa conclui (trigger `fn_sync_placa_nivel`, em `encerrado` false→true).
- **Bloqueio de nível**: `nivelRefazerBlockReason()` (domínio `form-progress.ts`) trava o nível concluído e
  todos os inferiores; só permite nível elegível **estritamente superior**. Validado no client (`validStep` /
  step 3 com `sp-level-locked`) **e** no servidor (`validateFormProgress` via `nivel_anterior` de `existing`).
- Admin vê badge "Ciclo N" + "Subiu de {nível}" e o painel "Ciclos de placa concluídos" no drawer.

### `thb_horarios_disponiveis`
Slots de entrevista configurados pelo admin. Recorrência semanal.
- `id`, `dia_semana` (0=Dom … 6=Sáb), `hora` ('HH:MM'), `ativo` (boolean)
- Lido anonimamente por `/agendar-entrevista` — requer policy anon SELECT

---

## Níveis de Resultado (`nivel_resultado`)

Ordenados por grau crescente de faturamento:

| Chave | Label | Faixa |
|-------|-------|-------|
| `iniciante` | Iniciante | — |
| `pessoal` | Pessoal | — |
| `em_formacao` | Em Formação | — |
| `profissional` | Profissional | — |
| `ouro` | Ouro | Primeiros R$ 50k |
| `platina` | Platina | R$ 500k em 12 meses |
| `diamante` | Diamante | R$ 1M em 12 meses |
| `diamante_vermelho` | Diamante Vermelho | R$ 5M+/ano |

Alunos com `nivel_resultado = null` (~1090 de 1515) **não aparecem na lista por padrão** — só via busca ativa.

---

## Unificação Aluno ↔ Comprador

`thb_alunos` é o **hub central** do sistema. Toda feature (Compras, Ativações HT/HM, Placas, Depoimentos) aponta para esta tabela.

### Arquitetura
- `thb_alunos.comprador_id` → FK para `compradores.id` (ON DELETE SET NULL)
- Matching por `lower(trim(email))` entre as duas tabelas
- View `vw_aluno_360` consolida dados de 6 tabelas sem duplicar colunas
- Função `fn_aluno_360(uuid)` — SECURITY DEFINER para bypass RLS de `compradores`

### Webhooks (`syncThbAluno`)
Ambos os webhooks Hotmart (HT e HM) chamam `syncThbAluno` após `upsertComprador`:
1. Busca `thb_alunos` por email (ilike)
2. Se existe e não tem `comprador_id` → vincula
3. Se não existe → cria novo registro com `fonte = 'webhook_hotmart_ht'` ou `'webhook_hotmart_hm'`

### Centro de Controle (`/sistema/alunos`)
Página dedicada com ficha 360° do aluno:
- Carrega dados via `db.rpc('fn_aluno_360')`
- Filtros: busca texto, nível, jornada (HT/HM/Placa/Depoimento)
- Tabela com sort por coluna
- Drawer lateral com 4 seções: Dados Pessoais, Programa, Jornada, Metadados
- CSS modular: `css/base.css`, `css/table.css`, `css/drawer.css` (prefixo `--cc-`)
- JS: `js/app.js`

### Regra para features futuras
Toda feature nova que envolva alunos deve:
1. Criar sua tabela própria com FK → `thb_alunos.id`
2. Atualizar `vw_aluno_360` para incluir flags derivadas
3. Propagar dados relevantes de volta para `thb_alunos` (write-back)

---

## Sidebar — Padrão de Grupos

Toda página tem seção "Relatórios" na sidebar:

```html
<div class="sidebar-group" data-group="reports">
  <button class="sidebar-section-toggle" type="button" onclick="toggleSidebarGroup('reports')">
    <span>Relatórios</span><span class="sidebar-section-chevron">⌄</span>
  </button>
  <div class="sidebar-group-body">
    <div class="sidebar-item" onclick="window.location.href='/relatorios/placas'">
      <span class="sidebar-item-icon">📋</span><span>Relatório de Placas</span>
    </div>
  </div>
</div>
<div class="sidebar-divider"></div>
```

---

## Controle de Acesso

- `isAdmin = perfil.cargo === 'admin'` — definido em `checkAuth()` após buscar perfil
- Somente admin pode editar dados de alunos, avançar/voltar etapas de auditoria
- Botões de ação ficam ocultos (`display:none`) para não-admins
- Todas as funções de escrita têm `if (!isAdmin) return` como guard

---

## Common Hurdles

### 1. Supabase join falha com "could not find a relationship"
PostgREST só faz joins automáticos se houver FK declarada no banco. Se a FK não existe, fazer duas queries separadas e mapear manualmente em JS.
- `thb_alunos.turma_id → thb_turmas.id` ainda não tem FK declarada — join é feito via duas queries

### 2. RLS bloqueia escrita em tabelas novas (403)
Toda tabela criada no Supabase tem RLS ativo por padrão. Sem políticas = ninguém acessa. Sempre criar políticas ao criar tabela:
```sql
CREATE POLICY "autenticados podem ler" ON nome_tabela
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "autenticados podem gravar" ON nome_tabela
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

### 3. z-index do edit panel abaixo do overlay principal
O overlay principal tem z-index 900. Edit panel e ep-overlay devem ser 1001+ para aparecer por cima. Se o edit panel "não abre", verificar z-index.

### 4. `nivel_resultado` default errado
Nunca usar `a.nivel_resultado || 'diamante'` como fallback — mascara dados reais. Usar `|| null` e tratar null explicitamente no render.

### 5. Perfil de usuário novo fica como `pendente`
Ao criar usuário via Supabase Auth UI, o trigger cria o perfil com `status = 'pendente'` e `cargo = 'visualizador'`. Atualizar manualmente:
```sql
UPDATE perfis SET cargo = 'admin', status = 'ativo' WHERE email = 'x@y.com';
```

### 6. Usuário criado via Auth UI tem UUID diferente do que está em `perfis`
Ao criar usuário via Auth UI, o UUID gerado pode conflitar com um perfil órfão existente. Verificar com `SELECT * FROM perfis WHERE email = '...'` e fazer UPDATE no perfil existente em vez de INSERT.

### 7. Botão dentro do overlay principal não abre painel secundário
Se um painel (edit panel) tem z-index menor que o overlay que o disparou, ele aparece atrás. Garantir que ep-overlay (1000) e edit-panel (1001) estejam acima do overlay principal (900).

### 8. Agendamento público e e-mails precisam de proteção extra
`confirm-horario.php` e `create-calendly-meeting.php` agora devem validar slot ativo, bloquear concorrência por horário e aplicar rate limit. Os endpoints `send-status-email.php` e `send-interview-email.php` devem aceitar somente origem/referer dos domínios oficiais e manter rate limit por IP.

### 9. CEP e rastreio devem atualizar sem refresh
O CEP do formulário público passa por `/api/cep.php`, com busca debounced no frontend e validação server-side antes de consultar o ViaCEP. O código de rastreio deve refletir no painel do aluno via update em tempo real ou polling de fallback, e o admin deve poder salvar o rastreio com `Enter` sem depender de refresh.

### 10. `step_index` 7 ainda é fase de agendamento
No fluxo de placas, `step_index`/`auditoria_step` igual a `7` não deve ser tratado como entrevista concluída. Use `step_index >= 8` ou data/hora já expiradas para bloquear reagendamento. Para links de retorno/acompanhamento, prefira origem permitida do request ou token já validado, nunca `HTTP_HOST` cru nem campo livre do payload.

---

## Design Patterns

### 0. REGRA FUNDAMENTAL — Nunca duplicar funções/consts de auth.js ou config.js
Qualquer função ou `const` já definida em `auth.js` ou `config.js` **não pode existir em nenhuma página HTML**. Duplicar causa:
- `SyntaxError: Identifier already declared` → quebra a página inteira
- Links sumindo da sidebar (ex: Depoimentos) porque a cópia local tinha lista incompleta
- Bugs silenciosos que não recebem atualizações futuras

**Consts proibidas de re-declarar:** `SUPABASE_URL`, `SUPABASE_KEY`, `db`, `PROJECTS`, `REPORTS`, `SYSTEM_NAV`, `ADMIN_PROXY`, `SIDEBAR_GROUPS_KEY`, `REPORTS_NAV_STATE_KEY`.

**Funções proibidas de re-declarar:** `renderSidebar`, `renderProjectNav`, `renderReportsNav`, `renderSystemNav`, `renderHomeNav`, `applySidebarGroups`, `toggleSidebarGroup`, `loadReportsNavState`, `saveReportsNavState`, `toggleReportsNavGroup`, `checkAuth`, `goLogin`, `renderHeaderUser`.

**Padrão correto para nova página:**
```html
<script src="/assets/js/config.js"></script>
<script src="/assets/js/auth.js"></script>
<script>
(async function init() {
  renderSidebar();                                      // cria aside + popula projetos/sistema
  const session = await checkAuth();
  if (!session) return;
  const perfil = await getUserProfile(session.user.id);
  renderHeaderUser(perfil);
  renderReportsNav('reports-nav', { isAdmin: perfil.cargo === 'admin' });
  // ... lógica da página
})();
</script>
```

### 1. CSS/JS inline no HTML
Sem arquivos externos — tudo em `<style>` e `<script>` no próprio HTML. Facilita deploy FTP e evita problemas de cache.

### 2. Supabase client no topo do script
```js
const SUPABASE_URL = 'https://...';
const SUPABASE_KEY = '...';
const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
```

### 3. init() async com await sequencial
```js
(async function init() {
  renderProjectNav();
  applySidebarGroups();
  await checkAuth();   // define isAdmin antes de qualquer render
  await loadUsers();   // busca dados reais
})();
```

### 4. Promise.all para fetches paralelos
```js
const [{ data: alunos }, { data: turmas }, { data: auditorias }] = await Promise.all([
  db.from('thb_alunos').select('...').order('nome'),
  db.from('thb_turmas').select('id, codigo'),
  db.from('thb_placas_auditoria').select('*'),
]);
```

### 5. Upsert com onConflict para audit state
```js
await db.from('thb_placas_auditoria')
  .upsert({ aluno_id: userId, ...campos }, { onConflict: 'aluno_id' })
  .select('id').single();
```

### 6. Rollback otimista
Atualizar estado local → tentar persistir → se erro, restaurar estado anterior e mostrar toast.

### 7. Admin gate em todas as funções de escrita
```js
async function minhaFuncao() {
  if (!isAdmin) return;
  // ...
}
```

### 8. Formatação de telefone E.164 → BR
```js
function formatTelefone(tel) {
  const c = String(tel).replace(/\D/g,'');
  if (c.startsWith('55') && c.length >= 12) {
    const l = c.slice(2), ddd = l.slice(0,2), num = l.slice(2);
    if (num.length === 9) return `(${ddd}) ${num.slice(0,5)}-${num.slice(5)}`;
  }
  return tel;
}
```

### 9. Faturamento como bigint
Armazenado como inteiro (bigint) no banco. Exibir com `Number(val).toLocaleString('pt-BR')`.

### 10. Sidebar collapse persistido em localStorage
```js
const SIDEBAR_GROUPS_KEY = 'gp_sidebar_groups';
function toggleSidebarGroup(name) { /* toggle + save */ }
function applySidebarGroups() { /* aplica ao carregar */ }
```

### 11. Alunos sem nível ocultos por padrão
Na listagem, filtrar `u.plano !== null` por padrão. Mostrar sem nível apenas quando há busca ativa.

### 12. Etapas de auditoria com buildTimeline()
Função compartilhada entre popup e edit panel. Recebe `u` (user object) e retorna HTML da timeline.

### 13. Estado de auditoria separado dos dados do aluno
`thb_alunos` = dados do aluno (fonte de verdade do import).
`thb_placas_auditoria` = processo de auditoria (step_index, dates, faturamento comprovado, protocolo, obs).
Uma linha por aluno, upsert por `aluno_id`.

### 14. CSS tokens via :root
```css
:root {
  --primary: #FF6300;
  --green: #16a34a;
  --border: #2a2a2a;
  --card: #111111;
  /* etc */
}
```

---

## Backlog Técnico

### CRÍTICO — Segurança (fazer antes de qualquer outra coisa)
| ID | Problema | Arquivo(s) | Correção |
|----|----------|-----------|---------|
| SEC-01 | Senha de banco em texto plano | `infra/scripts/db_migrate.py`, `hotmart_sync.py` | Mover para `os.getenv()` |
| SEC-02 | ClickUp API Key no frontend | `sistema/servicos-especializados/app.js` linha 6 | Proxy via `admin-proxy.php` |
| SEC-03 | Meta Ads token no PHP | `app/api/admin-proxy.php` linha 17 | Mover para `.env` |
| SEC-04 | SendFlow token hardcoded | `app/api/sendflow-webhook.php` linha 17 | Mover para `.env` |
| SEC-05 | Supabase Service Role Key commitada | `admin-proxy.php`, `sendflow-webhook.php` | Mover para `.env` servidor |

> `anon key` é ok no frontend (protegida por RLS). `service_role key` nunca no código ou frontend.

### ALTO — Duplicação
| ID | Problema | Impacto |
|----|----------|---------|
| ARQ-01 | ~17 páginas de projeto com conteúdo idêntico (~20k linhas) | 45% do codebase é copy-paste |
| ARQ-02 | Pastas duplicadas de projetos (legados junto com `projeto/`) | Navegação confusa |
| ARQ-03 | `holding-total-21/index.html` com 5.293 linhas | Impossível de manter |

### MÉDIO — Organização
| ID | Problema | Correção |
|----|----------|---------|
| ORG-01 | Falta `.env.example` | Criar com todas as variáveis (sem valores) |
| ORG-02 | Webhook duplicado | Verificar `infra/supabase/functions/` vs legado |
| ORG-03 | Login duplicado (`login.html` + `login/index.html`) | Unificar |
