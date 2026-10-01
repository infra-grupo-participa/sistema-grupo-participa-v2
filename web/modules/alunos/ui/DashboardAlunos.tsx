'use client';

import { useEffect, useMemo, useState } from 'react';
import { applyDashFilters, computeAlunosMetrics, computeTurmaEspacoMatrix, type DashFiltros, type DashView, type Distribuicao } from '../domain/metrics';
import { distribuicaoNivel, distribuicaoSituacao, distribuicaoTurmas, ingressos12m, serieEntrada, type ColunaEntrada, type Fatia } from '../domain/dashboard-executivo';
import type { Aluno360 } from '../domain/aluno-360';
import { ESPACO_COLOR, ESPACO_LABEL, SITUACAO } from '../domain/aluno-360';
import { nivelNormalize } from '@/shared/domain/nivel-resultado';
import { Card, SectionTitle, Button, Input, Modal, MultiSelect, Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtData } from '@/shared/ui/format';
import { motivoSemVencimento, sitTone, turmaCombo } from './alunos-ui-shared';
import { InstrucaoBadge } from './alunos-ui-bits';

// Coage valor de filtro para array (visões salvas no formato antigo eram string única).
const asArr = (v: unknown): string[] => (Array.isArray(v) ? (v as string[]) : typeof v === 'string' && v ? [v] : []);
const normFiltros = (f: DashFiltros): DashFiltros => ({ espaco: asArr(f.espaco), estado: asArr(f.estado), turma: asArr(f.turma) });

const VIEWS_KEY = 'gp_dash_views';
const COR_NIVEL: Record<string, string> = {
  ouro: 'var(--nivel-ouro)', platina: 'var(--nivel-platina)', diamante: 'var(--nivel-diamante)', diamante_vermelho: 'var(--nivel-diamante-vermelho)', __none__: 'var(--fg-4)',
};
const COR_SITUACAO: Record<string, string> = { em_dia: 'var(--green)', a_vencer: 'var(--yellow)', vencido: 'var(--red)', acompanha_titular: 'var(--fg-3)', __none__: 'var(--fg-4)' };
const COR_THB = 'var(--accent)';
const COR_AURUM = 'var(--nivel-ouro)';
const fmtN = (n: number) => n.toLocaleString('pt-BR');
const hojeLocal = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

interface SavedView {
  name: string;
  view: DashView;
  filtros: DashFiltros;
}

