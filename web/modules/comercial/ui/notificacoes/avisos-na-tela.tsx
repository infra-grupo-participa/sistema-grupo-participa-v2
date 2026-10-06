'use client';

// Aviso dentro da tela (canto inferior direito). Aparece sempre que chega notificação nova, com ou sem a
// permissão do navegador: no app do Claude e em navegador que bloqueou o aviso do sistema, é ele que avisa.
import Link from 'next/link';
import { useEffect, useSyncExternalStore } from 'react';
import { Icon } from '@/shared/ui/icons';

export interface AvisoTela { id: string; titulo: string; corpo: string; href?: string }

let fila: AvisoTela[] = [];
const ouvintes = new Set<() => void>();
const avisar = () => ouvintes.forEach((f) => f());
const DURACAO_MS = 9000;

export function mostrarAvisoNaTela(a: AvisoTela) {
  if (fila.some((x) => x.id === a.id)) return;
  fila = [...fila, a].slice(-4);
  avisar();
  setTimeout(() => fecharAviso(a.id), DURACAO_MS);
}

export function fecharAviso(id: string) {
  fila = fila.filter((x) => x.id !== id);
  avisar();
}

export function AvisosNaTela() {
  const itens = useSyncExternalStore(
    (cb) => { ouvintes.add(cb); return () => { ouvintes.delete(cb); }; },
    () => fila,
    () => fila,
  );
  // Esc fecha o mais recente.
  useEffect(() => {
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape' && fila.length) fecharAviso(fila[fila.length - 1].id); };
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, []);
  if (!itens.length) return null;
  return (
    <div aria-live="polite" className="fixed bottom-4 right-4 z-[1200] flex w-[min(360px,calc(100vw-32px))] flex-col gap-2">
      {itens.map((a) => {
        const corpo = (
          <>
            <span className="mt-0.5 grid place-items-center w-7 h-7 shrink-0 rounded-full bg-[var(--surface-3)] text-[var(--accent)]"><Icon name="alert" size={14} /></span>
            <span className="min-w-0 flex-1">
              <span className="block text-[13px] font-semibold text-[var(--fg)]">{a.titulo}</span>
              <span className="block text-xs text-[var(--fg-2)] line-clamp-2">{a.corpo}</span>
            </span>
          </>
        );
        return (
          <div key={a.id} role="status" className="gp-rise flex items-start gap-2 rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-3 shadow-[var(--shadow-lg)]">
            {a.href
              ? <Link href={a.href} onClick={() => fecharAviso(a.id)} className="flex flex-1 items-start gap-2.5 min-w-0">{corpo}</Link>
              : <span className="flex flex-1 items-start gap-2.5 min-w-0">{corpo}</span>}
            <button type="button" aria-label="Fechar aviso" onClick={() => fecharAviso(a.id)} className="grid place-items-center w-7 h-7 shrink-0 rounded-[var(--r-sm)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
              <Icon name="x" size={13} />
            </button>
          </div>
        );
      })}
    </div>
  );
}
