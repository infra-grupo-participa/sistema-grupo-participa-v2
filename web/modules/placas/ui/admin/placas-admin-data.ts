'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { AUDIT_STEP_INDEX, AUDIT_STEPS, planAuditAdvance, statusForAuditStep, type AdvancePlan } from '../../domain/auditoria';
import type { Solicitacao, Auditoria, HorarioSlot } from '../../domain/types';
import { buildAdminSeenPatch } from '../../domain/solicitacao';

// Camada de dados/ações do painel admin de placas (browser, sessão do usuário → RLS).
// Porta das funções de relatorios.html (bootstrap/avancar/voltar/agenda/etc).

const db = () => createBrowserSupabase();
const nowBr = () => {
  const d = new Date();
  return d.toLocaleDateString('pt-BR') + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
};

async function sendStatusEmail(tipo: string, sol: Partial<Solicitacao>, extra: Record<string, string> = {}) {
  try {
    await fetch('/api/email/status', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tipo, email: sol.email, nome: sol.nome, token: sol.token, ...extra }),
    });
  } catch {
    /* e-mail é melhor-esforço */
  }
}

function agendarLink(token?: string | null): string {
  if (!token) return '';
  return `${window.location.origin}/agendar-entrevista?token=${encodeURIComponent(token)}`;
}

export async function loadSolicitacoes(): Promise<Solicitacao[]> {
  const { data, error } = await db()
    .from('thb_placas_solicitacoes')
    .select('*')
    .order('updated_at', { ascending: false })
    .range(0, 9999);
  logQueryError('loadSolicitacoes', error);
  return (data as Solicitacao[]) ?? [];
}

export async function loadAuditorias(): Promise<Auditoria[]> {
  // O painel só consome aluno_id/step_index/dates — payload enxuto (obs/protocolo ficam de fora).
  const { data, error } = await db().from('thb_placas_auditoria').select('aluno_id, step_index, dates');
  logQueryError('loadAuditorias', error);
  return (data as Auditoria[]) ?? [];
}

/** Escapa curingas de (i)like — o valor deve casar literal. */
const escapeLike = (s: string) => s.replace(/[\\%_]/g, '\\$&');

/** Protocolo legível e estável por solicitação (PRD prevê rastreabilidade por protocolo). */
const gerarProtocolo = (sol: Solicitacao) =>
  `PL-${new Date().getFullYear()}-${String(sol.id).replace(/-/g, '').slice(0, 8).toUpperCase()}`;

