import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podePedirAlteracao } from '@/modules/alunos/domain/pedidos-alteracao';
import { PedidosAlteracaoClient } from '@/modules/alunos/ui/PedidosAlteracaoClient';

export const dynamic = 'force-dynamic';

/**
 * Pedidos de alteração de cadastro (catálogo 3.6). Quem pede NÃO precisa (nem ganha) acesso à Central:
 * vê só os próprios pedidos. A trava real é a do banco (pa_pode_pedir); esta só evita a tela vazia.
 */
export default async function PedidosAlteracaoPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!podePedirAlteracao(user)) redirect('/');
  return <PedidosAlteracaoClient />;
}
