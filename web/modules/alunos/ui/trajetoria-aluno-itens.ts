// Mapeamento puro: marcos da trajetória do aluno → modelo visual da TrajetoriaMarcos compartilhada. Separado do
// componente para ser testável.
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { MarcoVisual, PontoRegua } from '@/shared/ui/timeline';
import { DIMENSOES_TRAJETORIA, ROTULO_DIMENSAO, type LinhaTrajetoriaAluno } from '../domain/trajetoria-aluno';
import {
  agruparEmMarcos, diasDeSaida, mesAno, posicaoNaRegua,
  type CapituloTrajetoria, type MarcoTrajetoria, type TipoMarco,
} from '../domain/trajetoria-marcos';

export const OPCOES_DIMENSAO = DIMENSOES_TRAJETORIA.map((d) => ({ chave: d, rotulo: ROTULO_DIMENSAO[d] }));

/** Ícone do nó: diz o tipo do marco (a cor diz só alerta/positivo/início). */
const ICONE_TIPO: Record<Exclude<TipoMarco, 'capitulo'>, string> = {
  entrada: 'user', compra: 'receipt', estorno: 'alert', saida: 'logout', volta: 'rotate',
  troca: 'arrow-right', nivel: 'medal', placa: 'trophy', outro: 'circle',
};
const ICONE_CAPITULO: Record<CapituloTrajetoria, string> = {
  central: 'cursos', gps: 'trending-up', card_hm: 'briefcase', grupos: 'users', socios: 'link', acesso: 'lock', eventos: 'calendar',
};

const quando = (m: MarcoTrajetoria) => {
  if (m.tipo !== 'capitulo') return fmtData(m.inicio);
  const n = `${m.itens.length} ${m.itens.length === 1 ? 'registro' : 'registros'}`;
  return m.inicio === m.fim ? `${fmtData(m.inicio)} · ${n}` : `${fmtData(m.inicio)} a ${fmtData(m.fim)} · ${n}`;
};

const nota = (l: LinhaTrajetoriaAluno) => [l.fonte, l.regra].filter(Boolean).join(' · ') || null;

export function paraMarcosVisuais(marcos: MarcoTrajetoria[]): MarcoVisual[] {
  return marcos.map((m) => ({
    id: m.id,
    titulo: m.titulo,
    quando: quando(m),
    resumo: m.resumo,
    // valor null = nada na tela (quem não vê o financeiro recebe null da RPC).
    valor: m.valor == null ? null : fmtBRL(m.valor),
    tom: m.tom,
    icone: m.capitulo ? ICONE_CAPITULO[m.capitulo] : ICONE_TIPO[m.tipo as Exclude<TipoMarco, 'capitulo'>],
    capitulo: m.tipo === 'capitulo',
    itens: m.itens.map((l, i) => ({
      id: `${l.dia}|${l.dimensao}|${l.tipo}|${l.ref ?? ''}|${i}`,
      quando: fmtData(l.dia),
      titulo: l.titulo,
      detalhe: l.detalhe,
      valor: l.valor == null ? null : fmtBRL(l.valor),
      situacao: l.situacao,
      nota: nota(l),
    })),
  }));
}

/** Régua: só marcos próprios (capítulos ficam fora para não poluir), de 1º marco até `ate`. */
export function pontosDaRegua(marcos: MarcoTrajetoria[], ate: string): { pontos: PontoRegua[]; de: string; ate: string } | null {
  const proprios = marcos.filter((m) => m.tipo !== 'capitulo');
  if (!proprios.length) return null;
  const de = marcos.reduce((min, m) => (m.inicio < min ? m.inicio : min), marcos[0].inicio);
  const fim = marcos.reduce((max, m) => (m.fim > max ? m.fim : max), ate);
  return {
    de: mesAno(de),
    ate: mesAno(fim),
    pontos: proprios.map((m) => ({ id: m.id, pos: posicaoNaRegua(m.inicio, de, fim), tom: m.tom, rotulo: `${m.titulo} (${fmtData(m.inicio)})` })),
  };
}

/** Filtro por dimensão no cliente, antes de agrupar (null = todas). */
export function marcosFiltrados(linhas: LinhaTrajetoriaAluno[], dimensao: string | null): MarcoTrajetoria[] {
  // Corte de capítulo pelas saídas da trajetória inteira: filtrar não junta "antes" e "depois" de sair.
  return agruparEmMarcos(dimensao ? linhas.filter((l) => l.dimensao === dimensao) : linhas, diasDeSaida(linhas));
}