export function DashboardAlunos({ alunos, onAbrirAluno }: { alunos: Aluno360[]; onAbrirAluno?: (id: string) => void }) {
  const [view, setView] = useState<DashView>('alunos');
  const [filtros, setFiltros] = useState<DashFiltros>({});
  const [views, setViews] = useState<SavedView[]>([]);
  /* Card clicado: abre a lista de quem está por trás do número. */
  const [detalhe, setDetalhe] = useState<{ titulo: string; pessoas: Aluno360[] } | null>(null);
  useEffect(() => {
    try {
      const raw = JSON.parse(localStorage.getItem(VIEWS_KEY) || '[]') as SavedView[];
      setViews(raw.map((v) => ({ ...v, filtros: normFiltros(v.filtros) }))); // eslint-disable-line react-hooks/set-state-in-effect
    } catch { /* ignore */ }
  }, []);

  const m = useMemo(() => computeAlunosMetrics(alunos, view, filtros), [alunos, view, filtros]);
  // Mesma base que alimenta os KPIs — o modal mostra exatamente quem está contado no card.
  const baseAtual = useMemo(() => applyDashFilters(alunos, view, filtros), [alunos, view, filtros]);
  const matrix = useMemo(() => computeTurmaEspacoMatrix(baseAtual), [baseAtual]);
  const hoje = useMemo(() => hojeLocal(), []);
  const exec = useMemo(() => ({
    thb: distribuicaoTurmas(baseAtual, 'turma_codigo', 20),
    aurum: distribuicaoTurmas(baseAtual, 'turma_aurum_codigo'),
    nivel: distribuicaoNivel(baseAtual),
    situacao: distribuicaoSituacao(baseAtual),
    serie: serieEntrada(baseAtual),
    ing: ingressos12m(baseAtual, hoje),
  }), [baseAtual, hoje]);
  const nSit = (k: string) => exec.situacao.find((f) => f.key === k)?.count ?? 0;

  const estados = useMemo(() => Array.from(new Set(alunos.map((a) => String(a.estado ?? '').toUpperCase()).filter(Boolean))).sort(), [alunos]);
  const turmas = useMemo(() => Array.from(new Set(alunos.map((a) => a.turma_codigo).filter(Boolean) as string[])).sort((a, b) => b.localeCompare(a, 'pt-BR', { numeric: true, sensitivity: 'base' })), [alunos]);
  const temFiltro = Boolean(filtros.espaco?.length || filtros.estado?.length || filtros.turma?.length || view === 'socios');

  const persistViews = (next: SavedView[]) => { setViews(next); localStorage.setItem(VIEWS_KEY, JSON.stringify(next)); };
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const salvarVisao = () => {
    const name = saveName.trim();
    if (!name) return;
    persistViews([...views.filter((v) => v.name !== name), { name, view, filtros }]);
    setSaveOpen(false);
    setSaveName('');
  };

  const set = (k: keyof DashFiltros, v: string[]) => setFiltros((f) => ({ ...f, [k]: v.length ? v : undefined }));

  const abrirCard = (label: string, pred?: (a: Aluno360) => boolean) =>
    setDetalhe({
      titulo: label,
      pessoas: (pred ? baseAtual.filter(pred) : baseAtual.slice())
        .sort((a, b) => (a.nome || '').localeCompare(b.nome || '', 'pt-BR')),
    });
  const sitDe = (k: string) => (a: Aluno360) => (a.situacao_acesso && SITUACAO[a.situacao_acesso] ? a.situacao_acesso : '__none__') === k;
  const varIng = exec.ing.anterior ? Math.round(((exec.ing.atual - exec.ing.anterior) / exec.ing.anterior) * 100) : null;

  return (
    <div>
      <div className="flex items-center justify-end mb-3">
        <span className="text-xs text-[var(--fg-3)] tabular">{m.total.toLocaleString('pt-BR')} registros</span>
      </div>

      <div className="flex flex-wrap gap-2 mb-3">
        <MultiSelect values={filtros.espaco || []} onChange={(v) => set('espaco', v)} placeholder="Todos os espaços" options={Object.entries(ESPACO_LABEL).map(([value, label]) => ({ value, label }))} />
        <MultiSelect values={filtros.turma || []} onChange={(v) => set('turma', v)} placeholder="Todas as turmas" options={turmas.map((t) => ({ value: t, label: t }))} />
        <MultiSelect values={filtros.estado || []} onChange={(v) => set('estado', v)} placeholder="Todos os estados" options={estados.map((e) => ({ value: e, label: e }))} />
        {temFiltro && <Button variant="ghost" size="sm" onClick={() => { setFiltros({}); setView('alunos'); }}>Limpar</Button>}
        <Button variant="subtle" size="sm" onClick={() => setSaveOpen(true)}><Icon name="star" size={13} /> Salvar visão</Button>
      </div>

      {saveOpen && (
        <Modal
          title="Salvar visão rápida"
          width="max-w-sm"
          onClose={() => setSaveOpen(false)}
          footer={
            <>
              <Button variant="ghost" size="sm" onClick={() => setSaveOpen(false)}>Cancelar</Button>
              <Button size="sm" onClick={salvarVisao} disabled={!saveName.trim()}>Salvar</Button>
            </>
          }
        >
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Nome da visão</span>
            <Input autoFocus value={saveName} onChange={(e) => setSaveName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && salvarVisao()} placeholder="Ex.: THB GO ativos" className="mt-1" />
          </label>
        </Modal>
      )}

      {views.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          {views.map((v) => (
            <span key={v.name} className="inline-flex items-center gap-1 rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-2)] pl-3 pr-1.5 py-1 text-xs">
              <button onClick={() => { setView(v.view); setFiltros(v.filtros); }} className="text-[var(--fg-2)] hover:text-[var(--accent)] font-medium">{v.name}</button>
              <button onClick={() => persistViews(views.filter((x) => x.name !== v.name))} aria-label={`Excluir visão ${v.name}`} className="text-[var(--fg-4)] hover:text-[var(--red)] inline-flex"><Icon name="x" size={12} /></button>
            </span>
          ))}
        </div>
      )}

      {/* Topo: 5 KPIs (valor + comparação + auxílio visual). Os 7 cards por espaço saíram — o espaço
          está nas barras logo abaixo, que abrem a mesma lista ao clicar. */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-5">
        <KpiExec label="Alunos no recorte" valor={m.total} i={0} cor="var(--accent)" onClick={() => abrirCard('Alunos no recorte')}
          comparacao={temFiltro ? `de ${fmtN(alunos.length)} na base · ${Math.round((m.total / Math.max(1, alunos.length)) * 100)}%` : `${fmtN(m.totalTitulares)} titulares · ${fmtN(m.totalSocios)} sócios`}
          visual={<Split partes={[{ n: m.totalTitulares, cor: 'var(--accent)' }, { n: m.totalSocios, cor: 'var(--nivel-diamante)' }]} />} />
        {(['em_dia', 'a_vencer', 'vencido'] as const).map((k, i) => (
          <KpiExec key={k} label={k === 'a_vencer' ? 'A vencer em 30 dias' : SITUACAO[k].label} valor={nSit(k)} i={i + 1} cor={COR_SITUACAO[k]}
            onClick={() => abrirCard(SITUACAO[k].label, sitDe(k))}
            comparacao={`${Math.round((nSit(k) / Math.max(1, m.total)) * 100)}% do recorte`}
            visual={<Split partes={[{ n: nSit(k), cor: COR_SITUACAO[k] }, { n: m.total - nSit(k), cor: 'transparent' }]} />} />
        ))}
        <KpiExec label="Ingressos em 12 meses" valor={exec.ing.atual} i={4} cor="var(--info)"
          comparacao={`${fmtN(exec.ing.anterior)} nos 12 anteriores${varIng != null ? ` · ${varIng > 0 ? '+' : ''}${varIng}%` : ''}`}
          visual={<MiniColunas valores={exec.ing.meses} />} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-5 gp-rise">
          <SectionTitle right={<LegendaTS />}>Por espaço de instrução</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Titulares × sócios. Clique na linha para ver as pessoas.</p>
          <Bars data={m.porEspaco} total={m.total} onClick={(d) => abrirCard(d.label, (a) => (a.espaco_instrucao || '__none__') === d.key)} />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '60ms' }}>
          <SectionTitle>Por situação de acesso</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">% sobre o recorte. A vencer = vence nos próximos 30 dias.</p>
          <BarrasH fatias={exec.situacao} cor={(k) => COR_SITUACAO[k]} onClick={(f) => abrirCard(f.label, sitDe(f.key))} />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '120ms' }}>
          <SectionTitle>Por turma</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">
            Mais recente primeiro; % sobre quem tem turma{exec.thb.semTurma > 0 && <> · {fmtN(exec.thb.semTurma)} sem turma THB</>}.
          </p>
          {exec.thb.fatias.length > 0 && <SubRotulo cor={COR_THB}>THB · {fmtN(exec.thb.comTurma)}</SubRotulo>}
          <BarrasH fatias={exec.thb.fatias} cor={() => COR_THB} onClick={(f) => abrirCard(`Turma ${f.label}`, (a) => a.turma_codigo === f.key)} />
          {exec.aurum.fatias.length > 0 && (
            <>
              <SubRotulo cor={COR_AURUM}>Aurum · {fmtN(exec.aurum.comTurma)}</SubRotulo>
              <BarrasH fatias={exec.aurum.fatias} cor={() => COR_AURUM} onClick={(f) => abrirCard(`Turma Aurum ${f.label}`, (a) => a.turma_aurum_codigo === f.key)} />
            </>
          )}
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '180ms' }}>
          <SectionTitle>Por nível de resultado</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Na ordem da escala; % sobre o recorte.</p>
          <BarrasH fatias={exec.nivel} cor={(k) => COR_NIVEL[k] || 'var(--nivel-base)'} onClick={(f) => abrirCard(f.label, (a) => (nivelNormalize(a.nivel_resultado) ?? '__none__') === f.key)} />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '240ms' }}>
          <SectionTitle>Jornada no programa</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Nº de alunos do recorte que atingiram cada marco.</p>
          <Bars
            data={[
              { key: 'placa', label: 'Com placa', count: m.placa, color: 'var(--nivel-ouro)' },
              { key: 'dep', label: 'Com depoimento', count: m.depoimento, color: 'var(--green)' },
              { key: 'sip', label: 'Com SIP (Time Holding Brasil)', count: m.sip, color: 'var(--nivel-diamante-vermelho)' },
            ]}
            total={m.total}
          />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '300ms' }}>
          <SectionTitle right={<LegendaTS />}>Top estados</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">
            Os {m.porEstado.length} estados com mais alunos, de {m.totalEstados} no total. Passe o mouse para ver titulares × sócios.
          </p>
          <Bars data={m.porEstado} total={m.total} />
        </Card>
        {exec.serie.colunas.length > 0 && (
          <Card className="p-5 lg:col-span-2 gp-rise">
            <SectionTitle right={<LegendaEspacos itens={[...m.espacoKpi, { key: '__outros__', label: 'Outros', color: 'var(--fg-4)', total: exec.serie.colunas.some((c) => c.segs.some((s) => s.key === '__outros__')) ? 1 : 0 }]} />}>Linha do tempo de entrada no THB</SectionTitle>
            <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">
              Ingressos por {exec.serie.granularidade === 'mes' ? 'mês' : 'ano'} pela data da compra, empilhados por espaço de instrução
              {exec.serie.granularidade === 'ano' && ' (o recorte passa de 36 meses; filtre para ver por mês)'}.
            </p>
            <StackedColumn data={exec.serie.colunas} mensal={exec.serie.granularidade === 'mes'} />
          </Card>
        )}
        {matrix.turmas.length > 0 && (
          <Card className="p-5 lg:col-span-2 gp-rise">
            <SectionTitle>Matriz turma × espaço de instrução</SectionTitle>
            <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">
              Turma do THB (T40 → T1) × espaço. {matrix.turmas.length} turmas
              {m.semTurma > 0 && <> · {m.semTurma} {m.semTurma === 1 ? 'pessoa sem turma fica de fora' : 'pessoas sem turma ficam de fora'}</>}.
            </p>
            <div className="max-h-[420px] overflow-auto">
              <Matrix matrix={matrix} />
            </div>
          </Card>
        )}
      </div>

      {detalhe && (
        <Modal
          title={`${detalhe.titulo} · ${detalhe.pessoas.length.toLocaleString('pt-BR')} ${detalhe.pessoas.length === 1 ? 'pessoa' : 'pessoas'}`}
          width="max-w-5xl"
          onClose={() => setDetalhe(null)}
          footer={<Button variant="ghost" size="sm" onClick={() => setDetalhe(null)}>Fechar</Button>}
        >
          <ListaDoCard pessoas={detalhe.pessoas} onAbrirAluno={onAbrirAluno ? (id) => { setDetalhe(null); onAbrirAluno(id); } : undefined} />
        </Modal>
      )}
    </div>
  );
}

