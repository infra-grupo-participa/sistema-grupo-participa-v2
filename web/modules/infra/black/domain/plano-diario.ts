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
const ORDEM_CAMADAS = ['c3', 'c2', 'remarketing', 'c1', 'aquecimento', 'remarketing_live', 'carrinho', 'historico'] as const;
const ROTULO_CAMADA: Record<string, string> = {
  c3: 'C3', c2: 'C2', remarketing: 'Remarketing', c1: 'C1', aquecimento: 'Aquecimento',
  remarketing_live: 'Remarketing da live', carrinho: 'Carrinho', historico: 'Teaser (histórico)',
};
const COR_CAMADA: Record<string, string> = {
  c3: 'var(--accent)', c2: 'var(--cyan)', remarketing: 'var(--purple)', c1: 'var(--green)', aquecimento: 'var(--yellow)',
  remarketing_live: 'var(--red)', carrinho: 'var(--info)', historico: 'var(--fg-3)',
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

/**
 * Limites da vigia da Black (decisão 15 de 15/10/2026, aprovada pelo Arthur): os mesmos do alerta do Slack.
 * Ritmo com tolerância de 40% até 12h e 25% depois; zero lead a partir das 9h; CPL com teto R$ 30
 * (R$ 100 em campanha de aluno, piso R$ 8). Aqui o CPL é o do dia no segmento, não a janela de 3 horas da vigia.
 * O painel ainda não separa campanha de aluno: todo segmento é julgado pelo teto geral (cplTetoAluno fica registrado
 * para quando a camada trouxer essa marca). O piso vale: CPL abaixo dele não recomenda acelerar.
 */
export const VIGIA_BLACK = {
  toleranciaAte12h: 0.4, toleranciaDepois12h: 0.25, horaZeroLead: 9,
  cplTeto: 30, cplTetoAluno: 100, cplPiso: 8,
} as const;

function horaSp(agora: Date): number {
  const [h, m] = agora.toLocaleTimeString('sv-SE', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }).split(':').map(Number);
  return h + m / 60;
}
export const toleranciaRitmo = (agora: Date) => (horaSp(agora) < 12 ? VIGIA_BLACK.toleranciaAte12h : VIGIA_BLACK.toleranciaDepois12h);

export interface AlertaRitmo {
  segmento: Segmento; pctVerba: Valor; pctLeads: Valor; faltaVerba: number; faltaLeads: number; cpl: Valor;
  verbaAtras: boolean; leadsAtras: boolean; parado: boolean; zeroLead: boolean;
}

/**
 * Regras do parágrafo dos Alertas, sobre o dia de hoje (limites em VIGIA_BLACK):
 * - ritmo esperado = meta do dia × fração do dia já passada; atrás = abaixo de (1 - tolerância) do ritmo;
 * - parado: meta de verba e gasto zero a partir das 9h; zero lead: meta de leads e nenhum lead a partir das 9h.
 */
