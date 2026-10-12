// Perfil dos leads com filtro cruzado (pedido do Victor, 12/10): qualquer recorte (geral, funil, etapa, isca,
// conjunto) vira contagem por dimensão; clicar num valor filtra o resto. A lista de dimensões é configurável:
// campo novo do lead entra com uma linha em DIMENSOES_PERFIL.
// Conta CADASTROS (uma linha por porta). Pessoas únicas aparecem à parte, no resumo.
import { UFS, type Regiao } from './geo-brasil';
import { diaDe } from './recorte';
import {
  NAO_INFORMADO, ROTULO_CANAL, ROTULO_CONJUNTO_C3, ROTULO_FUNIL, ROTULO_ORIGEM, ROTULO_PORTA, ROTULO_PROFISSAO,
  type LinhaPerfil, type Pagina,
} from './tipos';

/** Chave de "sem valor" (vira "Não informado" na tela). */
export const SEM_VALOR = '__sem__';

export type DimensaoId =
  | 'profissao' | 'regiao' | 'uf' | 'utmSource' | 'pagina' | 'listaOrigem' | 'temperaturaBase' | 'porta' | 'isca'
  | 'funil' | 'conjuntoC3' | 'origem' | 'canal';

export interface Dimensao {
  id: DimensaoId;
  titulo: string;
  /** Nota curta da origem do dado (vai na dica). */
  nota?: string;
  valor: (l: LinhaPerfil) => string | null;
  /** Rótulo do valor. Padrão: o próprio valor (string exata da fonte). */
  rotulo?: (v: string, ctx: ContextoPerfil) => string;
}

export interface ContextoPerfil { paginas: ReadonlyMap<string, Pagina> }

const REGIAO_DA_UF = new Map<string, Regiao>(UFS.map((u) => [u.sigla, u.regiao]));
export const REGIOES: readonly Regiao[] = ['Norte', 'Nordeste', 'Centro-Oeste', 'Sudeste', 'Sul'];
export const regiaoDaUf = (uf: string | null): Regiao | null => (uf ? REGIAO_DA_UF.get(uf) ?? null : null);

export const DIMENSOES_PERFIL: readonly Dimensao[] = [
  { id: 'profissao', titulo: 'Profissão', valor: (l) => l.profissao, rotulo: (v) => ROTULO_PROFISSAO[v as keyof typeof ROTULO_PROFISSAO] ?? v },
  { id: 'regiao', titulo: 'Região', nota: 'Estado pelo DDD do telefone', valor: (l) => regiaoDaUf(l.uf) ?? (l.uf ? l.uf : null) },
  { id: 'uf', titulo: 'Estado', nota: 'Estado pelo DDD do telefone', valor: (l) => l.uf },
  { id: 'funil', titulo: 'Funil', valor: (l) => l.funil, rotulo: (v) => ROTULO_FUNIL[v as keyof typeof ROTULO_FUNIL] ?? v },
  { id: 'porta', titulo: 'Porta', valor: (l) => l.porta, rotulo: (v) => ROTULO_PORTA[v as keyof typeof ROTULO_PORTA] ?? v },
  { id: 'isca', titulo: 'Isca', valor: (l) => l.isca },
  { id: 'conjuntoC3', titulo: 'Conjunto do C3', valor: (l) => l.conjuntoC3, rotulo: (v) => ROTULO_CONJUNTO_C3[v as keyof typeof ROTULO_CONJUNTO_C3] ?? v },
  { id: 'origem', titulo: 'Origem', valor: (l) => l.origem, rotulo: (v) => ROTULO_ORIGEM[v as keyof typeof ROTULO_ORIGEM] ?? v },
  { id: 'canal', titulo: 'Canal', valor: (l) => l.canal, rotulo: (v) => ROTULO_CANAL[v as keyof typeof ROTULO_CANAL] ?? v },
  { id: 'utmSource', titulo: 'utm_source', valor: (l) => l.utmSource },
  { id: 'pagina', titulo: 'Página de origem', valor: (l) => l.paginaId, rotulo: (v, ctx) => ctx.paginas.get(v)?.url ?? v },
  { id: 'listaOrigem', titulo: 'Base de origem', valor: (l) => l.listaOrigem },
  { id: 'temperaturaBase', titulo: 'Temperatura da base', valor: (l) => l.temperaturaBase },
];
export const DIMENSAO = new Map(DIMENSOES_PERFIL.map((d) => [d.id, d]));

export const chaveDe = (d: Dimensao, l: LinhaPerfil) => d.valor(l) ?? SEM_VALOR;
export function rotuloDe(d: Dimensao, v: string, ctx: ContextoPerfil): string {
  if (v === SEM_VALOR) return NAO_INFORMADO;
  return d.rotulo ? d.rotulo(v, ctx) : v;
}

