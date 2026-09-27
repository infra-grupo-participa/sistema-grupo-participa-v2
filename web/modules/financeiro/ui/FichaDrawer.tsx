'use client';

// Ficha do aluno — foco no que o financeiro precisa: por que ainda não pagou
// e o que cobrar do comercial. Reusa Drawer/Tabs/Row do design system.
import { useEffect, useState } from 'react';
import {
  AvatarInicial, Badge, Button, CopyField, Drawer, EmptyState, Loading, Row, SectionTitle, Tabs, Textarea, Timeline, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData, fmtDataHora, fmtDesde } from '@/shared/ui/format';
import type { ContaReceber, Cobranca, InteracaoAtivacao, ReguaPasso } from '../domain/types';
import { contaMorta, direcaoDivergencia, mascararDoc, statusLabel, temDivergenciaPacote } from '../domain/financeiro';
import { corStatus } from '../domain/cor-status';
import { labelMotivoReuniao } from '../domain/reuniao';
import { statusCompraLabel, statusTone, TONE_BADGE } from './cor';
import { FichaResumoTopo } from './FichaResumoTopo';
import type { FinanceiroRepository } from '../application/ports';
import { ExtratoHotmart } from './hotmart/ExtratoHotmart';
import { carregarFicha, type Ficha } from '../application/carregar-ficha';
import { rotuloCategorias, rotuloMetodo, type BoardHotmart, type ProrataHM } from '../domain/hotmart';
import { explicarDivergencia, fmtMesAno, rotuloParcelamento, temAssinaturaHM, temDadoHotmart } from '../domain/board-hotmart';
import { prorataDoCard } from '../domain/prorata-hm';
import { carregarProrataHM, VALOR_PROGRAMA_HM } from '../application/carregar-prorata';

const CANAIS_COBRANCA = ['WhatsApp', 'E-mail', 'Ligação', 'Reunião'];
const RESULTADOS_COBRANCA = ['Sem resposta', 'Prometeu pagar', 'Renegociou', 'Recusou', 'Pagou'];

/** Tom + ícone por tipo de interação — âmbar é exclusivo de seleção/ação (system.md),
 *  por isso mudança de estágio (decisão de negócio) usa purple, não accent; nota é
 *  o operador registrando algo à mão (info); disparo/resposta são mensageria (base);
 *  sistema é evento automático (base). */
const TOM_INTERACAO: Record<InteracaoAtivacao['tipo'], { tone: 'purple' | 'info' | 'base'; icon: 'arrow-right' | 'notebook' | 'mail' | 'circle' }> = {
  mudanca_estagio: { tone: 'purple', icon: 'arrow-right' },
  nota: { tone: 'info', icon: 'notebook' },
  disparo: { tone: 'base', icon: 'mail' },
  resposta: { tone: 'base', icon: 'mail' },
  sistema: { tone: 'base', icon: 'circle' },
};

function tituloInteracao(it: InteracaoAtivacao): React.ReactNode {
  if (it.tipo === 'mudanca_estagio' && it.estagio_de && it.estagio_para) {
    return (
      <span className="inline-flex items-center gap-1">
        {it.estagio_de} <Icon name="arrow-right" size={11} /> {it.estagio_para}
      </span>
    );
  }
  return it.descricao || '—';
}

