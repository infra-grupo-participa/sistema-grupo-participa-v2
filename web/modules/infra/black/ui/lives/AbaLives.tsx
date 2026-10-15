'use client';

// Aba "Lives": o caminho até a live da Black. Cronograma, ao vivo agora, evolução do pico, cartões das realizadas e o
// detalhe de cada live (?live=). Independente do recorte global: funil, período e canal não se aplicam às lives.
// Cada bloco tem a sua leitura (timeout, try/catch, segura o último valor). Contrato: docs/dashboard-black/README.md.
import { useState } from 'react';
import { Button, EmptyState, Loading, SectionCard, Toast, useFlash } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { FonteDadosBlack } from '../../application/ports';
import type { Live } from '../../domain/lives';
import type { Recorte } from '../../domain/tipos';
import { AvisoBloco } from '../pecas';
import { ModalCadastrar, ModalImportar, ModalRemover } from './AdminLives';
import { AoVivoAgora } from './AoVivoAgora';
import { CartoesRealizadas } from './CartoesRealizadas';
import { Cronograma } from './Cronograma';
import { DetalheLive } from './DetalheLive';
import { EvolucaoLives } from './EvolucaoLives';
import { useAgoraMs } from './pecas-lives';
import { useLeitura } from './useLeitura';

const RELEITURA_AO_VIVO_MS = 60_000;

type Janela = { qual: 'cadastrar' } | { qual: 'importar'; live: Live | null } | { qual: 'remover' } | null;

export function AbaLives({ fonte, chave, isMaster, videoId, irPara, versao }: {
  fonte: FonteDadosBlack; chave: string; isMaster: boolean; videoId: string | null; irPara: (m: Partial<Recorte>) => void; versao: number;
}) {
  const [vLocal, setVLocal] = useState(0);
  const [janela, setJanela] = useState<Janela>(null);
  const { toast, flash } = useFlash(4000);
  const agoraMs = useAgoraMs(fonte, 30_000);
  // A releitura de 5 min é do cliente (a prop `versao`); com live no ar, a aba relê sozinha a cada minuto.
  const [aoVivoVisto, setAoVivoVisto] = useState(false);
  const lista = useLeitura<Live[]>('as lives', () => fonte.lives(chave), `lives|${chave}`, aoVivoVisto ? RELEITURA_AO_VIVO_MS : null, versao * 1000 + vLocal);

  const lives = lista.data ?? [];
  const temAoVivo = lives.some((l) => l.situacao === 'ao_vivo');
  if (temAoVivo !== aoVivoVisto) setAoVivoVisto(temAoVivo);
  const aoVivo = lives.find((l) => l.situacao === 'ao_vivo') ?? null;
  const relogio = new Date(agoraMs);

  const abrir = (id: string) => irPara({ aba: 'lives', live: id });
  const voltar = () => irPara({ aba: 'lives', live: undefined });
  const feito = (msg: string) => { setJanela(null); setVLocal((v) => v + 1); flash(msg); };
  // A importação fica aberta para mostrar o resultado gravado; a lista só relê por trás.
  const importado = (msg: string) => { setVLocal((v) => v + 1); flash(msg); };
  const importar = (l: Live | null) => setJanela({ qual: 'importar', live: l });

  const alvo = videoId ? lives.find((l) => l.videoId === videoId) ?? null : null;

  const admin = isMaster && (
    <div className="flex flex-wrap items-center gap-2 max-md:[&_button]:min-h-11">
      <Button variant="ghost" size="sm" onClick={() => setJanela({ qual: 'cadastrar' })}><span className="inline-flex items-center gap-1.5"><Icon name="plus" size={14} />Cadastrar live</span></Button>
      <Button variant="ghost" size="sm" onClick={() => importar(alvo)} disabled={lives.length === 0}><span className="inline-flex items-center gap-1.5"><Icon name="download" size={14} />Importar CSV do Studio</span></Button>
      <Button variant="ghost" size="sm" onClick={() => setJanela({ qual: 'remover' })} disabled={lives.length === 0}><span className="inline-flex items-center gap-1.5"><Icon name="trash" size={14} />Remover live</span></Button>
    </div>
  );

  return (
    <div className="mt-4 space-y-4">
      {admin}
      <AvisoBloco erro={lista.erro} lidoEm={lista.lidoEm} agora={relogio} />
      {lista.aviso && !lista.erro && <p role="note" className="text-xs text-[var(--fg-3)]">Lives: {lista.aviso}.</p>}

      {lista.carregando ? <Loading label="Lendo as lives…" />
        : lista.data === null ? (
          <SectionCard title="Sem dado"><EmptyState icon="video" title="Não há lives para mostrar" hint={lista.erro ? 'A leitura falhou. Tente Atualizar.' : 'Nenhuma live cadastrada para este dashboard ainda.'} /></SectionCard>
        ) : videoId ? (
          alvo ? <DetalheLive live={alvo} lives={lives} fonte={fonte} chave={chave} agoraMs={agoraMs} relogio={relogio} onVoltar={voltar} isMaster={isMaster} onImportar={importar} />
            : (
              <SectionCard title="Live não encontrada">
                <EmptyState icon="video" title="Não achei essa live no cronograma" hint="O link pode estar errado ou a live foi removida." />
                <div className="mt-3 flex justify-center"><Button variant="ghost" size="sm" onClick={voltar}>Ver todas as lives</Button></div>
              </SectionCard>
            )
        ) : lives.length === 0 ? (
          <SectionCard title="Lives"><EmptyState icon="video" title="Nenhuma live cadastrada" hint={isMaster ? 'Use Cadastrar live para começar o cronograma.' : 'O cronograma ainda não foi cadastrado.'} /></SectionCard>
        ) : (
          <div className={'space-y-4 transition-opacity ' + (lista.erro ? 'opacity-60' : '')}>
            <Cronograma lives={lives} fonte={fonte} agoraMs={agoraMs} onAbrir={abrir} />
            {aoVivo && <AoVivoAgora live={aoVivo} lives={lives} fonte={fonte} chave={chave} agoraMs={agoraMs} onAbrir={abrir} />}
            <EvolucaoLives lives={lives} onAbrir={abrir} />
            <CartoesRealizadas lives={lives} onAbrir={abrir} isMaster={isMaster} onImportar={importar} />
          </div>
        )}

      {janela?.qual === 'cadastrar' && <ModalCadastrar fonte={fonte} chave={chave} onClose={() => setJanela(null)} onFeito={feito} />}
      {janela?.qual === 'importar' && <ModalImportar fonte={fonte} chave={chave} lives={lives} inicial={janela.live} onClose={() => setJanela(null)} onFeito={importado} />}
      {janela?.qual === 'remover' && <ModalRemover fonte={fonte} chave={chave} lives={lives} onClose={() => setJanela(null)} onFeito={feito} />}
      <Toast>{toast}</Toast>
    </div>
  );
}
