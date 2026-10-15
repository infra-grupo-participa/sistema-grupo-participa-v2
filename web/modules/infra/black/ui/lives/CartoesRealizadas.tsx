'use client';

// Bloco D: cartões das lives realizadas. Pergunta: "qual live segurou melhor a sala?".
// O número com intenção é o fim em % do pico (último minuto ÷ pico). A ordem muda com os chips.
import { useState } from 'react';
import { Card, SectionCard } from '@/shared/ui/components';
import { duracaoTexto, fimEmPctDoPico, minutoDe, porData, type Live } from '../../domain/lives';
import { Chip } from '../pecas';
import { dataCurta, horaDe, numeroDe, pctDe, semanaDe, tituloDe } from './formatos';
import { Miniatura, SeloTipo } from './pecas-lives';

type Ordem = 'data' | 'retencao' | 'pico';
const ROTULO_ORDEM: Record<Ordem, string> = { data: 'Mais recentes', retencao: 'Quem segurou mais a sala', pico: 'Maior pico' };

function ordenar(lives: Live[], ordem: Ordem): Live[] {
  const l = [...lives];
  if (ordem === 'data') return l.sort((a, b) => porData(b, a));
  const chave = (x: Live) => (ordem === 'pico' ? x.pico : fimEmPctDoPico(x));
  // Sem dado vai para o fim, nunca para o topo nem para o zero.
  return l.sort((a, b) => {
    const va = chave(a); const vb = chave(b);
    if (va === null && vb === null) return porData(b, a);
    if (va === null) return 1;
    if (vb === null) return -1;
    return vb - va || porData(b, a);
  });
}

function Dado({ rotulo, valor, dica }: { rotulo: string; valor: string; dica?: string }) {
  return (
    <div className="min-w-0" title={dica}>
      <dt className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</dt>
      <dd className="tabular text-base font-bold leading-tight text-[var(--fg)]">{valor}</dd>
    </div>
  );
}

function Cartao({ live, onAbrir, isMaster, onImportar }: { live: Live; onAbrir: (id: string) => void; isMaster: boolean; onImportar: (l: Live) => void }) {
  const fim = fimEmPctDoPico(live);
  return (
    <li className="min-w-0">
      <Card className="flex h-full flex-col overflow-hidden">
        <button type="button" onClick={() => onAbrir(live.videoId)} aria-label={`Abrir o detalhe: ${tituloDe(live)}`}
          className="gp-press block w-full text-left outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]">
          <Miniatura live={live} />
          <div className="p-4 pb-2">
            <div className="flex flex-wrap items-center gap-2">
              <span className="tabular text-sm font-bold text-[var(--fg)]">{dataCurta(live.dataPrevista)}</span>
              <span className="text-xs text-[var(--fg-3)]">{semanaDe(live.dataPrevista)} {horaDe(live.dataPrevista)}</span>
              <SeloTipo tipo={live.tipo} />
            </div>
            <p className={'mt-2 break-words text-sm leading-snug ' + (live.titulo ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]')}>{tituloDe(live)}</p>
          </div>
        </button>
        <div className="mt-auto space-y-3 p-4 pt-2">
          <div>
            <div className="flex items-baseline justify-between gap-2 text-xs text-[var(--fg-2)]">
              <span title="Espectadores no último minuto ÷ pico">Ainda na sala no fim</span>
              <strong className="tabular text-sm text-[var(--fg)]">{pctDe(fim)}</strong>
            </div>
            <div className="mt-1 h-2 overflow-hidden rounded-full bg-[var(--surface-4)]" role="img" aria-label={fim === null ? 'Fim em % do pico: sem dado' : `Fim em % do pico: ${pctDe(fim)}`}>
              {fim !== null && <div className="h-full rounded-full bg-[var(--accent)]" style={{ width: `${Math.min(100, Math.max(0, fim * 100))}%` }} />}
            </div>
            <div className="mt-1 text-[11px] text-[var(--fg-3)]">{live.ultimoEspectadores !== null && live.pico !== null ? `${numeroDe(live.ultimoEspectadores)} no último minuto ÷ pico de ${numeroDe(live.pico)}` : 'Sem a curva minuto a minuto'}</div>
          </div>
          <dl className="grid grid-cols-2 gap-x-3 gap-y-2">
            <Dado rotulo="Pico" valor={live.pico === null ? 'Sem dado' : `${numeroDe(live.pico)}${live.picoSeg !== null ? ` · min ${minutoDe(live.picoSeg)}` : ''}`} />
            <Dado rotulo="Duração" valor={duracaoTexto(live.duracaoSeg)} />
            <Dado rotulo="Chat" valor={live.chatTotal === null ? 'Sem dado' : `${numeroDe(live.chatTotal)} msg`} dica="Mensagens do chat ao vivo (CSV do Studio)" />
            <Dado rotulo="Views" valor={numeroDe(live.views)} dica="Visualizações do vídeo na API do YouTube, contam também o replay" />
          </dl>
          {!live.temStudio && (
            <div className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-2 text-xs text-[var(--yellow)]">
              Sem o CSV do Studio: {live.pico === null ? 'não há pico nem curva minuto a minuto.' : 'o pico é amostrado pela API e pode diferir do Studio.'}
              {isMaster && <button type="button" onClick={() => onImportar(live)} className="ml-2 min-h-9 font-semibold underline underline-offset-2">Importar CSV</button>}
            </div>
          )}
        </div>
      </Card>
    </li>
  );
}

export function CartoesRealizadas({ lives, onAbrir, isMaster, onImportar }: { lives: Live[]; onAbrir: (id: string) => void; isMaster: boolean; onImportar: (l: Live) => void }) {
  const [ordem, setOrdem] = useState<Ordem>('data');
  const realizadas = lives.filter((l) => l.situacao === 'realizada');
  return (
    <SectionCard title="Lives realizadas" subtitle="Qual live segurou melhor a sala. Clique para abrir a curva minuto a minuto, o chat e os comentários."
      right={realizadas.length > 1 ? (
        <div className="flex flex-wrap justify-end gap-1.5" role="group" aria-label="Ordenar as lives">
          {(Object.keys(ROTULO_ORDEM) as Ordem[]).map((o) => <Chip key={o} ativo={ordem === o} onClick={() => setOrdem(o)}>{ROTULO_ORDEM[o]}</Chip>)}
        </div>
      ) : undefined}>
      {realizadas.length === 0
        ? <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Nenhuma live realizada ainda.</p>
        : <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">{ordenar(realizadas, ordem).map((l) => <Cartao key={l.videoId} live={l} onAbrir={onAbrir} isMaster={isMaster} onImportar={onImportar} />)}</ul>}
    </SectionCard>
  );
}
