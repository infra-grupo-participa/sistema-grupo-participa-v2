// Agenda do vendedor, pura e testável: em que aba cada atividade cai e como agrupar por período/dia.
// Tudo no fuso de Brasília (o dia do comercial é o dia de São Paulo, não o do navegador).
import { CADENCIA, ROTULO_ATIVIDADE } from '../../domain/catalogo';
import { atividadeAtrasada } from '../../domain/regras';
import type { Atividade, TipoAtividade } from '../../domain/types';

export const ABAS_AGENDA = ['hoje', 'atrasadas', 'proximas', 'concluidas'] as const;
export type AbaAgenda = (typeof ABAS_AGENDA)[number];

const FUSO = 'America/Sao_Paulo';

/** 'YYYY-MM-DD' do dia em Brasília. */
export function diaSP(v: string | Date): string {
  return new Date(v).toLocaleDateString('en-CA', { timeZone: FUSO });
}

/** Hora (0–23) em Brasília. */
export function horaSP(v: string | Date): number {
  return Number(new Date(v).toLocaleString('en-US', { timeZone: FUSO, hour: 'numeric', hour12: false })) % 24;
}

/** Diferença em dias entre dois 'YYYY-MM-DD' (b − a). */
export function difDias(a: string, b: string): number {
  const t = (s: string) => { const [y, m, d] = s.split('-').map(Number); return Date.UTC(y, m - 1, d); };
  return Math.round((t(b) - t(a)) / 86400000);
}

export type Periodo = 'manha' | 'tarde' | 'noite';
export const ROTULO_PERIODO: Record<Periodo, string> = { manha: 'Manhã', tarde: 'Tarde', noite: 'Noite' };

export function periodoDaHora(h: number): Periodo {
  if (h < 12) return 'manha';
  if (h < 18) return 'tarde';
  return 'noite';
}

/** Em que aba a atividade aparece. "Hoje" inclui as atrasadas (no topo), para ninguém esquecer delas. */
export function naAba(a: Atividade, aba: AbaAgenda, agora: Date): boolean {
  if (aba === 'concluidas') return !!a.concluidaEm;
  if (a.concluidaEm) return false;
  const hoje = diaSP(agora);
  const dia = diaSP(a.venceEm);
  if (aba === 'atrasadas') return atividadeAtrasada(a, agora);
  if (aba === 'hoje') return dia <= hoje;
  return dia > hoje;
}

/** Rótulo de um dia relativo a hoje: "Hoje", "Amanhã", "Ontem" ou a data por extenso. */
export function rotuloDia(dia: string, hoje: string): string {
  const d = difDias(hoje, dia);
  if (d === 0) return 'Hoje';
  if (d === 1) return 'Amanhã';
  if (d === -1) return 'Ontem';
  const [y, m, dd] = dia.split('-').map(Number);
  const txt = new Date(y, m - 1, dd).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  return d < 0 ? `${txt} · há ${-d} dias` : txt;
}

export interface GrupoAgenda {
  key: string;
  titulo: string;
  atrasado: boolean;
  itens: Atividade[];
}

/**
 * Agrupa a aba. Hoje: Atrasadas, Manhã, Tarde, Noite. Atrasadas e Próximas: por dia (mais antigo primeiro).
 * Concluídas: por dia de conclusão (mais recente primeiro).
 */
export function agruparAgenda(atividades: Atividade[], aba: AbaAgenda, agora: Date): GrupoAgenda[] {
  const hoje = diaSP(agora);
  const lista = atividades.filter((a) => naAba(a, aba, agora));

  if (aba === 'hoje') {
    const ordem = [...lista].sort((a, b) => a.venceEm.localeCompare(b.venceEm));
    const atrasadas = ordem.filter((a) => atividadeAtrasada(a, agora));
    const resto = ordem.filter((a) => !atividadeAtrasada(a, agora));
    const grupos: GrupoAgenda[] = [{ key: 'atrasadas', titulo: 'Atrasadas', atrasado: true, itens: atrasadas }];
    (['manha', 'tarde', 'noite'] as Periodo[]).forEach((p) => {
      grupos.push({ key: p, titulo: ROTULO_PERIODO[p], atrasado: false, itens: resto.filter((a) => periodoDaHora(horaSP(a.venceEm)) === p) });
    });
    return grupos.filter((g) => g.itens.length);
  }

  const concluidas = aba === 'concluidas';
  const dataDe = (a: Atividade) => (concluidas ? a.concluidaEm ?? a.venceEm : a.venceEm);
  const ordem = [...lista].sort((a, b) => (concluidas ? dataDe(b).localeCompare(dataDe(a)) : dataDe(a).localeCompare(dataDe(b))));
  const grupos = new Map<string, GrupoAgenda>();
  for (const a of ordem) {
    const dia = diaSP(dataDe(a));
    if (!grupos.has(dia)) grupos.set(dia, { key: dia, titulo: rotuloDia(dia, hoje), atrasado: aba === 'atrasadas', itens: [] });
    grupos.get(dia)!.itens.push(a);
  }
  return [...grupos.values()];
}

