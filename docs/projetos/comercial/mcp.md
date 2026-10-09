# MCP do Comercial — conectar o CRM ao Claude (F7)

> Versão de 09/10/2026 (playbook no MCP). **Status: no ar.** `crm.config.mcp_ligado = true`.
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
atividade, move etapa e **envia WhatsApp** (um por vez, sempre depois da sua confirmação).

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
| "Resuma a conversa de WhatsApp com a Ana e sugira a próxima mensagem." | Lê as mensagens e escreve resumo + sugestão. |
| "Abre conversa com o João Lima pelo número 2536 e manda: Oi João, tudo bem?…" | Mostra texto final, número (2536, QR) e destinatário; envia só depois do seu "pode enviar". QR = texto livre direto. |
| "Manda o template boas_vindas_ht para a Ana pelo número oficial." | Mostra a prévia já com o primeiro nome, o número e o destinatário; envia depois do seu ok. |
| "A Ana respondeu no oficial? Posso mandar texto livre?" | Diz se a janela de 24 h daquele número está aberta (e até quando) ou se precisa template. |
| "Quais números eu posso usar? Quais templates falam de aula?" | Lista números (Oficial/QR, status, 4 últimos dígitos) e templates aprovados com prévia. |
| "Crie uma ligação para a Ana amanhã às 10h: retomar proposta." | Agenda a atividade (depois de você confirmar). |
| "Anote na Ana: pediu desconto, vai falar com o sócio." | Registra a nota. |
| "Marque como feita a ligação da Ana, resultado: atendeu." | Conclui a atividade. |
| "Marquei por engano, reabra a ligação da Ana." | Reabre a atividade (volta para a agenda, sem resultado). |
| "Cadastre o João Lima, (21) 98765-4321." | Cria o contato. Se o telefone/e-mail já estiver no CRM, não duplica: devolve o existente. |
| "Corrija o e-mail da Ana para ana@escritorio.com." | Edita a ficha (o dado antigo fica guardado). |
| "Coloque a tag quente na Ana e tire a tag frio." | Adiciona/remove tags. |
| "Mova o negócio da Ana para Negociação." | Move de etapa, com as exigências da tela. |
| "Marca o João como contador começando em holding." (também por voz, no app do celular) | Preenche os campos do negócio e mostra o que mudou. Entende "contadora", "começando", "Holding Total", "Clínica Miami", "no pix". |
| "Lê a conversa da Maria e preenche o perfil." | Sugere os campos com o trecho da conversa que justifica cada um; grava só depois do seu ok. |
| "Resume este link: https://grupoparticipa.app.br/comercial/conversas?contato=…" | Abre o lead do link (conversa ou negócio): contato, negócios, próximas atividades, notas e últimas mensagens. Sem acesso: "Você não tem acesso a este lead." |
| "Como está o funil HT? E o meu desempenho na semana?" | Resumo por etapa e números do período. |
| "O que o playbook diz para a objeção 'está caro'?" | Busca no playbook e responde com o roteiro e os scripts de objeção, citando a seção. |
| "Qual o roteiro da etapa Qualificar?" | Lê no playbook o que a etapa pede (o que fazer, critério para avançar, prazo) e cita a seção. |
| "Me ajuda a responder a Ana, que achou caro. Segue o playbook." | Consulta o playbook antes de sugerir; mostra a seção usada; só envia se você pedir e confirmar. |
| "Como eu marco motivo de perda no sistema?" | Consulta a central de ajuda e explica o passo a passo da tela. |

Dica: comece o dia com "o que eu tenho para hoje e quem está sem próximo passo?".

## O que o Claude não faz

- Não envia WhatsApp **sem a sua confirmação**, não envia e-mail, não faz disparo em massa. Não apaga contato (aguarda decisão).
- WhatsApp só para contato seu (gestor: do time), nunca para quem pediu para sair; até 30 por hora por pessoa e 1 a cada
  20 s para o mesmo contato; nos números QR valem também os limites contra banimento.
