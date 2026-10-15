# Carga dos aptos da ação black-thb-2026-10 (THB com acesso vencido)

**Situação:** APLICADA em 15/10/2026 pelo Victor (ensaio com 386, carga com 386, conferida: 9 gerais, 7 válidos, 5 no grupo). Escrita pelo Hermes. Quem aplica é o Victor ou o João, com `service_role`/`postgres` (carga de dado,
no mesmo caminho da Lista 1 e 2 do ATM). Nada aqui é migration de estrutura: não cria tabela, coluna nem função.

## O que faz
Insere 386 linhas em `dados.lista_membros` (`chave = 'black-thb-2026-10'`, `lista = 'lista_1'`,
`importacao = 'planilha-thb-vencidos-2026-10-15'`). É a lista de **aptos** da ação. Com ela, o
`dados_atm_leads` passa a devolver `lista_origem = 'lista_1'` para quem é apto e `fora_das_listas` para quem não é.
O ATM e as outras chaves não mudam: a carga só acrescenta linhas da chave nova.

## Por que não criei tabela
`dados.lista_membros` já existe para isso (Lista 1/2 do ATM por chave, casando por e-mail normalizado). Os 386 também
estão em `public.thb_alunos`; a carga lê o e-mail de lá pelo id, então o arquivo não tem e-mail nem dado pessoal.

## Origem da lista
Planilha "Black do THB com acesso vencido", aba "Alunos THB Vencidos": 386 alunos (276 THB, 110 THB-sócio), todos
achados na Central. Os 7 das abas "Turma Especial (removidos)" e "Removidos 15/10" ficam de fora (inaptos, decisão do
Victor em 15/10/2026). Antes de aplicar de novo com a planilha mudada, regerar o arquivo: a lista é um retrato.

## Como aplicar (nessa ordem)
1. Rodar `carga-aptos-black-thb-ensaio.sql` (termina em `rollback`): deve imprimir `aptos_no_ensaio = 386`.
2. Rodar `carga-aptos-black-thb.sql` (termina em `commit`).
3. Conferir: `select count(*) from dados.lista_membros where chave = 'black-thb-2026-10'` = 386.
4. Registrar no `DIARIO-DO-BANCO.md` (regra do Victor).

## Reversão
`delete from dados.lista_membros where chave = 'black-thb-2026-10' and importacao = 'planilha-thb-vencidos-2026-10-15';`

## Efeito esperado nos 9 leads de hoje (conferido só com contagens, 15/10)
9 gerais · 7 válidos · 2 fora da lista · 5 com ingresso no grupo entre os válidos (71,43%).
