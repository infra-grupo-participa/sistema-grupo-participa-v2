import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { cargosGrantaveis, podeEditarUsuario } from '@/modules/usuarios/domain/cargos';
import { appOrigin, buildAccessLink } from '@/modules/usuarios/domain/access-link';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

const PERFIL_COLS = 'id, nome, email, cargo, status, funcoes, pode_ver_cpf_completo, areas, time, criado_em';

// Chave de função: `setor.acao` (minúsculas/underscore) — mesma gramática de temFuncao()/tem_permissao().
const FUNCAO_RE = /^[a-z_]+\.[a-z_]+$/;
const acessoV2 = ACESSO_DEPARTAMENTOS.acessoV2 === true;

function podeGerirUsuarios(user: Awaited<ReturnType<typeof getCurrentUser>>): boolean {
  return !!user && (acessoV2 ? user.acesso?.master === true : ehAdminOuAcima(user));
}

type ResultadoAtualizacao = { ok: true } | { ok: false; code: string };

/** A RPC registra o autor no log. A migração 20261007204017 já está aplicada. */
async function atualizarPerfil(admin: ReturnType<typeof createAdminSupabase>, autor: string, id: string, patch: Record<string, unknown>): Promise<ResultadoAtualizacao> {
  const { data, error } = await admin.rpc('acesso_perfil_atualizar_como', { p_autor: autor, p_id: id, p_patch: patch });
  if (error) return { ok: false, code: error.code || 'ERRO' };
  const resposta = data as { ok?: unknown; id?: unknown } | null;
  return resposta?.ok === true && resposta.id === id ? { ok: true } : { ok: false, code: 'RESPOSTA_INVALIDA' };
}

function erroAtualizacao(code: string, convite = false) {
  if (code === '42501') return jsonError('Sem direito de gerir este perfil ou alteração bloqueada pelo banco. Cargo admin/dev é restrito a master ou exceção nominal; acesso a CPF deve ser concedido pela capacidade cpf.ver.', 403);
  if (code === '22023') return jsonError('Campos do perfil inválidos. Revise a alteração.', 400);
  if (code === 'P0002') return jsonError('Usuário não encontrado.', 404);
  if (code === 'PGRST202') return jsonError('A função de atualização de usuários não está disponível no banco. Tente novamente mais tarde.', 503);
  return jsonError(convite ? 'Não foi possível salvar o perfil do convite.' : 'Não foi possível salvar o perfil.', 502);
}

// Gestão de perfis: no acesso v2, só master; permissões são geridas pelas RPCs de acesso.
export async function GET() {
  const user = await getCurrentUser();
  if (!podeGerirUsuarios(user)) return jsonError('Não autorizado.', 403);
  const admin = createAdminSupabase();
  const { data } = await admin.from('perfis').select(PERFIL_COLS).order('criado_em', { ascending: false });
  return jsonOk({ ok: true, usuarios: data ?? [] });
}

export async function PATCH(request: NextRequest) {
  const user = await getCurrentUser();
  if (!podeGerirUsuarios(user)) return jsonError('Não autorizado.', 403);
  if (!user) return jsonError('Não autorizado.', 403);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const id = String(body?.id ?? '');
  if (!isUuid(id)) return jsonError('ID inválido.', 400);

  const admin = createAdminSupabase();
  const { data: alvo } = await admin.from('perfis').select('id, cargo').eq('id', id).maybeSingle();
  if (!alvo) return jsonError('Usuário não encontrado.', 404);

  const alvoCargo = normalizeCargo(alvo);
  if (!acessoV2 && !podeEditarUsuario(user.cargo, alvoCargo)) return jsonError('Sem permissão para editar este usuário.', 403);

  const fields = body?.fields && typeof body.fields === 'object' && !Array.isArray(body.fields)
    ? body.fields as Record<string, unknown> : {};
  if (acessoV2 && ('cargo' in fields || 'pode_ver_cpf_completo' in fields || 'areas' in fields || 'funcoes' in fields)) {
    return jsonError('Use Departamentos e áreas para definir permissões.', 400);
  }
  const patch: Record<string, unknown> = {};
  if (typeof fields.nome === 'string') patch.nome = fields.nome.trim();
  if (typeof fields.status === 'string' && ['ativo', 'pendente', 'negado'].includes(fields.status)) patch.status = fields.status;
  if (!acessoV2 && typeof fields.pode_ver_cpf_completo === 'boolean') patch.pode_ver_cpf_completo = fields.pode_ver_cpf_completo;
  if (!acessoV2 && Array.isArray(fields.areas)) patch.areas = fields.areas.filter((a) => typeof a === 'string');
  if (!acessoV2 && Array.isArray(fields.funcoes)) patch.funcoes = fields.funcoes.filter((f) => typeof f === 'string' && FUNCAO_RE.test(f));
  if (typeof fields.time === 'string') patch.time = fields.time.trim() || null;

  if (!acessoV2 && typeof fields.cargo === 'string') {
    const novo = fields.cargo as Cargo;
    if (!cargosGrantaveis(user.cargo).includes(novo)) return jsonError('Você não pode atribuir este cargo.', 403);
    patch.cargo = novo;
  }

  const resultado = await atualizarPerfil(admin, user.id, id, patch);
  return resultado.ok ? jsonOk({ ok: true }) : erroAtualizacao(resultado.code);
}

export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!podeGerirUsuarios(user)) return jsonError('Não autorizado.', 403);
  if (!user) return jsonError('Não autorizado.', 403);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const email = safeEmail(String(body?.email ?? ''));
  const nome = String(body?.nome ?? '').trim();
  const cargo = String(body?.cargo ?? 'visualizador') as Cargo;
  if (!email) return jsonError('E-mail inválido.', 400);
  if (acessoV2 && (body?.cargo !== undefined || body?.pode_ver_cpf_completo !== undefined || body?.areas !== undefined || body?.funcoes !== undefined)) {
    return jsonError('Use Departamentos e áreas para definir permissões.', 400);
  }
  if (!acessoV2 && !cargosGrantaveis(user.cargo).includes(cargo)) return jsonError('Você não pode atribuir este cargo.', 403);

  const areas = Array.isArray(body?.areas) ? (body.areas as unknown[]).filter((a): a is string => typeof a === 'string') : [];
  const funcoes = Array.isArray(body?.funcoes) ? (body.funcoes as unknown[]).filter((f): f is string => typeof f === 'string' && FUNCAO_RE.test(f)) : [];
  const podeVerCpf = body?.pode_ver_cpf_completo === true;

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

  // O trigger handle_new_user cria o perfil; no v2, vínculos e capacidades são definidos pelas RPCs.
  const perfilPatch = acessoV2 ? {
      nome: nome || null,
      status: 'ativo',
    } : {
      nome: nome || null,
      cargo,
      status: 'ativo',
      areas,
      funcoes,
      pode_ver_cpf_completo: podeVerCpf,
    };
  const resultado = await atualizarPerfil(admin, user.id, gen.user.id, perfilPatch);
  if (!resultado.ok) return erroAtualizacao(resultado.code, true);

  const link = buildAccessLink(origin, gen.properties.hashed_token, 'invite');
  return jsonOk({ ok: true, id: gen.user.id, link });
}