/** Inicia a auditoria: cria/atualiza aluno, garante auditoria step 0, marca sol em_auditoria. */
export async function bootstrapAuditoria(sol: Solicitacao): Promise<void> {
  const supabase = db();
  const email = String(sol.email || '').trim().toLowerCase();
  let alunoId = sol.aluno_id;

  if (!alunoId && email) {
    // ilike: o matching precisa ser case-insensitive como no promoteToAluno — `.eq` não
    // casava "Joao@X.com" e criava um segundo aluno para a mesma pessoa.
    const { data: existe } = await supabase.from('thb_alunos').select('id').ilike('email', escapeLike(email)).limit(1).maybeSingle();
    if (existe?.id) {
      alunoId = existe.id;
    } else {
      const { data: novo } = await supabase
        .from('thb_alunos')
        .insert({
          nome: sol.nome,
          email,
          telefone: sol.telefone || null,
          nivel_resultado: sol.nivel || null,
          documento: sol.documento_nf || null,
          estado: sol.estado_uf || null,
          cidade: sol.cidade || null,
          cep: sol.cep || null,
          bairro: sol.bairro || null,
          endereco_logradouro: sol.logradouro || null,
          endereco_numero: sol.numero || null,
          endereco_complemento: sol.complemento || null,
        })
        .select('id')
        .single();
      alunoId = novo?.id;
    }
  }
  if (!alunoId) throw new Error('Não foi possível vincular o aluno.');

  // Idempotente: se a auditoria já existe, NÃO reseta step/dates (o upsert antigo apagava
  // todo o histórico de carimbos quando o bootstrap reprocessava a mesma linha).
  const { data: audExistente } = await supabase
    .from('thb_placas_auditoria')
    .select('id, protocolo')
    .eq('aluno_id', alunoId)
    .maybeSingle();

  if (!audExistente) {
    const { error } = await supabase.from('thb_placas_auditoria').insert({
      aluno_id: alunoId,
      step_index: AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE,
      encerrado: false,
      dates: {},
      protocolo: gerarProtocolo(sol),
      faturamento: sol.faturamento_declarado || null,
      obs: `Solicitação via wizard (${new Date().toLocaleDateString('pt-BR')}). Nível declarado: ${sol.nivel || '-'}.`,
    });
    logQueryError('bootstrapAuditoria:insert', error);
    if (error) throw new Error('Não foi possível iniciar a auditoria.');
  } else if (!audExistente.protocolo) {
    await supabase.from('thb_placas_auditoria').update({ protocolo: gerarProtocolo(sol) }).eq('id', audExistente.id);
  }

  const { error: solErr } = await supabase
    .from('thb_placas_solicitacoes')
    .update({
      status: 'em_auditoria',
      aluno_id: alunoId,
      auditoria_step: AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE,
      step_index: AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE,
      regularizacao_pendente: false,
      motivo_retorno: null,
      ...buildAdminSeenPatch(true),
    })
    .eq('id', sol.id);
  logQueryError('bootstrapAuditoria:solicitacao', solErr);
  if (solErr) throw new Error('Não foi possível iniciar a auditoria.');
}

/** Auto-inicia auditorias pendentes (status 'enviado'). Porta de autoStartPendingAuditorias. */
export async function autoStartPending(sols: Solicitacao[]): Promise<boolean> {
  const pend = sols.filter((s) => s.status === 'enviado');
  if (!pend.length) return false;
  for (const s of pend) {
    try {
      await bootstrapAuditoria(s);
    } catch {
      /* continua */
    }
  }
  return true;
}

