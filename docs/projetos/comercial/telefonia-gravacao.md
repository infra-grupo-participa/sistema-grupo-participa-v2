# Telefonia com gravação no CRM Comercial

**Dono a partir de 12/10/2026:** João Pedro (decisão do Arthur).
**Status:** pesquisa feita, nada construído. Hoje o botão "Ligar" é a versão leve: disca pelo celular (`tel:`) ou abre o WhatsApp e registra a atividade "Ligação" com o resultado. Não grava.

## Objetivo

O vendedor liga **de dentro do sistema** (navegador) para o lead no Brasil, e a **gravação fica no histórico do contato**, com player, e opcionalmente transcrição e resumo.

## Situação da conta Infobip (lida em 09/10/2026, só GET)

| Item | Situação |
|---|---|
| Chave `infobip_api_key` (Vault) | já tem permissão em `/calls/1/*` |
| Números | 4, todos **só WhatsApp** (nenhum de voz) |
| `/calls/1/configurations` | vazio: Calls nunca configurado |
| Gravação | add-on não ativo |
| `/webrtc/1/applications` | 410 Gone (endpoint antigo; o navegador entra pela Calls API) |
| Saldo | R$ 327,56 |

## Opções

| Opção | Custo celular BR | Grava | Softphone na tela | Observação |
|---|---|---|---|---|
| **Infobip** Calls API + WebRTC SDK (`infobip-rtc`) | sob consulta | sim (add-on, `.wav` via API) | sim | já é fornecedor, cobra em BRL. **Recomendada** |
| Twilio Voice (Voice JS SDK) | US$ 0,066/min + número | sim (callback) | sim | plano B; número BR exige CNPJ e endereço |
| Api4com | ~R$ 0,35/min | sim | não (extensão do Chrome) | menos controle |
| WhatsApp Calling API (oficial) | — | sim (7 dias) | sim | **não serve como canal principal**: o lead precisa autorizar antes; permissão vale 72 h |

## O que precisa ativar (com o gerente de conta da Infobip)

1. Voz, WebRTC e o add-on de **gravação**.
2. **Número de voz brasileiro** (DID, de preferência fixo 021) em nome da empresa. Confirmar se a Infobip vende número BR.
3. Tabela de preço por minuto para celular BR.
4. Nome do evento de "gravação pronta" e por quanto tempo o arquivo fica disponível lá.
5. Recarga de saldo.

Anatel: o 0303 deixou de ser obrigatório em 08/2025; "Origem Verificada" só é obrigatória acima de 500 mil chamadas/mês. O número exibido precisa ser da empresa.

## Como o sistema fica (desenho proposto)

- **Banco:** tabela `crm.ligacao` (contato, negócio, vendedor, provedor, id externo, status, início, duração, caminho da gravação, transcrição), com RLS por helper e escrita só por RPC/edge (`crm.guarda_escrita()`), seguindo `docs/manual-banco-de-dados.md`. Kill-switch `ligacao_ligada` em `crm.config`, default false.
- **Edge `crm-ligacao-token`:** gera o token WebRTC (`/webrtc/1/token`) para o vendedor logado (só Comercial, não leitor).
- **Edge `crm-ligacao-webhook`:** no `CALL_RECEIVED` cria a chamada para o lead, faz a ponte (Dialog), toca o aviso de gravação e grava; no `CALL_FINISHED` baixa o `.wav`, converte (opcional) e salva em `crm-midia/ligacoes/...`, atualiza a tabela e cria a atividade "Ligação" concluída.
- **Tela:** botão "Ligar" (já existe; trocar o comportamento quando `ligacao_ligada`), softphone embutido (discar, mudo, desligar, cronômetro), player no histórico do contato com URL assinada.
- **Transcrição (opcional):** cliente de IA que o sistema já tem (Groq) + resumo no negócio.
- **MCP:** ferramenta de leitura para o Claude ver a transcrição/resumo das ligações do lead.

