'use client';

// Bloco A: cronograma até a Black. Responde "onde estamos no aquecimento e o que falta até a venda?".
// A live de venda é o cartão maior, com contagem regressiva. Os outros cartões seguem a ordem do calendário.
import { Card, SectionCard } from '@/shared/ui/components';
import type { FonteDadosBlack } from '../../application/ports';
import { contagemRegressiva, porData, ROTULO_SITUACAO_LIVE, ROTULO_TIPO_LIVE, type Live } from '../../domain/lives';
import { COR_SITUACAO, DICA_SITUACAO, dataCurta, horaDe, numeroDe, quando, semanaDe, tituloDe } from './formatos';
import { ContagemRegressiva, SeloSituacao, SeloTipo } from './pecas-lives';

/** A live de venda a destacar: a próxima ainda não realizada; se todas passaram, a última. */
export function liveDaBlack(lives: readonly Live[]): Live | null {
  const pretas = lives.filter((l) => l.tipo === 'black').sort(porData);
  return pretas.find((l) => l.situacao !== 'realizada') ?? pretas[pretas.length - 1] ?? null;
}

function Trilha({ lives }: { lives: Live[] }) {
  const feitas = lives.filter((l) => l.situacao === 'realizada').length;
  return (
    <div>
      <ol className="flex items-center gap-1.5" aria-label={`${feitas} de ${lives.length} lives realizadas`}>
        {lives.map((l) => (
          <li key={l.videoId} title={`${dataCurta(l.dataPrevista)} ${ROTULO_TIPO_LIVE[l.tipo]}: ${ROTULO_SITUACAO_LIVE[l.situacao]}`}
            className={(l.tipo === 'black' ? 'flex-[1.6] ' : 'flex-1 ') + 'h-2 rounded-full ' + (l.situacao === 'ao_vivo' ? 'motion-safe:animate-pulse ' : '') + (l.situacao === 'a_agendar' ? 'border border-dashed border-[var(--yellow)]' : '')}
            style={{ background: l.situacao === 'a_agendar' ? 'transparent' : l.situacao === 'em_breve' ? (l.tipo === 'black' ? 'var(--accent-subtle)' : 'var(--surface-4)') : COR_SITUACAO[l.situacao], boxShadow: l.tipo === 'black' ? '0 0 0 1px var(--accent)' : undefined }} />
        ))}
      </ol>
      <div className="mt-1.5 flex justify-between text-[11px] text-[var(--fg-3)]">
        <span>{lives[0] ? dataCurta(lives[0].dataPrevista) : ''}</span>
        <span>{lives.length ? dataCurta(lives[lives.length - 1].dataPrevista) : ''}</span>
      </div>
    </div>
  );
}

function RodapeCartao({ live, agoraMs }: { live: Live; agoraMs: number }) {
  if (live.situacao === 'realizada') {
    return <p className="text-sm text-[var(--fg-2)]">Pico <strong className="tabular text-[var(--fg)]">{numeroDe(live.pico)}</strong>{live.pico === null ? ' (falta importar o CSV do Studio)' : ' espectadores'}</p>;
  }
  if (live.situacao === 'ao_vivo') {
    return <p className="text-sm text-[var(--fg-2)]">Agora <strong className="tabular text-[var(--red)]">{numeroDe(live.espectadoresAgora ?? live.ultimoEspectadores)}</strong> na sala</p>;
  }
  if (live.situacao === 'a_agendar') return <p className="text-xs text-[var(--yellow)]">{DICA_SITUACAO.a_agendar}</p>;
  const c = contagemRegressiva(agoraMs, live.dataPrevista);
  if (!c || c.passou) return <p className="text-xs text-[var(--fg-3)]">Começa em instantes.</p>;
  return <p className="text-xs text-[var(--fg-3)]">{c.dias > 0 ? `Em ${c.dias} ${c.dias === 1 ? 'dia' : 'dias'}` : c.horas > 0 ? `Em ${c.horas} h` : `Em ${c.minutos} min`}</p>;
}

