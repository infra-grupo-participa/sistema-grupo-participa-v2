// Meta contra realizado por dia e segmento da Black (pedido do Arthur, 16/10/2026). Lê a RPC dados_black_plano_diario:
// uma linha por dia, plataforma e camada, com verba e leads da meta e do realizado. Funções puras, testadas.
import type { Valor } from './tipos';

export type Plataforma = 'meta' | 'google';
export interface LinhaPlano {
  dia: string; plataforma: Plataforma; camada: string | null;
  verbaMeta: number; verbaReal: number | null; leadsMeta: number; leadsReal: number | null;
}
export interface Segmento { chave: string; plataforma: Plataforma; camada: string | null; rotulo: string; cor: string; opaco: boolean }
export interface DiaPlano {
  dia: string;
  total: { verbaMeta: number; verbaReal: number | null; leadsMeta: number; leadsReal: number | null };
  segmentos: (LinhaPlano & { segmento: Segmento })[];
}

/** Ordem do pedido: Meta C3, C2, remarketing, C1, aquecimento; Google C3, C2, C1, aquecimento; depois live e carrinho. */
const ORDEM_CAMADAS = ['c3', 'c2', 'remarketing', 'c1', 'aquecimento', 'remarketing_live', 'carrinho'] as const;
const ROTULO_CAMADA: Record<string, string> = {
  c3: 'C3', c2: 'C2', remarketing: 'Remarketing', c1: 'C1', aquecimento: 'Aquecimento',
  remarketing_live: 'Remarketing da live', carrinho: 'Carrinho',
};
const COR_CAMADA: Record<string, string> = {
  c3: 'var(--accent)', c2: 'var(--cyan)', remarketing: 'var(--purple)', c1: 'var(--green)', aquecimento: 'var(--yellow)',
  remarketing_live: 'var(--red)', carrinho: 'var(--info)',
};

export function segmentoDe(plataforma: Plataforma, camada: string | null): Segmento {
  const nomePlat = plataforma === 'meta' ? 'Meta' : 'Google';
  return {
    chave: `${plataforma}:${camada ?? 'sem'}`, plataforma, camada,
    rotulo: camada ? `${nomePlat} ${ROTULO_CAMADA[camada] ?? camada}` : `${nomePlat} sem segmento`,
    cor: camada ? COR_CAMADA[camada] ?? 'var(--fg-3)' : 'var(--fg-4)',
    opaco: plataforma === 'google',
  };
}

export function ordemSegmento(s: Segmento): number {
  const i = s.camada ? ORDEM_CAMADAS.indexOf(s.camada as (typeof ORDEM_CAMADAS)[number]) : 99;
  const base = i < 0 ? 98 : i;
  // live e carrinho ficam no fim, nas duas plataformas
  return base >= 5 ? 200 + base * 2 + (s.plataforma === 'google' ? 1 : 0) : (s.plataforma === 'google' ? 100 : 0) + base;
}

const num = (v: unknown): number | null => (v === null || v === undefined || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);

export function mapearPlano(bruto: unknown): LinhaPlano[] {
  if (!Array.isArray(bruto)) return [];
  return bruto.map((r: Record<string, unknown>) => ({
    dia: String(r.dia).slice(0, 10),
    plataforma: r.plataforma === 'google' ? 'google' : 'meta',
    camada: typeof r.camada === 'string' && r.camada ? r.camada : null,
    verbaMeta: num(r.verba_meta) ?? 0, verbaReal: num(r.verba_real),
    leadsMeta: num(r.leads_meta) ?? 0, leadsReal: num(r.leads_real),
  }));
}

const soma = (vs: (number | null)[]): number | null => (vs.every((v) => v === null) ? null : vs.reduce<number>((a, v) => a + (v ?? 0), 0));

export function agruparPorDia(linhas: LinhaPlano[]): DiaPlano[] {
  const porDia = new Map<string, LinhaPlano[]>();
  for (const l of linhas) porDia.set(l.dia, [...(porDia.get(l.dia) ?? []), l]);
  return [...porDia.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([dia, ls]) => {
    const segmentos = ls.map((l) => ({ ...l, segmento: segmentoDe(l.plataforma, l.camada) }))
      .sort((a, b) => ordemSegmento(a.segmento) - ordemSegmento(b.segmento));
    return {
      dia,
      total: {
        verbaMeta: ls.reduce((a, l) => a + l.verbaMeta, 0), verbaReal: soma(ls.map((l) => l.verbaReal)),
        leadsMeta: ls.reduce((a, l) => a + l.leadsMeta, 0), leadsReal: soma(ls.map((l) => l.leadsReal)),
      },
      segmentos,
    };
  });
}

/** Segmentos presentes no período, na ordem do pedido (para legenda e cores do gráfico). */
export function segmentosDoPeriodo(dias: DiaPlano[]): Segmento[] {
  const m = new Map<string, Segmento>();
  for (const d of dias) for (const s of d.segmentos) m.set(s.segmento.chave, s.segmento);
  return [...m.values()].sort((a, b) => ordemSegmento(a) - ordemSegmento(b));
}

