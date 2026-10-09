# Dashboard Seminário ATM

## Escopo

Dashboard padronizado para ATMs em Infra > Dashboards > Escritório > Seminário ATM. A primeira edição registrada é **atm-elaine-1-2026-10**, live de 13/10 às 19h30. O caminho da tela é **/infra/dashboards/escritorio/atm/atm-elaine-1-2026-10**.

O registro em **web/modules/infra/atm/domain/registro.ts** fornece a chave, o rótulo e a data da edição. Para o próximo ATM, cadastre uma nova chave confirmada nesse registro e no banco, sem duplicar a tela nem criar valores específicos da edição no componente.

## Visão e fontes

Os cards aparecem na ordem do briefing:

1. Disparos
2. Leads
3. Ingresso no grupo
4. % ingresso no grupo
5. Taxa de evasão
6. Custo com disparo
7. CPL
8. Pré-checkout
9. Vendas
10. Taxa de conversão do pré-checkout
11. CAC
12. Faturamento bruto
13. Faturamento líquido
14. ROAS

O front lê somente RPCs Supabase com a chave do dashboard:

| Bloco | RPC |
|---|---|
| Cards | dados_atm_resumo |
| Evolução diária | dados_atm_serie_diaria |
| Modal de leads, evolução e resumo | dados_atm_leads e dados_atm_serie_diaria |
| Abas API, Grupo, SMS, Ligação e E-mail | dados_atm_disparos_canais |
| Comparecimento | dados_atm_comparecimento |
| Ciclo aberto e fechado pós-live | dados_atm_pos_live |

Receita, custos, CPL, CAC e ROAS são apresentados conforme os valores devolvidos pelo banco. Não há preço de venda fixo no código. Custos em centavos são convertidos para reais na camada de dados. O modal mostra os campos de origem descritos no briefing; dado pessoal só é buscado ao abrir o modal.

Se a RPC ainda não existir ou não devolver dado, o bloco permanece disponível e mostra “sem dado ainda”. Zero numérico devolvido pelo banco é apresentado como zero medido. Falhas isoladas não impedem os demais blocos. Uma falha de atualização preserva o último dado carregado. Resumo e série atualizam a cada 60 segundos somente com a aba visível, sem sobrepor chamadas.

## Situação do banco

O contrato do front está descrito na migration **infra/supabase/migrations/20261008161000_dados_criar_modelo_seminario_atm.sql**. Ela e o cadastro inicial (**20261008161100_dados_cadastrar_atm_elaine_1.sql**, sigla `ATMEL126`) foram aplicados em produção em 08/10/2026; situação e pendências em `MODELO-DE-DADOS.md`. O front não aplica migrations nem lê planilhas.

## Teste local

