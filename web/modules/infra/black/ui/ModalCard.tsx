'use client';

// Modal do card da Visão geral (molde do modal canônico). Sub-abas FIXAS em todo card: Por funil · Por canal ·
// Por fase · Por dia · Por criativo · Perfil. A que não se aplica ao card diz isso, em vez de sumir (o lugar de
// cada coisa não muda de um card para outro). Cada linha recalcula a MESMA métrica do card no recorte da linha.
import { useState } from 'react';
import { Modal } from '@/shared/ui/components';
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { filtrarDias, filtrarLinhas } from '../domain/metricas';
import { diaDe } from '../domain/recorte';
import { FASES, FUNIS, ROTULO_CANAL, ROTULO_FASE, ROTULO_FUNIL, type DesempenhoDia, type LinhaPerfil, type Valor } from '../domain/tipos';
import type { FormatoMetrica } from '../domain/jornada';
import type { DadosTela } from './contexto';
import { formatar, Numero } from './pecas';
import { PerfilLeads } from './perfil/PerfilLeads';

export type SubAbaModal = 'funil' | 'canal' | 'fase' | 'dia' | 'criativo' | 'perfil';
const SUBABAS: { k: SubAbaModal; l: string }[] = [
  { k: 'funil', l: 'Por funil' }, { k: 'canal', l: 'Por canal' }, { k: 'fase', l: 'Por fase' },
  { k: 'dia', l: 'Por dia' }, { k: 'criativo', l: 'Por criativo' }, { k: 'perfil', l: 'Perfil' },
];

export interface CardDef {
  id: string;
  rotulo: string;
  formato: FormatoMetrica;
  /** A métrica do card, recalculável em qualquer recorte de dias e cadastros. */
  medir: (dias: DesempenhoDia[], linhas: LinhaPerfil[]) => Valor;
  /** Sub-abas que fazem sentido para este card. */
  aplica: SubAbaModal[];
  dica?: string;
}

