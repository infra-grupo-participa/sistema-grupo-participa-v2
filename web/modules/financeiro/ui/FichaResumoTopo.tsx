// Faixa de destaque no topo da aba Resumo da ficha — dinheiro primeiro,
// contato por último (decisão do Marcio, 2026-08-27: "lê o valor e decide").
// Ordem de leitura = ordem de decisão de quem cobra: quanto? → estou
// atrasado? → o que faço?
//
// Fica no módulo financeiro (não em shared/ui/components): combina
// saldo_a_pagar + pago_pct + dias_atraso + proximaAcao — vocabulário de
// contas a receber. Levar para shared vazaria o tipo ContaReceber para a
// camada compartilhada por um único consumidor.
//
// Mesma regra de "falta pagar" × "quitado" do card (CardBoard.tsx:162-166) —
// não reinventada aqui, para ficha e card nunca divergirem de novo (mesma
// razão que criou ui/cor.ts).
import { ProgressBar } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtPrazo } from '@/shared/ui/format';
import type { ContaReceber, ReguaPasso } from '../domain/types';
import { proximaAcao } from '../domain/cobranca';
import { TONE_BARRA } from './cor';
import type { CorStatus } from '../domain/cor-status';

export function FichaResumoTopo({ conta, cor, regua, hojeISO }: {
  conta: ContaReceber;
  cor: CorStatus;
  regua: ReguaPasso[];
  hojeISO: string;
}) {
  const quitado = conta.status_financeiro === 'quitado';
  const pago = conta.total_pago_bruto ?? 0;
  const temPacote = conta.pacote != null && conta.pacote > 0;
  const pct = conta.pago_pct ?? (temPacote ? (pago / (conta.pacote as number)) * 100 : null);
  // Mesmo tratamento de pró-rata do card: clampa a barra em 100, excedente vira selo.
  const excedeu = pct != null && pct > 100;

  const emAtraso = (conta.dias_atraso ?? 0) > 0;
  // fmtPrazo (futuro), NÃO fmtRelativo (passado): fmtRelativo colapsa todo
  // futuro em "hoje", e uma conta que vence em 14 dias exibia "vence hoje"
  // exatamente na faixa que existe para responder "estou atrasado?".
  // Travado em shared/ui/format.test.ts. Devolve null quando já passou —
  // esse caso é do chip de atraso acima, que usa dias_atraso do banco.
  const prazo = fmtPrazo(conta.vencimento, hojeISO);
  const acao = proximaAcao(conta, regua, hojeISO);

  return (
    <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
      <div className="text-[10px] font-medium uppercase tracking-wide text-[var(--fg-3)]">
        {quitado ? 'Quitado' : 'Falta pagar'}
      </div>
      <div className="text-[28px] font-extrabold tabular leading-tight text-[var(--fg)]">
        {quitado ? fmtBRLc(pago) : conta.saldo_a_pagar == null ? '—' : fmtBRLc(conta.saldo_a_pagar)}
      </div>

      {temPacote ? (
        <div className="mt-2">
          <div className="flex items-center justify-between gap-2 text-[11px] tabular text-[var(--fg-3)]">
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
            <ProgressBar
              value={Math.min(100, pct ?? 0)}
              tone={TONE_BARRA[cor]}
              height={6}
              valueMin={0}
              valueMax={conta.pacote ?? undefined}
              valueNow={pago}
              ariaLabel={`${fmtBRLc(pago)} de ${fmtBRLc(conta.pacote)} pagos`}
            />
          </div>
        </div>
      ) : (
        <div className="mt-2 text-[11px] text-[var(--fg-4)]">Sem valor de pacote definido</div>
      )}

      {/* Linha de prazo: vence em… / Nd em atraso / sem acordo — texto, não
          só cor (mesma regra do card: leitor de tela, print sem tinta). */}
      <div className="mt-3 pt-3 border-t border-[var(--border-faint)] flex items-center gap-1.5 text-[13px]">
        {/* `quitado` vem ANTES de `prazo`: conta quitada com vencimento
            preenchido caía no branch do prazo e anunciava "vence em 5 dias"
            para quem já pagou tudo. Quem quitou não tem prazo a cumprir. */}
        {quitado ? (
          <span className="text-[var(--fg-3)]">Sem pendência</span>
        ) : emAtraso ? (
          <span className="inline-flex items-center gap-1 font-semibold text-[var(--red)]">
            <Icon name="alert" size={13} /> {conta.dias_atraso} dias em atraso
          </span>
        ) : prazo ? (
          <span className="text-[var(--fg-2)]" title={prazo.title}>{prazo.label}</span>
        ) : (
          <span className="text-[var(--fg-3)]">Sem acordo registrado</span>
        )}
      </div>

      {/* Linha de ação: o que fazer agora, segundo a régua. `nenhuma` cobre
          conta morta/quitada/régua concluída — não mostrar CTA fantasma. */}
      {acao.tipo !== 'nenhuma' && (
        <div className="mt-1.5 flex items-center gap-1.5 text-[13px] font-medium text-[var(--fg)]">
          <Icon name="arrow-right" size={13} className="text-[var(--fg-3)]" />
          {acao.titulo}
          {acao.quando && (
            <span className="text-[var(--fg-3)] font-normal">
              {acao.atrasada ? ' — atrasada' : ` — a partir de ${acao.quando.split('-').reverse().join('/')}`}
            </span>
          )}
        </div>
      )}
    </section>
  );
}
