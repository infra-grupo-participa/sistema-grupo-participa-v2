'use client';

// Card individual do board — cor por status_financeiro (corStatus), intensidade
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
import { fmtBRL, fmtBRLc, fmtData, fmtPrazo } from '@/shared/ui/format';
import type { BoardHotmart } from '../domain/hotmart';
import { explicarDivergencia, linhaAssinaturaHM, rotuloParcelamento, temDadoHotmart } from '../domain/board-hotmart';
import type { CardComEfeito } from '../application/carregar-board';
import { direcaoDivergencia, statusLabel, temDivergenciaPacote } from '../domain/financeiro';
import { labelMotivoReuniao } from '../domain/reuniao';
import { CLASSE_CARD, TONE_BARRA } from './cor';

// F7 (0307/0308 no repo da esteira): decisão do Marcio — "só o comercial
// grava a data, o financeiro apenas sinaliza". O chip aqui é INFORMATIVO,
// sem ação de escrita nenhuma (nem "Definir agora"): quem não ouviu a
// promessa não pode registrá-la, senão a autoria na timeline fica errada.
// O botão que grava existe só no board comercial (outro repo, card-sinais.tsx).
//
// ATUALIZADO 2026-08-20: reuniao_motivo_tipo/reuniao_retomar_em/
// intencao_pagamento agora vêm REAIS de fn_fin_board (o coordenador
// estendeu cs.vw_fin_board/fn_fin_board em produção) — sem cast, direto de
// `conta`. Trilha B real (não prometeu pagar) é o sinal preciso: motivo
// preenchido, sem vencimento combinado — NÃO entra em cobrança, é só
// contexto para o financeiro saber que já está sendo tratado. O fallback
// genérico (faixaFunil 'em_negociacao' sem vencimento e sem motivo) cobre
// cards que entraram na etapa antes da trava existir — mesmo espírito do
// board comercial (a trava só guarda a porta de entrada).

// Classe do card e tom da barra de progresso vêm de ui/cor.ts — projeção
// única de CorStatus (nenhum Record<> de cor nasce aqui). "Nunca âmbar"
// continua valendo para --accent (exclusivo de seleção/ação); --yellow
// agora É uma cor de status (vencido), não mais reservado.

/** Badge de origem na temática de cada produto (decisão do Marcio, 19/08):
 *  HM laranja, AURUM dourado ("aurum" = ouro em latim). Mesmos tokens das abas
 *  (ProdutoTabs.tsx) — um produto tem UMA cor em todo o board.
 *
 *  Precisa saltar aos olhos: a mesma pessoa pode ter 1 card por produto (ex.:
 *  Vania Thomaz — AURUM sem_tratativa R$ 58.700 + HM quitado R$ 13.376, valores
 *  distintos), e sem o badge forte os dois cards parecem duplicata/bug. */
const ORIGEM_CLASSE: Record<CardComEfeito['origem'], string> = {
  HM: 'bg-[var(--produto-hm-subtle)] text-[var(--produto-hm)] border border-[var(--produto-hm-border)]',
  AURUM: 'bg-[var(--produto-aurum-subtle)] text-[var(--produto-aurum)] border border-[var(--produto-aurum-border)]',
};

/** Faixa visual do tempo parado — calibrada pela distribuição real medida em
 *  19/08 (305 cards: até 7d=114, 8–30d=131, 31–60d=44, nenhum acima de 60d).
 *  Sem faixa "muito antigo": não existe caso real acima de 60 dias hoje. */
function tomParado(dias: number): 'discreto' | 'atencao' | 'forte' {
  if (dias <= 7) return 'discreto';
  if (dias <= 30) return 'atencao';
  return 'forte';
}

/** Marcador textual do limiar 7d/30d — não pode depender só de cor (leitor de
 *  tela, print sem tinta). Título explícito é o que permite `forte` sair do
 *  vermelho (que agora significa "cancelado") sem perder o sinal. */
const LIMIAR_PARADO: Record<ReturnType<typeof tomParado>, string | null> = {
  discreto: null,
  atencao: 'acima de 7 dias',
  forte: 'acima de 30 dias',
};

// `forte` sai de --red (agora reservado para "cancelado/reembolsado" na
// gramática de CorStatus) e passa a --yellow — mesma família de "vencido",
// que é semanticamente o que "parado há muito tempo" significa aqui.
const TEXTO_PARADO: Record<ReturnType<typeof tomParado>, string> = {
  discreto: 'text-[var(--fg-4)]',
  atencao: 'text-[var(--yellow)]',
  forte: 'text-[var(--yellow)]',
};

