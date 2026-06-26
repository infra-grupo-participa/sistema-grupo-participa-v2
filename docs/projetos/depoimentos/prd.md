# PRD — Sistema de Depoimentos Interno
**Projeto:** Base de Depoimentos de Alunos  
**Cliente:** Grupo Participa  
**Status:** Rascunho v3.1  
**Data:** 2026-03-31

---

## 1. Visão Geral

Módulo interno de gestão e visualização de depoimentos de alunos, integrado ao sistema legado (PHP + HTML/CSS/JS + Supabase), acessível apenas por usuários autenticados. O sistema permite registrar, editar e consultar depoimentos organizados por curso, com filtros dinâmicos combinados e um transcritor integrado ao formulário.

O admin cola um único **link de pasta do Google Drive** contendo os arquivos do depoimento. O sistema automaticamente lista os arquivos, separa vídeos de áudios, transcreve cada áudio gerando um parágrafo por arquivo, e seleciona o primeiro vídeo (ordem alfabética) para exibição no card.

---

## 2. Objetivos

- Centralizar depoimentos de alunos em uma base estruturada
- Vincular cada depoimento ao(s) curso(s) correspondente(s)
- Automatizar a transcrição a partir de uma pasta do Google Drive
- Permitir revisão e edição da transcrição antes de salvar
- Filtros dinâmicos e combináveis para busca de perfis na criação de copies
- Aproveitar dados existentes em `thb_alunos` via FK direta, sem duplicidade

---

## 3. Escopo

### 3.1 Dentro do Escopo (v1)

- CRUD completo de depoimentos (somente admin)
- Importação de dados do aluno via `thb_alunos` (busca por nome ou e-mail)
- Integração com Google Drive API via Service Account
- Listagem automática de arquivos da pasta do Drive
- Separação automática de vídeos e áudios
- Transcrição de todos os áudios via Groq API (Whisper Large v3) — um parágrafo por áudio
- Seleção automática do primeiro vídeo (ordem alfabética) para exibição no card
- Exibição da transcrição para edição antes de salvar
- Página de visualização com cards
- Filtros dinâmicos e combináveis (nível, região, curso, tag, profissão, data)
- Busca por nome do aluno
- Listagem agrupada por curso
- Gestão de cursos e tags

### 3.2 Fora do Escopo (v1)

- Hospedagem de vídeos ou áudios no sistema
- Acesso público à página de depoimentos
- Submissão de depoimentos pelos próprios alunos
- Integração automática com plataformas de curso
- Role `editor_depoimentos` (versão futura)

---

## 4. Níveis do Ecossistema

Gerenciados em `thb_alunos`, lidos via FK — sem duplicidade neste módulo.

| Nível | Elegível a Placa? |
|---|---|
| Iniciante | Não |
| Pessoal | Não |
| Em Formação | Não |
| Profissional | Não |
| Ouro | Sim |
| Platina | Sim |
| Diamante | Sim |
| Diamante Vermelho | Sim |

---

## 5. Módulo de Transcrição

### 5.1 Visão Geral

O admin cola um único link de pasta do Google Drive no formulário e clica em "Processar pasta". O sistema usa a Google Drive API (autenticada via Service Account) para listar os arquivos, identificar vídeos e áudios, transcrever cada áudio via Groq API e preencher o textarea de transcrição com um parágrafo por áudio. O primeiro vídeo encontrado (ordem alfabética) é salvo como `video_url` para exibição no card.

### 5.2 Stack do Módulo

| Componente | Tecnologia |
|---|---|
| Listagem de arquivos da pasta | Google Drive API v3 — Service Account |
| Download dos áudios | Google Drive API v3 (download direto pelo ID do arquivo) |
| Transcrição | Groq API — Whisper Large v3 (idioma: `pt`) |
| Orquestração | PHP (`app/api/depoimentos/processar-pasta.php`) |
| Retorno ao formulário | JSON via fetch JS |

### 5.3 Configuração da Service Account

