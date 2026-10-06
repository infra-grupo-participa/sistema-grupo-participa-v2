// Jornada da pessoa com a empresa: pontos (inscrição, lista, pesquisa, compra, reembolso, negócio, conversa…)
// agrupados por lançamento, do mais recente para o mais antigo. Uma pessoa entra por campanhas diferentes em
// lançamentos diferentes, e cada entrada guarda a própria UTM.
import type { FonteJornada, PontoJornada, TipoPontoJornada } from './types';

export const ROTULO_TIPO_JORNADA: Record<TipoPontoJornada, string> = {
  inscricao: 'Inscrição', lista: 'Lista', pesquisa: 'Pesquisa', grupo: 'Grupo', presenca: 'Presença', checkout: 'Checkout',
  compra: 'Compra', reembolso: 'Reembolso', negocio: 'Negócio', conversa: 'Conversa', disparo: 'Disparo', nota: 'Nota',
};

export const ICONE_TIPO_JORNADA: Record<TipoPontoJornada, string> = {
  inscricao: 'arrow-up-right', lista: 'mail', pesquisa: 'clipboard', grupo: 'users', presenca: 'video', checkout: 'wallet',
  compra: 'check-circle', reembolso: 'rotate', negocio: 'kanban', conversa: 'message', disparo: 'send', nota: 'pen',
};

export const ROTULO_FONTE: Record<FonteJornada, string> = {
  activecampaign: 'ActiveCampaign', hotmart: 'Hotmart', respondi: 'Respondi', sendflow: 'SendFlow', crm: 'CRM', infobip: 'Infobip',
  unnichat: 'Unnichat', manychat: 'Manychat', formulario: 'Formulário', youtube: 'YouTube', instagram: 'Instagram',
};

export interface BlocoLancamento {
  /** Chave do lançamento; null = pontos sem lançamento (conversa avulsa, nota). */
  lancamento: string | null;
  inicio: string;
  fim: string;
  pontos: PontoJornada[];
  /** UTM da primeira entrada no lançamento (como a pessoa chegou desta vez). */
  entrada: PontoJornada | null;
  comprou: boolean;
  reembolsou: boolean;
  valorPago: number;
}

/** Agrupa por lançamento; blocos e pontos do mais recente para o mais antigo. */
export function agruparPorLancamento(pontos: PontoJornada[]): BlocoLancamento[] {
  const mapa = new Map<string, PontoJornada[]>();
  for (const p of pontos) {
    const k = p.lancamento ?? '';
    mapa.set(k, [...(mapa.get(k) ?? []), p]);
  }
  const blocos: BlocoLancamento[] = [...mapa].map(([k, ps]) => {
    const asc = [...ps].sort((a, b) => a.em.localeCompare(b.em));
    const compras = asc.filter((p) => p.tipo === 'compra');
    const reembolsos = asc.filter((p) => p.tipo === 'reembolso');
    return {
      lancamento: k || null,
      inicio: asc[0].em,
      fim: asc[asc.length - 1].em,
      pontos: [...asc].reverse(),
      entrada: asc.find((p) => (p.tipo === 'inscricao' || p.tipo === 'lista') && p.utm) ?? null,
      comprou: compras.length > 0,
      reembolsou: reembolsos.length > 0,
      valorPago: compras.reduce((s, p) => s + (p.valor ?? 0), 0) - reembolsos.reduce((s, p) => s + (p.valor ?? 0), 0),
    };
  });
  return blocos.sort((a, b) => b.fim.localeCompare(a.fim));
}

/** Resumo da pessoa: quantos lançamentos, quanto já pagou, primeiro contato com a casa. */
export function resumoJornada(pontos: PontoJornada[]): { lancamentos: number; compras: number; valorPago: number; desde: string | null; reembolsos: number } {
  const blocos = agruparPorLancamento(pontos);
  return {
    lancamentos: blocos.filter((b) => b.lancamento).length,
    compras: pontos.filter((p) => p.tipo === 'compra').length,
    reembolsos: pontos.filter((p) => p.tipo === 'reembolso').length,
    valorPago: blocos.reduce((s, b) => s + b.valorPago, 0),
    desde: pontos.length ? [...pontos].sort((a, b) => a.em.localeCompare(b.em))[0].em : null,
  };
}
