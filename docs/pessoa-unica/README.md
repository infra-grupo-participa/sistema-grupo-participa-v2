# Pessoa única

Uma base só de pessoas para CSM e Escritório (`pessoas.pessoas`), com a história de cada pessoa
(`pessoas.eventos`, a "linha do tempo"): de quais eventos foi lead, a que checkout foi, o que comprou, em que turma
entrou, de quem é sócio. Uso final: consultas em linguagem natural (MCP) para montar listas e responder perguntas
sem planilha.

Decisões do Victor (14/10/2026) e plano completo: no segundo cérebro (`Projetos/sistema-unico/pessoa-unica/PLANO.md`).
Este documento fica no repositório para quem trabalha aqui sem acesso ao cérebro.

## Donos e situação (16/10/2026)

- **Donos do banco:** Victor Hugo, Arthur Galvão e João Pedro Alves (JP). Mudança de estrutura passa por um deles,
  pelo passo a passo `departamentos/dados/areas/infraestrutura/banco-de-dados/alterar-a-estrutura-do-banco.md` do
  `gp-operacoes`. Dono de cada schema: `mapa-dos-sistemas.md`, na mesma pasta.
- **Código:** a branch `victor-pessoa-unica` entrou na `main` em 16/10 (merge `2bcbeca`). O banco já tinha as
  migrations aplicadas desde 14/10; o merge só alinhou o código ao banco.
- **No banco (lido em 16/10):** `fin.eventos` tem 88 eventos, todos com chave (as 87 da 160000 mais, ao que tudo
  indica, o ATM de setembro da 160500; a conferir). Evento 59 = `Holding Total (HT21)`, chave `ht21-2026-04`.
- **Ligado em 16/10/2026 (ok do Victor):** migrations `20261016120000` e `20261016120100` aplicadas, Edge `pessoas-ac-delta`
  publicada, jobs 319 (`pessoas-incremental`, hora em hora, minuto 50) e 320 (`pessoas-ac-delta`, 05:40 UTC) **ligados**. Números e
  comandos na seção "Aplicação de 16/10/2026" abaixo. A carga da Hotmart (academy e escritório) terminou em 16/10 (57.424 e 546).
- **Ainda não feito:** ligação da `fin.identidade` à pessoa, fila de revisão sem dono, a primeira
  volta do delta do AC termina em 3 dias por causa do teto de 42 chamadas por dia (ver "Aplicação").

## Decisões que valem para o código

| Decisão | Consequência no banco |
|---|---|
| Pessoa oficial = `pessoas.pessoas` (CSM e Escritório juntos) | o setor é atributo da compra/evento, não da pessoa |
| `fin.identidade` continua casando a Hotmart | não é substituída; vai apontar para a pessoa oficial |
| Catálogo oficial de eventos = `fin.eventos`, com a chave da casa `nome-curto-aaaa-mm` | migration 160000 (chaves aprovadas pelo Victor) |
| `inicio` de um evento = dia do evento; captação em coluna própria | `fin.eventos.captacao_inicio` (160450); os funis do financeiro ordenam por `inicio` |
| Casar pessoa por e-mail, nunca por CPF | `pessoas.casar_email()` na carga em massa; CPF nunca entra |
| Sinal não é compra do produto (HM, Aurum); reserva = sinal; renovação é tipo próprio | `pessoas.oferta_tipo` + `pessoas.vw_oferta` (160400) |
| Descadastro no ActiveCampaign tira do disparo; inativo da empresa não | `pessoas.ac_contato.descadastrou` × `desativado_empresa` |
| Só acrescentar; nunca apagar pessoa | colunas nulas, FK `not valid`, índice `concurrently`, reversão escrita |

## Migrations (`infra/supabase/migrations/`)

