# Dashboard da Black Friday 2026 (Infra › Dashboards › CSM)

Rota: `/infra/dashboards/csm/black-friday-2026-10` · módulo `web/modules/infra/black/` · branch `victor-black-dashboard`.
Pedido do Victor Hugo (12/10/2026). Desenho e plano técnico no cérebro do Victor
(`Projetos/dashboard-black-friday/DESENHO-DASHBOARD-V2.md` e `PLANO-TECNICO-V2.md`).

## Situação

- **Ligado no banco (13/10/2026).** A fonte real (`infrastructure/fonte-supabase.ts`) chama as RPCs
  `dados_black_*` do Supabase com a sessão do usuário (mesmo padrão do ATM). Migrations no ar: A
  `20261012231649` (cadastro e `dados_black_trafego`), C `20261012233334` (trava de modelo nas RPCs
  presenciais), B `20261012234606` (`dados_black_perfil`, `dados_black_leads`, `dados_black_grupo`, marcar teste)
  e a foto do grupo `20261013001456`; depois, o recorte com lista `20261013120148` e a miniatura dos criativos
  `20261013121212` (13/10). Detalhe de cada método na seção "Fonte real" abaixo.
- **Publicado em produção em 13/10/2026**, após os PRs #14 e #15, ambos com CI verde.
- O deploy da Hostinger é automático a cada push na `main`.
- A demonstração (dado fictício) continua existindo só em dev com `NEXT_PUBLIC_BLACK_DEMO=1`.
- Fora do módulo, a branch toca 3 arquivos: a rota `app/(admin)/infra/dashboards/csm/[chave]/page.tsx`
  (desvia o modelo `jornada-captacao`), uma linha no `modules/infra/dados/domain/registro.ts` e a flag
  `blackDemo` no `shared/infrastructure/config/env.ts`. **Reversão:** tirar a linha do `registro.ts`.

## Como testar (localhost)

```powershell
cd web
npm ci                      # primeira vez nesta máquina (não commitar o package-lock se mudar)
$env:NEXT_PUBLIC_BLACK_DEMO='1'; npm run dev
```
No bash: `cd web && NEXT_PUBLIC_BLACK_DEMO=1 npm run dev`.

Login normal em `http://localhost:3000/login` (conta `@advmais.com`, cargo admin ou acima, que vê Infra) e abrir:
`http://localhost:3000/infra/dashboards/csm/black-friday-2026-10?funil=todos&periodo=desde-inicio&canal=todos&aba=visao`

- `?relogio=AAAA-MM-DD` (só no modo demonstração) move o relógio da demo. Padrão: 03/11/2026 18h, 1h30 antes da live.
- Testar também: 375 px de largura (sem rolagem horizontal), `prefers-reduced-motion` ligado (nada anima,
  o play do Histórico fica desligado) e recarregar a URL com filtros (volta igual; valor inválido cai no padrão).
- O dev local aponta para o banco de **produção** só para o login; os dados da tela saem do fixture.
- A demonstração **nunca liga em produção**: `modoDemoBlack` exige a flag `'1'` e `NODE_ENV !== 'production'`.
  Prova: `NEXT_PUBLIC_BLACK_DEMO=1 npm run build` e `grep -rl "Lead Teste" .next` dá **0** (o import do
  fixture fica atrás de um teste inline de `NODE_ENV` que o build de produção descarta).

### Totais da semente (PRNG mulberry32, semente 20261103, dias 04/10 a 03/11)

> **Atualizado em 12/10/2026 (noite):** com o Google zerado e a profissão nova, a semente passou a dar
> **R$ 263.977,08** de gasto (Google R$ 0), **13.528** cadastros e **13.102** pessoas únicas (medido no teste
> `fixtures.test.ts`). A tabela abaixo é da versão anterior e não foi remedida linha a linha.

| Total | Valor |
|---|---|
| Gasto de tráfego | R$ 276.000,76 (Meta 266.231,47 · Google 9.769,29) |
| Cadastros | 14.590, sendo 13.145 de tráfego pago |
| Pessoas únicas | 14.146 (444 com segunda porta) |
| Sem UF (sem DDD reconhecido) | 179 |
| Linhas dia × anúncio | 609, com 30 anúncios |
| Disparo fictício no período inteiro | R$ 6.461,32 (API 2.768,35 · SMS 1.628,37 · Ligação 2.064,60) |

Conferido na tela renderizada com o padrão `desde-inicio` (placar 14.146 de 15.000; verba R$ 276.000,76 de
R$ 428.571,00; CPL do placar R$ 14,61 = R$ 192.079,46 ÷ 13.145; soma das 6 fases = R$ 276.000,76).

## Ajustes da auditoria do Victor (12/10/2026)

- **P1, gaveta que não fechava.** Causa: a gaveta era `fixed z-40` dentro da página e a barra do app é `z-[60]`;
  o cabeçalho da gaveta, com o botão Fechar, ficava escondido atrás da barra. Agora a gaveta abre num portal no
  `<body>` em `z-[1000]` (mesma camada do Modal canônico), com o botão "Fechar" (X + texto) fixo no topo (só o
  corpo rola), Esc fecha, clique no fundo fecha e o foco fica preso na gaveta. Vale para etapa e criativo
  (as duas usam `ui/GavetaLateral.tsx`). Troca de decisão: a gaveta passou a ter fundo escurecido, porque o
  clique fora precisa fechar.
- **Visão geral.** "CPL do placar" virou **"CPL geral"**, com a dica em linguagem simples (gasto de captação e
  remarketing ÷ leads que vieram de anúncio); a conta não mudou. O gráfico **por fase** (card de investimento até 13/10 e
  sub-aba do modal) virou `BarrasFase` em `ui/graficos.tsx`: barras grossas, uma cor por fase sem vermelho
  (azul, ouro, roxo, verde-água, lilás e verde, tokens `--info`, `--nivel-ouro`, `--purple`, `--cyan`,
  `--nivel-diamante`, `--green`), entrada animada, dica com o valor ao passar o mouse ou focar, marca do previsto
  e muito mais espaço entre as fases. Fase acima do previsto diz "acima do previsto" em texto (antes era barra vermelha).
- **Funil macro** com **CPM** (gasto ÷ impressões × 1000) e **CPC** (gasto ÷ cliques, só nas linhas com clique
  medido, a mesma base do CTR; `cpc` em `domain/metricas.ts`, com teste), na ordem: Impressões, CPM, Cliques no
  link, CTR, CPC, Visualizações da página, Connect rate, Inscrições, Conversão da página, Grupo em 48h. Grade de
  5 colunas com linhas de altura igual. Presença na live e Vendas ficam numa linha própria abaixo.
- **Modal dos cards:** "Por dia" virou gráfico de **linha** (`GraficoLinha`: eixo X dia, eixo Y a métrica do dia,
  linha desenhada na entrada, cursor que mostra o valor do dia; dia sem dado quebra a linha). "Por criativo"
  ficou compacto: top 10, busca pelo nome, "maior/menor primeiro" (custos abrem pelo menor), rolagem e
  "mostrar todos"; o clique continua levando ao criativo. Modal de `max-w-4xl` para `max-w-3xl`.
- **CPL por etapa** ganhou a linha do **C1**, com CPM e custo por visualização e o aviso "não gera lead: não é CPL".
- **Mensageria.** Saiu o "custo por ingresso" (e "viraram ingresso/presença" como resultado do custo): cada envio
  tem um objetivo próprio, então o custo é do envio, **custo total** e **custo por mensagem enviada** (Σ custo ÷
  Σ enviados, só nos canais pagos). Cinco canais: **API, SMS e ligação** lado a lado (pagos) e **grupo e e-mail**
  (sem custo, "Sem custo por envio", cada um com as métricas que mede: membros alcançados e cliques no link no
  grupo; enviados, entregues, abertos, cliques e devolvidos no e-mail). Embaixo, a **lista de envios** no padrão
  do ATM (`atm/ui/DisparosDetalhe.tsx`): canal, data e hora, título, objetivo, tamanho da base, enviados, custo,
  custo por enviada e, aberto, as métricas do canal com a taxa e a copy; filtro por canal e "mostrar mais" de 20
  em 20. Tudo com selo "dado fictício". Tipos novos em `domain/tipos.ts` (`CanalDisparo`, `EnvioMensageria`,
  `MetricasDisparo`, `CANAL_PAGO`); o fixture gera 7 envios por dia a partir de 12/10 com sorteio próprio (os
  totais de tráfego e de leads da semente não mudaram) e a fonte soma o canal a partir dos envios do período
  (teste em `fixtures.test.ts`). A régua de API do grupo continua. Na Jornada, o nó "Régua do aquecimento" mostra
  Enviados, Entregues e Custo (antes "Viraram ingresso").
- **Campanha × conjunto** (aba Criativos e páginas) virou mestre e detalhe lado a lado (`ui/CampanhaConjunto.tsx`):
  campanhas à esquerda, os conjuntos da campanha clicada à direita, cada cartão com **gasto, CPL (com farol) e
  leads pagos** em destaque (no C1, custo por visualização e impressões). Clicar num conjunto filtra tudo, inclusive
  a lista de campanhas, que passa a mostrar só a campanha dele (pedido de 13/10; antes ela ignorava o conjunto). Trocar
  ou tirar a campanha limpa o conjunto (o conjunto é filho dela). Sai a dupla de barras.
- **Ordem dos criativos.** A conta da ordem estava certa (teste novo cobre as quatro ordens), mas não se via: o CTR
  com uma casa deixava quase todos em "1,1%" e o topo era o mesmo em "Mais leads", "Menor CPL" e "Mais gasto".
  Agora cada cartão mostra a posição e o valor que a ordem usa (ex.: "1º CTR 4,49%"), o CTR sai com duas casas,
  uma linha explica a ordem escolhida e o empate desempata por gasto e nome (`valorOrdem` e `ordenar` em
  `domain/criativos.ts`).
- **Funil do criativo em trapézios** (gaveta do criativo, segunda rodada de 12/10). O mini-funil de barras virou
  `FunilTrapezio` em `ui/graficos.tsx`: uma fatia por etapa com o valor total dentro (Impressões, Cliques, Views da
  página, Leads pagos, Ingresso no grupo (48h)) e, à direita, a ponte com a taxa de passagem (CTR, Connect rate,
  Conversão da página, Taxa de ingresso no grupo). No C1 fica Impressões e Vídeo 75%, com a taxa de vídeo 75%.
  A largura das fatias é ilustrativa (afunila sempre, para dar leitura); quem manda é o número. Etapa sem dado fica
  cinza com "Sem dado". Ao passar o mouse (ou focar com Tab) numa etapa, ela fica em destaque (borda grossa) com a
  ponte que chega nela, e as outras esmaecem (pedido do Victor, 12/10). As etapas e taxas saem de `funilCriativo` (`domain/criativos.ts`, com teste), que só chama
  as funções de `domain/metricas.ts` (`ctr`, `connectRate`, `conversaoPagina`, `ingressoGrupo`). O recorte é o do
  período escolhido, só do criativo. Atenção: a taxa de ingresso conta **pessoas únicas com a janela de 48h já
  fechada** (regra do `ingressoGrupo`), então o denominador dela pode ser menor que os leads pagos da fatia acima.
  O único outro funil de barras do painel, o "Funil do dia" do Histórico, ficou como estava (não é o mini-funil).
- **Investimento e leads por dia** (logo abaixo do funil) virou `GraficoInvestimentoLeads` em `ui/graficos.tsx`,
  no mesmo padrão de cursor do `GraficoLinha`: passando o mouse (ou o dedo) aparece a data, o investimento e os
  leads pagos do dia, com a barra do dia destacada. Também funciona no teclado: foco no gráfico e setas
  (Home e End vão ao primeiro e ao último dia, Esc fecha).
- **Campanhas e conjuntos paginados** (`ui/CampanhaConjunto.tsx`). Os dois lados usam o **mesmo cartão**, do mesmo
  tamanho: **lado a lado, metade da largura cada, um cartão embaixo do outro** (uma coluna só em cada metade,
  nada de dois cartões lado a lado nos conjuntos). Só abaixo de 768 px (celular) as duas metades empilham. **Sem campanha escolhida**, a direita mostra os
  conjuntos de **todas as campanhas** do recorte (antes ficava vazia), e a dica do cartão diz de qual campanha ele é;
  clicar numa campanha filtra para os conjuntos dela, clicar de novo tira. Cada lado mostra **no máximo 10** e embaixo
  a régua estilo Google: "‹ 1 2 3 4 5 ›" com a página atual destacada (`aria-current="page"`, `nav` com
  `aria-label`), setas desligadas nas pontas e "11 a 20 de 23". Uma página só = sem régua. **Trocar filtro volta
  para a página 1**: funil, canal, período, criativo ou página escolhidos mudam a chave; nos conjuntos, trocar a
  campanha também. Escolher um conjunto não mexe na página. Contas puras em `domain/paginacao.ts` (`paginar`,
  `paginasVisiveis`, com teste). Na semente fictícia são 9 campanhas (sem régua) e 14 conjuntos (2 páginas).

## O que foi feito (5 abas, filtro global)

Seletor global: funil (Todos, C1, Consultoria, Iscas, C3), período (Hoje, 7 dias, Desde o início, Semana do
ciclo) e canal (Todos, Meta, Google). Tudo mora na URL. Releitura a cada 5 min só com a aba visível.

