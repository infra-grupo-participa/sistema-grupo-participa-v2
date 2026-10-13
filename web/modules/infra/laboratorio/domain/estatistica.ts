// Estatística do Laboratório de decisões e testes (docs/projetos/laboratorio/playbook-de-decisoes-e-testes.md).
// Pura, sem dependência: a tela calcula e o banco guarda o cálculo como foi lido.
// Régua da casa: 95% de confiança (α = 0,05, bicaudal) e 80% de chance de enxergar a diferença (poder).

export const ALFA = 0.05;
export const PODER = 0.8;

/** Distribuição normal acumulada (Abramowitz-Stegun 7.1.26, erro < 1,5e-7). */
export function normalCdf(z: number): number {
  const t = 1 / (1 + 0.3275911 * Math.abs(z) / Math.SQRT2);
  const y = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-(z * z) / 2);
  return z >= 0 ? 0.5 * (1 + y) : 0.5 * (1 - y);
}

/** Inversa da normal (Acklam). */
export function normalInv(p: number): number {
  if (p <= 0 || p >= 1) throw new Error('p fora de (0,1)');
  const a = [-39.69683028665376, 220.9460984245205, -275.9285104469687, 138.357751867269, -30.66479806614716, 2.506628277459239];
  const b = [-54.47609879822406, 161.5858368580409, -155.6989798598866, 66.80131188771972, -13.28068155288572];
  const c = [-0.007784894002430293, -0.3223964580411365, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783];
  const d = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416];
  const pl = 0.02425;
  if (p < pl) {
    const q = Math.sqrt(-2 * Math.log(p));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (p > 1 - pl) return -normalInv(1 - p);
  const q = p - 0.5;
  const r = q * q;
  return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
}

const zAlfa = (alfa = ALFA) => normalInv(1 - alfa / 2);
const zPoder = (poder = PODER) => normalInv(poder);

/**
 * Casos POR GRUPO para enxergar uma melhora relativa `regua` numa taxa `taxaBase` (seção 7.1).
 * Fórmula clássica de duas proporções (variância agrupada sob H0). Reproduz a tabela do playbook.
 */
export function amostraTaxa(taxaBase: number, regua: number, alfa = ALFA, poder = PODER): number {
  if (!(taxaBase > 0 && taxaBase < 1) || !(regua > 0)) return NaN;
  const p1 = taxaBase;
  const p2 = Math.min(taxaBase * (1 + regua), 0.9999);
  const pm = (p1 + p2) / 2;
  const num = zAlfa(alfa) * Math.sqrt(2 * pm * (1 - pm)) + zPoder(poder) * Math.sqrt(p1 * (1 - p1) + p2 * (1 - p2));
  return Math.ceil((num * num) / ((p2 - p1) * (p2 - p1)));
}

/**
 * RESULTADOS por grupo (leads, MQL, vendas) para enxergar uma diferença `regua` num custo (seção 7.2).
 * Premissa: os resultados seguem Poisson; compara-se o log da razão das taxas (variância 1/n + 1/n).
 * "O dobro" = régua 1 (custo 2x). Reproduz ~33 / 95 / 230 / 315.
 */
export function amostraCusto(regua: number, alfa = ALFA, poder = PODER): number {
  if (!(regua > 0)) return NaN;
  const z = zAlfa(alfa) + zPoder(poder);
  const l = Math.log(1 + regua);
  return Math.ceil((2 * z * z) / (l * l));
}

/** Chance de o teste mostrar uma melhora relativa `efeito` numa taxa, com `n` casos por grupo (seção 6A.2). */
export function poderTaxa(taxaBase: number, efeito: number, n: number, alfa = ALFA): number {
  if (!(taxaBase > 0 && taxaBase < 1) || !(efeito > 0) || !(n > 0)) return NaN;
  const p1 = taxaBase;
  const p2 = Math.min(taxaBase * (1 + efeito), 0.9999);
  const pm = (p1 + p2) / 2;
  const z = (Math.abs(p2 - p1) * Math.sqrt(n) - zAlfa(alfa) * Math.sqrt(2 * pm * (1 - pm))) / Math.sqrt(p1 * (1 - p1) + p2 * (1 - p2));
  return normalCdf(z);
}

