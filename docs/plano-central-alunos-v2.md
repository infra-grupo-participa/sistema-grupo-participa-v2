# Plano Técnico — Central de Alunos v2

## Objetivo
Reformular a página `/sistema/alunos` (Centro de Controle) para torná-la um hub completo do aluno com:
- Dados editáveis com UX simplificada
- Filtros rápidos por pills clicáveis + filtros avançados
- Exibição detalhada de todas as features em que o aluno participa
- Links que levam ao pop-up da feature específica (placas, depoimentos)
- Campos novos editáveis: espaço de instrução, tipo HM/HT
- Listas em cadeia (expandíveis) no drawer

---

## Arquivos a Alterar

| Arquivo | O que fazer |
|---------|-------------|
| `app/sistema/alunos/index.php` | Adicionar filtros rápidos (pills), filtro por turma, filtro por tipo HM/HT |
| `app/sistema/alunos/js/app.js` | Drawer expandido, edição inline, links para features, listas em cadeia, novos filtros |
| `app/sistema/alunos/css/base.css` | Estilos para filtros rápidos (pills clicáveis), chips de tipo |
| `app/sistema/alunos/css/drawer.css` | Seções expandíveis (accordion), links clicáveis na jornada, inline edit |
| `app/sistema/alunos/css/table.css` | Sem alteração significativa |

---

## REGRAS CRÍTICAS (ler antes de qualquer alteração)

1. **NUNCA re-declarar** funções ou constantes de `auth.js` ou `config.js`. Ver lista completa em CLAUDE.md seção "Design Patterns > 0".
2. **Usar** `db.rpc('fn_aluno_360_safe')` para carregar dados (já existe, não mudar).
3. **Escrita em thb_alunos**: proteger com `if (!podeEditarAluno) return;` (variável já existe em app.js:16).
4. **Variáveis de estado**: usar o objeto `state` existente (app.js:30-47). Adicionar novas propriedades nele, nunca criar variáveis globais.
5. **Toast**: usar a função `toast(msg, type)` já existente (app.js:758).
6. **Escape HTML**: usar a função `esc(s)` já existente (app.js:717).
7. **CSS**: usar variáveis `--cc-*` já definidas em base.css. Novas variáveis devem seguir o mesmo padrão.
8. **Não criar arquivos novos**. Todas as alterações devem ser nos 4 arquivos existentes.
9. **Não alterar** as abas de Turmas HM e Edições HT (já funcionam, não mexer).
10. **Manter** toda a lógica de realtime (channels) intacta (app.js:1106-1148).

---

## Tarefa 1 — Filtros Rápidos (index.php + base.css + app.js)

### 1.1 HTML — Adicionar filtros rápidos no `index.php`

Inserir ENTRE o toolbar existente (linha 49) e o count (linha 76), um novo bloco de filtros rápidos:

```html
<!-- Quick Filters (pills clicáveis) -->
<div class="cc-quick-filters" id="cc-quick-filters">
  <button class="cc-qf-pill active" data-qf="todos" type="button">Todos</button>
  <button class="cc-qf-pill" data-qf="com_ht" type="button">Holding Total</button>
  <button class="cc-qf-pill" data-qf="com_hm" type="button">Holding Masters</button>
  <button class="cc-qf-pill" data-qf="com_placa" type="button">Com Placa</button>
  <button class="cc-qf-pill" data-qf="com_depoimento" type="button">Com Depoimento</button>
  <button class="cc-qf-pill" data-qf="sem_nivel" type="button">Sem Nível</button>
</div>
```

Também adicionar um filtro de turma e tipo (HM/HT) no toolbar existente. Inserir DEPOIS do select `cc-filtro-jornada` (linha 72):

```html
<select class="cc-filter-select" id="cc-filtro-turma">
  <option value="todos">Todas as turmas</option>
  <!-- Populado dinamicamente via JS -->
</select>
<select class="cc-filter-select" id="cc-filtro-tipo">
  <option value="todos">HM e HT</option>
  <option value="so_hm">Só HM</option>
  <option value="so_ht">Só HT</option>
  <option value="ambos">Ambos (HM+HT)</option>
</select>
```

