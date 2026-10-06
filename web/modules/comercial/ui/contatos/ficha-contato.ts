// Regras puras da ficha da pessoa e da lista de contatos: resumo da relação com a casa, filtro da jornada
// por tipo de ponto, ordem dos negócios e índice de lançamentos/última interação. Sem React, testáveis.
import { ROTULO_TIPO_JORNADA, resumoJornada, type BlocoLancamento } from '../../domain/jornada';
import type { Negocio, PontoJornada, TipoPontoJornada, Utm } from '../../domain/types';

export interface ResumoFicha {
  /** Comprou ao menos uma vez (ou já é aluno): "Cliente desde"; senão "Lead desde". */
  cliente: boolean;
  /** Primeira compra (cliente) ou primeiro contato com a casa (lead). */
  desde: string | null;
  lancamentos: number;
  compras: number;
  /** Pago líquido: compras menos reembolsos. */
  valorPago: number;
  reembolsos: number;
  negociosAbertos: number;
  negociosTotal: number;
}

/** Resumo do cabeçalho da ficha: jornada + negócios + data de cadastro. */
export function resumoFicha(
  pontos: PontoJornada[],
  negocios: Pick<Negocio, 'status'>[],
  contato: { criadoEm: string; ehAluno: boolean },
): ResumoFicha {
  const r = resumoJornada(pontos);
  const primeiraCompra = pontos.filter((p) => p.tipo === 'compra').map((p) => p.em).sort()[0] ?? null;
  const primeiroContato = [r.desde, contato.criadoEm].filter((x): x is string => !!x).sort()[0] ?? null;
  const cliente = !!primeiraCompra || contato.ehAluno;
  return {
    cliente,
    desde: primeiraCompra ?? primeiroContato,
    lancamentos: r.lancamentos,
    compras: r.compras,
    valorPago: r.valorPago,
    reembolsos: r.reembolsos,
    negociosAbertos: negocios.filter((n) => n.status === 'aberto').length,
    negociosTotal: negocios.length,
  };
}

/** Tipos de ponto presentes na jornada, na ordem do catálogo, com quantos de cada (chips de filtro). */
export function tiposPresentes(pontos: Pick<PontoJornada, 'tipo'>[]): { tipo: TipoPontoJornada; n: number }[] {
  const conta = new Map<TipoPontoJornada, number>();
  for (const p of pontos) conta.set(p.tipo, (conta.get(p.tipo) ?? 0) + 1);
  return (Object.keys(ROTULO_TIPO_JORNADA) as TipoPontoJornada[])
    .filter((t) => conta.has(t))
    .map((t) => ({ tipo: t, n: conta.get(t)! }));
}

/**
 * Filtra os pontos dos blocos pelos tipos escolhidos (vazio = todos). Bloco sem ponto que sobre sai da lista;
 * o resumo do bloco (entrada, comprou, valor) continua o do lançamento inteiro.
 */
export function filtrarBlocos(blocos: BlocoLancamento[], tipos: TipoPontoJornada[]): BlocoLancamento[] {
  if (!tipos.length) return blocos;
  const set = new Set(tipos);
  return blocos
    .map((b) => ({ ...b, pontos: b.pontos.filter((p) => set.has(p.tipo)) }))
    .filter((b) => b.pontos.length > 0);
}

/** Chave estável do bloco (lançamento ou "sem lançamento"). */
export function chaveBloco(b: Pick<BlocoLancamento, 'lancamento'>): string {
  return b.lancamento ?? '__sem_lancamento';
}

/** Os três lançamentos mais recentes começam abertos; os antigos, recolhidos. */
export const BLOCOS_ABERTOS_PADRAO = 3;

/** Bloco está aberto? `alternados` guarda os que a pessoa inverteu em relação ao padrão. */
export function blocoAberto(indice: number, chave: string, alternados: ReadonlySet<string>): boolean {
  const padrao = indice < BLOCOS_ABERTOS_PADRAO;
  return alternados.has(chave) ? !padrao : padrao;
}

/** "Expandir tudo"/"Recolher tudo": devolve o conjunto de alternados que deixa todos no estado pedido. */
export function alternadosPara(abrir: boolean, chaves: string[]): Set<string> {
  return new Set(chaves.filter((k, i) => (i < BLOCOS_ABERTOS_PADRAO) !== abrir));
}

/** UTM de uma entrada em pares rótulo/valor (source, medium, campaign, content), só os preenchidos. */
export function paresUtm(utm: Utm | null | undefined): { k: string; v: string }[] {
  if (!utm) return [];
  const pares: [string, string | null | undefined][] = [
    ['source', utm.source], ['medium', utm.medium], ['campaign', utm.campaign], ['content', utm.content],
  ];
  return pares.filter(([, v]) => !!v && !!v.trim()).map(([k, v]) => ({ k, v: v!.trim() }));
}

/** Negócios da pessoa: abertos primeiro; dentro de cada grupo, o mais recente antes. */
export function ordenarNegocios<T extends Pick<Negocio, 'status' | 'criadoEm' | 'fechadoEm'>>(negocios: T[]): T[] {
  const ref = (n: T) => n.fechadoEm ?? n.criadoEm;
  return [...negocios].sort(
    (a, b) => (a.status === 'aberto' ? 0 : 1) - (b.status === 'aberto' ? 0 : 1) || ref(b).localeCompare(ref(a)),
  );
}

export interface IndiceContato {
  lancamentos: number;
  ultimaEm: string | null;
}

/**
 * Para a lista: quantos lançamentos cada pessoa já fez e a última interação (o ponto mais recente da jornada
 * ou a última interação registrada num negócio, o que vier depois).
 */
export function indiceContatos(
  pontosPorContato: Map<string, Pick<PontoJornada, 'em' | 'lancamento'>[]>,
  negocios: Pick<Negocio, 'contatoId' | 'ultimaInteracaoEm'>[],
): Map<string, IndiceContato> {
  const mapa = new Map<string, IndiceContato>();
  const max = (a: string | null, b: string | null) => (!a ? b : !b ? a : a > b ? a : b);
  for (const [id, pontos] of pontosPorContato) {
    const lancs = new Set(pontos.map((p) => p.lancamento).filter((x): x is string => !!x));
    const ultima = pontos.reduce<string | null>((m, p) => max(m, p.em), null);
    mapa.set(id, { lancamentos: lancs.size, ultimaEm: ultima });
  }
  for (const n of negocios) {
    const atual = mapa.get(n.contatoId) ?? { lancamentos: 0, ultimaEm: null };
    mapa.set(n.contatoId, { ...atual, ultimaEm: max(atual.ultimaEm, n.ultimaInteracaoEm) });
  }
  return mapa;
}
