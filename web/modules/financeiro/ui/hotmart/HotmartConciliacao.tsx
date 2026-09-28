'use client';

// Visão "Conciliação" da Hotmart — o que a Hotmart tem e o banco não (webhook
// que falhou). Extraído de ui/Hotmart.tsx em 27/09/2026. Sem tela própria
// ainda: será pendurada em Relatórios por outro agente.
import { Badge, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import type { DivergenciaHotmart, FamiliaHotmart } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';
import { ROTULO_DIVERGENCIA } from './rotulos';
import { BotaoExportarPdf } from '@/shared/ui/pdf/BotaoExportarPdf';
import { chamadasProtocoloFinanceiro } from '../pdf/protocolo';
import { NIVEIS_RELATORIO, rascunhoConciliacao, recorteConciliacao } from '../pdf/documentos';

export function HotmartConciliacao({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const { dados, erro } = useCarga<DivergenciaHotmart[]>(() => repo.loadHotmartConciliacao(familia), [familia]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Conferindo Hotmart × banco…" minHeight={200} />;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <BotaoExportarPdf
          montar={() => rascunhoConciliacao(dados, recorteConciliacao(familia))}
          niveis={NIVEIS_RELATORIO.conciliacao}
          chamadas={chamadasProtocoloFinanceiro()}
        />
      </div>
      <SectionCard title={dados.length ? `${dados.length} divergência(s)` : 'Hotmart e banco batem'}>
        {!dados.length ? <EmptyState title="Nenhuma divergência" icon="check" /> : (
          <DataTable minWidth={900}>
            <Thead><Th>Tipo</Th><Th>Transação</Th><Th>E-mail</Th><Th>Hotmart</Th><Th>Banco</Th><Th>Pedido</Th><Th>Detalhe</Th></Thead>
            <tbody>
              {dados.map((d, i) => (
                <Tr key={`${d.tipo}-${d.transacao ?? i}`}>
                  <Td><Badge tone={d.tipo === 'falta_no_banco' || d.tipo === 'produto_sem_webhook' ? 'danger' : 'warning'}>{ROTULO_DIVERGENCIA[d.tipo]}</Badge></Td>
                  <Td className="font-mono text-xs">{d.transacao ?? '—'}</Td>
                  <Td className="text-xs break-all">{d.email ?? '—'}</Td>
                  <Td className="text-xs">{d.status_hotmart ?? ''}{d.valor_hotmart != null ? ` · ${fmtBRL(Number(d.valor_hotmart))}` : ''}</Td>
                  <Td className="text-xs">{d.status_banco ?? ''}{d.valor_banco != null ? ` · ${fmtBRL(Number(d.valor_banco))}` : ''}</Td>
                  <Td className="tabular text-xs">{d.pedido_em ? fmtData(d.pedido_em) : '—'}</Td>
                  <Td className="text-xs text-[var(--fg-2)]">{d.detalhe}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}
