'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  type HmFilaItem,
  type HmBucket,
  type TurmaThb,
  HM_BUCKETS,
  HM_CATEGORIA_LABEL,
  etapasDoItem,
  turmaPendente,
} from '../domain/acesso-hm';
import {
  loadHmFila,
  loadTurmasThb,
  setTurmaHm,
  marcarEtapa,
  ignorarHm,
  quitarManual,
  setTurmaAtual,
  criarTurma,
} from './acesso-hm-data';
import { Card, EmptyState, SectionTitle, Badge, Button, SkeletonRows, ConfirmDialog, Modal, Toast, useFlash, Input, DataTable, Thead, Th } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import { tel } from './alunos-ui-shared';

function CategoriaBadge({ categoria }: { categoria: string | null }) {
  if (!categoria) return <Badge tone="danger" dot>Sem categoria</Badge>;
  const m = HM_CATEGORIA_LABEL[categoria];
  return <Badge tone={m?.tone ?? 'neutral'} dot>{m?.label ?? categoria}</Badge>;
}

/** Botão-checkbox de etapa (Ativado / Acesso liberado). */
function StepCheck({ done, label, quem, quando, disabled, onToggle }: {
  done: boolean; label: string; quem?: string | null; quando?: string | null; disabled?: boolean; onToggle: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onToggle}
      title={done && quando ? `${quem ? quem + ' · ' : ''}${fmtDataHora(quando)}` : undefined}
      className={`inline-flex items-center gap-1.5 rounded-[var(--r-md)] border px-2.5 py-1.5 text-xs font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
        done
          ? 'border-[var(--green)] bg-[var(--green-subtle,transparent)] text-[var(--green)]'
          : 'border-[var(--border)] text-[var(--fg-2)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]'
      }`}
    >
      <Icon name={done ? 'check-circle' : 'circle'} size={14} />
      {label}
    </button>
  );
}

interface Props {
  canEdit: boolean;
  onOpenAluno?: (alunoId: string) => void;
  onCountChange?: (contagem: Record<string, number>) => void;
}

