// Premissas do Contas a Receber (z66) e feriados bancários — funções PURAS, sem I/O.
// Fonte: fn_fin_premissas_receber_listar() (uma linha por vigência, catálogo repetido) e fn_fin_feriados_listar().
// A regra (faixa, inteiro, cenário, vigência) mora no banco; aqui só: tipar, agrupar para a tela, converter a
// unidade de exibição (percentual é FRAÇÃO no banco: 0,05 = 5%) e validar antes de enviar — a validação do cliente
// só poupa uma ida ao banco, a trava de verdade é a RPC.
import { CENARIOS_RECEBER, type CenarioReceber } from './contas-receber';

/** 'reais' (z67): R$ por semana da venda nova, guardado em reais. */
export type UnidadePremissa = 'dias' | 'percentual' | 'liga_desliga' | 'reais';
export type SituacaoVigencia = 'vigente' | 'futura' | 'anterior';

export interface VigenciaPremissa {
  chave: string;
  chave_base: string;
  cenario: CenarioReceber;
  rotulo: string;
  unidade: UnidadePremissa;
  minimo: number;
  maximo: number;
  grupo_tela: string;
  ajuda: string;
  aceita_cenario: boolean;
  vigente_de: string;
  valor: number;
  fonte: string | null;
  criado_em: string | null;
  criado_por_nome: string | null;
  situacao: SituacaoVigencia;
}

const num = (v: unknown): number => Number(v ?? 0) || 0;
const texto = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const dia = (v: unknown): string => String(v ?? '').slice(0, 10);

export function normalizarVigencia(r: Record<string, unknown>): VigenciaPremissa {
  const cen = String(r.cenario ?? 'base');
  return {
    chave: String(r.chave ?? ''),
    chave_base: String(r.chave_base ?? r.chave ?? ''),
    // Cenário fora do contrato: mantido cru (não vira base em silêncio); a tela só agrupa os 3 conhecidos.
    cenario: cen as CenarioReceber,
    rotulo: String(r.rotulo ?? r.chave ?? ''),
    unidade: String(r.unidade ?? '') as UnidadePremissa,
    minimo: num(r.minimo),
    maximo: num(r.maximo),
    grupo_tela: String(r.grupo_tela ?? ''),
    ajuda: String(r.ajuda ?? ''),
    aceita_cenario: r.aceita_cenario === true || r.aceita_cenario === 'true',
    vigente_de: dia(r.vigente_de),
    valor: num(r.valor),
    fonte: texto(r.fonte),
    criado_em: texto(r.criado_em),
    criado_por_nome: texto(r.criado_por_nome),
    situacao: String(r.situacao ?? 'anterior') as SituacaoVigencia,
  };
}

/** Um cenário de uma premissa: o que vale hoje e o histórico. */
export interface CenarioPremissa {
  cenario: CenarioReceber;
  /** Vigência que vale hoje NESTE cenário. NULL = sem linha própria vigente: vale a base (`usaBase`). */
  vigente: VigenciaPremissa | null;
  /** Sem vigência própria hoje: o banco usa a da base (fin.premissa). Só em cenário ≠ base. */
  usaBase: boolean;
  /** Futuras (mais próxima primeiro) e anteriores (mais recente primeiro). */
  futuras: VigenciaPremissa[];
  anteriores: VigenciaPremissa[];
}

export interface PremissaTela {
  chave_base: string;
  rotulo: string;
  unidade: UnidadePremissa;
  minimo: number;
  maximo: number;
  ajuda: string;
  aceita_cenario: boolean;
  /** base sempre; conservador e otimista só quando aceita_cenario. */
  cenarios: CenarioPremissa[];
}

export interface GrupoPremissas {
  grupo: string;
  premissas: PremissaTela[];
}

