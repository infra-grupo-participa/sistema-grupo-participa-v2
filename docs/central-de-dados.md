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

## Padrões de nome de campanha e UTM

Fonte oficial: o repositório **gp-operacoes**, processos
`departamentos/dados/areas/infraestrutura/processos/padronizar-utm-dos-links.md` (UTM) e
`departamentos/marketing/areas/trafego/processos/nomear-campanhas-e-ler-relatorio.md` (nome de campanha). Aqui fica só o
resumo que o sistema usa; **se divergir, vale o gp-operacoes** (e este resumo precisa ser corrigido).

**Nome de campanha:** `GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA`, com a página opcional (só em teste de página).
Ex.: `RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1`. Lido por `mkt.campanha_traduzir` e
`web/modules/marketing/projetos/domain/campanha.ts` (a mesma regra nos dois; a do banco é a da migration 20261006e).

**Revisão do Victor (06/10/2026), migration 20261006e (NÃO APLICADA):**

- A **DESCRIÇÃO é tudo o que vem depois do OBJETIVO** e pode ter várias partes separadas por ` | `. Ex. real (Black
  Friday do Caio): `CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY` → gestor `CF`, projeto `BF26`,
  objetivo `ANTECIPAÇÃO`, descrição `TEASER | META | PQ | ABO | THRUPLAY`, sem página.
- A **PÁGINA** só é lida no **último** campo, com pelo menos uma parte de descrição antes, e só se tiver o formato do slug
  da casa (2 letras + número, sufixo opcional `-letra`: `ak1`, `bl2`, `jt10`, `ak1-b`; sem diferença de maiúscula).
  Senão o último campo é descrição (`RS | PB26 | LEADS | TESTE | OBRIGADO` está no padrão, descrição `TESTE | OBRIGADO`).
  Com 4 campos o quarto é sempre a descrição.
- **No padrão** = gestor, projeto e objetivo válidos + qualquer descrição. Objetivo com ou sem acento (`ANTECIPACAO` casa
  com `ANTECIPAÇÃO` se estiver na lista; aviso `sem_acento`).
