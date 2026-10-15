'use client';

// Modal aberto pelo card de uma etapa da Visão geral (C1, Consultoria, Iscas, C3): todos os funis da etapa lado a lado,
// um por subtipo do banco (nas Iscas, um por isca). Sem botão de troca de visão. Campanha sem etapa, com conflito ou
// sem subtipo reconhecido fica fora das colunas e o modal diz quantas e quais (nome exato). Sem dado = "Sem dado".
import { useEffect, useMemo, useRef, type ReactNode } from 'react';
import { Modal } from '@/shared/ui/components';
import { agregar, cpm, ctr, custoPorVisualizacao, farolCpl, gastoDe, taxaVideo75 } from '../domain/metricas';
import { cplCaptacao, conversaoPagina, gastoCampanha, leadsDoTrafego } from '../domain/numeros';
import { funisDaEtapa, type ColunaFunil } from '../domain/funis-etapa';
import { ROTULO_FUNIL, type DesempenhoDia, type Funil, type LinhaPerfil, type Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { Farol, MODAL_TELA_CHEIA, Numero, Taxa } from './pecas';

const FOCAVEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex]:not([tabindex="-1"])';

/** O Modal compartilhado fecha com Esc, mas não prende o foco nem se declara diálogo: isto fica só aqui. */
function useDialogoAcessivel(raiz: React.RefObject<HTMLDivElement | null>, rotulo: string) {
  useEffect(() => {
    const overlay = raiz.current?.closest<HTMLElement>('div.fixed');
    if (!overlay) return;
    const anterior = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', rotulo);
    overlay.querySelector<HTMLElement>('.sticky button')?.focus();
    const tecla = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;
      const itens = Array.from(overlay.querySelectorAll<HTMLElement>(FOCAVEL)).filter((el) => el.offsetParent !== null || el === document.activeElement);
      if (itens.length === 0) return;
      const primeiro = itens[0]; const ultimo = itens[itens.length - 1];
      if (!overlay.contains(document.activeElement)) { e.preventDefault(); primeiro.focus(); }
      else if (e.shiftKey && document.activeElement === primeiro) { e.preventDefault(); ultimo.focus(); }
      else if (!e.shiftKey && document.activeElement === ultimo) { e.preventDefault(); primeiro.focus(); }
    };
    window.addEventListener('keydown', tecla);
    return () => {
      window.removeEventListener('keydown', tecla);
      if (anterior && anterior.isConnected) anterior.focus();
    };
  }, [raiz, rotulo]);
}

function Metrica({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <div className="flex items-baseline justify-between gap-3 py-1 text-sm"><dt className="text-[var(--fg-3)]">{rotulo}</dt><dd className="text-right text-[var(--fg)]">{children}</dd></div>;
}

/** Gasto das campanhas inteiras (dias_campanha). Se uma campanha está sem dado, a coluna fica sem dado, nunca soma parcial. */
function gastoDasCampanhas(d: DadosTela, col: ColunaFunil): Valor {
  if (col.campanhas.length === 0) return null;
  let soma = 0;
  for (const c of col.campanhas) {
    const g = gastoCampanha(d.trafegoPeriodo, c.id).valor;
    if (g === null) return null;
    soma += g;
  }
  return soma;
}

function Coluna({ d, funil, col }: { d: DadosTela; funil: Funil; col: ColunaFunil }) {
  const a = agregar(col.dias);
  const temDia = col.dias.length > 0;
  // Nas Iscas o gasto vem dos anúncios do conjunto (a fonte não divide o gasto da campanha por conjunto).
  const gasto: Valor = funil === 'iscas' ? (temDia ? gastoDe(col.dias) : null) : gastoDasCampanhas(d, col);
  const nomes = funil === 'iscas' ? col.conjuntos.map((j) => j.nome) : col.campanhas.map((c) => c.nome);
  const unica = col.campanhas.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'campanha' && t.id === col.campanhas[0].id) : undefined;
  const faltaAlcance = col.campanhas.length > 1 ? 'alcance não soma entre campanhas' : 'alcance do período';
  const pagos = d.perfilSemDado ? null : leadsDoTrafego(col.linhas, d.idx);
  const cpl = pagos ? cplCaptacao(gasto, pagos) : null;
  return (
    <section aria-label={`${ROTULO_FUNIL[funil]}: ${col.rotulo}`} className="flex min-w-[16rem] flex-1 basis-0 flex-col rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
      <h3 className="break-words text-sm font-bold text-[var(--fg)]">{col.rotulo}</h3>
      <ul className="mb-2 mt-1 space-y-0.5 text-[11px] text-[var(--fg-3)]">
        {nomes.map((n) => <li key={n} className="break-words">{n}</li>)}
      </ul>
      <dl className="divide-y divide-[var(--border-faint)]">
        <Metrica rotulo="Investimento"><Numero valor={gasto} formato="brl" animado={false} falta="campanha sem gasto na fonte" /></Metrica>
        <Metrica rotulo="Impressões"><Numero valor={temDia ? a.impressoes : null} formato="int" animado={false} /></Metrica>
        {funil === 'c1' ? <>
          <Metrica rotulo="Alcance"><Numero valor={unica?.alcance ?? null} formato="int" falta={faltaAlcance} animado={false} /></Metrica>
          <Metrica rotulo="Frequência"><Numero valor={unica?.frequencia ?? null} formato="dec" falta={faltaAlcance} animado={false} /></Metrica>
          <Metrica rotulo="CPM"><Numero valor={temDia ? cpm(a) : null} formato="brl" animado={false} /></Metrica>
          <Metrica rotulo="ThruPlay"><Numero valor={a.thruplay.valor} formato="int" animado={false} /></Metrica>
          <Metrica rotulo="Vídeo 75%"><Taxa taxa={taxaVideo75(a)} /></Metrica>
          <Metrica rotulo="Custo por visualização"><Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} /></Metrica>
        </> : <>
          <Metrica rotulo="CTR"><Taxa taxa={ctr(a)} /></Metrica>
          <Metrica rotulo="Leads pagos"><Numero valor={pagos?.valor ?? null} formato="int" falta={d.avisoPerfil ?? undefined} animado={false} /></Metrica>
          <Metrica rotulo="CPL"><span className="inline-flex items-center gap-1.5"><Numero valor={cpl?.valor ?? null} formato="brl" falta="sem leads pagos no recorte" animado={false} /><Farol farol={farolCpl(cpl?.valor ?? null, d.config.reguaCpl)} /></span></Metrica>
          <Metrica rotulo="Conversão da página"><Taxa taxa={conversaoPagina(col.dias, col.linhas, d.idx)} /></Metrica>
        </>}
      </dl>
      {funil === 'iscas' && <p className="mt-2 text-[10px] text-[var(--fg-3)]">Tráfego agrupado pelo último bloco do nome do conjunto; leads pelo campo isca do perfil.</p>}
    </section>
  );
}

