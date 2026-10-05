# Pedidos de alteração de cadastro

Pedido do Victor (05/10/2026). Quem não tem acesso à Central de Alunos (ex.: Isabela Teixeira, Head de Sucesso do
Cliente) passa a **pedir** a alteração numa tela própria; o aprovador decide na Central e o sistema aplica.

**Status (05/10/2026): etapa 1 pronta, migration NÃO APLICADA.** O front está na branch
`feat/pedidos-alteracao` e só vai para a `main` depois de a migration estar no banco.

## Telas

- **`/sistema/pedidos-alteracao`** (menu "Pedidos de alteração"): para quem pede. Novo pedido + "Meus pedidos"
  com o andamento. Não mostra a lista da Central.
  - Busca do aluno a partir de 3 letras, com o mínimo para distinguir homônimos: instrução, "sócio de {titular}",
    turma, e-mail mascarado (`is***@gmail.com`), final do telefone e do documento. Filtros opcionais por
    instrução (as 12), espaço e titular/sócio. Até 15 resultados.
  - Tipos: **Alterar dado** (campo da lista fechada, com o valor atual na tela), **Trocar sócio** (titular, quem
    sai entre os sócios dele, quem entra: já na base ou pessoa nova) e **Outro** (texto livre).
  - Motivo obrigatório; evidência opcional (link).
- **Central de Alunos, aba "Pedidos de alteração"**: só para quem aprova, com contador de abertos. Mostra antes e
  depois, o valor de hoje quando mudou desde o pedido (conflito), aprovar (com ajuste opcional nos campos de
  texto) ou recusar (motivo obrigatório, quem pediu vê). Status da planilha e link para o caso de Remoção.

## Regras

- **Quem pede:** dev/admin, ou gestor/operador com a área **`pedidos_alteracao`** (catálogo de acessos **3.6** na
  tela de Usuários). Não dá acesso à Central. Espelho: `pa_pode_pedir()` e `podePedirAlteracao()`.
- **Quem aprova:** quem está em `public.pa_aprovadores` (hoje o Victor). Incluir outro:
  `insert into public.pa_aprovadores (perfil_id) values ('<uuid do perfil>');`
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
  **Remoção de Acessos** (tipo "Troca de sócio", aguardando triagem, prazo de 1 dia útil) para quem saiu: a
  retirada dos acessos segue o checklist do módulo (Victor, JP, Thomas, Ana Camila).
- **"Outro":** aprovar só registra; o aprovador faz à mão e marca como aplicado.

## Status

`pendente` → `aplicado` (ou `recusado`). `aprovado` = "outro" aprovado, falta aplicar. `erro` = falhou ao aplicar.
`planilha_status = pendente` em todo pedido aplicado (menos "outro"): é a fila da **etapa 2**.

## Etapa 2 (fora desta entrega)

Automação (n8n) que lê os pedidos com `planilha_status = 'pendente'`, escreve na planilha da Central e marca
`ok`/`erro` (`planilha_em`, `planilha_erro`). Precisa de uma função de leitura e confirmação para o n8n (padrão
`ra_slack_*`, com segredo), que ainda não existe.

## Banco

Migration `infra/supabase/migrations/20261005j_pedidos_alteracao.sql` (ensaio `20261005j_ensaio.sql`, medições em
`20261005j.explain.md`). Tabelas `pa_pedidos`, `pa_historico`, `pa_aprovadores`, fechadas. Funções da tela:
`pa_meu_papel`, `pa_buscar_alunos`, `pa_socios_do_titular`, `pa_valor_atual`, `pa_turmas`, `pa_criar`,
`pa_meus_pedidos`, `pa_fila`, `pa_decidir`, `pa_marcar_aplicado`.

Código: `web/modules/alunos/domain/pedidos-alteracao.ts` (regras e testes),
`web/modules/alunos/ui/PedidosAlteracaoClient.tsx`, `PedidosAprovacao.tsx`, `pedidos-alteracao-data.ts`.