- Número oficial: texto livre só com a janela de 24 h aberta naquele número; fora dela, só template aprovado.
- Não marca ganho nem perdido, não troca dono, não mexe em funil, produto, oferta ou motivo.
- Não vê CPF. E-mail e telefone completos só para o dono do contato ou o gestor.
- Não vê o que você não vê na tela. Não exporta lista de contatos.

## Cuidados (LGPD)

- Dado de cliente é dado pessoal. Use o Claude só para o atendimento. Não peça listas para copiar para fora.
- Conecte só com o **seu** login do sistema. Nunca com o de outra pessoa.
- Tudo que o Claude grava fica no Registro do CRM com o seu nome e "via Claude". Você responde pelo que ele registra.
- WhatsApp enviado pelo Claude sai no seu nome, aparece na conversa com "via Claude" e no Registro. Confira texto,
  número e destinatário antes de dizer "pode enviar". Nada de massa: disparo é pela ficha, no número oficial.
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
claims voltam ao fim. Lista fechada de 20 RPCs (8 ler + 12 operar; migrations 20261008222038 e 20261008233100); parâmetros só pelos nomes da assinatura viva (valor vira literal
tipado: injeção vira erro de tipo; parâmetro `text[]` aceita array JSON, que vira `array(select jsonb_array_elements_text(…))`). RLS, guardas, `escrita_ligada` e o `crm.tg_log` (`autor_tipo='mcp'`) valem igual.

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
| `comercial_reabrir_atividade` | operar | Desfaz a conclusão (dono da atividade ou gestor) | `crm_reabrir_atividade` |
| `comercial_criar_contato` | operar | Nome + telefone e/ou e-mail; duplicado devolve o existente (`nova=false`), sem trocar dono | `crm_criar_contato` |
| `comercial_editar_contato` | operar | Nome, telefone, e-mail, cidade/UF, perfil, holding, empresa, observação (D6) | `crm_editar_contato` |
| `comercial_tag_adicionar` | operar | Adiciona tags normalizadas (≤ 30 por contato; D6) | `crm_tags_contato` |
| `comercial_tag_remover` | operar | Remove tags pela forma normalizada (D6) | `crm_tags_contato` |
| `comercial_numeros_whatsapp` | operar (consulta) | Números que a pessoa pode usar: nome, Oficial/QR, status, 4 últimos dígitos, envia?, limites | `crm_mcp_numeros` |
| `comercial_templates_whatsapp` | operar (consulta) | Templates aprovados do oficial: nome, idioma, variáveis, prévia (busca, até 200) | `crm_mcp_templates` |
| `comercial_situacao_conversa` | operar (consulta) | Texto livre × template por número, quando a janela fecha, destinatário, bloqueios, prévia do template | `crm_mcp_situacao_conversa` |
| `comercial_enviar_whatsapp` | operar | 1 mensagem a 1 contato: texto OU template, `chave_idempotencia` obrigatória. Descrição exige confirmação explícita | `crm_mcp_enviar_whatsapp` |
| `comercial_campos_negocio` | ler | Campos do negócio (rótulo, opções, valor) + próxima etapa e o que ela exige (`faltando`) | `crm_mcp_negocio_campos` |
| `comercial_preencher_campos` | operar | `{chave: valor}` em fala natural, normalizado em `domain/campos-negocio.ts`; banco valida contra `crm.campo_def`/`crm.linha` e grava pela RPC da tela; devolve `mudou` | `crm_mcp_preencher_campos` → `crm_salvar_campos` |
| `comercial_sugerir_campos` | ler | Sugestões (campo, valor, trecho, fonte) pelas mensagens do cliente e notas; heurística determinística, sem LLM; não grava | `crm_mcp_lead` |
| `comercial_abrir_link` | ler | Link `…/comercial/conversas?contato=` ou `…/comercial/funil?negocio=` (só grupoparticipa.app.br/localhost, UUID válido) → contato, negócios com campos, próximas atividades, notas (20), mensagens | `crm_mcp_lead` |

### Campos do negócio, sugestão e link (pedido do Marcos Paulo, 09/10/2026; migration 20261009153128)

