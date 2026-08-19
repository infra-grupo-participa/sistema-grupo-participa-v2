'use client';

// Card individual do board — cor por status_financeiro (corDe), intensidade
// por urgência (urgencia, 0–3). Efeito via .gp-card (halo/borda/dot), tokens
// já definidos em globals.css — nenhum hex aqui.
//
// Redesign 2026-08-19 (squint test: o valor tem que saltar aos olhos, não o
// e-mail). Composição: nome (destaque) · badge origem · valor grande e
// dominante · tempo parado · selo de reserva. E-mail sai do card (LGPD +
// ruído visual) — permanece na ficha (FichaDrawer). Estágio da ativação vira
// `title` do card em vez de linha fixa — informação secundária, não estrutural.
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

/** Badge de origem por tom semântico (info=HM, purple=AURUM) — mesma pessoa
 *  pode ter 1 card por produto (ex.: Vania Thomaz: AURUM sem_tratativa + HM
 *  quitado, valores distintos). Precisa saltar aos olhos para não parecer
 *  duplicata — cor + peso maior que um badge neutro genérico. */
const ORIGEM_CLASSE: Record<CardComEfeito['origem'], string> = {
  HM: 'bg-[var(--info-subtle)] text-[var(--info)] border border-[var(--info-border)]',
  AURUM: 'bg-[var(--purple-subtle)] text-[var(--purple)] border border-[var(--purple-border)]',
};

/** Faixa visual do tempo parado — calibrada pela distribuição real medida em
 *  19/08 (305 cards: até 7d=114, 8–30d=131, 31–60d=44, nenhum acima de 60d).
 *  Sem faixa "muito antigo": não existe caso real acima de 60 dias hoje. */
function tomParado(dias: number): 'discreto' | 'atencao' | 'forte' {
  if (dias <= 7) return 'discreto';
  if (dias <= 30) return 'atencao';
  return 'forte';
}

const TEXTO_PARADO: Record<ReturnType<typeof tomParado>, string> = {
  discreto: 'text-[var(--fg-3)]',
  atencao: 'text-[var(--yellow)]',
  forte: 'text-[var(--red)]',
};

export function CardBoardView({ card, onOpen }: { card: CardComEfeito; onOpen: (id: string) => void }) {
  const { conta } = card;
  const dias = card.diasNoEstagio;
  const titleEstagio = conta.estagio_nome ? `Situação na ativação: ${conta.estagio_nome}` : undefined;

  return (
    <button
      type="button"
      onClick={() => onOpen(conta.contato_hm_id)}
      className={`gp-card ${TOM_CLASSE[card.cor]} gp-card--u${card.urgencia} w-full text-left p-3 cursor-pointer transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2`}
      aria-label={`Abrir ficha de ${conta.nome}`}
      title={titleEstagio}
    >
      <div className="relative z-[1] flex items-start justify-between gap-2">
        <div className="min-w-0 flex items-center gap-1.5">
          <span className="gp-card__dot" aria-hidden />
          <span className="truncate text-[13px] font-semibold text-[var(--fg)]" title={conta.nome || undefined}>{conta.nome || '—'}</span>
        </div>
        <span className={`shrink-0 text-[10px] font-bold uppercase tracking-wide rounded-[var(--r-sm)] px-1.5 py-0.5 ${ORIGEM_CLASSE[card.origem]}`}>
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

      {/* Valor: elemento dominante do card (squint test) — fonte maior que
          nome/badge/status, únicos números que precisam saltar aos olhos. */}
      <div className="relative z-[1] mt-2">
        <div className="text-[10px] text-[var(--fg-3)]">Falta pagar</div>
        <div className="text-[20px] font-extrabold tabular leading-tight text-[var(--fg)]">
          {conta.saldo_a_pagar == null ? '—' : fmtBRLc(conta.saldo_a_pagar)}
        </div>
      </div>

      <div className="relative z-[1] mt-1.5 flex items-center justify-between gap-2">
        <span className="text-[10px] font-medium text-[var(--fg-3)]">{statusLabel(conta.status_financeiro)}</span>
        {dias != null && (
          <span className={`shrink-0 text-[10px] font-semibold tabular ${TEXTO_PARADO[tomParado(dias)]}`}>
            parado há {dias}d
          </span>
        )}
      </div>

      {(conta.dias_atraso ?? 0) > 0 ? (
        <div className="relative z-[1] mt-1.5 flex items-center gap-1 text-[10px] font-semibold text-[var(--red)]">
          <Icon name="alert" size={11} /> {conta.dias_atraso}d em atraso
        </div>
      ) : conta.vencimento ? (
        <div className="relative z-[1] mt-1.5 text-[10px] tabular text-[var(--fg-3)]">vence {fmtData(conta.vencimento)}</div>
      ) : null}
    </button>
  );
}
