'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  type Aluno360,
  ESPACO_LABEL,
  SITUACAO,
  STATUS_ACESSO,
  RENOVACAO_LABEL,
  renovacaoStatus,
} from '../domain/aluno-360';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import { loadPlacaHistorico, type Turma, type PlacaHistorico } from './alunos-data';
import { AUDIT_STEPS } from '@/modules/placas/domain/auditoria';
import { computeDisplayStatus, displayStatusTone } from '@/modules/placas/domain/solicitacao';
import { loadCiclosByAluno, type Ciclo } from '@/modules/placas/ui/admin/placas-admin-data';
import { cursoDesempenhoMock } from '../domain/curso-mock';
import { Badge, NivelBadge, Drawer, AvatarInicial, SectionCard, Button, CopyField, KpiCard, ProgressBar, Spinner, Timeline, type TimelineEntry } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { fetchJson } from '@/shared/ui/fetch-json';
import { AlunoForm } from './AlunoForm';
import { SecTitle, SubTitle, Section, Row } from './alunos-ui-bits';

// Liga a aba "Curso" quando a integração real de desempenho existir (hoje só há mock zerado).
const CURSO_TAB_ATIVA = false as boolean;
import { sitTone, tel } from './alunos-ui-shared';

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
  const [ciclos, setCiclos] = useState<Ciclo[]>([]);
  const temPlaca = !!(a.tem_placa || a.tem_solicitacao_placa);
  useEffect(() => {
    if (!temPlaca || placaHist !== null) return;
    setPlacaLoading(true); // eslint-disable-line react-hooks/set-state-in-effect
    loadPlacaHistorico(a.id, a.email)
      .then(setPlacaHist)
      .finally(() => setPlacaLoading(false));
  }, [temPlaca, placaHist, a.id, a.email]);
  // Histórico de níveis (placa + cadastro) por aluno_id — sobrevive à exclusão da solicitação.
  useEffect(() => {
    if (!a.id) return;
    loadCiclosByAluno(a.id).then(setCiclos).catch(() => {});
  }, [a.id]);
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
        <AlunoForm a={a} turmas={turmas} onSaved={onSaved} />
      ) : (
        <div className="space-y-4">
          {/* HERO — resumo operacional em relance (nível, acesso, turma/vencimento, Hotmart) */}
          <HeroResumo a={a} sit={sit} />

          {/* JORNADA — o que a operação acompanha/age (subiu para o topo) + histórico de níveis */}
          <SectionCard title={<SecTitle icon="check-circle">Jornada</SecTitle>}>
            <div className="grid sm:grid-cols-2 sm:gap-x-4">
              <PlacaJornada on={temPlaca} hist={placaHist} loading={placaLoading} rastreioAluno={a.placa_rastreio} />
              <JornadaCard label="Depoimento" on={!!a.tem_depoimento} extra={a.total_depoimentos ? `${a.total_depoimentos} depoimento(s)` : ''} href={a.tem_depoimento ? '/depoimentos' : undefined} />
              <SipJornada email={a.email} on={!!a.sip_registrado} />
            </div>
            <HistoricoNiveis ciclos={ciclos} />
          </SectionCard>

          {/* Dados Pessoais + Renovação lado a lado */}
          <div className="grid gap-4 md:grid-cols-2 items-start">
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
          </div>

          {/* Acesso ao Curso — essencial visível + detalhe pesado recolhível (corta densidade) */}
          <SectionCard title={<SecTitle icon="graduation">Acesso ao Curso</SecTitle>}>
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
              {a.tratamento_manual && <div className="mb-2 p-2 rounded bg-[var(--yellow-subtle)] text-[var(--yellow)] text-xs flex items-center gap-1.5"><Icon name="alert" size={13} /> {a.tratamento_manual}</div>}
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
              {(a.cs_estagio || a.cs_responsavel || a.cs_observacoes) && (
                <>
                  <SubTitle>Acompanhamento CS</SubTitle>
                  {a.cs_estagio && <Row k="Estágio" v={a.cs_estagio} />}
                  {a.cs_responsavel && <Row k="Responsável" v={a.cs_responsavel} />}
                  {a.cs_observacoes && <Row k="Obs (CS)" v={a.cs_observacoes} />}
                </>
              )}
              {a.obs_central && (
                <>
                  <SubTitle>Observações</SubTitle>
                  <Row k="Obs central" v={a.obs_central} />
                </>
              )}
              <Collapse title="Hotmart & integrações">
                <Row k="Holding Total (HT)" v={a.tem_ht ? `Sim${a.ativacao_ht_status ? ` · ${a.ativacao_ht_status}` : ''}` : 'Não'} />
                <Row k="Holding Masters (HM)" v={a.tem_hm ? `Sim${a.hm_plano ? ` · ${a.hm_plano}` : ''}` : 'Não'} />
                <Row k="Hotmart UCode" v={a.hotmart_ucode} />
                <Row k="Registrado no SIP" v={a.sip_registrado ? 'Sim' : 'Não'} />
              </Collapse>
            </Section>
          </SectionCard>

          {/* Metadados — bloco discreto no fim */}
          <SectionCard title={<SecTitle icon="notebook">Metadados</SecTitle>}>
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              {a.fonte && <Row k="Fonte" v={a.fonte} />}
              <Row k="Importado em" v={fmtData(a.importado_em)} />
              <Row k="Atualizado em" v={fmtData(a.atualizado_em)} />
              {a.hotmart_ucode && <Row k="Hotmart UCode" v={a.hotmart_ucode} />}
            </div>
          </SectionCard>

          {/* Curso: oculto até existir integração real — cursoDesempenhoMock é 100% zerado
              e exibir métricas falsas confunde a operação. Reativar via CURSO_TAB_ATIVA. */}
          {CURSO_TAB_ATIVA && (
            <SectionCard title={<SecTitle icon="biblioteca">Curso</SecTitle>}>
              <CursoTab />
            </SectionCard>
          )}
        </div>
      )}
    </Drawer>
  );
}

