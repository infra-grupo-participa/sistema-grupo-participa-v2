import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { LaboratorioClient } from '@/modules/infra/laboratorio/ui/LaboratorioClient';

// O laboratório e seus dados continuam restritos ao departamento Infra.
export default async function LaboratorioPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  return <LaboratorioClient />;
}
