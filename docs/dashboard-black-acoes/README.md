# Ações de Renovação da Black Friday

## Implementação inicial · 14/10/2026

Foi criado o card `Ações de Renovação da Black Friday` em Infra > Dashboards > Academy (antigo CSM) e uma tela dirigida pelo registro de ações em `web/modules/infra/acoes/domain/registro.ts`.

O registro ativo é `THB vencidos`, com etiqueta `black-thb-2026-10` e origem `renovacao-thb-vencidos`. `THB a vencer` e `Aurum` aparecem como “em breve”; nenhuma etiqueta ou oferta foi inventada para elas. A oferta Hotmart de Holding Masters segue nula no registro até o Victor fornecer o código.

### Conteúdo e fontes

- **Cards:** usam `public.dados_atm_resumo` pelo carregador do ATM, com a etiqueta do registro e período nulo (período do cadastro). Investimento usa `custo_disparo_centavos`, nunca `investimento_total_centavos`. Leads, grupo, CPL, pré-checkouts e taxas vêm dos campos mapeados pelo ATM: `disparos_qtd`, `leads`, `grupo_entradas`, `grupo_pct`, `evasao_pct`, `cpl_centavos`, `pre_checkout_pessoas` e `conversao_pre_checkout_pct`. `custo_completo = false` indica custo de disparo pago faltando; nessa condição o CPL permanece sem dado. O contrato informa `grupo_tem_fonte = true`.
- **Venda e receita:** `vendas`, `cac_centavos`, `receita_bruta`, `receita_liquida` e `roas_liquido` vêm do resumo. Enquanto `ofertaHotmart` no registro for nula, a tela mostra “Aguardando oferta”; nenhum zero é apresentado nesses cards.
- **Evolução diária:** `public.dados_atm_serie_diaria`, campos `dia`, `custo_disparo_centavos`, `grupo_entradas`, `pre_checkout` e `vendas`.
- **Canais e detalhe dos disparos:** `public.dados_atm_disparos_canais` e `public.dados_atm_disparos_lista`. Os nomes das abas e o componente de detalhe são compartilhados com o ATM. O detalhe só carrega os campos retornados pelo banco.
- **Comparecimento:** `public.dados_atm_comparecimento`, com uma sessão para o evento.
- **Grupo:** a fonte de negócio indicada no pedido é a campanha SendFlow `R89eeAMF6pccfKbE9RYR`. A tela só a lê pelos dados publicados nas RPCs; não chama o SendFlow.
- **Pré-checkout e vendas:** a oferta Holding Masters ainda não existe, portanto o código da oferta permanece nulo. Não se presume uma oferta.

As RPCs e os formatos são os mesmos do “Esta edição” do ATM; o front reutiliza os carregadores, tipos, rótulos de canal, cartões e `DisparosDetalhe`. Não há RPC nova para Ações da Black.

O botão “Atualizar” e o polling de 60 segundos (apenas com a aba visível) releem cada bloco em paralelo. Respostas incompletas mantêm o último dado válido daquele bloco. Uma nova atualização não começa enquanto outra está ativa.

### Estado do cadastro

Na primeira versão do front, a etiqueta ainda não estava cadastrada no banco. O retorno `P0002` aparece como “Dashboard em preparação”, sem erro de tela ou zeros. Ao cadastrar a etiqueta, o mesmo fluxo carregará os dados. Falhas de leitura mantêm o último resultado bom por bloco. As abas THB a vencer e Aurum não têm etiqueta e não fazem chamadas RPC.

### Replicar para a próxima ação

1. Acrescente uma linha a `registroAcoesBlack` com nome e estado.
2. Preencha `etiqueta`, `origem` e `ofertaHotmart` somente com identificadores fornecidos para aquela ação. Para “em breve”, mantenha esses campos nulos.
3. Quando a oferta estiver definida, registre o código em `ofertaHotmart`; vendas, CAC, receitas e ROAS deixam de ficar “Aguardando oferta”.
4. O mesmo front usa as RPCs ATM via `infrastructure/dados.ts`. Se uma futura ação exigir contrato diferente, documente-o antes de criar um adaptador.

