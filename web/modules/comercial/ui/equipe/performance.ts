// Performance da equipe comercial: indicadores por vendedor, comparação com o período anterior e com o time,
// selos (destaques e alertas), ranking por critério explícito e o detalhe do vendedor. Funções puras, testáveis.
// As regras de contagem seguem domain/metricas.ts (mesma definição do ícone (i)). Dia no fuso de Brasília.
import { ETAPAS, produto as produtoDe, rotuloMotivo } from '../../domain/catalogo';
import { ROTULO_PAPEL } from '../../domain/funis';
import { atividadeAtrasada, semProximoPasso, situacaoSla } from '../../domain/regras';
import type {
  Atividade, Conversa, EtapaKey, EventoTimeline, Funil, MotivoPerda, MotivoPerdaConfig, Negocio, TipoAtividade,
} from '../../domain/types';
import { diaBR, diasDoIntervalo, intervalos, rotuloDia, type Intervalo } from '../inicio/metricas-painel';
import { perdidosPorMotivo, tempoMedioPorEtapa } from '../relatorios/indicadores';

const H = 3_600_000;
const D = 24 * H;
const FUSO = 3 * H; // Brasília = UTC-3

/** Mínimo de negócios encerrados para a conversão entrar em selo e ranking (amostra pequena engana). */
export const MIN_ENCERRADOS = 3;
/** Meta de primeiro contato (checkout): 15 minutos. */
export const META_PRIMEIRO_CONTATO_MIN = 15;

export interface BaseEquipe {
  negocios: Negocio[];
  atividades: Atividade[];
  eventos: EventoTimeline[];
  funis: Funil[];
  motivos: MotivoPerdaConfig[];
  conversas: Conversa[];
  agora: Date;
}

// ── Período ──

export type PeriodoEquipe = 'hoje' | '7d' | '30d' | 'mes' | 'personalizado';

export const ROTULO_PERIODO_EQUIPE: Record<PeriodoEquipe, string> = {
  hoje: 'Hoje', '7d': '7 dias', '30d': '30 dias', mes: 'Mês', personalizado: 'Personalizado',
};

/** Meia-noite (Brasília) de "AAAA-MM-DD". NaN se inválido. */
function inicioYmd(ymd: string): number {
  return /^\d{4}-\d{2}-\d{2}$/.test(ymd) ? Date.parse(`${ymd}T00:00:00Z`) + FUSO : NaN;
}

/**
 * Período escolhido e o anterior de mesmo tamanho. Personalizado: de `de` até o fim de `ate` (no máximo agora);
 * o anterior é o mesmo número de dias imediatamente antes. Datas inválidas caem nos últimos 7 dias.
 */
export function intervaloEquipe(p: PeriodoEquipe, agora: Date, de?: string, ate?: string): { atual: Intervalo; anterior: Intervalo } {
  if (p !== 'personalizado') return intervalos(p, agora);
  const ini = inicioYmd(de ?? '');
  const fimDia = inicioYmd(ate ?? '');
  if (!Number.isFinite(ini) || !Number.isFinite(fimDia) || fimDia < ini) return intervalos('7d', agora);
  const fim = Math.min(fimDia + D - 1, agora.getTime());
  const ini2 = Math.min(ini, fim);
  const dias = Math.max(1, Math.round((fimDia + D - ini) / D));
  return { atual: { ini: ini2, fim }, anterior: { ini: ini2 - dias * D, fim: ini2 - 1 } };
}

const dentro = (iso: string | null | undefined, i: Intervalo) => {
  if (!iso) return false;
  const t = Date.parse(iso);
  return t >= i.ini && t <= i.fim;
};

