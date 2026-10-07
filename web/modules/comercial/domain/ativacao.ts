// Funil de Ativação padrão: a primeira jornada do lead na empresa. Todo projeto, de qualquer tipo, ganha um.
// Fonte: gp-operacoes, departamentos/comercial/areas/prospeccao/processos/acompanhar-mql-ate-o-evento.md (três
// toques), com a correção do Arthur de 07/10/2026: o toque 1 sai NA HORA da entrada (inscrição, ingresso ou MQL),
// com o prazo de primeiro contato do playbook (5 min / 15 min, em horário comercial), e não no dia seguinte.
// Regras puras: o banco (migration 20261007135415) repete as que criam atividade e calculam prazo.
import type { ModeloFunil, ProdutoKey } from './types';

const H = 60;
const D = 24 * H;

/** Modelo do funil. Papéis compatíveis com o playbook: a única etapa de Ganho é "Comprou", e só a Hotmart fecha. */
export const MODELO_ATIVACAO: ModeloFunil = {
  id: 'ativacao', nome: 'Ativação', icone: 'user-check', tipo: 'manual', eventosHotmart: [],
  descricao: 'Primeira jornada do lead: quem se inscreveu, comprou o ingresso ou virou MQL recebe os três toques do mesmo vendedor até o evento. Toque 1 na hora da entrada.',
  etapas: [
    { nome: 'Toque 1: falar agora', papel: 'primeiro_contato', cor: 'red', slaAtencaoMin: 5, slaCriticoMin: 15, criterio: 'Mensagem do toque 1 enviada: pediu para salvar o número', camposObrigatorios: [] },
    { nome: 'Salvou o número', papel: 'qualificar', cor: 'cyan', slaAtencaoMin: null, slaCriticoMin: null, criterio: 'Ligação da sexta anterior ao evento feita (5 blocos)', camposObrigatorios: [] },
    { nome: 'Ligação feita', papel: 'qualificar', cor: 'info', slaAtencaoMin: D, slaCriticoMin: 2 * D, criterio: 'Confirmou presença. Sem resposta em 24 h: desapegar', camposObrigatorios: [] },
    { nome: 'Presença confirmada', papel: 'apresentar_oferta', cor: 'purple', slaAtencaoMin: null, slaCriticoMin: null, criterio: 'Esteve ao vivo no evento', camposObrigatorios: [] },
    { nome: 'Compareceu', papel: 'negociar', cor: 'accent', slaAtencaoMin: null, slaCriticoMin: null, criterio: 'Comprou a oferta do evento (Hotmart aprova)', camposObrigatorios: [] },
    { nome: 'Comprou', papel: 'fechado', cor: 'green', slaAtencaoMin: null, slaCriticoMin: null, criterio: '', camposObrigatorios: [] },
  ],
  campanhas: [
    { nome: 'Inscrição {chave}', canal: 'webhook', regra: 'Inscrição no ActiveCampaign que a catalogação de origem liga a {chave}', ativa: true },
    { nome: 'Ingresso {chave}', canal: 'hotmart', regra: 'Compra aprovada do ingresso que a catalogação de origem liga a {chave}', ativa: true },
    { nome: 'Pesquisa MQL {chave}', canal: 'formulario', regra: 'Pesquisa de MQL que a catalogação de origem liga a {chave}', ativa: true },
  ],
};

/** Teto (decisão do Arthur, 07/10/2026): 50 conversas novas por dia, por número. Atenção a partir de 40 (80%). */
export const TETO_CONVERSAS_NOVAS = { atencao: 40, maximo: 50 } as const;

export type FonteAtivacao = 'activecampaign' | 'hotmart' | 'respondi' | 'manual';

export const ROTULO_FONTE_ATIVACAO: Record<FonteAtivacao, string> = {
  activecampaign: 'Inscrição (ActiveCampaign)',
  hotmart: 'Ingresso (Hotmart)',
  respondi: 'Pesquisa (Respondi)',
  manual: 'Manual',
};

