/** Painel do /renov (hm.timeholdingbrasil.com.br/renov), 16/10/2026. Lê a RPC dados_renov_thb. */

export const OPCOES_RENOV = [
  { chave: 'nao-renovar', rotulo: 'Não renova' },
  { chave: 'renovar-holding-masters', rotulo: 'Renova Holding Masters' },
  { chave: 'upgrade-implementacao-assistida', rotulo: 'Upgrade Implementação Assistida' },
] as const;

export const OFERTAS_RENOV: Record<string, string> = {
  nv5f10zq: 'Renovação Holding Masters (R$ 6.000)',
  wftji6dl: 'Upgrade Implementação Assistida (R$ 10.000)',
};

export type AplicacaoRenov = {
  criadoEm: string; opcao: string; origem: string; pagou: boolean;
  nome: string | null; email: string | null; telefone: string | null;
};
export type VendaRenov = { em: string; oferta: string; valor: number; aplicou: boolean; nome: string | null; email: string | null };
export type PainelRenov = {
  total: number;
  porOpcao: { chave: string; rotulo: string; n: number }[];
  aplicaramEPagaram: number;
  vendas: { oferta: string; rotulo: string; vendas: number; valor: number }[];
  aplicacoes: AplicacaoRenov[];
  ultimasVendas: VendaRenov[];
  veContato: boolean;
};

const n = (v: unknown) => (typeof v === 'number' ? v : Number(v) || 0);
const s = (v: unknown) => (typeof v === 'string' ? v : null);
const lista = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? (v as Record<string, unknown>[]) : []);

export const rotuloOpcaoRenov = (chave: string) => OPCOES_RENOV.find((o) => o.chave === chave)?.rotulo ?? chave;

export function mapearPainelRenov(bruto: unknown): PainelRenov {
  const r = (bruto ?? {}) as Record<string, unknown>;
  const porOpcao = (r.por_opcao ?? {}) as Record<string, unknown>;
  return {
    total: n(r.aplicacoes_total),
    porOpcao: OPCOES_RENOV.map((o) => ({ chave: o.chave, rotulo: o.rotulo, n: n(porOpcao[o.chave]) })),
    aplicaramEPagaram: n(r.aplicaram_e_pagaram),
    vendas: lista(r.vendas).map((v) => ({ oferta: String(v.oferta), rotulo: OFERTAS_RENOV[String(v.oferta)] ?? String(v.oferta), vendas: n(v.vendas), valor: n(v.valor) })),
    aplicacoes: lista(r.aplicacoes).map((a) => ({
      criadoEm: String(a.criado_em), opcao: String(a.opcao), origem: s(a.origem) ?? '', pagou: a.pagou === true,
      nome: s(a.nome), email: s(a.email), telefone: s(a.telefone),
    })),
    ultimasVendas: lista(r.ultimas_vendas).map((v) => ({
      em: String(v.em), oferta: String(v.oferta), valor: n(v.valor), aplicou: v.aplicou === true, nome: s(v.nome), email: s(v.email),
    })),
    veContato: r.ve_contato === true,
  };
}
