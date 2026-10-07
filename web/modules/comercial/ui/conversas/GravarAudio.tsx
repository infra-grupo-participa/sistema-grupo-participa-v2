'use client';

// Microfone da conversa (migration 20261007s): grava no navegador (MediaRecorder), mostra o tempo, deixa ouvir, regravar
// ou descartar, e envia. O WhatsApp só mostra como nota de voz o ogg/opus: Firefox grava ogg direto; Chrome e Safari novo
// gravam webm/opus, que vira ogg por remux (domain/ogg-opus.ts, sem reencodar); Safari antigo grava m4a (sai como áudio
// comum). Para sozinho em 5 min. Só aparece com a janela de 24 h aberta; o banco valida tudo de novo.
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  AVISO_SEM_SUPORTE, DURACAO_MAX_MS, erroMicrofone, escolherFormato, fmtDuracao, planoAudio, validarAudio,
} from '../../domain/audio';
import { fmtTamanho } from '../../domain/midia';
import { ErroAudio, webmOpusParaOgg } from '../../domain/ogg-opus';
import { avisarMudanca, repo } from '../repositorio';

function suportaGravacao(): boolean {
  return typeof window !== 'undefined' && typeof window.MediaRecorder !== 'undefined'
    && typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getUserMedia;
}

export function BotaoGravarAudio({ contatoId, nomeContato, desabilitado, flash }: {
  contatoId: string; nomeContato: string; desabilitado?: boolean; flash: (m: string) => void;
}) {
  const [aberto, setAberto] = useState(false);
  const abrir = () => {
    if (!suportaGravacao()) { flash(AVISO_SEM_SUPORTE); return; }
    setAberto(true);
  };
  return (
    <>
      <Button
        variant="ghost"
        size="md"
        className="!px-3"
        disabled={desabilitado}
        onClick={abrir}
        aria-label="Gravar áudio"
        title="Gravar áudio"
      >
        <Icon name="mic" size={15} />
      </Button>
      {aberto && <ModalGravar contatoId={contatoId} nomeContato={nomeContato} flash={flash} onFechar={() => setAberto(false)} />}
    </>
  );
}

type Gravacao = { blob: Blob; url: string; duracaoMs: number; mime: string };
type Fase = 'pedindo' | 'gravando' | 'pronto' | 'enviando' | 'erro';

