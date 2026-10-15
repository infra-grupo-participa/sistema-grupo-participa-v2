# black-youtube

Coleta da aba **Lives** do Dashboard da Black Friday (`/infra/dashboards/csm/black-friday-2026-10`, chave `black-friday-2026-10`).
Lê a YouTube Data API v3 das lives cadastradas em `dados.black_lives` e grava no banco o que a aba mostra.
Migrations: `20261015220000_dados_black_lives_estrutura.sql` (tabelas, funções, RPCs), `20261015220100_dados_black_lives_cron.sql` (cron),
`20261015230000_dados_black_lives_sem_autor.sql` (sem autor + expurgo) e `20261015230100_dados_black_lives_teto_janela.sql` (teto de 6 h na janela).
Publicada em produção em 15/10/2026 como versão 6 (YouTube só com `part=snippet`; trava de concorrência).
Desenho: `Projetos/dashboard-black-friday/DESENHO-ABA-LIVES.md` no cérebro do Victor.

## O que faz

| Quando | O que lê | Onde grava |
|---|---|---|
| A cada 10 minutos (minuto UTC divisível por 10) | `videos.list` de todas as lives ativas: título, miniatura, situação, horários, views, likes, comentários | `black_lives` (leitura atual) e `black_live_foto` (1 foto por hora) |
| Todo minuto, enquanto alguma live está na janela (15 min antes do horário previsto até 3 h depois, ou última leitura "ao_vivo" até 6 h depois do previsto) | `videos.list` das lives na janela; no ar, `concurrentViewers` e `liveChat/messages` | `black_live_minuto` (origem `api`, espectadores e contagem de chat do minuto), `black_live_chat` (idempotente por `msg_id`) |
| Uma vez por hora por live | `commentThreads` (até 300 comentários por leitura) | `black_live_comentario` (idempotente por `comment_id`) |

- Situação: `upcoming` vira `em_breve`, `live` vira `ao_vivo`, `none` vira `realizada`. Vídeo que a API não devolve (privado, removido, id errado)
  fica `a_agendar` enquanto era `em_breve` ou `a_agendar`; `realizada` e `ao_vivo` não regridem.
- O minuto da amostra é `seg = floor((agora - actualStartTime) / 60) * 60`, o mesmo eixo do CSV do Studio. A aba prefere a origem `studio`
  e cai na `api` onde não há Studio.
- Chat: só `textMessageEvent`. **Guarda só o texto, sem autor**: nem `displayName`, nem `channelId`, URL do canal ou foto; a Edge nem pede `authorDetails` à API.
  O texto do chat e dos comentários é apagado 90 dias depois da Black (a partir de 01/02/2027) pelo cron `black-youtube-expurgo`.
  O `nextPageToken` fica em `black_lives.chat_page_token`, então cada minuto lê só o que chegou. Mensagem de antes do início tem `seg` negativo
  (fica guardada, fora da curva). Depois que a live acaba o chat não é mais legível: a Edge faz uma última leitura na chamada em que a live sai do ar.
- Reações: a API pública não entrega. `reacoes` fica nulo na origem `api`; só o Studio tem.
- Só `videos.list`, `commentThreads.list` e `liveChat/messages`. Nunca `search` (100 unidades).

## Quem chama e como se protege

- Cron `black-youtube` (`* * * * *`) pelo `ops.cron_post`, só quando `dados.black_live_pede_chamada()` é verdadeira (a cada 10 min, e todo minuto na janela).
- Header `x-sync-chave` = Vault `dados_black_youtube_chave`, comparado em tempo constante, **fail-closed** (sem segredo no Vault, 401).
- `verify_jwt = false` em `infra/supabase/config.toml`; sem isso o deploy devolve 401 ao cron.
- A Edge entra no banco como `postgres` (`SUPABASE_DB_URL`) e só chama as funções internas `dados.black_live_*` (sem grant para ninguém mais).
- Chave da YouTube: Vault `dados_black_youtube_api_key`, lida por `dados.black_youtube_credenciais()`. Nunca em código, log ou resposta.
  A resposta da Edge traz só contagens. Erros da API registram o status HTTP, nunca a URL (leva a chave) nem o corpo.

