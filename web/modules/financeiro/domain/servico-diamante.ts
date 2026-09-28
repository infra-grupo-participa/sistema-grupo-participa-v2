// Serviço Diamante (27/09/2026, João): "quais serviços ele contratou, quais está devendo, quais está em dia, quem está
// devendo" — separando os Diamantes que já pagaram alguma vez. Os serviços são UM produto na Hotmart (1462643) com uma
// oferta por serviço; fin.diamante_ofertas junta as ofertas. Linhas de fn_fin_diamante_servicos (pessoa × serviço).

export type SituacaoServico = 'devendo' | 'em_dia' | 'parou_devendo' | 'encerrado' | 'nunca_pagou';

export interface LinhaServicoDiamante {
  pessoa_chave: string;
  nome: string | null;
  email: string | null;
  emails: string[] | null;
  telefone: string | null;
  nivel: string | null;
  servico: string;
  ofertas: string[] | null;
  desconhecida: boolean;
  primeira_paga: string | null;
  ultima_paga: string | null;
  pagamentos: number;
  total_pago: number;
  liquido: number;
  mensalidade: number | null;
  devendo_n: number;
  devendo_valor: number;
  devendo_desde: string | null;
  /** Dívida com mais de 120 dias (assinatura que parou devendo). */
  antigo_n: number;
  antigo_valor: number;
  antigo_desde: string | null;
  estornos: number;
  tentativas: number;
  situacao: SituacaoServico;
}

export const SERVICOS_DIAMANTE: { chave: string; rotulo: string }[] = [
  { chave: 'trafego', rotulo: 'Gestão de Tráfego' },
  { chave: 'social_media', rotulo: 'Social Media' },
  { chave: 'web_design', rotulo: 'Web Design' },
  { chave: 'video', rotulo: 'Edição de Vídeo' },
  { chave: 'copy', rotulo: 'Copywriter' },
  { chave: 'design_grafico', rotulo: 'Design Gráfico' },
  { chave: 'disparos', rotulo: 'Gestor de Disparos' },
  { chave: 'automacao', rotulo: 'Automação' },
  { chave: 'pacote', rotulo: 'Pacote de serviços' },
  { chave: 'desconhecida', rotulo: 'Oferta desconhecida' },
];

export function rotuloServico(chave: string): string {
  return SERVICOS_DIAMANTE.find((s) => s.chave === chave)?.rotulo ?? chave;
}

export const ROTULO_SITUACAO_SERVICO: Record<SituacaoServico, string> = {
  devendo: 'Devendo',
  em_dia: 'Em dia',
  parou_devendo: 'Parou devendo',
  encerrado: 'Parou sem dever',
  nunca_pagou: 'Nunca pagou',
};

/** Ordem de leitura: o que pede ação primeiro. */
export const ORDEM_SITUACAO_SERVICO: SituacaoServico[] = ['devendo', 'em_dia', 'parou_devendo', 'encerrado', 'nunca_pagou'];

export const ROTULO_NIVEL: Record<string, string> = {
  diamante_vermelho: 'Diamante Vermelho', diamante: 'Diamante', platina: 'Platina', ouro: 'Ouro',
  profissional: 'Profissional', em_formacao: 'Em formação', pessoal: 'Pessoal', iniciante: 'Iniciante',
};
export const ehNivelDiamante = (n: string | null) => n === 'diamante' || n === 'diamante_vermelho';

export interface DiamanteCliente {
  pessoa_chave: string;
  nome: string;
  email: string | null;
  emails: string[];
  telefone: string | null;
  nivel: string | null;
  servicos: LinhaServicoDiamante[];
  situacao: SituacaoServico;
  jaPagou: boolean;
  totalPago: number;
  devendoValor: number;
  devendoN: number;
  devendoDesde: string | null;
  antigoValor: number;
  antigoN: number;
  /** Soma da última mensalidade dos serviços em dia. */
  mensalidadeAtiva: number;
  ultimaPaga: string | null;
  primeiraPaga: string | null;
}

const minData = (a: string | null, b: string | null) => (!a ? b : !b ? a : a < b ? a : b);
const maxData = (a: string | null, b: string | null) => (!a ? b : !b ? a : a > b ? a : b);

