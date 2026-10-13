# Playbook de decisões e testes

**Para a empresa inteira, em qualquer área.**

**Dono do documento:** Renan Schwarz

Versão 1.1, 13/10/2026 (inclui a seção 6A). Baseado no protocolo de testes do PB26 (`metodo/protocolo_de_testes_pb26.md`), que continua valendo como o manual detalhado do tráfego.

---

## 1. Para que serve este playbook

A premissa é simples: **aqui dentro, toda decisão importante é tratada como uma hipótese.** Nós achamos que algo vai funcionar, escrevemos o que esperamos que aconteça, conferimos se aconteceu e guardamos o que aprendemos.

Isso vale para tráfego, comercial, atendimento, conteúdo, RH, operações e financeiro.

Ser científico **não** é testar tudo. É ser honesto sobre o quanto sabemos em cada decisão. Por isso, este playbook tem **três níveis de rigor**. A decisão pequena ganha um registro simples. A decisão grande, com volume, ganha um teste completo.

> **Em uma frase:** antes de decidir, escreva o que você espera. Depois, confira se aconteceu. Sempre do mesmo jeito.

---

## 2. Os conceitos, em linguagem simples

Você não precisa saber estatística para usar este playbook. Precisa entender oito ideias.

| Conceito | O que é | Exemplo do dia a dia |
|---|---|---|
| **Hipótese** | Uma aposta que dá para conferir. Tem que ter número. | "A página nova aumenta as inscrições em pelo menos 30%." "Vai melhorar" não é hipótese, porque não dá para saber se errou. |
| **Variável** | A única coisa que você muda. | Trocar só o título do e-mail, e não o título, a imagem e o horário ao mesmo tempo. |
| **Grupo de controle** | Quem continua do jeito antigo, para comparar. | Um remédio só se prova comparando quem tomou com quem tomou placebo, no mesmo período. |
| **Amostra** | Quantos casos você precisa observar antes de concluir. | Jogar uma moeda 3 vezes e dar 3 caras não prova que a moeda é viciada. Jogar 300 vezes e dar 250 caras, sim. |
| **Ruído** | A variação que acontece por acaso, sem causa. | Um vendedor fecha 5 vendas numa semana e 2 na outra, sem ter mudado nada. |
| **Sinal** | A diferença que é real, grande demais para ser acaso. | O vendedor passa a fechar 5 por semana, toda semana, depois do treinamento. |
| **Confiança de 95%** | A régua da empresa. Só chamamos algo de "comprovado" quando a chance de ser acaso é de 5% ou menos. | É como um juiz que só condena com prova forte. Às vezes um culpado escapa, mas raramente um inocente é condenado. |
| **Confundidor** | Algo que mudou junto e pode explicar o resultado no lugar da sua mudança. | As vendas subiram no mês do roteiro novo, mas também era Black Friday. Qual dos dois causou? |

**Duas frases para guardar:**
- **"Não comprovado" não quer dizer "igual".** Quer dizer que ainda não sabemos. É um resultado **inconclusivo**.
- **Comparar "antes x depois" engana.** Um feriado, uma eleição ou o começo do mês mudam os números sozinhos. Sempre que der, compare **dois grupos no mesmo período**.

---

## 3. Qual nível usar

Antes de decidir qualquer coisa, responda três perguntas:

1. **Quanto custa errar?** Dinheiro, tempo, imagem, pessoas afetadas.
2. **Dá para desfazer?** Voltar atrás amanhã é fácil ou é caro?
3. **Tenho volume e consigo dividir ao acaso?** Tenho muitos casos (visitas, leads, mensagens) e consigo sortear quem recebe a versão nova?

Depois, escolha o nível:

```
A decisão é pequena e fácil de desfazer?
│
├── SIM ──► NÍVEL 1: Decisão registrada
│
└── NÃO ──► Tenho volume E consigo sortear quem recebe a mudança?
            │
            ├── SIM ──► NÍVEL 3: Teste controlado
            │
            └── NÃO ──► NÍVEL 2: Piloto com comparação
```

| Nível | Quando usar | Esforço | O que você ganha |
|---|---|---|---|
| **1. Decisão registrada** | Decisão pequena, fácil de desfazer, ou sem volume para testar | 5 minutos | Memória: saber depois se a aposta acertou |
| **2. Piloto com comparação** | Decisão relevante, mas não dá para sortear | Médio | Uma comparação justa, com os riscos anotados |
| **3. Teste controlado** | Decisão relevante, com volume e com sorteio possível | Alto | Prova de causa e efeito |

