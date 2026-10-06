'use client';

// Aba "Dashboards" de Relatórios: vários dashboards por pessoa (meus + compartilhados), montados arrastando
// métricas para uma grade de 12 colunas. Conteúdo de aba: quem pluga cuida da página (PaginaComercial).
import { useEffect, useMemo, useState } from 'react';
import { Badge, Button, Card, ConfirmDialog, Skeleton, Toast, useFlash } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Dashboard } from '../../domain/types';
import { Chip, combinarDados, EstadoErro, NotaRodape, useEquipe, Vazio } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import type { DadosPainel } from '../inicio/metricas-painel';
import { avisarMudanca, repo, useAgora, useDados } from '../repositorio';
import { Construtor } from './Construtor';
import { GradeDash } from './GradeDash';
import {
  dashboardNovo, MODELOS, nomeDeCopia, podeEditarDashboard, renovarIds, separarDashboards, widgetsDoModelo, type ModeloKey, type WidgetDash,
} from './layout';
import { ModalDashboard, type FormDashboard } from './ModalDashboard';

const CHAVE_SEL = 'gp_comercial_dashboard_sel';

const INFO_DASHBOARDS: TextoIndicador = {
  nome: 'Dashboards',
  oQueE: 'Telas de números montadas por você, com as mesmas métricas do Comercial (mesma definição em todas as telas).',
  comoConta: 'Cada widget calcula a métrica no período escolhido, com filtro opcional por funil e por vendedor. O vendedor vê sempre os próprios números.',
  paraQue: 'Acompanhar o que importa para você sem montar planilha. Compartilhe com o time para todos olharem o mesmo número.',
};

function lerSel(): string | null {
  try { return typeof window === 'undefined' ? null : window.localStorage.getItem(CHAVE_SEL); } catch { return null; }
}
function gravarSel(id: string | null) {
  try { if (id) window.localStorage.setItem(CHAVE_SEL, id); else window.localStorage.removeItem(CHAVE_SEL); } catch { /* sem armazenamento: só não lembra */ }
}

type ModalAberto = { modo: 'novo'; inicial: FormDashboard } | { modo: 'renomear'; inicial: FormDashboard } | null;

