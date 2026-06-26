// Lock de slot em memória (processo único Hostinger Node) — substitui o flock() do PHP.
// Garante que dois candidatos não reservem o mesmo horário simultaneamente.

const locked = new Set<string>();

export function tryAcquireSlot(key: string): boolean {
  if (locked.has(key)) return false;
  locked.add(key);
  return true;
}

export function releaseSlot(key: string): void {
  locked.delete(key);
}

/** Executa fn com lock exclusivo do slot; retorna null se já travado. */
export async function withSlotLock<T>(key: string, fn: () => Promise<T>): Promise<T | null> {
  if (!tryAcquireSlot(key)) return null;
  try {
    return await fn();
  } finally {
    releaseSlot(key);
  }
}
