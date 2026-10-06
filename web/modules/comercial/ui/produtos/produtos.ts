// Regras puras da tela "Produtos e ofertas". Produto e oferta nascem na Hotmart: aqui só se calcula o que
// mostrar (vigência, contagens, filtros) e se valida o que é do comercial (vínculo, oferta vigente).
import type { ContaHotmart, Escada, OfertaHotmart, OfertaOrfa, ProdutoHotmart, ProdutoKey } from '../../domain/types';

/** Modo de pagamento da Hotmart em português. Modo desconhecido volta como veio. */
export const ROTULO_MODO: Record<string, string> = {
  UNIQUE_PAYMENT: 'Pagamento único',
  SUBSCRIPTION: 'Assinatura',
  PAY_IN_FULL: 'À vista',
  HOTMART_INSTALLMENTS_UNIQUE_LINK: 'Parcelado (link único)',
  MULTIPLE_PAYMENTS: 'Múltiplos pagamentos',
  FINANCED_BILLET: 'Boleto financiado',
  BILLET_INSTALLMENT: 'Boleto parcelado',
};

export function rotuloModo(modo: string | null | undefined): string {
  if (!modo) return '—';
  return ROTULO_MODO[modo] ?? modo;
}

export const ROTULO_CONTA: Record<ContaHotmart, string> = { academy: 'Academy', escritorio: 'Escritório' };

export const ROTULO_ESCADA: Record<Escada, string> = { A: 'Escada A · serviço', B: 'Escada B · formação' };