- **Motivos de "fora do padrão"** (a tela mostra cada um com o que foi escrito): menos de 3 campos (`numero_de_campos`),
  gestor fora da lista, sigla fora do formato, projeto não cadastrado, objetivo fora da lista ("objetivo ANTECIPAÇÃO não
  está na lista"), sem descrição (só 3 campos) e parte vazia na descrição (`| |`). O erro antigo `pagina_invalida` deixou
  de existir.
- O retorno de `mkt.campanha_traduzir` manteve as mesmas chaves (quem usa: Web, pessoas e CRM da main, Tráfego) e ganhou
  `descricao_partes` e `campos`.
- **ANTECIPAÇÃO não está na lista de objetivos** (pergunta ao Victor abaixo). Até a resposta, a campanha do exemplo fica
  fora do padrão só pelo objetivo. Para ligar: `insert into mkt.campanha_objetivos (codigo) values ('ANTECIPAÇÃO')`, a
  fase em `mkt_trafego.objetivo_fase` (se tiver) e "Reler os nomes" na tela (comandos comentados na 20261006e).

| Campo | Valores (listas em `mkt.campanha_gestores`, `mkt.projetos`, `mkt.campanha_objetivos`) |
|---|---|
| Gestor | `CF`, `RS`, `EF` |
| Projeto (sigla) | `HT33`, `SEMSET26`, `PB26`, `BF26` |
| Objetivo → fase do Tráfego | `LEADS` → captação; `VENDAS` → captação (lançamento pago); `AQUECIMENTO` → aquecimento; `LEMBRETE` → lembrete; `REMARKETING` → remarketing; `CARRINHO` → abertura de carrinho; `DISTRIBUIÇÃO` → sem fase automática (marcar na campanha) |
| Página | código da casa (`AK1`, `BL2`, `AK1-B`), igual a `mkt.paginas.codigo` |

`CARRINHO` e `AQUECIMENTO` entram na lista pela 20261006g (ver "Tráfego").

**UTM do tráfego pago** (confirmado pelo Victor em 06/10/2026):

| Parâmetro | Meta | Google |
|---|---|---|
| `utm_source` | `metaads` | (ver o processo do gp-operacoes) |
| `utm_campaign` | a campanha, `nome\|id` | só o id (não existe macro de nome) |
| `utm_medium` | o conjunto de anúncios, `nome\|id` | (ver o processo do gp-operacoes) |
| `utm_content` | o anúncio (criativo), `nome\|id` | só o id |
| `utm_term` | o posicionamento | (ver o processo do gp-operacoes) |

Ex.: `utm_campaign=RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|120211234`. Como o nome da campanha já tem ` | `
dentro, **o id é o que vem depois da última `|`** (só se for número). Sem `|`: número é id, senão é nome (formato antigo,
dado histórico, continua valendo).

**Como o sistema lê:** uma função só, `mkt.utm_separar(texto)` → (nome, id) no banco (migration 20261006f) e
`separarUtm` em `web/modules/marketing/projetos/domain/utm.ts` (testes em `utm.test.ts`); `mkt_web.origem_ids` junta
campanha, conjunto (só com `utm_source=metaads`) e anúncio. **O cruzamento é sempre pelo id** (campanha do Tráfego,
anúncio); o nome só serve de reserva quando a visita não tem id, e é só o NOME que vai para a tradução do padrão de nome.
A coleta da Web guarda os ids em `mkt_web.sessoes.campaign_id`, `adset_id` e `ad_id` (o parâmetro explícito da URL vale
primeiro). Usam essa leitura: aba Origem, achados por criativo, connect rate (`mkt_web_connect`) e o resumo do Tráfego.

## Base compartilhada (Marketing)

Fase 1 da central de dados (decisões de 05/10/2026, `area-web-radar.md` no cérebro). É o cadastro que Web, Tráfego
e Mensageria leem; não é área. **Migration `infra/supabase/migrations/20261005m_mkt_base_compartilhada.sql`, JÁ
APLICADA** (ensaio `20261005m_ensaio.sql`, explicação `20261005m.explain.md`). Não se edita mais: mudança nela vai numa
migration nova (a 20261006j acrescenta tipo, unidade, tipo de lançamento, especialista e períodos em `mkt.projetos`).

| Peça | Onde | O que é |
|---|---|---|
| Projetos | `mkt.projetos` | Tabela de projetos ÚNICA. **Projeto = edição**; chave = sigla do nome de campanha (`PB26`, `HT33`, `SEMSET26`, `BF26`). Nome (livre), tipo/linha, edição, ano, etiqueta do ClickUp (texto exato, a chave única do gp-operacoes), início/fim, ativo. Desde a 20261006j: tipo (interno/externo), unidade, tipo de lançamento, especialista, períodos de captação e do evento; a subárea (interno/aurum/diamante) virou derivada |
| Páginas | `mkt.paginas` | Páginas de cada projeto: código da casa (`ak1`, `bl2`, `ak1-b`; opcional), domínio + caminho, função (captura, obrigado, quase_la, pesquisa, venda, outra), funil (texto curto), ativa |
| Listas do nome de campanha | `mkt.campanha_gestores`, `mkt.campanha_objetivos` | Gestores `CF`, `RS`, `EF`; objetivos `LEADS`, `VENDAS`, `REMARKETING`, `LEMBRETE`, `DISTRIBUIÇÃO` |
| Tradução do nome de campanha | `mkt.campanha_traduzir(text)` e `web/modules/marketing/projetos/domain/campanha.ts` | `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA` → campos + erros ("fora do padrão") + avisos. A mesma regra nos dois lados |
| Web | schema `mkt_web` | Coleta do Radar (migration 20261006f, ver a seção "Web"), tudo apontando para `mkt.projetos`/`mkt.paginas`, sem dado pessoal |
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
`infra/supabase/migrations/20261006f_mkt_web_coleta.sql`, NÃO APLICADA** (ensaio `20261006f_ensaio.sql`, explicação
`20261006f.explain.md`). Depende da 20261005m (aplicada).

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
| Origem e UTMs | `mkt_web_origem` | Plataforma (`utm_source`), campanha (`utm_campaign` em `nome\|id`, contada pelo id; só o nome é traduzido pelo padrão de nome, campo 5 = página), anúncio (`utm_content` = o anúncio/criativo em `nome\|id`, contado pelo id), fbclid/gclid, site de origem. Ver "Padrões de nome de campanha e UTM" |
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

### Fase 2 (migration 20261006h, NÃO APLICADA)

`infra/supabase/migrations/20261006h_mkt_web_fase2.sql` + `_ensaio.sql` + `20261006h.explain.md`. Depende da 20261006f.
Tudo sobre o que o gravador `radar-v1.js` já grava (não mudou: sem `radar-v2.js`).

| Peça | Onde | Como funciona |
|---|---|---|
| Fluxo | `mkt_web_fluxo`, `domain/fluxo.ts`, `ui/paineis-fase2.tsx` | A visita vira a sequência de caminhos de `mkt_web.visualizacoes`. Não é o Fluxo do Radar (pessoas do CRM, pesquisa), que segue fora da Web |
| Achados automáticos | `domain/achados.ts` (regras), `mkt_web_melhorias` (somas) | Porte de `oportunidades.ts` do Luiz com os mesmos limiares: primeira dobra (celular x desktop, rejeição que subiu), promessa do criativo, botão que ninguém vê, seção onde a leitura morre, campo do formulário, fricção, velocidade; aprendizados "o que o MQL lê" e "qual botão converte". Cada regra cita a origem no código. Ganho = teto de leads por semana. A regra de publicações não veio (publicações fora de escopo) |
| Testes A/B | `domain/testes-ab.ts` | Grupo pelo código da casa: `ak1` (original) x `ak1-b`, `ak1-c`. Conta quem entrou por cada versão. Teste de duas proporções, amostra para enxergar 20% (fator 7,85), veredito só com a amostra e 7 dias, aviso de divisão desigual (porte de `testes.ts` do Luiz). O teste não é cadastrado: vale o período da tela |
| Comparar | `mkt_web_comparar`, `ui/Comparar.tsx` | Duas páginas no mesmo período, ou a mesma página (ou o projeto) em dois períodos; veredito pela taxa de lead sobre quem viu a página, lado a lado, por aparelho e por origem |
| Mapa de calor sobre a página | `mkt_web_calor`, `domain/calor.ts`, `ui/MapaCalor.tsx` | Ponto = x % da largura e y como fração da altura da página vista. Fundo padrão = captura de página inteira do último teste do Google do mesmo aparelho; opção "página ao vivo" (iframe sem JavaScript, com aviso: o `<noscript>` do pixel do Meta pode contar visita, e a página pode recusar o quadro); opção sem fundo. Pintura portada do `calor.ts` do Luiz |
| PageSpeed de laboratório | `mkt_web.velocidade_lab`, Edge `infra/supabase/functions/mkt-web-pagespeed`, cron `mkt-web-pagespeed` (06:40 SP, pelo `ops.cron_post`) | Páginas ativas de projeto com a coleta ligada, celular e computador, 1 vez por dia (máx. 12 por chamada; o resto no dia seguinte). Guarda notas, LCP, FCP, TBT, Speed Index, CLS, 5 oportunidades, a captura e a falha. Chave do Google **opcional** no Vault (`mkt_web_pagespeed_api_key`); sem ela, a cota pública. A Edge confere o header `x-sync-chave` sozinha e está no `infra/supabase/config.toml` com `verify_jwt = false` (sem isso o cron recebe 401). `mkt_web.config` `pagespeed = desligado` para |
| Lead ligado à pessoa | `mkt_web_leads` | Leads da Web cujo navegador tem `visitantes.lead_ref` (gravado pela 20261005o) e quantos viraram MQL no projeto. Referência e link `/comercial?pessoa=<id>` (abre a ficha) só para `pessoas.pode_ver()` (admin/dev). Sem a 20261005o: só os números da Web |
| Connect rate | `mkt_web_connect` | Definição do Victor: **page views ÷ cliques no link**; conversão da página = **leads ÷ page views**. Por campanha do Tráfego, casada **pelo id** (`campaign_id` da URL ou o id do `utm_campaign` em `nome\|id`; Google só id); sem id na visita, pelo nome exato. Cliques no link = coluna `cliques_link`/`cliques_no_link` de `mkt_trafego.desempenho_dia`; sem ela, connect rate em branco (nunca o total de cliques). Por anúncio, só a Web (o Tráfego não guarda clique por anúncio). Sem a 20261006g: só as page views por anúncio |
| Páginas do PB26 | a própria migration | As que faltam das 11 do `patrimonio-brasil.json` (`obs = '20261006h: …'`); o passo 3 da virada fica feito ao aplicar |

**Aplicar:** 20261006f → ensaio da 20261006h (nenhum `ERRADO`) → publicar a Edge (`supabase functions deploy
mkt-web-pagespeed`) → 20261006h. A chave do Google, se o Victor quiser (sem ela vale a cota pública):
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
- **Ensaio da 20261006h:** com a 20261006f aplicada, rodar `20261006h_ensaio.sql` inteiro (termina em rollback) e
  conferir que nenhuma linha começa com `ERRADO`.

### Virada (trocar o gravador do PB para o nosso). NÃO feita; fazer fora da semana do evento (09 a 11/11)

O FTP das páginas do PB é do Luiz (publicação pelo `scripts/deploy.py` dele). Passo a passo, com data combinada com ele:

1. **Aplicar a 20261006f** em produção: rodar antes o `20261006f_ensaio.sql` e conferir os esperados; depois a
   migration. Conferir `select jobname, schedule from cron.job where jobname like 'mkt-web-%'` (3 rotinas).
2. **Publicar** a branch (merge na `main`). Conferir `https://grupoparticipa.app.br/web/radar-v1.js` (200, JavaScript)
   e que `POST /api/web/coletar` sem origem responde `dominio` (403).
3. **Cadastrar as páginas** do PB26 que faltam: **a 20261006h faz isso** (as 11 do `patrimonio-brasil.json` do Luiz:
   `/`, `/ak1/`, `/bl2/`, `/bl2-otimizacao/`, `/quase-la/`, `/pesquisa/`, `/obrigado/`, `/inscricao-recebida/`,
   `/profissionais/`, `/profissionais/advogados/`, `/profissionais/contadores/`, só as que faltam). Sem a 20261006h,
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
Tráfego). Saíram desta lista com a fase 2 (20261006h, não aplicada): mapa de calor sobre a página, Melhorias (achados,
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
`visitante` do gravador; a função devolve só `ref`, `como` e `revisao` e, se a 20261006f estiver aplicada, grava a `ref`
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
> branch `victor`. Migration `infra/supabase/migrations/20261006g_mkt_trafego.sql`, **NÃO APLICADA** (ensaio
> `20261006g_ensaio.sql`; o que foi medido em `20261006g.explain.md`). Tela `/marketing/trafego`, código em
> `web/modules/marketing/trafego/`.
> **Fase 2** (05/10/2026, mesma branch): migration `20261006i_mkt_trafego_fase2.sql`, **NÃO APLICADA** (depende da
> 20261006g; ensaio `20261006i_ensaio.sql`; o que foi medido em `20261006i.explain.md`). Resumo do dia, receita da
> Hotmart, atividades do ClickUp e a coleta Meta Ads (Edge pronta, **desligada**). Detalhe em "Fase 2" abaixo.
> **Cadastro do projeto** (06/10/2026, mesma branch): migration `20261006j_mkt_projetos_cadastro.sql`, **NÃO APLICADA**
> (depende da 20261006g e da 20261006i; ensaio `20261006j_ensaio.sql`; o que foi medido em `20261006j.explain.md`). Tipo e
> unidade, tipo de lançamento, especialista, contas do projeto, períodos, pacote, checklist de montagem e gerador de nome
> e UTM. Detalhe em "Cadastro do projeto" abaixo.

### Situação

| Peça | Situação |
|---|---|
| Banco (schema `mkt_trafego`, 13 funções `public.trafego_*`) | escrito e ensaiado em Postgres local; **não aplicado** |
| Tela `/marketing/trafego` (Projetos, Campanhas fora do padrão, Contas de anúncio, vida do projeto) | pronta; funciona de verdade só depois da migration; hoje dá para ver no modo demo |
| Coleta Meta Ads | **Edge `trafego-meta` pronta e testada com respostas simuladas, DESLIGADA** (20261006i): falta o Victor decidir o token (conta centralizadora ou um por conta) e ligar o cron |
| Coleta Google Ads | só o desenho e o esqueleto da conversão (`trafego-google/google.ts`); falta developer token, MCC e OAuth |
| Resumo do dia ("o que está pegando fogo") | pronto no banco e na tela (20261006i, não aplicada); limiares iniciais **propostos**, a confirmar |
| Receita (Hotmart) | ligada pelo vínculo produto → projeto, **cadastrado à mão** na vida do projeto (20261006i, não aplicada). Sem vínculo, "sem dado" |
| Connect rate e conversão da página | **ligados** no banco à Web fase 2 (20261006h, a mesma conta de `public.mkt_web_connect`). Sem a 20261006h aplicada, "sem dado" com aviso na tela |
| Atividades do ClickUp | espelho pela etiqueta do projeto e linha do tempo junto do gasto diário (20261006i, não aplicada). Rotina `trafego-clickup` pronta, **DESLIGADA** (falta o token e o id do workspace) |
| Contas de anúncio do Meta | as 16 que o token do sistema enxerga, com unidade e principal (20261006k, **não aplicada**); CA - Tutorial inativa. Token já salvo em produção; coleta **desligada** |
| Cadastro do projeto (evento) | tela pronta na Central (botão "Novo projeto" e "Projeto" na vida do projeto), banco escrito e ensaiado (20261006j, **não aplicada**); hoje dá para ver no modo demo |

### Decisões que mandam aqui (Victor, 05/10/2026)

- **KPIs da tabela:** CPL, leads, CTR, CPM, connect rate, conversão da página, % MQL. Mais status, projeto, receita gerada,
  investimento realizado, investimento máximo, % da verba e gestores.
- **Cliques no link** (Victor): CTR = cliques no link ÷ impressões; CPC = investido ÷ cliques no link. O gasto diário
  guarda cliques no link e cliques totais **separados**; os totais são só informação.
- **Connect rate = page views ÷ cliques no link; conversão da página = leads ÷ page views** (Victor). Para não ter dois
  números para o mesmo indicador, a page view é **a mesma da Web fase 2** (`public.mkt_web_connect`, 20261006h): a
  entrada na página vinda da campanha, **uma por visita** (`mkt_web.sessoes`, sem visita de teste), casada com a campanha
  do Tráfego **pelo id** (`campaign_id` da URL, ou o id do `utm_campaign` no formato `nome|id` do gp-operacoes, ou só id);
  sem id na visita, pelo nome exato (ver "Padrões de nome de campanha e UTM"). Orgânico e campanha que não está no
  Tráfego não entram. O lead da conversão também é o da Web: dessas visitas, as que viraram lead. O ensaio confere que o
  resumo do Tráfego e o `mkt_web_connect` dão o mesmo número. Projeto com campanha e sem visita = 0 page views (connect
  rate 0%); sem campanha no Tráfego = "sem dado". Por anúncio (`utm_content` = o anúncio (criativo) no formato `nome|id`,
  padrão oficial do gp-operacoes; o sistema cruza pelo id) só a Web mostra, porque o
  Tráfego ainda não guarda clique por anúncio.
- **Vários gestores por projeto** (Victor): tabela `projeto_gestores` (siglas da lista `mkt.campanha_gestores`).
- **Fases:** aquecimento, captação, lembrete, remarketing, abertura de carrinho. A fase da campanha sai do **objetivo** do
  nome (mapa `objetivo_fase`, configurável por SQL); a **correção à mão** na campanha prevalece; sem regra e sem correção =
  "sem fase". Mapa (Victor): LEADS e VENDAS → captação (VENDAS = lançamento pago, a campanha vende o ingresso em vez de
  captar lead), AQUECIMENTO → aquecimento, LEMBRETE → lembrete, REMARKETING → remarketing, CARRINHO → abertura de
  carrinho. **DISTRIBUIÇÃO** (distribuição de conteúdo) **não tem fase automática**: pode ou não ser aquecimento, fica
  "sem fase" até alguém marcar na campanha.
- **Objetivos do nome de campanha** passam a ser 7: LEADS, VENDAS, REMARKETING, LEMBRETE, DISTRIBUIÇÃO, **CARRINHO**
  (anuncia o produto principal na abertura de carrinho, em lançamento pago ou gratuito) e **AQUECIMENTO**. Os dois novos
  entram em `mkt.campanha_objetivos` (lista da 20261005m) pela 20261006g, com insert idempotente; o tradutor
  `mkt.campanha_traduzir` reconhece porque lê a lista. Na tela "Testar nome de campanha" (Marketing > Projetos e páginas)
  passam a valer depois de aplicar a 20261006g.
- **Status do projeto marcado à mão.** Verba, fases e metas preenchidas por Arthur, Victor e Caio (no banco: admin/dev).
  **Pendente (06/10/2026):** gestores e Arthur editam verba, fases e metas, depende do novo modelo de acesso do sistema
  (o Victor vai redefinir os níveis de acesso do sistema inteiro). Por ora, só admin/dev.
- **Lead que conta é o da nossa base** (`pessoas.eventos`, 20261005o): pessoas distintas com evento `lead` no projeto, sem
  pessoa de teste nem mesclada. Os leads que a plataforma informa ficam só na campanha.
- **"Quanto gerado" = receita** (Hotmart). Na fase 2: soma das compras aprovadas dos produtos ligados à mão ao projeto
  (ver "Fase 2"). Sem vínculo, nula.
- **Atividades do ClickUp ficam na tela** (pela etiqueta do projeto). Na fase 2: lista e linha do tempo com o gasto.
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
cliques no link; conversão da página = leads da página ÷ page views (as duas com a page view da Web fase 2); ritmo = gasto de ontem ÷ verba diária; "deveria ter gasto" = verba
de cada fase distribuída por igual nos dias dela. **Sem fonte = nulo, nunca zero** (projeto sem gasto coletado mostra
"sem dado", não R$ 0).

### Acesso

Igual ao resto do Marketing: tabelas fechadas, só funções; `mkt.pode_ver('mkt_trafego')` = hoje só admin e dev. Os dois
`receber` só `service_role`. O ensaio confere a recusa (42501) para sem perfil, operador (mesmo com a área
`mkt_trafego`), visualizador e anon.

### Telas (`/marketing/trafego`, só admin e dev)

- **Projetos:** a tabela da Central com os filtros interno/externo, unidade (CSM, Escritório, Aurum, Diamantes, "sem unidade"; 20261006j), gestor (CF, RS, EF,
  da lista do banco; casa com um dos gestores do projeto ou com o de alguma campanha), situação (status) e projetos
  desativados.
  Cartões: investido, verba, projetos acima da verba diária ontem, campanhas fora do padrão.
  **Resumo do dia** no topo (fase 2): os alertas de ontem, alta primeiro, com a sigla clicável (abre a vida do projeto),
  a situação das coletas e "Ver as regras e os limiares".
- **Vida do projeto** (clique na linha): investido × verba (por plataforma), ritmo de ontem, quanto deveria ter gasto
  pelas fases, KPIs × metas (com CPC e page views), fases planejado × gasto (uma linha por fase planejada ou com
  campanha nela, mais "sem fase"; criar, editar, apagar o planejamento), campanhas do projeto (fase "pelo objetivo" ou
  "à mão"), **receita gerada** com os produtos da Hotmart ligados (ligar, editar, apagar; o campo do id sugere os
  produtos que já venderam) e **atividades do ClickUp** com a linha do tempo do gasto diário (fase 2). Botão
  **Planejamento** (status, gestores, verbas, metas).
- **Campanhas fora do padrão:** o nome exato, o que está fora, ligar à mão a um projeto, "Reler os nomes" (depois de
  cadastrar projeto ou página em Marketing > Projetos e páginas). Opção "só as sem projeto".
- **Contas de anúncio:** cadastro e edição.
- **Novo projeto / Projeto (20261006j):** o cadastro do evento (ver "Cadastro do projeto"). Na tabela, coluna Montagem (x
  de y itens do checklist prontos); na vida do projeto, cadastro, campanhas sugeridas, checklist e gerador de nome e UTM.
- **Modelos de lançamento (20261006l, no lugar de "Pacotes e checklist"):** lista com filtro por tipo e unidade, editar,
  duplicar, ativar/inativar; os "Exemplo: …" com o selo "Rascunho a validar". Ver a seção "Modelos de lançamento".

### Testar localmente

1. **Ensaio do banco:** rodar `infra/supabase/migrations/20261006g_ensaio.sql` inteiro (termina em rollback) e conferir
   que nenhuma linha começa com `ERRADO` (o cabeçalho explica cada passo). Só dados fictícios.
2. **Telas sem banco:** em `web/.env.local`, `NEXT_PUBLIC_TRAFEGO_DEMO=1`; `npm run dev`; entrar como admin/dev e abrir
   `/marketing/trafego`. Projetos da semente + 2 externos "Exemplo", contas "Conta Exemplo", campanhas "EXEMPLO", gasto e
   leads inventados, com a faixa "Dados de demonstração" (grava só em memória; recarregar volta ao começo). Em produção
   (`NODE_ENV=production`) o modo nunca liga.
3. **Código:** `npx tsc --noEmit`, `npx vitest run` (`kpis.test.ts`, `fases.test.ts`, `demo.test.ts`; fase 2:
   `alertas.test.ts`, `linha-do-tempo.test.ts`, `coleta.test.ts`, `ui/fase2.test.ts`), `npm run build`.
4. **Fase 2:** com a 20261006g aplicada, rodar `20261006i_ensaio.sql` inteiro (termina em rollback) e conferir que
   nenhuma linha começa com `ERRADO` ("PULADO" é esperado onde falta Vault, pg_cron ou a 20261005o). No modo demo
   aparecem o resumo do dia, a receita do PB26 (produto "Ingresso Exemplo", R$ 18.450 fictícios) e as atividades
   "Exemplo: …" do ClickUp na vida do PB26. As Edges: `deno check infra/supabase/functions/trafego-meta/index.ts
   infra/supabase/functions/trafego-clickup/index.ts`; a parte pura roda no vitest com respostas simuladas
   (`infra/supabase/functions/_trafego-fixtures`), sem credencial e sem chamar API real.

### Para valer

Victor ver a tela no modo demo e responder as perguntas abaixo; rodar o ensaio no SQL editor; aplicar a 20261006g; levar a
`victor` para a `main`; cadastrar contas e planejamento. Fase 2: rodar o ensaio da 20261006i, aplicar, ligar à mão os
produtos da Hotmart de cada projeto e, quando decidir os tokens, ligar as rotinas (abaixo). Nada disso foi feito.

### O que falta (próximas etapas do plano)

2. Coleta Meta: **feita e desligada** (falta o token). Google: só desenho e esqueleto (falta developer token, MCC, OAuth).
3. Receita e ClickUp: **feitos** (20261006i, não aplicada); faltam os vínculos de produto (à mão) e o token do ClickUp.
   Connect rate e conversão já estão ligados; dependem da Web fase 2 (20261006h) aplicada e com dado.
4. Resumo do dia: **feito** (20261006i, não aplicada), com limiares a confirmar. Alerta fora da tela (Slack, e-mail): não feito.
5. MCP da central com os dados do Tráfego (fora desta fase).
6. Importação do histórico (planilhas que o Victor escolher; fora desta fase).
7. Externos (Aurum, Diamantes): estrutura decidida em 06/10/2026 (tipo externo, unidade Aurum ou Diamantes) e no
   cadastro (20261006j); a sigla deles no nome de campanha segue em aberto.

### Fase 2 (migration 20261006i, NÃO APLICADA)

`infra/supabase/migrations/20261006i_mkt_trafego_fase2.sql` + `_ensaio.sql` + `20261006i.explain.md`. Depende da
20261006g. Tudo o que não dependia de decisão em aberto; o que depende (tokens, limiares, bruto × líquido) ficou
configurável e está nas perguntas.

| Peça | Onde | Como funciona |
|---|---|---|
| Resumo do dia | `public.trafego_alertas`, `mkt_trafego.alertas`; `domain/alertas.ts`; `ui/ResumoDia.tsx` | Sobre ontem (São Paulo), só projetos ativos e com status que entra no resumo (`status_projeto.entra_no_resumo_dia`: inativo e encerrado ficam fora). 7 regras, limiar em `mkt_trafego.alerta_regras` (tabela abaixo). A mesma regra no front para o demo e os testes |
| Receita | `mkt_trafego.produtos_hotmart` (vínculo à mão), `mkt_trafego.receita`, `public.trafego_produto_*`, `trafego_hotmart_produtos`; `ui/ProdutosHotmart.tsx` | Soma `public.compras.preco` das compras **APPROVED, COMPLETE ou COMPLETED** (a regra que o repo já usa em `public.compras`) dos produtos ligados, com data `coalesce(data_aprovacao, data_compra)` no período (do vínculo, senão o do projeto; sem fim = até hoje; sem início não soma). Oferta opcional. Só BRL na soma (outra moeda contada à parte). Compra que casa com dois vínculos conta uma vez. Nada é copiado: lido na hora |
| Atividades do ClickUp | `mkt_trafego.clickup_tarefas` (espelho mínimo), `public.trafego_clickup`, `public.trafego_clickup_receber`; Edge `trafego-clickup`; `ui/ClickupPainel.tsx`, `domain/linha-do-tempo.ts` | A rotina lê (só GET) as tarefas de cada etiqueta de projeto ativo, todas as páginas, e grava o conjunto inteiro (quem não veio perde a etiqueta). Na vida do projeto: barras do gasto diário e bolinhas das atividades no dia (concluída, senão prazo, início ou criação) e a lista |
| Coleta Meta Ads | Edge `trafego-meta` (`meta.ts` puro + `index.ts`); `mkt_trafego.meta_contas`, `coleta_config`, `coletas` | Para cada conta Meta ativa: campanhas (nome exato e status) e insights por campanha e dia (`spend`, `impressions`, `inline_link_clicks` = cliques no link, `clicks` = totais, ação `lead` = leads da plataforma) dos últimos `meta_dias` (3) dias completos e hoje; grava pelos `receber` da 20261006g (campanhas antes, upsert idempotente). Token só no header; falha por conta vira código curto em `mkt_trafego.coletas` |
| Google Ads | `infra/supabase/functions/trafego-google/google.ts` | Só o esqueleto (GAQL e conversão de micros), sem `index.ts`. Desenho abaixo |

**Limiares (confirmados pelo Victor em 06/10/2026: verba diária, CPL, ritmo da fase e 90 % da verba; os avisos de leads
abaixo da meta e de campanha fora do padrão/sem fase ficam ligados, e o Victor não comentou esses dois):**

| Regra | Dispara quando | Limiar | Gravidade |
|---|---|---|---|
| Acima da verba diária | gasto de ontem > verba diária × (1 + limiar) | 0 % | alta |
| CPL acima da meta | CPL > meta de CPL × (1 + limiar) | 0 % | alta |
| Abaixo da meta de leads para a data | leads < esperado × (1 − limiar); esperado = meta × dias passados ÷ dias da captação planejada (senão do projeto) | 20 % | alta |
| Ritmo da fase fora do planejado | fase em andamento: gasto desde o início fora de esperado × (1 ± limiar); esperado = verba × dias passados ÷ dias da fase | 20 % | média |
| % da verba perto do fim | % da verba ≥ limiar | 90 % | média |
| Campanhas fora do padrão | fora do padrão com gasto nos últimos N dias (inclui sem projeto) | 7 dias | média |
| Campanhas sem fase | sem fase com gasto nos últimos N dias | 7 dias | média |
| Campanha do projeto em conta de fora (20261006j) | campanha com a sigla do projeto gastando nos últimos N dias numa conta que não é do projeto; só avalia projeto com conta ligada | 7 dias | média |

Mudar: `update mkt_trafego.alerta_regras set limiar = 30 where codigo = 'ritmo_fase';` (ou `ligada = false`).

**Ligar as rotinas (NÃO feito; decisão do Victor).** Ordem:
1. Publicar as Edges: `supabase functions deploy trafego-meta` e `supabase functions deploy trafego-clickup`
   (`verify_jwt = false` já está no `infra/supabase/config.toml`; elas conferem o header `x-sync-chave`, segredo
   `trafego_coleta_chave` que a migration cria no Vault).
2. Tokens no Vault, pelo SQL editor, **nunca no código nem no chat**:
   - Meta, conta centralizadora: `select vault.create_secret('<token>', 'meta_ads_token', 'Token Meta Ads, leitura');`
   - Meta, token por conta: `select vault.create_secret('<token>', 'meta_ads_token_<nome>', '…');` e
     `update mkt_trafego.contas set token_vault = 'meta_ads_token_<nome>' where id = <id>;` (conta sem `token_vault`
     usa o `meta_ads_token`). O token precisa ler insights (`ads_read`) das contas.
   - ClickUp: `select vault.create_secret('<token>', 'clickup_api_token', 'Token ClickUp, só leitura');` e
     `update mkt_trafego.coleta_config set valor = '<id do workspace>' where chave = 'clickup_team_id';`.
     **O token do ClickUp é decisão do Victor** (de quem é, qual usuário: ele enxerga só o que esse usuário enxerga).
3. Cadastrar as contas Meta em Marketing > Tráfego > Contas de anúncio.
4. Testar uma vez à mão (SQL editor): `select ops.cron_post('trafego-meta', url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-meta', body := '{"so_hoje": true}'::jsonb, headers := jsonb_build_object('Content-Type','application/json','x-sync-chave',(select decrypted_secret from vault.decrypted_secrets where name='trafego_coleta_chave')), timeout_milliseconds := 150000);`
   e ver `select * from mkt_trafego.coletas order by id desc limit 5;`.
5. Agendar: o bloco **LIGAR AS ROTINAS** no fim da migration (`trafego-meta` 06:30 SP, `trafego-clickup` 07:00 SP,
   opcional `trafego-meta-hoje` de 3 em 3 horas), sempre pelo `ops.cron_post` (regra 11 do CLAUDE.md).
   Recarga de dias passados: corpo `{"de": "AAAA-MM-DD", "ate": "AAAA-MM-DD"}` (até 92 dias).
   Desligar: `select cron.unschedule('trafego-meta'); select cron.unschedule('trafego-clickup');`.

**Google Ads: desenho (não funciona).** Precisa de: (1) **developer token** da API do Google Ads, pedido na conta
administradora e aprovado pelo Google (o nível "básico" basta para leitura); (2) **conta administradora (MCC)** com
acesso às contas dos projetos (o id vai no header `login-customer-id`); (3) **OAuth 2.0**: client id e secret de um
projeto do Google Cloud e um refresh token de um usuário com acesso à MCC. Tudo no Vault (`google_ads_developer_token`,
`google_ads_client_id`, `google_ads_client_secret`, `google_ads_refresh_token`). A rotina troca o refresh token por um
access token, chama `POST https://googleads.googleapis.com/<versão>/customers/<conta>/googleAds:searchStream` com a
consulta de `consultaGaql` (campanha × dia: custo em micros, impressões, cliques) e grava pelos mesmos `receber`. Decisão
pendente: no Google, "cliques no link" = `metrics.clicks` (clique no anúncio); totais e leads ficam nulos.

### Cadastro do projeto (migration 20261006j, NÃO APLICADA)

`infra/supabase/migrations/20261006j_mkt_projetos_cadastro.sql` + `_ensaio.sql` + `20261006j.explain.md`. Depende da
20261006g e da 20261006i (aplicar m, p, r e só então esta). A 20261005m já aplicada não foi editada: as colunas novas de
`mkt.projetos` entram por `alter table` e um gatilho.

**Decisões do Victor (06/10/2026):**

- **Estrutura:** projeto **interno** ou **externo**. Interno: unidade **CSM** (CSM Academy, o educacional) ou
  **Escritório** (escritório de advocacia). Externo: **Aurum** ou **Diamantes**. Substitui a subárea plana; os filtros
  da Central são tipo e unidade. Migração sem perda: subárea interno → interno sem unidade (CSM ou Escritório não está em
  fonte nenhuma; quem sabe marca na tela); aurum → externo Aurum; diamante → externo Diamantes; sem subárea → sem tipo.
  A subárea continua na tabela, derivada de tipo e unidade (a tela `/marketing/projetos` e o resumo da 20261006g a leem).
- **Tipos de lançamento** (tabela `mkt.tipos_lancamento`, regras em `mkt.lancamento_regras`; o banco recusa combinação
  fora da regra, a tela só oferece o que vale):

  | Unidade | Tipos de lançamento |
  |---|---|
  | CSM | Lançamento clássico, Lançamento pago, Lançamento pago semanal gravado (LPSG), ATM |
  | Escritório | Lançamento clássico, ATM (**lançamento pago e LPSG só existem na CSM**; Victor, 06/10/2026) |
  | Diamantes | Lançamento clássico, Lançamento pago |
  | Aurum | Palestra (fixo, preenchido sozinho) |

  "Lançamento gratuito" = lançamento clássico. **Perpétuo saiu** do interno (Victor, 06/10). **ATM** = ação curta para a
  base antiga/existente, sem captação nova (por ora é só ter o tipo). Projeto só de distribuição de conteúdo NÃO é tipo
  de lançamento (pergunta abaixo); campanha de distribuição dentro de um projeto já existe (objetivo DISTRIBUIÇÃO).
- **Especialista** (`mkt.especialistas`): interno = lista (semente: Marcio Carvalho de Sá e Elaine Montenegro; mais por
  SQL); externo = a pessoa/cliente do Aurum ou Diamantes, cadastrada na hora pela tela (nada semeado).
- **Nome do projeto é livre** (ex.: Seminário de setembro, Patrimônio Brasil, Seminário Conjunto, Black Friday, HT
  Delegado). Nenhum projeto novo semeado.
- **Revisão do Victor (06/10/2026):**
  - **Campo "Linha" saiu** do cadastro (o nome basta). A coluna `mkt.projetos.linha` é da 20261005m (aplicada e
    obrigatória) e ficou: projeto novo pelo Tráfego grava o nome nela; na edição ela não muda. A tela
    `/marketing/projetos` (função `mkt_projeto_salvar`, aplicada) ainda pede a linha; tirar de lá pede migration nova.
  - **Status "Em planejamento"** antes de Ativo (lista: em planejamento, ativo, pausado, inativo, encerrado). Em
    planejamento fica **fora do resumo do dia**, como inativo e encerrado (`entra_no_resumo_dia = false`; 20261006g e
    20261006i editadas no lugar).
  - **Etiqueta do ClickUp com busca:** a pessoa digita "seminario" e aparecem as etiquetas que contêm isso, sem acento e
    sem diferença de maiúscula (`public.trafego_clickup_etiquetas_buscar(busca, limite)`, admin/dev; tela
    `ui/EtiquetaClickupCampo.tsx`, regra em `domain/etiquetas.ts`). Fontes, juntas e sem repetição: as etiquetas que o
    painel de KPIs já grava (`kpi.medicao_tarefa.etiquetas`, sem token novo; lida só se a tabela existir e der acesso) e o
    espelho do ClickUp do Tráfego (`mkt_trafego.clickup_etiquetas_vistas` e `clickup_tarefas`, quando a rotina rodar).
    Só entram etiquetas no formato da chave. Etiqueta que não está na lista continua aceita, com o aviso "não encontrada
    no ClickUp".
  - **Gerador de nome:** descrição livre com várias partes (`TEASER | META | PQ`); sem página escolhida, a última parte
    não pode ter cara de código de página (o nome seria lido com página).
- **Etiqueta do ClickUp = o projeto** (a chave única do gp-operacoes, `modus-operandi/padronizacao-de-repositorio.md`:
  minúsculo, sem acento, hífen, ano-mês no fim quando é edição datada; a mesma string na pasta, na etiqueta, no canal e
  no `utm_campaign` dos disparos). A tela valida o formato (recusa fora dele; edição com data sem `-aaaa-mm` só avisa).
  Quando a rotina `trafego-clickup` tiver token e rodar, ela também lê as etiquetas reais dos spaces do workspace (só
  leitura: `GET /team/{id}/space` e `GET /space/{id}/tag`) para `mkt_trafego.clickup_etiquetas_vistas`, e a tela passa a
  oferecer a escolha entre elas; sem isso, texto.
- **Períodos:** período de **captação** e período do **evento**, separados. O início/fim de antes continua como o período
  do projeto inteiro: o gatilho calcula do começo mais cedo ao fim mais tarde quando algum período novo é preenchido; sem
  período novo, a data de antes fica (não se sabe se era de captação ou de evento). A captação é o **padrão** da fase de
  captação (pacote, "Nova fase" na tela, meta de leads do resumo do dia): `mkt_trafego.periodo_padrao`.
- **Receita sem período próprio do produto** (Victor, 06/10/2026): conta do **início da captação até o fim do período do
  evento**, para pegar a abertura de carrinho. **PROVISÓRIO, a confirmar depois pelo Victor.** A regra mora num lugar só:
  `mkt_trafego.periodo_receita` (criada na 20261006i, trocada pela 20261006j) e `periodoReceita` em
  `web/modules/marketing/trafego/domain/cadastro.ts`. Sem captação: começa no evento; sem período novo: início e fim do
  projeto, como antes.
- **Contas de anúncio do projeto** (`mkt_trafego.projeto_contas`): sugerem campanhas da conta com a sigla no nome (palavra
  inteira) e sem projeto, para ligar com um clique; criar o projeto (ou trocar a sigla) relê as campanhas e liga as que
  estão no padrão com a sigla; e o resumo do dia avisa quando uma campanha com a sigla gasta numa conta que não é do
  projeto (regra `conta_fora_projeto`, 7 dias, média).
- **Gestores:** CF, RS e EF; qualquer gestor opera interno ou externo (sem restrição).
- **Receita dos externos não entra** por ora: projeto externo mostra "não se aplica".
- **Pacote da campanha:** substituído pelos **modelos de lançamento** (20261006l, seção própria abaixo).
- **Gerador de nome de campanha e UTM** (vida do projeto): gestor, objetivo, descrição e página opcional →
  `GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA` (conferido pela mesma tradução do banco) e a linha de parâmetros do
  Meta, com botão de copiar. Parâmetros em `mkt_trafego.utm_parametros` (muda por SQL):
  `utm_source=metaads&utm_campaign={{campaign.name}}|{{campaign.id}}&utm_medium={{adset.name}}|{{adset.id}}&utm_content={{ad.name}}|{{ad.id}}&utm_term={{placement}}`.
  Macros conferidas na documentação do Meta (parâmetros de URL dinâmicos) e em guias que a citam; a página oficial não
  abriu fora do navegador, então a tabela é configurável. Google: sem linha (fica como está). UTM: nada mudou.
- **Checklist de montagem** (vida do projeto e coluna Montagem na Central, x de y): itens **automáticos** que o banco
  confere (contas de anúncio vinculadas; campanhas com a sigla; nenhuma fora do padrão e fase de cada campanha, quando há
  campanha; produtos da Hotmart, não se aplica a externo; páginas cadastradas; etiqueta do ClickUp; verba máxima; fases
  planejadas; metas de leads, receita ou CPL) e itens **manuais**. Desde a 20261006l os manuais são do projeto (vêm do
  modelo ou são criados na hora), tudo agrupado por momento e com o caminho para resolver (seção "Modelos de lançamento").
- **Onde mora a tela:** na Central do Tráfego (botão "Novo projeto" e "Projeto" na vida do projeto), porque os campos são
  do Tráfego e o resto da montagem está lá; grava na tabela de projetos única (`mkt.projetos`). `/marketing/projetos`
  continua para páginas e dados gerais e mostra o tipo derivado.
- **Leads do Meta:** fica a ação `lead` por enquanto. **Google:** sem token, fica como está. **Conta centralizadora do
  Infra:** já decidida (ver Perguntas, item 6).
- **Acesso:** sem mudança (admin/dev). Permissão para gestores e Arthur: pendente do novo modelo de acesso.

**Como testar:**

1. Banco: com a 20261006g e a 20261006i aplicadas (ou na mesma transação), rodar `20261006j_ensaio.sql` inteiro (termina
   em rollback) e conferir que nenhuma linha começa com `ERRADO`. Medido em Postgres local (PGlite): 69 `ok`.
2. Tela: `NEXT_PUBLIC_TRAFEGO_DEMO=1` em `web/.env.local`, `npm run dev`, `/marketing/trafego`. Projeto fictício
   **LPEXA26 "Lançamento Pago Exemplo"** (CSM, lançamento pago, captação e evento, conta Exemplo, item do SendFlow marcado
   por "Pessoa Exemplo", campanha sugerida, alerta de conta de fora), DEXA26 (Diamantes, lançamento clássico, "Especialista
   Exemplo", receita "não se aplica"), AEXA26 (Aurum, palestra). Botão "Novo projeto", aba "Modelos de lançamento".
3. Código: `npx vitest run` (`domain/cadastro.test.ts`, `alertas.test.ts`, `infrastructure/demo.test.ts`,
   `ui/montagem.test.ts`, `coleta.test.ts`), `npx tsc --noEmit`, `npm run build`.

### Modelos de lançamento (migration 20261006l, NÃO APLICADA)

`infra/supabase/migrations/20261006l_mkt_trafego_modelos.sql` + `_ensaio.sql` + `20261006l.explain.md`. Depende da
20261006j. Pedido do Victor (06/10/2026): substitui o "pacote" e organiza o checklist.

- **Modelo** (`mkt_trafego.modelos`): nome livre (ex.: "LPSG padrão CSM"), tipo de lançamento, **unidades** (uma ou mais,
  só nas combinações que valem: o banco recusa), ativo/inativo, **rascunho**, e um **padrão** por tipo + unidade. Vários
  modelos por tipo; sempre editável; **duplicar**.
- **Dentro do modelo:** **fases** (da lista, ordem, início e fim relativos às datas do projeto: "7 dias antes do início
  da captação", "no fim da captação", "2 dias antes do início do evento"; % da verba máxima), **campanhas esperadas**
  (objetivo, fase, descrição sugerida, página opcional), **checklist manual** (texto e momento: antes de subir as
  campanhas, durante, encerramento) e **metas padrão** opcionais, só as que a Central mede por meta: CPL e % MQL.
- **Mockups:** um "Exemplo: &lt;tipo&gt; &lt;unidade&gt;" por combinação (9), rascunho a validar e padrão. Fases da lista
  que já existe, **datas e percentuais genéricos de exemplo (não são decisão de ninguém)**; uma campanha esperada por
  fase pelo mapa objetivo → fase (captação no pago e no LPSG = VENDAS); o item do SendFlow nos modelos com captação.
  Tabela dos números em `20261006l.explain.md`.
- **No projeto, "Aplicar modelo"** (cadastro do projeto e item do checklist): lista os modelos ativos do tipo de
  lançamento e da unidade do projeto (padrão primeiro), mostra a **prévia** (fases com datas calculadas e verba = % ×
  verba máxima, o que é novo, o que mudaria e o que fica igual; campanhas esperadas; itens; metas) e aplica: cria o que
  falta; **fase que já existe só muda marcando "substituir" e confirmando**; meta só onde o projeto não tem (ou
  confirmando). **Nunca apaga nada.** Fica guardado qual modelo foi aplicado.
- **Checklist que leva à ação:** agrupado por momento; cada item automático pendente tem o link para onde se resolve
  (editar projeto, planejamento, fases, páginas, Hotmart, aplicar modelo, gerador, campanhas). Itens novos: "modelo
  aplicado", "campanhas esperadas criadas" (compara por objetivo e página as esperadas com as campanhas do projeto) e,
  no encerramento, "status encerrado depois do fim do evento". Item manual pode ser criado só para o projeto, marcado
  (quem e quando) e tirado.
- **Gerador de nome:** mostra as campanhas esperadas do modelo; um clique preenche objetivo, descrição e página.
- **Resumo do dia:** regra nova `checklist_incompleto` (média, limiar 0 dias): projeto em captação com item de "antes de
  subir as campanhas" pendente.
- **Sai:** `pacote_modelos`, `checklist_itens`, `checklist_marcas` e as funções do pacote e do checklist manual global
  (20261006j, nunca aplicada, sem dado).

**Como testar:** banco, `20261006l_ensaio.sql` depois da 20261006j (nenhuma `ERRADO`); tela, modo demo: aba "Modelos de
lançamento" (9 exemplos), LPEXA26 já com o "Exemplo: Lançamento pago CSM" aplicado (fases, esperadas, SendFlow marcado,
alerta de checklist incompleto em captação); código, `domain/modelos.test.ts`, `cadastro.test.ts`, `demo.test.ts`,
`ui/montagem.test.ts`.

**Perguntas (para o Victor):** os números dos exemplos (fases, datas e % por tipo) e quais modelos têm captação em grupo
(hoje o SendFlow vai em todos com captação); metas padrão por modelo; mais itens manuais por tipo de lançamento.

### Contas de anúncio do Meta (migration 20261006k, NÃO APLICADA)

`infra/supabase/migrations/20261006k_mkt_trafego_contas_meta.sql` + `_ensaio.sql` + `20261006k.explain.md` (a tabela das
16 contas está lá). Depende da 20261006j. O token do Meta (Vault `meta_ads_token`, usuário do sistema do portfólio Grupo
Participa) **já está salvo em produção** e enxerga 16 contas (`/me/adaccounts`, lidas em 06/10/2026). A migration as
cadastra de forma idempotente (por plataforma e id): nome exato, id sem `act_`, Meta, BRL, internas (dono grupo), com
**unidade** e **principal** (colunas novas em `mkt_trafego.contas`).

- **Regra do Victor (06/10/2026):** Escritório = contas com "Seminário" ou "Aurum" no nome (5); CSM = Marcio, Holding
  Total, CNF, Imersões, THB, Treinamento (10).
- **Principais** (aparecem primeiro na seleção; todas continuam selecionáveis): 1º Holding Total 2.0, CNF Holding Familiar,
  THB - Ads, Treinamento Participa, Seminários - Leads. "1º Holding Total 2.0" confirmada pelo Victor (06/10/2026).
- **CA - Tutorial:** CSM por enquanto, mas **não vai ser usada** (Victor, 06/10/2026): cadastrada **inativa**, fora da
  seleção do projeto e da coleta (`mkt_trafego.meta_contas` só lê ativas); dá para reativar em Contas de anúncio.
- **Tela:** Contas de anúncio mostra unidade e "principal" e permite mudar (unidade precisa combinar com o dono: Grupo =
  CSM ou Escritório); no cadastro do projeto as principais vêm primeiro (★).
- **A coleta continua DESLIGADA** (nenhum cron). Ligar: bloco LIGAR da 20261006i, depois de aplicar p, r, 20261006j e
  20261006k.

### Perguntas (respondidas pelo Victor em 05/10/2026, salvo as em aberto)

1. ~~Status~~ **Respondido:** ativo, pausado, inativo, encerrado; **em planejamento** acrescentado em 06/10/2026 (fora do
   resumo do dia).
2. ~~Connect rate e conversão~~ **Respondido:** connect rate = page views ÷ cliques no link; conversão da página = leads
   ÷ page views. Ligado à mesma page view da Web fase 2 (ver Decisões). **Confirmado pelo Victor (05/10):** page view =
   uma entrada por visita, como o Meta conta; o lead da conversão é o da Web (visitas da campanha que viraram lead), e o
   lead da base fica na coluna de leads, no CPL e no % MQL.
3. ~~Cliques~~ **Respondido:** cliques no link para CTR e CPC; totais guardados à parte.
4. ~~Fase da campanha~~ **Respondido:** pelo objetivo do nome, com correção à mão prevalecendo; mapa e objetivos novos
   (CARRINHO, AQUECIMENTO) nas Decisões. DISTRIBUIÇÃO sem fase automática.
5. ~~Externos (Aurum, Diamantes)~~ **Estrutura decidida (06/10/2026):** cada um é projeto em `mkt.projetos`, tipo externo,
   unidade Aurum ou Diamantes. A sigla de campanha segue em aberto (pergunta b abaixo).
6. ~~Conta centralizadora~~ **Decidido (Victor, 06/10/2026):** uma conta centralizadora **do Infra**, com acesso às contas de anúncio internas e externas ligadas a ela, gera o token de API que a coleta usa. Recomendação: token de **usuário do sistema** no Business Manager do Grupo (não expira e não depende de uma pessoa), com permissão `ads_read`. Conta nova não pede token novo: basta atribuí-la ao usuário do sistema e cadastrá-la em Contas de anúncio.
7. ~~Gestor do projeto~~ **Respondido:** vários gestores por projeto (`projeto_gestores`).

**Fase 2 (em aberto):**

8. ~~Token do Meta~~ **Decidido (06/10):** conta centralizadora, um `meta_ads_token` no Vault. Falta gerar e cadastrar.
9. **Token do ClickUp:** de qual usuário (ele só lê o que esse usuário enxerga)? E qual o id do workspace?
10. ~~Limiares do resumo do dia~~ **Confirmados (06/10/2026)** verba diária, CPL, ritmo e 90 %; leads abaixo da meta e
    fora do padrão/sem fase ficam ligados (o Victor não comentou esses dois). Texto original: os iniciais eram proposta minha (0 % verba diária, 0 % CPL, 20 % leads e ritmo da
    fase, 90 % da verba, 7 dias para fora do padrão e sem fase). Servem? Inativo e encerrado fora do resumo, ok?
11. **Receita bruta ou líquida?** Hoje soma `public.compras.preco` (o valor da compra que a Hotmart manda no webhook,
    antes da taxa). O financeiro tem o líquido em `fin.hotmart_transacoes`.
12. **Reembolso e chargeback:** a Hotmart troca o status da própria compra, então ela sai da receita (inclusive de dias
    passados: a receita de um projeto encerrado pode cair depois). É isso que você quer, ou a receita deve ficar como no
    dia da venda e o reembolso aparecer à parte?
13. **Compra em outra moeda:** fica fora da soma (contada à parte). Ok?
14. **Período da receita:** o do projeto (`mkt.projetos` início e fim) ou o de cada produto? Hoje vale o do vínculo se
    preenchido, senão o do projeto. Os projetos da semente estão sem datas: sem data, o vínculo não soma.
15. ~~Leads da plataforma no Meta~~ **Decidido (06/10/2026):** fica a ação `lead` por enquanto (provavelmente muda depois).

**Cadastro do projeto (20261006j, em aberto):**

- a) **Projeto só de distribuição de conteúdo** (contínuo, sem fim, métricas separadas): ideia a definir. Como modelar
  (tipo de projeto próprio? sem período?) e quais métricas.
- b) **Sigla do projeto externo** no nome da campanha (Aurum, Diamantes): qual padrão?
- c) ~~Receita dos externos~~ **Decidido (06/10/2026):** não entra por ora.
- d) ~~Conteúdo do pacote~~ **Virou modelos de lançamento (20261006l):** os 9 exemplos são rascunho a validar (fases,
  datas e % genéricos).