**REMOVER** o select `cc-filtro-jornada` existente (linhas 66-72) pois os quick filters substituem essa funcionalidade.

### 1.2 CSS — Estilos para quick filters

Adicionar no final de `base.css`:

```css
/* Quick filters */
.cc-quick-filters {
  display: flex; flex-wrap: wrap; gap: 6px; padding: 2px 0;
}
.cc-qf-pill {
  padding: 6px 14px; border-radius: 999px; border: 1px solid var(--cc-border);
  background: var(--cc-surface); color: var(--cc-text-soft); font-size: 12px;
  font-weight: 600; cursor: pointer; transition: all .15s; white-space: nowrap;
}
.cc-qf-pill:hover { border-color: var(--cc-orange); color: var(--cc-text); }
.cc-qf-pill.active {
  background: var(--cc-orange); border-color: var(--cc-orange); color: #000; font-weight: 700;
}
```

### 1.3 JS — Lógica dos quick filters

No `app.js`, adicionar ao state (linha 36, após `filtroJornada`):

```js
filtroQuick: 'todos',
filtroTurma: 'todos',
filtroTipo: 'todos',
```

Adicionar event listeners (após os existentes, ~linha 780):

```js
// Quick filters
document.querySelectorAll('.cc-qf-pill').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.cc-qf-pill').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    state.filtroQuick = btn.dataset.qf;
    state.page = 0;
    applyFilters();
  });
});

// Filtro turma
document.getElementById('cc-filtro-turma').addEventListener('change', e => {
  state.filtroTurma = e.target.value;
  applyFilters();
});

// Filtro tipo
document.getElementById('cc-filtro-tipo').addEventListener('change', e => {
  state.filtroTipo = e.target.value;
  applyFilters();
});
```

Popular o select de turmas após `loadAlunos()`. Adicionar esta lógica dentro de `loadAlunos()`, DEPOIS de `state.alunos = all;` (linha 79):

```js
// Popula filtro de turmas (valores únicos)
const turmaSelect = document.getElementById('cc-filtro-turma');
const turmasUnicas = [...new Set(all.map(a => a.turma_codigo).filter(Boolean))].sort();
turmaSelect.innerHTML = '<option value="todos">Todas as turmas</option>' +
  turmasUnicas.map(t => `<option value="${t}">${esc(t)}</option>`).join('');
```

Alterar a função `applyFilters()` para incluir os novos filtros. SUBSTITUIR o bloco de filtro de jornada (linhas 385-388) por:

```js
// Quick filter
if (state.filtroQuick !== 'todos') {
  if (state.filtroQuick === 'com_ht' && !a.tem_ht) return false;
  if (state.filtroQuick === 'com_hm' && !a.tem_hm) return false;
  if (state.filtroQuick === 'com_placa' && !a.tem_placa) return false;
  if (state.filtroQuick === 'com_depoimento' && !a.tem_depoimento) return false;
  if (state.filtroQuick === 'sem_nivel' && a.nivel_resultado) return false;
}

// Filtro turma
if (state.filtroTurma !== 'todos' && a.turma_codigo !== state.filtroTurma) return false;

// Filtro tipo (HM/HT)
if (state.filtroTipo === 'so_hm' && !a.tem_hm) return false;
if (state.filtroTipo === 'so_ht' && !a.tem_ht) return false;
if (state.filtroTipo === 'ambos' && (!a.tem_ht || !a.tem_hm)) return false;
```

**REMOVER** o event listener do `cc-filtro-jornada` antigo (linhas 778-781) e a referência `state.filtroJornada`.

---

## Tarefa 2 — Drawer Expandido com Dados Completos (app.js + drawer.css)

### 2.1 Expandir `buildDrawerContent(a)` (app.js:527-578)

SUBSTITUIR a função `buildDrawerContent(a)` inteira por uma versão que inclui:

#### Seção 1: Dados Pessoais (manter, expandir)
- Manter: Nome, Email, Telefone, Documento, Profissão, Endereço
- **Adicionar**: Link Facebook (se existir, como link clicável)
- **Adicionar**: País

