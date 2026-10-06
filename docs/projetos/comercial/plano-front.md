# CRM Comercial — plano do front-end

Pedidos do Arthur Galvão em 05/10/2026. O front roda com dados de demonstração; o backend entra depois por trás
de `web/modules/comercial/application/ports.ts`. Regra transversal: **nenhuma tabela com rolagem horizontal**
(lista em cartões ou colunas que quebram linha; detalhe vai para a ficha).

## Onda 1 — fundação (dados e contratos)

| Item | O que muda |
|---|---|
| Jornada da pessoa | Contato vira "pessoa": cada entrada (inscrição em lista, lançamento, campanha com UTM própria), compra, reembolso, pesquisa, grupo, negócio e conversa é um ponto da jornada, com data, fonte e UTM daquela entrada. Uma pessoa tem vários negócios ao longo dos lançamentos |
| Motivos de perda | Saem do código e viram cadastro (os 9 do playbook vêm de fábrica; o gestor cria novos, desativa, marca "volta para reativação" e "vai para bloqueio") |
| Ícone do funil | Campo no funil, escolhido numa grade de ícones |
| Modelos de funil | Biblioteca por tipo de projeto (ver Onda 2) |
| Dashboard por pessoa | Configuração do painel salva por vendedor: cartões, gráficos, ordem e tamanho |
| Notificações | Preferências por pessoa (o que avisa, horário) |

## Onda 2 — telas

| Tela | Entrega |
|---|---|
| Início | Ícone (i) clicável em todo indicador com a definição exata. Gestor escolhe "ver como" um vendedor e vê o painel dele: agir agora, atrasadas, números do dia. Dashboard personalizável: adicionar cartão, criar gráfico, reordenar, redimensionar, esconder |
| Funis | Assistente passo a passo para funil novo (modelo → etapas → campanhas e integrações → distribuição → checklist de boas práticas). Ícone do funil. Modelos prontos. Botão **"Comecei um novo projeto"**: escolhe o tipo e cria de uma vez os funis certos, com a chave do projeto nas campanhas |
| Pessoa (ficha) | Card por pessoa com a jornada completa: todos os lançamentos, cada um com a UTM daquela entrada, listas, compras, reembolsos, pesquisas, grupos, negócios (abertos e encerrados) e conversas |
| Playbook | Submódulo novo no menu do Comercial, com o playbook completo e navegável (inegociáveis, funil, distribuição, canais, disparo, cadência, conversa e objeções, alertas, fechamento do dia, rituais, indicadores, processos, primeiros 30 dias, erros e lições) |
| Configurações | Motivos de perda (cadastro). Integrações: Hotmart, Infobip, Unnichat, Manychat, ActiveCampaign, SendFlow, Slack, Clint (migração), Instagram (social selling, em breve), MCP |
| Notificações no desktop | Notificação do navegador/sistema: lead novo atribuído a mim, lead respondeu, prazo estourado, venda aprovada, ficha para aprovar. Pede permissão uma vez; respeita as preferências |

### Modelos de funil por tipo de projeto (proposta)

| Tipo de projeto | Funis criados |
|---|---|
| Lançamento clássico (CPLs) | Captação e MQL · Venda ativa no carrinho · Checkout e recuperação (Hotmart) · Recuperação pós-carrinho |
| Lançamento semanal gravado / meteórico | Venda ativa · Checkout e recuperação · Quentes primeiro (pós-aula) |
| Webinar / perpétuo | Inscritos do webinar · Venda ativa · Checkout e recuperação |
| Seminário (escada A) | Sessão de Viabilidade · Croqui · Implantação |
| Evento presencial (Imersão, ETHB) | Confirmação de presença · Venda no evento · Recuperação pós-evento |
| Ascensão de aluno | HT → HM · HM → Aurum |

## Onda 3 — depende do backend

| Item | Observação |
|---|---|
| MCP do Comercial | Servidor MCP para o Claude (cloud) consultar e operar o CRM: buscar pessoa, ver funil, criar atividade, mover etapa, fechamento do dia. Precisa do banco: entra junto com o backend |
| Social selling (Instagram) | Conectar perfis (Marcio, Elaine, outros), ler comentários e transformar em lead com um clique. No front entra agora só como área "Em breve" |
| Unnichat / Manychat / Infobip reais | Webhooks de entrada e envio |
