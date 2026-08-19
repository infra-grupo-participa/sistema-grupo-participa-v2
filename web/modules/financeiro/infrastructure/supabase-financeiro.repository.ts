'use client';

// Adapter Supabase do FinanceiroRepository — ÚNICO lugar do módulo que chama
// .rpc(). Todo schema `cs` (sistema de ativação) fica fora do PostgREST; o
// guard de permissão vive dentro de cada função no Postgres (gp_pode_ver_financeiro/
// gp_pode_operar_financeiro), não em RLS de tabela.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type {
  Acordo, CardBoard, Cobranca, CompraHistorico, DiaFaturamento, Lancamento, Meta, Oferta,
  OfertaOrfa, ReguaPasso, SaudeCheck, TurmaFin,
} from '../domain/types';
import type { FinanceiroRepository, Resultado } from '../application/ports';

function erroPara(msg: string): Resultado {
  return { ok: false, msg };
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

  async loadFaturamento(turma: string | null): Promise<DiaFaturamento[]> {
    const { data, error } = await this.db().rpc('fn_fin_faturamento_diario', { p_turma: turma });
    logQueryError('loadFaturamento', error);
    if (error) throw new Error('Não foi possível carregar o faturamento diário.');
    return (data as DiaFaturamento[]) ?? [];
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
}
