// Listas "sem card" do board (Programa HM, Programa Aurum, mensalidade do HM antigo) — cache por aba visitada.
//
// Medido em produção (coordenador, 28/09, 2ª execução): fn_fin_programa_sem_card('HM') 65 ms · ('AURUM') 713 ms ·
// fn_fin_assinatura_hm_sem_card() 127 ms. Regra: cada lista carrega na 1ª vez que o produto dela fica visível e fica
// guardada (voltar à aba não consulta de novo). O recarregar do board invalida tudo e recarrega só o que está visível;
// o resto recarrega na próxima visita. Aba nunca visitada nunca consulta.
import type { FinanceiroRepository } from './ports';
import type { PagouSemCard } from '../domain/programa-sem-card';
import type { AssinaturaHMSemCard } from '../domain/assinatura-hm';

export type ListaSemCard = 'programa_HM' | 'programa_AURUM' | 'assinatura_HM';

export type DadosListaSemCard = PagouSemCard[] | AssinaturaHMSemCard[];

/** Listas cujo bloco está na tela neste recorte. Fora da aba board ou no Serviço Diamante: nenhuma. */
export function listasVisiveis(tab: string, produto: 'HM' | 'AURUM', verDiamante: boolean): ListaSemCard[] {
  if (tab !== 'board' || verDiamante) return [];
  return produto === 'HM' ? ['programa_HM', 'assinatura_HM'] : ['programa_AURUM'];
}

type Repo = Pick<FinanceiroRepository, 'loadProgramaSemCard' | 'loadAssinaturaHMSemCard'>;

function buscar(repo: Repo, lista: ListaSemCard): Promise<DadosListaSemCard> {
  if (lista === 'assinatura_HM') return repo.loadAssinaturaHMSemCard();
  return repo.loadProgramaSemCard(lista === 'programa_HM' ? 'HM' : 'AURUM');
}

export interface CacheListasSemCard {
  /** Pede as listas que ainda não foram pedidas nesta geração. Falha vira lista vazia (o bloco some). */
  garantir(listas: readonly ListaSemCard[]): void;
  /** Esquece tudo o que foi pedido; respostas ainda em voo são descartadas. */
  invalidar(): void;
}

export function criarCacheListasSemCard(
  repo: Repo, aoCarregar: (lista: ListaSemCard, dados: DadosListaSemCard) => void,
): CacheListasSemCard {
  const pedidas = new Set<ListaSemCard>();
  let geracao = 0;
  return {
    garantir(listas) {
      for (const l of listas) {
        if (pedidas.has(l)) continue;
        pedidas.add(l);
        const g = geracao;
        buscar(repo, l)
          .catch((): DadosListaSemCard => [])
          .then((d) => { if (g === geracao) aoCarregar(l, d); });
      }
    },
    invalidar() {
      geracao += 1;
      pedidas.clear();
    },
  };
}