interface Linha { chave: string; rotulo: string; valor: Valor; anuncioId?: string }
const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export function ModalCard({ d, card, onClose }: { d: DadosTela; card: CardDef | null; onClose: () => void }) {
  const [sub, setSub] = useState<SubAbaModal>('funil');
  if (!card) return null;
  const ativa = card.aplica.includes(sub) ? sub : card.aplica[0] ?? 'funil';
  const { idx } = d;
  const canalAtual = { canal: d.recorte.canal };
  const funilAtual = { funil: d.recorte.funil };

  // Variação de hoje contra ontem, no recorte de funil e canal.
  const hoje = d.periodo.ate; const ontem = deslocarDia(hoje, -1);
  const doDia = (dia: string) => card.medir(
    filtrarDias(d.diasTodos.filter((x) => x.dia === dia), idx, { ...funilAtual, ...canalAtual }),
    filtrarLinhas(d.linhasTodas.filter((l) => diaDe(l.criadoEm) === dia), { ...funilAtual, ...canalAtual }),
  );
  const vHoje = doDia(hoje); const vOntem = doDia(ontem);
  const variacao = vHoje !== null && vOntem !== null && vOntem !== 0 ? (vHoje - vOntem) / vOntem : null;

  const linhas = (): Linha[] => {
    if (ativa === 'funil') return FUNIS.map((f) => ({
      chave: f, rotulo: ROTULO_FUNIL[f],
      valor: card.medir(filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: f, ...canalAtual }), filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: f, ...canalAtual })),
    }));
    if (ativa === 'canal') return (['meta', 'google'] as const).map((c) => ({
      chave: c, rotulo: ROTULO_CANAL[c],
      valor: card.medir(filtrarDias(d.diasPeriodoSemFiltro, idx, { ...funilAtual, canal: c }), filtrarLinhas(d.linhasPeriodoSemFiltro, { ...funilAtual, canal: c })),
    }));
    if (ativa === 'fase') return FASES.map((f) => ({
      chave: f, rotulo: ROTULO_FASE[f],
      valor: card.medir(d.dias.filter((x) => idx.campanhaDoAnuncio(x.anuncioId)?.fase === f), d.linhas.filter((l) => (l.campanhaId ? idx.campanha.get(l.campanhaId)?.fase : null) === f)),
    }));
    if (ativa === 'dia') return d.diasPeriodo.map((dia) => ({
      chave: dia, rotulo: dataCurta(dia),
      valor: card.medir(d.dias.filter((x) => x.dia === dia), d.linhas.filter((l) => diaDe(l.criadoEm) === dia)),
    }));
    if (ativa === 'criativo') {
      const ids = [...new Set(d.dias.map((x) => x.anuncioId))];
      return ids.map((id) => ({
        chave: id, anuncioId: id, rotulo: idx.anuncio.get(id)?.nome ?? id,
        valor: card.medir(d.dias.filter((x) => x.anuncioId === id), d.linhas.filter((l) => l.anuncioId === id)),
      })).sort((a, b) => (b.valor ?? -Infinity) - (a.valor ?? -Infinity));
    }
    return [];
  };

  const lista = ativa === 'perfil' ? [] : linhas();
  const max = Math.max(0, ...lista.map((l) => (l.valor !== null && l.valor > 0 ? l.valor : 0)));

  return (
    <Modal open onClose={onClose} title={card.rotulo} width="max-w-4xl">
      <div className="space-y-3">
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
          <span className="text-2xl font-bold text-[var(--fg)]"><Numero valor={card.medir(d.dias, d.linhas)} formato={card.formato} /></span>
          <span className="text-xs text-[var(--fg-3)]">
            Hoje ({dataCurta(hoje)}): {formatar(vHoje, card.formato)} · ontem: {formatar(vOntem, card.formato)}
            {variacao !== null ? ` · variação ${variacao >= 0 ? '+' : ''}${formatar(variacao, 'pct')}` : ''}
          </span>
        </div>
        {card.dica && <p className="text-xs text-[var(--fg-3)]">{card.dica}</p>}

        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Detalhar por">
          {SUBABAS.map((s) => (
            <button key={s.k} type="button" aria-pressed={ativa === s.k} onClick={() => setSub(s.k)}
              className={'min-h-9 rounded-[var(--r-md)] px-3 text-xs ' + (ativa === s.k ? 'bg-[var(--accent)] font-semibold text-black' : 'bg-[var(--surface-3)] text-[var(--fg-2)] hover:text-[var(--fg)]')}>
              {s.l}
            </button>
          ))}
        </div>

        {!card.aplica.includes(sub) ? (
          <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Não se aplica a este card.</p>
        ) : ativa === 'perfil' ? (
          <PerfilLeads d={d} linhas={d.linhas} />
        ) : (
          <ul className="space-y-1.5">
            {lista.map((l) => (
              <li key={l.chave}>
                <div className="flex items-center gap-3 text-sm">
                  {l.anuncioId ? (
                    <button type="button" className="min-w-0 flex-1 break-words text-left text-[var(--fg-2)] underline-offset-2 hover:text-[var(--fg)] hover:underline"
                      onClick={() => { onClose(); d.irPara({ aba: 'criativos', criativos: { anuncio: l.anuncioId } }); d.abrirGaveta({ tipo: 'criativo', id: l.anuncioId! }); }}>
                      {l.rotulo}
                    </button>
                  ) : <span className="min-w-0 flex-1 break-words text-[var(--fg-2)]">{l.rotulo}</span>}
                  <span className="shrink-0 text-[var(--fg)]"><Numero valor={l.valor} formato={card.formato} animado={false} /></span>
                </div>
                <div className="mt-0.5 h-1 overflow-hidden rounded-full bg-[var(--surface-4)]">
                  <div className="atm-historico-barra h-full rounded-full bg-[var(--accent)]" style={{ width: max > 0 && l.valor !== null && l.valor > 0 ? `${(l.valor / max) * 100}%` : '0%' }} />
                </div>
              </li>
            ))}
            {lista.length === 0 && <li className="text-sm text-[var(--fg-3)]">Sem dado no recorte.</li>}
          </ul>
        )}
      </div>
    </Modal>
  );
}
