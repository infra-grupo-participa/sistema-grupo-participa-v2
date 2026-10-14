'use client';

// Gaveta do criativo: miniatura, caminho (campanha › conjunto › página, nomes exatos da fonte), funil em trapézios
// (impressões → cliques → views → leads pagos → ingresso no grupo em 48h, com CTR, connect rate, conversão da página
// e taxa de ingresso nas pontes; no C1, impressões → vídeo 75%), curva diária interativa e os três botões (Ver anúncio, Abrir no Gerenciador, Abrir página). Link só abre se for http(s) válido; no modo
// demonstração os botões ficam desabilitados.
import { useMemo } from 'react';
import { safeHttpUrl } from '@/shared/domain/url-segura';
import { anunciosDoCriativo, funilCriativo, resumir, serieDiariaAnuncio } from '../domain/criativos';
import { filtrarDias } from '../domain/metricas';
import type { DadosTela } from './contexto';
import { FunilTrapezio, GraficoInvestimentoLeads } from './graficos';
import { MiniaturaFicticia } from './MiniaturaFicticia';
import { Farol, Numero, Taxa } from './pecas';

export function GavetaCriativo({ d, id }: { d: DadosTela; id: string }) {
  const a = d.idx.anuncio.get(id);
  const dados = useMemo(() => {
    // Criativo = todos os anúncios de mesmo nome (um por conjunto): a gaveta soma os conjuntos onde ele roda.
    const ids = anunciosDoCriativo(d.idx, id); const conjunto = new Set(ids);
    const dias = filtrarDias(d.diasPeriodoSemFiltro.filter((x) => conjunto.has(x.anuncioId)), d.idx, { funil: 'todos', canal: 'todos' });
    const linhas = d.linhasPeriodoSemFiltro.filter((l) => l.anuncioId !== null && conjunto.has(l.anuncioId));
    const camps = ids.map((x) => d.idx.campanhaDoAnuncio(x));
    const distribuicao = camps.every((c) => c === null || c.funil === 'c1' || c.funil === null);
    const resumo = resumir(dias, linhas, d.idx, d.config.reguaCpl, distribuicao);
    return { ids, dias, linhas, distribuicao, resumo, funil: funilCriativo(resumo, dias, linhas, d.idx), serie: serieDiariaAnuncio(ids, dias, linhas, d.diasPeriodo) };
  }, [d, id]);
  if (!a) return <p className="text-sm text-[var(--fg-3)]">Criativo não encontrado no catálogo.</p>;
  // Onde o criativo roda: nomes exatos das campanhas e dos conjuntos (sem repetir), na ordem dos anúncios.
  const conjuntos = [...new Set(dados.ids.map((x) => d.idx.conjuntoDoAnuncio(x)).filter((c): c is NonNullable<typeof c> => c !== null))];
  const campanhas = [...new Set(conjuntos.map((c) => d.idx.campanha.get(c.campanhaId)?.nome).filter((n): n is string => Boolean(n)))];
  const pagina = a.paginaId ? d.paginas.get(a.paginaId) : undefined;
  const r = dados.resumo;
  const demo = d.fonte.modo === 'demonstracao';
  const miniatura = demo ? null : safeHttpUrl(a.miniaturaUrl);

  return (
    <div className="space-y-4">
      <div className="mx-auto max-w-xs">
        {miniatura
          // eslint-disable-next-line @next/next/no-img-element -- URL assinada do Storage (bucket trafego-miniaturas), já validada por safeHttpUrl
          ? <img src={miniatura} alt={`Miniatura de ${a.nome}`} className="block w-full rounded-[var(--r-md)]" />
          : <MiniaturaFicticia id={a.id} formato={a.formato} />}
      </div>

      <dl className="space-y-1 text-xs">
        <div><dt className="inline text-[var(--fg-3)]">Campanha: </dt><dd className="inline break-words text-[var(--fg-2)]">{campanhas.length ? campanhas.join(' · ') : 'Não informado'}</dd></div>
        <div><dt className="inline text-[var(--fg-3)]">{conjuntos.length > 1 ? `Conjuntos (${conjuntos.length}): ` : 'Conjunto: '}</dt><dd className="inline break-words text-[var(--fg-2)]">{conjuntos.length ? conjuntos.map((c) => c.nome).join(' · ') : 'Não informado'}</dd></div>
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

      <section aria-label="Funil do criativo">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil</h3>
        <FunilTrapezio etapas={dados.funil} rotulo="Funil do criativo no período" />
      </section>

      <GraficoInvestimentoLeads serie={dados.serie} />

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
