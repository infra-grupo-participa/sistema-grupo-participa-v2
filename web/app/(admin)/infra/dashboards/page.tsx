import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

export default function DashboardsInfraPage() {
  return (
    <div className="max-w-5xl">
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Dashboards</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Escolha a área dos dashboards.</p>
      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <CartaoModulo href="/infra/dashboards/csm" label="CSM" descricao="Dashboards do Educacional" ico="graduation" />
        <CartaoModulo href="/infra/dashboards/escritorio" label="Escritório" descricao="Seminários e outros dashboards" ico="building" />
      </div>
    </div>
  );
}
