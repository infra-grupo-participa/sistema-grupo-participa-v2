'use client';

// Sub-aba "Base auditável" (#receber?ver=base): a lista inteira do cenário ativo, linha a linha, com o porquê de cada
// tratamento; o resumo centro de custo × mês (ponte para o fluxo mensal/DRE do financeiro); e o CSV do filtrado em 2
// níveis de dado pessoal. Tudo sai de `dados.linhas` — a MESMA resposta da grade; nenhuma consulta nova.
// Paginada (200 por página): ~551 linhas hoje, ~900 com a projeção ligada. Sem virtualização e sem nada `absolute`.
import { useMemo, useState } from 'react';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { ContasReceberCarregado } from '../../application/carregar-contas-receber';
import { temPerda } from '../../domain/contas-receber';
import {
  csvBaseAuditavel, FILTRO_BASE_PADRAO, filtrarBase, NIVEIS_CSV_BASE, nomeArquivoCsvBase, opcoesBase, resumoCentroMes,
  rotuloSemanaDaLinha, SEM_VALOR, SITUACOES_BASE, somarBase, TODOS, type FiltroBase, type NivelCsvBase,
} from './base-auditavel';
import { rotuloBloco, rotuloCerteza, rotuloComponente, rotuloMes, rotuloSituacaoLinha } from './rotulos-receber';
import { BASE_AUDITAVEL as T, GRADE_RECEBER } from './textos';

export const LINHAS_POR_PAGINA = 200;

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 whitespace-nowrap';
const TD_NUM = 'px-2 py-1 text-right tabular whitespace-nowrap';
const CAMPO = 'rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-1)] px-1.5 py-0.5 text-xs text-[var(--fg)]';
const BOTAO = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';

const fmtFator = (f: number) => `× ${f.toLocaleString('pt-BR', { minimumFractionDigits: 4, maximumFractionDigits: 4 })}`;

function baixarCsv(conteudo: string, nome: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([conteudo], { type: 'text/csv;charset=utf-8' }));
  a.download = nome;
  a.click();
  URL.revokeObjectURL(a.href);
}

