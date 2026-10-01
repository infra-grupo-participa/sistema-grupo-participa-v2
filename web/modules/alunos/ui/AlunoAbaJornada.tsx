'use client';

// Aba "Jornada" da ficha do aluno: placa, depoimento, SIP e histórico de níveis.
// Blocos movidos do AlunoDrawer sem alteração. Os dados de placa e ciclos são carregados
// pela moldura (AlunoDrawer) na abertura da ficha — não aqui —, porque as pendências do
// Resumo dependem deles e trocar de aba não pode disparar nova consulta.
import { useState } from 'react';
import type { Aluno360 } from '../domain/aluno-360';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import { placaCicloLabel, placaLembreteLabel, placaParadoInfo } from '../domain/placa-funil';
import type { PlacaHistorico } from './alunos-data';
import { AUDIT_STEPS } from '@/modules/placas/domain/auditoria';
import { computeDisplayStatus, displayStatusTone } from '@/modules/placas/domain/solicitacao';
import type { Ciclo } from '@/modules/placas/ui/admin/placas-admin-data';
import { Badge, SectionCard, CopyField, ProgressBar, Spinner, Timeline, type TimelineEntry } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { fetchJson } from '@/shared/ui/fetch-json';
import { SecTitle, Row } from './alunos-ui-bits';

export function AlunoAbaJornada({ a, temPlaca, placaHist, placaLoading, ciclos }: {
  a: Aluno360;
  temPlaca: boolean;
  placaHist: PlacaHistorico | null;
  placaLoading: boolean;
  ciclos: Ciclo[];
}) {
  return (
    <SectionCard title={<SecTitle icon="check-circle">Jornada</SecTitle>}>
      <div className="grid sm:grid-cols-2 sm:gap-x-4">
        <PlacaJornada a={a} on={temPlaca} hist={placaHist} loading={placaLoading} rastreioAluno={a.placa_rastreio} />
        <JornadaCard label="Depoimento" on={!!a.tem_depoimento} extra={a.total_depoimentos ? `${a.total_depoimentos} depoimento(s)` : ''} href={a.tem_depoimento ? '/depoimentos' : undefined} />
        <SipJornada email={a.email} on={!!a.sip_registrado} />
      </div>
      <HistoricoNiveis ciclos={ciclos} />
    </SectionCard>
  );
}

