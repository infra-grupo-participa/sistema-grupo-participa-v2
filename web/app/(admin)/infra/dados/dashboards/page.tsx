import { registroDashboards } from '@/modules/infra/dados/domain/registro';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { temCapacidade } from '@/shared/domain/departamentos';

export default async function DashboardsPage() {
  const user = await getCurrentUser();
  const podeVerReceita = !ACESSO_DEPARTAMENTOS.acessoV2 || temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS);
  return <div className="max-w-5xl"><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dados</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Dashboards</h1><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{podeVerReceita && registroDashboards.map((d) => <CartaoModulo key={d.chave} href={`/infra/dados/dashboards/${d.chave}`} label={d.titulo} descricao={d.descricao} ico="chart" />)}</div>{!podeVerReceita && <p className="mt-6 text-sm text-[var(--fg-2)]">Nenhum dashboard disponível para seu acesso.</p>}</div>;
}
