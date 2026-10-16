import type { LeadAtm } from '@/modules/infra/atm/domain/dashboard';

/*
 * Leads gerais x leads válidos das Ações da Black (pedido do Victor, 15/10/2026).
 *
 * Quem preenche a página entra como lead mesmo sem ter direito à oferta (a página só valida nome, e-mail e WhatsApp).
 * "Válido para a oferta" = a pessoa está na lista de aptos da ação. No banco essa lista é `dados.lista_membros`
 * (a mesma tabela que o ATM usa para a Lista 1 e a Lista 2): `dados_atm_leads.lista_origem` vem como `lista_1`/`lista_2`
 * para quem está nela, `descartado` para quem foi retirado de propósito e `fora_das_listas` para o resto.
 * Enquanto a ação não tem lista carregada, `lista_origem` vem nulo em todo mundo e o resultado é "sem dado"
 * (nunca "não válido"): sem lista não dá para dizer quem é apto.
 */

export type ValidadeOferta = 'sim' | 'nao' | 'semDado';

const LISTAS_DE_APTOS = new Set(['lista_1', 'lista_2', 'lista_1_e_2']);

export function validadeDaOferta(lead: Pick<LeadAtm, 'listaOrigem'>): ValidadeOferta {
  if (lead.listaOrigem === null) return 'semDado';
  return LISTAS_DE_APTOS.has(lead.listaOrigem) ? 'sim' : 'nao';
}

export function rotuloValidadeOferta(v: ValidadeOferta): string {
  return v === 'sim' ? 'Sim' : v === 'nao' ? 'Não' : 'Sem dado';
}

/** Por que a pessoa não é válida, em português, para a tabela. */
export function motivoDeNaoValido(lead: Pick<LeadAtm, 'listaOrigem'>): string {
  if (lead.listaOrigem === 'descartado') return 'Retirado da lista de aptos';
  if (lead.listaOrigem === 'fora_das_listas') return 'E-mail fora da lista de aptos';
  return '';
}

export type ContagemLeadsAcao = {
  /** Todos os leads sem teste: é o `dados_atm_resumo.leads`. */
  gerais: number;
  /** Leads na lista de aptos. `null` = a ação ainda não tem lista de aptos carregada. */
  validos: number | null;
  foraDaLista: number | null;
  /** Ingressos no grupo entre os válidos. `null` = sem lista ou sem fonte de grupo. */
  ingressoValidos: number | null;
  /** Ingresso entre os válidos ÷ válidos × 100. `null` quando não há válido para dividir. */
  ingressoValidosPct: number | null;
};

export function contarLeadsAcao(leads: readonly LeadAtm[]): ContagemLeadsAcao {
  const contam = leads.filter((l) => !l.teste);
  const comLista = contam.some((l) => l.listaOrigem !== null);
  const validos = contam.filter((l) => validadeDaOferta(l) === 'sim');
  const temGrupo = contam.some((l) => l.entrouGrupo !== null);
  const ingresso = validos.filter((l) => l.entrouGrupo === true).length;
  return {
    gerais: contam.length,
    validos: comLista ? validos.length : null,
    foraDaLista: comLista ? contam.length - validos.length : null,
    ingressoValidos: comLista && temGrupo ? ingresso : null,
    ingressoValidosPct: comLista && temGrupo && validos.length > 0 ? (ingresso / validos.length) * 100 : null,
  };
}

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const decimal = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 });

export type ExibicaoCardLeads = { valor: number; formato: 'inteiro' | 'percentual'; hint: string };

/**
 * Cards do topo que mudam para "leads válidos" (decisão do Victor, 15/10/2026): o válido fica no card principal e o
 * geral aparece ao lado, no hint. Devolve `null` quando não dá para dizer o válido (ação sem lista de aptos, sem
 * fonte de grupo) ou quando o card não muda; aí a tela mostra o número do resumo, sem inventar.
 */
export function exibicaoCardLeads(chave: string, geral: { valor: number; semDado: boolean }, c: ContagemLeadsAcao): ExibicaoCardLeads | null {
  if (c.validos === null || c.foraDaLista === null) return null;
  if (chave === 'leads') {
    return { valor: c.validos, formato: 'inteiro', hint: `válidos para a oferta · ${inteiro.format(c.gerais)} gerais, ${inteiro.format(c.foraDaLista)} fora da lista` };
  }
  // Ingresso no grupo: o hint "entre os leads válidos" saiu em 16/10 (Victor); quem entra no grupo veio do disparo, não
  // da página. O card agora diz quantos números são aptos, em exibicaoCardIngressoGrupo (aptos vêm do resumo).
  if (chave === 'percentualIngressoGrupo' && c.ingressoValidosPct !== null) {
    const validos = `${decimal.format(c.ingressoValidosPct)}% sobre os leads válidos`;
    return geral.semDado
      ? { valor: c.ingressoValidosPct, formato: 'percentual', hint: `sobre os leads válidos · geral sem dado` }
      : { valor: geral.valor, formato: 'percentual', hint: `no geral · ${validos}` };
  }
  return null;
}

/**
 * Card "Ingresso no grupo" (Victor, 16/10/2026): o geral é o número grande e embaixo quantos deles são aptos (estão na lista
 * do disparo). Os aptos vêm do resumo (`dados_atm_resumo.grupo_aptos`, migration 20261017003000), não mais da lista do grupo.
 * Sem o campo (resumo antigo, usuário sem contato.ver, dashboard sem fonte de grupo) o card não inventa: sem hint.
 */
export function exibicaoCardIngressoGrupo(geral: { valor: number; semDado: boolean }, aptos: { valor: number; semDado: boolean }): ExibicaoCardLeads | null {
  if (geral.semDado || aptos.semDado) return null;
  return { valor: geral.valor, formato: 'inteiro', hint: `no geral · ${inteiro.format(aptos.valor)} ${aptos.valor === 1 ? 'apto' : 'aptos'}` };
}
