// Guarda dos modais: só busca quando ainda não há resultado e nada está carregando.
export const deveCarregar = (estado: { resultado: unknown; carregando: boolean }): boolean =>
  !estado.resultado && !estado.carregando;