#### Seção 2: Programa (expandir com novos campos)
- Manter: Nível, Plano, Turma HM
- **Adicionar**: Espaço de Instrução — mostrar valor formatado:
  - `holding_masters` → "Holding Masters"
  - `aurum` → "Mentoria Aurum"
  - `coach_platina` → "Coach Platina"
  - `mastermind` → "Mastermind"
  - `null` → "Não definido"
- **Adicionar**: Tipo do Cliente — derivado de `tem_ht` e `tem_hm`:
  - Ambos true → "HM + HT"
  - Só HT → "Holding Total"
  - Só HM → "Holding Masters"
  - Nenhum → "Sem produto"
- **Adicionar**: Placa Aurum (se existir)
- **Adicionar**: Turma Aurum (se existir `turma_aurum_id`)
- **Adicionar**: Sócio (se `eh_socio`, mostrar nome do sócio)

#### Seção 3: Jornada — REFORMULAR como lista em cadeia clicável

Cada item da jornada deve ser um card expandível (accordion) que mostra sub-detalhes E tem um botão de ação que leva para a feature.

Implementar assim:

```js
function buildJornadaSection(a) {
  return `
    <div class="cc-d-block">
      <div class="cc-d-section"><span class="cc-d-section-icon">🚀</span> Jornada do Aluno</div>
      <div class="cc-d-jornada-chain">

        ${buildJornadaCard('Holding Total', a.tem_ht, {
          status: a.ativacao_ht_status,
          dataCompra: a.data_compra_ht,
        }, null)}

        ${buildJornadaCard('Holding Masters', a.tem_hm, {
          status: a.ativacao_hm_status,
          dataCompra: a.data_compra_hm,
          plano: a.hm_plano,
        }, null)}

        ${buildJornadaCard('Placa de Resultado', a.tem_placa, {
          step: a.placa_step,
          encerrada: a.placa_encerrada,
          protocolo: a.placa_protocolo,
        }, a.tem_placa ? '/relatorios/placas' : null)}

        ${buildJornadaCard('Depoimento', a.tem_depoimento, {
          total: a.total_depoimentos,
        }, a.tem_depoimento ? '/depoimentos' : null)}

      </div>
    </div>`;
}
```

Função auxiliar `buildJornadaCard`:

```js
function buildJornadaCard(label, active, details, linkUrl) {
  const cls = active ? 'active' : 'inactive';
  const chevron = active ? '▾' : '▸';

  let detailsHtml = '';
  if (active) {
    const rows = [];
    if (details.status) rows.push(dRow('Status', formatStatus(details.status)));
    if (details.dataCompra) rows.push(dRow('Data da compra', fmtData(details.dataCompra)));
    if (details.plano) rows.push(dRow('Plano', details.plano));
    if (details.step !== undefined) rows.push(dRow('Etapa atual', `${details.step || 0} de 9`));
    if (details.encerrada !== undefined) rows.push(dRow('Concluída', details.encerrada ? 'Sim ✓' : 'Em andamento'));
    if (details.protocolo) rows.push(dRow('Protocolo', details.protocolo));
    if (details.total) rows.push(dRow('Total registrado', `${details.total} depoimento(s)`));
    detailsHtml = `<div class="cc-jc-details">${rows.join('')}</div>`;
  }

  const linkHtml = (active && linkUrl)
    ? `<a class="cc-jc-link" href="${linkUrl}" target="_blank">Abrir na feature →</a>`
    : '';

  return `
    <div class="cc-jc-card ${cls}" onclick="this.classList.toggle('expanded')">
      <div class="cc-jc-header">
        <div class="cc-jc-dot"></div>
        <span class="cc-jc-label">${esc(label)}</span>
        <span class="cc-jc-badge">${active ? 'Ativo' : 'Não iniciado'}</span>
        ${active ? `<span class="cc-jc-chevron">${chevron}</span>` : ''}
      </div>
      ${detailsHtml}
      ${linkHtml}
    </div>`;
}
```

Função auxiliar `formatStatus`:

```js
function formatStatus(status) {
  const map = {
    fazer_onboarding: 'Aguardando Onboarding',
    em_ativacao: 'Em Ativação',
    ativado: 'Ativado',
    cancelado: 'Cancelado',
    pendente: 'Pendente',
    concluido: 'Concluído',
  };
  return map[status] || status || '—';
}
```

