'use client';

// Campanha × conjunto lado a lado (auditoria do Victor, 12/10): campanhas à esquerda; clicar numa campanha mostra
// os conjuntos dela à direita. Gasto, CPL e leads pagos em destaque em cada cartão (no C1, distribuição, o CPL dá
// lugar ao custo por visualização e os leads às impressões). Nada de uma tabela empilhada por nível.
// O clique continua sendo o filtro cruzado da aba (mora na URL): trocar de campanha limpa o conjunto escolhido.
import type { ReactNode } from 'react';
import type { ItemPainel } from '../domain/criativos';
import { Farol, formatar, moeda } from './pecas';

export function CampanhaConjunto({ campanhas, conjuntos, campanha, conjunto, nomeCampanha, onCampanha, onConjunto }: {
  campanhas: ItemPainel[]; conjuntos: ItemPainel[]; campanha: string | null; conjunto: string | null;
  nomeCampanha: (id: string) => string; onCampanha: (id: string) => void; onConjunto: (id: string) => void;
}) {
  const maxCampanha = Math.max(1, ...campanhas.map((i) => i.resumo.gasto));
  const maxConjunto = Math.max(1, ...conjuntos.map((i) => i.resumo.gasto));
  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
      <section aria-labelledby="black-cc-campanhas" className="min-w-0">
        <h3 id="black-cc-campanhas" className="text-sm font-semibold text-[var(--fg)]">Campanhas</h3>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Clique numa campanha para ver os conjuntos dela ao lado.</p>
        {campanhas.length === 0
          ? <p className="text-sm text-[var(--fg-3)]">Nada veiculado neste recorte.</p>
          : (
            <ul className="space-y-2">
              {campanhas.map((it, i) => (
                <li key={it.id}>
                  <Cartao it={it} sel={campanha === it.id} apagado={campanha !== null && campanha !== it.id} max={maxCampanha} i={i}
                    onClick={() => onCampanha(it.id)} rotulo={campanha === it.id ? 'Campanha escolhida. Clique de novo para tirar.' : 'Ver os conjuntos desta campanha'} />
                </li>
              ))}
            </ul>
          )}
      </section>

      <section aria-labelledby="black-cc-conjuntos" aria-live="polite" className="min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
        <h3 id="black-cc-conjuntos" className="break-words text-sm font-semibold text-[var(--fg)]">
          {campanha ? <>Conjuntos de <span className="text-[var(--accent)]">{nomeCampanha(campanha)}</span></> : 'Conjuntos'}
        </h3>
        {!campanha ? (
          <p className="mt-2 text-sm text-[var(--fg-3)]">Escolha uma campanha à esquerda: os conjuntos dela aparecem aqui, com gasto, CPL e leads.</p>
        ) : conjuntos.length === 0 ? (
          <p className="mt-2 text-sm text-[var(--fg-3)]">Nenhum conjunto desta campanha veiculou neste recorte.</p>
        ) : (
          <>
            <p className="mb-2 text-xs text-[var(--fg-3)]">Nome exato do gerenciador. Clique num conjunto para filtrar os criativos abaixo.</p>
            <ul className="grid gap-2 xl:grid-cols-2">
              {conjuntos.map((it, i) => (
                <li key={it.id} className="min-w-0">
                  <Cartao it={it} sel={conjunto === it.id} apagado={conjunto !== null && conjunto !== it.id} max={maxConjunto} i={i}
                    onClick={() => onConjunto(it.id)} rotulo={conjunto === it.id ? 'Conjunto escolhido. Clique de novo para tirar.' : 'Filtrar os criativos por este conjunto'} />
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
    </div>
  );
}

function Cartao({ it, sel, apagado, max, i, onClick, rotulo }: {
  it: ItemPainel; sel: boolean; apagado: boolean; max: number; i: number; onClick: () => void; rotulo: string;
}) {
  const r = it.resumo;
  return (
    <button type="button" aria-pressed={sel} title={rotulo} onClick={onClick} style={{ animationDelay: `${Math.min(i, 8) * 40}ms` }}
      className={'atm-historico-card atm-historico-interativo block w-full rounded-[var(--r-lg)] border bg-[var(--surface-2)] p-3 text-left '
        + (sel ? 'border-[var(--accent)] ' : 'border-[var(--border)] hover:border-[var(--border-accent)] ') + (apagado ? 'opacity-60' : '')}>
      <span className={'block break-words text-xs ' + (sel ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]')}>{it.nome}</span>
      <span className="mt-2 grid grid-cols-3 gap-2">
        <Destaque r="Gasto">{moeda(r.gasto)}</Destaque>
        {r.distribuicao
          ? <Destaque r="Custo por visualização" dica="Distribuição (C1): não gera lead, não tem CPL. Gasto ÷ ThruPlay.">{formatar(r.custoVisualizacao, 'brl')}</Destaque>
          : <Destaque r="CPL" dica="Gasto ÷ leads pagos do mesmo recorte.">
              <span className="inline-flex items-center gap-1.5">{formatar(r.cpl, 'brl')} <Farol farol={r.farol} /></span>
            </Destaque>}
        {r.distribuicao
          ? <Destaque r="Impressões">{formatar(r.impressoes, 'int')}</Destaque>
          : <Destaque r="Leads pagos">{formatar(r.leadsPagos, 'int')}</Destaque>}
      </span>
      <span className="mt-2 block h-1.5 overflow-hidden rounded-full bg-[var(--surface-4)]" aria-hidden="true">
        <span className="atm-historico-barra block h-full rounded-full" style={{ width: `${(r.gasto / max) * 100}%`, background: sel ? 'var(--accent)' : 'var(--cyan)' }} />
      </span>
    </button>
  );
}

function Destaque({ r, dica, children }: { r: string; dica?: string; children: ReactNode }) {
  return (
    <span className="flex min-w-0 flex-col" title={dica}>
      <span className="truncate text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{r}</span>
      <span className="tabular text-base font-bold leading-tight text-[var(--fg)]">{children}</span>
    </span>
  );
}
