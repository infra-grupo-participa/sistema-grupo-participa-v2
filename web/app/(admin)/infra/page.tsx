import { departamento } from '@/shared/domain/departamentos';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

export default function InfraPage() {
  const d = departamento('infra');
  return <div className="max-w-5xl"><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Departamento</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{d.label}</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Escolha a área.</p><div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{d.areas.map((a, i) => <CartaoModulo key={a.key} href={a.path} label={a.label} descricao={a.descricao} ico={a.ico} emBreve={a.status === 'em_breve'} indice={i} />)}</div></div>;
}
