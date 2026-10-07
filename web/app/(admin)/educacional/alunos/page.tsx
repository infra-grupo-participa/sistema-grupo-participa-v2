import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar, temFuncao } from '@/shared/domain/auth';
import { AlunosClient } from '@/modules/alunos/ui/AlunosClient';
import { podeEditarArea } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

export default async function AlunosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  // Acesso à base sensível: admin+ ou quem tem o módulo Centro de Controle (3.1).
  // Visualizador global NÃO entra na base — é dado sensível (LGPD).
  const temModuloBase =
    (user.cargo === 'gestor' || user.cargo === 'operador') && user.setores.includes('centro_controle');
  const editorV2 = podeEditarArea(user, 'educacional', null, ACESSO_DEPARTAMENTOS);
  const acessoBase = ACESSO_DEPARTAMENTOS.acessoV2 ? editorV2 : ehAdminOuAcima(user) || temModuloBase;
  // Liberação Holding Masters (3.2.3): admin+ ou operador com placas.hm_liberar.
  const canLiberarHm = ACESSO_DEPARTAMENTOS.acessoV2 ? editorV2 && (user.acesso?.master === true || temFuncao(user, 'placas.hm_liberar')) : ehAdminOuAcima(user) || temFuncao(user, 'placas.hm_liberar');

  if (!acessoBase && !canLiberarHm) redirect('/');

  return (
    <AlunosClient
      canEditBase={ACESSO_DEPARTAMENTOS.acessoV2 ? editorV2 : ehAdminOuAcima(user) || podeEditar(user, 'centro_controle')}
      canLiberarHm={canLiberarHm}
      canManageTurmas={ACESSO_DEPARTAMENTOS.acessoV2 ? editorV2 : ehAdminOuAcima(user)}
      onlyHm={!acessoBase && canLiberarHm}
    />
  );
}
