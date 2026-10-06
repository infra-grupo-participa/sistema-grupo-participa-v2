'use client';

// Modo edição do dashboard: biblioteca à esquerda, grade ao centro (prévia ao vivo), propriedades à direita.
// Nada grava até "Salvar". Desfazer/refazer em pilha (botões e Ctrl+Z / Ctrl+Shift+Z).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, ConfirmDialog, FilterSelect, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { METRICAS } from '../../domain/metricas';
import type { Dashboard, Funil, MetricaKey, Vendedor } from '../../domain/types';
import { Aviso, Campo } from '../comum';
import type { DadosPainel } from '../inicio/metricas-painel';
import { avisarMudanca, repo } from '../repositorio';
import { Biblioteca } from './Biblioteca';
import { GradeDash, type AcoesGrade, type Arrasto } from './GradeDash';
import {
  aplicar, atualizarWidget, criarHistorico, desfazer, duplicarWidget, fecharPasso, inserir, LIMITE_WIDGETS_DASH, moverParaPonto,
  moverParaPosicao, moverPorDelta, redimensionar, refazer, removerWidget, validarDashboard, widgetDaMetrica, widgetsMudaram,
  type Historico, type WidgetDash,
} from './layout';
import { PainelPropriedades } from './PainelPropriedades';

let seq = 0;
const novoId = () => `w-${Date.now().toString(36)}-${(seq++).toString(36)}`;

