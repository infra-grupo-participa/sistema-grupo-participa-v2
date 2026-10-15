'use client';

import { rotuloListaOrigem, rotuloValorResumoLead, type LeadAtm, type MetricaAtm, type NumeroGrupoAtm, type PessoaPreCheckoutAtm } from '../domain/dashboard';
import { vendasNoPeriodoAtm, type SituacaoGrupoAtm } from '../domain/modal-pessoas';
import { dataDaVendaSessaoViabilidade, notaVendasTesteForaDoTotal, valorDaVendaSessaoViabilidade, type VendaSessaoViabilidade } from '../domain/sessao-viabilidade';
import { MENSAGEM_PRE_CHECKOUT_NAO_PUBLICADA } from '../infrastructure/atm-data';
import type { EstadoListaAtm } from './carregador-listas';
import { dataHoraAtm, ModalPessoasAtm, simNaoAtm, type CampoResumoPessoasAtm, type ColunaPessoasAtm } from './ModalPessoasAtm';

/*
 * Os três modais do funil do Seminário ATM (Leads, Pré-checkout, Vendas), todos no ModalPessoasAtm (13/10/2026).
 * Os números dos cards vêm de dados_atm_resumo; cada modal lê a sua lista sozinho (SeminarioAtmClient + useListaAtm)
 * e o contador usa o mesmo critério do card (domain/modal-pessoas.ts).
 */

type Comum = {
  open: boolean;
  onClose: () => void;
  periodoLabel: string;
  periodo: { de: string | null; ate: string | null };
  card: MetricaAtm;
  isMaster: boolean;
  incluirTeste: boolean;
  onIncluirTeste: (v: boolean) => void;
  grupo: EstadoListaAtm<NumeroGrupoAtm> | null;
};

const SEM_CONTATO = { titulo: 'Lista indisponível', hint: 'A capacidade contato.ver é necessária para visualizar dados pessoais.' };
const MENSAGEM_TESTE = 'Esta marcação vale para este Seminário ATM. O lead e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?';
const grupoSimNao = (s: SituacaoGrupoAtm | undefined) => (!s || s.semTelefone ? 'Sem telefone' : s.numero ? 'Sim' : 'Não');
const texto = (v: string | null) => v ?? 'Não lançado';

const COLUNAS_LEADS: ColunaPessoasAtm<LeadAtm>[] = [
  { titulo: 'Data', celula: (l) => dataHoraAtm(l.dataHora), className: 'whitespace-nowrap' },
  { titulo: 'Nome', celula: (l) => texto(l.nome) },
  { titulo: 'E-mail', celula: (l) => texto(l.email) },
  { titulo: 'Telefone', celula: (l) => texto(l.telefone), className: 'whitespace-nowrap' },
  { titulo: 'Entrou no grupo?', celula: (l) => simNaoAtm(l.entrouGrupo) },
  { titulo: 'É aluno?', celula: (l) => simNaoAtm(l.aluno) },
  { titulo: 'utm_source', celula: (l) => texto(l.utmSource) },
  { titulo: 'Estado', celula: (l) => texto(l.estado) },
  { titulo: 'Lista de origem', celula: (l) => texto(rotuloListaOrigem(l.listaOrigem)) },
  { titulo: 'Seminário de origem', celula: (l) => texto(l.seminarioOrigem) },
];
const CAMPOS_LEADS: CampoResumoPessoasAtm<LeadAtm>[] = [
  { nome: 'Entrou no grupo?', valor: (l) => rotuloValorResumoLead(l.entrouGrupo) },
  { nome: 'É aluno?', valor: (l) => rotuloValorResumoLead(l.aluno) },
  { nome: 'utm_source', valor: (l) => rotuloValorResumoLead(l.utmSource) },
  { nome: 'Estado', valor: (l) => rotuloValorResumoLead(l.estado) },
  { nome: 'Lista de origem', valor: (l) => rotuloValorResumoLead(rotuloListaOrigem(l.listaOrigem)) },
  { nome: 'Seminário de origem', valor: (l) => rotuloValorResumoLead(l.seminarioOrigem) },
];

