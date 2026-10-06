# Central de dados: departamentos e áreas

> Decisão do Victor Hugo (05/10/2026), com o João Pedro ciente. O sistema deixa de ser só a Central de Alunos e
> vira a central da empresa: ao entrar, a pessoa vê os **departamentos**; dentro deles, as **áreas**.
> Mapeamento e proposta de origem: `Projetos/sistema-unico/central-de-dados/modularizacao-educacional.md` no
> cérebro do Victor.

## Estrutura

| Departamento | Rota | Situação | Dentro |
|---|---|---|---|
| Educacional | `/educacional` | ativo | tudo o que existia no sistema até 05/10/2026 (sem áreas) |
| Marketing | `/marketing` | ativo, **só admin e dev** | áreas **Web** e **Tráfego** ativas (ver "Web" e "Tráfego"); Mensageria, Audiovisual, Social Media "Em breve" |
| Comercial | `/comercial` | ativo, **só admin e dev** | sem áreas: CRM e base única de pessoas (ver "Comercial e base de pessoas") |
| Financeiro | `/financeiro` | Em breve | a mapear |
| Infra | `/infra` | Em breve | IA e Dados |

- **Fonte única:** `web/shared/domain/departamentos.ts` (departamentos, áreas, status, quem vê, e a que
  departamento pertence cada pasta de `web/modules`). Home, sidebar e o gate do Marketing leem dali.
- **Home `/`:** cartões dos departamentos. Marketing aparece com "Acesso restrito" para quem não pode entrar.
- **Início do Educacional `/educacional`:** os atalhos que eram a home antes.
- **Sidebar:** grupo "Departamentos" (seletor); o menu do Educacional (mesmos filtros de antes) aparece dentro do
  Educacional e nas telas globais; as áreas do Marketing aparecem dentro do Marketing; "Sistema" fica fixo.
- **Global (fora dos departamentos):** `/usuarios`, `/sistema/configuracoes`, `/sistema/admin-dev`. Valem para a
  Central toda (usuário e permissão serão de todos os departamentos).
- **Não mudaram:** `/login`, `/definir-senha`, `/auth/confirm`, `/solicitar-placa`, `/agendar-entrevista`,
  `/modelos`, todo `/api/*` (o pg_cron chama URL fixa).

### Dois "Financeiro" (de propósito, por enquanto)

- **Módulo Financeiro** (Contas a Receber, Board, Funis, Escritório, Ofertas): mora **dentro do Educacional**, em
  `/educacional/financeiro`, e **mantém o nome** (decisão de 05/10/2026). Código em `web/modules/financeiro`.
- **Departamento Financeiro:** `/financeiro`, cartão "Em breve". Não tem relação com o módulo acima.

## Rotas do Educacional e redirects

Tabela em `web/shared/ui/nav/redirects.ts`, aplicada por `redirects()` do `web/next.config.ts`: **308
(permanente)**, roda antes do proxy, **preserva a query** (`?caso=`) e o navegador mantém o `#hash`.

| Antiga | Nova |
|---|---|
| `/sistema/alunos` | `/educacional/alunos` |
| `/sistema/pedidos-alteracao` | `/educacional/pedidos-alteracao` |
| `/relatorios/placas` | `/educacional/placas` |
| `/relatorios/financeiro` | `/educacional/financeiro` |
| `/relatorios/remocoes` | `/educacional/remocoes` |
| `/depoimentos` | `/educacional/depoimentos` |
| `/depoimentos/biblioteca` | `/educacional/depoimentos/biblioteca` |

**Nunca apagar uma entrada.** As mensagens de Slack da Remoção de Acessos já enviadas (e as que continuam sendo
enviadas) apontam para `/relatorios/remocoes?caso=<id>`: o link é montado no banco a partir de
`ra_config.app_url` nas funções das migrations `infra/supabase/migrations/20260916_remocao_acessos*.sql`. Trocar
o caminho dentro dessas funções pede migration nova; não foi feito, o redirect cobre.

Testes: `web/shared/ui/nav/redirects.test.ts` (cada antiga vai para a nova, query e hash preservados, destino
existe como página, menu só aponta para rotas novas).

## Acesso

- **Educacional:** qualquer pessoa da equipe entra; cada tela mantém o gate que já tinha (nenhuma regra mudou).
- **Marketing:** só `admin` e `dev`, até os níveis de acesso por departamento serem desenhados (com LGPD).
  Bloqueado para o **visualizador geral**, gestor e operador. Checagem no servidor em
  `web/app/(admin)/marketing/layout.tsx` (redireciona para `/`) e na interface (sidebar esconde, home bloqueia).
  No banco, a base compartilhada (20261005m) usa a mesma regra em `mkt.pode_ver` (ver "Base compartilhada"). Teste: `web/shared/domain/departamentos.test.ts`.
- **Comercial:** a mesma regra do Marketing (só `admin` e `dev`), em `web/app/(admin)/comercial/layout.tsx`, na page,
  na sidebar e na home. No banco, `pessoas.pode_ver()` em cada função (ver "Comercial e base de pessoas").
- ⚠️ `podeVer()` libera o visualizador em qualquer setor. Setor novo de Marketing precisa de regra própria que o
  negue (como Financeiro e Remoção fazem), no front **e** na RLS.

## Como adicionar uma área (ex.: Mensageria)

1. **Registro:** a área já existe em `DEPARTAMENTOS` (`web/shared/domain/departamentos.ts`). Quando ficar pronta,
   trocar o `status` dela para `'ativo'` (some o selo "Em breve"). Área nova: acrescentar uma linha `area(...)`.
2. **Código:** `web/modules/marketing/<area>/` com as camadas de sempre (`domain`, `application`,
   `infrastructure`, `ui`; ver `web/ARCHITECTURE.md`). Apagar o `.gitkeep`.
3. **Tela:** substituir o `EmBreve` em `web/app/(admin)/marketing/<area>/page.tsx` pela tela da área. A page
   também chama a regra de acesso (o layout e a page renderizam em paralelo no Next).
4. **Banco:** schema próprio (ex.: `mkt_mensageria`), RLS desde a criação, setor no padrão `mkt_<area>` (sem
   ponto no nome do setor: a regex de funções é `^[a-z_]+\.[a-z_]+$`).
5. Departamento novo: entrada em `DEPARTAMENTOS`, pasta em `web/app/(admin)/<departamento>/`, e o teste de
   registro atualizado.

## Base compartilhada (Marketing)

