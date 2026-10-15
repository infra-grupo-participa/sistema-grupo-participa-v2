import type { Valor } from './tipos';

export const INICIO_CAPTACAO = '2026-10-12';
export const FIM_CAPTACAO = '2026-11-03';
export const SEMENTE_LEADS = 154;

export interface PontoRitmo {
  dia: string;
  realizado: Valor;
  metaDia: Valor;
  acumulado: Valor;
  metaAcumulada: Valor;
}
export interface ProjecaoRitmo {
  pontos: PontoRitmo[];
  hoje: string;
  acumuladoHoje: Valor;
  realizadoHoje: Valor;
  necessarioPorDia: Valor;
  faltaHoje: Valor;
  media: Valor;
  mediaDias: string[];
  projecao: Valor;
  diasRestantes: number;
  percentualMeta: Valor;
}

/** Quantidades de pessoas são inteiras; metas diárias e faltas arredondam para cima para não subestimar. */
export function arredondarInteiroRitmo(valor: Valor, modo: 'normal' | 'cima' = 'normal'): Valor {
  if (valor === null) return null;
  return modo === 'cima' ? Math.ceil(valor) : Math.round(valor);
}

const deslocar = (dia: string, n: number) => {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
const diferencaDias = (de: string, ate: string) => Math.round((Date.parse(`${ate}T00:00:00Z`) - Date.parse(`${de}T00:00:00Z`)) / 86_400_000);

/** Projeção CNHF: ritmo por dia sobre o saldo de meta, média dos últimos dias fechados com valor > 0. */
export function projetarRitmo({
  inicio = INICIO_CAPTACAO, fim = FIM_CAPTACAO, hoje, meta, realizados, semente = 0, janelaMedia = 3,
}: {
  inicio?: string; fim?: string; hoje: string; meta: Valor; realizados: ReadonlyMap<string, Valor>; semente?: number; janelaMedia?: number;
}): ProjecaoRitmo {
  const diasTotais = Math.max(1, diferencaDias(inicio, fim) + 1);
  const ultimoDia = hoje < inicio ? inicio : hoje > fim ? fim : hoje;
  const diasPassados = Math.max(0, diferencaDias(inicio, ultimoDia));
  const diasRestantes = Math.max(1, diasTotais - diasPassados - 1);
  const datas = Array.from({ length: diasTotais }, (_, i) => deslocar(inicio, i));
  let acumuladoReal: Valor = semente;
  let acumuladoReferencia: Valor = semente;
  const pontos: PontoRitmo[] = [];
  for (let i = 0; i < datas.length; i += 1) {
    const dia = datas[i];
    const restante = Math.max(1, diasTotais - i);
    const metaDia = meta === null || acumuladoReferencia === null ? null : Math.max(0, (meta - acumuladoReferencia) / restante);
    const realizado = dia > ultimoDia ? null : realizados.has(dia) ? realizados.get(dia) ?? null : 0;
    acumuladoReal = realizado === null || acumuladoReal === null ? null : acumuladoReal + realizado;
    if (realizado !== null && acumuladoReferencia !== null) acumuladoReferencia += realizado;
    // O ritmo diário é recalculado sobre o saldo real. Não some esses alvos
    // diários: isso faz a meta acumulada ultrapassar a meta final. Converta o
    // alvo diário em acumulado pela distância que falta até o fim.
    const acumuladoMeta = meta === null || metaDia === null
      ? null
      : Math.min(meta, Math.max(semente, meta - metaDia * (diasTotais - i - 1)));
    pontos.push({ dia, realizado, metaDia, acumulado: acumuladoReal, metaAcumulada: acumuladoMeta });
  }
  const doDia = (dia: string): Valor => realizados.has(dia) ? realizados.get(dia) ?? null : 0;
  const realizadoHoje = hoje >= inicio && hoje <= fim ? doDia(hoje) : 0;
  const acumuladoHoje = pontos.find((p) => p.dia === ultimoDia)?.acumulado ?? (hoje < inicio ? semente : null);
  const necessarioPorDia = meta === null || acumuladoHoje === null ? null : Math.max(0, (meta - acumuladoHoje) / diasRestantes);
  const faltaHoje = necessarioPorDia === null || realizadoHoje === null ? null : Math.max(0, necessarioPorDia - realizadoHoje);
  const mediaDias = datas.filter((dia) => dia < hoje && dia >= deslocar(hoje, -janelaMedia) && (realizados.get(dia) ?? 0) > 0);
  const media = mediaDias.length ? mediaDias.reduce((s, dia) => s + (realizados.get(dia) as number), 0) / mediaDias.length : null;
  const projecao = acumuladoHoje === null || media === null ? null : acumuladoHoje + media * diasRestantes;
  const percentualMeta = meta === null || projecao === null || meta === 0 ? null : projecao / meta;
  return { pontos, hoje, acumuladoHoje, realizadoHoje, necessarioPorDia, faltaHoje, media, mediaDias, projecao, diasRestantes, percentualMeta };
}

export type TipoConteudoC1 = 'Teaser' | 'Manifesto' | 'Reels' | 'Sem tipo no nome';
export function tipoConteudoC1(nome: string): TipoConteudoC1 {
  const s = nome.toLocaleUpperCase('pt-BR');
  if (s.includes('TEASER')) return 'Teaser';
  if (s.includes('MANIFESTO')) return 'Manifesto';
  if (s.includes('REELS') || s.includes('REEL')) return 'Reels';
  return 'Sem tipo no nome';
}

/** Isca do conjunto C2: o último bloco não vazio depois do separador, sem supor CONSULTORIA como isca. */
export function iscaDoNomeConjunto(nome: string): string | null {
  const parte = nome.split('|').map((x) => x.trim()).filter(Boolean).at(-1);
  if (!parte || /^CONSULTORIA$/i.test(parte)) return null;
  if (/^CHECKUP$/i.test(parte)) return 'Checkup';
  if (/^FLUXOGRAMA$/i.test(parte)) return 'Fluxograma';
  if (/^FUTUROMETRO$/i.test(parte)) return 'Futurômetro';
  return null;
}
