// Catálogo de DEMONSTRAÇÃO no formato do que a sincronização da Hotmart grava (fin.produtos / fin.ofertas).
// Ids e códigos fictícios. No backend real, estas listas vêm do banco; o CRM só acrescenta os campos do comercial.
import { linkCheckout as link } from '../domain/hotmart';
import type { OfertaHotmart, OfertaOrfa, ProdutoHotmart } from '../domain/types';

const agora = Date.now();
const diasAtras = (d: number) => new Date(agora - d * 86400_000).toISOString();

const P = (produtoId: string, nomeHotmart: string, familia: string, conta: ProdutoHotmart['conta'], vinc: Partial<ProdutoHotmart> = {}): ProdutoHotmart => ({
  produtoId, nomeHotmart, familia, conta, noComercial: false, nomeComercial: null, produtoKey: null, agrupadorId: null, escada: null,
  sincronizadoEm: diasAtras(0.2), ...vinc,
});

export const PRODUTOS_DEMO: ProdutoHotmart[] = [
  P('3810021', 'HOLDING TOTAL - IMERSÃO 3 DIAS', 'HT', 'academy', { noComercial: true, nomeComercial: 'Holding Total', produtoKey: 'ht', agrupadorId: 'ag-ht', escada: 'B' }),
  P('4120577', 'HOLDING MASTERS - IMPLEMENTAÇÃO ASSISTIDA', 'HM', 'academy', { noComercial: true, nomeComercial: 'Holding Masters', produtoKey: 'hm', agrupadorId: 'ag-hm', escada: 'B' }),
  P('4120578', 'HOLDING MASTERS - RESERVA', 'HM', 'academy', { noComercial: true, nomeComercial: 'Holding Masters · reserva', produtoKey: 'hm', agrupadorId: 'ag-hm', escada: 'B' }),
  P('3992110', 'AURUM - MENTORIA PRESENCIAL', 'AURUM', 'academy', { noComercial: true, nomeComercial: 'Aurum', produtoKey: 'aurum', agrupadorId: 'ag-aurum', escada: 'B' }),
  P('4301888', 'ACELERA HOLDING', 'ACELERA', 'academy', { noComercial: true, nomeComercial: 'Acelera Holding', produtoKey: 'acelera', agrupadorId: 'ag-acelera', escada: 'B' }),
  P('4205513', 'ETHB - ENCONTRO TIME HOLDING BRASIL', 'EVENTOS', 'academy'),
  P('4402990', 'SESSÃO DE VIABILIDADE PATRIMONIAL', 'ESCRITORIO', 'escritorio', { noComercial: true, nomeComercial: 'Sessão de Viabilidade', produtoKey: 'sv', agrupadorId: 'ag-escritorio', escada: 'A' }),
  P('4402991', 'CROQUI ESTRUTURAL', 'ESCRITORIO', 'escritorio'),
  P('3700145', 'CLÍNICA DE HOLDING', 'EVENTOS', 'academy'),
  P('3500012', 'PROGRAMA DIAMANTE (LEGADO)', 'DIAMANTE', 'academy'),
  P('4455001', 'APOSTILA HOLDING FAMILIAR', 'OUTROS', 'academy'),
];

const O = (codigo: string, produtoId: string, nomeHotmart: string, preco: number, modo: string, extra: Partial<OfertaHotmart> = {}): OfertaHotmart => ({
  codigo, produtoId, nomeHotmart, preco, moeda: 'BRL', modo, principal: false, linkCheckout: link(codigo),
  vigente: false, condicao: null, validaAte: null, uso: null, transacoes: 0, ultimaVendaEm: null, vistaEm: diasAtras(0.2), ...extra,
});