/** Situação da pessoa = a mais urgente entre os serviços (devendo > em dia > parou > nunca pagou). */
export function agruparPorDiamante(linhas: LinhaServicoDiamante[]): DiamanteCliente[] {
  const por = new Map<string, DiamanteCliente>();
  for (const l of linhas) {
    let c = por.get(l.pessoa_chave);
    if (!c) {
      c = {
        pessoa_chave: l.pessoa_chave, nome: l.nome?.trim() || l.email || '—', email: l.email, emails: l.emails ?? [],
        telefone: l.telefone, nivel: l.nivel, servicos: [], situacao: 'nunca_pagou', jaPagou: false, totalPago: 0,
        devendoValor: 0, devendoN: 0, devendoDesde: null, antigoValor: 0, antigoN: 0, mensalidadeAtiva: 0, ultimaPaga: null, primeiraPaga: null,
      };
      por.set(l.pessoa_chave, c);
    }
    c.servicos.push(l);
    c.totalPago += Number(l.total_pago) || 0;
    c.devendoValor += Number(l.devendo_valor) || 0;
    c.devendoN += l.devendo_n || 0;
    c.devendoDesde = minData(c.devendoDesde, l.devendo_desde);
    c.antigoValor += Number(l.antigo_valor) || 0;
    c.antigoN += l.antigo_n || 0;
    if (l.situacao === 'em_dia') c.mensalidadeAtiva += Number(l.mensalidade) || 0;
    if (l.pagamentos > 0) c.jaPagou = true;
    c.ultimaPaga = maxData(c.ultimaPaga, l.ultima_paga);
    c.primeiraPaga = minData(c.primeiraPaga, l.primeira_paga);
  }
  for (const c of por.values()) {
    c.situacao = ORDEM_SITUACAO_SERVICO.find((s) => c.servicos.some((x) => x.situacao === s)) ?? 'nunca_pagou';
    c.servicos.sort((a, b) => ORDEM_SITUACAO_SERVICO.indexOf(a.situacao) - ORDEM_SITUACAO_SERVICO.indexOf(b.situacao)
      || (b.total_pago - a.total_pago));
  }
  return [...por.values()].sort((a, b) =>
    ORDEM_SITUACAO_SERVICO.indexOf(a.situacao) - ORDEM_SITUACAO_SERVICO.indexOf(b.situacao)
    || b.devendoValor - a.devendoValor || b.antigoValor - a.antigoValor || b.totalPago - a.totalPago);
}

export interface ResumoServico { chave: string; contrataram: number; emDia: number; devendo: number; devendoValor: number; mensalidadeAtiva: number }
export interface ResumoDiamante {
  jaPagaram: number;
  nuncaPagaram: number;
  emDia: number;
  devendo: number;
  devendoValor: number;
  pararam: number;
  pararamDevendo: number;
  antigoValor: number;
  mensalidadeAtiva: number;
  totalPago: number;
  foraDoDiamante: number;
  servicos: ResumoServico[];
}

export function resumirDiamantes(clientes: DiamanteCliente[]): ResumoDiamante {
  const pagantes = clientes.filter((c) => c.jaPagou);
  const porServ = new Map<string, ResumoServico>();
  for (const c of pagantes) {
    for (const s of c.servicos) {
      if (s.pagamentos === 0 && s.devendo_n === 0 && s.antigo_n === 0) continue;
      const r = porServ.get(s.servico) ?? { chave: s.servico, contrataram: 0, emDia: 0, devendo: 0, devendoValor: 0, mensalidadeAtiva: 0 };
      r.contrataram += 1;
      if (s.situacao === 'em_dia') { r.emDia += 1; r.mensalidadeAtiva += Number(s.mensalidade) || 0; }
      if (s.situacao === 'devendo') { r.devendo += 1; r.devendoValor += Number(s.devendo_valor) || 0; }
      porServ.set(s.servico, r);
    }
  }
  const ordem = SERVICOS_DIAMANTE.map((s) => s.chave);
  return {
    jaPagaram: pagantes.length,
    nuncaPagaram: clientes.length - pagantes.length,
    emDia: pagantes.filter((c) => c.situacao === 'em_dia').length,
    devendo: pagantes.filter((c) => c.situacao === 'devendo').length,
    devendoValor: pagantes.reduce((s, c) => s + c.devendoValor, 0),
    pararam: pagantes.filter((c) => c.situacao === 'encerrado').length,
    pararamDevendo: pagantes.filter((c) => c.situacao === 'parou_devendo').length,
    antigoValor: pagantes.reduce((s, c) => s + c.antigoValor, 0),
    mensalidadeAtiva: pagantes.reduce((s, c) => s + c.mensalidadeAtiva, 0),
    totalPago: pagantes.reduce((s, c) => s + c.totalPago, 0),
    foraDoDiamante: pagantes.filter((c) => (c.situacao === 'em_dia' || c.situacao === 'devendo') && !ehNivelDiamante(c.nivel)).length,
    servicos: [...porServ.values()].sort((a, b) => ordem.indexOf(a.chave) - ordem.indexOf(b.chave)),
  };
}

/** Dias entre duas datas ISO (YYYY-MM-DD). */
export function diasEntre(deISO: string, ateISO: string): number {
  const d = (s: string) => Date.UTC(Number(s.slice(0, 4)), Number(s.slice(5, 7)) - 1, Number(s.slice(8, 10)));
  return Math.round((d(ateISO) - d(deISO)) / 86_400_000);
}
