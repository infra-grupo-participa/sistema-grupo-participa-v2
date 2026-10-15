import { getCurrentUser } from '@/shared/composition/server-container';
import { redirect } from 'next/navigation';
import { podeVerCpf } from '@/shared/domain/auth';
import { podeOperarFinanceiro, podeVerFinanceiro } from '@/modules/financeiro/domain/acesso';
import { FinanceiroClient } from '@/modules/financeiro/ui/FinanceiroClient';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { temCapacidade } from '@/shared/domain/departamentos';

export const dynamic = 'force-dynamic';

/**
 * Departamento Financeiro = Contas a Receber (web/modules/financeiro). Até 15/10/2026 a tela morava em
 * /educacional/financeiro, que agora é 308 para cá (shared/ui/nav/redirects.ts); o "Em breve" saiu (pedido do João).
 * O layout de /financeiro aplica a mesma régua; a page repete porque layout e page renderizam em paralelo no Next.
 */
export default async function FinanceiroPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Financeiro não é modelo aberto: visualizador não enxerga dinheiro (ver acesso.ts).
  const v2 = ACESSO_DEPARTAMENTOS.acessoV2;
  if (v2 ? !temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS) : !podeVerFinanceiro(user)) redirect('/');
  return <FinanceiroClient canEdit={v2 ? temCapacidade(user, 'financeiro.operar', ACESSO_DEPARTAMENTOS) : podeOperarFinanceiro(user)} canVerDoc={v2 ? temCapacidade(user, 'cpf.ver', ACESSO_DEPARTAMENTOS) : podeVerCpf(user)} />;
}
