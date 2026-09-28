'use client';

// Serviço Diamante — aba do Board Financeiro (27/09/2026, 2ª rodada). O João: "coloca ele como uma aba no board
// financeiro… abrir o card do aluno, ver o status dele certinho, o nível dele, quem é ele… se a pessoa estiver devendo
// tem que estar bem escancarado… bater o olho e entender cada caso".
// Layout: faixa de cobrança (o que está em aberto, em vermelho) → colunas por situação (Devendo · Em dia · Parou
// devendo · Encerrado), como o mosaico do board → ficha lateral com a grade de meses de cada serviço.
// Fonte: fn_fin_diamante_servicos (espelho da Hotmart + cadastro Diamante). Só leitura.
import { useEffect, useMemo, useRef, useState } from 'react';
import { AvatarInicial, Drawer, Loading, NivelBadge, Row, SearchInput } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import {
  agruparPorDiamante, compraEmOutroNome, dividaTotal, ehNivelDiamante, recebidoPorMes, resumirDiamantes, ROTULO_NIVEL, ROTULO_SITUACAO_SERVICO,
  rotuloServico, ultimosMeses, type DiamanteCliente, type EstadoMes, type LinhaServicoDiamante, type SituacaoServico,
} from '../domain/servico-diamante';
import { hojeSaoPaulo } from '../domain/prorata-hm';
import { celulaCsv, type DiaHotmart } from '../domain/hotmart';
import { TelefoneContato } from './FichaDrawer';
import { Erro, useCarga } from './hotmart/comum';

const COR: Record<SituacaoServico, string> = {
  devendo: 'var(--red)', em_dia: 'var(--green)', parou_devendo: 'var(--accent)', encerrado: 'var(--fg-4)', nunca_pagou: 'var(--yellow)',
};
const COLUNAS: { s: SituacaoServico; titulo: string }[] = [
  { s: 'devendo', titulo: 'Devendo' },
  { s: 'em_dia', titulo: 'Em dia' },
  { s: 'parou_devendo', titulo: 'Parou devendo' },
  { s: 'encerrado', titulo: 'Encerrado' },
];
const COR_MES: Record<EstadoMes, string> = {
  pago: 'var(--green)', atrasado: 'var(--red)', coberto: 'var(--cyan)', estornado: 'var(--yellow)', tentativa: 'var(--fg-4)',
};
const ROTULO_MES: Record<EstadoMes, string> = {
  pago: 'pago', atrasado: 'em aberto', coberto: 'coberto por pagamento agrupado ou acordo', estornado: 'estornado', tentativa: 'só tentativa',
};
const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const mesCurto = (k: string) => `${MESES[Number(k.slice(5, 7)) - 1]}/${k.slice(2, 4)}`;
const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** Carrega as linhas uma vez (117 ms, ~180 linhas); a contagem da aba e o board usam o mesmo resultado. */
export function useServicoDiamante(repo: FinanceiroRepository, ativo: boolean) {
  const [estado, setEstado] = useState<{ dados: LinhaServicoDiamante[] | null; erro: string | null }>({ dados: null, erro: null });
  const pedido = useRef(false);
  useEffect(() => {
    if (!ativo || pedido.current) return;
    pedido.current = true;
    repo.loadServicoDiamante()
      .then((d) => setEstado({ dados: d, erro: null }))
      .catch((e: Error) => setEstado({ dados: null, erro: e.message }));
  }, [repo, ativo]);
  return estado;
}

/** Quantos Diamantes já pagaram — o número da aba. */
export function contarDiamantes(dados: LinhaServicoDiamante[] | null): number | null {
  if (!dados) return null;
  return new Set(dados.filter((l) => l.pagamentos > 0).map((l) => l.pessoa_chave)).size;
}

