// Trajetória em MARCOS (pedido do João, 30/09/2026): a lista plana da fn_aluno_trajetoria vira poucos pontos
// principais, do mais antigo ao mais recente (lê-se de cima para baixo como história), cada um com os registros
// que o compõem. Função pura; o contrato da RPC não muda.
//
// Regras de agrupamento:
// 1. Marco próprio (ponto principal da história):
//    - "Entrou no time": âncora = 1º entrada_thb (sem ele, a 1ª turma_origem). Entram sempre entrada_thb,
//      tipo_entrada e turma_origem; ingresso, turma_atual e turma_aurum entram se estiverem a até
//      JANELA_ENTRADA_DIAS da âncora (antes ou depois). Sem âncora, não há marco de entrada.
//    - compra, estorno, saída, volta, troca (turma/plano), nível, placa: 1 marco por tipo e por dia
//      (registros do mesmo dia juntos). No mesmo dia, o estorno entra no marco "Saiu" (é o estorno que gerou a
//      saída) e a compra entra no marco "Voltou" (é a compra que gerou a volta).
// 2. Capítulo (1 marco no 1º dia, com o intervalo): Central do Aluno, GPS, Card HM, Grupos de WhatsApp, Sócios,
//    Situação de acesso, Outros eventos. Cada saída do time corta o capítulo: registros até o dia da saída ficam
//    num capítulo, os posteriores abrem outro — assim a história não junta "antes" e "depois" de sair.
// 3. Tipo desconhecido: marco próprio com o título da própria linha (nada some da tela).
import { resumirTrajetoriaAluno, type LinhaTrajetoriaAluno } from './trajetoria-aluno';

export const JANELA_ENTRADA_DIAS = 30;

export type TipoMarco = 'entrada' | 'compra' | 'estorno' | 'saida' | 'volta' | 'troca' | 'nivel' | 'placa' | 'capitulo' | 'outro';
export type CapituloTrajetoria = 'central' | 'gps' | 'card_hm' | 'grupos' | 'socios' | 'acesso' | 'eventos';
export type TomMarco = 'neutro' | 'inicio' | 'alerta' | 'positivo';

export interface MarcoTrajetoria {
  id: string;
  tipo: TipoMarco;
  capitulo: CapituloTrajetoria | null;
  titulo: string;
  /** 'YYYY-MM-DD'. Marco próprio: o dia do marco. Capítulo: 1º e último registro. */
  inicio: string;
  fim: string;
  /** 1 linha humana; null quando não há o que resumir. */
  resumo: string | null;
  tom: TomMarco;
  /** Registros do marco, do mais antigo ao mais recente. */
  itens: LinhaTrajetoriaAluno[];
  /** Soma das compras do marco (compra, estorno, saída, volta), só quando TODAS têm valor; entrada e capítulo: null.
   *  Quem não vê o financeiro recebe valor null da RPC e não vê nada. */
  valor: number | null;
}

export const TITULO_CAPITULO: Record<CapituloTrajetoria, string> = {
  central: 'Central do Aluno',
  gps: 'GPS',
  card_hm: 'Card HM',
  grupos: 'Grupos de WhatsApp',
  socios: 'Sócios',
  acesso: 'Situação de acesso',
  eventos: 'Outros eventos',
};

type Classe = { tipo: Exclude<TipoMarco, 'capitulo'>; kitEntrada?: 'sempre' | 'janela' } | { capitulo: CapituloTrajetoria };

export function classificarLinha(l: LinhaTrajetoriaAluno): Classe {
  switch (l.dimensao) {
    case 'vinculo':
      if (l.tipo === 'entrada_thb' || l.tipo === 'tipo_entrada') return { tipo: 'entrada', kitEntrada: 'sempre' };
      if (l.tipo === 'saida' || l.tipo === 'cancelamento') return { tipo: 'saida' };
      if (l.tipo === 'volta') return { tipo: 'volta' };
      if (l.tipo === 'troca_plano') return { tipo: 'troca' };
      if (l.tipo === 'situacao_acesso' || l.tipo === 'status_acesso') return { capitulo: 'acesso' };
      return { tipo: 'outro' };
    case 'turma':
      if (l.tipo === 'turma_origem') return { tipo: 'entrada', kitEntrada: 'sempre' };
      if (l.tipo === 'turma_atual' || l.tipo === 'turma_aurum') return { tipo: 'troca', kitEntrada: 'janela' };
      return { tipo: 'troca' };
    case 'compras':
      if (l.tipo === 'estorno' || l.tipo === 'cancelamento') return { tipo: 'estorno' };
      if (l.tipo === 'ingresso') return { tipo: 'compra', kitEntrada: 'janela' };
      return { tipo: 'compra' };
    case 'socios':
      return { capitulo: 'socios' };
    case 'grupos':
      return { capitulo: 'grupos' };
    case 'eventos':
      if (l.fonte === 'Central') return { capitulo: 'central' };
      if (l.fonte.startsWith('GPS')) return { capitulo: 'gps' };
      return { capitulo: 'eventos' };
    case 'atendimento':
      if (l.fonte === 'Card HM') return { capitulo: 'card_hm' };
      if (l.tipo === 'nivel') return { tipo: 'nivel' };
      if (l.tipo === 'solicitou_placa') return { tipo: 'placa' };
      if (l.tipo === 'acesso_central') return { capitulo: 'acesso' };
      return { tipo: 'outro' };
    default:
      return { tipo: 'outro' };
  }
}

