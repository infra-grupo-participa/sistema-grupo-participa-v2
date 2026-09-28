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
import { statusTone } from './cor';
import { FichaResumoTopo } from './FichaResumoTopo';
import type { FinanceiroRepository } from '../application/ports';
import { carregarFicha, type Ficha } from '../application/carregar-ficha';
import { rotuloMetodo, type BoardHotmart, type ProrataHM } from '../domain/hotmart';
import { descreverBoletoAberto, fmtMesAno, rotuloParcelamento, temAssinaturaHM, temDadoHotmart } from '../domain/board-hotmart';
import { inicioDoCiclo, prorataDoCard } from '../domain/prorata-hm';
import { ContaProrata } from './hotmart/ContaProrata';
import { Bloco, EmUmaOlhada, PagamentosFicha } from './FichaPagamentos';
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
  // Reorganizada em 27/09 (João: "entender melhor o que está acontecendo"): uma pergunta por aba —
  // quanto falta e por quê (Resumo) · o que pagou (Pagamentos) · quanto dá o pro rata · quem está cobrando.
  const [tab, setTab] = useState<'resumo' | 'pagamentos' | 'prorata' | 'cobranca'>('resumo');
  const hm = hotmartPorCard?.get(conta.contato_hm_id) ?? null;
  const hmCarregando = !hotmartPorCard && !hotmartErro;
  const ehHM = (hm?.origem ?? (/aurum/i.test(conta.produto) ? 'AURUM' : 'HM')) === 'HM';
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
          { k: 'pagamentos', l: 'Pagamentos' },
          ...(ehHM ? [{ k: 'prorata', l: 'Pro rata' }] : []),
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
          <AvisoBoleto hm={hm} hojeISO={hojeISO} />
          <EmUmaOlhada conta={conta} hm={hotmartErro ? null : hm} carregando={hmCarregando} />
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
            <SectionTitle>De onde veio</SectionTitle>
            <Row k="Ação / evento" v={conta.acao_nome ?? '—'} />
            <Row k="Canal" v={conta.canal} />
            <Row k="1ª compra" v={conta.captado_em ? fmtData(conta.captado_em) : 'ainda não pagou'} />
            {conta.captado_sck && <Row k="Link de venda (sck)" v={conta.captado_sck} />}
            {conta.acao_regra && (
              <p className="mt-1 text-[11px] text-[var(--fg-4)]">Identificado por: {conta.acao_regra}.</p>
            )}
          </section>
          <section>
            <SectionTitle>Dados pessoais</SectionTitle>
            <div className="space-y-2 mb-2">
              {conta.email && <CopyField label="E-mail" value={conta.email} />}
              <TelefoneContato telefone={conta.telefone ?? hm?.telefone ?? null} />
            </div>
            <Row k="Documento" v={mascararDoc(conta.documento, canVerDoc)} />
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

      {tab === 'pagamentos' && (
        ficha === null && !erro ? (
          <Loading label="Carregando pagamentos…" minHeight={160} />
        ) : !ficha ? null : (
          <div className="space-y-5">
            <PagamentosFicha conta={conta} repo={repo} board={ficha.extrato} />
            <SecaoBoardHotmart hm={hm} carregando={hmCarregando} erro={hotmartErro && !hotmartPorCard} />
          </div>
        )
      )}

      {tab === 'prorata' && ehHM && (
        <BlocoProrataHM repo={repo} contatoHmId={conta.contato_hm_id} hm={hm} />
      )}

      {tab === 'cobranca' && (
        <div className="space-y-5">
          <CobrancaTab
            conta={conta}
            repo={repo}
            canEdit={canEdit}
            cobrancas={ficha?.cobrancas ?? []}
            carregando={ficha === null && !erro}
            flash={flash}
            onAcordoSalvo={onAcordoSalvo}
          />
          <section>
            <SectionTitle>Histórico do comercial ({ficha?.historicoAtivacao.length ?? 0})</SectionTitle>
            {!ficha ? <Loading label="Carregando…" minHeight={80} /> : !ficha.historicoAtivacao.length ? (
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
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]" role="status">
          {toast}
        </div>
      )}
    </Drawer>
  );
}

/** Números da Hotmart deste contrato em blocos — taxa, líquido, juros, parcelamento. Só leitura: não muda o board.
 *  A assinatura entra em bloco próprio (contrato à parte); os outros pagamentos já estão na lista acima. */