#### Seção 4: Metadados (manter como está)

### 2.2 CSS — Estilos para jornada em cadeia

Adicionar no final de `drawer.css`:

```css
/* Jornada em cadeia (accordion) */
.cc-d-jornada-chain { display: flex; flex-direction: column; gap: 0; }
.cc-jc-card {
  border: 1px solid var(--border); border-radius: 0;
  background: var(--surface-2); padding: 0;
  transition: border-color .15s; cursor: default;
}
.cc-jc-card:first-child { border-radius: 10px 10px 0 0; }
.cc-jc-card:last-child { border-radius: 0 0 10px 10px; }
.cc-jc-card:only-child { border-radius: 10px; }
.cc-jc-card + .cc-jc-card { border-top: none; }

.cc-jc-card.active { cursor: pointer; }
.cc-jc-card.active:hover { border-color: rgba(22,163,74,.3); }

.cc-jc-header {
  display: flex; align-items: center; gap: 10px;
  padding: 12px 14px;
}
.cc-jc-dot {
  width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
  background: var(--surface-4); border: 1px solid var(--border);
}
.cc-jc-card.active .cc-jc-dot {
  background: var(--cc-green); border-color: var(--cc-green);
  box-shadow: 0 0 0 3px rgba(22,163,74,.2);
}
.cc-jc-label { flex: 1; font-size: 13px; font-weight: 600; color: var(--cc-text); }
.cc-jc-card.inactive .cc-jc-label { color: var(--cc-text-dim); }
.cc-jc-badge {
  font-size: 10px; font-weight: 700; padding: 2px 8px; border-radius: 999px;
  background: rgba(255,255,255,.05); border: 1px solid var(--cc-border); color: var(--cc-text-soft);
}
.cc-jc-card.active .cc-jc-badge {
  background: rgba(22,163,74,.1); border-color: rgba(22,163,74,.25); color: var(--cc-green);
}
.cc-jc-chevron {
  font-size: 12px; color: var(--cc-text-soft); transition: transform .15s;
}
.cc-jc-card.expanded .cc-jc-chevron { transform: rotate(180deg); }

/* Detalhes (ocultos por padrão, visíveis quando expanded) */
.cc-jc-details {
  display: none; border-top: 1px solid var(--border-faint);
  background: var(--surface-3);
}
.cc-jc-card.expanded .cc-jc-details { display: block; }

.cc-jc-details .cc-d-row { padding: 8px 14px; }
.cc-jc-details .cc-d-label { font-size: 11px; }
.cc-jc-details .cc-d-value { font-size: 12px; }

.cc-jc-link {
  display: block; padding: 8px 14px; font-size: 11px; font-weight: 700;
  color: var(--cc-orange); text-decoration: none; border-top: 1px solid var(--border-faint);
  transition: background .15s; display: none;
}
.cc-jc-card.expanded .cc-jc-link { display: block; }
.cc-jc-link:hover { background: rgba(242,151,37,.05); }
```

---

## Tarefa 3 — Formulário de Edição Expandido (app.js)

### 3.1 Expandir `buildEditForm(a)` (app.js:581-624)

SUBSTITUIR a função inteira. O novo formulário deve ter:

#### Seção Dados Pessoais (manter campos existentes + adicionar):
- Nome, Email, Telefone, Documento, Profissão — **manter como está**
- **Adicionar** Link Facebook: `<input type="url" id="ef-facebook" value="${esc(a.link_facebook || '')}">`
- Cidade, Estado — **manter como está**
- **Adicionar** CEP: `<input type="text" id="ef-cep" value="${esc(a.cep || '')}">`
- **Adicionar** Logradouro: `<input type="text" id="ef-logradouro" value="${esc(a.endereco_logradouro || '')}">`
- **Adicionar** Número: `<input type="text" id="ef-numero" value="${esc(a.endereco_numero || '')}">`
- **Adicionar** Complemento: `<input type="text" id="ef-complemento" value="${esc(a.endereco_complemento || '')}">`
- **Adicionar** Bairro: `<input type="text" id="ef-bairro" value="${esc(a.bairro || '')}">`