- e) **Acesso:** gestores e Arthur editam verba, fases e metas, depende do novo modelo de acesso do sistema (pendente).
- f) ~~LPSG no Escritório~~ **Decidido (06/10/2026):** LPSG é só da CSM; o Escritório fica com lançamento clássico e ATM.
  (ATM vale nas duas unidades internas.)
- g) **Unidade dos projetos que já existem:** PB26, HT33 e BF26 são CSM ou Escritório? SEMSET26 é interno ou externo?
  (ficaram sem unidade/tipo; marcar na tela).
- h) **Itens manuais do checklist** além do SendFlow, e para quais modelos (agora ficam no modelo, com o momento).
- i) ~~Período padrão da receita~~ **Respondido, provisório (06/10/2026):** do início da captação ao fim do evento. A
  confirmar depois pelo Victor (trocar em `mkt_trafego.periodo_receita` e `periodoReceita`).
- j) **Etiquetas do ClickUp:** ler as de todos os spaces do workspace (hoje) ou de um space só?
- k) **Especialistas internos:** além de Marcio Carvalho de Sá e Elaine Montenegro, quem mais (entra por SQL)?
- l) **ANTECIPAÇÃO entra na lista de objetivos? Em qual fase?** (exemplo `CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ |
  ABO | THRUPLAY`). Hoje fica fora do padrão só por isso; ligar = os comandos comentados na 20261006e.

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
- **05/10/2026:** Marketing > Web (o Radar do Luiz, sem vídeo): migration 20261006f (NÃO APLICADA) com a coleta em
  `mkt_web`, rota pública `/api/web/coletar` com limite por IP e por sessão, gravador `/web/radar-v1.js`, telas em
  `/marketing/web`, modo de demonstração local e seed de dev. Virada documentada, não feita. Branch `victor`.
