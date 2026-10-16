# Hotmart na pessoa única: setor pelo produto e linha do tempo sem duplicata

Terminal Hotmart (back-end-sr), 16/10/2026, branch `victor-hotmart-setor`. **Situação: APLICADO em produção em 16/10/2026, entre 11:31 e 11:33 UTC**, pelo Victor (sessão principal), depois da 2ª rodada do pentest (APROVADO). Ordem 230000 → 230100 → 230200, com a carga parada na 230200; as três versões estão em `supabase_migrations.schema_migrations`. Detalhe da aplicação na seção "Aplicação" abaixo.

## O que foi feito e por quê
- **Setor pelo produto, não pela conta** (`20261016230100`). SV, Croqui e SV com a Elaine vendidos na conta academy são escritório. A função nova `pessoas.hotmart_setor(produto_id)` devolve `'escritorio'` para `fin.produtos.familia` `ESCRITORIO` e `ESCRITORIO_SOLUCOES`; qualquer outro devolve `null` (não afirma "educação"). A carga (`pessoas.carga_fin_hotmart`) e o webhook (`crm.hotmart_processar`) gravam `detalhe.setor`.
- **Sem evento de educação em venda de escritório**: a carga anula o `evento_id` quando o setor do evento do financeiro não é escritório. A conta escritório não passa mais por `fin.trajetoria_nucleo`.
- **Idempotência nos dois sentidos**: o passo 3 do webhook só insere se não existe linha do mesmo `(ref_id, tipo)` (com lock de aviso por transação e tipo); a carga já reivindicava a linha do webhook. Causa dos 13 grupos: duas ingestões (`webhook` e `sync`, chaves diferentes em `crm.hotmart_processado`) e o passo 3 sempre inserindo.
- **Índice parcial** `eventos_hotmart_ref_idx` (`20261016230000`): a reivindicação passa de Parallel Seq Scan (398 ms por transação) para Index Scan (0,039 ms).
- **Limpeza do que já está gravado** (`20261016230200`): remove 13 duplicatas, tira o evento de educação de 2 vendas de escritório e marca `setor` em 572 linhas. Backup em `arquivo.pessoas__eventos__20261016` (prazo 2027-01-14) com as linhas dos três passos (`duplicado_removido`, `evento_educacao_em_escritorio`, `setor_marcado`). A guarda aborta se a premissa mudar (mais de 13 grupos, grupo com pessoas diferentes ou mais de 2 linhas, alvo do passo 2 diferente de 2, índice inválido) e a pós-condição desfaz tudo se o backup não tiver 13 + 2 + as marcadas. A reversão volta o setor só das linhas `setor_marcado`, por id.
- Cada migration tem `.explain.md` (5 perguntas), reversão e o ensaio `20261016230100_ensaio.sql` cobre as três e a carga.

## Decisões e pontos a confirmar
- **DECIDIDO pelo Victor em 16/10/2026: `3595938 Holding Familiar` é do escritório** (hoje família `OUTROS`, `sincroniza = false`, 44 transações: aprovações de 12/2023 a 12/2024, último pedido em 01/05/2025). A migration `20261016233000_fin_classificar_holding_familiar_escritorio.sql` foi **APLICADA em 16/10/2026 12:58 UTC** (antes escrita e ensaiada com rollback; 1.960 linhas com setor escritório, 0 duplicados): muda a família para `ESCRITORIO` (sem mexer em `sincroniza`), marca `detalhe.setor = 'escritorio'` nas 44 linhas da linha do tempo e anula o `evento_id` das 14 que estavam presas a evento de educação (backup em `arquivo`). Medição de impacto, trade-off do `evento_id` e comando de aplicação em `infra/supabase/migrations/20261016233000.explain.md`. Atenção: nenhuma tela do Financeiro lista a família `ESCRITORIO`, então R$ 405.410,08 de valor da oferta (23 vendas) saem da aba "Outros produtos" no histórico completo e não aparecem em outra aba (na janela padrão de 90 dias o efeito é zero).
- **Reclassificado em 16/10/2026 13:20 UTC (decisão do Victor):** `1537308 Croqui Estrutural para Holding Familiar` virou `ESCRITORIO` pela migration `20261016235000` (0 transações, então nada a marcar em `pessoas.eventos`; vale para venda futura). Agora são 5 produtos em ESCRITORIO.
- `fin.identidade.calculado_em` parado em 11/10 **não é defeito**: a reescrita é diferencial e só avança quando a `pessoa_chave` muda; o cron de hora em hora roda (71 execuções ok desde 13/10).

