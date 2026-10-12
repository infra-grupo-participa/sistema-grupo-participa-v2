'use client';

// Esboço provisório: a aba entra no próximo commit desta branch.
import { EmptyState } from '@/shared/ui/components';
import type { DadosTela } from './contexto';

export function AbaCriativosPaginas({ d, gaveta }: { d: DadosTela; gaveta?: unknown }) {
  void d; void gaveta;
  return <EmptyState title="Em construção" hint="Esta aba entra no próximo commit da branch." />;
}
