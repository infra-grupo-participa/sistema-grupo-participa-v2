'use client';

// Faturamento · Taxa Hotmart (F7, z70). Pergunta que responde (catálogo, seção B):
// "A Hotmart está cobrando o que combinou?"
//
// Dado: fn_fin_taxa_auditoria por período e, só se houver divergente, fn_fin_taxa_divergencias — via o cache que o
// FinanceiroClient guarda (voltar a um período já visto não consulta). Período inválido nem chega a consultar.
// Hierarquia por posição: resumo numa frase → tabela por produto → parcelado (informativo) → lista das divergentes.
import { useEffect, useState } from 'react';
import { DataTable, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtBRLc, fmtData } from '@/shared/ui/format';
import type { CacheTaxaHotmart, TaxaHotmartCarregada } from '../../application/carregar-taxa-hotmart';
import { validarPeriodoCaixa } from '../../domain/caixa-hotmart';
import {
  chaveTaxa, csvDivergencias, JANELA_MAX_DIAS_TAXA, periodo12MesesTaxa, periodoPadraoTaxa,
  type DivergenciaTaxa, type TaxaParcela, type TaxaProduto,
} from '../../domain/taxa-hotmart';
import { TAXA_HOTMART as T } from './textos';

/** Preset ativo: 'ano' = ano corrente (padrão); 365 = últimos 12 meses; null = datas digitadas. */
export type PresetTaxa = 'ano' | 365 | null;
export interface PeriodoTaxa { de: string; ate: string; preset: PresetTaxa }

export function periodoInicialTaxa(hojeISO: string): PeriodoTaxa {
  return { ...periodoPadraoTaxa(hojeISO), preset: 'ano' };
}

