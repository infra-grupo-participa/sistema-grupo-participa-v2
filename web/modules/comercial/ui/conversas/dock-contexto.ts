'use client';

// Contexto do dock de conversa do Funil (sem dependências: comum.tsx e o card do funil leem daqui sem ciclo de import).
import { createContext, useContext } from 'react';

export interface DockApi { abrir: (contatoId: string) => void }
export const DockContexto = createContext<DockApi | null>(null);

/** Dentro do Funil: abre a conversa no dock. null = fora do Funil (o botão navega para a tela de Conversas). */
export function useDockConversa(): DockApi | null {
  return useContext(DockContexto);
}
