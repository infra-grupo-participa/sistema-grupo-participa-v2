// Redução de PII para a trilha thb_system_events: funções puras (sem banco), fora do módulo que os testes mockam.

/** Só o domínio de um e-mail (ou lista) — a trilha nunca guarda o endereço. */
export function dominioEmail(to: string | string[] | null | undefined): string | string[] | null {
  const um = (e: string) => {
    const at = String(e ?? '').lastIndexOf('@');
    return at >= 0 ? String(e).slice(at + 1).trim().toLowerCase() : null;
  };
  if (Array.isArray(to)) return to.map(um).filter((d): d is string => !!d);
  return to ? um(to) : null;
}

/** Troca endereços de e-mail num texto livre (erro do provedor ecoa o destinatário) por ***@dominio. */
export function mascararEmails(texto: string): string {
  return String(texto ?? '').replace(/[^\s@<>"'(),;:]+@([^\s@<>"'(),;:]+)/g, '***@$1');
}
