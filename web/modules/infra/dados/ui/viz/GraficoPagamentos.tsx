import { EmptyState } from '@/shared/ui/components';
import type { PagamentoPresencial } from '../../domain/presencial';
import { reais } from '../formato';

export function GraficoPagamentos({ linhas }: { linhas: PagamentoPresencial[] }) {
  const maximo = Math.max(1, ...linhas.map((l) => l.vendas));
  return <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
    <h3 className="mb-1 text-sm font-semibold text-[var(--fg)]">Formas de pagamento</h3>
    <p className="mb-4 text-xs text-[var(--fg-2)]">Vendas pagas por forma e parcelas. Receita bruta em BRL.</p>
    {!linhas.length ? <EmptyState title="Sem vendas para mostrar" /> : <ul className="space-y-3">{linhas.map((l) => <li key={`${l.forma}-${l.parcelas ?? 'sem-parcelas'}`}>
      <div className="mb-1 flex flex-wrap justify-between gap-2 text-sm"><span className="font-medium text-[var(--fg)]">{l.forma_nome}{l.parcelas === null ? ' · parcelas sem dado' : ` · ${l.parcelas}x`}</span><span className="tabular text-[var(--fg-2)]">{l.vendas.toLocaleString('pt-BR')} vendas · {reais(l.receita_bruta)}</span></div>
      <svg className="h-3 w-full" viewBox="0 0 100 12" preserveAspectRatio="none" role="img" aria-label={`${l.forma_nome}: ${l.vendas} vendas`}><rect x="0" y="0" width="100" height="12" rx="3" fill="var(--surface-3)" /><rect x="0" y="0" width={l.vendas === 0 ? 0 : Math.max(2, l.vendas / maximo * 100)} height="12" rx="3" fill="var(--accent)" /></svg>
    </li>)}</ul>}
  </section>;
}