/** Filtro do perfil, na ordem em que foi clicado (a trilha mostra a contagem a cada passo). */
export interface FiltroPerfilItem { dim: DimensaoId; valor: string }
export type FiltroPerfil = readonly FiltroPerfilItem[];

export function aplicarPerfil(linhas: readonly LinhaPerfil[], filtro: FiltroPerfil, exceto?: DimensaoId): LinhaPerfil[] {
  const ativos = filtro.filter((f) => f.dim !== exceto);
  if (ativos.length === 0) return [...linhas];
  const dims = ativos.map((f) => ({ d: DIMENSAO.get(f.dim)!, v: f.valor }));
  return linhas.filter((l) => dims.every(({ d, v }) => chaveDe(d, l) === v));
}

/** Liga ou desliga um valor. Valor novo numa dimensão já filtrada troca o anterior. Região nova solta a UF de outra região. */
export function alternarPerfil(filtro: FiltroPerfil, item: FiltroPerfilItem): FiltroPerfil {
  const atual = filtro.find((f) => f.dim === item.dim);
  if (atual && atual.valor === item.valor) {
    // Tirar a região tira a UF junto (encadeadas).
    return filtro.filter((f) => f.dim !== item.dim && !(item.dim === 'regiao' && f.dim === 'uf'));
  }
  let novo = filtro.filter((f) => f.dim !== item.dim);
  if (item.dim === 'regiao') novo = novo.filter((f) => f.dim !== 'uf' || regiaoDaUf(f.valor) === item.valor);
  return [...novo, item];
}

export interface Contagem { valor: string; rotulo: string; quantidade: number }
/**
 * Contagem por valor da dimensão, com todos os OUTROS filtros aplicados (filtro cruzado: o valor escolhido
 * continua vendo os irmãos). Ordem: maior primeiro, "Não informado" no fim.
 */
export function contarPor(linhas: readonly LinhaPerfil[], dimId: DimensaoId, filtro: FiltroPerfil, ctx: ContextoPerfil): Contagem[] {
  const d = DIMENSAO.get(dimId)!;
  const base = aplicarPerfil(linhas, filtro, dimId);
  const n = new Map<string, number>();
  for (const l of base) { const k = chaveDe(d, l); n.set(k, (n.get(k) ?? 0) + 1); }
  return [...n.entries()]
    .map(([valor, quantidade]) => ({ valor, rotulo: rotuloDe(d, valor, ctx), quantidade }))
    .sort((a, b) => (a.valor === SEM_VALOR ? 1 : b.valor === SEM_VALOR ? -1 : b.quantidade - a.quantidade || a.rotulo.localeCompare(b.rotulo, 'pt-BR')));
}

export interface PassoTrilha { item: FiltroPerfilItem | null; rotulo: string; quantidade: number }
/** "1.000 → 412 → 180": contagem depois de cada filtro, na ordem dos cliques. */
export function trilhaPerfil(linhas: readonly LinhaPerfil[], filtro: FiltroPerfil, ctx: ContextoPerfil): PassoTrilha[] {
  const out: PassoTrilha[] = [{ item: null, rotulo: 'Todos', quantidade: linhas.length }];
  let atual: readonly LinhaPerfil[] = linhas;
  for (const f of filtro) {
    const d = DIMENSAO.get(f.dim)!;
    atual = atual.filter((l) => chaveDe(d, l) === f.valor);
    out.push({ item: f, rotulo: `${d.titulo}: ${rotuloDe(d, f.valor, ctx)}`, quantidade: atual.length });
  }
  return out;
}

/** Cadastros por dia (sub-aba Evolução). Dia de São Paulo. */
export function evolucaoPorDia(linhas: readonly LinhaPerfil[], dias: readonly string[]): { dia: string; quantidade: number }[] {
  const n = new Map<string, number>();
  for (const l of linhas) { const k = diaDe(l.criadoEm); n.set(k, (n.get(k) ?? 0) + 1); }
  return dias.map((dia) => ({ dia, quantidade: n.get(dia) ?? 0 }));
}

/** Leads por UF para o mapa. `semUf` = sem DDD legível; 'Outros' = DDD fora da tabela dados.ddd_uf. */
export function porUf(linhas: readonly LinhaPerfil[]): { porUf: Map<string, number>; semUf: number; outros: number } {
  const m = new Map<string, number>();
  let semUf = 0; let outros = 0;
  for (const l of linhas) {
    if (l.uf === null) semUf += 1;
    else if (!REGIAO_DA_UF.has(l.uf)) outros += 1;
    else m.set(l.uf, (m.get(l.uf) ?? 0) + 1);
  }
  return { porUf: m, semUf, outros };
}

/** Raio da bolha: sqrt(n/max) × 28 (plano, seção 4). Zero = 0 (a tela desenha ponto cinza). */
export const raioBolha = (n: number, maximo: number, teto = 28) => (n <= 0 || maximo <= 0 ? 0 : Math.sqrt(n / maximo) * teto);
