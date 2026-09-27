'use client';

// Calculadora de Pro Rata — aba própria do financeiro (não é mais um dos
// relatórios de ui/Relatorios.tsx, por pedido do João em 27/09/2026). Lista
// geral de quem tem acesso ao HM + crédito de migração para o Programa;
// clicar numa pessoa abre o diagnóstico completo (ProrataDiagnostico.tsx).
import { useState } from 'react';
import { DataTable, EmptyState, KpiCard, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { celulaCsv, type ProrataHM as LinhaProrataHM } from '../../domain/hotmart';
import { Chip, Erro, useCarga } from './comum';
import { ProrataDiagnostico } from './ProrataDiagnostico';
import { carregarProrataHM } from '../../application/carregar-prorata';
import { hojeSaoPaulo, VALOR_PROGRAMA_HM } from '../../domain/prorata-hm';

type Filtro = 'credito' | 'vence60' | 'vencido' | 'gps' | 'sem_hotmart' | null;

/** Diferença em dias de calendário entre `iso` e `hojeISO` (ambos 'YYYY-MM-DD...'). Positivo = futuro. */
function diffDias(iso: string, hojeISO: string): number {
  const ms = (s: string) => {
    const [y, m, d] = s.slice(0, 10).split('-').map(Number);
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((ms(iso) - ms(hojeISO)) / 86_400_000);
}

export function ProrataHM({ repo }: { repo: FinanceiroRepository }) {
  // mesma carga (e mesmo cache de 10 min) da ficha do board: uma consulta, não duas
  const { dados, erro } = useCarga<LinhaProrataHM[]>(() => carregarProrataHM(repo), []);
  const [busca, setBusca] = useState('');
  const [filtro, setFiltro] = useState<Filtro>(null);
  const [abertoEmail, setAbertoEmail] = useState<string | null>(null);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Calculando o pro rata do HM…" minHeight={200} />;

  const hojeISO = hojeSaoPaulo();

  const comCredito = dados.filter((p) => Number(p.credito) > 0).length;
  const somaCreditos = dados.reduce((s, p) => s + Number(p.credito), 0);
  const qtdVence60 = dados.filter((p) => { const d = diffDias(p.vencimento, hojeISO); return d >= 0 && d <= 60; }).length;
  const qtdVencido = dados.filter((p) => p.meses_restantes === 0 && diffDias(p.vencimento, hojeISO) < 0).length;
  const qtdGps = dados.filter((p) => p.no_gps).length;
  // aluno da turma sem nenhuma venda de HM na Hotmart (pagou por fora ou com e-mail que o espelho não liga) — 20260928i
  const qtdSemHotmart = dados.filter((p) => p.ultimo_pagamento == null).length;

  const termo = busca.trim().toLowerCase();
  const lista = dados
    .filter((p) => {
      if (filtro === 'credito') return Number(p.credito) > 0;
      if (filtro === 'vence60') { const d = diffDias(p.vencimento, hojeISO); return d >= 0 && d <= 60; }
      if (filtro === 'vencido') return p.meses_restantes === 0 && diffDias(p.vencimento, hojeISO) < 0;
      if (filtro === 'gps') return p.no_gps;
      if (filtro === 'sem_hotmart') return p.ultimo_pagamento == null;
      return true;
    })
    .filter((p) => !termo ||
      (p.nome ?? '').toLowerCase().includes(termo) ||
      (p.email ?? '').toLowerCase().includes(termo) ||
      (p.turma ?? '').toLowerCase().includes(termo))
    // acesso vigente primeiro (vence antes = mais urgente); vencidos no fim, o mais recente antes
    .sort((a, b) => {
      const va = a.vencimento >= hojeISO, vb = b.vencimento >= hojeISO;
      if (va !== vb) return va ? -1 : 1;
      return va ? a.vencimento.localeCompare(b.vencimento) : b.vencimento.localeCompare(a.vencimento);
    });

  return (
    <div className="space-y-4">
      <SectionCard title="Como o crédito é calculado">
        <p className="text-sm text-[var(--fg-2)] leading-relaxed">
          Crédito = o que a pessoa pagou no HM no ciclo atual × meses cheios que faltam do acesso ÷ 12.
          Valor a pagar = {fmtBRLc(VALOR_PROGRAMA_HM)} − crédito. O vencimento vem da turma. Estão aqui todos os alunos
          de turma com vencimento — quem não tem pagamento de HM na Hotmart aparece com crédito zero e o aviso na linha.
        </p>
      </SectionCard>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
        <KpiCard label="Pessoas" value={String(dados.length)} bar="accent" />
        <KpiCard label="Com crédito" value={String(comCredito)} bar="green" />
        <KpiCard label="Soma dos créditos" value={fmtBRLc(somaCreditos)} bar="purple" />
      </div>

      <div className="flex flex-wrap gap-1.5">
        <Chip ativo={filtro == null} onClick={() => setFiltro(null)}>Todos · {dados.length}</Chip>
        <Chip ativo={filtro === 'credito'} onClick={() => setFiltro('credito')} tom="success">Com crédito · {comCredito}</Chip>
        <Chip ativo={filtro === 'vence60'} onClick={() => setFiltro('vence60')} tom="warning">Vence em até 60 dias · {qtdVence60}</Chip>
        <Chip ativo={filtro === 'vencido'} onClick={() => setFiltro('vencido')} tom="danger">Já vencido · {qtdVencido}</Chip>
        <Chip ativo={filtro === 'gps'} onClick={() => setFiltro('gps')} tom="info">No GPS · {qtdGps}</Chip>
        <Chip ativo={filtro === 'sem_hotmart'} onClick={() => setFiltro('sem_hotmart')} tom="warning">Sem pagamento de HM na Hotmart · {qtdSemHotmart}</Chip>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <input
          type="search" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome, e-mail ou turma"
          aria-label="Buscar pessoa por nome, e-mail ou turma"
          className="w-full max-w-sm rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-3 py-1.5 text-sm"
        />
        <button type="button" onClick={() => exportarProrataCsv(lista)}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          Exportar CSV ({lista.length})
        </button>
      </div>

      <SectionCard title={`${lista.length} pessoa(s)`} subtitle="Clique numa pessoa para ver a conta: quanto pagou, quanto vira crédito e quanto tem que pagar.">
        {!lista.length ? <EmptyState title="Ninguém neste recorte" /> : (
          <DataTable minWidth={960}>
            <Thead>
              <Th>Pessoa</Th><Th>Turma</Th><Th>Vence em</Th><Th>Meses cheios restantes</Th>
              <Th>Pago no ciclo</Th><Th>Crédito</Th><Th>Valor a pagar</Th><Th>Card no board</Th>
            </Thead>
            <tbody>
              {lista.map((p) => (
                <Tr key={p.pessoa_chave} onClick={() => p.email && setAbertoEmail(p.email)}>
                  <Td>
                    <div className="font-medium text-[var(--fg)]">{p.nome ?? '—'}</div>
                    <div className="text-[11px] text-[var(--fg-3)] break-all">{p.email ?? '—'}</div>
                  </Td>
                  <Td>{p.turma ?? '—'}</Td>
                  <Td className="tabular">{fmtData(p.vencimento)}</Td>
                  <Td className="tabular">{p.meses_restantes}</Td>
                  <Td className="tabular">
                    {fmtBRLc(Number(p.pago_no_ciclo))}
                    {p.formas && <div className="text-[11px] text-[var(--fg-3)]">{p.formas}</div>}
                    {p.ultimo_pagamento == null && <div className="whitespace-nowrap text-[11px] text-[var(--yellow)]" title="Sem pagamento de HM na Hotmart neste cadastro — confirmar com a Isabela se pagou por fora ou com outro e-mail">sem pagamento na Hotmart</div>}
                  </Td>
                  <Td className="tabular">{fmtBRLc(Number(p.credito))}</Td>
                  <Td className="tabular font-semibold text-[var(--fg)]">{fmtBRLc(Number(p.diferenca))}</Td>
                  <Td>{p.tem_card ? 'Sim' : 'Não'}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>

      {abertoEmail && (
        <ProrataDiagnostico repo={repo} email={abertoEmail} onClose={() => setAbertoEmail(null)} />
      )}
    </div>
  );
}

/** CSV da lista filtrada (separador ; para abrir direto no Excel em pt-BR). */
function exportarProrataCsv(lista: LinhaProrataHM[]) {
  const col: [string, (p: LinhaProrataHM) => unknown][] = [
    ['Nome', (p) => p.nome], ['E-mail', (p) => p.email], ['Turma', (p) => p.turma],
    ['Vencimento', (p) => p.vencimento], ['Meses restantes', (p) => p.meses_restantes],
    ['Pago no ciclo', (p) => Number(p.pago_no_ciclo)], ['Pagamentos no ciclo', (p) => p.pagamentos_no_ciclo],
    ['Formas', (p) => p.formas], ['Crédito', (p) => Number(p.credito)], ['Valor a pagar', (p) => Number(p.diferenca)],
    ['Último pagamento', (p) => p.ultimo_pagamento], ['Card no board', (p) => (p.tem_card ? 'sim' : 'não')],
    ['No GPS', (p) => (p.no_gps ? 'sim' : 'não')],
  ];
  const linhas = [col.map(([c]) => c).join(';'), ...lista.map((p) => col.map(([, f]) => celulaCsv(f(p))).join(';'))];
  const blob = new Blob(['﻿' + linhas.join('\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `prorata-hm-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}
