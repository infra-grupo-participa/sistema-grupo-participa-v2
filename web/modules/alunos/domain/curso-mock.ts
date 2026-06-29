// Desempenho do aluno no curso — DADOS ILUSTRATIVOS (MOCK).
// Não há integração real de progresso de curso; estes números são gerados de
// forma determinística a partir do id do aluno só para validar o layout da aba.
// Substituir por fonte real quando a integração existir.

export interface CursoModulo {
  nome: string;
  progresso: number; // 0–100
  concluido: boolean;
}

export interface CursoDesempenhoMock {
  progressoGeral: number; // 0–100
  modulosConcluidos: number;
  modulosTotal: number;
  aulasAssistidas: number;
  aulasTotal: number;
  ultimoAcessoDias: number; // há quantos dias
  engajamento: 'alto' | 'médio' | 'baixo';
  modulos: CursoModulo[];
}

const MODULOS = [
  'Fundamentos da Holding',
  'Estruturação Societária',
  'Planejamento Tributário',
  'Proteção Patrimonial',
  'Sucessão Familiar',
  'Casos Práticos',
];

/** Hash estável (FNV-1a) do id → semente determinística. */
function seed(id: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < id.length; i++) {
    h ^= id.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0) / 0xffffffff;
}

export function cursoDesempenhoMock(alunoId: string): CursoDesempenhoMock {
  const s = seed(alunoId);
  const modulos: CursoModulo[] = MODULOS.map((nome, i) => {
    const r = ((s * (i + 7)) % 1 + 1) % 1; // 0–1 estável por módulo
    const progresso = Math.min(100, Math.round(r * 120));
    return { nome, progresso, concluido: progresso >= 100 };
  });
  const modulosConcluidos = modulos.filter((m) => m.concluido).length;
  const progressoGeral = Math.round(modulos.reduce((a, m) => a + m.progresso, 0) / modulos.length);
  const aulasTotal = 48;
  const aulasAssistidas = Math.round((progressoGeral / 100) * aulasTotal);
  const ultimoAcessoDias = Math.round(s * 45);
  const engajamento = progressoGeral >= 66 ? 'alto' : progressoGeral >= 33 ? 'médio' : 'baixo';
  return { progressoGeral, modulosConcluidos, modulosTotal: MODULOS.length, aulasAssistidas, aulasTotal, ultimoAcessoDias, engajamento, modulos };
}
