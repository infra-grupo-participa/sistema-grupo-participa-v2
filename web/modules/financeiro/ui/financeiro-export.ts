'use client';

// Exportação Excel do contas a receber — mesma lib e estilo de placas-export.ts.
// A planilha espelha a lista exibida: o recorte vem da tela (gaveta + filtros +
// busca + ordenação) e sai como está, colunas na ordem da tabela + extras úteis.

import type { ContaReceber } from '../domain/types';
import { mascararDoc, statusLabel } from '../domain/financeiro';
import { fmtData } from '@/shared/ui/format';

const HEADERS = [
  'Nome',
  'E-mail',
  'Telefone',
  'Canal',
  'Sinal (bruto)',
  'Sinal (líquido)',
  'Sinal pago em',
  'Saldo a pagar',
  'Saldo pago (bruto)',
  'Saldo pago (líquido)',
  'Lançamentos do saldo',
  'Saldo pago em',
  'Vencimento',
  'Dias em atraso',
  'Status',
  'Documento',
  'Turma',
  'Pacote',
  'Crédito',
  'Oferta (código)',
  'Oferta (valor)',
  'Oferta (link)',
  'Motivo de cancelamento',
] as const;

// Datas formatadas; dinheiro como número cru — o financeiro soma/filtra no Excel.
function buildRows(rows: ContaReceber[], canVerDoc: boolean): (string | number)[][] {
  return rows.map((c) => [
    c.nome ?? '',
    c.email ?? '',
    c.telefone ?? '',
    c.canal ?? '',
    c.sinal_bruto ?? '',
    c.sinal_liquido ?? '',
    c.sinal_pago_em ? fmtData(c.sinal_pago_em) : '',
    c.saldo_a_pagar ?? '',
    c.saldo_pago_bruto ?? 0,
    c.saldo_pago_liquido ?? 0,
    c.saldo_lancamentos ?? 0,
    c.saldo_pago_em ? fmtData(c.saldo_pago_em) : '',
    c.vencimento ? fmtData(c.vencimento) : '',
    c.dias_atraso ?? '',
    statusLabel(c.status_financeiro),
    mascararDoc(c.documento, canVerDoc),
    c.turma ?? '',
    c.pacote ?? '',
    c.credito ?? '',
    c.oferta_codigo ?? '',
    c.oferta_valor ?? '',
    c.oferta_link ?? '',
    c.cancelamento_motivo ?? '',
  ]);
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '') || 'todas';
const nomeArquivo = (turma: string | null) =>
  `financeiro-${slug(turma ?? 'todas')}-${new Date().toISOString().slice(0, 10)}.xlsx`;

/**
 * Exporta a lista visível (gaveta + filtros + busca + ordenação já aplicados na
 * tela) para .xlsx. Retorna a quantidade de linhas exportadas.
 */
export async function exportarExcelFinanceiro(rows: ContaReceber[], turma: string | null, canVerDoc: boolean): Promise<number> {
  if (!rows.length) return 0;

  const body = buildRows(rows, canVerDoc);
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
  XLSX.utils.book_append_sheet(wb, ws, 'Contas a Receber');
  XLSX.writeFile(wb, nomeArquivo(turma));
  return rows.length;
}
