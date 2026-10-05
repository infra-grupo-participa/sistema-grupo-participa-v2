# Web (o Radar na central): guia para quem chega

> Para o **Luiz Fernando** e quem mais for mexer na área Web. Escrito em 05/10/2026 pelo Victor (com o Claude).
> Este arquivo é o ponto de partida: diz o que já foi feito, o que foi decidido e o que falta. O detalhe técnico
> completo (coleta, telas, testes, passo a passo da virada) está em
> [`central-de-dados.md`, seção "Web"](central-de-dados.md#web-marketing--web-o-radar-dentro-da-central).

## 1. Em uma frase

O Radar passou a ser do Grupo e está sendo refeito **dentro deste sistema** (Marketing > Web), no **Supabase do
Grupo**, com as mesmas regras de análise. Nada aqui conecta no Supabase, no domínio ou na hospedagem pessoais do Luiz.

## 2. Onde está cada coisa

| O quê | Onde |
|---|---|
| Código das telas e da coleta | `web/modules/marketing/web/` (`domain`, `application`, `infrastructure`, `ui`) |
| Rota que recebe os pacotes | `web/app/api/web/coletar/route.ts` |
| Gravador (adaptado do `radar-051026-0007.js`, sem vídeo) | `web/public/web/radar-v1.js` |
| Banco (schema `mkt_web`, 14 tabelas) | `infra/supabase/migrations/20261005n_mkt_web_coleta.sql` + `_ensaio.sql` + `.explain.md` |
| Base compartilhada (projetos, páginas, padrão de nome de campanha) | `infra/supabase/migrations/20261005m_*` (**já aplicada em produção**) |
| Base única de pessoas (lead) e CRM do Comercial | `infra/supabase/migrations/20261005o_*` e `web/modules/comercial/` |
| Dados inventados para testar sem banco | `web/modules/marketing/web/infrastructure/demo.ts` e `infra/scripts/mkt_web_seed_dev.sql` |

## 3. Situação em 05/10/2026

| Peça | Situação |
|---|---|
| Base compartilhada (`mkt.projetos`, `mkt.paginas`, tradutor do nome de campanha) | **No ar** (migration 20261005m aplicada, tela Marketing > Projetos) |
| Coleta + 9 abas da Web | **Pronta na branch `victor`, não publicada.** Migration 20261005n **não aplicada** (ensaio rodado em produção com rollback: 113 linhas, 0 erro) |
| Gravador nas páginas do PB | **Ainda é o do Luiz.** A troca ("virada") não foi feita |
| Base de pessoas e CRM do Comercial | Pronta na branch `victor`, **não aplicada**. Já grava a referência do lead em `mkt_web.visitantes.lead_ref` |
| Publicação | Só depois de o Victor ver as telas. **Nada vai para a `main` sem ok do Victor** |

## 4. Decisões já tomadas (não reabrir sem falar com o Victor)

| Tema | Decisão |
|---|---|
| Dono | O Radar passa a fazer parte da central de dados do Grupo |
| Projeto | **Projeto = edição** (`PB26`, `HT33`, `SEMSET26`, `BF26`), a mesma sigla do nome de campanha. Uma tabela de projetos só (`mkt.projetos`), compartilhada por Web, Tráfego e Mensageria |
| Lead | Mora na **base única de pessoas**. A Web **não guarda dado pessoal**, só a referência opaca do lead |
| CRM do Radar (nome, e-mail, telefone) | **Não migra na primeira fase** (LGPD) |
| Gravação de visita (replay) | **Fica para uma segunda fase** (dado mais pesado e mais sensível) |
| Quem vê a Web | Por ora só admin e dev. Depois, a área `mkt_web` para o Luiz e o Iromar |
| `utm_content` | **= id do anúncio.** A página vai no nome da campanha (campo 5 do padrão) |
| Padrão de nome de campanha | `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA(opcional)`, ex.: `RS \| PB26 \| LEADS \| TESTE DE ESCRITÓRIOS \| AK1` |
| FTP das páginas do PB | É do Luiz; o do Grupo vem depois. A virada usa o dele por ora |
| Data da virada | **Fora da semana do PB26 (09 a 11/11/2026)** |

## 5. Como trabalhar neste repositório

- **Uma branch por pessoa.** A do Luiz é `luis-fernando`. Ninguém produz direto na `main`.
- O código da Web está na branch `victor` (ainda não está na `main`). Para começar, a `luis-fernando` precisa receber
  a `victor` (merge); combinar com o Victor antes.
- `git pull` antes de mexer e antes de subir: outras pessoas trabalham no mesmo repo.
- **Banco:** só existe produção. Migration nova segue o padrão das 20261005m/n/o (tabelas fechadas, funções
  `SECURITY DEFINER` com `search_path ''`, arquivo `_ensaio.sql` que termina em rollback, `.explain.md`). Quem aplica é
  o Victor ou o João.
- Antes de pedir revisão: `npx tsc --noEmit`, `npx vitest run`, `npm run build` em `web/`.
- **Documentar o que fizer** neste arquivo (seção 7) e na seção "Web" de `central-de-dados.md`, no mesmo commit do
  código.
- Nunca commitar chave, token ou senha. Dado pessoal (CRM) não entra no git.

## 6. O que falta (em ordem)

1. **Virada**, com data combinada com o Luiz: passo a passo completo em
   [`central-de-dados.md`, "Virada"](central-de-dados.md). Resumo: aplicar a 20261005n, publicar, cadastrar as 11
   páginas do PB26, ligar a coleta, rodar um dia em paralelo numa página, trocar a linha do gravador nas páginas.
2. **Importar o histórico do banco do Luiz** (feito pelo Luiz, na branch dele, revisado por Victor/João):
   - não migrar: vídeo, `pacotes`, `recusas`, `falhas`, `tempos_api`, `chaves*`, `membros`, `config` e Vault;
   - migrar: `visitantes`, `sessoes`, `visualizacoes`, `eventos_funil`, `erros`, `cliques` (90 dias), `paginas_mapa`,
     `publicacoes`, `velocidade_lab`, `achados*`, `testes`, `apelidos`, exportando só os dados e conferindo as
     contagens antes e depois;
   - CRM: só depois da revisão LGPD, por canal seguro, fora do git.
3. **Depois da virada:** desligar o Supabase e o domínio pessoais do Luiz.
4. **Segunda fase** (ainda sem data): gravação/replay, mapa de calor sobre a página, Melhorias (achados, testes A/B),
   Diário com IA, PageSpeed de laboratório, publicações, Fluxo e Pesquisas, reenvio ao ActiveCampaign, connect rate com
   o Tráfego, ferramentas da Web no MCP da central, área `mkt_web` para o Luiz e o Iromar.

## 7. Perguntas para o Luiz (abertas em 05/10/2026)

1. Quanto ocupa o banco do Radar hoje (MB) e quantas linhas têm as tabelas grandes (`sessoes`, `visualizacoes`,
   `cliques`, `crm.pessoas`)?
2. O `radar-active-fila` está ativo? Há rotina fora das listadas na PASSAGEM?
3. Quais páginas estão com qual gravador (011026-0251 ou 051026-0007)? A 3.15 foi publicada?
4. A FTP do PB (`PB_FTP_*`) e a do `api/crm.php` são contas do Grupo ou suas?
5. O que vai no `utm_campaign` dos anúncios do Meta: nome ou id da campanha?
6. O que do CRM você considera indispensável levar?
7. Prefere adaptar você as migrações do Radar para o schema `mkt_web` ou que a gente faça?
8. Quem mais tem login no Radar hoje?
9. A licença do rrweb e das fontes (Metropolis) permite uso no sistema do Grupo?
10. As páginas do PB têm Content-Security-Policy? (se sim, liberar `grupoparticipa.app.br` na virada)

## 8. Registro do que foi feito

| Data | Quem | O quê |
|---|---|---|
| 05/10/2026 | Victor + Claude | Estudo do pacote do Radar; base compartilhada aplicada (20261005m); coleta e 9 abas na branch `victor` (20261005n, não aplicada); este guia |