const DIA_MS = 86_400_000;
const diaUTC = (d: string) => Date.UTC(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10)));
const distanciaDias = (a: string, b: string) => Math.abs(diaUTC(a) - diaUTC(b)) / DIA_MS;

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;
const depoisDosDoisPontos = (t: string) => { const i = t.indexOf(': '); return i < 0 ? t : t.slice(i + 2); };
const minusculaInicial = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);
const conta = (itens: LinhaTrajetoriaAluno[], ...tipos: string[]) => itens.filter((l) => tipos.includes(l.tipo)).length;
const juntar = (partes: (string | null | false | undefined)[]) => partes.filter(Boolean).join(' · ') || null;

/** Motivo da saída em português (a `regra` da RPC é técnica). */
export function motivoSaida(regra: string | null): string | null {
  if (!regra) return null;
  if (regra.startsWith('estorno')) return 'estorno da compra principal';
  if (regra.startsWith('parcela')) return 'parcela sem pagamento por 30 dias';
  if (regra.startsWith('cancelamento do card')) return 'cancelamento no card HM';
  if (regra === 'thb_alunos.cancelado_em') return 'cancelado na base de alunos';
  return regra;
}

const ETAPA_CARD: Record<string, string> = {
  entrada_card: 'entrada', reuniao: 'reunião', entrevista: 'entrevista', pagamento: 'pagamento', quitado: 'quitado',
  pedido_cancelamento: 'pediu cancelamento', cancelado_hotmart: 'cancelado na Hotmart', acessos_revogados: 'acessos revogados',
};
const CARD_ALERTA = new Set(['pedido_cancelamento', 'cancelado_hotmart', 'acessos_revogados']);

function resumoCapitulo(cap: CapituloTrajetoria, itens: LinhaTrajetoriaAluno[]): string | null {
  switch (cap) {
    case 'central': {
      const ini = conta(itens, 'trilha_iniciada');
      const enc = conta(itens, 'trilha_encerrada');
      return juntar([
        ini > 0 && plural(ini, 'trilha', 'trilhas'),
        enc > 0 && `encerrou ${enc}`,
        conta(itens, 'raio_x') > 0 && 'Raio-X feito',
        conta(itens, 'boas_vindas') > 0 && 'boas-vindas',
        conta(itens, 'debriefing') > 0 && 'debriefing liberado',
      ]);
    }
    case 'gps': {
      const meses = conta(itens, 'atividade_mes');
      const clientes = itens.filter((l) => l.tipo.startsWith('cliente_')).length;
      const plantoes = conta(itens, 'plantao_inscricao', 'plantao_presenca');
      const presencas = conta(itens, 'plantao_presenca');
      return juntar([
        conta(itens, 'conta_criada') > 0 && 'conta criada',
        conta(itens, 'onboarding_concluido') > 0 ? 'onboarding concluído' : conta(itens, 'onboarding_iniciado') > 0 && 'onboarding iniciado',
        meses > 0 && plural(meses, 'mês com atividade', 'meses com atividade'),
        clientes > 0 && plural(clientes, 'resultado com cliente', 'resultados com cliente'),
        plantoes > 0 && `${plural(plantoes, 'plantão', 'plantões')}${presencas ? ` (${presencas} com presença)` : ''}`,
      ]);
    }
    case 'card_hm': {
      const etapas: string[] = [];
      for (const l of itens) { const e = ETAPA_CARD[l.tipo] ?? l.titulo; if (!etapas.includes(e)) etapas.push(e); }
      return juntar(etapas);
    }
    case 'grupos': {
      const ent = conta(itens, 'entrou_grupo');
      const sai = conta(itens, 'saiu_grupo');
      return juntar([ent > 0 && `entrou em ${plural(ent, 'grupo', 'grupos')}`, sai > 0 && `saiu de ${sai}`]);
    }
    case 'socios': {
      const vinc = conta(itens, 'socio_vinculado');
      const conv = conta(itens, 'convite_socio');
      const aceitos = conta(itens, 'convite_socio_aceito');
      return juntar([
        vinc > 0 && plural(vinc, 'sócio vinculado', 'sócios vinculados'),
        ...itens.filter((l) => l.tipo === 'socio_de').map((l) => minusculaInicial(l.titulo)),
        conv > 0 && `${plural(conv, 'convite', 'convites')}${aceitos ? ` (${aceitos} ${aceitos === 1 ? 'aceito' : 'aceitos'})` : ''}`,
        conta(itens, 'marcado_socio') > 0 && 'marcação de sócio',
      ]);
    }
    case 'acesso': {
      const ult = itens[itens.length - 1];
      return juntar([plural(itens.length, 'mudança', 'mudanças'), ult && `última: ${depoisDosDoisPontos(ult.titulo)}`]);
    }
    default:
      return null;
  }
}

