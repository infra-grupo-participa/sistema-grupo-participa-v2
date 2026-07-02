'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  type Aluno360,
  ESPACO_LABEL,
  ESPACO_COLOR,
  NRANK,
  SITUACAO,
  searchHaystack,
} from '../domain/aluno-360';
import { nivelOptions } from '@/shared/domain/nivel-resultado';
import { loadAlunos360, loadTurmas, type Turma } from './alunos-data';
import { Badge, NivelBadge, DataTable, Thead, Th as Thx, Tr, Td, EmptyState, Button, Toolbar, SearchInput, MultiSelect, SkeletonRows, Toast, useFlash } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtData } from '@/shared/ui/format';
import { DashboardAlunos } from './DashboardAlunos';
import { AlunoDrawer } from './AlunoDrawer';
import { exportarCsvAlunos, exportarExcelAlunos } from './alunos-export';
import { sitTone, tel, turmaCombo } from './alunos-ui-shared';

type SortCol = 'nome' | 'nivel' | 'instrucao' | 'turma' | 'vencimento';
interface Filtros { situacao: string[]; espaco: string[]; nivel: string[]; jornada: string[]; papel: string[]; turma: string[]; estado: string[] }
const FILTROS_VAZIO: Filtros = { situacao: [], espaco: [], nivel: [], jornada: [], papel: [], turma: [], estado: [] };

function EspacoBadge({ espaco }: { espaco: string }) {
  const label = ESPACO_LABEL[espaco];
  if (!label) return <span className="text-[var(--fg-2)]">{espaco}</span>;
  return <Badge dotColor={ESPACO_COLOR[espaco] || 'var(--nivel-base)'}>{label}</Badge>;
}

/** Texto com botão de copiar — não propaga o clique para a linha. */
function CopyText({ value, display }: { value: string; display?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard?.writeText(value).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1200); });
      }}
      title="Copiar"
      className="group inline-flex items-center gap-1 text-xs text-[var(--fg-3)] hover:text-[var(--accent)] transition-colors max-w-full"
    >
      <span className="truncate">{display || value}</span>
      <span className="opacity-0 group-hover:opacity-100 transition-opacity shrink-0 inline-flex">{copied ? <Icon name="check" size={13} /> : <Icon name="copy" size={13} />}</span>
    </button>
  );
}

