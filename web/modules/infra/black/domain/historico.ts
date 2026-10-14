// Histórico dia a dia (molde da aba Histórico do ATM): gasto, funil e leads acumulados.
// Meta acumulada = 650 × dias desde o início da captação (CONCEPCAO: "cerca de 650 leads por dia", desde 12/10).
// Leads da meta = pessoas únicas na lista (a meta é "15.000 leads na lista do Método Perfeito").
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { diaDe } from './recorte';
import { ehMqlPorProfissao, ehPago } from './metricas';
import type { ConfigBlack, DesempenhoDia, LinhaPerfil, Valor } from './tipos';

export interface DiaHistorico {
  dia: string;
  gasto: number; impressoes: number; cliques: Valor; lpv: Valor;
  cadastros: number; leadsPagos: number; pessoasNovas: number;
  mql: Valor; mqlBase: Valor; mqlPagos: Valor; mqlPagosBase: Valor; ingressoGrupoPagosMql: Valor; ingressoGrupo: Valor;
  pessoasAcumuladas: number; metaAcumulada: Valor;
}

/** Quantos dias de captação já contam até `dia` inclusive (0 antes do início). */
export function diasDeCaptacao(dia: string, inicioCaptacao: string): number {
  if (dia < inicioCaptacao) return 0;
  let n = 0;
  for (let d = inicioCaptacao; d <= dia; d = deslocarDia(d, 1)) n += 1;
  return n;
}

/** Sem início de captação ou sem meta diária cadastrados (fonte real hoje), não há meta acumulada: null. */
export const metaAcumuladaAte = (dia: string, cfg: Pick<ConfigBlack, 'inicioCaptacao' | 'metaLeadsDia'>): Valor => {
  if (cfg.inicioCaptacao === null || cfg.metaLeadsDia === null) return null;
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
  const pessoas = new Map<string, { dia: string; envioMaisRecente: LinhaPerfil; grupo: boolean; primeiroPagoDia: string | null }>();
  const cad = new Map<string, { n: number; p: number }>();
  for (const l of linhas) {
    const dia = diaDe(l.criadoEm);
    const c = cad.get(dia) ?? { n: 0, p: 0 };
    c.n += 1; if (l.origem === 'pago') c.p += 1; cad.set(dia, c);
    const atual = pessoas.get(l.pessoaId);
    if (!atual) pessoas.set(l.pessoaId, { dia, envioMaisRecente: l, grupo: l.entrouGrupoEm !== null, primeiroPagoDia: ehPago(l) ? dia : null });
    else {
      if (dia < atual.dia) atual.dia = dia;
      if (Date.parse(l.criadoEm) > Date.parse(atual.envioMaisRecente.criadoEm)) atual.envioMaisRecente = l;
      atual.grupo ||= l.entrouGrupoEm !== null;
      if (ehPago(l) && (atual.primeiroPagoDia === null || dia < atual.primeiroPagoDia)) atual.primeiroPagoDia = dia;
    }
  }
  const novas = new Map<string, { pessoas: number; mql: number; mqlConhecidos: number; grupo: number }>();
  const pagos = new Map<string, { mql: number; grupoMql: number }>();
  for (const pessoa of pessoas.values()) {
    const item = novas.get(pessoa.dia) ?? { pessoas: 0, mql: 0, mqlConhecidos: 0, grupo: 0 };
    item.pessoas += 1;
    item.mqlConhecidos += 1;
    if (ehMqlPorProfissao(pessoa.envioMaisRecente)) item.mql += 1;
    if (pessoa.grupo) item.grupo += 1;
    novas.set(pessoa.dia, item);
    if (pessoa.primeiroPagoDia !== null) {
      const pagosDoDia = pagos.get(pessoa.primeiroPagoDia) ?? { mql: 0, grupoMql: 0 };
      if (ehMqlPorProfissao(pessoa.envioMaisRecente)) {
        pagosDoDia.mql += 1;
        if (pessoa.grupo) pagosDoDia.grupoMql += 1;
      }
      pagos.set(pessoa.primeiroPagoDia, pagosDoDia);
    }
  }
  const ini = periodo[0] ?? '';
  let acumulado = 0;
  for (const [dia, n] of novas) if (dia < ini) acumulado += n.pessoas;
  return periodo.map((dia) => {
    const t = porDia.get(dia);
    const c = cad.get(dia);
    const cohort = novas.get(dia);
    const pn = cohort?.pessoas ?? 0;
    acumulado += pn;
    return {
      dia, gasto: t?.g ?? 0, impressoes: t?.i ?? 0, cliques: t?.c ?? null, lpv: t?.l ?? null,
      cadastros: c?.n ?? 0, leadsPagos: c?.p ?? 0, pessoasNovas: pn, pessoasAcumuladas: acumulado,
      mql: cohort?.mqlConhecidos ? cohort.mql : null, mqlBase: cohort?.mqlConhecidos ?? null,
      mqlPagos: c ? (pagos.get(dia)?.mql ?? 0) : null, mqlPagosBase: c?.p ?? null,
      ingressoGrupoPagosMql: c ? (pagos.get(dia)?.grupoMql ?? 0) : null,
      ingressoGrupo: cohort ? cohort.grupo : null,
      metaAcumulada: metaAcumuladaAte(dia, cfg),
    };
  });
}