function CartaoLive({ live, agoraMs, onAbrir }: { live: Live; agoraMs: number; onAbrir: (id: string) => void }) {
  const abre = live.situacao === 'realizada' || live.situacao === 'ao_vivo';
  const corpo = (
    <>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="tabular text-base font-bold leading-tight text-[var(--fg)]">{dataCurta(live.dataPrevista)} <span className="text-xs font-medium text-[var(--fg-3)]">{semanaDe(live.dataPrevista)} {horaDe(live.dataPrevista)}</span></div>
        </div>
        <SeloSituacao situacao={live.situacao} />
      </div>
      <div className="mt-2"><SeloTipo tipo={live.tipo} /></div>
      <p className={'mt-2 break-words text-sm leading-snug ' + (live.titulo ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]')}>{tituloDe(live)}</p>
      <div className="mt-3"><RodapeCartao live={live} agoraMs={agoraMs} /></div>
    </>
  );
  const classe = 'block h-full w-full p-4 text-left';
  return (
    <li className="min-w-0">
      <Card className={'h-full overflow-hidden ' + (abre ? 'hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]' : '')} style={{ borderTop: `3px solid ${COR_SITUACAO[live.situacao]}` }}>
        {abre
          ? <button type="button" onClick={() => onAbrir(live.videoId)} className={classe + ' gp-press min-h-11 rounded-[var(--r-lg)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]'} aria-label={`Abrir o detalhe: ${tituloDe(live)}, ${quando(live.dataPrevista)}`}>{corpo}</button>
          : <div className={classe}>{corpo}</div>}
      </Card>
    </li>
  );
}

function CartaoBlack({ live, fonte, onAbrir }: { live: Live; fonte: FonteDadosBlack; onAbrir: (id: string) => void }) {
  const futura = live.situacao === 'em_breve' || live.situacao === 'a_agendar';
  return (
    <Card className="gp-rise overflow-hidden border-[var(--border-accent)] bg-[linear-gradient(135deg,var(--accent-subtle),transparent_60%)]">
      <div className="grid gap-4 p-4 sm:p-5 md:grid-cols-[minmax(0,1fr)_auto] md:items-center">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">A live de venda</span>
            <SeloSituacao situacao={live.situacao} />
          </div>
          <div className="mt-1 tabular text-2xl font-bold text-[var(--fg)] sm:text-3xl">{quando(live.dataPrevista)}</div>
          <p className={'mt-1 break-words text-sm leading-snug ' + (live.titulo ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]')}>{tituloDe(live)}</p>
          {live.situacao === 'a_agendar' && <p className="mt-1 text-xs text-[var(--yellow)]">{DICA_SITUACAO.a_agendar}</p>}
          {!futura && (
            <button type="button" onClick={() => onAbrir(live.videoId)} className="mt-3 min-h-11 rounded-[var(--r-md)] border border-[var(--border-accent)] px-3 text-sm font-semibold text-[var(--accent)] hover:bg-[var(--accent-subtle)]">Abrir o detalhe</button>
          )}
        </div>
        {futura && (
          <div className="min-w-0">
            <div className="mb-1.5 text-xs text-[var(--fg-3)]">Ainda não aconteceu. Faltam:</div>
            <ContagemRegressiva fonte={fonte} alvoIso={live.dataPrevista} />
          </div>
        )}
      </div>
    </Card>
  );
}

export function Cronograma({ lives, fonte, agoraMs, onAbrir }: { lives: Live[]; fonte: FonteDadosBlack; agoraMs: number; onAbrir: (videoId: string) => void }) {
  const ordenadas = [...lives].sort(porData);
  const black = liveDaBlack(ordenadas);
  const outras = ordenadas.filter((l) => l.videoId !== black?.videoId);
  const feitas = ordenadas.filter((l) => l.situacao === 'realizada').length;
  const aoVivo = ordenadas.filter((l) => l.situacao === 'ao_vivo').length;
  const c = black && black.situacao !== 'realizada' ? contagemRegressiva(agoraMs, black.dataPrevista) : null;
  const partes = [`${feitas} de ${ordenadas.length} lives realizadas`];
  if (aoVivo > 0) partes.push(`${aoVivo} ao vivo agora`);
  if (c && !c.passou) partes.push(`faltam ${c.dias} ${c.dias === 1 ? 'dia' : 'dias'} para a Black`);
  return (
    <SectionCard title="Cronograma até a Black" subtitle={partes.join(' · ')}>
      <div className="space-y-4">
        <Trilha lives={ordenadas} />
        {black && <CartaoBlack live={black} fonte={fonte} onAbrir={onAbrir} />}
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {outras.map((l) => <CartaoLive key={l.videoId} live={l} agoraMs={agoraMs} onAbrir={onAbrir} />)}
        </ul>
      </div>
    </SectionCard>
  );
}
