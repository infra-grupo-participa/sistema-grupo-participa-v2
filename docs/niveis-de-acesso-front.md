# Níveis de acesso no front

Situação em 07/10/2026: código na branch `victor-captura-pre-checkout`, sem publicação. A fase 0 do banco (`20261007180503`) fornece `public.gp_meu_acesso()`. A fase 2 foi aplicada; a fase 3 está no commit `68fcd64`, ainda sem aplicação no banco. A flag `NEXT_PUBLIC_ACESSO_V2` começa desligada.

## Como funciona

`getCurrentUser()` lê o perfil e, quando a flag está ligada, chama `gp_meu_acesso()` uma vez. O `cache` do React compartilha esse resultado entre layout e página no mesmo request. O front usa `ver`, `editar`, `master` e `capacidades` do contrato. Resposta inválida ou ausente falha fechada; pessoa fora da equipe não entra.

`podeVerDepartamento` confere `ver`. `podeEditarArea` confere `editar`, aceitando o departamento inteiro para o responsável dele, ou `departamento/area` para o membro da área. `financeiro.ver` é necessário para ver o departamento financeiro, Contas a Receber e o dashboard presencial com receita. `financeiro.operar` controla a edição de Contas a Receber. A gestão de usuários fica só para master quando a flag está ligada.

No Marketing, os leitores podem abrir as páginas sem os controles de escrita. Tráfego restringe `?novo=1` e o botão “Novo projeto” a quem edita Tráfego. A página compartilhada “Projetos e páginas” separa a edição de projetos (Tráfego) e páginas (Web). Sem `financeiro.ver`, Tráfego usa `mkt_projetos_listar` e não chama `trafego_resumo` nem `trafego_projeto`, pois essas respostas contêm receita. A vista mostra projetos e permite iniciar projeto para o editor. Web oculta a instalação da coleta para leitores. Mensageria mostra as vistas de projeto e integrações para leitores. No Comercial, quem não é membro vê só Relatórios; Contatos e Conversas ficam fechados.

Na página de Usuários, masters veem a aba “Departamentos e áreas”. Ela lê `acesso_listar()` e usa `acesso_vincular`, `acesso_desvincular` e `acesso_capacidade_definir`. O banco confere master em cada operação. Erros registrados no console contêm apenas códigos, sem dados de pessoas.

Com a flag ligada, a página e as rotas `/api/admin/usuarios` e `/api/admin/usuarios/link` exigem `gp_meu_acesso().master`. O formulário antigo deixa de editar cargo, áreas, funções e a coluna `pode_ver_cpf_completo`. Convites criam o perfil sem escrever esses campos; depois o master atribui departamento e área com `acesso_vincular` e CPF com `acesso_capacidade_definir` usando `cpf.ver`. A API rejeita tentativas de enviar os campos antigos. Status, nome e time continuam na edição do perfil. Configurações oculta a edição do próprio nome para quem não é master e salva apenas avatar; a fase 3 do banco também barra alteração direta do próprio nome. Com a flag desligada, a interface e as rotas seguem as regras anteriores.

## Como testar

Na pasta `web`, executar `npm run lint`, `npx tsc --noEmit`, `npm test`, `npm run lint:tokens` e `npm run build`. No localhost, manter a flag desligada e confirmar o comportamento antigo. Depois, ligar `NEXT_PUBLIC_ACESSO_V2=true` e reiniciar o Next, pois a variável entra no build. Conferir com contas reais autorizadas: Web abre Tráfego sem “Novo projeto” e `?novo=1` não abre cadastro; Tráfego pode iniciar projeto; leitor do Comercial abre Relatórios, mas não Contatos nem Conversas; sem `financeiro.ver` não vê Contas a Receber nem o dashboard presencial; master vê a aba de gestão. Na página Usuários, tentar enviar `cargo` ou `pode_ver_cpf_completo` à API deve retornar 400; sem master, GET, PATCH, POST e geração de link retornam 403. Convidar uma pessoa e vincular seu departamento e `cpf.ver` pela aba nova. Em Configurações, verificar que quem não é master edita avatar sem campo de nome. Confirmar que RPCs de escrita negam quem só lê, pois esconder botões não é a fronteira de segurança.

## Pendente

Validar os papéis no navegador com sessões de teste aprovadas e comparar cada resposta RPC com as permissões visíveis. Aplicar e validar a fase 3 antes de ligar a flag em ambiente publicado. Refinar as vistas de leitura de Tráfego e Mensageria para expor mais detalhes sem controles de escrita nem dinheiro.
