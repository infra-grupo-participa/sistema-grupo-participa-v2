'use client';

// Painel "Saúde do financeiro": roda as checagens de integridade HM ao vivo
// (fn_fin_saude) + lista ofertas fora do catálogo (fn_fin_ofertas_orfas). Torna o
// "não permita erros" visível — o furo nunca mais fica silencioso.
import { useEffect, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { OfertaOrfa, SaudeCheck } from '../domain/types';
import { loadOfertasOrfas, loadSaude } from './financeiro-data';
import { Badge, DataTable, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';

export function SaudeFinanceiro() {
  const [checks, setChecks] = useState<SaudeCheck[] | null>(null);
  const [orfas, setOrfas] = useState<OfertaOrfa[] | null>(null);

  useEffect(() => {
    let vivo = true;
    loadSaude().then((c) => { if (vivo) setChecks(c); });
    loadOfertasOrfas().then((o) => { if (vivo) setOrfas(o); });
    return () => { vivo = false; };
  }, []);

  const tudoOk = checks?.every((c) => c.ok) ?? false;
  const pendencias = checks?.filter((c) => !c.ok).length ?? 0;

  return (
    <div className="mt-4">
      <SectionCard
        title={
          <span className="inline-flex items-center gap-2">
            <Icon name="check-circle" size={16} /> Saúde do financeiro
            {checks && (tudoOk
              ? <Badge tone="success">Tudo certo</Badge>
              : <Badge tone="danger">{pendencias} {pendencias === 1 ? 'pendência' : 'pendências'}</Badge>)}
          </span>
        }
        subtitle="Checagens de integridade ao vivo — se algo acender vermelho, tem furo a tratar."
      >
        {checks === null ? (
          <Loading label="Verificando…" minHeight={120} />
        ) : (
          <div className="space-y-1.5">
            {checks.map((c) => (
              <div key={c.check_id} className="flex items-center gap-2 text-sm">
                <Icon name={c.ok ? 'check' : 'alert'} size={14} style={{ color: c.ok ? 'var(--green)' : 'var(--red)' }} />
                <span className="text-[var(--fg-2)]">{c.label}</span>
                {!c.ok && <span className="ml-auto font-semibold tabular text-[var(--red)]">{c.valor}</span>}
              </div>
            ))}
          </div>
        )}

        {orfas && orfas.length > 0 && (
          <div className="mt-4">
            <div className="text-xs text-[var(--fg-3)] mb-2">
              Ofertas usadas em compras mas <strong className="text-[var(--red)]">sem categoria no catálogo</strong> —
              precisam ser catalogadas, senão a compra escapa da esteira e da razão.
            </div>
            <DataTable>
              <Thead>
                <Th>Oferta</Th>
                <Th>Produto</Th>
                <Th className="text-right">Compras</Th>
                <Th className="text-right">Faixa</Th>
                <Th>Último</Th>
                <Th>Exemplo</Th>
              </Thead>
              <tbody>
                {orfas.map((o) => (
                  <Tr key={o.oferta_codigo}>
                    <Td className="tabular text-xs text-[var(--fg)]">{o.oferta_codigo}</Td>
                    <Td className="text-xs text-[var(--fg-2)]">{o.produto_nome} ({o.produto_id})</Td>
                    <Td className="tabular text-xs text-right">{o.compras}</Td>
                    <Td className="tabular text-xs text-right text-[var(--fg-2)]">
                      {fmtBRL(o.menor)}{o.menor !== o.maior ? ` – ${fmtBRL(o.maior)}` : ''}
                    </Td>
                    <Td className="text-xs text-[var(--fg-3)] whitespace-nowrap">{fmtData(o.ultimo)}</Td>
                    <Td className="text-xs text-[var(--fg-2)]">{o.exemplo_aluno}</Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          </div>
        )}
      </SectionCard>
    </div>
  );
}
