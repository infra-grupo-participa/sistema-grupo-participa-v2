'use client';

// Visão "Pessoas" da Hotmart — situação de cada comprador + extrato com o que
// ele TENTOU comprar. Extraído de ui/Hotmart.tsx em 27/09/2026. Sem tela
// própria ainda: será pendurada em Relatórios por outro agente.
import { useState } from 'react';
import { Badge, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import {
  celulaCsv, contarSituacoes, ORDEM_SITUACAO, resumirAdimplencia, ROTULO_SITUACAO, rotuloCategorias, rotuloDocumento, rotuloMetodo,
  type FamiliaHotmart, type LinhaAdimplencia, type PessoaHotmart, type SituacaoPessoa,
} from '../../domain/hotmart';
import { Chip, Erro, useCarga } from './comum';
import { carregarPessoasHotmart } from '../../application/carregar-pessoas';
import { ExtratoHotmart } from './ExtratoHotmart';
import { BotaoExportarPdf } from '@/shared/ui/pdf/BotaoExportarPdf';
import { chamadasProtocoloFinanceiro } from '../pdf/protocolo';
import { NIVEIS_RELATORIO, rascunhoPessoas, recortePessoas } from '../pdf/documentos';

const TOM_SITUACAO: Record<SituacaoPessoa, Tone> = {
  devendo: 'danger', negociacao_cancelamento: 'danger', em_pagamento: 'warning', boleto_em_aberto: 'warning',
  reembolsado: 'neutral', ativo: 'success', inadimplencia_antiga: 'warning', vencido: 'neutral', so_tentou: 'info',
};

/** "até 12x · 3 parceladas" — null (nenhuma venda parcelada) mostra travessão. */
function rotuloParcelamento(p: PessoaHotmart): string {
  if (p.parcelas_max == null) return '—';
  const base = `até ${p.parcelas_max}x`;
  return p.vendas_parceladas > 0 ? `${base} · ${p.vendas_parceladas} parcelada(s)` : base;
}

/**
 * `recorte="sem_card"` (Board, 27/09): mostra antes a adimplência de TODO mundo que pagou na família e,
 * na tabela, só quem pagou na Hotmart e não tem card no board ("pode exibir elas, mesmo sem oferta" — João).
 */
export function HotmartPessoas({ repo, familia, recorte }: { repo: FinanceiroRepository; familia: FamiliaHotmart; recorte?: 'sem_card' }) {
  const { dados: todos, erro } = useCarga<PessoaHotmart[]>(() => carregarPessoasHotmart(repo, familia), [familia]);
  const dados = todos && recorte === 'sem_card' ? todos.filter((p) => p.cards === 0 && p.compras_pagas > 0) : todos;
  const [filtro, setFiltro] = useState<SituacaoPessoa | 'avisos' | 'multi' | null>(null);
  const [periodo, setPeriodo] = useState<{ de: string; ate: string }>({ de: '', ate: '' });
  const [busca, setBusca] = useState('');
  const [aberta, setAberta] = useState<string | null>(null);

  if (erro) return <Erro msg={erro} />;
  if (!dados || !todos) return <Loading label="Carregando situação das pessoas…" minHeight={200} />;

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
  // Coprodução só existe em parte das famílias (Aurum antigo) — coluna aparece
  // só quando há algo a mostrar, mesmo padrão de KpiCard/coluna em FaturamentoDiario.
  const temCoproducao = lista.some((p) => Number(p.coproducao ?? 0) > 0);

  return (
    <div className="space-y-3">
      {recorte === 'sem_card' && <ResumoAdimplencia linhas={resumirAdimplencia(todos)} />}
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
        <BotaoExportarPdf
          montar={() => rascunhoPessoas(lista, recortePessoas({
            familia, filtro, de: periodo.de, ate: periodo.ate, busca, semCard: recorte === 'sem_card',
          }))}
          niveis={NIVEIS_RELATORIO.pessoas}
          chamadas={chamadasProtocoloFinanceiro()}
        />
      </div>
      <SectionCard
        title={recorte === 'sem_card' ? `Pagaram na Hotmart e não estão no board · ${lista.length}` : `${lista.length} pessoa(s)`}
      >
        {!lista.length ? <EmptyState title="Ninguém neste recorte" /> : (
          <DataTable minWidth={1000}>
            <Thead>
              <Th>Pessoa</Th><Th>Situação</Th><Th>Origem e caminho</Th><Th>Pago (bruto)</Th><Th>Líquido</Th>
              <Th>Cliente pagou (c/ juros)</Th><Th>Juros</Th><Th>Taxa Hotmart</Th>
              {temCoproducao && <Th>Coprodução</Th>}
              <Th>Parcelamento</Th><Th>Forma</Th>
              <Th>Último pagamento</Th><Th>Atrasado (120 dias)</Th><Th>Tentativas</Th><Th>Board · GPS</Th>
            </Thead>
            <tbody>
              {lista.slice(0, 500).map((p) => (
                <LinhaPessoa key={p.pessoa_chave} p={p} aberta={aberta === p.pessoa_chave} temCoproducao={temCoproducao}
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

function LinhaPessoa({ p, aberta, temCoproducao, onToggle, repo }: {
  p: PessoaHotmart; aberta: boolean; temCoproducao: boolean; onToggle: () => void; repo: FinanceiroRepository;
}) {
  const doc = p.documentos[0];
  const colSpan = 13 + (temCoproducao ? 1 : 0);
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
          {p.fluxo && <div className="text-[var(--fg-3)]">{rotuloCategorias(p.fluxo)}</div>}
        </Td>
        <Td className="tabular">{fmtBRL(Number(p.valor_pago))}<div className="text-[11px] text-[var(--fg-3)]">{p.compras_pagas} pagamento(s)</div></Td>
        <Td className="tabular text-[var(--green)]">{fmtBRL(Number(p.liquido))}</Td>
        <Td className="tabular text-[var(--fg-2)]">{fmtBRL(Number(p.cobrado_cliente ?? 0))}</Td>
        <Td className="tabular text-[var(--fg-3)]">{Number(p.juros ?? 0) > 0 ? fmtBRL(Number(p.juros)) : '—'}</Td>
        <Td className="tabular text-[var(--fg-3)]">{fmtBRL(Number(p.taxa_hotmart ?? 0))}</Td>
        {temCoproducao && <Td className="tabular text-[var(--fg-3)]">{Number(p.coproducao ?? 0) > 0 ? fmtBRL(Number(p.coproducao)) : '—'}</Td>}
        <Td className="text-[11px] text-[var(--fg-2)]">{rotuloParcelamento(p)}</Td>
        <Td className="text-[11px] text-[var(--fg-2)]">{rotuloMetodo(p.forma_pagamento_principal)}</Td>
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
        <tr><td colSpan={colSpan} className="bg-[var(--surface-2)] px-4 py-3"><ExtratoHotmart email={p.emails[0]} repo={repo} /></td></tr>
      )}
    </>
  );
}

/** CSV da lista filtrada (separador ; para abrir direto no Excel em pt-BR). */
function exportarPessoasCsv(lista: PessoaHotmart[]) {
  const temCoproducao = lista.some((p) => Number(p.coproducao ?? 0) > 0);
  const col: [string, (p: PessoaHotmart) => unknown][] = [
    ['Nome', (p) => p.nome], ['E-mails', (p) => p.emails.join(' | ')], ['Documentos', (p) => p.documentos.join(' | ')],
    ['Telefone', (p) => p.telefone], ['Cidade', (p) => p.cidade], ['Situação', (p) => ROTULO_SITUACAO[p.situacao]],
    ['Aviso', (p) => p.aviso], ['1ª compra', (p) => p.primeira_compra], ['1ª oferta', (p) => p.primeira_oferta],
    ['Origem (sck)', (p) => p.origem], ['Caminho', (p) => rotuloCategorias(p.fluxo)], ['Pagamentos', (p) => p.compras_pagas],
    ['Pago bruto', (p) => p.valor_pago], ['Líquido', (p) => p.liquido],
    ['Cliente pagou (c/ juros)', (p) => Number(p.cobrado_cliente ?? 0)],
    ['Juros', (p) => Number(p.juros ?? 0)],
    ['Taxa Hotmart', (p) => Number(p.taxa_hotmart ?? 0)],
    ...(temCoproducao ? [['Coprodução', (p: PessoaHotmart) => Number(p.coproducao ?? 0)] as [string, (p: PessoaHotmart) => unknown]] : []),
    ['Parcelamento', (p) => rotuloParcelamento(p)],
    ['Forma', (p) => rotuloMetodo(p.forma_pagamento_principal)],
    ['Último pagamento', (p) => p.ultima_compra_paga],
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

/** Adimplência de quem pagou (com e sem card). Números de Pessoas — dívida da Hotmart por parcela. */
function ResumoAdimplencia({ linhas }: { linhas: LinhaAdimplencia[] }) {
  const total = linhas.reduce((s, l) => s + l.pessoas, 0);
  const tom: Record<LinhaAdimplencia['chave'], string> = {
    em_dia: 'text-[var(--green)]', boleto: 'text-[var(--yellow)]', devendo: 'text-[var(--red)]', antiga: 'text-[var(--yellow)]',
    cancelamento: 'text-[var(--red)]', reembolsado: 'text-[var(--fg-3)]', vencido: 'text-[var(--fg-3)]',
  };
  return (
    <SectionCard
      title={`Está todo mundo pagando em dia? · ${total} pessoa(s) que pagaram`}
    >
      <div className="grid gap-2 [grid-template-columns:repeat(auto-fill,minmax(170px,1fr))]">
        {linhas.map((l) => (
          <div key={l.chave} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
            <div className="text-[11px] text-[var(--fg-3)]">{l.rotulo}</div>
            <div className={`tabular text-lg font-semibold ${tom[l.chave]}`}>{l.pessoas}</div>
            <div className="text-[11px] text-[var(--fg-3)]">
              {l.valor > 0 ? `${fmtBRL(l.valor)} · ` : ''}{l.comCard} com card
            </div>
          </div>
        ))}
      </div>
    </SectionCard>
  );
}