export function ServicoDiamante({ dados, erro, repo }: { dados: LinhaServicoDiamante[] | null; erro: string | null; repo: FinanceiroRepository }) {
  const [servico, setServico] = useState<string | null>(null);
  const [busca, setBusca] = useState('');
  const [verNunca, setVerNunca] = useState(false);
  const [aberto, setAberto] = useState<string | null>(null);
  const hoje = hojeSaoPaulo();
  const [mesAtual, mesAnterior] = [ultimosMeses(hoje, 1)[0], ultimosMeses(hoje, 2)[0]];
  // Recebido no mês e no anterior (espelho da Hotmart, família DIAMANTE) — a comparação do faturamento esperado.
  const { dados: fat } = useCarga<DiaHotmart[]>(() => repo.loadHotmartFaturamento('DIAMANTE', `${mesAnterior}-01`, hoje), [mesAnterior, hoje]);
  const recebido = useMemo(() => recebidoPorMes(fat ?? []), [fat]);

  const clientes = useMemo(() => agruparPorDiamante(dados ?? []), [dados]);
  const resumo = useMemo(() => resumirDiamantes(clientes), [clientes]);
  const visiveis = useMemo(() => {
    const q = semAcento(busca.trim());
    return clientes.filter((c) => {
      if (servico && !c.servicos.some((s) => s.servico === servico)) return false;
      if (q && !semAcento([c.nome, c.nomeCompra ?? '', ...c.emails].join(' ')).includes(q)) return false;
      return true;
    });
  }, [clientes, servico, busca]);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando Serviço Diamante…" minHeight={260} />;

  const devedores = clientes.filter((c) => c.jaPagou && dividaTotal(c) > 0);
  const naRua = resumo.devendoAtivoValor + resumo.pararamDevendoValor;
  const recebidoMes = fat ? recebido.get(mesAtual) ?? 0 : null;
  const recebidoAnt = fat ? recebido.get(mesAnterior) ?? 0 : null;
  const cobrancaAtiva = clientes.filter((c) => c.jaPagou && dividaTotal(c) > 0);
  const aberta = aberto ? clientes.find((c) => c.pessoa_chave === aberto) ?? null : null;
  const nunca = visiveis.filter((c) => !c.jaPagou);

  return (
    <div className="space-y-4">
      {/* Visão macro (João, 27/09): faturamento esperado por mês · dinheiro na rua · quanto os Diamantes devem */}
      <div className="grid gap-3 lg:grid-cols-3">
        <Macro rotulo="Faturamento esperado por mês" valor={fmtBRL(resumo.esperadoMes)} cor="var(--fg)"
          linhas={[
            `${resumo.ativos} Diamantes ativos · serviços em dia e devendo`,
            recebidoMes == null ? 'carregando o recebido…'
              : `Recebido em ${mesCurto(mesAtual)}: ${fmtBRL(recebidoMes)} (${resumo.esperadoMes ? Math.round((recebidoMes / resumo.esperadoMes) * 100) : 0}% do esperado; inclui atrasados e acordos pagos no mês)`,
            recebidoAnt == null ? '' : `Recebido em ${mesCurto(mesAnterior)}: ${fmtBRL(recebidoAnt)}`,
          ]} />
        <Macro rotulo="Dinheiro na rua" valor={fmtBRL(naRua)} cor={naRua > 0 ? 'var(--red)' : 'var(--green)'} destaque={naRua > 0}
          linhas={[
            `${devedores.length} Diamantes com mensalidade cobrada e não paga`,
            `${fmtBRL(resumo.pararamDevendoValor)} de ${resumo.pararamDevendo} que pararam de pagar`,
          ]} />
        <Macro rotulo="Diamantes ativos devendo" valor={fmtBRL(resumo.devendoAtivoValor)} cor={resumo.devendoAtivoValor > 0 ? 'var(--red)' : 'var(--green)'} destaque={resumo.devendoAtivoValor > 0}
          linhas={[
            `${resumo.devendo} Diamantes ainda com serviço ativo`,
            `${resumo.emDia} em dia · ${fmtBRL(resumo.mensalidadeAtiva)}/mês pagos em dia`,
          ]} />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] text-[var(--fg-3)]">
        <span>{resumo.jaPagaram} Diamantes já pagaram · {fmtBRL(resumo.totalPago)} desde o início</span>
        <button type="button" onClick={() => exportarCobranca(cobrancaAtiva)} disabled={!cobrancaAtiva.length}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)] disabled:opacity-50">
          Baixar lista de cobrança ({cobrancaAtiva.length})
        </button>
      </div>

      {/* Filtros: serviço + busca */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-full sm:w-64">
          <SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} placeholder="Buscar Diamante ou e-mail" aria-label="Buscar Diamante" />
        </div>
        <Pilula ativo={!servico} onClick={() => setServico(null)}>Todos os serviços</Pilula>
        {resumo.servicos.filter((s) => s.chave !== 'desconhecida').map((s) => (
          <Pilula key={s.chave} ativo={servico === s.chave} onClick={() => setServico(servico === s.chave ? null : s.chave)}>
            {rotuloServico(s.chave)}
            <span className="tabular text-[var(--fg-4)]" title="em dia / já contrataram">{s.emDia}/{s.contrataram}</span>
            {s.devendo > 0 && <span className="tabular font-bold text-[var(--red)]" title="devendo">{s.devendo}</span>}
          </Pilula>
        ))}
      </div>

      {/* Colunas por situação — como o mosaico do board */}
      <div className="grid gap-3 lg:grid-cols-2 2xl:grid-cols-4">
        {COLUNAS.map((col) => {
          const lista = visiveis.filter((c) => c.jaPagou && c.situacao === col.s);
          const total = col.s === 'em_dia' ? lista.reduce((a, c) => a + c.mensalidadeAtiva, 0) : lista.reduce((a, c) => a + dividaTotal(c), 0);
          return (
            <section key={col.s} aria-label={col.titulo} className="flex min-h-[120px] flex-col overflow-hidden rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)]">
              <header className="flex items-center justify-between gap-2 border-b border-[var(--border)] px-3 py-2" style={{ borderTop: `3px solid ${COR[col.s]}` }}>
                <span className="text-sm font-semibold text-[var(--fg)]">{col.titulo} <span className="tabular text-[var(--fg-3)]">{lista.length}</span></span>
                {total > 0 && <span className="tabular text-xs font-semibold" style={{ color: COR[col.s] }}>{fmtBRL(total)}{col.s === 'em_dia' ? '/mês' : ''}</span>}
              </header>
              <ul className={`flex-1 space-y-2 p-2 ${col.s === 'encerrado' ? 'max-h-[560px] overflow-y-auto' : ''}`}>
                {lista.length === 0 && <li className="px-2 py-4 text-center text-xs text-[var(--fg-4)]">Ninguém</li>}
                {lista.map((c) => <li key={c.pessoa_chave}><CardDiamante c={c} servicoFoco={servico} onOpen={() => setAberto(c.pessoa_chave)} /></li>)}
              </ul>
            </section>
          );
        })}
      </div>

      {nunca.length > 0 && (
        <div>
          <button type="button" onClick={() => setVerNunca(!verNunca)} aria-expanded={verNunca}
            className="text-xs font-semibold text-[var(--fg-3)] hover:text-[var(--fg)]">
            {verNunca ? '▾' : '▸'} Tentaram e nunca pagaram ({nunca.length})
          </button>
          {verNunca && (
            <ul className="mt-2 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
              {nunca.map((c) => <li key={c.pessoa_chave}><CardDiamante c={c} servicoFoco={servico} onOpen={() => setAberto(c.pessoa_chave)} /></li>)}
            </ul>
          )}
        </div>
      )}

      {aberta && <FichaDiamante c={aberta} hoje={hoje} onClose={() => setAberto(null)} />}
    </div>
  );
}