#### Seção Programa (expandir):
- Nível — **manter** (select com nivelMap)
- Turma HM — **manter** (select populado com turmas)
- **Adicionar** Espaço de Instrução:
```html
<select id="ef-espaco">
  <option value="">Não definido</option>
  <option value="holding_masters" ${a.espaco_instrucao === 'holding_masters' ? 'selected' : ''}>Holding Masters</option>
  <option value="aurum" ${a.espaco_instrucao === 'aurum' ? 'selected' : ''}>Mentoria Aurum</option>
  <option value="coach_platina" ${a.espaco_instrucao === 'coach_platina' ? 'selected' : ''}>Coach Platina</option>
  <option value="mastermind" ${a.espaco_instrucao === 'mastermind' ? 'selected' : ''}>Mastermind</option>
</select>
```

**IMPORTANTE**: O campo `espaco_instrucao` existe em `thb_placas_solicitacoes` mas **NÃO** em `thb_alunos`. Para que isso funcione, é preciso:
1. **Verificar** se a coluna já existe em `thb_alunos` antes de salvar. Se não existir, o save vai falhar.
2. **Alternativa**: salvar o valor na tabela `thb_placas_solicitacoes` onde o aluno tem registro, OU adicionar a coluna no banco (tarefa do agente SQL, não deste plano).
3. **Para o frontend**: renderizar o campo no formulário de qualquer forma. Se o save falhar por coluna inexistente, mostrar toast de aviso. O dado virá do `fn_aluno_360_safe` que pode ser expandido pelo agente SQL.

**NOTA PARA O IMPLEMENTADOR**: se `a.espaco_instrucao` vier como `undefined` na RPC, significa que a view `vw_aluno_360` ainda não inclui esse campo. Nesse caso, mostrar "Não definido" e desabilitar o save desse campo específico até que o agente SQL atualize a view.

#### Seção Tipo de Cliente:
Exibir como info (read-only), derivado de `tem_ht` + `tem_hm`. Não é editável pois vem das compras.

### 3.2 Expandir `saveAlunoEdit()` (app.js:627-660)

Adicionar os novos campos ao objeto `fields`:

```js
// Adicionar estes campos ao objeto fields existente:
link_facebook: document.getElementById('ef-facebook')?.value?.trim() || null,
cep: document.getElementById('ef-cep')?.value?.trim() || null,
endereco_logradouro: document.getElementById('ef-logradouro')?.value?.trim() || null,
endereco_numero: document.getElementById('ef-numero')?.value?.trim() || null,
endereco_complemento: document.getElementById('ef-complemento')?.value?.trim() || null,
bairro: document.getElementById('ef-bairro')?.value?.trim() || null,
```

O `espaco_instrucao` só deve ser incluído se a coluna existir no banco. Para segurança, envolver em try/catch separado ou simplesmente incluir e tratar o erro.

---

## Tarefa 4 — Melhorias de UX/UI (base.css + drawer.css + app.js)

### 4.1 Stat card de Depoimentos

No `index.php`, adicionar um 5º stat card após o de "Com Placa" (linha 45):

```html
<div class="cc-stat orange" style="--stripe: var(--cc-orange)"><div class="cc-stat-label">Depoimentos</div><div class="cc-stat-value" id="cc-stat-depoimento">—</div></div>
```

Ajustar o grid para 5 colunas no CSS (`base.css` linha 38):
```css
.cc-stats-grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; }
```

Atualizar `renderStats()` no app.js (após linha 410):
```js
document.getElementById('cc-stat-depoimento').textContent = all.filter(a => a.tem_depoimento).length;
```

### 4.2 Linguagem simplificada

No drawer, usar labels em linguagem simples:
- "nivel_resultado" → "Nível de Resultado"
- "espaco_instrucao" → "Espaço de Instrução"
- "turma_codigo" → "Turma"
- "placa_step" → "Etapa da Placa"
- "tem_ht" → exibir como pill "HT" ou "Holding Total"
- "ativacao_ht_status" → "Status HT"
- Datas: sempre formatadas com `fmtData()` (dd/mm/aaaa)