function tituloProprio(tipo: TipoMarco, itens: LinhaTrajetoriaAluno[]): string {
  switch (tipo) {
    case 'entrada': return 'Entrou no time';
    case 'saida': return itens.every((l) => l.tipo === 'cancelamento' || l.dimensao !== 'vinculo') ? 'Cancelado na base' : 'Saiu do time';
    case 'volta': return 'Voltou ao time';
    case 'estorno': return itens.length === 1 ? `Estorno: ${itens[0].titulo}` : `${itens.length} estornos`;
    case 'nivel': return 'Mudou de nível';
    case 'placa': return 'Solicitou placa';
    case 'compra': {
      if (itens.length > 1) return `${itens.length} compras no dia`;
      const l = itens[0];
      return l.tipo === 'ingresso' ? `Ingresso: ${l.titulo}` : `Comprou ${l.titulo}`;
    }
    case 'troca': {
      const turma = itens.some((l) => l.dimensao === 'turma');
      const plano = itens.some((l) => l.tipo === 'troca_plano');
      if (turma && plano) return 'Mudou turma e plano';
      if (plano) return 'Trocou de plano';
      if (itens.every((l) => l.tipo === 'turma_atual' || l.tipo === 'turma_aurum')) return itens[0].titulo;
      return 'Trocou de turma';
    }
    default: return itens[0].titulo;
  }
}

function resumoProprio(tipo: TipoMarco, itens: LinhaTrajetoriaAluno[]): string | null {
  switch (tipo) {
    case 'entrada':
      return juntar([
        itens.find((l) => l.tipo === 'entrada_thb')?.detalhe,
        ...itens.filter((l) => l.tipo === 'turma_origem' || l.tipo === 'turma_atual' || l.tipo === 'turma_aurum').map((l) => minusculaInicial(l.titulo)),
        conta(itens, 'ingresso') > 0 && plural(conta(itens, 'ingresso'), 'ingresso', 'ingressos'),
      ]);
    case 'saida': {
      const s = itens.find((l) => l.dimensao === 'vinculo');
      return juntar([s?.detalhe, motivoSaida(s?.regra ?? null)]);
    }
    case 'volta':
      return juntar([itens.find((l) => l.tipo === 'volta')?.detalhe]);
    case 'compra':
      return itens.length > 1 ? juntar(itens.map((l) => l.titulo)) : itens[0].detalhe;
    case 'estorno':
      return itens.length > 1 ? juntar(itens.map((l) => l.titulo)) : itens[0].detalhe;
    case 'troca':
    case 'nivel':
      return juntar(itens.filter((l) => l.tipo !== 'turma_atual' && l.tipo !== 'turma_aurum').map((l) => l.detalhe));
    default:
      return juntar(itens.map((l) => l.detalhe));
  }
}

function tomDe(tipo: TipoMarco, cap: CapituloTrajetoria | null, itens: LinhaTrajetoriaAluno[]): TomMarco {
  if (tipo === 'saida' || tipo === 'estorno') return 'alerta';
  if (tipo === 'volta') return 'positivo';
  if (tipo === 'entrada') return 'inicio';
  if (cap === 'card_hm' && itens.some((l) => CARD_ALERTA.has(l.tipo))) return 'alerta';
  if (tipo === 'compra' && itens.some((l) => l.tipo === 'cancelamento')) return 'alerta';
  return 'neutro';
}

