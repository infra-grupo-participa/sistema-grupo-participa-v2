// Exportação da lista filtrada de alunos (CSV e Excel compartilham as colunas).

import { type Aluno360, ESPACO_LABEL, SITUACAO } from '../domain/aluno-360';
import { nivelLabel } from '@/shared/domain/nivel-resultado';

const EXPORT_COLS: [string, (a: Aluno360) => unknown][] = [
  ['Nome', (a) => a.nome],
  ['E-mail', (a) => a.email],
  ['Telefone', (a) => a.telefone],
  ['Documento', (a) => a.documento],
  ['Profissão', (a) => a.profissao],
  ['Nível', (a) => nivelLabel(a.nivel_resultado)],
  ['Espaço de instrução', (a) => ESPACO_LABEL[a.espaco_instrucao || ''] || ''],
  ['Turma THB', (a) => a.turma_codigo],
  ['Turma Aurum', (a) => a.turma_aurum_codigo],
  ['Cidade', (a) => a.cidade],
  ['Estado', (a) => a.estado],
  ['Papel', (a) => (a.eh_socio ? 'Sócio' : 'Titular')],
  ['Situação de acesso', (a) => (a.situacao_acesso ? SITUACAO[a.situacao_acesso]?.label || a.situacao_acesso : '')],
  ['Vencimento', (a) => a.data_expiracao],
  ['HT', (a) => (a.tem_ht ? 'Sim' : '')],
  ['HM', (a) => (a.tem_hm ? 'Sim' : '')],
  ['Placa', (a) => (a.tem_placa ? 'Sim' : '')],
  ['Depoimento', (a) => (a.tem_depoimento ? 'Sim' : '')],
  ['SIP', (a) => (a.sip_registrado ? 'Sim' : '')],
];

const nomeExport = (ext: string) => `alunos-${new Date().toISOString().slice(0, 10)}.${ext}`;

/** Exporta a lista filtrada para Excel (.xlsx) — SheetJS via import dinâmico. */
export async function exportarExcelAlunos(rows: Aluno360[]) {
  const XLSX = await import('xlsx');
  const aoa: unknown[][] = [EXPORT_COLS.map((c) => c[0]), ...rows.map((a) => EXPORT_COLS.map((c) => { const v = c[1](a); return v == null ? '' : v; }))];
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Alunos');
  XLSX.writeFile(wb, nomeExport('xlsx'));
}

/** Exporta a lista filtrada para CSV (separador ';' + BOM UTF-8 → abre no Excel). */
export function exportarCsvAlunos(rows: Aluno360[]) {
  const esc = (v: unknown) => {
    const s = v == null ? '' : String(v);
    return /[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [EXPORT_COLS.map((c) => c[0]).join(';'), ...rows.map((a) => EXPORT_COLS.map((c) => esc(c[1](a))).join(';'))].join('\r\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = nomeExport('csv');
  link.click();
  URL.revokeObjectURL(url);
}
