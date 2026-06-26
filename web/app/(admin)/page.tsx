import { getCurrentUser } from '@/shared/composition/server-container';

export default async function DashboardPage() {
  const user = await getCurrentUser();

  return (
    <div className="max-w-4xl">
      <h1 className="text-2xl font-bold text-[var(--fg)]">Sobre o sistema</h1>
      <p className="mt-2 text-[var(--fg-2)]">
        Bem-vindo, {user?.nome || 'usuário'}. Sistema interno do Grupo Participa.
      </p>

      <div className="mt-6 grid gap-4 sm:grid-cols-3">
        {[
          { label: 'Relatório de Placas', href: '/relatorios/placas#solicitacoes' },
          { label: 'Base de Alunos', href: '/sistema/alunos' },
          { label: 'Depoimentos', href: '/depoimentos#biblioteca' },
        ].map((c) => (
          <a
            key={c.href}
            href={c.href}
            className="block rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-5 hover:border-[var(--border-accent)] transition-colors"
          >
            <span className="text-[var(--fg)] font-medium">{c.label}</span>
          </a>
        ))}
      </div>
    </div>
  );
}
