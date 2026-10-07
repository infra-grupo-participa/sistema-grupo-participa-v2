import { registroDashboards } from '@/modules/infra/dados/domain/registro';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

export default function DashboardsPage() {
  return <div className="max-w-5xl"><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dados</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Dashboards</h1><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{registroDashboards.map((d) => <CartaoModulo key={d.chave} href={`/infra/dados/dashboards/${d.chave}`} label={d.titulo} descricao={d.descricao} ico="chart" />)}</div></div>;
}
