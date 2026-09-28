'use client';

// Aba Relatórios: seletor de 4 relatórios.
// "Carteira do board" = seleção de colunas + export XLSX e "PDF" (window.print()) —
// a MESMA tabela renderizada aqui é o que vai para o papel; print CSS de
// globals.css cuida de tema claro/paginação; nada de componente exclusivo pra impressão.
// Os outros 3 são leitura do espelho da Hotmart (schema fin), já prontos em ui/hotmart/*.
import { useMemo, useState } from 'react';
import { Badge, Button, Checkbox, DataTable, EmptyState, SectionCard, Td, Th, Thead, Toolbar, Tr, useFlash, Toast } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber } from '../domain/types';
import { COLUNAS_PADRAO, COLUNAS_RELATORIO, montarRelatorio } from '../application/montar-relatorio';
import type { FinanceiroRepository } from '../application/ports';
import { ROTULO_FAMILIA, type BoardHotmart, type FamiliaHotmart } from '../domain/hotmart';
import { statusTone } from './cor';
import { exportarXLSX, exportarPDF, formatarCelulaTela } from './exportar';
import { AceleraParaHM } from './hotmart/AceleraParaHM';
import { HotmartConciliacao } from './hotmart/HotmartConciliacao';
import { HotmartIdentidade } from './hotmart/HotmartIdentidade';
import { HotmartPessoas } from './hotmart/HotmartPessoas';

type TipoRelatorio = 'board' | 'pessoas' | 'conciliacao' | 'identidade' | 'acelera';

const RELATORIOS: { tipo: TipoRelatorio; rotulo: string }[] = [
  { tipo: 'board', rotulo: 'Carteira do board' },
  { tipo: 'pessoas', rotulo: 'Pessoas na Hotmart' },
  { tipo: 'conciliacao', rotulo: 'Conciliação Hotmart × banco' },
  { tipo: 'identidade', rotulo: 'Mesma pessoa?' },
  { tipo: 'acelera', rotulo: 'Acelera → HM' },
];

/** Botão do seletor de relatório — mesmo padrão visual do seletor de família (FaturamentoDiario.tsx). */
function BotaoRelatorio({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      onClick={onClick}
      className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold disabled:opacity-50 ${ativo ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}
    >
      {children}
    </button>
  );
}

/** Seletor de família (HM / Aurum / Acelera Holding) — usado pelos relatórios que leem por família. */
function SeletorFamilia({ familia, onChange }: { familia: FamiliaHotmart; onChange: (f: FamiliaHotmart) => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {(['HM', 'AURUM', 'ACELERA'] as FamiliaHotmart[]).map((f) => (
        <BotaoRelatorio key={f} ativo={familia === f} onClick={() => onChange(f)}>
          {ROTULO_FAMILIA[f]}
        </BotaoRelatorio>
      ))}
    </div>
  );
}

export function Relatorios({
  contas, turma, canVerDoc, repo, hotmartPorCard,
}: {
  contas: ContaReceber[];
  turma: string | null;
  canVerDoc: boolean;
  repo: FinanceiroRepository;
  hotmartPorCard: Map<string, BoardHotmart> | null;
}) {
  const [tipo, setTipo] = useState<TipoRelatorio>('board');
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 gp-print-hide">
        {RELATORIOS.map((r) => (
          <BotaoRelatorio key={r.tipo} ativo={tipo === r.tipo} onClick={() => setTipo(r.tipo)}>
            {r.rotulo}
          </BotaoRelatorio>
        ))}
      </div>

      {tipo === 'board' && <CarteiraDoBoard contas={contas} turma={turma} canVerDoc={canVerDoc} hotmartPorCard={hotmartPorCard} />}

      {tipo === 'pessoas' && (
        <div className="space-y-4">
          <SeletorFamilia familia={familia} onChange={setFamilia} />
          <HotmartPessoas repo={repo} familia={familia} />
        </div>
      )}

      {tipo === 'conciliacao' && (
        <div className="space-y-4">
          <SeletorFamilia familia={familia} onChange={setFamilia} />
          <HotmartConciliacao repo={repo} familia={familia} />
        </div>
      )}

      {tipo === 'identidade' && <HotmartIdentidade repo={repo} />}

      {tipo === 'acelera' && <AceleraParaHM repo={repo} />}
    </div>
  );
}

/** Relatório original da aba: seleção de colunas do board + export XLSX/PDF. */
function CarteiraDoBoard({
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
