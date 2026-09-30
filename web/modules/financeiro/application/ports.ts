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
import type { LinhaFunilEscritorio, PessoaFunilEscritorio } from '../domain/escritorio-funil';
import type { PassoTrajetoria } from '../domain/trajetoria';
import type { OfertaSemCatalogo, PagouSemCard } from '../domain/programa-sem-card';
import type { AssinaturaHMBoard, AssinaturaHMSemCard } from '../domain/assinatura-hm';
import type { CenarioReceber, LinhaReceber } from '../domain/contas-receber';
import type { FeriadoBancario, SugestaoPremissa, VigenciaPremissa } from '../domain/premissas-receber';
import type { FotoReceber, LinhaPrevistoRealizado, MudancaReceber } from '../domain/visao-receber';
import type { EventoPlanejado, EventoPlanejadoEntrada } from '../domain/eventos-planejados';
import type { LinhaCaixaHotmart, TotaisCaixaHotmart } from '../domain/caixa-hotmart';
import type { DivergenciaTaxa } from '../domain/taxa-hotmart';
import type { Informado, InformadoEntrada, ResultadoLinhaImportacao } from '../domain/recebimentos-informados';
import type { DecisaoOferta, OfertaFila } from '../domain/fila-ofertas';
import type { LinhaMensalContratoHF, PagamentoContratoHF, SyncStatusContratosHF } from '../domain/contratos-hf';

