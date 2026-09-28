'use client';

// Oferta PAGA fora do catálogo (fn_fin_ofertas_sem_catalogo, 28/09/2026): o webhook grava a compra, mas o card não nasce
// e o pagamento não é lançado até alguém cadastrar a oferta. O banco já gerava alerta crítico e ninguém via — foi assim
// que os 39 do Programa ficaram sem card. Some sozinho quando a oferta entra no catálogo.
import { useEffect, useState } from 'react';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import type { OfertaSemCatalogo } from '../domain/programa-sem-card';

export function OfertasSemCatalogo({ repo, familia }: { repo: FinanceiroRepository; familia: 'HM' | 'AURUM' }) {
  const [dados, setDados] = useState<OfertaSemCatalogo[] | null>(null);
  const [aberto, setAberto] = useState(false);
  useEffect(() => {
    let vivo = true;
    repo.loadOfertasSemCatalogo().then((d) => { if (vivo) setDados(d); }).catch(() => { if (vivo) setDados([]); });
    return () => { vivo = false; };
  }, [repo]);
  const linhas = (dados ?? []).filter((d) => d.familia === familia);
  if (!linhas.length) return null;
  const valor = linhas.reduce((s, d) => s + d.valor, 0);
  const pessoas = linhas.reduce((s, d) => s + d.pessoas, 0);
  return (
    <section className="mb-3 rounded-[var(--r-lg)] border border-[var(--yellow-border,var(--border))] bg-[var(--yellow-subtle,var(--surface))]">
      <button type="button" onClick={() => setAberto(!aberto)} aria-expanded={aberto}
        className="flex w-full items-center gap-2 px-3 py-2 text-left">
        <span className="min-w-0 flex-1 truncate text-sm font-semibold text-[var(--yellow)]">
          {linhas.length} {linhas.length === 1 ? 'oferta paga' : 'ofertas pagas'} fora do catálogo · {pessoas} {pessoas === 1 ? 'pessoa' : 'pessoas'} · {fmtBRL(valor)} {aberto ? '▾' : '▸'}
        </span>
        <span className="hidden shrink-0 text-[11px] text-[var(--fg-3)] sm:inline">o card não anda até a oferta ser cadastrada</span>
      </button>
      {aberto && (
        <div className="overflow-x-auto border-t border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[640px] text-xs">
            <thead><tr className="text-left text-[10px] uppercase tracking-wide text-[var(--fg-3)]">
              <th className="px-3 py-1.5 font-medium">Oferta</th><th className="px-2 py-1.5 font-medium">Quem pagou</th>
              <th className="px-2 py-1.5 font-medium text-right">Pagamentos</th><th className="px-2 py-1.5 font-medium text-right">Valor</th>
              <th className="px-3 py-1.5 font-medium">Quando</th>
            </tr></thead>
            <tbody>
              {linhas.map((d) => (
                <tr key={d.oferta} className="border-t border-[var(--border)]">
                  <td className="px-3 py-1.5"><div className="font-mono font-semibold text-[var(--fg)]">{d.oferta}</div><div className="text-[10px] text-[var(--fg-3)]">{d.produto}</div></td>
                  <td className="px-2 py-1.5 text-[var(--fg-2)]">{d.nomes ?? '—'}</td>
                  <td className="tabular px-2 py-1.5 text-right">{d.pagamentos}</td>
                  <td className="tabular px-2 py-1.5 text-right">{fmtBRL(d.valor)}</td>
                  <td className="tabular px-3 py-1.5">{d.primeira === d.ultima ? fmtData(d.primeira) : `${fmtData(d.primeira)} a ${fmtData(d.ultima)}`}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="border-t border-[var(--border)] px-3 py-2 text-[11px] text-[var(--fg-3)]">
            Para o card nascer, a oferta precisa entrar no catálogo com a categoria (sinal, saldo ou compra cheia).
          </p>
        </div>
      )}
    </section>
  );
}
