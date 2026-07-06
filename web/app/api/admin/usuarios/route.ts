import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { cargosGrantaveis, podeEditarUsuario } from '@/modules/usuarios/domain/cargos';
import { appOrigin, buildAccessLink } from '@/modules/usuarios/domain/access-link';

const PERFIL_COLS = 'id, nome, email, cargo, status, funcoes, pode_ver_cpf_completo, areas, time, criado_em';

// Chave de função: `setor.acao` (minúsculas/underscore) — mesma gramática de temFuncao()/tem_permissao().
const FUNCAO_RE = /^[a-z_]+\.[a-z_]+$/;

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
  const { data: alvo } = await admin.from('perfis').select('id, cargo').eq('id', id).maybeSingle();
  if (!alvo) return jsonError('Usuário não encontrado.', 404);

  const alvoCargo = normalizeCargo(alvo);
  if (!podeEditarUsuario(user.cargo, alvoCargo)) return jsonError('Sem permissão para editar este usuário.', 403);

  const fields = (body?.fields ?? {}) as Record<string, unknown>;
  const patch: Record<string, unknown> = {};
  if (typeof fields.nome === 'string') patch.nome = fields.nome.trim();
  if (typeof fields.status === 'string' && ['ativo', 'pendente', 'negado'].includes(fields.status)) patch.status = fields.status;
  if (typeof fields.pode_ver_cpf_completo === 'boolean') patch.pode_ver_cpf_completo = fields.pode_ver_cpf_completo;
  if (Array.isArray(fields.areas)) patch.areas = fields.areas.filter((a) => typeof a === 'string');
  if (Array.isArray(fields.funcoes)) patch.funcoes = fields.funcoes.filter((f) => typeof f === 'string' && FUNCAO_RE.test(f));
  if (typeof fields.time === 'string') patch.time = fields.time.trim() || null;

  if (typeof fields.cargo === 'string') {
    const novo = fields.cargo as Cargo;
    if (!cargosGrantaveis(user.cargo).includes(novo)) return jsonError('Você não pode atribuir este cargo.', 403);
    patch.cargo = novo;
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
  const origin = appOrigin(request);
  // generateLink cria o auth user SEM enviar e-mail e devolve o hashed_token —
  // montamos o link copiável que o admin envia pelo canal que quiser.
  const { data: gen, error: genErr } = await admin.auth.admin.generateLink({
    type: 'invite',
    email,
    options: { redirectTo: origin + '/auth/confirm' },
  });
  if (genErr || !gen?.user || !gen.properties?.hashed_token) {
    return jsonError('Não foi possível gerar o convite: ' + (genErr?.message || ''), 502);
  }

  // O trigger handle_new_user cria o perfil; ajustamos cargo/status/nome.
  await admin
    .from('perfis')
    .update({
      nome: nome || null,
      cargo,
      status: 'ativo',
      atualizado_em: new Date().toISOString(),
    })
    .eq('id', gen.user.id);

  const link = buildAccessLink(origin, gen.properties.hashed_token, 'invite');
  return jsonOk({ ok: true, id: gen.user.id, link });
}