/**
 * Ativação de um projeto (crm.projeto_ativacao). Datas em AAAA-MM-DD; hora em HH:MM (Brasília).
 * A qual projeto um evento pertence (lista/tag do AC, produto da Hotmart, UTM…) NÃO mora aqui: é a catalogação de
 * origem (crm.projeto_do_evento), feita à parte.
 */
export interface ProjetoAtivacao {
  projeto: string;
  nome: string;
  funilId: string;
  produto: ProdutoKey;
  eventoInicio: string | null;
  eventoFim: string | null;
  eventoHora: string | null;
  /** Fechamento do carrinho (CRM). Vazio = fim do evento. A Ativação acaba no dia seguinte a ele. */
  carrinhoFim: string | null;
  /** Último dia da Ativação (carrinho ou evento). */
  fimAtivacao: string | null;
  /** As datas do evento vieram do cadastro do Marketing (mkt.projetos), não do CRM. */
  datasDoMarketing: boolean;
  /** Produtos da Hotmart (id) da oferta do evento: compra aprovada = "Comprou" (ganho do negócio de ativação). */
  hotmartOferta: string[];
  ligado: boolean;
  encerradoEm: string | null;
  filaId: string | null;
  /** Negócios abertos por etapa (vendedor: só os dele). */
  porEtapa: Record<string, number>;
  entradasHoje: number;
  mqls: number;
  /** Disparos da Mensageria hoje no projeto (aviso de colisão com a régua). */
  mensageriaHoje: number;
}

/** Carga do dia por vendedor: conversas novas (toque 1) e toques que vencem hoje. */
export interface CargaAtivacao {
  vendedorId: string;
  novasHoje: number;
  toquesHoje: number;
}

export interface PainelAtivacao {
  projetos: ProjetoAtivacao[];
  carga: CargaAtivacao[];
  /** Conversas novas (toque 1) de hoje somando todos: o teto é por NÚMERO, e o número oficial é um só. */
  totalNovasHoje: number;
  /** Interruptor geral (crm.config.ativacao_ligada): desligado, nada entra sozinho. */
  ligada: boolean;
  /** Projetos (chave) que têm funis mas ainda não têm o funil de Ativação. */
  semAtivacao: string[];
}

export type EdicaoAtivacao = Pick<ProjetoAtivacao,
  'projeto' | 'eventoInicio' | 'eventoFim' | 'eventoHora' | 'carrinhoFim' | 'hotmartOferta' | 'ligado'>;

// ── Horário comercial (decisão do Arthur, 07/10/2026) ──
// Seg a sex 8h–20h, sáb 9h–13h, domingo e feriado fechados, Brasília. No banco: crm.config.expediente + crm.feriado
// (a fonte de verdade das atividades). Aqui, o mesmo para a demonstração e os testes.
export const FERIADOS_NACIONAIS = [
  '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25', '2027-01-01', '2027-03-26', '2027-04-21',
  '2027-05-01', '2027-09-07', '2027-10-12', '2027-11-02', '2027-11-15', '2027-11-20', '2027-12-25',
];
const FERIADOS = new Set(FERIADOS_NACIONAIS);

function dataIso(d: Date) { return d.toISOString().slice(0, 10); }

const FUSO_MIN = -3 * 60; // Brasília, sem horário de verão desde 2019
const JANELA: Record<number, [number, number] | null> = { 0: null, 1: [8 * H, 20 * H], 2: [8 * H, 20 * H], 3: [8 * H, 20 * H], 4: [8 * H, 20 * H], 5: [8 * H, 20 * H], 6: [9 * H, 13 * H] };

/** Data e minuto do dia em Brasília. */
function local(d: Date): { dia: Date; min: number; dow: number } {
  const l = new Date(d.getTime() + FUSO_MIN * 60000);
  const dia = new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), l.getUTCDate()));
  return { dia, min: l.getUTCHours() * 60 + l.getUTCMinutes(), dow: l.getUTCDay() };
}

