'use client';

// Kanban do funil: uma coluna por etapa, largura fixa e rolagem horizontal (nome não corta).
// Arrastar um card para outra coluna move o negócio; pelo teclado ou no celular, o menu "Mover para…" do card.
// As travas do banco (dono, campos obrigatórios, ganho só com pagamento) vêm de domain/travas.ts: a coluna que não
// aceita o card arrastado não vira alvo (cursor de proibido) e o card de outro dono nem arrasta.
// No celular (< md) aparece uma coluna por vez, escolhida no segmentado de etapas.
import { useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { COR_ETAPA, fmtMinutos } from '../../domain/funis';
import { situacaoSla } from '../../domain/regras';
import type { TravaMover } from '../../domain/travas';
import type { Contato, EtapaFunil, Funil, Negocio } from '../../domain/types';
import { CardNegocio, fmtValorCurto } from './CardNegocio';
import { Segmentado } from '../comum';
import { ordenarPorUrgencia } from './regras-funil';

/** Cards por vez em cada coluna; o resto vem no "Mostrar mais". */
const LOTE = 20;

export function KanbanFunil({ funil, negocios, contatoPorId, agora, nomeDe, altura, ocultarGanho, leituraDe, travaPara, onAbrir, onMover, onAgendar, onCopiarTelefone }: {
  funil: Funil;
  negocios: Negocio[];
  contatoPorId: Map<string, Contato>;
  agora: Date;
  nomeDe: (id: string | null) => string;
  /** Altura disponível (px) no desktop; as colunas rolam por dentro. */
  altura: number | null;
  /** Com filtro de alerta ativo a coluna de ganho não tem o que mostrar. */
  ocultarGanho?: boolean;
  /** Motivo de só leitura do negócio para quem está na tela (null = pode mexer). */
  leituraDe: (n: Negocio) => string | null;
  travaPara: (n: Negocio, etapaId: string) => TravaMover;
  onAbrir: (negocioId: string) => void;
  onMover: (negocioId: string, etapaId: string) => void;
  onAgendar: (negocio: Negocio) => void;
  onCopiarTelefone: (tel: string) => void;
}) {
  const [sobre, setSobre] = useState<string | null>(null);
  const [arrastandoId, setArrastandoId] = useState<string | null>(null);
  const arrastando = arrastandoId ? negocios.find((n) => n.id === arrastandoId) ?? null : null;
  const [limite, setLimite] = useState<Record<string, number>>({});
  const etapas = ocultarGanho ? funil.etapas.filter((e) => e.papel !== 'fechado') : funil.etapas;
  const [etapaMovel, setEtapaMovel] = useState<string>(etapas[0]?.id ?? '');
  const ativaMovel = etapas.some((e) => e.id === etapaMovel) ? etapaMovel : etapas[0]?.id;

  const colunas = etapas.map((e) => {
    const ganho = e.papel === 'fechado';
    const itens = ordenarPorUrgencia(
      negocios.filter((n) => n.etapaId === e.id && (ganho ? n.status === 'ganho' : n.status === 'aberto')), agora,
    );
    return {
      e, ganho, itens,
      total: itens.reduce((s, n) => s + n.valor, 0),
      criticos: itens.filter((n) => situacaoSla(n, agora) === 'critico').length,
    };
  });

  return (
    <div className="flex flex-col gap-3 min-h-0" style={altura ? ({ '--kanban-h': `${altura}px` } as React.CSSProperties) : undefined}>
      {/* Celular: uma etapa por vez. */}
      <Segmentado
        rotulo="Etapa"
        className="md:hidden"
        valor={ativaMovel ?? ''}
        onChange={setEtapaMovel}
        opcoes={colunas.map(({ e, itens, criticos }) => ({ valor: e.id, rotulo: e.nome, n: itens.length, alerta: criticos > 0 }))}
      />

      <div className="md:overflow-x-auto md:h-[var(--kanban-h,auto)] pb-1">
        <div className="flex gap-3 md:min-w-max md:h-full items-start">
          {colunas.map(({ e, ganho, itens, total, criticos }) => {
            // Enquanto arrasta: a coluna só aceita se a trava permitir (campos, ganho, dono).
            const aceita = !ganho && (!arrastando || arrastando.etapaId === e.id || travaPara(arrastando, e.id).permitido);
            const recusa = !!arrastando && !aceita && arrastando.etapaId !== e.id;
            const alvo = sobre === e.id && aceita;
            const max = limite[e.id] ?? LOTE;
            const visiveis = itens.slice(0, max);
            return (
              <section
                key={e.id}
                aria-label={`${e.nome}: ${itens.length} ${itens.length === 1 ? 'negócio' : 'negócios'}`}
                onDragOver={(ev) => { if (aceita) { ev.preventDefault(); setSobre(e.id); } }}
                onDragLeave={(ev) => { if (!ev.currentTarget.contains(ev.relatedTarget as Node)) setSobre((s) => (s === e.id ? null : s)); }}
                onDrop={(ev) => {
                  ev.preventDefault();
                  setSobre(null);
                  setArrastandoId(null);
                  const id = ev.dataTransfer.getData('text/negocio');
                  if (id && aceita) onMover(id, e.id);
                }}
                className={`${e.id === ativaMovel ? 'flex' : 'hidden'} md:flex w-full md:w-[272px] shrink-0 flex-col md:max-h-full rounded-[var(--r-lg)] border transition-colors ${alvo ? 'border-[var(--border-accent)] bg-[var(--accent-subtle)]' : 'border-[var(--border)] bg-[var(--surface-1)]'} ${recusa ? 'opacity-60' : ''}`}
                title={recusa && arrastando ? travaPara(arrastando, e.id).motivo ?? undefined : undefined}
              >
                <CabecalhoColuna e={e} ganho={ganho} qtd={itens.length} total={total} criticos={criticos} />
                <div className="flex flex-col gap-2 p-2 min-h-[120px] md:min-h-0 md:overflow-y-auto">
                  {visiveis.map((n) => (
                    <CardNegocio
                      key={n.id}
                      n={n}
                      c={contatoPorId.get(n.contatoId)}
                      agora={agora}
                      nomeDe={nomeDe}
                      etapas={funil.etapas}
                      leitura={leituraDe(n)}
                      travaPara={(etapaId) => travaPara(n, etapaId)}
                      onArrastar={setArrastandoId}
                      onAbrir={() => onAbrir(n.id)}
                      onAgendar={() => onAgendar(n)}
                      onMover={(etapaId) => onMover(n.id, etapaId)}
                      onCopiarTelefone={onCopiarTelefone}
                      arrastavel={n.status === 'aberto'}
                    />
                  ))}
                  {itens.length > max && (
                    <button type="button" onClick={() => setLimite((l) => ({ ...l, [e.id]: max + LOTE }))}
                      className="min-h-8 rounded-[var(--r-md)] text-xs font-medium text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
                      Mostrar mais {Math.min(LOTE, itens.length - max)} de {itens.length - max}
                    </button>
                  )}
                  {itens.length === 0 && (
                    <div className={`py-6 text-center text-xs text-[var(--fg-3)] rounded-[var(--r-md)] ${alvo ? '' : 'border border-dashed border-[var(--border-faint)]'}`}>
                      {ganho ? 'Nenhum pagamento aprovado' : <><span className="hidden md:inline">Arraste um negócio para cá</span><span className="md:hidden">Nenhum negócio nesta etapa</span></>}
                    </div>
                  )}
                </div>
              </section>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function CabecalhoColuna({ e, ganho, qtd, total, criticos }: { e: EtapaFunil; ganho: boolean; qtd: number; total: number; criticos: number }) {
  const dica = [
    e.criterio && `Critério para passar: ${e.criterio}`,
    e.slaAtencaoMin != null && `Alerta: atenção ${fmtMinutos(e.slaAtencaoMin)}, crítico ${fmtMinutos(e.slaCriticoMin)}`,
    ganho ? 'Ganho só com pagamento aprovado na Hotmart' : 'Ordenado por urgência: crítico primeiro',
  ].filter(Boolean).join(' · ');
  return (
    <header className="shrink-0 px-3 py-2 border-b border-[var(--border)]" title={dica}>
      <div className="flex items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 min-w-0 text-[13px] font-semibold text-[var(--fg)]">
          <span aria-hidden className="w-2 h-2 rounded-full shrink-0" style={{ background: COR_ETAPA[e.cor] }} />
          <span className="truncate">{e.nome}</span>
        </h3>
        <span className="shrink-0 text-[11px] font-semibold tabular text-[var(--fg-2)] rounded-[var(--r-pill)] bg-[var(--surface-3)] px-2 py-0.5">{qtd}</span>
      </div>
      <div className="mt-0.5 flex items-center justify-between gap-2 text-xs text-[var(--fg-3)]">
        <span className="tabular text-[var(--fg-2)]">{qtd ? fmtValorCurto(total) : '—'}</span>
        {criticos > 0 && <span className="font-medium text-[var(--red)]">{criticos} {criticos === 1 ? 'crítico' : 'críticos'}</span>}
        {ganho && <span className="inline-flex items-center gap-1"><Icon name="lock" size={12} /> pela Hotmart</span>}
      </div>
    </header>
  );
}
