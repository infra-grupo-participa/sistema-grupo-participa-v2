# Pessoa única

Uma base só de pessoas para CSM e Escritório (`pessoas.pessoas`), com a história de cada pessoa
(`pessoas.eventos`, a "linha do tempo"): de quais eventos foi lead, a que checkout foi, o que comprou, em que turma
entrou, de quem é sócio. Uso final: consultas em linguagem natural (MCP) para montar listas e responder perguntas
sem planilha.

Decisões do Victor (14/10/2026) e plano completo: no segundo cérebro (`Projetos/sistema-unico/pessoa-unica/PLANO.md`).
Este documento fica no repositório para quem trabalha aqui sem acesso ao cérebro.

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
| 20261014150135 | 160000 | `fin.eventos.chave` (87 chaves aprovadas pelo Victor) | B | **aplicada 14/10 ~15:01 UTC** (aceite do JP) |
| 20261014150138 | 160100 | `evento_id` em `mkt.projetos`, `ht_editions`, `controle.evento`, `ht.cohorts`; `thb_turmas.chave` | B | **aplicada** |
| 20261014150141 | 160400 | tipo das ofertas (`pessoas.oferta_tipo`, 68 pelo nome) | B | **aplicada** |
| 20261014150144 | 160450 | `fin.eventos.captacao_inicio` (HT20 01/01, HT21 13/03) | B | **aplicada** |
| 20261014150148 | 160500 | evento ATM de setembro (`atm-2-2026-09`) | B | **aplicada** |
| 20261014150150 | 160510 | evento 59 = HT21 | B | **aplicada** |
| 20261014152236 | 170100 → 210100 | cargas das fontes do banco (Hotmart por conta, Central, T1-T40, HM, Respondi, leads, CRM) + modo só novos | C | **aplicada 14/10 ~15:22 UTC** (pentester liberou) |
| 20261014152239 | 170200 → 210200 | planilha "Alunos T1-T42 Ativação" (estágio e carga, sem CPF) | C | **aplicada** |
| 20261014152242 | 170300 → 210300 | rotina de hora em hora + agendamento do delta do AC; os 2 jobs **desligados** | C | **aplicada** |

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