// F8 (0307/0308 no repo da esteira: "Reunião Finalizada exige prazo de
// pagamento") — o que foi combinado na reunião + responsável comercial.
// `vendedor` já aparece em "Dados pessoais" acima, repetido aqui no rodapé
// da seção para o contexto ficar junto do combinado. Estendido em produção
// pelo coordenador (2026-08-20): cs.vw_fin_board/fn_fin_board agora
// projetam reuniao_resultado + os 4 campos da trilha A/B — todos REAIS em
// ContaReceber agora (sem cast), mapeados em
// application/carregar-board.ts:cardBoardParaContaReceber. `obs_comercial`
// (campo DIFERENTE de intencao_pagamento_obs) continua sem fonte na RPC —
// fica null, não confundir os dois. Seção INTEIRA some quando não há nada
// para mostrar — não poluir 100% das fichas com um bloco vazio.
//
// Rótulos pt-BR do motivo (trilha B): FONTE ÚNICA em ../domain/reuniao.ts,
// consumida também por CardBoard.tsx (chip/tooltip) — achado do
// fable-orchestrator, 2026-08-21: o mapa vivia só aqui, e o chip do board
// mostrava o valor cru.
function SecaoCombinadoComercial({ conta }: { conta: ContaReceber }) {
  const prometeu = conta.intencao_pagamento === 'vai_pagar';
  const naoPrometeu = !prometeu && !!conta.reuniao_motivo_tipo;
  const temAlgo = !!conta.reuniao_resultado || !!conta.obs_comercial || prometeu || naoPrometeu;
  if (!temAlgo) return null;

  return (
    <section>
      <SectionTitle>Combinado na reunião</SectionTitle>
      <Row k="Resultado da reunião" v={conta.reuniao_resultado} />
      {(prometeu || naoPrometeu) && (
        <Row k="Trilha" v={prometeu ? 'Prometeu pagar' : 'Não prometeu pagar'} />
      )}
      {naoPrometeu && <Row k="Motivo" v={labelMotivoReuniao(conta.reuniao_motivo_tipo)} />}
      {naoPrometeu && conta.reuniao_retomar_em && (
        <Row k="Comercial retoma em" v={fmtData(conta.reuniao_retomar_em)} />
      )}
      <Row k="Observação do comercial" v={conta.intencao_pagamento_obs || conta.obs_comercial} />
      <Row k="Responsável comercial" v={conta.vendedor} />
    </section>
  );
}

