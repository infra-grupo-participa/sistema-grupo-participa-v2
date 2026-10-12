'use client';

// Gaveta do criativo: miniatura, caminho (campanha › conjunto › página, nomes exatos da fonte), mini-funil
// (impressões → cliques → views → leads pagos → grupo em 48h; no C1, impressões → vídeo 75%), curva diária e os
// três botões (Ver anúncio, Abrir no Gerenciador, Abrir página). Link só abre se for http(s) válido; no modo
// demonstração os botões ficam desabilitados.
import { useMemo } from 'react';
import { safeHttpUrl } from '@/shared/domain/url-segura';
import { resumir, serieDiariaAnuncio } from '../domain/criativos';
import { ingressoGrupo, taxa, type Taxa as TipoTaxa } from '../domain/metricas';
import type { Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { MiniaturaFicticia } from './MiniaturaFicticia';
import { Farol, formatar, moeda, Numero, Taxa } from './pecas';

const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export function GavetaCriativo({ d, id }: { d: DadosTela; id: string }) {
  const a = d.idx.anuncio.get(id);
  const dados = useMemo(() => {
    const dias = d.diasPeriodoSemFiltro.filter((x) => x.anuncioId === id);
    const linhas = d.linhasPeriodoSemFiltro.filter((l) => l.anuncioId === id);
    const c = d.idx.campanhaDoAnuncio(id);
    const distribuicao = c === null || c.funil === 'c1' || c.funil === null;
    return { dias, linhas, distribuicao, resumo: resumir(dias, linhas, d.idx, d.config.reguaCpl, distribuicao), serie: serieDiariaAnuncio(id, dias, linhas, d.diasPeriodo) };
  }, [d, id]);
  if (!a) return <p className="text-sm text-[var(--fg-3)]">Criativo não encontrado no catálogo.</p>;
  const cj = d.idx.conjunto.get(a.conjuntoId);
  const camp = cj ? d.idx.campanha.get(cj.campanhaId) : undefined;
  const pagina = a.paginaId ? d.paginas.get(a.paginaId) : undefined;
  const r = dados.resumo;
  const demo = d.fonte.modo === 'demonstracao';
  const miniatura = demo ? null : safeHttpUrl(a.miniaturaUrl);

  const etapas: { rotulo: string; valor: Valor; taxa?: TipoTaxa }[] = dados.distribuicao
    ? [
      { rotulo: 'Impressões', valor: r.impressoes },
      { rotulo: 'Vídeo 75%', valor: r.video75.num, taxa: r.video75 },
    ]
    : [
      { rotulo: 'Impressões', valor: r.impressoes },
      { rotulo: 'Cliques', valor: r.cliques, taxa: r.ctr },
      { rotulo: 'Views da página', valor: r.lpv, taxa: r.connect },
      { rotulo: 'Leads pagos', valor: r.leadsPagos, taxa: taxa(r.leadsPagos, r.lpv) },
      { rotulo: 'Grupo em 48h', valor: ingressoGrupo(dados.linhas, 48, d.agora).num, taxa: ingressoGrupo(dados.linhas, 48, d.agora) },
    ];
  const maxEtapa = Math.max(1, ...etapas.map((e) => e.valor ?? 0));

  return (
    <div className="space-y-4">
      <div className="mx-auto max-w-xs">
        {miniatura
          // eslint-disable-next-line @next/next/no-img-element -- miniatura externa do Meta, já validada por safeHttpUrl
          ? <img src={miniatura} alt={`Miniatura de ${a.nome}`} className="block w-full rounded-[var(--r-md)]" />
          : <MiniaturaFicticia id={a.id} formato={a.formato} />}
      </div>

      <dl className="space-y-1 text-xs">
        <div><dt className="inline text-[var(--fg-3)]">Campanha: </dt><dd className="inline break-words text-[var(--fg-2)]">{camp?.nome ?? 'Não informado'}</dd></div>
        <div><dt className="inline text-[var(--fg-3)]">Conjunto: </dt><dd className="inline break-words text-[var(--fg-2)]">{cj?.nome ?? 'Não informado'}</dd></div>
        <div><dt className="inline text-[var(--fg-3)]">Página: </dt><dd className="inline break-words text-[var(--fg-2)]">{pagina?.rotulo ?? 'Sem página (distribuição)'}</dd></div>
      </dl>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Mini r="Investimento"><Numero valor={dados.dias.length ? r.gasto : null} formato="brl" animado={false} /></Mini>
        <Mini r="CPM"><Numero valor={r.cpm} formato="brl" animado={false} /></Mini>
        {dados.distribuicao
          ? <Mini r="Custo por visualização"><Numero valor={r.custoVisualizacao} formato="brl" falta="ThruPlay" animado={false} /></Mini>
          : <Mini r="CPL"><span className="inline-flex items-center gap-1.5"><Numero valor={r.cpl} formato="brl" animado={false} /><Farol farol={r.farol} /></span></Mini>}
        <Mini r="CTR"><Taxa taxa={r.ctr} /></Mini>
      </div>

      <section aria-label="Mini-funil do criativo">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Mini-funil</h3>
        <ol className="space-y-1.5">
          {etapas.map((e, i) => (
            <li key={e.rotulo}>
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <span className="text-[var(--fg-2)]">{e.rotulo}</span>
                <span className="flex items-baseline gap-2">
                  {i > 0 && e.taxa && <span className="text-xs text-[var(--fg-3)]"><Taxa taxa={e.taxa} /></span>}
                  <Numero valor={e.valor} formato="int" animado={false} />
                </span>
              </div>
              <div className="mt-0.5 h-1.5 overflow-hidden rounded-full bg-[var(--surface-4)]">
                <div className="atm-historico-funil-bar h-full rounded-full bg-[var(--accent)]" style={{ width: e.valor ? `${(e.valor / maxEtapa) * 100}%` : '0%' }} />
              </div>
            </li>
          ))}
        </ol>
      </section>

      <CurvaDiaria serie={dados.serie} />

      <div className="flex flex-wrap gap-2">
        <Link rotulo="Ver anúncio" href={a.linkPrevia} demo={demo} />
        <Link rotulo="Abrir no Gerenciador" href={a.linkGerenciador} demo={demo} />
        <Link rotulo="Abrir página" href={pagina?.url ?? null} demo={demo} />
      </div>
    </div>
  );
}

function Mini({ r, children }: { r: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-2">
      <div className="truncate text-[10px] uppercase tracking-wide text-[var(--fg-3)]" title={r}>{r}</div>
      <div className="mt-0.5 text-sm font-semibold text-[var(--fg)]">{children}</div>
    </div>
  );
}

function Link({ rotulo, href, demo }: { rotulo: string; href: string | null; demo: boolean }) {
  const url = demo ? null : safeHttpUrl(href);
  const cls = 'inline-flex min-h-9 items-center rounded-[var(--r-md)] border px-3 text-xs';
  if (!url) {
    return <button type="button" disabled title={demo ? 'sem link (demonstração)' : 'sem link na fonte'} className={cls + ' cursor-not-allowed border-[var(--border)] text-[var(--fg-3)]'}>{rotulo}</button>;
  }
  return <a href={url} target="_blank" rel="noopener noreferrer" className={cls + ' border-[var(--border-accent)] text-[var(--fg)] hover:bg-[var(--surface-3)]'}>{rotulo}</a>;
}

/** Curva diária do criativo: investimento em barras, leads pagos em linha (escalas próprias, legendadas). */
function CurvaDiaria({ serie }: { serie: { dia: string; gasto: number; impressoes: number; leads: number }[] }) {
  if (serie.length === 0) return null;
  const W = 480; const H = 120; const n = serie.length;
  const maxG = Math.max(1, ...serie.map((s) => s.gasto)); const maxL = Math.max(1, ...serie.map((s) => s.leads));
  const larg = W / n;
  const pontos = serie.map((s, i) => `${(i + 0.5) * larg},${H - (s.leads / maxL) * (H - 8) - 4}`).join(' ');
  const total = serie.reduce((s, x) => s + x.gasto, 0);
  return (
    <figure>
      <figcaption className="mb-1 flex flex-wrap items-center gap-3 text-xs text-[var(--fg-3)]">
        <span>Por dia</span>
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-2 w-3 rounded-sm bg-[var(--accent)] opacity-60" />Investimento (máx. {moeda(maxG)})</span>
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-0.5 w-3 bg-[var(--cyan)]" />Leads pagos (máx. {formatar(maxL, 'int')})</span>
      </figcaption>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="h-28 w-full" role="img"
        aria-label={`Investimento total ${moeda(total)}. ${serie.map((s) => `${dataCurta(s.dia)}: ${moeda(s.gasto)}, ${s.leads} leads`).join('; ')}`}>
        {serie.map((s, i) => (
          <rect key={s.dia} x={i * larg + larg * 0.15} width={larg * 0.7} y={H - (s.gasto / maxG) * (H - 8)} height={(s.gasto / maxG) * (H - 8)} fill="var(--accent)" opacity="0.45">
            <title>{`${dataCurta(s.dia)}: ${moeda(s.gasto)} · ${s.leads} leads pagos`}</title>
          </rect>
        ))}
        <polyline points={pontos} fill="none" stroke="var(--cyan)" strokeWidth="2" vectorEffect="non-scaling-stroke" />
      </svg>
      <div className="mt-1 flex justify-between text-[10px] text-[var(--fg-3)]"><span>{dataCurta(serie[0].dia)}</span><span>{dataCurta(serie[serie.length - 1].dia)}</span></div>
    </figure>
  );
}