Fase 1 da central de dados (decisões de 05/10/2026, `area-web-radar.md` no cérebro). É o cadastro que Web, Tráfego
e Mensageria leem; não é área. **Migration `infra/supabase/migrations/20261005m_mkt_base_compartilhada.sql`, NÃO
APLICADA** (ensaio `20261005m_ensaio.sql`, explicação `20261005m.explain.md`).

| Peça | Onde | O que é |
|---|---|---|
| Projetos | `mkt.projetos` | Tabela de projetos ÚNICA. **Projeto = edição**; chave = sigla do nome de campanha (`PB26`, `HT33`, `SEMSET26`, `BF26`). Nome, tipo/linha, edição, ano, etiqueta do ClickUp (texto exato), subárea do Tráfego (interno/aurum/diamante), início/fim, ativo |
| Páginas | `mkt.paginas` | Páginas de cada projeto: código da casa (`ak1`, `bl2`, `ak1-b`; opcional), domínio + caminho, função (captura, obrigado, quase_la, pesquisa, venda, outra), funil (texto curto), ativa |
| Listas do nome de campanha | `mkt.campanha_gestores`, `mkt.campanha_objetivos` | Gestores `CF`, `RS`, `EF`; objetivos `LEADS`, `VENDAS`, `REMARKETING`, `LEMBRETE`, `DISTRIBUIÇÃO` |
| Tradução do nome de campanha | `mkt.campanha_traduzir(text)` e `web/modules/marketing/projetos/domain/campanha.ts` | `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA` → campos + erros ("fora do padrão") + avisos. A mesma regra nos dois lados |
| Web | schema `mkt_web` | Coleta do Radar (migration 20261005n, ver a seção "Web"), tudo apontando para `mkt.projetos`/`mkt.paginas`, sem dado pessoal |
| Tela | `/marketing/projetos` | Listar, cadastrar e editar projetos e páginas; testar um nome de campanha |

- **Acesso:** tabelas e schemas fechados (sem USAGE para anon/authenticated). Tudo pelas funções `public.mkt_*`
  (SECURITY DEFINER, `search_path ''`): `mkt_projetos_listar`, `mkt_paginas_listar`, `mkt_projeto_salvar`,
  `mkt_pagina_salvar`, `mkt_campanha_listas`, `mkt_campanha_traduzir`. A trava é `mkt.pode_ver(area)`: hoje só
  `gp_is_admin()` (admin/dev). **A área `mkt_web` (Luiz, Iromar) entra nessa função**, negando o visualizador geral;
  não liberada ainda.
- **Seed:** só o que está nas fontes. PB26 (`seminario-conjunto-2026-11`), HT33 (sem etiqueta conhecida),
  SEMSET26 (`sem-set-2026`), BF26 (`black-friday-2026-10`); datas nulas. Páginas do PB: `/ak1/`, `/obrigado/`,
  `/quase-la/`, `/pesquisa/` em `patrimoniobrasil.com.br`, caminhos e funis do `patrimonio-brasil.json` do Radar.
- **Ligações previstas:** campo 2 do nome de campanha = `mkt.projetos.sigla`; campo 5 = `mkt.paginas.codigo`
  (em minúsculas no banco); etiqueta do ClickUp = `mkt.projetos.etiqueta_clickup`.

## Web (Marketing > Web: o Radar dentro da central)

> **Quem chega para mexer na Web (Luiz) começa por [`web-guia-luiz.md`](web-guia-luiz.md)**: situação, decisões, o que falta e perguntas abertas.

Fase 2 da central de dados (decisões de 05/10/2026, `area-web-radar.md` no cérebro): o Radar do Luiz Fernando (pacote
`SistemaWEB/sistemas/radar/` de 05/10/2026) passou a ser do Grupo e mora aqui, no nosso Supabase. **Migration
`infra/supabase/migrations/20261005n_mkt_web_coleta.sql`, NÃO APLICADA** (ensaio `20261005n_ensaio.sql`, explicação
`20261005n.explain.md`). Depende da 20261005m (aplicada).

### Como o dado chega

```
página do PB (gravador /web/radar-v1.js no <head>)
  → POST text/plain a cada 3 s → https://grupoparticipa.app.br/api/web/coletar   (rota pública do Next, fora do Proxy)
  → public.mkt_web_coletar(corpo, origem, ip_hash) com a chave de SERVIÇO       (anon/authenticated não executam)
  → mkt_web.sessoes, visualizacoes, eventos, cliques, erros, paginas_mapa
  → pg_cron: resumo_dia (03:20 SP), retenção (03:17 SP), ritmo e espaço (10 min)
```

| Peça | Onde | O que faz |
|---|---|---|
| Gravador | `web/public/web/radar-v1.js` | Adaptado do `radar-051026-0007.js` do Luiz, **sem vídeo** (sem rrweb). Mede página vista, rolagem, tempo, cliques (raiva, morto), erros, dataLayer (só leitura; só nome do evento e as chaves `pagina, motivo, origem, area, versao`), velocidade (LCP, INP, CLS, FCP, TTFB), leitura por seção (`<section>`/`data-secao`), botões (`data-cta`), formulário campo a campo **sem o valor digitado**, origem (UTMs, `fbclid`/`gclid` só sim/não, domínio de onde veio). Sistema, navegador, app e o lugar da VisitorAPI (cidade/estado). Mesmos biscoitos do Radar (`radar_v`, `radar_s`): a visita continua na virada |
| Linha de instalação | Marketing > Web > Instalação | `<script src="https://grupoparticipa.app.br/web/radar-v1.js" data-projeto="PB26" async></script>` (`data-projeto` = sigla de `mkt.projetos`). Versão nova do gravador = arquivo novo (`radar-v2.js`), por causa do cache |
| Rota | `web/app/api/web/coletar/route.ts` + `web/modules/marketing/web/application/receber-pacote.ts` | Só POST; origem tem que ser domínio de página **ativa** de projeto com a **coleta ligada** (lista em cache de 60 s via `mkt_web_dominios`); corpo lido com teto de **64 KB**; robô recebe `pausado`; **limite em memória de 600 pacotes/min por IP**. Fora do Proxy de sessão (matcher em `web/proxy.ts`): sem login, sem `getUser()` por pacote. CORS só para a origem aceita |
| Banco | `public.mkt_web_coletar` | Confere tudo de novo (projeto pela sigla, `mkt_web.funis.coleta`, domínio, ids, tamanho, JSON), **limite por IP (hash) e por sessão por minuto** (`mkt_web.config`: 600 e 60), pacote repetido, erro de fora e clique automático (regras do Radar), e grava. Erro interno vira linha em `mkt_web.falhas` e a resposta `erro` |
| IP | rota | Nunca vai ao banco: só `sha-256(sal secreto + dia + IP)`, usado no limite e apagado em até 1 hora (`mkt_web.ritmo`) |
| Contrato do funil | `mkt_web.funis` | Por projeto: `coleta` (a chave), `eventos_lead`, `chaves_datalayer`, `resultados` (MQL…), `funis` (etapas por caminho ou evento). PB26 copiado do `patrimonio-brasil.json` do Luiz, **com a coleta DESLIGADA** |
| Proteção da Central | `mkt_web.config` | `coleta = pausada` desliga tudo na hora; `mkt_web.vigiar_espaco` pausa sozinho se o schema passar de `limite_mb` (2048) |
| Retenção | `mkt_web.manter` | Sessões e páginas vistas 395 dias; cliques, eventos e erros 90 dias; `resumo_dia` para sempre |

