// Aba "Análise" do Faturamento (João, 27/09: "lógicas de econometria… soluções inteligentes que façam sentido para
// auxiliar o financeiro"). Ele escolheu quatro: dinheiro já contratado, previsão com faixa, dependência de eventos e
// crescimento real. Funções PURAS; os números vêm de fn_fin_hotmart_faturamento, fn_fin_contratado e
// fn_fin_faturamento_por_acao (20260928p).

export interface MesValor { chave: string; bruto: number; vendas: number }

const soma = (xs: number[]) => xs.reduce((s, v) => s + v, 0);
const media = (xs: number[]) => (xs.length ? soma(xs) / xs.length : 0);

/** Média móvel simples de `n` períodos (os primeiros n−1 usam o que existe até ali). */
export function mediaMovel(valores: number[], n: number): number[] {
  return valores.map((_, i) => {
    const ini = Math.max(0, i - n + 1);
    const janela = valores.slice(ini, i + 1);
    return janela.reduce((s, v) => s + v, 0) / janela.length;
  });
}

/** Quantil por interpolação linear (xs não precisa vir ordenado). */
export function quantil(xs: number[], q: number): number {
  if (!xs.length) return NaN;
  const o = [...xs].sort((a, b) => a - b);
  const pos = (o.length - 1) * q;
  const i = Math.floor(pos);
  return o[i] + (o[Math.min(i + 1, o.length - 1)] - o[i]) * (pos - i);
}