const mediana = (v: number[]): number | null => {
  if (!v.length) return null;
  const s = [...v].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

const media = (v: number[]): number | null => (v.length ? v.reduce((s, x) => s + x, 0) / v.length : null);

/** Toque de abordagem: WhatsApp ou ligação (definição de "abordados"). */
const ehToque = (a: Pick<Atividade, 'tipo'>) => a.tipo === 'whatsapp' || a.tipo === 'ligacao';

/** Motivos que são falha de processo (avisam o gestor) e não do lead. */
export function motivosDeFalha(motivos: Pick<MotivoPerdaConfig, 'key' | 'alertaGestor'>[]): Set<MotivoPerda> {
  return new Set<MotivoPerda>(['ja_atendido_outro_vendedor', ...motivos.filter((m) => m.alertaGestor).map((m) => m.key)]);
}

// ── Indicadores por vendedor ──

export interface IndicadoresVendedor {
  /** null = time inteiro. */
  vendedorId: string | null;
  vendas: number;
  receita: number;
  /** receita ÷ vendas. null sem venda. */
  ticketMedio: number | null;
  ganhos: number;
  perdidos: number;
  encerrados: number;
  /** ganhos ÷ encerrados (%). null sem encerrado. */
  conversao: number | null;
  /** Carga: negócios abertos agora. */
  abertos: number;
  criticos: number;
  semProximo: number;
  atrasadas: number;
  /** Mediana em minutos entre o negócio nascer e o primeiro contato concluído pelo dono. */
  tempoPrimeiroContatoMin: number | null;
  /** Toques (WhatsApp/ligação) concluídos no período. */
  abordagens: number;
  abordagensDia: number;
  atividadesConcluidas: number;
  /** Atividades que venceram no período: quantas foram concluídas até o vencimento. */
  noPrazo: { cumpridas: number; base: number; pct: number | null };
  principalMotivo: { motivo: MotivoPerda; rotulo: string; quantidade: number } | null;
  /** Perdidos por falha de processo (ex.: já atendido por outro vendedor). */
  falhaProcesso: number;
  /** Reembolsos e vendas com condição especial: entram com o backend (Hotmart por transação). */
  reembolsos: number | null;
  condicaoEspecial: number | null;
  /** Conversas em que o lead escreveu por último e ninguém respondeu. */
  semResposta: number;
}

const doDono = (donoId: string | null) => (id: string | null) => donoId == null || id === donoId;

/** Indicadores de um vendedor (ou do time, com `donoId` null) no intervalo. Carga e alertas são retrato de agora. */
export function indicadoresVendedor(base: BaseEquipe, donoId: string | null, i: Intervalo): IndicadoresVendedor {
  const meu = doDono(donoId);
  const agora = base.agora;
  const negs = base.negocios.filter((n) => meu(n.donoId));
  const ganhos = negs.filter((n) => n.status === 'ganho' && dentro(n.fechadoEm, i));
  const perdidos = negs.filter((n) => n.status === 'perdido' && dentro(n.fechadoEm, i));
  const receita = ganhos.reduce((s, n) => s + n.valor, 0);
  const encerrados = ganhos.length + perdidos.length;
  const ativs = base.atividades.filter((a) => meu(a.donoId));

  // Primeiro contato: negócios nascidos no período, com dono.
  const tempos: number[] = [];
  const porNegocio = new Map<string, string>();
  for (const a of ativs) {
    if (!a.concluidaEm || !a.negocioId) continue;
    const atual = porNegocio.get(`${a.negocioId}|${a.donoId}`);
    if (!atual || a.concluidaEm < atual) porNegocio.set(`${a.negocioId}|${a.donoId}`, a.concluidaEm);
  }
  for (const n of negs) {
    if (!n.donoId || !dentro(n.criadoEm, i)) continue;
    const primeira = porNegocio.get(`${n.id}|${n.donoId}`);
    if (primeira && primeira >= n.criadoEm) tempos.push((Date.parse(primeira) - Date.parse(n.criadoEm)) / 60000);
  }
  const tMed = mediana(tempos);

  const concluidas = ativs.filter((a) => dentro(a.concluidaEm, i));
  const abordagens = concluidas.filter(ehToque).length;
  const dias = Math.max(1, diasDoIntervalo(i).length);

  // No prazo: venceu no período (até agora) e foi concluída até o vencimento.
  const vencidas = ativs.filter((a) => dentro(a.venceEm, i) && Date.parse(a.venceEm) <= agora.getTime());
  const cumpridas = vencidas.filter((a) => a.concluidaEm && Date.parse(a.concluidaEm) <= Date.parse(a.venceEm)).length;

  const cont = new Map<MotivoPerda, number>();
  for (const n of perdidos) if (n.motivoPerda) cont.set(n.motivoPerda, (cont.get(n.motivoPerda) ?? 0) + 1);
  const top = [...cont].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0])))[0];
  const falha = motivosDeFalha(base.motivos);

  return {
    vendedorId: donoId,
    vendas: ganhos.length,
    receita,
    ticketMedio: ganhos.length ? receita / ganhos.length : null,
    ganhos: ganhos.length,
    perdidos: perdidos.length,
    encerrados,
    conversao: encerrados ? (ganhos.length / encerrados) * 100 : null,
    abertos: negs.filter((n) => n.status === 'aberto').length,
    criticos: negs.filter((n) => situacaoSla(n, agora) === 'critico').length,
    semProximo: negs.filter(semProximoPasso).length,
    atrasadas: ativs.filter((a) => atividadeAtrasada(a, agora)).length,
    tempoPrimeiroContatoMin: tMed == null ? null : Math.round(tMed),
    abordagens,
    abordagensDia: Math.round((abordagens / dias) * 10) / 10,
    atividadesConcluidas: concluidas.length,
    noPrazo: { cumpridas, base: vencidas.length, pct: vencidas.length ? Math.round((cumpridas / vencidas.length) * 100) : null },
    principalMotivo: top ? { motivo: top[0], rotulo: rotuloMotivo(top[0], base.motivos), quantidade: top[1] } : null,
    falhaProcesso: perdidos.filter((n) => n.motivoPerda && falha.has(n.motivoPerda)).length,
    reembolsos: null,
    condicaoEspecial: null,
    semResposta: conversasSemResposta(base, donoId).length,
  };
}

