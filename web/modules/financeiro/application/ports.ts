// Ports (contratos) do módulo Financeiro. Implementados por adapters Supabase
// em infrastructure. Casos de uso dependem só destas interfaces, nunca de
// Supabase direto — mesmo padrão de modules/placas/application/ports.ts.
import type {
  Acordo, CardBoard, Cobranca, CompraHistorico, DiaFaturamento, Lancamento,
  Meta, Oferta, OfertaOrfa, ReguaPasso, SaudeCheck, TurmaFin,
} from '../domain/types';

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
  registrarCobranca(contatoHmId: string, canal: string, resultado: string, obs: string | null): Promise<Resultado>;
  salvarAcordo(contatoHmId: string, a: Acordo): Promise<Resultado>;

  // ── Faturamento diário ───────────────────────────────────────────────────
  loadFaturamento(turma: string | null): Promise<DiaFaturamento[]>;

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
}