export function alertasDoDia(dia: DiaPlano | undefined, agora: Date): AlertaRitmo[] {
  if (!dia) return [];
  const f = fracaoDoDia(dia.dia, agora);
  if (f <= 0) return [];
  const piso = (1 - (f >= 1 ? VIGIA_BLACK.toleranciaDepois12h : toleranciaRitmo(agora))) * 100;
  const depoisDas9 = f >= 1 || horaSp(agora) >= VIGIA_BLACK.horaZeroLead;
  const out: AlertaRitmo[] = [];
  for (const s of dia.segmentos) {
    if (s.verbaReal === null || s.verbaMeta <= 0) continue; // sem coleta (Google) ou sem meta
    const ritmoVerba = s.verbaMeta * f;
    const ritmoLeads = s.leadsMeta * f;
    const pctVerba = ritmoVerba > 0 ? (s.verbaReal / ritmoVerba) * 100 : null;
    const pctLeads = ritmoLeads > 0 && s.leadsReal !== null ? (s.leadsReal / ritmoLeads) * 100 : null;
    const parado = s.verbaReal === 0 && depoisDas9;
    const zeroLead = s.leadsMeta > 0 && s.leadsReal === 0 && s.verbaReal > 0 && depoisDas9;
    const verbaAtras = pctVerba !== null && pctVerba < piso;
    const leadsAtras = pctLeads !== null && pctLeads < piso;
    if (!verbaAtras && !leadsAtras && !parado && !zeroLead) continue;
    out.push({
      segmento: s.segmento, pctVerba, pctLeads, parado, zeroLead, verbaAtras, leadsAtras,
      cpl: s.leadsReal && s.leadsReal > 0 ? s.verbaReal / s.leadsReal : null,
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
  partes.push(`Hoje, às ${hora} (verba em mídia, sem imposto do Meta): verba em ${pct(pctVerbaDia)} do ritmo, faltam ${brl(Math.max(0, t.verbaMeta - (t.verbaReal ?? 0)))} para a meta do dia; leads em ${pct(pctLeadsDia)} do ritmo, faltam ${Math.max(0, t.leadsMeta - (t.leadsReal ?? 0))}.`);
  const alertas = alertasDoDia(dia, agora);
  const teto = VIGIA_BLACK.cplTeto;
  for (const a of alertas.filter((x) => !x.parado).slice(0, 3)) {
    const cplTxt = a.cpl === null ? 'CPL sem dado' : `CPL ${brl(a.cpl)}`;
    if (a.zeroLead) {
      partes.push(`${a.segmento.rotulo} gastou sem nenhum lead hoje: conferir criativo, público e página antes de manter a verba.`);
    } else if (a.leadsAtras && (a.cpl === null || a.cpl > teto)) {
      partes.push(`${a.segmento.rotulo} com leads em ${pct(a.pctLeads)} do ritmo e ${cplTxt} (teto ${brl(teto)}): revisar criativo, público ou página; não subir verba enquanto o CPL estiver acima do teto.`);
    } else if (a.verbaAtras && a.cpl !== null && a.cpl >= VIGIA_BLACK.cplPiso && a.cpl <= teto) {
      partes.push(`${a.segmento.rotulo} com verba em ${pct(a.pctVerba)} do ritmo e ${cplTxt}, dentro do teto: faltam ${brl(a.faltaVerba)} para a meta do dia, dá para acelerar a entrega.`);
    } else if (a.verbaAtras) {
      const porque = a.cpl === null ? 'CPL ainda sem dado' : a.cpl < VIGIA_BLACK.cplPiso ? `${cplTxt}, abaixo do piso de ${brl(VIGIA_BLACK.cplPiso)}: conferir se os leads são reais` : `${cplTxt}, acima do teto`;
      partes.push(`${a.segmento.rotulo} com verba em ${pct(a.pctVerba)} do ritmo (faltam ${brl(a.faltaVerba)} para a meta do dia) e ${porque}; não acelerar até o CPL estar dentro do teto.`);
    } else if (a.leadsAtras) {
      partes.push(`${a.segmento.rotulo} com leads em ${pct(a.pctLeads)} do ritmo e ${cplTxt}: faltam ${a.faltaLeads} leads; olhar a conversão da página e os criativos.`);
    }
  }
  const parados = alertas.filter((a) => a.parado).map((a) => a.segmento.rotulo);
  if (parados.length) partes.push(`Sem gasto hoje com meta: ${parados.join(', ')}. Conferir se a campanha está parada.`);
  if (conversaoPagina !== null && conversaoPagina < 40) partes.push(`Página convertendo ${Math.round(conversaoPagina)}%, abaixo de 40%: revisar a página antes de subir verba.`);
  const semGoogle = dia.segmentos.some((s) => s.plataforma === 'google' && s.verbaMeta > 0 && s.verbaReal === null);
  if (semGoogle) partes.push('Google sem coleta no banco: o realizado do Google não entra nesta conta.');
  if (alertas.length === 0 && pctVerbaDia !== null) partes.push('Todos os segmentos com coleta estão dentro da tolerância da vigia.');
  return partes.join(' ');
}