**Respostas do coletor** (o gravador entende): `ok`, `repetido`, `pausado` (para 30 min), `limite` (5 min), `dominio` /
`projeto` (60 min), `identificador`, `tamanho`, `json`, `erro` (3 seguidas = 10 min).

### Telas (`/marketing/web`, só admin e dev)

Código em `web/modules/marketing/web/` (`domain`, `application`, `infrastructure`, `ui`). Filtro por **projeto**
(`mkt.projetos`) e **período** (até 92 dias, dia de São Paulo). Uma aba por pergunta, cada uma lendo uma função
`public.mkt_web_*` (trava `mkt.pode_ver('mkt_web')`, hoje `gp_is_admin()`):

| Aba | Função | O que mostra |
|---|---|---|
| Visão geral | `mkt_web_visao` | Visitas, navegadores, engajamento e rejeição, leads e taxa, tempo, % de anúncio, raiva, erro, resultados (MQL), visitas e leads por dia |
| Páginas | `mkt_web_paginas` | Por caminho: vistas, entradas, rejeição, lead por entrada, saída rápida, rolagem, tempo, LCP p75; comparação das duas melhores com o selo forte/provável/pode ser acaso |
| Funil | `mkt_web_funil` | As etapas do contrato, cada uma com as visitas que cumpriram ela e as anteriores, e a maior perda |
| Origem e UTMs | `mkt_web_origem` | Plataforma (`utm_source`), campanha traduzida pelo padrão de nome (campo 5 = página), anúncio (`utm_content`), fbclid/gclid, site de origem |
| Velocidade | `mkt_web_velocidade` | p75 de LCP, INP, CLS, FCP, TTFB por página e aparelho, na régua do Google, e LCP por dia |
| Rolagem e leitura | `mkt_web_leitura` | Até onde rolam, segundos por seção (apelido de gente), botões vistos e clicados |
| Cliques e erros | `mkt_web_problemas` | Raiva, mortos, mais clicados, erros da página e o ruído de fora (app do Facebook, extensões) |
| Formulário | `mkt_web_formulario` | Viram, começaram, enviaram, campo a campo (focos, tempo, preenchido, erro) e onde param |
| Instalação | `mkt_web_instalacao`, `mkt_web_coleta_ligar` | Linha do gravador, domínios aceitos, contrato, último pacote, ligar/desligar a coleta, recusas dos últimos 7 dias |
| Fluxo (fase 2) | `mkt_web_fluxo` | Caminho entre páginas na mesma visita: entradas e saídas por página, de onde para onde (com "saiu do site"), caminhos mais comuns (até 5 páginas). Recarregar a mesma página não é passo |
| Mapa de calor (fase 2) | `mkt_web_calor` | Cliques (ou raiva e mortos, ou rolagem) desenhados sobre a página, por aparelho; fundo = captura do teste do Google; mais clicados; elemento fixo contado à parte |
| Melhorias (fase 2) | `mkt_web_melhorias`, `mkt_web_comparar` | Achados automáticos (regras do Radar), testes A/B entre variações (`ak1` x `ak1-b`) e Comparar (duas páginas ou dois períodos) |
| Dentro das abas antigas (fase 2) | `mkt_web_leads`, `mkt_web_connect`, `mkt_web_lab` | Visão geral: leads na base de pessoas e MQL (ficha só admin/dev). Origem: connect rate com o Tráfego. Velocidade: teste do Google (laboratório) |

Sem visita no período, cada aba diz **"Sem dados ainda: a coleta começa na virada."** Regras de análise portadas do
Radar em `domain/analise.ts` (teste de duas proporções, maior perda do funil, apelido de seção, origem, régua do Google).

### Fase 2 (migration 20261005q, NÃO APLICADA)

`infra/supabase/migrations/20261005q_mkt_web_fase2.sql` + `_ensaio.sql` + `20261005q.explain.md`. Depende da 20261005n.
Tudo sobre o que o gravador `radar-v1.js` já grava (não mudou: sem `radar-v2.js`).

