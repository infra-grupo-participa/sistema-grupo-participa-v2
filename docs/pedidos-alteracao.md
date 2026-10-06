# Pedidos de alteração de cadastro

Pedido do Victor (05/10/2026). Quem precisa mudar um cadastro da Central de Alunos passa a **pedir** a alteração
numa tela própria; o aprovador decide e o sistema aplica. Quem pede não ganha acesso à Central por isso (a área
`pedidos_alteracao` é só a tela de pedidos).

**Status (06/10/2026): etapa 1 no ar** (migration `20261005j` aplicada, merge `e20aaab`). **Sócio novo com cadastro
completo** (migration `20261005k`) **APLICADA** (commit `002535a`, na `main`).
**Troca de sócio direto em remoção** (`20261006144912`) e **sócio novo herda entrada e turma** (`20261006144913`):
**APLICADAS em 06/10/2026** (ensaio OK antes; pentester e orquestrador aprovaram). Ver "Banco".
**Etapa 2, parte do banco** (migrations `20261006160401` a `20261006160404`): **APLICADAS em 06/10/2026**, com
ensaio OK, pentester aprovado e ok do Victor. Os ensaios gastaram números da sequência: o próximo pedido real sai com
nº 103 (os 11 a 102 não existem). Ver "Etapa 2".

## Telas

- **`/educacional/pedidos-alteracao`** (menu "Pedidos de alteração"): para quem pede. Novo pedido + "Meus pedidos"
  com o andamento. Não mostra a lista da Central.
  - Busca do aluno a partir de 3 letras, com o mínimo para distinguir homônimos: instrução, "sócio de {titular}",
    turma, e-mail mascarado (`is***@gmail.com`), final do telefone e do documento. Filtros opcionais por
    instrução (as 12), espaço e titular/sócio. Até 15 resultados.
  - Tipos: **Alterar dado** (campo da lista fechada, com o valor atual na tela), **Trocar sócio** (titular, quem
    sai entre os sócios dele, quem entra: já na base ou pessoa nova) e **Outro** (texto livre).
  - **Trocar sócio > Pessoa nova** (05/10/2026, migration `20261005k`): cadastro completo. Nome, e-mail, telefone e
    CPF/CNPJ obrigatórios; profissão opcional; endereço em bloco: **país primeiro** (padrão Brasil). Brasil: CEP com
    máscara que preenche logradouro, bairro, cidade e UF pelo ViaCEP (editável; se o CEP não for achado, segue à mão) e
    **UF em lista fechada (27)**. Exterior: estado/província e código postal livres, telefone internacional.
    Erro aparece ao lado de cada campo.
  - **"Mesmo endereço de <quem sai>"**: caixa que só aparece se quem sai tem endereço. Marcada: campos travados e cinza
    com o endereço de quem sai; o pedido guarda a **foto** desse endereço (`endereco_mantido = true`). Desmarcada:
    campos vazios, com o endereço de quem sai como exemplo cinza.
  - **Duplicata**: ao digitar e-mail ou CPF/CNPJ válido, a tela avisa se já existe aluno com esse dado e oferece
    "Usar esta pessoa" (vira sócio existente). O banco recusa o pedido nesse caso.
  - "Alterar dado" de endereço usa o mesmo bloco (país, UF em lista, CEP com busca).
  - Motivo obrigatório; evidência opcional (link).
- **Central de Alunos, aba "Pedidos de alteração"**: só para quem aprova, com contador de abertos. Mostra antes e
  depois, o valor de hoje quando mudou desde o pedido (conflito), aprovar (com ajuste opcional nos campos de
  texto) ou recusar (motivo obrigatório, quem pediu vê). Status da planilha e link para o caso de Remoção.

## Regras

- **Quem pede:** dev/admin, ou gestor/operador com a área **`pedidos_alteracao`** (catálogo de acessos **3.6** na
  tela de Usuários). Não dá acesso à Central. Espelho: `pa_pode_pedir()` e `podePedirAlteracao()`.
