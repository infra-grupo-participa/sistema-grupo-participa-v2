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

## Padrão: card de ingresso no grupo tem modal com evolução diária

Regra do Victor (16/10/2026, card ClickUp 17tya50h5m6): **todo card de ingresso no grupo ("Ingresso no grupo" e "% ingresso no grupo") de qualquer dashboard abre um modal com a evolução diária, em gráfico e tabela.** Dashboard novo com esse card só fica pronto com o modal.

**Componente único** (`web/modules/infra/ingresso-grupo/`): `domain/evolucao.ts` (função pura `pontosEvolucaoIngresso`, com testes), `ui/EvolucaoIngressoGrupo.tsx` (conteúdo: resumo do período, gráfico de % ingresso, gráfico de entradas por dia e tabela) e `ui/ModalEvolucaoIngressoGrupo.tsx` (o conteúdo dentro do `Modal` do DS). Os gráficos reutilizam o `GraficoLinha` canônico da Black. Quem tem outras abas no modal (Ações da Black) usa `EvolucaoIngressoGrupo` como aba "Evolução diária".

**Entrada:** as linhas de `dados_atm_serie_diaria(p_chave, p_de, p_ate)` (`dia`, `leads`, `grupo_entradas`). **Tabela:** Data, Entradas no dia, Entradas acumuladas, Leads acumulados, % ingresso no grupo. **Regra da taxa:** membros únicos no grupo ÷ leads, soma sobre soma do início do período até o dia (nunca média de taxas diárias). O último dia reproduz o card, porque `dados_atm_resumo.grupo_pct` usa o mesmo período e o mesmo critério (leads sem teste, entradas de `v_grupo_pessoas` por `entrou_em`, testes fora). `grupo_entradas` nulo vira "—" e a tela diz "Sem fonte de grupo para este projeto"; nunca vira 0%. Série em falha mantém o último dado e avisa; sem dado nenhum mostra o erro.

**Situação (16/10/2026, branch `victor-modal-grupo-diario`, sem push):**

| Dashboard | Card | Situação |
|---|---|---|
| Seminário ATM (`SeminarioAtmClient`) | Ingresso no grupo, % ingresso no grupo | Feito: ambos abrem o modal `grupo` (`modalDoCardAtm`). |
| Ações da Black (`DashboardAcoesBlackClient`) | Ingresso no grupo, % ingresso no grupo | Feito: modal ganhou a aba "Evolução diária"; o card de % abre direto nela. O número grande do card é o geral; a série também é a geral (os "leads válidos" do hint não têm série diária). |
| Black, Visão geral (`AbaVisaoGeral` `ModalIngresso`) | Ingresso no grupo | Já tinha aba "Evolução do percentual" própria (chama `dados_black_grupo` uma vez por dia, em lotes de 4). Não migrado, para não arriscar o dashboard em uso. Migrar é o passo seguinte. |
| Black, Histórico (`AbaHistorico`) | Ingresso no grupo geral | Card sem modal; a aba inteira já é por dia. Pendente. |
| **Clínica de Miami** (`/infra/dashboards/csm/clinica-miami-2026-12`) | não existe | **Bloqueado no back-end.** A tela não tem card de grupo e o banco não tem fonte: `dados_presencial_resumo` não traz grupo e `dados_presencial_vendas` devolve `entrou_grupo` sempre `null` (ver `dashboard-presencial.md` §2.3). Falta (1) ligar o grupo do SendFlow da Clínica à chave do projeto (`dados.dashboard_grupos`) e (2) uma função de série diária de grupo/leads para essa chave (mesmas colunas de `dados_atm_serie_diaria`: `dia`, `leads`, `grupo_entradas`). Com isso o card e o modal entram só com `ModalEvolucaoIngressoGrupo`, sem componente novo. Nenhuma migration foi criada. |