export function AlunosClient({ canEdit }: { canEdit: boolean }) {
  const [alunos, setAlunos] = useState<Aluno360[]>([]);
  const [turmas, setTurmas] = useState<Turma[]>([]);
  const [loading, setLoading] = useState(true);
  const [busca, setBusca] = useState('');
  const [filtros, setFiltros] = useState<Filtros>(FILTROS_VAZIO);
  const [sortCol, setSortCol] = useState<SortCol>('nome');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [editMode, setEditMode] = useState(false);
  const { toast, flash } = useFlash();
  const [topTab, setTopTab] = useState<'dashboard' | 'lista'>('dashboard');

  const reload = useCallback(async () => setAlunos(await loadAlunos360()), []);
  useEffect(() => {
    (async () => {
      const [a, t] = await Promise.all([loadAlunos360(), loadTurmas()]);
      setAlunos(a);
      setTurmas(t);
      setLoading(false);
    })();
  }, []);

  const filtered = useMemo(() => {
    const tokens = busca.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const f = filtros;
    const list = alunos.filter((a) => {
      if (tokens.length) {
        const hay = searchHaystack(a);
        if (!tokens.every((t) => hay.includes(t))) return false;
      }
      // Múltipla seleção: OR dentro de cada filtro, AND entre filtros.
      if (f.situacao.length && !f.situacao.some((s) => (s === 'inadimplente' ? Number(a.saldo_devedor) > 0 : a.situacao_acesso === s))) return false;
      if (f.espaco.length && !f.espaco.includes(a.espaco_instrucao || '')) return false;
      if (f.nivel.length && !f.nivel.includes(a.nivel_resultado || '')) return false;
      if (f.papel.length && !f.papel.some((p) => (p === 'socio' ? a.eh_socio : p === 'titular' ? !a.eh_socio : p === 'aurum' ? a.turma_aurum_id != null : false))) return false;
      if (f.turma.length && !f.turma.some((t) => a.turma_codigo === t || a.turma_aurum_codigo === t)) return false;
      if (f.estado.length && !f.estado.includes(String(a.estado ?? '').toUpperCase())) return false;
      if (f.jornada.length && !f.jornada.some((j) => (j === 'com_ht' && a.tem_ht) || (j === 'com_hm' && a.tem_hm) || (j === 'com_placa' && a.tem_placa) || (j === 'com_depoimento' && a.tem_depoimento) || (j === 'com_sip' && a.sip_registrado))) return false;
      return true;
    });
    list.sort((a, b) => {
      if (sortCol === 'nivel') {
        const ra = a.nivel_resultado ? NRANK[a.nivel_resultado] ?? -1 : -2;
        const rb = b.nivel_resultado ? NRANK[b.nivel_resultado] ?? -1 : -2;
        if (ra !== rb) return sortDir === 'asc' ? ra - rb : rb - ra;
        return (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      }
      if (sortCol === 'instrucao') {
        const cmp = (ESPACO_LABEL[a.espaco_instrucao || ''] || '￿').localeCompare(ESPACO_LABEL[b.espaco_instrucao || ''] || '￿', 'pt-BR');
        return sortDir === 'asc' ? cmp : -cmp;
      }
      if (sortCol === 'turma') {
        const cmp = (turmaCombo(a) || '￿').localeCompare(turmaCombo(b) || '￿', 'pt-BR', { numeric: true });
        return sortDir === 'asc' ? cmp : -cmp;
      }
      if (sortCol === 'vencimento') {
        const ra = a.data_expiracao ? Date.parse(a.data_expiracao) : Infinity;
        const rb = b.data_expiracao ? Date.parse(b.data_expiracao) : Infinity;
        if (ra !== rb) return sortDir === 'asc' ? ra - rb : rb - ra;
        return (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      }
      const cmp = (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return list;
  }, [alunos, busca, filtros, sortCol, sortDir]);

  // Opções de filtro (turma em ordem decrescente T38→T1; estados A–Z).
  const turmaOpts = useMemo(() => Array.from(new Set(alunos.flatMap((a) => [a.turma_codigo, a.turma_aurum_codigo]).filter(Boolean) as string[])).sort((a, b) => b.localeCompare(a, 'pt-BR', { numeric: true, sensitivity: 'base' })), [alunos]);
  const estadoOpts = useMemo(() => Array.from(new Set(alunos.map((a) => String(a.estado ?? '').toUpperCase()).filter(Boolean))).sort(), [alunos]);
  const temFiltroLista = Boolean(busca) || Object.values(filtros).some((arr) => arr.length > 0);

  const selected = selectedId ? alunos.find((a) => a.id === selectedId) ?? null : null;
  const sortBtn = (col: SortCol) => () => {
    if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortCol(col); setSortDir('asc'); }
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Base de Alunos</h1>
      <p className="text-sm text-[var(--fg-3)] mb-4">Centro de controle — ficha 360° do aluno. {loading && 'carregando…'}</p>

      <div className="flex gap-1 border-b border-[var(--border)] mb-5">
        {([['dashboard', 'Dashboard'], ['lista', 'Lista de alunos']] as const).map(([k, l]) => (
          <button
            key={k}
            onClick={() => setTopTab(k)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
              topTab === k ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'
            }`}
          >
            {l}
          </button>
        ))}
      </div>

      {topTab === 'dashboard' && <DashboardAlunos alunos={alunos} />}

      {topTab === 'lista' && (
      <>
      <Toolbar className="mb-3">
        <SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome, e-mail, documento, cidade…" />
        <MultiSelect values={filtros.turma} onChange={(v) => setFiltros((f) => ({ ...f, turma: v }))} placeholder="Todas as turmas" options={turmaOpts.map((t) => ({ value: t, label: t }))} />
        <MultiSelect values={filtros.espaco} onChange={(v) => setFiltros((f) => ({ ...f, espaco: v }))} placeholder="Todos os espaços" options={Object.entries(ESPACO_LABEL).map(([k, l]) => ({ value: k, label: l }))} />
        <MultiSelect values={filtros.papel} onChange={(v) => setFiltros((f) => ({ ...f, papel: v }))} placeholder="Titular / Sócio" options={[{ value: 'titular', label: 'Titulares' }, { value: 'socio', label: 'Sócios' }, { value: 'aurum', label: 'Aurum' }]} />
        <MultiSelect values={filtros.estado} onChange={(v) => setFiltros((f) => ({ ...f, estado: v }))} placeholder="Todos os estados" options={estadoOpts.map((e) => ({ value: e, label: e }))} />
        <MultiSelect values={filtros.nivel} onChange={(v) => setFiltros((f) => ({ ...f, nivel: v }))} placeholder="Todos os níveis" options={nivelOptions().map((n) => ({ value: n.id, label: n.label }))} />
        <MultiSelect values={filtros.jornada} onChange={(v) => setFiltros((f) => ({ ...f, jornada: v }))} placeholder="Toda jornada" options={[{ value: 'com_ht', label: 'Com HT' }, { value: 'com_hm', label: 'Com HM' }, { value: 'com_placa', label: 'Com placa' }, { value: 'com_depoimento', label: 'Com depoimento' }, { value: 'com_sip', label: 'Com SIP' }]} />
        <MultiSelect values={filtros.situacao} onChange={(v) => setFiltros((f) => ({ ...f, situacao: v }))} placeholder="Toda situação" options={[...Object.entries(SITUACAO).map(([k, s]) => ({ value: k, label: s.label })), { value: 'inadimplente', label: 'Inadimplente' }]} />
      </Toolbar>

      <div className="flex items-center justify-between gap-3 mb-2 flex-wrap">
        <span className="text-xs text-[var(--fg-3)] tabular">{filtered.length.toLocaleString('pt-BR')} resultado{filtered.length === 1 ? '' : 's'} encontrado{filtered.length === 1 ? '' : 's'}</span>
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" onClick={() => exportarCsvAlunos(filtered)} disabled={!filtered.length}><Icon name="download" size={13} /> CSV</Button>
          <Button variant="ghost" size="sm" onClick={() => exportarExcelAlunos(filtered)} disabled={!filtered.length}><Icon name="download" size={13} /> Excel</Button>
          {temFiltroLista && <Button variant="ghost" size="sm" onClick={() => { setBusca(''); setFiltros(FILTROS_VAZIO); }}>Limpar filtros</Button>}
        </div>
      </div>

      <DataTable>
        <Thead>
          <Thx sortable active={sortCol === 'nome'} dir={sortDir} onClick={sortBtn('nome')}>Aluno</Thx>
          <Thx sortable active={sortCol === 'nivel'} dir={sortDir} onClick={sortBtn('nivel')}>Nível</Thx>
          <Thx>Profissão</Thx>
          <Thx sortable active={sortCol === 'instrucao'} dir={sortDir} onClick={sortBtn('instrucao')}>Espaço</Thx>
          <Thx sortable active={sortCol === 'turma'} dir={sortDir} onClick={sortBtn('turma')}>Turma</Thx>
          <Thx sortable active={sortCol === 'vencimento'} dir={sortDir} onClick={sortBtn('vencimento')}>Vencimento</Thx>
        </Thead>
        <tbody>
          {loading && !filtered.length && <SkeletonRows cols={[56, 80, 64, 48, 72]} />}
          {filtered.slice(0, 500).map((a) => {
            const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
            return (
              <Tr key={a.id} onClick={() => { setSelectedId(a.id); setEditMode(false); }}>
                <Td>
                  <div className="text-[var(--fg)] font-medium">{a.nome || '—'}</div>
                  <div className="flex flex-col gap-0.5 mt-0.5">
                    {a.email && <CopyText value={a.email} />}
                    {a.telefone && <CopyText value={a.telefone} display={tel(a.telefone)} />}
                  </div>
                </Td>
                <Td><NivelBadge nivel={a.nivel_resultado} /></Td>
                <Td className="text-[var(--fg-2)]">{a.profissao || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td>{a.espaco_instrucao ? <EspacoBadge espaco={a.espaco_instrucao} /> : <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="text-[var(--fg-2)] whitespace-nowrap">{turmaCombo(a) || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="whitespace-nowrap">
                  {a.data_expiracao
                    ? <div><span className="text-[var(--fg-2)]">{fmtData(a.data_expiracao)}</span>{sit && <div className="mt-0.5"><Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge></div>}</div>
                    : <span className="text-[var(--fg-3)]">—</span>}
                </Td>
              </Tr>
            );
          })}
        </tbody>
      </DataTable>
      {!filtered.length && !loading && <EmptyState title="Nenhum aluno encontrado" hint="Ajuste a busca ou os filtros." icon="users" />}
      {filtered.length > 500 && <p className="text-xs text-[var(--fg-3)] mt-2">Exibindo 500 de {filtered.length}. Refine a busca.</p>}
      </>
      )}

      {selected && (
        <AlunoDrawer
          a={selected}
          turmas={turmas}
          canEdit={canEdit}
          editMode={editMode}
          onToggleEdit={() => setEditMode((e) => !e)}
          onClose={() => { setSelectedId(null); setEditMode(false); }}
          onSaved={async (msg) => { flash(msg); setEditMode(false); await reload(); }}
        />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