**Na dúvida entre dois níveis, use o mais simples que ainda responde à pergunta.**

---

## 4. Nível 1: decisão registrada

**Para que serve:** decisões do dia a dia que não justificam um teste, mas que merecem ser conferidas depois. Sem registro, a empresa nunca descobre se as próprias apostas costumam acertar.

**Ficha curta (preencher antes de decidir):**

| Campo | O que escrever |
|---|---|
| Decisão | O que vamos fazer |
| Por quê | A hipótese, em uma frase |
| Previsão com número | O que esperamos ver, e até quando |
| Data de revisão | Quando vamos conferir |
| Na revisão | A previsão bateu? Sim, não ou não dá para saber. O que aprendemos? |

**Exemplo:**
- **Decisão:** mudar a reunião de alinhamento do tráfego de segunda para terça.
- **Por quê:** na segunda ainda não temos os dados do fim de semana fechados.
- **Previsão:** as decisões da reunião passam a usar dados completos, e não precisamos refazer nenhuma na mesma semana.
- **Revisão:** daqui a 4 semanas.

---

## 5. Nível 2: piloto com comparação

**Para que serve:** quando a decisão importa, mas não dá para sortear. Por exemplo: não dá para sortear metade dos funcionários para um processo novo, nem dividir clientes ao acaso sem risco.

**A ideia:** um grupo faz a mudança e um grupo **parecido** continua como está, **no mesmo período**. Como não houve sorteio, os dois grupos nunca são idênticos. Por isso, anotamos tudo o que pode ser diferente entre eles (os confundidores).

**Ficha:**

| Campo | O que escrever |
|---|---|
| Hipótese | Com número |
| Grupo piloto | Quem faz a mudança |
| Grupo de comparação | Quem continua como está. Por que ele é parecido com o piloto? |
| Métrica | O que vamos medir, e como |
| Período | Os dois grupos medidos nas mesmas datas |
| Medição antes | Os números dos dois grupos **antes** da mudança, para ver se já eram diferentes |
| Confundidores | O que mais pode explicar o resultado |
| Leitura | Data fixa |
| Decisão combinada | O que fazemos se der certo, errado ou empatar |

**Como ler:** olhe a **diferença das diferenças**. Se o grupo piloto melhorou 20% e o grupo de comparação também melhorou 15% no mesmo período, a mudança explica só uns 5%. O resto veio de fora: sazonalidade, mercado, feriado.

**Exemplo:**
- **Hipótese:** um roteiro novo na sessão de viabilidade aumenta a taxa de fechamento em pelo menos 20%.
- **Piloto:** o time A usa o roteiro novo por 4 semanas.
- **Comparação:** o time B continua com o roteiro atual nas mesmas 4 semanas.
- **Medição antes:** a taxa de fechamento dos dois times nas 4 semanas anteriores.
- **Confundidores:** a experiência dos vendedores, a origem dos leads de cada time e a troca de alguém no meio do piloto.

**Atenção:** o nível 2 dá uma **boa pista**, não uma prova. Se o resultado for decisivo e caro, vale tentar transformar em nível 3. No exemplo acima, isso seria sortear os leads entre os dois roteiros, em vez de comparar times.

---

## 6. Nível 3: teste controlado

**Para que serve:** decisões relevantes em que temos volume e conseguimos **sortear** quem recebe cada versão. É o único nível que **prova causa e efeito**, porque o sorteio deixa os dois grupos iguais em tudo, menos na mudança.

**Onde já dá para usar hoje:**
- **Tráfego:** criativos, páginas, públicos. O manual detalhado está em `metodo/protocolo_de_testes_pb26.md`.
- **WhatsApp e e-mail:** dividir a base ao acaso entre duas mensagens, ou deixar **10% sem receber** para saber se a mensagem muda alguma coisa.
- **Comercial:** sortear os leads entre dois roteiros ou duas ofertas.
- **Página:** dividir os visitantes entre duas versões, como no teste BL2 atual x BL2 de uma dobra.

### 6.1 As sete regras do teste controlado

1. **Ficha preenchida antes de começar.** Sem ficha, não é teste: é mudança.
2. **Uma variável só.** Mudou duas coisas, não dá para saber qual funcionou.
3. **Sorteio e mesmo período.** Os dois grupos rodam ao mesmo tempo, com quem cai em cada um decidido ao acaso.
4. **Amostra calculada antes** (seção 7).
5. **Duração mínima.** Pelo menos uma semana inteira quando o comportamento muda com o dia da semana. No tráfego, o mínimo é de 3 dias e o ideal é 7.
6. **Não mexer no meio.** Qualquer mudança reinicia o relógio.
7. **Conferir a medição antes de ligar.** Se o dado não chega certo, nenhuma estatística salva o teste.

