'use client';

// Recorrências: as cobranças futuras do bloco 2 (assinaturas e parcelas a vencer), uma linha por cobrança
// (antecipação + garantia da mesma cobrança juntas pela `ref`), com a situação de cada uma.
// Valor = a cobrança sem perda; Esperado (só quando há perda no cenário) = o que a grade soma.
// "Realizada" aparece para auditoria e não soma na grade; "fora da projeção" saiu da projeção; "coberta por recebimento
// informado" é a cobrança que um informado (bloco 5) já cobre — não soma, para não contar duas vezes. Nunca "devendo".
// O nome "Carteira" está reservado para outra tela.
import { useMemo, useState } from 'react';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import { hojeSaoPaulo } from '../../application/carregar-contas-receber';
import type { CobrancaRecorrente, SituacaoReceber } from '../../domain/contas-receber';
import { diasEntre, resumoRecorrencias, type FaixaAtraso } from '../../domain/receber-executivo';
import { EXECUTIVO_RECEBER, SECAO_RECORRENCIAS, SITUACAO_RECEBER, TABELA_RECORRENCIAS } from './textos';
import { BarrasH, Chip, CX_TABELA_LONGA, FaixaKpis, Farol, KpiFin, LINHA, THEAD_FIXO, Vazio, type TomFin } from './visual';

const T = TABELA_RECORRENCIAS;

const ORDEM: SituacaoReceber[] = ['a_receber', 'realizada', 'em_atraso_fora', 'coberta_informado'];

export function rotuloSituacao(s: string): string {
  if (s === 'a_receber') return SITUACAO_RECEBER.aReceber;
  if (s === 'realizada') return SITUACAO_RECEBER.realizada;
  if (s === 'em_atraso_fora') return SITUACAO_RECEBER.foraDaProjecao;
  if (s === 'coberta_informado') return SITUACAO_RECEBER.cobertaInformado;
  return s; // fora do contrato: mostra cru, não disfarça
}

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const X = EXECUTIVO_RECEBER.recorrencias;

/** Tom da situação: realizada = verde, fora da projeção (atraso) = vermelho, o resto neutro. */
const TOM_SITUACAO: Record<string, TomFin> = { realizada: 'bom', em_atraso_fora: 'ruim' };
const TOM_FAIXA: Record<FaixaAtraso, TomFin> = { ate30: 'atencao', de31a60: 'ruim', mais60: 'ruim' };
const pct = (v: number | null) => (v == null ? '—' : `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`);

