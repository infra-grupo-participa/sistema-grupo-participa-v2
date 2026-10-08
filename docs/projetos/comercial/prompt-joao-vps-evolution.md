# Prompt — subir a Evolution API na VPS (para o João Pedro rodar no Claude dele)

Contexto: o CRM do Comercial vai conectar números de WhatsApp por QR Code usando a **Evolution API v2** auto-hospedada.
O sistema (tela de QR, webhook, envio) está sendo construído no repo; este prompt cobre só a **infra na VPS**.
Copiar tudo abaixo da linha e colar no Claude que tem o conector da Hostinger com a conta da VPS.

---

Você vai instalar a **Evolution API v2** numa VPS da Hostinger para o CRM do Grupo Participa. Trabalhe com cuidado: é produção.

## Regras de segurança (obrigatórias)
- **Antes de qualquer coisa, liste as VPS da conta e mostre o que já roda em cada uma** (containers, serviços, portas abertas, uso de disco/RAM). **Não use "recreate"/reinstalar sistema, não pare nem apague nada que já exista** sem eu confirmar. Se a VPS já hospeda outra coisa, instale a Evolution ao lado, em pasta própria, sem conflitar portas.
- Se não houver VPS adequada (mínimo 1 vCPU / 4 GB RAM livres), **pare e me pergunte** antes de comprar qualquer coisa.
- **Nunca mostre segredos na resposta** (API key, senhas do Postgres). Gere-os na própria VPS (`openssl rand -hex 32`) e guarde em `/opt/evolution/.env` com permissão `600`.
- **Não conecte nenhum número de WhatsApp** e não envie mensagem a ninguém. Os números serão conectados pela tela do CRM.
- Postgres e Redis **não podem** ficar expostos na internet — só na rede interna do Docker.

## 1. DNS
- Criar registro **A** `wa.grupoparticipa.app.br` → IP público da VPS (TTL baixo). Descubra onde está o DNS de `grupoparticipa.app.br` (Hostinger ou Cloudflare). Se for Cloudflare, deixe o registro **sem proxy (nuvem cinza)** para o Caddy emitir o certificado.
- Confirmar propagação (`dig +short wa.grupoparticipa.app.br`).

## 2. Preparar a VPS
- Ubuntu atualizado (`apt update && apt upgrade -y`), Docker + Docker Compose plugin instalados (se a Hostinger já tiver template com Docker, reaproveite).
- Firewall (ufw ou firewall da Hostinger): liberar só **22, 80, 443**. Se 80/443 já estiverem em uso por outro proxy (nginx/traefik), **não derrube** — me avise e use esse proxy para rotear `wa.grupoparticipa.app.br` para a Evolution.
- Criar `/opt/evolution/`.

## 3. Arquivos em `/opt/evolution/`

`docker-compose.yml`:
```yaml
services:
  evolution:
    image: evoapicloud/evolution-api:<TAG_V2_ESTAVEL>   # fixe a última v2 estável do Docker Hub; nunca "latest"
    restart: unless-stopped
    env_file: .env
    depends_on: [postgres, redis]
    volumes:
      - evolution_instances:/evolution/instances
    networks: [interna]
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: evolution
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: evolution
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks: [interna]
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    networks: [interna]
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks: [interna]
volumes: { evolution_instances: {}, pg_data: {}, redis_data: {}, caddy_data: {}, caddy_config: {} }
networks: { interna: {} }
```
(Se o passo 2 mostrou outro proxy já usando 80/443, remova o serviço `caddy` e roteie pelo proxy existente para `evolution:8080`.)

`Caddyfile`:
```
wa.grupoparticipa.app.br {
  encode gzip
  reverse_proxy evolution:8080
}
```

`.env` (gere os valores na VPS, `chmod 600 .env`):
```
SERVER_TYPE=http
SERVER_PORT=8080
SERVER_URL=https://wa.grupoparticipa.app.br
AUTHENTICATION_API_KEY=<openssl rand -hex 32>
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false
POSTGRES_PASSWORD=<openssl rand -hex 24>
DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution:<mesma senha>@postgres:5432/evolution?schema=public
DATABASE_CONNECTION_CLIENT_NAME=evolution_crm
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=false
DATABASE_SAVE_MESSAGE_UPDATE=false
DATABASE_SAVE_DATA_CONTACTS=false
DATABASE_SAVE_DATA_CHATS=false
CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://redis:6379/6
CACHE_REDIS_PREFIX_KEY=evolution
CACHE_LOCAL_ENABLED=false
CONFIG_SESSION_PHONE_CLIENT=CRM Grupo Participa
CONFIG_SESSION_PHONE_NAME=Chrome
QRCODE_LIMIT=30
DEL_INSTANCE=false
WEBHOOK_GLOBAL_ENABLED=false
LOG_LEVEL=ERROR,WARN,INFO
LOG_BAILEYS=error
CORS_ORIGIN=https://grupoparticipa.app.br
```
(As mensagens não ficam guardadas na VPS — o histórico mora no Supabase do CRM via webhook. Confira na doc oficial da Evolution v2 se algum nome de variável mudou na tag escolhida e ajuste.)

## 4. Subir e validar
- `cd /opt/evolution && docker compose up -d` e `docker compose ps` (todos `running`/healthy).
- `curl -s https://wa.grupoparticipa.app.br/` → deve responder JSON da Evolution com a versão (certificado válido).
- Teste de autenticação sem expor a chave: `curl -s -o /dev/null -w '%{http_code}' https://wa.grupoparticipa.app.br/instance/fetchInstances` → **401**; com o header `apikey` lido do `.env` → **200**.
- Teste de QR (opcional, sem escanear): criar instância `teste-joao`, confirmar que retorna QR em base64, e **apagar a instância** em seguida (`DELETE /instance/delete/teste-joao`).
- Confirmar que as portas 5432 e 6379 **não** respondem de fora (`nc -zv <ip> 5432` de fora deve falhar).

## 5. Operação
- Backup diário do volume `pg_data` (pg_dump via cron na VPS, guardando 7 dias) — as sessões conectadas ficam aí; perder isso obriga a escanear o QR de novo.
- Atualização: só trocando a tag fixa no compose, nunca automática.
- Habilitar snapshot semanal da VPS no painel da Hostinger, se disponível.

## 6. Entregar a chave ao sistema (sem colar em chat/Slack)
A `AUTHENTICATION_API_KEY` precisa chegar ao app sem passar por mensagem:
- **No painel da Hostinger do app Node `grupoparticipa.app.br`** (variáveis de ambiente), criar:
  - `EVOLUTION_API_URL` = `https://wa.grupoparticipa.app.br`
  - `EVOLUTION_API_KEY` = valor do `.env` da VPS (copie direto da VPS para o painel)
  e reiniciar/redeploy o app.
- Se você tiver acesso ao Supabase do projeto `mbvybujpkwuorhtdzcde`, gravar também no Vault: `evolution_api_url` e `evolution_api_key` (`select vault.create_secret('<valor>', 'evolution_api_key')` — sem imprimir o valor no retorno). Se não tiver, avise o Arthur que falta esse passo.

## 7. Resposta final (sem nenhum segredo)
- Qual VPS usou (plano, RAM/CPU livres) e o que já rodava nela.
- Tag da Evolution instalada.
- Resultado de cada teste do passo 4 (códigos HTTP).
- Backup configurado (sim/não, horário).
- Variáveis criadas na Hostinger do app e no Vault (só os **nomes**).
- Qualquer coisa que ficou pendente ou que você precisou adaptar.