1. Em **web/**, instale as dependências conforme o lockfile e configure o **.env.local** existente.
2. Rode **npm run dev -- -p 3001**.
3. Entre com um usuário autorizado a Infra e a **financeiro.ver**.
4. Abra Infra > Dashboards > Escritório > Seminário ATM.
5. Sem RPCs aplicadas, confira que a página carrega, os cards mostram zero com “sem dado ainda” e as seções sem linhas mostram o estado vazio.
6. Com as RPCs aplicadas e dados cadastrados, confira a ordem dos cards, abra o modal de leads e navegue pelas cinco abas de disparo, comparecimento e ciclos pós-live.
7. Verifique a atualização periódica e o rótulo de horário no cabeçalho.

Verificações do projeto:

    cd web
    npm run lint
    npx tsc --noEmit
    npx vitest run
    npm run build

## Teste em produção (08/10/2026)

- Merge `ba417ab` na main, CI verde. Teste logado em produção: card no Escritório, 14 cards zerados com "sem dado ainda", modal e abas ok, chave inexistente 404, sem rolagem horizontal em 374 e 377 px.
- **Acesso:** a tela usa o mesmo gate da Clínica (`csm/[chave]`). Com `acessoV2` desligado em produção, vale o modelo antigo: quem vê Infra vê a tela. O dado continua protegido no banco: as RPCs recusam quem não é da equipe (42501). Bloquear por `financeiro.ver` depende de ligar o `acessoV2`, que é outra frente.
- **Console:** enquanto a migration não for aplicada, as RPCs respondem PGRST202 (função inexistente). Desde este commit isso é tratado como "sem dado ainda", sem registrar erro.

## Resumo do modal de leads

A aba Resumo apresenta as mesmas seis categorias e contagens que antes apareciam em linhas: Entrou no grupo?, É aluno?, utm_source, Estado, Lista de origem e Seminário de origem. Valores booleanos aparecem como “Sim” e “Não”, sem texto `true`/`false`. Cada categoria usa o componente reutilizável RoscaCategorias, já adotado pela visão geral de vendas do dashboard presencial. A legenda conserva o rótulo e a quantidade de cada categoria; o centro mostra o total de leads da categoria. Em telas estreitas, a legenda fica abaixo da rosca para manter rótulo e valor legíveis.

Na rosca e na tabela, `lista_origem = 'descartado'` (estava na aba Descartados de uma das listas) aparece como **Outros**, pedido do Victor em 08/10/2026. O valor no banco continua `descartado`; a troca é só de rótulo, em `rotuloListaOrigem` (`web/modules/infra/atm/domain/dashboard.ts`).

## Período e marcação de teste

Contrato aplicado em produção em 08/10/2026, migration `20261008191000` e ajuste `20261008191100`. O detalhe de nomes, parâmetros e limites está em [MODELO-DE-DADOS.md](./MODELO-DE-DADOS.md), seção 0.

- O seletor oferece Período do evento, Hoje, Ontem, Últimos 3 dias e Últimos 7 dias. As datas relativas são calculadas em `America/Sao_Paulo`; Período do evento envia `p_de` e `p_ate` nulos para usar as datas da configuração do dashboard.
- Resumo, série, leads, canais e números do grupo recebem o período. Comparecimento e pós-live continuam no evento inteiro.
- Atualizar recarrega todos os blocos. O polling continua atualizando resumo e série a cada 60 segundos só com a aba visível. Falhas conservam o último resultado bom.
- O modal Leads ganhou a aba Grupo. Master pode marcar e desmarcar leads ou números do grupo; os controles não aparecem para outros perfis. A confirmação informa que a marcação vale para aquele evento.
- O banco exclui marcados dos indicadores. A tela não filtra resultados numéricos. Lead marcado permanece na lista master, esmaecido e com etiqueta “teste”. Números do grupo marcados também mostram a etiqueta e o motivo equipe quando aplicável.
- Se o banco devolver `leads_teste`, `grupo_teste`, `vendas_teste` ou `receita_teste_bruta` maior que zero, a tela apresenta um aviso para deixar claro o que foi excluído, inclusive quantidade de vendas e faturamento bruto.
- O aviso de itens excluídos por marcação de teste é decidido no servidor pelo UUID autenticado. A configuração única em `web/modules/infra/atm/domain/visibilidade-aviso-teste.ts` aponta para a conta do Victor; o cliente recebe só um booleano. Os dados marcados continuam fora dos indicadores para todos os usuários.
- As RPCs retornam `42501`, `P0002` e `22023` em situações de acesso, vínculo ao evento e validação. A tela apresenta mensagens legíveis e não registra identificadores pessoais nos logs.

Para validar: selecionar cada período, conferir as datas e os números, abrir Leads e Grupo, verificar as etiquetas de teste com um perfil master e confirmar que os outros perfis não recebem os controles. O aviso de exclusões aparece apenas para o Victor; confirme com sessão dele e com uma conta QA. O teste local não deve marcar ou desmarcar dados reais.

## Aba Histórico (09/10/2026, branch `victor-atm-historico`, não publicada)

Pedido do Victor de 09/10/2026 (card 17tya50ftxn). O dashboard ganhou duas abas no topo: **Esta edição** (tudo o que existia antes, sem mudança de comportamento) e **Histórico**. O histórico só é lido na primeira vez que a aba é aberta.

**Fonte.** Uma RPC só: `dados_historico_edicoes(p_familia)`, criada pela migration `20261009200000` (banco descrito no `.explain.md` dela). A família vem de `familia` no registro (`web/modules/infra/atm/domain/registro.ts`, hoje `seminario-atm`). A RPC devolve uma linha por edição com os números medidos, `fontes` (texto da fonte de cada número) e `provisorio` (métricas que ainda podem mudar). Dinheiro chega em centavos e vira reais em `infrastructure/historico-data.ts`. Enquanto a função não existir (PGRST202) a aba mostra "sem dado ainda", sem erro. Tempo limite de 15 s; falha conserva a última leitura, esmaece a tela e mostra a hora dela.

**Sub-abas.**
- **Comparativo geral:** métricas nas linhas, uma coluna por edição (rótulo exato do banco), em quatro blocos: Captação, Aulas, Vendas e Eficiência. A conversão sobre o pré-checkout é a linha principal, em destaque. A tabela rola por dentro em tela estreita.
- **Uma sub-aba por edição** devolvida pela RPC: cartão principal com a conversão sobre o pré-checkout, cards de receita líquida, ROAS, vendas, CAC, leads, ingressos no grupo, taxa de ingresso, investimento total (com tráfego e disparo) e CPL; gráfico dos picos D1 a D3 com retenção e comparativo; funil leads → grupo → pico na live (dia 1) → pré-checkout → vendas, com a passagem entre etapas e o percentual sobre os leads. Não há funil de investimento.

**Fórmulas (calculadas na tela, nunca gravadas), em `web/modules/infra/atm/domain/historico.ts`:**

| Métrica | Fórmula |
|---|---|
| Investimento total | tráfego + disparo (se uma das partes vier nula, o total fica "—") |
| CPL | investimento total ÷ leads |
| CAC | investimento total ÷ vendas |
| ROAS | receita líquida ÷ investimento total |
| Taxa de ingresso no grupo | grupo ÷ leads |
| Conversão (pré-checkout, grupo, leads) | vendas ÷ base |
| Retenção | pico da aula ÷ pico da aula anterior da mesma edição |
| Comparativo | pico da edição ÷ pico da mesma aula da edição anterior (anterior = a edição imediatamente antes pela `ordem`) |

Divisão por zero ou valor nulo aparece como "—". Dia 3 nulo (ATM JUL/26) mostra "—" e "sem dia 3", sem quebrar o layout. Cada número tem tooltip com a fonte (string do campo `fontes`) e, se for calculado, a fórmula; número provisório leva `*` e aviso. Para teclado e leitor de tela, o bloco "Fonte de cada número" lista as mesmas fontes.

**Como entra a próxima edição.** Basta a linha nova em `dados.edicoes_historico` com a mesma família e a `ordem` seguinte: a sub-aba e a coluna aparecem sozinhas, sem mexer na tela. Como a linha é preenchida está no `.explain.md` da migration `20261009200000`.

**Como testar.**
1. Em `web/`: `npx vitest run modules/infra/atm` (os testes de `historico.test.ts` conferem os dois ATMs: ROAS 4,86x e 6,02x; CAC R$ 291,42 e R$ 235,50; conversão sobre o pré-checkout 26,9% e 27,3%; retenção D2/D1 28,4% e 48,8%; comparativo D1 171,6% e D2 295,2%).
2. Com a migration aplicada, logado com usuário da equipe, abrir Infra > Dashboards > Escritório > Seminário ATM > Histórico e conferir cada número da tabela contra a seção "Números que valem" do pedido e contra a carga da migration.
3. Em 375 px: a página não pode rolar na horizontal; a tabela rola por dentro.
4. Sem a migration: a aba mostra "Histórico sem edições · sem dado ainda".