### Como testar

- `npx vitest run modules/infra/acoes` verifica o mapeamento de custo, a espera por oferta, a chamada com etiqueta e a ausência de chamadas para abas sem etiqueta.
- `npx tsc --noEmit`, `npm run lint:tokens` e `npm run build` verificam tipos, tokens e compilação.
- Abra Infra > Dashboards > Academy > Ações de Renovação da Black Friday. Confira THB vencidos, os cartões e o detalhe de disparos; selecione THB a vencer e Aurum e confirme o aviso “Ação em breve”.
- Com a etiqueta cadastrada, THB vencidos deve carregar os dados publicados nas RPCs. Se a chave não existir, a tela mostra “Dashboard em preparação”.

## Validação com a etiqueta cadastrada · 14/10/2026

A etiqueta `black-thb-2026-10` foi cadastrada no projeto 87. Na conferência em localhost, o resumo retornou 3 leads e 1 ingresso no grupo; pré-checkout ficou em 0. Vendas e métricas financeiras dependentes da oferta aparecem como “Aguardando oferta”. Investimento e CPL aparecem como “Sem dado” enquanto o custo de disparo não está sincronizado. A série do dia mostrou uma entrada no grupo e nenhum pré-checkout. Comparecimento carregou, preservando “Sem dado” para medidas ainda ausentes.

A leitura manual em 14/10 confirmou os mesmos dados após clicar em Atualizar. O custo de disparo permanece pendente de sincronização. A oferta ainda não foi configurada. Os dados acima são retrato da validação, não valores fixos na tela.

## Modal de Leads, leads válidos e gerais · 15/10/2026

- **Card Leads abre o modal.** Reaproveita o `ModalPessoasAtm` do ATM (`ui/ModalLeadsAcao.tsx`), sem a aba Grupo. Abas: Leads (tabela), Evolução (leads por dia em **linha**, eixos X e Y) e Resumo (pizzas de `utm_source`, estado, instrução, turma e "válido para a oferta?"). A linha da Evolução existe como opção `graficoEvolucao="linha"` do modal; o ATM segue em barras.
- **Todo mundo que preenche vira lead**, apto ou não: a Edge `metodo-perfeito` (ação `reuniao`) só valida nome, e-mail e WhatsApp. Quem usa e-mail fora da lista cai na página de "esse evento não é para você" e já está gravado.
- **Válido para a oferta** = está na lista de aptos da ação, que é `dados.lista_membros` com a chave da ação (mesma tabela da Lista 1/2 do ATM; não há tabela nova). Regra em `domain/leads.ts`: `lista_1`/`lista_2` = sim; `fora_das_listas`/`descartado` = não; sem lista carregada = **sem dado** (nunca "não").
- **Cards do topo:** Leads mostra os **válidos** e deixa o geral no hint. **Ingresso no grupo e % ingresso, desde 15/10 à tarde, fazem o contrário** (pedido do Victor): o número grande é o **geral** (todo número que entrou no grupo) e embaixo vem quantos batem com os leads válidos (o % embaixo divide pelos válidos). Se o geral estiver sem dado, o card mostra o dos válidos e diz "geral sem dado". Regra em `exibicaoCardLeads` (`domain/leads.ts`). Sem lista de aptos carregada, os três ficam com o número do resumo, como antes.
- **Quem é apto:** a lista da planilha "Black do THB com acesso vencido" (386). Os removidos (Turma Especial e Removidos 15/10) são inaptos. A carga está em `infra/supabase/cargas/black-thb-2026-10/` e **não foi aplicada**.
- **Por que não deduzir da Central:** "THB ou THB-sócio e vencido" dá 328 pessoas, 310 dentro da planilha e 18 fora; a planilha tem regra própria (sócio segue o titular, remoções manuais).

