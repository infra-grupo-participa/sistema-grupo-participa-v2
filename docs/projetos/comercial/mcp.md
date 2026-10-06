# MCP do Comercial — conectar o CRM ao Claude (F7)

> Versão de 06/10/2026. **Status: migration `20261006050132` APLICADA (MCP desligado: mcp_ligado=false), código sem deploy.**
> Banco: `infra/supabase/migrations/20261006050132_crm_f7_mcp.sql` (+ `20261006050132_ensaio.sql`, `20261006050132.explain.md`).
> Servidor: `web/app/api/mcp/route.ts` → `web/modules/comercial/application/mcp-servidor.ts`.

## 1. O que é

Um servidor MCP remoto em `https://grupoparticipa.app.br/api/mcp`. Cada pessoa do Comercial gera um **token pessoal**
e conecta o Claude. O Claude passa a consultar o CRM e, se o token permitir, registrar atividade, nota e mover etapa.

**Tudo roda como a dona do token.** O servidor troca o token por um JWT curto (5 min) da própria pessoa e chama as
MESMAS RPCs `public.crm_*` da tela. RLS, guardas e `crm.config.escrita_ligada` decidem, igual à tela:
vendedor vê os próprios leads e os sem dono; gestor (dev/admin, ou cargo gestor com área comercial) vê o time.
Service role só é usada para validar o token (`crm_mcp_autenticar`), nunca para agir.

## 2. Ferramentas

| Ferramenta | Escopo | O que faz | RPC |
|---|---|---|---|
| `comercial_listar_funis` | ler | Funis ativos com etapas (ids) | `crm_funis` |
| `comercial_resumo_funil` | ler | Abertos por etapa (qtd, valor, sem dono, SLA estourado) + ganhos/perdidos 30 d | `crm_funil_resumo` |
| `comercial_negocios_por_etapa` | ler | Negócios de um funil/etapa com próxima atividade (até 200) | `crm_negocios` |
| `comercial_buscar_pessoa` | ler | Busca por e-mail, telefone ou nome (≥ 3 caracteres, até 20) | `crm_contatos` |
| `comercial_pessoa_jornada` | ler | Jornada + negócios + atividades da pessoa | `crm_jornada`, `crm_negocios`, `crm_atividades` |
| `comercial_atividades_do_dia` | ler | Do dia, atrasadas e concluídas no dia (Brasília) | `crm_atividades` |
| `comercial_desempenho` | ler | Por dono: abertos, criados, ganhos/valor, perdidos, conversão, atividades | `crm_desempenho` |
| `comercial_criar_atividade` | operar | Agenda whatsapp/ligação/e-mail/tarefa/reunião | `crm_criar_atividade` |
| `comercial_adicionar_nota` | operar | Nota interna na pessoa/negócio | `crm_adicionar_nota` |
| `comercial_mover_etapa` | operar | Move negócio (Ganho recusado; campos obrigatórios exigidos) | `crm_mover_etapa` |

**De propósito, não existe:** marcar ganho/perdido, transferir dono, disparo, editar funil/motivo/produto/oferta,
exportar lista. Nunca sai CPF. E-mail/telefone completos só para a dona do contato ou gestor (o resto vem mascarado).
Toda escrita fica no Registro do CRM com `autor_tipo = mcp` e o nome da dona do token.

## 3. Pré-requisitos (uma vez, pelo Arthur)

1. Aplicar `20261006050132` (checklist no `.explain.md` §6). Para as ferramentas de escrita: F2 (`20261005t`) aplicada e
   `crm.config.escrita_ligada = true`.
2. Na Hostinger (variável de ambiente, nunca em arquivo): `SUPABASE_JWT_SECRET` = "Legacy JWT secret" do projeto
   (Supabase → Project Settings → JWT Keys). Deploy do `web/`.
3. Ligar: `update crm.config set mcp_ligado = true;` (desligar = `false`, vale em ~10 s para todos os tokens).

