# Ajuste rápido do CRM: erro dos "mais de 2.500 contatos" (06/10/2026)

> Só código das telas e da camada de acesso (`web/modules/comercial/**`). **Nenhuma migration, nada no banco.**
> Autorizado pelo Victor em 06/10/2026. É o "passo 1" do diagnóstico; o "passo 2" (correção definitiva) está no fim.

## O problema

- A camada de acesso lia a lista **inteira** de contatos em páginas de 100, com teto de 25 páginas (2.500). O gestor
  enxerga 2.648 contatos (a importação Hotmart desde 01/01/2026 criou 2.640 ganhos em 06/10), passou do teto e 10 telas
  mostravam `Lista grande demais para carregar de uma vez (crm_contatos: mais de 2500).` Os vendedores estavam a
  ~250/300 contatos do mesmo teto.
- A tela Contatos, depois de carregar a lista, chamava `repo.jornada(id)` (RPC `crm_jornada`, ~167 ms cada) **para cada
  contato, todas em paralelo**, só para preencher "Lançamentos" e "Última interação". Para um vendedor seriam ~2.200
  chamadas simultâneas por abertura da tela: enche o pool de conexões do Supabase e deixa lento todo sistema que usa o
  mesmo banco (Central de Alunos, Financeiro etc.).

## O que mudou

1. **Tela Contatos sem histórico em massa** (`ui/contatos/ContatosClient.tsx`). A lista não chama mais a jornada de
   ninguém. O histórico só é buscado ao abrir a ficha da pessoa (`ContatoDrawer`), uma chamada `crm_jornada` por
   contato aberto, como já era.
   - "Última interação" passa a vir só dos negócios já carregados (`ultimaInteracaoEm`). Pessoa sem negócio fica em
     branco na lista; a jornada completa continua na ficha.
   - "Lançamentos" fica com um traço na lista (não dá para ordenar por ela por enquanto); o número aparece na ficha, aba
     Jornada. O balão de ajuda da coluna explica isso.
   - **Importante:** isto tinha que vir antes ou junto do aumento de página abaixo; sem isso, destravar o gestor faria a
     tela disparar 2.648 chamadas de uma vez.
2. **Leitura de contatos em lotes de 500** (`infrastructure/supabase-comercial.repository.ts`). `PAGINA_CONTATOS` de 100
   para 500 (máximo que `crm_contatos` aceita) e teto próprio de 20 páginas (`MAX_PAGINAS_CONTATOS`), ou seja
   **10.000 contatos**. Lista do gestor hoje: 6 chamadas em vez de 27. Passou do teto, a tela mostra
   `Lista grande demais para carregar de uma vez (crm_contatos: mais de 10.000 contatos). Avise o time de dados.`
   (nunca corta calado). O teto de negócios e atividades (25 páginas) não mudou.
3. **Fichas laterais: comportamento mantido.** `NegocioDrawer` e `ContatoDrawer` continuam pedindo a lista inteira para
   achar um contato. Motivo: **não existe nenhuma função `crm_*` que devolva um contato pelo id** (conferido nas
   migrations: só `crm_contatos(p_busca, p_limite, p_offset)`, cuja busca é por e-mail, telefone ou nome, nunca por id).
   Criar uma é migration, fora do escopo deste ajuste. Com o lote de 500, cada abertura de ficha custa 6 chamadas em vez
   de 27. A `ContatoDrawer` também usa a lista para o aviso de possível duplicado.
4. **Conferência das outras telas.** Nenhuma outra tela chama o repositório em laço por contato: as demais chamadas por
   pessoa (`repo.mensagens`, `repo.eventos`, `repo.jornada`) são de uma pessoa aberta por vez (ficha, conversa
   selecionada). O MCP executa planos fixos de 1 a poucas RPCs. Continua valendo que **9 telas** (Início, Funil,
   Atividades, Conversas, Recuperação, Disparos, Performance da equipe e as duas fichas) baixam a lista inteira de
   contatos; agora em lotes de 500.

Regra de quem vê o quê e máscara de e-mail/telefone: **não mudaram** (moram na RPC `crm_contatos`, não foi tocada).

## Testes

- `infrastructure/supabase-comercial.repository.test.ts`: 2.648 contatos vêm em 6 chamadas de 500 (offsets 0 a 2.500);
  10.000 ainda carregam; 10.001 dá a mensagem clara; `jornada()` faz 1 chamada só para o id pedido.
- `ui/contatos/chamadas-por-contato.test.ts`: a tela Contatos não chama `repo.jornada` nem `Promise.all`/`map(async)`;
  a ficha chama `repo.jornada(contatoId)` uma vez; nenhuma tela do Comercial chama o repositório dentro de laço.
  É teste sobre o código-fonte (o projeto não tem teste de componente `.tsx`). Conferido que ele falha com o código
  antigo.

## O que fica para a correção definitiva (passo 2, com migration, ensaio e `.explain.md`)

1. **Função paginada no banco**: `crm_contatos_pagina(busca, dono, perfil, uf, tags, opt_out, so_alunos, ordem, dir,
   limite 50, offset)` devolvendo `{itens, total}`. A tela Contatos vira **paginada com filtros e ordenação no
   servidor** (hoje filtra e ordena no navegador), e "Lançamentos" e "Última interação" voltam calculados em lote na
   própria RPC.
2. **Números do topo à parte**: `crm_contatos_resumo()` (total, sem dono, opt-out, alunos) em vez de contar no navegador.
3. **Contatos por id**: `crm_contatos_por_ids(uuid[])` com a mesma visibilidade e máscara de `crm_contatos`, para as
   fichas e para as telas que só precisam do nome dos contatos dos negócios que mostram (ou `crm_negocios` devolver um
   contato mínimo junto). Aí nenhuma tela precisa mais da lista inteira.
4. **Montar contatos em lote**: trocar `pessoas.dados()` chamado linha a linha (270 a 430 ms por página de 100) por um
   join único para o conjunto da página.
5. **Índices**: `crm.pessoa_comercial (criado_em desc, pessoa_id)` e `(dono_id)`.
6. **Listas de negócios e atividades**: `negocios()` e `atividades()` também baixam tudo (3.666 negócios em 06/10,
   teto 50.000). Mesma lógica: filtro por funil e status no banco.
7. Decisão de negócio pendente (D6): vendedor vê os 1.800 contatos sem dono, quase todos só compradores Hotmart.
   **Decidido em 06/10/2026** (Victor): sem dono e sem negócio aberto sai da lista do vendedor e continua na busca;
   os 2.640 ganhos retroativos saem. Ver `hotmart-sem-retroativo-2026-10-06.md` (migration 20261006191824).

Diagnóstico completo: segundo cérebro, `Projetos/sistema-unico/central-de-dados/area-comercial-mapa.md`, seção (c).

## Passo 2: preparado (06/10/2026), migration 20261006m NÃO APLICADA

Migration `infra/supabase/migrations/20261006m_crm_desempenho.sql` (+ `_ensaio.sql` e `.explain.md`), ensaiada em
`begin … rollback` com JWT real de gestor e vendedores: lista, máscara e totais iguais aos de `crm_contatos`, nada
persistiu. Front em `web/modules/comercial` já usa as RPCs novas e volta sozinho ao caminho antigo enquanto elas não
existem. Itens 1 a 6 acima: feitos (5: nenhum índice novo, os necessários já existem; 6: `crm_negocios` já filtrava,
o front passou a usar `p_pessoa` na ficha). Ficam no caminho antigo, por precisarem da base toda: Disparos e
Performance da equipe. Números e decisões: `20261006m.explain.md`.