| Peça | Onde | Como funciona |
|---|---|---|
| Fluxo | `mkt_web_fluxo`, `domain/fluxo.ts`, `ui/paineis-fase2.tsx` | A visita vira a sequência de caminhos de `mkt_web.visualizacoes`. Não é o Fluxo do Radar (pessoas do CRM, pesquisa), que segue fora da Web |
| Achados automáticos | `domain/achados.ts` (regras), `mkt_web_melhorias` (somas) | Porte de `oportunidades.ts` do Luiz com os mesmos limiares: primeira dobra (celular x desktop, rejeição que subiu), promessa do criativo, botão que ninguém vê, seção onde a leitura morre, campo do formulário, fricção, velocidade; aprendizados "o que o MQL lê" e "qual botão converte". Cada regra cita a origem no código. Ganho = teto de leads por semana. A regra de publicações não veio (publicações fora de escopo) |
| Testes A/B | `domain/testes-ab.ts` | Grupo pelo código da casa: `ak1` (original) x `ak1-b`, `ak1-c`. Conta quem entrou por cada versão. Teste de duas proporções, amostra para enxergar 20% (fator 7,85), veredito só com a amostra e 7 dias, aviso de divisão desigual (porte de `testes.ts` do Luiz). O teste não é cadastrado: vale o período da tela |
| Comparar | `mkt_web_comparar`, `ui/Comparar.tsx` | Duas páginas no mesmo período, ou a mesma página (ou o projeto) em dois períodos; veredito pela taxa de lead sobre quem viu a página, lado a lado, por aparelho e por origem |
| Mapa de calor sobre a página | `mkt_web_calor`, `domain/calor.ts`, `ui/MapaCalor.tsx` | Ponto = x % da largura e y como fração da altura da página vista. Fundo padrão = captura de página inteira do último teste do Google do mesmo aparelho; opção "página ao vivo" (iframe sem JavaScript, com aviso: o `<noscript>` do pixel do Meta pode contar visita, e a página pode recusar o quadro); opção sem fundo. Pintura portada do `calor.ts` do Luiz |
| PageSpeed de laboratório | `mkt_web.velocidade_lab`, Edge `infra/supabase/functions/mkt-web-pagespeed`, cron `mkt-web-pagespeed` (06:40 SP, pelo `ops.cron_post`) | Páginas ativas de projeto com a coleta ligada, celular e computador, 1 vez por dia (máx. 12 por chamada; o resto no dia seguinte). Guarda notas, LCP, FCP, TBT, Speed Index, CLS, 5 oportunidades, a captura e a falha. Chave do Google **opcional** no Vault (`mkt_web_pagespeed_api_key`); sem ela, a cota pública. `mkt_web.config` `pagespeed = desligado` para |
| Lead ligado à pessoa | `mkt_web_leads` | Leads da Web cujo navegador tem `visitantes.lead_ref` (gravado pela 20261005o) e quantos viraram MQL no projeto. Referência e link `/comercial?pessoa=<id>` (abre a ficha) só para `pessoas.pode_ver()` (admin/dev). Sem a 20261005o: só os números da Web |
| Connect rate | `mkt_web_connect` | Definição do Victor: **page views ÷ cliques no link**; conversão da página = **leads ÷ page views**. Por campanha do Tráfego (`campaign_id` = id, ou `utm_campaign` = nome exato ou id). Cliques no link = coluna `cliques_link`/`cliques_no_link` de `mkt_trafego.desempenho_dia`; sem ela, connect rate em branco (nunca o total de cliques). Por anúncio, só a Web (o Tráfego não guarda clique por anúncio). Sem a 20261005p: só as page views por anúncio |
| Páginas do PB26 | a própria migration | As que faltam das 11 do `patrimonio-brasil.json` (`obs = '20261005q: …'`); o passo 3 da virada fica feito ao aplicar |

**Aplicar:** 20261005n → ensaio da 20261005q (nenhum `ERRADO`) → publicar a Edge (`supabase functions deploy
mkt-web-pagespeed`) → 20261005q. A chave do Google, se o Victor quiser (sem ela vale a cota pública):
`select vault.create_secret('<chave>', 'mkt_web_pagespeed_api_key');` no SQL editor, nunca no código.

**Ferramentas da Web para o MCP da central** (não existe MCP da central no repo; não foi criado servidor). Só leitura,
por projeto e página, sem dado pessoal e sem vídeo, cada uma chamando a função que a tela já usa: `web_resumo`
(`mkt_web_visao`), `web_paginas` (`mkt_web_paginas`), `web_funil` (`mkt_web_funil`), `web_fluxo` (`mkt_web_fluxo`),
`web_origem` (`mkt_web_origem` + `mkt_web_connect`), `web_velocidade` (`mkt_web_velocidade` + `mkt_web_lab`),
`web_leitura` (`mkt_web_leitura`), `web_calor_contagem` (`mkt_web_calor` sem a imagem), `web_problemas`,
`web_formulario`, `web_achados` (`mkt_web_melhorias` + as regras de `domain/achados.ts`), `web_testes_ab`,
`web_comparar`, `web_instalacao`. Porta: chave só com hash, limite por minuto e por dia e registro de uso (o desenho da
porta do Luiz, estudo seção 5.5).

### Testar localmente (antes da virada)

- **Telas com números (sem banco):** em `web/.env.local` pôr `NEXT_PUBLIC_WEB_DEMO=1`, rodar `npm run dev` em `web/`,
  abrir `http://localhost:3000/marketing/web` e entrar com o login de sempre (admin/dev). Aparece a faixa **"Dados de
  demonstração"**: os números são inventados (`web/modules/marketing/web/infrastructure/demo.ts`). Só liga em `next dev`:
  com `NODE_ENV=production` (o servidor) nunca liga, mesmo com a variável. Tirar a linha do `.env.local` volta ao banco.
- **Banco local com as migrations:** `infra/scripts/mkt_web_seed_dev.sql` põe 4.200 visitas inventadas do PB26 (ids
  `dev…`). Trava: só roda depois de `select set_config('app.mkt_web_seed', 'sou-banco-de-dev', false);` e aborta se já
  houver coleta de verdade. **Nunca rodar em produção.** O bloco LIMPAR no fim apaga só o que é `dev`.
- Testes: `npx vitest run modules/marketing/web` (regras, rota, telas renderizando, estado vazio; na fase 2, achados,
  testes A/B, mapa de calor, fluxo, o resumo do Google da Edge e as telas novas) e
  `shared/infrastructure/supabase/proxy-dominio.test.ts` (a coleta fica fora do Proxy).
- **Fase 2 no modo de demonstração:** as abas Fluxo, Mapa de calor e Melhorias (Ver: Achados, Testes A/B, Comparar) e as
  seções novas da Visão geral, Origem e Velocidade aparecem com números inventados (a página "AK1 B (demonstração)" só
  existe no modo de demonstração, para mostrar um teste A/B). O mapa de calor de demonstração não tem captura (fundo
  "Sem fundo").
- **Ensaio da 20261005q:** com a 20261005n aplicada, rodar `20261005q_ensaio.sql` inteiro (termina em rollback) e
  conferir que nenhuma linha começa com `ERRADO`.

### Virada (trocar o gravador do PB para o nosso). NÃO feita; fazer fora da semana do evento (09 a 11/11)

O FTP das páginas do PB é do Luiz (publicação pelo `scripts/deploy.py` dele). Passo a passo, com data combinada com ele:

1. **Aplicar a 20261005n** em produção: rodar antes o `20261005n_ensaio.sql` e conferir os esperados; depois a
   migration. Conferir `select jobname, schedule from cron.job where jobname like 'mkt-web-%'` (3 rotinas).
2. **Publicar** a branch (merge na `main`). Conferir `https://grupoparticipa.app.br/web/radar-v1.js` (200, JavaScript)
   e que `POST /api/web/coletar` sem origem responde `dominio` (403).
3. **Cadastrar as páginas** do PB26 que faltam: **a 20261005q faz isso** (as 11 do `patrimonio-brasil.json` do Luiz:
   `/`, `/ak1/`, `/bl2/`, `/bl2-otimizacao/`, `/quase-la/`, `/pesquisa/`, `/obrigado/`, `/inscricao-recebida/`,
   `/profissionais/`, `/profissionais/advogados/`, `/profissionais/contadores/`, só as que faltam). Sem a 20261005q,
   cadastrar em Marketing > Projetos e páginas. Caminho não cadastrado é gravado mesmo assim (sem página), mas o domínio
   precisa de ao menos uma página ativa.