/** Instante (UTC) de um dia local + minutos. */
function instante(dia: Date, min: number): Date {
  return new Date(dia.getTime() + (min - FUSO_MIN) * 60000);
}

/** Agora, se está no expediente; senão a abertura do próximo expediente. */
export function proximoExpediente(agora: Date): Date {
  const { dia, min, dow } = local(agora);
  for (let i = 0; i < 15; i++) {
    const j = JANELA[(dow + i) % 7];
    const d = new Date(dia.getTime() + i * D * 60000);
    if (!j || FERIADOS.has(dataIso(d))) continue;
    if (i === 0) {
      if (min < j[0]) return instante(d, j[0]);
      if (min < j[1]) return agora;
      continue;
    }
    return instante(d, j[0]);
  }
  return agora;
}

export function emExpediente(agora: Date): boolean {
  return proximoExpediente(agora).getTime() === agora.getTime();
}

// ── Agenda dos três toques ──

const deIso = (s: string) => new Date(`${s}T00:00:00Z`);

/** A sexta-feira ANTERIOR ao início do evento (se o evento começa na sexta, é a da semana anterior). */
export function sextaAnterior(eventoInicio: string): string {
  const d = deIso(eventoInicio);
  const volta = ((d.getUTCDay() - 5 + 7) % 7) || 7;
  return dataIso(new Date(d.getTime() - volta * D * 60000));
}

/** Dias do evento, do início ao fim (fim nulo = um dia). */
export function diasDoEvento(inicio: string, fim: string | null): string[] {
  const a = deIso(inicio).getTime();
  const b = deIso(fim ?? inicio).getTime();
  const dias: string[] = [];
  for (let t = a; t <= b && dias.length < 7; t += D * 60000) dias.push(dataIso(new Date(t)));
  return dias;
}

export type ToqueKey = 'toque1' | 'toque2' | 'toque3';

export interface ToqueAgendado {
  toque: ToqueKey;
  /** Título igual ao do banco (o banco reconhece a atividade pelo começo do título). */
  titulo: string;
  tipo: 'whatsapp' | 'ligacao';
  venceEm: Date;
}

const minDe = (hhmm: string | null, padrao: number) => {
  const m = /^(\d{2}):(\d{2})/.exec(hhmm ?? '');
  return m ? Number(m[1]) * 60 + Number(m[2]) : padrao;
};

/**
 * As atividades que a entrada cria para o dono. Toque 1 vence na hora (ou na abertura do expediente).
 * Toque 2: sexta anterior ao evento, 10h; quem entra depois dela e antes do evento, no próximo expediente.
 * Toque 3: cada dia do evento, 1 h antes do início (sem hora cadastrada, 9h). Dia que já passou não entra.
 */
export function agendaAtivacao(entrada: Date, evento: Pick<ProjetoAtivacao, 'eventoInicio' | 'eventoFim' | 'eventoHora'>): ToqueAgendado[] {
  const toques: ToqueAgendado[] = [
    { toque: 'toque1', titulo: 'Toque 1: mensagem agora (salvar o número)', tipo: 'whatsapp', venceEm: proximoExpediente(entrada) },
  ];
  if (!evento.eventoInicio) return toques;
  const hoje = dataIso(local(entrada).dia);
  if (evento.eventoInicio > hoje) {
    const sexta = sextaAnterior(evento.eventoInicio);
    const venc = sexta > hoje ? instante(deIso(sexta), 10 * H) : proximoExpediente(entrada);
    toques.push({ toque: 'toque2', titulo: 'Toque 2: ligar (5 blocos)', tipo: 'ligacao', venceEm: venc });
  }
  const minuto = Math.max(0, minDe(evento.eventoHora, 10 * H) - H);
  diasDoEvento(evento.eventoInicio, evento.eventoFim).forEach((dia, i) => {
    if (dia < hoje) return;
    const v = instante(deIso(dia), minuto);
    toques.push({ toque: 'toque3', titulo: `Toque 3 · dia ${i + 1}: link no privado antes do grupo`, tipo: 'whatsapp', venceEm: v < entrada ? entrada : v });
  });
  return toques;
}