### 6.2 Ficha completa

| Campo | O que escrever |
|---|---|
| Nome | A x B, em poucas palavras |
| Responsáveis | Quem monta, quem confere, quem lê |
| Hipótese | Com número |
| Variável única | O que muda, e a lista do que **não** muda |
| Como sortear | Como cada caso cai em A ou em B |
| Métrica de decisão | **Uma** métrica, a mais próxima do resultado que importa |
| Métricas de diagnóstico | As que ajudam a explicar o porquê |
| Menor diferença que importa | Abaixo disso, mesmo que seja real, não vale a mudança. Como escolher: seção 6A |
| Amostra mínima | Pela tabela da seção 7 |
| Início e data de leitura | Datas fixas |
| Alarme | Quando paramos antes: dano claro ou medição quebrada |
| Decisão combinada | O que fazemos em cada um dos quatro resultados (seção 8) |

---

## 6A. Como escolher a "menor diferença que importa"

Esta é a dúvida mais comum de quem monta a primeira ficha: **"Como eu vou saber que a minha mudança vai mexer 30% ou mais, se ainda não testei?"**

A resposta curta: **você não sabe, e não precisa saber.**

### 6A.1 Os 30% não são uma previsão. São a escolha da balança.

Imagine três balanças:

- uma **de caminhão**, que pesa toneladas;
- uma **de banheiro**, que pesa pessoas;
- uma **de farmácia**, que pesa remédios em gramas.

Antes de pesar, você não sabe o peso exato do que vai colocar em cima. Mas sabe **o que quer conseguir enxergar**. Para pesar uma carta, a balança de caminhão não serve: ela vai marcar "zero", e isso não quer dizer que a carta não pesa nada. Quer dizer que a balança não é sensível o bastante.

A "menor diferença que importa" é **escolher a balança do teste**. Quando a ficha diz 30%, ela está dizendo:

> "Se a diferença real for de 30% ou mais, quero ter quase certeza de que o teste vai mostrar. Se for bem menor que isso, aceito que o teste não mostre."

Ninguém está prometendo que a mudança vai dar 30%. O teste existe justamente para descobrir quanto ela dá.

### 6A.2 O que acontece quando a diferença real é menor que a régua

Exemplo real: o teste da página BL2 atual x BL2 de uma dobra, com a régua de 30% e cerca de 1.450 visitas por versão.

| Se a página nova for, na verdade... | Chance de o teste mostrar isso |
|---|---|
| 50% melhor | 99% |
| **30% melhor (a régua)** | **80%** |
| 20% melhor | 48% |
| 15% melhor | 30% |
| 10% melhor | 16% |

**Como ler:** quanto menor a diferença real, mais o teste "deixa passar". Se a página nova for só 10% melhor, em 84 de cada 100 testes como esse o resultado vai ser **inconclusivo**.

E está tudo bem. Inconclusivo, nesse caso, quer dizer: "se existe uma melhora, ela é pequena demais para essa amostra". Não quer dizer que as duas páginas são iguais.

**Quer uma balança mais fina?** Precisa de mais casos. Com os 7 dias completos do teste (cerca de 3.400 visitas por versão), a chance de enxergar uma melhora de 20% sobe de 48% para 83%.

### 6A.3 As quatro perguntas para escolher a régua

Você não chuta a régua. Você responde quatro perguntas.

**Pergunta 1: quanto vale a pena?**
Qual a menor melhora que justifica o trabalho de mudar? Se a página nova der só 5% a mais, vale o esforço de manter, revisar e comunicar a mudança? Se a resposta for "não", 5% está abaixo do piso. Essa pergunta define **o mínimo que interessa ao negócio**.

**Pergunta 2: o que os nossos próprios dados já mostram?**
Olhe quanto aquela métrica já varia naturalmente entre as opções que você tem.
- No PB26, o custo por lead varia de R$ 14 a R$ 81 entre os escritórios: 5 vezes. Então, trocar de escritório ou de criativo mexer 30% é totalmente plausível.
- Já a cor de um botão quase nunca mexe 30% em lugar nenhum.

Se a variação que você já vê no dia a dia é bem maior que a sua régua, a régua é realista.

