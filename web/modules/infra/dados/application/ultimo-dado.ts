import type { Resultado } from '../infrastructure/presencial-data';

/** Uma falha de leitura não apaga o último dado válido do bloco. */
export function manterUltimoDado<T>(anterior: Resultado<T> | null, atual: Resultado<T>): Resultado<T> {
  if (atual.data !== null && !atual.erro) return atual;
  return { data: anterior?.data ?? null, erro: atual.erro ?? 'Não foi possível carregar agora.' };
}
