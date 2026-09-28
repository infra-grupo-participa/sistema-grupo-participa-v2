'use client';

// Aba Relatórios: dropdown com os 6 tipos de relatório.
// "Carteira do board" (seleção de colunas + export XLSX/PDF) vive em ./CarteiraDoBoard.tsx.
// Os outros 5 são leitura do espelho da Hotmart (schema fin), já prontos em ui/hotmart/*.
import { useState } from 'react';
import { Badge, Button, FilterSelect, Input, SectionCard } from '@/shared/ui/components';
import type { ContaReceber } from '../domain/types';
import type { FinanceiroRepository, RelatorioVerificado } from '../application/ports';
import { FAMILIAS_EM_ORDEM, ROTULO_FAMILIA, type BoardHotmart, type FamiliaHotmart } from '../domain/hotmart';
import { CarteiraDoBoard } from './CarteiraDoBoard';
import { AceleraParaHM } from './hotmart/AceleraParaHM';
import { ProrataHM } from './hotmart/ProrataHM';
import { HotmartConciliacao } from './hotmart/HotmartConciliacao';
import { HotmartIdentidade } from './hotmart/HotmartIdentidade';
import { HotmartPessoas } from './hotmart/HotmartPessoas';

type TipoRelatorio = 'board' | 'pessoas' | 'conciliacao' | 'identidade' | 'acelera' | 'prorata';

const RELATORIOS: { tipo: TipoRelatorio; rotulo: string }[] = [
  { tipo: 'board', rotulo: 'Carteira do board' },
  { tipo: 'pessoas', rotulo: 'Pessoas na Hotmart' },
  { tipo: 'conciliacao', rotulo: 'Conciliação Hotmart × banco' },
  { tipo: 'identidade', rotulo: 'Mesma pessoa?' },
  { tipo: 'acelera', rotulo: 'Acelera → HM' },
  // Saiu do menu lateral na limpeza de 28/09; por pessoa continua na ficha do aluno.
  { tipo: 'prorata', rotulo: 'Pro rata (todos)' },
];

/** Botão do seletor de família — mesmo padrão visual usado em FaturamentoDiario.tsx. */
function BotaoFamilia({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
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
      {FAMILIAS_EM_ORDEM.map((f) => (
        <BotaoFamilia key={f} ativo={familia === f} onClick={() => onChange(f)}>
          {ROTULO_FAMILIA[f]}
        </BotaoFamilia>
      ))}
    </div>
  );
}

const ROTULO_SITUACAO_PROTOCOLO: Record<RelatorioVerificado['situacao'], { texto: string; tone: 'success' | 'warning' | 'danger' }> = {
  selado: { texto: 'Selado', tone: 'success' },
  aguardando_selo: { texto: 'Aguardando selo (dentro da janela)', tone: 'warning' },
  nao_concluido: { texto: 'Não concluído (janela de 15 min expirou sem selar)', tone: 'danger' },
};

/**
 * Conferência interna de um protocolo já emitido (fn_fin_relatorio_verificar).
 * Não é um 7º tipo de relatório: campo à parte, dentro da aba. A RPC já exige
 * usuário logado com gp_pode_ver_financeiro() — a UI só chama, não reinventa guarda.
 */
function ConferirProtocolo({ repo }: { repo: FinanceiroRepository }) {
  const [valor, setValor] = useState('');
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [resultado, setResultado] = useState<RelatorioVerificado | null>(null);

  const conferir = async () => {
    const protocolo = valor.trim();
    if (!protocolo) return;
    setCarregando(true);
    setErro(null);
    setResultado(null);
    try {
      const r = await repo.verificarRelatorio(protocolo);
      if (!r) setErro('Nenhum relatório emitido com esse protocolo.');
      else setResultado(r);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível conferir o protocolo.');
    } finally {
      setCarregando(false);
    }
  };

  return (
    <SectionCard title="Conferir protocolo" subtitle="Confere um relatório em PDF já emitido (protocolo GP-REL-AAAA-NNNNNN).">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          value={valor}
          onChange={(e) => setValor(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') conferir(); }}
          placeholder="GP-REL-2026-000041"
          className="max-w-xs"
        />
        <Button variant="ghost" size="sm" onClick={conferir} disabled={carregando || !valor.trim()}>
          {carregando ? 'Conferindo…' : 'Conferir'}
        </Button>
      </div>

      {erro && <p className="mt-3 text-xs text-[var(--red)]">{erro}</p>}

      {resultado && (
        <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs sm:grid-cols-3">
          <div><dt className="text-[var(--fg-3)]">Situação</dt><dd><Badge tone={ROTULO_SITUACAO_PROTOCOLO[resultado.situacao].tone}>{ROTULO_SITUACAO_PROTOCOLO[resultado.situacao].texto}</Badge></dd></div>
          <div><dt className="text-[var(--fg-3)]">Tipo</dt><dd className="text-[var(--fg)]">{resultado.tipo}</dd></div>
          <div><dt className="text-[var(--fg-3)]">Nível</dt><dd className="text-[var(--fg)]">{resultado.nivel}</dd></div>
          <div><dt className="text-[var(--fg-3)]">Emitido por</dt><dd className="text-[var(--fg)]">{resultado.gerado_por_nome}</dd></div>
          <div><dt className="text-[var(--fg-3)]">Emitido em</dt><dd className="text-[var(--fg)]">{new Date(resultado.emitido_em).toLocaleString('pt-BR')}</dd></div>
          <div><dt className="text-[var(--fg-3)]">Linhas</dt><dd className="text-[var(--fg)]">{resultado.linhas.toLocaleString('pt-BR')}</dd></div>
          {resultado.selado_em && (
            <div><dt className="text-[var(--fg-3)]">Selado em</dt><dd className="text-[var(--fg)]">{new Date(resultado.selado_em).toLocaleString('pt-BR')}</dd></div>
          )}
          {resultado.paginas != null && (
            <div><dt className="text-[var(--fg-3)]">Páginas</dt><dd className="text-[var(--fg)]">{resultado.paginas}</dd></div>
          )}
          {resultado.sha256 && (
            <div className="col-span-2 sm:col-span-3"><dt className="text-[var(--fg-3)]">SHA-256</dt><dd className="text-[var(--fg)] break-all font-mono">{resultado.sha256}</dd></div>
          )}
        </dl>
      )}
    </SectionCard>
  );
}

export function Relatorios({
  contas, turma, canVerDoc, repo, hotmartPorCard, tipoInicial,
}: {
  tipoInicial?: TipoRelatorio;
  contas: ContaReceber[];
  turma: string | null;
  canVerDoc: boolean;
  repo: FinanceiroRepository;
  hotmartPorCard: Map<string, BoardHotmart> | null;
}) {
  const [tipo, setTipo] = useState<TipoRelatorio>(tipoInicial ?? 'board');
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');

  return (
    <div className="space-y-4">
      <div className="gp-print-hide">
        <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value as TipoRelatorio)}>
          {RELATORIOS.map((r) => (
            <option key={r.tipo} value={r.tipo}>{r.rotulo}</option>
          ))}
        </FilterSelect>
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

      {tipo === 'prorata' && <ProrataHM repo={repo} />}

      <ConferirProtocolo repo={repo} />
    </div>
  );
}