**Pergunta 3: faz sentido na conta?**
Faça a conta de trás para frente e veja se o número exigido é possível.
- Exemplo da página: para o MQL por visita subir 30% (de 11,9% para 15,5%), quase **20%** das visitas teriam que completar a pesquisa. Hoje são 15,6%.
- 20% é possível? Antes de 10/10, a Bernadete já levava **18,8%** das visitas a completar a pesquisa na página atual.
- Conclusão: 20% é ambicioso, mas fica perto do que o nosso melhor tráfego já fez. A aposta é realista, não um chute.

Se a conta exigir um número que nunca foi visto em lugar nenhum, a régua está alta demais.

**Pergunta 4: qual o tamanho da alavanca?**
Mudanças grandes mexem muito. Ajustes finos mexem pouco. Do maior impacto para o menor:

| Tamanho | O que muda | Exemplos |
|---|---|---|
| Muito grande | **Quem** recebe | Público, escritório, oferta |
| Grande | **O que dizemos** | Ângulo, promessa, dor (herança x proteção x imposto) |
| Médio | **Formato** | Pessoa falando, depoimento, página longa x página curta |
| Pequeno | **Gancho** | Os primeiros 3 segundos, a primeira frase |
| Muito pequeno | **Execução** | Cor, cenário, música, uma palavra no título |

Quanto mais para baixo na tabela, menos provável chegar a 30%.

### 6A.4 Exemplo do começo ao fim

**Situação:** queremos testar uma página de uma dobra no lugar da página atual da BL2.

| Pergunta | Resposta | Conclusão |
|---|---|---|
| 1. Quanto vale a pena? | Menos de uns 20% não compensa o trabalho de manter a página nova | Piso: 20% |
| 2. O que os dados mostram? | A conclusão da pesquisa já varia de 13,5% a 18,8% entre os anúncios | Uma diferença de 30% está dentro do que já acontece |
| 3. Faz sentido na conta? | Precisa de ~20% de conclusão; o melhor tráfego já fez 18,8% | Ambicioso, mas possível |
| 4. Tamanho da alavanca | Página inteira nova = formato | Médio a grande |
| **Régua escolhida** | **30%** | Com 7 dias, a amostra ainda pega bem 20% |

### 6A.5 Os três erros na hora de escolher a régua

| Erro | O que acontece | O certo |
|---|---|---|
| **Escolher uma régua pequena "por segurança"** (ex.: 5%) | A amostra necessária explode. Com 5%, seriam dezenas de milhares de visitas por versão. O teste nunca termina ou termina inconclusivo. | Usar as quatro perguntas. Se só uma diferença pequena faz sentido, talvez não valha testar (seção 10). |
| **Escolher a régua depois de ver o resultado** | Vira trapaça com você mesmo: sempre dá para achar uma régua que "aprova" o que você queria. | A régua vai na ficha, **antes** de ligar o teste. Não muda depois. |
| **Achar que a régua é uma meta** | Se der 25%, a pessoa conclui "falhou". | A régua é a sensibilidade do teste. Se der 25% com 95% de confiança, isso é um vencedor. |

### 6A.6 E se as perguntas mostrarem que 30% é improvável?

Você tem três saídas, todas honestas:

1. **Deixar a mudança mais ousada.** Em vez de trocar uma frase da página, trocar a página inteira.
2. **Aceitar uma régua menor, sabendo o preço.** Cortar a diferença pela metade exige cerca de **4 vezes mais casos** (seção 7).
3. **Não testar.** Decidir pelo custo ou pela simplicidade e **registrar no log que foi assim** (nível 1).

> **Resumo da seção:** a régua não adivinha o resultado. Ela define o que o teste consegue enxergar. Escolha com as quatro perguntas, escreva na ficha antes de começar e não mude depois.

---

## 7. Quantos casos eu preciso (amostra)

**A regra de ouro:** quanto menor a diferença que você quer enxergar, mais casos você precisa. **Cortar a diferença pela metade exige uns 4 vezes mais casos.**

Por isso, **só testamos o que pode mudar o resultado em 30% ou mais.** Detalhes pequenos (a cor de um botão, uma palavra no título) precisam de um volume que quase nunca temos.

### 7.1 Para taxas (conversão, resposta, presença, fechamento)

Casos **por grupo**, com 95% de confiança e 80% de chance de enxergar a diferença, se ela existir:

