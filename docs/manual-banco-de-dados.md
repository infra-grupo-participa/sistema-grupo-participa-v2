# Manual de operação no banco — Grupo Participa

> Como a gente mexe em dado no Supabase/Postgres: o ritual, as regras e os perigos que já custaram produção, dinheiro ou dado pessoal. Cada regra aqui nasceu de um incidente real (o número entre parênteses é a prova).
> Versão de 05/10/2026. Fonte viva: vault Obsidian `00 Painel/Livro - Back-end.md`, `Livro - Seguranca.md` e `~/.claude/PROTOCOLO-SUSTENTABILIDADE.md`.

---

## 0. Por que isto existe

Em **19/08/2026 o Postgres travou em produção**. Nenhuma causa era falta de máquina: eram features empilhadas sem validação. Uma função gastava **1.085 ms varrendo 71.728 linhas** para achar 1 e-mail porque a query fazia `btrim(lower(email))` e o índice era `lower(btrim(email))`. Um job rodava 72×/dia inserindo zero linhas. Nada disso se resolve com upgrade — só com código correto.

**Princípios (o jeito Marcio):**
- **Número medido vence opinião.** Medir antes de afirmar; contar quantos passam antes de filtrar ou travar.
- **Verde não é prova; HTTP 200 não é sucesso.** Prova é o efeito real observado no banco.
- **O mínimo que resolve, sempre reversível:** flag, alias, arquivar. **Nunca apagar.**
- **Consertar a classe, não a ocorrência:** achar TODOS os leitores/escritores pelo nome da coluna ou do símbolo.
- **"Possivelmente" é premissa inventada** → pergunta para o Marcio antes de seguir.

---

## 1. O ritual (ordem de operação de qualquer mudança no banco)

1. **Já existe? Já foi removido por decisão?** Procurar no vault e no `CLAUDE.md` do projeto. (Feature de agendamento do GPS foi removida em 10/08 e quase reconstruída pela 3ª vez.)
2. **Ler o estado VIVO, não o repositório.** `pg_get_functiondef`, `pg_get_viewdef`, `pg_get_constraintdef`, `pg_indexes`. O repo já esteve na migration 0166 com produção em 0178; Edge Function no repo já esteve 5 semanas atrás da publicada.
3. **Responder as 5 perguntas** (seção 2). "Não sei" = investigar, não codar.
4. **Contar a massa** antes de decidir: quantas linhas a mudança atinge, quantos passam no filtro.
5. **Escrever a migration versionada** (seção 3), com **guarda de premissa** que aborta se a base não estiver como esperado.
6. **Ensaiar em transação desfeita** (`begin … rollback`) com `lock_timeout` e `statement_timeout` (seção 4).
7. **`explain (analyze, buffers)` colado** — sem plano medido, a mudança não passa.
8. **Aplicar**, depois **provar o efeito no dado** (não "rodou sem erro").
9. **Conferir permissões** da coisa nova (seção 6).
10. **Registrar**: migration no repo com a versão que o banco gravou, nota no vault, card no ClickUp.

---

## 2. As 5 perguntas (responder ANTES de escrever)

| Pergunta | O que verificar | Sinal de morte |
|---|---|---|
| **Escala** — e com 10× mais linhas? | tem `limit`? custo por item novo ou pela base inteira? | funciona com 20 mil, morre com 200 mil |
| **Índice** — o planner VAI usar? | `explain analyze` mostra `Index Scan` | `Rows Removed by Filter` alto |
| **Frequência** — quantas vezes/dia? | cron no ritmo em que o dado muda de verdade | job 72×/dia que insere zero |
| **Repetição** — N telas = N queries? | coalescer; filtro no cliente não alivia o banco | 4 componentes, 4 queries iguais no mesmo segundo |
| **Reversão** — como desligo? | kill-switch no banco, caminho de volta | só desliga com deploy |

---

## 3. Migrations e schema