const pct = (v: number | null, casas = 2) =>
  v == null ? '—' : `${v.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

export function TaxaHotmart({ cache, periodo, onPeriodo, hojeISO }: {
  cache: CacheTaxaHotmart;
  periodo: PeriodoTaxa;
  onPeriodo: (p: PeriodoTaxa) => void;
  hojeISO: string;
}) {
  const { de, ate } = periodo;
  const validacao = validarPeriodoCaixa(de, ate);
  const chave = chaveTaxa(de, ate);
  const [res, setRes] = useState<{ chave: string; dados: TaxaHotmartCarregada | null; erro: string | null } | null>(null);
  const [tentativa, setTentativa] = useState(0);

  useEffect(() => {
    if (!validacao.ok || cache.lido(de, ate)) return;
    let vivo = true;
    cache.obter(de, ate).then(
      (d) => { if (vivo) setRes({ chave, dados: d, erro: null }); },
      (e: Error) => { if (vivo) setRes({ chave, dados: null, erro: e.message }); },
    );
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave, validacao.ok, tentativa]);

  const atual = res && res.chave === chave ? res : null;
  const dados = cache.lido(de, ate) ?? atual?.dados ?? null;
  const erro = dados ? null : atual?.erro ?? null;
  const presets: { p: Exclude<PresetTaxa, null>; rotulo: string; de: string }[] = [
    { p: 'ano', rotulo: T.anoCorrente(hojeISO.slice(0, 4)), de: periodoPadraoTaxa(hojeISO).de },
    { p: 365, rotulo: T.meses12, de: periodo12MesesTaxa(hojeISO).de },
  ];
  const msgValidacao = validacao.ok ? null
    : validacao.motivo === 'datas' ? T.erroDatas
    : validacao.motivo === 'invertido' ? T.erroInvertido
    : T.erroJanela(JANELA_MAX_DIAS_TAXA);

  return (
    <div className="space-y-3">
      <p className="text-xs text-[var(--fg-3)]"><span className="font-semibold text-[var(--fg-2)]">{T.pergunta}</span> {T.escopo}</p>
      <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label={T.periodo}>
        {presets.map((x) => (
          <button key={String(x.p)} type="button" aria-pressed={periodo.preset === x.p}
            onClick={() => onPeriodo({ de: x.de, ate: hojeISO, preset: x.p })}
            className={`rounded-[var(--r-sm)] border px-2.5 py-1 text-xs ${periodo.preset === x.p ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}>
            {x.rotulo}
          </button>
        ))}
        <span className="ml-2 text-xs text-[var(--fg-3)]">{T.ou}</span>
        <input type="date" aria-label={T.de} value={de} max={ate}
          onChange={(e) => onPeriodo({ ...periodo, de: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
        <span className="text-xs text-[var(--fg-3)]">{T.ateCurto}</span>
        <input type="date" aria-label={T.ate} value={ate} min={de}
          onChange={(e) => onPeriodo({ ...periodo, ate: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
      </div>

      {msgValidacao ? (
        <p role="alert" className="text-xs font-semibold text-[var(--red)]">{msgValidacao}</p>
      ) : erro ? (
        <div role="alert" className="rounded-[var(--r-sm)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-3 py-2 text-sm text-[var(--fg)]">
          {erro}{' '}
          <button type="button" onClick={() => { setRes(null); setTentativa((t) => t + 1); }}
            className="ml-2 rounded-[var(--r-sm)] border border-[var(--red-border)] px-2 py-0.5 text-xs font-semibold text-[var(--red)]">
            {T.tentarDeNovo}
          </button>
        </div>
      ) : !dados ? (
        <Loading label={T.carregando} minHeight={160} />
      ) : (
        <TaxaConteudo dados={dados} />
      )}
    </div>
  );
}

/** Resumo + por produto + parcelado + divergentes. Exportado para o teste de render (HTML estático, sem efeito). */
export function TaxaConteudo({ dados }: { dados: TaxaHotmartCarregada }) {
  const { auditoria: { produtos, parcelas, resumo: r }, divergencias } = dados;
  return (
    <>
      <section aria-label={T.resumoRotulo} className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm text-[var(--fg)]">
        {r.nVendas === 0 ? <p>{T.semVendas}</p> : (
          <p>
            <span className="font-semibold">{T.vendasAVista(r.nVendas)}</span>
            {r.nDivergentes === 0 ? <>. {T.tudoCerto}</>
              : <>, <span className="font-semibold text-[var(--red)]">{T.divergentes(r.nDivergentes, fmtBRLc(Math.abs(r.impactoDivergentes)), r.impactoDivergentes >= 0)}</span></>}
          </p>
        )}
        {(r.nSemTaxa > 0 || r.nSemAcordoEspecifico > 0) && (
          <p className="mt-0.5 text-xs text-[var(--fg-3)]">
            {[r.nSemTaxa > 0 ? T.semTaxa(r.nSemTaxa) : null, r.nSemAcordoEspecifico > 0 ? T.semAcordo(r.nSemAcordoEspecifico) : null]
              .filter(Boolean).join(' ')}
          </p>
        )}
      </section>

      {produtos.length > 0 && (
        <section aria-labelledby="taxa-produtos-titulo" className="space-y-1.5">
          <h3 id="taxa-produtos-titulo" className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{T.produtosTitulo}</h3>
          <DataTable minWidth={960}>
            <caption className="sr-only">{T.produtosRotulo}</caption>
            <Thead>
              <Th>{T.produto}</Th><Th>{T.acordo}</Th><Th>{T.nVendas}</Th><Th>{T.oferta}</Th>
              <Th>{T.taxaReal}</Th><Th>{T.taxaEsperada}</Th><Th>{T.nDivergentes}</Th>
              <Th><abbr title={T.ajudaImpacto} className="no-underline">{T.impacto}</abbr></Th>
            </Thead>
            <tbody>{produtos.map((p) => <LinhaProduto key={p.produtoId} p={p} />)}</tbody>
          </DataTable>
        </section>
      )}

      <section aria-labelledby="taxa-parcelado-titulo" className="space-y-1.5">
        <h3 id="taxa-parcelado-titulo" className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{T.parceladoTitulo}</h3>
        <p className="text-xs text-[var(--fg-3)]">{T.parceladoExplica}</p>
        <TabelaParcelado parcelas={parcelas} />
      </section>

      {divergencias.length > 0 && (
        <section aria-labelledby="taxa-divergencias-titulo" className="space-y-1.5">
          <div className="flex flex-wrap items-center gap-2">
            <h3 id="taxa-divergencias-titulo" className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{T.divergenciasTitulo}</h3>
            <button type="button" onClick={() => baixarCsv(divergencias, dados.de, dados.ate)} title={T.exportarAjuda}
              className="rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)]">
              {T.exportar}
            </button>
            {r.nDivergentes > divergencias.length && (
              <span className="text-xs text-[var(--fg-3)]">{T.limite(divergencias.length, r.nDivergentes)}</span>
            )}
          </div>
          <DataTable minWidth={820}>
            <caption className="sr-only">{T.divergenciasRotulo}</caption>
            <Thead>
              <Th>{T.transacao}</Th><Th>{T.dia}</Th><Th>{T.produto}</Th><Th>{T.oferta}</Th>
              <Th>{T.taxaReal}</Th><Th>{T.taxaEsperada}</Th><Th>{T.diferenca}</Th>
            </Thead>
            <tbody>{divergencias.map((d) => <LinhaDivergencia key={d.transacao} d={d} />)}</tbody>
          </DataTable>
        </section>
      )}
    </>
  );
}

function LinhaProduto({ p }: { p: TaxaProduto }) {
  return (
    <Tr>
      <Td className="font-semibold">{p.produtoNome}</Td>
      <Td className="whitespace-nowrap">
        {p.grupoAcordo}
        {p.semAcordoEspecifico && <span className="ml-1.5 text-xs font-semibold text-[var(--fg-2)]">· {T.semAcordoEspecifico}</span>}
      </Td>
      <Td className="tabular">
        {p.nVendas.toLocaleString('pt-BR')}
        {p.nSemTaxa > 0 && <span className="ml-1 text-xs text-[var(--fg-3)]">{T.semTaxaNota(p.nSemTaxa)}</span>}
      </Td>
      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(p.valorOferta)}</Td>
      <Td className="tabular">{pct(p.taxaRealPct)} <span className="text-xs text-[var(--fg-3)]">{fmtBRLc(p.taxaRealRs)}</span></Td>
      <Td className="tabular">{pct(p.taxaEsperadaPct)} <span className="text-xs text-[var(--fg-3)]">{fmtBRLc(p.taxaEsperadaRs)}</span></Td>
      <Td className={`tabular ${p.nDivergentes ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>{p.nDivergentes}</Td>
      <Td className={`tabular ${p.nDivergentes ? 'font-semibold' : 'text-[var(--fg-3)]'}`}>{p.nDivergentes ? fmtBRLc(p.impactoDivergentesRs) : '—'}</Td>
    </Tr>
  );
}

function TabelaParcelado({ parcelas }: { parcelas: TaxaParcela[] }) {
  const base = parcelas.find((x) => x.parcelas === 1)?.taxaClientePct ?? null;
  return (
    <DataTable minWidth={560}>
      <caption className="sr-only">{T.parceladoRotulo}</caption>
      <Thead>
        <Th>{T.parcelas}</Th><Th>{T.nVendas}</Th><Th>{T.oferta}</Th><Th>{T.clientePaga}</Th><Th>{T.aMaisQue1x}</Th>
      </Thead>
      <tbody>
        {parcelas.map((x) => {
          const dif = x.parcelas > 1 && x.taxaClientePct != null && base != null ? x.taxaClientePct - base : null;
          return (
            <Tr key={x.parcelas}>
              <Td className="whitespace-nowrap tabular">{T.parcela(x.parcelas)}</Td>
              <Td className="tabular">{x.nVendas.toLocaleString('pt-BR')}</Td>
              <Td className="tabular text-[var(--fg-2)]">{x.nVendas ? fmtBRL(x.valorOferta) : '—'}</Td>
              <Td className="tabular">{pct(x.taxaClientePct, 1)}</Td>
              <Td className="tabular text-[var(--fg-2)]">
                {dif == null ? '—' : T.pontos(dif.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 }))}
              </Td>
            </Tr>
          );
        })}
      </tbody>
    </DataTable>
  );
}

function LinhaDivergencia({ d }: { d: DivergenciaTaxa }) {
  return (
    <Tr>
      <Td className="whitespace-nowrap font-mono text-xs">{d.transacao}</Td>
      <Td className="whitespace-nowrap tabular">{fmtData(d.dia)}</Td>
      <Td>{d.produtoNome}</Td>
      <Td className="tabular text-[var(--fg-2)]">{fmtBRLc(d.valorOferta)}</Td>
      <Td className="tabular">{fmtBRLc(d.taxaReal)}</Td>
      <Td className="tabular">{fmtBRLc(d.taxaEsperada)}</Td>
      <Td className="tabular font-semibold">{d.diferenca > 0 ? '+' : ''}{fmtBRLc(d.diferenca)}</Td>
    </Tr>
  );
}

function baixarCsv(linhas: DivergenciaTaxa[], de: string, ate: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csvDivergencias(linhas)], { type: 'text/csv;charset=utf-8' }));
  a.download = `taxa-hotmart-divergencias-${de}-a-${ate}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}