export function pctDaMeta(real: number | null, meta: number): Valor {
  if (real === null || meta <= 0) return null;
  return (real / meta) * 100;
}

/** Fração do dia já passada em São Paulo (0 a 1). Dia passado = 1; futuro = 0. */
export function fracaoDoDia(dia: string, agora: Date): number {
  const hojeSp = agora.toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  if (dia < hojeSp) return 1;
  if (dia > hojeSp) return 0;
  const [h, m] = agora.toLocaleTimeString('sv-SE', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }).split(':').map(Number);
  return Math.min(1, Math.max(0, (h * 60 + m) / (24 * 60)));
}

export interface AlertaRitmo { segmento: Segmento; pctVerba: Valor; pctLeads: Valor; faltaVerba: number; faltaLeads: number; parado: boolean }

/**
 * Regras do parágrafo dos Alertas, sobre o dia de hoje:
 * - ritmo esperado = meta do dia × fração do dia já passada;
 * - abaixo de 80% do ritmo (verba ou leads) entra no resumo;
 * - meta do dia acima de zero e gasto zero depois das 10h = campanha possivelmente parada.
 */
export function alertasDoDia(dia: DiaPlano | undefined, agora: Date, limite = 0.8): AlertaRitmo[] {
  if (!dia) return [];
  const f = fracaoDoDia(dia.dia, agora);
  if (f <= 0) return [];
  const out: AlertaRitmo[] = [];
  for (const s of dia.segmentos) {
    if (s.verbaReal === null || s.verbaMeta <= 0) continue; // sem coleta (Google) ou sem meta
    const ritmoVerba = s.verbaMeta * f;
    const ritmoLeads = s.leadsMeta * f;
    const pctVerba = ritmoVerba > 0 ? (s.verbaReal / ritmoVerba) * 100 : null;
    const pctLeads = ritmoLeads > 0 && s.leadsReal !== null ? (s.leadsReal / ritmoLeads) * 100 : null;
    const parado = s.verbaReal === 0 && f >= 10 / 24;
    const abaixo = (pctVerba !== null && pctVerba < limite * 100) || (pctLeads !== null && pctLeads < limite * 100);
    if (!abaixo && !parado) continue;
    out.push({
      segmento: s.segmento, pctVerba, pctLeads, parado,
      faltaVerba: Math.max(0, s.verbaMeta - s.verbaReal),
      faltaLeads: Math.max(0, s.leadsMeta - (s.leadsReal ?? 0)),
    });
  }
  return out.sort((a, b) => b.faltaVerba - a.faltaVerba);
}

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 }).format(v);
const pct = (v: Valor) => (v === null ? 'sem dado' : `${Math.round(v)}%`);

/** Parágrafo do topo dos Alertas. `conversaoPagina` em %, quando houver. Devolve null sem plano para hoje. */
export function resumoAjusteDoDia(dia: DiaPlano | undefined, agora: Date, conversaoPagina: Valor): string | null {
  if (!dia) return null;
  const hora = agora.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' });
  const f = fracaoDoDia(dia.dia, agora);
  const t = dia.total;
  const partes: string[] = [];
  const pctVerbaDia = t.verbaReal === null || t.verbaMeta <= 0 || f <= 0 ? null : (t.verbaReal / (t.verbaMeta * f)) * 100;
  const pctLeadsDia = t.leadsReal === null || t.leadsMeta <= 0 || f <= 0 ? null : (t.leadsReal / (t.leadsMeta * f)) * 100;
  partes.push(`Hoje, às ${hora}: verba em ${pct(pctVerbaDia)} do ritmo (faltam ${brl(Math.max(0, t.verbaMeta - (t.verbaReal ?? 0)))} no dia) e leads em ${pct(pctLeadsDia)} do ritmo (faltam ${Math.max(0, t.leadsMeta - (t.leadsReal ?? 0))}).`);
  const alertas = alertasDoDia(dia, agora);
  const abaixo = alertas.filter((a) => !a.parado).slice(0, 3);
  for (const a of abaixo) {
    partes.push(`${a.segmento.rotulo} em ${pct(a.pctVerba)} do ritmo de verba e ${pct(a.pctLeads)} do de leads: subir a verba em ${brl(a.faltaVerba)} até o fim do dia.`);
  }
  const parados = alertas.filter((a) => a.parado).map((a) => a.segmento.rotulo);
  if (parados.length) partes.push(`Sem gasto hoje com meta: ${parados.join(', ')}. Conferir se a campanha está parada.`);
  if (conversaoPagina !== null && conversaoPagina < 40) partes.push(`Página convertendo ${Math.round(conversaoPagina)}%, abaixo de 40%: revisar a página antes de subir verba.`);
  const semGoogle = dia.segmentos.some((s) => s.plataforma === 'google' && s.verbaMeta > 0 && s.verbaReal === null);
  if (semGoogle) partes.push('Google sem coleta no banco: o realizado do Google não entra nesta conta.');
  if (partes.length === 1 && pctVerbaDia !== null && pctVerbaDia >= 80 && (pctLeadsDia === null || pctLeadsDia >= 80)) partes.push('Todos os segmentos com coleta estão no ritmo.');
  return partes.join(' ');
}
