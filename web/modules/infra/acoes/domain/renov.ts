/** Painel do /renov (hm.timeholdingbrasil.com.br/renov), 16/10/2026. Lê a RPC dados_renov_thb(p_chave, p_incluir_teste). */

export const OPCOES_RENOV = [
  { chave: 'nao-renovar', rotulo: 'Não renova' },
  { chave: 'renovar-holding-masters', rotulo: 'Renova Holding Masters' },
  { chave: 'upgrade-implementacao-assistida', rotulo: 'Upgrade Implementação Assistida' },
] as const;

export const OFERTAS_RENOV: Record<string, string> = {
  nv5f10zq: 'Renovação Holding Masters (R$ 6.000)',
  wftji6dl: 'Upgrade Implementação Assistida (R$ 10.000)',
};
/** Link externo de cada oferta do checkout. */
export const LINK_OFERTA_RENOV = (oferta: string) => `https://pay.hotmart.com/L97981750T?off=${encodeURIComponent(oferta)}`;
/** Qual opção do formulário leva a cada oferta. */
export const OPCAO_DA_OFERTA: Record<string, string> = { nv5f10zq: 'renovar-holding-masters', wftji6dl: 'upgrade-implementacao-assistida' };

export type AplicacaoRenov = {
  id: string; criadoEm: string; opcao: string; origem: string; pagou: boolean;
  /** teste efetivo = coluna legada OU e-mail @advmais.com OU marcação do dashboard (dados.marcacoes_teste). */
  teste: boolean; testeFixo: boolean; testeColuna: boolean; testeMarcado: boolean; acessosAntes: number | null;
  nome: string | null; email: string | null; telefone: string | null;
};
export type VendaRenov = { em: string; oferta: string; valor: number; aplicou: boolean; nome: string | null; email: string | null };
export type PainelRenov = {
  total: number;
  porOpcao: { chave: string; rotulo: string; n: number }[];
  aplicaramEPagaram: number;
  /** Vendas e valor das ofertas da ação, pela mesma regra do card Vendas. */
  vendasTotal: number;
  valorTotal: number;
  semOferta: boolean;
  acessos: number;
  visitantes: number;
  visitantesQueAplicaram: number;
  /** Visitantes que aplicaram sobre visitantes únicos, em %. Null sem visitante. */
  taxaAplicacao: number | null;
  vendas: { oferta: string; rotulo: string; vendas: number; valor: number }[];
  aplicacoes: AplicacaoRenov[];
  ultimasVendas: VendaRenov[];
  veContato: boolean;
  ehMaster: boolean;
};

/** Filtro da tabela pelos cards. Clicar no card ativo limpa. */
export type FiltroRenov = { tipo: 'opcao'; opcao: string } | { tipo: 'pagou' } | { tipo: 'oferta'; oferta: string } | null;

const n = (v: unknown) => (typeof v === 'number' ? v : Number(v) || 0);
const s = (v: unknown) => (typeof v === 'string' ? v : null);
const lista = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? (v as Record<string, unknown>[]) : []);

export const rotuloOpcaoRenov = (chave: string) => OPCOES_RENOV.find((o) => o.chave === chave)?.rotulo ?? chave;

export function mapearPainelRenov(bruto: unknown): PainelRenov {
  const r = (bruto ?? {}) as Record<string, unknown>;
  const porOpcao = (r.por_opcao ?? {}) as Record<string, unknown>;
  const visitantes = n(r.visitantes);
  const visitantesQueAplicaram = n(r.visitantes_que_aplicaram);
  return {
    total: n(r.aplicacoes_total),
    porOpcao: OPCOES_RENOV.map((o) => ({ chave: o.chave, rotulo: o.rotulo, n: n(porOpcao[o.chave]) })),
    aplicaramEPagaram: n(r.aplicaram_e_pagaram),
    vendasTotal: n(r.vendas_total),
    valorTotal: n(r.valor_total),
    semOferta: r.sem_oferta === true,
    acessos: n(r.acessos),
    visitantes,
    visitantesQueAplicaram,
    taxaAplicacao: visitantes > 0 ? (visitantesQueAplicaram / visitantes) * 100 : null,
    vendas: lista(r.vendas).map((v) => ({ oferta: String(v.oferta), rotulo: OFERTAS_RENOV[String(v.oferta)] ?? String(v.oferta), vendas: n(v.vendas), valor: n(v.valor) })),
    aplicacoes: lista(r.aplicacoes).map((a) => ({
      id: String(a.id ?? ''), criadoEm: String(a.criado_em), opcao: String(a.opcao), origem: s(a.origem) ?? '', pagou: a.pagou === true,
      teste: a.teste === true, testeFixo: a.teste_fixo === true, testeColuna: a.teste_coluna === true, testeMarcado: a.teste_marcado === true,
      acessosAntes: a.acessos_antes === null || a.acessos_antes === undefined ? null : n(a.acessos_antes),
      nome: s(a.nome), email: s(a.email), telefone: s(a.telefone),
    })),
    ultimasVendas: lista(r.ultimas_vendas).map((v) => ({
      em: String(v.em), oferta: String(v.oferta), valor: n(v.valor), aplicou: v.aplicou === true, nome: s(v.nome), email: s(v.email),
    })),
    veContato: r.ve_contato === true,
    ehMaster: r.eh_master === true,
  };
}

/** Linhas que formam o número do card escolhido. */
export function filtrarAplicacoesRenov(aplicacoes: AplicacaoRenov[], filtro: FiltroRenov): AplicacaoRenov[] {
  if (!filtro) return aplicacoes;
  if (filtro.tipo === 'opcao') return aplicacoes.filter((a) => a.opcao === filtro.opcao);
  if (filtro.tipo === 'pagou') return aplicacoes.filter((a) => a.pagou && a.opcao !== 'nao-renovar');
  return aplicacoes.filter((a) => a.pagou && a.opcao === OPCAO_DA_OFERTA[filtro.oferta]);
}

export const mesmoFiltroRenov = (a: FiltroRenov, b: FiltroRenov) => JSON.stringify(a) === JSON.stringify(b);