export function CardBoardView({ card, onOpen, hojeISO, hotmart = null }: {
  card: CardComEfeito;
  onOpen: (id: string) => void;
  hojeISO: string;
  /** Linha de fn_fin_board_hotmart deste card (null = sem dado ou camada não carregou → selo some). */
  hotmart?: BoardHotmart | null;
}) {
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
  // fmtPrazo (futuro), NÃO fmtRelativo (passado) — fmtRelativo colapsa todo
  // futuro em "hoje", então um card com vencimento em 14 dias mostrava
  // "vence hoje". Bug pré-existente, achado em 2026-08-27 junto com o mesmo
  // uso na ficha; corrigido nos DOIS lugares para não divergirem.
  // Travado em shared/ui/format.test.ts.
  const prazo = fmtPrazo(conta.vencimento, hojeISO);

  // F7: "sem data de pagamento" — informativo, sem ação. Trilha B (não
  // prometeu): mostra motivo + data de retomar, para o financeiro saber que
  // está sendo tratado e por quem — NÃO é cobrança, ninguém prometeu pagar
  // (decisão do Marcio), por isso fica fora da fila de vencimento acima.
  const motivoB = conta.reuniao_motivo_tipo ?? null;
  // Rótulo pt-BR — fonte única em ../domain/reuniao.ts, consumida também
  // por FichaDrawer.tsx. Achado do fable-orchestrator (2026-08-21): este
  // chip mostrava o slug CRU (`quer_parcelar`) no texto e no tooltip, a
  // mesma classe de erro que scripts/test-vocabulario.ts barra no repo da
  // esteira (o repo B não tem essa trava).
  const motivoBLabel = labelMotivoReuniao(motivoB);
  const retomarB = conta.reuniao_retomar_em ?? null;
  // Trilha B real (motivo preenchido) OU o fallback genérico de cards sem
  // NENHUMA trilha gravada ainda (card antigo, entrou antes da trava 0308).
  // Nunca conta trilha A (intencao_pagamento === 'vai_pagar') como "sem
  // data": quem prometeu pagar tem vencimento — se este card não tem, é
  // porque a trilha A ainda não foi completada, mesma situação do fallback.
  const semDataPagamento = !quitado && !conta.vencimento
    && conta.intencao_pagamento !== 'vai_pagar'
    && (!!motivoB || card.faixaFunil === 'em_negociacao');

  // Divergência pacote cravado × régua (N2, 2026-09-04): informação NEUTRA,
  // nunca alerta de erro — o cravado sempre prevalece (comportamento já
  // existente). Cor --fg-2/--fg-3 de propósito: o card já usa 3 pigmentos de
  // status/alerta (CLASSE_CARD, --red de atraso, --yellow de parado); um 4º
  // pigmento aqui competiria por atenção com sinais que de fato pedem ação.
  const divergePacote = temDivergenciaPacote(conta);
  const direcaoPacote = direcaoDivergencia(conta);
  const tituloDivergencia = divergePacote
    ? `Valor travado manualmente: ${fmtBRLc(conta.pacote)}. Cálculo automático: ${fmtBRLc(conta.pacote_regra)}. Diferença: ${fmtBRLc(Math.abs(conta.divergencia_regra as number))} ${direcaoPacote === 'a_maior' ? 'a mais' : 'a menos'}.`
    : undefined;

  // Camada Hotmart: só aviso, nunca muda valor do card. Sem dado → nada
  // (nunca "R$ 0", que diria "não pagou nada" quando a verdade é "não sabemos").
  const hm = temDadoHotmart(hotmart) ? hotmart : null;
  const hmDiverge = hm?.diverge === true;
  const hmExplicacao = hm ? explicarDivergencia(hm, fmtBRLc) : null;
  const hmParcelamento = hm ? rotuloParcelamento(hm.parcelas_max) : null;
  const hmTitle = hm
    ? `Números da Hotmart (não mudam os valores do board).${hm.cards_da_pessoa > 1 ? ` Esta pessoa tem ${hm.cards_da_pessoa} cards: os mesmos números aparecem em cada um.` : ''}`
    : undefined;
  // Assinatura HM (mensalidades): contrato à parte — decisão do João, NÃO soma
  // no "pago" do card nem na linha Hotmart acima. Sem assinatura → nada.
  const hmAssinatura = linhaAssinaturaHM(hm, fmtBRL);
  const hmAssinaturaAtiva = hm?.assinatura_ativa === true;

  return (
    <button
      type="button"
      onClick={() => onOpen(conta.contato_hm_id)}
      // ⚠️ 2026-08-27: SEM `shadow-*` do Tailwind aqui. A faixa lateral de status
      // é `box-shadow: inset` (.gp-card--{cor} em globals.css), e uma utility de
      // sombra na mesma especificidade sobrescreve a propriedade inteira — a
      // faixa sumia no hover, justamente o sinal de cor mais forte do card.
      // Elevação e faixa convivem em UMA declaração só, em `.gp-card`/`.gp-card:hover`.
      className={`gp-card ${CLASSE_CARD[card.cor]} gp-card--u${card.urgencia} w-full text-left p-4 cursor-pointer transition-[transform,box-shadow] duration-150 hover:-translate-y-0.5 focus-visible:ring-2`}
      aria-label={`Abrir ficha de ${conta.nome}, ${card.origem}, ${statusLabel(conta.status_financeiro)}${
        conta.saldo_a_pagar != null ? `, falta pagar ${fmtBRLc(conta.saldo_a_pagar)}` : ''
      }${card.motivoUrgencia ? `, ${card.motivoUrgencia}` : ''}${
        divergePacote ? `, pacote divergente da régua, ${direcaoPacote === 'a_maior' ? 'a mais' : 'a menos'}` : ''
      }${hmDiverge ? ', diverge da Hotmart' : ''}${
        hmAssinatura ? `, assinatura HM ${hmAssinaturaAtiva ? 'ativa' : 'encerrada'}` : ''
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
          do total (reserva ENTRA em esperado/naRua). Chip NEUTRO de propósito:
          --yellow agora é cor de status (vencido) — um card com barra-topo
          verde/azul não pode carregar um segundo papel para o mesmo pigmento,
          e o chip amarelo sobre --yellow-subtle reprovava contraste AA no
          tema claro (4,14:1, medido em 2026-08-23). */}
      {card.reserva && (
        <div className="relative z-[1] mt-2">
          <span className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-2)]">
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
              <span className="inline-flex items-center gap-1">
                {fmtBRLc(pago)} de {fmtBRLc(conta.pacote)}
                {/* Divergência pacote cravado × régua: marca discreta, cor
                    NEUTRA (nunca cor de status) — mesmo padrão do selo +N%
                    ao lado. O cravado sempre prevalece; isto é só sinal. */}
                {divergePacote && (
                  <span className="shrink-0 text-[var(--fg-3)]" title={tituloDivergencia}>
                    <Icon name="alert" size={10} />
                  </span>
                )}
              </span>
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
                tone={TONE_BARRA[card.cor]}
                height={5}
                valueMin={0}
                valueMax={conta.pacote ?? undefined}
                valueNow={pago}
                ariaLabel={`${fmtBRLc(pago)} de ${fmtBRLc(conta.pacote)} pagos`}
              />
            </div>
          </div>
        ) : (
          <div className="mt-2 text-[10px] text-[var(--fg-4)]">Sem valor de pacote definido</div>
        )}
      </div>

      {/* Nível 3 — situação (27/09, João: "as partes dentro do card estão muito desorganizadas"): uma linha de
          selos (status + prazo + avisos), depois a Hotmart em dois números lado a lado, e o rodapé com quem cuida
          e há quanto tempo está parado. Cada informação num lugar fixo — o olho acha sem ler o card inteiro. */}
      <div className="relative z-[1] mt-3 flex flex-wrap items-center gap-1">
        <span className="rounded-[var(--r-sm)] bg-[var(--surface-3)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-2)]">
          {statusLabel(conta.status_financeiro)}
        </span>
        {/* --red DE PROPÓSITO: alarme pontual de prazo estourado, não cor de status (ver plano, CONFLITO 1). */}
        {emAtraso ? (
          <span className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--red)]">
            <Icon name="alert" size={10} /> {conta.dias_atraso}d em atraso
          </span>
        ) : prazo ? (
          <span className="rounded-[var(--r-sm)] bg-[var(--surface-3)] px-1.5 py-0.5 text-[10px] tabular text-[var(--fg-3)]" title={prazo.title}>
            {prazo.label}
          </span>
        ) : null}
        {/* F7: informativo, sem ação (só o comercial registra a promessa). */}
        {semDataPagamento && (
          <span
            className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--red)]"
            title={
              motivoBLabel
                ? `Não prometeu pagar — motivo: ${motivoBLabel}${retomarB ? `, retomar em ${fmtData(retomarB)}` : ''}. Quem registra é o comercial, não o financeiro.`
                : 'Sem data de pagamento combinada — quem registra é o comercial, não o financeiro.'
            }
          >
            {motivoBLabel ? `sem data · ${retomarB ? `retoma ${fmtData(retomarB)}` : motivoBLabel}` : 'sem data de pagamento'}
          </span>
        )}
        {hmDiverge && (
          <span
            className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-2)]"
            title={hmExplicacao ?? undefined}
          >
            <Icon name="alert" size={10} className="text-[var(--yellow)]" /> Diverge da Hotmart
          </span>
        )}
      </div>

      {/* Camada Hotmart: dois números fixos. Sem dado → nada (nunca "R$ 0", que diria "não pagou"). */}
      {hm && (
        <div className="relative z-[1] mt-2 grid grid-cols-2 gap-1.5" title={hmTitle}>
          <div className="rounded-[var(--r-sm)] bg-[var(--surface-2)] px-2 py-1">
            <div className="text-[9px] font-medium uppercase tracking-wide text-[var(--fg-4)]">Hotmart</div>
            <div className="truncate text-[11px] font-semibold tabular text-[var(--fg)]">
              {hm.vendas_pagas > 0 ? fmtBRL(hm.pago_bruto) : 'nada pago'}
            </div>
            {hm.vendas_pagas > 0 && hmParcelamento && <div className="truncate text-[9px] text-[var(--fg-4)]">{hmParcelamento}</div>}
          </div>
          <div className="rounded-[var(--r-sm)] bg-[var(--surface-2)] px-2 py-1">
            <div className="text-[9px] font-medium uppercase tracking-wide text-[var(--fg-4)]">Devendo</div>
            <div className={`truncate text-[11px] font-semibold tabular ${hm.parcelas_devidas > 0 ? 'text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
              {hm.parcelas_devidas > 0 ? fmtBRL(hm.valor_devido) : 'em dia'}
            </div>
            {hm.parcelas_devidas > 0 && <div className="truncate text-[9px] text-[var(--fg-4)]">{hm.parcelas_devidas} parcela{hm.parcelas_devidas === 1 ? '' : 's'}</div>}
          </div>
        </div>
      )}
      {hmAssinatura && (
        <div
          className="relative z-[1] mt-1.5 flex items-center justify-between gap-2"
          title="Assinatura HM (mensalidades) é outro contrato: não entra no pago deste card."
        >
          <span className="truncate text-[10px] tabular text-[var(--fg-3)]">{hmAssinatura}</span>
          <span className="shrink-0 inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-2)]">
            {hmAssinaturaAtiva && <span className="h-1.5 w-1.5 rounded-full bg-[var(--green)]" aria-hidden />}
            {hmAssinaturaAtiva ? 'ativa' : 'encerrada'}
          </span>
        </div>
      )}

      {(conta.vendedor || dias != null) && (
        <div className="relative z-[1] mt-3 flex items-center justify-between gap-2 border-t border-[var(--border-faint)] pt-2">
          <span className="inline-flex min-w-0 items-center gap-1 truncate text-[10px] text-[var(--fg-3)]" title={conta.vendedor ? `Comercial: ${conta.vendedor}` : undefined}>
            {conta.vendedor && <Icon name="user" size={10} className="shrink-0" />}{conta.vendedor ?? ''}
          </span>
          {dias != null && (
            <span
              className={`shrink-0 text-[10px] font-semibold tabular ${TEXTO_PARADO[tomParado(dias)]}`}
              title={LIMIAR_PARADO[tomParado(dias)] ? `parado há ${dias} dias, ${LIMIAR_PARADO[tomParado(dias)]}` : undefined}
              aria-label={LIMIAR_PARADO[tomParado(dias)] ? `parado há ${dias} dias, ${LIMIAR_PARADO[tomParado(dias)]}` : `parado há ${dias} dias`}
            >
              parado há {dias}d
            </span>
          )}
        </div>
      )}
    </button>
  );
}
