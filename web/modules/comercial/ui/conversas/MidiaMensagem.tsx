'use client';

// Arquivo de uma mensagem do WhatsApp (migration 20261007140044): imagem (miniatura → grande), áudio e vídeo (player),
// documento (nome, tamanho, abrir). O arquivo fica no bucket privado crm-midia; a URL é assinada na hora (10 min) e só
// sai para quem pode ver a conversa (policy do Storage). Mensagem antiga sem arquivo não passa por aqui.
import { useEffect, useState, useSyncExternalStore } from 'react';
import { Modal, Spinner } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { avisoMidia, ehOggOpus, fmtTamanho, nomeArquivo, tipoMidia } from '../../domain/midia';
import type { Mensagem } from '../../domain/types';
import { repo } from '../repositorio';

// URL assinada vale 10 min no Storage; reaproveita por 8 (cada tela que abre a conversa não pede de novo).
const REUSO_MS = 8 * 60 * 1000;
const cache = new Map<string, { url: string; ate: number }>();
const pedidos = new Map<string, Promise<string | null>>();

function urlAssinada(caminho: string): Promise<string | null> {
  const c = cache.get(caminho);
  if (c && c.ate > Date.now()) return Promise.resolve(c.url);
  const emCurso = pedidos.get(caminho);
  if (emCurso) return emCurso;
  const p = repo.urlMidia(caminho)
    .then((url) => {
      if (url) cache.set(caminho, { url, ate: Date.now() + REUSO_MS });
      return url;
    })
    .catch(() => null)
    .finally(() => pedidos.delete(caminho));
  pedidos.set(caminho, p);
  return p;
}

function useUrlMidia(caminho: string | null) {
  const [estado, setEstado] = useState<{ caminho: string | null; url: string | null; falhou: boolean }>({ caminho: null, url: null, falhou: false });
  useEffect(() => {
    if (!caminho) return;
    let vivo = true;
    urlAssinada(caminho).then((url) => { if (vivo) setEstado({ caminho, url, falhou: !url }); });
    return () => { vivo = false; };
  }, [caminho]);
  const atual = estado.caminho === caminho;
  return { url: atual ? estado.url : null, falhou: atual && estado.falhou, carregando: !!caminho && !atual };
}

// O navegador toca ogg/opus? (Safari antigo não.) Lido do DOM uma vez; no servidor assume que toca.
let tocaOggMemo: boolean | null = null;
function tocaOgg(): boolean {
  if (tocaOggMemo === null) {
    const a = document.createElement('audio');
    tocaOggMemo = a.canPlayType('audio/ogg; codecs="opus"') !== '' || a.canPlayType('audio/ogg') !== '';
  }
  return tocaOggMemo;
}
const semAssinatura = () => () => {};
function useSemOgg(mime: string | null): boolean {
  const toca = useSyncExternalStore(semAssinatura, tocaOgg, () => true);
  return ehOggOpus(mime) && !toca;
}

const LINK = 'inline-flex items-center gap-1 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:underline';

export function MidiaMensagem({ m, compacto = false }: { m: Mensagem; compacto?: boolean }) {
  const tipo = tipoMidia(m);
  const midia = m.midia ?? null;
  const { url, falhou, carregando } = useUrlMidia(midia?.status === 'ok' ? midia.caminho : null);
  const semOgg = useSemOgg(tipo === 'audio' ? midia?.mime ?? null : null);
  const [grande, setGrande] = useState(false);
  if (!tipo || !midia) return null;
  const nome = nomeArquivo(m);
  const tamanho = fmtTamanho(midia.tamanho);

  const aviso = avisoMidia(midia);
  if (aviso) {
    return (
      <div className="mb-1 flex items-start gap-1.5 text-xs text-[var(--fg-2)]">
        <Icon name="alert" size={13} className="mt-0.5 shrink-0 text-[var(--yellow)]" /> <span>{aviso}</span>
      </div>
    );
  }
  if (midia.status === 'pendente' || carregando) {
    return (
      <div className="mb-1 inline-flex items-center gap-2 text-xs text-[var(--fg-3)]" aria-busy="true">
        <Spinner size={14} /> {midia.status === 'pendente' ? 'Recebendo arquivo…' : 'Carregando arquivo…'}
      </div>
    );
  }
  if (falhou || !url) {
    return (
      <div className="mb-1 flex items-start gap-1.5 text-xs text-[var(--fg-2)]">
        <Icon name="lock" size={13} className="mt-0.5 shrink-0 text-[var(--fg-3)]" /> <span>Arquivo indisponível para o seu usuário.</span>
      </div>
    );
  }

  if (tipo === 'imagem') {
    return (
      <>
        <button
          type="button"
          onClick={() => setGrande(true)}
          className="mb-1 block overflow-hidden rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]"
          aria-label={`Abrir imagem ${nome}`}
          title="Abrir imagem"
        >
          {/* eslint-disable-next-line @next/next/no-img-element -- URL assinada temporária do Storage, fora do otimizador do Next */}
          <img src={url} alt={nome} loading="lazy" className={`block w-auto max-w-full object-cover ${compacto ? 'max-h-32' : 'max-h-60'}`} />
        </button>
        {grande && (
          <Modal onClose={() => setGrande(false)} title={nome} width="max-w-4xl">
            <div className="space-y-3">
              {/* eslint-disable-next-line @next/next/no-img-element -- idem */}
              <img src={url} alt={nome} className="mx-auto block max-h-[70vh] w-auto max-w-full rounded-[var(--r-md)]" />
              <div className="text-right">
                <a href={url} target="_blank" rel="noopener noreferrer" className={LINK}><Icon name="download" size={12} /> Abrir original</a>
              </div>
            </div>
          </Modal>
        )}
      </>
    );
  }

  if (tipo === 'audio') {
    if (semOgg) {
      return (
        <div className="mb-1 space-y-1">
          <p className="text-xs text-[var(--fg-2)]">Este navegador não toca o áudio do WhatsApp (OGG). Baixe para ouvir.</p>
          <a href={url} target="_blank" rel="noopener noreferrer" className={LINK}><Icon name="download" size={12} /> Baixar áudio{tamanho ? ` (${tamanho})` : ''}</a>
        </div>
      );
    }
    return <audio controls preload="metadata" src={url} className="mb-1 block w-full min-w-[220px] max-w-[320px]" aria-label="Áudio da mensagem" />;
  }

  if (tipo === 'video') {
    return (
      <video controls preload="metadata" src={url} className={`mb-1 block w-full max-w-[360px] rounded-[var(--r-md)] bg-[var(--surface-3)] ${compacto ? 'max-h-40' : 'max-h-72'}`}>
        <a href={url} target="_blank" rel="noopener noreferrer">Baixar vídeo</a>
      </video>
    );
  }

  // documento
  return (
    <div className="mb-1 flex min-w-0 items-center gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2">
      <Icon name="file" size={20} className="shrink-0 text-[var(--fg-3)]" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium text-[var(--fg)]" title={nome}>{nome}</div>
        {tamanho && <div className="text-[11px] text-[var(--fg-3)] tabular">{tamanho}</div>}
      </div>
      <a href={url} target="_blank" rel="noopener noreferrer" className={`${LINK} shrink-0`} aria-label={`Abrir ${nome}`}>
        <Icon name="download" size={12} /> Abrir
      </a>
    </div>
  );
}