4. **Ligar a coleta do PB26:** Marketing > Web > Instalação > Ligar (ou `mkt_web_coleta_ligar`). Sem isso o coletor
   responde `projeto` e o gravador para por 60 min.
5. **Rodar em paralelo um dia** numa página só (sugestão: `/obrigado/`): o Luiz acrescenta a nossa linha **sem tirar** a
   dele. Os dois gravadores usam os mesmos biscoitos e não se atrapalham. Comparar visitas do dia nas duas telas.
6. **Trocar nas páginas:** o Luiz republica as páginas com a linha
   `<script src="https://grupoparticipa.app.br/web/radar-v1.js" data-projeto="PB26" async></script>` no lugar da linha
   `luisweb.com.br/radar/gravador/radar-….js` (as mesmas marcas `data-cta`, `data-secao` e o dataLayer continuam valendo).
   Se as páginas tiverem Content-Security-Policy, liberar `grupoparticipa.app.br` em `script-src` e `connect-src`
   (não sei se têm: conferir).
7. **Conferir na hora:** Instalação mostra "Último pacote" de agora e nenhuma recusa nova; Visão geral com visitas;
   `select * from mkt_web.falhas order by id desc limit 20` vazio.
8. **Desfazer, se precisar:** o Luiz volta a linha antiga (`deploy.py --voltar`) e/ou Instalação > Desligar; para
   parar tudo de uma vez, `update mkt_web.config set valor = 'pausada' where chave = 'coleta'`.
9. **Depois:** importar o histórico do banco do Luiz (estudo, seção 5.6) e desligar o Supabase/domínio pessoais dele.

### O que ficou para depois

Gravação/replay das visitas (vídeo), Diário com IA, publicações/deploys (e a regra de achados "antes e depois da
publicação"), CRM do Luiz, Pesquisas, reenvio ao ActiveCampaign, o **servidor** MCP da central (as ferramentas da Web
estão descritas acima), a área `mkt_web` para o Luiz e o Iromar (entra em `mkt.pode_ver`), importação do histórico do
Radar, teste A/B cadastrado (com início, fim, hipótese e trava, como o Radar), clique no link por anúncio (depende do
Tráfego). Saíram desta lista com a fase 2 (20261005q, não aplicada): mapa de calor sobre a página, Melhorias (achados,
testes A/B, comparar), PageSpeed de laboratório, referência ao lead, Fluxo (caminho entre páginas) e connect rate.

## Comercial e base de pessoas

> Migration `20261005o_pessoas_crm_comercial.sql`, **NÃO APLICADA** (05/10/2026, branch `victor`). Ensaio
> `20261005o_ensaio.sql`; o que foi medido em `20261005o.explain.md`. Telas em `/comercial`, código em
> `web/modules/comercial/`.

Regras do Victor que mandam aqui (05/10/2026): **o mesmo dado não se duplica; se o aluno já existe, tudo se liga a
ele**; Comercial não tem áreas; CRM com **ativação, vendas, recuperação de carrinho e recuperação de venda**;
ativação = contato **sem intenção de vender** (ensinar a entrar na área de membros ou no evento); o lead do Marketing
mora numa base única de pessoas e a Web guarda **só uma referência opaca**; o CRM do Luiz **não migra agora** (LGPD).

### Modelo

| Schema | Tabela | O que guarda | Dado próprio ou referência |
|---|---|---|---|
| `pessoas` | `pessoas` | uma linha por pessoa; `ref` opaca; `situacao` (ativa, revisar, mesclada) | **referência** a `thb_alunos.id` e `compradores.id` (únicas); `nome` só de quem não é aluno nem comprador |
| | `identificadores` | documento, telefone, e-mail, nome+CEP **normalizados** | **próprio**: só o que a pessoa informou e que o aluno/comprador ligado **não** tem |
| | `origens` | projeto (`mkt.projetos`), página (`mkt.paginas`), campanha no padrão `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA` (traduzida por `mkt.campanha_traduzir`), UTMs, "de anúncio" | próprio (não existe em outro lugar) |
| | `eventos` | entrou como lead, virou MQL, não MQL, cadastro, ativada, CRM, ligada a aluno, juntada, revisão | próprio; `ref_tipo`/`ref_id` apontam (negócio, compra, aluno), nunca copiam |
| | `revisao` | dúvida de identidade para uma pessoa decidir | próprio (só o tipo do identificador, nunca o valor) |
| | `acessos` | quem buscou, abriu ficha, cadastrou, revisou, mexeu no CRM | próprio (a busca guarda o tamanho do termo, não o termo) |
| | `config` | `areas_leitura`, `areas_edicao`, `areas_contato` (vazias) | gancho dos níveis de acesso |
| `crm` | `pipelines`, `etapas`, `motivos_perda` | 4 pipelines; etapas **proposta** e configuráveis; motivos vazios | próprio |
| | `negocios`, `historico` | o card: pessoa, projeto, etapa, responsável, próximo passo, motivo de perda; histórico de cada mudança | próprio; `externo_tipo`/`externo_id` = gancho para o card do `cs.contatos_hm` |

**Lido na hora, nunca copiado:** nome, e-mail, telefone, documento e turma do aluno (`thb_alunos`); nome, e-mail,
telefone e documento do comprador (`compradores`); compras (`public.compras`: a Hotmart manda no dinheiro, esta base
não grava valor). Hierarquia do `disparos-thb`: Hotmart manda no dinheiro, `thb_alunos` na matrícula, `cs.contatos_hm`
na operação; quando as fontes discordam, marcar para conferência humana (aqui: a revisão de identidade).

### Identidade (cascata da casa)

Documento (CPF/CNPJ com dígito verificador; zeros à esquerda devolvidos) → telefone (**DDD + 8 últimos**) → e-mail →
**nome + CEP** (nome de 2 palavras ou mais). Procura na base de pessoas, em `thb_alunos` e em `compradores` (nome + CEP
só no aluno). Regras:

- Documento ou telefone que batem com **nome diferente** (primeiro nome) **não fundem**: a pessoa nasce em revisão.
- **Só o nome bate** → pessoa nova em revisão. **Mais de uma pessoa possível** → revisão.
- Liga sozinho só sem dúvida: o lead sem aluno que bate com um aluno (o lead que virou aluno) ganha o vínculo.
- Juntar (mesclar) é sempre decisão humana em **Revisão de identidade**; leva identificadores, origens, eventos e
  negócios; não junta dois alunos nem dois compradores diferentes (isso se confere na Central de Alunos).
