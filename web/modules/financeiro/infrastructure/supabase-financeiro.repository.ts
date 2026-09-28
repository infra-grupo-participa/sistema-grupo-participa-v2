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
import type { FinanceiroRepository, RelatorioEmitido, RelatorioVerificado, Resultado } from '../application/ports';
import { VALOR_PROGRAMA_HM } from '../domain/prorata-hm';
import type {
  AceleraParaHM, BoardHotmart, DiaHotmart, DivergenciaHotmart, FamiliaHotmart, FunilHotmart, IdentidadeRevisao, OfertaHotmart, PessoaHotmart, ProrataDiagnostico, ProrataHM, SyncHotmart, TransacaoHotmart,
} from '../domain/hotmart';
import type { FaturamentoAcao, LinhaContratado } from '../domain/faturamento-analise';
import type { LinhaServicoDiamante } from '../domain/servico-diamante';
import type { CompradorFunil, Funil } from '../domain/funis';
import type { PassoTrajetoria } from '../domain/trajetoria';
import type { OfertaSemCatalogo, PagouSemCard } from '../domain/programa-sem-card';
import {
  normalizarAssinaturaBoard, normalizarAssinaturaSemCard, type AssinaturaHMBoard, type AssinaturaHMSemCard,
} from '../domain/assinatura-hm';
import { normalizarLinhaReceber, type LinhaReceber } from '../domain/contas-receber';

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

  // Contas a Receber — p_corte/p_ate nulos: o banco decide o corte (última venda) e o horizonte.
  async loadContasReceber(): Promise<LinhaReceber[]> {
    const linhas = await this.rpcLista<Record<string, unknown>>('fn_fin_contas_receber', { p_corte: null, p_ate: null },
      'Não foi possível carregar as contas a receber.');
    return linhas.map(normalizarLinhaReceber);
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
