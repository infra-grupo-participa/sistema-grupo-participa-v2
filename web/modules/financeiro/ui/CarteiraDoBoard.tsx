'use client';

// "Carteira do board" = seleção de colunas + export XLSX e PDF oficial.
// O PDF sai do MESMO dataset da tabela (colunas selecionadas, contas do recorte)
// via ui/pdf/documentos.ts → shared/ui/pdf (identidade Grupo Participa + protocolo).
// O antigo "Exportar PDF (imprimir)" (window.print()) saiu em 28/09/2026.
import { useMemo, useState } from 'react';
import { Badge, Button, Checkbox, DataTable, EmptyState, SectionCard, Td, Th, Thead, Toolbar, Tr, useFlash, Toast } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber } from '../domain/types';
import { COLUNAS_PADRAO, COLUNAS_RELATORIO, montarRelatorio } from '../application/montar-relatorio';
import type { BoardHotmart } from '../domain/hotmart';
import { statusTone } from './cor';
import { exportarXLSX, formatarCelulaTela } from './exportar';
import { BotaoExportarPdf } from '@/shared/ui/pdf/BotaoExportarPdf';
import { NIVEIS_RELATORIO, rascunhoCarteira, recorteCarteira } from './pdf/documentos';
import { chamadasProtocoloFinanceiro } from './pdf/protocolo';

/** Relatório original da aba: seleção de colunas do board + export XLSX e PDF com protocolo. */
export function CarteiraDoBoard({
  contas, turma, canVerDoc, hotmartPorCard,
}: {
  contas: ContaReceber[];
  turma: string | null;
  canVerDoc: boolean;
  hotmartPorCard: Map<string, BoardHotmart> | null;
}) {
  const [selecionadas, setSelecionadas] = useState<string[]>(COLUNAS_PADRAO);
  const [exportando, setExportando] = useState(false);
  const { toast, flash } = useFlash();

  const dataset = useMemo(
    () => montarRelatorio(contas, selecionadas, { canVerDoc, hotmartPorCard }),
    [contas, selecionadas, canVerDoc, hotmartPorCard],
  );

  // `dataset` guarda só o rótulo (statusLabel) — application não formata cor,
  // é camada de apresentação (mesma regra de montar-relatorio.ts). Mapa por
  // contato_hm_id (== linha.chave) para achar o status_financeiro cru na hora
  // de escolher o tom do Badge, sem mudar o formato do dataset (o export
  // XLSX/PDF continua recebendo string pura de formatarCelulaTela).
  const statusPorLinha = useMemo(
    () => new Map(contas.map((c) => [c.contato_hm_id, c.status_financeiro])),
    [contas],
  );

  const toggle = (key: string) =>
    setSelecionadas((s) => (s.includes(key) ? s.filter((k) => k !== key) : [...s, key]));

  const exportar = async () => {
    setExportando(true);
    try {
      const n = await exportarXLSX(dataset, turma);
      flash(n ? `${n} ${n === 1 ? 'linha exportada' : 'linhas exportadas'}.` : 'Nenhuma linha para exportar.');
    } catch {
      flash('Não foi possível gerar a planilha.');
    } finally {
      setExportando(false);
    }
  };

  return (
    <div className="space-y-4">
      <SectionCard title="Colunas do relatório" className="gp-print-hide">
        <div className="flex flex-wrap gap-x-4 gap-y-2">
          {COLUNAS_RELATORIO.map((c) => (
            <Checkbox key={c.key} checked={selecionadas.includes(c.key)} onChange={() => toggle(c.key)} label={c.label} />
          ))}
        </div>
      </SectionCard>

      <Toolbar className="gp-print-hide">
        <Button variant="ghost" size="sm" onClick={exportar} disabled={exportando || !dataset.linhas.length}>
          <Icon name="download" size={14} /> {exportando ? 'Gerando…' : 'Exportar Excel'}
        </Button>
        <BotaoExportarPdf
          montar={() => rascunhoCarteira(dataset, contas, recorteCarteira(turma))}
          niveis={NIVEIS_RELATORIO.board}
          chamadas={chamadasProtocoloFinanceiro()}
          desabilitado={!dataset.linhas.length}
        />
        <span className="text-xs text-[var(--fg-3)] tabular">{dataset.linhas.length} linha(s)</span>
      </Toolbar>

      {!dataset.linhas.length ? (
        <EmptyState title="Nenhuma conta para relatar" hint="Ajuste os filtros do board antes de vir para cá." icon="file" />
      ) : (
        <DataTable>
          <Thead>
            {dataset.colunas.map((c) => <Th key={c.key}>{c.label}</Th>)}
          </Thead>
          <tbody>
            {dataset.linhas.map((linha) => (
              <Tr key={linha.chave}>
                {dataset.colunas.map((c) => (
                  <Td key={c.key} className={c.tipo === 'moeda' || c.tipo === 'numero' ? 'tabular' : undefined}>
                    {c.key === 'status' ? (
                      <Badge tone={statusTone(statusPorLinha.get(linha.chave) ?? '')}>
                        {formatarCelulaTela(c, linha.valores[c.key])}
                      </Badge>
                    ) : (
                      formatarCelulaTela(c, linha.valores[c.key])
                    )}
                  </Td>
                ))}
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
