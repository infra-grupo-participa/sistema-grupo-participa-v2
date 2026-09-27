'use client';

// Painel "Diagnóstico" da Calculadora de Pro Rata — aberto ao clicar numa
// pessoa em ProrataHM.tsx. Mostra a conta passo a passo, os avisos, cada
// pagamento com o motivo de entrar ou não no ciclo, e permite simular outro
// vencimento/valor do programa (nada é gravado — fn_fin_prorata_diagnostico é
// só leitura).
import { useState } from 'react';
import { Badge, DataTable, Drawer, EmptyState, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { rotuloCategorias, type ProrataPagamento } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';
import { VALOR_PROGRAMA_HM } from '../../domain/prorata-hm';

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
          <div className="text-sm text-[var(--fg-2)]">
            Vence em <strong className="text-[var(--fg)]">{fmtData(diag.pessoa.vencimento_usado)}</strong>
            {simulando && diag.pessoa.vencimento_cadastrado && (
              <span className="text-[var(--fg-3)]"> (cadastrado: {fmtData(diag.pessoa.vencimento_cadastrado)})</span>
            )}
          </div>

          <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 space-y-1.5 text-sm">
            <div className="text-[11px] uppercase tracking-wide text-[var(--fg-3)] font-semibold">Como chegamos neste número</div>
            <div className="text-[var(--fg-2)]">
              Ciclo de {fmtData(diag.ciclo.inicio)} até {fmtData(diag.ciclo.fim)} (hoje: {fmtData(diag.ciclo.hoje)})
            </div>
            <div className="text-[var(--fg-2)]">
              Pago no ciclo {fmtBRLc(diag.calculo.pago_no_ciclo)} ({diag.calculo.pagamentos_no_ciclo} pagamento(s)) ×{' '}
              {diag.calculo.meses_restantes} meses cheios ÷ 12 = crédito {fmtBRLc(diag.calculo.credito)}
            </div>
            <div className="text-[var(--fg-2)]">
              {fmtBRLc(diag.calculo.valor_programa)} − {fmtBRLc(diag.calculo.credito)} = diferença a pagar{' '}
              <strong className="text-base text-[var(--fg)]">{fmtBRLc(diag.calculo.diferenca)}</strong>
            </div>
          </div>

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

function TabelaPagamentos({ pagamentos }: { pagamentos: ProrataPagamento[] }) {
  if (!pagamentos.length) return <EmptyState title="Sem pagamentos nesta conta" />;
  return (
    <DataTable minWidth={760}>
      <Thead>
        <Th>Data</Th><Th>Produto</Th><Th>Forma</Th><Th>Método</Th><Th>Valor</Th><Th>Entra no cálculo?</Th><Th>Motivo</Th>
      </Thead>
      <tbody>
        {pagamentos.map((p) => (
          <Tr key={p.transacao}>
            <Td className="tabular">{fmtData(p.data)}</Td>
            <Td>{p.produto ?? '—'}{p.oferta && <div className="text-[11px] text-[var(--fg-3)]">{p.oferta}</div>}</Td>
            <Td>{rotuloCategorias(p.forma)}</Td>
            <Td>{p.metodo ?? '—'}</Td>
            <Td className="tabular">{fmtBRLc(p.valor)}</Td>
            <Td className={p.entra ? 'font-semibold text-[var(--green)]' : 'text-[var(--fg-4)]'}>{p.entra ? '✓' : '✗'}</Td>
            <Td className="text-[11px] text-[var(--fg-3)]">{p.motivo}</Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}
