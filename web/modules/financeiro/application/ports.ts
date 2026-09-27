// Ports (contratos) do módulo Financeiro. Implementados por adapters Supabase
// em infrastructure. Casos de uso dependem só destas interfaces, nunca de
// Supabase direto — mesmo padrão de modules/placas/application/ports.ts.
import type {
  Acordo, CardBoard, Cobranca, CompraHistorico, InteracaoAtivacao, Lancamento,
  Meta, Oferta, OfertaOrfa, ReguaPasso, SaudeCheck, TurmaFin,
} from '../domain/types';
import type {
  AceleraParaHM, BoardHotmart, DiaHotmart, DivergenciaHotmart, FamiliaHotmart, FunilHotmart, IdentidadeRevisao, OfertaHotmart, PessoaHotmart, ProrataDiagnostico, ProrataHM, SyncHotmart, TransacaoHotmart,
} from '../domain/hotmart';

/** Resultado padrão de uma escrita (RPC de mutação). */
export interface Resultado {
  ok: boolean;
  msg?: string;
}

export interface FinanceiroRepository {
  // ── Board (novo) ────────────────────────────────────────────────────────
  /** fn_fin_board(p_turma, p_produto). p_produto filtra por origem ('HM'|'AURUM'). */
  loadBoard(turma: string | null, produto: string | null): Promise<CardBoard[]>;

  // ── Turmas / metas / régua ──────────────────────────────────────────────
  loadTurmas(): Promise<TurmaFin[]>;
  loadMetas(): Promise<Meta[]>;
  salvarMeta(m: Meta): Promise<Resultado>;
  loadRegua(): Promise<ReguaPasso[]>;
  salvarRegua(passos: ReguaPasso[]): Promise<Resultado>;

  // ── Ficha do aluno (detalhe) ─────────────────────────────────────────────
  loadExtrato(compradorId: string): Promise<Lancamento[]>;
  loadComprasAluno(compradorId: string): Promise<CompraHistorico[]>;
  loadCobrancas(contatoHmId: string): Promise<Cobranca[]>;
  /** fn_fin_historico_ativacao(uuid) — histórico do comercial (cs.interacoes), 100 mais recentes. */
  loadHistoricoAtivacao(contatoHmId: string): Promise<InteracaoAtivacao[]>;
  registrarCobranca(contatoHmId: string, canal: string, resultado: string, obs: string | null): Promise<Resultado>;
  salvarAcordo(contatoHmId: string, a: Acordo): Promise<Resultado>;

  // ── Ofertas ──────────────────────────────────────────────────────────────
  loadOfertas(): Promise<Oferta[]>;
  /**
   * fn_fin_oferta_salvar — RPC ainda NÃO aplicada em produção (não existe
   * migration). Contrato preparado por antecipação: `categoria` é read-only
   * (legado que mente para 3 ofertas — nunca enviado na escrita), `papel` é o
   * único campo editável. Chamar antes da RPC existir resulta em erro do
   * Postgres (função inexistente) — tratado como falha de rede pela UI.
   */
  salvarOfertaPapel(codigo: string, papel: string): Promise<Resultado>;

  // ── Saúde / diagnóstico ──────────────────────────────────────────────────
  loadSaude(): Promise<SaudeCheck[]>;
  loadOfertasOrfas(): Promise<OfertaOrfa[]>;

  // ── Espelho da Hotmart (schema fin, só leitura — 27/09/2026) ─────────────
  loadHotmartFaturamento(familia: FamiliaHotmart, inicio: string | null, fim: string | null): Promise<DiaHotmart[]>;
  loadHotmartFunis(familia: FamiliaHotmart, inicio: string | null, fim: string | null): Promise<FunilHotmart[]>;
  loadHotmartPessoas(familia: FamiliaHotmart): Promise<PessoaHotmart[]>;
  loadHotmartExtrato(email: string): Promise<TransacaoHotmart[]>;
  loadHotmartOfertas(familia: FamiliaHotmart): Promise<OfertaHotmart[]>;
  loadHotmartConciliacao(familia: FamiliaHotmart): Promise<DivergenciaHotmart[]>;
  loadHotmartSync(): Promise<SyncHotmart | null>;
  loadHotmartIdentidade(): Promise<IdentidadeRevisao[]>;
  /** fn_fin_board_hotmart — card do board × espelho Hotmart, por pessoa/família. */
  loadBoardHotmart(): Promise<BoardHotmart[]>;
  /** fn_fin_prorata_hm — pro rata do HM por pessoa (regra do João, 27/09). */
  loadProrataHM(valorPrograma?: number): Promise<ProrataHM[]>;
  /** fn_fin_acelera_para_hm — quem comprou o Acelera e o que comprou de HM depois. */
  loadAceleraParaHM(): Promise<AceleraParaHM[]>;
  /** fn_fin_prorata_diagnostico — uma pessoa, com cada pagamento e o motivo; vencimento/valor = simulação. */
  loadProrataDiagnostico(email: string, vencimento?: string | null, valorPrograma?: number): Promise<ProrataDiagnostico | null>;
}
