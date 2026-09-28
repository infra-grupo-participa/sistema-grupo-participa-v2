'use client';

// Aba Relatórios: dropdown com os 6 tipos de relatório.
// "Carteira do board" (seleção de colunas + export XLSX/PDF) vive em ./CarteiraDoBoard.tsx.
// Os outros 5 são leitura do espelho da Hotmart (schema fin), já prontos em ui/hotmart/*.
import { useRef, useState } from 'react';
import { ROTULO_NIVEL, type NivelPii } from '@/shared/ui/pdf/modelo';
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
import {
  TEXTO_NAO_ENCONTRADO, hashDoArquivo, protocoloDoNomeArquivo, quandoEmitido, totaisParaTela, vereditoConferencia,
  type Veredito,
} from './pdf/conferir';

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

const COR_VEREDITO: Record<Veredito['tipo'], string> = {
  identico: 'border-[var(--green-border)] bg-[var(--green-subtle)] text-[var(--green)]',
  alterado: 'border-[var(--red-border)] bg-[var(--red-subtle)] text-[var(--red)]',
  nao_concluido: 'border-[var(--red-border)] bg-[var(--red-subtle)] text-[var(--red)]',
  aguardando_selo: 'border-[var(--yellow-border)] bg-[var(--yellow-subtle)] text-[var(--yellow)]',
  so_registro: 'border-[var(--border)] text-[var(--fg-2)]',
};

const rotuloTipo = (t: string) => RELATORIOS.find((r) => r.tipo === t)?.rotulo ?? t;
const rotuloNivel = (n: string) => ROTULO_NIVEL[n as NivelPii] ?? n;
const ehPdf = (f: File) => f.type === 'application/pdf' || /\.pdf$/i.test(f.name);

/**
 * Conferência de um PDF já emitido (fn_fin_relatorio_verificar). Não é um 7º tipo
 * de relatório: campo à parte, dentro da aba. A RPC já exige usuário logado com
 * gp_pode_ver_financeiro() — a UI só chama, não reinventa guarda.
 *
 * Compara o ARQUIVO (decisão do Marcio, pentest 28/09): o SHA-256 do PDF anexado é
 * calculado aqui no navegador com a mesma função que selou; o arquivo não sobe.
 * O veredito é derivado no render: trocar o arquivo recompara sem nova chamada.
 */