// ── Referência do time ──

export interface ReferenciaTime {
  vendas: number | null;
  receita: number | null;
  ticketMedio: number | null;
  conversao: number | null;
  abertos: number | null;
  tempoPrimeiroContatoMin: number | null;
  abordagensDia: number | null;
  noPrazoPct: number | null;
  atrasadas: number | null;
  semProximo: number | null;
}

/**
 * Média do time por vendedor. Contagens: média simples. Taxas: do time somado (conversão = ganhos ÷ encerrados
 * de todos; ticket = receita ÷ vendas de todos; no prazo = cumpridas ÷ vencidas de todos), para um vendedor com
 * pouca base não puxar a média.
 */
export function referenciaTime(linhas: IndicadoresVendedor[]): ReferenciaTime {
  const soma = (f: (l: IndicadoresVendedor) => number) => linhas.reduce((s, l) => s + f(l), 0);
  const m = (f: (l: IndicadoresVendedor) => number) => (linhas.length ? soma(f) / linhas.length : null);
  const vendas = soma((l) => l.vendas);
  const enc = soma((l) => l.encerrados);
  const base = soma((l) => l.noPrazo.base);
  return {
    vendas: m((l) => l.vendas),
    receita: m((l) => l.receita),
    ticketMedio: vendas ? soma((l) => l.receita) / vendas : null,
    conversao: enc ? (soma((l) => l.ganhos) / enc) * 100 : null,
    abertos: m((l) => l.abertos),
    tempoPrimeiroContatoMin: media(linhas.map((l) => l.tempoPrimeiroContatoMin).filter((x): x is number => x != null)),
    abordagensDia: m((l) => l.abordagensDia),
    noPrazoPct: base ? (soma((l) => l.noPrazo.cumpridas) / base) * 100 : null,
    atrasadas: m((l) => l.atrasadas),
    semProximo: m((l) => l.semProximo),
  };
}

/** Variação % contra uma referência (período anterior ou média do time). null quando não dá para comparar. */
export function variacaoPct(valor: number | null, ref: number | null): number | null {
  if (valor == null || ref == null || ref === 0) return null;
  return Math.round(((valor - ref) / ref) * 100);
}

