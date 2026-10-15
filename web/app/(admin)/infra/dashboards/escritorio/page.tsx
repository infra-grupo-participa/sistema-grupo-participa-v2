import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';
import { LinkVoltar } from '@/shared/ui/departamentos/LinkVoltar';
import { registroAtm } from '@/modules/infra/atm/domain/registro';

export default function EscritorioDashboardsPage() {
  return (
    <div className="max-w-5xl">
      <LinkVoltar href="/infra/dashboards" para="Dashboards" />
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Soluções</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Dashboards de seminários e outras frentes.</p>
      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {registroAtm.map((item) => (
            <CartaoModulo
              key={item.chave}
              href={`/infra/dashboards/escritorio/atm/${item.chave}`}
              label="Seminário ATM"
              descricao={item.rotulo}
              ico="chart"
            />
          ))}
      </div>
    </div>
  );
}
