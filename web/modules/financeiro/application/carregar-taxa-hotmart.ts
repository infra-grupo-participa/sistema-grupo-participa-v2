// Faturamento · Taxa Hotmart: na 1ª vez que um período é pedido, 1 chamada (auditoria) e, SÓ se houver divergente,
// a 2ª (lista das divergências). O mesmo período de novo não consulta. Falha não fica guardada.
//
// O cache é criado no FinanceiroClient (useState) e passado para baixo: a aba Faturamento desmonta a cada troca de
// aba, então o cache não pode morar nela (mesmo desenho de carregar-caixa-hotmart).
import type { FinanceiroRepository } from './ports';
import { chaveTaxa, montarAuditoriaTaxa, type AuditoriaTaxa, type DivergenciaTaxa } from '../domain/taxa-hotmart';

type RepoTaxa = Pick<FinanceiroRepository, 'loadTaxaAuditoria' | 'loadTaxaDivergencias'>;

export interface TaxaHotmartCarregada {
  de: string;
  ate: string;
  auditoria: AuditoriaTaxa;
  /** Vazia quando não há divergente (a RPC nem é chamada). */
  divergencias: DivergenciaTaxa[];
}

export async function carregarTaxaHotmart(repo: RepoTaxa, de: string, ate: string): Promise<TaxaHotmartCarregada> {
  const auditoria = montarAuditoriaTaxa(await repo.loadTaxaAuditoria(de, ate));
  const divergencias = auditoria.resumo.nDivergentes > 0 ? await repo.loadTaxaDivergencias(de, ate) : [];
  return { de, ate, auditoria, divergencias };
}

export interface CacheTaxaHotmart {
  /** Já carregado (síncrono) — para pintar sem "carregando" ao voltar a um período visto. */
  lido(de: string, ate: string): TaxaHotmartCarregada | undefined;
  /** Carrega uma vez por período; pedidos simultâneos do mesmo período dividem a mesma promessa. */
  obter(de: string, ate: string): Promise<TaxaHotmartCarregada>;
}

export function criarCacheTaxaHotmart(repo: RepoTaxa): CacheTaxaHotmart {
  const prontos = new Map<string, TaxaHotmartCarregada>();
  const emVoo = new Map<string, Promise<TaxaHotmartCarregada>>();
  return {
    lido: (de, ate) => prontos.get(chaveTaxa(de, ate)),
    obter(de, ate) {
      const k = chaveTaxa(de, ate);
      const pronto = prontos.get(k);
      if (pronto) return Promise.resolve(pronto);
      const voo = emVoo.get(k);
      if (voo) return voo;
      const p = carregarTaxaHotmart(repo, de, ate).then(
        (r) => { prontos.set(k, r); emVoo.delete(k); return r; },
        (e: unknown) => { emVoo.delete(k); throw e; },
      );
      emVoo.set(k, p);
      return p;
    },
  };
}