- **Gravar = a mesma RPC da tela.** `crm_mcp_preencher_campos` (INVOKER) valida cada chave contra `crm.campo_def` ativo
  (opção dentro de `opcoes`; tipo `linha` = chave de `crm.linha` ativa; texto ≤ 200; `""`/null limpa) e chama
  `public.crm_salvar_campos` com o JWT do usuário: `crm.guarda_escrita()` (leitor recusa, `escrita_ligada`), dono do
  negócio ou gestor, `crm.log` com canal `mcp`. Devolve `mudou: [{chave, rotulo, de, para}]` e a próxima etapa.
  `crm_salvar_campos` continua FORA da lista do MCP.
- **Normalização** é pura (`web/modules/comercial/domain/campos-negocio.ts`, com teste): "é contadora" → contador;
  "começando" → comecando; "Holding Total" → ht; "Clínica Miami" → clinica_miami; "no pix" → pix. O que não reconhece vira
  slug e o banco recusa listando as opções válidas.
- **Sugestão sem LLM no servidor:** `sugerirCampos` (mesmo arquivo) procura pistas (OAB/advogad*, CRC/contador*,
  "já faço holding", "estou começando", nome de produto, forma de pagamento, objeção) só nas mensagens do **cliente** e nas
  notas (a fala da equipe tem pitch com "advogados e contadores"). Devolve o trecho; valores conflitantes voltam todos.
  Quem decide é o Claude do usuário, que propõe e só grava com `comercial_preencher_campos` depois do sim.
- **Link:** `domain/link-crm.ts` aceita só `https://grupoparticipa.app.br` (ou `www.`) e `http(s)://localhost|127.0.0.1`,
  caminho `/comercial/…`, sem usuário/senha, um único `contato` ou `negocio` UUID. A permissão é do banco:
  `crm_mcp_lead` (INVOKER) resolve o negócio pela RLS de `crm.negocio`, exige `crm.pode_ver_pessoa` e reaproveita
  `crm_contatos_por_ids`, `crm_negocios`, `crm_atividades` (abertas), `crm.nota` (RLS, 20 últimas) e `crm_mensagens`.
  Sem acesso ou id inexistente: `{ok:false, msg:'Você não tem acesso a este lead.'}` (o servidor transforma qualquer
  `ok:false` de leitura em erro da ferramenta).
- Medido (`explain analyze`, 2×, Arthur, negócio real): `crm_mcp_negocio_campos` 9,5 → 4,4 ms; `crm_mcp_lead` (100
  mensagens) 69 → 37 ms.

### WhatsApp pelo Claude (decisão do Arthur, 08/10/2026; migration 20261008233100)

Travas **no banco** (`crm_mcp_enviar_whatsapp`, SECURITY DEFINER), nesta ordem: `crm.guarda_escrita()` (leitor,
`escrita_ligada`) → só com claim `gp_canal='mcp'` (a tela continua em `crm_enviar_mensagem`, que segue fora da lista do
MCP) → kill-switch `crm.config.mcp_envio_ligado` (default true, independente de `envio_ligado`) → chave de
idempotência obrigatória (mesma chave = mesma mensagem, antes dos limites) → D6 (`crm.pode_escrever_pessoa`) → opt-out
→ limites do MCP com advisory lock: `mcp_envio_limite_hora` (30/usuário/h) e `mcp_envio_intervalo_contato_s` (20 s por
contato) → número (pedido; senão conversa mais recente não excluída; senão o oficial) → template só no oficial, aprovado,
até 1 variável ({{1}} = primeiro nome, como na tela; 2+ = ficha de disparo) → oficial sem template exige janela de 24 h
**daquele número** ("precisa template") → `crm_enviar_mensagem` (travas da tela: `envio_ligado`, `evolution_ligado`,
número conectado, anti-ban/massa no trigger `crm.tg_mensagem_canal`) → `crm.mensagem.origem = 'mcp'`.
Registro: `crm.log` com canal/autor_tipo `mcp`, autor = dono do token, resumo sem o texto. A bolha mostra "via Claude".
Fila: `status='na_fila'`; o envio real sai pelo pg_net/cron só depois do COMMIT.
Desligar só o envio: `update crm.config set mcp_envio_ligado = false;`.