## 4. Gerar token

O token tem o formato `gpc_` + 64 caracteres hex, aparece **uma vez** e o banco guarda só o sha-256.
Regras: até 5 ativos por pessoa, validade de 1 a 180 dias (padrão 90), escopo `ler` ou `ler` + `operar`.

- **Tela:** ainda não existe (próximo passo: um bloco "Conectar ao Claude" em `/comercial/configuracoes` chamando
  `crm_mcp_criar_token`, `crm_mcp_tokens` e `crm_mcp_revogar_token` pelo supabase-js do navegador).
- **Enquanto isso (só para o próprio Arthur),** no SQL editor do Supabase, numa transação:

  ```sql
  begin;
  select set_config('request.jwt.claims', json_build_object('sub', '<SEU perfil_id>', 'role', 'authenticated')::text, true);
  set local role authenticated;
  select public.crm_mcp_criar_token('Claude Code notebook', array['ler', 'operar'], 30);
  commit;
  ```

  Copie o `token` do resultado direto para o cliente. Não gere token de outra pessoa por aqui (você veria o token dela).

Revogar: `crm_mcp_revogar_token(<id>)` (a própria pessoa ou gestor; funciona mesmo com o MCP desligado).
Vendedor inativado em `crm.vendedor` ou perfil não ativo perde o acesso na hora, sem revogar.

## 5. Conectar

### Claude Code

```bash
claude mcp add --transport http comercial https://grupoparticipa.app.br/api/mcp \
  --header "Authorization: Bearer gpc_SEU_TOKEN"
```

### Claude Desktop

Configurações → Desenvolvedor → Editar config (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "comercial": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://grupoparticipa.app.br/api/mcp",
               "--header", "Authorization: Bearer ${GP_MCP_TOKEN}"],
      "env": { "GP_MCP_TOKEN": "gpc_SEU_TOKEN" }
    }
  }
}
```

### claude.ai (web) e app do celular

Conector personalizado do claude.ai só aceita OAuth. Com token Bearer **não conecta**. Caminho para a v2: servidor
OAuth 2.1 do Supabase Auth + tela de consentimento no app (ver `.explain.md` §7).

### Testar sem o Claude

```bash
curl -s https://grupoparticipa.app.br/api/mcp -H "Authorization: Bearer gpc_SEU_TOKEN" \
  -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## 6. Protocolo e limites

- MCP Streamable HTTP **stateless**: só `POST` com uma mensagem JSON-RPC; resposta JSON (sem SSE, sem sessão,
  sem lote). Versões: `2025-06-18` (padrão), `2025-03-26`, `2024-11-05`. `GET`/`DELETE` → 405.
- Limites: 60 chamadas de ferramenta por minuto por token (no banco, `crm.mcp_chamada`); 300 requisições/min por IP
  (memória do servidor); corpo até 64 KB. `Origin` de site de terceiro → 403.
- Respostas HTTP: 401 token inválido/revogado/expirado (com `WWW-Authenticate`), 403 perfil fora do Comercial,
  503 MCP desligado ou servidor sem `SUPABASE_JWT_SECRET`. Erro de regra do CRM (ex.: "Este negócio não é seu.",
  "CRM em manutenção: escrita desligada.") volta como erro da ferramenta, com a mesma mensagem da tela.

## 7. Auditoria

- `crm.mcp_chamada`: quem (token, perfil), qual ferramenta, quando. Expurgo à mão > 180 dias.
- `crm.log`: toda escrita feita pelo MCP com `autor_tipo = 'mcp'`, `canal = 'mcp'`, autor = dona do token.
- `crm.mcp_token.ultimo_uso_em` (atualizado no máximo 1×/min).

## 8. Riscos

Ver `.explain.md` §7: dado do CRM sai para o Claude (decisão LGPD antes de ligar), segredo HS256 legado no servidor
(poder de service role), claude.ai web sem OAuth, tela de tokens pendente.
