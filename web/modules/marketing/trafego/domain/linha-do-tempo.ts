// Linha do tempo da vida do projeto: gasto diário (desempenho_dia) e as atividades do ClickUp no mesmo eixo de dias.
// Domínio puro. Dia da tarefa = conclusão, senão prazo, senão início, senão criação, no dia de São Paulo.
import type { DiaSerie, TarefaClickup } from './tipos';

export interface DiaLinha { dia: string; gasto: number | null; tarefas: TarefaClickup[] }

const DIA_MS = 86400000;
const soma = (ymd: string, n: number) => new Date(Date.parse(`${ymd}T12:00:00Z`) + n * DIA_MS).toISOString().slice(0, 10);

/** Dia (São Paulo) em que a tarefa entra na linha do tempo, e por quê. */
export function marcoDaTarefa(t: TarefaClickup): { dia: string; tipo: 'concluida' | 'prazo' | 'inicio' | 'criada' } | null {
  const pares: [string | null, 'concluida' | 'prazo' | 'inicio' | 'criada'][] = [
    [t.concluida_em, 'concluida'], [t.prazo, 'prazo'], [t.inicio, 'inicio'], [t.criada_em, 'criada'],
  ];
  for (const [v, tipo] of pares) {
    if (!v) continue;
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) continue;
    return { dia: d.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' }), tipo };
  }
  return null;
}

/**
 * Dias da linha do tempo: de quando começa o gasto ou a primeira tarefa até `ate` (ontem) ou o prazo mais adiante
 * (no máximo 14 dias à frente), limitado aos últimos `maxDias` dias. Dia sem gasto coletado = null (não zero).
 * `fora` = tarefas que caíram fora da janela.
 */
export function montarLinhaDoTempo(serie: DiaSerie[], tarefas: TarefaClickup[], ate: string, maxDias = 60) {
  const marcos = tarefas.map((t) => ({ t, m: marcoDaTarefa(t) })).filter((x) => x.m != null) as { t: TarefaClickup; m: NonNullable<ReturnType<typeof marcoDaTarefa>> }[];
  const datas = [...serie.map((s) => s.dia), ...marcos.map((x) => x.m.dia)].sort();
  if (datas.length === 0) return { dias: [] as DiaLinha[], maxGasto: 0, fora: tarefas.length };
  const limiteFuturo = soma(ate, 14);
  const fim = [ate, ...datas.filter((d) => d <= limiteFuturo)].sort().at(-1)!;
  const inicio = [datas[0], soma(fim, -(maxDias - 1))].sort().at(-1)!;
  const gasto = new Map(serie.map((s) => [s.dia, s.gasto]));
  const dias: DiaLinha[] = [];
  for (let d = inicio; d <= fim; d = soma(d, 1)) dias.push({ dia: d, gasto: gasto.get(d) ?? null, tarefas: [] });
  const idx = new Map(dias.map((d, i) => [d.dia, i]));
  let fora = tarefas.length - marcos.length;
  for (const { t, m } of marcos) {
    const i = idx.get(m.dia);
    if (i == null) fora++;
    else dias[i].tarefas.push(t);
  }
  return { dias, maxGasto: Math.max(0, ...dias.map((d) => d.gasto ?? 0)), fora };
}
