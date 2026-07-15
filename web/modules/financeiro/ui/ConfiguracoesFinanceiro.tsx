'use client';

// Configurações do controle financeiro — o "personalizável": metas por turma
// e a régua de cobrança que alimenta a fila do dia.
import { useEffect, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { Meta, ReguaPasso } from '../domain/types';
import { loadMetas, loadRegua, salvarMeta, salvarRegua } from './financeiro-data';
import {
  Button, DataTable, EmptyState, FilterSelect, Input, Loading, SectionCard, Td, Th, Thead,
  Toast, Toggle, Tr, useFlash,
} from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';

const CANAIS = [
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'ligacao', label: 'Ligação' },
  { value: 'email', label: 'E-mail' },
];
const canalLabel = (c: string | null) => CANAIS.find((x) => x.value === c)?.label ?? c ?? '—';

/** Formulário da meta em texto cru — só converte para número/null no salvar. */
interface MetaForm { arrecadacao: string; cobertura: string; prazo: string; fechamento: string; obs: string }
const META_VAZIA: MetaForm = { arrecadacao: '', cobertura: '', prazo: '', fechamento: '', obs: '' };

/** Passo da régua em edição — offset como texto para aceitar "-" durante a digitação. */
interface PassoEdit { key: number; offset: string; titulo: string; canal: string; ativo: boolean }