/** Diferença em pontos percentuais (para taxas). */
export function diferencaPp(valor: number | null, ref: number | null): number | null {
  if (valor == null || ref == null) return null;
  return Math.round(valor - ref);
}

// ── Selos ──

export interface Selo {
  k: 'mais_vende' | 'melhor_conversao' | 'responde_rapido' | 'disciplina' | 'fila_parada' | 'conversao_abaixo' | 'contato_lento' | 'carga_alta' | 'falha_processo';
  rotulo: string;
  tipo: 'destaque' | 'alerta';
  /** Por que o selo apareceu, com o número. */
  motivo: string;
}

/** Destaques e alertas do vendedor, comparando com o time. Alertas primeiro. */
export function selosVendedor(l: IndicadoresVendedor, ref: ReferenciaTime, todos: IndicadoresVendedor[]): Selo[] {
  const s: Selo[] = [];
  const maxVendas = Math.max(0, ...todos.map((x) => x.vendas));
  const convs = todos.filter((x) => x.conversao != null && x.encerrados >= MIN_ENCERRADOS).map((x) => x.conversao!);
  const maxConv = convs.length ? Math.max(...convs) : null;

  if (l.semProximo + l.criticos >= 2) {
    s.push({ k: 'fila_parada', rotulo: 'Fila parada', tipo: 'alerta', motivo: `${l.semProximo} sem próximo passo e ${l.criticos} em prazo crítico.` });
  }
  if (l.conversao != null && ref.conversao != null && l.encerrados >= MIN_ENCERRADOS && l.conversao < ref.conversao - 10) {
    s.push({ k: 'conversao_abaixo', rotulo: 'Conversão abaixo do time', tipo: 'alerta', motivo: `${Math.round(l.conversao)}% contra ${Math.round(ref.conversao)}% do time.` });
  }
  if (l.tempoPrimeiroContatoMin != null && l.tempoPrimeiroContatoMin > 60) {
    s.push({ k: 'contato_lento', rotulo: 'Primeiro contato lento', tipo: 'alerta', motivo: `Mediana de ${l.tempoPrimeiroContatoMin} min; a meta é ${META_PRIMEIRO_CONTATO_MIN} min.` });
  }
  if (ref.abertos != null && l.abertos >= 5 && l.abertos > ref.abertos * 1.5) {
    s.push({ k: 'carga_alta', rotulo: 'Carga alta', tipo: 'alerta', motivo: `${l.abertos} negócios abertos; média do time ${Math.round(ref.abertos)}.` });
  }
  if (l.falhaProcesso > 0) {
    s.push({ k: 'falha_processo', rotulo: 'Perda por falha de processo', tipo: 'alerta', motivo: `${l.falhaProcesso} perdido(s) por motivo que avisa o gestor.` });
  }
  if (l.vendas > 0 && l.vendas === maxVendas) {
    s.push({ k: 'mais_vende', rotulo: 'Mais vendas', tipo: 'destaque', motivo: `${l.vendas} venda(s) no período, o maior número do time.` });
  }
  if (maxConv != null && l.conversao != null && l.encerrados >= MIN_ENCERRADOS && l.conversao === maxConv) {
    s.push({ k: 'melhor_conversao', rotulo: 'Melhor conversão', tipo: 'destaque', motivo: `${Math.round(l.conversao)}% dos encerrados viraram venda.` });
  }
  if (l.tempoPrimeiroContatoMin != null && l.tempoPrimeiroContatoMin <= META_PRIMEIRO_CONTATO_MIN
    && (ref.tempoPrimeiroContatoMin == null || l.tempoPrimeiroContatoMin <= ref.tempoPrimeiroContatoMin)) {
    s.push({ k: 'responde_rapido', rotulo: 'Responde rápido', tipo: 'destaque', motivo: `Primeiro contato em ${l.tempoPrimeiroContatoMin} min (mediana).` });
  }
  if (l.atrasadas === 0 && l.semProximo === 0 && l.atividadesConcluidas > 0 && (l.noPrazo.pct ?? 100) >= 90) {
    s.push({ k: 'disciplina', rotulo: 'Disciplina em dia', tipo: 'destaque', motivo: 'Nenhuma atrasada, nenhum negócio sem próximo passo.' });
  }
  return s;
}