## Marcar lead como teste e gráficos só com válidos · 15/10/2026

- **Por quê:** o Victor não conseguia marcar lead como teste no modal de Leads. O botão nunca tinha sido ligado na tela da Black (o `ModalLeadsAcao` não passava `acaoTeste`). O banco já aceitava: a ação tem `modelo = 'acao-black'` em `dados.dashboards`, e `public.dados_marcar_teste` segue o mesmo caminho do ATM (`dados.atm_cadastro` + `dados.atm_pertence`), gravando em `dados.marcacoes_teste`. Conferido em 15/10: todos os 14 leads com e-mail da `black-thb-2026-10` passam em `atm_pertence`. **Nenhuma mudança no banco.**
- **O que mudou:** na aba Leads, master vê "Marcar como teste" / "Desmarcar teste" (mesmas RPCs `dados_marcar_teste` e `dados_desmarcar_teste` do ATM, pela etiqueta da ação), com confirmação própria da Black. Depois de marcar, a lista e os cards releem.
- **Evolução e Resumo contam só os leads válidos** (na lista de aptos e sem teste). A tabela continua com todos, com a coluna "Válido para a oferta?". A pizza "válido para a oferta?" saiu do Resumo (seria 100% sim). Sem lista de aptos carregada, os gráficos usam o conjunto inteiro, porque não dá para separar. O recorte é a opção `recorteGraficos` do `ModalPessoasAtm`; o ATM não usa e não muda.
- **Como testar:** entrar como master, abrir o card Leads da aba THB vencidos, marcar um lead de teste, conferir que o card Leads cai em 1 e que o lead some da Evolução e do Resumo; desmarcar e conferir que volta.
- **Validação:** `tsc`, `lint`, `lint:tokens`, `vitest` em `modules/infra/acoes` e `modules/infra/atm` (129 testes) e `build` passaram.

## Acesso aos dashboards da Infra · 15/10/2026

Usuários autenticados da equipe podem abrir `/infra/dashboards` e consultar os dashboards CSM, Ações da Black e Escritório/ATM sem vínculo ao departamento Infra ou à capacidade `financeiro.ver`. O menu exibe um grupo próprio **Dashboards** para quem não tem acesso à Infra. A página inicial da Infra e o Laboratório mantêm a verificação de departamento.

Os totais e gráficos permanecem visíveis. As listas com nome, e-mail ou telefone exigem `contato.ver`: isso inclui o detalhe de leads da Black e as listas de leads, pré-checkout e vendas do ATM e de Ações. Sem a capacidade, o front não solicita essas listas e apresenta aviso de acesso restrito. Marcar ou desmarcar registros como teste continua limitado a master.

As RPCs não verificam `infra` nem `financeiro.ver`; exigem perfil ativo da equipe `@advmais.com` e dashboard ativo. As RPCs das listas pessoais do ATM também validam `contato.ver`; `dados_black_leads` ainda não faz essa validação no banco, então a tela evita solicitar seus detalhes quando a capacidade falta. Nenhuma alteração de banco foi feita.

## Ingresso no grupo por números únicos · 15/10/2026

