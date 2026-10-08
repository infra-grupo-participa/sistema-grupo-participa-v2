# MCP do Comercial — conectar o CRM ao Claude (F7)

> Versão de 08/10/2026. **Status: no ar.** `crm.config.mcp_ligado = true`.
> Banco: `20261006050132_crm_f7_mcp` (tokens, auditoria, canal `mcp`), `20261008150823_crm_mcp_oauth` (execução sem
> segredo JWT + OAuth 2.1 próprio) e `20261008151421_crm_mcp_tokens_oauth` (lista de conexões) — todas APLICADAS.
> Servidor: `web/app/api/mcp/route.ts` → `web/modules/comercial/application/mcp-servidor.ts`.
> OAuth: `web/app/.well-known/*`, `web/app/oauth/autorizar`, `web/app/api/oauth/{registrar,token}`,
> `web/modules/comercial/{domain,application}/mcp-oauth.ts`.

**Parte 1 é o guia para o time** (Jonathan, Marcos Paulo, Jusy). O mesmo texto está na central de ajuda do CRM
(Playbook › Central de ajuda › Conectar ao Claude). Parte 2 é técnica.

---

# Parte 1 — Guia para o time comercial

## O que é

O Claude vira um assistente do seu CRM. Você pergunta em português e ele busca no sistema: sua agenda, seus negócios,
o histórico de uma pessoa, a conversa de WhatsApp dela. Se você deixar, ele também agenda atividade, anota, conclui
atividade e move etapa.

Ele entra **como você**: vê só o que você já vê na tela, com as mesmas regras. Vendedor vê os próprios leads e os sem
dono; gestor vê o time.

## Como conectar

### claude.ai (navegador) — uma vez só

1. Entre no **claude.ai** com a sua conta do Claude.
2. **Configurações › Conectores › Adicionar conector personalizado**.
3. Nome: **CRM Comercial**. URL: **`https://grupoparticipa.app.br/api/mcp`**. Clique em **Adicionar**.
4. Clique em **Conectar**. Abre a tela do nosso sistema: entre com o seu e-mail e senha de sempre.
5. Confira o que o Claude vai poder fazer. Deixe marcado **"Também registrar por mim"** se quiser que ele crie
   atividades e notas. Clique em **Permitir**.
6. Numa conversa nova, confira no botão de ferramentas que o **CRM Comercial** está ligado.

### App do celular e Claude Desktop

Depois do passo acima, o conector aparece sozinho no app do celular e no Claude Desktop (mesma conta). Numa conversa,
ligue o "CRM Comercial" no botão de ferramentas. Se pedir login de novo, entre e clique em Permitir.

### Claude Code (terminal)

```bash
claude mcp add --transport http comercial https://grupoparticipa.app.br/api/mcp
```

Depois, dentro do Claude Code: `/mcp` › `comercial` › **Authenticate**. O navegador abre o login do sistema: entre e
clique em Permitir. Sem navegador? Use um token (abaixo).

### Alternativa: token pessoal

CRM › **Configurações › Conectar ao Claude › Novo token**. Copie na hora (não aparece de novo) e use o comando pronto
da tela (Claude Code ou Claude Desktop via `mcp-remote`). Token é como senha.

### Como desligar

**Configurações › Conectar ao Claude**: a conexão aparece como "Claude: …". Clique em **Revogar** — perde o acesso na
hora. Ou remova o conector no claude.ai.

## O que pedir (exemplos do dia a dia)

| Você pede | O Claude faz |
|---|---|
| "Quais são as minhas atividades de hoje? E as atrasadas?" | Lista a agenda do dia, as atrasadas e o que já foi concluído. |
| "Quais negócios meus estão sem próximo passo?" | Negócios abertos sem atividade agendada, do mais parado para o mais recente. |
| "Quais são os meus negócios na etapa Proposta do funil HT?" | Negócios da etapa, com valor e próxima atividade. |
| "Resuma o histórico da Ana Souza: compras, etapas e notas." | Acha a pessoa e conta a jornada dela. |
| "Resuma a conversa de WhatsApp com a Ana e sugira a próxima mensagem." | Lê as mensagens e escreve resumo + sugestão. **Quem envia é você**, pela tela de Conversas. |
| "Crie uma ligação para a Ana amanhã às 10h: retomar proposta." | Agenda a atividade (depois de você confirmar). |
| "Anote na Ana: pediu desconto, vai falar com o sócio." | Registra a nota. |
| "Marque como feita a ligação da Ana, resultado: atendeu." | Conclui a atividade. |
| "Mova o negócio da Ana para Negociação." | Move de etapa, com as exigências da tela. |
| "Como está o funil HT? E o meu desempenho na semana?" | Resumo por etapa e números do período. |

Dica: comece o dia com "o que eu tenho para hoje e quem está sem próximo passo?".

## O que o Claude não faz