1. **Visão geral:** placar (até a live, leads x meta, CPL x régua, verba x orçamento); investimento do período
   (total = tráfego + disparo, tráfego por canal, disparo fictício; o por fase x previsto saiu da visão geral em 13/10 e ficou no modal); funil macro só da
   captação; funis lado a lado; CPL por etapa. Todo card abre o **modal com sub-abas fixas** (Por funil, canal,
   fase, dia, criativo, Perfil; a que não cabe diz "Não se aplica a este card").
2. **Jornada:** o fluxograma do Arthur vivo, setas com espessura pelo volume e fluxo animado; o funil filtrado
   apaga os outros nós. Clicar no nó abre a **gaveta lateral** (Etapa · Criativos · Perfil).
3. **Criativos e páginas:** trilha Campanha › Conjunto › Criativo › Página com chips; campanhas e conjuntos
   lado a lado, 10 por página (sem campanha, todos os conjuntos); galeria com miniatura fictícia e ordem por chips; cartões por página. O criativo abre a
   gaveta com miniatura, funil em trapézios, curva diária interativa e os 3 botões (desligados na demonstração).
4. **Mensageria:** API, SMS e ligação lado a lado (custo total e por mensagem enviada), grupo e e-mail sem custo,
   lista de envios por canal (título, objetivo, data e hora, base, copy, métricas) e régua de API do grupo (+2h,
   +12h, +24h). Selo "dado fictício".
5. **Histórico:** régua de dias com play que "toca" o funil do dia e o gráfico de investimento por dia com
   pessoas acumuladas contra a meta acumulada.

Perfil dos leads (modal, gaveta): profissão, estado pelo DDD (mapa do Brasil com bolhas, malha do IBGE),
região, utm_source, página, base de origem, isca; tudo clicável e encadeado; tabela de leads sob demanda.

## Fórmulas (regra única: razão = soma sobre soma, mesmo recorte; sem dado nunca vira zero)

- CPL = gasto ÷ leads pagos (só cadastro com origem paga). CPL geral (antes "CPL do placar"; provisório, BLOQUEIO 3): gasto de
  captação + remarketing ÷ leads pagos. Farol pela régua do Caio: até R$ 15 verde, até R$ 20 amarelo, acima vermelho.
- Connect rate = Σ views da página ÷ Σ cliques, só consultoria, iscas e C3 e só nas linhas com as duas
  métricas (Google não tem LPV e fica fora, com nota). Conversão da página = leads pagos ÷ views, mesma regra.
- CTR = cliques ÷ impressões; CPM = gasto ÷ impressões × 1000; CPC = gasto ÷ cliques (só linhas com clique medido); vídeo 75% = p75 ÷ impressões com vídeo;
  custo por visualização = gasto ÷ ThruPlay. Alcance e frequência não somam entre dias: vêm do total do período.
- Grupo em 48h = pessoas que entraram no grupo em até 48h ÷ pessoas com a janela de 48h já fechada.
- Meta acumulada = 650 × dias desde o início da captação (12/10). Leads da meta = pessoas únicas.
- Mensageria: custo por mensagem enviada = Σ custo ÷ Σ enviados dos canais pagos (na ligação, por discada); taxas
  do canal sobre entregues quando o canal mede entrega, senão sobre enviados; falhas sobre enviados.
- MQL = profissão advogado, contador ou estudante de Direito (4 respostas; decisão de 12/10, noite, ver Decisões). Conferido em
  12/10: nenhuma conta do dashboard usa MQL hoje; "MQL" só aparece como rótulo de temperatura de base, string da fonte.
- Falha de bloco: segura o último valor, esmaece e mostra a idade da leitura.

## Mobile (13/10/2026)

O desktop (1440 px) ficou idêntico ao anterior: toda mudança é variante `max-*` (só abaixo do breakpoint) ou troca de
breakpoint que dá o mesmo CSS a partir de 1280 px. Conteúdo, tokens e regras de cálculo não mudaram.

O que foi ajustado:
- Abas principais quebram linha abaixo de 768 px (nenhuma fica escondida atrás da rolagem) e ganham 44 px de altura.
- Rótulo que era cortado com reticências (`truncate` do KpiCard e das listas) quebra linha abaixo de 1280 px:
  `ROTULO_INTEIRO` em `ui/pecas.tsx`, aplicado na raiz do dashboard e no corpo da gaveta (que é portal).
- Modal de card e modal de tabela ocupam a tela inteira abaixo de 768 px (`MODAL_TELA_CHEIA`, somado ao `width`).
- Funil macro: duas colunas no celular, três a partir de 1024 px, cinco com linhas iguais a partir de 1280 px. O card
  Ingresso no grupo ocupa a linha inteira abaixo de 1280 px, com a lista por grupo dentro da moldura.
- Investimento no período empilha até 1023 px; Campanhas e conjuntos ficam um embaixo do outro até 1279 px, e os
  três números de cada cartão passam a duas colunas abaixo de 640 px (o valor não quebra no meio).
- Mapa da Jornada: o SVG só aparece a partir de 1280 px; abaixo, a lista de etapas que já existia.
- CPL por etapa: no celular o nome da etapa fica na primeira linha e o cálculo desce para a segunda.
- Mensageria: canais pagos lado a lado só a partir de 1280 px, canais sem custo a partir de 1024 px; no envio, o
  "Ver detalhes" desce para baixo do título no celular. Histórico: os quatro KPIs do dia em uma coluna abaixo de 640 px.
- Área de toque de 44 px no celular: Atualizar, Filtrar, Ver os envios, Mostrar mais, Limpar e chips do filtro,
  Anterior/Próxima da tabela, linhas das legendas do Perfil e a régua do Histórico.

Como testar: `npm run dev` em `web/` e abrir o dashboard no DevTools em modo dispositivo. Larguras conferidas por foto
(Playwright): 360, 375, 390, 414, 768 e 1440 px, cada aba, o modal de Leads (com Perfil e tabela), o modal de MQLs, a
gaveta de etapa e a de criativo. Em 360 a 768 px nenhum elemento passa da largura da tela. O 1440 foi comparado pixel a
pixel com o antes: idêntico, fora o relógio "Lido às".

Ficou de fora (a decidir): as barras do gráfico do Histórico seguem com 10 px de largura (a régua é o controle no
celular); e a lista de estados do mapa do Perfil tem 24 px de altura.

### Card Ingresso no grupo e modal descentralizado (13/10/2026, pedido do Victor)

- **Card:** no desktop a lista por grupo (Advogados, Contadores, Outros) vazava para baixo da moldura, por cima da seção
  seguinte. Causa: `[&>*]:h-full` dava a altura toda da célula ao KpiCard e a lista ficava fora. Agora a moldura vai
  para fora em qualquer largura (`MOLDURA_COM_LISTA` em `ui/AbaVisaoGeral.tsx`) e só ela ocupa a célula.
- **Modal:** o modal dos cards do funil macro abria no meio da aba, lá embaixo, e não no meio da tela. Causa: a animação
  de entrada do painel (`.atm-historico-panel-enter`, em `app/globals.css`) usava `both` e deixava um `transform` preso
  no painel; elemento com `transform` vira o bloco de referência do `position: fixed`. Trocado para `backwards`: a
  animação é a mesma e nada fica preso. Vale também para os modais e gavetas do ATM, que usam a mesma classe.
- Como testar: abrir a Visão geral a 1440 px, conferir a lista dentro do card e clicar num card do funil macro com a
  página rolada até o funil: o modal tem que abrir no centro da tela.

### Visão geral: placar na primeira dobra, sem o gráfico por fase (13/10/2026, pedido do Victor)

- **Pedido:** visão geral parecida com a do HT. Os cards Até a live, Leads contra a meta, CPL geral, Verba contra o
  orçamento, Investimento total, Investimento em tráfego e Investimento com disparo ficam juntos na primeira faixa, e o
  funil macro (Impressões, CPM, Cliques no link, CTR e o resto) sobe logo abaixo.
- **Feito:** o gráfico "Por fase" saiu da visão geral; ele continua na sub-aba Fase do detalhe do card de tráfego
  (`ModalCard`). A faixa "Investimento no período" deixou de ser seção própria: os três cards de investimento são a
  segunda linha do placar e ganharam o nome "Investimento ..." no rótulo. Números e fórmulas não mudaram (os três
  continuam no período escolhido no topo; os quatro de cima, do início até agora).
- Como testar: abrir a Visão geral a 1440 px e conferir que os sete cards e o começo do funil macro aparecem sem rolar.

### Placar e funil macro v3 (14/10/2026, pedido do Victor)

- O placar começa com **Investimento total**, **Investimento em tráfego** e **Investimento com disparo**, lado a lado. Total e tráfego mostram valor, barra e percentual contra `ORCAMENTO.total` (R$ 428.571,00). Até existir limite separado para disparos, o total reutiliza esse mesmo orçamento; esse uso provisório está comentado no card. Disparo conserva `Sem dado` quando o custo não foi lançado, mostra a barra vazia e `limite sem cadastro`; não há selo de dado fictício.
- **Leads contra a meta** conta pessoas únicas de todas as portas desde o início do projeto e ignora filtros do período, funil e canal. A meta aparece no card com valor, percentual e barra. A linha `N do tráfego` usa pessoas pagas únicas atribuídas às campanhas elegíveis C2/C3.
- **CPL geral** sai do placar e passa ao primeiro trecho do Funil macro, logo depois de Investimento em captação. O numerador é o investimento C2/C3 do período selecionado; o divisor são pessoas pagas únicas atribuídas às mesmas campanhas e ao mesmo filtro de funil/canal. A classificação de campanha segue `etapa_black`; ENTRESAFRA, remarketing e `consultoria_respondi` ficam fora.
- **Inscrições** no Funil macro contam pessoas únicas atribuídas às campanhas elegíveis C2/C3 no período escolhido, em todas as portas. Cadastro repetido não aumenta a contagem.
- O card `Verba contra o orçamento` e o card grande `Até a live` foram removidos. Quando a live ainda está no futuro, aparece apenas uma contagem pequena no canto do título do placar.
- Como testar: selecione períodos diferentes e confirme que Leads contra a meta não muda, enquanto Inscrições, N do tráfego e CPL seguem o período e os filtros globais. No modo de demonstração, repita em 1280 e 375 px, nos temas claro e escuro. Testes de deduplicação e exclusão de `consultoria_respondi`: `domain/metricas.test.ts`.

## Decisões

### Revisão visual da Black (14/10/2026)

- **Escopo:** revisão visual/UX, sem alterar fontes, fórmulas, cortes ou regras do banco. A Entresafra continua fora de todos os gastos; as outras decisões vigentes seguem iguais.
- **Visão geral:** cards com números em hierarquia mais forte e menos contexto em linha. Investimento em captação mostra o total e a divisão Meta Ads/Google Ads; o clique abre detalhe com cobertura e motivo de campanhas sem entrega ou sem dado. O card de ingresso traz as taxas e barras por segmento dentro da moldura.
- **CPL por etapa:** recolhido por padrão; expandir uma etapa mostra campanhas, conjuntos e métricas disponíveis. CPL continua omitido quando não há valor.
- **Histórico:** o funil diário agora usa polígonos trapezoidais dimensionados pelos valores do dia, com a taxa de passagem entre as etapas e CPM entre impressões e cliques. O gráfico mantém o destaque selecionado e a legenda acessível com investimento do dia e leads acumulados; não exibe meta.
- **Criativos:** título, ranking e leads pagos usam superfícies opacas e texto de maior contraste também no tema claro. Os cinco critérios de ordenação existentes continuam disponíveis, inclusive % MQL.
- **Filtros e modais:** os atalhos de período, período personalizado, funil e canal permanecem. Nos celulares o modal continua centralizado, com respiro ao redor, em vez de ocupar a tela toda.
- **Como testar:** executar `NEXT_PUBLIC_BLACK_DEMO=1 npm run dev -- --webpack -p 3006` em `web/` e abrir `http://localhost:3006/infra/dashboards/csm/black-friday-2026-10`. Na Visão geral, abrir o detalhe de Investimento em captação, expandir uma etapa do CPL e conferir as barras por grupo. No Histórico, escolher dias na régua e passar/focar sobre as barras do gráfico. Em Criativos, alternar todos os cinco critérios. Repetir em claro/escuro e em 1280×900/375×812. A faixa de demonstração permanece visível; os valores locais são fictícios.
- **Evidência visual:** `screenshots-2026-10-14/before/` contém a visão geral anterior nos quatro tamanhos/temas; `after/` registra a visão geral, funil macro, ingresso, modal, CPL por etapa, funil e tooltip do histórico, ranking e ordenações dos criativos. Nenhuma tabela de leads foi aberta. O baseline das abas Histórico e Criativos não foi capturado nesta revisão.
- **Situação:** implementação local na branch `victor-black-visual-2`; não publicada. Sem necessidade de dado novo ou mudança no banco.

- **Profissão com 4 respostas e MQL com estudante (Victor, 12/10/2026, noite).** Advogado, contador, estudante de
  Direito e outros (texto "Outros", padronizado nas páginas). **MQL = advogado, contador ou estudante de Direito**
  (`PROFISSOES_MQL` em `domain/tipos.ts`). A opção "Não trabalho na área, quero organizar o patrimônio da minha
  família", que existia no Respondi, saiu. Substitui a lista anterior de 3 respostas.
- **Google zerado (Victor, 12/10/2026, noite).** Ainda não há campanha de Google. A campanha fictícia continua no
  C3 e no filtro de canal, mas com gasto 0 e sem leads, até existir campanha real.

