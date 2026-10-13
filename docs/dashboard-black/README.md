# Dashboard da Black Friday 2026 (Infra › Dashboards › CSM)

Rota: `/infra/dashboards/csm/black-friday-2026-10` · módulo `web/modules/infra/black/` · branch `victor-black-dashboard`.
Pedido do Victor Hugo (12/10/2026). Desenho e plano técnico no cérebro do Victor
(`Projetos/dashboard-black-friday/DESENHO-DASHBOARD-V2.md` e `PLANO-TECNICO-V2.md`).

## Situação

- **Ligado no banco (13/10/2026).** A fonte real (`infrastructure/fonte-supabase.ts`) chama as RPCs
  `dados_black_*` do Supabase com a sessão do usuário (mesmo padrão do ATM). Migrations no ar: A
  `20261012231649` (cadastro e `dados_black_trafego`), C `20261012233334` (trava de modelo nas RPCs
  presenciais), B `20261012234606` (`dados_black_perfil`, `dados_black_leads`, `dados_black_grupo`, marcar teste)
  e a foto do grupo `20261013001456`. Detalhe de cada método na seção "Fonte real" abaixo.
- **Não mergeado, sem push.** A decisão de levar para a `main` (deploy automático) é do Maestro/Victor no fim.
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
  remarketing ÷ leads que vieram de anúncio); a conta não mudou. O gráfico **por fase** (card de investimento e
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
   (total = tráfego + disparo, tráfego por canal, disparo fictício, por fase x previsto); funil macro só da
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
celular); a lista de estados do mapa do Perfil tem 24 px de altura; e no desktop a lista do card Ingresso no grupo
continua vazando para baixo da moldura (corrigir mudaria o 1440).

## Decisões

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
| `trafego(chave, p)` | `dados_black_trafego(p_chave, p_de, p_ate)` (A) | Centavos viram reais. Métrica que a API não mandou continua `null`. Etapa C1 → funil C1; C2 + subtipo CONSULTORIA → consultoria; C2 + ISCA → iscas; C3 → C3; **etapa null → "Sem etapa"** (seção própria na Visão geral, com o nome exato da campanha e o gasto). `subtipo` e `conflito` preservados. Só plataforma `meta`. |
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
