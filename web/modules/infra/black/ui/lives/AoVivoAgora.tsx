'use client';

// Bloco B: ao vivo agora (só aparece com uma live no ar). Pergunta: "estamos acima ou abaixo da última live parecida,
// no mesmo minuto?", para dar tempo de chamar mais gente enquanto a live ainda está rolando. Relê a cada 60 s.
// Leitura atrasada ou com falha: segura o último valor, esmaece e mostra a idade (nunca vira zero).
import { SectionCard } from '@/shared/ui/components';
import type { FonteDadosBlack } from '../../application/ports';
import { curvaComparativa, DETALHE_VAZIO, marcosDaCurva, minutoDe, posicaoContraAnterior, ROTULO_TIPO_LIVE, ultimaRealizadaDoTipo, type Live } from '../../domain/lives';
import { CurvaComparativa } from '../graficos-lives';
import { AvisoBloco } from '../pecas';
import { dataCurta, idadeTexto, numeroDe, tituloDe } from './formatos';
import { SeloSituacao, SeloTipo } from './pecas-lives';
import { useLeitura } from './useLeitura';

/** Passou disto sem leitura nova da API, o número da sala deixa de ser "agora". */
const ATRASO_MS = 3 * 60_000;

export function AoVivoAgora({ live, lives, fonte, chave, agoraMs, onAbrir }: {
  live: Live; lives: Live[]; fonte: FonteDadosBlack; chave: string; agoraMs: number; onAbrir: (videoId: string) => void;
}) {
  const anterior = ultimaRealizadaDoTipo(lives, live);
  const atual = useLeitura('a curva ao vivo', () => fonte.liveDetalhe(chave, live.videoId), `aovivo|${chave}|${live.videoId}`, 60_000);
  const ref = useLeitura('a live de referência', anterior ? () => fonte.liveDetalhe(chave, anterior.videoId) : null, `ref|${chave}|${anterior?.videoId ?? '-'}`, null);

  const minutos = atual.data?.minutos ?? DETALHE_VAZIO.minutos;
  const pontos = curvaComparativa(minutos, ref.data?.minutos ?? []);
  const pos = posicaoContraAnterior(pontos);
  const marcos = marcosDaCurva(minutos);
  const ultimo = [...minutos].reverse().find((m) => m.espectadores !== null) ?? null;
  const naSala = live.espectadoresAgora ?? ultimo?.espectadores ?? null;
  const coletado = live.coletadoEm ? Date.parse(live.coletadoEm) : null;
  const atrasada = coletado === null || agoraMs - coletado > ATRASO_MS || Boolean(atual.erro);
  const rotuloAnterior = anterior ? `${ROTULO_TIPO_LIVE[anterior.tipo]} ${dataCurta(anterior.dataPrevista)}` : null;
  const rotuloAtual = `${ROTULO_TIPO_LIVE[live.tipo]} ${dataCurta(live.dataPrevista)}`;
  const rel = pos && pos.anterior > 0 ? pos.atual / pos.anterior : null;

  return (
    <SectionCard
      title={<span className="inline-flex items-center gap-2"><span aria-hidden className="inline-block h-2.5 w-2.5 rounded-full bg-[var(--red)] motion-safe:animate-pulse" />Ao vivo agora</span>}
      subtitle="Acima ou abaixo da última live do mesmo tipo, no mesmo minuto. Atualiza a cada minuto enquanto a live estiver no ar."
      right={<button type="button" onClick={() => onAbrir(live.videoId)} className="min-h-11 shrink-0 rounded-[var(--r-md)] border border-[var(--border)] px-3 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]">Abrir o detalhe</button>}>
      <div className={'space-y-4 transition-opacity ' + (atrasada ? 'opacity-60' : '')}>
        <div className="flex flex-wrap items-center gap-2">
          <SeloSituacao situacao="ao_vivo" /><SeloTipo tipo={live.tipo} />
          <span className="min-w-0 break-words text-sm text-[var(--fg)]">{tituloDe(live)}</span>
        </div>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <div className="min-w-0">
            <div className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)]">Na sala agora</div>
            <div className="tabular text-4xl font-bold leading-tight text-[var(--accent)]">{numeroDe(naSala)}</div>
            <div className="text-[11px] text-[var(--fg-3)]">{coletado !== null ? `Leitura da API ${idadeTexto(live.coletadoEm, agoraMs)}` : 'Sem leitura da API ainda'}</div>
          </div>
          <div className="min-w-0">
            <div className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)]">Minuto da live</div>
            <div className="tabular text-2xl font-bold leading-tight text-[var(--fg)]">{ultimo ? minutoDe(ultimo.seg) : 'Sem dado'}</div>
            <div className="text-[11px] text-[var(--fg-3)]">Pico até agora: {numeroDe(marcos.pico?.espectadores ?? null)}{marcos.pico ? ` (min ${marcos.pico.minuto})` : ''}</div>
          </div>
          <div className="col-span-2 min-w-0">
            <div className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)]">{anterior ? `Contra ${rotuloAnterior}, no mesmo minuto` : 'Sem live anterior do mesmo tipo para comparar'}</div>
            {pos ? (
              <>
                <div className={'tabular text-2xl font-bold leading-tight ' + (pos.diferenca >= 0 ? 'text-[var(--green)]' : 'text-[var(--yellow)]')}>
                  {pos.diferenca >= 0 ? '+' : '-'}{numeroDe(Math.abs(pos.diferenca))} <span className="text-base">({rel !== null ? `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 }).format(rel * 100)}%` : 'Sem dado'})</span>
                </div>
                <div className="text-[11px] text-[var(--fg-3)]">Min {pos.minuto}: {numeroDe(pos.atual)} agora contra {numeroDe(pos.anterior)} naquela live.</div>
              </>
            ) : <div className="text-sm text-[var(--fg-3)]">{anterior ? 'Sem dado para comparar neste minuto.' : 'A comparação aparece quando houver uma live anterior com curva.'}</div>}
          </div>
        </div>
        <CurvaComparativa pontos={pontos} rotuloAtual={rotuloAtual} rotuloAnterior={rotuloAnterior}
          rotulo={`Espectadores por minuto: ${rotuloAtual} ao vivo${rotuloAnterior ? ` contra ${rotuloAnterior}` : ''}`} />
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--fg-2)]">
          <span className="inline-flex items-center gap-1.5"><span aria-hidden className="h-0.5 w-5 rounded bg-[var(--accent)]" />{rotuloAtual} (ao vivo)</span>
          {rotuloAnterior && <span className="inline-flex items-center gap-1.5"><span aria-hidden className="h-0.5 w-5 rounded bg-[var(--fg-3)]" />{rotuloAnterior} (já realizada)</span>}
        </div>
        <AvisoBloco erro={atual.erro ?? ref.erro} lidoEm={atual.lidoEm} agora={new Date(agoraMs)} />
        {atrasada && !atual.erro && <p role="status" className="text-xs text-[var(--yellow)]">Última leitura da API {idadeTexto(live.coletadoEm, agoraMs) ?? 'indisponível'}. Os números abaixo podem estar atrasados.</p>}
      </div>
    </SectionCard>
  );
}