// ── Carga do dia (teto da Meta) ──

export type NivelCarga = 'ok' | 'atencao' | 'acima';

export function nivelCarga(novasHoje: number): NivelCarga {
  if (novasHoje > TETO_CONVERSAS_NOVAS.maximo) return 'acima';
  if (novasHoje >= TETO_CONVERSAS_NOVAS.atencao) return 'atencao';
  return 'ok';
}

export function avisoCarga(c: Pick<CargaAtivacao, 'novasHoje'>, nome: string): string | null {
  const n = nivelCarga(c.novasHoje);
  if (n === 'acima') return `${nome} tem ${c.novasHoje} conversas novas hoje: passou do teto de ${TETO_CONVERSAS_NOVAS.maximo} por número. Divida o lote antes do toque 1.`;
  if (n === 'atencao') return `${nome} tem ${c.novasHoje} conversas novas hoje: perto do teto de ${TETO_CONVERSAS_NOVAS.maximo} por número.`;
  return null;
}

export function avisoMensageria(p: Pick<ProjetoAtivacao, 'mensageriaHoje' | 'nome'>): string | null {
  if (p.mensageriaHoje <= 0) return null;
  return `A Mensageria tem ${p.mensageriaHoje} disparo(s) hoje em ${p.nome}. A mesma pessoa não recebe régua e toque no mesmo dia: confira a agenda de disparos antes do toque.`;
}

// ── Validação do cadastro (a mesma do banco) ──

const RE_PRODUTO = /^[0-9]{1,20}$/;

/** Normaliza a lista digitada: sem espaços nas pontas, sem vazios, sem repetidos. */
export function normalizarLista(v: string[]): string[] {
  const vistos = new Set<string>();
  const out: string[] = [];
  for (const x of v) {
    const t = x.trim();
    if (t && !vistos.has(t)) { vistos.add(t); out.push(t); }
  }
  return out;
}

/** As mesmas mensagens de crm_ativacao_salvar. */
export function validarAtivacao(e: EdicaoAtivacao): string | null {
  if ((e.eventoInicio == null) !== (e.eventoFim == null)) return 'Preencha o início e o fim do evento, ou nenhum.';
  if (e.eventoInicio && e.eventoFim) {
    if (e.eventoFim < e.eventoInicio) return 'O fim do evento vem antes do início.';
    if (diasEntre(e.eventoInicio, e.eventoFim) > 6) return 'Evento de até 7 dias.';
  }
  if (e.eventoHora && !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(e.eventoHora)) return 'Hora no formato HH:MM.';
  if (e.hotmartOferta.some((x) => !RE_PRODUTO.test(x))) return 'Produto da Hotmart é o número do produto.';
  if (e.ligado && !e.eventoInicio) return 'Ativação ligada precisa da data do evento.';
  if (e.carrinhoFim && e.eventoInicio && e.carrinhoFim < e.eventoInicio) return 'O carrinho não fecha antes do início do evento.';
  return null;
}

function diasEntre(a: string, b: string): number {
  return Math.round((deIso(b).getTime() - deIso(a).getTime()) / (D * 60000));
}

// ── Modelos de mensagem (roteiros do processo) ──

export interface RoteiroAtivacao {
  id: string;
  toque: ToqueKey | 'followup';
  titulo: string;
  texto: string;
}