/** Agrupa por grupo_tela (ordem em que o banco devolve) → premissa → cenário. */
export function agruparPremissas(vs: VigenciaPremissa[]): GrupoPremissas[] {
  const grupos = new Map<string, Map<string, { cat: VigenciaPremissa; linhas: VigenciaPremissa[] }>>();
  for (const v of vs) {
    let g = grupos.get(v.grupo_tela);
    if (!g) { g = new Map(); grupos.set(v.grupo_tela, g); }
    let p = g.get(v.chave_base);
    if (!p) { p = { cat: v, linhas: [] }; g.set(v.chave_base, p); }
    p.linhas.push(v);
  }
  return [...grupos.entries()].map(([grupo, ps]) => ({
    grupo,
    premissas: [...ps.values()].map(({ cat, linhas }) => {
      const cens = cat.aceita_cenario ? CENARIOS_RECEBER : (['base'] as CenarioReceber[]);
      return {
        chave_base: cat.chave_base, rotulo: cat.rotulo, unidade: cat.unidade, minimo: cat.minimo, maximo: cat.maximo,
        ajuda: cat.ajuda, aceita_cenario: cat.aceita_cenario,
        cenarios: cens.map((cenario) => {
          const doCen = linhas.filter((l) => l.cenario === cenario);
          const vigente = doCen.find((l) => l.situacao === 'vigente') ?? null;
          return {
            cenario,
            vigente,
            usaBase: cenario !== 'base' && vigente == null,
            futuras: doCen.filter((l) => l.situacao === 'futura').sort((a, b) => a.vigente_de.localeCompare(b.vigente_de)),
            anteriores: doCen.filter((l) => l.situacao === 'anterior').sort((a, b) => b.vigente_de.localeCompare(a.vigente_de)),
          };
        }),
      };
    }),
  }));
}

// ─── Unidade de exibição ────────────────────────────────────────────────────
/** Banco → tela. Percentual: fração × 100 (0,05 → 5). Dias e liga/desliga: iguais. */
export const paraExibicao = (valor: number, unidade: UnidadePremissa): number =>
  unidade === 'percentual' ? Math.round(valor * 100 * 1e6) / 1e6 : valor;

/** Tela → banco. Percentual: ÷ 100 (5 → 0,05), sem resíduo de ponto flutuante. */
export const paraBanco = (exibido: number, unidade: UnidadePremissa): number =>
  unidade === 'percentual' ? Math.round((exibido / 100) * 1e8) / 1e8 : exibido;

const fmtNum = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 4 });
const fmtReais = (n: number) => n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** Valor como a tela mostra: "5%", "30 dias", "Ligado"/"Desligado", "R$ 30.000,00". */
export function formatarPremissa(valor: number, unidade: UnidadePremissa): string {
  if (unidade === 'percentual') return `${fmtNum(paraExibicao(valor, unidade))}%`;
  if (unidade === 'reais') return fmtReais(valor);
  if (unidade === 'dias') return `${fmtNum(valor)} ${valor === 1 ? 'dia' : 'dias'}`;
  if (unidade === 'liga_desliga') return valor > 0 ? 'Ligado' : 'Desligado';
  return fmtNum(valor);
}

/** Faixa aceita, na unidade de exibição: "0% a 50%", "0 a 30 dias". */
export function formatarFaixa(p: Pick<PremissaTela, 'minimo' | 'maximo' | 'unidade'>): string {
  if (p.unidade === 'percentual') return `${fmtNum(paraExibicao(p.minimo, 'percentual'))}% a ${fmtNum(paraExibicao(p.maximo, 'percentual'))}%`;
  if (p.unidade === 'dias') return `${fmtNum(p.minimo)} a ${fmtNum(p.maximo)} dias`;
  if (p.unidade === 'reais') return `${fmtReais(p.minimo)} a ${fmtReais(p.maximo)}`;
  return `${fmtNum(p.minimo)} a ${fmtNum(p.maximo)}`;
}

/**
 * Número digitado em pt-BR ("5,5", "1.000,5") ou com ponto ("5.5"). NULL = não é número.
 * `milharComPonto` (reais): "30.000" é trinta mil, não 30 — sem vírgula, ponto seguido de grupos de 3 dígitos é milhar.
 */
