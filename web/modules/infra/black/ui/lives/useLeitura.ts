'use client';

// Leitura de um bloco da aba Lives: timeout de 15 s, try/catch, erro segura a última leitura (a tela esmaece e mostra a
// idade), releitura opcional enquanto a aba do navegador está visível. Troca de `marca` zera o que estava na tela; `gatilho` só pede nova leitura e mantém o que já estava (usado depois de uma escrita).
import { useEffect, useRef, useState } from 'react';
import type { Resultado } from '../../domain/tipos';

const TEMPO_LIMITE_MS = 15_000;

export interface Leitura<T> {
  data: T | null; semDado: boolean; erro: string | null; aviso: string | null; lidoEm: Date | null;
  /** true até a primeira resposta (ou falha) desta marca. */
  carregando: boolean;
}

interface Estado<T> extends Leitura<T> { marca: string }
const inicial = <T,>(marca: string): Estado<T> => ({ marca, data: null, semDado: false, erro: null, aviso: null, lidoEm: null, carregando: true });

function comTempo<T>(p: Promise<T>): Promise<T> {
  return new Promise<T>((ok, falha) => {
    const t = setTimeout(() => falha(new Error('tempo esgotado')), TEMPO_LIMITE_MS);
    p.then((v) => { clearTimeout(t); ok(v); }, (e) => { clearTimeout(t); falha(e); });
  });
}

export function useLeitura<T>(nome: string, ler: (() => Promise<Resultado<T>>) | null, marca: string, intervaloMs: number | null, gatilho = 0): Leitura<T> {
  const [estado, setEstado] = useState<Estado<T>>(() => inicial<T>(marca));
  const lerRef = useRef(ler);
  useEffect(() => { lerRef.current = ler; });
  const ativo = ler !== null;

  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    const executar = async () => {
      const f = lerRef.current;
      if (!f) return;
      try {
        const r = await comTempo(f());
        if (!vivo) return;
        if (r.erro) setEstado((e) => ({ ...(e.marca === marca ? e : inicial<T>(marca)), marca, erro: `Falha ao ler ${nome}: ${r.erro}`, carregando: false }));
        else setEstado({ marca, data: r.data, semDado: r.semDado, erro: null, aviso: r.aviso ?? null, lidoEm: new Date(), carregando: false });
      } catch (e) {
        if (!vivo) return;
        const motivo = e instanceof Error && e.message === 'tempo esgotado' ? 'tempo esgotado' : 'erro na leitura';
        setEstado((s) => ({ ...(s.marca === marca ? s : inicial<T>(marca)), marca, erro: `Falha ao ler ${nome} (${motivo}).`, carregando: false }));
      }
    };
    void executar();
    const id = intervaloMs ? window.setInterval(() => { if (document.visibilityState === 'visible') void executar(); }, intervaloMs) : null;
    return () => { vivo = false; if (id !== null) window.clearInterval(id); };
  }, [ativo, marca, intervaloMs, nome, gatilho]);

  return estado.marca === marca ? estado : inicial<T>(marca);
}
