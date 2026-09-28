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
import type { FaturamentoAcao, LinhaContratado } from '../domain/faturamento-analise';
import type { LinhaServicoDiamante } from '../domain/servico-diamante';
import type { CompradorFunil, Funil } from '../domain/funis';
import type { PassoTrajetoria } from '../domain/trajetoria';
import type { OfertaSemCatalogo, PagouSemCard } from '../domain/programa-sem-card';

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
  /** fn_fin_contratado — dinheiro já vendido que ainda vai entrar, por mês e fonte (20260928p). */
  loadContratado(familia: FamiliaHotmart): Promise<LinhaContratado[]>;
  /** fn_fin_faturamento_por_acao — faturamento dentro da janela de cada ação de fin.acoes. */
  loadFaturamentoPorAcao(familia: FamiliaHotmart): Promise<FaturamentoAcao[]>;
  /** fn_fin_diamante_servicos — Serviço Diamante: uma linha por pessoa × serviço (20260928r). */
  loadServicoDiamante(): Promise<LinhaServicoDiamante[]>;
  /** fn_fin_funis — resultado de cada evento/funil (fin.eventos × Hotmart). */
  loadFunis(): Promise<Funil[]>;
  /** fn_fin_funil_compradores — quem pagou num funil. */
  loadFunilCompradores(eventoId: number): Promise<CompradorFunil[]>;
  /** Trajetória da pessoa (fn_fin_trajetoria): toda compra, em que funil, desde 2019. */
  loadTrajetoria(email: string): Promise<PassoTrajetoria[]>;
  /** Pagou oferta do Programa e não tem card no board (fn_fin_programa_sem_card). */
  loadProgramaSemCard(familia: 'HM' | 'AURUM'): Promise<PagouSemCard[]>;
  /** Ofertas pagas fora do catálogo (fn_fin_ofertas_sem_catalogo). */
  loadOfertasSemCatalogo(): Promise<OfertaSemCatalogo[]>;
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

  // ── Protocolo dos relatórios em PDF (fn_fin_relatorio_*, 20260928z50) ───
  /** fn_fin_relatorio_emitir — grava a emissão e devolve o protocolo GP-REL-AAAA-NNNNNN. */
  emitirRelatorio(
    tipo: string, nivel: string, recorte: Record<string, unknown>, linhas: number, totais: Record<string, unknown>,
  ): Promise<RelatorioEmitido>;
  /** fn_fin_relatorio_selar — true = selou agora; false = fora da janela, já selado ou não é seu. */
  selarRelatorio(protocolo: string, sha256: string, paginas: number): Promise<boolean>;
  /** fn_fin_relatorio_verificar — conferência manual, dentro do sistema, de um protocolo já emitido. */
  verificarRelatorio(protocolo: string): Promise<RelatorioVerificado | null>;
}

/** Devolvido por fn_fin_relatorio_emitir. */
export interface RelatorioEmitido {
  protocolo: string;
  emitido_em: string;
  gerado_por_nome: string;
}

/** Devolvido por fn_fin_relatorio_verificar. */
export interface RelatorioVerificado {
  protocolo: string;
  tipo: string;
  nivel: string;
  recorte: Record<string, unknown>;
  linhas: number;
  totais: Record<string, unknown>;
  emitido_em: string;
  gerado_por_nome: string;
  selado_em: string | null;
  paginas: number | null;
  sha256: string | null;
  situacao: 'selado' | 'aguardando_selo' | 'nao_concluido';
}