function valorDe(itens: LinhaTrajetoriaAluno[]): number | null {
  const compras = itens.filter((l) => l.dimensao === 'compras');
  if (!compras.length || compras.some((l) => l.valor == null)) return null;
  return compras.reduce((s, l) => s + (l.valor as number), 0);
}

const ORDEM_TIPO: Record<TipoMarco, number> = {
  entrada: 0, compra: 1, troca: 2, nivel: 3, placa: 4, outro: 5, estorno: 6, saida: 7, volta: 8, capitulo: 9,
};

/** Do mais antigo ao mais recente: dia asc, momento asc (sem momento primeiro no dia); empate mantém a ordem da RPC. */
export function ordenarCronologico(linhas: LinhaTrajetoriaAluno[]): LinhaTrajetoriaAluno[] {
  return linhas
    .map((l, i) => ({ l, i }))
    .sort((a, b) => a.l.dia.localeCompare(b.l.dia) || (a.l.momento ?? '').localeCompare(b.l.momento ?? '') || a.i - b.i)
    .map((x) => x.l);
}

const ehSaida = (l: LinhaTrajetoriaAluno) => l.dimensao === 'vinculo' && (l.tipo === 'saida' || l.tipo === 'cancelamento');

/** Dias de saída que cortam capítulos. Exposto para o filtro por dimensão cortar igual à visão completa. */
export const diasDeSaida = (linhas: LinhaTrajetoriaAluno[]) => [...new Set(linhas.filter(ehSaida).map((l) => l.dia))].sort();

/** `diasCorte`: por padrão, as saídas das próprias linhas; o filtro passa as da trajetória inteira. */
export function agruparEmMarcos(linhas: LinhaTrajetoriaAluno[], diasCorte: string[] = diasDeSaida(linhas)): MarcoTrajetoria[] {
  const crono = ordenarCronologico(linhas);
  const classes = crono.map((l) => ({ l, c: classificarLinha(l) }));

  const ancora = crono.find((l) => l.tipo === 'entrada_thb')?.dia
    ?? crono.find((l) => l.tipo === 'turma_origem')?.dia ?? null;

  const entrada: LinhaTrajetoriaAluno[] = [];
  const proprios = new Map<string, { tipo: Exclude<TipoMarco, 'capitulo'>; dia: string; itens: LinhaTrajetoriaAluno[] }>();
  const doCapitulo: { l: LinhaTrajetoriaAluno; cap: CapituloTrajetoria }[] = [];

  for (const { l, c } of classes) {
    if ('capitulo' in c) { doCapitulo.push({ l, cap: c.capitulo }); continue; }
    if (ancora && (c.kitEntrada === 'sempre' || (c.kitEntrada === 'janela' && distanciaDias(l.dia, ancora) <= JANELA_ENTRADA_DIAS))) {
      entrada.push(l);
      continue;
    }
    // tipo_entrada / turma_origem sem âncora não chegam aqui (âncora existe se houver turma_origem); entrada_thb idem.
    const tipo = c.tipo === 'entrada' ? 'outro' : c.tipo;
    const k = `${tipo}|${l.dia}`;
    const g = proprios.get(k) ?? { tipo, dia: l.dia, itens: [] };
    g.itens.push(l);
    proprios.set(k, g);
  }

  // No mesmo dia: estorno entra na saída; compra entra na volta.
  for (const [k, g] of proprios) {
    const alvo = g.tipo === 'estorno' ? proprios.get(`saida|${g.dia}`) : g.tipo === 'compra' ? proprios.get(`volta|${g.dia}`) : undefined;
    if (alvo) { alvo.itens.push(...g.itens); proprios.delete(k); }
  }

  const marcos: MarcoTrajetoria[] = [];
  const cronoIdx = new Map(crono.map((l, i) => [l, i]));
  const emOrdem = (xs: LinhaTrajetoriaAluno[]) => [...xs].sort((a, b) => (cronoIdx.get(a) ?? 0) - (cronoIdx.get(b) ?? 0));

  if (entrada.length && ancora) {
    const itens = emOrdem(entrada);
    marcos.push({
      id: `entrada|${ancora}`, tipo: 'entrada', capitulo: null, titulo: tituloProprio('entrada', itens),
      inicio: ancora, fim: ancora, resumo: resumoProprio('entrada', itens), tom: 'inicio', itens,
      // Sem valor no cabeçalho: o ingresso agregado não é "o valor da entrada" (fica no sub-item).
      valor: null,
    });
  }
  for (const g of proprios.values()) {
    const itens = emOrdem(g.itens);
    marcos.push({
      id: `${g.tipo}|${g.dia}`, tipo: g.tipo, capitulo: null, titulo: tituloProprio(g.tipo, itens),
      inicio: g.dia, fim: g.dia, resumo: resumoProprio(g.tipo, itens), tom: tomDe(g.tipo, null, itens), itens,
      valor: valorDe(itens),
    });
  }

  // Capítulos, cortados por saída (registros no próprio dia da saída ficam antes do corte).
  const segmento = (dia: string) => diasCorte.filter((d) => d < dia).length;
  const caps = new Map<string, { cap: CapituloTrajetoria; seg: number; itens: LinhaTrajetoriaAluno[] }>();
  for (const { l, cap } of doCapitulo) {
    const seg = segmento(l.dia);
    const k = `${cap}|${seg}`;
    const g = caps.get(k) ?? { cap, seg, itens: [] };
    g.itens.push(l);
    caps.set(k, g);
  }
  for (const g of caps.values()) {
    const itens = emOrdem(g.itens);
    marcos.push({
      id: `capitulo|${g.cap}|${g.seg}`, tipo: 'capitulo', capitulo: g.cap, titulo: TITULO_CAPITULO[g.cap],
      inicio: itens[0].dia, fim: itens[itens.length - 1].dia, resumo: resumoCapitulo(g.cap, itens),
      tom: tomDe('capitulo', g.cap, itens), itens, valor: null,
    });
  }

  return marcos.sort((a, b) => a.inicio.localeCompare(b.inicio) || ORDEM_TIPO[a.tipo] - ORDEM_TIPO[b.tipo] || a.id.localeCompare(b.id));
}

