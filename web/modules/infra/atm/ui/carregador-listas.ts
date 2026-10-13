/*
 * Carregador das listas dos modais do ATM (13/10/2026). Existe por causa do bug do modal de Leads zerado: a lista só era
 * pedida dentro do refresh grande da página (8 RPCs, ~10 s) e, se já houvesse um refresh em curso, esperava o fim dele;
 * enquanto isso o estado inicial `{ data: [], semDado: true }` aparecia como "0 leads válidos · Leads indisponíveis".
 *
 * Regras (a classe do erro, não a ocorrência):
 *   - cada lista é lida sozinha, na hora em que o modal abre ou o período muda, em paralelo com as outras;
 *   - o estado diz o que está acontecendo: `carregando` (nunca vira zero nem "indisponível"), `pronto` (inclusive lista
 *     vazia de verdade), `erro` (mensagem da leitura), `naoPublicada` (só PGRST202), `semPermissao` (42501, limpa a lista);
 *   - cache por chave (RPC, evento, período, incluir teste) enquanto a página está aberta: reabrir mostra a última lista na
 *     hora e revalida por trás; falha de releitura mantém a última lista, com o erro e a hora da leitura;
 *   - duas aberturas da mesma chave ao mesmo tempo fazem uma leitura só.
 * Sem React aqui, para dar para testar no Vitest (ambiente node). O gancho fica em `useListaAtm`.
 */
import type { Resultado } from '../infrastructure/atm-data';

export type FaseListaAtm = 'carregando' | 'pronto' | 'erro' | 'naoPublicada' | 'semPermissao';

export type EstadoListaAtm<T> = {
  fase: FaseListaAtm;
  /** Última lista lida com sucesso para esta chave; `null` = nunca lida (nada a mostrar além do estado). */
  data: T[] | null;
  /** Mensagem da última leitura que falhou (com `data` preenchido, a lista mostrada é a anterior). */
  erro: string | null;
  lidoEm: Date | null;
  /** Há lista na tela e uma releitura em curso. */
  revalidando: boolean;
};

export const LISTA_CARREGANDO: EstadoListaAtm<never> = Object.freeze({ fase: 'carregando', data: null, erro: null, lidoEm: null, revalidando: false }) as EstadoListaAtm<never>;

const MENSAGEM_FALHA = 'Não foi possível carregar os dados agora.';

/** Estado depois de uma leitura. Exportado para teste. */
export function estadoAposLeitura<T>(anterior: EstadoListaAtm<T> | undefined, leitura: Resultado<T[]>, agora: Date): EstadoListaAtm<T> {
  if (!leitura.semDado) return { fase: 'pronto', data: leitura.data, erro: leitura.erro, lidoEm: agora, revalidando: false };
  if (leitura.semPermissao) return { fase: 'semPermissao', data: null, erro: leitura.erro, lidoEm: null, revalidando: false };
  if (leitura.naoPublicada) return { fase: 'naoPublicada', data: null, erro: leitura.erro, lidoEm: null, revalidando: false };
  const erro = leitura.erro ?? MENSAGEM_FALHA;
  if (anterior?.data) return { ...anterior, fase: 'pronto', erro, revalidando: false };
  return { fase: 'erro', data: null, erro, lidoEm: null, revalidando: false };
}

export type CarregadorListasAtm = ReturnType<typeof criarCarregadorListasAtm>;

export function criarCarregadorListasAtm(agora: () => Date = () => new Date()) {
  const cache = new Map<string, EstadoListaAtm<unknown>>();
  const emVoo = new Map<string, Promise<void>>();
  const ouvintes = new Set<() => void>();
  const avisar = () => { for (const fn of ouvintes) fn(); };
  const gravar = (chave: string, estado: EstadoListaAtm<unknown>) => { cache.set(chave, estado); avisar(); };

  return {
    /** Estado atual da chave; a mesma referência enquanto nada muda (exigência do useSyncExternalStore). */
    estado<T>(chave: string): EstadoListaAtm<T> {
      return (cache.get(chave) as EstadoListaAtm<T> | undefined) ?? LISTA_CARREGANDO;
    },
    /** Lê (ou relê) a chave. Com leitura da mesma chave em curso, devolve a mesma promessa em vez de pedir de novo. */
    carregar<T>(chave: string, ler: () => Promise<Resultado<T[]>>): Promise<void> {
      const voando = emVoo.get(chave);
      if (voando) return voando;
      const anterior = cache.get(chave) as EstadoListaAtm<T> | undefined;
      if (anterior?.data) gravar(chave, { ...anterior, revalidando: true });
      else if (anterior) gravar(chave, { ...LISTA_CARREGANDO });
      const promessa = (async () => {
        let leitura: Resultado<T[]>;
        try {
          leitura = await ler();
        } catch {
          leitura = { data: [], semDado: true, erro: MENSAGEM_FALHA };
        }
        gravar(chave, estadoAposLeitura(cache.get(chave) as EstadoListaAtm<T> | undefined, leitura, agora()) as EstadoListaAtm<unknown>);
      })().finally(() => { emVoo.delete(chave); });
      emVoo.set(chave, promessa);
      return promessa;
    },
    inscrever(fn: () => void): () => void {
      ouvintes.add(fn);
      return () => { ouvintes.delete(fn); };
    },
  };
}

/** Chave do cache: RPC, evento, período e inclusão de teste. Período nulo = período do evento. */
export function chaveListaAtm(rpc: string, chave: string, periodo: { p_de: string | null; p_ate: string | null } | null, incluirTeste: boolean): string {
  return [rpc, chave, periodo?.p_de ?? '', periodo?.p_ate ?? '', incluirTeste ? 'com-teste' : 'sem-teste'].join('|');
}
