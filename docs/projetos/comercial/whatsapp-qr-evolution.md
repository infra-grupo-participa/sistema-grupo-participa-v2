# WhatsApp por QR Code no CRM (Evolution API v2)

Conectar números de WhatsApp ao CRM lendo um QR Code dentro do sistema, ao lado do número oficial (Infobip).
Primeiro os dois números que hoje estão na Clint; depois, qualquer número. O número continua na Clint e no celular
(o WhatsApp aceita até 4 aparelhos conectados) até ser desligado de lá.

- Migration: `infra/supabase/migrations/20261008152212_crm_whatsapp_evolution.sql` — **APLICADA** em 08/10/2026
  (explicação e ensaio: `20261008152212.explain.md`, `20261008152212_ensaio.sql`).
- Edge Functions publicadas: `crm-evolution-webhook` (entrada) e `crm-evolution-enviar` (saída), `verify_jwt = false`.
- Tela: **Comercial › Configurações › Números de WhatsApp** (só gestor; o leitor não vê) e filtro/selo por número em **Conversas**.
- Migration do servidor ler a chave no Vault: `20261008180226_crm_evolution_credenciais_servidor.sql` — **APLICADA**
  em 08/10/2026 (`20261008180226.explain.md`, `20261008180226_ensaio.sql`).
- **LIGADO em 08/10/2026** (`crm.config.evolution_ligado = true`). Nenhum número conectado ainda.
- Infra: **Evolution v2.3.7 no Easypanel da VPS do João (Hostinger KVM 4)**, HTTPS pelo **Traefik do próprio Easypanel**
  (sem Caddy — o `Caddyfile` de `infra/evolution/` ficou só como referência). `CORS_ORIGIN=*`: a v2.3.7 recusava chamada
  servidor→servidor sem `Origin`; a proteção é a `apikey`. **Backup diário às 03:30.** Histórico do passo de infra:
  `docs/projetos/comercial/prompt-joao-vps-evolution.md`.

## Como funciona

```
celular / Clint ──(aparelho conectado)── WhatsApp ── Evolution (VPS, wa.grupoparticipa.app.br)
                                                        │  webhook por instância (header x-crm-chave)
                                                        ▼
                                Edge crm-evolution-webhook ── crm.evolution_webhook(canal, eventos)
                                                        │        └ crm.mensagem / crm.conversa (numero_id = canal)
Tela Conversas ── crm_enviar_mensagem(p_canal) ── fila ── Edge crm-evolution-enviar ── Evolution ── WhatsApp
Tela Configurações ── /api/comercial/canais (Next, servidor) ── Evolution (criar instância, QR, estado, sair)
```

- **Canal = `crm.numero_whatsapp`** (já era a FK `crm.conversa.numero_id`). Ganhou `provedor` `infobip|evolution`,
  `instancia` (`crm-<slug>-<6 hex>`, criada pelo sistema), `status` (`desconectado|aguardando_qr|conectado|banido`),
  `dono_id`, `equipe`, `recebe`, `envia`. A Infobip atual é o canal 1 (backfill: status `conectado`).
- **Mensagem** ganhou `numero_id` (canal, preenchido por trigger a partir da conversa) e `externa` (enviada pelo celular
  ou pela Clint no número por QR — entra no histórico para ele ficar completo).
- **Resposta pelo mesmo número**: `crm_enviar_mensagem(..., p_canal)`; sem `p_canal`, o banco usa o número da conversa
  mais recente da pessoa; sem conversa, o oficial.
- **Entrada** (`MESSAGES_UPSERT`, inclusive `fromMe`): idempotente pelo id da mensagem (`provedor_msg_id =
  <instância>:<id>`); grupos (`@g.us`), status/listas (`@broadcast`) e canais (`@newsletter`) são ignorados na Edge.
  Pessoa casada como no resto do CRM (`pessoas.registrar` por telefone → `controle.fone_key`); desconhecido vira contato
  novo. Arquivo chega em base64 no próprio webhook e a Edge sobe para o bucket privado `crm-midia`.
- **Conexão** (`CONNECTION_UPDATE`, `QRCODE_UPDATED`): atualiza status e o QR (guardado só em
  `crm.numero_whatsapp_segredo`, sem grant). Fechou com 403 = `banido`.
- **Envio**: texto, imagem, PDF e áudio pelo canal da conversa, respeitando `envio_ligado` e a chave de idempotência.
  Sem janela de 24 h e sem template (é WhatsApp comum).

### Anti-ban (no banco, vale para tela, MCP e qualquer escritor)

| Regra | Onde | Padrão |
|---|---|---|
| Sem disparo em massa por número QR | trigger `crm.tg_ficha_numero_oficial` (ficha) + `crm.tg_mensagem_canal` (mensagem com `ficha_id`) | bloqueado |
| Sem template por número QR | `crm.tg_mensagem_canal` e `crm_enviar_mensagem` | bloqueado |
| Número padrão (disparos/templates) só o oficial | trigger `crm.tg_config_numero_oficial` | — |
| Mensagens por minuto por número | `crm.config.evolution_limite_minuto` | 15 |
| Mensagens por hora por número | `crm.config.evolution_limite_hora` | 200 |
| Primeiros contatos por hora (quem nunca escreveu no número) | `crm.config.evolution_novos_hora` | 20 |
| Pausa entre mensagens do mesmo número na Edge | `pausaMs` | 1,2–2,4 s |

### Kill-switches

- `crm.config.evolution_ligado` (default false; **true desde 08/10/2026**): desligado = mensagens recebidas ficam guardadas em
  `crm.integracao_evento` (processadas quando ligar, sem o arquivo); nada sai por número QR. Status de conexão continua
  sendo atualizado (é dado do número, não do lead).
