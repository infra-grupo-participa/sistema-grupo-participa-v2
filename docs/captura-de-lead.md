# Captura de lead servidor a servidor (`POST /api/captura/lead`)

**Situação (07/10/2026): NÃO PUBLICADO e migration NÃO APLICADA.** O código está na branch `victor-captura-pre-checkout`
(não está na `main`). A migration `20261007i` existe só como arquivo e espera o aceite do Arthur.

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
| 429 | `{"error":"Muitas requisições…"}` | 10 falhas de segredo no mesmo IP em 10 min, ou mais de 120 chamadas autorizadas por minuto no mesmo IP |
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
Depois da migration `20261007i`, o detalhe do evento guarda `chave_evento`, `sck`, `xcod` e `pagina`. Antes dela:
`tipo: pre_checkout` recebe 400 ("Evento inválido…") e `tipo: lead` grava, mas sem esses quatro campos.
O projeto do evento fica vazio: a função só liga projeto pela sigla de `mkt.projetos` (ex.: `PB26`), e a chave
`clinica-miami-2026-12` não é sigla. Pré-checkout não conta como lead no Tráfego nem aparece na jornada do CRM.

## Como testar

- Automático: `cd web && npx vitest run app/api/captura` (mocka o banco; cobre 200, 400, 401, 413, 429, 502, 503 e
  confere que o log de erro não leva dado pessoal).
- Local com banco: atenção, o `.env.local` aponta para o Supabase de **produção**. Só com `"teste": true`, e-mail
  `@exemplo.invalid`, e conferindo o **conteúdo** da resposta e o evento gravado, não só o HTTP 200.

## O que falta

1. Aceite do Arthur e aplicação da migration `20261007i` (ensaio antes; ver `20261007i.explain.md`).
2. Revisão do pentester na rota.
3. `CAPTURA_LEAD_SECRET` na Hostinger e no `config.php` da página.
4. Merge na `main` (publica).
5. Edição do `submit.php` via FTP, na regra acima.
6. Sigla da Clínica em `mkt.projetos` (para o evento ganhar projeto) e decidir se pré-checkout conta em algum painel.
7. Conferir a regra da lista 614 do ActiveCampaign na catalogação do CRM (`20261007141044`): ela leva "Clínica
   Internacional Diamante Dez/26" para `miami-2026-12`, e a Clínica é `clinica-miami-2026-12`.