- **Taxa:** nos cards `Ingresso no grupo` e `% ingresso no grupo`, a tela usa diretamente `dados_atm_resumo.grupo_entradas` e `dados_atm_resumo.grupo_pct`. Não recalcula a taxa pelo campo `eh_lead` de `dados_atm_grupo_numeros`; por isso a taxa pode passar de 100% quando há mais números no grupo que leads.
- **Modal:** o card `Ingresso no grupo` abre a aba `Leads`, uma linha por número único retornado por `dados_atm_grupo_leads`, ordenada pelo banco por `entrou_em` decrescente. A tabela apresenta nome, e-mail, telefone, turma, instrução, origem, entrada, saída e se o número permanece no grupo. `entrada_aproximada` aparece como “data aproximada”. Origem é exibida como “Lista do disparo”, “Base de leads” ou “Não encontrado”. Para `nao_encontrado`, o front mantém somente o telefone; os outros campos ficam vazios.
- **Permissão:** sem `contato.ver`, o modal mantém a contagem do resumo e não solicita a RPC com contatos. Se a leitura retornar `42501`, a mensagem pede `contato.ver`.
- **Contrato e estado:** `dados_atm_grupo_leads(p_chave, p_de?, p_ate?)` pertence ao contrato do Galego para `black-thb-2026-10`; a migration `20261015210000` foi aplicada em 15/10/2026 às 18:35 UTC. O front não grava nem altera dados no banco.
- **Como testar:** `cd web && npx vitest run modules/infra/atm/infrastructure/atm-data.test.ts` cobre chamada sem período (período do evento), os campos da lista, mascaramento de linhas não encontradas, taxa acima de 100%, `42501` e `PGRST202`. Para revisar visualmente sem PII, suba local com `NEXT_PUBLIC_BLACK_DEMO=1`, entre em Ações da Black > THB vencidos e abra o card Ingresso no grupo; a tabela usa contatos fictícios e exibe o aviso de demonstração. Sem a capacidade `contato.ver`, confirme que o total permanece visível e que a lista não é consultada. Para validação real pós-aplicação, use usuário com `contato.ver`; sem essa permissão a RPC retorna `42501` e a tela pede a capacidade.

Nenhuma alteração de banco foi feita. O banco já confirmou 13 linhas: 10 `lista_disparo`, 1 `base_leads` e 2 `nao_encontrado`. Esses totais servem para validar a leitura autorizada; não foram copiados como números fixos para a tela.

Para testar: autenticar com perfil ativo da equipe sem vínculo Infra nem `financeiro.ver`, abrir `/infra/dashboards`, entrar em CSM, Ações da Black e Escritório/ATM e conferir os indicadores. Abrir o detalhe de leads sem `contato.ver`: os totais continuam disponíveis e a lista não aparece. Confirmar que os controles de marcar teste não aparecem para não master. Abrir `/infra` e `/infra/laboratorio` com o mesmo perfil e confirmar que seguem restritos.

## Gráficos vivos no modal de Leads · 15/10/2026

- **Por quê:** o Victor achou os gráficos do modal de Leads "muito estáticos", e a Evolução era um ponto solto sem tooltip (com 1 ou 2 dias de dado, uma linha não desenha nada).
- **O que mudou** (só no modal da Black; o ATM não liga a opção `graficosInterativos` do `ModalPessoasAtm` e segue igual):
  - **Animação:** fatias crescem do zero, barras sobem, a linha do acumulado se desenha; ao filtrar, a Evolução anima de novo. Respeita `prefers-reduced-motion` (animação desligada).
  - **Destaque no cursor:** a fatia sob o cursor engrossa, as outras esmaecem e um tooltip mostra o nome, a contagem e o %. O centro da rosca mostra o número da fatia em foco. Na Evolução o dia sob o cursor fica marcado, com tooltip da data (dia da semana incluso), "No dia" e "Acumulado". Funciona por toque e por teclado (Tab na legenda; setas esquerda/direita percorrem os dias).
  - **Clique filtra:** clicar numa fatia (ou no item da legenda) da aba Resumo filtra os outros gráficos, a Evolução e a tabela de Leads. Clicar de novo desfaz; clicar em outro valor do mesmo campo troca; campos diferentes se somam (E). O gráfico do próprio campo mostra todas as opções, com a escolhida em destaque. O filtro ativo aparece numa faixa acima das abas, com um chip por filtro (clique remove) e "Limpar filtros", e vale em todas as abas. Fechar o modal limpa os filtros.
  - **Evolução refeita:** barras por dia (eixo esquerdo) + linha do acumulado (eixo direito). O eixo vai do primeiro lead até hoje e cobre no mínimo 7 dias terminando em hoje, então 1 ou 2 dias de dado não viram ponto solto. O eixo não encolhe quando há filtro (é calculado sobre o conjunto sem filtro). Tem 1 ponto por dia, incluindo os dias zerados.
