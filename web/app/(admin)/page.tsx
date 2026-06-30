import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, ehDev } from '@/shared/domain/auth';
import { Card } from '@/shared/ui/components';

export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const user = await getCurrentUser();
  const isAdmin = ehAdminOuAcima(user);
  const isDev = ehDev(user);

  const atalhos = [
    { emoji: '🏆', label: 'Relatório de Placas', desc: 'Fila de solicitações, auditoria e agenda', href: '/relatorios/placas#solicitacoes', show: true },
    { emoji: '👥', label: 'Base de Alunos', desc: 'Ficha 360° do aluno e edição', href: '/sistema/alunos', show: isAdmin },
    { emoji: '💬', label: 'Depoimentos', desc: 'Biblioteca, highlights e copy', href: '/depoimentos#biblioteca', show: isAdmin },
    { emoji: '👤', label: 'Usuários', desc: 'Perfis, cargos e permissões', href: '/usuarios', show: isAdmin },
    { emoji: '⚙️', label: 'Configurações', desc: 'Seu perfil e tema', href: '/sistema/configuracoes', show: true },
    { emoji: '🛠️', label: 'Admin Dev', desc: 'Observabilidade técnica', href: '/sistema/admin-dev', show: isDev },
  ].filter((a) => a.show);

  const primeiroNome = (user?.nome || 'usuário').split(' ')[0];

  return (
    <div className="max-w-5xl">
      <div className="rounded-[var(--r-xl)] border border-[var(--border)] bg-gradient-to-br from-[var(--surface-2)] to-[var(--surface-1)] p-6 sm:p-8">
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Grupo Participa</div>
        <h1 className="mt-1 text-2xl sm:text-3xl font-bold text-[var(--fg)]">Olá, {primeiroNome} 👋</h1>
        <p className="mt-2 text-[var(--fg-2)] max-w-2xl">
          Sistema interno do Grupo Participa. Acesse abaixo os módulos disponíveis para o seu perfil
          {user?.cargo ? ` (${user.cargo})` : ''}.
        </p>
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {atalhos.map((c) => (
          <Card
            key={c.href}
            as="a"
            href={c.href}
            className="group block p-5 hover:border-[var(--border-accent)] hover:bg-[var(--surface-3)] transition-colors"
          >
            <div className="text-2xl">{c.emoji}</div>
            <div className="mt-2 text-[var(--fg)] font-semibold group-hover:text-[var(--accent)] transition-colors">{c.label}</div>
            <div className="mt-0.5 text-sm text-[var(--fg-3)]">{c.desc}</div>
          </Card>
        ))}
      </div>
    </div>
  );
}