- **Quem aprova:** quem está em `public.pa_aprovadores`: o Victor e, desde 06/10/2026 19:08 UTC, a **Isabela
  Teixeira** (inserida em produção por pedido direto do Victor; a `20261006160401` repete o insert sem efeito). Incluir
  outro: `insert into public.pa_aprovadores (perfil_id) values ('<uuid do perfil>') on conflict do nothing;`
  **Decisão do Victor (06/10/2026):** a Isabela aprova pela tela de pedidos (aba "Aprovar"), pode aprovar o próprio
  pedido (fica registrado e a tela mostra o selo "aprovou o próprio pedido") e **mantém os acessos que já tem** (é
  admin, vê a Central no sistema e edita a planilha). Nada foi fechado para ela. Ela não recebe aviso no Slack.
- **Campos editáveis (lista fechada, `pa_campos()`):** nome, e-mail, telefone, telefone profissional, documento,
  endereço (CEP, logradouro, número, complemento, bairro, cidade, UF, país), profissão, turma, instrução, espaço de
  instrução, observação da Central. **Nunca** dinheiro, compra ou Hotmart.
- **Aprovar aplica na hora**, numa transação: grava `thb_alunos` (com `atualizado_por`) e uma linha por coluna em
  `thb_alunos_audit_log` com `origem = 'pedido_alteracao:<nº>'`. Erro de validação não grava nada; erro
  inesperado deixa o pedido em `erro` (pode aprovar de novo).
- **Conflito:** se o valor na base mudou desde o pedido, não aplica sem o aprovador confirmar.
- **E-mail:** o antigo fica no audit e no pedido (a regra da Central de manter o antigo ao lado vale na planilha).
- **Troca de sócio:** quem sai só perde o vínculo; quem entra recebe vínculo, instrução `<NÍVEL> - SÓCIO`,
  espaço, vencimento e `Acompanha titular`; `num_socios` do titular é recontado. Abre um caso em
  **Remoção de Acessos** (tipo "Troca de sócio", prazo de 1 dia útil) para quem saiu: a retirada dos acessos segue o
  checklist do módulo (Victor, JP, Thomas, Ana Camila).
  **Com a `20261006144912` (APLICADA em 06/10/2026; decisão do Victor, 06/10/2026):** quem sai **sem compra própria** entra
  **direto em remoção** (sem triagem, itens já criados, Slack marca quem remove); **com compra própria** de Holding
  Masters ou Aurum (em `public.compras` ou no financeiro da Hotmart, conta academy) cai em **aguardando triagem**, com as
  compras na ficha; quem sai **sem e-mail e sem documento** também cai em triagem (não dá para checar). Antes dela, todo caso de troca cai em aguardando triagem. Regra completa em `remocao-acessos.md`.
- **Sócio novo herda do titular (`20261006144913`, APLICADA em 06/10/2026; decisão do Victor, 06/10/2026):** pessoa nova recebe
  `data_entrada_thb` e `turma_id` do titular, com auditoria. Sócio que entra já existente mantém os dele.
