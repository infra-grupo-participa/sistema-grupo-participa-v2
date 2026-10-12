# Dashboard da Black Friday 2026 (Infra › Dashboards › CSM)

Rota: `/infra/dashboards/csm/black-friday-2026-10` · módulo `web/modules/infra/black/` · branch `victor-black-dashboard`.
Pedido do Victor Hugo (12/10/2026). Desenho e plano técnico no cérebro do Victor
(`Projetos/dashboard-black-friday/DESENHO-DASHBOARD-V2.md` e `PLANO-TECNICO-V2.md`).

## Situação

- **Só dado fictício.** Nada lê banco nem rede. O adaptador real (`infrastructure/fonte-supabase.ts`)
  devolve "Sem dado" em tudo, sem chamada nenhuma.
- **Nenhuma migration, nenhuma tabela nova.**
- **Não mergeado.** Mergear hoje publica um cartão com tudo "Sem dado" para todos os admins (ver Riscos).
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

## O que foi feito (5 abas, filtro global)

Seletor global: funil (Todos, C1, Consultoria, Iscas, C3), período (Hoje, 7 dias, Desde o início, Semana do
ciclo) e canal (Todos, Meta, Google). Tudo mora na URL. Releitura a cada 5 min só com a aba visível.

1. **Visão geral:** placar (até a live, leads x meta, CPL x régua, verba x orçamento); investimento do período
   (total = tráfego + disparo, tráfego por canal, disparo fictício, por fase x previsto); funil macro só da
   captação; funis lado a lado; CPL por etapa. Todo card abre o **modal com sub-abas fixas** (Por funil, canal,
   fase, dia, criativo, Perfil; a que não cabe diz "Não se aplica a este card").
2. **Jornada:** o fluxograma do Arthur vivo, setas com espessura pelo volume e fluxo animado; o funil filtrado
   apaga os outros nós. Clicar no nó abre a **gaveta lateral** (Etapa · Criativos · Perfil).
3. **Criativos e páginas:** trilha Campanha › Conjunto › Criativo › Página com chips; painéis de campanhas e
   conjuntos em barras; galeria com miniatura fictícia e ordem por chips; cartões por página. O criativo abre a
   gaveta com miniatura, mini-funil, curva diária e os 3 botões (desligados na demonstração).
4. **Mensageria:** API, SMS e ligação com enviados, entregues, cliques ou atendidas, custo, custo por clique,
   ingresso e presença; régua de API do grupo (+2h, +12h, +24h). Selo "dado fictício".
5. **Histórico:** régua de dias com play que "toca" o funil do dia e o gráfico de investimento por dia com
   pessoas acumuladas contra a meta acumulada.

Perfil dos leads (modal, gaveta): profissão, estado pelo DDD (mapa do Brasil com bolhas, malha do IBGE),
região, utm_source, página, base de origem, isca; tudo clicável e encadeado; tabela de leads sob demanda.

## Fórmulas (regra única: razão = soma sobre soma, mesmo recorte; sem dado nunca vira zero)

- CPL = gasto ÷ leads pagos (só cadastro com origem paga). CPL do placar (provisório, BLOQUEIO 3): gasto de
  captação + remarketing ÷ leads pagos. Farol pela régua do Caio: até R$ 15 verde, até R$ 20 amarelo, acima vermelho.
- Connect rate = Σ views da página ÷ Σ cliques, só consultoria, iscas e C3 e só nas linhas com as duas
  métricas (Google não tem LPV e fica fora, com nota). Conversão da página = leads pagos ÷ views, mesma regra.
- CTR = cliques ÷ impressões; CPM = gasto ÷ impressões × 1000; vídeo 75% = p75 ÷ impressões com vídeo;
  custo por visualização = gasto ÷ ThruPlay. Alcance e frequência não somam entre dias: vêm do total do período.
- Grupo em 48h = pessoas que entraram no grupo em até 48h ÷ pessoas com a janela de 48h já fechada.
- Meta acumulada = 650 × dias desde o início da captação (12/10). Leads da meta = pessoas únicas.
- Falha de bloco: segura o último valor, esmaece e mostra a idade da leitura.

## Decisões

Do Victor (12/10): funil como filtro global; gaveta lateral na Jornada; aba Criativos aprovada; Perfil geral e
por etapa com mapa; mensageria com dado fictício e selo; sem tabela no Supabase agora; login normal no localhost (opção A).

Do executor (front-end-sr), sem pedido explícito:
- flag `blackDemo` no `env.ts` (regra do repo), mas o teste de `NODE_ENV` fica inline em `infrastructure/fonte.ts`
  para o build de produção descartar o fixture;
- a live absorve o carrinho no nó da Jornada; nós semanais sem fonte mostram "Sem dado";
- com fonte real e config ausente, a tela mostra um aviso vazio em vez de números;
- gaveta lateral própria (`ui/GavetaLateral.tsx`), porque o Drawer canônico é modal e escurece o fundo;
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
9. Custo de disparo e LPV do Google: sem fonte.

Acréscimos da revisão: o grupo legado conta nos 15 mil? Título e descrição do cartão no registro. O parser
`traduzirCampanha` (Marketing › Tráfego) rejeita o gestor `ZZ` dos nomes fictícios: não é usado aqui, mas
qualquer tela que passe esses nomes por ele vai recusá-los.

## Contrato da fonte (`application/ports.ts`)

`FonteDadosBlack` com `modo` (`'demonstracao' | 'real'`), `agora()` e métodos que devolvem
`Resultado<T> = { data, semDado, erro }`: `config(chave)`, `trafego(chave, periodo)` (catálogo, dias e totais
do período), `perfil(chave, periodo)` (uma linha por cadastro, sem dado pessoal), `leads(chave, ids)` (nome,
e-mail e telefone, só quando a tabela abre), `mensageria(chave, periodo)` e `marcos(chave)` (presença e vendas).

## Riscos

- Mergear publica o cartão para todos os admins com tudo "Sem dado".
- Com dado real, a tabela de leads fica protegida só por "vê Infra": precisa de RPC com guarda própria e revisão do pentester antes da `main`.
- Filtro cruzado no cliente não escala para 150 mil leads.
- DDD 42: a tabela `dados.ddd_uf` diz PR (espelhada aqui); a BrasilAPI diz SC.
- Base da casa no config = 188.013; o desenho fala em "cerca de 189 mil".
