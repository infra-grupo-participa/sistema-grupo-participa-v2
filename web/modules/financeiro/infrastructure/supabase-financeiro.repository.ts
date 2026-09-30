'use client';

// Adapter Supabase do FinanceiroRepository — ÚNICO lugar do módulo que chama
// .rpc(). Todo schema `cs` (sistema de ativação) fica fora do PostgREST; o
// guard de permissão vive dentro de cada função no Postgres (gp_pode_ver_financeiro/
// gp_pode_operar_financeiro), não em RLS de tabela.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type {
  Acordo, CardBoard, Cobranca, CompraHistorico, InteracaoAtivacao, Lancamento, Meta,
  Oferta, OfertaOrfa, ReguaPasso, SaudeCheck, TurmaFin,
} from '../domain/types';
import type {
  FinanceiroRepository, ImportacaoInformados, RelatorioEmitido, RelatorioVerificado, Resultado,
} from '../application/ports';
import { RecursoAusenteError } from '../application/ports';
import {
  normalizarLinhaMensal, normalizarPagamento, normalizarSyncStatus, type LinhaMensalContratoHF, type PagamentoContratoHF,
  type SyncStatusContratosHF,
} from '../domain/contratos-hf';
import { VALOR_PROGRAMA_HM } from '../domain/prorata-hm';
import type {
  AceleraParaHM, BoardHotmart, DiaHotmart, DivergenciaHotmart, FamiliaHotmart, FunilHotmart, IdentidadeRevisao, OfertaHotmart, PessoaHotmart, ProrataDiagnostico, ProrataHM, SyncHotmart, TransacaoHotmart,
} from '../domain/hotmart';
import type { FaturamentoAcao, LinhaContratado } from '../domain/faturamento-analise';
import type { LinhaServicoDiamante } from '../domain/servico-diamante';
import type { CompradorFunil, Funil } from '../domain/funis';
import type { LinhaFunilEscritorio, PessoaFunilEscritorio } from '../domain/escritorio-funil';
import type { PassoTrajetoria } from '../domain/trajetoria';
import type { OfertaSemCatalogo, PagouSemCard } from '../domain/programa-sem-card';
import {
  normalizarAssinaturaBoard, normalizarAssinaturaSemCard, type AssinaturaHMBoard, type AssinaturaHMSemCard,
} from '../domain/assinatura-hm';
import { normalizarLinhaReceber, type CenarioReceber, type LinhaReceber } from '../domain/contas-receber';
import {
  normalizarLinhaCaixa, normalizarTotaisCaixa, type LinhaCaixaHotmart, type TotaisCaixaHotmart,
} from '../domain/caixa-hotmart';
import { normalizarDivergencia, type DivergenciaTaxa } from '../domain/taxa-hotmart';
import {
  normalizarFeriado, normalizarSugestao, normalizarVigencia, type FeriadoBancario, type SugestaoPremissa, type VigenciaPremissa,
} from '../domain/premissas-receber';
import {
  normalizarInformado, normalizarResultadoImportacao, type Informado, type InformadoEntrada,
} from '../domain/recebimentos-informados';
import { normalizarEventoPlanejado, type EventoPlanejado, type EventoPlanejadoEntrada } from '../domain/eventos-planejados';
import { argsDecidirOferta, normalizarOfertaFila, type DecisaoOferta, type OfertaFila } from '../domain/fila-ofertas';
import {
  normalizarFoto, normalizarMudanca, normalizarPrevistoRealizado,
  type FotoReceber, type LinhaPrevistoRealizado, type MudancaReceber,
} from '../domain/visao-receber';

function erroPara(msg: string): Resultado {
  return { ok: false, msg };
}

/**
 * Mensagem legível para as RPCs fn_fin_relatorio_* (20260928z50): 42501 = sem
 * permissão (gp_pode_ver_financeiro/dono do protocolo), 22023 = validação de
 * entrada (tipo/nível/recorte/linhas/totais/sha/páginas fora do formato).
 */
function msgErroRelatorio(error: { code?: string; message?: string } | null, acao: string): string {
  if (error?.code === '42501') return 'Sem permissão para emitir relatórios do Financeiro.';
  if (error?.code === '22023') return error.message ?? 'Dados do relatório inválidos.';
  return `Não foi possível ${acao} o protocolo do relatório (erro de rede).`;
}

/**
 * Erro das escritas de recebimentos informados. 42501 = sem gp_pode_operar_financeiro(); P0001 (raise exception) =
 * validação do SQL, mensagem já em português para a tela. O log leva só o CÓDIGO: a mensagem do SQL pode repetir
 * cliente/identificador colado, e o texto colado nunca vai para o console.
 */
function erroInformado(nome: string, error: { code?: string; message?: string }, acao: string): string {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para operar o financeiro.';
  if (error.code === 'P0001' && error.message) return error.message;
  return `Não foi possível ${acao} (erro de rede ou recurso ainda não disponível).`;
}

/** Função inexistente no banco: PostgREST devolve PGRST202 (fora do schema cache); 42883 = undefined_function. */
export const rpcAusente = (error: { code?: string } | null) => error?.code === 'PGRST202' || error?.code === '42883';

/**
 * Erro das LEITURAS dos contratos HF (z93). Função ausente vira RecursoAusenteError (a tela esconde a sub-aba);
 * 42501 = sem gp_pode_ver_financeiro(); 22023 = período recusado (mensagem do SQL). O log leva só o código.
 */
