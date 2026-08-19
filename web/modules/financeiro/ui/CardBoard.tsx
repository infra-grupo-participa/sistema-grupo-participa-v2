'use client';

// Card individual do board — cor por status_financeiro (corDe), intensidade
// por urgência (urgencia, 0–3). Efeito via .gp-card (halo/borda/dot), tokens
// já definidos em globals.css — nenhum hex aqui.
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { CardComEfeito } from '../application/carregar-board';
import { statusLabel } from '../domain/financeiro';

const TOM_CLASSE: Record<CardComEfeito['cor'], string> = {
  verde: 'gp-card--verde',
  azul: 'gp-card--azul',
  vermelho: 'gp-card--vermelho',
  neutro: 'gp-card--neutro',
};

export function CardBoardView({ card, onOpen }: { card: CardComEfeito; onOpen: (id: string) => void }) {
  const { conta } = card;
  return (
    <button
      type="button"
      onClick={() => onOpen(conta.contato_hm_id)}
      className={`gp-card ${TOM_CLASSE[card.cor]} gp-card--u${card.urgencia} w-full text-left p-3 cursor-pointer transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2`}
      aria-label={`Abrir ficha de ${conta.nome}`}
    >
      <div className="relative z-[1] flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 min-w-0">
            <span className="gp-card__dot" aria-hidden />
            <span className="truncate text-[13px] font-semibold text-[var(--fg)]" title={conta.nome || undefined}>{conta.nome || '—'}</span>
          </div>
          <div className="mt-0.5 truncate text-[11px] text-[var(--fg-3)]" title={conta.email}>{conta.email}</div>
        </div>
        <span className="shrink-0 text-[10px] font-semibold uppercase tracking-wide rounded-[var(--r-sm)] px-1.5 py-0.5 bg-[var(--surface-3)] text-[var(--fg-3)]">
          {card.origem}
        </span>
      </div>

      {/* Reserva de vaga (só sinal pago): esperado mais frágil que saldo em
          curso — R$ 300 de um pacote de R$ 15.000. Marca própria, não some
          do total (reserva ENTRA em esperado/naRua). */}
      {card.reserva && (
        <div className="relative z-[1] mt-1.5">
          <span className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--yellow)]">
            <Icon name="alert" size={10} /> Reserva de vaga
          </span>
        </div>
      )}

      <div className="relative z-[1] mt-2 flex items-end justify-between gap-2">
        <div className="min-w-0">
          <div className="text-[10px] text-[var(--fg-3)]">Falta pagar</div>
          <div className="text-[14px] font-bold tabular text-[var(--fg)]">
            {conta.saldo_a_pagar == null ? '—' : fmtBRLc(conta.saldo_a_pagar)}
          </div>
        </div>
        <span className="shrink-0 text-[10px] font-medium text-[var(--fg-3)]">{statusLabel(conta.status_financeiro)}</span>
      </div>

      {(conta.dias_atraso ?? 0) > 0 ? (
        <div className="relative z-[1] mt-1.5 flex items-center gap-1 text-[10px] font-semibold text-[var(--red)]">
          <Icon name="alert" size={11} /> {conta.dias_atraso}d em atraso
        </div>
      ) : conta.vencimento ? (
        <div className="relative z-[1] mt-1.5 text-[10px] tabular text-[var(--fg-3)]">vence {fmtData(conta.vencimento)}</div>
      ) : null}

      {conta.estagio_nome && (
        <div className="relative z-[1] mt-1.5 truncate text-[10px] text-[var(--fg-3)]" title={`Situação na ativação: ${conta.estagio_nome}`}>
          <span className="opacity-60">ativação:</span> {conta.estagio_nome}
        </div>
      )}
    </button>
  );
}