| Taxa de hoje | Para enxergar +20% | +30% | +50% | O dobro |
|---|---|---|---|---|
| 2% | 21.100 | 9.800 | 3.800 | 1.140 |
| 5% | 8.160 | 3.780 | 1.470 | 430 |
| 10% | 3.840 | 1.770 | 690 | 200 |
| 20% | 1.680 | 770 | 290 | 80 |
| 40% | 600 | 270 | 100 | 22 |

**Como ler:** se 10% dos visitantes se inscrevem hoje e você quer saber se a página nova leva isso a pelo menos 13% (+30%), precisa de cerca de **1.770 visitantes em cada versão**.

### 7.2 Para custos (custo por lead, por MQL, por venda)

Resultados **por grupo** (leads, MQL, vendas):

| Diferença que queremos enxergar | Resultados por grupo |
|---|---|
| O dobro (um custa 2x o outro) | ~33 |
| 50% | ~95 |
| 30% | ~230 |
| 25% | ~315 |

### 7.3 E se o volume não chega?

Se a amostra não cabe no tempo ou na verba, **não é para fingir que testou.** Há três saídas honestas:
1. Testar uma mudança **maior**, que possa fazer uma diferença maior.
2. **Descer para o nível 2**, sabendo que o resultado é uma pista e não uma prova.
3. **Decidir sem teste**, pelo custo ou pela simplicidade, e **escrever que foi assim**.

---

## 8. Como ler o resultado

Na data de leitura, sempre nesta ordem:

1. **A amostra chegou?** Se não chegou, o resultado é inconclusivo, mesmo que pareça óbvio.
2. **A medição e o contexto estão ok?** Algum dado quebrado, feriado ou mudança no meio? Se sim, anotar e desconfiar.
3. **Qual o tamanho da diferença?** Ela é maior que a "menor diferença que importa" da ficha?
4. **Qual a confiança?**
   - **95% ou mais:** comprovado. Agir.
   - **De 90 a 95%:** provável. Agir só se a tendência dos dias confirmar.
   - **Abaixo de 90%:** ruído. Só agir com justificativa de prazo ou custo, e dizendo isso.
5. **Confere no degrau de cima?** Se a versão nova ganhou na métrica rápida, mas perdeu no que importa no fim (qualidade, venda, presença), ela não ganhou.

### Os quatro resultados possíveis

| Resultado | Quando | O que fazer |
|---|---|---|
| **Vencedor** | 95% ou mais, e a diferença passa da mínima | Vira o padrão |
| **Provável** | De 90 a 95%, com a tendência a favor | Adotar aos poucos, mantendo a versão antiga em parte até confirmar |
| **Empate prático** | A diferença é pequena e o intervalo inteiro fica dentro da mínima | Ficar com a mais barata ou a mais simples |
| **Inconclusivo** | A amostra não chegou ou a margem de erro é larga | Estender o teste, ou decidir por outro critério dizendo qual |

As contas (intervalo de 95%, probabilidade de uma versão ser pior) saem do script `metodo/analise_teste.py`. Quem não sabe rodar pede para quem sabe. **Ninguém declara vencedor "no olho".**

---

## 9. Os erros mais comuns (com exemplos nossos)

| Erro | Por que é um problema | Exemplo real do PB26 |
|---|---|---|
| **Comparar antes x depois** | Algo de fora pode ter mudado junto | O custo da BL2 piorou de 10 a 12/10, que foi um feriado prolongado. Parte da piora pode ser o feriado, e não as campanhas. |
| **Olhar todo dia e parar quando "ficou bom"** | Cedo ou tarde, o acaso produz um dia bonito. Parar nele fabrica falso vencedor. | Por isso a regra é olhar todo dia, mas decidir só na data marcada. |
| **Decidir com um dia só** | Um dia é quase sempre ruído | O Wiliam saiu a R$ 69 por MQL em 10/10 e a R$ 35 em 11/10, sem nada ter mudado. |
| **Mudar duas coisas juntas** | Não dá para saber qual funcionou | A Bernadete recebeu mais verba e entrou na CBO ao mesmo tempo. Não dá para separar o efeito de cada mudança. |
| **Confundir média com o resultado da última unidade** | A média esconde que o dinheiro extra rende menos | A CBO saía a R$ 40 por MQL na média, mas os R$ 1.250 a mais da Bernadete compraram MQL a cerca de R$ 70. |
| **Chamar de "igual" o que é inconclusivo** | Faz a empresa abandonar ideias boas cedo demais | Sem amostra, "não deu diferença" quer dizer "não sabemos". |
| **Declarar vencedor pela métrica rápida** | O clique não é a venda | Um criativo com muito clique e página que não converte não é vencedor. |
| **Rodar testes demais ao mesmo tempo** | Um atrapalha o outro e o acaso aparece como "resultado" | O tráfego limita a 1 a 3 testes no ar ao mesmo tempo. |

