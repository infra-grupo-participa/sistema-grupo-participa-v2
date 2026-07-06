'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  type HmFilaItem,
  type HmBucket,
  type HmAcao,
  HM_BUCKETS,
  HM_CATEGORIA_LABEL,
  HM_ACAO_LABEL,
} from '../domain/acesso-hm';
import { loadHmFila, baixarHm } from './acesso-hm-data';
import { Card, EmptyState, SectionTitle, Badge, Button, SkeletonRows, ConfirmDialog, Toast, useFlash, Input, DataTable, Thead, Th } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { tel } from './alunos-ui-shared';

function CategoriaBadge({ categoria }: { categoria: string | null }) {
  if (!categoria) return <Badge tone="danger" dot>Sem categoria</Badge>;
  const m = HM_CATEGORIA_LABEL[categoria];
  return <Badge tone={m?.tone ?? 'neutral'} dot>{m?.label ?? categoria}</Badge>;
}

interface Props {
  canEdit: boolean;
  onOpenAluno?: (alunoId: string) => void;
  /** Notifica o pai (AlunosClient) quando o total de pendentes muda, p/ atualizar o badge da aba. */
  onCountChange?: (contagem: Record<string, number>) => void;
}

export function AcessoHmClient({ canEdit, onOpenAluno, onCountChange }: Props) {
  const [items, setItems] = useState<HmFilaItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState<HmBucket>('liberacoes');
  const [busca, setBusca] = useState('');
  const [ignorar, setIgnorar] = useState<HmFilaItem | null>(null);
  const [ignorarObs, setIgnorarObs] = useState('');
  const { toast, flash } = useFlash();

  useEffect(() => {
    (async () => {
      setItems(await loadHmFila());
      setLoading(false);
    })();
  }, []);

  const contagem = useMemo(() => {
    const c: Record<string, number> = {};
    for (const i of items) c[i.bucket] = (c[i.bucket] ?? 0) + 1;
    return c;
  }, [items]);

  // Propaga contagem p/ o badge da aba sempre que a fila muda.
  useEffect(() => { if (!loading) onCountChange?.(contagem); }, [contagem, loading, onCountChange]);

  const doBucket = HM_BUCKETS.find((b) => b.key === bucket)!;

  const lista = useMemo(() => {
    const tokens = busca.toLowerCase().trim().split(/\s+/).filter(Boolean);
    return items
      .filter((i) => i.bucket === bucket)
      .filter((i) => {
        if (!tokens.length) return true;
        const hay = `${i.nome ?? ''} ${i.email ?? ''} ${i.offerCode ?? ''} ${i.ofertaLabel ?? ''}`.toLowerCase();
        return tokens.every((t) => hay.includes(t));
      })
      .sort((a, b) => (b.dataCompra ?? '').localeCompare(a.dataCompra ?? ''));
  }, [items, bucket, busca]);

  /** Baixa com rollback otimista (Design Pattern #6). */
  async function aplicar(item: HmFilaItem, acao: HmAcao, obs?: string, msg?: string) {
    if (!canEdit) return;
    const antes = items;
    setItems((cur) => cur.filter((i) => i.compraId !== item.compraId));
    const res = await baixarHm(item.compraId, acao, obs);
    if (!res.ok) {
      setItems(antes);
      flash(res.msg ? `Falhou: ${res.msg}` : 'Falhou ao salvar.');
      return;
    }
    flash(msg ?? 'Feito!');
  }

  function acoesDoCard(item: HmFilaItem) {
    if (!canEdit) return null;
    if (bucket === 'liberacoes')
      return <Button size="sm" variant="success" onClick={() => aplicar(item, 'liberado', undefined, 'Acesso liberado.')}><Icon name="check" size={14} /> Marcar liberado</Button>;
    if (bucket === 'renovacoes')
      return <Button size="sm" variant="success" onClick={() => aplicar(item, 'renovado', undefined, 'Renovação registrada.')}><Icon name="refresh" size={14} /> Marcar renovado</Button>;
    if (bucket === 'aguardando_diferenca')
      return (
        <div className="flex gap-2">
          <Button size="sm" variant="subtle" onClick={() => aplicar(item, 'quitado_manual', undefined, 'Movido para liberações.')}>Mover p/ liberação</Button>
          <Button size="sm" variant="ghost" onClick={() => { setIgnorar(item); setIgnorarObs(''); }}>Ignorar</Button>
        </div>
      );
    if (bucket === 'nao_classificado')
      return <Button size="sm" variant="ghost" onClick={() => { setIgnorar(item); setIgnorarObs(''); }}>Ignorar</Button>;
    return null;
  }

  return (
    <div>
      <SectionTitle right={<span className="text-xs text-[var(--fg-3)]">{loading ? 'carregando…' : `${items.length} compras HM`}</span>}>
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
                  b.acionavel && n > 0 ? 'bg-[var(--accent)] text-black' : 'bg-[var(--surface-4)] text-[var(--fg-2)]'
                }`}>{n}</span>
              )}
            </button>
          );
        })}
      </div>

      <div className="mb-3 max-w-sm">
        <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome, e-mail, oferta…" />
      </div>

      {loading ? (
        <Card className="p-4"><DataTable><Thead><Th>Aluno</Th><Th>Oferta</Th><Th>Valor</Th><Th>Compra</Th><Th> </Th></Thead><tbody><SkeletonRows cols={[80, 64, 40, 48, 56]} /></tbody></DataTable></Card>
      ) : !lista.length ? (
        <EmptyState title={`Nada em "${doBucket.label}"`} hint="Compras HM entram aqui automaticamente pelo webhook." icon={doBucket.icon} />
      ) : (
        <div className="grid gap-2.5">
          {lista.map((item) => (
            <Card key={item.compraId} className="p-4">
              <div className="flex items-start justify-between gap-4 flex-wrap">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-[var(--fg)]">{item.nome || '—'}</span>
                    <CategoriaBadge categoria={item.categoria} />
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
                  {bucket === 'concluido' && item.baixaAcao && (
                    <div className="mt-1.5 text-xs text-[var(--fg-3)]">
                      {HM_ACAO_LABEL[item.baixaAcao]}{item.baixadoPorNome ? ` por ${item.baixadoPorNome}` : ''}{item.baixadoEm ? ` · ${fmtData(item.baixadoEm)}` : ''}
                    </div>
                  )}
                </div>
                <div className="flex flex-col items-end gap-2 shrink-0">
                  <div className="text-right">
                    <div className="font-bold tabular text-[var(--fg)]">{fmtBRL(item.preco)}</div>
                    <div className="text-[11px] text-[var(--fg-3)]">{fmtData(item.dataCompra)}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    {item.alunoId && onOpenAluno && (
                      <Button size="sm" variant="ghost" onClick={() => onOpenAluno(item.alunoId!)}>Ver ficha</Button>
                    )}
                    {acoesDoCard(item)}
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      {ignorar && (
        <ConfirmDialog
          title="Ignorar item"
          message={
            <span>
              Remover <strong>{ignorar.nome || 'este item'}</strong> da fila? Informe o motivo (opcional):
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
          onConfirm={() => { const it = ignorar; setIgnorar(null); aplicar(it, 'ignorado', ignorarObs || undefined, 'Item ignorado.'); }}
        />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
