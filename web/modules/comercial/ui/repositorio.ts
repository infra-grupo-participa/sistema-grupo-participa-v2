'use client';

// Ponto único de troca da fonte de dados do Comercial (mesmo contrato `ComercialRepository`; nenhuma tela muda).
// NEXT_PUBLIC_COMERCIAL_FONTE=supabase → banco real (F1: só leitura). Ausente/inválido → demonstração em memória.
import { useCallback, useEffect, useRef, useState } from 'react';
import { publicEnv } from '@/shared/infrastructure/config/env';
import type { ComercialRepository } from '../application/ports';
import { idsUnicos } from '../domain/contatos';
import type { Contato } from '../domain/types';
import { MockComercialRepository } from '../infrastructure/mock-comercial.repository';
import { SupabaseComercialRepository } from '../infrastructure/supabase-comercial.repository';

export const repo: ComercialRepository = publicEnv.comercialFonte === 'supabase'
  ? new SupabaseComercialRepository()
  : new MockComercialRepository();

/** true enquanto a fonte for a de demonstração (mostra o aviso nas telas). */
export const MODO_DEMONSTRACAO = publicEnv.comercialFonte === 'mock';

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

/**
 * Só os contatos que a tela mostra (ids dos negócios, atividades, conversas…), numa chamada (`crm_contatos_por_ids`),
 * em vez da lista inteira. `ids` nulo = a fonte dos ids ainda está carregando (fica carregando também).
 */
export function useContatosPorIds(ids: (string | null | undefined)[] | null | undefined) {
  const chave = ids ? idsUnicos(ids).sort() : null;
  return useDados<Contato[] | null>(async () => (chave ? repo.contatosPorIds(chave) : null), [chave]);
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
