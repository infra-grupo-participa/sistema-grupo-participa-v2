import { redirect } from 'next/navigation';

/** Rota antiga: preservada para links salvos. */
export default function DashboardsAntigoPage() {
  redirect('/infra/dashboards');
}
