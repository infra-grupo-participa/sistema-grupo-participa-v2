# WhatsApp por QR Code no CRM (Evolution API v2)

Conectar números de WhatsApp ao CRM lendo um QR Code dentro do sistema, ao lado do número oficial (Infobip).
Primeiro os dois números que hoje estão na Clint; depois, qualquer número. O número continua na Clint e no celular
(o WhatsApp aceita até 4 aparelhos conectados) até ser desligado de lá.

- Migration: `infra/supabase/migrations/20261008152212_crm_whatsapp_evolution.sql` — **APLICADA** em 08/10/2026
  (explicação e ensaio: `20261008152212.explain.md`, `20261008152212_ensaio.sql`).
- Edge Functions publicadas: `crm-evolution-webhook` (entrada) e `crm-evolution-enviar` (saída), `verify_jwt = false`.
- Tela: **Comercial › Configurações › Números de WhatsApp** (só gestor; o leitor não vê) e filtro/selo por número em **Conversas**.
- Infra da VPS: `docs/projetos/comercial/prompt-joao-vps-evolution.md` (passo da infra, não repetido aqui) e os arquivos
  prontos em `infra/evolution/` (`docker-compose.yml`, `Caddyfile`, `.env.example`, sem segredo).

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

- `crm.config.evolution_ligado` (**default false**): desligado = mensagens recebidas ficam guardadas em
  `crm.integracao_evento` (processadas quando ligar, sem o arquivo); nada sai por número QR. Status de conexão continua
  sendo atualizado (é dado do número, não do lead).
- `crm.config.envio_ligado` (já existia): desliga também o envio por QR.

## O que depende da VPS

Tudo do lado do sistema está pronto e publicado. Falta só a Evolution no ar e as chaves:

| Onde | Nome | Valor |
|---|---|---|
| Hostinger do app Next (variáveis de ambiente) | `EVOLUTION_API_URL` | `https://wa.grupoparticipa.app.br` |
| Hostinger do app Next | `EVOLUTION_API_KEY` | a `AUTHENTICATION_API_KEY` do `.env` da VPS |
| Vault do Supabase (Edge de envio) | `evolution_api_url` | `https://wa.grupoparticipa.app.br` |
| Vault do Supabase | `evolution_api_key` | a mesma chave |

Sem as variáveis no app, "Conectar número" responde "Evolution não configurada" (503). Sem o Vault, a Edge de envio
responde 503 e nada sai. Nunca colar a chave em chat/Slack: copiar direto da VPS para o painel.

Gravar no Vault (SQL Editor do Supabase; o retorno não mostra o valor):

```sql
select vault.create_secret('https://wa.grupoparticipa.app.br', 'evolution_api_url');
select vault.create_secret('<chave>', 'evolution_api_key');
```

## Passo a passo para o Arthur

1. **VPS** (João, `prompt-joao-vps-evolution.md`): Hostinger KVM 2 (2 vCPU / 8 GB) é o recomendado; o mínimo que
   funciona é KVM 1 (1 vCPU / 4 GB) para 2–5 números. DNS `wa.grupoparticipa.app.br` → IP da VPS; Docker; os 3 arquivos
   de `infra/evolution/` em `/opt/evolution/` (`.env` a partir do `.env.example`, `chmod 600`); `docker compose up -d`.
2. **Conferir**: `https://wa.grupoparticipa.app.br/` responde JSON com a versão; `/instance/fetchInstances` sem `apikey`
   dá 401.
3. **Chaves**: as 2 variáveis na Hostinger do app (e redeploy) + os 2 segredos no Vault (tabela acima).
4. **Ligar**: `update crm.config set evolution_ligado = true;` (desligar = `false`, efeito em segundos).
5. **Conectar o 1º número da Clint**: Configurações › Números de WhatsApp › Conectar número → nome (ex.: "Clint 4276")
   → no celular desse número, WhatsApp › Aparelhos conectados › Conectar aparelho → ler o QR. Status vira "Conectado".
   Repetir para o segundo.
6. **Testar sem incomodar ninguém**: de um celular da equipe, mandar "teste" para o número conectado → a conversa
   aparece em Conversas com o selo do número; responder pelo CRM → chega no celular da equipe; responder pelo celular do
   número → aparece no CRM como "Celular/Clint". Não testar com lead.
7. **Se algo der errado**: `update crm.config set evolution_ligado = false;` e Configurações › Desconectar.

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
- Gestão (criar instância, QR, desconectar) pelo **servidor Next** com `EVOLUTION_API_URL/KEY`; envio pela **Edge** com o
  Vault. A chave nunca vai ao navegador.
- Uma chave de webhook **por instância**, gerada no banco, conferida em tempo constante.
- A VPS não guarda mensagem (`DATABASE_SAVE_DATA_NEW_MESSAGE=false`): o arquivo recebido vem em base64 no webhook. Se a
  Edge não conseguir subir o arquivo e a Evolution não reenviar, a mensagem fica com "Arquivo não chegou ao CRM" em 15 min.
