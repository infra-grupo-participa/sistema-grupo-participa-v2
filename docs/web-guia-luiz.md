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
| Banco (schema `mkt_web`, 14 tabelas) | `infra/supabase/migrations/20261006f_mkt_web_coleta.sql` + `_ensaio.sql` + `.explain.md` |
| Fase 2 (Fluxo, mapa de calor, Melhorias, teste do Google, lead ligado à pessoa, connect rate) | `infra/supabase/migrations/20261006h_mkt_web_fase2.sql` + `_ensaio.sql` + `.explain.md` e `infra/supabase/functions/mkt-web-pagespeed/` |
| Regras de achados e testes A/B (porte do `oportunidades.ts` e do `testes.ts` do Radar) | `web/modules/marketing/web/domain/achados.ts` e `testes-ab.ts` |
| Base compartilhada (projetos, páginas, padrão de nome de campanha) | `infra/supabase/migrations/20261005m_*` (**já aplicada em produção**) |
| Base única de pessoas (lead) e CRM do Comercial (do Arthur) | `infra/supabase/migrations/20261005r_pessoas_e_crm_fundacao.sql` e seguintes, `web/modules/comercial/` e `docs/projetos/comercial/` |
| Dados inventados para testar sem banco | `web/modules/marketing/web/infrastructure/demo.ts` e `infra/scripts/mkt_web_seed_dev.sql` |

## 3. Situação em 05/10/2026

| Peça | Situação |
|---|---|
| Base compartilhada (`mkt.projetos`, `mkt.paginas`, tradutor do nome de campanha) | **No ar** (migration 20261005m aplicada, tela Marketing > Projetos) |
| Coleta + 9 abas da Web | **Pronta na branch `victor`, não publicada.** Migration 20261006f **não aplicada** (ensaio rodado em produção com rollback: 113 linhas, 0 erro) |
| Gravador nas páginas do PB | **Ainda é o do Luiz.** A troca ("virada") não foi feita |
| Base de pessoas e CRM do Comercial (do Arthur) | **No ar** (20261005r_pessoas_e_crm_fundacao e seguintes, aplicadas). `pessoas.registrar` grava a referência do lead em `mkt_web.visitantes.lead_ref` quando o formulário manda o `visitante`; só passa a gravar depois que a 20261006f criar a tabela |
| Fase 2 da Web (Fluxo, mapa de calor sobre a página, Melhorias, teste do Google, leads na base de pessoas, connect rate, páginas do PB26) | **Pronta na branch `victor`, não aplicada** (migration 20261006h, depende da 20261006f; ensaio local sem erro). O gravador não mudou |
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
| UTM (`utm_content` e demais) | **`utm_content` = o anúncio (criativo) no formato `nome\|id`, padrão oficial do gp-operacoes; o sistema cruza pelo id.** No Meta, `utm_source=metaads`, `utm_campaign` = campanha `nome\|id`, `utm_medium` = conjunto `nome\|id`, `utm_term` = posicionamento; no Google só id. Fonte: gp-operacoes, `departamentos/dados/areas/infraestrutura/processos/padronizar-utm-dos-links.md` (Victor, 06/10/2026); resumo em `docs/central-de-dados.md`, "Padrões de nome de campanha e UTM". A página vai no nome da campanha (campo 5 do padrão) |
| Padrão de nome de campanha | `GESTOR \| PROJETO \| OBJETIVO \| DESCRIÇÃO \| PÁGINA(opcional)`, ex.: `RS \| PB26 \| LEADS \| TESTE DE ESCRITÓRIOS \| AK1` |
| FTP das páginas do PB | É do Luiz; o do Grupo vem depois. A virada usa o dele por ora |
| Data da virada | **Fora da semana do PB26 (09 a 11/11/2026)** |
| Page view no connect rate | **Uma entrada na página por visita vinda da campanha**, como o Meta conta (Victor, 05/10). Connect rate = page views ÷ cliques no link; conversão = leads ÷ page views. Mesma regra na Web e no Tráfego |

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
   [`central-de-dados.md`, "Virada"](central-de-dados.md). Resumo: aplicar a 20261006f, aplicar a 20261006h (já cadastra
   as 11 páginas do PB26; antes, publicar a Edge `mkt-web-pagespeed`), publicar, ligar a coleta, rodar um dia em
   paralelo numa página, trocar a linha do gravador nas páginas.
2. **Importar o histórico do banco do Luiz** (feito pelo Luiz, na branch dele, revisado por Victor/João):
   - não migrar: vídeo, `pacotes`, `recusas`, `falhas`, `tempos_api`, `chaves*`, `membros`, `config` e Vault;
   - migrar: `visitantes`, `sessoes`, `visualizacoes`, `eventos_funil`, `erros`, `cliques` (90 dias), `paginas_mapa`,
     `publicacoes`, `velocidade_lab`, `achados*`, `testes`, `apelidos`, exportando só os dados e conferindo as
     contagens antes e depois;
   - CRM: só depois da revisão LGPD, por canal seguro, fora do git.
