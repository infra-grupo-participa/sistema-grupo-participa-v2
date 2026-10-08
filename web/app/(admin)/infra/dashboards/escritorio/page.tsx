import { EmBreve } from '@/shared/ui/departamentos/EmBreve';

export default function EscritorioDashboardsPage() {
  return <EmBreve titulo="Escritório" descricao="Dashboards de seminários e outras frentes." ico="building" voltar={{ href: '/infra/dashboards', label: 'Dashboards' }} />;
}