export function erroLeituraContratosHf(nome: string, error: { code?: string; message?: string }, acao: string): Error {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (rpcAusente(error)) return new RecursoAusenteError();
  if (error.code === '42501') return new Error('Sem permissão para ver o financeiro.');
  if (error.code === '22023' && error.message) return new Error(error.message);
  return new Error(`Não foi possível ${acao} (erro de rede).`);
}

/**
 * Erro das escritas de premissa e feriado (z66/z64). 42501 = sem gp_pode_operar_financeiro(); 22023 = faixa, inteiro,
 * cenário ou data (mensagem do SQL, em português, com o rótulo da premissa); 23505 = mesma premissa na mesma data;
 * PGRST202 = a função ainda não existe no banco (migration não aplicada). O log leva só o código.
 */
export function erroPremissa(nome: string, error: { code?: string; message?: string }, acao: string): string {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para operar o financeiro.';
  if ((error.code === '22023' || error.code === '23505') && error.message) return error.message;
  if (error.code === '23505') return 'Já existe vigência nesta data. Grave com outra data.';
  if (error.code === 'PGRST202') return `Não foi possível ${acao}: recurso ainda não disponível no banco.`;
  return `Não foi possível ${acao} (erro de rede ou recurso ainda não disponível).`;
}

/**
 * Erro das LEITURAS do Contas a Receber (premissas, feriados, sugestões, eventos e as fotos da z69). A guarda de leitura
 * é gp_pode_ver_financeiro(): 42501 aqui é "ver", nunca "operar" (a escrita usa erroPremissa). 22023 = parâmetro
 * recusado, mensagem do SQL em português; PGRST202 = a função ainda não existe no banco. O log leva só o código.
 */
export function erroLeituraReceber(nome: string, error: { code?: string; message?: string }, acao: string): string {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para ver o financeiro.';
  if (error.code === '22023' && error.message) return error.message;
  if (error.code === 'PGRST202') return `Não foi possível ${acao}: recurso ainda não disponível no banco.`;
  return `Não foi possível ${acao} (erro de rede ou recurso ainda não disponível).`;
}

/**
 * Erro das leituras do Caixa Hotmart (z68). 42501 = sem gp_pode_ver_financeiro(); 22023 = período recusado (datas,
 * fim antes do início, janela > 400 dias), mensagem do SQL já em português. O log leva só o código.
 */
export function erroCaixaHotmart(nome: string, error: { code?: string; message?: string }): string {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para ver o financeiro.';
  if (error.code === '22023' && error.message) return error.message;
  if (error.code === 'PGRST202') return 'Caixa Hotmart ainda não disponível no banco.';
  return 'Não foi possível carregar o caixa da Hotmart (erro de rede).';
}

