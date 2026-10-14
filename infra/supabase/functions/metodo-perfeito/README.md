# Edge `metodo-perfeito`

Recebe as inscrições das páginas de captação do `timeholdingbrasil.com.br` e grava no schema `metodo` do Supabase
(`pesquisa_respostas`, `consultoria_aplicacoes`). Também manda ao ActiveCampaign e, em algumas ações, à planilha.
O cabeçalho do `index.ts` lista as ações (`inscricao`, `parcial`, `pesquisa`, `consultoria`, `consultoria_resultados`,
`reuniao`).

## Origem desta fonte
- Até 14/10/2026 a Edge **não estava em repo nenhum**. O `index.ts` foi recuperado do source map do pacote publicado
  (versão 16, md5 `0e04d520bb363b4a228ba80ec91e2998`). Esse arquivo, sem alteração, está no commit `f0b075e`.
- Daqui em diante, publique a partir deste diretório, para nenhuma mudança se perder.

## Publicar
- `verify_jwt = true` (está no `infra/supabase/config.toml`). As páginas mandam a chave anon, e a `/renovacao` passa
  pelo `api.php` da `dominiodometodo.com.br/oportunidade`.
- Segredos só no ambiente da Edge (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`). Os do ActiveCampaign e da planilha
  ficam em `metodo.segredos`.
- Antes de publicar, rode `deno check index.ts`.

## Ação `reuniao` (Black THB Vencidos)
| Página | Como envia | `origem` em `pesquisa_respostas` |
|---|---|---|
| `timeholdingbrasil.com.br/dp4` (reunião de 14/10, 19h30) | direto na Edge | `dp4-thb-vencidos` |
| `timeholdingbrasil.com.br/renovacao` (reunião de 16/10, 14h) | `api.php` → Edge | `renovacao-thb-vencidos` (desde 14/10/2026) |

- A origem sai do campo `pagina` que a página manda, pelo mapa `ORIGEM_POR_PAGINA`.
- A comparação ignora protocolo, `www`, `?query`, `#âncora`, barra final e maiúsculas. Página fora do mapa continua
  `dp4-thb-vencidos`.
- A etiqueta do projeto (`black-thb-2026-10`) não está aqui: vem do banco, pelo de-para `metodo.origem_etiqueta`
  (migrations `20261014200000` e `20261014200100`).
- As duas páginas mandam ao Active a lista 622 e a tag 899.

## Reverter a mudança de 14/10
- Publicar o `index.ts` do commit `f0b075e` (v16).
