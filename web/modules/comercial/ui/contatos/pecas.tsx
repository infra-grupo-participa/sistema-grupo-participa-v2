'use client';

// Peças só da base de contatos: flags da pessoa, dono da linha e o popover de filtros.
// O resto (FaixaNumeros, Aviso, Campo, Vazio, Pessoa…) vem de comum.tsx.
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_CANAL, SELO_CANAL, nomeProjeto, type OrigemContato } from '../../domain/catalogacao';
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
          className="gp-pop-in origin-top-right absolute right-0 z-30 mt-1 w-[min(320px,calc(100vw-32px))] space-y-4 rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-4 shadow-[var(--highlight-surface),var(--shadow-lg)]"
        >
          {children}
        </div>
      )}
    </div>
  );
}

/**
 * Origem da linha: selo do canal de entrada + projeto (ou "sem projeto", com a linha do produto quando há compra).
 * Sem catalogação (banco sem a 20261007141044): traço.
 */
export function OrigemLinha({ origem, compacta = false, className = '' }: {
  origem: OrigemContato | null | undefined; compacta?: boolean; className?: string;
}) {
  if (!origem) return <span className={`block text-sm text-[var(--fg-3)] ${className}`}>—</span>;
  const projeto = origem.projeto ? nomeProjeto(origem.projeto, origem.projetoNome) : null;
  const semProjeto = origem.linha ? `${origem.linha.toUpperCase()}, sem projeto` : 'Sem projeto';
  const title = `Entrou por ${ROTULO_CANAL[origem.canal]}${projeto ? ` · ${projeto}` : ` · ${semProjeto}`}${origem.projeto ? ` (${origem.projeto})` : ''}`;
  return (
    <span className={`flex min-w-0 items-center gap-1.5 ${compacta ? 'text-xs' : 'text-sm'} ${className}`} title={title}>
      <span className="shrink-0 rounded-[var(--r-sm)] border border-[var(--border)] px-1.5 text-[11px] leading-5 text-[var(--fg-2)]">
        {SELO_CANAL[origem.canal]}
      </span>
      <span className={`truncate ${projeto ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>{projeto ?? semProjeto}</span>
    </span>
  );
}
