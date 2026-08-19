'use client';

// Rodapé fixo com os 4 totais do board. Recalcula sobre o array filtrado —
// calcularTotais() é síncrono e puro, sem query nova ao trocar o filtro.
// semValorDefinido e perdaDetalhe SEMPRE aparecem quando > 0: dinheiro não
// pode sumir em silêncio atrás de um total arredondado.
import { KpiCard } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import type { Totais } from '../domain/totais';

export function RodapeTotais({ totais, totalCards }: { totais: Totais; totalCards: number }) {
  return (
    <div className="gp-print-hide sticky bottom-0 -mx-1 px-1 pt-3 pb-1 bg-gradient-to-t from-[var(--surface-0)] via-[var(--surface-0)] to-transparent">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5">
        <KpiCard label="Valor esperado" value={fmtBRL(totais.esperado)} bar="accent" hint="Em casa + na rua" />
        <KpiCard label="Na rua" value={fmtBRL(totais.naRua)} bar="purple" hint={totais.reservas ? `${totais.reservas} reserva(s) de vaga inclusa(s)` : undefined} />
        <KpiCard label="Em casa" value={fmtBRL(totais.emCasa)} bar="green" hint={`líquido ${fmtBRL(totais.emCasaLiquido)}`} />
        <KpiCard
          label="Perda"
          value={fmtBRL(totais.perda)}
          bar="red"
          hint={`devolvido ${fmtBRL(totais.perdaDetalhe.devolvido)} · não realizado ${fmtBRL(totais.perdaDetalhe.naoRealizado)}`}
        />
      </div>
      {/* Dinheiro/contas que não somam em nenhum dos 4 totais acima — nunca ficam invisíveis. */}
      {(totais.semValorDefinido > 0 || totais.segundaMetade.parceiros > 0) && (
        <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] text-[var(--fg-3)]">
          {totais.semValorDefinido > 0 && (
            <span>
              <strong className="text-[var(--yellow)] font-semibold">{totais.semValorDefinido}</strong> conta(s) sem valor definido — fora dos 4 totais (não é zero, é &quot;não sabemos&quot;)
            </span>
          )}
          {totais.segundaMetade.parceiros > 0 && (
            <span>2ª metade condicional: {fmtBRL(totais.segundaMetade.valor)} ({totais.segundaMetade.parceiros} parceiro(s), fora do esperado)</span>
          )}
          <span className="ml-auto tabular">{totalCards} card(s) no board</span>
        </div>
      )}
    </div>
  );
}
