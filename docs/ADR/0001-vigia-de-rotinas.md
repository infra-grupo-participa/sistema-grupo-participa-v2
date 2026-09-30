# ADR 0001 — Vigia externo das rotinas (pg_cron + pg_net)

- Data: 30/09/2026
- Estado: proposto (migrations `20261001a..e` escritas e ensaiadas; não aplicadas)
- Provas: `infra/supabase/migrations/20261001.explain.md`

## Contexto

As rotinas do banco rodam no `pg_cron`. As que chamam edge functions usam `net.http_post`, que é
assíncrono: o `cron.job_run_details` marca `succeeded` quando o pedido entra na fila, não quando a edge
responde. Em 30/09 00:45 UTC, 100% das execuções HTTP dos últimos 7 dias estavam `succeeded`, enquanto
`net._http_response` (6 h) tinha 29 timeouts, 15×502, 14×500 e 1×546. Ninguém via:

- `ingest-meta`, `ingest-paginas`, `ingest-criativos`: 502, token da Meta vencido em 19/09.
- `ingest-active`, `ingest-disparos`: a edge morre em 150 s (504 IDLE_TIMEOUT); o pg_net desiste em 5 s.
- `sessao-emails` (GPS): 2.016 falhas SQL seguidas desde 22/09 (voltou em 30/09 00:50 UTC).
- `ingest-aquecimento`: 500 a cada 15 min até ser desligada.

O `net._http_response` não guarda url nem nome da rotina e expira em 6 h: sem registrar a chamada na
hora, não dá para saber de quem é a resposta.

## Decisão

1. Schema `ops`, fechado para `anon`/`authenticated`.
2. Wrapper `ops.cron_post(p_job, <mesmos parâmetros de net.http_post>)`: chama `net.http_post` e grava
   `request_id`, rotina, url sem query e hora em `ops.rotina_chamada`. Nunca grava headers/params. O
   registro fica num sub-bloco que engole erro: o vigia nunca derruba a rotina.
3. Os 15 crons HTTP passam a chamar o wrapper (só troca o nome da função; prova por eco).
4. `ops.vigiar()` a cada 10 min (minuto 2): reconcilia chamadas × respostas, lê `cron.job_run_details`
   por cursor em `runid`, classifica, mantém estado por rotina, abre/fecha incidente e grava UMA mensagem
   por ciclo, só quando algo mudou. Envio ao Slack desligado por padrão (`ops.config.enviar = false`).
5. Tela: `public.ops_saude_rotinas()` (só `gp_is_admin()`).

### Regras

| intervalo | abre com N falhas seguidas | ou sem sucesso por | fecha com K ok |
|---|---|---|---|
| ≤ 15 min | 3 | máx(3×intervalo, 30 min) | 3 |
| ≤ 1 h | 2 | 3 h | 3 |
| < 20 h | 2 | 2×intervalo + 1 h | 2 |
| diário+ | 1 | intervalo + 2 h | 1 |

Intervalo = mediana medida em 7 dias; rotina nova entra sozinha pelo schedule. Silenciar:
`ops.rotina.silenciado_ate`.

### Timeout por rotina, não piso global (revisto após pentest)

Com o timeout padrão de 5 s, `ingest-mensageria` teve respostas 200 cortadas (a edge responde em 3,0–5,6 s),
o que daria falso positivo. A 1ª versão usava piso global de 155 s; o pentest reprovou: o worker do pg_net
0.19.5 só pega o próximo lote quando o atual termina, e um pedido de 155 s seguraria a fila inteira
(inclusive avisos de 10 s como `ra_fn_avisar_n8n`).

Agora:
- `ops.rotina.timeout_ms` (nulo = o do command) só onde o dado justifica: `ingest-mensageria-hourly` = 15 s.
- `ops.config.timeout_minimo_ms` padrão 0, teto 30 s.
- 504 real (`ingest-active`, `ingest-disparos`) se conserta na edge; o vigia os vê como `timeout_cliente`.

### O que vai ao Slack

Só nome da rotina, motivo, status HTTP + classe e horários, com `& < >` escapados. O trecho de erro
(corpo/`return_message`) fica só no banco, redigido (e-mail, CPF, telefone, JWT, Bearer, token ≥ 20).

## Consequências

- Custo por ciclo: ~3 ms, 134 buffers (medido). `cron.job_run_details` só por `runid > cursor` (pkey).
- 144 ciclos/dia; `ops.rotina_chamada` ~300 linhas/dia, expurgo de 14 dias.
- Rotina HTTP nova criada com `net.http_post` direto aparece como `sem_rastreio` na mensagem.
- O vigia não vigia a si mesmo: `vigia_ultimo_ciclo` na RPC mostra se ele parou.

## Fora do escopo (pendências)

- `net.http_post` tem EXECUTE para PUBLIC (medido 30/09): qualquer role que alcance o schema `net`
  faz requisição de saída. Avaliar à parte.
- `cron.job_run_details`: 75 mil linhas, 28 MB, sem expurgo.
- Criar no Vault `slack_webhook_rotinas` e só então `update ops.config set enviar = true`.
- `ig-collect-quad-daily` (job 2, inativo) passa body `::bytea`, que o pg_net 0.19.5 não aceita.