## Como testar
Rodar `20261016230100_ensaio.sql` (termina em rollback). Conferir: grupos duplicados 13 → 0, escritório com evento de educação 2 → 0, reversão volta aos números de antes, 3 chamadas do webhook para a mesma transação geram 2 linhas (checkout e reembolso). Depois de aplicar: `select ref_id, tipo, count(*) from pessoas.eventos where ref_tipo='hotmart.transacao' group by 1,2 having count(*)>1` deve voltar vazio.

## Revisão do pentest (16/10/2026, reprovou `fea176f`; correção no commit seguinte)
Corrigidos: reversão só por id (achado 1), guarda de premissa e pós-condição (achado 2), guarda de índice com `indisvalid and indisready` na 230100 e 230200 (achado 3). Ensaio refeito com a reversão provada: linha de webhook gravada depois da 230200 mantém o setor depois da reversão.

## Pendências registradas
- **Corrida webhook x carga e lock de aviso preso (pentest 4 e 5): NÃO feito.** Conserto da classe: migration separada (230250), índice único parcial `(ref_id, tipo) where ref_tipo = 'hotmart.transacao'` criado `CONCURRENTLY` **depois** da 230200, mais `on conflict do nothing` no webhook e na carga (o que dispensa o lock). Não entrou neste commit porque mexe de novo nas duas funções, falha com índice INVALID se uma duplicata nascer entre a limpeza e a criação, e pede ensaio próprio. Até lá a corrida é rara e detectável com a query de duplicados acima.
- **Prazo do backup**: `arquivo.pessoas__eventos__20261016` vence em 2027-01-14 e não há rotina que apague; precisa de card (dono Victor).
- **Mudança de comportamento, DECIDIDA pelo Victor em 16/10/2026:** o webhook agora grava uma linha por transação e tipo. `compra_em_aberto` seguido de `expirada` na mesma transação (os dois viram `checkout`) passa a ser **uma linha só** (a primeira); antes eram duas. O Victor aprovou: a compra "deixa de ficar aberta".

## Aplicação (16/10/2026)
- **230000** (11:31:39 a 11:31:42 UTC): `create index concurrently` numa chamada só, fora de transação. `indisvalid` e `indisready` verdadeiros, 320 kB.
- **230100** (11:32:08 a 11:32:10): aplicada em transação única. Conferido: `pessoas.hotmart_setor('1663254')` (SV vendida na conta academy) = `escritorio`; `pessoas.hotmart_setor('446345')` = null.
- **230200** (11:32:21 a 11:32:24): grupos repetidos 13 → 0; backup com `duplicado_removido` 13, `evento_educacao_em_escritorio` 2, `setor_marcado` 572.
- **Carga do escritório** (execução 72): fechou `ok`, 546 transações lidas (7 novas, 539 já ligadas).
- **Carga da academy** (execução 71): retomada em lotes de 500 com o freio de RAM (150 MB) ligado, de 11:33 a 11:50 UTC; fechou `ok` com 57.424 lidas (1.161 novas, 56.263 casadas), lotes de 0,7 a 6 s, sem travar o banco.
- **Resultado:** academy 57.424 de 57.424 transações ligadas à pessoa única e escritório 546 de 546; 1.916 linhas com `setor = escritorio` (SV, Croqui e SV com a Elaine vendidas na academy, mais toda a conta escritório); query de duplicados vazia.

## O que falta
- ~~Aplicar a `20261016233000`~~ aplicada em 16/10/2026. Fica em aberto: a família `ESCRITORIO` não tem aba no Financeiro (a aba "Outros produtos" perdeu R$ 405.410,08 do histórico completo); decidir se o front ganha a aba.
- `fin.identidade` → `pessoas.pessoas` (coluna ou tabela de ligação `fin.identidade_pessoa`): não feito; próximo passo é a migration `230300` do plano (18.580 ligadas, 4.211 sem pessoa, 388 com várias pessoas, medidos em 16/10; CPF não casa pessoa).
- `evento_id` nulo nas linhas do webhook (6.945 de 7.543 linhas Hotmart): a carga preenche ao reivindicar; ligar em massa é passo seguinte.