/** Textos do processo. Variáveis: {nome}, {vendedor}, {especialista}, {datas}, {temas}. Nunca mencionar replay. */
export const ROTEIROS_ATIVACAO: RoteiroAtivacao[] = [
  {
    id: 'toque1', toque: 'toque1', titulo: 'Toque 1: salvar o número',
    texto: 'Olá, {nome}, tudo joia? Aqui é o {vendedor}, da equipe do {especialista}. Você se inscreveu para participar do nosso evento que acontece no YouTube nos dias {datas}. Só estou passando para certificar que você recebeu o presente que enviamos após sua inscrição. Chegou certinho, conseguiu ter acesso? Caso não tenha recebido, me avisa aqui que eu resolvo na hora. Ah, já aproveita e salva o meu número. Sou eu quem vai te acompanhar durante o evento.',
  },
  {
    id: 'toque2', toque: 'toque2', titulo: 'Toque 2: ligação em 5 blocos',
    texto: '1. Reconexão: "não sei se lembra, mas a gente falou alguns dias atrás pelo WhatsApp".\n2. Contexto: o que o evento é e o que o {especialista} vai tratar em cada dia.\n3. Check-in: recebeu o material? Entrou no grupo? Tem dificuldade de entrar no YouTube? (quem tiver recebe o passo a passo em vídeo).\n4. Segurança: toda comunicação sai só pelos administradores; não existe venda paralela nem abordagem durante o evento.\n5. Compromisso: "o evento foi feito para quem vai participar ao vivo. Já separa esses dias, eu conto com a sua presença".',
  },
  {
    id: 'followup', toque: 'followup', titulo: 'Toque 2: não atendeu',
    texto: 'Oi, {nome}! Tentei te ligar agora há pouco para falar do evento dos dias {datas}. Qual o melhor horário para a gente conversar rapidinho?',
  },
  {
    id: 'toque3-dia1', toque: 'toque3', titulo: 'Toque 3 · dia 1',
    texto: 'Hoje começa, {nome}! O {especialista} vai mostrar {temas}. O link vai no grupo, mas para você se antecipar já estou te mandando por aqui. Conto com sua presença.',
  },
  {
    id: 'toque3-dia2', toque: 'toque3', titulo: 'Toque 3 · dia 2',
    texto: 'Você acompanhou ontem, {nome}? O que achou? Ficou com dúvida? Hoje ele vai explicar {temas}. Mando o link por aqui de novo para garantir.',
  },
  {
    id: 'toque3-dia3', toque: 'toque3', titulo: 'Toque 3 · dia 3',
    texto: 'Hoje é o dia mais importante, {nome}. Não vai ficar gravado. Vamos entregar um presente surpresa para quem estiver ao vivo. Já te mando o link antes mesmo de sair no grupo.',
  },
];

export type VariaveisRoteiro = Partial<Record<'nome' | 'vendedor' | 'especialista' | 'datas' | 'temas', string>>;

/** Troca as variáveis que vieram; as que faltam ficam entre colchetes para o vendedor completar. */
export function preencherRoteiro(texto: string, v: VariaveisRoteiro): string {
  return texto.replace(/\{(nome|vendedor|especialista|datas|temas)\}/g, (_, k: keyof VariaveisRoteiro) => {
    const val = v[k]?.trim();
    return val ? val : `[${k}]`;
  });
}

/** Proibido na base: replay. Serve de trava para quem editar os roteiros. */
export function mencionaReplay(texto: string): boolean {
  return /\breplay\b|\breprise\b|\bgrava[çc][ãa]o dispon[íi]vel\b/i.test(texto);
}

/** "12 a 14/11" ou "12/11". */
export function datasDoEvento(inicio: string | null, fim: string | null): string {
  if (!inicio) return '';
  const [, mi, di] = inicio.split('-');
  if (!fim || fim === inicio) return `${di}/${mi}`;
  const [, mf, df] = fim.split('-');
  return mi === mf ? `${di} a ${df}/${mf}` : `${di}/${mi} a ${df}/${mf}`;
}
