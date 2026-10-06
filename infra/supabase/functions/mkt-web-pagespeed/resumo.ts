// mkt-web-pagespeed: o resumo da resposta do Google PageSpeed Insights (v5) que fica guardado em mkt_web.velocidade_lab
// (migration 20261006h). Puro (sem Deno, sem rede): testado em web/modules/marketing/web/domain/pagespeed-resumo.test.ts.
// O que sai: as notas das 4 categorias (0 a 100), as métricas de laboratório (LCP, FCP, TBT, Speed Index, CLS), até 5
// oportunidades (o que mais economiza tempo, como o Radar mostrava) e a captura da página inteira (o fundo do mapa de
// calor), quando o Google manda.

// deno-lint-ignore no-explicit-any
type Json = any;

export interface ResumoGoogle {
  nota: number | null;
  notas: { desempenho?: number; acessibilidade?: number; praticas?: number; seo?: number };
  lcp_ms: number | null; fcp_ms: number | null; tbt_ms: number | null; si_ms: number | null; cls: number | null;
  oportunidades: { id: string; titulo: string; ms: number }[];
  captura: { img: string; largura: number; altura: number } | null;
}

const CATEGORIA: Record<string, keyof ResumoGoogle['notas']> = {
  performance: 'desempenho', accessibility: 'acessibilidade', 'best-practices': 'praticas', seo: 'seo',
};

const nota = (score: unknown) => (typeof score === 'number' && score >= 0 && score <= 1 ? Math.round(score * 100) : null);
const ms = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v) : null);
/** a captura vai para o banco só se for imagem em base64 e couber (teto do banco: 2 MB no jsonb) */
const CAPTURA_MAX = 1_900_000;

export function resumirGoogle(resposta: Json): ResumoGoogle {
  const lh = resposta?.lighthouseResult ?? {};
  const cats = lh.categories ?? {};
  const audits = lh.audits ?? {};
  const notas: ResumoGoogle['notas'] = {};
  for (const [id, chave] of Object.entries(CATEGORIA)) {
    const n = nota(cats[id]?.score);
    if (n != null) notas[chave] = n;
  }
  const oportunidades = Object.entries(audits as Record<string, Json>)
    .map(([id, a]) => ({ id, titulo: String(a?.title ?? id), ms: ms(a?.details?.overallSavingsMs) ?? 0, tipo: a?.details?.type }))
    .filter((o) => o.tipo === 'opportunity' && o.ms > 0)
    .sort((a, b) => b.ms - a.ms)
    .slice(0, 5)
    .map(({ id, titulo, ms: m }) => ({ id, titulo: titulo.slice(0, 160), ms: m }));
  // captura da página inteira: lighthouseResult.fullPageScreenshot (Lighthouse 10+) ou a auditoria antiga
  const tela = lh.fullPageScreenshot?.screenshot ?? audits['full-page-screenshot']?.details?.screenshot;
  const img = typeof tela?.data === 'string' ? tela.data : '';
  const captura = /^data:image\/(jpeg|png|webp);base64,/.test(img) && img.length <= CAPTURA_MAX && tela.width > 0 && tela.height > 0
    ? { img, largura: Math.round(tela.width), altura: Math.round(tela.height) }
    : null;
  const cls = audits['cumulative-layout-shift']?.numericValue;
  return {
    nota: notas.desempenho ?? null,
    notas,
    lcp_ms: ms(audits['largest-contentful-paint']?.numericValue),
    fcp_ms: ms(audits['first-contentful-paint']?.numericValue),
    tbt_ms: ms(audits['total-blocking-time']?.numericValue),
    si_ms: ms(audits['speed-index']?.numericValue),
    cls: typeof cls === 'number' && Number.isFinite(cls) && cls >= 0 ? Math.round(cls * 1000) / 1000 : null,
    oportunidades,
    captura,
  };
}

/** a URL do pedido ao Google; a chave entra só se existir (sem ela, a cota pública) */
export function urlGoogle(url: string, estrategia: 'mobile' | 'desktop', chave?: string | null): string {
  const q = new URLSearchParams({ url, strategy: estrategia, locale: 'pt' });
  for (const c of ['performance', 'accessibility', 'best-practices', 'seo']) q.append('category', c);
  if (chave) q.set('key', chave);
  return 'https://www.googleapis.com/pagespeedonline/v5/runPagespeed?' + q.toString();
}
