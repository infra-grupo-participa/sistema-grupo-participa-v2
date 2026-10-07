import { Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

/**
 * Cartão de departamento ou área (home e página do Marketing).
 * - `em_breve`: clicável, leva à tela "Em breve" e mostra o selo.
 * - `bloqueado`: sem link, mostra "Acesso restrito" (ex.: Marketing para quem não é admin/dev).
 */
export function CartaoModulo({ href, label, descricao, ico, emBreve, bloqueado, indice = 0 }: {
  href: string; label: string; descricao: string; ico: string; emBreve?: boolean; bloqueado?: boolean; indice?: number;
}) {
  const conteudo = (
    <>
      <div className="flex items-start justify-between">
        <div className={`grid place-items-center w-11 h-11 rounded-[var(--r-md)] border transition-colors duration-[var(--dur-mid)] ease-[var(--ease-out)] ${
          bloqueado
            ? 'bg-[var(--surface-3)] border-[var(--border)] text-[var(--fg-3)]'
            : 'bg-[var(--accent-subtle)] border-[var(--accent-border)] text-[var(--accent)] shadow-[var(--highlight-surface)] group-hover:bg-[var(--accent)] group-hover:text-black group-hover:shadow-[var(--highlight-inset)]'
        }`}>
          <Icon name={ico} size={22} />
        </div>
        {bloqueado ? (
          <span className="inline-flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded-[var(--r-pill)] bg-[var(--surface-3)] text-[var(--fg-3)]">
            <Icon name="lock" size={11} /> Acesso restrito
          </span>
        ) : emBreve ? (
          <span className="text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded-[var(--r-pill)] bg-[var(--surface-3)] text-[var(--fg-2)]">Em breve</span>
        ) : null}
      </div>
      <div className={`mt-3 font-semibold tracking-[-0.01em] transition-colors duration-[var(--dur-mid)] ${bloqueado ? 'text-[var(--fg-3)]' : 'text-[var(--fg)] group-hover:text-[var(--accent)]'}`}>{label}</div>
      <div className="mt-0.5 text-sm text-[var(--fg-3)] leading-relaxed">{descricao}</div>
    </>
  );
  const delay = { animationDelay: `${indice * 45}ms` };
  if (bloqueado) {
    return <Card aria-disabled="true" style={delay} className="gp-rise block p-5 opacity-70 cursor-not-allowed">{conteudo}</Card>;
  }
  return (
    <Card as="a" href={href} style={delay} className="group gp-rise block p-5 hover:border-[var(--border-accent)] hover:bg-[var(--surface-3)] hover:shadow-[var(--highlight-surface),var(--shadow-md)] hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.99]">
      {conteudo}
    </Card>
  );
}