- **05/10/2026:** Comercial e base de pessoas: migration 20261005o (NÃO APLICADA) com os schemas `pessoas` (uma pessoa
  por identidade, cascata da casa, aluno e comprador por referência, origem, eventos, revisão, registro de acesso,
  máscara no SQL) e `crm` (4 pipelines, etapas configuráveis, negócios, histórico); telas em `/comercial` (só admin e
  dev) com modo de demonstração local. Perguntas abertas na seção "Comercial e base de pessoas". Branch `victor`.
- **05/10/2026:** Tráfego etapa 1 (migration 20261006g, NÃO APLICADA): contas, campanhas, desempenho diário, planejamento
  (status, verba, fases, metas) e a Central do Tráfego em `/marketing/trafego` (área ativa), com modo demo. Branch `victor`.
- **05/10/2026:** Tráfego, respostas do Victor na própria 20261006g (ainda NÃO APLICADA): cliques no link separados dos
  totais (CTR, CPC), connect rate e conversão da página com a mesma page view da Web fase 2 (`mkt_web_connect`), vários
  gestores por projeto,
  fase da campanha pelo objetivo do nome (com correção à mão), fases remarketing e abertura de carrinho, objetivos
  CARRINHO e AQUECIMENTO no padrão de nome.
- **05/10/2026:** Tráfego fase 2 (migration 20261006i, NÃO APLICADA): resumo do dia com limiares em tabela, receita da
  Hotmart pelo vínculo produto → projeto (cadastro à mão), atividades do ClickUp com linha do tempo do gasto, Edges
  `trafego-meta` e `trafego-clickup` testadas com respostas simuladas e **desligadas**, esqueleto do Google Ads. Branch `victor`.
