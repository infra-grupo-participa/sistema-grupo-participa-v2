# e2e (Playwright)

Testes de navegador contra o sistema rodando em `next dev` (porta 3100) com o banco de **produção**.

## Rodar

```
npm run e2e                                  # todos
npx playwright test financeiro-fila          # um arquivo
npx playwright show-report e2e/.resultados/relatorio
```

Na 1ª vez na máquina: `npx playwright install chromium`.
Se já houver um `next dev` na porta 3100, ele é reusado.

## .env.local (valores nunca vão para código, log ou commit)

- `E2E_FIN_EMAIL` — e-mail do usuário-robô do Financeiro. **Precisa terminar em `@advmais.com`**: a tela de login,
  o proxy e a RLS (`gp_eh_equipe()`) recusam qualquer outro domínio.
- `E2E_FIN_SENHA` — senha do robô.

Sem as duas, os testes que precisam de login são **pulados** com mensagem. E-mail fora do domínio: a execução
**falha** no setup com a causa.

A sessão fica em `e2e/.auth/fin.json` e é reusada (novo login só quando ela expira — poupa o limitador de login).
Artefatos (screenshot, trace, relatório) em `e2e/.resultados/`. As duas pastas estão no `.gitignore`.

## Regra: somente leitura em produção

- O teste abre painéis e **cancela**. Nunca clica em confirmar, ligar, criar, rejeitar, salvar.
- Todo spec novo instala a rede de segurança de `financeiro-fila.spec.ts`: RPC com nome de escrita e qualquer
  escrita REST fora de `/rpc/` são abortadas no navegador, e o teste falha se alguma for tentada.
- Espera por locator/estado (`expect(...).toBeVisible()`, `expect.poll`). Nada de `isVisible()` instantâneo nem
  `waitForTimeout`. Teste que alterna entre pulado e falha é espera errada.