/** Erro das leituras da auditoria da taxa Hotmart (z70): mesmos códigos do Caixa (42501, 22023). */
export function erroTaxaHotmart(nome: string, error: { code?: string; message?: string }): string {
  logQueryError(nome, { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para ver o financeiro.';
  if (error.code === '22023' && error.message) return error.message;
  if (error.code === 'PGRST202') return 'Auditoria da taxa Hotmart ainda não disponível no banco.';
  return 'Não foi possível carregar a auditoria da taxa Hotmart (erro de rede).';
}

/**
 * Erro de fn_fin_decidir_oferta (z82). 42501 = sem gp_pode_ver_financeiro(); 55000 = outra pessoa já decidiu; P0002 =
 * saiu da fila ou o evento escolhido não existe; 22023/23505 = validação ou "já existe / já ligada" com mensagem do SQL
 * em português. O log leva só o código.
 */
export function erroDecidirOferta(error: { code?: string; message?: string }): string {
  logQueryError('fn_fin_decidir_oferta', { message: `código ${error.code ?? 'desconhecido'}` });
  if (error.code === '42501') return 'Sem permissão para decidir as ofertas do financeiro.';
  if (error.code === '55000') return 'Outra pessoa já decidiu esta oferta. A lista foi atualizada.';
  if ((error.code === '22023' || error.code === '23505' || error.code === 'P0002') && error.message) return error.message;
  if (error.code === 'PGRST202') return 'Não foi possível decidir a oferta: recurso ainda não disponível no banco.';
  return 'Não foi possível gravar a decisão (erro de rede). Tente de novo.';
}

export class SupabaseFinanceiroRepository implements FinanceiroRepository {
  private db() {
    return createBrowserSupabase();
  }

  async loadBoard(turma: string | null, produto: string | null): Promise<CardBoard[]> {
    const { data, error } = await this.db().rpc('fn_fin_board', { p_turma: turma, p_produto: produto });
    logQueryError('loadBoard', error);
    if (error) throw new Error('Não foi possível carregar o board financeiro.');
    return (data as CardBoard[]) ?? [];
  }

  async loadTurmas(): Promise<TurmaFin[]> {
    const { data, error } = await this.db().rpc('fn_fin_turmas');
    logQueryError('loadTurmas', error);
    if (error) throw new Error('Não foi possível carregar as turmas.');
    return (data as TurmaFin[]) ?? [];
  }

  async loadMetas(): Promise<Meta[]> {
    const { data, error } = await this.db().rpc('fn_fin_metas');
    logQueryError('loadMetas', error);
    if (error) throw new Error('Não foi possível carregar as metas.');
    return (data as Meta[]) ?? [];
  }

  async salvarMeta(m: Meta): Promise<Resultado> {
    const { data, error } = await this.db().rpc('fn_fin_meta_salvar', {
      p_turma: m.turma,
      p_meta_arrecadacao: m.meta_arrecadacao,
      p_meta_cobertura_pct: m.meta_cobertura_pct,
      p_prazo_quitacao_dias: m.prazo_quitacao_dias,
      p_data_fechamento: m.data_fechamento,
      p_obs: m.obs,
    });
    logQueryError('salvarMeta', error);
    if (error) return erroPara('Não foi possível salvar a meta (erro de rede).');
    const r = data as { ok: boolean; erro?: string } | null;
    if (!r?.ok) return erroPara(r?.erro === 'sem_permissao' ? 'Sem permissão para editar metas.' : 'Não foi possível salvar a meta.');
    return { ok: true, msg: 'Meta salva.' };
  }

  async loadRegua(): Promise<ReguaPasso[]> {
    const { data, error } = await this.db().rpc('fn_fin_regua');
    logQueryError('loadRegua', error);
    if (error) throw new Error('Não foi possível carregar a régua de cobrança.');
    return (data as ReguaPasso[]) ?? [];
  }

  async salvarRegua(passos: ReguaPasso[]): Promise<Resultado> {
    const payload = passos.map((p, i) => ({ ordem: i + 1, offset_dias: p.offset_dias, titulo: p.titulo, canal: p.canal, ativo: p.ativo }));
    const { data, error } = await this.db().rpc('fn_fin_regua_salvar', { p_passos: payload });
    logQueryError('salvarRegua', error);
    if (error) return erroPara('Não foi possível salvar a régua (erro de rede).');
    const r = data as { ok: boolean; erro?: string } | null;
    if (!r?.ok) return erroPara(r?.erro === 'sem_permissao' ? 'Sem permissão para editar a régua.' : 'Não foi possível salvar a régua.');
    return { ok: true, msg: 'Régua salva.' };
  }

  async loadExtrato(compradorId: string): Promise<Lancamento[]> {
    const { data, error } = await this.db().rpc('fn_fin_extrato', { p_comprador_id: compradorId });
    logQueryError('loadExtrato', error);
    if (error) throw new Error('Não foi possível carregar o extrato.');
    return (data as Lancamento[]) ?? [];
  }

  async loadComprasAluno(compradorId: string): Promise<CompraHistorico[]> {
    const { data, error } = await this.db().rpc('fn_fin_compras_aluno', { p_comprador_id: compradorId });
    logQueryError('loadComprasAluno', error);
    if (error) throw new Error('Não foi possível carregar o histórico de compras.');
    return (data as CompraHistorico[]) ?? [];
  }

  async loadCobrancas(contatoHmId: string): Promise<Cobranca[]> {
    const { data, error } = await this.db().rpc('fn_fin_cobrancas', { p_contato_hm_id: contatoHmId });
    logQueryError('loadCobrancas', error);
    if (error) throw new Error('Não foi possível carregar o histórico de cobrança.');
    return (data as Cobranca[]) ?? [];
  }

  async loadHistoricoAtivacao(contatoHmId: string): Promise<InteracaoAtivacao[]> {
    const { data, error } = await this.db().rpc('fn_fin_historico_ativacao', { p_contato_hm_id: contatoHmId });
    logQueryError('loadHistoricoAtivacao', error);
    if (error) throw new Error('Não foi possível carregar o histórico do comercial.');
    return (data as InteracaoAtivacao[]) ?? [];
  }

  async registrarCobranca(contatoHmId: string, canal: string, resultado: string, obs: string | null): Promise<Resultado> {
    const { data, error } = await this.db().rpc('fn_fin_cobranca_registrar', {
      p_contato_hm_id: contatoHmId, p_canal: canal, p_resultado: resultado, p_obs: obs,
    });
    logQueryError('registrarCobranca', error);
    if (error) return erroPara('Não foi possível registrar a cobrança (erro de rede).');
    const r = data as { ok: boolean; erro?: string } | null;
    if (!r?.ok) return erroPara(r?.erro === 'sem_permissao' ? 'Sem permissão para registrar cobrança.' : 'Não foi possível registrar.');
    return { ok: true, msg: 'Cobrança registrada.' };
  }

  async salvarAcordo(contatoHmId: string, a: Acordo): Promise<Resultado> {
    const { data, error } = await this.db().rpc('fn_fin_salvar_acordo', {
      p_contato_hm_id: contatoHmId,
      p_vencimento: a.vencimento,
      p_acordo: a.acordo,
      p_meio: a.meio,
      p_forma: a.forma,
      p_parcelas: a.parcelas,
    });
    logQueryError('salvarAcordo', error);
    if (error) return erroPara('Não foi possível salvar o acordo (erro de rede).');
    const r = data as { ok: boolean; erro?: string } | null;
    if (!r?.ok) {
      return erroPara(r?.erro === 'sem_permissao' ? 'Você não tem permissão para registrar acordos.' : 'Não foi possível salvar o acordo.');
    }
    return { ok: true, msg: 'Acordo registrado.' };
  }

  async loadOfertas(): Promise<Oferta[]> {
    const { data, error } = await this.db().rpc('fn_fin_ofertas');
    logQueryError('loadOfertas', error);
    if (error) throw new Error('Não foi possível carregar as ofertas.');
    return (data as Oferta[]) ?? [];
  }

  /**
   * fn_fin_oferta_salvar pode não existir ainda em produção (ver ports.ts).
   * Se a RPC não existir, o Postgres devolve error (função inexistente) —
   * tratado aqui como falha normal, nunca lançado como exceção não pega.
   */
  async salvarOfertaPapel(codigo: string, papel: string): Promise<Resultado> {
    const { data, error } = await this.db().rpc('fn_fin_oferta_salvar', { p_codigo: codigo, p_papel: papel });
    logQueryError('salvarOfertaPapel', error);
    if (error) return erroPara('Não foi possível salvar o papel da oferta (recurso ainda não disponível ou erro de rede).');
    const r = data as { ok: boolean; erro?: string } | null;
    if (!r?.ok) return erroPara(r?.erro === 'sem_permissao' ? 'Sem permissão para editar ofertas.' : 'Não foi possível salvar.');
    return { ok: true, msg: 'Oferta atualizada.' };
  }

  async loadSaude(): Promise<SaudeCheck[]> {
    const { data, error } = await this.db().rpc('fn_fin_saude');
    logQueryError('loadSaude', error);
    if (error) throw new Error('Não foi possível carregar a saúde do financeiro.');
    return (data as SaudeCheck[]) ?? [];
  }

  async loadOfertasOrfas(): Promise<OfertaOrfa[]> {
    const { data, error } = await this.db().rpc('fn_fin_ofertas_orfas');
    logQueryError('loadOfertasOrfas', error);
    if (error) throw new Error('Não foi possível carregar as ofertas órfãs.');
    return (data as OfertaOrfa[]) ?? [];
  }

  // ── Espelho da Hotmart (fn_fin_hotmart_*, só leitura) ─────────────────────
  private async rpcLista<T>(nome: string, args: Record<string, unknown>, msg: string): Promise<T[]> {
    const { data, error } = await this.db().rpc(nome, args);
    logQueryError(nome, error);
    if (error) throw new Error(msg);
    return (data as T[]) ?? [];
  }

  loadHotmartFaturamento(familia: FamiliaHotmart, inicio: string | null, fim: string | null): Promise<DiaHotmart[]> {
    return this.rpcLista<DiaHotmart>('fn_fin_hotmart_faturamento', { p_familia: familia, p_inicio: inicio, p_fim: fim },
      'Não foi possível carregar o faturamento da Hotmart.');
  }

  loadHotmartFunis(familia: FamiliaHotmart, inicio: string | null, fim: string | null): Promise<FunilHotmart[]> {
    return this.rpcLista<FunilHotmart>('fn_fin_hotmart_funis', { p_familia: familia, p_inicio: inicio, p_fim: fim },
      'Não foi possível carregar o faturamento por funil.');
  }

  async loadContratado(familia: FamiliaHotmart): Promise<LinhaContratado[]> {
    const linhas = await this.rpcLista<LinhaContratado>('fn_fin_contratado', { p_familia: familia },
      'Não foi possível carregar o dinheiro já contratado.');
    return linhas.map((l) => ({ ...l, valor: Number(l.valor) || 0, em_risco: Number(l.em_risco) || 0 }));
  }

  async loadFaturamentoPorAcao(familia: FamiliaHotmart): Promise<FaturamentoAcao[]> {
    const linhas = await this.rpcLista<FaturamentoAcao>('fn_fin_faturamento_por_acao', { p_familia: familia },
      'Não foi possível carregar o faturamento por ação.');
    return linhas.map((a) => ({ ...a, bruto: Number(a.bruto) || 0, liquido: Number(a.liquido) || 0 }));
  }

  async loadServicoDiamante(): Promise<LinhaServicoDiamante[]> {
    const linhas = await this.rpcLista<LinhaServicoDiamante>('fn_fin_diamante_servicos', {},
      'Não foi possível carregar os serviços Diamante.');
    const n = (v: unknown) => Number(v ?? 0) || 0;
    return linhas.map((l) => ({
      ...l, total_pago: n(l.total_pago), liquido: n(l.liquido), devendo_valor: n(l.devendo_valor), antigo_valor: n(l.antigo_valor),
      coberto_valor: n(l.coberto_valor), meses: (l.meses ?? {}) as LinhaServicoDiamante['meses'],
      mensalidade: l.mensalidade == null ? null : n(l.mensalidade),
    }));
  }

  async loadFunis(): Promise<Funil[]> {
    const n = (v: unknown) => Number(v ?? 0) || 0;
    const linhas = await this.rpcLista<Funil>('fn_fin_funis', {}, 'Não foi possível carregar os funis.');
    return linhas.map((f) => ({
      ...f, ingressos_bruto: n(f.ingressos_bruto), ingressos_liquido: n(f.ingressos_liquido), oferta_bruto: n(f.oferta_bruto),
      oferta_liquido: n(f.oferta_liquido), bruto: n(f.bruto), liquido: n(f.liquido),
      ref_valor: f.ref_valor == null ? null : n(f.ref_valor), liquido_conferencia: n(f.liquido_conferencia),
    }));
  }

  async loadFunilCompradores(eventoId: number): Promise<CompradorFunil[]> {
    const n = (v: unknown) => Number(v ?? 0) || 0;
    const linhas = await this.rpcLista<CompradorFunil>('fn_fin_funil_compradores', { p_evento_id: eventoId },
      'Não foi possível carregar quem pagou neste funil.');
    return linhas.map((c) => ({ ...c, valor: n(c.valor), liquido: n(c.liquido) }));
  }

  async loadEscritorioFunil(): Promise<LinhaFunilEscritorio[]> {
    const n = (v: unknown) => Number(v ?? 0) || 0;
    const nn = (v: unknown) => (v == null ? null : Number(v));
    const linhas = await this.rpcLista<LinhaFunilEscritorio>('fn_fin_escritorio_funil', {},
      'Não foi possível carregar o funil do escritório.');
    return linhas.map((l) => ({
      ...l, evento_id: n(l.evento_id), sessoes_valor: n(l.sessoes_valor), sessoes_estornos_valor: n(l.sessoes_estornos_valor),
      croqui_valor: n(l.croqui_valor), hf_valor: n(l.hf_valor), croqui_pct: nn(l.croqui_pct), hf_pct: nn(l.hf_pct),
      mediana_dias_sessao_croqui: nn(l.mediana_dias_sessao_croqui), mediana_dias_croqui_hf: nn(l.mediana_dias_croqui_hf),
    }));
  }

  async loadEscritorioFunilPessoas(eventoId: number): Promise<PessoaFunilEscritorio[]> {
    const nn = (v: unknown) => (v == null ? null : Number(v));
    const linhas = await this.rpcLista<PessoaFunilEscritorio>('fn_fin_escritorio_funil_pessoas', { p_evento: eventoId },
      'Não foi possível carregar as pessoas desta linha do funil.');
    return linhas.map((p) => ({
      ...p, sessao_valor: nn(p.sessao_valor), croqui_valor: nn(p.croqui_valor), hf_valor: nn(p.hf_valor),
    }));
  }

  // ── Contratos Holding Familiar (z93) ─────────────────────────────────────
  async loadContratosHfMensal(de: string | null, ate: string | null): Promise<LinhaMensalContratoHF[]> {
    const { data, error } = await this.db().rpc('fn_fin_contratos_hf_mensal', { p_de: de, p_ate: ate });
    if (error) throw erroLeituraContratosHf('fn_fin_contratos_hf_mensal', error, 'carregar os contratos');
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarLinhaMensal);
  }

  async loadContratosHfPagamentos(soFila: boolean): Promise<PagamentoContratoHF[]> {
    const { data, error } = await this.db().rpc('fn_fin_contratos_hf_pagamentos', { p_so_fila: soFila });
    if (error) throw erroLeituraContratosHf('fn_fin_contratos_hf_pagamentos', error, 'carregar a conferência da Hotmart');
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarPagamento);
  }

  async loadContratosHfSyncStatus(): Promise<SyncStatusContratosHF> {
    const { data, error } = await this.db().rpc('fn_fin_contratos_hf_sync_status');
    if (error) throw erroLeituraContratosHf('fn_fin_contratos_hf_sync_status', error, 'ler o status da sincronização');
    return normalizarSyncStatus(data as Record<string, unknown>[] | null);
  }

  async salvarContratoHf(p: Record<string, string | null>): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_contrato_hf_salvar', { p });
    if (error) return erroPara(erroInformado('salvarContratoHf', error, p.arquivar_motivo ? 'arquivar o contrato' : 'salvar o contrato'));
    return { ok: true, msg: p.arquivar_motivo ? 'Contrato arquivado.' : 'Contrato atualizado.' };
  }

  async concluirEtapaParcela(id: string, data: string | null): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_parcela_etapa_concluir', { p_id: id, p_data: data });
    if (error) return erroPara(erroInformado('concluirEtapaParcela', error, data ? 'concluir a etapa' : 'reabrir a etapa'));
    return { ok: true, msg: data ? 'Etapa concluída: a parcela entrou na previsão.' : 'Etapa reaberta.' };
  }

  async desfundirContratoHf(id: string, motivo: string): Promise<Resultado> {
    const { data, error } = await this.db().rpc('fn_fin_contrato_hf_desfundir', { p_id: id, p_motivo: motivo });
    if (error) return erroPara(erroInformado('desfundirContratoHf', error, 'desfazer a fusão'));
    return { ok: true, msg: data ? 'Fusão desfeita: a ficha criada pelo sinal foi reaberta.' : 'Fusão desfeita.' };
  }

  async loadOfertasSemCatalogo(): Promise<OfertaSemCatalogo[]> {
    const linhas = await this.rpcLista<OfertaSemCatalogo>('fn_fin_ofertas_sem_catalogo', {},
      'Não foi possível carregar as ofertas fora do catálogo.');
    return linhas.map((o) => ({ ...o, valor: Number(o.valor ?? 0) || 0 }));
  }

  async loadProgramaSemCard(familia: 'HM' | 'AURUM'): Promise<PagouSemCard[]> {
    const linhas = await this.rpcLista<PagouSemCard>('fn_fin_programa_sem_card', { p_familia: familia },
      'Não foi possível carregar quem pagou o Programa sem card.');
    return linhas.map((p) => ({ ...p, valor: Number(p.valor ?? 0) || 0 }));
  }

  async loadTrajetoria(email: string): Promise<PassoTrajetoria[]> {
    const linhas = await this.rpcLista<PassoTrajetoria>('fn_fin_trajetoria', { p_email: email },
      'Não foi possível carregar a trajetória desta pessoa.');
    return linhas.map((p) => ({ ...p, valor: Number(p.valor ?? 0) || 0 }));
  }

  loadHotmartPessoas(familia: FamiliaHotmart): Promise<PessoaHotmart[]> {
    return this.rpcLista<PessoaHotmart>('fn_fin_hotmart_pessoas', { p_familia: familia },
      'Não foi possível carregar a situação das pessoas.');
  }

  loadHotmartExtrato(email: string): Promise<TransacaoHotmart[]> {
    return this.rpcLista<TransacaoHotmart>('fn_fin_hotmart_extrato', { p_email: email },
      'Não foi possível carregar o histórico da Hotmart.');
  }

  loadHotmartOfertas(familia: FamiliaHotmart): Promise<OfertaHotmart[]> {
    return this.rpcLista<OfertaHotmart>('fn_fin_hotmart_ofertas', { p_familia: familia },
      'Não foi possível carregar as ofertas da Hotmart.');
  }

  loadHotmartConciliacao(familia: FamiliaHotmart): Promise<DivergenciaHotmart[]> {
    return this.rpcLista<DivergenciaHotmart>('fn_fin_hotmart_conciliacao', { p_familia: familia },
      'Não foi possível carregar a conciliação.');
  }

  async loadHotmartSync(): Promise<SyncHotmart | null> {
    const lista = await this.rpcLista<SyncHotmart>('fn_fin_hotmart_sync_status', {},
      'Não foi possível conferir a sincronização com a Hotmart.');
    return lista[0] ?? null;
  }

  loadHotmartIdentidade(): Promise<IdentidadeRevisao[]> {
    return this.rpcLista<IdentidadeRevisao>('fn_fin_hotmart_identidade', {},
      'Não foi possível carregar a revisão de identidade.');
  }

  loadBoardHotmart(): Promise<BoardHotmart[]> {
    return this.rpcLista<BoardHotmart>('fn_fin_board_hotmart', {},
      'Não foi possível carregar os dados da Hotmart do board.');
  }

  async loadBoardAssinaturaHM(): Promise<AssinaturaHMBoard[]> {
    const linhas = await this.rpcLista<AssinaturaHMBoard>('fn_fin_board_assinatura_hm', {},
      'Não foi possível carregar a mensalidade do HM antigo.');
    return linhas.map(normalizarAssinaturaBoard);
  }

  async loadAssinaturaHMSemCard(): Promise<AssinaturaHMSemCard[]> {
    const linhas = await this.rpcLista<AssinaturaHMSemCard>('fn_fin_assinatura_hm_sem_card', {},
      'Não foi possível carregar quem paga a mensalidade do HM antigo sem card.');
    return linhas.map(normalizarAssinaturaSemCard);
  }

  loadProrataHM(valorPrograma = VALOR_PROGRAMA_HM): Promise<ProrataHM[]> {
    return this.rpcLista<ProrataHM>('fn_fin_prorata_hm', { p_valor_programa: valorPrograma },
      'Não foi possível calcular o pro rata do HM.');
  }

  loadAceleraParaHM(): Promise<AceleraParaHM[]> {
    return this.rpcLista<AceleraParaHM>('fn_fin_acelera_para_hm', {},
      'Não foi possível carregar quem subiu do Acelera para o HM.');
  }

  async loadProrataDiagnostico(email: string, vencimento: string | null = null, valorPrograma = VALOR_PROGRAMA_HM): Promise<ProrataDiagnostico | null> {
    const { data, error } = await this.db().rpc('fn_fin_prorata_diagnostico',
      { p_email: email, p_vencimento: vencimento, p_valor_programa: valorPrograma });
    logQueryError('loadProrataDiagnostico', error);
    if (error) throw new Error('Não foi possível montar o diagnóstico do pro rata.');
    return (data as ProrataDiagnostico | null) ?? null;
  }

  // Contas a Receber — p_corte/p_ate nulos: o banco decide o corte (agora) e o horizonte. Cenário 'base' NÃO envia
  // p_cenario: durante o deploy o banco pode estar na z63 (sem o parâmetro) e o PostgREST recusaria a chamada; na z66
  // o padrão do parâmetro já é 'base'. Os outros cenários exigem a z66 (antes dela: erro de carga, com "tentar de novo").
  async loadContasReceber(cenario: CenarioReceber = 'base'): Promise<LinhaReceber[]> {
    const args: Record<string, unknown> = { p_corte: null, p_ate: null };
    if (cenario !== 'base') args.p_cenario = cenario;
    const linhas = await this.rpcLista<Record<string, unknown>>('fn_fin_receber_semanal', args,
      'Não foi possível carregar as contas a receber.');
    return linhas.map(normalizarLinhaReceber);
  }

  // ── Caixa Hotmart (z68) ──────────────────────────────────────────────────
  async loadCaixaHotmart(inicio: string, fim: string): Promise<LinhaCaixaHotmart[]> {
    const { data, error } = await this.db().rpc('fn_fin_caixa_hotmart', { p_inicio: inicio, p_fim: fim });
    if (error) throw new Error(erroCaixaHotmart('fn_fin_caixa_hotmart', error));
    return ((data as Record<string, unknown>[]) ?? []).map(normalizarLinhaCaixa);
  }

  async loadCaixaHotmartTotais(inicio: string, fim: string): Promise<TotaisCaixaHotmart> {
    const { data, error } = await this.db().rpc('fn_fin_caixa_hotmart_totais', { p_inicio: inicio, p_fim: fim });
    if (error) throw new Error(erroCaixaHotmart('fn_fin_caixa_hotmart_totais', error));
    return normalizarTotaisCaixa(((data as Record<string, unknown>[]) ?? [])[0]);
  }

  // ── Taxa Hotmart (z70) ───────────────────────────────────────────────────
  async loadTaxaAuditoria(inicio: string, fim: string): Promise<Record<string, unknown>[]> {
    const { data, error } = await this.db().rpc('fn_fin_taxa_auditoria', { p_inicio: inicio, p_fim: fim });
    if (error) throw new Error(erroTaxaHotmart('fn_fin_taxa_auditoria', error));
    return (data as Record<string, unknown>[]) ?? [];
  }

  async loadTaxaDivergencias(inicio: string, fim: string): Promise<DivergenciaTaxa[]> {
    const { data, error } = await this.db().rpc('fn_fin_taxa_divergencias', { p_inicio: inicio, p_fim: fim });
    if (error) throw new Error(erroTaxaHotmart('fn_fin_taxa_divergencias', error));
    return ((data as Record<string, unknown>[]) ?? []).map(normalizarDivergencia);
  }

  // ── Premissas do Contas a Receber e feriados bancários (z66) ────────────
  async loadPremissasReceber(): Promise<VigenciaPremissa[]> {
    const { data, error } = await this.db().rpc('fn_fin_premissas_receber_listar', {});
    if (error) throw new Error(erroLeituraReceber('fn_fin_premissas_receber_listar', error, 'carregar as premissas'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarVigencia);
  }

  async salvarPremissaReceber(chave: string, valor: number, vigenteDe: string, cenario: CenarioReceber): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_premissa_receber_salvar',
      { p_chave: chave, p_valor: valor, p_vigente_de: vigenteDe, p_cenario: cenario });
    if (error) return erroPara(erroPremissa('salvarPremissaReceber', error, 'gravar a premissa'));
    return { ok: true, msg: 'Vigência gravada.' };
  }

  async loadFeriados(): Promise<FeriadoBancario[]> {
    const { data, error } = await this.db().rpc('fn_fin_feriados_listar', {});
    if (error) throw new Error(erroLeituraReceber('fn_fin_feriados_listar', error, 'carregar os feriados'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarFeriado);
  }

  async salvarFeriado(dia: string, nome: string, ativo: boolean): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_feriado_salvar', { p_dia: dia, p_nome: nome, p_ativo: ativo });
    if (error) return erroPara(erroPremissa('salvarFeriado', error, 'gravar o feriado'));
    return { ok: true, msg: ativo ? 'Feriado gravado.' : 'Feriado desligado.' };
  }

  // ── Sugestões medidas e eventos planejados (z67) ─────────────────────────
  // Leitura: erro vira exceção com a mensagem de erroLeituraReceber (só o código vai ao log; nada do conteúdo).
  async loadSugestoesReceber(cenario: CenarioReceber = 'base'): Promise<SugestaoPremissa[]> {
    const { data, error } = await this.db().rpc('fn_fin_receber_sugestoes', { p_cenario: cenario });
    if (error) throw new Error(erroLeituraReceber('fn_fin_receber_sugestoes', error, 'carregar as sugestões medidas'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarSugestao);
  }

  async loadEventosPlanejados(): Promise<EventoPlanejado[]> {
    const { data, error } = await this.db().rpc('fn_fin_eventos_planejados_listar');
    if (error) throw new Error(erroLeituraReceber('fn_fin_eventos_planejados_listar', error, 'carregar os eventos planejados'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarEventoPlanejado);
  }

  async salvarEventoPlanejado(p: EventoPlanejadoEntrada): Promise<Resultado & { id?: number }> {
    const { data, error } = await this.db().rpc('fn_fin_evento_planejado_salvar', { p });
    if (error) return erroPara(erroPremissa('salvarEventoPlanejado', error, 'gravar o evento planejado'));
    const linha = ((data as Record<string, unknown>[] | null) ?? [])[0];
    return { ok: true, msg: p.id != null ? 'Evento planejado alterado.' : 'Evento planejado criado.', id: linha?.id == null ? undefined : Number(linha.id) };
  }

  async arquivarEventoPlanejado(id: number, motivo: string): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_evento_planejado_arquivar', { p_id: id, p_motivo: motivo });
    if (error) return erroPara(erroPremissa('arquivarEventoPlanejado', error, 'arquivar o evento planejado'));
    return { ok: true, msg: 'Evento planejado arquivado.' };
  }

  // ── Ofertas a confirmar (z82) ───────────────────────────────────────────
  async carregarFilaOfertas(): Promise<OfertaFila[]> {
    const { data, error } = await this.db().rpc('fn_fin_fila_ofertas');
    if (error) throw new Error(erroLeituraReceber('fn_fin_fila_ofertas', error, 'carregar as ofertas a confirmar'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarOfertaFila);
  }

  async decidirOferta(codigo: string, decisao: DecisaoOferta): Promise<Resultado & { recarregar?: boolean }> {
    const { data, error } = await this.db().rpc('fn_fin_decidir_oferta', argsDecidirOferta(codigo, decisao));
    if (error) return { ...erroPara(erroDecidirOferta(error)), recarregar: ['P0002', '55000', '23505'].includes(error.code ?? '') };
    const r = (data ?? {}) as Record<string, unknown>;
    if (r.status === 'rejeitada') return { ok: true, msg: 'Marcada como venda fora de evento.' };
    return { ok: true, msg: r.evento_criado === true ? 'Evento criado e vendas ligadas a ele.' : 'Vendas ligadas ao evento.' };
  }

  // ── Fotografia semanal da previsão (z69) ─────────────────────────────────
  async loadFotosReceber(): Promise<FotoReceber[]> {
    const { data, error } = await this.db().rpc('fn_fin_receber_fotos_listar');
    if (error) throw new Error(erroLeituraReceber('fn_fin_receber_fotos_listar', error, 'carregar as fotos da previsão'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarFoto);
  }

  async loadMudancasReceber(fotoA: string, fotoB: string): Promise<MudancaReceber[]> {
    const { data, error } = await this.db().rpc('fn_fin_receber_mudancas', { p_foto_a: fotoA, p_foto_b: fotoB });
    if (error) throw new Error(erroLeituraReceber('fn_fin_receber_mudancas', error, 'carregar o que mudou'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarMudanca);
  }

  async loadPrevistoRealizado(semanas = 8): Promise<LinhaPrevistoRealizado[]> {
    const { data, error } = await this.db().rpc('fn_fin_receber_previsto_realizado', { p_semanas: semanas });
    if (error) throw new Error(erroLeituraReceber('fn_fin_receber_previsto_realizado', error, 'carregar o previsto × realizado'));
    return ((data as Record<string, unknown>[] | null) ?? []).map(normalizarPrevistoRealizado);
  }

  // ── Recebimentos informados (bloco 5, 20260928z63) ───────────────────────
  async loadInformados(): Promise<Informado[]> {
    const linhas = await this.rpcLista<Record<string, unknown>>('fn_fin_informados_listar', {},
      'Não foi possível carregar os recebimentos informados.');
    return linhas.map(normalizarInformado);
  }

  async salvarInformado(p: InformadoEntrada): Promise<Resultado & { id?: string }> {
    const { data, error } = await this.db().rpc('fn_fin_informado_salvar', { p });
    if (error) return erroPara(erroInformado('salvarInformado', error, 'salvar o recebimento informado'));
    return { ok: true, msg: p.id ? 'Recebimento informado atualizado.' : 'Recebimento informado criado.', id: data == null ? undefined : String(data) };
  }

  async baixarInformado(id: string, data: string | null): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_informado_baixar', { p_id: id, p_data: data });
    if (error) return erroPara(erroInformado('baixarInformado', error, data ? 'registrar a baixa' : 'desfazer a baixa'));
    return { ok: true, msg: data ? 'Baixa manual registrada.' : 'Baixa manual desfeita.' };
  }

  async arquivarInformado(id: string, motivo: string): Promise<Resultado> {
    const { error } = await this.db().rpc('fn_fin_informado_arquivar', { p_id: id, p_motivo: motivo });
    if (error) return erroPara(erroInformado('arquivarInformado', error, 'arquivar'));
    return { ok: true, msg: 'Recebimento informado arquivado.' };
  }

  async importarInformados(linhas: InformadoEntrada[], simular: boolean): Promise<ImportacaoInformados> {
    const { data, error } = await this.db().rpc('fn_fin_informados_importar', { p_linhas: linhas, p_simular: simular });
    if (error) return { ok: false, msg: erroInformado('importarInformados', error, simular ? 'conferir as linhas' : 'gravar as linhas'), linhas: [] };
    const res = ((data as Record<string, unknown>[] | null) ?? []).map(normalizarResultadoImportacao);
    return { ok: res.every((r) => r.ok), linhas: res };
  }

  // ── Protocolo dos relatórios em PDF (fn_fin_relatorio_*, 20260928z50) ───
  async emitirRelatorio(
    tipo: string, nivel: string, recorte: Record<string, unknown>, linhas: number, totais: Record<string, unknown>,
  ): Promise<RelatorioEmitido> {
    const { data, error } = await this.db().rpc('fn_fin_relatorio_emitir', {
      p_tipo: tipo, p_nivel: nivel, p_recorte: recorte, p_linhas: linhas, p_totais: totais,
    });
    logQueryError('emitirRelatorio', error);
    if (error) throw new Error(msgErroRelatorio(error, 'emitir'));
    const linha = (data as RelatorioEmitido[] | null)?.[0];
    if (!linha?.protocolo) throw new Error('A emissão não devolveu protocolo.');
    return linha;
  }

  async selarRelatorio(protocolo: string, sha256: string, paginas: number): Promise<boolean> {
    const { data, error } = await this.db().rpc('fn_fin_relatorio_selar', {
      p_protocolo: protocolo, p_sha256: sha256, p_paginas: paginas,
    });
    logQueryError('selarRelatorio', error);
    if (error) throw new Error(msgErroRelatorio(error, 'selar'));
    return data === true;
  }

  async verificarRelatorio(protocolo: string): Promise<RelatorioVerificado | null> {
    const { data, error } = await this.db().rpc('fn_fin_relatorio_verificar', { p_protocolo: protocolo });
    logQueryError('verificarRelatorio', error);
    if (error) throw new Error(msgErroRelatorio(error, 'conferir'));
    return (data as RelatorioVerificado[] | null)?.[0] ?? null;
  }
}