1. Criar projeto no Google Cloud Console (gratuito)
2. Ativar a Google Drive API
3. Criar uma Service Account e baixar o arquivo JSON de credenciais
4. Armazenar o JSON de credenciais fora do diretório público (`/credentials/google-service-account.json`)
5. Para cada pasta do Drive usada no sistema: **compartilhar a pasta com o e-mail da Service Account** (acesso de leitor)
6. A pasta pode continuar privada para o público — a Service Account acessa via permissão direta

> A pasta **não precisa ser pública**. O compartilhamento é feito uma vez por pasta com o e-mail da Service Account.

### 5.4 Fluxo Técnico Detalhado

```
[Admin cola link da pasta do Drive]
        │
        ▼
[JS extrai o ID da pasta do link]
        │
        ▼
[POST → app/api/depoimentos/processar-pasta.php]
        │
        ├── Autentica com Service Account (JSON de credenciais)
        ├── Lista arquivos da pasta via Drive API v3
        ├── Separa arquivos por MIME type:
        │     ├── Vídeos: video/mp4, video/quicktime, video/webm, etc.
        │     └── Áudios: audio/mpeg, audio/mp4, audio/wav, audio/webm, etc.
        │
        ├── VÍDEOS:
        │     └── Seleciona o primeiro em ordem alfabética → salva URL de visualização
        │
        └── ÁUDIOS (para cada áudio, em ordem alfabética):
              ├── Baixa o arquivo via Drive API
              ├── Envia para Groq API (Whisper Large v3, lang: pt)
              ├── Recebe transcrição
              └── Deleta arquivo temporário do servidor
        │
        ▼
[Retorna JSON]:
{
  "video_url": "https://drive.google.com/file/d/.../view",
  "transcript": "Parágrafo 1 (áudio 1).\n\nParágrafo 2 (áudio 2)."
}
        │
        ▼
[JS preenche campo video_url e textarea de transcrição]
        │
        ▼
[Admin revisa e edita a transcrição]
        │
        ▼
[Admin salva o depoimento]
```

### 5.5 Regras de Separação de Arquivos

| Tipo | MIME Types aceitos | Ação |
|---|---|---|
| Vídeo | `video/mp4`, `video/quicktime`, `video/x-msvideo`, `video/webm`, `video/mpeg` | Primeiro em ordem alfabética → `video_url` |
| Áudio | `audio/mpeg`, `audio/mp4`, `audio/wav`, `audio/webm`, `audio/x-m4a` | Todos transcritos → um parágrafo cada |
| Outros | Qualquer outro MIME | Ignorados silenciosamente |

### 5.6 Geração da Transcrição

- Cada áudio gera um parágrafo separado
- Parágrafos são separados por linha em branco (`\n\n`)
- A ordem dos parágrafos segue a ordem alfabética dos arquivos de áudio na pasta
- O textarea é preenchido com todos os parágrafos concatenados
- O admin pode editar livremente antes de salvar

**Exemplo de resultado:**
```
Eu comecei o curso sem saber nada sobre finanças, e em três meses já tinha 
organizado toda a minha empresa. Foi transformador.

A metodologia do Grupo Participa mudou completamente a forma como eu vejo 
os negócios. Recomendo para todo empresário que quer crescer de verdade.
```

### 5.7 UX do Transcritor no Formulário

- Campo: `Link da pasta do Google Drive` — input texto
- Botão: `Processar pasta` — dispara o processo via fetch
- Estado de loading: botão desabilitado + spinner + texto *"Buscando arquivos e transcrevendo áudios, aguarde..."*
- Após retorno:
  - Campo `video_url` preenchido automaticamente com o link do primeiro vídeo
  - Textarea de transcrição preenchido com os parágrafos
  - Mensagem: *"Processamento concluído. X áudio(s) transcritos. Revise e edite se necessário."*
- Erros tratados individualmente:
  - Pasta não encontrada ou sem acesso: *"Não foi possível acessar a pasta. Verifique se ela foi compartilhada com a Service Account."*
  - Nenhum áudio encontrado: *"Nenhum arquivo de áudio encontrado na pasta."*
  - Nenhum vídeo encontrado: campo `video_url` fica vazio, admin preenche manualmente
  - Falha em um dos áudios: parágrafo substituído por *"[Falha na transcrição deste áudio]"*

### 5.8 Segurança e Boas Práticas

