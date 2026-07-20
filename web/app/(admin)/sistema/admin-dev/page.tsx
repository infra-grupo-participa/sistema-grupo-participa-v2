import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehDev } from '@/shared/domain/auth';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { StatCard, Badge, DataTable, Thead, Th, Tr, Td, EmptyState } from '@/shared/ui/components';

export const dynamic = 'force-dynamic';

interface SystemEvent {
  id: number;
  tipo: string;
  fonte: string;
  titulo: string;
  detalhe: Record<string, unknown> | null;
  criado_em: string;
}

const TIPO_TONE: Record<string, 'danger' | 'warning' | 'info' | 'neutral'> = {
  error: 'danger',
  warn: 'warning',
  business: 'info',
};

/** Detalhe jsonb como "chave: valor" compacto — legível sem abrir o banco. */
function fmtDetalhe(d: Record<string, unknown> | null): string {
  if (!d || !Object.keys(d).length) return '';
  return Object.entries(d)
    .map(([k, v]) => `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`)
    .join(' · ');
}

export default async function AdminDevPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ehDev(user)) redirect('/'); // painel técnico exclusivo de dev

  let resumo: Record<string, unknown> | null = null;
  let eventos: SystemEvent[] = [];
  let zoomErros7d: number | null = null;
  let mailerErros7d: number | null = null;
  let semZoom7d: number | null = null;
  try {
    const admin = createAdminSupabase();
    const seteDias = new Date(Date.now() - 7 * 86400000).toISOString();
    const [{ data: r }, { data: e }, zoomQ, mailQ, semZoomQ] = await Promise.all([
      admin.from('vw_dashboard_resumo').select('*').maybeSingle(),
      admin.from('thb_system_events').select('id, tipo, fonte, titulo, detalhe, criado_em').order('criado_em', { ascending: false }).limit(100),
      admin.from('thb_system_events').select('id', { count: 'exact', head: true }).eq('fonte', 'zoom').eq('tipo', 'error').gte('criado_em', seteDias),
      admin.from('thb_system_events').select('id', { count: 'exact', head: true }).eq('fonte', 'mailer').eq('tipo', 'error').gte('criado_em', seteDias),
      admin.from('thb_system_events').select('id', { count: 'exact', head: true }).in('fonte', ['agenda_confirm', 'agenda_admin']).eq('tipo', 'warn').gte('criado_em', seteDias),
    ]);
    resumo = r ?? null;
    eventos = (e as SystemEvent[]) ?? [];
    zoomErros7d = zoomQ.count ?? 0;
    mailerErros7d = mailQ.count ?? 0;
    semZoom7d = semZoomQ.count ?? 0;
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
  const saude = [
    { l: 'Falhas Zoom (7d)', v: zoomErros7d },
    { l: 'Agendamentos sem link Zoom (7d)', v: semZoom7d },
    { l: 'Falhas de e-mail (7d)', v: mailerErros7d },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Admin Dev</h1>
      <p className="text-sm text-[var(--fg-3)] mb-4">Observabilidade técnica {!resumo && '(configure SUPABASE_SERVICE_ROLE_KEY para ver as métricas)'}</p>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3">
        {cards.map((c, i) => (
          <div key={c.k} className="gp-rise" style={{ animationDelay: `${i * 40}ms` }}>
            <StatCard label={c.l} value={metric(c.k)} />
          </div>
        ))}
      </div>

      {/* Saúde das integrações — zero é o estado saudável; >0 pede ação (Zoom fora do ar, Resend etc). */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-6">
        {saude.map((c, i) => (
          <div key={c.l} className="gp-rise" style={{ animationDelay: `${(i + 8) * 40}ms` }}>
            <StatCard label={c.l} value={c.v === null ? '—' : String(c.v)} tone={c.v ? 'var(--red)' : 'var(--green)'} bar={c.v ? 'red' : 'green'} />
          </div>
        ))}
      </div>

      <div className="text-sm font-semibold text-[var(--fg)] mb-2">Eventos recentes do sistema</div>
      <DataTable fixed>
        <Thead>
          <Th className="w-[100px]">Tipo</Th>
          <Th className="w-[130px]">Fonte</Th>
          <Th className="w-[300px]">Título</Th>
          <Th>Detalhe</Th>
          <Th className="w-[140px]">Quando</Th>
        </Thead>
        <tbody>
          {eventos.map((ev) => {
            const det = fmtDetalhe(ev.detalhe);
            return (
              <Tr key={ev.id}>
                <Td className="overflow-hidden"><Badge tone={TIPO_TONE[ev.tipo] ?? 'neutral'}>{ev.tipo}</Badge></Td>
                <Td className="overflow-hidden"><span className="block truncate text-[var(--fg-3)] text-xs" title={ev.fonte}>{ev.fonte}</span></Td>
                <Td className="overflow-hidden"><span className="block truncate text-[var(--fg-2)]" title={ev.titulo}>{ev.titulo}</span></Td>
                <Td className="overflow-hidden">
                  {det ? <span className="block truncate text-xs text-[var(--fg-3)] font-mono" title={det}>{det}</span> : <span className="text-[var(--fg-3)]">—</span>}
                </Td>
                <Td className="text-[var(--fg-3)] text-xs whitespace-nowrap">{new Date(ev.criado_em).toLocaleString('pt-BR')}</Td>
              </Tr>
            );
          })}
          {!eventos.length && (
            <tr>
              <td colSpan={5}>
                <EmptyState title="Sem eventos." />
              </td>
            </tr>
          )}
        </tbody>
      </DataTable>
    </div>
  );
}
