'use client';

// Galeria de criativos: cartão com miniatura e, sobre ela, investimento, CTR e CPL (no C1, custo por
// visualização) com o farol da régua do Caio. Ordem por chips. Clicar abre a gaveta do criativo.
// Auditoria de 12/10: a ordem existia, mas não se via (CTR com uma casa decimal deixava quase todos em "1,1%" e
// o topo era o mesmo em três ordens). Agora cada cartão mostra a posição e o valor que a ordem usa, em destaque,
// e o CTR sai com duas casas.
import { useState } from 'react';
import { ORDENS_GALERIA, ROTULO_ORDEM, ordenar, valorOrdem, type ItemPainel, type OrdemGaleria } from '../domain/criativos';
import type { Anuncio, Valor } from '../domain/tipos';
import { MiniaturaFicticia } from './MiniaturaFicticia';
import { Chip, Farol, formatar, moeda } from './pecas';

const CTR2 = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const ctrTexto = (v: Valor) => (v === null ? 'Sem dado' : `${CTR2.format(v * 100)}%`);
const NOME_VALOR: Record<OrdemGaleria, string> = { leads: 'Leads pagos', cpl: 'CPL', ctr: 'CTR', gasto: 'Gasto' };
const EXPLICA: Record<OrdemGaleria, string> = {
  leads: 'do maior para o menor número de leads pagos; criativo de distribuição (C1) vai para o fim',
  cpl: 'do menor para o maior CPL; criativo sem CPL (distribuição, C1) vai para o fim',
  ctr: 'do maior para o menor CTR (cliques no link ÷ impressões); sem clique medido vai para o fim',
  gasto: 'do maior para o menor investimento no período',
};

function textoValor(ordem: OrdemGaleria, v: Valor): string {
  if (ordem === 'ctr') return ctrTexto(v);
  if (ordem === 'leads') return formatar(v, 'int');
  return formatar(v, 'brl');
}

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
      <p className="text-xs text-[var(--fg-3)]" aria-live="polite">Ordem: {EXPLICA[ordem]}.</p>
      {lista.length === 0 && <p className="text-sm text-[var(--fg-3)]">Nenhum criativo veiculado neste recorte.</p>}
      <ol className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {lista.map((it, pos) => {
          const a = anuncio(it.id); const r = it.resumo;
          const apagado = selecionado !== null && selecionado !== it.id;
          const v = valorOrdem(it, ordem);
          return (
            <li key={it.id} className="atm-historico-card min-w-0">
              <button type="button" onClick={() => onAbrir(it.id)} aria-pressed={ativo === it.id}
                className={'atm-historico-interativo block w-full overflow-hidden rounded-[var(--r-lg)] border bg-[var(--surface-2)] text-left '
                  + (ativo === it.id ? 'border-[var(--accent)] ' : 'border-[var(--border)] hover:border-[var(--border-accent)] ') + (apagado ? 'opacity-50' : '')}>
                <span className="relative block">
                  <MiniaturaFicticia id={it.id} formato={a?.formato ?? null} className="rounded-none" />
                  <span className="absolute left-2 top-2 inline-flex items-center gap-1.5 rounded-full bg-[var(--scrim)] px-2 py-0.5 text-[11px] font-semibold text-[var(--fg)]">
                    <span className="tabular">{pos + 1}º</span>
                    <span className="text-[var(--fg-2)]">{NOME_VALOR[ordem]}</span>
                    <span className={'tabular ' + (v === null ? 'text-[var(--fg-3)]' : 'text-[var(--accent)]')}>{v === null ? 'Sem dado' : textoValor(ordem, v)}</span>
                  </span>
                  <span className="absolute inset-x-0 bottom-0 flex flex-wrap items-center gap-x-3 gap-y-0.5 bg-[var(--scrim)] px-2 py-1 text-[11px] text-[var(--fg)]">
                    <span className="tabular">{moeda(r.gasto)}</span>
                    <span className="tabular" title="CTR: cliques no link ÷ impressões">CTR {ctrTexto(r.ctr.valor)}</span>
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
      </ol>
    </div>
  );
}
