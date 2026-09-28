'use client';

// Faturamento · Caixa Hotmart (F6): quanto já caiu, quanto está retido, quanto custou antecipar.
// Pergunta que responde (catálogo, seção B): "Quanto já caiu, quanto está retido, quanto custou antecipar?"
//
// Dado: 2 RPCs (fn_fin_caixa_hotmart + _totais) por período, via o cache que o FinanceiroClient guarda — voltar a um
// período já visto não consulta. Período inválido (datas, invertido, > 400 dias) nem chega a consultar.
import { useEffect, useState } from 'react';
import { DataTable, EmptyState, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { CacheCaixaHotmart, CaixaHotmartCarregado } from '../../application/carregar-caixa-hotmart';
import {
  chaveCaixa, INICIO_ANTECIPACAO, JANELA_MAX_DIAS_CAIXA, pegaAntesDaAntecipacao, periodoPadraoCaixa, semAntecipacao,
  somarDias, validarPeriodoCaixa, type LinhaCaixaHotmart,
} from '../../domain/caixa-hotmart';
import { avisoSemAntecipacao, CAIXA_HOTMART as T } from './textos';

/** Preset ativo: 'marco' = desde o início da antecipação; número = últimos N dias; null = datas digitadas. */
export type PresetCaixa = 'marco' | 30 | 365 | null;
export interface PeriodoCaixa { de: string; ate: string; preset: PresetCaixa }

export function periodoInicialCaixa(hojeISO: string): PeriodoCaixa {
  return { ...periodoPadraoCaixa(hojeISO), preset: 'marco' };
}

export function CaixaHotmart({ cache, periodo, onPeriodo, hojeISO }: {
  cache: CacheCaixaHotmart;
  periodo: PeriodoCaixa;
  onPeriodo: (p: PeriodoCaixa) => void;
  hojeISO: string;
}) {
  const { de, ate } = periodo;
  const validacao = validarPeriodoCaixa(de, ate);
  const chave = chaveCaixa(de, ate);
  const [res, setRes] = useState<{ chave: string; dados: CaixaHotmartCarregado | null; erro: string | null } | null>(null);
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
  const marco = fmtData(INICIO_ANTECIPACAO);
  const presets: { p: Exclude<PresetCaixa, null>; rotulo: string; de: string }[] = [
    { p: 'marco', rotulo: T.desdeAntecipacao(marco), de: periodoPadraoCaixa(hojeISO).de },
    { p: 30, rotulo: T.dias30, de: somarDias(hojeISO, -29) },
    { p: 365, rotulo: T.meses12, de: somarDias(hojeISO, -364) },
  ];
  const msgValidacao = validacao.ok ? null
    : validacao.motivo === 'datas' ? T.erroDatas
    : validacao.motivo === 'invertido' ? T.erroInvertido
    : T.erroJanela(JANELA_MAX_DIAS_CAIXA);

  return (
    <div className="space-y-3">
      <p className="text-xs text-[var(--fg-3)]">{T.escopo}</p>
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

      {validacao.ok && pegaAntesDaAntecipacao(de) && (
        <p role="note" className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-xs text-[var(--fg-2)]">
          {avisoSemAntecipacao(marco)}
        </p>
      )}

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
        <CaixaConteudo dados={dados} />
      )}
    </div>
  );
}

