'use client';

// Exportação Excel do faturamento diário — mesma lib e estilo de financeiro-export.ts.
// A planilha espelha a tabela exibida (com acumulado), colunas na mesma ordem;
// dinheiro sai como número cru para o financeiro somar/filtrar no Excel.

import type { DiaComAcumulado } from '../domain/financeiro';
import { fmtData } from '@/shared/ui/format';

const HEADERS = [
  'Dia',
  'Lançamentos',
  'Bruto',
  'Líquido',
  'Taxas',
  'Sinal',
  'Saldo',
  'Mensalidade',
  'Compra cheia',
  'Acumulado',
  'Alunos',
] as const;

// Data formatada; dinheiro como número cru; categoria sem valor no dia → vazio.
function buildRows(rows: DiaComAcumulado[]): (string | number)[][] {
  return rows.map((d) => [
    fmtData(d.dia),
    d.lancamentos,
    d.bruto,
    d.liquido,
    d.taxas,
    d.sinal ?? '',
    d.saldo ?? '',
    d.mensalidade ?? '',
    d.compra_cheia ?? '',
    d.acumulado,
    d.alunos,
  ]);
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '') || 'todas';
const nomeArquivo = (turma: string | null) =>
  `faturamento-${slug(turma ?? 'todas')}-${new Date().toISOString().slice(0, 10)}.xlsx`;

/** Exporta os dias visíveis (com acumulado) para .xlsx. Retorna a quantidade de linhas. */
export async function exportarExcelFaturamento(rows: DiaComAcumulado[], turma: string | null): Promise<number> {
  if (!rows.length) return 0;

  const body = buildRows(rows);
  const aoa: unknown[][] = [HEADERS.slice(), ...body];

  const XLSX = await import('xlsx');
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  // Largura automática das colunas: max(header, maior valor) + 4 (paridade placas).
  ws['!cols'] = HEADERS.map((h, i) => {
    let max = h.length;
    for (const r of body) max = Math.max(max, String(r[i] ?? '').length);
    return { wch: max + 4 };
  });
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Faturamento Diário');
  XLSX.writeFile(wb, nomeArquivo(turma));
  return rows.length;
}