/** Avança uma etapa de auditoria (com carimbo de data, status, e-mail e remoção de slot). */
export async function avancarEtapa(sol: Solicitacao): Promise<{ ok: boolean; msg: string }> {
  if (!sol.aluno_id) return { ok: false, msg: 'Auditoria não iniciada.' };
  const stepAtual = sol.auditoria_step ?? 0;
  const plan = planAuditAdvance(stepAtual, { hasCodigoRastreio: Boolean(sol.codigo_rastreio) });
  if ('blocked' in plan) {
    const m: Record<string, string> = {
      concluido: 'Processo já concluído.',
      aguardando_agendamento: 'Aguardando o cliente agendar a entrevista.',
      sem_rastreio: 'Informe o código de rastreio para continuar.',
    };
    return { ok: false, msg: m[plan.blocked] };
  }
  const p = plan as AdvancePlan;
  const supabase = db();
  const { data: aud } = await supabase.from('thb_placas_auditoria').select('dates').eq('aluno_id', sol.aluno_id).maybeSingle();
  const dates = { ...((aud?.dates as Record<string, string>) || {}), [p.stampStepKey]: nowBr() };
  const ehFinal = p.novoStep === AUDIT_STEP_INDEX.PLACA_RECEBIDA;

  // Sem transação no PostgREST: gravamos SEQUENCIAL, solicitação primeiro (é o que a UI e o
  // cliente leem). Se ela falhar, nada mudou. A auditoria é carimbo/histórico: falha nela é
  // logada e se auto-corrige no próximo upsert — antes, o Promise.all podia deixar a
  // solicitação avançada com e-mail não enviado e o botão travado para sempre.
  const r2 = await supabase
    .from('thb_placas_solicitacoes')
    .update({ auditoria_step: p.novoStep, step_index: p.novoStep, status: p.novoStatus, regularizacao_pendente: false, motivo_retorno: null, ...buildAdminSeenPatch(true) })
    .eq('id', sol.id);
  logQueryError('avancarEtapa:solicitacao', r2.error);
  if (r2.error) return { ok: false, msg: 'Não foi possível concluir a operação.' };

  // encerrado=true no passo final dispara o trigger fn_sync_placa_nivel (nível oficial no aluno).
  const r1 = await supabase
    .from('thb_placas_auditoria')
    .upsert({ aluno_id: sol.aluno_id, step_index: p.novoStep, dates, encerrado: ehFinal }, { onConflict: 'aluno_id' });
  logQueryError('avancarEtapa:auditoria', r1.error);

  if (p.removeInterviewSlot && sol.entrevista_data && sol.entrevista_hora) {
    // Delete direto por (data, hora): cobre slots duplicados (o select .maybeSingle() antigo
    // errava com múltiplas linhas e deixava o horário "usado" disponível para outros).
    await supabase
      .from('thb_horarios_disponiveis')
      .delete()
      .eq('slot_data', sol.entrevista_data)
      .eq('hora', String(sol.entrevista_hora).slice(0, 5));
  }

  if (p.emailEvent === 'docs_aprovados') await sendStatusEmail('docs_aprovados', sol, { token_link: agendarLink(sol.token) });
  else if (p.emailEvent === 'entrevista_finalizada') await sendStatusEmail('entrevista_finalizada', sol);
  else if (p.emailEvent === 'placa_em_caminho') await sendStatusEmail('placa_em_caminho', sol, { codigo_rastreio: sol.codigo_rastreio || '' });
  if (ehFinal) await sendStatusEmail('placa_recebida', sol);

  return { ok: true, msg: `"${AUDIT_STEPS[stepAtual].name}" confirmada!` };
}

/** Volta uma etapa (sem disparar e-mail). Porta de voltarEtapa. */
export async function voltarEtapa(sol: Solicitacao): Promise<boolean> {
  if (!sol.aluno_id) return false;
  const novo = Math.max(0, (sol.auditoria_step ?? 0) - 1);
  const supabase = db();
  // Recomputa o status: sem isso, voltar de "Placa enviada" mantinha status placa_postada
  // e a fila/badge continuavam exibindo "7/7 · Placa enviada" com a etapa real atrás.
  const r2 = await supabase
    .from('thb_placas_solicitacoes')
    .update({ auditoria_step: novo, step_index: novo, status: statusForAuditStep(novo) })
    .eq('id', sol.id);
  logQueryError('voltarEtapa:solicitacao', r2.error);
  if (r2.error) return false;
  const r1 = await supabase
    .from('thb_placas_auditoria')
    .upsert({ aluno_id: sol.aluno_id, step_index: novo, encerrado: false }, { onConflict: 'aluno_id' });
  logQueryError('voltarEtapa:auditoria', r1.error);
  return true;
}

/** Aprova reenvio após correção → DOCS_APROVADOS + e-mail de agendamento. */
export async function aprovarReenvio(sol: Solicitacao): Promise<boolean> {
  if (!sol.proof_url || !sol.declaracao_url) return false;
  let s = sol;
  if (!s.aluno_id) {
    await bootstrapAuditoria(s);
    const { data } = await db().from('thb_placas_solicitacoes').select('*').eq('id', sol.id).single();
    s = (data as Solicitacao) ?? s;
  }
  const novoStep = AUDIT_STEP_INDEX.DOCS_APROVADOS;
  const supabase = db();
  const { data: aud } = await supabase.from('thb_placas_auditoria').select('dates').eq('aluno_id', s.aluno_id!).maybeSingle();
  const dates = { ...((aud?.dates as Record<string, string>) || {}), [AUDIT_STEPS[0].key]: nowBr() };
  const r2 = await supabase
    .from('thb_placas_solicitacoes')
    .update({ auditoria_step: novoStep, step_index: novoStep, status: 'docs_aprovados', regularizacao_pendente: false, motivo_retorno: null, ...buildAdminSeenPatch(true) })
    .eq('id', s.id);
  logQueryError('aprovarReenvio:solicitacao', r2.error);
  if (r2.error) return false; // antes retornava true mesmo com RLS negando — toast "Feito!" mentiroso
  const r1 = await supabase
    .from('thb_placas_auditoria')
    .upsert({ aluno_id: s.aluno_id, step_index: novoStep, dates, encerrado: false }, { onConflict: 'aluno_id' });
  logQueryError('aprovarReenvio:auditoria', r1.error);
  await sendStatusEmail('docs_aprovados', s, { token_link: agendarLink(s.token) });
  return true;
}