- **Migration versionada SEMPRE, e ANTES**, mesmo com urgência. SQL aplicado direto (MCP/painel) volta para o repositório no mesmo dia.
- **Antes de numerar:** `ls supabase/migrations | tail` — já houve número duplicado.
- **Migration aplicada não se edita.** Coluna nova = migration nova.
- O `apply_migration` do MCP **grava a versão pelo relógio**, não pelo nome do arquivo: depois de aplicar, ler `supabase_migrations.schema_migrations` e renomear o arquivo do repo para a versão gravada (senão `db push` reaplica).
- **Mudou a assinatura de função? `drop function` + `create`.** `create or replace` com parâmetro diferente cria **sobrecarga**: a versão antiga continua viva (e já ficou chamável por anônimo).
- **Recriar função parte do corpo vigente** (`pg_get_functiondef`), nunca de migration antiga.
- `create or replace view` que muda tipo força DROP em cascata e **recria sem GRANT**.
- **Nunca envelopar uma view em subselect** para acrescentar coluna: vira barreira de otimização. Isso já derrubou Database, Auth e Storage juntos (18/08).
- **CHECK não aceita subquery** (erro 0A000) — passa no build, no pentest e na revisão; só falha ao aplicar. Encapsular em função `IMMUTABLE`.
- **Antes de reescrever um CHECK:** `pg_get_constraintdef` filtrando por `conname`. Reescrever de memória apaga valor permitido em silêncio (2 em 7 conferências pegaram erro real).
- **Coluna nova com `default`** pode desfazer regra no próximo INSERT. Conferir `column_default` e provar a DATA resultante, não só o valor.
- **Schema novo** só aparece na API depois de entrar em `pgrst.db_schemas` + `notify pgrst`. O painel "Exposed schemas" **sobrescreve a lista inteira**.
- `RETURNS TABLE` com nome igual a uma coluna quebra (ambiguous).
- Horário de evento: `date` + `time`, nunca `timestamptz` (19:30 viraria 16:30). Formatar com fuso explícito.
- Coluna contadora: conferir o limite do tipo (`int4`) contra a taxa real de crescimento.
- Supabase **recusa `SET app.x` na definição de função** (42501): usar `set_config` em runtime.
- Migration com guarda de premissa tem de **tolerar o estado que a migration seguinte deixa**: ensaiar a SEQUÊNCIA 2×, não cada uma sozinha.
- DDL grande pelo MCP pode dar "Invalid or expired requestState": dividir em partes — e o `revoke` vai **na mesma chamada** do `create function`.
- No Windows, mandar SQL pela Management API via pipe grava acento quebrado: abrir o arquivo com `encoding="utf-8"` e conferir depois.

---

## 4. Ensaio e prova (como testar sem quebrar produção)

- **Ensaio em `begin … rollback`**, com `set local lock_timeout` e `set local statement_timeout`. Ensaio longo **segura lock em produção**: o MCP estourou 60 s e travou o cron de sincronização por 28 s.
- Chamadas ao MCP abaixo de ~25 s; ensaio que chama função cara 30× não cabe — dividir.
- **`explain (analyze)` em UPDATE/DELETE/INSERT executa de verdade.** Sempre dentro de transação com rollback (já gravou valor em produção).
- `explain (analyze)` **duas vezes**: a primeira mede cache frio (56 ms × 7,5 ms).
- **Medir a função/RPC inteira que a tela chama**, não o SELECT solto (0,66 ms isolado × 2,7 ms real; 0,7 s o corpo × 15,5 s a função).
- Tabela que ainda não existe: simular com `generate_series` em `begin … rollback`, `analyze`, `explain`.
- **Provar RLS com `set local role authenticated`/`anon` + JWT real.** Como `postgres` ou `service_role` o bug fica escondido.
- **Guarda de contagem exata na migration** pega base que mudou (esperava 15 backups, havia 18 — abortou antes de mover nada).
- Ensaio de trigger roda **a função que escreve de verdade** (o cron real), não um UPDATE à mão.
- Antes de dizer "não existe": `information_schema.tables` **sem filtro de schema**. O mesmo projeto pode ter dois sistemas (`public` e `portal`).
- Antes de dizer "o job não roda": conferir `cron.job_run_details`.
- **Risco tem 2 metades: mecanismo e massa.** Ler config e anunciar desastre sem contar as linhas afetadas é alarme falso.

---

## 5. Performance e índice

- **Índice funcional exige a MESMA expressão, caractere a caractere.** Este banco tem 3 convenções vivas:
  - `lower(btrim(email))` — `controle.lead_active`, `controle.lead`, `workbook.*`, `public.compradores`
  - `btrim(lower(email))` — `central.alunos`
  - `lower(trim(both from email))` — `public.thb_alunos`, `cs.hm_socios`, `public.thb_placas_solicitacoes`
  - Sempre: `select indexdef from pg_indexes where tablename='<tabela>'` e copiar a expressão.
