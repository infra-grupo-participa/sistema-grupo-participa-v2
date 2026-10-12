'use client';

// Esboço provisório: a aba entra no próximo commit desta branch.
import { EmptyState } from '@/shared/ui/components';
import type { DadosTela } from './contexto';

export function AbaJornada({ d }: { d: DadosTela }) {
  void d;
  return <EmptyState title="Em construção" hint="Esta aba entra no próximo commit da branch." />;
}
