'use client';

// Recorrências: as cobranças futuras do bloco 2 (assinaturas e parcelas a vencer), uma linha por cobrança
// (antecipação + garantia da mesma cobrança juntas pela `ref`), com a situação de cada uma.
// Valor = a cobrança sem perda; Esperado (só quando há perda no cenário) = o que a grade soma.
// "Realizada" aparece para auditoria e não soma na grade; "fora da projeção" saiu da projeção; "coberta por recebimento
// informado" é a cobrança que um informado (bloco 5) já cobre — não soma, para não contar duas vezes. Nunca "devendo".
// O nome "Carteira" está reservado para outra tela.
import { useMemo, useState } from 'react';
import { Badge } from '@/shared/ui/components';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { CobrancaRecorrente, SituacaoReceber } from '../../domain/contas-receber';
import { SECAO_RECORRENCIAS, SITUACAO_RECEBER, TABELA_RECORRENCIAS } from './textos';

const T = TABELA_RECORRENCIAS;

const ORDEM: SituacaoReceber[] = ['a_receber', 'realizada', 'em_atraso_fora', 'coberta_informado'];

export function rotuloSituacao(s: string): string {
  if (s === 'a_receber') return SITUACAO_RECEBER.aReceber;
  if (s === 'realizada') return SITUACAO_RECEBER.realizada;
  if (s === 'em_atraso_fora') return SITUACAO_RECEBER.foraDaProjecao;
  if (s === 'coberta_informado') return SITUACAO_RECEBER.cobertaInformado;
  return s; // fora do contrato: mostra cru, não disfarça
}

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';

export function Recorrencias({ cobrancas }: { cobrancas: CobrancaRecorrente[] }) {
  const [filtro, setFiltro] = useState<SituacaoReceber | null>(null);
  const resumo = useMemo(() => {
    const r = new Map<string, { n: number; cents: number }>();
    for (const c of cobrancas) {
      const x = r.get(c.situacao) ?? { n: 0, cents: 0 };
      x.n += 1; x.cents += Math.round(c.valor * 100);
      r.set(c.situacao, x);
    }
    return r;
  }, [cobrancas]);
  // Com perda (cenário), a cobrança tem valor (bruto) e esperado; sem perda, uma coluna só.
  const comPerda = cobrancas.some((c) => Math.round(c.valor * 100) !== Math.round(c.esperado * 100));
  const nCols = comPerda ? 8 : 7;
  const visiveis = filtro ? cobrancas.filter((c) => c.situacao === filtro) : cobrancas;
  const botoes: { k: SituacaoReceber | null; l: string; n: number; v: number | null }[] = [
    { k: null, l: T.todas, n: cobrancas.length, v: null },
    ...ORDEM.map((s) => ({ k: s, l: rotuloSituacao(s), n: resumo.get(s)?.n ?? 0, v: (resumo.get(s)?.cents ?? 0) / 100 })),
  ];

  return (
    <section className="space-y-2" aria-labelledby="recorrencias-titulo">
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="recorrencias-titulo" className="text-sm font-semibold text-[var(--fg)]">{SECAO_RECORRENCIAS.titulo}</h2>
        {botoes.map((b) => (
          <button key={b.k ?? 'todas'} type="button" aria-pressed={filtro === b.k} onClick={() => setFiltro(b.k)}
            className={`rounded-[var(--r-sm)] border px-2 py-0.5 text-xs ${filtro === b.k ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`}>
            {b.l} <span className="tabular">{b.n}</span>{b.v != null && b.n > 0 ? <span className="tabular"> · {fmtBRLc(b.v)}</span> : null}
          </button>
        ))}
      </div>
      <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
        <table className="w-full border-collapse text-xs">
          <thead className="bg-[var(--surface-2)]">
            <tr>
              <th className={TH}>{T.cobrancaPrevista}</th><th className={TH}>{T.grupo}</th>
              <th className={TH}>{T.nome}</th><th className={TH}>{T.produto}</th>
              <th className={TH}>{T.caiNoCaixa}</th><th className={`${TH} text-right`}>{T.valor}</th>
              {comPerda && <th className={`${TH} text-right`}>{T.esperado}</th>}
              <th className={TH}>{T.situacao}</th>
            </tr>
          </thead>
          <tbody>
            {visiveis.length === 0 ? (
              <tr><td colSpan={nCols} className="px-2 py-2 text-[var(--fg-3)]">{T.nenhuma}</td></tr>
            ) : visiveis.map((c, i) => (
              <tr key={`${c.ref ?? 'sem-ref'}-${c.situacao}-${i}`} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
                <td className="px-2 py-1 tabular whitespace-nowrap">{fmtData(c.prevista)}</td>
                <td className="px-2 py-1 text-[var(--fg-2)]">{c.grupo}</td>
                <td className="px-2 py-1">{c.rotulo ?? '—'}</td>
                <td className="px-2 py-1 text-[var(--fg-2)]">{c.produto ?? '—'}</td>
                <td className="px-2 py-1 tabular whitespace-nowrap text-[var(--fg-2)]">{c.caixa.map(fmtData).join(' · ') || '—'}</td>
                <td className="px-2 py-1 text-right tabular whitespace-nowrap">{fmtBRLc(c.valor)}</td>
                {comPerda && <td className="px-2 py-1 text-right tabular whitespace-nowrap">{fmtBRLc(c.esperado)}</td>}
                <td className="px-2 py-1 whitespace-nowrap">
                  {/* Cor só no que pede atenção: saiu da projeção. O texto diz a situação; a cor não é o único sinal. */}
                  {c.situacao === 'em_atraso_fora' ? <Badge tone="warning">{rotuloSituacao(c.situacao)}</Badge> : rotuloSituacao(c.situacao)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