export function lerNumeroDigitado(t: string, milharComPonto = false): number | null {
  const s = t.trim().replace(/\s|%|R\$/g, '');
  if (!s) return null;
  const normal = s.includes(',') ? s.replace(/\./g, '').replace(',', '.')
    : milharComPonto && /^-?\d{1,3}(\.\d{3})+$/.test(s) ? s.replace(/\./g, '') : s;
  if (!/^-?\d+(\.\d+)?$/.test(normal)) return null;
  const n = Number(normal);
  return Number.isFinite(n) ? n : null;
}

/** Hoje + n dias (YYYY-MM-DD, calendário puro). */
export function somarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** Mesmo teto da RPC: vigência de hoje até hoje + 366. */
export const VIGENCIA_MAX_DIAS = 366;

export type ValidacaoPremissa = { ok: true; valor: number } | { ok: false; erros: string[] };

/**
 * Valida o que foi digitado ANTES de ir ao banco, com as mesmas regras da RPC: número, faixa do catálogo, inteiro em
 * dias e liga/desliga, vigência de hoje a hoje+366. Devolve o valor NA UNIDADE DO BANCO (fração no percentual).
 */
export function validarPremissa(
  p: Pick<PremissaTela, 'minimo' | 'maximo' | 'unidade' | 'rotulo'>, digitado: string, vigenteDe: string, hojeISO: string,
): ValidacaoPremissa {
  const erros: string[] = [];
  const exibido = lerNumeroDigitado(digitado, p.unidade === 'reais');
  let valor = 0;
  if (exibido == null) erros.push('Informe um número.');
  else {
    valor = paraBanco(exibido, p.unidade);
    if (valor < p.minimo || valor > p.maximo) erros.push(`Fora da faixa: ${formatarFaixa(p)}.`);
    else if ((p.unidade === 'dias' || p.unidade === 'liga_desliga') && !Number.isInteger(valor)) erros.push('Só número inteiro.');
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(vigenteDe)) erros.push('Informe a data de início da vigência.');
  else if (vigenteDe < hojeISO || vigenteDe > somarDias(hojeISO, VIGENCIA_MAX_DIAS)) {
    erros.push('Vigência entre hoje e um ano à frente (a previsão já vista não muda).');
  }
  return erros.length ? { ok: false, erros } : { ok: true, valor };
}

// ─── Feriados bancários ─────────────────────────────────────────────────────
export interface FeriadoBancario {
  dia: string;
  nome: string;
  ativo: boolean;
  fonte: string | null;
  criado_em: string | null;
  atualizado_em: string | null;
  atualizado_por_nome: string | null;
}

export function normalizarFeriado(r: Record<string, unknown>): FeriadoBancario {
  return {
    dia: dia(r.dia),
    nome: String(r.nome ?? ''),
    ativo: r.ativo === true || r.ativo === 'true',
    fonte: texto(r.fonte),
    criado_em: texto(r.criado_em),
    atualizado_em: texto(r.atualizado_em),
    atualizado_por_nome: texto(r.atualizado_por_nome),
  };
}

/** Anos presentes na lista, crescente. */
export const anosDosFeriados = (fs: FeriadoBancario[]): number[] =>
  [...new Set(fs.map((f) => Number(f.dia.slice(0, 4))).filter((n) => Number.isFinite(n) && n > 0))].sort((a, b) => a - b);

/** Mesma faixa da fn_fin_feriado_salvar (z64). */
export const FERIADO_DIA_MIN = '2015-01-01';
export const FERIADO_DIA_MAX = '2036-12-31';

export function validarFeriado(diaISO: string, nome: string): string[] {
  const erros: string[] = [];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(diaISO) || diaISO < FERIADO_DIA_MIN || diaISO > FERIADO_DIA_MAX) {
    erros.push('Data entre 2015 e 2036.');
  }
  const n = nome.trim();
  if (!n || n.length > 120) erros.push('Nome do feriado obrigatório (até 120 caracteres).');
  return erros;
}

