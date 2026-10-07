// Modelos de funil prontos e tipos de projeto ("Comecei um novo projeto").
// Um projeto cria de uma vez os funis certos, com a chave do projeto nas campanhas (a mesma chave do
// ClickUp, do Drive e do utm_campaign — padrão da casa).
import { etapasPadrao } from './funis';
import type { Agrupador, EtapaFunil, Funil, ModeloFunil, ModeloProjeto, ProdutoKey, TipoProjeto } from './types';

const e = (nome: string, papel: EtapaFunil['papel'], cor: EtapaFunil['cor'], atencao: number | null, critico: number | null, criterio = '', campos: EtapaFunil['camposObrigatorios'] = []): Omit<EtapaFunil, 'id'> =>
  ({ nome, papel, cor, slaAtencaoMin: atencao, slaCriticoMin: critico, criterio, camposObrigatorios: campos });
const H = 60;
const D = 24 * H;
const QUALI: EtapaFunil['camposObrigatorios'] = ['perfil_profissional', 'atua_com_holding', 'produto_interesse'];

const vendaAtiva = (): Omit<EtapaFunil, 'id'>[] =>
  etapasPadrao('x').map((et) => ({ nome: et.nome, papel: et.papel, cor: et.cor, slaAtencaoMin: et.slaAtencaoMin, slaCriticoMin: et.slaCriticoMin, criterio: et.criterio, camposObrigatorios: et.camposObrigatorios }));

