# Roteiro da carga noturna da pessoa única (14/10/2026)

À noite **só entra dado**. A estrutura já está no banco: grupos A e B aplicados em 14/10 ~15:00 UTC (ver `README.md`).
Um passo por vez, **nunca dois scripts ao mesmo tempo** (uma conexão só). Cada passo vira uma entrada no
DIARIO-DO-BANCO (no segundo cérebro) com os números.

Os scripts estão em `infra/scripts/pessoa-unica/` e rodam deste Mac. Credenciais usadas (só o nome, nunca o valor):
- `SUPABASE_ACESS_TOKEN` do `controle-de-eventos/.env` (Management API);
- `SUPABASE_SERVICE_ROLE_KEY` do mesmo arquivo (só para ler a RAM nas métricas);
- Vault `activecampaign_api_key` (AC);
- token Google do Victor em `~/.mcp-google-sheets/` (planilha).

Todo script confere, antes de cada lote:
- a chave `pessoas.carga_chave`;
- o disco (**para acima de 6 GB**);
- a RAM livre (espera abaixo de 150 MB);
- as conexões (até 50), o vigia e o tempo do lote.

Rodar de novo **retoma** de onde parou.

## 0. Antes de tudo (21:55)

```sql
-- sem live no ar: ritmo dos últimos 15 min perto ou abaixo da média de 24 h, conexões < 50, 0 alerta do vigia
select (select count(*) from pessoas.eventos where quando > now() - interval '15 minutes') eventos_15min,
       round((select count(*) from pessoas.eventos where quando > now() - interval '24 hours') / 96.0, 1) media_15min,
       (select count(*) from pg_stat_activity) conexoes,
       (select count(*) from ops.banco_alerta where criado_em > now() - interval '60 minutes') alertas;
select pessoas.carga_contagem();   -- anotar: é a contagem "antes" da noite
```

Sinal de live (escrita bem acima da média, conexões perto de 50, alerta do vigia) = **adiar e avisar o Maestro**.

## 1. Aplicar 170100, 170200 e 170300 (só se o pentester aprovou)

Pelo `aplicar.py` da sessão ou pela Management API (`/database/migrations`, `begin`/`commit`), nesta ordem:
`20261014152236_pessoas_criar_cargas_fontes.sql` → `20261014152239_pessoas_criar_carga_planilha_ativacao.sql` →
`20261014152242_pessoas_criar_rotinas_manter_vivo.sql`. Depois de cada uma: anotar a versão gravada em
`supabase_migrations.schema_migrations` e renomear o arquivo para ela. Os 2 jobs da 170300 nascem **desligados**.
Sem o ok do pentester: pular os passos 1, 3 e 4 e fazer só o passo 2.

## 2. ActiveCampaign completo (~3,5 a 4 h)

```bash
cd infra/scripts/pessoa-unica
python3 carga_ac.py --ensaio 300                              # amostra real, desfeita (rollback interno); só contagens
python3 carga_ac.py --rodar catalogo                          # 167 listas, 603 tags, 792 campos
python3 carga_ac.py --rodar estagio --max-lotes 2 --lote 500  # 2 lotes de teste
python3 carga_ac.py --status
caffeinate -i python3 carga_ac.py --rodar tudo --lote 500     # o resto; subir para --lote 1000 se os lotes ficarem < 5 s
```

**Conferir no fim:**

```sql
select fase, status, lotes, lidas, inseridas, atualizadas, iguais from pessoas.carga_execucao where fonte = 'activecampaign' order by id;
select count(*), count(*) filter (where pendente) pendentes, count(*) filter (where descadastrou) descadastrou,
       count(*) filter (where desativado_empresa) inativo_empresa, count(*) filter (where pessoa_nova) pessoas_novas
  from pessoas.ac_contato;                                     -- esperado: ~508 mil, 0 pendentes
select tipo, count(*) from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato' group by 1;   -- lead ~508 mil + pre_checkout
select pessoas.carga_contagem();
```

## 3. Fontes do banco (< 1 h; depois do passo 1)

```bash
caffeinate -i python3 carga_fontes.py --rodar todas
```

A ordem é Hotmart academy (~57 mil transações, a mais lenta) → Hotmart escritório → Central → T1-T40 → HM → sócios do HM →
Respondi → leads CNHF → leads workbook → leads Black → CRM.

**Conferir no fim:**

```sql
select fonte, status, lotes, lidas, inseridas, atualizadas, iguais from pessoas.carga_execucao where fonte <> 'activecampaign' order by id;
select fonte_tabela, tipo, count(*) from pessoas.eventos where fonte_tabela is not null group by 1, 2 order by 1, 2;
select count(*) from pessoas.relacoes;
```

## 4. Planilha de ativação T1-T42 (minutos; depois do passo 1)

```bash
python3 carga_planilha.py --previa     # sem banco: abas, colunas reconhecidas, linhas por aba (esperado ~8.836)
caffeinate -i python3 carga_planilha.py --rodar
```

**Conferir:**

```sql
select papel, count(*), count(*) filter (where pendente) pendentes from pessoas.planilha_linha group by 1;
```

## 5. Manter vivo

- **De hora em hora (só banco: Hotmart, Respondi e as outras fontes do banco).** Ligar só depois dos passos 3 e 4 com
  status `ok`, com o ok do Maestro:
  ```sql
  select cron.alter_job(jobid, active := true) from cron.job where jobname = 'pessoas-incremental';
  ```
  Hotmart e Respondi não têm rotina externa: o webhook da Hotmart e o `respondi-sync` já põem o dado no banco.
- **Delta diário do AC: fica DESLIGADO.** Para ligar (ok do Victor dado em 14/10, com condições):
  1. publicar a Edge `pessoas-ac-delta` (quem publica: Maestro ou JP);
  2. `update pessoas.carga_chave set ligada = true where fonte = 'activecampaign_delta';` (a data de fim, 31/12/2026, já está gravada);
  3. `select cron.alter_job(jobid, active := true) from cron.job where jobname = 'pessoas-ac-delta';`

  O delta usa:
  - chave do AC do Vault `activecampaign_api_key` (conta do AC `drmarciosa79109`) e segredo do cron Vault `cron_webhook_secret`;
  - 1× por dia, às 05:40 UTC (02:40 em Brasília);
  - no máximo 42 chamadas ao AC por dia (2 de listas + teto de 40 páginas de contatos);
  - fim em 31/12/2026.

## Parar na hora

```sql
update pessoas.carga_chave set ligada = false where fonte in ('activecampaign', 'hotmart_academy', 'hotmart_escritorio', 'thb_alunos',
  'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio',
  'ativacao_planilha', 'incremental', 'activecampaign_delta');
```

O lote em curso termina e o próximo é recusado; a execução fica `parada` e retoma quando religar.

## Como voltar

- **Estrutura:** `*_reversao.sql` de cada migration, na ordem inversa da aplicação.
- **Dado carregado:** pessoa não se apaga (regra I-03). A carga é identificada:
  - por fonte: `pessoas.eventos.fonte_tabela`;
  - pessoas que a carga do AC criou: `pessoas.ac_contato.pessoa_nova`;
  - pessoas que a planilha criou: `pessoas.planilha_linha.pessoa_id`.

  Desfazer eventos de uma fonte é decisão do Maestro, com contagem antes.
- **Estágio do AC:** e-mail, telefone e nome viram nulos em D+2 depois da carga conferida; os campos, em até 30 dias
  (aprovado pelo Victor). Migration própria, com ensaio.
