import { departamento } from '@/shared/domain/departamentos';
import { EmBreve } from '@/shared/ui/departamentos/EmBreve';

// Área "Em breve". O código da área mora em web/modules/marketing/social-media/ (ver docs/central-de-dados.md).
export default function Page() {
  const a = departamento('marketing').areas.find((x) => x.key === 'social-media')!;
  return <EmBreve titulo={a.label} descricao={`Marketing · ${a.descricao}`} ico={a.ico} voltar={{ href: '/marketing', label: 'Marketing' }} />;
}