- A mesma regra existe em `web/modules/comercial/domain/identidade.ts` (testes e modo de demonstração); o banco é quem
  decide.

### Referência opaca para a Web

`pessoas.pessoas.ref` (`pe_` + 32 hex aleatórios, não deriva de e-mail nem telefone). O servidor do formulário chama
`public.pessoas_registrar_lead` (só `service_role`) com nome, e-mail, telefone, projeto, campanha, UTMs e o
`visitante` do gravador; a função devolve só `ref`, `como` e `revisao` e, se a 20261005n estiver aplicada, grava a `ref`
em `mkt_web.visitantes.lead_ref`. A Web nunca recebe e-mail ou telefone. Ligar o `api/crm.php` do PB a essa função é
passo da virada da Web, **não feito**.

### Acesso e LGPD

- Tabelas fechadas (RLS ligada, sem policy, sem USAGE). Só `public.pessoas_*` e `public.crm_*`, com a permissão no corpo.
- Hoje **só admin e dev** (`gp_is_admin`). Gancho: pôr uma área em `pessoas.config` (`areas_leitura`,
  `areas_edicao`, `areas_contato`) libera gestor/operador ativo dessa área sem mexer em função.
- Documento sem máscara só com `gp_pode_ver_cpf()` (padrão `podeVerCpf`). E-mail e telefone completos só admin/dev ou
  `areas_contato`. A máscara é feita **no SQL** (a da tela seria cosmética, como mostrou a 20260819g).
- Lista do quadro **sem** e-mail e telefone (minimização); contato só na ficha.
- Toda busca, ficha aberta, cadastro, revisão e mudança no CRM vai para `pessoas.acessos`.

### Telas (`/comercial`, só admin e dev)

- **CRM:** um pipeline por vez; **quadro** (kanban por etapa) ou **lista**; filtros por projeto, responsável (ou "sem
  responsável") e situação (em andamento, ganhos, perdidos). O negócio abre com mover etapa (perda pede motivo;
  fechado só reabre), próximo passo, data, responsável, projeto e histórico. "Novo negócio" a partir de uma pessoa.
- **Pessoas:** busca por nome, e-mail, telefone ou documento, ou todos de um projeto; cadastro (o banco decide se já
  existe); aluno que ainda não está na base aparece com "Trazer para a base" (cria só a referência).
- **Revisão de identidade:** cada dúvida com o cadastro novo e os candidatos; "É a mesma" ou "São pessoas diferentes".
- **Ficha:** dados (mascarados pelo banco conforme a permissão), origem, histórico (eventos + compras da Hotmart),
  compras, negócios, dúvida de identidade.

### Testar localmente

1. **Ensaio do banco:** rodar `infra/supabase/migrations/20261005o_ensaio.sql` inteiro (termina em rollback) e conferir
   que nenhuma linha começa com `ERRADO` (o cabeçalho explica cada passo). Usa só dados fictícios.
2. **Telas sem banco:** em `web/.env.local`, `NEXT_PUBLIC_COMERCIAL_DEMO=1`; `npm run dev`; entrar como admin/dev e abrir
   `/comercial`. Pessoas e negócios inventados, em memória, com a faixa "Dados de demonstração" (nada é gravado;
   recarregar volta ao começo). Em produção (`NODE_ENV=production`) o modo nunca liga.
3. **Código:** `npx tsc --noEmit`, `npx vitest run` (cascata, normalização, transições, demonstração), `npm run build`.

### Para valer

Victor ver as telas no modo de demonstração e responder as perguntas abaixo; rodar o ensaio no SQL editor; aplicar a
20261005o; levar a `victor` para a `main`. Nada disso foi feito.

### Perguntas abertas (para o Victor)

**LGPD e acesso**
1. Quem do Comercial vai ver a base de pessoas, e quem vê **e-mail e telefone completos**? (Hoje só admin e dev; o
   gancho é `pessoas.config`.) Quem pode **juntar** pessoas na revisão?
2. **Retenção:** lead que nunca comprou fica para sempre? Por quanto tempo guardar `pessoas.acessos`? (Não há
   retenção nesta migration.)
3. Base legal e aviso de privacidade nas páginas de captura cobrem guardar o lead nesta base (e cruzar com aluno)?
4. Pedido de exclusão (titular pede para apagar): apagar a pessoa e os eventos, ou anonimizar? (Não há rotina ainda.)

**Convivência com o `disparos-thb`**
5. O HM continua inteiro no `disparos-thb` (`cs.contatos_hm`, esteiras Comercial e Ativação)? Proposta: **sim**; o CRM
   daqui serve aos outros produtos e, quando o Victor decidir, **mostra o card do HM só para leitura** (pelo gancho
   `externo_tipo = 'cs.contatos_hm'`), sem copiar etapa nem dinheiro. Alternativas: espelhar as etapas do HM aqui, ou
   migrar o HM para cá (mexe no sistema do João e no `disparos_app`).
6. A ativação daqui (contato sem intenção de vender, ex.: ingresso do HT) é a mesma coisa que a esteira **Ativação** do
   HM (onboarding de quem quitou), ou são processos diferentes com o mesmo nome?

**Regras de etapa e do CRM**
7. As **etapas** de cada pipeline (hoje proposta genérica: A contatar, Em contato, Ativado/Não ativado; Novo, Em contato,
   Negociação, Ganho, Perdido; A contatar, Em contato, Recuperado/Não recuperado). Quais são as de verdade?
8. **Motivos de perda** de cada pipeline (a lista nasce vazia; hoje vale texto livre).
9. **"Recuperação de venda"** é o quê exatamente (boleto/Pix não pago, cancelamento, reembolso, chargeback)? E
   "recuperação de carrinho" vem de qual evento da Hotmart?
10. **Ganho** em vendas/recuperação deve **exigir compra** na Hotmart (como o "lastro" do HM), ou o comercial marca na
    mão? Hoje: marca na mão; a compra aparece na ficha pela referência.
11. Quem pode ser **responsável** (hoje: admin/dev ativos, e as áreas de `areas_edicao` quando liberadas)?
12. Os negócios devem nascer **sozinhos** (lead novo → vendas; carrinho abandonado → recuperação; compra do ingresso →
    ativação)? Nesta fase nascem só à mão.
13. **Nome compatível = mesmo primeiro nome.** Serve, ou quer uma regra mais rígida (nome completo) para documento e
    telefone?

## Tráfego (Marketing > Tráfego: a Central do Tráfego)

