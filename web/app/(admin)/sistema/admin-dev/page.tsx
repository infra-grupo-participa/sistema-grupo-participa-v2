import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehDev } from '@/shared/domain/auth';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

export const dynamic = 'force-dynamic';

interface SystemEvent { id: number; tipo: string; fonte: string; titulo: string; criado_em: string }

export default async function AdminDevPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ehDev(user)) redirect('/'); // painel técnico exclusivo de dev

  let resumo: Record<string, unknown> | null = null;
  let eventos: SystemEvent[] = [];
  try {
    const admin = createAdminSupabase();
    const [{ data: r }, { data: e }] = await Promise.all([
      admin.from('vw_dashboard_resumo').select('*').maybeSingle(),
      admin.from('thb_system_events').select('id, tipo, fonte, titulo, criado_em').order('criado_em', { ascending: false }).limit(50),
    ]);
    resumo = r ?? null;
    eventos = (e as SystemEvent[]) ?? [];
  } catch {
    // service_role não configurado → painel mostra vazio.
  }

  const metric = (k: string) => (resumo ? String(resumo[k] ?? '—') : '—');
  const cards = [
    { l: 'Total de alunos', k: 'total_alunos' },
    { l: 'Alunos sem nível', k: 'alunos_sem_nivel' },
    { l: 'Placas em auditoria', k: 'placas_em_auditoria' },
    { l: 'Placas concluídas', k: 'placas_concluidas' },
    { l: 'Erros (24h)', k: 'erros_24h' },
    { l: 'Eventos (24h)', k: 'eventos_24h' },
    { l: 'Audits (24h)', k: 'audits_24h' },
    { l: 'Inconsistências', k: 'total_inconsistencias' },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Admin Dev</h1>
      <p className="text-sm text-[var(--fg-3)] mb-4">Observabilidade técnica {!resumo && '(configure SUPABASE_SERVICE_ROLE_KEY para ver as métricas)'}</p>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
        {cards.map((c) => (
          <div key={c.k} className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
            <div className="text-xl font-bold text-[var(--fg)]">{metric(c.k)}</div>
            <div className="text-xs text-[var(--fg-3)]">{c.l}</div>
          </div>
        ))}
      </div>

      <div className="text-sm font-semibold text-[var(--fg)] mb-2">Eventos recentes do sistema</div>
      <div className="rounded-[var(--r-lg)] border border-[var(--border)] overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-[var(--surface-2)] text-[var(--fg-3)]"><tr>
            <th className="text-left px-3 py-2 font-medium">Tipo</th>
            <th className="text-left px-3 py-2 font-medium">Fonte</th>
            <th className="text-left px-3 py-2 font-medium">Título</th>
            <th className="text-left px-3 py-2 font-medium">Quando</th>
          </tr></thead>
          <tbody>
            {eventos.map((ev) => (
              <tr key={ev.id} className="border-t border-[var(--border)]">
                <td className="px-3 py-2"><span className="text-xs font-semibold" style={{ color: ev.tipo === 'error' ? 'var(--red)' : 'var(--fg-2)' }}>{ev.tipo}</span></td>
                <td className="px-3 py-2 text-[var(--fg-3)] text-xs">{ev.fonte}</td>
                <td className="px-3 py-2 text-[var(--fg-2)]">{ev.titulo}</td>
                <td className="px-3 py-2 text-[var(--fg-3)] text-xs">{new Date(ev.criado_em).toLocaleString('pt-BR')}</td>
              </tr>
            ))}
            {!eventos.length && <tr><td colSpan={4} className="px-3 py-8 text-center text-[var(--fg-3)]">Sem eventos.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
}