/** A RPC não existe no banco (PostgREST PGRST202: migration ainda não aplicada). A tela esconde o recurso. */
export class RecursoAusenteError extends Error {
  constructor(msg = 'Recurso ainda não disponível no banco.') { super(msg); this.name = 'RecursoAusenteError'; }
}

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
  /** fn_fin_caixa_hotmart(p_inicio, p_fim) — Caixa Hotmart por dia de aprovação (z68); janela ≤ 400 dias. */
  loadCaixaHotmart(inicio: string, fim: string): Promise<LinhaCaixaHotmart[]>;
  /** fn_fin_caixa_hotmart_totais(p_inicio, p_fim) — 1 linha com os totais do período (z68). */
  loadCaixaHotmartTotais(inicio: string, fim: string): Promise<TotaisCaixaHotmart>;
  /** fn_fin_taxa_auditoria(p_inicio, p_fim) — taxa Hotmart real × acordo por produto ('a_vista') e por nº de parcelas
   *  ('parcelado', 1..12), linhas cruas (z70); janela ≤ 400 dias. Quem separa e normaliza é domain/taxa-hotmart. */
  loadTaxaAuditoria(inicio: string, fim: string): Promise<Record<string, unknown>[]>;
  /** fn_fin_taxa_divergencias(p_inicio, p_fim) — vendas à vista com |real − esperado| > R$ 10, até 500 (z70). */
  loadTaxaDivergencias(inicio: string, fim: string): Promise<DivergenciaTaxa[]>;
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
  /** fn_fin_escritorio_funil — Sessão → Croqui → HF por evento do escritório + 3 baldes (z92). */
  loadEscritorioFunil(): Promise<LinhaFunilEscritorio[]>;
  /** fn_fin_escritorio_funil_pessoas — pessoas de uma linha do funil do escritório (id do evento ou -1/-2/-3). */
  loadEscritorioFunilPessoas(eventoId: number): Promise<PessoaFunilEscritorio[]>;

  // ── Contratos Holding Familiar (z93) — leitura gp_pode_ver_financeiro, escrita gp_pode_operar_financeiro ──
  // Leitura: função ausente no banco (z93 não aplicada) → RecursoAusenteError; outra falha → Error com mensagem.
  /** fn_fin_contratos_hf_mensal(p_de, p_ate) — grade contrato × mês; null = padrão do banco (5 meses atrás a 6 à frente). */
  loadContratosHfMensal(de: string | null, ate: string | null): Promise<LinhaMensalContratoHF[]>;
  /** fn_fin_contratos_hf_pagamentos(p_so_fila) — true = só a fila de conferência. */
  loadContratosHfPagamentos(soFila: boolean): Promise<PagamentoContratoHF[]>;
  /** fn_fin_contratos_hf_sync_status() — sempre 1 linha; tudo nulo = o cron nunca rodou. */
  loadContratosHfSyncStatus(): Promise<SyncStatusContratosHF>;
  /** fn_fin_contrato_hf_salvar(p) — id obrigatório; chave ausente = mantém. P0001 = mensagem do banco. */
  salvarContratoHf(p: Record<string, string | null>): Promise<Resultado>;
  /** fn_fin_parcela_etapa_concluir(p_id, p_data) — data nula desfaz. */
  concluirEtapaParcela(id: string, data: string | null): Promise<Resultado>;
  /** fn_fin_contrato_hf_desfundir(p_id, p_motivo) — devolve o id da ficha reaberta (ou null). */
  desfundirContratoHf(id: string, motivo: string): Promise<Resultado>;
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
  /** fn_fin_board_assinatura_hm — mensalidade do HM antigo (3507214) por pessoa_chave; 1 chamada por abertura do board (z52). */
  loadBoardAssinaturaHM(): Promise<AssinaturaHMBoard[]>;
  /** fn_fin_assinatura_hm_sem_card — pagou mensalidade do HM antigo e não tem card (z52). */
  loadAssinaturaHMSemCard(): Promise<AssinaturaHMSemCard[]>;
  /** fn_fin_prorata_hm — pro rata do HM por pessoa (regra do João, 27/09). */
  loadProrataHM(valorPrograma?: number): Promise<ProrataHM[]>;
  /** fn_fin_acelera_para_hm — quem comprou o Acelera e o que comprou de HM depois. */
  loadAceleraParaHM(): Promise<AceleraParaHM[]>;
  /** fn_fin_prorata_diagnostico — uma pessoa, com cada pagamento e o motivo; vencimento/valor = simulação. */
  loadProrataDiagnostico(email: string, vencimento?: string | null, valorPrograma?: number): Promise<ProrataDiagnostico | null>;

  // ── Contas a Receber (blocos 1, 2 e 5; contrato v2 z66) ──────────────────
  /** fn_fin_receber_semanal(p_corte, p_ate, p_cenario) — UMA chamada por cenário; numeric já convertido.
   *  'base' não envia p_cenario (funciona com o banco antes e depois da z66). */
  loadContasReceber(cenario?: CenarioReceber): Promise<LinhaReceber[]>;

  // ── Premissas do Contas a Receber e feriados bancários (z66; feriados z60/z64) ──
  /** fn_fin_premissas_receber_listar() — uma linha por vigência. */
  loadPremissasReceber(): Promise<VigenciaPremissa[]>;
  /** fn_fin_premissa_receber_salvar(p_chave, p_valor, p_vigente_de, p_cenario) — só acrescenta vigência; valor na unidade do banco. */
  salvarPremissaReceber(chave: string, valor: number, vigenteDe: string, cenario: CenarioReceber): Promise<Resultado>;
  /** fn_fin_feriados_listar(). */
  loadFeriados(): Promise<FeriadoBancario[]>;
  /** fn_fin_feriado_salvar(p_dia, p_nome, p_ativo) — cria ou liga/desliga; nada se apaga. */
  salvarFeriado(dia: string, nome: string, ativo: boolean): Promise<Resultado>;
  /** fn_fin_receber_sugestoes(p_cenario) (z67) — sugestão medida da venda nova semanal e da reserva, com o valor em uso. */
  loadSugestoesReceber(cenario?: CenarioReceber): Promise<SugestaoPremissa[]>;

  // ── Eventos planejados (bloco 4, z67) ────────────────────────────────────
  /** fn_fin_eventos_planejados_listar() — todos (ativo, encerrado, arquivado), com a curva da referência. */
  loadEventosPlanejados(): Promise<EventoPlanejado[]>;
  /** fn_fin_evento_planejado_salvar(p) — sem id cria; com id altera (todas as chaves). Guarda gp_pode_operar_financeiro. */
  salvarEventoPlanejado(p: EventoPlanejadoEntrada): Promise<Resultado & { id?: number }>;
  /** fn_fin_evento_planejado_arquivar(p_id, p_motivo) — motivo 3 a 500. Nada se apaga. */
  arquivarEventoPlanejado(id: number, motivo: string): Promise<Resultado>;

  // ── Fotografia semanal da previsão (z69) — leitura, guarda gp_pode_ver_financeiro ──
  /** fn_fin_receber_fotos_listar() — fotos disponíveis, mais nova primeiro. */
  loadFotosReceber(): Promise<FotoReceber[]>;
  /** fn_fin_receber_mudancas(p_foto_a, p_foto_b) — por (bloco, grupo), com os motivos. 22023 = foto não existe. */
  loadMudancasReceber(fotoA: string, fotoB: string): Promise<MudancaReceber[]>;
  /** fn_fin_receber_previsto_realizado(p_semanas 1..52) — linhas 'semana' e 'perda'. */
  loadPrevistoRealizado(semanas?: number): Promise<LinhaPrevistoRealizado[]>;

  // ── Recebimentos informados (bloco 5, 20260928z63; contrato Holding Familiar = bloco 7, z73) ──────────
  // Escrita: guarda gp_pode_operar_financeiro() no banco; erro de validação = mensagem em português do SQL.
  // z73: tipo contrato_holding_familiar com parcela_n, parcela_de e contrato_assinado (chaves só nesse tipo).
  /** fn_fin_informados_listar() — identificadores MASCARADOS sem gp_pode_ver_cpf(). parcela_n, parcela_de,
   *  contrato_assinado no fim (nulos fora do contrato e no banco sem a z73). */
  loadInformados(): Promise<Informado[]>;
  /** fn_fin_informado_salvar(p) — sem id cria; com id atualiza. Chave ausente = não mexe. */
  salvarInformado(p: InformadoEntrada): Promise<Resultado & { id?: string }>;
  /** fn_fin_informado_baixar(p_id, p_data) — data nula desfaz a baixa manual. */
  baixarInformado(id: string, data: string | null): Promise<Resultado>;
  /** fn_fin_informado_arquivar(p_id, p_motivo) — motivo ≥ 3 caracteres. Nada se apaga. */
  arquivarInformado(id: string, motivo: string): Promise<Resultado>;
  /** fn_fin_informados_importar(p_linhas, p_simular) — simular = prévia sem gravar; gravar = tudo ou nada. */
  importarInformados(linhas: InformadoEntrada[], simular: boolean): Promise<ImportacaoInformados>;

  // ── Ofertas a confirmar (z82) — guarda gp_pode_ver_financeiro nas duas (quem vê o Financeiro decide) ──
  /** fn_fin_fila_ofertas() — pendentes, até 50, mais vendas primeiro. Erro vira exceção com mensagem simples. */
  carregarFilaOfertas(): Promise<OfertaFila[]>;
  /** fn_fin_decidir_oferta(p_oferta, p_evento_id | p_criar | p_rejeitar) — exatamente uma ação. `recarregar` = a oferta
   *  já foi decidida/ligada por outra pessoa ou saiu da fila: a lista na tela está velha. */
  decidirOferta(codigo: string, decisao: DecisaoOferta): Promise<Resultado & { recarregar?: boolean }>;

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

/** Devolvido por importarInformados: falha de transporte/permissão em `msg`; resultado por linha em `linhas`. */
export interface ImportacaoInformados {
  ok: boolean;
  msg?: string;
  linhas: ResultadoLinhaImportacao[];
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
