'use client';

// Visão "Mesma pessoa?" da Hotmart. Extraído de ui/Hotmart.tsx em 27/09/2026.
// Sem tela própria ainda: será pendurada por outro agente.
//
// E-mail, CPF/CNPJ e conta Hotmart iguais JÁ juntam a pessoa sozinhos (componente
// conexo). Aqui ficam só os casos que precisam de olho humano: telefone ou nome
// igual em pessoas diferentes, e documento compartilhado (escritório/contador).
import { Badge, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import type { IdentidadeRevisao } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';
import { MOTIVO_SUGESTAO, rotuloEvidencia } from './rotulos';
import { BotaoExportarPdf } from '@/shared/ui/pdf/BotaoExportarPdf';
import { chamadasProtocoloFinanceiro } from '../pdf/protocolo';
import { NIVEIS_RELATORIO, rascunhoIdentidade } from '../pdf/documentos';

export function HotmartIdentidade({ repo }: { repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<IdentidadeRevisao[]>(() => repo.loadHotmartIdentidade(), ['identidade']);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando revisão de identidade…" minHeight={200} />;
  const sug = dados.filter((d) => d.tipo === 'sugestao');
  const rev = dados.filter((d) => d.tipo === 'revisao');
  const lista = (v: string[] | null) => (v?.length ? v.join(', ') : '—');
  return (
    <div className="space-y-4">
      {/* Só nível completo (auditoria interna): sem seletor de nível. */}
      <div className="flex flex-wrap items-center gap-2">
        <BotaoExportarPdf montar={() => rascunhoIdentidade(dados)} niveis={NIVEIS_RELATORIO.identidade} chamadas={chamadasProtocoloFinanceiro()} />
      </div>
      <SectionCard title={`${sug.length} par(es) que podem ser a mesma pessoa`}>
        {!sug.length ? <EmptyState title="Nenhum par para conferir" icon="check" /> : (
          <DataTable minWidth={900}>
            <Thead><Th>Motivo</Th><Th>Pessoa A</Th><Th>Pessoa B</Th><Th>Pago A</Th><Th>Pago B</Th></Thead>
            <tbody>
              {sug.map((d) => (
                <Tr key={`${d.motivo}-${d.pessoa_a}-${d.pessoa_b}`}>
                  <Td>
                    <Badge tone="warning">{MOTIVO_SUGESTAO[d.motivo] ?? d.motivo}</Badge>
                    <div className="text-[10px] text-[var(--fg-4)]">
                      {rotuloEvidencia(d.motivo, d.evidencia)}
                    </div>
                  </Td>
                  <Td className="text-xs"><div className="font-medium">{lista(d.nomes_a)}</div><div className="text-[var(--fg-3)] break-all">{lista(d.emails_a)}</div></Td>
                  <Td className="text-xs"><div className="font-medium">{lista(d.nomes_b)}</div><div className="text-[var(--fg-3)] break-all">{lista(d.emails_b)}</div></Td>
                  <Td className="tabular text-xs">{fmtBRL(Number(d.pago_a ?? 0))}</Td>
                  <Td className="tabular text-xs">{fmtBRL(Number(d.pago_b ?? 0))}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
      <SectionCard title={`${rev.length} documento(s) em revisão`}>
        {!rev.length ? <EmptyState title="Nada em revisão" icon="check" /> : (
          <DataTable minWidth={600}>
            <Thead><Th>Documento</Th><Th>Motivo</Th></Thead>
            <tbody>
              {rev.map((d) => (
                <Tr key={d.pessoa_a}><Td className="font-mono text-xs">{d.evidencia}</Td><Td className="text-xs">{d.motivo}</Td></Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}
