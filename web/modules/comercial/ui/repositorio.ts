'use client';

// Ponto único de troca da fonte de dados do Comercial.
// HOJE: dados de demonstração em memória. Quando o backend existir, trocar a linha abaixo por
// `new SupabaseComercialRepository()` (mesmo contrato `ComercialRepository`). Nenhuma tela muda.
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ComercialRepository } from '../application/ports';
import { MockComercialRepository } from '../infrastructure/mock-comercial.repository';

export const repo: ComercialRepository = new MockComercialRepository();

/** true enquanto a fonte for a de demonstração (mostra o aviso nas telas). */
export const MODO_DEMONSTRACAO = true;

// Aviso de mudança: depois de uma escrita, toda tela aberta recarrega o que mostra.
const ouvintes = new Set<() => void>();
export function avisarMudanca() {
  ouvintes.forEach((f) => f());
}

/**
 * Carrega dado do repositório e recarrega quando alguém avisar mudança.
 * `carregar` deve ser estável (useCallback) ou depender só de `deps`.
 */
export function useDados<T>(carregar: () => Promise<T>, deps: unknown[] = []) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const vivo = useRef(true);
  // A função mais recente fica num ref; `deps` (serializado) decide quando buscar de novo.
  const fnRef = useRef(carregar);
  useEffect(() => { fnRef.current = carregar; });
  const chave = JSON.stringify(deps);

  const recarregar = useCallback(async () => {
    try {
      const d = await fnRef.current();
      if (vivo.current) { setDados(d); setErro(null); }
    } catch (e) {
      if (vivo.current) setErro(e instanceof Error ? e.message : 'Não foi possível carregar.');
    }
  }, []);

  useEffect(() => {
    vivo.current = true;
    // Busca inicial e assinatura de mudanças (sistema externo).
    recarregar();
    ouvintes.add(recarregar);
    return () => { vivo.current = false; ouvintes.delete(recarregar); };
  }, [recarregar, chave]);

  return { dados, erro, recarregar };
}

/** Relógio que anda a cada 30 s: os alertas de tempo mudam sem recarregar a página. */
export function useAgora(intervaloMs = 30_000): Date {
  const [agora, setAgora] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setAgora(new Date()), intervaloMs);
    return () => clearInterval(t);
  }, [intervaloMs]);
  return agora;
}