> **Etapa 1 de 6** do plano (`Projetos/sistema-unico/central-de-dados/plano-trafego.md` no cérebro do Victor), 05/10/2026,
> branch `victor`. Migration `infra/supabase/migrations/20261005p_mkt_trafego.sql`, **NÃO APLICADA** (ensaio
> `20261005p_ensaio.sql`; o que foi medido em `20261005p.explain.md`). Tela `/marketing/trafego`, código em
> `web/modules/marketing/trafego/`.

### Situação

| Peça | Situação |
|---|---|
| Banco (schema `mkt_trafego`, 13 funções `public.trafego_*`) | escrito e ensaiado em Postgres local; **não aplicado** |
| Tela `/marketing/trafego` (Projetos, Campanhas fora do padrão, Contas de anúncio, vida do projeto) | pronta; funciona de verdade só depois da migration; hoje dá para ver no modo demo |
| Coleta Meta Ads e Google Ads | **não feita** (etapa 2). As funções de entrada existem (`trafego_campanhas_receber`, `trafego_desempenho_receber`, só `service_role`), ninguém as chama |
| Receita (Hotmart) | **sem fonte**: a tela mostra "sem dado" |
| Connect rate e conversão da página | **ligados** no banco (page views da Web, `mkt_web.resumo_dia`, 20261005n; leads da base, 20261005o). Enquanto essas migrations não estiverem aplicadas e com dado, "sem dado" |
| Atividades do ClickUp | lugar reservado na vida do projeto, sem integração |

### Decisões que mandam aqui (Victor, 05/10/2026)

- **KPIs da tabela:** CPL, leads, CTR, CPM, connect rate, conversão da página, % MQL. Mais status, projeto, receita gerada,
  investimento realizado, investimento máximo, % da verba e gestores.
- **Cliques no link** (Victor): CTR = cliques no link ÷ impressões; CPC = investido ÷ cliques no link. O gasto diário
  guarda cliques no link e cliques totais **separados**; os totais são só informação.
- **Connect rate = page views ÷ cliques no link; conversão da página = leads ÷ page views** (Victor). Page views = as das
  páginas de **captura** do projeto (`mkt.paginas.funcao = 'captura'`), da Web; leads = os da base de pessoas. Limite: o
  resumo diário da Web não separa a visita que veio de anúncio, então as page views incluem tráfego orgânico.
- **Vários gestores por projeto** (Victor): tabela `projeto_gestores` (siglas da lista `mkt.campanha_gestores`).
- **Fases:** aquecimento, captação, lembrete, remarketing, abertura de carrinho. A fase da campanha sai do **objetivo** do
  nome (mapa `objetivo_fase`, configurável por SQL); a **correção à mão** na campanha prevalece; sem regra e sem correção =
  "sem fase". Mapa (Victor): LEADS e VENDAS → captação (VENDAS = lançamento pago, a campanha vende o ingresso em vez de
  captar lead), AQUECIMENTO → aquecimento, LEMBRETE → lembrete, REMARKETING → remarketing, CARRINHO → abertura de
  carrinho. **DISTRIBUIÇÃO** (distribuição de conteúdo) **não tem fase automática**: pode ou não ser aquecimento, fica
  "sem fase" até alguém marcar na campanha.
- **Objetivos do nome de campanha** passam a ser 7: LEADS, VENDAS, REMARKETING, LEMBRETE, DISTRIBUIÇÃO, **CARRINHO**
  (anuncia o produto principal na abertura de carrinho, em lançamento pago ou gratuito) e **AQUECIMENTO**. Os dois novos
  entram em `mkt.campanha_objetivos` (lista da 20261005m) pela 20261005p, com insert idempotente; o tradutor
  `mkt.campanha_traduzir` reconhece porque lê a lista. Na tela "Testar nome de campanha" (Marketing > Projetos e páginas)
  passam a valer depois de aplicar a 20261005p.
- **Status do projeto marcado à mão.** Verba, fases e metas preenchidas por Arthur, Victor e Caio (no banco: admin/dev).
- **Lead que conta é o da nossa base** (`pessoas.eventos`, 20261005o): pessoas distintas com evento `lead` no projeto, sem
  pessoa de teste nem mesclada. Os leads que a plataforma informa ficam só na campanha.
- **"Quanto gerado" = receita** (Hotmart), ainda não ligada: nula.
- **Atividades do ClickUp ficam na tela** (pela etiqueta do projeto); nesta etapa só o lugar.
- **Nada duplicado:** projeto e página em `mkt`, lead em `pessoas`, visita em `mkt_web`.

### Modelo

| Tabela | O que guarda |
|---|---|
| `plataformas`, `status_projeto`, `fases` | listas (Meta Ads, Google Ads; ativo, pausado, inativo, encerrado; aquecimento, captação, lembrete, remarketing, abertura de carrinho). Mudam por SQL |
| `objetivo_fase` | objetivo do nome → fase (ver Decisões). Muda por SQL |
| `contas` | conta de anúncio: plataforma, id na plataforma (Meta sem `act_`, Google só dígitos), nome, de quem é (grupo, diamante, aurum), cliente, moeda |
| `campanhas` | nome **exato** da plataforma + leitura pelo padrão `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA` (`mkt.campanha_traduzir`): projeto, gestor, objetivo, página, fora do padrão. Projeto pode ser ligado à mão; `fase_manual` corrige a fase do objetivo |
| `desempenho_dia` | gasto, impressões, cliques no link, cliques totais, leads da plataforma por campanha e dia (vazia até a coleta) |
| `planejamento` | por projeto: status, verba máxima e diária, metas de leads, receita, CPL e % MQL |
| `projeto_gestores` | gestores do projeto (vários) |
| `projeto_fases` | verba planejada e período de cada fase |

Fórmulas (banco em `mkt_trafego.resumo`, front em `web/modules/marketing/trafego/domain/kpis.ts`, as duas testadas com os
mesmos números): % da verba = investido ÷ verba máxima; CPL = investido ÷ leads; CTR = cliques no link ÷ impressões;
CPC = investido ÷ cliques no link; CPM = investido ÷ impressões × 1000; % MQL = MQL ÷ leads; connect rate = page views ÷
cliques no link; conversão da página = leads ÷ page views; ritmo = gasto de ontem ÷ verba diária; "deveria ter gasto" = verba
de cada fase distribuída por igual nos dias dela. **Sem fonte = nulo, nunca zero** (projeto sem gasto coletado mostra
"sem dado", não R$ 0).

### Acesso

Igual ao resto do Marketing: tabelas fechadas, só funções; `mkt.pode_ver('mkt_trafego')` = hoje só admin e dev. Os dois
`receber` só `service_role`. O ensaio confere a recusa (42501) para sem perfil, operador (mesmo com a área
`mkt_trafego`), visualizador e anon.

