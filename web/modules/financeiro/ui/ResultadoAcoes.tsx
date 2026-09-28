'use client';

// Quadro "Resultado por ação" no topo do board: em cada ação/evento do Programa, quem entrou, quantos pagaram, quanto já
// entrou e quanto falta. Clicar numa linha filtra o board por aquela ação (mesmo filtro dos botões).
import { useMemo, useState } from 'react';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { CardComEfeito } from '../application/carregar-board';
import { resultadoPorAcao } from '../domain/resultado-acao';
import { chaveDaAcao, rotuloDaAcao } from './TimelineAcoes';

export function ResultadoAcoes({ cards, ativa, onSelecionar }: {
  cards: CardComEfeito[];
  ativa: string | null;
  onSelecionar: (chave: string | null) => void;
}) {
  const [aberto, setAberto] = useState(true);
  const linhas = useMemo(() => resultadoPorAcao(cards.map((c) => ({
    acaoNome: c.acaoNome, acaoData: c.acaoData, status: c.conta.status_financeiro,
    pago: c.conta.total_pago_bruto, saldo: c.conta.saldo_a_pagar,
  }))), [cards]);
  if (!linhas.length) return null;
  const tot = linhas.reduce((t, l) => ({ p: t.p + l.pessoas, g: t.g + l.pagaram, r: t.r + l.recebido, a: t.a + l.aReceber }), { p: 0, g: 0, r: 0, a: 0 });
  return (
    <section className="mb-3 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface)]">
      <button type="button" onClick={() => setAberto(!aberto)} aria-expanded={aberto}
        className="flex w-full items-center justify-between gap-2 px-3 py-2 text-left">
        <span className="text-sm font-semibold text-[var(--fg)]">Resultado por ação</span>
        <span className="tabular text-[11px] text-[var(--fg-3)]">{tot.p} pessoas · {tot.g} pagaram · {fmtBRL(tot.r)} recebido · {fmtBRL(tot.a)} a receber {aberto ? '▾' : '▸'}</span>
      </button>
      {aberto && (
        <div className="overflow-x-auto border-t border-[var(--border)]">
          <table className="w-full min-w-[640px] text-xs">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-wide text-[var(--fg-3)]">
                <th className="px-3 py-1.5 font-medium">Ação / evento</th>
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
                const chave = chaveDaAcao(l.acao === 'Sem ação identificada' ? null : l.acao);
                const ativo = ativa === chave;
                return (
                  <tr key={l.acao} onClick={() => onSelecionar(ativo ? null : chave)}
                    className={`cursor-pointer border-t border-[var(--border)] hover:bg-[var(--surface-2)] ${ativo ? 'bg-[var(--accent-subtle)]' : ''}`}>
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