export function AcessoHmClient({ canEdit, onOpenAluno, onCountChange }: Props) {
  const [items, setItems] = useState<HmFilaItem[]>([]);
  const [turmas, setTurmas] = useState<TurmaThb[]>([]);
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState<HmBucket>('liberacoes');
  const [busca, setBusca] = useState('');
  const [ignorar, setIgnorar] = useState<HmFilaItem | null>(null);
  const [ignorarObs, setIgnorarObs] = useState('');
  const [turmasOpen, setTurmasOpen] = useState(false);
  const [novaTurma, setNovaTurma] = useState('');
  const [busy, setBusy] = useState<Set<string>>(new Set());
  const { toast, flash } = useFlash();

  const recarregar = useCallback(async () => {
    const [f, t] = await Promise.all([loadHmFila(), loadTurmasThb()]);
    setItems(f);
    setTurmas(t);
  }, []);

  useEffect(() => {
    (async () => { await recarregar(); setLoading(false); })();
  }, [recarregar]);

  const contagem = useMemo(() => {
    const c: Record<string, number> = {};
    for (const i of items) c[i.bucket] = (c[i.bucket] ?? 0) + 1;
    return c;
  }, [items]);

  useEffect(() => { if (!loading) onCountChange?.(contagem); }, [contagem, loading, onCountChange]);

  const turmaAtual = useMemo(() => turmas.find((t) => t.atual) ?? null, [turmas]);
  const doBucket = HM_BUCKETS.find((b) => b.key === bucket)!;

  const lista = useMemo(() => {
    const tokens = busca.toLowerCase().trim().split(/\s+/).filter(Boolean);
    return items
      .filter((i) => i.bucket === bucket)
      .filter((i) => {
        if (!tokens.length) return true;
        const hay = `${i.nome ?? ''} ${i.email ?? ''} ${i.offerCode ?? ''} ${i.ofertaLabel ?? ''} ${i.turmaCodigo ?? ''}`.toLowerCase();
        return tokens.every((t) => hay.includes(t));
      })
      .sort((a, b) => (b.dataCompra ?? '').localeCompare(a.dataCompra ?? ''));
  }, [items, bucket, busca]);

  /** Executa uma mutação, resincroniza a fila e dá feedback. */
  async function run(compraId: string, action: () => Promise<{ ok: boolean; msg?: string }>, okMsg?: string) {
    if (!canEdit) return;
    setBusy((s) => new Set(s).add(compraId));
    const res = await action();
    if (res.ok) { await recarregar(); if (okMsg) flash(okMsg); }
    else flash(res.msg ? `Falhou: ${res.msg}` : 'Falhou ao salvar.');
    setBusy((s) => { const n = new Set(s); n.delete(compraId); return n; });
  }

  function onToggleEtapa(item: HmFilaItem, etapa: 'ativacao' | 'acesso', done: boolean) {
    if (etapa === 'ativacao' && !done && turmaPendente(item)) { flash('Defina a turma antes de ativar.'); return; }
    run(item.compraId, () => marcarEtapa(item.compraId, etapa, !done), !done ? 'Etapa marcada.' : 'Etapa desfeita.');
  }

  async function gerirTurmaAtual(id: number) { await run('turmas', () => setTurmaAtual(id), 'Turma atual atualizada.'); }
  async function gerirCriarTurma() {
    const codigo = novaTurma.trim();
    if (!codigo) return;
    setNovaTurma('');
    await run('turmas', () => criarTurma(codigo, false), `Turma ${codigo} criada.`);
  }

  return (
    <div>
      <SectionTitle
        right={
          <div className="flex items-center gap-2">
            {turmaAtual && <span className="text-xs text-[var(--fg-3)]">Turma atual: <strong className="text-[var(--fg-2)]">{turmaAtual.codigo}</strong></span>}
            {canEdit && <Button variant="ghost" size="sm" onClick={() => setTurmasOpen(true)}><Icon name="tags" size={14} /> Turmas</Button>}
            <span className="text-xs text-[var(--fg-3)]">{loading ? 'carregando…' : `${items.length} compras HM`}</span>
          </div>
        }
      >
        Acesso Holding Masters
      </SectionTitle>

      {/* Sub-abas por bucket */}
      <div className="flex flex-wrap gap-1 border-b border-[var(--border)] mb-4">
        {HM_BUCKETS.map((b) => {
          const n = contagem[b.key] ?? 0;
          const ativo = bucket === b.key;
          return (
            <button
              key={b.key}
              onClick={() => setBucket(b.key)}
              className={`inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
                ativo ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'
              }`}
            >
              <Icon name={b.icon} size={14} />
              {b.label}
              {n > 0 && (
                <span className={`ml-0.5 min-w-[18px] rounded-full px-1.5 py-0.5 text-[11px] font-semibold tabular ${
                  b.acionavel ? 'bg-[var(--accent)] text-black' : 'bg-[var(--surface-4)] text-[var(--fg-2)]'
                }`}>{n}</span>
              )}
            </button>
          );
        })}
      </div>

      <div className="mb-3 max-w-sm">
        <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome, e-mail, oferta, turma…" />
      </div>

      {loading ? (
        <Card className="p-4"><DataTable><Thead><Th>Aluno</Th><Th>Oferta</Th><Th>Valor</Th><Th>Etapas</Th><Th> </Th></Thead><tbody><SkeletonRows cols={[80, 64, 40, 64, 40]} /></tbody></DataTable></Card>
      ) : !lista.length ? (
        <EmptyState title={`Nada em "${doBucket.label}"`} hint="Compras HM entram aqui automaticamente pelo webhook." icon={doBucket.icon} />
      ) : (
        <div className="grid gap-2.5">
          {lista.map((item) => {
            const etapas = etapasDoItem(item);
            const trabalhando = busy.has(item.compraId);
            const precisaTurma = turmaPendente(item);
            return (
              <Card key={item.compraId} className="p-4">
                <div className="flex items-start justify-between gap-4 flex-wrap">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-[var(--fg)]">{item.nome || '—'}</span>
                      <CategoriaBadge categoria={item.categoria} />
                      {item.turmaCodigo && <Badge tone="accent" dot>{item.turmaCodigo}</Badge>}
                      {item.jaEraAlunoHm && <Badge tone="info" dot>Já era aluno HM</Badge>}
                      {!item.alunoId && <Badge tone="warning" dot>Sem aluno vinculado</Badge>}
                      {bucket === 'aguardando_diferenca' && <Badge tone="warning" dot>Só sinal pago</Badge>}
                      {bucket === 'nao_classificado' && item.offerCode && <Badge tone="danger" dot>offer: {item.offerCode}</Badge>}
                    </div>
                    <div className="mt-1 text-xs text-[var(--fg-3)] flex flex-wrap gap-x-3 gap-y-0.5">
                      {item.email && <span>{item.email}</span>}
                      {item.telefone && <span>{tel(item.telefone)}</span>}
                      {item.ofertaLabel && <span className="text-[var(--fg-2)]">{item.ofertaLabel}</span>}
                    </div>

                    {/* Etapas + turma (buckets acionáveis de acesso) */}
                    {(bucket === 'liberacoes' || bucket === 'renovacoes') && canEdit && (
                      <div className="mt-2.5 flex items-center gap-2 flex-wrap">
                        {item.needsAtivacao && (
                          <select
                            value={item.turmaId ?? ''}
                            disabled={trabalhando}
                            onChange={(e) => { const v = Number(e.target.value); if (v) run(item.compraId, () => setTurmaHm(item.compraId, v), 'Turma definida.'); }}
                            className={`rounded-[var(--r-md)] border bg-[var(--surface-3)] px-2 py-1.5 text-xs text-[var(--fg)] ${precisaTurma ? 'border-[var(--yellow)]' : 'border-[var(--border)]'}`}
                          >
                            <option value="">{turmaAtual ? `Turma (${turmaAtual.codigo})…` : 'Selecionar turma…'}</option>
                            {turmas.map((t) => <option key={t.id} value={t.id}>{t.codigo}{t.atual ? ' (atual)' : ''}</option>)}
                          </select>
                        )}
                        {etapas.includes('ativacao') && (
                          <StepCheck done={!!item.ativadoEm} label="Ativado" quem={item.ativadoPorNome} quando={item.ativadoEm} disabled={trabalhando} onToggle={() => onToggleEtapa(item, 'ativacao', !!item.ativadoEm)} />
                        )}
                        <StepCheck done={!!item.acessoEm} label="Acesso liberado" quem={item.acessoPorNome} quando={item.acessoEm} disabled={trabalhando} onToggle={() => onToggleEtapa(item, 'acesso', !!item.acessoEm)} />
                      </div>
                    )}

                    {bucket === 'concluido' && (
                      <div className="mt-1.5 text-xs text-[var(--fg-3)] flex flex-wrap gap-x-3">
                        {item.ativadoEm && <span>Ativado{item.ativadoPorNome ? ` por ${item.ativadoPorNome}` : ''} · {fmtData(item.ativadoEm)}</span>}
                        {item.acessoEm && <span>Acesso{item.acessoPorNome ? ` por ${item.acessoPorNome}` : ''} · {fmtData(item.acessoEm)}</span>}
                        {item.ignoradoEm && <span>Ignorado{item.obs ? ` (${item.obs})` : ''}</span>}
                      </div>
                    )}
                  </div>

                  <div className="flex flex-col items-end gap-2 shrink-0">
                    <div className="text-right">
                      <div className="font-bold tabular text-[var(--fg)]">{fmtBRL(item.preco)}</div>
                      <div className="text-[11px] text-[var(--fg-3)]">{fmtData(item.dataCompra)}</div>
                    </div>
                    <div className="flex items-center gap-2">
                      {item.alunoId && onOpenAluno && <Button size="sm" variant="ghost" onClick={() => onOpenAluno(item.alunoId!)}>Ver ficha</Button>}
                      {canEdit && bucket === 'aguardando_diferenca' && (
                        <Button size="sm" variant="subtle" disabled={trabalhando} onClick={() => run(item.compraId, () => quitarManual(item.compraId, true), 'Movido para liberações.')}>Mover p/ liberação</Button>
                      )}
                      {canEdit && bucket !== 'concluido' && (
                        <Button size="sm" variant="ghost" disabled={trabalhando} onClick={() => { setIgnorar(item); setIgnorarObs(''); }}>Ignorar</Button>
                      )}
                    </div>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {/* Modal de gestão de turmas */}
      {turmasOpen && (
        <Modal open onClose={() => setTurmasOpen(false)} title="Turmas THB" width="max-w-md">
          <p className="text-sm text-[var(--fg-3)] mb-3">A turma <strong>atual</strong> é o padrão sugerido ao liberar aluno novo.</p>
          <div className="grid gap-1.5 mb-4 max-h-64 overflow-y-auto">
            {turmas.map((t) => (
              <div key={t.id} className="flex items-center justify-between gap-3 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2">
                <span className="text-sm text-[var(--fg)]">{t.codigo} {t.atual && <Badge tone="accent" dot>atual</Badge>}</span>
                {!t.atual && canEdit && <Button size="sm" variant="ghost" onClick={() => gerirTurmaAtual(t.id)}>Tornar atual</Button>}
              </div>
            ))}
          </div>
          {canEdit && (
            <div className="flex items-center gap-2 border-t border-[var(--border)] pt-3">
              <Input value={novaTurma} onChange={(e) => setNovaTurma(e.target.value)} placeholder="Nova turma (ex.: T40)" onKeyDown={(e) => { if (e.key === 'Enter') gerirCriarTurma(); }} />
              <Button size="sm" onClick={gerirCriarTurma} disabled={!novaTurma.trim()}><Icon name="plus" size={14} /> Criar</Button>
            </div>
          )}
        </Modal>
      )}

      {ignorar && (
        <ConfirmDialog
          title="Ignorar item"
          message={
            <span>
              Remover <strong>{ignorar.nome || 'este item'}</strong> da fila? Motivo (opcional):
              <textarea
                value={ignorarObs}
                onChange={(e) => setIgnorarObs(e.target.value)}
                rows={2}
                className="mt-2 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1.5 text-sm text-[var(--fg)]"
                placeholder="Ex.: compra duplicada / teste"
              />
            </span>
          }
          confirmLabel="Ignorar"
          danger
          onCancel={() => setIgnorar(null)}
          onConfirm={() => { const it = ignorar; setIgnorar(null); run(it.compraId, () => ignorarHm(it.compraId, ignorarObs || undefined), 'Item ignorado.'); }}
        />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