export function BaseAuditavel({ dados, rotuloCenario }: { dados: ContasReceberCarregado; rotuloCenario: string }) {
  const [filtro, setFiltroBruto] = useState<FiltroBase>(FILTRO_BASE_PADRAO);
  const [pagina, setPagina] = useState(1);
  const [nivel, setNivel] = useState<NivelCsvBase>('completo');
  const [aviso, setAviso] = useState<string | null>(null);
  const setFiltro = (p: Partial<FiltroBase>) => { setFiltroBruto((f) => ({ ...f, ...p })); setPagina(1); setAviso(null); };

  const opcoes = useMemo(() => opcoesBase(dados.linhas), [dados.linhas]);
  const filtradas = useMemo(() => filtrarBase(dados.linhas, filtro), [dados.linhas, filtro]);
  const soma = useMemo(() => somarBase(filtradas), [filtradas]);
  const resumo = useMemo(() => resumoCentroMes(filtradas), [filtradas]);
  const paginas = Math.max(1, Math.ceil(filtradas.length / LINHAS_POR_PAGINA));
  const pag = Math.min(pagina, paginas);
  const visiveis = filtradas.slice((pag - 1) * LINHAS_POR_PAGINA, pag * LINHAS_POR_PAGINA);
  const semanas = dados.grade.semanas;

  const exportar = () => {
    baixarCsv(csvBaseAuditavel(filtradas, semanas, nivel, rotuloCenario), nomeArquivoCsvBase(dados.hojeISO, dados.cenario, nivel));
    setAviso(T.exportou(filtradas.length));
  };

  return (
    <div className="space-y-3">
      <form role="search" aria-label={T.filtros} className="flex flex-wrap items-end gap-2 text-xs" onSubmit={(e) => e.preventDefault()}>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.situacao}
          <select className={CAMPO} value={filtro.situacao} onChange={(e) => setFiltro({ situacao: e.target.value as FiltroBase['situacao'] })}>
            {SITUACOES_BASE.map((s) => <option key={s} value={s}>{rotuloSituacaoLinha(s)}</option>)}
            <option value={TODOS}>{T.todas}</option>
          </select>
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.bloco}
          <select className={CAMPO} value={filtro.bloco} onChange={(e) => setFiltro({ bloco: e.target.value })}>
            <option value={TODOS}>{T.todos}</option>
            {opcoes.blocos.map((b) => <option key={b} value={String(b)}>{`${b}. ${rotuloBloco(b)}`}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.centroCusto}
          <select className={CAMPO} value={filtro.centro} onChange={(e) => setFiltro({ centro: e.target.value })}>
            <option value={TODOS}>{T.todos}</option>
            {opcoes.centros.map((x) => <option key={x} value={x}>{x}</option>)}
            {opcoes.temSemCentro && <option value={SEM_VALOR}>{T.semCentro}</option>}
          </select>
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.certeza}
          <select className={CAMPO} value={filtro.certeza} onChange={(e) => setFiltro({ certeza: e.target.value })}>
            <option value={TODOS}>{T.todas}</option>
            {opcoes.certezas.map((x) => <option key={x} value={x}>{rotuloCerteza(x)}</option>)}
            {opcoes.temSemCerteza && <option value={SEM_VALOR}>{T.semCerteza}</option>}
          </select>
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.busca}
          <input type="search" className={`${CAMPO} w-48`} value={filtro.busca} placeholder={T.buscaAjuda}
            onChange={(e) => setFiltro({ busca: e.target.value })} />
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.de}
          <input type="date" className={CAMPO} value={filtro.de} onChange={(e) => setFiltro({ de: e.target.value })} />
        </label>
        <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
          {T.ate}
          <input type="date" className={CAMPO} value={filtro.ate} onChange={(e) => setFiltro({ ate: e.target.value })} />
        </label>
        <button type="button" className={BOTAO} onClick={() => setFiltro(FILTRO_BASE_PADRAO)}>{T.limpar}</button>
        <span className="ml-auto flex items-end gap-2">
          <label className="flex flex-col gap-0.5 text-[var(--fg-3)]">
            {T.nivel}
            <select className={CAMPO} value={nivel} onChange={(e) => { setNivel(e.target.value as NivelCsvBase); setAviso(null); }}>
              {NIVEIS_CSV_BASE.map((n) => <option key={n} value={n}>{T.niveis[n]}</option>)}
            </select>
          </label>
          <button type="button" className={BOTAO} onClick={exportar} disabled={filtradas.length === 0}>
            {T.exportar} ({filtradas.length.toLocaleString('pt-BR')})
          </button>
        </span>
      </form>
      {aviso && <p role="status" className="text-xs text-[var(--fg-2)]">{aviso}</p>}

      <ResumoCentroMesTabela resumo={resumo} />

      <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
        <table className="w-max min-w-full border-collapse text-xs">
          <caption className="px-2 py-1.5 text-left text-xs text-[var(--fg-2)]">
            <span className="font-semibold text-[var(--fg)]">{T.caption(rotuloCenario)}</span> · {T.linhas(filtradas.length, dados.linhas.length)}
          </caption>
          <thead className="bg-[var(--surface-2)]">
            <tr>
              <th scope="col" className={TH}>{T.dataCaixa}</th>
              <th scope="col" className={TH}>{T.semana}</th>
              <th scope="col" className={TH}>{T.bloco}</th>
              <th scope="col" className={TH}>{T.grupo}</th>
              <th scope="col" className={TH}>{T.componente}</th>
              <th scope="col" className={TH}>{T.descricao}</th>
              <th scope="col" className={`${TH} text-right`}>{T.valorEsperado}</th>
              <th scope="col" className={`${TH} text-right`}>{T.valorBruto}</th>
              <th scope="col" className={`${TH} text-right`}>{T.fator}</th>
              <th scope="col" className={TH}>{T.centroCusto}</th>
              <th scope="col" className={TH}>{T.certeza}</th>
              <th scope="col" className={TH}>{T.situacao}</th>
              <th scope="col" className={TH}>{T.tratamento}</th>
            </tr>
          </thead>
          <tbody>
            {visiveis.length === 0 ? (
              <tr><td colSpan={13} className="px-2 py-2 text-[var(--fg-3)]">{T.vazio}</td></tr>
            ) : visiveis.map((l, i) => {
              const semBase = l.situacao === 'sem_base';
              const somaNaLinha = l.situacao === 'a_receber';
              const desc = [l.rotulo, l.produto].filter(Boolean).join(' · ');
              return (
                <tr key={i} className={`border-t border-[var(--border-faint)] ${somaNaLinha ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>
                  <td className={`${TD} tabular`}>{fmtData(l.data_caixa)}</td>
                  <td className={`${TD} tabular`}>{rotuloSemanaDaLinha(semanas, l.data_caixa) || '—'}</td>
                  <td className={TD}>{`${l.bloco}. ${rotuloBloco(l.bloco)}`}</td>
                  <td className={TD}>{l.grupo}</td>
                  <td className={TD}>{rotuloComponente(l.componente)}</td>
                  <td className="px-2 py-1">{desc || '—'}</td>
                  <td className={TD_NUM}>{semBase ? T.semBaseValor : fmtBRLc(l.valor)}</td>
                  <td className={TD_NUM}>{semBase ? '—' : fmtBRLc(l.valor_bruto)}</td>
                  <td className={TD_NUM}>{temPerda(l) ? fmtFator(l.fator) : '—'}</td>
                  <td className={TD}>{l.centro_custo ?? '—'}</td>
                  <td className={TD}>{rotuloCerteza(l.certeza)}</td>
                  <td className={TD}>{rotuloSituacaoLinha(l.situacao)}</td>
                  <td className="min-w-[16rem] px-2 py-1">{l.tratamento ?? '—'}</td>
                </tr>
              );
            })}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-[var(--border)] font-semibold text-[var(--fg)]">
              <th scope="row" colSpan={6} className="px-2 py-1 text-left">
                {soma.aReceber.linhas > 0 ? T.somaAReceber(soma.aReceber.linhas) : T.semAReceber}
              </th>
              <td className={TD_NUM}>{soma.aReceber.linhas > 0 ? fmtBRLc(soma.aReceber.valor) : '—'}</td>
              <td className={TD_NUM}>{soma.aReceber.linhas > 0 ? fmtBRLc(soma.aReceber.bruto) : '—'}</td>
              <td colSpan={5} />
            </tr>
            {soma.foraDaSoma.length > 0 && (
              <tr className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
                <td colSpan={13} className="px-2 py-1">
                  {T.foraDaSoma}{' '}
                  {soma.foraDaSoma.map((x) => `${rotuloSituacaoLinha(x.situacao)} ${x.linhas.toLocaleString('pt-BR')}`).join(' · ')}
                </td>
              </tr>
            )}
          </tfoot>
        </table>
      </div>

      {paginas > 1 && (
        <nav aria-label={T.paginacao} className="flex items-center gap-2 text-xs text-[var(--fg-2)]">
          <button type="button" className={BOTAO} disabled={pag <= 1} onClick={() => setPagina(pag - 1)}>{T.anterior}</button>
          <span aria-live="polite">{T.pagina(pag, paginas)}</span>
          <button type="button" className={BOTAO} disabled={pag >= paginas} onClick={() => setPagina(pag + 1)}>{T.proxima}</button>
        </nav>
      )}
    </div>
  );
}

function ResumoCentroMesTabela({ resumo }: { resumo: ReturnType<typeof resumoCentroMes> }) {
  const num = (v: number) => (Math.round(v * 100) === 0 ? <span className="text-[var(--fg-4)]">–</span> : fmtBRLc(v));
  return (
    <div className="space-y-1">
      <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
        <table className="w-max min-w-full border-collapse text-xs">
          <caption className="px-2 py-1.5 text-left text-xs text-[var(--fg-2)]">
            <span className="font-semibold text-[var(--fg)]">{T.resumoTitulo}</span> · {T.resumoCaption}
          </caption>
          {resumo.meses.length === 0 ? (
            <tbody><tr><td className="px-2 py-2 text-[var(--fg-3)]">{T.resumoVazio}</td></tr></tbody>
          ) : (
            <>
              <thead className="bg-[var(--surface-2)]">
                <tr>
                  <th scope="col" className={TH}>{T.centroCusto}</th>
                  {resumo.meses.map((m) => <th key={m} scope="col" className={`${TH} text-right`}>{rotuloMes(m)}</th>)}
                  <th scope="col" className={`${TH} border-l border-[var(--border)] text-right`}>{GRADE_RECEBER.total}</th>
                </tr>
              </thead>
              <tbody>
                {resumo.linhas.map((l) => (
                  <tr key={l.centro ?? SEM_VALOR} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
                    <th scope="row" className="px-2 py-1 text-left font-normal whitespace-nowrap">{l.centro ?? T.semCentro}</th>
                    {l.porMes.map((v, i) => <td key={i} className={TD_NUM}>{num(v)}</td>)}
                    <td className={`${TD_NUM} border-l border-[var(--border)]`}>{num(l.total)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--border)] font-semibold text-[var(--fg)]">
                  <th scope="row" className="px-2 py-1 text-left">{T.resumoTotal}</th>
                  {resumo.totalPorMes.map((v, i) => <td key={i} className={TD_NUM}>{num(v)}</td>)}
                  <td className={`${TD_NUM} border-l border-[var(--border)]`}>{num(resumo.total)}</td>
                </tr>
              </tfoot>
            </>
          )}
        </table>
      </div>
      {resumo.semData.linhas > 0 && (
        <p className="text-xs text-[var(--fg-3)]">{T.resumoSemData(resumo.semData.linhas, fmtBRLc(resumo.semData.valor))}</p>
      )}
    </div>
  );
}
