'use client';

import { useRef, useState } from 'react';
import { Badge, ConfirmDialog, DataTable, EmptyState, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Modal } from '@/shared/ui/components/Modal';
import {
  contarVendasSessaoViabilidade,
  dataDaVendaSessaoViabilidade,
  listaAposLeituraSv,
  notaVendasTesteForaDoTotal,
  valorDaVendaSessaoViabilidade,
  type VendaSessaoViabilidade,
} from '../domain/sessao-viabilidade';
import type { MetricaAtm } from '../domain/dashboard';
import { carregarAtmSvVendas, desmarcarAtmTestePorEmail, marcarAtmTestePorEmail, type Resultado } from '../infrastructure/atm-data';

/*
 * Modais dos cards Pré-checkout e Vendas do funil do Seminário ATM (decisão do Victor, 13/10/2026 18h35):
 * substituem a antiga seção separada "Sessão de Viabilidade". Os números dos cards vêm de dados_atm_resumo;
 * os modais só mostram a lista (dado pessoal, gate contato.ver na tela e no banco).
 */

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });

function textoMetrica(metrica: MetricaAtm) {
  return metrica.semDado ? 'Sem dado' : inteiro.format(metrica.valor);
}

/**
 * Leitura da lista de vendas da SV (`public.dados_atm_sv_vendas`). Só chama a RPC para quem tem `contato.ver`.
 * Falha mantém a última lista (esmaecida, com a hora da leitura), menos a perda de permissão (42501), que limpa.
 */
