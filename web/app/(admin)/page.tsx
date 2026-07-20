import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, ehDev } from '@/shared/domain/auth';
import { Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const user = await getCurrentUser();
  const isAdmin = ehAdminOuAcima(user);
  const isDev = ehDev(user);

  const atalhos = [
    { ico: 'trophy', label: 'Relatório de Placas', desc: 'Fila de solicitações, auditoria e agenda', href: '/relatorios/placas#solicitacoes', external: false, show: true },
    { ico: 'users', label: 'Base de Alunos', desc: 'Ficha 360° do aluno e edição', href: '/sistema/alunos', external: false, show: isAdmin },
    { ico: 'depoimentos', label: 'Depoimentos', desc: 'Biblioteca, highlights e copy', href: '/depoimentos#biblioteca', external: false, show: isAdmin },
    { ico: 'user', label: 'Usuários', desc: 'Perfis, cargos e permissões', href: '/usuarios', external: false, show: isAdmin },
    { ico: 'check-circle', label: 'Ativação', desc: 'Sistema de ativação de acessos', href: 'https://ativacao.grupoparticipa.app.br/login', external: true, show: true },
    { ico: 'gem', label: 'Serviços Diamante', desc: 'Sistema de Serviços Diamante', href: 'https://diamantes.grupoparticipa.app.br/', external: true, show: true },
    { ico: 'settings', label: 'Configurações', desc: 'Seu perfil e tema', href: '/sistema/configuracoes', external: false, show: true },
    { ico: 'wrench', label: 'Admin Dev', desc: 'Observabilidade técnica', href: '/sistema/admin-dev', external: false, show: isDev },
  ].filter((a) => a.show);

  const primeiroNome = (user?.nome || 'usuário').split(' ')[0];

  return (
    <div className="max-w-5xl">
      {/* Hero — assinatura âmbar sutil (glow radial no canto), fiel ao painel operacional */}
      <div className="relative overflow-hidden rounded-[var(--r-xl)] border border-[var(--border)] bg-gradient-to-br from-[var(--surface-2)] to-[var(--surface-1)] p-6 sm:p-8 gp-rise">
        <div
          aria-hidden
          className="pointer-events-none absolute -top-16 -right-16 h-56 w-56 rounded-full opacity-60"
          style={{ background: 'radial-gradient(circle, var(--accent-subtle), transparent 70%)' }}
        />
        <div className="relative">
          <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Grupo Participa</div>
          <h1 className="mt-1 text-2xl sm:text-3xl font-bold text-[var(--fg)] inline-flex items-center gap-2">Olá, {primeiroNome} <Icon name="wave" size={24} className="text-[var(--accent)]" /></h1>
          <p className="mt-2 text-[var(--fg-2)] max-w-2xl leading-relaxed">
            Sistema interno do Grupo Participa. Acesse abaixo os módulos disponíveis para o seu perfil
            {user?.cargo ? ` (${user.cargo})` : ''}.
          </p>
        </div>
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {atalhos.map((c, i) => (
          <Card
            key={c.href}
            as="a"
            href={c.href}
            target={c.external ? '_blank' : undefined}
            rel={c.external ? 'noopener noreferrer' : undefined}
            style={{ animationDelay: `${i * 45}ms` }}
            className="group gp-rise block p-5 hover:border-[var(--border-accent)] hover:bg-[var(--surface-3)] hover:shadow-[var(--shadow-md)] hover:-translate-y-0.5"
          >
            <div className="flex items-start justify-between">
              <div className="grid place-items-center w-11 h-11 rounded-[var(--r-md)] bg-[var(--accent-subtle)] border border-[var(--accent-border)] text-[var(--accent)] transition-colors group-hover:bg-[var(--accent)] group-hover:text-black">
                <Icon name={c.ico} size={22} />
              </div>
              {c.external && <Icon name="arrow-up-right" size={16} className="text-[var(--fg-3)] transition-transform group-hover:text-[var(--accent)] group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />}
            </div>
            <div className="mt-3 text-[var(--fg)] font-semibold group-hover:text-[var(--accent)] transition-colors">{c.label}</div>
            <div className="mt-0.5 text-sm text-[var(--fg-3)] leading-relaxed">{c.desc}</div>
          </Card>
        ))}
      </div>
    </div>
  );
}
