'use client';

// Peças só da base de contatos: flags da pessoa, dono da linha e o popover de filtros.
// O resto (FaixaNumeros, Aviso, Campo, Vazio, Pessoa…) vem de comum.tsx.
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Contato } from '../../domain/types';
import { Dono, Sinal } from '../comum';

/** Duplicado / opt-out / aluno como ícones após o nome: altura de linha fixa, texto para leitor de tela. */
export function FlagsContato({ duplicado, optOut, aluno }: { duplicado: boolean; optOut: boolean; aluno: boolean }) {
  if (!duplicado && !optOut && !aluno) return null;
  return (
    <>
      {duplicado && <Sinal icone="alert" rotulo="Possível duplicado: outro contato tem o mesmo final de telefone" />}
      {optOut && <Sinal icone="lock" tom="danger" rotulo="Não quer contato: lista de bloqueio, fora de disparos e abordagens" />}
      {aluno && <Sinal icone="graduation" rotulo="Já é aluno" />}
    </>
  );
}

/**
 * Dono da linha. "Sem dono" é vermelho (meta zero), menos em opt-out: ali o cadeado já é o vermelho
 * da linha e ninguém vai abordar mesmo.
 */
export function DonoLinha({ c, nomeDe, className = '' }: {
  c: Pick<Contato, 'donoId' | 'optOut'>; nomeDe: (id: string | null) => string; className?: string;
}) {
  if (!c.donoId && c.optOut) return <span className={`block truncate text-sm text-[var(--fg-3)] ${className}`}>Sem dono</span>;
  return <div className={`truncate ${className}`}><Dono id={c.donoId} nomeDe={nomeDe} /></div>;
}

/** Botão "Filtros (n)" com painel suspenso; fecha no clique fora e no Esc (sem fechar a página de trás). */
export function PopoverFiltros({ ativos, children }: { ativos: number; children: React.ReactNode }) {
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const botao = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.stopPropagation();
      setAberto(false);
      botao.current?.focus();
    };
    document.addEventListener('mousedown', fora);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc); };
  }, [aberto]);
  return (
    <div ref={ref} className="relative">
      <Button
        ref={botao}
        type="button"
        variant="ghost"
        aria-expanded={aberto}
        aria-haspopup="dialog"
        onClick={() => setAberto((a) => !a)}
        className={ativos ? '!border-[var(--border-strong)] !text-[var(--fg)]' : ''}
      >
        <Icon name="sliders" size={14} /> Filtros{ativos ? <span className="tabular">({ativos})</span> : null}
      </Button>
      {aberto && (
        <div
          role="dialog"
          aria-label="Filtros"
          className="absolute right-0 z-30 mt-1 w-[min(320px,calc(100vw-32px))] space-y-4 rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-4 shadow-[var(--shadow-lg)]"
        >
          {children}
        </div>
      )}
    </div>
  );
}
