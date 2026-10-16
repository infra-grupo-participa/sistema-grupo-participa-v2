'use client';

import { Modal } from '@/shared/ui/components';
import { ehVazio } from '../domain/relatorio-miami';

/** Detalhe de uma linha de qualquer tabela da cópia: todas as colunas, com o cabeçalho exato da planilha. */
export function ModalLinhaRelatorio({ titulo, colunas, celulas, ocultar = [], onClose }: {
  titulo: string; colunas: string[]; celulas: string[]; ocultar?: string[]; onClose: () => void;
}) {
  const campos = colunas.map((coluna, k) => ({ coluna, valor: celulas[k] ?? '' })).filter((c) => !ocultar.includes(c.coluna));
  return <Modal onClose={onClose} title={celulas[0] ? celulas[0] : titulo} width="max-w-3xl">
    <p className="mb-4 text-xs text-[var(--fg-3)]">{titulo}</p>
    <dl className="grid gap-x-6 gap-y-4 sm:grid-cols-2">
      {campos.map(({ coluna, valor }) => <div key={coluna} className="min-w-0">
        <dt className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{coluna}</dt>
        <dd className={`mt-0.5 break-words text-sm ${ehVazio(valor) ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]'}`}>{valor.trim() === '' ? '—' : valor}</dd>
      </div>)}
    </dl>
  </Modal>;
}
