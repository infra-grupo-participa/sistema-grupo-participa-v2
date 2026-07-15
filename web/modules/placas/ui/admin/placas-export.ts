'use client';

// Exportação Excel do relatório de placas — colunas/ordem/formato idênticos ao legado
// (relatorios.html → exportarXLSX): 14 colunas, aba "Solicitações de Placas",
// arquivo placas-solicitacoes-YYYY-MM-DD.xlsx.
//
// A planilha espelha a lista exibida: o recorte vem da tela (gaveta + filtros + busca +
// ordenação) e é exportado como está, sem descartar linhas por elegibilidade.

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import type { Solicitacao } from '../../domain/types';

const HEADERS = [
  'QR-CODE',
  'Ano de ingresso',
  'Nome',
  'E-mail',
  'Nível',
  'CPF/CNPJ',
  'CEP',
  'Logradouro',
  'Número',
  'Complemento',
  'Bairro',
  'Cidade',
  'Estado',
  'Código de Envio',
] as const;

const digits = (v: unknown) => String(v ?? '').replace(/\D/g, '');
const normEmail = (v: unknown) => String(v ?? '').trim().toLowerCase();
const yearOf = (d: unknown) => {
  const s = String(d ?? '');
  return /^\d{4}/.test(s) ? s.slice(0, 4) : '';
};

/** Ano de ingresso = ano de thb_alunos.data_compra_importada, casado por aluno_id → email → documento. */
async function anoIngressoLookup(rows: Solicitacao[]): Promise<(s: Solicitacao) => string> {
  const byId = new Map<string, string>();
  const byEmail = new Map<string, string>();
  const byDoc = new Map<string, string>();
  const consume = (data: Array<Record<string, unknown>> | null) => {
    for (const a of data ?? []) {
      const y = yearOf(a.data_compra_importada);
      if (!y) continue;
      if (a.id) byId.set(String(a.id), y);
      const e = normEmail(a.email);
      if (e) byEmail.set(e, y);
      const dc = digits(a.documento);
      if (dc) byDoc.set(dc, y);
    }
  };

  const db = createBrowserSupabase();
  const ids = [...new Set(rows.map((r) => r.aluno_id).filter(Boolean))] as string[];
  const emails = [...new Set(rows.map((r) => normEmail(r.email)).filter(Boolean))];
  const cols = 'id,email,documento,data_compra_importada';
  if (ids.length) consume((await db.from('thb_alunos').select(cols).in('id', ids)).data as Array<Record<string, unknown>> | null);
  if (emails.length) consume((await db.from('thb_alunos').select(cols).in('email', emails)).data as Array<Record<string, unknown>> | null);

  return (s: Solicitacao) => {
    if (s.aluno_id && byId.has(s.aluno_id)) return byId.get(s.aluno_id)!;
    const e = normEmail(s.email);
    if (e && byEmail.has(e)) return byEmail.get(e)!;
    const dc = digits(s.documento_nf);
    if (dc && byDoc.has(dc)) return byDoc.get(dc)!;
    return '';
  };
}

function nivelCol(nivel: string | null): string {
  if (!nivel) return '—';
  return nivelLabel(nivel) || nivel;
}

function buildRows(rows: Solicitacao[], anoDe: (s: Solicitacao) => string): string[][] {
  return rows.map((s) => [
    '', // QR-CODE (preenchido manualmente depois)
    anoDe(s), // Ano de ingresso
    s.nome ?? '',
    s.email ?? '',
    nivelCol(s.nivel),
    s.documento_nf ?? '', // CPF/CNPJ — valor bruto (sem máscara), como no legado
    s.cep ?? '', // CEP — valor bruto
    s.logradouro ?? '',
    s.numero ?? '',
    s.complemento ?? '',
    s.bairro ?? '',
    s.cidade ?? '',
    s.estado_uf ?? '',
    '', // Código de Envio (preenchido manualmente depois)
  ]);
}

const nomeArquivo = () => `placas-solicitacoes-${new Date().toISOString().slice(0, 10)}.xlsx`;

/**
 * Exporta a lista visível (gaveta + filtros + busca + ordenação já aplicados na tela) para
 * .xlsx idêntico ao legado. Retorna a quantidade de linhas exportadas.
 */
export async function exportarExcelPlacas(rows: Solicitacao[]): Promise<number> {
  if (!rows.length) return 0;

  const anoDe = await anoIngressoLookup(rows);
  const body = buildRows(rows, anoDe);
  const aoa: unknown[][] = [HEADERS.slice(), ...body];

  const XLSX = await import('xlsx');
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  // Largura automática das colunas: max(header, maior valor) + 4 (paridade legado).
  ws['!cols'] = HEADERS.map((h, i) => {
    let max = h.length;
    for (const r of body) max = Math.max(max, String(r[i] ?? '').length);
    return { wch: max + 4 };
  });
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Solicitações de Placas');
  XLSX.writeFile(wb, nomeArquivo());
  return rows.length;
}
