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
  croqui_pct: number | null;
  hf_pessoas: number;
  hf_pct: number | null;
}

/**
 * Rodapé: soma das linhas (eventos + baldes). Cada pessoa tem UMA linha de entrada no SQL (funil_id), então somar
 * `pessoas`, `croqui_pessoas` e `hf_pessoas` não conta ninguém duas vezes. A % é a mesma conta da RPC
 * (n / pessoas × 100, 1 casa) sobre as somas. Mediana não se soma: o rodapé não mostra.
 */
export function totalizarFunilEscritorio(linhas: LinhaFunilEscritorio[]): TotalFunilEscritorio {
  const soma = (f: (l: LinhaFunilEscritorio) => number) => linhas.reduce((s, l) => s + f(l), 0);
  const pessoas = soma((l) => l.pessoas);
  const croqui = soma((l) => l.croqui_pessoas);
  const hf = soma((l) => l.hf_pessoas);
  const pct = (n: number) => (pessoas ? Math.round((1000 * n) / pessoas) / 10 : null);
  return {
    sessoes_vendas: soma((l) => l.sessoes_vendas), pessoas,
    croqui_pessoas: croqui, croqui_pct: pct(croqui), hf_pessoas: hf, hf_pct: pct(hf),
  };
}