export function DashboardsRelatorios() {
  const { sessao, vendedores, nomeDe, gestor } = useEquipe();
  const dashQ = useDados(() => repo.dashboards());
  const negQ = useDados(() => repo.negocios());
  const atvQ = useDados(() => repo.atividades());
  const evtQ = useDados(() => repo.eventos());
  const funQ = useDados(() => repo.funis());
  const motQ = useDados(() => repo.motivosPerda());
  const base = combinarDados(negQ, atvQ, evtQ, funQ, motQ);
  const agora = useAgora(60_000);
  const { toast, flash } = useFlash();

  const [selId, setSelId] = useState<string | null>(lerSel);
  const [editando, setEditando] = useState(false);
  const [modal, setModal] = useState<ModalAberto>(null);
  const [excluir, setExcluir] = useState(false);
  const [salvando, setSalvando] = useState(false);

  const lista = dashQ.dados;
  const euId = sessao?.vendedorId ?? null;
  const { meus, compartilhados } = useMemo(() => separarDashboards(lista ?? [], euId), [lista, euId]);
  const dash: Dashboard | null = lista ? lista.find((d) => d.id === selId) ?? meus[0] ?? compartilhados[0] ?? null : null;
  const podeEditar = dash ? podeEditarDashboard(dash, sessao) : false;

  useEffect(() => { if (dash) gravarSel(dash.id); }, [dash]);

  // Dados de cada widget: o gestor filtra por vendedor; o vendedor vê sempre os próprios números.
  const [negocios, atividades, eventos, funis, motivos] = base.dados ?? [];
  const dadosPara = useMemo(() => {
    if (!negocios || !atividades || !eventos || !funis || !motivos || !sessao) return null;
    const cache = new Map<string, DadosPainel>();
    return (vendedorId: string | null | undefined): DadosPainel => {
      const donoId = gestor ? vendedorId ?? null : sessao.vendedorId;
      const k = donoId ?? '';
      let d = cache.get(k);
      if (!d) {
        d = { negocios, atividades, eventos, funis, motivos, vendedores, agora, donoId };
        cache.set(k, d);
      }
      return d;
    };
  }, [negocios, atividades, eventos, funis, motivos, vendedores, agora, gestor, sessao]);

  const selecionar = (id: string) => { if (!editando) setSelId(id); };

  const salvarModal = async (f: FormDashboard) => {
    if (!modal || !sessao) return;
    setSalvando(true);
    try {
      if (modal.modo === 'novo') {
        const widgets: WidgetDash[] = f.modelo ? widgetsDoModelo(f.modelo, `m-${Date.now().toString(36)}`) : [];
        const r = await repo.salvarDashboard(dashboardNovo({ ...f, donoId: sessao.vendedorId, widgets, agora: new Date().toISOString() }));
        flash(r.msg ?? (r.ok ? 'Dashboard criado.' : 'Não foi possível criar.'));
        if (!r.ok) return;
        await dashQ.recarregar();
        avisarMudanca();
        if (r.dashboardId) setSelId(r.dashboardId);
        setModal(null);
        // Em branco: já abre a grade para arrastar.
        if (!f.modelo) setEditando(true);
      } else if (dash) {
        const r = await repo.salvarDashboard({ ...dash, nome: f.nome, descricao: f.descricao || null, compartilhado: f.compartilhado });
        flash(r.msg ?? (r.ok ? 'Dashboard salvo.' : 'Não foi possível salvar.'));
        if (!r.ok) return;
        avisarMudanca();
        setModal(null);
      }
    } catch (e) {
      flash(e instanceof Error ? e.message : 'Não foi possível salvar.');
    } finally {
      setSalvando(false);
    }
  };

  const duplicar = async () => {
    if (!dash || !sessao) return;
    const nome = nomeDeCopia(dash.nome, (lista ?? []).map((d) => d.nome));
    const r = await repo.salvarDashboard({
      ...dash, id: '', nome, donoId: sessao.vendedorId, compartilhado: false,
      widgets: renovarIds(dash.widgets as WidgetDash[], `c-${Date.now().toString(36)}`),
    });
    flash(r.ok ? `Criado "${nome}".` : r.msg ?? 'Não foi possível duplicar.');
    if (!r.ok) return;
    await dashQ.recarregar();
    avisarMudanca();
    if (r.dashboardId) setSelId(r.dashboardId);
  };

  const confirmarExcluir = async () => {
    if (!dash) return;
    setExcluir(false);
    const r = await repo.excluirDashboard(dash.id);
    flash(r.msg ?? (r.ok ? 'Dashboard excluído.' : 'Não foi possível excluir.'));
    if (r.ok) { setSelId(null); avisarMudanca(); }
  };

  const abrirNovo = (modelo: ModeloKey | null = null) => {
    const m = MODELOS.find((x) => x.key === modelo);
    setModal({ modo: 'novo', inicial: { nome: m?.nome ?? '', descricao: m?.descricao ?? '', compartilhado: false, modelo } });
  };

  const carregando = !lista || !dadosPara;
  const erro = dashQ.erro ?? base.erro;

  return (
    <section aria-label="Dashboards" className="min-w-0 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="inline-flex items-center gap-1 text-base font-bold text-[var(--fg)]">
          Dashboards <InfoIndicador texto={INFO_DASHBOARDS} />
        </h2>
        {!editando && lista && lista.length > 0 && (
          <Button size="sm" variant="ghost" onClick={() => abrirNovo()}><Icon name="plus" size={14} /> Novo dashboard</Button>
        )}
      </div>

      {erro && carregando ? (
        <Card><EstadoErro mensagem={erro} onTentar={() => { void dashQ.recarregar(); base.onTentar(); }} /></Card>
      ) : carregando ? (
        <Esqueleto />
      ) : !dash ? (
        <ComecarDoZero onNovo={abrirNovo} />
      ) : (
        <>
          {!editando && (
            <SeletorDashboards meus={meus} compartilhados={compartilhados} atual={dash.id} nomeDe={nomeDe} onSelecionar={selecionar} />
          )}

          {editando && podeEditar ? (
            <Construtor
              key={dash.id} dash={dash} dadosPara={dadosPara} funis={funis ?? []} vendedores={vendedores} gestor={gestor}
              nomeDe={nomeDe} flash={flash} onSair={() => setEditando(false)}
            />
          ) : (
            <>
              <CabecalhoDashboard
                dash={dash} podeEditar={podeEditar} euId={euId} nomeDe={nomeDe}
                onEditar={() => setEditando(true)}
                onRenomear={() => setModal({ modo: 'renomear', inicial: { nome: dash.nome, descricao: dash.descricao ?? '', compartilhado: dash.compartilhado, modelo: null } })}
                onDuplicar={duplicar}
                onExcluir={() => setExcluir(true)}
              />
              {dash.widgets.length ? (
                <GradeDash widgets={dash.widgets as WidgetDash[]} dadosPara={dadosPara} funis={funis ?? []} nomeDe={nomeDe} />
              ) : (
                <Card>
                  <Vazio
                    icone="dashboard"
                    titulo="Dashboard vazio"
                    hint={podeEditar ? 'Entre em edição e arraste as métricas da biblioteca para a grade.' : 'Quem criou ainda não colocou nenhum widget.'}
                    acao={podeEditar && <Button size="sm" onClick={() => setEditando(true)}><Icon name="pencil" size={14} /> Montar dashboard</Button>}
                  />
                </Card>
              )}
              {!gestor && <NotaRodape>Os widgets mostram os seus números. O filtro por vendedor vale para o gestor.</NotaRodape>}
            </>
          )}
        </>
      )}

      {modal && (
        <ModalDashboard modo={modal.modo} inicial={modal.inicial} salvando={salvando} onCancelar={() => setModal(null)} onSalvar={salvarModal} />
      )}
      <ConfirmDialog
        open={excluir && !!dash}
        title="Excluir dashboard?"
        message={<>&ldquo;{dash?.nome}&rdquo; some para você{dash?.compartilhado ? ' e para o time' : ''}. Os números não mudam: só a tela montada é apagada.</>}
        confirmLabel="Excluir" danger
        onCancel={() => setExcluir(false)}
        onConfirm={confirmarExcluir}
      />
      <Toast>{toast}</Toast>
    </section>
  );
}