- **06/10/2026:** UTM no padrão oficial do gp-operacoes (`nome|id` para campanha, conjunto e anúncio no Meta; Google só
  id), confirmado pelo Victor. Leitura única `mkt.utm_separar` / `mkt_web.origem_ids` (20261006f) e `separarUtm`
  (`projetos/domain/utm.ts`); aba Origem, achados por criativo, `mkt_web_connect` (20261006h) e resumo do Tráfego
  (20261006g) cruzam pelo id, nome só como reserva; formato antigo continua valendo. Seção "Padrões de nome de campanha e
  UTM" nesta doc. Migrations editadas no lugar (todas ainda NÃO APLICADAS). Branch `victor`.
- **06/10/2026:** Tráfego, cadastro do projeto (migration 20261006j, NÃO APLICADA): tipo interno/externo e unidade (CSM,
  Escritório, Aurum, Diamantes) no lugar da subárea, tipos de lançamento por unidade com a regra no banco (lançamento
  pago só na CSM; Aurum palestra fixo; ATM; perpétuo fora), especialista, períodos de captação e do evento (captação como
  padrão da receita e da fase de captação; `periodo_padrao` acrescentada na 20261006i, ainda não aplicada), contas de
  anúncio do projeto (sugestões e alerta de conta de fora), etiqueta do ClickUp como chave (com as etiquetas reais dos
  spaces pela rotina), pacote da campanha (vazio), checklist de montagem e gerador de nome de campanha e UTM. Receita dos
  externos fora. Tela na Central do Tráfego, modo demo. Branch `victor`.
