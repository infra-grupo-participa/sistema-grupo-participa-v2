'use client';

import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { AUDIT_STEP_TOTAL, AUDIT_STEP_INDEX, type AuditStep } from '../../domain/auditoria';
import { computeDisplayStatus, isSolicitacaoRegularizacao } from '../../domain/solicitacao';
import type { Solicitacao, Auditoria } from '../../domain/types';
import * as data from './placas-admin-data';
import { NIVEL_FAIXA_ORDER, DEFAULT_NIVEL_FAIXAS } from '../../domain/config';
import { Badge, NivelBadge, Drawer, AvatarInicial, Button, CopyField, Input, FilterSelect, ConfirmDialog, Modal } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { fmtBRL, fmtDataExtenso, type Act } from './relatorio-shared';

export function SolicitacaoDrawer({
  sol,
  auditoria,
  canEdit,
  steps,
  onClose,
  act,
}: {
  sol: Solicitacao;
  auditoria?: Auditoria;
  canEdit: boolean;
  steps: AuditStep[];
  onClose: () => void;
  act: Act;
}) {
  const [rastreio, setRastreio] = useState(sol.codigo_rastreio || '');
  const [motivo, setMotivo] = useState('');
  const [showCorrecao, setShowCorrecao] = useState(false);
  const [confirmExcluir, setConfirmExcluir] = useState(false);
  const [confirmRejeitar, setConfirmRejeitar] = useState(false);
  const [motivoRejeicao, setMotivoRejeicao] = useState('');
  const [editando, setEditando] = useState(false);
  const [reprovacoes, setReprovacoes] = useState<data.Reprovacao[]>([]);
  const [histOpen, setHistOpen] = useState(false);
  const step = sol.auditoria_step ?? -1;

  // Histórico de reprovações do aluno (append-only em thb_placas_reprovacoes).
  const carregarReprovacoes = useCallback(() => {
    data.loadReprovacoes(sol.id).then(setReprovacoes).catch(() => {});
  }, [sol.id]);
  useEffect(() => { carregarReprovacoes(); }, [carregarReprovacoes]);
  const dates = (auditoria?.dates as Record<string, string>) || {};
  const regular = isSolicitacaoRegularizacao(sol);
  const reenvioCompleto = regular && Boolean(sol.proof_url) && Boolean(sol.declaracao_url);

  return (
    <Drawer
      width="max-w-5xl"
      onClose={onClose}
      avatar={<AvatarInicial nome={sol.nome} />}
      title={sol.nome || '—'}
      subtitle={`${sol.email ?? ''}${sol.telefone ? ' · ' + sol.telefone : ''}`}
      badges={
        <>
          <NivelBadge nivel={sol.nivel} />
          <Badge tone="accent" dot>{step >= 0 && !regular ? `${step + 1}/${AUDIT_STEP_TOTAL} · ` : ''}{computeDisplayStatus(sol).label}</Badge>
          {sol.admin_seen_at && <Badge tone="neutral">Visto</Badge>}
        </>
      }
      actions={canEdit ? (
        <div className="hidden sm:flex gap-1.5">
          <Button size="sm" variant={editando ? 'primary' : 'subtle'} onClick={() => setEditando((v) => !v)}><Icon name="pencil" size={13} /> {editando ? 'Fechar edição' : 'Editar dados'}</Button>
          <Button size="sm" variant="subtle" onClick={() => act(() => data.marcarVisto(sol, true))}>Marcar visto</Button>
          <Button size="sm" variant="ghost" onClick={() => act(() => data.marcarVisto(sol, false))}>Não visto</Button>
        </div>
      ) : undefined}
      footer={canEdit ? (
        <>
          {step > 0 && step < AUDIT_STEP_TOTAL - 1 && <Button size="sm" variant="ghost" onClick={() => act(() => data.voltarEtapa(sol))}><Icon name="arrow-left" size={13} /> Etapa anterior</Button>}
          {step >= 0 && step < AUDIT_STEP_TOTAL - 1 && <Button size="sm" variant="success" onClick={() => act(() => data.confirmarJaPossuiPlaca(sol))}><Icon name="check" size={13} /> Já possui placa — avançar para o final</Button>}
          <Button size="sm" variant="ghost" onClick={() => setShowCorrecao((v) => !v)}><Icon name="rotate" size={13} /> Correção</Button>
          <div className="ml-auto flex gap-1.5">
            {sol.status !== 'rejeitado' && sol.status !== 'concluido' && (
              <Button size="sm" variant="ghost" onClick={() => setConfirmRejeitar(true)}><Icon name="x" size={13} /> Rejeitar</Button>
            )}
            <Button size="sm" variant="danger" onClick={() => setConfirmExcluir(true)}><Icon name="trash" size={13} /> Excluir</Button>
          </div>
        </>
      ) : undefined}
    >
      <div className="grid gap-4 lg:grid-cols-[1fr_300px] items-start">
        {/* Coluna principal */}
        <div className="space-y-4 min-w-0">
          {canEdit && editando && (
            <EditarDados sol={sol} act={act} onDone={() => setEditando(false)} />
          )}

          {sol.regularizacao_pendente && sol.motivo_retorno ? (
            <Panel icon="alert" title="Motivo do retorno" accent="var(--yellow)">
              <p className="text-sm text-[var(--fg-2)] leading-relaxed whitespace-pre-wrap">{sol.motivo_retorno}</p>
              {reprovacoes.length > 0 && (
                <button onClick={() => setHistOpen(true)} className="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-[var(--accent)] hover:underline">
                  <Icon name="rotate" size={13} /> Ver histórico de reprovações ({reprovacoes.length})
                </button>
              )}
            </Panel>
          ) : reprovacoes.length > 0 ? (
            <Panel icon="rotate" title="Histórico de reprovações">
              <div className="flex items-center justify-between gap-3 flex-wrap">
                <span className="text-sm text-[var(--fg-2)]">Este aluno já teve <strong className="text-[var(--fg)]">{reprovacoes.length}</strong> reprovação(ões) neste processo.</span>
                <Button size="sm" variant="subtle" onClick={() => setHistOpen(true)}><Icon name="rotate" size={13} /> Ver histórico</Button>
              </div>
            </Panel>
          ) : null}

          {sol.codigo_rastreio && <CopyField label="Código de rastreio" value={sol.codigo_rastreio} />}

          <Panel icon="arrow-right" title="Próxima ação">
            {!canEdit ? (
              <p className="text-sm text-[var(--fg-3)]">Somente leitura.</p>
            ) : regular && !reenvioCompleto ? (
              <div className="rounded-[var(--r-md)] bg-[var(--yellow-subtle)] p-3 text-sm flex items-start gap-2">
                <Icon name="alert" size={16} className="text-[var(--yellow)] mt-0.5 shrink-0" />
                <div><div className="font-semibold text-[var(--yellow)]">Cliente em correção</div><div className="text-[var(--fg-2)] mt-0.5">Aguardando novo envio de documentação ou correção do questionário pelo cliente. Quando ele reenviar, o processo volta para a fila ativa.</div></div>
              </div>
            ) : regular && reenvioCompleto ? (
              <>
                <div className="rounded-[var(--r-md)] bg-[var(--green-subtle)] p-3 text-sm mb-3 flex items-start gap-2">
                  <Icon name="check-circle" size={16} className="text-[var(--green)] mt-0.5 shrink-0" />
                  <div><div className="font-semibold text-[var(--green)]">Reenvio recebido</div><div className="text-[var(--fg-2)] mt-0.5">A cliente reenviou os documentos da correção. Se estiverem corretos, aprove para enviar o link de agendamento.</div></div>
                </div>
                <BigAction variant="success" icon="check" onClick={() => act(() => data.aprovarReenvio(sol))}>Aprovar reenvio</BigAction>
              </>
            ) : step < 0 || sol.status === 'enviado' ? (
              <BigAction icon="play" onClick={() => act(() => data.bootstrapAuditoria(sol).then(() => true))}>Iniciar auditoria</BigAction>
            ) : step === AUDIT_STEP_INDEX.DOCS_APROVADOS ? (
              <p className="text-sm text-[var(--fg-2)]">Aguardando o cliente agendar a entrevista.</p>
            ) : step >= AUDIT_STEP_INDEX.PLACA_RECEBIDA ? (
              <div className="rounded-[var(--r-md)] bg-[var(--green-subtle)] text-[var(--green)] p-3 text-sm inline-flex items-center gap-2"><Icon name="check-circle" size={16} /> Processo concluído — placa recebida.</div>
            ) : (
              <>
                <p className="text-sm text-[var(--fg-2)] mb-3 leading-relaxed">{steps[step]?.desc}</p>
                {step === AUDIT_STEP_INDEX.PLACA_EM_CONFECCAO && (
                  <div className="flex gap-2 mb-2">
                    <Input value={rastreio} onChange={(e) => setRastreio(e.target.value)} placeholder="Código de rastreio" className="flex-1" />
                    <Button variant="subtle" onClick={() => act(() => data.salvarRastreio(sol, rastreio))}>Salvar</Button>
                  </div>
                )}
                <BigAction icon="check" onClick={() => act(() => data.avancarEtapa(sol))}>{steps[step]?.actionLabel || 'Avançar etapa'}</BigAction>
                {step === AUDIT_STEP_INDEX.ENTREVISTA_AGENDADA && (
                  <button onClick={() => act(() => data.marcarNaoCompareceu(sol))} className="w-full mt-2 inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-2 text-sm font-medium text-[var(--red)] border border-[var(--red-border)] hover:bg-[var(--red-subtle)] transition-colors"><Icon name="x" size={14} /> Não compareceu — reabrir agendamento</button>
                )}
              </>
            )}
            {showCorrecao && canEdit && (
              <div className="mt-3 space-y-2 pt-3 border-t border-[var(--border)]">
                <p className="text-xs text-[var(--fg-3)]">A reprovação registra o motivo no histórico, limpa os documentos enviados e devolve o processo para o cliente reenviar. O cliente é notificado por e-mail.</p>
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Descreva o que precisa ser corrigido…" rows={3} className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
                <Button variant="subtle" disabled={!motivo.trim()} onClick={() => act(() => data.solicitarCorrecao(sol, motivo).then((r) => { if (r.ok) { setShowCorrecao(false); setMotivo(''); carregarReprovacoes(); } return r; }))}>Reprovar e solicitar correção</Button>
              </div>
            )}
          </Panel>

          {sol.entrevista_data && (
            <Panel icon="calendar" title="Entrevista agendada">
              <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-4 text-center mb-3">
                <div className="text-lg font-bold text-[var(--fg)] capitalize">{fmtDataExtenso(sol.entrevista_data)}</div>
                {sol.entrevista_hora && <div className="text-sm text-[var(--info)] mt-1 inline-flex items-center gap-1.5"><Icon name="calendar" size={14} /> Às {String(sol.entrevista_hora).slice(0, 5)}</div>}
              </div>
              {(sol.meet_link || sol.entrevista_link) && (
                <a href={sol.meet_link || sol.entrevista_link!} target="_blank" rel="noopener" className="w-full inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 transition-[filter]" style={{ background: 'var(--info)' }}><Icon name="camera" size={15} /> Abrir sala da entrevista</a>
              )}
            </Panel>
          )}

          <Panel icon="coins" title="Faturamento & Comprovação" accent="var(--accent)">
            <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-4 mb-3">
              <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Faturamento declarado</div>
              <div className="text-2xl font-bold tabular text-[var(--fg)] mt-1">{fmtBRL(sol.faturamento_declarado)}</div>
            </div>
            <div className="grid sm:grid-cols-2 gap-2 mb-3">
              <DocLink url={sol.proof_url} label="Comprovante financeiro" />
              <DocLink url={sol.declaracao_url} label="Declaração assinada" />
            </div>
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              <Row2 k="Nível atual" v={<NivelBadge nivel={sol.nivel} />} />
              <Row2 k="Espaço de instrução" v={sol.espaco_instrucao} />
              <Row2 k="Interesse" v={sol.interesse} />
            </div>
          </Panel>

          {!editando && (
          <Panel icon="user" title="Dados Pessoais">
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              <Row2 k="Nome" v={sol.nome} />
              <Row2 k="E-mail" v={sol.email} />
              <Row2 k="Telefone" v={sol.telefone} />
              <Row2 k="Profissão" v={sol.profissao} />
              <Row2 k="Endereço" v={[sol.logradouro, sol.numero, sol.bairro, sol.cidade, sol.estado_uf].filter(Boolean).join(', ') || null} />
              <Row2 k="CEP" v={sol.cep} />
              <Row2 k="Documento (NF)" v={sol.documento_nf} />
              <Row2 k="E-mail de entrega" v={sol.email_entrega} />
              {sol.codigo_rastreio && <Row2 k="Código de rastreio" v={sol.codigo_rastreio} />}
            </div>
          </Panel>
          )}
        </div>

        {/* Coluna lateral: status + remanejamento */}
        <div className="space-y-4">
          <Panel icon="check-circle" title="Status da auditoria">
            <ol className="space-y-1">
              {steps.map((s, i) => {
                const done = i < step;
                const current = i === step;
                return (
                  <li key={s.key} className={`flex items-center gap-2.5 rounded-[var(--r-md)] px-2 py-1.5 ${current ? 'bg-[var(--accent-subtle)] border border-[var(--accent-border)]' : ''}`}>
                    <span className="grid place-items-center w-6 h-6 rounded-full text-[11px] font-bold shrink-0" style={{ background: done ? 'var(--green)' : current ? 'var(--accent)' : 'var(--surface-4)', color: done || current ? '#fff' /* hex-ok: contraste */ : 'var(--fg-3)' }}>{done ? <Icon name="check" size={12} strokeWidth={3} /> : i + 1}</span>
                    <span className={`text-sm ${current ? 'font-semibold text-[var(--fg)]' : done ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>{s.name}</span>
                    {dates[s.key] && <span className="ml-auto text-[10px] tabular text-[var(--fg-3)] shrink-0">{dates[s.key]}</span>}
                  </li>
                );
              })}
            </ol>
          </Panel>

          {canEdit && step >= 0 && (
            <Panel title="Remanejamento rápido">
              <div className="flex flex-wrap gap-1.5">
                {steps.map((s, i) => {
                  const done = i < step;
                  const current = i === step;
                  return (
                    <button key={s.key} title={s.name} onClick={() => act(() => data.setAuditStep(sol, i))} className="grid place-items-center w-8 h-8 rounded-full text-xs font-bold border border-[var(--border)] transition-[filter] hover:brightness-125" style={{ background: done ? 'var(--green)' : current ? 'var(--accent)' : 'var(--surface-3)', color: done || current ? '#fff' /* hex-ok: contraste */ : 'var(--fg-2)' }}>{i + 1}</button>
                  );
                })}
              </div>
              <p className="text-[11px] text-[var(--fg-3)] mt-2">Clique para posicionar a auditoria na etapa (não dispara e-mails).</p>
            </Panel>
          )}
        </div>
      </div>

      {confirmExcluir && (
        <ConfirmDialog
          title="Excluir solicitação"
          message="Excluir esta solicitação e a auditoria vinculada? Ação irreversível."
          confirmLabel="Excluir"
          danger
          onConfirm={() => { setConfirmExcluir(false); act(() => data.excluirSolicitacao(sol)); }}
          onCancel={() => setConfirmExcluir(false)}
        />
      )}

      {confirmRejeitar && (
        <Modal
          title="Rejeitar solicitação"
          width="max-w-md"
          onClose={() => setConfirmRejeitar(false)}
          footer={
            <>
              <Button variant="ghost" size="sm" onClick={() => setConfirmRejeitar(false)}>Cancelar</Button>
              <Button variant="danger" size="sm" onClick={() => { setConfirmRejeitar(false); act(() => data.rejeitar(sol, motivoRejeicao)); setMotivoRejeicao(''); }}>Rejeitar e notificar</Button>
            </>
          }
        >
          <p className="text-sm text-[var(--fg-2)] leading-relaxed mb-3">
            Diferente da exclusão, a rejeição <strong>mantém o registro</strong> e notifica o cliente por e-mail.
            Se precisar reverter depois, use o Remanejamento rápido.
          </p>
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Motivo (vai no e-mail — opcional)</span>
            <textarea value={motivoRejeicao} onChange={(e) => setMotivoRejeicao(e.target.value)} rows={3} placeholder="Ex.: não atende aos critérios de comprovação do nível…" className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
          </label>
        </Modal>
      )}

      {histOpen && (
        <Modal open onClose={() => setHistOpen(false)} title={`Histórico de reprovações (${reprovacoes.length})`} width="max-w-2xl">
          {reprovacoes.length === 0 ? (
            <p className="text-sm text-[var(--fg-3)]">Nenhuma reprovação registrada.</p>
          ) : (
            <div className="space-y-3">
              {reprovacoes.map((r, i) => (
                <div key={r.id} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3">
                  <div className="flex items-center justify-between gap-2 flex-wrap mb-1.5">
                    <span className="text-xs font-semibold text-[var(--fg-2)] inline-flex items-center gap-2">
                      <span className="grid place-items-center w-5 h-5 rounded-full bg-[var(--yellow-subtle)] text-[var(--yellow)] text-[10px] font-bold">{reprovacoes.length - i}</span>
                      {fmtDataHora(r.created_at)}
                    </span>
                    {r.reprovado_por_email && <span className="text-[11px] text-[var(--fg-3)]">por {r.reprovado_por_email}</span>}
                  </div>
                  <p className="text-sm text-[var(--fg)] whitespace-pre-wrap leading-relaxed">{r.motivo}</p>
                  <div className="flex flex-wrap gap-2 mt-2 text-[11px]">
                    {r.nivel && <span className="rounded-[var(--r-sm)] bg-[var(--surface-4)] px-2 py-0.5 text-[var(--fg-2)]">Nível: {DEFAULT_NIVEL_FAIXAS[r.nivel]?.nm || r.nivel}</span>}
                    {r.faturamento_declarado != null && <span className="rounded-[var(--r-sm)] bg-[var(--surface-4)] px-2 py-0.5 text-[var(--fg-2)] tabular">{fmtBRL(r.faturamento_declarado)}</span>}
                    {r.proof_url && <a href={r.proof_url} target="_blank" rel="noopener" className="rounded-[var(--r-sm)] bg-[var(--surface-4)] px-2 py-0.5 text-[var(--accent)] inline-flex items-center gap-1"><Icon name="file" size={11} /> Comprovante</a>}
                    {r.declaracao_url && <a href={r.declaracao_url} target="_blank" rel="noopener" className="rounded-[var(--r-sm)] bg-[var(--surface-4)] px-2 py-0.5 text-[var(--accent)] inline-flex items-center gap-1"><Icon name="file" size={11} /> Declaração</a>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Modal>
      )}
    </Drawer>
  );
}

// ── Edição inline dos dados do aluno (drawer) ──────────────────────────────
const NIVEL_OPCOES = NIVEL_FAIXA_ORDER.map((v) => ({ v, l: DEFAULT_NIVEL_FAIXAS[v].nm }));

function CampoEdit({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return (
    <label className={`block ${full ? 'sm:col-span-2' : ''}`}>
      <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}</span>
      <div className="mt-1">{children}</div>
    </label>
  );
}

function EditarDados({
  sol,
  act,
  onDone,
}: {
  sol: Solicitacao;
  act: Act;
  onDone: () => void;
}) {
  const [f, setF] = useState<Record<string, string>>({
    nome: sol.nome ?? '',
    email: sol.email ?? '',
    telefone: sol.telefone ?? '',
    turma: sol.turma ?? '',
    profissao: sol.profissao ?? '',
    nivel: sol.nivel ?? '',
    interesse: sol.interesse ?? '',
    espaco_instrucao: sol.espaco_instrucao ?? '',
    faturamento_declarado: sol.faturamento_declarado != null ? String(sol.faturamento_declarado) : '',
    documento_nf: sol.documento_nf ?? '',
    email_entrega: sol.email_entrega ?? '',
    cep: sol.cep ?? '',
    logradouro: sol.logradouro ?? '',
    numero: sol.numero ?? '',
    complemento: sol.complemento ?? '',
    bairro: sol.bairro ?? '',
    cidade: sol.cidade ?? '',
    estado_uf: sol.estado_uf ?? '',
  });
  const set = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));

  async function salvar() {
    const fatDigits = f.faturamento_declarado.replace(/\D/g, '');
    const campos: data.DadosEditaveis = {
      nome: f.nome,
      email: f.email,
      telefone: f.telefone,
      turma: f.turma,
      profissao: f.profissao,
      nivel: f.nivel,
      interesse: f.interesse,
      espaco_instrucao: f.espaco_instrucao,
      faturamento_declarado: fatDigits ? Number(fatDigits) : null,
      documento_nf: f.documento_nf,
      email_entrega: f.email_entrega,
      cep: f.cep,
      logradouro: f.logradouro,
      numero: f.numero,
      complemento: f.complemento,
      bairro: f.bairro,
      cidade: f.cidade,
      estado_uf: f.estado_uf,
    };
    await act(() => data.atualizarDadosSolicitacao(sol, campos));
    onDone();
  }

  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--accent-border)] bg-[var(--surface-2)] p-4" style={{ borderLeft: '3px solid var(--accent)' }}>
      <div className="flex items-center gap-2 mb-3 text-[11px] font-bold uppercase tracking-wider text-[var(--accent)]">
        <Icon name="pencil" size={14} /> Editando dados do aluno
      </div>
      <div className="grid sm:grid-cols-2 gap-3">
        <CampoEdit label="Nome"><Input value={f.nome} onChange={(e) => set('nome', e.target.value)} /></CampoEdit>
        <CampoEdit label="E-mail"><Input value={f.email} onChange={(e) => set('email', e.target.value)} /></CampoEdit>
        <CampoEdit label="Telefone"><Input value={f.telefone} onChange={(e) => set('telefone', e.target.value)} /></CampoEdit>
        <CampoEdit label="Profissão"><Input value={f.profissao} onChange={(e) => set('profissao', e.target.value)} /></CampoEdit>
        <CampoEdit label="Turma"><Input value={f.turma} onChange={(e) => set('turma', e.target.value)} placeholder="T1, A2…" /></CampoEdit>
        <CampoEdit label="Nível">
          <FilterSelect value={f.nivel} onChange={(e) => set('nivel', e.target.value)}>
            <option value="">— sem nível —</option>
            {NIVEL_OPCOES.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
          </FilterSelect>
        </CampoEdit>
        <CampoEdit label="Espaço de instrução"><Input value={f.espaco_instrucao} onChange={(e) => set('espaco_instrucao', e.target.value)} /></CampoEdit>
        <CampoEdit label="Interesse"><Input value={f.interesse} onChange={(e) => set('interesse', e.target.value)} /></CampoEdit>
        <CampoEdit label="Faturamento declarado (R$)"><Input value={f.faturamento_declarado} onChange={(e) => set('faturamento_declarado', e.target.value)} inputMode="numeric" placeholder="0" /></CampoEdit>
        <CampoEdit label="Documento (NF)"><Input value={f.documento_nf} onChange={(e) => set('documento_nf', e.target.value)} /></CampoEdit>
        <CampoEdit label="E-mail de entrega"><Input value={f.email_entrega} onChange={(e) => set('email_entrega', e.target.value)} /></CampoEdit>
        <CampoEdit label="CEP"><Input value={f.cep} onChange={(e) => set('cep', e.target.value)} /></CampoEdit>
        <CampoEdit label="Logradouro" full><Input value={f.logradouro} onChange={(e) => set('logradouro', e.target.value)} /></CampoEdit>
        <CampoEdit label="Número"><Input value={f.numero} onChange={(e) => set('numero', e.target.value)} /></CampoEdit>
        <CampoEdit label="Complemento"><Input value={f.complemento} onChange={(e) => set('complemento', e.target.value)} /></CampoEdit>
        <CampoEdit label="Bairro"><Input value={f.bairro} onChange={(e) => set('bairro', e.target.value)} /></CampoEdit>
        <CampoEdit label="Cidade"><Input value={f.cidade} onChange={(e) => set('cidade', e.target.value)} /></CampoEdit>
        <CampoEdit label="UF"><Input value={f.estado_uf} onChange={(e) => set('estado_uf', e.target.value.toUpperCase().slice(0, 2))} maxLength={2} /></CampoEdit>
      </div>
      <div className="flex gap-2 mt-4">
        <Button variant="primary" onClick={salvar}><Icon name="check" size={14} /> Salvar alterações</Button>
        <Button variant="ghost" onClick={onDone}>Cancelar</Button>
      </div>
    </div>
  );
}

/** Bloco de seção com cabeçalho de ícone (linguagem do card legado). */
function Panel({ icon, title, accent, children }: { icon?: string; title: string; accent?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4" style={accent ? { borderLeft: `3px solid ${accent}` } : undefined}>
      <div className="flex items-center gap-2 mb-3 text-[11px] font-bold uppercase tracking-wider text-[var(--fg-3)]">
        {icon && <Icon name={icon} size={14} className="text-[var(--accent)]" />} {title}
      </div>
      {children}
    </div>
  );
}

/** Botão de ação primária, grande e destacado (Próxima Ação). */
function BigAction({ children, onClick, variant = 'accent', icon }: { children: React.ReactNode; onClick: () => void; variant?: 'accent' | 'success'; icon?: string }) {
  return (
    <button onClick={onClick} className="w-full inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-3 text-sm font-bold text-black hover:brightness-110 transition-[filter]" style={{ background: variant === 'success' ? 'var(--green)' : 'var(--accent)' }}>
      {icon && <Icon name={icon} size={16} />}{children}
    </button>
  );
}

/** Cartão de documento (comprovante/declaração). */
function DocLink({ url, label }: { url: string | null; label: string }) {
  if (!url) {
    return <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border)] p-3 text-xs text-[var(--fg-4)]">{label}: —</div>;
  }
  return (
    <a href={url} target="_blank" rel="noopener" className="block rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 hover:border-[var(--border-strong)] transition-colors">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--green)] flex items-center gap-1.5"><Icon name="file" size={13} /> {label}</div>
      <div className="text-sm text-[var(--fg)] mt-1 inline-flex items-center gap-1.5"><Icon name="arrow-up-right" size={13} /> Abrir arquivo</div>
    </a>
  );
}

/** Linha rótulo-em-cima / valor (leitura densa nas seções). */
function Row2({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="py-1.5 border-b border-[var(--border-faint)]">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{k}</div>
      <div className="text-sm text-[var(--fg)] mt-0.5">{v || '—'}</div>
    </div>
  );
}