- **Melhor ainda:** normalizar o **valor buscado** numa variável e comparar com a coluna crua (0,530 → 0,083 ms).
- Índice parcial só é usado se a query **repetir o predicado literal**.
- **Medir antes de criar índice.** Em tabela pequena Seq Scan vence (índice já deixou mais lento: 0,686 × 0,809 ms).
- Sem falta de índice? **Reescrever a forma da query** (`left join lateral`): 93 → 0,67 ms.
- View cara chamada milhares de vezes/dia → **materialized view** com refresh (245 → 1,3 ms).
- Ingestão que reescreve tudo precisa de **trigger que ignora linha idêntica** (skip no-op): eram 10,2 milhões de updates em 7 mil linhas.
- Subconsulta sobre a view no WHERE de função SQL reavalia linha a linha: usar `= any(array(select …))`.
- Em guarda com OR, a condição mais barata vem primeiro.
- **Egress = frequência de leitura**, não tamanho. Polling de uma aba aberta estoura o teto (329 MB/h). Tabela sem assinante sai da publication do Realtime. O teto é da **organização** inteira.
- `select('*')` + join em JavaScript = 42 mil linhas por clique. Trazer só o necessário, agregado no banco.

---

## 6. Segurança no banco (LGPD é aqui, não na tela)

- **Toda função nasce executável por PUBLIC.** `revoke execute … from public, anon` e conferir `proacl` em toda função nova ou recriada.
- **`SECURITY DEFINER` em schema exposto sem guarda = vazamento.** Em 28/09 o anônimo lia 1.890 alunos com CPF por uma função assim. Guarda no corpo + revoke.
- Guarda de `SECURITY DEFINER` **falha aberta com NULL**: `coalesce(…, false)` em toda checagem.
- **Guarda na função não vale se a VIEW que a embrulha tem grant direto** — fechar a view também.
- View com `security_invoker = false` **ignora a RLS da tabela**.
- `GRANT SELECT` não revoga a escrita padrão: revogar insert/update/delete explicitamente.
- RLS ligada sem policy bloqueia até o service_role: policy e GRANT na mesma migration.
- **Policy não consulta a própria tabela** (recursão 42P17 — derrubou o onboarding do GPS). Comparar antigo × novo por trigger BEFORE UPDATE.
- Filtro de visibilidade mora **na policy**, não só na RPC (senão vaza pela API direta).
- Identidade resolvida numa **função única** usada por todas as policies; guarda de papel própria (`gps.eh_equipe()`), nunca mexer na genérica (`gp_is_admin()` é lida por 50 tabelas).
- Campo sensível sai do `returns table` da RPC, não só da tela. RPC pública pode devolver mais do que a tela usa — reconferir o contrato.
- Varrer exposição **por privilégio** (`has_table_privilege('anon'|'authenticated', …)`), não por nome. Já apareceu cópia de `auth.users` com hash de senha legível por qualquer login, e backup com 1.035 contatos aberto a anônimo.
- Hash sem sal de CPF volta ao CPF: id exposto = HMAC com segredo do Vault.
- **Nunca** escrever segredo, token ou dado pessoal em migration, nota, card ou chat.

---

## 7. Lógica e dado (onde o número mente)

- **NULL é tri-valorado:** `not(a or b)` com NULL vira no-op. `coalesce` em cada predicado.
- **"É zero" ≠ "não sei".** Busca que falha devolve erro, não lista vazia nem KPI zerado.
- **`coalesce(liquido, bruto)` transforma buraco em número plausível.** Faltou dado → NULL e aviso. Função de derivação precisa de ramo para toda combinação, ou devolve null (36 cards viraram "quitados com R$ 0").
- **Fato monetário vence rótulo:** total vem de valor pago e saldo, nunca de flag de status (85 "quitados" com R$ 231 mil de saldo).
- **Join 1:N infla contagem:** agregar com `distinct`/`bool_or` antes de contar.
- **Casar pessoa por e-mail**, nunca por nome ou CPF. Equipe = domínio `@advmais.com`.
- **Chave de casamento sai da função que GRAVA a tabela** (ex.: `controle.fone_key()`), nunca de suposição de formato.
- Ler-modificar-escrever: **abortar se a leitura falhar**; jsonb se lê inteiro antes de reescrever.
- **DELETE em lote valida o casamento antes.** Ingestão que apaga "o que sumiu" precisa de trava (já zerou 59 linhas quando o mapa de colunas quebrou).
- Webhook fora de ordem: upsert condicional pelo timestamp (`greatest`).
- Cache agregado é invalidado em **todos** os caminhos de escrita.
- Trocar valor fixo por consulta dinâmica exige provar que o conjunto é o mesmo.
- Trigger de histórico: `AFTER UPDATE … WHEN (old.x is distinct from new.x)` **sem `OF`** (o `OF` não vê coluna trocada por trigger BEFORE). Colunas rastreadas saem do **escritor real**.
- Sem JWT, `session_user` = `postgres` tanto para cron quanto para SQL à mão: não rotular como "rotina".
- **Filtro de elegibilidade: CONTAR antes de recomendar** (filtro aprovado dava 0 alunos; tela que recusa 100% carrega sem erro).

