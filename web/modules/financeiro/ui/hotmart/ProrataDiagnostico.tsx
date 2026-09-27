'use client';

// Painel "Diagnóstico" da Calculadora de Pro Rata — aberto ao clicar numa
// pessoa em ProrataHM.tsx. Mostra a conta passo a passo, os avisos, cada
// pagamento com o motivo de entrar ou não no ciclo, e permite simular outro
// vencimento/valor do programa (nada é gravado — fn_fin_prorata_diagnostico é
// só leitura).
import { useState } from 'react';
import { Badge, Drawer, EmptyState, Loading } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { rotuloCategorias, rotuloMetodo, type ProrataPagamento } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';
import { VALOR_PROGRAMA_HM } from '../../domain/prorata-hm';
import { ContaProrata } from './ContaProrata';

const VALOR_PADRAO = VALOR_PROGRAMA_HM;

export function ProrataDiagnostico({ repo, email, onClose }: {
  repo: FinanceiroRepository; email: string; onClose: () => void;
}) {
  // Parâmetros efetivamente aplicados na consulta — só mudam ao clicar "Recalcular".
  const [vencimentoAplicado, setVencimentoAplicado] = useState<string | null>(null);
  const [valorAplicado, setValorAplicado] = useState(VALOR_PADRAO);
  // Rascunho dos campos — não recalcula a cada tecla digitada.
  const [vencimentoInput, setVencimentoInput] = useState('');
  const [valorInput, setValorInput] = useState(String(VALOR_PADRAO));

  const { dados: diag, erro } = useCarga(
    () => repo.loadProrataDiagnostico(email, vencimentoAplicado, valorAplicado),
    [email, vencimentoAplicado, valorAplicado],
  );

  const simulando = vencimentoAplicado != null || valorAplicado !== VALOR_PADRAO;

  const recalcular = () => {
    setVencimentoAplicado(vencimentoInput || null);
    const v = Number(String(valorInput).replace(',', '.'));
    setValorAplicado(Number.isFinite(v) && v > 0 ? v : VALOR_PADRAO);
  };

  const voltarCadastrado = () => {
    setVencimentoAplicado(null);
    setValorAplicado(VALOR_PADRAO);
    setVencimentoInput('');
    setValorInput(String(VALOR_PADRAO));
  };

  return (
    <Drawer
      open
      onClose={onClose}
      title={diag?.pessoa.nome ?? 'Diagnóstico do pro rata'}
      subtitle={diag?.pessoa.emails.join(' · ')}
      badges={diag && (
        <>
          {diag.pessoa.turma && <Badge>{diag.pessoa.turma}</Badge>}
          {diag.pessoa.no_gps && <Badge tone="info">No GPS</Badge>}
          {simulando && <Badge tone="warning">SIMULAÇÃO — nada é gravado</Badge>}
        </>
      )}
    >
      {erro ? <Erro msg={erro} /> : !diag ? <Loading label="Carregando diagnóstico…" minHeight={160} /> : (
        <div className="space-y-4">
          {simulando && (
            <div className="text-sm text-[var(--fg-2)]">
              Simulando vencimento em <strong className="text-[var(--fg)]">{fmtData(diag.pessoa.vencimento_usado)}</strong>
              {diag.pessoa.vencimento_cadastrado && (
                <span className="text-[var(--fg-3)]"> (cadastrado: {fmtData(diag.pessoa.vencimento_cadastrado)})</span>
              )}
            </div>
          )}

          <ContaProrata c={{
            pago: Number(diag.calculo.pago_no_ciclo), pagamentos: Number(diag.calculo.pagamentos_no_ciclo),
            vencimento: diag.ciclo.fim, inicioCiclo: diag.ciclo.inicio, meses: Number(diag.calculo.meses_restantes),
            credito: Number(diag.calculo.credito), valorPrograma: Number(diag.calculo.valor_programa),
            diferenca: Number(diag.calculo.diferenca),
          }} />

          {diag.avisos.length > 0 && (
            <div className="space-y-1.5">
              {diag.avisos.map((a) => (
                <div key={a} className="flex items-start gap-2 rounded-[var(--r-md)] bg-[var(--yellow-subtle)] p-3 text-sm">
                  <Icon name="alert" size={16} className="mt-0.5 shrink-0 text-[var(--yellow)]" />
                  <span className="text-[var(--fg-2)]">{a}</span>
                </div>
              ))}
            </div>
          )}

          <div className="rounded-[var(--r-md)] border border-[var(--border)] p-3">
            <div className="mb-2 text-[11px] uppercase tracking-wide text-[var(--fg-3)] font-semibold">Simular outro cenário</div>
            <div className="flex flex-wrap items-end gap-2">
              <label className="text-xs text-[var(--fg-3)]">
                Vencimento (simular)
                <input
                  type="date" value={vencimentoInput} onChange={(e) => setVencimentoInput(e.target.value)}
                  className="mt-1 block rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-sm text-[var(--fg)]"
                />
              </label>
              <label className="text-xs text-[var(--fg-3)]">
                Valor do programa
                <input
                  type="number" value={valorInput} onChange={(e) => setValorInput(e.target.value)}
                  className="mt-1 block w-32 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-sm text-[var(--fg)]"
                />
              </label>
              <button
                type="button" onClick={recalcular}
                className="rounded-[var(--r-md)] border border-[var(--accent)] px-3 py-1.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)]"
              >
                Recalcular
              </button>
              {simulando && (
                <button
                  type="button" onClick={voltarCadastrado}
                  className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]"
                >
                  Voltar ao cadastrado
                </button>
              )}
            </div>
          </div>

          {diag.board && (
            <div className="text-sm text-[var(--fg-2)]">
              Card no board: {diag.board.status ?? '—'} · pago {fmtBRLc(diag.board.pago)} · saldo {fmtBRLc(diag.board.saldo)}
              {diag.board.canal && <span className="text-[var(--fg-3)]"> · {diag.board.canal}</span>}
            </div>
          )}

          <TabelaPagamentos pagamentos={diag.pagamentos} />
        </div>
      )}
    </Drawer>
  );
}

/** Cada pagamento em uma linha que cabe na gaveta: o que foi, quanto, e se entrou na conta (com o motivo). */
function TabelaPagamentos({ pagamentos }: { pagamentos: ProrataPagamento[] }) {
  if (!pagamentos.length) return <EmptyState title="Sem pagamentos nesta conta" />;
  return (
    <section>
      <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Pagamentos da pessoa e se entram na conta</div>
      <ul className="divide-y divide-[var(--border)] rounded-[var(--r-lg)] border border-[var(--border)]">
        {pagamentos.map((p) => (
          <li key={p.transacao} className="flex items-start gap-3 px-3 py-2">
            <span
              aria-label={p.entra ? 'Entra no cálculo' : 'Não entra no cálculo'}
              className={`mt-0.5 w-4 shrink-0 text-center text-sm font-bold ${p.entra ? 'text-[var(--green)]' : 'text-[var(--fg-4)]'}`}
            >
              {p.entra ? '✓' : '✗'}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                <span className="text-sm text-[var(--fg)]">
                  <span className="tabular">{fmtData(p.data)}</span> · {rotuloCategorias(p.forma)}
                  <span className="text-[var(--fg-3)]"> · {p.produto ?? '—'}{p.oferta ? ` (${p.oferta})` : ''}</span>
                </span>
                <span className={`tabular text-sm font-semibold ${p.entra ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>{fmtBRLc(p.valor)}</span>
              </div>
              <div className="text-[11px] text-[var(--fg-3)]">{rotuloMetodo(p.metodo)} · {p.motivo}</div>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