/** Célula compacta do hero (rótulo minúsculo + valor destacado). */
function MiniStat({ label, tone, children }: { label: string; tone?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 min-w-0" style={tone ? { borderLeft: `3px solid ${tone}` } : undefined}>
      <div className="text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}</div>
      <div className="text-sm font-semibold text-[var(--fg)] mt-1 truncate">{children}</div>
    </div>
  );
}

/** Tira de resumo operacional no topo da ficha (relance: nível, acesso, turma/venc., Hotmart). */
function HeroResumo({ a, sit }: { a: Aluno360; sit: { label: string; cls: string } | null }) {
  const st = a.status_acesso ? STATUS_ACESSO[a.status_acesso] : null;
  const rs = renovacaoStatus(a.turma_codigo);
  const vencTone = rs ? (rs === 'em_renovacao' ? 'var(--yellow)' : 'var(--red)') : undefined;
  const hotmart = [
    a.tem_ht ? `HT${a.ativacao_ht_status ? ` · ${a.ativacao_ht_status}` : ''}` : null,
    a.tem_hm ? `HM${a.hm_plano ? ` · ${a.hm_plano}` : ''}` : null,
  ].filter(Boolean).join('  •  ');
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
      <MiniStat label="Nível de resultado" tone="var(--accent)">
        {a.nivel_resultado ? <NivelBadge nivel={a.nivel_resultado} /> : '—'}
      </MiniStat>
      <MiniStat label="Acesso">{st?.label || sit?.label || '—'}</MiniStat>
      <MiniStat label="Turma · Vencimento" tone={vencTone}>
        {(a.turma_codigo || '—') + (a.data_expiracao ? ` · ${fmtData(a.data_expiracao)}` : '')}
      </MiniStat>
      <MiniStat label="Hotmart">{hotmart || '—'}</MiniStat>
    </div>
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
              {c.concluido_em && <span className="text-[11px] text-[var(--fg-3)] shrink-0">{fmtData(c.concluido_em)}</span>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** Seção recolhível para detalhe secundário (corta densidade sem esconder dados). */
function Collapse({ title, children }: { title: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mt-2 border-t border-[var(--border-faint)] pt-2">
      <button type="button" onClick={() => setOpen((o) => !o)} className="w-full flex items-center justify-between text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] hover:text-[var(--fg-2)] transition-colors">
        <span>{title}</span>
        <span className="inline-flex transition-transform" style={{ transform: open ? 'rotate(180deg)' : 'none' }}><Icon name="chevron-down" size={13} /></span>
      </button>
      {open && <div className="mt-2 space-y-1.5 gp-fade-in">{children}</div>}
    </div>
  );
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
function PlacaJornada({ on, hist, loading, rastreioAluno }: { on: boolean; hist: PlacaHistorico | null; loading: boolean; rastreioAluno?: string | null }) {
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
            {aud?.protocolo && <div>Protocolo: <span className="text-[var(--fg-2)]">{aud.protocolo}</span></div>}
            {(aud?.faturamento || sol?.faturamento_declarado) != null && <div>Faturamento: <span className="text-[var(--fg-2)]">{fmtBRL(aud?.faturamento ?? sol?.faturamento_declarado ?? null)}</span></div>}
            {sol?.entrevista_data && <div>Entrevista: <span className="text-[var(--fg-2)]">{fmtData(sol.entrevista_data)}{sol.entrevista_hora ? ` ${String(sol.entrevista_hora).slice(0, 5)}` : ''}</span></div>}
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