export const MODELOS_FUNIL: ModeloFunil[] = [
  {
    id: 'venda_ativa', nome: 'Venda ativa', icone: 'kanban', tipo: 'manual', eventosHotmart: [],
    descricao: 'As 6 etapas do playbook. Onde o comercial trabalha lead que pediu contato ou veio de lista.',
    etapas: vendaAtiva(),
    campanhas: [{ nome: 'Captação {chave}', canal: 'utm', regra: 'utm_campaign = {chave}', ativa: true }],
  },
  {
    id: 'checkout', nome: 'Checkout e recuperação', icone: 'zap', tipo: 'hotmart',
    eventosHotmart: ['carrinho_abandonado', 'cartao_recusado', 'compra_em_aberto', 'expirada'],
    descricao: 'Nasce sozinho da Hotmart. Ligação em até 15 minutos; cartão recusado é problema de meio de pagamento, não objeção.',
    etapas: [
      e('Ligar em até 15 min', 'primeiro_contato', 'red', 10, 15, 'Atendeu ou respondeu'),
      e('Em conversa', 'qualificar', 'cyan', 4 * H, D, 'Entendeu o que travou'),
      e('Link novo enviado', 'negociar', 'accent', 12 * H, 2 * D, 'Escolheu a forma de pagamento'),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Recuperado', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Checkout {chave}', canal: 'hotmart', regra: 'Eventos de checkout das ofertas de {chave}', ativa: true }],
  },
  {
    id: 'captacao_mql', nome: 'Captação e MQL', icone: 'target', tipo: 'manual', eventosHotmart: [],
    descricao: 'Acompanha o MQL da pesquisa até o evento (três toques: mensagem, ligação na sexta, link no privado).',
    etapas: [
      e('Respondeu a pesquisa', 'primeiro_contato', 'info', D, 2 * D, 'Toque 1 enviado'),
      e('Toque 1: salvou o número', 'qualificar', 'cyan', 3 * D, 5 * D, 'Ligação feita', QUALI),
      e('Ligação de confirmação', 'apresentar_oferta', 'purple', D, 2 * D, 'Confirmou presença'),
      e('Presença confirmada', 'negociar', 'accent', null, null, 'Assistiu ao vivo'),
      e('Assistiu e comprou', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Pesquisa MQL {chave}', canal: 'formulario', regra: 'Pesquisa de qualificação de {chave} com perfil MQL', ativa: true }],
  },
  {
    id: 'pos_carrinho', nome: 'Recuperação pós-carrinho', icone: 'rotate', tipo: 'manual', eventosHotmart: [],
    descricao: 'Quem assistiu e não comprou. Primeiro quem respondeu e ficou sem retorno; C e D só depois de A e B zeradas.',
    etapas: [
      e('A abordar', 'primeiro_contato', 'neutral', D, 2 * D, 'Mensagem 1 enviada'),
      e('Tentando contato', 'qualificar', 'info', D, 2 * D, 'Respondeu'),
      e('Em conversa', 'apresentar_oferta', 'cyan', D, 3 * D, 'Pediu condição ou link'),
      e('Vai comprar', 'negociar', 'accent', 2 * D, 5 * D, 'Escolheu a forma de pagamento', ['objecao_principal']),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Ganho', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Fila de recuperação {chave}', canal: 'manual', regra: 'Fila montada no fechamento do carrinho de {chave}', ativa: true }],
  },
  {
    id: 'quentes', nome: 'Quentes primeiro', icone: 'flame', tipo: 'manual', eventosHotmart: [],
    descricao: 'Logo depois da aula gravada: quem clicou no link, depois quem só leu, depois quem nem abriu.',
    etapas: [
      e('Clicou no link', 'primeiro_contato', 'red', 30, 2 * H, 'Recebeu contato'),
      e('Em conversa', 'qualificar', 'cyan', 12 * H, D, 'Objeção identificada', QUALI),
      e('Negociando', 'negociar', 'accent', D, 3 * D, 'Escolheu pagamento'),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Ganho', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Aula {chave}', canal: 'utm', regra: 'utm_campaign = {chave}', ativa: true }],
  },
  {
    id: 'webinar', nome: 'Inscritos do webinar', icone: 'video', tipo: 'manual', eventosHotmart: [],
    descricao: 'Webinar perpétuo: inscrição, presença e oferta no pitch.',
    etapas: [
      e('Inscrito', 'primeiro_contato', 'info', 2 * H, D, 'Lembrete enviado'),
      e('Assistiu', 'qualificar', 'cyan', D, 2 * D, 'Conversa aberta', QUALI),
      e('Oferta apresentada', 'apresentar_oferta', 'purple', 2 * D, 3 * D, 'Pediu link'),
      e('Negociar', 'negociar', 'accent', 3 * D, 7 * D, 'Escolheu pagamento', ['objecao_principal']),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Ganho', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Webinar {chave}', canal: 'webhook', regra: 'Inscrição na página do webinar {chave}', ativa: true }],
  },
  {
    id: 'sessao_viabilidade', nome: 'Sessão de Viabilidade', icone: 'calendar', tipo: 'manual', eventosHotmart: [],
    descricao: 'Escada A (cliente final): agendar, realizar e propor o croqui. Valor pago abate no degrau seguinte.',
    etapas: [
      e('Agendar a sessão', 'primeiro_contato', 'info', 30, 2 * H, 'Sessão marcada'),
      e('Sessão marcada', 'qualificar', 'cyan', 3 * D, 5 * D, 'Sessão realizada', QUALI),
      e('Sessão realizada', 'apresentar_oferta', 'purple', D, 3 * D, 'Croqui proposto'),
      e('Proposta do croqui', 'negociar', 'accent', 3 * D, 7 * D, 'Família decidiu', ['objecao_principal']),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Sessão paga', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Seminário {chave}', canal: 'utm', regra: 'utm_campaign = {chave}', ativa: true }],
  },
  {
    id: 'croqui_implantacao', nome: 'Croqui e implantação', icone: 'briefcase', tipo: 'manual', eventosHotmart: [],
    descricao: 'Escada A depois da sessão: croqui estrutural e implantação da holding.',
    etapas: [
      e('Croqui em elaboração', 'qualificar', 'cyan', 5 * D, 10 * D, 'Croqui apresentado'),
      e('Croqui apresentado', 'apresentar_oferta', 'purple', 3 * D, 7 * D, 'Proposta de implantação enviada'),
      e('Negociar implantação', 'negociar', 'accent', 5 * D, 14 * D, 'Contrato aceito', ['objecao_principal']),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', 2 * D, 5 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Implantação contratada', 'fechado', 'green', null, null),
    ],
    campanhas: [],
  },
  {
    id: 'presenca_evento', nome: 'Confirmação de presença', icone: 'user-check', tipo: 'manual', eventosHotmart: [],
    descricao: 'Evento presencial: quem comprou o ingresso confirma presença e vira oportunidade da oferta do evento.',
    etapas: [
      e('Ingresso comprado', 'primeiro_contato', 'info', D, 2 * D, 'Contato feito'),
      e('Presença confirmada', 'qualificar', 'cyan', null, null, 'Fez check-in', QUALI),
      e('Presente no evento', 'apresentar_oferta', 'purple', null, null, 'Recebeu a oferta'),
      e('Negociar no evento', 'negociar', 'accent', 12 * H, D, 'Escolheu pagamento'),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Vendido', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Ingressos {chave}', canal: 'hotmart', regra: 'Compra aprovada do ingresso de {chave}', ativa: true }],
  },
  {
    id: 'ascensao', nome: 'Ascensão de aluno', icone: 'trending-up', tipo: 'manual', eventosHotmart: [],
    descricao: 'Aluno que está pronto para o próximo degrau (HT → HM, HM → Aurum). Dono a definir com a Educação.',
    etapas: [
      e('Sinal de ascensão', 'primeiro_contato', 'info', 2 * D, 5 * D, 'Conversa marcada'),
      e('Conversa de diagnóstico', 'qualificar', 'cyan', 3 * D, 7 * D, 'Momento entendido', QUALI),
      e('Proposta do degrau', 'apresentar_oferta', 'purple', 3 * D, 7 * D, 'Pediu condição'),
      e('Negociar', 'negociar', 'accent', 5 * D, 14 * D, 'Escolheu pagamento', ['objecao_principal']),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Subiu de degrau', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Ascensão {chave}', canal: 'manual', regra: 'Lista de alunos indicada pela Educação', ativa: true }],
  },
  {
    id: 'atm_ativacao', nome: 'Ativação comercial (pré-checkout)', icone: 'phone', tipo: 'manual', eventosHotmart: [],
    descricao: 'Régua de pré-checkout do ATM: quem foi ao checkout em eventos anteriores e não comprou recebe a API do caso; o comercial liga (recebeu? assistiu?) e convida para a live.',
    etapas: [
      e('Lista recebida', 'primeiro_contato', 'neutral', D, 2 * D, 'Ligação feita: recebeu a API do caso?'),
      e('Contato feito', 'qualificar', 'info', D, 2 * D, 'Recebeu e assistiu ao caso; convite para a live feito', QUALI),
      e('Convidado para a live', 'qualificar', 'cyan', D, 2 * D, 'Confirmou que vai à live'),
      e('Presença confirmada', 'apresentar_oferta', 'purple', null, null, 'Esteve na live e ouviu a oferta'),
      e('Ofertado no fechamento', 'negociar', 'accent', 2 * H, 6 * H, 'Escolheu a forma de pagamento até 23h59 do dia da live'),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', D, 2 * D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Fechado na live', 'fechado', 'green', null, null),
    ],
    campanhas: [
      { nome: 'API do caso {chave}', canal: 'disparo', regra: 'Pré-checkout de {chave}: foi ao checkout em eventos anteriores, não comprou e recebeu a API com o estudo de caso', ativa: true },
      { nome: 'Base antiga {chave}', canal: 'disparo', regra: 'Reativação da base antiga (e-mail e grupos antigos) para a live de {chave}, sem quem reagiu ao último ATM', ativa: true },
      { nome: 'Grupo {chave}', canal: 'formulario', regra: 'Inscrito no formulário de {chave} que entrou no grupo de WhatsApp da live', ativa: true },
    ],
  },
  {
    id: 'atm_fechamento', nome: 'Fechamento da live', icone: 'hourglass', tipo: 'hotmart',
    eventosHotmart: ['carrinho_abandonado', 'cartao_recusado', 'compra_em_aberto'],
    descricao: 'Nasce sozinho da Hotmart: checkout da oferta da live. A condição especial vale até 23h59 do mesmo dia, então a ligação é na hora.',
    etapas: [
      e('Ligar agora (vale até 23h59)', 'primeiro_contato', 'red', 5, 15, 'Atendeu ou respondeu'),
      e('Em conversa', 'qualificar', 'cyan', 30, 2 * H, 'Entendeu o que travou'),
      e('Link da condição enviado', 'negociar', 'accent', H, 3 * H, 'Escolheu a forma de pagamento antes das 23h59'),
      e('Aguardar pagamento', 'aguardar_pagamento', 'yellow', 12 * H, D, 'Pagamento aprovado', ['forma_pagamento']),
      e('Recuperado', 'fechado', 'green', null, null),
    ],
    campanhas: [{ nome: 'Oferta da live {chave}', canal: 'hotmart', regra: 'Checkout da oferta da live de {chave}: condição especial com escassez até 23h59 do dia da live', ativa: true }],
  },
];

