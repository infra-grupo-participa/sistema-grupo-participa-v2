import { getCurrentUser } from '@/shared/composition/server-container';
import { redirect } from 'next/navigation';
import { podeVerCpf } from '@/shared/domain/auth';
import { podeOperarFinanceiro, podeVerFinanceiro } from '@/modules/financeiro/domain/acesso';
import { FinanceiroClient } from '@/modules/financeiro/ui/FinanceiroClient';

export const dynamic = 'force-dynamic';

export default async function FinanceiroPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Financeiro não é modelo aberto: visualizador não enxerga dinheiro (ver acesso.ts).
  if (!podeVerFinanceiro(user)) redirect('/');
  return <FinanceiroClient canEdit={podeOperarFinanceiro(user)} canVerDoc={podeVerCpf(user)} />;
}
