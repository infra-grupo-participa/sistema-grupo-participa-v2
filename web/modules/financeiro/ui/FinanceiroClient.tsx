'use client';

import { memo, useCallback, useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber, DiaFaturamento, Oferta, TurmaFin } from '../domain/types';
import {
  FILTROS_VAZIOS, STATUS_ORDEM, contaMorta, filtrar, resumir, statusLabel, statusTone, type Filtros,
} from '../domain/financeiro';
import * as data from './financeiro-data';
import { FinanceiroDashboard } from './FinanceiroDashboard';
import { FaturamentoDiario } from './FaturamentoDiario';
import { ContaDrawer } from './ContaDrawer';
import { exportarExcelFinanceiro } from './financeiro-export';
import {
  Badge, Button, DataTable, EmptyState, FilterSelect, Loading, MultiSelect, SearchInput,
  SectionCard, SkeletonRows, Td, Th, Thead, Toast, Toolbar, Tr, useFlash,
} from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';

type Tab = 'dashboard' | 'contas' | 'ofertas' | 'faturamento';
type Gaveta = Filtros['gaveta'];

/** Gavetas da fila — os cards de KPI são o próprio seletor (padrão do piloto Placas). */
const GAVETAS: { key: Gaveta; label: string; icon: string; tone: string }[] = [
  { key: 'todos', label: 'Todos', icon: 'users', tone: 'var(--fg-2)' },
  { key: 'vencido', label: 'Vencido', icon: 'alert', tone: 'var(--red)' },
  { key: 'sem_acordo', label: 'Sem acordo', icon: 'clipboard', tone: 'var(--fg-3)' },
  { key: 'incalculavel', label: 'A calcular', icon: 'notebook', tone: 'var(--yellow)' },
  { key: 'a_receber', label: 'A receber', icon: 'trending-up', tone: 'var(--accent)' },
  { key: 'quitado', label: 'Quitado', icon: 'check', tone: 'var(--green)' },
];

const SEM_CONTAS: ContaReceber[] = [];
const SEM_DIAS: DiaFaturamento[] = [];