/**
 * Reprova/devolve a solicitação para correção.
 * Usa a RPC atômica fn_placas_reprovar (SECURITY DEFINER): grava snapshot imutável em
 * thb_placas_reprovacoes ANTES de resetar, limpa documentos/entrevista/etapa e marca
 * regularizacao_pendente. Assim o histórico fica auditável e o estado volta a "aguardando
 * nova documentação" (antes o v2 mantinha os docs e a fila mostrava "reenviou" na hora).
 */
export async function solicitarCorrecao(sol: Solicitacao, motivo: string): Promise<{ ok: boolean; msg: string }> {
  const m = motivo.trim();
  if (!m) return { ok: false, msg: 'Informe o motivo da reprovação.' };
  const supabase = db();
  const { error } = await supabase.rpc('fn_placas_reprovar', { p_sol_id: sol.id, p_motivo: m });
  if (error) return { ok: false, msg: 'Não foi possível registrar a reprovação.' };
  // A RPC zera admin_seen_at; como quem acabou de agir foi o admin, marcamos como visto
  // (o item volta a chamar atenção só quando o cliente reenviar).
  await supabase.from('thb_placas_solicitacoes').update(buildAdminSeenPatch(true)).eq('id', sol.id);
  await sendStatusEmail('retorno_auditoria', sol, { token_link: `${window.location.origin}/solicitar-placa?token=${sol.token}`, motivo_retorno: m });
  return { ok: true, msg: 'Reprovação registrada e cliente notificado.' };
}

/** thb_placas_reprovacoes — histórico imutável de reprovações (uma linha por evento). */
export interface Reprovacao {
  id: string;
  motivo: string;
  proof_url: string | null;
  declaracao_url: string | null;
  faturamento_declarado: number | null;
  nivel: string | null;
  step_index_reprovado: number | null;
  reprovado_por_email: string | null;
  created_at: string;
}

/** Carrega o histórico de reprovações da solicitação (mais recente primeiro). */
export async function loadReprovacoes(solId: string): Promise<Reprovacao[]> {
  const { data, error } = await db()
    .from('thb_placas_reprovacoes')
    .select('id, motivo, proof_url, declaracao_url, faturamento_declarado, nivel, step_index_reprovado, reprovado_por_email, created_at')
    .eq('solicitacao_id', solId)
    .order('created_at', { ascending: false });
  logQueryError('loadReprovacoes', error);
  return (data as Reprovacao[]) ?? [];
}

/** Não compareceu: reabre agendamento (volta para docs_aprovados, limpa entrevista) + e-mail. */
export async function marcarNaoCompareceu(sol: Solicitacao): Promise<boolean> {
  if (!sol.aluno_id) return false;
  const supabase = db();
  const r2 = await supabase
    .from('thb_placas_solicitacoes')
    .update({ auditoria_step: AUDIT_STEP_INDEX.DOCS_APROVADOS, step_index: AUDIT_STEP_INDEX.DOCS_APROVADOS, status: 'docs_aprovados', entrevista_data: null, entrevista_hora: null, entrevista_link: null, meet_link: null })
    .eq('id', sol.id);
  logQueryError('marcarNaoCompareceu:solicitacao', r2.error);
  if (r2.error) return false;
  const r1 = await supabase
    .from('thb_placas_auditoria')
    .upsert({ aluno_id: sol.aluno_id, step_index: AUDIT_STEP_INDEX.DOCS_APROVADOS, encerrado: false }, { onConflict: 'aluno_id' });
  logQueryError('marcarNaoCompareceu:auditoria', r1.error);
  await sendStatusEmail('nao_compareceu', sol, { token_link: agendarLink(sol.token) });
  return true;
}

