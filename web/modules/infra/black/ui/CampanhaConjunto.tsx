'use client';

// Campanha × conjunto lado a lado (auditoria do Victor, 12/10): campanhas à esquerda, conjuntos à direita, os dois
// com o MESMO cartão (gasto, CPL e leads pagos em destaque; no C1, distribuição, o CPL dá lugar ao custo por
// visualização e os leads às impressões). Sem campanha escolhida, a direita mostra os conjuntos de todas as
// campanhas do recorte; clicar numa campanha filtra para os conjuntos dela (clicar de novo tira).
// Cada lado pagina de 10 em 10 com a régua estilo Google ("‹ 1 2 3 4 5 ›"), sem rolagem lateral. Trocar filtro
// volta para a página 1 (a página guarda a chave do filtro em que foi escolhida; chave nova = página 1).
// O clique continua sendo o filtro cruzado da aba (mora na URL): trocar de campanha limpa o conjunto escolhido.
import { useState, type ReactNode } from 'react';
import type { ItemPainel } from '../domain/criativos';
import { paginar, paginasVisiveis, POR_PAGINA, type Pagina } from '../domain/paginacao';
import { Farol, formatar, moeda } from './pecas';

export function CampanhaConjunto({ campanhas, conjuntos, campanha, conjunto, chaveFiltro, nomeCampanha, campanhaDoConjunto, onCampanha, onConjunto }: {
  campanhas: ItemPainel[]; conjuntos: ItemPainel[]; campanha: string | null; conjunto: string | null;
  /** Assinatura do filtro vigente (período, funil, canal, criativo, página). Mudou = volta para a página 1. */
  chaveFiltro: string;
  nomeCampanha: (id: string) => string; campanhaDoConjunto: (id: string) => string | null;
  onCampanha: (id: string) => void; onConjunto: (id: string) => void;
}) {
  const pagCampanhas = usePagina(campanhas, chaveFiltro);
  const pagConjuntos = usePagina(conjuntos, `${chaveFiltro}|${campanha ?? ''}`);
  const maxCampanha = Math.max(1, ...campanhas.map((i) => i.resumo.gasto));
  const maxConjunto = Math.max(1, ...conjuntos.map((i) => i.resumo.gasto));
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <section aria-labelledby="black-cc-campanhas" className="min-w-0">
        <h3 id="black-cc-campanhas" className="text-sm font-semibold text-[var(--fg)]">Campanhas</h3>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Clique numa campanha para ver só os conjuntos dela ao lado.</p>
        {campanhas.length === 0
          ? <p className="text-sm text-[var(--fg-3)]">Nada veiculado neste recorte.</p>
          : (
            <>
              <ul className="space-y-2">
                {pagCampanhas.pagina.itens.map((it, i) => (
                  <li key={it.id}>
                    <Cartao it={it} sel={campanha === it.id} apagado={campanha !== null && campanha !== it.id} max={maxCampanha} i={i}
                      onClick={() => onCampanha(it.id)} rotulo={campanha === it.id ? 'Campanha escolhida. Clique de novo para tirar.' : 'Ver só os conjuntos desta campanha'} />
                  </li>
                ))}
              </ul>
              <Paginacao rotulo="Páginas das campanhas" pagina={pagCampanhas.pagina} onIr={pagCampanhas.ir} />
            </>
          )}
      </section>

      <section aria-labelledby="black-cc-conjuntos" aria-live="polite" className="min-w-0">
        <h3 id="black-cc-conjuntos" className="break-words text-sm font-semibold text-[var(--fg)]">
          {campanha ? <>Conjuntos de <span className="text-[var(--accent)]">{nomeCampanha(campanha)}</span></> : 'Conjuntos de todas as campanhas'}
        </h3>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Nome exato do gerenciador. Clique num conjunto para filtrar os criativos abaixo.</p>
        {conjuntos.length === 0 ? (
          <p className="text-sm text-[var(--fg-3)]">{campanha ? 'Nenhum conjunto desta campanha veiculou neste recorte.' : 'Nenhum conjunto veiculou neste recorte.'}</p>
        ) : (
          <>
            <ul className="space-y-2">
              {pagConjuntos.pagina.itens.map((it, i) => {
                const origem = campanha ? null : campanhaDoConjunto(it.id);
                const acao = conjunto === it.id ? 'Conjunto escolhido. Clique de novo para tirar.' : 'Filtrar os criativos por este conjunto';
                return (
                  <li key={it.id}>
                    <Cartao it={it} sel={conjunto === it.id} apagado={conjunto !== null && conjunto !== it.id} max={maxConjunto} i={i}
                      onClick={() => onConjunto(it.id)} rotulo={origem ? `${acao} Campanha: ${origem}` : acao} />
                  </li>
                );
              })}
            </ul>
            <Paginacao rotulo="Páginas dos conjuntos" pagina={pagConjuntos.pagina} onIr={pagConjuntos.ir} />
          </>
        )}
      </section>
    </div>
  );
}

/** Página atual de uma lista. A página escolhida vale só para a chave em que foi escolhida (chave nova = página 1). */
function usePagina<T>(itens: readonly T[], chave: string) {
  const [estado, setEstado] = useState<{ chave: string; n: number }>({ chave, n: 1 });
  const pagina = paginar(itens, estado.chave === chave ? estado.n : 1, POR_PAGINA);
  return { pagina, ir: (n: number) => setEstado({ chave, n }) };
}

function Paginacao<T>({ rotulo, pagina, onIr }: { rotulo: string; pagina: Pagina<T>; onIr: (n: number) => void }) {
  if (pagina.paginas <= 1) return null;
  const { pagina: atual, paginas, total } = pagina;
  const inicio = (atual - 1) * POR_PAGINA + 1; const fim = Math.min(total, atual * POR_PAGINA);
  const base = 'inline-flex min-h-9 min-w-9 items-center justify-center rounded-[var(--r-md)] border px-2 text-sm tabular transition-colors';
  const seta = (alvo: number, desligado: boolean, nome: string, simbolo: string) => (
    <button type="button" aria-label={nome} disabled={desligado} onClick={() => onIr(alvo)}
      className={base + (desligado ? ' cursor-not-allowed border-transparent text-[var(--fg-4)]' : ' border-transparent text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]')}>
      <span aria-hidden="true">{simbolo}</span>
    </button>
  );
  return (
    <nav aria-label={rotulo} className="mt-3 flex flex-col items-center gap-1">
      <ul className="flex flex-wrap items-center justify-center gap-1">
        <li>{seta(atual - 1, atual <= 1, 'Página anterior', '‹')}</li>
        {paginasVisiveis(atual, paginas).map((n) => (
          <li key={n}>
            <button type="button" aria-label={`Página ${n}`} aria-current={n === atual ? 'page' : undefined} onClick={() => onIr(n)}
              className={base + (n === atual
                ? ' border-[var(--accent)] bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]'
                : ' border-transparent text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]')}>
              {n}
            </button>
          </li>
        ))}
        <li>{seta(atual + 1, atual >= paginas, 'Próxima página', '›')}</li>
      </ul>
      <p className="text-[11px] text-[var(--fg-3)]">{`${inicio} a ${fim} de ${total}`}</p>
    </nav>
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
      <span className="mt-2 grid grid-cols-3 gap-2 max-sm:grid-cols-2">
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
      <span className="tabular text-base font-bold leading-tight text-[var(--fg)] max-md:break-words max-md:text-sm">{children}</span>
    </span>
  );
}