- **06/10/2026:** Tráfego, respostas do Victor na própria 20261006j (ainda NÃO APLICADA): LPSG só na CSM (Escritório com
  clássico e ATM, recusado também no banco); receita sem período próprio do produto do início da captação ao fim do evento
  (provisório, a confirmar; regra só em `mkt_trafego.periodo_receita`, acrescentada na 20261006i, e `periodoReceita`).
- **06/10/2026:** Tráfego, contas do Meta (migration 20261006k, NÃO APLICADA): as 16 contas que o token do sistema enxerga,
  com unidade (CSM 11, Escritório 5) e principal (5), CA - Tutorial inativa; unidade e principal na tela de contas e na
  seleção do projeto. Coleta continua desligada. Branch `victor`.
- **06/10/2026:** revisão do Victor no Tráfego: nome de campanha com descrição de várias partes e página só no último
  campo com formato de slug (migration **20261006e**, NÃO APLICADA, troca só o corpo de `mkt.campanha_traduzir` com as
  mesmas chaves de retorno), motivo exato de cada campanha fora do padrão na tela, campo "Linha" fora do cadastro, status
  "em planejamento" (fora do resumo do dia), etiqueta do ClickUp com busca (`trafego_clickup_etiquetas_buscar`, fonte
  `kpi.medicao_tarefa`). ANTECIPAÇÃO ficou como pergunta. 20261006g, 20261006i e 20261006j editadas no lugar (não
  aplicadas). Branch `victor`.
- **06/10/2026:** Tráfego, modelos de lançamento (migration **20261006l**, NÃO APLICADA): no lugar do pacote; modelo com
  unidades e padrão, fases com datas relativas e % da verba, campanhas esperadas, checklist por momento e metas padrão;
  9 exemplos rascunho; "Aplicar modelo" com prévia no projeto (nada apagado; fase existente só confirmando); checklist
  com o caminho para resolver, "campanhas esperadas criadas" e alerta de checklist incompleto em captação. Branch `victor`.