export function useVendasSvAtm(chave: string, isMaster: boolean, podeVerContato: boolean) {
  const [incluirTeste, setIncluirTeste] = useState(isMaster);
  const [lista, setLista] = useState<Resultado<VendaSessaoViabilidade[]>>({ data: [], semDado: true, erro: null });
  const [lidoEm, setLidoEm] = useState<Date | null>(null);
  const [carregando, setCarregando] = useState(false);
  const pedidoAtual = useRef(0);

  const carregar = async (comTeste: boolean = incluirTeste) => {
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

  const trocarInclusao = (valor: boolean) => {
    setIncluirTeste(valor);
    void carregar(valor);
  };

  return { lista, lidoEm, carregando, incluirTeste, carregar, trocarInclusao };
}

export type VendasSvAtm = ReturnType<typeof useVendasSvAtm>;

export function ModalVendasAtm({ open, onClose, chave, vendas, vendasTeste, periodoLabel, podeVerContato, isMaster, sv, onTesteAlterado }: {
  open: boolean;
  onClose: () => void;
  chave: string;
  /** `dados_atm_resumo.vendas` no período aplicado (o número do card). */
  vendas: MetricaAtm;
  /** `dados_atm_resumo.vendas_teste`: vendas que a marcação de teste tirou do total. */
  vendasTeste: number | null;
  periodoLabel: string;
  podeVerContato: boolean;
  isMaster: boolean;
  sv: VendasSvAtm;
  /** Releitura do resumo depois de marcar ou desmarcar teste (o card Vendas vem dele). */
  onTesteAlterado: () => Promise<void>;
}) {
  const [alvo, setAlvo] = useState<VendaSessaoViabilidade | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);
  const { lista, lidoEm, carregando, incluirTeste } = sv;
  const contagem = contarVendasSessaoViabilidade(lista.data);
  const listaSemPermissao = lista.semPermissao === true;
  const desatualizada = lista.erro !== null && lidoEm !== null;
  const notaTeste = isMaster ? notaVendasTesteForaDoTotal(vendasTeste) : null;

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
    await Promise.all([sv.carregar(), onTesteAlterado()]);
  };

  return <Modal open={open} onClose={() => { setErroAcao(null); onClose(); }} title="Vendas da Sessão de Viabilidade" width="max-w-6xl">
    <div className="mb-3 flex flex-wrap items-center gap-3 text-xs text-[var(--fg-3)]">
      <span className="text-sm text-[var(--fg-2)]">Card Vendas: <strong className="tabular text-[var(--fg)]">{textoMetrica(vendas)}</strong> no período {periodoLabel}</span>
      {notaTeste && <span>{notaTeste}</span>}
    </div>
    {!podeVerContato
      ? <EmptyState title="Lista indisponível" hint="A capacidade contato.ver é necessária para visualizar dados pessoais." />
      : <>
        <div className="mb-3 flex flex-wrap items-center gap-3 text-xs text-[var(--fg-3)]">
          {isMaster && <Toggle checked={incluirTeste} onChange={sv.trocarInclusao} disabled={carregando} label="Incluir testes" />}
          <span>{lista.semDado ? 'sem dado ainda' : `${inteiro.format(contagem.validas)} vendas válidas na lista${incluirTeste && isMaster ? ` · ${inteiro.format(contagem.teste)} de teste fora das contagens` : ''}`}</span>
          <span className="ml-auto">{carregando ? 'Carregando…' : lidoEm ? `lista lida às ${lidoEm.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' })}` : ''}</span>
        </div>
        <p className="mb-3 text-xs text-[var(--fg-3)]">A lista traz todas as vendas do evento, sem o filtro de período. O card Vendas segue o período aplicado.</p>
        {lista.erro && <p role="status" className="mb-3 rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{lista.erro}{desatualizada ? ' A lista abaixo é a última lida.' : ''}</p>}
        {erroAcao && <p role="alert" className="mb-3 rounded border border-[var(--red)]/40 p-3 text-sm text-[var(--red)]">{erroAcao}</p>}
        {listaSemPermissao
          ? <EmptyState title="Lista indisponível" hint="A permissão para ler esta lista foi perdida. Recarregue a página ou entre de novo." />
          : lista.semDado
            ? <EmptyState title="Vendas da Sessão de Viabilidade" hint={carregando ? 'carregando…' : 'sem dado ainda'} />
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
      </>}
    {alvo && <ConfirmDialog title="Marcar venda como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvo(null)} onConfirm={() => void mudarTeste(alvo, true)} message="Esta marcação vale para este Seminário ATM e é feita pelo e-mail desta linha: a pessoa e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />}
  </Modal>;
}

/** Colunas da lista de pré-checkout pedidas pelo Victor (13/10/2026). A lista ainda não tem RPC pública. */
const COLUNAS_PRE_CHECKOUT = ['Data do pré-checkout', 'Nome', 'E-mail', 'Telefone', 'Comprou?', 'utm_source'];

export function ModalPreCheckoutAtm({ open, onClose, preCheckout, periodoLabel, podeVerContato }: {
  open: boolean;
  onClose: () => void;
  /** `dados_atm_resumo.pre_checkout_pessoas` no período aplicado (o número do card). */
  preCheckout: MetricaAtm;
  periodoLabel: string;
  podeVerContato: boolean;
}) {
  return <Modal open={open} onClose={onClose} title="Pré-checkout" width="max-w-6xl">
    <div className="mb-3 text-sm text-[var(--fg-2)]">Card Pré-checkout: <strong className="tabular text-[var(--fg)]">{textoMetrica(preCheckout)}</strong> no período {periodoLabel}</div>
    {!podeVerContato
      ? <EmptyState title="Lista indisponível" hint="A capacidade contato.ver é necessária para visualizar dados pessoais." />
      : <DataTable minWidth={760}>
        <Thead>{COLUNAS_PRE_CHECKOUT.map((c) => <Th key={c} className="px-2!">{c}</Th>)}</Thead>
        <tbody><tr><td colSpan={COLUNAS_PRE_CHECKOUT.length} className="p-0"><EmptyState title="Lista ainda não ligada" hint="O número do card vem do banco (dados_atm_resumo). A lista de quem preencheu o formulário depende de uma função do banco que ainda não existe; nenhuma linha é mostrada até ela ser criada." /></td></tr></tbody>
      </DataTable>}
  </Modal>;
}