| Versão gravada | Arquivo antes | O que faz | Grupo | Situação |
|---|---|---|---|---|
| 20261014150003 | 160200 | `pessoas.eventos` + evento/turma/fonte; `pessoas.relacoes` (sócio de); `pessoas.vw_oferta` | A | **aplicada 14/10 ~15:00 UTC** |
| (não registrada) | 160300 | índices `concurrently` (único por fonte, por evento, por turma); um por chamada, fora de transação | A | **aplicada 14/10 ~15:01 UTC**, 3 válidos |
| 20261014150034 | 170000 | carga do ActiveCampaign: estágio, controle, chave de desligar (com data de fim), funções, regra das listas de SV | A | **aplicada 14/10 ~15:00 UTC** |
| 20261014150135 | 160000 | `fin.eventos.chave` (87 chaves aprovadas pelo Victor; 88 no banco em 16/10) | B | **aplicada 14/10 ~15:01 UTC** (aceite do JP) |
| 20261014150138 | 160100 | `evento_id` em `mkt.projetos`, `ht_editions`, `controle.evento`, `ht.cohorts`; `thb_turmas.chave` | B | **aplicada** |
| 20261014150141 | 160400 | tipo das ofertas (`pessoas.oferta_tipo`, 68 pelo nome) | B | **aplicada** |
| 20261014150144 | 160450 | `fin.eventos.captacao_inicio` (HT20 01/01, HT21 13/03) | B | **aplicada** |
| 20261014150148 | 160500 | evento ATM de setembro (`atm-2-2026-09`) | B | **aplicada** |
| 20261014150150 | 160510 | evento 59 = HT21 | B | **aplicada** (conferido no banco em 16/10; o cabeçalho antigo do arquivo dizia "NÃO APLICADA") |
| 20261014152236 | 170100 → 210100 | cargas das fontes do banco (Hotmart por conta, Central, T1-T40, HM, Respondi, leads, CRM) + modo só novos | C | **aplicada 14/10 ~15:22 UTC** (pentester liberou) |
| 20261014152239 | 170200 → 210200 | planilha "Alunos T1-T42 Ativação" (estágio e carga, sem CPF) | C | **aplicada** |
| 20261014152242 | 170300 → 210300 | rotina de hora em hora + agendamento do delta do AC; os 2 jobs **desligados** | C | **aplicada** |
| 20261016120000 | (16/10) | `pessoas-incremental` por fonte, com `COMMIT`, teto de linhas, orçamento em segundos, erro visível no vigia, chaves com fim em 15/11 (achado 7) | C | **aplicada 16/10 ~12:33 UTC**; job 319 ligado ~12:35 UTC |
| 20261016120100 | (16/10) | `carga_respondi` e `carga_aluno_historico` no modo só novos sem fome: filtro = mesmo descarte da `casar_email` (e-mail válido, até 320). Respondi: 3.505 sem evento, só 9 viram evento; aluno_historico: 29 descartadas | C | **aplicada 16/10 ~12:33 UTC** (md5 dos corpos conferidos) |

Os arquivos foram renomeados para a versão gravada em `supabase_migrations.schema_migrations` (guia 6.3); o primeiro
comentário de cada um diz o nome antigo. Cada uma tem `.explain.md`, ensaio e reversão.

## Carga do ActiveCampaign

Script: `infra/scripts/pessoa-unica/carga_ac.py` (leia o `LEIAME.md` da pasta).

- Fases: catálogo (listas, tags, campos) → estágio (`pessoas.ac_contato`) → pessoas (`pessoas.pessoas`,
  `identificadores`, `eventos`).
- Em série, uma chamada por vez, lotes de 500 a 1.000. Antes de cada lote confere a chave de desligar, o disco (para
  acima de 6 GB), a RAM livre da máquina do banco (espera abaixo de 150 MB), as conexões, o vigia e o tempo do lote.
- Retoma de onde parou (cursor em `pessoas.carga_execucao`).
- Dado pessoal: o lote vai como parâmetro ligado (fora do texto do SQL e do log); erro só com código e 1ª linha; cada
  valor do lote é validado antes de CHECK e cast.

## Delta diário do AC (Edge `pessoas-ac-delta`)

Código em `infra/supabase/functions/pessoas-ac-delta/index.ts`. **PUBLICADA em 16/10/2026 (versão 1, `verify_jwt = false`); job 320 e chave ligados.**
- Teto de 42 requisições ao AC por dia UTC. Cada requisição é conferida e gravada em `pessoas.carga_lote` (detalhe
  `chamada_ac`) **num comando só** (`insert ... select ... where (select count(*) ...) < 42 returning id`; sem linha =
  teto atingido). A soma conta todas as linhas `chamada_ac` do dia, de qualquer execução (achados B1 e B2 da 3ª revisão
  do pentester, corrigidos em 14/10 à noite).