### Telas (`/marketing/trafego`, só admin e dev)

- **Projetos:** a tabela da Central com os filtros interno/externo, subárea (Interno, Aurum, Diamantes), gestor (CF, RS, EF,
  da lista do banco; casa com um dos gestores do projeto ou com o de alguma campanha), situação (status) e projetos
  desativados.
  Cartões: investido, verba, projetos acima da verba diária ontem, campanhas fora do padrão.
- **Vida do projeto** (clique na linha): investido × verba (por plataforma), ritmo de ontem, quanto deveria ter gasto
  pelas fases, KPIs × metas (com CPC e page views), fases planejado × gasto (uma linha por fase planejada ou com
  campanha nela, mais "sem fase"; criar, editar, apagar o planejamento), campanhas do projeto (fase "pelo objetivo" ou
  "à mão"), lugar das atividades do ClickUp. Botão **Planejamento** (status, gestores, verbas, metas).
- **Campanhas fora do padrão:** o nome exato, o que está fora, ligar à mão a um projeto, "Reler os nomes" (depois de
  cadastrar projeto ou página em Marketing > Projetos e páginas). Opção "só as sem projeto".
- **Contas de anúncio:** cadastro e edição.

### Testar localmente

1. **Ensaio do banco:** rodar `infra/supabase/migrations/20261005p_ensaio.sql` inteiro (termina em rollback) e conferir
   que nenhuma linha começa com `ERRADO` (o cabeçalho explica cada passo). Só dados fictícios.
2. **Telas sem banco:** em `web/.env.local`, `NEXT_PUBLIC_TRAFEGO_DEMO=1`; `npm run dev`; entrar como admin/dev e abrir
   `/marketing/trafego`. Projetos da semente + 2 externos "Exemplo", contas "Conta Exemplo", campanhas "EXEMPLO", gasto e
   leads inventados, com a faixa "Dados de demonstração" (grava só em memória; recarregar volta ao começo). Em produção
   (`NODE_ENV=production`) o modo nunca liga.
3. **Código:** `npx tsc --noEmit`, `npx vitest run` (`kpis.test.ts`, `fases.test.ts`, `demo.test.ts`), `npm run build`.

### Para valer

Victor ver a tela no modo demo e responder as perguntas abaixo; rodar o ensaio no SQL editor; aplicar a 20261005p; levar a
`victor` para a `main`; cadastrar contas e planejamento. Nada disso foi feito.

### O que falta (próximas etapas do plano)

2. Coleta Meta + Google (depende da conta centralizadora e das credenciais): rotina diária chamando os dois `receber`.
3. Ligar receita (Hotmart → projeto) e atividades do ClickUp. Connect rate e conversão já estão ligados; dependem da
   Web (20261005n) e da base de pessoas (20261005o) aplicadas e com dado.
4. Resumo do dia ("o que está pegando fogo") e alerta de nome fora do padrão.
5. MCP da central com os dados do Tráfego.
6. Importação do histórico (planilhas que o Victor escolher).

### Perguntas (respondidas pelo Victor em 05/10/2026, salvo as em aberto)

1. ~~Status~~ **Respondido:** ativo, pausado, inativo, encerrado (fica como está).
2. ~~Connect rate e conversão~~ **Respondido:** connect rate = page views ÷ cliques no link; conversão da página = leads
   ÷ page views. Ligado (ver Decisões).
3. ~~Cliques~~ **Respondido:** cliques no link para CTR e CPC; totais guardados à parte.
4. ~~Fase da campanha~~ **Respondido:** pelo objetivo do nome, com correção à mão prevalecendo; mapa e objetivos novos
   (CARRINHO, AQUECIMENTO) nas Decisões. DISTRIBUIÇÃO sem fase automática.
5. **Externos (Aurum, Diamantes):** em aberto (Victor vai ver com o Caio). Cada cliente vira um projeto em `mkt.projetos`?
   Qual sigla de campanha?
6. **Conta centralizadora** (ideia do Caio): em aberto. É dela que a coleta lê.
7. ~~Gestor do projeto~~ **Respondido:** vários gestores por projeto (`projeto_gestores`).

## Branches

Uma branch por pessoa, criadas a partir da `main` em 05/10/2026: `victor`, `joao-pedro`, `arthur`. Cada um
trabalha na sua. **Push na `main` publica em produção** (Hostinger): levar para a `main` só depois de
`npx tsc --noEmit`, `npx vitest run` e `npm run build` verdes em `web/`.

## Histórico

- **05/10/2026:** departamentos criados; rotas do Educacional movidas para `/educacional/...` com redirect 308;
  Marketing com as 5 áreas "Em breve", restrito a admin/dev; Comercial, Financeiro e Infra "Em breve".
  Branch `victor`.
- **05/10/2026:** base compartilhada do Marketing (migration 20261005m, NÃO APLICADA): `mkt.projetos`,
  `mkt.paginas`, listas e tradução do nome de campanha, schema `mkt_web` vazio, tela `/marketing/projetos`.
  Branch `victor`.
- **05/10/2026:** Marketing > Web (o Radar do Luiz, sem vídeo): migration 20261005n (NÃO APLICADA) com a coleta em
  `mkt_web`, rota pública `/api/web/coletar` com limite por IP e por sessão, gravador `/web/radar-v1.js`, telas em
  `/marketing/web`, modo de demonstração local e seed de dev. Virada documentada, não feita. Branch `victor`.
- **05/10/2026:** Comercial e base de pessoas: migration 20261005o (NÃO APLICADA) com os schemas `pessoas` (uma pessoa
  por identidade, cascata da casa, aluno e comprador por referência, origem, eventos, revisão, registro de acesso,
  máscara no SQL) e `crm` (4 pipelines, etapas configuráveis, negócios, histórico); telas em `/comercial` (só admin e
  dev) com modo de demonstração local. Perguntas abertas na seção "Comercial e base de pessoas". Branch `victor`.
- **05/10/2026:** Tráfego etapa 1 (migration 20261005p, NÃO APLICADA): contas, campanhas, desempenho diário, planejamento
  (status, verba, fases, metas) e a Central do Tráfego em `/marketing/trafego` (área ativa), com modo demo. Branch `victor`.
- **05/10/2026:** Tráfego, respostas do Victor na própria 20261005p (ainda NÃO APLICADA): cliques no link separados dos
  totais (CTR, CPC), connect rate e conversão da página ligados à Web e à base de pessoas, vários gestores por projeto,
  fase da campanha pelo objetivo do nome (com correção à mão), fases remarketing e abertura de carrinho, objetivos
  CARRINHO e AQUECIMENTO no padrão de nome.
