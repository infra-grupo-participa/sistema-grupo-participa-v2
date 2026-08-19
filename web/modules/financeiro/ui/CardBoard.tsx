'use client';

// Card individual do board — cor por status_financeiro (corDe), intensidade
// por urgência (urgencia, 0–3). Efeito via .gp-card (halo/borda/dot), tokens
// já definidos em globals.css — nenhum hex aqui.
//
// Redesign 2026-08-19 (2ª passada — acabamento). 3 níveis de hierarquia:
// identidade (nome + origem) → dinheiro (valor + progresso rotulado) →
// contexto (status/reserva/prazo em cima, vendedor/tempo parado no rodapé).
// E-mail continua fora do card (LGPD + ruído) — permanece na ficha
// (FichaDrawer). Estágio da ativação vira `title` do card em vez de linha
// fixa — informação secundária, não estrutural.
import { Icon } from '@/shared/ui/icons';
import { ProgressBar } from '@/shared/ui/components';
import { fmtBRLc, fmtRelativo } from '@/shared/ui/format';
import type { CardComEfeito } from '../application/carregar-board';
import { statusLabel } from '../domain/financeiro';

const TOM_CLASSE: Record<CardComEfeito['cor'], string> = {
  verde: 'gp-card--verde',
  azul: 'gp-card--azul',
  vermelho: 'gp-card--vermelho',
  neutro: 'gp-card--neutro',
};

/** Tom da barra de progresso segue a mesma leitura semântica da cor do card
 *  (corDe) — quitado/em dia = verde, em acompanhamento = azul, vencido =
 *  vermelho, sem acordo/incalculável = neutro. Nunca âmbar: --accent é
 *  exclusivo de seleção/ação, não de status. */
const TOM_BARRA: Record<CardComEfeito['cor'], 'green' | 'info' | 'red' | 'neutral'> = {
  verde: 'green',
  azul: 'info',
  vermelho: 'red',
  neutro: 'neutral',
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
  discreto: 'text-[var(--fg-4)]',
  atencao: 'text-[var(--yellow)]',
  forte: 'text-[var(--red)]',
};

export function CardBoardView({ card, onOpen }: { card: CardComEfeito; onOpen: (id: string) => void }) {
  const { conta } = card;
  const dias = card.diasNoEstagio;
  const titleEstagio = conta.estagio_nome ? `Situação na ativação: ${conta.estagio_nome}` : undefined;

  const pago = conta.total_pago_bruto ?? 0;
  const temPacote = conta.pacote != null && conta.pacote > 0;
  const pct = conta.pago_pct ?? (temPacote ? (pago / (conta.pacote as number)) * 100 : null);
  // 7 casos reais passam de 100% (pró-rata com pacote recalculado menor que o
  // já pago) — a barra clampa em 100 e o excedente vira um selo discreto ao
  // lado, nunca estoura a trilha nem some silenciosamente.
  const excedeu = pct != null && pct > 100;

  const quitado = conta.status_financeiro === 'quitado';
  const emAtraso = (conta.dias_atraso ?? 0) > 0;
  const venceRel = conta.vencimento ? fmtRelativo(conta.vencimento) : null;

  return (
    <button
      type="button"
      onClick={() => onOpen(conta.contato_hm_id)}
      className={`gp-card ${TOM_CLASSE[card.cor]} gp-card--u${card.urgencia} w-full text-left p-4 cursor-pointer shadow-[var(--shadow-sm)] transition-[transform,box-shadow] duration-150 hover:-translate-y-0.5 hover:shadow-[var(--shadow-md)] focus-visible:ring-2`}
      aria-label={`Abrir ficha de ${conta.nome}, ${card.origem}, ${statusLabel(conta.status_financeiro)}${
        conta.saldo_a_pagar != null ? `, falta pagar ${fmtBRLc(conta.saldo_a_pagar)}` : ''
      }`}
      title={titleEstagio}
    >
      {/* Nível 1 — identidade: nome + origem. O badge de origem precisa
          continuar saltando (mesma pessoa pode ter 2 cards, um por produto). */}
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
        <div className="relative z-[1] mt-2">
          <span className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--yellow)]">
            <Icon name="alert" size={10} /> Reserva de vaga
          </span>
        </div>
      )}

      {/* Nível 2 — dinheiro: elemento dominante do card (squint test). Valor
          restante em destaque; progresso do pacote logo abaixo, com valor
          absoluto ("R$ 300 de R$ 15.000") — % sozinho não distingue um
          pacote de 15 mil de um de 60 mil. */}
      <div className="relative z-[1] mt-3">
        <div className="text-[10px] font-medium uppercase tracking-wide text-[var(--fg-3)]">
          {quitado ? 'Quitado' : 'Falta pagar'}
        </div>
        <div className="text-[20px] font-extrabold tabular leading-tight text-[var(--fg)]">
          {quitado ? fmtBRLc(conta.total_pago_bruto) : conta.saldo_a_pagar == null ? '—' : fmtBRLc(conta.saldo_a_pagar)}
        </div>

        {temPacote ? (
          <div className="mt-2">
            <div className="flex items-center justify-between gap-2 text-[10px] tabular text-[var(--fg-3)]">
              <span>{fmtBRLc(pago)} de {fmtBRLc(conta.pacote)}</span>
              {excedeu && (
                <span
                  className="shrink-0 font-semibold text-[var(--fg-2)]"
                  title={`Pago ${Math.round(pct as number)}% do pacote calculado — excedente por pró-rata`}
                >
                  +{Math.round((pct as number) - 100)}%
                </span>
              )}
            </div>
            <div className="mt-1">
              <ProgressBar value={Math.min(100, pct ?? 0)} tone={TOM_BARRA[card.cor]} height={5} />
            </div>
          </div>
        ) : (
          <div className="mt-2 text-[10px] text-[var(--fg-4)]">Sem valor de pacote definido</div>
        )}
      </div>

      {/* Nível 3 — contexto: status/reserva/prazo agrupados, respiro do bloco
          de dinheiro acima; vendedor + tempo parado no rodapé (discreto,
          cobrança de posição do comercial sem competir com o valor). */}
      <div className="relative z-[1] mt-3 pt-2 border-t border-[var(--border-faint)] space-y-1">
        <div className="flex items-center justify-between gap-2">
          <span className="text-[10px] font-medium text-[var(--fg-3)]">{statusLabel(conta.status_financeiro)}</span>
          {emAtraso ? (
            <span className="shrink-0 inline-flex items-center gap-1 text-[10px] font-semibold text-[var(--red)]">
              <Icon name="alert" size={11} /> {conta.dias_atraso}d em atraso
            </span>
          ) : venceRel ? (
            <span className="shrink-0 text-[10px] tabular text-[var(--fg-3)]" title={venceRel.title}>
              vence {venceRel.label}
            </span>
          ) : null}
        </div>

        {(conta.vendedor || dias != null) && (
          <div className="flex items-center justify-between gap-2">
            <span className="truncate text-[10px] text-[var(--fg-3)]" title={conta.vendedor ? `Comercial: ${conta.vendedor}` : undefined}>
              {conta.vendedor ?? ''}
            </span>
            {dias != null && (
              <span className={`shrink-0 text-[10px] font-semibold tabular ${TEXTO_PARADO[tomParado(dias)]}`}>
                parado há {dias}d
              </span>
            )}
          </div>
        )}
      </div>
    </button>
  );
}
