# Carga do histórico das lives da Black (15/10/2026)

Pedido do Victor Hugo (15/10/2026). Alimenta a aba Lives (migrations 20261015220000 e 20261015220100; sem autor desde a 20261015230000) com o que as 3 lives já realizadas deixaram.

| O quê | Fonte | Onde | Situação |
|---|---|---|---|
| Minuto a minuto do Studio | `liveViewership_*.csv` dentro dos 3 `.zip` do YouTube Studio | `dados.black_live_minuto`, origem `studio` | **APLICADA** em 15/10 (`carga-studio.sql`, md5 e507d4337bd71431e2ef11910c1ca7ab) |
| Chat | `chat-downloader` (replay), uma linha por mensagem | `dados.black_live_chat` | **APLICADA** em 15/10. O SQL tinha nome de autor, **não está no repositório** e foi apagado do scratchpad em 15/10. A coluna `autor` foi removida pela migration 20261015230000; o texto é apagado em 01/02/2027 |
| Comentários do vídeo | `commentThreads` pela Edge `black-youtube` | `dados.black_live_comentario` | **APLICADA** em 15/10 (pela primeira rodada da Edge) |

## Studio
`python3 -I gerar_carga_studio.py ~/Downloads > carga-studio.sql` lê só o `liveViewership_*.csv` de cada zip (em memória; o nome interno tem "/"). Só números.
O SQL é uma transação: confere que a live existe e que o título bate com o do zip, apaga e regrava as linhas `studio` do vídeo e confere linhas, pico e somas.
Rodar de novo muda 0 linhas de resultado. Conferido contra o esperado:

| Live | Linhas | Pico | Posição do pico | Chat | Reações |
|---|---|---|---|---|---|
| fpgmDwBKVcQ (06/10) | 96 | 363 | 2880 s | 291 | 48 |
| Hdsg23VbfHI (08/10) | 81 | 125 | 3540 s | 102 | 2 |
| t0PLYUORt1E (13/10) | 121 | 342 | 3480 s | 242 | 61 |

## Chat do replay: não bate com o Studio (e por quê)
Mensagens do replay (positivas, depois do início): 259, 74 e 221, contra 291, 102 e 242 do Studio. O replay perde mensagens apagadas ou ocultadas; o Studio conta as que existiram.
Além disso o replay guarda 50, 8 e 27 mensagens de **antes do início** (`seg` negativo): ficam no banco, fora da curva. Totais gravados: 309, 82 e 248 (`chat_guardado`).
A tela deve mostrar `chat_total` (Studio) como número da live e o texto guardado como amostra.
O zero do Studio fica de 10 a 45 s antes do `actualStartTime` da API (com deslocamento de +40 s, 79 de 96 minutos da live 1 batem exatamente; sem deslocamento, 21). A Edge usa `actualStartTime` como zero.
`seg` do chat histórico = `timestamp` da mensagem menos `inicio` da API (mesmo critério da Edge).

## Como voltar
`delete from dados.black_live_minuto where origem = 'studio' and video_id in ('fpgmDwBKVcQ','Hdsg23VbfHI','t0PLYUORt1E');`
`delete from dados.black_live_chat where video_id in (...as mesmas...);` (comentários: `delete from dados.black_live_comentario where video_id in (...)`).
Também foram apagadas as 201 linhas `api` só de chat que o gravador criou para essas 3 lives (a tela ignora `api` quando existe `studio`).
