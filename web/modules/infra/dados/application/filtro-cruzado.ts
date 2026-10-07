export type CampoFiltro = 'comprou' | 'instrucao' | 'turma' | 'utm_source' | 'status_grupo' | 'estado' | 'entrou_grupo';
export type Filtro = { campo: CampoFiltro; valor: string };

export function rotuloFiltro(campo: CampoFiltro, valor: unknown): string {
  if (valor === null || valor === undefined || valor === '') {
    if (campo === 'instrucao' || campo === 'turma') return 'Não é aluno';
    if (campo === 'entrou_grupo') return 'Sem fonte';
    return 'Sem informação';
  }
  if (typeof valor === 'boolean') return valor ? 'Sim' : 'Não';
  return String(valor);
}
export function chaveFiltro(valor: unknown): string {
  return valor === null || valor === undefined ? '__null__' : String(valor);
}
export function aplicarFiltros<T extends object>(linhas: T[], filtros: Filtro[], excluir?: CampoFiltro): T[] {
  return linhas.filter((linha) => filtros.every(({ campo, valor }) => campo === excluir || chaveFiltro((linha as Record<string, unknown>)[campo]) === valor));
}
export function agrupar<T extends object>(linhas: T[], campo: CampoFiltro, filtros: Filtro[]) {
  const contagem = new Map<string, { valor: string; rotulo: string; quantidade: number }>();
  for (const linha of aplicarFiltros(linhas, filtros, campo)) {
    const raw = (linha as Record<string, unknown>)[campo];
    const valor = chaveFiltro(raw);
    const atual = contagem.get(valor);
    if (atual) atual.quantidade += 1;
    else contagem.set(valor, { valor, rotulo: rotuloFiltro(campo, raw), quantidade: 1 });
  }
  return [...contagem.values()].sort((a, b) => b.quantidade - a.quantidade || a.rotulo.localeCompare(b.rotulo, 'pt-BR'));
}
export function alternarFiltro(filtros: Filtro[], campo: CampoFiltro, valor: string): Filtro[] {
  const demais = filtros.filter((f) => f.campo !== campo);
  return filtros.some((f) => f.campo === campo && f.valor === valor) ? demais : [...demais, { campo, valor }];
}