export interface ContadoresAgenda {
  /** Abertas que vencem hoje e ainda estão no prazo. */
  hoje: number;
  atrasadas: number;
  concluidasHoje: number;
  /** Ligações feitas hoje. */
  ligacoesHoje: number;
  /** Ligações agendadas para hoje (feitas ou não). */
  ligacoesAgendadasHoje: number;
}

export function contadoresAgenda(atividades: Atividade[], agora: Date): ContadoresAgenda {
  const hoje = diaSP(agora);
  const deHoje = (iso: string | null) => !!iso && diaSP(iso) === hoje;
  return {
    hoje: atividades.filter((a) => !a.concluidaEm && deHoje(a.venceEm) && !atividadeAtrasada(a, agora)).length,
    atrasadas: atividades.filter((a) => atividadeAtrasada(a, agora)).length,
    concluidasHoje: atividades.filter((a) => deHoje(a.concluidaEm)).length,
    ligacoesHoje: atividades.filter((a) => a.tipo === 'ligacao' && deHoje(a.concluidaEm)).length,
    ligacoesAgendadasHoje: atividades.filter((a) => a.tipo === 'ligacao' && deHoje(a.venceEm)).length,
  };
}

/** Tempo passado desde `iso`, curto: "agora", "há 12 min", "há 3 h", "há 2 dias". */
export function tempoDesde(iso: string, agora: Date): string {
  const min = Math.floor((agora.getTime() - new Date(iso).getTime()) / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.floor(h / 24);
  return d === 1 ? 'há 1 dia' : `há ${d} dias`;
}

/** Toques de um dia da cadência numa linha: "Dia 2: Ligação + WhatsApp". */
export function toquesDoDia(dia: number): string | null {
  const d = CADENCIA.find((x) => x.dia === dia);
  if (!d) return null;
  return `Dia ${dia}: ${d.toques.map((t) => ROTULO_ATIVIDADE[t.tipo]).join(' + ')}`;
}

/** Resultados rápidos ao concluir um toque (um clique conclui). */
export const RESULTADOS_RAPIDOS = ['Respondeu', 'Não atendeu', 'Pediu retorno', 'Caixa postal'] as const;

/** 'YYYY-MM-DDTHH:mm' de amanhã às 10h no relógio do navegador (formato do input datetime-local). */
export function amanhaAs10(agora: Date): string {
  const d = new Date(agora);
  d.setDate(d.getDate() + 1);
  const p = (x: number) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T10:00`;
}

export interface SugestaoProximoPasso {
  tipo: TipoAtividade;
  titulo: string;
  /** Dia da cadência da sugestão, quando ela segue a cadência. */
  cadenciaDia: number | null;
}

/**
 * Próximo passo sugerido depois de concluir uma atividade (o vendedor pode trocar tudo).
 * Pediu retorno: mesmo canal. Respondeu: ligação para avançar. Sem resposta: segue a cadência
 * (primeiro toque do dia seguinte) ou alterna ligação e WhatsApp fora dela.
 */
export function sugestaoProximoPasso(a: Pick<Atividade, 'tipo' | 'cadenciaDia'>, resultado: string): SugestaoProximoPasso {
  if (resultado === 'Pediu retorno') return { tipo: a.tipo, titulo: 'Retorno combinado com o lead', cadenciaDia: null };
  if (resultado === 'Respondeu') return { tipo: 'ligacao', titulo: 'Dar sequência à conversa', cadenciaDia: null };
  const prox = a.cadenciaDia ? CADENCIA.find((d) => d.dia === a.cadenciaDia! + 1) : undefined;
  if (prox) return { tipo: prox.toques[0].tipo, titulo: `${prox.toques[0].titulo} (dia ${prox.dia} da cadência)`, cadenciaDia: prox.dia };
  return { tipo: a.tipo === 'ligacao' ? 'whatsapp' : 'ligacao', titulo: 'Nova tentativa de contato', cadenciaDia: null };
}
