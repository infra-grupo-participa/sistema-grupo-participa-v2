'use client';

// Painel personalizável do Início: cada pessoa monta o seu (repo.painel / repo.salvarPainel).
// Grade de 4 colunas (1 no celular). "Personalizar" entra no modo edição: adicionar, editar, remover, mudar
// largura, reordenar (setas ou arrastar), restaurar padrão; nada grava até "Salvar".
import { useMemo, useState } from 'react';
import { Button, Card, FilterSelect, Input, Modal, SectionCard, Skeleton } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { METRICAS, ROTULO_AGRUPAR, ROTULO_PERIODO, ROTULO_VISUAL } from '../../domain/metricas';
import type { Funil, MetricaKey, PeriodoWidget, VisualWidget, WidgetPainel } from '../../domain/types';
import { Campo, EstadoErro, Segmentado, Vazio } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { avisarMudanca, repo, useDados } from '../repositorio';
import { VisualWidgetSvg } from './Graficos';
import { calcularWidget, FOTOGRAFIA, type DadosPainel } from './metricas-painel';
import {
  agrupamentosPermitidos, coerente, LARGURAS, LIMITE_WIDGETS, moverPara, moverWidget, painelMudou, painelPadraoInicio,
  salvarWidget, validarWidget, visuaisPermitidos, widgetNovo,
} from './painel-edicao';
import { INFO_PAINEL } from './textos';

/** Classes literais (o Tailwind só gera o que aparece escrito). */
const SPAN: Record<WidgetPainel['largura'], string> = {
  1: '',
  2: 'md:col-span-2',
  3: 'md:col-span-2 xl:col-span-3',
  4: 'md:col-span-2 xl:col-span-4',
};

