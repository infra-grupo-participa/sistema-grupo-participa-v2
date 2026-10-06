// Marketing > Web > Melhorias: testes A/B entre VARIAÇÕES DA MESMA PÁGINA, pelo padrão de código da casa (ak1, ak1-b,
// ak1-c: mkt.paginas.codigo). A é a página sem sufixo; cada variação é comparada com ela. Cada versão conta quem ENTROU
// por ela (entradas, como o Radar). Regras portadas de sistemas/radar/_interface/src/lib/testes.ts do Luiz (05/10/2026):
// teste de duas proporções (compararTaxas), amostra para 80% de poder e 95% de confiança (fator 7,85) depois das
// primeiras 50 entradas de A, divisão meio a meio (qui-quadrado > 3,84 e 3 pontos de diferença), veredito travado até a
// amostra E 7 dias. Diferença que se quer enxergar: 20% (o padrão do Radar, salvar_teste da 024).
// Diferente do Radar: aqui o teste não é cadastrado (sem início, fim e hipótese salvos); o período é o da tela.
import { compararTaxas, type Comparacao } from './analise';
import type { PaginaMelhorias } from './tipos';

export const EFEITO_PADRAO = 0.2;
const CODIGO = /^([a-z]{2}[0-9]{1,3})(?:-([a-z]))?$/;

/** amostra por versão para 80% de poder e 95% de confiança (duas caudas); p = taxa de A, efeito = diferença relativa */
export function amostraNecessaria(p: number, efeito: number): number {
  const p2 = Math.min(0.99, p * (1 + efeito));
  const d = p2 - p;
  if (p <= 0 || d <= 0) return 0;
  return Math.ceil((7.85 * (p * (1 - p) + p2 * (1 - p2))) / (d * d));
}

export interface GrupoAB { base: string; a: PaginaMelhorias; variacoes: PaginaMelhorias[] }

/** junta as páginas com código da casa por base (ak1 + ak1-b + ak1-c); só grupos com A e pelo menos uma variação */
export function gruposAB(paginas: PaginaMelhorias[]): GrupoAB[] {
  const porBase = new Map<string, { a?: PaginaMelhorias; v: PaginaMelhorias[] }>();
  for (const p of paginas) {
    const m = p.codigo ? CODIGO.exec(p.codigo) : null;
    if (!m) continue;
    const g = porBase.get(m[1]) ?? { v: [] };
    if (m[2]) g.v.push(p); else g.a = p;
    porBase.set(m[1], g);
  }
  return [...porBase.entries()]
    .filter(([, g]) => g.a && g.v.length)
    .map(([base, g]) => ({ base, a: g.a!, variacoes: g.v.sort((x, y) => (x.codigo ?? '').localeCompare(y.codigo ?? '')) }))
    .sort((x, y) => x.base.localeCompare(y.base));
}

export type Veredito = 'aguardando' | 'b_vence' | 'a_vence' | 'sem_diferenca';
export const ROTULO_VEREDITO: Record<Veredito, string> = {
  aguardando: 'Aguardando amostra', b_vence: 'A variação vence', a_vence: 'A original vence', sem_diferenca: 'Sem diferença',
};

export interface LeituraAB {
  comparacao: Comparacao; amostra: number; menor: number; falta: number; ritmo: number; diasFaltam: number | null;
  dias: number; divisao: { parteA: number; desigual: boolean }; veredito: Veredito;
}

/** lerTeste do testes.ts, sem o estado agendado/encerrado (o teste não é cadastrado) */
export function lerAB(a: PaginaMelhorias, b: PaginaMelhorias, metrica: 'lead' | 'mql' = 'lead', efeito = EFEITO_PADRAO, hoje?: string): LeituraAB {
  const eA = a.entradas, eB = b.entradas;
  const conv = (p: PaginaMelhorias) => (metrica === 'mql' ? p.mql_entrada : p.leads_entrada);
  const comparacao = compararTaxas(conv(a), eA, conv(b), eB);
  const amostra = eA >= 50 ? amostraNecessaria(comparacao.a, efeito) : 0;
  const menor = Math.min(eA, eB);
  const falta = amostra ? Math.max(0, amostra - menor) : 0;
  // ritmo: média dos últimos 7 dias fechados (antes de hoje) da versão mais lenta
  const dias = new Set([...(a.por_dia ?? []), ...(b.por_dia ?? [])].map((d) => d.dia));
  const ultimos = [...dias].filter((d) => !hoje || d < hoje).sort().slice(-7);
  const soma = (p: PaginaMelhorias) => ultimos.reduce((s, d) => s + (p.por_dia?.find((x) => x.dia === d)?.entradas ?? 0), 0);
  const ritmo = ultimos.length ? Math.min(soma(a), soma(b)) / ultimos.length : 0;
  const diasFaltam = !amostra ? null : falta === 0 ? 0 : ritmo > 0 ? Math.ceil(falta / ritmo) : null;
  const total = eA + eB;
  const parteA = total ? eA / total : 0;
  const qui = total ? ((eA - eB) * (eA - eB)) / total : 0;
  const temAmostra = amostra > 0 && menor >= amostra && dias.size >= 7;
  const veredito: Veredito = !temAmostra ? 'aguardando' : !comparacao.confiavel ? 'sem_diferenca' : comparacao.b > comparacao.a ? 'b_vence' : 'a_vence';
  return {
    comparacao, amostra, menor, falta, ritmo, diasFaltam, dias: dias.size,
    divisao: { parteA, desigual: qui > 3.84 && Math.abs(parteA - 0.5) >= 0.03 },
    veredito,
  };
}
