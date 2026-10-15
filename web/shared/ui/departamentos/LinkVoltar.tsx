import Link from 'next/link';
import { Icon } from '@/shared/ui/icons';

/** Link "Voltar" para a tela de cima (ex.: de um dashboard para o módulo que o lista). */
export function LinkVoltar({ href, para }: { href: string; para: string }) {
  return (
    <Link href={href} className="mb-2 inline-flex min-h-11 items-center gap-1.5 text-sm font-medium text-[var(--fg-2)] hover:text-[var(--accent)] md:min-h-0">
      <Icon name="arrow-left" size={14} />
      Voltar para {para}
    </Link>
  );
}