/** Chance de enxergar uma diferença `efeito` num custo, com `n` resultados por grupo. */
export function poderCusto(efeito: number, n: number, alfa = ALFA): number {
  if (!(efeito > 0) || !(n > 0)) return NaN;
  return normalCdf(Math.abs(Math.log(1 + efeito)) * Math.sqrt(n / 2) - zAlfa(alfa));
}

export const EFEITOS_SENSIBILIDADE = [0.1, 0.15, 0.2, 0.3, 0.5] as const;

export function sensibilidade(tipo: 'taxa' | 'custo', n: number, taxaBase?: number | null): { efeito: number; chance: number }[] {
  return EFEITOS_SENSIBILIDADE.map((efeito) => ({
    efeito,
    chance: tipo === 'taxa' ? poderTaxa(taxaBase ?? NaN, efeito, n) : poderCusto(efeito, n),
  }));
}

export interface Leitura {
  /** Melhora relativa de B sobre A no que importa (taxa maior ou custo menor), em fração. */
  beneficio: number;
  /** Intervalo de 95% do benefício relativo. */
  ic: [number, number];
  /** 1 − p bilateral: "a chance de NÃO ser acaso", como o playbook usa (seção 2). */
  confianca: number;
  /** Chance de B ser melhor que A (normal aproximada). */
  probBMelhor: number;
  detalhe: Record<string, number>;
}

/** Leitura de taxa: teste z de duas proporções (agrupado) e IC 95% pela variância não agrupada. */
export function lerTaxa(aN: number, aX: number, bN: number, bX: number): Leitura | null {
  if (!(aN > 0 && bN > 0) || aX < 0 || bX < 0 || aX > aN || bX > bN) return null;
  const pA = aX / aN;
  const pB = bX / bN;
  const p = (aX + bX) / (aN + bN);
  const sePool = Math.sqrt(p * (1 - p) * (1 / aN + 1 / bN));
  const se = Math.sqrt((pA * (1 - pA)) / aN + (pB * (1 - pB)) / bN);
  const dif = pB - pA;
  const z = sePool > 0 ? dif / sePool : 0;
  const confianca = 1 - 2 * (1 - normalCdf(Math.abs(z)));
  const za = zAlfa();
  const base = pA > 0 ? pA : NaN;
  return {
    beneficio: dif / base,
    ic: [(dif - za * se) / base, (dif + za * se) / base],
    confianca,
    probBMelhor: se > 0 ? normalCdf(dif / se) : 0.5,
    detalhe: { taxaA: pA, taxaB: pB, diferencaAbsoluta: dif, z },
  };
}

/**
 * Leitura de custo: gasto e resultados de cada grupo. Compara resultados por real (Poisson, log da razão);
 * benefício = quanto B rende a mais por real (custo de B menor ⇒ benefício positivo).
 */
export function lerCusto(aGasto: number, aRes: number, bGasto: number, bRes: number): Leitura | null {
  if (!(aGasto > 0 && bGasto > 0 && aRes > 0 && bRes > 0)) return null;
  const razao = bRes / bGasto / (aRes / aGasto);
  const l = Math.log(razao);
  const se = Math.sqrt(1 / aRes + 1 / bRes);
  const z = l / se;
  const za = zAlfa();
  return {
    beneficio: razao - 1,
    ic: [Math.exp(l - za * se) - 1, Math.exp(l + za * se) - 1],
    confianca: 1 - 2 * (1 - normalCdf(Math.abs(z))),
    probBMelhor: normalCdf(z),
    detalhe: { custoA: aGasto / aRes, custoB: bGasto / bRes, razao, z },
  };
}

