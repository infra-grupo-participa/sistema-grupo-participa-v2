# 20261009001000 — fin.recalcular_identidade() rápida

**Status: APLICADA em produção 08/10/2026 (~23h BRT; versão em supabase_migrations.schema_migrations).** Ensaio `20261009001000_fin_identidade_rapida_ensaio.sql` rodado contra produção em
`begin … rollback` (08/10/2026 ~21:30 UTC), 2 blocos, **todas as linhas ok = true**. Reversão ensaiada em
`begin … rollback`: md5(prosrc) volta a `203c6f02…`, ACL `{postgres=X/postgres}`, 1 função (sem sobrecarga).
Produção conferida depois: md5 `203c6f02285e76595ac22ea1ee688650` (intacta).

Versão: maior em `supabase_migrations.schema_migrations` e no repo = `20261008230000` → esta é `20261009001000`.
Se aplicada por `apply_migration` do MCP, a versão vira a do relógio: renomear os arquivos para a versão gravada.

## O que cresceu (medido)
| período | job 54 (cron.job_run_details) | causa medida |
|---|---|---|
| 27/09 18:20–19:20 | 1,9–2,3 s | `fin.hotmart_transacoes` com ~11 mil linhas |
| 27/09 20:20 → 28/09 04:20 | 6–10 s | +11.932 linhas às 19h de 27/09 (carga do histórico) |
| 28/09 05:20 → 29/09 | 16–28 s | +34.278 linhas entre 01h e 04h de 28/09 (carga) → 57,9 mil |
| 29/09 → 08/10 | média diária 20,0 → 31,5 s, máx 67 s | dado parado (+105 linhas em 9 dias); sobe com a disputa de cache/IO |

O "~930 ms" de 27/09 foi medido antes da carga. Hoje o cálculo puro do algoritmo antigo em tabela temporária leva
~9 s; o cron leva 31,5 s porque grava tudo em tabela logada (truncate + 68 mil + 49 mil inserts, 5 UPDATEs de
propagação, UPDATE final de 68 mil linhas só para `calculado_em`) e relê `fin.hotmart_transacoes` (114 MB de
heap, `shared_buffers` 256 MB para 7 sistemas) ~10 vezes por rodada. Muda em média **0 linha** por hora
(ensaio T10). Efeito colateral: `TRUNCATE` = ACCESS EXCLUSIVE em `fin.identidade` a rodada inteira — ~25 funções
leitoras (crm_jornada, crm.emails_da_pessoa, trajetória, relatórios do financeiro) esperam 30–67 s por hora.

## Antes — algoritmo antigo por fase (texto do corpo vivo, fin.identidade* → temp, temp_buffers 64MB)
| fase | ms (2 rodadas) |
|---|---|
| arestas | 820 / 1.526 |
| revisão | 211 / 212 |
| nós | 853 / 859 |
| propagação (5 rodadas, UPDATE da tabela toda) | 3.209 / 3.231 |
| sugestões | 2.478 / 2.546 |
| final (UPDATE calculado_em + contagens) | 1.496 / 1.513 (7.049 com temp_buffers 8MB) |
| **cron real (tabela logada)** | **média 31.500, máx 67.000** |

`explain (analyze, buffers)` — sugestão `mesmo_nome` do corpo vivo (`begin … rollback`):
```
HashAggregate (actual rows=660)  Buffers: shared hit=2651 read=30954, temp read=1407 written=1411
  ->  Merge Join (actual rows=14540)  Rows Removed by Join Filter: 823761
        ->  Sort  Sort Method: external merge  Disk: 5592kB
              ->  Seq Scan on hotmart_transacoes t   Buffers: shared hit=188 read=14372
        ->  Materialize -> Sort  Sort Method: external merge  Disk: 5664kB
              ->  Seq Scan on hotmart_transacoes t_1  Buffers: shared hit=220 read=14340
Execution Time: 1134.206 ms
```
Propagação, 1ª rodada (UPDATE da tabela toda): `Update on _idt_no (actual rows=44784)`, HashAggregate
`Batches: 5 Disk Usage: 3416kB`, `local read=26271 written=21631`, **1.371 ms**; repete por 5 rodadas.

## Depois
Função nova ponta a ponta (ensaio): **T3 4.873 ms** (bloco 1), **T6 5.143 ms** (bloco 2, temp_buffers padrão = cron),
**T9 4.938 ms** (2ª rodada, 0 linha escrita). Perfil por trecho (temp_buffers padrão, 2 rodadas):
lê transações + arestas 497/790 · analyze + fontes 552/545 · revisão 126/123 · nós 220/262 · propagação 1.509/1.443 ·
sugestões 410+851 / 398+984 · gravação da diferença 143+3+176+170 / 135+1+169+170 · contagens 206.

