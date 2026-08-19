// Caso de uso: mapa de ofertas de cobrança do saldo. `categoria` é read-only
// (legado que mente para 3 ofertas — nunca editar); `papel` é o único campo
// que a UI pode gravar. fn_fin_oferta_salvar pode não estar aplicada ainda —
// ver nota em application/ports.ts.
import type { Oferta } from '../domain/types';
import type { FinanceiroRepository, Resultado } from './ports';

export async function listarOfertas(repo: FinanceiroRepository): Promise<Oferta[]> {
  const ofertas = await repo.loadOfertas();
  return [...ofertas].sort((a, b) => (b.valor ?? 0) - (a.valor ?? 0));
}

export async function salvarPapelOferta(repo: FinanceiroRepository, codigo: string, papel: string): Promise<Resultado> {
  return repo.salvarOfertaPapel(codigo, papel);
}
