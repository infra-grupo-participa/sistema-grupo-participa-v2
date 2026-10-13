import { LaboratorioClient } from '@/modules/infra/laboratorio/ui/LaboratorioClient';

// O gate do departamento está no layout do Infra; o dado é protegido pelas RPCs public.lab_* (gp_eh_equipe).
export default function LaboratorioPage() {
  return <LaboratorioClient />;
}