/** 'YYYY-MM-DD' local de uma data (sem fuso UTC, que no Brasil volta um dia à noite). */
export function diaLocal(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** Oferta marcada vigente cuja validade já passou: não pode ser oferecida. */
export function ofertaVencida(o: Pick<OfertaHotmart, 'vigente' | 'validaAte'>, hojeISO: string): boolean {
  if (!o.vigente || !o.validaAte) return false;
  return o.validaAte.slice(0, 10) < hojeISO;
}

/** Vigente de verdade: marcada, dentro da validade e com o produto no comercial. */
export function ofertaValendo(o: Pick<OfertaHotmart, 'vigente' | 'validaAte'>, produtoNoComercial: boolean, hojeISO: string): boolean {
  return produtoNoComercial && o.vigente && !ofertaVencida(o, hojeISO);
}

export interface ResumoProduto {
  nOfertas: number;
  nVigentes: number;
  nVencidas: number;
  ultimaVendaEm: string | null;
  transacoes: number;
}

/** Contagens de um produto a partir das ofertas dele. */
export function resumoProduto(p: Pick<ProdutoHotmart, 'produtoId' | 'noComercial'>, ofertas: OfertaHotmart[], hojeISO: string): ResumoProduto {
  const minhas = ofertas.filter((o) => o.produtoId === p.produtoId);
  let ultima: string | null = null;
  for (const o of minhas) if (o.ultimaVendaEm && (!ultima || o.ultimaVendaEm > ultima)) ultima = o.ultimaVendaEm;
  return {
    nOfertas: minhas.length,
    nVigentes: minhas.filter((o) => ofertaValendo(o, p.noComercial, hojeISO)).length,
    nVencidas: minhas.filter((o) => p.noComercial && ofertaVencida(o, hojeISO)).length,
    ultimaVendaEm: ultima,
    transacoes: minhas.reduce((s, o) => s + o.transacoes, 0),
  };
}

export interface ResumoTela {
  noComercial: number;
  foraDoComercial: number;
  ofertasVigentes: number;
  ofertasVencidas: number;
  orfas: number;
  transacoesOrfas: number;
  semVigente: number;
}

/** Números da faixa do topo. */
export function resumoTela(produtos: ProdutoHotmart[], ofertas: OfertaHotmart[], orfas: OfertaOrfa[], hojeISO: string): ResumoTela {
  const vinculados = produtos.filter((p) => p.noComercial);
  const resumos = vinculados.map((p) => resumoProduto(p, ofertas, hojeISO));
  return {
    noComercial: vinculados.length,
    foraDoComercial: produtos.length - vinculados.length,
    ofertasVigentes: resumos.reduce((s, r) => s + r.nVigentes, 0),
    ofertasVencidas: resumos.reduce((s, r) => s + r.nVencidas, 0),
    orfas: orfas.length,
    transacoesOrfas: orfas.reduce((s, o) => s + o.transacoes, 0),
    semVigente: resumos.filter((r) => r.nVigentes === 0).length,
  };
}

export type Lado = 'comercial' | 'fora';

export interface FiltroProdutos {
  lado: Lado;
  conta: ContaHotmart | 'todas';
  familia: string | 'todas';
  busca: string;
  /** Só produtos do comercial sem oferta vigente (atalho da faixa de números). */
  semVigente: boolean;
}

export const FILTRO_INICIAL: FiltroProdutos = { lado: 'comercial', conta: 'todas', familia: 'todas', busca: '', semVigente: false };

/** Busca sem acento e sem caixa. */
export function normalizar(t: string): string {
  return t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

/** Aplica lado, conta, família, busca (nome, id ou código de oferta) e o atalho "sem vigente". */
export function filtrarProdutos(produtos: ProdutoHotmart[], ofertas: OfertaHotmart[], f: FiltroProdutos, hojeISO: string): ProdutoHotmart[] {
  const q = normalizar(f.busca);
  return produtos.filter((p) => {
    if (f.lado === 'comercial' ? !p.noComercial : p.noComercial) return false;
    if (f.conta !== 'todas' && p.conta !== f.conta) return false;
    if (f.familia !== 'todas' && (p.familia ?? '') !== f.familia) return false;
    if (f.semVigente && f.lado === 'comercial' && resumoProduto(p, ofertas, hojeISO).nVigentes > 0) return false;
    if (!q) return true;
    const textos = [p.nomeHotmart, p.nomeComercial ?? '', p.produtoId, p.familia ?? ''];
    for (const o of ofertas) if (o.produtoId === p.produtoId) textos.push(o.codigo, o.nomeHotmart ?? '');
    return textos.some((t) => normalizar(t).includes(q));
  });
}

/** Famílias presentes, em ordem alfabética (para o filtro). */
export function familias(produtos: ProdutoHotmart[]): string[] {
  return [...new Set(produtos.map((p) => p.familia).filter((f): f is string => !!f))].sort((a, b) => a.localeCompare(b));
}

export interface ItemCola {
  produto: ProdutoHotmart;
  vigentes: OfertaHotmart[];
}

/** "O que vender hoje": por produto do comercial, só as ofertas valendo (principal primeiro). */
export function colaDoVendedor(produtos: ProdutoHotmart[], ofertas: OfertaHotmart[], hojeISO: string): ItemCola[] {
  return produtos
    .filter((p) => p.noComercial)
    .map((p) => ({
      produto: p,
      vigentes: ofertas
        .filter((o) => o.produtoId === p.produtoId && ofertaValendo(o, true, hojeISO))
        .sort((a, b) => Number(b.principal) - Number(a.principal) || b.transacoes - a.transacoes),
    }))
    .sort((a, b) => Number(b.vigentes.length > 0) - Number(a.vigentes.length > 0)
      || (a.produto.nomeComercial ?? a.produto.nomeHotmart).localeCompare(b.produto.nomeComercial ?? b.produto.nomeHotmart));
}

// ── Vínculo ao comercial ──

export interface RascunhoVinculo {
  produtoId: string;
  nomeComercial: string;
  produtoKey: ProdutoKey | null;
  agrupadorId: string | null;
  escada: Escada | null;
}

export function rascunhoVinculo(p: ProdutoHotmart): RascunhoVinculo {
  return {
    produtoId: p.produtoId,
    nomeComercial: p.nomeComercial ?? '',
    produtoKey: p.produtoKey,
    agrupadorId: p.agrupadorId,
    escada: p.escada,
  };
}

export const LIMITE_NOME_COMERCIAL = 60;

/** Erros por campo; vazio = pode salvar. */
export function validarVinculo(r: RascunhoVinculo): Partial<Record<'nomeComercial' | 'escada', string>> {
  const e: Partial<Record<'nomeComercial' | 'escada', string>> = {};
  const nome = r.nomeComercial.trim();
  if (!nome) e.nomeComercial = 'Dê o nome que o comercial usa.';
  else if (nome.length > LIMITE_NOME_COMERCIAL) e.nomeComercial = `Até ${LIMITE_NOME_COMERCIAL} caracteres.`;
  if (!r.escada) e.escada = 'Escolha a escada: A (serviço) ou B (formação). Nunca misturar.';
  return e;
}

// ── Dados do comercial na oferta ──

export interface RascunhoOferta {
  codigo: string;
  vigente: boolean;
  condicao: string;
  validaAte: string;
  uso: string;
}

export function rascunhoOferta(o: OfertaHotmart): RascunhoOferta {
  return { codigo: o.codigo, vigente: o.vigente, condicao: o.condicao ?? '', validaAte: o.validaAte?.slice(0, 10) ?? '', uso: o.uso ?? '' };
}

/** Rascunho mudou em relação ao que está salvo. */
export function ofertaAlterada(r: RascunhoOferta, o: OfertaHotmart): boolean {
  const s = rascunhoOferta(o);
  return r.vigente !== s.vigente || r.condicao.trim() !== s.condicao.trim() || r.validaAte !== s.validaAte || r.uso.trim() !== s.uso.trim();
}

/** Vigente exige condição escrita (o vendedor precisa dela) e validade que não passou. */
export function validarOferta(r: RascunhoOferta, produtoNoComercial: boolean, hojeISO: string): string | null {
  if (!r.vigente) return null;
  if (!produtoNoComercial) return 'Vincule o produto ao comercial antes de marcar oferta vigente.';
  if (!r.condicao.trim()) return 'Oferta vigente precisa da condição escrita: é o que o vendedor fala.';
  if (r.validaAte && r.validaAte < hojeISO) return 'A validade já passou. Mude a data ou desmarque vigente.';
  return null;
}

/** Converte o rascunho no formato do repositório (texto vazio vira null). */
export function paraSalvar(r: RascunhoOferta): Pick<OfertaHotmart, 'codigo' | 'vigente' | 'condicao' | 'validaAte' | 'uso'> {
  return {
    codigo: r.codigo,
    vigente: r.vigente,
    condicao: r.condicao.trim() || null,
    validaAte: r.validaAte || null,
    uso: r.uso.trim() || null,
  };
}

/** Ofertas fora do catálogo: mais transações primeiro (o maior buraco no pagamento). */
export function ordenarOrfas(orfas: OfertaOrfa[]): OfertaOrfa[] {
  return [...orfas].sort((a, b) => b.transacoes - a.transacoes || b.ultimaEm.localeCompare(a.ultimaEm));
}
