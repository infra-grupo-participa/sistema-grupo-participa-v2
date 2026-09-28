'use client';

// Aba "Contas a Receber" (fase 1, 28/09/2026): grade semana (colunas) × bloco/grupo (linhas), com total por semana,
// por mês e acumulado. Substitui o "Fluxo Semanal" da planilha do financeiro nos blocos 1 e 2 (o que é certo).
// Clicar num número abre, logo abaixo da grade e SEM consulta nova, quem compõe aquele valor — tudo sai da mesma
// resposta de fn_fin_contas_receber (application/carregar-contas-receber.ts).
// O detalhe fica no fluxo da página (não é `absolute`): nada invisível entra na área rolável da grade.
import { useState } from 'react';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { ContasReceberCarregado } from '../../application/carregar-contas-receber';
import {
  composicaoDaCelula, GRUPO_BLOCO_1, type GradeReceber, type LinhaReceber, type Semana,
} from '../../domain/contas-receber';
import { Recorrencias } from './Recorrencias';
import { BLOCOS_RECEBER, COMPONENTES_VENDA, ESCOPO_RECEBER, ESTADOS_RECEBER, ROTULOS_TOTAL } from './textos';

// Textos provisórios — ainda não existem em ./textos (luis move para lá).
const PROVISORIO = {
  total: 'Total',
  componenteCheio: 'Valor cheio',
  recebimentoDesligado: 'Cálculo de recebimento desligado',
  semDataCaixa: (n: number, v: string) => `${n} cobrança(s) a receber sem data de caixa (${v}) não estão somadas acima.`,
  foraDoPeriodo: (n: number, v: string) => `${n} lançamento(s) a receber fora do período da grade (${v}) não estão somados acima.`,
  fechar: 'Fechar',
  todasAsSemanas: 'todas as semanas',
  caiNoCaixa: 'Cai no caixa',
  parte: 'Parte',
  vendasDe: 'Vendas de',
  transacao: 'Transação',
  produto: 'Produto',
  nome: 'Nome',
  liquidoDaVenda: 'Líquido da venda',
  valor: 'Valor',
  cobrancaPrevista: 'Vencimento',
  semVendasNoDetalhe: 'vendas do dia não vieram no detalhe',
} as const;

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const rotuloMes = (m: string) => `${MESES[Number(m.slice(5, 7)) - 1]}/${m.slice(0, 4)}`;
const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const rotuloSemana = (s: Semana) => (s.inicio === s.fim ? ddmm(s.inicio) : `${s.inicio.slice(8, 10)}–${ddmm(s.fim)}`);

export function rotuloComponente(c: string): string {
  if (c === 'antecipacao') return COMPONENTES_VENDA.antecipacao;
  if (c === 'garantia') return COMPONENTES_VENDA.garantia;
  if (c === 'cheio') return PROVISORIO.componenteCheio;
  return c;
}

const rotuloBloco = (b: number) => (b === 1 ? BLOCOS_RECEBER.vendasRealizadas : b === 2 ? BLOCOS_RECEBER.assinaturasEParcelasFuturas : `Bloco ${b}`);

type Celula = { bloco: number; grupo: string; semana: number | null };

const TH = 'px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD_NUM = 'px-2 py-1 text-right tabular whitespace-nowrap';
const COL1 = 'sticky left-0 z-[1] bg-[var(--surface-1)] px-2 py-1 text-left whitespace-nowrap';

function Numero({ v, onClick, ativo }: { v: number; onClick?: () => void; ativo?: boolean }) {
  if (v === 0) return <span className="text-[var(--fg-4)]">–</span>;
  if (!onClick) return <>{fmtBRLc(v)}</>;
  return (
    <button type="button" onClick={onClick} aria-pressed={ativo}
      className={`tabular underline decoration-dotted underline-offset-2 hover:text-[var(--accent)] ${ativo ? 'font-semibold text-[var(--accent)]' : 'text-[var(--fg)]'}`}>
      {fmtBRLc(v)}
    </button>
  );
}

