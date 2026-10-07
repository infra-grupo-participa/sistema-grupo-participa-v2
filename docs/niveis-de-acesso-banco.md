# Níveis de acesso: o lado do banco

Pedido do Victor Hugo (07/10/2026): líder edita a própria área e só vê as outras; financeiro só para quem foi nomeado.
O front está em `docs/niveis-de-acesso-front.md`. Este arquivo é o banco: o que existe, em que ordem entrou e o que
falta. Detalhe e provas de cada passo no `.explain.md` da migration.

## Modelo (schema `acesso`)

- `acesso.master` (Victor Hugo, Arthur Galvão, João Pedro Alves; e a conta de teste QA Sessoes desde 07/10, para o JP
  testar a tela, ver `20261007204002`), `acesso.vinculo` (departamento/área, papel
  responsável ou membro, com vigência), `acesso.capacidade` (`financeiro.ver`, `financeiro.operar`, `cpf.ver`,
  `contato.ver`), `acesso.excecao_admin` (6 não masters com admin/dev, decisão do Victor), `acesso.log` (só acréscimo).
- Regra: todo perfil ativo da equipe vê tudo, menos o Financeiro; edita o que o vínculo dá; capacidades nunca vêm de
  "vê o resto". `gp_is_admin()` = master ou exceção nominal.
- O app lê `public.gp_meu_acesso()` (uma vez por request). Gestão só master: `acesso_listar`, `acesso_vincular`,
  `acesso_desvincular`, `acesso_capacidade_definir`.
- Gatilho `acesso_guarda` em `public.perfis`: cargo admin/dev só para master ou exceção; CPF novo só pela capacidade;
  o próprio nome de equipe só o master troca; mudanças de acesso vão para `acesso.log`.
- Blindagem (de outra equipe, 07/10 19:25 UTC): recriar `gp_is_admin`, `gps.eh_equipe` e outras exige
  `blindagem.autorizar_guarda(motivo)` na mesma transação.

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
| `20261007y` | B2 parte 1: RPC `acesso_perfil_atualizar_como`, log com o autor da rota | não aplicada (pentester) |
| `20261007y2` | B2 parte 2: recusa mudança de acesso pela service_role sem autor | não aplicada; **só depois da rota nova na main** |
| `20261007z` | anon sem execute nas 4 guardas; sem MAINTAIN em perfis | não aplicada (pentester) |
| `20261007zz` | B3: `gps.trocar_meu_nome` não derruba a parte do aluno | não aplicada (pentester) |

## Pendências

- Rota `/api/admin/usuarios` usar `acesso_perfil_atualizar_como` (contrato em `20261007y.explain.md` §3), depois a y2.
- MAINTAIN nas outras tabelas do `public` (default do Supabase): dívida.
- Telas de Usuários e Configurações (front).
