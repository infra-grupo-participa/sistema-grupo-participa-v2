'use client';

// Aba Relatórios: seleção de colunas + export XLSX e "PDF" (window.print()).
// A MESMA tabela renderizada aqui é o que vai para o papel — print CSS de
// globals.css cuida de tema claro/paginação; nada de componente exclusivo pra impressão.
import { useMemo, useState } from 'react';
import { Button, Checkbox, DataTable, EmptyState, SectionCard, Td, Th, Thead, Toolbar, Tr, useFlash, Toast } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber } from '../domain/types';
import { COLUNAS_PADRAO, COLUNAS_RELATORIO, montarRelatorio } from '../application/montar-relatorio';
import { exportarXLSX, exportarPDF, formatarCelulaTela } from './exportar';

export function Relatorios({ contas, turma, canVerDoc }: { contas: ContaReceber[]; turma: string | null; canVerDoc: boolean }) {
  const [selecionadas, setSelecionadas] = useState<string[]>(COLUNAS_PADRAO);
  const [exportando, setExportando] = useState(false);
  const { toast, flash } = useFlash();

  const dataset = useMemo(
    () => montarRelatorio(contas, selecionadas, { canVerDoc }),
    [contas, selecionadas, canVerDoc],
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
      <SectionCard title="Colunas do relatório" subtitle="Selecione o que entra no export (XLSX ou PDF/impressão)." className="gp-print-hide">
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
        <Button variant="ghost" size="sm" onClick={exportarPDF} disabled={!dataset.linhas.length}>
          <Icon name="file" size={14} /> Exportar PDF (imprimir)
        </Button>
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
                    {formatarCelulaTela(c, linha.valores[c.key])}
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
