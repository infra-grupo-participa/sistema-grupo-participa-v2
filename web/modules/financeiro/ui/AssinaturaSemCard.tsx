'use client';

// "Pagam ou pagaram a mensalidade do HM antigo e não têm card" (z52, decisão 2 do Marcio, 28/09): lista própria com a
// turma de origem — essa gente NÃO ganha card. Mesmo carregamento e exportação do bloco "pagaram o Programa sem card".
import { useEffect, useState } from 'react';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import { totaisAssinaturaSemCard, type AssinaturaHMSemCard } from '../domain/assinatura-hm';
import { celulaCsv } from '../domain/hotmart';

export function AssinaturaSemCard({ repo }: { repo: FinanceiroRepository }) {
  const [dados, setDados] = useState<AssinaturaHMSemCard[] | null>(null);
  const [aberto, setAberto] = useState(false);
  useEffect(() => {
    let vivo = true;
    repo.loadAssinaturaHMSemCard().then((d) => { if (vivo) setDados(d); }).catch(() => { if (vivo) setDados([]); });
    return () => { vivo = false; };
  }, [repo]);
  if (!dados?.length) return null;
  const t = totaisAssinaturaSemCard(dados);
  return (
    <section className="mb-3 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)]">
      <div className="flex items-center gap-2 px-3 py-2">
        <button type="button" onClick={() => setAberto(!aberto)} aria-expanded={aberto} className="min-w-0 flex-1 truncate text-left text-sm font-semibold text-[var(--fg)]">
          {t.pessoas} pagam ou pagaram a mensalidade do HM antigo e não têm card · {fmtBRL(t.pago)} · {t.aindaPagam} ainda {t.aindaPagam === 1 ? 'paga' : 'pagam'} {aberto ? '▾' : '▸'}
        </button>
        <button type="button" onClick={() => exportar(dados)}
          className="shrink-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)]">
          Baixar lista
        </button>
      </div>
      {aberto && (
        <div className="overflow-x-auto border-t border-[var(--border)] bg-[var(--surface)]">
          <table className="w-full min-w-[820px] text-xs">
            <thead><tr className="text-left text-[10px] uppercase tracking-wide text-[var(--fg-3)]">
              <th className="px-3 py-1.5 font-medium">Pessoa</th><th className="px-2 py-1.5 font-medium">Turma de origem</th>
              <th className="px-2 py-1.5 font-medium">1ª mensalidade</th><th className="px-2 py-1.5 font-medium">Última paga</th>
              <th className="px-2 py-1.5 font-medium text-right">Pagas</th><th className="px-2 py-1.5 font-medium text-right">Total pago</th>
              <th className="px-2 py-1.5 font-medium">Situação</th><th className="px-3 py-1.5 font-medium text-right">Atraso 120 d</th>
            </tr></thead>
            <tbody>
              {dados.map((d) => (
                <tr key={d.pessoa_chave} className="border-t border-[var(--border)]">
                  <td className="px-3 py-1.5">
                    <div className="font-medium text-[var(--fg)]">{d.nome ?? '—'}</div>
                    <div className="text-[10px] text-[var(--fg-3)]">{d.emails.join(', ')}{d.telefone ? ` · ${d.telefone}` : ''}</div>
                  </td>
                  <td className="px-2 py-1.5">
                    <div>{d.turma_origem ?? 'sem origem'}</div>
                    {d.turma_origem && d.origem_regra && <div className="text-[10px] text-[var(--fg-3)]">{d.origem_regra}</div>}
                  </td>
                  <td className="tabular px-2 py-1.5">{fmtData(d.primeira)}</td>
                  <td className="tabular px-2 py-1.5">{fmtData(d.ultima_paga)}</td>
                  <td className="tabular px-2 py-1.5 text-right">{d.mensalidades_pagas}</td>
                  <td className="tabular px-2 py-1.5 text-right">{fmtBRL(d.pago)}</td>
                  <td className="px-2 py-1.5">{d.ainda_paga ? 'ainda paga' : 'parou'}</td>
                  <td className={`tabular px-3 py-1.5 text-right ${d.atraso_120d_n > 0 ? 'text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
                    {d.atraso_120d_n > 0 ? `${d.atraso_120d_n} · ${fmtBRL(d.atraso_120d_valor)}` : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function exportar(dados: AssinaturaHMSemCard[]) {
  const reais = (n: number) => n.toFixed(2).replace('.', ',');
  const col: [string, (d: AssinaturaHMSemCard) => unknown][] = [
    ['Nome', (d) => d.nome], ['E-mails', (d) => d.emails.join(', ')], ['Documento', (d) => d.documento], ['Telefone', (d) => d.telefone],
    ['Turma de origem', (d) => d.turma_origem ?? 'sem origem'], ['Regra da origem', (d) => d.origem_regra],
    ['Turma pelo calendário', (d) => d.turma_calendario], ['Turma pelo cadastro', (d) => d.turma_cadastro],
    ['1ª mensalidade', (d) => d.primeira], ['Última paga', (d) => d.ultima_paga], ['Mensalidades pagas', (d) => d.mensalidades_pagas],
    ['Total pago', (d) => reais(d.pago)], ['Situação', (d) => (d.ainda_paga ? 'ainda paga' : 'parou')],
    ['Em atraso 120 d (qtd)', (d) => d.atraso_120d_n], ['Em atraso 120 d (R$)', (d) => reais(d.atraso_120d_valor)],
  ];
  const txt = [col.map(([n]) => n).join(';'), ...dados.map((d) => col.map(([, g]) => celulaCsv(g(d))).join(';'))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' }));
  a.download = 'hm-mensalidade-antiga-sem-card.csv';
  a.click();
  URL.revokeObjectURL(a.href);
}
