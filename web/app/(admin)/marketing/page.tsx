import { BASE_MARKETING, departamento } from '@/shared/domain/departamentos';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';

/** Departamento Marketing: a base compartilhada (projetos e páginas) e os cartões das 5 áreas. O gate (admin/dev) está no layout.tsx. */
export default function MarketingPage() {
  const d = departamento('marketing');
  return (
    <div className="max-w-5xl">
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Departamento</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{d.label}</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Escolha a área.</p>
      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {d.areas.map((a, i) => (
          <CartaoModulo key={a.key} href={a.path} label={a.label} descricao={a.descricao} ico={a.ico} emBreve={a.status === 'em_breve'} indice={i} />
        ))}
      </div>
      <h2 className="mt-8 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Base compartilhada</h2>
      <div className="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {BASE_MARKETING.map((b, i) => (
          <CartaoModulo key={b.key} href={b.path} label={b.label} descricao={b.descricao} ico={b.ico} indice={d.areas.length + i} />
        ))}
      </div>
    </div>
  );
}
