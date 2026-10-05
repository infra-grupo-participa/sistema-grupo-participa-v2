# Pedidos de alteração de cadastro

Pedido do Victor (05/10/2026). Quem não tem acesso à Central de Alunos (ex.: Isabela Teixeira, Head de Sucesso do
Cliente) passa a **pedir** a alteração numa tela própria; o aprovador decide na Central e o sistema aplica.

**Status (05/10/2026): etapa 1 no ar** (migration `20261005j` aplicada, merge `e20aaab`). **Sócio novo com cadastro
completo** (migration `20261005k`) **NÃO APLICADA**: front na branch `feat/pedidos-socio-novo-endereco`, só vai para a
`main` depois de a migration estar no banco.

## Telas

- **`/sistema/pedidos-alteracao`** (menu "Pedidos de alteração"): para quem pede. Novo pedido + "Meus pedidos"
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

## Etapa 2 (fora desta entrega)

Automação (n8n) que lê os pedidos com `planilha_status = 'pendente'`, escreve na planilha da Central e marca
`ok`/`erro` (`planilha_em`, `planilha_erro`). Precisa de uma função de leitura e confirmação para o n8n (padrão
`ra_slack_*`, com segredo), que ainda não existe.

## Banco

Migration `infra/supabase/migrations/20261005j_pedidos_alteracao.sql` (ensaio `20261005j_ensaio.sql`, medições em
`20261005j.explain.md`). **Aplicada em 05/10/2026.**

Migration `20261005k_pedidos_socio_novo_endereco.sql` (ensaio `20261005k_ensaio.sql`, medições em `20261005k.explain.md`):
sócio novo completo. **Status: NÃO APLICADA** (branch `feat/pedidos-socio-novo-endereco`; a tela nova só vai para a
`main` junto com a migration, porque manda campos que a `pa_criar` da j recusa sem endereço). Funções novas:
`pa_ufs`, `pa_doc_valido`, `pa_eh_brasil`, `pa_endereco`, `pa_telefone_pessoa` (internas) e `pa_duplicata_pessoa`
(tela). Substituídas: `pa_normalizar`, `pa_criar`, `pa_decidir`. Tabelas `pa_pedidos`, `pa_historico`, `pa_aprovadores`, fechadas. Funções da tela:
`pa_meu_papel`, `pa_buscar_alunos`, `pa_socios_do_titular`, `pa_valor_atual`, `pa_turmas`, `pa_criar`,
`pa_meus_pedidos`, `pa_fila`, `pa_decidir`, `pa_marcar_aplicado`.

Código: `web/modules/alunos/domain/pedidos-alteracao.ts` (regras e testes),
`web/modules/alunos/ui/PedidosAlteracaoClient.tsx`, `PedidosAprovacao.tsx`, `pedidos-alteracao-data.ts`,
`pedidos-endereco-ui.tsx` (bloco de endereço).
