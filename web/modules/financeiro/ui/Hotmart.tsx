'use client';

// Aba "Hotmart" do financeiro (27/09/2026) — a fonte oficial do dinheiro.
//
// Lê o espelho da API da Hotmart (schema fin, sincronizado de hora em hora pela
// Edge Function hotmart-sync). SÓ LEITURA: nada aqui altera o board, os cards ou o
// que o financeiro já mostra. Quatro visões:
//   Faturamento · bruto (valor da oferta) × líquido (o que fica para o produtor)
//   Pessoas     · situação de cada comprador + extrato com o que ele TENTOU comprar
//   Ofertas     · o que cada código é, quanto vendeu, se está no catálogo
//   Conciliação · o que a Hotmart tem e o banco não (webhook que falhou)
import { useEffect, useMemo, useState } from 'react';
import { Badge, DataTable, EmptyState, KpiCard, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import {
  celulaCsv, contarSituacoes, ORDEM_SITUACAO, REGRA_TAXA_HOTMART, resumirHotmart, ROTULO_GRUPO, ROTULO_SITUACAO,
  rotuloDocumento, serieHotmart,
  type DiaHotmart, type DivergenciaHotmart, type FamiliaHotmart, type OfertaHotmart,
  type IdentidadeRevisao, type PessoaHotmart, type SituacaoPessoa, type SyncHotmart, type TransacaoHotmart,
} from '../domain/hotmart';

type Visao = 'faturamento' | 'pessoas' | 'identidade' | 'ofertas' | 'conciliacao';
const PERIODOS = [
  { dias: 30, rotulo: '30 dias' }, { dias: 90, rotulo: '90 dias' },
  { dias: 365, rotulo: '12 meses' },
  // "Tudo" = desde a 1ª venda do espelho (Aurum, 2021). "3 anos" cortava o HM de ago/2023.
  { dias: Math.ceil((Date.now() - Date.UTC(2021, 0, 1)) / 86_400_000), rotulo: 'Tudo (desde 2021)' },
] as const;

const TOM_SITUACAO: Record<SituacaoPessoa, Tone> = {
  devendo: 'danger', negociacao_cancelamento: 'danger', em_pagamento: 'warning', boleto_em_aberto: 'warning',
  reembolsado: 'neutral', ativo: 'success', inadimplencia_antiga: 'warning', vencido: 'neutral', so_tentou: 'info',
};
const MOTIVO_SUGESTAO: Record<string, string> = {
  mesmo_telefone: 'Mesmo telefone', mesmo_nome: 'Mesmo nome', mesmo_documento_tentativa: 'Mesmo CPF em tentativa',
};
const TOM_GRUPO: Record<TransacaoHotmart['grupo'], Tone> = {
  pago: 'success', estornado: 'danger', atrasado: 'danger', em_aberto: 'warning', recusado: 'neutral', expirado: 'neutral', outro: 'neutral',
};

function isoDiasAtras(n: number): string {
  const d = new Date(Date.now() - n * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

export function Hotmart({ repo }: { repo: FinanceiroRepository }) {
  const [visao, setVisao] = useState<Visao>('faturamento');
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');
  const [sync, setSync] = useState<{ s: SyncHotmart; atrasado: boolean } | null>(null);

  useEffect(() => {
    repo.loadHotmartSync()
      .then((s) => setSync(s ? {
        s,
        // Rotina roda de hora em hora: mais de 3 h sem atualizar é sincronização parada.
        atrasado: !!s.ultima_atualizacao && Date.now() - new Date(s.ultima_atualizacao).getTime() > 3 * 3_600_000,
      } : null))
      .catch(() => setSync(null));
  }, [repo]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {(['faturamento', 'pessoas', 'identidade', 'ofertas', 'conciliacao'] as Visao[]).map((v) => (
          <button
            key={v}
            type="button"
            aria-pressed={visao === v}
            onClick={() => setVisao(v)}
            className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold ${visao === v ? 'border-[var(--accent)] bg-[var(--accent-subtle)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'}`}
          >
            {{ faturamento: 'Dia a dia', pessoas: 'Pessoas', identidade: 'Mesma pessoa?', ofertas: 'Ofertas', conciliacao: 'Conciliação' }[v]}
          </button>
        ))}
        <span className="mx-1 h-5 w-px bg-[var(--border)]" aria-hidden="true" />
        {(['HM', 'AURUM'] as FamiliaHotmart[]).map((f) => (
          <button
            key={f}
            type="button"
            aria-pressed={familia === f}
            onClick={() => setFamilia(f)}
            className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold disabled:opacity-50 ${familia === f ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}
          >
            {f === 'HM' ? 'Holding Masters' : 'Aurum'}
          </button>
        ))}
        <SyncSelo sync={sync} />
      </div>

      {visao === 'faturamento' && <VisaoFaturamento repo={repo} familia={familia} />}
      {visao === 'pessoas' && <VisaoPessoas repo={repo} familia={familia} />}
      {visao === 'identidade' && <VisaoIdentidade repo={repo} />}
      {visao === 'ofertas' && <VisaoOfertas repo={repo} familia={familia} />}
      {visao === 'conciliacao' && <VisaoConciliacao repo={repo} familia={familia} />}
    </div>
  );
}

function SyncSelo({ sync: estado }: { sync: { s: SyncHotmart; atrasado: boolean } | null }) {
  if (!estado) return null;
  const sync = estado.s;
  const tom: Tone = sync.janelas_com_erro > 0 || estado.atrasado ? 'warning' : 'success';
  return (
    <span className="ml-auto">
      <Badge tone={tom}>
        {sync.transacoes.toLocaleString('pt-BR')} transações · atualizado {sync.ultima_atualizacao ? fmtDataHora(sync.ultima_atualizacao) : '—'}
        {sync.janelas_pendentes > 0 ? ` · sincronizando histórico (${sync.janelas_pendentes})` : ''}
        {sync.janelas_com_erro > 0 ? ` · ${sync.janelas_com_erro} janela(s) com erro` : ''}
      </Badge>
    </span>
  );
}

/** Carrega sob demanda. O resultado guarda a CHAVE da consulta que o gerou: trocar
 *  de filtro não mostra o dado velho (a chave não bate → volta a "carregando"),
 *  sem setState síncrono dentro do efeito. */
function useCarga<T>(fn: () => Promise<T>, deps: unknown[]) {
  const chave = JSON.stringify(deps);
  const [res, setRes] = useState<{ chave: string; dados: T | null; erro: string | null } | null>(null);
  useEffect(() => {
    let vivo = true;
    fn()
      .then((d) => { if (vivo) setRes({ chave, dados: d, erro: null }); })
      .catch((e: Error) => { if (vivo) setRes({ chave, dados: null, erro: e.message }); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave]);
  const atual = res && res.chave === chave ? res : null;
  return { dados: atual?.dados ?? null, erro: atual?.erro ?? null };
}

function Erro({ msg }: { msg: string }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--red-border)] bg-[var(--red-subtle)] p-4 text-sm text-[var(--fg)]">
      <Icon name="alert" size={16} className="mr-1.5 inline text-[var(--red)]" />{msg}
    </div>
  );
}

// ─── Faturamento ────────────────────────────────────────────────────────────
function VisaoFaturamento({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const [intervalo, setIntervalo] = useState<{ de: string; ate: string; preset: number | null }>(
    { de: isoDiasAtras(29), ate: isoDiasAtras(0), preset: 30 });
  const { dados, erro } = useCarga<DiaHotmart[]>(
    () => repo.loadHotmartFaturamento(familia, intervalo.de, intervalo.ate), [familia, intervalo.de, intervalo.ate]);
  const resumo = useMemo(() => resumirHotmart(dados ?? []), [dados]);
  const serie = useMemo(() => serieHotmart(dados ?? []), [dados]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-1.5">
        {PERIODOS.map((p) => (
          <button key={p.dias} type="button" aria-pressed={intervalo.preset === p.dias}
            onClick={() => setIntervalo({ de: isoDiasAtras(p.dias - 1), ate: isoDiasAtras(0), preset: p.dias })}
            className={`rounded-[var(--r-sm)] border px-2.5 py-1 text-xs ${intervalo.preset === p.dias ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}>
            {p.rotulo}
          </button>
        ))}
        <span className="ml-2 text-xs text-[var(--fg-3)]">ou de</span>
        <input type="date" aria-label="Data inicial" value={intervalo.de} max={intervalo.ate}
          onChange={(e) => e.target.value && setIntervalo({ ...intervalo, de: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
        <span className="text-xs text-[var(--fg-3)]">até</span>
        <input type="date" aria-label="Data final" value={intervalo.ate} min={intervalo.de}
          onChange={(e) => e.target.value && setIntervalo({ ...intervalo, ate: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
      </div>
      {erro ? <Erro msg={erro} /> : !dados ? <Loading label="Carregando faturamento…" minHeight={200} /> : (
        <>
          {/* Do bruto ao líquido: o que foi vendido, o que a Hotmart tira e o que fica para nós. */}
          <div className={`grid grid-cols-2 gap-2.5 ${resumo.repasses > 0 ? 'lg:grid-cols-4' : 'lg:grid-cols-3'}`}>
            <KpiCard label="Bruto (vendido)" value={fmtBRL(resumo.valorOferta)} bar="accent"
              hint={`${resumo.vendas} venda(s) paga(s) · preço das ofertas`}
              title="Soma do preço das ofertas vendidas e pagas. Não inclui os juros do parcelamento, que o cliente paga à Hotmart." />
            <KpiCard label="− Taxa da Hotmart" value={fmtBRL(resumo.taxa)} bar="yellow"
              hint={resumo.taxaPct != null ? `${(resumo.taxaPct * 100).toFixed(2)}% do bruto · ${REGRA_TAXA_HOTMART}` : REGRA_TAXA_HOTMART}
              title="O que a Hotmart cobra de nós por venda. Regra medida em 27/09/2026: 4% do valor da oferta + R$ 1 por venda." />
            {resumo.repasses > 0 && (
              <KpiCard label="− Coprodução / afiliados" value={fmtBRL(resumo.repasses)} bar="purple"
                hint="coprodutor, afiliados e add-on (produtos antigos do Aurum)"
                title="Oferta − taxa − líquido: comissão de coprodutor (Borboleta Digital), de afiliados e do add-on Club nas vendas antigas do Aurum." />
            )}
            <KpiCard label="= Líquido (fica para nós)" value={fmtBRL(resumo.liquido)} bar="green"
              hint={resumo.margem != null ? `${(resumo.margem * 100).toFixed(1)}% do bruto${resumo.liquidoEstimado ? ` · ${resumo.liquidoEstimado} estimado(s)` : ''}` : 'sem venda no período'}
              title="O que cai para o produtor (comissão PRODUCER da API da Hotmart)." />
          </div>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-2.5">
            <KpiCard label="Juros do parcelamento" value={fmtBRL(resumo.juros)} bar="gray"
              hint="pago pelo cliente · fica com a Hotmart, não é nosso"
              title="Quando o cliente parcela no cartão, ele paga juros à Hotmart. Esse valor não sai do nosso bruto nem entra no líquido." />
            <KpiCard label="Reembolsos / chargebacks" value={fmtBRL(resumo.valorEstornado)} bar="red"
              hint={`${resumo.estornos} venda(s) devolvida(s)`} />
            <KpiCard label="Cartões recusados" value={String(resumo.recusadas)} bar="gray"
              hint="tentativas de compra que não passaram" />
          </div>
          <SectionCard title="Dia a dia" subtitle="Dia da aprovação do pagamento (horário de São Paulo). Recusas e boletos contam no dia do pedido. Dia sem venda aparece como R$ 0.">
            {!serie.length ? <EmptyState title="Nenhuma movimentação no período" icon="trending-up" /> : (
              <DataTable minWidth={1100}>
                <Thead>
                  <Th>Dia</Th><Th>Vendas</Th><Th>Bruto</Th><Th>Taxa Hotmart</Th>
                  {resumo.repasses > 0 && <Th>Coprodução / afiliados</Th>}
                  <Th>Líquido</Th><Th>vs. dia anterior</Th><Th>Acumulado</Th><Th>Juros (cliente)</Th>
                  <Th>Reembolsos</Th><Th>Recusados</Th><Th>Boletos</Th>
                </Thead>
                <tbody>
                  {[...serie].reverse().map((d) => (
                    <Tr key={d.dia} className={d.preenchido ? 'opacity-60' : undefined}>
                      <Td className="tabular">
                        {fmtData(d.dia)}
                        {d.preenchido && <span className="ml-1.5 text-[10px] font-medium text-[var(--fg-3)]">sem venda</span>}
                      </Td>
                      <Td className="tabular">{d.vendas}</Td>
                      <Td className="tabular font-semibold">{fmtBRL(d.bruto)}</Td>
                      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(d.taxa)}</Td>
                      {resumo.repasses > 0 && <Td className="tabular text-[var(--fg-2)]">{d.repasses > 0 ? fmtBRL(d.repasses) : '—'}</Td>}
                      <Td className="tabular font-semibold text-[var(--green)]">
                        {fmtBRL(d.liquido)}
                        {d.liquidoEstimado > 0 && <span className="ml-1 text-[10px] text-[var(--fg-3)]" title="Sem comissão na API: líquido = oferta − taxa">≈</span>}
                      </Td>
                      <Td><Variacao pct={d.variacaoDiaAnterior} /></Td>
                      <Td className="tabular text-[var(--fg-3)]">{fmtBRL(d.acumulado)}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.juros ? fmtBRL(d.juros) : '—'}</Td>
                      <Td className="tabular">{d.estornos > 0 ? <span className="text-[var(--red)]">{d.estornos} · {fmtBRL(d.valorEstornado)}</span> : '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.recusadas || '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.boletos || '—'}</Td>
                    </Tr>
                  ))}
                </tbody>
              </DataTable>
            )}
          </SectionCard>
        </>
      )}
    </div>
  );
}

/** Seta + % vs. dia anterior — verde alta, vermelho queda. */
function Variacao({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-[11px] text-[var(--fg-4)]">—</span>;
  const subiu = pct >= 0;
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-semibold tabular ${subiu ? 'text-[var(--green)]' : 'text-[var(--red)]'}`}>
      <Icon name={subiu ? 'arrow-up' : 'arrow-down'} size={12} />
      {Math.abs(pct).toFixed(0)}%
    </span>
  );
}

// ─── Pessoas ────────────────────────────────────────────────────────────────
function VisaoPessoas({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const { dados, erro } = useCarga<PessoaHotmart[]>(() => repo.loadHotmartPessoas(familia), [familia]);
  const [filtro, setFiltro] = useState<SituacaoPessoa | 'avisos' | 'multi' | null>(null);
  const [periodo, setPeriodo] = useState<{ de: string; ate: string }>({ de: '', ate: '' });
  const [busca, setBusca] = useState('');
  const [aberta, setAberta] = useState<string | null>(null);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando situação das pessoas…" minHeight={200} />;

  const contagem = contarSituacoes(dados);
  const avisos = dados.filter((p) => p.aviso).length;
  const termo = busca.trim().toLowerCase();
  const termoDigitos = termo.replace(/\D/g, '');
  const lista = dados.filter((p) =>
    (filtro == null || (filtro === 'avisos' ? !!p.aviso : filtro === 'multi' ? p.emails.length > 1 : p.situacao === filtro)) &&
    (!periodo.de || (p.primeira_compra ?? '') >= periodo.de) &&
    (!periodo.ate || (p.primeira_compra ?? '9999') <= periodo.ate) &&
    (!termo || p.emails.some((e) => e.includes(termo)) || (p.nome ?? '').toLowerCase().includes(termo) ||
      (termoDigitos.length >= 4 && p.documentos.some((d) => d.includes(termoDigitos))) ||
      (p.origem ?? '').toLowerCase().includes(termo)));
  const multi = dados.filter((p) => p.emails.length > 1).length;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-1.5">
        <Chip ativo={filtro == null} onClick={() => setFiltro(null)}>Todas · {dados.length}</Chip>
        <Chip ativo={filtro === 'avisos'} onClick={() => setFiltro('avisos')} tom="danger">Avisos · {avisos}</Chip>
        <Chip ativo={filtro === 'multi'} onClick={() => setFiltro('multi')} tom="info">Mais de um e-mail · {multi}</Chip>
        {ORDEM_SITUACAO.map((s) => (
          <Chip key={s} ativo={filtro === s} onClick={() => setFiltro(s)} tom={TOM_SITUACAO[s]}>
            {ROTULO_SITUACAO[s]} · {contagem[s]}
          </Chip>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="search" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome, e-mail, CPF/CNPJ ou origem"
          aria-label="Buscar pessoa por nome, e-mail, documento ou origem"
          className="w-full max-w-sm rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-3 py-1.5 text-sm"
        />
        <span className="text-xs text-[var(--fg-3)]">1ª compra de</span>
        <input type="date" aria-label="Primeira compra a partir de" value={periodo.de}
          onChange={(e) => setPeriodo({ ...periodo, de: e.target.value })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
        <span className="text-xs text-[var(--fg-3)]">até</span>
        <input type="date" aria-label="Primeira compra até" value={periodo.ate}
          onChange={(e) => setPeriodo({ ...periodo, ate: e.target.value })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
        <button type="button" onClick={() => exportarPessoasCsv(lista)}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          Exportar CSV ({lista.length})
        </button>
      </div>
      <SectionCard title={`${lista.length} pessoa(s)`} subtitle="Clique numa linha para ver tudo o que a pessoa comprou e tentou comprar na Hotmart.">
        {!lista.length ? <EmptyState title="Ninguém neste recorte" /> : (
          <DataTable minWidth={1000}>
            <Thead>
              <Th>Pessoa</Th><Th>Situação</Th><Th>Origem e caminho</Th><Th>Pago (bruto)</Th><Th>Líquido</Th><Th>Último pagamento</Th>
              <Th>Atrasado (120 dias)</Th><Th>Tentativas</Th><Th>Board · GPS</Th>
            </Thead>
            <tbody>
              {lista.slice(0, 500).map((p) => (
                <LinhaPessoa key={p.pessoa_chave} p={p} aberta={aberta === p.pessoa_chave}
                  onToggle={() => setAberta(aberta === p.pessoa_chave ? null : p.pessoa_chave)} repo={repo} />
              ))}
            </tbody>
          </DataTable>
        )}
        {lista.length > 500 && <p className="mt-2 text-xs text-[var(--fg-3)]">Mostrando 500 de {lista.length}. Use a busca ou um filtro para ver o resto.</p>}
      </SectionCard>
    </div>
  );
}

function Chip({ ativo, onClick, children, tom = 'neutral' }: { ativo: boolean; onClick: () => void; children: React.ReactNode; tom?: Tone }) {
  return (
    <button type="button" aria-pressed={ativo} onClick={onClick}
      className={`rounded-[var(--r-sm)] border px-2 py-1 text-xs ${ativo ? 'border-[var(--accent)] font-semibold text-[var(--fg)] bg-[var(--surface-3)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`}>
      <Badge tone={tom}>{children}</Badge>
    </button>
  );
}

function LinhaPessoa({ p, aberta, onToggle, repo }: { p: PessoaHotmart; aberta: boolean; onToggle: () => void; repo: FinanceiroRepository }) {
  const doc = p.documentos[0];
  return (
    <>
      <Tr onClick={onToggle} className="cursor-pointer">
        <Td>
          <div className="font-medium text-[var(--fg)]">{p.nome ?? '—'}</div>
          {p.emails.map((e) => <div key={e} className="text-[11px] text-[var(--fg-3)] break-all">{e}</div>)}
          {(doc || p.cidade) && (
            <div className="text-[11px] text-[var(--fg-4)]">
              {doc ? rotuloDocumento(doc) : ''}{doc && p.cidade ? ' · ' : ''}{p.cidade ?? ''}
            </div>
          )}
          {p.aviso && <div className="mt-0.5 text-[11px] font-medium text-[var(--red)]"><Icon name="alert" size={11} className="mr-1 inline" />{p.aviso}</div>}
        </Td>
        <Td><Badge tone={TOM_SITUACAO[p.situacao]}>{ROTULO_SITUACAO[p.situacao]}</Badge></Td>
        <Td className="text-[11px]">
          <div className="text-[var(--fg-2)]">{p.primeira_compra ? fmtData(p.primeira_compra) : '—'}{p.primeira_oferta ? ` · ${p.primeira_oferta}` : ''}</div>
          {p.origem && <div className="text-[var(--fg-3)] break-all">{p.origem}</div>}
          {p.fluxo && <div className="text-[var(--fg-3)]">{p.fluxo}</div>}
        </Td>
        <Td className="tabular">{fmtBRL(Number(p.valor_pago))}<div className="text-[11px] text-[var(--fg-3)]">{p.compras_pagas} pagamento(s)</div></Td>
        <Td className="tabular text-[var(--green)]">{fmtBRL(Number(p.liquido))}</Td>
        <Td className="tabular">{p.ultima_compra_paga ? fmtData(p.ultima_compra_paga) : '—'}
          {p.acesso_hotmart_ate && <div className="text-[11px] text-[var(--fg-3)]">+1 ano: {fmtData(p.acesso_hotmart_ate)}</div>}</Td>
        <Td className="tabular">
          {p.parcelas_atrasadas > 0 ? <span className="text-[var(--red)]">{p.parcelas_atrasadas} · {fmtBRL(Number(p.valor_atrasado))}</span> : '—'}
          {p.atrasadas_antigas > 0 && <div className="text-[11px] text-[var(--fg-3)]" title="Parcelas vencidas há mais de 120 dias (em geral assinatura já cancelada)">antigas: {p.atrasadas_antigas} · {fmtBRL(Number(p.valor_atrasado_antigo))}</div>}
        </Td>
        <Td className="tabular text-[var(--fg-3)]">{p.recusadas > 0 ? `${p.recusadas} recusa(s)` : '—'}{p.em_aberto > 0 ? ` · ${p.em_aberto} boleto(s)` : ''}</Td>
        <Td className="text-[11px]">
          {p.cards > 0
            ? <div>{p.cards} card(s){p.status_card ? ` · ${p.status_card}` : ''}{p.canal_card ? <div className="text-[var(--fg-3)]">{p.canal_card}</div> : null}</div>
            : <span className="text-[var(--fg-4)]">sem card</span>}
          <div className="mt-0.5 flex flex-wrap gap-1">
            {p.turma && <Badge>{p.turma}</Badge>}
            {p.no_gps && <Badge tone="info">No GPS</Badge>}
          </div>
        </Td>
      </Tr>
      {aberta && (
        <tr><td colSpan={9} className="bg-[var(--surface-2)] px-4 py-3"><ExtratoHotmart email={p.emails[0]} repo={repo} /></td></tr>
      )}
    </>
  );
}

/** CSV da lista filtrada (separador ; para abrir direto no Excel em pt-BR). */
function exportarPessoasCsv(lista: PessoaHotmart[]) {
  const col: [string, (p: PessoaHotmart) => unknown][] = [
    ['Nome', (p) => p.nome], ['E-mails', (p) => p.emails.join(' | ')], ['Documentos', (p) => p.documentos.join(' | ')],
    ['Telefone', (p) => p.telefone], ['Cidade', (p) => p.cidade], ['Situação', (p) => ROTULO_SITUACAO[p.situacao]],
    ['Aviso', (p) => p.aviso], ['1ª compra', (p) => p.primeira_compra], ['1ª oferta', (p) => p.primeira_oferta],
    ['Origem (sck)', (p) => p.origem], ['Caminho', (p) => p.fluxo], ['Pagamentos', (p) => p.compras_pagas],
    ['Pago bruto', (p) => p.valor_pago], ['Líquido', (p) => p.liquido], ['Último pagamento', (p) => p.ultima_compra_paga],
    ['Acesso até (+1 ano)', (p) => p.acesso_hotmart_ate], ['Atrasado 120d', (p) => p.valor_atrasado],
    ['Atrasado antigo', (p) => p.valor_atrasado_antigo], ['Reembolsado', (p) => p.valor_estornado],
    ['Recusas', (p) => p.recusadas], ['Cards', (p) => p.cards], ['Status card', (p) => p.status_card],
    ['Canal', (p) => p.canal_card], ['Turma', (p) => p.turma], ['No GPS', (p) => (p.no_gps ? 'sim' : 'não')],
  ];
  const linhas = [col.map(([c]) => c).join(';'), ...lista.map((p) => col.map(([, f]) => celulaCsv(f(p))).join(';'))];
  const blob = new Blob(['﻿' + linhas.join('\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `hotmart-pessoas-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

/** Extrato completo de uma pessoa na Hotmart — reusado na ficha do board. */
export function ExtratoHotmart({ email, repo }: { email: string; repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<TransacaoHotmart[]>(() => repo.loadHotmartExtrato(email), [email]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando histórico da Hotmart…" minHeight={80} />;
  if (!dados.length) return <p className="text-xs text-[var(--fg-3)]">Nenhuma transação na Hotmart com este e-mail.</p>;
  return (
    <DataTable minWidth={760}>
      <Thead><Th>Pedido</Th><Th>E-mail</Th><Th>Situação</Th><Th>Oferta</Th><Th>Bruto</Th><Th>Cobrado</Th><Th>Líquido</Th><Th>Pagamento</Th><Th>Origem</Th></Thead>
      <tbody>
        {dados.map((t) => (
          <Tr key={t.transacao}>
            <Td className="tabular">{t.pedido_em ? fmtDataHora(t.pedido_em) : '—'}<div className="text-[10px] text-[var(--fg-4)]">{t.transacao}</div></Td>
            <Td className="text-[11px] text-[var(--fg-3)] break-all">{t.email}</Td>
            <Td><Badge tone={TOM_GRUPO[t.grupo]}>{ROTULO_GRUPO[t.grupo]}</Badge></Td>
            <Td className="text-xs">{t.oferta_codigo ?? '—'}<div className="text-[10px] text-[var(--fg-3)]">{t.produto}</div></Td>
            <Td className="tabular">{fmtBRL(Number(t.valor_oferta ?? 0))}</Td>
            <Td className="tabular text-[var(--fg-3)]">{fmtBRL(Number(t.cobrado ?? 0))}</Td>
            <Td className="tabular text-[var(--green)]">{t.liquido != null ? fmtBRL(Number(t.liquido)) : '—'}{t.liquido_estimado && ' ≈'}</Td>
            <Td className="text-xs">{t.metodo ?? '—'}{t.parcelas && t.parcelas > 1 ? ` · ${t.parcelas}x` : ''}{t.recorrencia ? ` · parcela ${t.recorrencia}` : ''}</Td>
            <Td className="text-[11px] text-[var(--fg-3)] break-all">{t.origem_sck ?? '—'}</Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}

// ─── Ofertas ────────────────────────────────────────────────────────────────
function VisaoOfertas({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const { dados, erro } = useCarga<OfertaHotmart[]>(() => repo.loadHotmartOfertas(familia), [familia]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando ofertas…" minHeight={200} />;
  const fora = dados.filter((o) => !o.no_catalogo && o.vendas_pagas > 0).length;
  return (
    <SectionCard title={`${dados.length} oferta(s) com movimento na Hotmart`}
      subtitle={fora ? `${fora} oferta(s) com venda paga estão FORA do catálogo — venda nelas não vira card no board.` : 'Todas as ofertas com venda paga estão no catálogo.'}>
      <DataTable minWidth={1000}>
        <Thead><Th>Oferta</Th><Th>Produto</Th><Th>Tipo</Th><Th>Preço</Th><Th>Pagas</Th><Th>Bruto</Th><Th>Líquido</Th><Th>Reemb.</Th><Th>Recusas</Th><Th>Última venda</Th><Th>Catálogo</Th></Thead>
        <tbody>
          {dados.map((o) => (
            <Tr key={o.oferta_codigo}>
              <Td className="font-mono text-xs">{o.oferta_codigo}{o.nome_comercial && <div className="font-sans text-[11px] text-[var(--fg-3)]">{o.nome_comercial}</div>}</Td>
              <Td className="text-xs">{o.produto}<div className="text-[10px] text-[var(--fg-3)]">{o.papel_produto}</div></Td>
              <Td className="text-[11px] text-[var(--fg-3)]">{o.modo_pagamento ?? '—'}</Td>
              <Td className="tabular">{o.preco_oferta != null ? fmtBRL(Number(o.preco_oferta)) : '—'}</Td>
              <Td className="tabular">{o.vendas_pagas}</Td>
              <Td className="tabular">{fmtBRL(Number(o.receita_oferta))}</Td>
              <Td className="tabular text-[var(--green)]">{fmtBRL(Number(o.receita_liquida))}</Td>
              <Td className="tabular">{o.estornos || '—'}</Td>
              <Td className="tabular text-[var(--fg-3)]">{o.recusadas || '—'}</Td>
              <Td className="tabular">{o.ultima_venda ? fmtData(o.ultima_venda) : '—'}</Td>
              <Td>{o.no_catalogo
                ? <Badge tone="success">{o.categoria_catalogo ?? 'sem categoria'}{o.papel_catalogo ? ` · ${o.papel_catalogo}` : ''}</Badge>
                : <Badge tone={o.vendas_pagas > 0 ? 'danger' : 'neutral'}>fora do catálogo</Badge>}</Td>
            </Tr>
          ))}
        </tbody>
      </DataTable>
    </SectionCard>
  );
}

// ─── Conciliação ────────────────────────────────────────────────────────────
const ROTULO_DIVERGENCIA: Record<DivergenciaHotmart['tipo'], string> = {
  falta_no_banco: 'Pago na Hotmart, ausente no banco',
  produto_sem_webhook: 'Produto sem webhook',
  status_diferente: 'Status diferente',
  valor_diferente: 'Valor diferente',
};

function VisaoConciliacao({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const { dados, erro } = useCarga<DivergenciaHotmart[]>(() => repo.loadHotmartConciliacao(familia), [familia]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Conferindo Hotmart × banco…" minHeight={200} />;
  return (
    <SectionCard title={dados.length ? `${dados.length} divergência(s)` : 'Hotmart e banco batem'}
      subtitle="Compara o espelho da Hotmart com o que o webhook gravou em public.compras. Nada aqui é corrigido sozinho.">
      {!dados.length ? <EmptyState title="Nenhuma divergência" icon="check" /> : (
        <DataTable minWidth={900}>
          <Thead><Th>Tipo</Th><Th>Transação</Th><Th>E-mail</Th><Th>Hotmart</Th><Th>Banco</Th><Th>Pedido</Th><Th>Detalhe</Th></Thead>
          <tbody>
            {dados.map((d, i) => (
              <Tr key={`${d.tipo}-${d.transacao ?? i}`}>
                <Td><Badge tone={d.tipo === 'falta_no_banco' || d.tipo === 'produto_sem_webhook' ? 'danger' : 'warning'}>{ROTULO_DIVERGENCIA[d.tipo]}</Badge></Td>
                <Td className="font-mono text-xs">{d.transacao ?? '—'}</Td>
                <Td className="text-xs break-all">{d.email ?? '—'}</Td>
                <Td className="text-xs">{d.status_hotmart ?? ''}{d.valor_hotmart != null ? ` · ${fmtBRL(Number(d.valor_hotmart))}` : ''}</Td>
                <Td className="text-xs">{d.status_banco ?? ''}{d.valor_banco != null ? ` · ${fmtBRL(Number(d.valor_banco))}` : ''}</Td>
                <Td className="tabular text-xs">{d.pedido_em ? fmtData(d.pedido_em) : '—'}</Td>
                <Td className="text-xs text-[var(--fg-2)]">{d.detalhe}</Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
    </SectionCard>
  );
}

// ─── Mesma pessoa? ──────────────────────────────────────────────────────────
// E-mail, CPF/CNPJ e conta Hotmart iguais JÁ juntam a pessoa sozinhos (componente
// conexo). Aqui ficam só os casos que precisam de olho humano: telefone ou nome
// igual em pessoas diferentes, e documento compartilhado (escritório/contador).
function VisaoIdentidade({ repo }: { repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<IdentidadeRevisao[]>(() => repo.loadHotmartIdentidade(), ['identidade']);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando revisão de identidade…" minHeight={200} />;
  const sug = dados.filter((d) => d.tipo === 'sugestao');
  const rev = dados.filter((d) => d.tipo === 'revisao');
  const lista = (v: string[] | null) => (v?.length ? v.join(', ') : '—');
  return (
    <div className="space-y-4">
      <SectionCard title={`${sug.length} par(es) que podem ser a mesma pessoa`}
        subtitle="Mesmo telefone, mesmo nome completo ou mesmo CPF digitado numa tentativa de compra que não foi paga. Não foram juntados: confira antes.">
        {!sug.length ? <EmptyState title="Nenhum par para conferir" icon="check" /> : (
          <DataTable minWidth={900}>
            <Thead><Th>Motivo</Th><Th>Pessoa A</Th><Th>Pessoa B</Th><Th>Pago A</Th><Th>Pago B</Th></Thead>
            <tbody>
              {sug.map((d) => (
                <Tr key={`${d.motivo}-${d.pessoa_a}-${d.pessoa_b}`}>
                  <Td>
                    <Badge tone="warning">{MOTIVO_SUGESTAO[d.motivo] ?? d.motivo}</Badge>
                    <div className="text-[10px] text-[var(--fg-4)]">
                      {d.motivo !== 'mesmo_nome' && d.evidencia ? `···${d.evidencia.slice(-4)}` : d.evidencia}
                    </div>
                  </Td>
                  <Td className="text-xs"><div className="font-medium">{lista(d.nomes_a)}</div><div className="text-[var(--fg-3)] break-all">{lista(d.emails_a)}</div></Td>
                  <Td className="text-xs"><div className="font-medium">{lista(d.nomes_b)}</div><div className="text-[var(--fg-3)] break-all">{lista(d.emails_b)}</div></Td>
                  <Td className="tabular text-xs">{fmtBRL(Number(d.pago_a ?? 0))}</Td>
                  <Td className="tabular text-xs">{fmtBRL(Number(d.pago_b ?? 0))}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
      <SectionCard title={`${rev.length} documento(s) em revisão`}
        subtitle="Documento compartilhado por pessoas diferentes ou ligado a muitos e-mails (escritório, contador). Não junta ninguém.">
        {!rev.length ? <EmptyState title="Nada em revisão" icon="check" /> : (
          <DataTable minWidth={600}>
            <Thead><Th>Documento</Th><Th>Motivo</Th></Thead>
            <tbody>
              {rev.map((d) => (
                <Tr key={d.pessoa_a}><Td className="font-mono text-xs">{d.evidencia}</Td><Td className="text-xs">{d.motivo}</Td></Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}
