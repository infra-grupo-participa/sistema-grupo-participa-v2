import type { DiaPresencial } from '../../domain/presencial';
import { dataBR } from '../formato';

export function SerieDiaria({ dias }: { dias: DiaPresencial[] }) {
  const max = Math.max(1, ...dias.flatMap((d) => [d.pre_checkout, d.pedidos, d.vendas]));
  const altura = 120, largura = Math.max(320, dias.length * 34), passo = largura / Math.max(1, dias.length);
  return <div className="overflow-x-auto rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
    <div className="mb-2 flex gap-4 text-xs text-[var(--fg-2)]"><span>● Pré-checkout</span><span>● Pedidos</span><span>● Vendas</span></div>
    <svg width={largura} height={altura + 42} viewBox={`0 0 ${largura} ${altura + 42}`} role="img" aria-label="Série diária de pré-checkout, pedidos e vendas">
      <line x1="0" y1={altura} x2={largura} y2={altura} stroke="var(--border)" />
      {dias.map((d, i) => { const x = i * passo + 4, bw = Math.min(8, (passo - 8) / 3); return <g key={d.dia}>
        {([['pre_checkout', 'var(--accent)'], ['pedidos', 'var(--yellow)'], ['vendas', 'var(--green)']] as const).map(([campo, cor], j) => { const h = d[campo] / max * (altura - 8); return <rect key={campo} x={x + j * bw} y={altura - h} width={bw} height={h} fill={cor}><title>{`${dataBR(d.dia)}: ${campo} ${d[campo]}`}</title></rect>; })}
        <text x={x} y={altura + 18} fontSize="9" fill="var(--fg-3)">{dataBR(d.dia).slice(0, 5)}</text>
      </g>; })}
    </svg>
  </div>;
}
