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

Se a RPC ainda não existir, falhar ou não devolver dado, o bloco permanece disponível, mostra zero quando se trata de card numérico e exibe “sem dado ainda”. Falhas isoladas não impedem os demais blocos. Uma falha de atualização preserva o último dado carregado. Resumo e série atualizam a cada 60 segundos somente com a aba visível, sem sobrepor chamadas.

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
