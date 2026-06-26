import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, clientIp } from '@/shared/infrastructure/http/security';
import { rateLimitOk } from '@/shared/infrastructure/http/rate-limit';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser, serverContainer } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import { transcriptApto, parseGroqHighlights } from '@/modules/depoimentos/domain/highlights';
import { HIGHLIGHTS_SYSTEM, buildHighlightsUserPrompt } from '@/modules/depoimentos/application/highlights-prompt';
import { groqChatJson } from '@/shared/infrastructure/ai/groq';

// Porta de app/api/depoimentos/processar-highlights.php (Groq llama-3.3-70b).
export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || !ehAdminOuAcima(user)) return jsonError('Não autorizado.', 403);
  if (!rateLimitOk(clientIp(request), 'gp_dep_highlights_rate_', 30, 300)) return jsonError('Tente novamente em instantes.', 429);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const id = String(body?.depoimento_id ?? '').toLowerCase().trim();
  if (!isUuid(id)) return jsonError('ID do depoimento inválido.', 400);

  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) return jsonError('Serviço de IA não configurado no servidor.', 500);
  const model = process.env.GROQ_HIGHLIGHTS_MODEL || 'llama-3.3-70b-versatile';

  const { supabase } = await serverContainer();

  const { data: dep } = await supabase.from('gp_depoimentos').select('id, aluno_id, transcript, profissao').eq('id', id).maybeSingle();
  if (!dep) return jsonError('Depoimento não encontrado.', 404);
  if (!transcriptApto(dep.transcript as string)) return jsonError('Transcrição vazia ou muito curta para gerar highlights.', 400);

  let alunoNome = '', alunoNivel = '', cidade = '', estado = '';
  if (dep.aluno_id && isUuid(String(dep.aluno_id))) {
    const { data: aluno } = await supabase.from('thb_alunos').select('nome, nivel_resultado, cidade, estado').eq('id', dep.aluno_id).maybeSingle();
    if (aluno) {
      alunoNome = String(aluno.nome ?? '');
      alunoNivel = nivelLabel(aluno.nivel_resultado) || '';
      cidade = String(aluno.cidade ?? '');
      estado = String(aluno.estado ?? '');
    }
  }

  await supabase.from('gp_depoimentos').update({ highlights_status: 'processando', highlights_erro: null, updated_by: user.id }).eq('id', id);

  const r = await groqChatJson({
    apiKey: groqKey,
    model,
    system: HIGHLIGHTS_SYSTEM,
    user: buildHighlightsUserPrompt({ alunoNome, profissao: String(dep.profissao ?? ''), alunoNivel, cidade, estado, transcript: String(dep.transcript) }),
  });

  const markErr = async (erro: string) => {
    await supabase.from('gp_depoimentos').update({ highlights_status: 'erro', highlights_erro: erro.slice(0, 400), updated_by: user.id }).eq('id', id);
  };

  if (r.status === 0 || r.error) {
    await markErr('Falha ao conectar no serviço de IA.');
    return jsonError('Falha ao conectar no serviço de IA.', 502);
  }
  if (r.status === 429) {
    await supabase.from('gp_rate_limit_log').insert({ endpoint: 'processar-highlights', provider: 'groq', modelo: model, http_status: 429, message: r.upstreamMessage, retry_after: r.retryAfter || null, depoimento_id: id });
    await supabase.from('gp_depoimentos').update({ highlights_status: 'limite_diario', highlights_erro: 'Limite diário do serviço de IA atingido.', updated_by: user.id }).eq('id', id);
    return jsonOk({ ok: false, code: 'LIMITE_DIARIO', titulo: 'Limite diário do serviço atingido', mensagem: 'Usamos o Groq no plano gratuito para gerar os highlights. O limite renova em algumas horas. Seus dados estão salvos — basta tentar novamente mais tarde.', retry_after: r.retryAfter }, 429);
  }
  if (r.status < 200 || r.status >= 300) {
    await markErr(r.upstreamMessage || 'Resposta inválida do serviço de IA.');
    return jsonError('O serviço de IA não conseguiu gerar os highlights agora.', 502);
  }

  let parsed: Record<string, unknown> | null = null;
  try {
    parsed = JSON.parse(r.content);
  } catch {
    parsed = null;
  }
  if (!parsed) {
    await markErr('IA retornou formato inválido.');
    return jsonError('O serviço de IA retornou um formato inválido.', 502);
  }

  const result = parseGroqHighlights(parsed);
  const update = {
    highlights: result.highlights,
    objecao: result.objecao,
    antes_depois: result.antes_depois,
    gancho: result.gancho,
    resumo: result.resumo,
    highlights_status: 'ok',
    highlights_processado_em: new Date().toISOString(),
    highlights_erro: null,
    highlights_modelo: model,
    updated_by: user.id,
  };
  await supabase.from('gp_depoimentos').update(update).eq('id', id);
  return jsonOk({ ok: true, data: update });
}
