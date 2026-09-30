// Teclado das abas (padrão WAI-ARIA Tabs, ativação automática): ←/→ circulam, Home/End vão às pontas.
// Qualquer outra tecla (Esc incluído) devolve null e segue borbulhando — o Esc continua fechando a gaveta.
export function indiceAbaPorTecla(tecla: string, atual: number, total: number): number | null {
  if (total <= 0) return null;
  switch (tecla) {
    case 'ArrowRight': return (atual + 1) % total;
    case 'ArrowLeft': return (atual - 1 + total) % total;
    case 'Home': return 0;
    case 'End': return total - 1;
    default: return null;
  }
}

/** Ids casados aba ↔ painel, para `aria-controls` / `aria-labelledby`. */
export function idsAba(idBase: string, k: string): { tab: string; panel: string } {
  return { tab: `${idBase}-tab-${k}`, panel: `${idBase}-panel-${k}` };
}

export function rotuloPendencias(n: number): string {
  return n === 1 ? '1 pendência' : `${n} pendências`;
}
