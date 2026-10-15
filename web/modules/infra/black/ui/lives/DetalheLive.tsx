'use client';

// Bloco E: detalhe de uma live. Pergunta: "onde a sala encheu, onde esvaziou e o que o público dizia naquele minuto?".
import { useMemo, useState } from 'react';
import { Button, EmptyState, KpiCard, Loading, SectionCard } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { FonteDadosBlack } from '../../application/ports';
import { DETALHE_VAZIO, duracaoTexto, fimEmPctDoPico, marcosDaCurva, mensagensPorMinuto, minutoDe, picoContraAnterior, type Live, type MinutoLive } from '../../domain/lives';
import { CurvaMinuto, marcadoresDe } from '../graficos-lives';
import { AvisoBloco, Chip } from '../pecas';
import { ChatLive, ComentariosLive } from './ChatLive';
import { dataCurta, dataHoraTexto, idadeTexto, numeroDe, pctDe, quando, tituloDe } from './formatos';
import { Miniatura, SeloSituacao, SeloTipo } from './pecas-lives';
import { useLeitura } from './useLeitura';

export function DetalheLive({ live, lives, fonte, chave, agoraMs, relogio, onVoltar, isMaster, onImportar }: {
  live: Live; lives: Live[]; fonte: FonteDadosBlack; chave: string; agoraMs: number; relogio: Date;
  onVoltar: () => void; isMaster: boolean; onImportar: (l: Live) => void;
}) {
  const [minuto, setMinuto] = useState<number | null>(null);
  const aoVivo = live.situacao === 'ao_vivo';
  const det = useLeitura('o detalhe da live', () => fonte.liveDetalhe(chave, live.videoId), `det|${chave}|${live.videoId}`, aoVivo ? 60_000 : null);
  const detalhe = det.data ?? DETALHE_VAZIO;

  // Sem o CSV do Studio a faixa de chat sai do chat guardado (só quando nenhum minuto trouxe o dado do CSV).
  const minutos = useMemo<MinutoLive[]>(() => {
    const ms = detalhe.minutos;
    if (ms.length === 0 || ms.some((m) => m.chat !== null) || detalhe.chat.length === 0) return ms;
    const porMin = mensagensPorMinuto(detalhe.chat);
    return ms.map((m) => ({ ...m, chat: porMin.get(minutoDe(m.seg)) ?? 0 }));
  }, [detalhe.minutos, detalhe.chat]);
  const marcos = useMemo(() => marcosDaCurva(minutos), [minutos]);
  const marcadores = marcadoresDe(marcos);
  const contra = picoContraAnterior(lives, live);
  const fim = fimEmPctDoPico(live);
  const emBreve = live.situacao === 'em_breve' || live.situacao === 'a_agendar';
  const semCurva = minutos.every((m) => m.espectadores === null);
  const origemApi = minutos.length > 0 && minutos.every((m) => m.origem === 'api');
  const link = `https://www.youtube.com/watch?v=${encodeURIComponent(live.videoId)}`;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="ghost" size="sm" onClick={onVoltar} className="min-h-11"><span className="inline-flex items-center gap-1.5"><Icon name="chevron-left" size={14} />Todas as lives</span></Button>
        {isMaster && !emBreve && <Button variant="ghost" size="sm" onClick={() => onImportar(live)} className="min-h-11"><span className="inline-flex items-center gap-1.5"><Icon name="download" size={14} />Importar CSV do Studio</span></Button>}
      </div>

      <SectionCard>
        <div className="grid gap-4 md:grid-cols-[16rem_1fr]">
          <div className="overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]"><Miniatura live={live} /></div>
          <div className="min-w-0 space-y-2">
            <div className="flex flex-wrap items-center gap-2"><SeloSituacao situacao={live.situacao} /><SeloTipo tipo={live.tipo} /></div>
            <h2 className="break-words text-xl font-bold leading-snug text-[var(--fg)]">{tituloDe(live)}</h2>
            <p className="text-sm text-[var(--fg-2)]">{quando(live.dataPrevista)}{live.inicio ? ` · começou ${dataHoraTexto(live.inicio)}` : ''}</p>
            <a href={link} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-[var(--accent)] hover:underline">
              <Icon name="link" size={14} />Abrir no YouTube
            </a>
          </div>
        </div>
      </SectionCard>

      <AvisoBloco erro={det.erro} lidoEm={det.lidoEm} agora={relogio} />
      {det.aviso && !det.erro && <p role="note" className="text-xs text-[var(--fg-3)]">{det.aviso}</p>}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <KpiCard label="Pico" value={numeroDe(live.pico)} hint={live.picoSeg !== null ? `min ${minutoDe(live.picoSeg)}${live.temStudio ? '' : ' · amostra da API'}` : 'Sem dado'}
          title="Maior número de espectadores simultâneos. Vem do CSV do Studio; sem ele, é a maior leitura que a API amostrou." />
        <KpiCard label="Sala cheia" value={live.salaCheiaSeg !== null ? `min ${minutoDe(live.salaCheiaSeg)}` : 'Sem dado'} bar="gray"
          hint="Primeiro minuto com 90% do pico ou mais" title="Primeiro minuto em que a sala chegou a 90% do pico." />
        <KpiCard label="Fim em % do pico" value={pctDe(fim)} bar="green"
          hint={live.ultimoEspectadores !== null && live.pico !== null ? `${numeroDe(live.ultimoEspectadores)} ÷ ${numeroDe(live.pico)}` : 'Sem a curva minuto a minuto'}
          title="Espectadores no último minuto ÷ pico. Quanto da sala ainda estava lá no fim." />
        <KpiCard label="Duração" value={duracaoTexto(live.duracaoSeg)} bar="purple" />
        <KpiCard label="Pico vs anterior" value={contra ? pctDe(contra.razao) : 'Sem dado'} bar="yellow"
          hint={contra ? `${numeroDe(contra.num)} ÷ ${numeroDe(contra.den)} (${dataCurta(contra.contra.dataPrevista)})` : 'Não há live anterior do mesmo tipo com pico'}
          title="Pico desta live ÷ pico da live anterior do mesmo tipo." />
        <KpiCard label="Chat" value={live.chatTotal === null ? 'Sem dado' : `${numeroDe(live.chatTotal)} msg`} bar="gray"
          hint={live.temStudio ? 'Mensagens (CSV do Studio)' : 'Mensagens lidas pela API, durante a live'}
          title={live.temStudio ? 'Soma da coluna de chat do CSV do Studio. O chat guardado, mais abaixo, é outra contagem.' : 'Sem o CSV do Studio, é a contagem das mensagens que a API trouxe dentro da live.'} />
        <KpiCard label="Reações" value={numeroDe(live.reacoesTotal)} bar="purple" hint={live.temStudio ? 'CSV do Studio' : 'A API não traz reações'} />
        <KpiCard label="Views · likes · comentários" bar="none" value={`${numeroDe(live.views)} · ${numeroDe(live.likes)} · ${numeroDe(live.comentarios)}`}
          hint={live.coletadoEm ? `API do YouTube, lida ${idadeTexto(live.coletadoEm, agoraMs)}` : 'Sem leitura da API'}
          title="Números públicos da API do YouTube. As views contam também o replay." valueClassName="text-base" />
      </div>

      <SectionCard title="Espectadores minuto a minuto" subtitle="A curva é a sala; a faixa de baixo é o chat e as reações no mesmo eixo de tempo. Clique num ponto para filtrar o chat daquele minuto.">
        {det.carregando ? <Loading label="Lendo a curva…" />
          : emBreve ? <EmptyState icon="clock" title={live.situacao === 'em_breve' ? 'Em breve' : 'A agendar'} hint={live.situacao === 'em_breve' ? 'A live ainda não começou. A curva aparece quando ela estiver no ar.' : 'A API do YouTube ainda não encontrou o vídeo desta live.'} />
          : semCurva ? <EmptyState icon="chart" title="Sem a curva minuto a minuto" hint={isMaster ? 'Importe o CSV do Studio desta live para ver a sala minuto a minuto.' : 'O CSV do Studio desta live ainda não foi importado.'} />
          : (
            <div className="space-y-3">
              {origemApi && <p role="note" className="text-xs text-[var(--yellow)]">Sem o CSV do Studio: os pontos são amostras da API e podem faltar minutos.</p>}
              <CurvaMinuto minutos={minutos} marcos={marcos} selecionado={minuto} onSelecionar={setMinuto}
                rotulo={`Espectadores por minuto: ${tituloDe(live)}`} />
              {marcadores.length > 0 && (
                <div className="flex flex-wrap gap-1.5" role="group" aria-label="Ir para um marco da curva">
                  {marcadores.map((m) => <Chip key={m.id} ativo={minuto === minutoDe(m.seg)} onClick={() => setMinuto(minutoDe(m.seg))} title={m.rotulo}>{m.letra}: {m.rotulo}</Chip>)}
                </div>
              )}
            </div>
          )}
      </SectionCard>

      {!emBreve && (
        <>
          <ChatLive chat={detalhe.chat} minuto={minuto} onLimparMinuto={() => setMinuto(null)} guardado={live.chatGuardado} />
          <ComentariosLive comentarios={detalhe.comentarios} total={live.comentarios} />
        </>
      )}
    </div>
  );
}