// ── Ranking por critério ──

export type CriterioRanking = 'volume' | 'conversao' | 'qualidade' | 'disciplina';

export const CRITERIOS: Record<CriterioRanking, { rotulo: string; comoConta: string }> = {
  volume: { rotulo: 'Volume', comoConta: 'Receita de pagamentos aprovados no período.' },
  conversao: { rotulo: 'Conversão', comoConta: `Ganhos ÷ encerrados no período. Fica de fora quem encerrou menos de ${MIN_ENCERRADOS}.` },
  qualidade: {
    rotulo: 'Qualidade',
    comoConta: 'Provisório: % dos encerrados sem perda por falha de processo. Reembolso e venda com condição especial entram com o backend e passam a pesar aqui.',
  },
  disciplina: {
    rotulo: 'Disciplina',
    comoConta: '% de atividades concluídas no prazo, menos 10 pontos por atividade atrasada e por negócio sem próximo passo (mínimo 0).',
  },
};

/** Nota do vendedor no critério. null = sem base para avaliar. */
export function notaCriterio(l: IndicadoresVendedor, c: CriterioRanking): number | null {
  switch (c) {
    case 'volume': return l.receita;
    case 'conversao': return l.encerrados >= MIN_ENCERRADOS ? l.conversao : null;
    case 'qualidade':
      if (l.reembolsos != null && l.vendas > 0) return Math.max(0, 100 - (l.reembolsos / l.vendas) * 100);
      return l.encerrados ? Math.round(((l.encerrados - l.falhaProcesso) / l.encerrados) * 100) : null;
    case 'disciplina': {
      if (l.noPrazo.base === 0 && l.atividadesConcluidas === 0 && l.abertos === 0) return null;
      return Math.max(0, (l.noPrazo.pct ?? 100) - 10 * (l.atrasadas + l.semProximo));
    }
  }
}

export interface PosicaoRanking {
  vendedorId: string;
  nota: number | null;
  /** 1 = melhor. Empate divide a posição. null = sem base. */
  posicao: number | null;
}

/** Ordena o time no critério: maior nota primeiro, sem base no fim. */
export function rankingPor(linhas: IndicadoresVendedor[], c: CriterioRanking, nomeDe: (id: string) => string = (id) => id): PosicaoRanking[] {
  const comNota = linhas
    .filter((l): l is IndicadoresVendedor & { vendedorId: string } => l.vendedorId != null)
    .map((l) => ({ vendedorId: l.vendedorId, nota: notaCriterio(l, c) }));
  comNota.sort((a, b) => {
    if (a.nota == null && b.nota == null) return nomeDe(a.vendedorId).localeCompare(nomeDe(b.vendedorId), 'pt-BR');
    if (a.nota == null) return 1;
    if (b.nota == null) return -1;
    return b.nota - a.nota || nomeDe(a.vendedorId).localeCompare(nomeDe(b.vendedorId), 'pt-BR');
  });
  let pos = 0;
  let anterior: number | null = null;
  return comNota.map((x, i) => {
    if (x.nota == null) return { ...x, posicao: null };
    if (x.nota !== anterior) { pos = i + 1; anterior = x.nota; }
    return { ...x, posicao: pos };
  });
}

/** Posição do vendedor em cada critério ("2º de 3"). */
export function posicoesNoTime(linhas: IndicadoresVendedor[], vendedorId: string): Record<CriterioRanking, { posicao: number | null; de: number }> {
  const out = {} as Record<CriterioRanking, { posicao: number | null; de: number }>;
  for (const c of Object.keys(CRITERIOS) as CriterioRanking[]) {
    const r = rankingPor(linhas, c);
    out[c] = { posicao: r.find((x) => x.vendedorId === vendedorId)?.posicao ?? null, de: r.filter((x) => x.posicao != null).length };
  }
  return out;
}