export function FichaDrawer({ conta, repo, canEdit, canVerDoc, regua, hojeISO, onClose, onAcordoSalvo, hotmartPorCard = null, hotmartErro = false }: {
  conta: ContaReceber;
  repo: FinanceiroRepository;
  canEdit: boolean;
  canVerDoc: boolean;
  /** Régua de cobrança já carregada pelo chamador (FinanceiroClient) — nunca
   *  buscada aqui: seria N queries por abertura de ficha para um dado que já
   *  está em memória (F3 do plano). */
  regua: ReguaPasso[];
  hojeISO: string;
  onClose: () => void;
  onAcordoSalvo: () => void;
  /** Camada Hotmart do board, já carregada pelo chamador (nenhuma query aqui). */
  hotmartPorCard?: Map<string, BoardHotmart> | null;
  hotmartErro?: boolean;
}) {
  const [tab, setTab] = useState<'resumo' | 'historico' | 'cobranca'>('resumo');
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const { toast, flash } = useFlash();

  useEffect(() => {
    // Sem reset de estado aqui: o Drawer é montado com `key={contato_hm_id}`
    // pelo chamador (FinanceiroClient), então cada conta já nasce com
    // ficha/erro em null — não precisa (nem deve) resetar dentro do efeito.
    let vivo = true;
    carregarFicha(repo, conta.comprador_id, conta.contato_hm_id)
      .then((f) => { if (vivo) setFicha(f); })
      .catch(() => { if (vivo) setErro('Não foi possível carregar o histórico financeiro. Tente novamente.'); });
    return () => { vivo = false; };
  }, [repo, conta.comprador_id, conta.contato_hm_id]);

  const morta = contaMorta(conta);

  return (
    <Drawer
      onClose={onClose}
      title={conta.nome || '—'}
      subtitle={conta.email}
      avatar={<AvatarInicial nome={conta.nome} size={44} />}
      badges={
        <>
          <Badge tone={statusTone(conta.status_financeiro)}>{statusLabel(conta.status_financeiro)}</Badge>
          {conta.turma && <Badge tone="neutral">{conta.turma}</Badge>}
          <Badge tone="accent">{conta.produto}</Badge>
        </>
      }
    >
      <Tabs
        active={tab}
        onChange={(k) => setTab(k as typeof tab)}
        tabs={[
          { k: 'resumo', l: 'Resumo' },
          { k: 'historico', l: 'Histórico financeiro' },
          { k: 'cobranca', l: 'Cobrança' },
        ]}
      />

      {erro && (
        <div className="mb-4 rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-3 py-2 text-sm text-[var(--red)]">
          {erro}
        </div>
      )}

      {tab === 'resumo' && (
        <div className="space-y-4">
          <FichaResumoTopo conta={conta} cor={corStatus(conta.status_financeiro)} regua={regua} hojeISO={hojeISO} />
          <section>
            <SectionTitle>Por que ainda não pagou</SectionTitle>
            <Row k="Pacote" v={conta.pacote != null ? fmtBRLc(conta.pacote) : 'Sem valor de pacote definido'} />
            {/* Divergência pacote cravado × régua (N2, 2026-09-04): informação
                NEUTRA, não alerta — o cravado (Row "Pacote" acima) sempre
                prevalece no cálculo. Sem divergência conhecida (dado ausente
                ou dentro da tolerância), nada muda aqui. */}
            {temDivergenciaPacote(conta) && (
              <>
                <Row k="Pacote pela régua" v={fmtBRLc(conta.pacote_regra)} />
                <Row
                  k="Diferença"
                  v={`${fmtBRLc(Math.abs(conta.divergencia_regra as number))} ${direcaoDivergencia(conta) === 'a_maior' ? 'a mais' : 'a menos'}`}
                />
              </>
            )}
            <Row k="Já pago (bruto)" v={fmtBRLc(conta.total_pago_bruto)} />
            <Row k="Solicitou cancelamento" v={conta.solicitou_cancelamento ? 'Sim' : 'Não'} />
            {conta.oferta_codigo && <Row k="Oferta enviada" v={`${conta.oferta_codigo} (${fmtData(conta.oferta_enviada_em)})`} />}
          </section>
          <SecaoCombinadoComercial conta={conta} />
          <section>
            <SectionTitle>Dados pessoais</SectionTitle>
            <div className="space-y-2 mb-2">
              {conta.telefone && <CopyField label="Telefone" value={conta.telefone} />}
              {conta.email && <CopyField label="E-mail" value={conta.email} />}
            </div>
            <Row k="Documento" v={mascararDoc(conta.documento, canVerDoc)} />
            <Row k="Canal de origem" v={conta.canal} />
            <Row k="Vendedor" v={conta.vendedor} />
            <Row k="Situação na ativação" v={conta.estagio_nome} />
          </section>
          {morta && (
            <section>
              <SectionTitle>Encerramento</SectionTitle>
              {conta.cancelamento_em && <Row k="Cancelamento solicitado em" v={fmtData(conta.cancelamento_em)} />}
              {conta.cancelamento_efetivado_em && <Row k="Cancelamento efetivado em" v={fmtData(conta.cancelamento_efetivado_em)} />}
              {conta.reembolso_em && <Row k="Reembolso em" v={fmtData(conta.reembolso_em)} />}
              {conta.reembolso_valor != null && <Row k="Valor reembolsado" v={fmtBRLc(conta.reembolso_valor)} />}
            </section>
          )}
        </div>
      )}

      {tab === 'historico' && (
        ficha === null && !erro ? (
          <Loading label="Carregando histórico…" minHeight={160} />
        ) : !ficha ? null : (
          <div className="space-y-4">
            <section>
              <SectionTitle>Lançamentos ({ficha.extrato.length})</SectionTitle>
              {!ficha.extrato.length ? (
                <EmptyState title="Nenhum lançamento" icon="receipt" />
              ) : (
                <Timeline
                  items={ficha.extrato.map((l) => ({
                    tone: l.categoria === 'sinal' ? 'purple' : 'green',
                    done: true,
                    title: `${l.categoria} — ${fmtBRLc(l.valor_bruto)}`,
                    meta: fmtData(l.pago_em),
                    body: `${l.metodo_pagamento ?? '—'}${l.parcela ? ` · parcela ${l.parcela}` : ''}${l.oferta_codigo ? ` · oferta ${l.oferta_codigo}` : ''}`,
                  }))}
                />
              )}
            </section>
            <section>
              <SectionTitle>Compras Hotmart ({ficha.compras.length})</SectionTitle>
              {!ficha.compras.length ? (
                <EmptyState title="Nenhuma compra encontrada" icon="receipt" />
              ) : (
                ficha.compras.map((c) => (
                  <Row
                    key={c.id}
                    k={c.produto_nome}
                    v={
                      <span>
                        {c.bruto != null ? fmtBRLc(c.bruto) : '—'}{' '}
                        {/* Tom deriva do MESMO vocabulário do card/ficha (TONE_BADGE), não
                            mais decidido aqui. `morto` funde vencido/cancelado/estornado na
                            origem (CompraHistorico.morto) — sai vermelho mesmo quando era só
                            um boleto vencido; imprecisão conhecida, documentada no plano
                            (CONFLITO 3), não separada no cliente sem migration. */}
                        <Badge tone={c.pago ? TONE_BADGE.verde : c.pendente ? TONE_BADGE.azul : c.morto ? TONE_BADGE.vermelho : TONE_BADGE.neutro}>
                          {statusCompraLabel(c.status)}
                        </Badge>
                      </span>
                    }
                  />
                ))
              )}
            </section>
            <SecaoBoardHotmart
              conta={conta}
              repo={repo}
              hm={hotmartPorCard?.get(conta.contato_hm_id) ?? null}
              carregando={!hotmartPorCard && !hotmartErro}
              erro={hotmartErro && !hotmartPorCard}
            />
            <section>
              <SectionTitle>Histórico na Hotmart (API oficial)</SectionTitle>
              <p className="mb-2 text-[11px] text-[var(--fg-3)]">
                Tudo o que este e-mail comprou e tentou comprar, direto da Hotmart — inclusive cartão recusado,
                boleto não pago, parcela atrasada e reembolso. Só leitura.
              </p>
              <ExtratoHotmart email={conta.email} repo={repo} />
            </section>
            <section>
              <SectionTitle>Histórico do comercial ({ficha.historicoAtivacao.length})</SectionTitle>
              {!ficha.historicoAtivacao.length ? (
                <EmptyState title="Nenhuma interação registrada" hint="O comercial ainda não registrou contato, nota ou mudança de estágio para esta conta." icon="clipboard" />
              ) : (
                <Timeline
                  items={ficha.historicoAtivacao.map((it) => {
                    const { tone, icon } = TOM_INTERACAO[it.tipo];
                    return {
                      tone,
                      icon: <Icon name={icon} size={11} />,
                      title: tituloInteracao(it),
                      meta: fmtDesde(it.quando).label,
                      body: it.autor ? `por ${it.autor}` : undefined,
                    };
                  })}
                />
              )}
            </section>
          </div>
        )
      )}

      {tab === 'cobranca' && (
        <CobrancaTab
          conta={conta}
          repo={repo}
          canEdit={canEdit}
          cobrancas={ficha?.cobrancas ?? []}
          carregando={ficha === null && !erro}
          flash={flash}
          onAcordoSalvo={onAcordoSalvo}
        />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]" role="status">
          {toast}
        </div>
      )}
    </Drawer>
  );
}