function SecaoBoardHotmart({ hm, carregando, erro }: {
  hm: BoardHotmart | null;
  carregando: boolean;
  erro: boolean;
}) {
  if (carregando) return null;
  const titulo = <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Como pagou na Hotmart</div>;
  if (erro) return <section>{titulo}<p className="text-[11px] text-[var(--fg-3)]">Números da Hotmart indisponíveis agora. O board não depende deles.</p></section>;
  if (!temDadoHotmart(hm)) return <section>{titulo}<p className="text-[11px] text-[var(--fg-3)]">Esta pessoa não foi encontrada na Hotmart.</p></section>;
  const parcelamento = rotuloParcelamento(hm.parcelas_max);
  return (
    <section>
      {titulo}
      {hm.cards_da_pessoa > 1 && (
        <p className="mb-2 text-[11px] text-[var(--fg-3)]">
          Esta pessoa tem {hm.cards_da_pessoa} cards: os números abaixo são dela inteira e se repetem em cada card.
        </p>
      )}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <Bloco rotulo="Recebido (bruto)" valor={fmtBRLc(hm.pago_bruto)} detalhe={`${hm.vendas_pagas} venda${hm.vendas_pagas === 1 ? '' : 's'} deste contrato`} />
        <Bloco rotulo="Taxa da Hotmart" valor={fmtBRLc(hm.taxa_hotmart)} detalhe={hm.coproducao > 0 ? `coprodução ${fmtBRLc(hm.coproducao)}` : null} />
        <Bloco rotulo="Líquido" tom="verde" valor={fmtBRLc(hm.liquido)} detalhe="fica para nós" />
        <Bloco rotulo="Cliente pagou" valor={fmtBRLc(hm.cobrado_cliente)} detalhe={hm.juros > 0 ? `juros ${fmtBRLc(hm.juros)} (ficam com a Hotmart)` : 'sem juros'} />
        <Bloco rotulo="Como pagou" valor={rotuloMetodo(hm.forma_pagamento_principal)} detalhe={parcelamento ?? null} />
        <Bloco rotulo="Último pagamento" valor={hm.ultimo_pagamento_em ? fmtData(hm.ultimo_pagamento_em) : '—'}
          detalhe={hm.ultimo_pagamento_valor != null ? fmtBRLc(hm.ultimo_pagamento_valor) : null} />
      </div>
      {temAssinaturaHM(hm) && <div className="mt-3"><BlocoAssinaturaHM hm={hm} /></div>}
      {hm.sincronizado_em && (
        <p className="mt-2 text-[11px] text-[var(--fg-4)]">Hotmart sincronizada em {fmtDataHora(hm.sincronizado_em)}.</p>
      )}
    </section>
  );
}

/** Boleto/Pix gerado e não pago (20260928o): o que é, quanto, há quanto tempo. Some quando não há. */
function AvisoBoleto({ hm, hojeISO }: { hm: BoardHotmart | null; hojeISO: string }) {
  const b = descreverBoletoAberto(hm, hojeISO, fmtBRLc);
  if (!b) return null;
  return (
    <section className="flex items-start gap-2 rounded-[var(--r-lg)] border border-dashed border-[var(--info-border)] bg-[var(--info-subtle)] px-3 py-2.5">
      <Icon name="receipt" size={16} className="mt-0.5 shrink-0 text-[var(--info)]" />
      <div className="text-sm">
        <div className="font-semibold text-[var(--fg)]">{b.titulo}</div>
        <div className="text-xs text-[var(--fg-2)]">{b.detalhe} Veja na aba Pagamentos (filtro «Não pagos»).</div>
      </div>
    </section>
  );
}

/** Telefone com copiar e WhatsApp. Mascarado (···1234) para quem não pode ver dado pessoal completo: aí só mostra. */
export function TelefoneContato({ telefone }: { telefone: string | null }) {
  if (!telefone) return <Row k="Telefone" v="não informado" />;
  const digitos = telefone.replace(/\D/g, '');
  const mascarado = telefone.includes('·') || digitos.length < 10;
  if (mascarado) return <Row k="Telefone" v={telefone} />;
  const comDdi = digitos.length <= 11 ? `55${digitos}` : digitos;
  return (
    <div className="space-y-1">
      <CopyField label="Telefone" value={telefone} />
      <a href={`https://wa.me/${comDdi}`} target="_blank" rel="noopener noreferrer"
        className="inline-flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] focus-visible:ring-2">
        <Icon name="arrow-up-right" size={13} /> Abrir no WhatsApp
      </a>
    </div>
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

/** Pro rata HM → Programa. fn_fin_prorata_hm carregada SOB DEMANDA na 1ª ficha
 *  aberta e reaproveitada (application/carregar-prorata.ts) — nunca por card. */
function BlocoProrataHM({ repo, contatoHmId, hm }: { repo: FinanceiroRepository; contatoHmId: string; hm: BoardHotmart | null }) {
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
      <ContaProrata c={{
        pago: p.pago_no_ciclo, pagamentos: p.pagamentos_no_ciclo, formas: p.formas, vencimento: p.vencimento,
        inicioCiclo: inicioDoCiclo(p.vencimento), meses: p.meses_restantes, credito: p.credito,
        valorPrograma: VALOR_PROGRAMA_HM, diferenca: p.diferenca,
      }} />
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