/** Boas práticas do ATM (gp-operacoes: projetos/2026-09-seminario-atm e a decisão de 09/09/2026 da cadência de 15 dias). */
export const CHECKLIST_ATM = [
  'Replay e treplay são internos: não divulgar o replay para a base',
  'Excluir da lista quem reagiu ao último ATM',
  'Não colidir com o Seminário: ATM e Seminário a cada 15 dias, alternando semana a semana',
  'Ligações do comercial para a lista de pré-checkout a partir de D-5',
  'Oferta, condição especial e escassez (até 23h59 do dia) prontas antes da live',
  'Teto de 30 a 50 conversas novas por dia por número na Meta',
];

export const MODELOS_PROJETO: ModeloProjeto[] = [
  {
    tipo: 'lancamento_classico', nome: 'Lançamento clássico', icone: 'megaphone',
    descricao: 'Captação, CPLs, carrinho aberto e recuperação.',
    funis: ['captacao_mql', 'venda_ativa', 'checkout', 'pos_carrinho'],
    checklist: [
      'Oferta vigente definida (preço, forma de pagamento e prazo) antes de abrir o carrinho',
      'Links rastreáveis por vendedor criados (SCK com a sigla)',
      'Escala do plantão comercial publicada para os dias de evento e carrinho',
      'Script de abordagem e de checkout abandonado escritos até D-10',
      'Supressões combinadas com a Mensageria: a mesma pessoa não recebe régua e cadência no mesmo dia',
    ],
  },
  {
    tipo: 'lancamento_meteorico', nome: 'Lançamento semanal gravado (meteórico)', icone: 'zap',
    descricao: 'Aula gravada, carrinho curto: quentes primeiro, logo depois da aula.',
    funis: ['quentes', 'venda_ativa', 'checkout'],
    checklist: [
      'Lista de quem clicou no link pronta no fim da aula',
      'Teto de 30 a 50 conversas novas por dia por número',
      'Oferta vigente e prazo real do carrinho (não inventar lote)',
    ],
  },
  {
    tipo: 'webinar_perpetuo', nome: 'Webinar / perpétuo', icone: 'video',
    descricao: 'Inscrição contínua, presença e oferta no pitch.',
    funis: ['webinar', 'venda_ativa', 'checkout'],
    checklist: ['Webhook da página de inscrição ligado', 'Lembrete antes da sessão configurado na Mensageria'],
  },
  {
    tipo: 'seminario', nome: 'Seminário (Escada A)', icone: 'calendar',
    descricao: 'Cliente final: Sessão de Viabilidade, croqui e implantação.',
    funis: ['captacao_mql', 'sessao_viabilidade', 'croqui_implantacao', 'checkout'],
    checklist: [
      'Critério de MQL escrito (patrimônio, idade) antes da captação',
      'Agenda de sessões com capacidade por escritório',
      'Nunca misturar escada A e escada B na mesma conversa',
    ],
  },
  {
    tipo: 'evento_presencial', nome: 'Evento presencial (Imersão, ETHB)', icone: 'user-check',
    descricao: 'Ingresso, presença, venda no evento e recuperação depois.',
    funis: ['presenca_evento', 'checkout', 'pos_carrinho'],
    checklist: ['Lista de presentes exportada no fim de cada dia', 'Fila de recuperação dos presentes que não compraram em até 48 h'],
  },
  {
    tipo: 'ascensao_aluno', nome: 'Ascensão de aluno', icone: 'trending-up',
    descricao: 'Alunos que sobem de degrau: HT → HM → Aurum.',
    funis: ['ascensao'],
    checklist: ['Dono definido com a Educação (Isabela) antes de abordar', 'Faturamento declarado conferido'],
  },
  {
    tipo: 'atm', nome: 'ATM (aula ao vivo de entrada)', icone: 'mic',
    descricao: 'Uma live sobre a base que já existe, sem captação paga; fechamento na própria live.',
    funis: ['atm_ativacao', 'atm_fechamento'],
    produtosSugeridos: ['ht', 'sv'],
    checklist: CHECKLIST_ATM,
  },
];