---

## 8. Domínio — armadilhas conhecidas

- **`thb_alunos` e `compradores` são os hubs centrais**; preservar a ponte `comprador_id`.
- **Turma não se deduz por data de compra.** Pessoa de turma antiga nunca vai para turma nova: `coalesce(turma_origem, turma_do_aluno, turma_atual)`. Turma `atual` sem `sale_start_at` = cadastro errado.
- **Oferta nova de pagamento é catalogada no MESMO DIA** (`hm_product_catalog` + UI). Oferta fora do catálogo = webhook chega e não vira pagamento (Acelera inteiro ficou fora: 436 transações; 4ª recorrência).
- **Card é por pessoa × produto:** função que resolve só por `comprador_id` mistura o dinheiro de HM e Aurum.
- **Separar por conta/tenant = fechar a classe:** filtrar só o caixa deixou 44 leitores somando a 2ª conta Hotmart. Listar leitores vivos em `pg_proc`/`pg_views`.
- **Hotmart:** OVERDUE é por tentativa de cobrança, não por parcela; uma tentativa pode cobrar N meses; cada parcela é uma transação. Dívida = e-mail × produto × oferta × recorrência, uma vez.
- "Tem atraso" ≠ "está em risco": risco = parcela aberta com recorrência maior que a última paga, ou plano parado há 45+ dias.
- Campo "quem vendeu" pode ser carimbo de trigger: reconstruir pela linha do tempo.
- `public.perfis` é tabela da **equipe**; signup de aluno não cria linha lá.
- **Funil/evento/trajetória nunca à mão:** evento novo = `fin.eventos` + `fin.evento_ofertas` + `fin.acoes.evento_id`, registrado automático.
- **"Zero chamadores" no banco não prova código morto:** outro sistema chama por SQL direto de outro repo.
- Banco compartilhado entre sistemas: mudar um lado exige mudar o outro.

---

## 9. Integrações disparadas pelo banco

- **`net.http_post` é assíncrono** e `net._http_response` expira em ~6 h (e o id é reciclado). Carimbar "enviado" logo após o post marca como avisado quem levou erro: guardar o resultado numa coluna própria e reconciliar.
- **Resend: 10 req/s** — lote sem pausa devolve 429 na maioria.
- Cron de 0,05 s que só chama `http_post` não é barato: o custo vem depois.
- HTTP 200 não é sucesso: comparar pedido × resposta.
- PATCH parcial em API externa pode resetar o campo ausente: diff campo a campo.

---

## 10. Reversibilidade (o padrão validado)

- **Kill-switch no banco**, não no deploy (desliga em ~10 s).
- **Restaurar backup em projeto NOVO**, nunca por cima da produção. Primeiro passo: desligar os crons do restaurado.
- Função admin que apaga dado de terceiros grava **retrato completo antes**, com restauração e expurgo por prazo (180 dias).
- Unificar cadastro com **alias**, não merge destrutivo. **Inativar** em vez de excluir quando há FK.
- Voltar para NULL o valor derivável errado é mais seguro que cravar o "certo".
- Função que substitui outra liga em **2 etapas**: a nova ao lado da antiga até uma execução real provar a nova.
- Trigger sobre insert de outra equipe **preserva a gravação principal** mesmo se a lógica extra falhar.
- Contraprova por mutação: restaurar por **cópia + md5**, nunca `git checkout --` (apaga trabalho não commitado).

---

## 11. Checklist de bolso (antes de aplicar)

- [ ] Li a definição VIVA (função, view, CHECK, índice) — não o repo
- [ ] Contei a massa afetada e quem lê/escreve a coluna (classe inteira)
- [ ] 5 perguntas respondidas
- [ ] Migration versionada, número conferido, guarda de premissa que aborta
- [ ] Ensaio em `begin … rollback` com `lock_timeout`/`statement_timeout`
- [ ] `explain (analyze, buffers)` da RPC inteira, rodado 2×, colado
- [ ] Função nova/recriada: `revoke` de PUBLIC/anon, `proacl` conferido, guarda com `coalesce`
- [ ] RLS provada com `set local role` + JWT real
- [ ] Efeito provado no dado depois de aplicar
- [ ] Arquivo do repo renomeado para a versão gravada em `schema_migrations`
- [ ] Kill-switch / caminho de volta definido
- [ ] Nota no vault + card no ClickUp

**Dúvida de critério de negócio não se inventa: pergunta para o Marcio.**