// ─── Sugestão medida (z67: fn_fin_receber_sugestoes) ────────────────────────
/** Uma premissa com sugestão calculada do histórico: venda nova semanal por grupo e reserva de reembolso. */
export interface SugestaoPremissa {
  chave: string;
  rotulo: string;
  unidade: UnidadePremissa;
  /** Na unidade do banco (fração no percentual). NULL = sem base medida. */
  sugestao: number | null;
  /** Texto do banco: de onde a sugestão veio (janela, regra). */
  base_medida: string | null;
  /** Venda semanal: as semanas medidas. Reserva: vendido e estornado na janela. */
  semanas: { semana: string; valor: number }[];
  reserva: { vendido: number; estornado: number; de: string | null; ate: string | null } | null;
  /** O que vale hoje no cenário pedido: premissa gravada, senão a sugestão. NULL = sem base. */
  valor_efetivo: number | null;
  /** 'sugestão medida' | 'definido por <nome> em dd/mm/aaaa' | 'sem base medida'. */
  origem: string;
  vigente_de: string | null;
  cenario: string;
}

const numOuNull = (v: unknown): number | null => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));

export function normalizarSugestao(r: Record<string, unknown>): SugestaoPremissa {
  let medida: unknown = r.medida;
  if (typeof medida === 'string') { try { medida = JSON.parse(medida); } catch { medida = null; } }
  const semanas = Array.isArray(medida)
    ? medida.map((x) => { const o = (x ?? {}) as Record<string, unknown>; return { semana: dia(o.semana), valor: num(o.valor) }; })
    : [];
  const m = medida && typeof medida === 'object' && !Array.isArray(medida) ? (medida as Record<string, unknown>) : null;
  return {
    chave: String(r.chave ?? ''),
    rotulo: String(r.rotulo ?? r.chave ?? ''),
    unidade: String(r.unidade ?? '') as UnidadePremissa,
    sugestao: numOuNull(r.sugestao),
    base_medida: texto(r.base_medida),
    semanas,
    reserva: m ? { vendido: num(m.vendido), estornado: num(m.estornado), de: texto(m.de) && dia(m.de), ate: texto(m.ate) && dia(m.ate) } : null,
    valor_efetivo: numOuNull(r.valor_efetivo),
    origem: String(r.origem ?? ''),
    vigente_de: texto(r.vigente_de) && dia(r.vigente_de),
    cenario: String(r.cenario ?? 'base'),
  };
}

/**
 * Valor que o botão "Usar sugestão" grava (unidade do banco), arredondado como a tela mostra: reais em centavos,
 * percentual em centésimo de ponto (fração com 4 casas). O que se vê é o que se grava.
 */
export function valorDaSugestao(sugestao: number, unidade: UnidadePremissa): number {
  if (unidade === 'reais') return Math.round(sugestao * 100) / 100;
  if (unidade === 'percentual') return Math.round(sugestao * 1e4) / 1e4;
  return sugestao;
}

/**
 * Diferença "em uso − sugestão", na unidade de exibição, como texto: "R$ 1.500,00 acima da sugestão",
 * "0,5 p.p. abaixo da sugestão", "igual à sugestão". NULL quando falta um dos dois.
 */
export function diferencaDaSugestao(emUso: number | null, sugestao: number | null, unidade: UnidadePremissa): string | null {
  if (emUso == null || sugestao == null) return null;
  const d = unidade === 'reais' ? Math.round((emUso - sugestao) * 100) / 100
    : unidade === 'percentual' ? Math.round((emUso - sugestao) * 1e6) / 1e4 : emUso - sugestao;
  if (d === 0) return 'igual à sugestão';
  const abs = Math.abs(d);
  const txt = unidade === 'reais' ? fmtReais(abs) : unidade === 'percentual' ? `${fmtNum(abs)} p.p.` : fmtNum(abs);
  return `${txt} ${d > 0 ? 'acima' : 'abaixo'} da sugestão`;
}