export function Recorrencias({ cobrancas, filtroInicial = null, hojeISO }: {
  cobrancas: CobrancaRecorrente[];
  /** Situação já filtrada ao abrir (link da Visão geral, `&situacao=`). O pai troca a `key` quando ele muda. */
  filtroInicial?: string | null;
  /** Hoje (São Paulo) para a idade do atraso. Padrão: agora. */
  hojeISO?: string;
}) {
  const hoje = hojeISO ?? hojeSaoPaulo();
  const ex = useMemo(() => resumoRecorrencias(cobrancas, hoje), [cobrancas, hoje]);
  const [filtro, setFiltro] = useState<SituacaoReceber | null>(
    ORDEM.includes(filtroInicial as SituacaoReceber) ? (filtroInicial as SituacaoReceber) : null);
  const resumo = useMemo(() => {
    const r = new Map<string, { n: number; cents: number }>();
    for (const c of cobrancas) {
      const x = r.get(c.situacao) ?? { n: 0, cents: 0 };
      x.n += 1; x.cents += Math.round(c.valor * 100);
      r.set(c.situacao, x);
    }
    return r;
  }, [cobrancas]);
  // Com perda (cenário), a cobrança tem valor (bruto) e esperado; sem perda, uma coluna só.
  const comPerda = cobrancas.some((c) => Math.round(c.valor * 100) !== Math.round(c.esperado * 100));
  const nCols = comPerda ? 8 : 7;
  const visiveis = filtro ? cobrancas.filter((c) => c.situacao === filtro) : cobrancas;
  const botoes: { k: SituacaoReceber | null; l: string; n: number; v: number | null }[] = [
    { k: null, l: T.todas, n: cobrancas.length, v: null },
    ...ORDEM.map((s) => ({ k: s, l: rotuloSituacao(s), n: resumo.get(s)?.n ?? 0, v: (resumo.get(s)?.cents ?? 0) / 100 })),
  ];

  const top = ex.porProduto[0];
  return (
    <section className="space-y-2" aria-labelledby="recorrencias-titulo">
      <FaixaKpis>
        <KpiFin rotulo={X.aReceber} icone="wallet" valor={fmtBRLc(ex.aReceber.valor)} tom={ex.aReceber.n > 0 ? 'bom' : 'neutro'}
          onClick={() => setFiltro('a_receber')}
          detalhe={ex.aReceber.n === 0 ? X.nenhuma : `${X.cobrancas(ex.aReceber.n)}${top ? ` · ${X.maior(top.produto, pct(top.pct))}` : ''}`} />
        <KpiFin rotulo={X.emDia} valor={pct(ex.pctEmDia)}
          tom={ex.pctEmDia == null ? 'neutro' : ex.pctEmDia >= 95 ? 'bom' : ex.pctEmDia >= 85 ? 'atencao' : 'ruim'}
          detalhe={X.emDiaAjuda} />
        <KpiFin rotulo={X.atraso} icone="alert" valor={ex.atraso.n === 0 ? X.nenhuma : fmtBRLc(ex.atraso.valor)}
          tom={ex.atraso.n === 0 ? 'bom' : 'ruim'} onClick={ex.atraso.n === 0 ? undefined : () => setFiltro('em_atraso_fora')}
          detalhe={ex.atraso.n === 0 ? X.nadaAtrasado : `${X.cobrancas(ex.atraso.n)} · ${X.maisAntiga(ex.maiorAtrasoDias ?? 0)}`} />
        <KpiFin rotulo={X.realizadas} valor={fmtBRLc(ex.realizada.valor)} tom="neutro"
          onClick={ex.realizada.n === 0 ? undefined : () => setFiltro('realizada')}
          detalhe={`${X.cobrancas(ex.realizada.n)}${ex.coberta.n > 0 ? ` · ${X.cobertas(fmtBRLc(ex.coberta.valor))}` : ''}`} />
      </FaixaKpis>
      {ex.atraso.n === 0 ? (
        <p className="text-xs"><Farol ok>{X.semAtraso}</Farol></p>
      ) : (
        <BarrasH titulo={X.agingTitulo}
          itens={ex.aging.map((a) => ({ rotulo: X.faixas[a.faixa], valor: a.valor, tom: TOM_FAIXA[a.faixa], detalhe: X.cobrancas(a.n) }))} />
      )}
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="recorrencias-titulo" className="text-sm font-semibold text-[var(--fg)]">{SECAO_RECORRENCIAS.titulo}</h2>
        {botoes.map((b) => (
          <button key={b.k ?? 'todas'} type="button" aria-pressed={filtro === b.k} onClick={() => setFiltro(b.k)}
            className={`rounded-[var(--r-sm)] border px-2 py-0.5 text-xs ${filtro === b.k ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`}>
            {b.l} <span className="tabular">{b.n}</span>{b.v != null && b.n > 0 ? <span className="tabular"> · {fmtBRLc(b.v)}</span> : null}
          </button>
        ))}
      </div>
      <div className={CX_TABELA_LONGA}>
        <table className="w-full border-collapse text-xs">
          <thead className={THEAD_FIXO}>
            <tr>
              <th className={TH}>{T.cobrancaPrevista}</th><th className={TH}>{T.grupo}</th>
              <th className={TH}>{T.nome}</th><th className={TH}>{T.produto}</th>
              <th className={TH}>{T.caiNoCaixa}</th><th className={`${TH} text-right`}>{T.valor}</th>
              {comPerda && <th className={`${TH} text-right`}>{T.esperado}</th>}
              <th className={TH}>{T.situacao}</th>
            </tr>
          </thead>
          <tbody>
            {visiveis.length === 0 ? (
              <tr><td colSpan={nCols} className="px-2 py-2"><Vazio>{T.nenhuma}{filtro ? ` ${X.trocarFiltro}` : ''}</Vazio></td></tr>
            ) : visiveis.map((c, i) => (
              <tr key={`${c.ref ?? 'sem-ref'}-${c.situacao}-${i}`} className={`${LINHA} text-[var(--fg)]`}>
                <td className="px-2 py-1 tabular whitespace-nowrap">{fmtData(c.prevista)}</td>
                <td className="min-w-[9rem] px-2 py-1 text-[var(--fg-2)]">{c.grupo}</td>
                <td className="min-w-[14rem] px-2 py-1">{c.rotulo ?? '—'}</td>
                <td className="min-w-[9rem] px-2 py-1 text-[var(--fg-2)]">{c.produto ?? '—'}</td>
                <td className="px-2 py-1 tabular whitespace-nowrap text-[var(--fg-2)]">{c.caixa.map(fmtData).join(' · ') || '—'}</td>
                <td className="px-2 py-1 text-right font-semibold tabular whitespace-nowrap">{fmtBRLc(c.valor)}</td>
                {comPerda && <td className="px-2 py-1 text-right tabular whitespace-nowrap">{fmtBRLc(c.esperado)}</td>}
                <td className="px-2 py-1 whitespace-nowrap">
                  {/* O texto diz a situação; cor e ícone só reforçam. Atraso diz há quantos dias venceu. */}
                  <Chip tom={TOM_SITUACAO[c.situacao] ?? 'neutro'}>{rotuloSituacao(c.situacao)}</Chip>
                  {c.situacao === 'em_atraso_fora' && (
                    <span className="ml-1.5 text-[11px] text-[var(--red)]">{X.ha(Math.max(0, diasEntre(c.prevista, hoje)))}</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
