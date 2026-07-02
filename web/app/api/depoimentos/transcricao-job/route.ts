import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, clientIp } from '@/shared/infrastructure/http/security';
import { rateLimitOk } from '@/shared/infrastructure/http/rate-limit';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { extractDriveFolderId } from '@/modules/depoimentos/domain/drive';

// Porta de app/api/depoimentos/transcricao-job.php.
// O Node enfileira/consulta o job; o worker Python (faster-whisper) faz Drive + transcrição.

// Colunas que o cliente consome (interface TranscriptionJob) — evita puxar prompt_context/etc.
const JOB_COLS = 'id, status, transcript, source_audios_count, audios_succeeded, audios_failed, error_message, processing_notes';

export async function GET(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);
  if (!rateLimitOk(clientIp(request), 'gp_dep_job_rate_', 80, 300)) return jsonError('Tente novamente em instantes.', 429);

  const jobId = String(request.nextUrl.searchParams.get('id') ?? request.nextUrl.searchParams.get('job_id') ?? '').toLowerCase();
  if (!isUuid(jobId)) return jsonError('Informe um job válido.', 400);

  const admin = createAdminSupabase();
  const { data } = await admin.from('gp_depoimento_transcription_jobs').select(JOB_COLS).eq('id', jobId).maybeSingle();
  if (!data) return jsonError('Job de transcrição não encontrado.', 404);
  return jsonOk({ success: true, data });
}

export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);
  if (!rateLimitOk(clientIp(request), 'gp_dep_job_rate_', 80, 300)) return jsonError('Tente novamente em instantes.', 429);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const folderInput = String(body?.folder_url ?? body?.folder_id ?? '').trim();
  const folderId = extractDriveFolderId(folderInput);
  if (!folderId) return jsonError('Informe um link ou ID válido da pasta do Drive.', 400);

  const admin = createAdminSupabase();

  // Reaproveita job recente da mesma pasta (a não ser que force=true).
  const { data: latest } = await admin
    .from('gp_depoimento_transcription_jobs')
    .select(JOB_COLS)
    .eq('folder_id', folderId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!body?.force && latest && ['queued', 'processing', 'completed'].includes(String(latest.status))) {
    return jsonOk({ success: true, reused: true, data: latest });
  }

  const ctx = (body?.transcription_context ?? {}) as Record<string, unknown>;
  const { data: created, error } = await admin
    .from('gp_depoimento_transcription_jobs')
    .insert({
      folder_id: folderId,
      folder_url: typeof body?.folder_url === 'string' ? body.folder_url : null,
      provider: 'faster-whisper',
      status: 'queued',
      prompt_context: {
        student_name: String(ctx.student_name ?? ''),
        profession: String(ctx.profession ?? ''),
        turma_codigo: String(ctx.turma_codigo ?? ''),
        cidade: String(ctx.cidade ?? ''),
        estado: String(ctx.estado ?? ''),
      },
      requested_by: user.id,
    })
    .select(JOB_COLS)
    .single();

  if (error || !created) return jsonError('Não foi possível enfileirar a transcrição agora.', 502);
  return jsonOk({ success: true, queued: true, data: created });
}