/** Board × Hotmart — os números da Hotmart deste card, lado a lado com o que
 *  o board registra. Só leitura e só aviso: não muda nenhum valor do board. */
function SecaoBoardHotmart({ conta, repo, hm, carregando, erro }: {
  conta: ContaReceber;
  repo: FinanceiroRepository;
  hm: BoardHotmart | null;
  carregando: boolean;
  erro: boolean;
}) {
  if (carregando) return null;
  const aviso = (texto: string) => (
    <section>
      <SectionTitle>Board × Hotmart</SectionTitle>
      <p className="text-[11px] text-[var(--fg-3)]">{texto}</p>
    </section>
  );
  if (erro) return aviso('Números da Hotmart indisponíveis agora. O board não depende deles.');
  if (!temDadoHotmart(hm)) return aviso('Esta pessoa não foi encontrada na Hotmart — sem números para comparar.');

  const explicacao = explicarDivergencia(hm, fmtBRLc);
  const parcelamento = rotuloParcelamento(hm.parcelas_max);
  return (
    <section>
      <SectionTitle>Board × Hotmart</SectionTitle>
      {hm.cards_da_pessoa > 1 && (
        <p className="mb-1 text-[11px] text-[var(--fg-3)]">
          Esta pessoa tem {hm.cards_da_pessoa} cards: os números da Hotmart abaixo são dela inteira e se repetem em cada card.
        </p>
      )}
      <Row k="Pago segundo o board (bruto)" v={fmtBRLc(conta.total_pago_bruto)} />
      <Row k={`Pago na Hotmart (${hm.vendas_pagas} venda${hm.vendas_pagas === 1 ? '' : 's'})`} v={fmtBRLc(hm.pago_bruto)} />
      <Row k="Taxa da Hotmart" v={fmtBRLc(hm.taxa_hotmart)} />
      {hm.coproducao > 0 && <Row k="Coprodução" v={fmtBRLc(hm.coproducao)} />}
      <Row k="Líquido (fica para nós)" v={fmtBRLc(hm.liquido)} />
      <Row k="Cliente pagou (com juros)" v={fmtBRLc(hm.cobrado_cliente)} />
      <Row k="Juros do parcelamento" v={fmtBRLc(hm.juros)} />
      <Row k="Parcelamento" v={parcelamento ?? '—'} />
      <Row k="Forma de pagamento" v={rotuloMetodo(hm.forma_pagamento_principal)} />
      <Row
        k="Último pagamento"
        v={hm.ultimo_pagamento_em ? `${fmtData(hm.ultimo_pagamento_em)}${hm.ultimo_pagamento_valor != null ? ` · ${fmtBRLc(hm.ultimo_pagamento_valor)}` : ''}` : '—'}
      />
      <Row
        k="Devendo na Hotmart"
        v={hm.parcelas_devidas > 0 ? `${fmtBRLc(hm.valor_devido)} (${hm.parcelas_devidas} parcela${hm.parcelas_devidas === 1 ? '' : 's'})` : 'Nada'}
      />
      {hm.estornos > 0 && <Row k="Estornos" v={`${fmtBRLc(hm.valor_estornado)} (${hm.estornos})`} />}
      {explicacao ? (
        <div className="mt-2 flex items-start gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-2 text-xs text-[var(--fg-2)]">
          <Icon name="alert" size={13} className="mt-0.5 shrink-0 text-[var(--yellow)]" />
          <span><strong className="font-semibold">Diverge da Hotmart:</strong> {explicacao}</span>
        </div>
      ) : hm.diverge === false ? (
        <p className="mt-1 text-[11px] text-[var(--fg-3)]">Board e Hotmart batem para esta pessoa.</p>
      ) : null}
      {hm.sincronizado_em && (
        <p className="mt-1 text-[11px] text-[var(--fg-4)]">Hotmart sincronizada em {fmtDataHora(hm.sincronizado_em)}.</p>
      )}
      {temAssinaturaHM(hm) && <BlocoAssinaturaHM hm={hm} />}
      {(hm.outros_pagamentos ?? 0) > 0 && <BlocoOutrosPagamentos hm={hm} />}
      {hm.origem === 'HM' && <BlocoProrataHM repo={repo} contatoHmId={conta.contato_hm_id} hm={hm} />}
    </section>
  );
}