- `crm.config.envio_ligado` (já existia): desliga também o envio por QR.

## Onde ficam as chaves

| Onde | Nome | Quem usa |
|---|---|---|
| **Vault do Supabase** (fonte principal) | `evolution_api_url` = `https://wa.grupoparticipa.app.br` | Edge de envio e servidor Next |
| **Vault do Supabase** | `evolution_api_key` = a `AUTHENTICATION_API_KEY` da Evolution | Edge de envio e servidor Next |
| Hostinger do app Next (**opcional**) | `EVOLUTION_API_URL` / `EVOLUTION_API_KEY` | servidor Next; se preenchidas, **têm prioridade** sobre o Vault |

- O servidor Next, com o env vazio, lê o Vault por `public.crm_evolution_credenciais()` (execute só `service_role`), com
  `createAdminSupabase()`, **só depois** do portão de gestor (`crm_sessao().papel = 'gestor'`) nas rotas
  `/api/comercial/canais`. Cache em memória de 5 min (30 s quando vazio). Código:
  `web/modules/comercial/infrastructure/evolution-credenciais.ts`; regra de prioridade em `escolherCredenciais`
  (`domain/canais-whatsapp.ts`, teste `domain/credenciais-evolution.test.ts`).
- Trocar a chave: atualizar o segredo no Vault (`vault.update_secret`); o Next pega em até 5 min (ou no próximo deploy).
- Nada configurado = "Conectar número" responde 503 e a Edge de envio responde 503 (fail-closed). Nunca colar a chave em
  chat/Slack.

## Conferência de 08/10/2026 (pg_net com a chave do Vault, sem imprimir a chave)

| Chamada | HTTP |
|---|---|
| `GET https://wa.grupoparticipa.app.br/` | 200 (2.3.7) |
| `GET /instance/fetchInstances` com apikey / sem apikey | 200 / 401 |
| `POST /functions/v1/crm-evolution-webhook` sem segredo | 401 |

## Passo a passo para o Arthur

1. **Conectar o 1º número da Clint** (só gestor do Comercial): **Comercial › Configurações › aba Números de WhatsApp ›
   Conectar número** → nome (ex.: "Clint 4276") → **Gerar QR Code** → no celular desse número, **WhatsApp › Aparelhos
   conectados › Conectar aparelho** → ler o QR. Status vira "Conectado". Repetir para o segundo.
2. **Testar sem incomodar ninguém**: de um celular da equipe, mandar "teste" para o número conectado → a conversa
   aparece em Conversas com o selo do número; responder pelo CRM → chega no celular da equipe; responder pelo celular do
   número → aparece no CRM como "Celular/Clint". Não testar com lead.
3. **Se algo der errado**: `update crm.config set evolution_ligado = false;` (efeito em segundos) e Configurações ›
   Desconectar.

## Testes e conferências

- Vitest: `web/modules/comercial/infrastructure/evolution-webhook.test.ts` (normalização do webhook),
  `evolution-envio.test.ts` (pedido de envio/erros), `web/modules/comercial/domain/canais-whatsapp.test.ts` (regras),
  `mapeamento-canais.test.ts`.
- Saúde no banco:

```sql
select provedor, nome, status, status_motivo, right(numero, 4) final from crm.numero_whatsapp;
select resultado, count(*) from crm.integracao_evento where fonte = 'evolution' group by 1;
select status, count(*) from crm.mensagem where provedor = 'evolution' and direcao = 'saida' group by 1;
```

## Decisões

- Webhook na **Edge do Supabase** (não no Next): nenhuma mensagem se perde quando o site cai ou está em deploy.
- Gestão (criar instância, QR, desconectar) pelo **servidor Next** (env opcional, senão Vault); envio pela **Edge** com o
  Vault. A chave nunca vai ao navegador nem ao log.
- Uma chave de webhook **por instância**, gerada no banco, conferida em tempo constante.
- A VPS não guarda mensagem (`DATABASE_SAVE_DATA_NEW_MESSAGE=false`): o arquivo recebido vem em base64 no webhook. Se a
  Edge não conseguir subir o arquivo e a Evolution não reenviar, a mensagem fica com "Arquivo não chegou ao CRM" em 15 min.

## Ações na mensagem, status do atendimento e agendada (migration 20261009153515)

- **Menu na mensagem** (tela de Conversas e dock do Funil): copiar; responder citando (só QR, `quoted` no sendText);
  editar (só QR, até 15 min, quem enviou ou gestor) e apagar para todos (só QR, até 48 h). No oficial (API Cloud) editar e
  apagar aparecem desativados com o motivo. A tela grava em `crm.mensagem_acao`; a Edge `crm-evolution-enviar` chama
  `POST /chat/updateMessage` / `DELETE /chat/deleteMessageForEveryone` e devolve em `crm.evolution_acao_resultado`.
- **Webhook:** a instância assina também `MESSAGES_EDITED` e `MESSAGES_DELETE` (contato ou celular editou/apagou →
  `crm.evolution_alteracao`). Instância antiga: Configurações → Números → **Atualizar eventos** (reaplica o webhook sem
  desconectar). O texto anterior de uma edição não é guardado; apagada vira "Mensagem apagada" na API.
- **Atendimento:** aberto / em espera / encerrado em `crm.conversa`; mensagem nova do contato reabre.
- **Agendada:** mesma fila do envio (`fila_em` no futuro). Detalhes e decisões: `infra/supabase/migrations/20261009153515.explain.md`.
