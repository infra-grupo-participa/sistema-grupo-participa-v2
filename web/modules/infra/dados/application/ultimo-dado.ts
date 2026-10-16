import type { Resultado as ResultadoAtm } from '@/modules/infra/atm/infrastructure/atm-data';
import type { Resultado } from '../infrastructure/presencial-data';

export type EstadoLeitura<T> = { resultado: Resultado<T> | null; carregando: boolean };

/** Uma falha de leitura não apaga o último dado válido do bloco. */
export function manterUltimoDado<T>(anterior: Resultado<T> | null, atual: Resultado<T>): Resultado<T> {
  if (atual.data !== null && !atual.erro) return atual;
  return { data: anterior?.data ?? null, erro: atual.erro ?? 'Não foi possível carregar agora.' };
}

/** Mesma regra para as leituras no formato do ATM (`semDado`): leitura que falhou mantém a última lista e só troca o aviso. */
export function manterUltimaLeituraAtm<T>(anterior: ResultadoAtm<T>, proximo: ResultadoAtm<T>): ResultadoAtm<T> {
  return proximo.semDado ? { ...anterior, erro: proximo.erro } : proximo;
}