**Como testar:** `npm run dev`, abrir um Seminário ATM (`/infra/dashboards/escritorio`) e clicar nos dois cards de ingresso no grupo; abrir Ações da Black e clicar em "% ingresso no grupo" (abre na aba Evolução diária) e em "Ingresso no grupo" (abre em Leads, trocar de aba). Conferir que a linha do último dia da tabela tem as mesmas entradas, leads e % do card (com o filtro de período igual). Em `web/`: `npx vitest run modules/infra/ingresso-grupo modules/infra/atm`.

## Verificação

Na pasta `web`, rodar `npm run lint`, `npx tsc --noEmit`, `npm test` e `npm run build`. Para abrir localmente, rodar `npm run dev -- -p 3001`, navegar por `/infra` → `/infra/dashboards` → `/infra/dashboards/csm` → Clínica de Miami com uma conta da equipe e confirmar o aviso Em breve em Escritório. Conferir também os redirects das três URLs antigas listadas acima. Sem as funções aplicadas, a tela deve exibir a mensagem de função ausente no bloco correspondente. Depois da aplicação, conferir cada número diretamente na fonte antes de usar o dashboard para decisão.

Após a aplicação das funções do §2.9, comparar o total de vendas dos pagamentos, o total das roscas e o último ponto de vendas acumuladas com `resumo.vendas`; comparar receita acumulada final com `resumo.receita_bruta`. Nos cards, conferir que o total de pessoas não é a soma das categorias quando há sobreposição. Abrir cada modal e conferir a contagem de linhas com a linha `total` do grupo. Na aba visível, observar a segunda leitura após 60 s; disparos e a lista dos modais não devem ser chamados pelo polling. Repetir com a aba oculta e simular falha de uma função para confirmar que só seu bloco mostra aviso e mantém os dados anteriores.

## Clínica de Miami: abas da cópia da planilha (card ClickUp 17tya50h3b8)

Situação: **não publicado**. Branch `victor-miami-relatorio`, commit local, sem push. A migration `20261016240000` (função `public.dados_miami_relatorio`) e a Edge `dados-planilha-relatorio` ainda **não estão aplicadas nem no ar** (ver `docs/dashboard-presencial.md` §2.12.3). Sem a função, a tela degrada: só estas abas mostram a mensagem de função ausente; o restante do dashboard segue normal.

### O que foi feito e por quê

O Victor pediu que o dashboard da Clínica de Miami replique a aba "Relatório" da planilha "Dados [MIAMI 2026]" da Isabela, mantendo-se atualizado. O back-end copia a aba para o banco e a tela lê só por `public.dados_miami_relatorio(p_chave, p_md5)` (contrato em `docs/dashboard-presencial.md` §2.12 e §2.12.1). A tela não lê a planilha.

Abas (só para `clinica-miami-2026-12`): **Relatório**, **Diamantes** (conteúdo trocado pelo da planilha, 22 colunas), **Compradores** (nova, 16 colunas), **Presença por evento** (inclui Camisas) e **Fichas de interesse** (inalterada).

