import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';
import { LinkVoltar } from '@/shared/ui/departamentos/LinkVoltar';
import { registroDashboards } from '@/modules/infra/dados/domain/registro';

export default function CsmDashboardsPage() {
  return (
    <div className="max-w-5xl">
      <LinkVoltar href="/infra/dashboards" para="Dashboards" />
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Academy</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Dashboards do Educacional.</p>
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
          <CartaoModulo
            href="/infra/dashboards/csm/acoes-black"
            label="Ações da Black Friday"
            descricao="Acompanhamento das ações de renovação e ofertas da Black Friday."
            ico="chart"
          />
      </div>
    </div>
  );
}
