import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar, temFuncao } from '@/shared/domain/auth';
import { AlunosClient } from '@/modules/alunos/ui/AlunosClient';

export const dynamic = 'force-dynamic';

export default async function AlunosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  // Acesso à base sensível: admin+ ou quem tem o módulo Centro de Controle (3.1).
  // Visualizador global NÃO entra na base — é dado sensível (LGPD).
  const temModuloBase =
    (user.cargo === 'gestor' || user.cargo === 'operador') && user.setores.includes('centro_controle');
  const acessoBase = ehAdminOuAcima(user) || temModuloBase;
  // Liberação Holding Masters (3.2.3): admin+ ou operador com placas.hm_liberar.
  const canLiberarHm = ehAdminOuAcima(user) || temFuncao(user, 'placas.hm_liberar');

  if (!acessoBase && !canLiberarHm) redirect('/');

  return (
    <AlunosClient
      canEditBase={ehAdminOuAcima(user) || podeEditar(user, 'centro_controle')}
      canLiberarHm={canLiberarHm}
      canManageTurmas={ehAdminOuAcima(user)}
      onlyHm={!acessoBase && canLiberarHm}
    />
  );
}
