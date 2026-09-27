// Junta a configuração de ofertas (cobrança de saldo, cs.ofertas via fn_fin_ofertas)
// com o desempenho de vendas no espelho da Hotmart (fn_fin_hotmart_ofertas), por
// código de oferta. Pura — sem I/O. Usada pela aba Ofertas (ui/Ofertas.tsx) para
// mostrar as duas fontes numa tabela só, sem somar bruto/líquido com "usos".
import type { Oferta } from './types';
import type { OfertaHotmart } from './hotmart';

/** Uma linha da junção — código de oferta com o que existe de configuração e/ou venda. */
export interface OfertaJunta {
  /** Código como apareceu na primeira ocorrência (trim aplicado, case original preservado). */
  codigo: string;
  temConfig: boolean;
  temVenda: boolean;

  // ── Configuração (cs.ofertas / fn_fin_ofertas) — "Usos (board)" ──────────
  valorConfig: number | null;
  recorrente: boolean | null;
  link: string | null;
  ativoConfig: boolean | null;
  /** Usos no board (cs.contatos_hm que referenciam esta oferta) — NÃO é venda paga. */
  usosBoard: number | null;
  papel: string | null;

  // ── Vendas (espelho Hotmart) — "Vendas pagas (Hotmart)" ──────────────────
  produto: string | null;
  papelProduto: string | null;
  modoPagamento: string | null;
  precoOferta: number | null;
  vendasPagas: number;
  estornos: number;
  recusadas: number;
  receitaBruta: number;
  receitaLiquida: number;
  primeiraVenda: string | null;
  ultimaVenda: string | null;
  categoriaCatalogo: string | null;
  papelCatalogo: string | null;
  nomeComercial: string | null;
  noCatalogo: boolean | null;
  ativaHotmart: boolean | null;
}

/** Normaliza para casar código entre as duas fontes: trim + minúsculas. */
function normalizar(codigo: string): string {
  return codigo.trim().toLowerCase();
}

function linhaBase(codigoExibido: string): OfertaJunta {
  return {
    codigo: codigoExibido.trim(),
    temConfig: false,
    temVenda: false,
    valorConfig: null,
    recorrente: null,
    link: null,
    ativoConfig: null,
    usosBoard: null,
    papel: null,
    produto: null,
    papelProduto: null,
    modoPagamento: null,
    precoOferta: null,
    vendasPagas: 0,
    estornos: 0,
    recusadas: 0,
    receitaBruta: 0,
    receitaLiquida: 0,
    primeiraVenda: null,
    ultimaVenda: null,
    categoriaCatalogo: null,
    papelCatalogo: null,
    nomeComercial: null,
    noCatalogo: null,
    ativaHotmart: null,
  };
}

const menorData = (a: string | null, b: string | null): string | null => {
  if (!a) return b;
  if (!b) return a;
  return a < b ? a : b;
};
const maiorData = (a: string | null, b: string | null): string | null => {
  if (!a) return b;
  if (!b) return a;
  return a > b ? a : b;
};

/**
 * Junção completa (full outer) por código de oferta normalizado. Cada código
 * normalizado gera UMA linha. Config duplicada (mesmo código, grafia
 * diferente) faz a última entrada prevalecer nos campos de configuração;
 * vendas duplicadas somam os números e widen a janela primeira/última venda —
 * nenhuma fonte real duplica hoje, mas normalizar sem isso perderia dado em
 * silêncio se algum dia duplicar.
 */
export function juntarOfertas(config: Oferta[], vendas: OfertaHotmart[]): OfertaJunta[] {
  const porCodigo = new Map<string, OfertaJunta>();

  for (const o of config) {
    const chave = normalizar(o.codigo);
    const linha = porCodigo.get(chave) ?? linhaBase(o.codigo);
    linha.temConfig = true;
    linha.valorConfig = o.valor;
    linha.recorrente = o.recorrente;
    linha.link = o.link;
    linha.ativoConfig = o.ativo;
    linha.usosBoard = o.usos;
    linha.papel = o.papel ?? null;
    porCodigo.set(chave, linha);
  }

  for (const v of vendas) {
    const chave = normalizar(v.oferta_codigo);
    const linha = porCodigo.get(chave) ?? linhaBase(v.oferta_codigo);
    linha.temVenda = true;
    linha.produto = v.produto;
    linha.papelProduto = v.papel_produto;
    linha.modoPagamento = v.modo_pagamento;
    linha.precoOferta = v.preco_oferta;
    linha.vendasPagas += v.vendas_pagas;
    linha.estornos += v.estornos;
    linha.recusadas += v.recusadas;
    linha.receitaBruta += v.receita_oferta;
    linha.receitaLiquida += v.receita_liquida;
    linha.primeiraVenda = menorData(linha.primeiraVenda, v.primeira_venda);
    linha.ultimaVenda = maiorData(linha.ultimaVenda, v.ultima_venda);
    linha.categoriaCatalogo = v.categoria_catalogo;
    linha.papelCatalogo = v.papel_catalogo;
    linha.nomeComercial = v.nome_comercial;
    linha.noCatalogo = v.no_catalogo;
    linha.ativaHotmart = v.ativa;
    porCodigo.set(chave, linha);
  }

  return [...porCodigo.values()];
}