/** Remanejamento rápido: posiciona a auditoria numa etapa específica (0–6). */
export async function setAuditStep(sol: Solicitacao, step: number): Promise<boolean> {
  let s = sol;
  if (!s.aluno_id) {
    await bootstrapAuditoria(s);
    const { data } = await db().from('thb_placas_solicitacoes').select('*').eq('id', sol.id).single();
    s = (data as Solicitacao) ?? s;
  }
  if (!s.aluno_id) return false;
  const supabase = db();
  const ehFinal = step === AUDIT_STEP_INDEX.PLACA_RECEBIDA;
  const r2 = await supabase
    .from('thb_placas_solicitacoes')
    .update({ auditoria_step: step, step_index: step, status: statusForAuditStep(step), regularizacao_pendente: false, motivo_retorno: null, ...buildAdminSeenPatch(true) })
    .eq('id', s.id);
  logQueryError('setAuditStep:solicitacao', r2.error);
  if (r2.error) return false;
  const r1 = await supabase
    .from('thb_placas_auditoria')
    .upsert({ aluno_id: s.aluno_id, step_index: step, encerrado: ehFinal }, { onConflict: 'aluno_id' });
  logQueryError('setAuditStep:auditoria', r1.error);
  return true;
}

/** "Já possui placa — avançar para o final": conclui o processo. */
export async function confirmarJaPossuiPlaca(sol: Solicitacao): Promise<boolean> {
  return setAuditStep(sol, AUDIT_STEP_INDEX.PLACA_RECEBIDA);
}

/** Exclui a solicitação (e a auditoria vinculada). Ação destrutiva. */
export async function excluirSolicitacao(sol: Solicitacao): Promise<boolean> {
  const supabase = db();
  if (sol.aluno_id) await supabase.from('thb_placas_auditoria').delete().eq('aluno_id', sol.aluno_id);
  const { error } = await supabase.from('thb_placas_solicitacoes').delete().eq('id', sol.id);
  if (error) {
    logQueryError('excluirSolicitacao', error);
    return false;
  }
  // Limpa o vínculo no hub central — sem isso o aluno ficava apontando para uma
  // solicitação inexistente (o rastreio já persistido em placa_codigo_rastreio permanece).
  if (sol.aluno_id) {
    await supabase.from('thb_alunos').update({ placa_solicitacao_id: null }).eq('id', sol.aluno_id);
  }
  return true;
}

/** Rejeição definitiva: mantém o registro, notifica o cliente. Reversível via Remanejamento. */
export async function rejeitar(sol: Solicitacao, motivo?: string): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update({ status: 'rejeitado', motivo_retorno: motivo?.trim() || null, ...buildAdminSeenPatch(true) }).eq('id', sol.id);
  if (error) {
    logQueryError('rejeitar', error);
    return false;
  }
  await sendStatusEmail('solicitacao_rejeitada', sol, motivo?.trim() ? { motivo_retorno: motivo.trim() } : {});
  return true;
}

export async function salvarRastreio(sol: Solicitacao, codigo: string): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update({ codigo_rastreio: codigo.trim() || null }).eq('id', sol.id);
  return !error;
}

export async function marcarVisto(sol: Solicitacao, visto: boolean): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update(buildAdminSeenPatch(visto)).eq('id', sol.id);
  return !error;
}

