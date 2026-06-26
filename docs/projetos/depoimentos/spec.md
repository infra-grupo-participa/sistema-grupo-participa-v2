# SPEC — Sistema de Depoimentos Interno
**Projeto:** Base de Depoimentos de Alunos  
**Cliente:** Grupo Participa  
**Referência:** PRD v3.1  
**Status:** v1.0  
**Data:** 2026-03-31

---

## Índice

1. [Banco de Dados — Migrations SQL](#1-banco-de-dados--migrations-sql)
2. [Spec Técnica — Endpoints](#2-spec-técnica--endpoints)
3. [Spec de Implementação — Ordem de Construção](#3-spec-de-implementação--ordem-de-construção)

---

## 1. Banco de Dados — Migrations SQL

> Executar no Supabase SQL Editor na ordem abaixo.  
> Prefixo `gp_` para isolar tabelas deste módulo das tabelas legadas (`thb_`).

---

### 1.1 Habilitar extensão UUID (se ainda não estiver ativa)

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

### 1.2 `gp_cursos`

```sql
CREATE TABLE gp_cursos (
  id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name    VARCHAR(255) NOT NULL,
  slug    VARCHAR(255) NOT NULL UNIQUE,
  active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### 1.3 `gp_tags`

```sql
CREATE TABLE gp_tags (
  id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  label VARCHAR(100) NOT NULL UNIQUE,
  color VARCHAR(7),  -- hex, ex: #FF5733
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### 1.4 `gp_depoimentos`

```sql
CREATE TABLE gp_depoimentos (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  aluno_id          UUID NOT NULL REFERENCES thb_alunos(id) ON DELETE RESTRICT,
  foto_url          TEXT,
  social_handle     VARCHAR(255),
  drive_folder_url  TEXT,
  video_url         TEXT,
  transcript        TEXT,
  testimonial_date  DATE,
  created_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION gp_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_gp_depoimentos_updated_at
BEFORE UPDATE ON gp_depoimentos
FOR EACH ROW EXECUTE FUNCTION gp_set_updated_at();
```

---

### 1.5 `gp_depoimento_cursos`

```sql
CREATE TABLE gp_depoimento_cursos (
  depoimento_id UUID NOT NULL REFERENCES gp_depoimentos(id) ON DELETE CASCADE,
  curso_id      UUID NOT NULL REFERENCES gp_cursos(id) ON DELETE RESTRICT,
  PRIMARY KEY (depoimento_id, curso_id)
);
```

---

### 1.6 `gp_depoimento_tags`

```sql
CREATE TABLE gp_depoimento_tags (
  depoimento_id UUID NOT NULL REFERENCES gp_depoimentos(id) ON DELETE CASCADE,
  tag_id        UUID NOT NULL REFERENCES gp_tags(id) ON DELETE RESTRICT,
  PRIMARY KEY (depoimento_id, tag_id)
);
```

---

### 1.7 Verificação de `profissao` em `thb_alunos`

Antes de rodar as migrations, verificar se o campo existe:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'thb_alunos'
  AND column_name = 'profissao';
```

**Se não existir**, adicionar como campo complementar em `gp_depoimentos`:

```sql
ALTER TABLE gp_depoimentos ADD COLUMN profissao VARCHAR(255);
```

---

### 1.8 Row Level Security (RLS)

```sql
-- Habilitar RLS nas tabelas do módulo
ALTER TABLE gp_depoimentos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE gp_cursos            ENABLE ROW LEVEL SECURITY;
ALTER TABLE gp_tags              ENABLE ROW LEVEL SECURITY;
ALTER TABLE gp_depoimento_cursos ENABLE ROW LEVEL SECURITY;
ALTER TABLE gp_depoimento_tags   ENABLE ROW LEVEL SECURITY;

-- Somente usuários autenticados com role admin têm acesso
-- Ajustar conforme a estrutura de roles já existente no sistema legado
CREATE POLICY "admin_full_access_depoimentos"
ON gp_depoimentos FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "admin_full_access_cursos"
ON gp_cursos FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "admin_full_access_tags"
ON gp_tags FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "admin_full_access_dep_cursos"
ON gp_depoimento_cursos FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "admin_full_access_dep_tags"
ON gp_depoimento_tags FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin')
WITH CHECK (auth.jwt() ->> 'role' = 'admin');
```

---

### 1.9 Índices para Performance

```sql
-- Filtros frequentes na página de visualização
CREATE INDEX idx_gp_dep_aluno_id        ON gp_depoimentos(aluno_id);
CREATE INDEX idx_gp_dep_testimonial_date ON gp_depoimentos(testimonial_date DESC);
CREATE INDEX idx_gp_dep_cursos_curso     ON gp_depoimento_cursos(curso_id);
CREATE INDEX idx_gp_dep_tags_tag         ON gp_depoimento_tags(tag_id);
```

---

## 2. Spec Técnica — Endpoints

> Todos os endpoints PHP retornam `Content-Type: application/json`.  
> Todos requerem sessão autenticada com role `admin`.  
> Em caso de falha de autenticação: `401 Unauthorized`.  
> Em caso de falha de autorização: `403 Forbidden`.

---

### 2.1 Processar Pasta do Drive

**Arquivo:** `app/api/depoimentos/processar-pasta.php`

```
POST /api/depoimentos/processar-pasta
```

**Request body:**
```json
{
  "folder_url": "https://drive.google.com/drive/folders/1OBSym8GRWWvxzDO-eOALoy0ddk4HB965"
}
```

**Processamento interno:**
1. Extrair `FOLDER_ID` do link via regex
2. Autenticar com Service Account (JSON em `credentials/google-service-account.json`)
3. Chamar Drive API v3: `GET /drive/v3/files?q='FOLDER_ID'+in+parents&fields=files(id,name,mimeType)`
4. Separar arquivos por MIME type (vídeo / áudio / ignorar)
5. Selecionar primeiro vídeo em ordem alfabética por `name`
6. Para cada áudio (ordem alfabética por `name`):
   - Baixar via Drive API v3: `GET /drive/v3/files/FILE_ID?alt=media`
   - Salvar temporariamente em `/tmp/audio_TIMESTAMP_N.ext`
   - Enviar para Groq API (Whisper Large v3, `language: pt`)
   - Capturar transcrição
   - Deletar arquivo temporário
7. Concatenar transcrições com `\n\n`
8. Retornar resultado

**Response 200:**
```json
{
  "success": true,
  "video_url": "https://drive.google.com/file/d/VIDEO_ID/view",
  "transcript": "Parágrafo do áudio 1.\n\nParágrafo do áudio 2.",
  "audios_count": 2,
  "video_found": true
}
```

**Response 200 — sem vídeo:**
```json
{
  "success": true,
  "video_url": null,
  "transcript": "Parágrafo do áudio 1.",
  "audios_count": 1,
  "video_found": false
}
```

**Erros:**

| Código | Situação | Mensagem |
|---|---|---|
| 400 | `folder_url` ausente ou inválido | `"Link de pasta inválido."` |
| 404 | Pasta não encontrada ou sem acesso | `"Pasta não encontrada. Verifique se foi compartilhada com a Service Account."` |
| 422 | Nenhum áudio na pasta | `"Nenhum arquivo de áudio encontrado na pasta."` |
| 500 | Falha na Groq API | `"Falha na transcrição do áudio N. Tente novamente."` |
| 500 | Falha na Drive API | `"Erro ao acessar o Google Drive. Tente novamente."` |

---

### 2.2 Depoimentos — CRUD

**Arquivo:** `app/api/depoimentos/index.php`

---

#### Listar depoimentos

```
GET /api/depoimentos
```

**Query params (todos opcionais):**

| Param | Tipo | Descrição |
|---|---|---|
| `search` | string | Busca por nome do aluno (ILIKE) |
| `nivel` | string | Filtro por nível (`thb_alunos.nivel`) |
| `estado_uf` | string | Filtro por estado |
| `cidade` | string | Filtro por cidade |
| `curso_id` | UUID | Filtro por curso |
| `tag_id` | UUID | Filtro por tag |
| `turma` | string | Filtro por turma |
| `profissao` | string | Filtro por profissão |
| `order` | `asc\|desc` | Ordenação por `testimonial_date` (padrão: `desc`) |
| `page` | int | Página (padrão: 1) |
| `per_page` | int | Itens por página (padrão: 20, máx: 100) |

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "aluno": {
        "id": "uuid",
        "nome": "João Silva",
        "email": "joao@email.com",
        "cidade": "Goiânia",
        "estado_uf": "GO",
        "nivel": "Platina",
        "turma": "Turma 12",
        "profissao": "Médico"
      },
      "foto_url": "https://...",
      "social_handle": "@joaosilva",
      "drive_folder_url": "https://drive.google.com/drive/folders/...",
      "video_url": "https://drive.google.com/file/d/.../view",
      "transcript": "Texto do depoimento...",
      "testimonial_date": "2026-01-15",
      "cursos": [
        { "id": "uuid", "name": "Curso X", "slug": "curso-x" }
      ],
      "tags": [
        { "id": "uuid", "label": "transformação", "color": "#FF5733" }
      ],
      "created_at": "2026-03-31T10:00:00Z",
      "updated_at": "2026-03-31T10:00:00Z"
    }
  ],
  "pagination": {
    "total": 45,
    "page": 1,
    "per_page": 20,
    "total_pages": 3
  }
}
```

---

#### Buscar aluno em thb_alunos

```
GET /api/depoimentos/buscar-aluno?q=TERMO
```

**Descrição:** Busca em `thb_alunos` por nome ou e-mail para vincular ao depoimento.

**Response 200:**
```json
{
  "data": [
    {
      "id": "uuid",
      "nome": "João Silva",
      "email": "joao@email.com",
      "cidade": "Goiânia",
      "estado_uf": "GO",
      "nivel": "Platina",
      "turma": "Turma 12",
      "profissao": "Médico"
    }
  ]
}
```

---

#### Criar depoimento

```
POST /api/depoimentos
```

**Request body:**
```json
{
  "aluno_id": "uuid",
  "foto_url": "https://...",
  "social_handle": "@joaosilva",
  "drive_folder_url": "https://drive.google.com/drive/folders/...",
  "video_url": "https://drive.google.com/file/d/.../view",
  "transcript": "Texto revisado...",
  "testimonial_date": "2026-01-15",
  "curso_ids": ["uuid1", "uuid2"],
  "tag_ids": ["uuid3", "uuid4"]
}
```

**Validações:**
- `aluno_id`: obrigatório, deve existir em `thb_alunos`
- `transcript`: obrigatório, mínimo 10 caracteres
- `testimonial_date`: obrigatório, formato `YYYY-MM-DD`, não pode ser data futura
- `curso_ids`: obrigatório, mínimo 1 curso

**Response 201:**
```json
{
  "success": true,
  "id": "uuid-do-novo-depoimento"
}
```

**Erros:**

| Código | Situação |
|---|---|
| 400 | Campos obrigatórios ausentes ou inválidos |
| 404 | `aluno_id` não encontrado em `thb_alunos` |
| 409 | Depoimento já existente para este aluno nesta data |

---

#### Obter depoimento

```
GET /api/depoimentos/{id}
```

**Response 200:** mesmo schema do item individual em "Listar depoimentos".  
**Response 404:** `{ "error": "Depoimento não encontrado." }`

---

#### Atualizar depoimento

```
PUT /api/depoimentos/{id}
```

**Request body:** mesmo schema do POST (todos os campos opcionais exceto os obrigatórios).

**Response 200:**
```json
{ "success": true }
```

---

#### Excluir depoimento

```
DELETE /api/depoimentos/{id}
```

**Response 200:**
```json
{ "success": true }
```

**Response 404:** `{ "error": "Depoimento não encontrado." }`

---

### 2.3 Cursos

**Arquivo:** `app/api/depoimentos/cursos.php`

| Método | Rota | Ação |
|---|---|---|
| `GET` | `/api/depoimentos/cursos` | Listar todos (ativos e inativos) |
| `POST` | `/api/depoimentos/cursos` | Criar curso |
| `PUT` | `/api/depoimentos/cursos/{id}` | Editar curso |
| `PATCH` | `/api/depoimentos/cursos/{id}/toggle` | Ativar / desativar |
| `DELETE` | `/api/depoimentos/cursos/{id}` | Excluir (somente se sem depoimentos vinculados) |

**POST/PUT body:**
```json
{
  "name": "Nome do Curso",
  "slug": "nome-do-curso"
}
```

---

### 2.4 Tags

**Arquivo:** `app/api/depoimentos/tags.php`

| Método | Rota | Ação |
|---|---|---|
| `GET` | `/api/depoimentos/tags` | Listar todas com contagem de uso |
| `POST` | `/api/depoimentos/tags` | Criar tag |
| `PUT` | `/api/depoimentos/tags/{id}` | Editar tag |
| `DELETE` | `/api/depoimentos/tags/{id}` | Excluir (com alerta se em uso) |

**POST/PUT body:**
```json
{
  "label": "transformação",
  "color": "#FF5733"
}
```

**DELETE — Response 409 se em uso:**
```json
{
  "error": "Esta tag está vinculada a 5 depoimento(s) e não pode ser excluída.",
  "usage_count": 5
}
```

---

### 2.5 Filtros Disponíveis

**Arquivo:** `app/api/depoimentos/filtros.php`

```
GET /api/depoimentos/filtros
```

Retorna os valores únicos disponíveis para popular os dropdowns de filtro.

**Response 200:**
```json
{
  "niveis": ["Iniciante", "Pessoal", "Em Formação", "Profissional", "Ouro", "Platina", "Diamante", "Diamante Vermelho"],
  "estados": ["GO", "SP", "RJ"],
  "cidades": ["Goiânia", "São Paulo", "Rio de Janeiro"],
  "turmas": ["Turma 12", "Turma 13"],
  "cursos": [{ "id": "uuid", "name": "Curso X" }],
  "tags": [{ "id": "uuid", "label": "transformação", "color": "#FF5733" }]
}
```

---

## 3. Spec de Implementação — Ordem de Construção

> Seguir esta ordem garante que cada etapa tem dependências resolvidas antes de avançar.

---

### Fase 0 — Pré-requisitos (antes de qualquer código)

| # | Tarefa | Responsável | Observação |
|---|---|---|---|
| 0.1 | ~~Criar projeto no Google Cloud e ativar Drive API~~ | ✅ Concluído | Service Account: __sistema-gp@sistema-gp-491120.iam.gserviceaccount.com__ |
| 0.2 | ~~Criar Service Account e baixar JSON de credenciais~~ | ✅ Concluído | Mesma SA usada no Google Calendar |
| 0.3 | Adicionar `credentials/` ao `.gitignore` | Dev | **Fazer antes do primeiro commit** |
| 0.4 | Criar conta no Groq e gerar API key | ✅ Concluído | Gerar nova chave após rotacionar a exposta |
| 0.5 | Configurar variável de ambiente `GROQ_API_KEY` no servidor | ✅ Concluído | Gerenciado via .env na Hostinger |
| 0.6 | Inspecionar `thb_alunos` no Supabase | Dev | Verificar campos, tipo do `id`, presença de `profissao` |
| 0.7 | Executar migrations SQL (Seção 1) no Supabase | Dev | Na ordem: extensão → cursos → tags → depoimentos → vínculos → RLS → índices |

---

### Fase 1 — Base de Dados e Gestão Auxiliar

**Objetivo:** CRUD de cursos e tags funcionando antes de qualquer depoimento.

| # | Tarefa | Arquivo(s) |
|---|---|---|
| 1.1 | Implementar `GET/POST/PUT/PATCH/DELETE /api/depoimentos/cursos` | `app/api/depoimentos/cursos.php` |
| 1.2 | Implementar `GET/POST/PUT/DELETE /api/depoimentos/tags` | `app/api/depoimentos/tags.php` |
| 1.3 | Página de gestão de cursos | `app/admin/depoimentos/cursos.html` |
| 1.4 | Página de gestão de tags | `app/admin/depoimentos/tags.html` |
| 1.5 | Adicionar links de navegação no menu do sistema legado | `app/assets/js/config.js` |

**Critério de conclusão da Fase 1:** admin consegue criar, editar e desativar cursos e tags via painel.

---

### Fase 2 — Módulo de Transcrição

**Objetivo:** `processar-pasta.php` funcionando de ponta a ponta antes de construir o formulário em volta.

| # | Tarefa | Arquivo(s) |
|---|---|---|
| 2.1 | Instalar SDK do Google Drive para PHP (`composer require google/apiclient`) | `composer.json` |
| 2.2 | Implementar autenticação via Service Account | `app/api/depoimentos/processar-pasta.php` |
| 2.3 | Implementar listagem de arquivos da pasta via Drive API | idem |
| 2.4 | Implementar separação por MIME type (vídeo / áudio / ignorar) | idem |
| 2.5 | Implementar seleção do primeiro vídeo (ordem alfabética) | idem |
| 2.6 | Implementar download de áudio e envio para Groq API | idem |
| 2.7 | Implementar concatenação de parágrafos e limpeza de temporários | idem |
| 2.8 | Testar com pasta real do Drive contendo 1 vídeo + 2 áudios | — |
| 2.9 | Testar casos de erro: pasta sem áudio, pasta sem acesso, áudio corrompido | — |

**Critério de conclusão da Fase 2:** endpoint retorna `video_url` e `transcript` corretamente para uma pasta real.

---

### Fase 3 — CRUD de Depoimentos

**Objetivo:** formulário completo de cadastro e edição.

| # | Tarefa | Arquivo(s) |
|---|---|---|
| 3.1 | Implementar `GET /api/depoimentos/buscar-aluno` | `app/api/depoimentos/buscar-aluno.php` |
| 3.2 | Implementar `POST /api/depoimentos` com validações | `app/api/depoimentos/index.php` |
| 3.3 | Implementar `GET /api/depoimentos/{id}` | idem |
| 3.4 | Implementar `PUT /api/depoimentos/{id}` | idem |
| 3.5 | Implementar `DELETE /api/depoimentos/{id}` | idem |
| 3.6 | Página de listagem admin com paginação | `app/admin/depoimentos/index.html` |
| 3.7 | Formulário de criação: busca de aluno + preview de dados | idem |
| 3.8 | Formulário: campo de pasta do Drive + botão "Processar pasta" + loading state | idem |
| 3.9 | Formulário: preenchimento automático de `video_url` e `transcript` após processamento | idem |
| 3.10 | Formulário: multi-select de cursos e tags (com criação inline de tag) | idem |
| 3.11 | Formulário de edição (mesmo componente, dados preenchidos) | idem |
| 3.12 | Confirmação de exclusão | idem |

**Critério de conclusão da Fase 3:** admin consegue cadastrar um depoimento completo do zero em menos de 3 minutos.

---

### Fase 4 — Página de Visualização

**Objetivo:** página de consulta com filtros para uso na criação de copies.

| # | Tarefa | Arquivo(s) |
|---|---|---|
| 4.1 | Implementar `GET /api/depoimentos` com todos os filtros e paginação | `app/api/depoimentos/index.php` |
| 4.2 | Implementar `GET /api/depoimentos/filtros` | `app/api/depoimentos/filtros.php` |
| 4.3 | Página de visualização: layout de cards agrupados por curso | `app/depoimentos/index.html` |
| 4.4 | Cards: foto, nome, cidade/estado, profissão, turma, nível (badge), cursos, tags, data, @, vídeo | idem |
| 4.5 | Transcrição expansível no card (truncada por padrão) | idem |
| 4.6 | Painel de filtros: nível, estado, cidade, curso, tag, turma, profissão, data | idem |
| 4.7 | Barra de busca por nome | idem |
| 4.8 | Badges de nível com identidade visual (cores por nível) | idem |

**Critério de conclusão da Fase 4:** admin consegue filtrar "Platina + Centro-Oeste + tag transformação" e ver os cards corretos.

---

### Fase 5 — Testes e Validações Finais

| # | Tarefa |
|---|---|
| 5.1 | Testar acesso sem autenticação (todas as rotas devem retornar 401) |
| 5.2 | Testar RLS no Supabase (acesso direto pela chave anon deve ser bloqueado) |
| 5.3 | Confirmar que `credentials/` não está no repositório |
| 5.4 | Confirmar que `GROQ_API_KEY` não aparece em nenhum arquivo front-end |
| 5.5 | Confirmar que arquivos temporários de áudio são deletados após transcrição |
| 5.6 | Testar pasta do Drive com múltiplos áudios e verificar ordem dos parágrafos |
| 5.7 | Testar soft delete: remover aluno de `thb_alunos` e verificar comportamento do depoimento |
| 5.8 | Validar performance dos filtros combinados com volume real de dados |

---

## Apêndice — Variáveis de Ambiente Necessárias

```env
GROQ_API_KEY=gsk_...
GOOGLE_SERVICE_ACCOUNT_PATH=/caminho/fora/do/public_html/credentials/google-service-account.json
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

---

## Apêndice — MIME Types Aceitos

| Tipo | MIME Types |
|---|---|
| Vídeo | `video/mp4`, `video/quicktime`, `video/x-msvideo`, `video/webm`, `video/mpeg`, `video/x-matroska` |
| Áudio | `audio/mpeg`, `audio/mp4`, `audio/wav`, `audio/webm`, `audio/x-m4a`, `audio/ogg`, `audio/flac` |


---

## Apêndice — Contexto do Ambiente

| Item | Valor |
|---|---|
| Service Account | `sistema-gp@sistema-gp-491120.iam.gserviceaccount.com` |
| Google Drive API | ✅ Ativada no projeto `sistema-gp-491120` |
| Pastas do Drive | Compartilhadas com a Service Account |
| Groq API Key | Configurada no `.env` da Hostinger como `GROQ_API_KEY` |
| Gerenciador de dependências PHP | A definir — verificar disponibilidade do Composer na Hostinger |
| Credenciais JSON | Armazenar fora do `public_html`, nunca commitar |

> **Atenção:** rotacionar a chave Groq exposta antes de usar em produção.