Do Victor (12/10): funil como filtro global; gaveta lateral na Jornada; aba Criativos aprovada; Perfil geral e
por etapa com mapa; mensageria com dado fictício e selo; sem tabela no Supabase agora; login normal no localhost (opção A).

Do executor (front-end-sr), sem pedido explícito:
- flag `blackDemo` no `env.ts` (regra do repo), mas o teste de `NODE_ENV` fica inline em `infrastructure/fonte.ts`
  para o build de produção descartar o fixture;
- a live absorve o carrinho no nó da Jornada; nós semanais sem fonte mostram "Sem dado";
- com fonte real e config ausente, a tela mostra um aviso vazio em vez de números;
- gaveta lateral própria (`ui/GavetaLateral.tsx`), porque o Drawer canônico é um modal centrado (desde 12/10 ela também escurece o fundo e fecha no clique fora);
- KpiCard envolvido por um `div role=button` (o canônico não tem clique); barras clicáveis próprias;
- alcance e frequência do C1 só quando há uma única campanha no recorte (não somam entre campanhas);
- links (Ver anúncio, Gerenciador, Página) desligados na demonstração; com dado real, só http(s) válido;
- total do investimento só com funil e canal em "Todos" (disparo não tem funil nem canal);
- o funil do dia do Histórico é só da captação (C2 e C3), como na Visão geral;
- a faixa de demonstração não repete o nome dos leads fictícios (para o grep do build ficar limpo).

## O que falta para o dado real (BLOQUEIOS, voltam ao Victor)

1. Granularidade do Meta: o coletor lê `level=campaign`; sem conjunto e anúncio não há CPL por isca, por conjunto do C3, aba de criativos nem miniatura.
2. Fases: `mkt_trafego.fases` não tem DISTRIBUIÇÃO; falta o mapeamento para as 6 fases do Caio.
3. CPL do placar: quais etapas entram e qual UTM carrega o id de campanha, conjunto e anúncio.
4. Profissão: não existe coluna em `pessoas`; faltam os valores brutos dos formulários.
5. "Semana do ciclo": datas e rótulos indefinidos (a demo usa segunda a domingo, provisório).
6. Campanha do criativo da consultoria: não está no documento do Caio.
7. Temperatura: PQ/PF/MIX/ADV (Caio) x Superquente/Quente/MQL/Lançamentos gratuitos (publicos.md).
8. Farol de frequência: fora do teto 3/semana no C3 e remarketing, faixas não definidas.
9. Custo de disparo e LPV do Google: sem fonte. A lista de envios real (título, objetivo, base, copy e métricas por canal, incluindo grupo e e-mail) também não tem fonte ligada; o ATM lê os disparos dele de outra fonte, não sei se serve à Black, precisa confirmar.

Acréscimos da revisão: o grupo legado conta nos 15 mil? Título e descrição do cartão no registro. O parser
`traduzirCampanha` (Marketing › Tráfego) rejeita o gestor `ZZ` dos nomes fictícios: não é usado aqui, mas
qualquer tela que passe esses nomes por ele vai recusá-los.

## Banco: migration B (leads, perfil, grupo e teste)

`infra/supabase/migrations/20261012234606_*` (branch `victor-black-banco-b`), **aplicada em 12/10/2026 23:46 UTC** (versão
`20261012234606`, depois da A e da C). View `dados.black_leads` (fechada) e as RPCs `dados_black_perfil`, `dados_black_leads` e
`dados_black_grupo` (com recorte `{"tipo","valor"}`), mais a marcação de teste com ramo por modelo. Regras de MQL,
ingresso único no grupo e "A corrigir", números e ensaio: [`20261012234606.explain.md`](../../infra/supabase/migrations/20261012234606.explain.md).

## Banco: marcar teste só master e ids do Meta no tráfego (13/10, aplicadas)

Duas migrations, aprovadas pelo pentester e **aplicadas em produção em 13/10/2026** (escritas como `20261013013625` e
`20261013014209`; arquivos renomeados para a versão gravada):

- **`20261013021142`** (aplicada às 02:11:42 UTC; achado bloqueante do pentester): na Black, `dados_marcar_teste` e
  `dados_desmarcar_teste` exigem master (`acesso.eh_master()`, 42501 para os demais), como o presencial. **Marcar e
  desmarcar teste na Black agora é só para master**: quem é da equipe e não é master recebe "sem acesso" (conferido em
  produção, numa transação desfeita). O ATM ficou igual, ainda aberto à equipe (pendência registrada para decisão). O
  desmarcar só toca marcação da própria chave. Detalhe: [`20261013021142.explain.md`](../../infra/supabase/migrations/20261013021142.explain.md).
- **`20261013021259`** (aplicada às 02:12:59 UTC): `dados_black_trafego` devolve `campanha_externa` (em cada item de
  `campanhas`) e `conjunto_externa` (em cada item de `conjuntos`), que a tela já lê para o recorte por campanha e
  conjunto. Conferido em produção: 7 de 7 campanhas e 32 de 32 conjuntos com o id, iguais às tabelas de origem. Nada mais
  muda. Detalhe: [`20261013021259.explain.md`](../../infra/supabase/migrations/20261013021259.explain.md).

Efeito na tela: marcar/desmarcar teste na Black dá "sem acesso" para quem não é master; o recorte do grupo por campanha
e por conjunto passa a receber o id do Meta que a tela lê (a tela em si não foi aberta nesta conferência, só a RPC).
Reverter: os `_reversao.sql` de cada uma.

## Banco: telefone de teste fora do grupo (13/10, aplicada)

**`20261013024435`**, aprovada pelo pentester e **aplicada em produção em 13/10/2026 às 02:44:35 UTC** (escrita como
`20261013023136`; arquivos renomeados para a versão gravada). `dados_black_grupo` só tirava
do grupo a marcação de teste **por fone**, mas as marcações da Black são **por e-mail**: os telefones de teste entravam
nos cards do grupo (auditoria de 13/10). Regra nova, só no CTE `tst`: além da marcação por fone, sai do grupo o telefone
cujos envios da Black são **todos** teste (`dados.teste_ativo`, todos os envios da Black, não só os do período).

- **Telefone misto continua contando** (o caso de "A corrigir": mesmo telefone com um e-mail marcado e outro não). É
  decisão do Victor; quando ele decidir, marcar o outro e-mail ou o telefone basta, sem migration.
- Ensaio (13/10 ~02:40 UTC, todo o período, sem teste): Advogados/Contadores/Outros **90/33/44 → 88/31/42**, únicos nos
  grupos de MQL **112 → 110**. Em cada grupo saem os 2 telefones só de teste; o misto (1 em cada grupo) fica. Leads,
  cruzados e `p_incluir_teste = true` sem mudança. Custo: +~10 ms por chamada (24 → 33 ms).
- **Conferido em produção logo depois** (02:45 UTC, transação desfeita, como master): **88/31/42**, MQL nos grupos **110**,
  total nos grupos **144**; leads 171 únicos / 114 MQL, iguais a antes; travas iguais (chave do ATM P0002, fora da equipe
  e anon 42501). Os cards **Ingresso no grupo** passam a mostrar esses números (a tela em si não foi aberta, só a RPC).
- Detalhe, números por fase e a aplicação: [`20261013024435.explain.md`](../../infra/supabase/migrations/20261013024435.explain.md).
  Reverter: `20261013024435_reversao.sql` (recusa se o corpo vivo não for o desta migration).

## Banco: recorte de criativo com vários anúncios e `metaads` como Meta (APLICADA 13/10)

**`20261013120148`** (arquivos nasceram como `20261013140000`). **Aplicada em 13/10/2026 às 12:01 UTC** pela Management
API, depois do ensaio em transação desfeita (43 de 43 `true` às 11:55 UTC) e da aprovação do pentester. Conferido em
produção: sem recorte nada mudou (92/31/44, 193 únicos, 129 MQL); a lista de anúncios de um criativo passou a devolver
número (`ADV_BF26_09_PROVA_SOCIAL_A`: 3/3, antes 0/0).

- Recorte `{"tipo":"anuncio"}` passa a aceitar uma lista de ids do Meta separados por vírgula (só dígitos e vírgula, até
  2000 caracteres): criativo = anúncios de mesmo nome em vários conjuntos. Os outros tipos não mudam.
- `utm_source=metaads` passa a ser canal `meta` e deixa de cair em `utm_campaign_fora_do_padrao`: no ensaio, 8 envios
  (8 pessoas) mudam de canal; nenhum outro envio nem coluna muda; `dados_black_grupo` sem recorte fica igual.
- **O que muda na tela** (já nesta branch): escolhido um criativo em Criativos, os cards de MQL e de ingresso no grupo
  passam a somar todos os anúncios de mesmo nome (cada pessoa conta uma vez, conta do servidor), em vez de "Sem dado,
  escolha também um conjunto". Com conjunto ou campanha escolhidos, a lista se reduz aos anúncios deles. Lista acima de
  2000 caracteres (cerca de 105 anúncios) continua "Sem dado", com o motivo; nunca um número de outro recorte.
- **Ordem obrigatória:** aplicar a migration antes de a tela ir para a `main`. Antes de aplicada, o servidor compara a
  lista inteira como se fosse um id só: até 200 caracteres ela é aceita e **devolve 0** (número errado, sem erro); acima
  disso, 22023.
- Detalhe, guarda corrigida (md5 vivos), números e caminho de aplicação:
  [`20261013120148.explain.md`](../../infra/supabase/migrations/20261013120148.explain.md).

## Miniatura em 1080 em vez de 64x64 (13/10, publicada)

As miniaturas dos cartões de criativo apareciam borradas. A coleta (`infra/supabase/functions/trafego-meta/anuncios.ts`)
pedia `creative{thumbnail_url}` sem tamanho, e o Meta devolve 64x64 nesse caso (média de 1,4 KB no bucket).

- **Coleta:** `CAMPOS_ANUNCIO` passa a pedir `creative.thumbnail_width(1080).thumbnail_height(1080){...}`
  (`LADO_MINIATURA`). Testado na v23.0 e v24.0 com `/act_<conta>/ads` e filtering: os demais campos voltam iguais, e as
  imagens vêm em 1080x1080 com 43 a 113 KB, abaixo do teto de 1 MB da coleta. Teste novo em
  `web/modules/marketing/trafego/infrastructure/coleta-anuncios.test.ts`.
- **Edge `trafego-meta` publicada** (versão 11) em 13/10/2026 às 12:51 UTC (`npx supabase functions deploy trafego-meta
  --use-api --no-verify-jwt`, a partir de `infra/`).
- **As 83 miniaturas que já existiam foram regravadas** às 12:54 UTC no mesmo caminho (`meta/<conta>/<criativo>.jpg`,
  `x-upsert`), com a imagem de 1080 do mesmo criativo (só host `*.fbcdn.net`, mesmo tipo pelos bytes). Sem mudança no
  banco: a coleta só baixa miniatura de criativo que ainda não tem, então ela não trocaria as antigas sozinha. Depois:
  média de 71 KB, mínima de 41 KB. A tela não mudou (a galeria já carrega com `loading="lazy"`).
- **Voltar:** reverter o commit e publicar a Edge de novo. As antigas de 64x64 ficaram guardadas fora do repo (não
  há motivo para voltar a elas).

## Banco e tela: miniatura e "Abrir no Gerenciador" nos criativos (APLICADA 13/10)

Branch `victor-black-miniatura`. Na aba "Criativos e páginas", os cartões (galeria e gaveta) não mostravam a miniatura
nem os links "Ver anúncio" e "Abrir no Gerenciador": o adaptador gravava os três como `null` fixo. Nada foi redesenhado;
os campos que já existiam na tela passam a receber dado real.

- **Migration `20261013121212`** (escrita como `20261013114630`; **APLICADA** em 13/10/2026 às 12:12 UTC pela Management
  API, depois do APROVADO do pentester e de um segundo ensaio igual ao primeiro; md5 depois `4ecabc5c…`, o esperado):
  `dados_black_trafego` devolve `miniatura_caminho` em cada anúncio e `conta_externa` em cada campanha; função
  `public.trafego_miniatura_pode_ver` e policy `trafego_miniaturas_ler` (só `SELECT`, só `authenticated`, só o bucket
  privado `trafego-miniaturas`): a equipe lê só as miniaturas dos anúncios da Black que ela vê, como o anexo do CRM
  (`crm-midia`). Ensaio em produção, transação desfeita: equipe vê 63 objetos (exatamente as miniaturas da Black, de 80
  no bucket), fora da equipe e anon 0; resultado da RPC sem as 2 chaves novas igual ao de antes; ATM com o mesmo md5 nas
  3 fases; `url_tags` fora. Por que esta via, números e como aplicar:
  [`20261013121212.explain.md`](../../infra/supabase/migrations/20261013121212.explain.md).
- **Miniatura (tela).** `fonte-supabase.ts` pede ao Storage, em lote, URLs assinadas de 900 s para os caminhos
  distintos (`createSignedUrls`, com a sessão do usuário) e guarda em cache por caminho, renovando quando faltam menos
  de 420 s: a releitura de 5 min não reassina nem baixa as imagens de novo. A galeria mostra a imagem no mesmo quadro
  16:10 da fictícia; a gaveta já mostrava quando havia URL. Sem URL (demonstração, sem acesso, caminho fora do formato
  `meta/<conta>/<criativo>.<ext>`, falha), fica a miniatura fictícia de antes, sem erro na tela.
