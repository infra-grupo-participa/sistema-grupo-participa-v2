import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, normalizeCargo } from '@/shared/domain/auth';
import { podeEditarUsuario } from '@/modules/usuarios/domain/cargos';
import { appOrigin, buildAccessLink } from '@/modules/usuarios/domain/access-link';

// Gera um link de acesso novo para um usuário JÁ existente (reenvio / pendente
// que perdeu o link). Recovery deixa a pessoa definir a senha e entrar.
export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const id = String(body?.id ?? '');
  if (!isUuid(id)) return jsonError('ID inválido.', 400);

  const admin = createAdminSupabase();
  const { data: alvo } = await admin.from('perfis').select('id, cargo, email').eq('id', id).maybeSingle();
  if (!alvo) return jsonError('Usuário não encontrado.', 404);
  if (!podeEditarUsuario(user.cargo, normalizeCargo(alvo))) {
    return jsonError('Sem permissão para este usuário.', 403);
  }

  const email = safeEmail(String(alvo.email ?? ''));
  if (!email) return jsonError('Usuário sem e-mail válido.', 400);

  const origin = appOrigin(request);
  const { data: gen, error: genErr } = await admin.auth.admin.generateLink({
    type: 'recovery',
    email,
    options: { redirectTo: origin + '/auth/confirm' },
  });
  if (genErr || !gen?.properties?.hashed_token) {
    return jsonError('Não foi possível gerar o link: ' + (genErr?.message || ''), 502);
  }

  const link = buildAccessLink(origin, gen.properties.hashed_token, 'recovery');
  return jsonOk({ ok: true, link });
}
