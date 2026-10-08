# Dashboard presencial: tela

Dashboard original na branch `victor-captura-pre-checkout`; reorganização da navegação na branch `victor-modularizacao-infra`. Sem publicação.

## Rotas e modelo

Infra (`/infra`) leva a Dashboards (`/infra/dashboards`), que apresenta CSM e Escritório. CSM abre a lista (`/infra/dashboards/csm`) e a Clínica de Miami fica em `/infra/dashboards/csm/clinica-miami-2026-12`. Escritório abre um aviso Em breve. O manifesto em `web/modules/infra/dados/domain/registro.ts` valida a chave antes da renderização. A entrada atual usa `clinica-miami-2026-12` e o modelo `presencial-base`. O título dentro da tela vem de `projeto_nome` da função de resumo, não do manifesto.

Os links antigos continuam funcionando por redirect: `/infra/dados` e `/infra/dados/dashboards` vão para `/infra/dashboards`; `/infra/dados/dashboards/[chave]` vai para `/infra/dashboards/csm/[chave]`. O layout de Infra mantém o gate do departamento nos caminhos novos e antigos, e a tela da Clínica exige `financeiro.ver` quando a flag de acesso V2 está ligada. O menu lateral e os títulos de navegação usam a hierarquia Infra / Dashboards / CSM.

Para acrescentar outro dashboard do mesmo modelo, cadastre a chave, o título de navegação e a descrição no manifesto. A chave também precisa existir em `dados.dashboards` e as cinco funções `public.dados_presencial_*` precisam responder para ela. Nenhum componente deve copiar a tela. O gate do departamento é feito no servidor e a função `dados.pode_ver` controla os dados no banco.

## Leitura e estados

Ao abrir, a tela chama resumo e série diária. Depois, refaz essas duas leituras a cada 60 s com a aba visível e ao voltar para ela. Nunca inicia nova leitura enquanto a anterior não terminou. O horário exibido é o da última leitura bem-sucedida dos dois blocos. A aba de disparos, os modais de leads e vendas chamam suas funções na primeira abertura; o polling não os recarrega. O botão Atualizar recarrega também os blocos sob demanda, sem apagar resumo e série durante a leitura. Cada chamada guarda erro e dados separadamente. Falha de leitura mantém o último dado válido do bloco e mostra aviso; uma resposta vazia mostra estado vazio, não zero. `42501`, `PGRST202` e `P0002` têm textos próprios; outros erros mostram mensagem genérica. O log recebe apenas o código.

`numeric` do PostgREST é convertido em um só módulo. `null` continua `null`: custo não lançado, ausência de instrução, grupo sem fonte e abandonos sem fonte não viram zero. O filtro das vendas começa em `pago`. Os gráficos de barras filtram entre si e filtram a tabela. O gráfico diário mostra pré-checkout, pedidos e vendas; pedidos incluem qualquer status e abandonos seguem sem fonte.

Leads e vendas começam ociosos e só são buscados quando o modal abre; a guarda `deveCarregar` (`application/carga-sob-demanda.ts`) impede uma segunda busca enquanto a primeira carrega ou depois que já há resultado. Instrução vazia aparece como "Sem registro de aluno ativo", porque a ausência na base de alunos ativos não prova que a pessoa nunca foi aluna. A última coluna da Visão de disparos é a taxa de clique.

## Gráficos da Visão geral de vendas

Contrato em `docs/dashboard-presencial.md` §2.9. A aba mostra formas de pagamento por forma e parcelas, roscas de turma e instrução, pendências por pessoa única, vendas e receita acumuladas, conversão diária e vendas por hora. A legenda das roscas explicita o casamento por e-mail, documento e telefone e a quantidade sem aluno. `null` continua "sem dado"; dia sem pré-checkout não ganha ponto de conversão. Gráficos sem linhas usam `EmptyState`.

As cinco funções agregadas novas (`dados_presencial_pagamentos`, `dados_presencial_compradores_perfil`, `dados_presencial_pendencias`, `dados_presencial_serie_vendas`, `dados_presencial_vendas_por_hora`) entram no polling de 60 s junto de resumo e série diária. O Galego mediu 31 a 113 ms para essas leituras. Cada bloco conserva seu último resultado bom e mostra erro próprio. A função `dados_presencial_pendencias_pessoas`, que traz dados pessoais, é chamada só quando alguém abre o modal de não pagos ou canceladas; o modal usa as abas Pessoas e Resumo. O total dos cards vem da linha `categoria = total`, pois uma pessoa pode aparecer em mais de uma categoria.

As seis funções constam como aplicadas no banco na migration `20261007212530` (commit `91e4c31`). Se alguma não estiver visível ao PostgREST, só seu bloco mostra `PGRST202`; resumo e série anteriores continuam disponíveis. A conferência numérica ponta a ponta da tela fica para o aviso do Maestro. Não usar números sintéticos na tela publicada.

## Verificação

Na pasta `web`, rodar `npm run lint`, `npx tsc --noEmit`, `npm test` e `npm run build`. Para abrir localmente, rodar `npm run dev -- -p 3001`, navegar por `/infra` → `/infra/dashboards` → `/infra/dashboards/csm` → Clínica de Miami com uma conta da equipe e confirmar o aviso Em breve em Escritório. Conferir também os redirects das três URLs antigas listadas acima. Sem as funções aplicadas, a tela deve exibir a mensagem de função ausente no bloco correspondente. Depois da aplicação, conferir cada número diretamente na fonte antes de usar o dashboard para decisão.

Após a aplicação das funções do §2.9, comparar o total de vendas dos pagamentos, o total das roscas e o último ponto de vendas acumuladas com `resumo.vendas`; comparar receita acumulada final com `resumo.receita_bruta`. Nos cards, conferir que o total de pessoas não é a soma das categorias quando há sobreposição. Abrir cada modal e conferir a contagem de linhas com a linha `total` do grupo. Na aba visível, observar a segunda leitura após 60 s; disparos e a lista dos modais não devem ser chamados pelo polling. Repetir com a aba oculta e simular falha de uma função para confirmar que só seu bloco mostra aviso e mantém os dados anteriores.