export function GradeContasReceber({ grade, selecionada, onSelecionar }: {
  grade: GradeReceber; selecionada: Celula | null; onSelecionar: (c: Celula) => void;
}) {
  const sems = grade.semanas;
  const eAtiva = (bloco: number, grupo: string, semana: number | null) =>
    selecionada?.bloco === bloco && selecionada.grupo === grupo && selecionada.semana === semana;
  const linhasDoBloco = (b: number) => grade.linhas.filter((l) => l.bloco === b);

  return (
    <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
      <table className="w-max min-w-full border-collapse text-xs">
        <thead className="bg-[var(--surface-2)]">
          <tr>
            <th className={`${TH} sticky left-0 z-[1] bg-[var(--surface-2)] text-left`} rowSpan={2}>&nbsp;</th>
            {grade.meses.map((m) => (
              <th key={m.mes} colSpan={m.semanas.length} className={`${TH} border-l border-[var(--border)] text-center`}>{rotuloMes(m.mes)}</th>
            ))}
            <th className={`${TH} border-l border-[var(--border)] text-right`} rowSpan={2}>{PROVISORIO.total}</th>
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
          {grade.blocos.map((b) => {
            const gs = linhasDoBloco(b.bloco);
            // Bloco com um grupo só e de mesmo nome (bloco 1): uma linha, clicável. Senão: subtotal + grupos.
            const unico = gs.length === 1 && gs[0].grupo === (b.bloco === 1 ? GRUPO_BLOCO_1 : rotuloBloco(b.bloco));
            return [
              <tr key={`b${b.bloco}`} className="border-t border-[var(--border)]">
                <td className={`${COL1} font-semibold text-[var(--fg)]`}>{b.bloco}. {rotuloBloco(b.bloco)}</td>
                {b.porSemana.map((v, i) => (
                  <td key={i} className={`${TD_NUM} font-semibold`}>
                    <Numero v={v} onClick={unico ? () => onSelecionar({ bloco: b.bloco, grupo: gs[0].grupo, semana: i }) : undefined}
                      ativo={unico && eAtiva(b.bloco, gs[0].grupo, i)} />
                  </td>
                ))}
                <td className={`${TD_NUM} font-semibold border-l border-[var(--border)]`}>
                  <Numero v={b.total} onClick={unico ? () => onSelecionar({ bloco: b.bloco, grupo: gs[0].grupo, semana: null }) : undefined}
                    ativo={unico && eAtiva(b.bloco, gs[0].grupo, null)} />
                </td>
              </tr>,
              ...(unico ? [] : gs.map((g) => (
                <tr key={`g${b.bloco}-${g.grupo}`} className="border-t border-[var(--border-faint)]">
                  <td className={`${COL1} pl-5 text-[var(--fg-2)]`}>{g.grupo}</td>
                  {g.porSemana.map((v, i) => (
                    <td key={i} className={TD_NUM}>
                      <Numero v={v} onClick={() => onSelecionar({ bloco: g.bloco, grupo: g.grupo, semana: i })} ativo={eAtiva(g.bloco, g.grupo, i)} />
                    </td>
                  ))}
                  <td className={`${TD_NUM} border-l border-[var(--border)]`}>
                    <Numero v={g.total} onClick={() => onSelecionar({ bloco: g.bloco, grupo: g.grupo, semana: null })} ativo={eAtiva(g.bloco, g.grupo, null)} />
                  </td>
                </tr>
              ))),
            ];
          })}
          <tr className="border-t-2 border-[var(--border)] font-semibold text-[var(--fg)]">
            <td className={COL1}>{ROTULOS_TOTAL.totalDaSemana}</td>
            {grade.totalPorSemana.map((v, i) => <td key={i} className={TD_NUM}><Numero v={v} /></td>)}
            <td className={`${TD_NUM} border-l border-[var(--border)]`}><Numero v={grade.total} /></td>
          </tr>
          <tr className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <td className={COL1}>{ROTULOS_TOTAL.totalDoMes}</td>
            {grade.meses.map((m) => (
              <td key={m.mes} colSpan={m.semanas.length} className={`${TD_NUM} text-center border-l border-[var(--border)]`}><Numero v={m.total} /></td>
            ))}
            <td className={`${TD_NUM} border-l border-[var(--border)]`}><Numero v={grade.total} /></td>
          </tr>
          <tr className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
            <td className={COL1}>{ROTULOS_TOTAL.acumulado}</td>
            {grade.acumuladoPorSemana.map((v, i) => <td key={i} className={TD_NUM}><Numero v={v} /></td>)}
            <td className={`${TD_NUM} border-l border-[var(--border)]`} />
          </tr>
        </tbody>
      </table>
    </div>
  );
}

/** Quem compõe a célula clicada. Bloco 1: as vendas do dia (detalhe). Bloco 2: as cobranças. */
export function ComposicaoCelula({ linhas, celula, semana, onFechar }: {
  linhas: LinhaReceber[]; celula: Celula; semana: Semana | null; onFechar: () => void;
}) {
  const itens = composicaoDaCelula(linhas, semana, celula.bloco, celula.grupo);
  const total = itens.reduce((s, l) => s + Math.round(l.valor * 100), 0) / 100;
  return (
    <section className="rounded-[var(--r-md)] border border-[var(--border)]" aria-label={`Composição: ${celula.grupo}`}>
      <div className="flex items-center gap-3 border-b border-[var(--border)] bg-[var(--surface-2)] px-2 py-1.5 text-xs">
        <span className="font-semibold text-[var(--fg)]">{celula.grupo}</span>
        <span className="text-[var(--fg-3)]">{semana ? `S${semana.n} · ${fmtData(semana.inicio)} a ${fmtData(semana.fim)}` : PROVISORIO.todasAsSemanas}</span>
        <span className="tabular font-semibold text-[var(--fg)]">{fmtBRLc(total)}</span>
        <button type="button" onClick={onFechar} className="ml-auto rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          {PROVISORIO.fechar}
        </button>
      </div>
      <div className="overflow-x-auto">
        {celula.bloco === 1 ? <VendasDoDia itens={itens} /> : <CobrancasDaCelula itens={itens} />}
      </div>
    </section>
  );
}