/** 'YYYY-MM' somado de `n` meses. */
export function somarMeses(chave: string, n: number): string {
  const [y, m] = chave.split('-').map(Number);
  const t = y * 12 + (m - 1) + n;
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}`;
}

/** Meses FECHADOS (antes do mês de hoje), contínuos, a partir da série diária. Mês sem venda entra com zero. */
export function mesesFechados(dias: { dia: string; bruto: number; vendas: number }[], hojeISO: string): MesValor[] {
  const atual = hojeISO.slice(0, 7);
  const por = new Map<string, MesValor>();
  for (const d of dias) {
    const k = d.dia.slice(0, 7);
    if (k >= atual) continue;
    const m = por.get(k) ?? { chave: k, bruto: 0, vendas: 0 };
    m.bruto += d.bruto; m.vendas += d.vendas;
    por.set(k, m);
  }
  if (!por.size) return [];
  const chaves = [...por.keys()].sort();
  const saida: MesValor[] = [];
  for (let k = chaves[0]; k < atual; k = somarMeses(k, 1)) saida.push(por.get(k) ?? { chave: k, bruto: 0, vendas: 0 });
  return saida;
}

// ─── Previsão com faixa ─────────────────────────────────────────────────────
// Três modelos simples; o que errou menos nos últimos meses (backtest) é o escolhido. A faixa não é "±10%" chutado:
// é onde o valor real caiu, em 8 de cada 10 testes, em relação ao que o modelo previa (quantis 10% e 90% da razão
// real ÷ previsto). Mês com evento grande estoura a faixa — é exatamente isso que a "Dependência de eventos" mede.

export interface ModeloPrevisao { id: 'media3' | 'media12' | 'sazonal'; nome: string }
export const MODELOS: ModeloPrevisao[] = [
  { id: 'media3', nome: 'média dos últimos 3 meses' },
  { id: 'media12', nome: 'média dos últimos 12 meses' },
  { id: 'sazonal', nome: 'mesmo mês do ano anterior × crescimento dos últimos 12 meses' },
];

/** Previsão de um modelo para o h-ésimo mês depois do fim de `hist` (h = 1, 2, 3). null = histórico insuficiente. */
export function preverModelo(id: ModeloPrevisao['id'], hist: number[], h: number): number | null {
  const n = hist.length;
  if (id === 'media3') return n >= 3 ? media(hist.slice(-3)) : null;
  if (id === 'media12') return n >= 12 ? media(hist.slice(-12)) : null;
  if (n < 24) return null;
  const ult = soma(hist.slice(-12)), ant = soma(hist.slice(-24, -12));
  if (ant <= 0) return null;
  const cresc = Math.min(2, Math.max(0.5, ult / ant));
  return hist[n - 12 + h - 1] * cresc;
}

export interface MesPrevisto { chave: string; conservador: number; provavel: number; otimista: number; parcial: number | null }
export interface Previsao {
  modelo: ModeloPrevisao;
  /** Erro médio do modelo nos testes: Σ|real − previsto| ÷ Σ real (WAPE). */
  erro: number;
  testes: number;
  meses: MesPrevisto[];
}

/**
 * Previsão dos próximos `h` meses, começando pelo mês corrente. `hist` = meses fechados (mesesFechados).
 * Mês corrente = o que já entrou (`parcialAtual`) + o modelo só para a fração que falta (`decorrido` = 0–1).
 * Backtest: origens nos últimos `janela` meses, horizontes 1..h; exige 8+ testes para o modelo concorrer.
 */
export function preverComFaixa(hist: MesValor[], parcialAtual: number, decorrido = 0, h = 3, janela = 12): Previsao | null {
  if (hist.length < 6) return null;
  const x = hist.map((m) => m.bruto);
  const n = x.length;
  let melhor: { modelo: ModeloPrevisao; erro: number; razoes: number[] } | null = null;
  for (const modelo of MODELOS) {
    let absErr = 0, real = 0;
    const razoes: number[] = [];
    for (let o = Math.max(1, n - janela - h + 1); o < n; o++) {
      for (let k = 1; k <= h && o + k - 1 < n; k++) {
        const p = preverModelo(modelo.id, x.slice(0, o), k);
        if (p == null || p <= 0) continue;
        const a = x[o + k - 1];
        absErr += Math.abs(a - p); real += a; razoes.push(a / p);
      }
    }
    if (razoes.length < 8 || real <= 0) continue;
    const erro = absErr / real;
    if (!melhor || erro < melhor.erro) melhor = { modelo, erro, razoes };
  }
  if (!melhor) return null;
  const q10 = quantil(melhor.razoes, 0.1), q50 = quantil(melhor.razoes, 0.5), q90 = quantil(melhor.razoes, 0.9);
  const meses: MesPrevisto[] = [];
  for (let k = 1; k <= h; k++) {
    const p = preverModelo(melhor.modelo.id, x, k) ?? 0;
    const base = k === 1 ? parcialAtual : 0;
    const resto = k === 1 ? Math.max(0, 1 - decorrido) : 1;
    meses.push({
      chave: somarMeses(hist[n - 1].chave, k),
      conservador: base + p * q10 * resto,
      provavel: base + p * q50 * resto,
      otimista: base + p * q90 * resto,
      parcial: k === 1 ? parcialAtual : null,
    });
  }
  return { modelo: melhor.modelo, erro: melhor.erro, testes: melhor.razoes.length, meses };
}

// ─── Dependência de eventos ─────────────────────────────────────────────────

export interface FaturamentoAcao {
  acao: string; canal: string | null; inicio: string; fim: string; dias: number;
  vendas: number; compradores: number; bruto: number; liquido: number;
}
export interface AcaoRanqueada extends FaturamentoAcao { porDia: number; vezesDiaComum: number | null }
export interface Dependencia {
  de: string; ate: string;
  total: number;
  /** Fração do bruto que entrou em dia coberto por alguma ação. */
  emAcao: number;
  /** Fração dos dias que tiveram ação. */
  diasEmAcao: number;
  /** Média diária FORA de ação: o "dia comum". */
  diaComum: number;
  /** Fração do bruto que veio dos 10% de dias que mais venderam. */
  top10: number;
  acoes: AcaoRanqueada[];
}

/** Cruza a série diária com as janelas das ações (fin.acoes), do início da primeira ação até hoje. */
export function dependenciaEventos(dias: { dia: string; bruto: number }[], acoes: FaturamentoAcao[], hojeISO: string): Dependencia | null {
  const validas = acoes.filter((a) => a.inicio && a.fim);
  if (!validas.length) return null;
  const de = validas.map((a) => a.inicio).sort()[0];
  const ate = hojeISO.slice(0, 10);
  const janela = dias.filter((d) => d.dia >= de && d.dia <= ate);
  if (!janela.length) return null;
  const naAcao = (dia: string) => validas.some((a) => dia >= a.inicio && dia <= a.fim);
  const total = soma(janela.map((d) => d.bruto));
  const dentro = janela.filter((d) => naAcao(d.dia));
  const fora = janela.filter((d) => !naAcao(d.dia));
  const diaComum = fora.length ? media(fora.map((d) => d.bruto)) : 0;
  const ordenados = janela.map((d) => d.bruto).sort((a, b) => b - a);
  const nTop = Math.max(1, Math.round(ordenados.length * 0.1));
  const ranqueadas = validas
    .map((a) => {
      const porDia = a.bruto / Math.max(1, a.dias);
      return { ...a, porDia, vezesDiaComum: diaComum > 0 ? porDia / diaComum : null };
    })
    .sort((a, b) => b.bruto - a.bruto);
  return {
    de, ate, total,
    emAcao: total > 0 ? soma(dentro.map((d) => d.bruto)) / total : 0,
    diasEmAcao: dentro.length / janela.length,
    diaComum,
    top10: total > 0 ? soma(ordenados.slice(0, nTop)) / total : 0,
    acoes: ranqueadas,
  };
}

// ─── Crescimento real ───────────────────────────────────────────────────────

/** Regressão linear simples y = a + b·x (x = 0..n−1). R² = quanto da variação a reta explica. */
export function regressao(ys: number[]): { inclinacao: number; r2: number } | null {
  const n = ys.length;
  if (n < 3) return null;
  const mx = (n - 1) / 2, my = media(ys);
  let sxy = 0, sxx = 0, syy = 0;
  ys.forEach((y, i) => { sxy += (i - mx) * (y - my); sxx += (i - mx) ** 2; syy += (y - my) ** 2; });
  const b = sxy / sxx;
  return { inclinacao: b, r2: syy > 0 ? (sxy * sxy) / (sxx * syy) : 0 };
}

export interface Crescimento {
  /** Último mês fechado contra o mesmo mês do ano anterior. */
  yoy: { chave: string; atual: number; anterior: number; pct: number | null } | null;
  /** Mês corrente até hoje contra os mesmos dias do mesmo mês do ano anterior. */
  mesAteHoje: { atual: number; anterior: number; pct: number | null; dia: number } | null;
  /** Soma dos últimos 12 meses fechados contra os 12 antes deles (tira a sazonalidade). */
  doze: { atual: number; anterior: number; pct: number | null } | null;
  /** Tendência dos últimos 12 meses fechados: R$/mês e a mesma inclinação em % da média. */
  tendencia: { porMes: number; pctMedia: number; r2: number } | null;
  ticket: { atual: number; anterior: number; pct: number | null } | null;
  /** Soma móvel de 12 meses, mês a mês (linha sem sazonalidade). */
  movel12: { chave: string; valor: number }[];
}

const variacao = (a: number, b: number) => (b > 0 ? ((a - b) / b) * 100 : null);

export function crescimentoReal(hist: MesValor[], dias: { dia: string; bruto: number }[], hojeISO: string): Crescimento {
  const n = hist.length;
  const ult = hist[n - 1];
  const mesmoAnt = ult ? hist.find((m) => m.chave === somarMeses(ult.chave, -12)) : undefined;
  const hoje = hojeISO.slice(0, 10);
  const dia = Number(hoje.slice(8, 10));
  const mesAtual = hoje.slice(0, 7), mesAntAno = somarMeses(mesAtual, -12);
  const temAnoAnterior = dias.some((d) => d.dia <= `${mesAntAno}-31`);
  const somaAte = (pref: string) => soma(dias.filter((d) => d.dia.startsWith(pref) && Number(d.dia.slice(8, 10)) <= dia).map((d) => d.bruto));
  const u12 = hist.slice(-12), a12 = n >= 24 ? hist.slice(-24, -12) : [];
  const reg = u12.length === 12 ? regressao(u12.map((m) => m.bruto)) : null;
  const med12 = media(u12.map((m) => m.bruto));
  const tk = (ms: MesValor[]) => { const v = soma(ms.map((m) => m.vendas)); return v ? soma(ms.map((m) => m.bruto)) / v : 0; };
  const movel12: { chave: string; valor: number }[] = [];
  for (let i = 11; i < n; i++) movel12.push({ chave: hist[i].chave, valor: soma(hist.slice(i - 11, i + 1).map((m) => m.bruto)) });
  return {
    yoy: ult && mesmoAnt ? { chave: ult.chave, atual: ult.bruto, anterior: mesmoAnt.bruto, pct: variacao(ult.bruto, mesmoAnt.bruto) } : null,
    mesAteHoje: temAnoAnterior ? (() => {
      const a = somaAte(mesAtual), b = somaAte(mesAntAno);
      return { atual: a, anterior: b, pct: variacao(a, b), dia };
    })() : null,
    doze: a12.length === 12 ? (() => {
      const a = soma(u12.map((m) => m.bruto)), b = soma(a12.map((m) => m.bruto));
      return { atual: a, anterior: b, pct: variacao(a, b) };
    })() : null,
    tendencia: reg && med12 > 0 ? { porMes: reg.inclinacao, pctMedia: (reg.inclinacao / med12) * 100, r2: reg.r2 } : null,
    ticket: a12.length === 12 ? { atual: tk(u12), anterior: tk(a12), pct: variacao(tk(u12), tk(a12)) } : null,
    movel12,
  };
}

// ─── Dinheiro já contratado ─────────────────────────────────────────────────

export type FonteContratado = 'parcelado' | 'assinatura' | 'combinado';
export interface LinhaContratado { mes: string; fonte: FonteContratado; valor: number; pessoas: number; em_risco: number }
export interface MesContratado { chave: string; parcelado: number; assinatura: number; combinado: number; total: number; emRisco: number }

/** Linhas de fn_fin_contratado → um registro por mês (YYYY-MM), com o total e o que está em risco. */
export function agruparContratado(linhas: LinhaContratado[]): MesContratado[] {
  const por = new Map<string, MesContratado>();
  for (const l of linhas) {
    const k = String(l.mes).slice(0, 7);
    const m = por.get(k) ?? { chave: k, parcelado: 0, assinatura: 0, combinado: 0, total: 0, emRisco: 0 };
    const v = Number(l.valor) || 0;
    m[l.fonte] += v; m.total += v; m.emRisco += Number(l.em_risco) || 0;
    por.set(k, m);
  }
  return [...por.values()].sort((a, b) => a.chave.localeCompare(b.chave));
}