### Playbook e central de ajuda (pedido do Arthur, 09/10/2026; sem migration)

| Ferramenta | Escopo | O que faz | RPC |
|---|---|---|---|
| `comercial_playbook_indice` | ler | Seções e subseções do playbook + central de ajuda (id, título, parte, grupo, resumo de 1 linha); `parte` filtra | — |
| `comercial_playbook_ler` | ler | Markdown de uma seção (`conversa`) ou subseção (`conversa/objecoes`); páginas de até 12.000 caracteres (`pagina`, `proximaPagina`) | — |
| `comercial_playbook_buscar` | ler | A mesma busca da tela (`buscarSecoes`: sem acento, todas as palavras, ranking título > sinônimo > resumo > corpo); devolve id, subseção, trecho; até 20 | — |

- **Fonte única:** `web/modules/comercial/domain/playbook/` (`conteudo.ts` = playbook, `ajuda-conteudo.ts` = central, que já
  inclui o playbook inteiro; `busca.ts`). A tela (`ui/playbook/`) e o MCP leem os mesmos arquivos; `mcp-playbook.ts` só
  converte em índice/markdown/páginas/resources. Até 09/10 os três moravam em `ui/playbook/` (já eram dado puro, sem React).
- **Sem banco além do token:** são ferramentas `local` (plano vazio). O pedido passa pelo mesmo `crm_mcp_autenticar`
  (kill-switch, token, perfil do Comercial, limite de 60/min, linha em `crm.mcp_chamada`), escopo `ler`. Nenhuma RPC, por
  isso nada muda em `crm_mcp_rpc`.
- **Resources:** `initialize` anuncia `resources`; `resources/list` devolve uma entrada por seção da central
  (`playbook://comercial/<id>`, `text/markdown`), `resources/templates/list` devolve `playbook://comercial/{id}` (aceita
  subseção `secao/subsecao`), `resources/read` devolve a seção inteira (sem paginar) e conta no limite como
  `recurso_playbook`. URI desconhecida → erro `-32002`.
- **Instruções do servidor** pedem ao Claude: consultar o playbook antes de sugerir abordagem, roteiro, resposta a objeção
  ou regra; citar a seção; trecho "a definir"/"a validar" não vale como regra; playbook não é fonte de preço.
- **Fichas de produto:** o app não tem lugar para ficha de produto (a tela Produtos e ofertas mostra só o que vem da
  Hotmart). A Clínica Internacional Diamante (Miami) **não** entrou; fica como sugestão (ficha em `domain/playbook/` +
  seção na central).

**De propósito, não existe:** disparo em massa, apagar contato (aguarda decisão do Arthur), ganho/perdido, transferir dono, editar funil/motivo/produto/
oferta, exportar lista. Nunca sai CPF. Ferramenta nova = `domain/mcp-ferramentas.ts` + teste + RPC na lista fechada de
`crm_mcp_rpc` (migration nova). Exceção: ferramenta `local` (só conteúdo do app, plano vazio) não precisa de RPC.

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
   `operar` opcional, marcado por padrão; a tela diz que "escrever" inclui enviar WhatsApp). "Permitir" → `crm_mcp_oauth_autorizar` (código de 64 hex, uso único, 5 min,
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

- Dado do CRM sai para o Claude (Anthropic): decisão LGPD do gestor; o MCP não exporta lista.
- Envio ao cliente pelo Claude: a confirmação antes de enviar é regra da descrição da ferramenta (o servidor não vê a
  conversa); o que o banco garante é D6, opt-out, janela, limites, idempotência e o registro "via Claude".
- `crm_mcp_rpc` impersona o dono a partir da service role: mesmo poder que o JWT assinado tinha, sem segredo novo
  fora do Supabase. Protegido por grant (só service_role), lista fechada e conferência do token dentro da função.
- Registro dinâmico é aberto, mas inútil para terceiros: o redirect só pode ser o Claude ou a máquina de quem consente.
- Na tela de tokens, conexão OAuth aparece pela validade do refresh (`crm_mcp_tokens.expiraEm`, campo `oauth`).