// ── Tendência ──

/**
 * Receita por dia do vendedor (ou do time), para a sparkline. Períodos com menos de 7 dias mostram os
 * últimos 7 dias até o fim do período (um ponto só não é tendência).
 */
export function tendenciaReceita(base: BaseEquipe, donoId: string | null, i: Intervalo): { dia: string; valor: number }[] {
  const ini = i.fim - i.ini < 6 * D ? i.fim - 6 * D : i.ini;
  const dias = diasDoIntervalo({ ini, fim: i.fim });
  const meu = doDono(donoId);
  const porDia = new Map<string, number>();
  for (const n of base.negocios) {
    if (n.status !== 'ganho' || !meu(n.donoId) || !n.fechadoEm) continue;
    const t = Date.parse(n.fechadoEm);
    if (t < ini || t > i.fim) continue;
    const k = diaBR(n.fechadoEm);
    porDia.set(k, (porDia.get(k) ?? 0) + n.valor);
  }
  return dias.map((d) => ({ dia: d, valor: porDia.get(d) ?? 0 }));
}

// ── Detalhe do vendedor ──

export interface LinhaFunilPessoal {
  etapa: EtapaKey;
  rotulo: string;
  chegaram: number;
  /** % que passou da etapa anterior. null na entrada. */
  passagem: number | null;
  passagemTime: number | null;
}

/** Negócios de venda ativa trabalhados no período: nasceram ou encerraram nele, ou seguem abertos. */
function negociosDoPeriodo(base: BaseEquipe, donoId: string | null, i: Intervalo): Negocio[] {
  const meu = doDono(donoId);
  return base.negocios.filter((n) => n.origem === 'venda_ativa' && meu(n.donoId)
    && (n.status === 'aberto' || dentro(n.criadoEm, i) || dentro(n.fechadoEm, i)));
}

function passagens(negs: Negocio[]): { etapa: EtapaKey; chegaram: number; passagem: number | null }[] {
  const ordem = ETAPAS.map((e) => e.key);
  const chegaram = ordem.map((e, k) => negs.filter((n) => n.status === 'ganho' || ordem.indexOf(n.etapa) >= k).length);
  return ordem.map((e, k) => ({
    etapa: e,
    chegaram: chegaram[k],
    passagem: k === 0 ? null : chegaram[k - 1] ? Math.round((chegaram[k] / chegaram[k - 1]) * 100) : null,
  }));
}

/** Funil pessoal pelo PAPEL da etapa (vale para qualquer funil), com a passagem do time ao lado. */
export function funilPessoal(base: BaseEquipe, donoId: string, i: Intervalo, time: string[]): LinhaFunilPessoal[] {
  const meu = passagens(negociosDoPeriodo(base, donoId, i));
  const doTime = passagens(negociosDoPeriodo(base, null, i).filter((n) => n.donoId && time.includes(n.donoId)));
  return meu.map((l, k) => ({ ...l, rotulo: ROTULO_PAPEL[l.etapa], passagemTime: doTime[k].passagem }));
}

export const TIPOS_ATIVIDADE: TipoAtividade[] = ['whatsapp', 'ligacao', 'email', 'tarefa', 'reuniao'];

/** Atividades concluídas por tipo no período, do vendedor e a média por vendedor do time. */
export function atividadesPorTipo(base: BaseEquipe, donoId: string, i: Intervalo, time: string[]): { tipo: TipoAtividade; vendedor: number; mediaTime: number }[] {
  const n = Math.max(1, time.length);
  return TIPOS_ATIVIDADE.map((tipo) => {
    const concl = base.atividades.filter((a) => a.tipo === tipo && dentro(a.concluidaEm, i));
    return {
      tipo,
      vendedor: concl.filter((a) => a.donoId === donoId).length,
      mediaTime: Math.round((concl.filter((a) => time.includes(a.donoId)).length / n) * 10) / 10,
    };
  });
}

