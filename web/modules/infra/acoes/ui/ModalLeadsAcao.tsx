'use client';

import { rotuloValorResumoLead, type LeadAtm, type MetricaAtm, type NumeroGrupoAtm } from '@/modules/infra/atm/domain/dashboard';
import type { EstadoListaAtm } from '@/modules/infra/atm/ui/carregador-listas';
import { dataHoraAtm, ModalPessoasAtm, simNaoAtm, type CampoResumoPessoasAtm, type ColunaPessoasAtm } from '@/modules/infra/atm/ui/ModalPessoasAtm';
import { contarLeadsAcao, motivoDeNaoValido, rotuloValidadeOferta, validadeDaOferta } from '../domain/leads';

/*
 * Modal de Leads das Ações da Black (15/10/2026): o mesmo ModalPessoasAtm do Seminário ATM, sem a aba Grupo, com a
 * Evolução em linha (eixos X e Y) e o Resumo em pizzas. Os leads vêm de `dados_atm_leads` com a etiqueta da ação.
 * "Válido para a oferta" = está na lista de aptos da ação (ver domain/leads.ts).
 */

const texto = (v: string | null) => v ?? 'Não lançado';
const validade = (l: LeadAtm) => rotuloValidadeOferta(validadeDaOferta(l));

const COLUNAS: ColunaPessoasAtm<LeadAtm>[] = [
  { titulo: 'Data', celula: (l) => dataHoraAtm(l.dataHora), className: 'whitespace-nowrap' },
  { titulo: 'Nome', celula: (l) => texto(l.nome) },
  { titulo: 'E-mail', celula: (l) => texto(l.email) },
  { titulo: 'Telefone', celula: (l) => texto(l.telefone), className: 'whitespace-nowrap' },
  { titulo: 'Válido para a oferta?', celula: (l) => <span title={motivoDeNaoValido(l) || undefined}>{validade(l)}</span> },
  { titulo: 'Entrou no grupo?', celula: (l) => simNaoAtm(l.entrouGrupo) },
  { titulo: 'Instrução', celula: (l) => texto(l.instrucao) },
  { titulo: 'Turma', celula: (l) => texto(l.turma) },
  { titulo: 'Estado', celula: (l) => texto(l.estado) },
  { titulo: 'utm_source', celula: (l) => texto(l.utmSource) },
];

const CAMPOS: CampoResumoPessoasAtm<LeadAtm>[] = [
  { nome: 'utm_source', valor: (l) => rotuloValorResumoLead(l.utmSource) },
  { nome: 'Estado', valor: (l) => rotuloValorResumoLead(l.estado) },
  { nome: 'Instrução', valor: (l) => rotuloValorResumoLead(l.instrucao) },
  { nome: 'Turma', valor: (l) => rotuloValorResumoLead(l.turma) },
  { nome: 'Válido para a oferta?', valor: (l) => validade(l) },
];

export function ModalLeadsAcao({ nomeAcao, lista, card, periodoLabel, open, onClose, isMaster, incluirTeste, onIncluirTeste }: {
  nomeAcao: string;
  lista: EstadoListaAtm<LeadAtm> | null;
  card: MetricaAtm;
  periodoLabel: string;
  open: boolean;
  onClose: () => void;
  isMaster: boolean;
  incluirTeste: boolean;
  onIncluirTeste: (v: boolean) => void;
}) {
  const c = lista?.data ? contarLeadsAcao(lista.data) : null;
  const faixa = c && c.validos !== null
    ? <p className="mb-3 text-xs text-[var(--fg-2)]"><strong className="tabular text-[var(--fg)]">{c.validos}</strong> válidos para a oferta · <strong className="tabular text-[var(--fg)]">{c.foraDaLista}</strong> fora da lista de aptos · <strong className="tabular text-[var(--fg)]">{c.gerais}</strong> leads gerais. Quem usa um e-mail fora da lista também entra como lead.</p>
    : c ? <p className="mb-3 text-xs text-[var(--yellow)]">Esta ação ainda não tem a lista de aptos carregada no banco: não dá para separar leads válidos de leads gerais.</p> : null;
  const semGrupo: { modo: 'numeros'; estado: EstadoListaAtm<NumeroGrupoAtm> | null } = { modo: 'numeros', estado: null };
  return <ModalPessoasAtm<LeadAtm>
    open={open} onClose={onClose} titulo={`Leads · ${nomeAcao}`} abaPessoas="Leads" rotuloContador={['lead', 'leads']} rotuloCentro="leads"
    periodoLabel={periodoLabel} periodo={{ de: null, ate: null }} card={{ rotulo: 'Leads', metrica: card }} lista={lista}
    colunas={COLUNAS} rotuloData="Data" dataDe={(l) => l.dataHora} campos={CAMPOS} grupo={semGrupo}
    textos={{ naoPublicada: 'Leads indisponíveis', vazio: 'Nenhum lead nesta ação ainda' }}
    isMaster={isMaster} incluirTeste={incluirTeste} onIncluirTeste={onIncluirTeste}
    graficoEvolucao="linha" semAbaGrupo resumoNoTopo={faixa} />;
}
