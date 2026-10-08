import { EmptyState } from '@/shared/ui/components';

export type Fatia = { rotulo: string; quantidade: number };
const cores = ['var(--accent)', 'var(--green)', 'var(--cyan)', 'var(--purple)', 'var(--yellow)', 'var(--red)'];

export function RoscaCategorias({ titulo, fatias, rotuloCentro = 'compradores' }: { titulo: string; fatias: Fatia[]; rotuloCentro?: string }) {
  const positivas = fatias.map((f, i) => ({ ...f, cor: cores[i % cores.length] })).filter((f) => f.quantidade > 0);
  const total = positivas.reduce((s, f) => s + f.quantidade, 0);
  const circunferencia = 2 * Math.PI * 42;
  const arcos = positivas.map((f, i) => ({ ...f, inicio: positivas.slice(0, i).reduce((s, anterior) => s + anterior.quantidade, 0) / total }));
  return <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
    <h3 className="mb-3 text-sm font-semibold text-[var(--fg)]">{titulo}</h3>
    {total === 0 ? <EmptyState title="Sem dados para este gráfico" /> : <div className="flex flex-col items-center gap-5 sm:flex-row">
      <svg width="176" height="176" viewBox="0 0 176 176" role="img" aria-label={`${titulo}: ${total} ${rotuloCentro}`}>
        <circle cx="88" cy="88" r="42" fill="none" stroke="var(--surface-3)" strokeWidth="25" />
        {arcos.map((f) => <circle key={f.rotulo} cx="88" cy="88" r="42" fill="none" stroke={f.cor} strokeWidth="25" strokeDasharray={`${f.quantidade / total * circunferencia} ${circunferencia}`} strokeDashoffset={-f.inicio * circunferencia} transform="rotate(-90 88 88)"><title>{`${f.rotulo}: ${f.quantidade}`}</title></circle>)}
        <text x="88" y="84" textAnchor="middle" fill="var(--fg)" fontSize="22" fontWeight="700">{total}</text>
        <text x="88" y="104" textAnchor="middle" fill="var(--fg-2)" fontSize="10">{rotuloCentro}</text>
      </svg>
      <ul className="min-w-0 w-full flex-1 space-y-2 text-sm sm:w-auto">{fatias.map((f, i) => <li key={f.rotulo} className="flex items-center justify-between gap-3"><span className="flex min-w-0 flex-1 items-center gap-2"><span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: cores[i % cores.length] }} /><span className="break-words text-[var(--fg-2)]">{f.rotulo}</span></span><strong className="shrink-0 tabular text-[var(--fg)]">{f.quantidade.toLocaleString('pt-BR')}</strong></li>)}</ul>
    </div>}
  </section>;
}