`explain (analyze, buffers)`, `begin … rollback`:
```
-- leitura ÚNICA de fin.hotmart_transacoes (antes: ~10 por rodada)
Seq Scan on hotmart_transacoes (actual rows=57367)  Filter: (conta = 'academy')  Rows Removed by Filter: 537
  Buffers: shared hit=14414 read=149                       Execution Time: 137.927 ms
-- diferença em fin.identidade (nada mudou: 0 linha escrita)
Delete on identidade f -> Hash Anti Join (rows=0)  Buffers: shared hit=2232      Execution Time: 67.088 ms
Update on identidade f -> Hash Join (rows=0)  Rows Removed by Join Filter: 68212  Execution Time: 72.889 ms
Insert on identidade -> Hash Anti Join (rows=0) -> Index Only Scan using identidade_pkey  Execution Time: 81.983 ms
Delete on identidade_aresta f -> Merge Anti Join (rows=0)
  -> Index Scan using identidade_aresta_pkey / _idt_aresta_pkey                    Execution Time: 370.536 ms
-- propagação, 2ª rodada só a partir de quem mudou (44.784 → 21.103)
Update on _idt_no (actual rows=21103)  Execution Time: 805.283 ms
```
Seq Scan nas tabelas de 68/49 mil linhas é a escolha certa: a função lê todas por definição (anti-join).

## Prova de mesmo resultado (ensaio, `begin … rollback`)
Bloco 1 — algoritmo antigo × função nova, mesmo instante: md5 `identidade c552455c`, `aresta 6108d37e`,
`revisao 28b3eebe`, `sugestao 75a283e5` (com evidência) iguais; jsonb igual
`{"nos":68212,"arestas":49139,"pessoas":23179,"revisao":93,"rodadas":5,"sugestoes":1080,"emails_hotmart":23709,"pessoas_hotmart":22909}`.
Bloco 2 — tabelas reais estragadas (−500/+lixo/300 alterados em identidade; −200/+lixo em aresta; 5 motivos,
3 contagens, −3/+lixo em revisão; −50/20 evidências/+lixo em sugestão) → a função conserta exatamente isso
(`identidade ins 500 upd 300 del 1`, `aresta ins 200 del 1`, `sugestao ins 50 upd 20 del 1`, `revisao ins 2 upd 9`)
e os 4 md5 voltam aos de antes. 2ª rodada: **0 linha escrita** (`pg_stat_xact_user_tables`).

## As 5 perguntas
1. **Escala.** Ainda recalcula a base inteira (o grafo é global: um e-mail novo pode juntar duas pessoas
   antigas), mas em memória/temp e lendo a tabela de 114 MB uma vez. Escrita = só o que mudou (hoje ~0/h).
   Com 10× transações: leitura única cresce linear (~1,4 s), propagação e sugestões crescem com o grafo.
   Incremental por "pessoa suja" não foi feito: as fontes (compradores, thb_alunos, auth.users, gps.membros,
   cs.*, sip_users) não têm carimbo de alteração confiável; ver Risco no relatório.
2. **Índice.** Nenhum índice novo. Diferença usa os PKs existentes (`identidade_pkey`, `identidade_aresta_pkey`)
   e hash anti-join; temp tables com PK próprio e `analyze` após a carga.
3. **Frequência.** Continua 24×/dia (cron 54, `47 * * * *`, intacto). Custo/rodada 31,5 s → ~5 s; escrita
   ~117 mil linhas/h → ~0.
4. **Repetição.** `fin.hotmart_transacoes` lida 1× por rodada (antes ~10×). Leitores de `fin.identidade` deixam
   de esperar o recálculo (sem TRUNCATE, só row lock).
5. **Reversão.** `20261009001000_fin_identidade_rapida_reversao.sql` (corpo vivo de 08/10, guarda por md5,
   ensaiada). Freio sem DDL: `select cron.alter_job(54, active := false);` (dado fica parado, não some).


## Medido depois de aplicar (08/10/2026)
- md5 do corpo vivo `9cdc97cd…`, ACL `{postgres=X/postgres}`; `fn_acelera_sync_funil` com `work_mem=16MB`.
- Duas rodadas manuais pela Management API (inclui ~1 s de rede): **7,3 s e 6,4 s** (antes: média 31,5 s, máx 67 s). Retorno idêntico ao ensaio: nos 68212, arestas 49139, pessoas 23179, sugestoes 1080, rodadas 5.
- Pendente: conferir as 3 primeiras rodadas do job 54 (`47 * * * *`) em `cron.job_run_details`.
