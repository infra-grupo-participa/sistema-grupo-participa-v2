'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { aplicarLeitura, estadoInicialRelatorio, type EstadoRelatorioMiami } from '../application/relatorio-miami-estado';
import { carregarRelatorioMiami } from '../infrastructure/relatorio-miami-data';

export const INTERVALO_RELATORIO_MS = 60_000;

/**
 * Lê a cópia da aba Relatório e a mantém atualizada enquanto `ativo` (alguma das abas que a usam está aberta).
 * Polling leve: manda o md5 da cópia que já tem, então cópia igual volta sem conteúdo e não rebaixa a tela.
 * Só roda com a aba do navegador visível e para sozinho em falha permanente (ex.: função ainda fora do banco).
 */
export function useRelatorioMiami(chave: string, ativo: boolean) {
  const [estado, setEstado] = useState<EstadoRelatorioMiami>(() => estadoInicialRelatorio(chave));
  const ref = useRef<EstadoRelatorioMiami>(estado);
  const emAndamento = useRef<Promise<void> | null>(null);
  const [reinicio, setReinicio] = useState(0);

  const ler = useCallback((): Promise<void> => {
    if (emAndamento.current) return emAndamento.current;
    const base = ref.current.chave === chave ? ref.current : estadoInicialRelatorio(chave);
    const tarefa = carregarRelatorioMiami(chave, base.conteudo ? base.md5 : null).then((lida) => {
      const proximo = aplicarLeitura(base, lida, Date.now());
      ref.current = proximo;
      setEstado(proximo);
    }).finally(() => { emAndamento.current = null; });
    emAndamento.current = tarefa;
    return tarefa;
  }, [chave]);

  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const agendar = () => {
      if (timer) clearTimeout(timer);
      if (vivo && document.visibilityState === 'visible' && !ref.current.permanente) timer = setTimeout(() => { void rodar(); }, INTERVALO_RELATORIO_MS);
    };
    const rodar = async () => {
      if (timer) clearTimeout(timer);
      await ler();
      if (vivo) agendar();
    };
    const aoMudarVisibilidade = () => {
      if (timer) clearTimeout(timer);
      if (document.visibilityState === 'visible') void rodar();
    };
    void rodar();
    document.addEventListener('visibilitychange', aoMudarVisibilidade);
    return () => {
      vivo = false;
      if (timer) clearTimeout(timer);
      document.removeEventListener('visibilitychange', aoMudarVisibilidade);
    };
  }, [ativo, ler, reinicio]);

  // Troca de chave: o estado de outra chave nunca aparece.
  const visivel = estado.chave === chave ? estado : estadoInicialRelatorio(chave);
  // Atualizar à mão também religa o polling que uma falha permanente tinha parado.
  const atualizar = useCallback((): Promise<void> => {
    const lendo = ler();
    setReinicio((n) => n + 1);
    return lendo;
  }, [ler]);
  return { estado: visivel, atualizar };
}
