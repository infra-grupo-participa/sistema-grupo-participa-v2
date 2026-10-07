# Dashboard presencial: tela

Implementação local na branch `victor-captura-pre-checkout`. Sem publicação.

## Rotas e modelo

Infra (`/infra`) leva a Dados (`/infra/dados`), à lista (`/infra/dados/dashboards`) e à tela (`/infra/dados/dashboards/[chave]`). O manifesto em `web/modules/infra/dados/domain/registro.ts` valida a chave antes da renderização. A entrada atual usa `clinica-miami-2026-12` e o modelo `presencial-base`. O título dentro da tela vem de `projeto_nome` da função de resumo, não do manifesto.

Para acrescentar outro dashboard do mesmo modelo, cadastre a chave, o título de navegação e a descrição no manifesto. A chave também precisa existir em `dados.dashboards` e as cinco funções `public.dados_presencial_*` precisam responder para ela. Nenhum componente deve copiar a tela. O gate do departamento é feito no servidor e a função `dados.pode_ver` controla os dados no banco.

## Leitura e estados

Ao abrir, a tela chama resumo e série diária. A aba de disparos, os modais de leads e vendas chamam suas funções na primeira abertura. O botão Atualizar invalida todos os resultados locais. Cada chamada guarda erro e dados separadamente. Erro em uma função aparece só no bloco que depende dela; uma resposta vazia mostra estado vazio, não zero. `42501`, `PGRST202` e `P0002` têm textos próprios; outros erros mostram mensagem genérica. O log recebe apenas o código.

`numeric` do PostgREST é convertido em um só módulo. `null` continua `null`: custo não lançado, ausência de instrução, grupo sem fonte e abandonos sem fonte não viram zero. O filtro das vendas começa em `pago`. Os gráficos de barras filtram entre si e filtram a tabela. O gráfico diário mostra pré-checkout, pedidos e vendas; pedidos incluem qualquer status e abandonos seguem sem fonte.

Leads e vendas começam ociosos e só são buscados quando o modal abre; a guarda `deveCarregar` (`application/carga-sob-demanda.ts`) impede uma segunda busca enquanto a primeira carrega ou depois que já há resultado. Instrução vazia aparece como "Sem registro de aluno ativo", porque a ausência na base de alunos ativos não prova que a pessoa nunca foi aluna. A última coluna da Visão de disparos é a taxa de clique.

## Verificação

Na pasta `web`, rodar `npm run lint`, `npx tsc --noEmit`, `npm test` e `npm run build`. Para abrir localmente, rodar `npm run dev -- -p 3001` e entrar em `/infra/dados/dashboards/clinica-miami-2026-12` com uma conta da equipe. Sem as funções aplicadas, a tela deve exibir a mensagem de função ausente no bloco correspondente. Depois da aplicação, conferir cada número diretamente na fonte antes de usar o dashboard para decisão.
