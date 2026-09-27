// Pro rata do HM sob demanda (fn_fin_prorata_hm, ~265 ms): carregado na 1ª
// ficha aberta e reaproveitado pelas seguintes — NUNCA por card no board.
// Cache por instância de repositório, com validade curta (o cálculo depende
// de "hoje" e de pagamentos novos). Falha não fica em cache: a próxima ficha tenta de novo.
import type { FinanceiroRepository } from './ports';
import type { ProrataHM } from '../domain/hotmart';
import { normalizarProrataHM, VALOR_PROGRAMA_HM } from '../domain/prorata-hm';

export { VALOR_PROGRAMA_HM };
const VALIDADE_MS = 10 * 60 * 1000;

type Entrada = { em: number; p: Promise<ProrataHM[]> };
const cache = new WeakMap<Pick<FinanceiroRepository, 'loadProrataHM'>, Entrada>();

export function carregarProrataHM(
  repo: Pick<FinanceiroRepository, 'loadProrataHM'>, agora: number = Date.now(),
): Promise<ProrataHM[]> {
  const e = cache.get(repo);
  if (e && agora - e.em < VALIDADE_MS) return e.p;
  const p = repo.loadProrataHM(VALOR_PROGRAMA_HM).then((ls) => ls.map(normalizarProrataHM));
  const entrada = { em: agora, p };
  cache.set(repo, entrada);
  p.catch(() => { if (cache.get(repo) === entrada) cache.delete(repo); });
  return p;
}
