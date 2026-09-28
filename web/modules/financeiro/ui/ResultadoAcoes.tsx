'use client';

// Quadro "Resultado" no topo do board: em cada ação/evento do Programa (ou turma de origem, ou canal), quem entrou,
// quantos pagaram, quanto já entrou e quanto falta. FECHADO por padrão (João, 28/09); ao abrir, botões trocam a visão.
// Na visão por ação, clicar numa linha filtra o board por aquela ação (mesmo filtro dos botões do topo).
import { useMemo, useState } from 'react';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { CardComEfeito } from '../application/carregar-board';
import { resultadoPorAcao } from '../domain/resultado-acao';
import { chaveDaAcao, rotuloDaAcao } from './TimelineAcoes';

type Visao = 'acao' | 'turma' | 'canal';
const VISOES: { k: Visao; l: string }[] = [
  { k: 'acao', l: 'Por ação' }, { k: 'turma', l: 'Por turma de origem' }, { k: 'canal', l: 'Por canal' },
];

export function ResultadoAcoes({ cards, ativa, onSelecionar }: {
  cards: CardComEfeito[];
  ativa: string | null;
  onSelecionar: (chave: string | null) => void;
}) {
  const [aberto, setAberto] = useState(false);
  const [visao, setVisao] = useState<Visao>('acao');
  const linhas = useMemo(() => {
    const r = resultadoPorAcao(cards.map((c) => ({
      acaoNome: visao === 'acao' ? c.acaoNome : visao === 'turma' ? (c.conta.turma ?? 'Sem turma') : (c.conta.canal ?? 'Sem canal'),
      acaoData: visao === 'acao' ? c.acaoData : null,
      status: c.conta.status_financeiro, pago: c.conta.total_pago_bruto, saldo: c.conta.saldo_a_pagar,
    })));
    // turma: T1 → T41 na ordem numérica (Aurum A1 → A11 depois); canal: pelo tamanho
    if (visao === 'turma') r.sort((a, b) => (Number(a.acao.replace(/\D/g, '')) || 999) - (Number(b.acao.replace(/\D/g, '')) || 999));
    if (visao === 'canal') r.sort((a, b) => b.pessoas - a.pessoas);
    return r;
  }, [cards, visao]);
  if (!linhas.length) return null;
  const tot = linhas.reduce((t, l) => ({ p: t.p + l.pessoas, g: t.g + l.pagaram, r: t.r + l.recebido, a: t.a + l.aReceber }), { p: 0, g: 0, r: 0, a: 0 });
  return (
    <section className="mb-3 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface)]">
      <button type="button" onClick={() => setAberto(!aberto)} aria-expanded={aberto}
        className="flex w-full items-center justify-between gap-2 px-3 py-2 text-left">
        <span className="text-sm font-semibold text-[var(--fg)]">Resultado por ação, turma e canal</span>
        <span className="tabular text-[11px] text-[var(--fg-3)]">{tot.p} pessoas · {tot.g} pagaram · {fmtBRL(tot.r)} recebido · {fmtBRL(tot.a)} a receber {aberto ? '▾' : '▸'}</span>
      </button>
      {aberto && (
        <div className="flex flex-wrap gap-1.5 border-t border-[var(--border)] px-3 py-2" role="tablist" aria-label="Agrupar resultado">
          {VISOES.map((v) => (
            <button key={v.k} type="button" role="tab" aria-selected={visao === v.k} onClick={() => setVisao(v.k)}
              className={`rounded-[var(--r-pill)] border px-2.5 py-1 text-xs font-medium ${visao === v.k ? 'border-[var(--border-accent)] bg-[var(--accent-subtle)] text-[var(--accent)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:border-[var(--border-strong)]'}`}>
              {v.l}
            </button>
          ))}
        </div>
      )}
      {aberto && (
        <div className="overflow-x-auto border-t border-[var(--border)]">
          <table className="w-full min-w-[640px] text-xs">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-wide text-[var(--fg-3)]">
                <th className="px-3 py-1.5 font-medium">{visao === 'acao' ? 'Ação / evento' : visao === 'turma' ? 'Turma de origem' : 'Canal'}</th>
                <th className="px-2 py-1.5 font-medium text-right">Pessoas</th>
                <th className="px-2 py-1.5 font-medium text-right">Pagaram</th>
                <th className="px-2 py-1.5 font-medium text-right">Quitados</th>
                <th className="px-2 py-1.5 font-medium text-right">Saíram</th>
                <th className="px-2 py-1.5 font-medium text-right">Recebido</th>
                <th className="px-3 py-1.5 font-medium text-right">A receber</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => {
                const chave = chaveDaAcao(l.acao === 'Sem identificação' ? null : l.acao);
                const clicavel = visao === 'acao';
                const ativo = clicavel && ativa === chave;
                return (
                  <tr key={l.acao} onClick={clicavel ? () => onSelecionar(ativo ? null : chave) : undefined}
                    className={`border-t border-[var(--border)] ${clicavel ? 'cursor-pointer hover:bg-[var(--surface-2)]' : ''} ${ativo ? 'bg-[var(--accent-subtle)]' : ''}`}>
                    <td className="px-3 py-1.5">
                      <span className="font-medium text-[var(--fg)]">{rotuloDaAcao(l.acao)}</span>
                      {l.data && <span className="ml-2 tabular text-[10px] text-[var(--fg-4)]">{fmtData(l.data)}</span>}
                    </td>
                    <td className="tabular px-2 py-1.5 text-right">{l.pessoas}</td>
                    <td className="tabular px-2 py-1.5 text-right">{l.pagaram}</td>
                    <td className="tabular px-2 py-1.5 text-right">{l.quitados}</td>
                    <td className="tabular px-2 py-1.5 text-right text-[var(--fg-3)]">{l.saidas}</td>
                    <td className="tabular px-2 py-1.5 text-right text-[var(--green)]">{fmtBRL(l.recebido)}</td>
                    <td className="tabular px-3 py-1.5 text-right">{fmtBRL(l.aReceber)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
