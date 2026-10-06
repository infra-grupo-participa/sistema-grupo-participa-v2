// Séries dos widgets do painel personalizável, puras e testáveis.
// Cada widget = métrica de METRICAS + período + agrupamento (+ funil opcional). As regras de contagem seguem
// as definições de `domain/metricas.ts`; mudou lá, conferir aqui. Dia sempre no fuso de Brasília (UTC-3, sem
// horário de verão desde 2019).
import { produto, rotuloMotivo } from '../../domain/catalogo';
import { ROTULO_PAPEL } from '../../domain/funis';
import { METRICAS } from '../../domain/metricas';
import { atividadeAtrasada, semProximoPasso, situacaoSla } from '../../domain/regras';
import type {
  AgrupamentoWidget, Atividade, EventoTimeline, Funil, MetricaKey, MotivoPerdaConfig, Negocio, PeriodoWidget, Vendedor, WidgetPainel,
} from '../../domain/types';

const H = 3_600_000;
const D = 24 * H;
const FUSO = 3 * H; // Brasília = UTC-3

export interface DadosPainel {
  negocios: Negocio[];
  atividades: Atividade[];
  eventos: EventoTimeline[];
  funis: Funil[];
  motivos: Pick<MotivoPerdaConfig, 'key' | 'label'>[];
  vendedores: Pick<Vendedor, 'id' | 'nome'>[];
  agora: Date;
  /** Perspectiva: vendedor dono. null = time inteiro. */
  donoId: string | null;
}

export interface PontoSerie {
  chave: string;
  rotulo: string;
  valor: number;
}

export interface SerieWidget {
  formato: 'numero' | 'moeda' | 'percentual' | 'minutos';
  /** Valor do período inteiro (null = sem base, ex.: conversão sem negócio encerrado). */
  valor: number | null;
  /** Mesmo cálculo no período anterior equivalente; null quando não faz sentido (fotografia do momento). */
  anterior: number | null;
  pontos: PontoSerie[];
  /** Fotografia do momento: ignora o período. */
  fotografia: boolean;
}

/** Métricas que são fotografia do agora (não somam no tempo). */
export const FOTOGRAFIA: ReadonlySet<MetricaKey> = new Set(['em_negociacao', 'abertos', 'criticos', 'sem_proximo', 'sem_dono', 'atrasadas']);

// ── Datas ──

/** "2026-10-05" do dia em Brasília. */
export function diaBR(d: Date | string): string {
  const t = typeof d === 'string' ? new Date(d).getTime() : d.getTime();
  return new Date(t - FUSO).toISOString().slice(0, 10);
}

/** Meia-noite de Brasília do dia de `d`. */
export function inicioDiaBR(d: Date): Date {
  return new Date(Date.parse(`${diaBR(d)}T00:00:00Z`) + FUSO);
}

export interface Intervalo { ini: number; fim: number }

/** Período do widget e o anterior equivalente (mesmo tamanho, até o mesmo ponto: hoje até agora × ontem até esta hora). */
export function intervalos(periodo: PeriodoWidget, agora: Date): { atual: Intervalo; anterior: Intervalo } {
  const hoje = inicioDiaBR(agora).getTime();
  const fim = agora.getTime();
  if (periodo === 'mes') {
    const [y, m] = diaBR(agora).split('-').map(Number);
    const ini = Date.UTC(y, m - 1, 1) + FUSO;
    const iniAnt = Date.UTC(y, m - 2, 1) + FUSO;
    const fimAnt = Math.min(iniAnt + (fim - ini), ini);
    return { atual: { ini, fim }, anterior: { ini: iniAnt, fim: fimAnt } };
  }
  const dias = periodo === 'hoje' ? 1 : periodo === '7d' ? 7 : 30;
  const ini = hoje - (dias - 1) * D;
  return { atual: { ini, fim }, anterior: { ini: ini - dias * D, fim: fim - dias * D } };
}

const dentro = (iso: string | null | undefined, i: Intervalo) => {
  if (!iso) return false;
  const t = Date.parse(iso);
  return t >= i.ini && t <= i.fim;
};

/** Dias (chave "AAAA-MM-DD") do intervalo, em ordem. */
export function diasDoIntervalo(i: Intervalo): string[] {
  const out: string[] = [];
  for (let t = inicioDiaBR(new Date(i.ini)).getTime(); t <= i.fim; t += D) out.push(diaBR(new Date(t)));
  return out;
}

// ── Cálculo ──

/** Um fato contável: quem é o dono, de que negócio, quando, e quanto vale (ou mede). */
interface Fato {
  donoId: string | null;
  negocio: Negocio | null;
  em: string | null;
  /** Para conversão: 1 = ganho, 0 = perdido. Para tempo: minutos. Para moeda: valor. Senão 1. */
  peso: number;
  /** Pessoa (contato) para métricas que contam gente única. */
  pessoa?: string;
}

