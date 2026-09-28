'use client';

// Aba "Previsão de caixa" (#receber; fase 1 28/09/2026, F2 com cenários e perda, F3 com o estimado): grade semana (colunas)
// × bloco/grupo (linhas), com total por semana, por mês e acumulado. Substitui o "Fluxo Semanal" da planilha do financeiro.
// Seções, nesta ordem: CERTO (blocos 1, 2, 5) com subtotal; ESTIMADO (blocos 3, 4, 6; a reserva é negativa) com subtotal;
// total geral; e, abaixo dos totais, a faixa "Informativo — fora da soma" (bloco 8, acordos do board). Grupo estimado
// sem base aparece como "sem base medida", nunca como zero.
// Clicar num número abre, logo abaixo da grade e SEM consulta nova, quem compõe aquele valor — tudo sai da mesma
// resposta de fn_fin_receber_semanal (application/carregar-contas-receber.ts). A grade soma o ESPERADO (contrato v2);
// onde há perda (fator < 1) a célula mostra também o bruto, e a composição mostra bruto, fator, esperado e o porquê.
// O detalhe fica no fluxo da página (não é `absolute`): nada invisível entra na área rolável da grade.
import { useRef, useState, type ReactNode } from 'react';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import { hojeSaoPaulo, type ContasReceberCarregado } from '../../application/carregar-contas-receber';
import {
  BLOCO_INFORMATIVO, CENARIOS_RECEBER, composicaoDaCelula, GRUPO_BLOCO_1, GRUPO_BLOCO_6, secaoDoBloco, temPerda,
  type CenarioReceber, type GradeReceber, type LinhaGrade, type LinhaReceber, type PagamentoContrato, type Semana,
} from '../../domain/contas-receber';
import type { FeriadoBancario, SugestaoPremissa, VigenciaPremissa } from '../../domain/premissas-receber';
import type { EventoPlanejado } from '../../domain/eventos-planejados';
import type { Funil } from '../../domain/funis';
import { Recorrencias } from './Recorrencias';
import { Informados, type RepoInformados } from './Informados';
import { Premissas, type RepoPremissas } from './Premissas';
import { Eventos, type RepoEventos } from './Eventos';
import { BaseAuditavel } from './BaseAuditavel';
import { rotuloBloco, rotuloComponente, rotuloMes } from './rotulos-receber';
import {
  CENARIO_RECEBER, ESCOPO_RECEBER, ESTADOS_RECEBER, GRADE_RECEBER, ROTULOS_TOTAL, SECOES_RECEBER, SUBABAS_RECEBER,
} from './textos';
import type { SubAbaReceber } from './hash';

export type { SubAbaReceber } from './hash';
export { rotuloComponente } from './rotulos-receber';

const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const rotuloSemana = (s: Semana) => (s.inicio === s.fim ? ddmm(s.inicio) : `${s.inicio.slice(8, 10)}–${ddmm(s.fim)}`);

/** Nome do grupo que, sozinho no bloco, faz o bloco virar uma linha só (clicável). */
const grupoUnico = (b: number) => (b === 1 ? GRUPO_BLOCO_1 : b === 6 ? GRUPO_BLOCO_6 : rotuloBloco(b));

type Celula = { bloco: number; grupo: string; semana: number | null };

const TH = 'px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD_NUM = 'px-2 py-1 text-right tabular whitespace-nowrap';
const COL1 = 'sticky left-0 z-[1] bg-[var(--surface-1)] px-2 py-1 text-left whitespace-nowrap';

/** Célula da grade: o esperado; com perda (bruto ≠ esperado), o bruto logo abaixo, em texto (não só cor). */
function Numero({ v, bruto, onClick, ativo }: { v: number; bruto?: number; onClick?: () => void; ativo?: boolean }) {
  if (v === 0 && !bruto) return <span className="text-[var(--fg-4)]">–</span>;
  const comPerda = bruto != null && Math.round(bruto * 100) !== Math.round(v * 100);
  const linhaBruto = comPerda
    ? <span className="block text-[10px] font-normal text-[var(--fg-3)]">{GRADE_RECEBER.brutoCurto(fmtBRLc(bruto))}</span>
    : null;
  if (!onClick) return <>{fmtBRLc(v)}{linhaBruto}</>;
  return (
    <button type="button" onClick={onClick} aria-pressed={ativo}
      className={`tabular text-right hover:text-[var(--accent)] ${ativo ? 'font-semibold text-[var(--accent)]' : 'text-[var(--fg)]'}`}>
      <span className="underline decoration-dotted underline-offset-2">{fmtBRLc(v)}</span>
      {linhaBruto}
    </button>
  );
}

type BlocoGrade = GradeReceber['blocos'][number];

