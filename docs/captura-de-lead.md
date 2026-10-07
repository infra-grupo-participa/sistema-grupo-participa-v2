# Captura de lead servidor a servidor (`POST /api/captura/lead`)

**Situação (07/10/2026, fim do dia): rota NÃO PUBLICADA; as quatro migrations de Miami APLICADAS em produção.** O
código está na branch `victor-captura-pre-checkout` (não está na `main`). Aceite do Arthur dado em 07/10 (verbal,
informado pelo Victor). Migrations aplicadas em 07/10/2026 com autorização do Victor, depois do ensaio final da sequência
2× com rollback (0 erro): `20261007152702_pessoas_pre_checkout` (era i), `20261007152751_crm_regra_lista_614_clinica_miami`
(era j), `20261007152825_mkt_projeto_clinica_miami` (era k, CNFMIAMI26) e `20261007152903_mkt_projeto_encontro_diamantes_miami`
(era l, EDIMIAMI26). Prova pós-aplicação em `infra/supabase/migrations/20261007152903.explain.md` §6.

## O que é e por quê

Rota genérica para uma página de captura mandar um lead para a base de pessoas (`pessoas.registrar`, via
`public.pessoas_registrar_lead`, que só o `service_role` executa). Primeiro uso: o pré-checkout da Clínica de Miami
(chave `clinica-miami-2026-12`). O servidor PHP da página (`clinica.timeholdingbrasil.com.br/miami/api/submit.php`) chama
a rota depois de validar o formulário; a página continua gravando a planilha e o ActiveCampaign como hoje.

Por que servidor a servidor: o segredo mora no `config.php` da página (o `.htaccess` nega acesso a ele), nunca no
navegador. A rota não tem CORS de propósito.

## Contrato

```
POST /api/captura/lead
Content-Type: application/json
Authorization: Bearer <CAPTURA_LEAD_SECRET>
```

| Campo | Obrigatório | Regra |
|---|---|---|
| `chave_evento` | sim | minúscula com hífen, até 80 (chave da casa `nome-curto-aaaa-mm`) |
| `tipo` | sim | `lead` ou `pre_checkout` |
| `email` | email ou telefone | até 254, vira minúsculo |
| `telefone` | email ou telefone | 10 a 13 dígitos depois de tirar o que não é dígito (página manda `55` + DDD + número) |
| `nome` | não | 2 a 160 |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | não | até 300 cada |
| `sck`, `xcod` | não | até 200 cada |
| `pagina_origem` | não | até 300; `?query` e `#fragmento` são cortados antes de gravar |
| `teste` | não | `true` marca a pessoa como teste na base |

Corpo até 8 KB. Campo desconhecido é ignorado (ex.: `data` e `hora` que a página manda: vale o horário do banco).

Exemplo com dado fictício:

```bash
curl -sS -m 3 -X POST https://grupoparticipa.app.br/api/captura/lead \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $CAPTURA_LEAD_SECRET" \
  -d '{"chave_evento":"clinica-miami-2026-12","tipo":"pre_checkout","nome":"Pessoa Ficticia",
       "email":"pessoa.ficticia@exemplo.invalid","telefone":"5511900000000",
       "utm_source":"meta","utm_medium":"cpc","utm_campaign":"clinica-miami-2026-12","utm_content":"miami",
       "utm_term":"teste","sck":"sck-ficticio","xcod":"xcod-ficticio",
       "pagina_origem":"https://clinica.timeholdingbrasil.com.br/miami/","teste":true}'
```

## Respostas

| HTTP | Corpo | Quando |
|---|---|---|
| 200 | `{"ok":true}` | gravado (a função confirmou `ok: true`) |
| 400 | `{"error":"…"}` | Content-Type, JSON ou campo inválido (a mensagem cita só o nome do campo), ou a base recusou |
| 401 | `{"error":"Não autorizado."}` | Bearer ausente ou errado |
| 413 | `{"error":"Corpo acima de 8 KB."}` | corpo grande demais |
| 429 | `{"error":"Muitas requisições…"}` | 10 falhas de segredo no mesmo IP em 10 min, ou mais de 20 chamadas autorizadas por minuto no mesmo IP (era 120; baixado em 07/10 pela condição B1 do pentester) |
| 502 | `{"error":"Não foi possível gravar agora."}` | erro do banco (o log do servidor guarda só o código do erro) |
| 503 | `{"error":"Captura indisponível."}` | `CAPTURA_LEAD_SECRET` ausente ou com menos de 32 caracteres |

Nenhuma resposta e nenhum log traz nome, e-mail ou telefone.

## Variável de ambiente

`CAPTURA_LEAD_SECRET`: só servidor (lida em `web/shared/infrastructure/config/env.ts`, `env.captura.leadSecret`), mínimo
32 caracteres (`openssl rand -hex 32`). O mesmo valor vai no `config.php` da página. Sem ela, a rota responde 503 e não
grava nada. Desligar a captura = apagar a variável na Hostinger e reiniciar o app.

