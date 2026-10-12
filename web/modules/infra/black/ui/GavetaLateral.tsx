'use client';

// Esboço provisório: a gaveta entra com a aba Jornada.
import type { AlvoGaveta, DadosTela } from './contexto';

export function GavetaLateral({ d, alvo, onClose, onTrocar }: { d: DadosTela; alvo: AlvoGaveta | null; onClose: () => void; onTrocar: (a: AlvoGaveta) => void }) {
  void d; void alvo; void onClose; void onTrocar;
  return null;
}