function Macro({ rotulo, valor, cor, linhas, destaque }: { rotulo: string; valor: string; cor: string; linhas: string[]; destaque?: boolean }) {
  return (
    <div className={`rounded-[var(--r-lg)] border px-4 py-3 ${destaque ? 'border-[var(--red)] bg-[var(--red-subtle)]' : 'border-[var(--border)] bg-[var(--surface-1)]'}`}>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-2)]">{rotulo}</div>
      <div className="tabular mt-0.5 text-3xl font-bold" style={{ color: cor }}>{valor}</div>
      {linhas.filter(Boolean).map((l) => <div key={l} className="tabular text-xs text-[var(--fg-2)]">{l}</div>)}
    </div>
  );
}

/** Lista de cobrança (CSV, separador ; para o Excel pt-BR): quem deve, quanto, desde quando, de quais serviços. */
function exportarCobranca(lista: DiamanteCliente[]) {
  const col: [string, (c: DiamanteCliente) => unknown][] = [
    ['Nome', (c) => c.nome], ['Situação', (c) => ROTULO_SITUACAO_SERVICO[c.situacao]], ['Nível', (c) => (c.nivel ? ROTULO_NIVEL[c.nivel] ?? c.nivel : '')],
    ['Em aberto', (c) => dividaTotal(c).toFixed(2).replace('.', ',')], ['Mensalidades em aberto', (c) => c.devendoN + c.antigoN],
    ['Desde', (c) => c.servicos.map((s) => s.antigo_desde ?? s.devendo_desde).filter(Boolean).sort()[0] ?? ''],
    ['Serviços devendo', (c) => c.servicos.filter((s) => s.devendo_n + s.antigo_n > 0).map((s) => `${rotuloServico(s.servico)} ${s.devendo_n + s.antigo_n}x`).join(', ')],
    ['Serviços em dia', (c) => c.servicos.filter((s) => s.situacao === 'em_dia').map((s) => rotuloServico(s.servico)).join(', ')],
    ['Último pagamento', (c) => c.ultimaPaga ?? ''], ['E-mail', (c) => c.email], ['Outros e-mails', (c) => c.emails.filter((e) => e !== c.email).join(', ')],
    ['Telefone', (c) => c.telefone ?? ''], ['Nome na compra', (c) => c.nomeCompra ?? ''],
  ];
  const linhas = [col.map(([n]) => n).join(';'), ...lista.map((c) => col.map(([, f]) => celulaCsv(f(c))).join(';'))];
  const blob = new Blob(['\ufeff' + linhas.join('\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `cobranca-servico-diamante-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

function Pilula({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button type="button" aria-pressed={ativo} onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-2.5 py-1 text-xs ${ativo ? 'border-[var(--accent)] bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
      {children}
    </button>
  );
}

function CardDiamante({ c, servicoFoco, onOpen }: { c: DiamanteCliente; servicoFoco: string | null; onOpen: () => void }) {
  const divida = dividaTotal(c);
  return (
    <button type="button" onClick={onOpen}
      className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2.5 text-left transition-colors hover:border-[var(--border-strong)] focus-visible:ring-2"
      style={{ borderLeft: `3px solid ${COR[c.situacao]}` }}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="truncate text-sm font-semibold text-[var(--fg)]">{c.nome}</div>
          <div className="mt-0.5 flex min-w-0 items-center gap-1.5 text-[10px] text-[var(--fg-3)]">
            {c.nivel ? <span className={`shrink-0 ${ehNivelDiamante(c.nivel) ? 'text-[var(--cyan)]' : 'text-[var(--yellow)]'}`}>{ROTULO_NIVEL[c.nivel] ?? c.nivel}</span> : <span className="shrink-0">sem nível</span>}
            {compraEmOutroNome(c.nome, c.nomeCompra) && <span className="truncate">· compra como {c.nomeCompra}</span>}
            {c.acordoPago > 0 && <span className="shrink-0 text-[var(--cyan)]">· acordo pago</span>}
          </div>
        </div>
        <div className="shrink-0 text-right">
          {divida > 0 ? (
            <>
              <div className="tabular text-sm font-bold text-[var(--red)]">{fmtBRL(divida)}</div>
              <div className="tabular text-[10px] text-[var(--red)]">{c.devendoN + c.antigoN} mensalidade{c.devendoN + c.antigoN === 1 ? '' : 's'}</div>
            </>
          ) : c.mensalidadeAtiva > 0 ? (
            <div className="tabular text-sm font-semibold text-[var(--fg)]">{fmtBRL(c.mensalidadeAtiva)}<span className="text-[10px] font-normal text-[var(--fg-3)]">/mês</span></div>
          ) : (
            <div className="tabular text-[10px] text-[var(--fg-3)]">{c.ultimaPaga ? `até ${fmtData(c.ultimaPaga)}` : '—'}</div>
          )}
        </div>
      </div>
      <div className="mt-2 flex flex-wrap gap-1">
        {c.servicos.map((s) => (
          <span key={s.servico} title={`${rotuloServico(s.servico)}: ${ROTULO_SITUACAO_SERVICO[s.situacao]}`}
            className={`inline-flex items-center gap-1 rounded-[var(--r-sm)] border px-1.5 py-0.5 text-[10px] ${servicoFoco === s.servico ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)]'} ${s.situacao === 'encerrado' ? 'opacity-60' : ''}`}>
            <span className="h-1.5 w-1.5 rounded-full" style={{ background: COR[s.situacao] }} aria-hidden />
            {rotuloServico(s.servico)}
          </span>
        ))}
      </div>
    </button>
  );
}

function FichaDiamante({ c, hoje, onClose }: { c: DiamanteCliente; hoje: string; onClose: () => void }) {
  const meses = ultimosMeses(hoje, 12);
  const divida = dividaTotal(c);
  const desde = c.servicos.map((s) => s.antigo_desde ?? s.devendo_desde).filter((d): d is string => !!d).sort()[0];
  return (
    <Drawer
      onClose={onClose}
      title={c.nome}
      subtitle={c.email ?? undefined}
      avatar={<AvatarInicial nome={c.nome} size={44} />}
      badges={
        <>
          {c.nivel ? <NivelBadge nivel={c.nivel} /> : <span className="text-xs text-[var(--fg-3)]">sem nível no cadastro</span>}
          <span className="inline-flex items-center rounded-[var(--r-sm)] border px-2 py-0.5 text-xs font-semibold" style={{ borderColor: COR[c.situacao], color: COR[c.situacao] }}>
            {ROTULO_SITUACAO_SERVICO[c.situacao]}
          </span>
          {c.nivel && !ehNivelDiamante(c.nivel) && <span className="rounded-[var(--r-sm)] border border-[var(--yellow)] px-2 py-0.5 text-xs text-[var(--fg-2)]">nível no cadastro não é Diamante</span>}
        </>
      }
    >
      <div className="space-y-5">
        <div className="grid gap-2 sm:grid-cols-3">
          <Caixa rotulo="Em aberto" valor={fmtBRL(divida)} cor={divida > 0 ? 'var(--red)' : 'var(--green)'}
            sub={divida > 0 ? `${c.devendoN + c.antigoN} mensalidade(s)${desde ? ` · desde ${fmtData(desde)}` : ''}` : 'nada em aberto'} />
          <Caixa rotulo="Mensalidade ativa" valor={c.mensalidadeAtiva ? `${fmtBRL(c.mensalidadeAtiva)}/mês` : '—'}
            sub={`${c.servicos.filter((s) => s.situacao === 'em_dia').length} serviço(s) em dia`} />
          <Caixa rotulo="Pago desde o início" valor={fmtBRL(c.totalPago)} sub={c.primeiraPaga ? `cliente desde ${fmtData(c.primeiraPaga)}` : ''} />
        </div>
        {c.cobertoN > 0 && (
          <p className="rounded-[var(--r-md)] border border-[var(--cyan)] px-3 py-2 text-xs text-[var(--fg-2)]">
            {c.cobertoN} mensalidade(s) atrasada(s) ({fmtBRL(c.cobertoValor)}) foram abatidas por pagamento agrupado, oferta &quot;Vencido&quot; ou acordo
            {c.acordoPago > 0 ? <> — acordo pago: <strong className="tabular">{fmtBRL(c.acordoPago)}</strong>, a confirmar com o financeiro</> : null}.
          </p>
        )}

        <div>
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Mensalidades — últimos 12 meses</span>
            <span className="flex flex-wrap gap-2 text-[10px] text-[var(--fg-3)]">
              {(['pago', 'atrasado', 'coberto'] as EstadoMes[]).map((e) => (
                <span key={e} className="inline-flex items-center gap-1"><span className="h-2.5 w-2.5 rounded-sm" style={{ background: COR_MES[e] }} />{ROTULO_MES[e]}</span>
              ))}
            </span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[560px] text-[11px]">
              <thead>
                <tr className="text-[var(--fg-4)]">
                  <th className="w-36 pb-1 text-left font-normal"><span className="sr-only">Serviço</span></th>
                  {meses.map((m) => <th key={m} className="pb-1 text-center font-normal">{mesCurto(m)}</th>)}
                </tr>
              </thead>
              <tbody>
                {[...c.servicos, ...(c.acordo ? [c.acordo] : [])].map((s) => (
                  <tr key={s.servico}>
                    <td className="py-0.5 pr-2 font-medium text-[var(--fg)]">{rotuloServico(s.servico)}</td>
                    {meses.map((m) => {
                      const e = s.meses?.[m];
                      return (
                        <td key={m} className="px-0.5 py-0.5">
                          <div className="mx-auto h-4 w-full max-w-[30px] rounded-[3px] border border-[var(--border)]"
                            style={{ background: e ? COR_MES[e] : 'transparent' }}
                            title={`${rotuloServico(s.servico)} · ${mesCurto(m)}: ${e ? ROTULO_MES[e] : 'sem cobrança'}`} />
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Serviços contratados</div>
          <div className="space-y-2">
            {c.servicos.map((s) => {
              const deve = s.devendo_valor + s.antigo_valor;
              return (
                <div key={s.servico} className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2" style={{ borderLeft: `3px solid ${COR[s.situacao]}` }}>
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="text-sm font-semibold text-[var(--fg)]">{rotuloServico(s.servico)}</span>
                    <span className="text-xs font-semibold" style={{ color: COR[s.situacao] }}>{ROTULO_SITUACAO_SERVICO[s.situacao]}</span>
                  </div>
                  <div className="mt-1 grid grid-cols-2 gap-x-4 gap-y-0.5 text-[11px] text-[var(--fg-2)] sm:grid-cols-4">
                    <span>Mensalidade <strong className="tabular">{s.mensalidade ? fmtBRL(s.mensalidade) : '—'}</strong></span>
                    <span>Pagou <strong className="tabular">{s.pagamentos}×</strong> · {fmtBRL(s.total_pago)}</span>
                    <span>{s.primeira_paga ? `${fmtData(s.primeira_paga)} a ${fmtData(s.ultima_paga!)}` : 'nenhum pagamento'}</span>
                    <span className={deve > 0 ? 'font-semibold text-[var(--red)]' : ''}>
                      {deve > 0 ? `Deve ${fmtBRL(deve)} (${s.devendo_n + s.antigo_n}×)` : 'Nada em aberto'}
                    </span>
                  </div>
                  {s.desconhecida && <div className="mt-1 text-[10px] text-[var(--fg-4)]">oferta fora do catálogo: {(s.ofertas ?? []).join(', ')}</div>}
                </div>
              );
            })}
          </div>
        </div>

        <div className="space-y-1">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Quem é</div>
          <Row k="Nome" v={c.nome} />
          {c.nomeCompra && <Row k="Nome na compra (Hotmart)" v={c.nomeCompra} />}
          <Row k="Cadastro" v={c.clienteCadastro ? 'cliente do sistema Diamantes' : 'fora do cadastro Diamantes (nome do cadastro de alunos ou da Hotmart)'} />
          <Row k="Nível" v={c.nivel ? ROTULO_NIVEL[c.nivel] ?? c.nivel : 'não informado'} />
          <Row k="E-mails de compra" v={c.emails.join(', ') || '—'} />
          <TelefoneContato telefone={c.telefone} />
        </div>
      </div>
    </Drawer>
  );
}

function Caixa({ rotulo, valor, sub, cor }: { rotulo: string; valor: string; sub?: string; cor?: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
      <div className="text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular text-lg font-bold" style={{ color: cor ?? 'var(--fg)' }}>{valor}</div>
      {sub && <div className="text-[10px] text-[var(--fg-3)]">{sub}</div>}
    </div>
  );
}
