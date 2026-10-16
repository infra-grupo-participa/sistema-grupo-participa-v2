# Hotmart na pessoa única: setor pelo produto e linha do tempo sem duplicata

Terminal Hotmart (back-end-sr), 16/10/2026, branch `victor-hotmart-setor`. **Situação: escrito e ensaiado (transação desfeita); NADA aplicado em produção.** Falta o pentester (escreve em `pessoas`, reescreve `crm.hotmart_processar`) e o aplicar do Victor.

## O que foi feito e por quê
- **Setor pelo produto, não pela conta** (`20261016230100`). SV, Croqui e SV com a Elaine vendidos na conta academy são escritório. A função nova `pessoas.hotmart_setor(produto_id)` devolve `'escritorio'` para `fin.produtos.familia` `ESCRITORIO` e `ESCRITORIO_SOLUCOES`; qualquer outro devolve `null` (não afirma "educação"). A carga (`pessoas.carga_fin_hotmart`) e o webhook (`crm.hotmart_processar`) gravam `detalhe.setor`.
- **Sem evento de educação em venda de escritório**: a carga anula o `evento_id` quando o setor do evento do financeiro não é escritório. A conta escritório não passa mais por `fin.trajetoria_nucleo`.
- **Idempotência nos dois sentidos**: o passo 3 do webhook só insere se não existe linha do mesmo `(ref_id, tipo)` (com lock de aviso por transação e tipo); a carga já reivindicava a linha do webhook. Causa dos 13 grupos: duas ingestões (`webhook` e `sync`, chaves diferentes em `crm.hotmart_processado`) e o passo 3 sempre inserindo.
- **Índice parcial** `eventos_hotmart_ref_idx` (`20261016230000`): a reivindicação passa de Parallel Seq Scan (398 ms por transação) para Index Scan (0,039 ms).
- **Limpeza do que já está gravado** (`20261016230200`): remove 13 duplicatas, tira o evento de educação de 2 vendas de escritório e marca `setor` em 578 linhas (572 depois das duplicatas). Backup em `arquivo.pessoas__eventos__20261016` (prazo 2027-01-14).
- Cada migration tem `.explain.md` (5 perguntas), reversão e o ensaio `20261016230100_ensaio.sql` cobre as três e a carga.

## Decisões e pontos a confirmar
- **A confirmar com o Victor (NÃO reclassificado):** `3595938 Holding Familiar` (família `OUTROS`, 44 transações de 12/2023 a 05/2025) e `1537308 Croqui Estrutural para Holding Familiar` (família `OUTROS`, 0 transações). Se forem escritório: mudar `fin.produtos.familia` (ou a regra `e_comprador_escritorio`) e repetir o passo 3 da 230200.
- `fin.identidade.calculado_em` parado em 11/10 **não é defeito**: a reescrita é diferencial e só avança quando a `pessoa_chave` muda; o cron de hora em hora roda (71 execuções ok desde 13/10).

## Como testar
Rodar `20261016230100_ensaio.sql` (termina em rollback). Conferir: grupos duplicados 13 → 0, escritório com evento de educação 2 → 0, reversão volta aos números de antes, 3 chamadas do webhook para a mesma transação geram 2 linhas (checkout e reembolso). Depois de aplicar: `select ref_id, tipo, count(*) from pessoas.eventos where ref_tipo='hotmart.transacao' group by 1,2 having count(*)>1` deve voltar vazio.

## O que falta
- `fin.identidade` → `pessoas.pessoas` (coluna ou tabela de ligação `fin.identidade_pessoa`): não feito; próximo passo é a migration `230300` do plano (18.580 ligadas, 4.211 sem pessoa, 388 com várias pessoas, medidos em 16/10; CPF não casa pessoa).
- `evento_id` nulo nas linhas do webhook (6.945 de 7.543 linhas Hotmart): a carga preenche ao reivindicar; ligar em massa é passo seguinte.
- Retomada da carga 71 (academy) e fechamento da 72 (escritório): roteiro em `ROTEIRO-CARGA-NOTURNA.md` e no relatório; só depois de aplicar 230000 a 230200.
