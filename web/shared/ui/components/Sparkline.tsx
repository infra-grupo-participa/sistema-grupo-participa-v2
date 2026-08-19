// Sparkline — não existia no design system (Faturamento é o 1º consumidor).
// SVG inline puro, sem lib de gráfico nova (bundle) — regra do módulo.
// Decorativo por padrão (aria-hidden): o número ao lado do gráfico já carrega
// a informação; o traço é reforço visual, não fonte primária do dado.

export function Sparkline({ valores, width = 72, height = 24, tone = 'var(--fg-3)' }: {
  valores: number[];
  width?: number;
  height?: number;
  tone?: string;
}) {
  if (valores.length < 2) return null;
  const min = Math.min(...valores);
  const max = Math.max(...valores);
  const range = max - min || 1;
  const stepX = width / (valores.length - 1);
  const pad = 2;
  const pontos = valores.map((v, i) => {
    const x = i * stepX;
    const y = pad + (1 - (v - min) / range) * (height - pad * 2);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  });
  const ultimo = pontos[pontos.length - 1].split(',');

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} aria-hidden="true" className="shrink-0">
      <polyline points={pontos.join(' ')} fill="none" stroke={tone} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={ultimo[0]} cy={ultimo[1]} r={1.8} fill={tone} />
    </svg>
  );
}