/** Campos que o admin pode editar diretamente na solicitação. */
export type DadosEditaveis = Partial<
  Pick<
    Solicitacao,
    | 'nome'
    | 'email'
    | 'telefone'
    | 'turma'
    | 'profissao'
    | 'nivel'
    | 'interesse'
    | 'espaco_instrucao'
    | 'faturamento_declarado'
    | 'cep'
    | 'logradouro'
    | 'numero'
    | 'complemento'
    | 'bairro'
    | 'cidade'
    | 'estado_uf'
    | 'documento_nf'
    | 'email_entrega'
  >
>;

/**
 * Atualiza os dados da solicitação e propaga (write-back) para thb_alunos quando
 * já vinculada — mantém o hub central em sincronia (convenção do projeto).
 */
export async function atualizarDadosSolicitacao(
  sol: Solicitacao,
  campos: DadosEditaveis,
): Promise<{ ok: boolean; msg: string }> {
  const supabase = db();
  const patch: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(campos)) {
    patch[k] = typeof v === 'string' ? (v.trim() === '' ? null : v.trim()) : v;
  }
  if (!Object.keys(patch).length) return { ok: false, msg: 'Nada para salvar.' };

  const { error } = await supabase.from('thb_placas_solicitacoes').update(patch).eq('id', sol.id);
  if (error) return { ok: false, msg: 'Não foi possível salvar os dados.' };

  // Write-back para thb_alunos (só campos correspondentes, quando vinculado).
  if (sol.aluno_id) {
    const back: Record<string, unknown> = {};
    if ('nome' in patch) back.nome = patch.nome;
    if ('email' in patch) back.email = patch.email;
    if ('telefone' in patch) back.telefone = patch.telefone;
    if ('nivel' in patch) back.nivel_resultado = patch.nivel;
    if ('documento_nf' in patch) back.documento = patch.documento_nf;
    if ('estado_uf' in patch) back.estado = patch.estado_uf;
    if ('cidade' in patch) back.cidade = patch.cidade;
    if ('cep' in patch) back.cep = patch.cep;
    if ('bairro' in patch) back.bairro = patch.bairro;
    if ('logradouro' in patch) back.endereco_logradouro = patch.logradouro;
    if ('numero' in patch) back.endereco_numero = patch.numero;
    if ('complemento' in patch) back.endereco_complemento = patch.complemento;
    if (Object.keys(back).length) {
      await supabase.from('thb_alunos').update(back).eq('id', sol.aluno_id);
    }
  }
  return { ok: true, msg: 'Dados atualizados!' };
}

// ── Agenda de horários ──
export async function loadHorarios(): Promise<HorarioSlot[]> {
  const { data, error } = await db().from('thb_horarios_disponiveis').select('*').order('slot_data', { ascending: true }).order('hora', { ascending: true });
  logQueryError('loadHorarios', error);
  return (data as HorarioSlot[]) ?? [];
}
export async function criarHorario(slotData: string, hora: string): Promise<boolean> {
  const supabase = db();
  // Sem duplicata: a UI deduplica a exibição, então um slot repetido ficava invisível no
  // painel mas contava no banco (e quebrava a remoção automática ao finalizar a entrevista).
  const { data: existente } = await supabase
    .from('thb_horarios_disponiveis')
    .select('id')
    .eq('slot_data', slotData)
    .eq('hora', hora)
    .limit(1)
    .maybeSingle();
  if (existente) return false;
  const { error } = await supabase.from('thb_horarios_disponiveis').insert({ slot_data: slotData, hora, ativo: true });
  return !error;
}
export async function toggleHorario(id: number, ativo: boolean): Promise<boolean> {
  const { error } = await db().from('thb_horarios_disponiveis').update({ ativo }).eq('id', id);
  return !error;
}
export async function excluirHorario(id: number): Promise<boolean> {
  const { error } = await db().from('thb_horarios_disponiveis').delete().eq('id', id);
  return !error;
}