## Como a página chama (regra para o `submit.php`)

A falha da rota **não pode** quebrar o envio da página. O PHP chama com timeout curto (ex.: `CURLOPT_CONNECTTIMEOUT` 2 s
e `CURLOPT_TIMEOUT` 3 s), **ignora o resultado** para o fluxo do usuário e **loga só o código HTTP** (nunca o corpo
enviado, nunca a resposta inteira). Planilha e ActiveCampaign seguem gravando independentemente.

## O que a base guarda

`pessoas.registrar(p, 'formulario')`: cria ou acha a pessoa por e-mail ou telefone e grava um evento do `tipo` pedido.
Com a migration `20261007152702` (aplicada em 07/10), o detalhe do evento guarda `chave_evento`, `sck`, `xcod` e `pagina`. Antes dela:
`tipo: pre_checkout` recebe 400 ("Evento inválido…") e `tipo: lead` grava, mas sem esses quatro campos.
O projeto do evento fica vazio: a função só liga projeto pela sigla de `mkt.projetos` (ex.: `PB26`), e a chave
`clinica-miami-2026-12` não é sigla. Pré-checkout não conta como lead no Tráfego nem aparece na jornada do CRM.

## Como testar

- Automático: `cd web && npx vitest run app/api/captura` (mocka o banco; cobre 200, 400, 401, 413, 429, 502, 503 e
  confere que o log de erro não leva dado pessoal).
- Local com banco: atenção, o `.env.local` aponta para o Supabase de **produção**. Só com `"teste": true`, e-mail
  `@exemplo.invalid`, e conferindo o **conteúdo** da resposta e o evento gravado, não só o HTTP 200.

## Os dois projetos de Miami (decisões do Victor Hugo, 07/10/2026)

São dois eventos, cada um com cadastro próprio em `mkt.projetos` (`gp-operacoes/projetos/calendario.md`, bloco de 07/10):

| | Clínica Internacional de Holding Familiar | Encontro Internacional dos Diamantes |
|---|---|---|
| Chave / etiqueta | `clinica-miami-2026-12` | `miami-2026-12` |
| Datas | 03 e 04/12/2026, Miami | 01 e 02/12/2026, Miami |
| Público | paga, aberta a todo o time (Diamantes já participam sem comprar) | gratuito, só Diamantes |
| Sigla | **`CNFMIAMI26`** (CNF, não CHF: o calendário dizia "CHF"; decisão do Victor) | **`EDIMIAMI26`** (dada pelo Victor em 07/10) |
| Migration (aplicada) | `20261007152825` (era k) | `20261007152903` (era l) |
| Lista do ActiveCampaign | 614 "Clínica Internacional Diamante Dez/26" (`20261007152751`, era j) | nenhuma |

**Risco do Encontro (resolvido):** a regra 42 (lista 614) era a única coisa que mantinha `miami-2026-12` como chave
conhecida no CRM. A j tirou essa chave dela e a l a cadastrou em `mkt.projetos`. Aplicadas em sequência, a chave ficou
cerca de 1 minuto sem resolver (15:27:51 a 15:29:03 UTC), com 0 contatos nela. Hoje as duas chaves são conhecidas.

## Como aplicar (i, j, k, l)

Caminho: `Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py aplicar`, que manda o arquivo pela Management API
do Supabase dentro de `begin … commit` (tudo ou nada). **Diferença para o MCP:** o `apply_migration` do MCP grava a linha
em `supabase_migrations.schema_migrations`; este caminho **não grava**. Sem a linha, um `db push` futuro tentaria
reaplicar. Por isso o comando abaixo junta, no mesmo arquivo temporário (mesma transação), a migration e o insert:

```sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('<AAAAMMDDHHMMSS UTC na hora de aplicar>', '<nome sem a versão>', array[$mig$<texto inteiro do arquivo>$mig$]);
```

Formato conferido no banco em 07/10/2026 (só leitura): colunas `version text`, `statements text[]`, `name text`,
`created_by text`, `idempotency_key text`, `rollback text[]`. As linhas do MCP têm `version` = relógio UTC de 14 dígitos,
`name` = nome do arquivo sem a versão (ex.: `20261007150847` `crm_estrategias_opcoes`), **1 statement** com o arquivo
inteiro (md5 do statement = md5 do arquivo), `created_by` com o e-mail da conta do MCP, `idempotency_key` e `rollback`
nulos. As duas aplicadas antes pela Management API (`20261005230000`, `20261006012500`) têm `created_by` nulo: o insert
segue esse precedente e deixa `created_by` nulo (não põe nome de ninguém). A versão sai do relógio na hora, então fica
depois da última gravada (`20261007150847` em 07/10).

Prova feita (07/10/2026, produção, rollback): i, j e k + o insert acima, com versões fictícias `2099…`, numa transação
desfeita: md5 de `statements[1]` igual ao md5 de cada arquivo (`2c444427…`, `3dbef8f5…`, `cacd1422…`), 0 linhas `2099%`
depois.

