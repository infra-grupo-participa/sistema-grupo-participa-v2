// Visão geral do Contas a Receber (#visao): a carga das fotos (z69), SÓ quando a Visão geral abre. O cache mora no pai
// (FinanceiroClient): voltar à Visão geral não consulta de novo.
//   1ª ida, em paralelo: fn_fin_receber_fotos_listar + fn_fin_receber_previsto_realizado(8).
//   2ª ida, só com 2 fotos base ou mais: fn_fin_receber_mudancas(anterior, mais recente) — precisa do foto_em que a
//   1ª ida devolve. Com 1 foto (o caso até a segunda 05/10) são 2 chamadas.
// Cada parte devolve dado OU erro, separados: uma falha não apaga as outras e nunca vira lista vazia. "Tentar de novo"
// pede só as partes que falharam.
import type { FinanceiroRepository } from './ports';
import {
  parComparacao, type FotoReceber, type LinhaPrevistoRealizado, type MudancaReceber,
} from '../domain/visao-receber';

export type Parte<T> = { dados: T; erro: null } | { dados: null; erro: string };

export interface VisaoReceberCarregada {
  fotos: Parte<FotoReceber[]>;
  /** NULL = não houve comparação: menos de 2 fotos base, ou a lista de fotos falhou. */
  mudancas: Parte<MudancaReceber[]> | null;
  comparacao: { anterior: FotoReceber; recente: FotoReceber } | null;
  previsto: Parte<LinhaPrevistoRealizado[]>;
}

/** Semanas completas pedidas ao previsto × realizado (o padrão da RPC). */
export const SEMANAS_PREVISTO = 8;

type Repo = Pick<FinanceiroRepository, 'loadFotosReceber' | 'loadMudancasReceber' | 'loadPrevistoRealizado'>;

const msg = (e: unknown, padrao: string) => (e instanceof Error && e.message ? e.message : padrao);

async function parte<T>(p: () => Promise<T>, padrao: string): Promise<Parte<T>> {
  try {
    return { dados: await p(), erro: null };
  } catch (e) {
    return { dados: null, erro: msg(e, padrao) };
  }
}

/** `anterior` = a carga que já está na tela: parte que deu certo é reusada (não consulta de novo). */
export async function carregarVisaoReceber(repo: Repo, anterior: VisaoReceberCarregada | null = null): Promise<VisaoReceberCarregada> {
  const [fotos, previsto] = await Promise.all([
    anterior?.fotos.dados ? Promise.resolve(anterior.fotos) : parte(() => repo.loadFotosReceber(), 'Não foi possível carregar as fotos da previsão.'),
    anterior?.previsto.dados ? Promise.resolve(anterior.previsto)
      : parte(() => repo.loadPrevistoRealizado(SEMANAS_PREVISTO), 'Não foi possível carregar o previsto × realizado.'),
  ]);
  const comparacao = fotos.dados ? parComparacao(fotos.dados) : null;
  let mudancas: VisaoReceberCarregada['mudancas'] = null;
  if (comparacao) {
    const mesma = anterior?.comparacao && anterior.mudancas?.dados
      && anterior.comparacao.anterior.foto_em === comparacao.anterior.foto_em
      && anterior.comparacao.recente.foto_em === comparacao.recente.foto_em;
    mudancas = mesma ? anterior!.mudancas
      : await parte(() => repo.loadMudancasReceber(comparacao.anterior.foto_em, comparacao.recente.foto_em),
        'Não foi possível carregar o que mudou.');
  }
  return { fotos, mudancas, comparacao, previsto };
}

/** Alguma parte falhou? (a tela oferece "tentar de novo" só então) */
export const visaoTemErro = (v: VisaoReceberCarregada): boolean =>
  v.fotos.erro != null || v.previsto.erro != null || (v.mudancas?.erro ?? null) != null;