- JSON de credenciais da Service Account armazenado fora do `public_html`
- API key do Groq em variável de ambiente (nunca exposta no front-end)
- Arquivos de áudio temporários deletados imediatamente após a transcrição
- Nenhum arquivo de vídeo é baixado para o servidor (apenas a URL é salva)
- Limite Groq: 2h de áudio/dia no plano gratuito — suficiente para cadastro manual

---

## 6. Entidades e Modelo de Dados

### 6.1 `thb_alunos` — Tabela existente (somente leitura)

| Campo | Uso no módulo |
|---|---|
| `id` | PK referenciada em `gp_depoimentos` |
| `nome` | Exibição no card e busca |
| `email` | Identificação / busca |
| `cidade` | Filtro de região |
| `estado_uf` | Filtro de região |
| `nivel` | Filtro de nível / badge no card |
| `turma` | Filtro / exibição |
| `profissao` *(se existir)* | Filtro de profissão |

### 6.2 `gp_depoimentos` — Depoimentos

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | UUID | PK |
| `aluno_id` | UUID | FK → `thb_alunos.id` |
| `foto_url` | TEXT | URL da foto do aluno |
| `social_handle` | VARCHAR | @ ou link de rede social |
| `drive_folder_url` | TEXT | Link da pasta do Drive (fonte dos arquivos) |
| `video_url` | TEXT | Link do primeiro vídeo (gerado automaticamente) |
| `transcript` | TEXT | Transcrição revisada (um parágrafo por áudio) |
| `testimonial_date` | DATE | Data do depoimento |
| `created_by` | UUID | FK → usuário que cadastrou |
| `created_at` | TIMESTAMP | — |
| `updated_at` | TIMESTAMP | — |

### 6.3 `gp_cursos` — Cursos

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | UUID | PK |
| `name` | VARCHAR | Nome do curso |
| `slug` | VARCHAR | Slug para URL/âncora |
| `active` | BOOLEAN | Curso ativo? |

### 6.4 `gp_tags` — Tags

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | UUID | PK |
| `label` | VARCHAR | Nome da tag |
| `color` | VARCHAR | Cor hex (opcional) |

### 6.5 `gp_depoimento_cursos` — Vínculo N:N

| Campo | Tipo |
|---|---|
| `depoimento_id` | UUID FK → `gp_depoimentos` |
| `curso_id` | UUID FK → `gp_cursos` |

### 6.6 `gp_depoimento_tags` — Vínculo N:N

| Campo | Tipo |
|---|---|
| `depoimento_id` | UUID FK → `gp_depoimentos` |
| `tag_id` | UUID FK → `gp_tags` |

---

## 7. Integração com thb_alunos

- `gp_depoimentos.aluno_id` referencia `thb_alunos.id` via FK direta
- Dados do aluno (nome, nível, cidade, turma) são lidos via JOIN em tempo real
- No formulário: admin busca por nome ou e-mail → preview com dados de `thb_alunos`
- Este módulo **não escreve** em `thb_alunos`
- Se `profissao` não existir em `thb_alunos`, adicionar como campo em `gp_depoimentos`

---

## 8. Filtros Dinâmicos para Copy

Todos os filtros são combináveis entre si. Nenhum é obrigatório.

| Dimensão | Origem |
|---|---|
| Nível | `thb_alunos.nivel` |
| Estado | `thb_alunos.estado_uf` |
| Cidade | `thb_alunos.cidade` |
| Curso | `gp_cursos` |
| Tag | `gp_tags` |
| Profissão | `thb_alunos.profissao` ou campo próprio |
| Data do depoimento | `gp_depoimentos.testimonial_date` |
| Nome | `thb_alunos.nome` |
| Turma | `thb_alunos.turma` |

---

## 9. Permissões

| Role | Acesso |
|---|---|
| `admin` | CRUD completo, transcritor, gestão de cursos e tags |
| Demais roles | Sem acesso (v1) |

> Role `editor_depoimentos` planejada para versão futura.

---

## 10. Funcionalidades

### 10.1 Página de Visualização (`/depoimentos`)

- Cards com: foto, nome, cidade/estado, profissão, turma, nível (badge), curso(s), tags, data, @, trecho da transcrição (expansível), link do vídeo
- Painel de filtros combinados
- Busca por nome
- Agrupamento por curso

