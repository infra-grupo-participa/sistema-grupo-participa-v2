# sistema-grupo-participa-v2

Sistema interno do **Grupo Participa**, reescrito em **Next.js 16** (App Router) sobre
**Supabase** (PostgreSQL + Auth). Substitui o sistema legado PHP/HTML.

## Estrutura

```
web/      → aplicação Next.js (frontend + APIs). É o produto.
infra/    → backend operacional
  supabase/functions/   → edge functions (webhooks Hotmart)
  scripts/              → worker de transcrição de depoimentos (Python)
docs/     → PRDs e especificações de produto
```

## Rodar o app

```bash
cd web
npm ci
npm run build
npm run start      # produção (Hostinger Node web app)
npm run dev        # desenvolvimento
npm test           # testes de domínio (Vitest)
```

Configuração de ambiente e deploy: ver [`web/DEPLOY.md`](web/DEPLOY.md).
Arquitetura: ver [`web/ARCHITECTURE.md`](web/ARCHITECTURE.md).

## Features

Placas (público + admin), Base de Alunos 360, Depoimentos (+ highlights por IA) e
administração (usuários, configurações, painel técnico).

> Secrets ficam em `.env` locais (gitignored) — nunca versionados.
