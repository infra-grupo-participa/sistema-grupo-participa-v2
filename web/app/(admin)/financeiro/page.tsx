import { departamento } from '@/shared/domain/departamentos';
import { EmBreve } from '@/shared/ui/departamentos/EmBreve';

// Departamento ainda não construído (decisão do Victor, 05/10/2026). Ver docs/central-de-dados.md.
export default function Page() {
  const d = departamento('financeiro');
  return <EmBreve titulo={d.label} descricao={d.descricao} ico={d.ico} />;
}
