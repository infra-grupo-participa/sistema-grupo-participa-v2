import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { cargosGrantaveis, podeEditarUsuario } from '@/modules/usuarios/domain/cargos';

const PERFIL_COLS = 'id, nome, email, cargo, status, nivel_hierarquia, eh_dev, pode_ver_cpf_completo, areas, time, criado_em';

// Porta das ações de usuário do admin-proxy.php — gestão de perfis (service_role + hierarquia).
export async function GET() {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);
  const admin = createAdminSupabase();
  const { data } = await admin.from('perfis').select(PERFIL_COLS).order('criado_em', { ascending: false });
  return jsonOk({ ok: true, usuarios: data ?? [] });
}

export async function PATCH(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const id = String(body?.id ?? '');
  if (!isUuid(id)) return jsonError('ID inválido.', 400);

  const admin = createAdminSupabase();
  const { data: alvo } = await admin.from('perfis').select('id, cargo, nivel_hierarquia, eh_dev').eq('id', id).maybeSingle();
  if (!alvo) return jsonError('Usuário não encontrado.', 404);

  const alvoCargo = normalizeCargo(alvo);
  if (!podeEditarUsuario(user.cargo, alvoCargo)) return jsonError('Sem permissão para editar este usuário.', 403);

  const fields = (body?.fields ?? {}) as Record<string, unknown>;
  const patch: Record<string, unknown> = {};
  if (typeof fields.nome === 'string') patch.nome = fields.nome.trim();
  if (typeof fields.status === 'string' && ['ativo', 'pendente', 'negado'].includes(fields.status)) patch.status = fields.status;
  if (typeof fields.pode_ver_cpf_completo === 'boolean') patch.pode_ver_cpf_completo = fields.pode_ver_cpf_completo;
  if (Array.isArray(fields.areas)) patch.areas = fields.areas.filter((a) => typeof a === 'string');
  if (typeof fields.time === 'string') patch.time = fields.time.trim() || null;

  if (typeof fields.cargo === 'string') {
    const novo = fields.cargo as Cargo;
    if (!cargosGrantaveis(user.cargo).includes(novo)) return jsonError('Você não pode atribuir este cargo.', 403);
    patch.cargo = novo;
    patch.eh_dev = novo === 'dev';
    patch.nivel_hierarquia = novo === 'admin' ? 'admin_principal' : novo;
  }

  patch.atualizado_em = new Date().toISOString();
  const { error } = await admin.from('perfis').update(patch).eq('id', id);
  return error ? jsonError('Não foi possível salvar.', 502) : jsonOk({ ok: true });
}

export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const email = safeEmail(String(body?.email ?? ''));
  const nome = String(body?.nome ?? '').trim();
  const cargo = String(body?.cargo ?? 'visualizador') as Cargo;
  if (!email) return jsonError('E-mail inválido.', 400);
  if (!cargosGrantaveis(user.cargo).includes(cargo)) return jsonError('Você não pode atribuir este cargo.', 403);

  const admin = createAdminSupabase();
  const redirectTo = (process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br') + '/login';
  const { data: invited, error: inviteErr } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
  if (inviteErr || !invited?.user) return jsonError('Não foi possível convidar: ' + (inviteErr?.message || ''), 502);

  // O trigger handle_new_user cria o perfil; ajustamos cargo/status/nome.
  await admin
    .from('perfis')
    .update({
      nome: nome || null,
      cargo,
      status: 'ativo',
      eh_dev: cargo === 'dev',
      nivel_hierarquia: cargo === 'admin' ? 'admin_principal' : cargo,
      atualizado_em: new Date().toISOString(),
    })
    .eq('id', invited.user.id);

  return jsonOk({ ok: true, id: invited.user.id });
}