const SUBTITULO = 'mt-3 mb-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]';

/** Assinatura HM (mensalidades) — contrato à parte (decisão do João): fica
 *  fora do "pago" do card e fora das linhas de venda acima. */
function BlocoAssinaturaHM({ hm }: { hm: BoardHotmart }) {
  const de = fmtMesAno(hm.assinatura_de);
  const ate = fmtMesAno(hm.assinatura_ate);
  return (
    <div>
      <div className={SUBTITULO}>Assinatura HM (contrato à parte)</div>
      <Row k="Mensalidades pagas" v={hm.assinatura_mensalidades} />
      <Row k="Total das mensalidades" v={fmtBRLc(hm.assinatura_valor)} />
      <Row k="De / até" v={`${de ?? '—'} → ${ate ?? '—'}`} />
      <Row
        k="Situação"
        v={hm.assinatura_ativa == null ? '—' : <Badge tone={hm.assinatura_ativa ? 'success' : 'neutral'}>{hm.assinatura_ativa ? 'ativa' : 'encerrada'}</Badge>}
      />
      <p className="mt-1 text-[11px] text-[var(--fg-3)]">Não entra no &quot;pago&quot; deste card — é outro contrato.</p>
    </div>
  );
}

/** Outros pagamentos da pessoa na Hotmart que o card não mostra (renovação,
 *  complemento, oferta fora do catálogo = "desconhecida") — só informação,
 *  não entra no "pago" do card (20260928i). */