export function GradeContasReceber({ grade, selecionada, onSelecionar }: {
  grade: GradeReceber; selecionada: Celula | null; onSelecionar: (c: Celula) => void;
}) {
  const sems = grade.semanas;
  const nCols = sems.length + 1; // semanas + Total (a 1ª coluna fica de fora)
  const eAtiva = (bloco: number, grupo: string, semana: number | null) =>
    selecionada?.bloco === bloco && selecionada.grupo === grupo && selecionada.semana === semana;
  const linhasDoBloco = (b: number) => grade.linhas.filter((l) => l.bloco === b);
  const semBaseDoBloco = (b: number) => grade.semBase.filter((x) => x.bloco === b);
  const blocosDa = (secao: 'certo' | 'estimado') => {
    const nums = new Set<number>([
      ...grade.blocos.filter((b) => secaoDoBloco(b.bloco) === secao).map((b) => b.bloco),
      ...grade.semBase.filter((x) => secaoDoBloco(x.bloco) === secao).map((x) => x.bloco),
    ]);
    return [...nums].sort((a, b) => a - b);
  };
  const certo = blocosDa('certo');
  const estimado = blocosDa('estimado');
  const temEstimado = estimado.length > 0;

  /** Cabeçalho de seção: o rótulo na 1ª coluna (fixa ao rolar), o resto da linha vazio. */
  const cabecalhoSecao = (k: string, titulo: string, ajuda: string) => (
    <tr key={k} className="border-t-2 border-[var(--border)] bg-[var(--surface-2)]">
      <th scope="rowgroup" className={`${COL1} bg-[var(--surface-2)] text-[11px] font-semibold uppercase text-[var(--fg-2)]`}>
        {titulo} <span className="font-normal normal-case text-[var(--fg-3)]">— {ajuda}</span>
      </th>
      <td colSpan={nCols} />
    </tr>
  );

  const linhaSemBase = (k: string, rotulo: ReactNode, tratamento: string | null, recuo: boolean) => (
    <tr key={k} className="border-t border-[var(--border-faint)]">
      <td className={`${COL1} ${recuo ? 'pl-5 text-[var(--fg-2)]' : 'font-semibold text-[var(--fg)]'}`}>{rotulo}</td>
      <td colSpan={nCols} className="px-2 py-1 text-left text-[var(--fg-2)]">
        <span className="font-semibold text-[var(--fg)]">{SECOES_RECEBER.semBase}</span>{tratamento ? ` — ${tratamento}` : ''}
      </td>
    </tr>
  );

  const linhasDeValor = (bloco: number, g: LinhaGrade | BlocoGrade, clicavel: string | null, forte: boolean) => [
    ...g.porSemana.map((v, i) => (
      <td key={i} className={`${TD_NUM} ${forte ? 'font-semibold' : ''}`}>
        <Numero v={v} bruto={g.brutoPorSemana[i]} onClick={clicavel != null ? () => onSelecionar({ bloco, grupo: clicavel, semana: i }) : undefined}
          ativo={clicavel != null && eAtiva(bloco, clicavel, i)} />
      </td>
    )),
    <td key="t" className={`${TD_NUM} ${forte ? 'font-semibold' : ''} border-l border-[var(--border)]`}>
      <Numero v={g.total} bruto={g.brutoTotal} onClick={clicavel != null ? () => onSelecionar({ bloco, grupo: clicavel, semana: null }) : undefined}
        ativo={clicavel != null && eAtiva(bloco, clicavel, null)} />
    </td>,
  ];

  const linhasDoBlocoNaGrade = (bloco: number) => {
    const b = grade.blocos.find((x) => x.bloco === bloco);
    const gs = linhasDoBloco(bloco);
    const sb = semBaseDoBloco(bloco);
    const titulo = `${bloco}. ${rotuloBloco(bloco)}`;
    if (!b) {
      // Só "sem base": o bloco aparece, sem número.
      if (sb.length === 1 && sb[0].grupo === grupoUnico(bloco)) return [linhaSemBase(`sb${bloco}`, titulo, sb[0].tratamento, false)];
      return [
        <tr key={`b${bloco}`} className="border-t border-[var(--border)]">
          <td className={`${COL1} font-semibold text-[var(--fg)]`}>{titulo}</td>
          <td colSpan={nCols} />
        </tr>,
        ...sb.map((x) => linhaSemBase(`sb${bloco}-${x.grupo}`, x.grupo, x.tratamento, true)),
      ];
    }
    // Bloco com um grupo só e de mesmo nome (blocos 1 e 6): uma linha, clicável. Senão: subtotal + grupos.
    const unico = gs.length === 1 && gs[0].grupo === grupoUnico(bloco);
    return [
      <tr key={`b${bloco}`} className="border-t border-[var(--border)]">
        <td className={`${COL1} font-semibold text-[var(--fg)]`}>{titulo}</td>
        {linhasDeValor(bloco, b, unico ? gs[0].grupo : null, true)}
      </tr>,
      ...(unico ? [] : gs.map((g) => (
        <tr key={`g${bloco}-${g.grupo}`} className="border-t border-[var(--border-faint)]">
          <td className={`${COL1} pl-5 text-[var(--fg-2)]`}>{g.grupo}</td>
          {linhasDeValor(bloco, g, g.grupo, false)}
        </tr>
      ))),
      ...sb.map((x) => linhaSemBase(`sb${bloco}-${x.grupo}`, x.grupo, x.tratamento, true)),
    ];
  };

  const linhaTotal = (k: string, rotulo: string, porSemana: number[], total: number, classe: string) => (
    <tr key={k} className={classe}>
      <td className={COL1}>{rotulo}</td>
      {porSemana.map((v, i) => <td key={i} className={TD_NUM}><Numero v={v} /></td>)}
      <td className={`${TD_NUM} border-l border-[var(--border)]`}><Numero v={total} /></td>
    </tr>
  );

  const info = grade.informativo;

  return (
    <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
      <table className="w-max min-w-full border-collapse text-xs">
        <thead className="bg-[var(--surface-2)]">
          <tr>
            <th className={`${TH} sticky left-0 z-[1] bg-[var(--surface-2)] text-left`} rowSpan={2}>&nbsp;</th>
            {grade.meses.map((m) => (
              <th key={m.mes} colSpan={m.semanas.length} className={`${TH} border-l border-[var(--border)] text-center`}>{rotuloMes(m.mes)}</th>
            ))}
            <th className={`${TH} border-l border-[var(--border)] text-right`} rowSpan={2}>{GRADE_RECEBER.total}</th>
          </tr>
          <tr>
            {sems.map((s, i) => (
              <th key={s.n} className={`${TH} text-right font-normal normal-case ${grade.meses.some((m) => m.semanas[0] === i) ? 'border-l border-[var(--border)]' : ''}`}>
                <span className="block font-semibold">S{s.n}</span>{rotuloSemana(s)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {cabecalhoSecao('sec-certo', SECOES_RECEBER.certo, SECOES_RECEBER.certoAjuda)}
          {certo.flatMap(linhasDoBlocoNaGrade)}
          {temEstimado && linhaTotal('sub-certo', SECOES_RECEBER.subtotalCerto, grade.certoPorSemana, grade.certoTotal,
            'border-t border-[var(--border)] font-semibold text-[var(--fg)]')}
        </tbody>
        <tbody>
          {cabecalhoSecao('sec-estimado', SECOES_RECEBER.estimado, SECOES_RECEBER.estimadoAjuda)}
          {temEstimado ? estimado.flatMap(linhasDoBlocoNaGrade) : (
            <tr className="border-t border-[var(--border-faint)]">
              <td className={`${COL1} text-[var(--fg-3)]`}>{SECOES_RECEBER.nenhumEstimado}</td>
              <td colSpan={nCols} />
            </tr>
          )}
          {temEstimado && linhaTotal('sub-est', SECOES_RECEBER.subtotalEstimado, grade.estimadoPorSemana, grade.estimadoTotal,
            'border-t border-[var(--border)] font-semibold text-[var(--fg)]')}
        </tbody>
        <tbody>
          <tr className="border-t-2 border-[var(--border)] font-semibold text-[var(--fg)]">
            <td className={COL1}>{temEstimado ? SECOES_RECEBER.totalGeral : ROTULOS_TOTAL.totalDaSemana}</td>
            {grade.totalPorSemana.map((v, i) => <td key={i} className={TD_NUM}><Numero v={v} bruto={grade.brutoPorSemana[i]} /></td>)}
            <td className={`${TD_NUM} border-l border-[var(--border)]`}><Numero v={grade.total} bruto={grade.brutoTotal} /></td>
          </tr>
          <tr className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <td className={COL1}>{ROTULOS_TOTAL.totalDoMes}</td>
            {grade.meses.map((m) => (
              <td key={m.mes} colSpan={m.semanas.length} className={`${TD_NUM} text-center border-l border-[var(--border)]`}><Numero v={m.total} bruto={m.brutoTotal} /></td>
            ))}
            <td className={`${TD_NUM} border-l border-[var(--border)]`}><Numero v={grade.total} bruto={grade.brutoTotal} /></td>
          </tr>
          <tr className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
            <td className={COL1}>{ROTULOS_TOTAL.acumulado}</td>
            {grade.acumuladoPorSemana.map((v, i) => <td key={i} className={TD_NUM}><Numero v={v} /></td>)}
            <td className={`${TD_NUM} border-l border-[var(--border)]`} />
          </tr>
        </tbody>
        {info && (
          <tbody>
            {cabecalhoSecao('sec-info', SECOES_RECEBER.informativo, SECOES_RECEBER.informativoAjuda)}
            <tr className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
              <td className={`${COL1} pl-5`}>{rotuloBloco(BLOCO_INFORMATIVO)}</td>
              {info.porSemana.map((v, i) => (
                <td key={i} className={TD_NUM}>
                  <Numero v={v} onClick={() => onSelecionar({ bloco: BLOCO_INFORMATIVO, grupo: info.grupo, semana: i })}
                    ativo={eAtiva(BLOCO_INFORMATIVO, info.grupo, i)} />
                </td>
              ))}
              <td className={`${TD_NUM} border-l border-[var(--border)]`}>
                <Numero v={info.total} onClick={() => onSelecionar({ bloco: BLOCO_INFORMATIVO, grupo: info.grupo, semana: null })}
                  ativo={eAtiva(BLOCO_INFORMATIVO, info.grupo, null)} />
              </td>
            </tr>
          </tbody>
        )}
      </table>
    </div>
  );
}

/** Quem compõe a célula clicada. Bloco 1: as vendas do dia (detalhe). Blocos 2 e 5: as cobranças, com bruto, esperado e
 * o porquê; no bloco 2, as transações pagas do contrato (sem e-mail). */
export function ComposicaoCelula({ linhas, pagasPorRef, celula, semana, onFechar }: {
  linhas: LinhaReceber[]; pagasPorRef: Map<string, PagamentoContrato[]>; celula: Celula; semana: Semana | null; onFechar: () => void;
}) {
  const itens = composicaoDaCelula(linhas, semana, celula.bloco, celula.grupo);
  const total = itens.reduce((s, l) => s + Math.round(l.valor * 100), 0) / 100;
  const bruto = itens.reduce((s, l) => s + Math.round(l.valor_bruto * 100), 0) / 100;
  const comPerda = itens.some(temPerda);
  return (
    <section className="rounded-[var(--r-md)] border border-[var(--border)]" aria-label={`Composição: ${celula.grupo}`}>
      <div className="flex flex-wrap items-center gap-3 border-b border-[var(--border)] bg-[var(--surface-2)] px-2 py-1.5 text-xs">
        <span className="font-semibold text-[var(--fg)]">{celula.grupo}</span>
        <span className="text-[var(--fg-3)]">{semana ? `S${semana.n} · ${fmtData(semana.inicio)} a ${fmtData(semana.fim)}` : GRADE_RECEBER.todasAsSemanas}</span>
        <span className="tabular font-semibold text-[var(--fg)]">
          {comPerda ? GRADE_RECEBER.resumoComPerda(fmtBRLc(bruto), fmtBRLc(total)) : fmtBRLc(total)}
        </span>
        {celula.bloco === BLOCO_INFORMATIVO && <span className="text-[var(--fg-3)]">{GRADE_RECEBER.foraDaSoma}</span>}
        <button type="button" onClick={onFechar} className="ml-auto rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          {GRADE_RECEBER.fechar}
        </button>
      </div>
      <div className="overflow-x-auto">
        {celula.bloco === 1 ? <VendasDoDia itens={itens} />
          : celula.bloco === 3 || celula.bloco === 4 ? <VendasProjetadas itens={itens} />
            : celula.bloco === 6 ? <ReservaDaCelula itens={itens} />
              : <CobrancasDaCelula itens={itens} comPerda={comPerda} pagasPorRef={pagasPorRef} />}
      </div>
    </section>
  );
}

function VendasDoDia({ itens }: { itens: LinhaReceber[] }) {
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{GRADE_RECEBER.caiNoCaixa}</th><th className={TH}>{GRADE_RECEBER.parte}</th><th className={TH}>{GRADE_RECEBER.vendasDe}</th>
          <th className={TH}>{GRADE_RECEBER.transacao}</th><th className={TH}>{GRADE_RECEBER.produto}</th><th className={TH}>{GRADE_RECEBER.nome}</th>
          <th className={`${TH} text-right`}>{GRADE_RECEBER.liquidoDaVenda}</th><th className={`${TH} text-right`}>{GRADE_RECEBER.valor}</th>
          <th className={TH}>{GRADE_RECEBER.tratamento}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => [
          <tr key={`l${i}`} className="border-t border-[var(--border)] font-semibold text-[var(--fg)]">
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className="px-2 py-1">{rotuloComponente(l.componente)}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.origem_dia)}</td>
            <td className="px-2 py-1 font-normal text-[var(--fg-3)]" colSpan={3}>
              {l.detalhe.length ? GRADE_RECEBER.vendas(l.detalhe.length) : GRADE_RECEBER.semVendasNoDetalhe}
            </td>
            <td className={TD_NUM}>{fmtBRLc(l.detalhe.reduce((s, v) => s + v.liquido, 0))}</td>
            <td className={TD_NUM}>{fmtBRLc(l.valor)}</td>
            <td className="px-2 py-1 font-normal text-[var(--fg-2)]">{l.tratamento ?? '—'}</td>
          </tr>,
          ...l.detalhe.map((v, j) => (
            <tr key={`l${i}v${j}`} className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
              <td className="px-2 py-1" colSpan={3} />
              <td className="px-2 py-1 font-mono text-[11px]">{v.transacao}</td>
              <td className="px-2 py-1">{v.produto ?? '—'}</td>
              <td className="px-2 py-1">{v.nome ?? '—'}</td>
              <td className={TD_NUM}>{fmtBRLc(v.liquido)}</td>
              <td className="px-2 py-1" colSpan={2} />
            </tr>
          )),
        ])}
      </tbody>
    </table>
  );
}

