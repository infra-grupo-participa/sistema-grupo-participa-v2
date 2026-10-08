# Níveis de acesso: o lado do banco

Pedido do Victor Hugo (07/10/2026): líder edita a própria área e só vê as outras; financeiro só para quem foi nomeado.
O front está em `docs/niveis-de-acesso-front.md`. Este arquivo é o banco: o que existe, em que ordem entrou e o que
falta. Detalhe e provas de cada passo no `.explain.md` da migration.

## Modelo (schema `acesso`)

- `acesso.master` (Victor Hugo, Arthur Galvão, João Pedro Alves; e a conta de teste QA Sessoes desde 07/10, para o JP
  testar a tela, ver `20261007204002`), `acesso.vinculo` (departamento/área, papel
  responsável ou membro, com vigência), `acesso.capacidade` (`financeiro.ver`, `financeiro.operar`, `cpf.ver`,
  `contato.ver`), `acesso.excecao_admin` (6 não masters com admin/dev, decisão do Victor), `acesso.log` (só acréscimo).
- Contas de teste para a tela (sem pessoa real): QA Sessoes (`qa.sessoes@advmais.com`, master) e QA Tráfego
  (`qa.trafego@advmais.com`, membro do Tráfego, sem financeiro nem master, desde 07/10, ver `20261007204700`). Perfil para
  alterar e reverter na tela de Usuários: o Robô de teste E2E (Financeiro), sem tocar no `financeiro.ver` dele
  (`20261007204700.explain.md` §6).
- Regra: todo perfil ativo da equipe vê tudo, menos o Financeiro; edita o que o vínculo dá; capacidades nunca vêm de
  "vê o resto". `gp_is_admin()` = master ou exceção nominal. Vale para o v2; **não decide nada no GPS** desde 08/10
  (ver "Incidente do GPS").
- O app lê `public.gp_meu_acesso()` (uma vez por request). Gestão só master: `acesso_listar`, `acesso_vincular`,
  `acesso_desvincular`, `acesso_capacidade_definir`.
- Gatilho `acesso_guarda` em `public.perfis`: cargo admin/dev só para master ou exceção; CPF novo só pela capacidade;
  o próprio nome de equipe só o master troca; mudanças de acesso vão para `acesso.log`.
- Blindagem (de outra equipe, 07/10 19:25 UTC): recriar `gp_is_admin`, `gps.eh_equipe` e outras exige
  `blindagem.autorizar_guarda(motivo)` na mesma transação.

## Incidente do GPS (07/10) e o princípio (08/10)

- **O que aconteceu:** o JP relatou no Slack (08/10 10:31) que a migration de acesso de 07/10 redefiniu o
  `gp_is_admin()` e rebaixou o `perfis.cargo`, e a equipe do programa GPS ficou sem acesso. O GPS usava o acesso central:
  `gps.eh_equipe()` era `gp_is_admin() OR editar Educacional OR gps.eh_operador()`. A fase 2 (`20261007182928`, 18:29 UTC)
  tirou admin de quem operava o GPS; o João devolveu admin/dev a 6 pessoas às 18:39 UTC e instalou a blindagem às 19:25 UTC;
  a fase 3 (`20261007195738`) criou a exceção nominal para não tirar mais nada de ninguém.
- **Correção (do JP, no GPS, 08/10):** lista própria `gps.admins` + `gps.eh_admin()`, editada na tela "Equipe e admins"
  (repo `gps-thb`, migrations 366 a 375). O GPS não lê mais `gp_is_admin()`, `perfis.cargo` nem `gp_acesso_pode_editar`.
  No banco, em 08/10: `gps.eh_equipe()` = `gps.eh_admin() or gps.eh_operador()`.
- **O que deixou de valer aqui:** a frase "a exceção nominal mantém o GPS / o `gps.eh_equipe`" (comentário e explain da
  `20261007195738`, corrigidos em 08/10). As provas com `gps.eh_equipe()` saíram dos ensaios do v2: não medem mais nada do
  acesso central.
- **Princípio (aceito pelo Victor em 08/10):** identidade central, permissão no schema de cada sistema. O `acesso`
  central decide o v2; não decide nada dentro de outro projeto (GPS, SIP, Central, Workbook...). Mudança em
  `gp_is_admin()`, `perfis.cargo` ou `gp_acesso_pode_editar` exige antes conferir quem, fora do v2, ainda lê essas
  funções e colunas, e avisar o dono.

## Migrations

| Versão | O quê | Situação |
|---|---|---|
| `20261007180503` | fase 0: schema `acesso`, funções, seed | aplicada |
| `20261007181138` | fase 1: guardas "velho OU novo" | aplicada |
| `20261007182928` | fase 2: rebaixar não masters, vínculos | aplicada |
| `20261007184603` | registro da devolução manual de admin/dev das 18:39 | aplicada |
| `20261007193801`, `20261007194917` | registros da Jusy e do Marcos Paulo | aplicadas |
| `20261007195738` | fase 3: tira o atalho do cargo, exceção nominal, gatilho | aplicada |
| `20261007204002` | conta de teste QA Sessoes (`qa.sessoes@advmais.com`) vira master para o JP testar a tela (temporário; reversão no explain) | aplicada |
| `20261007204017` | B2 parte 1: RPC `acesso_perfil_atualizar_como` (só service_role; master só por master), log com o autor da rota | aplicada |
| `20261007y2` | B2 parte 2: recusa mudança de acesso pela service_role sem autor | não aplicada; **só depois da rota nova na main** |
| `20261007204020` | anon sem execute nas 4 guardas; sem MAINTAIN em perfis | aplicada |
| `20261007204024` | B3: `gps.trocar_meu_nome` não derruba a parte do aluno | aplicada |
| `20261007204700` | conta de teste QA Tráfego (`qa.trafego@advmais.com`) membro do Tráfego, sem financeiro, para o JP (reversão no explain) | aplicada |

## Pendências

- Rota `/api/admin/usuarios` usar `acesso_perfil_atualizar_como` (contrato em `20261007204017.explain.md` §3, RPC no ar desde 07/10), depois a y2.
- MAINTAIN nas outras tabelas do `public` (default do Supabase): dívida.
- Telas de Usuários e Configurações (front).