function BlocoOutrosPagamentos({ hm }: { hm: BoardHotmart }) {
  const n = hm.outros_pagamentos ?? 0;
  return (
    <div>
      <div className={SUBTITULO}>Outros pagamentos na Hotmart (fora do board)</div>
      <Row k={`${n} pagamento${n === 1 ? '' : 's'}`} v={fmtBRLc(hm.outros_valor ?? 0)} />
      <Row k="O que são" v={rotuloCategorias(hm.outros_formas)} />
      <Row k="Último" v={hm.outros_ultimo ? fmtData(hm.outros_ultimo) : '—'} />
      <p className="mt-1 text-[11px] text-[var(--fg-3)]">Não entram no &quot;pago&quot; deste card. &quot;Oferta desconhecida&quot; = a oferta não está no catálogo e o valor não diz o que é.</p>
    </div>
  );
}

/** Pro rata HM → Programa. fn_fin_prorata_hm carregada SOB DEMANDA na 1ª ficha
 *  aberta e reaproveitada (application/carregar-prorata.ts) — nunca por card. */
function BlocoProrataHM({ repo, contatoHmId, hm }: { repo: FinanceiroRepository; contatoHmId: string; hm: BoardHotmart }) {
  const [linhas, setLinhas] = useState<ProrataHM[] | null>(null);
  const [erro, setErro] = useState(false);
  useEffect(() => {
    let vivo = true;
    carregarProrataHM(repo)
      .then((ls) => { if (vivo) setLinhas(ls); })
      .catch(() => { if (vivo) setErro(true); });
    return () => { vivo = false; };
  }, [repo]);

  const titulo = <div className={SUBTITULO}>Pro rata para o Programa</div>;
  if (erro) return <div>{titulo}<p className="text-[11px] text-[var(--fg-3)]">Pro rata indisponível agora. Tente abrir a ficha de novo.</p></div>;
  if (!linhas) return <div>{titulo}<p className="text-[11px] text-[var(--fg-4)]">Calculando pro rata…</p></div>;
  const p = prorataDoCard(linhas, contatoHmId, hm);
  if (!p) return <div>{titulo}<p className="text-[11px] text-[var(--fg-3)]">Sem vencimento cadastrado na turma — confirme com a Isabela.</p></div>;
  return (
    <div>
      {titulo}
      <Row k="Turma" v={p.turma ?? '—'} />
      <Row k="Vence em" v={fmtData(p.vencimento)} />
      <Row k="Meses cheios restantes" v={p.meses_restantes} />
      <Row k="Pago no ciclo" v={`${fmtBRLc(p.pago_no_ciclo)}${p.formas ? ` (${p.formas})` : ''}`} />
      <Row k="Crédito" v={fmtBRLc(p.credito)} />
      <Row k="Diferença a pagar" v={<strong className="text-base font-bold tabular text-[var(--fg)]">{fmtBRLc(p.diferenca)}</strong>} />
      <p className="mt-1 text-[11px] text-[var(--fg-3)]">
        Regra: crédito = pago no ciclo × meses cheios restantes ÷ 12; diferença = {fmtBRLc(VALOR_PROGRAMA_HM)} − crédito.
      </p>
    </div>
  );
}