function ConferirProtocolo({ repo }: { repo: FinanceiroRepository }) {
  const [valor, setValor] = useState('');
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [resultado, setResultado] = useState<RelatorioVerificado | null>(null);
  const [arquivo, setArquivo] = useState<{ nome: string; sha256: string } | null>(null);
  const [calculando, setCalculando] = useState(false);
  const [arrastando, setArrastando] = useState(false);
  const inputArquivo = useRef<HTMLInputElement>(null);
  // Dois arquivos em sequência rápida: só o hash do último vale.
  const ultimoArquivo = useRef(0);

  const receberArquivo = async (f: File | undefined) => {
    if (!f) return;
    if (!ehPdf(f)) {
      setErro('Anexe o arquivo PDF do relatório.');
      return;
    }
    const vez = ++ultimoArquivo.current;
    setErro(null);
    setCalculando(true);
    setArquivo(null);
    const sugerido = protocoloDoNomeArquivo(f.name);
    if (sugerido && !valor.trim()) setValor(sugerido);
    try {
      const sha256 = await hashDoArquivo(f);
      if (vez === ultimoArquivo.current) setArquivo({ nome: f.name, sha256 });
    } catch {
      if (vez === ultimoArquivo.current) setErro('Não foi possível ler o arquivo.');
    } finally {
      if (vez === ultimoArquivo.current) setCalculando(false);
    }
  };

  const tirarArquivo = () => {
    ultimoArquivo.current++;
    setArquivo(null);
    setCalculando(false);
    if (inputArquivo.current) inputArquivo.current.value = '';
  };

  const conferir = async () => {
    const protocolo = valor.trim().toUpperCase();
    if (!protocolo || calculando) return;
    setCarregando(true);
    setErro(null);
    setResultado(null);
    try {
      const r = await repo.verificarRelatorio(protocolo);
      if (!r) setErro(TEXTO_NAO_ENCONTRADO);
      else setResultado(r);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível conferir o protocolo.');
    } finally {
      setCarregando(false);
    }
  };

  const veredito = resultado ? vereditoConferencia(resultado, arquivo?.sha256 ?? null) : null;
  const totais = resultado ? totaisParaTela(resultado.totais) : [];

  return (
    <SectionCard title="Conferir protocolo" subtitle="Digite o protocolo (GP-REL-AAAA-NNNNNN) e anexe o PDF recebido: o sistema diz se o arquivo é o mesmo que foi emitido.">
      <div
        className={`flex flex-wrap items-center gap-2 rounded-[var(--r-md)] border border-dashed p-2 ${arrastando ? 'border-[var(--accent)]' : 'border-[var(--border)]'}`}
        onDragOver={(e) => { e.preventDefault(); setArrastando(true); }}
        onDragLeave={() => setArrastando(false)}
        onDrop={(e) => { e.preventDefault(); setArrastando(false); receberArquivo(e.dataTransfer.files?.[0]); }}
      >
        <Input
          value={valor}
          onChange={(e) => setValor(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') conferir(); }}
          placeholder="GP-REL-2026-000041"
          aria-label="Protocolo"
          className="max-w-xs"
        />
        <input
          ref={inputArquivo}
          type="file"
          accept="application/pdf"
          aria-label="PDF recebido"
          className="max-w-[16rem] text-xs text-[var(--fg-3)]"
          onChange={(e) => receberArquivo(e.target.files?.[0])}
        />
        <Button variant="ghost" size="sm" onClick={conferir} disabled={carregando || calculando || !valor.trim()}>
          {carregando ? 'Conferindo…' : calculando ? 'Lendo arquivo…' : 'Conferir'}
        </Button>
        <span className="text-xs text-[var(--fg-3)]">
          {arquivo ? <>Arquivo: {arquivo.nome} · <button type="button" className="underline" onClick={tirarArquivo}>tirar</button></> : 'ou arraste o PDF para cá'}
        </span>
      </div>

      {erro && <p className="mt-3 text-xs text-[var(--red)]">{erro}</p>}

      {resultado && veredito && (
        <div className="mt-3 space-y-3">
          <p role="status" className={`rounded-[var(--r-md)] border px-3 py-2 text-sm font-semibold ${COR_VEREDITO[veredito.tipo]}`}>
            {resultado.protocolo} · {veredito.texto}
          </p>

          <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs sm:grid-cols-4">
            <div><dt className="text-[var(--fg-3)]">Situação do protocolo</dt><dd><Badge tone={ROTULO_SITUACAO_PROTOCOLO[resultado.situacao].tone}>{ROTULO_SITUACAO_PROTOCOLO[resultado.situacao].texto}</Badge></dd></div>
            <div><dt className="text-[var(--fg-3)]">Relatório</dt><dd className="text-[var(--fg)]">{rotuloTipo(resultado.tipo)}</dd></div>
            <div><dt className="text-[var(--fg-3)]">Nível</dt><dd className="text-[var(--fg)]">{rotuloNivel(resultado.nivel)}</dd></div>
            <div><dt className="text-[var(--fg-3)]">Emitido por</dt><dd className="text-[var(--fg)]">{resultado.gerado_por_nome}</dd></div>
            <div><dt className="text-[var(--fg-3)]">Emitido em</dt><dd className="text-[var(--fg)]">{quandoEmitido(resultado.emitido_em)}</dd></div>
            {/* Emissões desde 28/09 gravam linhas_da_lista e `linhas` = linhas impressas (lista acima de 2.000 = só totais). */}
            {typeof resultado.recorte?.linhas_da_lista === 'number' ? (
              <>
                <div><dt className="text-[var(--fg-3)]">Linhas no PDF</dt><dd className="text-[var(--fg)]">{resultado.linhas.toLocaleString('pt-BR')}</dd></div>
                <div><dt className="text-[var(--fg-3)]">Linhas da lista</dt><dd className="text-[var(--fg)]">{resultado.recorte.linhas_da_lista.toLocaleString('pt-BR')}</dd></div>
              </>
            ) : (
              <div><dt className="text-[var(--fg-3)]">Linhas</dt><dd className="text-[var(--fg)]">{resultado.linhas.toLocaleString('pt-BR')}</dd></div>
            )}
            {resultado.selado_em && (
              <div><dt className="text-[var(--fg-3)]">Selado em</dt><dd className="text-[var(--fg)]">{quandoEmitido(resultado.selado_em)}</dd></div>
            )}
            {resultado.paginas != null && (
              <div><dt className="text-[var(--fg-3)]">Páginas</dt><dd className="text-[var(--fg)]">{resultado.paginas}</dd></div>
            )}
          </dl>

          {totais.length > 0 && (
            <div>
              <p className="mb-1 text-xs text-[var(--fg-3)]">Totais registrados na emissão — compare com os números do PDF:</p>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-4">
                {totais.map((t) => (
                  <div key={t.rotulo}><dt className="text-[var(--fg-3)]">{t.rotulo}</dt><dd className="tabular text-[var(--fg)]">{t.valor}</dd></div>
                ))}
              </dl>
            </div>
          )}

          <dl className="grid grid-cols-1 gap-y-1 text-xs">
            {resultado.sha256 && (
              <div><dt className="text-[var(--fg-3)]">SHA-256 selado</dt><dd className="break-all font-mono text-[var(--fg)]">{resultado.sha256}</dd></div>
            )}
            {arquivo && (
              <div><dt className="text-[var(--fg-3)]">SHA-256 do arquivo anexado</dt><dd className="break-all font-mono text-[var(--fg)]">{arquivo.sha256}</dd></div>
            )}
          </dl>
        </div>
      )}
    </SectionCard>
  );
}

export function Relatorios({
  contas, produtoLabel, acaoLabel, turma, canVerDoc, repo, hotmartPorCard, tipoInicial,
}: {
  tipoInicial?: TipoRelatorio;
  contas: ContaReceber[];
  /** Filtros que já encolheram `contas` no board — declarados no PDF da Carteira. */
  produtoLabel: string;
  acaoLabel: string | null;
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

      {tipo === 'board' && <CarteiraDoBoard contas={contas} produtoLabel={produtoLabel} acaoLabel={acaoLabel} turma={turma} canVerDoc={canVerDoc} hotmartPorCard={hotmartPorCard} />}

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