export function PainelPersonalizavel({ vendedorId, padraoGestor, dados, funis, titulo, podeEditar, flash }: {
  /** Dono do painel. */
  vendedorId: string;
  /** O padrão de fábrica é o do gestor (time) ou o do vendedor. */
  padraoGestor: boolean;
  dados: DadosPainel;
  funis: Funil[];
  titulo: string;
  podeEditar: boolean;
  flash: (msg: string) => void;
}) {
  const painelQ = useDados(() => repo.painel(vendedorId), [vendedorId]);
  const [rascunho, setRascunho] = useState<WidgetPainel[] | null>(null);
  const [editando, setEditando] = useState<WidgetPainel | null>(null);
  const [salvando, setSalvando] = useState(false);
  const [arrastando, setArrastando] = useState<number | null>(null);
  const [confirmarSaida, setConfirmarSaida] = useState(false);

  const salvos = painelQ.dados?.widgets ?? null;
  const emEdicao = rascunho != null;
  const widgets = rascunho ?? salvos ?? [];

  const entrar = () => { setRascunho(salvos ? [...salvos] : []); };
  const sair = () => { setRascunho(null); setConfirmarSaida(false); };
  const cancelar = () => {
    if (rascunho && salvos && painelMudou(rascunho, salvos)) setConfirmarSaida(true);
    else sair();
  };
  const salvar = async () => {
    if (!rascunho) return;
    setSalvando(true);
    const r = await repo.salvarPainel({ vendedorId, widgets: rascunho });
    setSalvando(false);
    flash(r.msg ?? (r.ok ? 'Painel salvo.' : 'Não foi possível salvar o painel.'));
    // Recarrega antes de sair do modo edição: sem piscar o painel antigo.
    if (r.ok) { await painelQ.recarregar(); sair(); avisarMudanca(); }
  };
  const mudar = (f: (l: WidgetPainel[]) => WidgetPainel[]) => setRascunho((l) => (l ? f(l) : l));
  const largura = (id: string, lg: WidgetPainel['largura']) => mudar((l) => l.map((w) => (w.id === id ? { ...w, largura: lg } : w)));

  const acoes = !podeEditar ? null : emEdicao ? (
    <div className="flex flex-wrap items-center gap-2">
      <Button size="sm" variant="ghost" onClick={() => setRascunho(painelPadraoInicio(vendedorId, padraoGestor).widgets)} title="Volta para os widgets de fábrica (só grava ao salvar)">
        <Icon name="refresh" size={14} /> Restaurar padrão
      </Button>
      <Button size="sm" variant="ghost" onClick={() => setEditando(widgetNovo(`w-${Date.now().toString(36)}`))} disabled={widgets.length >= LIMITE_WIDGETS}
        title={widgets.length >= LIMITE_WIDGETS ? `No máximo ${LIMITE_WIDGETS} widgets` : undefined}>
        <Icon name="plus" size={14} /> Adicionar widget
      </Button>
      <Button size="sm" variant="ghost" onClick={cancelar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar painel'}</Button>
    </div>
  ) : (
    <Button size="sm" variant="ghost" onClick={entrar} disabled={!salvos}><Icon name="sliders" size={14} /> Personalizar</Button>
  );

  return (
    <section aria-label={titulo} className="min-w-0">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h2 className="inline-flex items-center gap-1 text-base font-bold text-[var(--fg)]">
          {titulo} <InfoIndicador texto={INFO_PAINEL} />
        </h2>
        {acoes}
      </div>

      {emEdicao && (
        <p className="mb-3 text-xs text-[var(--fg-3)]">
          Modo edição: arraste os widgets ou use as setas para reordenar. Nada é gravado até &ldquo;Salvar painel&rdquo;.
        </p>
      )}

      {painelQ.erro && !salvos ? (
        <Card><EstadoErro mensagem={painelQ.erro} onTentar={painelQ.recarregar} /></Card>
      ) : !salvos ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4" aria-busy="true" aria-label="Carregando o painel">
          {[2, 1, 1].map((lg, i) => (
            <Card key={i} className={`p-4 space-y-3 ${SPAN[lg as 1 | 2]}`}><Skeleton w="50%" h={12} /><Skeleton h={90} /></Card>
          ))}
        </div>
      ) : widgets.length === 0 ? (
        <Card>
          <Vazio
            icone="dashboard"
            titulo={emEdicao ? 'Painel vazio' : 'Nenhum widget no painel'}
            hint="Escolha os números e gráficos que você quer ver todo dia: vendas da semana, perdidos por motivo, abordados por dia…"
            acao={podeEditar && (emEdicao
              ? <Button size="sm" variant="ghost" onClick={() => setEditando(widgetNovo(`w-${Date.now().toString(36)}`))}><Icon name="plus" size={14} /> Adicionar widget</Button>
              : <Button size="sm" onClick={entrar}><Icon name="sliders" size={14} /> Personalizar</Button>)}
          />
        </Card>
      ) : (
        <ul className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
          {widgets.map((w, i) => (
            <li
              key={w.id}
              className={`min-w-0 ${SPAN[w.largura]} ${emEdicao && arrastando === i ? 'opacity-50' : ''}`}
              draggable={emEdicao}
              onDragStart={emEdicao ? (e) => { setArrastando(i); e.dataTransfer.effectAllowed = 'move'; } : undefined}
              onDragOver={emEdicao ? (e) => { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; } : undefined}
              onDrop={emEdicao ? (e) => { e.preventDefault(); if (arrastando != null) mudar((l) => moverPara(l, arrastando, i)); setArrastando(null); } : undefined}
              onDragEnd={() => setArrastando(null)}
            >
              <CartaoWidget
                w={w} dados={dados} funis={funis} emEdicao={emEdicao}
                primeiro={i === 0} ultimo={i === widgets.length - 1}
                onMover={(d) => mudar((l) => moverWidget(l, w.id, d))}
                onLargura={(lg) => largura(w.id, lg)}
                onEditar={() => setEditando(w)}
                onRemover={() => mudar((l) => l.filter((x) => x.id !== w.id))}
              />
            </li>
          ))}
        </ul>
      )}

      {editando && (
        <ModalWidget
          inicial={editando} novo={!widgets.some((w) => w.id === editando.id)} dados={dados} funis={funis}
          onCancelar={() => setEditando(null)}
          onSalvar={(w) => { mudar((l) => salvarWidget(l, w)); setEditando(null); }}
        />
      )}

      {confirmarSaida && (
        <Modal onClose={() => setConfirmarSaida(false)} title="Descartar mudanças?" width="max-w-sm"
          footer={<>
            <Button size="sm" variant="ghost" onClick={() => setConfirmarSaida(false)}>Continuar editando</Button>
            <Button size="sm" variant="danger" onClick={sair}>Descartar</Button>
          </>}>
          <p className="text-sm text-[var(--fg-2)]">As mudanças no painel ainda não foram salvas.</p>
        </Modal>
      )}
    </section>
  );
}

