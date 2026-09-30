// Aba Escritório · Funil (z92): 1 RPC (fn_fin_escritorio_funil) na 1ª vez que a aba abre e 1 RPC
// (fn_fin_escritorio_funil_pessoas) na 1ª vez que cada linha é aberta. Voltar à aba ou reabrir a mesma linha não
// consulta de novo. Falha não fica guardada (a próxima tentativa consulta).
//
// O cache é criado no FinanceiroClient (useState) e passado para baixo: a aba desmonta a cada troca de aba, então o
// cache não pode morar nela (mesmo motivo de criarCacheCaixaHotmart).
import type { FinanceiroRepository } from './ports';
import type { LinhaFunilEscritorio, PessoaFunilEscritorio } from '../domain/escritorio-funil';

type RepoEscritorio = Pick<FinanceiroRepository, 'loadEscritorioFunil' | 'loadEscritorioFunilPessoas'>;

export interface CacheEscritorioFunil {
  /** Já carregado (síncrono) — pinta sem "carregando" ao voltar à aba. */
  funilLido(): LinhaFunilEscritorio[] | undefined;
  funil(): Promise<LinhaFunilEscritorio[]>;
  pessoasLidas(eventoId: number): PessoaFunilEscritorio[] | undefined;
  pessoas(eventoId: number): Promise<PessoaFunilEscritorio[]>;
}

/** Uma promessa por chave; pedidos simultâneos dividem a mesma; erro não fica guardado. */
function memo<K, V>(carregar: (k: K) => Promise<V>) {
  const prontos = new Map<K, V>();
  const emVoo = new Map<K, Promise<V>>();
  return {
    lido: (k: K) => prontos.get(k),
    obter(k: K): Promise<V> {
      if (prontos.has(k)) return Promise.resolve(prontos.get(k) as V);
      const voo = emVoo.get(k);
      if (voo) return voo;
      const p = carregar(k).then(
        (v) => { prontos.set(k, v); emVoo.delete(k); return v; },
        (e: unknown) => { emVoo.delete(k); throw e; },
      );
      emVoo.set(k, p);
      return p;
    },
  };
}

export function criarCacheEscritorioFunil(repo: RepoEscritorio): CacheEscritorioFunil {
  const funil = memo<'funil', LinhaFunilEscritorio[]>(() => repo.loadEscritorioFunil());
  const pessoas = memo<number, PessoaFunilEscritorio[]>((id) => repo.loadEscritorioFunilPessoas(id));
  return {
    funilLido: () => funil.lido('funil'),
    funil: () => funil.obter('funil'),
    pessoasLidas: (id) => pessoas.lido(id),
    pessoas: (id) => pessoas.obter(id),
  };
}

export interface TotalFunilEscritorio {
  sessoes_vendas: number;
  pessoas: number;
  croqui_pessoas: number;
  hf_pessoas: number;
  /** % sobre quem começou pela Sessão (eventos + balde -3); os baldes -2 e -1 ficam fora do numerador e do denominador. */
  croqui_pct: number | null;
  hf_pct: number | null;
}

/** Baldes de quem NÃO começou pela Sessão (-2 direto no Croqui, -1 direto na HF): contam nas somas, não no %. */
const FORA_DO_PCT = new Set(['croqui', 'direto_hf']);

/**
 * Rodapé. Contagens: soma de TODAS as linhas (eventos + 3 baldes). Cada pessoa tem UMA linha de entrada no SQL
 * (funil_id), então a soma não conta ninguém duas vezes. %: conversão A PARTIR DA SESSÃO (decisão do coordenador,
 * 30/09) — só eventos e o balde -3; nos baldes -2/-1 o SQL conta a própria entrada (39 → Croqui = 100%), o que inflaria
 * a taxa. Mesma conta da RPC (n / pessoas × 100, 1 casa). Mediana não se soma: o rodapé não mostra.
 */
export function totalizarFunilEscritorio(linhas: LinhaFunilEscritorio[]): TotalFunilEscritorio {
  const soma = (ls: LinhaFunilEscritorio[], f: (l: LinhaFunilEscritorio) => number) => ls.reduce((s, l) => s + f(l), 0);
  const sessao = linhas.filter((l) => !FORA_DO_PCT.has(l.tipo));
  const base = soma(sessao, (l) => l.pessoas);
  const pct = (n: number) => (base ? Math.round((1000 * n) / base) / 10 : null);
  return {
    sessoes_vendas: soma(linhas, (l) => l.sessoes_vendas),
    pessoas: soma(linhas, (l) => l.pessoas),
    croqui_pessoas: soma(linhas, (l) => l.croqui_pessoas),
    hf_pessoas: soma(linhas, (l) => l.hf_pessoas),
    croqui_pct: pct(soma(sessao, (l) => l.croqui_pessoas)),
    hf_pct: pct(soma(sessao, (l) => l.hf_pessoas)),
  };
}