**Como foi aplicado (07/10/2026).** Uma por vez, na ordem i, j, k, l, conferindo cada uma antes da próxima, com o
comando abaixo (o mesmo serve para qualquer migration aplicada por este caminho; numa linha só, com `!` no prompt do
Claude Code se for o Victor):

```sh
cd "/Users/victorhugo/Documents/2° cérebro/sistema-grupo-participa-v2/infra/supabase/migrations" && A="/Users/victorhugo/Documents/2° cérebro/Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py" && f=<arquivo.sql> && n=<nome sem a versão> && v=$(date -u +%Y%m%d%H%M%S) && t=$(mktemp) && { cat "$f"; printf "\ninsert into supabase_migrations.schema_migrations (version, name, statements) values ('%s', '%s', array[\$mig\$" "$v" "$n"; cat "$f"; printf '$mig$]);\n'; } > "$t" && out=$(python3 "$A" aplicar "$t"); rm -f "$t"; echo "$f -> $v: $out"
```

Sucesso = `[]` (visto nas quatro). `ERRO` na saída = nada daquela migration gravou, nem a linha em `schema_migrations`.
Depois: conferir com `python3 "$A" consulta "select version, name, md5(statements[1]) from supabase_migrations.schema_migrations where name = '<nome>'"`
(o md5 tem de bater com `md5 -q <arquivo>`), renomear o trio (`.sql`, `_ensaio.sql`, `.explain.md`) para a versão
gravada e trocar o STATUS para APLICADA (manual de banco §3). Arquivo com letra (`20261007i_…`) não segue o padrão
`<dígitos>_nome.sql` do CLI do Supabase, que o ignora; é o nome com a versão que faz o `db push` reconhecer a migration
como já aplicada.

| Era | Versão gravada | Nome | md5 do statement = md5 do arquivo aplicado |
|---|---|---|---|
| 20261007i | `20261007152702` | `pessoas_pre_checkout` | `2c4444270de3d507a438c22aa20b2106` |
| 20261007j | `20261007152751` | `crm_regra_lista_614_clinica_miami` | `3dbef8f5dd2b33b0ed5e5d1943eb80f1` |
| 20261007k | `20261007152825` | `mkt_projeto_clinica_miami` | `cacd142226c57ee7308879a24d7a3fc0` |
| 20261007l | `20261007152903` | `mkt_projeto_encontro_diamantes_miami` | `13e86c8ce7769a3adf8f065acbff799e` |

Prova pós-aplicação (só leitura): CHECK de `pessoas.eventos` com `pre_checkout`; md5 de `pessoas.registrar` =
`8f77b9fc…`; ACL intacta; regra 42 em `clinica-miami-2026-12`; `mkt.projetos` com EDIMIAMI26 (`miami-2026-12`,
01 a 02/12) e CNFMIAMI26 (`clinica-miami-2026-12`, 03 a 04/12); `crm.projeto_conhecido` verdadeiro para as duas chaves.

## O que falta

1. ~~Aceite do Arthur~~ (dado em 07/10). ~~Ensaio~~ (07/10). ~~Aplicar as quatro migrations~~ (07/10, seção "Como aplicar").
2. ~~Revisão do pentester na rota~~ (aprovada em 07/10, com as condições A1, A2 e B1 antes do segredo).
   - **B1 cumprida (07/10, nesta branch):** limite de chamadas autorizadas por IP baixou de 120 para 20 por minuto
     (`AUTORIZADAS_MAX_MIN` em `web/app/api/captura/lead/route.ts`), com teste da 21ª chamada em `route.test.ts`.
     Continua NÃO PUBLICADO (só sai com o merge na `main`).
   - **A1** (limite por IP do visitante no `submit.php`): edição preparada fora do repo, NÃO subida para a Hostinger.
   - **A2** (`config.php` por FTPS): pendente.
3. `CAPTURA_LEAD_SECRET` na Hostinger e no `config.php` da página.
4. Merge na `main` (publica).
5. Edição do `submit.php` via FTP, na regra acima.
6. Sigla da Clínica em `mkt.projetos`: migration `20261007152825` (CNFMIAMI26, APLICADA em 07/10). **Atenção:** mesmo
   com a linha, o evento continua sem `projeto_id`, porque `pessoas.registrar` acha o projeto pela sigla
   (`projeto`) e a rota manda só `chave_evento` (que fica no detalhe). Ligar ao projeto é pedido à parte. Falta
   também decidir se pré-checkout conta em algum painel.
7. ~~Conferir a regra da lista 614 do ActiveCampaign na catalogação do CRM (`20261007141044`): ela leva "Clínica
   Internacional Diamante Dez/26" para `miami-2026-12`, e a Clínica é `clinica-miami-2026-12`.~~
   Corrigida pela migration `20261007152751_crm_regra_lista_614_clinica_miami` (decisão do Victor, 07/10):
   **APLICADA em 07/10** (0 contatos a recatalogar, 0 entradas de Ativação do Encontro vindas da 614); ver
   `infra/supabase/migrations/20261007152751.explain.md`.
