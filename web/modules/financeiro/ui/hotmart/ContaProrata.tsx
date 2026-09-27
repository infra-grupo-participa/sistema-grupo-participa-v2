'use client';

// "A conta do pro rata" — o mesmo recibo na ficha do board e no diagnóstico da Calculadora (pedido do João, 27/09:
// "clicou na tela do aluno, a gente tem que ver o que ele tem que pagar… ele gastou tanto, por isso vai pagar esse
// valor… e mostrar o que a gente falou para calcular"). Os números vêm do banco (fn_fin_prorata_hm /
// fn_fin_prorata_diagnostico); aqui só se explica a conta, de cima para baixo, com o valor a pagar no fim.
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import { explicarProrata, type ContaProrata as Conta } from '../../domain/prorata-hm';

export function ContaProrata({ c }: { c: Conta }) {
  const linhas: [string, string, string?][] = [
    [
      'Pagou no HM neste ciclo',
      fmtBRLc(c.pago),
      `${c.pagamentos} pagamento${c.pagamentos === 1 ? '' : 's'}${c.formas ? ` · ${c.formas}` : ''}${
        c.inicioCiclo && c.vencimento ? ` · de ${fmtData(c.inicioCiclo)} a ${fmtData(c.vencimento)}` : ''}`,
    ],
    ['Meses cheios de acesso que faltam', String(c.meses), c.vencimento ? `acesso vence em ${fmtData(c.vencimento)}` : undefined],
    ['Crédito', fmtBRLc(c.credito), `${fmtBRLc(c.pago)} × ${c.meses} ÷ 12`],
    ['Valor do Programa', fmtBRLc(c.valorPrograma), `${fmtBRLc(c.valorPrograma)} − ${fmtBRLc(c.credito)} de crédito`],
  ];
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)]">
      <div className="px-3 pt-3 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">A conta do pro rata</div>
      <dl className="divide-y divide-[var(--border)] px-3">
        {linhas.map(([k, v, d]) => (
          <div key={k} className="flex items-baseline justify-between gap-3 py-2">
            <dt className="text-sm text-[var(--fg-2)]">
              {k}
              {d && <span className="block text-[11px] text-[var(--fg-4)]">{d}</span>}
            </dt>
            <dd className="tabular text-sm font-medium text-[var(--fg)]">{v}</dd>
          </div>
        ))}
      </dl>
      <div className="flex items-baseline justify-between gap-3 rounded-b-[var(--r-lg)] border-t border-[var(--border-strong)] bg-[var(--surface-3)] px-3 py-3">
        <span className="text-sm font-semibold text-[var(--fg)]">Valor a pagar</span>
        <strong className="tabular text-2xl font-bold text-[var(--accent)]">{fmtBRLc(c.diferenca)}</strong>
      </div>
      <p className="px-3 py-2 text-sm leading-relaxed text-[var(--fg-2)]">{explicarProrata(c)}</p>
      <p className="px-3 pb-3 text-[11px] text-[var(--fg-4)]">
        Regra combinada (João e Isabela): crédito = o que pagou no HM no ciclo atual × meses cheios que faltam do acesso ÷ 12;
        valor a pagar = {fmtBRLc(c.valorPrograma)} − crédito. O vencimento vem da turma. Acelera Holding não entra.
      </p>
    </div>
  );
}