function VendasDoDia({ itens }: { itens: LinhaReceber[] }) {
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{PROVISORIO.caiNoCaixa}</th><th className={TH}>{PROVISORIO.parte}</th><th className={TH}>{PROVISORIO.vendasDe}</th>
          <th className={TH}>{PROVISORIO.transacao}</th><th className={TH}>{PROVISORIO.produto}</th><th className={TH}>{PROVISORIO.nome}</th>
          <th className={`${TH} text-right`}>{PROVISORIO.liquidoDaVenda}</th><th className={`${TH} text-right`}>{PROVISORIO.valor}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => [
          <tr key={`l${i}`} className="border-t border-[var(--border)] font-semibold text-[var(--fg)]">
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className="px-2 py-1">{rotuloComponente(l.componente)}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.origem_dia)}</td>
            <td className="px-2 py-1 font-normal text-[var(--fg-3)]" colSpan={3}>
              {l.detalhe.length ? `${l.detalhe.length} venda(s)` : PROVISORIO.semVendasNoDetalhe}
            </td>
            <td className={TD_NUM}>{fmtBRLc(l.detalhe.reduce((s, v) => s + v.liquido, 0))}</td>
            <td className={TD_NUM}>{fmtBRLc(l.valor)}</td>
          </tr>,
          ...l.detalhe.map((v, j) => (
            <tr key={`l${i}v${j}`} className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
              <td className="px-2 py-1" colSpan={3} />
              <td className="px-2 py-1 font-mono text-[11px]">{v.transacao}</td>
              <td className="px-2 py-1">{v.produto ?? '—'}</td>
              <td className="px-2 py-1">{v.nome ?? '—'}</td>
              <td className={TD_NUM}>{fmtBRLc(v.liquido)}</td>
              <td className="px-2 py-1" />
            </tr>
          )),
        ])}
      </tbody>
    </table>
  );
}

function CobrancasDaCelula({ itens }: { itens: LinhaReceber[] }) {
  return (
    <table className="w-full border-collapse text-xs">
      <thead>
        <tr className="text-left">
          <th className={TH}>{PROVISORIO.nome}</th><th className={TH}>{PROVISORIO.produto}</th><th className={TH}>{PROVISORIO.cobrancaPrevista}</th>
          <th className={TH}>{PROVISORIO.caiNoCaixa}</th><th className={TH}>{PROVISORIO.parte}</th><th className={`${TH} text-right`}>{PROVISORIO.valor}</th>
        </tr>
      </thead>
      <tbody>
        {itens.map((l, i) => (
          <tr key={i} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
            <td className="px-2 py-1">{l.rotulo ?? '—'}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{l.produto ?? '—'}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.origem_dia)}</td>
            <td className="px-2 py-1 tabular">{fmtData(l.data_caixa)}</td>
            <td className="px-2 py-1 text-[var(--fg-2)]">{rotuloComponente(l.componente)}</td>
            <td className={TD_NUM}>{fmtBRLc(l.valor)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export function ContasAReceber({ dados }: { dados: ContasReceberCarregado }) {
  const [celula, setCelula] = useState<Celula | null>(null);
  const { grade, linhas, recorrencias, desligado } = dados;
  const semana = celula?.semana == null ? null : grade.semanas[celula.semana] ?? null;
  const vazio = grade.linhas.length === 0;

  return (
    <div className="space-y-3">
      <p className="text-xs text-[var(--fg-3)]">{ESCOPO_RECEBER.legenda}</p>
      {desligado ? (
        // Premissa de recebimento desligada: sem data de caixa não há grade — zero aqui seria mentira.
        <p role="alert" className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-3 py-2 text-sm font-semibold text-[var(--fg)]">
          {PROVISORIO.recebimentoDesligado}
        </p>
      ) : vazio ? (
        <p className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm text-[var(--fg-2)]">{ESTADOS_RECEBER.vazio}</p>
      ) : (
        <GradeContasReceber grade={grade} selecionada={celula}
          onSelecionar={(c) => setCelula((a) => (a && a.bloco === c.bloco && a.grupo === c.grupo && a.semana === c.semana ? null : c))} />
      )}
      {!desligado && grade.semDataCaixa.linhas > 0 && (
        <p className="text-xs text-[var(--fg-3)]">{PROVISORIO.semDataCaixa(grade.semDataCaixa.linhas, fmtBRLc(grade.semDataCaixa.valor))}</p>
      )}
      {grade.foraDoPeriodo.linhas > 0 && (
        <p className="text-xs text-[var(--fg-3)]">{PROVISORIO.foraDoPeriodo(grade.foraDoPeriodo.linhas, fmtBRLc(grade.foraDoPeriodo.valor))}</p>
      )}
      {celula && <ComposicaoCelula linhas={linhas} celula={celula} semana={semana} onFechar={() => setCelula(null)} />}
      <Recorrencias cobrancas={recorrencias} />
    </div>
  );
}