/** Fatos da métrica no intervalo, já filtrados por dono e funil. */
function fatos(m: MetricaKey, d: DadosPainel, i: Intervalo, funilId: string | null): Fato[] {
  const porId = new Map(d.negocios.map((n) => [n.id, n]));
  // sem_dono é do time por definição: não filtra por dono.
  const doDono = (id: string | null) => m === 'sem_dono' || d.donoId == null || id === d.donoId;
  const doFunil = (n: Negocio | null | undefined) => !funilId || n?.funilId === funilId;
  const negs = d.negocios.filter((n) => doFunil(n) && doDono(n.donoId));
  const agora = d.agora;
  const fato = (n: Negocio, peso = 1, em: string | null = null): Fato => ({ donoId: n.donoId, negocio: n, em, peso });

  switch (m) {
    case 'abordados': {
      // Pessoa única no período (e por dia, ao agrupar por dia): `reduzir` deduplica por contato.
      return d.atividades
        .filter((a) => (a.tipo === 'whatsapp' || a.tipo === 'ligacao') && dentro(a.concluidaEm, i) && doDono(a.donoId))
        .map((a) => ({ a, n: a.negocioId ? porId.get(a.negocioId) ?? null : null }))
        .filter(({ n }) => doFunil(n))
        .map(({ a, n }) => ({ donoId: a.donoId, negocio: n, em: a.concluidaEm, peso: 1, pessoa: a.contatoId }));
    }
    case 'responderam':
    case 'entraram_contato': {
      const abordadosNoPeriodo = new Set(
        d.atividades.filter((a) => (a.tipo === 'whatsapp' || a.tipo === 'ligacao') && dentro(a.concluidaEm, i)).map((a) => a.contatoId),
      );
      return d.eventos
        .filter((e) => dentro(e.em, i) && (m === 'responderam'
          ? e.tipo === 'etapa' && e.detalhe === 'qualificar'
          : e.tipo === 'mensagem' && e.titulo.startsWith('Lead escreveu') && !abordadosNoPeriodo.has(e.contatoId)))
        .map((e) => ({ e, n: e.negocioId ? porId.get(e.negocioId) ?? null : null }))
        .filter(({ n }) => doFunil(n) && doDono(n?.donoId ?? null))
        .map(({ e, n }) => ({ donoId: n?.donoId ?? null, negocio: n, em: e.em, peso: 1, pessoa: e.contatoId }));
    }
    case 'em_negociacao':
      return negs.filter((n) => n.status === 'aberto' && (n.etapa === 'negociar' || n.etapa === 'aguardar_pagamento')).map((n) => fato(n, n.valor));
    case 'vendas':
      return negs.filter((n) => n.status === 'ganho' && dentro(n.fechadoEm, i)).map((n) => fato(n, 1, n.fechadoEm));
    case 'receita':
      return negs.filter((n) => n.status === 'ganho' && dentro(n.fechadoEm, i)).map((n) => fato(n, n.valor, n.fechadoEm));
    case 'abertos':
      return negs.filter((n) => n.status === 'aberto').map((n) => fato(n));
    case 'criticos':
      return negs.filter((n) => situacaoSla(n, agora) === 'critico').map((n) => fato(n));
    case 'sem_proximo':
      return negs.filter(semProximoPasso).map((n) => fato(n));
    case 'sem_dono':
      return negs.filter((n) => n.status === 'aberto' && !n.donoId).map((n) => fato(n));
    case 'atrasadas':
      return d.atividades
        .filter((a) => atividadeAtrasada(a, agora) && doDono(a.donoId))
        .map((a) => ({ a, n: a.negocioId ? porId.get(a.negocioId) ?? null : null }))
        .filter(({ n }) => doFunil(n))
        .map(({ a, n }) => ({ donoId: a.donoId, negocio: n, em: a.venceEm, peso: 1 }));
    case 'tempo_primeiro_contato': {
      const out: Fato[] = [];
      for (const n of negs) {
        if (!dentro(n.criadoEm, i) || !n.donoId) continue;
        const primeira = d.atividades
          .filter((a) => a.negocioId === n.id && a.donoId === n.donoId && a.concluidaEm && a.concluidaEm >= n.criadoEm)
          .map((a) => a.concluidaEm!)
          .sort()[0];
        if (primeira) out.push(fato(n, (Date.parse(primeira) - Date.parse(n.criadoEm)) / 60000, n.criadoEm));
      }
      return out;
    }
    case 'conversao':
      return negs.filter((n) => n.status !== 'aberto' && dentro(n.fechadoEm, i)).map((n) => fato(n, n.status === 'ganho' ? 1 : 0, n.fechadoEm));
    case 'perdidos':
      return negs.filter((n) => n.status === 'perdido' && dentro(n.fechadoEm, i)).map((n) => fato(n, 1, n.fechadoEm));
  }
}

