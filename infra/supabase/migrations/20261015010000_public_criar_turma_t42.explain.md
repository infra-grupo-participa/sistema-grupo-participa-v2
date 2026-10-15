# 20261015010000 · public: criar a turma T42

**O quê:** insere a T42 em `public.thb_turmas` (`codigo 'T42'`, `tipo 'thb'`, `atual = false`), igual à função da Central
`public.fn_turma_criar`. Liga ao `turma_id` da T42 só os eventos e relações da pessoa única vindos da planilha de ativação
com turma "T42" e sem turma (aditivo).

**Por quê:** pedido do Victor em 14/10/2026 ("t42 tem que ter... garante que vão entrar"). Formato e alcance confirmados
pelo Maestro no mesmo dia.

**O que NÃO faz:**
- não muda a turma atual (continua T41);
- não preenche `sale_start_at` nem `chave` (nenhuma fonte dá a data de início da T42; pergunta aberta ao Victor);
- não toca em `public.thb_alunos`: dos 25 alunos da aba T42, 10 estão com turma T41, 14 em turmas antigas e 1 sem turma; dos
  13 sócios, 8 sem turma, 1 sócio na T30 e 4 fora do `thb_alunos`. Mudar turma na Central é decisão do Victor.

**Escala:** 1 linha em `thb_turmas`; até 38 eventos e 9 relações. **Índice:** `thb_turmas_codigo_key` (único) já cobre a
busca; `eventos_fonte_unico` cobre os eventos. **Frequência:** uma vez. **Repetição:** idempotente (`where not exists`,
`turma_id is null`). **Reversão:** `_reversao.sql` (desliga da linha do tempo; apaga a linha só se nada usar a T42).

**Aplicação:** fora de live, entre scripts de carga (nunca junto com outra escrita), depois do ensaio.

**Aviso ao João (dono da Central):** a T42 aparece no seletor de turmas da tela de acesso HM, sem ser a atual.
