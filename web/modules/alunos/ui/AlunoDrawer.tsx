'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  type Aluno360,
  ESPACO_LABEL,
  SITUACAO,
  STATUS_ACESSO,
  SUGESTOES,
  RENOVACAO_LABEL,
  renovacaoStatus,
} from '../domain/aluno-360';
import { nivelLabel, nivelOptions } from '@/shared/domain/nivel-resultado';
import { loadPlacaHistorico, updateAluno, type Turma, type PlacaHistorico } from './alunos-data';
import { AUDIT_STEPS } from '@/modules/placas/domain/auditoria';
import { cursoDesempenhoMock } from '../domain/curso-mock';
import { Badge, NivelBadge, Drawer, AvatarInicial, SectionCard, Button, KpiCard, ProgressBar, Spinner } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { fetchJson } from '@/shared/ui/fetch-json';
import { sitTone, tel } from './alunos-ui-shared';

/** Cabeçalho de seção com ícone de acento (linguagem do card de Placas). */
function SecTitle({ icon, children }: { icon: string; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 text-[var(--fg)]">
      <Icon name={icon} size={15} className="text-[var(--accent)]" /> {children}
    </span>
  );
}

export function AlunoDrawer({ a, turmas, canEdit, editMode, onToggleEdit, onClose, onSaved }: {
  a: Aluno360;
  turmas: Turma[];
  canEdit: boolean;
  editMode: boolean;
  onToggleEdit: () => void;
  onClose: () => void;
  onSaved: (msg: string) => void;
}) {
  const [placaHist, setPlacaHist] = useState<PlacaHistorico | null>(null);
  const [placaLoading, setPlacaLoading] = useState(false);
  const temPlaca = !!(a.tem_placa || a.tem_solicitacao_placa);
  useEffect(() => {
    if (!temPlaca || placaHist !== null) return;
    setPlacaLoading(true); // eslint-disable-line react-hooks/set-state-in-effect
    loadPlacaHistorico(a.id, a.email)
      .then(setPlacaHist)
      .finally(() => setPlacaLoading(false));
  }, [temPlaca, placaHist, a.id, a.email]);
  const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
  const espaco = ESPACO_LABEL[a.espaco_instrucao || ''] || null;

  return (
    <Drawer
      onClose={onClose}
      title={a.nome || 'Sem nome'}
      subtitle={a.email || '—'}
      badges={
        !editMode ? (
          <>
            {sit && <Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge>}
            {a.nivel_resultado && <NivelBadge nivel={a.nivel_resultado} />}
            {(a.cidade || a.estado) && <Badge>{[a.cidade, a.estado].filter(Boolean).join(' · ')}</Badge>}
            {espaco && <Badge tone="info">{espaco}</Badge>}
            {a.eh_socio && <Badge tone="accent">Sócio</Badge>}
          </>
        ) : undefined
      }
      avatar={<AvatarInicial nome={a.nome} />}
      width="max-w-5xl"
      footer={canEdit ? <Button size="sm" variant={editMode ? 'ghost' : 'subtle'} onClick={onToggleEdit}><Icon name="pencil" size={13} /> {editMode ? 'Cancelar edição' : 'Editar dados'}</Button> : undefined}
    >
      {editMode ? (
        <EditForm a={a} turmas={turmas} onSaved={onSaved} />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 items-start">
          {/* Dados Pessoais */}
          <SectionCard title={<SecTitle icon="user">Dados Pessoais</SecTitle>}>
            <Section>
              {a.profissao && <Row k="Profissão" v={a.profissao} />}
              <Row k="E-mail" v={a.email} />
              <Row k="Telefone" v={tel(a.telefone)} />
              {a.telefone_profissional && <Row k="Tel. profissional" v={tel(a.telefone_profissional)} />}
              {a.documento && <Row k={a.tipo_documento || 'CPF/CNPJ'} v={a.documento} />}
              <Row k="Endereço" v={[a.endereco_logradouro, a.endereco_numero, a.bairro, a.cidade, a.estado].filter(Boolean).join(', ') || '—'} />
              <div className="flex gap-2 flex-wrap mt-2">
                {[['Facebook', a.link_facebook], ['Instagram', a.instagram_url], ['YouTube', a.youtube_url], ['Site', a.site_profissional]].filter(([, u]) => u).map(([l, u]) => (
                  <a key={l as string} href={u as string} target="_blank" rel="noopener" className="text-xs px-2 py-1 rounded border border-[var(--border)] text-[var(--accent)]">{l}</a>
                ))}
              </div>
            </Section>
          </SectionCard>

          {/* Renovação */}
          <SectionCard title={<SecTitle icon="refresh">Renovação</SecTitle>}>
            <Section>
              {(() => {
                const rs = renovacaoStatus(a.turma_codigo);
                const info = rs ? RENOVACAO_LABEL[rs] : null;
                return info ? (
                  <div className={`p-2.5 rounded-[var(--r-md)] mb-2 text-xs ${rs === 'em_renovacao' ? 'bg-[var(--yellow-subtle)] text-[var(--yellow)]' : 'bg-[var(--red-subtle)] text-[var(--red)]'}`}>
                    <span className="inline-flex items-center gap-1.5">{rs === 'em_renovacao' ? <Icon name="refresh" size={12} /> : <Icon name="alert" size={12} />} {info.label}</span>
                    <div className="text-[var(--fg-3)] mt-0.5">
                      {rs === 'em_renovacao'
                        ? `Turma ${a.turma_codigo} (T1–T29): segue o processo de renovação.`
                        : `Turma ${a.turma_codigo} (T30+): acesso vencido, sem processo de renovação (em dia, porém não renovado).`}
                    </div>
                  </div>
                ) : <div className="text-xs text-[var(--fg-3)] mb-2">Sem turma THB definida — status de renovação indisponível.</div>;
              })()}
              <Row k="Turma" v={a.turma_codigo || '—'} />
              <Row k="Vencimento" v={fmtData(a.data_expiracao)} />
              <Row k="Data da compra" v={fmtData(a.data_compra_importada)} />
              {a.tempo_acesso && <Row k="Tempo de acesso" v={a.tempo_acesso} />}
              {a.oferta && <Row k="Oferta" v={a.oferta} />}
              {a.tipo_oferta && <Row k="Tipo de oferta" v={a.tipo_oferta} />}
            </Section>
          </SectionCard>

          {/* Acesso ao Curso */}
          <SectionCard className="md:col-span-2" title={<SecTitle icon="graduation">Acesso ao Curso</SecTitle>}>
            <Section>
              {(() => {
                const st = a.status_acesso ? STATUS_ACESSO[a.status_acesso] : null;
                return (
                  <div className="flex flex-wrap gap-1.5 mb-2">
                    {sit && <Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge>}
                    {st && <Badge tone={st.cls === 'green' ? 'success' : st.cls === 'blue' ? 'info' : 'neutral'}>{st.label}</Badge>}
                    {a.status_acesso_central && <Badge tone="neutral">{a.status_acesso_central}</Badge>}
                  </div>
                );
              })()}
              <SubTitle>Produto &amp; oferta</SubTitle>
              <Row k="Produto" v={a.produto} />
              <Row k="Oferta" v={a.oferta} />
              <Row k="Tipo de oferta" v={a.tipo_oferta} />
              <Row k="Origem de acesso" v={a.origem_acesso} />
              <Row k="Instrução" v={a.instrucao} />
              <Row k="Espaço de instrução" v={espaco} />
              <SubTitle>Programa</SubTitle>
              <Row k="Nível de resultado" v={nivelLabel(a.nivel_resultado) || '—'} />
              <Row k="Turma THB" v={a.turma_codigo} />
              <Row k="Turma Aurum" v={a.turma_aurum_codigo} />
              {a.placa_aurum && <Row k="Placa Aurum" v={a.placa_aurum} />}
              <SubTitle>Vigência</SubTitle>
              <Row k="Regra de acesso" v={a.regra_acesso} />
              <Row k="Tempo de acesso" v={a.tempo_acesso} />
              <Row k="Vencimento" v={fmtData(a.data_expiracao)} />
              {(a.mes_expiracao || a.ano_expiracao) && <Row k="Mês/Ano expiração" v={[a.mes_expiracao, a.ano_expiracao].filter(Boolean).join('/')} />}
              <Row k="Data da compra" v={fmtData(a.data_compra_importada)} />
              <SubTitle>Hotmart</SubTitle>
              <Row k="Holding Total (HT)" v={a.tem_ht ? `Sim${a.ativacao_ht_status ? ` · ${a.ativacao_ht_status}` : ''}` : 'Não'} />
              <Row k="Holding Masters (HM)" v={a.tem_hm ? `Sim${a.hm_plano ? ` · ${a.hm_plano}` : ''}` : 'Não'} />
              <Row k="Hotmart UCode" v={a.hotmart_ucode} />
              <Row k="Registrado no SIP" v={a.sip_registrado ? 'Sim' : 'Não'} />
              {(a.cs_estagio || a.cs_responsavel || a.cs_observacoes) && (
                <>
                  <SubTitle>Acompanhamento CS</SubTitle>
                  {a.cs_estagio && <Row k="Estágio" v={a.cs_estagio} />}
                  {a.cs_responsavel && <Row k="Responsável" v={a.cs_responsavel} />}
                  {a.cs_observacoes && <Row k="Obs (CS)" v={a.cs_observacoes} />}
                </>
              )}
              {a.tratamento_manual && <div className="mt-3 p-2 rounded bg-[var(--yellow-subtle)] text-[var(--yellow)] text-xs flex items-center gap-1.5"><Icon name="alert" size={13} /> {a.tratamento_manual}</div>}
              {a.obs_central && <Row k="Obs" v={a.obs_central} />}
            </Section>
          </SectionCard>

          {/* Jornada */}
          <SectionCard className="md:col-span-2" title={<SecTitle icon="check-circle">Jornada</SecTitle>}>
            <div className="grid sm:grid-cols-2 sm:gap-x-4">
              <PlacaJornada on={temPlaca} hist={placaHist} loading={placaLoading} />
              <JornadaCard label="Depoimento" on={!!a.tem_depoimento} extra={a.total_depoimentos ? `${a.total_depoimentos} depoimento(s)` : ''} href={a.tem_depoimento ? '/depoimentos' : undefined} />
              <SipJornada email={a.email} on={!!a.sip_registrado} />
            </div>
            <div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Metadados</div>
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              {a.fonte && <Row k="Fonte" v={a.fonte} />}
              <Row k="Importado em" v={fmtData(a.importado_em)} />
              <Row k="Atualizado em" v={fmtData(a.atualizado_em)} />
              {a.hotmart_ucode && <Row k="Hotmart UCode" v={a.hotmart_ucode} />}
            </div>
          </SectionCard>

          {/* Curso */}
          <SectionCard className="md:col-span-2" title={<SecTitle icon="biblioteca">Curso</SecTitle>}>
            <CursoTab />
          </SectionCard>
        </div>
      )}
    </Drawer>
  );
}