function SeletorDashboards({ meus, compartilhados, atual, nomeDe, onSelecionar }: {
  meus: Dashboard[]; compartilhados: Dashboard[]; atual: string; nomeDe: (id: string | null) => string; onSelecionar: (id: string) => void;
}) {
  const grupo = (rotulo: string, itens: Dashboard[], dono: boolean) => itens.length > 0 && (
    <div role="group" aria-label={rotulo} className="flex flex-wrap items-center gap-2">
      <span className="w-full text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] sm:w-auto sm:mr-1">{rotulo}</span>
      {itens.map((d) => (
        <Chip key={d.id} ativo={d.id === atual} onClick={() => onSelecionar(d.id)} icone={d.compartilhado ? 'users' : 'dashboard'}
          title={dono ? `De ${nomeDe(d.donoId)}` : d.compartilhado ? 'Compartilhado com o time' : 'Só você vê'}>
          <span className="max-w-[220px] truncate">{d.nome}</span>
        </Chip>
      ))}
    </div>
  );
  return (
    <nav aria-label="Escolher dashboard" className="space-y-2">
      {grupo('Meus', meus, false)}
      {grupo('Compartilhados comigo', compartilhados, true)}
    </nav>
  );
}

function CabecalhoDashboard({ dash, podeEditar, euId, nomeDe, onEditar, onRenomear, onDuplicar, onExcluir }: {
  dash: Dashboard; podeEditar: boolean; euId: string | null; nomeDe: (id: string | null) => string;
  onEditar: () => void; onRenomear: () => void; onDuplicar: () => void; onExcluir: () => void;
}) {
  const atualizado = dash.atualizadoEm
    ? new Date(dash.atualizadoEm).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
    : null;
  const meu = dash.donoId === euId;
  return (
    <div className="flex flex-wrap items-start justify-between gap-3 border-b border-[var(--border-faint)] pb-3">
      <div className="min-w-0">
        <h3 className="flex flex-wrap items-center gap-2 text-lg font-bold text-[var(--fg)]">
          <span className="min-w-0 break-words">{dash.nome}</span>
          {dash.compartilhado ? <Badge tone="info">Compartilhado</Badge> : <Badge>Só você</Badge>}
        </h3>
        {dash.descricao && <p className="mt-0.5 text-sm text-[var(--fg-2)]">{dash.descricao}</p>}
        <p className="mt-1 text-[11px] text-[var(--fg-3)]">
          {meu ? 'Criado por você' : `Criado por ${nomeDe(dash.donoId)}`}
          {atualizado ? ` · atualizado em ${atualizado}` : ''}
          {` · ${dash.widgets.length} ${dash.widgets.length === 1 ? 'widget' : 'widgets'}`}
          {!podeEditar ? ' · só o dono e o gestor editam; duplique para ter a sua versão' : ''}
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {podeEditar && <Button size="sm" variant="ghost" onClick={onRenomear}><Icon name="pen" size={14} /> Renomear</Button>}
        <Button size="sm" variant="ghost" onClick={onDuplicar}><Icon name="copy" size={14} /> Duplicar</Button>
        {podeEditar && <Button size="sm" variant="danger" onClick={onExcluir}><Icon name="trash" size={14} /> Excluir</Button>}
        {podeEditar && <Button size="sm" onClick={onEditar}><Icon name="sliders" size={14} /> Editar dashboard</Button>}
      </div>
    </div>
  );
}