- Não envia WhatsApp nem e-mail, não faz disparo.
- Não marca ganho nem perdido, não troca dono, não mexe em funil, produto, oferta ou motivo.
- Não vê CPF. E-mail e telefone completos só para o dono do contato ou o gestor.
- Não vê o que você não vê na tela. Não exporta lista de contatos.

## Cuidados (LGPD)

- Dado de cliente é dado pessoal. Use o Claude só para o atendimento. Não peça listas para copiar para fora.
- Conecte só com o **seu** login do sistema. Nunca com o de outra pessoa.
- Tudo que o Claude grava fica no Registro do CRM com o seu nome e "via Claude". Você responde pelo que ele registra.
- O Claude pode errar: confira número, data e nome antes de usar com o cliente.
- Celular perdido ou saiu da empresa: revogue a conexão (gestor também pode revogar de qualquer pessoa).

---

# Parte 2 — Técnico

## 1. Como funciona

Servidor MCP remoto em `https://grupoparticipa.app.br/api/mcp` (Streamable HTTP **stateless**: 1 POST = 1 mensagem
JSON-RPC = 1 resposta JSON; sem SSE, sem sessão, sem lote; versões `2025-06-18`, `2025-03-26`, `2024-11-05`).

Credencial = `Authorization: Bearer gpc_<64 hex>`, sempre uma linha de `crm.mcp_token` (o banco guarda só o sha-256):
- **token manual** (tela, 1–180 dias, até 5 ativos por pessoa), ou
- **access token do OAuth** (1 h, renovado pelo refresh `gpr_…` de 30 dias, teto 180 dias desde o consentimento;
  1 conexão ativa por pessoa × cliente).

Por pedido: `crm_mcp_autenticar(hash, ferramenta)` (service role; kill-switch, token, perfil do Comercial via
`crm.mcp_papel`, 60 ferramentas/min/token, auditoria em `crm.mcp_chamada`). Cada RPC da ferramenta vai por
**`public.crm_mcp_rpc(token_id, rpc, params)`** (só service_role): confere o token de novo, monta as claims do dono
(`sub`, `email`, `gp_canal='mcp'`), `SET LOCAL ROLE authenticated` e chama a **mesma** `public.crm_*` da tela; role e
claims voltam ao fim. Lista fechada de 12 RPCs; parâmetros só pelos nomes da assinatura viva (valor vira literal
tipado: injeção vira erro de tipo). RLS, guardas, `escrita_ligada` e o `crm.tg_log` (`autor_tipo='mcp'`) valem igual.

**Mudança de 08/10/2026:** antes o servidor assinava um JWT HS256 com o "Legacy JWT secret" (`SUPABASE_JWT_SECRET`).
A variável nunca foi configurada na Hostinger → `tools/call` dava 503 em produção. A troca por `crm_mcp_rpc` dispensa
o segredo legado (que tem poder de service role e não precisava sair do Supabase). **`SUPABASE_JWT_SECRET` não é
mais usado**; se estiver na Hostinger, pode remover.

## 2. Ferramentas

| Ferramenta | Escopo | O que faz | RPC |
|---|---|---|---|
| `comercial_listar_funis` | ler | Funis ativos com etapas (ids) | `crm_funis` |
| `comercial_resumo_funil` | ler | Abertos por etapa (qtd, valor, sem dono, SLA estourado) + ganhos/perdidos 30 d | `crm_funil_resumo` |
| `comercial_negocios_por_etapa` | ler | Negócios (funil e etapa opcionais; `apenas_meus`), com próxima atividade | `crm_negocios` |
| `comercial_sem_proximo_passo` | ler | Abertos sem atividade agendada, mais parado primeiro (vendedor: os dele) | `crm_negocios` |
| `comercial_buscar_pessoa` | ler | Busca por e-mail, telefone ou nome (≥ 3 caracteres, até 20) | `crm_contatos` |
| `comercial_pessoa_jornada` | ler | Jornada + negócios + atividades da pessoa | `crm_jornada`, `crm_negocios`, `crm_atividades` |
| `comercial_conversa_whatsapp` | ler | Mensagens de WhatsApp da pessoa (até 300; só data, lado, tipo, texto, status) | `crm_mensagens` |
| `comercial_atividades_do_dia` | ler | Do dia, atrasadas e concluídas no dia (Brasília) | `crm_atividades` |
| `comercial_desempenho` | ler | Por dono: abertos, criados, ganhos/valor, perdidos, conversão, atividades | `crm_desempenho` |
| `comercial_criar_atividade` | operar | Agenda whatsapp/ligação/e-mail/tarefa/reunião | `crm_criar_atividade` |
| `comercial_adicionar_nota` | operar | Nota interna na pessoa/negócio | `crm_adicionar_nota` |
| `comercial_concluir_atividade` | operar | Conclui atividade com resultado | `crm_concluir_atividade` |
| `comercial_mover_etapa` | operar | Move negócio (Ganho recusado; campos obrigatórios exigidos) | `crm_mover_etapa` |