---

## 10. Quando NÃO testar

Testar tem custo: tempo, verba, atenção e a parte do público que recebe a versão pior. Não teste quando:

- **A decisão é óbvia ou obrigatória:** lei, segurança, um erro claro a corrigir.
- **É fácil de desfazer e barata:** use o nível 1 e siga em frente.
- **O volume nunca vai chegar a tempo:** veja a seção 7.3.
- **Não existe uma decisão esperando o resultado:** se nada muda com a resposta, o teste é só curiosidade.

> **Pergunta de controle:** "Se o resultado vier A, fazemos o quê? E se vier B?" Se as duas respostas forem iguais, não precisa testar.

---

## 11. O log de decisões e testes

Toda decisão de nível 2 ou 3, e as de nível 1 que valem lembrar, entram numa linha do log. É assim que a empresa acumula conhecimento, e não só opinião.

| Data | Área | Nível | Decisão ou teste | Hipótese com número | Leitura em | Resultado | Confiança | O que fizemos | O que aprendemos |
|---|---|---|---|---|---|---|---|---|---|
| 13/10 | Tráfego | 3 | Página BL2 atual x uma dobra | Uma dobra aumenta MQL por visita em 30% ou mais | 7 dias após o início | Em andamento | | | |
| 05/10 | Tráfego | 2 | Migrar a captação da AK1 para a BL2 | O custo por lead qualificado cai na BL2 | 07, 12 e 16/10 | Em andamento | | | |

**Onde fica:** `metodo/log_de_testes.md` no repositório. O resultado de cada teste também vira comentário na tarefa do ClickUp.

**Revisão mensal:** uma vez por mês, conferir as previsões do nível 1. Qual a taxa de acerto das nossas apostas? No tráfego, o curso estima que só cerca de 1 em cada 10 testes vira vencedor. Errar faz parte. **Não registrar é que é o erro.**

---

## 12. Exemplos por área

| Área | Pergunta | Nível | Como fazer |
|---|---|---|---|
| Tráfego | Qual criativo traz MQL mais barato? | 3 | Um criativo por conjunto, orçamento igual. Manual: `protocolo_de_testes_pb26.md` |
| Tráfego | A página nova converte mais? | 3 | Dividir os visitantes ao acaso entre as duas versões |
| CRM / WhatsApp | O lembrete aumenta a presença na live? | 3 | Sortear 10% dos inscritos para **não** receber o lembrete e comparar a presença |
| CRM / e-mail | Qual assunto de e-mail é mais aberto? | 3 | Dividir a base ao acaso entre os dois assuntos |
| Comercial | O roteiro novo fecha mais? | 3 ou 2 | O ideal é sortear os leads entre os roteiros (3). Se não der, um time faz e o outro não (2) |
| Conteúdo | O formato carrossel engaja mais que o vídeo? | 2 | Alternar os formatos em semanas comparáveis, anotando o tema de cada post como confundidor |
| RH | O processo seletivo novo contrata melhor? | 2 ou 1 | Comparar quem entrou pelos dois processos no mesmo período, pela avaliação aos 90 dias |
| Operações | A nova rotina de checagem reduz erros? | 2 | Uma equipe faz e outra não, com os erros medidos antes e depois nas duas |
| Financeiro | Mudar o dia de vencimento reduz atraso? | 2 ou 3 | Se der para sortear os clientes entre as datas, nível 3 |

---

## 13. Resumo de bolso

1. **Escreva antes:** hipótese com número, o que muda, como vai medir, quando vai ler.
2. **Compare no mesmo período**, com sorteio sempre que der.
3. **Uma mudança de cada vez.**
4. **Escolha a régua antes** (a menor diferença que importa) com as quatro perguntas da seção 6A. Ela não é uma previsão: é a sensibilidade do teste.
5. **Calcule a amostra.** Sem volume, não finja que testou.
6. **Não mexa no meio e não pare no dia bonito.**
7. **Leia sempre com a mesma régua de confiança:** 95% é comprovado; de 90 a 95% é provável; abaixo de 90% é ruído.
8. **Inconclusivo não é igual.**
9. **Registre no log**, inclusive o que deu errado.