export function modeloFunil(id: string): ModeloFunil | undefined {
  return MODELOS_FUNIL.find((m) => m.id === id);
}

/** Chave de projeto no padrão da casa: minúsculas, sem acento, hífens (ex.: ht34-meteorico-out26). */
export function chaveProjeto(texto: string): string {
  return texto.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

/** Funil pronto (sem id) a partir de um modelo, com a chave do projeto aplicada às campanhas. */
export function funilDoModelo(m: ModeloFunil, opts: { nome?: string; agrupadorId: string; produto: ProdutoKey; chave: string | null; prefixoId: string }): Funil {
  const troca = (s: string) => (opts.chave ? s.replaceAll('{chave}', opts.chave) : s.replaceAll(' {chave}', '').replaceAll('{chave}', ''));
  return {
    id: '', nome: opts.nome ?? m.nome, icone: m.icone, projeto: opts.chave, agrupadorId: opts.agrupadorId, produto: opts.produto,
    tipo: m.tipo, eventosHotmart: [...m.eventosHotmart],
    etapas: m.etapas.map((et, i) => ({ ...et, camposObrigatorios: [...et.camposObrigatorios], id: `${opts.prefixoId}-e${i + 1}` })),
    campanhas: m.campanhas.map((c, i) => ({ ...c, nome: troca(c.nome), regra: troca(c.regra), id: `${opts.prefixoId}-c${i + 1}`, criadoEm: '' })),
    distribuicao: null, ativo: true, criadoEm: '',
  };
}

/** Os funis de um projeto novo, na ordem do modelo, com o nome do projeto na frente. */
export function funisDoProjeto(tipo: TipoProjeto, nomeProjeto: string, agrupador: Agrupador, produto: ProdutoKey): Funil[] {
  const p = MODELOS_PROJETO.find((x) => x.tipo === tipo);
  if (!p) return [];
  const chave = chaveProjeto(nomeProjeto);
  return p.funis
    .map((id) => modeloFunil(id))
    .filter((m): m is ModeloFunil => !!m)
    .map((m, i) => funilDoModelo(m, { nome: `${nomeProjeto} · ${m.nome}`, agrupadorId: agrupador.id, produto, chave, prefixoId: `${chave}-${i + 1}` }));
}

/** Produto ao trocar o tipo: mantém o atual se o tipo serve a ele; senão, o primeiro sugerido (ex.: ATM → HT ou SV). */
export function produtoDoTipo(tipo: TipoProjeto, atual: ProdutoKey): ProdutoKey {
  const sug = MODELOS_PROJETO.find((x) => x.tipo === tipo)?.produtosSugeridos;
  return !sug?.length || sug.includes(atual) ? atual : sug[0];
}
