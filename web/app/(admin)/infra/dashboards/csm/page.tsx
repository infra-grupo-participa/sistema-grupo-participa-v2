import { getCurrentUser } from '@/shared/composition/server-container';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { temCapacidade } from '@/shared/domain/departamentos';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';
import { registroDashboards } from '@/modules/infra/dados/domain/registro';

export default async function CsmDashboardsPage() {
  const user = await getCurrentUser();
  const podeVerFinanceiro = !ACESSO_DEPARTAMENTOS.acessoV2 || temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS);
  return (
    <div className="max-w-5xl">
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">CSM</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Dashboards do Educacional.</p>
      {podeVerFinanceiro ? (
        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {registroDashboards.map((dashboard) => (
            <CartaoModulo
              key={dashboard.chave}
              href={`/infra/dashboards/csm/${dashboard.chave}`}
              label={dashboard.titulo}
              descricao={dashboard.descricao}
              ico="chart"
            />
          ))}
        </div>
      ) : (
        <p className="mt-6 text-sm text-[var(--fg-2)]">Nenhum dashboard disponível para seu acesso.</p>
      )}
    </div>
  );
}
