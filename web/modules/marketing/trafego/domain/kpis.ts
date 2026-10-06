// Marketing > Tráfego: os cálculos da Central do Tráfego. Domínio puro (sem Next, sem Supabase).
//
// As MESMAS fórmulas estão no banco (mkt_trafego.resumo, migration 20261006g). Mudou aqui, muda lá (e o contrário).
// Regra da casa: sem fonte ou sem base para a conta = null ("sem dado"), nunca zero inventado.
//   % da verba   = investido ÷ verba máxima × 100           (1 casa)
//   CPL          = investido ÷ leads da nossa base           (2 casas) (lead da base, decisão do Victor 05/10/2026)
//   leads        = nulo ("sem dado") enquanto o projeto não tiver nenhum lead na base; com isso CPL e % MQL também
//   CTR          = cliques no link ÷ impressões × 100        (2 casas) (cliques no link, Victor 05/10/2026)
//   CPC          = investido ÷ cliques no link               (2 casas)
//   CPM          = investido ÷ impressões × 1000             (2 casas)
//   % MQL        = MQL ÷ leads × 100                         (1 casa)
//   connect rate = page views ÷ cliques no link × 100        (1 casa)
//   conversão    = leads da página ÷ page views × 100        (1 casa)
//   page view = a mesma da Web fase 2 (public.mkt_web_connect, 20261006h): visita vinda da campanha, uma por visita;
//   leads da página = dessas visitas, as que viraram lead. Assim o Tráfego e a Web mostram o mesmo número.
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
export const ctr = (cliquesLink: number | null, impressoes: number | null) => razao(cliquesLink, impressoes, 100, 2);
export const cpc = (investido: number | null, cliquesLink: number | null) => razao(investido, cliquesLink, 1, 2);
export const connectRate = (pageViews: number | null, cliquesLink: number | null) => razao(pageViews, cliquesLink, 100, 1);
export const conversaoPagina = (leadsPagina: number | null, pageViews: number | null) => razao(leadsPagina, pageViews, 100, 1);
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
type Totais = 'investido' | 'verba_maxima' | 'impressoes' | 'cliques_link' | 'page_views' | 'leads_pagina' | 'leads' | 'mql' | 'gasto_ontem' | 'verba_diaria';
type Kpis = 'pct_verba' | 'cpl' | 'ctr' | 'cpc' | 'cpm' | 'pct_mql' | 'connect_rate' | 'conversao_pagina' | 'ritmo_ontem';
export function comKpis<T extends Pick<LinhaResumo, Totais>>(l: T): T & Pick<LinhaResumo, Kpis> {
  // nenhum lead do projeto na base = "sem dado", não zero (auditoria 06/10/2026; o banco faz o mesmo em mkt_trafego.resumo)
  const leads = num(l.leads) && l.leads > 0 ? l.leads : null;
  const mql = leads === null ? null : l.mql;
  return {
    ...l,
    leads,
    mql,
    pct_verba: pctVerba(l.investido, l.verba_maxima),
    cpl: cpl(l.investido, leads),
    ctr: ctr(l.cliques_link, l.impressoes),
    cpc: cpc(l.investido, l.cliques_link),
    cpm: cpm(l.investido, l.impressoes),
    pct_mql: pctMql(mql, leads),
    connect_rate: connectRate(l.page_views, l.cliques_link),
    conversao_pagina: conversaoPagina(l.leads_pagina, l.page_views),
    ritmo_ontem: l.investido == null ? null : ritmo(l.gasto_ontem, l.verba_diaria),
  };
}

export interface FiltrosCentral {
  tipo: '' | Tipo;
  /** Código da unidade (csm, escritorio, aurum, diamantes); 'sem' = sem unidade marcada. */
  unidade: string;
  /** Sigla do gestor (CF, RS, EF): casa com um dos gestores do projeto OU com o de alguma campanha do projeto. */
  gestor: string;
  /** Código do status; 'sem' = sem status marcado. */
  status: string;
  /** Mostrar projetos desativados em mkt.projetos. */
  inativos: boolean;
}

export const FILTROS_INICIAIS: FiltrosCentral = { tipo: '', unidade: '', gestor: '', status: '', inativos: false };

