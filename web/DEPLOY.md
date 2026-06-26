# Deploy — Hostinger Node web app

App **Next.js 16** (App Router) que substitui o frontend estático + APIs PHP legados.
Backend continua no **Supabase** (DB + Auth). Roda como processo Node único (`next start`).

## Pré-requisitos
- Node ≥ 20 (testado em 24).
- Projeto Supabase de produção (`mbvybujpkwuorhtdzcde`) ou homologação (`msjppzivlxmqclhxqutd`).

## Variáveis de ambiente
Copie `.env.example` → `.env` (ou configure no painel da Hostinger). Obrigatórias:
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` — públicas (RLS protege).
- `SUPABASE_SERVICE_ROLE_KEY` — **server-only**. Necessária para: fluxos públicos de placa,
  gestão de usuários (`/api/admin/usuarios`) e painel admin-dev.
- `NEXT_PUBLIC_APP_URL`, `APP_ALLOWED_ORIGINS`.

Opcionais (degradam graciosamente se ausentes):
- `RESEND_API_KEY` (+ `MAIL_FROM`, `ADMIN_EMAIL`) — e-mails transacionais. Sem isso, envio é no-op.
- `ZOOM_*` — cria sala da entrevista no confirm. Sem isso, agenda salva sem link.
- `GROQ_API_KEY` — highlights de depoimentos por IA. Sem isso, o botão retorna erro de config.

## Build e start
```bash
cd web
npm ci
npm run build
npm run start      # next start (porta 3000 por padrão; respeita $PORT)
```
Na Hostinger Node web app: comando de build `npm ci && npm run build`, comando de start `npm run start`,
diretório da aplicação `web/`. Apontar o domínio para a porta do app.

## Qualidade (CI local)
```bash
npm run lint        # ESLint
npm test            # Vitest (domínio puro: placas, depoimentos)
npm run build       # type-check + build
```

## Verificação pós-deploy
- `/login` carrega; login com usuário admin redireciona para `/`.
- `/solicitar-placa` e `/agendar-entrevista` abrem sem sessão (rotas públicas por token).
- `/relatorios/placas`, `/sistema/alunos`, `/depoimentos`, `/usuarios` exigem sessão (proxy → /login).
- `/api/cep?cep=01001000` retorna o endereço (ViaCEP).

## Worker de transcrição (separado)
A transcrição Whisper de depoimentos roda no worker Python `infra/scripts/depoimentos_transcriber.py`
consumindo a fila `gp_depoimento_transcription_jobs` (Hostinger Node não roda faster-whisper).
O app Node enfileira/edita transcrição e gera os **highlights** (Groq) — a transcrição em si é do worker.

## ⚠️ Segurança pré-existente (banco)
10 tabelas de **backup** estão com RLS desabilitado e expostas à anon key
(`thb_alunos_bkp_*`, `_dedup_map_*`, `_hotmart_2025_stg`, `hm_product_catalog`).
Antes do go-live: dropar os backups OU habilitar RLS. Apresentar SQL ao responsável; não auto-aplicar.

## Cut-over
Desenvolver/validar em `web/` sem tocar no legado `app/` (ainda em produção). Trocar o document root
do domínio para o app Node só após a validação completa.