/** Histórico de níveis (placa + cadastro) — snapshots de ciclos anteriores. */
function HistoricoNiveis({ ciclos }: { ciclos: Ciclo[] }) {
  if (!ciclos.length) return null;
  return (
    <div className="mt-3">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-2">Histórico de níveis ({ciclos.length})</div>
      <div className="space-y-1.5">
        {ciclos.map((c) => {
          const ehPlaca = c.tipo === 'placa';
          return (
            <div key={c.id} className="flex items-center justify-between gap-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2">
              <span className="text-sm text-[var(--fg)] inline-flex items-center gap-2 min-w-0">
                <span className="grid place-items-center w-5 h-5 rounded-full bg-[var(--accent-subtle)] text-[var(--accent)] text-[10px] font-bold shrink-0">{c.ciclo}</span>
                <span className="truncate">{nivelLabel(c.nivel) || c.nivel || '—'}</span>
                <Badge tone={ehPlaca ? 'success' : 'neutral'}>{ehPlaca ? 'Placa' : 'Cadastro'}</Badge>
              </span>
              {c.concluido_em && <span className="text-[11px] text-[var(--fg-3)] shrink-0 tabular">{fmtData(c.concluido_em)}</span>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function JornadaCard({ label, on, extra, href }: { label: string; on: boolean; extra?: string; href?: string }) {
  const body = (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 transition-[border-color,background-color,box-shadow,transform] duration-150 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'} ${href ? 'hover:-translate-y-0.5 hover:shadow-[var(--shadow-md)] hover:border-[var(--border-accent)]' : ''}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">{label}</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? <span className="inline-flex items-center gap-1"><Icon name="check" size={12} /> Sim</span> : 'Não'}</span>
      </div>
      {extra && <div className="text-xs text-[var(--fg-3)] mt-1">{extra}</div>}
    </div>
  );
  return href ? <a href={href} className="block">{body}</a> : body;
}

// ── SIP: card de jornada expansível (progresso real + link pro card do aluno no SIP) ──
const SIP_BASE = process.env.NEXT_PUBLIC_SIP_URL || 'https://sip.grupoparticipa.app.br';
const SIP_STATUS: Record<string, string> = { approved: 'Aprovado', pending: 'Pendente', rejected: 'Rejeitado' };
const SIP_CICLO: Record<string, string> = { aurum: 'Aurum', seminario: 'Seminário', diamante: 'Diamante', platina: 'Platina' };

interface SipProgresso {
  registrado: boolean;
  sip_user_id?: string;
  ciclo_type?: string | null;
  taskline_label?: string | null;
  approval_status?: string | null;
  onboarding_done?: boolean | null;
  nivel?: string | null;
  turma?: string | null;
  raiox?: { score: number; max: number | null } | null;
  tarefas?: { concluidas: number | null; total: number | null };
  palestra?: { data: string; label: string } | null;
}

function SipJornada({ email, on }: { email: string | null; on: boolean }) {
  const [open, setOpen] = useState(false);
  const [data, setData] = useState<SipProgresso | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState(false);

  async function toggle() {
    const next = !open;
    setOpen(next);
    if (next && !data && !loading && email) {
      setLoading(true);
      setErr(false);
      const r = await fetchJson<SipProgresso>(`/api/sip/progresso?email=${encodeURIComponent(email)}`);
      if (r.json) setData(r.json);
      else setErr(true);
      setLoading(false);
    }
  }

  const sipUrl = data?.sip_user_id ? `${SIP_BASE}/admin.html?student=${data.sip_user_id}` : `${SIP_BASE}/admin.html`;
  const tarefas = data?.tarefas;

  return (
    <div className={`rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <button type="button" onClick={toggle} className="w-full p-3 flex items-center justify-between text-left">
        <span className="text-sm font-medium text-[var(--fg)]">SIP — Time Holding Brasil</span>
        <span className="flex items-center gap-2">
          <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? <span className="inline-flex items-center gap-1"><Icon name="check" size={12} /> Sim</span> : 'Não'}</span>
          <span className="text-[var(--fg-3)] inline-flex transition-transform" style={{ transform: open ? 'rotate(180deg)' : 'none' }}><Icon name="chevron-down" size={13} /></span>
        </span>
      </button>
      {open && (
        <div className="px-3 pb-3 pt-2 border-t border-[var(--border-faint)] gp-fade-in">
          {loading && <div className="text-xs text-[var(--fg-3)] flex items-center gap-2"><Spinner size={14} /> Carregando progresso…</div>}
          {err && <div className="text-xs text-[var(--red)]">Não foi possível carregar o progresso do SIP.</div>}
          {data && !loading && (data.registrado ? (
            <div className="space-y-1.5">
              <Row k="Status" v={data.approval_status ? (SIP_STATUS[data.approval_status] || data.approval_status) : '—'} />
              <Row k="Ciclo" v={data.ciclo_type ? (SIP_CICLO[data.ciclo_type] || data.ciclo_type) : '—'} />
              {data.taskline_label && <Row k="Trilha" v={data.taskline_label} />}
              {data.palestra && <Row k="Palestra mais próxima" v={`${data.palestra.label} · ${fmtData(data.palestra.data)}`} />}
              {data.nivel && <Row k="Nível no SIP" v={data.nivel} />}
              {data.turma && <Row k="Turma" v={data.turma} />}
              {tarefas?.concluidas != null && (
                <div className="py-1">
                  <div className="flex justify-between text-xs text-[var(--fg-3)] mb-1">
                    <span>Tarefas concluídas</span>
                    <span className="tabular">{tarefas.concluidas}{tarefas.total ? ` / ${tarefas.total}` : ''}</span>
                  </div>
                  {tarefas.total ? <ProgressBar value={(tarefas.concluidas / tarefas.total) * 100} tone="accent" /> : null}
                </div>
              )}
              {data.raiox && <Row k="Raio-X" v={`${data.raiox.score}${data.raiox.max ? '/' + data.raiox.max : ''}`} />}
              <Row k="Onboarding" v={data.onboarding_done ? 'Concluído' : 'Pendente'} />
              <a href={sipUrl} target="_blank" rel="noopener noreferrer" className="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-[var(--accent)] hover:underline">
                Abrir card no SIP <Icon name="arrow-up-right" size={13} />
              </a>
            </div>
          ) : (
            <div className="text-xs text-[var(--fg-3)]">Sem registro no SIP para este e-mail.</div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Placa de Resultado: card + histórico (solicitação + auditoria) ──
/** Funil da placa vindo da ficha (fn_aluno_360_safe). Campo null = linha omitida. */
function PlacaFunil({ a, entrevistaFallback }: { a: Aluno360; entrevistaFallback: { data: string; hora: string | null } | null }) {
  const data = a.placa_entrevista_data || entrevistaFallback?.data || null;
  const hora = a.placa_entrevista_hora || (a.placa_entrevista_data ? null : entrevistaFallback?.hora) || null;
  const lembrete = placaLembreteLabel(a.placa_lembrete_em);
  const ciclo = placaCicloLabel(a.placa_ciclo);
  const nivel = a.placa_nivel_declarado ? nivelLabel(a.placa_nivel_declarado) || a.placa_nivel_declarado : null;
  const parado = placaParadoInfo(a.placa_dias_parado);
  const zoom = data && a.placa_tem_link_zoom != null ? (a.placa_tem_link_zoom ? 'Sala do Zoom criada' : 'Sem sala') : null;
  // Lembrete só faz sentido com entrevista marcada; sem data não afirmamos "ainda não enviado".
  const lembreteTxt = lembrete ? `Lembrete enviado em ${lembrete}` : data ? 'Lembrete ainda não enviado' : null;
  if (!data && !ciclo && !nivel && !parado) return null;

  return (
    <div className="text-xs space-y-0.5 text-[var(--fg-3)] mt-2">
      {data && <div>Entrevista: <span className="text-[var(--fg-2)] tabular">{fmtData(data)}{hora ? ` ${String(hora).slice(0, 5)}` : ''}</span></div>}
      {zoom && <div>{zoom}</div>}
      {lembreteTxt && <div>{lembreteTxt}</div>}
      {ciclo && <div>{ciclo}</div>}
      {nivel && <div>Nível declarado: <span className="text-[var(--fg-2)]">{nivel}</span></div>}
      {parado && (parado.alerta
        ? <div className="font-semibold text-[var(--red)]">{parado.label}</div>
        : <div>{parado.label}</div>)}
    </div>
  );
}

function PlacaJornada({ a, on, hist, loading, rastreioAluno }: { a: Aluno360; on: boolean; hist: PlacaHistorico | null; loading: boolean; rastreioAluno?: string | null }) {
  const sol = hist?.solicitacao;
  const aud = hist?.auditoria;
  const stepIdx = aud?.step_index ?? sol?.auditoria_step ?? sol?.step_index ?? null;
  const stepNome = stepIdx != null && AUDIT_STEPS[stepIdx] ? AUDIT_STEPS[stepIdx].name : null;
  const dates = aud?.dates || {};
  const carimbos = AUDIT_STEPS.map((s) => ({ nome: s.name, quando: dates[s.key] })).filter((c) => c.quando);
  // Rastreio vinculado ao aluno: prefere a solicitação viva, cai para o write-back em thb_alunos.
  const rastreio = sol?.codigo_rastreio || rastreioAluno || null;

  return (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">Placa de Resultado</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? <span className="inline-flex items-center gap-1"><Icon name="check" size={12} /> Sim</span> : 'Não'}</span>
      </div>

      {rastreio && <div className="mt-2"><CopyField label="Código de rastreio" value={rastreio} /></div>}

      <PlacaFunil a={a} entrevistaFallback={sol?.entrevista_data ? { data: sol.entrevista_data, hora: sol.entrevista_hora ?? null } : null} />

      {on && loading && <div className="text-xs text-[var(--fg-3)] mt-2">Carregando histórico…</div>}

      {on && !loading && hist && (
        <div className="mt-2 space-y-2">
          <div className="flex flex-wrap gap-1.5">
            {/* Status único e bem mapeado (mesmo vocabulário da fila de placas): cobre etapa,
                reprovação em correção ("Aluno reprovado · aguardando nova documentação"),
                reenvio e rejeição definitiva — nada de status cru no chip. */}
            {sol && (() => {
              const d = computeDisplayStatus(sol);
              return <Badge tone={displayStatusTone(d.cls)}>{d.label}</Badge>;
            })()}
            {!sol && stepNome && <Badge tone="info">{stepNome}</Badge>}
            {aud?.encerrado && sol?.status !== 'rejeitado' && sol?.status !== 'concluido' && <Badge tone="warning">Encerrado</Badge>}
          </div>
          <div className="text-xs space-y-0.5 text-[var(--fg-3)]">
            {aud?.protocolo && <div>Protocolo: <span className="text-[var(--fg-2)] tabular">{aud.protocolo}</span></div>}
            {(aud?.faturamento || sol?.faturamento_declarado) != null && <div>Faturamento: <span className="text-[var(--fg-2)] tabular">{fmtBRL(aud?.faturamento ?? sol?.faturamento_declarado ?? null)}</span></div>}
            {sol?.motivo_retorno && (
              <div className="text-[var(--red)]">
                {sol.status === 'rejeitado' ? 'Motivo da rejeição' : 'Motivo do retorno'}: {sol.motivo_retorno}
              </div>
            )}
          </div>

          {(sol?.proof_url || sol?.declaracao_url) && (
            <div className="flex flex-wrap gap-1.5">
              {sol?.proof_url && (
                <a href={sol.proof_url} target="_blank" rel="noopener" className="inline-flex items-center gap-1.5 text-xs font-medium text-[var(--accent)] rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-1 hover:border-[var(--border-strong)] transition-colors">
                  <Icon name="file" size={12} /> Comprovante
                </a>
              )}
              {sol?.declaracao_url && (
                <a href={sol.declaracao_url} target="_blank" rel="noopener" className="inline-flex items-center gap-1.5 text-xs font-medium text-[var(--accent)] rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-1 hover:border-[var(--border-strong)] transition-colors">
                  <Icon name="file" size={12} /> Declaração
                </a>
              )}
            </div>
          )}

          {/* Jornada visual do processo (mesma linguagem do acompanhamento público):
              cada etapa com estado real — verde (vencida, com data do carimbo), âmbar (atual),
              amarela (atual em correção), numerada cinza (pendente) e o marco vermelho
              "Reprovado" encerrando a linha quando rejeitado. */}
          {(stepIdx != null || carimbos.length > 0) && (
            <div className="mt-3">
              <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-2">Jornada do processo</div>
              <Timeline
                items={(() => {
                  const concluido = sol?.status === 'concluido';
                  const rejeitado = sol?.status === 'rejeitado';
                  const emCorrecao = Boolean(sol?.regularizacao_pendente);
                  const items: TimelineEntry[] = AUDIT_STEPS.map((s, i) => {
                    const feita = concluido || (stepIdx != null && i < stepIdx) || Boolean(dates[s.key]);
                    const atual = !concluido && !rejeitado && stepIdx === i;
                    return {
                      title: s.name,
                      meta: dates[s.key],
                      tone: feita ? 'green' : atual ? (emCorrecao ? 'yellow' : 'accent') : 'base',
                      done: feita,
                      icon: feita ? undefined : String(i + 1),
                      body: atual
                        ? (emCorrecao ? 'Aluno reprovado — aguardando nova documentação para retomar.' : 'Etapa atual do processo.')
                        : undefined,
                    };
                  });
                  if (rejeitado) {
                    items.push({
                      title: <span className="text-[var(--red)] font-semibold">Reprovado — processo rejeitado</span>,
                      meta: sol?.updated_at ? fmtData(sol.updated_at) : undefined,
                      tone: 'red',
                      done: true,
                      icon: <Icon name="x" size={11} strokeWidth={3} />,
                      body: sol?.motivo_retorno ? `Motivo: ${sol.motivo_retorno}` : undefined,
                    });
                  }
                  return items;
                })()}
              />
            </div>
          )}

          {aud?.obs && <div className="text-xs text-[var(--fg-3)] italic">“{aud.obs}”</div>}
          <a href="/relatorios/placas#solicitacoes" className="inline-block text-xs text-[var(--accent)]">Abrir no Relatório de Placas →</a>
        </div>
      )}

      {on && !loading && hist && !sol && !aud && (
        <div className="text-xs text-[var(--fg-3)] mt-2">Sem registro detalhado de solicitação/auditoria.</div>
      )}
    </div>
  );
}