- Estouro do orçamento de tempo (110 s) sai como `tempo_esgotado`, não como `teto_do_dia`.
- Revisão de 16/10 (`victor-ac-delta`, não publicada): header vazio devolve 401 antes do Vault; chave ligada com `ate`
  vencida devolve 503 `chave_vencida`; parcial na fase das listas vira `ok:false, parcial:true` (HTTP 200 não é sucesso);
  primeiro delta parte do dia anterior ao fim da carga inicial (cobre os ~334 contatos criados desde a parada de 15/10),
  com o cursor validado por regex; estágio para pessoas limitado a 6 chamadas de 1.000 por execução.
- Diferença de 334 contatos (AC 508.976 em 16/10 x `pessoas.ac_contato` 508.642): a carga parou em 15/10 ~04:30 UTC e a
  criação média é ~285/dia, então o delta cobre isso. **Não pega contato apagado no AC** (não verificado, sem a API).
- Correções da 4ª revisão (16/10): no fim da leitura o cursor recebe o dia UTC de `iniciada_em` da própria execução (não "hoje": um ciclo
  retomado depois da meia-noite deixaria de fora o contato atualizado depois da passagem do id); `aguardando` com chave ligada sai `ok:false`;
  flag em memória além da trava consultiva (esta é de sessão e reentrante) e `idle_timeout` de 150 s (era 20 s e fechava a conexão, soltando a trava,
  na espera entre tentativas). Data de fim das chaves: 15/11/2026; ao ligar, `ate = current_date + 30`.
- Situação: pentester aprovou a 5ª revisão (`ca2fe42`); publicada e ligada em 16/10 com o ok do Victor. `deno check` passou na máquina de
  quem publicou (deno 2.9.7); a Edge rodou de verdade pela primeira vez em 16/10 ~12:36 UTC (seção abaixo).

## Aplicação de 16/10/2026 (rotina horária e delta do AC)

Feito por quem publicou, com o ok do Victor de 16/10/2026 ("desde que o banco aguente"), medindo a RAM livre da máquina (948 MB) a cada passo
(piso combinado: 150 MB). Horários em UTC.

| Hora | Passo | Resultado |
|---|---|---|
| 12:33:35 a :37 | `aplica_sql.py aplicar` da `20261016120000` (begin/commit, versão gravada na mesma transação) | procedure e função por fonte criadas, job 319 chama `call pessoas.carga_incremental_rodar(200, 60, 1500)`, chaves `incremental` e `activecampaign_delta` com fim 2026-11-15, sem permissão para anon/authenticated/service_role |
| 12:33:47 a :48 | idem da `20261016120100` | md5 dos corpos: `carga_respondi` `149b00e7…`, `carga_aluno_historico` `cae0c782…` (os esperados) |
| ~12:34 | Edge `pessoas-ac-delta` publicada (`supabase functions deploy --use-api --no-verify-jwt`, versão 1) | GET 405, POST sem header 401, POST com segredo errado 401. Vault: `cron_webhook_secret` e `activecampaign_api_key` existem (a chave do AC com a URL da conta na descrição) |
| 12:35:00 a :18 | `call pessoas.carga_incremental_rodar(20, 60, 200)` pela Management API (o `COMMIT` valeu) | 11 fontes, 61 linhas lidas, 0 erro; hotmart_* e as sem novidade não gravam execução; 73 eventos novos no banco no intervalo |
| 12:35:36 | chave `incremental` ligada com `ate = current_date + 30` (2026-11-15) e `cron.alter_job(319, active := true)` | |
| 12:36:19 a :34 | chave `activecampaign_delta` ligada (`ate` 2026-11-15) e 1 POST na Edge, como o cron faz | `ok:false, parcial:true`, 42 chamadas ao AC (2 listas + 40 páginas), 4.000 contatos lidos (3.680 iguais, 320 atualizados, 0 novos), 74,7 s, cursor `2026-10-14\|431856`, 1 chamada de estágio para pessoas (restam 0) |
| 12:38:29 | `cron.alter_job(320, active := true)` | |
| 12:50:00 a :21 | 1ª rodada do job 319 pelo cron | `succeeded`, 21,3 s, 279 linhas lidas (respondi 6, leads_black 73, crm_negocio 200, hm_socios 0), 0 problemas, 0 alerta do vigia |