- **"Abrir no Gerenciador".** `https://adsmanager.facebook.com/adsmanager/manage/ads?act=<conta_externa>&selected_ad_ids=<anuncio_externa>`,
  montado só com os dois ids numéricos (senão, sem link) e validado por `safeHttpUrl` (host `facebook.com`). Criativo
  em vários conjuntos usa o anúncio que representa o cartão (o de menor id do grupo de mesmo nome). **Não conferido
  abrindo no Meta com login**: o formato da URL precisa ser confirmado por quem tem acesso à conta.
- **"Ver anúncio" continua desligado** ("sem link na fonte"). A coleta (`infra/supabase/functions/trafego-meta/anuncios.ts`,
  `CAMPOS_ANUNCIO`) não pede `preview_shareable_link`, `effective_object_story_id` nem permalink. Para ligar faltaria:
  pedir um desses campos na Edge, coluna nova em `mkt_trafego.anuncios`, gravar em `trafego_anuncios_receber` e devolver
  na RPC. Não feito, por pedido (sem mexer na Edge agora).
- **Ordem segura.** A tela pode ir para a `main` antes da migration: sem `miniatura_caminho` ela não chama o Storage e
  sem `conta_externa` não monta link (testado). Depois da migration, os dois ligam sozinhos.
- **Como testar.** `cd web && npx vitest run modules/infra/black` (testes novos em `infrastructure/fonte-supabase.test.ts`:
  link do Gerenciador, ids não numéricos, formato do caminho, lote, cache, renovação, sem acesso e RPC antiga). Depois
  de aplicada: abrir a aba "Criativos e páginas" logado como equipe e ver as imagens nos cartões e o botão "Abrir no
  Gerenciador" ligado; no DevTools, um único `POST .../storage/v1/object/sign/trafego-miniaturas` por ~10 min.
- **Conferido depois de aplicar** (banco vivo, como equipe, transação desfeita): 63 objetos visíveis no bucket, 74 de 74
  anúncios da Black com `miniatura_caminho`. **Falta:** conferir o link do Gerenciador com login no Meta.
  Reverter: `20261013121212_reversao.sql` (a tela volta sozinha à
  fictícia e ao botão desligado).

## Banco: ingresso no grupo (webhook n8n e backfill)

Não tem migration: usa o caminho que já existe para o ATM. Situação em 12/10/2026: **o n8n foi publicado às 23:55 UTC
(aprovado pelo pentester na 4ª rodada, testado nos caminhos verde e de recusa, teste apagado) e o backfill foi
aplicado às 23:56 UTC (111 eventos).** Reverter o backfill: `delete from crm.evento_jornada where fonte='sendflow' and
tag like 'BF26 - %' and ocorreu_em < '2026-10-12 23:50+00'`.

Checagem de 12/10 ~23:58 UTC: os telefones com data na planilha batem com o banco (Advogados 47, Contadores 16,
Outros 39). A foto do grupo bate com o total da planilha em Advogados (89) e Contadores (33). Risco: o SendFlow devolve
`export-leads: http 403` para duas das três BF26 em cada ciclo do cron `dados-grupo-foto`. **Corrigido pela migration
`20261013001456`** (aplicada em 13/10 às 00:14 UTC): o ciclo abre no máximo uma foto, primeiro a de quem tem a foto
concluída mais antiga. Cada grupo fica com foto a cada ~10 min.

- **Ao vivo.** SendHook das 3 campanhas BF26 → n8n `B7RBTJkAl9ynPNZh` (`/webhook/bf26-grupo-whatsapp`) → "Filtro BF26"
  → POST na Edge `crm-integracao-webhook/sendflow` (header `x-webhook-secret`) → `crm.evento_jornada` (fonte
  `sendflow`, tag = nome da campanha). Depois disso, a planilha grava como antes, mesmo que o banco falhe, e o nó
  "Confere o banco" deixa a execução com erro quando o banco não gravou. O filtro existe porque a URL do webhook não
  tem autenticação. Ele só deixa passar um evento por chamada, dos 3 `campaignId` da BF26, de entrada ou saída, com
  número, grupo e `createdAt` a até ±2 dias, e reconstrói o corpo. O que ele recusa vai só para a planilha e aparece
  como erro.
- **Histórico.** A aba "Ingressos Whatsapp" da LEADS [BF26] entra em `crm.evento_jornada` com dedup de ±60 s. No
  ensaio e na aplicação foram 111 eventos (Advogados 52 entradas e 1 saída, Contadores 17, Outros 40 e 1). A linha sem
  data fica de fora, porque quem cobre essa pessoa é a foto do grupo (`dados.grupo_participantes`).
- **A reconciliação `dvYnvsyyYofowmQ3` continua só na planilha.** O que ela recupera não tem hora. No banco, quem
  reconcilia é a foto.
- O CNHF não muda: `controle` e o hook `sendflow-webhook` continuam intactos. O Victor desliga no painel do SendFlow os
  hooks de campanha BF26 que estiverem apontando para lá, quando houver.

## Listas para disparo na Mensageria (Fase 1, 13/10/2026)

Topo da aba **Mensageria**, com **dado real**, separado dos blocos de envios que têm o selo de dado fictício
(`ui/BlocoListas.tsx`). As decisões do Victor de 13/10 estão em `Projetos/dashboard-black-friday/CONCEPCAO-LISTAS-MENSAGERIA.md`,
no cérebro dele. A migration é a `20261013180931`; o detalhe e a prova estão em
`infra/supabase/migrations/20261013180931.explain.md`.

- **As 3 listas** (um cartão cada, com a contagem de agora, "atualizado há X min" e os botões **Baixar CSV** e **Ver**):
  1. **Live de consultoria**: todo mundo de todas as fontes, só o geral.
  2. **Fora do grupo da Black**, com as guias Geral, Advogado, Contador e Outros:
     - Advogado inclui estudante de direito;
     - Outros inclui quem não tem profissão, e a tela diz quantos são;
     - quem saiu do grupo também está aqui;
     - aviso fixo: "fora do grupo = sem registro de entrada".
  3. **Saíram do grupo**: da Black ou da consultoria. O CSV traz "Grupo de onde saiu" (Black ou Consultoria e o
     subgrupo) e "Segmento". Também tem guias por segmento.
- **CSV:**
  - colunas `Nome, Email, Telefone`, com BOM e escape, como no `ForaDoGrupo.vue` do CNHF;
  - nome do arquivo `black_<lista>[_<segmento>]_AAAA-MM-DD_HHhMM.csv`, no horário de Brasília;
  - o telefone fora do padrão (DDI estrangeiro, número quebrado, sem o 9 ou sem telefone) nunca entra no CSV principal.
    Ele sai num arquivo à parte, `..._fora-do-padrao_...`, com a coluna Motivo.
- **Ver** abre a gaveta lateral (`PainelLateral` em `ui/GavetaLateral.tsx`) com:
  - busca por nome, e-mail ou telefone;
  - segmento, situação nos dois grupos e as fontes de cada pessoa.
- **Regras (no banco, sem opção na tela):**
  - uma pessoa por linha (telefone, 8 últimos dígitos, ou e-mail);
  - sem teste;
  - **sem a Turma Especial**: a tela mostra quantos foram removidos;
  - grupo da consultoria congelado; "fora do grupo" é sempre em relação ao grupo da Black.