export function ModalFunisEtapa({ d, funil, dias, linhas, onClose }: {
  d: DadosTela; funil: Funil; dias: readonly DesempenhoDia[]; linhas: readonly LinhaPerfil[]; onClose: () => void;
}) {
  const raiz = useRef<HTMLDivElement>(null);
  const titulo = `Funis: ${ROTULO_FUNIL[funil]}, lado a lado`;
  useDialogoAcessivel(raiz, titulo);
  const { colunas, fora, conjuntosSemIsca } = useMemo(() => funisDaEtapa(funil, d.trafegoPeriodo, dias, linhas, d.idx), [funil, d.trafegoPeriodo, dias, linhas, d.idx]);
  const avisos = fora.length + conjuntosSemIsca.length;
  return (
    <Modal open onClose={onClose} title={titulo} width={`max-w-7xl ${MODAL_TELA_CHEIA}`}>
      <div ref={raiz} className="space-y-3">
        {colunas.length === 0
          ? <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Nenhum funil com nomenclatura reconhecida no {ROTULO_FUNIL[funil]} neste recorte.</p>
          : <div role="region" aria-label={`Funis: ${ROTULO_FUNIL[funil]}`} tabIndex={0} className="flex gap-3 overflow-x-auto pb-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
            {colunas.map((col) => <Coluna key={col.rotulo} d={d} funil={funil} col={col} />)}
          </div>}
        {avisos > 0 && (
          <details className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 text-xs text-[var(--fg-2)]">
            <summary className="cursor-pointer font-semibold text-[var(--fg)]">
              {fora.length > 0 && `${fora.length} ${fora.length === 1 ? 'campanha fora' : 'campanhas fora'} dos funis`}
              {fora.length > 0 && conjuntosSemIsca.length > 0 && ' · '}
              {conjuntosSemIsca.length > 0 && `${conjuntosSemIsca.length} ${conjuntosSemIsca.length === 1 ? 'conjunto' : 'conjuntos'} de isca sem a isca no nome`}
            </summary>
            <p className="mt-2 text-[var(--fg-3)]">Sem etapa, com conflito de subtipo ou sem subtipo reconhecido no nome: não entram em nenhuma coluna (nem em outra etapa). Corrigir o nome no gerenciador.</p>
            <ul className="mt-2 space-y-1">
              {fora.map(({ campanha, motivo }) => <li key={campanha.id} className="break-words"><code className="text-[var(--fg)]">{campanha.nome}</code> <span className="text-[var(--fg-3)]">({motivo})</span></li>)}
              {funil === 'iscas' && conjuntosSemIsca.map((j) => <li key={j.id} className="break-words"><code className="text-[var(--fg)]">{j.nome}</code> <span className="text-[var(--fg-3)]">(conjunto sem isca reconhecida)</span></li>)}
            </ul>
          </details>
        )}
      </div>
    </Modal>
  );
}
