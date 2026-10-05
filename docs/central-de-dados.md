# Central de dados: departamentos e áreas

> Decisão do Victor Hugo (05/10/2026), com o João Pedro ciente. O sistema deixa de ser só a Central de Alunos e
> vira a central da empresa: ao entrar, a pessoa vê os **departamentos**; dentro deles, as **áreas**.
> Mapeamento e proposta de origem: `Projetos/sistema-unico/central-de-dados/modularizacao-educacional.md` no
> cérebro do Victor.

## Estrutura

| Departamento | Rota | Situação | Dentro |
|---|---|---|---|
| Educacional | `/educacional` | ativo | tudo o que existia no sistema até 05/10/2026 (sem áreas) |
| Marketing | `/marketing` | ativo, **só admin e dev** | áreas Web, Mensageria, Tráfego, Audiovisual, Social Media (todas "Em breve") |
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
| Web | schema `mkt_web` | **Vazio.** Na fase 2 recebe a coleta do Radar (visitantes, sessões, visualizações, eventos do funil, erros, cliques, velocidade, publicações, operação e `funis`), tudo apontando para `mkt.projetos`/`mkt.paginas`, sem dado pessoal |
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
