// Miniatura de demonstração: o anúncio fictício não tem imagem. Desenho só com tokens, com "FICTÍCIO" escrito,
// para ninguém confundir com peça real. A cor varia pelo id (estável entre renderizações).
const CORES = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--green)', 'var(--yellow)'];

function indice(id: string) {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return h % CORES.length;
}

export function MiniaturaFicticia({ id, formato, className = '' }: { id: string; formato: 'video' | 'imagem' | null; className?: string }) {
  const cor = CORES[indice(id)];
  return (
    <svg viewBox="0 0 160 100" className={'block h-auto w-full rounded-[var(--r-md)] ' + className} role="img" aria-label="Miniatura fictícia (demonstração)">
      <rect width="160" height="100" fill="var(--surface-3)" />
      <circle cx="128" cy="22" r="34" fill={cor} opacity="0.18" />
      <rect x="12" y="62" width="96" height="8" rx="4" fill={cor} opacity="0.55" />
      <rect x="12" y="76" width="64" height="6" rx="3" fill="var(--fg-3)" opacity="0.5" />
      {formato === 'video' && (
        <g transform="translate(80 38)">
          <circle r="15" fill="var(--surface-1)" opacity="0.85" />
          <path d="M-5 -8 L9 0 L-5 8 z" fill={cor} />
        </g>
      )}
      <text x="12" y="20" className="fill-[var(--fg-2)] text-[10px] font-semibold uppercase tracking-wide">FICTÍCIO</text>
    </svg>
  );
}
