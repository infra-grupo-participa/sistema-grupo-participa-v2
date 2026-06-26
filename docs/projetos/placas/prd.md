# PRD - Mini-Sistema de Placas

> Status: implantado em homologacao, com fluxo operacional ativo
>
> Versao: 5.2
>
> Ultima revisao: 2026-03-26
>
> Escopo: visao geral consolidada do mini-sistema de placas, seus modulos, regras, dados, integracoes e organizacao no repositorio

---

## 1. Visao Geral

O mini-sistema de placas atende o processo de reconhecimento de alunos do ecossistema Holding Total Brasil, desde a entrada publica do cadastro ate a operacao administrativa de auditoria, agendamento, postagem e acompanhamento da entrega.

Ele funciona como um modulo operacional dentro do sistema Grupo Participa e foi estruturado para:

- registrar dados do aluno com clareza;
- separar cadastro simples de fluxo elegivel para placa;
- reduzir operacao manual do time;
- manter rastreabilidade entre formulario, auditoria, entrevista e logistica;
- oferecer leitura administrativa mais segura e mais padronizada.

Hoje o modulo nao e apenas um formulario. Ele ja cobre entrada publica, continuidade de jornada, operacao interna, comunicacao por e-mail, agenda de horarios e rastreio.

---

## 2. Objetivos do Produto

O mini-sistema existe para:

1. captar os dados de alunos interessados em reconhecimento por nivel;
2. validar elegibilidade sem gerar friccao desnecessaria;
3. centralizar a operacao de placas na aba `Solicitacoes`;
4. permitir auditoria, agendamento e logistica no mesmo contexto;
5. reduzir inconsistencias de status, etapas e comunicacao;
6. padronizar navegacao e leitura em todas as paginas do sistema que apontam para o modulo.

---

## 3. Escopo Funcional

### 3.1 Entradas publicas

- formulario publico em `/solicitar-placa`;
- retomada por token;
- validacao de duplicidade por dados unicos;
- preenchimento automatico de endereco por CEP;
- bifurcacao automatica para fluxo curto ou fluxo completo.

### 3.2 Operacao interna

- listagem central de solicitacoes;
- abertura de popup detalhado por aluno;
- avancar e retornar etapas;
- gerenciamento de agenda de horarios;
- atualizacao de codigo de rastreio sem refresh;
- exportacao XLSX para fase operacional de envio.

### 3.3 Comunicacao

- e-mails por etapas relevantes da auditoria;
- e-mail de entrevista;
- exibicao de status e rastreio no acompanhamento do aluno.

---

## 4. Perfis de Uso

### 4.1 Aluno

O aluno utiliza o sistema para:

- iniciar ou retomar seu cadastro;
- informar dados pessoais, nivel e contexto academico;
- enviar comprovacao e declaracao quando aplicavel;
- acompanhar andamento;
- agendar entrevista quando liberado;
- consultar dados de entrega e codigo de rastreio.

### 4.2 Operacao / Admin

O time administrativo utiliza o sistema para:

- revisar solicitacoes recebidas;
- acompanhar o pipeline de auditoria;
- editar dados do candidato;
- controlar disponibilidade de horarios;
- registrar agendamento e rastreio;
- exportar a lista de alunos aptos para confecao e envio.

### 4.3 Visualizador

Usuarios com perfil nao-admin podem consumir a navegacao e a leitura do modulo, mas acoes sensiveis devem continuar restritas ao cargo administrativo.

---

## 5. Mapa de Modulos

| Modulo | Rota | Arquivo principal | Papel |
|---|---|---|---|
| Solicitacao publica | `/solicitar-placa` | `app/solicitar-placa/index.html` | jornada principal do aluno |
| Agendamento | `/agendar-entrevista` | `app/agendar-entrevista/index.html` | escolha e confirmacao de horario |
| Relatorio de placas | `/relatorios/placas` | `app/relatorios/placas/relatorios.html` | operacao administrativa central |
| Confirmacao de horario | `/api/confirm-horario.php` | `app/api/confirm-horario.php` | reserva definitiva do slot |
| E-mail de status | `/api/send-status-email.php` | `app/api/send-status-email.php` | notificacoes transacionais |
| E-mail de entrevista | `/api/send-interview-email.php` | `app/api/send-interview-email.php` | comunicacao da entrevista |
| CEP | `/api/cep.php` | `app/api/cep.php` | lookup padronizado de endereco |

---

## 6. Jornada do Aluno

### 6.1 Entrada

O aluno acessa `/solicitar-placa` e recebe um token publico que permite retomar a jornada sem perder o progresso.

### 6.2 Etapas principais

