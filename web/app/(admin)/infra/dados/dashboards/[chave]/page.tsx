import { redirect } from 'next/navigation';

/** Mantém os links antigos da Clínica de Miami e de outros dashboards registrados. */
export default async function DashboardAntigoPage({ params }: { params: Promise<{ chave: string }> }) {
  const { chave } = await params;
  redirect(`/infra/dashboards/csm/${encodeURIComponent(chave)}`);
}
