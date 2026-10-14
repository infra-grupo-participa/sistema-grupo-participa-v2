'use client';

// Aba 3, Criativos e páginas (aprovada em 12/10). Trilha Campanha › Conjunto › Criativo › Página; cada clique em
// qualquer painel vira chip e refiltra os outros (cada painel vê os filtros dos outros, o próprio só destaca).
// O filtro mora na URL (recorte.criativos), então o link volta igual. Campanha × conjunto lado a lado
// (`CampanhaConjunto`), paginados de 10 em 10. Clicar num conjunto filtra TUDO, inclusive a lista de campanhas, que
// passa a mostrar só a campanha dele (Victor, 13/10/2026). Sem campanha escolhida, a de conjuntos mostra todos os do
// recorte. Cada painel continua vendo os filtros dos outros e só destaca o seu próprio.
import { useMemo } from 'react';
import { SectionCard } from '@/shared/ui/components';
import { idDoCriativo, painel, type PainelCriativos } from '../domain/criativos';
import type { FiltroCriativos } from '../domain/tipos';
import { CampanhaConjunto } from './CampanhaConjunto';
import type { AlvoGaveta, DadosTela } from './contexto';
import { GaleriaCriativos } from './GaleriaCriativos';
import { Numero, Taxa } from './pecas';
import { TrilhaFiltro } from './TrilhaFiltro';

export function AbaCriativosPaginas({ d, gaveta }: { d: DadosTela; gaveta?: AlvoGaveta | null }) {
  const f = d.recorte.criativos;
  const nomePagina = (id: string) => d.paginas.get(id)?.rotulo ?? id;
  const paineis = useMemo(() => {
    const p = (q: PainelCriativos, filtro = f) => painel(q, filtro, d.dias, d.linhas, d.idx, d.config.reguaCpl, (id) => d.paginas.get(id)?.rotulo ?? id);
    return { campanha: p('campanha'), conjunto: p('conjunto'), anuncio: p('anuncio'), pagina: p('pagina') };
  }, [f, d.dias, d.linhas, d.idx, d.config.reguaCpl, d.paginas]);

  const alternar = (k: keyof FiltroCriativos, id: string) => d.irPara({ criativos: { ...f, [k]: f[k] === id ? undefined : id } });
  const tirar = (k: keyof FiltroCriativos) => d.irPara({ criativos: { ...f, [k]: undefined, ...(k === 'campanha' ? { conjunto: undefined } : {}) } });
  // Trocar (ou tirar) a campanha limpa o conjunto: o conjunto escolhido é filho da campanha anterior.
  const escolherCampanha = (id: string) => d.irPara({ criativos: { ...f, campanha: f.campanha === id ? undefined : id, conjunto: undefined } });
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
      <SectionCard title="Campanhas e conjuntos" subtitle="Gasto, CPL com o farol da régua e leads pagos do período, 10 por página. Clique na campanha para ver só os conjuntos dela.">
        <CampanhaConjunto campanhas={paineis.campanha} conjuntos={paineis.conjunto} campanha={f.campanha ?? null} conjunto={f.conjunto ?? null}
          chaveFiltro={[d.recorte.funil, d.recorte.canal, d.recorte.periodo, f.conjunto ?? '', f.anuncio ?? '', f.pagina ?? ''].join('|')}
          nomeCampanha={(id) => d.idx.campanha.get(id)?.nome ?? id}
          campanhaDoConjunto={(id) => { const c = d.idx.conjunto.get(id); return c ? d.idx.campanha.get(c.campanhaId)?.nome ?? null : null; }}
          onCampanha={escolherCampanha} onConjunto={(id) => alternar('conjunto', id)} />
      </SectionCard>
      <SectionCard title="Criativos" subtitle="Clique para abrir o detalhe (miniatura, funil, curva diária e links).">
        <GaleriaCriativos itens={paineis.anuncio} anuncio={(id) => d.idx.anuncio.get(id)} selecionado={f.anuncio ? idDoCriativo(d.idx, f.anuncio) : null}
          ativo={gaveta?.tipo === 'criativo' ? gaveta.id : null} onAbrir={abrirCriativo} />
      </SectionCard>
      <SectionCard title="Páginas" subtitle="Origem da página vem dos leads pagos atribuídos a cada anúncio. Clique para filtrar os criativos relacionados.">
        {paineis.pagina.length === 0 && <p className="text-sm text-[var(--fg-3)]">Página não medida: sem lead pago com origem de página neste recorte. O C1 não tem página de conversão.</p>}
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
                    <Par r="Conversão da página"><Taxa taxa={r.conversao} /></Par>
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
