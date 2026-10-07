import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

export default function DadosPage() {
  return <div className="max-w-5xl"><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Dados</h1><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3"><CartaoModulo href="/infra/dados/dashboards" label="Dashboards" descricao="Dashboards de eventos e projetos" ico="chart" /></div></div>;
}