- **Relatório:** os três blocos de indicadores viram cards (`KpiCard`). Percentual ganha barra de progresso. Subgrupo em que todos os itens são contagens inteiras (um item sem valor abre o subgrupo) vira rosca, porque a soma das fatias é o total do subgrupo. As linhas 1 a 30 foram deixadas a critério do front-end pelo Victor.
- **Diamantes e Compradores:** gráficos de barras por coluna categórica (no máximo 12 valores distintos; clicar na barra filtra a tabela), busca sem acento nem caixa, ordenação por coluna (data, número pt-BR, texto; vazio sempre no fim), cabeçalho fixo, contador "X de Y linhas", chips de filtro, interruptor "Todas as colunas" (a visão padrão mostra as colunas principais; as demais ficam no detalhe), lista de cartões no mobile e modal com a linha completa ao clicar.
- **Presença por evento:** três gráficos (Diamante, Time e Total geral estimados), uma barra por evento. Evento com "—" não vira zero: fica fora da barra e é contado como "sem dado". Tabela completa, modal por evento e tabela de Camisas com a linha Total em destaque.
- **Rótulos e cabeçalhos** são a string exata do contrato. Nada foi renomeado. Um rótulo da planilha ("... (clique no número para ver quem)") é mantido, mas **o clique não existe na tela**.
- **Contato** (`E-mail`, `Telefone (WhatsApp)`, `Telefone`): visível para todos, decisão provisória do Victor (16/10). Com `contato_visivel = false` as três colunas somem da tabela e do detalhe. Na visão padrão elas já ficam fora da tabela e aparecem no detalhe e em "Todas as colunas".
- **Atualização:** polling de 60 s só com a aba do navegador visível. Envia `p_md5` apenas quando já há cópia; resposta `igual` não troca o conteúdo. O botão Atualizar força a leitura e religa o polling parado. Timeout de 15 s por chamada, `try/catch`, e o log recebe só o código do erro.
- **Estados:** carregando; sem cópia (`disponivel = false`, nada de zero); erro sem cópia (alerta); erro com cópia boa (mantém o último valor, esmaece, mostra "lida em ... (há X)" e o aviso); erro do leitor da planilha (código do erro e a data da cópia exibida); `avisos` do contrato sempre visíveis. `42501`, `PGRST202` e `P0002` são permanentes (o polling para).

### Arquivos (módulo `web/modules/infra/dados`)

Novos: `domain/relatorio-miami.ts` (contrato, busca, ordenação, agrupamento), `application/relatorio-miami-estado.ts` (junção de leituras), `infrastructure/relatorio-miami-data.ts` (RPC), `ui/useRelatorioMiami.ts` (polling), `ui/AbaRelatorioMiami.tsx`, `ResumoRelatorioMiami.tsx`, `TabelaRelatorioMiami.tsx`, `PresencaMiami.tsx`, `ModalLinhaRelatorio.tsx` e os testes. `domain/relatorio-miami.fixture.ts` só serve aos testes e usa pessoas inventadas, com cabeçalhos importados do leitor da Edge.

Alterados: `ui/DashboardPresencialClient.tsx` (só registro das abas, o hook e o botão Atualizar; o modal de ingresso no grupo, trabalho de outro agente, não foi tocado). Removido: `ui/AbaDiamantes.tsx` (substituído). Mantidos de propósito: `carregarDiamantesMiami`, `DiamantePresencial` e seu teste (a função `dados_miami_diamantes` segue no banco); o campo `diamantes` nos refs `miamiEmAndamento` e `recarregarMiami` ficou como resíduo para reduzir conflito de merge e pode sair numa limpeza posterior.

### Como testar

1. Em `web/`: `npx tsc --noEmit`, `npm run lint`, `npx vitest run`, `npm run build`, `npm run lint:tokens`.
2. Hoje (função ainda ausente): abrir `/infra/dashboards/csm/clinica-miami-2026-12`, entrar em Relatório, Diamantes, Compradores e Presença. Cada uma mostra "Esta função ainda não está no banco..." e as demais abas continuam funcionando.
3. Depois de aplicar a migration, publicar a Edge e rodar a primeira leitura (§2.12.2): comparar na tela, com a planilha aberta, `Pessoas na Lista Diamantes`, `Compradores da Clínica` e uma contagem de Presença; conferir o total de linhas de Diamantes e Compradores. Número só vale depois de conferido na fonte.
4. Com a aba visível, observar o polling no Network (a cada 60 s; segunda chamada com `p_md5`; resposta `igual: true` sem recarregar a tabela). Simular falha e ver o conteúdo esmaecido com a idade da cópia.

### O que falta

- Aplicar a migration, publicar a Edge e conferir os números contra a planilha (a tela com dados reais **não foi aberta**: a função não existe no banco e a rota exige login).
- Tornar o número "clique para ver quem" clicável, se o Victor quiser (precisa de decisão e de contrato: hoje a cópia não traz a lista de quem).
- Revisar o gate de contato quando os níveis de acesso forem revistos.
- Teste visual em navegador (desktop e mobile) após a aplicação.
