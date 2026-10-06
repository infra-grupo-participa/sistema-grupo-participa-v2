// Busca de etiqueta do ClickUp no cadastro do projeto (revisão do Victor, 06/10/2026). Domínio puro.
//
// A MESMA regra de public.trafego_clickup_etiquetas_buscar (migration 20261006j): casa por "contém", sem acento e sem
// diferença de maiúscula; só etiquetas no formato da chave (minúsculas, números e hífen); ordem: igual ao digitado,
// depois as que começam com ele, depois alfabética. O banco junta as fontes (kpi.medicao_tarefa e o espelho do ClickUp
// do Tráfego); aqui a lista chega pronta. O modo de demonstração usa filtrarEtiquetas sobre uma lista em memória.
import { ETIQUETA_RE } from '../../projetos/domain/projetos';

export interface EtiquetaClickup {
  etiqueta: string;
  /** De onde veio: kpi (painel de KPIs), trafego (espelho do ClickUp do Tráfego). */
  fontes: string[];
}

/** O que public.trafego_clickup_etiquetas_buscar devolve. */
export interface BuscaEtiquetas {
  etiquetas: EtiquetaClickup[];
  /** true = a fonte do painel de KPIs (kpi.medicao_tarefa) foi lida. */
  fonte_kpi: boolean;
}

/** Texto de busca normalizado: sem acento, minúsculo, sem espaço nas pontas. */
export const normalizarBusca = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

export function filtrarEtiquetas(todas: EtiquetaClickup[], busca: string, limite = 30): EtiquetaClickup[] {
  const b = normalizarBusca(busca);
  const porEtq = new Map<string, Set<string>>();
  for (const e of todas) {
    const x = e.etiqueta.trim().toLowerCase();
    if (!ETIQUETA_RE.test(x) || !x.includes(b)) continue;
    const f = porEtq.get(x) ?? new Set<string>();
    e.fontes.forEach((y) => f.add(y));
    porEtq.set(x, f);
  }
  const peso = (x: string) => (x === b ? 0 : x.startsWith(b) ? 1 : 2);
  return [...porEtq.entries()]
    .map(([etiqueta, f]) => ({ etiqueta, fontes: [...f].sort() }))
    .sort((a, c) => peso(a.etiqueta) - peso(c.etiqueta) || a.etiqueta.localeCompare(c.etiqueta))
    .slice(0, Math.max(1, limite));
}

/** A etiqueta digitada está entre as achadas? (vazio = não se aplica). */
export const etiquetaEncontrada = (achadas: EtiquetaClickup[] | null, valor: string) =>
  !valor.trim() || achadas === null || achadas.some((e) => e.etiqueta === valor.trim().toLowerCase());