- **"Outro":** aprovar só registra; o aprovador faz à mão e marca como aplicado.
- **Sócio novo (20261005k):** grava em `thb_alunos` nome, e-mail, telefone, documento, `tipo_documento` (CPF/CNPJ),
  profissão e as 8 colunas de endereço (`cep`, `endereco_logradouro`, `endereco_numero`, `endereco_complemento`,
  `bairro`, `cidade`, `estado`, `pais`). **Endereço mantido = foto do pedido**, não o endereço de quem sai na hora da
  aprovação: o aprovador vê exatamente o que vai gravar (a aba mostra o cadastro completo e o selo "Endereço mantido
  do sócio que sai"). Pedido antigo, sem endereço, aprova com endereço vazio e país Brasil.
- **Validação (tela e banco iguais):** CPF/CNPJ com dígito verificador (vale também no "alterar dado" de documento);
  e-mail; telefone Brasil = 55 + DDD + número (12 ou 13 dígitos), exterior = 8 a 15 dígitos com o código do país;
  Brasil exige CEP com 8 dígitos e UF da lista; e-mail ou documento já na base = recusa.
- **Quem pede vê o endereço de quem sai** (já era assim pelo `pa_valor_atual`: quem pede vê o endereço de qualquer
  aluno, só o documento é mascarado). A checagem de duplicata devolve o mesmo resumo da busca (e-mail mascarado,
  final do documento), nunca o CPF inteiro, e só consulta documento com dígito válido.
- **CEP:** a tela chama a rota do próprio app `/api/cep` (a mesma da Placa, com checagem de origem e limite por IP),
  que consulta o ViaCEP no servidor. A CSP do app (`next.config.ts`) não restringe `connect-src`, mas a rota evita
  depender disso e não expõe o navegador a outro domínio.

## Status

`pendente` → `aplicado` (ou `recusado`). `aprovado` = "outro" aprovado, falta aplicar. `erro` = falhou ao aplicar.
`planilha_status = pendente` em todo pedido aplicado (menos "outro"): é a fila da **etapa 2**.

## Etapa 2 (banco aplicado em 06/10/2026)

Decisões do Victor de 06/10/2026 (noite). Quatro migrations, cada uma com `_ensaio.sql` e `.explain.md` (saída do
ensaio, `explain (analyze)`, as 5 perguntas e a reversão):

| Migration | O que faz | Depende de |
|---|---|---|
| `20261006160401_pa_aprovador_isabela.sql` | Isabela em `pa_aprovadores` (idempotente); `pa_linha`, e por ela `pa_fila` e `pa_meus_pedidos`, devolvem `autoaprovado` = aprovado/aplicado **e** `decidido_por = solicitado_por` | nada |
| `20261006160402_pa_slack_dm.sql` | `pa_config` e `pa_avisos` (fechadas), `pa_slack_reservar`, `pa_slack_confirmar`, gatilho `trg_pa_avisar_n8n` (pg_net, nunca derruba o insert) | nada |
| `20261006160403_pa_planilha.sql` | `pa_planilha_reservas` (fechada), `pa_planilha_reservar`, `pa_planilha_confirmar` | 160402 |
| `20261006160404_pa_historico_aluno.sql` | `pa_historico_aluno(p_aluno)` + 3 índices parciais em `pa_pedidos` (aluno, sai, entra) | nada |

Ordem de aplicar: 160401, 160402, 160403, 160404 (só a 160403 exige outra antes). Comando:
`python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py aplicar infra/supabase/migrations/<arquivo>.sql`.

**Aviso de pedido novo (DM no Slack, só para o Victor).** Texto: `:memo: Solicitaram uma alteração do aluno *<nome>*:
<tipo>, pedido por <quem pediu>. <https://grupoparticipa.app.br/educacional/pedidos-alteracao|Abrir a fila>` (nomes
escapados com `ra_slack_esc`). Destinatário em `pa_config.slack_destinos` (`{U0AQ4H2GZ0T}`), não "todo aprovador".

**`pa_config` nasce desligada.** Uma linha só, fechada (só se lê no banco, pelo SQL editor ou pelo `aplica_sql.py`):

- `segredo`: 64 caracteres gerados na migration, comparado por hash sha256 (`pa_n8n_valido`). Ler só pelo SQL editor
  do Supabase (o `aplica_sql.py consulta` imprime no terminal e, rodado por agente, cai no chat) e guardar só no
  n8n. Nunca em commit ou chat.
- `n8n_webhook_url`: nula. Enquanto for nula o gatilho não chama nada. Gravar a URL do webhook do workflow do Slack.
- `ligado_em`: nula = aviso desligado. Ligar: `update public.pa_config set ligado_em = now();`. Só pedido criado
  **depois** disso vira DM (o nº 9 e o nº 10 não geram aviso retroativo). Pedido decidido antes da rodada não gera DM.
- `planilha_id`: nula = a reserva da planilha devolve `{"ok": true, "planilha_id": null, "pedidos": []}`. Gravar
  primeiro o id da **CÓPIA** da planilha. A reserva da planilha **não** olha `ligado_em`.

**Contrato com o n8n** (PostgREST como anon, padrão `ra_slack_*`; segredo inválido devolve só `{"ok": false}`):

- `pa_slack_reservar(p_segredo)` → `{ok, mensagens: [{pedido, slack_id, texto}]}`; reserva de 2 min, até 20.
  Depois de mandar (`chat.postMessage`, `channel = slack_id`, bot `remocaoacessos`):
  `pa_slack_confirmar(p_segredo, p_pedido, p_slack_id, p_ts)`. Sem confirmar, volta na rodada seguinte.
- Gatilho: a cada pedido novo, `POST n8n_webhook_url` com `{"pedido": <nº>}` (sem segredo, só acorda o workflow).
- `pa_planilha_reservar(p_segredo)` → `{ok, planilha_id, abas, cabecalhos, reserva_minutos: 10, pedidos: [...]}`: até
  5 pedidos `aplicado` com `planilha_status = 'pendente'` (alterar dado e troca de sócio), em ordem de nº. Cada pedido
  traz as chaves para achar a linha (`emails` em minúsculas, `documentos` só dígitos) e os valores **por nome de
  cabeçalho** (`escrever`, `esperado_antes`, datas dd/mm/aaaa, turma pelo código). Troca de sócio traz `titular`
  (Sócio e Nº de sócios), `sai`, `entra`, `removidos` (J, K, M, N com os textos decididos e A = data da decisão),
  `copiar_para_removidos` e os dois caminhos `se_entra_sem_linha` / `se_entra_com_linha`.
- `pa_planilha_confirmar(p_segredo, p_pedido, p_ok, p_erro, p_detalhe)`: grava `planilha_status` ok/erro,
  `planilha_em`, `planilha_erro` e uma linha em `pa_historico` (`planilha_ok` / `planilha_erro`). Só aceita pedido
  reservado e pendente (não confirma duas vezes).

**O que o workflow da planilha tem que respeitar** (regra de casar linha fica no n8n):

1. Conferir a linha 1 contra `cabecalhos` antes de escrever. Os nomes são exatos e diferenciam maiúscula (`Obs`).
2. Achar a linha só por e-mail (as duas partes de `novo / antigo` da coluna Email) ou documento; nunca por nome. 0 ou
   mais de 1 linha, ou célula diferente do `esperado_antes` = `p_ok = false` com o motivo, sem escrever nada.
   Documento na planilha com 10 dígitos (zero à esquerda perdido) compara completando com zero.
3. Ordem na troca: achar todas as linhas, acrescentar quem sai em "Removidos — Histórico", escrever, e **apagar por
   último** (quando quem entra já tem linha).
4. Escrever Documento como texto (valor cru, sem virar número).
   Valor de texto que comece com `=`, `+`, `-` ou `@` vai com `'` na frente: texto livre aprovado (Obs, Nome,
   Profissão, Motivo) não pode virar fórmula (`IMPORTXML`/`IMAGE` mandariam dado da planilha para fora). Pentester,
   06/10/2026.
5. `p_detalhe` leva só número de linha, coluna e aba, nunca valor de célula: ele volta sem máscara no histórico do
   pedido para os aprovadores.
6. `planilha_status = 'erro'` não volta sozinho para a fila: corrigir a planilha à mão e marcar, ou ajustar no banco.

**Histórico no card do aluno.** `pa_historico_aluno(p_aluno uuid) returns table(em, pedido_id, papel, texto)`, só para
a equipe (`gp_eh_equipe()`), mais recente primeiro. Lê pedidos `aplicado` de troca e de alterar dado (sem tabela nova,
sem backfill). Uma troca vira 3 textos, um para cada pessoa: titular "<titular> trocou o sócio <X> pelo sócio <Y>",
quem sai "<X> saiu como sócio de <titular>", quem entra "<Y> entrou como sócio de <titular>" (+ " (cadastro novo)").
Alterar dado: "<Rótulo> alterado/alterada de <antes> para <depois>", com `pa_exibir` (documento mascarado para quem
não pode ver). Todos terminam em "(pedido nº N, aprovado por <nome> em dd/mm/aaaa)". "Outro" fica de fora.

**Telas da etapa 2** (`web/modules/alunos/`):

- `PedidosAlteracaoClient.tsx`: aba **Aprovar** para quem tem `pode_aprovar` em `pa_meu_papel()` (Victor e Isabela),
  montando `PedidosAprovacao.tsx`. Pedido em que quem aprovou é quem pediu mostra o selo "aprovou o próprio pedido"
  (campo `autoaprovado` de `pa_fila`/`pa_linha`).
- `PedidosAprovacao.tsx`: histórico do pedido com rótulo para `planilha_ok` ("Planilha da Central atualizada") e
  `planilha_erro` ("Erro ao atualizar a planilha da Central"); o selo `ROTULO_PLANILHA` mostra pendente, atualizada ou erro.
- `HistoricoAluno.tsx` + aba **Histórico** da ficha (`AlunoDrawer.tsx`, `ficha-aluno-abas.ts`): lê
  `pa_historico_aluno` e lista os textos acima, mais recente primeiro.
- Regras puras e testes: `domain/pedidos-alteracao.ts` e `domain/pedidos-alteracao-etapa2.test.ts`.

**Como testar:** os 4 ensaios (`aplica_sql.py ensaio infra/supabase/migrations/2026100616040<n>_ensaio.sql`; o da
160403 já carrega a 160402). Esperado nenhuma linha `ERRADO`. Depois de aplicar: abrir a fila como Isabela (aba
"Aprovar"), aprovar um pedido dela e ver o selo; abrir o histórico de um aluno com troca aplicada.

**O que falta:** criar os workflows `[Central] Pedidos de alteração
— Slack` e `[Central] Pedidos de alteração — planilha` no n8n (desligados, rodada 15 min, tokens em credencial),
gravar `n8n_webhook_url`, ligar `ligado_em`; gravar `planilha_id` da CÓPIA, aprovar o nº 9 e o nº 10, conferir a cópia
e só então a planilha real.

## Banco

Migration `infra/supabase/migrations/20261005j_pedidos_alteracao.sql` (ensaio `20261005j_ensaio.sql`, medições em
`20261005j.explain.md`). **Aplicada em 05/10/2026.**

Migration `20261005k_pedidos_socio_novo_endereco.sql` (ensaio `20261005k_ensaio.sql`, medições em `20261005k.explain.md`):
sócio novo completo. **Status: APLICADA** (commit `002535a`, na `main`). Funções novas:
`pa_ufs`, `pa_doc_valido`, `pa_eh_brasil`, `pa_endereco`, `pa_telefone_pessoa` (internas) e `pa_duplicata_pessoa`
(tela). Substituídas: `pa_normalizar`, `pa_criar`, `pa_decidir`. Tabelas `pa_pedidos`, `pa_historico`, `pa_aprovadores`, fechadas. Funções da tela:
`pa_meu_papel`, `pa_buscar_alunos`, `pa_socios_do_titular`, `pa_valor_atual`, `pa_turmas`, `pa_criar`,
`pa_meus_pedidos`, `pa_fila`, `pa_decidir`, `pa_marcar_aplicado`.

Migrations de 06/10/2026, **APLICADAS em 06/10/2026**, independentes entre si:

- `20261006144912_pa_troca_socio_direto_remocao.sql`: `pa_abrir_caso_remocao` (direto em remoção sem compra própria),
  `ra_slack_pendentes_base` (aviso próprio da troca direta, título legível da troca em triagem) e
  `ra_desfazer_triagem` (recusa a troca direta). A tela (`CasoDrawer.tsx`) esconde "Desfazer triagem" nesse caso.
- `20261006144913_pa_socio_novo_entrada.sql`: `pa_decidir` com a herança de `data_entrada_thb` e `turma_id`.

Migrations da etapa 2 (`20261006160401` a `20261006160404`): **APLICADAS em 06/10/2026**, ver "Etapa 2".

**Como testar:** `python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio infra/supabase/migrations/<ts>_ensaio.sql`
(roda em `begin … rollback`; esperado nenhuma linha `ERRADO`). Depois de aplicar: aprovar um pedido de troca e conferir
em `/educacional/remocoes` o status do caso ("Em remoção" sem compra própria, "Aguardando triagem" com compra) e, no
aluno novo, a entrada e a turma iguais às do titular. Saída do ensaio, `explain (analyze)` e reversão nos `.explain.md`.
Atenção: cada ensaio consome números da sequência de `pa_pedidos` (o rollback não devolve). Até 06/10/2026 os ensaios
já gastaram até o nº 75; o maior pedido real é o nº 10, então o próximo pedido real terá número maior que 75.

Código: `web/modules/alunos/domain/pedidos-alteracao.ts` (regras e testes),
`web/modules/alunos/ui/PedidosAlteracaoClient.tsx`, `PedidosAprovacao.tsx`, `pedidos-alteracao-data.ts`,
`pedidos-endereco-ui.tsx` (bloco de endereço).