- Trava de concorrência: a Edge reserva uma conexão e pega `pg_try_advisory_lock(20261015)`. Se outra rodada ainda está em andamento (cron todo minuto + chamada manual), responde `{"ocupado":true}` com 200, sem chamar o YouTube.
  Se a Edge cair, a conexão fecha e o lock é solto sozinho.

## Operar

- Desligar: `select cron.alter_job((select jobid from cron.job where jobname = 'black-youtube'), active := false);`
- Religar: `... active := true`.
- Ver o que a última rodada fez: `select status_code, left(content, 300) from net._http_response order by created desc limit 5;`
- Expurgo: `select dados.black_live_expurgar();` devolve `expurgou:false` até o corte (01/02/2027 ou 90 dias depois da última live, o que for maior). Cron `black-youtube-expurgo`, `52 4 * * *`.
- Ver a leitura atual: `select video_id, situacao, views, espectadores_agora, coletado_em from dados.black_lives order by data_prevista;`
- Cadastrar uma live nova ou trocar o horário: pela aba (master) ou `dados_black_live_cadastrar`. O id do vídeo é o `v=` da URL do YouTube.
- Trocar a chave da YouTube: `select vault.update_secret((select id from vault.secrets where name = 'dados_black_youtube_api_key'), '<nova>');` (a Edge relê em até 10 min).
- Publicar de novo: Management API `POST /v1/projects/mbvybujpkwuorhtdzcde/functions/deploy?slug=black-youtube` com `verify_jwt=false`, arquivos `index.ts` e `youtube.ts`.

## Testar

- Unidade: `deno test infra/supabase/functions/black-youtube/youtube.test.ts` (fixtures escritas à mão no formato da API, sem dado real).
- Tipos e lint: `deno check infra/supabase/functions/black-youtube/index.ts` e `deno lint infra/supabase/functions/black-youtube`.
- Rota: sem header ou com chave errada, `401 {"erro":"chave"}`; com a chave certa, `200` e as contagens. Nos minutos que não são múltiplos de 10 e sem live na janela, `{"lives":0}` (é o esperado, não é falha).

## Cota

Chave compartilhada com o `dashboard-ht` (`YT_API_KEY`), limite de 10 mil unidades por dia. `videos.list` e `commentThreads` custam 1 por chamada.
`liveChat/messages` custa cerca de 5 por chamada (valor da documentação, **ainda não medido nesta chave**). Estimativa de uma live de 2 h:
195 minutos de janela x (1 + ~5) = cerca de 1.200 unidades. Medir na live de 15/10 (comparar o consumo no Google Cloud Console) antes de 03/11.

## Riscos conhecidos

- Se a Edge parar com a live `ao_vivo`, a janela fica aberta por no máximo 6 h depois do horário previsto (teto da migration `20261015230100`); depois disso o cron volta a chamar só a cada 10 minutos.
  O vigia (`ops.rotina`, 3 falhas seguidas ou 30 min sem sucesso) avisa.
- O nome apagado do chat/comentários pode ficar fisicamente em tuplas mortas até o vacuum e nos backups do Supabase; não há como removê-lo de backup por aqui.
- Expurgo depende do pg_cron ativo em fevereiro/2027: conferir em 02/02/2027 que `black_live_chat` e `black_live_comentario` zeraram.
- Ler o chat uma vez por minuto pode perder mensagens se passarem de 2.000 por minuto (a Edge lê até 3 páginas por minuto, ou seja 6.000).
- Pico por amostra de 1 minuto da API pode diferir do pico do Studio (que é por minuto cheio); a aba prefere o Studio quando existe.