export function ModalLeadsAtm({ lista, podeVerContato, onToggleLead, onToggleGrupo, ...c }: Comum & {
  lista: EstadoListaAtm<LeadAtm> | null;
  podeVerContato: boolean;
  onToggleLead: (lead: LeadAtm, teste: boolean) => Promise<string | null>;
  onToggleGrupo: (numero: NumeroGrupoAtm, teste: boolean) => Promise<string | null>;
}) {
  return <ModalPessoasAtm<LeadAtm> {...c} titulo="Leads do Seminário ATM" abaPessoas="Leads" rotuloContador={['lead válido', 'leads válidos']} rotuloCentro="leads"
    card={{ rotulo: 'Leads', metrica: c.card }} lista={lista} colunas={COLUNAS_LEADS} rotuloData="Data" dataDe={(l) => l.dataHora} campos={CAMPOS_LEADS}
    grupo={{ modo: 'numeros', estado: c.grupo, onToggle: onToggleGrupo }}
    textos={{ naoPublicada: 'Leads indisponíveis', vazio: 'Nenhum lead neste período' }}
    bloqueio={podeVerContato ? null : SEM_CONTATO}
    acaoTeste={{ disponivel: (l) => !!(l.email || l.telefone), tituloConfirmacao: 'Marcar lead como teste', mensagemConfirmacao: MENSAGEM_TESTE, executar: onToggleLead }} />;
}

const COLUNAS_PRE_CHECKOUT: ColunaPessoasAtm<PessoaPreCheckoutAtm>[] = [
  { titulo: 'Data do pré-checkout', celula: (p) => dataHoraAtm(p.dataHora), className: 'whitespace-nowrap' },
  { titulo: 'Nome', celula: (p) => texto(p.nome) },
  { titulo: 'E-mail', celula: (p) => texto(p.email) },
  { titulo: 'Telefone', celula: (p) => texto(p.telefone), className: 'whitespace-nowrap' },
  { titulo: 'É lead?', celula: (p) => simNaoAtm(p.ehLead) },
  { titulo: 'Comprou?', celula: (p) => simNaoAtm(p.comprou) },
  { titulo: 'utm_source', celula: (p) => texto(p.utmSource) },
];
const CAMPOS_PRE_CHECKOUT: CampoResumoPessoasAtm<PessoaPreCheckoutAtm>[] = [
  { nome: 'Entrou no grupo?', valor: (_p, g) => grupoSimNao(g), usaGrupo: true },
  { nome: 'É lead?', valor: (p) => rotuloValorResumoLead(p.ehLead) },
  { nome: 'É aluno?', valor: (p) => rotuloValorResumoLead(p.aluno) },
  { nome: 'Comprou?', valor: (p) => rotuloValorResumoLead(p.comprou) },
  { nome: 'utm_source', valor: (p) => rotuloValorResumoLead(p.utmSource) },
  { nome: 'Estado', valor: (p) => rotuloValorResumoLead(p.estado) },
  { nome: 'Lista de origem', valor: (p) => rotuloValorResumoLead(rotuloListaOrigem(p.listaOrigem)) },
  { nome: 'Seminário de origem', valor: (p) => rotuloValorResumoLead(p.seminarioOrigem) },
];

export function ModalPreCheckoutAtm({ lista, podeVerContato, onTogglePessoa, ...c }: Comum & {
  lista: EstadoListaAtm<PessoaPreCheckoutAtm> | null;
  podeVerContato: boolean;
  onTogglePessoa: (pessoa: PessoaPreCheckoutAtm, teste: boolean) => Promise<string | null>;
}) {
  return <ModalPessoasAtm<PessoaPreCheckoutAtm> {...c} titulo="Pré-checkout" abaPessoas="Pessoas" rotuloContador={['pessoa no pré-checkout', 'pessoas no pré-checkout']} rotuloCentro="pessoas"
    card={{ rotulo: 'Pré-checkout', metrica: c.card }} lista={lista} colunas={COLUNAS_PRE_CHECKOUT} rotuloData="Data do pré-checkout" dataDe={(p) => p.dataHora} campos={CAMPOS_PRE_CHECKOUT}
    grupo={{ modo: 'cruzamento', estado: c.grupo, telefoneDe: (p) => p.telefone, nomeDe: (p) => p.nome }}
    textos={{ naoPublicada: MENSAGEM_PRE_CHECKOUT_NAO_PUBLICADA, vazio: 'Ninguém fez pré-checkout neste período' }}
    bloqueio={podeVerContato ? null : SEM_CONTATO}
    acaoTeste={{ disponivel: (p) => !!(p.email || p.telefone), tituloConfirmacao: 'Marcar pessoa como teste', mensagemConfirmacao: 'Esta marcação vale para este Seminário ATM e é feita pelo e-mail desta linha (pelo telefone só quando não há e-mail): a pessoa e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?', executar: onTogglePessoa }} />;
}

