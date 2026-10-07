import { EmptyState } from '@/shared/ui/components';
import type { DiaPresencial } from '../domain/presencial';
import { SerieDiaria } from './viz/SerieDiaria';

export function AbaVisaoVendas({ dias, erro, carregando }: { dias: DiaPresencial[] | null; erro: string | null; carregando: boolean }) {
  if (carregando) return <p>Carregando série diária…</p>;
  return <div>
    {erro && <p role="alert" className="mb-3 text-sm text-[var(--fg-2)]">{erro} {dias !== null && 'Exibindo a última série carregada.'}</p>}
    {dias === null ? !erro && <p role="alert">Não foi possível carregar agora.</p> : !dias.length ? <EmptyState title="Sem dados na série diária" /> : <><h2 className="mb-1 text-base font-semibold text-[var(--fg)]">Pré-checkout, pedidos e vendas por dia</h2><p className="mb-3 text-sm text-[var(--fg-2)]">Pedidos são transações criadas na Hotmart, em qualquer status. Abandonos: sem fonte.</p><SerieDiaria dias={dias} /></>}
  </div>;
}
