'use client';

// Uma linha do registro: autor, ação, entidade, resumo, hora e as mudanças campo a campo (sob demanda).
import { useId, useState } from 'react';
import { AvatarInicial } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { LogCrm } from '../../domain/types';
import { ACAO, ENTIDADE, horaLog, nomeAutor } from './registro';

export function ItemLog({ l, nomeDe, compacto = false }: { l: LogCrm; nomeDe: (id: string | null) => string; compacto?: boolean }) {
  const [aberto, setAberto] = useState(false);
  const idDetalhe = useId();
  const autor = nomeAutor(l.autorId, nomeDe);
  const acao = ACAO[l.acao] ?? { verbo: l.acao, icone: 'circle' };
  const tamanho = compacto ? 24 : 28;

  return (
    <li className={`flex gap-3 ${compacto ? 'px-2 py-2' : 'px-3 py-2.5'}`}>
      {l.autorId == null ? (
        <span
          className="grid shrink-0 place-items-center rounded-full border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg-3)]"
          style={{ width: tamanho, height: tamanho }}
          title="Feito pelo sistema (integração ou rotina)"
        >
          <Icon name="server" size={compacto ? 12 : 14} />
        </span>
      ) : (
        <span className="shrink-0"><AvatarInicial nome={autor} size={tamanho} /></span>
      )}

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <span className="text-sm font-medium text-[var(--fg)] truncate max-w-full">{autor}</span>
          <span className="inline-flex items-center gap-1 text-xs text-[var(--fg-2)]">
            <Icon name={acao.icone} size={12} className="text-[var(--fg-3)]" />
            {acao.verbo}
          </span>
          <span className="text-xs text-[var(--fg-3)]">· {ENTIDADE[l.entidade] ?? l.entidade}</span>
          <time dateTime={l.em} className="ml-auto text-xs tabular text-[var(--fg-3)]">{horaLog(l.em)}</time>
        </div>
        <p className="mt-0.5 text-sm text-[var(--fg-2)] break-words">{l.resumo}</p>

        {l.mudancas.length > 0 && (
          <>
            <button
              type="button"
              onClick={() => setAberto((a) => !a)}
              aria-expanded={aberto}
              aria-controls={idDetalhe}
              className="mt-1 inline-flex items-center gap-1 text-xs text-[var(--fg-3)] hover:text-[var(--fg)] hover:underline"
            >
              <Icon name={aberto ? 'chevron-up' : 'chevron-down'} size={12} />
              {aberto ? 'Esconder detalhes' : `Ver detalhes (${l.mudancas.length} ${l.mudancas.length === 1 ? 'campo' : 'campos'})`}
            </button>
            {aberto && (
              <dl id={idDetalhe} className="mt-2 space-y-1.5 rounded-[var(--r-md)] border border-[var(--border-faint)] bg-[var(--surface-2)] px-3 py-2 text-xs">
                {l.mudancas.map((m, i) => (
                  <div key={`${m.campo}-${i}`} className="grid gap-x-3 gap-y-0.5 sm:grid-cols-[minmax(0,120px)_1fr]">
                    <dt className="font-medium text-[var(--fg-2)] truncate">{m.campo}</dt>
                    <dd className="flex flex-wrap items-center gap-x-1.5 min-w-0 text-[var(--fg)]">
                      {m.antes != null
                        ? <><span className="sr-only">antes:</span><s className="text-[var(--fg-3)] break-words">{m.antes}</s></>
                        : <span className="text-[var(--fg-3)]">vazio</span>}
                      <Icon name="arrow-right" size={12} className="shrink-0 text-[var(--fg-3)]" />
                      <span className="sr-only">depois:</span>
                      <span className="break-words">{m.depois ?? <span className="text-[var(--fg-3)]">vazio</span>}</span>
                    </dd>
                  </div>
                ))}
              </dl>
            )}
          </>
        )}
      </div>
    </li>
  );
}