export function filtrar(linhas: LinhaResumo[], f: FiltrosCentral): LinhaResumo[] {
  return linhas.filter((l) => {
    if (!f.inativos && !l.projeto_ativo) return false;
    if (f.tipo && l.tipo !== f.tipo) return false;
    if (f.unidade === 'sem' ? (l.unidade ?? null) !== null : f.unidade && l.unidade !== f.unidade) return false;
    if (f.gestor && !l.gestores.includes(f.gestor) && !l.gestores_campanhas.includes(f.gestor)) return false;
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

// ─── Busca e ordenação da tabela da Central (auditoria 06/10/2026). Estado na URL: ?q=…&ordem=coluna&dir=asc|desc ──

export const COLUNAS_CENTRAL = [
  'status', 'projeto', 'receita', 'investido', 'verba_maxima', 'pct_verba', 'cpl', 'leads', 'ctr', 'cpm', 'connect_rate',
  'conversao_pagina', 'pct_mql', 'gestor', 'montagem',
] as const;
export type ColunaCentral = (typeof COLUNAS_CENTRAL)[number];
export type Direcao = 'asc' | 'desc';
export interface OrdemCentral { coluna: ColunaCentral | null; dir: Direcao }
export const ORDEM_INICIAL: OrdemCentral = { coluna: null, dir: 'asc' };

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/** Busca por sigla ou nome do projeto (sem diferença de maiúscula nem acento). Vazio = todas. */
export function buscarLinhas(linhas: LinhaResumo[], q: string): LinhaResumo[] {
  const t = semAcento(q);
  if (!t) return linhas;
  return linhas.filter((l) => semAcento(l.sigla).includes(t) || semAcento(l.nome ?? '').includes(t));
}

/** O valor que a coluna mostra (o que ordena). null = "sem dado" (vai sempre para o fim, nas duas direções). */
function valorColuna(l: LinhaResumo, c: ColunaCentral): number | string | null {
  switch (c) {
    case 'status': return l.status_nome ?? null;
    case 'projeto': return l.sigla;
    case 'receita': return l.receita_aplica === false ? null : l.receita;
    case 'gestor': {
      const g = l.gestores.length ? l.gestores : l.gestores_campanhas;
      return g.length ? g.join(', ') : null;
    }
    case 'montagem': return l.checklist_total ? (l.checklist_feitos ?? 0) / l.checklist_total : null;
    default: return l[c] ?? null;
  }
}

/** Ordena pela coluna; empate e "sem dado" ficam na ordem original (o banco já manda ativos primeiro e por sigla). */
export function ordenarLinhas(linhas: LinhaResumo[], o: OrdemCentral): LinhaResumo[] {
  if (!o.coluna) return linhas;
  const c = o.coluna;
  const sinal = o.dir === 'asc' ? 1 : -1;
  return linhas
    .map((l, i) => ({ l, i, v: valorColuna(l, c) }))
    .sort((a, b) => {
      if (a.v === null || b.v === null) return a.v === b.v ? a.i - b.i : a.v === null ? 1 : -1;
      const d = typeof a.v === 'number' && typeof b.v === 'number' ? a.v - b.v : String(a.v).localeCompare(String(b.v), 'pt-BR');
      return d !== 0 ? d * sinal : a.i - b.i;
    })
    .map((x) => x.l);
}

/** Clique no cabeçalho: coluna nova começa crescente; a mesma alterna; a terceira vez volta à ordem do banco. */
export function alternarOrdem(atual: OrdemCentral, c: ColunaCentral): OrdemCentral {
  if (atual.coluna !== c) return { coluna: c, dir: 'asc' };
  return atual.dir === 'asc' ? { coluna: c, dir: 'desc' } : ORDEM_INICIAL;
}

/** Lê busca e ordem da URL (valores fora da lista são ignorados). */
export function lerEstadoUrl(qs: string): { q: string; ordem: OrdemCentral } {
  const p = new URLSearchParams(qs);
  const col = p.get('ordem');
  const coluna = (COLUNAS_CENTRAL as readonly string[]).includes(col ?? '') ? (col as ColunaCentral) : null;
  return { q: (p.get('q') ?? '').slice(0, 80), ordem: coluna ? { coluna, dir: p.get('dir') === 'desc' ? 'desc' : 'asc' } : ORDEM_INICIAL };
}

/** Escreve busca e ordem na query string atual, sem tocar nos outros parâmetros. */
export function escreverEstadoUrl(qs: string, q: string, o: OrdemCentral): string {
  const p = new URLSearchParams(qs);
  if (q.trim()) p.set('q', q.trim()); else p.delete('q');
  if (o.coluna) { p.set('ordem', o.coluna); p.set('dir', o.dir); } else { p.delete('ordem'); p.delete('dir'); }
  const s = p.toString();
  return s ? `?${s}` : '';
}
