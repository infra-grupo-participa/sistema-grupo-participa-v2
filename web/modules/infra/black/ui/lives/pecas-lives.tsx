'use client';

// Peças pequenas da aba Lives: selos de tipo e situação, miniatura, relógio e contagem regressiva.
import { useEffect, useState } from 'react';
import { Badge } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { FonteDadosBlack } from '../../application/ports';
import { contagemRegressiva, ROTULO_SITUACAO_LIVE, ROTULO_TIPO_LIVE, type Live, type SituacaoLive, type TipoLive } from '../../domain/lives';
import { usePrefereMenosMovimento } from '../pecas';
import { COR_TIPO, DICA_SITUACAO } from './formatos';

export function SeloTipo({ tipo }: { tipo: TipoLive }) {
  return <Badge dotColor={COR_TIPO[tipo]}>{ROTULO_TIPO_LIVE[tipo]}</Badge>;
}

const TOM: Record<SituacaoLive, 'success' | 'danger' | 'neutral' | 'warning'> = { realizada: 'success', ao_vivo: 'danger', em_breve: 'neutral', a_agendar: 'warning' };

export function SeloSituacao({ situacao }: { situacao: SituacaoLive }) {
  return <span title={DICA_SITUACAO[situacao]} className="inline-flex"><Badge tone={TOM[situacao]}>{ROTULO_SITUACAO_LIVE[situacao]}</Badge></span>;
}

/** Miniatura do vídeo (já filtrada para os hosts do YouTube pelo mapeador). Sem miniatura: quadro neutro. */
export function Miniatura({ live, className = '' }: { live: Pick<Live, 'miniatura'>; className?: string }) {
  if (!live.miniatura) {
    return <div aria-hidden className={`grid aspect-video place-items-center bg-[var(--surface-3)] text-[var(--fg-4)] ${className}`}><Icon name="video" size={28} strokeWidth={1.5} /></div>;
  }
  // eslint-disable-next-line @next/next/no-img-element -- URL de miniatura do YouTube, validada por safeHttpUrl (ytimg.com, youtube.com) no mapeador
  return <img src={live.miniatura} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" className={`aspect-video w-full object-cover ${className}`} />;
}

/** Relógio da tela: a fonte decide a hora (no demo fica fixa). Só renderiza de novo quando o valor muda. */
export function useAgoraMs(fonte: FonteDadosBlack, intervaloMs: number): number {
  const [agora, setAgora] = useState(() => fonte.agora().getTime());
  useEffect(() => {
    const id = window.setInterval(() => setAgora(fonte.agora().getTime()), intervaloMs);
    return () => window.clearInterval(id);
  }, [fonte, intervaloMs]);
  return agora;
}

/** Contagem regressiva em caixas (dias, horas, minutos e segundos). Com movimento reduzido, não conta os segundos. */
export function ContagemRegressiva({ fonte, alvoIso }: { fonte: FonteDadosBlack; alvoIso: string }) {
  const menos = usePrefereMenosMovimento();
  const agora = useAgoraMs(fonte, menos ? 60_000 : 1000);
  const c = contagemRegressiva(agora, alvoIso);
  if (!c || c.passou) return null;
  const itens: [string, number][] = [['dias', c.dias], ['horas', c.horas], ['min', c.minutos], ...(menos ? [] : [['seg', c.segundos] as [string, number]])];
  const falado = `Faltam ${c.dias} dias, ${c.horas} horas e ${c.minutos} minutos`;
  return (
    <div role="timer" aria-label={falado} className="flex items-stretch gap-2">
      {itens.map(([rotulo, v]) => (
        <div key={rotulo} className="min-w-[3.6rem] rounded-[var(--r-md)] border border-[var(--border-accent)] bg-[var(--surface-1)] px-2 py-1.5 text-center">
          <div className="tabular text-2xl font-bold leading-none text-[var(--accent)]" aria-hidden>{String(v).padStart(2, '0')}</div>
          <div className="mt-1 text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]" aria-hidden>{rotulo}</div>
        </div>
      ))}
    </div>
  );
}
