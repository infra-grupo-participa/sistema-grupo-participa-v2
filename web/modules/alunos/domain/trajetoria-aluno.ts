// Trajetória do aluno (fn_aluno_trajetoria, fase 1 — 30/09/2026): tudo o que aconteceu com a pessoa no THB,
// numa linha só, separada por dimensão. Contrato fixo da RPC; o back-end é de outro executor.

export const DIMENSOES_TRAJETORIA = ['vinculo', 'compras', 'eventos', 'turma', 'socios', 'grupos', 'atendimento'] as const;
export type DimensaoTrajetoria = (typeof DIMENSOES_TRAJETORIA)[number];

export const ROTULO_DIMENSAO: Record<DimensaoTrajetoria, string> = {
  vinculo: 'Vínculo',
  compras: 'Compras',
  eventos: 'Eventos',
  turma: 'Turma',
  socios: 'Sócios',
  grupos: 'Grupos',
  atendimento: 'Atendimento',
};

export interface LinhaTrajetoriaAluno {
  dia: string; // 'YYYY-MM-DD'
  momento: string | null;
  dimensao: DimensaoTrajetoria;
  tipo: string;
  titulo: string;
  detalhe: string | null;
  /** null para quem está fora do financeiro — nesse caso a tela não mostra nada. */
  valor: number | null;
  situacao: string | null;
  fonte: string;
  regra: string | null;
  ref: string | null;
}

/** Tipos que pedem atenção (badge de alerta) e o que é retorno (badge positivo). */
export const TIPOS_ALERTA = new Set(['saida', 'estorno', 'cancelamento']);
export const TIPO_VOLTA = 'volta';

/** Do mais recente para o mais antigo: dia desc, depois momento desc (sem momento vai por último no dia). Estável. */
export function ordenarTrajetoria(linhas: LinhaTrajetoriaAluno[]): LinhaTrajetoriaAluno[] {
  return linhas
    .map((l, i) => ({ l, i }))
    .sort((a, b) => {
      const d = b.l.dia.localeCompare(a.l.dia);
      if (d) return d;
      const ma = a.l.momento ?? '';
      const mb = b.l.momento ?? '';
      if (ma !== mb) return mb.localeCompare(ma);
      return a.i - b.i;
    })
    .map((x) => x.l);
}

export interface ResumoTrajetoriaAluno {
  /** Dia da 1ª linha 'entrada_thb'; sem ela, o dia da linha mais antiga. */
  entradaThb: string | null;
  /** true quando a entrada veio da 1ª linha, e não de um 'entrada_thb'. */
  entradaInferida: boolean;
  compras: number;
  saidas: number;
  voltas: number;
  eventos: number;
}

export function resumirTrajetoriaAluno(linhas: LinhaTrajetoriaAluno[]): ResumoTrajetoriaAluno {
  const cronologica = [...ordenarTrajetoria(linhas)].reverse();
  const entrada = cronologica.find((l) => l.tipo === 'entrada_thb');
  return {
    entradaThb: entrada?.dia ?? cronologica[0]?.dia ?? null,
    entradaInferida: !entrada && cronologica.length > 0,
    // Estorno/cancelamento na dimensão compras não é compra.
    compras: linhas.filter((l) => l.dimensao === 'compras' && !TIPOS_ALERTA.has(l.tipo)).length,
    saidas: linhas.filter((l) => l.tipo === 'saida').length,
    voltas: linhas.filter((l) => l.tipo === TIPO_VOLTA).length,
    eventos: linhas.filter((l) => l.dimensao === 'eventos').length,
  };
}

/** Normaliza o que vem da RPC (numeric pode chegar como string; valor null continua null). */
export function normalizarLinhas(brutas: unknown[]): LinhaTrajetoriaAluno[] {
  return (brutas as LinhaTrajetoriaAluno[]).map((l) => ({
    ...l,
    dia: String(l.dia).slice(0, 10),
    valor: l.valor == null ? null : Number(l.valor),
  }));
}