/** Blocos 3 e 4 (estimado): cada data de caixa com a parte, a base do valor e as vendas projetadas que caem nela, com a
 * base de cada venda (mediana, definido por, curva). A linha do retido não repete a lista (é a mesma venda). */
function VendasProjetadas({ itens }: { itens: LinhaReceber[] }) {
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{GRADE_RECEBER.caiNoCaixa}</th><th className={TH}>{GRADE_RECEBER.parte}</th>
          <th className={TH}>{GRADE_RECEBER.vendasDe}</th><th className={TH}>{GRADE_RECEBER.deOndeVeio}</th>
          <th className={`${TH} text-right`}>{GRADE_RECEBER.valor}</th><th className={TH}>{GRADE_RECEBER.tratamento}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => [
          <tr key={`p${i}`} className="border-t border-[var(--border)] text-[var(--fg)]">
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className="px-2 py-1">{rotuloComponente(l.componente)}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.origem_dia)}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.rotulo ?? '—'}</td>
            <td className={`${TD_NUM} font-semibold`}>{fmtBRLc(l.valor)}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.tratamento ?? '—'}</td>
          </tr>,
          ...(l.projecao.length ? [
            <tr key={`p${i}d`}>
              <td className="px-2 pb-1 pl-5 text-[11px] text-[var(--fg-3)]" colSpan={6}>
                <span>{GRADE_RECEBER.vendasProjetadas(l.projecao.length)}</span>
                <table className="mt-0.5 border-collapse">
                  <thead>
                    <tr>
                      <th className="pr-3 text-left font-normal">{GRADE_RECEBER.vendasDe}</th>
                      <th className="pr-3 text-right font-normal">{GRADE_RECEBER.vendaDoDia}</th>
                      <th className="text-left font-normal">{GRADE_RECEBER.deOndeVeio}</th>
                    </tr>
                  </thead>
                  <tbody className="text-[var(--fg-2)]">
                    {l.projecao.map((v, j) => (
                      <tr key={`${v.dia}-${j}`}>
                        <td className="pr-3 tabular">{fmtData(v.dia)}</td>
                        <td className="pr-3 text-right tabular">{fmtBRLc(v.valor_venda)}</td>
                        <td>{v.base ?? '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </td>
            </tr>,
          ] : []),
        ])}
      </tbody>
    </table>
  );
}

