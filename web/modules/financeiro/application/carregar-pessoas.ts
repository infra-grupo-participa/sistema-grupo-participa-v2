// Pessoas da Hotmart por família (fn_fin_hotmart_pessoas, ~535 ms): o Board e a aba
// Relatórios → Pessoas leem a mesma lista. Sem cache, cada troca de aba refazia a consulta.
// Mesmo desenho de carregar-prorata.ts: por instância de repositório, validade curta, falha não fica em cache.
import type { FinanceiroRepository } from './ports';
import type { FamiliaHotmart, PessoaHotmart } from '../domain/hotmart';

const VALIDADE_MS = 10 * 60 * 1000;

type Entrada = { em: number; p: Promise<PessoaHotmart[]> };
const cache = new WeakMap<Pick<FinanceiroRepository, 'loadHotmartPessoas'>, Map<FamiliaHotmart, Entrada>>();

export function carregarPessoasHotmart(
  repo: Pick<FinanceiroRepository, 'loadHotmartPessoas'>, familia: FamiliaHotmart, agora: number = Date.now(),
): Promise<PessoaHotmart[]> {
  let porFamilia = cache.get(repo);
  if (!porFamilia) { porFamilia = new Map(); cache.set(repo, porFamilia); }
  const e = porFamilia.get(familia);
  if (e && agora - e.em < VALIDADE_MS) return e.p;
  const p = repo.loadHotmartPessoas(familia);
  const entrada = { em: agora, p };
  porFamilia.set(familia, entrada);
  const mapa = porFamilia;
  p.catch(() => { if (mapa.get(familia) === entrada) mapa.delete(familia); });
  return p;
}
