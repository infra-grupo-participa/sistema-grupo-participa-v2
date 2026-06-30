import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima } from '@/shared/domain/auth';

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
    .select('id, name, role, ciclo_type, current_ciclo_id, approval_status, onboarding_done, nivel, turma_aurum, turma_thb, raiox_score, raiox_max_score, created_at')
    .ilike('email', email)
    .maybeSingle();

  if (!u) return jsonOk({ registrado: false });

  // Progresso de tarefas (defensivo — não quebra o card se o modelo mudar).
  let concluidas: number | null = null;
  let total: number | null = null;
  try {
    const [done, tasks] = await Promise.all([
      sip.from('progress').select('id', { count: 'exact', head: true }).eq('user_id', u.id).eq('completed', true),
      sip.from('tasks').select('id', { count: 'exact', head: true }),
    ]);
    concluidas = done.count ?? null;
    total = tasks.count ?? null;
  } catch {
    /* progresso é opcional */
  }

  return jsonOk({
    registrado: true,
    sip_user_id: u.id,
    nome: u.name,
    role: u.role,
    ciclo_type: u.ciclo_type,
    approval_status: u.approval_status,
    onboarding_done: u.onboarding_done,
    nivel: u.nivel,
    turma: u.turma_aurum || u.turma_thb || null,
    raiox: u.raiox_score != null ? { score: u.raiox_score, max: u.raiox_max_score } : null,
    tarefas: { concluidas, total },
    criado_em: u.created_at,
  });
}
