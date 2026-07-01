import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima } from '@/shared/domain/auth';

type SipDb = ReturnType<typeof createAdminSupabase>;

const TASKLINE_LABEL: Record<string, string> = {
  aurum_novo: 'Aurum — Novo',
  aurum_senior: 'Aurum — Sênior',
  seminario_novo: 'Seminário — Novo',
  seminario_senior: 'Seminário — Sênior',
};

/**
 * Resolve a TRILHA (taskline) do aluno — porta de resolveTaskline do SIP.
 * ciclo 'aurum'/'seminario' têm duas trilhas conforme o Raio-X ("quantas
 * palestras/seminários já realizou?"): 0/ausente → _novo, ≥1 → _senior.
 */
async function resolveTaskline(
  sip: ReturnType<SipDb['schema']>,
  cicloType: string | null,
  answers: Record<string, unknown> | null,
): Promise<string> {
  if (cicloType !== 'aurum' && cicloType !== 'seminario') return 'default';
  const categoria = cicloType === 'aurum' ? 'Palestras' : 'Seminários';
  const { data: q } = await sip
    .from('raiox_questions')
    .select('id')
    .eq('categoria', categoria)
    .eq('tipo', 'numero')
    .eq('active', true)
    .order('ordem', { ascending: true })
    .limit(1)
    .maybeSingle();
  const qid = q?.id as string | undefined;
  const raw = qid && answers ? Number(answers[qid]) : 0;
  const count = Number.isFinite(raw) && raw > 0 ? raw : 0;
  return count === 0 ? `${cicloType}_novo` : `${cicloType}_senior`;
}

// Progresso do aluno no SIP (Time Holding Brasil), cruzado por e-mail.
// O schema `sip` não é exposto ao anon — leitura via service role (admin gate).
export async function GET(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);

  const email = safeEmail(new URL(request.url).searchParams.get('email') || '');
  if (!email) return jsonError('E-mail inválido.', 400);

  const sip = createAdminSupabase().schema('sip');
  const { data: u } = await sip
    .from('users')
    .select('id, name, role, ciclo_type, current_ciclo_id, approval_status, onboarding_done, nivel, turma_aurum, turma_thb, raiox_score, raiox_max_score, raiox_answers, created_at')
    .ilike('email', email)
    .maybeSingle();

  if (!u) return jsonOk({ registrado: false });

  // Progresso de tarefas — SÓ da trilha do aluno (ciclo_type + taskline), tarefas
  // ativas e do aluno (owner != 'equipe'). Numerador só conta tarefas dessa trilha.
  let concluidas: number | null = null;
  let total: number | null = null;
  let taskline: string | null = null;
  try {
    taskline = await resolveTaskline(sip, u.ciclo_type, (u.raiox_answers as Record<string, unknown> | null) ?? null);
    const { data: tasks } = await sip
      .from('tasks')
      .select('id, owner')
      .eq('ciclo_type', u.ciclo_type)
      .eq('taskline', taskline)
      .eq('active', true);
    const validos = new Set((tasks ?? []).filter((t) => (t.owner ?? 'aluno') !== 'equipe').map((t) => t.id));
    total = validos.size;
    const { data: prog } = await sip
      .from('progress')
      .select('task_id')
      .eq('user_id', u.id)
      .eq('completed', true);
    concluidas = (prog ?? []).filter((p) => validos.has(p.task_id)).length;
  } catch {
    /* progresso é opcional */
  }

  return jsonOk({
    registrado: true,
    sip_user_id: u.id,
    nome: u.name,
    role: u.role,
    ciclo_type: u.ciclo_type,
    taskline,
    taskline_label: taskline ? TASKLINE_LABEL[taskline] ?? null : null,
    approval_status: u.approval_status,
    onboarding_done: u.onboarding_done,
    nivel: u.nivel,
    turma: u.turma_aurum || u.turma_thb || null,
    raiox: u.raiox_score != null ? { score: u.raiox_score, max: u.raiox_max_score } : null,
    tarefas: { concluidas, total },
    criado_em: u.created_at,
  });
}