1. dados pessoais;
2. interesse e contexto;
3. nivel atual e espaco de instrucao;
4. comprovacao financeira;
5. declaracao assinada;
6. endereco de entrega e envio final.

### 6.3 Regras de bifurcacao

- alunos abaixo de `ouro` nao entram no fluxo completo da placa;
- nesses casos, o sistema registra apenas cadastro e grau academico;
- alunos elegiveis seguem para comprovacao, declaracao, endereco, auditoria e entrega.

### 6.4 Continuidade e acompanhamento

A jornada do aluno deve refletir:

- status atualizado;
- liberacao de agendamento quando aplicavel;
- codigo de rastreio quando informado pela operacao;
- mensagens claras sem exposicao de dados de terceiros.

---

## 7. Jornada Operacional

### 7.1 Solicitacoes

`Solicitacoes` e a visao principal do modulo. Toda operacao diaria deve partir dessa aba.

Ela concentra:

- lista de cadastros recebidos;
- filtros por busca, nivel, turma, UF, cidade e status;
- leitura rapida de progresso;
- popup detalhado por registro;
- acoes de auditoria e logistica.

### 7.2 Agenda de Horarios

`Agenda de Horarios` e um subtoptico administrativo do `Relatorio de Placas`.

Ela existe para:

- controlar os horarios ativos;
- refletir indisponibilidade para todos quando um slot for reservado;
- impedir selecao de horario ocupado;
- manter consistencia entre painel e tela publica.

### 7.3 Popup administrativo

Ao abrir um registro, o operador ve:

- perfil do aluno;
- dados financeiros;
- links de comprovacao e declaracao;
- endereco de entrega;
- rastreio e bloco de logistica;
- presenca online;
- timeline da auditoria;
- estado do agendamento;
- acoes operacionais.

---

## 8. Regras de Negocio

### 8.1 Duplicidade

O sistema deve fazer verificacao em tempo real para impedir duplicidade por dados unicos, principalmente e-mail e CPF/CNPJ.

Regra de comunicacao:

- nunca exibir nome de outro cliente;
- usar mensagens neutras como "ja esta em uso" ou "ja possui cadastro".

### 8.2 Elegibilidade

Fluxo completo de placa so existe para alunos elegiveis.

Faixa operacional:

- abaixo de `ouro`: cadastro curto;
- `ouro` e acima: fluxo completo da placa.

### 8.3 Agendamento

O agendamento deve respeitar:

- slots ativos;
- bloqueio visual de horarios ocupados;
- indisponibilidade imediata para todos os usuarios;
- redirecionamento para o cadastro inicial quando a solicitacao nao estiver mais apta ao agendamento.

### 8.4 Rastreio

O codigo de rastreio deve refletir imediatamente no painel e no acompanhamento, sem depender de refresh manual.

### 8.5 Exportacao XLSX

O XLSX deve considerar somente alunos que ja chegaram na etapa operacional de envio da placa. Registros anteriores nao devem aparecer no arquivo.

---

## 9. Modelo de Dados

### 9.1 `thb_placas_solicitacoes`

Tabela principal do fluxo publico.

Campos centrais:

- `token`
- `nome`
- `email`
- `telefone`
- `turma`
- `espaco_instrucao`
- `nivel`
- `faturamento_declarado`
- `proof_url`
- `declaracao_url`
- `cep`
- `logradouro`
- `numero`
- `complemento`
- `bairro`
- `cidade`
- `estado_uf`
- `pais`
- `documento_nf`
- `entrevista_data`
- `entrevista_hora`
- `entrevista_link`
- `meet_link`
- `codigo_rastreio`
- `status`
- `step_index`
- `auditoria_step`
- `created_at`
- `updated_at`

### 9.2 `thb_horarios_disponiveis`

Tabela de agenda operacional.

Campos centrais:

- `dia_semana`
- `hora`
- `ativo`

### 9.3 Base administrativa de apoio

O modulo cruza dados tambem com:

- `thb_alunos`
- `thb_turmas`
- `thb_placas_auditoria`

Esse conjunto alimenta historico, sincronizacao de etapas e leitura administrativa.

---

## 10. Estados do Processo

### 10.1 Status principais

| Status | Significado |
|---|---|
| `rascunho` | jornada iniciada e ainda nao enviada |
| `enviado` | formulario concluido e pronto para analise |
| `em_auditoria` | operacao revisando o caso |
| `docs_aprovados` | caso apto a entrevista ou proxima fase |
| `cadastro_concluido` | cadastro encerrado sem fluxo de placa |
| `concluido` | processo finalizado com entrega ou encerramento positivo |
| `rejeitado` | solicitacao recusada |