/** Bloco 6: a reserva (negativa) por data de caixa, o percentual e de onde ele veio; a base em R$ vem no tratamento. */
function ReservaDaCelula({ itens }: { itens: LinhaReceber[] }) {
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{GRADE_RECEBER.caiNoCaixa}</th><th className={`${TH} text-right`}>{GRADE_RECEBER.valor}</th>
          <th className={TH}>{GRADE_RECEBER.deOndeVeio}</th><th className={TH}>{GRADE_RECEBER.tratamento}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => (
          <tr key={`r${i}`} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className={`${TD_NUM} font-semibold`}>{fmtBRLc(l.valor)}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.rotulo ?? '—'}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.tratamento ?? '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Fator de perda com 4 casas: 0,857375 → "× 0,8574". */
const fmtFator = (f: number) => `× ${f.toLocaleString('pt-BR', { minimumFractionDigits: 4, maximumFractionDigits: 4 })}`;

function CobrancasDaCelula({ itens, comPerda, pagasPorRef }: {
  itens: LinhaReceber[]; comPerda: boolean; pagasPorRef: Map<string, PagamentoContrato[]>;
}) {
  // Pelo contrato (ref), nunca por l.pagas: o banco manda a lista uma vez por contrato, só na 1ª linha a_receber.
  const pagasDe = (l: LinhaReceber) => (l.ref != null ? pagasPorRef.get(l.ref) : l.pagas) ?? [];
  const nCols = comPerda ? 9 : 7;
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{GRADE_RECEBER.nome}</th><th className={TH}>{GRADE_RECEBER.produto}</th><th className={TH}>{GRADE_RECEBER.cobrancaPrevista}</th>
          <th className={TH}>{GRADE_RECEBER.caiNoCaixa}</th><th className={TH}>{GRADE_RECEBER.parte}</th>
          {comPerda ? (
            <>
              <th className={`${TH} text-right`}>{GRADE_RECEBER.bruto}</th><th className={`${TH} text-right`}>{GRADE_RECEBER.fator}</th>
              <th className={`${TH} text-right`}>{GRADE_RECEBER.esperado}</th>
            </>
          ) : <th className={`${TH} text-right`}>{GRADE_RECEBER.valor}</th>}
          <th className={TH}>{GRADE_RECEBER.tratamento}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => [
          <tr key={`c${i}`} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <td className="px-2 py-1">{l.rotulo ?? '—'}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.produto ?? '—'}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.origem_dia)}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{rotuloComponente(l.componente)}</td>
            {comPerda ? (
              <>
                <td className={TD_NUM}>{fmtBRLc(l.valor_bruto)}</td>
                <td className={`${TD_NUM} text-[var(--fg-2)]`}>{temPerda(l) ? fmtFator(l.fator) : '—'}</td>
                <td className={`${TD_NUM} font-semibold`}>{fmtBRLc(l.valor)}</td>
              </>
            ) : <td className={TD_NUM}>{fmtBRLc(l.valor)}</td>}
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.tratamento ?? '—'}</td>
          </tr>,
          // Bloco 2: as transações pagas do contrato (só na linha antecipação/cheio; a garantia é a mesma cobrança).
          ...(l.bloco === 2 && l.componente !== 'garantia' ? [
            <tr key={`c${i}p`}>
              <td className="px-2 pb-1 pl-5 text-[11px] text-[var(--fg-3)]" colSpan={nCols}>
                {pagasDe(l).length === 0 ? GRADE_RECEBER.semPagasNoContrato : (
                  <>
                    <span>{GRADE_RECEBER.pagasDoContrato(pagasDe(l).length)}</span>
                    <table className="mt-0.5 border-collapse">
                      <thead>
                        <tr>
                          <th className="pr-3 text-left font-normal">{GRADE_RECEBER.parcela}</th>
                          <th className="pr-3 text-left font-normal">{GRADE_RECEBER.transacao}</th>
                          <th className="pr-3 text-left font-normal">{GRADE_RECEBER.pagaEm}</th>
                          <th className="text-right font-normal">{GRADE_RECEBER.liquidoPago}</th>
                        </tr>
                      </thead>
                      <tbody className="text-[var(--fg-2)]">
                        {pagasDe(l).map((p, j) => (
                          <tr key={`${p.transacao}-${j}`}>
                            <td className="pr-3 tabular">{p.n ?? '—'}</td>
                            <td className="pr-3 font-mono">{p.transacao}</td>
                            <td className="pr-3 tabular">{fmtData(p.dia)}</td>
                            <td className="text-right tabular">{fmtBRLc(p.liquido)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </>
                )}
              </td>
            </tr>,
          ] : []),
        ])}
      </tbody>
    </table>
  );
}

