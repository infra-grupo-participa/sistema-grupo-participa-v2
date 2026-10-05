'use client';

// Peças compartilhadas da tela de pedidos (quem pede) e da aba de aprovação (Central).
import { useEffect, useState } from 'react';
import { Badge, Button, Input, MultiSelect } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ESPACO_LABEL, parseInstrucao } from '../domain/aluno-360';
import {
  INSTRUCOES,
  ROTULO_PLANILHA,
  ROTULO_STATUS,
  TOM_STATUS,
  distincaoAluno,
  type AlunoResumo,
  type PedidoLinha,
} from '../domain/pedidos-alteracao';
import { buscarAlunos } from './pedidos-alteracao-data';

export const rotuloInstrucao = (v: string) => parseInstrucao({ instrucao: v, espaco_instrucao: null, eh_socio: null })?.label ?? v;

export const FIELD_CLS =
  'w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)] transition-colors focus:border-[var(--border-accent)] focus:outline-none';

export function Rotulo({ children, dica }: { children: React.ReactNode; dica?: string }) {
  return (
    <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">
      {children}
      {dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}
    </span>
  );
}

export function StatusPedido({ p }: { p: Pick<PedidoLinha, 'status' | 'planilha_status'> }) {
  return (
    <span className="inline-flex flex-wrap gap-1">
      <Badge tone={TOM_STATUS[p.status]}>{ROTULO_STATUS[p.status]}</Badge>
      {p.planilha_status && (
        <Badge tone={p.planilha_status === 'ok' ? 'success' : p.planilha_status === 'erro' ? 'danger' : 'neutral'}>
          {ROTULO_PLANILHA[p.planilha_status]}
        </Badge>
      )}
    </span>
  );
}

/** Uma linha de aluno com os dados de distinção (homônimos). */
export function AlunoDistincao({ a }: { a: AlunoResumo }) {
  return (
    <span className="block min-w-0">
      <span className="block text-sm font-medium text-[var(--fg)] truncate">{a.nome || 'sem nome'}</span>
      <span className="block text-xs text-[var(--fg-3)] truncate">{distincaoAluno(a, rotuloInstrucao) || 'sem dados de distinção'}</span>
    </span>
  );
}

/**
 * Busca de aluno com sugestão a partir de 3 letras (pa_buscar_alunos). Mostra só o mínimo para distinguir
 * homônimos. `papelFixo` trava titular/sócio (ex.: titular na troca de sócio).
 */
export function BuscaAluno({ rotulo, escolhido, onEscolher, papelFixo, excluirIds = [] }: {
  rotulo: string;
  escolhido: AlunoResumo | null;
  onEscolher: (a: AlunoResumo | null) => void;
  papelFixo?: 'titular' | 'socio';
  excluirIds?: string[];
}) {
  const [termo, setTermo] = useState('');
  const [instrucoes, setInstrucoes] = useState<string[]>([]);
  const [espacos, setEspacos] = useState<string[]>([]);
  const [papel, setPapel] = useState<string[]>([]);
  const [resultados, setResultados] = useState<AlunoResumo[] | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [filtrosAbertos, setFiltrosAbertos] = useState(false);

  const termoOk = termo.trim().length >= 3;
  const papelBusca = papelFixo ?? (papel.length === 1 ? (papel[0] as 'titular' | 'socio') : null);

  useEffect(() => {
    if (!termoOk || escolhido) return;
    let vivo = true;
    const t = setTimeout(async () => {
      setBuscando(true);
      const r = await buscarAlunos(termo.trim(), { instrucoes, espacos, papel: papelBusca });
      if (!vivo) return;
      setResultados(r);
      setBuscando(false);
    }, 300);
    return () => { vivo = false; clearTimeout(t); };
  }, [termo, termoOk, instrucoes, espacos, papelBusca, escolhido]);

  if (escolhido) {
    return (
      <div>
        <Rotulo>{rotulo}</Rotulo>
        <div className="flex items-center justify-between gap-3 rounded-[var(--r-md)] border border-[var(--border-accent)] bg-[var(--accent-subtle)] px-3 py-2">
          <AlunoDistincao a={escolhido} />
          <Button variant="ghost" size="sm" onClick={() => { onEscolher(null); setResultados(null); }}>Trocar</Button>
        </div>
      </div>
    );
  }

  const lista = (resultados ?? []).filter((a) => !excluirIds.includes(a.id));
  return (
    <div>
      <Rotulo dica="digite 3 letras ou mais">{rotulo}</Rotulo>
      <div className="flex gap-2">
        <div className="flex-1">
          <Input value={termo} onChange={(e) => setTermo(e.target.value)} placeholder="Nome ou e-mail do aluno" aria-label={rotulo} />
        </div>
        <Button variant="ghost" size="sm" onClick={() => setFiltrosAbertos((v) => !v)} aria-expanded={filtrosAbertos}>
          <Icon name="search" size={14} /> Filtros
        </Button>
      </div>
      {filtrosAbertos && (
        <div className="mt-2 flex flex-wrap gap-2">
          <MultiSelect values={instrucoes} onChange={setInstrucoes} placeholder="Todas as instruções"
            options={INSTRUCOES.map((i) => ({ value: i, label: rotuloInstrucao(i) }))} />
          <MultiSelect values={espacos} onChange={setEspacos} placeholder="Todos os espaços"
            options={Object.entries(ESPACO_LABEL).map(([k, l]) => ({ value: k, label: l }))} />
          {!papelFixo && (
            <MultiSelect values={papel} onChange={setPapel} placeholder="Titular / Sócio"
              options={[{ value: 'titular', label: 'Titular' }, { value: 'socio', label: 'Sócio' }]} />
          )}
        </div>
      )}
      {termoOk && (
        <div className="mt-2 max-h-72 overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)] divide-y divide-[var(--border-faint)]">
          {buscando && resultados === null && <div className="px-3 py-2 text-xs text-[var(--fg-3)]">Buscando…</div>}
          {resultados !== null && lista.length === 0 && (
            <div className="px-3 py-2 text-xs text-[var(--fg-3)]">Nenhum aluno encontrado. Confira o nome ou os filtros.</div>
          )}
          {lista.map((a) => (
            <button key={a.id} type="button" onClick={() => onEscolher(a)}
              className="w-full text-left px-3 py-2 hover:bg-[var(--surface-3)] transition-colors">
              <AlunoDistincao a={a} />
            </button>
          ))}
          {lista.length >= 15 && <div className="px-3 py-1.5 text-[11px] text-[var(--fg-3)]">Mostrando os 15 primeiros: refine a busca.</div>}
        </div>
      )}
    </div>
  );
}