export type Resultado = 'vencedor' | 'provavel' | 'empate' | 'inconclusivo';

export const ROTULO_RESULTADO: Record<Resultado, string> = {
  vencedor: 'Vencedor',
  provavel: 'Provável',
  empate: 'Empate prático',
  inconclusivo: 'Inconclusivo',
};

export interface Classificacao {
  resultado: Resultado;
  quem: 'A' | 'B' | null;
  explicacao: string;
}

/**
 * Os quatro resultados da seção 8, na ordem das perguntas: amostra → medição → tamanho → confiança.
 * Confiança ≥ 95% = comprovado (vencedor, mesmo abaixo da régua: a régua é sensibilidade, não meta — 6A.5);
 * 90–95% = provável; intervalo inteiro dentro de ±régua = empate prático; o resto é inconclusivo.
 */
export function classificar(l: Leitura, op: { regua: number | null; amostraChegou: boolean; medicaoOk: boolean }): Classificacao {
  const quem: 'A' | 'B' = l.beneficio >= 0 ? 'B' : 'A';
  const nome = quem === 'B' ? 'a versão nova (B)' : 'a versão atual (A)';
  if (!op.amostraChegou) {
    return { resultado: 'inconclusivo', quem: null, explicacao: 'A amostra mínima ainda não chegou. Mesmo que pareça óbvio, o resultado é inconclusivo: estenda o teste ou decida por outro critério, dizendo qual.' };
  }
  if (!op.medicaoOk) {
    return { resultado: 'inconclusivo', quem: null, explicacao: 'A medição ou o contexto teve problema. Anote o que houve e desconfie: nenhuma estatística salva dado quebrado.' };
  }
  if (l.confianca >= 0.95) {
    return { resultado: 'vencedor', quem, explicacao: `Comprovado: ${nome} é melhor, com ${(l.confianca * 100).toFixed(1).replace('.', ',')}% de confiança. Vira o padrão. Confira se ganhou também no degrau de cima (venda, presença, qualidade).` };
  }
  if (l.confianca >= 0.9) {
    return { resultado: 'provavel', quem, explicacao: `Provável: ${nome} tende a ser melhor (${(l.confianca * 100).toFixed(1).replace('.', ',')}%). Adote aos poucos e mantenha a versão antiga em parte até confirmar.` };
  }
  if (op.regua != null && l.ic[0] > -op.regua && l.ic[1] < op.regua) {
    return { resultado: 'empate', quem: null, explicacao: `Empate prático: o intervalo inteiro (${pct(l.ic[0])} a ${pct(l.ic[1])}) fica dentro da menor diferença que importa (±${pct(op.regua)}). Fique com a mais barata ou a mais simples.` };
  }
  return { resultado: 'inconclusivo', quem: null, explicacao: `Inconclusivo: a confiança é de ${(l.confianca * 100).toFixed(1).replace('.', ',')}% (abaixo de 90% é ruído) e a margem vai de ${pct(l.ic[0])} a ${pct(l.ic[1])}. Não quer dizer que são iguais: ainda não sabemos.` };
}

export function pct(x: number, casas = 0): string {
  if (!Number.isFinite(x)) return '—';
  const s = (x * 100).toFixed(casas).replace('.', ',');
  return `${x > 0 ? '+' : ''}${s}%`;
}

/** Escolha do nível pelas perguntas da seção 3. */
export function sugerirNivel(r: { pequenaEReversivel: boolean; temVolumeESorteio: boolean }): 1 | 2 | 3 {
  if (r.pequenaEReversivel) return 1;
  return r.temVolumeESorteio ? 3 : 2;
}

/** Pergunta de controle (seção 10): se as duas respostas forem iguais, não precisa testar. */
export function precisaTestar(seA: string, seB: string): boolean {
  const n = (s: string) => s.toLowerCase().replace(/[\s.,;!]+/g, ' ').trim();
  return !(n(seA) && n(seA) === n(seB));
}