const SUBABAS_LISTA: { k: SubAbaReceber; l: string }[] = [
  { k: 'semana', l: SUBABAS_RECEBER.semana },
  { k: 'recorrencias', l: SUBABAS_RECEBER.recorrencias },
  { k: 'informados', l: SUBABAS_RECEBER.informados },
  { k: 'eventos', l: SUBABAS_RECEBER.eventos },
  { k: 'premissas', l: SUBABAS_RECEBER.premissas },
  { k: 'base', l: SUBABAS_RECEBER.base },
];

/** Tablist das sub-abas de Previsão de caixa. Padrão WAI-ARIA de "automatic activation": seta move o foco E
 * já troca a aba — não precisa de Enter/Espaço depois. Home/End vão à primeira/última. */
function SubAbasReceber({ ativa, onSelecionar }: { ativa: SubAbaReceber; onSelecionar: (s: SubAbaReceber) => void }) {
  const botoes = useRef<Partial<Record<SubAbaReceber, HTMLButtonElement | null>>>({});
  const ir = (alvo: SubAbaReceber) => { onSelecionar(alvo); botoes.current[alvo]?.focus(); };
  const mover = (dir: 1 | -1) => {
    const i = SUBABAS_LISTA.findIndex((s) => s.k === ativa);
    ir(SUBABAS_LISTA[(i + dir + SUBABAS_LISTA.length) % SUBABAS_LISTA.length].k);
  };
  return (
    <div
      role="tablist"
      aria-label={SUBABAS_RECEBER.rotuloGrupo}
      className="flex w-fit overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]"
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') { e.preventDefault(); mover(1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); mover(-1); }
        else if (e.key === 'Home') { e.preventDefault(); ir(SUBABAS_LISTA[0].k); }
        else if (e.key === 'End') { e.preventDefault(); ir(SUBABAS_LISTA[SUBABAS_LISTA.length - 1].k); }
      }}
    >
      {SUBABAS_LISTA.map((s, i) => (
        <button
          key={s.k}
          ref={(el) => { botoes.current[s.k] = el; }}
          type="button"
          role="tab"
          id={`receber-tab-${s.k}`}
          aria-selected={ativa === s.k}
          aria-controls={`receber-painel-${s.k}`}
          tabIndex={ativa === s.k ? 0 : -1}
          onClick={() => onSelecionar(s.k)}
          className={`${i ? 'border-l border-[var(--border)] ' : ''}px-3 py-1.5 text-xs font-semibold ${
            ativa === s.k ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'
          }`}
        >
          {s.l}
        </button>
      ))}
    </div>
  );
}