const MES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
/** 'YYYY-MM-DD' → 'mar/2022'. */
export const mesAno = (dia: string) => `${MES[Number(dia.slice(5, 7)) - 1] ?? '?'}/${dia.slice(0, 4)}`;

/** Meses inteiros entre dois dias → "8 meses", "1 ano", "3 anos e 6 meses"; menos de 1 mês → "menos de 1 mês". */
export function duracaoEntre(de: string, ate: string): string {
  let m = (Number(ate.slice(0, 4)) - Number(de.slice(0, 4))) * 12 + (Number(ate.slice(5, 7)) - Number(de.slice(5, 7)));
  if (Number(ate.slice(8, 10)) < Number(de.slice(8, 10))) m -= 1;
  if (m < 1) return 'menos de 1 mês';
  const anos = Math.floor(m / 12);
  const meses = m % 12;
  const a = anos ? plural(anos, 'ano', 'anos') : '';
  const ms = meses ? plural(meses, 'mês', 'meses') : '';
  return a && ms ? `${a} e ${ms}` : a || ms;
}

export interface FaixaJornada {
  desde: string | null;
  /** true quando não há entrada_thb: "desde" é o 1º registro. */
  desdeInferido: boolean;
  /** Fora do time = a última saída é posterior à última volta. */
  fora: boolean;
  /** Fim da contagem: hoje, ou o dia da última saída quando está fora. */
  ate: string;
  duracao: string | null;
  compras: number;
  saidas: number;
  voltas: number;
}

export function faixaJornada(linhas: LinhaTrajetoriaAluno[], hoje: string): FaixaJornada {
  const r = resumirTrajetoriaAluno(linhas);
  const ultSaida = linhas.filter(ehSaida).map((l) => l.dia).sort().pop();
  const ultVolta = linhas.filter((l) => l.tipo === 'volta').map((l) => l.dia).sort().pop();
  const fora = !!ultSaida && (!ultVolta || ultSaida > ultVolta);
  const ate = fora ? (ultSaida as string) : hoje;
  return {
    desde: r.entradaThb,
    desdeInferido: r.entradaInferida,
    fora,
    ate,
    duracao: r.entradaThb ? duracaoEntre(r.entradaThb, ate) : null,
    compras: r.compras,
    saidas: r.saidas,
    voltas: r.voltas,
  };
}

/** Posição 0..1 de um dia na régua [de, ate]; fora do intervalo é preso às pontas; intervalo nulo = 0. */
export function posicaoNaRegua(dia: string, de: string, ate: string): number {
  const total = diaUTC(ate) - diaUTC(de);
  if (total <= 0) return 0;
  return Math.min(1, Math.max(0, (diaUTC(dia) - diaUTC(de)) / total));
}