export function Construtor({ dash, dadosPara, funis, vendedores, gestor, nomeDe, flash, onSair }: {
  dash: Dashboard;
  dadosPara: (vendedorId: string | null | undefined) => DadosPainel;
  funis: Funil[];
  vendedores: Vendedor[];
  gestor: boolean;
  nomeDe: (id: string | null) => string;
  flash: (msg: string) => void;
  /** Saiu do modo edição (salvou ou descartou). */
  onSair: () => void;
}) {
  const salvos = useMemo(() => dash.widgets as WidgetDash[], [dash.widgets]);
  const [hist, setHist] = useState<Historico<WidgetDash[]>>(() => criarHistorico(salvos));
  const [selecionado, setSelecionado] = useState<string | null>(null);
  const [arrasto, setArrasto] = useState<Arrasto>(null);
  const [focarId, setFocoPedido] = useState<{ id: string; vez: number } | null>(null);
  const setFocarId = (id: string | null) => setFocoPedido(id ? { id, vez: Date.now() + Math.random() } : null);
  const [anuncio, setAnuncio] = useState('');
  const [moverId, setMoverId] = useState<string | null>(null);
  const [confirmarDescarte, setConfirmarDescarte] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erroSalvar, setErroSalvar] = useState<string | null>(null);

  const widgets = hist.presente;
  const mudou = widgetsMudaram(widgets, salvos);
  const cheio = widgets.length >= LIMITE_WIDGETS_DASH;
  const titulo = (id: string) => widgets.find((w) => w.id === id)?.titulo || 'Widget';

  const mudar = useCallback((f: (l: WidgetDash[]) => WidgetDash[], chave: string | null = null) => {
    setHist((h) => aplicar(h, f(h.presente), chave));
    setErroSalvar(null);
  }, []);

  const adicionar = (m: MetricaKey, ponto?: number) => {
    if (cheio) { flash(`No máximo ${LIMITE_WIDGETS_DASH} widgets por dashboard.`); return; }
    const w = widgetDaMetrica(m, novoId());
    // Clique na biblioteca: entra logo depois do selecionado; senão no fim.
    const i = selecionado ? widgets.findIndex((x) => x.id === selecionado) : -1;
    const pos = ponto ?? (i >= 0 ? i + 1 : widgets.length);
    mudar((l) => inserir(l, w, pos));
    setSelecionado(w.id);
    setFocarId(w.id);
    setAnuncio(`${METRICAS[m].nome} adicionado na posição ${pos + 1} de ${widgets.length + 1}.`);
  };

  const acoes: AcoesGrade = {
    selecionar: (id) => setSelecionado(id),
    mover: (id, delta) => {
      const i = widgets.findIndex((w) => w.id === id);
      const j = i + delta;
      if (i < 0 || j < 0 || j >= widgets.length) return;
      mudar((l) => moverPorDelta(l, id, delta));
      setFocarId(id);
      setAnuncio(`${titulo(id)} movido para a posição ${j + 1} de ${widgets.length}.`);
    },
    soltarWidget: (id, ponto) => {
      const de = widgets.findIndex((w) => w.id === id);
      mudar((l) => moverParaPonto(l, de, ponto));
      setSelecionado(id);
      setAnuncio(`${titulo(id)} movido.`);
    },
    soltarMetrica: (m, ponto) => adicionar(m, ponto),
    largura: (id, lg, continuo) => {
      mudar((l) => redimensionar(l, id, lg), continuo ? `largura:${id}` : null);
      setAnuncio(`Largura de ${titulo(id)}: ${lg} de 4.`);
    },
    fimLargura: () => setHist(fecharPasso),
    duplicar: (id) => {
      if (cheio) { flash(`No máximo ${LIMITE_WIDGETS_DASH} widgets por dashboard.`); return; }
      const nid = novoId();
      mudar((l) => duplicarWidget(l, id, nid));
      setSelecionado(nid);
      setFocarId(nid);
      setAnuncio(`${titulo(id)} duplicado.`);
    },
    remover: (id) => {
      const i = widgets.findIndex((w) => w.id === id);
      const vizinho = widgets[i + 1]?.id ?? widgets[i - 1]?.id ?? null;
      mudar((l) => removerWidget(l, id));
      if (selecionado === id) setSelecionado(null);
      setFocarId(vizinho);
      setAnuncio(`${titulo(id)} removido. Ctrl+Z desfaz.`);
    },
    pedirMoverPara: (id) => setMoverId(id),
  };

  const voltar = () => { if (!hist.passado.length) return; setHist(desfazer); setAnuncio('Desfeito.'); };
  const avancar = () => { if (!hist.futuro.length) return; setHist(refazer); setAnuncio('Refeito.'); };

  // Atalhos: Ctrl/Cmd+Z desfaz, Ctrl/Cmd+Shift+Z ou Ctrl+Y refaz. Em campo de texto, o campo cuida.
  const atalhos = useRef({ voltar, avancar });
  useEffect(() => { atalhos.current = { voltar, avancar }; });
  useEffect(() => {
    const tecla = (e: KeyboardEvent) => {
      const alvo = e.target as HTMLElement | null;
      if (alvo && (alvo.tagName === 'INPUT' || alvo.tagName === 'TEXTAREA' || alvo.tagName === 'SELECT' || alvo.isContentEditable)) return;
      if (!(e.ctrlKey || e.metaKey)) return;
      const k = e.key.toLowerCase();
      if (k === 'z' && !e.shiftKey) { e.preventDefault(); atalhos.current.voltar(); }
      else if ((k === 'z' && e.shiftKey) || k === 'y') { e.preventDefault(); atalhos.current.avancar(); }
    };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, []);

  // Sair da página com mudança não salva: o navegador pergunta.
  useEffect(() => {
    if (!mudou) return;
    const antes = (e: BeforeUnloadEvent) => { e.preventDefault(); };
    window.addEventListener('beforeunload', antes);
    return () => window.removeEventListener('beforeunload', antes);
  }, [mudou]);

  const salvar = async () => {
    const erro = validarDashboard(dash.nome, widgets);
    if (erro) { setErroSalvar(erro); return; }
    setSalvando(true);
    try {
      const r = await repo.salvarDashboard({ ...dash, widgets: widgets.map((w) => ({ ...w, titulo: w.titulo.trim() })) });
      if (!r.ok) { setErroSalvar(r.msg ?? 'Não foi possível salvar.'); return; }
      flash(r.msg ?? 'Dashboard salvo.');
      avisarMudanca();
      onSair();
    } catch (e) {
      setErroSalvar(e instanceof Error ? e.message : 'Não foi possível salvar.');
    } finally {
      setSalvando(false);
    }
  };

  const descartar = () => { if (mudou) setConfirmarDescarte(true); else onSair(); };
  const sel = widgets.find((w) => w.id === selecionado) ?? null;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
        <p className="min-w-0 text-sm text-[var(--fg-2)]">
          <span className="font-semibold text-[var(--fg)]">Editando {dash.nome}</span>
          <span className="text-[var(--fg-3)]"> · {widgets.length} {widgets.length === 1 ? 'widget' : 'widgets'}{mudou ? ' · mudanças não salvas' : ''}</span>
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="ghost" onClick={voltar} disabled={!hist.passado.length} aria-label="Desfazer" title="Desfazer (Ctrl+Z)">
            <Icon name="arrow-left" size={14} /> Desfazer
          </Button>
          <Button size="sm" variant="ghost" onClick={avancar} disabled={!hist.futuro.length} aria-label="Refazer" title="Refazer (Ctrl+Shift+Z)">
            Refazer <Icon name="arrow-right" size={14} />
          </Button>
          <Button size="sm" variant="ghost" onClick={descartar}>Descartar</Button>
          <Button size="sm" onClick={salvar} disabled={salvando || !mudou}>{salvando ? 'Salvando…' : 'Salvar dashboard'}</Button>
        </div>
      </div>

      {erroSalvar && <Aviso tom="danger" alerta titulo="Não foi salvo">{erroSalvar}</Aviso>}

      <div className="grid gap-4 lg:grid-cols-[220px_minmax(0,1fr)] 2xl:grid-cols-[220px_minmax(0,1fr)_280px] items-start">
        <div className="lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
          <Biblioteca onAdicionar={(m) => adicionar(m)} setArrasto={setArrasto} cheio={cheio} />
        </div>
        <div className="min-w-0 space-y-4">
          <GradeDash
            widgets={widgets} dadosPara={dadosPara} funis={funis} nomeDe={nomeDe}
            edicao={{ selecionado, arrasto, setArrasto, focarId, acoes }}
          />
          {/* Telas médias: propriedades abaixo da grade. */}
          <div className="2xl:hidden">
            {sel && (
              <PainelPropriedades
                w={sel} funis={funis} vendedores={vendedores} gestor={gestor}
                onMudar={(p, chave) => mudar((l) => atualizarWidget(l, sel.id, p), chave ?? null)}
                onFecharPasso={() => setHist(fecharPasso)} onFechar={() => setSelecionado(null)}
              />
            )}
          </div>
        </div>
        <div className="hidden 2xl:block 2xl:sticky 2xl:top-4">
          <PainelPropriedades
            w={sel} funis={funis} vendedores={vendedores} gestor={gestor}
            onMudar={(p, chave) => sel && mudar((l) => atualizarWidget(l, sel.id, p), chave ?? null)}
            onFecharPasso={() => setHist(fecharPasso)} onFechar={() => setSelecionado(null)}
          />
        </div>
      </div>

      <p className="sr-only" aria-live="polite">{anuncio}</p>

      {moverId && (
        <ModalMoverPara
          titulo={titulo(moverId)} total={widgets.length} atual={widgets.findIndex((w) => w.id === moverId)}
          onCancelar={() => setMoverId(null)}
          onMover={(para) => {
            const de = widgets.findIndex((w) => w.id === moverId);
            mudar((l) => moverParaPosicao(l, de, para));
            setFocarId(moverId);
            setAnuncio(`${titulo(moverId)} movido para a posição ${para + 1} de ${widgets.length}.`);
            setMoverId(null);
          }}
        />
      )}

      <ConfirmDialog
        open={confirmarDescarte}
        title="Descartar mudanças?"
        message="As mudanças neste dashboard ainda não foram salvas. Descartar volta para a última versão salva."
        confirmLabel="Descartar" cancelLabel="Continuar editando" danger
        onCancel={() => setConfirmarDescarte(false)}
        onConfirm={() => { setConfirmarDescarte(false); onSair(); }}
      />
    </div>
  );
}

function ModalMoverPara({ titulo, total, atual, onCancelar, onMover }: {
  titulo: string; total: number; atual: number; onCancelar: () => void; onMover: (para: number) => void;
}) {
  const [para, setPara] = useState(atual);
  const rotulo = (i: number) => (i === 0 ? '1ª posição (início)' : i === total - 1 ? `${i + 1}ª posição (fim)` : `${i + 1}ª posição`);
  return (
    <Modal onClose={onCancelar} title="Mover widget" width="max-w-sm"
      footer={<>
        <Button size="sm" variant="ghost" onClick={onCancelar}>Cancelar</Button>
        <Button size="sm" onClick={() => onMover(para)} disabled={para === atual}>Mover</Button>
      </>}>
      <Campo rotulo={`Mover "${titulo}" para`} dica={`Hoje está na ${atual + 1}ª posição de ${total}.`}>
        <FilterSelect value={para} autoFocus onChange={(e) => setPara(Number(e.target.value))}>
          {Array.from({ length: total }, (_, i) => <option key={i} value={i}>{rotulo(i)}{i === atual ? ' · atual' : ''}</option>)}
        </FilterSelect>
      </Campo>
    </Modal>
  );
}