/** Seletor de cenário: grupo de botões de alternância (aria-pressed), um por cenário, e a legenda do que ele muda. */
export function SeletorCenario({ cenario, onCenario }: { cenario: CenarioReceber; onCenario: (c: CenarioReceber) => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2 text-xs">
      <div role="group" aria-labelledby="receber-cenario-rotulo" className="flex items-center gap-1">
        <span id="receber-cenario-rotulo" className="font-semibold text-[var(--fg-3)]">{CENARIO_RECEBER.rotulo}</span>
        {CENARIOS_RECEBER.map((c) => (
          <button key={c} type="button" aria-pressed={cenario === c} onClick={() => onCenario(c)}
            className={`rounded-[var(--r-sm)] border px-2 py-0.5 ${cenario === c ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'}`}>
            {CENARIO_RECEBER[c]}
          </button>
        ))}
      </div>
      <span className="text-[var(--fg-3)]">{CENARIO_RECEBER.legenda}</span>
    </div>
  );
}

/** Estado da sub-aba Premissas, guardado pelo pai (carga sob demanda, 1× enquanto a página está aberta). */
export interface PremissasEstado {
  premissas: VigenciaPremissa[] | null;
  feriados: FeriadoBancario[] | null;
  erroPremissas: string | null;
  erroFeriados: string | null;
  /** fn_fin_receber_sugestoes (z67), 1 chamada ao abrir a sub-aba. Ausente (pai antigo/teste) = sem sugestões. */
  sugestoes?: SugestaoPremissa[] | null;
  erroSugestoes?: string | null;
}

