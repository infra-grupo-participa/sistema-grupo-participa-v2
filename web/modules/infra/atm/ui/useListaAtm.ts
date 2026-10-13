'use client';

import { useEffect, useRef, useSyncExternalStore } from 'react';
import type { Resultado } from '../infrastructure/atm-data';
import type { CarregadorListasAtm, EstadoListaAtm } from './carregador-listas';

/**
 * Liga um modal a uma lista do carregador. `chave` nula = não ler (modal fechado ou sem permissão): devolve `null`.
 * Lê quando a chave aparece ou muda (abrir o modal, trocar período ou "Incluir testes") e quando `versao` muda
 * (botão Atualizar, marcação de teste). Listas diferentes disparam juntas, cada uma no seu tempo.
 */
export function useListaAtm<T>(carregador: CarregadorListasAtm, chave: string | null, ler: () => Promise<Resultado<T[]>>, versao = 0): EstadoListaAtm<T> | null {
  const lerRef = useRef(ler);
  useEffect(() => { lerRef.current = ler; });
  const instantaneo = () => (chave ? carregador.estado<T>(chave) : null);
  const estado = useSyncExternalStore(carregador.inscrever, instantaneo, instantaneo);
  useEffect(() => {
    if (chave) void carregador.carregar<T>(chave, () => lerRef.current());
  }, [carregador, chave, versao]);
  return estado;
}