function SubTitle({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mt-3 mb-1 pt-1 border-t border-[var(--border-faint)]">{children}</div>;
}
function Section({ children }: { children: React.ReactNode }) {
  return <div className="space-y-1.5">{children}</div>;
}
function Row({ k, v }: { k: string; v: string | null }) {
  return <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]"><span className="text-xs text-[var(--fg-3)]">{k}</span><span className="text-sm text-[var(--fg)] text-right">{v || '—'}</span></div>;
}
function JornadaCard({ label, on, extra, href }: { label: string; on: boolean; extra?: string; href?: string }) {
  const body = (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">{label}</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? <span className="inline-flex items-center gap-1"><Icon name="check" size={12} /> Sim</span> : 'Não'}</span>
      </div>
      {extra && <div className="text-xs text-[var(--fg-3)] mt-1">{extra}</div>}
    </div>
  );
  return href ? <a href={href}>{body}</a> : body;
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
function PlacaJornada({ on, hist, loading }: { on: boolean; hist: PlacaHistorico | null; loading: boolean }) {
  const sol = hist?.solicitacao;
  const aud = hist?.auditoria;
  const stepIdx = aud?.step_index ?? sol?.auditoria_step ?? sol?.step_index ?? null;
  const stepNome = stepIdx != null && AUDIT_STEPS[stepIdx] ? AUDIT_STEPS[stepIdx].name : null;
  const dates = aud?.dates || {};
  const carimbos = AUDIT_STEPS.map((s) => ({ nome: s.name, quando: dates[s.key] })).filter((c) => c.quando);

  return (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">Placa de Resultado</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? <span className="inline-flex items-center gap-1"><Icon name="check" size={12} /> Sim</span> : 'Não'}</span>
      </div>

      {on && loading && <div className="text-xs text-[var(--fg-3)] mt-2">Carregando histórico…</div>}

      {on && !loading && hist && (
        <div className="mt-2 space-y-2">
          <div className="flex flex-wrap gap-1.5">
            {stepNome && <Badge tone="info">{stepNome}</Badge>}
            {sol?.status && <Badge tone="neutral">{sol.status}</Badge>}
            {aud?.encerrado && <Badge tone="warning">Encerrado</Badge>}
            {sol?.regularizacao_pendente && <Badge tone="danger">Regularização pendente</Badge>}
          </div>
          <div className="text-xs space-y-0.5 text-[var(--fg-3)]">
            {aud?.protocolo && <div>Protocolo: <span className="text-[var(--fg-2)]">{aud.protocolo}</span></div>}
            {sol?.codigo_rastreio && <div>Rastreio: <span className="text-[var(--fg-2)]">{sol.codigo_rastreio}</span></div>}
            {(aud?.faturamento || sol?.faturamento_declarado) != null && <div>Faturamento: <span className="text-[var(--fg-2)]">{fmtBRL(aud?.faturamento ?? sol?.faturamento_declarado ?? null)}</span></div>}
            {sol?.entrevista_data && <div>Entrevista: <span className="text-[var(--fg-2)]">{fmtData(sol.entrevista_data)}{sol.entrevista_hora ? ` ${String(sol.entrevista_hora).slice(0, 5)}` : ''}</span></div>}
            {sol?.motivo_retorno && <div className="text-[var(--red)]">Motivo do retorno: {sol.motivo_retorno}</div>}
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

          {carimbos.length > 0 && (
            <div className="mt-2 border-l border-[var(--border)] pl-3 space-y-1.5">
              {carimbos.map((c) => (
                <div key={c.nome} className="relative text-xs">
                  <span className="absolute -left-[15px] top-1 w-1.5 h-1.5 rounded-full bg-[var(--accent)]" />
                  <span className="text-[var(--fg-2)]">{c.nome}</span>
                  <span className="text-[var(--fg-4)]"> · {c.quando}</span>
                </div>
              ))}
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

// ── Curso: desempenho (DADOS ILUSTRATIVOS / MOCK) ──
function CursoTab() {
  const m = useMemo(() => cursoDesempenhoMock(), []);
  return (
    <Section>
      <div className="p-2 rounded-[var(--r-md)] bg-[var(--surface-3)] text-[10px] text-[var(--fg-3)] mb-2">
        ⓘ Demonstração de layout — ainda sem integração de progresso de curso. Os valores aparecem zerados de propósito.
      </div>
      <div className="grid grid-cols-3 gap-3 mb-3">
        <KpiCard label="Progresso" value={`${m.progressoGeral}%`} />
        <KpiCard label="Módulos" value={`${m.modulosConcluidos}/${m.modulosTotal}`} />
        <KpiCard label="Aulas" value={`${m.aulasAssistidas}/${m.aulasTotal}`} />
      </div>
      <Row k="Engajamento" v="—" />
      <Row k="Último acesso" v="—" />
      <div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Progresso por módulo</div>
      <div className="space-y-2">
        {m.modulos.map((mod) => (
          <div key={mod.nome}>
            <div className="flex justify-between text-xs mb-1">
              <span className="text-[var(--fg-2)]">{mod.nome}</span>
              <span className="text-[var(--fg-3)] tabular">{mod.progresso}%</span>
            </div>
            <ProgressBar value={mod.progresso} height={6} />
          </div>
        ))}
      </div>
    </Section>
  );
}

// ── Formulário de edição — todos os dados do aluno, em seções (porta de saveAlunoEdit) ──
const FIELD_CLS = 'mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]';

// Campos de texto livre persistidos como string (null se vazio).
const TXT_FIELDS = [
  'nome', 'email', 'telefone', 'telefone_profissional', 'tipo_documento', 'profissao',
  'link_facebook', 'instagram_url', 'youtube_url', 'site_profissional',
  'cep', 'endereco_logradouro', 'endereco_numero', 'endereco_complemento', 'bairro', 'cidade', 'pais',
  'nivel_resultado', 'espaco_instrucao', 'placa_aurum', 'hotmart_ucode',
  'produto', 'oferta', 'tipo_oferta', 'origem_acesso', 'instrucao', 'regra_acesso', 'tempo_acesso',
  'status_acesso', 'status_acesso_central', 'situacao_acesso',
  'situacao_financeira', 'status_pagamento',
  'tratamento_manual', 'obs_central',
];

function EditForm({ a, turmas, onSaved }: { a: Aluno360; turmas: Turma[]; onSaved: (m: string) => void }) {
  const init: Record<string, string> = {};
  const raw = a as unknown as Record<string, unknown>;
  for (const k of TXT_FIELDS) init[k] = raw[k] != null ? String(raw[k]) : '';
  init.documento = a.documento && !a.documento.includes('*') ? a.documento : '';
  init.estado = a.estado || '';
  init.turma_id = a.turma_id ? String(a.turma_id) : '';
  init.turma_aurum_id = a.turma_aurum_id ? String(a.turma_aurum_id) : '';
  init.data_expiracao = a.data_expiracao || '';
  init.ultimo_pagamento = a.ultimo_pagamento || '';
  init.mes_expiracao = a.mes_expiracao != null ? String(a.mes_expiracao) : '';
  init.ano_expiracao = a.ano_expiracao != null ? String(a.ano_expiracao) : '';
  init.valor_total = a.valor_total != null ? String(a.valor_total) : '';
  init.valor_pago = a.valor_pago != null ? String(a.valor_pago) : '';
  init.saldo_devedor = a.saldo_devedor != null ? String(a.saldo_devedor) : '';
  init.num_cobrancas = a.num_cobrancas != null ? String(a.num_cobrancas) : '';

  const [f, setF] = useState<Record<string, string>>(init);
  const [busy, setBusy] = useState(false);
  const s = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));
  const thbTurmas = turmas.filter((t) => t.tipo !== 'aurum');
  const aurumTurmas = turmas.filter((t) => t.tipo === 'aurum');

  async function save() {
    setBusy(true);
    const fields: Record<string, unknown> = {};
    const txt = (k: string) => (f[k]?.trim() ? f[k].trim() : null);
    const numv = (k: string) => { const t = f[k]?.trim(); if (!t) return null; const n = Number(t.replace(',', '.')); return Number.isFinite(n) ? n : null; };
    const intv = (k: string) => { const n = numv(k); return n == null ? null : Math.trunc(n); };
    const dt = (k: string) => (f[k]?.trim() ? f[k].trim() : null);

    for (const k of TXT_FIELDS) fields[k] = txt(k);
    fields.estado = f.estado?.trim() ? f.estado.trim().toUpperCase() : null;
    if (f.documento.trim()) fields.documento = f.documento.trim(); // só sobrescreve se preenchido (mascarado fica vazio)
    fields.turma_id = f.turma_id ? Number(f.turma_id) : null;
    fields.turma_aurum_id = f.turma_aurum_id ? Number(f.turma_aurum_id) : null;
    fields.data_expiracao = dt('data_expiracao');
    fields.ultimo_pagamento = dt('ultimo_pagamento');
    fields.mes_expiracao = intv('mes_expiracao');
    fields.ano_expiracao = intv('ano_expiracao');
    fields.valor_total = numv('valor_total');
    fields.valor_pago = numv('valor_pago');
    fields.saldo_devedor = numv('saldo_devedor');
    fields.num_cobrancas = intv('num_cobrancas');

    const r = await updateAluno(a.id, fields);
    setBusy(false);
    onSaved(r.ok ? 'Aluno atualizado!' : 'Erro ao salvar: ' + (r.msg || ''));
  }

  // Funções (não componentes) — evitam recriar tipo de componente a cada render (perda de foco).
  const inp = (k: string, label: string, type = 'text') => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <input type={type} value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS} /></label>
  );
  const inpList = (k: string, label: string, opts: readonly string[]) => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <input list={`dl-${k}`} value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS} />
      <datalist id={`dl-${k}`}>{opts.map((o) => <option key={o} value={o} />)}</datalist></label>
  );
  const sel = (k: string, label: string, opts: { value: string; label: string }[]) => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <select value={f[k]} onChange={(e) => s(k, e.target.value)} className={FIELD_CLS}>
        <option value="">—</option>{opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select></label>
  );
  const espacoOpts = Object.entries(ESPACO_LABEL).map(([value, label]) => ({ value, label }));
  const situacaoOpts = Object.entries(SITUACAO).map(([value, x]) => ({ value, label: x.label }));
  const statusAcessoOpts = Object.entries(STATUS_ACESSO).map(([value, x]) => ({ value, label: x.label }));

  // Edição espelha a MESMA ordem/agrupamento da leitura (Faturamento → Dados → Acesso → Observações).
  const grid = 'grid grid-cols-1 sm:grid-cols-2 gap-2.5';
  return (
    <div className="space-y-4">
      <SectionCard title={<SecTitle icon="user">Dados Pessoais</SecTitle>}>
        <div className={grid}>
          {inp('nome', 'Nome')}
          {inp('email', 'E-mail')}
          {inp('telefone', 'Telefone')}
          {inp('telefone_profissional', 'Tel. profissional')}
          {inp('documento', 'Documento (vazio mantém)')}
          {inp('tipo_documento', 'Tipo de documento')}
          {inp('profissao', 'Profissão')}
        </div>
        <SubTitle>Endereço</SubTitle>
        <div className={grid}>
          {inp('cep', 'CEP')}
          {inp('endereco_logradouro', 'Logradouro')}
          {inp('endereco_numero', 'Número')}
          {inp('endereco_complemento', 'Complemento')}
          {inp('bairro', 'Bairro')}
          {inp('cidade', 'Cidade')}
          {inp('estado', 'Estado (UF)')}
          {inp('pais', 'País')}
        </div>
        <SubTitle>Presença online</SubTitle>
        <div className={grid}>
          {inp('link_facebook', 'Facebook')}
          {inp('instagram_url', 'Instagram')}
          {inp('youtube_url', 'YouTube')}
          {inp('site_profissional', 'Site')}
        </div>
      </SectionCard>

      <SectionCard title={<SecTitle icon="graduation">Acesso ao Curso</SecTitle>}>
        <SubTitle>Produto &amp; oferta</SubTitle>
        <div className={grid}>
          {inpList('produto', 'Produto', SUGESTOES.produto)}
          {inp('oferta', 'Oferta')}
          {inpList('tipo_oferta', 'Tipo de oferta', SUGESTOES.tipo_oferta)}
          {inpList('origem_acesso', 'Origem de acesso', SUGESTOES.origem_acesso)}
          {inpList('instrucao', 'Instrução', SUGESTOES.instrucao)}
          {sel('espaco_instrucao', 'Espaço de instrução', espacoOpts)}
        </div>
        <SubTitle>Programa</SubTitle>
        <div className={grid}>
          {sel('nivel_resultado', 'Nível de resultado', nivelOptions().map((n) => ({ value: n.id, label: n.label })))}
          {inp('placa_aurum', 'Placa Aurum')}
          {sel('turma_id', 'Turma THB', thbTurmas.map((t) => ({ value: String(t.id), label: t.codigo })))}
          {sel('turma_aurum_id', 'Turma Aurum', aurumTurmas.map((t) => ({ value: String(t.id), label: t.codigo })))}
        </div>
        <SubTitle>Vigência</SubTitle>
        <div className={grid}>
          {inpList('regra_acesso', 'Regra de acesso', SUGESTOES.regra_acesso)}
          {inpList('tempo_acesso', 'Tempo de acesso', SUGESTOES.tempo_acesso)}
          {inp('data_expiracao', 'Vencimento', 'date')}
          {inp('mes_expiracao', 'Mês expiração', 'number')}
          {inp('ano_expiracao', 'Ano expiração', 'number')}
        </div>
        <SubTitle>Hotmart &amp; status</SubTitle>
        <div className={grid}>
          {inp('hotmart_ucode', 'Hotmart UCode')}
          {sel('status_acesso', 'Status de acesso', statusAcessoOpts)}
          {inpList('status_acesso_central', 'Status central', SUGESTOES.status_acesso_central)}
          {sel('situacao_acesso', 'Situação de acesso', situacaoOpts)}
        </div>
      </SectionCard>

      <SectionCard title={<SecTitle icon="pencil">Observações</SecTitle>}>
        <div className="space-y-2.5">
          {inp('tratamento_manual', 'Tratamento manual')}
          <label className="block"><span className="text-xs text-[var(--fg-3)]">Obs central</span>
            <textarea value={f.obs_central} onChange={(e) => s('obs_central', e.target.value)} rows={3} className={FIELD_CLS} /></label>
        </div>
      </SectionCard>

      <Button onClick={save} disabled={busy} className="w-full justify-center py-2.5"><Icon name="check" size={15} /> {busy ? 'Salvando…' : 'Salvar alterações'}</Button>
    </div>
  );
}