export const OFERTAS_DEMO: OfertaHotmart[] = [
  O('ht33lote1', '3810021', 'HT33 · Lote 1', 297, 'UNIQUE_PAYMENT', { principal: true, vigente: true, condicao: 'R$ 297 à vista ou 12x', uso: 'Carrinho HT33 Meteórico', transacoes: 418, ultimaVendaEm: diasAtras(0.5) }),
  O('ht33lote2', '3810021', 'HT33 · Lote 2', 397, 'UNIQUE_PAYMENT', { transacoes: 96, ultimaVendaEm: diasAtras(9), uso: 'Virada de lote' }),
  O('htbf26', '3810021', 'HT · Black Friday 26', 197, 'UNIQUE_PAYMENT', { uso: 'Black Friday (03/11)', validaAte: '2026-11-30' }),
  O('hm30k12x', '4120577', 'HM · 1ª metade 12x', 15000, 'HOTMART_INSTALLMENTS_UNIQUE_LINK', { principal: true, vigente: true, condicao: '1ª metade R$ 15 mil em 12x de R$ 1.461 · 2ª metade só depois de R$ 150 mil faturados', uso: 'Pitch da Imersão e venda ativa', transacoes: 37, ultimaVendaEm: diasAtras(1) }),
  O('hmavista', '4120577', 'HM · à vista Pix', 13500, 'PAY_IN_FULL', { vigente: true, condicao: 'À vista com desconto de 10% (contrapartida: pagamento na hora)', transacoes: 6, ultimaVendaEm: diasAtras(4) }),
  O('hmboleto', '4120577', 'HM · boleto parcelado', 15000, 'FINANCED_BILLET', { transacoes: 17, ultimaVendaEm: diasAtras(12), uso: 'Só com aprovação do gestor' }),
  O('hmreserva300', '4120578', 'HM · Reserva', 300, 'UNIQUE_PAYMENT', { principal: true, vigente: true, condicao: 'Reserva de R$ 300, abatida da 1ª parcela', transacoes: 54, ultimaVendaEm: diasAtras(0.3) }),
  O('aurum100k', '3992110', 'Aurum · 12x', 100000, 'HOTMART_INSTALLMENTS_UNIQUE_LINK', { principal: true, vigente: true, condicao: '12x no cartão ou boleto financiado', transacoes: 15, ultimaVendaEm: diasAtras(20) }),
  O('aurumassin', '3992110', 'Aurum · assinatura (legado)', 8900, 'SUBSCRIPTION', { transacoes: 140, ultimaVendaEm: diasAtras(160) }),
  O('acl1997', '4301888', 'Acelera · lote 1', 1997, 'UNIQUE_PAYMENT', { principal: true, transacoes: 212, ultimaVendaEm: diasAtras(38) }),
  O('acl2497', '4301888', 'Acelera · lote 2', 2497, 'UNIQUE_PAYMENT', { transacoes: 101, ultimaVendaEm: diasAtras(36) }),
  O('acl2997', '4301888', 'Acelera · lote 3', 2997, 'UNIQUE_PAYMENT', { transacoes: 70, ultimaVendaEm: diasAtras(34) }),
  O('ethb497', '4205513', 'ETHB · pista', 497, 'UNIQUE_PAYMENT', { principal: true, transacoes: 88, ultimaVendaEm: diasAtras(55) }),
  O('ethb1997', '4205513', 'ETHB · VIP', 1997, 'UNIQUE_PAYMENT', { transacoes: 21, ultimaVendaEm: diasAtras(55) }),
  O('sv1200', '4402990', 'Sessão de Viabilidade', 1200, 'UNIQUE_PAYMENT', { principal: true, vigente: true, condicao: 'R$ 1.200 (tabela R$ 4.800), abatido no croqui', transacoes: 31, ultimaVendaEm: diasAtras(2) }),
  O('sv3000', '4402990', 'Sessão de Viabilidade (set/26)', 3000, 'UNIQUE_PAYMENT', { transacoes: 4, ultimaVendaEm: diasAtras(25), uso: 'Preço do Seminário de setembro: divergente do arquivo do produto' }),
  O('croqui', '4402991', 'Croqui estrutural', 9800, 'UNIQUE_PAYMENT', { principal: true }),
  O('clinica997', '3700145', 'Clínica · lote 1', 997, 'UNIQUE_PAYMENT', { principal: true, transacoes: 64, ultimaVendaEm: diasAtras(90) }),
  O('diam01', '3500012', 'Diamante (legado)', 2400, 'SUBSCRIPTION', { principal: true, transacoes: 320, ultimaVendaEm: diasAtras(400) }),
  O('apost47', '4455001', 'Apostila', 47, 'UNIQUE_PAYMENT', { principal: true, transacoes: 1203, ultimaVendaEm: diasAtras(1) }),
];

export const ORFAS_DEMO: OfertaOrfa[] = [
  { codigo: 'x9acl4live', produtoId: '4301888', transacoes: 436, ultimaEm: diasAtras(33) },
  { codigo: 'hmpix10', produtoId: '4120577', transacoes: 12, ultimaEm: diasAtras(3) },
  { codigo: 'k2ht33vip', produtoId: '3810021', transacoes: 5, ultimaEm: diasAtras(1) },
  { codigo: 'zz71q0', produtoId: null, transacoes: 2, ultimaEm: diasAtras(70) },
];
