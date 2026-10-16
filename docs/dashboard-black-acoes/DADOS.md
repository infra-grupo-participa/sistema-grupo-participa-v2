# Ações de Renovação da Black Friday · dados

A parte de banco do dashboard "Ações de Renovação da Black Friday". A tela (card em Academy, abas e componentes) está no README desta
pasta. Migrations: `20261014210000` (estrutura) e `20261014210100` (cadastro da primeira ação). O porquê e o ensaio estão
em `infra/supabase/migrations/20261014210000.explain.md`.

## Situação (14/10/2026)
- **No ar** desde 20:12 UTC: migrations `20261014210000`, `20261014230000` e `20261014210100`. Projeto 87
  (`black-thb-2026-10`, sigla técnica `BTHBV26`).
- A planilha `[BF26 THB VENCIDOS] MENSAGERIA` está ligada na sync desde 20:13 UTC. A oferta sai em 15/10; sem SMS.

## Como funciona
- **Uma ação é uma linha de `dados.dashboards`** (modelo `acao-black`), ligada a um projeto de `mkt.projetos` pela
  etiqueta. A tela usa as RPCs do "Esta edição" do ATM com `p_chave` = etiqueta.

| O que a tela mostra | De onde vem |
|---|---|
| Leads | `metodo.pesquisa_respostas` com `etiqueta` = chave. A etiqueta é posta pelo de-para `metodo.origem_etiqueta`. Origem `teste` é teste. |
| Custo e disparos | Planilha de mensageria da ação em `mkt_mensageria.planilhas` (sync a cada 10 min, job 257), mais os disparos de grupo do SendFlow da campanha cadastrada |
| Ingresso no grupo | `dados.dashboard_grupos`: entradas do SendHook em `crm.evento_jornada`, sem export |
| Pré-checkout | `pessoas.eventos` do projeto e a lista do Active em `lista_ac` (nula até existir) |
| Vendas | Hotmart pela `oferta_codigo` (e `ofertas_extra`) na conta do cadastro; nula até existir a oferta |
| Comparecimento | `dados.sessoes` (a live) e as presenças, como no ATM |

## Contrato com a tela
- **Cards:** `dados_atm_resumo(p_chave, p_de, p_ate)`.
  - Investimento = `custo_disparo_centavos`.
  - Vendas, CAC, receita e ROAS nulos sem oferta: mostrar "aguardando oferta".
- **Evolução diária:** `dados_atm_serie_diaria`.
- **Disparos:** `dados_atm_disparos_canais` e `dados_atm_disparos_lista`.
- **Comparecimento:** `dados_atm_comparecimento`.

## Replicar para uma ação nova (ex.: THB a vencer, Aurum)
1. Etiqueta da ação (Victor) e sigla do projeto.
2. Uma migration no molde da `20261014210100`:
   - `mkt.projetos` e `dados.dashboards` (modelo `acao-black`);
   - a sessão, a campanha do SendFlow (`dados.dashboard_grupos`) e a planilha de mensageria (desligada; o mapa de colunas
     confere o cabeçalho).
3. Se a página de captação for do `metodo`: uma linha em `metodo.origem_etiqueta` (origem → etiqueta).
4. SendHook da campanha apontando para `crm-integracao-webhook/sendflow`. Sem isso, o ingresso não chega.
5. Na tela, uma linha no registro com a etiqueta e o estado `ativa`.

## Nomenclatura dos disparos
- O padrão é `[etiqueta] [CANAL] [MOMENTO] NOME`, por exemplo `[black-thb-2026-10] [API] [14/10 17H] CONVITE`. O
  MOMENTO sai das colunas DATA e HORÁRIO.
- O `api_item` liga ao projeto o disparo que chega pela API com a etiqueta entre colchetes (migration `20261014230000`).

## Cuidados
- **Data sem ano** na planilha: pôr `"ano"` no mapa da aba. Sem isso, a linha é ignorada calada.
- **Hora em faixa** ("09H-18H"): `"hora_faixa": true`.
- **Aba sem coluna de público** (ex.: GRUPOS THB): `"lista_fixa": "<público>"`.
- **Cabeçalho fora da linha 1** (ex.: GRUPOS THB, linha 10): `"cabecalho_linha": 10`.
- **Aba API:** o tipo (`utility` ou `marketing`) é obrigatório; nesta planilha vem da coluna CATEGORIA META.
- **Projeto pela `[SIGLA]`:** "[BF26 THB VENCIDOS]" no nome da mensagem não casa com a BF26 (vira `BF26THBVENCIDOS`). O
  disparo da API sem planilha fica sem projeto.