### 4.3 Responsividade dos stats

No CSS, ajustar breakpoints:
```css
@media (max-width: 1280px) { .cc-stats-grid { grid-template-columns: repeat(3, 1fr); } }
@media (max-width: 768px) { .cc-stats-grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 480px) { .cc-stats-grid { grid-template-columns: 1fr; } }
```

---

## Tarefa 5 — Coluna "Tipo" na Tabela (app.js + table.css)

### 5.1 Adicionar coluna "Tipo" na tabela

No `index.php`, adicionar header na tabela (após a coluna "Jornada", linha 88):
```html
<th>Tipo</th>
```

Atualizar colspan dos empty states de 5 → 6.

No `renderTable()` do app.js, adicionar a célula na row:
```js
// Após a célula de Jornada (pills), adicionar:
const tipo = (a.tem_ht && a.tem_hm) ? 'HM+HT'
  : a.tem_ht ? 'HT'
  : a.tem_hm ? 'HM'
  : '—';
const tipoCls = (a.tem_ht && a.tem_hm) ? 'green'
  : a.tem_ht ? 'blue'
  : a.tem_hm ? 'yellow'
  : '';

// Célula: <td><span class="cc-pill ${tipoCls}">${tipo}</span></td>
```

---

## Ordem de Execução

1. **Tarefa 1** — Filtros (menor risco, maior impacto visual)
2. **Tarefa 4.1** — Stat card de depoimentos (simples)
3. **Tarefa 5** — Coluna Tipo na tabela (simples)
4. **Tarefa 2** — Drawer expandido com jornada em cadeia (mais complexo)
5. **Tarefa 3** — Formulário de edição expandido (depende do drawer)
6. **Tarefa 4.2/4.3** — Polish final

---

## Dados disponíveis na RPC `fn_aluno_360_safe`

Campos que a view `vw_aluno_360` retorna (e que estão disponíveis no objeto `a` dentro do JS):

```
id, nome, email, documento, telefone, telefone_e164, profissao, link_facebook,
cep, endereco_logradouro, endereco_numero, endereco_complemento, bairro, cidade, estado, pais,
turma_id, turma_codigo, turma_tipo, turma_aurum_id, plano, nivel_resultado, placa_aurum,
eh_socio, socio_de_aluno_id, socio_de_nome, status_acesso,
comprador_id, hotmart_ucode,
tem_ht, data_compra_ht, ativacao_ht_status,
tem_hm, data_compra_hm, ativacao_hm_status, hm_plano,
tem_placa, placa_step, placa_encerrada, placa_protocolo,
tem_depoimento, total_depoimentos,
fonte, data_compra_importada, importado_em, atualizado_em
```

**NOTA**: `espaco_instrucao` NÃO está na view atual. Se precisar, o agente SQL deve adicioná-lo.

---

## Valores de Enum Importantes

### `nivel_resultado`
`iniciante | pessoal | em_formacao | profissional | ouro | platina | diamante | diamante_vermelho`

### `espaco_instrucao` (em thb_placas_solicitacoes)
`holding_masters | aurum | coach_platina | mastermind`

### Tipo de Cliente (derivado, não é coluna)
Calculado a partir de `tem_ht` e `tem_hm` (booleans da view)

---

## Checklist Final

- [ ] Filtros rápidos funcionam (pills clicáveis alternam corretamente)
- [ ] Filtro de turma popula automaticamente
- [ ] Filtro de tipo HM/HT funciona
- [ ] Drawer mostra todos os dados pessoais completos
- [ ] Drawer mostra espaço de instrução (se disponível na view)
- [ ] Jornada em cadeia: cards expandíveis com detalhes
- [ ] Links "Abrir na feature" levam para a URL correta
- [ ] Formulário de edição tem todos os campos novos
- [ ] Save funciona para todos os campos (testar com um aluno)
- [ ] Stat de depoimentos aparece
- [ ] Coluna Tipo aparece na tabela
- [ ] Responsivo funciona em mobile
- [ ] Não quebrou realtime (canais continuam funcionando)
- [ ] Não re-declarou nada de auth.js/config.js
- [ ] Toast aparece após salvar