Esforço estimado: 6 a 9 dias (banco 1, edges 2–3, softphone e player 2–3, transcrição 1, teste ponta a ponta 1). A ponte e a gravação só dão para testar depois da ativação na Infobip.

## Paliativo: gravar a ligação do WhatsApp pelo navegador (ideia do Arthur, 12/10/2026)

Enquanto a telefonia nativa não sai: o CRM abre a ligação no WhatsApp e, ao mesmo tempo, grava o áudio pelo navegador.

**Limite técnico:**
- O navegador não acessa o áudio de outro aplicativo. A ligação do **WhatsApp Desktop ou do celular não dá para gravar** pelo CRM.
- No macOS, o Chrome só captura o áudio do sistema quando é o áudio de uma **aba do próprio Chrome** (`getDisplayMedia` com `audio: true`, escolhendo a aba e marcando "compartilhar áudio").
- Gravar só o microfone (`getUserMedia`) pega a voz do vendedor, não a do lead.

**Onde funciona:** a ligação precisa acontecer no **WhatsApp Web, numa aba do Chrome**. Fluxo:
1. O vendedor clica em "Ligar (gravado)" no CRM.
2. O CRM pede "compartilhar aba com áudio" e o vendedor escolhe a aba do WhatsApp Web.
3. O CRM grava, com `MediaRecorder`, o áudio da aba (lead) mixado com o microfone (vendedor), usando Web Audio API.
4. Ao encerrar, faz upload para `crm-midia/ligacoes/...`, registra em `crm.ligacao` com `origem = 'navegador'` e cria a atividade "Ligação" com player no histórico do contato.

**Riscos:**
- Depende de o WhatsApp Web fazer ligação de voz na conta e versão do vendedor. **Verificar antes de construir.**
- O vendedor precisa escolher a aba e marcar "compartilhar áudio" a cada ligação; se esquecer, fica sem gravação. Mostrar um aviso e detectar quando a faixa de áudio da aba não vier.
- Só funciona no Chrome desktop. Ligação pelo celular não grava.
- Não há prova automática de com quem foi a ligação. A gravação é amarrada ao contato de onde o vendedor clicou.
- O aviso LGPD ("esta ligação está sendo gravada") passa a ser falado pelo vendedor. Pôr no roteiro e registrar na atividade que o aviso foi dado (checkbox).
- WhatsApp: gravar a própria ligação não é proibido pelos termos, mas a transparência LGPD vale do mesmo jeito.

**Esforço estimado:** 2 a 3 dias, reaproveitando tabela, player e upload, que também servem para a solução nativa. Construir o paliativo primeiro adianta parte da nativa.

**Recomendação:** fazer o paliativo como ponte, se a verificação do WhatsApp Web com ligação der certo, e manter a nativa (Infobip) como destino. A gravação confiável e automática só vem com a nativa.

## LGPD (decisões pendentes)

- Aviso no início da chamada: "Esta ligação será gravada para registro do atendimento."
- Base legal: legítimo interesse (art. 7º, IX) ou procedimentos preliminares a contrato (art. 7º, V). Não depender de consentimento.
- **Retenção: a decidir com o Arthur e o jurídico.** Sugestão: 12 meses para quem não comprou, 5 anos para quem comprou, com exclusão automática.
- Acesso: bucket privado, URL assinada; quem ouve segue a regra de quem vê o lead.

## Fontes

- Infobip WebRTC: https://www.infobip.com/docs/voice-and-video/webrtc
- Infobip Calls API: https://www.infobip.com/docs/voice-and-video/calls
- Infobip add-ons de voz: https://www.infobip.com/docs/voice-and-video/getting-started/enable-voice-add-ons
- Meta, gravação de chamadas: https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/call-recording/
- Twilio, Brasil: https://www.twilio.com/en-us/guidelines/br/voice
- Anatel e o fim do 0303: https://agenciabrasil.ebc.com.br/geral/noticia/2025-08/anatel-justifica-fim-da-obrigatoriedade-do-uso-do-0303/
