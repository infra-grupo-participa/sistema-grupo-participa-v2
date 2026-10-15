/*
 * Filtro cruzado dos gráficos do modal de pessoas (Ações da Black, 15/10/2026): clicar numa fatia filtra os outros
 * gráficos e a tabela; clicar de novo desfaz. Regras puras, sem tela. Cada campo guarda no máximo um valor; campos
 * diferentes se somam (E). O gráfico do próprio campo ignora o filtro dele mesmo, para a pessoa ver as outras opções
 * e trocar de valor sem limpar antes.
 */
import { diaEmSaoPaulo, type DiaSerieAtm } from './modal-pessoas';

export type FiltroGrafico = { campo: string; valor: string };
export type CampoFiltravel<T> = { nome: string; valor: (item: T) => string };

/** Clicou no valor: seleciona, troca o valor do mesmo campo ou, se já era esse, desfaz. */
export function alternarFiltroGrafico(filtros: readonly FiltroGrafico[], campo: string, valor: string): FiltroGrafico[] {
  const demais = filtros.filter((f) => f.campo !== campo);
  return filtros.some((f) => f.campo === campo && f.valor === valor) ? demais : [...demais, { campo, valor }];
}

export function removerFiltroGrafico(filtros: readonly FiltroGrafico[], campo: string): FiltroGrafico[] {
  return filtros.filter((f) => f.campo !== campo);
}

export function valorFiltrado(filtros: readonly FiltroGrafico[], campo: string): string | null {
  return filtros.find((f) => f.campo === campo)?.valor ?? null;
}

/** Itens que passam em todos os filtros. `excluir` = campo do gráfico que está sendo desenhado. Filtro de campo desconhecido não filtra. */
export function aplicarFiltrosGraficos<T>(itens: readonly T[], campos: readonly CampoFiltravel<T>[], filtros: readonly FiltroGrafico[], excluir?: string): T[] {
  const ativos = filtros.filter((f) => f.campo !== excluir).map((f) => ({ valor: f.valor, campo: campos.find((c) => c.nome === f.campo) })).filter((f) => f.campo);
  if (!ativos.length) return [...itens];
  return itens.filter((item) => ativos.every((f) => f.campo!.valor(item) === f.valor));
}

export type DiaAcumulado = DiaSerieAtm & { acumulado: number };

/** Acrescenta o total corrido (acumulado até o fim de cada dia) à série diária. */
export function acumularSerie(serie: readonly DiaSerieAtm[]): DiaAcumulado[] {
  let soma = 0;
  return serie.map((d) => { soma += d.quantidade; return { ...d, acumulado: soma }; });
}

function deslocar(dia: string, delta: number): string {
  const [a, m, d] = dia.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d + delta)).toISOString().slice(0, 10);
}

/**
 * Janela do eixo de datas da Evolução: do primeiro dia com lead (do conjunto SEM filtro, para o eixo não encolher
 * quando alguém filtra) até hoje, com no mínimo `minimoDias` dias terminando em hoje. Assim, com 1 ou 2 dias de dado,
 * o gráfico mostra a semana e não um ponto solto. Sem nenhuma data, devolve `null` (não inventa período).
 */
export function janelaDaEvolucao<T>(itens: readonly T[], dataDe: (item: T) => string | null, hoje: string, minimoDias = 7): { de: string; ate: string } | null {
  let primeiro: string | null = null;
  let ultimo: string | null = null;
  for (const item of itens) {
    const dia = diaEmSaoPaulo(dataDe(item));
    if (!dia) continue;
    if (primeiro === null || dia < primeiro) primeiro = dia;
    if (ultimo === null || dia > ultimo) ultimo = dia;
  }
  if (!primeiro || !ultimo) return null;
  const ate = ultimo > hoje ? ultimo : hoje;
  const maisCedo = deslocar(ate, -(minimoDias - 1));
  return { de: primeiro < maisCedo ? primeiro : maisCedo, ate };
}