### 10.2 Timeline administrativa

A timeline interna cobre, de forma progressiva:

- contato inicial;
- confirmacao de nivel;
- solicitacao de documentos;
- recebimento de documentos;
- aprovacao;
- declaracao;
- dados de entrega;
- entrevista;
- placa postada;
- placa recebida.

---

## 11. UX/UI e Padroes de Operacao

### 11.1 Formulario publico

O formulario deve priorizar:

- clareza de campos;
- textos objetivos;
- validacao em tempo real quando relevante;
- continuidade de jornada;
- responsividade;
- mensagens de erro seguras.

### 11.2 Relatorio administrativo

A experiencia administrativa deve priorizar:

- entrada unica por `Solicitacoes`;
- filtros sempre no contexto correto da listagem;
- popup com hierarquia clara entre titulo, rotulo e valor;
- acoes operacionais junto do bloco correspondente;
- feedback visual imediato ao salvar dados criticos.

### 11.3 Navegacao

Qualquer pagina com grupo `Relatorios` deve seguir o mesmo padrao:

- item pai: `Relatorio de Placas`;
- subtopticos: `Solicitacoes` e `Agenda de Horarios`;
- `Agenda de Horarios` visivel apenas para admin.

---

## 12. Integracoes e Dependencias

| Servico | Uso |
|---|---|
| Supabase Auth | autenticacao administrativa |
| Supabase Database | persistencia principal |
| Supabase Storage | documentos do fluxo |
| ViaCEP | apoio ao preenchimento de endereco |
| APIs PHP | regras operacionais especificas |
| E-mail transacional | comunicacao de status e entrevista |

---

## 13. Arquitetura Tecnica

### 13.1 Stack

- frontend em HTML, CSS e JS vanilla;
- paginas com CSS e JS majoritariamente inline;
- Supabase como autenticacao e banco;
- endpoints PHP em `app/api/` para orquestracao especifica;
- deploy por FTP via GitHub Actions.

### 13.2 Comportamentos tecnicos relevantes

- atualizacoes importantes usam sincronizacao sem refresh;
- a agenda deve refletir conflitos de slot em tempo quase real;
- a listagem de `Solicitacoes` concentra filtros e operacao;
- o painel depende de consistencia entre status, `step_index` e `auditoria_step`.

### 13.3 Restricoes do contexto atual

- nao ha framework frontend;
- parte importante da logica ainda esta concentrada em arquivos HTML longos;
- o ambiente de homologacao e a referencia de validacao antes de promover para producao.

---

## 14. Mapa no Repositorio

### 14.1 Caminhos principais do mini-sistema

| Tipo | Caminho |
|---|---|
| PRD do modulo | `docs/projetos/placas/prd.md` |
| Base de conhecimento geral | `docs/base-de-conhecimento/` |
| Formulario publico | `app/solicitar-placa/index.html` |
| Agendamento | `app/agendar-entrevista/index.html` |
| Relatorio administrativo | `app/relatorios/placas/relatorios.html` |
| Endpoints do modulo | `app/api/` |
| JS compartilhado de navegacao | `app/assets/js/config.js` e `app/assets/js/auth.js` |

### 14.2 Organizacao de pastas

A organizacao recomendada e vigente para o modulo e:

- tudo que vai para deploy permanece em `app/`;
- documentacao permanece em `docs/`;
- conhecimento de apoio e agentes ficam em `docs/base-de-conhecimento/`;
- scripts e infraestrutura nao deploy ficam fora do fluxo do modulo.

Nesta revisao, a base de conhecimento foi alinhada para dentro de `docs/`, reduzindo divergencia entre estrutura real e estrutura documentada.

---

## 15. Ambientes e Deploy

| Ambiente | Branch | Objetivo |
|---|---|---|
| Homologacao | `homologacao` | validar comportamento antes de publicar |
| Producao | `main` | operacao oficial |

Regra operacional:

- qualquer ajuste do mini-sistema deve passar primeiro por homologacao;
- o PRD deve refletir o comportamento homologado mais recente;
- mudancas estruturais de navegacao, fluxo ou dados devem ser registradas aqui.

---

## 16. Estado Atual do Produto

No estado atual, o mini-sistema oferece:

- jornada publica com validacoes e retomada;
- fluxo curto para nao elegiveis;
- operacao centralizada em `Solicitacoes`;
- agenda administrativa integrada ao relatorio;
- e-mails por etapa relevante;
- rastreio atualizado sem refresh;
- filtros operacionais na listagem correta;
- documentacao principal consolidada neste PRD.

Este documento deve servir como referencia de produto, operacao e organizacao tecnica do mini-sistema de placas.
