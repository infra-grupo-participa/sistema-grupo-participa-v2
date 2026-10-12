// Fonte REAL do dashboard da Black: esboço. Nenhuma tabela nem migration existe ainda (decisão do plano
// técnico, passo 7), então todo método devolve semDado, SEM chamada de rede. A tela mostra "Sem dado" e o
// aviso de fonte não ligada; nunca zero. Ligar cada método a uma view/RPC é trabalho do back-end, com o
// manual do banco (docs/manual-banco-de-dados.md).
import type { FonteDadosBlack } from '../application/ports';
import type { ConfigBlack, Resultado } from '../domain/tipos';

const AVISO = 'Fonte real ainda não ligada (sem tabela no Supabase).';
const semDado = <T,>(data: T): Promise<Resultado<T>> => Promise.resolve({ data, semDado: true, erro: AVISO });

export const fonteSupabaseBlack: FonteDadosBlack = {
  modo: 'real',
  agora: () => new Date(),
  config: () => semDado<ConfigBlack>(null as unknown as ConfigBlack),
  trafego: () => semDado({ campanhas: [], conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null }),
  perfil: () => semDado([]),
  leads: () => semDado([]),
  mensageria: () => semDado({ canais: [], envios: [], regua: [] }),
  marcos: () => semDado({ presencaLive: null, vendas: null }),
};
