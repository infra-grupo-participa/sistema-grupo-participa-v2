import type { DetalheLive, Live, PreviaImportacao, ResultadoLiveAcao, TipoLive } from '../domain/lives';
import type { LinhaStudio } from '../domain/lives-studio';
import type {
  ConfigBlack, GrupoResumoBlack, LeadDetalhe, LinhaPerfil, Marcos, MensageriaBlack, Periodo, RecorteGrupo, Resultado, ResultadoAcao,
  TrafegoBlack,
} from '../domain/tipos';

/**
 * Fonte de dados do dashboard da Black. Duas implementações:
 * - demonstração (infrastructure/fixtures/fonte-fixtures.ts): dado fictício em memória, só em dev com NEXT_PUBLIC_BLACK_DEMO=1;
 * - real (infrastructure/fonte-supabase.ts): RPCs dados_black_* do Supabase com a sessão do usuário.
 * Contrato de cada método: docs/dashboard-black/README.md.
 */
export interface FonteDadosBlack {
  readonly modo: 'demonstracao' | 'real';
  /** Relógio da tela (o demo usa um relógio fixo, movível por ?relogio=AAAA-MM-DD). */
  agora(): Date;
  config(chave: string): Promise<Resultado<ConfigBlack>>;
  trafego(chave: string, p: Periodo): Promise<Resultado<TrafegoBlack>>;
  /** Uma linha por envio. `incluirTeste` = traz também os marcados como teste (a tela tira das contas; só master vê). */
  perfil(chave: string, p: Periodo, opcoes?: { incluirTeste?: boolean }): Promise<Resultado<LinhaPerfil[]>>;
  /** Dado pessoal: só ao abrir a tabela, 50 por página. */
  leads(chave: string, leadIds: string[]): Promise<Resultado<LeadDetalhe[]>>;
  /** Ingresso no grupo por segmento, sem teste. `recorte` null = sem recorte (conta simples, sem cruzar). */
  grupo(chave: string, p: Periodo, recorte: RecorteGrupo | null): Promise<Resultado<GrupoResumoBlack>>;
  /** Marca o lead como teste neste evento (pelo e-mail e pelo telefone do LeadDetalhe). */
  marcarTeste(chave: string, lead: LeadDetalhe): Promise<ResultadoAcao>;
  desmarcarTeste(chave: string, lead: LeadDetalhe): Promise<ResultadoAcao>;
  mensageria(chave: string, p: Periodo): Promise<Resultado<MensageriaBlack>>;
  marcos(chave: string): Promise<Resultado<Marcos>>;

  // ── Aba Lives (independente do recorte global: funil, período e canal não se aplicam às lives) ──
  /** Cadastro das lives com a última leitura da API e o resumo da curva (dados_black_lives). */
  lives(chave: string): Promise<Resultado<Live[]>>;
  /** Curva minuto a minuto, chat, comentários e fotos de uma live (dados_black_live_detalhe). */
  liveDetalhe(chave: string, videoId: string): Promise<Resultado<DetalheLive>>;
  /** Master. `confirmar` false = só a prévia; true grava (tudo ou nada). Idempotente. */
  importarLive(chave: string, videoId: string, linhas: readonly LinhaStudio[], confirmar: boolean): Promise<ResultadoLiveAcao<PreviaImportacao>>;
  /** Master. `dataPrevista` = ISO com fuso (-03:00). */
  cadastrarLive(chave: string, videoId: string, tipo: TipoLive, dataPrevista: string): Promise<ResultadoLiveAcao<{ videoId: string }>>;
  /** Master. Tira a live da aba (não apaga o histórico). */
  removerLive(chave: string, videoId: string): Promise<ResultadoLiveAcao<{ videoId: string }>>;
}

export const LEADS_POR_PAGINA = 50;
