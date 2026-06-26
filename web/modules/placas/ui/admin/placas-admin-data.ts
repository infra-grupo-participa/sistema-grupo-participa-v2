'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { AUDIT_STEP_INDEX, AUDIT_STEPS, planAuditAdvance, type AdvancePlan } from '../../domain/auditoria';
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
  const { data } = await db()
    .from('thb_placas_solicitacoes')
    .select('*')
    .order('updated_at', { ascending: false })
    .range(0, 9999);
  return (data as Solicitacao[]) ?? [];
}

export async function loadAuditorias(): Promise<Auditoria[]> {
  const { data } = await db().from('thb_placas_auditoria').select('*');
  return (data as Auditoria[]) ?? [];
}

/** Inicia a auditoria: cria/atualiza aluno, upserta auditoria step 0, marca sol em_auditoria. */
export async function bootstrapAuditoria(sol: Solicitacao): Promise<void> {
  const supabase = db();
  const email = String(sol.email || '').trim().toLowerCase();
  let alunoId = sol.aluno_id;

  if (!alunoId && email) {
    const { data: existe } = await supabase.from('thb_alunos').select('id').eq('email', email).maybeSingle();
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

  await supabase.from('thb_placas_auditoria').upsert(
    {
      aluno_id: alunoId,
      step_index: AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE,
      encerrado: false,
      dates: {},
      faturamento: sol.faturamento_declarado || null,
      obs: `Solicitação via wizard (${new Date().toLocaleDateString('pt-BR')}). Nível declarado: ${sol.nivel || '-'}.`,
    },
    { onConflict: 'aluno_id' },
  );

  await supabase
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

  const [r1, r2] = await Promise.all([
    supabase.from('thb_placas_auditoria').upsert({ aluno_id: sol.aluno_id, step_index: p.novoStep, dates, encerrado: false }, { onConflict: 'aluno_id' }),
    supabase
      .from('thb_placas_solicitacoes')
      .update({ auditoria_step: p.novoStep, step_index: p.novoStep, status: p.novoStatus, regularizacao_pendente: false, motivo_retorno: null, ...buildAdminSeenPatch(true) })
      .eq('id', sol.id),
  ]);
  if (r1.error || r2.error) return { ok: false, msg: 'Não foi possível concluir a operação.' };

  if (p.removeInterviewSlot && sol.entrevista_data && sol.entrevista_hora) {
    const { data: slot } = await supabase
      .from('thb_horarios_disponiveis')
      .select('id')
      .eq('slot_data', sol.entrevista_data)
      .eq('hora', String(sol.entrevista_hora).slice(0, 5))
      .maybeSingle();
    if (slot?.id) await supabase.from('thb_horarios_disponiveis').delete().eq('id', slot.id);
  }

  if (p.emailEvent === 'docs_aprovados') await sendStatusEmail('docs_aprovados', sol, { token_link: agendarLink(sol.token) });
  else if (p.emailEvent === 'entrevista_finalizada') await sendStatusEmail('entrevista_finalizada', sol);
  else if (p.emailEvent === 'placa_em_caminho') await sendStatusEmail('placa_em_caminho', sol, { codigo_rastreio: sol.codigo_rastreio || '' });

  return { ok: true, msg: `"${AUDIT_STEPS[stepAtual].name}" confirmada!` };
}

/** Volta uma etapa (sem disparar e-mail). Porta de voltarEtapa. */
export async function voltarEtapa(sol: Solicitacao): Promise<boolean> {
  if (!sol.aluno_id) return false;
  const novo = Math.max(0, (sol.auditoria_step ?? 0) - 1);
  const supabase = db();
  const [r1, r2] = await Promise.all([
    supabase.from('thb_placas_auditoria').upsert({ aluno_id: sol.aluno_id, step_index: novo, encerrado: false }, { onConflict: 'aluno_id' }),
    supabase.from('thb_placas_solicitacoes').update({ auditoria_step: novo, step_index: novo }).eq('id', sol.id),
  ]);
  return !r1.error && !r2.error;
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
  await Promise.all([
    supabase.from('thb_placas_auditoria').upsert({ aluno_id: s.aluno_id, step_index: novoStep, dates, encerrado: false }, { onConflict: 'aluno_id' }),
    supabase.from('thb_placas_solicitacoes').update({ auditoria_step: novoStep, step_index: novoStep, status: 'docs_aprovados', regularizacao_pendente: false, motivo_retorno: null, ...buildAdminSeenPatch(true) }).eq('id', s.id),
  ]);
  await sendStatusEmail('docs_aprovados', s, { token_link: agendarLink(s.token) });
  return true;
}

/** Solicita correção: regularizacao_pendente + motivo + e-mail de retorno. */
export async function solicitarCorrecao(sol: Solicitacao, motivo: string): Promise<boolean> {
  const { error } = await db()
    .from('thb_placas_solicitacoes')
    .update({ regularizacao_pendente: true, motivo_retorno: motivo, ...buildAdminSeenPatch(true) })
    .eq('id', sol.id);
  if (error) return false;
  await sendStatusEmail('retorno_auditoria', sol, { token_link: `${window.location.origin}/solicitar-placa?token=${sol.token}`, motivo_retorno: motivo });
  return true;
}

/** Não compareceu: reabre agendamento (volta para docs_aprovados, limpa entrevista) + e-mail. */
export async function marcarNaoCompareceu(sol: Solicitacao): Promise<boolean> {
  if (!sol.aluno_id) return false;
  const supabase = db();
  await Promise.all([
    supabase.from('thb_placas_auditoria').upsert({ aluno_id: sol.aluno_id, step_index: AUDIT_STEP_INDEX.DOCS_APROVADOS, encerrado: false }, { onConflict: 'aluno_id' }),
    supabase.from('thb_placas_solicitacoes').update({ auditoria_step: AUDIT_STEP_INDEX.DOCS_APROVADOS, step_index: AUDIT_STEP_INDEX.DOCS_APROVADOS, status: 'docs_aprovados', entrevista_data: null, entrevista_hora: null, entrevista_link: null, meet_link: null }).eq('id', sol.id),
  ]);
  await sendStatusEmail('nao_compareceu', sol, { token_link: agendarLink(sol.token) });
  return true;
}

export async function rejeitar(sol: Solicitacao): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update({ status: 'rejeitado', ...buildAdminSeenPatch(true) }).eq('id', sol.id);
  return !error;
}

export async function salvarRastreio(sol: Solicitacao, codigo: string): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update({ codigo_rastreio: codigo.trim() || null }).eq('id', sol.id);
  return !error;
}

export async function marcarVisto(sol: Solicitacao, visto: boolean): Promise<boolean> {
  const { error } = await db().from('thb_placas_solicitacoes').update(buildAdminSeenPatch(visto)).eq('id', sol.id);
  return !error;
}

// ── Agenda de horários ──
export async function loadHorarios(): Promise<HorarioSlot[]> {
  const { data } = await db().from('thb_horarios_disponiveis').select('*').order('slot_data', { ascending: true }).order('hora', { ascending: true });
  return (data as HorarioSlot[]) ?? [];
}
export async function criarHorario(slotData: string, hora: string): Promise<boolean> {
  const { error } = await db().from('thb_horarios_disponiveis').insert({ slot_data: slotData, hora, ativo: true });
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
