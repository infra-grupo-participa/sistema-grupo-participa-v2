import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, validateOrigin } from '@/shared/infrastructure/http/security';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createServerSupabase } from '@/shared/infrastructure/supabase/server-client';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { caminhoMidiaValido, erroMotivoExclusao } from '@/modules/comercial/domain/excluir-conversa';

export const dynamic = 'force-dynamic';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BUCKET = 'crm-midia';

// POST /api/comercial/conversas/excluir {conversaId, motivo} — "Excluir conversa" (só gestor do Comercial).
// 1) crm_excluir_conversa com o JWT de quem clicou: o banco confere gestor/leitor/motivo, marca a conversa e as
//    mensagens como excluídas (exclusão lógica), grava o registro e avisa as telas (migration 20261008190613).
// 2) Só depois do ok: apaga do bucket privado crm-midia os arquivos dessas mensagens (lixo de teste), com service role.
//    Os caminhos vêm do banco, nunca do corpo do pedido. Falhou? A exclusão vale; o arquivo fica para limpeza posterior
//    (consulta no .explain.md da migration).
export async function POST(req: NextRequest) {
  if (!validateOrigin(req)) return jsonError('Origem não permitida.', 403);
  const user = await getCurrentUser();
  if (!user) return jsonError('Não autorizado.', 401);
  const corpo = (await req.json().catch(() => null)) as { conversaId?: unknown; motivo?: unknown } | null;
  const conversaId = typeof corpo?.conversaId === 'string' ? corpo.conversaId : '';
  const motivo = typeof corpo?.motivo === 'string' ? corpo.motivo : '';
  if (!UUID.test(conversaId)) return jsonError('Conversa inválida.', 400);
  const erroMotivo = erroMotivoExclusao(motivo);
  if (erroMotivo) return jsonError(erroMotivo, 400);

  const { data, error } = await (await createServerSupabase()).rpc('crm_excluir_conversa', { p_conversa: conversaId, p_motivo: motivo.trim() });
  if (error) return jsonError('Não foi possível falar com o banco.', 502);
  const r = (data ?? {}) as { ok?: unknown; msg?: unknown; mensagens?: unknown; midias?: unknown };
  if (r.ok !== true) return jsonError(typeof r.msg === 'string' ? r.msg : 'Não foi possível excluir a conversa.', 403);

  const midias = Array.isArray(r.midias) ? r.midias.filter(caminhoMidiaValido) : [];
  let midiasPendentes = 0;
  if (midias.length) {
    try {
      const { error: e } = await createAdminSupabase().storage.from(BUCKET).remove(midias);
      if (e) midiasPendentes = midias.length;
    } catch {
      midiasPendentes = midias.length;
    }
  }
  return jsonOk({
    ok: true,
    msg: typeof r.msg === 'string' ? r.msg : 'Conversa excluída.',
    mensagens: typeof r.mensagens === 'number' ? r.mensagens : 0,
    midiasRemovidas: midias.length - midiasPendentes,
    midiasPendentes,
  });
}