export const DIAS_SEMANA = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
export const FAIXAS_HORA = [
  { rotulo: '8–10h', ini: 8, fim: 10 },
  { rotulo: '10–12h', ini: 10, fim: 12 },
  { rotulo: '12–14h', ini: 12, fim: 14 },
  { rotulo: '14–16h', ini: 14, fim: 16 },
  { rotulo: '16–18h', ini: 16, fim: 18 },
  { rotulo: '18–20h', ini: 18, fim: 20 },
  { rotulo: 'Fora', ini: -1, fim: -1 },
];

/** Mapa de calor: atividades concluídas por dia da semana × faixa de hora (Brasília). */
export function mapaCalor(base: BaseEquipe, donoId: string, i: Intervalo): { celulas: number[][]; max: number; total: number } {
  const celulas = DIAS_SEMANA.map(() => FAIXAS_HORA.map(() => 0));
  let total = 0;
  for (const a of base.atividades) {
    if (a.donoId !== donoId || !dentro(a.concluidaEm, i)) continue;
    const local = new Date(Date.parse(a.concluidaEm!) - FUSO);
    const dia = (local.getUTCDay() + 6) % 7; // segunda = 0
    const h = local.getUTCHours();
    let f = FAIXAS_HORA.findIndex((x) => h >= x.ini && h < x.fim);
    if (f < 0) f = FAIXAS_HORA.length - 1;
    celulas[dia][f] += 1;
    total += 1;
  }
  return { celulas, max: Math.max(0, ...celulas.flat()), total };
}

/** Cadência (toques com dia de cadência) que venceram no período: concluídos no prazo, atrasados e em aberto. */
export function cadenciaCumprida(base: BaseEquipe, donoId: string | null, i: Intervalo): { previstos: number; noPrazo: number; comAtraso: number; pendentes: number; pct: number | null } {
  const meu = doDono(donoId);
  const lista = base.atividades.filter((a) => a.cadenciaDia != null && meu(a.donoId) && dentro(a.venceEm, i) && Date.parse(a.venceEm) <= base.agora.getTime());
  const noPrazo = lista.filter((a) => a.concluidaEm && a.concluidaEm <= a.venceEm).length;
  const comAtraso = lista.filter((a) => a.concluidaEm && a.concluidaEm > a.venceEm).length;
  return { previstos: lista.length, noPrazo, comAtraso, pendentes: lista.length - noPrazo - comAtraso, pct: lista.length ? Math.round((noPrazo / lista.length) * 100) : null };
}

/** Tempo médio parado em cada etapa (estimativa pelos abertos), do vendedor e do time. */
export function tempoPorEtapaComparado(base: BaseEquipe, donoId: string, time: string[]): { etapa: EtapaKey; rotulo: string; abertos: number; mediaMin: number | null; mediaTimeMin: number | null }[] {
  const meu = tempoMedioPorEtapa(base.negocios.filter((n) => n.donoId === donoId), 'todos', base.agora);
  const doTime = tempoMedioPorEtapa(base.negocios.filter((n) => n.donoId && time.includes(n.donoId)), 'todos', base.agora);
  return meu.map((l, k) => ({ etapa: l.etapa, rotulo: ROTULO_PAPEL[l.etapa], abertos: l.abertos, mediaMin: l.mediaMin, mediaTimeMin: doTime[k]?.mediaMin ?? null }));
}

/** Perdidos do vendedor no período por motivo do cadastro, com a fatia do motivo no time. */
export function perdidosDoVendedor(base: BaseEquipe, donoId: string, i: Intervalo, time: string[]): { motivo: MotivoPerda; rotulo: string; quantidade: number; pct: number; pctTime: number; falha: boolean }[] {
  const doPeriodo = (n: Negocio) => n.status === 'perdido' && dentro(n.fechadoEm, i);
  const meus = base.negocios.filter((n) => n.donoId === donoId && doPeriodo(n));
  const doTime = base.negocios.filter((n) => n.donoId && time.includes(n.donoId) && doPeriodo(n));
  const linhasTime = new Map(perdidosPorMotivo(doTime, 'todos', base.motivos).map((l) => [l.motivo, l.quantidade]));
  const falha = motivosDeFalha(base.motivos);
  return perdidosPorMotivo(meus, 'todos', base.motivos)
    .filter((l) => l.quantidade > 0)
    .sort((a, b) => b.quantidade - a.quantidade)
    .map((l) => ({
      motivo: l.motivo,
      rotulo: l.rotulo,
      quantidade: l.quantidade,
      pct: Math.round((l.quantidade / meus.length) * 100),
      pctTime: doTime.length ? Math.round(((linhasTime.get(l.motivo) ?? 0) / doTime.length) * 100) : 0,
      falha: falha.has(l.motivo),
    }));
}