- **Decisões:**
  - SVG próprio, sem biblioteca nova: o v2 não usa nenhuma de gráfico (`web/package.json`) e a rosca/barras já eram SVG.
  - A regra do filtro é função pura em `modules/infra/atm/domain/filtro-graficos.ts` (com `filtro-graficos.test.ts`), no `atm/domain` porque o `ModalPessoasAtm` mora lá. O `filtro-cruzado.ts` de `infra/dados` tem campos fixos de outra tela e não foi alterado.
  - A tabela de Leads filtra por qualquer campo do Resumo (utm_source, Estado, Instrução, Turma) e continua mostrando também os não válidos; o contador do modal e o aviso de divergência do card seguem sobre o conjunto sem filtro.
  - **Clicar numa barra da Evolução filtra por aquele dia** (campo `Dia`, mesmo chip e mesmo "Limpar filtros"; a Evolução mantém os outros dias visíveis, com o escolhido em destaque, e os demais gráficos e a tabela mostram só aquele dia). Pelo teclado, setas percorrem os dias e Enter filtra. O tooltip fica sempre dentro da área do gráfico (abre para baixo quando não há espaço em cima).
- **Situação:** na branch `victor-acoes-graficos-interativos`, sem merge e sem deploy. Nenhuma mudança de banco.
- **Como testar:** `npx vitest run modules/infra/acoes modules/infra/atm`, `npx tsc --noEmit`, `npm run lint:tokens`, `npm run build`. Na tela (Infra > Dashboards > Academy > Ações de Renovação da Black Friday > card Leads > Resumo): clique em "Unnichat" na rosca de utm_source e confira que as outras roscas, a Evolução e a aba Leads passam a mostrar só esses leads, e que o chip/"Limpar filtros" desfaz. Passe o cursor nas fatias e nos dias da Evolução para ver o tooltip.

## Marcar número do grupo como teste · 15/10/2026

- **Por quê:** o Victor queria marcar teste também no modal de Ingresso no grupo, não só no de Leads.
- **O que mudou:** no modal de Ingresso no grupo, master vê a coluna "Teste" com "Marcar como teste" e uma confirmação. Chama `dados_marcar_teste` com a etiqueta da ação e **só o telefone do grupo** (`foneGrupo`). O banco aceita número que só está no grupo (`dados.atm_pertence`, tipo `fone`, olha `v_grupo_pessoas_todos`) e grava em `dados.marcacoes_teste` (tipo `fone`, 8 últimos dígitos). Sem banco novo.
- **Efeito:** o número some da lista (`dados_atm_grupo_leads` já exclui `teste`) e sai do ingresso geral do card (`grupo_entradas` do resumo também exclui). Se o número for lead, sai dos leads também.
- **Desfazer:** a lista do grupo não traz os testes, então não há "Desmarcar" nela. Se o número for lead, desmarca no modal de Leads com "incluir testes" ligado; se não for, só por SQL (`dados_desmarcar_teste`).
- **Como testar:** master, aba da ação, card Ingresso no grupo, marcar um número; a linha some e o card cai em 1.
- **Validação:** `tsc`, `eslint` em `modules/infra/acoes`, `lint:tokens` e `vitest` de `acoes` + `atm` (143) passaram. Não testado na tela publicada.

## Evolução diária do ingresso no grupo (16/10/2026)

O modal do card "Ingresso no grupo" ganhou a aba "Evolução diária" e o card "% ingresso no grupo" também abre o modal (direto nessa aba). A aba usa a série diária já carregada (`dados_atm_serie_diaria`) e o componente compartilhado `web/modules/infra/ingresso-grupo/`. Regra e situação por dashboard: `docs/dashboard-presencial-tela.md`, seção "Padrão: card de ingresso no grupo tem modal com evolução diária".