**De propósito, não existe:** envio de WhatsApp/disparo, ganho/perdido, transferir dono, editar funil/motivo/produto/
oferta, exportar lista. Nunca sai CPF. Ferramenta nova = `domain/mcp-ferramentas.ts` + teste + RPC na lista fechada de
`crm_mcp_rpc` (migration nova).

## 3. OAuth 2.1 (claude.ai, celular, Desktop, Claude Code com login)

**Por que próprio e não o servidor OAuth do Supabase Auth:** o Supabase monta a tela de consentimento como
*Site URL do projeto + caminho*. O Site URL do projeto é de outro sistema do grupo (`sip.timeholdingbrasil.com.br`,
conferido em 08/10 pelo redirect de `/auth/v1/verify`), e mudar o Site URL quebraria os e-mails daquele sistema. Além
disso o OAuth do Supabase estava desligado e os tokens dele valeriam direto no PostgREST de todo o projeto
compartilhado. O servidor próprio é mínimo e reaproveita `crm.mcp_token` (revogação, kill-switch, limite, auditoria).

Fluxo:
1. `POST /api/mcp` sem token → 401 com `WWW-Authenticate: Bearer resource_metadata=".../.well-known/oauth-protected-resource/api/mcp"`.
2. `GET /.well-known/oauth-protected-resource[/api/mcp]` (RFC 9728) → servidor = `https://grupoparticipa.app.br`.
3. `GET /.well-known/oauth-authorization-server` (RFC 8414): PKCE S256, `token_endpoint_auth_methods_supported: ["none"]`.
4. `POST /api/oauth/registrar` (RFC 7591): cliente público; **redirect só** `https://claude.ai/api/mcp/auth_callback`,
   `https://claude.com/api/mcp/auth_callback` ou loopback `http://localhost|127.0.0.1:<porta>/…`. 10/h por IP, 200/dia no banco.
5. `GET /oauth/autorizar?...` (página, exige sessão da equipe pelo proxy; o login devolve a query): confere cliente +
   redirect + Comercial + MCP ligado (`crm_mcp_oauth_cliente`, JWT da pessoa) e mostra o consentimento (escopo
   `operar` opcional, marcado por padrão). "Permitir" → `crm_mcp_oauth_autorizar` (código de 64 hex, uso único, 5 min,
   só hash no banco, ≤ 20 por pessoa a cada 10 min) → redirect com `code`, `state`, `iss`. "Recusar" → `access_denied`.
6. `POST /api/oauth/token`: `authorization_code` (+ `code_verifier`, conferido como S256 no banco; código repetido
   revoga o que ele emitiu) ou `refresh_token` (rotativo: o anterior deixa de valer). 60/min por IP.

Proxy: `/.well-known` e `/api/oauth` são públicos; `/oauth/autorizar` não.

## 4. Pré-requisitos e operação

- Hostinger: nada novo. Precisa só da `SUPABASE_SERVICE_ROLE_KEY` (já existe). `NEXT_PUBLIC_APP_URL` vazio ou
  `https://grupoparticipa.app.br` (é a base dos metadados OAuth).
- Ligar/desligar: `update crm.config set mcp_ligado = true|false;` (vale em ~10 s para tokens, OAuth, consentimento e renovação).
- Revogar: tela (o próprio ou gestor) ou `crm_mcp_revogar_token(<id>)`.
- Teste rápido: `curl -s https://grupoparticipa.app.br/api/mcp -H "Authorization: Bearer gpc_…" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'`.

## 5. Limites e respostas

60 ferramentas/min por token; 300 req/min por IP no `/api/mcp`; corpo ≤ 64 KB; `Origin` de terceiro → 403 (claude.ai
aceito). 401 token inválido (com `resource_metadata`), 403 perfil fora do Comercial, 503 MCP desligado. Erro de regra
do CRM volta como erro da ferramenta com a mensagem da tela.

## 6. Auditoria

`crm.mcp_chamada` (quem, qual ferramenta, quando; expurgo à mão > 180 d), `crm.log` (`autor_tipo='mcp'`, autor = dono),
`crm.mcp_token.ultimo_uso_em`, `crm.mcp_oauth_cliente` (clientes registrados), `crm.mcp_oauth_codigo` (códigos; os
vencidos há > 1 dia são apagados no próximo consentimento da mesma pessoa).

## 7. Riscos conhecidos

- Dado do CRM sai para o Claude (Anthropic): decisão LGPD do gestor; o MCP não exporta lista e não envia nada ao cliente.
- `crm_mcp_rpc` impersona o dono a partir da service role: mesmo poder que o JWT assinado tinha, sem segredo novo
  fora do Supabase. Protegido por grant (só service_role), lista fechada e conferência do token dentro da função.
- Registro dinâmico é aberto, mas inútil para terceiros: o redirect só pode ser o Claude ou a máquina de quem consente.
- Na tela de tokens, conexão OAuth aparece pela validade do refresh (`crm_mcp_tokens.expiraEm`, campo `oauth`).