### 10.2 CRUD de Depoimentos (`/admin/depoimentos`)

- Listagem tabular com paginação
- Formulário com:
  - Busca de aluno em `thb_alunos` + preview dos dados
  - Foto (URL) e @ social
  - Campo de link da pasta do Drive + botão "Processar pasta"
  - Campo `video_url` (preenchido automaticamente, editável)
  - Textarea de transcrição (preenchida automaticamente, editável)
  - Vínculo com cursos e tags
  - Data do depoimento
- Confirmação antes de excluir

### 10.3 Gestão de Cursos e Tags

- `/admin/depoimentos/cursos` — criar, editar, ativar/desativar
- `/admin/depoimentos/tags` — criar, editar, excluir (com alerta se em uso)

---

## 11. Stack Técnica

| Camada | Tecnologia |
|---|---|
| Front-End | HTML, CSS, JavaScript vanilla |
| Back-End | PHP |
| Banco de Dados | Supabase (PostgreSQL) |
| Autenticação do sistema | Sistema legado existente |
| Acesso ao Drive | Google Drive API v3 — Service Account |
| Transcrição | Groq API — Whisper Large v3 |
| Credenciais | JSON fora do `public_html` + variáveis de ambiente |

---

## 12. Mapa no Repositório

| Tipo | Caminho |
|---|---|
| PRD | `docs/projetos/depoimentos/prd.md` |
| SPEC | `docs/projetos/depoimentos/spec.md` |
| Credenciais Google (fora do deploy) | `credentials/google-service-account.json` |
| Página de visualização | `app/depoimentos/index.html` |
| CRUD admin | `app/admin/depoimentos/index.html` |
| Gestão de cursos | `app/admin/depoimentos/cursos.html` |
| Gestão de tags | `app/admin/depoimentos/tags.html` |
| API — processar pasta | `app/api/depoimentos/processar-pasta.php` |
| API — CRUD depoimentos | `app/api/depoimentos/` |

---

## 13. Critérios de Aceite

- [ ] Admin cola link de pasta do Drive e o sistema lista, separa e processa os arquivos automaticamente
- [ ] Cada áudio gera um parágrafo separado no textarea de transcrição
- [ ] O primeiro vídeo (ordem alfabética) é salvo em `video_url` automaticamente
- [ ] Pasta sem áudio exibe mensagem clara; campo de vídeo fica vazio se não houver vídeo
- [ ] Admin consegue editar a transcrição antes de salvar
- [ ] Admin consegue vincular depoimento a aluno via busca em `thb_alunos`
- [ ] Filtros são combináveis livremente
- [ ] Usuário sem autenticação não acessa nenhuma rota do módulo
- [ ] Arquivos temporários de áudio são deletados após a transcrição
- [ ] Credenciais da Service Account e API key do Groq não são expostas no front-end

---

## 14. Pontos em Aberto

| Ponto | Observação |
|---|---|
| Campo `profissao` em `thb_alunos` | Verificar se existe; se não, adicionar em `gp_depoimentos` |
| Soft delete de aluno | Comportamento quando aluno for removido de `thb_alunos` |
| Foto do aluno | URL externa ou upload para Supabase Storage |
| Filtros em tempo real vs submit | Definir conforme performance |
| Design visual dos cards e badges | Seguir identidade visual do sistema |
| Lib Python existente | Avaliar se tem utilidade neste módulo |
| `credentials/` no `.gitignore` | Garantir que o JSON da Service Account nunca suba para o repositório |

---

## 15. Próximos Passos

1. Validar PRD com o time
2. Criar projeto no Google Cloud, ativar Drive API e gerar Service Account
3. Criar conta Groq e gerar API key
4. Inspecionar `thb_alunos` (campos disponíveis, tipo do `id`, campo `profissao`)
5. Criar tabelas `gp_*` no Supabase
6. Implementar `processar-pasta.php` e testar com pasta real do Drive
7. Implementar formulário de cadastro com transcritor integrado
8. Implementar página de visualização com filtros
9. Garantir que `credentials/` está no `.gitignore` antes do primeiro commit
