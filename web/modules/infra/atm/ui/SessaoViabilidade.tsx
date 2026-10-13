'use client';

import { useRef, useState } from 'react';
import { Badge, Card, ConfirmDialog, DataTable, EmptyState, KpiCard, SectionCard, Tabs, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Modal } from '@/shared/ui/components/Modal';
import {
  contarVendasSessaoViabilidade,
  conversaoSessaoViabilidade,
  listaAposLeituraSv,
  dataDaVendaSessaoViabilidade,
  notaVendasTesteForaDoTotal,
  valorDaVendaSessaoViabilidade,
  type VendaSessaoViabilidade,
} from '../domain/sessao-viabilidade';
import type { MetricaAtm } from '../domain/dashboard';
import { carregarAtmSvVendas, desmarcarAtmTestePorEmail, marcarAtmTestePorEmail, type Resultado } from '../infrastructure/atm-data';

type AbaSv = 'vendas' | 'precheckout' | 'resumo';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const CLASSE_CARD = 'text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] rounded-[var(--r-lg)]';

function formatarMetrica(metrica: MetricaAtm) {
  return metrica.semDado ? 'Sem dado' : inteiro.format(metrica.valor);
}

function SeloMockup() {
  return <Badge tone="warning">MOCKUP</Badge>;
}

