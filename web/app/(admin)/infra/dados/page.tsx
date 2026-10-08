import { redirect } from 'next/navigation';

/** Rota antiga: mantém links salvos e leva ao novo nível de Dashboards. */
export default function DadosAntigoPage() {
  redirect('/infra/dashboards');
}
