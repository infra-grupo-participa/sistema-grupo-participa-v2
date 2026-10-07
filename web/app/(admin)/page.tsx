import { getCurrentUser } from '@/shared/composition/server-container';
import { DEPARTAMENTOS, acessoComercial, podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { CartaoModulo } from '@/shared/ui/departamentos/CartaoModulo';
import { Icon } from '@/shared/ui/icons';
import { podeVerCalendario } from '@/modules/calendario/domain/acesso';
import { CalendarioEmpresa } from '@/modules/calendario/ui/CalendarioEmpresa';

export const dynamic = 'force-dynamic';

/**
 * Home da Central: os departamentos (decisão do Victor, 05/10/2026). Os atalhos que eram a home até então
 * estão no Início do Educacional (/educacional). Marketing aparece bloqueado para quem não é admin/dev.
 * Embaixo, o calendário da empresa (Arthur, 07/10/2026) para toda a equipe — a page confere a regra também
 * (layout e page renderizam em paralelo) e o banco confere de novo em public.calendario_eventos.
 */
export default async function HomePage() {
  const user = await getCurrentUser();
  const primeiroNome = (user?.nome || 'usuário').split(' ')[0];

  return (
    <div className="max-w-5xl">
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
            Central do Grupo Participa. Escolha o departamento
            {user?.cargo ? ` (seu perfil: ${user.cargo})` : ''}.
          </p>
        </div>
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {DEPARTAMENTOS.map((d, i) => (
          <CartaoModulo
            key={d.key}
            // Quem só pede estratégia entra direto em /comercial/estrategias.
            href={d.key === 'comercial' && acessoComercial(user, ACESSO_DEPARTAMENTOS) === 'estrategias' ? '/comercial/estrategias' : d.key === 'comercial' && acessoComercial(user, ACESSO_DEPARTAMENTOS) === 'relatorios' ? '/comercial/relatorios' : d.path}
            label={d.label}
            descricao={d.descricao}
            ico={d.ico}
            emBreve={d.status === 'em_breve'}
            bloqueado={d.key === 'comercial' ? !acessoComercial(user, ACESSO_DEPARTAMENTOS) : !podeVerDepartamento(user, d.key, ACESSO_DEPARTAMENTOS)}
            indice={i}
          />
        ))}
      </div>

      {podeVerCalendario(user) && (
        <div className="mt-6">
          <CalendarioEmpresa />
        </div>
      )}
    </div>
  );
}