function CartaoWidget({ w, dados, funis, emEdicao, primeiro, ultimo, onMover, onLargura, onEditar, onRemover }: {
  w: WidgetPainel; dados: DadosPainel; funis: Funil[]; emEdicao: boolean; primeiro: boolean; ultimo: boolean;
  onMover: (delta: number) => void; onLargura: (lg: WidgetPainel['largura']) => void; onEditar: () => void; onRemover: () => void;
}) {
  const serie = useMemo(() => calcularWidget(w, dados), [w, dados]);
  const funil = w.funilId ? funis.find((f) => f.id === w.funilId)?.nome ?? 'Funil arquivado' : null;
  const contexto = [FOTOGRAFIA.has(w.metrica) ? 'Agora' : ROTULO_PERIODO[w.periodo], w.agrupar !== 'nenhum' ? ROTULO_AGRUPAR[w.agrupar].toLowerCase() : null, funil]
    .filter(Boolean).join(' · ');
  const btn = 'grid place-items-center w-7 h-7 rounded-[var(--r-sm)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-40 disabled:pointer-events-none';

  return (
    <Card className={`h-full p-4 flex flex-col gap-3 ${emEdicao ? 'border-dashed cursor-grab active:cursor-grabbing' : ''}`}>
      <div className="flex items-start justify-between gap-2 min-w-0">
        <div className="min-w-0">
          <h3 className="flex items-center gap-1 text-sm font-semibold text-[var(--fg)] min-w-0">
            <span className="truncate">{w.titulo}</span>
            <InfoIndicador metrica={w.metrica} className="shrink-0" />
          </h3>
          <p className="text-[11px] text-[var(--fg-3)] truncate">{contexto}</p>
        </div>
        {emEdicao && (
          <div className="flex shrink-0 items-center">
            <button type="button" className={btn} onClick={() => onMover(-1)} disabled={primeiro} aria-label={`Mover ${w.titulo} para trás`}><Icon name="arrow-left" size={14} /></button>
            <button type="button" className={btn} onClick={() => onMover(1)} disabled={ultimo} aria-label={`Mover ${w.titulo} para frente`}><Icon name="arrow-right" size={14} /></button>
            <button type="button" className={btn} onClick={onEditar} aria-label={`Editar ${w.titulo}`}><Icon name="pencil" size={14} /></button>
            <button type="button" className={`${btn} hover:!text-[var(--red)]`} onClick={onRemover} aria-label={`Remover ${w.titulo}`}><Icon name="trash" size={14} /></button>
          </div>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <VisualWidgetSvg visual={w.visual} serie={serie} metrica={w.metrica} />
      </div>
      {emEdicao && (
        <div className="flex items-center justify-between gap-2 border-t border-[var(--border-faint)] pt-2">
          <span className="text-[11px] text-[var(--fg-3)]">Largura</span>
          <Segmentado
            rotulo={`Largura de ${w.titulo} em colunas`}
            valor={String(w.largura) as '1' | '2' | '3' | '4'}
            onChange={(v) => onLargura(Number(v) as WidgetPainel['largura'])}
            opcoes={LARGURAS.map((l) => ({ valor: String(l) as '1' | '2' | '3' | '4', rotulo: String(l), title: `${l} de 4 colunas` }))}
          />
        </div>
      )}
    </Card>
  );
}

const PERIODOS: PeriodoWidget[] = ['hoje', '7d', '30d', 'mes'];

function ModalWidget({ inicial, novo, dados, funis, onCancelar, onSalvar }: {
  inicial: WidgetPainel; novo: boolean; dados: DadosPainel; funis: Funil[];
  onCancelar: () => void; onSalvar: (w: WidgetPainel) => void;
}) {
  const [w, setW] = useState<WidgetPainel>(() => coerente(inicial));
  const [tentou, setTentou] = useState(false);
  const def = METRICAS[w.metrica];
  const erro = validarWidget(w);
  const previa = useMemo(() => calcularWidget(w, dados), [w, dados]);
  const atualizar = (p: Partial<WidgetPainel>) => setW((x) => coerente({ ...x, ...p }));
  const fotografia = FOTOGRAFIA.has(w.metrica);
  const agrupamentos = agrupamentosPermitidos(w.metrica, w.visual);

  const confirmar = () => {
    setTentou(true);
    if (!erro) onSalvar({ ...w, titulo: w.titulo.trim() });
  };

  return (
    <Modal
      onClose={onCancelar}
      title={novo ? 'Adicionar widget' : 'Editar widget'}
      width="max-w-2xl"
      footer={<>
        <Button size="sm" variant="ghost" onClick={onCancelar}>Cancelar</Button>
        <Button size="sm" onClick={confirmar}>{novo ? 'Adicionar' : 'Aplicar'}</Button>
      </>}
    >
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-3 min-w-0">
          <Campo rotulo="Título" dica={tentou && erro ? <span className="text-[var(--red)]">{erro}</span> : undefined}>
            <Input value={w.titulo} maxLength={60} placeholder={def.nome} onChange={(e) => setW((x) => ({ ...x, titulo: e.target.value }))} autoFocus />
          </Campo>
          <Campo rotulo="Métrica">
            <FilterSelect value={w.metrica} onChange={(e) => atualizar({ metrica: e.target.value as MetricaKey })}>
              {(Object.keys(METRICAS) as MetricaKey[]).map((k) => <option key={k} value={k}>{METRICAS[k].nome}</option>)}
            </FilterSelect>
          </Campo>
          <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3 text-xs leading-relaxed">
            <p className="text-[var(--fg-2)]">{def.oQueE}</p>
            <p className="mt-1.5 text-[var(--fg-3)]"><span className="font-semibold text-[var(--fg-2)]">Como conta: </span>{def.comoConta}</p>
            {def.meta && <p className="mt-1.5 text-[var(--fg-3)]"><span className="font-semibold text-[var(--fg-2)]">Meta: </span>{def.meta}</p>}
          </div>
          <Campo rotulo="Visual">
            <Segmentado<VisualWidget>
              rotulo="Visual do widget" valor={w.visual} onChange={(v) => atualizar({ visual: v })}
              opcoes={visuaisPermitidos(w.metrica).map((v) => ({ valor: v, rotulo: ROTULO_VISUAL[v] }))}
            />
          </Campo>
          <Campo rotulo="Período" dica={fotografia ? 'Fotografia do momento: o período não muda este número.' : 'Comparado com o período anterior de mesmo tamanho.'}>
            <Segmentado<PeriodoWidget>
              rotulo="Período" valor={w.periodo} onChange={(v) => atualizar({ periodo: v })}
              opcoes={PERIODOS.map((p) => ({ valor: p, rotulo: ROTULO_PERIODO[p] }))}
            />
          </Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo rotulo="Agrupar">
              <FilterSelect value={w.agrupar} onChange={(e) => atualizar({ agrupar: e.target.value as WidgetPainel['agrupar'] })} disabled={agrupamentos.length <= 1}>
                {agrupamentos.map((a) => <option key={a} value={a}>{ROTULO_AGRUPAR[a]}</option>)}
              </FilterSelect>
            </Campo>
            <Campo rotulo="Largura">
              <FilterSelect value={w.largura} onChange={(e) => atualizar({ largura: Number(e.target.value) as WidgetPainel['largura'] })}>
                {LARGURAS.map((l) => <option key={l} value={l}>{l} {l === 1 ? 'coluna' : 'colunas'}</option>)}
              </FilterSelect>
            </Campo>
          </div>
          <Campo rotulo="Funil" extra={<span className="text-[var(--fg-3)]">opcional</span>}>
            <FilterSelect value={w.funilId ?? ''} onChange={(e) => atualizar({ funilId: e.target.value || null })}>
              <option value="">Todos os funis</option>
              {funis.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
            </FilterSelect>
          </Campo>
        </div>
        <div className="min-w-0">
          <p className="mb-2 text-xs font-medium text-[var(--fg-2)]">Prévia</p>
          <SectionCard className="!p-4" title={<span className="text-sm">{w.titulo.trim() || def.nome}</span>}>
            <VisualWidgetSvg visual={w.visual} serie={previa} metrica={w.metrica} />
          </SectionCard>
          <p className="mt-2 text-[11px] text-[var(--fg-3)]">Com os dados de quem está no painel agora.</p>
        </div>
      </div>
    </Modal>
  );
}
