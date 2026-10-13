'use client';

import { useState } from 'react';
import { Card, DataTable, EmptyState, KpiCard, SectionCard, Tabs, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { Modal } from '@/shared/ui/components/Modal';
import { conversaoSessaoViabilidade } from '../domain/sessao-viabilidade';
import type { MetricaAtm } from '../domain/dashboard';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });

function formatarMetrica(metrica: MetricaAtm) {
  return metrica.semDado ? 'Sem dado' : inteiro.format(metrica.valor);
}

export function SessaoViabilidade({ vendas, podeVerContato, isMaster }: {
  vendas: MetricaAtm;
  podeVerContato: boolean;
  isMaster: boolean;
}) {
  const [aberto, setAberto] = useState(false);
  const [aba, setAba] = useState('tabela');
  const preCheckoutsUnicos: number | null = null;
  const conversao = conversaoSessaoViabilidade(vendas, preCheckoutsUnicos);

  return <>
    <SectionCard title="Sessão de Viabilidade" subtitle="Pré-checkouts únicos por e-mail, vendas e conversão. A lista será ligada à fonte própria da sessão.">
      <div className="grid gap-3 sm:grid-cols-3">
        <button type="button" onClick={() => setAberto(true)} className="text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] rounded-[var(--r-lg)]">
          <KpiCard label="Pré-checkouts únicos" value="Sem dado" hint="sem dado ainda · fonte não ligada" />
        </button>
        <button type="button" onClick={() => setAberto(true)} className="text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] rounded-[var(--r-lg)]">
          <KpiCard label="Total de vendas" value={formatarMetrica(vendas)} hint={vendas.semDado ? 'sem dado ainda · oferta não cadastrada' : 'dados_atm_resumo'} bar="green" />
        </button>
        <button type="button" onClick={() => setAberto(true)} className="text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] rounded-[var(--r-lg)]">
          <KpiCard label="Conversão do pré-checkout" value={conversao.semDado ? 'Sem dado' : `${conversao.valor.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`} hint="vendas ÷ pré-checkouts únicos" />
        </button>
      </div>
      {!podeVerContato && <p className="mt-3 text-xs text-[var(--fg-3)]">Dados pessoais da lista exigem a capacidade contato.ver.</p>}
      {podeVerContato && isMaster && <p className="mt-3 text-xs text-[var(--fg-3)]">A marcação de teste ficará disponível por pessoa quando a fonte da sessão for ligada.</p>}
    </SectionCard>

    <Modal open={aberto} onClose={() => setAberto(false)} title="Pré-checkout da Sessão de Viabilidade" width="max-w-6xl">
      <Tabs tabs={[{ k: 'tabela', l: 'Pessoas' }, { k: 'resumo', l: 'Resumo' }]} active={aba} onChange={setAba} label="Visões do pré-checkout da Sessão de Viabilidade" />
      {aba === 'tabela' ? podeVerContato ? <>
        <div className="mt-4">
          <DataTable minWidth={isMaster ? 1120 : 1040}>
            <Thead><Th>Data do evento</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Data do pré-checkout</Th><Th>Comprou?</Th><Th>Status da compra</Th><Th>Oferta</Th>{isMaster && <Th>Ação</Th>}</Thead>
            <tbody><tr><td colSpan={isMaster ? 9 : 8} className="p-0"><EmptyState title="Pré-checkout da sessão ainda sem dados" hint="A fonte própria de pré-checkouts da Sessão de Viabilidade ainda não foi ligada. Nenhum contato foi carregado." /></td></tr></tbody>
          </DataTable>
        </div>
      </> : <EmptyState title="Lista indisponível" hint="A capacidade contato.ver é necessária para visualizar dados pessoais." /> : <div className="mt-4"><Card className="p-4"><h3 className="text-sm font-semibold text-[var(--fg)]">Resumo</h3><p className="mt-2 text-sm text-[var(--fg-2)]">sem dado ainda · o resumo por situação será preenchido quando a fonte própria for conectada.</p></Card></div>}
    </Modal>
  </>;
}
