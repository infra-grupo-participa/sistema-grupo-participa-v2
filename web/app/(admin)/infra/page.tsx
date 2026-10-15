import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { departamento } from '@/shared/domain/departamentos';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

export default async function InfraPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  const d = departamento('infra');
  return <div className="max-w-5xl"><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Departamento</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{d.label}</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Escolha uma seção.</p><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3"><CartaoModulo href="/infra/dashboards" label="Dashboards" descricao="Academy e Soluções" ico="chart" /><CartaoModulo href="/infra/laboratorio" label="Laboratório" descricao="Decisões e testes, do registro ao teste controlado" ico="target" indice={1} /></div></div>;
}