3. **Depois da virada:** desligar o Supabase e o domínio pessoais do Luiz.
4. **Segunda fase, o que ainda falta** (o resto da segunda fase está na 20261006h, não aplicada): gravação/replay,
   Diário com IA, publicações (e o achado "antes e depois da publicação"), Pesquisas, reenvio ao ActiveCampaign, o
   servidor MCP da central (as ferramentas da Web estão descritas em `central-de-dados.md`), área `mkt_web` para o Luiz
   e o Iromar, teste A/B cadastrado (início, fim, hipótese, trava) e clique no link por anúncio (depende do Tráfego).
5. **Tarefa do Luiz: chave do PageSpeed.** Decisão do Victor (05/10): o sistema fica sem chave por ora e o Luiz
   cadastra. Criar uma chave da API PageSpeed Insights num projeto Google do Grupo e gravar no Vault do Supabase com o
   nome `mkt_web_pagespeed_api_key` (nunca no código nem no git). Sem ela, a rotina usa a cota pública e o Google pode
   recusar parte dos pedidos (a falha aparece na aba Velocidade).
6. **Conferir depois da virada:** o tempo de `mkt_web_melhorias` com 30 dias de dado; se as páginas do PB aceitam ser
   abertas num quadro (fundo "página ao vivo" do mapa de calor).
7. **UTM longo no gravador v1:** o `radar-v1.js` corta cada UTM em 120 caracteres (comportamento mantido de propósito).
   No formato `nome|id` o id fica no FIM; nome de campanha muito longo perde o id no corte e a visita cai na reserva
   pelo nome. Ao fazer o `radar-v2.js`, guardar o fim do texto (ou subir o limite para 300, como o servidor já aceita).

## 7. Perguntas para o Luiz (abertas em 05/10/2026)

1. Quanto ocupa o banco do Radar hoje (MB) e quantas linhas têm as tabelas grandes (`sessoes`, `visualizacoes`,
   `cliques`, `crm.pessoas`)?
2. O `radar-active-fila` está ativo? Há rotina fora das listadas na PASSAGEM?
3. Quais páginas estão com qual gravador (011026-0251 ou 051026-0007)? A 3.15 foi publicada?
4. A FTP do PB (`PB_FTP_*`) e a do `api/crm.php` são contas do Grupo ou suas?
5. ~~O que vai no `utm_campaign` dos anúncios do Meta: nome ou id da campanha?~~ Respondida pelo Victor em 06/10/2026:
   `nome|id` (padrão do gp-operacoes; ver a seção 4).
6. O que do CRM você considera indispensável levar?
7. Prefere adaptar você as migrações do Radar para o schema `mkt_web` ou que a gente faça?
8. Quem mais tem login no Radar hoje?
9. A licença do rrweb e das fontes (Metropolis) permite uso no sistema do Grupo?
10. As páginas do PB têm Content-Security-Policy? (se sim, liberar `grupoparticipa.app.br` na virada)
11. A `/bl2-otimizacao/` é variação de teste da BL2? Se for, renomear o código para o padrão da casa (`bl2-b`) faz o
    teste A/B aparecer sozinho em Melhorias; hoje ela fica sem código.
12. As páginas do PB mandam `X-Frame-Options` ou `frame-ancestors`? (o fundo "página ao vivo" do mapa de calor depende disso)

## 8. Registro do que foi feito

| Data | Quem | O quê |
|---|---|---|
| 05/10/2026 | Victor + Claude | Estudo do pacote do Radar; base compartilhada aplicada (20261005m); coleta e 9 abas na branch `victor` (20261006f, não aplicada); este guia |
| 05/10/2026 | Victor + Claude | Fase 2 na branch `victor` (20261006h, não aplicada): abas Fluxo, Mapa de calor (sobre a captura do Google) e Melhorias (achados automáticos com as regras do `oportunidades.ts`, testes A/B por `ak1`/`ak1-b`, Comparar); teste diário do Google (Edge `mkt-web-pagespeed`); leads na base de pessoas com link para a ficha (admin/dev); connect rate (page views ÷ cliques no link) com o Tráfego; as 11 páginas do PB26. Gravador sem mudança |
| 06/10/2026 | Victor + Claude | UTM no padrão do gp-operacoes (`nome\|id`): leitura única `mkt.utm_separar`/`mkt_web.origem_ids` (20261006f), Origem, achados por criativo e connect rate cruzam pelo id; a coleta guarda os ids em `campaign_id`/`adset_id`/`ad_id`; UTM guardado até 300 caracteres no servidor. Gravador sem mudança de comportamento (ver o risco do corte em 120 caracteres na seção 6) |