**De onde o delta tira o ponto de partida.** Do cursor da última execução do delta com `status = 'ok'` (`fonte = 'activecampaign'`, `fase = 'estagio'`,
`por = 'delta'`); sem nenhuma, usa o dia UTC de `terminada_em` da última carga do script (`por` diferente de `delta` e `ensaio`) menos 1 dia.
Em 16/10 não havia delta: a carga do script (execução 69) terminou em 15/10 04:30 UTC, então o cursor saiu `2026-10-14|0`. O estágio foi lido de 15/10
00:57 a 04:30 UTC, por isso 14/10 00:00 cobre a carga inteira com mais de 24 h de margem (inclusive se o relógio do AC estiver até 5 h deslocado:
o `udate` do AC vem com `-05:00` e, em 17 contatos do estágio, a data de atualização é posterior ao fim da carga).

**Tamanho do intervalo (GET de contagem no AC, `meta.total`, 16/10 ~12:31 UTC):** atualizados desde 2026-10-13 = 11.262; desde 2026-10-14 = **9.853**
(99 páginas de 100); desde 2026-10-15 = 2.885 (em 15/10 e 16/10, ~1,5 dia, ou ~19 páginas por dia); contatos com id acima do último da carga (748276) = 416.
Dos 9.853, a maioria já estava no estágio (a atualização em massa de 14/10: 7.798 contatos), por isso as primeiras 40 páginas trouxeram só 320 mudanças.

**Por que não zerou em 16/10.** O teto de 42 chamadas ao AC por dia UTC (condição do ok de 14/10, contada em `pessoas.carga_lote`) foi todo gasto na 1ª chamada:
2 de listas + 40 páginas = 4.000 contatos, ids até 431856. Faltam cerca de 5.850 (59 páginas) e os 416 contatos novos, que ficam no fim porque a leitura é por id
crescente. A execução ficou `parada` com o cursor `2026-10-14|431856`; o cron das 05:40 UTC de 17/10 retoma dele (e o de 18/10 termina). Os leads novos
do AC entram como `lead` no fim dessa volta (18/10); para adiantar, só subindo o teto do dia (código da Edge e novo ok do Victor). Depois da volta
o cursor passa a ser o dia em que a execução começou (16/10) e a leitura diária fica em 19 a 38 páginas.

**Como conferir:**
```sql
select id, fase, status, cursor, lidas, atualizadas, iguais from pessoas.carga_execucao where fonte = 'activecampaign' and por = 'delta' order by id desc limit 4;
select * from pessoas.carga_execucao where fonte = 'incremental' order by id desc limit 3;     -- coluna erro: problemas e fontes puladas
select status, return_message from cron.job_run_details where jobid in (319, 320) order by runid desc limit 4;
select count(*) from (select 1 from pessoas.eventos where fonte_id is not null group by fonte_tabela, fonte_id, tipo having count(*) > 1) z;  -- 0
```

**Como desfazer:** `select cron.alter_job(319, active := false); select cron.alter_job(320, active := false);` e
`update pessoas.carga_chave set ligada = false where fonte in ('incremental', 'activecampaign_delta');`. A estrutura sai com os `_reversao.sql` das duas migrations.
Dado carregado não se apaga (regra I-03).

## Como testar

- Antes de aplicar: `python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio
  infra/supabase/migrations/20261014170000_ensaio.sql` (dado fictício, transação desfeita).
- Depois de aplicar: `python3 infra/scripts/pessoa-unica/carga_ac.py --ensaio 300` (amostra real passada a
  `pessoas.carga_ensaio`, que roda tudo e desfaz; só contagens).
- `python3 infra/scripts/pessoa-unica/carga_ac.py --status`.

## O que falta

- Cargas das outras fontes (Hotmart `fin`, `controle.aluno_historico` T1-T40, ativação T1-T42, `thb_alunos`,
  `cs.contatos_hm`/`hm_socios`, leads de evento, Respondi, CRM): desenhadas, não escritas.
- Base T1-T40: vai até a T40, mas T39 e T40 estão incompletas e T41/T42 não estão; completar pela planilha de ativação e
  por `thb_alunos`.
- Manter vivo (carga incremental por gatilho ou pg_cron, leve), atributos do dicionário e funções de consulta do MCP
  (com pentester).
- Limpeza do estágio `pessoas.ac_contato`: e-mail, telefone e nome em D+2 depois da carga conferida; campos em até 30 dias
  (aprovado pelo Victor em 14/10/2026).