function ModalGravar({ contatoId, nomeContato, flash, onFechar }: {
  contatoId: string; nomeContato: string; flash: (m: string) => void; onFechar: () => void;
}) {
  const [fase, setFase] = useState<Fase>('pedindo');
  const [erro, setErro] = useState<string | null>(null);
  const [decorrido, setDecorrido] = useState(0);
  const [gravacao, setGravacao] = useState<Gravacao | null>(null);

  const stream = useRef<MediaStream | null>(null);
  const gravador = useRef<MediaRecorder | null>(null);
  const partes = useRef<Blob[]>([]);
  const inicio = useRef(0);
  const relogio = useRef<ReturnType<typeof setInterval> | null>(null);
  const descartando = useRef(false);
  const urlAtual = useRef<string | null>(null);
  const vivo = useRef(true);
  const geracao = useRef(0);   // cada iniciar() tem a sua; resposta atrasada do microfone de uma geração velha é descartada

  const soltarMicrofone = useCallback(() => {
    if (relogio.current) { clearInterval(relogio.current); relogio.current = null; }
    stream.current?.getTracks().forEach((t) => t.stop());
    stream.current = null;
  }, []);

  const liberarUrl = useCallback(() => {
    if (urlAtual.current) URL.revokeObjectURL(urlAtual.current);
    urlAtual.current = null;
  }, []);

  const parar = useCallback(() => {
    const g = gravador.current;
    if (g && g.state !== 'inactive') g.stop();
  }, []);

  // só mexe em estado depois do await (o estado inicial já é 'pedindo'; regravar/tentar de novo zeram antes de chamar)
  const iniciar = useCallback(async () => {
    descartando.current = false;
    const minha = ++geracao.current;
    let s: MediaStream;
    try {
      s = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    } catch (e) {
      if (!vivo.current || minha !== geracao.current) return;
      setErro(erroMicrofone(e instanceof DOMException ? e.name : null));
      setFase('erro');
      return;
    }
    if (!vivo.current || minha !== geracao.current) { s.getTracks().forEach((t) => t.stop()); return; }
    stream.current = s;
    const formato = escolherFormato((m) => MediaRecorder.isTypeSupported(m));
    let g: MediaRecorder;
    try {
      g = new MediaRecorder(s, formato ? { mimeType: formato, audioBitsPerSecond: 32000 } : undefined);
    } catch {
      soltarMicrofone();
      setErro(AVISO_SEM_SUPORTE);
      setFase('erro');
      return;
    }
    gravador.current = g;
    partes.current = [];
    g.ondataavailable = (ev) => { if (ev.data && ev.data.size > 0) partes.current.push(ev.data); };
    g.onstop = () => {
      const duracaoMs = Date.now() - inicio.current;
      soltarMicrofone();
      gravador.current = null;
      if (descartando.current || !vivo.current) return;
      const mime = g.mimeType || formato || partes.current[0]?.type || '';
      const blob = new Blob(partes.current, { type: mime });
      liberarUrl();
      urlAtual.current = URL.createObjectURL(blob);
      setGravacao({ blob, url: urlAtual.current, duracaoMs, mime });
      setFase('pronto');
    };
    inicio.current = Date.now();
    g.start(1000);
    setDecorrido(0);
    setFase('gravando');
    relogio.current = setInterval(() => {
      const d = Date.now() - inicio.current;
      setDecorrido(d);
      if (d >= DURACAO_MAX_MS) parar();   // para sozinho em 5 min
    }, 250);
  }, [liberarUrl, parar, soltarMicrofone]);

  // ao fechar: invalida o pedido de microfone em andamento, para o gravador, solta o microfone e a URL local
  const encerrar = useCallback(() => {
    vivo.current = false;
    geracao.current++;
    descartando.current = true;
    const g = gravador.current;
    if (g && g.state !== 'inactive') g.stop();
    soltarMicrofone();
    liberarUrl();
  }, [liberarUrl, soltarMicrofone]);

  // abre já gravando
  useEffect(() => {
    vivo.current = true;
    const t = setTimeout(() => { void iniciar(); }, 0);
    return () => { clearTimeout(t); encerrar(); };
  }, [iniciar, encerrar]);

  const reiniciar = () => {
    setErro(null);
    setDecorrido(0);
    setFase('pedindo');
    void iniciar();
  };

  const descartar = () => {
    if (fase === 'enviando') return;
    descartando.current = true;
    parar();
    soltarMicrofone();
    liberarUrl();
    onFechar();
  };

  const regravar = () => {
    liberarUrl();
    setGravacao(null);
    reiniciar();
  };

  const plano = gravacao ? planoAudio(gravacao.mime) : null;

  const enviar = async () => {
    if (!gravacao || fase === 'enviando') return;
    if (!plano) { flash('Este navegador gravou num formato que o WhatsApp não aceita. Use Chrome, Edge, Firefox ou Safari atualizados.'); return; }
    setFase('enviando');
    let arquivo: Blob;
    try {
      if (plano.acao === 'remux') {
        const r = webmOpusParaOgg(new Uint8Array(await gravacao.blob.arrayBuffer()));
        arquivo = new Blob([r.ogg as BlobPart], { type: plano.mime });
      } else {
        arquivo = new Blob([gravacao.blob], { type: plano.mime });
      }
    } catch (e) {
      setFase('pronto');
      flash(e instanceof ErroAudio ? `${e.message} Grave de novo.` : 'Não foi possível preparar o áudio. Grave de novo.');
      return;
    }
    const v = validarAudio({ tamanho: arquivo.size, duracaoMs: gravacao.duracaoMs });
    if (!v.ok) { setFase('pronto'); flash(v.msg); return; }
    const r = await repo.enviarAudio(contatoId, arquivo, { mime: plano.mime, ext: plano.ext });
    if (!vivo.current) return;
    if (!r.ok) { setFase('pronto'); flash(r.msg ?? 'Não foi possível enviar o áudio.'); return; }
    flash(r.msg ?? 'Áudio na fila de envio.');
    avisarMudanca();
    onFechar();
  };

  const rodape = (() => {
    if (fase === 'gravando') {
      return (
        <>
          <Button variant="ghost" size="sm" onClick={descartar}>Descartar</Button>
          <Button size="sm" onClick={parar}><Icon name="pause" size={14} /> Parar</Button>
        </>
      );
    }
    if (fase === 'pronto' || fase === 'enviando') {
      const enviando = fase === 'enviando';
      return (
        <>
          <Button variant="ghost" size="sm" onClick={descartar} disabled={enviando}>Descartar</Button>
          <Button variant="ghost" size="sm" onClick={regravar} disabled={enviando}><Icon name="rotate" size={14} /> Regravar</Button>
          <Button size="sm" onClick={enviar} disabled={enviando || !plano}>
            <Icon name="send" size={14} /> {enviando ? 'Enviando…' : 'Enviar'}
          </Button>
        </>
      );
    }
    if (fase === 'erro') {
      return (
        <>
          <Button variant="ghost" size="sm" onClick={onFechar}>Fechar</Button>
          <Button size="sm" onClick={reiniciar}>Tentar de novo</Button>
        </>
      );
    }
    return <Button variant="ghost" size="sm" onClick={descartar}>Cancelar</Button>;
  })();

  return (
    <Modal onClose={descartar} title={`Áudio para ${nomeContato}`} width="max-w-md" footer={rodape}>
      <div className="space-y-3" aria-live="polite">
        {fase === 'pedindo' && (
          <p className="text-sm text-[var(--fg-2)]">Pedindo acesso ao microfone… Se o navegador perguntar, clique em Permitir.</p>
        )}
        {fase === 'gravando' && (
          <div className="flex items-center gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-3">
            <span className="block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--red)] animate-pulse" aria-hidden="true" />
            <span className="text-sm font-medium text-[var(--fg)]">Gravando</span>
            <span className="ml-auto text-sm tabular text-[var(--fg-2)]" role="timer">
              {fmtDuracao(decorrido)} <span className="text-[var(--fg-3)]">/ {fmtDuracao(DURACAO_MAX_MS)}</span>
            </span>
          </div>
        )}
        {(fase === 'pronto' || fase === 'enviando') && gravacao && (
          <>
            <audio controls preload="metadata" src={gravacao.url} className="block w-full" aria-label="Ouvir a gravação" />
            <p className="text-[11px] text-[var(--fg-3)] tabular">
              {fmtDuracao(gravacao.duracaoMs)} · {fmtTamanho(gravacao.blob.size)}
              {plano && !plano.voz && ' · chega como arquivo de áudio (este navegador não grava no formato de voz do WhatsApp)'}
            </p>
            {!plano && (
              <p className="text-xs text-[var(--red)]">Formato de gravação não aceito pelo WhatsApp. Use Chrome, Edge, Firefox ou Safari atualizados.</p>
            )}
          </>
        )}
        {fase === 'erro' && erro && <p className="text-sm text-[var(--red)]">{erro}</p>}
      </div>
    </Modal>
  );
}