const COLUNAS_VENDAS: ColunaPessoasAtm<VendaSessaoViabilidade>[] = [
  { titulo: 'Data da venda', celula: (v) => dataDaVendaSessaoViabilidade(v) ?? 'Sem dado', className: 'whitespace-nowrap' },
  { titulo: 'Nome', celula: (v) => <><div>{v.nome ?? 'Sem dado'}</div><div className="text-[10px] text-[var(--fg-3)]" title="Transação">{v.transacao ?? 'Transação: sem dado'}</div></>, className: 'whitespace-nowrap' },
  { titulo: 'E-mail', celula: (v) => v.email ?? 'Sem dado' },
  { titulo: 'Telefone', celula: (v) => v.telefone ?? 'Sem dado', className: 'whitespace-nowrap' },
  { titulo: 'Status', celula: (v) => v.status ?? 'Sem dado' },
  { titulo: 'Bruto / líquido', celula: (v) => `${valorDaVendaSessaoViabilidade(v.valorBruto, v.moeda) ?? 'Sem dado'} / ${valorDaVendaSessaoViabilidade(v.valorLiquido, v.moeda) ?? 'Sem dado'}`, className: 'whitespace-nowrap tabular' },
  { titulo: 'Oferta', celula: (v) => v.ofertaCodigo ?? 'Sem dado', className: 'whitespace-nowrap' },
];
const CAMPOS_VENDAS: CampoResumoPessoasAtm<VendaSessaoViabilidade>[] = [
  { nome: 'Status', valor: (v) => v.status ?? 'Sem dado' },
  { nome: 'Oferta', valor: (v) => v.ofertaCodigo ?? 'Sem dado' },
  { nome: 'Entrou no grupo?', valor: (_v, g) => grupoSimNao(g), usaGrupo: true },
];

export function ModalVendasAtm({ lista, podeVerContato, vendasTeste, onToggleVenda, linkRetorno, ...c }: Comum & {
  lista: EstadoListaAtm<VendaSessaoViabilidade> | null;
  podeVerContato: boolean;
  /** `dados_atm_resumo.vendas_teste`: vendas que a marcação de teste tirou do total. */
  vendasTeste: number | null;
  onToggleVenda: (venda: VendaSessaoViabilidade, teste: boolean) => Promise<string | null>;
  /** Retorno da SV deste evento (`RegistroAtm.retornoSvUrl`). Sem link, o botão não aparece. */
  linkRetorno?: string;
}) {
  const notaTeste = c.isMaster ? notaVendasTesteForaDoTotal(vendasTeste) : null;
  const { de, ate } = c.periodo;
  return <ModalPessoasAtm<VendaSessaoViabilidade> {...c} titulo="Vendas da Sessão de Viabilidade" abaPessoas="Pessoas" rotuloContador={['venda válida', 'vendas válidas']} rotuloCentro="vendas"
    card={{ rotulo: 'Vendas', metrica: c.card }} lista={lista} filtrar={(data) => vendasNoPeriodoAtm(data, de, ate)}
    colunas={COLUNAS_VENDAS} rotuloData="Data da venda" dataDe={(v) => v.aprovadoEm} campos={CAMPOS_VENDAS}
    grupo={{ modo: 'cruzamento', estado: c.grupo, telefoneDe: (v) => v.telefone, nomeDe: (v) => v.nome }}
    textos={{ naoPublicada: 'A lista de vendas da Sessão de Viabilidade não está publicada no banco', vazio: 'Nenhuma venda da Sessão de Viabilidade registrada neste período' }}
    bloqueio={podeVerContato ? null : SEM_CONTATO}
    notas={<>{linkRetorno && <a href={linkRetorno} target="_blank" rel="noopener noreferrer" className="mb-3 inline-flex min-h-11 items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--accent-border)] bg-[var(--accent-subtle)] px-3 text-sm font-medium text-[var(--accent)] hover:bg-[var(--surface-3)] md:min-h-9">Ver retorno da SV<span className="sr-only"> (abre em nova aba)</span></a>}<p className="mb-3 text-xs text-[var(--fg-3)]">Vendas no período aplicado (pela data de aprovação, a mesma regra do card Vendas).{notaTeste ? ` ${notaTeste}.` : ''}</p></>}
    acaoTeste={{ disponivel: (v) => !!v.email, semAcao: 'Sem e-mail', tituloConfirmacao: 'Marcar venda como teste', mensagemConfirmacao: 'Esta marcação vale para este Seminário ATM e é feita pelo e-mail desta linha: a pessoa e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?', executar: onToggleVenda }} />;
}
