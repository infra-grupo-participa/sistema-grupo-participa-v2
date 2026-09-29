// Ofertas a confirmar (z82) — funções PURAS, sem I/O.
// O banco liga sozinho cada oferta da Hotmart a um evento; quando não tem certeza, a oferta vai para a fila
// (public.fn_fin_fila_ofertas) e alguém do Financeiro decide (public.fn_fin_decidir_oferta). Aqui só: tipar a linha da
// fila, montar os argumentos da decisão (exatamente UMA ação) e repetir as travas do "criar evento" para poupar uma ida
// ao banco — a trava de verdade é a RPC.

/** Evento proposto pelo banco quando nenhum evento existente cobre a 1ª venda. Campos podem vir nulos. */
export interface PropostaEvento {
  nome: string | null;
  categoria: string | null;
  carrinho_inicio: string | null;
  venda_ate: string | null;
}

export interface OfertaFila {
  oferta_codigo: string;
  oferta_nome: string | null;
  produto_id: string | null;
  produto_nome: string | null;
  n_vendas: number;
  primeira_venda: string | null;
  ultima_venda: string | null;
  sugestao_evento_id: number | null;
  sugestao_evento: string | null;
  proposta_evento: PropostaEvento | null;
  criado_em: string | null;
}

/** Payload de p_criar. Datas YYYY-MM-DD; fim/venda_ate/carrinho_inicio opcionais (a RPC completa fim = início). */
export interface NovoEvento {
  nome: string;
  categoria: string;
  inicio: string;
  fim?: string;
  venda_ate?: string;
  carrinho_inicio?: string;
}

export type DecisaoOferta =
  | { tipo: 'confirmar'; eventoId: number }
  | { tipo: 'criar'; evento: NovoEvento }
  | { tipo: 'rejeitar' };

const texto = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));
const idOuNull = (v: unknown): number | null => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));

function lerProposta(v: unknown): PropostaEvento | null {
  let bruto: unknown = v;
  if (typeof bruto === 'string') {
    try { bruto = JSON.parse(bruto); } catch { return null; }
  }
  if (bruto == null || typeof bruto !== 'object' || Array.isArray(bruto)) return null;
  const o = bruto as Record<string, unknown>;
  return { nome: texto(o.nome), categoria: texto(o.categoria), carrinho_inicio: dia(o.carrinho_inicio), venda_ate: dia(o.venda_ate) };
}

export function normalizarOfertaFila(r: Record<string, unknown>): OfertaFila {
  return {
    oferta_codigo: String(r.oferta_codigo ?? ''),
    oferta_nome: texto(r.oferta_nome),
    produto_id: texto(r.produto_id),
    produto_nome: texto(r.produto_nome),
    n_vendas: Number(r.n_vendas ?? 0) || 0,
    primeira_venda: dia(r.primeira_venda),
    ultima_venda: dia(r.ultima_venda),
    sugestao_evento_id: idOuNull(r.sugestao_evento_id),
    sugestao_evento: texto(r.sugestao_evento),
    proposta_evento: lerProposta(r.proposta_evento),
    criado_em: texto(r.criado_em),
  };
}

/** Nome que a tela mostra: o nome da oferta; sem nome, o código (nunca vazio). */
export const rotuloOferta = (o: Pick<OfertaFila, 'oferta_nome' | 'oferta_codigo'>) => o.oferta_nome ?? o.oferta_codigo;

/** Argumentos de fn_fin_decidir_oferta: exatamente UMA ação; as outras chaves nem são enviadas (default da RPC). */
export function argsDecidirOferta(codigo: string, d: DecisaoOferta): Record<string, unknown> {
  if (d.tipo === 'confirmar') return { p_oferta: codigo, p_evento_id: d.eventoId };
  if (d.tipo === 'rejeitar') return { p_oferta: codigo, p_rejeitar: true };
  const e: NovoEvento = { nome: d.evento.nome.trim(), categoria: d.evento.categoria.trim().toLowerCase(), inicio: d.evento.inicio };
  if (d.evento.fim) e.fim = d.evento.fim;
  if (d.evento.venda_ate) e.venda_ate = d.evento.venda_ate;
  if (d.evento.carrinho_inicio) e.carrinho_inicio = d.evento.carrinho_inicio;
  return { p_oferta: codigo, p_criar: e };
}

/** Formulário "Criar evento" (strings do input date: '' = vazio). */
export interface FormNovoEvento {
  nome: string;
  categoria: string;
  inicio: string;
  fim: string;
  carrinho_inicio: string;
  venda_ate: string;
}

/** Pré-preenche com a proposta do banco. A proposta não traz a data do evento: o início fica para quem decide. */
export function formDaProposta(o: Pick<OfertaFila, 'proposta_evento' | 'oferta_nome' | 'produto_nome'>): FormNovoEvento {
  const p = o.proposta_evento;
  return {
    nome: p?.nome ?? o.oferta_nome ?? o.produto_nome ?? '',
    categoria: p?.categoria ?? '',
    inicio: '',
    fim: '',
    carrinho_inicio: p?.carrinho_inicio ?? '',
    venda_ate: p?.venda_ate ?? '',
  };
}

export const CATEGORIA_EVENTO_RE = /^[a-z][a-z0-9_]{1,39}$/;
const ISO = /^\d{4}-\d{2}-\d{2}$/;

/** Mesmas travas de fn_fin_decidir_oferta (p_criar). Lista vazia = pode enviar. */
export function validarNovoEvento(f: FormNovoEvento): string[] {
  const erros: string[] = [];
  const nome = f.nome.trim();
  if (!nome || nome.length > 200) erros.push('Informe o nome do evento (até 200 caracteres).');
  if (!CATEGORIA_EVENTO_RE.test(f.categoria.trim().toLowerCase())) {
    erros.push('Categoria: só letras minúsculas, números e _ (ex.: holding_total).');
  }
  if (!ISO.test(f.inicio)) { erros.push('Informe a data do evento.'); return erros; }
  const fim = f.fim || f.inicio;
  if (fim < f.inicio) erros.push('O fim do evento não pode ser antes do início.');
  const ate = f.venda_ate || fim;
  if (f.carrinho_inicio && f.carrinho_inicio > ate) erros.push('A abertura das vendas não pode ser depois do fim das vendas.');
  return erros;
}

export function novoEventoDoForm(f: FormNovoEvento): NovoEvento {
  return {
    nome: f.nome, categoria: f.categoria, inicio: f.inicio,
    fim: f.fim || undefined, venda_ate: f.venda_ate || undefined, carrinho_inicio: f.carrinho_inicio || undefined,
  };
}