/** Totais numa faixa só + tabela por dia. Exportado para o teste de render (HTML estático, sem efeito). */
export function CaixaConteudo({ dados }: { dados: CaixaHotmartCarregado }) {
  const { totais: t, derivado: d, linhas } = dados;
  const itens: { rotulo: string; valor: number; nota: string }[] = [
    { rotulo: T.liquido, valor: t.liquido, nota: T.vendas(t.nVendas) },
    { rotulo: T.jaCaiuD2, valor: d.jaCaiuD2, nota: d.aCairD2 > 0 ? T.aCair(fmtBRL(d.aCairD2)) : '' },
    { rotulo: T.custoAntecipacao, valor: t.custoAntecipacao, nota: '' },
    { rotulo: T.retidoALiberar, valor: t.retidoALiberar, nota: t.retido > 0 ? T.jaLiberado(fmtBRL(d.jaLiberado)) : T.semRetidoAberto },
    { rotulo: T.liquidoTotal, valor: t.liquidoTotal, nota: T.somaDasPartes },
  ];
  return (
    <>
      <section aria-label={T.totaisRotulo}>
        <dl className="grid grid-cols-2 overflow-hidden rounded-[var(--r-md)] border border-[var(--border)] sm:grid-cols-5">
          {itens.map((i, k) => (
            <div key={i.rotulo} className={`px-3 py-2 ${k ? 'border-l border-[var(--border)]' : ''}`}>
              <dt className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{i.rotulo}</dt>
              <dd className="tabular text-sm font-semibold text-[var(--fg)]">{fmtBRL(i.valor)}</dd>
              {i.nota && <dd className="text-[11px] text-[var(--fg-3)]">{i.nota}</dd>}
            </div>
          ))}
        </dl>
      </section>

      {!linhas.length ? <EmptyState title={T.vazio} icon="trending-up" /> : (
        <DataTable minWidth={1100}>
          <caption className="sr-only">{T.tabelaRotulo}</caption>
          <Thead>
            <Th>{T.dia}</Th><Th>{T.nVendas}</Th><Th>{T.liquido}</Th><Th>{T.custoAntecipacao}</Th>
            <Th>{T.entraD2}</Th><Th>{T.dataD2}</Th><Th>{T.situacaoD2}</Th>
            <Th>{T.retido}</Th><Th>{T.liberaEm}</Th><Th>{T.situacaoRetido}</Th>
          </Thead>
          <tbody>
            {[...linhas].reverse().map((l) => <LinhaDia key={l.dia} l={l} />)}
          </tbody>
        </DataTable>
      )}
    </>
  );
}

function Situacao({ s }: { s: keyof typeof T.situacao | null }) {
  if (!s) return <span className="text-[var(--fg-4)]">—</span>;
  const concluido = s === 'recebido' || s === 'liberado';
  return <span className={concluido ? 'text-[var(--fg-3)]' : 'font-semibold text-[var(--fg)]'}>{T.situacao[s]}</span>;
}

function LinhaDia({ l }: { l: LinhaCaixaHotmart }) {
  const semAnt = semAntecipacao(l);
  const semRegra = l.entraEm == null && l.liberaEm == null;
  return (
    <Tr>
      <Td className="whitespace-nowrap tabular">{fmtData(l.dia)}</Td>
      <Td className="tabular">{l.nVendas}</Td>
      <Td className="tabular font-semibold">{fmtBRL(l.liquido)}</Td>
      <Td className="tabular text-[var(--fg-2)]">{semAnt ? '—' : fmtBRL(l.custoAntecipacao)}</Td>
      {semRegra ? (
        <Td className="text-xs text-[var(--fg-3)]">{T.semPremissa}</Td>
      ) : semAnt ? (
        <Td className="text-xs text-[var(--fg-3)]">{T.semAntecipacao}</Td>
      ) : (
        <Td className="tabular">{fmtBRL(l.entraRapido)}</Td>
      )}
      <Td className="whitespace-nowrap tabular text-[var(--fg-2)]">{semAnt || semRegra ? '—' : fmtData(l.entraEm)}</Td>
      <Td>{semAnt ? <span className="text-[var(--fg-4)]">—</span> : <Situacao s={l.situacaoD2} />}</Td>
      <Td className="tabular">{semRegra ? '—' : fmtBRL(l.retido)}</Td>
      <Td className="whitespace-nowrap tabular text-[var(--fg-2)]">{fmtData(l.liberaEm)}</Td>
      <Td><Situacao s={l.situacaoRetido} /></Td>
    </Tr>
  );
}
