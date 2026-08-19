'use client';

// Ficha do aluno — foco no que o financeiro precisa: por que ainda não pagou
// e o que cobrar do comercial. Reusa Drawer/Tabs/Row do design system.
import { useEffect, useState } from 'react';
import {
  AvatarInicial, Badge, Button, Drawer, EmptyState, Loading, Row, Tabs, Textarea, Timeline, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData, fmtDesde } from '@/shared/ui/format';
import type { ContaReceber, Cobranca, InteracaoAtivacao } from '../domain/types';
import { contaMorta, mascararDoc, statusLabel, statusTone } from '../domain/financeiro';
import type { FinanceiroRepository } from '../application/ports';
import { carregarFicha, type Ficha } from '../application/carregar-ficha';

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

export function FichaDrawer({ conta, repo, canEdit, canVerDoc, onClose, onAcordoSalvo }: {
  conta: ContaReceber;
  repo: FinanceiroRepository;
  canEdit: boolean;
  canVerDoc: boolean;
  onClose: () => void;
  onAcordoSalvo: () => void;
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
          <section>
            <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Dados pessoais</h3>
            <Row k="E-mail" v={conta.email} />
            <Row k="Telefone" v={conta.telefone} />
            <Row k="Documento" v={mascararDoc(conta.documento, canVerDoc)} />
            <Row k="Canal de origem" v={conta.canal} />
            <Row k="Vendedor" v={conta.vendedor} />
            <Row k="Situação na ativação" v={conta.estagio_nome} />
          </section>
          <section>
            <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Por que ainda não pagou</h3>
            <Row k="Pacote" v={conta.pacote != null ? fmtBRLc(conta.pacote) : '—'} />
            <Row k="Já pago (bruto)" v={fmtBRLc(conta.total_pago_bruto)} />
            <Row k="Falta pagar" v={conta.saldo_a_pagar != null ? fmtBRLc(conta.saldo_a_pagar) : 'Sem valor definido'} />
            <Row k="Vencimento combinado" v={conta.vencimento ? fmtData(conta.vencimento) : 'Sem acordo registrado'} />
            <Row k="Dias em atraso" v={conta.dias_atraso != null && conta.dias_atraso > 0 ? `${conta.dias_atraso} dias` : '—'} />
            <Row k="Solicitou cancelamento" v={conta.solicitou_cancelamento ? 'Sim' : 'Não'} />
            {conta.oferta_codigo && <Row k="Oferta enviada" v={`${conta.oferta_codigo} (${fmtData(conta.oferta_enviada_em)})`} />}
          </section>
          {morta && (
            <section>
              <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Encerramento</h3>
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
              <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Lançamentos ({ficha.extrato.length})</h3>
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
              <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Compras Hotmart ({ficha.compras.length})</h3>
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
                        <Badge tone={c.pago ? 'success' : c.pendente ? 'warning' : c.morto ? 'danger' : 'neutral'}>{c.status}</Badge>
                      </span>
                    }
                  />
                ))
              )}
            </section>
            <section>
              <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Histórico do comercial ({ficha.historicoAtivacao.length})</h3>
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
          <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Registrar cobrança</h3>
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
        <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Histórico de cobrança</h3>
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