const mediana = (v: number[]) => {
  if (!v.length) return null;
  const s = [...v].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

/** Junta os fatos num número, conforme a métrica. */
function reduzir(m: MetricaKey, f: Fato[]): number | null {
  if (m === 'abordados' || m === 'responderam' || m === 'entraram_contato') return new Set(f.map((x) => x.pessoa)).size;
  if (m === 'tempo_primeiro_contato') {
    const v = mediana(f.map((x) => x.peso));
    return v == null ? null : Math.round(v);
  }
  if (m === 'conversao') return f.length ? Math.round((f.filter((x) => x.peso === 1).length / f.length) * 1000) / 10 : null;
  return f.reduce((s, x) => s + x.peso, 0);
}

function chaveGrupo(a: AgrupamentoWidget, f: Fato, d: DadosPainel): { chave: string; rotulo: string } {
  const n = f.negocio;
  switch (a) {
    case 'vendedor': return { chave: f.donoId ?? '-', rotulo: f.donoId ? d.vendedores.find((v) => v.id === f.donoId)?.nome ?? '—' : 'Sem dono' };
    case 'produto': return n ? { chave: n.produto, rotulo: produto(n.produto).nome } : { chave: '-', rotulo: 'Sem negócio' };
    case 'etapa': return n ? { chave: n.etapa, rotulo: ROTULO_PAPEL[n.etapa] } : { chave: '-', rotulo: 'Sem negócio' };
    case 'funil': return n ? { chave: n.funilId, rotulo: d.funis.find((x) => x.id === n.funilId)?.nome ?? 'Funil arquivado' } : { chave: '-', rotulo: 'Sem negócio' };
    case 'motivo': return { chave: n?.motivoPerda ?? '-', rotulo: rotuloMotivo(n?.motivoPerda ?? null, d.motivos) };
    case 'dia': {
      const k = f.em ? diaBR(f.em) : '-';
      return { chave: k, rotulo: rotuloDia(k) };
    }
    default: return { chave: 'total', rotulo: 'Total' };
  }
}

/** "05/10" a partir de "2026-10-05". */
export function rotuloDia(k: string): string {
  const [, m, d] = k.split('-');
  return d && m ? `${d}/${m}` : k;
}

/** Calcula o que o widget mostra, na perspectiva de `d.donoId`. */
export function calcularWidget(w: Pick<WidgetPainel, 'metrica' | 'periodo' | 'agrupar' | 'funilId'>, d: DadosPainel): SerieWidget {
  const def = METRICAS[w.metrica];
  const fotografia = FOTOGRAFIA.has(w.metrica);
  const { atual, anterior } = intervalos(w.periodo, d.agora);
  const fAtual = fatos(w.metrica, d, atual, w.funilId);
  const valor = reduzir(w.metrica, fAtual);
  const valorAnterior = fotografia ? null : reduzir(w.metrica, fatos(w.metrica, d, anterior, w.funilId));

  // Agrupamento só se a métrica aceita; senão vira total.
  const agrupar: AgrupamentoWidget = def.agrupamentos.includes(w.agrupar) ? w.agrupar : 'nenhum';
  let pontos: PontoSerie[] = [];
  if (agrupar !== 'nenhum') {
    const grupos = new Map<string, { rotulo: string; fatos: Fato[] }>();
    for (const f of fAtual) {
      const g = chaveGrupo(agrupar, f, d);
      const item = grupos.get(g.chave) ?? { rotulo: g.rotulo, fatos: [] };
      item.fatos.push(f);
      grupos.set(g.chave, item);
    }
    if (agrupar === 'dia') {
      // Todo dia do período aparece, mesmo zerado: a linha não pula dia.
      pontos = diasDoIntervalo(atual).map((k) => ({ chave: k, rotulo: rotuloDia(k), valor: reduzir(w.metrica, grupos.get(k)?.fatos ?? []) ?? 0 }));
    } else {
      pontos = [...grupos].map(([chave, g]) => ({ chave, rotulo: g.rotulo, valor: reduzir(w.metrica, g.fatos) ?? 0 }))
        .sort((a, b) => b.valor - a.valor || a.rotulo.localeCompare(b.rotulo));
    }
  }
  return { formato: def.formato, valor, anterior: valorAnterior, pontos, fotografia };
}

/** Variação contra o período anterior, em %. null quando não dá para comparar. */
export function variacao(s: Pick<SerieWidget, 'valor' | 'anterior'>): number | null {
  if (s.valor == null || s.anterior == null || s.anterior === 0) return null;
  return Math.round(((s.valor - s.anterior) / s.anterior) * 100);
}

/** Métricas em que subir é ruim (a seta fica vermelha quando sobe). */
export const MENOS_E_MELHOR: ReadonlySet<MetricaKey> = new Set(['criticos', 'sem_proximo', 'sem_dono', 'atrasadas', 'tempo_primeiro_contato', 'perdidos']);

/** Valor formatado conforme a métrica (sem depender de React). */
export function formatarValor(v: number | null, formato: SerieWidget['formato']): string {
  if (v == null) return '—';
  if (formato === 'moeda') return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
  if (formato === 'percentual') return `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
  if (formato === 'minutos') {
    if (v < 60) return `${Math.round(v)} min`;
    const h = Math.floor(v / 60);
    return h < 24 ? `${h} h ${Math.round(v % 60)} min` : `${Math.floor(h / 24)} d ${h % 24} h`;
  }
  return v.toLocaleString('pt-BR');
}