/** Lista de quem está por trás do número do card. Mesmas colunas da aba "Lista de alunos". */
function ListaDoCard({ pessoas, onAbrirAluno }: { pessoas: Aluno360[]; onAbrirAluno?: (id: string) => void }) {
  const [busca, setBusca] = useState('');
  const filtradas = useMemo(() => {
    const q = busca.trim().toLowerCase();
    if (!q) return pessoas;
    return pessoas.filter((a) =>
      // `socio_de_nome` entra na busca para achar todos os sócios de um titular pelo nome dele.
      [a.nome, a.email, a.turma_codigo, a.turma_aurum_codigo, a.cidade, a.estado, a.profissao, a.instrucao, a.socio_de_nome]
        .filter(Boolean).join(' ').toLowerCase().includes(q),
    );
  }, [pessoas, busca]);
  const LIMITE = 300;
  if (!pessoas.length) return <EmptyState title="Nenhuma pessoa neste recorte" icon="users" />;
  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
        <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Filtrar por nome, e-mail, turma, cidade…" className="max-w-xs" />
        <span className="text-xs text-[var(--fg-3)] tabular">
          {filtradas.length.toLocaleString('pt-BR')} de {pessoas.length.toLocaleString('pt-BR')}
        </span>
      </div>
      <DataTable>
        <Thead>
          <Th>Aluno</Th>
          <Th>Nível</Th>
          <Th>Profissão</Th>
          <Th>Instrução</Th>
          <Th>Turma</Th>
          <Th>Vencimento</Th>
        </Thead>
        <tbody>
          {filtradas.slice(0, LIMITE).map((a) => {
            const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
            return (
              <Tr key={a.id} onClick={onAbrirAluno ? () => onAbrirAluno(a.id) : undefined}>
                <Td>
                  <div className="text-[var(--fg)] font-medium">{a.nome || '—'}</div>
                  {a.email && <div className="text-xs text-[var(--fg-3)] truncate">{a.email}</div>}
                </Td>
                <Td><NivelBadge nivel={a.nivel_resultado} /></Td>
                <Td className="text-[var(--fg-2)]">{a.profissao || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td>
                  {/* Espaço mostrava só o grupo: mil pessoas como "Holding Masters", sem
                      separar titular de sócio. A instrução responde as duas coisas. */}
                  <InstrucaoBadge a={a} />
                  {a.eh_socio && a.socio_de_nome && (
                    <div className="text-[11px] text-[var(--fg-3)] mt-0.5 truncate max-w-[190px]" title={`Sócio de ${a.socio_de_nome}`}>
                      de {a.socio_de_nome}
                    </div>
                  )}
                </Td>
                <Td className="text-[var(--fg-2)] whitespace-nowrap">{turmaCombo(a) || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="whitespace-nowrap">
                  {/* Sem data, o status ainda tem de aparecer: sócio herda o prazo do
                      titular e a base pré-Hotmart nunca teve ano — nos dois casos o
                      badge é a única resposta para "está em dia ou vencido?". */}
                  <div>
                    {a.data_expiracao
                      ? <span className="text-[var(--fg-2)]">{fmtData(a.data_expiracao)}</span>
                      : <span className="text-[var(--fg-3)]">{motivoSemVencimento(a) || '—'}</span>}
                    {sit
                      ? <div className="mt-0.5"><Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge></div>
                      : a.status_acesso_central && <div className="mt-0.5"><Badge tone="neutral" dot>{a.status_acesso_central}</Badge></div>}
                  </div>
                </Td>
              </Tr>
            );
          })}
        </tbody>
      </DataTable>
      {filtradas.length > LIMITE && (
        <p className="text-xs text-[var(--fg-3)] mt-2">Exibindo {LIMITE} de {filtradas.length.toLocaleString('pt-BR')}. Use o filtro acima para refinar.</p>
      )}
    </div>
  );
}

function Bars({ data, total, onClick }: { data: Distribuicao[]; total: number; onClick?: (d: Distribuicao) => void }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  if (!data.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  return (
    <div className="space-y-2.5">
      {data.map((d) => (
        <Linha key={d.key} onClick={onClick ? () => onClick(d) : undefined} title={d.titulares != null ? `${d.titulares} titulares · ${d.socios} sócios` : undefined}>
          <div className="flex justify-between text-xs mb-1">
            <span className="text-[var(--fg-2)]">{d.label}</span>
            <span className="text-[var(--fg-3)] tabular">{d.count.toLocaleString('pt-BR')}{total ? <span className="text-[var(--fg-4)]"> · {Math.round((d.count / total) * 100)}%</span> : null}</span>
          </div>
          <div className="h-2 rounded-full bg-[var(--surface-3)] overflow-hidden flex">
            {d.titulares != null ? (
              <>
                <div className="h-full transition-[width] duration-500" style={{ width: `${(d.titulares / max) * 100}%`, background: 'var(--accent)' }} />
                <div className="h-full transition-[width] duration-500" style={{ width: `${((d.socios ?? 0) / max) * 100}%`, background: 'var(--nivel-diamante)' }} />
              </>
            ) : (
              <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${(d.count / max) * 100}%`, background: d.color || 'var(--accent)' }} />
            )}
          </div>
        </Linha>
      ))}
    </div>
  );
}

/** Linha de distribuição: vira botão quando abre a lista de pessoas (número clicável só se parecer clicável). */
function Linha({ onClick, title, children }: { onClick?: () => void; title?: string; children: React.ReactNode }) {
  if (!onClick) return <div title={title}>{children}</div>;
  return (
    <button type="button" onClick={onClick} title={title} className="block w-full text-left rounded-[var(--r-sm)] -mx-1 px-1 py-0.5 hover:bg-[var(--surface-3)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
      {children}
    </button>
  );
}

/** Barras horizontais: rótulo · contagem · %, barra proporcional ao maior valor. */
function BarrasH({ fatias, cor, onClick }: { fatias: Fatia[]; cor: (key: string) => string; onClick?: (f: Fatia) => void }) {
  if (!fatias.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  const max = Math.max(1, ...fatias.map((f) => f.count));
  return (
    <div className="space-y-1">
      {fatias.map((f) => (
        <Linha key={f.key} onClick={onClick && f.key !== '__outras__' ? () => onClick(f) : undefined}>
          <div className="grid grid-cols-[minmax(4.5rem,9rem)_minmax(0,1fr)_auto] items-center gap-2 text-xs">
            <span className="text-[var(--fg-2)] truncate" title={f.label}>{f.label}</span>
            <span className="h-2 rounded-[var(--r-pill)] bg-[var(--surface-3)] overflow-hidden">
              <span className="block h-full rounded-[var(--r-pill)]" style={{ width: `${(f.count / max) * 100}%`, background: cor(f.key) }} />
            </span>
            <span className="tabular text-[var(--fg-3)] text-right min-w-[4.5rem]">{fmtN(f.count)} <span className="text-[var(--fg-4)]">· {f.pct}%</span></span>
          </div>
        </Linha>
      ))}
    </div>
  );
}

function SubRotulo({ cor, children }: { cor: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-1.5 mt-2 mb-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">
      <span className="w-2 h-2 rounded-full" style={{ background: cor }} />{children}
    </div>
  );
}

function Matrix({ matrix }: { matrix: ReturnType<typeof computeTurmaEspacoMatrix> }) {
  return (
    <table className="text-sm border-collapse min-w-full">
      <thead className="sticky top-0 z-10 bg-[var(--surface-1)]">
        <tr>
          <th className="text-left px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)] sticky left-0 bg-[var(--surface-1)]">Turma</th>
          {matrix.colunas.map((col) => (
            <th key={col.key} className="px-2 py-1.5 text-center">
              <span className="inline-flex items-center gap-1 text-[10px] text-[var(--fg-3)] whitespace-nowrap"><span className="w-2 h-2 rounded-full" style={{ background: col.color }} />{col.label}</span>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {matrix.turmas.map((t) => (
          <tr key={t} className="border-t border-[var(--border-faint)]">
            <td className="px-2 py-1.5 font-medium text-[var(--fg)] whitespace-nowrap sticky left-0 bg-[var(--surface-1)]">{t}</td>
            {matrix.colunas.map((col) => {
              const c = matrix.cells[t][col.key];
              const intensity = matrix.max ? c / matrix.max : 0;
              return (
                <td key={col.key} className="px-2 py-1.5 text-center tabular" style={{ background: c ? `color-mix(in srgb, ${col.color} ${Math.round(8 + intensity * 55)}%, transparent)` : 'transparent', color: c ? 'var(--fg)' : 'var(--fg-4)' }}>
                  {c || '·'}
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function KpiExec({ label, valor, comparacao, visual, cor, i = 0, onClick }: {
  label: string; valor: number; comparacao: string; visual: React.ReactNode; cor: string; i?: number; onClick?: () => void;
}) {
  const conteudo = (
    <>
      <div className="flex items-center gap-1.5">
        <span className="text-[11px] font-medium uppercase tracking-wide text-[var(--fg-3)] leading-tight break-words min-w-0">{label}</span>
        {onClick && <Icon name="chevron-right" size={12} className="shrink-0 text-[var(--fg-4)]" />}
      </div>
      <div className="mt-1 text-2xl font-bold tabular leading-none text-[var(--fg)]">{fmtN(valor)}</div>
      <div className="mt-1 text-[11px] tabular text-[var(--fg-3)] truncate" title={comparacao}>{comparacao}</div>
      <div className="mt-2">{visual}</div>
    </>
  );
  const estilo = { borderTop: `2px solid ${cor}`, animationDelay: `${i * 45}ms` } as React.CSSProperties;
  if (!onClick) return <Card className="p-4 min-w-0 overflow-hidden gp-rise" style={estilo}>{conteudo}</Card>;
  return (
    <Card className="p-0 min-w-0 overflow-hidden gp-rise" style={estilo}>
      <button
        type="button"
        onClick={onClick}
        title={`Ver os ${fmtN(valor)} de ${label}`}
        className="w-full text-left p-4 transition-colors hover:bg-[var(--surface-3)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]"
      >
        {conteudo}
      </button>
    </Card>
  );
}

/** Barra fina 100% dividida entre as partes (aria-hidden: o número e a comparação já dizem). */
function Split({ partes }: { partes: { n: number; cor: string }[] }) {
  const t = Math.max(1, partes.reduce((s, p) => s + p.n, 0));
  return (
    <div className="h-1.5 rounded-[var(--r-pill)] bg-[var(--surface-3)] overflow-hidden flex" aria-hidden>
      {partes.map((p, k) => <div key={k} className="h-full" style={{ width: `${(p.n / t) * 100}%`, background: p.cor }} />)}
    </div>
  );
}

/** 12 colunas mínimas, mês mais antigo à esquerda. */
function MiniColunas({ valores }: { valores: number[] }) {
  const max = Math.max(1, ...valores);
  return (
    <div className="flex items-end gap-px h-4" aria-hidden>
      {valores.map((v, k) => <div key={k} className="flex-1 rounded-t-[1px]" style={{ height: `${Math.max(8, (v / max) * 100)}%`, background: v ? 'var(--info)' : 'var(--surface-3)' }} />)}
    </div>
  );
}

function LegendaTS() {
  return (
    <span className="flex items-center gap-3 text-[10px] text-[var(--fg-3)]">
      <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--accent)' }} /> Titulares</span>
      <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--nivel-diamante)' }} /> Sócios</span>
    </span>
  );
}

function LegendaEspacos({ itens }: { itens: { key: string; label: string; color: string; total: number }[] }) {
  return (
    <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-[var(--fg-3)]">
      {itens.filter((e) => e.total !== 0).map((e) => (
        <span key={e.key} className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: e.color }} /> {e.label}</span>
      ))}
    </span>
  );
}

function StackedColumn({ data, mensal }: { data: ColunaEntrada[]; mensal: boolean }) {
  const max = Math.max(1, ...data.map((d) => d.total));
  const denso = data.length > 16;
  const nomeSeg = (k: string) => ESPACO_LABEL[k] || 'Outros';
  return (
    <div className={`flex items-end h-44 pt-2 overflow-hidden ${denso ? 'gap-px sm:gap-0.5' : 'gap-2'}`} role="list" aria-label="Ingressos por período">
      {data.map((d) => {
        const desc = `${d.rotuloLongo}: ${d.total} ${d.total === 1 ? 'ingresso' : 'ingressos'}${d.segs.length ? ` (${d.segs.map((s) => `${nomeSeg(s.key)} ${s.count}`).join(', ')})` : ''}`;
        // Mensal: rótulo em jan (com o ano) e a cada trimestre; no celular só janeiro e julho. O rótulo nasce na
        // borda esquerda da coluna e transborda para a direita (colunas sem rótulo); o gráfico corta o excesso.
        const rotulo = !mensal ? d.rotulo : d.marco === 'ano' ? d.rotulo : d.marco === 'trimestre' ? d.rotulo.slice(0, 3) : '';
        const soDesktop = mensal && d.marco === 'trimestre' && !d.rotulo.startsWith('jul');
        return (
          // h-full: sem altura definida na coluna, o height em % da barra resolve para 0 e só sobra o minHeight
          <div key={d.key} role="listitem" aria-label={desc} title={desc} className="flex-1 min-w-0 h-full flex flex-col items-center gap-1">
            <div className="flex-1 w-full flex flex-col justify-end items-center gap-1">
              {!denso && <span className="text-[10px] text-[var(--fg-3)] tabular">{d.total}</span>}
              <div className="w-full rounded-t overflow-hidden flex flex-col-reverse" style={{ height: `${(d.total / max) * 85}%`, minHeight: d.total ? 2 : 0 }}>
                {d.segs.map((s) => <div key={s.key} style={{ height: `${(s.count / d.total) * 100}%`, background: ESPACO_COLOR[s.key] || 'var(--fg-4)' }} />)}
              </div>
            </div>
            <span className={`${mensal ? 'self-start' : ''} h-3 text-[10px] leading-3 tabular whitespace-nowrap ${d.marco === 'ano' ? 'text-[var(--fg-2)] font-medium' : 'text-[var(--fg-3)]'} ${soDesktop ? 'hidden sm:inline' : ''}`} aria-hidden>{rotulo}</span>
          </div>
        );
      })}
    </div>
  );
}