function CobrancaTab({ conta, repo, canEdit, cobrancas, carregando, flash, onAcordoSalvo }: {
  conta: ContaReceber;
  repo: FinanceiroRepository;
  canEdit: boolean;
  cobrancas: Cobranca[];
  carregando: boolean;
  flash: (msg: string) => void;
  onAcordoSalvo: () => void;
}) {
  const [canal, setCanal] = useState(CANAIS_COBRANCA[0]);
  const [resultado, setResultado] = useState(RESULTADOS_COBRANCA[0]);
  const [obs, setObs] = useState('');
  const [salvando, setSalvando] = useState(false);

  const registrar = async () => {
    setSalvando(true);
    try {
      const r = await repo.registrarCobranca(conta.contato_hm_id, canal, resultado, obs.trim() || null);
      flash(r.msg || (r.ok ? 'Feito!' : 'Falhou.'));
      if (r.ok) { setObs(''); onAcordoSalvo(); }
    } catch {
      flash('Não foi possível registrar a cobrança (erro de rede).');
    } finally {
      setSalvando(false);
    }
  };

  return (
    <div className="space-y-4">
      {canEdit && (
        <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
          <SectionTitle>Registrar cobrança</SectionTitle>
          <div className="grid grid-cols-2 gap-2 mb-2">
            <label className="text-xs text-[var(--fg-3)]">
              Canal
              <select value={canal} onChange={(e) => setCanal(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1.5 text-sm text-[var(--fg)]">
                {CANAIS_COBRANCA.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </label>
            <label className="text-xs text-[var(--fg-3)]">
              Resultado
              <select value={resultado} onChange={(e) => setResultado(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1.5 text-sm text-[var(--fg)]">
                {RESULTADOS_COBRANCA.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </label>
          </div>
          <label className="text-xs text-[var(--fg-3)]">
            Observação (opcional)
            <Textarea value={obs} onChange={(e) => setObs(e.target.value)} className="mt-1" rows={2} placeholder="O que foi combinado…" />
          </label>
          <div className="mt-2 flex justify-end">
            <Button size="sm" onClick={registrar} disabled={salvando}>
              <Icon name="mail" size={13} /> {salvando ? 'Registrando…' : 'Registrar cobrança'}
            </Button>
          </div>
        </section>
      )}

      <section>
        <SectionTitle>Histórico de cobrança</SectionTitle>
        {carregando ? (
          <Loading label="Carregando…" minHeight={100} />
        ) : !cobrancas.length ? (
          <EmptyState title="Nenhuma cobrança registrada" hint="Ainda não há histórico de contato para esta conta." icon="mail" />
        ) : (
          <Timeline
            items={cobrancas.map((c) => ({
              tone: 'accent',
              done: true,
              title: `${c.canal ?? '—'} — ${c.resultado ?? '—'}`,
              meta: fmtDesde(c.quando).label,
              body: c.obs ? `${c.obs}${c.autor ? ` · ${c.autor}` : ''}` : c.autor ? `por ${c.autor}` : undefined,
            }))}
          />
        )}
      </section>
    </div>
  );
}
