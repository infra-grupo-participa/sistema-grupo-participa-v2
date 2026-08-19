'use client';

// Rodapé de totais do board. Recalcula sobre o array filtrado —
// calcularTotais() é síncrono e puro, sem query nova ao trocar o filtro.
// semValorDefinido e perdaDetalhe SEMPRE aparecem quando > 0: dinheiro não
// pode sumir em silêncio atrás de um total arredondado.
//
// Redesign 2026-08-19: deixou de ser `sticky` sobre o board — problema 4 do
// Marcio (rodapé flutuando por cima cortava cards). Agora é um bloco normal
// no fluxo, abaixo da área de scroll das colunas — nunca sobrepõe conteúdo.
// Também deixa explícito se o total é do RECORTE filtrado ou da carteira
// inteira (problema 6): sem isso "5 card(s) no board" parecia contradizer os
// 305 cards somados nos chips da timeline de ações.
import { KpiCard } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL } from '@/shared/ui/format';
import type { Totais } from '../domain/totais';

export function RodapeTotais({ totais, totalCards, filtroAtivo }: {
  totais: Totais;
  totalCards: number;
  /** Rótulo legível da ação/canal ativo na timeline (null = sem filtro, totais são da carteira). */
  filtroAtivo: string | null;
}) {
  return (
    <div className="gp-print-hide mt-3 pt-3 border-t border-[var(--border)]">
      <div className="mb-2 flex items-center gap-1.5 text-[11px] text-[var(--fg-3)]">
        {filtroAtivo ? (
          <>
            <Icon name="alert" size={12} className="text-[var(--accent)]" />
            <span>
              Filtrado por <strong className="text-[var(--accent)] font-semibold">{filtroAtivo}</strong> — totais abaixo somam
              <strong className="tabular text-[var(--fg-2)] font-semibold"> {totalCards} </strong>card(s), não a carteira inteira.
            </span>
          </>
        ) : (
          <span>Totais da carteira completa — <strong className="tabular text-[var(--fg-2)] font-semibold">{totalCards}</strong> card(s).</span>
        )}
      </div>
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
        </div>
      )}
    </div>
  );
}
