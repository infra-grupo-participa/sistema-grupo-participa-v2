// Histórico dia a dia (molde da aba Histórico do ATM): gasto, funil e leads acumulados contra a meta acumulada.
// Meta acumulada = 650 × dias desde o início da captação (CONCEPCAO: "cerca de 650 leads por dia", desde 12/10).
// Leads da meta = pessoas únicas na lista (a meta é "15.000 leads na lista do Método Perfeito").
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { diaDe } from './recorte';
import type { ConfigBlack, DesempenhoDia, LinhaPerfil, Valor } from './tipos';

export interface DiaHistorico {
  dia: string;
  gasto: number; impressoes: number; cliques: Valor; lpv: Valor;
  cadastros: number; leadsPagos: number; pessoasNovas: number;
  pessoasAcumuladas: number; metaAcumulada: Valor;
}

/** Quantos dias de captação já contam até `dia` inclusive (0 antes do início). */
export function diasDeCaptacao(dia: string, inicioCaptacao: string): number {
  if (dia < inicioCaptacao) return 0;
  let n = 0;
  for (let d = inicioCaptacao; d <= dia; d = deslocarDia(d, 1)) n += 1;
  return n;
}

export const metaAcumuladaAte = (dia: string, cfg: Pick<ConfigBlack, 'inicioCaptacao' | 'metaLeadsDia'>): Valor => {
  const n = diasDeCaptacao(dia, cfg.inicioCaptacao);
  return n === 0 ? null : n * cfg.metaLeadsDia;
};

/**
 * Uma linha por dia do período. `pessoasAcumuladas` conta desde o início do projeto (não do período), para a
 * curva bater com o placar; por isso recebe TODAS as linhas até o fim do período.
 */
export function serieHistorico(
  dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], periodo: readonly string[],
  cfg: Pick<ConfigBlack, 'inicioCaptacao' | 'metaLeadsDia'>,
): DiaHistorico[] {
  const porDia = new Map<string, { g: number; i: number; c: number | null; l: number | null }>();
  for (const d of dias) {
    const x = porDia.get(d.dia) ?? { g: 0, i: 0, c: null, l: null };
    x.g += d.gasto; x.i += d.impressoes;
    if (d.cliquesLink !== null) x.c = (x.c ?? 0) + d.cliquesLink;
    if (d.landingPageViews !== null) x.l = (x.l ?? 0) + d.landingPageViews;
    porDia.set(d.dia, x);
  }
  const primeiro = new Map<string, string>();
  const cad = new Map<string, { n: number; p: number }>();
  for (const l of linhas) {
    const dia = diaDe(l.criadoEm);
    const c = cad.get(dia) ?? { n: 0, p: 0 };
    c.n += 1; if (l.origem === 'pago') c.p += 1; cad.set(dia, c);
    const atual = primeiro.get(l.pessoaId);
    if (atual === undefined || dia < atual) primeiro.set(l.pessoaId, dia);
  }
  const novas = new Map<string, number>();
  for (const dia of primeiro.values()) novas.set(dia, (novas.get(dia) ?? 0) + 1);
  const ini = periodo[0] ?? '';
  let acumulado = 0;
  for (const [dia, n] of novas) if (dia < ini) acumulado += n;
  return periodo.map((dia) => {
    const t = porDia.get(dia);
    const c = cad.get(dia);
    const pn = novas.get(dia) ?? 0;
    acumulado += pn;
    return {
      dia, gasto: t?.g ?? 0, impressoes: t?.i ?? 0, cliques: t?.c ?? null, lpv: t?.l ?? null,
      cadastros: c?.n ?? 0, leadsPagos: c?.p ?? 0, pessoasNovas: pn, pessoasAcumuladas: acumulado,
      metaAcumulada: metaAcumuladaAte(dia, cfg),
    };
  });
}
