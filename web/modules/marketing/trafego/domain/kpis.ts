// Marketing > Tráfego: os cálculos da Central do Tráfego. Domínio puro (sem Next, sem Supabase).
//
// As MESMAS fórmulas estão no banco (mkt_trafego.resumo, migration 20261005p). Mudou aqui, muda lá (e o contrário).
// Regra da casa: sem fonte ou sem base para a conta = null ("sem dado"), nunca zero inventado.
//   % da verba   = investido ÷ verba máxima × 100           (1 casa)
//   CPL          = investido ÷ leads da nossa base           (2 casas) (lead da base, decisão do Victor 05/10/2026)
//   CTR          = cliques ÷ impressões × 100                (2 casas)
//   CPM          = investido ÷ impressões × 1000             (2 casas)
//   % MQL        = MQL ÷ leads × 100                         (1 casa)
//   ritmo        = gasto do dia ÷ verba diária × 100         (1 casa)
//   esperado até = soma, por fase, da verba proporcional aos dias já passados da fase

import type { LinhaResumo, Subarea, Tipo } from './tipos';

const num = (v: number | null | undefined): v is number => typeof v === 'number' && Number.isFinite(v);

/** Arredonda como o round() do Postgres em numeric (meio para longe do zero). */
export function arredondar(v: number, casas: number): number {
  const f = 10 ** casas;
  // toPrecision(15) tira o resto do ponto flutuante (1.005 × 100 = 100.49999…) antes de arredondar.
  return (Math.sign(v) * Math.round(Number((Math.abs(v) * f).toPrecision(15)))) / f;
}

function razao(a: number | null | undefined, b: number | null | undefined, vezes: number, casas: number): number | null {
  if (!num(a) || !num(b) || b <= 0) return null;
  return arredondar((a / b) * vezes, casas);
}

export const pctVerba = (investido: number | null, verbaMaxima: number | null) => razao(investido, verbaMaxima, 100, 1);
export const cpl = (investido: number | null, leads: number | null) => razao(investido, leads, 1, 2);
export const ctr = (cliques: number | null, impressoes: number | null) => razao(cliques, impressoes, 100, 2);
export const cpm = (investido: number | null, impressoes: number | null) => razao(investido, impressoes, 1000, 2);
export const pctMql = (mql: number | null, leads: number | null) => razao(mql, leads, 100, 1);
export const ritmo = (gastoDia: number | null, verbaDiaria: number | null) => razao(gastoDia, verbaDiaria, 100, 1);

export type SituacaoRitmo = 'acima' | 'dentro';
/** Acima = gastou mais que a verba diária ("o que está pegando fogo"). */
export function situacaoRitmo(pct: number | null): SituacaoRitmo | null {
  if (!num(pct)) return null;
  return pct > 100 ? 'acima' : 'dentro';
}

/** Interno ou externo sai da subárea (Interno = interno; Aurum e Diamantes = externo). */
export function tipoDaSubarea(s: Subarea | null): Tipo | null {
  if (!s) return null;
  return s === 'interno' ? 'interno' : 'externo';
}

const DIA_MS = 86400000;
const diaUTC = (ymd: string) => Date.UTC(Number(ymd.slice(0, 4)), Number(ymd.slice(5, 7)) - 1, Number(ymd.slice(8, 10)));

/**
 * Quanto deveria ter sido gasto até `ate` (inclusive), pelas fases: cada fase entrega a verba dela por igual em cada
 * dia do período. Fase sem verba não conta; fase com verba mas sem início ou fim entra em `semPeriodo` e fica fora.
 * Sem nenhuma fase com verba e período: valor null.
 */
export function esperadoAte(
  fases: { verba: number | null; inicio: string | null; fim: string | null }[],
  ate: string,
): { valor: number | null; semPeriodo: number } {
  let total = 0;
  let contou = 0;
  let semPeriodo = 0;
  const hoje = diaUTC(ate);
  for (const f of fases) {
    if (!num(f.verba)) continue;
    if (!f.inicio || !f.fim) { semPeriodo++; continue; }
    const ini = diaUTC(f.inicio);
    const fim = diaUTC(f.fim);
    const dias = Math.round((fim - ini) / DIA_MS) + 1;
    const passados = Math.min(dias, Math.max(0, Math.round((hoje - ini) / DIA_MS) + 1));
    total += (f.verba * passados) / dias;
    contou++;
  }
  return { valor: contou === 0 ? null : arredondar(total, 2), semPeriodo };
}

/** Recalcula os KPIs de uma linha a partir dos totais (o modo de demonstração usa isto; o banco faz o mesmo). */
export function comKpis<T extends Pick<LinhaResumo, 'investido' | 'verba_maxima' | 'impressoes' | 'cliques' | 'leads' | 'mql' | 'gasto_ontem' | 'verba_diaria'>>(l: T):
  T & Pick<LinhaResumo, 'pct_verba' | 'cpl' | 'ctr' | 'cpm' | 'pct_mql' | 'ritmo_ontem'> {
  return {
    ...l,
    pct_verba: pctVerba(l.investido, l.verba_maxima),
    cpl: cpl(l.investido, l.leads),
    ctr: ctr(l.cliques, l.impressoes),
    cpm: cpm(l.investido, l.impressoes),
    pct_mql: pctMql(l.mql, l.leads),
    ritmo_ontem: l.investido == null ? null : ritmo(l.gasto_ontem, l.verba_diaria),
  };
}

export interface FiltrosCentral {
  tipo: '' | Tipo;
  subarea: '' | Subarea;
  /** Sigla do gestor (CF, RS, EF): casa com o gestor do planejamento OU com o de alguma campanha do projeto. */
  gestor: string;
  /** Código do status; 'sem' = sem status marcado. */
  status: string;
  /** Mostrar projetos desativados em mkt.projetos. */
  inativos: boolean;
}

export const FILTROS_INICIAIS: FiltrosCentral = { tipo: '', subarea: '', gestor: '', status: '', inativos: false };

export function filtrar(linhas: LinhaResumo[], f: FiltrosCentral): LinhaResumo[] {
  return linhas.filter((l) => {
    if (!f.inativos && !l.projeto_ativo) return false;
    if (f.tipo && l.tipo !== f.tipo) return false;
    if (f.subarea && l.subarea !== f.subarea) return false;
    if (f.gestor && l.gestor !== f.gestor && !l.gestores_campanhas.includes(f.gestor)) return false;
    if (f.status === 'sem' ? l.status !== null : f.status && l.status !== f.status) return false;
    return true;
  });
}

/** Totais da tela (só soma o que tem dado; null se nenhuma linha tem). */
export function totais(linhas: LinhaResumo[]): { investido: number | null; verba: number | null; foraPadrao: number; acimaRitmo: number } {
  const soma = (xs: (number | null)[]) => (xs.some(num) ? arredondar(xs.filter(num).reduce((a, b) => a + b, 0), 2) : null);
  return {
    investido: soma(linhas.map((l) => l.investido)),
    verba: soma(linhas.map((l) => l.verba_maxima)),
    foraPadrao: linhas.reduce((a, l) => a + l.campanhas_fora_padrao, 0),
    acimaRitmo: linhas.filter((l) => situacaoRitmo(l.ritmo_ontem) === 'acima').length,
  };
}