export function ConfiguracoesFinanceiro({ canEdit, turmas, onReguaSalva }: {
  canEdit: boolean;
  turmas: string[];
  /** Sincroniza a régua recém-salva com o client (fila/drawer usam a mesma). */
  onReguaSalva?: (passos: ReguaPasso[]) => void;
}) {
  const { toast, flash } = useFlash();
  const [metas, setMetas] = useState<Meta[] | null>(null);
  const [passos, setPassos] = useState<PassoEdit[] | null>(null);
  const proximaKey = useRef(0);

  useEffect(() => {
    let vivo = true;
    loadMetas().then((ms) => { if (vivo) setMetas(ms); });
    loadRegua().then((ps) => {
      if (!vivo) return;
      setPassos(ps.map((p) => ({
        key: proximaKey.current++,
        offset: String(p.offset_dias),
        titulo: p.titulo,
        canal: p.canal ?? '',
        ativo: p.ativo,
      })));
    });
    return () => { vivo = false; };
  }, []);

  // ── Metas por turma ────────────────────────────────────────────────────────
  // Sem setState em efeito: a turma ativa é derivada e o rascunho vem carimbado
  // com a turma dele — trocar de turma re-hidrata do que está salvo (mesmo padrão
  // de "carga carimbada" do FinanceiroClient).
  const [turmaEscolhida, setTurmaEscolhida] = useState<string | null>(null);
  const turmaSel = turmaEscolhida ?? turmas[0] ?? '';
  const [rascunho, setRascunho] = useState<{ turma: string; f: MetaForm } | null>(null);
  const [salvandoMeta, setSalvandoMeta] = useState(false);

  const metaDaTurma = (t: string): MetaForm => {
    const m = metas?.find((x) => x.turma === t);
    return m ? {
      arrecadacao: m.meta_arrecadacao != null ? String(m.meta_arrecadacao) : '',
      cobertura: m.meta_cobertura_pct != null ? String(m.meta_cobertura_pct) : '',
      prazo: m.prazo_quitacao_dias != null ? String(m.prazo_quitacao_dias) : '',
      fechamento: m.data_fechamento ? m.data_fechamento.slice(0, 10) : '',
      obs: m.obs ?? '',
    } : META_VAZIA;
  };
  const form = rascunho && rascunho.turma === turmaSel ? rascunho.f : metaDaTurma(turmaSel);

  const set = (k: keyof MetaForm) => (v: string) =>
    setRascunho({ turma: turmaSel, f: { ...form, [k]: v } });

  const gravarMeta = async () => {
    if (!turmaSel) { flash('Selecione uma turma.'); return; }
    setSalvandoMeta(true);
    const r = await salvarMeta({
      turma: turmaSel,
      meta_arrecadacao: form.arrecadacao.trim() ? Number(form.arrecadacao) : null,
      meta_cobertura_pct: form.cobertura.trim() ? Number(form.cobertura) : null,
      prazo_quitacao_dias: form.prazo.trim() ? Number(form.prazo) : null,
      data_fechamento: form.fechamento || null,
      obs: form.obs.trim() || null,
      atualizado_em: null,
      atualizado_por: null,
    });
    flash(r.msg ?? (r.ok ? 'Meta salva.' : 'Falhou.'));
    if (r.ok) {
      setMetas(await loadMetas());
      setRascunho(null); // re-hidrata do que ficou salvo no banco
    }
    setSalvandoMeta(false);
  };

  // ── Régua de cobrança ──────────────────────────────────────────────────────
  const [salvandoRegua, setSalvandoRegua] = useState(false);

  const mudarPasso = (key: number, patch: Partial<PassoEdit>) =>
    setPassos((ps) => (ps ?? []).map((p) => (p.key === key ? { ...p, ...patch } : p)));

  const addPasso = () =>
    setPassos((ps) => [...(ps ?? []), { key: proximaKey.current++, offset: '0', titulo: '', canal: '', ativo: true }]);

  const removerPasso = (key: number) => setPassos((ps) => (ps ?? []).filter((p) => p.key !== key));

  const gravarRegua = async () => {
    const lista = passos ?? [];
    if (lista.some((p) => !p.titulo.trim() || !Number.isFinite(Number(p.offset)) || p.offset.trim() === '')) {
      flash('Preencha título e offset (em dias) de todos os passos.');
      return;
    }
    setSalvandoRegua(true);
    const payload: ReguaPasso[] = lista.map((p, i) => ({
      ordem: i + 1,
      offset_dias: Number(p.offset),
      titulo: p.titulo.trim(),
      canal: p.canal || null,
      ativo: p.ativo,
    }));
    const r = await salvarRegua(payload);
    flash(r.msg ?? (r.ok ? 'Régua salva.' : 'Falhou.'));
    if (r.ok) onReguaSalva?.(payload);
    setSalvandoRegua(false);
  };

  if (metas === null || passos === null) return <Loading label="Carregando configurações…" />;

  const metasOrdenadas = [...metas].sort((a, b) => a.turma.localeCompare(b.turma, 'pt-BR'));

  return (
    <div className="space-y-4">
      <SectionCard
        title="Metas por turma"
        subtitle="O alvo que o dashboard persegue: arrecadação, cobertura e prazo de quitação de cada turma."
      >
        <div className="space-y-3">
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Turma</span>
              <FilterSelect value={turmaSel} onChange={(e) => setTurmaEscolhida(e.target.value)} className="mt-1">
                {!turmas.length && <option value="">— sem turmas —</option>}
                {turmas.map((t) => <option key={t} value={t}>{t}</option>)}
              </FilterSelect>
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Meta de arrecadação (R$)</span>
              <Input type="number" min={0} value={form.arrecadacao} onChange={(e) => set('arrecadacao')(e.target.value)} disabled={!canEdit} placeholder="Ex.: 450000" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Meta de cobertura (%)</span>
              <Input type="number" min={0} max={100} value={form.cobertura} onChange={(e) => set('cobertura')(e.target.value)} disabled={!canEdit} placeholder="Ex.: 85" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Prazo de quitação (dias)</span>
              <Input type="number" min={0} value={form.prazo} onChange={(e) => set('prazo')(e.target.value)} disabled={!canEdit} placeholder="Ex.: 90" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Data de fechamento</span>
              <Input type="date" value={form.fechamento} onChange={(e) => set('fechamento')(e.target.value)} disabled={!canEdit} className="mt-1" />
            </label>
          </div>
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Observação</span>
            <Input value={form.obs} onChange={(e) => set('obs')(e.target.value)} disabled={!canEdit} placeholder="Ex.: turma com 30% de alunos da base — meta ajustada" className="mt-1" />
          </label>
          {canEdit && (
            <Button onClick={gravarMeta} disabled={salvandoMeta || !turmaSel}>
              <Icon name="check" size={14} /> {salvandoMeta ? 'Salvando…' : 'Salvar meta'}
            </Button>
          )}
        </div>

        <div className="mt-4">
          {!metasOrdenadas.length ? (
            <EmptyState title="Nenhuma meta salva ainda" hint="Escolha uma turma acima e defina o alvo dela." icon="clipboard" />
          ) : (
            <DataTable>
              <Thead>
                <Th>Turma</Th>
                <Th className="text-right">Arrecadação</Th>
                <Th className="text-right">Cobertura</Th>
                <Th className="text-right">Prazo</Th>
                <Th>Fechamento</Th>
                <Th>Observação</Th>
              </Thead>
              <tbody>
                {metasOrdenadas.map((m) => (
                  <Tr key={m.turma}>
                    <Td className="text-[13px] font-medium text-[var(--fg)]">{m.turma}</Td>
                    <Td className="text-right tabular text-[13px] text-[var(--fg)]">{fmtBRL(m.meta_arrecadacao)}</Td>
                    <Td className="text-right tabular text-xs text-[var(--fg-2)]">{m.meta_cobertura_pct != null ? `${m.meta_cobertura_pct}%` : '—'}</Td>
                    <Td className="text-right tabular text-xs text-[var(--fg-2)]">{m.prazo_quitacao_dias != null ? `${m.prazo_quitacao_dias}d` : '—'}</Td>
                    <Td className="text-xs tabular text-[var(--fg-2)] whitespace-nowrap">{m.data_fechamento ? fmtData(m.data_fechamento) : '—'}</Td>
                    <Td className="text-xs text-[var(--fg-3)]">{m.obs || '—'}</Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </div>
      </SectionCard>

      <SectionCard
        title="Régua de cobrança"
        subtitle="Offset em dias relativo ao vencimento combinado — negativo dispara antes, 0 no dia, positivo depois."
      >
        {!passos.length ? (
          <EmptyState title="Régua vazia" hint="Adicione o primeiro passo para a fila do dia começar a trabalhar." icon="mail" />
        ) : (
          <div className="space-y-2">
            <div className="hidden sm:grid grid-cols-[72px_1fr_150px_auto_auto] gap-2 px-0.5 text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">
              <span>Offset</span><span>Título do passo</span><span>Canal</span><span>Ativo</span><span />
            </div>
            {passos.map((p) => (
              <div key={p.key} className="grid grid-cols-[72px_1fr] sm:grid-cols-[72px_1fr_150px_auto_auto] gap-2 items-center">
                <Input
                  type="number"
                  value={p.offset}
                  onChange={(e) => mudarPasso(p.key, { offset: e.target.value })}
                  disabled={!canEdit}
                  aria-label="Offset em dias"
                  className="tabular"
                />
                <Input
                  value={p.titulo}
                  onChange={(e) => mudarPasso(p.key, { titulo: e.target.value })}
                  disabled={!canEdit}
                  placeholder="Ex.: Lembrete de vencimento"
                  aria-label="Título do passo"
                />
                <FilterSelect
                  value={p.canal}
                  onChange={(e) => mudarPasso(p.key, { canal: e.target.value })}
                  disabled={!canEdit}
                  aria-label="Canal do passo"
                >
                  <option value="">—</option>
                  {CANAIS.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
                </FilterSelect>
                <Toggle checked={p.ativo} onChange={(v) => mudarPasso(p.key, { ativo: v })} disabled={!canEdit} />
                {canEdit ? (
                  <Button variant="ghost" size="sm" onClick={() => removerPasso(p.key)} title="Remover passo" aria-label={`Remover passo ${p.titulo || canalLabel(p.canal)}`}>
                    <Icon name="trash" size={14} />
                  </Button>
                ) : <span />}
              </div>
            ))}
          </div>
        )}
        {canEdit && (
          <div className="mt-3 flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={addPasso}>
              <Icon name="plus" size={14} /> Adicionar passo
            </Button>
            <Button onClick={gravarRegua} disabled={salvandoRegua}>
              <Icon name="check" size={14} /> {salvandoRegua ? 'Salvando…' : 'Salvar régua'}
            </Button>
          </div>
        )}
      </SectionCard>

      <Toast>{toast}</Toast>
    </div>
  );
}
