'use client';

// Galeria de criativos: cartão com miniatura e, sobre ela, investimento, CTR e CPL (no C1, custo por
// visualização) com o farol da régua do Caio. Ordem por chips. Clicar abre a gaveta do criativo.
// Auditoria de 12/10: a ordem existia, mas não se via (CTR com uma casa decimal deixava quase todos em "1,1%" e
// o topo era o mesmo em três ordens). Agora cada cartão mostra a posição e o valor que a ordem usa, em destaque,
// e o CTR sai com duas casas.
// Miniatura: a real (URL assinada do bucket trafego-miniaturas, validada por safeHttpUrl) no mesmo quadro 16:10 da
// fictícia; sem ela (demonstração, sem acesso, coleta sem imagem), a fictícia de antes.
import { useState } from 'react';
import { safeHttpUrl } from '@/shared/domain/url-segura';
import { ORDENS_GALERIA, ROTULO_ORDEM, ordenar, valorOrdem, type ItemPainel, type OrdemGaleria } from '../domain/criativos';
import type { Anuncio, Valor } from '../domain/tipos';
import { MiniaturaFicticia } from './MiniaturaFicticia';
import { Farol, formatar, moeda } from './pecas';

const CTR2 = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const ctrTexto = (v: Valor) => (v === null ? 'Sem dado' : `${CTR2.format(v * 100)}%`);
const NOME_VALOR: Record<OrdemGaleria, string> = { leads: 'Leads pagos', cpl: 'CPL', ctr: 'CTR', gasto: 'Gasto', mql: '% MQL' };
const EXPLICA: Record<OrdemGaleria, string> = {
  leads: 'do maior para o menor número de leads pagos; criativo de distribuição (C1) vai para o fim',
  cpl: 'do menor para o maior CPL; criativo sem CPL (distribuição, C1) vai para o fim',
  ctr: 'do maior para o menor CTR (cliques no link ÷ impressões); sem clique medido vai para o fim',
  gasto: 'do maior para o menor investimento no período',
  mql: 'da maior para a menor proporção de pessoas MQL entre os cadastros do criativo',
};

