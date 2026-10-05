import Link from 'next/link';
import { Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

/** Tela "Em breve" reutilizável: departamento ou área que ainda não está pronto. */
export function EmBreve({ titulo, descricao, ico = 'hourglass', voltar }: {
  titulo: string;
  descricao?: string;
  ico?: string;
  /** Link de volta (ex.: { href: '/marketing', label: 'Marketing' }). Padrão: Início. */
  voltar?: { href: string; label: string };
}) {
  const v = voltar ?? { href: '/', label: 'Início' };
  return (
    <div className="max-w-3xl">
      <Card className="p-8 sm:p-10 gp-rise text-center">
        <div className="mx-auto grid place-items-center w-14 h-14 rounded-[var(--r-lg)] bg-[var(--accent-subtle)] border border-[var(--accent-border)] text-[var(--accent)]">
          <Icon name={ico} size={26} />
        </div>
        <h1 className="mt-4 text-2xl font-bold text-[var(--fg)]">{titulo}</h1>
        {descricao && <p className="mt-1 text-sm text-[var(--fg-3)]">{descricao}</p>}
        <div className="mt-4 inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide px-2.5 py-1 rounded-[var(--r-pill)] bg-[var(--surface-3)] text-[var(--fg-2)]">
          <Icon name="hourglass" size={12} /> Em breve
        </div>
        <p className="mt-4 text-sm text-[var(--fg-2)] leading-relaxed">Este espaço ainda está sendo construído.</p>
        <Link href={v.href} className="mt-6 inline-flex items-center gap-1.5 text-sm text-[var(--accent)] hover:underline">
          <Icon name="arrow-left" size={14} /> Voltar para {v.label}
        </Link>
      </Card>
    </div>
  );
}
