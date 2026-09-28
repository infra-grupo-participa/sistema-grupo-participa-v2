'use client';

// "Pagaram o Programa e não têm card no board" — dinheiro que entrou sem cadastro na ativação. Só visível e exportável:
// quem cria o card é o sistema de ativação.
import { useEffect, useState } from 'react';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import type { PagouSemCard } from '../domain/programa-sem-card';
import { celulaCsv } from '../domain/hotmart';

export function ProgramaSemCard({ repo }: { repo: FinanceiroRepository }) {
  const [dados, setDados] = useState<PagouSemCard[] | null>(null);
  const [aberto, setAberto] = useState(false);
  useEffect(() => {
    let vivo = true;
    repo.loadProgramaSemCard().then((d) => { if (vivo) setDados(d); }).catch(() => { if (vivo) setDados([]); });
    return () => { vivo = false; };
  }, [repo]);
  if (!dados?.length) return null;
  const total = dados.reduce((s, d) => s + d.valor, 0);
  const fora = dados.filter((d) => d.fora_do_catalogo).length;
  return (
    <section className="mb-3 rounded-[var(--r-lg)] border border-[var(--red-border)] bg-[var(--red-subtle)]">
      <div className="flex flex-wrap items-center gap-2 px-3 py-2">
        <button type="button" onClick={() => setAberto(!aberto)} aria-expanded={aberto} className="text-left text-sm font-semibold text-[var(--red)]">
          {dados.length} pagaram o Programa e não têm card no board · {fmtBRL(total)} {aberto ? '▾' : '▸'}
        </button>
        {fora > 0 && <span className="text-[11px] text-[var(--fg-2)]">{fora} por oferta fora do catálogo</span>}
        <button type="button" onClick={() => exportar(dados)}
          className="ml-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)]">
          Baixar lista
        </button>
      </div>
      {aberto && (
        <div className="overflow-x-auto border-t border-[var(--red-border)] bg-[var(--surface)]">
          <table className="w-full min-w-[640px] text-xs">
            <thead><tr className="text-left text-[10px] uppercase tracking-wide text-[var(--fg-3)]">
              <th className="px-3 py-1.5 font-medium">Pessoa</th><th className="px-2 py-1.5 font-medium">Ação</th>
              <th className="px-2 py-1.5 font-medium">Pagou em</th><th className="px-2 py-1.5 font-medium text-right">Valor</th>
              <th className="px-3 py-1.5 font-medium">Oferta</th>
            </tr></thead>
            <tbody>
              {dados.map((d) => (
                <tr key={d.email} className="border-t border-[var(--border)]">
                  <td className="px-3 py-1.5"><div className="font-medium text-[var(--fg)]">{d.nome ?? '—'}</div><div className="text-[10px] text-[var(--fg-3)]">{d.email}{d.telefone ? ` · ${d.telefone}` : ''}</div></td>
                  <td className="px-2 py-1.5">{d.acao ?? '—'}</td>
                  <td className="tabular px-2 py-1.5">{fmtData(d.primeira)}</td>
                  <td className="tabular px-2 py-1.5 text-right">{fmtBRL(d.valor)}</td>
                  <td className="px-3 py-1.5 text-[11px]">{d.ofertas}{d.fora_do_catalogo ? <span className="ml-1 text-[var(--red)]">(fora do catálogo)</span> : null}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function exportar(dados: PagouSemCard[]) {
  const col: [string, (d: PagouSemCard) => unknown][] = [
    ['Nome', (d) => d.nome], ['E-mail', (d) => d.email], ['Telefone', (d) => d.telefone], ['Ação', (d) => d.acao],
    ['Pagou em', (d) => d.primeira], ['Valor', (d) => d.valor.toFixed(2).replace('.', ',')], ['Ofertas', (d) => d.ofertas],
    ['Fora do catálogo', (d) => (d.fora_do_catalogo ? 'sim' : 'não')],
  ];
  const txt = [col.map(([n]) => n).join(';'), ...dados.map((d) => col.map(([, g]) => celulaCsv(g(d))).join(';'))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' }));
  a.download = 'programa-pago-sem-card.csv';
  a.click();
  URL.revokeObjectURL(a.href);
}