/** Nenhum dashboard ainda: convite com os modelos prontos. */
function ComecarDoZero({ onNovo }: { onNovo: (m?: ModeloKey | null) => void }) {
  return (
    <Card className="p-5">
      <div className="mx-auto max-w-3xl text-center">
        <Icon name="dashboard" size={28} className="mx-auto text-[var(--fg-3)]" />
        <p className="mt-2 text-base font-bold text-[var(--fg)]">Monte o seu primeiro dashboard</p>
        <p className="mt-1 text-sm text-[var(--fg-2)]">Comece por um modelo pronto e ajuste arrastando, ou parta de uma grade vazia.</p>
      </div>
      <ul className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {MODELOS.map((m) => (
          <li key={m.key} className="min-w-0">
            <button
              type="button" onClick={() => onNovo(m.key)}
              className="flex h-full w-full flex-col items-start gap-2 rounded-[var(--r-md)] border border-[var(--border)] p-3 text-left transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]"
            >
              <span className="grid w-8 h-8 place-items-center rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name={m.icone} size={15} /></span>
              <span className="text-sm font-semibold text-[var(--fg)]">{m.nome}</span>
              <span className="text-[11px] leading-relaxed text-[var(--fg-3)]">{m.descricao}</span>
              <span className="mt-auto inline-flex items-center gap-1 text-xs text-[var(--fg-2)]">Usar modelo <Icon name="arrow-right" size={12} /></span>
            </button>
          </li>
        ))}
      </ul>
      <div className="mt-5 flex justify-center">
        <Button size="sm" onClick={() => onNovo(null)}><Icon name="plus" size={14} /> Novo dashboard em branco</Button>
      </div>
    </Card>
  );
}

function Esqueleto() {
  return (
    <div className="space-y-4" aria-busy="true" aria-label="Carregando dashboards">
      <div className="flex gap-2"><Skeleton w={120} h={32} /><Skeleton w={140} h={32} /><Skeleton w={100} h={32} /></div>
      <div className="grid gap-4 md:grid-cols-4">
        {[2, 1, 1, 2, 2].map((lg, i) => (
          <Card key={i} className={`p-4 space-y-3 ${lg === 2 ? 'md:col-span-2' : ''}`}><Skeleton w="50%" h={12} /><Skeleton h={90} /></Card>
        ))}
      </div>
    </div>
  );
}
