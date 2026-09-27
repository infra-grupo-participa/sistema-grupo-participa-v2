'use client';

// Extrato completo de uma pessoa na Hotmart — reusado na ficha do board
// (ui/FichaDrawer.tsx) e na linha expansível de Pessoas (HotmartPessoas.tsx).
// Extraído de ui/Hotmart.tsx em 27/09/2026.
import { Badge, DataTable, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { fmtBRL, fmtDataHora } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { ROTULO_GRUPO, type TransacaoHotmart } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';

const TOM_GRUPO: Record<TransacaoHotmart['grupo'], Tone> = {
  pago: 'success', estornado: 'danger', atrasado: 'danger', em_aberto: 'warning', recusado: 'neutral', expirado: 'neutral', outro: 'neutral',
};

export function ExtratoHotmart({ email, repo }: { email: string; repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<TransacaoHotmart[]>(() => repo.loadHotmartExtrato(email), [email]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando histórico da Hotmart…" minHeight={80} />;
  if (!dados.length) return <p className="text-xs text-[var(--fg-3)]">Nenhuma transação na Hotmart com este e-mail.</p>;
  return (
    <DataTable minWidth={760}>
      <Thead><Th>Pedido</Th><Th>E-mail</Th><Th>Situação</Th><Th>Oferta</Th><Th>Bruto</Th><Th>Cobrado</Th><Th>Líquido</Th><Th>Pagamento</Th><Th>Origem</Th></Thead>
      <tbody>
        {dados.map((t) => (
          <Tr key={t.transacao}>
            <Td className="tabular">{t.pedido_em ? fmtDataHora(t.pedido_em) : '—'}<div className="text-[10px] text-[var(--fg-4)]">{t.transacao}</div></Td>
            <Td className="text-[11px] text-[var(--fg-3)] break-all">{t.email}</Td>
            <Td><Badge tone={TOM_GRUPO[t.grupo]}>{ROTULO_GRUPO[t.grupo]}</Badge></Td>
            <Td className="text-xs">{t.oferta_codigo ?? '—'}<div className="text-[10px] text-[var(--fg-3)]">{t.produto}</div></Td>
            <Td className="tabular">{fmtBRL(Number(t.valor_oferta ?? 0))}</Td>
            <Td className="tabular text-[var(--fg-3)]">{fmtBRL(Number(t.cobrado ?? 0))}</Td>
            <Td className="tabular text-[var(--green)]">{t.liquido != null ? fmtBRL(Number(t.liquido)) : '—'}{t.liquido_estimado && ' ≈'}</Td>
            <Td className="text-xs">{t.metodo ?? '—'}{t.parcelas && t.parcelas > 1 ? ` · ${t.parcelas}x` : ''}{t.recorrencia ? ` · parcela ${t.recorrencia}` : ''}</Td>
            <Td className="text-[11px] text-[var(--fg-3)] break-all">{t.origem_sck ?? '—'}</Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}