export function FinanceiroClient({ canEdit, canVerDoc }: { canEdit: boolean; canVerDoc: boolean }) {
  const [tab, setTab] = useState<Tab>('dashboard');
  // Contas carimbadas com a turma de origem: `loading` é derivado (carga ≠ turma
  // selecionada), sem setState síncrono em efeito.
  const [carga, setCarga] = useState<{ turma: string | null; contas: ContaReceber[] } | null>(null);
  const [cargaFat, setCargaFat] = useState<{ turma: string | null; dias: DiaFaturamento[] } | null>(null);
  const [turmas, setTurmas] = useState<TurmaFin[]>([]);
  const [ofertas, setOfertas] = useState<Oferta[]>([]);
  const [turma, setTurma] = useState<string | null>(null);
  // Só carrega contas depois de saber qual é a turma atual (evita carga dupla no mount).
  const [pronto, setPronto] = useState(false);
  const contas = carga && carga.turma === turma ? carga.contas : SEM_CONTAS;
  const loading = !pronto || !carga || carga.turma !== turma;
  const dias = cargaFat && cargaFat.turma === turma ? cargaFat.dias : SEM_DIAS;
  const loadingFat = !pronto || !cargaFat || cargaFat.turma !== turma;
  const [filtros, setFiltros] = useState<Filtros>(FILTROS_VAZIOS);
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const { toast, flash } = useFlash();

  useEffect(() => {
    (async () => {
      const [ts, ofs] = await Promise.all([data.loadTurmas(), data.loadOfertas()]);
      setTurmas(ts);
      setOfertas(ofs);
      setTurma(ts.find((t) => t.atual)?.turma ?? ts[0]?.turma ?? null);
      setPronto(true);
    })();
    // A sidebar dispara 'hashchange' nativo ao trocar de aba na mesma rota (ver Sidebar.tsx),
    // então basta escutar hashchange/popstate + ler o hash no mount.
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'contas-a-receber') setTab('contas');
      else if (h === 'ofertas') setTab('ofertas');
      else if (h === 'faturamento') setTab('faturamento');
      else setTab('dashboard');
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    window.addEventListener('popstate', applyHash);
    return () => {
      window.removeEventListener('hashchange', applyHash);
      window.removeEventListener('popstate', applyHash);
    };
  }, []);

  useEffect(() => {
    if (!pronto) return;
    let vivo = true;
    data.loadContas(turma).then((cs) => { if (vivo) setCarga({ turma, contas: cs }); });
    data.loadFaturamento(turma).then((ds) => { if (vivo) setCargaFat({ turma, dias: ds }); });
    return () => { vivo = false; };
  }, [turma, pronto]);

  const reload = useCallback(async () => {
    setCarga({ turma, contas: await data.loadContas(turma) });
  }, [turma]);

  const act = useCallback(async (fn: () => Promise<{ ok: boolean; msg?: string }>) => {
    const r = await fn();
    flash(r.msg || (r.ok ? 'Feito!' : 'Falhou.'));
    await reload();
  }, [reload, flash]);

  const irPara = (hash: string) => { window.location.hash = hash; };

  const resumo = useMemo(() => resumir(contas), [contas]);
  const counts = useMemo(() => ({
    todos: contas.length,
    vencido: contas.filter((c) => c.status_financeiro === 'vencido').length,
    sem_acordo: resumo.semAcordo,
    incalculavel: resumo.incalculavel,
    a_receber: contas.filter((c) => (c.saldo_a_pagar ?? 0) > 0 && !contaMorta(c)).length,
    quitado: resumo.quitados,
  }), [contas, resumo]);
  const gavetaHint: Record<Gaveta, string> = {
    todos: turma ? `turma ${turma}` : 'todas as turmas',
    vencido: `${fmtBRL(resumo.vencido)} em atraso`,
    sem_acordo: 'sem data combinada — agir',
    incalculavel: 'sem insumo — descobrir o valor',
    a_receber: `${fmtBRL(resumo.aReceber)} a perseguir`,
    quitado: 'pacote 100% pago',
  };

  const canalOpts = useMemo(
    () => Array.from(new Set(contas.map((c) => c.canal).filter(Boolean))).sort((a, b) => a.localeCompare(b, 'pt-BR')),
    [contas],
  );

  type SortCol = 'nome' | 'canal' | 'sinal_pago_em' | 'saldo_a_pagar' | 'vencimento' | 'status_financeiro';
  const [sortCol, setSortCol] = useState<SortCol | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const sortBtn = (col: SortCol) => () => {
    if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortCol(col); setSortDir('asc'); }
  };

  // Busca adiada: digitar não trava a renderização da tabela.
  const dq = useDeferredValue(q);
  const visiveis = useMemo(() => {
    const statusRank = (s: string) => {
      const i = (STATUS_ORDEM as readonly string[]).indexOf(s);
      return i === -1 ? STATUS_ORDEM.length : i;
    };
    const lista = filtrar(contas, { ...filtros, termo: dq });
    if (!sortCol) return lista;
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...lista].sort((a, b) => {
      if (sortCol === 'nome') return dir * a.nome.localeCompare(b.nome, 'pt-BR');
      if (sortCol === 'canal') return dir * a.canal.localeCompare(b.canal, 'pt-BR');
      // Datas nulas sempre no fim, independente da direção.
      if (sortCol === 'sinal_pago_em') return dir * String(a.sinal_pago_em ?? '9999').localeCompare(String(b.sinal_pago_em ?? '9999'));
      if (sortCol === 'vencimento') return dir * String(a.vencimento ?? '9999').localeCompare(String(b.vencimento ?? '9999'));
      if (sortCol === 'saldo_a_pagar') return dir * ((a.saldo_a_pagar ?? -1) - (b.saldo_a_pagar ?? -1));
      return dir * (statusRank(a.status_financeiro) - statusRank(b.status_financeiro));
    });
  }, [contas, filtros, dq, sortCol, sortDir]);

  const temFiltro = filtros.status.length > 0 || filtros.canais.length > 0 || filtros.gaveta !== 'todos' || dq.trim().length > 0;
  const aberta = openId ? contas.find((c) => c.contato_hm_id === openId) ?? null : null;

  const [exportando, setExportando] = useState(false);
  const exportar = useCallback(async () => {
    setExportando(true);
    try {
      // Exporta exatamente o recorte visível: gaveta + filtros + busca + ordenação.
      const n = await exportarExcelFinanceiro(visiveis, turma, canVerDoc);
      flash(n ? `${n} ${n === 1 ? 'conta exportada' : 'contas exportadas'}.` : 'Nenhuma conta na lista para exportar.');
    } catch {
      flash('Não foi possível gerar a planilha.');
    } finally {
      setExportando(false);
    }
  }, [visiveis, turma, canVerDoc, flash]);

  const ofertasOrdenadas = useMemo(() => [...ofertas].sort((a, b) => (b.valor ?? 0) - (a.valor ?? 0)), [ofertas]);
  const turmaAtual = turmas.find((t) => t.turma === turma);

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">
          {tab === 'dashboard' ? (
            <>Dashboard <span className="text-[var(--accent)]">Financeiro</span></>
          ) : tab === 'contas' ? (
            <>
              Contas a <span className="text-[var(--accent)]">Receber</span>
              <span className="ml-2 align-middle text-xs font-semibold rounded-[var(--r-pill)] bg-[var(--accent-subtle)] text-[var(--accent)] px-2 py-0.5 tabular">{contas.length}</span>
            </>
          ) : tab === 'faturamento' ? (
            <>Faturamento <span className="text-[var(--accent)]">Diário</span></>
          ) : (
            <>Mapa de <span className="text-[var(--accent)]">Ofertas</span></>
          )}
        </h1>
        <div className="flex items-center gap-2">
          {tab === 'contas' && (
            <Button variant="ghost" size="sm" onClick={exportar} disabled={exportando || !visiveis.length} title="Exportar a lista visível (.xlsx)">
              <Icon name="download" size={14} /> {exportando ? 'Gerando…' : 'Exportar Excel'}
            </Button>
          )}
          <FilterSelect aria-label="Turma" value={turma ?? ''} onChange={(e) => setTurma(e.target.value || null)}>
            {!turmas.length && <option value="">Todas as turmas</option>}
            {turmas.map((t) => (
              <option key={t.turma} value={t.turma}>{t.turma}{t.atual ? ' (atual)' : ''} · {t.alunos} alunos</option>
            ))}
          </FilterSelect>
        </div>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">
        {tab === 'faturamento'
          ? 'Regime de caixa — o que entrou por dia de pagamento'
          : 'Sinal pago na Hotmart + saldo do pacote combinado com o financeiro'}
        {turmaAtual ? ` · turma ${turmaAtual.turma} (${turmaAtual.alunos} alunos)` : ''}
      </p>

      {tab === 'dashboard' ? (
        <FinanceiroDashboard
          contas={contas}
          loading={loading}
          onDrill={(g) => { setFiltros({ ...FILTROS_VAZIOS, gaveta: g }); setQ(''); irPara('#contas-a-receber'); }}
          onDrillStatus={(s) => { setFiltros({ ...FILTROS_VAZIOS, status: [s] }); setQ(''); irPara('#contas-a-receber'); }}
        />
      ) : tab === 'faturamento' ? (
        <FaturamentoDiario dias={dias} loading={loadingFat} turma={turma} />
      ) : tab === 'contas' ? (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-4" role="tablist" aria-label="Gavetas de contas">
            {GAVETAS.map((g) => (
              <QueueCard
                key={g.key}
                label={g.label}
                hint={gavetaHint[g.key]}
                icon={g.icon}
                tone={g.tone}
                value={counts[g.key]}
                active={filtros.gaveta === g.key}
                onClick={() => setFiltros((f) => ({ ...f, gaveta: g.key }))}
              />
            ))}
          </div>

          <Toolbar className="mb-3">
            <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome, e-mail, telefone, acordo…" />
            <MultiSelect
              values={filtros.status}
              onChange={(v) => setFiltros((f) => ({ ...f, status: v }))}
              placeholder="Todos os status"
              options={STATUS_ORDEM.map((s) => ({ value: s, label: statusLabel(s) }))}
            />
            <MultiSelect
              values={filtros.canais}
              onChange={(v) => setFiltros((f) => ({ ...f, canais: v }))}
              placeholder="Todos os canais"
              options={canalOpts.map((c) => ({ value: c, label: c }))}
            />
            {temFiltro && (
              <Button variant="ghost" size="sm" onClick={() => { setFiltros(FILTROS_VAZIOS); setQ(''); }}>Limpar</Button>
            )}
            <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{visiveis.length} de {contas.length}</span>
          </Toolbar>

          {/* Layout fixo: larguras definidas aqui; células truncam em vez de forçar scroll lateral. */}
          <DataTable fixed>
            <Thead>
              <Th sortable active={sortCol === 'nome'} dir={sortDir} onClick={sortBtn('nome')}>Aluno</Th>
              <Th sortable active={sortCol === 'canal'} dir={sortDir} onClick={sortBtn('canal')} className="w-[180px]">Canal</Th>
              <Th className="w-[105px]">Sinal</Th>
              <Th sortable active={sortCol === 'sinal_pago_em'} dir={sortDir} onClick={sortBtn('sinal_pago_em')} className="w-[95px]">Pago em</Th>
              <Th sortable active={sortCol === 'saldo_a_pagar'} dir={sortDir} onClick={sortBtn('saldo_a_pagar')} className="w-[115px]">Saldo a pagar</Th>
              <Th className="w-[115px]">Saldo pago</Th>
              <Th className="w-[95px]">Pago em (saldo)</Th>
              <Th sortable active={sortCol === 'vencimento'} dir={sortDir} onClick={sortBtn('vencimento')} className="w-[110px]">Vencimento</Th>
              <Th sortable active={sortCol === 'status_financeiro'} dir={sortDir} onClick={sortBtn('status_financeiro')} className="w-[150px]">Status</Th>
            </Thead>
            <tbody>
              {loading && !contas.length
                ? <SkeletonRows cols={[88, 64, 56, 72, 72, 56, 64, 88]} />
                : visiveis.map((c) => <LinhaConta key={c.contato_hm_id} c={c} onOpen={setOpenId} flash={flash} />)}
            </tbody>
          </DataTable>
          {!visiveis.length && !loading && (
            <EmptyState
              title={dq.trim() ? 'Nenhuma conta encontrada na busca' : 'Nenhuma conta nesta gaveta'}
              hint={dq.trim() ? 'Confira a grafia ou limpe a busca.' : 'Selecione outra gaveta acima para ver as demais.'}
              icon="wallet"
            />
          )}
        </>
      ) : (
        <SectionCard
          title="Ofertas de cobrança do saldo"
          subtitle="Ofertas Hotmart usadas para cobrar o saldo do pacote (o que resta depois do sinal de R$ 300). Copie o link da oferta combinada e envie ao aluno."
        >
          {!pronto ? (
            <Loading label="Carregando ofertas…" minHeight={160} />
          ) : !ofertasOrdenadas.length ? (
            <EmptyState title="Nenhuma oferta cadastrada" icon="banknote" />
          ) : (
            <DataTable>
              <Thead>
                <Th>Código</Th>
                <Th>Valor</Th>
                <Th>Tipo</Th>
                <Th>Usos</Th>
                <Th>Link</Th>
              </Thead>
              <tbody>
                {ofertasOrdenadas.map((o) => (
                  <Tr key={o.codigo}>
                    <Td>
                      <span className="font-semibold text-[var(--fg)] tabular">{o.codigo}</span>
                      {!o.ativo && <span className="ml-2 align-middle inline-flex"><Badge tone="danger">Inativa</Badge></span>}
                    </Td>
                    <Td className="tabular text-[var(--fg)]">{fmtBRL(o.valor)}</Td>
                    <Td><Badge tone={o.recorrente ? 'info' : 'neutral'}>{o.recorrente ? 'Recorrente' : 'À vista'}</Badge></Td>
                    <Td className="tabular text-[var(--fg-2)]">{o.usos}</Td>
                    <Td>
                      {o.link ? (
                        <Button size="sm" variant="ghost" onClick={() => { navigator.clipboard?.writeText(o.link); flash('Link copiado.'); }}>
                          <Icon name="copy" size={13} /> Copiar link
                        </Button>
                      ) : '—'}
                    </Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </SectionCard>
      )}

      {aberta && (
        <ContaDrawer conta={aberta} canEdit={canEdit} canVerDoc={canVerDoc} onClose={() => setOpenId(null)} act={act} />
      )}

      <Toast>{toast}</Toast>
    </div>
  );
}

/** Card-gaveta da fila: KPI clicável que filtra a tabela (mesma anatomia do piloto Placas). */
function QueueCard({ label, hint, icon, tone, value, active, onClick }: {
  label: string; hint: string; icon: string; tone: string; value: number; active: boolean; onClick: () => void;
}) {
  return (
    <button
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`text-left rounded-[var(--r-lg)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-3.5 border transition-colors ${active ? 'border-[var(--border-accent)]' : 'border-[var(--border)] hover:border-[var(--border-strong)]'}`}
      style={{ borderTopWidth: 2, borderTopColor: tone }}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-xl font-bold tabular leading-none text-[var(--fg)]">{value.toLocaleString('pt-BR')}</div>
          <div className={`mt-1.5 text-[10px] font-semibold uppercase tracking-wider ${active ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>{label}</div>
          <div className="mt-0.5 text-[10px] text-[var(--fg-3)] truncate">{hint}</div>
        </div>
        <span className="grid place-items-center w-7 h-7 rounded-[var(--r-md)] shrink-0" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}><Icon name={icon} size={15} /></span>
      </div>
    </button>
  );
}

/** Linha da fila — memoizada: digitar na busca não re-renderiza linhas que não mudaram. */
const LinhaConta = memo(function LinhaConta({ c, onOpen, flash }: {
  c: ContaReceber; onOpen: (id: string) => void; flash: (msg: string) => void;
}) {
  const vencido = c.status_financeiro === 'vencido';
  // stopPropagation: o clique de copiar não pode abrir o drawer da linha.
  const copiar = (e: React.MouseEvent, valor: string, oQue: string) => {
    e.stopPropagation();
    navigator.clipboard?.writeText(valor);
    flash(`${oQue} copiado.`);
  };
  return (
    <Tr onClick={() => onOpen(c.contato_hm_id)}>
      <Td>
        <div className="min-w-0">
          <div className="truncate text-[13px] font-medium text-[var(--fg)]">{c.nome || '—'}</div>
          <div className="text-[11px] text-[var(--fg-3)] flex items-center gap-2 min-w-0">
            <button type="button" title="Copiar e-mail" onClick={(e) => copiar(e, c.email, 'E-mail')} className="truncate hover:text-[var(--fg)] hover:underline transition-colors">{c.email}</button>
            {c.telefone && (
              <button type="button" title="Copiar telefone" onClick={(e) => copiar(e, c.telefone!, 'Telefone')} className="shrink-0 tabular hover:text-[var(--fg)] hover:underline transition-colors">{c.telefone}</button>
            )}
          </div>
        </div>
      </Td>
      <Td><span className="inline-flex whitespace-normal"><Badge tone="neutral">{c.canal}</Badge></span></Td>
      <Td className="overflow-hidden">
        <div className="text-[13px] tabular text-[var(--fg)]">{fmtBRL(c.sinal_bruto)}</div>
        <div className="text-[10px] tabular text-[var(--fg-3)]">líq. {fmtBRL(c.sinal_liquido)}</div>
      </Td>
      <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap">{fmtData(c.sinal_pago_em)}</Td>
      <Td className="overflow-hidden">
        <span className={`text-[13px] tabular ${vencido ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg)]'}`}>{fmtBRL(c.saldo_a_pagar)}</span>
      </Td>
      <Td className="overflow-hidden">
        {c.saldo_pago_bruto > 0 ? (
          <>
            <div className="text-[13px] tabular text-[var(--fg)]">
              {fmtBRL(c.saldo_pago_bruto)}
              {c.saldo_lancamentos > 1 && <span className="ml-1 text-[10px] font-semibold text-[var(--fg-3)]">{c.saldo_lancamentos}x</span>}
            </div>
            <div className="text-[10px] tabular text-[var(--fg-3)]">líq. {fmtBRL(c.saldo_pago_liquido)}</div>
          </>
        ) : (
          <span className="text-[var(--fg-3)]">—</span>
        )}
      </Td>
      <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap">{c.saldo_pago_em ? fmtData(c.saldo_pago_em) : '—'}</Td>
      <Td className="overflow-hidden">
        {c.vencimento ? (
          <>
            <div className="text-xs text-[var(--fg)] tabular whitespace-nowrap">{fmtData(c.vencimento)}</div>
            {(c.dias_atraso ?? 0) > 0 && <span className="text-[11px] text-[var(--red)] font-semibold">{c.dias_atraso}d em atraso</span>}
          </>
        ) : (
          <span className="text-xs text-[var(--fg-3)]">a combinar</span>
        )}
      </Td>
      <Td className="overflow-hidden"><Badge tone={statusTone(c.status_financeiro)} dot>{statusLabel(c.status_financeiro)}</Badge></Td>
    </Tr>
  );
});
