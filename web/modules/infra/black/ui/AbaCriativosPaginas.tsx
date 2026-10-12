'use client';

// Aba 3, Criativos e páginas (aprovada em 12/10). Trilha Campanha › Conjunto › Criativo › Página; cada clique em
// qualquer painel vira chip e refiltra os outros (cada painel vê os filtros dos outros, o próprio só destaca).
// O filtro mora na URL (recorte.criativos), então o link volta igual.
import { useMemo } from 'react';
import { SectionCard } from '@/shared/ui/components';
import { painel, type ItemPainel, type PainelCriativos } from '../domain/criativos';
import { taxa } from '../domain/metricas';
import type { FiltroCriativos } from '../domain/tipos';
import type { AlvoGaveta, DadosTela } from './contexto';
import { GaleriaCriativos } from './GaleriaCriativos';
import { Farol, formatar, moeda, Numero, Taxa } from './pecas';
import { TrilhaFiltro } from './TrilhaFiltro';

export function AbaCriativosPaginas({ d, gaveta }: { d: DadosTela; gaveta?: AlvoGaveta | null }) {
  const f = d.recorte.criativos;
  const nomePagina = (id: string) => d.paginas.get(id)?.rotulo ?? id;
  const paineis = useMemo(() => {
    const p = (q: PainelCriativos) => painel(q, f, d.dias, d.linhas, d.idx, d.config.reguaCpl, (id) => d.paginas.get(id)?.rotulo ?? id);
    return { campanha: p('campanha'), conjunto: p('conjunto'), anuncio: p('anuncio'), pagina: p('pagina') };
  }, [f, d.dias, d.linhas, d.idx, d.config.reguaCpl, d.paginas]);

  const alternar = (k: keyof FiltroCriativos, id: string) => d.irPara({ criativos: { ...f, [k]: f[k] === id ? undefined : id } });
  const tirar = (k: keyof FiltroCriativos) => d.irPara({ criativos: { ...f, [k]: undefined } });
  const nome = (k: keyof FiltroCriativos, id: string) => {
    if (k === 'campanha') return d.idx.campanha.get(id)?.nome ?? id;
    if (k === 'conjunto') return d.idx.conjunto.get(id)?.nome ?? id;
    if (k === 'anuncio') return d.idx.anuncio.get(id)?.nome ?? id;
    return nomePagina(id);
  };
  const abrirCriativo = (id: string) => {
    d.irPara({ criativos: { ...f, anuncio: id } });
    d.abrirGaveta({ tipo: 'criativo', id });
  };

  return (
    <div className="space-y-4">
      <TrilhaFiltro filtro={f} nome={nome} onTirar={tirar} onLimpar={() => d.irPara({ criativos: {} })} />
      <div className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="Campanhas" subtitle="Investimento, CPL com farol e leads pagos. Clique para filtrar.">
          <Barras itens={paineis.campanha} selecionado={f.campanha ?? null} onSelect={(id) => alternar('campanha', id)} />
        </SectionCard>
        <SectionCard title="Conjuntos" subtitle="Nome exato do gerenciador. Clique para filtrar.">
          <Barras itens={paineis.conjunto} selecionado={f.conjunto ?? null} onSelect={(id) => alternar('conjunto', id)} />
        </SectionCard>
      </div>
      <SectionCard title="Criativos" subtitle="Clique para abrir o detalhe (miniatura, mini-funil, curva diária e links).">
        <GaleriaCriativos itens={paineis.anuncio} anuncio={(id) => d.idx.anuncio.get(id)} selecionado={f.anuncio ?? null}
          ativo={gaveta?.tipo === 'criativo' ? gaveta.id : null} onAbrir={abrirCriativo} />
      </SectionCard>
      <SectionCard title="Páginas" subtitle="Um cartão por página de destino. Clique para filtrar os criativos que levam a ela.">
        {paineis.pagina.length === 0 && <p className="text-sm text-[var(--fg-3)]">Nenhuma página com veiculação neste recorte (o C1 não tem página).</p>}
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {paineis.pagina.map((it) => {
            const p = d.paginas.get(it.id); const r = it.resumo; const sel = f.pagina === it.id;
            return (
              <li key={it.id} className="atm-historico-card min-w-0">
                <button type="button" aria-pressed={sel} onClick={() => alternar('pagina', it.id)}
                  className={'atm-historico-interativo block w-full rounded-[var(--r-lg)] border bg-[var(--surface-2)] p-3 text-left ' + (sel ? 'border-[var(--accent)]' : 'border-[var(--border)] hover:border-[var(--border-accent)]')}>
                  <span className="block break-words text-sm font-semibold text-[var(--fg)]">{it.nome}</span>
                  {p && <span className="block break-all text-[11px] text-[var(--fg-3)]">{p.url}</span>}
                  <span className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
                    <Par r="Views da página"><Numero valor={r.lpv} formato="int" falta="view da página" animado={false} /></Par>
                    <Par r="Inscrições pagas"><Numero valor={r.leadsPagos} formato="int" animado={false} /></Par>
                    <Par r="Conversão da página"><Taxa taxa={taxa(r.leadsPagos, r.lpv)} /></Par>
                    <Par r="Connect rate"><Taxa taxa={r.connect} /></Par>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      </SectionCard>
    </div>
  );
}

function Par({ r, children }: { r: string; children: React.ReactNode }) {
  return <span className="flex min-w-0 flex-col"><span className="truncate text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{r}</span><span className="text-[var(--fg)]">{children}</span></span>;
}

/** Barras horizontais (não tabela): investimento na barra, CPL com farol e leads pagos ao lado. */
function Barras({ itens, selecionado, onSelect }: { itens: ItemPainel[]; selecionado: string | null; onSelect: (id: string) => void }) {
  if (itens.length === 0) return <p className="text-sm text-[var(--fg-3)]">Nada veiculado neste recorte.</p>;
  const max = Math.max(1, ...itens.map((i) => i.resumo.gasto));
  return (
    <ul className="space-y-2">
      {itens.map((it) => {
        const r = it.resumo; const sel = selecionado === it.id; const apagado = selecionado !== null && !sel;
        return (
          <li key={it.id}>
            <button type="button" aria-pressed={sel} onClick={() => onSelect(it.id)}
              className={'atm-historico-interativo block w-full rounded-[var(--r-sm)] text-left ' + (apagado ? 'opacity-50' : '')}>
              <span className="flex flex-wrap items-baseline justify-between gap-x-3 text-xs">
                <span className={'min-w-0 break-words ' + (sel ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]')}>{it.nome}</span>
                <span className="inline-flex shrink-0 items-center gap-2 tabular">
                  <span className="text-[var(--fg)]">{moeda(r.gasto)}</span>
                  {r.distribuicao
                    ? <span className="text-[var(--fg-3)]" title="Custo por visualização (ThruPlay)">C/vis. {formatar(r.custoVisualizacao, 'brl')}</span>
                    : <span className="inline-flex items-center gap-1 text-[var(--fg-2)]">CPL {formatar(r.cpl, 'brl')} <Farol farol={r.farol} /></span>}
                  {!r.distribuicao && <span className="text-[var(--fg-3)]">{formatar(r.leadsPagos, 'int')} leads</span>}
                </span>
              </span>
              <span className="mt-0.5 block h-1.5 overflow-hidden rounded-full bg-[var(--surface-4)]">
                <span className="atm-historico-barra block h-full rounded-full" style={{ width: `${(r.gasto / max) * 100}%`, background: sel ? 'var(--accent)' : 'var(--cyan)' }} />
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
