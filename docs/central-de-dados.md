# Central de dados: departamentos e áreas

> Decisão do Victor Hugo (05/10/2026), com o João Pedro ciente. O sistema deixa de ser só a Central de Alunos e
> vira a central da empresa: ao entrar, a pessoa vê os **departamentos**; dentro deles, as **áreas**.
> Mapeamento e proposta de origem: `Projetos/sistema-unico/central-de-dados/modularizacao-educacional.md` no
> cérebro do Victor.

## Estrutura

| Departamento | Rota | Situação | Dentro |
|---|---|---|---|
| Educacional | `/educacional` | ativo | tudo o que existia no sistema até 05/10/2026 (sem áreas) |
| Marketing | `/marketing` | ativo, **só admin e dev** | área **Web ativa** (ver "Web"); Mensageria, Tráfego, Audiovisual, Social Media "Em breve" |
| Comercial | `/comercial` | Em breve | sem áreas |
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

Sem visita no período, cada aba diz **"Sem dados ainda: a coleta começa na virada."** Regras de análise portadas do
Radar em `domain/analise.ts` (teste de duas proporções, maior perda do funil, apelido de seção, origem, régua do Google).

### Testar localmente (antes da virada)

- **Telas com números (sem banco):** em `web/.env.local` pôr `NEXT_PUBLIC_WEB_DEMO=1`, rodar `npm run dev` em `web/`,
  abrir `http://localhost:3000/marketing/web` e entrar com o login de sempre (admin/dev). Aparece a faixa **"Dados de
  demonstração"**: os números são inventados (`web/modules/marketing/web/infrastructure/demo.ts`). Só liga em `next dev`:
  com `NODE_ENV=production` (o servidor) nunca liga, mesmo com a variável. Tirar a linha do `.env.local` volta ao banco.
- **Banco local com as migrations:** `infra/scripts/mkt_web_seed_dev.sql` põe 4.200 visitas inventadas do PB26 (ids
  `dev…`). Trava: só roda depois de `select set_config('app.mkt_web_seed', 'sou-banco-de-dev', false);` e aborta se já
  houver coleta de verdade. **Nunca rodar em produção.** O bloco LIMPAR no fim apaga só o que é `dev`.
- Testes: `npx vitest run modules/marketing/web` (regras, rota, telas renderizando, estado vazio) e
  `shared/infrastructure/supabase/proxy-dominio.test.ts` (a coleta fica fora do Proxy).

### Virada (trocar o gravador do PB para o nosso). NÃO feita; fazer fora da semana do evento (09 a 11/11)

O FTP das páginas do PB é do Luiz (publicação pelo `scripts/deploy.py` dele). Passo a passo, com data combinada com ele:

1. **Aplicar a 20261005n** em produção: rodar antes o `20261005n_ensaio.sql` e conferir os esperados; depois a
   migration. Conferir `select jobname, schedule from cron.job where jobname like 'mkt-web-%'` (3 rotinas).
2. **Publicar** a branch (merge na `main`). Conferir `https://grupoparticipa.app.br/web/radar-v1.js` (200, JavaScript)
   e que `POST /api/web/coletar` sem origem responde `dominio` (403).
3. **Cadastrar as páginas** do PB26 que faltam em Marketing > Projetos e páginas (hoje só `/ak1/`, `/obrigado/`,
   `/quase-la/`, `/pesquisa/`). O `patrimonio-brasil.json` do Luiz lista 11: `/`, `/ak1/`, `/bl2/`,
   `/bl2-otimizacao/`, `/quase-la/`, `/pesquisa/`, `/obrigado/`, `/inscricao-recebida/`, `/profissionais/`,
   `/profissionais/advogados/`, `/profissionais/contadores/`. Caminho não cadastrado é gravado mesmo assim (sem página),
   mas o domínio precisa de ao menos uma página ativa.
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

Gravação/replay das visitas (vídeo), mapa de calor desenhado sobre a página (hoje: elementos mais clicados), Melhorias
(achados automáticos, testes A/B, comparar), Diário com IA, PageSpeed de laboratório, publicações/deploys, CRM do Luiz
e a referência ao lead (`visitantes.lead_ref`, quando a base de pessoas existir), Fluxo e Pesquisas, Meta/Google/Hotmart e
reenvio ao ActiveCampaign, connect rate com o Tráfego, ferramentas da Web no MCP, a área `mkt_web` para o Luiz e o
Iromar (entra em `mkt.pode_ver`), importação do histórico do Radar.

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
