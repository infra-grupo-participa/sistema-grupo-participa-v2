'use client';

// Galeria de criativos: cartão com miniatura e, sobre ela, investimento, CTR e CPL (no C1, custo por
// visualização) com o farol da régua do Caio. Ordem por chips. Clicar abre a gaveta do criativo.
import { useState } from 'react';
import { ORDENS_GALERIA, ROTULO_ORDEM, ordenar, type ItemPainel, type OrdemGaleria } from '../domain/criativos';
import type { Anuncio } from '../domain/tipos';
import { MiniaturaFicticia } from './MiniaturaFicticia';
import { Chip, Farol, formatar, moeda, pct } from './pecas';

export function GaleriaCriativos({ itens, anuncio, selecionado, ativo, onAbrir }: {
  itens: ItemPainel[]; anuncio: (id: string) => Anuncio | undefined; selecionado: string | null; ativo: string | null; onAbrir: (id: string) => void;
}) {
  const [ordem, setOrdem] = useState<OrdemGaleria>('leads');
  const lista = ordenar(itens, ordem);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Ordenar criativos">
        {ORDENS_GALERIA.map((o) => <Chip key={o} ativo={ordem === o} onClick={() => setOrdem(o)}>{ROTULO_ORDEM[o]}</Chip>)}
      </div>
      {lista.length === 0 && <p className="text-sm text-[var(--fg-3)]">Nenhum criativo veiculado neste recorte.</p>}
      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {lista.map((it) => {
          const a = anuncio(it.id); const r = it.resumo;
          const apagado = selecionado !== null && selecionado !== it.id;
          return (
            <li key={it.id} className="atm-historico-card min-w-0">
              <button type="button" onClick={() => onAbrir(it.id)} aria-pressed={ativo === it.id}
                className={'atm-historico-interativo block w-full overflow-hidden rounded-[var(--r-lg)] border bg-[var(--surface-2)] text-left '
                  + (ativo === it.id ? 'border-[var(--accent)] ' : 'border-[var(--border)] hover:border-[var(--border-accent)] ') + (apagado ? 'opacity-50' : '')}>
                <span className="relative block">
                  <MiniaturaFicticia id={it.id} formato={a?.formato ?? null} className="rounded-none" />
                  <span className="absolute inset-x-0 bottom-0 flex flex-wrap items-center gap-x-3 gap-y-0.5 bg-[var(--scrim)] px-2 py-1 text-[11px] text-[var(--fg)]">
                    <span className="tabular">{moeda(r.gasto)}</span>
                    <span className="tabular" title="CTR">CTR {pct(r.ctr.valor)}</span>
                    {r.distribuicao
                      ? <span className="tabular" title="Custo por visualização (ThruPlay)">C/vis. {formatar(r.custoVisualizacao, 'brl')}</span>
                      : <span className="inline-flex items-center gap-1 tabular">CPL {formatar(r.cpl, 'brl')} <Farol farol={r.farol} /></span>}
                  </span>
                </span>
                <span className="block p-2.5">
                  <span className="block break-words text-xs font-semibold text-[var(--fg)]">{it.nome}</span>
                  <span className="mt-1 block text-[11px] text-[var(--fg-3)]">
                    {r.distribuicao ? `${formatar(r.impressoes, 'int')} impressões` : `${formatar(r.leadsPagos, 'int')} leads pagos · ${formatar(r.leads, 'int')} cadastros`}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
