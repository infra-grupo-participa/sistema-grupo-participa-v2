# Laboratório de decisões e testes (Infra › Laboratório)

Tela: `/infra/laboratorio`. Especificação: `playbook-de-decisoes-e-testes.md` (dono: Renan Schwarz).
Banco: migrations `20261013165350` e `20261013165429` (ver o `.explain.md`).

## Abas
- **Início**: no ar, leituras e revisões vencendo (≤ hoje + 2), taxa de acerto das apostas de nível 1, vencedores.
- **Log** (seção 11): filtros por área, nível e status; exporta CSV (`;`, UTF-8 com BOM, abre no Excel).
- **Calculadora**: amostra (taxa e custo) com a tabela de sensibilidade da 6A, e leitura com os 4 resultados.
- **Como funciona**: o playbook renderizado (fonte única: o `.md` desta pasta → `web/modules/infra/laboratorio/domain/playbook-md.ts`).
- **Nova decisão ou teste**: as perguntas da seção 3 sugerem o nível; pergunta de controle da seção 10; ficha do nível.
- **Ficha**: editar (com as travas), pôr no ar, voltar a rascunho, cancelar, registrar leitura (5 perguntas da seção 8), revisar (nível 1).

## Fórmulas (`web/modules/infra/laboratorio/domain/estatistica.ts`, testadas)
- **Amostra de taxa**: duas proporções, bicaudal, α = 0,05, poder 80%, variância agrupada sob H0. Bate com a tabela 7.1 (≤ 5%).
- **Amostra de custo**: resultados ~ Poisson, log da razão das taxas, `n = 2(zα+zβ)²/ln(1+régua)²`. Bate com a 7.2 (33/95/230/315).
- **Sensibilidade**: poder para efeitos de 10/15/20/30/50%. Reproduz o exemplo BL2 da 6A.2 (80% a 30%, 48% a 20%, 16% a 10%).
- **Leitura de taxa**: teste z agrupado; IC 95% pela variância não agrupada; confiança = 1 − p bilateral (a "chance de não ser acaso" da seção 2).
- **Leitura de custo**: resultados por real (Poisson), log da razão; benefício positivo = B rende mais por real (custo menor).
- **Classificação**: amostra não chegou ou medição quebrada → inconclusivo; ≥ 95% → vencedor (mesmo abaixo da régua, 6A.5);
  90–95% → provável; IC inteiro dentro de ±régua → empate prático; resto → inconclusivo.

## Decisões
- A tela calcula; o banco guarda o cálculo como foi lido (`lab.leitura.calculo`), para o log não mudar se a fórmula mudar.
- Acesso: toda a equipe vê e cria; edita quem criou, os responsáveis e admin.
