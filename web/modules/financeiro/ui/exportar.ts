'use client';

// Export XLSX (SheetJS por CDN, `await import('xlsx')` — mesmo padrão do
// export legado) a partir do dataset neutro de montar-relatorio.ts. O PDF não
// mora aqui: é o documento com protocolo de ui/pdf/documentos.ts + shared/ui/pdf
// (o antigo exportarPDF() = window.print() foi removido em 28/09/2026).
import type { DatasetRelatorio } from '../application/montar-relatorio';
import { fmtBRLc, fmtData } from '@/shared/ui/format';

function valorParaExport(coluna: DatasetRelatorio['colunas'][number], valor: string | number | null): string | number {
  if (valor == null) return '';
  if (coluna.tipo === 'data' && typeof valor === 'string') return fmtData(valor);
  return valor;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '') || 'todas';
const nomeArquivo = (turma: string | null) =>
  `financeiro-board-${slug(turma ?? 'todas')}-${new Date().toISOString().slice(0, 10)}.xlsx`;

/** Exporta o dataset neutro (já filtrado/selecionado pela tela) para .xlsx.
 *  Datas formatadas pt-BR; dinheiro cru em número — o financeiro soma/filtra
 *  no Excel (mesmo padrão do export legado). Retorna a quantidade exportada. */
export async function exportarXLSX(dataset: DatasetRelatorio, turma: string | null): Promise<number> {
  if (!dataset.linhas.length) return 0;

  const headers = dataset.colunas.map((c) => c.label);
  const body = dataset.linhas.map((linha) =>
    dataset.colunas.map((c) => valorParaExport(c, linha.valores[c.key])),
  );
  const aoa: unknown[][] = [headers, ...body];

  const XLSX = await import('xlsx');
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws['!cols'] = headers.map((h, i) => {
    let max = h.length;
    for (const r of body) max = Math.max(max, String(r[i] ?? '').length);
    return { wch: max + 4 };
  });
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Financeiro');
  XLSX.writeFile(wb, nomeArquivo(turma));
  return dataset.linhas.length;
}

/** Formata uma célula do dataset para exibição em tela/impressão (fmtBRLc/fmtData). */
export function formatarCelulaTela(coluna: DatasetRelatorio['colunas'][number], valor: string | number | null): string {
  if (valor == null || valor === '') return '—';
  if (coluna.tipo === 'moeda' && typeof valor === 'number') return fmtBRLc(valor);
  if (coluna.tipo === 'data' && typeof valor === 'string') return fmtData(valor);
  return String(valor);
}
