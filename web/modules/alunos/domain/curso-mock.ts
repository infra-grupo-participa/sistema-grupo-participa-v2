// Desempenho do aluno no curso — DEMONSTRAÇÃO DE LAYOUT (tudo zerado).
// Não há integração real de progresso de curso ainda; por decisão de produto,
// nada é inventado: todos os indicadores ficam em zero/vazio só para mostrar
// como a aba vai ficar. Substituir por fonte real quando a integração existir.

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

/**
 * Demonstração zerada — sem dados reais nem inventados. Todos os indicadores
 * em zero/vazio; só os nomes dos módulos aparecem para ilustrar o layout.
 */
export function cursoDesempenhoMock(): CursoDesempenhoMock {
  const modulos: CursoModulo[] = MODULOS.map((nome) => ({ nome, progresso: 0, concluido: false }));
  return {
    progressoGeral: 0,
    modulosConcluidos: 0,
    modulosTotal: MODULOS.length,
    aulasAssistidas: 0,
    aulasTotal: 0,
    ultimoAcessoDias: 0,
    engajamento: 'baixo',
    modulos,
  };
}