function textoValor(ordem: OrdemGaleria, v: Valor): string {
  if (ordem === 'ctr') return ctrTexto(v);
  if (ordem === 'mql') return v === null ? 'Sem dado' : `${(v * 100).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
  if (ordem === 'leads') return formatar(v, 'int');
  return formatar(v, 'brl');
}

export function GaleriaCriativos({ itens, anuncio, selecionado, ativo, onAbrir }: {
  itens: ItemPainel[]; anuncio: (id: string) => Anuncio | undefined; selecionado: string | null; ativo: string | null; onAbrir: (id: string) => void;
}) {
  const [ordem, setOrdem] = useState<OrdemGaleria>('leads');
  const [ordenacaoAberta, setOrdenacaoAberta] = useState(false);
  const lista = ordenar(itens, ordem);
  return (
    <div className="space-y-3">
      <div className="relative">
        <button type="button" aria-haspopup="listbox" aria-expanded={ordenacaoAberta} onClick={() => setOrdenacaoAberta((v) => !v)}
          className="min-h-10 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 text-sm font-semibold text-[var(--fg)] hover:border-[var(--border-accent)]">
          Ordenar: {ROTULO_ORDEM[ordem]} <span aria-hidden="true" className="ml-1">{ordenacaoAberta ? '▴' : '▾'}</span>
        </button>
        {ordenacaoAberta && <div role="listbox" aria-label="Ordenar criativos" className="absolute left-0 top-full z-20 mt-1 min-w-56 overflow-hidden rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-1 shadow-[var(--shadow-overlay)]">
          {ORDENS_GALERIA.map((o) => <button key={o} type="button" role="option" aria-selected={ordem === o} onClick={() => { setOrdem(o); setOrdenacaoAberta(false); }}
            className={'block min-h-10 w-full rounded-[var(--r-sm)] px-3 text-left text-sm ' + (ordem === o ? 'bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]')}>
            {ROTULO_ORDEM[o]}
          </button>)}
        </div>}
      </div>
      <p className="text-xs text-[var(--fg-3)]" aria-live="polite">Ordem: {EXPLICA[ordem]}.</p>
      {lista.length === 0 && <p className="text-sm text-[var(--fg-3)]">Nenhum criativo veiculado neste recorte.</p>}
      <ol className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {lista.map((it, pos) => {
          const a = anuncio(it.id); const r = it.resumo;
          const apagado = selecionado !== null && selecionado !== it.id;
          const v = valorOrdem(it, ordem);
          const mqlSemPosicao = ordem === 'mql' && (r.leadsPagos < 5 || v === null);
          const miniatura = safeHttpUrl(a?.miniaturaUrl);
          return (
            <li key={it.id} className="atm-historico-card min-w-0">
              <button type="button" onClick={() => onAbrir(it.id)} aria-pressed={ativo === it.id}
                className={'atm-historico-interativo block w-full overflow-hidden rounded-[var(--r-lg)] border bg-[var(--surface-2)] text-left '
                  + (ativo === it.id ? 'border-[var(--accent)] ' : 'border-[var(--border)] hover:border-[var(--border-accent)] ') + (apagado ? 'opacity-50' : '')}>
                <span className="relative block">
                  {miniatura
                    // eslint-disable-next-line @next/next/no-img-element -- URL assinada do Storage, já validada por safeHttpUrl
                    ? <img src={miniatura} alt={`Miniatura de ${it.nome}`} loading="lazy" className="block aspect-[8/5] w-full object-cover" />
                    : <MiniaturaFicticia id={it.id} formato={a?.formato ?? null} className="rounded-none" />}
                  <span className="absolute left-2 top-2 inline-flex items-center gap-1.5 rounded-full border border-[var(--border)] bg-[var(--surface-1)] px-2 py-0.5 text-[11px] font-bold text-[var(--fg)] shadow-[var(--shadow-sm)]">
                    <span className="tabular">{mqlSemPosicao ? '—' : `${pos + 1}º`}</span>
                    <span className="text-[var(--fg)]">{NOME_VALOR[ordem]}</span>
                    <span className="tabular text-[var(--fg)]">
                      {ordem === 'mql' && r.leadsPagos < 5 ? 'menos de 5 leads' : v === null ? 'Sem dado' : textoValor(ordem, v)}
                    </span>
                  </span>
                  <span className="absolute inset-x-0 bottom-0 flex flex-wrap items-center gap-x-3 gap-y-0.5 border-t border-[var(--border)] bg-[var(--surface-1)] px-2 py-1 text-[11px] font-medium text-[var(--fg)] shadow-[var(--shadow-sm)]">
                    <span className="tabular">{moeda(r.gasto)}</span>
                    <span className="tabular" title="CTR: cliques no link ÷ impressões">CTR {ctrTexto(r.ctr.valor)}</span>
                    {r.distribuicao
                      ? <span className="tabular" title="Custo por visualização (ThruPlay)">C/vis. {formatar(r.custoVisualizacao, 'brl')}</span>
                      : <span className="inline-flex items-center gap-1 tabular">CPL {formatar(r.cpl, 'brl')} <Farol farol={r.farol} /></span>}
                  </span>
                </span>
                <span className="block border-t border-[var(--border)] bg-[var(--surface-1)] p-3">
                  <span className="block break-words text-sm font-bold leading-snug text-[var(--fg)]">{it.nome}</span>
                  <span className="mt-1 block text-xs text-[var(--fg-2)]">
                    {r.distribuicao ? `${formatar(r.impressoes, 'int')} impressões` : <><strong className="font-bold text-[var(--fg)]">{formatar(r.leadsPagos, 'int')} leads pagos</strong><span className="text-[var(--fg-2)]"> · {formatar(r.leads, 'int')} cadastros</span></>}
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