/** Estado da sub-aba Eventos, guardado pelo pai (carga sob demanda: a lista ao abrir a sub-aba; os candidatos a
 * referência, fn_fin_funis, só quando o formulário abre). */
export interface EventosEstado {
  eventos: EventoPlanejado[] | null;
  erro: string | null;
  candidatos: Funil[] | null;
  erroCandidatos: string | null;
}

export function ContasAReceber({
  dados, repo, canEdit, canVerDoc, onInformadosAlterados, sub, onSubChange,
  cenario = 'base', onCenario, premissas, onTentarPremissas, onPremissaGravada, onFeriadoGravado,
  eventos, onTentarEventos, onPedirCandidatos, onEventoAlterado,
}: {
  /** Carga do cenário ativo. NULL = o cenário ainda está carregando (a grade e Recorrências esperam; o resto não). */
  dados: ContasReceberCarregado | null;
  /** Recebimentos informados (bloco 5) e premissas. Sem repo, as sub-abas de escrita ficam vazias (teste de render). */
  repo?: RepoInformados & Partial<RepoPremissas> & Partial<RepoEventos>;
  canEdit?: boolean;
  canVerDoc?: boolean;
  onInformadosAlterados?: () => void;
  /** Sub-aba ativa. Controlada pelo pai (hash `#receber?ver=`, ver FinanceiroClient.tsx). Sem pai (ex.: testes),
   * o componente guarda o próprio estado, começando em "semana" — o mesmo destino do link `#receber` puro. */
  sub?: SubAbaReceber;
  onSubChange?: (s: SubAbaReceber) => void;
  cenario?: CenarioReceber;
  /** Troca de cenário: o pai consulta 1× por cenário e guarda. Sem pai, o seletor não aparece. */
  onCenario?: (c: CenarioReceber) => void;
  premissas?: PremissasEstado;
  onTentarPremissas?: () => void;
  onPremissaGravada?: () => void;
  onFeriadoGravado?: () => void;
  eventos?: EventosEstado;
  onTentarEventos?: () => void;
  /** O formulário de evento abriu: o pai busca os candidatos a referência (1×). */
  onPedirCandidatos?: () => void;
  /** Evento gravado ou arquivado: o pai rebusca a lista e a grade. */
  onEventoAlterado?: () => void;
}) {
  const [celula, setCelula] = useState<Celula | null>(null);
  const [subLocal, setSubLocal] = useState<SubAbaReceber>('semana');
  const subAtiva = sub ?? subLocal;
  const setSub = onSubChange ?? setSubLocal;
  const grade = dados?.grade ?? null;
  const semana = celula?.semana == null || !grade ? null : grade.semanas[celula.semana] ?? null;
  const repoPremissas: RepoPremissas | undefined = repo?.salvarPremissaReceber && repo.salvarFeriado
    ? { salvarPremissaReceber: repo.salvarPremissaReceber.bind(repo), salvarFeriado: repo.salvarFeriado.bind(repo) }
    : undefined;
  const repoEventos: RepoEventos | undefined = repo?.salvarEventoPlanejado && repo.arquivarEventoPlanejado
    ? { salvarEventoPlanejado: repo.salvarEventoPlanejado.bind(repo), arquivarEventoPlanejado: repo.arquivarEventoPlanejado.bind(repo) }
    : undefined;

  return (
    <div className="space-y-3">
      <p className="text-xs text-[var(--fg-3)]">{ESCOPO_RECEBER.legenda}</p>
      <SubAbasReceber ativa={subAtiva} onSelecionar={setSub} />

      {subAtiva === 'semana' && (
        <div id="receber-painel-semana" role="tabpanel" aria-labelledby="receber-tab-semana" className="space-y-3">
          {onCenario && <SeletorCenario cenario={cenario} onCenario={(c) => { setCelula(null); onCenario(c); }} />}
          {!dados || !grade ? (
            <p role="status" className="text-xs text-[var(--fg-3)]">{GRADE_RECEBER.carregandoCenario}</p>
          ) : dados.desligado ? (
            // Premissa de recebimento desligada: sem data de caixa não há grade — zero aqui seria mentira.
            <p role="alert" className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-3 py-2 text-sm font-semibold text-[var(--fg)]">
              {GRADE_RECEBER.recebimentoDesligado}
            </p>
          ) : grade.linhas.length === 0 ? (
            <p className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm text-[var(--fg-2)]">{ESTADOS_RECEBER.vazio}</p>
          ) : (
            <GradeContasReceber grade={grade} selecionada={celula}
              onSelecionar={(c) => setCelula((a) => (a && a.bloco === c.bloco && a.grupo === c.grupo && a.semana === c.semana ? null : c))} />
          )}
          {dados && grade && !dados.desligado && grade.semDataCaixa.linhas > 0 && (
            <p className="text-xs text-[var(--fg-3)]">{GRADE_RECEBER.semDataCaixa(grade.semDataCaixa.linhas, fmtBRLc(grade.semDataCaixa.valor))}</p>
          )}
          {grade && grade.foraDoPeriodo.linhas > 0 && (
            <p className="text-xs text-[var(--fg-3)]">{GRADE_RECEBER.foraDoPeriodo(grade.foraDoPeriodo.linhas, fmtBRLc(grade.foraDoPeriodo.valor))}</p>
          )}
          {grade && grade.informativo && grade.informativo.foraDoPeriodo.linhas > 0 && (
            <p className="text-xs text-[var(--fg-3)]">
              {SECOES_RECEBER.informativoForaDoPeriodo(grade.informativo.foraDoPeriodo.linhas, fmtBRLc(grade.informativo.foraDoPeriodo.valor))}
            </p>
          )}
          {dados && celula && <ComposicaoCelula linhas={dados.linhas} pagasPorRef={dados.pagasPorRef} celula={celula} semana={semana} onFechar={() => setCelula(null)} />}
        </div>
      )}

      {subAtiva === 'base' && (
        <div id="receber-painel-base" role="tabpanel" aria-labelledby="receber-tab-base" className="space-y-3">
          {/* Sem consulta nova: as linhas do cenário ativo, as mesmas da grade. Trocar o cenário usa o cache do pai. */}
          {onCenario && <SeletorCenario cenario={cenario} onCenario={(c) => { setCelula(null); onCenario(c); }} />}
          {dados?.desligado && (
            <p role="alert" className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-3 py-2 text-sm font-semibold text-[var(--fg)]">
              {GRADE_RECEBER.recebimentoDesligado}
            </p>
          )}
          {dados ? <BaseAuditavel dados={dados} rotuloCenario={CENARIO_RECEBER[dados.cenario]} />
            : <p role="status" className="text-xs text-[var(--fg-3)]">{GRADE_RECEBER.carregandoCenario}</p>}
        </div>
      )}

      {subAtiva === 'recorrencias' && (
        <div id="receber-painel-recorrencias" role="tabpanel" aria-labelledby="receber-tab-recorrencias">
          {dados ? <Recorrencias cobrancas={dados.recorrencias} />
            : <p role="status" className="text-xs text-[var(--fg-3)]">{GRADE_RECEBER.carregandoCenario}</p>}
        </div>
      )}

      {subAtiva === 'informados' && repo && (
        <div id="receber-painel-informados" role="tabpanel" aria-labelledby="receber-tab-informados">
          {/* A carga (fn_fin_informados_listar) acontece SOB DEMANDA ao abrir esta sub-aba, não junto da grade. */}
          <Informados repo={repo} canEdit={!!canEdit} canVerDoc={!!canVerDoc} onAlterado={onInformadosAlterados} />
        </div>
      )}

      {subAtiva === 'eventos' && (
        <div id="receber-painel-eventos" role="tabpanel" aria-labelledby="receber-tab-eventos">
          <Eventos eventos={eventos?.eventos ?? null} erro={eventos?.erro ?? null} candidatos={eventos?.candidatos ?? null}
            erroCandidatos={eventos?.erroCandidatos ?? null} canEdit={!!canEdit} hojeISO={dados?.hojeISO ?? hojeSaoPaulo()}
            repo={repoEventos} onTentarDeNovo={onTentarEventos} onPedirCandidatos={onPedirCandidatos} onAlterado={onEventoAlterado} />
        </div>
      )}

      {subAtiva === 'premissas' && (
        <div id="receber-painel-premissas" role="tabpanel" aria-labelledby="receber-tab-premissas">
          <Premissas premissas={premissas?.premissas ?? null} feriados={premissas?.feriados ?? null}
            erroPremissas={premissas?.erroPremissas ?? null} erroFeriados={premissas?.erroFeriados ?? null}
            sugestoes={premissas?.sugestoes} erroSugestoes={premissas?.erroSugestoes ?? null}
            canEdit={!!canEdit} hojeISO={dados?.hojeISO ?? hojeSaoPaulo()} repo={repoPremissas}
            onTentarDeNovo={onTentarPremissas} onPremissaGravada={onPremissaGravada} onFeriadoGravado={onFeriadoGravado} />
        </div>
      )}
    </div>
  );
}