export function SessaoViabilidade({ chave, vendas, vendasTeste, periodoLabel, podeVerContato, isMaster, onTesteAlterado }: {
  chave: string;
  vendas: MetricaAtm;
  /** `dados_atm_resumo.vendas_teste`: vendas que a marcação de teste tirou do total. */
  vendasTeste: number | null;
  periodoLabel: string;
  podeVerContato: boolean;
  isMaster: boolean;
  /** Releitura do resumo depois de marcar ou desmarcar teste (o card Total de vendas vem dele). */
  onTesteAlterado: () => Promise<void>;
}) {
  const [aberto, setAberto] = useState(false);
  const [aba, setAba] = useState<AbaSv>('vendas');
  const [incluirTeste, setIncluirTeste] = useState(isMaster);
  const [lista, setLista] = useState<Resultado<VendaSessaoViabilidade[]>>({ data: [], semDado: true, erro: null });
  const [lidoEm, setLidoEm] = useState<Date | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [alvo, setAlvo] = useState<VendaSessaoViabilidade | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);
  const pedidoAtual = useRef(0);

  // Pré-checkout da SV ainda não tem fonte: fica nulo (mockup), e a conversão herda o "Sem dado".
  const preCheckoutsUnicos: number | null = null;
  const conversao = conversaoSessaoViabilidade(vendas, preCheckoutsUnicos);
  const notaTeste = notaVendasTesteForaDoTotal(vendasTeste);
  const contagem = contarVendasSessaoViabilidade(lista.data);
  const listaSemPermissao = lista.semPermissao === true;
  const desatualizada = lista.erro !== null && lidoEm !== null;

  // Só pede a lista (que traz dado pessoal) para quem pode ver contato. Falha mantém a última lista, menos a perda de permissão (42501), que limpa.
  const carregar = async (comTeste: boolean) => {
    if (!podeVerContato) return;
    const id = ++pedidoAtual.current;
    setCarregando(true);
    const r = await carregarAtmSvVendas(chave, isMaster && comTeste);
    if (id !== pedidoAtual.current) return;
    setCarregando(false);
    setLista((anterior) => listaAposLeituraSv(anterior, r));
    if (!r.semDado) setLidoEm(new Date());
    else if (r.semPermissao) setLidoEm(null);
  };

  const abrir = (proxima: AbaSv) => {
    setAba(proxima);
    setErroAcao(null);
    setAberto(true);
    void carregar(incluirTeste);
  };

  const trocarInclusao = (valor: boolean) => {
    setIncluirTeste(valor);
    void carregar(valor);
  };

  const mudarTeste = async (venda: VendaSessaoViabilidade, teste: boolean) => {
    if (salvando || !isMaster) return;
    setSalvando(venda.id); setErroAcao(null);
    if (!venda.email) { setSalvando(null); setAlvo(null); setErroAcao('Esta venda não tem e-mail: a marcação é feita pelo e-mail.'); return; }
    const r = teste
      ? await marcarAtmTestePorEmail(chave, venda.email)
      : await desmarcarAtmTestePorEmail(chave, venda.email);
    setSalvando(null);
    setAlvo(null);
    if (r.erro) { setErroAcao(r.erro); return; }
    await Promise.all([carregar(incluirTeste), onTesteAlterado()]);
  };

  return <>
    <SectionCard
      title="Sessão de Viabilidade"
      subtitle="Total de vendas, pré-checkouts únicos por e-mail e conversão do pré-checkout."
      right={<span className="inline-flex items-center gap-2 text-xs text-[var(--fg-3)]">Pré-checkout em <SeloMockup /></span>}
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <button type="button" onClick={() => abrir('vendas')} className={CLASSE_CARD}>
          <KpiCard label="Total de vendas" value={formatarMetrica(vendas)} hint={vendas.semDado ? 'sem dado ainda' : notaTeste ?? (vendasTeste === 0 ? 'nenhuma venda de teste no período' : 'dados_atm_resumo')} bar="green" title={`dados_atm_resumo.vendas · ${periodoLabel}`} />
        </button>
        <button type="button" onClick={() => abrir('precheckout')} className={CLASSE_CARD}>
          <KpiCard label="Pré-checkouts únicos" value={<span className="inline-flex flex-wrap items-center gap-2">Sem dado <SeloMockup /></span>} hint="mockup · fonte da sessão ainda não ligada" />
        </button>
        <button type="button" onClick={() => abrir('resumo')} className={CLASSE_CARD}>
          <KpiCard label="Conversão do pré-checkout" value={conversao.semDado ? 'Sem dado' : `${conversao.valor.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`} hint="vendas ÷ pré-checkouts únicos · depende do pré-checkout (mockup)" />
        </button>
      </div>
      {!podeVerContato && <p className="mt-3 text-xs text-[var(--fg-3)]">A lista de vendas com dados pessoais exige a capacidade contato.ver.</p>}
    </SectionCard>

    <Modal open={aberto} onClose={() => setAberto(false)} title="Sessão de Viabilidade" width="max-w-6xl">
      <Tabs tabs={[{ k: 'vendas', l: 'Vendas' }, { k: 'precheckout', l: 'Pré-checkout · MOCKUP' }, { k: 'resumo', l: 'Resumo' }]} active={aba} onChange={(k) => setAba(k === 'precheckout' ? 'precheckout' : k === 'resumo' ? 'resumo' : 'vendas')} label="Visões da Sessão de Viabilidade" />

      {aba === 'vendas' && (!podeVerContato
        ? <EmptyState title="Lista indisponível" hint="A capacidade contato.ver é necessária para visualizar dados pessoais." />
        : <>
          <div className="mb-3 flex flex-wrap items-center gap-3 text-xs text-[var(--fg-3)]">
            {isMaster && <Toggle checked={incluirTeste} onChange={trocarInclusao} disabled={carregando} label="Incluir testes" />}
            <span>{lista.semDado ? 'sem dado ainda' : `${inteiro.format(contagem.validas)} vendas válidas na lista${incluirTeste && isMaster ? ` · ${inteiro.format(contagem.teste)} de teste fora das contagens` : ''}`}</span>
            <span className="ml-auto">{carregando ? 'Carregando…' : lidoEm ? `lista lida às ${lidoEm.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' })}` : ''}</span>
          </div>
          <p className="mb-3 text-xs text-[var(--fg-3)]">A lista não recebe o período selecionado. O card Total de vendas segue o período aplicado: {periodoLabel}.</p>
          {lista.erro && <p role="status" className="mb-3 rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{lista.erro}{desatualizada ? ' A lista abaixo é a última lida.' : ''}</p>}
          {erroAcao && <p role="alert" className="mb-3 rounded border border-[var(--red)]/40 p-3 text-sm text-[var(--red)]">{erroAcao}</p>}
          {listaSemPermissao
            ? <EmptyState title="Lista indisponível" hint="A permissão para ler esta lista foi perdida. Recarregue a página ou entre de novo." />
            : lista.semDado
            ? <EmptyState title="Vendas da Sessão de Viabilidade" hint="sem dado ainda" />
            : lista.data.length === 0
              ? <EmptyState title="Nenhuma venda da Sessão de Viabilidade" />
              : <div className={'max-h-[65vh] overflow-auto ' + (desatualizada ? 'opacity-60' : '')}>
                <DataTable minWidth={isMaster ? 1040 : 900}>
                  <Thead><Th className="px-2!">Data da venda</Th><Th className="px-2!">Nome</Th><Th className="px-2!">E-mail</Th><Th className="px-2!">Telefone</Th><Th className="px-2!">Status</Th><Th className="px-2!">Bruto / líquido</Th><Th className="px-2!">Oferta</Th>{isMaster && <><Th className="px-2!">Teste</Th><Th className="px-2!">Ação</Th></>}</Thead>
                  <tbody>{lista.data.map((venda) => <Tr key={venda.id} className={venda.teste ? 'opacity-60' : ''}>
                    <Td className="px-2! whitespace-nowrap">{dataDaVendaSessaoViabilidade(venda) ?? 'Sem dado'}</Td>
                    <Td className="px-2! whitespace-nowrap"><div>{venda.nome ?? 'Sem dado'}</div><div className="text-[10px] text-[var(--fg-3)]" title="Transação">{venda.transacao ?? 'Transação: sem dado'}</div></Td>
                    <Td className="px-2! max-w-[9rem] truncate"><span title={venda.email ?? undefined}>{venda.email ?? 'Sem dado'}</span></Td>
                    <Td className="px-2! whitespace-nowrap">{venda.telefone ?? 'Sem dado'}</Td>
                    <Td className="px-2!">{venda.status ?? 'Sem dado'}</Td>
                    <Td className="px-2! whitespace-nowrap tabular">{valorDaVendaSessaoViabilidade(venda.valorBruto, venda.moeda) ?? 'Sem dado'} / {valorDaVendaSessaoViabilidade(venda.valorLiquido, venda.moeda) ?? 'Sem dado'}</Td>
                    <Td className="px-2! whitespace-nowrap">{venda.ofertaCodigo ?? 'Sem dado'}</Td>
                    {isMaster && <>
                      <Td className="px-2!">{venda.teste ? <Badge tone="warning">TESTE</Badge> : 'Não'}</Td>
                      <Td className="px-2!">{venda.email ? <button type="button" disabled={salvando === venda.id} onClick={() => { setErroAcao(null); if (venda.teste) void mudarTeste(venda, false); else setAlvo(venda); }} className="whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs hover:bg-[var(--surface-3)] disabled:opacity-50">{salvando === venda.id ? 'Salvando…' : venda.teste ? 'Desmarcar teste' : 'Marcar teste'}</button> : 'Sem e-mail'}</Td>
                    </>}
                  </Tr>)}</tbody>
                </DataTable>
              </div>}
          {isMaster && !lista.semDado && <p className="mt-2 text-xs text-[var(--fg-3)]">Linha marcada TESTE fica fora de todas as contagens deste evento (marcação em dados.marcacoes_teste).</p>}
        </>)}

      {aba === 'precheckout' && <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2 text-sm text-[var(--fg-2)]"><SeloMockup /><span>Visão de pré-checkout da Sessão de Viabilidade em mockup: sem fonte ligada, sem número e sem contato.</span></div>
        <DataTable minWidth={760}>
          <Thead><Th>Data do pré-checkout</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Comprou?</Th></Thead>
          <tbody><tr><td colSpan={5} className="p-0"><EmptyState title="Pré-checkout da sessão sem fonte" hint="MOCKUP · a regra pedida é pré-checkouts únicos por e-mail. Os campos desta tabela dependem da fonte que ainda será definida." /></td></tr></tbody>
        </DataTable>
      </div>}

      {aba === 'resumo' && <div className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard label="Total de vendas" value={formatarMetrica(vendas)} hint={`dados_atm_resumo · ${periodoLabel}`} bar="green" />
          <KpiCard label="Vendas de teste fora" value={vendasTeste == null ? 'Sem dado' : inteiro.format(vendasTeste)} hint="dados_atm_resumo.vendas_teste" />
          <KpiCard label="Pré-checkouts únicos" value={<span className="inline-flex flex-wrap items-center gap-2">Sem dado <SeloMockup /></span>} hint="mockup" />
          <KpiCard label="Conversão do pré-checkout" value={conversao.semDado ? 'Sem dado' : `${conversao.valor.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`} hint="vendas ÷ pré-checkouts únicos" />
        </div>
        <Card className="p-4"><p className="text-sm text-[var(--fg-2)]">Total de vendas vem de dados_atm_resumo.vendas, já sem as vendas marcadas como teste. A conversão fica sem dado enquanto o pré-checkout da sessão for mockup.</p></Card>
      </div>}
      {alvo && <ConfirmDialog title="Marcar venda como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvo(null)} onConfirm={() => void mudarTeste(alvo, true)} message="Esta marcação vale para este Seminário ATM e é feita pelo e-mail desta linha: a pessoa e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />}
    </Modal>
  </>;
}
