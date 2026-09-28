// Faturamento · Caixa Hotmart: 2 chamadas (linhas por dia + totais) na 1ª vez que um período é pedido; o mesmo
// período de novo não consulta. Falha não fica guardada (a próxima tentativa consulta de novo).
//
// O cache é criado no FinanceiroClient (useState) e passado para baixo: a aba Faturamento desmonta a cada troca de
// aba, então o cache não pode morar nela.
import type { FinanceiroRepository } from './ports';
import {
  chaveCaixa, derivarCaixa, type DerivadoCaixa, type LinhaCaixaHotmart, type TotaisCaixaHotmart,
} from '../domain/caixa-hotmart';

export interface CaixaHotmartCarregado {
  de: string;
  ate: string;
  linhas: LinhaCaixaHotmart[];
  totais: TotaisCaixaHotmart;
  derivado: DerivadoCaixa;
}

export async function carregarCaixaHotmart(
  repo: Pick<FinanceiroRepository, 'loadCaixaHotmart' | 'loadCaixaHotmartTotais'>, de: string, ate: string,
): Promise<CaixaHotmartCarregado> {
  const [linhas, totais] = await Promise.all([repo.loadCaixaHotmart(de, ate), repo.loadCaixaHotmartTotais(de, ate)]);
  return { de, ate, linhas, totais, derivado: derivarCaixa(linhas, totais) };
}

export interface CacheCaixaHotmart {
  /** Já carregado (síncrono) — para pintar sem "carregando" ao voltar a um período visto. */
  lido(de: string, ate: string): CaixaHotmartCarregado | undefined;
  /** Carrega uma vez por período; pedidos simultâneos do mesmo período dividem a mesma promessa. */
  obter(de: string, ate: string): Promise<CaixaHotmartCarregado>;
}

export function criarCacheCaixaHotmart(
  repo: Pick<FinanceiroRepository, 'loadCaixaHotmart' | 'loadCaixaHotmartTotais'>,
): CacheCaixaHotmart {
  const prontos = new Map<string, CaixaHotmartCarregado>();
  const emVoo = new Map<string, Promise<CaixaHotmartCarregado>>();
  return {
    lido: (de, ate) => prontos.get(chaveCaixa(de, ate)),
    obter(de, ate) {
      const k = chaveCaixa(de, ate);
      const pronto = prontos.get(k);
      if (pronto) return Promise.resolve(pronto);
      const voo = emVoo.get(k);
      if (voo) return voo;
      const p = carregarCaixaHotmart(repo, de, ate).then(
        (r) => { prontos.set(k, r); emVoo.delete(k); return r; },
        (e: unknown) => { emVoo.delete(k); throw e; },
      );
      emVoo.set(k, p);
      return p;
    },
  };
}
