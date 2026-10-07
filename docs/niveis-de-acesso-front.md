# Níveis de acesso no front

Situação em 07/10/2026: código na branch `victor-captura-pre-checkout`, sem publicação. A fase 0 do banco (`20261007180503`) fornece `public.gp_meu_acesso()`. A flag `NEXT_PUBLIC_ACESSO_V2` começa desligada. Fases 2 e 3, que rebaixam os cargos antigos e removem a regra antiga, dependem da validação do Victor.

## Como funciona

`getCurrentUser()` lê o perfil e, quando a flag está ligada, chama `gp_meu_acesso()` uma vez. O `cache` do React compartilha esse resultado entre layout e página no mesmo request. O front usa `ver`, `editar`, `master` e `capacidades` do contrato. Resposta inválida ou ausente falha fechada; pessoa fora da equipe não entra.

`podeVerDepartamento` confere `ver`. `podeEditarArea` confere `editar`, aceitando o departamento inteiro para o responsável dele, ou `departamento/area` para o membro da área. `financeiro.ver` é necessário para ver o departamento financeiro, Contas a Receber e o dashboard presencial com receita. `financeiro.operar` controla a edição de Contas a Receber. A gestão de usuários fica só para master quando a flag está ligada.

No Marketing, os leitores podem abrir as páginas sem os controles de escrita. Tráfego restringe `?novo=1` e o botão “Novo projeto” a quem edita Tráfego. A página compartilhada “Projetos e páginas” separa a edição de projetos (Tráfego) e páginas (Web). A vista de Tráfego para quem não edita ou não tem `financeiro.ver` mostra só campos sem dinheiro; quem edita Tráfego ainda pode iniciar projeto. Web oculta a instalação da coleta para leitores. Mensageria mostra as vistas de projeto e integrações para leitores. No Comercial, quem não é membro vê só Relatórios; Contatos e Conversas ficam fechados.

Na página de Usuários, masters veem a aba “Departamentos e áreas”. Ela lê `acesso_listar()` e usa `acesso_vincular`, `acesso_desvincular` e `acesso_capacidade_definir`. O banco confere master em cada operação. Erros registrados no console contêm apenas códigos, sem dados de pessoas.

## Como testar

Na pasta `web`, executar `npm run lint`, `npx tsc --noEmit`, `npm test`, `npm run lint:tokens` e `npm run build`. No localhost, manter a flag desligada e confirmar o comportamento antigo. Depois, ligar `NEXT_PUBLIC_ACESSO_V2=true` e reiniciar o Next, pois a variável entra no build. Conferir com contas reais autorizadas: Web abre Tráfego sem “Novo projeto” e `?novo=1` não abre cadastro; Tráfego pode iniciar projeto; leitor do Comercial abre Relatórios, mas não Contatos nem Conversas; sem `financeiro.ver` não vê Contas a Receber nem o dashboard presencial; master vê a aba de gestão. Confirmar que RPCs de escrita negam quem só lê, pois esconder botões não é a fronteira de segurança.

## Pendente

Validar os papéis no navegador com sessões de teste aprovadas e comparar cada resposta RPC com as permissões visíveis. A fase 1 do banco ainda precisa estar aplicada para a leitura dos novos membros funcionar. A fase 2 exige o relatório “quem perde o quê” e o aceite do Victor. Refinar as vistas de leitura de Tráfego e Mensageria para expor mais detalhes sem controles de escrita nem dinheiro.