export interface GrupoVenda { chave: string; rotulo: string; quantidade: number; valor: number }

/** Vendas do vendedor no período agrupadas por produto ou por funil. */
export function vendasAgrupadas(base: BaseEquipe, donoId: string, i: Intervalo, por: 'produto' | 'funil'): GrupoVenda[] {
  const mapa = new Map<string, GrupoVenda>();
  for (const n of base.negocios) {
    if (n.donoId !== donoId || n.status !== 'ganho' || !dentro(n.fechadoEm, i)) continue;
    const chave = por === 'produto' ? n.produto : n.funilId;
    const rotulo = por === 'produto' ? produtoDe(n.produto).nome : base.funis.find((f) => f.id === n.funilId)?.nome ?? 'Funil arquivado';
    const g = mapa.get(chave) ?? { chave, rotulo, quantidade: 0, valor: 0 };
    g.quantidade += 1;
    g.valor += n.valor;
    mapa.set(chave, g);
  }
  return [...mapa.values()].sort((a, b) => b.valor - a.valor || a.rotulo.localeCompare(b.rotulo, 'pt-BR'));
}

export interface LinhaCarteira {
  etapa: EtapaKey;
  rotulo: string;
  abertos: number;
  valor: number;
  atencao: number;
  criticos: number;
}

/** Carteira atual: negócios abertos do vendedor por papel da etapa, com prazo em atenção/crítico. */
export function carteira(base: BaseEquipe, donoId: string): { linhas: LinhaCarteira[]; criticos: Negocio[] } {
  const abertos = base.negocios.filter((n) => n.donoId === donoId && n.status === 'aberto');
  const linhas = ETAPAS.filter((e) => e.key !== 'fechado').map((e) => {
    const daqui = abertos.filter((n) => n.etapa === e.key);
    return {
      etapa: e.key,
      rotulo: ROTULO_PAPEL[e.key],
      abertos: daqui.length,
      valor: daqui.reduce((s, n) => s + n.valor, 0),
      atencao: daqui.filter((n) => situacaoSla(n, base.agora) === 'atencao').length,
      criticos: daqui.filter((n) => situacaoSla(n, base.agora) === 'critico').length,
    };
  });
  const criticos = abertos
    .filter((n) => situacaoSla(n, base.agora) === 'critico')
    .sort((a, b) => a.etapaDesde.localeCompare(b.etapaDesde));
  return { linhas, criticos };
}

/** Conversas em que o lead escreveu por último (aguardando o vendedor), mais antiga primeiro. */
export function conversasSemResposta(base: Pick<BaseEquipe, 'conversas' | 'agora'>, donoId: string | null): { contatoId: string; esperaMin: number; naoLidas: number; texto: string }[] {
  return base.conversas
    .filter((c) => c.ultimaMensagem.direcao === 'entrada' && c.atribuidaA != null && (donoId == null || c.atribuidaA === donoId))
    .map((c) => ({
      contatoId: c.contatoId,
      esperaMin: Math.max(0, Math.round((base.agora.getTime() - Date.parse(c.ultimaMensagem.em)) / 60000)),
      naoLidas: c.naoLidas,
      texto: c.ultimaMensagem.texto,
    }))
    .sort((a, b) => b.esperaMin - a.esperaMin);
}

/** "05/10" (reexporta para a tela). */
export { rotuloDia };
