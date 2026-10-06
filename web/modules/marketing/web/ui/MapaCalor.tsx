'use client';

// Marketing > Web > Mapa de calor: os cliques (ou a rolagem) desenhados SOBRE a página. Fundo, nesta ordem:
//   1. a captura de página inteira do último teste do Google do mesmo aparelho (mkt_web.velocidade_lab, rotina diária);
//   2. a página ao vivo num quadro (iframe) SEM JavaScript, só se a pessoa pedir: sem script o gravador e os pixels não
//      rodam, mas o <noscript> do pixel do Meta pode contar uma visita, e a página pode recusar ser aberta num quadro
//      (X-Frame-Options); por isso não é o padrão;
//   3. sem fundo (só a camada, na proporção da página).
// O ponto vem do banco como x % e y como fração da altura da página vista (migration 20261005q), então cai no lugar
// certo sobre qualquer fundo da mesma largura. Pintura portada do calor.ts do Radar do Luiz.
import { useEffect, useRef, useState } from 'react';
import { DataTable, EmptyState, KpiCard, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { num, pct } from '../domain/analise';
import { alturaDoFundo, cor, ehMorto, ehRaiva, forcaPonto, fracaoAlcance, posicao, raioPonto } from '../domain/calor';
import type { Calor } from '../domain/tipos';
import { SEM_DADOS } from './paineis';

export type Camada = 'cliques' | 'raiva' | 'rolagem';
type Fundo = 'captura' | 'pagina' | 'nenhum';

/* cores fixas do desenho (canvas não lê variável CSS) */
const COR_RAIVA = 'rgb(210,59,59)'; /* viz-colors */
const COR_MORTO = 'rgb(184,110,7)'; /* viz-colors */
const COR_ETIQUETA = 'rgba(14,26,47,0.86)'; /* viz-colors */

function pintar(cv: HTMLCanvasElement, c: Calor, camada: Camada, w: number, h: number) {
  const fator = w > 900 ? 0.5 : 1;
  cv.width = Math.max(1, Math.round(w * fator));
  cv.height = Math.max(1, Math.round(h * fator));
  const ctx = cv.getContext('2d');
  if (!ctx) return;
  ctx.clearRect(0, 0, cv.width, cv.height);
  if (camada === 'rolagem') {
    const al = c.alcance ?? [];
    const n = Math.max(1, al.length - 1);
    for (let i = 0; i < n; i++) {
      const [r, g, b] = cor(fracaoAlcance(al, i + 1));
      ctx.fillStyle = `rgba(${Math.round(r)},${Math.round(g)},${Math.round(b)},0.34)`;
      ctx.fillRect(0, (i / n) * cv.height, cv.width, cv.height / n);
    }
    ctx.font = `600 ${Math.round(13 * fator + 2)}px system-ui, sans-serif`;
    for (let i = 3; i < n; i += 4) {
      const y = ((i + 1) / n) * cv.height;
      const texto = Math.round(fracaoAlcance(al, i + 1) * 100) + '% chegaram até aqui';
      const lw = ctx.measureText(texto).width + 16;
      ctx.fillStyle = COR_ETIQUETA;
      ctx.fillRect(8, y - 24 * fator, lw, 20 * fator + 4);
      ctx.fillStyle = 'white';
      ctx.fillText(texto, 16, y - 8 * fator);
    }
    return;
  }
  const soRaiva = camada === 'raiva';
  const lista = soRaiva ? c.pontos.filter((p) => p[2] > 0) : c.pontos;
  const raio = raioPonto(w) * fator;
  const forca = forcaPonto(lista.length, soRaiva);
  for (const p of lista) {
    const { x, y } = posicao(p[0], p[1], cv.width, cv.height);
    const g = ctx.createRadialGradient(x, y, 0, x, y, raio);
    g.addColorStop(0, `rgba(0,0,0,${forca})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(x - raio, y - raio, raio * 2, raio * 2);
  }
  const img = ctx.getImageData(0, 0, cv.width, cv.height);
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const a = d[i + 3];
    if (!a) continue;
    const [r, g, b] = cor(a / 190);
    d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = Math.min(215, 70 + a);
  }
  ctx.putImageData(img, 0, 0);
  if (soRaiva) {
    for (const p of lista) {
      const { x, y } = posicao(p[0], p[1], cv.width, cv.height);
      ctx.strokeStyle = ehRaiva(p[2]) ? COR_RAIVA : ehMorto(p[2]) ? COR_MORTO : COR_RAIVA;
      ctx.lineWidth = 2 * fator + 0.5;
      ctx.beginPath(); ctx.arc(x, y, 9 * fator + 2, 0, Math.PI * 2); ctx.stroke();
    }
  }
}

export function PainelCalor({ c, camada, onCamada }: { c: Calor; camada: Camada; onCamada?: (c: Camada) => void }) {
  const [fundo, setFundo] = useState<Fundo>(c.captura ? 'captura' : 'nenhum');
  const palco = useRef<HTMLDivElement>(null);
  const tela = useRef<HTMLCanvasElement>(null);
  const [largura, setLargura] = useState(0);

  useEffect(() => {
    const el = palco.current;
    if (!el) return;
    const medir = () => setLargura(Math.min(el.clientWidth, c.largura && c.largura < 700 ? 420 : 960));
    medir();
    const ro = new ResizeObserver(medir);
    ro.observe(el);
    return () => ro.disconnect();
  }, [c.largura]);

  const altura = alturaDoFundo(largura || 1, fundo === 'captura' ? c.captura : null, c.largura, c.altura_doc);

  useEffect(() => {
    if (tela.current && largura > 0) pintar(tela.current, c, camada, largura, altura);
  }, [c, camada, largura, altura]);

  if (!c.visitas) return <SectionCard><EmptyState title={SEM_DADOS} hint="Sem visita desta página neste aparelho no período." icon="globe" /></SectionCard>;

  const k = c.contagem ?? { cliques: 0, raiva: 0, mortos: 0, fixos: 0 };
  const escalaIframe = c.largura ? largura / c.largura : 1;
  const botao = (ativo: boolean) => `rounded-[var(--r-md)] border px-2.5 py-1 text-xs ${ativo ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`;
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Páginas vistas" value={num(c.visitas)} hint={c.largura ? `largura típica ${c.largura} px` : undefined} bar="gray" />
        <KpiCard label="Cliques na página" value={num(k.cliques)} hint={c.amostra ? 'desenho com amostra de 5.000' : undefined} />
        <KpiCard label="Raiva e mortos" value={`${num(k.raiva)} · ${num(k.mortos)}`} bar="yellow" />
        <KpiCard label="Em elemento fixo" value={num(k.fixos)} hint="janela, barra fixa: fora do desenho" bar="gray" />
      </div>
      <SectionCard title="Sobre a página"
        subtitle={fundo === 'captura' && c.captura ? `Fundo: captura do teste do Google de ${new Date(c.captura.medido_em).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' })}. Se a página mudou depois, o desenho pode não bater.` : fundo === 'pagina' ? 'Fundo: a página ao vivo, sem JavaScript (pode ficar diferente do que a pessoa viu, ou em branco se a página não deixar ser aberta num quadro).' : 'Sem fundo: só a camada, na proporção da página.'}>
        <div className="mb-3 flex flex-wrap gap-2" role="group" aria-label="Camada e fundo">
          {onCamada && (['cliques', 'raiva', 'rolagem'] as const).map((x) => (
            <button key={x} type="button" className={botao(camada === x)} aria-pressed={camada === x} onClick={() => onCamada(x)}>
              {x === 'cliques' ? 'Cliques' : x === 'raiva' ? 'Raiva e mortos' : 'Rolagem'}
            </button>
          ))}
          <span className="mx-1 text-[var(--fg-3)]">|</span>
          <button type="button" className={botao(fundo === 'captura')} disabled={!c.captura} onClick={() => setFundo('captura')}
            title={c.captura ? '' : 'Sem captura ainda: vem do teste diário do Google (aba Velocidade)'}>Captura do Google</button>
          <button type="button" className={botao(fundo === 'pagina')} disabled={!c.url} onClick={() => setFundo('pagina')}>Página ao vivo</button>
          <button type="button" className={botao(fundo === 'nenhum')} onClick={() => setFundo('nenhum')}>Sem fundo</button>
        </div>
        {fundo === 'pagina' && (
          <p className="mb-2 text-xs text-[var(--yellow)]">Abrir a página ao vivo carrega o HTML dela (sem JavaScript). O pixel do Meta em &lt;noscript&gt; pode contar uma visita.</p>
        )}
        <div ref={palco} className="w-full">
          <div className="relative mx-auto max-h-[760px] overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)]" style={{ width: largura || '100%' }}>
            <div className="relative" style={{ height: altura }}>
              {fundo === 'captura' && c.captura && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={c.captura.img} alt="Captura da página feita pelo teste do Google" className="absolute left-0 top-0 w-full" style={{ height: altura }} />
              )}
              {fundo === 'pagina' && c.url && c.largura && (
                <iframe src={c.url} title="Página ao vivo (sem JavaScript)" sandbox="" referrerPolicy="no-referrer" loading="lazy"
                  className="absolute left-0 top-0 origin-top-left pointer-events-none border-0 bg-white"
                  style={{ width: c.largura, height: altura / (escalaIframe || 1), transform: `scale(${escalaIframe})` }} />
              )}
              <canvas ref={tela} className="absolute left-0 top-0 pointer-events-none" style={{ width: '100%', height: altura }} aria-label="Camada do mapa de calor" />
            </div>
          </div>
        </div>
      </SectionCard>
      <SectionCard title="Mais clicados">
        {!c.top.length ? <p className="text-sm text-[var(--fg-3)]">Nenhum clique no período.</p> : (
          <DataTable minWidth={600}>
            <Thead><Th>Elemento</Th><Th>Texto</Th><Th>Cliques</Th><Th>Raiva</Th><Th>Mortos</Th></Thead>
            <tbody>{c.top.map((t) => (
              <Tr key={t.sel}><Td><span className="font-mono text-xs break-all">{t.sel}</span>{t.fixo && <span className="ml-1 text-[11px] text-[var(--fg-3)]">(fixo)</span>}</Td>
                <Td>{t.txt || '–'}</Td><Td>{num(t.n)}</Td><Td>{pct(t.raiva, t.n, 0)}</Td><Td>{pct(t.morto, t.n, 0)}</Td></Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}