- **De onde vem cada fonte:**
  - **captação:** `metodo.pesquisa_respostas` com origem `metodo-perfeito`;
  - **isca:** `metodo.pesquisa_respostas` (fluxograma), `rede.diagnosticos` (checkup) e `rede.futurometros`;
  - **página da consultoria:** `metodo.consultoria_aplicacoes`. Essas três já chegam pela view `dados.black_leads`.
  - **Fora deste placar:** origem `dp4-thb-vencidos` (Black do THB para acesso vencido, páginas `/dp4` e `/renovacao`
    do timeholdingbrasil.com.br). É outro projeto, com a etiqueta `black-thb-2026-10` gravada em
    `pesquisa_respostas.etiqueta` pelo de-para `metodo.origem_etiqueta` (migration `20261014200000`).
  - **Respondi da consultoria:** `JmSmjBBS`, workspace 3504, pelo `respondi-sync` diário.
    - Quem não terminou o formulário fica **fora** das listas, da planilha e do CSV ("por enquanto não", Victor, 13/10;
      migration `20261013183618`).
    - Essas respostas continuam no banco, marcadas como incompletas.
    - Para religar: `update dados.black_lista_config set incluir_respondi_parcial = true`.
  - **grupo da Black:** os 3 grupos BF26, pela foto do SendFlow e pelo webhook;
  - **grupo da consultoria:** "Consultoria ao Vivo - Aberto", pelo histórico do SendFlow carregado em 13/10 e pela foto.
    O SendFlow não exporta os subgrupos cheios (#1 e #2).
  - **Turma Especial:** `dados.turma_especial_chaves`, só os hashes.
- **Permissão:**
  - os números dos cartões aparecem para quem acessa o dashboard;
  - Ver e Baixar exigem a capacidade **`contato.ver`**. Os masters têm sempre; para os outros, liga com
    `acesso_capacidade_definir`, e quem recebe é decisão do Victor.
  - Em 13/10, por decisão do Victor, receberam `contato.ver`: Victor, Arthur, João Pedro (JP) e Jéssica.
  - Sem a permissão, a tela diz o que pedir.
- **Log:**
  - cada Ver e cada Baixar grava em `dados.black_lista_downloads` quem, ação, lista, segmento, linhas e quando;
  - o registro é gravado pelo banco, não pela tela;
  - consulta: `select * from dados.black_lista_downloads order by em desc`.
- **Recarregar a Turma Especial** quando a planilha da Isabela mudar:
  - o script lê a aba Página1 com a conta Google do Victor, calcula o sha256 na máquina e regrava a tabela inteira;
  - o roteiro está no explain da migration;
  - ainda não é automático: risco anotado.
- **Como testar:**
  1. Abrir `/infra/dashboards/csm/black-friday-2026-10?aba=mensageria` com um master.
  2. Conferir os cartões e baixar um CSV. A linha nova aparece no log.
  3. Com um usuário da equipe que não é master, Ver e Baixar respondem "sem permissão".
- **Planilha automática** (seção abaixo): continua como está, também sem a Turma Especial. **O Apps Script de hora em
  hora é opcional.** Ele não precisa ser instalado, porque o botão do dashboard resolve.

## Lista de disparo automática (13/10/2026)

Planilha: "[BLACK FRIDAY/26] LISTA DISPARO LIVE CONSULTORIA 13/10"
([`1Ym6Lq6y228Xgipn6JAVgCOH6pHmkXKZFxNfd2j3yjEo`](https://docs.google.com/spreadsheets/d/1Ym6Lq6y228Xgipn6JAVgCOH6pHmkXKZFxNfd2j3yjEo/edit)).
O link e o cabeçalho são os mesmos da versão manual: na aba "Lista", `Nome | Email | Telefone`; na aba "Telefone fora do
padrao", `Nome | Email | Telefone (como veio) | Motivo`. Pedido do Victor, com ok em 13/10. A lista é atualizada de hora em
hora. Migration `20261013174100`; o detalhe da regra está em `infra/supabase/migrations/20261013174100.explain.md`.

- **O que é:** a união deduplicada de todos os leads da Black, sem teste e sem a Turma Especial.
- **Fontes:**
  - `dados.black_leads`: captação `metodo-perfeito`, iscas e página nova da consultoria;
  - Respondi `JmSmjBBS`, a aplicação da consultoria, workspace 3504. O `respondi-sync` passou a ler esse workspace, só
    esse slug, uma vez por dia às 09:10 UTC;
  - os 3 grupos BF26 e o grupo "Consultoria ao Vivo - Aberto" do SendFlow, pela foto a cada ~10 min e pelo webhook.
    O grupo da consultoria tem `papel = 'lista'` em `dados.dashboard_grupos`, por isso não entra nos cards.
- **Regra:**
  - a mesma pessoa é reconhecida pelo telefone (8 últimos dígitos) **ou** pelo e-mail;
  - teste sai: marcação, `parece_teste` e, no grupo, o telefone cujos registros são todos teste;
  - telefone no formato `55` + DDD + número;
  - DDI estrangeiro, DDD inválido ou tamanho errado vão para a aba "Telefone fora do padrao", com o motivo;
  - quem só está no grupo entra com nome e e-mail vazios;
  - a Turma Especial (planilha da Isabela) sai no Apps Script, por e-mail ou telefone. Não há casamento por documento,
    porque nenhuma fonte da lista pede CPF.
- **DESLIGADA desde 14/10 (migration `20261014010100`):** `public.black_lista_disparo` não é mais executável por anon
  (nem por mais ninguém além de `postgres`). O Apps Script nunca foi ligado (chave nunca configurada, 0 leituras); a
  lista de disparo é o botão da Mensageria. Religar = migration nova com `grant execute ... to anon`, com o ok do Victor
  e do pentester. O texto abaixo descreve como era.
- **Caminho (OPCIONAL desde 13/10: o botão da Mensageria substitui):**
  - o Apps Script `infra/apps-script/black-lista-disparo/Codigo.gs` é um projeto separado, só do Victor e não
    compartilhado;
  - ele chamaria `public.black_lista_disparo(p_chave)` (até 14/10 executável por anon; hoje fechada). A chave é gerada no próprio Apps Script e
    o banco guarda só o sha256, em `dados.black_lista_config`;
  - a porta aceita no máximo 1 leitura a cada 5 min;
  - cada leitura grava só contagens em `dados.black_lista_leituras`;
  - a guarda de queda faz o script não gravar nada se a lista nova vier menor que a metade da atual.
- **Como testar:**
  - `select dados.black_lista_disparo_montar()->'resumo'` no SQL editor, que roda como postgres e devolve só contagens;
  - `select * from dados.black_lista_leituras order by id desc` mostra as leituras do gatilho;
  - na planilha, a aba "Lista" muda a cada hora.
- **Desligar:** já desligada no banco (`20261014010100`). Se um dia religarem: no projeto do Apps Script, Acionadores,
  apagar o de `atualizar`, ou fechar a porta com `update dados.black_lista_config set chave_sha256 = null`.
- **Reversão completa:** `20261013174100_reversao.sql` e depois desligar o gatilho.

## Conferência de dado tela x fonte e correções (13/10/2026, noite, NÃO aplicadas)

Pedido do Victor (12 itens). Relatório completo, com tela x fonte por etapa, fica no cérebro (entrega do Galego de 13/10).
O que vale para o repositório:

- **CPL geral** (`domain/metricas.ts`, `cplPlacar`): hoje soma as campanhas com o bloco `LEAD` no nome, o que inclui a
  C3 ENTRESAFRA (R$ 596,05 sem nenhum lead pago na base), e divide por **todos** os pagos (14, todos da campanha
  479754). Deve ser: gasto das campanhas de captação C2/C3 (pela etapa do banco, sem remarketing) ÷ leads pagos
  **dessas** campanhas. A ENTRESAFRA entrar ou não é decisão do Victor.
- **Jornada, C1** (`domain/jornada.ts`): "Cortes das consultorias" soma todo o C1 (Teaser + Manifesto); deve ser só a
  campanha de cortes (hoje nenhuma com gasto). O Manifesto pago (fase AQUECIMENTO no nome) cai no "Lembrete de cada
  live"; deve ir para o nó Manifesto. Usar o `subtipo` que a RPC já devolve.
- **Alcance e frequência:** a RPC não mandava total; migration `20261013225000` acrescenta `totais` (período inteiro da
  campanha, `mkt_trafego.desempenho_total`). Front: `mapearTrafego` deixa de fixar `totais: []`.
- **Respondi da consultoria: DESCARTADO** (decisão do Victor, 13/10 ~21h05). Os leads do Respondi da consultoria ficam
  fora do dashboard da Black, que conta só os leads e os grupos da Black. A migration `20261013225100` nunca foi aplicada;
  o registro do que foi proposto está em `infra/supabase/migrations/20261013225100.explain.md`.
- **Regra de MQL (decisão do Victor, 13/10 noite):** a pessoa é MQL pela profissão do **envio mais recente** que tem
  profissão, em todo o dashboard. O banco já usa essa regra (`dados_black_grupo`); o `mqlDoRecorte` do front
  (`domain/metricas.ts`, hoje "algum envio MQL") muda para ela.
- **`entrou_grupo_em` só com o grupo da Black:** migration `20261013225200` (C). Antes o perfil lia
  `dados.v_grupo_pessoas_todos`, que junta todos os grupos da chave, e contava o grupo da consultoria na taxa de grupo
  em 48h, no funil do criativo e no Histórico (aplicada em 13/10 às 23:10 UTC: 135 MQL "no grupo" pelo perfil passou a 97, igual à conta só com o grupo da Black).
- **Páginas:** `mapearTrafego` fixa `paginas: []` e `paginaId: null`, e a coleta do Meta não traz a URL de destino
  (só `url_tags`). Curto prazo: página pelos leads pagos do anúncio. Definitivo: a Edge `trafego-meta` pedir o link do
  criativo (coluna nova).
- **Meta acumulada do Histórico:** sempre nula na fonte real (`configReal`: `inicioCaptacao` e `metaLeadsDia` nulos);
  depende do Victor dizer o início da captação e a meta diária.
- **Google Ads:** sem fonte no banco (`mkt_trafego` só tem Meta).

## Contrato da fonte (`application/ports.ts`)

`FonteDadosBlack` com `modo` (`'demonstracao' | 'real'`), `agora()` e métodos que devolvem
`Resultado<T> = { data, semDado, erro, aviso? }` (`erro` = falha, a tela segura a última leitura e esmaece;
`aviso` = sem dado legítimo com motivo, não é falha). Ações devolvem `ResultadoAcao = { data, erro }`.

## Fonte real (13/10/2026)

Cliente: `createBrowserSupabase()` com a sessão do usuário; só a chave anon pública vai ao navegador. Quem
decide o acesso são as RPCs (`42501` sem acesso, `P0002` fora do cadastro, `22023` parâmetro inválido).
Função que não existe no banco (`PGRST202` / `42883`) vira `semDado` com o aviso **"Fonte ainda não ligada"**,
sem quebrar a tela. Os mapeadores são puros e testados sem rede contra respostas cruas em snake_case
(`infrastructure/respostas-rpc-black.ts`, testes em `infrastructure/fonte-supabase.test.ts`).

| Método | De onde vem | Observações |
|---|---|---|
| `config(chave)` | `dados.dashboards.periodo_inicio` (A): início 04/10/2026, fixo no adaptador | Metas de leads, CPL, régua, orçamento, reserva, previsto por fase, base da casa e data da live **não têm cadastro no banco**: ficam `null` e a tela mostra "Sem dado" / "sem cadastro". Nunca inventadas. |
| `trafego(chave, p)` | `dados_black_trafego(p_chave, p_de, p_ate)` (A) | Centavos viram reais. Métrica que a API não mandou continua `null`. Etapa C1 → funil C1; C2 + subtipo CONSULTORIA → consultoria; C2 + ISCA → iscas; C3 → C3; **etapa null → "Sem etapa"** (seção própria na Visão geral, com o nome exato da campanha e o gasto). `subtipo` e `conflito` preservados. Só plataforma `meta`. Desde `20261013121212` (aplicada 13/10): miniatura por URL assinada do bucket `trafego-miniaturas` (cache de 900 s) e "Abrir no Gerenciador" pela `conta_externa` + `anuncio_externa`; "Ver anúncio" sem fonte. |
| `perfil(chave, p, {incluirTeste})` | `dados_black_perfil` (B) | Uma linha por envio, sem dado pessoal. Os ids do Meta da utm (`campanha_id`, `conjunto_id`, `anuncio_id`) casam com o tráfego pelo anúncio (`domain/alinhar.ts`). Master recebe também os testes (para ver e desmarcar); a tela tira os testes de todas as contas. |
| `leads(chave, ids)` | `dados_black_leads` (B) | Nome, e-mail e telefone só ao abrir a tabela, 50 por página (a RPC aceita até 500). |
| `grupo(chave, p, recorte)` | `dados_black_grupo` (B), sempre `p_incluir_teste = false` | Alimenta os cards **MQLs** e **Ingresso no grupo**. |
| `marcarTeste` / `desmarcarTeste` | `dados_marcar_teste` / `dados_desmarcar_teste` (as mesmas do ATM, `p_motivo = 'teste'`) | Só master. Confirmação antes de marcar; recarrega todos os blocos depois. `parece_teste` aparece como sugestão ("parece teste"), nunca marca sozinho. |
| `mensageria`, `marcos` | sem fonte | `semDado` com aviso "Sem fonte no banco para este bloco." |

### Cards MQLs e Ingresso no grupo (Visão geral, logo depois de "Conversão da página")

- **MQLs** = `leads.mql`; % = `leads.mql ÷ leads.unicos`.
- **Ingresso no grupo**: número grande = `unicos_grupos_mql ÷ leads.mql`. Linhas: Advogados =
  `grupos[advogado].unicos ÷ leads.advogado_mais_estudante`; Contadores = `grupos[contador].unicos ÷ leads.contador`;
  Outros (não MQL) = `grupos[outros].unicos ÷ leads.nao_mql`. Zero ou null no denominador = "Sem dado".
  Mais de um grupo no mesmo segmento = "Sem dado" (somar contaria a mesma pessoa duas vezes).
- **Recorte** (`domain/grupo.ts`, `recorteDaTela` sobre `recorteGrupoDe`): o item escolhido em Criativos vence o
  funil, do mais fino para o mais grosso: **anúncio, conjunto, campanha, página, funil**. Anúncio, conjunto e
  campanha vão como `{tipo, valor}` com o **id do Meta** (`anuncio_externa`, `conjunto_externa`,
  `campanha_externa`, o que vem depois do `|` na utm); o id interno de `mkt_trafego` não serve e o id nunca é
  deduzido pelos leads. Página vai como `isca` (se tiver) ou `porta`. Funil vai como `porta` (C3 =
  `inscricao_direta`, Consultoria = `consultoria`, Iscas = `isca`); "Todos" sem item escolhido = `null` (conta
  simples, sem cruzar). Com recorte, os numeradores passam a ser `unicos_cruzados` / `unicos_cruzados_mql`, com o
  rótulo "dos leads deste nó, quantos estão no grupo", e os dois cards mostram **"Recorte: <nome exato do item>"**
  (ex.: "Anúncio: <nome do anúncio>", "Funil: Consultoria").
- Sem número (o card mostra "Sem dado" com o motivo, nunca o número de outro recorte): C1; filtro por canal; item
  que não está no tráfego do período; anúncio sem `anuncio_externa`; e **campanha ou conjunto enquanto
  `dados_black_trafego` não devolver `campanha_externa` / `conjunto_externa`** (as colunas existem em
  `mkt_trafego.campanhas` e `mkt_trafego.conjuntos`; hoje a função só devolve `anuncio_externa`). O adaptador já
  lê os dois campos (`idExterno`): basta a função passar a mandar, sem mudar a tela.
- A fórmula é a do contrato da B e não muda: únicos no grupo ÷ leads únicos, mesmo que dê 100% ou passe disso.
- **Teste no grupo:** fica fora do numerador o telefone marcado como teste e, desde a `20261013024435` (aplicada em
  13/10), o telefone cujos envios da Black são todos teste. Telefone misto (envio teste e envio não teste) conta até
  o Victor decidir (ver "A corrigir").
- Os outros cards da Visão geral seguem filtrando só por funil e canal; só os dois cards do grupo seguem o item de
  Criativos (por isso o rótulo "Recorte:").
- **Marcar e desmarcar teste** (só master, tabela de leads): as **duas** ações pedem confirmação antes de gravar
  (ressalva do pentester, 13/10).
- Os dois cards abrem a tabela de leads filtrada (envios MQL; envios cuja pessoa entrou no grupo no período).

### Conferência contra o banco (13/10/2026 ~01h35 UTC, período 04/10 a 12/10, sem teste)

Recontado **direto da origem**, sem passar pelas RPCs (tabelas de cada página, `dados.black_leads`,
`dados.marcacoes_teste`, `crm.evento_jornada` e `dados.grupo_participantes`), e comparado com as RPCs. Bateu tudo:

| Medida | Origem | RPC |
|---|---|---|
| Envios / pessoas (sem teste) | 194 / 166 | 194 / 166 (`dados_black_perfil`) |
| Captação | 176 brutos, 172 / 155 | 172 / 155 |
| Consultoria | 25 brutos, 20 / 16 | 20 / 16 |
| Checkup | 5 brutos, 1 / 1 | 1 / 1 |
| Futurômetro | 2 brutos, 1 / 1 | 1 / 1 |
| Fluxograma | 0 | 0 |
| MQL (advogado 84, contador 29, estudante 0) | 113 | 113 |
| Não MQL (outros 40, sem profissão 13) | 53 | 53 |
| Grupo Advogados (webhook 48, foto 90, união 90) | 90 | 90 |
| Grupo Contadores (webhook 16, foto 33, união 33) | 33 | 33 |
| Grupo Outros (webhook 39, foto 42, união 43) | 43 | 43 |
| Únicos nos grupos de MQL / total | | 112 / 145 |

Ingresso no grupo sem recorte = 112 ÷ 113 (99,1%). Os números mudam com a captação (a conferência anterior, ~1h
antes, deu 191 / 165 e MQL 112).

### Nó a nó

| Nó | Na tela | No banco | Casos de borda |
|---|---|---|---|
| Captação (C3, página `captacao`) | inscrições, MQL e grupo do funil C3 | `dados_black_perfil.pagina = 'captacao'`, `porta = 'inscricao_direta'`; grupo com `p_recorte {porta, inscricao_direta}` | teste fora por padrão; sem UTM conta como não pago; telefone sem DDD fica sem UF |
| Método Perfeito | Sem dado | sem fonte ligada à Black | não sei se é página própria da Black: precisa confirmar |
| Consultoria | funil Consultoria | `pagina = 'consultoria'`, `porta = 'consultoria'` | os primeiros envios (12/10 até 20h35) chegaram **sem UTM** (`a_corrigir` = `sem_utm`); a partir daí, com `utm_source=sendflow` |
| Futurômetro | iscas | `pagina = 'futurometro'`, `isca = 'Futurômetro'` | **profissão vazia** (`profissao_vazia`), cai em não MQL |
| Checkup | iscas | `pagina = 'checkup'`, `isca = 'Checkup'` | **profissão vazia**, cai em não MQL |
| Fluxograma | iscas | `pagina = 'fluxograma'`, `isca = 'Fluxograma'` | sem envio no período da conferência |
| C1 | gasto, alcance e vídeo | `dados_black_trafego`, etapa C1 | não gera cadastro: card de grupo mostra o motivo |
| C2 | gasto por consultoria e iscas | `dados_black_trafego`, etapa C2 + subtipo | nome com dois subtipos = `conflito` |
| C3 | gasto e CPL da captação | `dados_black_trafego`, etapa C3 | sem data no envio: a linha é descartada pelo mapeador |

## A corrigir (na fonte, não na tela)

- Profissão vazia no checkup e no futurômetro.
- Consultoria: os envios de 12/10 antes das 20h35 chegaram sem UTM.
- Consultoria: um telefone aparece em 4 envios com dois e-mails diferentes (12/10). Os 2 envios de um e-mail estão
  marcados como teste, os 2 do outro não (a marcação foi por e-mail). Nada foi marcado ou desmarcado: o Victor
  decide se é a mesma pessoa de teste. Até lá, esse telefone **continua contando no grupo** também depois da
  `20261013024435` (ela só tira o telefone cujos envios são todos teste). Em 13/10 ~02:30 UTC havia 2 telefones mistos
  na base, 1 deles nos grupos (contagem feita para o ensaio; qual dos 2 é o caso acima não foi conferido).
- `utm_campaign=disparo` e `utm_campaign=grupoantigo` fora do padrão (`utm_campaign_fora_do_padrao`).
- `utm_term` trazendo o placement.
- CPF01 com `projeto_id` nulo.
- Campanhas sem código de etapa no nome (TEASER, MANIFESTO, CPF01) aparecem como "Sem etapa" até o tráfego
  renomear. A etapa nunca é deduzida.

## Riscos

- Mergear publica o dashboard para quem vê Infra; os dados pessoais saem só por `dados_black_leads`, que tem guarda
  própria (revisada pelo pentester na B).
- Sem recorte, "Ingresso no grupo" divide todos os membros dos grupos de MQL (inclui quem não é lead do período,
  como a base antiga) pelos leads MQL: a taxa pode chegar a 100% ou passar. É a regra do contrato da B; o cruzado
  só existe com recorte.
- Filtro cruzado no cliente não escala para 150 mil leads.
- DDD 42: a tabela `dados.ddd_uf` diz PR (espelhada aqui); a BrasilAPI diz SC.
- Base da casa no config = 188.013; o desenho fala em "cerca de 189 mil".

## Redesign e correções com base no relatório de dados (13/10/2026)

Esta seção substitui descrições anteriores que atribuíam os números de C1 ou o CPL de forma incorreta. O front não
fixa os valores do relatório: continua lendo as RPCs, com os filtros escolhidos. Nenhum dado pessoal foi copiado.

### Regras implementadas

- **C1 na Jornada:** Teaser e Manifesto filtram `etapa_black = C1` pelo `subtipo` exato (`TEASER` e `MANIFESTO`).
  Cortes exige `subtipo = CORTES`; sem campanha marcada assim, aparece Sem dado. Lembrete exige fase
  `AQUECIMENTO` e campanha fora de C1. O nó Assistiu 75% usa o C1 inteiro. Não inferir subtipo pelo nome.
- **Alcance e frequência:** `mapearTrafego` lê `r.totais`, chave `campanha_id` convertida para string, datas `de`/`ate`,
  alcance, frequência e demais campos da migration A. Os totais são de toda a campanha, não do filtro atual. A tela
  os mostra por campanha como “Período da campanha: de X a Y”; nunca soma alcance/frequência de campanhas distintas.
- **Páginas:** cada anúncio só recebe uma página quando os leads pagos daquele anúncio, dentro do período e dos filtros
  atuais, apontam todos para o mesmo texto exato de `dados_black_perfil.pagina`. Sem lead pago = “Página não medida”.
  Se os leads do mesmo anúncio apontarem para mais de uma página, não atribui uma página. URL de destino não existe
  na coleta atual e não é inventada. A correção definitiva depende da Edge Meta obter `link_destino`.
- **MQL por criativo:** taxa = leads pagos MQL ÷ leads pagos com MQL conhecido. O ranking por MQL usa piso de cinco
  leads pagos. Abaixo disso, o cartão vai ao fim, sem posição e com “menos de 5 leads”. A ordem não indica resultado
  confiável para amostras pequenas.
- **CPL geral:** campanhas de captação C2/C3 ÷ leads pagos atribuídos a essas campanhas. Remarketing fica fora.
  Na versão inicial desta revisão, Entresafra era excluída apenas do CPL. Essa regra foi substituída pela decisão de
  14/10/2026: Entresafra sai de todos os gastos e métricas de tráfego.
- **CPL por etapa:** sanfona fechada, uma etapa aberta de cada vez. C1 não mostra CPL, mostra CPM e custo por
  visualização; campanha e conjunto exibem investimento, impressões, cliques, CTR, views de página e leads pagos;
  MQL e CPL só aparecem quando há base para o cálculo. Iscas considera apenas Iscas C3.
- **Histórico:** gráfico e detalhe mostram investimento do dia e leads acumulados, sem linha nem projeção de meta.
- **Investimento em captação:** card em primeiro lugar no Funil macro. Separa Meta e Google. A fonte atual não entrega
  investimento Google: aparece “sem fonte”, não zero; o total fica sem dado enquanto uma fonte estiver faltando.
- **Janela e cadastros:** Respondi `consultoria_respondi` não foi mapeado. A migration B continua aguardando decisão.

### Tela x fonte conferida no relatório do Galego

Período padrão conferido no relatório: 04 a 13/10/2026, sem teste. Os valores abaixo descrevem a fonte e as fórmulas; a
conferência visual autenticada continua pendente.

| Área da tela | Regra/campo | Fonte informada no relatório | Valores de referência |
|---|---|---|---|
| Leads pagos e CPL | Leads com canal pago; investimento das campanhas elegíveis, com Entresafra desligada | `dados_black_perfil`, `dados_black_trafego.gastoCampanhas` | Valores históricos da leitura de 13/10, substituídos pela correção global de 14/10. |
| Investimento em captação | Etapa C2/C3, sem remarketing nem Entresafra; separado por canal | `campanhas[].etapa`, `gastoCampanhas` | Valores históricos da leitura de 13/10, substituídos pela correção global de 14/10. |
| Teaser / Manifesto / Cortes / Lembrete | Subtipo C1 exato / fase AQUECIMENTO fora de C1 | `campanhas[].etapa`, `campanhas[].subtipo`, `campanhas[].fase` | Teaser R$ 15.110,20; Manifesto R$ 3.680,40; Cortes sem dado; Lembrete sem valor de Manifesto atribuído. |
| Alcance e frequência C1 | Total separado por campanha, com intervalo próprio | `dados_black_trafego.totais` | Teaser 200.722 / 4,5930 (04 a 13/10); Manifesto 50.897 / 2,3904 (07 a 13/10). Não somar. |
| C3, páginas e leads | Página de lead pago do anúncio; anúncio sem lead fica não medido | `dados_black_perfil.pagina` por `anuncio_id` | 9 anúncios com lead pago apontam para `captacao`; C2 não tem campanha com veiculação. |
| MQL e grupo | MQL da fonte; pessoas únicas MQL e entradas no grupo | `dados_black_perfil.mql`, `dados_black_perfil.entrou_grupo_em` | 151/222 MQL (68,0%); ingresso 117/151 = 77,5% na regra sem recorte. |
| Histórico, 13/10 | Métricas por dia; acumulado por primeira data da pessoa | `dias_anuncio`, `dados_black_perfil` | Investimento R$ 927,25; C3 R$ 370,74; 6.666 impressões, 90 cliques, 81 LPV; 60 cadastros, 50 pessoas novas, 37 novas MQL, 14 pagos, 9 pagos MQL, 41 entradas no grupo. |
| C1 no CPL por etapa | CPM e custo por visualização; nunca CPL | `dias_anuncio` | Teaser R$ 15.110,20 / 921.921 impressões; Manifesto R$ 3.680,40 / 121.662 impressões. Cortes sem subtipo CORTES = Sem dado. |
| C3 no CPL por etapa | Campanha e conjunto; CPL só quando há lead pago | `dias_anuncio`, `dados_black_perfil`, ids externos de conjunto | Campanha 479754: R$ 333,50, 5.983 impressões, 82 cliques, CTR 1,37%, 74 LPV, 14 pagos, CPL R$ 23,82. Campanha 587257: R$ 14,26 em anúncios, 132 impressões, 2 cliques, 0 pagos. |

**Diferença em aberto:** o relatório do Galego atualiza Consultoria para 73 envios / 62 pessoas; a orientação anterior do
Victor preserva 72. O front não fixa nenhum desses totais e não adiciona Respondi. Confirmar qual número de negócio
deve ser comunicado antes de qualquer ajuste de fonte ou rótulo.

### Testes desta atualização

```bash
cd web
npx vitest run modules/infra/black
npx tsc --noEmit
npx eslint modules/infra/black
npm run lint:tokens
npm run build
```

Os prints autenticados pós-migration C e o registro de números vistos ficam em `.maestri/entregas/black-dashboard-v2/`.
Esta revisão acrescenta a trilha de cálculo e a indicação explícita de valores parciais; o relatório de entrega informa
o que foi validado e as diferenças de agregação ainda pendentes.

### Revisão dos cards de investimento · 13/10/2026

- **CPL geral:** numerador em `dados_black_trafego.dias_campanha[].gasto_centavos`, mapeado como `gastoCampanhas`; o front filtra campanhas classificadas em C2/C3 e tira remarketing e Entresafra. Denominador: linhas de `dados_black_perfil` com `origem = 'pago'`, vinculadas às mesmas campanhas. Os números citados neste parágrafo registram a leitura histórica do print e não são os valores vigentes.
- **Investimento em captação:** a primeira versão do critério e da cobertura descrita nesta revisão foi substituída pela atualização "Investimento de captação fechado com coleta validada" abaixo. A decisão nova fecha Google em zero quando não há campanha e reconhece o zero Meta validado pelo Galego.
- **CPM:** calculado sobre as linhas de `dados_black_trafego.dias_anuncio`, campos `gasto_centavos` e `impressoes`, para os funis de captação que entraram no filtro da tela: `Σ gasto ÷ Σ impressões × 1.000`. A dica do card expõe o numerador e o denominador exatos usados. Não usa o gasto do CPL nem o gasto de todas as etapas.
- **Investimento em tráfego:** soma `dias_anuncio[].gasto_centavos` do período selecionado, em todos os funis/canais presentes na fonte. Não deve ser interpretado como gasto de captação.
- **Investimento com disparo:** a fonte da Black ainda retorna `semFonte` com canais vazios. A tela mostra Sem dado sem selo fictício. O selo fica reservado a dados de demonstração efetivamente carregados.
- **Como testar:** `npx vitest run modules/infra/black/domain/custo-captacao.test.ts`; abrir a Visão Geral em claro e conferir a dica do CPM e a cobertura de campanhas do card de captação. Para conciliar totais atuais, comparar o payload de `dados_black_trafego` e `dados_black_perfil` com o período exibido.

**Exemplo da leitura ao vivo da revisão (20:31 BRT, 13/10):** CPL R$ 380,75 ÷ 15 = R$ 25,38; captação Meta R$ 976,84 medidos em 3/4 campanhas e Google sem fonte, portanto o total de captação permanece Sem dado; CPM R$ 46,21 com R$ 977,21 de gasto por anúncio ÷ 21.149 impressões × 1.000. O tráfego total do período era R$ 19.822,10 (todas as etapas). O Galego confirmou que o custo por campanha é a medida para investimento total; o CPM usa a quebra por anúncio. Esses dois agregados diferiam em R$ 0,37, atribuídos à diferença de granularidade. O CPM de R$ 45,85 no print anterior, com 20.806 impressões, implica cerca de R$ 953,96; como o CPM estava arredondado a duas casas, não é possível recuperar o numerador exato daquela leitura. A dica nova expõe o numerador bruto da leitura atual.

### Regra B de MQL e decisão sobre Respondi · 13/10/2026

- **MQL em toda a tela:** usar a profissão do envio mais recente da pessoa, conforme `dados_black_grupo` (regra B). `domain/metricas.ts` expõe `enviosMaisRecentesPorPessoa`, `ehMqlPorProfissao` e `mqlDoRecorte`; a classificação não usa o booleano `LinhaPerfil.mql`, que representa a regra anterior. Isso se aplica aos percentuais de criativos, Perfil, funil do criativo, cartões por campanha/conjunto e Histórico. Pessoa sem profissão MQL no envio mais recente fica fora do numerador; pessoas únicas continuam no denominador. Empate de horário mantém a primeira linha recebida.
- **Conferência:** em leitura às 20:31 BRT, Galego confirmou 228 pessoas e 154 MQL em `dados_black_grupo.leads.unicos` e `.mql`, regra B. Os 153 eram da foto anterior às 20:18; entrou uma pessoa depois. O teste unitário cobre um caso em que profissão anterior de MQL é substituída por profissão posterior não MQL. O modal MQL lista um envio mais recente por pessoa conforme a mesma classificação.
- **Respondi da consultoria:** decisão do Victor em 13/10: não entra na Black. A tela não consome `pagina='consultoria_respondi'`, não soma esses cadastros e não apresenta seus campos. A migration B citada em histórico deste README não autoriza inclusão na tela.
- **Como testar:** `npx vitest run modules/infra/black/domain`; abrir Visão Geral, Criativos e Histórico; comparar o placar MQL com `dados_black_grupo` e verificar que o modal MQL apresenta pessoas pelo envio mais recente.

### Investimento de captação fechado com coleta validada · 13/10/2026

- **Critério atualizado:** captação é determinada por `dados_black_trafego.campanhas[].etapa` C2 ou C3, sem remarketing. A presença de `LEAD` no nome não é requisito. Isso vale para Investimento em captação e CPL, inclusive para a futura C2 de Consultoria mesmo que o nome não contenha `LEAD`.
- **CPL:** o numerador segue `dados_black_trafego.dias_campanha[].gasto_centavos` para campanhas C2/C3 sem remarketing nem Entresafra. O denominador são os leads pagos vinculados às mesmas campanhas em `dados_black_perfil` (`origem = 'pago'`).
- **Investimento:** usa o gasto por campanha para C2/C3 sem remarketing nem Entresafra, em todos os cards e métricas de tráfego. Google sem campanha cadastrada é exibido como `sem campanha · R$ 0,00`, conforme decisão do Victor em 12/10.
- **Zero de entrega:** `dados_black_trafego.campanhas[].sem_entrega_comprovada` é a fonte de verdade. Sem linha de desempenho e com o campo verdadeiro, a campanha vale R$ 0,00; sem prova continua Sem dado. O detalhe mostra o nome exato e o horário de coleta da RPC.
- **Total:** quando todas as campanhas C2/C3, exceto Entresafra e remarketing, têm desempenho ou zero validado pela fonte, soma Meta + Google. Campanha sem medida e sem confirmação continua parcial; ausência de dado não vira zero por padrão.
- **Como testar:** `npx vitest run modules/infra/black/domain/custo-captacao.test.ts modules/infra/black/domain/metricas.test.ts modules/infra/black/infrastructure/fonte-supabase.test.ts`; na Visão Geral, conferir o total, Google sem campanha e o nome exato e horário de coleta que a fonte devolver para cada campanha sem entrega. `npm run lint:tokens`, `npx tsc --noEmit` e `npm run build`.

#### Estado de coleta genérico · histórico de 13/10/2026

- O adaptador mapeia `campanhas[].primeira_vista_em`, `campanhas[].coleta` (`estado`, `ultima_ok_em`, `ultima_falha_em`, `validade_min`) e `campanhas[].sem_entrega_comprovada`.
- Ausência de linha de gasto só vira zero quando `sem_entrega_comprovada = true`, calculado pela fonte para a campanha e período. Estado de falha, coleta velha, sem coleta ou cobertura incompleta permanece “Sem dado”. O detalhe do card mostra nome exato e horário da coleta validada, ou o motivo explícito da pendência.
- Naquele registro, o contrato ainda aguardava aplicação. O estado atual é descrito na seção de 14/10 abaixo.
- A tela não conhece IDs ou nomes especiais para determinar zero. Campanhas novas seguem o mesmo contrato automaticamente.
- Como testar: mapeador em `infrastructure/fonte-supabase.test.ts`; regra genérica, campanha validada, cobertura incompleta e falha recente em `domain/custo-captacao.test.ts`.

### Correção global de Entresafra e confirmação de zero · 14/10/2026

- **Decisão do Victor:** a campanha `CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD` fica fora de todo gasto do dashboard. Não entra no Investimento em captação, Investimento total, Investimento em tráfego, Verba contra o orçamento, CPL, CPM, CPC, CTR, impressões, cliques ou outros agregados do funil macro. Os filtros de desempenho removem os dias da campanha também nos detalhes e na gaveta de criativo. O filtro é por subtipo `ENTRESAFRA` ou pelo token exato `ENTRESAFRA` no nome, sem ID fixo.
- Cards e detalhes exibem a nota **“Entresafra fora de todos os gastos (decisão do Victor)”**.
- A regra de zero vem de `dados_black_trafego.campanhas[].sem_entrega_comprovada`, mapeada para `semEntregaComprovada`. A RPC foi aplicada pelo Galego em 14/10/2026. O front não fixa ID ou nome para converter ausência de linha em R$ 0,00.
- Conferência necessária após a atualização: registrar na entrega os valores anteriores e os novos valores lidos na tela, separando Investimento em captação, Investimento total, Investimento em tráfego, Verba contra o orçamento, CPL, CPM, CPC, CTR, impressões e cliques. Os números do snapshot antigo não são reutilizados como leitura atual.
- Testes: `npx vitest run modules/infra/black/domain/metricas.test.ts modules/infra/black/domain/custo-captacao.test.ts`; verificar também a tela de Visão Geral e o detalhe dos cards. Nenhum dado pessoal deve aparecer em print ou relatório.

### Correções da auditoria visual · 14/10/2026

- **Cards da Visão geral:** Captação agora é o primeiro card do placar, com total e divisão Meta/Google. Os demais cards ficaram com rótulo, valor e indicador visual; explicações, alvos, cobertura, horário e regra de cálculo foram para o tooltip ou para o modal. O CPL conserva o farol compacto; meta ideal e limite permanecem na dica.
- **Histórico:** as etapas do funil diário são trapézios centralizados, com larguras dinâmicas estritamente decrescentes e a mesma forma em cada etapa. As taxas entre etapas permanecem. O contexto dos quatro KPIs foi transferido para dicas acessíveis.
- **Altura e rótulos:** o grid do funil macro não força mais a mesma altura para todas as linhas; os cards baixos não ficam esticados pelo card de Ingresso. Até 1320 px, rótulos longos quebram linha em vez de truncar.
- **Modal e ordenação:** overlay do modal ocupa também a faixa de scrollbar em telas estreitas; no modal de captação a divisão de canais aparece uma vez só. O seletor de ordenação da galeria abre as cinco opções: Mais leads, Menor CPL, Maior CTR, Mais gasto e Maior % de MQL.
- **Dados reais, somente leitura:** teste local com `NEXT_PUBLIC_BLACK_DEMO` removida do ambiente. No período padrão, 04 a 13/10, a tela mostrou 229 leads únicos e 154 MQL. Galego confirmou os mesmos totais em `public.dados_black_grupo`, sem teste e com a janela padrão, às 01:18 UTC de 14/10; consulta em transação desfeita. Nenhum dado foi gravado.
- **Evidências:** `screenshots-2026-10-14/revisao-maestro/` contém Visão geral e Histórico em claro e escuro, desktop e celular; o modal mobile claro; e o seletor de ordenação aberto (captura visual sem dado pessoal).
- **Como validar:** na raiz de `web/`, executar `npx vitest run modules/infra/black`, `npx tsc --noEmit`, ESLint nos arquivos alterados, `npm run lint:tokens` e `npm run build`. Abrir a rota da Black no localhost, alternar Visão geral/Histórico, redimensionar para 1280×900 e 375×812, abrir o modal de Captação e o seletor de ordenação. Para comparar os totais reais, remover `NEXT_PUBLIC_BLACK_DEMO` do ambiente de inicialização e conferir `dados_black_grupo.leads.unicos` e `.mql`; não abrir tabelas de pessoas.
- **Estado:** revisão local na worktree `victor-black-visual-2`, ainda sem commit, PR, merge ou deploy.

### Auditoria da rodada visual 2 · 13/10/2026

- **Funil do Histórico:** Leads pagos continua sendo a etapa de entrada do recorte. MQL agora é contado somente entre as pessoas que tiveram lead pago, usando a profissão do envio mais recente pela regra B. A taxa usa o total de leads pagos como denominador. Ingresso conta somente quem pertence a esse mesmo conjunto de MQL pagos e entrou no grupo. O MQL total continua nos indicadores gerais, fora do funil diário. No dia 13/10, a tela mostrou 16 leads pagos, 9 MQL pagos (56,3%) e 5 desses MQL no grupo (55,6%).
- **Placar em 1280 px:** os cinco cards ficam alinhados em duas linhas, três na primeira e dois na segunda. Os cards das duas linhas preenchem a altura do respectivo grid. Em mobile, ficam em uma coluna.
- **Modal de captação:** a revisão visual em 375×812 não mostrou bolinha no divisor sob a campanha; o overlay cobre a largura e não há rolagem horizontal. A bolinha do print anterior era o indicador vermelho de posição do cursor do portal, fora do DOM do produto. Para a nova evidência, o cursor foi movido para a margem vazia antes da captura. O selo preto `N` fora do modal é o indicador de desenvolvimento do Next.
- **Conferência dos investimentos com Galego:** leitura apenas, sem escrita no banco. Para a coleta de 21:45 ou 22:15, os três valores auditados estavam corretos: captação R$ 450,42, tráfego total R$ 19.507,95 e investimento de 13/10 R$ 1.273,86. Na coleta seguinte, às 22:45, foram R$ 479,68, R$ 19.570,61 e R$ 1.336,52, respectivamente. O total do tráfego cobre todos os funis no período; o investimento do dia usa a mesma regra, restrito a 13/10. Captação usa somente C2/C3. A diferença do snapshot antigo corresponde a R$ 19.057,53 de C1, obtida pela diferença entre os agregados daquele mesmo snapshot. Na leitura de 22:45, C1 somou R$ 19.090,93. Galego identificou Teaser, Manifesto e Fake Live Consultoria como campanhas C1 com gasto. Não há campanha de remarketing nem C2 no banco nessa leitura. Entresafra fica fora de todos os valores.
- **Fontes:** captação soma `dados_black_trafego.dias_campanha[].gasto_centavos` para campanhas C2/C3 elegíveis, incluindo zero somente quando `sem_entrega_comprovada` valida a coleta. Tráfego geral e investimento diário somam `dados_black_trafego.dias_anuncio[].gasto_centavos`, em todos os funis e no dia selecionado, removendo Entresafra. Por campanha e por anúncio os agregados fecham após a coleta; durante o dia podem divergir alguns centavos entre coletas.
- **Leitura na tela às 22:55:** investimento em captação R$ 479,68, tráfego R$ 19.570,61, leads únicos 229 e MQLs 154. No Histórico de 13/10, investimento do dia R$ 1.336,52; o funil exibiu 16 → 9 → 5 para pagos, MQLs pagos e ingresso no grupo dos MQLs pagos. São valores da tela no instante indicado, pois a coleta ainda varia às 15 e 45 minutos.
- **Dica do CPL:** o texto de cálculo, alvo e exclusões está no atributo `title` do card e foi conferido no DOM. O screenshot do portal não renderiza o balão nativo do navegador. `detalhe-cpl-1280-light.png` mostra a mesma regra no modal aberto pelo card; `cpl-card-contexto-1280-light.png` registra o card com farol em claro.
- **Evidências reais, sem demonstração:** `screenshots-2026-10-14/revisao-maestro-2/`. Inclui a Visão geral completa em 1280 e 375, claro e escuro; CPL C3 aberto; filtro Personalizado aberto; card de captação em modal mobile; modal de detalhe do CPL em claro; tela de Criativos em claro; e Histórico com o funil completo em claro. Em 375 px, `document.documentElement.scrollWidth` não excedeu `innerWidth`. Não houve log de console após atualizar a página. O banner de demonstração estava ausente.
- **Como testar:** executar `npx vitest run modules/infra/black/domain/historico.test.ts`, `npx vitest run modules/infra/black`, `npx tsc --noEmit`, `npx eslint modules/infra/black`, `npm run lint:tokens` e `npm run build`. Abrir a rota Black em sessão QA local sem `NEXT_PUBLIC_BLACK_DEMO`, conferir as etapas 16, 9, 5 em 13/10 e abrir o card de captação em modal estreito.
- **Estado:** worktree `victor-black-visual-2`, sem commit, PR, merge ou deploy.


### Ajuste do card Ingresso no grupo · 14/10/2026

- Na Visão geral, cada grupo agora apresenta o rótulo em uma linha própria, seguido pela taxa e pela contagem. Isso evita que “Advogados”, “Contadores” ou “Outros (não MQL)” encostem nos percentuais em 1280 px.
- Conferido no portal local com dados reais em viewport de 1280 px, tema claro e escuro. Capturas: `screenshots-2026-10-14/revisao-maestro-2/ingresso-1280-light.png` e `ingresso-1280-dark.png`.
- Testes: componente validado na tela local; executar `npx vitest run modules/infra/black`, `npx tsc --noEmit`, `npx eslint modules/infra/black/ui/AbaVisaoGeral.tsx`, `npm run lint:tokens` e `npm run build`.
- Estado: correção local na worktree `victor-black-visual-2`, sem commit ou publicação.


### % de MQL e Histórico no estilo do funil de Criativos (14/10/2026, acréscimo do Victor)

- **% de MQL** aparece ao lado do card MQLs no Funil macro. O rótulo anterior “Potencial de MQL” foi substituído para nomear diretamente a taxa exibida, inclusive no detalhe aberto pelo card. O cálculo não muda: Regra B (profissão do envio mais recente com profissão) e MQL ÷ pessoas únicas de cada recorte. O cartão compara a taxa geral e a parcela C2/C3 com a meta de 60% definida pelo Victor, usando o mesmo farol do placar. O cálculo único é `mqlDoRecorte` (`domain/metricas.ts`) e o mesmo resultado alimenta o total de MQL e a taxa.
- No **Histórico**, o botão de reprodução automática foi removido. A régua de datas continua permitindo navegar pelos dias; o funil usa o componente SVG `FunilTrapezio` compartilhado com Criativos e destaca uma etapa sob foco ou cursor. O gráfico de investimento continua com barras e linha, e o acumulado de pessoas usa `pessoasUnicas`, de todas as portas e sem filtro, para bater com Leads contra a meta.
- Métricas compartilhadas: pessoas únicas em `pessoasUnicas`; CPL de captação em `cplPlacar` (com `cpl` para divisão); CPLs por etapa também deduplicam com `cplDo`; conversão de página deduplica com `conversaoPagina`; connect rate usa `connectRate`; investimento de captação usa `investimentoCaptacao`. Inscrições do Funil macro contam pessoas únicas atribuídas a C2/C3.
- Para revisar: no período `desde-inicio`, comparar Leads contra a meta com o acumulado do Histórico; mudar período e filtro e confirmar que Inscrições, MQL e % de MQL acompanham o recorte; passar o cursor por cada etapa do funil do Histórico. Testes: `domain/metricas.test.ts` e `domain/historico.test.ts`.

### Placar v3, funções centrais e alias de ISCAS (14/10/2026)

- `domain/numeros.ts` reúne o cálculo e o rótulo de recorte para pessoas únicas, inscrições C2/C3, pagos atribuídos a campanhas C2/C3, investimento por campanha (`dias_campanha`), CPL de captação, MQL do servidor, % de MQL, connect rate, conversão da página e as três métricas de ingresso no grupo. Cards explicitam período, campanhas C2/C3 ou base de pessoas conforme a métrica.
- Leads acumulados no Histórico usam `acumuladoLeadsPessoas`, a mesma regra de pessoa única de `leadsPessoas`, processada em uma passagem por eficiência. O número diário de pagos também deduplica por pessoa. MQL escolhe o envio mais recente que tem profissão, alinhado à regra do servidor; pessoas sem profissão continuam na base do denominador.
- Visão Geral e Criativos/Páginas compartilham os cálculos de connect rate e conversão da página. O gasto de investimento em tráfego usa a soma por campanha de `dados_black_trafego.dias_campanha`; campanhas de Entresafra ficam fora e ausência de dado sem confirmação não vira zero.
- O placar começa com Investimento total, Investimento em tráfego e Investimento com disparo, cada um com barra contra o limite visível. CPL sai do placar e entra no Funil macro; Inscrições são pessoas únicas C2/C3; % de MQL mostra MQL ÷ base única do mesmo recorte, com meta de 60% para o total e o tráfego. `cplCaptacao` recebe gasto de campanha e pagadores únicos atribuídos ao recorte em Visão Geral e Jornada.
- No Histórico, a reprodução automática foi removida. A régua escolhe o dia; o funil escalonado realça a etapa em hover/foco e usa connect rate e conversão de página compartilhados com a Visão Geral.
- O painel da aba Histórico não usa mais a animação inicial que podia manter todo o conteúdo transparente quando a página estava em segundo plano. Assim, a régua, o funil e as séries continuam visíveis em retomadas e capturas do navegador.
- O campo `mkt_trafego.etapa_black` classifica subtipo por token exato. A migration `20261014130200` foi aplicada em produção em 14/10/2026 às 13:17:38 UTC e adiciona `ISCAS` como alias de `ISCA`; a tela recebe a classificação pela RPC existente `dados_black_trafego`. Ensaio, hashes, reversão e comprovação estão em `infra/supabase/migrations/20261014130200.explain.md`.
- Na leitura ao vivo registrada às 13:27 UTC, a campanha `CF | BF26 | C2 | ISCAS | CAPTAÇÃO | META | PQ | ABO | LEAD` aparece como C2 / ISCA, com R$ 52,02 e 9 leads pagos. O total de tráfego sem Entresafra é R$ 20.177,70. Os valores R$ 43,69, 6 leads e R$ 20.109,28 eram de uma fotografia anterior e já não correspondem à fonte atual.
- Fonte das métricas financeiras: `dados_black_trafego.dias_campanha`; leads e profissão: `dados_black_perfil`; ingresso agregado por grupos: `dados_black_grupo`. Para valores reais atuais, conferir as RPCs com o Galego; contagens variam com novas inscrições e coletas.
- Como testar: `npx vitest run modules/infra/black/domain/numeros.test.ts modules/infra/black/domain/metricas.test.ts modules/infra/black/domain/historico.test.ts modules/infra/black/domain/criativos.test.ts modules/infra/black/domain/jornada.test.ts`, `npx tsc --noEmit` e abrir a Black local. A migration tem ensaio e reversão próprios em `infra/supabase/migrations/20261014130200_*.sql`.

### Desfazer filtro do funil (14/10/2026)

- Na faixa **Funis lado a lado**, o card atualmente filtrado troca “Filtrar” por “Limpar filtro”; o botão volta para `funil=todos`. Os demais cards continuam trocando o filtro.
- Um aviso fixo abaixo do seletor global mostra `Filtrando: <funil>` e o botão “Limpar” em todas as abas enquanto houver um funil ativo, inclusive depois de rolar a página. O seletor global já inclui “Todos”.
- O valor `?funil=c2` é o agregado de Consultoria + Iscas. Ele filtra as duas categorias e deixa as demais apagadas; como a RPC de grupo aceita uma porta por chamada, o bloco do grupo mostra “Sem dado” com esse motivo nesse recorte.
- A aba Criativos e páginas já permite remover cada filtro pela trilha (`TrilhaFiltro`) e oferece limpar todos; não havia outro botão “Filtrar” na interface Black.
- Teste local: abrir a Visão geral, usar “Filtrar” em Iscas, confirmar o aviso e “Limpar filtro” no card; limpar pelo aviso, atualizar a página e conferir que `funil=todos` permanece na URL. Abrir também `?funil=c2`, conferir Consultoria + Iscas e limpar.

### Ajustes de legibilidade e explicação das bases · 14/10/2026

- No Histórico, o rótulo da última etapa do funil quebra em duas linhas quando contém “ · ” para permanecer dentro do trapézio. O valor de “Investimento em captação” usa fonte responsiva e `nowrap`, sem quebrar centavos.
- **Connect rate** vem de `dados_black_trafego.dias_anuncio`: soma LPV ÷ soma de cliques no link, somente nas linhas C2/C3 onde ambos os campos existem. Na leitura conferida, período: 193 ÷ 203 = 95,1%; 14/10: 58 ÷ 61 = 95,1%. Cliques totais (206 e 62) incluem respectivamente três e uma linhas sem LPV, que não entram nessa taxa. O Histórico calcula com as linhas do dia selecionado; a coincidência com o percentual do período é arredondamento, não reutilização do dado do período.
- **CPM** também vem de `dados_black_trafego.dias_anuncio`: soma do gasto por anúncio ÷ soma das impressões × 1.000. Na leitura conferida, R$ 748,11 ÷ 14.840 × 1.000 = R$ 50,41. “Investimento em captação” usa `dias_campanha`, agregado por campanha, que nessa leitura soma R$ 747,25 e 14.822 impressões. O coletor faz chamadas independentes à Meta nos níveis de campanha (`insights?level=campaign`) e anúncio (`insights?level=ad`). No dia 14/10, as leituras foram gravadas com 20 segundos de diferença e tiveram totais distintos; em 13/10, ambos os níveis coincidiram. Assim, o numerador de CPM e o investimento de captação vêm de fontes em níveis diferentes. A dica do CPM mostra sua fonte, fórmula e numerador/denominador atuais.
- **Hora de leitura:** o texto “Lido às” é formatado com `America/Sao_Paulo`; 11:09 no print corresponde ao horário de Brasília daquela leitura. O ponto vermelho sobre a aba “Visão geral” no print anterior era o indicador do cursor do portal, não elemento da tela.
- **Como testar:** `npx vitest run modules/infra/black`; conferir o hover de Connect rate, o detalhe do CPM, o número de captação em 1280 px e o rótulo do funil no Histórico.

### Placar geral x tráfego · 14/10/2026

- **Leads:** o número principal continua sendo pessoas únicas de todas as portas em `dados_black_perfil` (hoje 251). A linha menor mostra a parcela atribuída a campanhas pagas C2/C3 (hoje 35). O card de Leads no Funil macro agora segue a mesma hierarquia. A conversão da página permanece apenas C2/C3.
- **MQL:** o número principal usa a Regra B sobre todos os leads do período: profissão do envio mais recente com profissão, uma pessoa por lead (169 de 251). A linha menor mostra MQL atribuídos ao tráfego C2/C3 (22 de 35). `% de MQL` apresenta as duas bases: geral e tráfego.
- **Ingresso no grupo:** geral = pessoas únicas com `entrou_grupo_em` em `dados_black_perfil` ÷ todas as pessoas únicas. A linha menor mostra o mesmo cálculo para leads atribuídos a C2/C3. A fonte do total geral hoje é 142/251; no tráfego, 17/35. Essa métrica inclui qualquer profissão e entradas aproximadas pela foto do grupo. Não usar `dados_black_grupo.unicos_grupos_total` como substituto: essa RPC conta pessoas por grupo, com semântica diferente.
- **Funil do Histórico:** o último estágio agora é ingresso na coorte de todos os leads do dia, dividido por todos os leads novos dessa coorte. Abaixo do número do grupo, a tela mostra `de N leads do dia` para explicitar o denominador. O estágio de MQL pagos segue seu recorte anterior. O filtro de período, funil e canal continua atuando sobre a série.
- **Fonte e cobertura:** Galego confirmou em leitura somente leitura às 14:24:49 UTC que `dados_black_perfil` contém 292 linhas para 251 pessoas, `mql` preenchido em todas, `entrou_grupo_em` disponível (142 pessoas), incluindo origens sem tráfego. `dados_black_grupo.leads.unicos/mql` fechou em 251/169. A diferença entre 142 pessoas com entrada no perfil e 165 `unicos_grupos_total` decorre de bases distintas; a tela usa o perfil e deduplica pessoa.
- **Como testar:** `npx vitest run modules/infra/black`, `npx tsc --noEmit` e abrir Visão Geral e Histórico na Black sem o modo demo. Conferir 251/35, 169/22, 169÷251 e 22÷35, 142÷251 e 17÷35; conversão da página deve continuar em tráfego C2/C3.

### V5: leads e ingresso por grupo, funil geral no Histórico (14/10/2026)

- **Leads totais:** pessoas únicas por `pessoaId` em `dados_black_perfil`, excluída a porta `consultoria_respondi`. No placar, o principal é desde o início; abaixo, “Do tráfego C2/C3” conta pessoas únicas pagas atribuídas a campanhas de captação. Em outros recortes, período, funil e canal ativos são respeitados.
- **Ingresso geral:** pessoas únicas com `entrou_grupo_em` preenchido ÷ pessoas únicas no mesmo recorte. **Ingresso do tráfego:** essa mesma conta só para pessoas pagas C2/C3. A tela informa numerador, denominador e percentual, incluindo entradas aproximadas pela foto.
- **Advogados, Contadores e Outros:** usa `grupos[].leads_no_grupo ÷ grupos[].leads_do_segmento` de `dados_black_grupo`. Denominadores são: advogado + estudante de Direito; contador; e outros, respectivamente. Numeradores e bases vêm do banco em cada leitura, nunca de valores fixos. `leads_em_algum_grupo` é a união de pessoas e `leads_em_mais_de_um_grupo` informa a sobreposição. A tela compara soma dos segmentos com a união e explica a diferença sem presumir quantas estão em dois ou três grupos. `grupos[].unicos` continua sendo total de membros, não substitui o cruzamento de leads.
- **Histórico:** seletor “Dia a dia | Geral”, padrão Dia a dia. `historico=geral` fica na URL; remover o parâmetro retorna ao padrão. Geral usa as mesmas etapas e ordem e respeita funil/canal selecionados. Impressões, cliques e views usam `dados_black_trafego.dias_anuncio` e as funções compartilhadas; leads pagos e MQL são deduplicados por pessoa; a última etapa é ingresso geral da coorte de primeiro cadastro no período, com denominador explícito. A soma diária mantém uma única coorte por pessoa que tem mais de uma porta.
- **Testes:** `domain/recorte.test.ts` verifica o modo na URL e a volta ao padrão; `domain/historico.test.ts` cobre soma por coorte, pessoas únicas e ingresso posterior ao primeiro cadastro; `infrastructure/fonte-supabase.test.ts` verifica o mapeamento do novo contrato de grupos com dados sintéticos. A conferência visual foi feita no portal local com leitura real, sem abrir tabela de leads. Não houve consulta direta nem alteração no banco.
- **Atualização de fonte (16:34 UTC):** RPC agora traz os cruzamentos por grupo e a união; mapeamento e resumo usam esses campos. Teste de mapeamento sintético incluído. Valores de produção conferidos na sessão visual, sem consulta direta ao banco.
- **Estado:** código preparado na branch `victor-black-v5-leads-grupos`, aguardando revisão do Maestro. Sem alteração de banco.

### Regra da taxa geral de ingresso · 14/10/2026

- A taxa geral da Visão Geral e o resumo geral de leads usam `dados_black_grupo.ingresso_geral`, que contém `numeros_unicos_no_grupo`, `leads_unicos` e `pct`. A fórmula exibida é **números únicos que entraram no grupo ÷ leads únicos**; não se cruza o telefone de cada membro com os leads.
- O percentual é recebido em pontos percentuais e convertido para a fração usada pelos componentes de taxa. Numerador e denominador também vêm do objeto para os detalhes do cartão.
- Quando `p_recorte` é aplicado, a RPC devolve `ingresso_geral = null`; o front mantém o cálculo cruzado já existente para tráfego, canal, criativo e MQL. O detalhe de tráfego do placar segue cruzado mesmo na visão geral.
- Se a resposta antiga não tiver o campo, a tela mantém a métrica legada durante atualização gradual; se o campo vier explicitamente null sem recorte, mostra Sem dado. Nenhum null vira zero.
- Mapeamento: `web/modules/infra/black/infrastructure/fonte-supabase.ts` (`mapearGrupo`). Cálculo e seleção por recorte: `web/modules/infra/black/domain/numeros.ts` (`ingressoGrupoGeral`).
- Testes: `npx vitest run modules/infra/black/domain/numeros.test.ts modules/infra/black/infrastructure/fonte-supabase.test.ts`.
